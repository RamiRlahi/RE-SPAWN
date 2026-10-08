--!strict
--[[
	MartialServer.luau
	Server side of the Martial Artist, "Flow · Strike · Master" (client:
	MartialController). Every hit and all state is decided here; clients get
	the moments to draw over MartialFX.

	  M1 Flowing Fists   a 4-hit combo: jab, cross, a spinning roundhouse that
	                     hits all round him, and a dragon palm that bursts
	                     with Qi (a small blast that shoves). Faster under Qi
	                     Release.
	  Passive            Qi Charge (MA_Charge, 0–100): abilities build it
	                     (Dragon Fist +20, Qi Release +15, Dragon Ascent +20,
	                     Dragon Soul +30) and so do landed strikes (+2). At
	                     100 the next ability is Empowered and uses it up.
	  E Dragon Fist      a short channel, then a dragon of Qi surges forward
	                     from the fists: everything it passes through is hit
	                     hard and pushed back; a shockwave where it ends.
	                     Empowered: three dragons, longer, harder.
	  F Qi Release       a burst of Qi, then circulating Qi round him for a
	                     while: faster movement and attacks, less damage
	                     taken. Empowered: a bigger aura, faster, tougher.
	  Q Dragon Ascent    Qi lifts him up, he rides a dragon's energy through
	                     everything to the aim, crashes down in an explosion
	                     and leaves a burning trail. Empowered: three dragons
	                     strike the path, a wider landing and trail.
	  R Dragon Soul      Qi gathers round him, a colossal dragon rises, then
	                     sweeps forward through everything in its path three
	                     times over, and dissipates.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local MartialLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MartialLook"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local MartialServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local COMBO_INTERVAL = 0.3    -- seconds between strikes at 1× attack speed
local COMBO_RESET = 1.0       -- the combo starts over after this long without a strike
local COMBO_DAMAGE = { 18, 18, 22, 34 }
local COMBO_RANGE = 7.5
local COMBO_ARC = math.cos(math.rad(65))
local PALM_RADIUS = 6         -- the 4th strike's burst of Qi

local CHARGE_MAX = 100
local CHARGE_GAIN = { 20, 15, 20, 30 } -- per ability
local CHARGE_PER_HIT = 2               -- per strike that lands (once per swing)

local FIST = { channel = 0.3, speed = 58, empRange = 1.35, empDamage = 1.3, lane = 3.4 } -- (lanes: side by side, Empowered / Projectile Count)

local QI = { speed = 1.25, attack = 1.3, guard = 0.7 }          -- multipliers while it lasts
local QI_EMP = { speed = 1.4, attack = 1.5, guard = 0.5, size = 1.4 }

-- Dragon Ascent (matches the client's flight: up, along, down)
local ASCENT = { rise = 0.24, dash = 0.22, fall = 0.12 }
local ASCENT_TRAIL = 2.5      -- seconds the trail burns
local ASCENT_TICK = 0.5
local ASCENT_WIDTH = 4

-- Dragon Soul
local SOUL = { summon = 0.8, manifest = 1.5, passes = { 1.75, 2.35, 2.95 }, fade = 3.3, total = 3.6 }

-- ── State ───────────────────────────────────────────────────────────────────
type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = {
	charge: number,
	step: number,
	lastSwing: number,
	busyUntil: number,
	qiUntil: number,
	qiEmp: boolean,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { charge = 0, step = 0, lastSwing = 0, busyUntil = 0, qiUntil = 0, qiEmp = false }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.MartialFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

-- ── Qi Charge ───────────────────────────────────────────────────────────────
local function setCharge(player: Player, st: State, v: number)
	st.charge = math.clamp(v, 0, CHARGE_MAX)
	player:SetAttribute("MA_Charge", st.charge)
end

local function gainCharge(player: Player, st: State, n: number)
	local before = st.charge
	setCharge(player, st, st.charge + n)
	if before < CHARGE_MAX and st.charge >= CHARGE_MAX then
		fx({ kind = "chargeFull", attacker = player })
	end
end

local function consume(player: Player, st: State): boolean
	if st.charge < CHARGE_MAX then return false end
	setCharge(player, st, 0)
	return true
end

-- ── Hits and shapes ─────────────────────────────────────────────────────────
local function hit(player: Player, t: Target, damage: number, source: string): number?
	if t.humanoid.Health <= 0 then return nil end
	return H.dealDamage(player, t, damage, source)
end

local function inRadius(char: Model, center: Vector3, radius: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - center
		if Vector3.new(d.X, 0, d.Z).Magnitude <= radius + H.lineReach(t, 0) * 0.5 and math.abs(d.Y) < radius + 6 then
			table.insert(out, t)
		end
	end
	return out
end

-- Everyone within `width` of the segment a→b (flat).
local function alongSegment(char: Model, a: Vector3, b: Vector3, width: number): { Target }
	local out = {}
	local ab = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = ab.Magnitude
	local dir = if len > 0.01 then ab / len else Vector3.zero
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = Vector3.new(t.rootPart.Position.X - a.X, 0, t.rootPart.Position.Z - a.Z)
		local along = math.clamp(d:Dot(dir), 0, len)
		local off = (d - dir * along).Magnitude
		if off <= H.lineReach(t, width) and math.abs(t.rootPart.Position.Y - a.Y) < 9 then
			table.insert(out, t)
		end
	end
	return out
end

local function isBoss(t: Target): boolean
	return t.character:GetAttribute("IsBoss") == true
end

local function shove(t: Target, away: Vector3, power: number, lift: number?)
	if isBoss(t) then return end
	local d = Vector3.new(away.X, 0, away.Z)
	d = if d.Magnitude > 0.05 then d.Unit else Vector3.xAxis
	pcall(function() t.rootPart:ApplyImpulse((d + Vector3.new(0, lift or 0.3, 0)).Unit * t.rootPart.AssemblyMass * power) end)
end

local function hold(t: Target, seconds: number)
	if isBoss(t) then return end
	local untilT = os.clock() + seconds
	if (tonumber(t.character:GetAttribute("StaggerUntil")) or 0) < untilT then
		t.character:SetAttribute("StaggerUntil", untilT)
	end
end

local function rayParams(char: Model): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { char }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	return params
end

local function clearDistance(char: Model, from: Vector3, dir: Vector3, length: number): number
	local res = Workspace:Raycast(from, dir * length, rayParams(char))
	return if res then math.max(1, res.Distance - 0.5) else length
end

local function floorAt(char: Model, pos: Vector3): Vector3
	local res = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), rayParams(char))
	return if res then res.Position else pos
end

-- Qi Release's multipliers right now (1 when it isn't up).
local function qiActive(st: State): boolean
	return os.clock() < st.qiUntil
end

-- ── M1: Flowing Fists ───────────────────────────────────────────────────────
function MartialServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1)
	if qiActive(st) then speed *= (if st.qiEmp then QI_EMP.attack else QI.attack) end
	if now - st.lastSwing < COMBO_INTERVAL / speed - 0.06 then return end
	if now - st.lastSwing > COMBO_RESET then st.step = 0 end
	st.step = st.step % 4 + 1
	st.lastSwing = now
	local step = st.step
	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local damage = COMBO_DAMAGE[step] * stat(player, "damage")
	local size = stat(player, "size")
	local reach = COMBO_RANGE * size
	-- (the 3rd strike is a spinning roundhouse: it hits all the way round him)
	local spin = step == 3
	local landed = false
	local struck: { Target } = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = Vector3.new(t.rootPart.Position.X - root.Position.X, 0, t.rootPart.Position.Z - root.Position.Z)
		if d.Magnitude <= reach + H.lineReach(t, 0) * 0.5 and math.abs(t.rootPart.Position.Y - root.Position.Y) < 6
			and (spin or d.Magnitude < 2 or dir:Dot(d.Unit) >= COMBO_ARC) then
			if hit(player, t, damage, if spin then "ROUNDHOUSE" else "FLOWING FISTS") then
				landed = true
				table.insert(struck, t)
				hold(t, 0.25)
				if step == 4 then shove(t, d, 38) elseif spin then shove(t, d, 22) end
			end
		end
	end
	-- the palm strike: a burst of Qi in front of him
	local palmAt = root.Position + dir * 4
	if step == 4 then
		local already: { [Model]: boolean } = {}
		for _, t in ipairs(struck) do already[t.character] = true end
		for _, t in ipairs(inRadius(char, palmAt, PALM_RADIUS * size)) do
			if not already[t.character] then
				if hit(player, t, damage * 0.6, "QI PALM") then
					landed = true
					shove(t, t.rootPart.Position - root.Position, 34)
				end
			end
		end
	end
	if landed then
		gainCharge(player, st, CHARGE_PER_HIT)
		if #struck > 0 then pcall(H.ricochet, player, char, struck[1], damage, "FLOWING FISTS") end
	end
	fx({ kind = "strike", attacker = player, step = step, pos = root.Position, dir = dir, landed = landed,
		palm = if step == 4 then palmAt else nil, radius = PALM_RADIUS * size })
end

-- ── E: Dragon Fist ──────────────────────────────────────────────────────────
-- (rooted for a moment: the channel)
local function busyFor(player: Player, seconds: number)
	local st = getState(player)
	st.busyUntil = math.max(st.busyUntil, os.clock() + seconds)
end

local function dragonFist(player: Player, char: Model, root: BasePart, dir: Vector3, config: any, empowered: boolean)
	local area = config.areaMultiplier or 1
	local range = (config.range or 28) * (if empowered then FIST.empRange else 1)
	local width = (config.width or 6) * area * 0.5
	local damage = (config.damage or 70) * (if empowered then FIST.empDamage else 1)
	local extra = math.max(0, math.floor(config.projectileCount or 0))
	local count = (if empowered then 3 else 1) + extra
	local center = root.Position + Vector3.new(0, 0.6, 0)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	-- (one dragon from the fist; more run side by side, all the same way)
	local origins, lengths = {}, {}
	for k = 1, count do
		local o = center + side * (k - (count + 1) / 2) * FIST.lane
		table.insert(origins, o)
		table.insert(lengths, clearDistance(char, o, dir, range))
	end
	busyFor(player, FIST.channel + 0.1)
	fx({ kind = "fist", attacker = player, from = center, origins = origins, dir = dir, lengths = lengths, speed = FIST.speed,
		channel = FIST.channel, empowered = empowered, width = width })
	task.delay(FIST.channel, function()
		if not char.Parent then return end
		for k, origin in ipairs(origins) do
			local d = dir
			local length = lengths[k]
			task.spawn(function()
				local flown = 0
				local struck: { [Model]: boolean } = {}
				while flown < length and char.Parent do
					local dt = RunService.Heartbeat:Wait()
					local was = flown
					flown = math.min(length, flown + FIST.speed * dt)
					for _, t in ipairs(alongSegment(char, origin + d * was, origin + d * flown, width)) do
						if not struck[t.character] then
							struck[t.character] = true
							if hit(player, t, damage, "DRAGON FIST") then
								shove(t, d, 55, 0.35)
								hold(t, 0.35)
							end
						end
					end
				end
				-- the brief shockwave where it ends
				local endAt = origin + d * length
				fx({ kind = "fistEnd", attacker = player, pos = endAt, k = k, radius = width * 1.6 })
				for _, t in ipairs(inRadius(char, endAt, width * 1.6)) do
					if not struck[t.character] then hit(player, t, damage * 0.4, "DRAGON FIST") end
					shove(t, t.rootPart.Position - endAt, 30)
				end
			end)
		end
	end)
end

-- ── F: Qi Release ───────────────────────────────────────────────────────────
local function qiRelease(player: Player, char: Model, root: BasePart, config: any, empowered: boolean)
	local st = getState(player)
	local q = if empowered then QI_EMP else QI
	local seconds = (config.duration or 6) * math.max(stat(player, "abilityDuration"), 0.1) * (if empowered then 1.3 else 1)
	local radius = (config.radius or 9) * (config.areaMultiplier or 1) * (if empowered then QI_EMP.size else 1)
	local now = os.clock()
	st.qiUntil = now + seconds
	st.qiEmp = empowered
	char:SetAttribute("SpeedMult", q.speed)
	player:SetAttribute("MA_QiUntil", Workspace:GetServerTimeNow() + seconds)
	player:SetAttribute("MA_QiEmp", empowered)
	fx({ kind = "qi", attacker = player, radius = radius, seconds = seconds, empowered = empowered })
	-- the burst as it activates
	for _, t in ipairs(inRadius(char, root.Position, radius)) do
		hit(player, t, (config.damage or 20), "QI RELEASE")
		shove(t, t.rootPart.Position - root.Position, 30)
	end
	local token = st.qiUntil
	task.delay(seconds, function()
		if st.qiUntil ~= token then return end -- (cast again meanwhile)
		st.qiEmp = false
		if char.Parent and char:GetAttribute("SpeedMult") == q.speed then char:SetAttribute("SpeedMult", nil) end
		player:SetAttribute("MA_QiUntil", nil)
		player:SetAttribute("MA_QiEmp", nil)
		fx({ kind = "qiEnd", attacker = player })
	end)
end

-- ── Q: Dragon Ascent ────────────────────────────────────────────────────────
local function ascent(player: Player, char: Model, root: BasePart, dir: Vector3, dest: Vector3, config: any, empowered: boolean)
	local st = getState(player)
	local area = config.areaMultiplier or 1
	local range = config.range or 26
	local origin = root.Position
	-- (where the client put him; never further than the reach)
	local d = Vector3.new(dest.X - origin.X, 0, dest.Z - origin.Z)
	if d.Magnitude > range + 4 then dest = origin + d.Unit * (range + 4) end
	local land = floorAt(char, dest)
	local from = floorAt(char, origin)
	local damage = config.damage or 55
	local radius = (config.radius or 9) * area * (if empowered then 1.4 else 1)
	local width = ASCENT_WIDTH * area * (if empowered then 1.5 else 1)
	local total = ASCENT.rise + ASCENT.dash + ASCENT.fall
	st.busyUntil = math.max(st.busyUntil, os.clock() + total)
	char:SetAttribute("InvulnerableUntil", math.max(tonumber(char:GetAttribute("InvulnerableUntil")) or 0, os.clock() + total + 0.1))
	fx({ kind = "ascent", attacker = player, from = from, to = land, t = ASCENT, empowered = empowered, radius = radius,
		width = width, trail = ASCENT_TRAIL })
	-- the strike: everything on the path (Empowered: three dragons, three hits)
	task.delay(ASCENT.rise + ASCENT.dash * 0.5, function()
		if not char.Parent then return end
		local hits = if empowered then 3 else 1
		for n = 1, hits do
			for _, t in ipairs(alongSegment(char, from, land, width)) do
				if hit(player, t, damage * (if empowered then 0.6 else 1), "DRAGON ASCENT") then hold(t, 0.4) end
			end
			if n < hits then task.wait(0.12) end
		end
	end)
	-- the landing
	task.delay(total, function()
		if not char.Parent then return end
		for _, t in ipairs(inRadius(char, land, radius)) do
			hit(player, t, damage * 1.2, "DRAGON ASCENT")
			shove(t, t.rootPart.Position - land, 45, 0.6)
		end
		-- the trail burns for a while
		local ends = os.clock() + ASCENT_TRAIL
		while os.clock() < ends and char.Parent do
			task.wait(ASCENT_TICK)
			for _, t in ipairs(alongSegment(char, from, land, width * 0.8)) do
				hit(player, t, damage * 0.1, "QI TRAIL")
			end
		end
	end)
end

-- ── R: Dragon Soul ──────────────────────────────────────────────────────────
local function dragonSoul(player: Player, char: Model, root: BasePart, dir: Vector3, config: any, empowered: boolean)
	local st = getState(player)
	local area = config.areaMultiplier or 1
	local length = (config.range or 70) * (if empowered then 1.2 else 1)
	local width = (config.width or 22) * area * 0.5 * (if empowered then 1.2 else 1)
	local damage = (config.damage or 90) * (if empowered then 1.3 else 1)
	local now = os.clock()
	local origin = floorAt(char, root.Position)
	st.busyUntil = now + SOUL.total
	char:SetAttribute("InvulnerableUntil", math.max(tonumber(char:GetAttribute("InvulnerableUntil")) or 0, now + SOUL.total + 0.2))
	fx({ kind = "soul", attacker = player, pos = origin, dir = dir, length = length, width = width, t = SOUL, empowered = empowered })
	local endAt = origin + dir * length
	for _, at in ipairs(SOUL.passes) do
		task.delay(at, function()
			if not char.Parent then return end
			for _, t in ipairs(alongSegment(char, origin, endAt, width)) do
				if hit(player, t, damage, "DRAGON SOUL") then
					hold(t, 0.6)
					shove(t, dir, 20, 0.8)
				end
			end
		end)
	end
end

-- ── Public ──────────────────────────────────────────────────────────────────
function MartialServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function MartialServer.OnSkill(player: Player, char: Model, skillIndex: number, origin: Vector3, dir: Vector3, config: any, targetPosition: Vector3?)
	local st = getState(player)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	dir = flat(dir)
	local empowered = consume(player, st)
	if empowered then fx({ kind = "empowered", attacker = player, skill = skillIndex }) end
	if skillIndex == 1 then
		dragonFist(player, char, root, dir, config, empowered)
	elseif skillIndex == 2 then
		qiRelease(player, char, root, config, empowered)
	elseif skillIndex == 3 then
		local range = config.range or 26
		local dest = root.Position + dir * range
		if typeof(targetPosition) == "Vector3" then dest = targetPosition end
		ascent(player, char, root, dir, dest, config, empowered)
	elseif skillIndex == 4 then
		dragonSoul(player, char, root, dir, config, empowered)
	end
	gainCharge(player, st, CHARGE_GAIN[skillIndex] or 0)
end

-- Seconds the Dragon Soul's summoning holds mobs still (the cutscene).
MartialServer.ULT_WINDUP = SOUL.summon

function MartialServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil, st.qiUntil, st.qiEmp = 0, 0, 0, 0, false
	player:SetAttribute("MA_QiUntil", nil)
	player:SetAttribute("MA_QiEmp", nil)
	setCharge(player, st, 0)
end

local function onCharacter(p: Player, char: Model)
	if p:GetAttribute("SelectedClass") ~= "martial_artist" then
		MartialLook.Undress(char)
		return
	end
	MartialServer.Reset(p)
	task.defer(function()
		if char.Parent and char:WaitForChild("Head", 5) and char:WaitForChild("Torso", 5) then MartialLook.Dress(char) end
	end)
end

function MartialServer.Init(helpers: any)
	H = helpers
	if helpers.addIncomingHook then
		helpers.addIncomingHook(function(player: Player, _char: Model, damage: number): number
			local st = states[player]
			if st and os.clock() < st.qiUntil then
				damage *= if st.qiEmp then QI_EMP.guard else QI.guard
			end
			return damage
		end)
	end
	local function watch(p: Player)
		p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
		p:GetAttributeChangedSignal("SelectedClass"):Connect(function()
			if p.Character then onCharacter(p, p.Character) end
		end)
		if p.Character then task.spawn(onCharacter, p, p.Character) end
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
end

return MartialServer
