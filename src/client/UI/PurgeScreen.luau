--!strict
--[[
	PurgeScreen.luau
	UI modal for the Purge Shrine: lets players sacrifice one of their held tomes
	or relics to the crimson flames.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local TomeData = require(Shared:WaitForChild("TomeData"))
local TomeIcons = require(script.Parent:WaitForChild("TomeIcons"))

local player = Players.LocalPlayer

local PurgeScreen = {}

local CRIMSON = Color3.fromRGB(220, 60, 80)
local CRIMSON_DARK = Color3.fromRGB(120, 20, 35)
local FLAME_ORANGE = Color3.fromRGB(255, 120, 40)
local GOLD = Color3.fromRGB(255, 215, 120)
local PLAQUE = Color3.fromRGB(24, 18, 22)
local PLAQUE_HOVER = Color3.fromRGB(44, 28, 34)
local PARCHMENT = Color3.fromRGB(239, 213, 170)
local MUTED = Color3.fromRGB(160, 140, 145)
local INK = Color3.fromRGB(20, 12, 14)
local FONT = Enum.Font.Antique

local gui: ScreenGui? = nil
local rootGroup: CanvasGroup? = nil
local currentRoomId: number? = nil
local isVisible = false

local function setCursorState(active: boolean)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local found = pg and pg:FindFirstChild("AimReticleGui")
	local reticle = if found and found:IsA("ScreenGui") then found else nil
	if active then
		UserInputService.MouseIconEnabled = true
		if reticle then reticle.Enabled = false end
	elseif reticle then
		reticle.Enabled = true
		UserInputService.MouseIconEnabled = false
	end
end

local function close()
	if not isVisible or not rootGroup then return end
	isVisible = false
	setCursorState(false)
	local tween = TweenService:Create(rootGroup, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		GroupTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not isVisible and gui then
			gui.Enabled = false
		end
	end)
end

local function buildCard(parent: Instance, item: { id: string, count: number, name: string, description: string, category: string }, onSelect: () -> ()): Frame
	local card = Instance.new("Frame")
	card.Name = `Card_{item.id}`
	card.Size = UDim2.new(1, -16, 0, 84)
	card.BackgroundColor3 = PLAQUE
	card.BorderSizePixel = 0
	card.Parent = parent

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(70, 30, 40)
	stroke.Thickness = 1.5
	stroke.Parent = card

	-- Icon container
	local iconHolder = Instance.new("Frame")
	iconHolder.Name = "IconHolder"
	iconHolder.Size = UDim2.fromOffset(56, 56)
	iconHolder.Position = UDim2.new(0, 14, 0.5, -28)
	iconHolder.BackgroundTransparency = 1
	iconHolder.Parent = card

	TomeIcons.Make(iconHolder, item.id, item.count, 56)

	-- Title and Badges
	local title = Instance.new("TextLabel")
	title.Name = "TomeName"
	title.Size = UDim2.new(0.55, 0, 0, 22)
	title.Position = UDim2.new(0, 82, 0, 12)
	title.BackgroundTransparency = 1
	title.Font = FONT
	title.TextSize = 20
	title.TextColor3 = GOLD
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Text = item.name
	title.Parent = card

	local catBadge = Instance.new("TextLabel")
	catBadge.Name = "Category"
	catBadge.Size = UDim2.fromOffset(64, 18)
	catBadge.Position = UDim2.new(0, 82, 0, 34)
	catBadge.BackgroundColor3 = if item.category == "Relic" then Color3.fromRGB(80, 40, 120) else CRIMSON_DARK
	catBadge.BorderSizePixel = 0
	catBadge.Font = Enum.Font.GothamBold
	catBadge.TextSize = 10
	catBadge.TextColor3 = PARCHMENT
	catBadge.Text = string.upper(item.category or "TOME")
	catBadge.Parent = card

	local catCorner = Instance.new("UICorner")
	catCorner.CornerRadius = UDim.new(0, 4)
	catCorner.Parent = catBadge

	-- Description
	local desc = Instance.new("TextLabel")
	desc.Name = "Description"
	desc.Size = UDim2.new(0.5, 0, 0, 26)
	desc.Position = UDim2.new(0, 154, 0, 32)
	desc.BackgroundTransparency = 1
	desc.Font = Enum.Font.GothamMedium
	desc.TextSize = 12
	desc.TextColor3 = MUTED
	desc.TextWrapped = true
	desc.TextTruncate = Enum.TextTruncate.AtEnd
	desc.TextXAlignment = Enum.TextXAlignment.Left
	desc.Text = item.description or ""
	desc.Parent = card

	-- Sacrifice Button
	local btn = Instance.new("TextButton")
	btn.Name = "SacrificeButton"
	btn.Size = UDim2.fromOffset(130, 44)
	btn.AnchorPoint = Vector2.new(1, 0.5)
	btn.Position = UDim2.new(1, -16, 0.5, 0)
	btn.BackgroundColor3 = CRIMSON_DARK
	btn.BorderSizePixel = 0
	btn.Font = FONT
	btn.TextSize = 18
	btn.TextColor3 = PARCHMENT
	btn.Text = "SACRIFICE"
	btn.AutoButtonColor = false
	btn.Parent = card

	local btnCorner = Instance.new("UICorner")
	btnCorner.CornerRadius = UDim.new(0, 6)
	btnCorner.Parent = btn

	local btnStroke = Instance.new("UIStroke")
	btnStroke.Color = CRIMSON
	btnStroke.Thickness = 1.5
	btnStroke.Parent = btn

	-- Hover Tweens
	btn.MouseEnter:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = CRIMSON, TextColor3 = Color3.new(1, 1, 1) }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Color = FLAME_ORANGE }):Play()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = PLAQUE_HOVER }):Play()
	end)

	btn.MouseLeave:Connect(function()
		TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundColor3 = CRIMSON_DARK, TextColor3 = PARCHMENT }):Play()
		TweenService:Create(stroke, TweenInfo.new(0.15), { Color = Color3.fromRGB(70, 30, 40) }):Play()
		TweenService:Create(card, TweenInfo.new(0.15), { BackgroundColor3 = PLAQUE }):Play()
	end)

	btn.MouseButton1Click:Connect(onSelect)

	return card
