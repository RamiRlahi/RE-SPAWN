local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))

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

	-- Dark Background & Vignette
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = UITheme.Colors.BackgroundOverlay
	bg.BackgroundTransparency = 0.3
	bg.BorderSizePixel = 0
	bg.Parent = container

	-- Top Header Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 70)
	topBar.BackgroundTransparency = 1
	topBar.Parent = container

	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.Size = UDim2.new(0, 150, 0, 38)
	backBtn.Position = UDim2.new(0, 24, 0.5, -19)
	backBtn.BackgroundColor3 = UITheme.Colors.Surface
	backBtn.AutoButtonColor = false
	backBtn.Text = "← BACK TO TITLE"
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
	headerTitle.Size = UDim2.new(0, 400, 1, 0)
	headerTitle.AnchorPoint = Vector2.new(0.5, 0.5)
	headerTitle.Position = UDim2.new(0.5, 0, 0.5, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "CHOOSE YOUR CLASS"
	headerTitle.TextColor3 = UITheme.Colors.GoldLight
	headerTitle.Font = UITheme.Fonts.Header
	headerTitle.TextSize = 24
	headerTitle.Parent = topBar

	-- Main Layout (Split: Left Grid of 8 Cards, Right Detail Panel)
	local mainSplit = Instance.new("Frame")
	mainSplit.Name = "MainSplit"
	mainSplit.Size = UDim2.new(1, -48, 1, -90)
	mainSplit.Position = UDim2.new(0, 24, 0, 75)
	mainSplit.BackgroundTransparency = 1
	mainSplit.Parent = container

	-- Left: 8 Cards Grid
	local leftCardList = Instance.new("ScrollingFrame")
	leftCardList.Name = "ClassGrid"
	leftCardList.Size = UDim2.new(0.48, -10, 1, 0)
	leftCardList.BackgroundTransparency = 1
	leftCardList.ScrollBarThickness = 4
	leftCardList.ScrollBarImageColor3 = UITheme.Colors.Gold
	leftCardList.CanvasSize = UDim2.new(0, 0, 0, 0)
	leftCardList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leftCardList.Parent = mainSplit

	local gridLayout = Instance.new("UIGridLayout")
	gridLayout.CellSize = UDim2.new(0.5, -6, 0, 100)
	gridLayout.CellPadding = UDim2.new(0, 10, 0, 10)
	gridLayout.SortOrder = Enum.SortOrder.LayoutOrder
	gridLayout.Parent = leftCardList

	-- Right: Details Inspection Panel
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "DetailsPanel"
	rightPanel.Size = UDim2.new(0.52, -10, 1, 0)
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.Position = UDim2.new(1, 0, 0, 0)
	rightPanel.BackgroundColor3 = UITheme.Colors.Surface
	rightPanel.Parent = mainSplit

	UITheme.AddCorner(rightPanel, 10)
	local rightStroke = UITheme.AddStroke(rightPanel, UITheme.Colors.Border, 1.5, 0.3)

	-- Inside Right Panel: Details Container
	local detailsScroll = Instance.new("ScrollingFrame")
	detailsScroll.Name = "DetailsScroll"
	detailsScroll.Size = UDim2.new(1, -24, 1, -84)
	detailsScroll.Position = UDim2.new(0, 12, 0, 12)
	detailsScroll.BackgroundTransparency = 1
	detailsScroll.ScrollBarThickness = 4
	detailsScroll.ScrollBarImageColor3 = UITheme.Colors.Gold
	detailsScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	detailsScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	detailsScroll.Parent = rightPanel

	local detailsLayout = Instance.new("UIListLayout")
	detailsLayout.FillDirection = Enum.FillDirection.Vertical
	detailsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	detailsLayout.Padding = UDim.new(0, 12)
	detailsLayout.Parent = detailsScroll

	-- 1. Class Header Info
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "ClassName"
	nameLabel.Size = UDim2.new(1, 0, 0, 32)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = UITheme.Fonts.Header
	nameLabel.TextSize = 26
	nameLabel.TextColor3 = UITheme.Colors.GoldLight
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.LayoutOrder = 1
	nameLabel.Parent = detailsScroll

	local titleRoleRow = Instance.new("Frame")
	titleRoleRow.Name = "TitleRoleRow"
	titleRoleRow.Size = UDim2.new(1, 0, 0, 24)
	titleRoleRow.BackgroundTransparency = 1
	titleRoleRow.LayoutOrder = 2
	titleRoleRow.Parent = detailsScroll

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(0.65, 0, 1, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = UITheme.Fonts.Body
	subtitleLabel.TextSize = 14
	subtitleLabel.TextColor3 = UITheme.Colors.TextSecondary
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.Parent = titleRoleRow

	local roleBadge = Instance.new("TextLabel")
	roleBadge.Name = "RoleBadge"
	roleBadge.Size = UDim2.new(0.35, 0, 1, 0)
	roleBadge.AnchorPoint = Vector2.new(1, 0)
	roleBadge.Position = UDim2.new(1, 0, 0, 0)
	roleBadge.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	roleBadge.Font = UITheme.Fonts.Tag
	roleBadge.TextSize = 11
	roleBadge.TextColor3 = UITheme.Colors.GoldLight
	roleBadge.Parent = titleRoleRow
	UITheme.AddCorner(roleBadge, 4)

	-- 2. Lore / Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(1, 0, 0, 0)
	descLabel.AutomaticSize = Enum.AutomaticSize.Y
	descLabel.BackgroundTransparency = 1
	descLabel.Font = UITheme.Fonts.Sub
	descLabel.TextSize = 13
	descLabel.TextColor3 = UITheme.Colors.TextPrimary
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.LayoutOrder = 3
	descLabel.Parent = detailsScroll

	-- 3. Stats Section
	local statsBox = Instance.new("Frame")
	statsBox.Name = "StatsBox"
	statsBox.Size = UDim2.new(1, 0, 0, 80)
	statsBox.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	statsBox.LayoutOrder = 4
	statsBox.Parent = detailsScroll
	UITheme.AddCorner(statsBox, 6)
	UITheme.AddPadding(statsBox, 8, 8, 12, 12)

	local statsGrid = Instance.new("UIGridLayout")
	statsGrid.CellSize = UDim2.new(0.5, -6, 0, 28)
	statsGrid.CellPadding = UDim2.new(0, 10, 0, 6)
	statsGrid.Parent = statsBox

	local statBars: { [string]: { Frame } } = {}
	local statKeys = { "offense", "defense", "agility", "difficulty" }

	for _, key in ipairs(statKeys) do
		local statRow = Instance.new("Frame")
		statRow.Name = "Stat_" .. key
		statRow.BackgroundTransparency = 1
		statRow.Parent = statsBox

		local sTitle = Instance.new("TextLabel")
		sTitle.Size = UDim2.new(0.4, 0, 1, 0)
		sTitle.BackgroundTransparency = 1
		sTitle.Text = key:upper()
		sTitle.TextColor3 = UITheme.Colors.TextSecondary
		sTitle.Font = UITheme.Fonts.Tag
		sTitle.TextSize = 11
		sTitle.TextXAlignment = Enum.TextXAlignment.Left
		sTitle.Parent = statRow

		local barRow = Instance.new("Frame")
		barRow.Size = UDim2.new(0.6, 0, 0, 10)
		barRow.AnchorPoint = Vector2.new(1, 0.5)
		barRow.Position = UDim2.new(1, 0, 0.5, 0)
		barRow.BackgroundTransparency = 1
		barRow.Parent = statRow

		local barLayout = Instance.new("UIListLayout")
		barLayout.FillDirection = Enum.FillDirection.Horizontal
		barLayout.Padding = UDim.new(0, 3)
		barLayout.Parent = barRow

		statBars[key] = {}
		for b = 1, 5 do
			local pip = Instance.new("Frame")
			pip.Name = "Pip_" .. b
			pip.Size = UDim2.new(0.2, -3, 1, 0)
			pip.BackgroundColor3 = UITheme.Colors.SurfaceSelected
			pip.BorderSizePixel = 0
			pip.Parent = barRow
			UITheme.AddCorner(pip, 2)
			table.insert(statBars[key], pip)
		end
	end

	-- 4. Abilities Section Header
	local abilitySectionHeader = Instance.new("TextLabel")
	abilitySectionHeader.Name = "AbilitiesHeader"
	abilitySectionHeader.Size = UDim2.new(1, 0, 0, 20)
	abilitySectionHeader.BackgroundTransparency = 1
	abilitySectionHeader.Text = "CLASS ABILITIES"
	abilitySectionHeader.TextColor3 = UITheme.Colors.GoldLight
	abilitySectionHeader.Font = UITheme.Fonts.Header
	abilitySectionHeader.TextSize = 14
	abilitySectionHeader.TextXAlignment = Enum.TextXAlignment.Left
	abilitySectionHeader.LayoutOrder = 5
	abilitySectionHeader.Parent = detailsScroll

	-- Abilities List Container
	local abilitiesContainer = Instance.new("Frame")
	abilitiesContainer.Name = "AbilitiesContainer"
	abilitiesContainer.Size = UDim2.new(1, 0, 0, 0)
	abilitiesContainer.AutomaticSize = Enum.AutomaticSize.Y
	abilitiesContainer.BackgroundTransparency = 1
	abilitiesContainer.LayoutOrder = 6
	abilitiesContainer.Parent = detailsScroll

	local abilitiesListLayout = Instance.new("UIListLayout")
	abilitiesListLayout.FillDirection = Enum.FillDirection.Vertical
	abilitiesListLayout.Padding = UDim.new(0, 6)
	abilitiesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilitiesListLayout.Parent = abilitiesContainer

	-- 5. Confirm Button at bottom of right panel
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmButton"
	confirmBtn.Size = UDim2.new(1, -24, 0, 48)
	confirmBtn.AnchorPoint = Vector2.new(0.5, 1)
	confirmBtn.Position = UDim2.new(0.5, 0, 1, -12)
	confirmBtn.BackgroundColor3 = UITheme.Colors.Gold
	confirmBtn.AutoButtonColor = false
	confirmBtn.Text = "CONFIRM & ENTER THE WORLD"
	confirmBtn.TextColor3 = Color3.fromRGB(20, 15, 10)
	confirmBtn.Font = UITheme.Fonts.Button
	confirmBtn.TextSize = 16
	confirmBtn.Parent = rightPanel

	UITheme.AddCorner(confirmBtn, 8)
	local confirmStroke = UITheme.AddStroke(confirmBtn, UITheme.Colors.GoldLight, 2, 0)
	UITheme.AddGradient(confirmBtn, UITheme.Colors.GoldLight, UITheme.Colors.Gold, 90)

	-- State
	local selectedClassId = "brawler"
	local cardButtons: { [string]: TextButton } = {}
	local cardStrokes: { [string]: UIStroke } = {}

	local function renderSelectedClass(classId: string)
		local info = ClassData.GetClass(classId)
		if not info then return end

		nameLabel.Text = info.name:upper()
		nameLabel.TextColor3 = info.accentColor
		subtitleLabel.Text = info.title
		roleBadge.Text = `[{info.role:upper()}]`
		roleBadge.TextColor3 = info.accentColor
		descLabel.Text = info.description

		-- Update Stat Pips
		for _, key in ipairs(statKeys) do
			local val = (info.stats :: any)[key] or 1
			local pips = statBars[key]
			if pips then
				for idx, pip in ipairs(pips) do
					local active = idx <= val
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
			abCard.Size = UDim2.new(1, 0, 0, 52)
			abCard.BackgroundColor3 = UITheme.Colors.SurfaceAlt
			abCard.LayoutOrder = i
			abCard.Parent = abilitiesContainer

			UITheme.AddCorner(abCard, 6)
			UITheme.AddStroke(abCard, UITheme.Colors.Border, 1, 0.6)

			local abTag = Instance.new("TextLabel")
			abTag.Name = "Tag"
			abTag.Size = UDim2.new(0, 100, 0, 18)
			abTag.Position = UDim2.new(0, 10, 0, 6)
			abTag.BackgroundColor3 = UITheme.Colors.Surface
			abTag.Font = UITheme.Fonts.Tag
			abTag.TextSize = 10
			abTag.TextColor3 = info.accentColor
			abTag.Text = ab.tag:upper()
			abTag.Parent = abCard
			UITheme.AddCorner(abTag, 3)

			local abName = Instance.new("TextLabel")
			abName.Name = "Name"
			abName.Size = UDim2.new(1, -125, 0, 18)
			abName.Position = UDim2.new(0, 118, 0, 6)
			abName.BackgroundTransparency = 1
			abName.Font = UITheme.Fonts.Header
			abName.TextSize = 13
			abName.TextColor3 = UITheme.Colors.TextPrimary
			abName.TextXAlignment = Enum.TextXAlignment.Left
			abName.Text = ab.name
			abName.Parent = abCard

			local abDesc = Instance.new("TextLabel")
			abDesc.Name = "Desc"
			abDesc.Size = UDim2.new(1, -20, 0, 22)
			abDesc.Position = UDim2.new(0, 10, 0, 26)
			abDesc.BackgroundTransparency = 1
			abDesc.Font = UITheme.Fonts.Sub
			abDesc.TextSize = 11
			abDesc.TextColor3 = UITheme.Colors.TextMuted
			abDesc.TextXAlignment = Enum.TextXAlignment.Left
			abDesc.Text = ab.description
			abDesc.Parent = abCard
		end

		-- Update Card selection borders
		for cId, btn in pairs(cardButtons) do
			local isSelected = (cId == classId)
			local stroke = cardStrokes[cId]
			local cInfo = ClassData.GetClass(cId)
			if stroke and cInfo then
				stroke.Color = isSelected and cInfo.accentColor or UITheme.Colors.Border
				stroke.Thickness = isSelected and 2 or 1
				stroke.Transparency = isSelected and 0 or 0.5
			end
			btn.BackgroundColor3 = isSelected and UITheme.Colors.SurfaceSelected or UITheme.Colors.Surface
		end
	end

	-- Populate 8 Class Cards
	for i, classId in ipairs(ClassData.Order) do
		local cInfo = ClassData.GetClass(classId)
		if not cInfo then continue end

		local card = Instance.new("TextButton")
		card.Name = "ClassCard_" .. classId
		card.Size = UDim2.new(1, 0, 1, 0)
		card.BackgroundColor3 = UITheme.Colors.Surface
		card.AutoButtonColor = false
		card.Text = ""
		card.LayoutOrder = i
		card.Parent = leftCardList

		UITheme.AddCorner(card, 8)
		local stroke = UITheme.AddStroke(card, UITheme.Colors.Border, 1, 0.5)
		cardStrokes[classId] = stroke
		cardButtons[classId] = card

		-- Colored Left Accent Indicator Strip
		local indicator = Instance.new("Frame")
		indicator.Name = "AccentStrip"
		indicator.Size = UDim2.new(0, 4, 1, -16)
		indicator.Position = UDim2.new(0, 8, 0.5, -((100 - 16) / 2))
		indicator.BackgroundColor3 = cInfo.accentColor
		indicator.BorderSizePixel = 0
		indicator.Parent = card
		UITheme.AddCorner(indicator, 2)

		-- Class Title & Role inside Card
		local cardName = Instance.new("TextLabel")
		cardName.Name = "CardName"
		cardName.Size = UDim2.new(1, -28, 0, 24)
		cardName.Position = UDim2.new(0, 20, 0, 14)
		cardName.BackgroundTransparency = 1
		cardName.Text = cInfo.name
		cardName.TextColor3 = UITheme.Colors.TextPrimary
		cardName.Font = UITheme.Fonts.Header
		cardName.TextSize = 16
		cardName.TextXAlignment = Enum.TextXAlignment.Left
		cardName.Parent = card

		local cardRole = Instance.new("TextLabel")
		cardRole.Name = "CardRole"
		cardRole.Size = UDim2.new(1, -28, 0, 18)
		cardRole.Position = UDim2.new(0, 20, 0, 40)
		cardRole.BackgroundTransparency = 1
		cardRole.Text = cInfo.role
		cardRole.TextColor3 = cInfo.accentColor
		cardRole.Font = UITheme.Fonts.Tag
		cardRole.TextSize = 11
		cardRole.TextXAlignment = Enum.TextXAlignment.Left
		cardRole.Parent = card

		local cardSubtitle = Instance.new("TextLabel")
		cardSubtitle.Name = "CardSubtitle"
		cardSubtitle.Size = UDim2.new(1, -28, 0, 16)
		cardSubtitle.Position = UDim2.new(0, 20, 0, 62)
		cardSubtitle.BackgroundTransparency = 1
		cardSubtitle.Text = cInfo.title
		cardSubtitle.TextColor3 = UITheme.Colors.TextMuted
		cardSubtitle.Font = UITheme.Fonts.Sub
		cardSubtitle.TextSize = 10
		cardSubtitle.TextXAlignment = Enum.TextXAlignment.Left
		cardSubtitle.Parent = card

		card.MouseEnter:Connect(function()
			SoundManager.PlayHover()
			if selectedClassId ~= classId then
				TweenService:Create(card, UITheme.Tweens.Fast, {
					BackgroundColor3 = UITheme.Colors.SurfaceHover,
				}):Play()
			end
		end)

		card.MouseLeave:Connect(function()
			if selectedClassId ~= classId then
				TweenService:Create(card, UITheme.Tweens.Fast, {
					BackgroundColor3 = UITheme.Colors.Surface,
				}):Play()
			end
		end)

		card.MouseButton1Click:Connect(function()
			if selectedClassId ~= classId then
				selectedClassId = classId
				SoundManager.PlaySelect()
				renderSelectedClass(classId)
			end
		end)
	end

	-- Confirm Button Interaction
	UITheme.MakeButtonInteractive(
		confirmBtn,
		confirmStroke,
		UITheme.Colors.GoldLight,
		SoundManager.PlayHover,
		function()
			SoundManager.PlayConfirm()
			callbacks.onConfirmClass(selectedClassId)
		end
	)

	-- Initial Render
	renderSelectedClass("brawler")

	return container
end

return ClassSelectionScreen
