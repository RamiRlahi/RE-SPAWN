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
		cyl(m, h / 4 + 0.4, 1.6 - i * 0.18, trunk * CFrame.new(0, h / 8 + i * h / 4, 0), rgb(120, 92, 64), M.Wood)
	end
	local top = trunk * CFrame.new(0, h, 0)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + rng:NextNumber(0, 0.4)
		part(m, Vector3.new(1.4, 0.3, 8), top * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-22), 0, 0) * CFrame.new(0, -0.6, -4),
			rgb(70, 120, 60), M.LeafyGrass, { CanCollide = false })
	end
end
B.driftwood = function(cf, rng, m)
	cyl(m, rng:NextNumber(5, 9), rng:NextNumber(0.8, 1.3), cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(90)),
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
local WOOD, POST = rgb(112, 86, 60), rgb(70, 54, 40)
-- planks on posts out into the water (`n` long), some gone
local function planks(cf: CFrame, rng: Random, m: Model, n: number)
	for i = 0, n - 1 do
		if i > 3 and rng:NextNumber() < 0.22 then continue end -- (a plank gone)
		local tilt = if i > n - 4 then math.rad(rng:NextNumber(-6, 6)) else 0
		part(m, Vector3.new(9, 0.5, 2.6), cf * CFrame.new(0, 1.2, i * 2.7) * CFrame.Angles(tilt, 0, tilt * 0.5), WOOD, M.WoodPlanks)
		if i % 3 == 0 then
			for _, s in ipairs({ -4, 4 }) do cyl(m, 7, 0.9, cf * CFrame.new(s, -1.5, i * 2.7), POST, M.Wood) end
		end
	end
end
-- a lone pier off a beach (cf faces inland: it runs out behind, +Z)
B.pier = function(cf, rng, m)
	planks(cf, rng, m, rng:NextInteger(7, 11))
	if rng:NextNumber() < 0.5 then cyl(m, 3, 1.4, cf * CFrame.new(3, 2.6, 8), rgb(124, 92, 58), M.WoodPlanks) end -- (a barrel)
end
B.docks = function(cf, rng, m)
	planks(cf, rng, m, 12)
	-- a fisher's hut at the land end, a lantern on a post
	local hut = cf * CFrame.new(-9, 0, -12)
	part(m, Vector3.new(9, 9, 8), hut * CFrame.new(0, 2.5, 0), rgb(120, 88, 58), M.WoodPlanks)
	part(m, Vector3.new(3, 4.4, 0.3), hut * CFrame.new(0, 1.4, 4.1), rgb(60, 44, 32), M.Wood)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(6.2, 0.6, 10), hut * CFrame.new(sx * 2.6, 8.4, 0) * CFrame.Angles(0, 0, math.rad(sx * -32)), rgb(70, 130, 56), M.Grass)
	end
	part(m, Vector3.new(0.6, 6, 0.6), cf * CFrame.new(5, 3, -2), POST, M.Wood)
	glow(m, Vector3.new(1, 1.2, 1), cf * CFrame.new(5, 6.4, -2), rgb(255, 190, 90))
	-- an abandoned boat by it, half sunk
	local boat = cf * CFrame.new(9, -0.6, 16) * CFrame.Angles(math.rad(8), math.rad(20), math.rad(14))
	part(m, Vector3.new(4, 1.4, 10), boat, rgb(96, 70, 48), M.WoodPlanks)
	for _, s in ipairs({ -1.9, 1.9 }) do part(m, Vector3.new(0.4, 1.6, 10), boat * CFrame.new(s, 0.9, 0), rgb(84, 62, 42), M.WoodPlanks) end
end
-- the wreck: a galleon run aground, heeled over in the shallows, its hull
-- stove in, two masts with torn black sails (cf faces inland: the ship lies
-- along its X)
B.shipwreck = function(cf, rng, m)
	local HULL, DARK, TRIM = rgb(92, 64, 44), rgb(62, 44, 32), rgb(120, 92, 60)
	local ship = cf * CFrame.new(0, -0.5, 10) * CFrame.Angles(0, 0, math.rad(-14)) * CFrame.Angles(math.rad(6), 0, 0)
	local N = 7
	for i = -N, N do
		local f = math.abs(i) / (N + 1)
		local w = 15 * (1 - f * f)
		local x = i * 4
		local holed = i >= -2 and i <= 1 -- (stove in amidships, on the beach side)
		-- keel, the belly, the sides, the rail
		part(m, Vector3.new(4.1, 3, w * 0.45), ship * CFrame.new(x, 0, 0), DARK, M.WoodPlanks)
		part(m, Vector3.new(4.1, 3, w * 0.8), ship * CFrame.new(x, 3, 0), HULL, M.WoodPlanks)
		for _, side in ipairs({ -1, 1 }) do
			if holed and side == -1 and rng:NextNumber() < 0.7 then continue end
			part(m, Vector3.new(4.1, 5, 1.2), ship * CFrame.new(x, 6.5, side * (w / 2 - 0.6)), if i % 2 == 0 then HULL else DARK, M.WoodPlanks)
			part(m, Vector3.new(4.1, 0.8, 1.5), ship * CFrame.new(x, 9.3, side * (w / 2 - 0.6)), TRIM, M.Wood)
		end
		if not holed then part(m, Vector3.new(4.1, 0.6, w - 2), ship * CFrame.new(x, 8.4, 0), TRIM, M.WoodPlanks) end
	end
	-- the stern castle, the bowsprit
	part(m, Vector3.new(10, 7, 12), ship * CFrame.new(-N * 4 + 3, 12, 0), HULL, M.WoodPlanks)
	part(m, Vector3.new(10.4, 0.8, 12.4), ship * CFrame.new(-N * 4 + 3, 15.8, 0), TRIM, M.Wood)
	for k = -1, 1 do glow(m, Vector3.new(0.4, 1.6, 1.6), ship * CFrame.new(-N * 4 - 2.05, 12, k * 3.5), rgb(255, 180, 80)) end
	cyl(m, 16, 1.4, ship * CFrame.new(N * 4 + 7, 10, 0) * CFrame.Angles(0, 0, math.rad(-70)), DARK, M.Wood)
	-- the masts: one standing, one snapped
	for mi, mx in ipairs({ 6, -10 }) do
		local h = if mi == 1 then 34 else 22
		cyl(m, h, 1.8, ship * CFrame.new(mx, 8 + h / 2, 0), DARK, M.Wood)
		for _, yy in ipairs(if mi == 1 then { 0.55, 0.9 } else { 0.8 }) do
			local y = 8 + h * yy
			part(m, Vector3.new(1, 1, 18), ship * CFrame.new(mx, y, 0) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, 0), DARK, M.Wood)
			-- a torn sail hanging from the yard, in two ragged pieces
			local sh = h * 0.22
			part(m, Vector3.new(0.3, sh, 7), ship * CFrame.new(mx + 0.8, y - sh / 2, -4.5), rgb(46, 44, 48), M.Fabric, { CanCollide = false })
			part(m, Vector3.new(0.3, sh * 0.65, 6), ship * CFrame.new(mx + 0.8, y - sh * 0.33, 4.5), rgb(56, 52, 56), M.Fabric, { CanCollide = false })
		end
	end
	-- spilled cargo and planks on the sand
	for _ = 1, 7 do
		local at = cf * CFrame.new(rng:NextNumber(-26, 26), 0.4, rng:NextNumber(-14, -2)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
		if rng:NextNumber() < 0.5 then
			part(m, Vector3.one * rng:NextNumber(2.4, 3.4), at * CFrame.new(0, 1, 0), rgb(124, 92, 58), M.WoodPlanks)
		else
			part(m, Vector3.new(rng:NextNumber(5, 9), 0.5, 1.4), at, HULL, M.WoodPlanks)
		end
	end
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
	cyl(m, h, h * 0.3, cf * CFrame.new(0, h / 2, 0), rgb(220, 210, 190), M.SmoothPlastic, { CanCollide = false })
	local c = cyl(m, h * 0.3, h * 1.1, cf * CFrame.new(0, h, 0), cap, M.Neon, { CanCollide = false })
	c.Transparency = 0.15
end
B.log = function(cf, rng, m)
	local l = rng:NextNumber(9, 16)
	cyl(m, l, rng:NextNumber(1.8, 2.8), cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		rgb(84, 64, 50), M.Wood)
end
-- a hunter's camp: a fire still burning, a timber shelter, a fence, logs to sit on
B.camp = function(cf, rng, m)
	local WOOD, DARK = rgb(124, 90, 56), rgb(84, 60, 42)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		part(m, Vector3.new(1.3, 1, 1.3), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.4, -2.4), rgb(90, 88, 92), M.Slate)
	end
	for k = 0, 2 do part(m, Vector3.new(0.6, 0.6, 3), cf * CFrame.Angles(0, k * 1.1, 0) * CFrame.new(0, 0.5, 0), DARK, M.Wood) end
	local fire = glow(m, Vector3.new(1.6, 0.8, 1.6), cf * CFrame.new(0, 0.9, 0), rgb(255, 150, 50))
	emit(fire, { Texture = FIRE, Color = ColorSequence.new(rgb(255, 210, 110), rgb(255, 100, 30)), Size = seq(2.4, 0.4), Transparency = seq(0.15, 1),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(3, 6), Rate = 16, LightEmission = 1 })
	-- logs round it
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2 + 0.5
		cyl(m, 5, 1.4, cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.7, -6) * CFrame.Angles(0, 0, math.rad(90)), DARK, M.Wood)
	end
	-- the shelter: four posts, beams, a slatted roof
	local sh = cf * CFrame.new(0, 0, 12)
	for _, c in ipairs({ { -6, -4 }, { 6, -4 }, { -6, 4 }, { 6, 4 } }) do
		part(m, Vector3.new(1, 9, 1), sh * CFrame.new(c[1], 4.5, c[2]), WOOD, M.Wood)
	end
	for _, z in ipairs({ -4, 4 }) do part(m, Vector3.new(14, 1, 1), sh * CFrame.new(0, 9, z), DARK, M.Wood) end
	for k = -3, 3 do
		if rng:NextNumber() < 0.2 then continue end
		part(m, Vector3.new(1.4, 0.4, 10), sh * CFrame.new(k * 2, 9.7, 0) * CFrame.Angles(math.rad(8), 0, 0), WOOD, M.WoodPlanks)
	end
	part(m, Vector3.new(3, 2.4, 3), sh * CFrame.new(-3, 1.2, 1), rgb(124, 92, 58), M.WoodPlanks)
	-- a fence along one side
	local fence = cf * CFrame.new(-14, 0, 0) * CFrame.Angles(0, math.rad(90), 0)
	for k = -3, 3 do part(m, Vector3.new(0.7, 4, 0.7), fence * CFrame.new(k * 3.4, 2, 0), DARK, M.Wood) end
	for _, y in ipairs({ 1.6, 3.2 }) do part(m, Vector3.new(21, 0.5, 0.5), fence * CFrame.new(0, y, 0), WOOD, M.Wood) end
