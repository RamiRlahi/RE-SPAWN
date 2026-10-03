--!strict
-- Run progression UI: the account XP bar, and the level-up / relic choice
-- (shown by ChoiceScreen: each tome a 3D book, each relic its own model).

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local RunScope = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RunScope"))
local Network = require(Shared:WaitForChild("Network"))
local TomeData = require(Shared:WaitForChild("TomeData"))
local ChoiceScreen = require(script.Parent:WaitForChild("ChoiceScreen"))

-- ── Palette (matches TitleScreen / SettingsModal) ────────────────────────────
local BRASS = Color3.fromRGB(194, 132, 52)
local BRASS_LIGHT = Color3.fromRGB(255, 213, 128)
local BRASS_DARK = Color3.fromRGB(120, 78, 26)
local PLAQUE_DARK = Color3.fromRGB(17, 13, 13)
local PARCHMENT = Color3.fromRGB(239, 213, 170)
local INK = Color3.fromRGB(28, 15, 10)

local FONT = Enum.Font.Antique

local function accentFor(id: string?): Color3
	return TomeData.AccentFor(id)
end

local TomeController = {}
TomeController.AccentFor = accentFor
local barRoot: Frame? = nil
local fill: Frame? = nil
local progressText: TextLabel? = nil
local choiceOverlay: Frame? = nil
local choiceScreen: any = nil

local function addGradient(parent: Instance, c1: Color3, c2: Color3, rotation: number?): UIGradient
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, c1),
		ColorSequenceKeypoint.new(1, c2),
	})
	grad.Rotation = rotation or 90
	grad.Parent = parent
	return grad
end

local function makeText(parent: Instance, text: string, size: number, color: Color3?, strokeColor: Color3?): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = FONT
	label.TextSize = size
	label.TextColor3 = color or PARCHMENT
	label.TextStrokeColor3 = strokeColor or INK
	label.TextStrokeTransparency = 0.35
	label.Text = text
	label.Parent = parent
	return label
end

-- The account level bar: shown during a run (not in the menus).
local function setProgress(level: number, xp: number, xpToNext: number)
	if not barRoot or not fill or not progressText then return end
	barRoot.Visible = level > 0 and player:GetAttribute("InLobby") == false
	if xpToNext <= 0 then
		fill.Size = UDim2.new(1, 0, 1, 0)
		progressText.Text = `LV. {level}   •   MAX`
	else
		fill.Size = UDim2.new(math.clamp(xp / xpToNext, 0, 1), 0, 1, 0)
		progressText.Text = `LV. {level}   •   {xp} / {xpToNext} XP`
	end
end

local function refreshProgress()
	setProgress(player:GetAttribute("AccountLevel") or 0, player:GetAttribute("AccountXP") or 0,
		player:GetAttribute("AccountXPToNext") or 0)
end

