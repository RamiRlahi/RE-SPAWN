--!strict
--[[
	CorruptionHUD.luau
	The greed on screen (Corruption.luau on the server):

	  • the moment the party chooses to descend past an extraction floor, a
	    banner: "THE DUNGEON STIRS"
	  • then a purple meter under the run timer: CORRUPTION and its level,
	    with what it's doing (enemies stronger, loot richer), pulsing as it
	    climbs

	Reads the run's attributes (RunScope): Corruption, CorruptionActive.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))

local player = Players.LocalPlayer

local CorruptionHUD = {}

local VIOLET = Color3.fromRGB(190, 90, 255)
local RED = Color3.fromRGB(255, 60, 50)
local PARCH = Color3.fromRGB(238, 226, 204)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local BODY = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = BODY
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.4
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function bigBanner(gui: ScreenGui, title: string, sub: string, color: Color3)
	local root = Instance.new("CanvasGroup")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.42)
	root.Size = UDim2.fromOffset(820, 120)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Parent = gui
	label(root, title, 46, color, { Font = Enum.Font.Antique, Size = UDim2.new(1, 0, 0, 56), TextStrokeColor3 = Color3.new(0, 0, 0), TextStrokeTransparency = 0.2 })
	label(root, sub, 16, PARCH, { Position = UDim2.fromOffset(0, 60), Size = UDim2.new(1, 0, 0, 40), TextWrapped = true })
	TweenService:Create(root, TweenInfo.new(0.4), { GroupTransparency = 0 }):Play()
	task.delay(4.5, function()
		TweenService:Create(root, TweenInfo.new(0.8), { GroupTransparency = 1 }):Play()
		task.delay(0.85, function() root:Destroy() end)
	end)
end

function CorruptionHUD.Init()
	local g = Instance.new("ScreenGui")
	g.Name = "CorruptionHUD"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 35
	g.Parent = player:WaitForChild("PlayerGui")

	-- the meter (under the timer)
	local meter = Instance.new("Frame")
	meter.AnchorPoint = Vector2.new(0.5, 0)
	meter.Position = UDim2.new(0.5, 0, 0, 148)
	meter.Size = UDim2.fromOffset(300, 30)
	meter.BackgroundColor3 = Color3.fromRGB(24, 10, 34)
	meter.BackgroundTransparency = 0.2
	meter.Visible = false
	meter.Parent = g
	local mc = Instance.new("UICorner")
	mc.CornerRadius = UDim.new(0, 6)
	mc.Parent = meter
	local ms = Instance.new("UIStroke")
	ms.Color = VIOLET
	ms.Thickness = 1.5
	ms.Parent = meter
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = VIOLET
	fill.BackgroundTransparency = 0.55
	fill.BorderSizePixel = 0
	fill.Parent = meter
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 6)
	fc.Parent = fill
	local name = label(meter, "", 13, Color3.new(1, 1, 1), { FontFace = BOLD, Size = UDim2.fromScale(1, 1) })
	local effect = label(meter, "", 11, PARCH, { Position = UDim2.new(0, 0, 1, 2), Size = UDim2.new(1, 0, 0, 14), TextTransparency = 0.2 })

	local WeeklyModifiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeeklyModifiers"))
	local omen = label(g, "", 13, PARCH, { FontFace = BOLD, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 126),
		Size = UDim2.fromOffset(500, 16), Visible = false })

	local lastLevel = -1
	local wasActive = false
	RunService.RenderStepped:Connect(function()
		local inRun = player:GetAttribute("InLobby") == false
		omen.Visible = inRun
		if inRun then
			local m = WeeklyModifiers.Current()
			omen.Text = m.name
			omen.TextColor3 = m.color
		end
		local active = inRun and RunScope.Mine("CorruptionActive") == true
		local level = if active then (RunScope.Mine("Corruption") or 0) else 0
		if active and not wasActive then
			bigBanner(g, "THE DUNGEON STIRS", "You chose greed. Every floor and every minute it grows stronger, and its treasure richer.", VIOLET)
		end
		wasActive = active
		meter.Visible = active
		if active then
			if level ~= lastLevel then
				lastLevel = level
				name.Text = `CORRUPTION  {level}`
				effect.Text = `Enemies +{level * 10}%   ·   Elites +{level * 4}%   ·   Loot luck +{level * 25}%`
				TweenService:Create(fill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(level / 10, 0, 1), 1) }):Play()
				-- (a pulse as it climbs)
				ms.Thickness = 4
				TweenService:Create(ms, TweenInfo.new(0.6), { Thickness = 1.5 }):Play()
			end
		else
			lastLevel = -1
		end
	end)
end

return CorruptionHUD
