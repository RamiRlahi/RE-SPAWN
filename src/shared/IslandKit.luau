--!strict
--[[
	IslandKit.luau
	The Forgotten Isle's pieces, built from parts (like KeepKit and ArcadeKit):
	the props each region scatters, its landmarks, the spawn sources enemies
	climb out of, the chests and the Ancient Sanctuary's ritual site. The
	ground itself is terrain (IslandGenerator); these are only what terrain
	can't be.

	  IslandKit.Build(name, cf, rng, parent) → Model   one piece, standing at cf
	  IslandKit.Statue(index, cf, parent) → Model     the ritual's statues (1..8)
	  IslandKit.Chest(kind, cf, parent) → Model       common / rare / cursed / elite / ritual
	  IslandKit.Altar(cf, parent) → Model

	Every part is anchored, never listens for touches, and only the big ones
	cast shadows; nothing carries a light (Neon glows on its own).
--]]

local IslandKit = {}

local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end

local M = Enum.Material
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lying flat

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch = false
	p.CastShadow = size.Magnitude > 9
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or M.SmoothPlastic
	if props then for k, v in pairs(props) do (p :: any)[k] = v end end
	p.Parent = parent
	return p
end
local function glow(parent: Instance, size: Vector3, cf: CFrame, color: Color3, props: { [string]: any }?): BasePart
	local p = part(parent, size, cf, color, M.Neon, props)
	p.CanCollide, p.CanQuery, p.CastShadow = false, false, false
	return p
end
local function cyl(parent: Instance, height: number, diameter: number, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
	local p = part(parent, Vector3.new(height, diameter, diameter), cf * FLAT, color, material, props)
	p.Shape = Enum.PartType.Cylinder
	return p
end
local function ball(parent: Instance, d: number, cf: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = part(parent, Vector3.one * d, cf, color, material)
	p.Shape = Enum.PartType.Ball
	return p
end
local function model(name: string, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = name
	m.Parent = parent
	return m
end
local function emit(parent: BasePart, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local function seq(a: number, b: number): NumberSequence return NumberSequence.new(a, b) end
IslandKit.SPARK, IslandKit.SMOKE = SPARK, SMOKE

-- ── Shore ───────────────────────────────────────────────────────────────────
local B: { [string]: (CFrame, Random, Model) -> () } = {}

B.palm = function(cf, rng, m)
	local h = rng:NextNumber(14, 20)
	local lean = CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12)))
	local trunk = cf * lean
	for i = 0, 3 do
		cyl(m, h / 4 + 0.4, 1.6 - i * 0.18, trunk * CFrame.new(0, h / 8 + i * h / 4, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(120, 92, 64), M.Wood)
	end
	local top = trunk * CFrame.new(0, h, 0)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + rng:NextNumber(0, 0.4)
		part(m, Vector3.new(1.4, 0.3, 8), top * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, -0.6, -4),
			rgb(70, 120, 60), M.LeafyGrass, { CanCollide = false })
	end
end
B.driftwood = function(cf, rng, m)
	cyl(m, rng:NextNumber(5, 9), rng:NextNumber(0.8, 1.3), cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(150, 132, 108), M.Wood)
end
B.crate = function(cf, rng, m)
	local s = rng:NextNumber(2.2, 3.2)
	part(m, Vector3.one * s, cf * CFrame.new(0, s / 2 - 0.2, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-8, 8))), rgb(124, 92, 58), M.WoodPlanks)
end
B.rock = function(cf, rng, m)
	local s = rng:NextNumber(3, 7)
	part(m, Vector3.new(s, s * rng:NextNumber(0.5, 0.9), s * rng:NextNumber(0.7, 1.2)),
		cf * CFrame.new(0, s * 0.2, 0) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
		rgb(96, 92, 96), M.Slate)
end

-- the broken docks: planks on posts out into the water, some gone (cf faces
-- inland: the docks run out behind it, +Z)
B.docks = function(cf, rng, m)
	local WOOD, POST = rgb(112, 86, 60), rgb(70, 54, 40)
	for i = 0, 11 do
		if i > 3 and rng:NextNumber() < 0.22 then continue end -- (a plank gone)
		local tilt = if i > 7 then math.rad(rng:NextNumber(-6, 6)) else 0
		part(m, Vector3.new(9, 0.5, 2.6), cf * CFrame.new(0, 1.2, i * 2.7) * CFrame.Angles(tilt, 0, tilt * 0.5), WOOD, M.WoodPlanks)
		if i % 3 == 0 then
			for _, s in ipairs({ -4, 4 }) do cyl(m, 7, 0.9, cf * CFrame.new(s, -1.5, i * 2.7) * CFrame.Angles(0, 0, math.rad(90)), POST, M.Wood) end
		end
	end
	-- an abandoned boat by it, half sunk
	local boat = cf * CFrame.new(9, -0.6, 16) * CFrame.Angles(math.rad(8), math.rad(20), math.rad(14))
	part(m, Vector3.new(4, 1.4, 10), boat, rgb(96, 70, 48), M.WoodPlanks)
	for _, s in ipairs({ -1.9, 1.9 }) do part(m, Vector3.new(0.4, 1.6, 10), boat * CFrame.new(s, 0.9, 0), rgb(84, 62, 42), M.WoodPlanks) end
