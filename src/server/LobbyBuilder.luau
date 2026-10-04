--!strict
--[[
	LobbyBuilder.luau
	Builds the lobby plaza (after the concept art): a floating grassy island
	at dusk with a round cobblestone plaza and a gold compass rose inlaid in
	it, stone stairs up from the front, low brick walls with lantern posts and
	red banners; on the left a great tree with a lantern hanging from its
	bough, the QUESTS notice board and market stalls; at the back the DUNGEON
	gate (a stone arch over a glowing portal, up a flight of steps); on the
	right the GACHA tent with its crystal, magic circle and menu board, a
	wooden fence and a waterfall spilling off the island's edge. Lit by its
	lanterns (flickering), two iron lamp posts at the stairhead, strings of
	glowing bulbs over the plaza and uplights on the gate. (The floating
	castles round it, and the lobby's light grade, are drawn on each client:
	MenuBackdrop.BuildHubSky / SetHubGrade.)

	LobbyBuilder.Build(center, prompts) → spawn CFrame
	  prompts.dungeon / prompts.quests / prompts.gacha (player) are called when
	  a player uses the gate, the board or the tent.

	The plaza faces north (-Z): the gate is at the back, you arrive at the
	front stairs (+Z).
--]]

local Workspace = game:GetService("Workspace")

local LobbyBuilder = {}

local COBBLE = Color3.fromRGB(122, 112, 104)
local STONE = Color3.fromRGB(116, 108, 102)
local STONE_DARK = Color3.fromRGB(78, 72, 72)
local BRICK = Color3.fromRGB(128, 112, 100)
local GRASS = Color3.fromRGB(70, 98, 50)
local WOOD = Color3.fromRGB(92, 62, 40)
local WOOD_DARK = Color3.fromRGB(54, 36, 26)
local GOLD = Color3.fromRGB(232, 182, 84)
local BANNER = Color3.fromRGB(118, 22, 26)
local LANTERN = Color3.fromRGB(255, 196, 120)
local PORTAL = Color3.fromRGB(80, 96, 220)
local PORTAL_INNER = Color3.fromRGB(150, 90, 230)
local GACHA_PURPLE = Color3.fromRGB(150, 90, 255)
local IRON = Color3.fromRGB(34, 30, 30)
local FLAME = Color3.fromRGB(255, 176, 104) -- the lanterns' light
local BULBS = { Color3.fromRGB(255, 214, 150), Color3.fromRGB(255, 168, 92) }

local FONT = Enum.Font.Antique
local UP = Vector3.yAxis
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lying flat (axis up)

type Prompts = { dungeon: (Player) -> (), quests: (Player) -> (), gacha: (Player) -> () }

