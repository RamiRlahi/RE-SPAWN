--!strict
-- Guild-hall menu style shared by the title menu and the class selection:
-- dark wood plaques framed by a brass rail, crimson ribbons, parchment text in
-- the Antique face.

local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))

local MenuStyle = {}

MenuStyle.Font = Enum.Font.Antique
MenuStyle.Colors = {
	Brass = Color3.fromRGB(194, 132, 52),
	BrassLight = Color3.fromRGB(255, 213, 128),
	BrassDark = Color3.fromRGB(96, 58, 26),
	Plaque = Color3.fromRGB(37, 28, 24),
	PlaqueHover = Color3.fromRGB(66, 44, 28),
	PlaqueDark = Color3.fromRGB(17, 13, 13),
	Parchment = Color3.fromRGB(239, 213, 170),
	ParchmentMuted = Color3.fromRGB(159, 121, 85),
	Ink = Color3.fromRGB(28, 15, 10),
	Crimson = Color3.fromRGB(103, 27, 20),
}
local C = MenuStyle.Colors

-- The ❖ ornament used on the title menu.
function MenuStyle.Ornament(parent: Instance, position: UDim2, anchorPoint: Vector2, rotation: number, size: number?): TextLabel
	local ornament = Instance.new("TextLabel")
	ornament.Size = UDim2.fromOffset(30, 30)
	ornament.AnchorPoint = anchorPoint
	ornament.Position = position
	ornament.BackgroundTransparency = 1
	ornament.Text = "❖"
	ornament.Font = MenuStyle.Font
	ornament.TextSize = size or 26
	ornament.TextColor3 = C.BrassLight
	ornament.TextStrokeColor3 = Color3.fromRGB(78, 41, 14)
	ornament.TextStrokeTransparency = 0.15
	ornament.Rotation = rotation
	ornament.ZIndex = 3
	ornament.Parent = parent
	return ornament
end

-- Parchment/brass text in the menu face.
function MenuStyle.Label(parent: Instance, text: string, size: number, color: Color3?, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.Font = MenuStyle.Font
	l.TextSize = size
	l.TextColor3 = color or C.Parchment
	l.TextStrokeColor3 = C.Ink
	l.TextStrokeTransparency = 0.25
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

-- A brass rule with a centred ornament (section divider).
function MenuStyle.Rule(parent: Instance, y: number, widthScale: number?): Frame
	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(widthScale or 0.82, 0, 0, 2)
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, y)
	rule.BackgroundColor3 = C.Brass
	rule.BorderSizePixel = 0
	rule.Parent = parent
	MenuStyle.Ornament(parent, UDim2.new(0.5, 0, 0, y + 1), Vector2.new(0.5, 0.5), 0, 18)
	return rule
end

-- Turn a Frame into a framed wood plaque (panels, cards). The inner brass rail
-- is a child Frame, so pass noRail for frames that lay out their children
-- with a UIListLayout (it would become a list item).
function MenuStyle.Plaque(frame: GuiObject, dark: boolean?, noRail: boolean?)
	frame.BackgroundColor3 = if dark then C.PlaqueDark else C.Plaque
	frame.BackgroundTransparency = if dark then 0.1 else 0.06
	frame.BorderSizePixel = 0
	UITheme.AddStroke(frame, C.BrassDark, 2, 0)
	UITheme.AddGradient(frame, Color3.fromRGB(64, 47, 37), C.PlaqueDark, 90)
	if noRail then return end
	local rail = Instance.new("Frame")
	rail.Name = "InnerBrassRail"
	rail.Size = UDim2.new(1, -10, 1, -10)
	rail.Position = UDim2.fromOffset(5, 5)
	rail.BackgroundTransparency = 1
	rail.BorderSizePixel = 0
	rail.ZIndex = frame.ZIndex
	rail.Parent = frame
	UITheme.AddStroke(rail, C.Brass, 1, if dark then 0.45 else 0.12)
end

