--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- AtmosphereManager.luau
-- Manages grim, moody medieval dungeon lighting, atmosphere, and player torch lights.
-- ─────────────────────────────────────────────────────────────────────────────

local Lighting   = game:GetService("Lighting")
local Workspace  = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local AtmosphereManager = {}

-- =============================================================================
-- ⚙️ LIGHTING & DIMMING CONFIGURATION (TWEAK VARIABLES HERE)
-- =============================================================================
-- Adjust these variables to get your exact preferred level of dimming and torch intensity:
AtmosphereManager.Config = {
	-- Gothic night: deep violet shadows, a low pale light throwing long shafts
	-- between the pillars, and warm pools of candlelight doing the real work.

	-- ── 1. Global light ─────────────────────────────────────────────────────
	-- Dim inside: the daylight falling through the windows (section 5), the
	-- candles, braziers and your torch do the real lighting.
	-- Ambient: light in fully shadowed areas. Keep it dark and teal.
	DungeonAmbient = Color3.fromRGB(30, 42, 72),       -- cool blue shadows: depth against the warm torches

	-- OutdoorAmbient: sky fill on open floors.
	DungeonOutdoorAmbient = Color3.fromRGB(46, 60, 96),

	-- Brightness of the low sun that casts the long pillar shadows.
	DungeonBrightness = 0.8,

	-- ClockTime: ~17.3 = low sun angle -> long shadows across the floor.
	DungeonClockTime = 17.3,
	DungeonLatitude = 35,

	-- Tints on sun-facing (Top) and opposite (Bottom) surfaces.
	DungeonColorShiftTop = Color3.fromRGB(40, 28, 18),     -- lit tops only faintly warm (the torches bring the warmth)
	DungeonColorShiftBottom = Color3.fromRGB(14, 24, 52),  -- cool blue undersides

	-- Overall exposure (negative = darker scene; lights keep their punch).
	DungeonExposure = -0.2,

	-- ── 2. Player Torch Light Controls ───────────────────────────────────────
	-- TorchEnabled: a soft warm fill above the player so the character reads
	-- in the dark. TorchEmbers: the held-torch ember particles.
	TorchEnabled = true,
	TorchEmbers = false,

	-- TorchRange: Radius in studs that the torch illuminates around the player (e.g. 24 - 45).
	TorchRange = 56, -- spread wide over the room around you

	-- TorchBrightness: Light intensity of the torch flame (e.g. 1.8 - 3.5).
	TorchBrightness = 1.0, -- kept moderate so ability VFX read clearly around the player

	-- TorchHeight: studs above the character the light hangs. Higher spreads the
	-- glow evenly instead of blowing out the character and the floor under them.
	TorchHeight = 10, -- higher spreads the glow wider and more evenly

	-- The torch's far reach: a wide spotlight hung high above you pointing
	-- down (a PointLight stops at 60 studs; this lights ~90 studs across).
	TorchSpreadRange = 60,
	TorchSpreadHeight = 30,
	TorchSpreadAngle = 150,
	TorchSpreadBrightness = 0.8,

	-- TorchColor: Color of the flame light.
	TorchColor = Color3.fromRGB(255, 190, 130),

	-- TorchShadows: Cast real-time shadows from dungeon walls and obstacles.
	TorchShadows = false,

	-- ── 3. Candle clusters (placed along room walls by the generator) ────────
	CandleColor = Color3.fromRGB(255, 146, 62),
	CandleBrightness = 2.4,
	CandleRange = 20,
	CandleShadows = true,
	CandlesPerRoom = 3,

	-- ── 4. Post-Processing & Fog ─────────────────────────────────────────────
	ColorCorrection = {
		Brightness = 0,
		Contrast = 0.3,                                   -- Painterly, punchy light vs. shadow
		Saturation = 0.38,                                -- Hades-rich colour
		TintColor = Color3.fromRGB(240, 244, 255),        -- A touch cool; the warmth comes from the flames
	},

	Atmosphere = {
		Density = 0,                                      -- none: past the map's edges you see the skybox itself, not haze
		Offset = 0,
		Color = Color3.fromRGB(36, 48, 78),               -- Cool blue haze
		Decay = Color3.fromRGB(14, 18, 36),
		Haze = 0,
		Glare = 0,
	},

	Bloom = {
		Intensity = 1.1,                                  -- Hades-style glow on flames, neon and VFX
		Size = 36,
		Threshold = 0.82,                                  -- Only genuinely bright things (flames, neon) bloom
	},

	-- ── 5. Daylight through the windows ──────────────────────────────────────
	-- Every window opening glows with the daylight outside and throws a soft
	-- shaft sloping down into the room, a pool of light where it lands and
	-- drifting dust.
	WindowLightColor = Color3.fromRGB(226, 226, 236), -- pale daylight, not orange
	WindowLightBrightness = 2.2,  -- the pool of light on the floor
	WindowShaftAngle = 38,        -- degrees below horizontal
	WindowShaftOpacity = 0.075,   -- per layer; three layers stack into a soft core
}

