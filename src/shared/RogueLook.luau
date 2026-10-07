--!strict
--[[
	RogueLook.luau
	The Rogue's gear, built in code:
	  BuildDagger()   "Shadowfang": a black-and-crimson dagger held point
	                  forward, with a red swing trail (DaggerTrail).
	  Dress(char)     a deep hood over the head and a crimson scarf over the
	                  mouth, welded on (tagged RogueLook so it can be removed).
--]]

local RogueLook = {}

local BLACK = Color3.fromRGB(18, 14, 20)
local STEEL = Color3.fromRGB(70, 66, 78)
local CRIMSON = Color3.fromRGB(200, 25, 45)
local CLOTH = Color3.fromRGB(26, 20, 30)

local function piece(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props or {}) do (p :: any)[k] = v end
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

function RogueLook.BuildDagger(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Shadowfang"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- Held in the fist, the blade out of the hand (along the handle's -Z).
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

	piece(tool, handle, "Grip", Vector3.new(0.2, 0.2, 0.7), CFrame.new(0, 0, 0.2), BLACK, Enum.Material.Fabric)
	piece(tool, handle, "Pommel", Vector3.one * 0.26, CFrame.new(0, 0, 0.6), CRIMSON, Enum.Material.Neon, { Shape = Enum.PartType.Ball })
	piece(tool, handle, "Guard", Vector3.new(0.7, 0.12, 0.16), CFrame.new(0, 0, -0.18), STEEL, Enum.Material.Metal)
	local blade = piece(tool, handle, "Blade", Vector3.new(0.24, 0.06, 1.5), CFrame.new(0, 0, -1.0), BLACK, Enum.Material.Metal,
		{ Reflectance = 0.2 })
	piece(tool, handle, "Edge", Vector3.new(0.05, 0.07, 1.4), CFrame.new(0.13, 0, -1.0), CRIMSON, Enum.Material.Neon)
	piece(tool, handle, "Tip", Vector3.new(0.17, 0.06, 0.17), CFrame.new(0, 0, -1.78) * CFrame.Angles(0, math.rad(45), 0), BLACK, Enum.Material.Metal)

	local a0 = Instance.new("Attachment")
	a0.Name = "BladeBase"
	a0.Position = Vector3.new(0, 0, 0.6)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "BladeTip"
	a1.Position = Vector3.new(0, 0, -0.8)
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "DaggerTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = 0.15
	trail.Color = ColorSequence.new(Color3.fromRGB(255, 90, 100), CRIMSON)
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Enabled = false
	trail.Parent = blade
	return tool
end

-- The hood and scarf. Safe to call again (the old ones go first).
function RogueLook.Dress(character: Model)
	for _, d in ipairs(character:GetChildren()) do
		if d:GetAttribute("RogueLook") then d:Destroy() end
	end
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local folder = Instance.new("Model")
	folder.Name = "RogueHood"
	folder:SetAttribute("RogueLook", true)
	folder.Parent = character
	local s = head.Size.Y
	-- Hood: a shell over the top and back of the head, a peak at the front.
	piece(folder, head, "Hood", Vector3.new(1.32, 1.12, 1.25) * s, CFrame.new(0, 0.12 * s, 0.1 * s), CLOTH, Enum.Material.Fabric)
	piece(folder, head, "HoodPeak", Vector3.new(1.15, 0.22, 0.4) * s, CFrame.new(0, 0.5 * s, -0.45 * s) * CFrame.Angles(math.rad(-20), 0, 0),
		CLOTH, Enum.Material.Fabric)
	piece(folder, head, "HoodBack", Vector3.new(1.0, 1.0, 0.5) * s, CFrame.new(0, -0.35 * s, 0.6 * s), CLOTH, Enum.Material.Fabric)
	-- Scarf over the mouth and nose, its tail trailing down the back.
	piece(folder, head, "Scarf", Vector3.new(1.08, 0.42, 1.08) * s, CFrame.new(0, -0.3 * s, 0), CRIMSON, Enum.Material.Fabric)
	piece(folder, head, "ScarfTail", Vector3.new(0.35, 1.3, 0.12) * s, CFrame.new(0.3 * s, -0.95 * s, 0.62 * s) * CFrame.Angles(math.rad(12), 0, 0),
		CRIMSON, Enum.Material.Fabric)
	-- Eyes glinting red in the shadow of the hood.
	for _, side in ipairs({ -1, 1 }) do
		piece(folder, head, "Eye", Vector3.new(0.16, 0.07, 0.05) * s, CFrame.new(side * 0.2 * s, 0.07 * s, -0.6 * s),
			Color3.fromRGB(255, 50, 60), Enum.Material.Neon)
	end
end

return RogueLook
