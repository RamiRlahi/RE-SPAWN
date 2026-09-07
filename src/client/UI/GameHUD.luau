--[[
	GameHUD.luau
	Hades-inspired in-game HUD:
	 • Bottom-left healthbar with damage trail + numeric HP readout
	 • 4 circular skill action slots (center-bottom) with keybind tags
	 • 2 item pickup slots (left of skills) with number keybinds
	All share a unified dark stone / gold / crimson aesthetic.
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))

local GameHUD = {}

-- ─── PALETTE ──────────────────────────────────────────────────
local C = {
	-- Dark stone backing
	StoneDark       = Color3.fromRGB(18, 16, 22),
	StoneMid        = Color3.fromRGB(30, 27, 35),
	StoneLight      = Color3.fromRGB(44, 40, 52),

	-- Gold / bronze filigree
	Gold            = Color3.fromRGB(215, 175, 65),
	GoldBright      = Color3.fromRGB(255, 215, 95),
	GoldDim         = Color3.fromRGB(140, 110, 40),
	Bronze          = Color3.fromRGB(165, 120, 55),

	-- Crimson / health
	HealthRed       = Color3.fromRGB(180, 30, 30),
	HealthRedBright = Color3.fromRGB(220, 50, 40),
	DamageTrail     = Color3.fromRGB(240, 180, 50),
	HealthBg        = Color3.fromRGB(40, 12, 12),

	-- Skill ring
	SkillRing       = Color3.fromRGB(70, 65, 80),
	SkillBg         = Color3.fromRGB(22, 20, 28),
	CooldownOverlay = Color3.fromRGB(10, 10, 14),

	-- Text
	TextWhite       = Color3.fromRGB(240, 235, 220),
	TextGold        = Color3.fromRGB(230, 195, 100),
	TextMuted       = Color3.fromRGB(120, 115, 130),
	TextKeybind     = Color3.fromRGB(190, 185, 175),

	-- Item slots
	ItemBg          = Color3.fromRGB(25, 22, 30),
	ItemBorder      = Color3.fromRGB(80, 72, 95),
}

-- ─── CONSTANTS ────────────────────────────────────────────────
local HP_BAR_WIDTH      = 260
local HP_BAR_HEIGHT     = 18
local HP_BAR_CORNER     = 3
local SKILL_SIZE        = 56
local SKILL_GAP         = 12
local ITEM_SIZE         = 42
local ITEM_GAP          = 8
local DAMAGE_TRAIL_SPEED = 2.5  -- how fast the trail catches up (per second fraction)

-- ─── SKILL ICON ASSET IDs ─────────────────────────────────────
-- Upload your 4 skill icons to Roblox (Game Explorer > Images) and paste the asset IDs here.
-- Format: "rbxassetid://123456789"
local SKILL_ICONS = {
	[1] = "rbxassetid://100153299372067",  -- 1st skill: Spin Attack (E)
	[2] = "rbxassetid://130845824985540",  -- 2nd skill: Flame Slash (F)
	[3] = "rbxassetid://129819062572666",  -- 3rd skill: Phoenix Dash (Q)
	[4] = "rbxassetid://90460231425099",   -- 4th skill: Ultimate (R)
}

-- ─── STATE ────────────────────────────────────────────────────
local player = Players.LocalPlayer
local screenGui: ScreenGui = nil
local hudFrame: Frame = nil

-- Health state
local currentHP = 100
local maxHP = 100
local displayTrailHP = 100  -- the "yellow damage trail" amount
local hpFill: Frame = nil
local hpTrail: Frame = nil
local hpText: TextLabel = nil
local livesText: TextLabel = nil

-- Skill state (cooldowns)
local skillSlots = {}  -- array of { frame, cooldownOverlay, cooldownText, keybindLabel }

-- Item state
local itemSlots = {}  -- array of { frame, iconLabel, countLabel }

-- Connections
local heartbeatConn: RBXScriptConnection? = nil
local healthConn: RBXScriptConnection? = nil
local characterConn: RBXScriptConnection? = nil

