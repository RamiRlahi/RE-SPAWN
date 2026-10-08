--!strict
--[[
	MageServer.luau
	Server side of the Mage, "The Arcanist" (client: MageController). Every
	hit and all state is decided here; clients get the moments to draw over
	MageFX.

	  M1 Arcane Bolt     a bolt of arcane light from the casting hand, seeking
	                     the enemy nearest the aim, bursting where it hits
	                     (Projectile Count: more bolts, fanned out).
	  Passive            Arcane Charge (MG_Charge, 0–100): every ability adds to
	                     it (Burst +10, Prison +20, Shift +15, Apocalypse +25).
	                     At 100 the next ability is Empowered and uses it up.
	  E Arcane Burst     a concentrated arcane projectile that explodes where it
	                     hits and tears open a black hole there, dragging
	                     everything near into it until it collapses; it
	                     leaves an Arcane Rune glowing there for a few seconds.
	                     Empowered: three projectiles converging on the aim.
	  F Astral Prison    a magic circle at the aim; after a moment spectral
	                     chains rise and hold every enemy in it. The longer
	                     they're held, the more it charges; then it collapses in
	                     a massive explosion, and any Arcane Rune inside
	                     detonates too. Empowered: bigger, drags enemies in,
	                     collapses sooner.
	  Q Arcane Shift     phase through space to the aim, untargetable on the
	                     way; a shockwave where you reappear, and an Arcane Echo
	                     left where you were, which repeats your next ability
	                     at half power. Empowered: three Echoes.
	  R Apocalypse       marks every enemy in a huge radius; a vast magic circle
	                     opens in the sky and arcane bolts rain down on them;
	                     then every mark detonates at once.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local MageLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MageLook"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local MageServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local BOLT_INTERVAL = 0.42   -- seconds between Arcane Bolts at 1× attack speed
local BOLT_DAMAGE = 20
local BOLT_SPEED = 120
local BOLT_RANGE = 55
local BOLT_WIDTH = 2.2
local BOLT_SEEK = math.cos(math.rad(16)) -- seeks enemies within this cone of the aim
local BOLT_FAN = math.rad(8)  -- spread between extra bolts
local BOLT_SPLASH = 4         -- a small burst round where it hits (half damage)

local CHARGE_MAX = 100
local CHARGE_GAIN = { 10, 20, 15, 25 } -- per ability

local HOLE_LIFE = 1.2        -- the Burst's black hole: drawing everything in this long
local HOLE_PULL = 30         -- (studs/s at the edge, easing off toward the middle)
local RUNE_LIFE = 6          -- seconds an Arcane Rune glows where a Burst landed
local RUNE_RADIUS = 9        -- a rune's own blast when a Prison detonates it

local PRISON = { chains = 0.6, hold = 3.0, emp = 0.55 } -- (Empowered: the hold × emp)
local PRISON_TICK = 0.5      -- the chains squeeze: this often…
local PRISON_SQUEEZE = 0.1   -- …for this share of the collapse's damage
local PRISON_CHARGE = 1.5    -- held the whole time: the collapse does 1 + this ×

local SHIFT_WAVE = 0.12      -- the shockwave this long after the phase
local ECHO_LIFE = 8          -- seconds an Echo waits for your next ability
local ECHO_POWER = 0.5       -- the Echo's repeat: this × the damage
local ECHO_DELAY = 0.3       -- and this long after yours

local ULT = { mark = 0.25, rainFrom = 0.8, rainTo = 2.8, detonate = 3.0, total = 3.4 }
local RAIN_EVERY = 0.07      -- one bolt from the sky this often
local RAIN_SPLASH = 4.5
local DETONATE_MULT = 6      -- each mark's blast: × a rain bolt's damage
local DETONATE_SPLASH = 7

-- ── State ───────────────────────────────────────────────────────────────────
type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type Rune = { id: number, pos: Vector3, expires: number }
type Echo = { id: number, pos: Vector3, expires: number }
type State = {
	charge: number,
	lastBolt: number,
	busyUntil: number,
	runes: { Rune },
	echoes: { Echo },
	nextId: number,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { charge = 0, lastBolt = 0, busyUntil = 0, runes = {}, echoes = {}, nextId = 0 }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.MageFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function newId(st: State): number
	st.nextId += 1
	return st.nextId
end

-- ── Arcane Charge ───────────────────────────────────────────────────────────
local function setCharge(player: Player, st: State, v: number)
	st.charge = math.clamp(v, 0, CHARGE_MAX)
	player:SetAttribute("MG_Charge", st.charge)
end

local function gainCharge(player: Player, st: State, n: number)
	local before = st.charge
	setCharge(player, st, st.charge + n)
	if before < CHARGE_MAX and st.charge >= CHARGE_MAX then
		fx({ kind = "chargeFull", attacker = player })
	end
end

-- At full Charge the ability uses it all up and is Empowered.
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
		if Vector3.new(d.X, 0, d.Z).Magnitude <= radius and math.abs(d.Y) < radius + 6 then
			table.insert(out, t)
		end
	end
	return out
end

local function isBoss(t: Target): boolean
	return t.character:GetAttribute("IsBoss") == true
end

-- Drawn toward `center` (bosses stand firm).
local function pull(t: Target, center: Vector3, speed: number)
	if isBoss(t) then return end
	local d = Vector3.new(center.X - t.rootPart.Position.X, 0, center.Z - t.rootPart.Position.Z)
	if d.Magnitude < 1 then return end
	t.rootPart.AssemblyLinearVelocity = d.Unit * math.min(speed, d.Magnitude * 6) + Vector3.new(0, t.rootPart.AssemblyLinearVelocity.Y, 0)
end

local function hold(t: Target, seconds: number)
	if isBoss(t) then return end
	local untilT = os.clock() + seconds
	if (tonumber(t.character:GetAttribute("StaggerUntil")) or 0) < untilT then
		t.character:SetAttribute("StaggerUntil", untilT)
	end
end

local function shove(t: Target, away: Vector3, power: number)
	if isBoss(t) then return end
	local d = Vector3.new(away.X, 0, away.Z)
	d = if d.Magnitude > 0.05 then d.Unit else Vector3.xAxis
	pcall(function() t.rootPart:ApplyImpulse((d + Vector3.new(0, 0.35, 0)).Unit * t.rootPart.AssemblyMass * power) end)
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

-- How far a flight from `from` along `dir` goes before a wall.
local function clearDistance(char: Model, from: Vector3, dir: Vector3, length: number): number
	local res = Workspace:Raycast(from, dir * length, rayParams(char))
	return if res then math.max(1, res.Distance - 0.5) else length
end

-- The floor under a point.
local function floorAt(char: Model, pos: Vector3): Vector3
	local res = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), rayParams(char))
	return if res then res.Position else pos
end

-- A projectile really travelling a path (`at(s)` → the point after `s`
-- studs, up to `length`), at `speed`: the first enemy whose body it reaches
-- is handed to `onHit` (true = it stops there); `onEnd` gets where it ended.
local function fly(char: Model, length: number, speed: number, width: number, at: (number) -> Vector3,
	onHit: (Target, Vector3) -> boolean, onEnd: (Vector3) -> ())
	task.spawn(function()
		local flown = 0
		local struck: { [Model]: boolean } = {}
		while flown < length do
			local dt = RunService.Heartbeat:Wait()
			if not char.Parent then return end
			flown = math.min(length, flown + speed * dt)
			local p = at(flown)
			for _, t in ipairs(H.getPotentialTargets(char)) do
				if struck[t.character] then continue end
				local r = H.lineReach(t, width)
				local d = t.rootPart.Position - p
				if Vector3.new(d.X, 0, d.Z).Magnitude <= r and math.abs(d.Y) < 5 then
					struck[t.character] = true
					if onHit(t, p) then
						onEnd(p)
						return
					end
				end
			end
		end
		onEnd(at(length))
	end)
end

-- ── M1: Arcane Bolt ─────────────────────────────────────────────────────────
function MageServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1)
	if now - st.lastBolt < BOLT_INTERVAL / speed - 0.05 then return end
	st.lastBolt = now
	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local origin = root.Position + dir * 1.4 + Vector3.new(0, 0.6, 0)
	-- (it seeks the enemy nearest the aim, if one's in the cone)
	local best, bestScore = nil, math.huge
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = Vector3.new(t.rootPart.Position.X - origin.X, 0, t.rootPart.Position.Z - origin.Z)
		local dist = d.Magnitude
		if dist > 1 and dist <= BOLT_RANGE then
			local dot = dir:Dot(d.Unit)
			if dot >= BOLT_SEEK then
				local score = dist * (2 - dot)
				if score < bestScore then best, bestScore = t, score end
			end
		end
	end
	local aim = if best then flat(best.rootPart.Position - origin) else dir
	local count = 1 + math.max(0, math.floor(stat(player, "projectileCount")))
	local damage = BOLT_DAMAGE * stat(player, "damage")
	local width = BOLT_WIDTH * stat(player, "size")
	local boltSpeed = BOLT_SPEED * stat(player, "projectileSpeed")
	local dirs = {}
	for k = 1, count do
		local a = (k - (count + 1) / 2) * BOLT_FAN
		local d = (CFrame.Angles(0, a, 0) * CFrame.new(Vector3.zero, aim)).LookVector
		d = flat(d)
		table.insert(dirs, d)
		local length = clearDistance(char, origin, d, BOLT_RANGE)
		fly(char, length, boltSpeed, width, function(s) return origin + d * s end, function(t, p)
			local dealt = hit(player, t, damage, "ARCANE BOLT")
			if dealt then
				for _, o in ipairs(inRadius(char, p, BOLT_SPLASH * stat(player, "size"))) do
					if o.character ~= t.character then hit(player, o, damage * 0.5, "ARCANE BOLT") end
				end
				pcall(H.ricochet, player, char, t, damage, "ARCANE BOLT")
			end
			return true
		end, function(p)
			if H.fxAllowed(player, "mageBolt", 14) then
				fx({ kind = "boltEnd", attacker = player, k = k, pos = p })
			end
		end)
	end
	fx({ kind = "bolt", attacker = player, from = origin, dirs = dirs, speed = boltSpeed, range = BOLT_RANGE })
end

-- ── E: Arcane Burst ─────────────────────────────────────────────────────────
local function addRune(player: Player, st: State, pos: Vector3)
	local rune: Rune = { id = newId(st), pos = pos, expires = os.clock() + RUNE_LIFE }
	table.insert(st.runes, rune)
	fx({ kind = "rune", attacker = player, id = rune.id, pos = pos, life = RUNE_LIFE })
	task.delay(RUNE_LIFE, function()
		local i = table.find(st.runes, rune)
		if i then
			table.remove(st.runes, i)
			fx({ kind = "runeGone", attacker = player, id = rune.id })
		end
	end)
end

-- One burst where a projectile ends: damage, everything near drawn into the
-- centre, a rune left on the floor.
local function burstAt(player: Player, char: Model, st: State, at: Vector3, config: any, power: number, rune: boolean)
	local area = config.areaMultiplier or 1
	local radius = (config.radius or 10) * area
	local reach = radius * 1.4
	local damage = (config.damage or 45) * power
	local floor = floorAt(char, at)
	fx({ kind = "burstBoom", attacker = player, pos = at, floor = floor, radius = radius, reach = reach, life = HOLE_LIFE })
	for _, t in ipairs(inRadius(char, at, reach)) do
		local d = Vector3.new(t.rootPart.Position.X - at.X, 0, t.rootPart.Position.Z - at.Z).Magnitude
		if d <= radius then hit(player, t, damage, "ARCANE BURST") end
	end
	-- (the black hole it leaves: everything in reach drawn into it and held
	-- there until it collapses)
	task.spawn(function()
		local t0 = os.clock()
		local held: { [Model]: boolean } = {}
		while os.clock() - t0 < HOLE_LIFE - 0.1 and char.Parent do
			for _, t in ipairs(inRadius(char, at, reach)) do
				pull(t, at, HOLE_PULL)
				if not held[t.character] then
					held[t.character] = true
					hold(t, HOLE_LIFE - (os.clock() - t0))
				end
			end
			RunService.Heartbeat:Wait()
		end
	end)
	if rune then addRune(player, st, floor) end
end

-- The projectiles: one straight at the aim, or (Empowered) three that swing
-- out and converge on it. Projectile Count adds more of the same.
local function arcaneBurst(player: Player, char: Model, st: State, origin: Vector3, aim: Vector3, config: any, empowered: boolean, power: number, rune: boolean)
	local dir = flat(aim - origin)
	local maxLen = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z).Magnitude
	local length = clearDistance(char, origin, dir, math.max(maxLen, 4))
	local target = origin + dir * length
	local speed = config.projectileSpeed or 95
	local width = 2.6 * (config.areaMultiplier or 1)
	local extra = math.max(0, math.floor(config.projectileCount or 0))
	local count = (if empowered then 3 else 1) + extra
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local paths = {}
	for k = 1, count do
		-- (a sideways bow, 0 for the middle one; the outer ones converge)
		local bow = if count == 1 then 0 else ((k - 1) / (count - 1) * 2 - 1) * length * 0.35
		table.insert(paths, bow)
		local ctrl = origin + dir * length * 0.5 + side * bow
		local function at(s: number): Vector3
			local u = math.clamp(s / length, 0, 1)
			local a = origin:Lerp(ctrl, u)
			local b = ctrl:Lerp(target, u)
			return a:Lerp(b, u)
		end
		-- (a bowed path is a little longer than the chord)
		local pathLen = length * (1 + math.abs(bow) / length * 0.6)
		fly(char, length, speed * length / pathLen, width, at, function(_t, _p)
			return true
		end, function(p)
			fx({ kind = "burstEnd", attacker = player, k = k, pos = p })
			burstAt(player, char, st, p, config, power * (if count > 1 then 0.7 else 1), rune and k == math.ceil(count / 2))
		end)
	end
	fx({ kind = "burstCast", attacker = player, from = origin, to = target, bows = paths, speed = speed, empowered = empowered })
