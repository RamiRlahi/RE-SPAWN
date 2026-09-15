--!strict
-- Medieval title menu inspired by a guild hall notice board: warm brass, dark wood, and stacked plaques.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))

export type TitleScreenCallbacks = {
	onStartGame: () -> (),
	onOpenSettings: () -> (),
}

local TitleScreen = {}

local LOGO_IMAGE = "rbxassetid://74919387892039"
local BRASS = Color3.fromRGB(194, 132, 52)
local BRASS_LIGHT = Color3.fromRGB(255, 213, 128)
local PLAQUE = Color3.fromRGB(37, 28, 24)
local PLAQUE_DARK = Color3.fromRGB(17, 13, 13)
local PARCHMENT = Color3.fromRGB(239, 213, 170)

local function addOrnament(parent: Instance, position: UDim2, anchorPoint: Vector2, rotation: number)
	local ornament = Instance.new("TextLabel")
	ornament.Size = UDim2.fromOffset(30, 30)
	ornament.AnchorPoint = anchorPoint
	ornament.Position = position
	ornament.BackgroundTransparency = 1
	ornament.Text = "✦"
	ornament.Font = Enum.Font.Antique
	ornament.TextSize = 26
	ornament.TextColor3 = BRASS_LIGHT
	ornament.TextStrokeColor3 = Color3.fromRGB(78, 41, 14)
	ornament.TextStrokeTransparency = 0.15
	ornament.Rotation = rotation
	ornament.ZIndex = 3
	ornament.Parent = parent
end