-- ─── HELPERS ──────────────────────────────────────────────────
local function makeFrame(props: {
	Name: string?,
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	BgColor: Color3?,
	BgTransparency: number?,
	ZIndex: number?,
	LayoutOrder: number?,
	ClipsDescendants: boolean?,
}): Frame
	local f = Instance.new("Frame")
	f.Name = props.Name or "Frame"
	f.Size = props.Size or UDim2.new(0, 100, 0, 100)
	f.Position = props.Position or UDim2.new(0, 0, 0, 0)
	f.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	f.BackgroundColor3 = props.BgColor or C.StoneDark
	f.BackgroundTransparency = props.BgTransparency or 0
	f.BorderSizePixel = 0
	f.ZIndex = props.ZIndex or 1
	f.LayoutOrder = props.LayoutOrder or 0
	f.ClipsDescendants = if props.ClipsDescendants ~= nil then props.ClipsDescendants else false
	f.Parent = props.Parent
	return f
end

local function makeLabel(props: {
	Name: string?,
	Parent: Instance?,
	Size: UDim2?,
	Position: UDim2?,
	AnchorPoint: Vector2?,
	Text: string?,
	Font: Enum.Font?,
	TextSize: number?,
	TextColor: Color3?,
	TextXAlignment: Enum.TextXAlignment?,
	TextYAlignment: Enum.TextYAlignment?,
	BgTransparency: number?,
	BgColor: Color3?,
	ZIndex: number?,
	TextTransparency: number?,
}): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.Name or "Label"
	l.Size = props.Size or UDim2.new(1, 0, 1, 0)
	l.Position = props.Position or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	l.Text = props.Text or ""
	l.Font = props.Font or UITheme.Fonts.Body
	l.TextSize = props.TextSize or 14
	l.TextColor3 = props.TextColor or C.TextWhite
	l.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	l.TextYAlignment = props.TextYAlignment or Enum.TextYAlignment.Center
	l.BackgroundTransparency = if props.BgTransparency ~= nil then props.BgTransparency else 1
	l.BackgroundColor3 = props.BgColor or C.StoneDark
	l.BorderSizePixel = 0
	l.ZIndex = props.ZIndex or 1
	l.TextTransparency = props.TextTransparency or 0
	l.Parent = props.Parent
	return l
end

-- ─── HEALTHBAR ────────────────────────────────────────────────
local function createHealthBar(parent: Frame)
	-- Container for the entire health section
	local healthContainer = makeFrame({
		Name = "HealthContainer",
		Parent = parent,
		Size = UDim2.new(0, HP_BAR_WIDTH + 20, 0, 52),
		Position = UDim2.new(0, 20, 1, -20),
		AnchorPoint = Vector2.new(0, 1),
		BgColor = C.StoneDark,
		BgTransparency = 0.15,
		ZIndex = 10,
	})
	UITheme.AddCorner(healthContainer, 6)
	UITheme.AddStroke(healthContainer, C.GoldDim, 1.5, 0.3)
	UITheme.AddPadding(healthContainer, 6, 8, 10, 10)

	-- Inner dark gradient overlay
	UITheme.AddGradient(healthContainer, C.StoneDark, C.StoneMid, 90)

	-- ═══ HP Bar Background ═══
	local barBg = makeFrame({
		Name = "BarBg",
		Parent = healthContainer,
		Size = UDim2.new(1, 0, 0, HP_BAR_HEIGHT),
		Position = UDim2.new(0, 0, 0, 0),
		BgColor = C.HealthBg,
		ZIndex = 11,
		ClipsDescendants = true,
	})
	UITheme.AddCorner(barBg, HP_BAR_CORNER)
	UITheme.AddStroke(barBg, C.StoneLight, 1, 0.4)

	-- Damage trail bar (yellow/gold bar that trails behind)
	hpTrail = makeFrame({
		Name = "HpTrail",
		Parent = barBg,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BgColor = C.DamageTrail,
		BgTransparency = 0.15,
		ZIndex = 12,
	})
	UITheme.AddCorner(hpTrail, HP_BAR_CORNER)

	-- Active HP fill (crimson red)
	hpFill = makeFrame({
		Name = "HpFill",
		Parent = barBg,
		Size = UDim2.new(1, 0, 1, 0),
		Position = UDim2.new(0, 0, 0, 0),
		BgColor = C.HealthRed,
		ZIndex = 13,
	})
	UITheme.AddCorner(hpFill, HP_BAR_CORNER)
	-- Bright-to-dark gradient on the fill for depth
	UITheme.AddGradient(hpFill, C.HealthRedBright, C.HealthRed, 90)

	-- Sheen / highlight line at the top of the bar
	local sheen = makeFrame({
		Name = "Sheen",
		Parent = barBg,
		Size = UDim2.new(1, -4, 0, 3),
		Position = UDim2.new(0, 2, 0, 1),
		BgColor = Color3.fromRGB(255, 255, 255),
		BgTransparency = 0.82,
		ZIndex = 14,
	})
	UITheme.AddCorner(sheen, 2)

	-- ═══ HP Numeric Text ═══
	hpText = makeLabel({
		Name = "HpText",
		Parent = healthContainer,
		Size = UDim2.new(0.6, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -2),
		AnchorPoint = Vector2.new(0, 1),
		Text = "100 / 100",
		Font = UITheme.Fonts.Header,
		TextSize = 13,
		TextColor = C.TextWhite,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 11,
	})

	-- ═══ Lives / Death Defiance counter ═══
	-- Small red drop icon + "1 / 3" text
	local livesContainer = makeFrame({
		Name = "LivesContainer",
		Parent = healthContainer,
		Size = UDim2.new(0, 50, 0, 16),
		Position = UDim2.new(1, 0, 1, -2),
		AnchorPoint = Vector2.new(1, 1),
		BgTransparency = 1,
		ZIndex = 11,
	})

	-- Red drop icon (text emoji substitute)
	makeLabel({
		Name = "DropIcon",
		Parent = livesContainer,
		Size = UDim2.new(0, 14, 0, 16),
		Position = UDim2.new(0, 0, 0, 0),
		Text = "❤",
		TextSize = 12,
		TextColor = C.HealthRedBright,
		Font = UITheme.Fonts.Body,
		ZIndex = 12,
	})

	livesText = makeLabel({
		Name = "LivesText",
		Parent = livesContainer,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 16, 0, 0),
		Text = "1 / 3",
		Font = UITheme.Fonts.Body,
		TextSize = 12,
		TextColor = C.TextMuted,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	})