end

-- ── F: Astral Prison ────────────────────────────────────────────────────────
local function prison(player: Player, char: Model, st: State, center: Vector3, config: any, empowered: boolean, power: number)
	local area = config.areaMultiplier or 1
	local radius = (config.radius or 12) * area * (if empowered then 1.35 else 1)
	local damage = (config.damage or 70) * power
	local holdFor = (config.duration or PRISON.hold) * (if empowered then PRISON.emp else 1)
	local floor = floorAt(char, center)
	local id = newId(st)
	fx({ kind = "prison", attacker = player, id = id, pos = floor, radius = radius, chains = PRISON.chains,
		hold = holdFor, empowered = empowered, echo = power < 1 })
	task.spawn(function()
		task.wait(PRISON.chains)
		if not char.Parent then return end
		local trapped: { [Model]: number } = {}
		local nextTick = os.clock() + PRISON_TICK
		local ends = os.clock() + holdFor
		while os.clock() < ends and char.Parent do
			local now = os.clock()
			-- every enemy in the circle is caught (and, Empowered, those near it dragged in)
			for _, t in ipairs(inRadius(char, floor, radius * (if empowered then 1.5 else 1))) do
				local d = Vector3.new(t.rootPart.Position.X - floor.X, 0, t.rootPart.Position.Z - floor.Z).Magnitude
				if empowered then pull(t, floor, 22) end
				if d <= radius then
					if not trapped[t.character] then
						trapped[t.character] = now
						if H.fxAllowed(player, "magePrisonChain", 10) then
							fx({ kind = "prisonChain", attacker = player, id = id, model = t.character })
						end
					end
					hold(t, ends - now + 0.25)
					if not isBoss(t) then
						t.rootPart.AssemblyLinearVelocity = Vector3.new(0, t.rootPart.AssemblyLinearVelocity.Y, 0)
					end
				end
			end
			if now >= nextTick then
				nextTick += PRISON_TICK
				for _, t in ipairs(inRadius(char, floor, radius)) do
					if trapped[t.character] then hit(player, t, damage * PRISON_SQUEEZE, "ASTRAL CHAINS") end
				end
			end
			task.wait(0.1)
		end
		if not char.Parent then return end
		-- The collapse: the longer each one was held, the harder it hits.
		local now = os.clock()
		local runes = {}
		for i = #st.runes, 1, -1 do
			local r = st.runes[i]
			if Vector3.new(r.pos.X - floor.X, 0, r.pos.Z - floor.Z).Magnitude <= radius then
				table.insert(runes, { id = r.id, pos = r.pos })
				table.remove(st.runes, i)
			end
		end
		fx({ kind = "prisonCollapse", attacker = player, id = id, pos = floor, radius = radius, runes = runes })
		for _, t in ipairs(inRadius(char, floor, radius * 1.1)) do
			local since = trapped[t.character]
			local frac = if since then math.clamp((now - since) / holdFor, 0, 1) else 0
			hit(player, t, damage * (1 + PRISON_CHARGE * frac), "ASTRAL COLLAPSE")
		end
		-- (and every rune inside goes up with it)
		for _, r in ipairs(runes) do
			for _, t in ipairs(inRadius(char, r.pos, RUNE_RADIUS * area)) do
				hit(player, t, damage * 0.8, "RUNE BURST")
			end
		end
	end)
