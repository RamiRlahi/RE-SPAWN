--!strict
--[[
	BerserkerServer.luau
	Server side of the Berserker, the Crimson Ravager (client:
	BerserkerController). Every hit and all state is decided here; clients get
	the moments to draw over BerserkerFX. Crimson energy, black smoke,
	fractured ground, red afterimages.

	  M1 Greatsword    a heavy 3-hit chain: a diagonal cleave, a backhand, and
	                   an overhead smash (all-round shockwave).
	  E  Rupture       crouch, leap, hang at the apex, crash down: a crater, a
	                   circular fracture and a shockwave (damage + knock-up).
	  F  Bloodstorm    dash from enemy to enemy with ever faster slashes, then a
	                   spinning cleave that throws them out. Half damage taken
	                   while it lasts.
	  Q  Bloodrage: Unchained
	                   plant the sword, tremble, roar: a crimson pulse, then for
	                   a while faster, harder attacks, and the NEXT skill is
	                   Empowered (bigger, more violent).
	  R  Worldbreaker  kneel and gather, launch into the sky, hang, dive onto the
	                   aimed spot dragging a giant blade: a cataclysmic impact,
	                   then a delayed second explosion that executes the
	                   badly wounded.

	Attributes (on the player): BR_UnchainedUntil (server time), BR_Empowered.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local BerserkerServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local SWING_INTERVAL = 0.48   -- seconds between combo swings at 1× attack speed (a heavy blade)
local COMBO_RESET = 1.2

local COMBO = {
	-- range, minimum facing dot (-1 = all round), damage, source
	[1] = { range = 12, dot = 0.1, damage = 30, source = "BERSERK CLEAVE" },
	[2] = { range = 12, dot = 0.1, damage = 30, source = "BERSERK CLEAVE" },
	[3] = { range = 13, dot = -1, damage = 52, source = "BERSERK SMASH" },
}

-- Rupture: crouch, leap, hang, crash (seconds after the cast).
local RUPTURE = { crouch = 0.32, rise = 0.3, hang = 0.18, fall = 0.14 }
RUPTURE.impact = RUPTURE.crouch + RUPTURE.rise + RUPTURE.hang + RUPTURE.fall
local RUPTURE_RANGE = 17      -- the furthest he can leap (to the cursor)

-- Bloodstorm: the lean, then dashes that each come faster.
local STORM_WINDUP = 0.3
local STORM_FIRST = 0.17      -- the first dash's length (s)
local STORM_ACCEL = 0.84      -- each next dash takes this much of the last
local STORM_FREEZE = 0.06     -- the impact freeze after each hit
local STORM_HITS = 5          -- (Empowered: 7)
local STORM_REACH = 24        -- enemies this close are fair game
local STORM_GUARD = 0.5       -- damage taken while storming

-- Bloodrage: Unchained.
local UNCHAIN_WINDUP = 1.1    -- plant, tremble, roar
local UNCHAIN_TIME = 8
local UNCHAIN_SPEED = 0.35    -- +35% attack speed
local UNCHAIN_DAMAGE = 0.25   -- +25% damage

-- Worldbreaker: gather, ascend, hang (time slows), dive; the second blast.
local WB = { gather = 1.4, ascend = 0.5, hang = 0.4, dive = 0.22, pull = 0.8 }
WB.impact = WB.gather + WB.ascend + WB.hang + WB.dive
WB.second = WB.impact + 0.6
WB.total = WB.second + WB.pull
local WB_RANGE = 34           -- how far the dive can land
local WB_EXECUTE = 0.2        -- the second blast kills non-bosses below this health

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = {
	step: number,
	lastSwing: number,
	busyUntil: number,
	guardUntil: number,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { step = 0, lastSwing = 0, busyUntil = 0, guardUntil = 0 }
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

-- ── Bloodrage: Unchained ────────────────────────────────────────────────────
local function unchained(player: Player): boolean
	return (tonumber(player:GetAttribute("BR_UnchainedUntil")) or 0) > Workspace:GetServerTimeNow()
end

local function damageMult(player: Player): number
	return stat(player, "damage") * (if unchained(player) then 1 + UNCHAIN_DAMAGE else 1)
end

-- The Unchained surge empowers the next skill (only one).
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

local function strike(player: Player, hits: { Target }, damage: number, source: string)
	for _, t in ipairs(hits) do
		H.dealDamage(player, t, damage, source)
	end
end

-- ── M1: the greatsword ──────────────────────────────────────────────────────
function BerserkerServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1) * (if unchained(player) then 1 + UNCHAIN_SPEED else 1)
	if now - st.lastSwing < (SWING_INTERVAL / speed) * 0.85 then return end
	st.step = if now - st.lastSwing > COMBO_RESET then 1 else (st.step % 3) + 1
	st.lastSwing = now

	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local c = COMBO[st.step]
	local size = stat(player, "size")
	local damage = c.damage * damageMult(player)
	local step = st.step
	fx({ kind = "combo", attacker = player, step = step, dir = dir })
	-- The blade lands a beat after the wind-up.
	task.delay(if step == 3 then 0.2 else 0.1, function()
		if not char.Parent or not root.Parent then return end
		strike(player, inRadius(char, root.Position, dir, c.range * size, c.dot), damage, c.source)
		if step == 3 then fx({ kind = "smash", attacker = player, pos = root.Position + dir * 3, radius = c.range * size }) end
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
		strike(player, inRadius(char, center, dir, radius, -1), damage, "RUPTURE")
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
-- The route: hop to the nearest enemy, then the nearest one not just hit (so
-- with two enemies he goes back and forth); with none, a zig-zag forward.
local function stormRoute(char: Model, from: Vector3, dir: Vector3, hits: number, reach: number): { { pos: Vector3, target: Target? } }
	local pool = inRadius(char, from, dir, reach, -1)
	local route = {}
	local at = from
	local last: Target? = nil
	for i = 1, hits do
		local best: Target? = nil
		local bestD = math.huge
		for _, t in ipairs(pool) do
			if t ~= last and t.humanoid.Health > 0 then
				local d = (t.rootPart.Position - at).Magnitude
				if d < bestD then best, bestD = t, d end
			end
		end
		if not best and last and last.humanoid.Health > 0 then best = last end
		local pos: Vector3
		if best then
			-- stop just short of it, on the side we came from
			local tp = best.rootPart.Position
			local away = Vector3.new(at.X - tp.X, 0, at.Z - tp.Z)
			away = if away.Magnitude > 0.1 then away.Unit else -dir
			pos = Vector3.new(tp.X, from.Y, tp.Z) + away * 2.6
		else
			local side = Vector3.new(-dir.Z, 0, dir.X) * (if i % 2 == 0 then 3.5 else -3.5)
			pos = from + dir * (5 * i) + side
		end
		table.insert(route, { pos = pos, target = best })
		last = best
		at = pos
	end
	return route
end

local function bloodstorm(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any, empowered: boolean)
	local area = config.areaMultiplier or 1
	local count = if empowered then STORM_HITS + 2 else STORM_HITS
	local damage = (config.damage or 30) * damageMult(player) * (if empowered then 1.3 else 1)
	local finalRadius = 12 * area * (if empowered then 1.4 else 1)
	local from = root.Position
	local route = stormRoute(char, from, dir, count, STORM_REACH * area)
	-- The timeline: each dash shorter than the last, a freeze after each hit.
	local t = STORM_WINDUP
	local dur = STORM_FIRST
	local stops = {}
	for i, r in ipairs(route) do
		local arrive = t + dur
		table.insert(stops, { pos = r.pos, leave = t, arrive = arrive })
		t = arrive + STORM_FREEZE
		dur *= STORM_ACCEL
		local target = r.target
		local pos = r.pos
		task.delay(arrive, function()
			if not char.Parent then return end
			-- the struck enemy (if it's still there) and anyone right by it
			local hits = inRadius(char, pos, dir, 5 * area, -1)
			if target and target.humanoid.Health > 0 and not table.find(hits, target)
				and (target.rootPart.Position - pos).Magnitude < 9 then
				table.insert(hits, target)
			end
			strike(player, hits, damage, "BLOODSTORM")
			fx({ kind = "stormHit", attacker = player, pos = pos, i = i, hit = #hits > 0 })
		end)
	end
	local finalAt = t + 0.12
	st.busyUntil = os.clock() + finalAt + 0.35
	st.guardUntil = os.clock() + finalAt + 0.2
	fx({ kind = "storm", attacker = player, dir = dir, stops = stops, finalAt = finalAt, finalRadius = finalRadius,
		empowered = empowered })
	task.delay(finalAt, function()
		if not char.Parent or not root.Parent then return end
		local center = root.Position
		fx({ kind = "stormFinal", attacker = player, pos = center, radius = finalRadius, empowered = empowered })
		strike(player, inRadius(char, center, dir, finalRadius, -1), damage * 2.2, "BLOODSTORM FINISH")
	end)
end

-- ── Q: Bloodrage: Unchained ─────────────────────────────────────────────────
local function unchain(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, config: any)
	st.busyUntil = os.clock() + UNCHAIN_WINDUP + 0.2
	fx({ kind = "unchainWindup", attacker = player, dir = dir, windup = UNCHAIN_WINDUP })
	task.delay(UNCHAIN_WINDUP, function()
		if not char.Parent or not root.Parent then return end
		local duration = config.duration or UNCHAIN_TIME
		player:SetAttribute("BR_UnchainedUntil", Workspace:GetServerTimeNow() + duration)
		player:SetAttribute("BR_Empowered", true)
		local radius = 12 * (config.areaMultiplier or 1)
		fx({ kind = "unchained", attacker = player, pos = root.Position, radius = radius, duration = duration })
		-- the pulse shoves back whatever is close
		strike(player, inRadius(char, root.Position, dir, radius, -1), (config.damage or 30) * damageMult(player), "BLOODRAGE PULSE")
	end)
end

-- ── R: Worldbreaker ─────────────────────────────────────────────────────────
local function worldbreaker(player: Player, char: Model, st: State, root: BasePart, dir: Vector3, aimAt: Vector3?, config: any, empowered: boolean)
	local area = (config.areaMultiplier or 1) * (if empowered then 1.3 else 1)
	local damage = (config.damage or 160) * damageMult(player) * (if empowered then 1.3 else 1)
	local radius = 18 * area
	local from = root.Position
	-- Where the dive lands: the aim, within reach.
	local land = from + dir * 14
	if aimAt then
		-- (the client sends the exact spot it dives to; only refuse one far
		-- out of reach, so the blow lands right where he does)
		local d = Vector3.new(aimAt.X - from.X, 0, aimAt.Z - from.Z)
		land = from + (if d.Magnitude > WB_RANGE + 8 then d.Unit * WB_RANGE else d)
	end
	st.busyUntil = os.clock() + WB.total
	char:SetAttribute("InvulnerableUntil", os.clock() + WB.total)
	fx({ kind = "worldbreaker", attacker = player, from = from, land = land, dir = dir, radius = radius,
		empowered = empowered, t = WB })
	task.delay(WB.impact, function()
		if not char.Parent or not root.Parent then return end
		-- (where the dive lands, not where the server last saw him: his body's
		-- replicated position trails the client's and is still in the air)
		local center = Vector3.new(land.X, from.Y, land.Z)
		fx({ kind = "wbImpact", attacker = player, pos = center, radius = radius, empowered = empowered })
		strike(player, inRadius(char, center, dir, radius, -1), damage, "WORLDBREAKER")
		task.delay(WB.second - WB.impact, function()
			if not char.Parent then return end
			local r2 = radius * 1.35
			fx({ kind = "wbSecond", attacker = player, pos = center, radius = r2, empowered = empowered })
			local hits = inRadius(char, center, dir, r2, -1)
			for _, t in ipairs(hits) do
				local hum = t.humanoid
				-- the execution window: the badly wounded don't get up
				if hum.Health > 0 and t.character:GetAttribute("IsBoss") ~= true and not Players:GetPlayerFromCharacter(t.character)
					and hum.Health <= hum.MaxHealth * WB_EXECUTE then
					H.dealDamage(player, t, hum.Health + 1, "WORLDBREAKER EXECUTE", { forceCrit = true })
				else
					H.dealDamage(player, t, damage * 0.5, "WORLDBREAKER")
				end
			end
		end)
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function BerserkerServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function BerserkerServer.OnSkill(player: Player, char: Model, skillIndex: number, _origin: Vector3, dir: Vector3, config: any, aimAt: Vector3?)
	local st = getState(player)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	dir = flat(dir)
	if skillIndex == 3 then
		unchain(player, char, st, root, dir, config)
		return
	end
	local empowered = takeEmpowered(player)
	if empowered then fx({ kind = "empowered", attacker = player, skill = skillIndex }) end
	if skillIndex == 1 then
		rupture(player, char, st, root, dir, aimAt, config, empowered)
	elseif skillIndex == 2 then
		bloodstorm(player, char, st, root, dir, config, empowered)
	elseif skillIndex == 4 then
		worldbreaker(player, char, st, root, dir, aimAt, config, empowered)
	end
end

-- (the ultimate's opening: mobs hold still while he gathers)
BerserkerServer.GATHER_TIME = WB.gather

-- Fresh combo and no Unchained state (new character / run).
function BerserkerServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil, st.guardUntil = 0, 0, 0, 0
	player:SetAttribute("BR_UnchainedUntil", nil)
	player:SetAttribute("BR_Empowered", nil)
end

function BerserkerServer.Init(helpers: any)
	H = helpers
	-- Bloodstorm: half damage while storming.
	if helpers.addIncomingHook then
		helpers.addIncomingHook(function(player: Player, _char: Model, damage: number): number
			local st = states[player]
			if st and os.clock() < st.guardUntil then return damage * STORM_GUARD end
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
