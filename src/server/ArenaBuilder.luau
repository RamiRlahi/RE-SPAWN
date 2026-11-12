--!strict
--[[
	ArenaBuilder.luau
	The Neon Arcade's rooms (MapData.arcade), built as cyberpunk gladiator
	arenas floating in the void: a round pit of dark metal plate and neon
	rings, ringed by a podium wall trimmed in light, tiered stands of dark
	steel all the way round with neon edging every other tier, two gates
	(the way in on -X, "INSERT COIN"; the way on, by the portals, on +X,
	"NEXT STAGE"), a VIP box on the far side, big screens over the top tier,
	and the vortex turning high in the sky.

	The fight area is the room's square exactly as before (its slab collides,
	and the barrier of light round it, with its invisible wall, stops you
	leaving): the round apron beyond it, out to the podium wall, is only seen.
	So spawns, portals, towers and room bounds are all unchanged, and the pit
	keeps the arcade's cabinets (DungeonGenerator's arcadeProps).

	The crowd is not built here: each arena leaves a tagged Folder
	("ArenaCrowd": its centre, radii and tiers as attributes) and the client
	(ArenaCrowd) seats spectators in the stands near you, animates them and
	makes them cheer and boo. Folders always replicate, so streaming never
	hides an arena from the client.

	  ArenaBuilder.Floor(room, parent)       the pit's floor (the slab you stand on)
	  ArenaBuilder.Edges(room, parent, rng)  barrier, podium, gates, stands, screens, vortex

	Everything is anchored, CanTouch off, no shadows, no lights (neon glows on
	its own); only the slab and the invisible barrier collide.
--]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ArcadeKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArcadeKit"))

local ArenaBuilder = {}

local TILE = 12 -- (DungeonGenerator's FLOOR_SIZE)

ArenaBuilder.TAG = "ArenaCrowd"

-- The stands: tiers rising away from the podium wall.
local WALL_H = 7        -- the podium wall, over the floor
local TIERS = 6
local TIER_DEPTH = 4.5
local TIER_RISE = 2.6
local SEGMENTS = 40     -- round the ring (each segment one block a tier)
local AISLE_EVERY = 8   -- every eighth segment an aisle
local BASE_DROP = 16    -- how far the stands reach down into the void
local EXIT_W = 16       -- the boss arena's way out: the gap in the barrier's +X side, the stairs' width

local NEON = Enum.Material.Neon
local METAL = Enum.Material.DiamondPlate
local SMOOTH = Enum.Material.SmoothPlastic

-- (Abyssal Neon, the arcade's palette: midnight, violet, ice cyan, magenta)
local C = {
	base = Color3.fromRGB(42, 46, 82),
	field = Color3.fromRGB(30, 34, 64),
	apron = Color3.fromRGB(24, 26, 52),
	seam = Color3.fromRGB(70, 58, 128),
	metal = Color3.fromRGB(48, 36, 91),
	steel = Color3.fromRGB(34, 36, 66),
	steelB = Color3.fromRGB(28, 30, 58),
	aisle = Color3.fromRGB(20, 18, 42),
	cap = Color3.fromRGB(58, 54, 110),
	cyan = Color3.fromRGB(66, 221, 245),
	purple = Color3.fromRGB(88, 64, 190),
	pink = Color3.fromRGB(120, 87, 255),
	magenta = Color3.fromRGB(255, 70, 210),
	amber = Color3.fromRGB(255, 198, 109),
	gate = Color3.fromRGB(8, 8, 18),
	screen = Color3.fromRGB(10, 12, 26),
}

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SMOOTH
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function cylinder(parent: Instance, radius: number, height: number, at: Vector3, color: Color3, material: Enum.Material?): BasePart
	local p = part(parent, Vector3.new(height, radius * 2, radius * 2), CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)), color, material)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- A line flat on the floor from `a` to `b` (their Y ignored: at `y`).
local function flat(parent: Instance, a: Vector3, b: Vector3, y: number, width: number, color: Color3, transparency: number, glow: boolean?)
	local mid = (a + b) / 2
	local len = (b - a).Magnitude
	if len < 0.1 then return end
	local p = part(parent, Vector3.new(width, 0.04, len), CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z)),
		color, if glow then NEON else SMOOTH)
	p.Transparency = transparency
end

-- Words on a part's front face, lit (no light: the GUI glows on its own).
local function sign(p: BasePart, text: string, color: Color3, canvas: Vector2)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 2
	sg.CanvasSize = canvas
	sg.MaxDistance = 500
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.Arcade
	label.Text = text
	label.TextScaled = true
	label.TextColor3 = color
	label.Parent = sg
	sg.Parent = p
end

type Room = { gx: number, gz: number, w: number, d: number, floorY: number, roomType: string }

-- The room's geometry: its middle, half its side, the floor's top, the
-- podium wall's radius (just round the square's corners).
local function frame(room: Room): (Vector3, number, number, number)
	local cx = (room.gx + (room.w - 1) / 2) * TILE
	local cz = (room.gz + (room.d - 1) / 2) * TILE
	local half = math.max(room.w, room.d) * TILE / 2
	local top = room.floorY + 0.5
	local R = half * math.sqrt(2) + 3
	return Vector3.new(cx, top, cz), half, top, R
end
ArenaBuilder.Frame = frame

-- A point on the ring round `c`, at angle `a` (0 is +X), radius `r`, height
-- `y`, facing the middle (-Z in, +Z out).
local function onRing(c: Vector3, a: number, r: number, y: number): CFrame
	local at = Vector3.new(c.X + math.cos(a) * r, y, c.Z + math.sin(a) * r)
	return CFrame.lookAt(at, Vector3.new(c.X, y, c.Z))
end