export type ButtonOptions = {
	rotation: number?,  -- the title menu tilts its plaques -4°
	ribbon: boolean?,   -- crimson banner tab on the left
	ornament: boolean?, -- ❖ on the right
	textSize: number?,
	popOrder: number?,  -- staggered entrance pop (title menu)
}

-- Style a TextButton as a guild-hall plaque with the title menu's hover,
-- press and entrance animations. Returns the label (to change text later).
function MenuStyle.PlaqueButton(button: TextButton, label: string, opts: ButtonOptions?, onClick: () -> ()): TextLabel
	local o: ButtonOptions = opts or {}
	button.BackgroundColor3 = C.Plaque
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Rotation = o.rotation or 0
	button.Text = ""

	local depthShadow = Instance.new("Frame")
	depthShadow.Name = "PlaqueDepthShadow"
	depthShadow.Size = UDim2.new(1, 2, 1, 2)
	depthShadow.Position = UDim2.fromOffset(-2, 5)
	depthShadow.BackgroundColor3 = Color3.fromRGB(8, 5, 4)
	depthShadow.BackgroundTransparency = 0.28
	depthShadow.BorderSizePixel = 0
	depthShadow.ZIndex = 0
	depthShadow.Parent = button

	local scale = Instance.new("UIScale")
	scale.Parent = button
	local outerStroke = UITheme.AddStroke(button, C.BrassDark, 2, 0)
	local gradient = UITheme.AddGradient(button, Color3.fromRGB(64, 47, 37), C.PlaqueDark, 90)

	-- A narrow inner brass rail gives the button the layered, framed-plaque silhouette.
	local inset = Instance.new("Frame")
	inset.Name = "InnerBrassRail"
	inset.Size = UDim2.new(1, -14, 1, -12)
	inset.Position = UDim2.fromOffset(7, 6)
	inset.BackgroundTransparency = 1
	inset.BorderSizePixel = 0
	inset.ZIndex = 2
	inset.Parent = button
	UITheme.AddStroke(inset, C.Brass, 1, 0.12)

	local lowerEdge = Instance.new("Frame")
	lowerEdge.Size = UDim2.new(1, -18, 0, 1)
	lowerEdge.Position = UDim2.new(0, 9, 1, -7)
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

	local textLeft = 10
	if o.ribbon then
		-- The small red tab makes the option read as a physical banner.
		local ribbon = Instance.new("Frame")
		ribbon.Name = "CrimsonRibbon"
		ribbon.Size = UDim2.new(0, 18, 1, 6)
		ribbon.Position = UDim2.fromOffset(16, -3)
		ribbon.BackgroundColor3 = C.Crimson
		ribbon.BorderSizePixel = 0
		ribbon.Rotation = o.rotation or 0
		ribbon.ZIndex = 4
		ribbon.Parent = button
		UITheme.AddGradient(ribbon, Color3.fromRGB(159, 54, 35), Color3.fromRGB(64, 16, 15), 90)
		UITheme.AddStroke(ribbon, Color3.fromRGB(59, 16, 12), 1, 0.2)

		local ribbonSeal = Instance.new("TextLabel")
		ribbonSeal.Size = UDim2.fromScale(1, 0.56)
		ribbonSeal.Position = UDim2.fromScale(0, 0.12)
		ribbonSeal.BackgroundTransparency = 1
		ribbonSeal.Text = "❖"
		ribbonSeal.Font = MenuStyle.Font
		ribbonSeal.TextSize = 15
		ribbonSeal.TextColor3 = C.BrassLight
		ribbonSeal.TextStrokeColor3 = Color3.fromRGB(76, 39, 10)
		ribbonSeal.TextStrokeTransparency = 0.2
		ribbonSeal.ZIndex = 5
		ribbonSeal.Parent = ribbon
		textLeft = 44
	end

	local text = Instance.new("TextLabel")
	text.Name = "ButtonLabel"
	text.Size = UDim2.new(1, -(textLeft + (if o.ornament then 30 else 10)), 1, 0)
	text.Position = UDim2.fromOffset(textLeft, 0)
	text.BackgroundTransparency = 1
	text.Text = label
	text.Font = MenuStyle.Font
	text.TextSize = o.textSize or 19
	text.TextColor3 = C.Parchment
	text.TextStrokeColor3 = C.Ink
	text.TextStrokeTransparency = 0.1
	text.TextXAlignment = Enum.TextXAlignment.Center
	text.ZIndex = 4
	text.Parent = button

	local ornament = if o.ornament then MenuStyle.Ornament(button, UDim2.new(1, -15, 0.5, 0), Vector2.new(0.5, 0.5), 0) else nil

	if o.popOrder then
		-- Entrance pop, staggered per plaque, for a livelier feel.
		scale.Scale = 0.85
		task.delay(0.06 * (o.popOrder - 1) + 0.12, function()
			TweenService:Create(scale, UITheme.Tweens.Spring, { Scale = 1 }):Play()
		end)
	end

	button.MouseEnter:Connect(function()
		SoundManager.PlayHover()
		TweenService:Create(button, UITheme.Tweens.Fast, { BackgroundColor3 = C.PlaqueHover }):Play()
		TweenService:Create(scale, UITheme.Tweens.Spring, { Scale = 1.05 }):Play()
		TweenService:Create(outerStroke, UITheme.Tweens.Fast, { Color = C.BrassLight, Thickness = 2.5 }):Play()
		TweenService:Create(text, UITheme.Tweens.Fast, { TextColor3 = Color3.fromRGB(255, 236, 194) }):Play()
		TweenService:Create(gradient, UITheme.Tweens.Fast, { Rotation = 0 }):Play()
		if ornament then
			TweenService:Create(ornament, UITheme.Tweens.Spring, { Rotation = 90, TextColor3 = C.BrassLight }):Play()
		end
	end)
	button.MouseLeave:Connect(function()
		TweenService:Create(button, UITheme.Tweens.Fast, { BackgroundColor3 = C.Plaque }):Play()
		TweenService:Create(scale, UITheme.Tweens.Fast, { Scale = 1 }):Play()
		TweenService:Create(outerStroke, UITheme.Tweens.Fast, { Color = C.BrassDark, Thickness = 2 }):Play()
		TweenService:Create(text, UITheme.Tweens.Fast, { TextColor3 = C.Parchment }):Play()
		TweenService:Create(gradient, UITheme.Tweens.Fast, { Rotation = 90 }):Play()
		if ornament then
			TweenService:Create(ornament, UITheme.Tweens.Spring, { Rotation = 0 }):Play()
		end
	end)
	button.Activated:Connect(function()
		SoundManager.PlayClick()
		TweenService:Create(scale, UITheme.Tweens.Fast, { Scale = 0.975 }):Play()
		task.delay(0.1, function()
			TweenService:Create(scale, UITheme.Tweens.Fast, { Scale = 1 }):Play()
			onClick()
		end)
	end)
	return text
