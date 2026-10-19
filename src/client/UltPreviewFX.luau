--[[
	UltPreviewFX.luau
	Looping, lightweight "ultimate aura" effects for the class-selection preview,
	played around the posed preview character (client-only):

	  heavy_knight — Infernal Wrath: flames along the greatsword, rising embers,
	                 a turning ring of fire at the feet
	  ranger       — Rain of Arrows: coiled thorn vines, a green rune ring,
	                 drifting leaves and spores
	  cleric       — Divine Ascent: god-ray fan from above, warm backlight rim,
	                 light pool and dust
	  ice_mage     — Blizzard: shadow wisps, glowing blue eyes, ice crystal
	                 ring, frost mist and falling snow
	  mage         — Apocalypse: violet rune rings turning on the floor, a
	                 magic circle over his raised hand, arcane motes rising,
	                 bolts of light falling round him
	  martial_artist — crimson rings turning on the floor, ink rising

	And each class's entrance (CastPoses' preview: its moments come from
	CastPoses.previewBeats): the Rogue's smoke and tossed dagger, the Martial
	Artist's ink burst and burning fists, the Mage's descent and landing
	rune, the Gunslinger's glint, the Ranger's leaves and three arrows, the
	Cleric's beam of light and scepter, the Ice Mage's frozen enemies and
	frost, the Berserker's dragged sword, roar and change into the beast.

	UltPreviewFX.Start(character, classId) replaces any running preview;
	UltPreviewFX.Stop() removes it.
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local CastPoses = require(script.Parent:WaitForChild("CastPoses"))

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

local UltPreviewFX = {}

local current: { folder: Folder, conns: { RBXScriptConnection }, attachments: { Instance }, cleanups: { () -> () } }? = nil

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
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
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
	for k, v in pairs(props) do
		(pe :: any)[k] = v
	end
	pe.Parent = parent
	return pe
end

local function anchorAt(folder: Folder, cf: CFrame): BasePart
	return part(folder, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = cf })
end

local function light(parent: Instance, color: Color3, brightness: number, range: number)
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range, l.Shadows = color, brightness, range, false
	l.Parent = parent
end

-- Ring of segments lying on the ground; returns an updater(spin).
local function groundRing(folder: Folder, center: Vector3, radius: number, n: number, color: Color3, transparency: number, thick: number): (number) -> ()
	local segs = {}
	for i = 1, n do
		segs[i] = part(folder, { Color = color, Transparency = transparency })
	end
	return function(spin: number)
		local segLen = 2 * math.pi * radius / n * 0.75
		for i, s in ipairs(segs) do
			local a = (i / n) * math.pi * 2 + spin
			local p = center + Vector3.new(math.cos(a) * radius, 0.08, math.sin(a) * radius)
			s.Size = Vector3.new(thick, 0.05, segLen)
			s.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
		end
	end
end

local function groundUnder(root: BasePart, char: Model): Vector3
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { char }
	for _, child in ipairs(Workspace.Terrain:GetChildren()) do
		table.insert(ignore, child)
	end
	rp.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -12, 0), rp)
	return hit and hit.Position or (root.Position - Vector3.new(0, 3, 0))
end

-- ─── Per-class auras ────────────────────────────────────────────────────────
-- (`right` is the character's right; `screenRight` the camera's, flat, and
-- `toward` the camera. `at(t, fn)` runs fn `t` seconds after the start, unless
-- the preview has moved on; `beats` are the entrance's moments.)
type Ctx = { char: Model, root: BasePart, folder: Folder, ground: Vector3, fwd: Vector3, right: Vector3,
	screenRight: Vector3, toward: Vector3, beats: { [string]: number }, at: (number, () -> ()) -> (),
	onStep: ((number) -> ()) -> (), attach: (Instance) -> (), onCleanup: (() -> ()) -> () }

local AURAS: { [string]: (Ctx) -> () } = {}

AURAS.heavy_knight = function(c)
	local FIRE = Color3.fromRGB(255, 140, 40)
	-- Flames along the greatsword (the preview Tool), else along the right arm.
	task.spawn(function()
		local sword: Instance? = nil
		for _ = 1, 20 do
			sword = c.char:FindFirstChild("PreviewGreatsword")
			if sword then break end
			task.wait(0.1)
		end
		local host = sword or c.char:FindFirstChild("Right Arm") or c.char:FindFirstChild("RightHand")
		if not host then return end
		for _, d in ipairs((host :: Instance):GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Size.Magnitude > 1 then
				local a = Instance.new("Attachment")
				a.Parent = d
				c.attach(a)
				emitter(a, { Texture = TEX_FIRE, Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 70, 20)),
					LightEmission = 1, Size = seq(0, 0.9, 1, 0), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1, 3),
					Acceleration = Vector3.new(0, 8, 0), SpreadAngle = Vector2.new(20, 20), Rate = 30, Rotation = NumberRange.new(0, 360) })
				light(a, FIRE, 1.2, 8)
			end
		end
	end)
	-- Embers rising around the knight, and a turning ring of fire at the feet.
	local base = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 0.3, 0)))
	emitter(base, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), FIRE), LightEmission = 1,
		Size = seq(0, 0.25, 1, 0), Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top, Rate = 20 })
	light(base, FIRE, 1.5, 14)
	local ringA = groundRing(c.folder, c.ground, 4.2, 30, FIRE, 0.25, 0.3)
	local ringB = groundRing(c.folder, c.ground, 3.1, 24, Color3.fromRGB(255, 210, 120), 0.45, 0.15)
	c.onStep(function(t)
		ringA(t * 0.5)
		ringB(-t * 0.8)
	end)
end

AURAS.gunslinger = function(c)
	local GOLD = Color3.fromRGB(255, 200, 96)
	-- A revolver cylinder at the feet: a slow golden ring with six chambers.
	local ring = groundRing(c.folder, c.ground, 3.6, 28, GOLD, 0.35, 0.18)
	local chambers = {}
	for i = 1, 6 do
		chambers[i] = part(c.folder, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.55, Color = GOLD, Transparency = 0.15 })
	end
	-- A coin spinning over the off hand.
	local coin = part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.9, 0.9), Color = Color3.fromRGB(255, 205, 90),
		Material = Enum.Material.Metal })
	light(coin, GOLD, 1.2, 7)
	-- Gunpowder haze drifting at knee height.
	local haze = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 0.8, 0)))
	emitter(haze, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(255, 240, 200), GOLD), LightEmission = 1,
		Size = seq(0, 0.2, 1, 0), Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(0.5, 1.5), Rate = 8 })
	c.onStep(function(t)
		ring(t * 0.35)
		for i, ch in ipairs(chambers) do
			local a = (i / 6) * math.pi * 2 + t * 0.35
			ch.CFrame = CFrame.new(c.ground + Vector3.new(math.cos(a) * 3.6, 0.2, math.sin(a) * 3.6))
		end
		local hand = c.root.Position - c.right * 1.4 + c.fwd * 0.8 + Vector3.new(0, 1.2 + math.sin(t * 2) * 0.25, 0)
		coin.CFrame = CFrame.new(hand) * CFrame.Angles(0, t * 4, 0) * CFrame.Angles(t * 7, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
	end)
end

AURAS.swordsman = function(c)
	local GOLD = Color3.fromRGB(90, 150, 255) -- (the Sword Master's blue)
	local WHITE = Color3.fromRGB(225, 238, 255)
	-- Two counter-turning rings at the feet, and six spectral blades orbiting
	-- point-down around the Swordsman (the storm about to break). No lights.
	local ringA = groundRing(c.folder, c.ground, 3.6, 28, GOLD, 0.45, 0.12)
	local ringB = groundRing(c.folder, c.ground, 2.4, 20, WHITE, 0.6, 0.08)
	-- Four small, faint spectral swords hanging point-down, drifting round:
	-- a thin blade, a gold guard and a short grip each.
	local swords = {}
	for i = 1, 4 do
		swords[i] = {
			blade = part(c.folder, { Size = Vector3.new(0.2, 1.7, 0.05), Color = WHITE, Transparency = 0.4 }),
			guard = part(c.folder, { Size = Vector3.new(0.62, 0.07, 0.06), Color = GOLD, Transparency = 0.3 }),
			grip = part(c.folder, { Size = Vector3.new(0.07, 0.42, 0.07), Color = GOLD, Transparency = 0.45 }),
		}
	end
	local motes = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 0.6, 0)))
	emitter(motes, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, GOLD), LightEmission = 1,
		Size = seq(0, 0.16, 1, 0), Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(0.5, 1.2),
		EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(40, 40), Rate = 6 })
	c.onStep(function(t)
		ringA(t * 0.4)
		ringB(-t * 0.7)
		for i, s in ipairs(swords) do
			local a = (i / 4) * math.pi * 2 + t * 0.45
			local base = c.ground + Vector3.new(math.cos(a) * 3.9, 1.9 + math.sin(t * 1.6 + i * 1.7) * 0.2, math.sin(a) * 3.9)
			-- Face outward so the flat of the blade reads from the front.
			local cf = CFrame.lookAt(base, Vector3.new(c.ground.X, base.Y, c.ground.Z)) * CFrame.Angles(0, 0, math.rad(math.sin(t + i) * 6))
			s.blade.CFrame = cf
			s.guard.CFrame = cf * CFrame.new(0, 0.88, 0)
			s.grip.CFrame = cf * CFrame.new(0, 1.12, 0)
		end
	end)
end

