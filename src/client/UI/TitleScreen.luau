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

function TitleScreen.Create(parent: GuiObject, callbacks: TitleScreenCallbacks): CanvasGroup
	local container = Instance.new("CanvasGroup")
	container.Name = "TitleScreen"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 0
	container.Parent = parent

	-- Cinematic Vignette Overlay
	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.new(1, 0, 1, 0)
	vignette.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	vignette.BackgroundTransparency = 0.4
	vignette.BorderSizePixel = 0
	vignette.Parent = container

	local vignetteGrad = Instance.new("UIGradient")
	vignetteGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(0.5, 0.2),
		NumberSequenceKeypoint.new(1, 0.7),
	})
	vignetteGrad.Rotation = 90
	vignetteGrad.Parent = vignette

	-- Center Content Area
	local content = Instance.new("Frame")
	content.Name = "Content"
	content.Size = UDim2.new(0, 500, 0, 480)
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.new(0.5, 0, 0.5, 0)
	content.BackgroundTransparency = 1
	content.Parent = container

	-- Title Header
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "TitleLabel"
	titleLabel.Size = UDim2.new(1, 0, 0, 70)
	titleLabel.Position = UDim2.new(0, 0, 0, 40)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "SANCTUARY"
	titleLabel.TextColor3 = UITheme.Colors.GoldLight
	titleLabel.Font = UITheme.Fonts.Title
	titleLabel.TextSize = 56
	titleLabel.TextStrokeColor3 = Color3.fromRGB(40, 25, 10)
	titleLabel.TextStrokeTransparency = 0.2
	titleLabel.Parent = content

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "SubtitleLabel"
	subtitleLabel.Size = UDim2.new(1, 0, 0, 24)
	subtitleLabel.Position = UDim2.new(0, 0, 0, 110)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Text = "CHRONICLES OF ASCENSION"
	subtitleLabel.TextColor3 = UITheme.Colors.TextSecondary
	subtitleLabel.Font = UITheme.Fonts.Tag
	subtitleLabel.TextSize = 14
	subtitleLabel.TextStrokeTransparency = 0.7
	subtitleLabel.Parent = content

	-- Decorative Divider
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(0, 240, 0, 2)
	divider.AnchorPoint = Vector2.new(0.5, 0)
	divider.Position = UDim2.new(0.5, 0, 0, 145)
	divider.BackgroundColor3 = UITheme.Colors.Gold
	divider.BorderSizePixel = 0
	divider.Parent = content
	UITheme.AddGradient(divider, UITheme.Colors.GoldLight, UITheme.Colors.GoldDark, 0)

	-- Button Container
	local buttonList = Instance.new("Frame")
	buttonList.Name = "ButtonList"
	buttonList.Size = UDim2.new(1, 0, 0, 200)
	buttonList.Position = UDim2.new(0, 0, 0, 180)
	buttonList.BackgroundTransparency = 1
	buttonList.Parent = content

	local listLayout = Instance.new("UIListLayout")
	listLayout.FillDirection = Enum.FillDirection.Vertical
	listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	listLayout.SortOrder = Enum.SortOrder.LayoutOrder
	listLayout.Padding = UDim.new(0, 16)
	listLayout.Parent = buttonList

	-- 1. Start Game Button
	local startBtn = Instance.new("TextButton")
	startBtn.Name = "StartButton"
	startBtn.Size = UDim2.new(0, 320, 0, 56)
	startBtn.BackgroundColor3 = UITheme.Colors.Gold
	startBtn.AutoButtonColor = false
	startBtn.Text = "START GAME"
	startBtn.TextColor3 = Color3.fromRGB(20, 15, 10)
	startBtn.Font = UITheme.Fonts.Button
	startBtn.TextSize = 20
	startBtn.LayoutOrder = 1
	startBtn.Parent = buttonList

	UITheme.AddCorner(startBtn, 8)
	local startStroke = UITheme.AddStroke(startBtn, UITheme.Colors.GoldLight, 2, 0)
	UITheme.AddGradient(startBtn, UITheme.Colors.GoldLight, UITheme.Colors.Gold, 90)

	UITheme.MakeButtonInteractive(
		startBtn,
		startStroke,
		UITheme.Colors.GoldLight,
		SoundManager.PlayHover,
		function()
			SoundManager.PlayClick()
			callbacks.onStartGame()
		end
	)

	-- 2. Settings Button
	local settingsBtn = Instance.new("TextButton")
	settingsBtn.Name = "SettingsButton"
	settingsBtn.Size = UDim2.new(0, 320, 0, 50)
	settingsBtn.BackgroundColor3 = UITheme.Colors.Surface
	settingsBtn.AutoButtonColor = false
	settingsBtn.Text = "SETTINGS & KEYBINDS"
	settingsBtn.TextColor3 = UITheme.Colors.TextPrimary
	settingsBtn.Font = UITheme.Fonts.Button
	settingsBtn.TextSize = 16
	settingsBtn.LayoutOrder = 2
	settingsBtn.Parent = buttonList

	UITheme.AddCorner(settingsBtn, 8)
	local settingsStroke = UITheme.AddStroke(settingsBtn, UITheme.Colors.Border, 1.5, 0.3)

	UITheme.MakeButtonInteractive(
		settingsBtn,
		settingsStroke,
		UITheme.Colors.Gold,
		SoundManager.PlayHover,
		function()
			SoundManager.PlayClick()
			callbacks.onOpenSettings()
		end
	)

	-- Version Tag
	local versionLabel = Instance.new("TextLabel")
	versionLabel.Name = "VersionLabel"
	versionLabel.Size = UDim2.new(0, 200, 0, 20)
	versionLabel.Position = UDim2.new(0, 20, 1, -30)
	versionLabel.BackgroundTransparency = 1
	versionLabel.Text = "v0.1.0 • Alpha Build"
	versionLabel.TextColor3 = UITheme.Colors.TextMuted
	versionLabel.Font = UITheme.Fonts.Body
	versionLabel.TextSize = 12
	versionLabel.TextXAlignment = Enum.TextXAlignment.Left
	versionLabel.Parent = container

	return container
end

return TitleScreen
