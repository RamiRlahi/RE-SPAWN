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
	local rig = WingsMounts.Build(reward.id)
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
		model:Destroy()
	end
end

-- A class (or a variant of one): its hero, dressed as the class, in the
-- class's ultimate pose.
local function heroShowcase(reward: any, classId: string, accent: Color3): (Model, () -> ())
	local conns: { RBXScriptConnection } = {}
	local model = characterCopy(false) or Instance.new("Model")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then model.PrimaryPart = root end
	pcall(ClassLook.Apply, model, classId, { armor = GachaRewards.BuiltInArmor[classId] == true })
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
		-- Same pose as the class-select screen: the Heavy Knight uses its
		-- uploaded animation, the other classes a held procedural pose.
		if classId ~= "heavy_knight" and CastPoses.holdUltPreview(model, classId) then return end
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
