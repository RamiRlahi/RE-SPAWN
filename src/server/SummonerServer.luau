--!strict
--[[
	SummonerServer.luau
	Server side of the Summoner, "The Beastcaller" (client: SummonerController,
	the beasts' looks and moves: Summons/Beasts). Every beast's body, mind and
	hit is decided here; clients draw them from Workspace.Summons and the
	moments sent over SummonerFX. Tuning: SummonerData.

	  M1 Bond Bolt      a spirit bolt from the staff; whatever it hits becomes
	                    every beast's Focus for a few seconds.
	  Passive Pack Bond each other beast on the field makes every beast hit
	                    harder.
	  E Rockborn        crashes down where you aim as a meteor and fights:
	                    taunts, hooks, hammer fists. Recast: Ground Slam, a
	                    leap to the aim and a slam that splits the floor.
	  F Skyfeather      dives in and hovers, firing feather volleys and diving
	                    on enemies. Recast: Wind Circle, a cyclone at the aim
	                    that drags enemies in and bursts.
	  Q Lunari          rises from a moon gate: heals the party in pulses,
	                    jabs and tramples through lines. Recast: Radiant
	                    Bloom, a rearing stomp that blooms moonlight: heals
	                    the party, stuns and burns enemies.
	  R Divine          every beast flies to you and fuses into the
	    Cataclysm       Skyrockorn: it circles raining starfire, rears and
	                    fires judgement rays, then crashes down. The beasts
	                    it was made of come back out of it.

	A beast's body: a Model in Workspace.Summons with an invisible
	HumanoidRootPart (unanchored, owned by the server, held by AlignPosition /
	AlignOrientation, so every client sees it glide smoothly) and a Humanoid
	(no state machine); IsAlly so nothing of ours hits it; the Rockborn is
	also a decoy (MobManager taunts mobs onto it, and they can break it).
	Attributes: Summon (kind), Owner (UserId), Expires (server time).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local SummonerData = require(Shared:WaitForChild("SummonerData"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local SummonerServer = {}

local BEAST = SummonerData.BEAST
local LIFT = SummonerData.ROOT_LIFT
local BOLT = SummonerData.BOLT
local LEASH = 46       -- a beast never chases further than this from you
local ENGAGE = 34      -- it picks fights this close to itself
local CATCH_UP = 72    -- further than this from you: it blinks back to your side
local THINK = 0.2      -- seconds between target choices

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type Beast = {
	kind: string,
	owner: Player,
	model: Model,
	root: BasePart,
	hum: Humanoid,
	align: AlignPosition,
	orient: AlignOrientation,
	pos: Vector3,        -- its ground origin, flat (y: the floor under it)
	vel: Vector3,
	face: Vector3,
	fly: number,         -- how high it flies over the floor right now
	expires: number,
	nextThink: number,
	nextAttack: number,
	busyUntil: number,   -- mid-attack: it stands its ground
	swings: number,
	target: Target?,
	script: ((number, number) -> boolean)?, -- a scripted move in control (true: done)
	scriptKind: string?,
	nextPulse: number,
	nextCharge: number,
	gone: boolean,
}
type State = {
	beasts: { [string]: Beast },
	lastBolt: number,
	busyUntil: number,
	sigReady: { [string]: number },
	focus: Model?,
	focusUntil: number,
	ulting: boolean,
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}
local folder: Folder

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = { beasts = {}, lastBolt = 0, busyUntil = 0, sigReady = {}, focus = nil, focusUntil = 0, ulting = false }
		states[player] = st
	end
	return st
end

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function fx(payload: any)
	Network.GetRemoteEvent("SummonerFX"):FireAllClients(payload)
end

local function now(): number
	return Workspace:GetServerTimeNow()
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function rootOf(char: Model?): BasePart?
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function isBoss(t: Target): boolean
	return t.character:GetAttribute("IsBoss") == true
end

local function alive(t: Target?): boolean
	return t ~= nil and t.character.Parent ~= nil and t.humanoid.Health > 0 and t.rootPart.Parent ~= nil
end

-- ── The world ───────────────────────────────────────────────────────────────
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.RespectCanCollide = true
local function refreshFloorParams()
	local ignore: { Instance } = { folder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	floorParams.FilterDescendantsInstances = ignore
end

-- The floor under a point (searching from a little above it).
local function floorY(pos: Vector3, from: number?): number?
	local top = from or pos.Y
	local res = Workspace:Raycast(Vector3.new(pos.X, top + 6, pos.Z), Vector3.new(0, -40, 0), floorParams)
	return if res then res.Position.Y else nil
end

local function floorAt(pos: Vector3): Vector3
	local y = floorY(pos)
	return if y then Vector3.new(pos.X, y, pos.Z) else pos
end

-- How far you can go from `from` along `dir` before a wall (at knee height).
local function clear(from: Vector3, dir: Vector3, length: number): number
	local res = Workspace:Raycast(from + Vector3.new(0, 2.5, 0), dir * length, floorParams)
	return if res then math.max(0, res.Distance - 2) else length
end

-- ── Targets ─────────────────────────────────────────────────────────────────
local function inRadius(char: Model, center: Vector3, radius: number): { Target }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local d = t.rootPart.Position - center
		if Vector3.new(d.X, 0, d.Z).Magnitude <= radius + H.lineReach(t, 0) * 0.5 and math.abs(d.Y) < radius + 8 then
			table.insert(out, t)
		end
	end
	return out
end

local function targetOf(model: Model?): Target?
	if not model or not model.Parent then return nil end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local r = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not hum or not r or not r:IsA("BasePart") or hum.Health <= 0 then return nil end
	return { character = model, humanoid = hum, rootPart = r }
end

local function hold(t: Target, seconds: number)
	if isBoss(t) then return end
	local untilT = os.clock() + seconds
	if (tonumber(t.character:GetAttribute("StaggerUntil")) or 0) < untilT then
		t.character:SetAttribute("StaggerUntil", untilT)
	end
end

local function pull(t: Target, center: Vector3, speed: number)
	if isBoss(t) then return end
	local d = Vector3.new(center.X - t.rootPart.Position.X, 0, center.Z - t.rootPart.Position.Z)
	if d.Magnitude < 1 then return end
	t.rootPart.AssemblyLinearVelocity = d.Unit * math.min(speed, d.Magnitude * 5) + Vector3.new(0, t.rootPart.AssemblyLinearVelocity.Y, 0)
end

local function launch(t: Target, from: Vector3, push: number, lift: number, holdFor: number)
	if isBoss(t) then return end
	local away = flat(t.rootPart.Position - from)
	H.knock(t, away * push, lift, 0.25)
	hold(t, holdFor)
end

-- Pack Bond: every beast hits harder for each other beast out.
local function packMult(st: State): number
	local n = 0
	for _, b in pairs(st.beasts) do
		if not b.gone then n += 1 end
	end
	return 1 + SummonerData.PACK_BONUS * math.max(0, n - 1)
end

local function hit(player: Player, t: Target, damage: number, source: string): number?
	if t.humanoid.Health <= 0 then return nil end
	return H.dealDamage(player, t, damage, source)
end

local function beastDamage(b: Beast, base: number): number
	return base * stat(b.owner, "damage") * packMult(getState(b.owner))
end

-- Allies (players) in reach get back a share of their max health.
local function healAround(center: Vector3, radius: number, share: number): { Model }
	local healed = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local c = p.Character
		local r = rootOf(c)
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		if c and r and hum and hum.Health > 0 and p:GetAttribute("InLobby") == false and flatDist(r.Position, center) <= radius then
			hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * share)
			table.insert(healed, c)
		end
	end
	return healed
end

-- ── Bodies ──────────────────────────────────────────────────────────────────
local function bodyCF(b: Beast): CFrame
	return CFrame.lookAt(Vector3.zero, b.face)
end

local function place(b: Beast)
	b.align.Position = b.pos + Vector3.new(0, LIFT + b.fly, 0)
	b.orient.CFrame = bodyCF(b)
end

local function newBody(player: Player, kind: string, at: Vector3, face: Vector3, life: number): Beast
	local cfg = BEAST[kind]
	local m = Instance.new("Model")
	m.Name = `Summon_{kind}_{player.UserId}`
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.CanCollide, root.CanQuery, root.CanTouch = false, false, false
	root.CFrame = CFrame.lookAt(at + Vector3.new(0, LIFT + cfg.fly, 0), at + Vector3.new(0, LIFT + cfg.fly, 0) + face)
	root.Parent = m
	m.PrimaryPart = root
	local att = Instance.new("Attachment")
	att.Parent = root
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.RigidityEnabled = true
	align.Position = root.Position
	align.Parent = root
	local orient = Instance.new("AlignOrientation")
	orient.Mode = Enum.OrientationAlignmentMode.OneAttachment
	orient.Attachment0 = att
	orient.RigidityEnabled = true
	orient.CFrame = CFrame.lookAt(Vector3.zero, face)
	orient.Parent = root
	local hum = Instance.new("Humanoid")
	hum.EvaluateStateMachine = false
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	local maxHp = 1e6
	if cfg.hp then
		local own = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		maxHp = math.max(200, (if own then own.MaxHealth else 100) * cfg.hp)
	end
	hum.MaxHealth = maxHp
	hum.Health = maxHp
	hum.Parent = m
	m:SetAttribute("IsAlly", true)
	m:SetAttribute("Summon", kind)
	m:SetAttribute("Owner", player.UserId)
	m:SetAttribute("Expires", now() + life)
	m:SetAttribute("Life", life)
	if cfg.taunt then m:SetAttribute("IsDecoy", true) end
	m.Parent = folder
	pcall(function() root:SetNetworkOwner(nil) end)
	local b: Beast = {
		kind = kind, owner = player, model = m, root = root, hum = hum, align = align, orient = orient,
		pos = at, vel = Vector3.zero, face = face, fly = cfg.fly, expires = os.clock() + life,
		nextThink = 0, nextAttack = os.clock() + 0.8, busyUntil = 0, swings = 0, target = nil,
		script = nil, scriptKind = nil, nextPulse = os.clock() + 1, nextCharge = os.clock() + 2, gone = false,
	}
	if cfg.taunt then H.registerDecoy(m, cfg.taunt) end
	return b
end

-- Gone: `how` is "expire" (fades), "break" (the Rockborn smashed), "fuse"
-- (into the Skyrockorn: no effect of its own), "quiet".
local function dismiss(b: Beast, how: string)
	if b.gone then return end
	b.gone = true
	local st = states[b.owner]
	if st and st.beasts[b.kind] == b then st.beasts[b.kind] = nil end
	if how ~= "quiet" then
		fx({ kind = "dismiss", owner = b.owner, model = b.model, beast = b.kind, how = how, pos = b.pos })
	end
	b.model:SetAttribute("Leaving", how)
	-- (the client's fade-out reads the body a moment longer)
	task.delay(if how == "quiet" then 0 else 1.2, function() b.model:Destroy() end)
	if b.kind ~= "fused" then
		b.owner:SetAttribute("SUM_" .. b.kind, nil)
	end
end

local function dismissAll(player: Player, how: string)
	local st = states[player]
	if not st then return end
	for _, b in pairs(st.beasts) do dismiss(b, how) end
	st.ulting = false
end

-- ── Moving ──────────────────────────────────────────────────────────────────
local function turnToward(b: Beast, want: Vector3, dt: number)
	want = flat(want)
	local rate = BEAST[b.kind].turn
	local cur = b.face
	local ang = math.acos(math.clamp(cur:Dot(want), -1, 1))
	if ang < 1e-3 then b.face = want return end
	local k = math.min(1, rate * dt / ang)
	b.face = flat(cur:Lerp(want, k))
end

-- Steer toward `goal` (flat), easing in as it arrives.
local function steer(b: Beast, goal: Vector3, dt: number, speedMult: number?)
	local cfg = BEAST[b.kind]
	local d = Vector3.new(goal.X - b.pos.X, 0, goal.Z - b.pos.Z)
	local dist = d.Magnitude
	local top = cfg.speed * (speedMult or 1)
	local want = if dist > 0.4 then d.Unit * math.min(top, dist * 3.2) else Vector3.zero
	local dv = want - b.vel
	local maxDv = cfg.accel * dt
	if dv.Magnitude > maxDv then dv = dv.Unit * maxDv end
	b.vel += dv
	local step = b.vel * dt
	-- walkers stop at walls (fliers sail over the low ones)
	if step.Magnitude > 1e-3 and cfg.fly == 0 then
		local free = clear(b.pos, step.Unit, step.Magnitude + 1)
		if free < step.Magnitude then
			step = step.Unit * free
			b.vel *= 0.5
		end
	end
	local nextPos = b.pos + step
	local y = floorY(nextPos, b.pos.Y + 2)
	-- (no floor there: a gap; a walker won't step off)
	if y == nil then
		if cfg.fly == 0 then b.vel = Vector3.zero return end
		y = b.pos.Y
	elseif cfg.fly == 0 and y > b.pos.Y + 3.5 then
		b.vel = Vector3.zero
		return
	end
	b.pos = Vector3.new(nextPos.X, y :: number, nextPos.Z)
end

-- Where it stands beside you when there's nothing to fight.
local function slotFor(b: Beast, ownerRoot: BasePart): Vector3
	local cfg = BEAST[b.kind]
	local look = flat(ownerRoot.CFrame.LookVector)
	local right = Vector3.new(-look.Z, 0, look.X)
	local s = cfg.slot
	return ownerRoot.Position + right * s.X - look * s.Z
end

-- Back at your side in a flash (lost behind a wall, left behind).
local function blinkTo(b: Beast, at: Vector3)
	local from = b.pos
	b.pos = floorAt(at)
	b.vel = Vector3.zero
	place(b)
	b.root.CFrame = CFrame.new(b.pos + Vector3.new(0, LIFT + b.fly, 0)) * bodyCF(b)
	fx({ kind = "blink", owner = b.owner, model = b.model, beast = b.kind, from = from, to = b.pos })
end

-- ── Choosing a fight ────────────────────────────────────────────────────────
local function pickTarget(b: Beast, ownerRoot: BasePart): Target?
	local st = getState(b.owner)
	local ownerChar = b.owner.Character :: Model
	-- your Focus first (what your Bond Bolt last hit)
	if st.focus and os.clock() < st.focusUntil then
		local t = targetOf(st.focus)
		if t and flatDist(t.rootPart.Position, ownerRoot.Position) < LEASH + 10 then return t end
	end
	-- keep the one it's on while it's still in reach
	local cur = b.target
	if cur and alive(cur) and flatDist(cur.rootPart.Position, ownerRoot.Position) < LEASH then return cur end
	local best, bestScore = nil, math.huge
	for _, t in ipairs(H.getPotentialTargets(ownerChar)) do
		local dOwner = flatDist(t.rootPart.Position, ownerRoot.Position)
		local dMe = flatDist(t.rootPart.Position, b.pos)
		if dOwner < LEASH and dMe < ENGAGE + 10 then
			-- (closest to it, but enemies on top of you count closer)
			local score = dMe + dOwner * 0.5
			if score < bestScore then best, bestScore = t, score end
		end
	end
	return best
end

-- ── Attacks ─────────────────────────────────────────────────────────────────
local function act(b: Beast, name: string, extra: { [string]: any }?)
	local msg: { [string]: any } = { kind = "act", owner = b.owner, model = b.model, beast = b.kind, act = name }
	if extra then for k, v in pairs(extra) do msg[k] = v end end
	fx(msg)
end

-- Everything in front of it within `range` and `arc` degrees each side.
local function inCone(b: Beast, range: number, arc: number): { Target }
	local out = {}
	local cosA = math.cos(math.rad(arc))
	for _, t in ipairs(H.getPotentialTargets(b.owner.Character :: Model)) do
		local d = Vector3.new(t.rootPart.Position.X - b.pos.X, 0, t.rootPart.Position.Z - b.pos.Z)
		local reach = range + H.lineReach(t, 0) * 0.5
		if d.Magnitude <= reach and math.abs(t.rootPart.Position.Y - b.pos.Y) < 9
			and (d.Magnitude < 2.5 or b.face:Dot(d.Unit) >= cosA) then
			table.insert(out, t)
		end
	end
	return out
end

local function later(b: Beast, t: number, fn: () -> ())
	task.delay(t, function()
		if not b.gone and b.model.Parent then fn() end
	end)
end

-- Rockborn: a left hook, a right hook, then a two-fisted hammer.
local function rockAttack(b: Beast, t: Target)
	local cfg = BEAST.rock
	b.swings += 1
	local o = os.clock()
	if b.swings % 3 == 0 then
		local h = cfg.hammer
		b.busyUntil = o + h.dur
		b.nextAttack = o + cfg.attack.every + 0.4
		act(b, "hammer", { dur = h.dur })
		later(b, h.hit, function()
			local at = b.pos + b.face * 3.5
			fx({ kind = "rockHammer", owner = b.owner, model = b.model, pos = at, radius = h.radius })
			for _, e in ipairs(inRadius(b.owner.Character :: Model, at, h.radius)) do
				if hit(b.owner, e, beastDamage(b, h.damage), "ROCKBORN") then launch(e, at, 14, 26, 0.6) end
			end
		end)
	else
		local a = cfg.attack
		local name = if b.swings % 3 == 1 then "hookL" else "hookR"
		b.busyUntil = o + a.dur
		b.nextAttack = o + a.every
		act(b, name, { dur = a.dur })
		later(b, a.hit, function()
			local struck = false
			for _, e in ipairs(inCone(b, a.range, a.arc)) do
				if hit(b.owner, e, beastDamage(b, a.damage), "ROCKBORN") then
					struck = true
					launch(e, b.pos, 22, 6, 0.3)
				end
			end
			if struck then act(b, "impact", { pos = b.pos + b.face * 4 + Vector3.new(0, 4, 0) }) end
		end)
	end
end

-- A projectile on a straight path: the first enemy it reaches is hit.
local function flyBolt(owner: Player, from: Vector3, dir: Vector3, speed: number, range: number, width: number,
	onHit: (Target, Vector3) -> (), onEnd: ((Vector3) -> ())?)
	local char = owner.Character
	if not char then return end
	local length = clear(from - Vector3.new(0, 2.5, 0), dir, range)
	task.spawn(function()
		local flown = 0
		while flown < length do
			local dt = RunService.Heartbeat:Wait()
			if not char.Parent then return end
			flown = math.min(length, flown + speed * dt)
			local p = from + dir * flown
			for _, t in ipairs(H.getPotentialTargets(char)) do
				local r = H.lineReach(t, width)
				local d = t.rootPart.Position - p
				if Vector3.new(d.X, 0, d.Z).Magnitude <= r and math.abs(d.Y) < 6 then
					onHit(t, p)
					if onEnd then onEnd(p) end
					return
				end
			end
		end
		if onEnd then onEnd(from + dir * length) end
	end)
end

-- Skyfeather: a fan of feather blades; every third attack, a dive.
local function skyStartDive(b: Beast, t: Target)
	local cfg = BEAST.sky.dive
	local from = b.pos
	local o = os.clock()
	b.busyUntil = o + cfg.dur
	b.nextAttack = o + BEAST.sky.attack.every + 0.5
	local aim = floorAt(t.rootPart.Position)
	local back = from + flat(from - aim) * 2
	act(b, "dive", { dur = cfg.dur, to = aim })
	local t0 = o
	local struck = false
	b.scriptKind = "dive"
	b.script = function(clock: number, dt: number): boolean
		local a = (clock - t0) / cfg.dur
		if a >= 1 then
			b.fly = BEAST.sky.fly
			return true
		end
		-- down onto it by the hit, then back up and away
		if a < cfg.hit / cfg.dur then
			local u = a / (cfg.hit / cfg.dur)
			b.pos = from:Lerp(aim, u * u)
			b.fly = BEAST.sky.fly * (1 - u) + 1.2 * u
		else
			local u = (a - cfg.hit / cfg.dur) / (1 - cfg.hit / cfg.dur)
			b.pos = aim:Lerp(back, u)
			b.fly = 1.2 + (BEAST.sky.fly - 1.2) * (1 - (1 - u) ^ 2)
			if not struck then
				struck = true
				fx({ kind = "skyDiveHit", owner = b.owner, model = b.model, pos = aim, radius = cfg.radius })
				for _, e in ipairs(inRadius(b.owner.Character :: Model, aim, cfg.radius)) do
					if hit(b.owner, e, beastDamage(b, cfg.damage), "SKYFEATHER") then launch(e, aim, 16, 18, 0.4) end
				end
			end
		end
		turnToward(b, aim - b.pos, dt)
		local y = floorY(b.pos, b.pos.Y + 2)
		if y then b.pos = Vector3.new(b.pos.X, y, b.pos.Z) end
		return false
	end
end

local function skyAttack(b: Beast, t: Target)
	local cfg = BEAST.sky
	b.swings += 1
	if b.swings % cfg.dive.every == 0 then
		skyStartDive(b, t)
		return
	end
	local a = cfg.attack
	local o = os.clock()
	b.busyUntil = o + a.dur
	b.nextAttack = o + a.every / math.max(stat(b.owner, "basicAttackSpeed"), 0.5)
	act(b, "volley", { dur = a.dur })
	later(b, a.hit, function()
		if not alive(t) then return end
		local from = b.pos + Vector3.new(0, b.fly + 2.2, 0) + b.face * 1.5
		local aim = flat(t.rootPart.Position - from)
		local count = a.count + math.max(0, math.floor(stat(b.owner, "projectileCount")))
		local speed = a.speed * stat(b.owner, "projectileSpeed")
		local dirs = {}
		for k = 1, count do
			local ang = math.rad((k - (count + 1) / 2) * a.spread)
			local d = flat((CFrame.Angles(0, ang, 0) * CFrame.lookAt(Vector3.zero, aim)).LookVector)
			table.insert(dirs, d)
			-- (feathers fall toward the target's height as they go)
			local drop = (t.rootPart.Position.Y - from.Y)
			flyBolt(b.owner, from + Vector3.new(0, drop * 0.5, 0), d, speed, a.range, 2.4, function(e, p)
				if hit(b.owner, e, beastDamage(b, a.damage), "SKYFEATHER") then
					if H.fxAllowed(b.owner, "sumFeather", 18) then
						fx({ kind = "featherHit", owner = b.owner, pos = p })
					end
				end
			end)
		end
		fx({ kind = "feathers", owner = b.owner, model = b.model, from = from, to = t.rootPart.Position, dirs = dirs, speed = speed, range = a.range })
	end)
end

-- Lunari: a horn jab up close; a trample through the line every few seconds.
local function moonCharge(b: Beast, t: Target)
	local cfg = BEAST.moon.charge
	local from = b.pos
	local dir = flat(t.rootPart.Position - from)
	local length = clear(from, dir, cfg.length)
	local to = from + dir * length
	local o = os.clock()
	b.busyUntil = o + cfg.dur
	b.nextCharge = o + cfg.every
	b.nextAttack = o + cfg.dur + 0.3
	b.face = dir
	act(b, "charge", { dur = cfg.dur, from = from, to = to })
	local struck: { [Model]: boolean } = {}
	local t0 = o
	b.scriptKind = "charge"
	b.script = function(clock: number, _dt: number): boolean
		local a = math.min((clock - t0) / cfg.dur, 1)
		local e = 1 - (1 - a) ^ 2
		b.pos = from:Lerp(to, e)
		local y = floorY(b.pos, b.pos.Y + 2)
		if y then b.pos = Vector3.new(b.pos.X, y, b.pos.Z) end
		for _, en in ipairs(inRadius(b.owner.Character :: Model, b.pos, cfg.width)) do
			if not struck[en.character] then
				struck[en.character] = true
				if hit(b.owner, en, beastDamage(b, cfg.damage), "LUNARI") then
					launch(en, b.pos - dir * 2, 18, 14, cfg.stun)
				end
			end
		end
		return a >= 1
	end
end

local function moonAttack(b: Beast, t: Target)
	local cfg = BEAST.moon
	local o = os.clock()
	if o >= b.nextCharge and flatDist(t.rootPart.Position, b.pos) > 4 then
		moonCharge(b, t)
		return
	end
	local a = cfg.attack
	b.busyUntil = o + a.dur
	b.nextAttack = o + a.every
	act(b, "jab", { dur = a.dur })
	later(b, a.hit, function()
		for _, e in ipairs(inCone(b, a.range, a.arc)) do
			if hit(b.owner, e, beastDamage(b, a.damage), "LUNARI") then launch(e, b.pos, 16, 10, 0.3) end
		end
	end)
end

local ATTACK: { [string]: (Beast, Target) -> () } = { rock = rockAttack, sky = skyAttack, moon = moonAttack }

-- ── The mind ────────────────────────────────────────────────────────────────
local function think(b: Beast, dt: number)
	local o = os.clock()
	local owner = b.owner
	local ownerRoot = rootOf(owner.Character)
	if not ownerRoot then return end
	local cfg = BEAST[b.kind]

	-- Lunari's healing pulses (whatever it's doing)
	if b.kind == "moon" and o >= b.nextPulse then
		local p = cfg.pulse
		b.nextPulse = o + p.every
		local healed = healAround(b.pos, p.radius * stat(owner, "size"), p.heal)
		fx({ kind = "moonPulse", owner = owner, model = b.model, pos = b.pos, radius = p.radius * stat(owner, "size"), healed = healed })
	end

	-- a scripted move has the body
	if b.script then
		local done = b.script(o, dt)
		if done then
			b.script = nil
			b.scriptKind = nil
		end
		return
	end
	-- (a flier climbs back to its height after a move that brought it down)
	b.fly += (cfg.fly - b.fly) * math.min(1, dt * 4)

	-- lost: back to your side
	if flatDist(b.pos, ownerRoot.Position) > CATCH_UP or math.abs(b.pos.Y - ownerRoot.Position.Y) > 30 then
		blinkTo(b, slotFor(b, ownerRoot))
		b.target = nil
		return
	end

	if o >= b.nextThink then
		b.nextThink = o + THINK
		b.target = pickTarget(b, ownerRoot)
	end
	local t = b.target
	if t and not alive(t) then t = nil b.target = nil end

	-- mid-swing: it stands, turning into the blow
	if o < b.busyUntil then
		b.vel *= math.max(0, 1 - dt * 10)
		if t then turnToward(b, t.rootPart.Position - b.pos, dt * 0.6) end
		return
	end

	if t then
		local tp = t.rootPart.Position
		local d = Vector3.new(tp.X - b.pos.X, 0, tp.Z - b.pos.Z)
		local dist = d.Magnitude
		local body = H.lineReach(t, 0) * 0.5
		local goal: Vector3
		if b.kind == "sky" then
			-- hangs back at range, drifting round the target
			local around = CFrame.Angles(0, math.sin(o * 0.7) * 0.6, 0) * (if dist > 0.1 then -d.Unit else -b.face)
			goal = tp + around * cfg.reach
		else
			goal = if dist > cfg.reach + body then tp - d.Unit * (cfg.reach * 0.75 + body) else b.pos
		end
		steer(b, goal, dt)
		turnToward(b, d, dt)
		local inReach = if b.kind == "sky" then dist <= cfg.attack.range * 0.8 else dist <= cfg.reach + body + 1
		local facing = dist < 0.1 or b.face:Dot(d.Unit) > 0.75
		if inReach and facing and o >= b.nextAttack then
			ATTACK[b.kind](b, t)
		end
		-- (the stag tramples whatever's in range, even from afar)
		if b.kind == "moon" and o >= b.nextCharge and o >= b.nextAttack and dist > 7 and dist < cfg.charge.length then
			moonCharge(b, t)
		end
	else
		local slot = slotFor(b, ownerRoot)
		local far = flatDist(slot, b.pos)
		steer(b, slot, dt, if far > 14 then 1.35 else 1)
		local mv = Vector3.new(b.vel.X, 0, b.vel.Z)
		if mv.Magnitude > 2 then
			turnToward(b, mv, dt)
		else
			turnToward(b, flat(ownerRoot.CFrame.LookVector), dt * 0.5)
		end
	end
end

local function step(dt: number)
	refreshFloorParams()
	local o = os.clock()
	for player, st in pairs(states) do
		local char = player.Character
		for _, b in pairs(st.beasts) do
			if b.gone then continue end
			if not char or not char.Parent or not b.model.Parent then dismiss(b, "quiet") continue end
			if b.kind ~= "fused" and o >= b.expires and not b.script then dismiss(b, "expire") continue end
			if b.hum.Health <= 0 then dismiss(b, "break") continue end
			if RunScope.Paused(char) then continue end
			local ok, err = pcall(think, b, dt)
			if not ok then warn("[SummonerServer]", b.kind, err) end
			place(b)
		end
	end
end

-- ── Arrivals ────────────────────────────────────────────────────────────────
-- A beast arrives (E / F / Q with none of that kind out). `at` is where it
-- lands (the Rockborn's meteor, the Skyfeather's dive, the Lunari's gate).
local function summon(player: Player, char: Model, kind: string, at: Vector3, face: Vector3, life: number, quiet: boolean?): Beast
	local st = getState(player)
	local old = st.beasts[kind]
	if old then dismiss(old, "quiet") end
	at = floorAt(at)
	local b = newBody(player, kind, at, face, life)
	st.beasts[kind] = b
	player:SetAttribute("SUM_" .. kind, b.model:GetAttribute("Expires"))
	player:SetAttribute("SUMLIFE_" .. kind, life)
	local cfg = BEAST[kind]
	local land = cfg.landing
	b.busyUntil = os.clock() + land.fall + 0.45
	b.nextAttack = os.clock() + land.fall + 0.6
	fx({ kind = "summon", owner = player, model = b.model, beast = kind, pos = at, face = face, life = life,
		fall = land.fall, quiet = quiet == true })
	if quiet then return b end
	later(b, land.fall, function()
		if kind == "moon" then
			local healed = healAround(at, land.radius * stat(player, "size"), land.heal)
			fx({ kind = "moonGate", owner = player, model = b.model, pos = at, radius = land.radius * stat(player, "size"), healed = healed })
			return
		end
		local radius = land.radius * stat(player, "size")
		for _, e in ipairs(inRadius(char, at, radius)) do
			if hit(player, e, beastDamage(b, land.damage), if kind == "rock" then "ROCKBORN" else "SKYFEATHER") then
				launch(e, at, 18, if kind == "rock" then 30 else 16, 0.5)
			end
		end
	end)
	return b
end

-- ── Signatures (recast) ─────────────────────────────────────────────────────
-- Rockborn, Ground Slam: a crouch, a leap to the aim, a slam that splits the
-- floor in a ring, and fissures that erupt outward a beat later.
local function rockSlam(b: Beast, aim: Vector3, config: any)
	local s = BEAST.rock.sig
	local area = config.areaMultiplier or 1
	local from = b.pos
	local d = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	if d.Magnitude > s.range then aim = from + d.Unit * s.range end
	aim = floorAt(aim)
	local dir = if d.Magnitude > 0.5 then d.Unit else b.face
	b.face = dir
	local t0 = os.clock()
	b.busyUntil = t0 + s.clip
	local landed = false
	local fissured = false
	fx({ kind = "sig", owner = b.owner, model = b.model, beast = "rock", from = from, to = aim, lead = 0, clip = s.clip,
		radius = s.radius * area, fissures = s.fissures, fissureLen = s.fissureLen * area })
	b.scriptKind = "sig"
	b.script = function(clock: number, _dt: number): boolean
		local t = clock - t0
		if t >= s.leapFrom and t <= s.leapTo then
			local u = (t - s.leapFrom) / (s.leapTo - s.leapFrom)
			u = u * u * (3 - 2 * u)
			local p = from:Lerp(aim, u)
			b.pos = Vector3.new(p.X, from.Y + (aim.Y - from.Y) * u, p.Z)
		elseif t > s.leapTo then
			b.pos = aim
		end
		if not landed and t >= s.hit then
			landed = true
			local radius = s.radius * area
			for _, e in ipairs(inRadius(b.owner.Character :: Model, aim, radius)) do
				if hit(b.owner, e, config.damage, "GROUND SLAM") then
					launch(e, aim, 10, 46, 1.1)
				end
			end
		end
		if not fissured and t >= s.fissureAt then
			fissured = true
			local len = s.fissureLen * area
			for k = 0, s.fissures - 1 do
				local fdir = (CFrame.Angles(0, k * math.pi * 2 / s.fissures + math.pi / s.fissures, 0) * CFrame.lookAt(Vector3.zero, dir)).LookVector
				for _, e in ipairs(H.getPotentialTargets(b.owner.Character :: Model)) do
					local rel = Vector3.new(e.rootPart.Position.X - aim.X, 0, e.rootPart.Position.Z - aim.Z)
					local along = rel:Dot(fdir)
					local side = (rel - fdir * along).Magnitude
					if along > s.radius * area * 0.6 and along < len + s.radius * area * 0.6 and side < 3.5 + H.lineReach(e, 0) * 0.5 then
						if hit(b.owner, e, config.damage * 0.5, "GROUND SLAM") then launch(e, aim, 6, 30, 0.7) end
					end
				end
			end
		end
		return t >= s.clip
	end
end

-- Skyfeather, Wind Circle: a dash to the aim, then it rises and circles,
-- the cyclone dragging every enemy in and cutting them; a burst as it lands.
local function skyCircle(b: Beast, aim: Vector3, config: any)
	local s = BEAST.sky.sig
	local area = config.areaMultiplier or 1
	local owner = b.owner
	local ownerRoot = rootOf(owner.Character)
	local from = b.pos
	local center = ownerRoot and ownerRoot.Position or from
	local d = Vector3.new(aim.X - center.X, 0, aim.Z - center.Z)
	if d.Magnitude > s.range then aim = center + d.Unit * s.range end
	aim = floorAt(aim)
	local t0 = os.clock()
	local dur = s.dash + s.clip
	b.busyUntil = t0 + dur
	local radius = s.radius * area
	local face = flat(aim - from)
	fx({ kind = "sig", owner = owner, model = b.model, beast = "sky", from = from, to = aim, lead = s.dash, clip = s.clip,
		radius = radius, travel = s.travel })
	local nextTick = s.dash + s.from
	local burst = false
	local flyFrom = b.fly
	b.scriptKind = "sig"
	b.script = function(clock: number, _dt: number): boolean
		local t = clock - t0
		if t < s.dash then
			local u = t / s.dash
			b.pos = from:Lerp(aim, u * (2 - u))
			b.fly = flyFrom * (1 - u)
			b.face = face
		else
			b.pos = aim
			b.fly = 0
			local ct = t - s.dash
			if ct >= s.from and ct <= s.to and t >= nextTick then
				nextTick += s.tick
				for _, e in ipairs(inRadius(owner.Character :: Model, aim, radius * 1.25)) do
					pull(e, aim, s.pull)
					hold(e, s.tick + 0.1)
					if flatDist(e.rootPart.Position, aim) <= radius then
						hit(owner, e, beastDamage(b, s.tickDamage), "WIND CIRCLE")
					end
				end
			end
			if not burst and ct >= s.hit then
				burst = true
				fx({ kind = "skyBurst", owner = owner, model = b.model, pos = aim, radius = radius })
				for _, e in ipairs(inRadius(owner.Character :: Model, aim, radius)) do
					if hit(owner, e, config.damage, "WIND CIRCLE") then
						launch(e, aim, 28, 34, 0.8)
					end
				end
			end
			if ct >= s.clip then return true end
		end
		return false
	end
end

-- Lunari, Radiant Bloom: a gallop to the aim, a rear, and a stomp that
-- blooms a flower of moonlight: the party healed, enemies stunned and burnt.
local function moonBloom(b: Beast, aim: Vector3, config: any)
	local s = BEAST.moon.sig
	local area = config.areaMultiplier or 1
	local owner = b.owner
	local from = b.pos
	local d = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	if d.Magnitude > s.range then aim = from + d.Unit * s.range end
	aim = floorAt(aim)
	d = Vector3.new(aim.X - from.X, 0, aim.Z - from.Z)
	-- (a short way: it blooms where it stands)
	local gallop = if d.Magnitude > 4 then math.min(1.0, d.Magnitude / (BEAST.moon.speed * 1.7)) else 0
	local face = if d.Magnitude > 0.5 then d.Unit else b.face
	local t0 = os.clock()
	b.busyUntil = t0 + gallop + s.clip
	local radius = s.radius * area
	fx({ kind = "sig", owner = owner, model = b.model, beast = "moon", from = from, to = aim, lead = gallop, clip = s.clip, radius = radius })
	local bloomed = false
	b.scriptKind = "sig"
	b.script = function(clock: number, _dt: number): boolean
		local t = clock - t0
		b.face = face
		if t < gallop then
			local u = t / gallop
			b.pos = from:Lerp(aim, u * (2 - u))
			local y = floorY(b.pos, b.pos.Y + 2)
			if y then b.pos = Vector3.new(b.pos.X, y, b.pos.Z) end
			return false
		end
		b.pos = aim
		if not bloomed and t - gallop >= s.hit then
			bloomed = true
			local healed = healAround(aim, radius * 1.3, s.heal)
			fx({ kind = "moonBloom", owner = owner, model = b.model, pos = aim, radius = radius, healed = healed })
			for _, e in ipairs(inRadius(owner.Character :: Model, aim, radius)) do
				if hit(owner, e, config.damage, "RADIANT BLOOM") then
					launch(e, aim, 8, 12, s.stun)
				end
			end
		end
		return t - gallop >= s.clip
	end
end

local SIGNATURE: { [string]: (Beast, Vector3, any) -> () } = { rock = rockSlam, sky = skyCircle, moon = moonBloom }

-- The Skyrockorn's flight is its baked GLB move (drawn by every client); the
-- server follows the same path to know where its trench and tornadoes fall.
-- (Its model data lives with the client's beasts; the server only reads the
-- root's track out of it.)
local flightPath: { Vector3 }? = nil
local flightFps = 15
local function flightAt(t: number): Vector3
	if not flightPath then
		local ok, data = pcall(function()
			local models = game:GetService("StarterPlayer"):WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
				:WaitForChild("Summons"):WaitForChild("Models"):WaitForChild(SummonerData.MODEL.fused)
			return require(models :: ModuleScript) :: any
		end)
		local path = {}
		if ok and data then
			local tr = data.anim.tracks.HumanoidRootPart
			flightFps = data.anim.fps
			for f = 0, data.anim.frames - 1 do
				local o = 2 + f * 7
				table.insert(path, Vector3.new(tr[o + 4], tr[o + 5], tr[o + 6]))
			end
		else
			warn("[SummonerServer] no Skyrockorn flight path:", data)
			table.insert(path, Vector3.new(0, 4, 0))
		end
		flightPath = path
	end
	local path = flightPath :: { Vector3 }
	local f = math.clamp(t * flightFps, 0, #path - 1)
	local i = math.floor(f)
	local j = math.min(i + 1, #path - 1)
	return path[i + 1]:Lerp(path[j + 1], f - i)
end

-- Where the Skyrockorn is `t` seconds into its flight, in the world (and
-- the floor right under it).
local function flightWorld(anchor: Vector3, face: Vector3, t: number): (Vector3, Vector3)
	local cfg = BEAST.fused
	local m = flightAt(t) * cfg.scale
	local turn = CFrame.lookAt(Vector3.zero, face)
	local off = turn:VectorToWorldSpace(Vector3.new(m.X * cfg.travel, 0, m.Z * cfg.travel))
	local at = anchor + off + Vector3.new(0, m.Y, 0)
	return at, floorAt(Vector3.new(at.X, anchor.Y, at.Z))
end

-- ── R: Divine Cataclysm ─────────────────────────────────────────────────────
local function cataclysm(player: Player, char: Model, st: State, config: any)
	local root = rootOf(char)
	if not root then return end
	local s = BEAST.fused.sig
	local area = config.areaMultiplier or 1
	local o = os.clock()
	local anchor = floorAt(root.Position)
	local face = flat(root.CFrame.LookVector)
	st.ulting = true
	st.busyUntil = o + s.gather
	char:SetAttribute("InvulnerableUntil", math.max(tonumber(char:GetAttribute("InvulnerableUntil")) or 0, o + s.gather + 0.3))
	-- 1 · the beasts out fly to you and become one
	local fused: { { kind: string, left: number } } = {}
	local froms = {}
	for kind, b in pairs(st.beasts) do
		if kind ~= "fused" and not b.gone then
			table.insert(fused, { kind = kind, left = math.max(4, b.expires - o) })
			table.insert(froms, { beast = kind, model = b.model, pos = b.pos })
			local start, startFly = b.pos, b.fly
			b.script = function(clock: number, _dt: number): boolean
				local u = math.min((clock - o) / s.gather, 1)
				b.pos = start:Lerp(anchor, u * u)
				b.fly = startFly + 9 * math.sin(u * math.pi * 0.5)
				return false
			end
			b.scriptKind = "fuse"
		end
	end
	local radius = s.radius * area
	local rainR = s.radius0 * area
	fx({ kind = "ult", owner = player, pos = anchor, face = face, gather = s.gather, clip = s.clip, beasts = froms,
		radius = radius, rainRadius = rainR })
	task.delay(s.gather, function()
		if not char.Parent then st.ulting = false return end
		for _, b in pairs(st.beasts) do
			if b.kind ~= "fused" then dismiss(b, "fuse") end
		end
		local beast = newBody(player, "fused", anchor, face, s.clip + 1)
		beast.script = function(): boolean return false end -- (it holds its spot: the flight is its own)
		st.beasts.fused = beast
		fx({ kind = "fusedRise", owner = player, model = beast.model, pos = anchor, face = face, clip = s.clip,
			travel = BEAST.fused.travel, radius = radius })
		local t0 = os.clock()
		-- 2 · starfire rains while it circles
		task.spawn(function()
			task.wait(s.rainFrom)
			local ends = t0 + s.rainTo
			while os.clock() < ends and char.Parent and not beast.gone do
				local list = inRadius(char, anchor, rainR)
				local at: Vector3
				if #list > 0 and math.random() < 0.7 then
					local t = list[math.random(1, #list)]
					at = t.rootPart.Position + Vector3.new(math.random() * 4 - 2, 0, math.random() * 4 - 2)
				else
					local a, r = math.random() * math.pi * 2, math.sqrt(math.random()) * rainR
					at = anchor + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
				end
				at = floorAt(at)
				fx({ kind = "ultRain", owner = player, pos = at })
				task.delay(0.16, function()
					if not char.Parent then return end
					for _, e in ipairs(inRadius(char, at, s.rainSplash * area)) do
						hit(player, e, config.damage * s.rainDamage / s.damage, "DIVINE CATACLYSM")
					end
				end)
				task.wait(s.rainEvery)
			end
		end)
		-- 3 · judgement rays from on high
		task.spawn(function()
			task.wait(s.raysFrom)
			local ends = t0 + s.raysTo
			while os.clock() < ends and char.Parent and not beast.gone do
				local list = inRadius(char, anchor, rainR)
				table.sort(list, function(a, b2)
					return flatDist(a.rootPart.Position, anchor) < flatDist(b2.rootPart.Position, anchor)
				end)
				local models = {}
				for k = 1, math.min(s.rays, #list) do
					local t = list[k]
					table.insert(models, t.character)
					hit(player, t, config.damage * s.rayDamage / s.damage, "DIVINE CATACLYSM")
					hold(t, s.rayEvery + 0.1)
				end
				if #models > 0 then fx({ kind = "ultRays", owner = player, model = beast.model, targets = models }) end
				task.wait(s.rayEvery)
			end
		end)
		-- 2b · the trench it tears along the floor beneath its flight, and the
		-- tornadoes it drops in its wake
		task.spawn(function()
			task.wait(s.trenchFrom)
			local _, prev = flightWorld(anchor, face, s.trenchFrom)
			local struck: { [Model]: number } = {}
			local nextTornado = os.clock() + 0.2
			local count = 0
			while os.clock() - t0 < s.trenchTo and char.Parent and not beast.gone do
				task.wait(s.trenchEvery)
				local t = os.clock() - t0
				local _, g = flightWorld(anchor, face, t)
				local width = s.trenchWidth * area
				fx({ kind = "ultTrench", owner = player, a = prev, b = g, width = width })
				-- everything on the line is thrown up out of it
				local seg = Vector3.new(g.X - prev.X, 0, g.Z - prev.Z)
				local len = seg.Magnitude
				local dir = if len > 0.05 then seg / len else face
				for _, e in ipairs(H.getPotentialTargets(char)) do
					local rel = Vector3.new(e.rootPart.Position.X - prev.X, 0, e.rootPart.Position.Z - prev.Z)
					local along = math.clamp(rel:Dot(dir), 0, len)
					local side = (rel - dir * along).Magnitude
					local o = os.clock()
					if side <= width * 0.5 + H.lineReach(e, 0) * 0.5 and math.abs(e.rootPart.Position.Y - g.Y) < 10
						and o >= (struck[e.character] or 0) then
						struck[e.character] = o + 0.45
						if hit(player, e, config.damage * s.trenchDamage / s.damage, "DIVINE CATACLYSM") then
							launch(e, g, 12, 34, 0.6)
						end
					end
				end
				if os.clock() >= nextTornado then
					nextTornado = os.clock() + s.tornadoEvery
					count += 1
					-- (each wanders off away from the middle, curling round it)
					local out = flat(Vector3.new(g.X - anchor.X, 0, g.Z - anchor.Z))
					local drift = flat(out + Vector3.new(-out.Z, 0, out.X) * (if count % 2 == 0 then 0.8 else -0.8))
					local radius = s.tornadoRadius * area
					local start = g
					fx({ kind = "ultTornado", owner = player, pos = start, dir = drift, speed = s.tornadoDrift,
						life = s.tornadoLife, radius = radius })
					task.spawn(function()
						local born = os.clock()
						local nextTick = born
						while os.clock() - born < s.tornadoLife and char.Parent do
							local age = os.clock() - born
							local c = floorAt(start + drift * s.tornadoDrift * age)
							for _, e in ipairs(inRadius(char, c, radius * 1.3)) do
								pull(e, c, s.tornadoPull)
								hold(e, 0.3)
							end
							if os.clock() >= nextTick then
								nextTick += s.tornadoTick
								for _, e in ipairs(inRadius(char, c, radius)) do
									hit(player, e, config.damage * s.tornadoDamage / s.damage, "DIVINE CATACLYSM")
								end
							end
							task.wait(0.1)
						end
					end)
				end
				prev = g
			end
		end)
		-- 4 · the crash
		task.delay(s.hit, function()
			if not char.Parent or beast.gone then return end
			fx({ kind = "ultImpact", owner = player, model = beast.model, pos = anchor, radius = radius, crater = s.crater * area })
			for _, e in ipairs(inRadius(char, anchor, radius)) do
				if hit(player, e, config.damage, "DIVINE CATACLYSM") then launch(e, anchor, 26, 50, 1.2) end
			end
		end)
		-- 5 · it comes apart: the beasts it was made of step back out
		task.delay(s.clip, function()
			st.ulting = false
			if beast.gone then return end
			dismiss(beast, "unfuse")
			if not char.Parent then return end
			local r2 = rootOf(char)
			for k, f in ipairs(fused) do
				local ang = (k - 1) / math.max(1, #fused) * math.pi * 2
				local at = anchor + Vector3.new(math.cos(ang) * 6, 0, math.sin(ang) * 6)
				summon(player, char, f.kind, at, if r2 then flat(r2.CFrame.LookVector) else face, f.left, true)
			end
		end)
	end)
end

-- ── M1: Bond Bolt ───────────────────────────────────────────────────────────
function SummonerServer.OnBasic(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local o = os.clock()
	if o < st.busyUntil then return end
	local speed = math.max(stat(player, "basicAttackSpeed"), 0.1)
	if o - st.lastBolt < BOLT.interval / speed - 0.06 then return end
	st.lastBolt = o
	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	local origin = root.Position + dir * 1.6 + Vector3.new(0, 0.9, 0)
	local count = 1 + math.max(0, math.floor(stat(player, "projectileCount")))
	local damage = BOLT.damage * stat(player, "damage")
	local width = BOLT.width * stat(player, "size")
	local boltSpeed = BOLT.speed * stat(player, "projectileSpeed")
	local dirs = {}
	for k = 1, count do
		local d = flat((CFrame.Angles(0, (k - (count + 1) / 2) * BOLT.fan, 0) * CFrame.lookAt(Vector3.zero, dir)).LookVector)
		table.insert(dirs, d)
		flyBolt(player, origin, d, boltSpeed, BOLT.range, width, function(t, p)
			if hit(player, t, damage, "BOND BOLT") then
				pcall(H.ricochet, player, char, t, damage, "BOND BOLT")
				-- (every beast turns on it)
				st.focus = t.character
				st.focusUntil = os.clock() + BOLT.focus
				if H.fxAllowed(player, "sumFocus", 6) then
					fx({ kind = "focus", owner = player, target = t.character, life = BOLT.focus })
				end
			end
			if H.fxAllowed(player, "sumBolt", 14) then fx({ kind = "boltEnd", owner = player, pos = p }) end
		end)
	end
	fx({ kind = "bolt", owner = player, from = origin, dirs = dirs, speed = boltSpeed, range = BOLT.range })
end

-- ── Public ──────────────────────────────────────────────────────────────────
function SummonerServer.CanUseSkill(player: Player, _skillIndex: number): boolean
	local st = getState(player)
	return os.clock() >= st.busyUntil
end

-- E / F / Q with that beast already out: its signature move (its own short
-- recharge, not the skill's cooldown). True when the press was used here.
function SummonerServer.TryRecast(player: Player, char: Model, skillIndex: number, payload: any): boolean
	local kind = SummonerData.SKILL_KIND[skillIndex]
	if not kind then return false end
	local st = getState(player)
	local b = st.beasts[kind]
	if not b or b.gone then return false end
	if st.ulting then return true end
	local o = os.clock()
	if b.script ~= nil and b.scriptKind == "sig" then return true end
	if o < (st.sigReady[kind] or 0) then return true end
	local root = rootOf(char)
	if not root then return true end
	local config = table.clone(require(Shared:WaitForChild("SkillData")).GetSkill("summoner", skillIndex) or {})
	config.damage = (config.sigDamage or config.damage or 60) * stat(player, "damage")
	config.areaMultiplier = stat(player, "size")
	local aim = root.Position + flat(root.CFrame.LookVector) * 12
	if typeof(payload) == "table" and typeof(payload.targetPosition) == "Vector3" then
		aim = payload.targetPosition
	end
	local cd = BEAST[kind].sig.cooldown * stat(player, "abilityCooldown")
	st.sigReady[kind] = o + cd
	-- (an attack in progress is dropped)
	b.script = nil
	b.busyUntil = 0
	SIGNATURE[kind](b, aim, config)
	fx({ kind = "sigReady", owner = player, beast = kind, at = now() + cd, cooldown = cd })
	return true
end

function SummonerServer.OnSkill(player: Player, char: Model, skillIndex: number, origin: Vector3, dir: Vector3, config: any, targetPosition: Vector3?)
	local st = getState(player)
	local root = rootOf(char)
	if not root then return end
	dir = flat(dir)
	if skillIndex == 4 then
		cataclysm(player, char, st, config)
		return
	end
	local kind = SummonerData.SKILL_KIND[skillIndex]
	local range = config.range or 30
	local aim = origin + dir * math.min(range, 14)
	if typeof(targetPosition) == "Vector3" then
		local d = Vector3.new(targetPosition.X - origin.X, 0, targetPosition.Z - origin.Z)
		aim = origin + (if d.Magnitude > range then d.Unit * range else d)
	end
	-- (never into a wall)
	local d = Vector3.new(aim.X - origin.X, 0, aim.Z - origin.Z)
	if d.Magnitude > 0.5 then aim = origin + d.Unit * math.min(d.Magnitude, clear(origin - Vector3.new(0, 2, 0), d.Unit, d.Magnitude)) end
	local life = config.duration or 16
	summon(player, char, kind, aim, dir, life)
	-- (the signature's own recharge starts fresh with the beast)
	st.sigReady[kind] = os.clock() + 1.2
	fx({ kind = "sigReady", owner = player, beast = kind, at = now() + 1.2, cooldown = 1.2 })
end

-- Seconds the ult's opening (the beasts gathering and fusing) freezes mobs.
SummonerServer.ULT_WINDUP = BEAST.fused.sig.gather

function SummonerServer.Reset(player: Player)
	dismissAll(player, "quiet")
	local st = getState(player)
	st.busyUntil, st.lastBolt = 0, 0
	st.focus = nil
	table.clear(st.sigReady)
end

function SummonerServer.Init(helpers: any)
	H = helpers
	folder = Workspace:FindFirstChild("Summons") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Summons"
		folder.Parent = Workspace
	end
	Network.GetRemoteEvent("SummonerFX")
	RunService.Heartbeat:Connect(step)
	local function watch(p: Player)
		p.CharacterAdded:Connect(function() SummonerServer.Reset(p) end)
		p.CharacterRemoving:Connect(function() SummonerServer.Reset(p) end)
		p:GetAttributeChangedSignal("SelectedClass"):Connect(function() SummonerServer.Reset(p) end)
		p:GetAttributeChangedSignal("InLobby"):Connect(function()
			if p:GetAttribute("InLobby") ~= false then SummonerServer.Reset(p) end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		dismissAll(p, "quiet")
		states[p] = nil
	end)
end

return SummonerServer