AURAS.ranger = function(c)
	local LEAF = Color3.fromRGB(155, 245, 75)
	local BARK = Color3.fromRGB(60, 92, 42)
	-- Thorn vines coiled up around the feet (static, gently swaying).
	local vines = {}
	for v = 1, 6 do
		local a0 = (v / 6) * math.pi * 2
		local segs = {}
		for i = 1, 7 do
			segs[i] = part(c.folder, { Shape = Enum.PartType.Cylinder, Color = i % 2 == 0 and BARK or Color3.fromRGB(46, 72, 32), Material = Enum.Material.Wood })
		end
		local tip = part(c.folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.4, 0.4, 0.4), Color = LEAF })
		table.insert(vines, { a0 = a0, segs = segs, tip = tip, h = 2.5 + (v % 3) * 0.8 })
	end
	local rune = groundRing(c.folder, c.ground, 3.8, 28, LEAF, 0.4, 0.2)
	local runeB = groundRing(c.folder, c.ground, 2.6, 20, Color3.fromRGB(200, 255, 140), 0.55, 0.12)
	local spores = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 0.5, 0)))
	emitter(spores, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(210, 255, 140), LEAF), LightEmission = 0.9,
		Size = seq(0, 0.3, 1, 0), Lifetime = NumberRange.new(1.5, 2.5), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, Rate = 18, Rotation = NumberRange.new(0, 360) })
	light(spores, LEAF, 1.2, 12)
	c.onStep(function(t)
		rune(t * 0.4)
		runeB(-t * 0.7)
		for _, vine in ipairs(vines) do
			local prev = nil
			for i, s in ipairs(vine.segs) do
				local k = i / #vine.segs
				local a = vine.a0 + k * 2.2 + math.sin(t * 1.2 + vine.a0) * 0.08
				local r = 1.8 - k * 0.7
				local p = c.ground + Vector3.new(math.cos(a) * r, k * vine.h, math.sin(a) * r)
				if prev then
					local len = (p - prev).Magnitude
					local th = 0.32 * (1 - k * 0.6)
					s.Size = Vector3.new(len + th * 0.4, th, th)
					s.CFrame = CFrame.lookAt((prev + p) * 0.5, p) * CFrame.Angles(0, math.rad(90), 0)
				else
					s.Size = Vector3.new(0.1, 0.1, 0.1)
					s.CFrame = CFrame.new(p)
				end
				prev = p
			end
			vine.tip.CFrame = CFrame.new(prev :: Vector3)
		end
	end)
end

AURAS.cleric = function(c)
	local IVORY = Color3.fromRGB(255, 244, 215)
	-- God-ray fan converging on the Cleric from high behind.
	local source = c.root.Position - c.fwd * 12 + Vector3.new(0, 36, 0)
	for i = 1, 7 do
		local u = (i - 4) / 3
		local target = c.ground + c.right * (u * 3.5)
		local len = (target - source).Magnitude
		local w = 0.8 + (i % 3) * 0.6
		part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, w, w),
			CFrame = CFrame.lookAt((source + target) * 0.5, target) * CFrame.Angles(0, math.rad(90), 0),
			Color = IVORY, Transparency = 0.88 })
	end
	-- Warm backlight rim + light pool + dust.
	local rim = anchorAt(c.folder, CFrame.new(c.root.Position - c.fwd * 1.8 + Vector3.new(0, 2.4, 0)))
	light(rim, Color3.fromRGB(255, 214, 150), 3, 10)
	part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 8, 8),
		CFrame = CFrame.new(c.ground + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 205, 130), Transparency = 0.8 })
	emitter(rim, { Texture = TEX_SPARKLE, Color = ColorSequence.new(IVORY), LightEmission = 1,
		Size = seq(0, 0.12, 0.5, 0.18, 1, 0), Transparency = seq(0, 0.4, 1, 1), Lifetime = NumberRange.new(3, 5),
		Speed = NumberRange.new(0.2, 0.8), SpreadAngle = Vector2.new(180, 180), Rate = 20 })
	local halo = groundRing(c.folder, c.ground, 3.4, 30, Color3.fromRGB(255, 205, 95), 0.4, 0.2)
	c.onStep(function(t) halo(t * 0.3) end)
end

