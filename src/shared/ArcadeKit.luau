--!strict
--[[
	ArcadeKit.luau
	The arcade map's pieces (the neon arcade dimension: deep indigo stone, hex
	and circuit patterns glowing magenta and cyan, portals of swirling violet
	in orange frames), built from parts like the rest of the game. Each
	builder returns a Model at the origin, its pivot where it sits: a floor
	tile's at the middle of its top, everything else at the middle of its base.

	  ArcadeKit.Build(name) → Model?      one piece
	  ArcadeKit.PIECES                    every piece: { name, kind, build }

	Rooms are circles laid of square floor tiles (Trim_Edge along the stepped
	rim, where a tile meets the void), dressed with the set pieces: no
	pillars.

	The Neon Arcade's map (MapData "arcade") draws its dungeon from these: the
	kind of each piece says where it goes. floor / center / wall / gate /
	cosmetic follow DungeonGenerator's map-asset sizes (they're saved into
	ReplicatedStorage["map:arcade assets"]: floors 12×12, walls 17 long and 17
	tall, along X; a cosmetic stands on the floor, its pivot at its base, and
	is scattered through the rooms). "set" pieces (the arena dais, the ring
	backdrop, the rim trim, bridges) are too big to scatter: they're for
	building rooms by hand. "tower" is ImmunityTower's.

	Glow: Neon parts, and patterns drawn on SurfaceGuis that ignore the light
	(LightInfluence 0, Brightness > 1), so they shine whatever the room's
	lighting. No PointLights (the performance rules: neon glows on its own).
--]]

local ArcadeKit = {}

-- The glow textures (white on clear, tinted per use).
ArcadeKit.TEX = {
	hex = "rbxassetid://131730188701979",
	circuit = "rbxassetid://123016813414644",
	swirl = "rbxassetid://137276181827966",
	screen = "rbxassetid://140367530030923",
	chevron = "rbxassetid://116498485433110",
}
local TEX = ArcadeKit.TEX

-- (the Abyssal Neon palette: midnight blue, electric violet, restrained ice
-- cyan, warm amber kept for rewards and accents)
local BASE_DARK = Color3.fromRGB(8, 13, 27)  -- midnight
local BASE = Color3.fromRGB(48, 36, 91)      -- violet
local METAL = Color3.fromRGB(58, 48, 104)
local CYAN = Color3.fromRGB(66, 221, 245)    -- ice cyan
local MAGENTA = Color3.fromRGB(120, 87, 255) -- arcane
local PURPLE = Color3.fromRGB(88, 64, 190)
local ORANGE = Color3.fromRGB(255, 198, 109) -- amber
local HOLO = Color3.fromRGB(150, 225, 255)
local SMOOTH = Enum.Material.SmoothPlastic
local NEON = Enum.Material.Neon
local CYL = Enum.PartType.Cylinder
local BALL = Enum.PartType.Ball
local UP = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder standing up)
local TAU = math.pi * 2

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function part(m: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	if shape and p:IsA("Part") then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or SMOOTH
	p.Anchored = true
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	-- (only the big pieces cast shadows)
	p.CastShadow = size.X * size.Y * size.Z > 8
	p.Parent = m
	return p
end

-- A glowing strip: no collision, no shadow.
local function neon(m: Instance, size: Vector3, cf: CFrame, color: Color3, shape: Enum.PartType?): BasePart
	local p = part(m, size, cf, color, NEON, shape)
	p.CanCollide = false
	p.CanQuery = false
	p.CastShadow = false
	return p
end

-- A pattern glowing on one face of `p` (tiled every `tile` studs). (Drawn only
-- within GLOW_RANGE of the camera: a floor is thousands of these.)
local GLOW_RANGE = 140
local function glowFace(p: BasePart, face: Enum.NormalId, image: string, color: Color3, tile: Vector2, brightness: number?,
	transparency: number?): SurfaceGui
	local PPS = 20
	local sg = Instance.new("SurfaceGui")
	sg.Name = "Glow" .. face.Name
	sg.Face = face
	sg.MaxDistance = GLOW_RANGE
	sg.LightInfluence = 0
	sg.Brightness = brightness or 2
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = PPS
	sg.ClipsDescendants = true
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = image
	img.ImageColor3 = color
	img.ImageTransparency = transparency or 0
	img.ScaleType = Enum.ScaleType.Tile
	img.TileSize = UDim2.fromOffset(tile.X * PPS, tile.Y * PPS)
	img.Parent = sg
	sg.Parent = p
	return sg
end

-- A ring of `n` neon segments of radius `r`, lying in `cf`'s XZ plane (a
-- vertical ring: turn `cf` so its Y faces out), from angle a0 to a1.
local function ring(m: Instance, cf: CFrame, r: number, n: number, thick: number, height: number, color: Color3, a0: number?, a1: number?)
	local from, to = a0 or 0, a1 or TAU
	local span = (to - from) / n
	local len = 2 * r * math.sin(span / 2) * 1.04
	for i = 0, n - 1 do
		local a = from + (i + 0.5) * span
		local pos = cf * Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local tangent = cf:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, math.cos(a)))
		neon(m, Vector3.new(thick, height, len), CFrame.lookAt(pos, pos + tangent, cf.UpVector), color)
	end