end

-- ── Ruins ───────────────────────────────────────────────────────────────────
local STONE, STONE2, MOSS = rgb(132, 128, 118), rgb(108, 106, 100), rgb(80, 110, 70)
B.pillar = function(cf, rng, m)
	local h = rng:NextNumber(5, 16)
	local broken = rng:NextNumber() < 0.6
	part(m, Vector3.new(4, 1, 4), cf * CFrame.new(0, 0.3, 0), STONE2, M.Slate)
	cyl(m, h, 2.8, cf * CFrame.new(0, h / 2 + 0.6, 0), STONE, M.Slate)
	if not broken then part(m, Vector3.new(4, 1, 4), cf * CFrame.new(0, h + 1, 0), STONE2, M.Slate) end
	if rng:NextNumber() < 0.5 then part(m, Vector3.new(3, 0.4, 3), cf * CFrame.new(0.4, h * 0.5, 0) * CFrame.Angles(0, 0, math.rad(80)), MOSS, M.Grass, { CanCollide = false }) end
	if broken and rng:NextNumber() < 0.5 then -- (its fallen top beside it)
		cyl(m, h * 0.5, 2.8, cf * CFrame.new(3.5, 1.4, 0) * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.Angles(0, 0, math.rad(90)), STONE, M.Slate)
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
		cyl(m, h, 2.6, top * CFrame.new(c[1], h / 2, c[2]), STONE, M.Marble)
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

-- ── The concept's landmarks ─────────────────────────────────────────────────
-- the ruined arcade: a row of mossy stone arches carrying a broken aqueduct
-- (water still glowing in its channel), a blue-lit statue before it
B.arches = function(cf, rng, m)
	local ST, ST2, MS = rgb(120, 122, 132), rgb(100, 102, 114), rgb(78, 132, 60)
	local row = cf * CFrame.new(0, 0, 6)
	local piers = { -27, -9, 9, 27 }
	for _, x in ipairs(piers) do
		part(m, Vector3.new(5, 20, 6), row * CFrame.new(x, 9.5, 0), ST, M.Slate)
		part(m, Vector3.new(6, 1.4, 7), row * CFrame.new(x, 0.2, 0), ST2, M.Slate)
	end
	for k = 1, #piers - 1 do
		local x = (piers[k] + piers[k + 1]) / 2
		if k == 3 and rng:NextNumber() < 0.6 then continue end -- (a span fallen)
		part(m, Vector3.new(13, 4, 6), row * CFrame.new(x, 18, 0), ST2, M.Slate)
		-- the arch's shoulders
		for _, sx in ipairs({ -1, 1 }) do part(m, Vector3.new(2.6, 2.6, 6), row * CFrame.new(x + sx * 5.2, 15, 0), ST2, M.Slate) end
	end
	-- the aqueduct on top: walls, a glowing channel, moss
	part(m, Vector3.new(60, 2, 7), row * CFrame.new(0, 21, 0), ST, M.Slate)
	for _, z in ipairs({ -3, 3 }) do part(m, Vector3.new(60, 2.4, 1), row * CFrame.new(0, 23, z), ST2, M.Slate) end
	glow(m, Vector3.new(58, 0.4, 4.6), row * CFrame.new(0, 22.3, 0), rgb(90, 190, 255), { Transparency = 0.15 })
	for _ = 1, 6 do
		part(m, Vector3.new(rng:NextNumber(4, 9), 0.8, 7.4), row * CFrame.new(rng:NextNumber(-26, 26), 24.4, 0), MS, M.Grass, { CanCollide = false })
	end
	-- a second storey's broken piers
	for _, x in ipairs({ -27, -9, 27 }) do
		local h = rng:NextNumber(5, 11)
		part(m, Vector3.new(4, h, 5), row * CFrame.new(x, 24 + h / 2, 0), ST, M.Slate)
	end
	-- fallen blocks, the statue in front, lit blue
	for _ = 1, 6 do
		local s = rng:NextNumber(2.5, 4.5)
		part(m, Vector3.new(s, s * 0.8, s * 1.3), row * CFrame.new(rng:NextNumber(-30, 30), s * 0.35, rng:NextNumber(-14, -6)) * CFrame.Angles(0, rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-10, 10))), ST2, M.Slate)
	end
	local st = cf * CFrame.new(14, 0, -10)
	part(m, Vector3.new(5, 2.4, 5), st * CFrame.new(0, 1.2, 0), ST2, M.Slate)
	part(m, Vector3.new(2.6, 7, 2), st * CFrame.new(0, 6, 0), rgb(170, 196, 220), M.Marble)
	part(m, Vector3.new(1.8, 1.8, 1.8), st * CFrame.new(0, 10.4, 0), rgb(170, 196, 220), M.Marble)
	glow(m, Vector3.new(3.2, 7.4, 0.3), st * CFrame.new(0, 6, -1.1), rgb(110, 200, 255), { Transparency = 0.5 })
end

-- the stone circle: standing stones round a fire pit on a paved floor
B.stone_circle = function(cf, rng, m)
	local ST, ST2 = rgb(116, 116, 124), rgb(92, 92, 102)
	cyl(m, 1, 34, cf * CFrame.new(0, 0.2, 0), ST2, M.Slate)
	cyl(m, 1.1, 14, cf * CFrame.new(0, 0.3, 0), ST, M.Cobblestone)
	local stones = {}
	for k = 0, 8 do
		local a = k / 9 * math.pi * 2
		local at = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -14)
		local h = rng:NextNumber(8, 13)
		if k % 4 == 2 then h = rng:NextNumber(3, 5) end -- (a few broken)
		part(m, Vector3.new(3.4, h, 2.4), at * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-4, 4))), if k % 2 == 0 then ST else ST2, M.Slate)
		table.insert(stones, { at = at, h = h })
	end
	for k = 1, #stones - 1, 3 do
		local a, b = stones[k], stones[k + 1]
		if a.h > 7 and b.h > 7 then
			local pa, pb = (a.at * CFrame.new(0, math.min(a.h, b.h) + 0.8, 0)).Position, (b.at * CFrame.new(0, math.min(a.h, b.h) + 0.8, 0)).Position
			part(m, Vector3.new(3, 1.6, (pb - pa).Magnitude + 3), CFrame.lookAt((pa + pb) / 2, pb), ST2, M.Slate)
		end
	end
	-- the fire pit
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		part(m, Vector3.new(2, 1.4, 1.6), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 1, -4), ST2, M.Slate)
	end
	local fire = glow(m, Vector3.new(5, 0.6, 5), cf * CFrame.new(0, 1.1, 0), rgb(255, 130, 40))
	emit(fire, { Texture = FIRE, Color = ColorSequence.new(rgb(255, 220, 120), rgb(255, 90, 30)), Size = seq(4, 0.6), Transparency = seq(0.1, 1),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(5, 9), Rate = 22, LightEmission = 1 })
	emit(fire, { Texture = SMOKE, Color = ColorSequence.new(rgb(60, 56, 60)), Size = seq(3, 8), Transparency = seq(0.6, 1),
		Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(4, 6), Rate = 4 })
end

