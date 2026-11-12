--!strict
--[[
	ForgeMinigame.luau
	Forging a new power piece at the Armory's forge (PowerGear.CRAFT_COST
	scrap), played out in a small smithy built for it far off-map: your own
	character (a clone) at the anvil with a hammer, a hearth, bellows and a
	quench barrel; the camera moves in, the Armory steps aside.

	  1. HEAT    hold (mouse / Space / tap / A) to work the bellows: the smith
	             pumps, the hearth flares and the ingot heats; let go and it
	             cools. Keep the heat inside the drifting band for 5 seconds.
	  2. HAMMER  the smith holds the hammer up; every press brings it down at
	             once (sparks, a flash, the camera jolts on the blow). Strike
	             while the marker crosses the glowing mark: PERFECT / GOOD /
	             OK / MISS, five times, each sweep faster.
	  3. QUENCH  quality = 35% heat + 65% hammer; the server forges the piece
	             (LootManager "craft": the score picks the rarity odds,
	             PowerGear.CraftRarity), it's quenched in a burst of steam and
	             glows in its rarity's colour, and its card is shown.

	The scene, the camera and the input binding are all undone when it closes.

	ForgeMinigame.Play(slot)
--]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GearData = require(Shared:WaitForChild("GearData"))
local PowerGear = require(Shared:WaitForChild("PowerGear"))

local player = Players.LocalPlayer

local ForgeMinigame = {}

local GOLD = Color3.fromRGB(240, 196, 110)
local PARCH = Color3.fromRGB(238, 226, 204)
local MUTED = Color3.fromRGB(150, 140, 128)
local GREEN = Color3.fromRGB(120, 230, 140)
local RED = Color3.fromRGB(230, 110, 100)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

local HEAT_TIME = 5
local STRIKES = 5
local ORIGIN = CFrame.new(-9000, 2500, -9000) -- the smithy, far from everything

-- Arm poses (R6 Right Shoulder angle, forward-positive) and the wrist angle
-- the hammer is held at: hanging at rest, raised overhead, down on the anvil.
local WRIST = math.rad(-165)
local ARM_REST = math.rad(20)
local ARM_RAISED = math.rad(195)
local ARM_IMPACT = math.rad(55)
local DOWNSWING = 0.08 -- seconds from the press to the blow
local RECOVER = 0.3