end

-- Bars along the polygon `pts` (in `cf`'s XY plane), `width` across it in the
-- plane and `depth` through it.
local function outline(m: Instance, cf: CFrame, pts: { Vector2 }, width: number, depth: number, color: Color3, glowing: boolean)
	for i = 1, #pts do
		local a, b = pts[i], pts[i % #pts + 1]
		local pa, pb = cf * Vector3.new(a.X, a.Y, 0), cf * Vector3.new(b.X, b.Y, 0)
		local size = Vector3.new(width, depth, (pb - pa).Magnitude + width * 0.9)
		local at = CFrame.lookAt((pa + pb) / 2, pb, cf.LookVector)
		if glowing then neon(m, size, at, color) else part(m, size, at, color, SMOOTH) end
	end
end

local function model(name: string, pivot: CFrame?): Model
	local m = Instance.new("Model")
	m.Name = name
	m.WorldPivot = pivot or CFrame.identity
	return m
end

-- ── Floors (12 × 12, the top at y = 0) ─────────────────────────────────────
-- The seams glow on two edges, so a laid floor is a grid of light.
local function floorBase(m: Model, color: Color3): BasePart
	local slab = part(m, Vector3.new(12, 1, 12), CFrame.new(0, -0.5, 0), color, SMOOTH)
	slab.CastShadow = false
	neon(m, Vector3.new(12, 0.08, 0.14), CFrame.new(0, 0.01, -5.93), PURPLE)
	neon(m, Vector3.new(0.14, 0.08, 12), CFrame.new(-5.93, 0.01, 0), PURPLE)
	neon(m, Vector3.new(0.1, 0.6, 0.6), CFrame.new(-5.93, 0.02, -5.93) * UP, CYAN, CYL)
	return slab
end

local function floorCircuit(): Model
	local m = model("Floor_Circuit")
	local slab = floorBase(m, BASE_DARK)
	glowFace(slab, Enum.NormalId.Top, TEX.circuit, CYAN, Vector2.new(12, 12), 1.3, 0.25)
	return m
end

local function floorPanel(): Model
	local m = model("Floor_Panel")
	floorBase(m, BASE_DARK)
	-- the inset panel, a rim of light round it (a glowing plate just bigger, under it)
	neon(m, Vector3.new(10.56, 0.06, 10.56), CFrame.new(0, 0.03, 0), MAGENTA)
	local inset = part(m, Vector3.new(10.4, 0.1, 10.4), CFrame.new(0, 0.06, 0), BASE, SMOOTH)
	inset.CastShadow = false
	return m
end

local function centerRing(): Model
	local m = model("Center_Ring")
	floorBase(m, BASE_DARK)
	local disc = part(m, Vector3.new(0.12, 8.4, 8.4), CFrame.new(0, 0.02, 0) * UP, BASE, SMOOTH, CYL)
	disc.CastShadow = false
	ring(m, CFrame.new(0, 0.07, 0), 4.5, 24, 0.18, 0.06, CYAN)
	ring(m, CFrame.new(0, 0.07, 0), 2.6, 16, 0.1, 0.06, MAGENTA)
	for k = 0, 3 do
		local a = k * math.pi / 2 + math.pi / 4
		local mid = Vector3.new(math.cos(a), 0, math.sin(a)) * 5.2
		neon(m, Vector3.new(0.1, 0.06, 1.2), CFrame.lookAt(mid + Vector3.new(0, 0.07, 0), Vector3.new(0, 0.07, 0)), CYAN)
	end
	neon(m, Vector3.new(0.1, 1.2, 1.2), CFrame.new(0, 0.08, 0) * UP, MAGENTA, CYL)
	return m
end

-- ── Walls (17 long along X, 17 tall, 2 thick; base at y = 0) ───────────────
local function wallBase(m: Model): BasePart
	local body = part(m, Vector3.new(17, 17, 2), CFrame.new(0, 8.5, 0), BASE, SMOOTH)
	part(m, Vector3.new(17.2, 0.6, 2.5), CFrame.new(0, 17.3, 0), METAL, SMOOTH)        -- the cap
	part(m, Vector3.new(17.2, 0.8, 2.6), CFrame.new(0, 0.4, 0), BASE_DARK, SMOOTH)      -- the plinth
	for _, sz in ipairs({ -1, 1 }) do
		neon(m, Vector3.new(17, 0.2, 0.1), CFrame.new(0, 16.6, sz * 1.03), CYAN)
		neon(m, Vector3.new(17.2, 0.16, 0.1), CFrame.new(0, 0.86, sz * 1.31), CYAN)
	end
	return body
end

local function wallHex(): Model
	local m = model("Wall_Hex")
	local body = wallBase(m)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		glowFace(body, face, TEX.hex, MAGENTA, Vector2.new(4.4, 5.1), 1.7, 0.1)
	end
	return m
end

local function wallCircuit(): Model
	local m = model("Wall_Circuit")
	local body = wallBase(m)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		glowFace(body, face, TEX.circuit, CYAN, Vector2.new(8.5, 8.5), 1.4, 0.2)
	end
	for _, sz in ipairs({ -1, 1 }) do
		neon(m, Vector3.new(17, 0.3, 0.12), CFrame.new(0, 8.5, sz * 1.03), MAGENTA)
	end
	return m
end

-- ── The edge: where a circle laid of square tiles meets the void, a lip of
-- light along the tile's outer side and a stone skirt hanging under it
-- (12 long along X, its pivot at the tile's edge, on the floor's top) ─────
local function trimEdge(): Model
	local m = model("Trim_Edge")
	local skirt = part(m, Vector3.new(12.2, 3, 0.8), CFrame.new(0, -1.5, 0.4), BASE_DARK, SMOOTH)
	skirt.CastShadow = false
	part(m, Vector3.new(12.2, 0.3, 0.9), CFrame.new(0, 0.15, 0.45), METAL, SMOOTH).CastShadow = false
	neon(m, Vector3.new(12.2, 0.12, 0.14), CFrame.new(0, 0.34, 0.85), CYAN)
	neon(m, Vector3.new(12.2, 0.1, 0.1), CFrame.new(0, -2.9, 0.82), PURPLE)
	return m
end

-- ── The portal gate: a twelve-pointed frame of orange light round a disc of
-- swirling violet, a white-hot orb low in it ─────────────────────────────
local function gatePortal(): Model
	local m = model("Gate_Portal")
	local c = CFrame.new(0, 8.4, 0)
	local pts: { Vector2 } = {}
	for k = 0, 23 do
		local a = k / 24 * TAU + math.pi / 2
		local r = if k % 2 == 0 then 7.7 else 6.9
		table.insert(pts, Vector2.new(math.cos(a) * r, math.sin(a) * r))
	end
	outline(m, c, pts, 0.9, 1.4, METAL, false)
	for _, sz in ipairs({ -1, 1 }) do
		outline(m, c * CFrame.new(0, 0, sz * 0.74), pts, 0.22, 0.12, ORANGE, true)
	end
	-- the posts and the step it stands on
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(1.6, 15, 2.2), CFrame.new(sx * 7.9, 7.5, 0), BASE, SMOOTH)
		neon(m, Vector3.new(0.14, 11, 0.1), CFrame.new(sx * 7.9, 7.5, -1.12), PURPLE)
		neon(m, Vector3.new(0.14, 11, 0.1), CFrame.new(sx * 7.9, 7.5, 1.12), PURPLE)
	end
	part(m, Vector3.new(17, 0.6, 3.4), CFrame.new(0, 0.3, 0), BASE_DARK, SMOOTH)
	-- the portal: the disc, the swirl on both faces, the orb, motes (named:
	-- RoomPortals darkens them while the way is shut)
	local disc = neon(m, Vector3.new(0.2, 13.4, 13.4), c * CFrame.Angles(0, math.rad(90), 0), PURPLE, CYL)
	disc.Name = "PortalDisc"
	disc.Transparency = 0.25
	local sheet = part(m, Vector3.new(13, 13, 0.05), c, PURPLE, SMOOTH)
	sheet.Name = "PortalSheet"
	sheet.Transparency = 1
	sheet.CanCollide, sheet.CanQuery, sheet.CastShadow = false, false, false
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local sg = glowFace(sheet, face, TEX.swirl, Color3.fromRGB(255, 170, 255), Vector2.new(13, 13), 2.4, 0.15)
		sg.MaxDistance = 300
		local img = sg:FindFirstChildOfClass("ImageLabel") :: ImageLabel
		img.ScaleType = Enum.ScaleType.Fit
		-- the swirl turns (PortalSpin, on each client: "Spin" degrees a second),
		-- and a paler one inside it turns back against it
		img:SetAttribute("Spin", 70)
		img:AddTag("PortalSwirl")
		local inner = img:Clone()
		inner.AnchorPoint = Vector2.new(0.5, 0.5)
		inner.Position = UDim2.fromScale(0.5, 0.5)
		inner.Size = UDim2.fromScale(0.7, 0.7)
		inner.ImageColor3 = Color3.fromRGB(255, 225, 255)
		inner.ImageTransparency = 0.4
		inner:SetAttribute("Spin", -45)
		inner.Parent = sg
	end
	local orb = neon(m, Vector3.one * 2.4, CFrame.new(0, 4.6, 0), Color3.fromRGB(255, 225, 255), BALL)
	orb.Name = "PortalOrb"
	local halo = neon(m, Vector3.one * 3.6, CFrame.new(0, 4.6, 0), Color3.fromRGB(230, 120, 255), BALL)
	halo.Name = "PortalHalo"
	halo.Transparency = 0.7
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 200, 255), PURPLE)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new(0.3, 0)
	motes.Lifetime = NumberRange.new(1.5, 2.5)
	motes.Speed = NumberRange.new(1, 3)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Rate = 8
	motes.Parent = orb
	return m