-- the infernal citadel: a black keep on the volcano, its gate a glowing red
-- eye, towers round it, one pouring lava down its face, torches burning
B.citadel = function(cf, rng, m)
	local BS, BS2, RED = rgb(40, 34, 38), rgb(56, 48, 52), rgb(255, 60, 40)
	-- the terrace it stands on, steps up to the gate
	part(m, Vector3.new(52, 4, 46), cf * CFrame.new(0, 1, 6), BS2, M.Basalt)
	for k = 0, 3 do part(m, Vector3.new(14, 1, 3), cf * CFrame.new(0, 0.5 + k, -17 - (3 - k) * 3 + 6), BS2, M.Basalt) end
	-- the keep
	local keep = cf * CFrame.new(0, 3, 10)
	part(m, Vector3.new(30, 28, 24), keep * CFrame.new(0, 14, 0), BS, M.Basalt)
	for k = -3, 3 do
		part(m, Vector3.new(2.6, 3, 2.6), keep * CFrame.new(k * 4.4, 29.5, -11), BS, M.Basalt)
		part(m, Vector3.new(2.6, 3, 2.6), keep * CFrame.new(k * 4.4, 29.5, 11), BS, M.Basalt)
	end
	-- the gate: a dark arch, the red eye above it
	part(m, Vector3.new(10, 12, 1), keep * CFrame.new(0, 6, -12.2), rgb(18, 14, 16), M.Slate)
	part(m, Vector3.new(13, 2, 2), keep * CFrame.new(0, 13, -12.6), BS2, M.Basalt)
	glow(m, Vector3.new(4.4, 4.4, 0.5), keep * CFrame.new(0, 18, -12.3) * CFrame.Angles(0, 0, math.rad(45)), RED)
	glow(m, Vector3.new(1.6, 1.6, 0.6), keep * CFrame.new(0, 18, -12.5) * CFrame.Angles(0, 0, math.rad(45)), rgb(255, 220, 120))
	-- the towers: four round the keep, the tallest behind, its lava fall
	for _, t in ipairs({ { -19, -6, 34 }, { 19, -6, 30 }, { -17, 20, 40 }, { 17, 20, 38 }, { 0, 26, 52 } }) do
		local w = if t[3] > 45 then 11 else 8
		local at = cf * CFrame.new(t[1], 3, t[2])
		part(m, Vector3.new(w, t[3], w), at * CFrame.new(0, t[3] / 2, 0), if rng:NextNumber() < 0.5 then BS else BS2, M.Basalt)
		for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
			part(m, Vector3.new(2.4, 3.4, 2.4), at * CFrame.new(c[1] * (w / 2 - 1.2), t[3] + 1.7, c[2] * (w / 2 - 1.2)), BS, M.Basalt)
		end
		glow(m, Vector3.new(1.4, 3, 0.4), at * CFrame.new(0, t[3] * 0.7, -w / 2 - 0.1), rgb(255, 120, 40)) -- (a lit window)
		if t[3] > 45 then
			glow(m, Vector3.new(3.4, t[3] - 4, 0.6), at * CFrame.new(0, t[3] / 2, -w / 2 - 0.3), rgb(255, 100, 30))
		end
	end
	-- torches either side of the gate, lava channels down the terrace
	for _, sx in ipairs({ -1, 1 }) do
		local tp = cf * CFrame.new(sx * 9, 3, -6)
		part(m, Vector3.new(1, 5, 1), tp * CFrame.new(0, 2.5, 0), BS2, M.Basalt)
		local fl = glow(m, Vector3.new(1.4, 1.4, 1.4), tp * CFrame.new(0, 5.6, 0), rgb(255, 150, 50))
		emit(fl, { Texture = FIRE, Color = ColorSequence.new(rgb(255, 210, 110), rgb(255, 90, 30)), Size = seq(1.6, 0.2), Transparency = seq(0.2, 1),
			Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 4), Rate = 10, LightEmission = 1 })
		glow(m, Vector3.new(3, 0.4, 40), cf * CFrame.new(sx * 22, 3.1, 4), rgb(255, 100, 30))
	end
end

-- ── The biomes' own pieces ──────────────────────────────────────────────────
-- The Shipwreck Coast: turquoise water, pale sand, weathered wood, faded blue
local DRIFT, DRIFT2, FADED = rgb(132, 104, 76), rgb(96, 74, 54), rgb(96, 130, 160)
B.barrel = function(cf, rng, m)
	local n = rng:NextInteger(1, 3)
	for k = 1, n do
		local at = cf * CFrame.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		if k == 3 or rng:NextNumber() < 0.25 then
			-- (one on its side)
			cyl(m, 3, 2.2, at * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), DRIFT, M.WoodPlanks)
		else
			cyl(m, 3, 2.2, at * CFrame.new(0, 1.5, 0), DRIFT, M.WoodPlanks)
			for _, y in ipairs({ 0.6, 2.4 }) do cyl(m, 0.25, 2.35, at * CFrame.new(0, y, 0), rgb(70, 66, 64), M.Metal) end
		end
	end
end
B.anchor = function(cf, rng, m)
	local IRON = rgb(64, 62, 66)
	local a = cf * CFrame.Angles(math.rad(rng:NextNumber(55, 75)), 0, 0)
	part(m, Vector3.new(0.8, 9, 0.8), a * CFrame.new(0, 4.5, 0), IRON, M.CorrodedMetal)
	part(m, Vector3.new(4, 0.7, 0.7), a * CFrame.new(0, 8, 0), IRON, M.CorrodedMetal)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(2.6, 0.8, 0.8), a * CFrame.new(sx * 1.4, 0.7, 0) * CFrame.Angles(0, 0, math.rad(sx * 35)), IRON, M.CorrodedMetal)
	end
	cyl(m, 0.5, 2, a * CFrame.new(0, 9.6, 0) * CFrame.Angles(math.rad(90), 0, 0), IRON, M.CorrodedMetal)
end
-- a fishing net strung between two posts, floats along its top
B.net = function(cf, rng, m)
	for _, sx in ipairs({ -4, 4 }) do part(m, Vector3.new(0.6, 6, 0.6), cf * CFrame.new(sx, 3, 0), DRIFT2, M.Wood) end
	part(m, Vector3.new(8, 4.4, 0.1), cf * CFrame.new(0, 3.4, 0) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), 0, 0), rgb(150, 140, 110), M.Fabric,
		{ Transparency = 0.45, CanCollide = false })
	for k = -2, 2 do ball(m, 0.7, cf * CFrame.new(k * 1.6, 5.6, 0), if k % 2 == 0 then rgb(220, 120, 60) else FADED, M.SmoothPlastic) end
end
-- a tide pool: a ring of rocks round clear water, a starfish, weed
B.tidepool = function(cf, rng, m)
	local r = rng:NextNumber(3, 4.5)
	part(m, Vector3.new(r * 2, 0.5, r * 2), cf * CFrame.new(0, 0.35, 0), rgb(60, 190, 200), M.Glass, { Transparency = 0.35, CanCollide = false })
	for k = 0, 8 do
		local a = k / 9 * math.pi * 2
		local s2 = rng:NextNumber(1.2, 2.2)
		part(m, Vector3.new(s2, s2 * 0.7, s2), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.4, -r) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), rgb(110, 108, 104), M.Slate)
	end
	part(m, Vector3.new(1, 0.25, 1), cf * CFrame.new(rng:NextNumber(-1, 1), 0.65, rng:NextNumber(-1, 1)) * CFrame.Angles(0, 0.6, 0), rgb(240, 120, 80), M.SmoothPlastic, { CanCollide = false })
	for _ = 1, 3 do
		part(m, Vector3.new(0.3, rng:NextNumber(1, 2), 0.3), cf * CFrame.new(rng:NextNumber(-2, 2), 0.8, rng:NextNumber(-2, 2)), rgb(70, 140, 70), M.Grass, { CanCollide = false })
	end
end
B.shell = function(cf, rng, m)
	local c = ({ rgb(250, 220, 200), rgb(240, 180, 160), rgb(230, 230, 210) })[rng:NextInteger(1, 3)]
	part(m, Vector3.new(0.9, 0.35, 0.7), cf * CFrame.new(0, 0.3, 0), c, M.SmoothPlastic, { CanCollide = false })
	part(m, Vector3.new(0.5, 0.3, 0.5), cf * CFrame.new(rng:NextNumber(1, 2), 0.25, rng:NextNumber(-1, 1)) * CFrame.Angles(0, 0.8, 0), rgb(240, 150, 120), M.SmoothPlastic, { CanCollide = false })