-- ── 1. Lighting & Atmosphere Setup ───────────────────────────────────────────

function AtmosphereManager.ApplyLobbyLighting()
	-- Configure bright daytime lobby / sanctuary lighting
	Lighting.Ambient = Color3.fromRGB(180, 180, 190)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.Brightness = 2.0
	Lighting.ClockTime = 14 -- Daytime illumination
	Lighting.GlobalShadows = true
	Lighting.ExposureCompensation = 0
	Lighting.ColorShift_Top = Color3.new(0, 0, 0)
	Lighting.ColorShift_Bottom = Color3.new(0, 0, 0)

	pcall(function()
		Lighting.EnvironmentDiffuseScale = 1.0
		Lighting.EnvironmentSpecularScale = 1.0
	end)

	local colorCorr = Lighting:FindFirstChild("DungeonColorCorrection") :: ColorCorrectionEffect?
	if colorCorr then
		colorCorr.Enabled = false
	end

	local bloom = Lighting:FindFirstChild("DungeonTorchBloom") :: BloomEffect?
	if bloom then
		bloom.Enabled = false
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.1
		atmosphere.Color = Color3.fromRGB(199, 217, 230)
		atmosphere.Decay = Color3.fromRGB(106, 126, 143)
		atmosphere.Haze = 0
	end

	print("[AtmosphereManager] Lobby / Sanctuary bright lighting applied.")
end

function AtmosphereManager.ApplyDungeonLighting()
	local cfg = AtmosphereManager.Config

	-- Configure dim, atmospheric dungeon lighting
	Lighting.Ambient = cfg.DungeonAmbient
	Lighting.OutdoorAmbient = cfg.DungeonOutdoorAmbient
	Lighting.Brightness = cfg.DungeonBrightness
	Lighting.ClockTime = cfg.DungeonClockTime
	Lighting.GeographicLatitude = cfg.DungeonLatitude
	Lighting.ColorShift_Top = cfg.DungeonColorShiftTop
	Lighting.ColorShift_Bottom = cfg.DungeonColorShiftBottom
	Lighting.ExposureCompensation = cfg.DungeonExposure
	Lighting.GlobalShadows = true

	pcall(function()
		Lighting.EnvironmentDiffuseScale = 0.25
		Lighting.EnvironmentSpecularScale = 0.6 -- a little sheen on the stone
	end)

	-- Future gives the candles real shadows and soft falloff. Scripts usually
	-- are not allowed to set this: set Lighting.Technology = Future in Studio.
	pcall(function()
		Lighting.Technology = Enum.Technology.Future
	end)

	local sunRays = Lighting:FindFirstChildOfClass("SunRaysEffect")
	if sunRays then sunRays.Enabled = false end

	-- 1. ColorCorrection Effect
	local colorCorr = Lighting:FindFirstChild("DungeonColorCorrection") :: ColorCorrectionEffect?
	if not colorCorr then
		colorCorr = Instance.new("ColorCorrectionEffect")
		colorCorr.Name = "DungeonColorCorrection"
		colorCorr.Parent = Lighting
	end
	colorCorr.Brightness = cfg.ColorCorrection.Brightness
	colorCorr.Contrast = cfg.ColorCorrection.Contrast
	colorCorr.Saturation = cfg.ColorCorrection.Saturation
	colorCorr.TintColor = cfg.ColorCorrection.TintColor
	colorCorr.Enabled = true

	-- 2. Torch Bloom Effect
	local bloom = Lighting:FindFirstChild("DungeonTorchBloom") :: BloomEffect?
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "DungeonTorchBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = cfg.Bloom.Intensity
	bloom.Size = cfg.Bloom.Size
	bloom.Threshold = cfg.Bloom.Threshold
	bloom.Enabled = true

	-- 3. Dungeon Atmosphere (Atmospheric fog & haze)
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = cfg.Atmosphere.Density
	atmosphere.Offset = cfg.Atmosphere.Offset
	atmosphere.Color = cfg.Atmosphere.Color
	atmosphere.Decay = cfg.Atmosphere.Decay
	atmosphere.Haze = cfg.Atmosphere.Haze
	atmosphere.Glare = cfg.Atmosphere.Glare

	print("[AtmosphereManager] Dungeon atmosphere & dim lighting applied successfully.")
