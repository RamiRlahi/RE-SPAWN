--!strict
--[[
	DragonBoss.luau
	Ignarath, the Cinder Wyrm: the boss of every run's first level (and a
	chance at later ones). A great red dragon crouched at the far end of the
	lava arena (Hazards.BuildBossArena), prowling along its perch.

	  Fire Breath      a telegraphed cone of flame (it sweeps once enraged)
	  Fireball Volley  lobbed fireballs at everyone; each leaves burning ground
	  Wing Buffet      rears up and blasts everyone away with its wings
	  Claw Swipe       rakes a foreleg across the ground in front of it
	  Slam             rears onto its hind legs and brings both forelimbs down
	  Inferno Beam     at 75% / 45% / 20% health it charges a beam of fire at
	                   whoever is nearest the Aegis, a huge metal shield standing
	                   on a plinth in the arena. They must run and grab it before
	                   the beam fires, then press the arrow keys shown
	                   (DragonBeam → their minigame). Finish in time and the
	                   shield throws the beam back: the dragon takes a big hit
	                   and crashes, stunned. Too slow to the shield, or to the
	                   keys, and the beam burns straight through.
	  Enrage           below half health: a roar, a burning body, faster moves.

	The model is built from parts (DragonBuilder). It moves by physics
	(AlignPosition / AlignOrientation on its server-owned body, so every client
	sees it move smoothly); the clients animate its wings, neck, jaw, legs and
	tail from the "DragonState" attribute and draw the fire (DragonBossFX). Skills hit it
	anywhere on its body: SkillManager targets its HitProxy, moved to the body
	point nearest the caster ("HitRadius").
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local DifficultyManager = require(script.Parent:WaitForChild("DifficultyManager"))
local DragonBuilder = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DragonBuilder"))

local DragonBoss = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local NAME = "★ Ignarath, the Cinder Wyrm"
local SCALE = 1.4             -- of the built dragon: about 50 studs nose to tail-tip
local HEALTH_MULT = 8         -- × the base boss health (400): 3200 at Threat I
local DAMAGE_MULT = 1.3       -- × the base boss damage (25)
local BASE_DAMAGE = 25
local XP_REWARD = 400
local HOVER = 0               -- its claws above the floor (it crouches on the ground)
local PERCH_INSET = 24        -- how far in from the arena's wall it perches
local HIT_RADIUS = 14         -- skills connect anywhere within this of its centre
local GAP, GAP_ENRAGED = 1.2, 0.6

local BEAM_AT = { 0.75, 0.45, 0.2 } -- health fractions that call the Inferno Beam
local BEAM_KEYS = { 6, 8, 10 }      -- arrows to press, per beam
local BEAM_GRAB_MIN, BEAM_GRAB_MAX = 3, 6 -- the charge: time to run and grab the shield
local BEAM_BRACE = 1.0              -- once it's in hand, this long before the beam hits
local BEAM_TIME_BASE = 1.8          -- + per key: the time to press them all once it hits
local BEAM_TIME_PER_KEY = 0.45
local BEAM_REFLECT = 0.1            -- of its max health, when the shield throws the beam back
local BEAM_FAIL = 0.6               -- of the target's max health, when it breaks through
local STUN_TIME = 3.5

local TELEGRAPH = Color3.fromRGB(255, 50, 40)
local FLAME = Color3.fromRGB(255, 130, 40)
local FLAME_DEEP = Color3.fromRGB(200, 40, 10)
local GOLD = Color3.fromRGB(255, 215, 120)
local STEEL = Color3.fromRGB(96, 100, 110)
local IRON = Color3.fromRGB(44, 44, 50)
local FIRE_TEXTURE = "rbxassetid://11534281007"

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lying flat

type Deps = {
	canAct: (Model) -> boolean,              -- not frozen / paused / chilled
	hurt: (Model, number, Vector3?) -> (),   -- damage a player (i-frames, parries, curses)
	reward: (Model, Vector3, number) -> (),  -- XP / gold / soul drops for the kill
}
local deps: Deps
local fxRemote: RemoteEvent
local beamRemote: RemoteEvent

type Arena = { minX: number, maxX: number, minZ: number, maxZ: number, floorY: number, center: Vector3 }
type Victim = { char: Model, root: BasePart, hum: Humanoid, player: Player }
type Beam = {
	token: number,
	target: Victim,
	keys: { string },
	progress: number,
	lastStep: number,
	opensAt: number,
	deadline: number,
	onStep: (() -> ())?,
}
type Dragon = {
	model: Model,
	body: BasePart,
	root: BasePart,
	head: BasePart,
	hum: Humanoid,
	mouth: Attachment,
	arena: Arena,
	groundOffset: number, -- body centre above its claws
	damage: number,
	ap: AlignPosition,
	ao: AlignOrientation,
	pos: Vector3,         -- where the body is flying to (before the hover bob)
	look: Vector3,        -- flat facing
	track: BasePart?,     -- keep facing this
	pitch: number,
	roll: number,
	bob: boolean,
	enraged: boolean,
	enrageQueued: boolean,
	beamsQueued: number,
	beamsDone: number,
	dead: boolean,
	onDied: () -> (),
	fx: Folder,
	aegis: any, -- the shield on its plinth (Aegis)
	home: { pos: Vector3, look: Vector3 }, -- its perch
}

local beams: { [number]: Beam } = {}
local nextToken = 0

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function flatDist(a: Vector3, b: Vector3): number
	return flat(a - b).Magnitude
end

local function rotY(dir: Vector3, angle: number): Vector3
	return CFrame.Angles(0, angle, 0):VectorToWorldSpace(dir)
end

-- The body's CFrame facing `f` (the model's nose is its body's +Z).
local function bodyCF(p: Vector3, f: Vector3): CFrame
	return CFrame.lookAt(p, p - f)
end

-- Distance from p to the segment a–b, flat.
local function segDist(p: Vector3, a: Vector3, b: Vector3): number
	local ab = flat(b - a)
	local ap = flat(p - a)
	local len2 = ab:Dot(ab)
	local t = if len2 > 0 then math.clamp(ap:Dot(ab) / len2, 0, 1) else 0
	return (ap - ab * t).Magnitude
end

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 1
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

-- A flat triangle a-b-c from two wedges (for the breath's cone telegraph).
local function triangle(parent: Instance, a: Vector3, b: Vector3, c: Vector3, transparency: number): { BasePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local out = {}
	for i, spec in ipairs({ { ab, a + b, 1 }, { ac, a + c, -1 } }) do
		local w = Instance.new("WedgePart")
		w.Anchored = true
		w.CanCollide = false
		w.CanQuery = false
		w.CanTouch = false
		w.CastShadow = false
		w.Material = Enum.Material.Neon
		w.Color = TELEGRAPH
		w.Transparency = transparency
		local edge = spec[1] :: Vector3
		local s = spec[3] :: number
		w.Size = Vector3.new(0.12, height, math.abs(edge:Dot(back)))
		w.CFrame = CFrame.fromMatrix((spec[2] :: Vector3) / 2, right * s, up, back * s)
		w.Parent = parent
		out[i] = w
	end
	return out
end

local function setState(d: Dragon, s: string)
	d.model:SetAttribute("DragonState", s)
end

local function sound(d: Dragon, name: string)
	local s = d.model:FindFirstChild(name, true)
	if s and s:IsA("Sound") then s:Play() end
end

local function hoverY(d: Dragon): number
	return d.arena.floorY + d.groundOffset + HOVER
end

local function clampToArena(d: Dragon, p: Vector3, margin: number): Vector3
	local a = d.arena
	return Vector3.new(math.clamp(p.X, a.minX + margin, a.maxX - margin), p.Y, math.clamp(p.Z, a.minZ + margin, a.maxZ - margin))
end

local function setAlign(d: Dragon, responsiveness: number?, maxVelocity: number?)
	d.ap.Responsiveness = responsiveness or 14
	d.ap.MaxVelocity = maxVelocity or 45
end

local function alive(d: Dragon): boolean
	return not d.dead and d.model.Parent ~= nil and d.hum.Health > 0
end

-- Wait `t` seconds of *active* time (paused while it's frozen / chilled / the
-- game is paused for tomes).
local function hold(d: Dragon, t: number): boolean
	local left = t
	while left > 0 do
		local dt = task.wait(0.05)
		if not alive(d) then return false end
		if deps.canAct(d.model) then left -= dt end
	end
	return true
end

-- Players fighting it: alive, in the run, inside the arena.
local function victims(d: Dragon): { Victim }
	local a = d.arena
	local out = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char and plr:GetAttribute("InLobby") == false then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local p = root.Position
				if p.X >= a.minX - 2 and p.X <= a.maxX + 2 and p.Z >= a.minZ - 2 and p.Z <= a.maxZ + 2
					and math.abs(p.Y - a.floorY) < 18 then
					table.insert(out, { char = char, root = root, hum = hum, player = plr })
				end
			end
		end
	end
	return out
end

local function nearest(d: Dragon, vs: { Victim }): Victim?
	local best, bestD = nil, math.huge
	for _, v in ipairs(vs) do
		local dist = flatDist(v.root.Position, d.body.Position)
		if dist < bestD then best, bestD = v, dist end
	end
	return best
end

local function dmg(d: Dragon, mult: number): number
	return BASE_DAMAGE * d.damage * mult
end

-- Knockback runs on the victim's own game (it owns its character's physics).
local function knock(v: Victim, from: Vector3, power: number, lift: number)
	fxRemote:FireClient(v.player, { kind = "knock", from = from, power = power, lift = lift })
end

-- Damage (through MobManager: i-frames, parries, curses), knocking the
-- victim back only if it landed.
local function hit(d: Dragon, v: Victim, mult: number, from: Vector3?, power: number, lift: number)
	local before = v.hum.Health
	deps.hurt(v.char, dmg(d, mult), from)
	if from and power > 0 and v.hum.Health < before then
		knock(v, from, power, lift)
	end
end

-- ── Telegraphs ──────────────────────────────────────────────────────────────
-- A telegraphed area: a glowing orange rim round a dark centre, a subtle
-- fill growing toward the edge and embers rising off the ground. (Kept
-- restrained on purpose: the blast that follows is the bright moment.)
local function circle(d: Dragon, center: Vector3, radius: number, t: number)
	local pos = Vector3.new(center.X, d.arena.floorY + 0.12, center.Z)
	local rim = part(d.fx, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = CFrame.new(pos) * FLAT, Color = Color3.fromRGB(255, 110, 40), Transparency = 0.45 })
	local inner = part(d.fx, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, radius * 2 - 0.9, radius * 2 - 0.9),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.01, 0)) * FLAT, Color = Color3.fromRGB(28, 8, 6), Material = Enum.Material.SmoothPlastic,
		Transparency = 0.35 })
	local fill = part(d.fx, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.4, 0.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.02, 0)) * FLAT, Color = Color3.fromRGB(230, 90, 30), Transparency = 0.7 })
	TweenService:Create(fill, TweenInfo.new(t, Enum.EasingStyle.Linear),
		{ Size = Vector3.new(0.14, radius * 2 - 0.9, radius * 2 - 0.9), Transparency = 0.5 }):Play()
	-- the rim brightens as it's about to go off
	TweenService:Create(rim, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 0.05 }):Play()
	emitter(rim, { Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(255, 170, 80), Color3.fromRGB(255, 70, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(2, 5), EmissionDirection = Enum.NormalId.Right,
		Shape = Enum.ParticleEmitterShape.Cylinder, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Rate = math.clamp(radius * 3, 10, 50) })
	Debris:AddItem(rim, t)
	Debris:AddItem(inner, t)
	Debris:AddItem(fill, t)
end

local function line(d: Dragon, from: Vector3, dir: Vector3, length: number, width: number, t: number)
	local y = d.arena.floorY + 0.12
	local mid = from + dir * (length / 2)
	local cf = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(mid.X + dir.X, y, mid.Z + dir.Z))
	local bar = part(d.fx, { Size = Vector3.new(width, 0.12, length), CFrame = cf, Color = TELEGRAPH, Transparency = 0.7 })
	-- The fill runs out from the dragon to the far end.
	local fill = part(d.fx, { Size = Vector3.new(width, 0.14, 0.2),
		CFrame = CFrame.lookAt(Vector3.new(from.X, y + 0.02, from.Z), Vector3.new(from.X + dir.X, y + 0.02, from.Z + dir.Z)) * CFrame.new(0, 0, -0.1),
		Color = TELEGRAPH, Transparency = 0.45 })
	TweenService:Create(fill, TweenInfo.new(t, Enum.EasingStyle.Linear), {
		Size = Vector3.new(width, 0.14, length),
		CFrame = CFrame.lookAt(Vector3.new(mid.X, y + 0.02, mid.Z), Vector3.new(mid.X + dir.X, y + 0.02, mid.Z + dir.Z)),
	}):Play()
	Debris:AddItem(bar, t)
	Debris:AddItem(fill, t)
