local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))

local player = Players.LocalPlayer

-- Class Armor Preview: maps classId -> armor folder name under ReplicatedStorage.Assets.Classes
local CLASS_ARMOR_FOLDERS: { [string]: string } = {
	heavy_knight = "heavy knight armor",
}

-- Maps armor piece name -> R6 body part name it should be welded to
local ARMOR_WELD_MAP: { [string]: string } = {
	chestplate              = "Torso",
	gauntlet_heavyknight    = "Left Arm", -- The left gauntlet
	leftarm_heavyknight     = "Left Arm",
	rightarm_heavyknight    = "Right Arm",
	heavyknight_BELT        = "Torso",
	leftleg                 = "Left Leg",
	rightleg                = "Right Leg",
}

-- Per-piece CFrame correction applied BEFORE the weld locks the offset in.
local ROT270 = CFrame.Angles(0, math.rad(270), 0)
local ROT90 = CFrame.Angles(0, math.rad(90), 0)

local ARMOR_CFRAME_OFFSETS: { [string]: CFrame } = {
	chestplate              = ROT270 * CFrame.new(0, 0, 0),
	gauntlet_heavyknight    = ROT90 * CFrame.new(0, 0, 0),
	leftarm_heavyknight     = ROT90 * CFrame.new(0, 0, 0),
	rightarm_heavyknight    = ROT270 * CFrame.new(0, 0, 0),
	heavyknight_BELT        = ROT270 * CFrame.new(0, -1.9, 0),
	leftleg                 = ROT270 * CFrame.new(-1, 0, 0), -- 1 stud forward
	rightleg                = ROT270 * CFrame.new(-1, 0, 0), -- 1 stud forward
}

local ARMOR_SCALE = 1-- Snug fit to make the armor smaller and well-proportioned

-- Per-piece forward nudge offsets applied in character space (Z negative = forward)
local ARMOR_PIECE_NUDGES: { [string]: Vector3 } = {
	gauntlet_heavyknight = Vector3.new(0, 0, -0.35),
	leftarm_heavyknight  = Vector3.new(0, 0, -0.35),
	leftleg              = Vector3.new(0, 0, -0.25),
}


local function scaleArmorPiece(piece: Model | BasePart, scale: number)
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
	elseif piece:IsA("BasePart") then
		piece.Size *= scale
	end
end

