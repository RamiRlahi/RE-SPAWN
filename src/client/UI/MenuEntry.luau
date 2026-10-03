--!strict
-- The quiet menu entry used on the title and campfire screens (after the
-- RE:SPAWN key art): a line icon, a bold label at ~65% opacity and a thin gold
-- underline. Hover (or `setLit`) turns it bright gold with a soft glow band,
-- slides the text, turns the icon and runs a spark along the underline.
-- Icons are drawn from frames because the menu font has no symbol glyphs.

local TweenService = game:GetService("TweenService")

local MenuEntry = {}

local BRASS = Color3.fromRGB(194, 132, 52)
local BRASS_LIGHT = Color3.fromRGB(255, 213, 128)
local IVORY = Color3.fromRGB(232, 222, 204)
local HOVER = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

MenuEntry.Colors = { Brass = BRASS, BrassLight = BRASS_LIGHT, Ivory = IVORY }
MenuEntry.Bold = BOLD

-- A filled or outlined frame centred on `pos`.
function MenuEntry.Shape(parent: Instance, size: Vector2, pos: UDim2, rotation: number?, filled: boolean?, round: boolean?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Size = UDim2.fromOffset(size.X, size.Y)
	f.Position = pos
	f.Rotation = rotation or 0
	f.BackgroundColor3 = IVORY
	f.BackgroundTransparency = if filled then 0 else 1
	f.BorderSizePixel = 0
	f.Parent = parent
	if not filled then
		local s = Instance.new("UIStroke")
		s.Color = IVORY
		s.Thickness = 1.5
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = f
	end
	if round then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = f
	end
	return f
end
local shape = MenuEntry.Shape

local function at(x: number, y: number): UDim2
	return UDim2.new(0.5, x, 0.5, y)
end

local function makeIcon(parent: Instance, kind: string): Frame
	local holder = Instance.new("Frame")
	holder.Name = "Icon"
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0, 0.5)
	holder.Size = UDim2.fromOffset(28, 28)
	holder.Position = UDim2.new(0, 14, 0.5, -3)
	holder.Parent = parent
	if kind == "play" then
		shape(holder, Vector2.new(15, 15), at(0, 0), 45)
		shape(holder, Vector2.new(5, 5), at(0, 0), 45, true)
	elseif kind == "settings" then
		shape(holder, Vector2.new(13, 13), at(0, 0), 0, false, true)
		for i = 0, 7 do
			local a = i * math.pi / 4
			shape(holder, Vector2.new(3, 5), at(math.sin(a) * 9, -math.cos(a) * 9), math.deg(a), true)
		end
		shape(holder, Vector2.new(4, 4), at(0, 0), 0, true, true)
	elseif kind == "keybinds" then
		shape(holder, Vector2.new(24, 15), at(0, 0))
		for row = 0, 1 do
			for col = 0, 3 do
				shape(holder, Vector2.new(3, 3), at(-7.5 + col * 5, -2.5 + row * 5), 0, true)
			end
		end
	elseif kind == "credits" then
		shape(holder, Vector2.new(15, 20), at(0, 0))
		for i = 0, 2 do
			shape(holder, Vector2.new(8, 1.5), at(0, -5 + i * 5), 0, true)
		end
	elseif kind == "ready" then -- a ring with a check mark
		shape(holder, Vector2.new(20, 20), at(0, 0), 0, false, true)
		shape(holder, Vector2.new(2.5, 6), at(-3, 1.5), -45, true)
		shape(holder, Vector2.new(2.5, 11), at(1.8, -0.8), 40, true)
	elseif kind == "invite" then -- a figure with a plus
		shape(holder, Vector2.new(8, 8), at(-4, -5), 0, false, true)
		shape(holder, Vector2.new(14, 7), at(-4, 6), 0, false, true)
		shape(holder, Vector2.new(8, 2), at(8, -2), 0, true)
		shape(holder, Vector2.new(2, 8), at(8, -2), 0, true)
	elseif kind == "class" then -- a sword
		shape(holder, Vector2.new(2.5, 18), at(1.5, -1.5), 45, true)
		shape(holder, Vector2.new(10, 2.5), at(-3.5, 3.5), 45, true)
		shape(holder, Vector2.new(4, 4), at(-7, 7), 45, true)
	else -- quit / leave: a door with an arrow leaving it
		shape(holder, Vector2.new(11, 20), at(-5, 0))
		shape(holder, Vector2.new(11, 2), at(5, 0), 0, true)
		shape(holder, Vector2.new(5, 5), at(9, 0), 45)
	end
	return holder
end

local function tint(holder: Instance, color: Color3)
	for _, d in ipairs(holder:GetDescendants()) do
		if d:IsA("Frame") then
			TweenService:Create(d, HOVER, { BackgroundColor3 = color }):Play()
		elseif d:IsA("UIStroke") then
			TweenService:Create(d, HOVER, { Color = color }):Play()
		end
	end
end