end
-- the wreck: a hull on its side in the shallows, ribs showing, a broken mast
B.shipwreck = function(cf, rng, m)
	local HULL, RIB = rgb(84, 64, 46), rgb(60, 46, 34)
	local base = cf * CFrame.Angles(0, 0, math.rad(-24))
	for i = -5, 5 do
		local z = i * 3
		local w = 12 - math.abs(i) * 0.9
		if math.abs(i) > 2 and rng:NextNumber() < 0.3 then
			part(m, Vector3.new(0.8, 9, 0.8), base * CFrame.new(-w / 2, 4, z), RIB, M.Wood) -- (a bare rib)
		else
			part(m, Vector3.new(w, 0.8, 3.1), base * CFrame.new(0, 0, z), HULL, M.WoodPlanks)
			part(m, Vector3.new(0.8, 7, 3.1), base * CFrame.new(-w / 2, 3.5, z), HULL, M.WoodPlanks)
		end
	end
	local mast = cf * CFrame.new(4, 6, 2) * CFrame.Angles(math.rad(70), math.rad(30), 0)
	cyl(m, 22, 1.2, mast * CFrame.Angles(0, 0, math.rad(90)), RIB, M.Wood)
	part(m, Vector3.new(0.3, 8, 7), mast * CFrame.new(2, 4, 0) * CFrame.Angles(0, 0, math.rad(12)), rgb(170, 160, 140), M.Fabric, { CanCollide = false })
end

-- ── Forest ──────────────────────────────────────────────────────────────────
local LEAVES = { rgb(58, 92, 52), rgb(72, 100, 58), rgb(64, 74, 84), rgb(88, 64, 96) } -- (corrupted: some purple-grey)
B.tree = function(cf, rng, m)
	local h = rng:NextNumber(12, 22)
	local w = rng:NextNumber(1.8, 3)
	local c = rgb(78, 58, 46)
	part(m, Vector3.new(w, h, w), cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), c, M.Wood)
	-- twisted roots
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2 + rng:NextNumber(0, 1)
		part(m, Vector3.new(w * 0.6, w * 0.6, 4), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.4, -w) * CFrame.Angles(math.rad(-20), 0, 0), c, M.Wood, { CanCollide = false })
	end
	local leaf = LEAVES[rng:NextInteger(1, #LEAVES)]
	local n = rng:NextInteger(2, 3)
	for k = 1, n do
		local s = rng:NextNumber(8, 13) * (1 - (k - 1) * 0.22)
		part(m, Vector3.new(s, s * 0.6, s), cf * CFrame.new(rng:NextNumber(-1.5, 1.5), h - 1 + (k - 1) * s * 0.4, rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0),
			leaf, M.LeafyGrass, { CanCollide = false })
	end
end
B.deadtree = function(cf, rng, m)
	local h = rng:NextNumber(9, 15)
	local c = rgb(56, 48, 46)
	local trunk = cf * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-8, 8)))
	part(m, Vector3.new(1.4, h, 1.4), trunk * CFrame.new(0, h / 2, 0), c, M.Wood)
	for k = 1, rng:NextInteger(2, 4) do
		local y = h * rng:NextNumber(0.5, 0.95)
		part(m, Vector3.new(0.7, 0.7, rng:NextNumber(3, 6)), trunk * CFrame.new(0, y, 0) * CFrame.Angles(math.rad(rng:NextNumber(-40, -10)), rng:NextNumber(0, 6.28), 0) * CFrame.new(0, 0, -2),
			c, M.Wood, { CanCollide = false })
	end
end
B.mushroom = function(cf, rng, m)
	local h = rng:NextNumber(1.5, 4)
	local cap = if rng:NextNumber() < 0.5 then rgb(150, 70, 190) else rgb(90, 200, 160)
	cyl(m, h, h * 0.3, cf * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), rgb(220, 210, 190), M.SmoothPlastic, { CanCollide = false })
	local c = cyl(m, h * 0.3, h * 1.1, cf * CFrame.new(0, h, 0) * CFrame.Angles(0, 0, math.rad(90)), cap, M.Neon, { CanCollide = false })
	c.Transparency = 0.15
