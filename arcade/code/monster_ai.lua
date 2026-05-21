-- monster_ai.luau · server
-- 8 states: idle, patrol, stalk, toying, chase, lookaround, jumpscare, return
-- transitions are driven by vision, hearing and distance
-- states dispatched through a handler table, config frozen at runtime,
-- GoodSignal drives a stateChanged event for client sync / debug.

local players            = game:GetService("Players")
local runService         = game:GetService("RunService")
local pathService        = game:GetService("PathfindingService")
local serverStorage      = game:GetService("ServerStorage")
local repStorage         = game:GetService("ReplicatedStorage")
local collectionService  = game:GetService("CollectionService")
local tweenService       = game:GetService("TweenService")
local debris             = game:GetService("Debris")

-- stravant's signal module
local Signal = require(repStorage.Packages.Signal)

-- runtime remotes so we don't need to place them manually
local jumpscareRemote = Instance.new("RemoteEvent")
jumpscareRemote.Name   = "JumpscareEvent"
jumpscareRemote.Parent = repStorage

local proximityRemote = Instance.new("RemoteEvent")
proximityRemote.Name   = "MonsterProximity"
proximityRemote.Parent = repStorage


-- read-only proxy. __newindex throws so config typos blow up loud
-- instead of silently breaking tuning months later
local function freeze(src: {[string]: any}): {[string]: any}
	return setmetatable({}, {
		__index    = src,
		__newindex = function(_, k)
			error(string.format("[MonsterAI] attempt to write '%s' on frozen table", k), 2)
		end,
		__tostring = function()
			local count = 0
			for _ in src do count += 1 end
			return string.format("FrozenConfig<%d keys>", count)
		end,
	})
end

-- every tuning value lives here. for variants i layer overrides via __index:
-- local fastCfg = setmetatable({ sprintSpd = 40 }, { __index = baseCfg })
local baseCfg = {
	walkSpd         = 22,
	sprintSpd       = 28.25,
	stalkSpd        = 25,

	-- vision: tight central cone + wider but shorter peripheral zone
	fovHalf         = 65,
	viewDist        = 95,
	peripheralDist  = 40,

	-- hearing grows when the target is sprinting -> sneaking actually matters
	hearDist        = 80,
	sprintHearDist  = 140,

	jumpscareReach  = 4.5,
	minChaseForScare = 1.8, -- stops the monster from insta-killing on chase entry

	idleDur         = 2.5,
	lookAroundMax   = 5,
	chaseMemory     = 4, -- how long it remembers your last seen pos

	rotSpd          = 6,
	headTrackSpd    = 8,
	proximityRange  = 50,

	-- raycast filtering. small decorations don't block vision
	minPartSize     = 3,
	maxPierces      = 25,

	pauseChance     = 0.04,
	pauseMin        = 1,
	pauseMax        = 3,
	spdJitter       = 3,

	playerLookTime  = 2, -- stare time before stalk/toying escalates to chase
	hearCooldown    = 5, -- silence hearing right after losing a target

	-- toying: circles around the player just outside their view
	toyRadius       = 140,
	toyingSpd       = 60,
	toyingMaxTime   = 40,
	toyReposMin     = 2,
	toyReposMax     = 6,
	laughChance     = 0.35,
	toyLoseDist     = 110,
	toyPauseMax     = 3,
	toyMinDist      = 70,
	toyMaxDist      = 110,

	stealthVol      = 0.03, -- stalk footsteps barely audible
	playerAvoidDist = 20,   -- non-chase states stay clear of players

	stuckThreshold  = 1.2,
	stuckMaxStreak  = 3,

	rolloff = {
		breathing  = 50,
		walk       = 65,
		sprint     = 120,
		lookAround = 60,
		jumpscare  = 100,
		laugh      = 70,
	},

	-- jumpscare lunge tuning + AlignOrientation feel
	lungeForce      = 50000,
	lungeSpeed      = 60,
	lungeDuration   = 0.3,
	alignTorque     = 50000,
	alignResponse   = 12,

	fadeDuration    = 0.5,
}

local cfg = freeze(baseCfg)

local soundIds = {
	breathing  = "rbxassetid://87119489483504",
	walk       = "rbxassetid://138514229177623",
	sprint     = "rbxassetid://139209257128845",
	lookAround = "rbxassetid://137431264282253",
	jumpscare  = "rbxassetid://137800374619679",
	laugh      = "rbxassetid://140186441914469",
}

-- union type so typos get caught at edit time
type aiState = "Idle" | "Patrol" | "LookAround"
	| "Chase" | "Jumpscare" | "Return"
	| "Stalk" | "Toying"

