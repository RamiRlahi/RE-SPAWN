--!strict
--[[
	MageLook.luau
	The Mage's look, built in code (after the class sheet's "Mage visuals"):
	a deep navy hooded robe trimmed in gold, the face lost in the hood's
	shadow but for two glowing violet eyes; a high collar, layered shoulder
	mantle, a belt with a gold buckle set with an arcane gem; navy sleeves
	with gold-banded cuffs, dark gloves, trousers and boots. The long cloak
	itself is cloth (ClothCape.MAGE, on the client).

	And the grimoire: an open spellbook floating at his left side, pages
	glowing with a violet rune, motes of arcane light drifting off it. It
	hangs on a Motor6D (GrimoireMotor) from the torso; the client bobs it and
	swings it up in front of him when he casts (MageController).

	  Dress(char)     put it all on (safe to call again)
	  Undress(char)   take it off, giving back the face and hair it hid
--]]

local CollectionService = game:GetService("CollectionService")

local MageLook = {}

local ATTR = "MageLook"       -- on everything added (cleanup)
local HIDDEN = "MageHidden"   -- the transparency of what was hidden under it
MageLook.GRIMOIRE_TAG = "MageGrimoire"

-- The palette (the sheet's swatches: violet to blue).
local NAVY = Color3.fromRGB(26, 30, 66)
local NAVY_DARK = Color3.fromRGB(15, 17, 40)
local NAVY_LIGHT = Color3.fromRGB(38, 46, 96)
local GOLD = Color3.fromRGB(212, 170, 84)
local GOLD_DARK = Color3.fromRGB(150, 112, 52)
local LEATHER = Color3.fromRGB(36, 28, 40)
local SHADOW = Color3.fromRGB(4, 4, 9)
local VIOLET = Color3.fromRGB(170, 90, 255)
local EYE = Color3.fromRGB(176, 84, 255)
local PAGE = Color3.fromRGB(232, 222, 196)
local COVER = Color3.fromRGB(44, 30, 86)
MageLook.VIOLET = VIOLET
MageLook.BLUE = Color3.fromRGB(96, 120, 255)

local function R(d: number): number return math.rad(d) end

local function piece(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3,
	material: Enum.Material?, shape: string?): BasePart
	local p: BasePart
	if shape == "wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "corner" then
		p = Instance.new("CornerWedgePart")
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

-- Hide `part` under the robes (its transparency kept to give back).
local function hide(part: Instance)
	if part:IsA("BasePart") or part:IsA("Decal") then
		if part:GetAttribute(HIDDEN) == nil then
			part:SetAttribute(HIDDEN, (part :: any).Transparency)
			;(part :: any).Transparency = 1
		end
	end
end

function MageLook.Undress(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:GetAttribute(ATTR) then
			if d.Parent then d:Destroy() end
		elseif d:GetAttribute(HIDDEN) ~= nil then
			(d :: any).Transparency = d:GetAttribute(HIDDEN)
			d:SetAttribute(HIDDEN, nil)
		end
	end
end

-- ── The hood ────────────────────────────────────────────────────────────────
local function hood(model: Model, head: BasePart)
	-- The shell: crown, sides and back, rising to a soft point behind.
	piece(model, head, "HoodCrown", Vector3.new(1.74, 0.32, 1.78), CFrame.new(0, 0.78, 0.06), NAVY)
	piece(model, head, "HoodPeak", Vector3.new(1.4, 0.55, 1.0), CFrame.new(0, 1.15, 0.28), NAVY, nil, "wedge")
	for _, sx in ipairs({ -1, 1 }) do
		piece(model, head, "HoodSide", Vector3.new(0.26, 1.48, 1.74), CFrame.new(sx * 0.84, 0.14, 0.06), NAVY)
		-- (the opening's gold edge)
		piece(model, head, "HoodTrim", Vector3.new(0.08, 1.4, 0.08), CFrame.new(sx * 0.72, 0.12, -0.84), GOLD, Enum.Material.Metal)
	end
	piece(model, head, "HoodBack", Vector3.new(1.74, 1.52, 0.3), CFrame.new(0, 0.14, 0.88), NAVY)
	piece(model, head, "HoodTrim", Vector3.new(1.5, 0.08, 0.08), CFrame.new(0, 0.86, -0.84), GOLD, Enum.Material.Metal)
	-- The cowl gathered round the neck and falling onto the shoulders.
	piece(model, head, "HoodCowl", Vector3.new(1.96, 0.62, 1.2), CFrame.new(0, -0.62, 0.32), NAVY_LIGHT)
	-- Inside: nothing but shadow, and two violet eyes in it.
	piece(model, head, "HoodShadow", Vector3.new(1.36, 1.3, 0.12), CFrame.new(0, 0.06, -0.6), SHADOW, Enum.Material.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		piece(model, head, "MageEye", Vector3.new(0.26, 0.07, 0.05), CFrame.new(sx * 0.23, 0.12, -0.68) * CFrame.Angles(0, 0, R(sx * -10)),
			EYE, Enum.Material.Neon)
	end
end

-- ── The robes ───────────────────────────────────────────────────────────────
local function robes(model: Model, char: Model, torso: BasePart)
	-- The robe over the body, open down the front over a dark inner panel,
	-- trimmed in gold.
	piece(model, torso, "Robe", Vector3.new(2.12, 2.04, 1.12), CFrame.new(0, 0, 0), NAVY)
	piece(model, torso, "RobeInner", Vector3.new(0.34, 2.0, 0.04), CFrame.new(0, 0, -0.575), NAVY_DARK)
	for _, sx in ipairs({ -1, 1 }) do
		piece(model, torso, "RobeTrim", Vector3.new(0.1, 2.02, 0.05), CFrame.new(sx * 0.2, 0, -0.58), GOLD, Enum.Material.Metal)
	end
	-- A high collar with a gold rim.
	piece(model, torso, "Collar", Vector3.new(1.46, 0.36, 1.26), CFrame.new(0, 1.08, 0.04), NAVY)
	piece(model, torso, "CollarRim", Vector3.new(1.48, 0.07, 1.28), CFrame.new(0, 1.25, 0.04), GOLD, Enum.Material.Metal)
	-- The shoulder mantle: two layers sloping off each shoulder, the lower
	-- edged in gold.
	for _, sx in ipairs({ -1, 1 }) do
		piece(model, torso, "Mantle", Vector3.new(1.2, 0.22, 1.38), CFrame.new(sx * 0.92, 0.98, 0.04) * CFrame.Angles(0, 0, R(sx * -18)), NAVY_LIGHT)
		piece(model, torso, "Mantle", Vector3.new(1.26, 0.2, 1.46), CFrame.new(sx * 1.06, 0.74, 0.04) * CFrame.Angles(0, 0, R(sx * -30)), NAVY)
		piece(model, torso, "MantleTrim", Vector3.new(0.08, 0.22, 1.48), CFrame.new(sx * 1.64, 0.42, 0.04) * CFrame.Angles(0, 0, R(sx * -30)),
			GOLD, Enum.Material.Metal)
	end
	-- The belt: dark leather, a gold buckle with a violet gem.
	piece(model, torso, "Belt", Vector3.new(2.18, 0.28, 1.18), CFrame.new(0, -0.8, 0), LEATHER, Enum.Material.Leather)
	piece(model, torso, "Buckle", Vector3.new(0.46, 0.38, 0.08), CFrame.new(0, -0.8, -0.62), GOLD, Enum.Material.Metal)
	piece(model, torso, "BuckleGem", Vector3.new(0.18, 0.18, 0.06), CFrame.new(0, -0.8, -0.67) * CFrame.Angles(0, 0, R(45)), VIOLET,
		Enum.Material.Neon)
	-- Sleeves, cuffs and gloves.
	for _, side in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = char:FindFirstChild(side) :: BasePart?
		if not arm then continue end
		piece(model, arm, "Sleeve", Vector3.new(1.08, 1.5, 1.08), CFrame.new(0, 0.26, 0), NAVY)
		piece(model, arm, "Cuff", Vector3.new(1.22, 0.42, 1.22), CFrame.new(0, -0.62, 0), NAVY_LIGHT)
		piece(model, arm, "CuffTrim", Vector3.new(1.24, 0.08, 1.24), CFrame.new(0, -0.8, 0), GOLD, Enum.Material.Metal)
		piece(model, arm, "Glove", Vector3.new(1.03, 0.36, 1.03), CFrame.new(0, -0.84, 0), LEATHER, Enum.Material.Leather)
	end
	-- Dark trousers and boots with a gold band.
	for _, side in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = char:FindFirstChild(side) :: BasePart?
		if not leg then continue end
		piece(model, leg, "Trousers", Vector3.new(1.03, 1.4, 1.03), CFrame.new(0, 0.3, 0), NAVY_DARK)
		piece(model, leg, "Boot", Vector3.new(1.08, 0.66, 1.14), CFrame.new(0, -0.68, -0.03), LEATHER, Enum.Material.Leather)
		piece(model, leg, "BootBand", Vector3.new(1.1, 0.08, 1.16), CFrame.new(0, -0.36, -0.03), GOLD_DARK, Enum.Material.Metal)
	end
end

-- ── The grimoire ────────────────────────────────────────────────────────────
-- Floating open off his left side, clear of the arm, its pages turned back
-- toward him (and the camera behind him).
MageLook.GRIMOIRE_REST = CFrame.new(-3.7, 0.3, -0.5) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(R(-35), R(20), R(8))

local function grimoire(model: Model, torso: BasePart)
	local core = Instance.new("Part")
	core.Name = "GrimoireCore"
	core.Size = Vector3.one * 0.2
	core.Transparency = 1
	core.CanCollide, core.CanTouch, core.CanQuery, core.Massless, core.CastShadow = false, false, false, true, false
	core.CFrame = torso.CFrame * MageLook.GRIMOIRE_REST
	core:SetAttribute(ATTR, true)
	core.Parent = model
	local m = Instance.new("Motor6D")
	m.Name = "GrimoireMotor"
	m.Part0 = torso
	m.Part1 = core
	m.C0 = MageLook.GRIMOIRE_REST
	m.Parent = core
	CollectionService:AddTag(core, MageLook.GRIMOIRE_TAG)
	-- Open, the two halves lifted a little from the spine.
	for _, sx in ipairs({ -1, 1 }) do
		local half = CFrame.new(sx * 0.46, 0, 0) * CFrame.Angles(0, 0, R(sx * 10))
		piece(model, core, "Cover", Vector3.new(0.94, 0.07, 1.28), half, COVER, Enum.Material.Leather)
		piece(model, core, "Pages", Vector3.new(0.84, 0.12, 1.16), half * CFrame.new(-sx * 0.02, 0.09, 0), PAGE, Enum.Material.SmoothPlastic)
		for _, sz in ipairs({ -1, 1 }) do
			piece(model, core, "Corner", Vector3.new(0.2, 0.09, 0.2), half * CFrame.new(sx * 0.38, 0.0, sz * 0.55), GOLD, Enum.Material.Metal)
		end
	end
	piece(model, core, "Spine", Vector3.new(0.16, 0.12, 1.3), CFrame.new(0, -0.03, 0), GOLD_DARK, Enum.Material.Metal)
	-- The rune glowing on the right-hand page, and a fainter one on the left.
	local rune = piece(model, core, "PageRune", Vector3.new(0.34, 0.02, 0.34),
		CFrame.new(0.46, 0.17, 0) * CFrame.Angles(0, 0, R(-10)) * CFrame.Angles(0, R(45), 0), VIOLET, Enum.Material.Neon)
	piece(model, core, "PageRune", Vector3.new(0.14, 0.02, 0.5), CFrame.new(-0.46, 0.17, 0) * CFrame.Angles(0, 0, R(10)), VIOLET,
		Enum.Material.Neon).Transparency = 0.4
	-- Motes of arcane light drifting up off the pages.
	local motes = Instance.new("ParticleEmitter")
	motes.Name = "GrimoireMotes"
	motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	motes.Color = ColorSequence.new(EYE, MageLook.BLUE)
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(0.8, 1.4)
	motes.Speed = NumberRange.new(0.6, 1.4)
	motes.SpreadAngle = Vector2.new(35, 35)
	motes.Acceleration = Vector3.new(0, 1.2, 0)
	motes.Rate = 7
	motes:SetAttribute(ATTR, true)
	motes.Parent = rune
	-- A loose leaf at the spine that the client turns over when he casts
	-- (LeafMotor; hidden at rest, lying on the right-hand page).
	local leaf = Instance.new("Part")
	leaf.Name = "GrimoireLeaf"
	leaf.Size = Vector3.new(0.84, 0.03, 1.12)
	leaf.Color = PAGE
	leaf.Material = Enum.Material.SmoothPlastic
	leaf.Transparency = 1
	leaf.CanCollide, leaf.CanTouch, leaf.CanQuery, leaf.Massless, leaf.CastShadow = false, false, false, true, false
	leaf.CFrame = core.CFrame * CFrame.new(0.44, 0.17, 0)
	leaf:SetAttribute(ATTR, true)
	leaf.Parent = model
	local lm = Instance.new("Motor6D")
	lm.Name = "LeafMotor"
	lm.Part0 = core
	lm.Part1 = leaf
	lm.C0 = CFrame.new(0, 0.17, 0)
	lm.C1 = CFrame.new(-0.44, 0, 0)
	lm.Parent = leaf
	piece(leaf, leaf, "LeafRune", Vector3.new(0.1, 0.02, 0.5), CFrame.new(0, 0.025, 0), VIOLET, Enum.Material.Neon).Transparency = 1
	-- Three glyphs of light circling the book (GlyphMotor; the client turns it).
	local hub = Instance.new("Part")
	hub.Name = "GlyphHub"
	hub.Size = Vector3.one * 0.1
	hub.Transparency = 1
	hub.CanCollide, hub.CanTouch, hub.CanQuery, hub.Massless, hub.CastShadow = false, false, false, true, false
	hub.CFrame = core.CFrame
	hub:SetAttribute(ATTR, true)
	hub.Parent = model
	local gm = Instance.new("Motor6D")
	gm.Name = "GlyphMotor"
	gm.Part0 = core
	gm.Part1 = hub
	gm.Parent = hub
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		piece(model, hub, "OrbitGlyph", Vector3.new(0.15, 0.15, 0.15),
			CFrame.new(math.cos(a) * 1.2, (k - 1) * 0.18, math.sin(a) * 1.2) * CFrame.Angles(R(45), 0, R(45)), EYE, Enum.Material.Neon)
	end
end

-- ── Public ──────────────────────────────────────────────────────────────────
function MageLook.Dress(char: Model)
	MageLook.Undress(char)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not (head and torso) then return end
	local model = Instance.new("Model")
	model.Name = "MageRobes"
	model:SetAttribute(ATTR, true)
	-- The face is lost in the hood; hair and hats go under it.
	local face = head:FindFirstChildOfClass("Decal")
	if face then hide(face) end
	for _, acc in ipairs(char:GetChildren()) do
		if acc:IsA("Accessory") then
			local handle = acc:FindFirstChild("Handle")
			local att = handle and handle:FindFirstChildOfClass("Attachment")
			local name = if att then att.Name else ""
			if handle and (string.find(name, "Hat") or string.find(name, "Hair") or string.find(name, "Face")) then
				hide(handle)
				for _, d in ipairs(handle:GetDescendants()) do hide(d) end
			end
		end
	end
	hood(model, head)
	robes(model, char, torso)
	grimoire(model, torso)
	model.Parent = char
end

return MageLook
