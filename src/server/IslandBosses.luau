--!strict
--[[
	IslandBosses.luau
	The Forgotten Isle's six ritual bosses (IslandRitual summons one at
	random). Each is a BossAI kind registered from here (BossAI.Register):
	its own body built from parts, three or more attacks and a telegraphed
	SIGNATURE (invulnerable while it runs, like every boss's), written with
	BossAI's own helpers (BossAI.Kit). Every attack is shown on the ground
	in red before it lands. Below half health each one enrages (BossAI):
	faster, and bigger versions of its moves.

	  The Drowned Sovereign  Trident Sweep · Tidal Wave (jump it) · Geysers ·
	                         THE DROWNING TIDE (the arena floods: only the
	                         glowing rings are safe)
	  The Ashen Colossus     Ground Slam (an expanding zone) · Volcanic Debris ·
	                         Frontal Eruption · CATACLYSM (the arena erupts in
	                         rings, middle first: step into the cooled stone)
	  The Hollow Saint       Consecration · Spectral Host · Cross of Light ·
	                         LITANY OF LIGHT (beams turn round her)
	  The Thorn Matriarch    Root Snare (slows) · Thorn Lines · Thornlings ·
	                         WILD OVERGROWTH (all but two slices of the arena
	                         burst with thorns)
	  The Riftbound Knight   Rift Strike (teleports onto you) · Rift Slashes ·
	                         Rift Tear (rifts that let enemies through) ·
	                         DIMENSION REND (slashes across the whole arena)
	  The Eclipse Wyrm       Eclipse Breath (a sweep) · Marked Ground · Tail
	                         Sweep · TOTAL ECLIPSE (half the arena burns, then
	                         the other: keep crossing)

	Each falls its own way (IslandBosses.Defeat) and has its own reward: its
	exclusive piece of gear in its Ritual Chest (EquipmentData `boss`).

	The bodies are placeholder geometry, unanimated: see the asset list in
	the Forgotten Isle report.
--]]

local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local BossAI = require(script.Parent:WaitForChild("BossAI"))

local IslandBosses = {}

local K = BossAI.Kit
local FLAT = K.FLAT
local rgb = Color3.fromRGB

-- How far from its middle the arena reaches (IslandConfig.Ritual.arenaRadius
-- is where the boss is held; the signatures fill a little less).
local ARENA = 58

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function flatDir(from: Vector3, to: Vector3): Vector3
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	return if d.Magnitude < 0.1 then Vector3.new(0, 0, -1) else d.Unit
end

local function angleDir(a: number): Vector3
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

local function inCone(origin: Vector3, dir: Vector3, r: number, half: number, p: Vector3): boolean
	local rel = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
	local d = rel.Magnitude
	if d > r then return false end
	if d < 2 then return true end
	return math.acos(math.clamp(rel.Unit:Dot(dir), -1, 1)) <= half
end

local function nearLine(from: Vector3, dir: Vector3, len: number, halfW: number, p: Vector3): boolean
	local rel = Vector3.new(p.X - from.X, 0, p.Z - from.Z)
	local along = rel:Dot(dir)
	if along < 0 or along > len then return false end
	return (rel - dir * along).Magnitude <= halfW
end

-- Hurt everyone (of the arena) for whom `pred` holds, each once.
local function blastWhere(b: any, pred: (Vector3) -> boolean, damage: number, from: Vector3?, hit: { [Model]: boolean }?)
	for _, v in ipairs(K.victims()) do
		local p = v.root.Position
		if K.flatDist(p, b.home) <= ARENA + 25 and (not hit or not hit[v.char]) and pred(p) then
			if hit then hit[v.char] = true end
			K.hurt(v.char, damage, from)
		end
	end
end

-- The players near the arena.
local function inArena(b: any): { any }
	local out = {}
	for _, v in ipairs(K.victims()) do
		if K.flatDist(v.root.Position, b.home) <= ARENA + 25 then table.insert(out, v) end
	end
	return out
end

-- A column bursting out of the floor and fading.
local function column(pos: Vector3, floorY: number, w: number, h: number, color: Color3, life: number, material: Enum.Material?)
	local p = K.part({ Size = Vector3.new(w, h, w), CFrame = CFrame.new(pos.X, floorY + h / 2, pos.Z), Color = color,
		Transparency = 0.25, Material = material or Enum.Material.Neon })
	TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.3, h * 1.25, 0.3), Transparency = 1 }):Play()
	Debris:AddItem(p, life + 0.05)
end

-- A flat disc on the floor (a safe ring, a burning patch).
local function disc(pos: Vector3, floorY: number, r: number, color: Color3, transparency: number, life: number?): BasePart
	local p = K.part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, r * 2, r * 2),
		CFrame = CFrame.new(pos.X, floorY + 0.12, pos.Z) * FLAT, Color = color, Transparency = transparency })
	if life then Debris:AddItem(p, life) end
	return p
end

-- A red ring zone (inner..outer) that holds `t` and is removed.
local function telegraphRing(center: Vector3, inner: number, outer: number, t: number, floorY: number)
	local n = 28
	local mid = (inner + outer) / 2
	for i = 0, n - 1 do
		local a = (i + 0.5) / n * math.pi * 2
		local arc = 2 * math.pi * mid / n + 0.6
		local pos = center + angleDir(a) * mid
		local seg = K.part({ Size = Vector3.new(outer - inner, 0.12, arc), Color = K.TELEGRAPH, Transparency = 0.7,
			CFrame = CFrame.lookAt(Vector3.new(pos.X, floorY + 0.1, pos.Z), Vector3.new(center.X, floorY + 0.1, center.Z)) * CFrame.Angles(0, math.rad(90), 0) })
		TweenService:Create(seg, TweenInfo.new(t, Enum.EasingStyle.Linear), { Transparency = 0.4 }):Play()
		Debris:AddItem(seg, t)
	end
end

-- A random point of the arena between `r0` and `r1` from its middle.
local function arenaPoint(b: any, r0: number, r1: number): Vector3
	local a = math.random() * math.pi * 2
	return b.home + angleDir(a) * (r0 + math.random() * (r1 - r0))
end

-- Into the arena's middle (for its signatures), with a burst where it was
-- and where it lands.
local function toCenter(b: any)
	local from = b.root.Position
	K.shock(from, 8, b.kind.color, b.floorY)
	b.root.AssemblyLinearVelocity = Vector3.zero
	b.root.CFrame = CFrame.new(b.home.X, K.standY(b), b.home.Z) * b.root.CFrame.Rotation
	K.shock(b.home, 14, b.kind.color, b.floorY)
end

local function teleport(b: any, to: Vector3)
	b.root.AssemblyLinearVelocity = Vector3.zero
	b.root.CFrame = CFrame.new(to.X, K.standY(b), to.Z) * b.root.CFrame.Rotation
end

-- Its minions alive (the dead dropped from its list).
local function minionCount(b: any): number
	for i = #b.minions, 1, -1 do
		local m = b.minions[i]
		local h = m:FindFirstChildOfClass("Humanoid")
		if not m.Parent or not h or h.Health <= 0 then table.remove(b.minions, i) end
	end
	return #b.minions
end

-- Up to `n` of a MobKinds kind beside it (never more than 6 at once). They
-- die with it (BossAI).
local MAX_MINIONS = 6
local function summon(b: any, kindId: string, at: Vector3, name: string, tint: Color3?)
	if minionCount(b) >= MAX_MINIONS then return end
	local MobManager = require(script.Parent:WaitForChild("MobManager")) :: any
	local m = MobManager.Spawn({
		kind = kindId,
		cf = CFrame.new(at.X, b.floorY, at.Z),
		runId = b.runId,
		name = name,
		healthMult = 0.6,
		xpMult = 0.3,
		attrs = { AggroRange = 140, IslandEnemy = "boss_minion" },
	})
	if not m then return end
	table.insert(b.minions, m)
	if tint then
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Material ~= Enum.Material.Neon and d.Transparency < 1 then d.Color = d.Color:Lerp(tint, 0.6) end
		end
	end
end