-- TweenInfos cached once -> no per-transition GC churn
local fadeInInfo  = TweenInfo.new(cfg.fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local fadeOutInfo = TweenInfo.new(cfg.fadeDuration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)


-- utilities

-- short-arc angle lerp. without this the body sometimes spins 270° instead of 90°
local function lerpAngle(from: number, to: number, alpha: number): number
	local delta = ((to - from) + math.pi) % (2 * math.pi) - math.pi
	return from + delta * alpha
end

-- horizontal-only distance. Y diffs would mess up range checks across floors
local function hDist(a: Vector3, b: Vector3): number
	if not a or not b then return math.huge end
	local dx = a.X - b.X
	local dz = a.Z - b.Z
	return math.sqrt(dx * dx + dz * dz)
end

-- inverse-tapered spatial sound. rolloff = max audible distance
local function mkSound(parent: BasePart, tag: string, assetId: string, loop: boolean, vol: number, rolloff: number): Sound
	local snd = Instance.new("Sound")
	snd.Name        = tag
	snd.SoundId     = assetId
	snd.Looped      = loop
	snd.Volume      = vol
	snd.RollOffMode        = Enum.RollOffMode.InverseTapered
	snd.RollOffMinDistance = 5
	snd.RollOffMaxDistance = rolloff
	snd.Parent      = parent
	return snd
end

-- shortest distance from point p to segment ab.
-- used so non-chase states don't walk past players
local function pointToSegDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab  = b - a
	local len = ab.Magnitude
	if len < 0.5 then return (p - a).Magnitude end
	local dir = ab / len
	local t   = math.clamp((p - a):Dot(dir), 0, len)
	return (p - (a + dir * t)).Magnitude
end


-- Monster class

local Monster = {}
Monster.__index = Monster

function Monster:__tostring(): string
	return string.format("Monster [%s] | HP: %d", self.state, self.hum.Health)
end

-- writes state attribute + fires signal so debug/client effects can react
function Monster:_setState(newState: aiState)
	local old = self.state
	self.state = newState
	if self.model then
		self.model:SetAttribute("AIState", newState)
	end
	self.stateChanged:Fire(old, newState)
end


-- subsystem init (kept out of new() so the constructor stays readable)

function Monster:_initAnims()
	self.animator = self.hum:FindFirstChildOfClass("Animator")
		or Instance.new("Animator", self.hum) :: Animator

	local animFolder = repStorage.Animations
	self.anims = {} :: {[string]: Animation}

	for _, tag in {"Idle", "Walk", "Sprint", "Jumpscare", "LookingAround"} do
		local obj = animFolder:FindFirstChild(tag)
		if obj and obj:IsA("Animation") then
			self.anims[tag] = obj
		end
	end

	self.tracks = {} :: {[string]: AnimationTrack}
end

function Monster:_initSounds()
	local ro = cfg.rolloff

	self.sfx = {
		breathing  = mkSound(self.root, "Breathing",  soundIds.breathing,  true,  0.3, ro.breathing),
		walk       = mkSound(self.root, "Walk",       soundIds.walk,       true,  0.5, ro.walk),
		sprint     = mkSound(self.root, "Sprint",     soundIds.sprint,     true,  0.8, ro.sprint),
		lookAround = mkSound(self.root, "LookAround", soundIds.lookAround, false, 0.6, ro.lookAround),
		jumpscare  = mkSound(self.root, "Jumpscare",  soundIds.jumpscare,  false, 10,  ro.jumpscare),
		laugh      = mkSound(self.root, "Laugh",      soundIds.laugh,      false, 0.7, ro.laugh),
	}

	self.sfx.breathing:Play()
end

function Monster:_initPathfinding()
	self.rayParams = RaycastParams.new()
	self.rayParams.FilterType = Enum.RaycastFilterType.Exclude
	self.rayParams.FilterDescendantsInstances = {self.model}
	self.rayParams.IgnoreWater = true

	-- indoor agent: can't jump, hates water
	self.pathAgent = pathService:CreatePath({
		AgentRadius     = 2.5,
		AgentHeight     = 7,
		AgentCanJump    = false,
		WaypointSpacing = 4,
		Costs           = { [Enum.Material.Water] = 100 },
	})
end

-- AlignOrientation handles smooth body rotation when not moving.
-- during movement humanoid AutoRotate takes over.
-- LinearVelocity for the jumpscare is built on demand.
function Monster:_initPhysics()
	local rootAttach = self.root:FindFirstChild("RootAttachment")
	if not rootAttach then
		rootAttach = Instance.new("Attachment")
		rootAttach.Name = "RootAttachment"
		rootAttach.Parent = self.root
	end
	self.rootAttach = rootAttach

	local align = Instance.new("AlignOrientation")
	align.Attachment0    = rootAttach
	align.Mode           = Enum.OrientationAlignmentMode.OneAttachment
	align.MaxTorque      = cfg.alignTorque
	align.Responsiveness = cfg.alignResponse
	align.Enabled        = false
	align.Parent         = self.root

	self.alignOrient = align
end


function Monster.new(origin: CFrame, waypoints: {BasePart})
	local mdl = serverStorage.Entities.Monster:Clone()
	mdl:PivotTo(origin)
	mdl.Parent = workspace

	-- default Animate script fights custom animation control
	local defAnim = mdl:FindFirstChild("Animate")
	if defAnim then defAnim:Destroy() end

	local hum:       Humanoid = mdl:FindFirstChildOfClass("Humanoid") :: Humanoid
	local rootPart:  BasePart = mdl:FindFirstChild("HumanoidRootPart") :: BasePart
	local headPart:  BasePart = mdl:FindFirstChild("Head") :: BasePart
	local torsoPart: BasePart = mdl:FindFirstChild("Torso") :: BasePart

	rootPart:SetNetworkOwner(nil) -- server owns physics so no rubberbanding
	hum.WalkSpeed   = cfg.walkSpd
	hum.AutoRotate  = true

	-- remember default neck C0 so we can blend back to it
	local neck: Motor6D? = torsoPart:FindFirstChild("Neck") :: Motor6D?
	local neckDef = if neck then neck.C0 else CFrame.new(0, 1, 0)

	local self = setmetatable({
		model    = mdl,    hum   = hum,
		root     = rootPart, head = headPart, torso = torsoPart,
		neckDef  = neckDef, waypoints = waypoints, spawnCF = origin,

		stateChanged = Signal.new(), -- anything can listen for transitions

		state       = "Idle" :: aiState,
		prevState   = "Idle" :: aiState,
		target      = nil :: Player?,
		lastSeenAt  = nil :: Vector3?,
		timer       = 0,
		moveAnim    = "" :: string,
		lastMoveDst = nil :: Vector3?,

		pathNodes    = nil :: {PathWaypoint}?,
		pathIdx      = 1,
		computing    = false,
		pathBuiltFor = nil :: Vector3?,
		destination  = nil :: Vector3?,

		patrolClock = 0,  paused      = false, pauseDur    = 0,
		stuckPos    = rootPart.Position, stuckClock = 0, stuckStreak = 0,
		facingY     = 0,  jumpscareFired = false,
		blindTime   = 0,  chaseTimer  = 0,
		scanAngle   = 0,  scanDir     = 1, scanClock = 0,
		netClock    = 0,
		playerLookTimer   = 0,
		hearCooldownTimer = 0,

		stalkDest   = nil :: Vector3?,
		stalkRecalc = 0,

		toyTimer      = 0, toyReposTime = 0, toyDest = nil :: Vector3?,
		toyingTotal   = 0, toyPausing   = false, toyPauseClock = 0,
	}, Monster)

	self:_initAnims()
	self:_initSounds()
	self:_initPathfinding()
	self:_initPhysics()

	-- auto-advance through path waypoints
	hum.MoveToFinished:Connect(function()
		if self.pathNodes and self.pathIdx <= #self.pathNodes then
			local nxt = self.pathNodes[self.pathIdx]
			self.lastMoveDst = nxt.Position
			hum:MoveTo(nxt.Position)
		end
	end)

	mdl:SetAttribute("AIState", "Idle")
	self:_setMoveAnim("Idle")
	return self
end


-- movement helpers

local DEST_THRESH = 3 -- skip MoveTo if goal hasn't drifted much

function Monster:_moveTo(pos: Vector3)
	if self.lastMoveDst and (self.lastMoveDst - pos).Magnitude < DEST_THRESH then return end
	self.lastMoveDst = pos
	self.hum:MoveTo(pos)
end

-- bypasses the threshold check (forced redirect)
function Monster:_forceMoveTo(pos: Vector3)
	self.lastMoveDst = pos
	self.hum:MoveTo(pos)
end

-- non-locomotion anims. locomotion (Idle/Walk/Sprint) is handled by _setMoveAnim
function Monster:_play(tag: string, fade: number?)
	for tName, track in self.tracks do
		local isLoco = tName == "Idle" or tName == "Walk" or tName == "Sprint"
		if not isLoco and tName ~= tag and track.IsPlaying then
			track:Stop(0.2)
		end
	end
	if not self.anims[tag] then return end
	if not self.tracks[tag] then
		self.tracks[tag] = self.animator:LoadAnimation(self.anims[tag])
	end
	if not self.tracks[tag].IsPlaying then
		self.tracks[tag]:Play(fade or 0.15)
	end
end

function Monster:_stop(tag: string)
	local t = self.tracks[tag]
	if t and t.IsPlaying then t:Stop(0.2) end
end

function Monster:_stopAll()
	for _, t in self.tracks do
		if t.IsPlaying then t:Stop(0.2) end
	end
	self.moveAnim = ""
end

-- swap locomotion anim without restarting the same track
function Monster:_setMoveAnim(tag: string)
	if self.moveAnim == tag then return end
	for _, n in {"Idle", "Walk", "Sprint"} do
		if n ~= tag then self:_stop(n) end
	end
	if self.anims[tag] then
		if not self.tracks[tag] then
			self.tracks[tag] = self.animator:LoadAnimation(self.anims[tag])
		end
		if not self.tracks[tag].IsPlaying then
			self.tracks[tag]:Play(0.2)
		end
	end
	self.moveAnim = tag
end


-- per-state sound bed. anything missing here = silence
local soundCfgMap: {[aiState]: {key: string, vol: number}} = {
	Patrol     = { key = "walk",       vol = 0.5 },
	Return     = { key = "walk",       vol = 0.5 },
	Stalk      = { key = "walk",       vol = cfg.stealthVol }, -- near-silent steps
	Chase      = { key = "sprint",     vol = 0.8 },
	LookAround = { key = "lookAround", vol = 0.6 },
	Jumpscare  = { key = "jumpscare",  vol = 10 },
}

function Monster:_syncSounds(st: aiState)
	self.sfx.walk:Stop()
	self.sfx.sprint:Stop()

	local entry = soundCfgMap[st]
	if entry then
		local snd = self.sfx[entry.key]
		snd.Volume = entry.vol
		snd:Play()
	end
end

-- breathing intensity per state. heavier when chasing, silent when toying
local breathingGoals: {[aiState]: number} = {
	Chase      = 0.7,
	LookAround = 0.5,
	Stalk      = 0.12,
	Toying     = 0,
}

function Monster:_tickBreathing(dt: number)
	local goal = breathingGoals[self.state] or 0.3
	local vol = self.sfx.breathing.Volume
	self.sfx.breathing.Volume = vol + (goal - vol) * math.clamp(3 * dt, 0, 1)
end


-- piercing raycast: ignores non-collidable + tiny decoration parts.
-- invisible barriers and small props no longer block vision.
function Monster:_castPiercing(from: Vector3, dir: Vector3): RaycastResult?
	local pos = from
	local rem = dir

	for _ = 1, cfg.maxPierces do
		local hit = workspace:Raycast(pos, rem, self.rayParams)
		if not hit then return nil end

		local part = hit.Instance

		if not part.CanCollide then
			local step = hit.Position - pos
			pos = hit.Position + (rem - step).Unit * 0.05
			rem = rem - step
			continue
		end

		local sz = part.Size
		if sz.X < cfg.minPartSize and sz.Y < cfg.minPartSize and sz.Z < cfg.minPartSize then
			local step = hit.Position - pos
			pos = hit.Position + (rem - step).Unit * 0.05
			rem = rem - step
			continue
		end

		-- solid wall
		return hit
	end
	return nil
end

-- two-zone vision: tight central cone (long range) + wide peripheral (short).
-- casts to torso AND head height so partial cover doesn't fully hide a player.
function Monster:_checkSight(plr: Player): (boolean, boolean, number)
	local char = plr.Character
	if not char then return false, false, math.huge end

	local tRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tHum  = char:FindFirstChildOfClass("Humanoid")
	if not tRoot or not tHum or tHum.Health <= 0 then return false, false, math.huge end

	local eye    = self.head.Position
	local look   = self.head.CFrame.LookVector
	local offset = tRoot.Position - eye
	local dist   = offset.Magnitude

	if dist > cfg.viewDist then return false, false, dist end

	local dot      = look:Dot(offset.Unit)
	local innerCos = math.cos(math.rad(cfg.fovHalf * 0.5))
	local outerCos = math.cos(math.rad(cfg.fovHalf))

	if dot < outerCos then return false, false, dist end

	local peripheral = dot < innerCos
	if peripheral and dist > cfg.peripheralDist then return false, false, dist end

	for _, point in { tRoot.Position, tRoot.Position + Vector3.new(0, 1.5, 0) } do
		local ray = point - eye
		local hit = self:_castPiercing(eye, ray.Unit * ray.Magnitude)
		if not hit then return true, peripheral, dist end
		-- 95% so grazing a wall edge still counts as seen
		if (hit.Position - eye).Magnitude >= ray.Magnitude * 0.95 then
			return true, peripheral, dist
		end
	end
	return false, false, dist
end

function Monster:_checkHearing(plr: Player): (boolean, number)
	local char = plr.Character
	if not char then return false, math.huge end

	local tRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local tHum  = char:FindFirstChildOfClass("Humanoid")
	if not tRoot or not tHum then return false, math.huge end

	local dist  = (tRoot.Position - self.root.Position).Magnitude
	local range = if tHum.WalkSpeed > 20 then cfg.sprintHearDist else cfg.hearDist
	return dist <= range, dist
end

-- player staring at us with LOS? used to trigger chase from stalk/toying
function Monster:_checkPlayerLooking(plr: Player): boolean
	local char = plr.Character
	if not char then return false end

	local pHead = char:FindFirstChild("Head") :: BasePart?
	if not pHead then return false end

	local toMonster = self.head.Position - pHead.Position
	local dist      = toMonster.Magnitude
	if dist > cfg.viewDist or dist < 0.5 then return false end

	-- 30° cone so it only counts if they're really looking
	if pHead.CFrame.LookVector:Dot(toMonster.Unit) < math.cos(math.rad(30)) then return false end

	local hit = self:_castPiercing(pHead.Position, toMonster.Unit * dist)
	if hit and (hit.Position - pHead.Position).Magnitude < dist * 0.95 then return false end
	return true
end


-- shared sense check used by idle / patrol / lookaround / return.
-- vision wins over hearing, hearing respects cooldown.
function Monster:_senseTargets(): aiState?
	local bestSeen: Player? = nil
	local bestSeenDist      = math.huge

	for _, plr in players:GetPlayers() do
		local seen, _, dist = self:_checkSight(plr)
		if seen and dist < bestSeenDist then
			bestSeen     = plr
			bestSeenDist = dist
		end
	end

	if bestSeen then
		local sRoot = bestSeen.Character and bestSeen.Character:FindFirstChild("HumanoidRootPart")
		if sRoot then
			self.target     = bestSeen
			self.lastSeenAt = sRoot.Position
			return "Chase"
		end
	end

	if self.hearCooldownTimer > 0 then return nil end

	local bestHeard: Player? = nil
	local bestHeardDist      = math.huge

	for _, plr in players:GetPlayers() do
		local heard, dist = self:_checkHearing(plr)
		if heard and dist < bestHeardDist then
			bestHeard     = plr
			bestHeardDist = dist
		end
	end

	if bestHeard then
		local hRoot = bestHeard.Character and bestHeard.Character:FindFirstChild("HumanoidRootPart")
		if hRoot then
			self.target     = bestHeard
			self.lastSeenAt = hRoot.Position
			return "Stalk"
		end
	end

	return nil
end


-- would a straight walk pass too close to any player?
function Monster:_lineNearAnyPlayer(from: Vector3, to: Vector3, safeRadius: number): boolean
	for _, plr in players:GetPlayers() do
		local char = plr.Character
		if not char then continue end

		local pRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pHum  = char:FindFirstChildOfClass("Humanoid")
		if not pRoot or not pHum or pHum.Health <= 0 then continue end

		if pointToSegDist(pRoot.Position, from, to) < safeRadius then
			return true
		end
	end
	return false
end


-- 8 candidates in the rear hemisphere, scored by how "behind" the player they are.
-- floor + clearance checks reject candidates inside walls / floating in air.
function Monster:_pickStalkPos(plr: Player): Vector3?
	local char = plr.Character
	if not char then return nil end

	local pHead = char:FindFirstChild("Head") :: BasePart?
	local pRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not pHead or not pRoot then return nil end

	local look      = pHead.CFrame.LookVector
	local playerPos = pRoot.Position
	local best: Vector3? = nil
	local bestDot = math.huge

	for _ = 1, 8 do
		local ang   = math.rad(90 + math.random() * 180) -- 90°-270° = behind
		local right = Vector3.new(-look.Z, 0, look.X).Unit
		local dir   = look * math.cos(ang) + right * math.sin(ang)
		dir = Vector3.new(dir.X, 0, dir.Z)
		if dir.Magnitude < 0.1 then continue end
		dir = dir.Unit

		local dist      = math.random(18, 30)
		local candidate = playerPos + dir * dist

		local floorHit = workspace:Raycast(candidate + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), self.rayParams)
		if not floorHit then continue end
		candidate = Vector3.new(candidate.X, floorHit.Position.Y + 3, candidate.Z)

		-- basic clearance
		local toCandidate = candidate - self.root.Position
		if toCandidate.Magnitude > 1 then
			local hit = self:_castPiercing(self.root.Position, toCandidate.Unit * math.min(toCandidate.Magnitude, 40))
			if hit and (hit.Position - self.root.Position).Magnitude < toCandidate.Magnitude * 0.5 then
				continue
			end
		end

		-- lower dot = more behind = better
		local dot = look:Dot((candidate - playerPos).Unit)
		if dot < bestDot then
			bestDot = dot
			best    = candidate
		end
	end
	return best
