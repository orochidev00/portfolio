local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Signal = require(ReplicatedStorage.Packages.Signal)

local function remote(name)
	local event = Instance.new("RemoteEvent")
	event.Name = name
	event.Parent = ReplicatedStorage
	return event
end

local jumpscareRemote = remote("JumpscareEvent")
local proximityRemote = remote("MonsterProximity")

local config = {
	walkSpeed = 22,
	sprintSpeed = 28.25,
	stalkSpeed = 25,
	speedJitter = 3,

	fovHalf = 65,
	viewDist = 95,
	peripheralDist = 40,
	hearDist = 80,
	sprintHearDist = 140,
	hearCooldown = 5,
	stareTime = 2,
	chaseMemory = 4,

	scareReach = 4.5,
	minChaseForScare = 1.8,
	idleTime = 2.5,
	lookAroundMax = 5,

	pauseChance = 0.04,
	pauseMin = 1,
	pauseMax = 3,

	toyRadius = 140,
	toySpeed = 60,
	toyMaxTime = 40,
	toyReposMin = 2,
	toyReposMax = 6,
	toyPauseMax = 3,
	toyMinDist = 70,
	toyMaxDist = 110,
	toyLoseDist = 110,
	laughChance = 0.35,

	turnSpeed = 6,
	headSpeed = 8,
	proximityRange = 50,
	minPartSize = 3,
	maxPierces = 25,
	stealthVolume = 0.03,
	avoidDist = 20,
	stuckThreshold = 1.2,
	stuckMaxStreak = 3,

	lungeForce = 50000,
	lungeSpeed = 60,
	lungeTime = 0.3,
	alignTorque = 50000,
	alignResponse = 12,
	fadeTime = 0.5,
}

local SOUNDS = {
	breathing = { id = "rbxassetid://87119489483504", looped = true, volume = 0.3, range = 50 },
	walk = { id = "rbxassetid://138514229177623", looped = true, volume = 0.5, range = 65 },
	sprint = { id = "rbxassetid://139209257128845", looped = true, volume = 0.8, range = 120 },
	lookAround = { id = "rbxassetid://137431264282253", looped = false, volume = 0.6, range = 60 },
	jumpscare = { id = "rbxassetid://137800374619679", looped = false, volume = 10, range = 100 },
	laugh = { id = "rbxassetid://140186441914469", looped = false, volume = 0.7, range = 70 },
}

local LOCOMOTION = { Idle = true, Walk = true, Sprint = true }
local MOVING = { Chase = true, Patrol = true, Return = true, Stalk = true, Toying = true }
local HUNTING = { Chase = true, Stalk = true, Toying = true }

local BEDS = {
	Patrol = { key = "walk", volume = 0.5 },
	Return = { key = "walk", volume = 0.5 },
	Stalk = { key = "walk", volume = config.stealthVolume },
	Chase = { key = "sprint", volume = 0.8 },
	LookAround = { key = "lookAround", volume = 0.6 },
	Jumpscare = { key = "jumpscare", volume = 10 },
}

local BREATH = { Chase = 0.7, LookAround = 0.5, Stalk = 0.12, Toying = 0 }