-- ── Bodies ──────────────────────────────────────────────────────────────────
-- A body from parts, its feet at y = 0 and facing -Z; MobManager welds the
-- parts to its root (configureMob). `h`/`w`: its root (its hull).
type Mk = (string, Vector3, CFrame, Color3, Enum.Material?, Enum.PartType?) -> BasePart
local function body(name: string, h: number, w: number): (Model, Mk)
	local m = Instance.new("Model")
	m.Name = name
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(w, h, w)
	root.CFrame = CFrame.new(0, h / 2, 0)
	root.Transparency = 1
	root.Anchored = true
	root.Parent = m
	m.PrimaryPart = root
	local function mk(n: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Name = n
		if shape then p.Shape = shape end
		p.Size = size
		p.CFrame = cf
		p.Color = color
		p.Material = material or Enum.Material.SmoothPlastic
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = m
		return p
	end
	return m, mk
end

-- `n` parts in a ring of radius `r` round `cf`'s Y axis.
local function ring(mk: Mk, cf: CFrame, r: number, n: number, size: Vector3, color: Color3, material: Enum.Material?)
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2
		mk("Ring", size, cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r), color, material)
	end
end

local function sparkles(parent: BasePart, color: Color3, rate: number)
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Speed = NumberRange.new(1.5, 4)
	e.Acceleration = Vector3.new(0, 2, 0)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rate = rate
	e.Parent = parent
end

local N = Enum.Material.Neon
local SLATE = Enum.Material.Slate
local METAL = Enum.Material.Metal
local FABRIC = Enum.Material.Fabric
local WOOD = Enum.Material.Wood
local BASALT = Enum.Material.Basalt
local BALL = Enum.PartType.Ball
local CYL = Enum.PartType.Cylinder

-- ── The Drowned Sovereign ───────────────────────────────────────────────────
local TIDE = rgb(60, 200, 225)
local DEEP = rgb(18, 52, 66)

local function buildSovereign(): Model
	local m, mk = body("DrownedSovereign", 16, 6)
	local robe, robeDark, coral, bone = rgb(28, 70, 82), rgb(16, 40, 50), rgb(255, 120, 110), rgb(205, 200, 180)
	-- a long drowned robe, wider at the hem
	for i, w in ipairs({ 7.5, 6.5, 5.6, 4.8 }) do
		mk("Robe", Vector3.new(w, 2.6, w * 0.8), CFrame.new(0, (i - 1) * 2.4 + 1.3, 0), if i % 2 == 0 then robe else robeDark, FABRIC)
	end
	mk("Chest", Vector3.new(4.8, 3.6, 3), CFrame.new(0, 10.6, 0), robeDark, SLATE)
	mk("Mantle", Vector3.new(7, 1.2, 3.6), CFrame.new(0, 12.2, 0), DEEP, SLATE)
	for _, s in ipairs({ -1, 1 }) do
		mk("Barnacles", Vector3.new(1.8, 1.8, 1.8), CFrame.new(s * 3.2, 12.6, 0), bone, SLATE, BALL)
		mk("Arm", Vector3.new(1.3, 5.4, 1.3), CFrame.new(s * 3.6, 9.8, -0.4) * CFrame.Angles(math.rad(-15), 0, math.rad(s * 8)), robe, FABRIC)
		-- seaweed hanging off it
		for k = 1, 3 do
			mk("Weed", Vector3.new(0.3, 3 + k * 0.6, 0.3), CFrame.new(s * (1.2 + k * 0.7), 8.2 - k * 0.4, 1.6), rgb(40, 110, 60), FABRIC)
		end
	end
	mk("Head", Vector3.new(2.8, 3, 2.6), CFrame.new(0, 14.2, 0), rgb(150, 175, 170), SLATE)
	mk("Beard", Vector3.new(2.4, 2.4, 1), CFrame.new(0, 12.9, -1.2), rgb(70, 120, 110), FABRIC)
	for _, s in ipairs({ -1, 1 }) do
		mk("Eye", Vector3.new(0.6, 0.4, 0.3), CFrame.new(s * 0.65, 14.5, -1.32), TIDE, N)
	end
	-- a crown of coral spikes
	for k = 0, 6 do
		local a = (k / 7) * math.pi * 2
		mk("Coral", Vector3.new(0.5, 1.6 + (k % 2) * 0.8, 0.5), CFrame.new(math.sin(a) * 1.3, 16.3, -math.cos(a) * 1.2) * CFrame.Angles(0, 0, math.rad(math.sin(a) * 12)), coral, N)
	end
	-- the trident in its right hand
	local shaft = CFrame.new(4.2, 9, -1.8)
	mk("Shaft", Vector3.new(0.5, 15, 0.5), shaft, rgb(70, 90, 95), METAL)
	mk("Guard", Vector3.new(3.4, 0.5, 0.5), shaft * CFrame.new(0, 6.8, 0), rgb(70, 90, 95), METAL)
	for _, x in ipairs({ -1.5, 0, 1.5 }) do
		mk("Prong", Vector3.new(0.4, if x == 0 then 3.4 else 2.6, 0.4), shaft * CFrame.new(x, if x == 0 then 8.6 else 8.2, 0), TIDE, N)
	end
	local core = mk("Pearl", Vector3.one * 1.2, CFrame.new(0, 10.8, -1.6), TIDE, N, BALL)
	sparkles(core, TIDE, 6)
	return m
end

local sovereign: { [string]: (any, any) -> () } = {}

sovereign.trident_sweep = function(b, target)
	local sweeps = if b.enraged then 2 else 1
	for _ = 1, sweeps do
		local v = K.nearestVictim(b) or target
		local origin = b.root.Position
		local dir = flatDir(origin, v.root.Position)
		local r, half = (if b.enraged then 30 else 25), math.rad(if b.enraged then 75 else 60)
		K.face(b, origin + dir)
		K.telegraphCone(origin, dir, r, half, 0.9, b.floorY)
		if not K.hold(b, 0.9) then return end
		local base = math.atan2(dir.Z, dir.X)
		for i = 0, 6 do
			local a = base - half + i * (2 * half / 6)
			column(origin + angleDir(a) * r * 0.65, b.floorY, 3, 7, TIDE, 0.45)
		end
		blastWhere(b, function(p) return inCone(origin, dir, r, half, p) end, K.dmg(b, 1.4), origin)
		K.shock(origin, r * 0.6, TIDE, b.floorY)
		if not K.hold(b, 0.35) then return end
	end
	K.hold(b, 0.45)
end

sovereign.tidal_wave = function(b, _target)
	K.telegraphCircle(b.root.Position, 6, 0.75, b.floorY)
	if not K.hold(b, 0.75) then return end
	for _ = 1, (if b.enraged then 3 else 2) do
		column(b.root.Position, b.floorY, 10, 10, TIDE, 0.5)
		K.MOVES.shockwaveOnce(b, nil)
		if not K.hold(b, 0.85) then return end
	end
	K.hold(b, 0.6)
end

sovereign.geysers = function(b, _target)
	for _ = 1, (if b.enraged then 3 else 2) do
		local spots = {}
		for _, v in ipairs(inArena(b)) do
			table.insert(spots, v.root.Position)
			if b.enraged then table.insert(spots, v.root.Position + angleDir(math.random() * math.pi * 2) * math.random(6, 10)) end
		end
		if #spots == 0 then break end
		for _, s in ipairs(spots) do
			K.telegraphCircle(s, 7, 1.3, b.floorY)
			disc(s, b.floorY, 2, TIDE, 0.3, 1.3)
		end
		if not K.hold(b, 1.3) then return end
		for _, s in ipairs(spots) do
			column(s, b.floorY, 9, 34, TIDE, 0.7)
			K.blast(s, 7, K.dmg(b, 1.1))
		end
		if not K.hold(b, 0.45) then return end
	end
	K.hold(b, 0.5)
end