end
-- a ruined watchtower: four leaning legs, a platform, a torn faded-blue flag
B.watchtower = function(cf, rng, m)
	local lean = cf * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), 0, math.rad(rng:NextNumber(-6, 6)))
	for _, c in ipairs({ { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }) do part(m, Vector3.new(1, 18, 1), lean * CFrame.new(c[1], 9, c[2]), DRIFT2, M.Wood) end
	for _, y in ipairs({ 5, 11 }) do
		part(m, Vector3.new(7, 0.6, 0.6), lean * CFrame.new(0, y, -3) * CFrame.Angles(0, 0, math.rad(30)), DRIFT, M.Wood)
		part(m, Vector3.new(0.6, 0.6, 7), lean * CFrame.new(3, y, 0) * CFrame.Angles(math.rad(30), 0, 0), DRIFT, M.Wood)
	end
	part(m, Vector3.new(9, 0.8, 9), lean * CFrame.new(0, 18, 0), DRIFT, M.WoodPlanks)
	for k = -1, 1, 2 do part(m, Vector3.new(9, 2.4, 0.5), lean * CFrame.new(0, 19.6, k * 4.3), DRIFT2, M.WoodPlanks) end
	part(m, Vector3.new(0.5, 2.4, 6), lean * CFrame.new(-4.3, 19.6, -1.5), DRIFT2, M.WoodPlanks)
	part(m, Vector3.new(0.4, 8, 0.4), lean * CFrame.new(3.5, 22, 3.5), DRIFT2, M.Wood)
	part(m, Vector3.new(0.1, 2.4, 4), lean * CFrame.new(3.5, 24.6, 1.5), FADED, M.Fabric, { CanCollide = false })
end
-- a half-buried treasure chest beside a wrecked rowboat
B.rowboat_chest = function(cf, rng, m)
	local boat = cf * CFrame.new(3, 0.3, 0) * CFrame.Angles(0, 0, math.rad(-28)) * CFrame.Angles(0, math.rad(20), 0)
	part(m, Vector3.new(4, 1, 10), boat, DRIFT2, M.WoodPlanks)
	for _, sx in ipairs({ -1.9, 1.9 }) do part(m, Vector3.new(0.4, 1.6, 10), boat * CFrame.new(sx, 0.8, 0), DRIFT, M.WoodPlanks) end
	part(m, Vector3.new(0.4, 0.3, 6), boat * CFrame.new(0, 1.2, 2) * CFrame.Angles(0, 0.4, 0), DRIFT, M.Wood) -- (an oar)
	local chest = cf * CFrame.new(-3, 0.2, 1) * CFrame.Angles(math.rad(14), 0.5, math.rad(8))
	part(m, Vector3.new(3, 2, 2), chest, rgb(120, 80, 40), M.WoodPlanks)
	part(m, Vector3.new(3.1, 0.3, 2.1), chest * CFrame.new(0, 0.6, 0), rgb(210, 170, 70), M.Metal)
	glow(m, Vector3.new(1.6, 0.3, 1), chest * CFrame.new(0, 1.05, 0), rgb(255, 210, 90))
	for _ = 1, 4 do glow(m, Vector3.new(0.5, 0.15, 0.5), cf * CFrame.new(rng:NextNumber(-5, -1), 0.3, rng:NextNumber(-1, 3)), rgb(255, 205, 80)) end
end

-- The Verdant Ruins: jungle green, mossy stone, golden light
B.fern = function(cf, rng, m)
	local g = ({ rgb(70, 150, 50), rgb(90, 170, 60), rgb(56, 130, 46) })[rng:NextInteger(1, 3)]
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + rng:NextNumber(0, 0.5)
		part(m, Vector3.new(0.8, 0.2, 3.4), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.9, -1.4) * CFrame.Angles(math.rad(28), 0, 0), g, M.Grass, { CanCollide = false })
	end
end
B.flower = function(cf, rng, m)
	local c = ({ rgb(255, 210, 80), rgb(255, 120, 150), rgb(250, 250, 240), rgb(255, 150, 60) })[rng:NextInteger(1, 4)]
	for _ = 1, rng:NextInteger(3, 6) do
		local at = cf * CFrame.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
		local h = rng:NextNumber(0.8, 1.6)
		part(m, Vector3.new(0.2, h, 0.2), at * CFrame.new(0, h / 2, 0), rgb(70, 130, 50), M.Grass, { CanCollide = false })
		part(m, Vector3.new(0.6, 0.35, 0.6), at * CFrame.new(0, h, 0), c, M.SmoothPlastic, { CanCollide = false })
	end
end
-- a great carved stone face, moss on its brow, its eyes glowing faint green
B.stoneface = function(cf, rng, m)
	local ST, ST2 = rgb(118, 122, 118), rgb(98, 104, 100)
	local f = cf * CFrame.Angles(math.rad(rng:NextNumber(-6, 4)), 0, math.rad(rng:NextNumber(-5, 5)))
	part(m, Vector3.new(10, 12, 8), f * CFrame.new(0, 5.5, 0), ST, M.Slate)
	part(m, Vector3.new(10.4, 1.2, 8.4), f * CFrame.new(0, 11.8, 0), rgb(80, 140, 60), M.Grass, { CanCollide = false })
	part(m, Vector3.new(8, 1.4, 1.2), f * CFrame.new(0, 8, -4.3), ST2, M.Slate) -- (the brow)
	for _, sx in ipairs({ -2.2, 2.2 }) do
		part(m, Vector3.new(2, 1.4, 0.5), f * CFrame.new(sx, 6.6, -4.1), rgb(20, 24, 22), M.Slate)
		glow(m, Vector3.new(0.8, 0.6, 0.2), f * CFrame.new(sx, 6.6, -4.4), rgb(120, 255, 140))
	end
	part(m, Vector3.new(2, 3, 1.6), f * CFrame.new(0, 4.6, -4.4), ST2, M.Slate) -- (the nose)
	part(m, Vector3.new(5, 1, 0.6), f * CFrame.new(0, 2, -4.1), rgb(30, 34, 32), M.Slate) -- (the mouth)
	for _ = 1, 4 do
		part(m, Vector3.new(0.4, rng:NextNumber(3, 7), 0.3), f * CFrame.new(rng:NextNumber(-4.5, 4.5), 8, -4.2), rgb(60, 130, 50), M.Grass, { CanCollide = false }) -- (vines)
	end
end
-- a fallen carved slab, its symbols glowing faint green in the cracks
B.glyph = function(cf, rng, m)
	local slab = cf * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, math.rad(rng:NextNumber(-80, -60)))
	part(m, Vector3.new(6, 1.4, 4), slab * CFrame.new(0, 1, 0), rgb(110, 114, 110), M.Slate)
	for k = -1, 1 do
		glow(m, Vector3.new(0.8, 0.1, 0.8), slab * CFrame.new(k * 1.7, 1.75, rng:NextNumber(-0.8, 0.8)) * CFrame.Angles(0, math.rad(45), 0), rgb(110, 255, 130), { Transparency = 0.3 })
	end
end

-- The Corrupted Forest: violet, blackened wood, magenta glow
local VOID, MAGENTA, CRYS = rgb(36, 26, 44), rgb(255, 60, 200), rgb(170, 80, 255)
B.corrupt_crystal = function(cf, rng, m)
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(3, 9)
		local w = h * rng:NextNumber(0.22, 0.32)
		local at = cf * CFrame.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2))
			* CFrame.Angles(math.rad(rng:NextNumber(-28, 28)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-28, 28)))
		local c = glow(m, Vector3.new(w, h, w), at * CFrame.new(0, h / 2 - 0.5, 0), if rng:NextNumber() < 0.5 then CRYS else MAGENTA)
		c.Transparency = 0.15
		c.CanCollide = true
		part(m, Vector3.new(w * 0.7, w * 0.7, w * 0.7), at * CFrame.new(0, h, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45)), rgb(230, 170, 255), M.Neon, { CanCollide = false, CastShadow = false })
	end
end
-- corrupted roots crawling over the ground, glowing veins along them
B.roots = function(cf, rng, m)
	for k = 0, rng:NextInteger(4, 6) do
		local a = k * 1.2 + rng:NextNumber(0, 0.6)
		local len = rng:NextNumber(5, 10)
		local r = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.4, -len / 2) * CFrame.Angles(math.rad(rng:NextNumber(-6, 4)), rng:NextNumber(-0.3, 0.3), 0)
		part(m, Vector3.new(rng:NextNumber(0.7, 1.2), 0.8, len), r, VOID, M.Wood, { CanCollide = false })
		if k % 2 == 0 then glow(m, Vector3.new(0.2, 0.2, len * 0.8), r * CFrame.new(0, 0.45, 0), MAGENTA, { Transparency = 0.25 }) end
	end
end
-- an abandoned shrine: a black stone frame, a cold violet flame, offerings
B.shrine = function(cf, rng, m)
	local S = rgb(50, 44, 58)
	part(m, Vector3.new(7, 1, 5), cf * CFrame.new(0, 0.5, 0), S, M.Slate)
	for _, sx in ipairs({ -2.6, 2.6 }) do part(m, Vector3.new(1.2, 7, 1.2), cf * CFrame.new(sx, 4, 0), S, M.Slate) end
	part(m, Vector3.new(7.4, 1.2, 1.8), cf * CFrame.new(0, 8, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-6, 6))), S, M.Slate)
	part(m, Vector3.new(2, 2, 2), cf * CFrame.new(0, 2, 0), rgb(40, 34, 46), M.Slate)
	local fl = glow(m, Vector3.new(0.8, 1.4, 0.8), cf * CFrame.new(0, 3.7, 0), CRYS)
	emit(fl, { Texture = FIRE, Color = ColorSequence.new(rgb(220, 160, 255), CRYS), Size = seq(1.4, 0.2), Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(1.5, 3), Rate = 8, LightEmission = 1 })