end

-- ─── SKILL SLOTS ──────────────────────────────────────────────
local function createSkillSlot(parent: Frame, index: number, keybind: string): {}
	local slotContainer = makeFrame({
		Name = "Skill_" .. index,
		Parent = parent,
		Size = UDim2.new(0, SKILL_SIZE, 0, SKILL_SIZE + 20),
		BgTransparency = 1,
		ZIndex = 10,
		LayoutOrder = index,
	})

	-- Outer ring (circular border)
	local ring = makeFrame({
		Name = "Ring",
		Parent = slotContainer,
		Size = UDim2.new(0, SKILL_SIZE, 0, SKILL_SIZE),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BgColor = C.SkillBg,
		ZIndex = 11,
	})
	UITheme.AddCorner(ring, SKILL_SIZE / 2)  -- fully round
	UITheme.AddStroke(ring, C.Gold, 2, 0.2)

	-- Inner gradient for depth
	UITheme.AddGradient(ring, C.StoneMid, C.SkillBg, 180)

	-- Inner dark circle (skill icon area)
	local innerCircle = makeFrame({
		Name = "InnerCircle",
		Parent = ring,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgColor = C.SkillBg,
		ZIndex = 12,
		ClipsDescendants = true,
	})
	UITheme.AddCorner(innerCircle, (SKILL_SIZE - 8) / 2)

	-- Skill icon image
	local skillIcon = Instance.new("ImageLabel")
	skillIcon.Name = "SkillIcon"
	skillIcon.Size = UDim2.new(1, 4, 1, 4)
	skillIcon.Position = UDim2.new(0.5, 0, 0.5, 0)
	skillIcon.AnchorPoint = Vector2.new(0.5, 0.5)
	skillIcon.BackgroundTransparency = 1
	skillIcon.BorderSizePixel = 0
	skillIcon.ZIndex = 13
	skillIcon.ScaleType = Enum.ScaleType.Fit
	skillIcon.ImageTransparency = 0
	skillIcon.Parent = innerCircle
	UITheme.AddCorner(skillIcon, (SKILL_SIZE - 8) / 2)

	-- Set the icon image if asset ID is configured
	local assetId = SKILL_ICONS[index]
	if assetId and assetId ~= "" then
		skillIcon.Image = assetId
	else
		-- Fallback: show a tinted placeholder
		skillIcon.ImageColor3 = C.TextGold
		skillIcon.ImageTransparency = 0.6
	end

	-- Cooldown dark overlay (radial sweep not possible in Roblox, so we use a filling bar)
	local cooldownOverlay = makeFrame({
		Name = "CooldownOverlay",
		Parent = innerCircle,
		Size = UDim2.new(1, 0, 0, 0),  -- grows from bottom up
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BgColor = C.CooldownOverlay,
		BgTransparency = 0.35,
		ZIndex = 14,
	})
	UITheme.AddCorner(cooldownOverlay, (SKILL_SIZE - 8) / 2)

	-- Cooldown timer text
	local cooldownText = makeLabel({
		Name = "CooldownText",
		Parent = innerCircle,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		TextSize = 16,
		TextColor = C.TextWhite,
		Font = UITheme.Fonts.Header,
		ZIndex = 15,
		TextTransparency = 0,
	})

	-- Subtle glow ring when skill is ready (outer ring pulse)
	-- We'll handle this via a secondary stroke
	local glowStroke = UITheme.AddStroke(ring, C.GoldBright, 1, 0.7)
	glowStroke.Name = "GlowStroke"

	-- Keybind label below the circle
	local keybindLabel = makeLabel({
		Name = "KeybindLabel",
		Parent = slotContainer,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = keybind,
		TextSize = 11,
		TextColor = C.TextKeybind,
		Font = UITheme.Fonts.Tag,
		ZIndex = 11,
	})

	local slot = {
		frame = slotContainer,
		ring = ring,
		innerCircle = innerCircle,
		cooldownOverlay = cooldownOverlay,
		cooldownText = cooldownText,
		keybindLabel = keybindLabel,
		glowStroke = glowStroke,
		icon = skillIcon,
	}
	table.insert(skillSlots, slot)
	return slot