AURAS.ice_mage = function(c)
	local ICE = Color3.fromRGB(120, 220, 255)
	local EYE = Color3.fromRGB(70, 175, 255)
	-- The body itself goes black (pale blue-grey arms), clothing and textures
	-- hidden — clothing templates draw over part colour. Restored on Stop.
	local saved: { [Instance]: { [string]: any } } = {}
	for _, d in ipairs(c.char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
			local props: { [string]: any } = { Color = d.Color, Material = d.Material }
			if d:IsA("MeshPart") then props.TextureID = d.TextureID; d.TextureID = "" end
			saved[d] = props
			local n = string.lower(d.Name)
			local isArm = (string.find(n, "arm") ~= nil or string.find(n, "hand") ~= nil) and d.Parent == c.char
			d.Color = if isArm then Color3.fromRGB(96, 116, 146) else Color3.fromRGB(5, 7, 13)
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("Decal") or d:IsA("Texture") then
			saved[d] = { Transparency = d.Transparency }
			d.Transparency = 1
		elseif d:IsA("SpecialMesh") and d.TextureId ~= "" then
			saved[d] = { TextureId = d.TextureId }
			d.TextureId = ""
		elseif d:IsA("Shirt") then
			saved[d] = { ShirtTemplate = d.ShirtTemplate }
			d.ShirtTemplate = ""
		elseif d:IsA("Pants") then
			saved[d] = { PantsTemplate = d.PantsTemplate }
			d.PantsTemplate = ""
		elseif d:IsA("ShirtGraphic") then
			saved[d] = { Graphic = d.Graphic }
			d.Graphic = ""
		elseif d:IsA("SurfaceAppearance") then
			saved[d] = { Parent = d.Parent }
			d.Parent = nil
		end
	end
	c.onCleanup(function()
		for inst, props in pairs(saved) do
			if inst.Parent or props.Parent then
				for k, v in pairs(props) do (inst :: any)[k] = v end
			end
		end
	end)
	-- Black energy over the whole silhouette: every visible part plus a core shroud.
	local DARK = ColorSequence.new(Color3.fromRGB(4, 5, 10), Color3.fromRGB(16, 22, 40))
	local count = 0
	for _, d in ipairs(c.char:GetDescendants()) do
		if count >= 24 then break end
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 and d.Size.Magnitude > 0.6 then
			count += 1
			local size = math.clamp(d.Size.Magnitude * 0.8, 1, 3.5)
			local a = Instance.new("Attachment")
			a.Parent = d
			c.attach(a)
			emitter(a, { Texture = TEX_SMOKE, Color = DARK, LightEmission = 0,
				Size = seq(0, size * 0.7, 1, size * 1.3), Transparency = seq(0, 1, 0.15, 0.2, 0.7, 0.5, 1, 1),
				Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(0.4, 1.8), SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 2, 0), Rate = math.clamp(size * 7, 8, 26), Rotation = NumberRange.new(0, 360) })
		end
	end
	local shroud = Instance.new("Attachment")
	shroud.Position = Vector3.new(0, 0.6, 0)
	shroud.Parent = c.root
	c.attach(shroud)
	emitter(shroud, { Texture = TEX_SMOKE, Color = DARK, LightEmission = 0,
		Size = seq(0, 2.5, 1, 6), Transparency = seq(0, 1, 0.15, 0.3, 0.75, 0.55, 1, 1),
		Lifetime = NumberRange.new(0.7, 1.1), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 2.5, 0), Rate = 24, Rotation = NumberRange.new(0, 360) })
	-- Ink strokes flung sideways off the silhouette.
	local INK = ColorSequence.new(Color3.new(0, 0, 0), Color3.fromRGB(10, 12, 20))
	for _, name in ipairs({ "Torso", "UpperTorso", "Head", "Left Arm", "Right Arm" }) do
		local limb = c.char:FindFirstChild(name)
		if limb and limb:IsA("BasePart") then
			for _, face in ipairs({ Enum.NormalId.Left, Enum.NormalId.Right }) do
				local a = Instance.new("Attachment")
				a.Parent = limb
				c.attach(a)
				emitter(a, { Texture = "rbxassetid://1053548563", Color = INK, LightEmission = 0,
					Orientation = Enum.ParticleOrientation.VelocityParallel, Size = seq(0, 0.4, 1, 0),
					Transparency = seq(0, 0, 1, 1), Lifetime = NumberRange.new(0.12, 0.25), Speed = NumberRange.new(10, 20),
					SpreadAngle = Vector2.new(30, 50), EmissionDirection = face, Rate = 14 })
			end
		end
	end
	-- Glowing blue eyes.
	local head = c.char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		for side = -1, 1, 2 do
			local eye = part(c.folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.18, 0.18), Color = EYE,
				Anchored = false, Massless = true,
				CFrame = head.CFrame * CFrame.new(side * 0.2, 0.12,
					-(if head:FindFirstChildOfClass("SpecialMesh") then 0.6 else head.Size.Z * 0.5) - 0.02) })
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = head, eye
			w.Parent = eye
			light(eye, EYE, 1.5, 5)
		end
	end
	-- Ice crystal ring, frost mist and falling snow.
	local crystals = {}
	for i = 1, 7 do
		local cr = part(c.folder, { ClassName = "WedgePart", Size = Vector3.new(0.3, 1.8 + (i % 3) * 0.6, 0.9),
			Color = i % 2 == 0 and Color3.fromRGB(200, 245, 255) or ICE, Material = Enum.Material.Glass, Transparency = 0.2 })
		crystals[i] = cr
	end
	local mist = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 0.5, 0)))
	emitter(mist, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(230, 245, 255)), LightEmission = 0.3,
		Size = seq(0, 2, 1, 5), Transparency = seq(0, 1, 0.3, 0.6, 1, 1), Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 10), Rate = 5 })
	local sky = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 12, 0)))
	emitter(sky, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), ICE), LightEmission = 0.6,
		Size = seq(0, 0.25, 1, 0.15), Lifetime = NumberRange.new(3, 4), Speed = NumberRange.new(3, 5),
		SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Bottom, Acceleration = Vector3.new(1.5, 0, 0), Rate = 30 })
	light(mist, ICE, 1.2, 12)
	c.onStep(function(t)
		for i, cr in ipairs(crystals) do
			local a = (i / #crystals) * math.pi * 2 + t * 0.25
			local p = c.ground + Vector3.new(math.cos(a) * 3.4, cr.Size.Y * 0.45, math.sin(a) * 3.4)
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			cr.CFrame = CFrame.lookAt(p, p + out) * CFrame.Angles(math.rad(-20), 0, 0)
		end
	end)
end

AURAS.mage = function(c)
	local VIOLET = Color3.fromRGB(170, 90, 255)
	local BLUE = Color3.fromRGB(96, 120, 255)
	local PALE = Color3.fromRGB(232, 206, 255)
	-- Two rune rings on the floor, turning against each other, and the star
	-- between them.
	local outer = groundRing(c.folder, c.ground, 4.6, 40, VIOLET, 0.15, 0.22)
	local inner = groundRing(c.folder, c.ground, 3.3, 30, PALE, 0.35, 0.12)
	local star = {}
	for i = 1, 8 do star[i] = part(c.folder, { Color = VIOLET, Transparency = 0.25 }) end
	-- A small circle of light over the raised hand.
	local hand = c.char:FindFirstChild("Right Arm") or c.char:FindFirstChild("RightHand")
	local halo = {}
	for i = 1, 20 do halo[i] = part(c.folder, { Color = PALE, Transparency = 0.1 }) end
	-- Motes rising round him; a violet glow.
	local motes = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 0.5, 0)))
	motes.Size = Vector3.new(8, 0.2, 8)
	emitter(motes, { Texture = TEX_SPARKLE, Color = ColorSequence.new(PALE, BLUE), LightEmission = 1, Size = seq(0, 0.25, 1, 0),
		Lifetime = NumberRange.new(1.2, 2.2), Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, 1.5, 0),
		SpreadAngle = Vector2.new(15, 15), Rate = 22, Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
	light(motes, VIOLET, 1.4, 14)
	-- Bolts of light falling round him now and then.
	local bolts = {}
	for i = 1, 4 do
		bolts[i] = { p = part(c.folder, { Color = VIOLET, Transparency = 1, Size = Vector3.new(0.3, 5, 0.3) }), t = i * 0.37, at = c.ground }
	end
	c.onStep(function(t)
		outer(t * 0.5)
		inner(-t * 0.8)
		local sr = 3.9
		for i, s in ipairs(star) do
			local k = (i - 1) % 4
			local sq = if i > 4 then math.pi / 4 else 0
			local a1 = k / 4 * math.pi * 2 + sq + t * 0.3
			local a2 = (k + 1) / 4 * math.pi * 2 + sq + t * 0.3
			local p1 = c.ground + Vector3.new(math.cos(a1) * sr, 0.1, math.sin(a1) * sr)
			local p2 = c.ground + Vector3.new(math.cos(a2) * sr, 0.1, math.sin(a2) * sr)
			s.Size = Vector3.new(0.12, 0.05, (p2 - p1).Magnitude)
			s.CFrame = CFrame.lookAt((p1 + p2) / 2, p2)
		end
		if hand and hand:IsA("BasePart") then
			local top = (hand :: BasePart).CFrame * CFrame.new(0, -1.6, 0)
			local c0 = CFrame.new(top.Position) * CFrame.Angles(0, t * 1.2, 0)
			for i, h in ipairs(halo) do
				local a = i / #halo * math.pi * 2
				local p = c0 * CFrame.new(math.cos(a) * 1.3, 0, math.sin(a) * 1.3)
				h.Size = Vector3.new(0.08, 0.05, 0.42)
				h.CFrame = CFrame.lookAt(p.Position, p.Position + (c0.Rotation * Vector3.new(-math.sin(a), 0, math.cos(a))))
			end
		end
		for _, b in ipairs(bolts) do
			local k = ((t + b.t) % 1.5) / 1.5
			if k < 0.12 then
				if k < 0.02 then
					local a = math.random() * math.pi * 2
					b.at = c.ground + Vector3.new(math.cos(a), 0, math.sin(a)) * (5 + math.random() * 4)
				end
				local u = k / 0.12
				b.p.CFrame = CFrame.new(b.at + Vector3.new(0, 22 * (1 - u) + 2.5, 0))
				b.p.Transparency = 0.1
			else
				b.p.Transparency = 1
			end
		end
	end)
end

AURAS.martial_artist = function(c)
	local CRIMSON = Color3.fromRGB(226, 26, 46)
	local HOT = Color3.fromRGB(255, 108, 104)
	local INK = Color3.fromRGB(10, 8, 12)
	-- Two rings of crimson on the floor turning against each other.
	local outer = groundRing(c.folder, c.ground, 4.4, 40, CRIMSON, 0.15, 0.22)
	local inner = groundRing(c.folder, c.ground, 3.0, 30, HOT, 0.35, 0.12)
	-- Wisps of ink rising off the floor round him.
	local motes = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 0.5, 0)))
	motes.Size = Vector3.new(7, 0.2, 7)
	emitter(motes, { Texture = "rbxassetid://16955854038", FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(INK), LightEmission = 0, Size = seq(0, 0.6, 1, 1.4),
		Transparency = seq(0, 0.4, 1, 1), Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(1.5, 3),
		Rotation = NumberRange.new(0, 360), SpreadAngle = Vector2.new(15, 15), Rate = 10, Shape = Enum.ParticleEmitterShape.Box,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
	c.onStep(function(t)
		outer(t * 0.6)
		inner(-t * 0.9)
	end)
end

-- ─── Entrances ──────────────────────────────────────────────────────────────
-- The effects on each class's entrance (CastPoses' preview), on its named
-- moments (CastPoses.previewBeats): smoke, an ink burst, the tossed dagger,
-- landing runes and leaves, a glint, three arrows, the scepter in the light,
-- frozen enemies and the frost she leaves walking between them.
local INK_TEX = "rbxassetid://16955854038"   -- (the pack's ash: black brush strokes, 4x4)
local FLAME_TEX = "rbxassetid://13818306392" -- (the pack's fire, 4x4)
local FLIP = Enum.ParticleFlipbookLayout.Grid4x4
local ONESHOT = Enum.ParticleFlipbookMode.OneShot

local ENTRANCES: { [string]: (Ctx) -> () } = {}

-- A flat ring on the floor swelling out from `r0` to `r1` and fading.
local function ringOut(c: Ctx, center: Vector3, r0: number, r1: number, dur: number, color: Color3, thick: number)
	local n = 28
	local segs = {}
	for i = 1, n do segs[i] = part(c.folder, { Color = color, Transparency = 0.1 }) end
	local t0 = os.clock()
	local done = false
	c.onStep(function()
		if done then return end
		local u = math.clamp((os.clock() - t0) / dur, 0, 1)
		local e = 1 - (1 - u) ^ 3
		local r = r0 + (r1 - r0) * e
		local segLen = 2 * math.pi * r / n * 0.8
		for i, s in ipairs(segs) do
			local a = (i / n) * math.pi * 2
			local p = center + Vector3.new(math.cos(a) * r, 0.1, math.sin(a) * r)
			s.Size = Vector3.new(thick, 0.05, segLen)
			s.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
			s.Transparency = 0.1 + 0.9 * u
		end
		if u >= 1 then
			done = true
			for _, s in ipairs(segs) do s:Destroy() end
		end
	end)
end

-- A ball of light swelling and fading at `pos`.
local function flare(c: Ctx, pos: Vector3, size: number, dur: number, color: Color3)
	local b = part(c.folder, { Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.3, CFrame = CFrame.new(pos), Color = color, Transparency = 0.1 })
	TweenService:Create(b, TweenInfo.new(dur, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(b, dur + 0.05)
end

-- A burst of particles at `cf` (a holder `box` big), cleaned up after.
local function burst(c: Ctx, cf: CFrame, box: Vector3, n: number, props: { [string]: any })
	local holder = anchorAt(c.folder, cf)
	holder.Size = box
	props.Rate = 0
	props.Shape = props.Shape or Enum.ParticleEmitterShape.Box
	props.ShapeStyle = props.ShapeStyle or Enum.ParticleEmitterShapeStyle.Volume
	local e = emitter(holder, props)
	e:Emit(n)
	Debris:AddItem(holder, e.Lifetime.Max + 0.3)
end

local function torsoOf(c: Ctx): BasePart?
	return (c.char:FindFirstChild("Torso") or c.char:FindFirstChild("UpperTorso")) :: BasePart?
end

local function fistOf(c: Ctx, side: string): Vector3?
	local arm = c.char:FindFirstChild(side) :: BasePart?
	return if arm then (arm.CFrame * CFrame.new(0, -1.05, 0)).Position else nil
end

-- The preview weapon (ClassLook's tool `toolName`) turned in the hand about the
-- grip's side-to-side axis (round a finger through the trigger guard; end over
-- end for a blade): returns spin(radians), or nil without the weapon. The arm
-- stays where the pose puts it; the grip goes back as it was when the preview ends.
local function gripOf(c: Ctx, toolName: string): ((number) -> ())?
	local tool = c.char:FindFirstChild(toolName)
	if not tool then return nil end
	for _, side in ipairs({ "Right Arm", "Left Arm", "RightHand", "LeftHand" }) do
		local hand = c.char:FindFirstChild(side)
		for _, w in ipairs(if hand then hand:GetChildren() else {}) do
			if w.Name == "LookGrip" and w:IsA("Weld") and w.Part1 and w.Part1:IsDescendantOf(tool) then
				local weld = w :: Weld
				local base = weld.C0
				local last = 0
				c.onCleanup(function()
					if weld.Parent then weld.C0 = base end
				end)
				return function(angle: number)
					if angle == last then return end
					last = angle
					weld.C0 = base * CFrame.Angles(angle, 0, 0)
				end
			end
		end
	end
	return nil
end

-- 0..1, eased, over `len` seconds from `at` in every `period` (0 otherwise).
local function sweep(t: number, period: number, at: number, len: number): number
	local u = ((t % period) - at) / len
	if u <= 0 or u >= 1 then return 0 end
	return u * u * (3 - 2 * u)
end

-- A flat pointed blade of two wedges (an arrowhead, a ray of the sun, a
-- leaf): its base's middle at `base`, pointing along `dir`, `w` wide, `thick`
-- thick across `flatAxis` (square to `dir`). Returns one of its halves.
local function spike(parent: Instance, base: Vector3, dir: Vector3, len: number, w: number, thick: number, flatAxis: Vector3,
	props: { [string]: any }): BasePart
	local back = -dir.Unit
	local x = flatAxis.Unit
	local frame = CFrame.fromMatrix(base, x, back:Cross(x), back)
	local first: BasePart? = nil
	for _, side in ipairs({ 1, -1 }) do
		local pr = table.clone(props)
		pr.ClassName = "WedgePart"
		pr.Size = Vector3.new(thick, w / 2, len)
		-- (a wedge is tall at its back, coming to an edge at its front: two,
		-- one upside down, back to back make the point)
		pr.CFrame = frame * CFrame.new(0, side * w / 4, -len / 2) * (if side < 0 then CFrame.Angles(0, 0, math.pi) else CFrame.identity)
		local made = part(parent, pr)
		first = first or made
	end
	return first :: BasePart
end

-- ── Martial Artist: ink bursts off the floor as he plants his feet; crimson
-- energy kindles round his fists and stays.
ENTRANCES.martial_artist = function(c)
	local CRIMSON = Color3.fromRGB(226, 26, 46)
	local HOT = Color3.fromRGB(255, 108, 104)
	c.at(c.beats.ink or 0.75, function()
		burst(c, CFrame.new(c.ground + Vector3.new(0, 0.4, 0)), Vector3.new(3, 0.2, 3), 26, {
			Texture = INK_TEX, FlipbookLayout = FLIP, FlipbookMode = ONESHOT, Color = ColorSequence.new(Color3.fromRGB(8, 6, 10)),
			LightEmission = 0, Size = seq(0, 1, 0.4, 2.6, 1, 3.2), Transparency = seq(0, 0, 0.7, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(80, 80),
			EmissionDirection = Enum.NormalId.Top, Drag = 5, Rotation = NumberRange.new(0, 360) })
		ringOut(c, c.ground, 1, 4.5, 0.45, CRIMSON, 0.3)
	end)
	c.at(c.beats.fists or 0.75, function()
		for _, side in ipairs({ "Right Arm", "Left Arm" }) do
			local arm = c.char:FindFirstChild(side)
			if arm then
				local a = Instance.new("Attachment")
				a.Position = Vector3.new(0, -1.1, 0)
				a.Parent = arm
				c.attach(a)
				emitter(a, { Texture = FLAME_TEX, FlipbookLayout = FLIP, FlipbookMode = ONESHOT, Color = ColorSequence.new(HOT, CRIMSON),
					LightEmission = 0.5, Size = seq(0, 0.45, 0.4, 0.85, 1, 0), Transparency = seq(0, 0.25, 1, 1),
					Lifetime = NumberRange.new(0.25, 0.4), Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.new(0, 4, 0),
					SpreadAngle = Vector2.new(30, 30), Rotation = NumberRange.new(0, 360), Rate = 20 })
				emitter(a, { Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, CRIMSON), LightEmission = 1, Size = seq(0, 0.16, 1, 0),
					Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(180, 180), Rate = 8 })
			end
		end
	end)
end

-- ── Rogue: a burst of smoke over the platform; the dagger tossed up spinning
-- (a stand-in flies, trailing crimson, while the real one is hidden) and back
-- into his hand.
ENTRANCES.rogue = function(c)
	local CRIMSON = Color3.fromRGB(170, 70, 255) -- (his shadow purple)
	-- (a pale grey-violet, unlit, so it reads against the night)
	local SMOKE = ColorSequence.new(Color3.fromRGB(176, 168, 190), Color3.fromRGB(100, 94, 114))
	local SHADE = ColorSequence.new(Color3.fromRGB(130, 122, 142), Color3.fromRGB(72, 66, 84))
	c.at(c.beats.smoke or 0, function()
		-- the cloud he's hidden in, thinning as he rises out of it
		burst(c, CFrame.new(c.ground + Vector3.new(0, 2.2, 0)), Vector3.new(2.5, 3, 2.5), 18, {
			Texture = TEX_SMOKE, Color = SMOKE, LightEmission = 0.1, Size = seq(0, 5, 0.5, 7, 1, 8.5),
			Transparency = seq(0, 0, 0.55, 0.15, 1, 1), Lifetime = NumberRange.new(1.1, 1.5), Speed = NumberRange.new(0.5, 2),
			SpreadAngle = Vector2.new(180, 180), Drag = 2, Acceleration = Vector3.new(0, 0.8, 0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-25, 25) })
		-- rolling out across the platform
		burst(c, CFrame.new(c.ground + Vector3.new(0, 0.8, 0)), Vector3.new(3, 0.5, 3), 36, {
			Texture = TEX_SMOKE, Color = SMOKE, LightEmission = 0.1, Size = seq(0, 3, 0.4, 5.5, 1, 7.5),
			Transparency = seq(0, 0.05, 0.6, 0.35, 1, 1), Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(8, 15),
			EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(80, 80), Drag = 3.2, Acceleration = Vector3.new(0, 0.6, 0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40) })
		-- darker curls inside it, for depth
		burst(c, CFrame.new(c.ground + Vector3.new(0, 1.2, 0)), Vector3.new(3, 1.5, 3), 14, {
			Texture = TEX_SMOKE, Color = SHADE, Size = seq(0, 2.5, 1, 5.5), Transparency = seq(0, 0.2, 0.6, 0.45, 1, 1),
			Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(3, 7), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(70, 70), Drag = 3, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60) })
		burst(c, CFrame.new(c.ground + Vector3.new(0, 1, 0)), Vector3.new(4, 1, 4), 14, {
			Texture = TEX_SPARKLE, Color = ColorSequence.new(CRIMSON), LightEmission = 1, Size = seq(0, 0.25, 1, 0),
			Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180) })
	end)
	-- a low puff across the floor as he drops into his crouch, and a little
	-- smoke left curling round his feet
	local toss, catch = c.beats.toss or 1.12, c.beats.catch or 1.67
	c.at(catch + 0.28, function()
		burst(c, CFrame.new(c.ground + Vector3.new(0, 0.4, 0)), Vector3.new(2, 0.2, 2), 16, {
			Texture = TEX_SMOKE, Color = SMOKE, Size = seq(0, 1.5, 1, 4), Transparency = seq(0, 0.25, 1, 1),
			Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(6, 10), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(88, 88), Drag = 4, Rotation = NumberRange.new(0, 360) })
		local feet = Instance.new("Attachment")
		feet.Position = Vector3.new(0, c.ground.Y - c.root.Position.Y + 0.3, 0)
		feet.Parent = c.root
		c.attach(feet)
		emitter(feet, { Texture = TEX_SMOKE, Color = SHADE, Size = seq(0, 1.2, 1, 3.2), Transparency = seq(0, 1, 0.3, 0.6, 1, 1),
			Lifetime = NumberRange.new(1.5, 2.2), Speed = NumberRange.new(0.8, 1.6), EmissionDirection = Enum.NormalId.Top,
			SpreadAngle = Vector2.new(88, 88), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-20, 20), Rate = 4 })
	end)
	-- now and then the dagger flips over in his hand (end over end; the arm stays put)
	local flip = gripOf(c, "Look_rogue")
	local idle = c.beats.idle
	if flip and idle then
		c.onStep(function(t)
			flip(if t < idle then 0 else -sweep(t - idle, 4.5, 2.5, 0.4) * 2 * math.pi)
		end)
	end
	c.at(toss, function()
		local tool = c.char:FindFirstChild("Look_rogue")
		local arm = c.char:FindFirstChild("Right Arm") :: BasePart?
		if not (tool and arm) then return end
		local handle = (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart", true)) :: BasePart?
		if not handle then return end
		-- the stand-in: a copy of every visible piece, flown as one
		local fly = Instance.new("Model")
		fly.Name = "TossedDagger"
		local hidden: { BasePart } = {}
		for _, p in ipairs(tool:GetDescendants()) do
			if p:IsA("BasePart") then
				local cp = p:Clone()
				for _, d in ipairs(cp:GetDescendants()) do
					if d:IsA("JointInstance") or d:IsA("WeldConstraint") or d:IsA("Constraint") then d:Destroy() end
				end
				cp.Anchored, cp.CanCollide, cp.CanQuery, cp.CanTouch = true, false, false, false
				cp.Parent = fly
				if p == handle then fly.PrimaryPart = cp end
				p.LocalTransparencyModifier = 1
				table.insert(hidden, p)
			end
		end
		if not fly.PrimaryPart then fly:Destroy(); return end
		fly.Parent = c.folder
		local function reveal()
			for _, p in ipairs(hidden) do
				if p.Parent then p.LocalTransparencyModifier = 0 end
			end
		end
		c.onCleanup(reveal)
		-- a crimson streak off the spinning blade
		local pp = fly.PrimaryPart :: BasePart
		local half = math.max(pp.Size.X, pp.Size.Y, pp.Size.Z) * 0.5
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, half, 0), Vector3.new(0, -half, 0)
		a0.Parent, a1.Parent = pp, pp
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(Color3.fromRGB(225, 170, 255), CRIMSON)
		tr.Transparency = seq(0, 0.2, 1, 1)
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.Lifetime = 0.18
		tr.Parent = pp
		local start = fly:GetPivot()
		local t0 = os.clock()
		local dur = math.max(catch - toss, 0.2)
		local caught = false
		c.onStep(function()
			if caught then return end
			local u = math.clamp((os.clock() - t0) / dur, 0, 1)
			local hand = (arm.CFrame * CFrame.new(0, -1, 0)).Position
			local pos = start.Position:Lerp(hand, u) + Vector3.new(0, math.sin(math.pi * u) * 5.5, 0)
			fly:PivotTo(CFrame.new(pos) * start.Rotation * CFrame.Angles(u * math.pi * 6, 0, 0))
			if u >= 1 then
				caught = true
				fly:Destroy()
				reveal()
				flare(c, hand, 1.6, 0.18, Color3.fromRGB(230, 200, 255))
			end
		end)
	end)
end

-- ── Mage: violet motes streaming off him as he floats down; a rune flashing
-- out round his feet as he lands; the book flares as he raises his hand.
ENTRANCES.mage = function(c)
	local VIOLET = Color3.fromRGB(170, 90, 255)
	local PALE = Color3.fromRGB(232, 206, 255)
	local torso = torsoOf(c)
	local trail: ParticleEmitter? = nil
	if torso then
		local a = Instance.new("Attachment")
		a.Parent = torso
		c.attach(a)
		trail = emitter(a, { Texture = TEX_SPARKLE, Color = ColorSequence.new(PALE, VIOLET), LightEmission = 1, Size = seq(0, 0.35, 1, 0),
			Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(0.5, 2), SpreadAngle = Vector2.new(180, 180), Rate = 40 })
	end
	c.at(c.beats.land or 1.75, function()
		if trail then trail.Enabled = false end
		ringOut(c, c.ground, 0.8, 4.2, 0.55, VIOLET, 0.25)
		ringOut(c, c.ground, 0.5, 2.8, 0.45, PALE, 0.15)
		burst(c, CFrame.new(c.ground + Vector3.new(0, 0.3, 0)), Vector3.new(3, 0.2, 3), 24, {
			Texture = TEX_SPARKLE, Color = ColorSequence.new(PALE, VIOLET), LightEmission = 1, Size = seq(0, 0.3, 1, 0),
			Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(70, 70),
			EmissionDirection = Enum.NormalId.Top, Drag = 3 })
	end)
	c.at(c.beats.open or 2.3, function()
		local core = c.char:FindFirstChild("GrimoireCore", true) :: BasePart?
		local at = if core then core.Position else (c.root.Position - c.right * 1.6)
		flare(c, at, 3, 0.35, PALE)
		burst(c, CFrame.new(at), Vector3.one * 0.5, 20, {
			Texture = TEX_SPARKLE, Color = ColorSequence.new(PALE, VIOLET), LightEmission = 1, Size = seq(0, 0.25, 1, 0),
			Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180), Drag = 2 })
	end)
end

-- ── Gunslinger: the revolver spinning round his finger as he walks in (the
-- gun turns in his hand; his arm stays down by his hip), a glint off it as he
-- catches it, and now and then it twirls again.
ENTRANCES.gunslinger = function(c)
	local GOLD = Color3.fromRGB(255, 220, 140)
	local walk, catch, idle = c.beats.walk or 0.05, c.beats.catch or 2.55, c.beats.idle or 2.93
	local spin = gripOf(c, "Look_gunslinger")
	if spin then
		-- (whole turns, so it comes round right as he catches it: forward, like a wheel rolling)
		local turns = math.max(1, math.floor((catch - walk) * 2.4 + 0.5))
		c.onStep(function(t)
			local a = 0
			if t >= walk and t < catch then
				a = -(t - walk) / (catch - walk) * turns * 2 * math.pi
			elseif t >= idle then
				-- two quick turns every 6 s (between the hammer fannings)
				a = -sweep(t - idle, 6, 4, 0.55) * 4 * math.pi
			end
			spin(a)
		end)
	end
	c.at(catch, function()
		local tool = c.char:FindFirstChild("Look_gunslinger")
		local h = tool and (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart", true)) :: BasePart?
		local at = if h then h.Position else (fistOf(c, "Right Arm") or c.root.Position)
		local cam = Workspace.CurrentCamera.CFrame
		-- a four-pointed star turned to the camera, flashing and shrinking away
		for _, spin in ipairs({ 0, 90 }) do
			local s = part(c.folder, { Size = Vector3.new(0.12, 2.6, 0.05), Color = Color3.new(1, 1, 1),
				CFrame = CFrame.lookAt(at, cam.Position) * CFrame.Angles(0, 0, math.rad(spin + 20)) })
			TweenService:Create(s, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.02, 0.4, 0.02), Transparency = 1 }):Play()
			Debris:AddItem(s, 0.4)
		end
		flare(c, at, 1.4, 0.2, GOLD)
	end)