end
-- a shattered statue: legs on a plinth, its torso and head in pieces beside it
B.broken_statue = function(cf, rng, m)
	local ST = rgb(120, 116, 128)
	part(m, Vector3.new(5, 2, 5), cf * CFrame.new(0, 1, 0), rgb(80, 76, 88), M.Slate)
	for _, sx in ipairs({ -0.8, 0.8 }) do part(m, Vector3.new(1.2, 4, 1.4), cf * CFrame.new(sx, 4, 0), ST, M.Marble) end
	part(m, Vector3.new(3, 4, 1.6), cf * CFrame.new(4, 1, 2) * CFrame.Angles(math.rad(80), 0, math.rad(20)), ST, M.Marble)
	part(m, Vector3.new(2, 2, 2), cf * CFrame.new(-3.5, 1, 2.5) * CFrame.Angles(0.4, 0.8, 0.2), ST, M.Marble)
	if rng:NextNumber() < 0.6 then glow(m, Vector3.new(1.2, 0.2, 2.4), cf * CFrame.new(0, 2.05, 0), MAGENTA, { Transparency = 0.3 }) end
end
-- a rock fragment floating over the ground, a glow beneath it
B.floatrock = function(cf, rng, m)
	local s2 = rng:NextNumber(2.5, 6)
	local y = rng:NextNumber(6, 14)
	part(m, Vector3.new(s2, s2 * 0.7, s2 * 0.9), cf * CFrame.new(0, y, 0) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6), rng:NextNumber(-0.4, 0.4)), rgb(58, 50, 68), M.Slate)
	part(m, Vector3.new(s2 * 0.5, s2 * 0.4, s2 * 0.5), cf * CFrame.new(0, y - s2 * 0.5, 0) * CFrame.Angles(0.3, 0.5, 0.2), rgb(48, 40, 58), M.Slate)
	glow(m, Vector3.new(s2 * 0.4, 0.2, s2 * 0.4), cf * CFrame.new(0, y - s2 * 0.75, 0), CRYS, { Transparency = 0.2 })
end
-- a dark pool reflecting purple light, mist over it
B.darkpool = function(cf, rng, m)
	local r = rng:NextNumber(4, 7)
	local pool = glow(m, Vector3.new(r * 2, 0.3, r * 1.6), cf * CFrame.new(0, 0.25, 0), rgb(70, 20, 110), { Transparency = 0.1 })
	part(m, Vector3.new(r * 2 + 1.5, 0.2, r * 1.6 + 1.5), cf * CFrame.new(0, 0.12, 0), rgb(20, 16, 26), M.Ground, { CanCollide = false })
	emit(pool, { Texture = SMOKE, Color = ColorSequence.new(rgb(150, 90, 220)), Size = seq(3, 8), Transparency = seq(0.75, 1),
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(0.5, 1.5), Rate = 3, Shape = Enum.ParticleEmitterShape.Box })
end
-- the Hollow Heart: a gigantic dead tree, its trunk split open on a glowing
-- purple core, black roots and crystals round it
B.grove = function(cf, rng, m)
	local BARK = rgb(30, 24, 32)
	local tr = cf
	-- the trunk: stacked, narrowing, twisting blocks, split down its front
	local y = 0
	for k = 0, 6 do
		local w = 14 - k * 1.5
		local h = 7
		local seg = tr * CFrame.new(0, y + h / 2, 0) * CFrame.Angles(0, math.rad(k * 9), math.rad(math.sin(k) * 3))
		for _, sx in ipairs({ -1, 1 }) do
			part(m, Vector3.new(w * 0.42, h, w), seg * CFrame.new(sx * w * 0.3, 0, 0), BARK, M.Wood)
		end
		part(m, Vector3.new(w * 0.3, h, w * 0.3), seg * CFrame.new(0, 0, w * 0.35), BARK, M.Wood)
		y += h
	end
	-- the core: a glowing heart in the split
	local core = glow(m, Vector3.new(3.4, 10, 3), tr * CFrame.new(0, 10, -1.5), MAGENTA)
	glow(m, Vector3.new(5, 14, 0.6), tr * CFrame.new(0, 12, -3), CRYS, { Transparency = 0.45 })
	emit(core, { Texture = SPARK, Color = ColorSequence.new(rgb(255, 150, 240), CRYS), Size = seq(0.8, 0), Transparency = seq(0.1, 1),
		Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(2, 5), Rate = 10, LightEmission = 1, SpreadAngle = Vector2.new(60, 60) })
	-- jagged bare branches
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2 + rng:NextNumber(0, 0.4)
		local by = rng:NextNumber(30, 46)
		local len = rng:NextNumber(10, 18)
		local br = tr * CFrame.new(0, by, 0) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(rng:NextNumber(-55, -30)), 0, 0)
		part(m, Vector3.new(1.6, 1.6, len), br * CFrame.new(0, 0, -len / 2), BARK, M.Wood)
		part(m, Vector3.new(1, 1, len * 0.5), br * CFrame.new(0, 0, -len) * CFrame.Angles(math.rad(-30), math.rad(rng:NextNumber(-40, 40)), 0) * CFrame.new(0, 0, -len * 0.25), BARK, M.Wood)
	end
	-- roots, and crystals among them
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local rt = tr * CFrame.Angles(0, a, 0) * CFrame.new(0, 1, -10) * CFrame.Angles(math.rad(14), 0, 0)
		part(m, Vector3.new(2.4, 2.4, 12), rt, BARK, M.Wood)
		if k % 2 == 0 then
			glow(m, Vector3.new(1.4, rng:NextNumber(4, 7), 1.4), tr * CFrame.Angles(0, a + 0.4, 0) * CFrame.new(0, 2, -15) * CFrame.Angles(0.3, 0, 0.2), CRYS, { Transparency = 0.15 })
		end
	end
end

-- The Sunken Sanctuary: luminous cyan, deep blue, teal stone
local TEAL, TEAL2, CYAN = rgb(92, 150, 150), rgb(70, 120, 128), rgb(90, 240, 255)
B.sunk_column = function(cf, rng, m)
	local h = rng:NextNumber(4, 14)
	part(m, Vector3.new(4, 1, 4), cf * CFrame.new(0, 0.3, 0), TEAL2, M.Slate)
	cyl(m, h, 2.8, cf * CFrame.new(0, h / 2 + 0.6, 0) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), 0, 0), TEAL, M.Slate)
	part(m, Vector3.new(2, 0.3, 1.6), cf * CFrame.new(0.6, h * 0.4, -1.3), rgb(240, 130, 150), M.SmoothPlastic, { CanCollide = false }) -- (coral)
end
B.blue_crystal = function(cf, rng, m)
	for _ = 1, rng:NextInteger(2, 4) do
		local h = rng:NextNumber(2.5, 7)
		local at = cf * CFrame.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-25, 25)))
		local c = glow(m, Vector3.new(h * 0.28, h, h * 0.28), at * CFrame.new(0, h / 2 - 0.4, 0), CYAN)
		c.Transparency = 0.15
	end
end
-- an ornate fountain: tiers of teal stone, glowing water
B.fountain = function(cf, rng, m)
	cyl(m, 1.4, 16, cf * CFrame.new(0, 0.7, 0), TEAL2, M.Slate)
	cyl(m, 0.6, 14, cf * CFrame.new(0, 1.3, 0), rgb(70, 200, 230), M.Glass, { Transparency = 0.3, CanCollide = false })
	cyl(m, 5, 2.4, cf * CFrame.new(0, 3.5, 0), TEAL, M.Slate)
	cyl(m, 0.8, 7, cf * CFrame.new(0, 6.2, 0), TEAL2, M.Slate)
	local jet = glow(m, Vector3.new(0.8, 3, 0.8), cf * CFrame.new(0, 8, 0), CYAN, { Transparency = 0.3 })
	emit(jet, { Texture = SPARK, Color = ColorSequence.new(rgb(200, 250, 255)), Size = seq(0.6, 0), Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(6, 9), Rate = 12, SpreadAngle = Vector2.new(25, 25), Acceleration = Vector3.new(0, -18, 0) })