end

-- ── The arena dais: a round stage, circuit arcs glowing across it ──────────
local function arenaDais(): Model
	local m = model("Arena_Dais")
	part(m, Vector3.new(1.0, 27, 27), CFrame.new(0, 0.5, 0) * UP, BASE_DARK, SMOOTH, CYL)
	part(m, Vector3.new(0.6, 25, 25), CFrame.new(0, 1.3, 0) * UP, BASE, SMOOTH, CYL)
	part(m, Vector3.new(0.64, 9, 9), CFrame.new(0, 1.32, 0) * UP, BASE_DARK, SMOOTH, CYL)
	ring(m, CFrame.new(0, 1.62, 0), 12.3, 40, 0.3, 0.06, CYAN)
	ring(m, CFrame.new(0, 1.66, 0), 4.6, 20, 0.2, 0.06, MAGENTA)
	-- the circuit: arcs in two bands, each ending in a node
	for band, r in ipairs({ 7, 9.8 }) do
		for k = 0, 2 do
			local a0 = k * TAU / 3 + band * 0.7
			local a1 = a0 + TAU / 3 * 0.62
			ring(m, CFrame.new(0, 1.63, 0), r, 9, 0.22, 0.05, CYAN, a0, a1)
			for _, a in ipairs({ a0, a1 }) do
				neon(m, Vector3.new(0.06, 0.7, 0.7), CFrame.new(math.cos(a) * r, 1.64, math.sin(a) * r) * UP, CYAN, CYL)
			end
			-- and a spoke out to the rim from the arc's end
			local p0 = Vector3.new(math.cos(a1) * r, 1.63, math.sin(a1) * r)
			local p1 = Vector3.new(math.cos(a1) * (r + 1.6), 1.63, math.sin(a1) * (r + 1.6))
			neon(m, Vector3.new(0.2, 0.05, 1.6), CFrame.lookAt((p0 + p1) / 2, p1), CYAN)
		end
	end
	return m