local function part(parent: Instance, props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Slate
	p.Color = STONE
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local function deco(parent: Instance, props: { [string]: any }, class: string?): BasePart
	local p = part(parent, props, class)
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	return p
end

-- Text on a board's front face.
local function boardText(board: BasePart, px: Vector2, build: (SurfaceGui) -> ())
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = px
	sg.LightInfluence = 0.15
	sg.Parent = board
	build(sg)
end

local function textLabel(parent: Instance, text: string, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(240, 214, 160)
	t.Text = text
	for k, v in pairs(props) do (t :: any)[k] = v end
	t.Parent = parent
	return t
end

-- A flame's light flickers: every client's TorchLightController flickers the
-- lights tagged CandleLight, each about its own BaseBrightness and Phase.
local flamePhase = 0
local function flicker(l: Light, base: number)
	flamePhase += 1.37
	l:SetAttribute("BaseBrightness", base)
	l:SetAttribute("Phase", flamePhase)
	l:AddTag("CandleLight")
end

-- A lantern (iron cap, glowing glass, a warm light) standing at `pos`. The
-- bigger ones (the posts', the gate's, the tree's) cast shadows. (Its own
-- iron casts none: the base would black out a circle under a hung lantern.)
local function lantern(parent: Instance, pos: Vector3, scale: number?)
	local k = scale or 1
	deco(parent, { Name = "LanternBase", Size = Vector3.new(1.2, 0.3, 1.2) * k, CFrame = CFrame.new(pos + Vector3.new(0, 0.15 * k, 0)),
		Color = IRON, Material = Enum.Material.Metal, CastShadow = false })
	local glass = deco(parent, { Name = "LanternGlass", Size = Vector3.new(0.9, 1.3, 0.9) * k, CFrame = CFrame.new(pos + Vector3.new(0, 0.95 * k, 0)),
		Color = Color3.fromRGB(230, 140, 60), Material = Enum.Material.Neon, Transparency = 0.4, CastShadow = false })
	deco(parent, { Name = "LanternCap", Size = Vector3.new(1.3, 0.35, 1.3) * k, CFrame = CFrame.new(pos + Vector3.new(0, 1.75 * k, 0)),
		Color = IRON, Material = Enum.Material.Metal, CastShadow = false })
	deco(parent, { Name = "LanternTop", Size = Vector3.new(0.5, 0.5, 0.5) * k, CFrame = CFrame.new(pos + Vector3.new(0, 2.1 * k, 0)) * CFrame.Angles(0, math.rad(45), 0),
		Color = IRON, Material = Enum.Material.Metal, CastShadow = false })
	local l = Instance.new("PointLight")
	l.Color = FLAME
	l.Range = 20 * k
	l.Brightness = 1.1
	l.Shadows = k >= 1.3
	l.Parent = glass
	flicker(l, 1.1)
end

-- An iron lamp post `h` tall, a lantern hung from its arm (toward `armDir`).
-- Returns the hook at its top (the string lights tie on there).
local function lampPost(parent: Instance, pos: Vector3, h: number, armDir: Vector3): Vector3
	local arm = Vector3.new(armDir.X, 0, armDir.Z).Unit
	part(parent, { Name = "LampPlinth", Size = Vector3.new(1.8, 0.8, 1.8), CFrame = CFrame.new(pos + Vector3.new(0, 0.4, 0)), Color = STONE_DARK })
	part(parent, { Name = "LampPost", Size = Vector3.new(0.55, h, 0.55), CFrame = CFrame.new(pos + Vector3.new(0, h / 2, 0)), Color = IRON, Material = Enum.Material.Metal })
	deco(parent, { Name = "LampFinial", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, CFrame = CFrame.new(pos + Vector3.new(0, h + 0.3, 0)),
		Color = GOLD, Material = Enum.Material.Metal })
	local armAt = pos + Vector3.new(0, h - 1.2, 0)
	local armEnd = armAt + arm * 2.6
	deco(parent, { Name = "LampArm", Size = Vector3.new(0.25, 0.25, 2.8), CFrame = CFrame.lookAt((armAt + armEnd) / 2, armEnd), Color = IRON, Material = Enum.Material.Metal })
	deco(parent, { Name = "Chain", Size = Vector3.new(0.14, 1.2, 0.14), CFrame = CFrame.new(armEnd - Vector3.new(0, 0.6, 0)), Color = IRON, Material = Enum.Material.Metal })
	lantern(parent, armEnd - Vector3.new(0, 1.2 + 2.35 * 1.3, 0), 1.3)
	return pos + Vector3.new(0, h - 0.3, 0)
end

-- A string of glowing bulbs from `a` to `b`, sagging `sag` in the middle;
-- every fifth bulb gives light.
local function festoon(parent: Instance, a: Vector3, b: Vector3, sag: number)
	local n = math.max(2, math.floor((b - a).Magnitude / 3))
	local prev = a
	for i = 1, n do
		local t = i / n
		local p = a:Lerp(b, t) - Vector3.new(0, 4 * sag * t * (1 - t), 0)
		deco(parent, { Name = "Wire", Size = Vector3.new(0.08, 0.08, (p - prev).Magnitude), CFrame = CFrame.lookAt((p + prev) / 2, p),
			Color = IRON, Material = Enum.Material.SmoothPlastic, CastShadow = false })
		if i < n then
			deco(parent, { Name = "BulbStem", Size = Vector3.new(0.08, 0.35, 0.08), CFrame = CFrame.new(p - Vector3.new(0, 0.17, 0)),
				Color = IRON, Material = Enum.Material.SmoothPlastic, CastShadow = false })
			local bulb = deco(parent, { Name = "Bulb", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = CFrame.new(p - Vector3.new(0, 0.6, 0)),
				Color = BULBS[i % 2 + 1], Material = Enum.Material.Neon, Transparency = 0.45, CastShadow = false })
			if i % 5 == 0 then
				local l = Instance.new("PointLight")
				l.Color = Color3.fromRGB(255, 192, 128)
				l.Range = 14
				l.Brightness = 0.7
				l.Shadows = false
				l.Parent = bulb
			end
		end
		prev = p
	end
end

-- A floor light at `pos` shining up (`dir`) at stone.
local function uplight(parent: Instance, pos: Vector3, dir: Vector3, color: Color3, range: number, brightness: number)
	local f = deco(parent, { Name = "Uplight", Size = Vector3.new(1, 0.4, 1), CFrame = CFrame.lookAt(pos, pos + dir) * CFrame.Angles(math.rad(-90), 0, 0),
		Color = IRON, Material = Enum.Material.Metal, CastShadow = false })
	local l = Instance.new("SpotLight")
	l.Face = Enum.NormalId.Top
	l.Angle = 55
	l.Color = color
	l.Range = range
	l.Brightness = brightness
	l.Shadows = false
	l.Parent = f
end

-- A hanging red banner with a gold emblem, its top at `top`, facing `face`.
local function banner(parent: Instance, top: Vector3, face: Vector3, w: number, h: number, color: Color3?)
	local cf = CFrame.lookAt(top - Vector3.new(0, h / 2, 0), top - Vector3.new(0, h / 2, 0) + face)
	deco(parent, { Name = "BannerRod", Size = Vector3.new(w + 0.6, 0.2, 0.2), CFrame = cf * CFrame.new(0, h / 2 + 0.1, 0),
		Color = GOLD, Material = Enum.Material.Metal })
	local b = deco(parent, { Name = "Banner", Size = Vector3.new(w, h, 0.12), CFrame = cf, Color = color or BANNER, Material = Enum.Material.Fabric })
	-- the swallowtail at the bottom
	for _, s in ipairs({ -1, 1 }) do
		deco(parent, { Name = "BannerTail", Size = Vector3.new(0.12, w * 0.3, w / 2), CFrame = cf * CFrame.new(s * w / 4, -h / 2 - w * 0.15, 0)
			* CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(math.pi, 0, 0), Color = color or BANNER, Material = Enum.Material.Fabric }, "WedgePart")
	end
	-- the gold star emblem: a diamond and its crossbars
	deco(parent, { Name = "Emblem", Size = Vector3.new(w * 0.32, w * 0.32, 0.05), CFrame = cf * CFrame.new(0, h * 0.12, -0.09) * CFrame.Angles(0, 0, math.rad(45)),
		Color = GOLD, Material = Enum.Material.Metal })
	deco(parent, { Name = "Emblem", Size = Vector3.new(w * 0.7, 0.12, 0.05), CFrame = cf * CFrame.new(0, h * 0.12, -0.1), Color = GOLD, Material = Enum.Material.Metal })
	deco(parent, { Name = "Emblem", Size = Vector3.new(0.12, w * 0.7, 0.05), CFrame = cf * CFrame.new(0, h * 0.12, -0.1), Color = GOLD, Material = Enum.Material.Metal })
	return b
end

-- A ring of short segments on the floor (the compass's gold rings).
local function floorRing(parent: Instance, c: Vector3, r: number, width: number, n: number, color: Color3, mat: Enum.Material?)
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		deco(parent, { Name = "Ring", Size = Vector3.new(width, 0.08, r * 2 * math.pi / n + 0.05),
			CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), Color = color, Material = mat or Enum.Material.Neon })
	end
end

-- A flat pointed spike on the floor from `c` out along `dir` (a compass point).
local function floorPoint(parent: Instance, c: Vector3, dir: Vector3, len: number, width: number, color: Color3, mat: Enum.Material)
	local side = (-dir):Cross(UP)
	local mid = c + dir * (len / 2)
	local base = CFrame.fromMatrix(mid, UP, side)
	for _, s in ipairs({ 1, -1 }) do
		local cf = base * CFrame.new(0, s * width / 4, 0) * (if s < 0 then CFrame.Angles(0, 0, math.pi) else CFrame.identity)
		deco(parent, { Name = "CompassPoint", Size = Vector3.new(0.1, width / 2, len), CFrame = cf, Color = color, Material = mat }, "WedgePart")
	end
end

-- ── The pieces ──────────────────────────────────────────────────────────────
local function buildIsland(m: Model, C: Vector3, rng: Random)
	-- grass top, a raised cobblestone plaza in its middle, rock below
	part(m, { Name = "Grass", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 172, 172), Material = Enum.Material.Grass, Color = GRASS,
		CFrame = CFrame.new(C + Vector3.new(0, -7, 0)) * FLAT })
	part(m, { Name = "Plaza", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 96, 96), Material = Enum.Material.Cobblestone, Color = COBBLE,
		CFrame = CFrame.new(C + Vector3.new(0, -2, 0)) * FLAT })
	-- the curb round the plaza
	for i = 1, 48 do
		local a = (i / 48) * math.pi * 2
		local deg = math.deg(a)
		if math.abs(deg - 90) < 16 or math.abs(deg - 270) < 16 then continue end -- (the stairs, the gate's steps)
		local p = C + Vector3.new(math.cos(a) * 48.3, -1.6, math.sin(a) * 48.3)
		part(m, { Name = "Curb", Size = Vector3.new(1.4, 3.4, 48.3 * 2 * math.pi / 48 + 0.2),
			CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), Color = STONE_DARK })
	end
	-- the island's underside: a great rock, with crags hanging off it
	deco(m, { Name = "Earth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 168, 168), Material = Enum.Material.Ground,
		Color = Color3.fromRGB(92, 70, 56), CFrame = CFrame.new(C + Vector3.new(0, -19, 0)) * FLAT })
	deco(m, { Name = "Underside", Shape = Enum.PartType.Ball, Size = Vector3.one * 150, Material = Enum.Material.Rock,
		Color = Color3.fromRGB(96, 84, 86), CFrame = CFrame.new(C + Vector3.new(0, -88, 0)) })
	for i = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(20, 60)
		local h = rng:NextNumber(30, 70)
		deco(m, { Name = "Crag", Size = Vector3.new(rng:NextNumber(14, 26), h, rng:NextNumber(14, 26)), Material = Enum.Material.Rock,
			Color = Color3.fromRGB(86, 74, 78), CFrame = CFrame.new(C + Vector3.new(math.cos(a) * r, -26 - h / 2, math.sin(a) * r)) * CFrame.Angles(math.pi, rng:NextNumber(0, 6), 0) },
			"CornerWedgePart")
	end
