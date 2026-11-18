--!strict
--[[
	SummonerLook.luau
	The Summoner's weapon, the "Bondgauntlet", built in code: a rune gauntlet
	of dark iron trimmed in old gold, worn over the right fist and forearm.
	The Bond Crystal is set in the back of the hand, the three beasts' stones
	in a row up the vambrace: ember (Rockborn), sky (Skyfeather), moon
	(Lunari), with glowing runes cut between them.

	  BuildGauntlet()   the Tool; its Handle sits at the bottom of the right
	                    arm, lined up with it (Handle +Y runs up the arm to the
	                    shoulder, -Z is the arm's front). Tagged Worn = true:
	                    it stays on the arm (never slung on the back).
--]]

local SummonerLook = {}

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

local IRON = Color3.fromRGB(40, 38, 48)
local IRON_LIGHT = Color3.fromRGB(66, 62, 78)
local RUNE = Color3.fromRGB(60, 200, 255)
local CRYSTAL_GLOW = Color3.fromRGB(90, 210, 255)

function SummonerLook.BuildGauntlet(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Bondgauntlet"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- (Roblox's RightGrip is arm * (0, -1, 0) * Rx(-90) * Grip^-1: this Grip
	-- puts the Handle at the bottom of the arm, turned with it)
	tool.Grip = CFrame.Angles(math.rad(-90), 0, 0)
	tool:SetAttribute("Worn", true)

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.3, 0.3, 0.3)
	handle.Transparency = 1
	handle.CanCollide, handle.CanTouch, handle.CanQuery, handle.Massless = false, false, false, true
	handle.CFrame = CFrame.new(0, 50, 0)
	handle.Parent = tool
	local M = Enum.Material

	-- the fist: an iron shell round the hand, gold knuckle plates in front
	piece(tool, handle, "Fist", Vector3.new(1.1, 0.55, 1.1), CFrame.new(0, 0.22, 0), IRON, M.Metal)
	piece(tool, handle, "FistTop", Vector3.new(1.16, 0.1, 1.16), CFrame.new(0, 0.52, 0), GOLD_DARK, M.Metal)
	for k = 0, 3 do
		local x = -0.36 + k * 0.24
		piece(tool, handle, "Knuckle", Vector3.new(0.2, 0.2, 0.14), CFrame.new(x, 0.12, -0.6), GOLD, M.Metal)
	end
	piece(tool, handle, "KnuckleBar", Vector3.new(1.0, 0.08, 0.1), CFrame.new(0, 0.26, -0.6), GOLD_DARK, M.Metal)

	-- the vambrace: a plate round the forearm, gold bands, a flared cuff
	piece(tool, handle, "Vambrace", Vector3.new(1.14, 0.66, 1.14), CFrame.new(0, 0.86, 0), IRON_LIGHT, M.Metal)
	piece(tool, handle, "Ridge", Vector3.new(0.14, 0.7, 0.12), CFrame.new(0, 0.86, -0.6), IRON, M.Metal)
	for _, y in ipairs({ 0.56, 1.16 }) do
		piece(tool, handle, "Band", Vector3.new(1.2, 0.08, 1.2), CFrame.new(0, y, 0), GOLD, M.Metal)
	end
	piece(tool, handle, "Cuff", Vector3.new(1.28, 0.12, 1.28), CFrame.new(0, 1.25, 0), GOLD_DARK, M.Metal)
	for _, side in ipairs({ 1, -1 }) do
		-- (a swept fin off each side of the cuff)
		piece(tool, handle, "Fin", Vector3.new(0.08, 0.42, 0.34), CFrame.new(side * 0.64, 1.14, 0.12) * CFrame.Angles(0, 0, math.rad(side * -16)), GOLD, M.Metal)
	end

	-- the Bond Crystal, set in the back of the hand (the arm's outer side)
	piece(tool, handle, "CrystalSeat", Vector3.new(0.1, 0.42, 0.42), CFrame.new(0.58, 0.26, 0) * CFrame.Angles(math.rad(45), 0, 0), GOLD, M.Metal)
	local crystal = piece(tool, handle, "BondCrystal", Vector3.new(0.12, 0.28, 0.28), CFrame.new(0.63, 0.26, 0) * CFrame.Angles(math.rad(45), 0, 0), CRYSTAL_GLOW, M.Neon)

	-- the three beasts' stones up the front of the vambrace, either side of the ridge
	for k, c in ipairs({ EMBER, SKY, MOON }) do
		local y = 0.68 + (k - 1) * 0.18
		for _, x in ipairs({ 0.3, -0.3 }) do
			piece(tool, handle, "BeastStone", Vector3.new(0.13, 0.13, 0.08), CFrame.new(x, y, -0.6) * CFrame.Angles(0, 0, math.rad(45)), c, M.Neon)
		end
	end
	-- runes: a glowing crossed sigil cut in the outer and inner faces
	for _, side in ipairs({ 1, -1 }) do
		for _, a in ipairs({ 35, -35 }) do
			piece(tool, handle, "Rune", Vector3.new(0.03, 0.46, 0.06), CFrame.new(side * 0.575, 0.86, 0) * CFrame.Angles(math.rad(a), 0, 0), RUNE, M.Neon)
		end
	end

	-- a soft glow of motes off the crystal
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(CRYSTAL)
	e.Size = NumberSequence.new(0.16, 0)
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Rate = 5
	e.Speed = NumberRange.new(0.3, 0.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Parent = crystal
	return tool
end

return SummonerLook
