--!strict
--[[
	SummonerLook.luau
	The Summoner's staff, "Bondstaff", built in code: a staff of dark
	heartwood bound in old gold, its head a cradle of three curved prongs
	holding the Bond Crystal, and the three beasts' stones set round it:
	ember (Rockborn), sky (Skyfeather), moon (Lunari).

	  BuildStaff()   the Tool, held upright in the right fist (the staff runs
	                 along the Handle's Y, its head up when the arm hangs)
--]]

local SummonerLook = {}

local WOOD = Color3.fromRGB(46, 32, 30)
local WOOD_LIGHT = Color3.fromRGB(70, 48, 40)
local GOLD = Color3.fromRGB(214, 172, 86)
local GOLD_DARK = Color3.fromRGB(150, 112, 52)
local CRYSTAL = Color3.fromRGB(190, 240, 255)
local EMBER = Color3.fromRGB(255, 150, 40)
local SKY = Color3.fromRGB(80, 225, 255)
local MOON = Color3.fromRGB(255, 226, 90)

local function piece(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3,
	material: Enum.Material, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide, p.CanTouch, p.CanQuery, p.Massless, p.CastShadow = false, false, false, true, false
	if p:IsA("Part") then p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth end
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = base, p
	w.Parent = p
	p.Parent = parent
	return p
end

function SummonerLook.BuildStaff(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Bondstaff"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- (handle space: the fist closes round the shaft a little under its
	-- middle; the shaft runs along Y, the head at +Y)
	tool.Grip = CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	tool:SetAttribute("BladeAxis", "+Y")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 0.3)
	handle.Transparency = 1
	handle.CanCollide, handle.CanTouch, handle.CanQuery, handle.Massless = false, false, false, true
	handle.CFrame = CFrame.new(0, 50, 0)
	handle.Parent = tool
	local M = Enum.Material

	-- the shaft: two tones of wood, slightly bent, gold bands
	piece(tool, handle, "Shaft", Vector3.new(0.26, 3.6, 0.26), CFrame.new(0, 0.4, 0), WOOD, M.Wood)
	piece(tool, handle, "ShaftTop", Vector3.new(0.3, 1.4, 0.3), CFrame.new(0, 2.6, 0) * CFrame.Angles(0, 0, math.rad(4)), WOOD_LIGHT, M.Wood)
	for _, y in ipairs({ -1.3, 0.9, 1.9 }) do
		piece(tool, handle, "Band", Vector3.new(0.34, 0.14, 0.34), CFrame.new(0, y, 0), GOLD, M.Metal)
	end
	piece(tool, handle, "Foot", Vector3.new(0.34, 0.3, 0.34), CFrame.new(0, -1.5, 0), GOLD_DARK, M.Metal)
	piece(tool, handle, "Grip", Vector3.new(0.3, 0.7, 0.3), CFrame.new(0, -0.1, 0), Color3.fromRGB(70, 40, 36), M.Fabric)

	-- the head: a collar, three curved prongs, the crystal held between them
	local headY = 3.35
	piece(tool, handle, "Collar", Vector3.new(0.5, 0.22, 0.5), CFrame.new(0, headY, 0), GOLD, M.Metal)
	for k = 0, 2 do
		local a = math.rad(k * 120)
		local around = CFrame.new(0, headY, 0) * CFrame.Angles(0, a, 0)
		piece(tool, handle, "Prong", Vector3.new(0.14, 0.75, 0.16), around * CFrame.new(0, 0.42, -0.34) * CFrame.Angles(math.rad(-22), 0, 0), GOLD, M.Metal)
		piece(tool, handle, "ProngTip", Vector3.new(0.12, 0.45, 0.14), around * CFrame.new(0, 0.98, -0.36) * CFrame.Angles(math.rad(26), 0, 0), GOLD, M.Metal)
	end
	local crystal = piece(tool, handle, "BondCrystal", Vector3.new(0.42, 0.62, 0.42), CFrame.new(0, headY + 0.72, 0) * CFrame.Angles(0, math.rad(45), 0), CRYSTAL, M.Neon)
	piece(tool, handle, "BondCore", Vector3.new(0.6, 0.6, 0.6), CFrame.new(0, headY + 0.72, 0), CRYSTAL, M.ForceField, "Part").Shape = Enum.PartType.Ball

	-- the three stones, one under each prong
	for k, c in ipairs({ EMBER, SKY, MOON }) do
		local a = math.rad((k - 1) * 120 + 60)
		piece(tool, handle, "BeastStone", Vector3.new(0.16, 0.2, 0.16),
			CFrame.new(0, headY + 0.08, 0) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -0.3) * CFrame.Angles(0, math.rad(45), 0), c, M.Neon)
	end

	-- a soft glow of motes off the crystal
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(CRYSTAL)
	e.Size = NumberSequence.new(0.18, 0)
	e.Lifetime = NumberRange.new(0.6, 1)
	e.Rate = 5
	e.Speed = NumberRange.new(0.3, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = crystal
	return tool
end

return SummonerLook
