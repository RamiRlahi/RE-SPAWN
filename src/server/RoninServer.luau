--!strict
--[[
	RoninServer.luau
	Server side of the Ronin (client: RoninController). A katana kept in its
	scabbard in the left hand: every skill is a draw. Hits land on the beats
	of the baked moves (RoninMoves.events), so the damage meets the blade.

	  M1 Edge       three quick cuts, upper body only (you keep moving).
	  E  Distant Cut
	                a quick-draw at range: the cuts land on the cursor (a
	                sphere of slashes) the moment the blade clicks home.
	  F  Rising Cut held: he coils into the draw and charges through three
	                stages; let go: a crescent rolls out, further, harder and
	                wider each stage.
	  Q  Falling Heaven
	                leap, two cross-cuts and a spin cut in the air, then a
	                front flip into a downward cut that drives everything
	                under him into the floor.
	  R  Thousand Cuts
	                stillness, a held draw, a storm of cuts over everything
	                near; the slow sheathe; the click: every cut lands at once.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RoninLook = require(Shared:WaitForChild("RoninLook"))
local RoninMoves = require(Shared:WaitForChild("RoninMoves")) :: any
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local RoninServer = {}

-- ── Tuning (mirrored in RoninController) ─────────────────────────────────────
local LEAD = 0.1 -- the blend into each move's first frame (RoninController)
local COMBO_RESET = 1.2
local COMBO = {
	-- range, minimum facing dot, damage, when it lands, when the next may start
	[1] = { range = 10, dot = 0.2, damage = 28, land = 0.14, free = 0.36 },
	[2] = { range = 10, dot = 0.2, damage = 28, land = 0.14, free = 0.36 },
	[3] = { range = 11, dot = 0.1, damage = 46, land = 0.2, free = 0.6, heavy = true },
}

-- Rising Cut is charged (the key held): stage 2 after RISE.stage2 seconds,
-- stage 3 (full) after RISE.stage3; let go by itself RISE.still after full.
-- He holds the coiled draw (baked frame RISE.from) while it charges; the
-- release plays the rest, its cut landing RISE_SLASH after the key comes up.
local RISE = { stage2 = 0.55, stage3 = 1.2, still = 0.8, from = 6 }
local RISE_SCALE = {
	{ range = 1, damage = 1, half = 1 },
	{ range = 1.35, damage = 1.7, half = 1.25 },
	{ range = 1.8, damage = 2.8, half = 1.6 },
}

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = { step: number, lastSwing: number, busyUntil: number, token: number,
	rising: { t0: number, config: any, token: {} }?, pendingRelease: { at: number, held: number?, dir: Vector3? }? }

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { step = 0, lastSwing = 0, busyUntil = 0, token = 0 }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.RoninFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function move(key: string): any
	return RoninMoves[key]
end

-- When `beat` of `key` lands, in seconds from the cast.
local function beat(key: string, name: string): number
	return LEAD + ((move(key).events :: any)[name] or 0)
end

local function inRadius(char: Model, origin: Vector3, dir: Vector3, range: number, minDot: number, height: number?): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - origin
		local fd = Vector3.new(d.X, 0, d.Z)
		if fd.Magnitude <= range and math.abs(d.Y) < (height or (range + 6)) then
			if minDot <= -1 or fd.Magnitude < 3 or dir:Dot(fd.Unit) >= minDot then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function strike(player: Player, hits: { Target }, damage: number, source: string): number
	local landed = 0
	for _, t in ipairs(hits) do
		if t.humanoid.Health > 0 and H.dealDamage(player, t, damage, source) then landed += 1 end
	end
	return landed
end

-- Runs `fn` at `t` seconds unless a newer move (or a respawn) took over.
local function at(st: State, char: Model, t: number, fn: () -> ())
	local token = st.token
	task.delay(t, function()
		if st.token ~= token or not char.Parent then return end
		local ok, err = pcall(fn)
		if not ok then warn("[RoninServer]", err) end
	end)
end

-- ── M1: Edge ────────────────────────────────────────────────────────────────
function RoninServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1)
	local prev = COMBO[st.step]
	if prev and now - st.lastSwing < (prev.free / speed) * 0.85 then return end
	st.step = if now - st.lastSwing > COMBO_RESET or st.step >= #COMBO then 1 else st.step + 1
	st.lastSwing = now
	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local c: any = COMBO[st.step]
	local step = st.step
	local damage = c.damage * stat(player, "damage")
	local size = stat(player, "size")
	fx({ kind = "m1", attacker = player, step = step, dir = dir })
	task.delay(c.land / speed, function()
		if not char.Parent or not root.Parent then return end
		strike(player, inRadius(char, root.Position, dir, c.range * size, c.dot), damage, if c.heavy then "RONIN FINISH" else "RONIN CUT")
	end)
end

-- ── Skills ──────────────────────────────────────────────────────────────────
local function distantCut(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any, aimAt: Vector3?)
	local range = config.range or 40
	local radius = (config.radius or 9) * (config.areaMultiplier or stat(player, "size"))
	local damage = (config.damage or 45) * stat(player, "damage")
	local from = root.Position
	local pos = from + dir * math.min(range, 20)
	if aimAt then
		local d = Vector3.new(aimAt.X - from.X, 0, aimAt.Z - from.Z)
		pos = Vector3.new(from.X, aimAt.Y, from.Z) + (if d.Magnitude > range then d.Unit * range else d)
	end
	local total = LEAD + move("rangedCut").length
	st.busyUntil = os.clock() + total
	fx({ kind = "move", move = "rangedCut", attacker = player, dir = dir, pos = pos, radius = radius })
	-- the click: the cuts keep falling on the spot for the whole flurry, five
	-- bursts (RoninController DISTANT_FLURRY / DISTANT_BURSTS). Once the blade's
	-- clicked home they're out there: a next move doesn't call them off.
	local click = beat("rangedCut", "click_cuts")
	local FLURRY, BURSTS = 0.9, 5
	at(st, char, click, function()
		for i = 0, BURSTS - 1 do
			task.delay(i * FLURRY / (BURSTS - 1), function()
				if not char.Parent then return end
				strike(player, inRadius(char, pos, dir, radius, -1, radius + 4), damage, "DISTANT CUT")
			end)
		end
	end)
end

-- The release, at `stage` (1-3): the cut reaches further, hits harder and
-- is wider each stage.
local function risingCut(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any, stage: number)
	local S = RISE_SCALE[stage] or RISE_SCALE[1]
	local area = config.areaMultiplier or stat(player, "size")
	local range = (config.range or 20) * area * S.range
	local damage = (config.damage or 80) * stat(player, "damage") * S.damage
	local fps = RoninMoves.fps
	local releaseLen = move("risingCut").length - RISE.from / fps
	local slashAt = LEAD + (move("risingCut").events :: any).slash_up - RISE.from / fps
	st.busyUntil = os.clock() + LEAD + releaseLen
	fx({ kind = "move", move = "risingCut_release", attacker = player, dir = dir, radius = range, stage = stage })
	-- (a thick crescent that rolls forward `range` studs from just ahead of him and
	-- fades: RoninController RISING_LIFE. It hits whatever it passes over, once each)
	local from = root.Position
	local seen: { [Model]: boolean } = {}
	local SLASH_TRAVEL, SLASH_HALF = 0.5 + 0.08 * (stage - 1), 8 * area * S.half
	for i = 0, 4 do
		at(st, char, slashAt + SLASH_TRAVEL * i / 4, function()
			local k = 1 - (1 - i / 4) ^ 2 -- (eases out, as it's drawn)
			local c = from + dir * (3 + range * k)
			local hits = {}
			for _, t in ipairs(inRadius(char, c, dir, SLASH_HALF, -1, 6)) do
				if not seen[t.character] then
					seen[t.character] = true
					table.insert(hits, t)
				end
			end
			strike(player, hits, damage, if stage >= 3 then "RISING CUT!!" elseif stage == 2 then "RISING CUT!" else "RISING CUT")
		end)
	end
end

-- The key came up (or it let go by itself): `held` is how long the client says
-- it was down (never more than the server has seen), `aim` where the cut goes.
local function risingRelease(player: Player, held: number?, aim: Vector3?)
	local st = getState(player)
	local r = st.rising
	if not r then return end
	st.rising = nil
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and root) then
		st.busyUntil = 0
		return
	end
	local elapsed = os.clock() - r.t0
	local h = math.clamp(tonumber(held) or elapsed, 0, elapsed + 0.15)
	local stage = if h >= RISE.stage3 then 3 elseif h >= RISE.stage2 then 2 else 1
	local dir = flat(if typeof(aim) == "Vector3" then aim else root.CFrame.LookVector)
	risingCut(player, char, st, root, dir, r.config, stage)
end

-- The cast: he coils into the draw and charges until the key comes up.
local function risingStart(player: Player, st: State, config: any)
	local now = os.clock()
	local token = {}
	st.rising = { t0 = now, config = config, token = token }
	st.busyUntil = now + RISE.stage3 + RISE.still + 1
	fx({ kind = "risingCharge", attacker = player })
	-- (a release that got here ahead of the cast: a tap)
	local pend = st.pendingRelease
	st.pendingRelease = nil
	if pend and now - pend.at < 0.6 then
		risingRelease(player, pend.held, pend.dir)
		return
	end
	-- (never let go: it goes by itself, a little grace for the client's own)
	task.delay(RISE.stage3 + RISE.still + 0.15, function()
		local r = st.rising
		if r and r.token == token then risingRelease(player, RISE.stage3 + RISE.still, nil) end
	end)
end

local function fallingHeaven(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local radius = (config.radius or 12) * (config.areaMultiplier or stat(player, "size"))
	local damage = (config.damage or 35) * stat(player, "damage")
	st.busyUntil = os.clock() + LEAD + move("airCut").length
	fx({ kind = "move", move = "airCut", attacker = player, dir = dir })
	-- the air cuts land round him where he is (his body is the client's: it replicates)
	for _, name in ipairs({ "slash_h", "slash_h2", "slash_spin", "slash_down" }) do
		at(st, char, beat("airCut", name), function()
			local c = root.Position + dir * 3
			strike(player, inRadius(char, c, dir, 9, -1, 9), damage, "AIR CUT")
		end)
	end
	-- the landing: everything under him driven into the floor
	at(st, char, beat("airCut", "impact"), function()
		local c = root.Position + dir * 3
		fx({ kind = "impact", attacker = player, pos = c, radius = radius })
		strike(player, inRadius(char, c, dir, radius, -1, 10), damage * 3.2, "HEAVEN FALL")
	end)
end

-- Time stops for whatever's caught in the ult: held where it stands (anchored),
-- every animation it plays paused (and any it starts while held), its AI
-- turns skipped (StaggerUntil). Never players. All of it back as it was at `untilT`.
type Held = { root: BasePart, wasAnchored: boolean, animator: Animator?, speeds: { [AnimationTrack]: number } }
local function timeStop(targets: { Target }, held: { [Model]: Held }, untilT: number)
	for _, t in ipairs(targets) do
		local m = t.character
		if held[m] or Players:GetPlayerFromCharacter(m) or t.humanoid.Health <= 0 then continue end
		local animator = t.humanoid:FindFirstChildOfClass("Animator")
		local h: Held = { root = t.rootPart, wasAnchored = t.rootPart.Anchored, animator = animator, speeds = {} }
		held[m] = h
		pcall(function() t.humanoid:Move(Vector3.zero) end)
		t.rootPart.AssemblyLinearVelocity = Vector3.zero
		t.rootPart.Anchored = true
		m:SetAttribute("StaggerUntil", math.max(tonumber(m:GetAttribute("StaggerUntil")) or 0, untilT))
		m:SetAttribute("TimeStopped", true)
	end
	-- (the animations: paused now and kept paused, new ones included)
	for m, h in pairs(held) do
		if not m.Parent or not h.animator then continue end
		for _, track in ipairs(h.animator:GetPlayingAnimationTracks()) do
			if h.speeds[track] == nil then
				h.speeds[track] = track.Speed
				track:AdjustSpeed(0)
			end
		end
	end
end
local function timeResume(held: { [Model]: Held })
	for m, h in pairs(held) do
		if m.Parent then
			if h.root.Parent and not h.wasAnchored then h.root.Anchored = false end
			for track, speed in pairs(h.speeds) do
				if track.IsPlaying then track:AdjustSpeed(speed) end
			end
			m:SetAttribute("TimeStopped", nil)
		end
	end
	table.clear(held)
end

local function thousandCuts(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local radius = (config.radius or 30) * (config.areaMultiplier or stat(player, "size"))
	local damage = (config.damage or 300) * stat(player, "damage")
	local center = root.Position
	st.busyUntil = os.clock() + LEAD + move("finisher").length
	char:SetAttribute("InvulnerableUntil", os.clock() + LEAD + move("finisher").length)
	fx({ kind = "move", move = "finisher", attacker = player, dir = dir, pos = center, radius = radius })
	-- everything in reach is caught from the freeze to just after the click
	local held: { [Model]: Held } = {}
	local freezeAt = beat("finisher", "freeze")
	local resumeAt = beat("finisher", "click_finish") + 0.25
	local untilT = os.clock() + resumeAt
	local stopped = false
	task.delay(freezeAt, function()
		if not char.Parent then return end
		stopped = true
		-- (re-checked as it runs: anything walking in is caught too, new animations paused)
		task.spawn(function()
			while stopped and char.Parent do
				timeStop(inRadius(char, center, dir, radius, -1, 16), held, untilT)
				task.wait(0.15)
			end
		end)
	end)
	task.delay(resumeAt, function()
		stopped = false
		timeResume(held)
	end)
	-- the storm: four quick waves of cuts over everything near
	local storm = beat("finisher", "slash_storm")
	for i = 0, 3 do
		at(st, char, storm + i * 0.09, function()
			strike(player, inRadius(char, center, dir, radius, -1, 14), damage * 0.06, "SWORD STORM")
		end)
	end
	-- the click: every cut lands at once
	at(st, char, beat("finisher", "click_finish"), function()
		strike(player, inRadius(char, center, dir, radius, -1, 16), damage, "THOUSAND CUTS")
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function RoninServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function RoninServer.OnSkill(player: Player, char: Model, skillIndex: number, _origin: Vector3, dir: Vector3, config: any, aimAt: Vector3?)
	local st = getState(player)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	dir = flat(dir)
	st.token += 1
	if skillIndex == 1 then
		distantCut(player, char, st, root, dir, config, aimAt)
	elseif skillIndex == 2 then
		risingStart(player, st, config)
	elseif skillIndex == 3 then
		fallingHeaven(player, char, st, root, dir, config)
	elseif skillIndex == 4 then
		thousandCuts(player, char, st, root, dir, config)
	end
end

-- (the ult's opening: the stillness and the held draw, before the storm)
RoninServer.ULT_WINDUP = LEAD + ((RoninMoves.finisher.events :: any).slash_storm or 1.3)

function RoninServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil = 0, 0, 0
	st.rising, st.pendingRelease = nil, nil
	st.token += 1
end

-- ── The scabbard on the real character ──────────────────────────────────────
local function refresh(p: Player, char: Model)
	if p:GetAttribute("SelectedClass") ~= "ronin" then
		RoninLook.RemoveScabbard(char)
		return
	end
	task.defer(function()
		if not char.Parent or not char:WaitForChild("Left Arm", 5) then return end
		if p.Character ~= char or p:GetAttribute("SelectedClass") ~= "ronin" then return end
		if not char:FindFirstChild("RoninScabbard") then RoninLook.AttachScabbard(char) end
	end)
end

function RoninServer.Init(helpers: any)
	-- (a dash cuts the move short: free to act again, and what was left of it doesn't land)
	(require(script.Parent:WaitForChild("Dash")) :: any).OnDash(function(p: Player)
		local st = states[p] :: any
		if not st then return end
		st.busyUntil = 0
		st.rising = nil -- (a charge dashed out of: no cut)
		if type(st.token) == "number" then st.token += 1 end
	end)
	H = helpers
	-- The Rising Cut's key let go.
	Network.GetRemoteEvent(Network.Remotes.RoninInput).OnServerEvent:Connect(function(player: Player, msg: any)
		if typeof(msg) ~= "table" or msg.kind ~= "release" then return end
		local held = tonumber(msg.held)
		local dir = if typeof(msg.dir) == "Vector3" then msg.dir :: Vector3 else nil
		local st = getState(player)
		if st.rising then
			risingRelease(player, held, dir)
		else
			st.pendingRelease = { at = os.clock(), held = held, dir = dir }
		end
	end)
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function(c)
			if p:GetAttribute("SelectedClass") == "ronin" then RoninServer.Reset(p) end
			refresh(p, c)
		end)
		p:GetAttributeChangedSignal("SelectedClass"):Connect(function()
			if p.Character then refresh(p, p.Character) end
		end)
		if p.Character then refresh(p, p.Character) end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
end

return RoninServer