end

-- ── 1b. Candle clusters ──────────────────────────────────────────────────────
-- A few wax candles with little flames and one warm, shadow-casting light.
-- `cf` is a point on the floor surface. The light is tagged "CandleLight" so
-- TorchLightController can flicker it on clients.
function AtmosphereManager.PlaceCandleCluster(cf: CFrame, parent: Instance, rng: Random): Model
	local cfg = AtmosphereManager.Config
	local model = Instance.new("Model")
	model.Name = "CandleCluster"

	local function candlePart(props: { [string]: any }): BasePart
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.CastShadow = false
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do (p :: any)[k] = v end
		p.Parent = model
		return p
	end

	local count = rng:NextInteger(3, 6)
	for i = 1, count do
		local angle = (i / count) * math.pi * 2 + rng:NextNumber() * 0.8
		local dist = if i == 1 then 0 else rng:NextNumber(0.5, 1.3)
		local height = rng:NextNumber(0.6, 1.9)
		local width = rng:NextNumber(0.32, 0.48)
		local base = cf * CFrame.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
		candlePart({
			Name = "Wax",
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(height, width, width),
			CFrame = base * CFrame.new(0, height / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = Color3.fromRGB(226, 214, 190),
			Material = Enum.Material.SmoothPlastic,
			CastShadow = true,
		})
		candlePart({
			Name = "Flame",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.16, 0.3, 0.16),
			CFrame = base * CFrame.new(0, height + 0.17, 0),
			Color = Color3.fromRGB(255, 190, 90),
			Material = Enum.Material.Neon,
		})
	end

	local glow = candlePart({
		Name = "Glow",
		Size = Vector3.new(0.2, 0.2, 0.2),
		CFrame = cf * CFrame.new(0, 2.4, 0),
		Transparency = 1,
	})
	local light = Instance.new("PointLight")
	light.Name = "CandleLight"
	light.Color = cfg.CandleColor
	light.Brightness = cfg.CandleBrightness
	light.Range = cfg.CandleRange
	light.Shadows = cfg.CandleShadows
	light:SetAttribute("BaseBrightness", cfg.CandleBrightness)
	light:SetAttribute("Phase", rng:NextNumber(0, 100))
	light.Parent = glow
	CollectionService:AddTag(light, "CandleLight")

	model.Parent = parent
	return model
end


-- ── 1c. Hades-style set dressing (no lights: Fire + Neon + particles) ────────
local MEDALLION_STONE = Color3.fromRGB(62, 78, 74)
local MEDALLION_DARK = Color3.fromRGB(34, 44, 44)
local MEDALLION_GOLD = Color3.fromRGB(214, 168, 78)
local BRAZIER_FLAME = Color3.fromRGB(90, 255, 160)