end

-- ── Ranger: leaves scattering as she lands; three arrows drawn from the
-- quiver, glowing faintly green, nocked as she draws, lying from her drawing
-- hand across the bow.
local function buildArrow(folder: Instance): Model
	local m = Instance.new("Model")
	m.Name = "PreviewArrow"
	local LEAF = Color3.fromRGB(120, 235, 80)
	-- (pointing along -Z, its middle at the origin: the nock 1.4 behind, the tip 1.7 ahead)
	part(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.75, 0.09, 0.09), Color = Color3.fromRGB(122, 88, 54),
		Material = Enum.Material.Wood, CFrame = CFrame.new(0, 0, 0.02) * CFrame.Angles(0, math.rad(90), 0) })
	-- a four-bladed broadhead, glowing
	local base = Vector3.new(0, 0, -1.32)
	local head = spike(m, base, Vector3.new(0, 0, -1), 0.4, 0.24, 0.035, Vector3.xAxis, { Color = LEAF })
	spike(m, base, Vector3.new(0, 0, -1), 0.4, 0.24, 0.035, Vector3.yAxis, { Color = LEAF })
	part(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 0.12, 0.12), Color = Color3.fromRGB(70, 74, 66),
		Material = Enum.Material.Metal, CFrame = CFrame.new(0, 0, -1.3) * CFrame.Angles(0, math.rad(90), 0) })
	-- three swept feathers, and the nock
	for k = 0, 2 do
		part(m, { ClassName = "WedgePart", Size = Vector3.new(0.025, 0.15, 0.5), Color = Color3.fromRGB(96, 168, 74),
			Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(0, 0, 1.08) * CFrame.Angles(0, 0, math.rad(k * 120)) * CFrame.new(0, 0.12, 0) })
	end
	part(m, { Size = Vector3.new(0.1, 0.1, 0.08), Color = Color3.fromRGB(40, 36, 30), Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(0, 0, 1.42) })
	emitter(head, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(210, 255, 160), LEAF), LightEmission = 1,
		Size = seq(0, 0.2, 1, 0), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(0.2, 0.8), SpreadAngle = Vector2.new(180, 180),
		Rate = 6 })
	m.WorldPivot = CFrame.identity
	m.Parent = folder
	return m