-- Signature: the arena floods; only the glowing rings stay dry.
sovereign.drowning_tide = function(b, _target)
	toCenter(b)
	if not K.hold(b, 0.5) then return end
	for _ = 1, (if b.enraged then 3 else 2) do
		local people = #inArena(b)
		local safe = {}
		for i = 1, math.max(3, people + 1) do
			local a = (i / math.max(3, people + 1)) * math.pi * 2 + math.random() * 0.8
			table.insert(safe, b.home + angleDir(a) * (20 + math.random() * 26))
		end
		local marks = {}
		for _, s in ipairs(safe) do
			table.insert(marks, disc(s, b.floorY + 0.05, 7, rgb(120, 255, 170), 0.35))
		end
		K.telegraphCircle(b.home, ARENA, 3, b.floorY)
		local water = disc(b.home, b.floorY - 1.5, ARENA, TIDE, 0.55)
		water.Material = Enum.Material.Glass
		TweenService:Create(water, TweenInfo.new(3, Enum.EasingStyle.Sine), { CFrame = water.CFrame + Vector3.new(0, 2.2, 0) }):Play()
		local ok = K.hold(b, 3)
		if ok then
			blastWhere(b, function(p)
				if K.flatDist(p, b.home) > ARENA + 4 then return false end
				for _, s in ipairs(safe) do
					if K.flatDist(p, s) <= 7.5 then return false end
				end
				return true
			end, K.dmg(b, 2.2), nil)
			for _ = 1, 6 do column(arenaPoint(b, 8, ARENA), b.floorY, 6, 18, TIDE, 0.6) end
		end
		water:Destroy()
		for _, d in ipairs(marks) do d:Destroy() end
		if not ok or not K.hold(b, 0.6) then return end
	end
	K.hold(b, 0.4)
end

-- ── The Ashen Colossus ──────────────────────────────────────────────────────
local MAGMA = rgb(255, 120, 40)

local function buildColossus(): Model
	local m, mk = body("AshenColossus", 18, 9)
	local stone, stone2 = rgb(48, 42, 40), rgb(70, 60, 56)
	for _, s in ipairs({ -1, 1 }) do
		mk("Leg", Vector3.new(3.2, 6.5, 3.4), CFrame.new(s * 2.4, 3.25, 0), stone, BASALT)
		mk("Foot", Vector3.new(3.8, 1.2, 4.6), CFrame.new(s * 2.4, 0.6, -0.5), stone2, BASALT)
		mk("Arm", Vector3.new(3, 8, 3), CFrame.new(s * 6.6, 10.5, 0) * CFrame.Angles(0, 0, math.rad(s * 6)), stone, BASALT)
		mk("Fist", Vector3.new(4, 3.6, 4), CFrame.new(s * 7.1, 5.8, -0.3), stone2, BASALT)
		mk("Shoulder", Vector3.new(4.6, 3.4, 4.4), CFrame.new(s * 5.8, 15, 0), stone2, BASALT)
		mk("ArmVein", Vector3.new(0.4, 6.5, 0.4), CFrame.new(s * 6.7, 10.5, -1.55), MAGMA, N)
	end
	mk("Hips", Vector3.new(7.5, 2.4, 4.6), CFrame.new(0, 7.4, 0), stone2, BASALT)
	mk("Torso", Vector3.new(9, 7.5, 5.4), CFrame.new(0, 12.2, 0), stone, BASALT)
	mk("Core", Vector3.new(2.6, 2.6, 0.6), CFrame.new(0, 12.6, -2.75), MAGMA, N)
	-- the cracks in it, glowing
	for k, cf in ipairs({ CFrame.new(-2, 13.8, -2.72) * CFrame.Angles(0, 0, 0.5), CFrame.new(2.4, 11, -2.72) * CFrame.Angles(0, 0, -0.7),
		CFrame.new(-1.4, 9.8, -2.72) * CFrame.Angles(0, 0, 1.2), CFrame.new(3, 14.5, -2.72) * CFrame.Angles(0, 0, 0.2) }) do
		mk("Crack", Vector3.new(0.35, 2.2 + k * 0.3, 0.2), cf, MAGMA, N)
	end
	mk("Head", Vector3.new(3.4, 3, 3.2), CFrame.new(0, 16.9, -0.6), stone2, BASALT)
	mk("Brow", Vector3.new(3.8, 0.8, 1), CFrame.new(0, 17.6, -2.1), stone, BASALT)
	for _, s in ipairs({ -1, 1 }) do
		mk("Eye", Vector3.new(0.8, 0.4, 0.3), CFrame.new(s * 0.8, 17, -2.25), MAGMA, N)
	end
	-- smoking ash off its shoulders
	local smoke = Instance.new("Smoke")
	smoke.Color = rgb(60, 55, 52)
	smoke.Opacity = 0.12
	smoke.RiseVelocity = 4
	smoke.Size = 3
	smoke.Parent = m:FindFirstChild("Head")
	sparkles(m:FindFirstChild("Core") :: BasePart, MAGMA, 8)
	return m
end

local colossus: { [string]: (any, any) -> () } = {}

-- A burning patch that hurts whoever stands in it for `life` seconds.
local function lava(b: any, at: Vector3, r: number, life: number)
	local d = disc(at, b.floorY, r, MAGMA, 0.3)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < life and d.Parent do
			task.wait(0.5)
			K.blast(at, r, K.dmg(b, 0.18))
		end
		TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		Debris:AddItem(d, 0.45)
	end)
end

colossus.ground_slam = function(b, target)
	local r = if b.enraged then 30 else 24
	local spot = b.root.Position
	K.face(b, target.root.Position)
	-- (the red disc grows out from under it: the zone it'll hit)
	K.telegraphCircle(spot, r, 1.5, b.floorY)
	local start = b.root.CFrame
	b.root.CFrame = start + Vector3.new(0, 5, 0)
	if not K.hold(b, 1.5) then return end
	b.root.CFrame = start
	K.blast(spot, r, K.dmg(b, 1.6))
	K.shock(spot, r, MAGMA, b.floorY)
	for k = 1, 8 do
		local a = k / 8 * math.pi * 2
		local rock = K.part({ Size = Vector3.one * 2.2, CFrame = CFrame.new(spot + Vector3.new(0, 2, 0)), Color = rgb(60, 50, 46), Material = BASALT })
		TweenService:Create(rock, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(spot + angleDir(a) * r * 0.8 + Vector3.new(0, 0.5, 0)) * CFrame.Angles(a, a, 0), Transparency = 1 }):Play()
		Debris:AddItem(rock, 0.65)
	end
	if b.enraged then
		if not K.hold(b, 0.4) then return end
		telegraphRing(spot, r, r + 12, 0.8, b.floorY)
		if not K.hold(b, 0.8) then return end
		blastWhere(b, function(p) local d = K.flatDist(p, spot) return d > r and d <= r + 12 end, K.dmg(b, 1.1), spot)
		K.shock(spot, r + 12, MAGMA, b.floorY)
	end
	K.hold(b, 0.6)
end

