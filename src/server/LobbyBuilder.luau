--!strict
--[[
	LobbyBuilder.luau
	Builds the lobby, The Crossroads (after the concept art): a floating grassy
	island at dusk, a round cobblestone plaza with a great glowing magic circle
	and a crystal fountain at its heart; at the back a gothic cathedral up a
	flight of steps, the great blue portal ring in its doorway (the DUNGEON
	gate), two angelic statues guarding it; round the plaza the stations, each
	with a floating label: the WARDROBE and the SUMMONING tent (the gacha) at
	the back, the ARMORY and the BUILD CODEX at the front; the guild podium
	(GUILD CHAMPIONS: LobbyPodium stands the season's top contributors on it)
	with the Guild board, and the QUESTS board. Wide stairs at the front, lamp
	posts and strings of lights, navy banners, blue crystal lamps, waterfalls
	off the edges and small floating islands round it. (The castles round it
	and the lobby's light grade are drawn on each client: MenuBackdrop.)

	LobbyBuilder.Build(parent, center, maps, prompts) → (model, spawn CFrame)
	  prompts.dungeon / prompts.quests / prompts.gacha (player) are called when
	  a player uses the gate, the board or the summoning tent. The Armory,
	  Wardrobe, Build Codex and Guild board open their screens on the client:
	  their prompts carry an OpenScreen attribute (LobbyHUD).

	The plaza faces north (-Z): the cathedral is at the back, you arrive at
	the front stairs (+Z).
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

-- The QUESTS board: a roofed notice board listing the dungeons, facing the
-- plaza's middle.
local function buildQuestBoard(m: Model, pos: Vector3, C: Vector3, maps: { any }, onUse: (Player) -> ()): Vector3
	local face = CFrame.lookAt(pos, Vector3.new(C.X, pos.Y, C.Z))
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
		lay.Padding = UDim.new(0, 8)
		lay.Parent = list
		-- (the rows share the board's height, however many maps there are)
		local rowH = math.min(86, math.floor((380 - 8 * (#maps - 1)) / math.max(#maps, 1)))
		for _, map in ipairs(maps) do
			local row = Instance.new("Frame")
			row.BackgroundTransparency = 1
			row.Size = UDim2.new(1, 0, 0, rowH)
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

-- ── The pieces ──────────────────────────────────────────────────────────────
local NAVY = Color3.fromRGB(26, 34, 78)
local CRYSTAL = Color3.fromRGB(90, 160, 255)
local CRYSTAL_HOT = Color3.fromRGB(190, 225, 255)
local MARBLE = Color3.fromRGB(214, 210, 204)
local PLAZA_R = 56

-- A floating label over a station: its emblem and name, seen from across
-- the plaza.
local function stationLabel(parent: BasePart, text: string, glyph: string, height: number)
	local bb = Instance.new("BillboardGui")
	bb.Name = "StationLabel"
	-- (sized in studs: it shrinks with distance like a sign, never crowding)
	bb.Size = UDim2.new(13, 0, 4.4, 0)
	bb.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 260
	bb.AlwaysOnTop = true -- (over roofs and awnings: always readable)
	bb.Parent = parent
	local icon = Instance.new("TextLabel")
	icon.BackgroundColor3 = Color3.fromRGB(22, 18, 26)
	icon.BackgroundTransparency = 0.15
	icon.AnchorPoint = Vector2.new(0.5, 0)
	icon.Position = UDim2.fromScale(0.5, 0)
	icon.Size = UDim2.fromScale(0.5, 0.5)
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 1
	ar.Parent = icon
	icon.Font = FONT
	icon.TextScaled = true
	icon.TextColor3 = Color3.fromRGB(240, 214, 160)
	icon.Text = glyph
	icon.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = icon
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Thickness = 2
	s.Parent = icon
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromScale(0, 0.54)
	t.Size = UDim2.fromScale(1, 0.44)
	t.Font = FONT
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(250, 236, 200)
	t.TextStrokeTransparency = 0.25
	t.TextStrokeColor3 = Color3.fromRGB(30, 20, 10)
	t.Text = text
	t.Parent = bb
end

-- A prompt that opens one of the lobby's screens on the client (LobbyHUD
-- reads OpenScreen) instead of calling the server.
local function screenPrompt(parent: BasePart, action: string, object: string, screen: string, dist: number)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = dist
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("OpenScreen", screen)
	prompt.Parent = parent
end

-- A blue crystal on a stone stand, glowing (the lobby's cool accent light).
local function crystalLamp(parent: Instance, pos: Vector3, scale: number?)
	local k = scale or 1
	part(parent, { Name = "CrystalStand", Size = Vector3.new(1.6, 3, 1.6) * k, CFrame = CFrame.new(pos + Vector3.new(0, 1.5 * k, 0)), Color = STONE_DARK })
	local c = deco(parent, { Name = "Crystal", Size = Vector3.new(1, 2.6, 1) * k, CFrame = CFrame.new(pos + Vector3.new(0, 4.4 * k, 0)) * CFrame.Angles(0, math.rad(45), math.rad(12)),
		Color = CRYSTAL, Material = Enum.Material.Neon, Transparency = 0.15, CastShadow = false })
	local l = Instance.new("PointLight")
	l.Color = CRYSTAL
	l.Range = 14 * k
	l.Brightness = 1.4
	l.Shadows = false
	l.Parent = c
end

local function buildIsland(m: Model, C: Vector3, rng: Random)
	-- grass top, a raised cobblestone plaza in its middle, rock below
	part(m, { Name = "Grass", Shape = Enum.PartType.Cylinder, Size = Vector3.new(8, 196, 196), Material = Enum.Material.Grass, Color = GRASS,
		CFrame = CFrame.new(C + Vector3.new(0, -7, 0)) * FLAT })
	part(m, { Name = "Plaza", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, PLAZA_R * 2, PLAZA_R * 2), Material = Enum.Material.Cobblestone, Color = COBBLE,
		CFrame = CFrame.new(C + Vector3.new(0, -2, 0)) * FLAT })
	-- the curb round the plaza (gaps for the front stairs and the cathedral steps)
	local n = 56
	for i = 1, n do
		local a = (i / n) * math.pi * 2
		local deg = math.deg(a)
		if math.abs(deg - 90) < 14 or math.abs(deg - 270) < 18 then continue end
		local p = C + Vector3.new(math.cos(a) * (PLAZA_R + 0.3), -1.6, math.sin(a) * (PLAZA_R + 0.3))
		part(m, { Name = "Curb", Size = Vector3.new(1.4, 3.4, (PLAZA_R + 0.3) * 2 * math.pi / n + 0.2),
			CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), Color = STONE_DARK })
	end
	-- the island's underside: a great rock, crags hanging off it
	deco(m, { Name = "Earth", Shape = Enum.PartType.Cylinder, Size = Vector3.new(16, 192, 192), Material = Enum.Material.Ground,
		Color = Color3.fromRGB(92, 70, 56), CFrame = CFrame.new(C + Vector3.new(0, -19, 0)) * FLAT })
	deco(m, { Name = "Underside", Shape = Enum.PartType.Ball, Size = Vector3.one * 172, Material = Enum.Material.Rock,
		Color = Color3.fromRGB(96, 84, 86), CFrame = CFrame.new(C + Vector3.new(0, -98, 0)) })
	for _ = 1, 14 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r = rng:NextNumber(24, 72)
		local h = rng:NextNumber(30, 80)
		deco(m, { Name = "Crag", Size = Vector3.new(rng:NextNumber(14, 28), h, rng:NextNumber(14, 28)), Material = Enum.Material.Rock,
			Color = Color3.fromRGB(86, 74, 78), CFrame = CFrame.new(C + Vector3.new(math.cos(a) * r, -26 - h / 2, math.sin(a) * r)) * CFrame.Angles(math.pi, rng:NextNumber(0, 6), 0) },
			"CornerWedgePart")
	end
end

-- The great magic circle in the plaza: glowing blue rings, gold runes, an
-- eight-pointed star; the crystal fountain at its heart.
local function buildCircle(m: Model, C: Vector3)
	local c = C + Vector3.new(0, 0.04, 0)
	floorRing(m, c, 24, 0.7, 72, CRYSTAL)
	floorRing(m, c, 22.6, 0.25, 64, GOLD, Enum.Material.Metal)
	floorRing(m, c, 17, 0.5, 56, CRYSTAL)
	floorRing(m, c, 11.5, 0.3, 40, GOLD, Enum.Material.Metal)
	-- runes between the outer rings
	for i = 1, 24 do
		local a = (i / 24) * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 20, 0.02, math.sin(a) * 20)
		deco(m, { Name = "Rune", Size = Vector3.new(0.9, 0.06, 1.6), CFrame = CFrame.lookAt(p, c) * CFrame.Angles(0, math.rad(if i % 2 == 0 then 0 else 45), 0),
			Color = if i % 3 == 0 then GOLD else CRYSTAL_HOT, Material = Enum.Material.Neon, Transparency = 0.2 })
	end
	-- the star: long blue points, short gold ones between
	for i = 0, 7 do
		local a = i * math.pi / 4 + math.pi / 8
		local dir = Vector3.new(math.sin(a), 0, -math.cos(a))
		local long = i % 2 == 0
		floorPoint(m, c + Vector3.new(0, 0.02, 0), dir, if long then 22 else 14, if long then 4 else 2.6,
			if long then Color3.fromRGB(120, 150, 255) else GOLD, if long then Enum.Material.Neon else Enum.Material.Metal)
	end
	-- the fountain: a round basin, a tier, water, the floating crystal
	local f = C
	part(m, { Name = "Basin", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 16, 16), CFrame = CFrame.new(f + Vector3.new(0, 1.2, 0)) * FLAT, Color = MARBLE, Material = Enum.Material.Marble })
	deco(m, { Name = "BasinWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 14.4, 14.4), CFrame = CFrame.new(f + Vector3.new(0, 2.25, 0)) * FLAT,
		Color = Color3.fromRGB(90, 150, 230), Material = Enum.Material.Glass, Transparency = 0.25 })
	for i = 1, 16 do
		local a = (i / 16) * math.pi * 2
		local p = f + Vector3.new(math.cos(a) * 8.1, 2.7, math.sin(a) * 8.1)
		part(m, { Name = "BasinRim", Size = Vector3.new(1, 0.9, 3.4), CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), Color = MARBLE, Material = Enum.Material.Marble })
	end
	part(m, { Name = "FountainColumn", Shape = Enum.PartType.Cylinder, Size = Vector3.new(5, 3, 3), CFrame = CFrame.new(f + Vector3.new(0, 4.5, 0)) * FLAT, Color = MARBLE, Material = Enum.Material.Marble })
	part(m, { Name = "FountainTier", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 7, 7), CFrame = CFrame.new(f + Vector3.new(0, 7.2, 0)) * FLAT, Color = MARBLE, Material = Enum.Material.Marble })
	deco(m, { Name = "TierWater", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 6.2, 6.2), CFrame = CFrame.new(f + Vector3.new(0, 7.75, 0)) * FLAT,
		Color = Color3.fromRGB(110, 170, 240), Material = Enum.Material.Glass, Transparency = 0.2 })
	-- four small gold dragons' heads spouting into the basin
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		deco(m, { Name = "Spout", Size = Vector3.new(0.8, 0.8, 1.6), CFrame = CFrame.lookAt(f + out * 3.4 + Vector3.new(0, 7, 0), f + out * 6 + Vector3.new(0, 6, 0)),
			Color = GOLD, Material = Enum.Material.Metal })
		local stream = deco(m, { Name = "Spray", Size = Vector3.new(0.3, 4.4, 0.3), CFrame = CFrame.new(f + out * 4.6 + Vector3.new(0, 4.6, 0)) * CFrame.Angles(out.Z * 0.35, 0, -out.X * 0.35),
			Color = Color3.fromRGB(170, 210, 255), Material = Enum.Material.Neon, Transparency = 0.72, CastShadow = false })
		local drip = Instance.new("ParticleEmitter")
		drip.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		drip.Color = ColorSequence.new(Color3.fromRGB(200, 230, 255))
		drip.LightEmission = 0.8
		drip.Size = NumberSequence.new(0.25)
		drip.Lifetime = NumberRange.new(0.4, 0.8)
		drip.Speed = NumberRange.new(1, 3)
		drip.Rate = 10
		drip.Parent = stream
	end
	-- the crystal, floating and turning (spun on every client: LobbyCrystal tag)
	local crystal = deco(m, { Name = "FountainCrystal", Size = Vector3.new(3.4, 3.4, 3.4), CFrame = CFrame.new(f + Vector3.new(0, 14, 0)) * CFrame.Angles(math.rad(45), 0, math.rad(45)),
		Color = CRYSTAL, Material = Enum.Material.Neon, Transparency = 0.1, CastShadow = false })
	crystal:AddTag("LobbyCrystal")
	deco(m, { Name = "CrystalHalo", Shape = Enum.PartType.Ball, Size = Vector3.one * 9, CFrame = CFrame.new(f + Vector3.new(0, 14, 0)),
		Color = CRYSTAL, Material = Enum.Material.Neon, Transparency = 0.88, CastShadow = false })
	local cl = Instance.new("PointLight")
	cl.Color = CRYSTAL
	cl.Range = 40
	cl.Brightness = 2.4
	cl.Parent = crystal
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(CRYSTAL_HOT, CRYSTAL)
	motes.LightEmission = 1
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	motes.Lifetime = NumberRange.new(1.5, 3)
	motes.Speed = NumberRange.new(0.5, 2)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Rate = 18
	motes.Parent = crystal
end

-- The front: wide stone stairs down to the grass where you arrive, lantern
-- posts and banners flanking them.
local function buildFront(m: Model, C: Vector3): CFrame
	for k = 1, 3 do
		local top = -k * 0.75
		local z = PLAZA_R - 1 + (k - 0.5) * 2.6
		part(m, { Name = "Step", Size = Vector3.new(30, top + 9, 2.6), CFrame = CFrame.new(C + Vector3.new(0, top - (top + 9) / 2, z)), Color = STONE })
	end
	for _, s in ipairs({ -1, 1 }) do
		for _, deg in ipairs({ 16, 30 }) do
			local a = math.rad(deg) * s
			local p = C + Vector3.new(math.sin(a) * (PLAZA_R - 0.4), 0, math.cos(a) * (PLAZA_R - 0.4))
			part(m, { Name = "Post", Size = Vector3.new(2.4, 5, 2.4), CFrame = CFrame.new(p + Vector3.new(0, 2.5, 0)), Color = STONE })
			part(m, { Name = "PostCap", Size = Vector3.new(2.9, 0.5, 2.9), CFrame = CFrame.new(p + Vector3.new(0, 5.25, 0)), Color = STONE_DARK })
			lantern(m, p + Vector3.new(0, 5.5, 0), 1.3)
			banner(m, p + Vector3.new(0, 4.4, 0) + (p - C).Unit * 1.3, (p - C).Unit, 1.7, 4.6, NAVY)
		end
		-- crystal spires at the foot of the stairs
		crystalLamp(m, C + Vector3.new(s * 17, -3, PLAZA_R + 9), 1.3)
	end
	return CFrame.lookAt(C + Vector3.new(0, 0.3, PLAZA_R + 16), C + Vector3.new(0, 0.3, 0))
end

-- The cathedral at the back: a gothic front with spires and a rose window,
-- the great blue portal ring in its arched doorway (the DUNGEON gate).
local function buildCathedral(m: Model, C: Vector3, onUse: (Player) -> ()): { Vector3 }
	local zg = -78 -- the doorway's plane
	local base = 6 -- the dais top above the plaza
	part(m, { Name = "GateDais", Size = Vector3.new(64, base + 9, 26), CFrame = CFrame.new(C + Vector3.new(0, base - (base + 9) / 2, zg - 2)), Color = STONE })
	for k = 1, base do
		local z = -PLAZA_R + 1 - (k - 0.5) * 2.4
		part(m, { Name = "GateStep", Size = Vector3.new(30, k + 9, 2.4), CFrame = CFrame.new(C + Vector3.new(0, k - (k + 9) / 2, z)), Color = STONE })
	end
	local floor = C.Y + base
	local function at(x: number, y: number, z: number): Vector3 return Vector3.new(C.X + x, floor + y, C.Z + z) end
	local DARKSTONE = Color3.fromRGB(70, 66, 78)
	-- the facade: a tall wall, buttresses, the gable
	part(m, { Name = "Facade", Size = Vector3.new(40, 46, 6), CFrame = CFrame.new(at(0, 23, zg - 4)), Color = DARKSTONE })
	for _, s in ipairs({ -1, 1 }) do
		-- buttress towers with spires
		part(m, { Name = "Tower", Size = Vector3.new(9, 58, 9), CFrame = CFrame.new(at(s * 24, 29, zg - 3)), Color = DARKSTONE })
		part(m, { Name = "TowerCap", Size = Vector3.new(10.4, 1.4, 10.4), CFrame = CFrame.new(at(s * 24, 58.7, zg - 3)), Color = STONE_DARK })
		local spire = part(m, { Name = "Spire", Size = Vector3.new(8, 22, 8), CFrame = CFrame.new(at(s * 24, 70.4, zg - 3)), Color = Color3.fromRGB(40, 42, 58) })
		local sm = Instance.new("SpecialMesh")
		sm.MeshType = Enum.MeshType.FileMesh
		sm.MeshId = "rbxassetid://1033714" -- (a cone)
		sm.Scale = Vector3.new(8, 22, 8)
		sm.Parent = spire
		deco(m, { Name = "SpireOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(at(s * 24, 82, zg - 3)), Color = CRYSTAL, Material = Enum.Material.Neon })
		-- tall lancet windows glowing blue
		for _, y in ipairs({ 16, 34 }) do
			deco(m, { Name = "Lancet", Size = Vector3.new(2.6, 9, 0.3), CFrame = CFrame.new(at(s * 24, y, zg + 1.6)), Color = Color3.fromRGB(70, 110, 230), Material = Enum.Material.Neon, Transparency = 0.25 })
		end
		-- navy banners on the towers
		banner(m, at(s * 24, 28, zg + 1.8), Vector3.new(0, 0, 1), 4, 12, NAVY)
		-- pinnacles along the facade
		for _, x in ipairs({ 9, 15 }) do
			local pin = part(m, { Name = "Pinnacle", Size = Vector3.new(2.6, 10, 2.6), CFrame = CFrame.new(at(s * x, 50, zg - 2)), Color = DARKSTONE })
			local pm = Instance.new("SpecialMesh")
			pm.MeshType = Enum.MeshType.FileMesh
			pm.MeshId = "rbxassetid://1033714"
			pm.Scale = Vector3.new(2.6, 10, 2.6)
			pm.Parent = pin
		end
		-- the steps' crystal lamps and lanterns
		crystalLamp(m, C + Vector3.new(s * 17, 0, -PLAZA_R + 4), 1.2)
		lantern(m, at(s * 12, 0, zg + 8), 1.4)
		uplight(m, at(s * 14, 0.2, zg + 6), Vector3.new(0, 1, -0.25), Color3.fromRGB(150, 170, 255), 46, 3)
	end
	-- the gable and its cross-star
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "Gable", Size = Vector3.new(24, 2.4, 6.4), CFrame = CFrame.new(at(s * 9.5, 52, zg - 4)) * CFrame.Angles(0, 0, math.rad(-38 * s)), Color = STONE_DARK })
	end
	-- the rose window over the door: a star of light in a stone ring
	local rose = at(0, 38, zg - 0.8)
	deco(m, { Name = "RoseGlass", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 10, 10), CFrame = CFrame.new(rose) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(60, 90, 220), Material = Enum.Material.Neon, Transparency = 0.2 })
	for i = 1, 24 do
		local a = (i / 24) * math.pi * 2
		local p = rose + Vector3.new(math.cos(a) * 5.4, math.sin(a) * 5.4, 0.3)
		part(m, { Name = "RoseFrame", Size = Vector3.new(1, 1.6, 1), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, a), Color = STONE })
	end
	for i = 0, 3 do
		deco(m, { Name = "RoseStar", Size = Vector3.new(0.5, 8.4, 0.2), CFrame = CFrame.new(rose + Vector3.new(0, 0, 0.5)) * CFrame.Angles(0, 0, i * math.pi / 4),
			Color = CRYSTAL_HOT, Material = Enum.Material.Neon })
	end
	-- the pointed arch round the doorway
	local archC = at(0, 16, zg)
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "DoorJamb", Size = Vector3.new(3, 16, 5), CFrame = CFrame.new(at(s * 11.5, 8, zg)), Color = STONE })
		for i = 0, 9 do
			local a = (i / 9) * math.rad(62)
			local p = archC + Vector3.new(s * (11.5 - (1 - math.cos(a)) * 13), math.sin(a) * 13, 0)
			part(m, { Name = "ArchStone", Size = Vector3.new(3, 2.4, 5), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, -s * a), Color = STONE })
		end
	end
	-- the DUNGEON sign over the arch
	local sign = part(m, { Name = "GateSign", Size = Vector3.new(16, 3, 0.5), CFrame = CFrame.new(at(0, 29.5, zg + 2.6)) * CFrame.Angles(0, math.pi, 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(sign, Vector2.new(640, 120), function(sg)
		textLabel(sg, "DUNGEON", { Size = UDim2.fromScale(1, 0.85), Position = UDim2.fromScale(0, 0.08) })
	end)
	-- the portal: the doorway filled with deep blue, the great glowing ring in it
	local portalRect = deco(m, { Name = "Portal", Size = Vector3.new(20, 26, 0.4), CFrame = CFrame.new(at(0, 13, zg)),
		Color = Color3.fromRGB(30, 50, 160), Material = Enum.Material.Neon, Transparency = 0.35 })
	local ringC = at(0, 13, zg + 0.4)
	for _, r in ipairs({ { 9, 0.8, CRYSTAL }, { 7.4, 0.35, CRYSTAL_HOT }, { 5, 0.25, Color3.fromRGB(140, 120, 255) } }) do
		local n = 44
		for i = 1, n do
			local a = i / n * math.pi * 2
			local p = ringC + Vector3.new(math.cos(a) * r[1], math.sin(a) * r[1], 0)
			deco(m, { Name = "PortalRing", Size = Vector3.new(r[2], r[1] * 2 * math.pi / n + 0.05, 0.15), CFrame = CFrame.new(p) * CFrame.Angles(0, 0, a),
				Color = r[3], Material = Enum.Material.Neon, Transparency = 0.1, CastShadow = false })
		end
	end
	deco(m, { Name = "PortalSwirl", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 14, 14), CFrame = CFrame.new(ringC) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(110, 140, 255), Material = Enum.Material.Neon, Transparency = 0.75 }):AddTag("LobbyPortalSwirl")
	local glow = Instance.new("PointLight")
	glow.Color = CRYSTAL
	glow.Range = 56
	glow.Brightness = 2.4
	glow.Parent = portalRect
	local spill = Instance.new("SpotLight")
	spill.Face = Enum.NormalId.Back
	spill.Angle = 80
	spill.Color = Color3.fromRGB(130, 160, 255)
	spill.Range = 50
	spill.Brightness = 2.4
	spill.Parent = portalRect
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	swirl.Color = ColorSequence.new(CRYSTAL_HOT, CRYSTAL)
	swirl.LightEmission = 1
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 0) })
	swirl.Lifetime = NumberRange.new(1.2, 2.4)
	swirl.Speed = NumberRange.new(1, 4)
	swirl.SpreadAngle = Vector2.new(180, 180)
	swirl.Rate = 50
	swirl.Parent = portalRect
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Choose a dungeon"
	prompt.ObjectText = "Dungeon Gate"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 24
	prompt.RequiresLineOfSight = false
	prompt.Parent = portalRect
	prompt.Triggered:Connect(onUse)
	-- (the string lights tie onto the steps' lanterns)
	return { at(-12, 2.4, zg + 8), at(12, 2.4, zg + 8) }
end

-- An angelic statue: a robed figure, wings spread, hands folded on a sword
-- planted before it, on a tall pedestal, facing `face`.
local function angel(m: Model, pos: Vector3, face: Vector3)
	local cf = CFrame.lookAt(pos, pos + face)
	local stone = Color3.fromRGB(196, 192, 186)
	local function at(x: number, y: number, z: number): CFrame return cf * CFrame.new(x, y, z) end
	part(m, { Name = "Pedestal", Size = Vector3.new(9, 6, 9), CFrame = at(0, 3, 0), Color = STONE })
	part(m, { Name = "PedestalCap", Size = Vector3.new(10, 1, 10), CFrame = at(0, 6.5, 0), Color = STONE_DARK })
	local s = { Color = stone, Material = Enum.Material.Marble }
	local function piece(name: string, size: Vector3, c: CFrame, class: string?)
		local props = table.clone(s)
		props.Name = name
		props.Size = size
		props.CFrame = c
		return part(m, props, class)
	end
	-- the robe (wide at the hem), the body, the head and hood
	piece("Robe", Vector3.new(5.6, 9, 4), at(0, 11.5, 0))
	piece("RobeHem", Vector3.new(6.6, 2, 4.8), at(0, 8, 0))
	piece("Torso", Vector3.new(4.6, 5, 3), at(0, 18.5, 0))
	piece("Head", Vector3.new(2.4, 2.8, 2.4), at(0, 22.6, 0))
	local halo = deco(m, { Name = "Halo", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 4, 4), CFrame = at(0, 23.4, 1.6) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(255, 220, 140), Material = Enum.Material.Neon, Transparency = 0.35, CastShadow = false })
	halo.Name = "Halo"
	-- the arms down to the hands, folded on the pommel
	for _, sd in ipairs({ -1, 1 }) do
		piece("Arm", Vector3.new(1.4, 5, 1.4), at(sd * 1.6, 17.4, -1.6) * CFrame.Angles(math.rad(35), 0, math.rad(sd * -18)))
	end
	-- the sword, point down before it
	piece("Blade", Vector3.new(0.9, 11, 0.3), at(0, 10.6, -3.2))
	piece("Guard", Vector3.new(4, 0.6, 0.6), at(0, 16.4, -3.2))
	piece("Pommel", Vector3.new(0.9, 1.6, 0.9), at(0, 17.6, -3.2))
	-- the wings: feathered layers sweeping up and out behind
	for _, sd in ipairs({ -1, 1 }) do
		for k = 0, 5 do
			local len = 11 - k * 1.2
			local ang = math.rad(sd * (18 + k * 11))
			piece("Feathers", Vector3.new(1.6, len, 0.5), at(sd * (2.4 + k * 1.1), 18 + k * 1.8, 2.2 + k * 0.2) * CFrame.Angles(0, sd * math.rad(-25), ang))
		end
	end
	-- a blue crystal brazier at its feet
	crystalLamp(m, (at(0, 7, -5.4)).Position, 0.9)
