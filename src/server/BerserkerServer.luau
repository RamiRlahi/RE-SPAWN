--!strict
--[[
	BerserkerServer.luau
	Server side of the Berserker, the Crimson Ravager (client:
	BerserkerController). Every hit and all state is decided here; clients get
	the moments to draw over BerserkerFX. Crimson energy, black smoke,
	fractured ground, red afterimages.

	The warrior:
	  M1 Greatsword    a heavy 3-hit chain: a diagonal cleave, a backhand, and
	                   an overhead smash (all-round shockwave).
	  E  Rupture       crouch, leap, hang at the apex, crash down: a crater, a
	                   circular fracture and a shockwave (damage + knock-up).
	  F  Bloodstorm    feet planted, a flurry of huge crescent slashes in front,
	                   each with a beat of hit-stop and a shove, then a spinning
	                   cleave that throws them out. Half damage taken while it
	                   lasts.
	  Q  Crimson Charge
	                   a lean, then a headlong charge at the aim: untouchable
	                   the whole way, every enemy in his path cut and thrown
	                   aside, a burst at the end that blows everything near
	                   away. His NEXT skill is Empowered (bigger, more violent).

	RAGE (0-100, "BR_Rage") builds as he fights: every enemy struck, more when
	one blow catches a crowd or lands heavy, a kill, and every hit he takes.
	Full, it unlocks:

	  R  BEAST AWAKENING
	                   he freezes, his body tears open and grows, the sword is
	                   cast aside, a roar blows everything near away: for 12 s
	                   he is the BEAST ("BR_BeastUntil"), bigger, faster, harder
	                   hitting, skills recharging twice as fast, and a new kit:
	  M1 Claws         claw, claw, claw, then a brutal downward maul that staggers.
	  E  Beast Slam    an enormous leap, a crash on all fours: those under him
	                   crushed and stunned, then three rings roll out (knocked
	                   back, launched, a last wave over the whole area).
	  F  Carnage       three huge claw swipes (across, back, a diagonal rake
	                   down): each one staggers longer; caught by all three,
	                   they bleed and the last one launches them.
	  Q  Beast Charge  down on all fours and through everything: each one struck
	                   is staggered and shoved aside; at the end he grabs the
	                   biggest he hit, hoists it and hurls it forward into the
	                   rest.
	                   Then he sinks to his knees, shrinks back and his sword
	                   reforms in his hand.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local BerserkerLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BerserkerLook"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))
local WeaponManager = require(script.Parent:WaitForChild("WeaponManager"))

local BerserkerServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local SWING_INTERVAL = 0.48   -- seconds between combo swings at 1× attack speed (a heavy blade)
local COMBO_RESET = 1.2

local COMBO = {
	-- range, minimum facing dot (-1 = all round), damage, source
	[1] = { range = 12, dot = 0.1, damage = 30, source = "BERSERK CLEAVE" },
	[2] = { range = 12, dot = 0.1, damage = 30, source = "BERSERK CLEAVE" },
	[3] = { range = 13, dot = -1, damage = 52, source = "BERSERK SMASH", heavy = true },
}

-- Rupture: crouch, leap, hang, crash (seconds after the cast).
local RUPTURE = { crouch = 0.32, rise = 0.3, hang = 0.18, fall = 0.14 }
RUPTURE.impact = RUPTURE.crouch + RUPTURE.rise + RUPTURE.hang + RUPTURE.fall
local RUPTURE_RANGE = 17      -- the furthest he can leap (to the cursor)

-- Bloodstorm: the lean, then swings on the spot that each come a little
-- faster, every one held a beat as it bites (the hit-stop).
local STORM_WINDUP = 0.35
local STORM_FIRST = 0.34      -- the first swing, heave to hack (s)
local STORM_ACCEL = 0.9       -- each next swing takes this much of the last
local STORM_FREEZE = 0.1      -- the hit-stop after each blow
local STORM_HITS = 5          -- (Empowered: 7)
local STORM_SLASH = 30        -- each crescent's reach in front (studs)
local STORM_ARC = -0.1        -- (the facing dot it reaches round to: the front half)
local STORM_FINISH = 36       -- the spinning cleave's radius
local STORM_GUARD = 0.5       -- damage taken while storming

-- Crimson Charge: the lean, then the run (mirrored in BerserkerController).
local CHARGE = { windup = 0.18, run = 0.45 }
local CHARGE_DIST = 28        -- how far he charges (short of walls)
local CHARGE_WIDTH = 6        -- how close to his path an enemy is run through
local CHARGE_BURST = 12       -- the burst at the end
local CHARGE_SHOVE = 40       -- knockback (× the enemy's mass)

-- Rage.
local RAGE_MAX = 100
local RAGE_HIT = 2.5          -- per enemy struck
local RAGE_CROWD = 4          -- more when one blow catches three or more
local RAGE_HEAVY = 3          -- more for a heavy blow (a finisher, a skill)
local RAGE_KILL = 6           -- per kill
local RAGE_HURT = 70          -- × the share of his max health a hit takes

-- Beast Awakening (mirrored in BerserkerController).
local BEAST = { freeze = 0.45, mutate = 1.15, roar = 0.5 }
BEAST.change = BEAST.freeze + BEAST.mutate -- the moment the body becomes the beast
BEAST.total = BEAST.change + BEAST.roar
local BEAST_TIME = 12
local BEAST_SCALE = 1.35
local BEAST_REVERT = 1.2      -- sinking back to his knees
local BEAST_DAMAGE = 0.3      -- +30% damage as the beast
local BEAST_SPEED = 1.15      -- move speed
local BEAST_JUMP = 1.7        -- × jump height
local BEAST_COOLDOWN = 0.5    -- skills recharge twice as fast
local BEAST_ROAR = 18         -- the roar's shockwave radius

-- The beast's claws: three rakes and the maul.
local CLAW_INTERVAL = 0.34
local CLAW_RESET = 1.0
local CLAWS = {
	[1] = { range = 14, dot = 0, damage = 26, source = "BEAST CLAW" },
	[2] = { range = 14, dot = 0, damage = 26, source = "BEAST CLAW" },
	[3] = { range = 14, dot = 0, damage = 28, source = "BEAST CLAW" },
	[4] = { range = 16, dot = 0.2, damage = 60, source = "BEAST MAUL", heavy = true },
}

-- Beast Slam: crouch, leap far up, hang, crash; then the rings roll out.
local SLAM = { crouch = 0.2, rise = 0.42, hang = 0.14, fall = 0.22 }
SLAM.impact = SLAM.crouch + SLAM.rise + SLAM.hang + SLAM.fall
local SLAM_RANGE = 26         -- the furthest he leaps (to the cursor)
local SLAM_UNDER = 9          -- crushed and stunned: right under him
local SLAM_RINGS = {
	{ at = 0.12, radius = 16, mult = 0.5, source = "BEAST QUAKE", band = true },    -- knocked back
	{ at = 0.38, radius = 24, mult = 0.5, source = "BEAST UPHEAVAL", band = true }, -- launched
	{ at = 0.66, radius = 32, mult = 0.4, source = "BEAST TREMOR", band = false },  -- the whole area
}

-- Carnage: three claws land at these times; the last reaches furthest.
local CARNAGE = { 0.22, 0.5, 0.88 }
local CARNAGE_REACH = { 18, 18, 24 }
local CARNAGE_DOT = { -0.1, -0.1, 0.05 }
local CARNAGE_STAGGER = 0.35  -- each claw that lands on one staggers it this much longer
local BLEED_TICKS, BLEED_EVERY = 5, 0.5

-- Beast Charge: crouch, run, the grab, the throw.
local BCHARGE = { crouch = 0.15, run = 0.6, grab = 0.45, throw = 0.25 }
local BCHARGE_DIST = 38
local BCHARGE_WIDTH = 7
local THROW_SPEED = 95
local THROW_HIT = 6           -- the thrown body bowls over whoever it passes this close to

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = {
	step: number,
	lastSwing: number,
	busyUntil: number,
	guardUntil: number,
	beastToken: number,
	jump: number?,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { step = 0, lastSwing = 0, busyUntil = 0, guardUntil = 0, beastToken = 0, jump = nil }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.BerserkerFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

-- ── Beast and Rage ──────────────────────────────────────────────────────────
local function beast(player: Player): boolean
	return (tonumber(player:GetAttribute("BR_BeastUntil")) or 0) > Workspace:GetServerTimeNow()
end

local function damageMult(player: Player): number
	return stat(player, "damage") * (if beast(player) then 1 + BEAST_DAMAGE else 1)
end

local function rageOf(player: Player): number
	return tonumber(player:GetAttribute("BR_Rage")) or 0
end

-- (none builds while he's the beast: the meter is spent)
local function addRage(player: Player, n: number)
	if n <= 0 or beast(player) then return end
	local before = rageOf(player)
	local now = math.clamp(before + n, 0, RAGE_MAX)
	if now ~= before then player:SetAttribute("BR_Rage", now) end
end

-- Crimson Charge empowers the next skill (only one).
local function takeEmpowered(player: Player): boolean
	if player:GetAttribute("BR_Empowered") ~= true then return false end
	player:SetAttribute("BR_Empowered", nil)
	return true
end

-- ── Hit shapes ──────────────────────────────────────────────────────────────
local function inRadius(char: Model, origin: Vector3, dir: Vector3, range: number, minDot: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - origin
		local fd = Vector3.new(d.X, 0, d.Z)
		if fd.Magnitude <= range and math.abs(d.Y) < range + 6 then
			if minDot <= -1 or fd.Magnitude < 3 or dir:Dot(fd.Unit) >= minDot then
				table.insert(out, t)
			end
		end
	end
	return out
end

-- Hit every one of `hits`; Rage for what landed. Returns how many did.
local function strike(player: Player, hits: { Target }, damage: number, source: string, heavy: boolean?): number
	local landed, kills = 0, 0
	for _, t in ipairs(hits) do
		if t.humanoid.Health <= 0 then continue end
		if H.dealDamage(player, t, damage, source) then
			landed += 1
			if t.humanoid.Health <= 0 then kills += 1 end
		end
	end
	if landed > 0 then
		addRage(player, landed * RAGE_HIT + (if landed >= 3 then RAGE_CROWD else 0) + (if heavy then RAGE_HEAVY else 0) + kills * RAGE_KILL)
	end
	return landed
end

-- Throw `t` away along `away` (flat, a little up). Bosses are too heavy to move.
local function shove(t: Target, away: Vector3, power: number)
	if t.character:GetAttribute("IsBoss") == true then return end
	local d = Vector3.new(away.X, 0, away.Z)
	d = if d.Magnitude > 0.05 then d.Unit else Vector3.xAxis
	pcall(function() t.rootPart:ApplyImpulse((d + Vector3.new(0, 0.35, 0)).Unit * t.rootPart.AssemblyMass * power) end)
end

local function stagger(t: Target, seconds: number)
	if t.character:GetAttribute("IsBoss") == true or Players:GetPlayerFromCharacter(t.character) then return end
	local untilT = os.clock() + seconds
	if (tonumber(t.character:GetAttribute("StaggerUntil")) or 0) < untilT then
		t.character:SetAttribute("StaggerUntil", untilT)
	end
end

-- Who his body passes during a run (`seconds` long, from now): each one once,
-- handed to `onHit`. Judged from where his body really goes (his game moves
-- him), the stretch since the last look, so a fast run skips no one.
local function sweepRun(char: Model, root: BasePart, seconds: number, width: number, onHit: (Target, Vector3) -> ())
	local struck: { [Model]: boolean } = {}
	local t0 = os.clock()
	local last = root.Position
	while os.clock() - t0 < seconds do
		if not char.Parent or not root.Parent then return end
		local now = root.Position
		local seg = Vector3.new(now.X - last.X, 0, now.Z - last.Z)
		for _, t in ipairs(H.getPotentialTargets(char)) do
			if struck[t.character] then continue end
			local rel = Vector3.new(t.rootPart.Position.X - last.X, 0, t.rootPart.Position.Z - last.Z)
			local along = if seg.Magnitude > 0.01 then math.clamp(rel:Dot(seg.Unit), 0, seg.Magnitude) else 0
			local side = rel - (if seg.Magnitude > 0.01 then seg.Unit * along else Vector3.zero)
			if side.Magnitude <= width and math.abs(t.rootPart.Position.Y - now.Y) < 10 then
				struck[t.character] = true
				onHit(t, side)
			end
		end
		last = now
		task.wait(0.04)
	end
end

-- ── M1: the greatsword / the claws ──────────────────────────────────────────
function BerserkerServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local isBeast = beast(player)
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1)
	local interval = if isBeast then CLAW_INTERVAL else SWING_INTERVAL
	if now - st.lastSwing < (interval / speed) * 0.85 then return end
	local chain = if isBeast then CLAWS else COMBO
	st.step = if now - st.lastSwing > (if isBeast then CLAW_RESET else COMBO_RESET) or st.step > #chain then 1 else (st.step % #chain) + 1
	st.lastSwing = now

	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local c: any = chain[st.step]
	local size = stat(player, "size") * (if isBeast then BEAST_SCALE else 1)
	local damage = c.damage * damageMult(player)
	local step = st.step
	local last = step == #chain
	fx({ kind = if isBeast then "claw" else "combo", attacker = player, step = step, dir = dir })
	-- The blow lands a beat after the wind-up.
	task.delay(if last then 0.2 else 0.1, function()
		if not char.Parent or not root.Parent then return end
		local hits = inRadius(char, root.Position, dir, c.range * size, c.dot)
		strike(player, hits, damage, c.source, c.heavy)
		if isBeast and last then
			for _, t in ipairs(hits) do stagger(t, 0.9) end
			fx({ kind = "maul", attacker = player, pos = root.Position + dir * 4, dir = dir, radius = c.range * size })
		elseif not isBeast and last then
			fx({ kind = "smash", attacker = player, pos = root.Position + dir * 3, radius = c.range * size })
		end
	end)
end

-- ── E: Rupture ──────────────────────────────────────────────────────────────
local function rupture(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, aimAt: Vector3?, config: any, empowered: boolean)
	local radius = (config.range or 14) * (config.areaMultiplier or 1) * (if empowered then 1.4 else 1)
	local damage = (config.damage or 75) * damageMult(player) * (if empowered then 1.5 else 1)
	st.busyUntil = os.clock() + RUPTURE.impact + 0.3
	-- Where he lands: the cursor (the client sends the exact spot), within reach.
	local from = root.Position
	local land = from + dir * 8
	if aimAt then
		local d = Vector3.new(aimAt.X - from.X, 0, aimAt.Z - from.Z)
		land = from + (if d.Magnitude > RUPTURE_RANGE + 6 then d.Unit * RUPTURE_RANGE else d)
	end
	fx({ kind = "rupture", attacker = player, dir = dir, land = land, radius = radius, empowered = empowered,
		t = RUPTURE })
	task.delay(RUPTURE.impact, function()
		if not char.Parent or not root.Parent then return end
		-- (the landing spot, not his replicated body: that trails, still in the air)
		local center = Vector3.new(land.X, from.Y, land.Z)
		fx({ kind = "ruptureImpact", attacker = player, pos = center, radius = radius, empowered = empowered })
		strike(player, inRadius(char, center, dir, radius, -1), damage, "RUPTURE", true)
		if empowered then
			-- Crimson spikes burst further out a moment later.
			task.delay(0.35, function()
				if not char.Parent then return end
				fx({ kind = "ruptureEcho", attacker = player, pos = center, radius = radius * 1.4 })
				strike(player, inRadius(char, center, dir, radius * 1.4, -1), damage * 0.6, "RUPTURE")
			end)
		end
	end)
end

-- ── F: Bloodstorm ───────────────────────────────────────────────────────────
-- He doesn't move: every swing is a crescent carved out in front of him, the
-- aim's way. The client times its poses (heave, hack, hold) from `swings`.
local function bloodstorm(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any, empowered: boolean)
	local area = (config.areaMultiplier or 1) * (if empowered then 1.2 else 1)
	local count = if empowered then STORM_HITS + 2 else STORM_HITS
	local damage = (config.damage or 30) * damageMult(player) * (if empowered then 1.3 else 1)
	local reach = STORM_SLASH * area
	local finalRadius = STORM_FINISH * area
	-- The timeline: each swing a little quicker than the last, a hit-stop after each.
	local t = STORM_WINDUP
	local dur = STORM_FIRST
	local swings = {}
	for i = 1, count do
		local strikeAt = t + dur
		table.insert(swings, { leave = t, arrive = strikeAt })
		t = strikeAt + STORM_FREEZE
		dur *= STORM_ACCEL
		task.delay(strikeAt, function()
			if not char.Parent or not root.Parent then return end
			local hits = inRadius(char, root.Position, dir, reach, STORM_ARC)
			strike(player, hits, damage, "BLOODSTORM")
			fx({ kind = "stormHit", attacker = player, pos = root.Position, dir = dir, radius = reach, i = i, hit = #hits > 0 })
		end)
	end
	local finalAt = t + 0.18
	st.busyUntil = os.clock() + finalAt + 0.35
	st.guardUntil = os.clock() + finalAt + 0.2
	fx({ kind = "storm", attacker = player, dir = dir, swings = swings, freeze = STORM_FREEZE, finalAt = finalAt,
		finalRadius = finalRadius, empowered = empowered })
	task.delay(finalAt, function()
		if not char.Parent or not root.Parent then return end
		local center = root.Position
		fx({ kind = "stormFinal", attacker = player, pos = center, radius = finalRadius, empowered = empowered })
		strike(player, inRadius(char, center, dir, finalRadius, -1), damage * 2.2, "BLOODSTORM FINISH", true)
	end)
end

-- ── Q: Crimson Charge ───────────────────────────────────────────────────────
-- He runs (his own game moves him: BerserkerController); here, everyone his
-- body passes is cut and thrown off the path, and at the end the burst.
-- Untouchable from the lean to the burst.
local function charge(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local area = config.areaMultiplier or 1
	local damage = (config.damage or 40) * damageMult(player)
	local total = CHARGE.windup + CHARGE.run
	st.busyUntil = os.clock() + total + 0.15
	char:SetAttribute("InvulnerableUntil", os.clock() + total + 0.25)
	local from = root.Position
	fx({ kind = "charge", attacker = player, from = from, dir = dir, dist = CHARGE_DIST, t = CHARGE })
	task.spawn(function()
		task.wait(CHARGE.windup)
		local struck: { [Model]: boolean } = {}
		sweepRun(char, root, CHARGE.run + 0.1, CHARGE_WIDTH * area, function(t, side)
			struck[t.character] = true
			strike(player, { t }, damage, "CRIMSON CHARGE")
			-- off to the side he's on, and on ahead
			shove(t, side.Unit * 0.8 + dir * 0.6, CHARGE_SHOVE)
		end)
		if not char.Parent or not root.Parent then return end
		-- The burst: everything near is blown away.
		local center = root.Position
		local r = CHARGE_BURST * area
		fx({ kind = "chargeEnd", attacker = player, pos = center, radius = r })
		local burst = {}
		for _, t in ipairs(inRadius(char, center, dir, r, -1)) do
			if not struck[t.character] then table.insert(burst, t) end
			shove(t, t.rootPart.Position - center, CHARGE_SHOVE * 1.2)
		end
		strike(player, burst, damage * 0.6, "CRIMSON CHARGE")
		-- (the rage carries into his next skill)
		player:SetAttribute("BR_Empowered", true)
	end)
end

-- ── R: Beast Awakening ──────────────────────────────────────────────────────
local function dropSword(player: Player, char: Model)
	for _, holder in ipairs({ char, player:FindFirstChildOfClass("Backpack") }) do
		local tool = holder and holder:FindFirstChild("Ragebringer")
		if tool then tool:Destroy() end
	end
end

-- Back to the man: down on his knees, the body shrinks, the sword reforms.
local function revert(player: Player, st: State)
	st.beastToken += 1 -- (anything still pending for the beast is off)
	player:SetAttribute("BR_BeastUntil", nil)
	local char = player.Character
	if not char then return end
	st.busyUntil = os.clock() + BEAST_REVERT
	fx({ kind = "revert", attacker = player, t = BEAST_REVERT })
	task.delay(BEAST_REVERT * 0.55, function()
		if player.Character ~= char or not char.Parent then return end
		pcall(function() char:ScaleTo(1) end)
		BerserkerLook.UndressBeast(char)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and st.jump then hum.JumpHeight = st.jump end
		st.jump = nil
		char:SetAttribute("SpeedMult", nil)
		WeaponManager.EquipWeapon(player, "berserker")
	end)
end

local function awaken(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	player:SetAttribute("BR_Rage", 0)
	st.beastToken += 1
	local token = st.beastToken
	st.busyUntil = os.clock() + BEAST.total + 0.1
	char:SetAttribute("InvulnerableUntil", os.clock() + BEAST.total + 0.3)
	fx({ kind = "awaken", attacker = player, dir = dir, t = BEAST })
	task.delay(BEAST.change, function()
		if st.beastToken ~= token or player.Character ~= char or not root.Parent then return end
		-- The sword is cast aside; the body tears open into the beast.
		dropSword(player, char)
		BerserkerLook.DressBeast(char)
		pcall(function() char:ScaleTo(BEAST_SCALE) end)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then
			st.jump = hum.JumpHeight
			hum.JumpHeight = hum.JumpHeight * BEAST_JUMP
		end
		char:SetAttribute("SpeedMult", BEAST_SPEED)
		player:SetAttribute("BR_BeastUntil", Workspace:GetServerTimeNow() + BEAST_TIME)
		-- The roar: a shockwave throws back everything near.
		local center = root.Position
		local r = BEAST_ROAR * (config.areaMultiplier or 1)
		fx({ kind = "roar", attacker = player, pos = center, radius = r })
		local hits = inRadius(char, center, dir, r, -1)
		for _, t in ipairs(hits) do shove(t, t.rootPart.Position - center, 55) end
		strike(player, hits, (config.damage or 160) * 0.4 * damageMult(player), "BEAST ROAR", true)
		task.delay(BEAST_TIME, function()
			if st.beastToken == token then revert(player, st) end
		end)
	end)
end

-- ── Beast E: Beast Slam ─────────────────────────────────────────────────────
local function beastSlam(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, aimAt: Vector3?, config: any)
	local area = (config.areaMultiplier or 1) * BEAST_SCALE
	local damage = (config.damage or 75) * damageMult(player) * 2
	st.busyUntil = os.clock() + SLAM.impact + 0.45
	char:SetAttribute("InvulnerableUntil", os.clock() + SLAM.impact + 0.1)
	local from = root.Position
	local land = from + dir * 10
	if aimAt then
		local d = Vector3.new(aimAt.X - from.X, 0, aimAt.Z - from.Z)
		land = from + (if d.Magnitude > SLAM_RANGE + 6 then d.Unit * SLAM_RANGE else d)
	end
	local token = st.beastToken
	fx({ kind = "beastSlam", attacker = player, dir = dir, land = land, t = SLAM })
	task.delay(SLAM.impact, function()
		if st.beastToken ~= token or not char.Parent or not root.Parent then return end
		local center = Vector3.new(land.X, from.Y, land.Z)
		-- Under him: crushed, and stunned.
		local under = inRadius(char, center, dir, SLAM_UNDER * area, -1)
		fx({ kind = "beastSlamImpact", attacker = player, pos = center, radius = SLAM_UNDER * area })
		strike(player, under, damage, "BEAST SLAM", true)
		for _, t in ipairs(under) do stagger(t, 1.6) end
		-- Then the three rings: knocked back, launched, and a last wave over it all.
		local inner = SLAM_UNDER * area
		for i, ring in ipairs(SLAM_RINGS) do
			local r0, r = inner, ring.radius * area
			inner = r
			task.delay(ring.at, function()
				if not char.Parent then return end
				fx({ kind = "beastRing", attacker = player, pos = center, radius = r, i = i })
				local hits = {}
				for _, t in ipairs(inRadius(char, center, dir, r, -1)) do
					local d = Vector3.new(t.rootPart.Position.X - center.X, 0, t.rootPart.Position.Z - center.Z).Magnitude
					if not ring.band or d > r0 then table.insert(hits, t) end
				end
				strike(player, hits, damage * ring.mult, ring.source)
			end)
		end
	end)
end

-- ── Beast F: Carnage ────────────────────────────────────────────────────────
local function bleed(player: Player, t: Target, total: number)
	task.spawn(function()
		for _ = 1, BLEED_TICKS do
			task.wait(BLEED_EVERY)
			if t.humanoid.Health <= 0 or not t.character.Parent then return end
			H.dealDamage(player, t, total / BLEED_TICKS, "BLEED")
		end
	end)
	fx({ kind = "bleed", attacker = player, model = t.character, duration = BLEED_TICKS * BLEED_EVERY })
end

local function carnage(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local area = (config.areaMultiplier or 1) * BEAST_SCALE
	local damage = (config.damage or 30) * damageMult(player) * 1.6
	local token = st.beastToken
	st.busyUntil = os.clock() + CARNAGE[3] + 0.35
	fx({ kind = "carnage", attacker = player, dir = dir, at = CARNAGE })
	local caught: { [Model]: number } = {}
	for i, at in ipairs(CARNAGE) do
		task.delay(at, function()
			if st.beastToken ~= token or not char.Parent or not root.Parent then return end
			local reach = CARNAGE_REACH[i] * area
			local hits = inRadius(char, root.Position, dir, reach, CARNAGE_DOT[i])
			fx({ kind = "carnageHit", attacker = player, pos = root.Position, dir = dir, radius = reach, i = i })
			if i < 3 then
				strike(player, hits, damage, "CARNAGE")
				for _, t in ipairs(hits) do
					caught[t.character] = (caught[t.character] or 0) + 1
					stagger(t, CARNAGE_STAGGER * caught[t.character])
				end
				return
			end
			-- The rake down: the biggest blow. Caught by all three: they bleed
			-- and are launched away.
			local finished, rest = {}, {}
			for _, t in ipairs(hits) do
				if (caught[t.character] or 0) >= 2 then table.insert(finished, t) else table.insert(rest, t) end
			end
			strike(player, rest, damage * 1.6, "CARNAGE", true)
			for _, t in ipairs(rest) do stagger(t, CARNAGE_STAGGER * ((caught[t.character] or 0) + 1)) end
			strike(player, finished, damage * 1.6, "CARNAGE FINISH", true)
			for _, t in ipairs(finished) do bleed(player, t, damage * 1.2) end
		end)
	end
end

-- ── Beast Q: Beast Charge ───────────────────────────────────────────────────
local function sizeOf(t: Target): number
	local ok, s = pcall(function() return t.character:GetExtentsSize() end)
	return if ok then (s :: Vector3).Magnitude else 0
end

local function beastCharge(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local area = (config.areaMultiplier or 1) * BEAST_SCALE
	local damage = (config.damage or 40) * damageMult(player) * 1.3
	local token = st.beastToken
	local runEnd = BCHARGE.crouch + BCHARGE.run
	st.busyUntil = os.clock() + runEnd + BCHARGE.grab + BCHARGE.throw + 0.1
	char:SetAttribute("InvulnerableUntil", os.clock() + runEnd + BCHARGE.grab + BCHARGE.throw + 0.2)
	fx({ kind = "beastCharge", attacker = player, from = root.Position, dir = dir, dist = BCHARGE_DIST, t = BCHARGE })
	task.spawn(function()
		task.wait(BCHARGE.crouch)
		-- Through everything: struck, staggered, shoved aside. The biggest is kept.
		local biggest: Target? = nil
		local biggestSize = 0
		sweepRun(char, root, BCHARGE.run + 0.08, BCHARGE_WIDTH * area, function(t, side)
			strike(player, { t }, damage, "BEAST CHARGE")
			stagger(t, 0.8)
			local size = sizeOf(t)
			if t.character:GetAttribute("IsBoss") ~= true and not Players:GetPlayerFromCharacter(t.character) and size > biggestSize then
				biggest, biggestSize = t, size
			end
			shove(t, side.Unit + dir * 0.3, 34)
		end)
		if st.beastToken ~= token or not char.Parent or not root.Parent then return end
		local victim = biggest
		if not victim or victim.humanoid.Health <= 0 or not victim.rootPart.Parent then
			st.busyUntil = os.clock() + 0.15
			return
		end
		-- The grab: hoisted overhead in his claws...
		local v = victim :: Target
		fx({ kind = "beastGrab", attacker = player, model = v.character, t = BCHARGE })
		local vr = v.rootPart
		vr.Anchored = true
		local t0 = os.clock()
		while os.clock() - t0 < BCHARGE.grab do
			if not vr.Parent or not root.Parent then break end
			local lift = math.min((os.clock() - t0) / (BCHARGE.grab * 0.6), 1)
			vr.CFrame = CFrame.new(root.Position + dir * 3 + Vector3.new(0, 3 + 5 * lift, 0)) * vr.CFrame.Rotation
			RunService.Heartbeat:Wait()
		end
		if not vr.Parent then return end
		-- ...and hurled forward into the rest.
		vr.Anchored = false
		pcall(function() vr:SetNetworkOwner(nil) end)
		vr.AssemblyLinearVelocity = dir * THROW_SPEED + Vector3.new(0, 24, 0)
		stagger(v, 1.4)
		strike(player, { v }, damage * 1.5, "BEAST THROW", true)
		fx({ kind = "beastThrow", attacker = player, model = v.character, dir = dir })
		local bowled: { [Model]: boolean } = { [v.character] = true }
		local t1 = os.clock()
		while os.clock() - t1 < 1.2 and vr.Parent do
			for _, t in ipairs(H.getPotentialTargets(char)) do
				if not bowled[t.character] and (t.rootPart.Position - vr.Position).Magnitude <= THROW_HIT then
					bowled[t.character] = true
					strike(player, { t }, damage, "BEAST THROW")
					stagger(t, 0.8)
					shove(t, t.rootPart.Position - vr.Position + dir, 40)
					fx({ kind = "throwHit", attacker = player, pos = t.rootPart.Position })
				end
			end
			task.wait(0.05)
		end
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function BerserkerServer.CanUseSkill(player: Player, skillIndex: number): boolean
	if os.clock() < getState(player).busyUntil then return false end
	-- The awakening needs a full meter (and he can't awaken twice).
	if skillIndex == 4 then return not beast(player) and rageOf(player) >= RAGE_MAX end
	return true
end

-- What his skills' cooldowns are multiplied by now (the beast's are halved).
function BerserkerServer.CooldownMult(player: Player): number
	return if beast(player) then BEAST_COOLDOWN else 1
end

function BerserkerServer.OnSkill(player: Player, char: Model, skillIndex: number, _origin: Vector3, dir: Vector3, config: any, aimAt: Vector3?)
	local st = getState(player)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	dir = flat(dir)
	if beast(player) then
		if skillIndex == 1 then
			beastSlam(player, char, st, root, dir, aimAt, config)
		elseif skillIndex == 2 then
			carnage(player, char, st, root, dir, config)
		elseif skillIndex == 3 then
			beastCharge(player, char, st, root, dir, config)
		end
		return
	end
	if skillIndex == 4 then
		awaken(player, char, st, root, dir, config)
		return
	end
	if skillIndex == 3 then
		charge(player, char, st, root, dir, config)
		return
	end
	local empowered = takeEmpowered(player)
	if empowered then fx({ kind = "empowered", attacker = player, skill = skillIndex }) end
	if skillIndex == 1 then
		rupture(player, char, st, root, dir, aimAt, config, empowered)
	elseif skillIndex == 2 then
		bloodstorm(player, char, st, root, dir, config, empowered)
	end
end

-- (the awakening's opening: mobs hold still while he transforms)
BerserkerServer.GATHER_TIME = BEAST.total

-- Fresh combo, no beast, an empty meter (new character / run).
function BerserkerServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil, st.guardUntil = 0, 0, 0, 0
	st.beastToken += 1
	st.jump = nil
	player:SetAttribute("BR_BeastUntil", nil)
	player:SetAttribute("BR_Empowered", nil)
	player:SetAttribute("BR_Rage", 0)
end

function BerserkerServer.Init(helpers: any)
	H = helpers
	if helpers.addIncomingHook then
		helpers.addIncomingHook(function(player: Player, char: Model, damage: number): number
			local st = states[player]
			-- Bloodstorm: half damage while storming.
			if st and os.clock() < st.guardUntil then damage *= STORM_GUARD end
			-- Every hit he takes feeds the rage.
			if player:GetAttribute("SelectedClass") == "berserker" and damage > 0 then
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum and hum.MaxHealth > 0 then addRage(player, damage / hum.MaxHealth * RAGE_HURT) end
			end
			return damage
		end)
	end
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function()
			if p:GetAttribute("SelectedClass") == "berserker" then BerserkerServer.Reset(p) end
		end)
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
end

return BerserkerServer
