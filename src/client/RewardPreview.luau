--[[
	RewardPreview.luau
	Builds a showcase model showing how a gacha reward looks on the character it
	belongs to — a copy of the local player's character, dressed with the same
	shared code the real game uses:

	  character / exclusive  that class's armor (ClassArmor), weapon (bow in the
	                         left hand), Ice Mage cape, held in the class's
	                         ultimate pose; exclusives add an aura in their colour
	                         and their title overhead
	  relic                  your current class, with the relic floating and
	                         orbiting at the shoulder
	  cosmetic (title)       your current class with the title overhead
	  material               a floating crystal with the item's icon

	RewardPreview.Build(reward) → (model, cleanup)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local ClassArmor = require(Shared:WaitForChild("ClassArmor"))
local IceCape = require(Shared:WaitForChild("IceCape"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))

local player = Players.LocalPlayer

local RewardPreview = {}

local WEAPONS = { heavy_knight = "Greatsword", ranger = "Bow" }
local LEFT_HANDED = { ranger = true }

local function findTemplate(name: string): Instance?
	local direct = ReplicatedStorage:FindFirstChild(name)
	if direct then return direct end
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d.Name == name and (d:IsA("Tool") or d:IsA("Model")) then return d end
	end
	return nil
end

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

-- A clean copy of the player's character: no scripts, tools, preview gear,
-- VFX or class armor — ready to be dressed for a class.
local function cleanCharacterCopy(): Model?
	local char = player.Character
	if not char then return nil end
	local was = char.Archivable
	char.Archivable = true
	local clone = char:Clone()
	char.Archivable = was
	if not clone then return nil end
	clone.Name = "RewardPreview"
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("Tool") or d:IsA("Sound") or d:IsA("ForceField")
			or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light") or d:IsA("Highlight")
			or (d:IsA("BillboardGui") and d.Name ~= "Title")
			or (d:IsA("Model") and d.Name == "IceCape")
			or d:GetAttribute("PreviewArmor") or d:GetAttribute("PreviewWeapon") then
			d:Destroy()
		end
	end
	-- Strip any class armor already worn (welded with ArmorWeld).
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("WeldConstraint") and d.Name == "ArmorWeld" and d.Parent then
			local piece = d.Parent
			while piece.Parent and piece.Parent ~= clone do piece = piece.Parent end
			if piece.Parent == clone and not piece:IsA("Humanoid") and piece.Name ~= "HumanoidRootPart" then
				piece:Destroy()
			end
		end
	end
	local hum = clone:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
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

local function giveWeapon(model: Model, classId: string)
	local name = WEAPONS[classId]
	local template = name and findTemplate(name)
	if not template then return end
	local tool = template:Clone()
	if not tool:IsA("Tool") then
		local inner = tool:FindFirstChildWhichIsA("Tool")
		if inner then tool = inner end
	end
	local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
	local arm = model:FindFirstChild(if LEFT_HANDED[classId] then "Left Arm" else "Right Arm")
		or model:FindFirstChild(if LEFT_HANDED[classId] then "LeftHand" else "RightHand")
	if not (handle and handle:IsA("BasePart") and arm and arm:IsA("BasePart")) then return end
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.Massless = false, false, true
		end
	end
	-- Loose tool parts ride on the handle.
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle then
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = handle, d
			w.Parent = d
		end
	end
	tool.Parent = model
	-- Same geometry as Roblox's RightGrip: hand attachment × the tool's Grip.
	local grip = Instance.new("Weld")
	grip.Part0 = arm
	grip.Part1 = handle
	grip.C0 = CFrame.new(0, -arm.Size.Y * 0.5, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	grip.C1 = if tool:IsA("Tool") then tool.Grip else CFrame.identity
	grip.Parent = arm
end

local function dressAs(model: Model, classId: string)
	ClassArmor.Equip(model, classId, "RewardPreview")
	if classId == "ice_mage" then IceCape.Attach(model, "RewardPreview") end
	giveWeapon(model, classId)
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
	g.Text = reward.glyph or "✨"
	g.Parent = bb
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, 2, 10
	light.Parent = core
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	pe.LightEmission, pe.LightInfluence = 1, 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.6, 1.2)
	pe.Speed = NumberRange.new(0.5, 1.5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 12
	pe.Parent = core
	return core
end

function RewardPreview.Build(reward: any): (Model, () -> ())
	local conns: { RBXScriptConnection } = {}
	local function cleanupFn(model: Model)
		return function()
			for _, c in ipairs(conns) do c:Disconnect() end
			CastPoses.stop(model)
			model:Destroy()
		end
	end

	-- Materials: just the crystal.
	if reward.type == "material" then
		local model = Instance.new("Model")
		model.Name = "RewardPreview"
		local core = crystal(model, reward, 1.6)
		model.PrimaryPart = core
		local t0 = os.clock()
		table.insert(conns, RunService.RenderStepped:Connect(function()
			if not core.Parent then return end
			core.CFrame = CFrame.new(core.Position) * CFrame.Angles(0, (os.clock() - t0) * 1.2, 0)
		end))
		return model, cleanupFn(model)
	end

	local classId = reward.classId
		or (typeof(player:GetAttribute("SelectedClass")) == "string" and player:GetAttribute("SelectedClass"))
		or "heavy_knight"
	local model = cleanCharacterCopy() or Instance.new("Model")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		model.PrimaryPart = root
		dressAs(model, classId)
	end
	-- Pose once it's in the world (motors need a parent to animate).
	model.AncestryChanged:Connect(function(_, parent)
		if parent and root then
			CastPoses.holdUltPreview(model, classId)
		end
	end)

	local accent = reward.accent or GachaConfig.Rarities[reward.rarity].color
	if root then
		if reward.type == "exclusive" then
			-- Aura in the character's colours + title overhead.
			local a = Instance.new("Attachment")
			a.Parent = root
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
			pe.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
			pe.LightEmission, pe.LightInfluence = 1, 0
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
			pe.Lifetime = NumberRange.new(0.8, 1.4)
			pe.Speed = NumberRange.new(1, 3)
			pe.SpreadAngle = Vector2.new(180, 180)
			pe.Acceleration = Vector3.new(0, 3, 0)
			pe.Rate = 40
			pe.Parent = a
			local l = Instance.new("PointLight")
			l.Color, l.Brightness, l.Range = accent, 2.5, 14
			l.Parent = root
			billboard(root, `✦ {reward.title or reward.name} ✦`, accent, 4.2)
		elseif reward.type == "cosmetic" then
			billboard(root, reward.title or reward.name, accent, 4.2)
		elseif reward.type == "relic" then
			-- The relic orbits at the shoulder.
			local core = crystal(model, reward, 0.6)
			local t0 = os.clock()
			table.insert(conns, RunService.RenderStepped:Connect(function()
				if not root.Parent then return end
				local t = os.clock() - t0
				local offset = CFrame.Angles(0, t * 1.4, 0) * Vector3.new(2.2, 0, 0)
				core.CFrame = CFrame.new(root.Position + offset + Vector3.new(0, 1.6 + math.sin(t * 2) * 0.2, 0)) * CFrame.Angles(0, t * 2, 0)
			end))
		end
	end
	return model, cleanupFn(model)
end

return RewardPreview
