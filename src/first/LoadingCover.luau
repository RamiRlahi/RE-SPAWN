--!strict
--[[
	LoadingCover.luau (ReplicatedFirst)
	The RE:SPAWN loading screen. It lives in ReplicatedFirst so it can be shown
	on the very first frame (Boot), before anything else has replicated; the
	menu loader (client MenuLoader) then drives it and fades it away once the
	menu's critical assets are loaded. One screen, shared by both.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")

local LoadingCover = {}

local LOGO = "rbxassetid://74919387892039"
local GOLD = Color3.fromRGB(255, 213, 128)
local BRASS = Color3.fromRGB(194, 132, 52)
local IVORY = Color3.fromRGB(232, 222, 204)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

LoadingCover.Logo = LOGO

type Ui = { gui: ScreenGui, root: CanvasGroup, logo: ImageLabel, fill: Frame, glint: Frame, status: TextLabel, pct: TextLabel }
local ui: Ui? = nil
local shown = 0 -- progress shown, 0..1
local hiding = false
local shimmer: RBXScriptConnection? = nil

local function build(): Ui
	local gui = Instance.new("ScreenGui")
	gui.Name = "MenuLoader"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 1000
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	local root = Instance.new("CanvasGroup")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(6, 4, 12)
	root.BorderSizePixel = 0
	root.Active = true -- nothing behind it can be clicked while it's up
	root.Parent = gui
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new(Color3.fromRGB(26, 16, 40), Color3.fromRGB(4, 3, 8))
	grad.Parent = root

	local logo = Instance.new("ImageLabel")
	logo.AnchorPoint = Vector2.new(0.5, 0.5)
	logo.Position = UDim2.fromScale(0.5, 0.42)
	logo.Size = UDim2.fromOffset(440, 184)
	logo.BackgroundTransparency = 1
	logo.Image = LOGO
	logo.ImageTransparency = 1 -- fades in once the image has arrived
	logo.ScaleType = Enum.ScaleType.Fit
	logo.Parent = root

	local track = Instance.new("Frame")
	track.AnchorPoint = Vector2.new(0.5, 0.5)
	track.Position = UDim2.fromScale(0.5, 0.62)
	track.Size = UDim2.fromOffset(360, 2)
	track.BackgroundColor3 = BRASS
	track.BackgroundTransparency = 0.7
	track.BorderSizePixel = 0
	track.ClipsDescendants = false
	track.Parent = root
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Parent = track
	-- A small diamond riding the end of the bar.
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.fromScale(1, 0.5)
	tip.Size = UDim2.fromOffset(7, 7)
	tip.Rotation = 45
	tip.BackgroundColor3 = GOLD
	tip.BorderSizePixel = 0
	tip.Parent = fill
	-- A soft glint sweeping along the track (so it never looks frozen).
	local glint = Instance.new("Frame")
	glint.AnchorPoint = Vector2.new(0.5, 0.5)
	glint.Position = UDim2.fromScale(0, 0.5)
	glint.Size = UDim2.fromOffset(60, 2)
	glint.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
	glint.BorderSizePixel = 0
	glint.Parent = track
	local gg = Instance.new("UIGradient")
	gg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) })
	gg.Parent = glint

	local status = Instance.new("TextLabel")
	status.AnchorPoint = Vector2.new(0.5, 0)
	status.Position = UDim2.new(0.5, -30, 0.62, 12)
	status.Size = UDim2.fromOffset(300, 18)
	status.BackgroundTransparency = 1
	status.FontFace = BOLD
	status.TextSize = 12
	status.TextColor3 = IVORY
	status.TextTransparency = 0.3
	status.TextXAlignment = Enum.TextXAlignment.Left
	status.Text = ""
	status.Parent = root
	local pct = Instance.new("TextLabel")
	pct.AnchorPoint = Vector2.new(0.5, 0)
	pct.Position = UDim2.new(0.5, 150, 0.62, 12)
	pct.Size = UDim2.fromOffset(60, 18)
	pct.BackgroundTransparency = 1
	pct.FontFace = BOLD
	pct.TextSize = 12
	pct.TextColor3 = GOLD
	pct.TextXAlignment = Enum.TextXAlignment.Right
	pct.Text = "0%"
	pct.Parent = root

	-- Reveal the logo as soon as its image is in.
	task.spawn(function()
		while not logo.IsLoaded and logo.Parent do task.wait(0.05) end
		TweenService:Create(logo, TweenInfo.new(0.5), { ImageTransparency = 0 }):Play()
		task.delay(0.55, function() logo.ImageTransparency = 0 end)
	end)

	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")
	return { gui = gui, root = root, logo = logo, fill = fill, glint = glint, status = status, pct = pct }
end

-- Show the screen fully opaque (creating it on first use). Already up (the
-- loader taking over from Boot): leave it, progress and all.
function LoadingCover.Show()
	if ui and (ui :: Ui).gui.Enabled and not hiding then return end
	if not ui then ui = build() end
	local u = ui :: Ui
	hiding = false
	shown = 0
	u.fill.Size = UDim2.fromScale(0, 1)
	u.root.GroupTransparency = 0
	u.gui.Enabled = true
	if not shimmer then
		local t = 0
		shimmer = RunService.Heartbeat:Connect(function(dt)
			t = (t + dt * 0.6) % 1.4
			u.glint.Position = UDim2.fromScale(math.clamp(t, 0, 1), 0.5)
		end)
	end
end

function LoadingCover.IsShown(): boolean
	return ui ~= nil and (ui :: Ui).gui.Enabled and not hiding
end

-- Progress 0..1 (never goes backwards) and an optional status line.
function LoadingCover.SetProgress(p: number, status: string?)
	local u = ui
	if not u then return end
	shown = math.max(shown, math.clamp(p, 0, 1))
	-- Set directly: UI tweens only advance on rendered frames.
	u.fill.Size = UDim2.fromScale(shown, 1)
	u.pct.Text = `{math.floor(shown * 100)}%`
	if status then u.status.Text = status end
end

-- Fade into whatever is behind it (1s), then switch off.
function LoadingCover.Hide()
	local u = ui
	if not u or hiding then return end
	hiding = true
	TweenService:Create(u.root, TweenInfo.new(1.0, Enum.EasingStyle.Sine), { GroupTransparency = 1 }):Play()
	-- Finish on a timer rather than on the tween (tweens freeze while the
	-- window isn't rendering); the screen must never get stuck up.
	task.delay(1.05, function()
		if hiding then
			u.root.GroupTransparency = 1
			u.gui.Enabled = false
			if shimmer then
				shimmer:Disconnect()
				shimmer = nil
			end
		end
	end)
end

return LoadingCover