local function prop(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- A big round stone medallion set into the floor: dark stone, gold inlay
-- rings, a ring of wedge tiles and a star at the centre (the room reward
-- floats above it).
function AtmosphereManager.PlaceFloorMedallion(center: Vector3, radius: number, parent: Instance): Model
	local model = Instance.new("Model")
	model.Name = "FloorMedallion"
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local y = center.Y + 0.06
	local c = CFrame.new(center.X, y, center.Z)
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, radius * 2, radius * 2), CFrame = c * flat,
		Color = MEDALLION_DARK, Material = Enum.Material.Slate })
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, radius * 1.86, radius * 1.86), CFrame = c * CFrame.new(0, 0.01, 0) * flat,
		Color = MEDALLION_GOLD, Material = Enum.Material.Metal })
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, radius * 1.78, radius * 1.78), CFrame = c * CFrame.new(0, 0.02, 0) * flat,
		Color = MEDALLION_STONE, Material = Enum.Material.Slate })
	-- Ring of wedge tiles with gold seams between them.
	local tiles = 12
	for i = 1, tiles do
		local a = (i / tiles) * math.pi * 2
		local rot = CFrame.Angles(0, a, 0)
		prop(model, { Size = Vector3.new(0.12, 0.05, radius * 0.42), CFrame = c * rot * CFrame.new(0, 0.1, -radius * 0.66),
			Color = MEDALLION_GOLD, Material = Enum.Material.Metal })
	end
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.18, radius * 0.95, radius * 0.95), CFrame = c * CFrame.new(0, 0.04, 0) * flat,
		Color = MEDALLION_GOLD, Material = Enum.Material.Metal })
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, radius * 0.86, radius * 0.86), CFrame = c * CFrame.new(0, 0.05, 0) * flat,
		Color = MEDALLION_DARK, Material = Enum.Material.Slate })
	-- Eight-point star in the middle.
	for i = 0, 3 do
		prop(model, { Size = Vector3.new(radius * 0.12, 0.06, radius * 0.7), CFrame = c * CFrame.new(0, 0.13, 0) * CFrame.Angles(0, i * math.pi / 4, 0),
			Color = MEDALLION_GOLD, Material = Enum.Material.Metal })
	end
	model.Parent = parent
	return model
end

-- A stone brazier on a short pedestal with a green (Tartarus) flame: a Fire
-- object plus rising sparks. Deliberately no PointLight.
function AtmosphereManager.PlaceBrazier(cf: CFrame, parent: Instance, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "Brazier"
	local flat = CFrame.Angles(0, 0, math.rad(90))
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, 2.6, 2.6), CFrame = cf * CFrame.new(0, 0.3, 0) * flat,
		Color = MEDALLION_DARK, Material = Enum.Material.Slate, CanCollide = true })
	prop(model, { Size = Vector3.new(1.3, 3, 1.3), CFrame = cf * CFrame.new(0, 2.1, 0),
		Color = MEDALLION_STONE, Material = Enum.Material.Slate, CanCollide = true })
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2, 2), CFrame = cf * CFrame.new(0, 3.2, 0) * flat,
		Color = MEDALLION_GOLD, Material = Enum.Material.Metal })
	local bowl = prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.8, 2.8), CFrame = cf * CFrame.new(0, 3.8, 0) * flat,
		Color = Color3.fromRGB(44, 30, 26), Material = Enum.Material.Metal, CanCollide = true })
	local coals = prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2.3, 2.3), CFrame = cf * CFrame.new(0, 4.2, 0) * flat,
		Color = BRAZIER_FLAME, Material = Enum.Material.Neon, Transparency = 0.2 })
	local fire = Instance.new("Fire")
	fire.Color = BRAZIER_FLAME
	fire.SecondaryColor = Color3.fromRGB(20, 110, 70)
	fire.Size = 5 + rng:NextNumber(0, 1.5)
	fire.Heat = 9
	fire.Parent = coals
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, 0.3, 0)
	att.Parent = coals
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.fromRGB(200, 255, 220), BRAZIER_FLAME)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(1, 2)
	sparks.Speed = NumberRange.new(2, 4)
	sparks.SpreadAngle = Vector2.new(20, 20)
	sparks.Acceleration = Vector3.new(0, 2, 0)
	sparks.Rate = 5
	sparks.Parent = att
	model.PrimaryPart = bowl
	model.Parent = parent
	return model
end