colossus.volcanic_debris = function(b, _target)
	local count = if b.enraged then 14 else 9
	for _ = 1, count do
		local vs = inArena(b)
		if #vs == 0 then break end
		local v = vs[math.random(1, #vs)]
		local spot = v.root.Position + angleDir(math.random() * math.pi * 2) * math.random(0, 7)
		K.telegraphCircle(spot, 6, 1.1, b.floorY)
		task.delay(0.6, function()
			local rock = K.part({ Shape = BALL, Size = Vector3.one * 4, CFrame = CFrame.new(spot.X, b.floorY + 50, spot.Z),
				Color = rgb(70, 40, 30), Material = BASALT })
			local fire = Instance.new("Fire")
			fire.Color, fire.SecondaryColor, fire.Size = MAGMA, rgb(60, 20, 10), 7
			fire.Parent = rock
			TweenService:Create(rock, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(spot.X, b.floorY + 1.5, spot.Z) }):Play()
			task.delay(0.5, function()
				rock:Destroy()
				K.shock(spot, 6, MAGMA, b.floorY)
				K.blast(spot, 6, K.dmg(b, 1))
				lava(b, spot, 3.5, 3)
			end)
		end)
		if not K.hold(b, if b.enraged then 0.18 else 0.26) then return end
	end
	K.hold(b, 1.1)
end

colossus.frontal_eruption = function(b, target)
	local origin = b.root.Position
	local dir = flatDir(origin, target.root.Position)
	local len, width = 72, if b.enraged then 16 else 12
	K.face(b, origin + dir)
	K.telegraphLine(origin, dir, len, width, 1.6, b.floorY)
	local glow = K.part({ Shape = BALL, Size = Vector3.one * 1, CFrame = CFrame.new(origin + Vector3.new(0, 12.6, 0) + dir * 3), Color = MAGMA })
	TweenService:Create(glow, TweenInfo.new(1.6), { Size = Vector3.one * 6 }):Play()
	Debris:AddItem(glow, 1.7)
	if not K.hold(b, 1.6) then return end
	glow:Destroy()
	local hit = {}
	for s = 1, 10 do
		local pos = origin + dir * (s * 7)
		column(pos, b.floorY, width * 0.7, 16, MAGMA, 0.5)
		blastWhere(b, function(p) return K.flatDist(p, pos) <= width * 0.6 end, K.dmg(b, 1.5), pos, hit)
		task.wait(0.05)
	end
	for s = 2, 9, 3 do lava(b, origin + dir * (s * 7), 4, 3.5) end
	K.hold(b, 0.7)
end

-- Signature: the arena erupts in rings, the middle first, then outward;
-- step into what's already burst and cooled.
colossus.cataclysm = function(b, _target)
	toCenter(b)
	if not K.hold(b, 0.4) then return end
	local zones = { { 0, 20 }, { 20, 40 }, { 40, ARENA + 6 } }
	local orders = { { 1, 2, 3 } }
	if b.enraged then table.insert(orders, { 3, 2, 1 }) end
	for _, order in ipairs(orders) do
		for step, zi in ipairs(order) do
			local z = zones[zi]
			local inner, outer = z[1], z[2]
			task.delay((step - 1) * 1.25, function()
				if not K.alive(b) then return end
				if inner == 0 then K.telegraphCircle(b.home, outer, 1.6, b.floorY) else telegraphRing(b.home, inner, outer, 1.6, b.floorY) end
				task.wait(1.6)
				if not K.alive(b) then return end
				blastWhere(b, function(p) local d = K.flatDist(p, b.home) return d >= inner and d <= outer end, K.dmg(b, 2), b.home)
				for k = 1, 8 do
					local a = k / 8 * math.pi * 2 + math.random()
					column(b.home + angleDir(a) * (inner + outer) / 2, b.floorY, 5, 18, MAGMA, 0.55)
				end
			end)
		end
		if not K.hold(b, 1.25 * 2 + 1.9) then return end
	end
	K.hold(b, 0.5)
end

-- ── The Hollow Saint ────────────────────────────────────────────────────────
local HOLY = rgb(255, 228, 150)

local function buildSaint(): Model
	local m, mk = body("HollowSaint", 15, 5)
	local robe, robe2, trim = rgb(205, 200, 190), rgb(160, 156, 150), rgb(210, 175, 90)
	-- it floats: a robe that thins to nothing at the bottom
	for i, w in ipairs({ 2.2, 3.4, 4.4, 5 }) do
		mk("Robe", Vector3.new(w, 2.4, w * 0.75), CFrame.new(0, 1.6 + (i - 1) * 2.2, 0), if i % 2 == 0 then robe else robe2, FABRIC)
	end
	mk("Sash", Vector3.new(5.2, 0.6, 3.9), CFrame.new(0, 9.4, 0), trim, METAL)
	mk("Chest", Vector3.new(4.4, 3.2, 2.8), CFrame.new(0, 11.2, 0), robe, FABRIC)
	mk("Hood", Vector3.new(3.4, 3.6, 3.2), CFrame.new(0, 13.6, 0.1), robe2, FABRIC)
	mk("Hollow", Vector3.new(2.2, 2.6, 0.4), CFrame.new(0, 13.4, -1.5), rgb(5, 5, 8), Enum.Material.SmoothPlastic)
	for _, s in ipairs({ -1, 1 }) do
		mk("Eye", Vector3.new(0.35, 0.35, 0.2), CFrame.new(s * 0.5, 13.7, -1.72), HOLY, N)
		mk("Sleeve", Vector3.new(1.4, 4.6, 1.4), CFrame.new(s * 3, 10.4, -0.6) * CFrame.Angles(math.rad(-30), 0, math.rad(s * 10)), robe2, FABRIC)
		-- tattered wings of light
		for k = 1, 3 do
			mk("Wing", Vector3.new(0.2, 1.2, 4.5 - k * 0.8), CFrame.new(s * (2.2 + k * 1.2), 12.4 - k * 0.7, 1.8) * CFrame.Angles(0, math.rad(s * 70), math.rad(s * (15 + k * 10))), HOLY, N)
		end
	end
	-- the halo
	ring(mk, CFrame.new(0, 15.6, 0.9) * CFrame.Angles(math.rad(80), 0, 0), 2.1, 12, Vector3.new(1.1, 0.25, 0.4), HOLY, N)
	-- a staff with a lantern
	local staff = CFrame.new(-3.4, 8.5, -1.6)
	mk("Staff", Vector3.new(0.4, 13, 0.4), staff, rgb(120, 100, 70), WOOD)
	local lantern = mk("Lantern", Vector3.new(1.2, 1.6, 1.2), staff * CFrame.new(0, 7.2, 0), HOLY, N)
	sparkles(lantern, HOLY, 7)
	return m
end

local saint: { [string]: (any, any) -> () } = {}

saint.consecrate = function(b, _target)
	local spots = {}
	for _, v in ipairs(inArena(b)) do
		table.insert(spots, v.root.Position)
		for _ = 1, (if b.enraged then 2 else 1) do
			table.insert(spots, v.root.Position + angleDir(math.random() * math.pi * 2) * math.random(9, 15))
		end
	end
	while #spots > 9 do table.remove(spots) end
	for _, s in ipairs(spots) do K.telegraphCircle(s, 8, 1, b.floorY) end
	if not K.hold(b, 1) then return end
	for _, s in ipairs(spots) do
		local d = disc(s, b.floorY, 8, HOLY, 0.45)
		column(s, b.floorY, 6, 20, HOLY, 0.5)
		task.spawn(function()
			for _ = 1, 12 do
				task.wait(0.5)
				if not d.Parent then break end
				K.blast(s, 8, K.dmg(b, 0.25))
			end
			TweenService:Create(d, TweenInfo.new(0.4), { Transparency = 1 }):Play()
			Debris:AddItem(d, 0.45)
		end)
	end
	K.hold(b, 0.6)
end

saint.spectral_host = function(b, _target)
	local n = if b.enraged then 4 else 3
	if minionCount(b) >= MAX_MINIONS then
		saint.cross_blast(b, K.nearestVictim(b) or _target)
		return
	end
	for i = 1, n do
		local pos = b.root.Position + angleDir(i / n * math.pi * 2) * 9
		K.telegraphCircle(pos, 3, 0.9, b.floorY)
		task.delay(0.9, function()
			if not K.alive(b) then return end
			column(pos, b.floorY, 3, 12, HOLY, 0.5)
			summon(b, "wraith", pos, "Spectral Acolyte", rgb(220, 220, 255))
		end)
	end
	K.hold(b, 1.3)
end

saint.cross_blast = function(b, target)
	local center = target.root.Position
	local dirs = { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1) }
	if b.enraged then
		table.insert(dirs, Vector3.new(1, 0, 1).Unit)
		table.insert(dirs, Vector3.new(1, 0, -1).Unit)
	end
	local len, width = 96, 8
	for _, d in ipairs(dirs) do K.telegraphLine(center - d * len / 2, d, len, width, 1.3, b.floorY) end
	if not K.hold(b, 1.3) then return end
	local hit = {}
	for _, d in ipairs(dirs) do
		local from = center - d * len / 2
		local beam = K.part({ Size = Vector3.new(width, 3, len), Color = HOLY, Transparency = 0.2,
			CFrame = CFrame.lookAt(Vector3.new(center.X, b.floorY + 1.5, center.Z), Vector3.new(center.X + d.X, b.floorY + 1.5, center.Z + d.Z)) })
		TweenService:Create(beam, TweenInfo.new(0.45), { Size = Vector3.new(0.4, 6, len), Transparency = 1 }):Play()
		Debris:AddItem(beam, 0.5)
		blastWhere(b, function(p) return nearLine(from, d, len, width / 2, p) end, K.dmg(b, 1.5), nil, hit)
	end
	K.hold(b, 0.6)
end

