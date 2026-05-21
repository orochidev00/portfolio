--!strict
-- el_thor.luau · LocalScript
-- vertical lightning strike on a mouse-targeted ground point.
-- Q to cast. fully client-side, no RemoteEvents for VFX (server handles damage).
-- assets cloned from ReplicatedStorage.Assets.VFX — originals untouched.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Lighting          = game:GetService("Lighting")

local player = Players.LocalPlayer
local mouse  = player:GetMouse()

-- asset templates (cloned per cast, never mutated)
local Assets          = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("VFX")
local CloudTemplate   = Assets:WaitForChild("Cloud")
local FloorTemplate   = Assets:WaitForChild("Floor")
local HandVFXTemplate = Assets:WaitForChild("HandVFX")
local BeamTemplate    = Assets:WaitForChild("Beam") -- Model: Inside + Outside cylinders + Highlight

-- server remote for damage + ragdoll
local ImpactRemote = ReplicatedStorage:WaitForChild("ElThorImpact")

-- tunables
local PLACEHOLDER_ANIM_ID = "rbxassetid://0" -- swap when real anim is ready
local CAST_WINDUP         = 0.15 -- stand-in for "lower hand" anim marker
local CLOUD_SPAWN_HEIGHT  = 200
local CLOUD_FADE_TIME     = 0.05
local FLOOR_DROP_TIME     = 0.05
local FLOOR_RETURN_TIME   = 0.30 -- floor flies back into cloud after impact
local BEAM_GROW_TIME      = 0.60 -- width expansion after impact
local BEAM_WIDTH_START    = 30
local BEAM_WIDTH_END      = 100
local BEAM_OUTSIDE_OFFSET = 5    -- Outside is +N studs wider for the halo
local IMPACT_FRAME_TIME   = 0.04 -- per ColorCorrection frame
local BEAM_FLASH_DURATION = 0.40 -- transparency pulse so particles can read through
local BEAM_FLASH_PEAK     = 0.9

-- sound ids
local CHARGE_SOUND_ID     = "rbxassetid://116644751820648"
local CHARGE_SOUND_VOLUME = 2
local STRIKE_SOUND_ID     = "rbxassetid://115206336107437"
local STRIKE_SOUND_VOLUME = 3

local RING_COUNT          = 2
local RING_SPACING        = 0.05 -- temporal gap between ring spawns
local RING_BASE_RADIUS    = 40
local RING_RADIUS_STEP    = 15   -- ring N+1 sits 15 studs further out
local BURST_PER_EMITTER   = 50
local CLEANUP_HOLD        = 1.5
local CLOUD_FADE_OUT_TIME = 0.30 -- runs in parallel with FLOOR_RETURN_TIME
local ROCK_EMERGE_TIME    = 0.18
local ROCK_SINK_TIME      = 0.40
local ROCK_SINK_GAP       = 0.05

-- damage / ragdoll constants live in the server script

local isCasting = false


-- helpers

-- exclude every player character + every NPC model (Humanoid root). that way
-- raycasts only hit terrain/scenery, never bodies.
local function getCharacterExcludes(): { Instance }
	local excludes: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(excludes, p.Character)
		end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") then
			if not table.find(excludes, child) then
				table.insert(excludes, child)
			end
		end
	end
	return excludes
end

local function raycastFromMouse(excludes: { Instance }): RaycastResult?
	local unitRay = mouse.UnitRay
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = excludes
	return workspace:Raycast(unitRay.Origin, unitRay.Direction * 5000, params)
end

local function forEachEmitter(attachment: Attachment?, fn: (ParticleEmitter) -> ())
	if not attachment then return end
	for _, child in ipairs(attachment:GetChildren()) do
		if child:IsA("ParticleEmitter") then
			fn(child)
		end
	end
end

-- play a positional Sound on a part. auto-destroyed on Ended.
local function playSoundOn(part: Instance, soundId: string, volume: number): Sound
	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume  = volume
	sound.Parent  = part
	sound:Play()
	sound.Ended:Connect(function()
		sound:Destroy()
	end)
	return sound
end