-- ── 1d. Daylight through the windows ────────────────────────────────────────
-- The window openings of the wall meshes, in the wall's local space (x across,
-- y up from the wall's centre, w × h in studs). Walls are 17 × 17 × 2.
local WINDOW_OPENINGS: { [string]: { { x: number, y: number, w: number, h: number } } } = {
	Wall_Window_01 = { { x = 4.4, y = -1.4, w = 2.2, h = 4.2 }, { x = -3.3, y = -1.4, w = 2.2, h = 4.2 } },
	Wall_Window_02 = { { x = 0, y = -1.0, w = 4.6, h = 6.4 } },
}

-- The openings of a wall asset (by name), or nil when it has none.
function AtmosphereManager.WindowOpenings(assetName: string): { { x: number, y: number, w: number, h: number } }?
	for key, list in pairs(WINDOW_OPENINGS) do
		if string.find(assetName, key, 1, true) then return list end
	end
	return nil
end

local function shaftTransparency(peak: number): NumberSequence
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.07, 1 - peak),
		NumberSequenceKeypoint.new(0.65, 1 - peak * 0.7),
		NumberSequenceKeypoint.new(1, 1),
	})
end

-- Daylight through a window wall. `wallCF` is the wall's centre with local +Z
-- pointing out of the room. Each opening gets: a glowing pane of daylight in
-- the hole, a soft shaft sloping down into the room (crossed beam sheets in
-- three widths so the edges fall off), a spotlight pooling on the floor where
-- the shaft lands, and slow dust in the beam.
function AtmosphereManager.PlaceWindowLight(wallCF: CFrame, openings: { { x: number, y: number, w: number, h: number } }, parent: Instance): Model
	local cfg = AtmosphereManager.Config
	local model = Instance.new("Model")
	model.Name = "WindowLight"
	model.Parent = parent
	local color = cfg.WindowLightColor
	local inward = wallCF.LookVector -- local -Z: into the room
	local across = wallCF.RightVector
	local a = math.rad(cfg.WindowShaftAngle)
	local d = (inward * math.cos(a) - Vector3.yAxis * math.sin(a)).Unit
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { model }

	for _, o in ipairs(openings) do
		-- The daylight pane, set into the middle of the wall's thickness.
		prop(model, { Size = Vector3.new(o.w * 0.95, o.h * 0.95, 0.1), CFrame = wallCF * CFrame.new(o.x, o.y, 0),
			Color = color, Material = Enum.Material.Neon, Transparency = 0.38, CanQuery = false })

		local origin = (wallCF * CFrame.new(o.x, o.y, -1.1)).Position
		local hit = Workspace:Raycast(origin + d * 0.5, d * 40, rp)
		local endPos = if hit then hit.Position else origin + d * ((7 + o.y) / math.sin(a))
		local len = (endPos - origin).Magnitude

		local anchor = prop(model, { Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.lookAt(origin, origin + d), Transparency = 1, CanQuery = false })
		local spot = Instance.new("SpotLight")
		spot.Face = Enum.NormalId.Front
		spot.Angle = 55
		spot.Range = len + 8
		spot.Brightness = cfg.WindowLightBrightness
		spot.Color = color
		spot.Shadows = false
		spot.Parent = anchor

		-- Beam sheets: with FaceCamera off a beam's width runs along its
		-- attachments' Y axis. One sheet spans the window's width, one its
		-- height, each in three widths for a soft falloff.
		local tall = across:Cross(d).Unit
		local function sheet(widthAxis: Vector3, w0: number, w1: number)
			local xAxis = widthAxis:Cross(d).Unit
			local a0 = Instance.new("Attachment")
			a0.Parent = anchor
			a0.WorldCFrame = CFrame.fromMatrix(origin, xAxis, widthAxis)
			local a1 = Instance.new("Attachment")
			a1.Parent = anchor
			a1.WorldCFrame = CFrame.fromMatrix(endPos, xAxis, widthAxis)
			for i, k in ipairs({ 1, 0.68, 0.4 }) do
				local b = Instance.new("Beam")
				b.Attachment0 = a0
				b.Attachment1 = a1
				b.FaceCamera = false
				b.Width0 = w0 * k
				b.Width1 = w1 * k
				b.LightEmission = 1
				b.LightInfluence = 0
				b.Segments = 8
				b.Color = ColorSequence.new(color)
				b.Transparency = shaftTransparency(cfg.WindowShaftOpacity * (0.8 + i * 0.2))
				b.Parent = a0
			end
		end
		sheet(across, o.w, o.w * 1.25)
		sheet(tall, o.h * math.cos(a), o.h * math.cos(a) * 1.2)

		-- Dust drifting in the light.
		local dust = prop(model, { Size = Vector3.new(o.w, o.h * math.cos(a), len * 0.85),
			CFrame = CFrame.lookAt(origin + d * len * 0.5, origin + d * len), Transparency = 1, CanQuery = false })
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(color)
		e.LightEmission = 1
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0.05) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(4, 7)
		e.Speed = NumberRange.new(0.1, 0.35)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 2.5
		e.Parent = dust
	end
	return model