end
-- the Drowned Gate: a gigantic doorway standing in the flooded heart, light
-- pouring through it; columns, sunken stairs, a fallen statue, a magic circle,
-- lily pads, hanging chains, a trident carving (cf: its foot, the pool's bed)
B.sunken_temple = function(cf, rng, m)
	local gate = cf * CFrame.new(0, 0, 6)
	-- the doorway
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(6, 30, 6), gate * CFrame.new(sx * 10, 15, 0), TEAL2, M.Slate)
		part(m, Vector3.new(7, 2, 7), gate * CFrame.new(sx * 10, 30.5, 0), TEAL, M.Slate)
		for k = 0, 2 do glow(m, Vector3.new(1, 1.6, 0.3), gate * CFrame.new(sx * 10, 8 + k * 7, -3.1), CYAN) end -- (crystals in the stone)
	end
	part(m, Vector3.new(28, 5, 7), gate * CFrame.new(0, 33, 0), TEAL, M.Slate)
	part(m, Vector3.new(10, 3, 7.4), gate * CFrame.new(0, 36.5, 0), TEAL2, M.Slate)
	local door = glow(m, Vector3.new(14, 30, 0.6), gate * CFrame.new(0, 15, 0), rgb(150, 245, 255), { Transparency = 0.25 })
	emit(door, { Texture = SPARK, Color = ColorSequence.new(rgb(200, 250, 255), CYAN), Size = seq(0.7, 0), Transparency = seq(0.1, 1),
		Lifetime = NumberRange.new(2, 4), Speed = NumberRange.new(1, 3), Rate = 10, LightEmission = 1, Shape = Enum.ParticleEmitterShape.Box,
		EmissionDirection = Enum.NormalId.Front })
	-- the trident carved over it
	glow(m, Vector3.new(0.6, 6, 0.3), gate * CFrame.new(0, 34, -3.6), CYAN)
	for _, sx in ipairs({ -1.4, 0, 1.4 }) do glow(m, Vector3.new(0.5, 1.8, 0.3), gate * CFrame.new(sx, 37.4, -3.6), CYAN) end
	glow(m, Vector3.new(3.4, 0.5, 0.3), gate * CFrame.new(0, 36.4, -3.6), CYAN)
	-- sunken stairs up to it
	for k = 0, 5 do part(m, Vector3.new(16, 1, 3), cf * CFrame.new(0, 0.5 + k, -8 + k * 2.4), TEAL2, M.Slate) end
	-- columns standing in the water round it, some broken
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local at = cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -20)
		local h = if k % 3 == 0 then rng:NextNumber(4, 8) else rng:NextNumber(12, 18)
		cyl(m, h, 3, at * CFrame.new(0, h / 2, 0), TEAL, M.Slate)
		part(m, Vector3.new(4, 1, 4), at * CFrame.new(0, h, 0), TEAL2, M.Slate)
		if h > 10 and k % 2 == 1 then -- (a chain hanging from it)
			for c = 0, 4 do part(m, Vector3.new(0.4, 1, 0.4), at * CFrame.new(1.8, h - 1 - c * 1.1, 0), rgb(60, 70, 74), M.Metal, { CanCollide = false }) end
		end
	end
	-- the magic circle on the water before the gate
	local ring = cyl(m, 0.3, 14, cf * CFrame.new(0, 8.2, -16), CYAN, M.Neon, { CanCollide = false, CanQuery = false })
	ring.Transparency = 0.55
	cyl(m, 0.35, 11, cf * CFrame.new(0, 8.25, -16), rgb(20, 60, 80), M.Slate, { CanCollide = false, CanQuery = false }).Transparency = 0.3
	-- a fallen statue half in the water
	part(m, Vector3.new(3, 9, 2.4), cf * CFrame.new(-14, 2, -6) * CFrame.Angles(math.rad(70), 0.6, 0), rgb(150, 190, 190), M.Marble)
	part(m, Vector3.new(2.2, 2.2, 2.2), cf * CFrame.new(-17, 1.6, -10) * CFrame.Angles(0.4, 0.3, 0.2), rgb(150, 190, 190), M.Marble)
	-- lily pads on the water, a flower or two
	for _ = 1, 12 do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(10, 24)
		local at = cf * CFrame.new(math.cos(a) * d, 8.15, math.sin(a) * d)
		cyl(m, 0.15, rng:NextNumber(1.6, 2.8), at, rgb(70, 160, 70), M.SmoothPlastic, { CanCollide = false, CanQuery = false })
		if rng:NextNumber() < 0.25 then part(m, Vector3.new(0.6, 0.5, 0.6), at * CFrame.new(0, 0.3, 0), rgb(255, 190, 220), M.SmoothPlastic, { CanCollide = false }) end
	end
end

-- The Infernal Citadel: volcanic black, molten orange, ember red
local SCORCH = rgb(36, 30, 32)
B.vent = function(cf, rng, m)
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		part(m, Vector3.new(1.8, rng:NextNumber(1.2, 2.4), 1.4), cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0.6, -1.8), SCORCH, M.Basalt)
	end
	local v = glow(m, Vector3.new(2.2, 0.4, 2.2), cf * CFrame.new(0, 0.4, 0), rgb(255, 110, 30))
	emit(v, { Texture = SMOKE, Color = ColorSequence.new(rgb(70, 64, 64)), Size = seq(3, 9), Transparency = seq(0.5, 1),
		Lifetime = NumberRange.new(3, 5), Speed = NumberRange.new(5, 8), Rate = 3 })
	emit(v, { Texture = SPARK, Color = ColorSequence.new(rgb(255, 190, 90)), Size = seq(0.4, 0), Lifetime = NumberRange.new(1, 2),
		Speed = NumberRange.new(6, 10), Rate = 5, LightEmission = 1, SpreadAngle = Vector2.new(20, 20) })
end
-- a spiked barricade: crossed beams, iron spikes
B.barricade = function(cf, rng, m)
	part(m, Vector3.new(10, 0.8, 0.8), cf * CFrame.new(0, 1, 0), rgb(60, 44, 34), M.Wood)
	for k = -2, 2 do
		part(m, Vector3.new(0.6, 0.6, 5), cf * CFrame.new(k * 2.2, 1.8, 0) * CFrame.Angles(math.rad(if k % 2 == 0 then 40 else -40), 0, 0), rgb(70, 50, 38), M.Wood)
		part(m, Vector3.new(0.3, 0.3, 1.4), cf * CFrame.new(k * 2.2, 3.4, if k % 2 == 0 then -2 else 2), rgb(120, 116, 120), M.Metal)
	end
end
-- a scorched banner on a pole, burnt ragged at its foot
B.banner = function(cf, rng, m)
	part(m, Vector3.new(0.6, 14, 0.6), cf * CFrame.new(0, 7, 0), rgb(40, 34, 36), M.Metal)
	part(m, Vector3.new(4, 0.4, 0.4), cf * CFrame.new(0, 13.6, 0), rgb(40, 34, 36), M.Metal)
	part(m, Vector3.new(3.6, 7, 0.1), cf * CFrame.new(0, 9.8, 0.1), rgb(120, 20, 24), M.Fabric, { CanCollide = false })
	part(m, Vector3.new(2.4, 1.6, 0.12), cf * CFrame.new(rng:NextNumber(-0.6, 0.6), 5.6, 0.1), rgb(50, 16, 18), M.Fabric, { CanCollide = false })
	glow(m, Vector3.new(1.2, 1.2, 0.15), cf * CFrame.new(0, 10.6, 0.05) * CFrame.Angles(0, 0, math.rad(45)), rgb(255, 120, 40))
end
-- a furnace: a black block, its mouth glowing, smoke from its stack
B.furnace = function(cf, rng, m)
	part(m, Vector3.new(9, 8, 8), cf * CFrame.new(0, 4, 0), SCORCH, M.Basalt)
	part(m, Vector3.new(3, 10, 3), cf * CFrame.new(2, 11, 2), rgb(46, 40, 42), M.Basalt)
	local mouth = glow(m, Vector3.new(4, 3, 0.4), cf * CFrame.new(0, 2.5, -4.05), rgb(255, 120, 30))
	emit(mouth, { Texture = FIRE, Color = ColorSequence.new(rgb(255, 210, 110), rgb(255, 80, 20)), Size = seq(1.6, 0.3), Transparency = seq(0.2, 1),
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(2, 4), Rate = 10, LightEmission = 1, EmissionDirection = Enum.NormalId.Front })
	local stack = part(m, Vector3.new(2, 0.4, 2), cf * CFrame.new(2, 16.2, 2), rgb(30, 26, 28), M.Basalt)
	emit(stack, { Texture = SMOKE, Color = ColorSequence.new(rgb(60, 56, 58)), Size = seq(3, 10), Transparency = seq(0.4, 1),
		Lifetime = NumberRange.new(4, 6), Speed = NumberRange.new(4, 6), Rate = 3, EmissionDirection = Enum.NormalId.Top })
end
-- an enormous demonic statue: horned, crouched on a plinth, eyes of fire
B.demon_statue = function(cf, rng, m)
	local D = rgb(44, 38, 42)
	part(m, Vector3.new(14, 4, 12), cf * CFrame.new(0, 2, 0), rgb(56, 48, 52), M.Basalt)
	part(m, Vector3.new(9, 12, 7), cf * CFrame.new(0, 10, 0) * CFrame.Angles(math.rad(-12), 0, 0), D, M.Basalt)
	part(m, Vector3.new(6, 5, 5.4), cf * CFrame.new(0, 18, -1.6), D, M.Basalt)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(1.4, 6, 1.4), cf * CFrame.new(sx * 3.6, 22, -1) * CFrame.Angles(0, 0, math.rad(sx * -30)), rgb(30, 26, 28), M.Basalt)
		part(m, Vector3.new(3, 9, 3), cf * CFrame.new(sx * 6, 8, -2) * CFrame.Angles(math.rad(-20), 0, math.rad(sx * 8)), D, M.Basalt) -- (arms)
		part(m, Vector3.new(4, 5, 7), cf * CFrame.new(sx * 3.5, 6, -1) , D, M.Basalt) -- (haunches)
		glow(m, Vector3.new(1.2, 0.6, 0.3), cf * CFrame.new(sx * 1.4, 18.6, -4.35), rgb(255, 90, 30))
		-- wings, folded
		part(m, Vector3.new(1, 14, 8), cf * CFrame.new(sx * 6, 14, 4) * CFrame.Angles(math.rad(20), 0, math.rad(sx * -20)), rgb(36, 30, 34), M.Basalt)
	end
	glow(m, Vector3.new(3, 0.6, 0.3), cf * CFrame.new(0, 16.4, -4.35), rgb(255, 120, 40)) -- (its burning maw)