end

function Monster:_isInPlayerFOV(plr: Player, pos: Vector3): boolean
	local char = plr.Character
	if not char then return false end

	local pHead = char:FindFirstChild("Head") :: BasePart?
	if not pHead then return false end

	local toPos = pos - pHead.Position
	local dist  = toPos.Magnitude
	if dist < 0.5 or dist > cfg.viewDist then return false end

	if pHead.CFrame.LookVector:Dot(toPos.Unit) < math.cos(math.rad(65)) then return false end

	local hit = self:_castPiercing(pHead.Position, toPos.Unit * dist)
	if hit and (hit.Position - pHead.Position).Magnitude < dist * 0.9 then return false end
	return true
end

-- sample a path. if any sample lands in the player's view, the route is unsafe
function Monster:_pathCrossesFOV(plr: Player, from: Vector3, to: Vector3): boolean
	local dir  = to - from
	local dist = dir.Magnitude
	if dist < 1 then return false end

	local steps = math.max(3, math.ceil(dist / 8))
	for i = 0, steps do
		if self:_isInPlayerFOV(plr, from + dir * (i / steps)) then
			return true
		end
	end
	return false
end

-- 30 candidates behind the player, scored by:
--   distance to monster (closer is easier to reach)
--   how directly behind the player they are
--   whether a wall is in the way (penalty)
function Monster:_pickToyPos(plr: Player): Vector3
	local char = plr.Character
	if not char then return self.root.Position end

	local pRoot = char:FindFirstChild("HumanoidRootPart")
	local pHead = char:FindFirstChild("Head")
	if not pRoot or not pHead then return self.root.Position end

	local look      = pHead.CFrame.LookVector
	local playerPos = pRoot.Position
	local best      = nil
	local bestScore = -math.huge

	for _ = 1, 30 do
		-- 130°-230° = mostly behind
		local ang   = math.rad(130 + math.random() * 100)
		local right = Vector3.new(-look.Z, 0, look.X).Unit
		local dir   = (look * math.cos(ang) + right * math.sin(ang))
		dir = Vector3.new(dir.X, 0, dir.Z).Unit

		local dist      = math.random(cfg.toyMinDist + 10, cfg.toyMaxDist)
		local candidate = playerPos + dir * dist

		local floorHit = workspace:Raycast(candidate + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), self.rayParams)
		if not floorHit then continue end
		candidate = floorHit.Position + Vector3.new(0, 3, 0)

		-- 4-direction clearance so we don't pick a spot inside a wall
		local blocked = false
		for _, ofs in {Vector3.new(3.5, 0, 0), Vector3.new(-3.5, 0, 0), Vector3.new(0, 0, 3.5), Vector3.new(0, 0, -3.5)} do
			if workspace:Raycast(candidate + Vector3.new(0, 1, 0), ofs, self.rayParams) then
				blocked = true
				break
			end
		end
		if blocked then continue end

		if self:_isInPlayerFOV(plr, candidate) then continue end

		local score    = (candidate - self.root.Position).Magnitude * 0.5
		local toPlayer = (playerPos - candidate).Unit
		score += (1 - pHead.CFrame.LookVector:Dot(-toPlayer)) * 150

		if workspace:Raycast(self.root.Position, (candidate - self.root.Position).Unit * 15, self.rayParams) then
			score -= 100
		end

		if score > bestScore then
			bestScore = score
			best      = candidate
		end
	end

	-- fallback: directly behind the player
	if not best then
		local fallback = playerPos - look * cfg.toyMinDist
		local floorHit = workspace:Raycast(fallback + Vector3.new(0, 10, 0), Vector3.new(0, -20, 0), self.rayParams)
		if floorHit then
			best = floorHit.Position + Vector3.new(0, 3, 0)
		else
			best = self.root.Position
		end
	end

	return best
