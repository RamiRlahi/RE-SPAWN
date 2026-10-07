--!strict
--[[
	RogueServer.luau
	Server side of the Rogue, "The Shadow" (client: RogueController). Every
	hit and all state is decided here; clients get the moments to draw over
	RogueFX.

	  M1 Dagger Combo   quick 3-hit chain (two slashes, then a stab).
	  Passive           Shadow Energy: damage dealt fills it (RG_Energy, 0-100).
	                    At full, the next ability uses it up and is Enhanced.
	                    Also: Shadow-Marked enemies take +25% from the Rogue,
	                    a kill gives +25% move speed for 2 s, and cooldowns
	                    recharge twice as fast while invisible.
	  E Shadow Dagger   a thrown dagger: it sticks in the first enemy it hits
	                    (Marking it) or wherever it stops. Pressing E again
	                    while it's out is SHADOW STEP: you appear at the dagger,
	                    behind the enemy it's stuck in, with a bonus backstab.
	                    The step costs no cooldown and works while invisible.
	                    Enhanced: pierces every enemy in the line.
	  F Dash            an instant dash: every enemy in the path is cut and
	                    Marked. Enhanced: longer and harder.
	  Q Invisibility    6 s unseen ("Hidden": mobs lose you), faster. Attacking
	                    or taking damage ends it. Enhanced: 9 s.
	  R Shadow Realm    4 s untargetable in the shadow realm while slashes
	                    cut every enemy round you ten times a second, then a
	                    burst that hits and Marks everything near. Enhanced:
	                    longer, harder.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local RogueLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RogueLook"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local RogueServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local SWING_INTERVAL = 0.26  -- seconds between combo hits at 1× attack speed
local COMBO_RESET = 0.9
local COMBO = {
	[1] = { range = 18, dot = 0.25, damage = 15, source = "DAGGER" },
	[2] = { range = 18, dot = 0.25, damage = 15, source = "DAGGER" },
	[3] = { range = 22, dot = 0.7, damage = 24, source = "DAGGER STAB" },
}
local ENERGY_MAX = 100
local ENERGY_PER_HIT = 5
local MARK_TIME = 5          -- seconds a Shadow Mark lasts
local MARK_BONUS = 0.25      -- +25% damage from the Rogue to a marked enemy
local KILL_SPEED = 1.25      -- move speed after a kill…
local KILL_SPEED_TIME = 2    -- …for this long
local HIDDEN_SPEED = 1.3     -- move speed while invisible
local STEP_BONUS = 1.6       -- Shadow Step backstab: × the dagger's damage
local REALM_TICK = 0.1       -- seconds between Shadow Realm slash waves (each cuts every enemy in range)
local REALM_ENERGY = 2       -- Shadow Energy per wave that lands (per hit, the realm would refill it at once)
local REALM_BURST = 9        -- the closing burst: × a slash's damage

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type Dagger = { pos: Vector3, stuck: Target?, expires: number, landsAt: number, damage: number }
type State = {
	step: number,
	lastSwing: number,
	energy: number,
	dagger: Dagger?,
	hiddenUntil: number,
	hiddenToken: number,
	speedUntil: number,
	realmUntil: number,
	busyUntil: number,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { step = 0, lastSwing = 0, energy = 0, dagger = nil, hiddenUntil = 0, hiddenToken = 0,
			speedUntil = 0, realmUntil = 0, busyUntil = 0 }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.RogueFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

-- ── Shadow Energy ───────────────────────────────────────────────────────────
local function setEnergy(player: Player, st: State, v: number)
	st.energy = math.clamp(v, 0, ENERGY_MAX)
	player:SetAttribute("RG_Energy", st.energy)
end

local function gain(player: Player, st: State, n: number)
	local before = st.energy
	setEnergy(player, st, st.energy + n)
	if before < ENERGY_MAX and st.energy >= ENERGY_MAX then
		fx({ kind = "energyFull", attacker = player })
	end
end

-- At full energy the ability eats it all and is Enhanced.
local function consume(player: Player, st: State): boolean
	if st.energy < ENERGY_MAX then return false end
	setEnergy(player, st, 0)
	return true
end

-- ── Speed (invisible, after a kill) ─────────────────────────────────────────
local function refreshSpeed(player: Player, st: State)
	local char = player.Character
	if not char then return end
	local now = os.clock()
	local m = 1
	if now < st.hiddenUntil then m = math.max(m, HIDDEN_SPEED) end
	if now < st.speedUntil then m = math.max(m, KILL_SPEED) end
	char:SetAttribute("SpeedMult", if m > 1 then m else nil)
end

-- ── Marks and hits ──────────────────────────────────────────────────────────
local function marked(t: Target): boolean
	return (t.character:GetAttribute("ShadowMarkUntil") or 0) > os.clock()
end

local function mark(t: Target, seconds: number?)
	local dur = seconds or MARK_TIME
	t.character:SetAttribute("ShadowMarkUntil", os.clock() + dur)
	fx({ kind = "mark", model = t.character, duration = dur })
end

-- One hit from the Rogue: the mark's bonus, energy (`energy`, or the usual
-- per hit), the speed on a kill. (`damage` already carries the Damage stat:
-- skill configs come scaled.)
local function hit(player: Player, st: State, t: Target, damage: number, source: string, opts: any?, energy: number?): number?
	if t.humanoid.Health <= 0 then return nil end
	local amount = damage
	if marked(t) then amount *= 1 + MARK_BONUS end
	local dealt = H.dealDamage(player, t, amount, source, opts)
	if dealt then
		gain(player, st, energy or ENERGY_PER_HIT)
		if t.humanoid.Health <= 0 then
			st.speedUntil = os.clock() + KILL_SPEED_TIME
			refreshSpeed(player, st)
			task.delay(KILL_SPEED_TIME + 0.05, refreshSpeed, player, st)
		end
	end
	return dealt
end

-- ── Hit shapes ──────────────────────────────────────────────────────────────
local function inArc(char: Model, origin: Vector3, dir: Vector3, range: number, minDot: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - origin
		local fd = Vector3.new(d.X, 0, d.Z)
		if fd.Magnitude <= range and (minDot <= -1 or fd.Magnitude < 3 or dir:Dot(fd.Unit) >= minDot) then
			table.insert(out, t)
		end
	end
	return out
end

-- Enemies along a line, nearest first, with how far along each one is.
local function onLine(char: Model, from: Vector3, dir: Vector3, length: number, width: number): { { t: Target, along: number } }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - from
		local along = Vector3.new(d.X, 0, d.Z):Dot(dir)
		if along >= -1 and along <= length + 1.5 then
			local closest = from + dir * along
			if Vector3.new(t.rootPart.Position.X - closest.X, 0, t.rootPart.Position.Z - closest.Z).Magnitude <= width then
				table.insert(out, { t = t, along = along })
			end
		end
	end
	table.sort(out, function(a, b) return a.along < b.along end)
	return out
end

-- How far a thrown / dashed line goes before a wall.
local function clearDistance(char: Model, from: Vector3, dir: Vector3, length: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { char }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local res = Workspace:Raycast(from + Vector3.new(0, 1.5, 0), dir * length, params)
	return if res then math.max(1, res.Distance - 1) else length
end

-- ── Invisibility ────────────────────────────────────────────────────────────
local function endHidden(player: Player, st: State, why: string?)
	if st.hiddenUntil <= 0 then return end
	st.hiddenUntil = 0
	st.hiddenToken += 1
	local char = player.Character
	if char and os.clock() >= st.realmUntil then char:SetAttribute("Hidden", nil) end
	refreshSpeed(player, st)
	fx({ kind = "hidden", attacker = player, on = false, why = why })
end

local function startHidden(player: Player, char: Model, st: State, seconds: number)
	st.hiddenUntil = os.clock() + seconds
	st.hiddenToken += 1
	local token = st.hiddenToken
	char:SetAttribute("Hidden", true)
	refreshSpeed(player, st)
	fx({ kind = "hidden", attacker = player, on = true, duration = seconds })
	-- While unseen, the other abilities recharge twice as fast.
	task.spawn(function()
		while st.hiddenToken == token and os.clock() < st.hiddenUntil do
			task.wait(0.5)
			if st.hiddenToken ~= token then return end
			for i = 1, 4 do
				if i ~= 3 and H.cooldownLeft(player, i) > 0 then H.reduceCooldown(player, i, 0.5) end
			end
		end
		if st.hiddenToken == token then endHidden(player, st, "time") end
	end)
end

-- Any attack from the Rogue (not the Shadow Step) breaks invisibility.
local function attacked(player: Player, st: State)
	if st.hiddenUntil > 0 then endHidden(player, st, "attack") end
end

-- ── M1: Dagger Combo ────────────────────────────────────────────────────────
function RogueServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1)
	if now - st.lastSwing < SWING_INTERVAL / speed - 0.05 then return end
	st.step = if now - st.lastSwing > COMBO_RESET then 1 else (st.step % 3) + 1
	st.lastSwing = now
	attacked(player, st)
	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local c = COMBO[st.step]
	local size = stat(player, "size")
	for _, t in ipairs(inArc(char, root.Position, dir, c.range * size, c.dot)) do
		hit(player, st, t, c.damage * stat(player, "damage"), c.source)
	end
	fx({ kind = "combo", attacker = player, step = st.step, dir = dir })
end

-- ── E: Shadow Dagger (and its Shadow Step) ──────────────────────────────────
local function throwDagger(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, config: any, enhanced: boolean)
	attacked(player, st)
	local range = (config.range or 40) * (if enhanced then 1.2 else 1)
	local speed = config.projectileSpeed or 110
	local length = clearDistance(char, origin, dir, range)
	local width = 2.6 * (config.areaMultiplier or 1)
	local damage = (config.damage or 34) * (if enhanced then 1.4 else 1)
	local life = config.duration or 4
	-- The picture starts on a guess (the first enemy on the line now); the
	-- flight below decides, and corrects the clients if it differs.
	local line = onLine(char, origin, dir, length, width)
	local guess: Target? = if not enhanced and #line > 0 then line[1].t else nil
	local guessAt = if guess then math.max(1, line[1].along) else length
	local mine: Dagger = { pos = origin + dir * guessAt, stuck = nil, landsAt = math.huge, expires = math.huge, damage = damage }
	st.dagger = mine
	fx({ kind = "dagger", attacker = player, from = origin, to = mine.pos, stuck = guess and guess.character,
		travel = guessAt / speed, life = life, enhanced = enhanced })

	-- The flight: it really travels the line, and the first body it reaches
	-- stops it (enhanced: it cuts through every one on the way). Judged as
	-- it flies, not where everyone stood when it was thrown: a mob stepping
	-- into its path, or a big one whose body (not its middle) is in the way,
	-- stops it too.
	local reach: { [Model]: number } = {}
	local struck: { [Model]: boolean } = {}
	local function land(at: number, on: Target?)
		mine.pos = origin + dir * at
		mine.stuck = on
		mine.landsAt = os.clock()
		mine.expires = os.clock() + life
		if on ~= guess or math.abs(at - guessAt) > 3 then
			fx({ kind = "daggerStop", attacker = player, to = mine.pos, stuck = on and on.character })
		end
		-- (gone when it expires unless stepped to)
		task.delay(life, function()
			if st.dagger == mine then
				st.dagger = nil
				fx({ kind = "daggerGone", attacker = player })
			end
		end)
	end
	task.spawn(function()
		local flown = 0
		while flown < length do
			local dt = RunService.Heartbeat:Wait()
			if not char.Parent or st.dagger ~= mine then return end -- (gone, or thrown again)
			local from = flown
			flown = math.min(length, flown + speed * dt)
			-- every enemy whose body this stretch of the flight passes through, nearest first
			local passed: { { t: Target, along: number } } = {}
			for _, t in ipairs(H.getPotentialTargets(char)) do
				if struck[t.character] then continue end
				local d = t.rootPart.Position - origin
				local along = Vector3.new(d.X, 0, d.Z):Dot(dir)
				local r = reach[t.character]
				if not r then
					r = H.lineReach(t, width)
					reach[t.character] = r
				end
				if along >= from - r and along <= flown + r then
					local c = origin + dir * math.clamp(along, from, flown)
					if Vector3.new(t.rootPart.Position.X - c.X, 0, t.rootPart.Position.Z - c.Z).Magnitude <= r then
						table.insert(passed, { t = t, along = math.max(1, along) })
					end
				end
			end
			table.sort(passed, function(a, b) return a.along < b.along end)
			for _, e in ipairs(passed) do
				struck[e.t.character] = true
				hit(player, st, e.t, damage, "SHADOW DAGGER")
				mark(e.t, if enhanced then MARK_TIME * 1.5 else MARK_TIME)
				if not enhanced then
					land(math.min(e.along, flown), e.t)
					return
				end
			end
		end
		land(length, nil)
	end)
end

-- Where the Shadow Step lands: behind the enemy the dagger is stuck in (on
-- the far side from the Rogue), or on the dagger.
local function stepSpot(st: State, char: Model): (Vector3?, Target?)
	local d = st.dagger
	if not d then return nil, nil end
	local s = d.stuck
	if s and s.character.Parent and s.humanoid.Health > 0 then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local away = if root then flat(s.rootPart.Position - root.Position) else flat(s.rootPart.CFrame.LookVector)
		return s.rootPart.Position + away * 3.5, s
	end
	return d.pos, nil
end

-- E pressed again while a dagger is out: Shadow Step. Returns true when it
-- was (so SkillManager skips the cooldown).
function RogueServer.TryRecast(player: Player, char: Model, skillIndex: number): boolean
	if skillIndex ~= 1 then return false end
	local st = getState(player)
	local d = st.dagger
	if not d or os.clock() > d.expires then return false end
	if os.clock() < d.landsAt - 0.1 then return true end -- (still in the air: swallow the press)
	local to, target = stepSpot(st, char)
	st.dagger = nil
	if not to then return true end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local from = if root then root.Position else to
	fx({ kind = "step", attacker = player, from = from, to = to, target = target and target.character })
	if target then
		-- The backstab: the dagger's damage again and more, always a crit.
		task.delay(0.05, function()
			if char.Parent then
				hit(player, st, target, d.damage * STEP_BONUS, "SHADOW STEP", { forceCrit = true })
				mark(target)
			end
		end)
	end
	return true
end

-- Whether the client should treat E as a Shadow Step right now.
function RogueServer.HasDagger(player: Player): boolean
	local d = getState(player).dagger
	return d ~= nil and os.clock() <= d.expires
end

-- ── F: Dash ─────────────────────────────────────────────────────────────────
local function dash(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, config: any, enhanced: boolean)
	attacked(player, st)
	local dist = clearDistance(char, origin, dir, (config.dashDistance or 22) * (if enhanced then 1.5 else 1))
	local width = (config.width or 5) * (config.areaMultiplier or 1) * (if enhanced then 1.3 else 1)
	local damage = (config.damage or 30) * (if enhanced then 1.5 else 1)
	char:SetAttribute("InvulnerableUntil", os.clock() + 0.3)
	fx({ kind = "dash", attacker = player, from = origin, to = origin + dir * dist, enhanced = enhanced })
	task.delay(0.04, function()
		if not char.Parent then return end
		for _, e in ipairs(onLine(char, origin, dir, dist, width)) do
			hit(player, st, e.t, damage, "DASH")
			mark(e.t)
		end
	end)
end

-- ── R: Shadow Realm ─────────────────────────────────────────────────────────
local function realm(player: Player, char: Model, st: State, config: any, enhanced: boolean)
	endHidden(player, st, "realm")
	local dur = (config.duration or 4) * (if enhanced then 1.5 else 1)
	local range = (config.range or 24) * (config.areaMultiplier or 1)
	local damage = (config.damage or 26) * (if enhanced then 1.4 else 1)
	st.realmUntil = os.clock() + dur
	st.busyUntil = st.realmUntil
	char:SetAttribute("Hidden", true)
	char:SetAttribute("InvulnerableUntil", st.realmUntil + 0.2)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local center = if root then root.Position else Vector3.zero
	fx({ kind = "realm", attacker = player, pos = center, duration = dur, range = range, enhanced = enhanced })
	task.spawn(function()
		while os.clock() < st.realmUntil and char.Parent do
			task.wait(REALM_TICK)
			local r = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not r then break end
			-- Every wave cuts every enemy in range (a damage number each); the
			-- cuts drawn over them are budgeted.
			local landed = false
			for _, t in ipairs(inArc(char, r.Position, Vector3.zero, range, -1)) do
				if hit(player, st, t, damage, "SHADOW REALM", nil, 0) then
					landed = true
					if H.fxAllowed(player, "realmSlash", 14) then
						fx({ kind = "realmSlash", attacker = player, pos = t.rootPart.Position })
					end
				end
			end
			if landed then gain(player, st, REALM_ENERGY) end
		end
		if not char.Parent then return end
		-- The burst: everything near takes a heavy hit and is Marked.
		local r = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local at = if r then r.Position else center
		fx({ kind = "realmBurst", attacker = player, pos = at, range = range })
		for _, t in ipairs(inArc(char, at, Vector3.zero, range, -1)) do
			hit(player, st, t, damage * REALM_BURST, "SHADOW BURST")
			mark(t)
		end
		if st.hiddenUntil <= 0 then char:SetAttribute("Hidden", nil) end
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function RogueServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function RogueServer.OnSkill(player: Player, char: Model, skillIndex: number, origin: Vector3, dir: Vector3, config: any)
	local st = getState(player)
	dir = flat(dir)
	local enhanced = consume(player, st)
	if enhanced then fx({ kind = "enhanced", attacker = player, skill = skillIndex }) end
	if skillIndex == 1 then
		throwDagger(player, char, st, origin, dir, config, enhanced)
	elseif skillIndex == 2 then
		dash(player, char, st, origin, dir, config, enhanced)
	elseif skillIndex == 3 then
		startHidden(player, char, st, (config.duration or 6) * (if enhanced then 1.5 else 1))
	elseif skillIndex == 4 then
		realm(player, char, st, config, enhanced)
	end
end

-- Seconds the Shadow Realm's entrance freezes mobs / holds the camera.
RogueServer.REALM_WINDUP = 0.5

-- Fresh state (new character / run).
function RogueServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil, st.realmUntil, st.speedUntil = 0, 0, 0, 0, 0
	st.dagger = nil
	st.hiddenUntil = 0
	st.hiddenToken += 1
	setEnergy(player, st, 0)
	local char = player.Character
	if char then
		char:SetAttribute("Hidden", nil)
		char:SetAttribute("SpeedMult", nil)
	end
end

local function onCharacter(p: Player, char: Model)
	if p:GetAttribute("SelectedClass") ~= "rogue" then
		-- (another class now: off with the hood)
		for _, d in ipairs(char:GetChildren()) do
			if d:GetAttribute("RogueLook") then d:Destroy() end
		end
		return
	end
	RogueServer.Reset(p)
	task.defer(function()
		if char.Parent and char:WaitForChild("Head", 5) then RogueLook.Dress(char) end
	end)
end

function RogueServer.Init(helpers: any)
	H = helpers
	-- Taking a hit ends invisibility (the hit still lands).
	helpers.addIncomingHook(function(plr: Player, _char: Model, damage: number): number
		local st = states[plr]
		if st and st.hiddenUntil > 0 and damage > 0 then endHidden(plr, st, "hurt") end
		return damage
	end)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
		-- Picked the Rogue with a character already standing: dress it.
		p:GetAttributeChangedSignal("SelectedClass"):Connect(function()
			if p.Character then onCharacter(p, p.Character) end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
end

return RogueServer
