--!strict
--[[
	IslandScenery.luau
	Each isle's scenery (IslandGenerator calls it once the isle's ground is
	built), after the concept art, and the crossings between the isles:

	  • the river's falls (a sheet of falling water at every cliff, ice on the
	    Frozen Isle, its water frozen over there), a plank bridge across the
	    top of each one below the first
	  • the bridges between an isle's islets: wooden on posts, arched stone,
	    black basalt seamed with lava, pale ice, obsidian seamed crimson
	  • lava rivers down from the summit where an isle has them (`lava`)
	  • the summit's landmark (`tower`): the Forgotten Isle's mossy temple, the
	    Corrupted Isle's violet spire, the Infernal Isle's crater and eruption,
	    the Frozen Isle's ice tower, the Sunken Isle's tidal tower, the
	    Shattered Isle's Ancient Spire (black towers round it, monoliths
	    chained to it)
	  • each biome's trees, vines down the ruins' cliffs, ice down the frozen
	    ones, coral in the shallows, lily pads on the Sunken Isle's pools
	  • the Shattered Isle's purple void and its floating landmasses

	IslandScenery.Build(origin, field, rng, parent, groundAt, taken)
	IslandScenery.Crossing(parent, a, b, nextIsle, rng) → (Model, seal Model)
	IslandScenery.Unseal(seal)
--]]--]]


local TweenService = game:GetService("TweenService")

local IslandScenery = {}

local MAT = Enum.Material
local WATER = Color3.fromRGB(120, 200, 255)
local WATER_BRIGHT = Color3.fromRGB(150, 225, 255)
local LAVA = Color3.fromRGB(255, 110, 30)
local OBSIDIAN = Color3.fromRGB(34, 30, 40)
local OBSIDIAN2 = Color3.fromRGB(48, 40, 54)
local CRIMSON = Color3.fromRGB(235, 40, 55)
local SILVER = Color3.fromRGB(170, 172, 184)
-- the spire's tiers { width, height }, from its foot
local TIERS = { { 52, 20 }, { 44, 28 }, { 36, 26 }, { 28, 22 }, { 20, 16 }, { 12, 10 } }
local STONE = Color3.fromRGB(86, 88, 104)
local MOSS = Color3.fromRGB(70, 140, 48)
local WOOD = Color3.fromRGB(110, 78, 50)
local WOOD_DARK = Color3.fromRGB(78, 54, 36)

local function piece(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanTouch = true, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.CastShadow = false
	p.Size, p.CFrame, p.Color, p.Material = size, cf, color, mat
	if props then for k, v in pairs(props) do (p :: any)[k] = v end end
	p.Parent = parent
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

-- A sheet of falling water from `top` down `drop` studs, `width` wide,
-- facing `dir` (the way it falls out), foam where it lands.
local function fall(parent: Instance, top: Vector3, dir: Vector3, width: number, drop: number, ice: boolean?)
	local face = CFrame.lookAt(top, top + dir)
	if ice then
		-- (frozen mid-fall: a sheet of pale ice, its edges in icicles)
		piece(parent, Vector3.new(width, drop, 1.2), face * CFrame.new(0, -drop / 2, -0.8), Color3.fromRGB(190, 225, 245), MAT.Ice,
			{ Transparency = 0.15, CanCollide = false, CanQuery = false, Name = "FrozenFall" })
		for k = -2, 2 do
			local h = math.min(drop, 2 + math.abs(k) * 1.5)
			piece(parent, Vector3.new(width / 6, h, 1.4), face * CFrame.new(k * width / 5, -drop + h / 2, -0.9), Color3.fromRGB(220, 240, 255), MAT.Ice,
				{ CanCollide = false, CanQuery = false, Name = "IceFoot" })
		end
		return
	end
	local sheet = piece(parent, Vector3.new(width, drop, 0.6), face * CFrame.new(0, -drop / 2, -0.6), WATER, MAT.Glass,
		{ Transparency = 0.25, CanCollide = false, CanQuery = false, Name = "Waterfall" })
	piece(parent, Vector3.new(width * 0.6, drop, 0.3), face * CFrame.new(0, -drop / 2, -0.95), WATER_BRIGHT, MAT.Neon,
		{ Transparency = 0.6, CanCollide = false, CanQuery = false, Name = "WaterfallGlow" })
	emitter(sheet, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(235, 245, 255)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) }),
		Lifetime = NumberRange.new(1.2, 2.2),
		Speed = NumberRange.new(1, 3),
		Rate = math.clamp(drop * 0.6, 3, 10),
		EmissionDirection = Enum.NormalId.Front,
	})
	-- foam on the pool below
	local foam = piece(parent, Vector3.new(0.3, width * 1.2, width * 1.2), CFrame.new(top + Vector3.new(0, -drop + 0.1, 0) + dir * 1.5) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(240, 250, 255), MAT.SmoothPlastic, { Transparency = 0.35, CanCollide = false, CanQuery = false, Shape = Enum.PartType.Cylinder, Name = "Foam" })
	emitter(foam, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(230, 245, 255)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(60, 60),
		EmissionDirection = Enum.NormalId.Right,
		Rate = 12,
	})
end

-- A plank bridge across from `a` to `b` (deck height), with rails and posts.
local function bridge(parent: Instance, a: Vector3, b: Vector3, width: number)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt(mid, b)
	local n = math.max(3, math.floor(len / 1.6))
	for i = 0, n - 1 do
		local z = -len / 2 + (i + 0.5) * len / n
		piece(parent, Vector3.new(width, 0.5, len / n - 0.15), cf * CFrame.new(0, 0, z), if i % 2 == 0 then WOOD else WOOD_DARK, MAT.WoodPlanks,
			{ CanCollide = true, Name = "BridgePlank" })
	end
	for _, s in ipairs({ -1, 1 }) do
		piece(parent, Vector3.new(0.4, 0.4, len), cf * CFrame.new(s * (width / 2 - 0.2), 2.8, 0), WOOD_DARK, MAT.Wood, { Name = "BridgeRail" })
		for i = 0, 3 do
			local z = -len / 2 + i * len / 3
			piece(parent, Vector3.new(0.5, 3.4, 0.5), cf * CFrame.new(s * (width / 2 - 0.2), 1.4, z), WOOD_DARK, MAT.Wood, { Name = "BridgePost" })
		end
	end
	-- the beams under it, sunk into the banks
	for _, s in ipairs({ -1, 1 }) do
		piece(parent, Vector3.new(0.8, 0.8, len + 4), cf * CFrame.new(s * (width / 2 - 1), -0.6, 0), WOOD_DARK, MAT.Wood, { Name = "BridgeBeam" })
	end
end