-- Signature: beams of light turn round her; keep ahead of them.
saint.litany = function(b, _target)
	toCenter(b)
	local arms = if b.enraged then 6 else 4
	local len, width = ARENA, 5
	local base = math.random() * math.pi * 2
	for i = 0, arms - 1 do
		K.telegraphLine(b.home, angleDir(base + i / arms * math.pi * 2), len, width, 1.3, b.floorY)
	end
	if not K.hold(b, 1.3) then return end
	local beams = {}
	for i = 1, arms do
		beams[i] = K.part({ Size = Vector3.new(width, 2.5, len), Color = HOLY, Transparency = 0.25 })
	end
	local speed = if b.enraged then 1.0 else 0.7
	local spin = if math.random() < 0.5 then 1 else -1
	local last: { [Model]: number } = {}
	local t0 = os.clock()
	local dur = 5.5
	local lastCheck = 0
	while os.clock() - t0 < dur and K.alive(b) do
		RunService.Heartbeat:Wait()
		local t = os.clock() - t0
		local a0 = base + spin * speed * t
		for i, beam in ipairs(beams) do
			local d = angleDir(a0 + (i - 1) / arms * math.pi * 2)
			local mid = b.home + d * len / 2
			beam.CFrame = CFrame.lookAt(Vector3.new(mid.X, b.floorY + 1.3, mid.Z), Vector3.new(mid.X + d.X, b.floorY + 1.3, mid.Z + d.Z))
		end
		if t - lastCheck >= 0.1 then
			lastCheck = t
			for _, v in ipairs(inArena(b)) do
				if (last[v.char] or 0) + 0.6 <= t then
					for i = 1, arms do
						if nearLine(b.home, angleDir(a0 + (i - 1) / arms * math.pi * 2), len, width / 2 + 0.5, v.root.Position) then
							last[v.char] = t
							K.hurt(v.char, K.dmg(b, 0.8), b.home)
							break
						end
					end
				end
			end
		end
	end
	for _, beam in ipairs(beams) do beam:Destroy() end
	K.hold(b, 0.5)
end

-- ── The Thorn Matriarch ─────────────────────────────────────────────────────
local THORN = rgb(120, 205, 70)
local BLOOM = rgb(255, 110, 190)
local BARK = rgb(70, 48, 34)

local function buildMatriarch(): Model
	local m, mk = body("ThornMatriarch", 15, 6)
	local bark2, leaf = rgb(96, 68, 46), rgb(56, 110, 48)
	-- a skirt of roots
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		mk("Root", Vector3.new(1, 1, 5), CFrame.new(math.cos(a) * 3, 0.6, math.sin(a) * 3) * CFrame.Angles(0, -a + math.pi / 2, 0) * CFrame.Angles(math.rad(-20), 0, 0), BARK, WOOD)
	end
	mk("Trunk", Vector3.new(4, 7, 3.4), CFrame.new(0, 4.5, 0), BARK, WOOD)
	mk("Bodice", Vector3.new(4.6, 4, 3.2), CFrame.new(0, 9.5, 0), bark2, WOOD)
	mk("Leaves", Vector3.new(5.4, 1.6, 3.8), CFrame.new(0, 11.4, 0), leaf, Enum.Material.Grass)
	mk("Head", Vector3.new(2.6, 2.8, 2.4), CFrame.new(0, 13.2, 0), bark2, WOOD)
	for _, s in ipairs({ -1, 1 }) do
		mk("Eye", Vector3.new(0.5, 0.35, 0.2), CFrame.new(s * 0.55, 13.4, -1.22), THORN, N)
		-- long vine arms with thorns
		local arm = CFrame.new(s * 3.4, 9.2, -0.8) * CFrame.Angles(math.rad(-25), 0, math.rad(s * 18))
		mk("Vine", Vector3.new(1, 6.5, 1), arm, leaf, Enum.Material.Grass)
		for k = 1, 3 do
			mk("Thorn", Vector3.new(0.25, 1, 0.25), arm * CFrame.new(s * 0.6, -3 + k * 1.6, 0) * CFrame.Angles(0, 0, math.rad(s * -60)), rgb(220, 210, 170), WOOD)
		end
		mk("Claw", Vector3.new(1.6, 1.6, 1.6), arm * CFrame.new(0, -3.6, 0), THORN, N, BALL)
	end
	-- thorns off its back
	for k = 1, 6 do
		mk("Spine", Vector3.new(0.4, 2.2, 0.4), CFrame.new((k % 3 - 1) * 1.3, 6 + k * 1.1, 1.8) * CFrame.Angles(math.rad(50), 0, 0), rgb(220, 210, 170), WOOD)
	end
	-- a crown of flowers
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2
		mk("Petal", Vector3.new(0.9, 0.5, 0.9), CFrame.new(math.sin(a) * 1.4, 14.8, -math.cos(a) * 1.3) * CFrame.Angles(0, a, math.rad(30)), BLOOM, N)
	end
	local heart = mk("Heart", Vector3.one * 1.2, CFrame.new(0, 9.6, -1.6), BLOOM, N, BALL)
	sparkles(heart, THORN, 6)
	return m
end

local matriarch: { [string]: (any, any) -> () } = {}

-- A thorn springing out of the floor and sinking back.
local function spike(at: Vector3, floorY: number, h: number)
	local p = K.part({ Size = Vector3.new(1.6, h, 1.6), Color = rgb(150, 190, 90), Material = WOOD,
		CFrame = CFrame.new(at.X, floorY - h / 2, at.Z) * CFrame.Angles(math.rad(math.random(-15, 15)), math.random() * 6, 0) }, "WedgePart")
	TweenService:Create(p, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = p.CFrame + Vector3.new(0, h * 0.95, 0) }):Play()
	task.delay(0.7, function()
		if p.Parent then TweenService:Create(p, TweenInfo.new(0.35), { CFrame = p.CFrame - Vector3.new(0, h, 0), Transparency = 1 }):Play() end
	end)
	Debris:AddItem(p, 1.1)
end

matriarch.root_snare = function(b, _target)
	local spots = {}
	for _, v in ipairs(inArena(b)) do
		table.insert(spots, v.root.Position)
		if b.enraged then table.insert(spots, v.root.Position + angleDir(math.random() * math.pi * 2) * 7) end
	end
	for _, s in ipairs(spots) do K.telegraphCircle(s, 5, 1, b.floorY) end
	if not K.hold(b, 1) then return end
	local now = Workspace:GetServerTimeNow()
	for _, s in ipairs(spots) do
		for k = 1, 5 do spike(s + angleDir(k / 5 * math.pi * 2) * 2.4, b.floorY, 5) end
		for _, v in ipairs(K.victims()) do
			if K.flatDist(v.root.Position, s) <= 5 then
				K.hurt(v.char, K.dmg(b, 0.8), nil)
				-- held by the roots: barely able to move for a moment
				v.char:SetAttribute("IceSlow", 0.2)
				v.char:SetAttribute("IceSlowUntil", now + 1.8)
			end
		end
	end
	K.hold(b, 0.6)
end

matriarch.thorn_lines = function(b, target)
	local origin = b.root.Position
	local n = if b.enraged then 9 else 6
	local base = math.atan2(target.root.Position.Z - origin.Z, target.root.Position.X - origin.X)
	local dirs = {}
	for i = 0, n - 1 do dirs[i + 1] = angleDir(base + i / n * math.pi * 2) end
	for _, d in ipairs(dirs) do K.telegraphLine(origin, d, 54, 5, 1, b.floorY) end
	if not K.hold(b, 1) then return end
	local hit = {}
	for step = 1, 9 do
		for _, d in ipairs(dirs) do
			local pos = origin + d * (step * 6)
			spike(pos, b.floorY, 6)
			blastWhere(b, function(p) return K.flatDist(p, pos) <= 3.4 end, K.dmg(b, 1.1), pos, hit)
		end
		task.wait(0.05)
	end
	K.hold(b, 0.6)
end

matriarch.thornlings = function(b, target)
	if minionCount(b) >= MAX_MINIONS then
		matriarch.thorn_lines(b, target)
		return
	end
	local n = if b.enraged then 4 else 3
	for i = 1, n do
		local pos = b.root.Position + angleDir(i / n * math.pi * 2 + 0.4) * 10
		K.telegraphCircle(pos, 3, 0.9, b.floorY)
		task.delay(0.9, function()
			if not K.alive(b) then return end
			for k = 1, 3 do spike(pos + angleDir(k * 2.1) * 1.5, b.floorY, 3) end
			summon(b, "slime", pos, "Thornling", THORN)
		end)
	end
	K.hold(b, 1.2)