-- play a positional Sound at a world point via a tiny invisible emitter part.
-- 15s failsafe in case Ended never fires.
local function playSoundAt(position: Vector3, soundId: string, volume: number): Sound
	local emitter = Instance.new("Part")
	emitter.Anchored     = true
	emitter.CanCollide   = false
	emitter.Transparency = 1
	emitter.Size         = Vector3.new(0.1, 0.1, 0.1)
	emitter.Position     = position
	emitter.Parent       = workspace

	local sound = Instance.new("Sound")
	sound.SoundId = soundId
	sound.Volume  = volume
	sound.Parent  = emitter
	sound:Play()
	sound.Ended:Connect(function()
		emitter:Destroy()
	end)
	task.delay(15, function()
		if emitter.Parent then
			emitter:Destroy()
		end
	end)
	return sound
end


-- HandVFX (continuous flow while channeling)

local function attachHandVFX(character: Model): BasePart?
	local leftHand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if not leftHand or not leftHand:IsA("BasePart") then return nil end

	local handVFX = HandVFXTemplate:Clone()
	handVFX.Anchored   = false
	handVFX.CanCollide = false
	handVFX.Massless   = true
	handVFX.CFrame     = leftHand.CFrame
	handVFX.Parent     = workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0  = handVFX
	weld.Part1  = leftHand
	weld.Parent = handVFX

	-- continuous emission, no :Emit() burst
	forEachEmitter(handVFX:FindFirstChildOfClass("Attachment"), function(em)
		em.Enabled = true
	end)

	return handVFX
end

-- disable emitters one by one (cleanup owns destruction)
local function disableHandVFXEmitters(handVFX: BasePart?)
	if not handVFX then return end
	forEachEmitter(handVFX:FindFirstChildOfClass("Attachment"), function(em)
		em.Enabled = false
	end)
end


-- Cloud + Floor + Beam cylinders.
-- cloud sits above the impact point. floor starts inside the cloud and drops.
-- Beam (Inside + Outside cylinders) starts at the cloud with Size.X collapsed
-- and extends downward to the ground. emitters are pre-parented inside Floor's
-- attachment with Enabled = false so we control when they burst.
local function createCloud(targetPos: Vector3): (BasePart, BasePart, Attachment?)
	local cloud = CloudTemplate:Clone()
	cloud.Anchored   = true
	cloud.CanCollide = false
	cloud.CFrame     = CFrame.new(targetPos + Vector3.new(0, CLOUD_SPAWN_HEIGHT, 0))

	-- fade in
	local originalTransparency = cloud.Transparency
	cloud.Transparency = 1
	cloud.Parent = workspace
	TweenService:Create(
		cloud,
		TweenInfo.new(CLOUD_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = originalTransparency }
	):Play()

	local floor = FloorTemplate:Clone()
	floor.Anchored     = true
	floor.CanCollide   = false
	floor.Transparency = 1
	floor.CFrame       = cloud.CFrame
	floor.Parent       = workspace

	local floorAttachment = floor:FindFirstChildOfClass("Attachment")
	forEachEmitter(floorAttachment, function(em)
		em.Enabled = false
	end)

	return cloud, floor, floorAttachment
end

-- Outside cylinder is slightly wider so it reads as a halo around Inside
local function widthForCylinder(partName: string, baseWidth: number): number
	if partName == "Outside" then
		return baseWidth + BEAM_OUTSIDE_OFFSET
	end
	return baseWidth
end

-- preserve the asset's (0, 90, 90) rotation — that orientation makes local X
-- point along world +Y, so Size.X grows vertically. Face decals on Outside
-- stay correctly mapped this way.
local function createBeamCylinders(cloudPos: Vector3): Model
	local beamModel = BeamTemplate:Clone()
	for _, part in ipairs(beamModel:GetChildren()) do
		if part:IsA("BasePart") then
			local w = widthForCylinder(part.Name, BEAM_WIDTH_START)
			part.Anchored   = true
			part.CanCollide = false
			part.CFrame     = CFrame.new(cloudPos) * part.CFrame.Rotation
			part.Size       = Vector3.new(0.05, w, w) -- X=length, Y/Z=diameter
		end
	end
	beamModel.Parent = workspace
	return beamModel
end


-- impact sequence

local function dropFloor(floor: BasePart, targetPos: Vector3): Tween
	local info = TweenInfo.new(FLOOR_DROP_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.In)
	local tween = TweenService:Create(floor, info, { CFrame = CFrame.new(targetPos) })
	tween:Play()
	return tween
