--!strict
-- Run progression UI: a segmented XP bar and a three-tome level-up choice.
-- Styled to match the medieval guild-hall menu (wood / brass / Antique),
-- with a distinct accent colour per buff.

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))

-- ── Palette (matches TitleScreen / SettingsModal) ────────────────────────────
local BRASS = Color3.fromRGB(194, 132, 52)
local BRASS_LIGHT = Color3.fromRGB(255, 213, 128)
local BRASS_DARK = Color3.fromRGB(120, 78, 26)
local PLAQUE = Color3.fromRGB(37, 28, 24)
local PLAQUE_DARK = Color3.fromRGB(17, 13, 13)
local WOOD_MID = Color3.fromRGB(72, 48, 33)
local PARCHMENT = Color3.fromRGB(239, 213, 170)
local INK = Color3.fromRGB(28, 15, 10)
local GLYPH = "❖"

local FONT = Enum.Font.Antique

-- Distinct accent colour per buff (keyed by tome id).
local BUFF_COLORS: { [string]: Color3 } = {
	agility = Color3.fromRGB(120, 230, 140),
	attack_speed = Color3.fromRGB(255, 160, 90),
	cooldown = Color3.fromRGB(120, 190, 255),
	damage = Color3.fromRGB(255, 100, 100),
	evasion = Color3.fromRGB(185, 160, 255),
	gold = Color3.fromRGB(255, 205, 80),
	health = Color3.fromRGB(255, 120, 150),
	knockback = Color3.fromRGB(205, 170, 120),
	precision = Color3.fromRGB(255, 230, 120),
	projectile_speed = Color3.fromRGB(130, 230, 230),
	regen = Color3.fromRGB(120, 245, 180),
	shield = Color3.fromRGB(150, 200, 255),
	silver = Color3.fromRGB(210, 215, 230),
	size = Color3.fromRGB(230, 170, 255),
	armor = Color3.fromRGB(170, 190, 210),
	attraction = Color3.fromRGB(255, 140, 220),
	bloody = Color3.fromRGB(205, 45, 55),
	chaos = Color3.fromRGB(200, 120, 255),
	cursed = Color3.fromRGB(150, 85, 190),
	duration = Color3.fromRGB(255, 180, 80),
	luck = Color3.fromRGB(130, 230, 120),
	quantity = Color3.fromRGB(255, 210, 140),
	thorns = Color3.fromRGB(120, 180, 90),
	xp = Color3.fromRGB(120, 200, 255),
}

local function accentFor(id: string?): Color3
	if id and BUFF_COLORS[id] then return BUFF_COLORS[id] end
	return BRASS_LIGHT
end

local TomeController = {}
local barRoot: Frame? = nil
local fill: Frame? = nil
local progressText: TextLabel? = nil
-- Per-tome icon images (optional). Key = tome id, value = "rbxassetid://...".
-- Drop matching image Decals in ReplicatedStorage and paste their ids here (same workflow as the skill icons).
local TOME_ICONS = {
	-- damage = "rbxassetid://000000000000000",
}

local choiceOverlay: Frame? = nil
local rerollButton: TextButton? = nil

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

local function addCorner(parent: Instance, corner: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, corner)
	c.Parent = parent
end

local function setProgress(level: number, xp: number, xpToNext: number)
	if not barRoot or not fill or not progressText then return end
	barRoot.Visible = level > 0
	fill.Size = UDim2.new(math.clamp(xp / math.max(xpToNext, 1), 0, 1), 0, 1, 0)
	progressText.Text = `LV. {level}   •   {xp} / {xpToNext}`
end