end

-- A fan of triangles: the breath's cone on the floor.
local function cone(d: Dragon, apex: Vector3, dir: Vector3, range: number, half: number, t: number)
	local y = d.arena.floorY + 0.12
	local a = Vector3.new(apex.X, y, apex.Z)
	local SEGMENTS = 6
	local parts: { BasePart } = {}
	for i = 0, SEGMENTS - 1 do
		local a0 = -half + (2 * half) * i / SEGMENTS
		local a1 = -half + (2 * half) * (i + 1) / SEGMENTS
		for _, w in ipairs(triangle(d.fx, a, a + rotY(dir, a0) * range, a + rotY(dir, a1) * range, 0.75)) do
			table.insert(parts, w)
		end
	end
	for _, w in ipairs(parts) do
		TweenService:Create(w, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 0.35 }):Play()
		Debris:AddItem(w, t)
	end
end

-- Burning ground left by a fireball.
local function burnPatch(d: Dragon, at: Vector3, r: number, life: number)
	local pos = Vector3.new(at.X, d.arena.floorY + 0.1, at.Z)
	local disc = part(d.fx, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, r * 2, r * 2),
		CFrame = CFrame.new(pos) * FLAT, Color = Color3.fromRGB(150, 45, 15), Material = Enum.Material.CrackedLava, Transparency = 0.2 })
	local att = Instance.new("Attachment")
	att.Orientation = Vector3.new(0, 0, 90)
	att.Parent = disc
	emitter(att, { Texture = FIRE_TEXTURE, EmissionDirection = Enum.NormalId.Right,
		Color = ColorSequence.new(FLAME, FLAME_DEEP),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.2) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(3, 7), SpreadAngle = Vector2.new(35, 35),
		Shape = Enum.ParticleEmitterShape.Disc, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rate = 30 })
	task.spawn(function()
		local t0 = os.clock()
		local hitAt: { [Model]: number } = {}
		while os.clock() - t0 < life and disc.Parent do
			for _, v in ipairs(victims(d)) do
				local p = v.root.Position
				if flatDist(p, at) <= r and p.Y - d.arena.floorY < 7 and os.clock() - (hitAt[v.char] or 0) >= 0.5 then
					hitAt[v.char] = os.clock()
					hit(d, v, 0.16, nil, 0, 0)
				end
			end
			task.wait(0.1)
		end
		if disc.Parent then
			for _, e in ipairs(disc:GetDescendants()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
			TweenService:Create(disc, TweenInfo.new(0.6), { Transparency = 1 }):Play()
			Debris:AddItem(disc, 1.2)
		end
	end)
end

-- ── Moves ───────────────────────────────────────────────────────────────────
local function face(d: Dragon, pos: Vector3)
	local f = flat(pos - d.body.Position)
	if f.Magnitude > 0.1 then d.look = f.Unit end
end

local function breath(d: Dragon, target: Victim)
	d.track = target.root
	setState(d, "breathWindup")
	sound(d, "Roar2")
	if not hold(d, 0.5) then return end
	d.track = nil
	local mouth = d.mouth.WorldPosition
	local apex = Vector3.new(mouth.X, d.arena.floorY, mouth.Z)
	local dir = flat(target.root.Position - apex)
	dir = if dir.Magnitude > 0.1 then dir.Unit else d.look
	local RANGE, HALF = 44, math.rad(22)
	local sweep = if d.enraged then math.rad(50) else 0
	cone(d, apex, dir, RANGE, HALF + sweep / 2, 0.9)
	d.look = rotY(dir, -sweep / 2)
	if not hold(d, 0.9) then return end
	setState(d, "breath")
	local duration = if d.enraged then 2 else 1.6
	fxRemote:FireAllClients({ kind = "breath", model = d.model, duration = duration, range = RANGE,
		from = rotY(dir, -sweep / 2), to = rotY(dir, sweep / 2) })
	local hitAt: { [Model]: number } = {}
	local t0 = os.clock()
	while os.clock() - t0 < duration do
		local cur = rotY(dir, -sweep / 2 + sweep * (os.clock() - t0) / duration)
		d.look = cur
		for _, v in ipairs(victims(d)) do
			local off = flat(v.root.Position - apex)
			if off.Magnitude <= RANGE and off.Magnitude > 0.5
				and math.acos(math.clamp(off.Unit:Dot(cur), -1, 1)) <= HALF + 0.05
				and os.clock() - (hitAt[v.char] or 0) >= 0.3 then
				hitAt[v.char] = os.clock()
				hit(d, v, 0.28, nil, 0, 0)
			end
		end
		task.wait(0.1)
		if not alive(d) then return end
	end
	setState(d, "idle")
	hold(d, 0.3)
end

local function fireballs(d: Dragon)
	local vs = victims(d)
	if #vs == 0 then return end
	setState(d, "spit")
	local n = if d.enraged then 6 else 4
	for i = 1, n do
		local v = vs[(i - 1) % #vs + 1]
		if v.root.Parent then
			face(d, v.root.Position)
			local lead = flat(v.root.AssemblyLinearVelocity) * 0.45
			local jitter = Vector3.new(math.random(-40, 40) / 10, 0, math.random(-40, 40) / 10)
			local aim = clampToArena(d, v.root.Position + lead + jitter, 4)
			aim = Vector3.new(aim.X, d.arena.floorY, aim.Z)
			local FLIGHT = 1.1
			circle(d, aim, 7, FLIGHT)
			fxRemote:FireAllClients({ kind = "fireball", model = d.model, to = aim, t = FLIGHT })
			task.delay(FLIGHT, function()
				if not d.model.Parent then return end
				fxRemote:FireAllClients({ kind = "explode", at = aim, radius = 7 })
				for _, w in ipairs(victims(d)) do
					if flatDist(w.root.Position, aim) <= 7 and w.root.Position.Y - d.arena.floorY < 9 then
						hit(d, w, 0.85, aim, 40, 18)
					end
				end
				burnPatch(d, aim, 5, 4)
			end)
		end
		if not hold(d, if d.enraged then 0.3 else 0.45) then return end
	end
	hold(d, 0.6)
end

local function gust(d: Dragon)
	setState(d, "gust")
	d.pitch = math.rad(-16) -- rears up
	local c = flat(d.body.Position) + Vector3.new(0, d.arena.floorY, 0)
	circle(d, c, 30, 0.9)
	sound(d, "Wing")
	if not hold(d, 0.9) then return end
	fxRemote:FireAllClients({ kind = "gust", at = c, radius = 30 })
	sound(d, "Wing")
	for _, v in ipairs(victims(d)) do
		if flatDist(v.root.Position, c) <= 30 then hit(d, v, 0.45, c, 70, 20) end
	end
	hold(d, 0.6)
	d.pitch = 0
end

-- Rears up on its hind legs and brings both forelimbs down: a shockwave in
-- front of its chest.
local function slam(d: Dragon)
	local c = flat(d.body.Position + d.look * 16) + Vector3.new(0, d.arena.floorY, 0)
	setState(d, "rise")
	sound(d, "Roar2")
	d.pitch = math.rad(-24)
	circle(d, c, 16, 1.0)
	if not hold(d, 0.85) then return end
	setState(d, "slam")
	d.pitch = math.rad(6)
	if not hold(d, 0.15) then return end
	fxRemote:FireAllClients({ kind = "quake", at = c, radius = 16 })
	for _, v in ipairs(victims(d)) do
		if flatDist(v.root.Position, c) <= 16 then hit(d, v, 1.1, c, 55, 30) end
	end
	if not hold(d, 0.6) then return end
	d.pitch = 0
end

-- A raking swipe of one foreleg across the ground in front of it.
local function swipe(d: Dragon, target: Victim)
	d.track = target.root
	setState(d, "swipeWindup")
	if not hold(d, 0.2) then return end
	d.track = nil
	local apex = flat(d.body.Position + d.look * 6) + Vector3.new(0, d.arena.floorY, 0)
	local dir = flat(target.root.Position - apex)
	dir = if dir.Magnitude > 0.1 then dir.Unit else d.look
	d.look = dir
	local RANGE, HALF = 24, math.rad(55)
	cone(d, apex, dir, RANGE, HALF, 0.55)
	if not hold(d, 0.55) then return end
	setState(d, "swipe")
	sound(d, "Wing")
	for _, v in ipairs(victims(d)) do
		local off = flat(v.root.Position - apex)
		if off.Magnitude <= RANGE and (off.Magnitude < 3 or math.acos(math.clamp(off.Unit:Dot(dir), -1, 1)) <= HALF) then
			hit(d, v, 1, apex, 60, 20)
		end
	end
	hold(d, 0.6)
end

-- Between moves it prowls along its end of the arena, eyes on the nearest
-- player.
local function prowl(d: Dragon)
	local side = Vector3.new(-d.home.look.Z, 0, d.home.look.X)
	local p = d.home.pos + side * ((math.random() * 2 - 1) * 16)
	d.pos = Vector3.new(p.X, hoverY(d), p.Z)
end

-- ── The Inferno Beam (the shield minigame) ──────────────────────────────────
local ARROWS = { "Up", "Down", "Left", "Right" }

local function makeKeys(n: number): { string }
	local keys = {}
	for i = 1, n do
		local k
		repeat
			k = ARROWS[math.random(1, 4)]
		until not (i > 2 and keys[i - 1] == k and keys[i - 2] == k)
		keys[i] = k
	end
	return keys
end

-- ── The Aegis: a huge tower shield standing in the arena ────────────────────
-- It waits on a stone plinth from the start of the fight. When the dragon
-- charges its Inferno Beam, the player it targets has to run and grab it.
type Aegis = {
	model: Model,
	plate: BasePart,
	front: Attachment,
	home: CFrame,
	glow: Highlight,
}

-- The shield itself, anchored with its plate's centre at `cf` (front = -Z).
local function buildShield(parent: Instance, cf: CFrame): (Model, BasePart, Attachment)
	local m = Instance.new("Model")
	m.Name = "DragonAegis"
	local function piece(size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Size = size
		if shape then p.Shape = shape end
		p.CFrame = cf * offset
		p.Color = color
		p.Material = material
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	local plate = piece(Vector3.new(7, 9, 0.6), CFrame.identity, STEEL, Enum.Material.Metal)
	plate.Name = "Plate"
	local RIM = 0.55
	piece(Vector3.new(7.5, RIM, 0.9), CFrame.new(0, 4.5, 0), IRON, Enum.Material.Metal)
	piece(Vector3.new(7.5, RIM, 0.9), CFrame.new(0, -4.5, 0), IRON, Enum.Material.Metal)
	piece(Vector3.new(RIM, 9.5, 0.9), CFrame.new(3.5, 0, 0), IRON, Enum.Material.Metal)
	piece(Vector3.new(RIM, 9.5, 0.9), CFrame.new(-3.5, 0, 0), IRON, Enum.Material.Metal)
	-- Gold cross bands and a raised boss.
	piece(Vector3.new(0.7, 8.4, 0.75), CFrame.new(0, 0, -0.1), Color3.fromRGB(190, 150, 70), Enum.Material.Metal)
	piece(Vector3.new(6.4, 0.7, 0.75), CFrame.new(0, 1, -0.1), Color3.fromRGB(190, 150, 70), Enum.Material.Metal)
	piece(Vector3.new(0.9, 2.8, 2.8), CFrame.new(0, 1, -0.45) * CFrame.Angles(0, math.rad(90), 0),
		Color3.fromRGB(210, 170, 90), Enum.Material.Metal, Enum.PartType.Cylinder)
	for _, c in ipairs({ { -2.9, 3.9 }, { 2.9, 3.9 }, { -2.9, -3.9 }, { 2.9, -3.9 } }) do
		piece(Vector3.new(0.6, 0.6, 0.6), CFrame.new(c[1], c[2], -0.35), Color3.fromRGB(200, 200, 205), Enum.Material.Metal, Enum.PartType.Ball)
	end
	for _, p in ipairs(m:GetChildren()) do
		if p ~= plate and p:IsA("BasePart") then
			local w = Instance.new("WeldConstraint")
			w.Part0 = plate
			w.Part1 = p
			w.Parent = p
		end
	end
	local front = Instance.new("Attachment")
	front.Name = "ShieldFront"
	front.Position = Vector3.new(0, 1, -1.1)
	front.Parent = plate
	m.PrimaryPart = plate
	m.Parent = parent
	return m, plate, front
end

local function setAnchored(m: Model, anchored: boolean)
	for _, p in ipairs(m:GetDescendants()) do
		if p:IsA("BasePart") then p.Anchored = anchored end
	end
end

-- Stand it on a plinth a little off the arena's centre, facing into the room.
local function placeAegis(d: Dragon): Aegis
	local a = d.arena
	local base = a.center + Vector3.new(0, 0, -math.min(14, (a.maxZ - a.minZ) * 0.1))
	local stone = Color3.fromRGB(70, 64, 72)
	local facing = CFrame.lookAt(Vector3.zero, Vector3.new(-1, 0, 1)) -- toward the game camera
	part(d.fx, { Name = "AegisPlinth", Size = Vector3.new(7, 0.8, 3.4), CFrame = CFrame.new(base + Vector3.new(0, 0.4, 0)) * facing,
		Color = stone, Material = Enum.Material.Slate })
	part(d.fx, { Name = "AegisPlinth", Size = Vector3.new(6, 0.5, 2.6), CFrame = CFrame.new(base + Vector3.new(0, 1.05, 0)) * facing,
		Color = Color3.fromRGB(86, 78, 88), Material = Enum.Material.Slate })
	-- Upright on the plinth, tipped back a touch as if propped there, its
	-- face (gold cross and boss) turned toward the game camera.
	local at = base + Vector3.new(0, 1.3 + 4.75, 0)
	local home = CFrame.lookAt(at, at + Vector3.new(-1, 0, 1)) * CFrame.Angles(math.rad(6), 0, 0)
	local model, plate, front = buildShield(d.fx, home)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 210, 140)
	light.Brightness = 0.8
	light.Range = 12
	light.Parent = plate
	local glow = Instance.new("Highlight")
	glow.FillColor = GOLD
	glow.OutlineColor = GOLD
	glow.FillTransparency = 1
	glow.OutlineTransparency = 1
	glow.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	glow.Parent = model
	return { model = model, plate = plate, front = front, home = home, glow = glow }
end

-- Into the hands of `v`: held up before them, welded to their body.
local function takeAegis(ag: Aegis, v: Victim)
	ag.model:PivotTo(v.root.CFrame * CFrame.new(0, 1.2, -2.7))
	local w = Instance.new("WeldConstraint")
	w.Name = "RootWeld"
	w.Part0 = v.root
	w.Part1 = ag.plate
	w.Parent = ag.plate
	setAnchored(ag.model, false)
end

-- Back on its plinth.
local function returnAegis(ag: Aegis)
	if not ag.model.Parent then return end
	local w = ag.plate:FindFirstChild("RootWeld")
	if w then w:Destroy() end
	setAnchored(ag.model, true)
	ag.plate.AssemblyLinearVelocity = Vector3.zero
	ag.model:PivotTo(ag.home)
end

-- The beam itself: Beam objects from the mouth to `to`, drawn by every client
-- along its own (animated) head.
local function beamVisual(d: Dragon, to: Attachment, colors: { Color3 }, widths: { number }): { Instance }
	local out: { Instance } = {}
	local specs = {
		{ w = widths[1], c = colors[1], t = 0.15, tex = FIRE_TEXTURE },
		{ w = widths[2], c = colors[2], t = 0.05, tex = nil },
		{ w = widths[3], c = colors[3], t = 0.7, tex = nil },
	}
	for _, s in ipairs(specs) do
		local b = Instance.new("Beam")
		b.Attachment0 = d.mouth
		b.Attachment1 = to
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Width0 = s.w * 0.75
		b.Width1 = s.w
		b.Color = ColorSequence.new(s.c)
		b.Transparency = NumberSequence.new(s.t)
		if s.tex then
			b.Texture = s.tex
			b.TextureMode = Enum.TextureMode.Wrap
			b.TextureLength = 7
			b.TextureSpeed = 3.5
		end
		b.Parent = d.head
		table.insert(out, b)
	end
	return out
end

local function beam(d: Dragon, target: Victim)
	local ag = (d :: any).aegis :: Aegis?
	if not ag or not ag.model.Parent then return end
	local plr = target.player
	local root = target.root
	local char = target.char
	nextToken += 1
	local token = nextToken
	local nKeys = BEAM_KEYS[math.min(d.beamsDone + 1, #BEAM_KEYS)]
	d.beamsDone += 1
	local keys = makeKeys(nKeys)
	local duration = BEAM_TIME_BASE + nKeys * BEAM_TIME_PER_KEY
	local home = ag.home.Position
	-- Time enough to run to the shield (at walking pace, plus a margin).
	local grabTime = math.clamp(flatDist(root.Position, home) / 16 + 1.6, BEAM_GRAB_MIN, BEAM_GRAB_MAX)

	-- It settles on its perch and glares at them.
	d.pos = Vector3.new(d.home.pos.X, hoverY(d), d.home.pos.Z)
	d.track = root
	setState(d, "beamCharge")
	sound(d, "Charge")
	ag.glow.FillTransparency = 0.75
	ag.glow.OutlineTransparency = 0
	beamRemote:FireClient(plr, { phase = "grab", token = token, shield = ag.plate, grabTime = grabTime })
	fxRemote:FireAllClients({ kind = "beamCharge", model = d.model, t = grabTime })

	local fireAt = os.clock() + grabTime
	local grabbed = false
	local b: Beam? = nil
	local visuals: { Instance } = {}
	local success = false
	local ok, err = pcall(function()
		-- Run for the shield!
		while os.clock() < fireAt do
			task.wait(0.05)
			if not alive(d) or not root.Parent or target.hum.Health <= 0 then return end
			if not grabbed and flatDist(root.Position, home) <= 7 and math.abs(root.Position.Y - home.Y) < 10 then
				grabbed = true
				-- Planted, the shield raised, facing the dragon.
				local m = d.mouth.WorldPosition
				root.CFrame = CFrame.lookAt(root.Position, Vector3.new(m.X, root.Position.Y, m.Z))
				root.AssemblyLinearVelocity = Vector3.zero
				root.Anchored = true
				char:SetAttribute("Rooted", true)
				takeAegis(ag, target)
				ag.glow.FillTransparency, ag.glow.OutlineTransparency = 1, 1
				fireAt = math.min(fireAt, os.clock() + BEAM_BRACE)
				char:SetAttribute("InvulnerableUntil", fireAt + duration + 1)
				b = {
					token = token, target = target, keys = keys, progress = 0, lastStep = 0,
					opensAt = fireAt, deadline = fireAt + duration,
				}
				beams[token] = b :: Beam
				beamRemote:FireClient(plr, { phase = "start", token = token, keys = keys, windup = fireAt - os.clock(), duration = duration })
				fxRemote:FireAllClients({ kind = "shield", char = char, on = true })
			end
		end
		-- FIRE: it holds still and pours it on.
		d.track = nil
		d.pos = d.body.Position
		setState(d, "beam")
		sound(d, "Roar1")
		ag.glow.FillTransparency, ag.glow.OutlineTransparency = 1, 1
		local mouth = d.mouth.WorldPosition

		if not grabbed or not b then
			-- They never reached the shield: straight into them.
			local hitAt = Instance.new("Attachment")
			hitAt.Parent = root
			table.insert(visuals, hitAt)
			for _, v in ipairs(beamVisual(d, hitAt, { FLAME, Color3.fromRGB(255, 240, 200), FLAME_DEEP }, { 5.5, 2, 10 })) do
				table.insert(visuals, v)
			end
			fxRemote:FireAllClients({ kind = "beamBreak", at = root.Position, char = char })
			if (char:GetAttribute("InvulnerableUntil") or 0) <= os.clock() then
				target.hum:TakeDamage(target.hum.MaxHealth * BEAM_FAIL)
				knock(target, mouth, 60, 22)
			end
			task.wait(0.7)
			return
		end

		local front = ag.front
		root.CFrame = CFrame.lookAt(root.Position, Vector3.new(mouth.X, root.Position.Y, mouth.Z))
		for _, v in ipairs(beamVisual(d, front, { FLAME, Color3.fromRGB(255, 240, 200), FLAME_DEEP }, { 5.5, 2, 10 })) do
			table.insert(visuals, v)
		end
		local clash = emitter(front, { Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), FLAME),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.25, 0.5), Speed = NumberRange.new(18, 34), SpreadAngle = Vector2.new(75, 75),
			EmissionDirection = Enum.NormalId.Front, Rate = 120 })
		local splash = emitter(front, { Texture = FIRE_TEXTURE, Color = ColorSequence.new(FLAME, FLAME_DEEP),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 5) }),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }),
			Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(85, 85),
			EmissionDirection = Enum.NormalId.Front, Rate = 45 })
		local light = Instance.new("PointLight")
		light.Color = FLAME
		light.Range = 16
		light.Brightness = 1.5 -- (brighter washed the whole arena out)
		light.Parent = ag.plate
		table.insert(visuals, clash)
		table.insert(visuals, splash)
		table.insert(visuals, light)
		-- The shield takes the beam: it blazes gold and throws up a shimmering
		-- barrier before it.
		ag.glow.FillTransparency, ag.glow.OutlineTransparency = 0.6, 0
		local barrier = Instance.new("Part")
		barrier.Name = "AegisBarrier"
		barrier.Shape = Enum.PartType.Ball
		barrier.Size = Vector3.new(11, 11, 11)
		barrier.Material = Enum.Material.ForceField
		barrier.Color = GOLD
		barrier.CanCollide, barrier.CanQuery, barrier.CanTouch, barrier.Massless, barrier.CastShadow = false, false, false, true, false
		barrier.CFrame = ag.plate.CFrame * CFrame.new(0, 0.5, -2.2)
		local bw = Instance.new("WeldConstraint")
		bw.Part0 = ag.plate
		bw.Part1 = barrier
		bw.Parent = barrier
		barrier.Parent = ag.model
		table.insert(visuals, barrier)
		fxRemote:FireAllClients({ kind = "beamFire", model = d.model, char = char, front = ag.front })

		-- The beam shoves them back; every right key digs in a step forward.
		local look = flat(mouth - root.Position)
		look = if look.Magnitude > 0.1 then look.Unit else Vector3.zAxis
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { char, d.model, d.fx }
		b.onStep = function()
			if root.Parent and flatDist(root.Position, mouth) > 16 then
				root.CFrame += look * 0.3
			end
		end
		while os.clock() < b.deadline + 0.2 and b.progress < #keys do
			task.wait(0.1)
			if not alive(d) or not root.Parent or target.hum.Health <= 0 then return end
			if not Workspace:Raycast(root.Position, -look * 2.5, params) then
				root.CFrame -= look * 0.05
			end
		end
		success = b.progress >= #keys
	end)
	if not ok then warn("[DragonBoss] Inferno Beam failed:", err) end
	beams[token] = nil
	for _, v in ipairs(visuals) do v:Destroy() end
	fxRemote:FireAllClients({ kind = "beamStop" })
	ag.glow.FillTransparency, ag.glow.OutlineTransparency = 1, 1

	local stillThere = root.Parent ~= nil and target.hum.Health > 0
	local flung = false
	if grabbed and alive(d) and stillThere and ok then
		if success then
			-- Thrown back into its own maw.
			local back = beamVisual(d, ag.front, { GOLD, Color3.new(1, 1, 1), Color3.fromRGB(255, 180, 60) }, { 7, 2.6, 13 })
			fxRemote:FireAllClients({ kind = "reflect", model = d.model, from = ag.front.WorldPosition })
			task.delay(0.6, function()
				for _, v in ipairs(back) do v:Destroy() end
			end)
		else
			fxRemote:FireAllClients({ kind = "beamBreak", at = ag.front.WorldPosition, char = char })
			char:SetAttribute("InvulnerableUntil", 0)
			target.hum:TakeDamage(target.hum.MaxHealth * BEAM_FAIL)
			-- The shield is torn out of their hands (it's back on its plinth soon).
			local w = ag.plate:FindFirstChild("RootWeld")
			if w then w:Destroy() end
			ag.plate.AssemblyLinearVelocity = -flat(d.look) * 40 + Vector3.new(0, 30, 0)
			ag.plate.AssemblyAngularVelocity = Vector3.new(math.random(-8, 8), math.random(-8, 8), math.random(-8, 8))
			task.delay(2.2, function() returnAegis(ag) end)
			flung = true
		end
	end

	-- Let them go.
	if not flung then returnAegis(ag) end
	if grabbed then
		if root.Parent then root.Anchored = false end
		char:SetAttribute("Rooted", nil)
		if success then char:SetAttribute("InvulnerableUntil", os.clock() + 0.6) end
		fxRemote:FireAllClients({ kind = "shield", char = char, on = false })
	end
	beamRemote:FireClient(plr, { phase = "end", token = token, success = success, grabbed = grabbed })
	if flung and stillThere then
		knock(target, d.mouth.WorldPosition, 60, 22)
	end
	d.bob = true

	if success and alive(d) then
		-- Stunned: it crashes to the floor for everyone to punish.
		task.delay(0.35, function()
			if alive(d) then d.hum:TakeDamage(d.hum.MaxHealth * BEAM_REFLECT) end
		end)
		setState(d, "stunned")
		d.bob = false
		local p = d.body.Position
		setAlign(d, 10, 60)
		d.pos = Vector3.new(p.X, d.arena.floorY + d.groundOffset - 3, p.Z) -- slumped on its belly
		d.pitch, d.roll = math.rad(10), math.rad(12)
		local t0 = os.clock()
		while os.clock() - t0 < STUN_TIME and alive(d) do task.wait(0.1) end
		d.pitch, d.roll = 0, 0
		setAlign(d)
		d.bob = true
		d.pos = Vector3.new(p.X, hoverY(d), p.Z)
	end
end

-- Who gets the beam: whoever is nearest the shield (they have a chance to
-- reach it).
local function beamTarget(d: Dragon, vs: { Victim }): Victim?
	local ag = (d :: any).aegis :: Aegis?
	if not ag then return vs[math.random(1, #vs)] end
	local best, bestD = nil, math.huge
	for _, v in ipairs(vs) do
		local dist = flatDist(v.root.Position, ag.home.Position)
		if dist < bestD then best, bestD = v, dist end
	end
	return best
end

-- ── Phases ──────────────────────────────────────────────────────────────────
local function intro(d: Dragon)
	local v = nearest(d, victims(d))
	d.track = v and v.root or nil
	setState(d, "roar")
	sound(d, "Roar1")
	fxRemote:FireAllClients({ kind = "intro", model = d.model, name = "IGNARATH", title = "THE CINDER WYRM" })
	hold(d, 2.4)
end

local function enrage(d: Dragon)
	d.enraged = true
	d.model:SetAttribute("Enraged", true)
	setState(d, "roar")
	sound(d, "Roar1")
	fxRemote:FireAllClients({ kind = "roar", model = d.model, enrage = true })
	local outline = Instance.new("Highlight")
	outline.Name = "EnrageGlow"
	outline.FillColor = Color3.fromRGB(255, 60, 20)
	outline.FillTransparency = 0.82
	outline.OutlineColor = Color3.fromRGB(255, 120, 40)
	outline.OutlineTransparency = 0.35
	outline.DepthMode = Enum.HighlightDepthMode.Occluded
	outline.Parent = d.model
	for _, name in ipairs({ "Body", "LeftWing", "RightWing" }) do
		local p = d.model:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			emitter(p, { Name = "EnrageEmbers", Texture = FIRE_TEXTURE, Color = ColorSequence.new(FLAME, FLAME_DEEP),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
				Lifetime = NumberRange.new(0.4, 0.9), Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, 8, 0),
				Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rate = 18 })
		end
	end
	local c = flat(d.body.Position) + Vector3.new(0, d.arena.floorY, 0)
	for _, v in ipairs(victims(d)) do
		if flatDist(v.root.Position, c) <= 24 then hit(d, v, 0.2, c, 50, 15) end
	end
	hold(d, 1.8)
end

local function die(d: Dragon)
	if d.dead then return end
	d.dead = true
	d.track = nil
	setState(d, "dead")
	sound(d, "Roar2")
	local pos = d.body.Position
	pcall(d.onDied)
	pcall(deps.reward, d.model, pos, XP_REWARD)
	fxRemote:FireAllClients({ kind = "death", model = d.model })
	-- Down it comes, rolling over.
	d.bob = false
	setAlign(d, 6, 30)
	d.pos = Vector3.new(pos.X, d.arena.floorY + d.groundOffset * 0.5, pos.Z)
	d.pitch, d.roll = math.rad(10), math.rad(35)
	task.delay(2.4, function()
		if not d.model.Parent then return end
		for _, p in ipairs(d.model:GetDescendants()) do
			if p:IsA("BasePart") then
				TweenService:Create(p, TweenInfo.new(1.2), { Transparency = 1 }):Play()
			elseif p:IsA("ParticleEmitter") then
				p.Enabled = false
			end
		end
		task.wait(1.3)
		if d.model.Parent then d.model:Destroy() end
	end)
end

local function run(d: Dragon)
	-- It waits, circling, until someone steps into its arena.
	while alive(d) and #victims(d) == 0 do task.wait(0.4) end
	if not alive(d) then return end
	intro(d)
	local last = ""
	while alive(d) do
		local vs = victims(d)
		if #vs == 0 or not deps.canAct(d.model) then
			task.wait(0.3)
			continue
		end
		local target = nearest(d, vs) :: Victim
		local move: string
		if d.enrageQueued and not d.enraged then
			move = "enrage"
		elseif d.beamsQueued > d.beamsDone then
			move = "beam"
		else
			-- Anyone within reach of its claws (just in front of it)?
			local close = false
			local reach = d.body.Position + d.look * 12
			for _, v in ipairs(vs) do
				if flatDist(v.root.Position, reach) < 20 then close = true end
			end
			local pool = {}
			local function add(m: string, w: number)
				if m == last then return end
				for _ = 1, w do table.insert(pool, m) end
			end
			add("breath", 3)
			add("fireballs", if close then 2 else 4)
			add("gust", if close then 2 else 1)
			if close then
				add("swipe", 4)
				add("slam", 3)
			end
			move = pool[math.random(1, #pool)]
		end
		last = move
		d.track = nil
		local ok, err = pcall(function()
			if move == "enrage" then
				enrage(d)
			elseif move == "beam" then
				local t = beamTarget(d, vs)
				if t then beam(d, t) end
			elseif move == "breath" then
				breath(d, target)
			elseif move == "fireballs" then
				fireballs(d)
			elseif move == "gust" then
				gust(d)
			elseif move == "swipe" then
				swipe(d, target)
			elseif move == "slam" then
				slam(d)
			end
		end)
		if not ok then warn(`[DragonBoss] {move} failed:`, err) end
		if not alive(d) then break end
		-- Settle, prowl a few steps along its perch and keep an eye on the
		-- nearest player.
		d.pitch, d.roll = 0, 0
		setAlign(d)
		setState(d, "idle")
		if math.random() < 0.6 then prowl(d) else d.pos = Vector3.new(d.pos.X, hoverY(d), d.pos.Z) end
		local n = nearest(d, victims(d))
		d.track = n and n.root or nil
		hold(d, if d.enraged then GAP_ENRAGED else GAP)
	end
end

-- ── Public ──────────────────────────────────────────────────────────────────
function DragonBoss.Available(): boolean
	return true -- (built from parts: DragonBuilder)
end

local function arenaOf(room: any): Arena
	local S = 12
	local minX = room.gx * S - S / 2
	local maxX = (room.gx + room.w - 1) * S + S / 2
	local minZ = room.gz * S - S / 2
	local maxZ = (room.gz + room.d - 1) * S + S / 2
	return {
		minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, floorY = room.floorY,
		center = Vector3.new((minX + maxX) / 2, room.floorY, (minZ + maxZ) / 2),
	}
end

-- Spawn the dragon over `room` (a DungeonGenerator room). `health` carries
-- over damage from an earlier visit. `onDied` runs once when it's slain.
function DragonBoss.Spawn(parent: Instance, room: any, health: number?, runId: string?, onDied: () -> ()): Model?
	local model = DragonBuilder.Build()
	model.Name = "Ignarath"
	pcall(function() model:ScaleTo(SCALE) end)

	local body = model:FindFirstChild("Body") :: BasePart?
	local head = model:FindFirstChild("Head") :: BasePart?
	local root = model:FindFirstChild("Root") :: BasePart?
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not (body and head and root and hum) then
		model:Destroy()
		return nil
	end
	root.Name = "HumanoidRootPart"
	hum.Name = "Humanoid"
	for _, c in ipairs(model:GetDescendants()) do
		if c:IsA("Animator") or c:IsA("Script") or c:IsA("LocalScript") then c:Destroy() end
	end

	local arena = arenaOf(room)
	-- It perches against a wall, facing the room: preferably the +X wall (the
	-- game camera looks toward +X / -Z, so it sits in the upper right of the
	-- screen, as in the concept art), never the side players come in from.
	local from: Vector3? = nil
	local bestD = math.huge
	for _, plr in ipairs(Players:GetPlayers()) do
		local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and plr:GetAttribute("InLobby") == false then
			local dd = flatDist(r.Position, arena.center)
			if dd < bestD then from, bestD = r.Position, dd end
		end
	end
	local toward = if from then flat(arena.center - from) else Vector3.new(0, 0, -1)
	toward = if toward.Magnitude > 0.1 then toward.Unit else Vector3.new(0, 0, -1)
	local wallDir = Vector3.new(0, 0, -1)
	for _, w in ipairs({ Vector3.xAxis, -Vector3.zAxis, -Vector3.xAxis, Vector3.zAxis }) do
		if w:Dot(toward) > -0.3 then
			wallDir = w
			break
		end
	end
	local halfExtent = if wallDir.X ~= 0 then (arena.maxX - arena.minX) / 2 else (arena.maxZ - arena.minZ) / 2
	local perch = arena.center + wallDir * math.max(halfExtent - PERCH_INSET, 10)
	local look = -wallDir
	model:PivotTo(bodyCF(arena.center, look))
	local bbCF, bbSize = model:GetBoundingBox()
	local groundOffset = body.Position.Y - (bbCF.Position.Y - bbSize.Y / 2)

	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide = false
			p.CanTouch = false
			p.Massless = p ~= body
			p.CanQuery = p ~= root
		elseif p:IsA("Sound") then
			p.Volume = if p.Name == "Wing" then 1 else 2.2
			p.RollOffMaxDistance = 260
		end
	end
	root.Transparency = 1

	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.PlatformStand = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	pcall(function() hum.EvaluateStateMachine = false end)
	local scale = DifficultyManager.GetMobScale(runId)
	local maxHp = math.floor(400 * HEALTH_MULT * scale.health)
	hum.MaxHealth = maxHp
	hum.Health = if health and health < maxHp then math.max(1, math.floor(health)) else maxHp

	model:SetAttribute("IsBoss", true)
	if runId then model:SetAttribute("RunId", runId) end
	model:SetAttribute("IsElite", false)
	model:SetAttribute("BossKind", "dragon")
	model:SetAttribute("DisplayName", NAME)
	model:SetAttribute("FloorY", arena.floorY)
	model:SetAttribute("HitRadius", HIT_RADIUS)
	model:SetAttribute("ArenaMin", Vector3.new(arena.minX, arena.floorY, arena.minZ))
	model:SetAttribute("ArenaMax", Vector3.new(arena.maxX, arena.floorY, arena.maxZ))
	model:SetAttribute("DragonState", "idle")

	-- Where skills land on it (SkillManager moves it per caster).
	local proxy = Instance.new("Part")
	proxy.Name = "HitProxy"
	proxy.Size = Vector3.new(2, 2, 2)
	proxy.Transparency = 1
	proxy.Anchored = true
	proxy.CanCollide = false
	proxy.CanQuery = false
	proxy.CanTouch = false
	proxy.CFrame = CFrame.new(arena.center + Vector3.new(0, 3, 0))
	proxy.Parent = model

	local mouth = head:FindFirstChild("DragonMouth") :: Attachment?
	if not mouth then
		mouth = Instance.new("Attachment")
		mouth.Name = "DragonMouth"
		mouth.Position = Vector3.new(0, 0, head.Size.Z * 0.4)
		mouth.Parent = head
	end

	local pos = Vector3.new(perch.X, arena.floorY + groundOffset + HOVER, perch.Z)
	model:PivotTo(bodyCF(pos, look))
	local att = Instance.new("Attachment")
	att.Name = "DragonAlign"
	att.Parent = body
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.MaxForce = math.huge
	ap.Responsiveness = 14
	ap.MaxVelocity = 45
	ap.Position = pos
	ap.Parent = body
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.Responsiveness = 9
	ao.CFrame = bodyCF(Vector3.zero, look)
	ao.Parent = body

	local fx = Instance.new("Folder")
	fx.Name = "DragonFX"
	fx.Parent = Workspace

	pcall(function() model.ModelStreamingMode = Enum.ModelStreamingMode.Atomic end)
	model.Parent = parent
	pcall(function() body:SetNetworkOwner(nil) end)

	local d: Dragon = {
		model = model, body = body, root = root, head = head, hum = hum, mouth = mouth,
		arena = arena, groundOffset = groundOffset,
		damage = DAMAGE_MULT * scale.damage,
		ap = ap, ao = ao, pos = pos, look = look, track = nil, pitch = 0, roll = 0, bob = true,
		enraged = false, enrageQueued = false, beamsQueued = 0, beamsDone = 0, dead = false,
		onDied = onDied, fx = fx, aegis = nil, home = { pos = pos, look = look },
	}
	-- The shield waits on its plinth in the arena for the whole fight.
	d.aegis = placeAegis(d)
	-- Thresholds it's already past (a return visit) don't fire again.
	local frac = hum.Health / hum.MaxHealth
	for _, at in ipairs(BEAM_AT) do
		if frac <= at then
			d.beamsQueued += 1
			d.beamsDone += 1
		end
	end
	d.enrageQueued = frac <= 0.5

	hum.HealthChanged:Connect(function(h)
		if d.dead then return end
		if h <= 0 then
			die(d)
			return
		end
		local f = h / hum.MaxHealth
		while d.beamsQueued < #BEAM_AT and f <= BEAM_AT[d.beamsQueued + 1] do
			d.beamsQueued += 1
		end
		if f <= 0.5 then d.enrageQueued = true end
	end)

	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent then
			conn:Disconnect()
			return
		end
		if d.track and d.track.Parent then
			local f = flat(d.track.Position - body.Position)
			if f.Magnitude > 1 then d.look = f.Unit end
		end
		ap.Position = d.pos
		ao.CFrame = bodyCF(Vector3.zero, d.look) * CFrame.Angles(d.pitch, 0, d.roll)
	end)
	model.Destroying:Connect(function()
		d.dead = true
		fx:Destroy()
	end)

	task.spawn(run, d)
	return model
end

function DragonBoss.Init(d: Deps)
	deps = d
	fxRemote = Network.GetRemoteEvent(Network.Remotes.DragonFX)
	beamRemote = Network.GetRemoteEvent(Network.Remotes.DragonBeam)
	Network.GetRemoteEvent(Network.Remotes.DragonBeamResult).OnServerEvent:Connect(function(plr: Player, token: any, step: any)
		if typeof(token) ~= "number" or typeof(step) ~= "number" then return end
		local b = beams[token]
		if not b or b.target.player ~= plr then return end
		local now = os.clock()
		-- (a little grace either side for the round trip)
		if now < b.opensAt - 0.15 or now > b.deadline + 0.25 then return end
		if step ~= b.progress + 1 or now - b.lastStep < 0.06 then return end
		b.progress = step
		b.lastStep = now
		if b.onStep then b.onStep() end
	end)
end

return DragonBoss