end

-- A chain of alternating links from `a` to `b`.
local CHAIN_IRON = Color3.fromRGB(58, 52, 50)
local function chain(parent: Instance, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	local links = math.max(1, math.floor(len / 0.55))
	local dir = CFrame.lookAt(a, b)
	for i = 0, links - 1 do
		local p = a:Lerp(b, (i + 0.5) / links)
		local link = prop(parent, { Size = Vector3.new(0.12, 0.34, 0.7),
			CFrame = CFrame.new(p) * dir.Rotation * CFrame.Angles(0, 0, if i % 2 == 0 then 0 else math.rad(90)),
			Color = CHAIN_IRON, Material = Enum.Material.Metal })
		link.CastShadow = false
	end
end

-- A hanging iron fire bowl: a wide bowl on four chains that meet above it,
-- one chain rising out of sight (no ceiling needed: the camera never sees
-- its top). Orange fire, embers and a hot coal glow — no PointLight.
function AtmosphereManager.PlaceHangingBrazier(pos: Vector3, parent: Instance, rng: Random): Model
	local model = Instance.new("Model")
	model.Name = "HangingBrazier"
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local c = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi), 0)
	-- Bowl: a rim ring over a tapered body and a small foot.
	local bowl = prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 3.2, 3.2), CFrame = c * flat,
		Color = Color3.fromRGB(42, 34, 32), Material = Enum.Material.Metal })
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.7, 2.4, 2.4), CFrame = c * CFrame.new(0, -0.6, 0) * flat,
		Color = Color3.fromRGB(36, 30, 28), Material = Enum.Material.Metal })
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 3.5, 3.5), CFrame = c * CFrame.new(0, 0.45, 0) * flat,
		Color = MEDALLION_GOLD, Material = Enum.Material.Metal })
	local coals = prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.7, 2.7), CFrame = c * CFrame.new(0, 0.5, 0) * flat,
		Color = Color3.fromRGB(255, 120, 40), Material = Enum.Material.Neon })
	local fire = Instance.new("Fire")
	fire.Color = Color3.fromRGB(255, 140, 40)
	fire.SecondaryColor = Color3.fromRGB(200, 40, 10)
	fire.Size = 6 + rng:NextNumber(0, 1.5)
	fire.Heat = 12
	fire.Parent = coals
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0.2, 0, 0)
	att.Parent = coals
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 90, 30))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(1, 2)
	embers.Speed = NumberRange.new(2, 5)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Acceleration = Vector3.new(0, 3, 0)
	embers.Rate = 8
	embers.Parent = att
	-- Four chains from the rim up to a ring, then one chain up out of view.
	local top = pos + Vector3.new(0, 3.6, 0)
	for i = 0, 3 do
		local a = i * math.pi / 2
		local rim = (c * CFrame.new(math.cos(a) * 1.55, 0.4, math.sin(a) * 1.55)).Position
		chain(model, rim, top)
	end
	prop(model, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.7, 0.7), CFrame = CFrame.new(top) * flat,
		Color = CHAIN_IRON, Material = Enum.Material.Metal })
	chain(model, top, top + Vector3.new(0, 40, 0))
	model.PrimaryPart = bowl
	model.Parent = parent
	return model
end

-- ── 2. Player Torch Light Attachment ─────────────────────────────────────────

