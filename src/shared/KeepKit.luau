--!strict
--[[
	KeepKit.luau
	The Infernal Keep's pieces (after its concept art): a fortress of dark
	purple-brown stone cut in big square blocks, heavy capped battlements with
	iron spikes, red banners with a black trident, black iron chains, fire
	pedestals, lava glowing up from pits between the walkways. Built from
	parts like the rest of the game. Each builder returns a Model at the
	origin, its pivot where it sits: a floor tile's at the middle of its top,
	everything else at the middle of its base.

	  KeepKit.Build(name) → Model?      one piece
	  KeepKit.PIECES                    every piece: { name, kind, build }
	  KeepKit.LavaPit(size, depth) → Model    a pit of lava (its pivot at the
	                                    middle of its rim, on the floor)
	  KeepKit.Chain(a, b, sag, parent, thick?)  an iron chain hung from a to b
	  KeepKit.ChainPost() → Model       a post to hang one from (ring at CHAIN_Y)
	  KeepKit.Spire(height, seed) → Model     a jagged rock spire (the backdrop)
	  KeepKit.COLORS                    the palette

	The Infernal Keep's map (MapData "keep") draws its dungeon from these,
	saved into ReplicatedStorage["map:keep assets"] (floors 12 × 12, walls 12
	long along X, their room side facing -Z): the kind of each piece says
	where it goes. "set" pieces are placed by DungeonGenerator's keepDecor.

	Glow: Neon parts (lava, embers, eyes) and fire particles. No PointLights
	(the performance rules: neon glows on its own).
--]]

local KeepKit = {}

local STONE = Color3.fromRGB(62, 47, 52)        -- the blocks
local STONE_HI = Color3.fromRGB(86, 66, 68)     -- their lit edges, caps
local STONE_DARK = Color3.fromRGB(38, 28, 32)   -- recesses, seams
local SEAM = Color3.fromRGB(22, 15, 18)
local IRON = Color3.fromRGB(34, 30, 34)
local IRON_HI = Color3.fromRGB(64, 58, 62)
local LAVA = Color3.fromRGB(255, 108, 24)
local LAVA_HOT = Color3.fromRGB(255, 196, 92)
local LAVA_CRUST = Color3.fromRGB(120, 30, 12)
local BANNER = Color3.fromRGB(150, 18, 22)
local BANNER_DARK = Color3.fromRGB(92, 10, 14)
local SIGIL = Color3.fromRGB(18, 10, 12)
local GOLD = Color3.fromRGB(196, 140, 60)
local WOOD = Color3.fromRGB(70, 44, 30)
KeepKit.COLORS = { STONE = STONE, STONE_HI = STONE_HI, STONE_DARK = STONE_DARK, IRON = IRON, LAVA = LAVA, LAVA_HOT = LAVA_HOT, BANNER = BANNER }

