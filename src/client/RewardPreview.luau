--[[
	RewardPreview.luau
	Builds a showcase model for a gacha reward: the thing you get, on its own.

	  character / variant    the class's hero, dressed as the class (its
	                         weapon, and its armour where that's part of the
	                         class), in the class's ultimate pose (as on the
	                         class-select screen); a variant adds an aura in its
	                         colour and its title overhead (a universal variant
	                         is shown on your class)
	  armor                  the armour itself, as if worn by someone invisible,
	                         turning slowly
	  wings                  the wings alone, spread and flapping, seen from
	                         behind and swaying round
	  mount                  the mount alone, walking in place three-quarters to
	                         the camera (shrunk to fit if it's a big one)
	  relic / material       a floating crystal with the item's icon
	  cosmetic (title)       the title itself, hanging in the air

	The model's pivot is where a character's root would be (about three studs
	over the floor), so it stands wherever a figure would.

	RewardPreview.Build(reward) → (model, cleanup)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local ClassArmor = require(Shared:WaitForChild("ClassArmor"))
local IceCape = require(Shared:WaitForChild("IceCape"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassLook = require(script.Parent:WaitForChild("ClassLook"))
local WingsMounts = require(script.Parent:WaitForChild("WingsMounts"))
local ClothCape = require(script.Parent:WaitForChild("ClothCape"))
local RogueScarf = require(script.Parent:WaitForChild("RogueScarf"))
local MageLook = require(Shared:WaitForChild("MageLook"))
local MartialLook = require(Shared:WaitForChild("MartialLook"))

local player = Players.LocalPlayer

local RewardPreview = {}

local FLOOR = 3      -- the pivot's height over the floor (a character's root)
local FIT = 6.5      -- the biggest a mount is shown, end to end (studs)

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

local function billboard(adornee: BasePart, str: string, color: Color3, offsetY: number): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 40)
	bb.StudsOffset = Vector3.new(0, offsetY, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = adornee
	bb.Parent = adornee
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Antique
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = str
	t.Parent = bb
	return bb
end

local function sparkles(parent: Instance, color: Color3, rate: number, size: number)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	pe.LightEmission, pe.LightInfluence = 1, 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.8, 1.4)
	pe.Speed = NumberRange.new(1, 3)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Acceleration = Vector3.new(0, 3, 0)
	pe.Rate = rate
	pe.Parent = parent
	return pe
end

-- An empty showcase: an invisible root at the pivot.
local function emptyModel(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "RewardPreview"
	local root = part(model, { Name = "Root", Size = Vector3.one * 0.2, Transparency = 1 })
	model.PrimaryPart = root
	return model, root
end

-- A copy of the player's character with nothing of their kit on it (weapon,
-- armour, capes, auras, effects). `plain`: a blank gray body too (no
-- clothing, accessories, face or colours).
local function characterCopy(plain: boolean): Model?
	local char = player.Character
	if not char then return nil end
	local was = char.Archivable
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = was
	if not clone then return nil end
	clone.Name = "RewardPreview"
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Tool") or d:IsA("Constraint") or d:IsA("BodyMover") or d:IsA("Sound") or d:IsA("ForceField")
			or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light") or d:IsA("Highlight")
			or (d:IsA("BillboardGui") and d.Name ~= "Title")
			or (d:IsA("Model") and d.Name == "IceCape")
			or string.sub(d.Name, 1, 4) == "Gear" or d.Name == "StowedWeapon"
			or d:GetAttribute("PreviewArmor") or d:GetAttribute("PreviewWeapon") then
			d:Destroy()
		end
	end
	-- Any class armour already worn (welded with ArmorWeld).
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("WeldConstraint") and d.Name == "ArmorWeld" and d.Parent then
			local piece = d.Parent
			while piece.Parent and piece.Parent ~= clone do piece = piece.Parent end
			if piece.Parent == clone and not piece:IsA("Humanoid") and piece.Name ~= "HumanoidRootPart" then
				piece:Destroy()
			end
		end
	end
	for _, d in ipairs(clone:GetChildren()) do
		-- Anything left that isn't the body (armour models, capes...).
		if d:IsA("Model") or d:IsA("Folder") then d:Destroy() end
	end
	if plain then
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("BodyColors")
				or d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
				d:Destroy()
			elseif d:IsA("SpecialMesh") then
				d.TextureId = ""
			end
		end
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("MeshPart") then d.TextureID = "" end
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
				d.Color = Color3.fromRGB(163, 162, 165)
				d.Material = Enum.Material.SmoothPlastic
				d.Transparency = 0
			end
		end
	end
	-- Back to the rest pose: the copy is taken mid-animation, and armour welded
	-- on (WeldConstraints keep the offset they're made with) would stay where
	-- the limbs were, then slip off them once the joints settle in the world.
	local rootPart = clone:FindFirstChild("HumanoidRootPart")
	if rootPart and rootPart:IsA("BasePart") then
		local motors: { Motor6D } = {}
		for _, d in ipairs(clone:GetDescendants()) do
			if d:IsA("Motor6D") then table.insert(motors, d) end
		end
		local placed: { [BasePart]: boolean } = { [rootPart] = true }
		local moved = true
		while moved do
			moved = false
			for _, m in ipairs(motors) do
				local p0, p1 = m.Part0, m.Part1
				if p0 and p1 and placed[p0] and not placed[p1] then
					p1.CFrame = p0.CFrame * m.C0 * m.C1:Inverse()
					placed[p1] = true
					moved = true
				end
			end
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.PlatformStand = true
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Anchored = d.Name == "HumanoidRootPart"
		end
	end
	return clone
end

local function crystal(parent: Instance, reward: any, size: number): BasePart
	local color = GachaConfig.Rarities[reward.rarity].color
	local core = part(parent, { Name = "RelicCrystal", Size = Vector3.new(0.9, 1.6, 0.9) * size, Material = Enum.Material.Glass, Color = color, Transparency = 0.1 })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(70 * size, 70 * size)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = core
	bb.Parent = core
	local g = Instance.new("TextLabel")
	g.Name = "Glyph"
	g.Size = UDim2.fromScale(1, 1)
	g.BackgroundTransparency = 1
	g.Font = Enum.Font.GothamBold
	g.TextScaled = true
	g.Text = reward.glyph or "?"
	g.Parent = bb
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, 2, 10
	light.Parent = core
	sparkles(core, color, 12, 0.3)
	return core
end

-- Character-space turn → a motor's own frame (as CastPoses).
local function turnMotor(m: Motor6D, yaw: number)
	local basis = m.C0.Rotation
	m.Transform = basis:Inverse() * CFrame.Angles(0, yaw, 0) * basis
end

-- ── The showcases ──────────────────────────────────────────────────────────

-- A relic or material: the crystal, floating and turning.
local function crystalShowcase(reward: any): (Model, () -> ())
	local model, root = emptyModel()
	local core = crystal(model, reward, 1.6)
	local conn = RunService.RenderStepped:Connect(function()
		if not core.Parent then return end
		local t = os.clock()
		core.CFrame = root.CFrame * CFrame.new(0, 0.4 + math.sin(t * 1.6) * 0.15, 0) * CFrame.Angles(0, t * 1.2, 0)
	end)
	return model, function()
		conn:Disconnect()
		model:Destroy()
	end
end

-- A title: the words themselves, hanging in the air.
local function titleShowcase(reward: any, accent: Color3): (Model, () -> ())
	local model, root = emptyModel()
	local plate = part(model, { Name = "TitlePlate", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1 })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(9, 2.4) -- (studs: it grows and shrinks with the camera, like an object)
	bb.LightInfluence = 0
	bb.Adornee = plate
	bb.Parent = plate
	local t = Instance.new("TextLabel")
	t.Name = "Title"
	t.Size = UDim2.fromScale(1, 0.75)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Antique
	t.TextScaled = true
	t.TextColor3 = accent
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.TextStrokeTransparency = 0.2
	t.Text = "« " .. (reward.title or reward.name) .. " »"
	t.Parent = bb
	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.fromScale(0.5, 0.8)
	rule.Size = UDim2.fromScale(0.7, 0.04)
	rule.BorderSizePixel = 0
	rule.BackgroundColor3 = accent
	rule.Parent = bb
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = rule
	sparkles(plate, accent, 14, 0.35)
	local conn = RunService.RenderStepped:Connect(function()
		if not plate.Parent then return end
		plate.CFrame = root.CFrame * CFrame.new(0, 0.6 + math.sin(os.clock() * 1.4) * 0.12, 0)
	end)
	return model, function()
		conn:Disconnect()
		model:Destroy()
	end
end

-- Wings or a mount: the rig alone, jointed to a turntable on the root.
local function rideShowcase(reward: any): (Model, () -> ())
	local model, root = emptyModel()
	local rig = WingsMounts.Build(reward.id, true)
	if not rig then return model, function() model:Destroy() end end
	local isWings = reward.type == "wings"
	-- (how big it is standing still, to shrink a big mount to fit)
	local lo, hi = Vector3.one * math.huge, -Vector3.one * math.huge
	for _, piece in ipairs(rig.pieces) do
		for k, p in ipairs(piece.parts) do
			if p.Transparency < 1 then
				local cf = piece.home * piece.offsets[k]
				local h = p.Size / 2
				for _, c in ipairs({ Vector3.new(-1, -1, -1), Vector3.new(1, 1, 1), Vector3.new(-1, 1, 1), Vector3.new(1, -1, -1),
					Vector3.new(1, -1, 1), Vector3.new(-1, 1, -1), Vector3.new(1, 1, -1), Vector3.new(-1, -1, 1) }) do
					local w = cf * (c * h)
					lo, hi = lo:Min(w), hi:Max(w)
				end
			end
		end
	end
	local span = if lo.X < math.huge then math.max(hi.X - lo.X, hi.Y - lo.Y, hi.Z - lo.Z) else 1
	local k = if isWings then 1 else math.min(1, FIT / span)
	-- the turntable: a joint on the root that turns it
	local spin = part(model, { Name = "Turntable", Size = Vector3.one * 0.2, Transparency = 1 })
	spin.Anchored = false
	spin.Massless = true
	local motor = Instance.new("Motor6D")
	motor.Part0, motor.Part1 = root, spin
	motor.Parent = spin
	rig.model.Parent = model
	-- wings at the height of a back, their back to the camera; a mount on the
	-- floor, three-quarters on (offsets in studs once shrunk, hence / k)
	local off = if isWings then CFrame.new(0, 0.8, 0) * CFrame.Angles(0, math.pi, 0)
		else CFrame.new(0, -FLOOR / k, 0) * CFrame.Angles(0, math.rad(-35), 0)
	WingsMounts.Attach(rig, spin, off)
	if k < 1 then model:ScaleTo(k) end
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		if not model.Parent then return end
		local t = os.clock() - t0
		motor.Transform = CFrame.Angles(0, math.sin(t * 0.5) * (if isWings then 0.6 else 0.45), 0)
		WingsMounts.Animate(rig, os.clock(), if isWings then 0.4 else 0.45)
	end)
	return model, function()
		conn:Disconnect()
		model:Destroy()
	end
end

-- Armour: worn by someone invisible, turning slowly.
local function armorShowcase(reward: any, classId: string): (Model, () -> ())
	local model = characterCopy(true) or Instance.new("Model")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then model.PrimaryPart = root end
	ClassArmor.Equip(model, classId, "RewardPreview")
	if classId == "ice_mage" then IceCape.Attach(model, "RewardPreview") end
	if classId == "heavy_knight" then ClothCape.Attach(model, "RewardPreview", ClothCape.FIRE_KNIGHT) end
	if classId == "gunslinger" then ClothCape.Attach(model, "RewardPreview", ClothCape.GUNSLINGER) end
	if classId == "swordsman" then ClothCape.Attach(model, "RewardPreview", ClothCape.SWORD_MASTER) end
	if classId == "berserker" then ClothCape.Attach(model, "RewardPreview", ClothCape.BERSERKER) end
	if classId == "mage" then
		MageLook.Dress(model)
		ClothCape.Attach(model, "RewardPreview", ClothCape.MAGE)
	end
	if classId == "martial_artist" then MartialLook.Dress(model) end
	-- (the scarf once the model's been placed: RogueScarf drops unparented ones)
	if classId == "rogue" then
		task.defer(function()
			if model.Parent then RogueScarf.Track(model, true) end
		end)
	end
	-- (the body itself out of sight: only what's worn on it shows)
	for _, name in ipairs({ "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
		"UpperTorso", "LowerTorso", "LeftUpperArm", "LeftLowerArm", "LeftHand", "RightUpperArm", "RightLowerArm", "RightHand",
		"LeftUpperLeg", "LeftLowerLeg", "LeftFoot", "RightUpperLeg", "RightLowerLeg", "RightFoot" }) do
		local p = model:FindFirstChild(name)
		if p and p:IsA("BasePart") then p.Transparency = 1 end
	end
	local lower = model:FindFirstChild("LowerTorso")
	local rootJoint = (root and root:FindFirstChild("RootJoint")) or (lower and lower:FindFirstChild("Root"))
	local t0 = os.clock()
	local conn = RunService.Stepped:Connect(function()
		if rootJoint and rootJoint:IsA("Motor6D") then turnMotor(rootJoint, (os.clock() - t0) * 0.6) end
	end)
	return model, function()
		conn:Disconnect()
		RogueScarf.Track(model, false)
		model:Destroy()
	end
end

-- Heroes turned from how the showcase is pivoted (degrees, + to his left):
-- the Swordsman's en garde is side on, so a quarter turn shows him to you.
local SHOWCASE_YAW: { [string]: number } = { swordsman = -90 }

-- The Fire Knight at ease: the greatsword hanging point down at his right
-- side, clear of his body (in his ultimate's animation it lay across his
-- chest and hid him), his head turned a little to you.
local FIRE_KNIGHT_TILT = CFrame.Angles(math.rad(-70), 0, 0)
local FIRE_KNIGHT_EASE = { RS = { 8, 0, 8 }, LS = { -4, 0, -6 }, N = { -4, 10, 0 }, W = { 0, -8, 0 } }

-- The weapon in hand as the class select holds it: the Swordsman's blade
-- upright.
local function heroGrip(classId: string, grip: CFrame): CFrame
	if classId == "swordsman" then return grip * CFrame.Angles(math.rad(90), 0, 0) end
	return grip
end

-- ── The Death Knight on his throne ─────────────────────────────────────────
-- He sits on a black stone throne up on a dais, his hands on its armrests,
-- the Graveblade standing head down on the dais at his right and leaning in
-- against the throne, while ghosts (sprites rendered in Blender) pour out
-- from behind it and drift away. Everything is in the root's space (+Z behind
-- him), the seat set so his head stays where a standing hero's is: the
-- portraits frame him the same.
-- (the Graveblade: its handle's place, turned over so the head is down, and
-- tipped in toward him; shown at half size, or it would tower over the throne)
local THRONE_PLANT = CFrame.new(2.95, 0.95, -0.55) * CFrame.Angles(0, 0, math.rad(7)) * CFrame.Angles(math.pi, 0, 0)
local THRONE_PLANT_SCALE = 0.5
local THRONE_SEATED = { W = { -5, 0, 0 }, N = { -4, 0, 0 }, RS = { 52, 0, 14 }, LS = { 52, 0, -14 },
	RH = { 80, 0, 7 }, LH = { 80, 0, -7 } }
local THRONE_STONE = Color3.fromRGB(42, 40, 52)
local THRONE_SOUL = Color3.fromRGB(70, 150, 210)
local GHOSTS = { "rbxassetid://103138279346123", "rbxassetid://110866102668351", "rbxassetid://134933143163501" }
local GHOST_COUNT = 8

local function buildThrone(model: Model, root: BasePart)
	local folder = Instance.new("Model")
	folder.Name = "Throne"
	folder.Parent = model
	local at = root.CFrame
	local diamond = CFrame.Angles(0, 0, math.rad(45))
	local function stone(size: Vector3, x: number, y: number, z: number, rot: CFrame?)
		part(folder, { Size = size, CFrame = at * CFrame.new(x, y, z) * (rot or CFrame.identity), Color = THRONE_STONE,
			Material = Enum.Material.Slate })
	end
	local function seam(size: Vector3, x: number, y: number, z: number)
		-- (not Neon: in a viewport it burns flat white-blue)
		part(folder, { Size = size, CFrame = at * CFrame.new(x, y, z), Color = THRONE_SOUL, Material = Enum.Material.SmoothPlastic })
	end
	stone(Vector3.new(6.4, 3.4, 4.8), 0, -3.8, -0.4) -- the dais (its foot runs out of the picture)
	seam(Vector3.new(6.4, 0.08, 0.08), 0, -2.12, -2.81) -- its front edge
	stone(Vector3.new(3.4, 0.7, 2.4), 0, -1.8, -0.1) -- seat
	seam(Vector3.new(3.4, 0.08, 0.08), 0, -1.47, -1.32) -- the seat's edge
	stone(Vector3.new(3.6, 5.1, 0.6), 0, 1.1, 1.15) -- back
	stone(Vector3.new(2.1, 2.1, 0.6), 0, 3.65, 1.15, diamond) -- its pointed top
	for _, s in ipairs({ -1, 1 }) do
		stone(Vector3.new(0.7, 6.3, 0.7), s * 2.0, 0.75, 1.15) -- pillar
		stone(Vector3.new(0.6, 0.6, 0.6), s * 2.0, 4.1, 1.15, diamond) -- finial
		stone(Vector3.new(0.55, 0.35, 2.3), s * 1.95, -0.55, -0.05) -- armrest
		stone(Vector3.new(0.4, 0.75, 0.4), s * 1.95, -1.08, -1.0) -- its post
		seam(Vector3.new(0.08, 4.0, 0.06), s * 1.25, 1.1, 0.83)
		seam(Vector3.new(0.07, 5.8, 0.06), s * 2.0, 0.75, 0.78)
	end
	seam(Vector3.new(2.6, 0.08, 0.06), 0, 3.1, 0.83)
	seam(Vector3.new(2.6, 0.08, 0.06), 0, -0.9, 0.83)
	part(folder, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.55, CFrame = at * CFrame.new(0, 3.7, 0.8), Color = THRONE_SOUL })
end

-- The ghosts: flat sprites turned to the viewport's camera every frame
-- (particles and billboards don't draw in a ViewportFrame), each rising out
-- from behind the throne and drifting off to one side, fading in and out,
-- then starting again somewhere else.
type Ghost = { part: BasePart, decal: Decal, from: Vector3, path: Vector3, size: number, life: number, age: number,
	roll: number, side: number }
local function ghostFlight(model: Model, root: BasePart): RBXScriptConnection
	local rng = Random.new()
	local ghosts: { Ghost } = {}
	local function launch(g: Ghost)
		g.side = if rng:NextNumber() < 0.5 then -1 else 1
		g.from = Vector3.new(g.side * rng:NextNumber(0.4, 1.6), rng:NextNumber(0.3, 2.2), 1.7)
		-- (out to the side and up, staying beside and behind him: never over his face)
		g.path = Vector3.new(g.side * rng:NextNumber(1.8, 3.4), rng:NextNumber(1.0, 2.4), rng:NextNumber(-1.4, -0.4))
		g.size = rng:NextNumber(2.0, 2.8)
		g.life = rng:NextNumber(3.2, 4.4)
		g.roll = rng:NextNumber(-12, 12)
		g.decal.Texture = GHOSTS[rng:NextInteger(1, #GHOSTS)]
		g.age = 0
	end
	for i = 1, GHOST_COUNT do
		local p = part(model, { Name = "Ghost", Size = Vector3.new(2, 2, 0.05), Transparency = 1, CFrame = root.CFrame })
		local d = Instance.new("Decal")
		d.Face = Enum.NormalId.Front
		d.Transparency = 1
		-- (over 1: brighter than the sprite, glowing against the dark)
		d.Color3 = Color3.new(1.3, 1.45, 1.6)
		d.Parent = p
		local g: Ghost = { part = p, decal = d, from = Vector3.zero, path = Vector3.zero, size = 2, life = 4, age = 0, roll = 0, side = 1 }
		launch(g)
		-- (already spread through their flights when it opens)
		g.age = g.life * (i - 1) / GHOST_COUNT
		table.insert(ghosts, g)
	end
	return RunService.RenderStepped:Connect(function(dt)
		local vp = model:FindFirstAncestorWhichIsA("ViewportFrame")
		local cam = vp and vp.CurrentCamera
		if not cam then return end
		local base = root.CFrame
		for _, g in ipairs(ghosts) do
			g.age += dt
			if g.age >= g.life then launch(g) end
			local u = g.age / g.life
			-- out and up along a curve (fast at first, easing off), swaying
			local e = 1 - (1 - u) ^ 2
			local sway = math.sin(g.age * 2.6 + g.roll) * 0.25
			local off = g.from + Vector3.new(g.path.X * e + sway, g.path.Y * u + math.sin(u * math.pi) * 0.4, g.path.Z * e)
			local pos = base:PointToWorldSpace(off)
			local fade = math.clamp(math.min(u / 0.18, (1 - u) / 0.3), 0, 1)
			local s = g.size * (0.7 + 0.35 * e)
			g.part.Size = Vector3.new(s, s, 0.05)
			-- facing the camera, leaning into its drift
			g.part.CFrame = CFrame.lookAt(pos, cam.CFrame.Position) * CFrame.Angles(0, 0, math.rad(g.roll - g.side * 14 * e))
			g.decal.Transparency = 1 - 0.95 * fade
		end
	end)
end

-- ── The Rogue's crouch ──────────────────────────────────────────────────────
-- After the class portrait: low on one knee, his left fist planted on the
-- ground, the dagger drawn back in his right in a reverse grip. The R6 rig
-- has no knees, so its legs are let go of their joints: each stands in for a
-- shin, placed where that would be (the thighs are left to the eye). The
-- arms stay on their shoulders, the body sunk and leaning over the left one
-- far enough for its fist to reach the floor. Every part's place is given in
-- the root's space: +X his right, +Y up (the floor 3 below), -Z the way he
-- faces.
local function aim(pos: Vector3, up: Vector3, front: Vector3): CFrame
	local u = up.Unit
	local look = (front - u * front:Dot(u)).Unit
	return CFrame.fromMatrix(pos, look:Cross(u), u, -look)
end
local ROGUE_CROUCH: { [string]: CFrame } = (function()
	local V = Vector3.new
	local spine = V(-0.34, 0.68, -0.65).Unit -- leaning hard toward you, and over his left arm
	local pelvis = V(0.1, -2.2, 0.6)
	local torso = aim(pelvis + spine, spine, V(0.22, -0.6, -0.77))
	local neck = pelvis + spine * 2
	local headUp = V(-0.12, 0.96, -0.24).Unit
	-- An arm hanging off its shoulder along `dir` (the shoulder: the top of
	-- the arm, where it turns).
	local function arm(side: number, dir: Vector3, front: Vector3): CFrame
		local d = dir.Unit
		return aim(torso * V(side * 1.5, 0.5, 0) + d * 0.5, -d, front)
	end
	-- (the left fist: on the floor ahead of him, as near under the shoulder as it reaches)
	local leftShoulder = torso * V(-1.5, 0.5, 0)
	return {
		Torso = torso,
		Head = aim(neck + headUp * 0.55 + V(0, 0, -0.1), headUp, V(0.06, -0.2, -1)), -- chin tucked, eyes on you
		["Left Arm"] = arm(-1, V(-1.9, -3, -1.75) - leftShoulder, V(0.15, 0, -1)),
		["Right Arm"] = arm(1, V(0.76, 0.54, -0.36), V(0.3, -0.3, -0.9)), -- drawn up and back
		["Right Leg"] = aim(V(1.25, -2.0, -1.35), V(-0.03, 0.99, -0.12), V(0.45, 0, -0.9)), -- the shin upright, boot planted
		["Left Leg"] = aim(V(-1.25, -2.5, 0.55), V(-0.12, 0.08, -0.99), V(0, -1, 0)), -- the shin back along the floor
	}
end)()
-- The dagger in the right fist (the arm's space): reversed, the blade out of
-- the bottom of the fist and away from him, its flat to you.
local ROGUE_GRIP: CFrame = (function()
	local arm = ROGUE_CROUCH["Right Arm"]
	local rot = CFrame.lookAt(Vector3.zero, Vector3.new(0.62, -0.68, -0.4).Unit, Vector3.new(0, 0, -1))
	-- (0.04, 0.1, 0.32: the point of the handle that sits in the fist, RogueLook's GRIP_AT)
	local handle = rot + (arm * Vector3.new(0, -0.8, 0) - rot:VectorToWorldSpace(Vector3.new(0.04, 0.1, 0.32)))
	return arm:Inverse() * handle
end)()
-- What a portrait has to show to see all of him (the root's space): the
-- middle of the pose, and how wide and tall it is.
local ROGUE_FRAME_AT = Vector3.new(0.5, -0.57, -0.3)
local ROGUE_FRAME_SIZE = Vector2.new(6.3, 5.6)

-- A weapon built in code is put together away from the hero, then welded to
-- the hand. Once the copy is in a viewport that weld brings only the handle:
-- the pieces riding on it (WeldConstraints) stay where they were built,
-- thousands of studs off. So every welded weapon is moved, whole, to where
-- its weld will hold it.
local function seatWeapons(model: Model)
	for _, w in ipairs(model:GetDescendants()) do
		if not (w:IsA("Weld") and (w.Name == "LookGrip" or w.Name == "OffHandGrip")) then continue end
		local hand, handle = w.Part0, w.Part1
		local tool = handle and handle:FindFirstAncestorOfClass("Tool")
		if not (hand and handle and tool) then continue end
		local links: { Instance } = {}
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("WeldConstraint") or d:IsA("JointInstance") then table.insert(links, d) end
		end
		-- (everything joined to this handle, however many joints away)
		local group: { [BasePart]: boolean } = { [handle] = true }
		local queue: { BasePart } = { handle }
		while #queue > 0 do
			local p = table.remove(queue) :: BasePart
			for _, l in ipairs(links) do
				local a, b = (l :: any).Part0, (l :: any).Part1
				local other = if a == p then b elseif b == p then a else nil
				if other and not group[other] and other:IsDescendantOf(tool) then
					group[other] = true
					table.insert(queue, other)
				end
			end
		end
		local delta = (hand.CFrame * w.C0 * w.C1:Inverse()) * handle.CFrame:Inverse()
		local to: { [BasePart]: CFrame } = {}
		for p in pairs(group) do to[p] = delta * p.CFrame end
		for p, cf in pairs(to) do p.CFrame = cf end
	end
end

-- A class (or a variant of one): its hero, dressed as the class, in the
-- class's ultimate pose.
local function heroShowcase(reward: any, classId: string, accent: Color3): (Model, () -> ())
	local conns: { RBXScriptConnection } = {}
	local model = characterCopy(false) or Instance.new("Model")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then model.PrimaryPart = root end
	-- (turned on the spot: wherever the model is pivoted, the hero stands
	-- this many degrees round from it)
	local yaw = SHOWCASE_YAW[classId]
	if root and yaw then root.PivotOffset = CFrame.Angles(0, math.rad(-yaw), 0) end
	local throned = classId == "death_knight" and root ~= nil
	local atEase = classId == "heavy_knight"
	-- (the crouch lets go of an R6 rig's joints: other rigs keep the class's pose)
	local crouch = classId == "rogue" and root ~= nil and model:FindFirstChild("Torso") ~= nil
	if throned and root then
		buildThrone(model, root)
		table.insert(conns, ghostFlight(model, root))
	end
	pcall(ClassLook.Apply, model, classId, {
		armor = player:GetAttribute(`Armor_{classId}`) == true,
		grip = heroGrip,
		-- (the crouch places the dagger itself; a tilt also keeps the arm
		-- out of Roblox's tool-holding animation)
		handTilt = if atEase then FIRE_KNIGHT_TILT elseif crouch then CFrame.identity else nil,
		plant = if throned then THRONE_PLANT else nil,
		plantScale = if throned then THRONE_PLANT_SCALE else nil,
	})
	if crouch and root then
		local arm = model:FindFirstChild("Right Arm")
		local grip = arm and arm:FindFirstChild("LookGrip")
		if grip and grip:IsA("Weld") then
			grip.C0, grip.C1 = ROGUE_GRIP, CFrame.identity
		end
		-- The second knife away: the left fist is on the floor.
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("Weld") and d.Name == "OffHandGrip" and d.Part1 then
				local off = d.Part1
				local tool = off:FindFirstAncestorOfClass("Tool")
				for _, c in ipairs(if tool then tool:GetDescendants() else {}) do
					if c:IsA("WeldConstraint") and c.Part0 == off and c.Part1 then c.Part1:Destroy() end
				end
				off:Destroy()
			end
		end
		-- (for whoever frames the portrait: see SummonScreen's setPortrait)
		model:SetAttribute("FrameAt", ROGUE_FRAME_AT)
		model:SetAttribute("FrameSize", ROGUE_FRAME_SIZE)
		-- Each joint turned so its part sits where the crouch puts it. Written
		-- after the Animator's own pass every frame, so nothing playing on
		-- the copy can pull a limb back.
		local placed: { { motor: Motor6D, at: CFrame } } = {}
		for _, d in ipairs(model:GetDescendants()) do
			if not d:IsA("Motor6D") then continue end
			local p0, p1 = d.Part0, d.Part1
			local target = p1 and ROGUE_CROUCH[p1.Name]
			if not (p0 and target) then continue end
			local base = if p0 == root then CFrame.identity else ROGUE_CROUCH.Torso
			table.insert(placed, { motor = d, at = (base * d.C0):Inverse() * target * d.C1 })
		end
		table.insert(conns, RunService.Stepped:Connect(function()
			for _, j in ipairs(placed) do j.motor.Transform = j.at end
		end))
	end
	seatWeapons(model)
	-- CastPoses multiplies its pose onto Motor6D.Transform every frame, relying
	-- on the Animator to reset the joints first. The copy has no animation
	-- playing, so reset them ourselves or the pose compounds and the rig spins.
	local motors: { Motor6D } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then table.insert(motors, d) end
	end
	local resetEvent = (RunService :: any).PreAnimation or RunService.RenderStepped
	table.insert(conns, resetEvent:Connect(function()
		for _, m in ipairs(motors) do m.Transform = CFrame.identity end
	end))
	-- Pose once it's in the world (motors need a parent to animate).
	model.AncestryChanged:Connect(function(_, parent)
		if not (parent and root) then return end
		if crouch then return end -- (held by its joints, above)
		-- The Death Knight on his throne, the Fire Knight at ease; the other
		-- classes their ultimate's held pose, as on the class select.
		local held = if throned then THRONE_SEATED elseif atEase then FIRE_KNIGHT_EASE else nil
		if held then
			CastPoses.play(model, {
				{ dur = 0.05, pose = held },
				-- (held still until CastPoses.stop: portraits don't move)
				{ dur = 1e6, pose = held },
			}, nil, true)
			return
		end
		if CastPoses.holdUltPreview(model, classId, { still = true }) then return end
		local humanoid = model:FindFirstChildOfClass("Humanoid")
		if not humanoid then return end
		local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
		animator.Parent = humanoid
		local anim = Instance.new("Animation")
		anim.AnimationId = "rbxassetid://101434181844277"
		local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
		if ok and track then
			track.Looped = true
			track:Play(0)
		end
	end)
	if root and reward.type == "variant" then
		-- Its aura in the variant's colours, and its title overhead.
		local a = Instance.new("Attachment")
		a.Parent = root
		sparkles(a, accent, 40, 0.45)
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range = accent, 2.5, 14
		l.Parent = root
		billboard(root, reward.title or reward.name, accent, 4.2)
	end
	return model, function()
		for _, c in ipairs(conns) do c:Disconnect() end
		CastPoses.stop(model)
		model:Destroy()
	end
end

function RewardPreview.Build(reward: any): (Model, () -> ())
	local accent = reward.accent or GachaConfig.Rarities[reward.rarity].color
	local classId = reward.classId
		or (typeof(player:GetAttribute("SelectedClass")) == "string" and player:GetAttribute("SelectedClass"))
		or "heavy_knight"
	if reward.type == "material" or reward.type == "relic" then return crystalShowcase(reward) end
	if reward.type == "cosmetic" then return titleShowcase(reward, accent) end
	if reward.type == "wings" or reward.type == "mount" then return rideShowcase(reward) end
	if reward.type == "armor" then return armorShowcase(reward, classId) end
	return heroShowcase(reward, classId, accent)
end

return RewardPreview