end


-- smooth body rotation. AlignOrientation when stationary, manual lerp fallback
function Monster:_lookToward(pos: Vector3, dt: number)
	local p      = self.root.Position
	local dx, dz = pos.X - p.X, pos.Z - p.Z
	if dx * dx + dz * dz < 0.01 then return end

	if self.alignOrient and self.alignOrient.Enabled then
		local flatTarget = Vector3.new(pos.X, p.Y, pos.Z)
		self.alignOrient.CFrame = CFrame.lookAt(p, flatTarget)
		self.facingY = math.atan2(-dx, -dz)
	else
		local goal  = math.atan2(-dx, -dz)
		local alpha = math.clamp(cfg.rotSpd * dt, 0, 1)
		self.facingY = lerpAngle(self.facingY, goal, alpha)
		self.root.CFrame = CFrame.new(p) * CFrame.Angles(0, self.facingY, 0)
	end
end

function Monster:_syncFacing()
	local lv = self.root.CFrame.LookVector
	self.facingY = math.atan2(-lv.X, -lv.Z)
end

-- creepy oscillating head scan during lookaround
function Monster:_scanLook(dt: number)
	self.scanClock = self.scanClock + dt
	if self.scanClock > 1.5 then
		self.scanClock = 0
		self.scanDir   = -self.scanDir
	end
	self.scanAngle = math.clamp(self.scanAngle + self.scanDir * 1.2 * dt, -1.2, 1.2)

	local p = self.root.Position
	local rotCF = CFrame.new(p) * CFrame.Angles(0, self.facingY + self.scanAngle * 0.3, 0)
	if self.alignOrient and self.alignOrient.Enabled then
		self.alignOrient.CFrame = rotCF
	else
		self.root.CFrame = rotCF
	end