end

local function createSkillBar(parent: Frame)
	-- Container centered at bottom
	local totalWidth = (SKILL_SIZE * 4) + (SKILL_GAP * 3)
	local skillContainer = makeFrame({
		Name = "SkillBar",
		Parent = parent,
		Size = UDim2.new(0, totalWidth, 0, SKILL_SIZE + 22),
		Position = UDim2.new(0.5, 0, 1, -14),
		AnchorPoint = Vector2.new(0.5, 1),
		BgTransparency = 1,
		ZIndex = 10,
	})

	-- Layout
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, SKILL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = skillContainer

	-- Create 4 skill slots with keybinds
	local keybinds = { "E", "F", "Q", "R" }
	for i = 1, 4 do
		createSkillSlot(skillContainer, i, keybinds[i])
	end

	-- Subtle backing panel behind the skills
	local backing = makeFrame({
		Name = "SkillBacking",
		Parent = parent,
		Size = UDim2.new(0, totalWidth + 30, 0, SKILL_SIZE + 12),
		Position = UDim2.new(0.5, 0, 1, -18),
		AnchorPoint = Vector2.new(0.5, 1),
		BgColor = C.StoneDark,
		BgTransparency = 0.5,
		ZIndex = 9,
	})
	UITheme.AddCorner(backing, 28)
	UITheme.AddStroke(backing, C.GoldDim, 1, 0.6)
	UITheme.AddGradient(backing, C.StoneDark, C.StoneMid, 90)
end

