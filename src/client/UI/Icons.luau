--!strict
--[[
	Icons.luau
	A small set of flat, one-colour icons drawn from plain UI shapes (Frames,
	rounded corners, strokes), so every icon in a row shares one colour and
	one shape language (Roblox's own UI guidance) and needs no image upload.
	They scale with the frame they're drawn into.

	  Icons.Draw(name, parent, color?, px?) → Frame   (px: its drawn size, default 29)
	      party, sword, shirt, tree, book, flag, plus, bag, horseshoe, gift,
	      help, chevron, lock
--]]

local Icons = {}

-- the size (pixels, unscaled) of the icon being drawn: strokes are set from it
local drawPx = 29

local function box(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, radius: number?, rot: number?): Frame
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(x, y)
	f.Size = UDim2.fromScale(w, h)
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Rotation = rot or 0
	f.Parent = parent
	if radius then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(radius, 0)
		c.Parent = f
	end
	return f
end

local function dot(parent: Instance, x: number, y: number, d: number, color: Color3): Frame
	return box(parent, x, y, d, d, color, 0.5)
end

-- A ring (outline only), `thick` as a share of the icon's size.
local function ring(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, thick: number): Frame
	local f = box(parent, x, y, w, h, color, 0.5)
	f.BackgroundTransparency = 1
	local s = Instance.new("UIStroke")
	s.Color = color
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = f
	-- (in pixels of the icon's own drawn size: a UIScale above scales it with
	-- everything else, so it is not measured from the screen)
	s.Thickness = math.max(1, drawPx * thick)
	return f
end

-- The lower half of a ring (a U), clipped.
local function cup(parent: Instance, x: number, y: number, w: number, h: number, color: Color3, thick: number)
	local clip = Instance.new("Frame")
	clip.AnchorPoint = Vector2.new(0.5, 0)
	clip.Position = UDim2.fromScale(x, y)
	clip.Size = UDim2.fromScale(w + thick * 2, h / 2 + thick)
	clip.BackgroundTransparency = 1
	clip.ClipsDescendants = true
	clip.Parent = parent
	local r = ring(clip, 0.5, 0, w / (w + thick * 2), h / (h / 2 + thick), color, thick)
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	return clip
end

local DRAW: { [string]: (Frame, Color3) -> () } = {
	party = function(f, c)
		dot(f, 0.36, 0.33, 0.26, c)
		box(f, 0.36, 0.72, 0.42, 0.3, c, 0.45)
		dot(f, 0.68, 0.38, 0.2, c)
		box(f, 0.7, 0.72, 0.32, 0.24, c, 0.45)
	end,
	sword = function(f, c)
		local s = Instance.new("Frame")
		s.AnchorPoint = Vector2.new(0.5, 0.5)
		s.Position = UDim2.fromScale(0.5, 0.5)
		s.Size = UDim2.fromScale(1, 1)
		s.BackgroundTransparency = 1
		s.Rotation = 45
		s.Parent = f
		box(s, 0.5, 0.36, 0.12, 0.56, c, 0.3)  -- blade
		box(s, 0.5, 0.66, 0.38, 0.08, c, 0.5)  -- guard
		box(s, 0.5, 0.78, 0.08, 0.16, c)       -- grip
		dot(s, 0.5, 0.88, 0.12, c)             -- pommel
	end,
	shirt = function(f, c)
		box(f, 0.5, 0.58, 0.44, 0.56, c, 0.1)
		box(f, 0.3, 0.38, 0.2, 0.3, c, 0.2, 35)
		box(f, 0.7, 0.38, 0.2, 0.3, c, 0.2, -35)
	end,
	tree = function(f, c)
		box(f, 0.5, 0.37, 0.07, 0.3, c)
		box(f, 0.36, 0.62, 0.07, 0.26, c, nil, 45)
		box(f, 0.64, 0.62, 0.07, 0.26, c, nil, -45)
		dot(f, 0.5, 0.22, 0.24, c)
		dot(f, 0.26, 0.76, 0.22, c)
		dot(f, 0.74, 0.76, 0.22, c)
	end,
	book = function(f, c)
		box(f, 0.3, 0.5, 0.3, 0.6, c, 0.12, -6)
		box(f, 0.7, 0.5, 0.3, 0.6, c, 0.12, 6)
		box(f, 0.5, 0.52, 0.06, 0.6, c)
	end,
	flag = function(f, c)
		box(f, 0.27, 0.52, 0.07, 0.76, c, 0.5)
		box(f, 0.53, 0.34, 0.46, 0.34, c, 0.12)
	end,
	plus = function(f, c)
		box(f, 0.5, 0.5, 0.14, 0.6, c, 0.5)
		box(f, 0.5, 0.5, 0.6, 0.14, c, 0.5)
	end,
	bag = function(f, c)
		box(f, 0.5, 0.64, 0.74, 0.44, c, 0.08)
		ring(f, 0.5, 0.36, 0.4, 0.3, c, 0.06)
	end,
	horseshoe = function(f, c)
		cup(f, 0.5, 0.38, 0.5, 0.5, c, 0.1)
		box(f, 0.25, 0.32, 0.12, 0.24, c, 0.3)
		box(f, 0.75, 0.32, 0.12, 0.24, c, 0.3)
	end,
	gift = function(f, c)
		box(f, 0.5, 0.66, 0.56, 0.4, c, 0.1)
		box(f, 0.5, 0.4, 0.66, 0.14, c, 0.2)
		dot(f, 0.4, 0.26, 0.16, c)
		dot(f, 0.6, 0.26, 0.16, c)
	end,
	help = function(f, c)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, 1)
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = c
		t.Text = "?"
		t.Parent = f
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0.02, 0), UDim.new(0.02, 0)
		pad.Parent = t
	end,
	-- (a small ^: "opens upward", on the dock's category tiles)
	chevron = function(f, c)
		box(f, 0.37, 0.56, 0.42, 0.16, c, 0.5, -42)
		box(f, 0.63, 0.56, 0.42, 0.16, c, 0.5, 42)
	end,
	lock = function(f, c)
		box(f, 0.5, 0.66, 0.56, 0.44, c, 0.18)
		local clip = Instance.new("Frame")
		clip.AnchorPoint = Vector2.new(0.5, 1)
		clip.Position = UDim2.fromScale(0.5, 0.46)
		clip.Size = UDim2.fromScale(0.52, 0.32)
		clip.BackgroundTransparency = 1
		clip.ClipsDescendants = true
		clip.Parent = f
		local r = ring(clip, 0.5, 1, 0.66, 1.6, c, 0.08)
		r.AnchorPoint = Vector2.new(0.5, 0.5)
	end,
}

function Icons.Draw(name: string, parent: Instance, color: Color3?, px: number?): Frame
	drawPx = px or 29
	local f = Instance.new("Frame")
	f.Name = "Icon"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromScale(0.6, 0.6)
	f.BackgroundTransparency = 1
	f.Parent = parent
	local a = Instance.new("UIAspectRatioConstraint")
	a.AspectRatio = 1
	a.Parent = f
	local draw = DRAW[name]
	if draw then draw(f, color or Color3.new(1, 1, 1)) end
	return f
end

-- A button that shrinks a little while pressed and springs back (Roblox's
-- guidance: every button reacts to a press).
function Icons.Press(button: GuiButton)
	local scale = button:FindFirstChildOfClass("UIScale") or Instance.new("UIScale")
	scale.Parent = button
	local TweenService = game:GetService("TweenService")
	button.MouseButton1Down:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.06), { Scale = 0.92 }):Play()
	end)
	local function up()
		TweenService:Create(scale, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
	button.MouseButton1Up:Connect(up)
	button.MouseLeave:Connect(up)
end

-- The close button Roblox's guidance describes: square, red, a white X, top
-- right of its window.
Icons.CLOSE_RED = Color3.fromRGB(224, 50, 50)

return Icons