end

-- ── The ring backdrop: a vast wheel of lit panels, a lens at its heart ─────
-- (its face is its -Z, like a LookVector: turn it to the room)
local function ringBackdrop(): Model
	local m = model("Ring_Backdrop")
	local c = CFrame.new(0, 22, 0) * CFrame.Angles(math.rad(-90), 0, 0) -- (its rings stand up; their +Y toward its face)
	local hub = CFrame.new(0, 22, 0)
	for k = 0, 23 do
		local a = k / 24 * TAU
		local dir = Vector3.new(math.cos(a), math.sin(a), 0)
		local at = hub.Position + dir * 19
		local cf = CFrame.lookAt(at, at - Vector3.zAxis, dir)
		part(m, Vector3.new(4.4, 3.2, 2), cf, BASE, SMOOTH)
		neon(m, Vector3.new(3.2, 1.6, 0.1), cf * CFrame.new(0, 0, -1.02), if k % 3 == 0 then Color3.fromRGB(190, 235, 255) else CYAN)
	end
	ring(m, c, 21, 32, 0.4, 0.4, PURPLE)
	ring(m, c * CFrame.new(0, 0.4, 0), 13.5, 20, 1.2, 0.8, METAL)
	ring(m, c * CFrame.new(0, 0.9, 0), 13.5, 20, 0.2, 0.1, CYAN)
	part(m, Vector3.new(1.6, 14, 14), hub * CFrame.Angles(0, math.rad(90), 0), BASE_DARK, SMOOTH, CYL)
	for k = 0, 7 do
		local a = k / 8 * TAU
		neon(m, Vector3.new(0.2, 1.4, 1.4), (hub + Vector3.new(math.cos(a) * 5, math.sin(a) * 5, 0)) * CFrame.Angles(0, math.rad(90), 0)
			* CFrame.new(0.85, 0, 0), CYAN, CYL)
	end
	part(m, Vector3.one * 4, hub, Color3.fromRGB(120, 160, 220), Enum.Material.Glass, BALL).Transparency = 0.3
	neon(m, Vector3.one * 1.8, hub, Color3.fromRGB(255, 120, 200), BALL)
	-- the stand it's mounted on
	part(m, Vector3.new(6, 3.2, 4), CFrame.new(0, 1.6, 0), BASE_DARK, SMOOTH)
	part(m, Vector3.new(3, 2.2, 3), CFrame.new(0, 3.6, 0), METAL, SMOOTH)
	return m