-- the ingot's colour by heat: cold iron → cherry → orange → white-hot
local HEAT_COLORS = {
	{ 0, Color3.fromRGB(70, 66, 66) },
	{ 0.35, Color3.fromRGB(150, 30, 20) },
	{ 0.6, Color3.fromRGB(240, 110, 30) },
	{ 0.85, Color3.fromRGB(255, 210, 90) },
	{ 1, Color3.fromRGB(255, 250, 230) },
}
local function heatColor(h: number): Color3
	for i = 2, #HEAT_COLORS do
		local a, b = HEAT_COLORS[i - 1], HEAT_COLORS[i]
		if h <= b[1] then return a[2]:Lerp(b[2], (h - a[1]) / (b[1] - a[1])) end
	end
	return HEAT_COLORS[#HEAT_COLORS][2]
end

local function grade(score: number): string
	return if score >= 0.95 then "MASTERWORK" elseif score >= 0.8 then "EXCELLENT" elseif score >= 0.6 then "FINE"
		elseif score >= 0.35 then "DECENT" else "CRUDE"
end

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in pairs(props) do (o :: any)[k] = v end
	if parent then o.Parent = parent end
	return o
end

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = make("Part", {
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Size = size, CFrame = cf,
		Color = color, Material = material or Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
	}, nil)
	for k, v in pairs(props or {}) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- ── The smithy ─────────────────────────────────────────────────────────────
type Scene = {
	folder: Folder,
	root: CFrame,           -- the smith's root (faces -Z)
	smith: Model?,
	rShoulder: Motor6D?, rBase: CFrame,
	lShoulder: Motor6D?, lBase: CFrame,
	hammerWeld: Weld?,
	ingot: Part,
	coals: Part,
	hearthLight: PointLight,
	flash: PointLight,
	bellowsBody: Part, bellowsTop: Part, bellowsBase: CFrame,
	sparks: ParticleEmitter,
	steam: ParticleEmitter,
	burst: ParticleEmitter,
	anvilTop: Vector3,      -- the strike point (the ingot's top)
	hearthSpot: Vector3,    -- the ingot in the coals
	quenchSpot: Vector3,
	camHome: CFrame,
}

-- A clone of the player's character, still and script-free, to be the smith.
local function cloneSmith(parent: Instance, at: CFrame): Model?
	local char = player.Character
	if not char then return nil end
	local was = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not clone then return nil end
	local m = clone :: Model
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("BillboardGui") or d:IsA("Highlight")
			or d:IsA("ParticleEmitter") or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("Light") or d:IsA("Trail")
			or d:IsA("Beam") then
			d:Destroy()
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.PlatformStand = true
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			d.Anchored = false
			d.Massless = true
		end
	end
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		m:Destroy()
		return nil
	end
	root.Anchored = true
	m.Parent = parent
	m:PivotTo(at)
	root.CFrame = at
	return m
end

local function buildScene(): Scene
	local folder = make("Folder", { Name = "ForgeScene" }, Workspace)
	local root = ORIGIN * CFrame.new(0, 3, 0) -- an R6 root stands 3 above the floor
	local floorY = ORIGIN.Y

	-- the room: slate floor, brick walls, a beamed roof (closed, so the sun stays out)
	local STONE = Color3.fromRGB(58, 54, 52)
	local BRICK = Color3.fromRGB(70, 46, 38)
	local WOOD = Color3.fromRGB(64, 44, 30)
	part(folder, Vector3.new(44, 1, 44), ORIGIN * CFrame.new(0, -0.5, 0), STONE, Enum.Material.Slate)
	part(folder, Vector3.new(44, 1, 44), ORIGIN * CFrame.new(0, 15, 0), WOOD, Enum.Material.WoodPlanks)
	for _, w in ipairs({
		{ Vector3.new(44, 16, 1), CFrame.new(0, 7.5, -14) },
		{ Vector3.new(44, 16, 1), CFrame.new(0, 7.5, 14) },
		{ Vector3.new(1, 16, 44), CFrame.new(-14, 7.5, 0) },
		{ Vector3.new(1, 16, 44), CFrame.new(14, 7.5, 0) },
	}) do
		part(folder, w[1], ORIGIN * w[2], BRICK, Enum.Material.Brick)
	end
	for i = -2, 2 do
		part(folder, Vector3.new(44, 0.8, 0.8), ORIGIN * CFrame.new(0, 14, i * 6), WOOD, Enum.Material.Wood)
	end
	-- tools on the back wall (decoration)
	for i, x in ipairs({ -6, -4.6, -3.2, 3.4, 4.8 }) do
		part(folder, Vector3.new(0.18, 2.4 + (i % 2) * 0.6, 0.18), ORIGIN * CFrame.new(x, 7, -13.3), Color3.fromRGB(90, 86, 84), Enum.Material.Metal)
	end
	part(folder, Vector3.new(14, 0.3, 0.6), ORIGIN * CFrame.new(-1, 8.4, -13.3), WOOD, Enum.Material.Wood)

	-- the smith (your character) and the hammer in its right hand
	local smith = cloneSmith(folder, root)
	local torso = smith and smith:FindFirstChild("Torso") :: BasePart?
	local rArm = smith and smith:FindFirstChild("Right Arm") :: BasePart?
	local rShoulder = torso and torso:FindFirstChild("Right Shoulder") :: Motor6D?
	local lShoulder = torso and torso:FindFirstChild("Left Shoulder") :: Motor6D?
	local rBase = if rShoulder then rShoulder.C0 else CFrame.identity
	local lBase = if lShoulder then lShoulder.C0 else CFrame.identity

	local IRON = Color3.fromRGB(64, 62, 66)
	local hammer = make("Model", { Name = "Hammer" }, folder)
	local handle = part(hammer, Vector3.new(0.2, 2.1, 0.2), root, Color3.fromRGB(96, 66, 40), Enum.Material.Wood, { Anchored = false, Massless = true })
	local head = part(hammer, Vector3.new(0.6, 0.6, 1.25), root, IRON, Enum.Material.Metal, { Anchored = false, Massless = true })
	make("Weld", { Part0 = handle, Part1 = head, C0 = CFrame.new(0, 0.95, 0) }, head)
	local hammerWeld: Weld? = nil
	if rArm then
		hammerWeld = make("Weld", { Part0 = rArm, Part1 = handle, C0 = CFrame.new(0, -1, 0) * CFrame.Angles(WRIST, 0, 0),
			C1 = CFrame.new(0, -0.85, 0) }, handle)
	else
		handle.Anchored = true
	end

	-- where the hammer lands: pose the arm at the blow and read the head's lower face
	local strike = (root * CFrame.new(1.5, -1.9, -3.4)).Position
	if rShoulder then
		rShoulder.C0 = rBase * CFrame.Angles(0, 0, ARM_IMPACT)
		RunService.Heartbeat:Wait()
		RunService.Heartbeat:Wait()
		local a = (head.CFrame * CFrame.new(0, 0, 0.625)).Position
		local b = (head.CFrame * CFrame.new(0, 0, -0.625)).Position
		strike = if a.Y < b.Y then a else b
		rShoulder.C0 = rBase * CFrame.Angles(0, 0, ARM_REST)
	end
	-- the anvil under it (the ingot's top is the strike point)
	local face = root.Rotation + Vector3.new(strike.X, 0, strike.Z)
	local topY = strike.Y - 0.24
	local floorUnder = floorY
	part(folder, Vector3.new(2.8, 0.5, 1.15), face + Vector3.new(0, topY - 0.25, 0), IRON, Enum.Material.Metal)
	local horn = part(folder, Vector3.new(1.15, 0.5, 1.1), (face + Vector3.new(0, topY - 0.25, 0)) * CFrame.new(-1.95, 0, 0) * CFrame.Angles(0, math.rad(-90), 0),
		IRON, Enum.Material.Metal)
	local hornShape = Instance.new("SpecialMesh")
	hornShape.MeshType = Enum.MeshType.Wedge
	hornShape.Parent = horn
	local waistH = math.max(0.3, topY - 0.5 - (floorUnder + 0.6))
	part(folder, Vector3.new(1, waistH, 0.75), face + Vector3.new(0, floorUnder + 0.6 + waistH / 2, 0), IRON, Enum.Material.Metal)
	part(folder, Vector3.new(2.2, 0.6, 1.5), face + Vector3.new(0, floorUnder + 0.3, 0), IRON, Enum.Material.Metal)
	part(folder, Vector3.new(2.6, 0.8, 2), face + Vector3.new(0, floorUnder + 0.0, 0), WOOD, Enum.Material.Wood) -- the stump

	-- the hearth (left, ahead), its coals, fire and light
	local hearthCF = root * CFrame.new(-5, -3, -3.2)
	part(folder, Vector3.new(3.4, 2.6, 3), hearthCF * CFrame.new(0, 1.3, 0), Color3.fromRGB(86, 60, 50), Enum.Material.Brick)
	local coals = part(folder, Vector3.new(2.6, 0.3, 2.2), hearthCF * CFrame.new(0, 2.65, 0), Color3.fromRGB(255, 90, 30), Enum.Material.Neon)
	part(folder, Vector3.new(3.6, 0.5, 3.2), hearthCF * CFrame.new(0, 6.5, -0.2), Color3.fromRGB(70, 50, 44), Enum.Material.Brick)
	part(folder, Vector3.new(1.6, 8, 1.6), hearthCF * CFrame.new(0, 10.5, -0.6), Color3.fromRGB(70, 50, 44), Enum.Material.Brick)
	for _, x in ipairs({ -1.5, 1.5 }) do
		part(folder, Vector3.new(0.5, 3.6, 0.5), hearthCF * CFrame.new(x, 4.5, -1.2), Color3.fromRGB(70, 50, 44), Enum.Material.Brick)
	end
	make("Fire", { Heat = 6, Size = 4, Color = Color3.fromRGB(255, 120, 40), SecondaryColor = Color3.fromRGB(255, 40, 10) }, coals)
	local embers = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 60, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(1, 2), Rate = 10, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 2, 0),
	}, coals)
	local hearthLight = make("PointLight", { Color = Color3.fromRGB(255, 130, 60), Range = 20, Brightness = 1.5, Shadows = true }, coals)

	-- the bellows, beside the hearth, worked by the left hand
	local bellowsBase = root * CFrame.new(-2.5, -2.55, -1.6)
	part(folder, Vector3.new(1.4, 0.15, 2.2), bellowsBase, WOOD, Enum.Material.Wood)
	local bellowsBody = part(folder, Vector3.new(1.2, 0.6, 1.9), bellowsBase * CFrame.new(0, 0.38, 0), Color3.fromRGB(110, 70, 44), Enum.Material.Fabric)
	local bellowsTop = part(folder, Vector3.new(1.4, 0.15, 2.2), bellowsBase * CFrame.new(0, 0.75, 0), WOOD, Enum.Material.Wood)
	part(folder, Vector3.new(0.25, 0.25, 1.8), bellowsBase * CFrame.new(-0.6, 0.3, -1.6) * CFrame.Angles(0, math.rad(-35), 0), IRON, Enum.Material.Metal)

	-- the quench barrel (behind, on the left)
	local barrelCF = root * CFrame.new(-2.2, -3, 3.2)
	part(folder, Vector3.new(2.2, 2.2, 2.2), barrelCF * CFrame.new(0, 1.1, 0) * CFrame.Angles(0, 0, math.rad(90)), WOOD, Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder })
	local water = part(folder, Vector3.new(0.1, 1.9, 1.9), barrelCF * CFrame.new(0, 2.1, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(40, 70, 90), Enum.Material.Glass, { Shape = Enum.PartType.Cylinder, Transparency = 0.2 })

	-- the ingot (in the coals to start)
	local hearthSpot = (hearthCF * CFrame.new(0, 2.95, 0)).Position
	local ingot = part(folder, Vector3.new(1, 0.24, 0.45), CFrame.new(hearthSpot) * root.Rotation, heatColor(0), Enum.Material.Neon)

	-- the blow: sparks and a flash at the strike point; steam at the barrel
	local strikeAtt = make("Attachment", { WorldPosition = strike }, Workspace.Terrain)
	local sparks = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 1, Enabled = false,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 120, 30)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.25, 0.6), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(75, 75),
		Acceleration = Vector3.new(0, -40, 0), EmissionDirection = Enum.NormalId.Top, Drag = 2,
	}, strikeAtt)
	local burst = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 1, Enabled = false,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180),
	}, strikeAtt)
	local flash = make("PointLight", { Color = Color3.fromRGB(255, 200, 120), Range = 12, Brightness = 0 }, strikeAtt)
	local steamAtt = make("Attachment", { WorldPosition = water.Position + Vector3.new(0, 0.2, 0) }, Workspace.Terrain)
	local steam = make("ParticleEmitter", {
		Texture = "rbxasset://textures/particles/smoke_main.dds", Enabled = false,
		Color = ColorSequence.new(Color3.fromRGB(230, 230, 235)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 4) }),
		Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
	}, steamAtt)
	-- (the attachments live under Terrain: tidied with the folder)
	folder.Destroying:Connect(function()
		strikeAtt:Destroy()
		steamAtt:Destroy()
	end)
	local _ = embers

	-- the camera: a three-quarter view from the hammer side, the hearth glowing beyond
	local camPos = (root * CFrame.new(12.5, 3.2, -8.5)).Position
	local look = (root * CFrame.new(-0.8, -0.9, -2)).Position
	return {
		folder = folder, root = root, smith = smith,
		rShoulder = rShoulder, rBase = rBase, lShoulder = lShoulder, lBase = lBase,
		hammerWeld = hammerWeld, ingot = ingot, coals = coals, hearthLight = hearthLight, flash = flash,
		bellowsBody = bellowsBody, bellowsTop = bellowsTop, bellowsBase = bellowsBase,
		sparks = sparks, steam = steam, burst = burst,
		anvilTop = strike, hearthSpot = hearthSpot, quenchSpot = water.Position,
		camHome = CFrame.lookAt(camPos, look),
	}