end

-- A station: a builder for its shop, its floating label and its prompt.
local function stationBase(m: Model, pos: Vector3, facePos: Vector3, w: number, d: number): (CFrame, (number, number, number) -> CFrame)
	local face = CFrame.lookAt(pos, Vector3.new(facePos.X, pos.Y, facePos.Z))
	local function at(x: number, y: number, z: number): CFrame return face * CFrame.new(x, y, z) end
	part(m, { Name = "StationFloor", Size = Vector3.new(w, 0.8, d), CFrame = at(0, 0.4, 0), Color = Color3.fromRGB(84, 62, 44), Material = Enum.Material.WoodPlanks })
	return face, at
end

-- The ARMORY: a timber forge shop, weapon racks, an anvil and its fire.
local function buildArmory(m: Model, pos: Vector3, C: Vector3)
	local face, at = stationBase(m, pos, C, 20, 14)
	for _, x in ipairs({ -9.4, 9.4 }) do
		for _, z in ipairs({ -6.4, 6.4 }) do
			part(m, { Name = "Beam", Size = Vector3.new(1, 13, 1), CFrame = at(x, 6.5, z), Color = WOOD_DARK, Material = Enum.Material.Wood })
		end
	end
	part(m, { Name = "BackWall", Size = Vector3.new(19, 11, 0.6), CFrame = at(0, 6, 6.6), Color = Color3.fromRGB(120, 100, 82), Material = Enum.Material.Brick })
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "Roof", Size = Vector3.new(22, 0.6, 9), CFrame = at(0, 14.6, s * 3.6) * CFrame.Angles(math.rad(-26 * s), 0, 0),
			Color = Color3.fromRGB(70, 46, 34), Material = Enum.Material.WoodPlanks })
	end
	-- weapon racks on the back wall: swords and axes
	for i = -3, 3 do
		deco(m, { Name = "RackBlade", Size = Vector3.new(0.4, 5, 0.15), CFrame = at(i * 2.3, 6.5, 6.1) * CFrame.Angles(0, 0, math.rad(i * 4)),
			Color = Color3.fromRGB(200, 205, 215), Material = Enum.Material.Metal })
		deco(m, { Name = "RackGuard", Size = Vector3.new(1.4, 0.3, 0.3), CFrame = at(i * 2.3, 4.2, 6.1), Color = GOLD, Material = Enum.Material.Metal })
	end
	-- a suit of armor on a stand
	for _, x in ipairs({ -6.5 }) do
		part(m, { Name = "ArmorStand", Size = Vector3.new(0.4, 6, 0.4), CFrame = at(x, 3.4, 3), Color = WOOD_DARK, Material = Enum.Material.Wood })
		deco(m, { Name = "Breastplate", Size = Vector3.new(2.6, 2.8, 1.6), CFrame = at(x, 5.8, 3), Color = Color3.fromRGB(170, 175, 185), Material = Enum.Material.Metal })
		deco(m, { Name = "Helm", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = at(x, 7.9, 3), Color = Color3.fromRGB(170, 175, 185), Material = Enum.Material.Metal })
	end
	-- the anvil and the forge's glow
	part(m, { Name = "AnvilBase", Size = Vector3.new(1.6, 2, 1.6), CFrame = at(3, 1.8, -1), Color = Color3.fromRGB(40, 38, 40), Material = Enum.Material.Metal })
	part(m, { Name = "Anvil", Size = Vector3.new(3.4, 1, 1.6), CFrame = at(3, 3.3, -1), Color = Color3.fromRGB(46, 44, 48), Material = Enum.Material.Metal })
	part(m, { Name = "Forge", Size = Vector3.new(4.4, 3.6, 3.4), CFrame = at(6.8, 2.2, 3.6), Color = Color3.fromRGB(90, 72, 66), Material = Enum.Material.Brick })
	local coals = deco(m, { Name = "Coals", Size = Vector3.new(3.2, 0.4, 2.4), CFrame = at(6.8, 4.1, 3.6), Color = Color3.fromRGB(255, 120, 40), Material = Enum.Material.Neon })
	local fl = Instance.new("PointLight")
	fl.Color = Color3.fromRGB(255, 140, 70)
	fl.Range = 18
	fl.Brightness = 1.6
	fl.Parent = coals
	flicker(fl, 1.6)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 120), Color3.fromRGB(255, 90, 30))
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Speed = NumberRange.new(3, 6)
	sparks.EmissionDirection = Enum.NormalId.Top
	sparks.SpreadAngle = Vector2.new(30, 30)
	sparks.Rate = 8
	sparks.Parent = coals
	-- red banners and a sign
	for _, x in ipairs({ -9.4, 9.4 }) do
		banner(m, at(x, 12, -7).Position, face.LookVector, 1.8, 5.2)
		lantern(m, at(x * 1.15, 0, -8).Position, 1.2)
	end
	local sign = part(m, { Name = "ArmorySign", Size = Vector3.new(9, 2.4, 0.4), CFrame = at(0, 12.4, -7) * CFrame.Angles(0, math.pi, 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(sign, Vector2.new(450, 120), function(sg)
		textLabel(sg, "ARMORY", { Size = UDim2.fromScale(1, 0.82), Position = UDim2.fromScale(0, 0.09) })
	end)
	local counter = part(m, { Name = "ArmoryCounter", Size = Vector3.new(10, 3, 2.4), CFrame = at(-2, 1.9, -4.6), Color = WOOD, Material = Enum.Material.WoodPlanks })
	stationLabel(counter, "ARMORY", "A", 16)
	screenPrompt(counter, "Browse gear", "Armory", "armory", 14)
end

-- The WARDROBE: a red-canopied booth, mannequins in outfits, racks of cloth.
local function buildWardrobe(m: Model, pos: Vector3, C: Vector3)
	local face, at = stationBase(m, pos, C, 18, 12)
	for _, x in ipairs({ -8.4, 8.4 }) do
		for _, z in ipairs({ -5.4, 5.4 }) do
			part(m, { Name = "Pole", Size = Vector3.new(0.7, 11, 0.7), CFrame = at(x, 5.5, z), Color = WOOD, Material = Enum.Material.Wood })
		end
	end
	for i = 0, 7 do
		local x = -8.4 + 16.8 * (i + 0.5) / 8
		deco(m, { Name = "Canopy", Size = Vector3.new(2.1, 0.25, 12.6), CFrame = at(x, 11.4 - math.abs(x) * 0.12, 0),
			Color = if i % 2 == 0 then Color3.fromRGB(150, 30, 40) else Color3.fromRGB(110, 20, 30), Material = Enum.Material.Fabric })
	end
	deco(m, { Name = "Valance", Size = Vector3.new(17.4, 1.2, 0.2), CFrame = at(0, 10.6, -6.3), Color = Color3.fromRGB(150, 30, 40), Material = Enum.Material.Fabric })
	deco(m, { Name = "ValanceTrim", Size = Vector3.new(17.4, 0.2, 0.25), CFrame = at(0, 10, -6.32), Color = GOLD, Material = Enum.Material.Metal })
	-- mannequins in coloured robes
	local robes = { Color3.fromRGB(40, 60, 140), Color3.fromRGB(120, 30, 40), Color3.fromRGB(60, 110, 70) }
	for i, x in ipairs({ -5, 0, 5 }) do
		part(m, { Name = "MannequinBase", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2), CFrame = at(x, 1, 2) * FLAT, Color = WOOD_DARK, Material = Enum.Material.Wood })
		deco(m, { Name = "Robe", Size = Vector3.new(2.4, 4.4, 1.4), CFrame = at(x, 3.6, 2), Color = robes[i], Material = Enum.Material.Fabric })
		deco(m, { Name = "Shoulders", Size = Vector3.new(3, 1, 1.4), CFrame = at(x, 6.1, 2), Color = robes[i], Material = Enum.Material.Fabric })
		deco(m, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, CFrame = at(x, 7.3, 2), Color = Color3.fromRGB(220, 200, 170), Material = Enum.Material.SmoothPlastic })
	end
	-- a rack of hanging cloth
	part(m, { Name = "RackBar", Size = Vector3.new(14, 0.3, 0.3), CFrame = at(0, 7.4, 5), Color = WOOD_DARK, Material = Enum.Material.Wood })
	for i = -6, 6 do
		deco(m, { Name = "Cloth", Size = Vector3.new(0.9, 4, 0.15), CFrame = at(i * 1.05, 5.3, 5),
			Color = Color3.fromHSV(((i + 6) / 13) % 1, 0.55, 0.65), Material = Enum.Material.Fabric })
	end
	for _, x in ipairs({ -8.4, 8.4 }) do
		lantern(m, at(x * 1.15, 0, -7).Position, 1.2)
		crystalLamp(m, at(x * 0.6, 0, -7.6).Position, 0.8)
	end
	local stand = part(m, { Name = "WardrobeMirror", Size = Vector3.new(3.4, 6, 0.4), CFrame = at(-7, 3.8, -2) * CFrame.Angles(0, math.rad(30), 0),
		Color = Color3.fromRGB(200, 210, 230), Material = Enum.Material.Glass, Reflectance = 0.4 })
	stationLabel(stand, "WARDROBE", "W", 12)
	screenPrompt(stand, "Change outfit", "Wardrobe", "wardrobe", 14)
end

-- The SUMMONING tent (the gacha): deep red, a crystal ball on its table, a
-- magic circle at its door.
local function buildSummoning(m: Model, pos: Vector3, C: Vector3, onUse: (Player) -> ())
	local face, at = stationBase(m, pos, C, 20, 14)
	local back = part(m, { Name = "TentBack", Size = Vector3.new(19, 13, 0.6), CFrame = at(0, 6.9, 6.6), Color = Color3.fromRGB(46, 20, 60), Material = Enum.Material.Neon, Transparency = 0.15 })
	local stars = Instance.new("ParticleEmitter")
	stars.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	stars.Color = ColorSequence.new(Color3.fromRGB(240, 200, 255))
	stars.LightEmission = 1
	stars.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.5, 0.45), NumberSequenceKeypoint.new(1, 0) })
	stars.Lifetime = NumberRange.new(2, 4)
	stars.Speed = NumberRange.new(0.1, 0.4)
	stars.Rate = 14
	stars.EmissionDirection = Enum.NormalId.Back
	stars.Parent = back
	for _, x in ipairs({ -9.2, 9.2 }) do
		part(m, { Name = "TentPole", Size = Vector3.new(0.8, 13, 0.8), CFrame = at(x, 6.5, -6), Color = WOOD, Material = Enum.Material.Wood })
		part(m, { Name = "TentSide", Size = Vector3.new(0.3, 12, 13), CFrame = at(x, 6.7, 0.2), Color = Color3.fromRGB(130, 24, 36), Material = Enum.Material.Fabric })
		banner(m, at(x, 11.6, -6.6).Position, face.LookVector, 1.8, 5.2, Color3.fromRGB(110, 20, 40))
		lantern(m, at(x * 1.15, 0, -8).Position, 1.2)
	end
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "TentRoof", Size = Vector3.new(12, 0.4, 15), CFrame = at(s * 5, 15.2, 0) * CFrame.Angles(0, 0, math.rad(-30 * s)),
			Color = Color3.fromRGB(140, 24, 40), Material = Enum.Material.Fabric })
		deco(m, { Name = "RoofTrim", Size = Vector3.new(12, 0.25, 0.3), CFrame = at(s * 5, 15, -7.5) * CFrame.Angles(0, 0, math.rad(-30 * s)), Color = GOLD, Material = Enum.Material.Metal })
	end
	-- the round table and the crystal ball
	part(m, { Name = "Table", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 6, 6), CFrame = at(0, 3, 1) * FLAT, Color = Color3.fromRGB(60, 30, 50), Material = Enum.Material.Wood })
	part(m, { Name = "TableLeg", Size = Vector3.new(1, 2.6, 1), CFrame = at(0, 1.5, 1), Color = WOOD_DARK, Material = Enum.Material.Wood })
	local ball = deco(m, { Name = "CrystalBall", Shape = Enum.PartType.Ball, Size = Vector3.one * 3, CFrame = at(0, 4.9, 1),
		Color = Color3.fromRGB(220, 120, 255), Material = Enum.Material.Neon, Transparency = 0.25 })
	local bl = Instance.new("PointLight")
	bl.Color = Color3.fromRGB(220, 120, 255)
	bl.Range = 26
	bl.Brightness = 2
	bl.Parent = ball
	-- the magic circle at its door
	local mc = at(0, 0, -11).Position
	mc = Vector3.new(mc.X, C.Y + 0.05, mc.Z)
	floorRing(m, mc, 5.5, 0.3, 32, Color3.fromRGB(240, 90, 200))
	floorRing(m, mc, 4, 0.2, 24, Color3.fromRGB(240, 120, 220))
	for i = 0, 5 do
		local a = i * math.pi / 3
		floorPoint(m, mc, Vector3.new(math.cos(a), 0, math.sin(a)), 3.8, 0.6, Color3.fromRGB(240, 120, 220), Enum.Material.Neon)
	end
	local sign = part(m, { Name = "SummonSign", Size = Vector3.new(12, 2.6, 0.5), CFrame = at(0, 13.2, -7) * CFrame.Angles(0, math.pi, 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(sign, Vector2.new(600, 130), function(sg)
		textLabel(sg, "SUMMONING", { Size = UDim2.fromScale(1, 0.82), Position = UDim2.fromScale(0, 0.09) })
	end)
	stationLabel(ball, "SUMMONING", "S", 14)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Summon"
	prompt.ObjectText = "Summoning"
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt.MaxActivationDistance = 16
	prompt.RequiresLineOfSight = false
	prompt.Parent = ball
	prompt.Triggered:Connect(onUse)
end

-- The BUILD CODEX: a little library, shelves of books, a lectern with the
-- open codex glowing.
local function buildCodex(m: Model, pos: Vector3, C: Vector3)
	local face, at = stationBase(m, pos, C, 18, 14)
	for _, x in ipairs({ -8.4, 8.4 }) do
		part(m, { Name = "Wall", Size = Vector3.new(0.8, 11, 13), CFrame = at(x, 6, 0.4), Color = Color3.fromRGB(110, 92, 80), Material = Enum.Material.Brick })
		lantern(m, at(x * 1.15, 0, -8).Position, 1.2)
	end
	part(m, { Name = "BackWall", Size = Vector3.new(17, 11, 0.8), CFrame = at(0, 6, 6.6), Color = Color3.fromRGB(110, 92, 80), Material = Enum.Material.Brick })
	for _, s in ipairs({ -1, 1 }) do
		part(m, { Name = "Roof", Size = Vector3.new(11, 0.6, 16), CFrame = at(s * 4.6, 13.4, 0) * CFrame.Angles(0, 0, math.rad(-28 * s)),
			Color = Color3.fromRGB(46, 50, 70), Material = Enum.Material.Slate })
	end
	-- bookshelves full of books
	for _, x in ipairs({ -5, 0, 5 }) do
		part(m, { Name = "Shelf", Size = Vector3.new(4.4, 9, 1.4), CFrame = at(x, 5.3, 5.6), Color = WOOD_DARK, Material = Enum.Material.Wood })
		for row = 0, 3 do
			for b = 0, 6 do
				deco(m, { Name = "Book", Size = Vector3.new(0.45, 1.6, 1), CFrame = at(x - 1.6 + b * 0.53, 2 + row * 2.1, 5.1),
					Color = Color3.fromHSV(((b * 7 + row * 3 + x) % 12) / 12, 0.55, 0.55), Material = Enum.Material.SmoothPlastic })
			end
		end
	end
	-- the lectern and the codex, glowing
	part(m, { Name = "Lectern", Size = Vector3.new(1.4, 3.6, 1.4), CFrame = at(0, 2.6, -1), Color = WOOD_DARK, Material = Enum.Material.Wood })
	local book = part(m, { Name = "Codex", Size = Vector3.new(3, 0.4, 2.2), CFrame = at(0, 4.6, -1) * CFrame.Angles(math.rad(-20), 0, 0),
		Color = Color3.fromRGB(230, 214, 170), Material = Enum.Material.SmoothPlastic })
	local gl = Instance.new("PointLight")
	gl.Color = Color3.fromRGB(255, 220, 150)
	gl.Range = 14
	gl.Brightness = 1.4
	gl.Parent = book
	local runes = Instance.new("ParticleEmitter")
	runes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	runes.Color = ColorSequence.new(Color3.fromRGB(255, 230, 160))
	runes.LightEmission = 1
	runes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	runes.Lifetime = NumberRange.new(1, 2)
	runes.Speed = NumberRange.new(0.6, 1.4)
	runes.EmissionDirection = Enum.NormalId.Top
	runes.Rate = 8
	runes.Parent = book
	local sign = part(m, { Name = "CodexSign", Size = Vector3.new(11, 2.4, 0.4), CFrame = at(0, 12, -7) * CFrame.Angles(0, math.pi, 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	boardText(sign, Vector2.new(560, 120), function(sg)
		textLabel(sg, "BUILD CODEX", { Size = UDim2.fromScale(1, 0.82), Position = UDim2.fromScale(0, 0.09) })
	end)
	stationLabel(book, "BUILD CODEX", "C", 12)
	screenPrompt(book, "Read the codex", "Build Codex", "codex", 14)
end

-- The guild podium: three tiers (2nd, 1st, 3rd), a marble back with the
-- season's crest, a Guild board beside it. The top contributors' figures
-- are stood on it by LobbyPodium (server) from GuildManager.Top3.
local function buildPodium(m: Model, pos: Vector3, C: Vector3): Model
	local face = CFrame.lookAt(pos, Vector3.new(C.X, pos.Y, C.Z))
	local function at(x: number, y: number, z: number): CFrame return face * CFrame.new(x, y, z) end
	local podium = Instance.new("Model")
	podium.Name = "GuildPodium"
	podium.Parent = m
	local tiers = { { x = 0, h = 4.5, rank = 1, color = Color3.fromRGB(230, 190, 90) }, { x = -6.4, h = 3, rank = 2, color = Color3.fromRGB(200, 205, 215) },
		{ x = 6.4, h = 2, rank = 3, color = Color3.fromRGB(200, 130, 80) } }
	for _, t in ipairs(tiers) do
		local block = part(podium, { Name = `Tier{t.rank}`, Size = Vector3.new(6, t.h, 6), CFrame = at(t.x, t.h / 2, 0), Color = MARBLE, Material = Enum.Material.Marble })
		deco(podium, { Name = "TierBand", Size = Vector3.new(6.1, 0.6, 6.1), CFrame = at(t.x, t.h - 0.3, 0), Color = t.color, Material = Enum.Material.Metal })
		boardText(block, Vector2.new(200, 200), function(sg)
			textLabel(sg, tostring(t.rank), { Size = UDim2.fromScale(0.6, 0.6), Position = UDim2.fromScale(0.2, 0.2), TextColor3 = t.color })
		end)
		-- where the figure stands (LobbyPodium reads these)
		local spot = deco(podium, { Name = `Spot{t.rank}`, Size = Vector3.new(1, 0.2, 1), CFrame = at(t.x, t.h + 0.1, 0) * CFrame.Angles(0, math.pi, 0),
			Transparency = 1 })
		spot:SetAttribute("Rank", t.rank)
	end
	-- the backdrop: a marble screen with the crest and GUILD CHAMPIONS
	part(podium, { Name = "PodiumBack", Size = Vector3.new(22, 12, 1.2), CFrame = at(0, 6, 4.4), Color = MARBLE, Material = Enum.Material.Marble })
	local crest = part(podium, { Name = "PodiumCrest", Size = Vector3.new(16, 3, 0.4), CFrame = at(0, 10.4, 3.7) * CFrame.Angles(0, math.pi, 0), Color = NAVY, Material = Enum.Material.Fabric })
	boardText(crest, Vector2.new(640, 120), function(sg)
		textLabel(sg, "GUILD CHAMPIONS", { Size = UDim2.fromScale(1, 0.8), Position = UDim2.fromScale(0, 0.1) })
	end)
	for _, s in ipairs({ -1, 1 }) do
		banner(podium, at(s * 12, 12, 3.8).Position, face.LookVector, 2.2, 7, NAVY)
		crystalLamp(podium, at(s * 12.5, 0, -3).Position, 1)
	end
	-- the Guild board
	local board = part(podium, { Name = "GuildBoard", Size = Vector3.new(7, 5, 0.5), CFrame = at(15, 4, -2) * CFrame.Angles(0, math.rad(-25), 0), Color = WOOD_DARK, Material = Enum.Material.Wood })
	for _, x in ipairs({ -3, 3 }) do
		part(podium, { Name = "BoardPost", Size = Vector3.new(0.5, 6, 0.5), CFrame = at(15, 3, -2) * CFrame.Angles(0, math.rad(-25), 0) * CFrame.new(x, 0, 0.3),
			Color = WOOD, Material = Enum.Material.Wood })
	end
	boardText(board, Vector2.new(350, 250), function(sg)
		textLabel(sg, "GUILDS", { Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.1) })
		textLabel(sg, "found · join · rankings", { Size = UDim2.new(1, 0, 0.22, 0), Position = UDim2.fromScale(0, 0.58), TextColor3 = Color3.fromRGB(200, 180, 140) })
	end)
	stationLabel(board, "GUILDS", "G", 7)
	screenPrompt(board, "Open guilds", "Guild Board", "guild", 14)
	return podium
end

-- Waterfalls off the island's edge, small floating islands round it (crystals,
-- trees, their own falls), bushes and rocks round the plaza.
local function waterfall(m: Model, top: Vector3, width: number, height: number)
	local fall = deco(m, { Name = "Waterfall", Size = Vector3.new(0.6, height, width), CFrame = CFrame.new(top - Vector3.new(0, height / 2, 0)),
		Color = Color3.fromRGB(150, 200, 255), Material = Enum.Material.Neon, Transparency = 0.45, CastShadow = false })
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(230, 240, 255))
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 4), NumberSequenceKeypoint.new(1, 12) })
	mist.Lifetime = NumberRange.new(2, 3.5)
	mist.Speed = NumberRange.new(2, 5)
	mist.Rate = 8
	mist.Parent = fall
	return fall