end

-- ── The crystal window: a tall six-sided frame, glowing cyan glass in it ───
local function crystalWindow(): Model
	local m = model("Crystal_Window")
	local c = CFrame.new(0, 10, 0)
	local pts = { Vector2.new(0, 9), Vector2.new(3.4, 6), Vector2.new(3.4, -6), Vector2.new(0, -9), Vector2.new(-3.4, -6), Vector2.new(-3.4, 6) }
	outline(m, c, pts, 0.9, 1.0, METAL, false)
	local glow = {}
	for i, v in ipairs(pts) do glow[i] = v * 1.12 end
	outline(m, c * CFrame.new(0, 0, -0.52), glow, 0.18, 0.1, PURPLE, true)
	local glass = part(m, Vector3.new(6.4, 12, 0.3), c, Color3.fromRGB(70, 200, 240), Enum.Material.Glass)
	glass.Transparency = 0.25
	glowFace(glass, Enum.NormalId.Front, TEX.circuit, Color3.fromRGB(170, 245, 255), Vector2.new(6.4, 6.4), 1.8)
	-- the glass's pointed top and bottom: a wedge each side (a wedge's right
	-- angle is at its back-bottom: turned so its height runs up (or down) the
	-- window from the glass's edge and its length out to the side)
	for _, sy in ipairs({ 1, -1 }) do
		for _, sx in ipairs({ 1, -1 }) do
			local y, z = Vector3.new(0, sy, 0), Vector3.new(-sx, 0, 0)
			local w = part(m, Vector3.new(0.3, 3, 3.2), c * CFrame.fromMatrix(Vector3.new(sx * 1.6, sy * 7.5, 0), y:Cross(z), y, z),
				Color3.fromRGB(70, 200, 240), Enum.Material.Glass, nil, "WedgePart")
			w.Transparency = 0.25
		end
	end
	part(m, Vector3.new(8, 1, 2), CFrame.new(0, 0.5, 0), BASE_DARK, SMOOTH)
	return m
end