end
B.log = function(cf, rng, m)
	local l = rng:NextNumber(9, 16)
	cyl(m, l, rng:NextNumber(1.8, 2.8), cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.new(0, 1, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(90)) * CFrame.Angles(0, 0, math.rad(-90)),
		rgb(84, 64, 50), M.Wood)
end
-- the grove: a ring of huge black trees round a corrupted pool
B.grove = function(cf, rng, m)
	for k = 0, 6 do
		local a = k / 7 * math.pi * 2
		local at = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -16)
		local h = rng:NextNumber(24, 32)
		part(m, Vector3.new(3.4, h, 3.4), at * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, a, math.rad(rng:NextNumber(-6, 6))), rgb(34, 28, 34), M.Wood)
		part(m, Vector3.new(14, 6, 14), at * CFrame.new(0, h, 0), rgb(60, 44, 70), M.LeafyGrass, { CanCollide = false })
	end
	local pool = cyl(m, 0.4, 14, cf * CFrame.new(0, 0.25, 0), rgb(120, 60, 170), M.Neon, { CanCollide = false })
	pool.Transparency = 0.25
	emit(pool, { Texture = SMOKE, Color = ColorSequence.new(rgb(140, 70, 200)), Size = seq(3, 7), Transparency = seq(0.7, 1),
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(1, 2), Rate = 4, SpreadAngle = Vector2.new(30, 30) })
end
-- a hunter's camp: a dead fire, a lean-to, bones
B.camp = function(cf, _rng, m)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		part(m, Vector3.new(1.2, 0.8, 1.2), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.3, -2), rgb(80, 78, 80), M.Slate)
	end
	part(m, Vector3.new(2.4, 0.3, 2.4), cf * CFrame.new(0, 0.2, 0), rgb(40, 34, 30), M.Ground)
	local lean = cf * CFrame.new(0, 0, 8)
	part(m, Vector3.new(8, 0.4, 6), lean * CFrame.new(0, 2.6, 0) * CFrame.Angles(math.rad(35), 0, 0), rgb(110, 90, 60), M.Fabric)
	for _, s in ipairs({ -3.6, 3.6 }) do part(m, Vector3.new(0.5, 5, 0.5), lean * CFrame.new(s, 2.5, -2.2), rgb(80, 60, 44), M.Wood) end
end

-- ── Ruins ───────────────────────────────────────────────────────────────────
local STONE, STONE2, MOSS = rgb(132, 128, 118), rgb(108, 106, 100), rgb(80, 110, 70)
B.pillar = function(cf, rng, m)
	local h = rng:NextNumber(5, 16)
	local broken = rng:NextNumber() < 0.6
	part(m, Vector3.new(4, 1, 4), cf * CFrame.new(0, 0.3, 0), STONE2, M.Slate)
	cyl(m, h, 2.8, cf * CFrame.new(0, h / 2 + 0.6, 0) * CFrame.Angles(0, 0, math.rad(90)), STONE, M.Slate)
	if not broken then part(m, Vector3.new(4, 1, 4), cf * CFrame.new(0, h + 1, 0), STONE2, M.Slate) end
	if rng:NextNumber() < 0.5 then part(m, Vector3.new(3, 0.4, 3), cf * CFrame.new(0.4, h * 0.5, 0) * CFrame.Angles(0, 0, math.rad(80)), MOSS, M.Grass, { CanCollide = false }) end
	if broken and rng:NextNumber() < 0.5 then -- (its fallen top beside it)
		cyl(m, h * 0.5, 2.8, cf * CFrame.new(3.5, 1.4, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.Angles(0, 0, 0), STONE, M.Slate)
	end
end
B.wall = function(cf, rng, m)
	local l = rng:NextNumber(10, 20)
	local w = cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	local x = -l / 2
	while x < l / 2 do
		local seg = math.min(rng:NextNumber(2.5, 4.5), l / 2 - x)
		local h = rng:NextNumber(2, 9)
		part(m, Vector3.new(seg, h, 2.2), w * CFrame.new(x + seg / 2, h / 2 - 0.3, 0), if rng:NextNumber() < 0.5 then STONE else STONE2, M.Slate)
		x += seg
	end
end
B.statue = function(cf, rng, m)
	part(m, Vector3.new(5, 2, 5), cf * CFrame.new(0, 0.8, 0), STONE2, M.Slate)
	local tilt = cf * CFrame.new(0, 1.8, 0) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-6, 6)))
	part(m, Vector3.new(3, 6, 2), tilt * CFrame.new(0, 3, 0), STONE, M.Marble)
	if rng:NextNumber() < 0.6 then part(m, Vector3.new(2, 2, 2), tilt * CFrame.new(0, 7, 0), STONE, M.Marble) end -- (some have lost their heads)
	part(m, Vector3.new(1, 5, 1), tilt * CFrame.new(1.9, 3, 0) * CFrame.Angles(0, 0, math.rad(15)), STONE2, M.Marble)
