--!strict
--[[
	FireKnightServer.luau
	Server side of the Fire Knight (class id "heavy_knight"; client:
	FireKnightController). Every hit and all state is decided here; clients get
	the moments to draw over FireKnightFX.

	  Passive  HEAT OF WAR   hits build Heat (0–100); it cools off when out of
	                         combat. At 100: OVERHEAT for a few seconds — bonus
	                         fire damage, burning ground under basic attacks,
	                         Empowered skills, no knockback — then Heat crashes
	                         back to 0.
	  Status   SCORCH        fire attacks stack Scorch (burn over time). At 5
	                         stacks the enemy IGNITES: an explosion that hurts
	                         and Scorches everyone near it and feeds Heat, so
	                         ignites chain through a pack.
	  M1  EMBERBLADE         Cinder Slash → Scorching Cross → Furnace Breaker
	                         (explodes) → Infernal Execution (a wound-up slam and
	                         a line of fire).
	  E   BLAZING CHARGE     ignite, charge, drag whoever's caught, finish with a
	                         launching upward slash. Empowered: a bull rush that
	                         plows through everything and leaves the path burning.
	  F   PHOENIX SLAM       soar up and become a phoenix of fire; the player
	                         picks where to land with a marker (FireKnightAim),
	                         then dives: an explosion and burning ground.
	                         Empowered: a bigger impact, flares going off round
	                         it and a lingering inferno.
	  Q   INFERNAL EARTHSHAKER  wind up, drive the sword into the ground: a big
	                         explosion, aftershocks rippling out, fire patches.
	                         Empowered: three expanding rings of fire.
	  R   HEART OF THE INFERNO  plant the sword and awaken; a pillar of fire,
	                         then several seconds of Inferno (every attack
	                         explodes, faster, Scorching aura) and THE FINAL BLOW:
	                         every flame in the arena is drawn into the sword for
	                         one enormous flame wave that then erupts. Stronger
	                         at 75 Heat; at Overheat it consumes it and becomes
	                         the PRIMORDIAL INFERNO.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local FireKnightServer = {}

local CLASS = "heavy_knight"

-- ── Tuning ──────────────────────────────────────────────────────────────────
local HEAT_MAX = 100
local HEAT_DECAY_DELAY = 4    -- seconds without gaining Heat before it cools
local HEAT_DECAY_RATE = 6     -- Heat lost per second while cooling
local OVERHEAT_TIME = 6
local OVERHEAT_BONUS = 0.3    -- +30% fire damage while Overheated

local SWING_INTERVAL = 0.42   -- seconds between combo swings at 1× attack speed
local COMBO_RESET = 1.2
local EXECUTION_WINDUP = 0.32 -- hit 4 pulls the sword back before the slam

local SCORCH_MAX = 5
local SCORCH_TIME = 4         -- stacks last this long (refreshed by new stacks)
local SCORCH_DPS = 4          -- damage per stack per second
local IGNITE_RADIUS = 10
local IGNITE_DAMAGE = 45
local IGNITE_LOCK = 1.0       -- an enemy can't ignite again this soon

local PATCH_TICK = 0.5
local PATCH_DPS = 8
local MAX_PATCHES = 40

local PHOENIX_RISE = 0.55     -- up into the air, becoming the phoenix
local PHOENIX_AIM = 2.2       -- longest the marker can be held before it dives anyway
local PHOENIX_DIVE = 0.3
local PHOENIX_RANGE = 40      -- how far from the take-off it can land
local PHOENIX_RADIUS = 11

local AWAKEN = 1.6            -- ult wind-up (mobs frozen, cutscene)
local INFERNO_TIME = 6
local FINAL_DELAY = 1.6       -- flames drawn into the raised sword
local INFERNO_SPEED = 1.25

local COMBO = {
	-- range: arc radius, or the blast radius when `at` is set (the blast is
	-- centred `at` studs ahead). dot: minimum facing dot for arcs.
	[1] = { range = 13, dot = -0.1, damage = 28, heat = 4, scorch = 1, source = "CINDER SLASH" },
	[2] = { range = 13, dot = 0.1, damage = 30, heat = 4, scorch = 1, source = "SCORCHING CROSS" },
	[3] = { range = 7, at = 6, damage = 38, heat = 5, scorch = 1, source = "FURNACE BREAKER" },
	[4] = { range = 8.5, at = 6, damage = 62, heat = 8, scorch = 2, source = "INFERNAL EXECUTION", line = 20 },
}

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = {
	heat: number,
	lastHeat: number,
	overheatUntil: number,
	step: number,
	lastSwing: number,
	busyUntil: number,
	phoenix: Phoenix?,
	phoenixToken: number,
	infernoUntil: number,
	infernoPower: number,
	infernoTier: number,
	lastAura: number,
}
type Burn = { stacks: number, expires: number, by: Player, lock: number, target: Target }
-- A Phoenix Slam in flight: where it took off, and where it's landing once
-- the player has picked the spot.
type Phoenix = { token: number, origin: Vector3, dir: Vector3, empowered: boolean, config: any, target: Vector3? }
type Patch = { pos: Vector3, radius: number, expires: number, by: Player, ticks: number }

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}
local burns: { [Model]: Burn } = {}
local patches: { Patch } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = {
			heat = 0, lastHeat = 0, overheatUntil = 0,
			step = 0, lastSwing = 0, busyUntil = 0,
			phoenix = nil, phoenixToken = 0,
			infernoUntil = 0, infernoPower = 1, infernoTier = 0, lastAura = 0,
		}
		states[player] = st
	end
	return st
end

local function isFireKnight(player: Player?): boolean
	return player ~= nil and player:GetAttribute("SelectedClass") == CLASS
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.FireKnightFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function rootOf(char: Model?): BasePart?
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function isHeavy(t: Target): boolean
	return t.character:GetAttribute("IsBoss") == true or t.character:GetAttribute("IsElite") == true
end

local function overheated(st: State): boolean
	return os.clock() < st.overheatUntil
end

local function infernoActive(st: State): boolean
	return os.clock() < st.infernoUntil
end

-- Damage multiplier for everything the knight does right now.
local function fireMult(st: State): number
	local m = 1
	if overheated(st) then m += OVERHEAT_BONUS end
	if infernoActive(st) then m *= st.infernoPower end
	return m
end

-- ── Hit shapes ──────────────────────────────────────────────────────────────
local function inArc(char: Model, origin: Vector3, dir: Vector3, range: number, minDot: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - origin
		local fd = Vector3.new(d.X, 0, d.Z)
		if fd.Magnitude <= range and math.abs(d.Y) < 10 then
			if minDot <= -1 or fd.Magnitude < 3 or dir:Dot(fd.Unit) >= minDot then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function inCircle(char: Model, center: Vector3, radius: number): { Target }
	return inArc(char, center, Vector3.zAxis, radius, -1)
end

local function onLine(char: Model, from: Vector3, dir: Vector3, length: number, width: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - from
		local along = Vector3.new(d.X, 0, d.Z):Dot(dir)
		if along >= -2 and along <= length + 2 and math.abs(d.Y) < 10 then
			local closest = from + dir * along
			if Vector3.new(t.rootPart.Position.X - closest.X, 0, t.rootPart.Position.Z - closest.Z).Magnitude <= width then
				table.insert(out, t)
			end
		end
	end
	return out
end

-- ── Heat ────────────────────────────────────────────────────────────────────
local function setHeat(player: Player, st: State, v: number)
	st.heat = math.clamp(v, 0, HEAT_MAX)
	player:SetAttribute("FK_Heat", math.floor(st.heat + 0.5))
end

local function setOverheat(player: Player, on: boolean, duration: number?)
	player:SetAttribute("FK_Overheat", on)
	player:SetAttribute("FK_OverheatEnd", if on then Workspace:GetServerTimeNow() + (duration or 0) else nil)
	local char = player.Character
	-- Resistance to interruption: mobs' hits don't knock an Overheated knight.
	if char then char:SetAttribute("Unstoppable", if on then true else nil) end
end

local function startOverheat(player: Player, st: State)
	st.overheatUntil = os.clock() + OVERHEAT_TIME
	setHeat(player, st, HEAT_MAX)
	setOverheat(player, true, OVERHEAT_TIME)
	fx({ kind = "overheat", attacker = player, duration = OVERHEAT_TIME })
end

-- Overheat runs out: Heat crashes back to nothing.
local function endOverheat(player: Player, st: State, quiet: boolean?)
	st.overheatUntil = 0
	setHeat(player, st, 0)
	setOverheat(player, false)
	if not quiet then fx({ kind = "cooldown", attacker = player }) end
end

local function gainHeat(player: Player, st: State, n: number)
	if n <= 0 or overheated(st) then return end
	st.lastHeat = os.clock()
	setHeat(player, st, st.heat + n)
	if st.heat >= HEAT_MAX then startOverheat(player, st) end
end

-- ── Scorch / Ignite ─────────────────────────────────────────────────────────
local ignite: (Player, Target) -> ()

local function applyScorch(player: Player, t: Target, n: number)
	if n <= 0 or t.humanoid.Health <= 0 then return end
	local b = burns[t.character]
	if not b then
		b = { stacks = 0, expires = 0, by = player, lock = 0, target = t }
		burns[t.character] = b
	end
	b.by = player
	b.target = t
	b.stacks = math.min(b.stacks + n, SCORCH_MAX)
	b.expires = os.clock() + SCORCH_TIME
	t.character:SetAttribute("FK_Scorch", b.stacks)
	if b.stacks >= SCORCH_MAX and os.clock() >= b.lock then
		b.lock = os.clock() + IGNITE_LOCK
		task.defer(ignite, player, t)
	end
end

ignite = function(player: Player, t: Target)
	local b = burns[t.character]
	if b then
		b.stacks = 0
		t.character:SetAttribute("FK_Scorch", 0)
	end
	local char = player.Character
	if not char then return end
	local st = getState(player)
	local pos = t.rootPart.Position
	fx({ kind = "ignite", attacker = player, pos = pos, radius = IGNITE_RADIUS })
	gainHeat(player, st, 6)
	local damage = IGNITE_DAMAGE * stat(player, "damage") * fireMult(st)
	for _, o in ipairs(inCircle(char, pos, IGNITE_RADIUS)) do
		H.dealDamage(player, o, damage, "IGNITE")
		-- The explosion spreads the fire: that's the chain.
		if o.character ~= t.character then applyScorch(player, o, 2) end
	end
end

-- ── Burning ground ──────────────────────────────────────────────────────────
local function addPatch(player: Player, pos: Vector3, radius: number, life: number)
	if #patches >= MAX_PATCHES then table.remove(patches, 1) end
	table.insert(patches, { pos = pos, radius = radius, expires = os.clock() + life, by = player, ticks = 0 })
	fx({ kind = "patch", attacker = player, pos = pos, radius = radius, life = life })
end

-- ── Burn / Heat loop ────────────────────────────────────────────────────────
local tickAcc = 0
local function step(dt: number)
	local now = os.clock()
	-- Heat: Overheat ending, cooling when out of combat, the Inferno's aura.
	for player, st in pairs(states) do
		if not player.Parent then
			states[player] = nil
			continue
		end
		if st.overheatUntil > 0 and now >= st.overheatUntil then
			endOverheat(player, st)
		elseif not overheated(st) and st.heat > 0 and now - st.lastHeat > HEAT_DECAY_DELAY then
			setHeat(player, st, st.heat - HEAT_DECAY_RATE * dt)
		end
		if infernoActive(st) and now - st.lastAura >= 1 then
			st.lastAura = now
			local char = player.Character
			local root = rootOf(char)
			if char and root then
				for _, t in ipairs(inCircle(char, root.Position, 10)) do
					applyScorch(player, t, if st.infernoTier >= 3 then 2 else 1)
				end
			end
		end
	end

	tickAcc += dt
	if tickAcc < PATCH_TICK then return end
	local tick = tickAcc
	tickAcc = 0

	-- Scorch burns.
	for model, b in pairs(burns) do
		local t = b.target
		if not model.Parent or t.humanoid.Health <= 0 or not b.by.Parent then
			burns[model] = nil
		elseif b.stacks > 0 then
			if now > b.expires then
				b.stacks = 0
				model:SetAttribute("FK_Scorch", 0)
			else
				H.dealDamage(b.by, t, SCORCH_DPS * b.stacks * tick * stat(b.by, "damage"), "SCORCH")
			end
		end
	end

	-- Burning ground: damage every tick, a Scorch stack every second.
	for i = #patches, 1, -1 do
		local p = patches[i]
		local char = p.by.Character
		if now > p.expires or not p.by.Parent or not char then
			table.remove(patches, i)
		else
			p.ticks += 1
			for _, t in ipairs(inCircle(char, p.pos, p.radius)) do
				H.dealDamage(p.by, t, PATCH_DPS * tick * stat(p.by, "damage"), "BURNING GROUND")
				if p.ticks % 2 == 0 then applyScorch(p.by, t, 1) end
			end
		end
	end
end

-- ── M1: Emberblade ──────────────────────────────────────────────────────────
-- An explosion at `pos` (Inferno: every attack explodes).
local function infernoBlast(player: Player, char: Model, st: State, pos: Vector3)
	local radius = 7 * stat(player, "size")
	fx({ kind = "blast", attacker = player, pos = pos, radius = radius })
	for _, t in ipairs(inCircle(char, pos, radius)) do
		H.dealDamage(player, t, 22 * stat(player, "damage") * fireMult(st), "INFERNO BLAST")
		applyScorch(player, t, 1)
	end
end

function FireKnightServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1) * (if infernoActive(st) then 1.25 else 1)
	if now - st.lastSwing < (SWING_INTERVAL / speed) * 0.85 then return end
	st.step = if now - st.lastSwing > COMBO_RESET then 1 else (st.step % 4) + 1
	st.lastSwing = now

	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local n = st.step
	local c = COMBO[n]
	fx({ kind = "combo", attacker = player, step = n, dir = dir })
	-- Damage lands on the swing's strike (FireKnightController.COMBO_HIT).
	local windup = ({ 0.12, 0.11, 0.14, EXECUTION_WINDUP })[n]
	if n == 4 then st.busyUntil = now + EXECUTION_WINDUP + 0.12 end

	task.delay(windup, function()
		if not char.Parent or not root.Parent then return end
		local size = stat(player, "size")
		local damage = c.damage * stat(player, "damage") * fireMult(st)
		local center = if c.at then root.Position + dir * c.at * size else root.Position
		local hits = if c.at then inCircle(char, center, c.range * size) else inArc(char, root.Position, dir, c.range * size, c.dot or -1)
		for _, t in ipairs(hits) do
			H.dealDamage(player, t, damage, c.source)
			applyScorch(player, t, c.scorch)
		end
		if n == 4 and c.line then
			-- A short line of fire erupting on from the impact.
			for _, t in ipairs(onLine(char, center, dir, c.line * size, 3.5 * size)) do
				H.dealDamage(player, t, damage * 0.4, "FIRE LINE")
				applyScorch(player, t, 1)
			end
		end
		if #hits > 0 then gainHeat(player, st, c.heat + math.min(#hits - 1, 4)) end
		if overheated(st) then
			addPatch(player, if c.at then center else root.Position + dir * 5 * size, 4 * size, 2.5)
		end
		if infernoActive(st) then
			infernoBlast(player, char, st, if c.at then center else root.Position + dir * 6 * size)
		end
	end)
end

-- ── E: Blazing Charge ───────────────────────────────────────────────────────
local CHARGE_WINDUP = 0.22

local function blazingCharge(player: Player, char: Model, st: State, dir: Vector3, config: any, empowered: boolean)
	local root = rootOf(char)
	if not root then return end
	local area = config.areaMultiplier or 1
	local dur = if empowered then 0.5 else 0.38
	local dist = (config.dashDistance or 22) * (if empowered then 1.45 else 1)
	local width = 4.5 * area
	local damage = (config.damage or 40) * fireMult(st)
	st.busyUntil = os.clock() + CHARGE_WINDUP + dur + 0.4
	char:SetAttribute("InvulnerableUntil", os.clock() + CHARGE_WINDUP + dur)
	fx({ kind = "charge", attacker = player, dir = dir, windup = CHARGE_WINDUP, dur = dur, dist = dist, empowered = empowered })

	task.delay(CHARGE_WINDUP, function()
		if not char.Parent then return end
		local caught: { [Model]: Target } = {}
		local firstAt: number? = nil
		local lastPatch = root.Position
		local t0 = os.clock()
		while os.clock() - t0 < dur do
			task.wait(0.05)
			if not char.Parent or not root.Parent then return end
			local p = root.Position
			for _, t in ipairs(inCircle(char, p + dir * 1.5, width)) do
				if not caught[t.character] then
					caught[t.character] = t
					firstAt = firstAt or os.clock()
					H.dealDamage(player, t, damage, "BLAZING CHARGE")
					applyScorch(player, t, 1)
				end
			end
			-- Whoever's caught is dragged along in front of the charge.
			for _, t in pairs(caught) do
				if not isHeavy(t) and not t.rootPart.Anchored and t.humanoid.Health > 0 then
					t.rootPart.AssemblyLinearVelocity = dir * (dist / dur) * 0.9 + Vector3.new(0, t.rootPart.AssemblyLinearVelocity.Y, 0)
				end
			end
			if empowered and (p - lastPatch).Magnitude >= 4 then
				-- The bull rush leaves its whole path burning.
				addPatch(player, p, 3.5 * area, 4)
				lastPatch = p
			end
			-- A plain charge stops a moment after it meets someone.
			if not empowered and firstAt and os.clock() - firstAt > 0.12 then break end
		end

		-- The upward slash at the end: launches the smaller ones.
		local p = root.Position
		fx({ kind = "rise", attacker = player, pos = p, dir = dir, empowered = empowered })
		local n = 0
		for _, t in pairs(caught) do n += 1 end
		for _, t in ipairs(inArc(char, p, dir, 9 * area, 0)) do
			H.dealDamage(player, t, damage * 1.2, "RISING SLASH")
			applyScorch(player, t, 1)
			n += 1
		end
		gainHeat(player, st, 6 + math.min(n, 6))
		if infernoActive(st) then infernoBlast(player, char, st, p + dir * 4) end
	end)
end

-- ── F: Phoenix Slam ────────────────────────────────────────────────────────
-- The dive: down onto `target`, an explosion and the ground left burning.
local function phoenixDive(player: Player, char: Model, st: State, target: Vector3)
	local ph = st.phoenix
	if not ph or ph.target then return end
	ph.target = target
	local config = ph.config
	local empowered = ph.empowered
	local area = config.areaMultiplier or 1
	local radius = PHOENIX_RADIUS * area * (if empowered then 1.35 else 1)
	fx({ kind = "phoenixDive", attacker = player, to = target, dur = PHOENIX_DIVE, radius = radius, empowered = empowered })
	task.delay(PHOENIX_DIVE, function()
		if st.phoenix == ph then st.phoenix = nil end
		if char.Parent then char:SetAttribute("FK_Phoenix", nil) end
		st.busyUntil = os.clock() + 0.3
		if not char.Parent then return end
		local damage = (config.damage or 90) * fireMult(st)
		fx({ kind = "phoenixImpact", attacker = player, pos = target, radius = radius, empowered = empowered })
		local hits = inCircle(char, target, radius)
		for _, t in ipairs(hits) do
			H.dealDamage(player, t, damage, "PHOENIX SLAM")
			applyScorch(player, t, 2)
		end
		-- The ground left burning (Empowered: a lingering inferno).
		local life = if empowered then 6 else 4
		addPatch(player, target, radius * 0.5, life)
		local ring = if empowered then 6 else 3
		for i = 1, ring do
			local a = (i / ring) * math.pi * 2 + math.random() * 0.6
			local d = radius * (0.55 + math.random() * 0.3)
			addPatch(player, target + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), 3 * area, life)
		end
		if empowered then
			-- More explosions: flares going off round the impact.
			local points = {}
			for i = 1, 5 do
				local a = (i / 5) * math.pi * 2 + math.random() * 0.5
				table.insert(points, target + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.95)
			end
			fx({ kind = "flares", attacker = player, points = points, radius = 5 * area })
			for i, p in ipairs(points) do
				task.delay(0.15 + i * 0.07, function()
					if not char.Parent then return end
					for _, t in ipairs(inCircle(char, p, 5 * area)) do
						H.dealDamage(player, t, damage * 0.45, "PHOENIX FLARE")
						applyScorch(player, t, 1)
					end
				end)
			end
		end
		gainHeat(player, st, 8 + math.min(#hits * 2, 12))
		if infernoActive(st) then infernoBlast(player, char, st, target) end
	end)
end

local function phoenixSlam(player: Player, char: Model, st: State, dir: Vector3, config: any, empowered: boolean)
	local root = rootOf(char)
	if not root then return end
	local now = os.clock()
	st.phoenixToken += 1
	local token = st.phoenixToken
	local ph: Phoenix = { token = token, origin = root.Position, dir = dir, empowered = empowered, config = config }
	st.phoenix = ph
	local total = PHOENIX_RISE + PHOENIX_AIM + PHOENIX_DIVE
	st.busyUntil = now + total + 0.5
	-- Untouchable up there (until it lands).
	char:SetAttribute("InvulnerableUntil", now + total + 0.4)
	char:SetAttribute("FK_Phoenix", true)
	local area = config.areaMultiplier or 1
	fx({ kind = "phoenixRise", attacker = player, rise = PHOENIX_RISE, aim = PHOENIX_AIM, range = PHOENIX_RANGE * area,
		radius = PHOENIX_RADIUS * area * (if empowered then 1.35 else 1), empowered = empowered })
	-- No spot picked in time: it dives ahead of where it took off.
	task.delay(PHOENIX_RISE + PHOENIX_AIM + 0.4, function()
		if st.phoenix == ph and not ph.target then
			phoenixDive(player, char, st, ph.origin + dir * 16 - Vector3.new(0, 3, 0))
		end
	end)
end

-- The player's chosen landing spot (FireKnightAim), kept within range of
-- the take-off and on its floor.
local function onAim(player: Player, payload: any)
	local st = states[player]
	local ph = st and st.phoenix
	local char = player.Character
	if not st or not ph or ph.target or not char then return end
	if typeof(payload) ~= "table" or typeof(payload.target) ~= "Vector3" then return end
	local t = payload.target :: Vector3
	if t ~= t then return end -- NaN
	local range = PHOENIX_RANGE * (ph.config.areaMultiplier or 1)
	local d = Vector3.new(t.X - ph.origin.X, 0, t.Z - ph.origin.Z)
	if d.Magnitude > range then
		local c = ph.origin + d.Unit * range
		t = Vector3.new(c.X, t.Y, c.Z)
	end
	if math.abs(t.Y - (ph.origin.Y - 3)) > 14 then t = Vector3.new(t.X, ph.origin.Y - 3, t.Z) end
	phoenixDive(player, char, st, t)
end

-- ── Q: Infernal Earthshaker ─────────────────────────────────────────────────
local QUAKE_WINDUP = 0.55

local function earthshaker(player: Player, char: Model, st: State, config: any, empowered: boolean)
	local root = rootOf(char)
	if not root then return end
	local area = config.areaMultiplier or 1
	local radius = (config.range or 14) * area
	st.busyUntil = os.clock() + QUAKE_WINDUP + 0.45
	fx({ kind = "quake", attacker = player, windup = QUAKE_WINDUP, radius = radius, empowered = empowered })

	task.delay(QUAKE_WINDUP, function()
		if not char.Parent or not root.Parent then return end
		local center = root.Position
		local damage = (config.damage or 70) * fireMult(st)
		local hitCount = 0
		if not empowered then
			fx({ kind = "quakeHit", attacker = player, pos = center, radius = radius })
			for _, t in ipairs(inCircle(char, center, radius)) do
				H.dealDamage(player, t, damage, "EARTHSHAKER")
				applyScorch(player, t, 2)
				hitCount += 1
			end
			-- Smaller explosions travel outward, then fire lingers.
			local rng = Random.new()
			local shocks = {}
			for i = 1, 6 do
				local a = (i / 6) * math.pi * 2 + rng:NextNumber(-0.3, 0.3)
				local d = radius * rng:NextNumber(0.75, 1.2)
				table.insert(shocks, center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d))
			end
			fx({ kind = "aftershocks", attacker = player, points = shocks, radius = 4.5 * area })
			for i, p in ipairs(shocks) do
				task.delay(0.12 + i * 0.05, function()
					if not char.Parent then return end
					for _, t in ipairs(inCircle(char, p, 4.5 * area)) do
						H.dealDamage(player, t, damage * 0.4, "AFTERSHOCK")
						applyScorch(player, t, 1)
					end
				end)
			end
			for _ = 1, 5 do
				local a = rng:NextNumber(0, math.pi * 2)
				local d = radius * rng:NextNumber(0.25, 0.9)
				addPatch(player, center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), 3 * area, 4)
			end
		else
			-- Three rings of fire expanding outward, each a band of damage.
			local radii = { radius * 0.7, radius * 1.3, radius * 1.85 }
			fx({ kind = "rings", attacker = player, pos = center, radii = radii, gap = 0.28 })
			local inner = 0
			for i, r in ipairs(radii) do
				local from = inner
				task.delay((i - 1) * 0.28, function()
					if not char.Parent then return end
					for _, t in ipairs(inCircle(char, center, r)) do
						local d = Vector3.new(t.rootPart.Position.X - center.X, 0, t.rootPart.Position.Z - center.Z).Magnitude
						if d >= from - 2 then
							H.dealDamage(player, t, damage * 1.1, "FIRE RING")
							applyScorch(player, t, 2)
						end
					end
				end)
				inner = r
			end
			hitCount = #inCircle(char, center, radii[3])
			for _ = 1, 8 do
				local a = math.random() * math.pi * 2
				local d = radii[3] * (0.2 + math.random() * 0.7)
				addPatch(player, center + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d), 3 * area, 4)
			end
		end
		gainHeat(player, st, 6 + math.min(hitCount * 2, 12))
	end)