-- ─── ITEM SLOTS ───────────────────────────────────────────────
local function createItemSlot(parent: Frame, index: number): {}
	local slotFrame = makeFrame({
		Name = "Item_" .. index,
		Parent = parent,
		Size = UDim2.new(0, ITEM_SIZE, 0, ITEM_SIZE + 16),
		BgTransparency = 1,
		ZIndex = 10,
		LayoutOrder = index,
	})

	-- Circle background
	local circle = makeFrame({
		Name = "Circle",
		Parent = slotFrame,
		Size = UDim2.new(0, ITEM_SIZE, 0, ITEM_SIZE),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BgColor = C.ItemBg,
		ZIndex = 11,
	})
	UITheme.AddCorner(circle, ITEM_SIZE / 2)
	UITheme.AddStroke(circle, C.ItemBorder, 1.5, 0.3)
	UITheme.AddGradient(circle, C.StoneMid, C.ItemBg, 180)

	-- Item icon placeholder
	local iconLabel = makeLabel({
		Name = "ItemIcon",
		Parent = circle,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		TextSize = 18,
		TextColor = C.TextMuted,
		Font = UITheme.Fonts.Body,
		ZIndex = 12,
	})

	-- Count badge (for stackable items)
	local countLabel = makeLabel({
		Name = "CountBadge",
		Parent = circle,
		Size = UDim2.new(0, 16, 0, 14),
		Position = UDim2.new(1, -2, 0, -2),
		AnchorPoint = Vector2.new(1, 0),
		Text = "",
		TextSize = 10,
		TextColor = C.TextWhite,
		Font = UITheme.Fonts.Tag,
		BgTransparency = 0,
		BgColor = C.StoneDark,
		ZIndex = 13,
	})
	UITheme.AddCorner(countLabel, 4)
	UITheme.AddStroke(countLabel, C.GoldDim, 1, 0.5)
	countLabel.Visible = false  -- hidden until item has count

	-- Keybind number below
	makeLabel({
		Name = "SlotNumber",
		Parent = slotFrame,
		Size = UDim2.new(1, 0, 0, 14),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 1),
		Text = tostring(index),
		TextSize = 10,
		TextColor = C.TextKeybind,
		Font = UITheme.Fonts.Tag,
		ZIndex = 11,
	})

	local slot = {
		frame = slotFrame,
		circle = circle,
		iconLabel = iconLabel,
		countLabel = countLabel,
	}
	table.insert(itemSlots, slot)
	return slot
end

local function createItemBar(parent: Frame)
	-- Container to the left of the skill bar
	local totalWidth = (ITEM_SIZE * 2) + ITEM_GAP
	local itemContainer = makeFrame({
		Name = "ItemBar",
		Parent = parent,
		Size = UDim2.new(0, totalWidth, 0, ITEM_SIZE + 18),
		Position = UDim2.new(0.5, -((SKILL_SIZE * 4 + SKILL_GAP * 3) / 2) - 24, 1, -18),
		AnchorPoint = Vector2.new(1, 1),
		BgTransparency = 1,
		ZIndex = 10,
	})

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Bottom
	layout.Padding = UDim.new(0, ITEM_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = itemContainer

	for i = 1, 2 do
		createItemSlot(itemContainer, i)
	end
end

-- ─── HP UPDATE LOGIC ──────────────────────────────────────────
local function updateHPDisplay(animate: boolean?)
	if not hpFill or not hpTrail or not hpText then return end

	local fraction = if maxHP > 0 then math.clamp(currentHP / maxHP, 0, 1) else 0

	-- Immediately snap the red bar
	TweenService:Create(hpFill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = UDim2.new(fraction, 0, 1, 0),
	}):Play()

	-- Update text
	hpText.Text = string.format("%d / %d", math.floor(currentHP), math.floor(maxHP))

	-- Flash effect on damage
	if animate and displayTrailHP > currentHP then
		-- Brief bright flash on the fill
		hpFill.BackgroundTransparency = 0.3
		task.delay(0.1, function()
			if hpFill then
				TweenService:Create(hpFill, TweenInfo.new(0.3), {
					BackgroundTransparency = 0,
				}):Play()
			end
		end)
	end

	-- If healed, snap trail immediately
	if currentHP > displayTrailHP then
		displayTrailHP = currentHP
	end
end

local function onHeartbeat(dt: number)
	if not hpTrail then return end

	-- Slowly move the damage trail towards the current HP
	if displayTrailHP > currentHP then
		displayTrailHP = displayTrailHP - (maxHP * DAMAGE_TRAIL_SPEED * dt)
		if displayTrailHP < currentHP then
			displayTrailHP = currentHP
		end
		local trailFraction = if maxHP > 0 then math.clamp(displayTrailHP / maxHP, 0, 1) else 0
		hpTrail.Size = UDim2.new(trailFraction, 0, 1, 0)
	else
		-- Keep trail in sync
		local fraction = if maxHP > 0 then math.clamp(currentHP / maxHP, 0, 1) else 0
		hpTrail.Size = UDim2.new(fraction, 0, 1, 0)
	end