end

local function buildEdges(m: Model, C: Vector3, rng: Random)
	-- falls off the main island, facing out
	for _, spec in ipairs({ { 96, -4, 20, 12 }, { -96, -4, 30, 10 }, { 60, -4, 76, 9 }, { -64, -4, 72, 9 } }) do
		local p = C + Vector3.new(spec[1], spec[2], spec[3])
		local out = Vector3.new(spec[1], 0, spec[3]).Unit
		local f = waterfall(m, p, spec[4], 150)
		f.CFrame = CFrame.lookAt(f.Position, f.Position + out) * CFrame.Angles(0, math.rad(90), 0)
		deco(m, { Name = "Stream", Size = Vector3.new(spec[4], 0.3, 18), CFrame = CFrame.lookAt(p - out * 8 + Vector3.new(0, 1.2, 0), p + Vector3.new(0, 1.2, 0)),
			Color = Color3.fromRGB(120, 180, 240), Material = Enum.Material.Glass, Transparency = 0.3 })
	end
	-- small floating islands
	for _, spec in ipairs({ { -150, 30, -60, 34 }, { 160, 20, -40, 30 }, { -130, -10, 90, 26 }, { 140, 40, 110, 22 }, { 0, 55, -190, 40 } }) do
		local c = C + Vector3.new(spec[1], spec[2], spec[3])
		local r = spec[4]
		deco(m, { Name = "IsleTop", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, r, r), CFrame = CFrame.new(c) * FLAT, Color = GRASS, Material = Enum.Material.Grass })
		deco(m, { Name = "IsleRock", Size = Vector3.new(r * 0.8, r * 1.1, r * 0.8), CFrame = CFrame.new(c - Vector3.new(0, r * 0.6, 0)) * CFrame.Angles(math.pi, rng:NextNumber(0, 6), 0),
			Color = Color3.fromRGB(90, 80, 84), Material = Enum.Material.Rock }, "CornerWedgePart")
		for _ = 1, 3 do
			local p = c + Vector3.new(rng:NextNumber(-r * 0.3, r * 0.3), 2, rng:NextNumber(-r * 0.3, r * 0.3))
			deco(m, { Name = "IsleTree", Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(5, 9), CFrame = CFrame.new(p + Vector3.new(0, 4, 0)),
				Color = Color3.fromRGB(rng:NextInteger(54, 84), rng:NextInteger(92, 128), rng:NextInteger(40, 58)), Material = Enum.Material.Grass })
		end
		deco(m, { Name = "IsleCrystal", Size = Vector3.new(2, 6, 2), CFrame = CFrame.new(c + Vector3.new(r * 0.32, 4.5, 0)) * CFrame.Angles(0, 0, math.rad(15)),
			Color = CRYSTAL, Material = Enum.Material.Neon, Transparency = 0.15 })
		waterfall(m, c + Vector3.new(r * 0.45, 0, 0), 4, 60)
	end
	-- bushes, flowers and rocks round the plaza (not on the stairs or the steps)
	local blooms = { Color3.fromRGB(240, 240, 250), Color3.fromRGB(230, 150, 200), Color3.fromRGB(180, 140, 230), Color3.fromRGB(250, 220, 120) }
	for _ = 1, 80 do
		local a = rng:NextNumber(0, math.pi * 2)
		local deg = math.deg(a)
		if math.abs(deg - 90) < 16 or math.abs(deg - 270) < 22 then continue end
		local r = rng:NextNumber(PLAZA_R + 2, 92)
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
	-- crystal clusters at the island's rim
	for i = 1, 8 do
		local a = (i / 8) * math.pi * 2 + 0.3
		local p = C + Vector3.new(math.cos(a) * 88, -3, math.sin(a) * 88)
		for k = 1, 3 do
			deco(m, { Name = "RimCrystal", Size = Vector3.new(1.4, 3 + k * 1.4, 1.4), CFrame = CFrame.new(p + Vector3.new(k - 2, 1.5 + k * 0.7, rng:NextNumber(-1, 1)))
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.4, 0.4)), Color = CRYSTAL, Material = Enum.Material.Neon, Transparency = 0.2 })
		end
	end
