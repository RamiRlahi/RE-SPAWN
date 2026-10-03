--!strict
-- The title menu, after the RE:SPAWN key art: the logo top-left, a thin
-- ornamented rail down the left edge, and quiet entries (MenuEntry) that sit at
-- ~65% opacity and light up gold on hover. It fades in as the last beat of the
-- backdrop's opening sequence (MenuBackdrop.OnRevealed).

local TweenService = game:GetService("TweenService")

local MenuStyle = require(script.Parent:WaitForChild("MenuStyle"))
local MenuEntry = require(script.Parent:WaitForChild("MenuEntry"))

local MenuBackdrop: any = nil
pcall(function()
	MenuBackdrop = require(script.Parent.Parent:WaitForChild("MenuBackdrop", 5) :: any)
end)

export type TitleScreenCallbacks = {
	onStartGame: () -> (),
	onOpenSettings: () -> (),
	onOpenKeybinds: (() -> ())?,
	onOpenCredits: (() -> ())?,
	onQuit: (() -> ())?,
}

local TitleScreen = {}

local LOGO_IMAGE = "rbxassetid://74919387892039"
local BRASS = MenuEntry.Colors.Brass
local BRASS_LIGHT = MenuEntry.Colors.BrassLight
local BOLD = MenuEntry.Bold
local shape = MenuEntry.Shape

local function group(parent: Instance, name: string): CanvasGroup
	local g = Instance.new("CanvasGroup")
	g.Name = name
	g.BackgroundTransparency = 1
	g.GroupTransparency = 1 -- faded in by the opening sequence
	g.Parent = parent
	return g
end

-- The thin ornamented rail down the left screen edge (also used by the
-- campfire screen).
function TitleScreen.Rail(parent: Instance): Frame
	local edge = Instance.new("Frame")
	edge.Position = UDim2.new(0, 22, 0, 30)
	edge.Size = UDim2.new(0, 1, 1, -60)
	edge.BackgroundColor3 = BRASS
	edge.BackgroundTransparency = 0.3
	edge.BorderSizePixel = 0
	edge.Parent = parent
	for _, y in ipairs({ 0, 0.25, 0.5, 0.75, 1 }) do
		local d = shape(edge, Vector2.new(7, 7), UDim2.fromScale(0.5, y), 45)
		local s = d:FindFirstChildOfClass("UIStroke")
		if s then s.Color = BRASS_LIGHT end
		shape(edge, Vector2.new(2, 2), UDim2.fromScale(0.5, y), 45, true).BackgroundColor3 = BRASS_LIGHT
	end
	return edge
end

function TitleScreen.Create(parent: GuiObject, callbacks: TitleScreenCallbacks): CanvasGroup
	local container = Instance.new("CanvasGroup")
	container.Name = "TitleScreen"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.Parent = parent

	local rail = group(container, "EdgeRail")
	rail.Size = UDim2.new(0, 44, 1, 0)
	TitleScreen.Rail(rail)

	local menu = Instance.new("Frame")
	menu.Name = "TitleMenu"
	menu.AnchorPoint = Vector2.new(0, 0.5)
	menu.Position = UDim2.new(0.035, 0, 0.5, 0)
	menu.Size = UDim2.new(0.3, 0, 0, 640)
	menu.BackgroundTransparency = 1
	menu.Parent = container
	MenuEntry.FitHeight(menu, 640)

	-- Logo, tagline and rule.
	local head = group(menu, "Head")
	head.Size = UDim2.new(1, 0, 0, 200)
	local logo = Instance.new("ImageLabel")
	logo.Name = "RespawnLogo"
	logo.Size = UDim2.new(1, 0, 0, 154)
	logo.BackgroundTransparency = 1
	logo.Image = LOGO_IMAGE
	logo.ScaleType = Enum.ScaleType.Fit
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 2.4
	ar.Parent = logo
	logo.Parent = head

	local tagline = Instance.new("TextLabel")
	tagline.Size = UDim2.new(1, 0, 0, 24)
	tagline.Position = UDim2.new(0, 0, 0, 158)
	tagline.BackgroundTransparency = 1
	tagline.Text = "RISE.  FALL.  RETURN STRONGER."
	tagline.FontFace = BOLD
	tagline.TextSize = 16
	tagline.TextStrokeTransparency = 0.5
	tagline.TextColor3 = BRASS_LIGHT
	tagline.TextTransparency = 0.15
	tagline.TextXAlignment = Enum.TextXAlignment.Left
	tagline.Parent = head

	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.Position = UDim2.new(0, 0, 0, 190)
	rule.BackgroundColor3 = BRASS
	rule.BorderSizePixel = 0
	rule.Parent = head
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	rg.Parent = rule
	MenuStyle.Ornament(head, UDim2.new(0, 6, 0, 190), Vector2.new(0.5, 0.5), 0)

	-- The entries.
	local list = group(menu, "Entries")
	list.Position = UDim2.new(0, 0, 0, 214)
	list.Size = UDim2.new(1, 0, 0, 420)
	local options = Instance.new("Frame")
	options.Name = "MenuOptions"
	options.Size = UDim2.new(1, 0, 0, 330)
	options.BackgroundTransparency = 1
	options.Parent = list
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = options

	local function none() end
	MenuEntry.Button(options, "PLAY", "play", 1, callbacks.onStartGame)
	MenuEntry.Button(options, "SETTINGS", "settings", 2, callbacks.onOpenSettings)
	MenuEntry.Button(options, "KEYBINDS", "keybinds", 3, callbacks.onOpenKeybinds or callbacks.onOpenSettings)
	MenuEntry.Button(options, "CREDITS", "credits", 4, callbacks.onOpenCredits or none)
	MenuEntry.Button(options, "QUIT", "quit", 5, callbacks.onQuit or none)

	local version = Instance.new("TextLabel")
	version.Size = UDim2.new(1, 0, 0, 20)
	version.Position = UDim2.new(0, 14, 0, 360)
	version.BackgroundTransparency = 1
	version.Text = "VERSION 0.1  •  THE AWAKENING"
	version.FontFace = BOLD
	version.TextSize = 11
	version.TextColor3 = Color3.fromRGB(190, 160, 120)
	version.TextTransparency = 0.4
	version.TextXAlignment = Enum.TextXAlignment.Left
	version.Parent = list

	-- Opening sequence (timed from the backdrop's reveal, as the loading
	-- screen fades over 1s): the logo at 1.1s, the menu and rail at 1.4s.
	local shown = false
	local function reveal(elapsed: number)
		if shown then return end
		shown = true
		task.delay(math.max(0, 1.1 - elapsed), function()
			head.Position = UDim2.fromOffset(-14, 0)
			TweenService:Create(head, TweenInfo.new(0.9, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				GroupTransparency = 0, Position = UDim2.fromOffset(0, 0),
			}):Play()
		end)
		task.delay(math.max(0, 1.4 - elapsed), function()
			list.Position = UDim2.new(0, -10, 0, 214)
			TweenService:Create(list, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				GroupTransparency = 0, Position = UDim2.new(0, 0, 0, 214),
			}):Play()
			TweenService:Create(rail, TweenInfo.new(1.2), { GroupTransparency = 0 }):Play()
		end)
	end
	if MenuBackdrop and MenuBackdrop.OnRevealed then
		MenuBackdrop.OnRevealed(reveal)
	else
		reveal(99)
	end
	-- Never leave the menu hidden if the backdrop didn't build.
	task.delay(15, function() reveal(99) end)

	return container
end

return TitleScreen