function AtmosphereManager.AttachTorchLight(character: Model)
	local rootPart = (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart) :: BasePart?
	if not rootPart then
		-- Fast asynchronous check if rootPart hasn't loaded yet
		task.spawn(function()
			local rp = character:WaitForChild("HumanoidRootPart", 3) :: BasePart?
			if rp then
				AtmosphereManager.AttachTorchLight(character)
			end
		end)
		return
	end

	-- Torch switched off: strip any torch pieces already on the character.
	if not AtmosphereManager.Config.TorchEnabled then
		for _, name in ipairs({ "TorchLightMount", "TorchSpreadMount", "PlayerTorchLight", "TorchEmbersAttachment" }) do
			local existing = rootPart:FindFirstChild(name)
			if existing then existing:Destroy() end
		end
		return
	end

	-- Do not re-attach if light is already attached
	if rootPart:FindFirstChild("PlayerTorchLight", true) then
		return
	end

	-- 1. Create Warm PointLight (Dynamic Torch), hung above the head
	local cfg = AtmosphereManager.Config
	local lightMount = Instance.new("Attachment")
	lightMount.Name = "TorchLightMount"
	lightMount.Position = Vector3.new(0, cfg.TorchHeight or 6, 0)
	lightMount.Parent = rootPart
	local torchLight = Instance.new("PointLight")
	torchLight.Name = "PlayerTorchLight"
	torchLight.Color = cfg.TorchColor
	torchLight.Range = cfg.TorchRange
	torchLight.Brightness = cfg.TorchBrightness
	torchLight.Shadows = cfg.TorchShadows
	torchLight.Parent = lightMount

	-- A PointLight can't reach past 60 studs: a wide spotlight hung high
	-- above, pointing down, carries the warm pool much further out.
	if cfg.TorchSpreadRange and cfg.TorchSpreadRange > 0 then
		local spreadMount = Instance.new("Attachment")
		spreadMount.Name = "TorchSpreadMount"
		spreadMount.Position = Vector3.new(0, cfg.TorchSpreadHeight or 30, 0)
		spreadMount.Parent = rootPart
		local spread = Instance.new("SpotLight")
		spread.Name = "PlayerTorchSpread"
		spread.Face = Enum.NormalId.Bottom
		spread.Angle = cfg.TorchSpreadAngle or 150
		spread.Range = cfg.TorchSpreadRange
		spread.Brightness = cfg.TorchSpreadBrightness or 1
		spread.Color = cfg.TorchColor
		spread.Shadows = false
		spread.Parent = spreadMount
	end

	-- 2. Create Subtle Floating Torch Embers Attachment
	if cfg.TorchEmbers and not rootPart:FindFirstChild("TorchEmbersAttachment") then
		local att = Instance.new("Attachment")
		att.Name = "TorchEmbersAttachment"
		att.Position = Vector3.new(0.6, 1.2, -0.4) -- Off to upper-right torso like held torch
		att.Parent = rootPart

		local embers = Instance.new("ParticleEmitter")
		embers.Name = "TorchEmbers"
		embers.Texture = "rbxassetid://258129532" -- Sparkle/Ember particle
		embers.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 100)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 120, 30)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 10)),
		})
		embers.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.8, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		embers.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		embers.Lifetime = NumberRange.new(0.8, 1.4)
		embers.Rate = 6
		embers.Speed = NumberRange.new(1.0, 2.5)
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.VelocityInheritance = 0.2
		embers.Parent = att
	end

	print(`[AtmosphereManager] Torch light attached to character: {character.Name}`)
end

-- ── 3. Character Visual Outline ──────────────────────────────────────────────
-- One black Highlight around the whole character (armor, weapons and cape
-- included, as they're added). One per character, not per part: Roblox only
-- draws ~31 Highlights at once, and ability VFX need some for their outlines.

function AtmosphereManager.AttachCharacterOutline(character: Model)
	if character:FindFirstChild("CharacterOutline") then return end
	-- Clear per-part outlines from older builds.
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Highlight") and desc.Name == "PartOutline" then desc:Destroy() end
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "CharacterOutline"
	highlight.FillTransparency = 1 -- textures and colours untouched
	highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
	highlight.OutlineTransparency = 0
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.Adornee = character
	highlight.Parent = character
end

return AtmosphereManager