-- A long span from `a` to `b` (the deck's top at each end): wooden planks
-- on posts down into the water, or arched stone on piers (`look`: its
-- stone, its trim, a glow along its seams for the volcano's).
local SEA_BED = -10
local SPANS: { [string]: { a: Color3, b: Color3, mat: Enum.Material, seam: Color3? } } = {
	stone = { a = Color3.fromRGB(122, 122, 132), b = Color3.fromRGB(104, 104, 116), mat = MAT.Slate },
	basalt = { a = Color3.fromRGB(44, 38, 42), b = Color3.fromRGB(58, 50, 54), mat = MAT.Basalt, seam = LAVA },
	ice = { a = Color3.fromRGB(196, 222, 240), b = Color3.fromRGB(160, 198, 228), mat = MAT.Ice, seam = Color3.fromRGB(120, 220, 255) },
	obsidian = { a = Color3.fromRGB(34, 30, 40), b = Color3.fromRGB(48, 40, 54), mat = MAT.Slate, seam = CRIMSON },
}
local function span(parent: Instance, a: Vector3, b: Vector3, kind: string, rng: Random)
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	local flat = CFrame.lookAt(Vector3.zero, Vector3.new(b.X - a.X, 0, b.Z - a.Z))
	if kind == "wood" then
		bridge(parent, a + Vector3.new(0, 0.25, 0), b + Vector3.new(0, 0.25, 0), 7)
		-- posts down into the water every dozen studs
		local n = math.floor(len / 12)
		for k = 1, n - 1 do
			local p = a:Lerp(b, k / n)
			local h = p.Y - SEA_BED
			for _, sx in ipairs({ -3.2, 3.2 }) do
				piece(parent, Vector3.new(0.9, h, 0.9), flat * CFrame.new(0, 0, 0) + Vector3.new(p.X, SEA_BED + h / 2, p.Z) + (flat.RightVector * sx),
					WOOD_DARK, MAT.Wood, { Name = "BridgePile", CanCollide = true })
			end
		end
		return
	end
	local look = SPANS[kind] or SPANS.stone
	local basalt = look.seam ~= nil
	local STONE_A, STONE_B, SMAT = look.a, look.b, look.mat
	local W = 9
	local segs = math.max(2, math.floor(len / 6))
	local sl = len / segs
	for k = 0, segs - 1 do
		local z = -len / 2 + (k + 0.5) * sl
		piece(parent, Vector3.new(W, 1.6, sl + 0.05), cf * CFrame.new(0, -0.8, z), if k % 2 == 0 then STONE_A else STONE_B, SMAT,
			{ Name = "BridgeDeck", CanCollide = true, CastShadow = true })
		for _, sx in ipairs({ -1, 1 }) do
			if not basalt and rng:NextNumber() < 0.12 then continue end -- (a parapet stone fallen)
			piece(parent, Vector3.new(1.2, 2.2, sl + 0.05), cf * CFrame.new(sx * (W / 2 - 0.6), 1.1, z), STONE_B, SMAT, { Name = "Parapet", CanCollide = true })
		end
	end
	if basalt then
		for _, sx in ipairs({ -1, 1 }) do
			piece(parent, Vector3.new(0.4, 0.5, len), cf * CFrame.new(sx * (W / 2 + 0.1), -1.2, 0), look.seam, MAT.Neon, { Name = "Seam", CanCollide = false, CanQuery = false })
		end
	end
	-- piers down to the sea bed, an arch's keystone between each pair
	local np = math.max(1, math.floor(len / 16))
	for k = 1, np do
		local f = k / (np + 1)
		local p = a:Lerp(b, f)
		local h = p.Y - 1.6 - SEA_BED
		piece(parent, Vector3.new(W - 1, h, 4), flat + Vector3.new(p.X, SEA_BED + h / 2, p.Z), STONE_B, SMAT, { Name = "BridgePier", CanCollide = true, CastShadow = true })
		piece(parent, Vector3.new(W + 0.6, 1.2, 5.4), flat + Vector3.new(p.X, p.Y - 2.2, p.Z), STONE_A, SMAT, { Name = "PierCap" })
	end
	for k = 0, np do
		local f = (k + 0.5) / (np + 1)
		local p = a:Lerp(b, f)
		piece(parent, Vector3.new(W - 1, 2.4, len / (np + 1) * 0.45), cf.Rotation + Vector3.new(p.X, p.Y - 2.8, p.Z), STONE_B, SMAT, { Name = "ArchKey" })
	end
end

-- A blocky tree: a trunk and a chunky crown of offset cubes.
local GREENS = { Color3.fromRGB(64, 148, 50), Color3.fromRGB(52, 124, 42), Color3.fromRGB(84, 166, 58), Color3.fromRGB(44, 112, 46) }
local function blockTree(parent: Instance, base: Vector3, rng: Random, scale: number)
	local h = rng:NextNumber(5, 8) * scale
	piece(parent, Vector3.new(1.8 * scale, h + 1, 1.8 * scale), CFrame.new(base + Vector3.new(0, (h - 1) / 2, 0)), Color3.fromRGB(96, 68, 44), MAT.Wood, { Name = "Trunk" })
	local g = GREENS[rng:NextInteger(1, #GREENS)]
	local s = rng:NextNumber(7, 9) * scale
	piece(parent, Vector3.new(s, s * 0.8, s), CFrame.new(base + Vector3.new(0, h + s * 0.3, 0)), g, MAT.Grass, { Name = "Leaves", CastShadow = true })
	for _ = 1, rng:NextInteger(1, 2) do
		local s2 = s * rng:NextNumber(0.5, 0.7)
		local off = Vector3.new(rng:NextNumber(-1, 1) * s * 0.4, s * rng:NextNumber(0.45, 0.65), rng:NextNumber(-1, 1) * s * 0.4)
		piece(parent, Vector3.new(s2, s2 * 0.85, s2), CFrame.new(base + Vector3.new(0, h + s * 0.3, 0) + off),
			GREENS[rng:NextInteger(1, #GREENS)], MAT.Grass, { Name = "Leaves" })
	end
end

-- A twisted tree of the Corrupted Forest: a black trunk kinked at angles,
-- jagged bare branches, a few violet leaf-blocks, a glow at its roots.
local function twistedTree(parent: Instance, base: Vector3, rng: Random, scale: number)
	local BARK = Color3.fromRGB(32, 26, 36)
	local cf = CFrame.new(base)
	local h = 0
	for k = 0, 2 do
		local seg = rng:NextNumber(4, 6) * scale
		local bend = CFrame.Angles(math.rad(rng:NextNumber(-22, 22)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-22, 22)))
		local at = cf * bend
		piece(parent, Vector3.new(1.6 * scale - k * 0.3, seg, 1.6 * scale - k * 0.3), at * CFrame.new(0, seg / 2, 0), BARK, MAT.Wood, { Name = "Trunk" })
		cf = at * CFrame.new(0, seg, 0)
		h += seg
	end
	for _ = 1, rng:NextInteger(3, 4) do
		local len = rng:NextNumber(3, 6) * scale
		local br = cf * CFrame.Angles(0, rng:NextNumber(0, 6.28), 0) * CFrame.Angles(math.rad(rng:NextNumber(-70, -40)), 0, 0)
		piece(parent, Vector3.new(0.6, 0.6, len), br * CFrame.new(0, 0, -len / 2), BARK, MAT.Wood, { Name = "Branch" })
		if rng:NextNumber() < 0.6 then
			local s2 = rng:NextNumber(2.2, 3.6) * scale
			piece(parent, Vector3.new(s2, s2 * 0.7, s2), br * CFrame.new(0, 0, -len), if rng:NextNumber() < 0.5 then Color3.fromRGB(110, 50, 150) else Color3.fromRGB(70, 36, 96),
				MAT.Grass, { Name = "Leaves" })
		end
	end
	if rng:NextNumber() < 0.35 then
		piece(parent, Vector3.new(2.4, 0.2, 2.4) * scale, CFrame.new(base + Vector3.new(0, 0.15, 0)), Color3.fromRGB(200, 70, 255), MAT.Neon, { Name = "RootGlow", CanQuery = false, Transparency = 0.4 })
	end
end

-- A mangrove of the Sunken Sanctuary: arched roots, teal-green leaf-blocks.
local function mangrove(parent: Instance, base: Vector3, rng: Random, scale: number)
	local BARK = Color3.fromRGB(96, 84, 70)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + rng:NextNumber(0, 0.5)
		piece(parent, Vector3.new(0.6, 4 * scale, 0.6), CFrame.new(base) * CFrame.Angles(0, a, 0) * CFrame.new(0, 1.6 * scale, -1.4 * scale) * CFrame.Angles(math.rad(-30), 0, 0),
			BARK, MAT.Wood, { Name = "Root" })
	end
	local h = 7 * scale
	piece(parent, Vector3.new(1.2 * scale, h - 2, 1.2 * scale), CFrame.new(base + Vector3.new(0, h / 2 + 1, 0)), BARK, MAT.Wood, { Name = "Trunk" })
	for _ = 1, 3 do
		local s2 = rng:NextNumber(4, 6) * scale
		piece(parent, Vector3.new(s2, s2 * 0.5, s2), CFrame.new(base + Vector3.new(rng:NextNumber(-2, 2), h + rng:NextNumber(0, 2), rng:NextNumber(-2, 2))),
			if rng:NextNumber() < 0.5 then Color3.fromRGB(60, 150, 120) else Color3.fromRGB(80, 170, 130), MAT.Grass, { Name = "Leaves" })
	end
end

-- A jungle giant of the Verdant Ruins: a thick trunk on exposed roots,
-- branching into a tiered canopy, vines hanging from it.
local function giantTree(parent: Instance, base: Vector3, rng: Random)
	local BARK = Color3.fromRGB(90, 64, 42)
	local h = rng:NextNumber(18, 26)
	piece(parent, Vector3.new(4, h, 4), CFrame.new(base + Vector3.new(0, h / 2, 0)), BARK, MAT.Wood, { Name = "Trunk", CastShadow = true })
	for k = 0, 4 do
		local a = k / 5 * math.pi * 2
		piece(parent, Vector3.new(1.6, 1.6, 6), CFrame.new(base) * CFrame.Angles(0, a, 0) * CFrame.new(0, 1, -3.4) * CFrame.Angles(math.rad(25), 0, 0), BARK, MAT.Wood, { Name = "Root" })
	end
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2 + rng:NextNumber(0, 0.6)
		local by = h * rng:NextNumber(0.6, 0.85)
		local len = rng:NextNumber(6, 10)
		local br = CFrame.new(base + Vector3.new(0, by, 0)) * CFrame.Angles(0, a, 0) * CFrame.Angles(math.rad(-35), 0, 0)
		piece(parent, Vector3.new(1.6, 1.6, len), br * CFrame.new(0, 0, -len / 2), BARK, MAT.Wood, { Name = "Branch" })
		local tip = (br * CFrame.new(0, 0, -len)).Position
		local s2 = rng:NextNumber(9, 13)
		piece(parent, Vector3.new(s2, s2 * 0.55, s2), CFrame.new(tip + Vector3.new(0, 1.5, 0)), GREENS[rng:NextInteger(1, #GREENS)], MAT.Grass, { Name = "Leaves", CastShadow = true })
		for _ = 1, 2 do
			local vl = rng:NextNumber(4, 9)
			piece(parent, Vector3.new(0.35, vl, 0.35), CFrame.new(tip + Vector3.new(rng:NextNumber(-3, 3), -vl / 2, rng:NextNumber(-3, 3))), Color3.fromRGB(60, 130, 46), MAT.Grass, { Name = "Vine" })
		end
	end
	piece(parent, Vector3.new(16, 7, 16), CFrame.new(base + Vector3.new(0, h + 3, 0)), GREENS[rng:NextInteger(1, #GREENS)], MAT.Grass, { Name = "Leaves", CastShadow = true })
	piece(parent, Vector3.new(10, 5, 10), CFrame.new(base + Vector3.new(rng:NextNumber(-2, 2), h + 8, rng:NextNumber(-2, 2))), GREENS[rng:NextInteger(1, #GREENS)], MAT.Grass, { Name = "Leaves" })
end

-- Each summit landmark's look (IslandIsles `tower`).
local TOWERS: { [string]: { [string]: any } } = {
	temple = { stone = Color3.fromRGB(110, 112, 122), trim = Color3.fromRGB(86, 88, 100), mat = MAT.Slate, ledge = MOSS, ledgeMat = MAT.Grass,
		energy = WATER_BRIGHT, glow = Color3.fromRGB(40, 110, 220), ledgeDress = "trees" },
	corrupt = { stone = Color3.fromRGB(46, 36, 58), trim = Color3.fromRGB(30, 24, 38), mat = MAT.Slate, ledge = Color3.fromRGB(90, 50, 120), ledgeMat = MAT.Grass,
		energy = Color3.fromRGB(255, 60, 200), glow = Color3.fromRGB(120, 30, 140), ledgeDress = "crystals", cracks = true },
	ice = { stone = Color3.fromRGB(190, 216, 236), trim = Color3.fromRGB(150, 190, 222), mat = MAT.Ice, ledge = Color3.fromRGB(240, 248, 255), ledgeMat = MAT.Snow,
		energy = Color3.fromRGB(120, 220, 255), glow = Color3.fromRGB(60, 140, 220), ledgeDress = "icicles", roof = true },
	sunken = { stone = Color3.fromRGB(80, 130, 134), trim = Color3.fromRGB(60, 104, 110), mat = MAT.Slate, ledge = Color3.fromRGB(90, 160, 120), ledgeMat = MAT.Grass,
		energy = Color3.fromRGB(90, 240, 255), glow = Color3.fromRGB(30, 120, 160), ledgeDress = "crystals" },
	spire = { stone = OBSIDIAN, trim = OBSIDIAN2, mat = MAT.Slate, ledge = SILVER, ledgeMat = MAT.Metal,
		energy = CRIMSON, glow = Color3.fromRGB(120, 20, 40), cracks = true, roof = true },
}

-- A snow pine of the Frozen Isle: a dark trunk, stacked tiers of needles,
-- each capped in snow.
local function pine(parent: Instance, base: Vector3, rng: Random, scale: number)
	local h = 3 * scale
	piece(parent, Vector3.new(1.4 * scale, h + 1, 1.4 * scale), CFrame.new(base + Vector3.new(0, (h - 1) / 2, 0)), Color3.fromRGB(70, 52, 40), MAT.Wood, { Name = "Trunk" })
	local y = h
	for k = 0, 3 do
		local w = (9 - k * 2) * scale
		local th = 2.6 * scale
		piece(parent, Vector3.new(w, th, w), CFrame.new(base + Vector3.new(0, y + th / 2, 0)) * CFrame.Angles(0, k * 0.4, 0),
			if k % 2 == 0 then Color3.fromRGB(40, 86, 66) else Color3.fromRGB(50, 100, 76), MAT.Grass, { Name = "Needles", CastShadow = k == 0 })
		piece(parent, Vector3.new(w * 0.82, 0.6 * scale, w * 0.82), CFrame.new(base + Vector3.new(0, y + th + 0.25 * scale, 0)) * CFrame.Angles(0, k * 0.4, 0),
			Color3.fromRGB(240, 246, 252), MAT.Snow, { Name = "Snow" })
		y += th * 0.85
	end
end

function IslandScenery.Build(origin: Vector3, field: any, rng: Random, parent: Instance, groundAt: (Vector3, number?) -> number?, taken: { any })
	local SHAPE = field.shape
	local def = field.def
	local P = SHAPE.plateau
	local RV = SHAPE.river or { width = 10, depth = 3 }
	local R = SHAPE.radius

	-- ── The river: its falls and bridges ────────────────────────────────────
	local line = field.riverLine
	local falls = 0
	for i = 2, #line do
		local a, b = line[i - 1], line[i]
		local intoSea = b.Y < -0.5
		local drop = if intoSea then a.Y else a.Y - b.Y
		if drop <= 3 then continue end
		local dir = Vector3.new(b.X - a.X, 0, b.Z - a.Z).Unit
		local lip = origin + Vector3.new(a.X, a.Y, a.Z) + dir * 1
		fall(parent, lip, dir, RV.width + 1, drop, def.frozen)
		falls += 1
		-- a bridge across the top of every fall below the summit's
		if falls > 1 then
			local at = Vector3.new(a.X, 0, a.Z) - dir * 4
			local across = Vector3.new(-dir.Z, 0, dir.X)
			local half = RV.width / 2 + 5
			local pa, pb = origin + at - across * half, origin + at + across * half
			local deck = math.max(a.Y + 2.2, math.min(groundAt(pa) or a.Y, groundAt(pb) or a.Y) + 0.3)
			bridge(parent, Vector3.new(pa.X, deck, pa.Z), Vector3.new(pb.X, deck, pb.Z), 7)
			table.insert(taken, { pos = origin + at, r = half })
		end
		if intoSea then break end
	end

	-- ── The bridges between the islets ──────────────────────────────────────
	for _, br in ipairs(field.bridges) do
		local a, b = origin + br.a, origin + br.b
		span(parent, a, b, br.kind, rng)
		table.insert(taken, { pos = a, r = 9 })
		table.insert(taken, { pos = b, r = 9 })
	end

	-- ── The lava rivers, from the summit down ────────────────────────────────
	for li, bearing in ipairs(def.lava or {}) do
		local off = li * 7
		local th = math.rad(bearing)
		local cr = field.coast(th)
		local prev: Vector3? = nil
		local k = 0
		local rr = P.radius + 10
		while rr < cr * 1.12 do
			local lp = Vector3.new(math.cos(th) * rr, 0, math.sin(th) * rr)
			lp += Vector3.new(-math.sin(th), 0, math.cos(th)) * math.sin(rr / 22 + off) * 7
			local wp = origin + lp
			local y = groundAt(wp)
			if y and y < 2 then
				if prev then break end -- (the shore: it pours into the sea below)
				rr += 4
				continue -- (not on the volcano yet)
			end
			if field.onPath(lp.X, lp.Z) then prev = nil end -- (it runs under the stairs)
			if y and not field.onPath(lp.X, lp.Z) then
				local here = Vector3.new(wp.X, y + 0.15, wp.Z)
				if prev then
					local drop = prev.Y - here.Y
					local len = (Vector3.new(here.X, 0, here.Z) - Vector3.new(prev.X, 0, prev.Z)).Magnitude
					if drop > 3 then
						-- a lava fall down the terrace's face
						local dir = (Vector3.new(here.X, 0, here.Z) - Vector3.new(prev.X, 0, prev.Z)).Unit
						piece(parent, Vector3.new(4.4, drop, 0.8), CFrame.lookAt(prev + dir * 1, prev + dir * 2) * CFrame.new(0, -drop / 2, 0), LAVA, MAT.Neon,
							{ CanCollide = false, CanQuery = false, Name = "LavaFall" })
					end
					local seg = piece(parent, Vector3.new(4.4, 0.4, len + 0.6), CFrame.lookAt((prev + here) / 2, here), LAVA, MAT.Neon,
						{ CanCollide = false, CanQuery = false, Name = "Lava" })
					piece(parent, Vector3.new(7, 0.3, len + 0.6), CFrame.lookAt((prev + here) / 2, here) * CFrame.new(0, -0.08, 0), Color3.fromRGB(60, 22, 14), MAT.CrackedLava,
						{ CanCollide = false, CanQuery = false, Name = "LavaBank" })
					k += 1
					if k % 6 == 0 then
						-- (no light: the neon glows on its own)
						emitter(seg, {
							Texture = "rbxasset://textures/particles/sparkles_main.dds",
							Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), LAVA),
							Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) }),
							Lifetime = NumberRange.new(0.8, 1.6),
							Speed = NumberRange.new(2, 5),
							EmissionDirection = Enum.NormalId.Top,
							SpreadAngle = Vector2.new(30, 30),
							Rate = 4,
						})
					end
				end
				prev = here
			end
			rr += 4
		end
		-- off the cliff into the sea
		if prev then
			local out = Vector3.new(math.cos(th), 0, math.sin(th))
			local drop = math.max(prev.Y + 1, 4)
			piece(parent, Vector3.new(5, drop, 1), CFrame.lookAt(prev + out * 1.5, prev + out * 3) * CFrame.new(0, -drop / 2, 0), LAVA, MAT.Neon,
				{ CanCollide = false, CanQuery = false, Name = "LavaFall" })
			emitter(piece(parent, Vector3.new(8, 1, 8), CFrame.new(Vector3.new(prev.X, 0.5, prev.Z) + out * 3), Color3.new(), MAT.SmoothPlastic,
				{ Transparency = 1, CanCollide = false, CanQuery = false, Name = "Steam" }), {
				Texture = "rbxasset://textures/particles/smoke_main.dds",
				Color = ColorSequence.new(Color3.fromRGB(230, 230, 235)),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) }),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 10) }),
				Lifetime = NumberRange.new(2, 3.5),
				Speed = NumberRange.new(3, 6),
				EmissionDirection = Enum.NormalId.Top,
				Rate = 6,
			})
		end
	end

	-- ── The summit's landmark ───────────────────────────────────────────────
	local style = TOWERS[def.tower]
	if style then
		local north = Vector3.new(0, 0, 1)
		-- (it stands on the shoulder behind the summit, towering over it)
		local base0 = origin + north * (P.radius + 12)
		local FOOT = math.min(groundAt(base0) or (P.height - 18), P.height)
		local base = Vector3.new(base0.X, FOOT, base0.Z)
		local face = CFrame.lookAt(base, base - north) -- facing south, over the ritual site
		local tower = Instance.new("Model")
		tower.Name = "SummitTower"
		tower.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
		tower.Parent = parent
		local y = 0
		for i, tier in ipairs(TIERS) do
			local w, h = tier[1], tier[2]
			piece(tower, Vector3.new(w, h, w), face * CFrame.new(0, y + h / 2, 0), style.stone, style.mat, { Name = "Tier" .. i, CastShadow = true })
			-- a ledge, battlements, pillars at the corners
			piece(tower, Vector3.new(w + 0.6, 1, w + 0.6), face * CFrame.new(0, y + h, 0), style.ledge, style.ledgeMat, { Name = "Ledge" })
			for k = -2, 2 do
				for _, sz in ipairs({ -1, 1 }) do
					piece(tower, Vector3.new(2, 2, 1.4), face * CFrame.new(k * w / 5.5, y + h + 1.4, sz * (w / 2 - 0.4)), style.trim, style.mat, { Name = "Merlon" })
				end
			end
			for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
				piece(tower, Vector3.new(3, h + 2, 3), face * CFrame.new(c[1] * (w / 2 - 0.5), y + h / 2 + 1, c[2] * (w / 2 - 0.5)), style.trim, style.mat, { Name = "Pillar" })
			end
			-- its energy in cracks climbing its walls; trees, crystals or icicles on its ledges
			if style.cracks then
				for _ = 1, 2 do
					local sx = rng:NextNumber(-w / 2 + 3, w / 2 - 3)
					piece(tower, Vector3.new(0.5, h * rng:NextNumber(0.4, 0.9), 0.3), face * CFrame.new(sx, y + h / 2, w / 2 + 0.1) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-20, 20))),
						style.energy, MAT.Neon, { CanCollide = false, CanQuery = false, Name = "Crack" })
				end
			end
			if i <= 3 and style.ledgeDress == "trees" then
				for _, sx in ipairs({ -1, 1 }) do
					blockTree(tower, (face * CFrame.new(sx * (w / 2 - 4), y + h + 0.6, -(w / 2 - 4))).Position, rng, 0.7)
				end
			elseif i <= 4 and style.ledgeDress == "crystals" then
				for _, sx in ipairs({ -1, 1 }) do
					local ch = rng:NextNumber(3, 6)
					piece(tower, Vector3.new(1.2, ch, 1.2), face * CFrame.new(sx * (w / 2 - 3), y + h + ch / 2, -(w / 2 - 3)) * CFrame.Angles(0.3, 0, sx * 0.3), style.energy, MAT.Neon,
						{ CanCollide = false, CanQuery = false, Name = "Crystal" })
				end
			elseif style.ledgeDress == "icicles" then
				for k = -2, 2 do
					local ih = rng:NextNumber(2, 5)
					piece(tower, Vector3.new(0.8, ih, 0.8), face * CFrame.new(k * w / 5.5, y + h - ih / 2, -(w / 2 + 0.5)), Color3.fromRGB(220, 240, 255), MAT.Ice,
						{ CanCollide = false, CanQuery = false, Name = "Icicle" })
				end
			end
			y += h
		end
		if style.roof then
			for k = 0, 3 do
				local w = 10 - k * 2.4
				piece(tower, Vector3.new(w, 4, w), face * CFrame.new(0, y + 2 + k * 4, 0), if k % 2 == 0 then style.stone else style.trim, style.mat, { Name = "Roof" })
			end
			piece(tower, Vector3.new(0.6, 10, 0.6), face * CFrame.new(0, y + 21, 0), style.ledge, MAT.Metal, { Name = "Finial" })
		end
		-- the channel down its face, stepping in with each tier, into a pool at its foot
		local ty = 0
		local W0 = TIERS[1][1]
		for _, tier in ipairs(TIERS) do
			local w, h = tier[1], tier[2]
			piece(tower, Vector3.new(5, h, 0.6), face * CFrame.new(0, ty + h / 2, -w / 2 - 0.35), style.energy, MAT.Neon,
				{ CanCollide = false, CanQuery = false, Transparency = 0.1, Name = "Channel" })
			piece(tower, Vector3.new(8, h, 0.3), face * CFrame.new(0, ty + h / 2, -w / 2 - 0.15), style.glow, MAT.Neon,
				{ CanCollide = false, CanQuery = false, Transparency = 0.3, Name = "ChannelGlow" })
			if ty > 0 then
				piece(tower, Vector3.new(5, 0.6, (W0 - w) / 2 + 0.6), face * CFrame.new(0, ty + 0.2, -w / 2 - (W0 - w) / 4), style.energy, MAT.Neon,
					{ CanCollide = false, CanQuery = false, Transparency = 0.1, Name = "Channel" })
			end
			ty += h
		end
		local pool = piece(tower, Vector3.new(0.6, 14, 14), face * CFrame.new(0, P.height - FOOT + 0.35, -W0 / 2 - 4) * CFrame.Angles(0, 0, math.rad(90)), style.energy, MAT.Neon,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.25, CanCollide = false, CanQuery = false, Name = "Pool" })
		emitter(pool, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(style.glow, style.energy),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.8, 1.6),
			Speed = NumberRange.new(2, 5),
			EmissionDirection = Enum.NormalId.Right,
			SpreadAngle = Vector2.new(50, 50),
			Rate = 14,
		})
		table.insert(taken, { pos = base, r = 28 })

		if def.tower == "spire" then
			-- black towers round the summit's edge, pointed roofs, broken bridges
			-- reaching between them; floating monoliths chained to the spire
			local towers = {}
			for k = 0, 3 do
				local a = math.rad(45 + k * 90)
				local d = P.radius + 6
				local tb = origin + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)
				local gy = groundAt(tb) or P.height
				local th = rng:NextNumber(30, 44)
				local tw = 10
				local tcf = CFrame.new(tb.X, gy, tb.Z) * CFrame.Angles(0, -a, 0)
				piece(parent, Vector3.new(tw, th, tw), tcf * CFrame.new(0, th / 2, 0), OBSIDIAN, MAT.Slate, { Name = "SpireTower", CastShadow = true, CanCollide = true })
				piece(parent, Vector3.new(tw + 1, 1, tw + 1), tcf * CFrame.new(0, th, 0), SILVER, MAT.Metal, { Name = "Ledge", CanCollide = true })
				for r = 0, 3 do
					local rw = tw - r * 2.4
					piece(parent, Vector3.new(rw, 3.4, rw), tcf * CFrame.new(0, th + 2.2 + r * 3.4, 0), if r % 2 == 0 then OBSIDIAN2 else OBSIDIAN, MAT.Slate, { Name = "Roof" })
				end
				piece(parent, Vector3.new(1.6, 3, 0.4), tcf * CFrame.new(0, th * 0.6, -tw / 2 - 0.15), CRIMSON, MAT.Neon, { Name = "Window", CanCollide = false, CanQuery = false })
				piece(parent, Vector3.new(0.5, th * 0.7, 0.3), tcf * CFrame.new(rng:NextNumber(-3, 3), th * 0.35, tw / 2 + 0.1), CRIMSON, MAT.Neon, { Name = "Crack", CanCollide = false, CanQuery = false })
				table.insert(towers, { top = Vector3.new(tb.X, gy + th * 0.75, tb.Z) })
				table.insert(taken, { pos = tb, r = 9 })
			end
			for k = 1, #towers do
				local a, b = towers[k].top, towers[k % #towers + 1].top
				-- (each bridge broken off partway: a stub from either tower)
				for _, e in ipairs({ { a, b }, { b, a } }) do
					local from, to = e[1], e[2]
					local len = (to - from).Magnitude * rng:NextNumber(0.22, 0.36)
					local dir = (to - from).Unit
					piece(parent, Vector3.new(5, 1.4, len), CFrame.lookAt(from + dir * (len / 2 + 5), to), OBSIDIAN2, MAT.Slate, { Name = "BrokenBridge", CanCollide = true })
				end
			end
			local spireTop = base + Vector3.new(0, 80, 0)
			for k = 0, 4 do
				local a = k / 5 * math.pi * 2 + 0.3
				local d = rng:NextNumber(60, 85)
				local at = origin + Vector3.new(math.cos(a) * d, P.height + rng:NextNumber(28, 52), math.sin(a) * d)
				local mh = rng:NextNumber(10, 16)
				local mono = CFrame.new(at) * CFrame.Angles(math.rad(rng:NextNumber(-10, 10)), a, math.rad(rng:NextNumber(-10, 10)))
				piece(parent, Vector3.new(4, mh, 3), mono, OBSIDIAN, MAT.Slate, { Name = "Monolith", CastShadow = true })
				piece(parent, Vector3.new(0.4, mh * 0.7, 0.2), mono * CFrame.new(0, 0, -1.6), CRIMSON, MAT.Neon, { Name = "Rune", CanCollide = false, CanQuery = false })
				-- a great chain from it to the spire, link by link
				local from, to = at, spireTop + Vector3.new(0, -k * 8, 0)
				local n = math.floor((to - from).Magnitude / 6)
				for c = 0, n - 1 do
					local q = from:Lerp(to, (c + 0.5) / n) - Vector3.new(0, math.sin(math.pi * (c + 0.5) / n) * 6, 0)
					piece(parent, Vector3.new(0.6, 1.8, 3.6), CFrame.lookAt(q, to) * CFrame.Angles(0, 0, if c % 2 == 0 then 0 else math.rad(90)),
						Color3.fromRGB(70, 68, 76), MAT.Metal, { Name = "ChainLink", CanCollide = false, CanQuery = false })
				end
			end
			-- beams of red and violet into the storm, leaning out from the spire
			for k = 0, 3 do
				local a = k / 4 * math.pi * 2 + 0.6
				local from = base + Vector3.new(0, 60, 0)
				local to = from + Vector3.new(math.cos(a) * 90, 260, math.sin(a) * 90)
				piece(parent, Vector3.new(2.4, 2.4, (to - from).Magnitude), CFrame.lookAt((from + to) / 2, to), if k % 2 == 0 then CRIMSON else Color3.fromRGB(170, 80, 255), MAT.Neon,
					{ CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.6, Name = "SkyBeam" })
			end
		end
	elseif def.tower == "volcano" then
		-- the crater: a jagged rim of black rock round the altar (gaps where
		-- the stairs come in), a ring of lava inside it, the eruption above
		local gaps = {}
		for _, cl in ipairs(SHAPE.climbs) do table.insert(gaps, cl[1]) end
		local function inGap(deg: number): boolean
			for _, g in ipairs(gaps) do
				if math.abs((deg - g + 180) % 360 - 180) < 16 then return true end
			end
			return false
		end
		for k = 0, 27 do
			local deg = k / 28 * 360
			if inGap(deg) then continue end
			local a = math.rad(deg)
			local d = P.radius + rng:NextNumber(4, 12)
			local at = origin + Vector3.new(math.cos(a) * d, P.height, math.sin(a) * d)
			local h = rng:NextNumber(8, 22)
			piece(parent, Vector3.new(rng:NextNumber(8, 13), h, rng:NextNumber(6, 10)), CFrame.new(at + Vector3.new(0, h / 2 - 2, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-8, 8)), -a, math.rad(rng:NextNumber(-10, 10))),
				Color3.fromRGB(38, 32, 34), MAT.Basalt, { Name = "CraterRim", CanCollide = true, CastShadow = true })
			if k % 3 == 0 then
				piece(parent, Vector3.new(0.4, h * 0.7, 0.3), CFrame.new(at + Vector3.new(0, h * 0.35, 0)) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -3.5), LAVA, MAT.Neon,
					{ CanCollide = false, CanQuery = false, Name = "Vein" })
			end
		end
		for k = 0, 35 do
			local deg = k / 36 * 360
			if inGap(deg) then continue end
			local a = math.rad(deg)
			local d = 67
			local seg = 2 * math.pi * d / 36
			piece(parent, Vector3.new(seg + 0.4, 0.4, 4), CFrame.new(origin + Vector3.new(math.cos(a) * d, P.height + 0.25, math.sin(a) * d)) * CFrame.Angles(0, -a + math.pi / 2, 0),
				LAVA, MAT.Neon, { CanCollide = false, CanQuery = false, Name = "LavaRing" })
		end
		-- the eruption: a column of black smoke and fire, embers raining
		local vent = piece(parent, Vector3.new(30, 4, 30), CFrame.new(origin + Vector3.new(0, P.height + 50, 70)), Color3.new(), MAT.SmoothPlastic,
			{ Transparency = 1, CanCollide = false, CanQuery = false, Name = "Eruption" })
		emitter(vent, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(60, 50, 50), Color3.fromRGB(20, 18, 20)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 16), NumberSequenceKeypoint.new(1, 60) }),
			Lifetime = NumberRange.new(6, 10),
			Speed = NumberRange.new(14, 24),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(12, 12),
			Rate = 5,
			Shape = Enum.ParticleEmitterShape.Box,
		})
		emitter(vent, {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 210, 110), LAVA),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 14), NumberSequenceKeypoint.new(1, 4) }),
			Lifetime = NumberRange.new(1, 1.8),
			Speed = NumberRange.new(20, 34),
			EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(15, 15),
			LightEmission = 1,
			Rate = 10,
		})
		emitter(vent, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), LAVA),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(3, 5),
			Speed = NumberRange.new(30, 50),
			SpreadAngle = Vector2.new(40, 40),
			Acceleration = Vector3.new(0, -30, 0),
			EmissionDirection = Enum.NormalId.Top,
			LightEmission = 1,
			Rate = 14,
		})
		-- the crater's back wall: a great cone of black rock behind the altar
		for k = 0, 3 do
			local w = 70 - k * 14
			piece(parent, Vector3.new(w, 14, w * 0.6), CFrame.new(origin + Vector3.new(0, P.height + 7 + k * 14, 70 + k * 3)), Color3.fromRGB(34 + k * 4, 28 + k * 3, 30 + k * 3), MAT.Basalt,
				{ Name = "Cone", CanCollide = true, CastShadow = true })
		end
		table.insert(taken, { pos = origin + Vector3.new(0, 0, 70), r = 36 })
	end

	-- ── Trees on the sea stacks, a rock arch by the one that has it ─────────
	for _, st in ipairs(SHAPE.stacks) do
		local th = math.rad(st[1])
		local cr = field.coast(th) * st[2]
		local c = origin + Vector3.new(math.cos(th) * cr, 0, math.sin(th) * cr)
		for _ = 1, math.max(1, math.floor(st[3] / 6)) do
			local p = c + Vector3.new(rng:NextNumber(-st[3] * 0.4, st[3] * 0.4), 0, rng:NextNumber(-st[3] * 0.4, st[3] * 0.4))
			local y = groundAt(p)
			if y and y > 6 then blockTree(parent, Vector3.new(p.X, y, p.Z), rng, rng:NextNumber(0.8, 1.2)) end
		end
		if st[5] then
			local out = Vector3.new(math.cos(th), 0, math.sin(th))
			local side = Vector3.new(-out.Z, 0, out.X)
			local at = c + side * (st[3] + 16)
			local h = st[4] * 0.7
			local face = CFrame.lookAt(at, at + side)
			for _, z in ipairs({ -12, 12 }) do
				piece(parent, Vector3.new(14, h + 8, 9), face * CFrame.new(0, h / 2 - 4, z), STONE, MAT.Slate, { Name = "ArchLeg", CanCollide = true, CastShadow = true })
			end
			piece(parent, Vector3.new(14, 9, 34), face * CFrame.new(0, h + 4, 0), Color3.fromRGB(76, 78, 94), MAT.Slate, { Name = "ArchTop", CanCollide = true, CastShadow = true })
			piece(parent, Vector3.new(14.4, 1.4, 34.4), face * CFrame.new(0, h + 9, 0), MOSS, MAT.Grass, { Name = "ArchMoss" })
			blockTree(parent, (face * CFrame.new(0, h + 9.5, 8)).Position, rng, 0.9)
		end
	end

	-- ── Boulders in the shallows ────────────────────────────────────────────
	for _ = 1, 90 do
		local th = rng:NextNumber(0, math.pi * 2)
		local rr = field.coast(th) * rng:NextNumber(1.0, 1.16)
		local x, z = math.cos(th) * rr, math.sin(th) * rr
		local h = field.height(x, z)
		if h > -0.6 or h < -9 then continue end
		local sz = rng:NextNumber(4, 9)
		local top = rng:NextNumber(0.5, 4)
		piece(parent, Vector3.new(sz, top - h + 1, sz * rng:NextNumber(0.7, 1.2)),
			CFrame.new(origin + Vector3.new(x, (top + h - 1) / 2, z)) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0),
			if rng:NextNumber() < 0.5 then STONE else Color3.fromRGB(70, 72, 86), MAT.Slate, { Name = "Boulder", CanCollide = true })
	end

	-- ── Trees over every green ledge ────────────────────────────────────────
	-- (thickest in clumps, thinning out; none on the paths, the beaches, the
	-- volcano, the summit or anything already placed)
	local TREE_GRID = 12
	local trees = 0
	local seedN = rng:NextNumber(0, 100)
	for gx = -R * 1.1, R * 1.1, TREE_GRID do
		for gz = -R * 1.1, R * 1.1, TREE_GRID do
			local x = gx + rng:NextNumber(-4, 4)
			local z = gz + rng:NextNumber(-4, 4)
			local clump = math.noise(x / 70 + seedN, z / 70)
			if clump < -0.15 or rng:NextNumber() > 0.42 + clump then continue end
			local h = field.height(x, z)
			if h < 8 or math.sqrt(x * x + z * z) < P.radius + 6 then continue end
			if field.onPath(x, z) or field.river(x, z) > 0 then continue end
			local reg = field.region(x, z)
			if reg == "highlands" or reg == "shore" or reg == "sanctuary" then continue end
			if reg == "frozen" and rng:NextNumber() < 0.25 then continue end
			if reg == "sunken" and rng:NextNumber() < 0.6 then continue end
			-- (on a ledge, not over a cliff's edge)
			if math.abs(field.height(x + 5, z) - h) > 1.5 or math.abs(field.height(x - 5, z) - h) > 1.5
				or math.abs(field.height(x, z + 5) - h) > 1.5 or math.abs(field.height(x, z - 5) - h) > 1.5 then continue end
			local wp = origin + Vector3.new(x, 0, z)
			local clear = true
			for _, t in ipairs(taken) do
				if (Vector3.new(t.pos.X, 0, t.pos.Z) - wp).Magnitude < t.r * 1.35 + 6 then
					clear = false
					break
				end
			end
			if not clear then continue end
			local y = groundAt(wp)
			if not y then continue end
			local at = Vector3.new(wp.X, y, wp.Z)
			if reg == "forest" then
				twistedTree(parent, at, rng, rng:NextNumber(0.9, 1.5))
			elseif reg == "frozen" then
				pine(parent, at, rng, rng:NextNumber(0.9, 1.5))
			elseif reg == "sunken" then
				mangrove(parent, at, rng, rng:NextNumber(0.8, 1.2))
			elseif rng:NextNumber() < 0.06 then
				giantTree(parent, at, rng)
			else
				blockTree(parent, at, rng, rng:NextNumber(0.9, 1.45))
			end
			trees += 1
		end
		task.wait()
	end

	-- ── Vines down the Verdant Ruins' cliffs ────────────────────────────────
	local vines = 0
	for gx = -R * 1.1, R * 1.1, 9 do
		for gz = -R * 1.1, R * 1.1, 9 do
			if vines > 340 then break end
			local x, z = gx + rng:NextNumber(-3, 3), gz + rng:NextNumber(-3, 3)
			local h = field.height(x, z)
			if h < 14 or field.region(x, z) ~= "ruins" or field.onPath(x, z) then continue end
			for _, d in ipairs({ Vector3.new(6, 0, 0), Vector3.new(-6, 0, 0), Vector3.new(0, 0, 6), Vector3.new(0, 0, -6) }) do
				local below = field.height(x + d.X, z + d.Z)
				if h - below > 7 and rng:NextNumber() < 0.5 then
					local len = math.min(h - below - 1, rng:NextNumber(5, 14))
					local at = origin + Vector3.new(x, h - len / 2, z) + d.Unit * 2.9
					piece(parent, Vector3.new(if d.X ~= 0 then 0.3 else rng:NextNumber(1.5, 3), len, if d.X ~= 0 then rng:NextNumber(1.5, 3) else 0.3), CFrame.new(at),
						GREENS[rng:NextInteger(1, #GREENS)], MAT.Grass, { Name = "Vine" })
					vines += 1
					break
				end
			end
		end
		task.wait()
	end

	-- ── Coral and seaweed in the Shipwreck Coast's shallows ─────────────────
	local CORAL = { Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 160, 80), Color3.fromRGB(120, 220, 200), Color3.fromRGB(200, 120, 255) }
	local corals = 0
	for _ = 1, 1400 do
		if corals > 150 then break end
		local x, z = rng:NextNumber(-R * 1.15, R * 1.15), rng:NextNumber(-R * 1.15, R * 1.15)
		local h = field.height(x, z)
		local creg = field.region(x, z)
		if h > -1.2 or h < -7 or (creg ~= "shore" and creg ~= "sunken") then continue end
		local at = origin + Vector3.new(x, h, z)
		if rng:NextNumber() < 0.6 then
			for _ = 1, rng:NextInteger(2, 4) do
				local ch = rng:NextNumber(1, 3)
				piece(parent, Vector3.new(0.7, ch, 0.7), CFrame.new(at + Vector3.new(rng:NextNumber(-1.2, 1.2), ch / 2, rng:NextNumber(-1.2, 1.2))) * CFrame.Angles(rng:NextNumber(-0.4, 0.4), 0, rng:NextNumber(-0.4, 0.4)),
					CORAL[rng:NextInteger(1, #CORAL)], MAT.SmoothPlastic, { Name = "Coral" })
			end
		else
			for _ = 1, 3 do
				local wh = rng:NextNumber(2, math.min(5, -h + 0.5))
				piece(parent, Vector3.new(0.4, wh, 0.2), CFrame.new(at + Vector3.new(rng:NextNumber(-1, 1), wh / 2, rng:NextNumber(-1, 1))) * CFrame.Angles(0, rng:NextNumber(0, 3), rng:NextNumber(-0.2, 0.2)),
					Color3.fromRGB(60, 130, 70), MAT.Grass, { Name = "Seaweed" })
			end
		end
		corals += 1
	end

	-- ── Ice down the Frozen Isle's cliffs ───────────────────────────────────
	if def.frozen then
		local ices = 0
		for gx = -R * 1.05, R * 1.05, 10 do
			for gz = -R * 1.05, R * 1.05, 10 do
				if ices > 220 then break end
				local x, z = gx + rng:NextNumber(-3, 3), gz + rng:NextNumber(-3, 3)
				local h = field.height(x, z)
				if h < 20 or field.onPath(x, z) then continue end
				for _, d in ipairs({ Vector3.new(6, 0, 0), Vector3.new(-6, 0, 0), Vector3.new(0, 0, 6), Vector3.new(0, 0, -6) }) do
					local below = field.height(x + d.X, z + d.Z)
					if h - below > 9 and rng:NextNumber() < 0.45 then
						local len = math.min(h - below - 1, rng:NextNumber(6, 18))
						local w = rng:NextNumber(2, 5)
						local at = origin + Vector3.new(x, h - len / 2, z) + d.Unit * 3
						piece(parent, Vector3.new(if d.X ~= 0 then 0.8 else w, len, if d.X ~= 0 then w else 0.8), CFrame.new(at),
							Color3.fromRGB(196, 228, 248), MAT.Ice, { Name = "IceSheet", Transparency = 0.1 })
						ices += 1
						break
					end
				end
			end
			task.wait()
		end
		-- the river and the lakes frozen over (ice to walk on)
		for i = 1, #field.riverLine, 3 do
			local q = field.riverLine[i]
			local nxt = field.riverLine[math.min(#field.riverLine, i + 3)]
			local dir = Vector3.new(nxt.X - q.X, 0, nxt.Z - q.Z)
			local cf = if dir.Magnitude > 0.1 then CFrame.lookAt(origin + Vector3.new(q.X, q.Y + 0.4, q.Z), origin + Vector3.new(nxt.X, q.Y + 0.4, nxt.Z)) else CFrame.new(origin + Vector3.new(q.X, q.Y + 0.4, q.Z))
			piece(parent, Vector3.new(RV.width + 2, 0.4, 6.4), cf, Color3.fromRGB(190, 226, 246), MAT.Ice, { Name = "RiverIce", Transparency = 0.15, CanCollide = true })
		end
		for _, pl in ipairs(field.pools) do
			piece(parent, Vector3.new(0.4, pl.r * 2, pl.r * 2), CFrame.new(origin + Vector3.new(pl.x, pl.y + 0.4, pl.z)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(196, 230, 248), MAT.Ice,
				{ Name = "LakeIce", Shape = Enum.PartType.Cylinder, Transparency = 0.12, CanCollide = true })
		end
	end

	-- ── Lily pads on the Sunken Isle's pools ────────────────────────────────
	if def.lilies then
		for _, pl in ipairs(field.pools) do
			for _ = 1, math.floor(pl.r / 2.5) do
				local a = rng:NextNumber(0, math.pi * 2)
				local d = math.sqrt(rng:NextNumber()) * pl.r * 0.85
				local at = origin + Vector3.new(pl.x + math.cos(a) * d, pl.y + 0.6, pl.z + math.sin(a) * d)
				piece(parent, Vector3.new(0.15, rng:NextNumber(1.6, 3), rng:NextNumber(1.6, 3)), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
					Color3.fromRGB(70, 160, 70), MAT.SmoothPlastic, { Shape = Enum.PartType.Cylinder, CanCollide = false, CanQuery = false, Name = "Lily" })
				if rng:NextNumber() < 0.25 then
					piece(parent, Vector3.new(0.6, 0.5, 0.6), CFrame.new(at + Vector3.new(0, 0.3, 0)), Color3.fromRGB(255, 190, 220), MAT.SmoothPlastic, { CanCollide = false, CanQuery = false, Name = "LilyFlower" })
				end
			end
		end
	end

	-- ── The Shattered Isle: the void, the floating landmasses ───────────────
	if def.void then
		local VOIDC = Color3.fromRGB(40, 10, 64)
		piece(parent, Vector3.new(0.6, R * 2.5, R * 2.5), CFrame.new(origin + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), VOIDC, MAT.SmoothPlastic,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.15, CanCollide = false, CanQuery = false, Name = "Void" })
		local glowV = piece(parent, Vector3.new(0.3, R * 2.5, R * 2.5), CFrame.new(origin + Vector3.new(0, 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(150, 60, 255), MAT.Neon,
			{ Shape = Enum.PartType.Cylinder, Transparency = 0.88, CanCollide = false, CanQuery = false, Name = "VoidGlow" })
		emitter(glowV, {
			Texture = "rbxasset://textures/particles/smoke_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(120, 50, 200), Color3.fromRGB(30, 10, 50)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 10), NumberSequenceKeypoint.new(1, 30) }),
			Lifetime = NumberRange.new(5, 8),
			Speed = NumberRange.new(1, 3),
			Rate = 4,
			Shape = Enum.ParticleEmitterShape.Box,
		})
		for k = 0, 9 do
			local a = k / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local d = R * rng:NextNumber(0.45, 1.05)
			local y = rng:NextNumber(60, 160)
			local at = origin + Vector3.new(math.cos(a) * d, y, math.sin(a) * d)
			local w = rng:NextNumber(18, 34)
			local rock = CFrame.new(at) * CFrame.Angles(math.rad(rng:NextNumber(-6, 6)), rng:NextNumber(0, 6), math.rad(rng:NextNumber(-6, 6)))
			piece(parent, Vector3.new(w, 4, w * 0.8), rock, Color3.fromRGB(44, 38, 50), MAT.Slate, { Name = "FloatingLand", CastShadow = true })
			piece(parent, Vector3.new(w + 0.4, 1, w * 0.8 + 0.4), rock * CFrame.new(0, 2.4, 0), Color3.fromRGB(60, 40, 70), MAT.Grass, { Name = "FloatingTop" })
			-- (its underside tapering to a point)
			for t = 1, 3 do
				local f = 1 - t * 0.25
				piece(parent, Vector3.new(w * f, 5, w * 0.8 * f), rock * CFrame.new(rng:NextNumber(-1, 1), -2 - t * 5, rng:NextNumber(-1, 1)), Color3.fromRGB(36 + t * 4, 30, 42), MAT.Slate, { Name = "FloatingRoot" })
			end
			piece(parent, Vector3.new(0.4, 12, 0.3), rock * CFrame.new(w * 0.3, -6, -w * 0.4), CRIMSON, MAT.Neon, { Name = "Crack", CanCollide = false, CanQuery = false })
			if k % 3 == 0 then
				-- an upside-down ruin hanging from it: columns and a lintel, inverted
				for _, sx in ipairs({ -w * 0.3, w * 0.3 }) do
					piece(parent, Vector3.new(2.4, 12, 2.4), rock * CFrame.new(sx, -8, 0), Color3.fromRGB(120, 116, 128), MAT.Marble, { Name = "HangingColumn" })
				end
				piece(parent, Vector3.new(w * 0.8, 2.4, 3.4), rock * CFrame.new(0, -15, 0), Color3.fromRGB(104, 100, 112), MAT.Marble, { Name = "HangingLintel" })
			elseif k % 3 == 1 then
				-- a monolith standing on it, a crimson rune
				piece(parent, Vector3.new(3, 12, 2.4), rock * CFrame.new(0, 8.5, 0), Color3.fromRGB(30, 26, 34), MAT.Slate, { Name = "Monolith" })
				piece(parent, Vector3.new(0.4, 8, 0.2), rock * CFrame.new(0, 8.5, -1.3), CRIMSON, MAT.Neon, { Name = "Rune", CanCollide = false, CanQuery = false })
			end
		end
	end
end

-- ── The crossings between the isles ─────────────────────────────────────────
-- From `a` (the end of one isle's high ground) to `b` (the next's): stone
-- pillars standing in the sea like stepping stones, a span of the next
-- isle's kind between each pair, glowing arrows down the middle pointing
-- on; at its start a gate, sealed by a wall of the next isle's light.
function IslandScenery.Crossing(parent: Instance, a: Vector3, b: Vector3, nextIsle: any, rng: Random): (Model, Model)
	local model = Instance.new("Model")
	model.Name = "Crossing_" .. nextIsle.level
	model.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	model.Parent = parent
	local kind = nextIsle.crossing
	local color = nextIsle.altar.beam
	local flat = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = flat.Magnitude
	local dir = flat.Unit
	local n = math.max(2, math.ceil(len / 54))
	local pts = {}
	for k = 0, n do table.insert(pts, a:Lerp(b, k / n)) end
	local look = SPANS[kind] or SPANS.stone
	local pillarColor = if kind == "wood" then Color3.fromRGB(92, 94, 108) else look.b
	local pillarMat = if kind == "wood" then MAT.Slate else look.mat
	for k = 2, n do
		local p = pts[k]
		local h = p.Y - SEA_BED
		-- the stepping stone: a rock in the sea, a pillar up from it, a platform
		piece(model, Vector3.new(22, 10, 22), CFrame.new(Vector3.new(p.X, SEA_BED + 6, p.Z)) * CFrame.Angles(0, rng:NextNumber(0, 1), 0), Color3.fromRGB(76, 78, 90), MAT.Slate,
			{ Name = "SteppingRock", CanCollide = true, CastShadow = true })
		piece(model, Vector3.new(12, h - 1.6, 12), CFrame.lookAt(Vector3.zero, dir) + Vector3.new(p.X, SEA_BED + (h - 1.6) / 2, p.Z), pillarColor, pillarMat,
			{ Name = "CrossingPillar", CanCollide = true, CastShadow = true })
		piece(model, Vector3.new(14, 1.6, 14), CFrame.lookAt(Vector3.zero, dir) + Vector3.new(p.X, p.Y - 0.8, p.Z), look.a, pillarMat,
			{ Name = "CrossingPlatform", CanCollide = true })
		-- a lantern of the next isle's light on each
		piece(model, Vector3.new(0.6, 5, 0.6), CFrame.new(p + Vector3.new(0, 2.5, 0) + dir:Cross(Vector3.yAxis) * 6), Color3.fromRGB(50, 46, 50), MAT.Metal, { Name = "LanternPost" })
		piece(model, Vector3.new(1.2, 1.2, 1.2), CFrame.new(p + Vector3.new(0, 5.6, 0) + dir:Cross(Vector3.yAxis) * 6), color, MAT.Neon, { Name = "Lantern", CanCollide = false, CanQuery = false })
	end
	for k = 1, n do
		span(model, pts[k], pts[k + 1], kind, rng)
	end
	-- the way on: a glowing line and chevrons pointing to the next isle
	local d = 8
	while d < len - 6 do
		local p = a:Lerp(b, d / len) + Vector3.new(0, 0.62, 0)
		local cf = CFrame.lookAt(p, p + Vector3.new(b.X - a.X, b.Y - a.Y, b.Z - a.Z))
		for _, sx in ipairs({ -1, 1 }) do
			piece(model, Vector3.new(0.5, 0.12, 3.2), cf * CFrame.new(sx * 1, 0, 0) * CFrame.Angles(0, math.rad(sx * 40), 0), color, MAT.Neon,
				{ Name = "Arrow", CanCollide = false, CanQuery = false })
		end
		d += 18
	end
	-- the seal at its start
	local seal = Instance.new("Model")
	seal.Name = "Seal"
	local gate = CFrame.lookAt(a, a + dir) * CFrame.new(0, 0, -4)
	for _, sx in ipairs({ -1, 1 }) do
		piece(model, Vector3.new(3, 20, 3), gate * CFrame.new(sx * 7, 10, 0), Color3.fromRGB(56, 54, 62), MAT.Slate, { Name = "GatePillar", CanCollide = true, CastShadow = true })
		piece(model, Vector3.new(1, 1.6, 1), gate * CFrame.new(sx * 7, 20.8, 0), color, MAT.Neon, { Name = "GateFlame", CanCollide = false, CanQuery = false })
	end
	piece(model, Vector3.new(18, 2.4, 3.4), gate * CFrame.new(0, 20.6, 0), Color3.fromRGB(70, 66, 76), MAT.Slate, { Name = "GateLintel", CanCollide = true })
	local wall = piece(seal, Vector3.new(11.5, 18.6, 0.6), gate * CFrame.new(0, 9.4, 0), color, MAT.Neon, { Name = "SealWall", CanCollide = true, Transparency = 0.45 })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(260, 60)
	gui.StudsOffset = Vector3.new(0, 12, 0)
	gui.MaxDistance = 140
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.3
	label.Text = "SEALED\nslay this isle's guardian at its altar"
	label.Parent = gui
	gui.Parent = wall
	seal.Parent = model
	return model, seal
end

-- The seal falls: its light fades and the way is open.
function IslandScenery.Unseal(seal: Model)
	for _, d in ipairs(seal:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			TweenService:Create(d, TweenInfo.new(1.6), { Transparency = 1 }):Play()
		elseif d:IsA("BillboardGui") then
			d.Enabled = false
		end
	end
	task.delay(1.8, function() seal:Destroy() end)
end

return IslandScenery
