local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local mouse = player:GetMouse()

local vfx = ReplicatedStorage:WaitForChild("Assets"):WaitForChild("VFX")
local cloudTemplate = vfx:WaitForChild("Cloud")
local floorTemplate = vfx:WaitForChild("Floor")
local handTemplate = vfx:WaitForChild("HandVFX")
local beamTemplate = vfx:WaitForChild("Beam")
local impactRemote = ReplicatedStorage:WaitForChild("ElThorImpact")

local ANIM_ID = "rbxassetid://0"
local CHARGE_SOUND = "rbxassetid://116644751820648"
local STRIKE_SOUND = "rbxassetid://115206336107437"

local WINDUP = 0.15
local CLOUD_HEIGHT = 200
local CLOUD_FADE_IN = 0.05
local CLOUD_FADE_OUT = 0.3
local DROP_TIME = 0.05
local RETURN_TIME = 0.3
local GROW_TIME = 0.6
local WIDTH_START = 30
local WIDTH_END = 100
local HALO = 5
local FRAME_TIME = 0.04
local FLASH_TIME = 0.4
local FLASH_PEAK = 0.9

local RINGS = 2
local RING_GAP = 0.05
local RING_RADIUS = 40
local RING_STEP = 15
local BURST = 50
local HOLD = 1.5
local EMERGE_TIME = 0.18
local SINK_TIME = 0.4
local SINK_GAP = 0.05

local IMPACT_FRAMES = { { 1, 0 }, { -1, 0 }, { 0, 2.5 }, { 0.3, 0.5 } }

local casting = false

local function tween(instance, time, goal, style, direction)
	local info = TweenInfo.new(time, style or Enum.EasingStyle.Quad, direction or Enum.EasingDirection.Out)
	local t = TweenService:Create(instance, info, goal)
	t:Play()
	return t
end

local function emitters(part)
	local list = {}
	local attachment = part:FindFirstChildOfClass("Attachment")
	if attachment then
		for _, child in ipairs(attachment:GetChildren()) do
			if child:IsA("ParticleEmitter") then
				table.insert(list, child)
			end
		end
	end
	return list
end

local function bodies()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, child in ipairs(workspace:GetChildren()) do
		if child:IsA("Model") and child:FindFirstChildOfClass("Humanoid") and not table.find(list, child) then
			table.insert(list, child)
		end
	end
	return list
end

local function playSound(parent, id, volume)
	local sound = Instance.new("Sound")
	sound.SoundId = id
	sound.Volume = volume
	sound.Parent = parent
	sound:Play()
	return sound
end

local function soundAt(position, id, volume)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Position = position
	anchor.Parent = workspace
	playSound(anchor, id, volume).Ended:Connect(function()
		anchor:Destroy()
	end)
	Debris:AddItem(anchor, 15)
end

local function attachHand(character)
	local hand = character:FindFirstChild("LeftHand") or character:FindFirstChild("Left Arm")
	if not (hand and hand:IsA("BasePart")) then
		return nil
	end

	local fx = handTemplate:Clone()
	fx.Anchored = false
	fx.CanCollide = false
	fx.Massless = true
	fx.CFrame = hand.CFrame
	fx.Parent = workspace

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = fx
	weld.Part1 = hand
	weld.Parent = fx

	for _, emitter in ipairs(emitters(fx)) do
		emitter.Enabled = true
	end
	return fx
end

local function spawnCloud(target)
	local cloud = cloudTemplate:Clone()
	local opacity = cloud.Transparency
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CFrame = CFrame.new(target + Vector3.new(0, CLOUD_HEIGHT, 0))
	cloud.Transparency = 1
	cloud.Parent = workspace
	tween(cloud, CLOUD_FADE_IN, { Transparency = opacity })

	local floor = floorTemplate:Clone()
	floor.Anchored = true
	floor.CanCollide = false
	floor.Transparency = 1
	floor.CFrame = cloud.CFrame
	floor.Parent = workspace
	for _, emitter in ipairs(emitters(floor)) do
		emitter.Enabled = false
	end

	return cloud, floor
end

local function width(part, base)
	if part.Name == "Outside" then
		return base + HALO
	end
	return base
end

local function spawnBeam(origin)
	local beam = beamTemplate:Clone()
	local parts = {}
	for _, part in ipairs(beam:GetChildren()) do
		if part:IsA("BasePart") then
			local w = width(part, WIDTH_START)
			part.Anchored = true
			part.CanCollide = false
			part.CFrame = CFrame.new(origin) * part.CFrame.Rotation
			part.Size = Vector3.new(0.05, w, w)
			table.insert(parts, part)
		end
	end
	beam.Parent = workspace
	return beam, parts
end

local function stretch(parts, top, bottom)
	local length = top.Y - bottom.Y
	local middle = Vector3.new(top.X, top.Y - length / 2, top.Z)
	for _, part in ipairs(parts) do
		tween(part, DROP_TIME, {
			Size = Vector3.new(length, part.Size.Y, part.Size.Z),
			CFrame = CFrame.new(middle) * part.CFrame.Rotation,
		}, Enum.EasingStyle.Linear, Enum.EasingDirection.In)
	end
end

local function retract(parts, top)
	for _, part in ipairs(parts) do
		tween(part, RETURN_TIME, {
			Size = Vector3.new(0.05, part.Size.Y, part.Size.Z),
			CFrame = CFrame.new(top) * part.CFrame.Rotation,
		})
	end
end