end

local function buildCompass(m: Model, C: Vector3)
	local c = C + Vector3.new(0, 0.04, 0)
	floorRing(m, c, 16, 0.45, 40, GOLD, Enum.Material.Metal)
	floorRing(m, c, 11.5, 0.3, 32, GOLD, Enum.Material.Metal)
	floorRing(m, c, 21, 0.25, 48, Color3.fromRGB(150, 120, 70), Enum.Material.Metal)
	for i = 0, 7 do
		local a = i * math.pi / 4
		local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
		local long = i % 2 == 0
		floorPoint(m, c + Vector3.new(0, 0.02, 0), dir, if long then 15 else 9, if long then 3.2 else 2.2,
			if long then GOLD else Color3.fromRGB(196, 150, 80), Enum.Material.Metal)
	end
	deco(m, { Name = "CompassHeart", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 3.2, 3.2), CFrame = CFrame.new(c + Vector3.new(0, 0.06, 0)) * FLAT,
		Color = Color3.fromRGB(200, 150, 70), Material = Enum.Material.Neon, Transparency = 0.35 })
	deco(m, { Name = "CompassHeart", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 1.8, 1.8), CFrame = CFrame.new(c + Vector3.new(0, 0.07, 0)) * FLAT,
		Color = COBBLE, Material = Enum.Material.Slate })
end

-- The front: stone stairs down to the grass where you arrive, walls and
-- lantern posts flanking them, banners.
local function buildFront(m: Model, C: Vector3): CFrame
	local south = Vector3.new(0, 0, 1)
	for k = 1, 3 do
		local top = -k * 0.75
		local z = 47 + (k - 0.5) * 2.6
		part(m, { Name = "Step", Size = Vector3.new(26, top + 9, 2.6), CFrame = CFrame.new(C + Vector3.new(0, top - (top + 9) / 2, z)), Color = STONE })
	end
	-- low brick walls round the front of the plaza, either side of the stairs
	for _, s in ipairs({ -1, 1 }) do
		for i = 0, 7 do
			local a = math.rad(19 + i * 7) * s
			local p = C + Vector3.new(math.sin(a) * 47.6, 1.3, math.cos(a) * 47.6)
			part(m, { Name = "LowWall", Size = Vector3.new(6.2, 2.6, 1.4), CFrame = CFrame.lookAt(p, Vector3.new(C.X, p.Y, C.Z)), Color = BRICK, Material = Enum.Material.Brick })
		end
		-- the posts at the stairhead and along the wall, lanterns on top
		for _, deg in ipairs({ 18, 42, 68 }) do
			local a = math.rad(deg) * s
			local p = C + Vector3.new(math.sin(a) * 47.6, 0, math.cos(a) * 47.6)
			part(m, { Name = "Post", Size = Vector3.new(2.4, 5, 2.4), CFrame = CFrame.new(p + Vector3.new(0, 2.5, 0)), Color = STONE })
			part(m, { Name = "PostCap", Size = Vector3.new(2.9, 0.5, 2.9), CFrame = CFrame.new(p + Vector3.new(0, 5.25, 0)), Color = STONE_DARK })
			lantern(m, p + Vector3.new(0, 5.5, 0), 1.3)
			banner(m, p + Vector3.new(0, 4.4, 0) + (p - C).Unit * 1.3, (p - C).Unit, 1.7, 4.6)
		end
	end
	-- the arrival: on the grass before the stairs
	return CFrame.lookAt(C + Vector3.new(0, 0.3, 64), C + Vector3.new(0, 0.3, 0))