end

-- ── The overlay (kept small: the scene is the show) ─────────────────────────
local function text(parent: Instance, t: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1, FontFace = BOLD, Text = t, TextSize = size, TextColor3 = color,
		TextStrokeTransparency = 0.35, Size = UDim2.new(1, 0, 0, size + 6),
	}, parent)
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	return l
end

local function corner(o: Instance, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

local playing = false
local armoryToRestore: ScreenGui? = nil -- (re-opened when you're done, after any FORGE AGAIN)

function ForgeMinigame.Play(slot: string)
	if playing then return end
	playing = true
	local slotName = string.upper(PowerGear.SLOT_NAME[slot] or slot)
	local pg = player:WaitForChild("PlayerGui")

	-- every other screen steps aside while you forge (the Armory comes back after;
	-- the HUDs that keep themselves up watch "Forging")
	player:SetAttribute("Forging", true)
	local hidden: { ScreenGui } = {}
	for _, sg in ipairs(pg:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Enabled and sg.Name ~= "Armory" and sg.Name ~= "ForgeMinigame" then
			sg.Enabled = false
			table.insert(hidden, sg)
		end
	end
	local armoryGui = pg:FindFirstChild("Armory") :: ScreenGui?
	if armoryGui and armoryGui.Enabled then
		armoryToRestore = armoryGui
		armoryGui.Enabled = false
	end

	local scene = buildScene()

	-- the camera, held on the smithy (a little shake on each blow)
	local cam = Workspace.CurrentCamera
	local oldType = cam.CameraType
	local oldSubject = cam.CameraSubject
	local oldFov = cam.FieldOfView
	local shakeUntil, shakePower = 0, 0
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = 50
	RunService:BindToRenderStep("ForgeCamera", Enum.RenderPriority.Camera.Value + 10, function()
		cam.CameraType = Enum.CameraType.Scriptable
		local cf = scene.camHome
		local now = os.clock()
		if now < shakeUntil then
			local k = (shakeUntil - now) / 0.25 * shakePower
			cf *= CFrame.new((math.random() - 0.5) * 0.3 * k, (math.random() - 0.5) * 0.3 * k, 0)
		end
		cam.CFrame = cf
	end)

	-- the overlay
	local g = make("ScreenGui", { Name = "ForgeMinigame", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 70 }, pg)
	-- (a vignette, so the overlay reads against the fire)
	local vig = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0 }, g)
	make("UIGradient", { Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.22, 1), NumberSequenceKeypoint.new(0.78, 1), NumberSequenceKeypoint.new(1, 0.3),
	}), Rotation = 90 }, vig)
	text(g, "THE FORGE", 30, GOLD, { Position = UDim2.fromOffset(0, 26), Font = Enum.Font.Antique })
	local phaseLabel = text(g, `FORGING A {slotName}`, 14, PARCH, { Position = UDim2.fromOffset(0, 62) })
	local hint = text(g, "", 16, PARCH, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -26) })
	local function pop(t: string, color: Color3)
		local l = text(g, t, 34, color, { Position = UDim2.new(0, 0, 0.3, 0), TextStrokeTransparency = 0.1 })
		TweenService:Create(l, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0, 0, 0.3, -40), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.delay(0.85, function() l:Destroy() end)
	end

	-- input: bound above the game's own (Space would jump), sunk while forging
	local holding, pressed = false, false
	local acceptAfter = 0 -- (presses before this are ignored: the phase just started)
	ContextActionService:BindActionAtPriority("ForgeMinigame", function(_, state)
		if state == Enum.UserInputState.Begin then
			holding = true
			if os.clock() >= acceptAfter then pressed = true end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			holding = false
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)

	-- arm poses
	local function arm(a: number)
		if scene.rShoulder then scene.rShoulder.C0 = scene.rBase * CFrame.Angles(0, 0, a) end
	end
	local function leftArm(a: number)
		if scene.lShoulder then scene.lShoulder.C0 = scene.lBase * CFrame.Angles(0, 0, -a) end
	end

	-- ── 1. HEAT ──────────────────────────────────────────────────────────
	phaseLabel.Text = `FORGING A {slotName}   ·   1 / 2   HEAT`
	hint.Text = "HOLD to work the bellows  ·  keep the heat inside the band"
	local gauge = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -60, 0.5, 0), Size = UDim2.fromOffset(26, 300),
		BackgroundColor3 = Color3.fromRGB(20, 14, 12), BackgroundTransparency = 0.2 }, g)
	corner(gauge, 6)
	make("UIStroke", { Color = GOLD, Transparency = 0.4, Thickness = 1.4 }, gauge)
	local fill = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = heatColor(0.5), BorderSizePixel = 0 }, gauge)
	corner(fill, 6)
	local band = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 14, 0.2, 0), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1 }, gauge)
	local bandStroke = make("UIStroke", { Color = GOLD, Thickness = 2.5 }, band)
	corner(band, 4)
	text(gauge, "HEAT", 12, GOLD, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8), Size = UDim2.fromOffset(60, 16) })
	local inLabel = text(gauge, "", 13, PARCH, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -8), Size = UDim2.fromOffset(80, 16) })

	arm(ARM_REST)
	local heat, inBand, t = 0.1, 0, 0
	local phase0 = math.random() * 6
	local pump = 0
	while t < HEAT_TIME do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		heat = math.clamp(heat + (if holding then 0.7 else -0.4) * dt, 0, 1)
		local center = 0.6 + 0.22 * math.sin(phase0 + t * 1.3) + 0.06 * math.sin(phase0 * 2 + t * 3.1)
		local ok = math.abs(heat - center) <= 0.1
		if ok then inBand += dt end
		band.Position = UDim2.fromScale(0.5, 1 - center)
		bandStroke.Color = if ok then GREEN else GOLD
		fill.Size = UDim2.fromScale(1, heat)
		fill.BackgroundColor3 = heatColor(math.max(0.35, heat))
		inLabel.Text = `{math.floor(inBand / HEAT_TIME * 100 + 0.5)}%`
		-- the smith pumps the bellows while you hold; the hearth answers
		if holding then pump += dt * 9 end
		local squeeze = if holding then (math.sin(pump) + 1) / 2 else 0
		leftArm(math.rad(35 + 25 * squeeze))
		scene.bellowsBody.Size = Vector3.new(1.2, 0.6 - 0.35 * squeeze, 1.9)
		scene.bellowsBody.CFrame = scene.bellowsBase * CFrame.new(0, 0.38 - 0.17 * squeeze, 0)
		scene.bellowsTop.CFrame = scene.bellowsBase * CFrame.new(0, 0.75 - 0.35 * squeeze, 0)
		scene.hearthLight.Brightness = 1 + 3 * heat
		scene.coals.Color = heatColor(math.clamp(0.45 + heat * 0.5, 0, 1))
		scene.ingot.Color = heatColor(heat)
	end
	local heatScore = math.clamp(inBand / HEAT_TIME, 0, 1)
	gauge:Destroy()
	leftArm(math.rad(10))
	pop(`HEAT  {math.floor(heatScore * 100 + 0.5)}%`, if heatScore >= 0.7 then GREEN else GOLD)

	-- the ingot out of the coals and onto the anvil
	local from = scene.ingot.Position
	local to = scene.anvilTop - Vector3.new(0, 0.12, 0)
	local t0 = os.clock()
	while os.clock() - t0 < 0.55 do
		local k = (os.clock() - t0) / 0.55
		scene.ingot.CFrame = CFrame.new(from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2, 0)) * scene.root.Rotation
		RunService.RenderStepped:Wait()
	end
	scene.ingot.CFrame = CFrame.new(to) * scene.root.Rotation

	-- ── 2. HAMMER ────────────────────────────────────────────────────────
	phaseLabel.Text = `FORGING A {slotName}   ·   2 / 2   HAMMER`
	hint.Text = "PRESS to strike  ·  hit while the marker crosses the glowing mark"
	local bar = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -86), Size = UDim2.fromOffset(520, 22),
		BackgroundColor3 = Color3.fromRGB(20, 14, 12), BackgroundTransparency = 0.15 }, g)
	corner(bar, 6)
	make("UIStroke", { Color = GOLD, Transparency = 0.4, Thickness = 1.4 }, bar)
	local okZone = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0.24, 0, 1, 0), BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.8, BorderSizePixel = 0 }, bar)
	local goodZone = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0.12, 0, 1, 0), BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.5, BorderSizePixel = 0 }, bar)
	local perfectZone = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0.04, 0, 1, 0),
		BackgroundColor3 = Color3.fromRGB(255, 240, 200), BorderSizePixel = 0 }, bar)
	local marker = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 36), Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, bar)
	local pips = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(200, 14),
		BackgroundTransparency = 1 }, bar)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10) }, pips)
	local pipFrames = {}
	for i = 1, STRIKES do
		local pf = make("Frame", { Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(60, 50, 46), LayoutOrder = i }, pips)
		corner(pf, 6)
		pipFrames[i] = pf
	end

	-- the hammer goes up, ready
	local armAngle = ARM_REST
	local function swingTo(target: number, duration: number)
		local a0 = armAngle
		local s0 = os.clock()
		while os.clock() - s0 < duration do
			local k = (os.clock() - s0) / duration
			armAngle = a0 + (target - a0) * (1 - (1 - k) ^ 2)
			arm(armAngle)
			RunService.RenderStepped:Wait()
		end
		armAngle = target
		arm(armAngle)
	end
	swingTo(ARM_RAISED, 0.35)

	local hits = {}
	local pos, dir = 0, 1
	local ingotLen = 1
	for strike = 1, STRIKES do
		local mark = 0.2 + math.random() * 0.6
		for _, z in ipairs({ okZone, goodZone, perfectZone }) do z.Position = UDim2.fromScale(mark, 0) end
		local speed = 0.85 + 0.3 * (strike - 1) -- bar widths a second
		pressed = false
		acceptAfter = os.clock() + 0.15
		local waited = 0
		while not pressed do
			local dt = RunService.RenderStepped:Wait()
			waited += dt
			pos += dir * speed * dt
			if pos > 1 then pos, dir = 2 - pos, -1 elseif pos < 0 then pos, dir = -pos, 1 end
			marker.Position = UDim2.fromScale(pos, 0.5)
			-- (a little breathing at the top of the swing; the ingot cools)
			arm(ARM_RAISED + math.sin(os.clock() * 4) * 0.04)
			heat = math.max(0.35, heat - dt * 0.05)
			scene.ingot.Color = heatColor(heat)
			if waited > 6 then break end -- (no strike: a miss)
		end
		-- judged at the press; the blow lands right after
		local off = math.abs(pos - mark)
		local q, name, color
		if not pressed then
			q, name, color = 0, "MISS", RED
		elseif off <= 0.02 then
			q, name, color = 1, "PERFECT!", Color3.fromRGB(255, 240, 200)
		elseif off <= 0.06 then
			q, name, color = 0.75, "GOOD", GREEN
		elseif off <= 0.12 then
			q, name, color = 0.45, "OK", GOLD
		else
			q, name, color = 0.1, "MISS", RED
		end
		table.insert(hits, q)
		swingTo(ARM_IMPACT, DOWNSWING)
		-- the blow
		scene.sparks:Emit(if q >= 1 then 60 elseif q >= 0.75 then 36 elseif q > 0.2 then 18 else 6)
		scene.flash.Brightness = if q >= 1 then 8 else 4
		TweenService:Create(scene.flash, TweenInfo.new(0.3), { Brightness = 0 }):Play()
		shakeUntil, shakePower = os.clock() + 0.25, if q >= 1 then 1.6 elseif q >= 0.45 then 1 else 0.5
		pipFrames[strike].BackgroundColor3 = color
		pop(name, color)
		-- the ingot flattens a little with every blow
		ingotLen += 0.12
		scene.ingot.Size = Vector3.new(ingotLen, math.max(0.12, 0.24 - strike * 0.02), 0.45 + strike * 0.02)
		task.wait(0.06)
		if strike < STRIKES then swingTo(ARM_RAISED, RECOVER) end
	end
	local hammerScore = 0
	for _, q in ipairs(hits) do hammerScore += q end
	hammerScore /= STRIKES
	bar:Destroy()
	swingTo(ARM_REST, 0.4)

	-- ── 3. QUENCH ────────────────────────────────────────────────────────
	ContextActionService:UnbindAction("ForgeMinigame")
	local score = math.clamp(0.35 * heatScore + 0.65 * hammerScore, 0, 1)
	phaseLabel.Text = `FORGING A {slotName}   ·   QUENCHING`
	hint.Text = ""
	local q = text(g, `QUALITY  {math.floor(score * 100 + 0.5)}%   ·   {grade(score)}`, 26, GOLD, { Position = UDim2.fromOffset(0, 92) })
	q.TextTransparency = 1
	TweenService:Create(q, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()

	local result: any = nil
	local conn = Network.GetRemoteEvent(Network.Remotes.LootDrop).OnClientEvent:Connect(function(d: any)
		if typeof(d) == "table" and d.source == "forge" then result = d end
	end)
	Network.GetRemoteEvent(Network.Remotes.ArmoryAction):FireServer({ kind = "craft", slot = slot, score = score })

	-- into the barrel: a hiss of steam
	local inAt = scene.ingot.Position
	local t1 = os.clock()
	while os.clock() - t1 < 0.6 do
		local k = (os.clock() - t1) / 0.6
		scene.ingot.CFrame = CFrame.new(inAt:Lerp(scene.quenchSpot, k) + Vector3.new(0, math.sin(k * math.pi) * 2.5, 0)) * scene.root.Rotation
		RunService.RenderStepped:Wait()
	end
	scene.steam:Emit(30)
	scene.ingot.Color = heatColor(0.15)
	task.wait(0.8)
	local tw = os.clock()
	while not result and os.clock() - tw < 5 do task.wait(0.05) end
	conn:Disconnect()

	-- out of the water: the piece, in its rarity's colour, back on the anvil
	if result then
		local col = GearData.RARITY_COLOR[tostring(result.rarity)] or PARCH
		scene.ingot.CFrame = CFrame.new(scene.anvilTop + Vector3.new(0, 0.3, 0)) * scene.root.Rotation
		scene.ingot.Color = col
		scene.burst.Color = ColorSequence.new(col)
		scene.burst:Emit(70)
		scene.flash.Color = col
		scene.flash.Brightness = 6
		TweenService:Create(scene.flash, TweenInfo.new(1.2), { Brightness = 1.5 }):Play()
		shakeUntil, shakePower = os.clock() + 0.25, 1.2
		local card = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -90), Size = UDim2.fromOffset(460, 96),
			BackgroundColor3 = col:Lerp(Color3.fromRGB(16, 12, 14), 0.75), BackgroundTransparency = 0.05 }, g)
		corner(card, 8)
		make("UIStroke", { Color = col, Thickness = 2 }, card)
		text(card, `{string.upper(tostring(result.rarity))}  ·  {string.upper(tostring(result.slotName))}  ·  iLvl {result.ilvl}  ·  {result.itemPower} POWER`,
			12, col, { Position = UDim2.fromOffset(0, 8) })
		text(card, tostring(result.name), 24, Color3.new(1, 1, 1), { Position = UDim2.fromOffset(0, 26) })
		text(card, table.concat(result.stats or {}, "    "), 12, PARCH, { Position = UDim2.fromOffset(10, 60), Size = UDim2.new(1, -20, 0, 28),
			TextWrapped = true })
		local sc = make("UIScale", { Scale = 0.3 }, card)
		TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		if result.worn then pop(`WORN!  ▲ +{result.gain}`, GREEN) end
	else
		text(g, "The forge went cold. Try again.", 18, MUTED, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -110) })
	end

	-- done (or again, while the scrap lasts)
	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(420, 40),
		BackgroundTransparency = 1 }, g)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 14) }, row)
	local function close(again: boolean)
		RunService:UnbindFromRenderStep("ForgeCamera")
		ContextActionService:UnbindAction("ForgeMinigame")
		cam.CameraType = oldType
		cam.CameraSubject = oldSubject
		cam.FieldOfView = oldFov
		scene.folder:Destroy()
		g:Destroy()
		player:SetAttribute("Forging", nil)
		for _, sg in ipairs(hidden) do
			if sg.Parent then sg.Enabled = true end
		end
		if not again and armoryToRestore then
			armoryToRestore.Enabled = true
			armoryToRestore = nil
		end
		playing = false
		if again then task.defer(ForgeMinigame.Play, slot) end
	end
	local function button(label: string, color: Color3, order: number, fn: () -> ())
		local b = make("TextButton", { Size = UDim2.fromOffset(190, 40), BackgroundColor3 = color, FontFace = BOLD, TextSize = 15,
			TextColor3 = GOLD, Text = label, LayoutOrder = order }, row)
		corner(b, 6)
		make("UIStroke", { Color = GOLD, Transparency = 0.5 }, b)
		b.MouseButton1Click:Connect(fn)
	end
	button("DONE", Color3.fromRGB(60, 40, 30), 2, function() close(false) end)
	task.wait(0.3) -- (the scrap count arrives with the sync)
	local scrap = 0
	pcall(function()
		local armory = require(script.Parent:WaitForChild("Armory")) :: any
		scrap = armory.Scrap()
	end)
	if scrap >= PowerGear.CRAFT_COST then
		button(`FORGE AGAIN  ·  {PowerGear.CRAFT_COST}`, Color3.fromRGB(110, 70, 26), 1, function() close(true) end)
	end
end

return ForgeMinigame