local function buildCard(parent: Instance, tome: any, index: number, total: number)
	local accent = accentFor(tome.id)
	local accentBright = accent:Lerp(Color3.new(1, 1, 1), 0.35)

	local slotW = 1 / total
	local card = Instance.new("TextButton")
	card.Name = `Tome_{tome.id}`
	card.Size = UDim2.new(slotW, -16, 1, -12)
	card.Position = UDim2.new((index - 1) * slotW, 8, 0, 6)
	card.BackgroundTransparency = 1
	card.Text = ""
	card.BorderSizePixel = 0
	card.AutoButtonColor = false
	card.ZIndex = 22
	card.Rotation = -3
	card.Parent = parent

	-- Depth shadow plaque behind
	local shadow = Instance.new("Frame")
	shadow.Name = "Depth"
	shadow.Size = UDim2.new(1, 6, 1, 8)
	shadow.Position = UDim2.new(0, 4, 0, 6)
	shadow.BackgroundColor3 = Color3.fromRGB(8, 5, 4)
	shadow.BorderSizePixel = 0
	shadow.ZIndex = 1
	shadow.Parent = card
	addCorner(shadow, 8)

	-- Wood plaque face
	local face = Instance.new("Frame")
	face.Name = "Face"
	face.Size = UDim2.fromScale(1, 1)
	face.BackgroundColor3 = PLAQUE
	face.BorderSizePixel = 0
	face.ZIndex = 2
	face.Parent = card
	addCorner(face, 8)
	addGradient(face, WOOD_MID, PLAQUE_DARK, 90)

	-- Brass outer stroke, tinted toward the buff accent
	local outer = Instance.new("UIStroke")
	outer.Color = accent:Lerp(BRASS, 0.35)
	outer.Thickness = 2
	outer.Transparency = 0.05
	outer.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	outer.Parent = face

	-- Inner hairline
	local inner = Instance.new("Frame")
	inner.Name = "Inner"
	inner.Size = UDim2.new(1, -10, 1, -10)
	inner.Position = UDim2.new(0, 5, 0, 5)
	inner.BackgroundTransparency = 1
	inner.ZIndex = 3
	inner.Parent = face
	local innerStroke = Instance.new("UIStroke")
	innerStroke.Color = BRASS_DARK
	innerStroke.Thickness = 1
	innerStroke.Transparency = 0.4
	innerStroke.Parent = inner
	addCorner(inner, 6)

	-- ── Emblem seal (fills the upper half of the card) ──────────────────────
	local emblem = Instance.new("Frame")
	emblem.Name = "Emblem"
	emblem.AnchorPoint = Vector2.new(0.5, 0)
	emblem.Position = UDim2.new(0.5, 0, 0, 16)
	emblem.Size = UDim2.new(0, 68, 0, 68)
	emblem.BackgroundColor3 = PLAQUE_DARK
	emblem.BorderSizePixel = 0
	emblem.ZIndex = 4
	emblem.Parent = face
	addCorner(emblem, 34)
	local emblemGrad = Instance.new("UIGradient")
	emblemGrad.Color = ColorSequence.new(accent:Lerp(PLAQUE_DARK, 0.5), PLAQUE_DARK)
	emblemGrad.Rotation = 90
	emblemGrad.Parent = emblem
	local emblemRing = Instance.new("UIStroke")
	emblemRing.Color = accent
	emblemRing.Thickness = 2
	emblemRing.Transparency = 0.1
	emblemRing.Parent = emblem

	-- Wax-seal monogram fallback
	local monogram = makeText(emblem, string.sub(tome.name, 1, 1), 34, accentBright, INK)
	monogram.Name = "Monogram"
	monogram.Size = UDim2.fromScale(1, 1)
	monogram.ZIndex = 5

	-- Real icon image (shown when TOME_ICONS[tome.id] is set)
	local iconImage = Instance.new("ImageLabel")
	iconImage.Name = "Icon"
	iconImage.Size = UDim2.new(1, -8, 1, -8)
	iconImage.Position = UDim2.new(0.5, 0, 0.5, 0)
	iconImage.AnchorPoint = Vector2.new(0.5, 0.5)
	iconImage.BackgroundTransparency = 1
	iconImage.BorderSizePixel = 0
	iconImage.ScaleType = Enum.ScaleType.Fit
	iconImage.ZIndex = 6
	iconImage.Visible = false
	iconImage.Parent = emblem
	addCorner(iconImage, 30)
	local iconId = TOME_ICONS[tome.id]
	if iconId and iconId ~= "" then
		iconImage.Image = iconId
		iconImage.Visible = true
		monogram.Visible = false
	end

	-- Accent header bar
	local bar = Instance.new("Frame")
	bar.Name = "AccentBar"
	bar.Size = UDim2.new(1, -28, 0, 3)
	bar.Position = UDim2.new(0, 14, 0, 9)
	bar.BackgroundColor3 = accent
	bar.BorderSizePixel = 0
	bar.ZIndex = 4
	bar.Parent = face
	addCorner(bar, 2)
	local barGlow = Instance.new("UIStroke")
	barGlow.Color = accentBright
	barGlow.Thickness = 1
	barGlow.Transparency = 0.4
	barGlow.Parent = bar

	-- Title
	local title = makeText(face, tome.name, 19, accentBright, INK)
	title.Name = "Title"
	title.Size = UDim2.new(1, -20, 0, 24)
	title.Position = UDim2.new(0, 10, 0, 90)
	title.TextXAlignment = Enum.TextXAlignment.Center
	title.TextWrapped = true
	title.ZIndex = 4

	-- Category tag
	local category = (tome.category == "Unlockable") and "UNLOCKABLE" or "BASE"
	local tag = makeText(face, category, 11, BRASS, INK)
	tag.Name = "Tag"
	tag.Size = UDim2.new(1, -20, 0, 13)
	tag.Position = UDim2.new(0, 10, 0, 115)
	tag.TextXAlignment = Enum.TextXAlignment.Center
	tag.ZIndex = 4

	-- Divider
	local divider = Instance.new("Frame")
	divider.Name = "Divider"
	divider.Size = UDim2.new(1, -28, 0, 1)
	divider.Position = UDim2.new(0, 14, 0, 132)
	divider.BackgroundColor3 = accent
	divider.BackgroundTransparency = 0.55
	divider.BorderSizePixel = 0
	divider.ZIndex = 4
	divider.Parent = face

	-- Description
	local description = makeText(face, tome.description, 14, PARCHMENT, INK)
	description.Name = "Description"
	description.Size = UDim2.new(1, -24, 0, 52)
	description.Position = UDim2.new(0, 12, 0, 140)
	description.TextXAlignment = Enum.TextXAlignment.Center
	description.TextYAlignment = Enum.TextYAlignment.Top
	description.TextWrapped = true
	description.ZIndex = 4

	-- Corner ornaments in the accent colour
	for _, pos in ipairs({
		{ UDim2.new(0, 8, 0, 8), Enum.TextXAlignment.Left },
		{ UDim2.new(1, -8, 0, 8), Enum.TextXAlignment.Right },
	}) do
		local orn = Instance.new("TextLabel")
		orn.BackgroundTransparency = 1
		orn.Size = UDim2.new(0, 16, 0, 16)
		orn.Position = pos[1]
		orn.AnchorPoint = (pos[2] == Enum.TextXAlignment.Right) and Vector2.new(1, 0) or Vector2.new(0, 0)
		orn.Font = FONT
		orn.Text = GLYPH
		orn.TextSize = 13
		orn.TextColor3 = accent
		orn.TextStrokeColor3 = INK
		orn.TextStrokeTransparency = 0.5
		orn.ZIndex = 4
		orn.Parent = face
	end

	-- Hover + click feedback
	local baseStroke = outer.Color
	local baseTransparency = outer.Transparency
	card.MouseEnter:Connect(function()
		if not card.Active then return end
		TweenService:Create(face, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { BackgroundColor3 = PLAQUE:Lerp(accent, 0.12) }):Play()
		TweenService:Create(outer, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Color = accentBright, Transparency = 0, Thickness = 3 }):Play()
		TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Rotation = 0 }):Play()
	end)
	card.MouseLeave:Connect(function()
		TweenService:Create(face, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { BackgroundColor3 = PLAQUE }):Play()
		TweenService:Create(outer, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Color = baseStroke, Transparency = baseTransparency, Thickness = 2 }):Play()
		TweenService:Create(card, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Rotation = -3 }):Play()
	end)
	card.Activated:Connect(function()
		if not card.Active then return end
		choiceOverlay.Visible = false
		Network.GetRemoteEvent(Network.Remotes.ChooseTome):FireServer(tome.id)
	end)

	return card