end
-- the drowned temple: a stepped platform half under water, columns, a dark doorway
B.temple = function(cf, rng, m)
	for i = 0, 3 do
		local s = 40 - i * 7
		part(m, Vector3.new(s, 2, s), cf * CFrame.new(0, -1 + i * 2, 0), if i % 2 == 0 then STONE else STONE2, M.Slate)
	end
	local top = cf * CFrame.new(0, 7, 0)
	for _, c in ipairs({ { -8, -8 }, { 8, -8 }, { -8, 8 }, { 8, 8 }, { -8, 0 }, { 8, 0 } }) do
		local h = if rng:NextNumber() < 0.35 then rng:NextNumber(4, 8) else 14
		cyl(m, h, 2.6, top * CFrame.new(c[1], h / 2, c[2]) * CFrame.Angles(0, 0, math.rad(90)), STONE, M.Marble)
	end
	part(m, Vector3.new(20, 2, 20), top * CFrame.new(0, 15, 0) * CFrame.Angles(0, 0, math.rad(4)), STONE2, M.Slate)
	-- the shrine at its heart, a faint glow
	part(m, Vector3.new(4, 3, 4), top * CFrame.new(0, 1.5, 0), STONE2, M.Slate)
	local g = glow(m, Vector3.new(1.4, 1.4, 1.4), top * CFrame.new(0, 3.8, 0) * CFrame.Angles(0.6, 0.6, 0), rgb(90, 220, 255))
	g.Transparency = 0.2
end
-- the fallen colossus: a giant stone head and hand in the mud
B.fallen_statue = function(cf, _rng, m)
	local head = cf * CFrame.Angles(math.rad(-10), math.rad(30), math.rad(70))
	part(m, Vector3.new(14, 16, 14), head * CFrame.new(0, 4, 0), STONE, M.Marble)
	part(m, Vector3.new(4, 3, 3), head * CFrame.new(0, 3, -8), STONE2, M.Marble) -- (the nose)
	for _, s in ipairs({ -3.5, 3.5 }) do glow(m, Vector3.new(2, 1.2, 0.4), head * CFrame.new(s, 7, -7.1), rgb(80, 230, 255)) end
	local hand = cf * CFrame.new(22, 0, 6)
	part(m, Vector3.new(10, 4, 12), hand * CFrame.new(0, 2, 0), STONE, M.Marble)
	for k = -2, 1 do part(m, Vector3.new(2, 2, 7), hand * CFrame.new(k * 2.4 + 1, 4, -8) * CFrame.Angles(math.rad(-20), 0, 0), STONE2, M.Marble) end
end

-- ── Highlands ───────────────────────────────────────────────────────────────
local BASALT, ASH, EMBER = rgb(48, 42, 44), rgb(84, 78, 76), rgb(255, 110, 40)
B.spire = function(cf, rng, m)
	local h = rng:NextNumber(8, 20)
	local w = rng:NextNumber(3, 6)
	part(m, Vector3.new(w, h, w), cf * CFrame.new(0, h / 2 - 1, 0) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-8, 8))), BASALT, M.Basalt)
	if rng:NextNumber() < 0.5 then
		glow(m, Vector3.new(w * 0.3, h * 0.6, 0.3), cf * CFrame.new(0, h * 0.4, -w / 2 - 0.05), EMBER)
	end
end
-- a glowing crack in the ash
B.crack = function(cf, rng, m)
	local a = rng:NextNumber(0, 6.28)
	local at = cf * CFrame.Angles(0, a, 0)
	local n = rng:NextInteger(3, 5)
	for k = 0, n - 1 do
		local seg = at * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0) * CFrame.new(0, 0.12, -k * 4)
		glow(m, Vector3.new(rng:NextNumber(0.6, 1.4), 0.25, 4.4), seg, if k % 2 == 0 then EMBER else rgb(255, 170, 70))
	end
	local p = m:FindFirstChildWhichIsA("BasePart")
	if p and rng:NextNumber() < 0.5 then
		emit(p :: BasePart, { Texture = FIRE, Color = ColorSequence.new(EMBER), Size = seq(1.2, 0.2), Transparency = seq(0.3, 1),
			Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(2, 5), Rate = 3, LightEmission = 1 })
	end