end

-- Motor6D neck tracking, yaw/pitch clamped so it doesn't snap into impossible poses
function Monster:_trackHead(targetPos: Vector3?, dt: number)
	local neck: Motor6D? = self.torso:FindFirstChild("Neck") :: Motor6D?
	if not neck then return end

	if not targetPos then
		neck.C0 = neck.C0:Lerp(self.neckDef, math.clamp(cfg.headTrackSpd * dt, 0, 1))
		return
	end

	local localP = self.torso.CFrame:PointToObjectSpace(targetPos)
	local yaw    = math.clamp(math.atan2(-localP.X, -localP.Z), math.rad(-70), math.rad(70))
	local pitch  = math.clamp(
		math.atan2(localP.Y, math.sqrt(localP.X ^ 2 + localP.Z ^ 2)),
		math.rad(-40), math.rad(40)
	)

	local goalC0 = self.neckDef * CFrame.Angles(pitch, 0, yaw)
	neck.C0 = neck.C0:Lerp(goalC0, math.clamp(cfg.headTrackSpd * dt, 0, 1))
end

-- next patrol waypoint. mid-distance preferred, blocked ones penalized, jitter for unpredictability
function Monster:_pickWaypoint(): Vector3
	local best      = self.waypoints[1]
	local bestScore = -math.huge

	for _, wp in self.waypoints do
		local dist = (wp.Position - self.root.Position).Magnitude
		if dist < 10 then continue end

		local score = -math.abs(dist - 50) -- ~50 studs is the sweet spot

		local dir = (wp.Position - self.root.Position).Unit
		if self:_castPiercing(self.root.Position, dir * 20) then
			score -= 100
		end

		score += math.random() * 30
		if score > bestScore then
			bestScore = score
			best      = wp
		end
	end

	return best.Position + Vector3.new(math.random(-4, 4), 0, math.random(-4, 4))
end


-- 4Hz client proximity broadcast for heartbeat sfx / vignette
function Monster:_broadcastProximity()
	for _, plr in players:GetPlayers() do
		local char = plr.Character
		if not char then continue end
		local pRoot = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not pRoot then continue end

		local dist = (pRoot.Position - self.root.Position).Magnitude
		if dist > cfg.proximityRange then
			proximityRemote:FireClient(plr, 0, self.state)
			continue
		end

		local intensity = 1 - dist / cfg.proximityRange
		if self.state == "Chase" then
			intensity = math.clamp(intensity * 1.5, 0, 1)
		end
		proximityRemote:FireClient(plr, intensity, self.state)
	end
end


-- async pathfinding. coalesces requests that haven't moved much
function Monster:_requestPath(goal: Vector3)
	if self.computing then return end
	if self.pathBuiltFor and self.pathNodes and (self.pathBuiltFor - goal).Magnitude < 8 then return end

	self.computing = true
	task.spawn(function()
		local ok = pcall(function()
			self.pathAgent:ComputeAsync(self.root.Position, goal)
		end)

		if ok and self.pathAgent.Status == Enum.PathStatus.Success then
			local nodes = self.pathAgent:GetWaypoints()
			if #nodes >= 2 then
				self.pathNodes    = nodes
				self.pathIdx      = 2 -- skip current pos
				self.pathBuiltFor = goal
			else
				self.pathNodes    = nil
				self.pathBuiltFor = nil
			end
		else
			self.pathNodes    = nil
			self.pathBuiltFor = nil
		end

		self.computing = false
	end)
end


