--[[
	ClassArmor.luau
	Fits a class's armor (ReplicatedStorage.Assets.Classes[<folder>]) onto an R6
	character. Shared so the server (real equipment) and the class-selection
	preview (client-only copies) fit pieces identically.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ClassArmor = {}

-- Maps armor piece name -> R6 body part name it should be welded to
local ARMOR_WELD_MAP: { [string]: string } = {
	chestplate              = "Torso",
	gauntlet_heavyknight    = "Left Arm",
	leftarm_heavyknight     = "Left Arm",
	rightarm_heavyknight    = "Right Arm",
	heavyknight_BELT        = "Torso",
	leftleg                 = "Left Leg",
	rightleg                = "Right Leg",
	Accessory               = "Torso",
	Cape                    = "Torso",
	cape                    = "Torso",
	RangerCloak             = "Torso",
}

local ROT270 = CFrame.Angles(0, math.rad(270), 0)
local ROT90 = CFrame.Angles(0, math.rad(90), 0)


local ARMOR_CFRAME_OFFSETS: { [string]: CFrame } = {
	chestplate              = ROT270 * CFrame.new(0, 0, 0),
	gauntlet_heavyknight    = ROT90 * CFrame.new(0, 0, 0),
	leftarm_heavyknight     = ROT270 * CFrame.new(0, -0.2, 0),
	rightarm_heavyknight    = ROT270 * CFrame.new(0, -0.2, 0),
	heavyknight_BELT        = ROT270 * CFrame.new(0, -1.9, 0),
	leftleg                 = ROT270 * CFrame.Angles(0, 0, math.rad(10)) * CFrame.new(-0.1, 0, 0),
	rightleg                = ROT270 * CFrame.Angles(0, 0, math.rad(10)) * CFrame.new(-0.1, 0, 0),
	Accessory               = CFrame.new(0, -0.5, 1), -- Pushed outward so cape drapes OVER the armor
	Cape                    = ROT270 * CFrame.new(0, 0, 1),
	cape                    = ROT270 * CFrame.new(0, 0, 1),
	RangerCloak             = ROT90 * CFrame.new(0, 0, 0),
}


local ARMOR_SCALE = 1

-- Cleric Robe (ReplicatedStorage.Assets.Classes["Cleric armor"]["Cleric Robe"]).
-- It hangs from the shoulders instead of being centred on the torso, and is
-- auto-turned to face forward (a robe is wider than it is deep). Tweak these
-- if the mesh sits off:
local CLERIC_ROBE = {
	scale = 1,          -- overall size multiplier
	rotation = nil :: CFrame?, -- force a rotation (e.g. ROT90) instead of auto-facing
	raise = 0.45,       -- studs the robe's top sits above the shoulder line
	forward = 0.15,     -- studs to push it forward (-) or back (+)
	flip = true,        -- turn 180° (the mesh's back was facing forward)
}

local ARMOR_PIECE_SCALES: { [string]: number } = {
	leftleg  = 1.08, -- Slightly enlarged to fit over boots cleanly
	rightleg = 1.08,
	["Cleric Robe"] = CLERIC_ROBE.scale,
}


local function scaleArmorPiece(piece: Instance, scale: number)
	if scale == 1 then return end
	if piece:IsA("Model") then
		local pivot = piece:GetPivot()
		for _, part in ipairs(piece:GetDescendants()) do
			if part:IsA("BasePart") then
				local relative = pivot:ToObjectSpace(part.CFrame)
				local scaledPos = relative.Position * scale
				local rot = relative - relative.Position
				part.Size *= scale
				part.CFrame = pivot * CFrame.new(scaledPos) * rot
			end
		end
	elseif piece:IsA("Accessory") then
		local handle = piece:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			handle.Size *= scale
		end
	elseif piece:IsA("BasePart") then
		piece.Size *= scale
	end
end




ClassArmor.Enabled = true

-- ── Gunslinger outfit (built from parts, no asset) ───────────────────────────
-- The outlaw: a cowboy hat with a feather, a rust bandana over the mouth, a
-- long dark leather duster (sleeves, lapels, tails to the knee), crossed
-- bandoliers of brass rounds, a gun belt with a buckle and a holster, and
-- spurred boots. (The tattered cape is a cloth one: ClothCape.GUNSLINGER.)
-- Pieces weld to R6 limbs like other armor.
local GS_COAT = Color3.fromRGB(46, 34, 33)
local GS_DARK = Color3.fromRGB(34, 25, 21)
local GS_BRASS = Color3.fromRGB(192, 142, 62)
local GS_LEATHER = Color3.fromRGB(58, 40, 30)
local GS_STRAP = Color3.fromRGB(28, 20, 17)
local GS_SCARF = Color3.fromRGB(96, 40, 28)
local VERTICAL = CFrame.Angles(0, 0, math.rad(90)) -- cylinder axis (X) → up

local function buildGunslingerOutfit(character: Model, tag: string?)
	local outfit = Instance.new("Model")
	outfit.Name = "GunslingerOutfit"
	if tag then outfit:SetAttribute(tag, true) end

	local function add(limbName: string, name: string, size: Vector3, offset: CFrame, color: Color3,
		material: Enum.Material?, shape: Enum.PartType?)
		local limb = character:FindFirstChild(limbName) :: BasePart?
		if not limb then return end
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		if shape then p.Shape = shape end
		p.Color = color
		p.Material = material or Enum.Material.Leather
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.TopSurface = Enum.SurfaceType.Smooth
		p.BottomSurface = Enum.SurfaceType.Smooth
		p.CFrame = limb.CFrame * offset
		if shape == nil and name:find("Wedge") then
			-- (wedges: a WedgePart in place of the block)
			local w = Instance.new("WedgePart")
			for _, prop in ipairs({ "Name", "Size", "Color", "Material", "CanCollide", "CanTouch", "CanQuery", "Massless", "CFrame" }) do
				(w :: any)[prop] = (p :: any)[prop]
			end
			p:Destroy()
			p = w :: any
		end
		local weld = Instance.new("WeldConstraint")
		weld.Name = "ArmorWeld"
		weld.Part0 = limb
		weld.Part1 = p
		weld.Parent = p
		p.Parent = outfit
	end

	-- Cowboy hat: brim tipped forward with the sides curled up, a tapered
	-- crown pinched at the front with a centre crease, band and a feather.
	local hat = CFrame.new(0, 0.62, 0.04) * CFrame.Angles(math.rad(-7), 0, 0)
	add("Head", "HatBrim", Vector3.new(0.1, 2.3, 2.5), hat * VERTICAL, GS_DARK, nil, Enum.PartType.Cylinder)
	for _, side in ipairs({ -1, 1 }) do
		-- Curled side of the brim, rising toward its outer edge.
		add("Head", "HatCurl", Vector3.new(0.45, 0.1, 1.85),
			hat * CFrame.new(side * 1.02, 0.1, 0.05) * CFrame.Angles(0, 0, math.rad(side * 32)), GS_DARK)
		add("Head", "HatCurlTip", Vector3.new(0.24, 0.1, 1.1),
			hat * CFrame.new(side * 1.24, 0.3, 0.05) * CFrame.Angles(0, 0, math.rad(side * 58)), GS_DARK)
	end
	add("Head", "HatCrown", Vector3.new(0.5, 1.5, 1.62), hat * CFrame.new(0, 0.3, 0.05) * VERTICAL, GS_DARK, nil, Enum.PartType.Cylinder)
	add("Head", "HatCrownMid", Vector3.new(0.4, 1.4, 1.5), hat * CFrame.new(0, 0.72, 0.07) * VERTICAL, GS_DARK, nil, Enum.PartType.Cylinder)
	add("Head", "HatCrownTop", Vector3.new(0.14, 1.22, 1.36), hat * CFrame.new(0, 0.98, 0.09) * VERTICAL, GS_DARK, nil, Enum.PartType.Cylinder)
	add("Head", "HatCrease", Vector3.new(0.3, 0.1, 1.05), hat * CFrame.new(0, 1.07, 0.12), GS_COAT)
	for _, side in ipairs({ -1, 1 }) do
		-- Front pinch: the crown's front corners pressed in.
		add("Head", "HatPinch", Vector3.new(0.12, 0.62, 0.5),
			hat * CFrame.new(side * 0.42, 0.78, -0.6) * CFrame.Angles(0, math.rad(side * 35), 0), GS_COAT)
	end
	add("Head", "HatBand", Vector3.new(0.2, 1.54, 1.66), hat * CFrame.new(0, 0.2, 0.05) * VERTICAL, GS_BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	add("Head", "HatConcho", Vector3.new(0.08, 0.26, 0.26), hat * CFrame.new(0.55, 0.2, -0.62) * CFrame.Angles(0, math.rad(90 + 30), 0),
		GS_BRASS, Enum.Material.Metal, Enum.PartType.Cylinder)
	add("Head", "Feather", Vector3.new(0.1, 1.15, 0.32), hat * CFrame.new(0.78, 0.62, 0.3) * CFrame.Angles(math.rad(-20), 0, math.rad(-28)),
		Color3.fromRGB(196, 170, 132), Enum.Material.Fabric)
	add("Head", "FeatherTip", Vector3.new(0.08, 0.45, 0.22), hat * CFrame.new(0.99, 1.14, 0.43) * CFrame.Angles(math.rad(-20), 0, math.rad(-28)),
		Color3.fromRGB(90, 60, 40), Enum.Material.Fabric)
	-- The player's own hats would poke through the new one.
	for _, acc in ipairs(character:GetChildren()) do
		if acc:IsA("Accessory") and acc.AccessoryType == Enum.AccessoryType.Hat then
			local handle = acc:FindFirstChild("Handle")
			if handle and handle:IsA("BasePart") then handle.Transparency = 1 end
		end
	end
	-- The bandana: pulled up over the mouth and nose, knotted round the neck.
	add("Head", "BandanaFront", Vector3.new(1.24, 0.5, 0.12), CFrame.new(0, -0.24, -0.6), GS_SCARF, Enum.Material.Fabric)
	add("Head", "BandanaWedge", Vector3.new(1.0, 0.4, 0.12), CFrame.new(0, -0.62, -0.62) * CFrame.Angles(0, math.pi, math.pi), GS_SCARF, Enum.Material.Fabric)
	add("Torso", "Scarf", Vector3.new(0.45, 1.5, 1.5), CFrame.new(0, 1.05, 0) * VERTICAL, GS_SCARF, Enum.Material.Fabric, Enum.PartType.Cylinder)

	-- The duster: the coat over the torso, open at the chest, broad lapels.
	add("Torso", "Coat", Vector3.new(2.12, 2.06, 1.14), CFrame.new(0, 0, 0.02), GS_COAT)
	add("Torso", "Shirt", Vector3.new(0.7, 1.4, 0.06), CFrame.new(0, 0.25, -0.58), GS_STRAP, Enum.Material.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		add("Torso", "LapelWedge", Vector3.new(0.12, 1.1, 0.42),
			CFrame.new(side * 0.5, 0.45, -0.62) * CFrame.Angles(0, math.rad(side * 90), math.rad(side * 12)), GS_LEATHER)
	end
	-- crossed bandoliers of brass rounds
	for _, side in ipairs({ -1, 1 }) do
		local strap = CFrame.new(0, 0.05, -0.62) * CFrame.Angles(0, 0, math.rad(side * 38))
		add("Torso", "Bandolier", Vector3.new(0.3, 2.7, 0.07), strap, GS_STRAP)
		for k = -3, 3 do
			add("Torso", "Round", Vector3.new(0.16, 0.12, 0.12), strap * CFrame.new(0, k * 0.3, -0.07), GS_BRASS, Enum.Material.Metal)
		end
	end
	-- the gun belt, buckle and the holster on the right hip
	add("Torso", "GunBelt", Vector3.new(2.2, 0.32, 1.2), CFrame.new(0, -0.88, 0), GS_STRAP)
	add("Torso", "Buckle", Vector3.new(0.42, 0.3, 0.08), CFrame.new(0, -0.88, -0.62), GS_BRASS, Enum.Material.Metal)
	add("Right Leg", "Holster", Vector3.new(0.35, 0.95, 0.6), CFrame.new(0.58, 0.35, 0) * CFrame.Angles(0, 0, math.rad(8)), GS_LEATHER)
	add("Right Leg", "HolsterTie", Vector3.new(1.08, 0.12, 1.08), CFrame.new(0, -0.05, 0), GS_STRAP)
	-- sleeves with turned-back cuffs
	for _, arm in ipairs({ "Left Arm", "Right Arm" }) do
		add(arm, "Sleeve", Vector3.new(1.1, 1.75, 1.1), CFrame.new(0, 0.12, 0), GS_COAT)
		add(arm, "Cuff", Vector3.new(1.16, 0.3, 1.16), CFrame.new(0, -0.66, 0), GS_LEATHER)
		add(arm, "Shoulder", Vector3.new(1.18, 0.45, 1.18), CFrame.new(0, 0.82, 0), GS_LEATHER)
	end
	-- the duster's tails, down past the knee on each leg (they move with it)
	for _, leg in ipairs({ "Left Leg", "Right Leg" }) do
		add(leg, "CoatTail", Vector3.new(1.16, 1.25, 1.16), CFrame.new(0, 0.38, 0), GS_COAT)
		add(leg, "CoatHem", Vector3.new(1.2, 0.18, 1.2), CFrame.new(0, -0.25, 0), GS_LEATHER)
	end

	-- Boots with brass spurs.
	for _, leg in ipairs({ "Left Leg", "Right Leg" }) do
		add(leg, "Boot", Vector3.new(1.1, 0.75, 1.1), CFrame.new(0, -0.64, 0), GS_DARK)
		add(leg, "BootToe", Vector3.new(1.02, 0.35, 0.3), CFrame.new(0, -0.84, -0.6), GS_DARK)
		add(leg, "Spur", Vector3.new(0.1, 0.1, 0.34), CFrame.new(0, -0.88, 0.66), GS_BRASS, Enum.Material.Metal)
	end

	outfit.Parent = character
end

-- Equip a class's armor folder onto a character. `tag` (e.g. "PreviewArmor")
-- is set as an attribute on every piece so a preview can remove them again.
function ClassArmor.Equip(character: Model, classId: string, tag: string?)
	if not ClassArmor.Enabled then return end
	if classId == "gunslinger" then
		buildGunslingerOutfit(character, tag)
		return
	end

	-- (The Fire Knight wears no plate: his outfit is his cloth cape with the
	-- black fur mantle, hung on each client by ClassCapes / ClassLook.)
	local CLASS_ARMOR_FOLDERS = {
		ranger = "Ranger armor",
		cleric = "Cleric armor",
	}

	local folderName = CLASS_ARMOR_FOLDERS[classId]
	if not folderName then return end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local classes = assets and assets:FindFirstChild("Classes")
	local armorFolder = classes and classes:FindFirstChild(folderName)
	if not armorFolder then return end

	-- Position each armor piece individually on its target limb
	for _, piece in ipairs(armorFolder:GetChildren()) do
		if piece:IsA("Tool") then
			continue
		end


		print(`[ArmorEquip] Processing armor piece: "{piece.Name}" (ClassName: {piece.ClassName})`)
		local clone = piece:Clone()
		if tag then clone:SetAttribute(tag, true) end


		-- Scale first
		local pieceScale = ARMOR_PIECE_SCALES[piece.Name] or ARMOR_SCALE
		scaleArmorPiece(clone, pieceScale)

		-- RangerCloak has an authored "root" part. Align that root to the
		-- character root (with a small visual drop) instead of centering the
		-- whole model on the torso.
		local cloakRoot: BasePart? = nil
		local rootAlignedCloak = classId == "ranger" and piece.Name == "RangerCloak"
		if rootAlignedCloak then
			local foundRoot = clone:FindFirstChild("root", true)
			if foundRoot and foundRoot:IsA("BasePart") then
				cloakRoot = foundRoot
			else
				warn("[ArmorEquip] RangerCloak needs a BasePart named 'root'.")
				clone:Destroy()
				continue
			end
		end

		-- Determine target R6 limb
		local targetPartName = ARMOR_WELD_MAP[piece.Name] or "Torso"
		local targetPart = character:FindFirstChild(targetPartName) :: BasePart?
		if not targetPart then
			clone.Parent = character
			continue
		end

		-- Get the rotation offset for this piece
		local rotOffset = rootAlignedCloak and CFrame.new(0, 0.15, 0) or (ARMOR_CFRAME_OFFSETS[piece.Name] or CFrame.identity)

		-- Get the bounding box center of this piece
		local pieceCF: CFrame
		if rootAlignedCloak and cloakRoot then
			pieceCF = cloakRoot.CFrame
		elseif clone:IsA("Model") then
			pieceCF = clone:GetBoundingBox()
		elseif clone:IsA("Accessory") then
			local handle = clone:FindFirstChild("Handle") :: BasePart?
			if handle then
				pieceCF = handle.CFrame
			else
				pieceCF = CFrame.identity
			end
		elseif clone:IsA("BasePart") then
			pieceCF = clone.CFrame
		else
			clone.Parent = character
			continue
		end

		-- Cleric Robe: hang from the shoulders, facing forward.
		if classId == "cleric" and piece.Name == "Cleric Robe" then
			local boxSize: Vector3
			if clone:IsA("Model") then
				local _, size = clone:GetBoundingBox()
				boxSize = size
			elseif clone:IsA("BasePart") then
				boxSize = (clone :: BasePart).Size
			else
				boxSize = targetPart.Size
			end
			-- Wider along Z than X means the mesh came in sideways: turn it 90°.
			local facing = CLERIC_ROBE.rotation or (boxSize.Z > boxSize.X and ROT90 or CFrame.identity)
			if CLERIC_ROBE.flip then
				facing = CFrame.Angles(0, math.pi, 0) * facing
			end
			local drop = math.max(0, boxSize.Y * 0.5 - targetPart.Size.Y * 0.5) - CLERIC_ROBE.raise
			rotOffset = CFrame.new(0, -drop, CLERIC_ROBE.forward) * facing
			print(`[ArmorEquip] Cleric Robe box {boxSize}, dropped {drop} studs`)
		end

		-- Snap the piece center to the limb center with rotation
		local targetCF = targetPart.CFrame * rotOffset
		local transform = targetCF * pieceCF:Inverse()

		-- Apply transform to all parts
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = false
				desc.CFrame = transform * desc.CFrame
			end
		end
		if clone:IsA("BasePart") then
			local bp = clone :: BasePart
			bp.CanCollide = false
			bp.CanTouch = false
			bp.CanQuery = false
			bp.Massless = true
			bp.Anchored = false
			bp.CFrame = transform * bp.CFrame
		end

		clone.Parent = character

		-- Weld every BasePart in this piece to the target limb
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "ArmorWeld"
				weld.Part0 = targetPart
				weld.Part1 = desc
				weld.Parent = desc
			end
		end
		if clone:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "ArmorWeld"
			weld.Part0 = targetPart
			weld.Part1 = clone :: BasePart
			weld.Parent = clone
		end
	end

end

-- Remove every piece previously equipped with `tag`.
function ClassArmor.Remove(character: Model, tag: string)
	for _, d in ipairs(character:GetChildren()) do
		if d:GetAttribute(tag) then d:Destroy() end
	end
end

return ClassArmor