end
-- the ashen fort: broken walls and a gatehouse on a rise
B.fort = function(cf, rng, m)
	local S = 30
	for side = 0, 3 do
		local w = cf * CFrame.Angles(0, side * math.pi / 2, 0) * CFrame.new(0, 0, -S / 2)
		local x = -S / 2
		while x < S / 2 do
			local seg = 4
			local gap = side == 0 and math.abs(x + seg / 2) < 4 -- (the gate)
			if not gap and rng:NextNumber() < 0.85 then
				local h = rng:NextNumber(5, 12)
				part(m, Vector3.new(seg, h, 3), w * CFrame.new(x + seg / 2, h / 2 - 0.5, 0), if rng:NextNumber() < 0.5 then ASH else BASALT, M.Basalt)
				if h > 9 then part(m, Vector3.new(1.4, 1.4, 3.4), w * CFrame.new(x + seg / 2, h + 0.2, 0), BASALT, M.Basalt) end
			end
			x += seg
		end
	end
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local h = rng:NextNumber(12, 18)
		part(m, Vector3.new(7, h, 7), cf * CFrame.new(c[1] * S / 2, h / 2 - 0.5, c[2] * S / 2), BASALT, M.Basalt)
	end
	-- a brazier of embers in the yard
	part(m, Vector3.new(4, 3, 4), cf * CFrame.new(0, 1.5, 0), BASALT, M.Basalt)
	local fire = glow(m, Vector3.new(3, 0.6, 3), cf * CFrame.new(0, 3.2, 0), EMBER)
	emit(fire, { Texture = FIRE, Color = ColorSequence.new(rgb(255, 200, 100), EMBER), Size = seq(3, 0.5), Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(4, 7), Rate = 14, LightEmission = 1 })
end
-- the ember rift: a deep glowing chasm with spires round it
B.ember_rift = function(cf, rng, m)
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		local r = 10 + rng:NextNumber(-2, 2)
		local at = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r)
		local h = rng:NextNumber(6, 14)
		part(m, Vector3.new(3, h, 3), at * CFrame.new(0, h / 2 - 1, 0) * CFrame.Angles(math.rad(-15), 0, 0), BASALT, M.Basalt)
	end
	local core = glow(m, Vector3.new(14, 0.3, 6), cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0), EMBER)
	emit(core, { Texture = FIRE, Color = ColorSequence.new(rgb(255, 220, 120), EMBER), Size = seq(4, 1), Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(6, 10), Rate = 18, LightEmission = 1, Shape = Enum.ParticleEmitterShape.Box })
end

-- ── Caves ───────────────────────────────────────────────────────────────────
B.crystal = function(cf, rng, m)
	local c = if rng:NextNumber() < 0.5 then rgb(150, 110, 255) else rgb(100, 220, 255)
	for k = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(3, 8)
		local p = glow(m, Vector3.new(h * 0.3, h, h * 0.3), cf * CFrame.new(rng:NextNumber(-1.5, 1.5), h / 2 - 0.5, rng:NextNumber(-1.5, 1.5))
			* CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-25, 25))), c)
		p.Transparency = 0.15
		p.Material = M.Glass
	end
end

-- ── Spawn sources: where enemies climb out ──────────────────────────────────
B.src_clearing = function(cf, rng, m) -- a ring of corrupted roots round black earth
	cyl(m, 0.3, 10, cf * CFrame.new(0, 0.1, 0), rgb(36, 26, 40), M.Ground, { CanCollide = false })
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2 + rng:NextNumber(0, 0.5)
		part(m, Vector3.new(0.9, 0.9, 5), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.6, -5) * CFrame.Angles(math.rad(25), 0, 0), rgb(54, 34, 60), M.Wood, { CanCollide = false })
	end
end
B.src_fissure = function(cf, rng, m) -- a glowing split in the ground
	local at = cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	for k = -1, 1 do glow(m, Vector3.new(0.8, 0.3, 4.5), at * CFrame.new(k * 0.6, 0.12, k * 4) * CFrame.Angles(0, k * 0.4, 0), rgb(160, 70, 220)) end
end
B.src_ruin = function(cf, _rng, m) -- a broken arch, its keystone glowing
	for _, s in ipairs({ -4, 4 }) do part(m, Vector3.new(2, 9, 2), cf * CFrame.new(s, 4.5, 0), STONE2, M.Slate) end
	part(m, Vector3.new(10, 1.6, 2.2), cf * CFrame.new(0, 9.6, 0) * CFrame.Angles(0, 0, math.rad(6)), STONE, M.Slate)
	glow(m, Vector3.new(1.4, 1.4, 2.4), cf * CFrame.new(0, 9.6, 0), rgb(160, 70, 220))