local function createButton(parent: Instance, label: string, order: number, onClick: () -> ())
	local button = Instance.new("TextButton")
	button.Name = label:gsub("%s+", "") .. "Button"
	button.Size = UDim2.new(1, 0, 0, 76)
	button.BackgroundColor3 = PLAQUE
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.LayoutOrder = order
	-- The left edge reads closer to the player while the right edge recedes,
	-- matching the angled wooden-menu perspective of the reference.
	button.Rotation = -4
	button.Text = ""
	button.Parent = parent

	local depthShadow = Instance.new("Frame")
	depthShadow.Name = "PlaqueDepthShadow"
	depthShadow.Size = UDim2.new(1, 2, 1, 2)
	depthShadow.Position = UDim2.fromOffset(-3, 9)
	depthShadow.BackgroundColor3 = Color3.fromRGB(8, 5, 4)
	depthShadow.BackgroundTransparency = 0.22
	depthShadow.BorderSizePixel = 0
	depthShadow.ZIndex = 0
	depthShadow.Parent = button

	local scale = Instance.new("UIScale")
	scale.Parent = button
	local outerStroke = UITheme.AddStroke(button, Color3.fromRGB(96, 58, 26), 3, 0)
	local gradient = UITheme.AddGradient(button, Color3.fromRGB(64, 47, 37), PLAQUE_DARK, 90)

	-- A narrow inner brass rail gives the button the layered, framed-plaque silhouette.
	local inset = Instance.new("Frame")
	inset.Name = "InnerBrassRail"
	inset.Size = UDim2.new(1, -18, 1, -16)
	inset.Position = UDim2.fromOffset(9, 8)
	inset.BackgroundTransparency = 1
	inset.BorderSizePixel = 0
	inset.ZIndex = 2
	inset.Parent = button
	UITheme.AddStroke(inset, BRASS, 1, 0.12)

	local lowerEdge = Instance.new("Frame")
	lowerEdge.Size = UDim2.new(1, -24, 0, 2)
	lowerEdge.Position = UDim2.new(0, 12, 1, -10)
	lowerEdge.BackgroundColor3 = Color3.fromRGB(95, 57, 27)
	lowerEdge.BorderSizePixel = 0
	lowerEdge.ZIndex = 3
	lowerEdge.Parent = button

	-- Darken the distant end very slightly so the right side appears to fall away.
	local distanceShade = Instance.new("Frame")
	distanceShade.Name = "FarEdgeShade"
	distanceShade.Size = UDim2.new(0.38, 0, 1, -12)
	distanceShade.AnchorPoint = Vector2.new(1, 0.5)
	distanceShade.Position = UDim2.new(1, -6, 0.5, 0)
	distanceShade.BackgroundColor3 = Color3.fromRGB(8, 5, 4)
	distanceShade.BackgroundTransparency = 0.72
	distanceShade.BorderSizePixel = 0
	distanceShade.ZIndex = 2
	distanceShade.Parent = button
	local distanceGradient = Instance.new("UIGradient")
	distanceGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	distanceGradient.Parent = distanceShade

	-- The small red tab makes each option read as a physical banner rather than a flat UI control.
	local ribbon = Instance.new("Frame")
	ribbon.Name = "CrimsonRibbon"
	ribbon.Size = UDim2.fromOffset(26, 86)
	ribbon.Position = UDim2.fromOffset(20, -5)
	ribbon.BackgroundColor3 = Color3.fromRGB(103, 27, 20)
	ribbon.BorderSizePixel = 0
	ribbon.Rotation = -4
	ribbon.ZIndex = 4
	ribbon.Parent = button
	UITheme.AddGradient(ribbon, Color3.fromRGB(159, 54, 35), Color3.fromRGB(64, 16, 15), 90)
	UITheme.AddStroke(ribbon, Color3.fromRGB(59, 16, 12), 1, 0.2)

	local ribbonSeal = Instance.new("TextLabel")
	ribbonSeal.Size = UDim2.fromScale(1, 0.56)
	ribbonSeal.Position = UDim2.fromScale(0, 0.12)
	ribbonSeal.BackgroundTransparency = 1
	ribbonSeal.Text = "✦"
	ribbonSeal.Font = Enum.Font.Antique
	ribbonSeal.TextSize = 21
	ribbonSeal.TextColor3 = BRASS_LIGHT
	ribbonSeal.TextStrokeColor3 = Color3.fromRGB(76, 39, 10)
	ribbonSeal.TextStrokeTransparency = 0.2
	ribbonSeal.ZIndex = 5
	ribbonSeal.Parent = ribbon

	local text = Instance.new("TextLabel")
	text.Name = "ButtonLabel"
	text.Size = UDim2.new(1, -110, 1, 0)
	text.Position = UDim2.fromOffset(76, 0)
	text.BackgroundTransparency = 1
	text.Text = label
	text.Font = Enum.Font.Antique
	text.TextSize = 24
	text.TextColor3 = PARCHMENT
	text.TextStrokeColor3 = Color3.fromRGB(28, 15, 10)
	text.TextStrokeTransparency = 0.1
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.ZIndex = 4
	text.Parent = button

	addOrnament(button, UDim2.new(1, -15, 0.5, 0), Vector2.new(0.5, 0.5), 0)

	button.MouseEnter:Connect(function()
		SoundManager.PlayHover()
		TweenService:Create(button, UITheme.Tweens.Fast, { BackgroundColor3 = Color3.fromRGB(66, 44, 28) }):Play()
		TweenService:Create(scale, UITheme.Tweens.Spring, { Scale = 1.025 }):Play()
		TweenService:Create(outerStroke, UITheme.Tweens.Fast, { Color = BRASS_LIGHT, Thickness = 3 }):Play()
		TweenService:Create(text, UITheme.Tweens.Fast, { TextColor3 = Color3.fromRGB(255, 236, 194) }):Play()
		TweenService:Create(gradient, UITheme.Tweens.Fast, { Rotation = 0 }):Play()
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, UITheme.Tweens.Fast, { BackgroundColor3 = PLAQUE }):Play()
		TweenService:Create(scale, UITheme.Tweens.Fast, { Scale = 1 }):Play()
		TweenService:Create(outerStroke, UITheme.Tweens.Fast, { Color = Color3.fromRGB(96, 58, 26), Thickness = 3 }):Play()
		TweenService:Create(text, UITheme.Tweens.Fast, { TextColor3 = PARCHMENT }):Play()
		TweenService:Create(gradient, UITheme.Tweens.Fast, { Rotation = 90 }):Play()
	end)
	button.Activated:Connect(function()
		SoundManager.PlayClick()
		TweenService:Create(scale, UITheme.Tweens.Fast, { Scale = 0.975 }):Play()
		task.delay(0.1, onClick)
	end)
end

