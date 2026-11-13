--!strict
--[[
	MartialServer.luau
	Server side of the Martial Artist, "Flow · Strike · Master" (client:
	MartialController). Every hit and all state is decided here; clients get
	the moments to draw over MartialFX. The palette (the class sheet): crimson
	energy and black ink.

	  M1 Flowing Fists     a 7-hit chain, fast and relentless: jab, cross, high
	                       kick (pops them up), spinning strike (all round him),
	                       elbow, palm strike (a burst of Qi that shoves), and a
	                       flying knee driven into the ground (an eruption all
	                       round the landing); then a beat to recover.
	  Passive              Qi Charge (MA_Charge, 0–100): abilities build it
	                       (Focus Strike +20, Electric Uppercut +15, Ground
	                       Slam +20, Dragon Soul +30) and so do landed
	                       strikes (+2). At 100 the next ability is Empowered
	                       and uses it up.
	  E Hundred Fists      a barrage: both fists hammering out a storm of
	                       blows (afterimages of fists flying), everything in
	                       front of him hit again and again and held there;
	                       then one enhanced power punch that blasts a cone
	                       out in front, a crater torn into the floor along it,
	                       everything in it hit hard and thrown back.
	                       Empowered: harder, and a longer cone.
	                       (The old Focus Strike's hold-and-release is below,
	                       no longer cast.)
	  F Electric Uppercut  a crouch dash in and a rising uppercut (the Wind
	                       God Fist): everything in front of him is hit,
	                       launched into the air and shocked for a moment. Empowered (and each extra
	                       Projectile): the lightning chains on to more enemies.
	  Q Ground Slam        Qi lifts him up, he dives onto the aim, crashes down
	                       in an explosion and leaves a burning trail.
	                       Empowered: three strikes along the path, a wider
	                       landing and trail.
	  R Dragon Soul        he roars and a crimson Qi dragon spirals up out of
	                       the floor round him (the ult's cinematic), bursting
	                       out through everything near. For `duration`
	                       seconds he attacks DRAGON.speed× faster, and the
	                       dragon coils round him and lashes out along every
	                       strike he throws, hitting everything in its lane.
	                       Empowered: lasts longer, lashes harder.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local MartialLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MartialLook"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local MartialServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local COMBO_INTERVAL = 0.3    -- seconds between strikes at 1× attack speed
local COMBO_RESET = 1.0       -- the combo starts over after this long without a strike
-- The chain: jab, cross, high kick, spinning strike, elbow, palm, knee.
local COMBO_DAMAGE = { 16, 16, 22, 22, 24, 26, 40 }
-- (each strike drives a blast of air out to its reach: the client draws it
-- this long, MartialController's COMBO_RANGE)
local COMBO_RANGE = { 10, 10, 11, 10, 8.5, 10, 0 }
local COMBO_SOURCE = { "FLOWING FISTS", "FLOWING FISTS", "HIGH KICK", "SPINNING STRIKE", "ELBOW STRIKE", "PALM STRIKE", "POWER KNEE" }
local COMBO_ARC = math.cos(math.rad(65))
local COMBO_STEPS = 7
local PALM_RADIUS = 7.5       -- the palm strike's burst of Qi
local PALM_AT = 5             -- (that far in front of him)
local FINISH_RADIUS = 9.5     -- the knee's eruption round where it lands
local FINISH_LAND = 0.16      -- seconds from the click to the knee hitting the floor
local RECOVER = 0.5           -- the finisher, then back to guard: no strikes till then

local CHARGE_MAX = 100
local CHARGE_GAIN = { 20, 15, 20, 30 } -- per ability
local CHARGE_PER_HIT = 2               -- per strike that lands (once per swing)

-- Focus Strike (matches the client): fully charged after `full` seconds
-- (Empowered: `empFull`), off on its own after `hold`; the fist lands `hit`
-- after the release. Reach, lunge and damage grow with the charge, up to
-- `maxMult` × the damage.
local FOCUS = { full = 1.1, empFull = 0.55, hold = 2.4, hit = 0.08, reach = 7, fullReach = 11, lunge = 1.5, fullLunge = 6,
	maxMult = 3.5, splash = 8, arc = math.cos(math.rad(55)) }
local FOCUS_EMP = { damage = 1.3, splash = 1.4 }

-- Hundred Fists (matches the client): the barrage for `duration`, a hit to
-- everything in front every `every` seconds (`tick` × the damage each); the
-- power punch lands at `punchAt` (`punch` × the damage), its cone `cone`
-- studs long and `half` wide either side; back to guard at `total`.
local BARRAGE = { duration = 1.1, every = 0.1, reach = 9, arc = math.cos(math.rad(45)), tick = 0.2,
	punchAt = 1.32, total = 1.65, cone = 18, half = math.rad(36), punch = 2.4 }
local BARRAGE_EMP = { damage = 1.3, cone = 1.3 }

-- Electric Uppercut (matches the client): a long crouch dash in (up to `dash`
-- studs, stopping short at the first enemy in its path: that one takes the
-- uppercut), the uppercut landing `hit` in, back on his feet at `total`;
-- everything struck is launched and shocked for `stun`; chained lightning
-- jumps up to `chain` studs.
local UPPER = { hit = 0.27, total = 0.62, dash = 24, lane = 3.5, stopShort = 2.5, arc = math.cos(math.rad(70)), launch = 55, liftHold = 0.16, stun = 1.3, chain = 16,
	empChains = 4, chainStun = 0.6 }

-- Haymaker (Q, matches the client; after the reference clip, which was
-- stepped through frame by frame): he stands his ground and charges (full
-- after `full` seconds, Empowered `empFull`; off on its own after `hold`),
-- a lane marked out on the floor ahead growing `length`..`fullLength` studs
-- long as it charges. On release the punch drives a wave down the lane: its
-- front reaches the end in `travel` seconds, hitting everything within `half`
-- of the lane's line as it passes (up to `maxMult`x the damage at full
-- charge), blasting them on along it. Behind it a row of glassy arcs bursts
-- up every `gap` studs (`eruptRadius` round, `eruptMult`x, popping them up),
-- `after` seconds behind the front.
local HAY = { full = 1.0, empFull = 0.5, hold = 2.2, length = 12, fullLength = 30, half = 3.2, travel = 0.3,
	maxMult = 3.2, gap = 5, after = 0.12, eruptRadius = 4.2, eruptMult = 0.45 }
local HAY_EMP = { damage = 1.3, length = 1.2 }

-- Ground Slam (no longer cast: Q is the Haymaker; kept for reference)
local ASCENT = { rise = 0.3, dash = 0.08, fall = 0.22 } -- the leap up, the beat at the top, the dive
local ASCENT_TRAIL = 2.5      -- seconds the trail burns
local ASCENT_TICK = 0.5
local ASCENT_WIDTH = 4

-- Dragon Soul (matches the client): the summoning takes `rise` seconds (the
-- ult's cinematic: mobs held still, him untouchable), then the roar bursts
-- out `burst` studs round him. For `duration` seconds (Empowered: × `emp`)
-- his strikes come `speed`× faster and every one sends the dragon lashing
-- `reach` studs along it (`width` either side), `delay` after the strike,
-- for `lash` × the strike's damage (Empowered: `empLash`).
local DRAGON = { rise = 1.1, duration = 10, emp = 1.4, speed = 1.6, reach = 15, width = 3.2, delay = 0.1, lash = 0.7, empLash = 0.9,
	burst = 14 }


-- ── State ───────────────────────────────────────────────────────────────────
type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type Focus = { t0: number, empowered: boolean, config: any, token: {}, kind: string? }
type State = {
	charge: number,
	step: number,
	lastSwing: number,
	busyUntil: number,
	focus: Focus?,
	pendingRelease: { at: number, held: number?, dir: Vector3? }?,
	dragonUntil: number,
	dragonEmp: boolean,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { charge = 0, step = 0, lastSwing = 0, busyUntil = 0, dragonUntil = 0, dragonEmp = false }
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

-- Everyone in front of `at` along `dir`, within `reach` and the cone `arc`
-- (the cosine of its half-angle); right up close counts whatever the angle.
local function inFront(char: Model, at: Vector3, dir: Vector3, reach: number, arc: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = Vector3.new(t.rootPart.Position.X - at.X, 0, t.rootPart.Position.Z - at.Z)
		if d.Magnitude <= reach + H.lineReach(t, 0) * 0.5 and math.abs(t.rootPart.Position.Y - at.Y) < 7
			and (d.Magnitude < 2.5 or dir:Dot(d.Unit) >= arc) then
			table.insert(out, t)
		end
	end
	return out
end

local function isBoss(t: Target): boolean
	return t.character:GetAttribute("IsBoss") == true
end

-- Pushed `power` studs/s away (and `lift` × that up): held for a moment
-- through SkillManager's knock, so a walking mob can't shrug it off.
local function shove(t: Target, away: Vector3, power: number, lift: number?)
	if isBoss(t) then return end
	local d = Vector3.new(away.X, 0, away.Z)
	d = if d.Magnitude > 0.05 then d.Unit else Vector3.xAxis
	local u = (d + Vector3.new(0, lift or 0.3, 0)).Unit * power
	H.knock(t, Vector3.new(u.X, 0, u.Z), u.Y)
end

local function hold(t: Target, seconds: number)
	if isBoss(t) then return end
	local untilT = os.clock() + seconds
	if (tonumber(t.character:GetAttribute("StaggerUntil")) or 0) < untilT then
		t.character:SetAttribute("StaggerUntil", untilT)
	end
end

-- Shocked: frozen where they are for `seconds` (not bosses).
local function shock(t: Target, seconds: number)
	if isBoss(t) then return end
	local untilT = os.clock() + seconds
	local m = t.character
	m:SetAttribute("StaggerUntil", math.max(tonumber(m:GetAttribute("StaggerUntil")) or 0, untilT))
	m:SetAttribute("StunnedUntil", math.max(tonumber(m:GetAttribute("StunnedUntil")) or 0, untilT))
end

-- The uppercut's knock-up: an upward drive held a moment (a velocity set once
-- is lost to the mob's own walking), then it flies on and falls back.
local function launchUp(t: Target, dir: Vector3)
	local root = t.rootPart
	if root.Anchored then return end
	pcall(function() t.humanoid:MoveTo(root.Position) end)
	local old = root:FindFirstChild("UppercutLift")
	if old then old:Destroy() end
	local att = Instance.new("Attachment")
	att.Name = "UppercutLift"
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = math.huge
	lv.VectorVelocity = Vector3.new(dir.X * 6, UPPER.launch, dir.Z * 6)
	lv.Parent = att
	att.Parent = root
	task.delay(UPPER.liftHold, function()
		if att.Parent then att:Destroy() end
	end)
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

local function positions(list: { Target }): { Vector3 }
	local out = {}
	for _, t in ipairs(list) do table.insert(out, t.rootPart.Position) end
	return out
end

-- ── R: Dragon Soul ──────────────────────────────────────────────────────────
local function dragonOn(st: State): boolean
	return os.clock() < st.dragonUntil
end

-- The dragon lashes out along a strike thrown `dir` from `from`.
local function dragonLash(player: Player, char: Model, from: Vector3, dir: Vector3, damage: number, st: State)
	if not dragonOn(st) then return end
	local size = stat(player, "size")
	local reach = DRAGON.reach * size
	local mult = if st.dragonEmp then DRAGON.empLash else DRAGON.lash
	if H.fxAllowed(player, "maDragonLash", 10) then
		fx({ kind = "dragonLash", attacker = player, dir = dir, reach = reach })
	end
	task.delay(DRAGON.delay, function()
		if not char.Parent then return end
		for _, t in ipairs(alongSegment(char, from, from + dir * reach, DRAGON.width * size)) do
			hit(player, t, damage * mult, "DRAGON SOUL")
		end
	end)
end

-- ── M1: Flowing Fists ───────────────────────────────────────────────────────
function MartialServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1) * (if dragonOn(st) then DRAGON.speed else 1)
	if now - st.lastSwing < COMBO_INTERVAL / speed - 0.06 then return end
	if now - st.lastSwing > COMBO_RESET then st.step = 0 end
	st.step = st.step % COMBO_STEPS + 1
	st.lastSwing = now
	local step = st.step
	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local damage = COMBO_DAMAGE[step] * stat(player, "damage")
	local size = stat(player, "size")
	local source = COMBO_SOURCE[step]
	local landed = false
	local struck: { Target } = {}

	if step == COMBO_STEPS then
		-- The flying knee: it lands a moment later, an eruption all round where
		-- it comes down; then he recovers to guard before the chain starts over.
		st.busyUntil = now + RECOVER / speed
		st.step = 0
		local at = root.Position + dir * 2.5
		fx({ kind = "strike", attacker = player, step = step, pos = root.Position, dir = dir, landed = false,
			palm = at, radius = FINISH_RADIUS * size })
		dragonLash(player, char, root.Position, dir, damage, st)
		task.delay(FINISH_LAND / speed, function()
			if not char.Parent then return end
			local any = false
			for _, t in ipairs(inRadius(char, at, FINISH_RADIUS * size)) do
				if hit(player, t, damage, source) then
					any = true
					table.insert(struck, t)
				end
			end
			if any then
				gainCharge(player, st, CHARGE_PER_HIT)
				pcall(H.ricochet, player, char, struck[1], damage, source)
				fx({ kind = "strikeLanded", attacker = player, step = step, pos = root.Position, dir = dir })
			end
		end)
		return
	end

	local reach = COMBO_RANGE[step] * size
	-- (the spinning strike hits all the way round him; the elbow is close but wide)
	local spin = step == 4
	local arc = if step == 5 then math.cos(math.rad(90)) else COMBO_ARC
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = Vector3.new(t.rootPart.Position.X - root.Position.X, 0, t.rootPart.Position.Z - root.Position.Z)
		if d.Magnitude <= reach + H.lineReach(t, 0) * 0.5 and math.abs(t.rootPart.Position.Y - root.Position.Y) < 6
			and (spin or d.Magnitude < 2 or dir:Dot(d.Unit) >= arc) then
			-- (the knockback, the high kick's pop-up, the stagger and the white
			-- flash come with the hit: SkillManager's impact profile per strike)
			if hit(player, t, damage, source) then
				landed = true
				table.insert(struck, t)
			end
		end
	end
	-- the palm strike: a burst of Qi in front of him
	local palmAt = root.Position + dir * PALM_AT
	if step == 6 then
		local already: { [Model]: boolean } = {}
		for _, t in ipairs(struck) do already[t.character] = true end
		for _, t in ipairs(inRadius(char, palmAt, PALM_RADIUS * size)) do
			if not already[t.character] then
				if hit(player, t, damage * 0.6, "QI PALM") then landed = true end
			end
		end
	end
	if landed then
		gainCharge(player, st, CHARGE_PER_HIT)
		if #struck > 0 then pcall(H.ricochet, player, char, struck[1], damage, source) end
	end
	fx({ kind = "strike", attacker = player, step = step, pos = root.Position, dir = dir, landed = landed, reach = reach,
		palm = if step == 6 then palmAt else nil, radius = PALM_RADIUS * size })
	dragonLash(player, char, root.Position, dir, damage, st)
end

-- ── E: Focus Strike ─────────────────────────────────────────────────────────
-- The release: `held` is how long the client says the key was down (never
-- more than the server has seen), `aim` where the fist goes.
local haymakerRelease: (Player, Focus, number?, Vector3?) -> ()
local function focusRelease(player: Player, held: number?, aim: Vector3?)
	local st = getState(player)
	local f = st.focus
	if not f then return end
	st.focus = nil
	if f.kind == "haymaker" then
		haymakerRelease(player, f, held, aim)
		return
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and root) then
		st.busyUntil = 0
		return
	end
	local now = os.clock()
	local elapsed = now - f.t0
	local h = math.clamp(tonumber(held) or elapsed, 0, elapsed + 0.15)
	local c = math.clamp(h / (if f.empowered then FOCUS.empFull else FOCUS.full), 0, 1)
	local full = c >= 0.999
	local config = f.config
	local area = config.areaMultiplier or 1
	local dir = flat(if typeof(aim) == "Vector3" then aim else root.CFrame.LookVector)
	local lunge = clearDistance(char, root.Position, dir, FOCUS.lunge + (FOCUS.fullLunge - FOCUS.lunge) * c)
	local reach = (FOCUS.reach + (FOCUS.fullReach - FOCUS.reach) * c) * area
	local damage = (config.damage or 70) * (1 + (FOCUS.maxMult - 1) * c) * (if f.empowered then FOCUS_EMP.damage else 1)
	local splash = FOCUS.splash * area * (if f.empowered then FOCUS_EMP.splash else 1)
	local origin = root.Position
	-- (the fist lands a beat after the release: busy till he's recovered)
	st.busyUntil = now + FOCUS.hit + 0.3
	fx({ kind = "focusRelease", attacker = player, pos = origin, dir = dir, charge = c, full = full, lunge = lunge,
		reach = reach, splash = splash, empowered = f.empowered })
	task.delay(FOCUS.hit, function()
		if not char.Parent then return end
		local at = origin + dir * lunge
		local struck: { Target } = {}
		local seen: { [Model]: boolean } = {}
		for _, t in ipairs(inFront(char, at, dir, reach, FOCUS.arc)) do
			seen[t.character] = true
			if hit(player, t, damage, if full then "FOCUS STRIKE!" else "FOCUS STRIKE") then
				table.insert(struck, t)
				hold(t, 0.3 + 0.4 * c)
				shove(t, dir, 22 + 40 * c, 0.3 + 0.3 * c)
			end
		end
		-- fully charged: the ink splash bursts round where the fist lands
		local splashAt = at + dir * math.min(reach * 0.55, 5)
		if full then
			for _, t in ipairs(inRadius(char, splashAt, splash)) do
				if not seen[t.character] and hit(player, t, damage * 0.6, "INK SPLASH") then
					table.insert(struck, t)
					hold(t, 0.5)
					shove(t, t.rootPart.Position - splashAt, 38, 0.5)
				end
			end
		end
		if #struck > 0 then pcall(H.ricochet, player, char, struck[1], damage, "FOCUS STRIKE") end
		fx({ kind = "focusLanded", attacker = player, pos = at, dir = dir, full = full, charge = c, at = splashAt,
			splash = splash, hits = positions(struck) })
	end)
end

local function focusStart(player: Player, config: any, empowered: boolean)
	local st = getState(player)
	local now = os.clock()
	local token = {}
	st.focus = { t0 = now, empowered = empowered, config = config, token = token }
	st.busyUntil = math.max(st.busyUntil, now + FOCUS.hold + 0.4)
	fx({ kind = "focusCharge", attacker = player, empowered = empowered,
		full = if empowered then FOCUS.empFull else FOCUS.full, hold = FOCUS.hold })
	-- (a release that got here ahead of the cast: a tap)
	local pend = st.pendingRelease
	st.pendingRelease = nil
	if pend and now - pend.at < 0.6 then
		focusRelease(player, pend.held, pend.dir)
		return
	end
	task.delay(FOCUS.hold, function()
		local f = st.focus
		if f and f.token == token then focusRelease(player, FOCUS.hold, nil) end
	end)
end

-- ── E: Hundred Fists ────────────────────────────────────────────────────────
local function barrage(player: Player, char: Model, root: BasePart, dir: Vector3, config: any, empowered: boolean)
	local st = getState(player)
	local now = os.clock()
	st.busyUntil = math.max(st.busyUntil, now + BARRAGE.total)
	local area = config.areaMultiplier or 1
	local damage = (config.damage or 70) * (if empowered then BARRAGE_EMP.damage else 1)
	local cone = BARRAGE.cone * area * (if empowered then BARRAGE_EMP.cone else 1)
	fx({ kind = "barrage", attacker = player, pos = root.Position, dir = dir, cone = cone, half = BARRAGE.half, empowered = empowered })
	task.spawn(function()
		local t0 = os.clock()
		-- the barrage: blow after blow, everything in front held in it
		while char.Parent and root.Parent and os.clock() - t0 < BARRAGE.duration do
			for _, t in ipairs(inFront(char, root.Position, dir, BARRAGE.reach * area, BARRAGE.arc)) do
				if hit(player, t, damage * BARRAGE.tick, "BARRAGE") then hold(t, 0.3) end
			end
			task.wait(BARRAGE.every)
		end
		local left = BARRAGE.punchAt - (os.clock() - t0)
		if left > 0 then task.wait(left) end
		if not (char.Parent and root.Parent) then return end
		-- the power punch: everything in the cone hit hard and thrown back
		local at = root.Position
		local struck: { Target } = {}
		for _, t in ipairs(H.getPotentialTargets(char)) do
			local rel = Vector3.new(t.rootPart.Position.X - at.X, 0, t.rootPart.Position.Z - at.Z)
			local d = rel.Magnitude
			if d <= cone + H.lineReach(t, 0) * 0.5 and math.abs(t.rootPart.Position.Y - at.Y) < 8
				and (d < 3 or math.acos(math.clamp(rel.Unit:Dot(dir), -1, 1)) <= BARRAGE.half + math.rad(4)) then
				if hit(player, t, damage * BARRAGE.punch, "POWER PUNCH") then
					table.insert(struck, t)
					hold(t, 0.4)
					if not isBoss(t) then shove(t, dir, 60, 0.35) end
				end
			end
		end
		if #struck > 0 then pcall(H.ricochet, player, char, struck[1], damage * BARRAGE.punch, "POWER PUNCH") end
		fx({ kind = "barragePunch", attacker = player, pos = at, dir = dir, cone = cone, half = BARRAGE.half, hits = positions(struck) })
	end)
end

-- ── F: Electric Uppercut ────────────────────────────────────────────────────
local function uppercut(player: Player, char: Model, root: BasePart, dir: Vector3, config: any, empowered: boolean)
	local st = getState(player)
	local now = os.clock()
	st.busyUntil = math.max(st.busyUntil, now + UPPER.total)
	local area = config.areaMultiplier or 1
	local reach = (config.range or 7) * area
	local damage = config.damage or 65
	local origin = root.Position
	local dash = clearDistance(char, origin, dir, UPPER.dash)
	-- the first enemy in the dash's lane stops it, just short of them
	local first: Target? = nil
	local firstAlong = math.huge
	for _, t in ipairs(H.getPotentialTargets(char)) do
		if t.humanoid.Health <= 0 then continue end
		local rel = Vector3.new(t.rootPart.Position.X - origin.X, 0, t.rootPart.Position.Z - origin.Z)
		local along = rel:Dot(dir)
		local across = (rel - dir * along).Magnitude
		if along > 0 and along <= dash + UPPER.stopShort and across <= UPPER.lane + H.lineReach(t, 0) * 0.5
			and math.abs(t.rootPart.Position.Y - origin.Y) < 7 and along < firstAlong then
			first, firstAlong = t, along
		end
	end
	if first then dash = math.clamp(firstAlong - UPPER.stopShort, 0, dash) end
	fx({ kind = "uppercut", attacker = player, pos = origin, dir = dir, dash = dash, empowered = empowered, reach = reach })
	task.delay(UPPER.hit, function()
		if not char.Parent then return end
		local at = origin + dir * dash
		local struck: { Target } = {}
		local targets = inFront(char, at, dir, reach, UPPER.arc)
		-- (the one it stopped on always takes it, even if it moved a little)
		if first and first.humanoid.Health > 0 then
			local has = false
			for _, t in ipairs(targets) do
				if t.character == first.character then has = true end
			end
			if not has then table.insert(targets, 1, first) end
		end
		for _, t in ipairs(targets) do
			if hit(player, t, damage, "ELECTRIC UPPERCUT") then
				table.insert(struck, t)
				shock(t, UPPER.stun)
				-- (knocked up: driven straight up, a little away, for a moment, then
				-- falling back on their own; bosses only take the hit)
				if not isBoss(t) then launchUp(t, dir) end
			end
		end
		-- the lightning chains on from the first struck to the nearest enemy
		-- not yet hit, and on from there
		local links: { { Vector3 } } = {}
		local chains = (if empowered then UPPER.empChains else 0) + math.max(0, math.floor(config.projectileCount or 0))
		if chains > 0 and #struck > 0 then
			local seen: { [Model]: boolean } = {}
			for _, t in ipairs(struck) do seen[t.character] = true end
			local from = struck[1]
			for _ = 1, chains do
				local best: Target? = nil
				local bestD = UPPER.chain
				for _, t in ipairs(H.getPotentialTargets(char)) do
					if not seen[t.character] and t.humanoid.Health > 0 then
						local dd = (t.rootPart.Position - from.rootPart.Position).Magnitude
						if dd < bestD then best, bestD = t, dd end
					end
				end
				if not best then break end
				seen[best.character] = true
				table.insert(links, { from.rootPart.Position, best.rootPart.Position })
				if hit(player, best, damage * 0.6, "CHAIN LIGHTNING") then shock(best, UPPER.chainStun) end
				from = best
			end
		end
		if #struck > 0 then pcall(H.ricochet, player, char, struck[1], damage, "ELECTRIC UPPERCUT") end
		fx({ kind = "uppercutHit", attacker = player, pos = at, dir = dir, hits = positions(struck), links = links })
	end)
end

-- ── Q: Haymaker ─────────────────────────────────────────────────────────────
local function haymakerStart(player: Player, config: any, empowered: boolean)
	local st = getState(player)
	local now = os.clock()
	local token = {}
	st.focus = { t0 = now, empowered = empowered, config = config, token = token, kind = "haymaker" }
	st.busyUntil = math.max(st.busyUntil, now + HAY.hold + 0.5)
	fx({ kind = "haymakerCharge", attacker = player, empowered = empowered,
		full = if empowered then HAY.empFull else HAY.full, hold = HAY.hold })
	-- (a release that got here ahead of the cast: a tap)
	local pend = st.pendingRelease
	st.pendingRelease = nil
	if pend and now - pend.at < 0.6 then
		focusRelease(player, pend.held, pend.dir)
		return
	end
	task.delay(HAY.hold, function()
		local f = st.focus
		if f and f.token == token then focusRelease(player, HAY.hold, nil) end
	end)
end

haymakerRelease = function(player: Player, f: Focus, held: number?, aim: Vector3?)
	local st = getState(player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and root) then
		st.busyUntil = 0
		return
	end
	local now = os.clock()
	local elapsed = now - f.t0
	local h = math.clamp(tonumber(held) or elapsed, 0, elapsed + 0.15)
	local c = math.clamp(h / (if f.empowered then HAY.empFull else HAY.full), 0, 1)
	local full = c >= 0.999
	local config = f.config
	local area = config.areaMultiplier or 1
	local dir = flat(if typeof(aim) == "Vector3" then aim else root.CFrame.LookVector)
	local origin = root.Position
	-- the lane: longer the harder it was charged (and with Size / area)
	local length = (HAY.length + (HAY.fullLength - HAY.length) * c) * area * (if f.empowered then HAY_EMP.length else 1)
	local half = HAY.half * area
	local damage = (config.damage or 80) * (1 + (HAY.maxMult - 1) * c) * (if f.empowered then HAY_EMP.damage else 1)
	st.busyUntil = now + 0.45
	fx({ kind = "haymakerRelease", attacker = player, pos = origin, dir = dir, charge = c, full = full, length = length,
		half = half, empowered = f.empowered })
	-- the wave down the lane: each enemy hit as its front passes them
	local seen: { [Model]: boolean } = {}
	local first: Target? = nil
	for _, t in ipairs(alongSegment(char, origin, origin + dir * length, half)) do
		local rel = t.rootPart.Position - origin
		local along = math.clamp(Vector3.new(rel.X, 0, rel.Z):Dot(dir), 0, length)
		task.delay(HAY.travel * along / length, function()
			if not char.Parent or seen[t.character] then return end
			seen[t.character] = true
			if hit(player, t, damage, if full then "HAYMAKER!" else "HAYMAKER") then
				first = first or t
				hold(t, 0.3 + 0.3 * c)
				if not isBoss(t) then shove(t, dir, 40 + 50 * c, 0.25 + 0.3 * c) end
			end
		end)
	end
	-- the row of glassy arcs bursting up behind the front
	local n = math.max(1, math.floor(length / HAY.gap))
	for i = 1, n do
		local d = i * length / n
		task.delay(HAY.travel * d / length + HAY.after, function()
			if not char.Parent then return end
			local p = floorAt(char, origin + dir * d)
			for _, t in ipairs(inRadius(char, p, HAY.eruptRadius * area)) do
				if hit(player, t, damage * HAY.eruptMult, "HAYMAKER WAVE") and not isBoss(t) then launchUp(t, dir) end
			end
		end)
	end
	task.delay(HAY.travel + 0.05, function()
		local f1 = first
		if f1 and char.Parent then pcall(H.ricochet, player, char, f1, damage, "HAYMAKER") end
	end)
end

-- ── (old) Q: Ground Slam ────────────────────────────────────────────────────
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
	-- the strike: everything on the path, as he dives (Empowered: three
	-- strikes, three hits)
	task.delay(ASCENT.rise + ASCENT.dash + ASCENT.fall * 0.5, function()
		if not char.Parent then return end
		local hits = if empowered then 3 else 1
		for n = 1, hits do
			for _, t in ipairs(alongSegment(char, from, land, width)) do
				if hit(player, t, damage * (if empowered then 0.6 else 1), "GROUND SLAM") then hold(t, 0.4) end
			end
			if n < hits then task.wait(0.12) end
		end
	end)
	-- the landing
	task.delay(total, function()
		if not char.Parent then return end
		for _, t in ipairs(inRadius(char, land, radius)) do
			hit(player, t, damage * 1.2, "GROUND SLAM")
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

-- ── R: Dragon Soul (the summoning) ─────────────────────────────────────────
local function dragonSoul(player: Player, char: Model, root: BasePart, dir: Vector3, config: any, empowered: boolean)
	local st = getState(player)
	local now = os.clock()
	local duration = (config.duration or DRAGON.duration) * (if empowered then DRAGON.emp else 1)
	-- (held through the summoning, untouchable)
	st.busyUntil = now + DRAGON.rise
	char:SetAttribute("InvulnerableUntil", math.max(tonumber(char:GetAttribute("InvulnerableUntil")) or 0, now + DRAGON.rise + 0.2))
	fx({ kind = "dragonSoul", attacker = player, pos = root.Position, dir = dir, rise = DRAGON.rise, duration = duration })
	task.delay(DRAGON.rise, function()
		if not char.Parent then return end
		st.dragonUntil = os.clock() + duration
		st.dragonEmp = empowered
		player:SetAttribute("MA_DragonUntil", Workspace:GetServerTimeNow() + duration)
		-- the roar: it bursts out through everything round him
		local at = root.Position
		local r = DRAGON.burst * (config.areaMultiplier or 1)
		local damage = (config.damage or 160) * (if empowered then 1.3 else 1)
		for _, t in ipairs(inRadius(char, at, r)) do
			hit(player, t, damage, "DRAGON SOUL")
			shove(t, t.rootPart.Position - at, 40, 0.5)
		end
	end)
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
		barrage(player, char, root, dir, config, empowered)
	elseif skillIndex == 2 then
		uppercut(player, char, root, dir, config, empowered)
	elseif skillIndex == 3 then
		haymakerStart(player, config, empowered)
	elseif skillIndex == 4 then
		dragonSoul(player, char, root, dir, config, empowered)
	end
	gainCharge(player, st, CHARGE_GAIN[skillIndex] or 0)
end

-- Seconds the Dragon Soul's cinematic (the summoning) holds mobs still.
MartialServer.ULT_WINDUP = DRAGON.rise

function MartialServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil = 0, 0, 0
	st.focus, st.pendingRelease = nil, nil
	st.dragonUntil, st.dragonEmp = 0, false
	player:SetAttribute("MA_DragonUntil", nil)
	setCharge(player, st, 0)
end

local function onCharacter(p: Player, char: Model)
	if p:GetAttribute("SelectedClass") ~= "martial_artist" then
		MartialLook.Undress(char)
		return
	end
	MartialServer.Reset(p)
	task.defer(function()
		-- (the gi is armor: worn while equipped, the "Fighter's Gi" reward)
		if char.Parent and char:WaitForChild("Head", 5) and char:WaitForChild("Torso", 5) and p:GetAttribute("Armor_martial_artist") == true then
			MartialLook.Dress(char)
		end
	end)
end

function MartialServer.Init(helpers: any)
	-- (a dash cuts the move short: free to act again, and what was left of it doesn't land)
	(require(script.Parent:WaitForChild("Dash")) :: any).OnDash(function(p: Player)
		local st = states[p] :: any
		if not st then return end
		st.busyUntil = 0
		if type(st.token) == "number" then st.token += 1 end
		-- (a charging Haymaker is dropped: no punch goes off later)
		st.focus = nil
	end)
	H = helpers
	-- The Focus Strike's key let go (or a tap that beat the cast here).
	Network.GetRemoteEvent(Network.Remotes.MartialInput).OnServerEvent:Connect(function(player: Player, msg: any)
		if typeof(msg) ~= "table" or msg.kind ~= "release" then return end
		if player:GetAttribute("SelectedClass") ~= "martial_artist" then return end
		local held = tonumber(msg.held)
		local dir = if typeof(msg.dir) == "Vector3" then msg.dir else nil
		local st = getState(player)
		if st.focus then
			focusRelease(player, held, dir)
		else
			st.pendingRelease = { at = os.clock(), held = held, dir = dir }
		end
	end)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function(c) onCharacter(p, c) end)
		p:GetAttributeChangedSignal("SelectedClass"):Connect(function()
			if p.Character then onCharacter(p, p.Character) end
		end)
		p:GetAttributeChangedSignal("Armor_martial_artist"):Connect(function()
			local c = p.Character
			if not c or p:GetAttribute("SelectedClass") ~= "martial_artist" then return end
			if p:GetAttribute("Armor_martial_artist") == true then MartialLook.Dress(c) else MartialLook.Undress(c) end
		end)
		if p.Character then task.spawn(onCharacter, p, p.Character) end
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
end

return MartialServer