-- "LEVEL UP" across the top of the screen when the account gains a level.
local function levelUpBanner(gui: ScreenGui, level: number)
	local banner = makeText(gui, "LEVEL UP", 44, BRASS_LIGHT, INK)
	banner.Name = "AccountLevelUp"
	banner.AnchorPoint = Vector2.new(0.5, 0)
	banner.Position = UDim2.new(0.5, 0, 0, 90)
	banner.Size = UDim2.fromOffset(600, 50)
	banner.ZIndex = 30
	local sub = makeText(banner, `LEVEL {level}`, 20, PARCHMENT, INK)
	sub.Position = UDim2.fromOffset(0, 46)
	sub.Size = UDim2.new(1, 0, 0, 24)
	sub.ZIndex = 30
	banner.TextTransparency, sub.TextTransparency = 1, 1
	TweenService:Create(banner, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	TweenService:Create(sub, TweenInfo.new(0.35), { TextTransparency = 0 }):Play()
	task.delay(2.4, function()
		TweenService:Create(banner, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(sub, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	task.delay(3.1, function() banner:Destroy() end)
end

-- A level-up's tomes / boons or a relic found: the pick-one screen
-- (ChoiceScreen: 3D books and relics on pedestals).
local function showChoices(choices: { any }, rerollsRemaining: number, lockDuration: number)
	if not choiceOverlay or not choiceScreen then return end
	choiceOverlay.Visible = true
	choiceScreen.Show(choices, rerollsRemaining, lockDuration)
end

function TomeController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TomeProgressUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150
	gui.Parent = player:WaitForChild("PlayerGui")

	-- ── XP bar (wood trough + brass fill) ───────────────────────────────────
	barRoot = Instance.new("Frame")
	barRoot.Name = "ExperienceBar"
	barRoot.AnchorPoint = Vector2.new(0, 1)
	barRoot.Position = UDim2.new(0, 0, 1, 0)
	barRoot.Size = UDim2.new(1, 0, 0, 20)
	barRoot.BackgroundColor3 = PLAQUE_DARK
	barRoot.BorderSizePixel = 0
	barRoot.Visible = false
	barRoot.Parent = gui

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = BRASS
	fill.BorderSizePixel = 0
	fill.Parent = barRoot
	addGradient(fill, BRASS_DARK, BRASS_LIGHT, 0)

	local topEdge = Instance.new("Frame")
	topEdge.Size = UDim2.new(1, 0, 0, 2)
	topEdge.BackgroundColor3 = BRASS_LIGHT
	topEdge.BackgroundTransparency = 0.3
	topEdge.BorderSizePixel = 0
	topEdge.ZIndex = 2
	topEdge.Parent = barRoot

	for section = 1, 9 do
		local divider = Instance.new("Frame")
		divider.Name = `Section_{section * 10}`
		divider.Size = UDim2.new(0, 1, 1, 0)
		divider.Position = UDim2.new(section / 10, 0, 0, 0)
		divider.BackgroundColor3 = PARCHMENT
		divider.BackgroundTransparency = 0.55
		divider.BorderSizePixel = 0
		divider.ZIndex = 3
		divider.Parent = barRoot
	end

	progressText = makeText(barRoot, "", 14, PARCHMENT, INK)
	progressText.ZIndex = 4

	-- ── Level-up choice overlay ─────────────────────────────────────────────
	choiceOverlay = Instance.new("Frame")
	choiceOverlay.Name = "TomeChoices"
	choiceOverlay.Size = UDim2.fromScale(1, 1)
	choiceOverlay.BackgroundTransparency = 1
	choiceOverlay.BorderSizePixel = 0
	choiceOverlay.Visible = false
	choiceOverlay.ZIndex = 20
	choiceOverlay.Parent = gui

	-- While choosing, show the normal mouse cursor instead of the aim reticle
	-- (the reticle stops following the mouse while the game is paused).
	local overlay = choiceOverlay
	overlay:GetPropertyChangedSignal("Visible"):Connect(function()
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local found = pg and pg:FindFirstChild("AimReticleGui")
		local reticle = if found and found:IsA("ScreenGui") then found else nil
		if overlay.Visible then
			UserInputService.MouseIconEnabled = true
			if reticle then reticle.Enabled = false end
		elseif reticle then
			-- Back to the aim reticle (only in a run, where the reticle lives).
			reticle.Enabled = true
			UserInputService.MouseIconEnabled = false
		end
	end)

	choiceScreen = ChoiceScreen.Create(overlay, function(id: string)
		overlay.Visible = false
		Network.GetRemoteEvent(Network.Remotes.ChooseTome):FireServer(id)
	end, function()
		Network.GetRemoteEvent(Network.Remotes.RerollTomes):FireServer()
	end)
	-- (closed from anywhere: stop the 3D models spinning)
	overlay:GetPropertyChangedSignal("Visible"):Connect(function()
		if not overlay.Visible then choiceScreen.Hide() end
	end)

	Network.GetRemoteEvent(Network.Remotes.TomeProgress).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			setProgress(payload.level or 1, payload.xp or 0, payload.xpToNext or 0)
		end
	end)
	for _, attr in ipairs({ "AccountXP", "AccountXPToNext", "InLobby" }) do
		player:GetAttributeChangedSignal(attr):Connect(refreshProgress)
	end

	-- While a teammate is choosing a tome (the game is paused for everyone),
	-- say who everyone's waiting on.
	local waiting = makeText(gui, "", 22, PARCHMENT, INK)
	waiting.Name = "WaitingForTome"
	waiting.AnchorPoint = Vector2.new(0.5, 0)
	waiting.Position = UDim2.new(0.5, 0, 0, 140)
	waiting.Size = UDim2.fromOffset(720, 30)
	waiting.ZIndex = 25
	waiting.Visible = false
	local function refreshWaiting()
		local who = RunScope.Mine("TomesChoosing")
		local choosingMyself = choiceOverlay ~= nil and choiceOverlay.Visible
		local show = RunScope.Mine("TomesPaused") == true and typeof(who) == "string"
			and not choosingMyself and player:GetAttribute("InLobby") == false
		waiting.Visible = show
		if show then waiting.Text = `WAITING FOR {string.upper(who :: string)} TO CHOOSE A TOME…` end
	end
	-- (the run's attributes live on its RunScope folder: checked often)
	task.spawn(function()
		while true do
			task.wait(0.25)
			refreshWaiting()
		end
	end)
	if choiceOverlay then choiceOverlay:GetPropertyChangedSignal("Visible"):Connect(refreshWaiting) end
	refreshWaiting()
	local shownLevel: number? = player:GetAttribute("AccountLevel")
	player:GetAttributeChangedSignal("AccountLevel"):Connect(function()
		local level = player:GetAttribute("AccountLevel")
		-- The first value is the saved level arriving, not a level up.
		if typeof(level) == "number" and shownLevel and level > shownLevel then
			levelUpBanner(gui, level)
		end
		shownLevel = level
		refreshProgress()
	end)
	Network.GetRemoteEvent(Network.Remotes.TomeChoices).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.choices) == "table" then
			showChoices(payload.choices, payload.rerollsRemaining or 0, payload.lockDuration or 2)
		end
	end)

	refreshProgress()
end

return TomeController