end

-- Signature: all but two slices of the arena burst with thorns.
matriarch.overgrowth = function(b, _target)
	toCenter(b)
	local slices = 8
	local step = math.pi * 2 / slices
	for _ = 1, (if b.enraged then 3 else 2) do
		local base = math.random() * math.pi * 2
		local s1 = math.random(0, slices - 1)
		local s2 = (s1 + math.random(2, slices - 2)) % slices
		local marks = {}
		for k = 0, slices - 1 do
			local d = angleDir(base + (k + 0.5) * step)
			if k == s1 or k == s2 then
				for f = 1, 3 do
					table.insert(marks, disc(b.home + d * (f * 16), b.floorY + 0.05, 3.5, BLOOM, 0.3))
				end
			else
				K.telegraphCone(b.home, d, ARENA, step / 2, 1.7, b.floorY)
			end
		end
		local ok = K.hold(b, 1.7)
		for _, m in ipairs(marks) do m:Destroy() end
		if not ok then return end
		blastWhere(b, function(p)
			if K.flatDist(p, b.home) > ARENA + 4 then return false end
			local a = (math.atan2(p.Z - b.home.Z, p.X - b.home.X) - base) % (math.pi * 2)
			local k = math.floor(a / step)
			return k ~= s1 and k ~= s2
		end, K.dmg(b, 1.9), b.home)
		for k = 0, slices - 1 do
			if k ~= s1 and k ~= s2 then
				for f = 1, 3 do spike(b.home + angleDir(base + (k + 0.5) * step) * (f * 16), b.floorY, 9) end
			end
		end
		if not K.hold(b, 0.7) then return end
	end
	K.hold(b, 0.4)
end

-- ── The Riftbound Knight ────────────────────────────────────────────────────
local RIFT = rgb(170, 90, 255)

local function buildKnight(): Model
	local m, mk = body("RiftboundKnight", 14, 5)
	local steel, steel2 = rgb(40, 38, 48), rgb(70, 66, 82)
	for _, s in ipairs({ -1, 1 }) do
		mk("Greave", Vector3.new(1.8, 5.6, 2), CFrame.new(s * 1.3, 2.8, 0), steel, METAL)
		mk("Knee", Vector3.new(1.9, 1, 1), CFrame.new(s * 1.3, 4.2, -1.1), steel2, METAL)
		mk("Pauldron", Vector3.new(2.8, 1.6, 3), CFrame.new(s * 3, 11.4, 0) * CFrame.Angles(0, 0, math.rad(s * -15)), steel2, METAL)
		mk("Arm", Vector3.new(1.4, 4.8, 1.5), CFrame.new(s * 3.1, 8.6, 0), steel, METAL)
		mk("Rim", Vector3.new(2.9, 0.3, 3.1), CFrame.new(s * 3, 10.7, 0) * CFrame.Angles(0, 0, math.rad(s * -15)), RIFT, N)
	end
	mk("Tasset", Vector3.new(4.4, 2, 2.6), CFrame.new(0, 6.2, 0), steel2, METAL)
	mk("Cuirass", Vector3.new(4.6, 4.6, 2.8), CFrame.new(0, 9.4, 0), steel, METAL)
	mk("Rift", Vector3.new(0.5, 3.4, 0.2), CFrame.new(0.3, 9.4, -1.42) * CFrame.Angles(0, 0, math.rad(20)), RIFT, N)
	mk("Helm", Vector3.new(2.4, 2.8, 2.6), CFrame.new(0, 12.6, 0), steel2, METAL)
	mk("Visor", Vector3.new(1.8, 0.3, 0.2), CFrame.new(0, 12.8, -1.32), RIFT, N)
	mk("Crest", Vector3.new(0.3, 1.6, 2.6), CFrame.new(0, 14.4, 0.2), RIFT, N)
	mk("Cape", Vector3.new(4.2, 9, 0.3), CFrame.new(0, 7, 1.6) * CFrame.Angles(math.rad(6), 0, 0), rgb(46, 22, 70), FABRIC)
	-- the rift blade in its right hand
	local hilt = CFrame.new(3.4, 6.5, -1.5) * CFrame.Angles(math.rad(-70), 0, 0)
	mk("Hilt", Vector3.new(0.5, 2, 0.5), hilt, steel2, METAL)
	mk("Crossguard", Vector3.new(2.4, 0.4, 0.5), hilt * CFrame.new(0, 1.1, 0), steel2, METAL)
	local blade = mk("Blade", Vector3.new(0.9, 9, 0.25), hilt * CFrame.new(0, 5.8, 0), RIFT, N)
	sparkles(blade, RIFT, 6)
	return m
end

local knight: { [string]: (any, any) -> () } = {}

-- An upright rift (a ring of light) at `at`, for `life` seconds.
local function rift(at: Vector3, floorY: number, size: number, life: number): BasePart
	local p = K.part({ Shape = CYL, Size = Vector3.new(0.3, size, size * 0.65), Color = RIFT, Transparency = 0.25,
		CFrame = CFrame.new(at.X, floorY + size * 0.5, at.Z) * CFrame.Angles(0, math.random() * 6, 0) })
	local inner = K.part({ Shape = CYL, Size = Vector3.new(0.35, size * 0.8, size * 0.5), Color = rgb(20, 0, 40), Transparency = 0.1,
		CFrame = p.CFrame })
	Debris:AddItem(p, life)
	Debris:AddItem(inner, life)
	return p
end

knight.rift_strike = function(b, target)
	for _ = 1, (if b.enraged then 3 else 2) do
		local v = K.nearestVictim(b) or target
		local spot = v.root.Position
		K.telegraphCircle(spot, 9, 0.9, b.floorY)
		rift(spot, b.floorY, 7, 1.1)
		rift(b.root.Position, b.floorY, 9, 0.9)
		if not K.hold(b, 0.9) then return end
		teleport(b, spot)
		K.face(b, v.root.Position)
		K.blast(spot, 9, K.dmg(b, 1.3))
		K.shock(spot, 9, RIFT, b.floorY)
		column(spot, b.floorY, 4, 14, RIFT, 0.4)
		if not K.hold(b, 0.45) then return end
	end
	K.hold(b, 0.4)
end

knight.rift_slash = function(b, target)
	local origin = b.root.Position
	local base = math.atan2(target.root.Position.Z - origin.Z, target.root.Position.X - origin.X)
	local n = if b.enraged then 5 else 3
	local dirs = {}
	for i = 1, n do dirs[i] = angleDir(base + (i - (n + 1) / 2) * math.rad(18)) end
	local len = 70
	K.face(b, target.root.Position)
	for _, d in ipairs(dirs) do K.telegraphLine(origin, d, len, 6, 0.8, b.floorY) end
	if not K.hold(b, 0.8) then return end
	for _, d in ipairs(dirs) do
		task.spawn(function()
			local slash = K.part({ Size = Vector3.new(8, 3.5, 1.2), Color = RIFT, Transparency = 0.15 })
			local hit = {}
			local t0 = os.clock()
			while os.clock() - t0 < 0.6 do
				RunService.Heartbeat:Wait()
				local pos = origin + d * len * math.min(1, (os.clock() - t0) / 0.6)
				slash.CFrame = CFrame.lookAt(Vector3.new(pos.X, b.floorY + 1.8, pos.Z), Vector3.new(pos.X + d.X, b.floorY + 1.8, pos.Z + d.Z))
				blastWhere(b, function(p) return K.flatDist(p, pos) <= 4.2 end, K.dmg(b, 1.2), pos, hit)
			end
			slash:Destroy()
		end)
	end
	K.hold(b, 0.9)
end

knight.rift_tear = function(b, target)
	if minionCount(b) >= MAX_MINIONS then
		knight.rift_slash(b, target)
		return
	end
	local n = if b.enraged then 3 else 2
	for _ = 1, n do
		local at = arenaPoint(b, 15, 45)
		K.telegraphCircle(at, 4, 1, b.floorY)
		task.delay(1, function()
			if not K.alive(b) then return end
			rift(at, b.floorY, 9, 8)
			for k = 0, 2 do
				task.delay(k * 3, function()
					if K.alive(b) then summon(b, if k % 2 == 0 then "wraith" else "ghoul", at, "Riftspawn", RIFT) end
				end)
			end
		end)
	end
	K.hold(b, 1.2)