end
-- an abandoned siege engine: a broken catapult
B.siege = function(cf, rng, m)
	local W, I = rgb(80, 58, 40), rgb(70, 66, 70)
	part(m, Vector3.new(6, 1, 10), cf * CFrame.new(0, 1.6, 0), W, M.WoodPlanks)
	for _, c in ipairs({ { -3.2, -4 }, { 3.2, -4 }, { -3.2, 4 }, { 3.2, 4 } }) do
		cyl(m, 0.8, 3, cf * CFrame.new(c[1], 1.5, c[2]) * CFrame.Angles(0, 0, math.rad(90)), W, M.Wood)
	end
	for _, sx in ipairs({ -2.4, 2.4 }) do part(m, Vector3.new(0.8, 6, 0.8), cf * CFrame.new(sx, 5, 0), W, M.Wood) end
	part(m, Vector3.new(6, 0.8, 0.8), cf * CFrame.new(0, 7.6, 0), I, M.Metal)
	part(m, Vector3.new(0.7, 0.7, 11), cf * CFrame.new(0, 6.5, 1) * CFrame.Angles(math.rad(rng:NextNumber(20, 35)), 0, 0), W, M.Wood)
	part(m, Vector3.new(2.4, 1, 2.4), cf * CFrame.new(0, 3.5, 6), W, M.WoodPlanks)
end
-- broken chains hanging from a basalt post out over the drop
B.chains = function(cf, rng, m)
	part(m, Vector3.new(2.4, 12, 2.4), cf * CFrame.new(0, 6, 0), rgb(40, 34, 38), M.Basalt)
	part(m, Vector3.new(6, 1.2, 1.2), cf * CFrame.new(2.4, 11.6, 0), rgb(40, 34, 38), M.Basalt)
	for c = 0, rng:NextInteger(5, 9) do
		part(m, Vector3.new(0.5, 1.1, 0.25), cf * CFrame.new(5, 10.6 - c * 1, 0) * CFrame.Angles(0, if c % 2 == 0 then 0 else math.rad(90), 0), rgb(60, 56, 60), M.Metal, { CanCollide = false })
	end
end

-- ── The later isles' pieces ─────────────────────────────────────────────────
-- A builder's pieces tinted toward a colour (`amount` 0..1), its material
-- swapped where given: the same arcade as a corrupted chapel, a frozen
-- temple, a sunken aqueduct.
local function tinted(fn: (CFrame, Random, Model) -> (), color: Color3, amount: number, mat: Enum.Material?): (CFrame, Random, Model) -> ()
	return function(cf, rng, m)
		fn(cf, rng, m)
		for _, d in ipairs(m:GetDescendants()) do
			if d:IsA("BasePart") and d.Material ~= M.Neon then
				d.Color = d.Color:Lerp(color, amount)
				if mat and (d.Material == M.Slate or d.Material == M.Marble or d.Material == M.Grass) then d.Material = mat end
			end
		end
	end
end

-- The Corrupted Isle
B.corrupt_temple = function(cf, rng, m)
	tinted(B.arches, rgb(70, 40, 90), 0.6)(cf, rng, m)
	for _ = 1, 6 do
		local at = cf * CFrame.new(rng:NextNumber(-28, 28), 0, rng:NextNumber(-6, 14))
		B.corrupt_crystal(at, rng, m)
	end
	for _ = 1, 4 do B.thorns(cf * CFrame.new(rng:NextNumber(-30, 30), 0, rng:NextNumber(-14, 14)), rng, m) end
end
-- a bramble of black thorns, jagged spikes jutting every way
B.thorns = function(cf, rng, m)
	local T = rgb(30, 22, 34)
	for _ = 1, rng:NextInteger(5, 8) do
		local l = rng:NextNumber(3, 7)
		local at = cf * CFrame.new(rng:NextNumber(-2, 2), 0.5, rng:NextNumber(-2, 2))
			* CFrame.Angles(math.rad(rng:NextNumber(-60, 60)), rng:NextNumber(0, 6.28), math.rad(rng:NextNumber(-60, 60)))
		part(m, Vector3.new(0.5, l, 0.5), at * CFrame.new(0, l / 2, 0), T, M.Wood, { CanCollide = false })
		part(m, Vector3.new(0.25, 0.9, 0.25), at * CFrame.new(0, l * 0.6, 0.3) * CFrame.Angles(math.rad(50), 0, 0), T, M.Wood, { CanCollide = false })
	end
	if rng:NextNumber() < 0.4 then glow(m, Vector3.new(0.5, 0.5, 0.5), cf * CFrame.new(0, 1.5, 0), rgb(255, 60, 200)) end
end
-- the Thornwall: a ruined wall overgrown with thorns, crystals through it
B.thorn_ruins = function(cf, rng, m)
	tinted(B.wall, rgb(60, 40, 76), 0.5)(cf, rng, m)
	tinted(B.wall, rgb(60, 40, 76), 0.5)(cf * CFrame.new(10, 0, 8), rng, m)
	for _ = 1, 8 do B.thorns(cf * CFrame.new(rng:NextNumber(-14, 18), 0, rng:NextNumber(-8, 14)), rng, m) end
	for _ = 1, 3 do B.corrupt_crystal(cf * CFrame.new(rng:NextNumber(-12, 16), 0, rng:NextNumber(-6, 12)), rng, m) end
	B.broken_statue(cf * CFrame.new(4, 0, -8), rng, m)
end

-- The Infernal Isle: the black forge, anvils and a great furnace
B.forge = function(cf, rng, m)
	B.furnace(cf * CFrame.new(0, 0, 8), rng, m)
	B.furnace(cf * CFrame.new(-12, 0, 6) * CFrame.Angles(0, 0.4, 0), rng, m)
	for _, x in ipairs({ -6, 6 }) do
		part(m, Vector3.new(3, 2, 2), cf * CFrame.new(x, 1, -6), rgb(40, 36, 38), M.Metal)
		part(m, Vector3.new(4, 0.8, 1.6), cf * CFrame.new(x, 2.4, -6), rgb(60, 56, 60), M.Metal)
	end
	glow(m, Vector3.new(6, 0.4, 3), cf * CFrame.new(0, 0.3, -12), rgb(255, 110, 30))
	B.chains(cf * CFrame.new(10, 0, -4), rng, m)
	B.banner(cf * CFrame.new(-8, 0, -12), rng, m)
end

-- The Frozen Isle: pale ice, blue runes
local ICEC, ICE2, SNOWC, RUNEB = rgb(190, 222, 244), rgb(150, 196, 230), rgb(240, 246, 252), rgb(110, 200, 255)
B.ice_crystal = function(cf, rng, m)
	for _ = 1, rng:NextInteger(2, 5) do
		local h = rng:NextNumber(3, 10)
		local at = cf * CFrame.new(rng:NextNumber(-2, 2), 0, rng:NextNumber(-2, 2)) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-25, 25)))
		local c = part(m, Vector3.new(h * 0.3, h, h * 0.3), at * CFrame.new(0, h / 2 - 0.5, 0), if rng:NextNumber() < 0.5 then ICEC else ICE2, M.Ice)
		c.Transparency = 0.2
	end
	if rng:NextNumber() < 0.4 then glow(m, Vector3.new(0.6, 0.6, 0.6), cf * CFrame.new(0, 1, 0), RUNEB) end
end
B.snow_drift = function(cf, rng, m)
	for _ = 1, rng:NextInteger(2, 4) do
		local w = rng:NextNumber(3, 7)
		part(m, Vector3.new(w, rng:NextNumber(0.8, 2), w * rng:NextNumber(0.6, 1)), cf * CFrame.new(rng:NextNumber(-2, 2), 0.4, rng:NextNumber(-2, 2)) * CFrame.Angles(0, rng:NextNumber(0, 3), 0), SNOWC, M.Snow)
	end
end
-- a standing stone carved with glowing blue runes, frosted over
B.rune_stone = function(cf, rng, m)
	local h = rng:NextNumber(6, 10)
	local s = cf * CFrame.Angles(math.rad(rng:NextNumber(-5, 5)), 0, math.rad(rng:NextNumber(-5, 5)))
	part(m, Vector3.new(3, h, 2), s * CFrame.new(0, h / 2, 0), rgb(110, 120, 136), M.Slate)
	part(m, Vector3.new(3.2, 0.6, 2.2), s * CFrame.new(0, h + 0.2, 0), SNOWC, M.Snow)
	for k = 0, 2 do glow(m, Vector3.new(0.9, 0.9, 0.1), s * CFrame.new(0, h * (0.3 + k * 0.22), -1.02) * CFrame.Angles(0, 0, math.rad(45)), RUNEB) end