local OUTER_CONE = math.cos(math.rad(config.fovHalf))
local INNER_CONE = math.cos(math.rad(config.fovHalf / 2))
local STARE_CONE = math.cos(math.rad(30))
local VIEW_CONE = math.cos(math.rad(65))
local YAW_LIMIT = math.rad(70)
local PITCH_LIMIT = math.rad(40)
local UP = Vector3.new(0, 1, 0)
local CLEARANCE = { Vector3.new(3.5, 0, 0), Vector3.new(-3.5, 0, 0), Vector3.new(0, 0, 3.5), Vector3.new(0, 0, -3.5) }
local FADE = TweenInfo.new(config.fadeTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

local function lerpAngle(a, b, t)
	return a + ((b - a + math.pi) % (2 * math.pi) - math.pi) * t
end

local function flatDist(a, b)
	if not a or not b then
		return math.huge
	end
	return Vector2.new(a.X - b.X, a.Z - b.Z).Magnitude
end

local function segmentDist(p, a, b)
	local ab = b - a
	local length = ab.Magnitude
	if length < 0.5 then
		return (p - a).Magnitude
	end
	local dir = ab / length
	return (p - (a + dir * math.clamp((p - a):Dot(dir), 0, length))).Magnitude
end

local function rootOf(player)
	local character = player and player.Character
	return character and character:FindFirstChild("HumanoidRootPart")
end

local function headOf(player)
	local character = player and player.Character
	return character and character:FindFirstChild("Head")
end

local function aliveRoot(player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		return rootOf(player)
	end
	return nil
end

local function closest(check)
	local best, bestDist = nil, math.huge
	for _, player in ipairs(Players:GetPlayers()) do
		local ok, dist = check(player)
		if ok and dist < bestDist then
			best, bestDist = player, dist
		end
	end
	return best
end

local function routeNearPlayers(from, to, radius)
	for _, player in ipairs(Players:GetPlayers()) do
		local root = aliveRoot(player)
		if root and segmentDist(root.Position, from, to) < radius then
			return true
		end
	end
	return false
end

local function patrolSpeed()
	return config.walkSpeed + (math.random() - 0.5) * 2 * config.speedJitter
end

local Monster = {}
Monster.__index = Monster

function Monster.new(origin, waypoints)
	local model = ServerStorage.Entities.Monster:Clone()
	model:PivotTo(origin)
	model.Parent = workspace

	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model.HumanoidRootPart
	local torso = model.Torso
	local neck = torso:FindFirstChild("Neck")

	root:SetNetworkOwner(nil)
	humanoid.WalkSpeed = config.walkSpeed
	humanoid.AutoRotate = true

	local self = setmetatable({
		model = model,
		humanoid = humanoid,
		root = root,
		head = model.Head,
		torso = torso,
		neck = neck,
		neckRest = neck and neck.C0 or CFrame.new(0, 1, 0),
		waypoints = waypoints,
		stateChanged = Signal.new(),

		state = "Idle",
		timer = 0,
		loco = "",

		pathIdx = 1,
		computing = false,

		stuckPos = root.Position,
		stuckClock = 0,
		stuckStreak = 0,

		facing = 0,
		scanAngle = 0,
		scanDir = 1,
		scanClock = 0,
		netClock = 0,

		paused = false,
		pauseTime = 0,
		patrolClock = 0,
		stare = 0,
		hearCooldown = 0,
		blindTime = 0,
		chaseTimer = 0,
		scareFired = false,

		stalkClock = 0,

		toyTimer = 0,
		toyRepos = 0,
		toyTotal = 0,
		toyPausing = false,
		toyPauseClock = 0,
	}, Monster)

	self.animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator", humanoid)
	self.anims = {}
	self.tracks = {}
	for _, name in ipairs({ "Idle", "Walk", "Sprint", "Jumpscare", "LookingAround" }) do
		local anim = ReplicatedStorage.Animations:FindFirstChild(name)
		if anim and anim:IsA("Animation") then
			self.anims[name] = anim
		end
	end

	self.sfx = {}
	for key, spec in pairs(SOUNDS) do
		local sound = Instance.new("Sound")
		sound.Name = key
		sound.SoundId = spec.id
		sound.Looped = spec.looped
		sound.Volume = spec.volume
		sound.RollOffMode = Enum.RollOffMode.InverseTapered
		sound.RollOffMinDistance = 5
		sound.RollOffMaxDistance = spec.range
		sound.Parent = root
		self.sfx[key] = sound
	end
	self.sfx.breathing:Play()

	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = { model }
	self.rayParams.IgnoreWater = true

	self.agent = PathfindingService:CreatePath({
		AgentRadius = 2.5,
		AgentHeight = 7,
		AgentCanJump = false,
		WaypointSpacing = 4,
		Costs = { [Enum.Material.Water] = 100 },
	})

	local attachment = root:FindFirstChild("RootAttachment")
	if not attachment then
		attachment = Instance.new("Attachment")
		attachment.Name = "RootAttachment"
		attachment.Parent = root
	end
	self.attachment = attachment

	local align = Instance.new("AlignOrientation")
	align.Attachment0 = attachment
	align.Mode = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque = config.alignTorque
	align.Responsiveness = config.alignResponse
	align.Enabled = false
	align.Parent = root
	self.align = align

	humanoid.MoveToFinished:Connect(function()
		local node = self.path and self.path[self.pathIdx]
		if node then
			humanoid:MoveTo(node.Position)
		end
	end)

	model:SetAttribute("AIState", "Idle")
	self:setLoco("Idle")
	return self
end

function Monster:track(name)
	local anim = self.anims[name]
	if not anim then
		return nil
	end
	local track = self.tracks[name]
	if not track then
		track = self.animator:LoadAnimation(anim)
		self.tracks[name] = track
	end
	return track
end

function Monster:play(name, fade)
	for other, track in pairs(self.tracks) do
		if other ~= name and not LOCOMOTION[other] and track.IsPlaying then
			track:Stop(0.2)
		end
	end
	local track = self:track(name)
	if track and not track.IsPlaying then
		track:Play(fade or 0.15)
	end
end

function Monster:stop(name)
	local track = self.tracks[name]
	if track and track.IsPlaying then
		track:Stop(0.2)
	end
end

function Monster:stopAll()
	for _, track in pairs(self.tracks) do
		if track.IsPlaying then
			track:Stop(0.2)
		end
	end
	self.loco = ""
end

function Monster:setLoco(name)
	if self.loco == name then
		return
	end
	for other in pairs(LOCOMOTION) do
		if other ~= name then
			self:stop(other)
		end
	end
	local track = self:track(name)
	if track and not track.IsPlaying then
		track:Play(0.2)
	end
	self.loco = name
end

function Monster:syncSounds(state)
	self.sfx.walk:Stop()
	self.sfx.sprint:Stop()
	local bed = BEDS[state]
	if bed then
		local sound = self.sfx[bed.key]
		sound.Volume = bed.volume
		sound:Play()
	end
end

function Monster:tickBreathing(dt)
	local breathing = self.sfx.breathing
	local goal = BREATH[self.state] or 0.3
	breathing.Volume = breathing.Volume + (goal - breathing.Volume) * math.clamp(3 * dt, 0, 1)
end

function Monster:pierce(origin, direction)
	for _ = 1, config.maxPierces do
		local hit = workspace:Raycast(origin, direction, self.rayParams)
		if not hit then
			return nil
		end
		local size = hit.Instance.Size
		local small = size.X < config.minPartSize and size.Y < config.minPartSize and size.Z < config.minPartSize
		if hit.Instance.CanCollide and not small then
			return hit
		end
		local step = hit.Position - origin
		origin = hit.Position + (direction - step).Unit * 0.05
		direction = direction - step
	end
	return nil
end

function Monster:floorAt(point)
	local hit = workspace:Raycast(point + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), self.rayParams)
	return hit and hit.Position
end

function Monster:canSee(player)
	local root = aliveRoot(player)
	if not root then
		return false, math.huge
	end

	local eye = self.head.Position
	local offset = root.Position - eye
	local dist = offset.Magnitude
	if dist > config.viewDist then
		return false, dist
	end

	local dot = self.head.CFrame.LookVector:Dot(offset.Unit)
	if dot < OUTER_CONE or (dot < INNER_CONE and dist > config.peripheralDist) then
		return false, dist
	end

	for _, point in ipairs({ root.Position, root.Position + Vector3.new(0, 1.5, 0) }) do
		local ray = point - eye
		local hit = self:pierce(eye, ray)
		if not hit or (hit.Position - eye).Magnitude >= ray.Magnitude * 0.95 then
			return true, dist
		end
	end
	return false, dist
end

function Monster:canHear(player)
	local character = player.Character
	local root = rootOf(player)
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not root or not humanoid then
		return false, math.huge
	end
	local dist = (root.Position - self.root.Position).Magnitude
	local range = humanoid.WalkSpeed > 20 and config.sprintHearDist or config.hearDist
	return dist <= range, dist
end

function Monster:inSightOf(player, point, cone, tolerance)
	local head = headOf(player)
	if not head then
		return false
	end
	local offset = point - head.Position
	local dist = offset.Magnitude
	if dist < 0.5 or dist > config.viewDist or head.CFrame.LookVector:Dot(offset.Unit) < cone then
		return false
	end
	local hit = self:pierce(head.Position, offset)
	return not hit or (hit.Position - head.Position).Magnitude >= dist * tolerance
end

function Monster:inView(player, point)
	return self:inSightOf(player, point, VIEW_CONE, 0.9)
end

function Monster:sense()
	local seen = closest(function(p)
		return self:canSee(p)
	end)
	local seenRoot = rootOf(seen)
	if seenRoot then
		self.target = seen
		self.lastSeen = seenRoot.Position
		return "Chase"
	end

	if self.hearCooldown > 0 then
		return nil
	end

	local heard = closest(function(p)
		return self:canHear(p)
	end)
	local heardRoot = rootOf(heard)
	if heardRoot then
		self.target = heard
		self.lastSeen = heardRoot.Position
		return "Stalk"
	end
	return nil
end

function Monster:stalkCandidate(look, right, playerPos)
	local angle = math.rad(90 + math.random() * 180)
	local dir = look * math.cos(angle) + right * math.sin(angle)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then
		return nil
	end

	local spot = playerPos + dir.Unit * math.random(18, 30)
	local floor = self:floorAt(spot)
	if not floor then
		return nil
	end
	spot = Vector3.new(spot.X, floor.Y + 3, spot.Z)

	local origin = self.root.Position
	local offset = spot - origin
	if offset.Magnitude > 1 then
		local hit = self:pierce(origin, offset.Unit * math.min(offset.Magnitude, 40))
		if hit and (hit.Position - origin).Magnitude < offset.Magnitude * 0.5 then
			return nil
		end
	end
	return spot
end

function Monster:pickStalkSpot(player)
	local head, root = headOf(player), rootOf(player)
	if not head or not root then
		return nil
	end

	local look = head.CFrame.LookVector
	local right = Vector3.new(-look.Z, 0, look.X).Unit
	local best, bestDot = nil, math.huge

	for _ = 1, 8 do
		local spot = self:stalkCandidate(look, right, root.Position)
		if spot then
			local dot = look:Dot((spot - root.Position).Unit)
			if dot < bestDot then
				best, bestDot = spot, dot
			end
		end
	end
	return best
end

function Monster:routeInView(player, from, to)
	local offset = to - from
	local dist = offset.Magnitude
	if dist < 1 then
		return false
	end
	local steps = math.max(3, math.ceil(dist / 8))
	for i = 0, steps do
		if self:inView(player, from + offset * (i / steps)) then
			return true
		end
	end
	return false
end

function Monster:boxedIn(spot)
	for _, offset in ipairs(CLEARANCE) do
		if workspace:Raycast(spot + UP, offset, self.rayParams) then
			return true
		end
	end
	return false
end

function Monster:toyCandidate(player, look, right, playerPos)
	local angle = math.rad(130 + math.random() * 100)
	local dir = look * math.cos(angle) + right * math.sin(angle)
	local floor = self:floorAt(playerPos + Vector3.new(dir.X, 0, dir.Z).Unit * math.random(config.toyMinDist + 10, config.toyMaxDist))
	if not floor then
		return nil
	end

	local spot = floor + Vector3.new(0, 3, 0)
	if self:boxedIn(spot) or self:inView(player, spot) then
		return nil
	end

	local origin = self.root.Position
	local score = (spot - origin).Magnitude * 0.5 + (1 - look:Dot((spot - playerPos).Unit)) * 150
	if workspace:Raycast(origin, (spot - origin).Unit * 15, self.rayParams) then
		score = score - 100
	end
	return spot, score
end

function Monster:pickToySpot(player)
	local head, root = headOf(player), rootOf(player)
	if not head or not root then
		return self.root.Position
	end

	local look = head.CFrame.LookVector
	local right = Vector3.new(-look.Z, 0, look.X).Unit
	local best, bestScore = nil, -math.huge

	for _ = 1, 30 do
		local spot, score = self:toyCandidate(player, look, right, root.Position)
		if spot and score > bestScore then
			best, bestScore = spot, score
		end
	end

	if best then
		return best
	end
	local fallback = self:floorAt(root.Position - look * config.toyMinDist)
	return fallback and fallback + Vector3.new(0, 3, 0) or self.root.Position
end

function Monster:face(point, dt)
	local pos = self.root.Position
	local dx, dz = point.X - pos.X, point.Z - pos.Z
	if dx * dx + dz * dz < 0.01 then
		return
	end

	local yaw = math.atan2(-dx, -dz)
	if self.align.Enabled then
		self.align.CFrame = CFrame.lookAt(pos, Vector3.new(point.X, pos.Y, point.Z))
		self.facing = yaw
	else
		self.facing = lerpAngle(self.facing, yaw, math.clamp(config.turnSpeed * dt, 0, 1))
		self.root.CFrame = CFrame.new(pos) * CFrame.Angles(0, self.facing, 0)
	end
end

function Monster:syncFacing()
	local look = self.root.CFrame.LookVector
	self.facing = math.atan2(-look.X, -look.Z)
end

function Monster:scan(dt)
	self.scanClock = self.scanClock + dt
	if self.scanClock > 1.5 then
		self.scanClock = 0
		self.scanDir = -self.scanDir
	end
	self.scanAngle = math.clamp(self.scanAngle + self.scanDir * 1.2 * dt, -1.2, 1.2)

	local cf = CFrame.new(self.root.Position) * CFrame.Angles(0, self.facing + self.scanAngle * 0.3, 0)
	if self.align.Enabled then
		self.align.CFrame = cf
	else
		self.root.CFrame = cf
	end
end

function Monster:trackHead(point, dt)
	local neck = self.neck
	if not neck then
		return
	end

	local goal = self.neckRest
	if point then
		local p = self.torso.CFrame:PointToObjectSpace(point)
		local yaw = math.clamp(math.atan2(-p.X, -p.Z), -YAW_LIMIT, YAW_LIMIT)
		local pitch = math.clamp(math.atan2(p.Y, math.sqrt(p.X ^ 2 + p.Z ^ 2)), -PITCH_LIMIT, PITCH_LIMIT)
		goal = goal * CFrame.Angles(pitch, 0, yaw)
	end
	neck.C0 = neck.C0:Lerp(goal, math.clamp(config.headSpeed * dt, 0, 1))
end

function Monster:pickWaypoint()
	local origin = self.root.Position
	local best, bestScore = self.waypoints[1], -math.huge

	for _, waypoint in ipairs(self.waypoints) do
		local offset = waypoint.Position - origin
		local dist = offset.Magnitude
		if dist >= 10 then
			local score = -math.abs(dist - 50) + math.random() * 30
			if self:pierce(origin, offset.Unit * 20) then
				score = score - 100
			end
			if score > bestScore then
				best, bestScore = waypoint, score
			end
		end
	end

	return best.Position + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
end

function Monster:broadcast()
	for _, player in ipairs(Players:GetPlayers()) do
		local root = rootOf(player)
		if root then
			local dist = (root.Position - self.root.Position).Magnitude
			local intensity = math.max(0, 1 - dist / config.proximityRange)
			if self.state == "Chase" then
				intensity = math.min(intensity * 1.5, 1)
			end
			proximityRemote:FireClient(player, intensity, self.state)
		end
	end
end

function Monster:requestPath(goal)
	if self.computing or (self.path and self.pathGoal and (self.pathGoal - goal).Magnitude < 8) then
		return
	end

	self.computing = true
	task.spawn(function()
		local ok = pcall(self.agent.ComputeAsync, self.agent, self.root.Position, goal)
		local nodes = {}
		if ok and self.agent.Status == Enum.PathStatus.Success then
			nodes = self.agent:GetWaypoints()
		end
		if #nodes >= 2 then
			self.path, self.pathIdx, self.pathGoal = nodes, 2, goal
		else
			self.path, self.pathGoal = nil, nil
		end
		self.computing = false
	end)
end

function Monster:unstuck(dt)
	self.stuckClock = self.stuckClock + dt
	if self.stuckClock < 1 then
		return false
	end
	self.stuckClock = 0

	local moved = (self.root.Position - self.stuckPos).Magnitude
	self.stuckPos = self.root.Position
	if moved >= config.stuckThreshold then
		self.stuckStreak = 0
		return false
	end

	self.stuckStreak = self.stuckStreak + 1
	self.path, self.pathGoal = nil, nil
	if self.stuckStreak < config.stuckMaxStreak then
		return false
	end

	self.stuckStreak = 0
	local state = self.state
	if state == "Toying" then
		self.toyDest = nil
	elseif state == "Patrol" then
		self.destination = self:pickWaypoint()
	elseif state == "Stalk" then
		self.stalkDest = nil
	elseif state == "Return" then
		self.destination = nil
	elseif state == "Chase" and self.lastSeen then
		self.lastSeen = self.lastSeen + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
	end
	return true
end

function Monster:walk(goal, dt)
	self.destination = goal
	if self:unstuck(dt) then
		return
	end

	local origin = self.root.Position
	local offset = goal - origin
	local blocked = self:pierce(origin, offset.Unit * math.min(offset.Magnitude, 30))
	if not blocked and (self.state == "Chase" or not routeNearPlayers(origin, goal, config.avoidDist)) then
		self.path, self.pathGoal = nil, nil
		self.humanoid:MoveTo(goal)
		return
	end

	self:requestPath(goal)
	local path = self.path
	if not path or self.pathIdx > #path then
		self.humanoid:MoveTo(origin)
		return
	end

	if flatDist(origin, path[self.pathIdx].Position) < 3.5 then
		self.pathIdx = self.pathIdx + 1
	end
	local node = path[self.pathIdx]
	self.humanoid:MoveTo(node and node.Position or goal)
end

function Monster:halt()
	self.humanoid:MoveTo(self.root.Position)
	self.destination, self.path, self.pathGoal = nil, nil, nil
	self.stuckClock, self.stuckStreak = 0, 0
end

function Monster:fade(alpha)
	for _, part in ipairs(self.model:GetDescendants()) do
		if part:IsA("BasePart") and part ~= self.root then
			TweenService:Create(part, FADE, { Transparency = alpha }):Play()
		end
	end
end

function Monster:lunge(point)
	local pos = self.root.Position
	local flat = Vector3.new(point.X, pos.Y, point.Z)
	local offset = flat - pos
	if offset.Magnitude < 0.1 then
		return
	end

	self.root.CFrame = CFrame.lookAt(pos, flat)

	local velocity = Instance.new("LinearVelocity")
	velocity.Attachment0 = self.attachment
	velocity.MaxForce = config.lungeForce
	velocity.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	velocity.RelativeTo = Enum.ActuatorRelativeTo.World
	velocity.VectorVelocity = offset.Unit * config.lungeSpeed
	velocity.Parent = self.root
	Debris:AddItem(velocity, config.lungeTime)
end

function Monster:stared(dt)
	if not self.target then
		return false
	end
	if self:inSightOf(self.target, self.head.Position, STARE_CONE, 0.95) then
		self.stare = self.stare + dt
	else
		self.stare = math.max(0, self.stare - dt * 0.5)
	end
	return self.stare >= config.stareTime
end

function Monster:giveUp()
	self.target = nil
	self.hearCooldown = config.hearCooldown
	self:enter("LookAround")
end

function Monster:reposition()
	self.toyPausing = false
	self.toyTimer = 0
	self.toyRepos = math.random(config.toyReposMin, config.toyReposMax)

	local spot = self:pickToySpot(self.target)
	local root = rootOf(self.target)
	if root and self:routeInView(self.target, self.root.Position, spot) then
		local away = (spot - root.Position).Unit
		local side = Vector3.new(-away.Z, 0, away.X)
		if not workspace:Raycast(spot + UP, side.Unit * 20, self.rayParams) then
			spot = spot + side * 20
		end
	end

	self.toyDest = spot
	self.path, self.pathGoal = nil, nil
	self.humanoid.WalkSpeed = config.toySpeed
	self:setLoco("Sprint")

	if math.random() < config.laughChance then
		self.sfx.laugh:Play()
	end
end

local onEnter = {
	Chase = function(self)
		self.humanoid.WalkSpeed = config.sprintSpeed
		self:setLoco("Sprint")
		self.blindTime, self.chaseTimer, self.stare = 0, 0, 0
	end,
	Patrol = function(self)
		self.humanoid.WalkSpeed = patrolSpeed()
		self:setLoco("Walk")
	end,
	Return = function(self)
		self.humanoid.WalkSpeed = config.walkSpeed
		self:setLoco("Walk")
	end,
	Stalk = function(self)
		self.humanoid.WalkSpeed = config.stalkSpeed
		self:setLoco("Walk")
		self.stare, self.stalkDest, self.stalkClock = 0, nil, 0
	end,
	Toying = function(self)
		self.humanoid.WalkSpeed = config.toySpeed
		self:setLoco("Sprint")
		self.stare, self.toyTimer, self.toyTotal = 0, 0, 0
		self.toyRepos = math.random(config.toyReposMin, config.toyReposMax)
		self.toyDest, self.toyPausing, self.toyPauseClock = nil, false, 0
	end,
	Idle = function(self)
		self.humanoid.WalkSpeed = 0
		self:setLoco("Idle")
	end,
	LookAround = function(self)
		self.humanoid.WalkSpeed = 0
		self:setLoco("Idle")
		self.scanAngle, self.scanClock = 0, 0
	end,
	Jumpscare = function(self)
		self.humanoid.WalkSpeed = 0
		self:stopAll()
		self.scareFired = false
	end,
}

function Monster:enter(state)
	local previous = self.state
	if previous == state then
		return
	end

	if state == "Toying" then
		self:fade(0.75)
	elseif previous == "Toying" then
		self:fade(0)
	end

	self.state = state
	self.model:SetAttribute("AIState", state)
	self.stateChanged:Fire(previous, state)
	self.timer = 0
	self:syncSounds(state)

	local moving = MOVING[state] == true
	self.humanoid.AutoRotate = moving
	self.align.Enabled = not moving
	if not moving then
		self:halt()
		self:syncFacing()
	end

	onEnter[state](self)
end

local states = {}

function states.Idle(self)
	local reaction = self:sense()
	if reaction then
		self:enter(reaction)
	elseif self.timer >= config.idleTime then
		self:enter("Patrol")
	end
end

function states.Patrol(self, dt)
	local reaction = self:sense()
	if reaction then
		self:enter(reaction)
		return
	end

	if self.paused then
		if self.timer > self.pauseTime then
			self.paused = false
			self.patrolClock = 0
			self:stop("LookingAround")
			self.humanoid.AutoRotate = true
			self.align.Enabled = false
			self.humanoid.WalkSpeed = patrolSpeed()
			self:setLoco("Walk")
		end
		return
	end

	self:walk(self.destination or self:pickWaypoint(), dt)
	if flatDist(self.destination, self.root.Position) < 5 then
		self.destination = self:pickWaypoint()
		self.path, self.pathGoal = nil, nil
	end

	self.patrolClock = self.patrolClock + dt
	if self.patrolClock > 3 then
		self.patrolClock = 0
		if math.random() < config.pauseChance then
			self.paused = true
			self.timer = 0
			self.pauseTime = math.random(config.pauseMin, config.pauseMax)
			self:halt()
			self.humanoid.AutoRotate = false
			self.align.Enabled = true
			self:syncFacing()
			self.humanoid.WalkSpeed = 0
			self:setLoco("Idle")
			self:play("LookingAround")
		end
	end
end

function states.Stalk(self, dt, targetRoot)
	if targetRoot then
		self.lastSeen = targetRoot.Position
	end

	if self:stared(dt) then
		self:enter("Chase")
		return
	end
	if targetRoot and (targetRoot.Position - self.root.Position).Magnitude < config.toyRadius then
		self:enter("Toying")
		return
	end

	self.stalkClock = self.stalkClock + dt
	if not self.stalkDest or self.stalkClock >= 2 then
		self.stalkClock = 0
		local spot = self.target and self:pickStalkSpot(self.target)
		if spot then
			self.stalkDest = spot
			self.path = nil
		end
	end

	if self.stalkDest then
		self:walk(self.stalkDest, dt)
		if flatDist(self.stalkDest, self.root.Position) < 5 then
			self.stalkDest = nil
		end
	elseif self.lastSeen then
		self:walk(self.lastSeen, dt)
		if flatDist(self.lastSeen, self.root.Position) < 5 then
			self:enter("LookAround")
			self:play("LookingAround")
		end
	end
end

function states.Toying(self, dt, targetRoot)
	if not targetRoot then
		self:enter("LookAround")
		return
	end
	if self:stared(dt) then
		self:enter("Chase")
		return
	end

	self.toyTotal = self.toyTotal + dt
	if self.toyTotal >= config.toyMaxTime then
		self:enter("Chase")
		return
	end
	if (targetRoot.Position - self.root.Position).Magnitude > config.toyLoseDist then
		self:enter("LookAround")
		return
	end

	if not self.toyDest then
		self:reposition()
	elseif not self.toyPausing then
		self:walk(self.toyDest, dt)
		if flatDist(self.root.Position, self.toyDest) < 7 then
			if config.toyPauseMax <= 0 then
				self:reposition()
			else
				self.toyPausing = true
				self.toyPauseClock = 0
				self.toyDest = nil
				self:halt()
			end
		end
	else
		self.toyPauseClock = self.toyPauseClock + dt
		self.toyTimer = self.toyTimer + dt
		if self.toyTimer >= self.toyRepos or self.toyPauseClock >= config.toyPauseMax or self:inView(self.target, self.root.Position) then
			self:reposition()
		else
			self.humanoid.WalkSpeed = 0
			self:setLoco("Idle")
			self:face(targetRoot.Position, dt)
		end
	end
end

function states.Chase(self, dt, targetRoot)
	if not targetRoot then
		self:giveUp()
		return
	end

	self.chaseTimer = self.chaseTimer + dt
	local origin = self.root.Position
	local offset = targetRoot.Position - origin
	local dist = offset.Magnitude

	local visible = self:canSee(self.target)
	if not visible and dist < 30 then
		local hit = self:pierce(origin, offset)
		visible = not hit or (hit.Position - origin).Magnitude >= dist * 0.95
	end

	local light = self.head.SpotLight
	if visible then
		self.lastSeen = targetRoot.Position
		self.blindTime = 0
		if dist <= config.scareReach and self.chaseTimer >= config.minChaseForScare then
			light.Enabled = false
			self:enter("Jumpscare")
			return
		end
		light.Enabled = true
		self:walk(targetRoot.Position, dt)
		return
	end

	self.blindTime = self.blindTime + dt
	light.Enabled = false
	if self.blindTime < config.chaseMemory and self.lastSeen then
		self:walk(self.lastSeen, dt)
		if flatDist(self.lastSeen, self.root.Position) >= 5 then
			return
		end
	end
	self:giveUp()
end

function states.LookAround(self, dt)
	if self.lastSeen then
		self:face(self.lastSeen, dt * 0.3)
	end
	self:scan(dt)

	local reaction = self:sense()
	if reaction then
		self:stop("LookingAround")
		self:enter(reaction)
		return
	end

	local track = self.tracks.LookingAround
	if (track and not track.IsPlaying) or self.timer >= config.lookAroundMax then
		self.lastSeen = nil
		self:stop("LookingAround")
		self:enter("Return")
	end
end

function states.Jumpscare(self)
	if not self.scareFired then
		self.scareFired = true
		if self.target and self.target.Character then
			local root = rootOf(self.target)
			if root then
				self:lunge(root.Position)
			end
			local anim = self.anims.Jumpscare
			jumpscareRemote:FireClient(self.target, anim and anim.AnimationId or "")
		end
	end

	local track = self.tracks.Jumpscare
	if self.timer >= 0.15 and not (track and track.IsPlaying) then
		self:play("Jumpscare", 0.05)
	end

	if self.timer > 2.5 then
		self.target = nil
		self:stopAll()
		self:enter("Return")
	end
end

function states.Return(self, dt)
	local reaction = self:sense()
	if reaction then
		self:enter(reaction)
		return
	end

	if not self.destination then
		local origin = self.root.Position
		local nearest, nearestDist = self.waypoints[1], math.huge
		for _, waypoint in ipairs(self.waypoints) do
			local dist = (waypoint.Position - origin).Magnitude
			if dist < nearestDist then
				nearest, nearestDist = waypoint, dist
			end
		end
		self.destination = nearest.Position
	end

	self:walk(self.destination, dt)
	if flatDist(self.destination, self.root.Position) < 4 then
		self:enter("Idle")
	end
end

function Monster:update(dt)
	self.timer = self.timer + dt
	self:tickBreathing(dt)
	self.hearCooldown = math.max(0, self.hearCooldown - dt)

	self.netClock = self.netClock + dt
	if self.netClock > 0.25 then
		self:broadcast()
		self.netClock = 0
	end

	local targetRoot = rootOf(self.target)
	self:trackHead(targetRoot and HUNTING[self.state] and targetRoot.Position or nil, dt)
	states[self.state](self, dt, targetRoot)
end

local waypoints = {}
for _, part in ipairs(CollectionService:GetTagged("MonsterWaypoint")) do
	if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
		table.insert(waypoints, part)
	end
end

if #waypoints == 0 then
	warn("[MonsterAI] no parts tagged MonsterWaypoint in workspace")
	return
end

local start = waypoints[math.random(#waypoints)]
local monster = Monster.new(CFrame.new(start.Position + Vector3.new(0, 3, 0)), waypoints)

task.spawn(function()
	while monster.model.Parent and monster.humanoid.Health > 0 do
		monster:update(RunService.Heartbeat:Wait())
	end
end)