end

-- Signature: slashes across the whole arena, one after another.
knight.dimension_rend = function(b, _target)
	toCenter(b)
	local count = if b.enraged then 9 else 6
	local len, width = ARENA * 2 + 10, 8
	for _ = 1, count do
		local a = math.random() * math.pi
		local d = angleDir(a)
		local perp = Vector3.new(-d.Z, 0, d.X)
		local from = b.home + perp * math.random(-20, 20) - d * len / 2
		K.telegraphLine(from, d, len, width, 1.1, b.floorY)
		task.delay(1.1, function()
			if not K.alive(b) then return end
			local mid = from + d * len / 2
			local cut = K.part({ Size = Vector3.new(width, 4, len), Color = RIFT, Transparency = 0.15,
				CFrame = CFrame.lookAt(Vector3.new(mid.X, b.floorY + 2, mid.Z), Vector3.new(mid.X + d.X, b.floorY + 2, mid.Z + d.Z)) })
			TweenService:Create(cut, TweenInfo.new(0.4), { Size = Vector3.new(0.3, 8, len), Transparency = 1 }):Play()
			Debris:AddItem(cut, 0.45)
			blastWhere(b, function(p) return nearLine(from, d, len, width / 2, p) end, K.dmg(b, 1.5), nil)
		end)
		if not K.hold(b, 0.45) then return end
	end
	K.hold(b, 1.4)
end

-- ── The Eclipse Wyrm ────────────────────────────────────────────────────────
local CORONA = rgb(255, 175, 60)
local UMBRA = rgb(22, 16, 30)

local function buildWyrm(): Model
	local m, mk = body("EclipseWyrm", 12, 8)
	local scale2 = rgb(40, 30, 52)
	-- a long body behind it, coiling down to the tail
	for k = 0, 6 do
		local r = 3.4 - k * 0.38
		mk("Coil", Vector3.one * r * 2, CFrame.new(math.sin(k * 0.9) * 1.6, r + 0.2, 2 + k * 2.9), if k % 2 == 0 then UMBRA else scale2, SLATE, BALL)
		mk("Ridge", Vector3.new(0.4, 1.4, 1), CFrame.new(math.sin(k * 0.9) * 1.6, r * 2 + 0.6, 2 + k * 2.9), CORONA, N)
	end
	mk("Chest", Vector3.new(6, 6.5, 5.5), CFrame.new(0, 5.5, -1), UMBRA, SLATE)
	mk("Neck", Vector3.new(2.8, 5, 2.8), CFrame.new(0, 9.5, -3) * CFrame.Angles(math.rad(-25), 0, 0), scale2, SLATE)
	mk("Head", Vector3.new(3.2, 2.6, 5), CFrame.new(0, 12, -5.2), UMBRA, SLATE)
	mk("Jaw", Vector3.new(2.6, 0.9, 4), CFrame.new(0, 10.6, -5.6), scale2, SLATE)
	for _, s in ipairs({ -1, 1 }) do
		mk("Eye", Vector3.new(0.4, 0.4, 0.8), CFrame.new(s * 1.45, 12.4, -6.4), CORONA, N)
		mk("Horn", Vector3.new(0.5, 0.5, 3.4), CFrame.new(s * 1.1, 13.6, -3.4) * CFrame.Angles(math.rad(30), math.rad(s * 15), 0), rgb(200, 190, 170), SLATE)
		mk("Leg", Vector3.new(1.8, 4, 2), CFrame.new(s * 2.8, 2, -2.4), scale2, SLATE)
		-- wings: dark membranes with a burning edge
		for k = 1, 3 do
			mk("Wing", Vector3.new(0.25, 5 - k, 7 - k * 1.2), CFrame.new(s * (3.6 + k * 2), 9 + k * 0.6, 0.5) * CFrame.Angles(math.rad(-10), math.rad(s * 20), math.rad(s * (35 - k * 8))), UMBRA, FABRIC)
		end
		mk("WingEdge", Vector3.new(0.3, 0.3, 9), CFrame.new(s * 6.8, 11.6, 0.4) * CFrame.Angles(0, math.rad(s * 20), math.rad(s * 30)), CORONA, N)
	end
	-- the eclipse behind its head: a black disc in a burning ring
	local behind = CFrame.new(0, 15, -1.5)
	mk("Umbra", Vector3.new(0.3, 5, 5), behind * CFrame.Angles(0, math.rad(90), 0), rgb(4, 3, 6), Enum.Material.SmoothPlastic, CYL)
	ring(mk, behind * CFrame.Angles(math.rad(90), 0, 0), 2.8, 14, Vector3.new(1.3, 0.3, 0.45), CORONA, N)
	sparkles(m:FindFirstChild("Umbra") :: BasePart, CORONA, 8)
	return m
end

local wyrm: { [string]: (any, any) -> () } = {}

wyrm.eclipse_breath = function(b, target)
	local origin = b.root.Position
	local dir = flatDir(origin, target.root.Position)
	local half = math.rad(if b.enraged then 90 else 70)
	local r = 46
	K.face(b, origin + dir)
	K.telegraphCone(origin, dir, r, half, 1, b.floorY)
	if not K.hold(b, 1) then return end
	local base = math.atan2(dir.Z, dir.X)
	local side = if math.random() < 0.5 then 1 else -1
	local last: { [Model]: number } = {}
	local t0 = os.clock()
	local dur = 1.8
	local lastPuff = 0
	while os.clock() - t0 < dur and K.alive(b) do
		RunService.Heartbeat:Wait()
		local t = os.clock() - t0
		local a = base + side * (-half + 2 * half * (t / dur))
		local d = angleDir(a)
		K.face(b, origin + d)
		if t - lastPuff >= 0.07 then
			lastPuff = t
			local p = origin + d * math.random(8, r)
			column(p, b.floorY, 5, 7, CORONA, 0.35)
			for _, v in ipairs(inArena(b)) do
				if (last[v.char] or -1) + 0.4 <= t and inCone(origin, d, r, math.rad(13), v.root.Position) then
					last[v.char] = t
					K.hurt(v.char, K.dmg(b, 0.6), origin)
				end
			end
		end
	end
	K.hold(b, 0.6)
end

wyrm.marked_ground = function(b, _target)
	for _ = 1, (if b.enraged then 4 else 3) do
		local spots = {}
		for _, v in ipairs(inArena(b)) do table.insert(spots, v.root.Position) end
		if #spots == 0 then break end
		for _, s in ipairs(spots) do
			K.telegraphCircle(s, 8, 1.4, b.floorY)
			disc(s, b.floorY + 0.03, 3, UMBRA, 0.2, 1.4)
			task.delay(1.4, function()
				if not K.alive(b) then return end
				column(s, b.floorY, 10, 22, UMBRA, 0.5, Enum.Material.SmoothPlastic)
				column(s, b.floorY, 6, 26, CORONA, 0.45)
				K.blast(s, 8, K.dmg(b, 1))
			end)
		end
		if not K.hold(b, 0.6) then return end
	end
	K.hold(b, 1.1)
end

wyrm.tail_sweep = function(b, _target)
	local r = if b.enraged then 22 else 18
	local spot = b.root.Position
	K.telegraphCircle(spot, r, 0.8, b.floorY)
	if not K.hold(b, 0.8) then return end
	local start = b.root.CFrame
	for k = 1, 8 do
		b.root.CFrame = start * CFrame.Angles(0, k / 8 * math.pi * 2, 0)
		task.wait(0.03)
	end
	K.blast(spot, r, K.dmg(b, 1.2))
	K.shock(spot, r, CORONA, b.floorY)
	K.hold(b, 0.6)
end