-- ── A hologram spectator: a glassy, shimmering figure (arms up: cheering) ──
local function holoSpectator(cheer: boolean): Model
	local m = model(if cheer then "Holo_Spectator_Cheer" else "Holo_Spectator")
	local F = Enum.Material.ForceField
	local function limb(size: Vector3, cf: CFrame)
		local p = part(m, size, cf, HOLO, F)
		p.CanCollide, p.CastShadow = false, false
	end
	limb(Vector3.new(1.7, 1.9, 0.9), CFrame.new(0, 3.05, 0))
	local head = part(m, Vector3.one * 1.15, CFrame.new(0, 4.6, 0), HOLO, F, BALL)
	head.CanCollide, head.CastShadow = false, false
	for _, sx in ipairs({ -1, 1 }) do
		limb(Vector3.new(0.6, 2, 0.6), CFrame.new(sx * 0.45, 1.05, 0))
		local arm = if cheer
			then CFrame.new(sx * 1.25, 4.3, 0) * CFrame.Angles(0, 0, math.rad(sx * 160)) * CFrame.new(0, -0.85, 0)
			else CFrame.new(sx * 1.15, 3.95, 0) * CFrame.Angles(0, 0, math.rad(sx * 12)) * CFrame.new(0, -0.85, 0)
		limb(Vector3.new(0.55, 1.8, 0.55), arm)
	end
	-- the projector disc under its feet
	neon(m, Vector3.new(0.08, 2.2, 2.2), CFrame.new(0, 0.04, 0) * UP, CYAN, CYL).Transparency = 0.3
	local shimmer = Instance.new("ParticleEmitter")
	shimmer.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	shimmer.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	shimmer.LightEmission = 1
	shimmer.LightInfluence = 0
	shimmer.Size = NumberSequence.new(0.18, 0)
	shimmer.Lifetime = NumberRange.new(0.6, 1.2)
	shimmer.Speed = NumberRange.new(0.3, 1)
	shimmer.Rate = 4
	shimmer.Parent = head
	return m
end

-- ── An arcade cabinet ───────────────────────────────────────────────────────
local function arcadeCabinet(): Model
	local m = model("Arcade_Cabinet")
	part(m, Vector3.new(3, 6.4, 2.6), CFrame.new(0, 3.2, 0.2), BASE, SMOOTH)
	for _, sx in ipairs({ -1, 1 }) do
		neon(m, Vector3.new(0.08, 6.2, 0.1), CFrame.new(sx * 1.52, 3.2, -1.12), MAGENTA)
		neon(m, Vector3.new(0.08, 0.1, 2.6), CFrame.new(sx * 1.52, 6.36, 0.2), MAGENTA)
	end
	-- the screen, set back and tilted up
	local screen = part(m, Vector3.new(2.5, 1.9, 0.1), CFrame.new(0, 4.4, -1.05) * CFrame.Angles(math.rad(-12), 0, 0), Color3.new(0, 0, 0), SMOOTH)
	local sg = glowFace(screen, Enum.NormalId.Front, TEX.screen, Color3.new(1, 1, 1), Vector2.new(2.5, 1.9), 2.2)
	local img = sg:FindFirstChildOfClass("ImageLabel") :: ImageLabel
	img.ScaleType = Enum.ScaleType.Stretch
	-- the marquee
	local marquee = part(m, Vector3.new(3, 0.9, 0.9), CFrame.new(0, 6.0, -0.75), BASE_DARK, SMOOTH)
	local msg = Instance.new("SurfaceGui")
	msg.Face = Enum.NormalId.Front
	msg.LightInfluence = 0
	msg.Brightness = 2.5
	msg.PixelsPerStud = 50
	msg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Text = "RE///SPAWN"
	text.Font = Enum.Font.Arcade
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 120, 230)
	text.Parent = msg
	msg.Parent = marquee
	-- the control deck: a stick, three buttons
	part(m, Vector3.new(3, 0.5, 1.2), CFrame.new(0, 3.1, -1.3) * CFrame.Angles(math.rad(14), 0, 0), METAL, SMOOTH)
	part(m, Vector3.new(0.5, 0.12, 0.12), CFrame.new(-0.8, 3.55, -1.35) * UP, BASE_DARK, SMOOTH, CYL)
	neon(m, Vector3.one * 0.3, CFrame.new(-0.8, 3.75, -1.35), Color3.fromRGB(255, 70, 70), BALL)
	for k, col in ipairs({ CYAN, MAGENTA, Color3.fromRGB(255, 220, 70) }) do
		neon(m, Vector3.new(0.1, 0.26, 0.26), CFrame.new(0.05 + k * 0.38, 3.42, -1.38) * UP, col, CYL)
	end
	return m
end

-- ── The scoreboard: a hovering panel counting in glowing arcade digits ─────
local function scoreBoard(): Model
	local m = model("Score_Board")
	local panel = part(m, Vector3.new(8, 3, 0.4), CFrame.new(0, 7, 0), BASE_DARK, SMOOTH)
	outline(m, CFrame.new(0, 7, -0.22), { Vector2.new(-4, -1.5), Vector2.new(4, -1.5), Vector2.new(4, 1.5), Vector2.new(-4, 1.5) }, 0.16, 0.08, CYAN, true)
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 3
	sg.PixelsPerStud = 40
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	local text = Instance.new("TextLabel")
	text.Name = "Score"
	text.Size = UDim2.fromScale(0.9, 0.85)
	text.Position = UDim2.fromScale(0.05, 0.075)
	text.BackgroundTransparency = 1
	text.Text = "999"
	text.Font = Enum.Font.Arcade
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(150, 245, 255)
	text.Parent = sg
	sg.Parent = panel
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(0.4, 5.5, 0.4), CFrame.new(sx * 3, 2.75, 0.3), METAL, SMOOTH)
	end
	return m
