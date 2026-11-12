--!strict
--[[
	DeathKnightServer.luau
	Server side of the Death Knight, the Soul Reaper (client:
	DeathKnightController). Every hit and all state is decided here; clients
	get the moments to draw over DeathKnightFX. Black mist, dark smoke and a
	little icy spectral blue.

	  M1 Graveblade    a heavy 3-hit chain: a horizontal cleave, a rising
	                   backhand, an overhead slam (all round, a burst of mist).
	  E  Blackwake     the hammer dragged behind him, swung up with both
	                   hands: the floor tears open in a huge cone of black
	                   stone spikes and smoke in front of him, rippling out.
	  F  Doomfall      a crouch, a leap high with the blade raised (mist
	                   gathering on it), a crash sword-first at the cursor: a
	                   wide dark shockwave, and mist lingers on the spot,
	                   biting whoever stays in it.
	  Q  Grave Reversal
	                   a spectral chain from his left palm coils round the
	                   first enemy on its line: torn past him and smashed down
	                   behind him, dragged back round to in front of him, and
	                   executed under the hammer, pinned. A boss is too heavy:
	                   the chain holds it and both blows land where it stands.
	  R  King of the Grave
	                   a gigantic spectral warhammer summoned over him; he
	                   launches up, everything under him chained, and brings
	                   it down: a huge crater, everything thrown up; chains
	                   drag what's left in, marked with Dread, and the marks
	                   burst.

	DREAD (the passive, 0-100, "DK_Dread") builds as he fights: every enemy
	struck, more for a heavy blow, a kill, and the hits he takes. Full, he is
	DREADFORGED ("DK_DreadUntil", 8 s): +20% damage, his swings send out
	spectral shockwaves, his skills grow (a second Blackwake, a wider Doomfall
	whose mist bites harder, a wider King of the Grave). The meter is spent.

	Also dresses the real character in the Soul Reaper plate (DeathKnightLook)
	while the class is played: his armor is built in, always worn.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local DeathKnightLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DeathKnightLook"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local DeathKnightServer = {}

-- ── Tuning (mirrored in DeathKnightController) ──────────────────────────────
local COMBO_RESET = 1.7
-- Heavy, slow swings (the client's SWING): `land` when the blow lands, `free`
-- when the next swing may start (at 1x attack speed). Each hits harder to
-- keep the combo's damage per second where it was when it swung twice as fast.
local COMBO = {
	-- range, minimum facing dot (-1 = all round), damage, when it lands, source
	[1] = { range = 12, dot = 0.05, damage = 55, land = 0.46, free = 0.82, source = "GRAVE CLEAVE" },
	[2] = { range = 12, dot = 0.05, damage = 55, land = 0.44, free = 0.8, source = "GRAVE CLEAVE" },
	[3] = { range = 14, dot = -1, damage = 148, land = 0.96, free = 1.45, source = "GRAVE SMASH", heavy = true },
}

-- Blackwake: the wind-up (the hammer dragged behind him), then the upward
-- swing tears the floor open in a cone in front of him, rippling out.
local WAKE_WINDUP = 0.6       -- (mirrored in DeathKnightController: the plant and the drag)
local WAKE_STEP = 3.5         -- how far he walks it forward first
local WAKE_GAP = 0.3          -- (Dreadforged) the second wave behind the first

-- Doomfall: crouch, leap, hang (mist gathering), crash.
local DOOM = { crouch = 0.24, rise = 0.38, hang = 0.3, fall = 0.14 }
DOOM.impact = DOOM.crouch + DOOM.rise + DOOM.hang + DOOM.fall
local DOOM_MIST_TICK = 0.5
local DOOM_MIST_HIT = 0.12    -- × the crash's damage, each tick in the mist (Dreadforged 0.2)

-- Grave Reversal (Q): a heavy chain thrown from his left hand coils round the
-- first one on its line. He never moves: it's carried round him, never toward
-- him. From the bite (seconds):
--   grab     coiled round its chest, the chain drawn taut, held where it stands
--   launch   heaved up off its feet into the air, rising up and over him
--   over     ...past the top, swung down across him onto the far side
--   slam     (= grab + launch + over) smashed into the floor behind him, as far
--            out as it started
--   yank     the wind-up of the last yank, the chain lying slack
--   fling    flung on out away from him, and the chain lets go
--   land     it hits the floor again, further out
--   done     the end
-- A boss is too heavy: the chain holds fast and both blows land where it stands.
-- (Mirrored in DeathKnightController: his poses, his turning, the chain.)
local SNATCH = { cast = 0.3, grab = 0.3, launch = 0.4, over = 0.32, slam = 1.02, yank = 1.4, fling = 1.54, land = 2.1, done = 2.5 }
local SNATCH_MIN_R = 6        -- the arc's radius at least (pushed out a little if it was closer: never pulled in)
local SNATCH_MAX_UP = 15      -- how high over him the arc goes, at most
local SNATCH_SIDE = 2.6       -- how far to his left it passes over him (clear of his head; over the chain hand)
local SNATCH_FLING = 14       -- how much further out the last yank throws it
local SNATCH_WIDTH = 3.5      -- how close to its line the chain catches
local SNATCH_SPLASH = 8       -- the slam's radius round the body (the landing after the fling: 1.25x)

-- King of the Grave, in six beats (mirrored in DeathKnightController):
--   0      the awakening: the hammer raised, chains rising round him
--   pull   everything near drawn a little toward him
--   summon a gigantic spectral warhammer forms over him (the camera on it)
--   rise   he launches up; everything under him chained in place
--   fall   he brings it down...
--   impact ...the crater; everything in reach thrown into the air
--   drag   chains drag what's left into the crater, marked with Dread
--   burst  the marks burst
--   fade   the hammer dissolves; done: he's his own again
local KING = { pull = 0.3, summon = 1.0, rise = 2.0, fall = 2.6, impact = 2.85, drag = 3.35, burst = 4.25, fade = 4.4, done = 5.0 }
local KING_AHEAD = 4          -- the hammer's head comes down this far ahead of him
local KING_TUG = 9            -- (studs/s) the awakening's pull
local KING_DRAG = 45          -- (studs/s, at most) the chains' drag into the crater

-- Dread.
local DREAD_MAX = 100
local DREAD_HIT = 3           -- per enemy struck
local DREAD_HEAVY = 3         -- more for a heavy blow (a finisher, a skill)
local DREAD_KILL = 7          -- per kill
local DREAD_HURT = 40         -- × the share of his max health a hit takes
local DREAD_TIME = 8
local DREAD_DAMAGE = 0.2      -- +20% damage while Dreadforged
local DREAD_AREA = 1.25       -- his skills' size while Dreadforged
local DREAD_WAVE = 9          -- the spectral shockwave off each swing (radius)
local SNATCH_GUARD = 0.6      -- damage taken while he's busy with a snatch

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = {
	step: number,
	lastSwing: number,
	busyUntil: number,
	guardUntil: number,
	token: number,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { step = 0, lastSwing = 0, busyUntil = 0, guardUntil = 0, token = 0 }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.DeathKnightFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

-- ── Dread ───────────────────────────────────────────────────────────────────
local function dreadforged(player: Player): boolean
	return (tonumber(player:GetAttribute("DK_DreadUntil")) or 0) > Workspace:GetServerTimeNow()
end

local function damageMult(player: Player): number
	return stat(player, "damage") * (if dreadforged(player) then 1 + DREAD_DAMAGE else 1)
end

local function areaMult(player: Player, config: any): number
	return (config.areaMultiplier or stat(player, "size")) * (if dreadforged(player) then DREAD_AREA else 1)
end

local function dreadOf(player: Player): number
	return tonumber(player:GetAttribute("DK_Dread")) or 0
end

-- (none builds while Dreadforged: the meter is spent)
local function addDread(player: Player, n: number)
	if n <= 0 or dreadforged(player) or player:GetAttribute("SelectedClass") ~= "death_knight" then return end
	local now = math.clamp(dreadOf(player) + n, 0, DREAD_MAX)
	if now < DREAD_MAX then
		if now ~= dreadOf(player) then player:SetAttribute("DK_Dread", now) end
		return
	end
	-- Full: Dreadforged (longer with Ability Duration).
	local seconds = DREAD_TIME * math.max(stat(player, "abilityDuration"), 0.1)
	player:SetAttribute("DK_Dread", 0)
	player:SetAttribute("DK_DreadUntil", Workspace:GetServerTimeNow() + seconds)
	fx({ kind = "dread", attacker = player, seconds = seconds })
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

-- Hit every one of `hits`; Dread for what landed. Returns how many did.
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
		addDread(player, landed * DREAD_HIT + (if heavy then DREAD_HEAVY else 0) + kills * DREAD_KILL)
	end
	return landed
end

local function stagger(t: Target, seconds: number)
	if t.character:GetAttribute("IsBoss") == true or Players:GetPlayerFromCharacter(t.character) then return end
	local untilT = os.clock() + seconds
	if (tonumber(t.character:GetAttribute("StaggerUntil")) or 0) < untilT then
		t.character:SetAttribute("StaggerUntil", untilT)
	end
end

-- Too heavy to haul about: bosses, and the mobs built not to budge.
local function immovable(t: Target): boolean
	return t.character:GetAttribute("IsBoss") == true or t.character:GetAttribute("Unstaggerable") == true
		or t.character:GetAttribute("HitRadius") ~= nil
end

-- Dreadforged: a spectral shockwave off a swing, hitting everyone round where
-- the blade landed.
local function dreadWave(player: Player, char: Model, at: Vector3, dir: Vector3, damage: number)
	if not dreadforged(player) then return end
	local r = DREAD_WAVE * stat(player, "size")
	fx({ kind = "dreadWave", attacker = player, pos = at, radius = r })
	strike(player, inRadius(char, at, dir, r, -1), damage * 0.35, "DREAD WAVE")
end

-- ── M1: the Graveblade ──────────────────────────────────────────────────────
function DeathKnightServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
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
	local size = stat(player, "size")
	local damage = c.damage * damageMult(player)
	local step = st.step
	fx({ kind = "combo", attacker = player, step = step, dir = dir })
	task.delay(c.land / speed, function()
		if not char.Parent or not root.Parent then return end
		local hits = inRadius(char, root.Position, dir, c.range * size, c.dot)
		strike(player, hits, damage, c.source, c.heavy)
		local at = root.Position + dir * (if step == 3 then 6 else 5)
		if step == 3 then fx({ kind = "smash", attacker = player, pos = at, radius = c.range * size }) end
		dreadWave(player, char, at, dir, damage)
	end)
end

-- ── E: Blackwake ────────────────────────────────────────────────────────────
-- The crescent rolls out from where he stands along the aim; everyone it
-- passes (within half its width of its line) is cut once per wave.
local function blackwake(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local dread = dreadforged(player)
	local area = areaMult(player, config)
	-- (the cone's half-angle: wider with Size, never past a half-circle)
	local half = math.rad(math.min((config.angle or 70) * area, 170)) / 2
	local range = (config.range or 30) * (if dread then 1.15 else 1)
	local speed = math.max(config.projectileSpeed or 70, 10)
	local damage = (config.damage or 70) * damageMult(player)
	local waves = if dread then 2 else 1
	st.busyUntil = os.clock() + WAKE_WINDUP + 0.3
	local from = root.Position + dir * WAKE_STEP
	fx({ kind = "blackwake", attacker = player, from = from, dir = dir, half = half, range = range, speed = speed,
		windup = WAKE_WINDUP, waves = waves, gap = WAKE_GAP })
	for w = 1, waves do
		task.delay(WAKE_WINDUP + (w - 1) * WAKE_GAP, function()
			if not char.Parent then return end
			local struck: { [Model]: boolean } = {}
			local mult = if w == 1 then 1 else 0.55
			local t0 = os.clock()
			local reach = 0
			while reach < range do
				local last = reach
				reach = math.min(range, (os.clock() - t0) * speed + 2)
				for _, t in ipairs(H.getPotentialTargets(char)) do
					if struck[t.character] then continue end
					local d = t.rootPart.Position - from
					local along = Vector3.new(d.X, 0, d.Z):Dot(dir)
					if along < last - 3 or along > reach + 1 or math.abs(d.Y) > 12 then continue end
					local side = (Vector3.new(d.X, 0, d.Z) - dir * along).Magnitude
					if along > -1 and side <= math.max(along, 0) * math.tan(half) + 2.5 then
						struck[t.character] = true
						strike(player, { t }, damage * mult, "BLACKWAKE", true)
					end
				end
				task.wait(0.04)
			end
		end)
	end
end

-- ── F: Doomfall ─────────────────────────────────────────────────────────────
local function doomfall(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, aimAt: Vector3?, config: any)
	local dread = dreadforged(player)
	local radius = (config.radius or 14) * areaMult(player, config)
	local damage = (config.damage or 110) * damageMult(player)
	local reach = config.range or 24
	st.busyUntil = os.clock() + DOOM.impact + 0.35
	char:SetAttribute("InvulnerableUntil", os.clock() + DOOM.impact + 0.1)
	-- Where he lands: the cursor (the client sends the exact spot), within reach.
	local from = root.Position
	local land = from + dir * 8
	if aimAt then
		local d = Vector3.new(aimAt.X - from.X, 0, aimAt.Z - from.Z)
		land = from + (if d.Magnitude > reach + 6 then d.Unit * reach else d)
	end
	fx({ kind = "doomfall", attacker = player, dir = dir, land = land, radius = radius, t = DOOM, dread = dread })
	local token = st.token
	task.delay(DOOM.impact, function()
		if st.token ~= token or not char.Parent or not root.Parent then return end
		-- (the landing spot, not his replicated body: that trails, still in the air)
		local center = Vector3.new(land.X, from.Y, land.Z)
		local mistTime = config.duration or 3
		fx({ kind = "doomImpact", attacker = player, pos = center, radius = radius, mist = mistTime, dread = dread })
		local hits = inRadius(char, center, dir, radius, -1)
		strike(player, hits, damage, "DOOMFALL", true)
		-- The mist left on the spot bites whoever stays in it.
		local bite = damage * (if dread then 0.2 else DOOM_MIST_HIT)
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < mistTime do
				task.wait(DOOM_MIST_TICK)
				if not char.Parent then return end
				strike(player, inRadius(char, center, dir, radius * 0.75, -1), bite, "GRAVE MIST")
			end
		end)
	end)
end

-- ── Q: Grave Reversal ─────────────────────────────────────────────────────────
-- The first enemy along the chain's line, within reach.
local function firstOnLine(char: Model, from: Vector3, dir: Vector3, range: number): (Target?, number)
	local best: Target? = nil
	local bestAlong = range
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - from
		local fd = Vector3.new(d.X, 0, d.Z)
		local along = fd:Dot(dir)
		if along >= 0 and along <= bestAlong and math.abs(d.Y) < 10 then
			local side = (fd - dir * along).Magnitude
			if side <= H.lineReach(t, SNATCH_WIDTH) then
				best, bestAlong = t, along
			end
		end
	end
	return best, bestAlong
end

-- The floor under `p` (the body is slammed onto it).
local function floorY(p: Vector3, ignore: { Instance }): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(p + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position.Y else p.Y - 3
end

-- Clear floor along `from` → `to` at waist height: where it stops short of a wall.
local function clearTo(from: Vector3, to: Vector3, ignore: { Instance }): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = ignore
	local d = to - from
	if d.Magnitude < 0.1 then return to end
	local hit = Workspace:Raycast(from, d, params)
	if not hit then return to end
	return from + d.Unit * math.max(hit.Distance - 1.5, 0)
end

local function snatch(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local damage = (config.damage or 55) * damageMult(player)
	local range = config.range or 34
	local speed = math.max(config.projectileSpeed or 140, 20)
	st.token += 1
	local token = st.token
	-- (this throw's own count: cut short by a dash or another move, the chain
	-- is still let go on every client, unless a newer throw has taken over)
	local S = st :: any
	S.snatchSeq = (S.snatchSeq or 0) + 1
	local seq = S.snatchSeq
	local function release()
		if S.snatchSeq == seq then fx({ kind = "snatchRelease", attacker = player }) end
	end
	local from = root.Position
	local victim, along = firstOnLine(char, from, dir, range)
	local travel = along / speed
	if not victim then
		-- A miss: the chain flies out its full length, drops and is reeled back.
		st.busyUntil = os.clock() + SNATCH.cast + travel * 2 + 0.1
		fx({ kind = "snatch", attacker = player, dir = dir, to = from + dir * range, travel = travel, cast = SNATCH.cast })
		return
	end
	local v = victim :: Target
	local heavy = immovable(v)
	local T = SNATCH
	local total = T.cast + travel + T.done
	st.busyUntil = os.clock() + total + 0.1
	st.guardUntil = os.clock() + total
	local center = root.Position
	fx({ kind = "snatch", attacker = player, dir = dir, to = v.rootPart.Position, travel = travel, cast = T.cast,
		model = v.character, heavy = heavy, t = T, center = center })

	task.spawn(function()
		task.wait(T.cast + travel)
		if st.token ~= token or not char.Parent or not root.Parent then
			release()
			return
		end
		if v.humanoid.Health <= 0 or not v.rootPart.Parent then
			fx({ kind = "snatchRelease", attacker = player })
			st.busyUntil = os.clock() + 0.15
			return
		end
		strike(player, { v }, damage * 0.4, "GRAVE SNATCH")
		local ignore: { Instance } = { char, v.character }
		local function slam(i: number, p: Vector3)
			local g = Vector3.new(p.X, floorY(p, ignore), p.Z)
			local r = if i == 2 then SNATCH_SPLASH * 1.25 else SNATCH_SPLASH
			fx({ kind = "snatchSlam", attacker = player, pos = g, i = i, radius = r, model = v.character })
			if v.humanoid.Health > 0 then
				strike(player, { v }, damage * (if i == 1 then 1.4 else 2.2), if i == 1 then "GRAVE SLAM" else "GRAVE THROW", true)
			end
			local splash = {}
			for _, t in ipairs(inRadius(char, g, dir, r, -1)) do
				if t.character ~= v.character then table.insert(splash, t) end
			end
			strike(player, splash, damage * (if i == 1 then 0.6 else 0.8), "GRAVE SLAM")
		end

		if heavy then
			-- Too heavy to move: the chain holds fast and both blows land where
			-- it stands.
			for i, at in ipairs({ T.slam, T.land }) do
				task.delay(at, function()
					if st.token ~= token or not char.Parent or not v.rootPart.Parent then return end
					slam(i, v.rootPart.Position)
				end)
			end
			task.delay(T.done, release)
			return
		end

		-- Carried by the chain (anchored, the server moving it) on a circle round
		-- him: up off its feet, over him (passing over his left side) and down onto
		-- the far side at the same distance; then flung on out from there.
		local vr = v.rootPart
		local ok, err = pcall(function()
			vr.Anchored = true
			stagger(v, T.done + 1)
			local start = vr.Position
			local flat = Vector3.new(start.X - center.X, 0, start.Z - center.Z)
			local u = if flat.Magnitude > 0.5 then flat.Unit else dir -- (out toward it)
			local left = Vector3.yAxis:Cross(u).Unit -- (his left, as he faces it)
			local r0 = math.max(flat.Magnitude, SNATCH_MIN_R)
			local stand = start.Y - floorY(start, ignore) -- (its root's height over the floor)
			local baseY = floorY(center, ignore) + stand
			local hub = Vector3.new(center.X, baseY, center.Z)
			-- where it comes down: as far out on the other side, short of any wall
			local landAt = clearTo(hub, hub - u * r0, ignore)
			local r1 = math.max((landAt - hub).Magnitude, 3)
			local upScale = math.min(1, SNATCH_MAX_UP / r0)
			-- θ: 0 where it stood, 90° over him, 180° on the far side
			local function arcAt(th: number): Vector3
				local r = r0 + (r1 - r0) * math.clamp(th / math.pi, 0, 1)
				return hub + u * (r * math.cos(th)) + Vector3.yAxis * (r * math.sin(th) * upScale)
					+ left * (SNATCH_SIDE * math.sin(th))
			end
			-- the body hangs off the chain: chest toward him, head pointing out along it
			local function hung(p: Vector3)
				local toC = hub + Vector3.new(0, 1, 0) - p
				local look = if toC.Magnitude > 0.1 then toC.Unit else -u
				local outward = p - hub
				local up = outward - look * outward:Dot(look)
				up = if up.Magnitude > 0.05 then up.Unit else Vector3.yAxis
				vr.CFrame = CFrame.lookAt(p, p + look, up)
			end
			-- laid flat on the floor, head away from him
			local function pinned(p: Vector3)
				local away = Vector3.new(p.X - center.X, 0, p.Z - center.Z)
				away = if away.Magnitude > 0.05 then away.Unit else -u
				vr.CFrame = CFrame.fromMatrix(Vector3.new(p.X, floorY(p, ignore) + 0.6, p.Z), away:Cross(Vector3.yAxis).Unit, away)
			end
			local function over(dur: number, fn: (number) -> ()): boolean
				local t0 = os.clock()
				while true do
					if st.token ~= token or not vr.Parent or not root.Parent or v.humanoid.Health <= 0 then return false end
					local a = math.min((os.clock() - t0) / dur, 1)
					fn(a)
					if a >= 1 then return true end
					RunService.Heartbeat:Wait()
				end
			end
			local p0 = arcAt(0)
			-- 1 · grabbed: the coil bites, the chain draws taut, it's jerked up
			-- onto its toes where it stands (not toward him)
			if not over(T.grab, function(a)
				local jolt = math.sin(math.min(a / 0.35, 1) * math.pi * 0.5) * 0.35
				local q = start:Lerp(Vector3.new(p0.X, start.Y, p0.Z), a) + Vector3.new(0, jolt, 0)
				vr.CFrame = CFrame.lookAt(q, Vector3.new(center.X, q.Y, center.Z))
			end) then return end
			-- 2 · launched: heaved up off its feet, fast at first, slowing as it
			-- rises over him...
			local TOP = math.rad(100)
			if not over(T.launch, function(a)
				hung(arcAt(TOP * (1 - (1 - a) ^ 2)))
			end) then return end
			-- 3 · ...then swung down across him, faster and faster, into the floor
			-- on the far side
			if not over(T.over, function(a)
				hung(arcAt(TOP + (math.pi - TOP) * a * a))
			end) then return end
			local down = arcAt(math.pi)
			pinned(down)
			slam(1, down)
			if v.humanoid.Health <= 0 then return end
			-- 4 · lying there in the crater (a bounce, settling) while he winds up the yank
			if not over(T.fling - T.slam, function(a)
				pinned(down + Vector3.new(0, 0.8 * math.sin(math.min(a * 2.2, 1) * math.pi) * (1 - a), 0))
			end) then return end
			-- 5 · flung on out away from him, tumbling end over end
			local outDir = Vector3.new(down.X - center.X, 0, down.Z - center.Z)
			outDir = if outDir.Magnitude > 0.1 then outDir.Unit else -u
			local lift = Vector3.new(0, 1, 0)
			local landP = clearTo(down + lift, down + lift + outDir * SNATCH_FLING, ignore) - lift
			local axis = outDir:Cross(Vector3.yAxis).Unit
			local face = CFrame.lookAt(Vector3.zero, -outDir).Rotation
			if not over(T.land - T.fling, function(a)
				local e = 1 - (1 - a) ^ 1.6
				local p = down:Lerp(landP, e) + Vector3.new(0, 5.5 * math.sin(math.pi * a), 0)
				vr.CFrame = CFrame.new(p) * CFrame.fromAxisAngle(axis, -a * math.pi * 3) * face
			end) then return end
			pinned(landP)
			slam(2, landP)
			over(T.done - T.land, function() pinned(landP) end)
		end)
		if not ok then warn("[DeathKnightServer] snatch:", err) end
		if vr.Parent then
			vr.Anchored = false
			pcall(function() vr:SetNetworkOwner(nil) end)
		end
		release()
	end)
end

-- ── R: King of the Grave ────────────────────────────────────────────────────
local function king(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	local radius = (config.radius or 32) * areaMult(player, config)
	local damage = (config.damage or 60) * damageMult(player)
	st.token += 1
	local token = st.token
	st.busyUntil = os.clock() + KING.done + 0.1
	char:SetAttribute("InvulnerableUntil", os.clock() + KING.done)
	local from = root.Position
	-- (where the spectral hammer's head comes down: just ahead of him)
	local center = from + dir * KING_AHEAD
	fx({ kind = "king", attacker = player, pos = from, center = center, dir = dir, radius = radius, t = KING })
	local function alive(): boolean return st.token == token and char.Parent ~= nil and root.Parent ~= nil end
	-- (drawn toward `to` over `dur` seconds at `speed`, mobs only)
	local function haul(targets: { Target }, to: Vector3, dur: number, speed: number)
		local t0 = os.clock()
		task.spawn(function()
			while os.clock() - t0 < dur and alive() do
				for _, t in ipairs(targets) do
					local r = t.rootPart
					if r.Parent and not r.Anchored and not immovable(t) and not Players:GetPlayerFromCharacter(t.character) then
						local d = Vector3.new(to.X - r.Position.X, 0, to.Z - r.Position.Z)
						if d.Magnitude > 2.5 then
							local v = d.Unit * math.min(speed, d.Magnitude / 0.15)
							r.AssemblyLinearVelocity = Vector3.new(v.X, r.AssemblyLinearVelocity.Y, v.Z)
						end
					end
				end
				RunService.Heartbeat:Wait()
			end
		end)
	end
	-- 1 · The awakening: everything near drawn a little toward him.
	task.delay(KING.pull, function()
		if not alive() then return end
		haul(inRadius(char, from, dir, radius * 1.2, -1), from, KING.summon - KING.pull, KING_TUG)
	end)
	-- 3 · The ascension: everything under him chained where it stands.
	task.delay(KING.rise, function()
		if not alive() then return end
		local bound = inRadius(char, center, dir, radius, -1)
		local models = {}
		for _, t in ipairs(bound) do
			stagger(t, KING.impact - KING.rise + 0.2)
			table.insert(models, t.character)
		end
		fx({ kind = "kingBind", attacker = player, pos = center, models = models, hold = KING.impact - KING.rise })
		strike(player, bound, damage * 0.4, "GRAVE CHAINS")
	end)
	-- 4 · The execution: the spectral hammer comes down; everything in reach
	-- thrown into the air.
	task.delay(KING.impact, function()
		if not alive() then return end
		fx({ kind = "kingFinal", attacker = player, pos = center, radius = radius })
		strike(player, inRadius(char, center, dir, radius, -1), damage * 4.5, "KING OF THE GRAVE", true)
	end)
	-- 5 · The grave awakens: chains drag whatever's left into the crater and
	-- mark it; the marks burst.
	local marked: { Target } = {}
	task.delay(KING.drag, function()
		if not alive() then return end
		local models = {}
		for _, t in ipairs(inRadius(char, center, dir, radius * 1.4, -1)) do
			if t.humanoid.Health > 0 then
				table.insert(marked, t)
				table.insert(models, t.character)
				stagger(t, KING.burst - KING.drag + 0.3)
			end
		end
		fx({ kind = "kingDrag", attacker = player, pos = center, models = models, hold = KING.burst - KING.drag })
		haul(marked, center, 0.55, KING_DRAG)
	end)
	task.delay(KING.burst, function()
		if not alive() then return end
		local live, models = {}, {}
		for _, t in ipairs(marked) do
			if t.humanoid.Health > 0 and t.rootPart.Parent then
				table.insert(live, t)
				table.insert(models, t.character)
			end
		end
		fx({ kind = "kingBurst", attacker = player, models = models })
		strike(player, live, damage * 2.5, "GRAVE MARK", true)
	end)
	-- 6 · The aftermath.
	task.delay(KING.fade, function()
		if alive() then fx({ kind = "kingEnd", attacker = player, pos = center }) end
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function DeathKnightServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function DeathKnightServer.OnSkill(player: Player, char: Model, skillIndex: number, _origin: Vector3, dir: Vector3, config: any, aimAt: Vector3?)
	local st = getState(player)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	dir = flat(dir)
	if skillIndex == 1 then
		blackwake(player, char, st, root, dir, config)
	elseif skillIndex == 2 then
		doomfall(player, char, st, root, dir, aimAt, config)
	elseif skillIndex == 3 then
		snatch(player, char, st, root, dir, config)
	elseif skillIndex == 4 then
		king(player, char, st, root, dir, config)
	end
end

-- (the ult's opening, the awakening and the summoning: mobs hold still while
-- the camera's on him; the chains hold them after)
DeathKnightServer.ULT_WINDUP = KING.rise

-- Fresh combo, an empty meter (new character / run).
function DeathKnightServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil, st.guardUntil = 0, 0, 0, 0
	st.token += 1
	player:SetAttribute("DK_Dread", 0)
	player:SetAttribute("DK_DreadUntil", nil)
end

-- ── The plate on the real character ─────────────────────────────────────────
local dressConns: { [Model]: RBXScriptConnection } = {}

local function wearsPlate(p: Player): boolean
	return p:GetAttribute("SelectedClass") == "death_knight" and p:GetAttribute("Armor_death_knight") == true
end

local function refreshPlate(p: Player, char: Model)
	if not wearsPlate(p) then
		if dressConns[char] then
			dressConns[char]:Disconnect()
			dressConns[char] = nil
		end
		if DeathKnightLook.IsDressed(char) then DeathKnightLook.Undress(char) end
		return
	end
	task.defer(function()
		if not char.Parent or not char:WaitForChild("Head", 5) or not char:WaitForChild("Torso", 5) then return end
		for _, limb in ipairs({ "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do char:WaitForChild(limb, 5) end
		if p.Character ~= char or not wearsPlate(p) then return end
		DeathKnightLook.Dress(char)
		-- Hats and hair that load in after: under the plate too.
		if not dressConns[char] then
			dressConns[char] = char.ChildAdded:Connect(function(child)
				if child:IsA("Accessory") and DeathKnightLook.IsDressed(char) then
					task.defer(DeathKnightLook.HideAccessory, child)
				end
			end)
			char.AncestryChanged:Connect(function(_, parent)
				if not parent and dressConns[char] then
					dressConns[char]:Disconnect()
					dressConns[char] = nil
				end
			end)
		end
	end)
end

function DeathKnightServer.Init(helpers: any)
	-- (a dash cuts the move short: free to act again, and what was left of it doesn't land)
	(require(script.Parent:WaitForChild("Dash")) :: any).OnDash(function(p: Player)
		local st = states[p] :: any
		if not st then return end
		st.busyUntil = 0
		if type(st.token) == "number" then st.token += 1 end
	end)
	H = helpers
	if helpers.addIncomingHook then
		helpers.addIncomingHook(function(player: Player, char: Model, damage: number): number
			if player:GetAttribute("SelectedClass") ~= "death_knight" then return damage end
			local st = states[player]
			-- (busy with a snatch: the plate takes some of it)
			if st and os.clock() < st.guardUntil then damage *= SNATCH_GUARD end
			-- Every hit he takes feeds the dread.
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.MaxHealth > 0 and damage > 0 then addDread(player, damage / hum.MaxHealth * DREAD_HURT) end
			return damage
		end)
	end
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function(c)
			if p:GetAttribute("SelectedClass") == "death_knight" then DeathKnightServer.Reset(p) end
			refreshPlate(p, c)
		end)
		for _, a in ipairs({ "SelectedClass", "Armor_death_knight" }) do
			p:GetAttributeChangedSignal(a):Connect(function()
				if p.Character then refreshPlate(p, p.Character) end
			end)
		end
		if p.Character then refreshPlate(p, p.Character) end
	end
	Players.PlayerAdded:Connect(watch)
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
end

return DeathKnightServer