end

ENTRANCES.ranger = function(c)
	local LEAF = Color3.fromRGB(130, 220, 70)
	c.at(c.beats.land or 0.63, function()
		burst(c, CFrame.new(c.ground + Vector3.new(0, 0.5, 0)), Vector3.new(3, 0.2, 3), 30, {
			Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(180, 240, 90), Color3.fromRGB(70, 140, 40)),
			LightEmission = 0.4, Size = seq(0, 0.45, 1, 0.2), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(6, 12),
			SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, -14, 0),
			Drag = 1.5, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200) })
		ringOut(c, c.ground, 1, 3.6, 0.4, LEAF, 0.2)
	end)
	local at, nock = c.beats.arrows or 1.15, c.beats.nock or 1.3
	c.at(at, function()
		local ra = c.char:FindFirstChild("Right Arm") :: BasePart?
		local la = c.char:FindFirstChild("Left Arm") :: BasePart?
		if not (ra and la) then return end
		local arrows: { Model } = {}
		for i = 1, 3 do arrows[i] = buildArrow(c.folder) end
		flare(c, (ra.CFrame * CFrame.new(0, -1.05, 0)).Position, 1.4, 0.25, LEAF)
		local t0 = os.clock()
		c.onStep(function()
			local rf = (ra.CFrame * CFrame.new(0, -1.05, 0)).Position
			local lf = (la.CFrame * CFrame.new(0, -1.05, 0)).Position
			-- in her hand: gripped near the nocks, pointing on out the way her arm does
			local held = -ra.CFrame.UpVector
			-- on the bow: from her drawing hand through the bow hand
			local span = lf - rf
			local onBow = if span.Magnitude > 0.2 then span.Unit else held
			local k = math.clamp((os.clock() - t0 - (nock - at)) / 0.2, 0, 1)
			k = k * k * (3 - 2 * k)
			local dir = held:Lerp(onBow, k)
			dir = if dir.Magnitude > 0.05 then dir.Unit else onBow
			local up = Vector3.yAxis - dir * dir.Y
			if up.Magnitude < 0.1 then up = ra.CFrame.LookVector - dir * dir:Dot(ra.CFrame.LookVector) end
			up = up.Unit
			for i, m in ipairs(arrows) do
				local f = i - 2
				-- fanned in her hand; on the bow near parallel, one above another,
				-- resting along the top of her bow arm (not buried in it)
				local a = math.rad(f * (7 - 4 * k))
				local d = dir * math.cos(a) + up * math.sin(a)
				local nockAt = rf + up * ((0.58 + f * 0.09) * k) - d * (0.35 * (1 - k))
				local mid = nockAt + d * 1.4
				m:PivotTo(CFrame.lookAt(mid, mid + d, up))
			end
		end)
	end)