-- The gates (the way in, -X; the way on, +X) and the VIP box (-Z: across
-- the pit from the camera, so it's in view).
local GATE_IN, GATE_OUT, BOX = math.pi, 0, -math.pi / 2
local function nearAngle(a: number, b: number, within: number): boolean
	local d = (a - b + math.pi) % (2 * math.pi) - math.pi
	return math.abs(d) < within
end

-- ── The pit's floor ─────────────────────────────────────────────────────────
-- Quiet underfoot so the fight reads: a dark field, dim seams, and bright
-- lines only for boundaries (the arena's ring, the edge band, the way to the
-- portals). Round it, out to the podium wall, a darker apron with rings of
-- light, so the pit reads round.
function ArenaBuilder.Floor(room: Room, parent: Instance)
	local c, _, top, R = frame(room)
	local cx, cz = c.X, c.Z
	local W, D = room.w * TILE, room.d * TILE
	local y = top + 0.02
	-- the slab you stand on (the room's square, as before)
	local slab = part(parent, Vector3.new(W, 1, D), CFrame.new(cx, top - 0.5, cz), C.base, nil, true)
	slab.Name = "ArcadeFloor"
	-- the round apron it sits in (a hair lower: only its rim past the square shows)
	cylinder(parent, R + 0.5, 1, Vector3.new(cx, top - 0.53, cz), C.apron, METAL)
	-- the dark field: the combat area, a shade under the rest
	part(parent, Vector3.new(W - 14, 0.03, D - 14), CFrame.new(cx, top + 0.005, cz), C.field)
	-- the grid: dim seams only
	for i = 1, room.w - 1 do
		local x = cx - W / 2 + i * TILE
		flat(parent, Vector3.new(x, 0, cz - D / 2), Vector3.new(x, 0, cz + D / 2), y, 0.1, C.seam, 0.35)
	end
	for j = 1, room.d - 1 do
		local z = cz - D / 2 + j * TILE
		flat(parent, Vector3.new(cx - W / 2, 0, z), Vector3.new(cx + W / 2, 0, z), y, 0.1, C.seam, 0.35)
	end
	-- the arena's rings: one inside, softly lit; two out on the apron
	local function ring(r: number, n: number, width: number, color: Color3, transparency: number, ry: number)
		for k = 0, n - 1 do
			local a1, a2 = k / n * math.pi * 2, (k + 1) / n * math.pi * 2
			flat(parent, c + Vector3.new(math.cos(a1), 0, math.sin(a1)) * r, c + Vector3.new(math.cos(a2), 0, math.sin(a2)) * r, ry, width, color, transparency, true)
		end
	end
	ring(math.min(W, D) * 0.42, 40, 0.16, C.pink, 0.55, y)
	ring(R - 1.5, 56, 0.3, C.cyan, 0.35, top - 0.01)
	ring(R - 5, 56, 0.15, C.magenta, 0.55, top - 0.01)
	-- the edge band, just inside the barrier
	local inset = 3
	for _, s in ipairs({
		{ Vector3.new(cx - W / 2 + inset, 0, cz - D / 2 + inset), Vector3.new(cx + W / 2 - inset, 0, cz - D / 2 + inset) },
		{ Vector3.new(cx - W / 2 + inset, 0, cz + D / 2 - inset), Vector3.new(cx + W / 2 - inset, 0, cz + D / 2 - inset) },
		{ Vector3.new(cx - W / 2 + inset, 0, cz - D / 2 + inset), Vector3.new(cx - W / 2 + inset, 0, cz + D / 2 - inset) },
		{ Vector3.new(cx + W / 2 - inset, 0, cz - D / 2 + inset), Vector3.new(cx + W / 2 - inset, 0, cz + D / 2 - inset) },
	}) do
		flat(parent, s[1], s[2], y, 0.2, C.cyan, 0.5, true)
	end
	-- the path to the portals: faint chevrons toward +X
	local Rin = math.min(W, D) * 0.42
	for k = 1, 3 do
		local x = cx + Rin + 4 + k * 3.5
		if x < cx + W / 2 - inset - 1 then
			flat(parent, Vector3.new(x - 1.4, 0, cz - 2), Vector3.new(x, 0, cz), y, 0.25, C.amber, 0.35)
			flat(parent, Vector3.new(x - 1.4, 0, cz + 2), Vector3.new(x, 0, cz), y, 0.25, C.amber, 0.35)
		end
	end
end

-- ── The barrier: the fight's edge ───────────────────────────────────────────
-- Round the square (as the arcade always had it): a lit lip, a low rail of
-- light, a faint shimmering sheet over it with an invisible wall in it,
-- posts capped in cyan.
-- (exitGap: the boss arena, a gap of EXIT_W in the middle of its +X side, the
-- way to the stairs and the portal)
local function barrier(room: Room, parent: Instance, exitGap: boolean)
	local c, _, top = frame(room)
	local hx, hz = room.w * TILE / 2, room.d * TILE / 2
	local sides = {
		{ mid = Vector3.new(c.X, top, c.Z - hz), len = hx * 2, out = -Vector3.zAxis },
		{ mid = Vector3.new(c.X, top, c.Z + hz), len = hx * 2, out = Vector3.zAxis },
		{ mid = Vector3.new(c.X - hx, top, c.Z), len = hz * 2, out = -Vector3.xAxis },
		{ mid = Vector3.new(c.X + hx, top, c.Z), len = hz * 2, out = Vector3.xAxis, gap = exitGap },
	}
	for _, s in ipairs(sides) do
		local cf = CFrame.lookAt(s.mid, s.mid - s.out) -- (+Z out of the room, X along the side)
		-- (the stretches along the side: all of it, or the two either side of the gap)
		local full = s.len + 1.6
		local runs = { { 0, full } }
		if s.gap then
			local piece = (full - EXIT_W) / 2
			runs = { { -(EXIT_W + piece) / 2, piece }, { (EXIT_W + piece) / 2, piece } }
		end
		for _, run in ipairs(runs) do
			local x0, L = run[1], run[2]
			part(parent, Vector3.new(L, 0.3, 0.9), cf * CFrame.new(x0, 0.15, 0.45), C.metal)
			part(parent, Vector3.new(L, 0.12, 0.14), cf * CFrame.new(x0, 0.34, 0.85), C.cyan, NEON)
			part(parent, Vector3.new(L, 0.18, 0.18), cf * CFrame.new(x0, 1.2, 0.5), C.pink, NEON)
			part(parent, Vector3.new(L, 0.1, 0.1), cf * CFrame.new(x0, 0.7, 0.5), C.purple, NEON)
			local sheet = part(parent, Vector3.new(L, 5, 0.1), cf * CFrame.new(x0, 3.6, 0.5), C.purple, Enum.Material.ForceField)
			sheet.Transparency = 0.4
			local wall = part(parent, Vector3.new(L, 30, 1), cf * CFrame.new(x0, 15, 0.6), C.base, nil, true)
			wall.Transparency = 1
			wall.Name = "ArcadeBarrier"
		end
		local n = math.max(1, math.floor(s.len / (TILE * 2)))
		for k = 0, n do
			local x = -s.len / 2 + k * s.len / n
			if s.gap and math.abs(x) < EXIT_W / 2 + 0.5 then continue end
			part(parent, Vector3.new(0.4, 1.6, 0.4), cf * CFrame.new(x, 0.8, 0.5), C.metal)
			part(parent, Vector3.new(0.5, 0.3, 0.5), cf * CFrame.new(x, 1.7, 0.5), C.cyan, NEON)
		end
		if s.gap then
			-- the gap's posts, taller, lit red until the way opens (BossExit)
			for _, x in ipairs({ -EXIT_W / 2 - 0.4, EXIT_W / 2 + 0.4 }) do
				part(parent, Vector3.new(0.8, 4, 0.8), cf * CFrame.new(x, 2, 0.5), C.metal, METAL)
				part(parent, Vector3.new(0.9, 0.4, 0.9), cf * CFrame.new(x, 4.1, 0.5), C.magenta, NEON)
			end
		end
	end
end

-- A gate in the podium wall: a dark mouth behind a shutter of light bars,
-- a neon frame, pylons either side, its word lit over it.
local function gate(parent: Instance, cf: CFrame, word: string, color: Color3)
	-- (cf: on the wall's inner face, facing the middle)
	part(parent, Vector3.new(10, WALL_H - 0.6, 1), cf * CFrame.new(0, (WALL_H - 0.6) / 2, 0.8), C.gate)
	for x = -4, 4, 1.6 do
		local bar = part(parent, Vector3.new(0.15, WALL_H - 1.2, 0.15), cf * CFrame.new(x, (WALL_H - 1.2) / 2 + 0.2, 0.1), color, NEON)
		bar.Transparency = 0.35
	end
	for _, x in ipairs({ -5.6, 5.6 }) do
		part(parent, Vector3.new(1.6, WALL_H + 3, 1.8), cf * CFrame.new(x, (WALL_H + 3) / 2, -0.2), C.metal, METAL)
		part(parent, Vector3.new(0.25, WALL_H + 2.6, 0.2), cf * CFrame.new(x + (if x < 0 then 0.81 else -0.81), (WALL_H + 2.6) / 2, -1.0), color, NEON)
		part(parent, Vector3.new(1.9, 0.3, 2.1), cf * CFrame.new(x, WALL_H + 3.15, -0.2), C.cyan, NEON)
	end
	part(parent, Vector3.new(10, 0.25, 0.2), cf * CFrame.new(0, WALL_H - 0.5, -1.0), color, NEON)
	local board = part(parent, Vector3.new(12.4, 3, 0.6), cf * CFrame.new(0, WALL_H + 1.6, -0.6), C.screen)
	sign(board, word, color, Vector2.new(420, 100))
	part(parent, Vector3.new(12.6, 0.2, 0.25), cf * CFrame.new(0, WALL_H + 3.15, -0.95), color, NEON)
	part(parent, Vector3.new(12.6, 0.2, 0.25), cf * CFrame.new(0, WALL_H + 0.05, -0.95), color, NEON)
end

-- The VIP box: a raised deck on the stands with a lit canopy and its sign.
local function vipBox(parent: Instance, c: Vector3, R: number, top: number)
	local r = R + 2 + TIER_DEPTH * 2
	local y = top + WALL_H + 1 + TIER_RISE * 2.5
	local cf = onRing(c, BOX, r, y)
	part(parent, Vector3.new(18, 1, 10), cf * CFrame.new(0, 0.5, 0), C.metal, METAL)
	part(parent, Vector3.new(18.4, 1.2, 0.4), cf * CFrame.new(0, 1.6, -4.9), C.steel)
	part(parent, Vector3.new(18.4, 0.15, 0.5), cf * CFrame.new(0, 2.25, -4.9), C.magenta, NEON)
	for _, x in ipairs({ -8.5, 8.5 }) do
		for _, z in ipairs({ -4.5, 4.5 }) do
			part(parent, Vector3.new(0.6, 9, 0.6), cf * CFrame.new(x, 5, z), C.steel, METAL)
		end
	end
	local canopy = part(parent, Vector3.new(19.5, 0.4, 11), cf * CFrame.new(0, 9.6, 0), C.purple, Enum.Material.Glass)
	canopy.Transparency = 0.35
	part(parent, Vector3.new(19.7, 0.25, 0.25), cf * CFrame.new(0, 9.4, -5.5), C.cyan, NEON)
	local board = part(parent, Vector3.new(8, 2.4, 0.4), cf * CFrame.new(0, 11, -5.2), C.screen)
	sign(board, "VIP", C.magenta, Vector2.new(300, 90))
	-- the throne
	part(parent, Vector3.new(3, 1.6, 2.4), cf * CFrame.new(0, 1.8, 2), C.steel, METAL)
	part(parent, Vector3.new(3, 4, 0.6), cf * CFrame.new(0, 3, 3.1), C.steel, METAL)
	part(parent, Vector3.new(0.2, 3.6, 0.1), cf * CFrame.new(0, 3, 2.75), C.amber, NEON)
end

-- A big screen over the stands, on its mast, facing the pit.
local function screen(parent: Instance, cf: CFrame, word: string, color: Color3)
	part(parent, Vector3.new(1.2, 18, 1.2), cf * CFrame.new(0, 9, 1.5), C.steel, METAL)
	local board = part(parent, Vector3.new(22, 11, 1), cf * CFrame.new(0, 21, 0), C.screen)
	sign(board, word, color, Vector2.new(440, 220))
	for _, spec in ipairs({ { 0, 5.6, 22.4, 0.3 }, { 0, -5.6, 22.4, 0.3 }, { -11.1, 0, 0.3, 11.5 }, { 11.1, 0, 0.3, 11.5 } }) do
		part(parent, Vector3.new(spec[3], spec[4], 0.3), cf * CFrame.new(spec[1], 21 + spec[2], -0.55), color, NEON)
	end
end

-- The vortex: a vast swirl (it turns: PortalSpin) high in the sky, its face
-- to the arena, rings of dark blocks drifting round it.
local function vortex(parent: Instance, at: Vector3, face: Vector3, size: number, rng: Random)
	local cf = CFrame.lookAt(at, face)
	local disc = part(parent, Vector3.new(size, size, 0.2), cf, Color3.fromRGB(40, 20, 90))
	disc.Transparency = 1
	for _, spec in ipairs({ { size, 40, Color3.fromRGB(170, 120, 255), 0.1 }, { size * 0.55, -70, Color3.fromRGB(220, 190, 255), 0.35 } }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = 1.6
		sg.CanvasSize = Vector2.new(512, 512)
		sg.MaxDistance = 1000
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(spec[1] / size, spec[1] / size)
		img.Image = ArcadeKit.TEX.swirl
		img.ImageColor3 = spec[3]
		img.ImageTransparency = spec[4]
		img:SetAttribute("Spin", spec[2])
		img:AddTag("PortalSwirl")
		img.Parent = sg
		sg.Parent = disc
	end
	for ringN = 1, 2 do
		local r = size * (0.45 + ringN * 0.07)
		local n = 16 + ringN * 6
		for k = 0, n - 1 do
			if rng:NextNumber() < 0.7 then
				local a = k / n * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
				local s = rng:NextNumber(2, 6)
				local p = cf * CFrame.new(math.cos(a) * r, math.sin(a) * r, rng:NextNumber(-4, 4))
				part(parent, Vector3.new(s, s * rng:NextNumber(0.6, 1.4), s), p * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 1), a),
					if k % 5 == 0 then Color3.fromRGB(60, 40, 140) else Color3.fromRGB(16, 14, 34))
			end
		end
	end
end

-- ── The backdrop: towers, banners, braziers ─────────────────────────────────
local SIGIL_RED = Color3.fromRGB(255, 38, 64)
local BANNER = Color3.fromRGB(22, 8, 20)
local TOWER = Color3.fromRGB(18, 16, 34)
local TOWER_B = Color3.fromRGB(26, 22, 48)
local FLAME = "rbxasset://textures/particles/fire_main.dds"

-- The arena's sigil, drawn in red lines on a banner's face: a horned crest
-- over a downward blade, an eye at the crossing.
local function sigil(p: BasePart)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 2.2
	sg.CanvasSize = Vector2.new(200, 360)
	sg.MaxDistance = 600
	local function line(x1: number, y1: number, x2: number, y2: number, w: number)
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		f.BackgroundColor3 = SIGIL_RED
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.fromOffset((x1 + x2) / 2, (y1 + y2) / 2)
		f.Size = UDim2.fromOffset(math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2) + w * 0.5, w)
		f.Rotation = math.deg(math.atan2(y2 - y1, x2 - x1))
		f.Parent = sg
	end
	-- a horned helm: the horns sweep out and up from its brow, tips turned in
	for _, s in ipairs({ -1, 1 }) do
		line(100 + s * 22, 128, 100 + s * 58, 100, 16)
		line(100 + s * 58, 100, 100 + s * 70, 56, 13)
		line(100 + s * 70, 56, 100 + s * 60, 22, 9)
		-- the helm's face: a V from the brow down to the chin
		line(100 + s * 34, 122, 100 + s * 8, 222, 12)
	end
	line(64, 122, 136, 122, 12) -- (the brow)
	-- the blade down through it, its crossguard under the chin
	line(100, 70, 100, 330, 12)
	line(58, 244, 142, 244, 11)
	line(100, 330, 100, 346, 5)
	-- the eye: a diamond at the crossing
	local eye = Instance.new("Frame")
	eye.BorderSizePixel = 0
	eye.BackgroundColor3 = Color3.fromRGB(255, 120, 140)
	eye.AnchorPoint = Vector2.new(0.5, 0.5)
	eye.Position = UDim2.fromOffset(100, 160)
	eye.Size = UDim2.fromOffset(22, 22)
	eye.Rotation = 45
	eye.Parent = sg
	sg.Parent = p
end

-- A banner, hung from a lit bar on two posts (cf: its top middle, facing the
-- arena), the sigil on it, its edges lit.
local function banner(parent: Instance, cf: CFrame, w: number, h: number)
	local b = part(parent, Vector3.new(w, h, 0.3), cf * CFrame.new(0, -h / 2, 0), BANNER)
	b.Name = "ArenaBanner"
	sigil(b)
	for _, x in ipairs({ -w / 2, w / 2 }) do
		part(parent, Vector3.new(0.25, h, 0.2), cf * CFrame.new(x, -h / 2, -0.2), C.magenta, NEON)
		part(parent, Vector3.new(0.6, h + 4, 0.6), cf * CFrame.new(x * 1.12, -h / 2 + 1, 0.6), C.steel, METAL)
	end
	part(parent, Vector3.new(w + 2, 0.4, 0.4), cf * CFrame.new(0, 0.3, -0.1), C.magenta, NEON)
	-- (the tail: a notch of dark either side of the point)
	part(parent, Vector3.new(w, 0.2, 0.2), cf * CFrame.new(0, -h, -0.2), SIGIL_RED, NEON)
end

-- A brazier: a dark pedestal, a bowl rimmed in light, violet fire.
-- (Its flames are scenery: PerfMode turns them off when the frame rate drops.)
local function brazier(parent: Instance, at: Vector3, scale: number)
	local s = scale
	part(parent, Vector3.new(3 * s, 0.6 * s, 3 * s), CFrame.new(at + Vector3.new(0, 0.3 * s, 0)), C.steel, METAL)
	part(parent, Vector3.new(2 * s, 4 * s, 2 * s), CFrame.new(at + Vector3.new(0, 2.6 * s, 0)), TOWER, METAL)
	for _, o in ipairs({ Vector3.new(1, 0, 1), Vector3.new(-1, 0, 1), Vector3.new(1, 0, -1), Vector3.new(-1, 0, -1) }) do
		part(parent, Vector3.new(0.15, 3.4 * s, 0.15), CFrame.new(at + o * 1.02 * s + Vector3.new(0, 2.6 * s, 0)), C.purple, NEON)
	end
	cylinder(parent, 1.9 * s, 1.1 * s, at + Vector3.new(0, 5.1 * s, 0), TOWER, METAL)
	cylinder(parent, 2.0 * s, 0.25 * s, at + Vector3.new(0, 5.7 * s, 0), C.magenta, NEON)
	local core = cylinder(parent, 1.5 * s, 0.3 * s, at + Vector3.new(0, 5.75 * s, 0), Color3.fromRGB(200, 90, 255), NEON)
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "BrazierFlame"
	fire.Texture = FLAME
	fire.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 60, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(70, 20, 160)),
	})
	fire.LightEmission = 1
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.2 * s), NumberSequenceKeypoint.new(0.5, 1.8 * s), NumberSequenceKeypoint.new(1, 0) })
	fire.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.3, 0), NumberSequenceKeypoint.new(1, 1) })
	fire.Brightness = 2.5
	fire.Lifetime = NumberRange.new(0.5, 0.9)
	fire.Speed = NumberRange.new(4 * s, 7 * s)
	fire.SpreadAngle = Vector2.new(10, 10)
	fire.Rotation = NumberRange.new(-30, 30)
	fire.RotSpeed = NumberRange.new(-60, 60)
	fire.EmissionDirection = Enum.NormalId.Right -- (the cylinder lies on its side: Right is up)
	fire.Rate = 16
	fire.Parent = core