end

-- ── The brazier: a dark pedestal burning violet ────────────────────────────
local function brazierPurple(): Model
	local m = model("Brazier_Purple")
	part(m, Vector3.new(2.6, 0.6, 2.6), CFrame.new(0, 0.3, 0), BASE_DARK, SMOOTH)
	local column = part(m, Vector3.new(1.6, 3.2, 1.6), CFrame.new(0, 2.2, 0), BASE, SMOOTH)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back, Enum.NormalId.Left, Enum.NormalId.Right }) do
		glowFace(column, face, TEX.circuit, PURPLE, Vector2.new(1.6, 1.6), 1.8, 0.1)
	end
	local bowl = part(m, Vector3.new(0.7, 2.8, 2.8), CFrame.new(0, 4.15, 0) * UP, METAL, SMOOTH, CYL)
	neon(m, Vector3.new(0.12, 2.9, 2.9), CFrame.new(0, 4.5, 0) * UP, MAGENTA, CYL).Transparency = 0.4
	local fire = Instance.new("ParticleEmitter")
	fire.Name = "VioletFire"
	fire.Texture = "rbxasset://textures/particles/fire_main.dds"
	fire.Color = ColorSequence.new(Color3.fromRGB(255, 140, 255), Color3.fromRGB(120, 40, 255))
	fire.LightEmission = 1
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.2) })
	fire.Transparency = NumberSequence.new(0.2, 1)
	fire.Lifetime = NumberRange.new(0.6, 1)
	fire.Speed = NumberRange.new(2, 4)
	fire.SpreadAngle = Vector2.new(15, 15)
	fire.Acceleration = Vector3.new(0, 3, 0)
	fire.EmissionDirection = Enum.NormalId.Right -- (the bowl stands on its side: its +X is up)
	fire.Rate = 22
	fire.Parent = bowl
	return m
end

-- ── A bridge: a walkway, edges lit, arrows streaming along it ──────────────
local function bridgeSegment(): Model
	local m = model("Bridge_Segment")
	local deck = part(m, Vector3.new(6, 0.8, 12), CFrame.new(0, -0.4, 0), BASE, SMOOTH)
	glowFace(deck, Enum.NormalId.Top, TEX.chevron, ORANGE, Vector2.new(3, 1.5), 1.6, 0.35)
	for _, sx in ipairs({ -1, 1 }) do
		part(m, Vector3.new(0.5, 0.5, 12), CFrame.new(sx * 3.25, 0.05, 0), METAL, SMOOTH)
		neon(m, Vector3.new(0.12, 0.12, 12), CFrame.new(sx * 3.25, 0.36, 0), CYAN)
		neon(m, Vector3.new(0.1, 0.1, 12), CFrame.new(sx * 3.02, -0.82, 0), PURPLE)
	end
	part(m, Vector3.new(4, 1.2, 1.2), CFrame.new(0, -1.4, -4), BASE_DARK, SMOOTH)
	part(m, Vector3.new(4, 1.2, 1.2), CFrame.new(0, -1.4, 4), BASE_DARK, SMOOTH)
	return m
end