end
-- a great arch of clear ice
B.ice_arch = function(cf, rng, m)
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 4 do
			part(m, Vector3.new(4, 5, 4), cf * CFrame.new(sx * (10 - k * 1.2), 2.5 + k * 4.6, 0) * CFrame.Angles(0, 0, math.rad(sx * k * 9)), if k % 2 == 0 then ICEC else ICE2, M.Ice, { Transparency = 0.15 })
		end
	end
	part(m, Vector3.new(14, 4, 4), cf * CFrame.new(0, 24, 0), ICEC, M.Ice, { Transparency = 0.15 })
	part(m, Vector3.new(14.4, 1, 4.4), cf * CFrame.new(0, 26.4, 0), SNOWC, M.Snow)
	for k = -2, 2 do part(m, Vector3.new(0.7, rng:NextNumber(2, 4), 0.7), cf * CFrame.new(k * 2.6, 20.5, 0), rgb(220, 240, 255), M.Ice, { CanCollide = false }) end
end
-- an abandoned hut, its roof heavy with snow, the door frozen shut
B.frost_hut = function(cf, rng, m)
	part(m, Vector3.new(10, 7, 9), cf * CFrame.new(0, 3.5, 0), rgb(96, 74, 56), M.WoodPlanks)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(6.6, 0.8, 11), cf * CFrame.new(sx * 2.8, 8.4, 0) * CFrame.Angles(0, 0, math.rad(sx * -35)), rgb(70, 54, 42), M.WoodPlanks)
		part(m, Vector3.new(6.6, 0.8, 11), cf * CFrame.new(sx * 2.9, 9.0, 0) * CFrame.Angles(0, 0, math.rad(sx * -35)), SNOWC, M.Snow)
	end
	part(m, Vector3.new(3, 4.6, 0.3), cf * CFrame.new(0, 2.3, -4.6), rgb(150, 196, 230), M.Ice, { Transparency = 0.3 })
	part(m, Vector3.new(1.4, 1.4, 0.2), cf * CFrame.new(3, 4.4, -4.55), rgb(255, 200, 120), M.Neon)
	B.snow_drift(cf * CFrame.new(5, 0, 3), rng, m)
end
-- Hollowfrost: a ring of abandoned huts round a frozen well and a cold fire
B.frost_village = function(cf, rng, m)
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2 + 0.3
		B.frost_hut(cf * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -18) * CFrame.Angles(0, math.pi, 0), rng, m)
	end
	cyl(m, 3, 6, cf * CFrame.new(0, 1.5, 0), rgb(110, 116, 128), M.Slate)
	cyl(m, 0.4, 5, cf * CFrame.new(0, 3, 0), ICEC, M.Ice)
	for _, sx in ipairs({ -2.4, 2.4 }) do part(m, Vector3.new(0.5, 5, 0.5), cf * CFrame.new(sx, 4.5, 0), rgb(80, 60, 44), M.Wood) end
	part(m, Vector3.new(5.4, 0.5, 0.5), cf * CFrame.new(0, 7, 0), rgb(80, 60, 44), M.Wood)
	for _ = 1, 3 do B.rune_stone(cf * CFrame.new(rng:NextNumber(-26, 26), 0, rng:NextNumber(-26, 26)), rng, m) end
end
-- a frozen statue: a warrior caught in ice
B.frozen_statue = function(cf, rng, m)
	part(m, Vector3.new(4, 1.4, 4), cf * CFrame.new(0, 0.7, 0), rgb(110, 116, 128), M.Slate)
	part(m, Vector3.new(2.4, 5, 1.6), cf * CFrame.new(0, 4, 0), rgb(150, 160, 176), M.Marble)
	part(m, Vector3.new(1.6, 1.6, 1.6), cf * CFrame.new(0, 7.3, 0), rgb(150, 160, 176), M.Marble)
	part(m, Vector3.new(4, 8.6, 3.2), cf * CFrame.new(0, 5, 0), ICEC, M.Ice, { Transparency = 0.45 })
end
B.frost_temple = tinted(B.arches, rgb(190, 222, 244), 0.55, M.Ice)
-- the Icebound Galleon: the wreck, rimed white, ice grown through its hull
B.frozen_wreck = function(cf, rng, m)
	tinted(B.shipwreck, rgb(200, 226, 244), 0.5)(cf, rng, m)
	for _ = 1, 10 do
		local h = rng:NextNumber(3, 9)
		part(m, Vector3.new(h * 0.4, h, h * 0.4), cf * CFrame.new(rng:NextNumber(-26, 26), h / 2 - 1, rng:NextNumber(2, 18)) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), 0, math.rad(rng:NextNumber(-25, 25))),
			ICE2, M.Ice, { Transparency = 0.2 })
	end
end

-- The Sunken Isle
B.sunken_aqueduct = tinted(B.arches, rgb(80, 150, 150), 0.55)
-- a tall sea plant, swaying fronds of kelp
B.kelp = function(cf, rng, m)
	for _ = 1, rng:NextInteger(2, 4) do
		local h = rng:NextNumber(5, 11)
		local at = cf * CFrame.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5))
		for k = 0, 3 do
			part(m, Vector3.new(0.5, h / 4, 1.2), at * CFrame.new(math.sin(k) * 0.4, h / 8 + k * h / 4, 0) * CFrame.Angles(0, k * 0.5, math.rad(math.sin(k * 1.7) * 12)),
				if k % 2 == 0 then rgb(50, 130, 90) else rgb(70, 150, 100), M.Grass, { CanCollide = false })
		end
	end
end

-- The Shattered Isle
-- an enormous crimson portal: a ring of black stone, a swirl of red light
B.crimson_portal = function(cf, rng, m)
	local CR = rgb(235, 40, 55)
	for k = 0, 15 do
		local a = k / 16 * math.pi * 2
		part(m, Vector3.new(4, 4.6, 3), cf * CFrame.new(math.cos(a) * 12, 14 + math.sin(a) * 12, 0) * CFrame.Angles(0, 0, a), rgb(34, 30, 40), M.Slate)
		if k % 2 == 0 then glow(m, Vector3.new(0.6, 2, 3.2), cf * CFrame.new(math.cos(a) * 10, 14 + math.sin(a) * 10, 0) * CFrame.Angles(0, 0, a), CR) end
	end
	local disc = cyl(m, 0.6, 20, cf * CFrame.new(0, 14, 0) * CFrame.Angles(math.rad(90), 0, 0), CR, M.Neon, { CanCollide = false, CanQuery = false })
	disc.Transparency = 0.35
	emit(disc, { Texture = SPARK, Color = ColorSequence.new(rgb(255, 140, 140), CR), Size = seq(1, 0), Transparency = seq(0.1, 1),
		Lifetime = NumberRange.new(1.5, 3), Speed = NumberRange.new(2, 6), Rate = 14, LightEmission = 1, EmissionDirection = Enum.NormalId.Top })
	part(m, Vector3.new(14, 2, 6), cf * CFrame.new(0, 1, 0), rgb(48, 40, 54), M.Slate)
	for _ = 1, 4 do B.red_crystal(cf * CFrame.new(rng:NextNumber(-12, 12), 0, rng:NextNumber(-8, 8)), rng, m) end
end
-- the Shattered Temple: the arcade blackened, split, its stones floating apart
B.shattered_temple = function(cf, rng, m)
	tinted(B.arches, rgb(40, 34, 46), 0.75)(cf, rng, m)
	for _ = 1, 8 do
		local s = rng:NextNumber(2, 5)
		part(m, Vector3.new(s, s * 0.8, s), cf * CFrame.new(rng:NextNumber(-26, 26), rng:NextNumber(26, 44), rng:NextNumber(-6, 12)) * CFrame.Angles(rng:NextNumber(0, 3), rng:NextNumber(0, 3), 0),
			rgb(48, 42, 54), M.Slate, { CanCollide = false })
	end
	for _ = 1, 3 do glow(m, Vector3.new(0.5, rng:NextNumber(6, 14), 0.3), cf * CFrame.new(rng:NextNumber(-26, 26), 8, 6.1), rgb(235, 40, 55)) end
end
B.red_crystal = function(cf, rng, m)
	for _ = 1, rng:NextInteger(2, 4) do
		local h = rng:NextNumber(2.5, 7)
		local at = cf * CFrame.new(rng:NextNumber(-1.5, 1.5), 0, rng:NextNumber(-1.5, 1.5)) * CFrame.Angles(math.rad(rng:NextNumber(-25, 25)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-25, 25)))
		local c = glow(m, Vector3.new(h * 0.28, h, h * 0.28), at * CFrame.new(0, h / 2 - 0.4, 0), rgb(235, 40, 55))
		c.Transparency = 0.15
	end
end
-- a crack in the black ground, red light welling up
B.rift_crack = function(cf, rng, m)
	local at = cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0)
	for k = 0, rng:NextInteger(3, 5) - 1 do
		glow(m, Vector3.new(rng:NextNumber(0.6, 1.4), 0.25, 4.4), at * CFrame.Angles(0, rng:NextNumber(-0.6, 0.6), 0) * CFrame.new(0, 0.12, -k * 4), if k % 2 == 0 then rgb(235, 40, 55) else rgb(170, 70, 255))
	end
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