end

-- ─── CHARACTER HEALTH BINDING ─────────────────────────────────
local function bindToCharacter(character: Model)
	-- Disconnect previous health connection
	if healthConn then
		healthConn:Disconnect()
		healthConn = nil
	end

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then return end

	maxHP = humanoid.MaxHealth
	currentHP = humanoid.Health
	displayTrailHP = currentHP
	updateHPDisplay(false)

	healthConn = humanoid:GetPropertyChangedSignal("Health"):Connect(function()
		local oldHP = currentHP
		currentHP = humanoid.Health
		maxHP = humanoid.MaxHealth
		updateHPDisplay(currentHP < oldHP)
	end)
end

-- ─── PUBLIC API ───────────────────────────────────────────────

function GameHUD.Init()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	-- Create the ScreenGui
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 50
	screenGui.Parent = playerGui

	-- Main HUD frame (full screen, invisible, just a container)
	hudFrame = makeFrame({
		Name = "HUDContainer",
		Parent = screenGui,
		Size = UDim2.new(1, 0, 1, 0),
		BgTransparency = 1,
		ZIndex = 1,
	})

	-- Build UI components
	createHealthBar(hudFrame)
	createSkillBar(hudFrame)
	createItemBar(hudFrame)

	-- Bind to current character or wait for one
	if player.Character then
		task.spawn(function()
			bindToCharacter(player.Character)
		end)
	end

	characterConn = player.CharacterAdded:Connect(function(character)
		task.spawn(function()
			bindToCharacter(character)
		end)
	end)

	-- Heartbeat for damage trail animation
	heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)

	print("[GameHUD] Initialized successfully.")
end

-- Set skill cooldown display (call from combat system)
-- skillIndex: 1-4, remaining: seconds left, total: total cooldown
function GameHUD.SetSkillCooldown(skillIndex: number, remaining: number, total: number)
	local slot = skillSlots[skillIndex]
	if not slot then return end

	if remaining <= 0 then
		-- Skill ready
		slot.cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		slot.cooldownText.Text = ""
		-- Pulse the glow
		TweenService:Create(slot.glowStroke, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Transparency = 0.2,
		}):Play()
		task.delay(0.5, function()
			if slot.glowStroke then
				TweenService:Create(slot.glowStroke, TweenInfo.new(0.8), {
					Transparency = 0.7,
				}):Play()
			end
		end)
	else
		-- On cooldown
		local fraction = math.clamp(remaining / total, 0, 1)
		slot.cooldownOverlay.Size = UDim2.new(1, 0, fraction, 0)
		slot.cooldownText.Text = string.format("%.1f", remaining)
		slot.glowStroke.Transparency = 0.85
	end
end

-- Set item in a slot (call from inventory system)
-- slotIndex: 1-2, icon: emoji/text, count: stack count (nil to hide)
function GameHUD.SetItem(slotIndex: number, icon: string?, count: number?)
	local slot = itemSlots[slotIndex]
	if not slot then return end

	if icon and icon ~= "" then
		slot.iconLabel.Text = icon
		slot.iconLabel.TextColor3 = C.TextGold
	else
		slot.iconLabel.Text = ""
		slot.iconLabel.TextColor3 = C.TextMuted
	end

	if count and count > 0 then
		slot.countLabel.Text = tostring(count)
		slot.countLabel.Visible = true
	else
		slot.countLabel.Visible = false
	end
end

-- Set lives / death defiance count
function GameHUD.SetLives(current: number, max: number)
	if livesText then
		livesText.Text = string.format("%d / %d", current, max)
	end
end

-- Show / hide the HUD
function GameHUD.SetVisible(visible: boolean)
	if screenGui then
		screenGui.Enabled = visible
	end
end

-- Cleanup
function GameHUD.Destroy()
	if heartbeatConn then heartbeatConn:Disconnect() end
	if healthConn then healthConn:Disconnect() end
	if characterConn then characterConn:Disconnect() end
	if screenGui then screenGui:Destroy() end
	skillSlots = {}
	itemSlots = {}
end

return GameHUD
