--[[
	RewardPreview.luau
	Builds a showcase model for a gacha reward: a plain gray dummy rig (no
	armor, clothing or accessories) held in the class's ultimate pose, the
	same pose the class-select screen shows.

	  character / variant    the reward's class pose (a universal variant uses
	                         your class); variants add an aura in their colour
	                         and their title overhead
	  relic                  the relic floating and orbiting at the shoulder
	  cosmetic (title)       the title overhead
	  material               a floating crystal with the item's icon
	  wings                  worn on the dummy's back, flapping
	  mount                  the dummy riding it, the mount walking in place

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
local WingsMounts = require(script.Parent:WaitForChild("WingsMounts"))
local RideData = require(Shared:WaitForChild("RideData"))
local ClothCape = require(script.Parent:WaitForChild("ClothCape"))

local player = Players.LocalPlayer

local RewardPreview = {}

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

-- A copy of the player's character stripped down to a plain gray dummy rig.
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
		if d:IsA("BaseScript") or d:IsA("Tool") or d:IsA("Constraint") or d:IsA("BodyMover") or d:IsA("Sound") or d:IsA("ForceField")
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
	-- Plain gray dummy: no clothing, accessories, face, skin textures or colours.
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Accessory") or d:IsA("Clothing") or d:IsA("ShirtGraphic") or d:IsA("BodyColors")
			or d:IsA("SurfaceAppearance") or d:IsA("Decal") or d:IsA("Texture") then
			d:Destroy()
		elseif d:IsA("SpecialMesh") then
			d.TextureId = ""
		end
	end
	for _, d in ipairs(clone:GetChildren()) do
		-- Anything left that isn't the body rig itself (armor models, capes...).
		if d:IsA("Model") or d:IsA("Folder") then d:Destroy() end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("MeshPart") then d.TextureID = "" end
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Color = Color3.fromRGB(163, 162, 165)
			d.Material = Enum.Material.SmoothPlastic
			d.Transparency = 0
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
		-- Armor rewards are shown worn by the dummy.
		if reward.type == "armor" then
			ClassArmor.Equip(model, classId, "RewardPreview")
			if classId == "ice_mage" then IceCape.Attach(model, "RewardPreview") end
			if classId == "heavy_knight" then ClothCape.Attach(model, "RewardPreview", ClothCape.FIRE_KNIGHT) end
		end
	end
	-- CastPoses multiplies its pose onto Motor6D.Transform every frame, relying
	-- on the Animator to reset the joints first. The dummy has no animation
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

	local accent = reward.accent or GachaConfig.Rarities[reward.rarity].color
	if root then
		if reward.type == "variant" then
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
			billboard(root, reward.title or reward.name, accent, 4.2)
		elseif reward.type == "cosmetic" then
			billboard(root, reward.title or reward.name, accent, 4.2)
		elseif reward.type == "wings" or reward.type == "mount" then
			local rig = WingsMounts.Build(reward.id)
			if rig then
				rig.model.Parent = model
				local isWings = reward.type == "wings"
				local ride = RideData.RideHeight(reward.look)
				local hum = model:FindFirstChildOfClass("Humanoid")
				local liftedAt: Vector3? = nil
				table.insert(conns, RunService.RenderStepped:Connect(function()
					if not root.Parent or not model:IsDescendantOf(workspace) then return end
					local t = os.clock()
					if isWings then
						local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")
						if torso and torso:IsA("BasePart") then
							WingsMounts.Pose(rig, torso.CFrame * CFrame.new(0, 0.35, torso.Size.Z / 2 + 0.08), t, 0.4)
						end
					else
						-- (wherever it's put, it's lifted onto the mount's back)
						local pivot = model:GetPivot()
						if not liftedAt or (pivot.Position - liftedAt).Magnitude > 0.01 then
							pivot += Vector3.new(0, ride, 0)
							model:PivotTo(pivot)
							liftedAt = pivot.Position
						end
						local legs = if hum and hum.RigType == Enum.HumanoidRigType.R6 then 2 else 0
						local ground = root.Position.Y - root.Size.Y / 2 - legs - (if hum then hum.HipHeight else 2) - ride
						local look = root.CFrame.LookVector
						WingsMounts.Pose(rig, CFrame.new(root.Position.X, ground, root.Position.Z)
							* CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z)), t, 0.6)
					end
				end))
			end
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
