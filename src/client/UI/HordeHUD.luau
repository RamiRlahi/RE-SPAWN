--!strict
--[[
	HordeHUD.luau
	A horde event on screen (Horde.luau): "A HORDE APPROACHES", then SURVIVE
	and the time left, the count of the slain, and the light gone red while
	it lasts. (The music turns too: MusicController.)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))

local player = Players.LocalPlayer

local HordeHUD = {}

local RED = Color3.fromRGB(255, 70, 55)
local PARCH = Color3.fromRGB(238, 226, 204)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

function HordeHUD.Init()
	local g = Instance.new("ScreenGui")
	g.Name = "HordeHUD"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 36
	g.Parent = player:WaitForChild("PlayerGui")

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0)
	panel.Position = UDim2.new(0.5, 0, 0, 250)
	panel.Size = UDim2.fromOffset(420, 70)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = g
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 40)
	title.Font = Enum.Font.Antique
	title.TextSize = 36
	title.TextColor3 = RED
	title.TextStrokeTransparency = 0.2
	title.Parent = panel
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromOffset(0, 40)
	sub.Size = UDim2.new(1, 0, 0, 22)
	sub.FontFace = BOLD
	sub.TextSize = 16
	sub.TextColor3 = PARCH
	sub.TextStrokeTransparency = 0.4
	sub.Parent = panel

	local tint: ColorCorrectionEffect? = nil
	local was = false
	local announcedAt = 0
	RunService.RenderStepped:Connect(function()
		local untilT = if player:GetAttribute("InLobby") == false then RunScope.Mine("HordeUntil") else nil
		local on = typeof(untilT) == "number"
		if on and not was then
			announcedAt = os.clock()
			-- the light goes red
			if not tint then
				local t = Instance.new("ColorCorrectionEffect")
				t.Name = "HordeTint"
				t.TintColor = Color3.new(1, 1, 1)
				t.Parent = Lighting
				tint = t
			end
			TweenService:Create(tint :: ColorCorrectionEffect, TweenInfo.new(1.2), { TintColor = Color3.fromRGB(255, 175, 165), Saturation = 0.1, Contrast = 0.06 }):Play()
		elseif not on and was then
			if tint then
				local t = tint
				tint = nil
				local tw = TweenService:Create(t, TweenInfo.new(1.5), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 })
				tw.Completed:Once(function() t:Destroy() end)
				tw:Play()
			end
			-- a last word
			title.Text = "THE HORDE BREAKS"
			sub.Text = `{RunScope.Mine("HordeKills") or 0} slain  ·  a reward for every survivor`
			task.delay(3, function()
				if not was then panel.Visible = false end
			end)
		end
		was = on
		if on then
			panel.Visible = true
			local left = math.max(0, (untilT :: number) - Workspace:GetServerTimeNow())
			local intro = os.clock() - announcedAt < 2.5
			title.Text = if intro then "A HORDE APPROACHES" else string.format("SURVIVE   %d:%02d", left // 60, math.floor(left % 60))
			sub.Text = if intro then "Hold the line for a minute." else `{RunScope.Mine("HordeKills") or 0} slain`
			-- (a pulse on the title)
			title.TextTransparency = (math.sin(os.clock() * 5) + 1) * 0.08
		end
	end)
end

return HordeHUD