end

-- ── Cleric: a beam of golden light comes down round him and a scepter forms
-- in it, hanging in the air; he takes it, and holds it upright in both hands.
local function buildScepter(folder: Instance): Model
	local m = Instance.new("Model")
	m.Name = "PreviewScepter"
	local GOLD = { Color = Color3.fromRGB(228, 180, 76), Material = Enum.Material.SmoothPlastic, Reflectance = 0.18 }
	local GLOW = Color3.fromRGB(255, 236, 170)
	local function gold(props: { [string]: any }): { [string]: any }
		for k, v in pairs(GOLD) do
			if props[k] == nil then props[k] = v end
		end
		return props
	end
	-- a length of rod standing from y0 to y1, `d` thick
	local function rod(y0: number, y1: number, d: number, props: { [string]: any }): BasePart
		props.Shape = Enum.PartType.Cylinder
		props.Size = Vector3.new(y1 - y0, d, d)
		props.CFrame = CFrame.new(0, (y0 + y1) / 2, 0) * CFrame.Angles(0, 0, math.rad(90))
		return part(m, props)
	end
	-- (upright, the grip at the origin, its face to ±Z)
	rod(-1.45, 2.2, 0.17, { Color = Color3.fromRGB(240, 234, 216), Material = Enum.Material.SmoothPlastic }) -- ivory shaft
	rod(-0.45, 0.5, 0.2, { Color = Color3.fromRGB(116, 32, 40), Material = Enum.Material.Fabric })         -- wrapped grip
	for _, y in ipairs({ -0.5, 0.55, 1.4 }) do rod(y - 0.04, y + 0.04, 0.24, gold({})) end                  -- bands
	rod(-1.62, -1.42, 0.25, gold({}))                                                                       -- pommel
	part(m, gold({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.32, CFrame = CFrame.new(0, -1.7, 0) }))
	rod(2.12, 2.36, 0.3, gold({}))                                                                          -- collar
	part(m, gold({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.36, CFrame = CFrame.new(0, 2.45, 0) }))
	-- two leaves curling up off the collar to cradle the sun
	for _, side in ipairs({ -1, 1 }) do
		local a = math.rad(38)
		spike(m, Vector3.new(side * 0.1, 2.42, 0), Vector3.new(side * math.sin(a), math.cos(a), 0), 0.45, 0.2, 0.06, Vector3.zAxis, gold({}))
	end
	-- the sun: a gold ring, a thinner ring of light inside it, rays round it
	local C, R = Vector3.new(0, 3.1, 0), 0.55
	local function hoop(r: number, n: number, thick: number, props: { [string]: any })
		local seg = 2 * math.pi * r / n * 1.12
		for k = 0, n - 1 do
			local pr = table.clone(props)
			pr.Size = Vector3.new(seg, thick, thick)
			pr.CFrame = CFrame.new(C) * CFrame.Angles(0, 0, k / n * 2 * math.pi) * CFrame.new(0, r, 0)
			part(m, pr)
		end
	end
	hoop(R, 16, 0.1, gold({}))
	hoop(R - 0.12, 14, 0.04, { Color = GLOW, Transparency = 0.15 })
	for k = 0, 7 do
		if k ~= 4 then -- (none down into the collar)
			local a = k / 8 * 2 * math.pi
			local dir = Vector3.new(math.sin(a), math.cos(a), 0)
			local long = k % 2 == 0
			spike(m, C + dir * (R + 0.02), dir, if long then 0.5 else 0.3, if long then 0.16 else 0.12, 0.05, Vector3.zAxis, gold({}))
		end
	end
	-- the crystal at its heart, and its glow
	-- (a warm diamond with a white-hot one inside it)
	local gem = part(m, { Size = Vector3.new(0.42, 0.42, 0.14), Color = Color3.fromRGB(255, 206, 110), CFrame = CFrame.new(C) * CFrame.Angles(0, 0, math.rad(45)) })
	part(m, { Size = Vector3.new(0.24, 0.24, 0.2), Color = Color3.fromRGB(255, 250, 232), CFrame = CFrame.new(C) * CFrame.Angles(0, 0, math.rad(45)) })
	part(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = Color3.fromRGB(255, 200, 90), Transparency = 0.9, CFrame = CFrame.new(C) })
	emitter(gem, { Texture = TEX_SPARKLE, Color = ColorSequence.new(GLOW), LightEmission = 1, Size = seq(0, 0.22, 1, 0),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(0.3, 1), SpreadAngle = Vector2.new(180, 180), Rate = 10 })
	light(gem, Color3.fromRGB(255, 214, 140), 1.4, 8)
	m.WorldPivot = CFrame.identity -- (the grip, upright)
	m.Parent = folder
	return m
end

ENTRANCES.cleric = function(c)
	local GOLDEN = Color3.fromRGB(255, 214, 120)
	c.at(c.beats.light or 0.5, function()
		-- the beam coming down out of the sky onto him
		local H = 34
		local beam = part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 6, 6), Color = GOLDEN, Transparency = 0.55,
			CFrame = CFrame.new(c.ground + Vector3.new(0, H, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		local core = part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2.4, 2.4), Color = Color3.fromRGB(255, 248, 220),
			Transparency = 0.3, CFrame = beam.CFrame })
		for _, b in ipairs({ beam, core }) do
			local w = b.Size.Y
			TweenService:Create(b, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(H, w, w), CFrame = CFrame.new(c.ground + Vector3.new(0, H / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) }):Play()
			task.delay(2.6, function()
				if b.Parent then TweenService:Create(b, TweenInfo.new(1.4), { Transparency = 1 }):Play() end
			end)
		end
		ringOut(c, c.ground, 1, 4, 0.6, GOLDEN, 0.25)
		local motes = anchorAt(c.folder, CFrame.new(c.ground + Vector3.new(0, 12, 0)))
		motes.Size = Vector3.new(5, 0.2, 5)
		local e = emitter(motes, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(255, 248, 220), GOLDEN), LightEmission = 1,
			Size = seq(0, 0.25, 1, 0), Lifetime = NumberRange.new(1.4, 2), Speed = NumberRange.new(4, 7), EmissionDirection = Enum.NormalId.Bottom,
			SpreadAngle = Vector2.new(10, 10), Rate = 26, Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume })
		task.delay(3, function() e.Enabled = false end)
	end)
	local scepter: Model? = nil
	local floating = true
	-- the scepter at `grip`: upright, leaning `lean` degrees out to his right
	-- (so it stands beside his face rather than over it), its face to the front
	local function held(grip: Vector3, lean: number): CFrame
		local up = Vector3.yAxis * math.cos(math.rad(lean)) + c.right * math.sin(math.rad(lean))
		return CFrame.fromMatrix(grip, (c.right - up * up:Dot(c.right)).Unit, up)
	end
	c.at(c.beats.scepter or 1.3, function()
		local s = buildScepter(c.folder)
		scepter = s
		-- (hanging where his reaching hand will close on it)
		local home = c.root.Position + c.right * 0.55 + c.fwd * 1.5 + Vector3.new(0, 0.25, 0)
		s:PivotTo(held(home, 10))
		-- forming out of the light
		for _, p in ipairs(s:GetDescendants()) do
			if p:IsA("BasePart") then
				local goal = p.Transparency
				p.Transparency = 1
				TweenService:Create(p, TweenInfo.new(0.6), { Transparency = goal }):Play()
			end
		end
		flare(c, home + Vector3.new(0, 3.1, 0), 3.5, 0.5, Color3.fromRGB(255, 240, 190))
		local t0 = os.clock()
		c.onStep(function()
			if not floating or not s.Parent then return end
			local t = os.clock() - t0
			s:PivotTo(held(home + Vector3.new(0, math.sin(t * 2.4) * 0.12, 0), 10) * CFrame.Angles(0, math.sin(t * 0.9) * 0.3, 0))
		end)
	end)
	c.at(c.beats.grab or 2.95, function()
		local s = scepter
		local fist = fistOf(c, "Right Arm")
		if not (s and s.Parent and fist) then return end
		floating = false
		flare(c, fist, 1.6, 0.2, Color3.fromRGB(255, 240, 190))
		local from = s:GetPivot()
		local t0 = os.clock()
		c.onStep(function()
			if not s.Parent then return end
			local rf, lf = fistOf(c, "Right Arm"), fistOf(c, "Left Arm")
			if not (rf and lf) then return end
			local t = os.clock() - t0
			-- taken in his right hand; the left joins it as he settles
			local k = math.clamp(t / 0.4, 0, 1)
			k = k * k * (3 - 2 * k)
			local goal = held(rf:Lerp((rf + lf) / 2, k), 10 + 10 * k)
			local snap = math.clamp(t / 0.12, 0, 1)
			s:PivotTo(if snap < 1 then from:Lerp(goal, snap) else goal)
		end)
	end)