end

local function showOffer(roomId: number, tomes: { any })
	currentRoomId = roomId
	if not gui then
		local pg = player:WaitForChild("PlayerGui") :: PlayerGui
		gui = Instance.new("ScreenGui")
		gui.Name = "PurgeScreenGui"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 30
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = pg

		rootGroup = Instance.new("CanvasGroup")
		rootGroup.Name = "RootGroup"
		rootGroup.Size = UDim2.fromScale(1, 1)
		rootGroup.BackgroundTransparency = 1
		rootGroup.GroupTransparency = 1
		rootGroup.Parent = gui
	end

	local rg = rootGroup :: CanvasGroup
	rg:ClearAllChildren()

	-- Dark Backing Backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 6, 8)
	backdrop.BackgroundTransparency = 0.45
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = rg
	backdrop.MouseButton1Click:Connect(close)

	-- Center Modal Window
	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.Size = UDim2.fromOffset(680, 520)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.BackgroundColor3 = Color3.fromRGB(18, 14, 16)
	modal.BorderSizePixel = 0
	modal.Parent = rg

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, 12)
	modalCorner.Parent = modal

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = CRIMSON
	modalStroke.Thickness = 2
	modalStroke.Parent = modal

	-- Top Crimson Fire Glow Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 4)
	topBar.BackgroundColor3 = FLAME_ORANGE
	topBar.BorderSizePixel = 0
	topBar.Parent = modal

	-- Header Titles
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -80, 0, 36)
	titleLabel.Position = UDim2.new(0, 40, 0, 20)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = FONT
	titleLabel.TextSize = 32
	titleLabel.TextColor3 = FLAME_ORANGE
	titleLabel.TextStrokeColor3 = INK
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.Text = "PURGE SHRINE"
	titleLabel.Parent = modal

	local subLabel = Instance.new("TextLabel")
	subLabel.Name = "SubTitle"
	subLabel.Size = UDim2.new(1, -80, 0, 20)
	subLabel.Position = UDim2.new(0, 40, 0, 56)
	subLabel.BackgroundTransparency = 1
	subLabel.Font = Enum.Font.GothamMedium
	subLabel.TextSize = 13
	subLabel.TextColor3 = PARCHMENT
	subLabel.Text = "Choose one of your held tomes to sacrifice to the embers (removes 1 stack)."
	subLabel.Parent = modal

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(36, 36)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -16, 0, 16)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font = FONT
	closeBtn.TextSize = 24
	closeBtn.TextColor3 = MUTED
	closeBtn.Text = "✕"
	closeBtn.Parent = modal

	closeBtn.MouseEnter:Connect(function() closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100) end)
	closeBtn.MouseLeave:Connect(function() closeBtn.TextColor3 = MUTED end)
	closeBtn.MouseButton1Click:Connect(close)

	-- List of Tomes
	local scroll = Instance.new("ScrollingFrame")
	scroll.Name = "TomeList"
	scroll.Size = UDim2.new(1, -40, 1, -150)
	scroll.Position = UDim2.new(0, 20, 0, 88)
	scroll.BackgroundTransparency = 1
	scroll.BorderSizePixel = 0
	scroll.ScrollBarThickness = 6
	scroll.ScrollBarImageColor3 = CRIMSON
	scroll.CanvasSize = UDim2.fromScale(0, 0)
	scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	scroll.Parent = modal

	local listLayout = Instance.new("UIListLayout")
	listLayout.Padding = UDim.new(0, 10)
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Parent = scroll

	for i, item in ipairs(tomes) do
		local card = buildCard(scroll, item, function()
			close()
			Network.GetRemoteEvent(Network.Remotes.DiscardTome):FireServer({
				tomeId = item.id,
				roomId = currentRoomId,
			})
		end)
		card.LayoutOrder = i
	end

	-- Bottom Footer / Cancel Button
	local cancelBtn = Instance.new("TextButton")
	cancelBtn.Name = "CancelButton"
	cancelBtn.Size = UDim2.fromOffset(180, 36)
	cancelBtn.AnchorPoint = Vector2.new(0.5, 1)
	cancelBtn.Position = UDim2.new(0.5, 0, 1, -16)
	cancelBtn.BackgroundColor3 = Color3.fromRGB(32, 24, 28)
	cancelBtn.BorderSizePixel = 0
	cancelBtn.Font = FONT
	cancelBtn.TextSize = 16
	cancelBtn.TextColor3 = PARCHMENT
	cancelBtn.Text = "LEAVE SHRINE"
	cancelBtn.Parent = modal

	local cCorner = Instance.new("UICorner")
	cCorner.CornerRadius = UDim.new(0, 6)
	cCorner.Parent = cancelBtn

	local cStroke = Instance.new("UIStroke")
	cStroke.Color = Color3.fromRGB(60, 40, 48)
	cStroke.Thickness = 1
	cStroke.Parent = cancelBtn

	cancelBtn.MouseEnter:Connect(function()
		cancelBtn.BackgroundColor3 = Color3.fromRGB(50, 32, 38)
		cancelBtn.TextColor3 = Color3.new(1, 1, 1)
	end)
	cancelBtn.MouseLeave:Connect(function()
		cancelBtn.BackgroundColor3 = Color3.fromRGB(32, 24, 28)
		cancelBtn.TextColor3 = PARCHMENT
	end)
	cancelBtn.MouseButton1Click:Connect(close)

	-- Open Animation
	if gui then gui.Enabled = true end
	isVisible = true
	setCursorState(true)
	TweenService:Create(rg, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	}):Play()
end

function PurgeScreen.Init()
	Network.GetRemoteEvent(Network.Remotes.DiscardTomeOffer).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.tomes) == "table" then
			showOffer(payload.roomId or 0, payload.tomes)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if isVisible and input.KeyCode == Enum.KeyCode.Escape then
			close()
		end
	end)
end

return PurgeScreen