-- Signature: half the arena burns, then the other half: keep crossing.
wyrm.total_eclipse = function(b, _target)
	toCenter(b)
	K.bossFX(b, { kind = "island_eclipse", duration = 9 })
	local n = angleDir(math.random() * math.pi * 2)
	for _ = 1, (if b.enraged then 4 else 3) do
		K.telegraphCone(b.home, n, ARENA + 4, math.rad(90), 1.8, b.floorY)
		if not K.hold(b, 1.8) then return end
		local side = n
		blastWhere(b, function(p)
			local rel = Vector3.new(p.X - b.home.X, 0, p.Z - b.home.Z)
			return rel.Magnitude <= ARENA + 6 and rel:Dot(side) >= -1
		end, K.dmg(b, 2), nil)
		for k = 1, 7 do
			local a = math.atan2(side.Z, side.X) + (k / 8 - 0.5) * math.pi
			column(b.home + angleDir(a) * math.random(10, ARENA), b.floorY, 7, 24, CORONA, 0.5)
		end
		-- the other side next (turned a little, so it's never quite the same line)
		local turn = math.rad(math.random(-40, 40))
		local a = math.atan2(-n.Z, -n.X) + turn
		n = angleDir(a)
		if not K.hold(b, 0.5) then return end
	end
	K.hold(b, 0.5)
end

-- ── The roster ──────────────────────────────────────────────────────────────
-- (moves are named per boss, so no two share a name with BossAI's own)
local function prefixed(prefix: string, moves: { [string]: (any, any) -> () }): ({ [string]: (any, any) -> () }, { string })
	local out, names = {}, {}
	for name, fn in pairs(moves) do
		out[prefix .. name] = fn
		table.insert(names, prefix .. name)
	end
	table.sort(names)
	return out, names
end

export type BossDef = {
	id: string,
	name: string,
	title: string,       -- its line on the ritual's panel
	color: Color3,
	health: number,
	damage: number,
	moves: { [string]: (any, any) -> () },
	signature: string,
	signatureName: string,
	build: () -> Model,
	region: string,      -- the island region it belongs to (its look)
}

local DEFS: { BossDef } = {
	{ id = "drowned_sovereign", name = "★ The Drowned Sovereign", title = "King beneath the tide", color = TIDE,
		health = 6, damage = 1.25, moves = sovereign, signature = "drowning_tide", signatureName = "THE DROWNING TIDE",
		build = buildSovereign, region = "shore" },
	{ id = "ashen_colossus", name = "★ The Ashen Colossus", title = "The mountain that walks", color = MAGMA,
		health = 7.5, damage = 1.4, moves = colossus, signature = "cataclysm", signatureName = "CATACLYSM",
		build = buildColossus, region = "highlands" },
	{ id = "hollow_saint", name = "★ The Hollow Saint", title = "Faith with nothing inside", color = HOLY,
		health = 5.5, damage = 1.2, moves = saint, signature = "litany", signatureName = "LITANY OF LIGHT",
		build = buildSaint, region = "ruins" },
	{ id = "thorn_matriarch", name = "★ The Thorn Matriarch", title = "Mother of the rotting wood", color = THORN,
		health = 6, damage = 1.25, moves = matriarch, signature = "overgrowth", signatureName = "WILD OVERGROWTH",
		build = buildMatriarch, region = "forest" },
	{ id = "riftbound_knight", name = "★ The Riftbound Knight", title = "Sworn to a broken world", color = RIFT,
		health = 5.5, damage = 1.35, moves = knight, signature = "dimension_rend", signatureName = "DIMENSION REND",
		build = buildKnight, region = "caves" },
	{ id = "eclipse_wyrm", name = "★ The Eclipse Wyrm", title = "It swallowed the sun once", color = CORONA,
		health = 7, damage = 1.35, moves = wyrm, signature = "total_eclipse", signatureName = "TOTAL ECLIPSE",
		build = buildWyrm, region = "sanctuary" },
}

local byId: { [string]: BossDef } = {}
for _, d in ipairs(DEFS) do byId[d.id] = d end

function IslandBosses.Ids(): { string }
	local out = {}
	for _, d in ipairs(DEFS) do table.insert(out, d.id) end
	return out
end

function IslandBosses.Get(id: string): BossDef?
	return byId[id]
end

-- ── Defeats ─────────────────────────────────────────────────────────────────
-- Each falls its own way, where it fell.
local DEFEATS: { [string]: (Vector3, number) -> () } = {
	drowned_sovereign = function(pos, fy)
		-- the sea takes it back: a column of water collapses in a wave
		column(pos, fy, 14, 60, TIDE, 1.4)
		for k = 1, 3 do task.delay(k * 0.25, function() K.shock(pos, 18 + k * 12, TIDE, fy) end) end
	end,
	ashen_colossus = function(pos, fy)
		-- it crumbles: its stones fall and cool
		for k = 1, 14 do
			local a = k / 14 * math.pi * 2
			local rock = K.part({ Size = Vector3.one * math.random(2, 4), CFrame = CFrame.new(pos + Vector3.new(0, 8 + math.random() * 8, 0)),
				Color = if k % 3 == 0 then MAGMA else rgb(60, 50, 46), Material = if k % 3 == 0 then N else BASALT })
			TweenService:Create(rock, TweenInfo.new(0.9, Enum.EasingStyle.Bounce), { CFrame = CFrame.new(pos + angleDir(a) * math.random(4, 12) + Vector3.new(0, 1, 0)) * CFrame.Angles(a, a * 2, 0) }):Play()
			task.delay(2.5, function()
				if rock.Parent then TweenService:Create(rock, TweenInfo.new(1.5), { Transparency = 1, Color = rgb(30, 28, 28) }):Play() end
			end)
			Debris:AddItem(rock, 4.2)
		end
		K.shock(pos, 26, MAGMA, fy)
	end,
	hollow_saint = function(pos, fy)
		-- it rises out of its robe as light
		local p = K.part({ Size = Vector3.new(6, 6, 6), Shape = BALL, CFrame = CFrame.new(pos + Vector3.new(0, 10, 0)), Color = HOLY, Transparency = 0.2 })
		TweenService:Create(p, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = p.CFrame + Vector3.new(0, 90, 0), Size = Vector3.one * 1, Transparency = 1 }):Play()
		Debris:AddItem(p, 2.3)
		column(pos, fy, 10, 120, HOLY, 2)
	end,
	thorn_matriarch = function(pos, fy)
		-- it wilts, and flowers ring where it stood
		for k = 1, 16 do
			local at = pos + angleDir(k / 16 * math.pi * 2) * (6 + (k % 2) * 4)
			local f = K.part({ Size = Vector3.new(0.2, 1.6, 1.6), Shape = CYL, CFrame = CFrame.new(at.X, fy + 0.3, at.Z) * FLAT, Color = if k % 2 == 0 then BLOOM else THORN })
			TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.new(0.2, 3, 3) }):Play()
			task.delay(4, function() if f.Parent then TweenService:Create(f, TweenInfo.new(1.5), { Transparency = 1 }):Play() end end)
			Debris:AddItem(f, 5.6)
		end
		K.shock(pos, 22, THORN, fy)
	end,
	riftbound_knight = function(pos, fy)
		-- the rift swallows it: it implodes
		local p = rift(pos, fy, 16, 1.6)
		TweenService:Create(p, TweenInfo.new(1.5, Enum.EasingStyle.Back, Enum.EasingDirection.In), { Size = Vector3.new(0.3, 0.5, 0.5) }):Play()
		task.delay(1.4, function() K.shock(pos, 30, RIFT, fy) end)
	end,
	eclipse_wyrm = function(pos, fy)
		-- the eclipse breaks: rings of sunlight burst out
		for k = 0, 4 do task.delay(k * 0.2, function() K.shock(pos, 14 + k * 10, CORONA, fy) end) end
		column(pos, fy, 16, 80, CORONA, 1.5)
	end,
}

function IslandBosses.Defeat(id: string, pos: Vector3, floorY: number)
	local fn = DEFEATS[id]
	if fn then pcall(fn, pos, floorY) end
end

function IslandBosses.Init()
	for _, d in ipairs(DEFS) do
		local moves, names = prefixed(d.id .. ":", d.moves)
		BossAI.Register(d.id, {
			name = d.name,
			health = d.health,
			damage = d.damage,
			xp = 3, -- (×100 a kill; with the ritual's own reward about two levels at wave 3+)
			color = d.color,
			moves = names,
			signature = d.id .. ":" .. d.signature,
			gap = 1.1,
			build = d.build,
			aura = false,
			hidden = true,
		}, moves, d.signatureName)
	end
end

return IslandBosses