end

-- ── Ice Mage: frozen enemies stand round the platform; she walks in between
-- them leaving frost behind her, and ice spreads over each as she passes
-- (and over the ones beyond as she arrives).
local function buildFrozen(folder: Instance, base: CFrame): { parts: { BasePart }, cf: CFrame }
	local list: { BasePart } = {}
	local SKIN = Color3.fromRGB(96, 116, 120)
	local CLOTH = Color3.fromRGB(52, 60, 74)
	local function piece(size: Vector3, cf: CFrame, color: Color3)
		local p = part(folder, { Size = size, CFrame = cf, Color = color, Material = Enum.Material.Ice, Transparency = 0 })
		table.insert(list, p)
	end
	-- lunging at the middle, arms reaching out, caught mid-stride
	local torso = base * CFrame.new(0, 3, 0) * CFrame.Angles(math.rad(-15), 0, 0)
	piece(Vector3.new(2, 2, 1), torso, CLOTH)
	piece(Vector3.new(1.2, 1.2, 1.2), torso * CFrame.new(0, 1.55, -0.1), SKIN)
	for _, s in ipairs({ -1, 1 }) do
		piece(Vector3.new(1, 2, 1), torso * CFrame.new(s * 1.5, 0.5, 0) * CFrame.Angles(math.rad(70 + s * 8), 0, 0) * CFrame.new(0, -1, 0), SKIN)
		piece(Vector3.new(1, 2, 1), base * CFrame.new(s * 0.5, 2, 0) * CFrame.Angles(math.rad(s * 22), 0, 0) * CFrame.new(0, -1, 0), CLOTH)
	end
	return { parts = list, cf = base }
end

-- Ice closing over a frozen figure: a block of it growing up from the floor,
-- crystals breaking out round it, a burst of frost.
local function encase(c: Ctx, base: CFrame)
	local ICE = Color3.fromRGB(170, 225, 255)
	local block = part(c.folder, { Size = Vector3.new(3.6, 0.2, 3.2), CFrame = base * CFrame.new(0, 0.1, -0.4), Color = ICE,
		Material = Enum.Material.Glass, Transparency = 0.55 })
	TweenService:Create(block, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(3.6, 6.2, 3.2), CFrame = base * CFrame.new(0, 3.1, -0.4) }):Play()
	for k = 1, 7 do
		local a = k / 7 * math.pi * 2
		local cr = part(c.folder, { ClassName = "WedgePart", Size = Vector3.new(0.3, 0.1, 0.8), Color = if k % 2 == 0 then Color3.fromRGB(220, 245, 255) else ICE,
			Material = Enum.Material.Glass, Transparency = 0.2,
			CFrame = base * CFrame.new(math.cos(a) * 1.9, 0.4 + (k % 3) * 1.6, math.sin(a) * 1.7) * CFrame.Angles(math.rad(-25), a, 0) })
		TweenService:Create(cr, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0.05 * k), {
			Size = Vector3.new(0.3, 1.6 + (k % 3) * 0.5, 0.8) }):Play()
	end
	burst(c, base * CFrame.new(0, 2, 0), Vector3.new(2, 3, 2), 22, {
		Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), ICE), LightEmission = 1, Size = seq(0, 0.3, 1, 0),
		Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180), Drag = 2 })
	ringOut(c, base.Position, 0.8, 3, 0.4, ICE, 0.2)
end

ENTRANCES.ice_mage = function(c)
	local walk = CastPoses.ICE_WALK
	local start = c.beats.walk or 0.05
	local arrive = c.beats.arrive or (start + walk.walk)
	local R, T = c.screenRight, c.toward
	local center = Vector3.new(c.ground.X, c.ground.Y, c.ground.Z)
	for _, off in ipairs({ R * 8 - T * 3.2, R * 4 + T * 2.8, -R * 4.5 - T * 2.6 }) do
		local at = center + off
		local base = CFrame.lookAt(at, Vector3.new(center.X, at.Y, center.Z))
		buildFrozen(c.folder, base)
		-- (frost already round its feet)
		part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 3.6, 3.6), Color = Color3.fromRGB(215, 240, 255),
			Material = Enum.Material.Ice, Transparency = 0.35, CFrame = CFrame.new(at + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		-- the ice closes over it as she passes (or as she arrives, the far side)
		local along = off:Dot(R)
		local passAt = start + walk.walk * math.clamp(1 - along / walk.dist, 0, 1)
		c.at(math.min(passAt, arrive), function() encase(c, base) end)
	end
	-- the frost she leaves behind: mist and glitter at her feet, patches of it
	-- left on the floor
	local feet = anchorAt(c.folder, CFrame.new(center))
	local mist = emitter(feet, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(225, 242, 255)), LightEmission = 0.3,
		Size = seq(0, 1, 1, 2.6), Transparency = seq(0, 0.5, 1, 1), Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(0.3, 1),
		SpreadAngle = Vector2.new(180, 20), Rate = 0 })
	local glitter = emitter(feet, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(150, 220, 255)),
		LightEmission = 1, Size = seq(0, 0.2, 1, 0), Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180), Rate = 0 })
	local lastPatch: Vector3? = nil
	local patches = 0
	c.at(start, function()
		mist.Rate, glitter.Rate = 18, 26
	end)
	c.at(arrive, function()
		mist.Rate, glitter.Rate = 0, 0
		ringOut(c, center, 1, 5, 0.6, Color3.fromRGB(170, 225, 255), 0.25)
	end)
	local torso = torsoOf(c)
	local t0 = os.clock()
	c.onStep(function()
		local t = os.clock() - t0
		if not torso or t < start or t > arrive + 0.1 then return end
		local p = Vector3.new(torso.Position.X, center.Y, torso.Position.Z)
		feet.CFrame = CFrame.new(p + Vector3.new(0, 0.3, 0))
		if patches < 24 and (not lastPatch or (p - lastPatch).Magnitude > 0.9) then
			lastPatch = p
			patches += 1
			local s = 0.9 + math.random() * 0.8
			local frost = part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, s, s), Color = Color3.fromRGB(220, 242, 255),
				Material = Enum.Material.Ice, Transparency = 0.25, CFrame = CFrame.new(p + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
			TweenService:Create(frost, TweenInfo.new(4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2), { Transparency = 1 }):Play()
		end
	end)
end

-- ── Berserker: after the storyboard. The greatsword dragged behind him as he
-- walks in, sparks scraping off its point; the roar, red energy erupting out
-- of him (flames torn upward round his body, a column of red light, lightning
-- into the floor, a ring blown out across it); the change: the body bursts
-- into the beast (BerserkerLook.DressBeast, every piece of it swelling into
-- place), the sword flung aside to stick in the floor, and the beast's own
-- body takes over (BerserkerController.PreviewBeast: born low on all fours,
-- wrenched about, then up into its coiled stance, breathing, eyes on you).
-- (the angle the blade is turned back in his hand to drag along the floor)
local BERSERKER_DRAG = math.rad(-125)