end
B.src_rift = function(cf, _rng, m) -- a small standing tear of violet light
	local r = glow(m, Vector3.new(0.4, 7, 3), cf * CFrame.new(0, 4.2, 0), rgb(170, 80, 255))
	r.Transparency = 0.25
	emit(r, { Texture = SPARK, Color = ColorSequence.new(rgb(200, 140, 255)), Size = seq(0.5, 0), Transparency = seq(0, 1),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(1, 3), Rate = 6, LightEmission = 1, SpreadAngle = Vector2.new(180, 180) })
end
B.src_cave = function(cf, rng, m) -- stones round a hole into the dark
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		part(m, Vector3.new(3, rng:NextNumber(2, 4), 3), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 1, -4) * CFrame.Angles(0.2, 0.4, 0), rgb(60, 56, 64), M.Slate)
	end
	cyl(m, 0.3, 7, cf * CFrame.new(0, 0.1, 0), rgb(10, 8, 14), M.SmoothPlastic, { CanCollide = false })
end
B.src_elite = function(cf, _rng, m) -- a skull altar
	part(m, Vector3.new(5, 3, 5), cf * CFrame.new(0, 1.5, 0), BASALT, M.Basalt)
	ball(m, 2.2, cf * CFrame.new(0, 4, 0), rgb(220, 210, 190), M.SmoothPlastic)
	for _, s in ipairs({ -0.5, 0.5 }) do glow(m, Vector3.new(0.4, 0.4, 0.2), cf * CFrame.new(s, 4.2, -1.05), EMBER) end
end

function IslandKit.Build(name: string, cf: CFrame, rng: Random, parent: Instance): Model?
	local fn = B[name]
	if not fn then return nil end
	local m = model(name, parent)
	fn(cf, rng, m)
	return m
end

-- ── Chests ──────────────────────────────────────────────────────────────────
-- Their rarity told by the wood and the metal, the glow and the particles.
local CHEST_LOOK = {
	common = { wood = rgb(120, 86, 52), metal = rgb(120, 116, 112), glow = rgb(240, 220, 170), rate = 0 },
	rare = { wood = rgb(54, 60, 92), metal = rgb(150, 190, 255), glow = rgb(110, 170, 255), rate = 4 },
	cursed = { wood = rgb(40, 22, 34), metal = rgb(150, 40, 90), glow = rgb(220, 50, 120), rate = 6 },
	elite = { wood = rgb(70, 40, 90), metal = rgb(220, 170, 70), glow = rgb(200, 120, 255), rate = 6 },
	ritual = { wood = rgb(30, 24, 40), metal = rgb(255, 210, 110), glow = rgb(255, 200, 90), rate = 10 },
}
IslandKit.ChestLook = CHEST_LOOK
function IslandKit.Chest(kind: string, cf: CFrame, parent: Instance): Model
	local look = CHEST_LOOK[kind] or CHEST_LOOK.common
	local m = model("Chest_" .. kind, parent)
	local s = if kind == "ritual" then 1.6 elseif kind == "elite" or kind == "cursed" then 1.25 else 1
	local base = part(m, Vector3.new(4, 2.2, 2.6) * s, cf * CFrame.new(0, 1.1 * s, 0), look.wood, M.WoodPlanks)
	base.Name = "Base"
	for _, x in ipairs({ -1.5, 1.5 }) do part(m, Vector3.new(0.35, 2.3, 2.7) * s, cf * CFrame.new(x * s, 1.1 * s, 0), look.metal, M.Metal) end
	-- the lid, hinged at the back (IslandChests swings it open)
	local lid = part(m, Vector3.new(4, 1, 2.6) * s, cf * CFrame.new(0, 2.7 * s, 0), look.wood, M.WoodPlanks)
	lid.Name = "Lid"
	local band = part(m, Vector3.new(4.1, 0.3, 0.4) * s, cf * CFrame.new(0, 2.4 * s, -1.2 * s), look.metal, M.Metal)
	band.Name = "LidBand"
	local lock = glow(m, Vector3.new(0.6, 0.7, 0.2) * s, cf * CFrame.new(0, 2.1 * s, -1.36 * s), look.glow)
	lock.Name = "Lock"
	if look.rate > 0 then
		emit(base, { Texture = SPARK, Color = ColorSequence.new(look.glow), Size = seq(0.4, 0), Transparency = seq(0, 1),
			Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(0.5, 1.5), Rate = look.rate, LightEmission = 1, SpreadAngle = Vector2.new(60, 60) })
	end
	m.PrimaryPart = base
	return m