end

-- extend Size.X (vertical, post-rotation) from ~0 to cloud→ground distance.
-- CFrame slides to the midpoint so the TOP stays anchored at the cloud and the
-- bottom grows down to the floor.
local function extendBeamCylinders(beamModel: Model, cloudPos: Vector3, targetPos: Vector3)
	local distance = cloudPos.Y - targetPos.Y
	local midPos   = Vector3.new(cloudPos.X, cloudPos.Y - distance / 2, cloudPos.Z)
	local info     = TweenInfo.new(FLOOR_DROP_TIME, Enum.EasingStyle.Linear, Enum.EasingDirection.In)
	for _, part in ipairs(beamModel:GetChildren()) do
		if part:IsA("BasePart") then
			local newSize   = Vector3.new(distance, part.Size.Y, part.Size.Z)
			local newCFrame = CFrame.new(midPos) * part.CFrame.Rotation
			TweenService:Create(part, info, {
				Size   = newSize,
				CFrame = newCFrame,
			}):Play()
		end
	end
end

-- post-impact width grow. Outside keeps its halo offset.
local function growBeamCylinders(beamModel: Model)
	local info = TweenInfo.new(BEAM_GROW_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in ipairs(beamModel:GetChildren()) do
		if part:IsA("BasePart") then
			local w = widthForCylinder(part.Name, BEAM_WIDTH_END)
			TweenService:Create(part, info, {
				Size = Vector3.new(part.Size.X, w, w),
			}):Play()
		end
	end
end

local function returnFloorToCloud(floor: BasePart, cloud: BasePart)
	local info = TweenInfo.new(FLOOR_RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(floor, info, { CFrame = cloud.CFrame }):Play()
end

-- pulse beam transparency on impact so explosion particles aren't occluded.
-- up to BEAM_FLASH_PEAK over half the duration, back down to each part's
-- original transparency over the other half. non-blocking.
local function flashBeamTransparency(beamModel: Model)
	task.spawn(function()
		local half     = BEAM_FLASH_DURATION / 2
		local upInfo   = TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		local downInfo = TweenInfo.new(half, Enum.EasingStyle.Quad, Enum.EasingDirection.In)

		local originals: { [BasePart]: number } = {}
		for _, part in ipairs(beamModel:GetChildren()) do
			if part:IsA("BasePart") then
				originals[part] = part.Transparency
				TweenService:Create(part, upInfo, { Transparency = BEAM_FLASH_PEAK }):Play()
			end
		end

		task.wait(half)

		for part, orig in pairs(originals) do
			TweenService:Create(part, downInfo, { Transparency = orig }):Play()
		end
	end)
end

-- mirror of extend. cylinders collapse upward into the cloud.
local function retractBeamCylinders(beamModel: Model, cloudPos: Vector3)
	local info = TweenInfo.new(FLOOR_RETURN_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	for _, part in ipairs(beamModel:GetChildren()) do
		if part:IsA("BasePart") then
			local newCFrame = CFrame.new(cloudPos) * part.CFrame.Rotation
			TweenService:Create(part, info, {
				Size   = Vector3.new(0.05, part.Size.Y, part.Size.Z),
				CFrame = newCFrame,
			}):Play()
		end
	end
end

-- 4-frame B&W impact pulse:
--   F1 blinding overexposure -> F2 black -> F3 harsh contrast -> F4 fade
-- saturation = -1 across all 4 frames for monochrome punch.
local function runImpactFrames()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = -1
	cc.TintColor  = Color3.new(1, 1, 1)
	cc.Parent     = Lighting

	cc.Brightness, cc.Contrast =  1.0,  0.0; task.wait(IMPACT_FRAME_TIME) -- white-out
	cc.Brightness, cc.Contrast = -1.0,  0.0; task.wait(IMPACT_FRAME_TIME) -- black-out
	cc.Brightness, cc.Contrast =  0.0,  2.5; task.wait(IMPACT_FRAME_TIME) -- jagged contrast
	cc.Brightness, cc.Contrast =  0.3,  0.5; task.wait(IMPACT_FRAME_TIME) -- soft residue

	cc:Destroy()
end


-- impact bursts + debris rings

local function emitExplosion(floorAttachment: Attachment?)
	forEachEmitter(floorAttachment, function(em)
		-- per-emitter override via attribute, otherwise the default count
		local count = em:GetAttribute("EmitCount") or BURST_PER_EMITTER
		em:Emit(count)
	end)
end

-- one ring of irregular rocks around centerPos. rocks inherit Material/Color
-- from whatever surface was struck and start submerged, tweening up to emerge.
-- sizeMultiplier scales rock size per ring (inner rings get chunkier debris).
local function spawnDebrisRing(
	centerPos: Vector3,
	radius: number,
	hitInstance: BasePart,
	sizeMultiplier: number,
	raycastExcludes: { Instance }
)
	local material = hitInstance.Material
	local color    = hitInstance.Color

	-- each rock is a slab. its long axis (Z) follows the ring's tangent so the
	-- rocks trace the circle as a continuous band.
	local tangentLengthAvg = 7   * sizeMultiplier -- Size.Z along the ring
	local radialWidthAvg   = 3.5 * sizeMultiplier -- Size.X across the band
	local slabHeightAvg    = 1.5 * sizeMultiplier -- Size.Y vertical

	-- rockCount = circumference / avg tangent. ceil() makes adjacent rocks
	-- touch/overlap a hair = continuous outline.
	local rockCount = math.ceil((2 * math.pi * radius) / tangentLengthAvg)
	local rocks = {}

	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = raycastExcludes

	for i = 1, rockCount do
		local angle    = (i / rockCount) * math.pi * 2 + (math.random() - 0.5) * 0.05
		local jitterR  = radius + (math.random() - 0.5) * 0.5
		local horizontalOffset = Vector3.new(math.cos(angle) * jitterR, 0, math.sin(angle) * jitterR)
		local horizontalPos    = centerPos + horizontalOffset

		-- straight-down ray to find the ACTUAL surface at (x, z).
		-- if it misses (ledge / thin air) skip this rock entirely.
		local rayStart  = Vector3.new(horizontalPos.X, centerPos.Y + 100, horizontalPos.Z)
		local rayResult = workspace:Raycast(rayStart, Vector3.new(0, -400, 0), groundParams)
		if not rayResult then
			continue
		end
		local pos = Vector3.new(horizontalPos.X, rayResult.Position.Y, horizontalPos.Z)

		-- per-rock jitter (0.7-1.3x of avg) so they don't look stamped
		local tan = tangentLengthAvg * (0.7 + math.random() * 0.6)
		local rad = radialWidthAvg   * (0.7 + math.random() * 0.6)
		local h   = slabHeightAvg    * (0.7 + math.random() * 0.6)

		local rock = Instance.new("Part")
		rock.Size          = Vector3.new(rad, h, tan)
		rock.Material      = material
		rock.Color         = color
		rock.Anchored      = true
		rock.CanCollide    = false
		rock.TopSurface    = Enum.SurfaceType.Smooth
		rock.BottomSurface = Enum.SurfaceType.Smooth

		-- orient so Z follows the ring tangent at this angle
		local tangentDir = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		local baseCFrame = CFrame.lookAt(pos, pos + tangentDir)
		-- per-axis tilt so rocks don't look molded
		local tilt = CFrame.Angles(
			(math.random() - 0.5) * 0.6,
			(math.random() - 0.5) * 0.4,
			(math.random() - 0.5) * 0.6
		)
		local restCFrame = baseCFrame * tilt

		-- burial depth accounts for tilted slab length, otherwise a rotated
		-- long edge could poke above ground at extreme angles.
		local burialDepth = tan / 2 + h
		local startCFrame = restCFrame - Vector3.new(0, burialDepth, 0)
		local endCFrame   = restCFrame + Vector3.new(0, h * 0.3, 0)

		rock.CFrame = startCFrame
		rock.Parent = workspace

		TweenService:Create(
			rock,
			TweenInfo.new(ROCK_EMERGE_TIME, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ CFrame = endCFrame }
		):Play()

		table.insert(rocks, { part = rock, startCFrame = startCFrame, endCFrame = endCFrame })
	end

	return rocks
end


-- final cleanup. the only destruction point in the skill.
-- holds the post-explosion frame, sinks rings inner -> outer, then destroys.
local function cleanup(
	handVFX: BasePart?,
	cloud: BasePart,
	floor: BasePart,
	debrisRings: { any }
)
	task.wait(CLEANUP_HOLD)

	for _, ringRocks in ipairs(debrisRings) do
		for _, data in ipairs(ringRocks) do
			TweenService:Create(
				data.part,
				TweenInfo.new(ROCK_SINK_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = data.startCFrame }
			):Play()
		end
		task.wait(ROCK_SINK_GAP)
	end

	task.wait(ROCK_SINK_TIME)

	if handVFX then handVFX:Destroy() end
	cloud:Destroy()
	floor:Destroy()
	for _, ringRocks in ipairs(debrisRings) do
		for _, data in ipairs(ringRocks) do
			data.part:Destroy()
		end
	end
end


-- main orchestration

local function castElThor()
	if isCasting then return end
	local character = player.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	isCasting = true

	-- placeholder anim — swap when real one is in
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = PLACEHOLDER_ANIM_ID
	local track = animator:LoadAnimation(anim)
	pcall(function() track:Play() end)

	-- HandVFX channels continuously through windup
	local handVFX = attachHandVFX(character)

	-- charge SFX from the hand
	local chargeSound: Sound? = nil
	if handVFX then
		chargeSound = playSoundOn(handVFX, CHARGE_SOUND_ID, CHARGE_SOUND_VOLUME)
	end

	task.wait(CAST_WINDUP)

	-- snapshot the exclude list once. used for the mouse target AND every
	-- per-rock ground raycast in this cast.
	local raycastExcludes = getCharacterExcludes()

	-- snapshot the impact point. mouse drift after this is ignored.
	local raycastResult = raycastFromMouse(raycastExcludes)
	if not raycastResult then
		if handVFX then handVFX:Destroy() end
		isCasting = false
		return
	end
	local targetPos   = raycastResult.Position
	local hitInstance = raycastResult.Instance

	-- cloud + floor + beam cylinders ready, emitters wired but silent
	local cloud, floor, floorAttachment = createCloud(targetPos)
	local beamModel = createBeamCylinders(cloud.Position)

	-- channeling done
	disableHandVFXEmitters(handVFX)

	-- floor drops + beam cylinders extend in parallel. both land together.
	local dropTween = dropFloor(floor, targetPos)
	extendBeamCylinders(beamModel, cloud.Position, targetPos)
	dropTween.Completed:Wait()

	-- impact: burst, server damage, B&W frames, transparency pulse, width grow
	emitExplosion(floorAttachment)
	ImpactRemote:FireServer(targetPos)
	if chargeSound then chargeSound:Stop() end
	playSoundAt(targetPos, STRIKE_SOUND_ID, STRIKE_SOUND_VOLUME)
	task.spawn(runImpactFrames)
	flashBeamTransparency(beamModel)
	local beamStartClock = os.clock()
	growBeamCylinders(beamModel)

	-- concentric debris rings. inner rings = bigger chunks.
	local debrisRings = {}
	for i = 1, RING_COUNT do
		local radius  = RING_BASE_RADIUS + (i - 1) * RING_RADIUS_STEP
		local sizeMul = 2 - (i - 1) * (1 / math.max(1, RING_COUNT - 1)) -- 2.0 -> 1.0
		table.insert(debrisRings, spawnDebrisRing(targetPos, radius, hitInstance, sizeMul, raycastExcludes))
		task.wait(RING_SPACING)
	end

	-- wait for beams to reach full width before retracting (otherwise the
	-- collapse hides the moment they finally look thick).
	local elapsed   = os.clock() - beamStartClock
	local remaining = BEAM_GROW_TIME - elapsed
	if remaining > 0 then task.wait(remaining) end

	-- collapse phase: floor returns, beams retract, cloud fades — all in parallel
	returnFloorToCloud(floor, cloud)
	retractBeamCylinders(beamModel, cloud.Position)
	TweenService:Create(
		cloud,
		TweenInfo.new(CLOUD_FADE_OUT_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Transparency = 1 }
	):Play()

	-- beam destroy lines up with the retract tween
	task.delay(FLOOR_RETURN_TIME, function()
		beamModel:Destroy()
	end)

	-- everything else (hand, cloud, floor, debris) goes here
	cleanup(handVFX, cloud, floor, debrisRings)

	isCasting = false
end


-- input bind: Q to cast
UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.Q then
		castElThor()
	end
end)