function TitleScreen.Create(parent: GuiObject, callbacks: TitleScreenCallbacks): CanvasGroup
	local container = Instance.new("CanvasGroup")
	container.Name = "TitleScreen"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = parent

	-- The vignette anchors the menu in the middle without hiding the environment at the edges.
	local shade = Instance.new("Frame")
	shade.Name = "CinematicVignette"
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(10, 6, 5)
	shade.BackgroundTransparency = 0.25
	shade.BorderSizePixel = 0
	shade.Parent = container
	local shadeGradient = Instance.new("UIGradient")
	shadeGradient.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), Color3.fromRGB(50, 32, 23))
	shadeGradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.14),
		NumberSequenceKeypoint.new(0.5, 0.62),
		NumberSequenceKeypoint.new(1, 0.14),
	})
	shadeGradient.Parent = shade

	local menu = Instance.new("Frame")
	menu.Name = "GuildHallMenu"
	menu.AnchorPoint = Vector2.new(0, 0.5)
	menu.Position = UDim2.new(0.065, 0, 0.52, 0)
	menu.Size = UDim2.new(0.39, 0, 0, 505)
	menu.BackgroundTransparency = 1
	menu.Parent = container

	local logo = Instance.new("ImageLabel")
	logo.Name = "RespawnLogo"
	logo.Size = UDim2.new(1, 48, 0, 156)
	logo.Position = UDim2.new(0, -24, 0, 0)
	logo.BackgroundTransparency = 1
	logo.Image = LOGO_IMAGE
	logo.ScaleType = Enum.ScaleType.Fit
	logo.Visible = LOGO_IMAGE ~= ""
	logo.Parent = menu

	local title = Instance.new("TextLabel")
	title.Name = "RespawnTitleFallback"
	title.Size = UDim2.new(1, 0, 0, 82)
	title.Position = UDim2.new(0, 0, 0, 28)
	title.BackgroundTransparency = 1
	title.Text = "RE//SPAWN"
	title.Font = Enum.Font.Antique
	title.TextSize = 52
	title.TextStrokeColor3 = Color3.fromRGB(36, 8, 3)
	title.TextStrokeTransparency = 0.1
	title.TextColor3 = Color3.fromRGB(255, 184, 93)
	title.Visible = LOGO_IMAGE == ""
	title.Parent = menu

	local tagline = Instance.new("TextLabel")
	tagline.Size = UDim2.new(1, 0, 0, 24)
	tagline.Position = UDim2.new(0, 0, 0, 152)
	tagline.BackgroundTransparency = 1
	tagline.Text = "RISE.  FALL.  RETURN STRONGER."
	tagline.Font = Enum.Font.Antique
	tagline.TextSize = 16
	tagline.TextColor3 = BRASS_LIGHT
	tagline.TextXAlignment = Enum.TextXAlignment.Center
	tagline.Parent = menu

	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(0.82, 0, 0, 2)
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 186)
	rule.BackgroundColor3 = BRASS
	rule.BorderSizePixel = 0
	rule.Parent = menu
	addOrnament(menu, UDim2.new(0.5, 0, 0, 187), Vector2.new(0.5, 0.5), 0)

	local options = Instance.new("Frame")
	options.Name = "PlaqueMenuOptions"
	options.Size = UDim2.new(0.94, 0, 0, 202)
	options.AnchorPoint = Vector2.new(0.5, 0)
	options.Position = UDim2.new(0.5, 0, 0, 222)
	options.BackgroundTransparency = 1
	options.Parent = menu
	local layout = Instance.new("UIListLayout")
	-- Rotated plaques need more vertical breathing room than flat buttons.
	layout.Padding = UDim.new(0, 40)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = options

	createButton(options, "BEGIN EXPEDITION", 1, callbacks.onStartGame)
	createButton(options, "SETTINGS  /  KEYBINDS", 2, callbacks.onOpenSettings)

	local version = Instance.new("TextLabel")
	version.Size = UDim2.new(1, 0, 0, 20)
	version.Position = UDim2.new(0, 0, 1, -24)
	version.BackgroundTransparency = 1
	version.Text = "v0.1.0  •  ALPHA BUILD"
	version.Font = Enum.Font.Antique
	version.TextSize = 12
	version.TextColor3 = Color3.fromRGB(159, 121, 85)
	version.TextXAlignment = Enum.TextXAlignment.Center
	version.Parent = menu

	return container
end

return TitleScreen
