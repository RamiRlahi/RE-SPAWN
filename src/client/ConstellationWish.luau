--[[
	ConstellationWish.luau
	"Constellation Wishes": the summon. A floating island under a night sky;
	every pull is a wish star hanging in it, and you drag each one down
	yourself.

	  1 NIGHT     the scene fades in (far above the map, so nothing intrudes):
	              a sky of twinkling stars, one bright wish star per pull
	  2 WISH      grab a star and drag it down; let go low enough and it falls
	              onto the island, where its card appears. A star's colour
	              hints its rarity, but never above Epic: grab a Legendary and
	              it bursts gold in your hand (and fights you on the way down)
	  3 SKY       a landing star draws its rarity's constellation across the
	              sky: Common the Wolf, (Uncommon the Dragon), Rare the Kraken,
	              Epic the Leviathan, Legendary the Celestial Dragon (everything
	              goes quiet, line by line, then the sky turns gold), Mythic
	              the Galaxy. Each shows once a wish, all in one place: a rarer
	              one draws itself over the one shown, which fades beneath it
	  4 REVEAL    once every star is down, an Epic or better comes down as a
	              figure in a column of starlight; name, a row of stars, and
	              it waits for a click

	WISH ALL brings the rest down for you; SKIP brings everything down at once.

	ConstellationWish.Play(best, all, onDone) — `best` is the best GachaRewards
	entry, `all` every reward pulled (in order).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local UserInputService = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GachaConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GachaConfig"))
local RewardPreview = require(script.Parent:WaitForChild("RewardPreview"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))

local player = Players.LocalPlayer

local ConstellationWish = {}

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local STARLIGHT = Color3.fromRGB(235, 240, 255)
local ORIGIN = Vector3.new(0, 4200, 0) -- the island, far above the map
local ORDER = GachaConfig.RarityOrder

-- Constellations, one per rarity: drawn as polylines (x right, y up, about
-- -1..1), turned into stars (points) and the lines between them. A wish shows
-- each at most once; a rarer one drawn later outshines the one before it.
type Shape = { points: { Vector2 }, edges: { { number } }, scale: number }
local function shapeOf(lines: { { { number } } }, scale: number): Shape
	local points: { Vector2 } = {}
	local edges: { { number } } = {}
	local function idx(p: { number }): number
		for i, q in ipairs(points) do
			if math.abs(q.X - p[1]) < 1e-3 and math.abs(q.Y - p[2]) < 1e-3 then return i end
		end
		table.insert(points, Vector2.new(p[1], p[2]))
		return #points
	end
	for _, line in ipairs(lines) do
		local prev: number? = nil
		for _, p in ipairs(line) do
			local i = idx(p)
			if prev and prev ~= i then table.insert(edges, { prev, i }) end
			prev = i
		end
	end
	return { points = points, edges = edges, scale = scale }
end

local function spiralArms(): { { { number } } }
	local arms = {}
	for arm = 0, 1 do
		local line = { { 0, 0 } }
		for k = 1, 12 do
			local a = k * 0.52 + arm * math.pi
			local r = 0.05 + k * 0.07
			table.insert(line, { math.cos(a) * r * 1.3, math.sin(a) * r })
		end
		table.insert(arms, line)
	end
	-- the outer haze ring
	local ring = {}
	for k = 0, 14 do
		local a = k / 14 * math.pi * 2
		table.insert(ring, { math.cos(a) * 1.35, math.sin(a) * 1.0 })
	end
	table.insert(arms, ring)
	-- the bright core
	table.insert(arms, { { 0.09, 0 }, { 0, 0.07 }, { -0.09, 0 }, { 0, -0.07 }, { 0.09, 0 } })
	return arms
end

local SHAPES: { [string]: Shape } = {
	Common = shapeOf({ -- The Wolf
		{ { -0.6, 0.9 }, { -0.45, 0.45 }, { -0.2, 0.85 }, { 0, 0.4 }, { 0.45, 0.25 }, { 0.95, 0.05 }, { 0.75, -0.15 },
			{ 0.3, -0.2 }, { 0.1, -0.5 }, { -0.3, -0.8 }, { -0.75, -0.6 }, { -0.9, 0 }, { -0.6, 0.9 } },
		{ { 0, 0.4 }, { 0.15, 0.2 }, { 0.45, 0.25 } },
		{ { 0.75, -0.15 }, { 0.5, -0.35 }, { 0.1, -0.5 } },
	}, 26),
	Uncommon = shapeOf({ -- The Dragon
		{ { 0.95, 0.75 }, { 0.6, 0.7 }, { 0.5, 0.95 } },
		{ { 0.95, 0.75 }, { 0.8, 0.55 }, { 0.55, 0.5 }, { 0.6, 0.7 } },
		{ { 0.55, 0.5 }, { 0.4, 0.45 }, { 0, 0.5 }, { -0.4, 0.35 }, { -0.5, 0 }, { -0.2, -0.2 }, { 0.3, -0.25 },
			{ 0.5, -0.55 }, { 0.2, -0.85 }, { -0.3, -0.8 }, { -0.7, -0.6 } },
		{ { 0, 0.5 }, { 0.05, 0.2 } },
		{ { 0.3, -0.25 }, { 0.45, -0.05 } },
	}, 30),
	Rare = shapeOf({ -- The Kraken
		{ { 0, 1 }, { -0.2, 0.85 }, { -0.28, 0.6 }, { -0.22, 0.38 }, { 0, 0.32 }, { 0.22, 0.38 }, { 0.28, 0.6 }, { 0.2, 0.85 }, { 0, 1 } },
		{ { -0.12, 0.55 }, { -0.07, 0.55 } }, { { 0.07, 0.55 }, { 0.12, 0.55 } },
		{ { -0.22, 0.38 }, { -0.45, 0.3 }, { -0.7, 0.4 }, { -0.9, 0.3 }, { -0.95, 0.1 }, { -0.85, 0 }, { -0.75, 0.08 } },
		{ { -0.15, 0.33 }, { -0.35, 0.05 }, { -0.6, -0.1 }, { -0.75, -0.35 }, { -0.65, -0.5 }, { -0.52, -0.42 } },
		{ { -0.05, 0.32 }, { -0.15, -0.1 }, { -0.25, -0.5 }, { -0.15, -0.8 }, { 0, -0.85 }, { 0.05, -0.72 } },
		{ { 0.05, 0.32 }, { 0.15, -0.05 }, { 0.3, -0.45 }, { 0.45, -0.7 }, { 0.6, -0.65 }, { 0.6, -0.52 } },
		{ { 0.15, 0.33 }, { 0.4, 0.1 }, { 0.65, -0.05 }, { 0.85, -0.25 }, { 0.95, -0.1 }, { 0.88, 0.02 } },
		{ { 0.22, 0.38 }, { 0.45, 0.38 }, { 0.7, 0.55 }, { 0.9, 0.5 }, { 0.95, 0.7 }, { 0.82, 0.78 } },
	}, 36),
	Epic = shapeOf({ -- The Leviathan
		{ { -0.95, 0.75 }, { -0.6, 0.9 }, { -0.4, 0.85 } },
		{ { -0.95, 0.55 }, { -0.6, 0.6 }, { -0.45, 0.65 } },
		{ { -0.4, 0.85 }, { -0.3, 0.7 }, { -0.45, 0.65 } },
		{ { -0.55, 0.88 }, { -0.5, 1.05 }, { -0.4, 0.85 } }, { { -0.4, 0.85 }, { -0.25, 1 }, { -0.3, 0.7 } },
		{ { -0.62, 0.78 }, { -0.56, 0.78 } },
		{ { -0.3, 0.7 }, { -0.25, 0.4 }, { -0.4, 0.1 }, { -0.55, -0.2 }, { -0.4, -0.5 }, { -0.05, -0.6 }, { 0.25, -0.4 },
			{ 0.3, -0.05 }, { 0.15, 0.25 }, { 0.3, 0.5 }, { 0.6, 0.55 }, { 0.8, 0.35 }, { 0.85, 0.05 } },
		{ { 0.85, 0.05 }, { 1, -0.1 } }, { { 0.85, 0.05 }, { 0.7, -0.12 } },
		{ { -0.4, 0.1 }, { -0.2, 0.15 } }, { { -0.05, -0.6 }, { 0, -0.8 } }, { { 0.3, -0.05 }, { 0.45, 0.05 } }, { { 0.6, 0.55 }, { 0.65, 0.75 } },
	}, 46),
	Legendary = shapeOf({ -- The Celestial Dragon
		{ { 0.65, 0.55 }, { 0.85, 0.62 }, { 1, 0.55 }, { 0.9, 0.45 }, { 0.7, 0.42 }, { 0.65, 0.55 } },
		{ { 0.7, 0.58 }, { 0.6, 0.8 } }, { { 0.78, 0.6 }, { 0.74, 0.84 } },
		{ { 0.68, 0.45 }, { 0.5, 0.35 }, { 0.4, 0.15 }, { 0.15, 0.05 }, { -0.15, 0 }, { -0.35, -0.05 } },
		{ { 0.4, 0.15 }, { 0.35, 0 }, { 0.1, -0.15 }, { -0.2, -0.18 }, { -0.35, -0.05 } },
		{ { 0.25, -0.08 }, { 0.3, -0.35 }, { 0.4, -0.45 } }, { { 0.3, -0.35 }, { 0.22, -0.47 } },
		{ { -0.2, -0.18 }, { -0.15, -0.42 }, { -0.05, -0.5 } }, { { -0.15, -0.42 }, { -0.25, -0.52 } },
		{ { -0.35, -0.05 }, { -0.6, 0 }, { -0.85, -0.15 }, { -0.9, -0.4 }, { -0.75, -0.6 }, { -0.5, -0.62 }, { -0.4, -0.5 } },
		{ { 0.25, 0.1 }, { 0.2, 0.55 }, { 0.05, 0.95 }, { -0.15, 0.7 }, { -0.3, 0.95 }, { -0.4, 0.6 }, { -0.65, 0.75 }, { -0.5, 0.35 }, { -0.15, 0.02 } },
		{ { 0.05, 0.95 }, { 0.05, 0.08 } }, { { -0.3, 0.95 }, { -0.2, 0.05 } },
	}, 58),
	Mythic = shapeOf(spiralArms(), 64), -- The Galaxy
}
local SHAPE_NAMES = { Common = "THE WOLF", Uncommon = "THE DRAGON", Rare = "THE KRAKEN", Epic = "THE LEVIATHAN",
	Legendary = "THE CELESTIAL DRAGON", Mythic = "THE GALAXY" }

-- ─── Helpers ────────────────────────────────────────────────────────────────
local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local function seq(...): NumberSequence
	local a = { ... }
	local k = {}
	for i = 1, #a, 2 do table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1])) end
	return NumberSequence.new(k)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.LightInfluence = 0
	pe.LightEmission = 1
	pe.Texture = TEX_SPARKLE
	for k, v in pairs(props) do (pe :: any)[k] = v end
	pe.Parent = parent
	return pe
end

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function sfx(key: string, volume: number, pitch: number?)
	ClassFX.Sound2D(key, volume, pitch)
end

local function rarityIndex(r: string): number
	return table.find(ORDER, r) or 1
end
local function colorOf(r: string): Color3
	return GachaConfig.Rarities[r] and GachaConfig.Rarities[r].color or STARLIGHT
end

-- Lighting is switched to deep night for the wish, then put back exactly.
local function nightLighting(): () -> ()
	local saved = {
		ClockTime = Lighting.ClockTime, Brightness = Lighting.Brightness, Ambient = Lighting.Ambient,
		OutdoorAmbient = Lighting.OutdoorAmbient, FogEnd = Lighting.FogEnd, FogStart = Lighting.FogStart,
		ExposureCompensation = Lighting.ExposureCompensation,
	}
	local atmo = Lighting:FindFirstChildOfClass("Atmosphere")
	local atmoDensity = atmo and atmo.Density
	Lighting.ClockTime = 0
	Lighting.Brightness = 0.2
	Lighting.Ambient = Color3.fromRGB(28, 32, 62)
	Lighting.OutdoorAmbient = Color3.fromRGB(30, 34, 70)
	Lighting.FogStart, Lighting.FogEnd = 0, 100000
	Lighting.ExposureCompensation = 0
	if atmo then atmo.Density = 0 end
	return function()
		for k, v in pairs(saved) do (Lighting :: any)[k] = v end
		if atmo and atmoDensity then atmo.Density = atmoDensity end
	end
end

-- ─── The wish ───────────────────────────────────────────────────────────────
function ConstellationWish.Play(best: any, all: { any }?, onDone: (() -> ())?)
	local camera = Workspace.CurrentCamera
	local pulls = if all and #all > 0 then all else { best }
	local bestIndex = rarityIndex(best.rarity)

	local world = Instance.new("Folder")
	world.Name = "ConstellationWish"
	world.Parent = Workspace.Terrain
	local restoreLighting = nightLighting()
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity, bloom.Size, bloom.Threshold = 0.9, 40, 0.8
	bloom.Parent = Lighting
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Contrast, grade.Saturation, grade.TintColor = 0.1, 0.05, Color3.fromRGB(220, 228, 255)
	grade.Parent = Lighting
	local function bloomKick(i: number)
		bloom.Intensity = i
		tween(bloom, 0.9, { Intensity = 0.9 })
	end

	-- Duck every playing sound for the wish (restored at the end).
	local ducked: { [Sound]: number } = {}
	for _, container in ipairs({ Workspace, SoundService, player:WaitForChild("PlayerGui") }) do
		for _, s in ipairs(container:GetDescendants()) do
			if s:IsA("Sound") and s.Volume > 0 then
				ducked[s] = s.Volume
				tween(s, 0.6, { Volume = 0 })
			end
		end
	end

	-- ── Overlay ──
	local gui = Instance.new("ScreenGui")
	gui.Name = "ConstellationWishGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 0
	black.ZIndex = 10
	black.Parent = gui
	local white = black:Clone()
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.BackgroundTransparency = 1
	white.ZIndex = 11
	white.Parent = gui
	local function text(str: string, size: number, y: number, font: Enum.Font?): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, y)
		t.Size = UDim2.new(1, 0, 0, size + 10)
		t.Font = font or Enum.Font.Antique
		t.TextSize = size
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.TextStrokeColor3 = Color3.new(0, 0, 0)
		t.TextTransparency = 1
		t.Text = str
		t.ZIndex = 12
		t.Parent = gui
		return t
	end
	local hint = text(if #pulls > 1 then "DRAG THE STARS DOWN TO MAKE YOUR WISHES" else "DRAG THE STAR DOWN TO MAKE YOUR WISH", 22, 0.9)
	local nameLabel = text("", 56, 0.74)
	local rarityLabel = text("", 24, 0.82)
	local continueLabel = text("CLICK TO CONTINUE", 16, 0.95, Enum.Font.GothamMedium)
	local function button(str: string, x: number): TextButton
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(1, 0)
		b.Position = UDim2.new(1, x, 0, 24)
		b.Size = UDim2.fromOffset(150, 40)
		b.BackgroundColor3 = Color3.fromRGB(18, 20, 40)
		b.BackgroundTransparency = 0.25
		b.Font = Enum.Font.Antique
		b.TextSize = 18
		b.TextColor3 = STARLIGHT
		b.Text = str
		b.AutoButtonColor = true
		b.ZIndex = 12
		b.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = b
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(150, 160, 230)
		st.Thickness = 1.5
		st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		st.Parent = b
		return b
	end
	local skipBtn = button("SKIP", -24)
	local allBtn = button("WISH ALL", -184)
	allBtn.Visible = #pulls > 1

	-- ── Camera ──
	local camPos = ORIGIN + Vector3.new(0, 5, 24)
	local camLook = ORIGIN + Vector3.new(0, 24, -40)
	local camFov = 70
	local shake = 0
	camera.CameraType = Enum.CameraType.Scriptable
	local camConn = RunService.RenderStepped:Connect(function(dt)
		local j = Vector3.new(math.random() - 0.5, math.random() - 0.5, 0) * shake
		camera.CFrame = CFrame.lookAt(camPos, camLook) * CFrame.new(j)
		camera.FieldOfView = camFov
		shake *= math.exp(-5 * dt)
	end)
	camera.CFrame = CFrame.lookAt(camPos, camLook)
	local camCF = CFrame.lookAt(camPos, camLook)

	-- ── The island ──
	local island = Instance.new("Model")
	island.Name = "Island"
	island.Parent = world
	local rock = Color3.fromRGB(46, 44, 58)
	part(island, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2, 30, 30), CFrame = CFrame.new(ORIGIN) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(52, 78, 60), Material = Enum.Material.Grass })
	for i, layer in ipairs({ { 26, 3 }, { 19, 4 }, { 11, 5 }, { 4, 4 } }) do
		part(island, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(layer[2], layer[1], layer[1]),
			CFrame = CFrame.new(ORIGIN - Vector3.new(0, 1 + i * 3.4, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = rock, Material = Enum.Material.Slate })
	end
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2 + 0.3
		local h = 2 + (i % 3) * 1.2
		local cp = ORIGIN + Vector3.new(math.cos(a) * 12.5, h / 2 + 0.8, math.sin(a) * 12.5)
		part(island, { Size = Vector3.new(0.8, h, 0.8), CFrame = CFrame.new(cp) * CFrame.Angles(math.rad(12), a, math.rad(8)),
			Color = Color3.fromRGB(140, 170, 255), Transparency = 0.25 })
	end
	-- runes round the landing circle
	local runeRing = {}
	for i = 1, 40 do
		runeRing[i] = part(island, { Size = Vector3.new(0.25, 0.08, 1.1), Color = Color3.fromRGB(150, 170, 255), Transparency = 0.35 })
	end
	local islandLight = part(island, { Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(ORIGIN + Vector3.new(0, 8, 6)) })
	local il = Instance.new("PointLight")
	il.Color, il.Brightness, il.Range = Color3.fromRGB(170, 185, 255), 1.6, 30
	il.Parent = islandLight

	-- ── The night sky ──
	local sky = Instance.new("Folder")
	sky.Name = "Sky"
	sky.Parent = world
	local skyStars: { BasePart } = {}
	local fwd = (camLook - camPos).Unit
	for i = 1, 260 do
		local yaw = math.rad(math.random(-80, 80))
		local pitch = math.rad(math.random(5, 75))
		local dir = (CFrame.lookAt(Vector3.zero, Vector3.new(fwd.X, 0, fwd.Z)) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, 0)).LookVector
		local s = math.random(15, 40) / 10
		skyStars[i] = part(sky, { Shape = Enum.PartType.Ball, Size = Vector3.one * s, CFrame = CFrame.new(camPos + dir * 420),
			Color = STARLIGHT:Lerp(Color3.fromRGB(170, 190, 255), math.random()), Transparency = 0.2 + math.random() * 0.5 })
	end
	local skyConn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _ = 1, 24 do
			local s = skyStars[math.random(1, #skyStars)]
			s.Transparency = 0.15 + (math.sin(t * 3 + s.Size.X * 7) * 0.5 + 0.5) * 0.6
		end
	end)

	-- ── Wish stars ──
	-- Laid out on a plane facing the camera, in an arc across the upper sky.
	local planePoint = ORIGIN + Vector3.new(0, 34, -46)
	local planeNormal = (camPos - planePoint).Unit
	local right = camCF.RightVector
	local up = camCF.UpVector
	type Wish = { reward: any, index: number, part: BasePart, light: PointLight, aura: ParticleEmitter, home: Vector3,
		pos: Vector3, state: string, shown: Color3, actual: Color3, revealed: boolean, size: number }
	local wishes: { Wish } = {}
	local n = #pulls
	for i, r in ipairs(pulls) do
		local ri = rarityIndex(r.rarity)
		local u = if n == 1 then 0 else (i - 1) / (n - 1) * 2 - 1
		local home = planePoint + right * (u * 34) + up * ((1 - u * u) * 9 + (if i % 2 == 0 then 3 else 0))
		local shown = colorOf(ORDER[math.min(ri, 3)]) -- (never above Epic, until it's grabbed)
		if ri == 1 then shown = STARLIGHT end
		local size = 1.5 + math.min(ri, 3) * 0.45
		local p = part(world, { Shape = Enum.PartType.Ball, Size = Vector3.one * size, CFrame = CFrame.new(home), Color = shown, Transparency = 1 })
		local light = Instance.new("PointLight")
		light.Color, light.Brightness, light.Range = shown, 2, 10
		light.Parent = p
		local aura = emitter(p, {
			Color = ColorSequence.new(Color3.new(1, 1, 1), shown), Size = seq(0, size * 0.9, 1, 0), Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180), Rate = 10 + math.min(ri, 3) * 8,
		})
		wishes[i] = { reward = r, index = ri, part = p, light = light, aura = aura, home = home, pos = home, state = "sky", shown = shown,
			actual = colorOf(r.rarity), revealed = false, size = size }
	end

	-- Wish stars twinkle and drift; a held star follows the pointer.
	local held: Wish? = nil
	local pointerTarget: Vector3? = nil
	local wishConn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock()
		for _, w in ipairs(wishes) do
			if w.state == "sky" then
				local target = w.home + up * math.sin(t * 1.3 + w.home.X) * 0.4
				w.pos = w.pos:Lerp(target, 1 - math.exp(-6 * dt))
				w.part.CFrame = CFrame.new(w.pos)
			elseif w.state == "held" and pointerTarget then
				-- a Legendary or better fights you on the way down
				local pull = if w.index >= 4 then 0.5 else 1
				local target = w.home:Lerp(pointerTarget, pull)
				w.pos = w.pos:Lerp(target, 1 - math.exp(-14 * dt))
				w.part.CFrame = CFrame.new(w.pos)
				if w.index >= 4 then shake = math.max(shake, 0.25) end
			end
		end
		for i, rp in ipairs(runeRing) do
			local a = i / #runeRing * math.pi * 2 + t * 0.15
			rp.CFrame = CFrame.new(ORIGIN + Vector3.new(math.cos(a) * 9.5, 1.06, math.sin(a) * 9.5)) * CFrame.Angles(0, -a, 0)
		end
	end)

	-- ── Constellations ──
	-- One spot in the sky for all of them: a rarer one draws itself over the
	-- one shown and the old one fades out beneath it.
	local shownRank = 0
	local shownParts: { BasePart } = {}
	local skyName = text("", 26, 0.12)
	local function drawConstellation(rarity: string, slow: boolean): number
		local shape = SHAPES[rarity]
		if not shape then return 0 end
		local col = colorOf(rarity)
		local star = Color3.new(1, 1, 1):Lerp(col, 0.35)
		local center = camPos + fwd * 230 + up * 48
		-- the old one is outshone
		for _, old in ipairs(shownParts) do
			tween(old, 1.4, { Transparency = 1 })
			Debris:AddItem(old, 1.5)
		end
		shownParts = {}
		local pts = {}
		for i, pnt in ipairs(shape.points) do
			pts[i] = center + right * pnt.X * shape.scale + up * pnt.Y * shape.scale
		end
		local nodes = {}
		for i, pp in ipairs(pts) do
			nodes[i] = part(sky, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.1, CFrame = CFrame.new(pp), Color = star })
			table.insert(shownParts, nodes[i])
		end
		local step = if slow then math.min(0.2, 3.2 / #shape.edges) else math.min(0.05, 1.2 / #shape.edges)
		local nodeSize = if slow then 3.4 else 2.4
		for k, e in ipairs(shape.edges) do
			local a, b = pts[e[1]], pts[e[2]]
			local line = part(sky, { Size = Vector3.new(0.6, 0.6, 0.1), CFrame = CFrame.lookAt(a, b), Color = col, Transparency = 1 })
			table.insert(shownParts, line)
			task.delay((k - 1) * step, function()
				for _, node in ipairs({ nodes[e[1]], nodes[e[2]] }) do
					if node.Size.X < 1 then tween(node, 0.25, { Size = Vector3.one * nodeSize }, Enum.EasingStyle.Back) end
				end
				line.Transparency = 0.25
				tween(line, step * 1.6 + 0.05, { Size = Vector3.new(0.6, 0.6, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b) })
				if slow and k % 2 == 1 then sfx("ding", 0.3, 0.8 + k * 0.03) end
			end)
		end
		-- its name, in the sky's colour
		skyName.Text = SHAPE_NAMES[rarity] or ""
		skyName.TextColor3 = star
		skyName.TextTransparency = 1
		task.delay(#shape.edges * step, function()
			tween(skyName, 0.5, { TextTransparency = 0.1 })
			task.delay(2.5, function() tween(skyName, 0.8, { TextTransparency = 1 }) end)
		end)
		return #shape.edges * step + 0.3
	end
	-- Whether landing a `rarity` star outshines the constellation shown (and
	-- claims the sky at once, so stars landing together don't both draw).
	local function claimSky(rarity: string): boolean
		local rank = ({ Common = 1, Uncommon = 2, Rare = 3, Epic = 4, Legendary = 5, Mythic = 6 })[rarity] or 0
		if rank <= shownRank then return false end
		shownRank = rank
		return true
	end

	-- Aurora: wide translucent bands of colour waving over the sky.
	local auroraConn: RBXScriptConnection? = nil
	local function aurora(col: Color3)
		local bands = {}
		for i = 1, 5 do
			bands[i] = part(sky, { Size = Vector3.new(260, 18 + i * 4, 1), Color = col:Lerp(Color3.fromRGB(120, 255, 210), (i % 2) * 0.35), Transparency = 1 })
			tween(bands[i], 1.5, { Transparency = 0.82 })
		end
		local base = camPos + fwd * 300
		auroraConn = RunService.RenderStepped:Connect(function()
			local t = os.clock()
			for i, b in ipairs(bands) do
				b.CFrame = CFrame.lookAt(base + up * (70 + i * 14) + right * math.sin(t * 0.3 + i) * 20, camPos) * CFrame.Angles(0, 0, math.sin(t * 0.4 + i * 0.7) * 0.18)
			end
		end)
	end

	-- ── Landing ──
	local landed = 0
	local landSpots = {}
	local cards: { BillboardGui } = {}
	local function landingSpot(i: number): Vector3
		local a = (i / math.max(n, 1)) * math.pi * 2 + 0.4
		local r = if n == 1 then 0 else 6.5
		return ORIGIN + Vector3.new(math.cos(a) * r, 1.6, math.sin(a) * r * 0.6 + 2)
	end
	local function burst(at: Vector3, col: Color3, count: number, speed: number)
		local anchor = part(world, { Size = Vector3.one * 0.1, Transparency = 1, CFrame = CFrame.new(at) })
		local pe = emitter(anchor, { Color = ColorSequence.new(Color3.new(1, 1, 1), col), Size = seq(0, 0.7, 1, 0),
			Lifetime = NumberRange.new(0.5, 1.2), Speed = NumberRange.new(speed * 0.4, speed), SpreadAngle = Vector2.new(180, 180), Drag = 3, Rate = 0 })
		pe:Emit(count)
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range = col, 6, 22
		l.Parent = anchor
		tween(l, 0.7, { Brightness = 0 })
		Debris:AddItem(anchor, 2)
	end
	local function card(at: Vector3, r: any)
		local anchor = part(world, { Size = Vector3.one * 0.1, Transparency = 1, CFrame = CFrame.new(at) })
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(150, 64)
		bb.StudsOffset = Vector3.new(0, 1.8, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Adornee = anchor
		bb.Parent = anchor
		local col = colorOf(r.rarity)
		local glyph = Instance.new("TextLabel")
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.new(1, 0, 0, 34)
		glyph.Text = r.glyph or "?"
		glyph.TextScaled = true
		glyph.Font = Enum.Font.GothamBlack
		glyph.TextColor3 = col
		glyph.Parent = bb
		local nm = Instance.new("TextLabel")
		nm.BackgroundTransparency = 1
		nm.Position = UDim2.fromOffset(0, 34)
		nm.Size = UDim2.new(1, 0, 0, 18)
		nm.Text = r.name
		nm.TextScaled = true
		nm.Font = Enum.Font.Antique
		nm.TextColor3 = col
		nm.TextStrokeTransparency = 0.3
		nm.Parent = bb
		local sc = Instance.new("UIScale")
		sc.Scale = 0
		sc.Parent = bb
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		table.insert(cards, bb)
	end

	local quietUntil = 0
	local pendingLandings = 0 -- falling, or still drawing their constellation
	local function fall(w: Wish, fast: boolean)
		if w.state == "falling" or w.state == "down" then return end
		w.state = "falling"
		pendingLandings += 1
		landed += 1
		local slot = landed
		local to = landingSpot(slot)
		landSpots[slot] = to
		-- (the true colour shows as it falls, at the latest)
		if not w.revealed then
			w.revealed = true
			w.part.Color, w.light.Color = w.actual, w.actual
			w.aura.Color = ColorSequence.new(Color3.new(1, 1, 1), w.actual)
		end
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.5, 0)
		a0.Parent = w.part
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.5, 0)
		a1.Parent = w.part
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(Color3.new(1, 1, 1), w.actual)
		tr.Transparency = seq(0, 0, 1, 1)
		tr.Lifetime = 0.4
		tr.LightEmission = 1
		tr.FaceCamera = true
		tr.WidthScale = seq(0, 1.6, 1, 0)
		tr.Parent = w.part
		sfx("whoosh", 0.45, 0.8 + w.index * 0.05)
		local from = w.pos
		local dur = if fast then 0.35 else 0.6
		local t0 = os.clock()
		task.spawn(function()
			while os.clock() - t0 < dur do
				local a = (os.clock() - t0) / dur
				local e = a * a
				-- an arc: out and over, then down
				local mid = from:Lerp(to, 0.5) + Vector3.new(0, 6, 0)
				local pos = from:Lerp(mid, e):Lerp(mid:Lerp(to, e), e)
				w.pos = pos
				w.part.CFrame = CFrame.new(pos)
				RunService.RenderStepped:Wait()
			end
			w.state = "down"
			w.part.CFrame = CFrame.new(to)
			tween(w.part, 0.4, { Size = Vector3.one * w.size * 0.5, Transparency = 0.2 })
			w.aura.Rate = 4
			burst(to, w.actual, 20 + w.index * 12, 8 + w.index * 2)
			sfx("ding", 0.45, 0.85 + w.index * 0.12)
			if w.index >= 2 then sfx("magicBurst", 0.3 + w.index * 0.08, 1) end
			shake = math.max(shake, 0.15 + w.index * 0.12)
			card(to, w.reward)
			-- its constellation, if it outshines the one in the sky
			local rarity = w.reward.rarity
			local claims = claimSky(rarity)
			if claims and w.index >= 4 and not fast then
				-- Everything goes quiet; the hero draws itself; the sky turns gold.
				quietUntil = os.clock() + 99
				tween(black, 0.4, { BackgroundTransparency = 0.45 })
				task.wait(0.6)
				sfx("chime", 0.4, 0.7)
				local dur2 = drawConstellation(rarity, true)
				tween(black, dur2, { BackgroundTransparency = 0.7 })
				task.wait(dur2)
				white.BackgroundTransparency = 0.2
				tween(white, 0.6, { BackgroundTransparency = 1 })
				tween(black, 0.3, { BackgroundTransparency = 1 })
				sfx("boom", 0.8, 0.8)
				sfx("choir", 0.6, 1)
				sfx("angel", 0.5, 1)
				bloomKick(3.2)
				shake = 1.2
				tween(grade, 1, { TintColor = Color3.new(1, 1, 1):Lerp(w.actual, 0.3) })
				aurora(w.actual)
				task.wait(0.6)
				quietUntil = 0
			elseif claims then
				drawConstellation(rarity, false)
				if w.index >= 3 then sfx("chime", 0.35, 1.1) end
			end
			pendingLandings -= 1
		end)
	end

	-- Grabbing: a star near the pointer (screen distance).
	local function pointer(io: InputObject?): Vector2
		if io and io.UserInputType == Enum.UserInputType.Touch then
			local inset = GuiService:GetGuiInset()
			return Vector2.new(io.Position.X, io.Position.Y) + inset
		end
		return UserInputService:GetMouseLocation()
	end
	local function planeHit(screen: Vector2): Vector3?
		local ray = camera:ViewportPointToRay(screen.X, screen.Y)
		local denom = ray.Direction:Dot(planeNormal)
		if math.abs(denom) < 1e-4 then return nil end
		local tHit = (planePoint - ray.Origin):Dot(planeNormal) / denom
		return if tHit > 0 then ray.Origin + ray.Direction * tHit else nil
	end
	local function starAt(screen: Vector2): Wish?
		local bestW, bestD = nil, 70
		for _, w in ipairs(wishes) do
			if w.state == "sky" then
				local sp, onScreen = camera:WorldToViewportPoint(w.pos)
				local d = (Vector2.new(sp.X, sp.Y) - screen).Magnitude
				if onScreen and d < bestD then bestW, bestD = w, d end
			end
		end
		return bestW
	end
	local function releaseLow(w: Wish): boolean
		local sp = camera:WorldToViewportPoint(w.pos)
		return sp.Y / camera.ViewportSize.Y > (if w.index >= 4 then 0.5 else 0.58)
	end

	local canInteract = false
	local skipping = false
	local function remaining(): number
		local c = 0
		for _, w in ipairs(wishes) do
			if w.state == "sky" or w.state == "held" then c += 1 end
		end
		return c
	end
	local conns: { RBXScriptConnection } = {}
	table.insert(conns, UserInputService.InputBegan:Connect(function(io)
		if not canInteract or held or os.clock() < quietUntil then return end
		if io.UserInputType ~= Enum.UserInputType.MouseButton1 and io.UserInputType ~= Enum.UserInputType.Touch then return end
		local w = starAt(pointer(io))
		if not w then return end
		held = w
		w.state = "held"
		pointerTarget = planeHit(pointer(io))
		sfx("chime", 0.35, 1 + w.index * 0.05)
		tween(w.part, 0.15, { Size = Vector3.one * w.size * 1.3 })
		hint.TextTransparency = 1
		if w.index >= 4 and not w.revealed then
			-- It was never purple.
			w.revealed = true
			w.part.Color, w.light.Color = w.actual, w.actual
			w.aura.Color = ColorSequence.new(Color3.new(1, 1, 1), w.actual)
			w.aura.Rate = 60
			burst(w.pos, w.actual, 60, 18)
			white.BackgroundTransparency = 0.5
			tween(white, 0.35, { BackgroundTransparency = 1 })
			bloomKick(2.6)
			shake = 0.8
			sfx("thunder", 0.6, 1.1)
			sfx("charge", 0.5, 1)
		end
	end))
	table.insert(conns, UserInputService.InputChanged:Connect(function(io)
		if not held then return end
		if io.UserInputType == Enum.UserInputType.MouseMovement or io.UserInputType == Enum.UserInputType.Touch then
			pointerTarget = planeHit(pointer(io)) or pointerTarget
		end
	end))
	table.insert(conns, UserInputService.InputEnded:Connect(function(io)
		if not held then return end
		if io.UserInputType ~= Enum.UserInputType.MouseButton1 and io.UserInputType ~= Enum.UserInputType.Touch then return end
		local w = held :: Wish
		held = nil
		pointerTarget = nil
		if releaseLow(w) then
			fall(w, false)
		else
			w.state = "sky" -- springs back home
			tween(w.part, 0.2, { Size = Vector3.one * w.size })
			sfx("poof", 0.25, 1.4)
		end
	end))

	local function wishAll(fast: boolean)
		task.spawn(function()
			for _, w in ipairs(wishes) do
				if w.state == "sky" then
					while os.clock() < quietUntil do task.wait(0.1) end
					fall(w, fast)
					task.wait(if fast then 0.08 else 0.35)
				end
			end
		end)
	end
	allBtn.Activated:Connect(function()
		if not canInteract then return end
		allBtn.Visible = false
		wishAll(false)
	end)
	skipBtn.Activated:Connect(function()
		if skipping then return end
		skipping = true
		allBtn.Visible, skipBtn.Visible = false, false
		if held then
			held.state = "sky"
			held = nil
		end
		wishAll(true)
	end)

	-- ── 1. NIGHT ──
	sfx("wind", 0.4, 0.7)
	tween(black, 1.2, { BackgroundTransparency = 1 })
	for i, w in ipairs(wishes) do
		task.delay(0.5 + i * 0.09, function()
			tween(w.part, 0.4, { Transparency = 0 })
			sfx("ding", 0.2, 1.4 + i * 0.03)
		end)
	end
	task.wait(1.2 + n * 0.09)
	canInteract = true
	tween(hint, 0.5, { TextTransparency = 0 })

	-- ── 2/3. WISH — until every star is down ──
	while remaining() > 0 or pendingLandings > 0 do
		task.wait(0.1)
	end
	task.wait(0.6) -- (let the last landing settle)
	canInteract = false
	allBtn.Visible, skipBtn.Visible = false, false
	tween(hint, 0.2, { TextTransparency = 1 })

	-- ── 4. REVEAL ──
	local function nameCard()
		nameLabel.Text = string.upper(best.name)
		nameLabel.TextColor3 = best.accent or colorOf(best.rarity)
		rarityLabel.Text = string.upper(best.rarity)
		rarityLabel.TextColor3 = colorOf(best.rarity)
		nameLabel.TextSize = 92
		tween(nameLabel, 0.35, { TextTransparency = 0, TextSize = 56 }, Enum.EasingStyle.Back)
		tween(rarityLabel, 0.5, { TextTransparency = 0 })
		sfx("swordIn", 0.5, 1)
		local row = Instance.new("Frame")
		row.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Position = UDim2.fromScale(0.5, 0.66)
		row.Size = UDim2.fromOffset(bestIndex * 46, 44)
		row.BackgroundTransparency = 1
		row.ZIndex = 12
		row.Parent = gui
		for i = 1, bestIndex do
			local st = Instance.new("TextLabel")
			st.AnchorPoint = Vector2.new(0.5, 0.5)
			st.Position = UDim2.new(0, (i - 0.5) * 46, 0.5, 0)
			st.Size = UDim2.fromOffset(44, 44)
			st.BackgroundTransparency = 1
			st.Font = Enum.Font.GothamBlack
			st.Text = "★"
			st.TextScaled = true
			st.TextColor3 = colorOf(best.rarity)
			st.TextStrokeTransparency = 0.2
			st.TextTransparency = 1
			st.ZIndex = 12
			st.Parent = row
			local sc = Instance.new("UIScale")
			sc.Scale = 2.4
			sc.Parent = st
			task.delay(0.25 + i * 0.16, function()
				tween(st, 0.15, { TextTransparency = 0 })
				tween(sc, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)
				sfx("ding", 0.4, 0.9 + i * 0.12)
			end)
		end
	end

	local cleanupFigure: (() -> ())? = nil
	if bestIndex >= 3 then
		-- A column of starlight comes down on the island; the figure stands in it.
		for _, c in ipairs(cards) do c.Enabled = false end
		local front = Vector3.new(0, 0, 1)
		local standAt = ORIGIN + Vector3.new(0, 4, 0)
		local fromPos, fromLook = camPos, camLook
		local t0 = os.clock()
		while os.clock() - t0 < 0.9 do
			local a = math.clamp((os.clock() - t0) / 0.9, 0, 1)
			local e = a * a * (3 - 2 * a)
			camPos = fromPos:Lerp(standAt + front * 10 + Vector3.new(0, 1.5, 0), e)
			camLook = fromLook:Lerp(standAt + Vector3.new(0, 1.2, 0), e)
			camFov = 70 + (50 - 70) * e
			RunService.RenderStepped:Wait()
		end
		local col = colorOf(best.rarity)
		local column = part(world, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(160, 0.3, 0.3),
			CFrame = CFrame.new(standAt + Vector3.new(0, 78, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = STARLIGHT, Transparency = 0.1 })
		local columnGlow = part(world, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(160, 0.3, 0.3), CFrame = column.CFrame, Color = col, Transparency = 0.65 })
		tween(column, 0.3, { Size = Vector3.new(160, 3, 3) }, Enum.EasingStyle.Back)
		tween(columnGlow, 0.35, { Size = Vector3.new(160, 9, 9) }, Enum.EasingStyle.Back)
		white.BackgroundTransparency = 0.1
		tween(white, 0.5, { BackgroundTransparency = 1 })
		sfx("thunder", 0.6, 0.9)
		sfx("boom", 0.8, 0.8)
		bloomKick(3)
		shake = 1
		local figure, cleanup = RewardPreview.Build(best)
		cleanupFigure = cleanup
		figure.Parent = world
		figure:PivotTo(CFrame.lookAt(standAt, standAt + front))
		burst(standAt, col, 90, 16)
		local motes = part(world, { Size = Vector3.one * 0.1, Transparency = 1, CFrame = CFrame.new(standAt - Vector3.new(0, 2, 0)) })
		emitter(motes, { Color = ColorSequence.new(STARLIGHT, col), Size = seq(0, 0.3, 1, 0), Lifetime = NumberRange.new(1.5, 2.5),
			Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 30), Acceleration = Vector3.new(0, 2, 0), Rate = 30,
			Shape = Enum.ParticleEmitterShape.Cylinder, ShapeInOut = Enum.ParticleEmitterShapeInOut.Outward })
		tween(column, 1.2, { Size = Vector3.new(160, 1.2, 1.2), Transparency = 0.5 })
		tween(columnGlow, 1.2, { Size = Vector3.new(160, 5, 5), Transparency = 0.8 })
		task.wait(0.7)
		sfx("choir", 0.5, 1)
		-- a slow push in
		local p0 = camPos
		task.spawn(function()
			local s0 = os.clock()
			while cleanupFigure and os.clock() - s0 < 6 do
				local a = (os.clock() - s0) / 6
				camPos = p0:Lerp(standAt + front * 8 + Vector3.new(0, 1.2, 0), a)
				RunService.RenderStepped:Wait()
			end
		end)
	else
		-- Common / Rare at best: the island with every card on it.
		local fromPos, fromLook = camPos, camLook
		local t0 = os.clock()
		while os.clock() - t0 < 0.8 do
			local a = math.clamp((os.clock() - t0) / 0.8, 0, 1)
			local e = a * a * (3 - 2 * a)
			camPos = fromPos:Lerp(ORIGIN + Vector3.new(0, 9, 19), e)
			camLook = fromLook:Lerp(ORIGIN + Vector3.new(0, 1.5, 0), e)
			RunService.RenderStepped:Wait()
		end
	end
	nameCard()

	-- Wait for a click.
	task.wait(1.2)
	tween(continueLabel, 0.4, { TextTransparency = 0.2 })
	local clicked = false
	local clickConn = UserInputService.InputBegan:Connect(function(io)
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
			or io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.Return then
			clicked = true
		end
	end)
	local w0 = os.clock()
	while not clicked and os.clock() - w0 < 15 do
		continueLabel.TextTransparency = 0.25 + math.sin((os.clock() - w0) * 4) * 0.2
		RunService.RenderStepped:Wait()
	end
	clickConn:Disconnect()

	-- ── Tear down ──
	tween(black, 0.45, { BackgroundTransparency = 0 })
	task.wait(0.5)
	for _, c in ipairs(conns) do c:Disconnect() end
	camConn:Disconnect()
	skyConn:Disconnect()
	wishConn:Disconnect()
	if auroraConn then auroraConn:Disconnect() end
	if cleanupFigure then
		local c = cleanupFigure
		cleanupFigure = nil
		c()
	end
	world:Destroy()
	bloom:Destroy()
	grade:Destroy()
	restoreLighting()
	for s, vol in pairs(ducked) do
		if s.Parent then tween(s, 0.8, { Volume = vol }) end
	end
	for _, l in ipairs({ nameLabel, rarityLabel, continueLabel }) do l.Visible = false end
	tween(black, 0.4, { BackgroundTransparency = 1 })
	Debris:AddItem(gui, 0.5)
	if onDone then onDone() end
end

return ConstellationWish