local function weldArmorPiece(piece: Model | BasePart, targetPart: BasePart, pieceName: string)
	-- Scale the armor piece first
	scaleArmorPiece(piece, ARMOR_SCALE)

	-- Get all BaseParts in the piece
	local parts: { BasePart } = {}
	if piece:IsA("BasePart") then
		table.insert(parts, piece)
	elseif piece:IsA("Model") then
		for _, desc in ipairs(piece:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
	end

	if #parts == 0 then
		warn(`[ClassSelection] ⚠️ Piece "{pieceName}" has 0 BaseParts!`)
		return
	end

	local offset = ARMOR_CFRAME_OFFSETS[pieceName] or CFrame.identity

	-- Calculate the true bounding-box center and rotation of the armor piece
	local pieceCFrame: CFrame
	if piece:IsA("Model") then
		local cf, size = piece:GetBoundingBox()
		pieceCFrame = cf
		print(`  [WeldDetails] "{pieceName}" is Model (#parts: {#parts}, Size: {size}, BoxPos: {cf.Position})`)
	else
		pieceCFrame = piece.CFrame
		print(`  [WeldDetails] "{pieceName}" is BasePart (Size: {piece.Size}, Pos: {piece.Position})`)
	end

	-- Compute transformation to align armor center with target part CFrame + offset
	local targetCF = targetPart.CFrame * offset
	local transform = targetCF * pieceCFrame:Inverse()

	for _, part in ipairs(parts) do
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.CFrame = transform * part.CFrame

		local weld = Instance.new("WeldConstraint")
		weld.Name = "ArmorWeld"
		weld.Part0 = targetPart
		weld.Part1 = part
		weld.Parent = part
	end
end

local function applyClassCosmetics(classId: string)
	local character = player.Character
	if not character then return end

	-- Remove all previously applied preview armor
	for _, instance in ipairs(character:GetChildren()) do
		if instance:GetAttribute("PreviewArmor") then
			instance:Destroy()
		end
	end

	-- Find the armor folder for this class
	local folderName = CLASS_ARMOR_FOLDERS[classId]
	if not folderName then return end

	local armorFolder = ReplicatedStorage
		:FindFirstChild("Assets")
		:FindFirstChild("Classes")
		:FindFirstChild(folderName)

	if not armorFolder then
		warn("[ClassSelection] Armor folder not found:", folderName)
		return
	end

	-- Position each armor piece individually on its target limb
	for _, piece in ipairs(armorFolder:GetChildren()) do
		local clone = piece:Clone()
		clone:SetAttribute("PreviewArmor", true)

		-- Scale first
		scaleArmorPiece(clone, ARMOR_SCALE)

		-- Determine the target R6 body part
		local targetPartName = ARMOR_WELD_MAP[piece.Name] or "Torso"
		local targetPart = character:FindFirstChild(targetPartName) :: BasePart?
		if not targetPart then
			clone.Parent = character
			continue
		end

		-- Get the rotation offset for this piece
		local rotOffset = ARMOR_CFRAME_OFFSETS[piece.Name] or CFrame.identity

		-- Get the bounding box center of this piece
		local pieceCF: CFrame
		if clone:IsA("Model") then
			pieceCF = clone:GetBoundingBox()
		else
			pieceCF = (clone :: BasePart).CFrame
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
				desc.CFrame = transform * desc.CFrame
			end
		end
		if clone:IsA("BasePart") then
			local bp = clone :: BasePart
			bp.CanCollide = false
			bp.CanTouch = false
			bp.CanQuery = false
			bp.Massless = true
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


export type ClassSelectionCallbacks = {
	onBackToTitle: () -> (),
	onConfirmClass: (classId: string) -> (),
}

local ClassSelectionScreen = {}

function ClassSelectionScreen.Create(parent: GuiObject, callbacks: ClassSelectionCallbacks): CanvasGroup
	local container = Instance.new("CanvasGroup")
	container.Name = "ClassSelectionScreen"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 1
	container.Visible = false
	container.Parent = parent

	-- Subtle Dark Vignette Border (Keep center open to see the 3D character clearly)
	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.new(1, 0, 1, 0)
	vignette.BackgroundColor3 = UITheme.Colors.BackgroundOverlay
	vignette.BackgroundTransparency = 0.5
	vignette.BorderSizePixel = 0
	vignette.Parent = container

	local vignetteGrad = Instance.new("UIGradient")
	vignetteGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	vignetteGrad.Rotation = 0
	vignetteGrad.Parent = vignette

	-- Top Header Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 70)
	topBar.BackgroundTransparency = 1
	topBar.Parent = container

	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.Size = UDim2.new(0, 140, 0, 38)
	backBtn.Position = UDim2.new(0, 24, 0.5, -19)
	backBtn.BackgroundColor3 = UITheme.Colors.Surface
	backBtn.AutoButtonColor = false
	backBtn.Text = "← TITLE"
	backBtn.TextColor3 = UITheme.Colors.TextSecondary
	backBtn.Font = UITheme.Fonts.Button
	backBtn.TextSize = 13
	backBtn.Parent = topBar

	UITheme.AddCorner(backBtn, 6)
	local backStroke = UITheme.AddStroke(backBtn, UITheme.Colors.Border, 1, 0.5)
	UITheme.MakeButtonInteractive(backBtn, backStroke, UITheme.Colors.Gold, SoundManager.PlayHover, function()
		SoundManager.PlayClick()
		callbacks.onBackToTitle()
	end)

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "HeaderTitle"
	headerTitle.Size = UDim2.new(0, 450, 0, 30)
	headerTitle.AnchorPoint = Vector2.new(0.5, 0)
	headerTitle.Position = UDim2.new(0.5, 0, 0, 12)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "CHOOSE YOUR CLASS"
	headerTitle.TextColor3 = UITheme.Colors.GoldLight
	headerTitle.Font = UITheme.Fonts.Header
	headerTitle.TextSize = 22
	headerTitle.Parent = topBar

	local headerCounter = Instance.new("TextLabel")
	headerCounter.Name = "HeaderCounter"
	headerCounter.Size = UDim2.new(0, 450, 0, 20)
	headerCounter.AnchorPoint = Vector2.new(0.5, 0)
	headerCounter.Position = UDim2.new(0.5, 0, 0, 42)
	headerCounter.BackgroundTransparency = 1
	headerCounter.Text = "CLASS 1 OF 8"
	headerCounter.TextColor3 = UITheme.Colors.TextMuted
	headerCounter.Font = UITheme.Fonts.Tag
	headerCounter.TextSize = 11
	headerCounter.Parent = topBar

	---------------------------------------------------------------------
	-- Left Panel: Identity, Lore & Animated Stats
	---------------------------------------------------------------------
	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LeftPanel"
	leftPanel.Size = UDim2.new(0, 320, 1, -170)
	leftPanel.Position = UDim2.new(0, 24, 0, 75)
	leftPanel.BackgroundColor3 = UITheme.Colors.Surface
	leftPanel.BackgroundTransparency = 0.15
	leftPanel.Parent = container

	UITheme.AddCorner(leftPanel, 10)
	local leftStroke = UITheme.AddStroke(leftPanel, UITheme.Colors.Border, 1.5, 0.4)

	local leftScroll = Instance.new("ScrollingFrame")
	leftScroll.Name = "LeftScroll"
	leftScroll.Size = UDim2.new(1, -24, 1, -24)
	leftScroll.Position = UDim2.new(0, 12, 0, 12)
	leftScroll.BackgroundTransparency = 1
	leftScroll.ScrollBarThickness = 3
	leftScroll.ScrollBarImageColor3 = UITheme.Colors.Gold
	leftScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leftScroll.Parent = leftPanel

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.FillDirection = Enum.FillDirection.Vertical
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Padding = UDim.new(0, 12)
	leftLayout.Parent = leftScroll

	local classNameLabel = Instance.new("TextLabel")
	classNameLabel.Name = "ClassName"
	classNameLabel.Size = UDim2.new(1, 0, 0, 34)
	classNameLabel.BackgroundTransparency = 1
	classNameLabel.Font = UITheme.Fonts.Title
	classNameLabel.TextSize = 28
	classNameLabel.TextColor3 = UITheme.Colors.GoldLight
	classNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	classNameLabel.LayoutOrder = 1
	classNameLabel.Parent = leftScroll

	local titleRoleRow = Instance.new("Frame")
	titleRoleRow.Name = "TitleRoleRow"
	titleRoleRow.Size = UDim2.new(1, 0, 0, 24)
	titleRoleRow.BackgroundTransparency = 1
	titleRoleRow.LayoutOrder = 2
	titleRoleRow.Parent = leftScroll

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(0.6, 0, 1, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = UITheme.Fonts.Sub
	subtitleLabel.TextSize = 13
	subtitleLabel.TextColor3 = UITheme.Colors.TextSecondary
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.Parent = titleRoleRow

	local roleBadge = Instance.new("TextLabel")
	roleBadge.Name = "RoleBadge"
	roleBadge.Size = UDim2.new(0.4, 0, 1, 0)
	roleBadge.AnchorPoint = Vector2.new(1, 0)
	roleBadge.Position = UDim2.new(1, 0, 0, 0)
	roleBadge.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	roleBadge.Font = UITheme.Fonts.Tag
	roleBadge.TextSize = 10
	roleBadge.TextColor3 = UITheme.Colors.GoldLight
	roleBadge.Parent = titleRoleRow
	UITheme.AddCorner(roleBadge, 4)

	local loreBox = Instance.new("Frame")
	loreBox.Name = "LoreBox"
	loreBox.Size = UDim2.new(1, 0, 0, 0)
	loreBox.AutomaticSize = Enum.AutomaticSize.Y
	loreBox.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	loreBox.BackgroundTransparency = 0.5
	loreBox.LayoutOrder = 3
	loreBox.Parent = leftScroll
	UITheme.AddCorner(loreBox, 6)
	UITheme.AddPadding(loreBox, 8, 8, 10, 10)

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(1, 0, 0, 0)
	descLabel.AutomaticSize = Enum.AutomaticSize.Y
	descLabel.BackgroundTransparency = 1
	descLabel.Font = UITheme.Fonts.Body
	descLabel.TextSize = 12
	descLabel.TextColor3 = UITheme.Colors.TextPrimary
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = loreBox

	-- Stats Header
	local statsHeader = Instance.new("TextLabel")
	statsHeader.Name = "StatsHeader"
	statsHeader.Size = UDim2.new(1, 0, 0, 20)
	statsHeader.BackgroundTransparency = 1
	statsHeader.Text = "ATTRIBUTES & RATINGS"
	statsHeader.TextColor3 = UITheme.Colors.GoldLight
	statsHeader.Font = UITheme.Fonts.Header
	statsHeader.TextSize = 13
	statsHeader.TextXAlignment = Enum.TextXAlignment.Left
	statsHeader.LayoutOrder = 4
	statsHeader.Parent = leftScroll

	-- Stats Box with animated pips
	local statsBox = Instance.new("Frame")
	statsBox.Name = "StatsBox"
	statsBox.Size = UDim2.new(1, 0, 0, 110)
	statsBox.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	statsBox.LayoutOrder = 5
	statsBox.Parent = leftScroll
	UITheme.AddCorner(statsBox, 6)
	UITheme.AddPadding(statsBox, 8, 8, 10, 10)

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 6)
	statsLayout.Parent = statsBox

	local statBars: { [string]: { Frame } } = {}
	local statKeys = { "offense", "defense", "agility", "difficulty" }

	for idx, key in ipairs(statKeys) do
		local statRow = Instance.new("Frame")
		statRow.Name = "Stat_" .. key
		statRow.Size = UDim2.new(1, 0, 0, 18)
		statRow.BackgroundTransparency = 1
		statRow.LayoutOrder = idx
		statRow.Parent = statsBox

		local sTitle = Instance.new("TextLabel")
		sTitle.Size = UDim2.new(0.35, 0, 1, 0)
		sTitle.BackgroundTransparency = 1
		sTitle.Text = key:upper()
		sTitle.TextColor3 = UITheme.Colors.TextSecondary
		sTitle.Font = UITheme.Fonts.Tag
		sTitle.TextSize = 10
		sTitle.TextXAlignment = Enum.TextXAlignment.Left
		sTitle.Parent = statRow

		local barRow = Instance.new("Frame")
		barRow.Size = UDim2.new(0.65, 0, 0, 8)
		barRow.AnchorPoint = Vector2.new(1, 0.5)
		barRow.Position = UDim2.new(1, 0, 0.5, 0)
		barRow.BackgroundTransparency = 1
		barRow.Parent = statRow

		local barLayout = Instance.new("UIListLayout")
		barLayout.FillDirection = Enum.FillDirection.Horizontal
		barLayout.Padding = UDim.new(0, 4)
		barLayout.Parent = barRow

		statBars[key] = {}
		for b = 1, 5 do
			local pip = Instance.new("Frame")
			pip.Name = "Pip_" .. b
			pip.Size = UDim2.new(0.2, -4, 1, 0)
			pip.BackgroundColor3 = UITheme.Colors.SurfaceSelected
			pip.BorderSizePixel = 0
			pip.Parent = barRow
			UITheme.AddCorner(pip, 2)
			table.insert(statBars[key], pip)
		end
	end

	---------------------------------------------------------------------
	-- Right Panel: Skills Showcase & Equipment Showcase
	---------------------------------------------------------------------
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(0, 360, 1, -170)
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.Position = UDim2.new(1, -24, 0, 75)
	rightPanel.BackgroundColor3 = UITheme.Colors.Surface
	rightPanel.BackgroundTransparency = 0.15
	rightPanel.Parent = container

	UITheme.AddCorner(rightPanel, 10)
	local rightStroke = UITheme.AddStroke(rightPanel, UITheme.Colors.Border, 1.5, 0.4)

	local rightScroll = Instance.new("ScrollingFrame")
	rightScroll.Name = "RightScroll"
	rightScroll.Size = UDim2.new(1, -24, 1, -24)
	rightScroll.Position = UDim2.new(0, 12, 0, 12)
	rightScroll.BackgroundTransparency = 1
	rightScroll.ScrollBarThickness = 3
	rightScroll.ScrollBarImageColor3 = UITheme.Colors.Gold
	rightScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightScroll.Parent = rightPanel

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.FillDirection = Enum.FillDirection.Vertical
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 10)
	rightLayout.Parent = rightScroll

	-- 1. Skills Section Header
	local skillsHeader = Instance.new("TextLabel")
	skillsHeader.Name = "SkillsHeader"
	skillsHeader.Size = UDim2.new(1, 0, 0, 20)
	skillsHeader.BackgroundTransparency = 1
	skillsHeader.Text = "CLASS COMBAT SKILLS"
	skillsHeader.TextColor3 = UITheme.Colors.GoldLight
	skillsHeader.Font = UITheme.Fonts.Header
	skillsHeader.TextSize = 13
	skillsHeader.TextXAlignment = Enum.TextXAlignment.Left
	skillsHeader.LayoutOrder = 1
	skillsHeader.Parent = rightScroll

	local abilitiesContainer = Instance.new("Frame")
	abilitiesContainer.Name = "AbilitiesContainer"
	abilitiesContainer.Size = UDim2.new(1, 0, 0, 0)
	abilitiesContainer.AutomaticSize = Enum.AutomaticSize.Y
	abilitiesContainer.BackgroundTransparency = 1
	abilitiesContainer.LayoutOrder = 2
	abilitiesContainer.Parent = rightScroll

	local abilitiesListLayout = Instance.new("UIListLayout")
	abilitiesListLayout.FillDirection = Enum.FillDirection.Vertical
	abilitiesListLayout.Padding = UDim.new(0, 6)
	abilitiesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilitiesListLayout.Parent = abilitiesContainer

	-- 2. Equipment Section Header
	local eqHeader = Instance.new("TextLabel")
	eqHeader.Name = "EquipmentHeader"
	eqHeader.Size = UDim2.new(1, 0, 0, 20)
	eqHeader.BackgroundTransparency = 1
	eqHeader.Text = "SIGNATURE EQUIPMENT"
	eqHeader.TextColor3 = UITheme.Colors.GoldLight
	eqHeader.Font = UITheme.Fonts.Header
	eqHeader.TextSize = 13
	eqHeader.TextXAlignment = Enum.TextXAlignment.Left
	eqHeader.LayoutOrder = 3
	eqHeader.Parent = rightScroll

	-- Equipment Card Container
	local eqCard = Instance.new("Frame")
	eqCard.Name = "EquipmentCard"
	eqCard.Size = UDim2.new(1, 0, 0, 0)
	eqCard.AutomaticSize = Enum.AutomaticSize.Y
	eqCard.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	eqCard.LayoutOrder = 4
	eqCard.Parent = rightScroll

	UITheme.AddCorner(eqCard, 8)
	local eqStroke = UITheme.AddStroke(eqCard, UITheme.Colors.Gold, 1.5, 0.4)
	UITheme.AddPadding(eqCard, 10, 10, 12, 12)

	local eqLayout = Instance.new("UIListLayout")
	eqLayout.FillDirection = Enum.FillDirection.Vertical
	eqLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eqLayout.Padding = UDim.new(0, 6)
	eqLayout.Parent = eqCard

	local eqNameLabel = Instance.new("TextLabel")
	eqNameLabel.Name = "EqName"
	eqNameLabel.Size = UDim2.new(1, 0, 0, 20)
	eqNameLabel.BackgroundTransparency = 1
	eqNameLabel.Font = UITheme.Fonts.Header
	eqNameLabel.TextSize = 15
	eqNameLabel.TextColor3 = UITheme.Colors.GoldLight
	eqNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	eqNameLabel.LayoutOrder = 1
	eqNameLabel.Parent = eqCard

	local eqMetaRow = Instance.new("Frame")
	eqMetaRow.Name = "EqMetaRow"
	eqMetaRow.Size = UDim2.new(1, 0, 0, 18)
	eqMetaRow.BackgroundTransparency = 1
	eqMetaRow.LayoutOrder = 2
	eqMetaRow.Parent = eqCard

	local eqRarityBadge = Instance.new("TextLabel")
	eqRarityBadge.Name = "EqRarity"
	eqRarityBadge.Size = UDim2.new(0, 140, 1, 0)
	eqRarityBadge.BackgroundColor3 = UITheme.Colors.Surface
	eqRarityBadge.Font = UITheme.Fonts.Tag
	eqRarityBadge.TextSize = 10
	eqRarityBadge.TextColor3 = UITheme.Colors.Gold
	eqRarityBadge.Parent = eqMetaRow
	UITheme.AddCorner(eqRarityBadge, 3)

	local eqSlotLabel = Instance.new("TextLabel")
	eqSlotLabel.Name = "EqSlot"
	eqSlotLabel.Size = UDim2.new(1, -150, 1, 0)
	eqSlotLabel.Position = UDim2.new(0, 148, 0, 0)
	eqSlotLabel.BackgroundTransparency = 1
	eqSlotLabel.Font = UITheme.Fonts.Sub
	eqSlotLabel.TextSize = 11
	eqSlotLabel.TextColor3 = UITheme.Colors.TextMuted
	eqSlotLabel.TextXAlignment = Enum.TextXAlignment.Left
	eqSlotLabel.Parent = eqMetaRow

	local eqDescLabel = Instance.new("TextLabel")
	eqDescLabel.Name = "EqDesc"
	eqDescLabel.Size = UDim2.new(1, 0, 0, 0)
	eqDescLabel.AutomaticSize = Enum.AutomaticSize.Y
	eqDescLabel.BackgroundTransparency = 1
	eqDescLabel.Font = UITheme.Fonts.Sub
	eqDescLabel.TextSize = 11
	eqDescLabel.TextColor3 = UITheme.Colors.TextSecondary
	eqDescLabel.TextWrapped = true
	eqDescLabel.TextXAlignment = Enum.TextXAlignment.Left
	eqDescLabel.LayoutOrder = 3
	eqDescLabel.Parent = eqCard

	-- Equipment Stats Container
	local eqStatsRow = Instance.new("Frame")
	eqStatsRow.Name = "EqStatsRow"
	eqStatsRow.Size = UDim2.new(1, 0, 0, 0)
	eqStatsRow.AutomaticSize = Enum.AutomaticSize.Y
	eqStatsRow.BackgroundTransparency = 1
	eqStatsRow.LayoutOrder = 4
	eqStatsRow.Parent = eqCard

	local eqStatsLayout = Instance.new("UIListLayout")
	eqStatsLayout.FillDirection = Enum.FillDirection.Vertical
	eqStatsLayout.Padding = UDim.new(0, 3)
	eqStatsLayout.Parent = eqStatsRow

	---------------------------------------------------------------------
	-- Bottom Carousel Navigation & Confirmation Bar
	---------------------------------------------------------------------
	local bottomControls = Instance.new("Frame")
	bottomControls.Name = "BottomControls"
	bottomControls.Size = UDim2.new(1, 0, 0, 90)
	bottomControls.AnchorPoint = Vector2.new(0, 1)
	bottomControls.Position = UDim2.new(0, 0, 1, -10)
	bottomControls.BackgroundTransparency = 1
	bottomControls.Parent = container

	-- Left Arrow Button (< PREVIOUS)
	local prevBtn = Instance.new("TextButton")
	prevBtn.Name = "PrevButton"
	prevBtn.Size = UDim2.new(0, 60, 0, 50)
	prevBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	prevBtn.Position = UDim2.new(0.5, -230, 0.5, -8)
	prevBtn.BackgroundColor3 = UITheme.Colors.Surface
	prevBtn.AutoButtonColor = false
	prevBtn.Text = "◀"
	prevBtn.TextColor3 = UITheme.Colors.GoldLight
	prevBtn.Font = UITheme.Fonts.Header
	prevBtn.TextSize = 22
	prevBtn.Parent = bottomControls

	UITheme.AddCorner(prevBtn, 10)
	local prevStroke = UITheme.AddStroke(prevBtn, UITheme.Colors.Border, 1.5, 0.4)

	-- Right Arrow Button (NEXT >)
	local nextBtn = Instance.new("TextButton")
	nextBtn.Name = "NextButton"
	nextBtn.Size = UDim2.new(0, 60, 0, 50)
	nextBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	nextBtn.Position = UDim2.new(0.5, 230, 0.5, -8)
	nextBtn.BackgroundColor3 = UITheme.Colors.Surface
	nextBtn.AutoButtonColor = false
	nextBtn.Text = "▶"
	nextBtn.TextColor3 = UITheme.Colors.GoldLight
	nextBtn.Font = UITheme.Fonts.Header
	nextBtn.TextSize = 22
	nextBtn.Parent = bottomControls

	UITheme.AddCorner(nextBtn, 10)
	local nextStroke = UITheme.AddStroke(nextBtn, UITheme.Colors.Border, 1.5, 0.4)

	-- Center Confirm Button
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmButton"
	confirmBtn.Size = UDim2.new(0, 320, 0, 50)
	confirmBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmBtn.Position = UDim2.new(0.5, 0, 0.5, -8)
	confirmBtn.BackgroundColor3 = UITheme.Colors.Gold
	confirmBtn.AutoButtonColor = false
	confirmBtn.Text = "CONFIRM & ENTER WORLD"
	confirmBtn.TextColor3 = Color3.fromRGB(20, 15, 10)
	confirmBtn.Font = UITheme.Fonts.Button
	confirmBtn.TextSize = 16
	confirmBtn.Parent = bottomControls

	UITheme.AddCorner(confirmBtn, 8)
	local confirmStroke = UITheme.AddStroke(confirmBtn, UITheme.Colors.GoldLight, 2, 0)
	UITheme.AddGradient(confirmBtn, UITheme.Colors.GoldLight, UITheme.Colors.Gold, 90)

	-- Dots / Carousel Indicator Container
	local dotsContainer = Instance.new("Frame")
	dotsContainer.Name = "DotsContainer"
	dotsContainer.Size = UDim2.new(0, 320, 0, 16)
	dotsContainer.AnchorPoint = Vector2.new(0.5, 1)
	dotsContainer.Position = UDim2.new(0.5, 0, 1, 2)
	dotsContainer.BackgroundTransparency = 1
	dotsContainer.Parent = bottomControls

	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	dotsLayout.Padding = UDim.new(0, 8)
	dotsLayout.Parent = dotsContainer

	local dotFrames: { [number]: Frame } = {}

	for i = 1, #ClassData.Order do
		local dot = Instance.new("Frame")
		dot.Name = "Dot_" .. i
		dot.Size = UDim2.new(0, 10, 0, 10)
		dot.BackgroundColor3 = UITheme.Colors.SurfaceSelected
		dot.BorderSizePixel = 0
		dot.Parent = dotsContainer
		UITheme.AddCorner(dot, 5)
		dotFrames[i] = dot

		local dotBtn = Instance.new("TextButton")
		dotBtn.Size = UDim2.new(1, 0, 1, 0)
		dotBtn.BackgroundTransparency = 1
		dotBtn.Text = ""
		dotBtn.Parent = dot
	end

	---------------------------------------------------------------------
	-- Carousel State & Transition Logic
	---------------------------------------------------------------------
	local currentIndex = 2 -- Default to Heavy Knight (index 2)
	local isTransitioning = false

	local function updateCarouselUI(index: number, isSlideTransition: boolean?)
		local classId = ClassData.Order[index]
		local info = ClassData.GetClass(classId)
		if not info then return end

		-- Apply class-specific cosmetic armor preview on the character
		applyClassCosmetics(classId)

		headerCounter.Text = `CLASS {index} OF {#ClassData.Order} • {info.name:upper()}`

		-- Update Left Panel
		classNameLabel.Text = info.name:upper()
		classNameLabel.TextColor3 = info.accentColor
		subtitleLabel.Text = info.title
		roleBadge.Text = `[{info.role:upper()}]`
		roleBadge.TextColor3 = info.accentColor
		descLabel.Text = info.description

		-- Update Border Accents to match active Class Color
		leftStroke.Color = info.accentColor
		rightStroke.Color = info.accentColor
		eqStroke.Color = info.accentColor
		prevStroke.Color = info.accentColor
		nextStroke.Color = info.accentColor

		-- Update Stats Pips
		for _, key in ipairs(statKeys) do
			local val = (info.stats :: any)[key] or 1
			local pips = statBars[key]
			if pips then
				for bIdx, pip in ipairs(pips) do
					local active = bIdx <= val
					pip.BackgroundColor3 = active and info.accentColor or UITheme.Colors.SurfaceSelected
				end
			end
		end

		-- Clear and Rebuild Abilities
		for _, child in ipairs(abilitiesContainer:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for i, ab in ipairs(info.abilities) do
			local abCard = Instance.new("Frame")
			abCard.Name = "Ability_" .. i
			abCard.Size = UDim2.new(1, 0, 0, 48)
			abCard.BackgroundColor3 = UITheme.Colors.SurfaceAlt
			abCard.LayoutOrder = i
			abCard.Parent = abilitiesContainer

			UITheme.AddCorner(abCard, 6)
			UITheme.AddStroke(abCard, UITheme.Colors.Border, 1, 0.6)

			local abTag = Instance.new("TextLabel")
			abTag.Name = "Tag"
			abTag.Size = UDim2.new(0, 90, 0, 16)
			abTag.Position = UDim2.new(0, 8, 0, 5)
			abTag.BackgroundColor3 = UITheme.Colors.Surface
			abTag.Font = UITheme.Fonts.Tag
			abTag.TextSize = 9
			abTag.TextColor3 = info.accentColor
			abTag.Text = ab.tag:upper()
			abTag.Parent = abCard
			UITheme.AddCorner(abTag, 3)

			local abName = Instance.new("TextLabel")
			abName.Name = "Name"
			abName.Size = UDim2.new(1, -110, 0, 16)
			abName.Position = UDim2.new(0, 104, 0, 5)
			abName.BackgroundTransparency = 1
			abName.Font = UITheme.Fonts.Header
			abName.TextSize = 12
			abName.TextColor3 = UITheme.Colors.TextPrimary
			abName.TextXAlignment = Enum.TextXAlignment.Left
			abName.Text = ab.name
			abName.Parent = abCard

			local abDesc = Instance.new("TextLabel")
			abDesc.Name = "Desc"
			abDesc.Size = UDim2.new(1, -16, 0, 22)
			abDesc.Position = UDim2.new(0, 8, 0, 23)
			abDesc.BackgroundTransparency = 1
			abDesc.Font = UITheme.Fonts.Sub
			abDesc.TextSize = 10
			abDesc.TextColor3 = UITheme.Colors.TextMuted
			abDesc.TextXAlignment = Enum.TextXAlignment.Left
			abDesc.Text = ab.description
			abDesc.Parent = abCard
		end

		-- Update Equipment Card
		local eq = info.equipment
		if eq then
			eqNameLabel.Text = eq.name
			eqNameLabel.TextColor3 = info.accentColor
			eqRarityBadge.Text = eq.rarity:upper()
			eqRarityBadge.TextColor3 = info.accentColor
			eqSlotLabel.Text = `[ {eq.slot} ]`
			eqDescLabel.Text = eq.description

			-- Rebuild Equipment Stat rows
			for _, child in ipairs(eqStatsRow:GetChildren()) do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end

			local statIdx = 0
			for statName, statVal in pairs(eq.stats or {}) do
				statIdx += 1
				local row = Instance.new("Frame")
				row.Name = "StatRow_" .. statIdx
				row.Size = UDim2.new(1, 0, 0, 16)
				row.BackgroundTransparency = 1
				row.LayoutOrder = statIdx
				row.Parent = eqStatsRow

				local lblKey = Instance.new("TextLabel")
				lblKey.Size = UDim2.new(0.6, 0, 1, 0)
				lblKey.BackgroundTransparency = 1
				lblKey.Font = UITheme.Fonts.Sub
				lblKey.TextSize = 10
				lblKey.TextColor3 = UITheme.Colors.TextSecondary
				lblKey.TextXAlignment = Enum.TextXAlignment.Left
				lblKey.Text = `• {statName}:`
				lblKey.Parent = row

				local lblVal = Instance.new("TextLabel")
				lblVal.Size = UDim2.new(0.4, 0, 1, 0)
				lblVal.AnchorPoint = Vector2.new(1, 0)
				lblVal.Position = UDim2.new(1, 0, 0, 0)
				lblVal.BackgroundTransparency = 1
				lblVal.Font = UITheme.Fonts.Header
				lblVal.TextSize = 10
				lblVal.TextColor3 = UITheme.Colors.Success
				lblVal.TextXAlignment = Enum.TextXAlignment.Right
				lblVal.Text = tostring(statVal)
				lblVal.Parent = row
			end
		end

		-- Update Dots indicator
		for dIdx, dot in ipairs(dotFrames) do
			local isActive = (dIdx == index)
			if isActive then
				TweenService:Create(dot, UITheme.Tweens.Fast, {
					Size = UDim2.new(0, 24, 0, 10),
					BackgroundColor3 = info.accentColor,
				}):Play()
			else
				TweenService:Create(dot, UITheme.Tweens.Fast, {
					Size = UDim2.new(0, 10, 0, 10),
					BackgroundColor3 = UITheme.Colors.SurfaceSelected,
				}):Play()
			end
		end
	end

	local function navigateCarousel(direction: number)
		if isTransitioning then return end
		isTransitioning = true

		local totalClasses = #ClassData.Order
		currentIndex = ((currentIndex - 1 + direction) % totalClasses) + 1

		SoundManager.PlaySelect()
		updateCarouselUI(currentIndex, true)

		task.wait(0.12)
		isTransitioning = false
	end

	-- Hook Navigation Buttons
	UITheme.MakeButtonInteractive(prevBtn, prevStroke, UITheme.Colors.GoldLight, SoundManager.PlayHover, function()
		navigateCarousel(-1)
	end)

	UITheme.MakeButtonInteractive(nextBtn, nextStroke, UITheme.Colors.GoldLight, SoundManager.PlayHover, function()
		navigateCarousel(1)
	end)

	-- Hook Dots Clicking
	for dIdx, dot in ipairs(dotFrames) do
		local dotBtn = dot:FindFirstChildOfClass("TextButton")
		if dotBtn then
			dotBtn.MouseButton1Click:Connect(function()
				if currentIndex ~= dIdx and not isTransitioning then
					currentIndex = dIdx
					SoundManager.PlaySelect()
					updateCarouselUI(currentIndex, true)
				end
			end)
		end
	end

	-- Hook Confirm Button
	UITheme.MakeButtonInteractive(confirmBtn, confirmStroke, UITheme.Colors.GoldLight, SoundManager.PlayHover, function()
		SoundManager.PlayConfirm()
		local selectedClassId = ClassData.Order[currentIndex]
		callbacks.onConfirmClass(selectedClassId)
	end)

	-- Keyboard Navigation (A / D, Left / Right Arrow, Enter)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not container.Visible or container.GroupTransparency > 0.5 then return end

		if input.KeyCode == Enum.KeyCode.A or input.KeyCode == Enum.KeyCode.Left then
			navigateCarousel(-1)
		elseif input.KeyCode == Enum.KeyCode.D or input.KeyCode == Enum.KeyCode.Right then
			navigateCarousel(1)
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
			SoundManager.PlayConfirm()
			local selectedClassId = ClassData.Order[currentIndex]
			callbacks.onConfirmClass(selectedClassId)
		end
	end)

	-- Dynamic Re-renders when screen opens
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible then
			updateCarouselUI(currentIndex, false)
		end
	end)

	-- Initialize to Heavy Knight (index 2)
	currentIndex = 2
	updateCarouselUI(currentIndex, false)

	return container
end

return ClassSelectionScreen