-- ── The immunity tower: an obelisk of dark stone and magenta light, a crystal
-- hanging over it in a ring (ImmunityTower makes it work: while it stands the
-- mobs round it can't be hurt). Its crystal is named "Core" (the shield beams
-- run from it). ~15 tall. ────────────────────────────────────────────────
local function towerImmunity(): Model
	local m = model("Tower_Immunity")
	local R = 2.6
	-- the base: a hexagonal plinth, stepped
	for k = 0, 2 do
		part(m, Vector3.new(R, 1.2, R * math.sqrt(3)), CFrame.new(0, 0.6, 0) * CFrame.Angles(0, k * math.pi / 3, 0), BASE_DARK, SMOOTH)
		part(m, Vector3.new(R * 0.7, 0.8, R * 0.7 * math.sqrt(3)), CFrame.new(0, 1.6, 0) * CFrame.Angles(0, k * math.pi / 3, 0), BASE, SMOOTH)
	end
	for k = 0, 5 do
		local a = k * math.pi / 3
		neon(m, Vector3.new(0.16, 1.0, 0.16), CFrame.new(math.cos(a) * (R + 0.02), 0.6, math.sin(a) * (R + 0.02)), MAGENTA)
	end
	-- the shaft: stacked, tapering, a core of light showing between its plates
	neon(m, Vector3.new(0.7, 9, 0.7), CFrame.new(0, 6.5, 0), MAGENTA)
	for i = 0, 3 do
		local w = 1.9 - i * 0.22
		local y = 2.9 + i * 2.25
		for k = 0, 1 do
			part(m, Vector3.new(w, 1.7, w), CFrame.new(0, y, 0) * CFrame.Angles(0, k * math.pi / 4, 0), METAL, SMOOTH)
		end
		neon(m, Vector3.new(0.14, w * 1.25, w * 1.25), CFrame.new(0, y + 0.95, 0) * UP, CYAN, CYL)
	end
	-- three fins standing round the shaft
	for k = 0, 2 do
		local a = k * TAU / 3
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local at = out * 1.55 + Vector3.new(0, 5.2, 0)
		local fin = CFrame.lookAt(at, at + out) * CFrame.Angles(math.rad(-8), 0, 0)
		part(m, Vector3.new(0.4, 6.5, 1.2), fin, BASE, SMOOTH)
		neon(m, Vector3.new(0.12, 5.6, 0.12), fin * CFrame.new(0, 0, -0.62), MAGENTA)
	end
	-- the crystal over it, in a ring of light
	local top = CFrame.new(0, 13.2, 0)
	local core = neon(m, Vector3.new(1.3, 1.3, 1.3), top * CFrame.Angles(math.rad(45), 0, math.rad(45)), Color3.fromRGB(255, 120, 235))
	core.Name = "Core"
	neon(m, Vector3.new(0.9, 2.4, 0.9), top * CFrame.Angles(0, math.rad(45), 0), Color3.fromRGB(255, 200, 250))
	neon(m, Vector3.one * 3.4, top, MAGENTA, BALL).Transparency = 0.82
	ring(m, top * CFrame.Angles(math.rad(70), 0, 0), 2.4, 18, 0.16, 0.16, CYAN)
	ring(m, top * CFrame.Angles(math.rad(-60), math.rad(50), 0), 2.0, 16, 0.12, 0.12, MAGENTA)
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(Color3.fromRGB(255, 190, 245), MAGENTA)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new(0.25, 0)
	motes.Lifetime = NumberRange.new(0.8, 1.4)
	motes.Speed = NumberRange.new(1, 2.5)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Rate = 10
	motes.Parent = core
	return m
end

-- ── The catalogue ──────────────────────────────────────────────────────────
export type Piece = { name: string, kind: string, build: () -> Model }
ArcadeKit.PIECES = {
	{ name = "Floor_Circuit", kind = "floor", build = floorCircuit },
	{ name = "Floor_Panel", kind = "floor", build = floorPanel },
	{ name = "Center_Ring", kind = "center", build = centerRing },
	{ name = "Wall_Hex", kind = "wall", build = wallHex },
	{ name = "Wall_Circuit", kind = "wall", build = wallCircuit },
	{ name = "Trim_Edge", kind = "set", build = trimEdge },
	{ name = "Gate_Portal", kind = "gate", build = gatePortal },
	{ name = "Arena_Dais", kind = "set", build = arenaDais },
	{ name = "Ring_Backdrop", kind = "set", build = ringBackdrop },
	{ name = "Crystal_Window", kind = "cosmetic", build = crystalWindow },
	{ name = "Holo_Spectator", kind = "cosmetic", build = function() return holoSpectator(false) end },
	{ name = "Holo_Spectator_Cheer", kind = "cosmetic", build = function() return holoSpectator(true) end },
	{ name = "Arcade_Cabinet", kind = "cosmetic", build = arcadeCabinet },
	{ name = "Score_Board", kind = "cosmetic", build = scoreBoard },
	{ name = "Brazier_Purple", kind = "cosmetic", build = brazierPurple },
	{ name = "Bridge_Segment", kind = "set", build = bridgeSegment },
	{ name = "Tower_Immunity", kind = "tower", build = towerImmunity },
} :: { Piece }

function ArcadeKit.Build(name: string): Model?
	for _, p in ipairs(ArcadeKit.PIECES) do
		if p.name == name then return p.build() end
	end
	return nil
end

return ArcadeKit
