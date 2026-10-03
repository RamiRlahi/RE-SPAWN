--!strict
--[[
	SwordsmanServer.luau
	Server side of the Swordsman (client: SwordsmanController). Every hit and
	all state is decided here; clients get the moments to draw over
	SwordsmanFX.

	  M1 Sword Combo  a 4-hit chain: slash, cross slash, thrust, then a spinning
	                  finisher (all-round, knocks back). Resets after a pause.
	  Passive         Battle Momentum: each sword swing / skill strike that lands
	                  adds 1 (a parry adds 3), up to 10. Each stack is +4% attack
	                  speed. At 10 the next ability consumes it and is Empowered.
	  E Sword Rush    dash through enemies with two strikes; enemies hit by both
	                  take a heavier second cut. Empowered: longer, wider, a third.
	  F Parry         a short guard window. An attack landing in it is negated,
	                  the attacker is stunned, and a huge upward counter slash
	                  answers. Empowered: longer window, bigger counter.
	  Q Whirlwind     spin with the blade out: repeated hits, smaller foes are
	                  dragged in, the last cut launches everyone. Empowered:
	                  bigger radius, more hits.
	  R Blade Storm   plant the sword (mobs freeze for the moment), then flash
	                  to every enemy in the room, slashing each, and finish
	                  with a giant X that hits the whole room again.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local SwordsmanServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local SWING_INTERVAL = 0.3   -- seconds between combo swings at 1× attack speed
local COMBO_RESET = 1.0      -- a pause this long restarts the combo at hit 1
local MOMENTUM_MAX = 10
local MOMENTUM_SPEED = 0.04  -- +4% attack speed per stack

local COMBO = {
	-- range, minimum facing dot (-1 = all round), damage, source
	[1] = { range = 11, dot = 0.15, damage = 20, source = "SWORD COMBO" },
	[2] = { range = 11, dot = 0.15, damage = 20, source = "SWORD COMBO" },
	[3] = { range = 14, dot = 0.75, damage = 26, source = "SWORD COMBO" },
	[4] = { range = 12, dot = -1, damage = 38, source = "SWORD FINISHER" },
}

local STORM_WINDUP = 0.8     -- sword planted; matches the client cutscene
local STORM_STEP = 0.18      -- seconds between Blade Storm dashes
local STORM_X_RADIUS = 22

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = {
	step: number,
	lastSwing: number,
	momentum: number,
	busyUntil: number,
	parryEmpowered: boolean,
	parryConfig: any,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { step = 0, lastSwing = 0, momentum = 0, busyUntil = 0, parryEmpowered = false, parryConfig = nil }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent(Network.Remotes.SwordsmanFX):FireAllClients(payload)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

-- ── Momentum ────────────────────────────────────────────────────────────────
local function setMomentum(player: Player, st: State, v: number)
	st.momentum = math.clamp(v, 0, MOMENTUM_MAX)
	player:SetAttribute("SW_Momentum", st.momentum)
end

local function gain(player: Player, st: State, n: number)
	local before = st.momentum
	setMomentum(player, st, st.momentum + n)
	if before < MOMENTUM_MAX and st.momentum >= MOMENTUM_MAX then
		fx({ kind = "momentumMax", attacker = player })
	end
end

-- At max Momentum an ability eats it all and is Empowered.
local function consume(player: Player, st: State): boolean
	if st.momentum < MOMENTUM_MAX then return false end
	setMomentum(player, st, 0)
	return true
end

-- ── Hit shapes ──────────────────────────────────────────────────────────────
local function inArc(char: Model, origin: Vector3, dir: Vector3, range: number, minDot: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - origin
		local fd = Vector3.new(d.X, 0, d.Z)
		if fd.Magnitude <= range then
			if minDot <= -1 or fd.Magnitude < 3 or dir:Dot(fd.Unit) >= minDot then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function onLine(char: Model, from: Vector3, dir: Vector3, length: number, width: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - from
		local along = Vector3.new(d.X, 0, d.Z):Dot(dir)
		if along >= -2 and along <= length + 2 then
			local closest = from + dir * along
			if Vector3.new(t.rootPart.Position.X - closest.X, 0, t.rootPart.Position.Z - closest.Z).Magnitude <= width then
				table.insert(out, t)
			end
		end
	end
	return out
end

local function isHeavy(t: Target): boolean
	return t.character:GetAttribute("IsBoss") == true or t.character:GetAttribute("IsElite") == true
end

-- ── M1: Sword Combo ─────────────────────────────────────────────────────────
function SwordsmanServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1) * (1 + MOMENTUM_SPEED * st.momentum)
	if now - st.lastSwing < (SWING_INTERVAL / speed) * 0.85 then return end
	st.step = if now - st.lastSwing > COMBO_RESET then 1 else (st.step % 4) + 1
	st.lastSwing = now

	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local c = COMBO[st.step]
	local size = stat(player, "size")
	local damage = c.damage * stat(player, "damage")
	local hits = inArc(char, root.Position, dir, c.range * size, c.dot)
	for _, t in ipairs(hits) do
		H.dealDamage(player, t, damage, c.source)
	end
	if #hits > 0 then gain(player, st, 1) end
	fx({ kind = "combo", attacker = player, step = st.step, dir = dir, hit = #hits > 0 })
end

-- ── Skills ──────────────────────────────────────────────────────────────────
local function swordRush(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, config: any, empowered: boolean)
	local dist = (config.dashDistance or 20) * (if empowered then 1.5 else 1)
	local width = (config.width or 6) * (config.areaMultiplier or 1) * (if empowered then 1.4 else 1)
	local damage = config.damage or 30
	char:SetAttribute("InvulnerableUntil", os.clock() + 0.35)
	fx({ kind = "rush", attacker = player, from = origin, to = origin + dir * dist, empowered = empowered })

	local struckOnce: { [Model]: boolean } = {}
	local strikes = if empowered then 3 else 2
	for n = 1, strikes do
		task.delay(0.06 + (n - 1) * 0.13, function()
			if not char.Parent then return end
			local hits = onLine(char, origin, dir, dist, width)
			for _, t in ipairs(hits) do
				-- The second cut bites harder into anyone the first one caught.
				local mult = if n == 2 and struckOnce[t.character] then 1.6 elseif n == 3 then 1.3 else 1
				H.dealDamage(player, t, damage * mult, "SWORD RUSH")
				struckOnce[t.character] = true
			end
			if #hits > 0 then gain(player, st, 1) end
			fx({ kind = "rushCut", attacker = player, n = n, from = origin, to = origin + dir * dist, empowered = empowered })
		end)
	end
end

local function parry(player: Player, char: Model, st: State, config: any, empowered: boolean)
	local window = (config.duration or 0.6) * (if empowered then 1.6 else 1)
	char:SetAttribute("ParryUntil", os.clock() + window)
	st.parryEmpowered = empowered
	st.parryConfig = config
	fx({ kind = "guard", attacker = player, window = window, empowered = empowered })
end

-- Called by MobManager when an attack lands inside the parry window.
local function onParried(targetChar: Model, attacker: Model?): boolean
	local player = Players:GetPlayerFromCharacter(targetChar)
	if not player or player:GetAttribute("SelectedClass") ~= "swordsman" then return false end
	local st = getState(player)
	local root = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return false end
	targetChar:SetAttribute("ParryUntil", 0) -- one parry per guard
	targetChar:SetAttribute("InvulnerableUntil", os.clock() + 0.5)

	-- Stun whoever swung.
	local aRoot = attacker and (attacker:FindFirstChild("HumanoidRootPart") or attacker.PrimaryPart) :: BasePart?
	if attacker then
		local stun = if attacker:GetAttribute("IsBoss") == true then 0.8 else 2.2
		attacker:SetAttribute("StaggerUntil", os.clock() + stun)
		attacker:SetAttribute("StunnedUntil", os.clock() + stun)
	end
	local toward = if aRoot then flat(aRoot.Position - root.Position) else root.CFrame.LookVector
	fx({ kind = "parry", attacker = player, pos = root.Position, dir = toward, empowered = st.parryEmpowered })
	gain(player, st, 3)

	-- The counter: a huge upward slash in front (always catching the attacker).
	local config = st.parryConfig or {}
	local empowered = st.parryEmpowered
	task.delay(0.12, function()
		if not targetChar.Parent then return end
		local damage = (config.damage or 90) * (if empowered then 1.6 else 1)
		local range = (config.range or 14) * (config.areaMultiplier or 1) * (if empowered then 1.3 else 1)
		local hits = inArc(targetChar, root.Position, toward, range, 0)
		local gotAttacker = false
		for _, t in ipairs(hits) do
			H.dealDamage(player, t, damage, "COUNTER SLASH", { forceCrit = true })
			if t.character == attacker then gotAttacker = true end
		end
		if attacker and not gotAttacker then
			local hum = attacker:FindFirstChildOfClass("Humanoid")
			if hum and aRoot and hum.Health > 0 then
				H.dealDamage(player, { character = attacker, humanoid = hum, rootPart = aRoot }, damage, "COUNTER SLASH", { forceCrit = true })
			end
		end
		fx({ kind = "counter", attacker = player, pos = root.Position, dir = toward, empowered = empowered })
	end)
	return true
end

local function whirlwind(player: Player, char: Model, st: State, config: any, empowered: boolean)
	local duration = config.duration or 1.2
	local ticks = if empowered then 9 else 6
	local radius = (config.range or 13) * (config.areaMultiplier or 1) * (if empowered then 1.35 else 1)
	local damage = config.damage or 14
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	st.busyUntil = os.clock() + duration
	fx({ kind = "whirl", attacker = player, duration = duration, radius = radius, empowered = empowered })
	task.spawn(function()
		for i = 1, ticks do
			task.wait(duration / ticks)
			if not char.Parent or not root.Parent then return end
			local last = i == ticks
			local hits = inArc(char, root.Position, root.CFrame.LookVector, radius, -1)
			for _, t in ipairs(hits) do
				H.dealDamage(player, t, if last then damage * 2.5 else damage, if last then "WHIRL FINISH" else "WHIRL CUT")
				-- Drag smaller foes in (the last cut launches them instead).
				if not last and not isHeavy(t) and not t.rootPart.Anchored then
					local toward = root.Position - t.rootPart.Position
					local f = Vector3.new(toward.X, 0, toward.Z)
					if f.Magnitude > 3 then
						t.rootPart.AssemblyLinearVelocity = f.Unit * 14 + Vector3.new(0, t.rootPart.AssemblyLinearVelocity.Y, 0)
					end
				end
			end
			if #hits > 0 then gain(player, st, 1) end
		end
		fx({ kind = "whirlEnd", attacker = player, radius = radius })
	end)
end

-- Everyone Blade Storm can reach: every enemy in the caster's room (or
-- within `range` when not standing in a room), in a nearest-next path.
local function inRoom(char: Model, origin: Vector3, range: number): { Target }
	local bounds = H.roomBoundsAt and H.roomBoundsAt(origin)
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local p = t.rootPart.Position
		local ok = if bounds
			then p.X >= bounds.minX and p.X <= bounds.maxX and p.Z >= bounds.minZ and p.Z <= bounds.maxZ
				and math.abs(p.Y - bounds.floorY) < 14
			else (p - origin).Magnitude <= range
		if ok then table.insert(out, t) end
	end
	return out
end

local function bladeStorm(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, config: any, empowered: boolean)
	local range = (config.range or 45) * (config.areaMultiplier or 1)
	local damage = config.damage or 60
	-- Every enemy in the room, ordered as a path: always dash to the nearest
	-- one not yet cut. Big rooms speed the chain up so it stays snappy.
	local pool = inRoom(char, origin, range)
	local chain: { Target } = {}
	local at = origin
	while #pool > 0 do
		local bi, bd = 1, math.huge
		for i, t in ipairs(pool) do
			local d = (t.rootPart.Position - at).Magnitude
			if d < bd then bi, bd = i, d end
		end
		local t = table.remove(pool, bi)
		table.insert(chain, t)
		at = t.rootPart.Position
	end
	local step = if #chain > 0 then math.clamp(2.4 / #chain, 0.07, STORM_STEP) else STORM_STEP
	if empowered then damage *= 1.25 end

	local total = STORM_WINDUP + #chain * step + 0.45
	st.busyUntil = os.clock() + total
	char:SetAttribute("InvulnerableUntil", os.clock() + total)
	local models = {}
	for i, t in ipairs(chain) do models[i] = t.character end
	fx({ kind = "storm", attacker = player, origin = origin, dir = dir, targets = models,
		windup = STORM_WINDUP, step = step, empowered = empowered })

	for i, t in ipairs(chain) do
		task.delay(STORM_WINDUP + (i - 1) * step, function()
			if not char.Parent or t.humanoid.Health <= 0 then return end
			H.dealDamage(player, t, damage, "BLADE STORM")
			gain(player, st, 1)
		end)
	end
	task.delay(STORM_WINDUP + #chain * step + 0.3, function()
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end
		local center = root.Position
		fx({ kind = "stormX", attacker = player, pos = center, dir = dir, radius = STORM_X_RADIUS })
		-- The X lands on every enemy still in the room.
		for _, t in ipairs(inRoom(char, center, range)) do
			H.dealDamage(player, t, damage * 3, "BLADE STORM FINISH")
		end
	end)
end

-- ── Public ──────────────────────────────────────────────────────────────────
function SwordsmanServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	return os.clock() >= getState(player).busyUntil
end

function SwordsmanServer.OnSkill(player: Player, char: Model, skillIndex: number, origin: Vector3, dir: Vector3, config: any)
	local st = getState(player)
	dir = flat(dir)
	local empowered = consume(player, st)
	if empowered then fx({ kind = "empowered", attacker = player, skill = skillIndex }) end
	if skillIndex == 1 then
		swordRush(player, char, st, origin, dir, config, empowered)
	elseif skillIndex == 2 then
		parry(player, char, st, config, empowered)
	elseif skillIndex == 3 then
		whirlwind(player, char, st, config, empowered)
	elseif skillIndex == 4 then
		bladeStorm(player, char, st, origin, dir, config, empowered)
	end
end

-- Seconds the Blade Storm wind-up freezes mobs / holds the camera.
SwordsmanServer.STORM_WINDUP = STORM_WINDUP

-- Fresh combo and Momentum (new character / run).
function SwordsmanServer.Reset(player: Player)
	local st = getState(player)
	st.step, st.lastSwing, st.busyUntil = 0, 0, 0
	setMomentum(player, st, 0)
end

function SwordsmanServer.Init(helpers: any)
	H = helpers
	helpers.setParryHook(onParried)
	Players.PlayerRemoving:Connect(function(p) states[p] = nil end)
	Players.PlayerAdded:Connect(function(p)
		p.CharacterAdded:Connect(function()
			if p:GetAttribute("SelectedClass") == "swordsman" then SwordsmanServer.Reset(p) end
		end)
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		p.CharacterAdded:Connect(function()
			if p:GetAttribute("SelectedClass") == "swordsman" then SwordsmanServer.Reset(p) end
		end)
	end
end

return SwordsmanServer