end

-- ── The Ancient Sanctuary ───────────────────────────────────────────────────
-- The eight statues: each a different power, its own stone and silhouette.
-- Each has a "Glow" part (its eyes and sigil), dark until the ritual wakes it.
export type StatueLook = { name: string, stone: Color3, material: Enum.Material, accent: Color3 }
IslandKit.Statues = {
	{ name = "The Tidecaller", stone = rgb(70, 96, 104), material = M.Slate, accent = rgb(80, 220, 255) },
	{ name = "The Pyre King", stone = rgb(66, 52, 50), material = M.Basalt, accent = rgb(255, 120, 40) },
	{ name = "The Radiant", stone = rgb(214, 206, 188), material = M.Marble, accent = rgb(255, 220, 120) },
	{ name = "The Wildmother", stone = rgb(92, 104, 80), material = M.Cobblestone, accent = rgb(120, 255, 120) },
	{ name = "The Veiled", stone = rgb(54, 48, 70), material = M.Slate, accent = rgb(180, 90, 255) },
	{ name = "The Eclipse", stone = rgb(30, 28, 34), material = M.Granite, accent = rgb(255, 200, 90) },
	{ name = "The Bonewarden", stone = rgb(190, 182, 166), material = M.Limestone, accent = rgb(140, 255, 200) },
	{ name = "The Stormherald", stone = rgb(80, 86, 104), material = M.Granite, accent = rgb(120, 170, 255) },
} :: { StatueLook }

function IslandKit.Statue(index: number, cf: CFrame, parent: Instance): Model
	local look = IslandKit.Statues[index]
	local m = model("Statue_" .. index, parent)
	m:SetAttribute("StatueName", look.name)
	local S, MAT, A = look.stone, look.material, look.accent
	-- plinth, robed body, shoulders, head (all face the altar: -Z of cf)
	part(m, Vector3.new(7, 3, 7), cf * CFrame.new(0, 1.5, 0), S:Lerp(Color3.new(0, 0, 0), 0.25), MAT)
	part(m, Vector3.new(5, 9, 4), cf * CFrame.new(0, 7.5, 0), S, MAT)
	part(m, Vector3.new(7, 2, 4), cf * CFrame.new(0, 12.5, 0), S, MAT)
	local head = part(m, Vector3.new(2.6, 3, 2.6), cf * CFrame.new(0, 15, 0), S, MAT)
	head.Name = "Head"
	local eyes = glow(m, Vector3.new(1.8, 0.4, 0.2), cf * CFrame.new(0, 15.4, -1.36), A)
	eyes.Name = "Glow"
	eyes.Transparency = 0.85
	local sigil = glow(m, Vector3.new(1.6, 1.6, 0.2), cf * CFrame.new(0, 8, -2.06) * CFrame.Angles(0, 0, math.rad(45)), A)
	sigil.Name = "Glow"
	sigil.Transparency = 0.85
	-- its silhouette: what it holds and wears
	if index == 1 then -- the Tidecaller: a trident and a crown of shells
		part(m, Vector3.new(0.5, 16, 0.5), cf * CFrame.new(3.4, 8, -0.5), S, MAT)
		for k = -1, 1 do part(m, Vector3.new(0.4, 2.4, 0.4), cf * CFrame.new(3.4 + k * 0.8, 16.8, -0.5), S, MAT) end
		for k = -1, 1 do part(m, Vector3.new(0.6, 1.2, 0.6), cf * CFrame.new(k * 0.9, 17, 0) * CFrame.Angles(0, 0, k * 0.4), S, MAT) end
	elseif index == 2 then -- the Pyre King: great horns and a burning brand
		for _, s in ipairs({ -1, 1 }) do part(m, Vector3.new(0.7, 4, 0.7), cf * CFrame.new(s * 1.8, 17, 0) * CFrame.Angles(0, 0, -s * 0.6), S, MAT) end
		part(m, Vector3.new(0.8, 8, 0.8), cf * CFrame.new(-3.6, 10, -1) * CFrame.Angles(math.rad(-20), 0, 0), S, MAT)
	elseif index == 3 then -- the Radiant: a halo and folded wings
		local halo = cyl(m, 0.3, 4, cf * CFrame.new(0, 18, 0.6) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.rad(-90)) * CFrame.Angles(math.rad(90), 0, 0), S, MAT)
		halo.Name = "Halo"
		for _, s in ipairs({ -1, 1 }) do part(m, Vector3.new(1, 10, 4), cf * CFrame.new(s * 3.6, 10, 1.4) * CFrame.Angles(0, -s * 0.3, s * 0.2), S, MAT) end
	elseif index == 4 then -- the Wildmother: antlers of branches, a root-hem
		for _, s in ipairs({ -1, 1 }) do
			part(m, Vector3.new(0.5, 4, 0.5), cf * CFrame.new(s * 1.4, 17.5, 0) * CFrame.Angles(0, 0, -s * 0.5), S, MAT)
			part(m, Vector3.new(0.4, 2.4, 0.4), cf * CFrame.new(s * 2.6, 18.6, 0) * CFrame.Angles(0, 0, -s * 1.1), S, MAT)
		end
		for k = 0, 5 do part(m, Vector3.new(0.8, 0.8, 3.4), cf * CFrame.Angles(0, k / 6 * math.pi * 2, 0) * CFrame.new(0, 3.4, -3), S, MAT) end
	elseif index == 5 then -- the Veiled: a deep hood and an orb of void in both hands
		part(m, Vector3.new(3.6, 4, 3.4), cf * CFrame.new(0, 15.4, 0.2), S, MAT)
		local orb = glow(m, Vector3.one * 1.8, cf * CFrame.new(0, 9.5, -2.8), A)
		orb.Name = "Glow"
		orb.Shape = Enum.PartType.Ball
		orb.Transparency = 0.85
	elseif index == 6 then -- the Eclipse: a crescent behind its head
		for k = -3, 3 do
			local a = k / 3 * 1.1
			part(m, Vector3.new(0.6, 1.4, 0.6), cf * CFrame.new(math.sin(a) * 3, 15 + math.cos(a) * 3, 1.4) * CFrame.Angles(0, 0, -a), S, MAT)
		end
	elseif index == 7 then -- the Bonewarden: a skull face and a scythe
		part(m, Vector3.new(0.5, 15, 0.5), cf * CFrame.new(3.4, 7.5, -0.4), S, MAT)
		part(m, Vector3.new(0.4, 1, 5), cf * CFrame.new(3.4, 14.6, -2.6) * CFrame.Angles(math.rad(-15), 0, 0), S, MAT)
		for _, s in ipairs({ -0.6, 0.6 }) do part(m, Vector3.new(0.6, 0.6, 0.2), cf * CFrame.new(s, 15.6, -1.4), Color3.new(0, 0, 0), M.SmoothPlastic) end
	else -- the Stormherald: a spear raised high, a winged helm
		part(m, Vector3.new(0.5, 20, 0.5), cf * CFrame.new(-3.4, 12, -0.5) * CFrame.Angles(0, 0, math.rad(-8)), S, MAT)
		for _, s in ipairs({ -1, 1 }) do part(m, Vector3.new(0.3, 2, 2), cf * CFrame.new(s * 1.6, 16, 0) * CFrame.Angles(0, 0, -s * 0.5), S, MAT) end
	end
	return m