-- main movement driver. straight line if clear + safe, pathfinding otherwise.
-- stuck recovery picks a new objective after enough consecutive failures.
function Monster:_walkToward(goal: Vector3, dt: number)
	self.destination = goal

	self.stuckClock = self.stuckClock + dt
	if self.stuckClock >= 1 then
		self.stuckClock = 0
		local moved = (self.root.Position - self.stuckPos).Magnitude
		self.stuckPos = self.root.Position

		if moved < cfg.stuckThreshold then
			self.stuckStreak = self.stuckStreak + 1
			self.pathNodes    = nil
			self.pathBuiltFor = nil
			self.lastMoveDst  = nil

			if self.stuckStreak >= cfg.stuckMaxStreak then
				self.stuckStreak = 0

				if self.state == "Toying" then
					self.toyDest = nil
				elseif self.state == "Patrol" then
					self.destination = self:_pickWaypoint()
				elseif self.state == "Stalk" then
					self.stalkDest = nil
				elseif self.state == "Return" then
					self.destination = nil
				elseif self.state == "Chase" and self.lastSeenAt then
					-- nudge last seen pos so we don't stall on the same spot
					local ofs = Vector3.new(math.random(-10, 10), 0, math.random(-10, 10))
					self.lastSeenAt = self.lastSeenAt + ofs
				end
				return
			end
		else
			self.stuckStreak = 0
		end
	end

	local dir  = goal - self.root.Position
	local dist = dir.Magnitude
	local hit  = self:_castPiercing(self.root.Position, dir.Unit * math.min(dist, 30))

	-- outside chase, don't walk through players
	local avoidDirect = false
	if self.state ~= "Chase" then
		avoidDirect = self:_lineNearAnyPlayer(self.root.Position, goal, cfg.playerAvoidDist)
	end

	if not hit and not avoidDirect then
		self.pathNodes    = nil
		self.pathBuiltFor = nil
		self.hum:MoveTo(goal)
		return
	end

	self:_requestPath(goal)

	if self.pathNodes and self.pathIdx <= #self.pathNodes then
		local nodePos = self.pathNodes[self.pathIdx].Position
		if hDist(self.root.Position, nodePos) < 3.5 then
			self.pathIdx = self.pathIdx + 1
		end

		if self.pathNodes and self.pathIdx <= #self.pathNodes then
			self.hum:MoveTo(self.pathNodes[self.pathIdx].Position)
		else
			self.hum:MoveTo(goal)
		end
	else
		-- no path yet, hold position
		self.hum:MoveTo(self.root.Position)
	end
end

function Monster:_halt()
	self:_forceMoveTo(self.root.Position)
	self.destination  = nil
	self.pathNodes    = nil
	self.pathBuiltFor = nil
	self.lastMoveDst  = nil
	self.stuckClock   = 0
	self.stuckStreak  = 0
end


-- tween transparency for the toying "ghost" look
function Monster:_tweenTransparency(goalAlpha: number)
	for _, part in self.model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
			local info = if goalAlpha > 0 then fadeInInfo else fadeOutInfo
			tweenService:Create(part, info, { Transparency = goalAlpha }):Play()
		end
	end
end

-- physical jumpscare lunge. LinearVelocity > raw CFrame snap.
function Monster:_lungeAt(targetPos: Vector3)
	if not self.rootAttach then return end

	local dir = (targetPos - self.root.Position)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit

	local flatTarget = Vector3.new(targetPos.X, self.root.Position.Y, targetPos.Z)
	self.root.CFrame = CFrame.lookAt(self.root.Position, flatTarget)

	local lunge = Instance.new("LinearVelocity")
	lunge.Attachment0            = self.rootAttach
	lunge.MaxForce               = cfg.lungeForce
	lunge.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lunge.RelativeTo             = Enum.ActuatorRelativeTo.World
	lunge.VectorVelocity         = dir * cfg.lungeSpeed
	lunge.Parent                 = self.root

	debris:AddItem(lunge, cfg.lungeDuration)
end


-- states that drive their own movement (humanoid handles rotation)
local movingStates: {[aiState]: true} = {
	Chase  = true, Patrol = true, Return = true, Stalk  = true, Toying = true,
}

-- per-state setup. dispatch table so adding a state = adding one entry.
local EnterInit: {[aiState]: (any) -> ()} = {}

function EnterInit.Chase(self)
	self.hum.WalkSpeed   = cfg.sprintSpd
	self:_setMoveAnim("Sprint")
	self.blindTime       = 0
	self.chaseTimer      = 0
	self.playerLookTimer = 0
end

function EnterInit.Patrol(self)
	self.hum.WalkSpeed = cfg.walkSpd + (math.random() - 0.5) * 2 * cfg.spdJitter
	self:_setMoveAnim("Walk")
end

function EnterInit.Return(self)
	self.hum.WalkSpeed = cfg.walkSpd
	self:_setMoveAnim("Walk")
end

function EnterInit.Stalk(self)
	self.hum.WalkSpeed   = cfg.stalkSpd
	self:_setMoveAnim("Walk")
	self.playerLookTimer = 0
	self.stalkDest       = nil
	self.stalkRecalc     = 0
end

function EnterInit.Toying(self)
	self.hum.WalkSpeed   = cfg.toyingSpd
	self:_setMoveAnim("Sprint")
	self.playerLookTimer = 0
	self.toyTimer        = 0
	self.toyingTotal     = 0
	self.toyReposTime    = math.random(cfg.toyReposMin, cfg.toyReposMax)
	self.toyDest         = nil
	self.toyPausing      = false
	self.toyPauseClock   = 0
end

function EnterInit.Idle(self)
	self.hum.WalkSpeed = 0
	self:_setMoveAnim("Idle")
end

function EnterInit.LookAround(self)
	self.hum.WalkSpeed = 0
	self:_setMoveAnim("Idle")
	self.scanAngle = 0
	self.scanClock = 0
end

function EnterInit.Jumpscare(self)
	self.hum.WalkSpeed = 0
	self:_stopAll()
	self.jumpscareFired = false
end


-- transition. common setup first, then per-state init
function Monster:_enter(newState: aiState)
	if self.state == newState then return end

	-- toying = ghostly fade
	if newState == "Toying" then
		self:_tweenTransparency(0.75)
	elseif self.state == "Toying" then
		self:_tweenTransparency(0)
	end

	self.prevState = self.state
	self:_setState(newState)
	self.timer = 0
	self:_syncSounds(newState)

	local moving = movingStates[newState] ~= nil

	-- AutoRotate only when humanoid is driving movement
	self.hum.AutoRotate = moving
	if self.alignOrient then
		self.alignOrient.Enabled = not moving
	end

	if moving then
		self.lastMoveDst = nil
	else
		self:_halt()
		self:_syncFacing()
	end

	local init = EnterInit[newState]
	if init then init(self) end