end

-- Plaque styling for a TextButton that keeps its own Text (callers can change
-- the text and rest colours later, e.g. live prices or a selected tab).
-- primary adds the crimson ribbon and a brighter brass frame. Hover and press
-- match PlaqueButton. Returns the outer stroke.
function MenuStyle.TextPlaque(button: TextButton, primary: boolean?, onClick: () -> ()): UIStroke
	button.AutoButtonColor = false
	button.BorderSizePixel = 0
	button.BackgroundColor3 = C.Plaque
	button.Font = MenuStyle.Font
	button.TextSize = if primary then 20 else 16
	button.TextColor3 = C.Parchment
	button.TextStrokeColor3 = C.Ink
	button.TextStrokeTransparency = 0.1
	local baseStroke = if primary then C.Brass else C.BrassDark
	local stroke = UITheme.AddStroke(button, baseStroke, 2, 0)
	UITheme.AddGradient(button, Color3.fromRGB(64, 47, 37), C.PlaqueDark, 90)

	local rail = Instance.new("Frame")
	rail.Name = "InnerBrassRail"
	rail.Size = UDim2.new(1, -12, 1, -10)
	rail.Position = UDim2.fromOffset(6, 5)
	rail.BackgroundTransparency = 1
	rail.BorderSizePixel = 0
	rail.Parent = button
	UITheme.AddStroke(rail, C.Brass, 1, if primary then 0.12 else 0.45)

	if primary then
		local ribbon = Instance.new("Frame")
		ribbon.Name = "CrimsonRibbon"
		ribbon.Size = UDim2.new(0, 14, 1, 6)
		ribbon.Position = UDim2.fromOffset(14, -3)
		ribbon.BackgroundColor3 = C.Crimson
		ribbon.BorderSizePixel = 0
		ribbon.Parent = button
		UITheme.AddGradient(ribbon, Color3.fromRGB(159, 54, 35), Color3.fromRGB(64, 16, 15), 90)
		UITheme.AddStroke(ribbon, Color3.fromRGB(59, 16, 12), 1, 0.2)
	end

	-- The wood gradient would also tint the button's own text nearly black, so
	-- the text is drawn by a child label that mirrors the button's Text,
	-- TextColor3 and TextSize (callers keep setting those on the button).
	local label = Instance.new("TextLabel")
	label.Name = "ButtonLabel"
	label.Size = UDim2.new(1, if primary then -36 else -12, 1, 0)
	label.Position = UDim2.fromOffset(if primary then 30 else 6, 0)
	label.BackgroundTransparency = 1
	label.Font = MenuStyle.Font
	label.TextStrokeColor3 = C.Ink
	label.TextStrokeTransparency = 0.1
	label.TextWrapped = true
	label.ZIndex = 4
	label.Parent = button
	local function mirror()
		label.Text = button.Text
		label.TextColor3 = button.TextColor3
		label.TextSize = button.TextSize
		label.ZIndex = button.ZIndex + 1
	end
	mirror()
	button.TextTransparency = 1
	button.TextStrokeTransparency = 1
	for _, prop in ipairs({ "Text", "TextColor3", "TextSize", "ZIndex" }) do
		button:GetPropertyChangedSignal(prop):Connect(mirror)
	end

	local scale = Instance.new("UIScale")
	scale.Parent = button
	local hovering = false
	local restBg, restText = button.BackgroundColor3, button.TextColor3
	button.MouseEnter:Connect(function()
		if hovering then return end
		hovering = true
		restBg, restText = button.BackgroundColor3, button.TextColor3
		SoundManager.PlayHover()
		button.BackgroundColor3 = C.PlaqueHover
		button.TextColor3 = Color3.fromRGB(255, 236, 194)
		stroke.Color = C.BrassLight
		TweenService:Create(scale, UITheme.Tweens.Spring, { Scale = 1.04 }):Play()
	end)
	button.MouseLeave:Connect(function()
		if not hovering then return end
		hovering = false
		button.BackgroundColor3 = restBg
		button.TextColor3 = restText
		stroke.Color = baseStroke
		TweenService:Create(scale, UITheme.Tweens.Fast, { Scale = 1 }):Play()
	end)
	button.Activated:Connect(function()
		SoundManager.PlayClick()
		scale.Scale = 0.975
		TweenService:Create(scale, UITheme.Tweens.Spring, { Scale = if hovering then 1.04 else 1 }):Play()
		if hovering then
			-- Hand the rest colours back so the click handler can change them
			-- (e.g. a tab marking itself selected); keep those afterwards.
			button.BackgroundColor3, button.TextColor3 = restBg, restText
			onClick()
			restBg, restText = button.BackgroundColor3, button.TextColor3
			button.BackgroundColor3 = C.PlaqueHover
		else
			onClick()
		end
	end)
	return stroke
end

return MenuStyle