end

-- ── Q: Arcane Shift ─────────────────────────────────────────────────────────
local function dropEcho(player: Player, st: State, e: Echo)
	local i = table.find(st.echoes, e)
	if i then
		table.remove(st.echoes, i)
		fx({ kind = "echoGone", attacker = player, id = e.id })
	end
end

local function addEcho(player: Player, st: State, pos: Vector3): Echo
	-- (three at most: the oldest goes)
	while #st.echoes >= 3 do dropEcho(player, st, st.echoes[1]) end
	local e: Echo = { id = newId(st), pos = pos, expires = os.clock() + ECHO_LIFE }
	table.insert(st.echoes, e)
	task.delay(ECHO_LIFE, function() dropEcho(player, st, e) end)
	return e
end

local function shockwave(player: Player, char: Model, at: Vector3, config: any, power: number)
	local radius = (config.radius or 10) * (config.areaMultiplier or 1)
	for _, t in ipairs(inRadius(char, at, radius)) do
		hit(player, t, (config.damage or 35) * power, "ARCANE SHIFT")
		shove(t, t.rootPart.Position - at, 40)
	end
end

local function shift(player: Player, char: Model, st: State, origin: Vector3, dest: Vector3, config: any, empowered: boolean)
	-- (where the client put him; it never claims further than the reach)
	local reach = (config.range or 30) + 4
	local d = Vector3.new(dest.X - origin.X, 0, dest.Z - origin.Z)
	if d.Magnitude > reach then dest = origin + d.Unit * reach end
	local now = os.clock()
	char:SetAttribute("InvulnerableUntil", math.max(tonumber(char:GetAttribute("InvulnerableUntil")) or 0, now + 0.35))
	local wasHidden = char:GetAttribute("Hidden")
	if not wasHidden then
		char:SetAttribute("Hidden", true)
		task.delay(0.3, function()
			if char.Parent then char:SetAttribute("Hidden", nil) end
		end)
	end
	local dir = flat(d)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local echoes = {}
	for _, at in ipairs(if empowered then { origin, origin + side * 5, origin - side * 5 } else { origin }) do
		local e = addEcho(player, st, floorAt(char, at))
		table.insert(echoes, { id = e.id, pos = e.pos })
	end
	fx({ kind = "shift", attacker = player, from = origin, to = dest, echoes = echoes, empowered = empowered,
		radius = (config.radius or 10) * (config.areaMultiplier or 1), life = ECHO_LIFE })
	task.delay(SHIFT_WAVE, function()
		if char.Parent then shockwave(player, char, dest, config, 1) end
	end)