end

-- The altar: a stepped dais, a slab of black stone, and above it the focus,
-- a shard of crystal that drinks the light of the statues.
function IslandKit.Altar(cf: CFrame, parent: Instance): Model
	local m = model("Altar", parent)
	local DARK = rgb(34, 30, 40)
	for i = 0, 2 do cyl(m, 1, 18 - i * 4, cf * CFrame.new(0, 0.5 + i, 0), if i % 2 == 0 then DARK else rgb(48, 42, 56), M.Slate) end
	local slab = part(m, Vector3.new(6, 3, 4), cf * CFrame.new(0, 4.5, 0), rgb(22, 18, 26), M.Basalt)
	slab.Name = "Slab"
	for _, s in ipairs({ -1, 1 }) do
		part(m, Vector3.new(0.6, 1.2, 0.6), cf * CFrame.new(s * 2.4, 6.6, -1.4), rgb(220, 210, 180), M.SmoothPlastic) -- (candles)
		local flame = glow(m, Vector3.new(0.3, 0.5, 0.3), cf * CFrame.new(s * 2.4, 7.4, -1.4), rgb(255, 190, 90))
		flame.Name = "Candle"
	end
	local focus = glow(m, Vector3.new(1.6, 3.4, 1.6), cf * CFrame.new(0, 10, 0) * CFrame.Angles(0, math.rad(45), 0), rgb(190, 90, 255))
	focus.Name = "Focus"
	focus.Transparency = 0.45
	focus.Material = M.Glass
	emit(focus, { Texture = SPARK, Color = ColorSequence.new(rgb(200, 130, 255)), Size = seq(0.6, 0), Transparency = seq(0, 1),
		Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(0.5, 1.5), Rate = 5, LightEmission = 1, SpreadAngle = Vector2.new(180, 180) })
	return m
end

return IslandKit
