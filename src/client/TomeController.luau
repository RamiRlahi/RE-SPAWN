--!strict
-- Minimal run progression UI: a segmented XP bar and three-tome level-up choice.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))

local TomeController = {}
local barRoot: Frame? = nil
local fill: Frame? = nil
local progressText: TextLabel? = nil
local choiceOverlay: Frame? = nil
local rerollButton: TextButton? = nil

local function makeText(parent: Instance, text: string, size: number): TextLabel
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.TextSize = size
	label.TextColor3 = Color3.fromRGB(225, 252, 255)
	label.Text = text
	label.Parent = parent
	return label
end

local function setProgress(level: number, xp: number, xpToNext: number)
	if not barRoot or not fill or not progressText then return end
	barRoot.Visible = level > 0
	fill.Size = UDim2.new(math.clamp(xp / math.max(xpToNext, 1), 0, 1), 0, 1, 0)
	progressText.Text = `LV. {level}  •  {xp} / {xpToNext}`
end

local function showChoices(choices: { any }, rerollsRemaining: number, lockDuration: number)
	if not choiceOverlay then return end
	choiceOverlay.Visible = true
	local cards = choiceOverlay:FindFirstChild("Cards") :: Frame
	for _, child in ipairs(cards:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	for index, tome in ipairs(choices) do
		local card = Instance.new("TextButton")
		card.Name = `Tome_{tome.id}`
		card.Size = UDim2.new(1 / #choices, -16, 1, 0)
		card.Position = UDim2.new((index - 1) / #choices, 8, 0, 0)
		card.BackgroundColor3 = Color3.fromRGB(10, 28, 37)
		card.BorderSizePixel = 0
		card.AutoButtonColor = false
		card.ZIndex = 22
		card.Parent = cards
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(41, 215, 242)
		stroke.Transparency = 0.25
		stroke.Thickness = 1
		stroke.Parent = card
		local title = makeText(card, tome.name, 17)
		title.Size = UDim2.new(1, -20, 0, 32)
		title.Position = UDim2.new(0, 10, 0, 18)
		title.TextColor3 = Color3.fromRGB(74, 231, 255)
		title.TextWrapped = true
		title.ZIndex = 23
		local description = makeText(card, tome.description, 14)
		description.Size = UDim2.new(1, -24, 0, 48)
		description.Position = UDim2.new(0, 12, 0, 58)
		description.Font = Enum.Font.Gotham
		description.TextWrapped = true
		description.ZIndex = 23
		card.MouseEnter:Connect(function() card.BackgroundColor3 = Color3.fromRGB(16, 58, 70) end)
		card.MouseLeave:Connect(function() card.BackgroundColor3 = Color3.fromRGB(10, 28, 37) end)
		card.Activated:Connect(function()
			if not card.Active then return end
			choiceOverlay.Visible = false
			Network.GetRemoteEvent(Network.Remotes.ChooseTome):FireServer(tome.id)
		end)
	end

	if rerollButton then
		rerollButton.Text = rerollsRemaining > 0 and `REROLL ({rerollsRemaining})` or "NO REROLLS"
		rerollButton.Visible = rerollsRemaining > 0
		rerollButton.Active = false
		rerollButton.AutoButtonColor = false
	end
	for _, child in ipairs(cards:GetChildren()) do
		if child:IsA("TextButton") then
			child.Active = false
			child.AutoButtonColor = false
		end
	end
	task.delay(lockDuration, function()
		if not choiceOverlay or not choiceOverlay.Visible then return end
		for _, child in ipairs(cards:GetChildren()) do
			if child:IsA("TextButton") then
				child.Active = true
				child.AutoButtonColor = true
			end
		end
		if rerollButton and rerollsRemaining > 0 then
			rerollButton.Active = true
			rerollButton.AutoButtonColor = true
		end
	end)
end

function TomeController.Init()
	local gui = Instance.new("ScreenGui")
	gui.Name = "TomeProgressUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150
	gui.Parent = player:WaitForChild("PlayerGui")

	barRoot = Instance.new("Frame")
	barRoot.Name = "ExperienceBar"
	barRoot.AnchorPoint = Vector2.new(0, 1)
	barRoot.Position = UDim2.new(0, 0, 1, 0)
	barRoot.Size = UDim2.new(1, 0, 0, 18)
	barRoot.BackgroundColor3 = Color3.fromRGB(5, 19, 25)
	barRoot.BorderSizePixel = 0
	barRoot.Visible = false
	barRoot.Parent = gui

	fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(0, 0, 1, 0)
	fill.BackgroundColor3 = Color3.fromRGB(21, 205, 232)
	fill.BorderSizePixel = 0
	fill.Parent = barRoot
	local gradient = Instance.new("UIGradient")
	gradient.Color = ColorSequence.new(Color3.fromRGB(15, 148, 184), Color3.fromRGB(80, 242, 255))
	gradient.Parent = fill

	for section = 1, 9 do
		local divider = Instance.new("Frame")
		divider.Name = `Section_{section * 10}`
		divider.Size = UDim2.new(0, 1, 1, 0)
		divider.Position = UDim2.new(section / 10, 0, 0, 0)
		divider.BackgroundColor3 = Color3.fromRGB(165, 250, 255)
		divider.BackgroundTransparency = 0.45
		divider.BorderSizePixel = 0
		divider.ZIndex = 3
		divider.Parent = barRoot
	end

	progressText = makeText(barRoot, "", 12)
	progressText.ZIndex = 4
	progressText.TextStrokeTransparency = 0.5
	progressText.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

	choiceOverlay = Instance.new("Frame")
	choiceOverlay.Name = "TomeChoices"
	choiceOverlay.Size = UDim2.fromScale(1, 1)
	choiceOverlay.BackgroundColor3 = Color3.fromRGB(0, 8, 12)
	choiceOverlay.BackgroundTransparency = 0.2
	choiceOverlay.BorderSizePixel = 0
	choiceOverlay.Visible = false
	choiceOverlay.ZIndex = 20
	choiceOverlay.Parent = gui
	local heading = makeText(choiceOverlay, "LEVEL UP — CHOOSE A TOME", 22)
	heading.Size = UDim2.new(1, 0, 0, 34)
	heading.Position = UDim2.new(0, 0, 0.5, -125)
	heading.ZIndex = 21
	heading.TextColor3 = Color3.fromRGB(86, 238, 255)
	local cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.AnchorPoint = Vector2.new(0.5, 0.5)
	cards.Position = UDim2.new(0.5, 0, 0.5, 10)
	cards.Size = UDim2.new(0.8, 0, 0, 140)
	cards.BackgroundTransparency = 1
	cards.ZIndex = 21
	cards.Parent = choiceOverlay
	rerollButton = Instance.new("TextButton")
	rerollButton.Name = "Reroll"
	rerollButton.AnchorPoint = Vector2.new(0.5, 0)
	rerollButton.Position = UDim2.new(0.5, 0, 0.5, 170)
	rerollButton.Size = UDim2.new(0, 140, 0, 30)
	rerollButton.BackgroundColor3 = Color3.fromRGB(12, 46, 57)
	rerollButton.BorderSizePixel = 0
	rerollButton.Font = Enum.Font.GothamBold
	rerollButton.TextSize = 13
	rerollButton.TextColor3 = Color3.fromRGB(98, 237, 255)
	rerollButton.ZIndex = 22
	rerollButton.Parent = choiceOverlay
	rerollButton.Activated:Connect(function()
		if rerollButton and rerollButton.Active then
			rerollButton.Active = false
			Network.GetRemoteEvent(Network.Remotes.RerollTomes):FireServer()
		end
	end)

	Network.GetRemoteEvent(Network.Remotes.TomeProgress).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" then
			setProgress(payload.level or 1, payload.xp or 0, payload.xpToNext or 1)
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.TomeChoices).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.choices) == "table" then
			showChoices(payload.choices, payload.rerollsRemaining or 0, payload.lockDuration or 2)
		end
	end)

	setProgress(player:GetAttribute("Level") or 0, player:GetAttribute("XP") or 0, player:GetAttribute("XPToNext") or 1)
end

return TomeController