end

-- The Echoes repeat the ability just cast, from where they stand, at half
-- power, then fade.
local function echoesRepeat(player: Player, char: Model, st: State, skillIndex: number, aim: Vector3, config: any)
	local now = os.clock()
	local list = {}
	for _, e in ipairs(st.echoes) do
		if e.expires > now then table.insert(list, e) end
	end
	if #list == 0 then return end
	for _, e in ipairs(list) do dropEcho(player, st, e) end
	task.delay(ECHO_DELAY, function()
		if not char.Parent then return end
		for _, e in ipairs(list) do
			local from = e.pos + Vector3.new(0, 3, 0)
			fx({ kind = "echoCast", attacker = player, id = e.id, skill = skillIndex, pos = e.pos, aim = aim })
			if skillIndex == 1 then
				arcaneBurst(player, char, st, from, aim, config, false, ECHO_POWER, false)
			elseif skillIndex == 2 then
				prison(player, char, st, aim, config, false, ECHO_POWER)
			elseif skillIndex == 3 then
				task.delay(SHIFT_WAVE, function()
					if char.Parent then shockwave(player, char, e.pos, config, ECHO_POWER) end
				end)
			end
		end
	end)
end

-- ── R: Apocalypse ───────────────────────────────────────────────────────────
local function apocalypse(player: Player, char: Model, st: State, config: any, empowered: boolean)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local area = config.areaMultiplier or 1
	local radius = (config.radius or 45) * area * (if empowered then 1.2 else 1)
	local damage = (config.damage or 26) * (if empowered then 1.3 else 1)
	local center = root.Position
	local floor = floorAt(char, center)
	local now = os.clock()
	st.busyUntil = now + ULT.total
	char:SetAttribute("InvulnerableUntil", math.max(tonumber(char:GetAttribute("InvulnerableUntil")) or 0, now + ULT.total + 0.2))
	fx({ kind = "apoc", attacker = player, pos = floor, radius = radius, t = ULT, empowered = empowered })
	-- 1 · the marks
	local marked: { Target } = {}
	task.delay(ULT.mark, function()
		if not char.Parent then return end
		local list = {}
		for _, t in ipairs(inRadius(char, center, radius)) do
			table.insert(marked, t)
			table.insert(list, t.character)
			t.character:SetAttribute("ArcaneMarkUntil", os.clock() + ULT.total)
		end
		fx({ kind = "apocMarks", attacker = player, models = list })
	end)
	-- 2 · the rain
	task.delay(ULT.rainFrom, function()
		local ends = os.clock() + (ULT.rainTo - ULT.rainFrom)
		while os.clock() < ends and char.Parent do
			local alive = {}
			for _, t in ipairs(marked) do
				if t.humanoid.Health > 0 and t.character.Parent then table.insert(alive, t) end
			end
			local at: Vector3
			if #alive > 0 and math.random() < 0.7 then
				local t = alive[math.random(1, #alive)]
				at = t.rootPart.Position + Vector3.new(math.random() * 4 - 2, 0, math.random() * 4 - 2)
			else
				local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * radius
				at = center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
			end
			at = floorAt(char, at)
			fx({ kind = "apocBolt", attacker = player, pos = at })
			-- (it lands a moment after it's drawn falling)
			task.delay(0.12, function()
				if not char.Parent then return end
				for _, t in ipairs(inRadius(char, at, RAIN_SPLASH * area)) do hit(player, t, damage, "ARCANE RAIN") end
			end)
			task.wait(RAIN_EVERY)
		end
	end)
	-- 3 · every mark detonates
	task.delay(ULT.detonate, function()
		if not char.Parent then return end
		local blasts = {}
		for _, t in ipairs(marked) do
			if t.character.Parent and t.humanoid.Health > 0 then
				table.insert(blasts, { model = t.character, pos = t.rootPart.Position })
			end
			t.character:SetAttribute("ArcaneMarkUntil", nil)
		end
		fx({ kind = "apocDetonate", attacker = player, pos = floor, radius = radius, blasts = blasts })
		for _, b in ipairs(blasts) do
			local m = b.model :: Model
			local hum = m:FindFirstChildOfClass("Humanoid")
			local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and r and hum.Health > 0 then
				hit(player, { character = m, humanoid = hum, rootPart = r }, damage * DETONATE_MULT, "APOCALYPSE")
			end
			for _, o in ipairs(inRadius(char, b.pos, DETONATE_SPLASH * area)) do
				if o.character ~= m then hit(player, o, damage * DETONATE_MULT * 0.4, "APOCALYPSE") end
			end
		end
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function MageServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function MageServer.OnSkill(player: Player, char: Model, skillIndex: number, origin: Vector3, dir: Vector3, config: any, targetPosition: Vector3?)
	local st = getState(player)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	dir = flat(dir)
	local empowered = consume(player, st)
	if empowered then fx({ kind = "empowered", attacker = player, skill = skillIndex }) end
	local range = config.range or 40
	-- Where it's aimed: the cursor (within reach), else straight ahead.
	local aim = root.Position + dir * range
	if typeof(targetPosition) == "Vector3" then
		local d = Vector3.new(targetPosition.X - root.Position.X, 0, targetPosition.Z - root.Position.Z)
		aim = root.Position + (if d.Magnitude > range then d.Unit * range else d)
		aim = Vector3.new(aim.X, targetPosition.Y, aim.Z)
	end
	local hand = root.Position + dir * 1.4 + Vector3.new(0, 0.6, 0)
	if skillIndex == 1 then
		arcaneBurst(player, char, st, hand, Vector3.new(aim.X, hand.Y, aim.Z), config, empowered, 1, true)
		echoesRepeat(player, char, st, 1, Vector3.new(aim.X, hand.Y, aim.Z), config)
	elseif skillIndex == 2 then
		prison(player, char, st, aim, config, empowered, 1)
		echoesRepeat(player, char, st, 2, aim, config)
	elseif skillIndex == 3 then
		echoesRepeat(player, char, st, 3, aim, config)
		shift(player, char, st, root.Position, aim, config, empowered)
	elseif skillIndex == 4 then
		apocalypse(player, char, st, config, empowered)
	end
	gainCharge(player, st, CHARGE_GAIN[skillIndex] or 0)
end

-- Seconds the Apocalypse's opening (the marks) freezes mobs.
MageServer.ULT_WINDUP = ULT.rainFrom

-- Fresh state (new character / run).
function MageServer.Reset(player: Player)
	local st = getState(player)
	st.busyUntil, st.lastBolt = 0, 0
	table.clear(st.runes)
	table.clear(st.echoes)
	setCharge(player, st, 0)
end

local function onCharacter(p: Player, char: Model)
	if p:GetAttribute("SelectedClass") ~= "mage" then
		MageLook.Undress(char)
		return
	end
	MageServer.Reset(p)
	task.defer(function()
		if char.Parent and char:WaitForChild("Head", 5) and char:WaitForChild("Torso", 5) then MageLook.Dress(char) end
	end)
end

function MageServer.Init(helpers: any)
	H = helpers
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

return MageServer
