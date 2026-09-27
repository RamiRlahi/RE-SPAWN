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

-- Equip a class's armor folder onto a character. `tag` (e.g. "PreviewArmor")
-- is set as an attribute on every piece so a preview can remove them again.
function ClassArmor.Equip(character: Model, classId: string, tag: string?)
	if not ClassArmor.Enabled then return end

	local CLASS_ARMOR_FOLDERS = {
		heavy_knight = "heavy knight armor",
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

		-- Omit leg armor pieces for Heavy Knight
		if classId == "heavy_knight" and (piece.Name == "leftleg" or piece.Name == "rightleg" or string.find(string.lower(piece.Name), "leg") ~= nil) then
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