local SLATE = Enum.Material.Slate
local BRICK = Enum.Material.Cobblestone
local METAL = Enum.Material.Metal
local NEON = Enum.Material.Neon
local FABRIC = Enum.Material.Fabric
local CYL = Enum.PartType.Cylinder
local UP = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder standing up)

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function part(m: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SLATE
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- (only the big pieces cast shadows)
	p.CastShadow = size.X * size.Y * size.Z > 30
	p.Parent = m
	return p
end

-- Trim, glow and dressing: no collision, no shadow.
local function deco(m: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, class: string?): BasePart
	local p = part(m, size, cf, color, material, class)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

local function glow(m: Instance, size: Vector3, cf: CFrame, color: Color3?): BasePart
	return deco(m, size, cf, color or LAVA, NEON)
end

local function model(name: string, pivot: CFrame?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.WorldPivot = pivot or CFrame.identity
	return m
end

-- A four-sided spike, point up, its base centred at `cf` (wedges back to
-- back; `cheap`: just two, a ridge, for the small ones: parts add up).
local function spike(m: Instance, w: number, h: number, cf: CFrame, color: Color3?, cheap: boolean?)
	for k = 0, 1 do
		deco(m, Vector3.new(w, h, w / 2), cf * CFrame.Angles(0, k * math.pi, 0) * CFrame.new(0, h / 2, -w / 4), color or IRON, METAL, "WedgePart")
	end
	if cheap then return end
	for k = 0, 1 do
		deco(m, Vector3.new(w, h, w / 2), cf * CFrame.Angles(0, math.pi / 2 + k * math.pi, 0) * CFrame.new(0, h / 2, -w / 4), color or IRON, METAL, "WedgePart")
	end
end

-- Stone with a touch of variety: one of three close shades.
local SHADES = { STONE, Color3.fromRGB(68, 51, 56), Color3.fromRGB(56, 42, 47) }
local function shade(i: number): Color3
	return SHADES[(i % #SHADES) + 1]
end

-- ── Floors (12 × 12, the top at y = 0) ─────────────────────────────────────
-- One slab, its seams laid over it in thin dark strips (a few parts each:
-- a floor is thousands of tiles); each tile a shade of its own.
local function slab(m: Model, seed: number): BasePart
	-- (the full 12: no gap between tiles for things to fall or raycasts to slip through)
	local p = part(m, Vector3.new(12, 1, 12), CFrame.new(0, -0.5, 0), shade(seed), SLATE)
	p.CastShadow = false
	return p
end
local function seam(m: Model, along: string, at: number, from: number?, to: number?)
	local a0, a1 = from or -5.92, to or 5.92
	local len, mid = a1 - a0, (a0 + a1) / 2
	if along == "x" then
		deco(m, Vector3.new(len, 0.06, 0.16), CFrame.new(mid, 0.01, at), SEAM, SLATE)
	else
		deco(m, Vector3.new(0.16, 0.06, len), CFrame.new(at, 0.01, mid), SEAM, SLATE)
	end
end

local function floorSlabs(seed: number): () -> Model
	return function(): Model
		local m = model(if seed == 0 then "Floor_Slabs" else "Floor_Slabs_B")
		slab(m, seed)
		seam(m, "x", 0)
		seam(m, "z", if seed == 0 then 0 else 2, -5.92, 0)
		if seed ~= 0 then seam(m, "z", -2, 0, 5.92) end
		return m
	end
end

local function floorTiles(seed: number): () -> Model
	return function(): Model
		local m = model(if seed == 0 then "Floor_Tiles" else "Floor_Tiles_B")
		slab(m, seed + 1)
		seam(m, "x", -2)
		seam(m, "x", 2)
		seam(m, "z", if seed == 0 then -2 else 0)
		if seed == 0 then seam(m, "z", 2) end
		return m
	end
end

-- A slab split by a seam of lava glowing up through the crack.
local function floorCracked(): Model
	local m = model("Floor_Cracked")
	slab(m, 2)
	seam(m, "x", 0)
	local pts = { Vector3.new(-5.6, 0, -2.1), Vector3.new(-1.2, 0, 0.4), Vector3.new(2.2, 0, -0.8), Vector3.new(5.6, 0, 1.8) }
	for k = 1, #pts - 1 do
		local a, b = pts[k], pts[k + 1]
		local mid = (a + b) / 2
		glow(m, Vector3.new(0.12, 0.08, (b - a).Magnitude + 0.1), CFrame.lookAt(mid + Vector3.new(0, 0.03, 0), b + Vector3.new(0, 0.03, 0)), Color3.fromRGB(230, 72, 14))
	end
	return m
end

-- ── The centre: a broad dais engraved with a spiked compass star ────────────
local function centerSigil(): Model
	local m = model("Center_Sigil")
	local S = 22
	part(m, Vector3.new(S, 0.4, S), CFrame.new(0, 0.2, 0), STONE_DARK, SLATE).CastShadow = false
	-- the stepped rim
	for _, side in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
		local horiz = side[1] == 0
		local size = if horiz then Vector3.new(S, 0.5, 1.2) else Vector3.new(1.2, 0.5, S)
		deco(m, size, CFrame.new(side[1] * (S / 2 - 0.6), 0.45, side[2] * (S / 2 - 0.6)), STONE_HI, SLATE)
	end
	-- the ring the star sits in
	local R = 8.5
	local N = 24
	for k = 0, N - 1 do
		local a = k / N * math.pi * 2
		local seg = 2 * math.pi * R / N
		deco(m, Vector3.new(seg + 0.1, 0.14, 0.5), CFrame.new(math.cos(a) * R, 0.46, math.sin(a) * R) * CFrame.Angles(0, -a + math.pi / 2, 0), SEAM, SLATE)
	end
	-- thorny spikes round the ring
	for k = 0, 11 do
		local a = k / 12 * math.pi * 2 + math.pi / 12
		local at = Vector3.new(math.cos(a) * (R + 0.9), 0.46, math.sin(a) * (R + 0.9))
		deco(m, Vector3.new(0.6, 0.12, 1.6), CFrame.lookAt(at, at * 2) * CFrame.new(0, 0, -0.4), SEAM, SLATE, "WedgePart").CFrame =
			CFrame.lookAt(at, Vector3.new(at.X * 2, 0.46, at.Z * 2)) * CFrame.Angles(math.rad(-90), 0, 0)
	end
	-- the star: four long points and four short, each two wedges (lit / shadow halves)
	for k = 0, 7 do
		local a = k / 8 * math.pi * 2
		local len = if k % 2 == 0 then 10 else 5.5
		local w = if k % 2 == 0 then 2.4 else 1.7
		local base = CFrame.new(0, 0.47, 0) * CFrame.Angles(0, -a, 0)
		for side = -1, 1, 2 do
			local wedge = deco(m, Vector3.new(0.1, w / 2, len), base * CFrame.new(side * w / 4, 0, -len / 2) * CFrame.Angles(0, 0, side * math.rad(90)),
				if side == 1 then STONE_HI else STONE, SLATE, "WedgePart")
			wedge.CFrame = base * CFrame.new(side * w / 4, 0.05, -len / 2) * CFrame.Angles(0, 0, if side == 1 then math.rad(-90) else math.rad(90))
		end
	end
	-- the heart: a sunken diamond with an ember in it
	deco(m, Vector3.new(2.2, 0.16, 2.2), CFrame.new(0, 0.5, 0) * CFrame.Angles(0, math.rad(45), 0), SEAM, SLATE)
	glow(m, Vector3.new(0.9, 0.18, 0.9), CFrame.new(0, 0.52, 0) * CFrame.Angles(0, math.rad(45), 0), LAVA)
	return m
end

-- ── Walls (12 long along X, 18 tall, 3 thick; base at y = 0; the room on -Z) ─
local WALL_L, WALL_H, WALL_T = 12, 18, 3
-- Big smooth cut blocks: a plinth, two courses of tall blocks (the joints a
-- shade darker), a heavy cap and a continuous parapet. `post`: a square post
-- at the +X end, capped and spiked (every other wall or so, the art's rhythm).
local function wallBase(name: string, post: boolean?): Model
	local m = model(name)
	local body = part(m, Vector3.new(WALL_L, WALL_H, WALL_T), CFrame.new(0, WALL_H / 2, 0), STONE, SLATE)
	body.Name = "Body"
	part(m, Vector3.new(WALL_L, 1.6, WALL_T + 1.2), CFrame.new(0, 0.8, 0), STONE_DARK, SLATE)
	-- the courses: two bands of blocks on the room side, a joint in each
	local zf = -(WALL_T / 2 + 0.03)
	for _, y in ipairs({ 6.5, 12.5 }) do
		deco(m, Vector3.new(WALL_L, 0.3, 0.08), CFrame.new(0, y, zf), SEAM, SLATE)
	end
	deco(m, Vector3.new(0.3, 6, 0.08), CFrame.new(-2, 9.5, zf), SEAM, SLATE)
	-- the cap and parapet (a walkway-thick top with a low wall along the room side)
	part(m, Vector3.new(WALL_L, 1, WALL_T + 1.4), CFrame.new(0, WALL_H + 0.1, 0), STONE_HI, SLATE)
	part(m, Vector3.new(WALL_L, 2.4, 1.4), CFrame.new(0, WALL_H + 1.8, -WALL_T / 2 - 0.1), STONE, SLATE)
	if post then
		-- (inside the wall's 12 studs: a longer piece would be measured as the
		-- map's wall length, and the short stretches fall back to default walls)
		local x = WALL_L / 2 - 2.3
		part(m, Vector3.new(4.2, WALL_H + 4, 4.6), CFrame.new(x, (WALL_H + 4) / 2, 0), STONE, SLATE)
		part(m, Vector3.new(4.6, 1, 5.2), CFrame.new(x, WALL_H + 4.3, 0), STONE_HI, SLATE)
		-- a pyramid cap
		spike(m, 3.8, 3, CFrame.new(x, WALL_H + 4.8, 0), STONE_DARK)
	end
	return m
end

local function wallPlain(): Model
	local m = wallBase("Wall_Keep")
	return m
end

local function wallPost(): Model
	local m = wallBase("Wall_Keep_Post", true)
	-- a recessed panel in the middle of the room side
	deco(m, Vector3.new(6.4, 9, 0.4), CFrame.new(0, 8.5, -WALL_T / 2 - 0.15), STONE_DARK, SLATE)
	deco(m, Vector3.new(7.2, 0.6, 0.7), CFrame.new(0, 13.3, -WALL_T / 2 - 0.3), STONE_HI, SLATE)
	deco(m, Vector3.new(7.2, 0.6, 0.7), CFrame.new(0, 3.7, -WALL_T / 2 - 0.3), STONE_HI, SLATE)
	return m
end

-- A long red banner, a black trident on it, hung from an iron rod.
local function banner(m: Instance, cf: CFrame, w: number, h: number)
	deco(m, Vector3.new(w + 1, 0.3, 0.3), cf * CFrame.new(0, 0, -0.25), IRON, METAL)
	local cloth = deco(m, Vector3.new(w, h, 0.12), cf * CFrame.new(0, -h / 2, -0.2), BANNER, FABRIC)
	cloth.CastShadow = false
	-- the swallowtail at the bottom
	for _, sx in ipairs({ -1, 1 }) do
		local wedge = deco(m, Vector3.new(0.12, 1.4, w / 2), cf * CFrame.new(sx * w / 4, -h - 0.7, -0.2) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
			BANNER, FABRIC, "WedgePart")
		wedge.CFrame = cf * CFrame.new(sx * w / 4, -h - 0.7, -0.2) * CFrame.Angles(math.pi, if sx > 0 then math.rad(90) else math.rad(-90), 0)
	end
	-- the trident: shaft, crossbar, three prongs (the outer ones bent out)
	local f = cf * CFrame.new(0, -h * 0.55, -0.3)
	deco(m, Vector3.new(0.3, h * 0.8, 0.05), f * CFrame.new(0, h * 0.08, 0), SIGIL, SLATE)
	deco(m, Vector3.new(w * 0.62, 0.3, 0.05), f * CFrame.new(0, h * 0.2, 0), SIGIL, SLATE)
	for _, sx in ipairs({ -1, 1 }) do
		deco(m, Vector3.new(0.28, h * 0.24, 0.05), f * CFrame.new(sx * w * 0.27, h * 0.31, 0) * CFrame.Angles(0, 0, sx * math.rad(-12)), SIGIL, SLATE)
	end
end

local function wallBanner(): Model
	local m = wallBase("Wall_Keep_Banner", true)
	banner(m, CFrame.new(0, WALL_H - 1.6, -WALL_T / 2 - 0.05), 3.4, 11)
	return m
end

-- An iron chain from `a` to `b`, sagging `sag` studs in the middle: links of
-- two flat bars, every other one turned a quarter.
function KeepKit.Chain(a: Vector3, b: Vector3, sag: number, parent: Instance, thick: number?)
	local k0 = thick or 1
	local len = (b - a).Magnitude
	local n = math.max(3, math.floor(len / (1.3 * k0)))
	local prev = a
	for k = 1, n do
		local t = k / n
		local p = a:Lerp(b, t) - Vector3.new(0, sag * 4 * t * (1 - t), 0)
		local mid = (prev + p) / 2
		local dir = (p - prev)
		if dir.Magnitude > 0.01 then
			local cf = CFrame.lookAt(mid, p) * CFrame.Angles(0, 0, if k % 2 == 0 then math.rad(90) else 0)
			-- (a link: one flat ring-ish bar, turned a quarter from the last)
			deco(parent, Vector3.new(0.7 * k0, 0.28 * k0, dir.Magnitude + 0.4 * k0), cf, IRON, METAL)
		end
		prev = p
	end
end

local function wallChains(): Model
	local m = wallBase("Wall_Keep_Chains")
	-- two rings bolted high on the room side, a chain swagged between them
	for _, x in ipairs({ -4.6, 4.6 }) do
		deco(m, Vector3.new(0.3, 1.2, 1.2), CFrame.new(x, 14, -WALL_T / 2 - 0.35) * CFrame.Angles(0, math.rad(90), 0) * UP, IRON_HI, METAL, nil).Shape = CYL
	end
	KeepKit.Chain(Vector3.new(-4.6, 14, -WALL_T / 2 - 0.7), Vector3.new(4.6, 14, -WALL_T / 2 - 0.7), 3.6, m)
	return m
end

-- ── Pillar (5 square, 22 tall, spike on top; base at y = 0) ─────────────────
local function pillar(): Model
	local m = model("Pillar_Keep")
	part(m, Vector3.new(5.6, 1.6, 5.6), CFrame.new(0, 0.8, 0), STONE_DARK, SLATE)
	part(m, Vector3.new(4.4, 18, 4.4), CFrame.new(0, 10, 0), STONE, SLATE)
	part(m, Vector3.new(5.6, 1.4, 5.6), CFrame.new(0, 19.6, 0), STONE_HI, SLATE)
	spike(m, 4.4, 3.6, CFrame.new(0, 20.3, 0), STONE_DARK)
	return m
end

-- ── The corridor gateway (28 wide, posts either side, a raised portcullis) ──
local function gate(): Model
	local m = model("Gate_Keep")
	local half = 14
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(4, 20, 5), CFrame.new(sx * (half + 1), 10, 0), STONE, BRICK)
		part(m, Vector3.new(5, 1.4, 6), CFrame.new(sx * (half + 1), 0.7, 0), STONE_DARK, SLATE)
		part(m, Vector3.new(5, 1.2, 6), CFrame.new(sx * (half + 1), 20.6, 0), STONE_HI, SLATE)
		spike(m, 1.6, 3, CFrame.new(sx * (half + 1), 21.2, 0))
	end
	-- the lintel and the portcullis pulled up into it
	part(m, Vector3.new(half * 2 + 2, 3, 4), CFrame.new(0, 19.5, 0), STONE, BRICK)
	deco(m, Vector3.new(half * 2 + 2.4, 0.6, 4.6), CFrame.new(0, 18, 0), STONE_HI, SLATE)
	for x = -half + 1.5, half - 1.5, 2.5 do
		deco(m, Vector3.new(0.35, 3.2, 0.35), CFrame.new(x, 16.3, 0), IRON, METAL)
	end
	deco(m, Vector3.new(half * 2 - 2, 0.35, 0.4), CFrame.new(0, 17, 0), IRON, METAL)
	return m
end

-- ── Props (standing on the floor, pivot at the base) ────────────────────────
-- A square stone pedestal with an open fire in its bowl.
local function firePedestal(): Model
	local m = model("Fire_Pedestal")
	part(m, Vector3.new(3.4, 0.8, 3.4), CFrame.new(0, 0.4, 0), STONE_DARK, SLATE)
	part(m, Vector3.new(2.4, 3.4, 2.4), CFrame.new(0, 2.5, 0), STONE, BRICK)
	part(m, Vector3.new(3.2, 0.9, 3.2), CFrame.new(0, 4.6, 0), STONE_HI, SLATE)
	-- the coals, glowing
	local coals = glow(m, Vector3.new(1.6, 0.25, 1.6), CFrame.new(0, 5.12, 0), Color3.fromRGB(190, 50, 10))
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "Flame"
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(LAVA_HOT, LAVA)
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2), NumberSequenceKeypoint.new(1, 0.4) })
	fire.Transparency = NumberSequence.new(0.15, 1)
	fire.Lifetime = NumberRange.new(0.5, 0.8)
	fire.Speed = NumberRange.new(2, 4)
	fire.SpreadAngle = Vector2.new(12, 12)
	fire.Acceleration = Vector3.new(0, 4, 0)
	fire.Rate = 22
	fire.Parent = coals
	local sparks = Instance.new("ParticleEmitter")
	sparks.Name = "Sparks"
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(LAVA_HOT)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new(0.15, 0)
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Speed = NumberRange.new(3, 6)
	sparks.SpreadAngle = Vector2.new(25, 25)
	sparks.Rate = 4
	sparks.Parent = coals
	return m
end

-- A small iron-banded chest.
local function chest(): Model
	local m = model("Chest_Keep")
	part(m, Vector3.new(3, 1.6, 2), CFrame.new(0, 0.8, 0), WOOD, Enum.Material.Wood)
	local lid = part(m, Vector3.new(1.2, 2, 3), CFrame.new(0, 1.6, 0) * CFrame.Angles(0, math.rad(90), 0) * UP, WOOD, Enum.Material.Wood)
	lid.Shape = CYL
	for _, x in ipairs({ -1, 1 }) do
		deco(m, Vector3.new(0.25, 1.7, 2.1), CFrame.new(x, 0.85, 0), IRON_HI, METAL)
	end
	deco(m, Vector3.new(0.5, 0.6, 0.2), CFrame.new(0, 1.3, -1.05), GOLD, METAL)
	return m
end

-- A tall standing banner on an iron pole.
local function bannerStand(): Model
	local m = model("Banner_Stand")
	part(m, Vector3.new(2.4, 0.6, 2.4), CFrame.new(0, 0.3, 0), STONE_DARK, SLATE)
	part(m, Vector3.new(0.35, 12, 0.35), CFrame.new(0, 6, 0), IRON, METAL)
	spike(m, 0.6, 1, CFrame.new(0, 12, 0))
	banner(m, CFrame.new(0, 11.4, 0.3), 2.8, 7.5)
	return m
end

-- ── The boss's gate: a horned demon skull over a glowing portcullis ─────────
-- (32 wide, 30 tall: set against a wall, its back on +Z)
local function demonGate(): Model
	local m = model("Demon_Gate")
	-- the frame
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(6, 24, 6), CFrame.new(sx * 10, 12, 0), STONE, BRICK)
		part(m, Vector3.new(7, 1.4, 7), CFrame.new(sx * 10, 0.7, 0), STONE_DARK, SLATE)
		spike(m, 2.4, 4, CFrame.new(sx * 10, 24, 0))
	end
	part(m, Vector3.new(14, 2, 5), CFrame.new(0, 17, 0.5), STONE, BRICK)
	-- the doorway: molten light behind iron bars
	glow(m, Vector3.new(13.6, 16, 0.4), CFrame.new(0, 8, 1.6), LAVA).Name = "GateGlow"
	-- the portcullis (DungeonGenerator's keep exit raises it: "Portcullis" parts)
	for x = -6, 6, 2 do
		deco(m, Vector3.new(0.5, 16, 0.5), CFrame.new(x, 8, 0.6), IRON, METAL).Name = "Portcullis"
	end
	for y = 4, 13, 4.5 do
		deco(m, Vector3.new(13.6, 0.4, 0.5), CFrame.new(0, y, 0.6), IRON, METAL).Name = "Portcullis"
	end
	-- steps up to it
	for k = 0, 2 do
		part(m, Vector3.new(16 - k * 1.2, 0.6, 3), CFrame.new(0, 0.3 + k * 0.6, -3.5 + k * 1.2), STONE_HI, SLATE)
	end
	-- the skull: brow, cheeks, snout, fangs, two burning eyes, swept horns
	local skull = CFrame.new(0, 24, -0.5)
	part(m, Vector3.new(12, 6, 5), skull, STONE_DARK, SLATE)
	part(m, Vector3.new(13, 1.6, 5.4), skull * CFrame.new(0, 2.2, -0.4) * CFrame.Angles(math.rad(-12), 0, 0), STONE, SLATE)
	part(m, Vector3.new(5, 4, 4), skull * CFrame.new(0, -3.2, -1.2), STONE_DARK, SLATE)
	for _, sx in ipairs({ -1, 1 }) do
		-- the eye sockets and the eyes
		deco(m, Vector3.new(2.4, 1.3, 0.6), skull * CFrame.new(sx * 2.6, 0.4, -2.55) * CFrame.Angles(0, 0, sx * math.rad(-15)), SEAM, SLATE)
		glow(m, Vector3.new(1.6, 0.7, 0.4), skull * CFrame.new(sx * 2.6, 0.4, -2.7) * CFrame.Angles(0, 0, sx * math.rad(-15)), LAVA_HOT)
		-- cheekbones and fangs
		part(m, Vector3.new(3, 2.4, 3), skull * CFrame.new(sx * 4.5, -2.2, -1) * CFrame.Angles(0, 0, sx * math.rad(20)), STONE, SLATE)
		spike(m, 0.9, 2.2, skull * CFrame.new(sx * 1.4, -5.2, -2.6) * CFrame.Angles(math.pi, 0, 0), STONE_HI)
		-- the horns: three segments sweeping out and up
		local h = skull * CFrame.new(sx * 6, 2.5, 0)
		local size = 2.6
		for k = 1, 4 do
			h = h * CFrame.Angles(0, 0, sx * math.rad(-22)) * CFrame.new(sx * size * 0.8, size * 0.5, 0)
			part(m, Vector3.new(size * 1.6, size, size), h, if k % 2 == 0 then STONE else STONE_DARK, SLATE)
			size *= 0.8
		end
		spike(m, size, 3, h * CFrame.new(sx * size * 0.5, size * 0.3, 0) * CFrame.Angles(0, 0, sx * math.rad(-50)), STONE_HI)
	end
	-- banners either side
	for _, sx in ipairs({ -1, 1 }) do
		banner(m, CFrame.new(sx * 10, 20.5, -3.05), 3.6, 12)
	end
	return m
end

-- ── Lava pit: a square hole in the floor, its sides sheer stone, lava down
-- in it crusted and glowing (its pivot at the middle of its rim, on the floor)
function KeepKit.LavaPit(size: Vector2, depth: number): Model
	local m = model("Lava_Pit")
	local sx, sz = size.X, size.Y
	-- the sides
	for _, s in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
		local horiz = s[1] == 0
		local wsize = if horiz then Vector3.new(sx + 2, depth, 1) else Vector3.new(1, depth, sz + 2)
		part(m, wsize, CFrame.new(s[1] * (sx / 2 + 0.5), -depth / 2, s[2] * (sz / 2 + 0.5)), STONE_DARK, BRICK)
		-- the rim: a lip of cut stone at the floor
		local lip = if horiz then Vector3.new(sx + 2.4, 0.5, 1.4) else Vector3.new(1.4, 0.5, sz + 2.4)
		deco(m, lip, CFrame.new(s[1] * (sx / 2 + 0.5), 0.25, s[2] * (sz / 2 + 0.5)), STONE_HI, SLATE)
	end
	-- the lava: bright molten surface, a crust of darker veins over it
	local surface = glow(m, Vector3.new(sx, 0.4, sz), CFrame.new(0, -depth + 1.2, 0), Color3.fromRGB(235, 74, 14))
	surface.Name = "LavaSurface"
	-- (the crust: molten rock's dark veins over the glow, so it reads as lava,
	-- not a flat lamp)
	local crust = deco(m, Vector3.new(sx, 0.2, sz), CFrame.new(0, -depth + 1.45, 0), Color3.fromRGB(255, 132, 40), Enum.Material.CrackedLava)
	crust.Transparency = 0.25
	-- a glow up the sides
	for _, s in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
		local horiz = s[1] == 0
		local gsize = if horiz then Vector3.new(sx, 2.2, 0.1) else Vector3.new(0.1, 2.2, sz)
		glow(m, gsize, CFrame.new(s[1] * (sx / 2 - 0.02), -depth + 2.5, s[2] * (sz / 2 - 0.02)), LAVA).Transparency = 0.45
	end
	-- embers rising out of it
	local embers = Instance.new("ParticleEmitter")
	embers.Name = "Embers"
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(LAVA_HOT, LAVA)
	embers.LightEmission = 1
	embers.LightInfluence = 0
	embers.Size = NumberSequence.new(0.25, 0)
	embers.Lifetime = NumberRange.new(1.5, 2.5)
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(20, 20)
	embers.EmissionDirection = Enum.NormalId.Top
	embers.Shape = Enum.ParticleEmitterShape.Box
	embers.Rate = math.clamp(sx * sz / 40, 4, 14)
	embers.Parent = surface
	-- an invisible fence so nobody walks (or is knocked) in
	for _, s in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
		local horiz = s[1] == 0
		local fsize = if horiz then Vector3.new(sx + 2, 6, 0.6) else Vector3.new(0.6, 6, sz + 2)
		local f = part(m, fsize, CFrame.new(s[1] * (sx / 2 + 0.6), 3, s[2] * (sz / 2 + 0.6)), STONE, SLATE)
		f.Name = "PitFence"
		f.Transparency = 1
		f.CanQuery = false
		f.CastShadow = false
	end
	return m
end

-- ── A chain post: a short square stone post, an iron ring on top (a chain's
-- anchor at the lava pits; its pivot at its base, the ring at CHAIN_Y) ──────
KeepKit.CHAIN_Y = 6.4
function KeepKit.ChainPost(): Model
	local m = model("Chain_Post")
	part(m, Vector3.new(2.6, 0.8, 2.6), CFrame.new(0, 0.4, 0), STONE_DARK, SLATE)
	part(m, Vector3.new(1.9, 6, 1.9), CFrame.new(0, 3.6, 0), STONE, SLATE)
	part(m, Vector3.new(2.5, 0.7, 2.5), CFrame.new(0, 6.9, 0), STONE_HI, SLATE)
	spike(m, 1.6, 1.6, CFrame.new(0, 7.25, 0), STONE_DARK)
	local ring = deco(m, Vector3.new(0.3, 1, 1), CFrame.new(0, KeepKit.CHAIN_Y, 0) * UP, IRON_HI, METAL)
	ring.Shape = CYL
	return m
end

-- ── A jagged rock spire for the backdrop (its pivot at its base) ────────────
function KeepKit.Spire(height: number, seed: number): Model
	local rng = Random.new(seed)
	local m = model("Spire")
	local dark = Color3.fromRGB(28, 15, 20)
	local darker = Color3.fromRGB(20, 10, 15)
	local w = height * (0.28 + rng:NextNumber() * 0.1)
	-- a broad jagged base, then two or three narrower peaks stacked off-centre
	spike(m, w, height * 0.45, CFrame.new(0, 0, 0) * CFrame.Angles(0, rng:NextNumber() * math.pi, 0), dark)
	local y = height * 0.25
	local ww = w * 0.62
	for k = 1, 2 + rng:NextInteger(0, 1) do
		local off = Vector3.new(rng:NextNumber(-1, 1) * ww * 0.15, y, rng:NextNumber(-1, 1) * ww * 0.15)
		spike(m, ww, height * (0.5 - k * 0.06), CFrame.new(off) * CFrame.Angles(0, rng:NextNumber() * math.pi, rng:NextNumber(-0.05, 0.05)), if k % 2 == 0 then dark else darker)
		y += height * 0.22
		ww *= 0.62
	end
	-- a few shards jutting from the flanks
	for _ = 1, 3 do
		local a = rng:NextNumber() * math.pi * 2
		local r = w * 0.32
		spike(m, w * 0.22, height * 0.22, CFrame.new(math.cos(a) * r, height * rng:NextNumber(0.02, 0.15), math.sin(a) * r) * CFrame.Angles(0, a, math.rad(rng:NextNumber(-12, 12))), darker)
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Material = SLATE end
	end
	-- lava light catching its foot
	glow(m, Vector3.new(w * 0.95, height * 0.025, w * 0.95), CFrame.new(0, height * 0.0125, 0) * CFrame.Angles(0, math.rad(45), 0), LAVA).Transparency = 0.25
	return m
end

-- ── Every piece ─────────────────────────────────────────────────────────────
type Piece = { name: string, kind: string, build: () -> Model }
KeepKit.PIECES = {
	{ name = "Floor_Slabs", kind = "floor", build = floorSlabs(0) },
	{ name = "Floor_Slabs_B", kind = "floor", build = floorSlabs(1) },
	{ name = "Floor_Tiles", kind = "floor", build = floorTiles(0) },
	{ name = "Floor_Tiles_B", kind = "floor", build = floorTiles(1) },
	{ name = "Floor_Cracked", kind = "floor", build = floorCracked },
	{ name = "Center_Sigil", kind = "center", build = centerSigil },
	{ name = "Wall_Keep", kind = "wall", build = wallPlain },
	{ name = "Wall_Keep_Post", kind = "wall", build = wallPost },
	{ name = "Wall_Keep_Banner", kind = "wall", build = wallBanner },
	{ name = "Wall_Keep_Chains", kind = "wall", build = wallChains },
	{ name = "Pillar_Keep", kind = "pillar", build = pillar },
	{ name = "Gate_Keep", kind = "gate", build = gate },
	{ name = "Chest_Keep", kind = "cosmetic", build = chest },
	{ name = "Banner_Stand", kind = "cosmetic", build = bannerStand },
	{ name = "Fire_Pedestal", kind = "set", build = firePedestal },
	{ name = "Demon_Gate", kind = "set", build = demonGate },
} :: { Piece }

function KeepKit.Build(name: string): Model?
	for _, p in ipairs(KeepKit.PIECES) do
		if p.name == name then return p.build() end
	end
	return nil
end

return KeepKit
