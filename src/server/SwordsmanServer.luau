--!strict
--[[
	SwordsmanServer.luau
	Server side of the Swordsman (client: SwordsmanController). Every hit and
	all state is decided here; clients get the moments to draw over
	SwordsmanFX.

	  M1 Rapier Combo a 4-hit fencing chain: lunge, riposte cut, double thrust,
	                  then a flèche (a long lunge that carries him forward).
	                  Resets after a pause.
	  Passive         Battle Momentum: each sword swing / skill strike that lands
	                  adds 1 (a parry adds 3), up to 10. Each stack is +4% attack
	                  speed. At 10 the next ability consumes it and is Empowered.
	  E Sword Rush    dash through enemies with two strikes; enemies hit by both
	                  take a heavier second cut. Empowered: longer, wider, a third.
	  F Parry         a short guard window. An attack landing in it is negated,
	                  the attacker is stunned, and he ripostes: a flick of the
	                  blade, a dash straight in and the pommel driven into its
	                  chest (it's thrown back). Empowered: longer window,
	                  harder strike.
	  Q Piercing Judgement  held: on guard, the rapier's point gathering
	                  energy (up to JUDGE.full; let go any time, or it goes by
	                  itself if held at full too long), then a lunge and a needle
	                  thrust down a line, longer and harder the more it was
	                  charged. Every extra projectile (Projectile Count) adds a
	                  phantom echo down the same line a beat later, each a real
	                  hit. Empowered: charges faster, longer, harder, two more
	                  echoes.
	  R Blade Storm   en garde (mobs freeze for the moment), then flash to
	                  every enemy in the room, at least 8 cuts (a small room is
	                  cut more than once), and finish with a giant X that hits
	                  the whole room again. An empty room: straight to the X.
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
	[1] = { range = 13, dot = 0.7, damage = 20, source = "RAPIER LUNGE" },
	[2] = { range = 11, dot = 0.15, damage = 20, source = "RIPOSTE" },
	[3] = { range = 13, dot = 0.7, damage = 26, source = "DOUBLE THRUST" },
	[4] = { range = 16, dot = 0.6, damage = 38, source = "FLÈCHE" },
}

local STORM_WINDUP = 1.2     -- en garde; matches the client cutscene
local STORM_STEP = 0.18      -- seconds between Blade Storm dashes
local STORM_MIN_CUTS = 8     -- a room with fewer enemies is cut more than once
local STORM_X_RADIUS = 22
local ECHO_STEP = 0.16       -- seconds between the Judgement's thrust and each echo
-- Piercing Judgement (mirrored in SwordsmanController): seconds to a full
-- charge (Empowered: empFull), how long it can be held at full before it
-- goes by itself, the lunge and the line it pierces (tap → full), the damage
-- multiplier at full, and when the point lands after the release.
local JUDGE = { full = 2.4, empFull = 1.4, still = 1.6, lunge = 4, fullLunge = 11,
	length = 16, fullLength = 32, maxMult = 3, hit = 0.07 }
local RIPOSTE_HIT = 0.3      -- parry → the pommel lands (SwordsmanController's riposte)
local RIPOSTE_REACH = 16     -- furthest the riposte's dash carries him
local RIPOSTE_TIME = 0.8     -- the whole riposte, recovery included
local POMMEL_SPLASH = 5      -- others this close to the one struck are caught too

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type State = {
	step: number,
	lastSwing: number,
	momentum: number,
	busyUntil: number,
	parryEmpowered: boolean,
	parryConfig: any,
	judge: { t0: number, full: number, config: any, empowered: boolean, token: {} }?,
	pendingRelease: { at: number, held: number?, dir: Vector3? }?,
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
	local window = (config.duration or 1.2) * (if empowered then 1.6 else 1)
	char:SetAttribute("ParryUntil", os.clock() + window)
	st.busyUntil = math.max(st.busyUntil, os.clock() + window) -- (committed to the guard)
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
	targetChar:SetAttribute("InvulnerableUntil", os.clock() + RIPOSTE_TIME)
	st.busyUntil = os.clock() + RIPOSTE_TIME

	-- Stun whoever swung.
	local aRoot = attacker and (attacker:FindFirstChild("HumanoidRootPart") or attacker.PrimaryPart) :: BasePart?
	if attacker then
		local stun = if attacker:GetAttribute("IsBoss") == true then 0.8 else 2.2
		attacker:SetAttribute("StaggerUntil", os.clock() + stun)
		attacker:SetAttribute("StunnedUntil", os.clock() + stun)
	end
	local toward = if aRoot then flat(aRoot.Position - root.Position) else root.CFrame.LookVector
	-- (the client dashes in to `target`, if it's within reach)
	local inReach = aRoot ~= nil and (aRoot.Position - root.Position).Magnitude <= RIPOSTE_REACH + 4
	fx({ kind = "parry", attacker = player, pos = root.Position, dir = toward, empowered = st.parryEmpowered,
		target = if inReach then attacker else nil, to = if inReach and aRoot then aRoot.Position else nil })
	gain(player, st, 3)

	-- The riposte: the pommel lands on the attacker (and anyone pressed close
	-- to it), or just ahead of him if it was out of reach.
	local config = st.parryConfig or {}
	local empowered = st.parryEmpowered
	task.delay(RIPOSTE_HIT, function()
		if not targetChar.Parent then return end
		local damage = (config.damage or 90) * (if empowered then 1.6 else 1)
		local splash = POMMEL_SPLASH * (config.areaMultiplier or 1) * (if empowered then 1.3 else 1)
		local at = if inReach and aRoot and aRoot.Parent then aRoot.Position else root.Position + toward * 3
		local struck = false
		for _, t in ipairs(H.getPotentialTargets(targetChar)) do
			local d = t.rootPart.Position - at
			if Vector3.new(d.X, 0, d.Z).Magnitude <= splash then
				H.dealDamage(player, t, damage, "POMMEL STRIKE", { forceCrit = true })
				if t.character == attacker then struck = true end
			end
		end
		if inReach and attacker and not struck then
			local hum = attacker:FindFirstChildOfClass("Humanoid")
			if hum and aRoot and hum.Health > 0 then
				H.dealDamage(player, { character = attacker, humanoid = hum, rootPart = aRoot }, damage, "POMMEL STRIKE", { forceCrit = true })
			end
		end
		fx({ kind = "counter", attacker = player, pos = at, dir = toward, empowered = empowered })
	end)
	return true
end

-- ── Q: Piercing Judgement ──────────────────────────────────────────────────
-- The release: `held` is how long the client says the key was down (never
-- more than the server has seen), `aim` where the point goes.
local function judgeRelease(player: Player, held: number?, aim: Vector3?)
	local st = getState(player)
	local j = st.judge
	if not j then return end
	st.judge = nil
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and root) then
		st.busyUntil = 0
		return
	end
	local now = os.clock()
	local elapsed = now - j.t0
	local h = math.clamp(tonumber(held) or elapsed, 0, elapsed + 0.15)
	local c = math.clamp(h / j.full, 0, 1)
	local config = j.config
	local area = config.areaMultiplier or 1
	local dir = flat(if typeof(aim) == "Vector3" then aim else root.CFrame.LookVector)
	local length = (JUDGE.length + (JUDGE.fullLength - JUDGE.length) * c) * area * (if j.empowered then 1.3 else 1)
	local width = (config.width or 3.5) * area
	local damage = (config.damage or 45) * (1 + (JUDGE.maxMult - 1) * c) * (if j.empowered then 1.5 else 1)
	local echoes = math.max(0, math.floor(stat(player, "projectileCount"))) + (if j.empowered then 2 else 0)
	local from = root.Position
	st.busyUntil = now + 0.7
	fx({ kind = "judgeRelease", attacker = player, from = from, dir = dir, charge = c, length = length,
		lunge = JUDGE.lunge + (JUDGE.fullLunge - JUDGE.lunge) * c, echoes = echoes, step = ECHO_STEP,
		empowered = j.empowered })
	for n = 0, echoes do
		task.delay(JUDGE.hit + n * ECHO_STEP, function()
			if not char.Parent then return end
			local hits = onLine(char, from, dir, length, width)
			local at = {}
			for _, t in ipairs(hits) do
				H.dealDamage(player, t, if n == 0 then damage else damage * 0.6,
					if n == 0 then (if c >= 0.999 then "PIERCING JUDGEMENT!" else "PIERCING JUDGEMENT") else "JUDGEMENT ECHO")
				table.insert(at, t.rootPart.Position)
			end
			if #hits > 0 then gain(player, st, 1) end
			if n == 0 and #at > 0 then fx({ kind = "judgePierced", attacker = player, dir = dir, hits = at, charge = c }) end
		end)
	end
end

local function judgeStart(player: Player, config: any, empowered: boolean)
	local st = getState(player)
	local now = os.clock()
	local full = if empowered then JUDGE.empFull else JUDGE.full
	local token = {}
	st.judge = { t0 = now, full = full, config = config, empowered = empowered, token = token }
	st.busyUntil = math.max(st.busyUntil, now + full + JUDGE.still + 1)
	fx({ kind = "judgeCharge", attacker = player, full = full, still = JUDGE.still, empowered = empowered })
	-- (a release that got here ahead of the cast: a tap)
	local pend = st.pendingRelease
	st.pendingRelease = nil
	if pend and now - pend.at < 0.6 then
		judgeRelease(player, pend.held, pend.dir)
		return
	end
	-- (never let go: it goes by itself; a little grace for the client's own)
	task.delay(full + JUDGE.still + 0.15, function()
		local j = st.judge
		if j and j.token == token then judgeRelease(player, full, nil) end
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
	-- At least STORM_MIN_CUTS: go round the room again (nobody in it: no
	-- cuts, straight to the X).
	local n = #chain
	if n > 0 then
		for i = n + 1, STORM_MIN_CUTS do
			table.insert(chain, chain[(i - 1) % n + 1])
		end
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
		judgeStart(player, config, empowered)
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
	st.judge, st.pendingRelease = nil, nil
	setMomentum(player, st, 0)
end

function SwordsmanServer.Init(helpers: any)
	-- (a dash cuts the move short: free to act again, and what was left of it doesn't land)
	(require(script.Parent:WaitForChild("Dash")) :: any).OnDash(function(p: Player)
		local st = states[p] :: any
		if not st then return end
		st.busyUntil = 0
		if type(st.token) == "number" then st.token += 1 end
	end)
	H = helpers
	helpers.setParryHook(onParried)
	-- Piercing Judgement's key let go (or a tap that beat the cast here).
	Network.GetRemoteEvent(Network.Remotes.SwordsmanInput).OnServerEvent:Connect(function(player: Player, msg: any)
		if typeof(msg) ~= "table" or msg.kind ~= "release" then return end
		if player:GetAttribute("SelectedClass") ~= "swordsman" then return end
		local held = tonumber(msg.held)
		local dir = if typeof(msg.dir) == "Vector3" then msg.dir else nil
		local st = getState(player)
		if st.judge then
			judgeRelease(player, held, dir)
		else
			st.pendingRelease = { at = os.clock(), held = held, dir = dir }
		end
	end)
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