end


function Monster:_tickPlayerLook(dt: number): boolean
	if not self.target then return false end

	if self:_checkPlayerLooking(self.target) then
		self.playerLookTimer = self.playerLookTimer + dt
	else
		self.playerLookTimer = math.max(0, self.playerLookTimer - dt * 0.5)
	end

	return self.playerLookTimer >= cfg.playerLookTime
end


-- state dispatch table. one function per state.
type StateHandler = (self: any, dt: number, tRoot: BasePart?) -> ()
local Handlers: {[aiState]: StateHandler} = {}


function Handlers.Idle(self, dt: number, _tRoot: BasePart?)
	local reaction = self:_senseTargets()
	if reaction then
		self:_enter(reaction)
		return
	end

	if self.timer >= cfg.idleDur then
		self:_enter("Patrol")
	end
end


function Handlers.Patrol(self, dt: number, _tRoot: BasePart?)
	local reaction = self:_senseTargets()
	if reaction then
		self:_enter(reaction)
		return
	end

	if self.paused then
		if self.timer > self.pauseDur then
			self.paused      = false
			self.patrolClock = 0
			self.lastMoveDst = nil
			self:_stop("LookingAround")
			self.hum.AutoRotate = true
			if self.alignOrient then self.alignOrient.Enabled = false end
			self.hum.WalkSpeed  = cfg.walkSpd + (math.random() - 0.5) * 2 * cfg.spdJitter
			self:_setMoveAnim("Walk")
		end
	else
		if not self.destination then
			self.destination = self:_pickWaypoint()
		end

		self:_walkToward(self.destination, dt)

		if hDist(self.destination, self.root.Position) < 5 then
			self.destination  = self:_pickWaypoint()
			self.pathNodes    = nil
			self.pathBuiltFor = nil
			self.lastMoveDst  = nil
		end

		self.patrolClock = self.patrolClock + dt
		if self.patrolClock > 3 then
			if math.random() < cfg.pauseChance then
				self.paused   = true
				self.timer    = 0
				self.pauseDur = math.random(cfg.pauseMin, cfg.pauseMax)
				self:_halt()
				self.hum.AutoRotate = false
				if self.alignOrient then self.alignOrient.Enabled = true end
				self:_syncFacing()
				self.hum.WalkSpeed = 0
				self:_setMoveAnim("Idle")
				self:_play("LookingAround")
			end
			self.patrolClock = 0
		end
	end
end


function Handlers.Stalk(self, dt: number, tRoot: BasePart?)
	if self.target then
		local tChar  = self.target.Character
		local tRootS = tChar and tChar:FindFirstChild("HumanoidRootPart")
		if tRootS then
			self.lastSeenAt = tRootS.Position
		end
	end

	if self:_tickPlayerLook(dt) then
		self:_enter("Chase")
		return
	end

	local targetDist = math.huge
	if tRoot then
		targetDist = (tRoot.Position - self.root.Position).Magnitude
	end

	if targetDist < cfg.toyRadius then
		self:_enter("Toying")
		return
	end

	-- recompute stalk position every 2s as the target moves
	self.stalkRecalc = self.stalkRecalc + dt
	if not self.stalkDest or self.stalkRecalc >= 2 then
		self.stalkRecalc = 0
		if self.target then
			local newDest = self:_pickStalkPos(self.target)
			if newDest then
				self.stalkDest   = newDest
				self.pathNodes   = nil
				self.lastMoveDst = nil
			end
		end
	end

	if self.stalkDest then
		self:_walkToward(self.stalkDest, dt)
		if hDist(self.stalkDest, self.root.Position) < 5 then
			self.stalkDest = nil
		end
	elseif self.lastSeenAt then
		self:_walkToward(self.lastSeenAt, dt)
		if hDist(self.lastSeenAt, self.root.Position) < 5 then
			self:_enter("LookAround")
			self:_play("LookingAround")
		end
	end
end


-- darts around behind the player + occasional laugh. never jumpscares directly.
function Handlers.Toying(self, dt: number, tRoot: BasePart?)
	if not tRoot then self:_enter("LookAround") return end

	if self:_tickPlayerLook(dt) then
		self:_enter("Chase")
		return
	end

	self.toyingTotal = self.toyingTotal + dt
	if self.toyingTotal >= cfg.toyingMaxTime then
		self:_enter("Chase")
		return
	end

	local dist = (tRoot.Position - self.root.Position).Magnitude
	if dist > cfg.toyLoseDist then
		self:_enter("LookAround")
		return
	end

	local function startNewToyMove()
		self.toyPausing   = false
		self.toyTimer     = 0
		self.toyReposTime = math.random(cfg.toyReposMin, cfg.toyReposMax)

		local newSpot = self:_pickToyPos(self.target)

		-- sidestep if the route would cross the player's view
		if self.target and self.target.Character then
			if self:_pathCrossesFOV(self.target, self.root.Position, newSpot) then
				local pRootT = self.target.Character:FindFirstChild("HumanoidRootPart")
				if pRootT then
					local toNew    = (newSpot - pRootT.Position).Unit
					local sideStep = Vector3.new(-toNew.Z, 0, toNew.X)
					local testSpot = newSpot + sideStep * 20
					if not workspace:Raycast(newSpot + Vector3.new(0, 1, 0), (testSpot - newSpot).Unit * 20, self.rayParams) then
						newSpot = testSpot
					end
				end
			end
		end

		self.toyDest      = newSpot
		self.pathNodes    = nil
		self.pathBuiltFor = nil
		self.lastMoveDst  = nil
		self.hum.WalkSpeed = cfg.toyingSpd
		self:_setMoveAnim("Sprint")

		if math.random() < cfg.laughChance then self.sfx.laugh:Play() end
	end

	if not self.toyDest then
		startNewToyMove()
	elseif not self.toyPausing then
		self:_walkToward(self.toyDest, dt)
		if hDist(self.root.Position, self.toyDest) < 7 then
			if cfg.toyPauseMax <= 0 then
				startNewToyMove()
			else
				self.toyPausing    = true
				self.toyPauseClock = 0
				self.toyDest       = nil
				self:_halt()
			end
		end
	else
		self.toyPauseClock = self.toyPauseClock + dt
		self.toyTimer      = self.toyTimer + dt

		local exposed    = self:_isInPlayerFOV(self.target, self.root.Position)
		local shouldMove = self.toyTimer >= self.toyReposTime
			or self.toyPauseClock >= cfg.toyPauseMax or exposed

		if shouldMove then
			startNewToyMove()
		else
			self.hum.WalkSpeed = 0
			self:_setMoveAnim("Idle")
			if tRoot then self:_lookToward(tRoot.Position, dt) end
		end
	end
