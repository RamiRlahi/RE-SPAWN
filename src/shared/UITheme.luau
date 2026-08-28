local TweenService = game:GetService("TweenService")

local UITheme = {
	Colors = {
		Background = Color3.fromRGB(12, 14, 19),
		BackgroundOverlay = Color3.fromRGB(8, 10, 14),
		Surface = Color3.fromRGB(20, 23, 31),
		SurfaceAlt = Color3.fromRGB(28, 32, 44),
		SurfaceHover = Color3.fromRGB(36, 42, 58),
		SurfaceSelected = Color3.fromRGB(45, 52, 72),
		
		Border = Color3.fromRGB(52, 60, 80),
		BorderHover = Color3.fromRGB(100, 120, 165),
		BorderActive = Color3.fromRGB(235, 185, 75),
		
		Gold = Color3.fromRGB(235, 185, 75),
		GoldLight = Color3.fromRGB(255, 220, 115),
		GoldDark = Color3.fromRGB(170, 125, 35),
		
		TextPrimary = Color3.fromRGB(245, 248, 255),
		TextSecondary = Color3.fromRGB(165, 175, 195),
		TextMuted = Color3.fromRGB(100, 110, 130),
		
		Success = Color3.fromRGB(55, 215, 125),
		Danger = Color3.fromRGB(240, 70, 70),
		Info = Color3.fromRGB(70, 180, 255),
		Warning = Color3.fromRGB(250, 160, 45),
	},

	Fonts = {
		Title = Enum.Font.GothamBold,
		Header = Enum.Font.GothamBold,
		Body = Enum.Font.GothamMedium,
		Sub = Enum.Font.Gotham,
		Button = Enum.Font.GothamBold,
		Tag = Enum.Font.GothamBold,
	},

	Tweens = {
		Fast = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		Standard = TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		Spring = TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		SmoothFade = TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
	},
}

-- Utility Constructors
function UITheme.AddCorner(parent: Instance, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

function UITheme.AddStroke(parent: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness or 1
	stroke.Transparency = transparency or 0
	stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	stroke.Parent = parent
	return stroke
end

function UITheme.AddPadding(parent: Instance, top: number, bottom: number, left: number, right: number): UIPadding
	local pad = Instance.new("UIPadding")
	pad.PaddingTop = UDim.new(0, top)
	pad.PaddingBottom = UDim.new(0, bottom)
	pad.PaddingLeft = UDim.new(0, left)
	pad.PaddingRight = UDim.new(0, right)
	pad.Parent = parent
	return pad
end

function UITheme.AddGradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?): UIGradient
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(1, c2),
	})
	grad.Rotation = rotation or 0
	grad.Parent = parent
	return grad
end

function UITheme.MakeButtonInteractive(
	button: GuiButton,
	stroke: UIStroke?,
	accentColor: Color3?,
	onHoverSound: (() -> ())?,
	onClickSound: (() -> ())?
)
	local normalColor = button.BackgroundColor3
	local normalScale = button.Size
	local normalStroke = stroke and stroke.Color or UITheme.Colors.Border
	local hoverStroke = accentColor or UITheme.Colors.Gold

	button.MouseEnter:Connect(function()
		if onHoverSound then onHoverSound() end
		TweenService:Create(button, UITheme.Tweens.Fast, {
			BackgroundColor3 = UITheme.Colors.SurfaceHover,
		}):Play()
		if stroke then
			TweenService:Create(stroke, UITheme.Tweens.Fast, {
				Color = hoverStroke,
				Transparency = 0,
			}):Play()
		end
	end)

	button.MouseLeave:Connect(function()
		TweenService:Create(button, UITheme.Tweens.Fast, {
			BackgroundColor3 = normalColor,
		}):Play()
		if stroke then
			TweenService:Create(stroke, UITheme.Tweens.Fast, {
				Color = normalStroke,
				Transparency = 0.2,
			}):Play()
		end
	end)

	button.MouseButton1Down:Connect(function()
		if onClickSound then onClickSound() end
		TweenService:Create(button, UITheme.Tweens.Fast, {
			Size = UDim2.new(normalScale.X.Scale, normalScale.X.Offset - 2, normalScale.Y.Scale, normalScale.Y.Offset - 2),
		}):Play()
	end)

	button.MouseButton1Up:Connect(function()
		TweenService:Create(button, UITheme.Tweens.Spring, {
			Size = normalScale,
		}):Play()
	end)
end

return UITheme