end

-- ── R: Heart of the Inferno ─────────────────────────────────────────────────
local function finalBlow(player: Player, char: Model, st: State, config: any)
	local root = rootOf(char)
	if not root or not char.Parent then
		st.infernoUntil = 0
		return
	end
	st.busyUntil = os.clock() + FINAL_DELAY + 0.6
	char:SetAttribute("SpeedMult", nil)
	-- Every flame in the arena is drawn into the sword: burning ground and
	-- every Scorched enemy's fire.
	local sources: { Vector3 } = {}
	local absorbed = 0
	for i = #patches, 1, -1 do
		local p = patches[i]
		if (p.pos - root.Position).Magnitude < 90 then
			absorbed += 1
			if #sources < 40 then table.insert(sources, p.pos) end
			table.remove(patches, i)
		end
	end
	for model, b in pairs(burns) do
		if b.stacks > 0 and model.Parent and (b.target.rootPart.Position - root.Position).Magnitude < 90 then
			absorbed += b.stacks
			if #sources < 40 then table.insert(sources, b.target.rootPart.Position) end
			b.stacks = 0
			model:SetAttribute("FK_Scorch", 0)
		end
	end
	fx({ kind = "gather", attacker = player, sources = sources, delay = FINAL_DELAY, tier = st.infernoTier })

	task.delay(FINAL_DELAY, function()
		st.infernoUntil = 0
		char:SetAttribute("FK_Inferno", nil)
		player:SetAttribute("FK_InfernoEnd", nil)
		if not char.Parent or not root.Parent then return end
		local area = config.areaMultiplier or 1
		local origin = root.Position
		local length = 70 * area
		local width = 9 * area
		-- The wave goes down whichever line holds the most enemies (ties: the
		-- way he's facing).
		local look = flat(root.CFrame.LookVector)
		local best = #onLine(char, origin, look, length, width)
		for i = 0, 23 do
			local a = i / 24 * math.pi * 2
			local d = Vector3.new(math.cos(a), 0, math.sin(a))
			local n = #onLine(char, origin, d, length, width)
			if n > best then best, look = n, d end
		end
		local damage = (config.damage or 150) * st.infernoPower * (1 + math.min(absorbed, 40) * 0.04)
		fx({ kind = "execution", attacker = player, pos = origin, dir = look, length = length, width = width, tier = st.infernoTier })
		local hits = onLine(char, origin, look, length, width)
		for _, t in ipairs(hits) do
			H.dealDamage(player, t, damage, "EXECUTION")
		end
		-- After a beat, everything inside the wave erupts.
		task.delay(0.6, function()
			local points = {}
			for _, t in ipairs(hits) do
				if t.character.Parent then table.insert(points, t.rootPart.Position) end
			end
			fx({ kind = "erupt", attacker = player, points = points, origin = origin, dir = look, length = length })
			for _, t in ipairs(hits) do
				if t.humanoid.Health > 0 then
					H.dealDamage(player, t, damage * 0.6, "INFERNO ERUPTION")
					applyScorch(player, t, 2)
				end
			end
		end)
	end)
end

local function heartOfTheInferno(player: Player, char: Model, st: State, dir: Vector3, config: any)
	local root = rootOf(char)
	if not root then return end
	-- The ult reads the passive: 75+ Heat burns hotter; at Overheat it eats
	-- the Overheat and becomes the Primordial Inferno.
	local tier = if overheated(st) then 3 elseif st.heat >= 75 then 2 else 1
	if tier == 3 then endOverheat(player, st, true) end
	local power = ({ 1.25, 1.45, 1.8 })[tier]
	local infernoTime = INFERNO_TIME + (if tier == 3 then 2 else 0)
	st.busyUntil = os.clock() + AWAKEN + 0.3
	char:SetAttribute("InvulnerableUntil", os.clock() + AWAKEN + 0.3)
	fx({ kind = "awaken", attacker = player, dir = dir, awaken = AWAKEN, tier = tier, inferno = infernoTime })

	task.delay(AWAKEN, function()
		if not char.Parent or not root.Parent then return end
		local area = config.areaMultiplier or 1
		local center = root.Position
		st.infernoUntil = os.clock() + infernoTime
		st.infernoPower = power
		st.infernoTier = tier
		st.lastAura = 0
		char:SetAttribute("FK_Inferno", tier)
		char:SetAttribute("SpeedMult", INFERNO_SPEED)
		player:SetAttribute("FK_InfernoEnd", Workspace:GetServerTimeNow() + infernoTime)
		fx({ kind = "pillar", attacker = player, pos = center, radius = 13 * area, tier = tier, inferno = infernoTime })
		for _, t in ipairs(inCircle(char, center, 13 * area)) do
			H.dealDamage(player, t, (config.damage or 150) * 0.6 * power, "HEART OF THE INFERNO")
			applyScorch(player, t, 2)
		end
		if tier == 3 then
			-- Primordial: every Scorched enemy becomes an explosion.
			for model, b in pairs(burns) do
				if b.stacks > 0 and model.Parent and b.target.humanoid.Health > 0 then
					b.lock = os.clock() + IGNITE_LOCK
					task.defer(ignite, player, b.target)
				end
			end
		end
		task.delay(infernoTime, finalBlow, player, char, st, config)
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function FireKnightServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function FireKnightServer.OnSkill(player: Player, char: Model, skillIndex: number, _origin: Vector3, dir: Vector3, config: any)
	local st = getState(player)
	dir = flat(dir)
	-- Overheated or in the Inferno, every skill is Empowered (and bigger).
	local empowered = overheated(st) or infernoActive(st)
	if infernoActive(st) then config.areaMultiplier = (config.areaMultiplier or 1) * 1.3 end
	if skillIndex == 1 then
		blazingCharge(player, char, st, dir, config, empowered)
	elseif skillIndex == 2 then
		phoenixSlam(player, char, st, dir, config, empowered)
	elseif skillIndex == 3 then
		earthshaker(player, char, st, config, empowered)
	elseif skillIndex == 4 then
		heartOfTheInferno(player, char, st, dir, config)
	end
end

-- Seconds the ult's awakening freezes mobs / holds the camera.
FireKnightServer.AWAKEN = AWAKEN

-- Fresh Heat, combo and Inferno (new character / run).
function FireKnightServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil, st.infernoUntil = 0, 0, 0, 0
	st.overheatUntil = 0
	st.phoenix = nil
	if player.Character then player.Character:SetAttribute("FK_Phoenix", nil) end
	setHeat(player, st, 0)
	setOverheat(player, false)
	player:SetAttribute("FK_InfernoEnd", nil)
end

function FireKnightServer.Init(helpers: any)
	H = helpers
	RunService.Heartbeat:Connect(step)
	Network.GetRemoteEvent(Network.Remotes.FireKnightAim).OnServerEvent:Connect(onAim)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function()
			if isFireKnight(p) then FireKnightServer.Reset(p) end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		for model, b in pairs(burns) do
			if b.by == p then burns[model] = nil end
		end
	end)
end

return FireKnightServer
