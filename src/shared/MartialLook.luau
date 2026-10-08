--!strict
--[[
	MartialLook.luau
	The Martial Artist's look, built in code (after the class sheet): a black
	gi crossed over a white inner robe and edged in gold, a crimson sash
	knotted at the hip with its tails hanging, a crimson headband whose long
	tails fly behind him, wrapped forearms and fists, wide black trousers
	bound at the shin, dark slippers.

	The two sets of tails (headband and sash) hang on Motor6Ds the client
	sways as he moves (MartialController).

	  Dress(char)     put it all on (safe to call again)
	  Undress(char)   take it off
--]]

local MartialLook = {}

local ATTR = "MartialLook" -- on everything added (cleanup)

local GI = Color3.fromRGB(20, 18, 22)
local GI_LIGHT = Color3.fromRGB(34, 31, 38)
local INNER = Color3.fromRGB(226, 220, 206)
local GOLD = Color3.fromRGB(222, 170, 72)
local CRIMSON = Color3.fromRGB(176, 24, 30)
local CRIMSON_DARK = Color3.fromRGB(120, 14, 20)
local WRAP = Color3.fromRGB(214, 204, 186)
local SHOE = Color3.fromRGB(26, 22, 20)
MartialLook.QI = Color3.fromRGB(255, 176, 60)

local function R(d: number): number return math.rad(d) end

local function piece(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3,
	material: Enum.Material?, shape: string?): BasePart
	local p: BasePart
	if shape == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
	end
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = base.CFrame * offset
	p:SetAttribute(ATTR, true)
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

-- A hanging tail on its own motor (the client sways it): `name` .. "Motor".
local function tail(model: Model, base: BasePart, name: string, at: CFrame, length: number, width: number, color: Color3)
	local hub = Instance.new("Part")
	hub.Name = name
	hub.Size = Vector3.new(width, length, 0.08)
	hub.Color = color
	hub.Material = Enum.Material.Fabric
	hub.CanCollide, hub.CanTouch, hub.CanQuery, hub.Massless, hub.CastShadow = false, false, false, true, false
	hub.CFrame = base.CFrame * at * CFrame.new(0, -length / 2, 0)
	hub:SetAttribute(ATTR, true)
	hub.Parent = model
	local m = Instance.new("Motor6D")
	m.Name = name .. "Motor"
	m.Part0 = base
	m.Part1 = hub
	m.C0 = at
	m.C1 = CFrame.new(0, length / 2, 0)
	m.Parent = hub
	-- (a darker band at its end)
	piece(model, hub, name .. "Tip", Vector3.new(width + 0.01, 0.16, 0.09), CFrame.new(0, -length / 2 + 0.08, 0), CRIMSON_DARK)
end