end

-- A tower in the void beyond the stands: a dark block, a narrower crown, a
-- spire, lit strips and window slits on the face to the arena.
local function tower(parent: Instance, cf: CFrame, w: number, h: number, rng: Random)
	-- (cf: its foot, facing the arena)
	part(parent, Vector3.new(w, h, w), cf * CFrame.new(0, h / 2, 0), if rng:NextNumber() < 0.5 then TOWER else TOWER_B, METAL)
	local h2 = h * rng:NextNumber(0.18, 0.3)
	part(parent, Vector3.new(w * 0.68, h2, w * 0.68), cf * CFrame.new(0, h + h2 / 2, 0), TOWER, METAL)
	local h3 = h * rng:NextNumber(0.2, 0.4)
	part(parent, Vector3.new(w * 0.18, h3, w * 0.18), cf * CFrame.new(0, h + h2 + h3 / 2, 0), TOWER_B, METAL)
	local tip = if rng:NextNumber() < 0.5 then C.magenta else SIGIL_RED
	part(parent, Vector3.new(w * 0.22, 1.2, w * 0.22), cf * CFrame.new(0, h + h2 + h3, 0), tip, NEON)
	-- the strips: up the face to the arena, the crown's rim
	local col = if rng:NextNumber() < 0.55 then C.magenta elseif rng:NextNumber() < 0.6 then C.cyan else C.purple
	for _, x in ipairs({ -w * 0.32, w * 0.32 }) do
		part(parent, Vector3.new(0.35, h * 0.55, 0.2), cf * CFrame.new(x, h * 0.62, -w / 2 - 0.1), col, NEON)
	end
	part(parent, Vector3.new(w * 0.68 + 0.2, 0.3, 0.2), cf * CFrame.new(0, h + h2 - 0.6, -w * 0.34 - 0.1), col, NEON)
	-- window slits
	for _ = 1, rng:NextInteger(2, 4) do
		local y = h * rng:NextNumber(0.45, 0.95)
		local win = part(parent, Vector3.new(w * rng:NextNumber(0.2, 0.45), 0.5, 0.2),
			cf * CFrame.new(rng:NextNumber(-w * 0.15, w * 0.15), y, -w / 2 - 0.1), if rng:NextNumber() < 0.5 then C.cyan else C.pink, NEON)
		win.Transparency = 0.25
	end