end


-- sprint at the target. only state that can trigger Jumpscare.
function Handlers.Chase(self, dt: number, tRoot: BasePart?)
	if not tRoot then
		self.target            = nil
		self.hearCooldownTimer = cfg.hearCooldown
		self:_enter("LookAround")
		return
	end

	self.chaseTimer = self.chaseTimer + dt

	local seen = self:_checkSight(self.target)
	local hasLOS = seen

	-- close-range raw ray so it doesn't lose you if you slip out of the cone
	if not hasLOS then
		local chaseDir = tRoot.Position - self.root.Position
		local distC    = chaseDir.Magnitude
		if distC < 30 then
			local hit = self:_castPiercing(self.root.Position, chaseDir.Unit * distC)
			if not hit or (hit.Position - self.root.Position).Magnitude >= distC * 0.95 then
				hasLOS = true
			end
		end
	end

	if hasLOS then
		self.lastSeenAt = tRoot.Position
		self.blindTime  = 0
		self.head.SpotLight.Enabled = true

		local distToTarget = (tRoot.Position - self.root.Position).Magnitude

		if distToTarget <= cfg.jumpscareReach and self.chaseTimer >= cfg.minChaseForScare then
			self.head.SpotLight.Enabled = false
			self:_enter("Jumpscare")
			return
		end

		self:_walkToward(tRoot.Position, dt)
	else
		-- run to last known pos for chaseMemory seconds
		self.blindTime = self.blindTime + dt
		self.head.SpotLight.Enabled = false

		if self.blindTime < cfg.chaseMemory and self.lastSeenAt then
			self:_walkToward(self.lastSeenAt, dt)
			if hDist(self.lastSeenAt, self.root.Position) < 5 then
				self.target            = nil
				self.hearCooldownTimer = cfg.hearCooldown
				self:_enter("LookAround")
			end
		else
			self.target            = nil
			self.hearCooldownTimer = cfg.hearCooldown
			self:_enter("LookAround")
		end
	end
end


function Handlers.LookAround(self, dt: number, _tRoot: BasePart?)
	if self.lastSeenAt then
		self:_lookToward(self.lastSeenAt, dt * 0.3)
	end
	self:_scanLook(dt)

	local reaction = self:_senseTargets()
	if reaction then
		self:_stop("LookingAround")
		self:_enter(reaction)
		return
	end

	local track = self.tracks["LookingAround"]
	if (track and not track.IsPlaying) or self.timer >= cfg.lookAroundMax then
		self.lastSeenAt = nil
		self:_stop("LookingAround")
		self:_enter("Return")
	end
end


function Handlers.Jumpscare(self, dt: number, _tRoot: BasePart?)
	if not self.jumpscareFired then
		self.jumpscareFired = true
		if self.target and self.target.Character then
			local tRJ = self.target.Character:FindFirstChild("HumanoidRootPart")
			if tRJ then
				self:_lungeAt(tRJ.Position)
			end
			local animId = if self.anims["Jumpscare"] then self.anims["Jumpscare"].AnimationId else ""
			jumpscareRemote:FireClient(self.target, animId)
		end
	end

	-- tiny delay so the lunge reads before the anim
	if self.timer >= 0.15 and not (self.tracks["Jumpscare"] and self.tracks["Jumpscare"].IsPlaying) then
		self:_play("Jumpscare", 0.05)
	end

	if self.timer > 2.5 then
		self.target = nil
		self:_stopAll()
		self:_enter("Return")
	end
end


function Handlers.Return(self, dt: number, _tRoot: BasePart?)
	local reaction = self:_senseTargets()
	if reaction then
		self:_enter(reaction)
		return
	end

	if not self.destination then
		local nearest  = self.waypoints[1]
		local bestDist = math.huge
		for _, wp in self.waypoints do
			local d = (wp.Position - self.root.Position).Magnitude
			if d < bestDist then nearest = wp; bestDist = d end
		end
		self.destination = nearest.Position
	end

	self:_walkToward(self.destination, dt)

	if hDist(self.destination, self.root.Position) < 4 then
		self:_enter("Idle")
	end
end


-- heartbeat loop. global ticks + dispatch to active handler.
function Monster:update(dt: number)
	self.timer = self.timer + dt
	self:_tickBreathing(dt)

	if self.hearCooldownTimer > 0 then
		self.hearCooldownTimer = math.max(0, self.hearCooldownTimer - dt)
	end

	-- 4Hz proximity broadcast
	self.netClock = self.netClock + dt
	if self.netClock > 0.25 then
		self:_broadcastProximity()
		self.netClock = 0
	end

	local tRoot = nil
	if self.target and self.target.Character then
		tRoot = self.target.Character:FindFirstChild("HumanoidRootPart")
	end

	if tRoot and (self.state == "Chase" or self.state == "Stalk" or self.state == "Toying") then
		self:_trackHead(tRoot.Position, dt)
	else
		self:_trackHead(nil, dt)
	end

	local handler = Handlers[self.state]
	if handler then
		handler(self, dt, tRoot)
	end
end


-- entry point. waypoints come from CollectionService tags so streaming + level
-- editing stay painless.
local function init()
	local wps: {BasePart} = {}

	for _, part in collectionService:GetTagged("MonsterWaypoint") do
		if part:IsA("BasePart") and part:IsDescendantOf(workspace) then
			table.insert(wps, part)
		end
	end

	if #wps == 0 then
		warn("[MonsterAI] no parts tagged 'MonsterWaypoint' found in workspace")
		return
	end

	-- random spawn waypoint so each round feels different
	local spawnWp = wps[math.random(1, #wps)]
	local spawnCF = CFrame.new(spawnWp.Position + Vector3.new(0, 3, 0))
	local monster = Monster.new(spawnCF, wps)

	print(tostring(monster))

	task.spawn(function()
		while monster.model.Parent and monster.hum.Health > 0 do
			local step = runService.Heartbeat:Wait()
			monster:update(step)
		end
	end)
end

init()