-- Scales a menu column down on short screens so `designHeight` pixels fit.
function MenuEntry.FitHeight(frame: GuiObject, designHeight: number)
	local scale = Instance.new("UIScale")
	scale.Parent = frame
	local function update()
		local cam = workspace.CurrentCamera
		local h = if cam then cam.ViewportSize.Y else 800
		scale.Scale = math.clamp((h - 40) / designHeight, 0.55, 1)
	end
	update()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(update) end
end

export type Entry = {
	button: TextButton,
	setLabel: (string) -> (),
	setLit: (boolean) -> (),
	setEnabled: (boolean) -> (),
}

function MenuEntry.Button(parent: Instance, label: string, icon: string, order: number, onClick: () -> ()): Entry
	local button = Instance.new("TextButton")
	button.Name = label:gsub("%s+", "") .. "Button"
	button.Size = UDim2.new(1, 0, 0, 56)
	button.LayoutOrder = order
	button.BackgroundTransparency = 1
	button.AutoButtonColor = false
	button.Text = ""
	button.Parent = parent

	local glow = Instance.new("Frame")
	glow.Name = "HoverGlow"
	glow.Size = UDim2.new(0, 0, 1, -6)
	glow.BackgroundColor3 = Color3.fromRGB(255, 170, 70)
	glow.BackgroundTransparency = 1
	glow.BorderSizePixel = 0
	glow.Parent = button
	local gg = Instance.new("UIGradient")
	gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(0.55, 0.8), NumberSequenceKeypoint.new(1, 1) })
	gg.Parent = glow

	local iconHolder = makeIcon(button, icon)

	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Position = UDim2.fromOffset(56, 0)
	text.Size = UDim2.new(1, -56, 1, -6)
	text.Text = label
	text.FontFace = BOLD
	text.TextSize = 22
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextColor3 = IVORY
	text.TextTransparency = 0.35
	text.TextStrokeColor3 = Color3.fromRGB(20, 8, 4)
	text.TextStrokeTransparency = 0.6
	text.Parent = button

	local under = Instance.new("Frame")
	under.Name = "Underline"
	under.AnchorPoint = Vector2.new(0, 1)
	under.Position = UDim2.new(0, 14, 1, -3)
	under.Size = UDim2.new(0.68, 0, 0, 1)
	under.BackgroundColor3 = BRASS
	under.BackgroundTransparency = 0.45
	under.BorderSizePixel = 0
	under.Parent = button
	for _, x in ipairs({ 0, 1 }) do
		shape(under, Vector2.new(4, 4), UDim2.fromScale(x, 0.5), 45, true).BackgroundColor3 = BRASS_LIGHT
	end
	local spark = shape(under, Vector2.new(6, 6), UDim2.fromScale(0, 0.5), 45, true)
	spark.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
	spark.BackgroundTransparency = 1

	local turn = if icon == "play" then 90 else 20
	local hovered, lit, enabled = false, false, true
	local function refresh(sparkle: boolean)
		local on = (hovered and enabled) or lit
		TweenService:Create(glow, HOVER, { Size = UDim2.new(if on then 0.85 else 0, 0, 1, -6), BackgroundTransparency = if on then 0.72 else 1 }):Play()
		TweenService:Create(text, HOVER, {
			Position = UDim2.fromOffset(if on then 64 else 56, 0),
			TextColor3 = if on then BRASS_LIGHT else IVORY,
			TextTransparency = if not enabled then 0.7 elseif on then 0 else 0.35,
			TextStrokeTransparency = if on then 0.35 else 0.6,
		}):Play()
		TweenService:Create(iconHolder, HOVER, {
			Rotation = if on then turn else 0,
			Position = UDim2.new(0, if on then 18 else 14, 0.5, -3),
		}):Play()
		tint(iconHolder, if on then BRASS_LIGHT else IVORY)
		TweenService:Create(under, HOVER, {
			BackgroundTransparency = if on then 0 else 0.45,
			BackgroundColor3 = if on then BRASS_LIGHT else BRASS,
		}):Play()
		if on and sparkle then
			spark.Position = UDim2.fromScale(0, 0.5)
			spark.BackgroundTransparency = 0
			TweenService:Create(spark, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Position = UDim2.fromScale(1, 0.5), BackgroundTransparency = 1,
			}):Play()
		end
	end
	button.MouseEnter:Connect(function() hovered = true refresh(true) end)
	button.MouseLeave:Connect(function() hovered = false refresh(false) end)
	button.SelectionGained:Connect(function() hovered = true refresh(true) end)
	button.SelectionLost:Connect(function() hovered = false refresh(false) end)
	button.Activated:Connect(function()
		if enabled then onClick() end
	end)

	return {
		button = button,
		setLabel = function(s: string) text.Text = s end,
		setLit = function(v: boolean)
			if lit ~= v then
				lit = v
				refresh(v)
			end
		end,
		setEnabled = function(v: boolean)
			enabled = v
			button.AutoButtonColor = false
			refresh(false)
		end,
	}
end

return MenuEntry