function MartialLook.Undress(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:GetAttribute(ATTR) and d.Parent then
			d:Destroy()
		elseif d:IsA("Decal") and d:GetAttribute("MartialFace") ~= nil then
			d.Transparency = d:GetAttribute("MartialFace")
			d:SetAttribute("MartialFace", nil)
		end
	end
end

function MartialLook.Dress(char: Model)
	MartialLook.Undress(char)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not (head and torso) then return end
	local model = Instance.new("Model")
	model.Name = "MartialGi"
	model:SetAttribute(ATTR, true)

	-- The band: a crimson cloth tied over the eyes (the sheet's portrait),
	-- knotted at the back, its long tails flying.
	piece(model, head, "Headband", Vector3.new(1.3, 0.34, 1.3), CFrame.new(0, 0.12, 0), CRIMSON)
	piece(model, head, "HeadbandEdge", Vector3.new(1.32, 0.05, 1.32), CFrame.new(0, -0.03, 0), CRIMSON_DARK)
	piece(model, head, "HeadbandKnot", Vector3.new(0.32, 0.3, 0.18), CFrame.new(0, 0.12, 0.69), CRIMSON_DARK)
	tail(model, head, "BandTailL", CFrame.new(-0.1, 0.12, 0.74) * CFrame.Angles(R(-70), 0, R(8)), 1.8, 0.2, CRIMSON)
	tail(model, head, "BandTailR", CFrame.new(0.1, 0.08, 0.74) * CFrame.Angles(R(-62), 0, R(-10)), 1.5, 0.2, CRIMSON)
	-- the eyes it hides are hidden (the face decal goes under the cloth)
	local face = head:FindFirstChildOfClass("Decal")
	if face and face:GetAttribute("MartialFace") == nil then
		face:SetAttribute("MartialFace", face.Transparency)
		face.Transparency = 1
	end
	-- A crimson scarf knotted round the neck, its ends at the chest.
	piece(model, torso, "Scarf", Vector3.new(1.5, 0.34, 1.24), CFrame.new(0, 1.1, 0.02), CRIMSON)
	piece(model, torso, "ScarfFold", Vector3.new(1.0, 0.16, 1.26), CFrame.new(0, 0.96, 0.02), CRIMSON_DARK)
	piece(model, torso, "ScarfEnd", Vector3.new(0.34, 0.6, 0.08), CFrame.new(0.3, 0.72, -0.62) * CFrame.Angles(0, 0, R(-12)), CRIMSON)

	-- The gi: black over the body, crossed over a white inner robe, gold edges.
	piece(model, torso, "Gi", Vector3.new(2.1, 2.04, 1.1), CFrame.new(0, 0, 0), GI)
	piece(model, torso, "GiInner", Vector3.new(0.5, 0.9, 0.04), CFrame.new(0, 0.5, -0.565), INNER)
	for _, sx in ipairs({ -1, 1 }) do
		-- the lapels crossing down to the sash, gold-edged
		piece(model, torso, "Lapel", Vector3.new(0.34, 1.5, 0.05), CFrame.new(sx * 0.3, 0.3, -0.58) * CFrame.Angles(0, 0, R(sx * -24)), GI_LIGHT)
		piece(model, torso, "LapelTrim", Vector3.new(0.07, 1.5, 0.06), CFrame.new(sx * 0.15, 0.3, -0.6) * CFrame.Angles(0, 0, R(sx * -24)),
			GOLD, Enum.Material.Metal)
		-- shoulders, a little broad
		piece(model, torso, "GiShoulder", Vector3.new(1.12, 0.3, 1.16), CFrame.new(sx * 0.98, 0.92, 0), GI_LIGHT)
		piece(model, torso, "ShoulderTrim", Vector3.new(1.14, 0.06, 1.18), CFrame.new(sx * 0.98, 0.76, 0), GOLD, Enum.Material.Metal)
	end
	-- gold embroidery: a dragon coiling up the left breast (a curve of gold
	-- with a head at its top), and the sigil on the back
	for k, seg in ipairs({ { -0.62, -0.5, 30 }, { -0.74, -0.18, -20 }, { -0.66, 0.12, 25 }, { -0.76, 0.42, -30 } }) do
		piece(model, torso, "Embroidery", Vector3.new(0.07, 0.36, 0.05), CFrame.new(seg[1], seg[2], -0.575) * CFrame.Angles(0, 0, R(seg[3])),
			GOLD, Enum.Material.Metal)
		if k == 4 then
			piece(model, torso, "EmbroideryHead", Vector3.new(0.2, 0.14, 0.05), CFrame.new(-0.68, 0.62, -0.575) * CFrame.Angles(0, 0, R(-20)),
				GOLD, Enum.Material.Metal)
		end
	end
	piece(model, torso, "BackSigil", Vector3.new(0.7, 0.7, 0.04), CFrame.new(0, 0.25, 0.565) * CFrame.Angles(0, 0, R(45)), GOLD, Enum.Material.Metal)
	piece(model, torso, "BackSigilCore", Vector3.new(0.44, 0.44, 0.05), CFrame.new(0, 0.25, 0.57) * CFrame.Angles(0, 0, R(45)), GI)

	-- The sash: crimson round the waist, knotted at the left hip, tails hanging.
	piece(model, torso, "Sash", Vector3.new(2.16, 0.4, 1.16), CFrame.new(0, -0.78, 0), CRIMSON)
	piece(model, torso, "SashKnot", Vector3.new(0.36, 0.36, 0.2), CFrame.new(-0.62, -0.78, -0.62), CRIMSON_DARK)
	tail(model, torso, "SashTailA", CFrame.new(-0.56, -0.86, -0.66) * CFrame.Angles(R(-6), 0, R(6)), 1.3, 0.24, CRIMSON)
	tail(model, torso, "SashTailB", CFrame.new(-0.76, -0.86, -0.64) * CFrame.Angles(R(-4), 0, R(-4)), 1.05, 0.22, CRIMSON)

	-- Sleeves to the elbow, wrapped forearms and fists, gold-ringed.
	for _, side in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = char:FindFirstChild(side) :: BasePart?
		if not arm then continue end
		piece(model, arm, "Sleeve", Vector3.new(1.1, 0.95, 1.1), CFrame.new(0, 0.52, 0), GI)
		piece(model, arm, "SleeveTrim", Vector3.new(1.12, 0.08, 1.12), CFrame.new(0, 0.06, 0), GOLD, Enum.Material.Metal)
		piece(model, arm, "Wraps", Vector3.new(1.04, 0.8, 1.04), CFrame.new(0, -0.45, 0), WRAP)
		for k = 0, 2 do
			piece(model, arm, "WrapLine", Vector3.new(1.06, 0.05, 1.06), CFrame.new(0, -0.18 - k * 0.24, 0) * CFrame.Angles(0, 0, R(8)), CRIMSON_DARK)
		end
		piece(model, arm, "FistRing", Vector3.new(1.06, 0.07, 1.06), CFrame.new(0, -0.86, 0), GOLD, Enum.Material.Metal)
	end

	-- Wide black trousers bound at the shin, dark slippers.
	for _, side in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = char:FindFirstChild(side) :: BasePart?
		if not leg then continue end
		piece(model, leg, "Trousers", Vector3.new(1.12, 1.3, 1.12), CFrame.new(0, 0.35, 0), GI)
		piece(model, leg, "TrouserTrim", Vector3.new(1.14, 0.06, 1.14), CFrame.new(0, -0.28, 0), GOLD, Enum.Material.Metal)
		piece(model, leg, "ShinWrap", Vector3.new(1.05, 0.34, 1.05), CFrame.new(0, -0.45, 0), WRAP)
		piece(model, leg, "Slipper", Vector3.new(1.04, 0.36, 1.12), CFrame.new(0, -0.83, -0.04), SHOE, Enum.Material.Leather)
	end
	model.Parent = char
end

return MartialLook