end

local function showChoices(choices: { any }, rerollsRemaining: number, lockDuration: number)
	if not choiceOverlay then return end
	choiceOverlay.Visible = true
	local cards = choiceOverlay:FindFirstChild("Cards") :: Frame
	for _, child in ipairs(cards:GetChildren()) do
		if child:IsA("TextButton") then child:Destroy() end
	end

	for index, tome in ipairs(choices) do
		buildCard(cards, tome, index, #choices)
	end

	if rerollButton then
		rerollButton.Text = rerollsRemaining > 0 and `REROLL  ({rerollsRemaining})` or "NO REROLLS LEFT"
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

	-- Dark backdrop lives on its OWN low ZIndex layer. Previously the overlay itself
	-- was the dark panel at ZIndex 20, which rendered ABOVE the cards' inner elements
	-- (they use ZIndex 1-4), blacking out the tome panels. ZIndex is global per ScreenGui.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = PLAQUE_DARK
	backdrop.BackgroundTransparency = 0.35
	backdrop.BorderSizePixel = 0
	backdrop.ZIndex = 0
	backdrop.Parent = choiceOverlay

	-- Heading plaque
	local heading = makeText(choiceOverlay, "LEVEL UP", 40, BRASS_LIGHT, INK)
	heading.Name = "Heading"
	heading.Size = UDim2.new(1, 0, 0, 46)
	heading.Position = UDim2.new(0, 0, 0.5, -166)
	heading.ZIndex = 21
	local headingGlow = Instance.new("UIStroke")
	headingGlow.Color = BRASS_DARK
	headingGlow.Thickness = 1
	headingGlow.Transparency = 0.5
	headingGlow.Parent = heading

	local subheading = makeText(choiceOverlay, "—  CHOOSE A TOME  —", 18, PARCHMENT, INK)
	subheading.Name = "Subheading"
	subheading.Size = UDim2.new(1, 0, 0, 22)
	subheading.Position = UDim2.new(0, 0, 0.5, -116)
	subheading.ZIndex = 21

	local cards = Instance.new("Frame")
	cards.Name = "Cards"
	cards.AnchorPoint = Vector2.new(0.5, 0.5)
	cards.Position = UDim2.new(0.5, 0, 0.5, 6)
	cards.Size = UDim2.new(0.56, 0, 0, 200)
	cards.BackgroundTransparency = 1
	cards.ZIndex = 21
	cards.Parent = choiceOverlay

	rerollButton = Instance.new("TextButton")
	rerollButton.Name = "Reroll"
	rerollButton.AnchorPoint = Vector2.new(0.5, 0)
	rerollButton.Position = UDim2.new(0.5, 0, 0.5, 120)
	rerollButton.Size = UDim2.new(0, 170, 0, 38)
	rerollButton.BackgroundColor3 = PLAQUE
	rerollButton.BorderSizePixel = 0
	rerollButton.Font = FONT
	rerollButton.TextSize = 17
	rerollButton.TextColor3 = BRASS_LIGHT
	rerollButton.TextStrokeColor3 = INK
	rerollButton.TextStrokeTransparency = 0.4
	rerollButton.ZIndex = 22
	rerollButton.Parent = choiceOverlay
	addCorner(rerollButton, 6)
	addGradient(rerollButton, WOOD_MID, PLAQUE_DARK, 90)
	local rerollStroke = Instance.new("UIStroke")
	rerollStroke.Color = BRASS
	rerollStroke.Thickness = 2
	rerollStroke.Transparency = 0.15
	rerollStroke.Parent = rerollButton
	rerollButton.MouseEnter:Connect(function()
		if not rerollButton.Active then return end
		TweenService:Create(rerollButton, TweenInfo.new(0.15), { BackgroundColor3 = PLAQUE:Lerp(BRASS, 0.15) }):Play()
		TweenService:Create(rerollStroke, TweenInfo.new(0.15), { Color = BRASS_LIGHT, Transparency = 0 }):Play()
	end)
	rerollButton.MouseLeave:Connect(function()
		TweenService:Create(rerollButton, TweenInfo.new(0.15), { BackgroundColor3 = PLAQUE }):Play()
		TweenService:Create(rerollStroke, TweenInfo.new(0.15), { Color = BRASS, Transparency = 0.15 }):Play()
	end)
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