end

-- The DUNGEON gate at the back, up its steps.
local function buildGate(m: Model, C: Vector3, onUse: (Player) -> ()): { Vector3 }
	local zg = -66 -- the arch's plane
	local base = 5 -- the dais top above the plaza
	part(m, { Name = "GateDais", Size = Vector3.new(40, base + 9, 20), CFrame = CFrame.new(C + Vector3.new(0, base - (base + 9) / 2, zg - 2)), Color = STONE })
	for k = 1, base do
		local z = -47 - (k - 0.5) * 2.2
		part(m, { Name = "GateStep", Size = Vector3.new(22, k + 9, 2.2), CFrame = CFrame.new(C + Vector3.new(0, k - (k + 9) / 2, z)), Color = STONE })
	end
	local floor = C.Y + base
	local function at(x: number, y: number, z: number): Vector3 return Vector3.new(C.X + x, floor + y, C.Z + z) end
	-- the pillars
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "GatePillar", Size = Vector3.new(5, 26, 5), CFrame = CFrame.new(at(s * 11.5, 13, zg)), Color = STONE })
		part(m, { Name = "PillarBase", Size = Vector3.new(6.4, 2, 6.4), CFrame = CFrame.new(at(s * 11.5, 1, zg)), Color = STONE_DARK })
		part(m, { Name = "PillarCap", Size = Vector3.new(6.4, 1.6, 6.4), CFrame = CFrame.new(at(s * 11.5, 26.8, zg)), Color = STONE_DARK })
		-- side towers, lower, with lanterns
		part(m, { Name = "SideTower", Size = Vector3.new(5, 15, 5), CFrame = CFrame.new(at(s * 18, 7.5, zg + 1)), Color = STONE })
		part(m, { Name = "SideCap", Size = Vector3.new(6, 1.2, 6), CFrame = CFrame.new(at(s * 18, 15.6, zg + 1)), Color = STONE_DARK })
		lantern(m, at(s * 18, 16.2, zg + 1), 1.4)
		banner(m, at(s * 11.5, 22, zg + 2.6), Vector3.new(0, 0, 1), 2.6, 9)
		banner(m, at(s * 18, 13, zg + 3.6), Vector3.new(0, 0, 1), 2.2, 6.5)
		-- lanterns at the foot of the steps
		part(m, { Name = "StepPost", Size = Vector3.new(2, 4, 2), CFrame = CFrame.new(C + Vector3.new(s * 13, 2, -44)), Color = STONE })
		lantern(m, C + Vector3.new(s * 13, 4, -44), 1.2)
		-- warm light washing up the pillars and the arch
		uplight(m, at(s * 10, 0.2, zg + 5.5), Vector3.new(0, 1, -0.22), Color3.fromRGB(255, 186, 130), 34, 3)
		uplight(m, at(s * 18, 0.2, zg + 5), Vector3.new(0, 1, -0.3), Color3.fromRGB(255, 186, 130), 20, 2)
	end
	-- the arch: a lintel and a curve of voussoirs under it
	part(m, { Name = "Lintel", Size = Vector3.new(30, 4, 6), CFrame = CFrame.new(at(0, 29.6, zg)), Color = STONE })
	part(m, { Name = "Crown", Size = Vector3.new(12, 3, 6.4), CFrame = CFrame.new(at(0, 33, zg)), Color = STONE_DARK })
	local archC = at(0, 19, zg)
	for i = 0, 10 do
		local a = (i / 10) * math.pi
		local p = archC + Vector3.new(math.cos(a) * 9.3, math.sin(a) * 9.3, 0)
		part(m, { Name = "Voussoir", Size = Vector3.new(2.8, 2.8, 5.4), CFrame = CFrame.lookAt(p, p + Vector3.new(0, 0, 1)) * CFrame.Angles(0, 0, a - math.pi / 2),
			Color = STONE })
	end
	-- the sign: DUNGEON under the gold emblem
	local sign = part(m, { Name = "GateSign", Size = Vector3.new(16, 3.4, 0.5), CFrame = CFrame.new(at(0, 29.6, zg + 3.3)) * CFrame.Angles(0, math.pi, 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(sign, Vector2.new(640, 136), function(sg)
		textLabel(sg, "DUNGEON", { Size = UDim2.fromScale(1, 0.85), Position = UDim2.fromScale(0, 0.08) })
	end)
	floorRing(m, at(0, 33, zg + 3.3), 1.6, 0.25, 16, GOLD)
	-- the portal: the arch's opening filled with light
	local portalRect = deco(m, { Name = "Portal", Size = Vector3.new(18.2, 19, 0.4), CFrame = CFrame.new(at(0, 9.5, zg)), Color = PORTAL, Material = Enum.Material.Neon, Transparency = 0.5 })
	deco(m, { Name = "PortalTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 18.2, 18.2), CFrame = CFrame.new(archC) * CFrame.Angles(0, math.rad(90), 0),
		Color = PORTAL, Material = Enum.Material.Neon, Transparency = 0.5 })
	deco(m, { Name = "PortalSwirl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 12, 12), CFrame = CFrame.new(at(0, 12, zg + 0.1)) * CFrame.Angles(0, math.rad(90), 0),
		Color = PORTAL_INNER, Material = Enum.Material.Neon, Transparency = 0.7 })
	for _, r in ipairs({ { 8.6, 0.55, Color3.fromRGB(170, 200, 255) }, { 6, 0.4, Color3.fromRGB(200, 160, 255) } }) do
		for i = 1, 28 do
			local a = i / 28 * math.pi * 2
			local p = at(0, 12, zg + 0.3) + Vector3.new(math.cos(a) * r[1], math.sin(a) * r[1], 0)
			deco(m, { Name = "PortalRing", Size = Vector3.new(r[2], r[1] * 2 * math.pi / 28 + 0.05, 0.1), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, a),
				Color = r[3], Material = Enum.Material.Neon, Transparency = 0.2 })
		end
	end
	local glow = Instance.new("PointLight")
	glow.Color = PORTAL
	glow.Range = 44
	glow.Brightness = 2
	glow.Parent = portalRect
	-- (and onto the steps before it)
	local spill = Instance.new("SpotLight")
	spill.Face = Enum.NormalId.Back
	spill.Angle = 80
	spill.Color = Color3.fromRGB(130, 140, 255)
	spill.Range = 40
	spill.Brightness = 2.2
	spill.Parent = portalRect
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	swirl.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255), PORTAL_INNER)
	swirl.LightEmission = 1
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	swirl.Lifetime = NumberRange.new(1.2, 2.4)
	swirl.Speed = NumberRange.new(1, 4)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.Rate = 40
	swirl.Parent = portalRect
	-- ivy and flowers creeping over the arch
	for i = 1, 14 do
		local a = (i / 14) * math.pi
		local p = archC + Vector3.new(math.cos(a) * 11.6, math.sin(a) * 11.6 + 1, 2.4)
		deco(m, { Name = "Ivy", Shape = Enum.PartType.Ball, Size = Vector3.one * (1.4 + (i % 3) * 0.5), CFrame = CFrame.new(p),
			Color = Color3.fromRGB(64, 104, 48), Material = Enum.Material.Grass })
		if i % 3 == 0 then
			deco(m, { Name = "Bloom", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, CFrame = CFrame.new(p + Vector3.new(0, 0.4, 0.7)),
				Color = Color3.fromRGB(230, 160, 210), Material = Enum.Material.SmoothPlastic })
		end
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Choose a dungeon"
	prompt.ObjectText = "Dungeon Gate"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 22
	prompt.RequiresLineOfSight = false
	prompt.Parent = portalRect
	prompt.Triggered:Connect(onUse)
	-- the string lights tie onto the side towers' caps
	return { at(-18, 15.9, zg + 3.4), at(18, 15.9, zg + 3.4) }