end

function LobbyBuilder.Build(parent: Instance, C: Vector3, maps: { any }, prompts: Prompts): (Model, CFrame)
	local rng = Random.new(20261024)
	local m = Instance.new("Model")
	m.Name = "Lobby"
	-- (always streamed in whole: everyone in it sees all of it)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	buildIsland(m, C, rng)
	buildCircle(m, C)
	local spawnCF = buildFront(m, C)
	local stepLights = buildCathedral(m, C, prompts.dungeon)
	angel(m, C + Vector3.new(-25, -3, -64), Vector3.new(0.3, 0, 1).Unit)
	angel(m, C + Vector3.new(25, -3, -64), Vector3.new(-0.3, 0, 1).Unit)
	buildWardrobe(m, C + Vector3.new(-36, 0, -28), C)
	buildSummoning(m, C + Vector3.new(36, 0, -28), C, prompts.gacha)
	buildArmory(m, C + Vector3.new(-44, 0, 10), C)
	buildCodex(m, C + Vector3.new(44, 0, 10), C)
	buildPodium(m, C + Vector3.new(-30, 0, 38), C)
	buildQuestBoard(m, C + Vector3.new(30, 0, 40), C, maps, prompts.quests)
	buildEdges(m, C, rng)
	-- Lamp posts at the stairhead, strings of lights from them up to the
	-- cathedral steps, across the stairhead.
	local lights = Instance.new("Model")
	lights.Name = "StringLights"
	lights.Parent = m
	local left = lampPost(lights, C + Vector3.new(-20, 0, PLAZA_R - 12), 13, Vector3.new(1, 0, 0))
	local right = lampPost(lights, C + Vector3.new(20, 0, PLAZA_R - 12), 13, Vector3.new(-1, 0, 0))
	festoon(lights, left, right, 2.2)
	local backL = lampPost(lights, C + Vector3.new(-20, 0, -PLAZA_R + 12), 13, Vector3.new(1, 0, 0))
	local backR = lampPost(lights, C + Vector3.new(20, 0, -PLAZA_R + 12), 13, Vector3.new(-1, 0, 0))
	festoon(lights, left, backL, 4)
	festoon(lights, right, backR, 4)
	festoon(lights, backL, backR, 2.2)
	festoon(lights, backL, stepLights[1], 3)
	festoon(lights, backR, stepLights[2], 3)
	m.Parent = parent or Workspace
	return m, spawnCF
end

return LobbyBuilder