ENTRANCES.berserker = function(c)
	local CRIMSON = Color3.fromRGB(220, 20, 34)
	local HOT = Color3.fromRGB(255, 96, 100)
	local walk, halt = c.beats.walk or 0.05, c.beats.halt or 2.65
	local roar, change = c.beats.roar or 3.35, c.beats.change or 4.68
	local tool = c.char:FindFirstChild("Look_berserker")

	-- the blade laid back along the floor as he walks, raised again as he stops
	local turn = gripOf(c, "Look_berserker")
	if turn then
		c.onStep(function(t)
			local k = if t < halt then 1 else math.clamp(1 - (t - halt) / 0.4, 0, 1)
			turn(BERSERKER_DRAG * k * k * (3 - 2 * k))
		end)
	end
	-- sparks off its point while it drags: the point is the far end of the
	-- blade (the tool's biggest piece) from the grip
	local blade: BasePart? = nil
	for _, d in ipairs(if tool then tool:GetDescendants() else {}) do
		if d:IsA("BasePart") and d.Transparency < 1 and (not blade or d.Size.Magnitude > (blade :: BasePart).Size.Magnitude) then
			blade = d
		end
	end
	if blade then
		local b = blade :: BasePart
		local handle = (tool :: Instance):FindFirstChild("Handle") :: BasePart?
		local axis = if b.Size.X >= b.Size.Y and b.Size.X >= b.Size.Z then Vector3.xAxis
			elseif b.Size.Y >= b.Size.Z then Vector3.yAxis else Vector3.zAxis
		local half = axis * (b.Size:Dot(axis) / 2)
		local from = if handle then b.CFrame:PointToObjectSpace(handle.Position) else Vector3.zero
		local tip = Instance.new("Attachment")
		tip.Position = if (half - from).Magnitude > (-half - from).Magnitude then half else -half
		tip.Parent = b
		c.attach(tip)
		local sparks = emitter(tip, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(255, 190, 120), CRIMSON), LightEmission = 1,
			Size = seq(0, 0.22, 1, 0), Lifetime = NumberRange.new(0.18, 0.4), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(70, 70),
			Acceleration = Vector3.new(0, -30, 0), Rate = 0 })
		c.at(walk + 0.3, function() sparks.Rate = 26 end)
		c.at(halt, function() sparks.Rate = 0 end)
	end

	-- the roar: red energy erupting out of him
	c.at(roar + 0.08, function()
		local torso = torsoOf(c)
		local at = if torso then torso.Position else c.root.Position
		flare(c, at, 6, 0.4, HOT)
		ringOut(c, c.ground, 1, 9, 0.6, CRIMSON, 0.35)
		ringOut(c, c.ground, 0.5, 6, 0.45, HOT, 0.2)
		-- a column of red light
		local pillar = part(c.folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(18, 3.2, 3.2), Color = CRIMSON, Transparency = 0.45,
			CFrame = CFrame.new(c.ground + Vector3.new(0, 9, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
		TweenService:Create(pillar, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(18, 6, 6), Transparency = 1 }):Play()
		Debris:AddItem(pillar, 0.75)
		-- red lightning into the floor round him
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2 + math.random() * 0.4
			local p0 = at + Vector3.new(0, 0.5, 0)
			local p1 = c.ground + Vector3.new(math.cos(a) * 6, 0.2, math.sin(a) * 6)
			local mid = (p0 + p1) / 2 + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 1.6
			for _, seg in ipairs({ { p0, mid }, { mid, p1 } }) do
				local len = (seg[2] - seg[1]).Magnitude
				local bolt = part(c.folder, { Size = Vector3.new(0.14, 0.14, len), Color = HOT,
					CFrame = CFrame.lookAt((seg[1] + seg[2]) / 2, seg[2]) })
				TweenService:Create(bolt, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.03, 0.03, len) }):Play()
				Debris:AddItem(bolt, 0.3)
			end
		end
		-- flames of it torn upward round his body for as long as he roars
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(0, -0.5, 0)
		a.Parent = c.root
		c.attach(a)
		local e = emitter(a, { Texture = TEX_FIRE, Color = ColorSequence.new(HOT, CRIMSON), LightEmission = 0.9,
			Size = seq(0, 1.6, 0.6, 1.1, 1, 0), Transparency = seq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.35, 0.6),
			Speed = NumberRange.new(6, 12), SpreadAngle = Vector2.new(65, 65), Acceleration = Vector3.new(0, 14, 0),
			Rotation = NumberRange.new(0, 360), Shape = Enum.ParticleEmitterShape.Cylinder,
			ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Rate = 70 })
		e:Emit(30)
		task.delay(0.8, function() e.Enabled = false end)
		burst(c, CFrame.new(c.ground + Vector3.new(0, 0.4, 0)), Vector3.new(3, 0.2, 3), 24, {
			Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, CRIMSON), LightEmission = 1, Size = seq(0, 0.3, 1, 0),
			Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(10, 18), SpreadAngle = Vector2.new(80, 80),
			EmissionDirection = Enum.NormalId.Top, Drag = 3 })
	end)

	-- the change: the beast
	c.at(change, function()
		local BerserkerLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("BerserkerLook"))
		local Berserker = require(script.Parent:WaitForChild("BerserkerController"))
		-- the sword flung aside to stick in the floor beside him
		if tool then
			local fly = Instance.new("Model")
			fly.Name = "CastAsideSword"
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local cp = d:Clone()
					for _, j in ipairs(cp:GetChildren()) do
						if j:IsA("JointInstance") or j:IsA("WeldConstraint") or j:IsA("Attachment") then j:Destroy() end
					end
					cp.Anchored, cp.CanCollide, cp.CanQuery, cp.CanTouch = true, false, false, false
					cp.Parent = fly
				end
			end
			if #fly:GetChildren() > 0 then
				fly.Parent = c.folder
				local start = fly:GetPivot()
				local stuck = CFrame.new(c.ground + c.right * 5.5 - c.fwd * 1.5 + Vector3.new(0, 2.2, 0))
					* CFrame.Angles(math.rad(180 + 12), math.rad(30), 0)
				local t0 = os.clock()
				local landed = false
				c.onStep(function()
					if landed or not fly.Parent then return end
					local u = math.clamp((os.clock() - t0) / 0.35, 0, 1)
					fly:PivotTo(start:Lerp(stuck, u * u) + Vector3.new(0, math.sin(math.pi * u) * 3, 0))
					if u >= 1 then
						landed = true
						burst(c, CFrame.new(Vector3.new(stuck.X, c.ground.Y + 0.3, stuck.Z)), Vector3.new(0.6, 0.2, 0.6), 10, {
							Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(60, 52, 56)), Size = seq(0, 0.8, 1, 2),
							Transparency = seq(0, 0.4, 1, 1), Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(3, 6),
							EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(80, 80), Drag = 4 })
					end
				end)
			else
				fly:Destroy()
			end
		end
		c.onCleanup(function()
			Berserker.PreviewBeast(c.char, false)
			BerserkerLook.UndressBeast(c.char)
		end)
		BerserkerLook.DressBeast(c.char)
		Berserker.SproutBeast(c.char, 0.55)
		CastPoses.stop(c.char)
		Berserker.PreviewBeast(c.char, true)
		-- the burst: light, a ring of force, chips of black rock thrown off
		local torso = torsoOf(c)
		local at = if torso then torso.Position else c.root.Position
		flare(c, at, 5, 0.35, HOT)
		ringOut(c, c.ground, 1, 7, 0.5, CRIMSON, 0.3)
		burst(c, CFrame.new(at), Vector3.new(1.5, 1.5, 1.5), 18, {
			Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(40, 12, 16), Color3.fromRGB(12, 6, 8)), Size = seq(0, 1.5, 1, 4),
			Transparency = seq(0, 0.3, 1, 1), Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(4, 9),
			SpreadAngle = Vector2.new(180, 180), Drag = 3, Rotation = NumberRange.new(0, 360) })
		for _ = 1, 10 do
			local chip = part(c.folder, { Size = Vector3.new(0.3, 0.25, 0.35) * (0.6 + math.random()), Color = Color3.fromRGB(30, 24, 28),
				Material = Enum.Material.Slate, CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
			local dir = Vector3.new(math.random() - 0.5, math.random() * 0.6 + 0.2, math.random() - 0.5).Unit
			TweenService:Create(chip, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = CFrame.new(at + dir * (4 + math.random() * 3)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1 }):Play()
			Debris:AddItem(chip, 0.55)
		end
	end)
end

-- ─── Public ─────────────────────────────────────────────────────────────────
function UltPreviewFX.Stop()
	local cur = current
	if not cur then return end
	current = nil
	for _, conn in ipairs(cur.conns) do conn:Disconnect() end
	for _, fn in ipairs(cur.cleanups) do pcall(fn) end
	for _, a in ipairs(cur.attachments) do
		if a.Parent then a:Destroy() end
	end
	cur.folder:Destroy()
end

function UltPreviewFX.Start(char: Model?, classId: string)
	UltPreviewFX.Stop()
	local aura = AURAS[classId]
	local entrance = ENTRANCES[classId]
	if not char or not (aura or entrance) then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local folder = Instance.new("Folder")
	folder.Name = "UltPreviewFX"
	folder.Parent = Workspace.Terrain
	local state = { folder = folder, conns = {}, attachments = {}, cleanups = {} }
	current = state
	local fwd = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	fwd = fwd.Magnitude > 0.01 and fwd.Unit or Vector3.new(0, 0, -1)
	local t0 = os.clock()
	local camRight = Workspace.CurrentCamera.CFrame.RightVector
	camRight = Vector3.new(camRight.X, 0, camRight.Z)
	camRight = if camRight.Magnitude > 0.01 then camRight.Unit else -fwd:Cross(Vector3.yAxis).Unit
	local ctx: Ctx = {
		char = char,
		root = root,
		folder = folder,
		ground = groundUnder(root, char),
		fwd = fwd,
		right = fwd:Cross(Vector3.yAxis).Unit,
		onStep = function(fn)
			table.insert(state.conns, RunService.RenderStepped:Connect(function()
				fn(os.clock() - t0)
			end))
		end,
		attach = function(inst)
			table.insert(state.attachments, inst)
		end,
		onCleanup = function(fn)
			table.insert(state.cleanups, fn)
		end,
		screenRight = camRight,
		toward = camRight:Cross(Vector3.yAxis),
		beats = CastPoses.previewBeats(classId),
		at = function(t, fn)
			task.delay(math.max(t, 0), function()
				if current ~= state then return end
				local ok, err = pcall(fn)
				if not ok then warn("[UltPreviewFX] entrance:", err) end
			end)
		end,
	}
	if aura then aura(ctx) end
	if entrance then entrance(ctx) end
end

return UltPreviewFX
