--!strict
--[[
	SwordModel
	Builds the Swordsman's longsword as a Tool from parts (no uploaded asset).
	Shared by the server (the real weapon) and the class-select preview.

	Handle space: the blade runs along -Z from the hand, and the Tool's Grip
	turns it to stick out of the fist (forward with the arm hanging, up with
	the arm raised). Named pieces the client uses:
	  BladeBase / BladeTip — Attachments on the blade for the swing trail
	  SwordTrail           — the white/gold swing Trail (off until a swing)
	The game's Sword Tool in ReplicatedStorage (named "Sword" or "Longsword")
	is used instead whenever it exists; this built one is only a fallback.

	To flip a sword point-down (planted), set tool.Grip =
	SwordModel.FlippedGrip(tool.Grip): it turns the handle 180° across the
	blade whatever the tool's own Grip is.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local SwordModel = {}

local STEEL = Color3.fromRGB(205, 210, 220)
local EDGE = Color3.fromRGB(240, 244, 250)
local GOLD = Color3.fromRGB(214, 170, 82)
local LEATHER = Color3.fromRGB(56, 36, 28)

-- Slides the whole sword along the blade so the wrapped grip (not the guard)
-- sits in the fist. More negative = sword further toward its tip.
local HAND_OFFSET = -0.5
-- Sideways nudge into the palm (the hand's X axis). Negative = toward the
-- character's left (screen-right when they face the camera).
local HAND_SIDE = -0.35

local function piece(tool: Tool, handle: BasePart, name: string, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local offset = props.Offset :: CFrame
	props.Offset = nil
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.CFrame = handle.CFrame * CFrame.new(HAND_SIDE, 0, HAND_OFFSET) * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = handle
	w.Part1 = p
	w.Parent = p
	p.Parent = tool
	return p
end

-- The game's own sword asset: a Tool named "Sword" in ReplicatedStorage
-- (there's also an unrelated Folder of that name, so look by class). Its
-- Grip is authored in Studio; the blade runs along the Handle's +Y. We add the
-- swing trail along the blade and name it "Longsword" so the rest of the
-- Swordsman code finds it. Attribute BladeAxis tells code which way the blade
-- points in Handle space ("+Y" here, "-Z" for the built fallback).
local function fromAsset(): Tool?
	local template: Tool? = nil
	for _, c in ipairs(ReplicatedStorage:GetChildren()) do
		if c:IsA("Tool") and (c.Name == "Sword" or c.Name == "Longsword") then
			template = c
			break
		end
	end
	if not template then return nil end
	local tool = template:Clone()
	tool.Name = "Longsword"
	tool.CanBeDropped = false
	tool:SetAttribute("BladeAxis", "+Y")
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	local blade = handle and handle:FindFirstChildWhichIsA("BasePart")
	if handle and blade and not tool:FindFirstChild("SwordTrail", true) then
		-- Trail from just past the guard to the tip, measured in Handle space
		-- then placed on the blade mesh.
		local base = Instance.new("Attachment")
		base.Name = "BladeBase"
		base.WorldPosition = (handle.CFrame * CFrame.new(0, 1.1, 0)).Position
		base.Parent = blade
		local tip = Instance.new("Attachment")
		tip.Name = "BladeTip"
		tip.WorldPosition = (handle.CFrame * CFrame.new(0, 5, 0)).Position
		tip.Parent = blade
		local trail = Instance.new("Trail")
		trail.Name = "SwordTrail"
		trail.Attachment0 = base
		trail.Attachment1 = tip
		trail.FaceCamera = true
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.Lifetime = 0.18
		trail.MinLength = 0.02
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 236, 170)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 90)),
		})
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(1, 0.3),
		})
		trail.Enabled = false
		trail.Parent = blade
	end
	return tool
end

function SwordModel.Build(): Tool
	local asset = fromAsset()
	if asset then return asset end

	local tool = Instance.new("Tool")
	tool.Name = "Longsword"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- Held in the fist, blade pointing forward (not along the arm): the grip
	-- turns the handle's -Z (blade) from "down the arm" to "out of the hand".
	-- If the blade points backward in-game, flip this to +90.
	tool.Grip = CFrame.Angles(math.rad(-90), 0, 0)
	tool:SetAttribute("BladeAxis", "-Z")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CFrame = CFrame.new(0, 50, 0)
	handle.Parent = tool

	-- Grip (wrapped leather) and gold pommel behind the hand.
	piece(tool, handle, "Grip", { Size = Vector3.new(0.22, 0.22, 1.1), Offset = CFrame.new(0, 0, 0.15),
		Color = LEATHER, Material = Enum.Material.Fabric })
	piece(tool, handle, "Pommel", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.38, Offset = CFrame.new(0, 0, 0.78),
		Color = GOLD, Material = Enum.Material.Metal })
	-- Crossguard, slightly swept.
	piece(tool, handle, "Guard", { Size = Vector3.new(1.5, 0.16, 0.2), Offset = CFrame.new(0, 0, -0.44),
		Color = GOLD, Material = Enum.Material.Metal })
	piece(tool, handle, "GuardCenter", { Size = Vector3.new(0.34, 0.3, 0.3), Offset = CFrame.new(0, 0, -0.44),
		Color = GOLD, Material = Enum.Material.Metal })
	-- Blade: a flat steel body with a brighter edge and a tapered tip.
	local blade = piece(tool, handle, "Blade", { Size = Vector3.new(0.3, 0.08, 3.6), Offset = CFrame.new(0, 0, -2.36),
		Color = STEEL, Material = Enum.Material.Metal, Reflectance = 0.15 })
	piece(tool, handle, "Fuller", { Size = Vector3.new(0.08, 0.1, 2.8), Offset = CFrame.new(0, 0, -2.1),
		Color = Color3.fromRGB(150, 158, 172), Material = Enum.Material.Metal })
	piece(tool, handle, "Edge", { Size = Vector3.new(0.36, 0.04, 3.5), Offset = CFrame.new(0, 0, -2.36),
		Color = EDGE, Material = Enum.Material.Metal, Reflectance = 0.3 })
	piece(tool, handle, "Tip", { Size = Vector3.new(0.21, 0.08, 0.21), Offset = CFrame.new(0, 0, -4.2) * CFrame.Angles(0, math.rad(45), 0),
		Color = STEEL, Material = Enum.Material.Metal })

	-- Swing trail along the blade.
	local base = Instance.new("Attachment")
	base.Name = "BladeBase"
	base.Position = Vector3.new(0, 0, 1.4)
	base.Parent = blade
	local tip = Instance.new("Attachment")
	tip.Name = "BladeTip"
	tip.Position = Vector3.new(0, 0, -1.95)
	tip.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "SwordTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = 0.18
	trail.MinLength = 0.02
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 236, 170)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 200, 90)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	trail.Enabled = false
	trail.Parent = blade

	return tool
end

-- The Grip that holds `grip`'s sword upside-down in the same hand (blade
-- reversed): turns the handle 180° about its X axis, across the blade.
function SwordModel.FlippedGrip(grip: CFrame): CFrame
	return CFrame.Angles(math.pi, 0, 0) * grip
end

return SwordModel