end

-- The great tree on the left, a lantern hanging from the bough over the plaza.
local function buildTree(m: Model, C: Vector3, rng: Random)
	local base = C + Vector3.new(-58, -4, -26)
	local trunkCol = Color3.fromRGB(84, 60, 44)
	deco(m, { Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(22, 7.5, 7.5), CFrame = CFrame.new(base + Vector3.new(0, 11, 0)) * FLAT,
		Color = trunkCol, Material = Enum.Material.Wood }).CanCollide = true
	deco(m, { Name = "Trunk", Shape = Enum.PartType.Cylinder, Size = Vector3.new(18, 6, 6), CFrame = CFrame.new(base + Vector3.new(1.5, 27, 1)) * FLAT * CFrame.Angles(0.15, 0, 0),
		Color = trunkCol, Material = Enum.Material.Wood })
	for i = 0, 4 do
		local a = i / 5 * math.pi * 2
		deco(m, { Name = "Root", Size = Vector3.new(3, 4, 7), CFrame = CFrame.new(base + Vector3.new(math.cos(a) * 4.5, 1.6, math.sin(a) * 4.5))
			* CFrame.Angles(0, -a + math.pi / 2, 0), Color = trunkCol, Material = Enum.Material.Wood }, "WedgePart")
	end
	-- the bough reaching out over the plaza
	local from = base + Vector3.new(2, 26, 2)
	local to = C + Vector3.new(-30, 24, -10)
	local mid = (from + to) / 2
	deco(m, { Name = "Bough", Shape = Enum.PartType.Cylinder, Size = Vector3.new((to - from).Magnitude, 2.8, 2.8),
		CFrame = CFrame.lookAt(mid, to) * CFrame.Angles(0, math.rad(90), 0), Color = trunkCol, Material = Enum.Material.Wood })
	-- the canopy
	local leaf = { Color3.fromRGB(62, 104, 46), Color3.fromRGB(78, 122, 52), Color3.fromRGB(96, 138, 60), Color3.fromRGB(54, 90, 42) }
	for i = 1, 12 do
		local p = base + Vector3.new(rng:NextNumber(-14, 14), rng:NextNumber(30, 40), rng:NextNumber(-14, 14))
		deco(m, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(14, 22), CFrame = CFrame.new(p),
			Color = leaf[(i % #leaf) + 1], Material = Enum.Material.Grass })
	end
	for i = 1, 6 do
		local p = from:Lerp(to, i / 6) + Vector3.new(rng:NextNumber(-3, 3), rng:NextNumber(3, 7), rng:NextNumber(-3, 3))
		deco(m, { Name = "Leaves", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(8, 13), CFrame = CFrame.new(p),
			Color = leaf[(i % #leaf) + 1], Material = Enum.Material.Grass })
	end
	-- the hanging lantern
	local hang = to + Vector3.new(-1, -1, 0)
	deco(m, { Name = "Chain", Size = Vector3.new(0.18, 6, 0.18), CFrame = CFrame.new(hang - Vector3.new(0, 3, 0)), Color = Color3.fromRGB(40, 36, 36), Material = Enum.Material.Metal })
	lantern(m, hang - Vector3.new(0, 8.3, 0), 1.5)
	banner(m, from + Vector3.new(6, -6, 4), Vector3.new(1, 0, 0.3).Unit, 2, 6)
end

-- The QUESTS board on the left: a roofed notice board listing the dungeons.
local function buildQuestBoard(m: Model, C: Vector3, maps: { any }, onUse: (Player) -> ()): Vector3
	local pos = C + Vector3.new(-36, 0, -6)
	local face = CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0.35).Unit) -- toward the plaza's middle
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "BoardPost", Size = Vector3.new(1, 12, 1), CFrame = face * CFrame.new(s * 7.4, 6, 0), Color = WOOD, Material = Enum.Material.Wood })
		lantern(m, (face * CFrame.new(s * 7.4, 12, 0.6)).Position, 1.1)
	end
	local board = part(m, { Name = "QuestBoard", Size = Vector3.new(14, 8.4, 0.6), CFrame = face * CFrame.new(0, 6.6, 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	for _, y in ipairs({ -4.4, 4.4 }) do
		part(m, { Name = "BoardFrame", Size = Vector3.new(15, 0.6, 0.9), CFrame = face * CFrame.new(0, 6.6 + y, 0), Color = WOOD, Material = Enum.Material.Wood })
	end
	-- the little roof over it
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "BoardRoof", Size = Vector3.new(17, 0.5, 3.2), CFrame = face * CFrame.new(0, 13.6, s * 1.3) * CFrame.Angles(math.rad(28 * s), 0, 0),
			Color = Color3.fromRGB(96, 40, 32), Material = Enum.Material.WoodPlanks })
	end
	local sign = part(m, { Name = "QuestSign", Size = Vector3.new(7, 1.8, 0.4), CFrame = face * CFrame.new(0, 11.7, -0.5), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(sign, Vector2.new(420, 108), function(sg)
		textLabel(sg, "QUESTS", { Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1) })
	end)
	boardText(board, Vector2.new(700, 420), function(sg)
		local list = Instance.new("Frame")
		list.BackgroundTransparency = 1
		list.Size = UDim2.new(1, -60, 1, -40)
		list.Position = UDim2.fromOffset(30, 20)
		list.Parent = sg
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 10)
		lay.Parent = list
		for _, map in ipairs(maps) do
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, 86)
			row.Parent = list
			textLabel(row, "•  " .. map.name, { Size = UDim2.new(1, 0, 0.55, 0), TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(240, 222, 180) })
			textLabel(row, "     (Rank: " .. tostring(map.rank or "?") .. ")  " .. map.subtitle, { Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.58),
				TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = map.color })
		end
	end)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Read the quests"
	prompt.ObjectText = "Quest Board"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = board
	prompt.Triggered:Connect(onUse)
	return (face * CFrame.new(7.4, 13, -1.6)).Position -- the roof's corner nearer the stairs
end

-- Market stalls with striped awnings, crates and barrels.
local function buildStall(m: Model, pos: Vector3, facing: Vector3, rng: Random)
	local cf = CFrame.lookAt(pos, pos + facing)
	part(m, { Name = "Counter", Size = Vector3.new(9, 3, 3), CFrame = cf * CFrame.new(0, 1.5, 0), Color = WOOD, Material = Enum.Material.WoodPlanks })
	for _, x in ipairs({ -4.2, 4.2 }) do
		for _, z in ipairs({ -1.2, 4 }) do
			part(m, { Name = "Pole", Size = Vector3.new(0.5, 7.5, 0.5), CFrame = cf * CFrame.new(x, 3.75, z), Color = WOOD_DARK, Material = Enum.Material.Wood })
		end
	end
	for i = 0, 5 do
		local x = -4.5 + 1.5 * (i + 0.5)
		deco(m, { Name = "Awning", Size = Vector3.new(1.5, 0.2, 7.4), CFrame = cf * CFrame.new(x, 7.2, 1.4) * CFrame.Angles(math.rad(-14), 0, 0),
			Color = if i % 2 == 0 then Color3.fromRGB(226, 208, 170) else Color3.fromRGB(150, 44, 40), Material = Enum.Material.Fabric })
	end
	for _ = 1, 3 do
		local s = rng:NextNumber(1.2, 2)
		part(m, { Name = "Crate", Size = Vector3.one * s, CFrame = cf * CFrame.new(rng:NextNumber(-4, 4), s / 2, rng:NextNumber(-3.4, -2)) * CFrame.Angles(0, rng:NextNumber(0, 1), 0),
			Color = Color3.fromRGB(120, 86, 56), Material = Enum.Material.WoodPlanks })
	end
	part(m, { Name = "Barrel", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.6, 2, 2), CFrame = cf * CFrame.new(5.6, 1.3, 1) * FLAT,
		Color = Color3.fromRGB(110, 76, 48), Material = Enum.Material.Wood })
	-- goods on the counter
	for i = 1, 4 do
		deco(m, { Name = "Goods", Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = cf * CFrame.new(-3 + i * 1.3, 3.4, 0),
			Color = ({ Color3.fromRGB(200, 60, 50), Color3.fromRGB(230, 180, 60), Color3.fromRGB(120, 170, 70), Color3.fromRGB(160, 90, 200) })[i] })
	end
end

-- The GACHA tent on the right: purple-lit, a crystal on its pedestal, the
-- magic circle before it and its menu board.
local function buildGacha(m: Model, C: Vector3, onUse: (Player) -> ()): Vector3
	local pos = C + Vector3.new(34, 0, -12)
	local face = CFrame.lookAt(pos, pos + Vector3.new(-1, 0, 0.3).Unit) -- opening toward the plaza
	local function at(x: number, y: number, z: number): CFrame return face * CFrame.new(x, y, z) end
	part(m, { Name = "TentFloor", Size = Vector3.new(18, 0.8, 13), CFrame = at(0, 0.4, 2), Color = Color3.fromRGB(70, 44, 52), Material = Enum.Material.WoodPlanks })
	local back = part(m, { Name = "TentBack", Size = Vector3.new(18, 12, 0.6), CFrame = at(0, 6.4, 8.4), Color = Color3.fromRGB(46, 26, 84), Material = Enum.Material.Neon, Transparency = 0.1 })
	local stars = Instance.new("ParticleEmitter")
	stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	stars.Color = ColorSequence.new(Color3.fromRGB(220, 200, 255))
	stars.LightEmission = 1
	stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 0) })
	stars.Lifetime = NumberRange.new(2, 4)
	stars.Speed = NumberRange.new(0.1, 0.4)
	stars.Rate = 14
	stars.EmissionDirection = Enum.NormalId.Back
	stars.Parent = back
	for _, x in ipairs({ -8.6, 8.6 }) do
		for _, z in ipairs({ -4, 8 }) do
			part(m, { Name = "TentPole", Size = Vector3.new(0.8, 12, 0.8), CFrame = at(x, 6, z), Color = WOOD, Material = Enum.Material.Wood })
		end
		part(m, { Name = "TentSide", Size = Vector3.new(0.3, 11, 12), CFrame = at(x, 6.2, 2), Color = Color3.fromRGB(96, 26, 44), Material = Enum.Material.Fabric })
	end
	-- the gabled roof (red, gold-trimmed) with its peak
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "TentRoof", Size = Vector3.new(11, 0.4, 15), CFrame = at(s * 4.6, 14.4, 2) * CFrame.Angles(0, 0, math.rad(-32 * s)),
			Color = Color3.fromRGB(120, 28, 40), Material = Enum.Material.Fabric })
		deco(m, { Name = "RoofTrim", Size = Vector3.new(11, 0.25, 0.3), CFrame = at(s * 4.6, 14.2, -5.5) * CFrame.Angles(0, 0, math.rad(-32 * s)), Color = GOLD, Material = Enum.Material.Metal })
	end
	deco(m, { Name = "Finial", Size = Vector3.new(0.8, 2.4, 0.8), CFrame = at(0, 18.6, -4), Color = GOLD, Material = Enum.Material.Metal })
	-- the sign over the opening
	local sign = part(m, { Name = "GachaSign", Size = Vector3.new(11, 2.8, 0.5), CFrame = at(0, 12.6, -4.6), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(sign, Vector2.new(560, 142), function(sg)
		textLabel(sg, "GACHA", { Size = UDim2.fromScale(1, 0.82), Position = UDim2.fromScale(0, 0.09) })
	end)
	-- the crystal on its pedestal, glowing
	part(m, { Name = "Pedestal", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.4, 3, 3), CFrame = at(0, 2.5, 3) * FLAT, Color = Color3.fromRGB(70, 56, 86), Material = Enum.Material.Marble })
	local crystal = deco(m, { Name = "GachaCrystal", Size = Vector3.new(2.6, 4.4, 2.6), CFrame = at(0, 7, 3) * CFrame.Angles(0, math.rad(45), math.rad(45)),
		Color = Color3.fromRGB(150, 100, 240), Material = Enum.Material.Neon, Transparency = 0.25 })
	deco(m, { Name = "CrystalHalo", Shape = Enum.PartType.Ball, Size = Vector3.one * 6, CFrame = at(0, 7, 3), Color = GACHA_PURPLE, Material = Enum.Material.Neon, Transparency = 0.85 })
	floorRing(m, at(0, 7, 3).Position, 3.6, 0.2, 24, GOLD)
	local cl = Instance.new("PointLight")
	cl.Color = GACHA_PURPLE
	cl.Range = 28
	cl.Brightness = 2
	cl.Parent = crystal
	-- the magic circle before the tent
	local mc = at(0, 0.06, -9).Position
	mc = Vector3.new(mc.X, C.Y + 0.05, mc.Z)
	floorRing(m, mc, 5, 0.3, 32, Color3.fromRGB(240, 90, 200))
	floorRing(m, mc, 3.6, 0.2, 24, Color3.fromRGB(240, 120, 220))
	for i = 0, 5 do
		local a = i * math.pi / 3
		floorPoint(m, mc, Vector3.new(math.cos(a), 0, math.sin(a)), 3.4, 0.6, Color3.fromRGB(240, 120, 220), Enum.Material.Neon)
	end
	-- banners on the front poles, lanterns
	for _, x in ipairs({ -8.6, 8.6 }) do
		banner(m, at(x, 10.6, -4.6).Position, face.LookVector, 1.8, 5.2, Color3.fromRGB(70, 34, 110))
		lantern(m, at(x * 1.18, 0, -6).Position, 1.2)
	end
	-- the menu board beside it
	local menu = part(m, { Name = "GachaMenu", Size = Vector3.new(7, 8, 0.4), CFrame = at(-12.5, 5.4, -1) * CFrame.Angles(0, math.rad(-20), 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(menu, Vector2.new(350, 400), function(sg)
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 12)
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.VerticalAlignment = Enum.VerticalAlignment.Center
		lay.Parent = sg
		for _, w in ipairs({ "Characters", "Variants", "Relics", "Cosmetics" }) do
			textLabel(sg, "•  " .. w, { Size = UDim2.new(0.86, 0, 0, 62), TextXAlignment = Enum.TextXAlignment.Left })
		end
	end)
	for _, x in ipairs({ -3.2, 3.2 }) do
		part(m, { Name = "MenuPost", Size = Vector3.new(0.5, 4, 0.5), CFrame = at(-12.5, 2, -1) * CFrame.Angles(0, math.rad(-20), 0) * CFrame.new(x, 0, 0.3),
			Color = WOOD, Material = Enum.Material.Wood })
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Summon"
	prompt.ObjectText = "Gacha"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = crystal
	prompt.Triggered:Connect(onUse)
	return at(-8.6, 11.6, -4).Position -- the front pole nearer the stairs
end

-- The fence on the right, a waterfall off the island's edge, bushes and
-- flowers round the plaza.
local function buildEdges(m: Model, C: Vector3, rng: Random)
	-- the wooden fence along the right
	for i = 0, 18 do
		local a = math.rad(-40 + i * 6)
		local p = C + Vector3.new(math.cos(a) * 74, -3, math.sin(a) * 74)
		part(m, { Name = "FencePost", Size = Vector3.new(0.8, 4.4, 0.8), CFrame = CFrame.new(p + Vector3.new(0, 2.2, 0)), Color = WOOD, Material = Enum.Material.Wood })
		if i < 18 then
			local a2 = math.rad(-40 + (i + 1) * 6)
			local p2 = C + Vector3.new(math.cos(a2) * 74, -3, math.sin(a2) * 74)
			for _, y in ipairs({ 1.6, 3.4 }) do
				local mid = (p + p2) / 2 + Vector3.new(0, y, 0)
				part(m, { Name = "FenceRail", Size = Vector3.new(0.35, 0.45, (p2 - p).Magnitude + 0.4), CFrame = CFrame.lookAt(mid, p2 + Vector3.new(0, y, 0)),
					Color = WOOD, Material = Enum.Material.Wood })
			end
		end
	end
	-- the waterfall spilling off the right edge
	local wf = C + Vector3.new(84, -4, 18)
	local fall = deco(m, { Name = "Waterfall", Size = Vector3.new(0.6, 140, 10), CFrame = CFrame.new(wf - Vector3.new(0, 70, 0)),
		Color = Color3.fromRGB(150, 200, 255), Material = Enum.Material.Neon, Transparency = 0.45 })
	deco(m, { Name = "Stream", Size = Vector3.new(16, 0.3, 10), CFrame = CFrame.new(wf + Vector3.new(-8, 1.2, 0)),
		Color = Color3.fromRGB(120, 180, 240), Material = Enum.Material.Glass, Transparency = 0.3 })
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 12) })
	mist.Lifetime = NumberRange.new(2, 3.5)
	mist.Speed = NumberRange.new(2, 5)
	mist.Rate = 10
	mist.Parent = fall
	-- bushes and flowers round the plaza's rim (not on the stairs or before the gate)
	local blooms = { Color3.fromRGB(240, 240, 250), Color3.fromRGB(230, 150, 200), Color3.fromRGB(180, 140, 230), Color3.fromRGB(250, 220, 120) }
	for _ = 1, 70 do
		local a = rng:NextNumber(0, math.pi * 2)
		local deg = math.deg(a)
		-- (keep the front stairs (≈ 90°) and the gate (≈ 270°) clear)
		if math.abs(deg - 90) < 18 or math.abs(deg - 270) < 26 then continue end
		local r = rng:NextNumber(50, 70)
		local p = C + Vector3.new(math.cos(a) * r, -3, math.sin(a) * r)
		local s = rng:NextNumber(2.2, 4.6)
		deco(m, { Name = "Bush", Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = CFrame.new(p + Vector3.new(0, s * 0.3, 0)),
			Color = Color3.fromRGB(rng:NextInteger(54, 84), rng:NextInteger(92, 128), rng:NextInteger(40, 58)), Material = Enum.Material.Grass })
		for _ = 1, 3 do
			local fp = p + Vector3.new(rng:NextNumber(-3, 3), 0.25, rng:NextNumber(-3, 3))
			deco(m, { Name = "Flower", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(0.4, 0.75), CFrame = CFrame.new(fp),
				Color = blooms[rng:NextInteger(1, #blooms)], Material = Enum.Material.SmoothPlastic })
		end
	end
	-- a few mossy rocks
	for _ = 1, 10 do
		local a = rng:NextNumber(0, math.pi * 2)
		local deg = math.deg(a)
		if math.abs(deg - 90) < 18 or math.abs(deg - 270) < 26 then continue end
		local p = C + Vector3.new(math.cos(a) * rng:NextNumber(56, 78), -3, math.sin(a) * rng:NextNumber(56, 78))
		local s = rng:NextNumber(2, 5)
		part(m, { Name = "Rock", Size = Vector3.new(s * 1.4, s, s * 1.2), CFrame = CFrame.new(p + Vector3.new(0, s * 0.3, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6), 0),
			Color = Color3.fromRGB(96, 92, 90), Material = Enum.Material.Rock })
	end
end

function LobbyBuilder.Build(parent: Instance, C: Vector3, maps: { any }, prompts: Prompts): (Model, CFrame)
	local rng = Random.new(20261004)
	local m = Instance.new("Model")
	m.Name = "Lobby"
	-- (always streamed in whole: everyone in it sees all of it)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildIsland(m, C, rng)
	buildCompass(m, C)
	local spawnCF = buildFront(m, C)
	local towers = buildGate(m, C, prompts.dungeon)
	buildTree(m, C, rng)
	local boardHook = buildQuestBoard(m, C, maps, prompts.quests)
	buildStall(m, C + Vector3.new(-38, 0, 14), Vector3.new(1, 0, -0.25).Unit, rng)
	buildStall(m, C + Vector3.new(-26, 0, 28), Vector3.new(0.6, 0, -1).Unit, rng)
	local tentHook = buildGacha(m, C, prompts.gacha)
	buildEdges(m, C, rng)
	-- Lamp posts at the stairhead, strings of lights from them up to the
	-- gate's towers (framing the way in), across the stairhead, and out to the
	-- quest board and the gacha tent.
	local lights = Instance.new("Model")
	lights.Name = "StringLights"
	lights.Parent = m
	local left = lampPost(lights, C + Vector3.new(-17, 0, 37), 13, Vector3.new(1, 0, 0))
	local right = lampPost(lights, C + Vector3.new(17, 0, 37), 13, Vector3.new(-1, 0, 0))
	festoon(lights, left, towers[1], 4)
	festoon(lights, right, towers[2], 4)
	festoon(lights, left, right, 2.2)
	festoon(lights, left, boardHook, 2.5)
	festoon(lights, right, tentHook, 2.5)
	m.Parent = parent or Workspace
	return m, spawnCF
end

return LobbyBuilder