local function flash(parts)
	local half = FLASH_TIME / 2
	local original = {}
	for _, part in ipairs(parts) do
		original[part] = part.Transparency
		tween(part, half, { Transparency = FLASH_PEAK })
	end
	task.wait(half)
	for part, transparency in pairs(original) do
		tween(part, half, { Transparency = transparency }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	end
end

local function impactFrames()
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = -1
	cc.TintColor = Color3.new(1, 1, 1)
	cc.Parent = Lighting

	for _, frame in ipairs(IMPACT_FRAMES) do
		cc.Brightness, cc.Contrast = frame[1], frame[2]
		task.wait(FRAME_TIME)
	end
	cc:Destroy()
end

local function jitter()
	return 0.7 + math.random() * 0.6
end

local function spawnRock(center, angle, radius, surface, params, length, depth, height)
	local r = radius + (math.random() - 0.5) * 0.5
	local x, z = center.X + math.cos(angle) * r, center.Z + math.sin(angle) * r

	local ground = workspace:Raycast(Vector3.new(x, center.Y + 100, z), Vector3.new(0, -400, 0), params)
	if not ground then
		return nil
	end

	local position = Vector3.new(x, ground.Position.Y, z)
	local l, d, h = length * jitter(), depth * jitter(), height * jitter()

	local rock = Instance.new("Part")
	rock.Size = Vector3.new(d, h, l)
	rock.Material = surface.Material
	rock.Color = surface.Color
	rock.Anchored = true
	rock.CanCollide = false
	rock.TopSurface = Enum.SurfaceType.Smooth
	rock.BottomSurface = Enum.SurfaceType.Smooth

	local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
	local tilt = CFrame.Angles((math.random() - 0.5) * 0.6, (math.random() - 0.5) * 0.4, (math.random() - 0.5) * 0.6)
	local rest = CFrame.lookAt(position, position + tangent) * tilt
	local buried = rest - Vector3.new(0, l / 2 + h, 0)

	rock.CFrame = buried
	rock.Parent = workspace
	tween(rock, EMERGE_TIME, { CFrame = rest + Vector3.new(0, h * 0.3, 0) }, Enum.EasingStyle.Back)

	return { part = rock, buried = buried }
end

local function spawnRing(center, radius, surface, scale, params)
	local length, depth, height = 7 * scale, 3.5 * scale, 1.5 * scale
	local count = math.ceil(2 * math.pi * radius / length)
	local rocks = {}

	for i = 1, count do
		local angle = i / count * math.pi * 2 + (math.random() - 0.5) * 0.05
		local rock = spawnRock(center, angle, radius, surface, params, length, depth, height)
		if rock then
			table.insert(rocks, rock)
		end
	end

	return rocks
end

local function cleanup(hand, cloud, floor, rings)
	task.wait(HOLD)

	for _, ring in ipairs(rings) do
		for _, rock in ipairs(ring) do
			tween(rock.part, SINK_TIME, { CFrame = rock.buried }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		task.wait(SINK_GAP)
	end
	task.wait(SINK_TIME)

	if hand then
		hand:Destroy()
	end
	cloud:Destroy()
	floor:Destroy()
	for _, ring in ipairs(rings) do
		for _, rock in ipairs(ring) do
			rock.part:Destroy()
		end
	end
end

local function cast()
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if casting or not humanoid then
		return
	end
	casting = true

	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	local animation = Instance.new("Animation")
	animation.AnimationId = ANIM_ID
	local track = animator:LoadAnimation(animation)
	pcall(track.Play, track)

	local hand = attachHand(character)
	local charge
	if hand then
		charge = playSound(hand, CHARGE_SOUND, 2)
		charge.Ended:Connect(function()
			charge:Destroy()
		end)
	end

	task.wait(WINDUP)

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = bodies()

	local ray = mouse.UnitRay
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 5000, params)
	if not hit then
		if hand then
			hand:Destroy()
		end
		casting = false
		return
	end

	local target = hit.Position
	local cloud, floor = spawnCloud(target)
	local top = cloud.Position
	local beam, parts = spawnBeam(top)

	if hand then
		for _, emitter in ipairs(emitters(hand)) do
			emitter.Enabled = false
		end
	end

	stretch(parts, top, target)
	tween(floor, DROP_TIME, { CFrame = CFrame.new(target) }, Enum.EasingStyle.Linear, Enum.EasingDirection.In).Completed:Wait()

	for _, emitter in ipairs(emitters(floor)) do
		emitter:Emit(emitter:GetAttribute("EmitCount") or BURST)
	end
	impactRemote:FireServer(target)
	if charge then
		charge:Stop()
	end
	soundAt(target, STRIKE_SOUND, 3)
	task.spawn(impactFrames)
	task.spawn(flash, parts)

	local grown = os.clock() + GROW_TIME
	for _, part in ipairs(parts) do
		local w = width(part, WIDTH_END)
		tween(part, GROW_TIME, { Size = Vector3.new(part.Size.X, w, w) })
	end

	local rings = {}
	for i = 1, RINGS do
		local scale = 2 - (i - 1) / math.max(1, RINGS - 1)
		table.insert(rings, spawnRing(target, RING_RADIUS + (i - 1) * RING_STEP, hit.Instance, scale, params))
		task.wait(RING_GAP)
	end

	local remaining = grown - os.clock()
	if remaining > 0 then
		task.wait(remaining)
	end

	tween(floor, RETURN_TIME, { CFrame = cloud.CFrame })
	retract(parts, top)
	tween(cloud, CLOUD_FADE_OUT, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	task.delay(RETURN_TIME, function()
		beam:Destroy()
	end)

	cleanup(hand, cloud, floor, rings)
	casting = false
end

UserInputService.InputBegan:Connect(function(input, processed)
	if not processed and input.KeyCode == Enum.KeyCode.Q then
		cast()
	end
end)