end

-- Round the arena, out in the void: a ring of dark towers (taller on the far
-- side, the one the camera faces), banners with the sigil hung over the back
-- wall there, braziers burning on the podium wall's cap.
local function skyline(parent: Instance, c: Vector3, R: number, top: number, rBack: number, yBack: number, rng: Random, exitGap: boolean)
	local foot = top - BASE_DROP - 30
	local n = 16
	for k = 0, n - 1 do
		local a = (k + rng:NextNumber(-0.25, 0.25)) / n * math.pi * 2
		if exitGap and nearAngle(a, GATE_OUT, 0.32) then continue end -- (the portal's own towers)
		-- (the far side, toward +X -Z, gets the tall ones)
		local far = (math.cos(a - (-math.pi / 4)) + 1) / 2
		local h = (top - foot) + 30 + far * 55 + rng:NextNumber(0, 25)
		local w = rng:NextNumber(9, 15)
		local r = rBack + 12 + w / 2 + rng:NextNumber(0, 14)
		tower(parent, onRing(c, a, r, foot), w, h, rng)
	end
	-- the banners over the back wall, on the far side
	for _, a in ipairs({ -math.pi / 4 - 0.55, -math.pi / 4 + 0.55, -math.pi / 4 - 1.25, -math.pi / 4 + 1.25 }) do
		if exitGap and nearAngle(a, GATE_OUT, 0.3) then continue end
		banner(parent, onRing(c, a, rBack + 0.2, yBack + 26), 9, 18)
	end
	-- the braziers, on the podium wall's cap
	for _, a in ipairs({ -math.pi / 4 - 0.9, -math.pi / 4 - 0.3, -math.pi / 4 + 0.3, -math.pi / 4 + 0.9 }) do
		if exitGap and nearAngle(a, GATE_OUT, 0.25) then continue end
		local at = onRing(c, a, R + 1, top + WALL_H + 0.8).Position
		brazier(parent, at, 0.8)
	end
end

-- ── The boss arena's way out: the stairs and the portal ─────────────────────
-- Through a gap in the barrier's +X side (the side the portals to the next
-- room take in every other arena), a lit runway over the apron, through the
-- podium wall, then a grand stair up through the stands to a platform where a
-- vast ring portal stands, flanked by two towers with the sigil's banners and
-- braziers. Shut (a shutter of red light in the gap, the portal dim) until
-- the boss falls; then the shutter dies and the portal flares up.
-- Returns the zone you stand in to go down (DungeonGenerator's descend vote),
-- the call that opens it, and its place.
function ArenaBuilder.BossExit(room: Room, parent: Instance): (BasePart, () -> (), CFrame)
	local c, half, top, R = frame(room)
	local folder = Instance.new("Folder")
	folder.Name = "ArenaExit"
	folder.Parent = parent
	local W = EXIT_W
	local cz = c.Z
	local x0 = c.X + half          -- the barrier's gap
	local xs = c.X + R - 8         -- the stairs' foot
	local RISE = 22
	local xe = c.X + R + 2 + TIERS * TIER_DEPTH + 8 -- the stairs' head
	local yTop = top + RISE
	local plat = 22                -- the platform's depth
	local base = top - BASE_DROP
	local function invisibleWall(size: Vector3, cf: CFrame)
		local p = part(folder, size, cf, C.base, nil, true)
		p.Transparency = 1
		p.Name = "ExitWall"
	end

	-- the runway, over the apron to the stairs
	local runLen = xs - x0 + 1
	local runway = part(folder, Vector3.new(runLen, 1, W), CFrame.new(x0 + runLen / 2 - 0.5, top - 0.5, cz), C.apron, METAL, true)
	runway.Name = "ExitRunway"
	for _, z in ipairs({ -W / 2 + 0.4, W / 2 - 0.4 }) do
		part(folder, Vector3.new(runLen, 0.12, 0.3), CFrame.new(x0 + runLen / 2, top + 0.04, cz + z), C.magenta, NEON)
		invisibleWall(Vector3.new(runLen, 30, 1), CFrame.new(x0 + runLen / 2, top + 15, cz + z + (if z < 0 then -1 else 1) * 0.9))
	end
	for k = 0, math.floor(runLen / 6) - 1 do
		local x = x0 + 3 + k * 6
		flat(folder, Vector3.new(x - 1.8, 0, cz - 3), Vector3.new(x, 0, cz), top + 0.05, 0.35, SIGIL_RED, 0.2, true)
		flat(folder, Vector3.new(x - 1.8, 0, cz + 3), Vector3.new(x, 0, cz), top + 0.05, 0.35, SIGIL_RED, 0.2, true)
	end

	-- the stairs: lit-edged steps you see, a smooth ramp under them you walk
	local run = xe - xs
	local steps = RISE
	local depth = run / steps
	for i = 1, steps do
		local h = i * (RISE / steps)
		local xMid = xs + (i - 0.5) * depth
		local fill = h + 2
		part(folder, Vector3.new(depth + 0.05, fill, W), CFrame.new(xMid, top + h - fill / 2, cz), if i % 2 == 0 then C.steel else C.steelB, METAL)
		local edge = part(folder, Vector3.new(0.25, 0.12, W - 0.6), CFrame.new(xMid - depth / 2 + 0.1, top + h - 0.02, cz),
			if i % 4 == 0 then SIGIL_RED else C.magenta, NEON)
		edge.Transparency = 0.15
	end
	local foot, head = Vector3.new(xs, top, cz), Vector3.new(xe, yTop, cz)
	local slope = CFrame.lookAt((foot + head) / 2, head)
	local ramp = part(folder, Vector3.new(W, 1, (head - foot).Magnitude + 1), slope * CFrame.new(0, -0.5, 0), C.base, nil, true)
	ramp.Transparency = 1
	ramp.Name = "ExitRamp"
	-- the balustrades (lit along their tops) and the walls you can't fall past
	for _, sz in ipairs({ -1, 1 }) do
		local side = slope * CFrame.new(sz * (W / 2 + 0.75), 1.4, 0)
		part(folder, Vector3.new(1.5, 2.8, (head - foot).Magnitude), side, C.metal, METAL)
		part(folder, Vector3.new(0.3, 0.2, (head - foot).Magnitude), side * CFrame.new(0, 1.5, 0), C.magenta, NEON)
		invisibleWall(Vector3.new(1, 30, (head - foot).Magnitude + 2), slope * CFrame.new(sz * (W / 2 + 0.6), 14, 0))
		-- the cheeks: stepped blocks down into the void, filling the stands' gap
		local blocks = 6
		for b = 1, blocks do
			local bx = xs + (b - 0.5) * run / blocks
			local bh = (b / blocks) * RISE + 3
			part(folder, Vector3.new(run / blocks + 0.1, bh + BASE_DROP, 13),
				CFrame.new(bx, top + bh - (bh + BASE_DROP) / 2, cz + sz * (W / 2 + 8)), if b % 2 == 0 then C.steel else C.steelB, METAL)
			part(folder, Vector3.new(run / blocks + 0.1, 0.15, 0.2), CFrame.new(bx, top + bh + 0.05, cz + sz * (W / 2 + 1.6)), C.purple, NEON)
		end
	end
	-- (under the stairs: down into the void)
	part(folder, Vector3.new(run, BASE_DROP, W), CFrame.new(xs + run / 2, top - 2 - BASE_DROP / 2, cz), C.steelB, METAL)

	-- the platform at the top
	local platCF = CFrame.new(xe + plat / 2, yTop - 0.5, cz)
	part(folder, Vector3.new(plat, 1, W + 18), platCF, C.apron, METAL, true).Name = "ExitPlatform"
	part(folder, Vector3.new(plat, RISE + BASE_DROP, W + 18), platCF * CFrame.new(0, -(RISE + BASE_DROP) / 2 - 0.5, 0), C.steelB, METAL)
	part(folder, Vector3.new(0.3, 0.12, W + 18), CFrame.new(xe + 0.2, yTop + 0.04, cz), C.magenta, NEON)
	invisibleWall(Vector3.new(plat, 30, 1), CFrame.new(xe + plat / 2, yTop + 15, cz - (W + 18) / 2 - 0.5))
	invisibleWall(Vector3.new(plat, 30, 1), CFrame.new(xe + plat / 2, yTop + 15, cz + (W + 18) / 2 + 0.5))
	invisibleWall(Vector3.new(1, 30, W + 18), CFrame.new(xe + plat + 0.5, yTop + 15, cz))

	-- the portal: a vast ring standing on the platform, facing the arena
	local PR = 14
	local px = xe + 12
	local pc = CFrame.lookAt(Vector3.new(px, yTop + PR + 1.5, cz), Vector3.new(px - 1, yTop + PR + 1.5, cz))
	local ringParts: { BasePart } = {}
	local segs = 36
	for i = 0, segs - 1 do
		local a = (i + 0.5) / segs * math.pi * 2
		local arc = 2 * math.pi / segs
		-- the outer frame: heavy dark blocks, every third one jutting out
		local rOut = PR + 2.2
		local jut = i % 3 == 0
		part(folder, Vector3.new(arc * rOut + 0.3, if jut then 3.6 else 2.4, if jut then 3.2 else 2.4),
			pc * CFrame.Angles(0, 0, a) * CFrame.new(0, rOut, 0), TOWER, METAL)
		-- the inner rings of light
		local inner = part(folder, Vector3.new(arc * PR + 0.15, 0.55, 0.6), pc * CFrame.Angles(0, 0, a) * CFrame.new(0, PR + 0.6, -0.4), C.magenta, NEON)
		table.insert(ringParts, inner)
		-- (the frame's lit rims: magenta round its outside, red dashes on its face)
		table.insert(ringParts, part(folder, Vector3.new(arc * (PR + 3.7) + 0.1, 0.35, 0.35), pc * CFrame.Angles(0, 0, a) * CFrame.new(0, PR + 3.7, -1.4), C.magenta, NEON))
		if i % 2 == 0 then
			table.insert(ringParts, part(folder, Vector3.new(arc * (PR + 2.2) * 0.6, 0.3, 0.3), pc * CFrame.Angles(0, 0, a) * CFrame.new(0, PR + 2.2, -1.3), SIGIL_RED, NEON))
		end
	end
	-- (and its foot: a dais of three steps under the ring)
	for i = 1, 3 do
		part(folder, Vector3.new(6 - i, 0.5, 2 * PR + 8 - i * 3), CFrame.new(px + 0.5, yTop + (i - 0.5) * 0.5, cz), TOWER, METAL)
	end
	-- the swirl inside: a disc of light, two turning layers (PortalSpin)
	local disc = part(folder, Vector3.new(2 * PR, 2 * PR, 0.2), pc, Color3.fromRGB(190, 20, 120), NEON)
	disc.Name = "PortalDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.2, 2 * PR, 2 * PR)
	disc.CFrame = pc * CFrame.Angles(0, math.rad(90), 0)
	disc.Transparency = 0.82
	local swirls: { ImageLabel } = {}
	local face = part(folder, Vector3.new(2 * PR, 2 * PR, 0.1), pc * CFrame.new(0, 0, -0.3), C.base)
	face.Transparency = 1
	for _, spec in ipairs({ { 1, 50, Color3.fromRGB(255, 60, 200) }, { 0.7, -80, Color3.fromRGB(255, 90, 120) }, { 0.4, 120, Color3.fromRGB(255, 200, 240) } }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = 2.5
		sg.CanvasSize = Vector2.new(512, 512)
		sg.MaxDistance = 600
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(spec[1], spec[1])
		img.Image = ArcadeKit.TEX.swirl
		img.ImageColor3 = spec[3]
		img.ImageTransparency = 0.85
		img:SetAttribute("Spin", spec[2])
		img:AddTag("PortalSwirl")
		img.Parent = sg
		sg.Parent = face
		table.insert(swirls, img)
	end
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "PortalMotes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 90, 220), Color3.fromRGB(255, 40, 90))
	motes.LightEmission = 1
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	motes.Lifetime = NumberRange.new(1.2, 2)
	motes.Speed = NumberRange.new(2, 6)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Rate = 0
	motes.Parent = disc

	-- the two towers either side of it, with the banners and braziers
	for _, sz in ipairs({ -1, 1 }) do
		local tz = cz + sz * (PR + 9)
		local tcf = CFrame.lookAt(Vector3.new(px + 2, base - 20, tz), Vector3.new(px - 10, base - 20, tz))
		local th = (yTop - base) + 20 + 46
		part(folder, Vector3.new(10, th, 10), tcf * CFrame.new(0, th / 2, 0), TOWER, METAL)
		part(folder, Vector3.new(6.5, 14, 6.5), tcf * CFrame.new(0, th + 7, 0), TOWER_B, METAL)
		part(folder, Vector3.new(1.6, 18, 1.6), tcf * CFrame.new(0, th + 23, 0), TOWER, METAL)
		part(folder, Vector3.new(2, 1.2, 2), tcf * CFrame.new(0, th + 32, 0), SIGIL_RED, NEON)
		for _, x in ipairs({ -3.4, 3.4 }) do
			part(folder, Vector3.new(0.4, th * 0.6, 0.25), tcf * CFrame.new(x, th * 0.65, -5.1), if sz < 0 then C.cyan else C.magenta, NEON)
		end
		banner(folder, tcf * CFrame.new(0, th - 4, -5.6), 9, 20)
		brazier(folder, Vector3.new(xe + 4, yTop, cz + sz * (W / 2 + 4)), 1)
		brazier(folder, Vector3.new(xs - 6, top, cz + sz * (W / 2 + 4)), 1.1)
	end

	-- shut: a shutter of red light across the gap, and a wall in it
	local gapCF = CFrame.lookAt(Vector3.new(x0, top, cz), Vector3.new(x0 - 1, top, cz)) -- (X across the gap)
	local blocker = part(folder, Vector3.new(W + 1, 30, 1), gapCF * CFrame.new(0, 15, 0), C.base, nil, true)
	blocker.Transparency = 1
	blocker.Name = "ExitBlocker"
	local bars: { BasePart } = {}
	for x = -W / 2 + 1, W / 2 - 1, 1.75 do
		local bar = part(folder, Vector3.new(0.2, 6, 0.2), gapCF * CFrame.new(x, 3, 0), SIGIL_RED, NEON)
		bar.Transparency = 0.25
		table.insert(bars, bar)
	end
	for _, y in ipairs({ 0.4, 6 }) do
		table.insert(bars, part(folder, Vector3.new(W, 0.25, 0.25), gapCF * CFrame.new(0, y, 0), SIGIL_RED, NEON))
	end

	-- the zone: in the portal's mouth
	local zone = part(folder, Vector3.new(6, 16, 2 * PR), CFrame.new(px - 1, yTop + 8, cz), C.base)
	zone.Transparency = 1
	zone.CanQuery = false
	zone.Name = "DescendZone"

	local TweenService = game:GetService("TweenService")
	local opened = false
	local function open()
		if opened or not folder.Parent then return end
		opened = true
		for _, b in ipairs(bars) do
			TweenService:Create(b, TweenInfo.new(1.2, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		end
		blocker:Destroy()
		TweenService:Create(disc, TweenInfo.new(2, Enum.EasingStyle.Quad), { Transparency = 0.62 }):Play()
		for i, img in ipairs(swirls) do
			TweenService:Create(img, TweenInfo.new(2, Enum.EasingStyle.Quad), { ImageTransparency = ({ 0.05, 0.25, 0.4 })[i] }):Play()
		end
		for _, p in ipairs(ringParts) do p.Color = p.Color:Lerp(Color3.new(1, 1, 1), 0.25) end
		motes.Rate = 30
		task.delay(1.3, function()
			for _, b in ipairs(bars) do b:Destroy() end
		end)
	end
	return zone, open, CFrame.new(Vector3.new(px - 4, yTop, cz)) * CFrame.Angles(0, math.rad(90), 0)
end

-- ── The arena round the pit ─────────────────────────────────────────────────
function ArenaBuilder.Edges(room: Room, parent: Instance, rng: Random)
	local c, half, top, R = frame(room)
	-- (the boss arena: its +X side opens on the stairs to the portal, BossExit)
	local exitGap = room.roomType == "Boss"
	barrier(room, parent, exitGap)
	local exitHalf = (EXIT_W / 2 + 3) / (R + 1)

	-- The podium wall: dark steel, a magenta line at its foot, a cyan one
	-- under its cap, and lit panels along it.
	local N = 64
	local chord = 2 * (R + 1) * math.sin(math.pi / N) + 0.4
	for k = 0, N - 1 do
		local a = k / N * math.pi * 2
		local isGate = nearAngle(a, GATE_IN, 0.06) or nearAngle(a, GATE_OUT, if exitGap then exitHalf else 0.06)
		if exitGap and nearAngle(a, GATE_OUT, exitHalf) then continue end -- (the stairs go through here)
		local cf = onRing(c, a, R + 1, top)
		if not isGate then
			part(parent, Vector3.new(chord, WALL_H + 1, 2), cf * CFrame.new(0, (WALL_H + 1) / 2 - 1, 0), C.steel, METAL)
			part(parent, Vector3.new(chord, 0.15, 0.2), cf * CFrame.new(0, 0.5, -1.05), C.magenta, NEON)
			part(parent, Vector3.new(chord, 0.2, 0.2), cf * CFrame.new(0, WALL_H - 0.4, -1.05), C.cyan, NEON)
			if k % 4 == 2 then
				-- a lit panel: a dark plate, a slit of light down it
				part(parent, Vector3.new(2.4, 3.6, 0.3), cf * CFrame.new(0, WALL_H * 0.48, -1.1), C.screen)
				part(parent, Vector3.new(0.3, 3, 0.1), cf * CFrame.new(0, WALL_H * 0.48, -1.28), if k % 8 == 2 then C.magenta else C.cyan, NEON)
			end
		end
		part(parent, Vector3.new(chord, 0.8, 3), cf * CFrame.new(0, WALL_H + 0.4, 0.2), C.cap)
	end
	gate(parent, onRing(c, GATE_IN, R, top), "INSERT COIN", C.amber)
	if not exitGap then gate(parent, onRing(c, GATE_OUT, R, top), "NEXT STAGE", C.cyan) end

	-- The stands: tier on tier, one block a segment, the aisles darker with
	-- amber step lights; every other tier's edge lit, cyan and magenta in turn.
	local base = top - BASE_DROP
	for t = 1, TIERS do
		local r0 = R + 2 + (t - 1) * TIER_DEPTH
		local yTop = top + WALL_H + 1 + (t - 1) * TIER_RISE
		local rm = r0 + TIER_DEPTH / 2
		local segLen = 2 * (r0 + TIER_DEPTH) * math.sin(math.pi / SEGMENTS) + 0.3
		local edgeLen = 2 * r0 * math.sin(math.pi / SEGMENTS) + 0.1
		for k = 0, SEGMENTS - 1 do
			if exitGap and (k == 0 or k == SEGMENTS - 1) then continue end -- (the stairs)
			local a = (k + 0.5) / SEGMENTS * math.pi * 2
			local cf = onRing(c, a, rm, base)
			local h = yTop - base
			local aisle = k % AISLE_EVERY == 0
			local color = if aisle then C.aisle elseif t % 2 == 0 then C.steel else C.steelB
			part(parent, Vector3.new(segLen, h, TIER_DEPTH), cf * CFrame.new(0, h / 2, 0), color, METAL)
			local edge = onRing(c, a, r0, yTop)
			if aisle then
				part(parent, Vector3.new(0.6, 0.12, 0.6), edge * CFrame.new(0, 0.06, -0.2 + TIER_DEPTH / 2), C.amber, NEON)
			elseif t % 2 == 1 then
				part(parent, Vector3.new(edgeLen, 0.14, 0.14), edge * CFrame.new(0, -0.05, 0.05), if t % 4 == 1 then C.cyan else C.magenta, NEON)
			end
		end
	end
	-- the back wall over the top tier: steel, a lit rim, masts with holo
	-- pennants
	local rBack = R + 2 + TIERS * TIER_DEPTH + 1
	local yBack = top + WALL_H + 1 + (TIERS - 1) * TIER_RISE
	local backLen = 2 * (rBack + 1) * math.sin(math.pi / SEGMENTS) + 0.3
	for k = 0, SEGMENTS - 1 do
		if exitGap and (k == 0 or k == SEGMENTS - 1) then continue end -- (the portal's platform)
		local a = (k + 0.5) / SEGMENTS * math.pi * 2
		local cf = onRing(c, a, rBack, base)
		local h = yBack + 4 - base
		part(parent, Vector3.new(backLen, h, 2), cf * CFrame.new(0, h / 2, 0), C.steel, METAL)
		part(parent, Vector3.new(backLen, 0.2, 0.2), cf * CFrame.new(0, h - 0.3, -1.05), C.purple, NEON)
		if k % 5 == 2 then
			part(parent, Vector3.new(0.5, 10, 0.5), cf * CFrame.new(0, h + 5, 0), C.steel, METAL)
			local flag = part(parent, Vector3.new(3.5, 2.2, 0.1), cf * CFrame.new(1.8, h + 8.8, 0),
				if rng:NextNumber() < 0.5 then C.magenta else C.cyan, NEON)
			flag.Transparency = 0.35
			flag.Name = "ArenaPennant"
		end
	end
	-- the screens, over the far stands (the camera's side, -X +Z, has none:
	-- they'd only block the view)
	local scrR = rBack + 4
	local words = { { a = -math.pi / 4, w = "FIGHT!", col = C.magenta }, { a = math.pi / 5, w = "K.O.", col = C.cyan },
		{ a = -3 * math.pi / 4 + 0.3, w = "HI-SCORE", col = C.amber } }
	for _, s in ipairs(words) do
		screen(parent, onRing(c, s.a, scrR, yBack + 2), s.w, s.col)
	end
	vipBox(parent, c, R, top)
	skyline(parent, c, R, top, rBack, yBack, rng, exitGap)
	-- the vortex, high and far, off to one side behind the way in
	vortex(parent, Vector3.new(c.X - half - 120, top + 75, c.Z + (if rng:NextNumber() < 0.5 then -1 else 1) * half * 0.8),
		c + Vector3.new(0, 20, 0), 130, rng)

	-- What the client's crowd needs to seat itself.
	local tag = Instance.new("Folder")
	tag.Name = "ArenaCrowd"
	tag:SetAttribute("Center", c)
	tag:SetAttribute("Half", half)
	tag:SetAttribute("RingStart", R + 2)
	tag:SetAttribute("Tiers", TIERS)
	tag:SetAttribute("TierDepth", TIER_DEPTH)
	tag:SetAttribute("TierRise", TIER_RISE)
	tag:SetAttribute("FirstSeat", top + WALL_H + 1)
	tag:SetAttribute("Segments", SEGMENTS)
	tag:SetAttribute("AisleEvery", AISLE_EVERY)
	tag:SetAttribute("BoxAngle", BOX)
	tag:SetAttribute("ExitGap", exitGap) -- (no seats where the stairs go: the two segments either side of +X)
	-- (quiet rooms, the shop or the rest, draw a thinner crowd)
	local busy = room.roomType == "Combat" or room.roomType == "Elite" or room.roomType == "Boss" or room.roomType == "Start"
	tag:SetAttribute("Fill", if room.roomType == "Boss" then 0.95 elseif busy then 0.82 else 0.4)
	tag:SetAttribute("Seed", rng:NextInteger(1, 2 ^ 30))
	CollectionService:AddTag(tag, ArenaBuilder.TAG)
	tag.Parent = parent
end

return ArenaBuilder
