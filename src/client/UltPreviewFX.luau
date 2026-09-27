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

	UltPreviewFX.Start(character, classId) replaces any running preview;
	UltPreviewFX.Stop() removes it.
--]]

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

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
type Ctx = { char: Model, root: BasePart, folder: Folder, ground: Vector3, fwd: Vector3, right: Vector3,
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
				CFrame = head.CFrame * CFrame.new(side * 0.16, 0.12,
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
	if not char or not aura then return end
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
	aura({
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
	})
end

return UltPreviewFX
