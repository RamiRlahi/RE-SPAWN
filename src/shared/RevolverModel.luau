--!strict
--[[
	RevolverModel
	Builds the Gunslinger's revolver ("The Last Word") as a Tool from parts, so
	it needs no uploaded asset. Shared by the server (the real weapon) and the
	class-select preview.

	Handle space: the barrel points along -Z, the frame sits above the hand
	(+Y). Roblox's RightGrip lines the handle's -Z up with the arm, so when the
	arm is raised to aim the barrel points forward.

	Named pieces the client uses:
	  Muzzle    — Attachment at the barrel tip for flashes and tracers
	  Runes / RuneRib — neon engravings (glow white-hot when Deadeye is ready)
	If a Tool named "Revolver" exists in ReplicatedStorage it is used instead.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RevolverModel = {}

local WOOD = Color3.fromRGB(72, 42, 26)
local IRON = Color3.fromRGB(34, 31, 38)
local BRASS = Color3.fromRGB(196, 146, 62)
local RUNE = Color3.fromRGB(255, 196, 88)

local function piece(tool: Tool, handle: BasePart, name: string, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
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
	p.CFrame = handle.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = handle
	w.Part1 = p
	w.Parent = p
	p.Parent = tool
	return p
end

-- A cylinder part whose round axis runs along the handle's Z (barrel axis).
local ALONG_Z = CFrame.Angles(0, math.rad(90), 0)

function RevolverModel.Build(): Tool
	local template = ReplicatedStorage:FindFirstChild("Revolver")
	if template and template:IsA("Tool") then
		return template:Clone()
	end

	local tool = Instance.new("Tool")
	tool.Name = "Revolver"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	tool.Grip = CFrame.identity

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

	-- Grip: dark wood, raked back, with a brass butt cap.
	piece(tool, handle, "Grip", { Size = Vector3.new(0.26, 0.78, 0.4), Color = WOOD, Material = Enum.Material.Wood,
		Offset = CFrame.new(0, -0.05, 0.14) * CFrame.Angles(math.rad(-20), 0, 0) })
	piece(tool, handle, "GripCap", { Size = Vector3.new(0.3, 0.1, 0.44), Color = BRASS, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, -0.43, 0.28) * CFrame.Angles(math.rad(-20), 0, 0) })

	-- Frame above the hand.
	piece(tool, handle, "Frame", { Size = Vector3.new(0.24, 0.36, 0.86), Color = IRON, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, 0.38, -0.2) })
	-- Trigger guard and trigger.
	piece(tool, handle, "TriggerGuard", { Size = Vector3.new(0.06, 0.06, 0.42), Color = BRASS, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, 0.08, -0.2) })
	piece(tool, handle, "Trigger", { Size = Vector3.new(0.05, 0.2, 0.05), Color = IRON, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, 0.2, -0.12) * CFrame.Angles(math.rad(15), 0, 0) })

	-- Brass cylinder with a rune band.
	piece(tool, handle, "Cylinder", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.56, 0.54, 0.54), Color = BRASS,
		Material = Enum.Material.Metal, Offset = CFrame.new(0, 0.37, -0.32) * ALONG_Z })
	piece(tool, handle, "Runes", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.57, 0.57), Color = RUNE,
		Material = Enum.Material.Neon, Offset = CFrame.new(0, 0.37, -0.32) * ALONG_Z })

	-- Long octagonal barrel: a square barrel plus a 45° twin reads as eight-sided.
	piece(tool, handle, "Barrel", { Size = Vector3.new(0.2, 0.2, 1.5), Color = IRON, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, 0.47, -1.16) })
	piece(tool, handle, "BarrelEdge", { Size = Vector3.new(0.2, 0.2, 1.5), Color = IRON, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, 0.47, -1.16) * CFrame.Angles(0, 0, math.rad(45)) })
	-- Golden rib of engraving along the top of the barrel.
	piece(tool, handle, "RuneRib", { Size = Vector3.new(0.05, 0.04, 1.36), Color = RUNE, Material = Enum.Material.Neon,
		Offset = CFrame.new(0, 0.6, -1.14) })
	-- Ejector rod under the barrel, front sight, brass muzzle ring.
	piece(tool, handle, "Ejector", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 0.09, 0.09), Color = IRON,
		Material = Enum.Material.Metal, Offset = CFrame.new(0, 0.32, -0.96) * ALONG_Z })
	piece(tool, handle, "Sight", { Size = Vector3.new(0.05, 0.1, 0.1), Color = BRASS, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, 0.62, -1.84) })
	local muzzleRing = piece(tool, handle, "MuzzleRing", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.3, 0.3),
		Color = BRASS, Material = Enum.Material.Metal, Offset = CFrame.new(0, 0.47, -1.9) * ALONG_Z })
	local muzzle = Instance.new("Attachment")
	muzzle.Name = "Muzzle"
	-- ALONG_Z turns the ring's local +X to face down the barrel (handle -Z), so
	-- the muzzle sits just past the ring's front face.
	muzzle.Position = Vector3.new(0.08, 0, 0)
	muzzle.Parent = muzzleRing

	-- Hammer, cocked back over the grip.
	piece(tool, handle, "Hammer", { Size = Vector3.new(0.08, 0.2, 0.12), Color = IRON, Material = Enum.Material.Metal,
		Offset = CFrame.new(0, 0.62, 0.22) * CFrame.Angles(math.rad(35), 0, 0) })

	return tool
end

return RevolverModel
