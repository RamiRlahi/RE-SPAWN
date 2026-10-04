--[[
	GameHUD.luau
	Gothic in-game HUD (dark stone, thin gold filigree, crimson health):
	 • Bottom-left: diamond class emblem + long healthbar with damage trail,
	   gold coin counter underneath
	 • Top-center: "TIME SURVIVED" plaque with the threat tier below
	 • Bottom-center: 4 gold-ringed skill slots with keybind badges on a
	   filigree baseline
	 • Gunslinger only: a revolver-cylinder ammo counter right of the skills
   (brass rounds / empty chambers, spins while reloading) and a Deadeye bar
 • Bottom-right: Tab plate (opens the full dungeon map, like the Tab key)
	 • A soft dark vignette around the screen edges
]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RunScope = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RunScope"))
local UITheme = require(Shared:WaitForChild("UITheme"))

local GameHUD = {}

-- ─── PALETTE ──────────────────────────────────────────────────
local C = {
	-- Dark stone backing
	StoneDark       = Color3.fromRGB(14, 11, 17),
	StoneMid        = Color3.fromRGB(28, 23, 32),

	-- Gold filigree
	Gold            = Color3.fromRGB(212, 172, 92),
	GoldBright      = Color3.fromRGB(255, 222, 140),
	GoldDim         = Color3.fromRGB(128, 100, 52),

	-- Crimson / health
	HealthRed       = Color3.fromRGB(140, 14, 26),
	HealthRedBright = Color3.fromRGB(214, 34, 48),
	DamageTrail     = Color3.fromRGB(236, 170, 70),
	HealthBg        = Color3.fromRGB(30, 8, 12),

	-- Skills
	SkillBg         = Color3.fromRGB(20, 16, 24),
	CooldownOverlay = Color3.fromRGB(8, 6, 10),

	-- Text
	TextWhite       = Color3.fromRGB(242, 236, 224),
	TextGold        = Color3.fromRGB(226, 196, 132),
	TextKeybind     = Color3.fromRGB(236, 226, 204),
	Threat          = Color3.fromRGB(214, 64, 58),

	-- Coin
	CoinLight       = Color3.fromRGB(255, 220, 120),
	CoinDark        = Color3.fromRGB(176, 124, 40),
	CoinEdge        = Color3.fromRGB(110, 76, 24),
}

local SERIF = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

-- ─── CONSTANTS ────────────────────────────────────────────────
local BOTTOM_MARGIN     = 30   -- clears the XP bar along the bottom edge
local HP_BAR_WIDTH      = 390
local HP_BAR_HEIGHT     = 30
local EMBLEM_SIZE       = 76   -- side of the rotated square (diagonal ≈ 107)
local SKILL_SIZE        = 64
local SKILL_GAP         = 30
local KEY_BADGE_SIZE    = 22
local DAMAGE_TRAIL_SPEED = 2.5  -- how fast the trail catches up (per second fraction)

-- ─── SKILL ICON ASSET IDs ─────────────────────────────────────
-- Upload your 4 skill icons to Roblox (Game Explorer > Images) and paste the asset IDs here.
-- Format: "rbxassetid://123456789"
local SKILL_ICONS_BY_CLASS = {
	cleric = {
		[1] = "rbxassetid://83970690874192",  -- 1st ability (E)
		[2] = "rbxassetid://79167595723607",  -- 2nd ability (F)
		[3] = "rbxassetid://132229793951564", -- 3rd ability (Q)
		[4] = "rbxassetid://85719690091163",  -- Ultimate (R)
	},
	ranger = {
		[1] = "rbxassetid://71390904975203",   -- 1st ability (E)
		[2] = "rbxassetid://116665007054306",  -- 2nd ability (F)
		[3] = "rbxassetid://94605725583145",   -- 3rd ability (Q)
		[4] = "rbxassetid://123385594261124",  -- Ultimate (R)
	},
	heavy_knight = {
		[1] = "rbxassetid://100153299372067",  -- 1st ability (E)
		[2] = "rbxassetid://130845824985540",  -- 2nd ability (F)
		[3] = "rbxassetid://129819062572666",  -- 3rd ability (Q)
		[4] = "rbxassetid://90460231425099",   -- Ultimate (R)
	},
}

local function getSkillIcon(classId: string?, index: number): string?
	if not classId then return nil end
	local set = SKILL_ICONS_BY_CLASS[classId]
	return set and set[index] or nil
end

-- ─── STATE ────────────────────────────────────────────────────
local player = Players.LocalPlayer
local screenGui: ScreenGui = nil
local vignetteGui: ScreenGui = nil
local hudFrame: Frame = nil

-- Health state
local currentHP = 100
local maxHP = 100
local displayTrailHP = 100  -- the "damage trail" amount
local hpFill: Frame = nil
local shieldFill: Frame = nil -- Shield Tome HP: the top of the bar, drawn white
local hpTrail: Frame = nil
local hpText: TextLabel = nil
local runTimerText: TextLabel = nil
local runTierText: TextLabel = nil

-- Gold state
local goldText: TextLabel = nil
local goldScale: UIScale = nil
local shownGold = 0
local countingGold = false

-- Skill state (cooldowns)
local skillSlots = {}  -- array of { frame, cooldownOverlay, cooldownText, keybindLabel, glowStroke, icon }

-- Gunslinger ammo cylinder
local ammoWidget: Frame = nil
local cylinderSpin: Frame = nil
local chambers: { Frame } = {}
local reloadLabel: TextLabel = nil
local deadeyeFill: Frame = nil
local deadeyeLabel: TextLabel = nil
local deadeyeStroke: UIStroke = nil
local shownAmmo = -1
local cylinderAngle = 0

-- Connections
local heartbeatConn: RBXScriptConnection? = nil
local healthConn: RBXScriptConnection? = nil
local characterConn: RBXScriptConnection? = nil
local goldConn: RBXScriptConnection? = nil

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
	Rotation: number?,
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
	f.Rotation = props.Rotation or 0
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
	FontFace: Font?,
	TextSize: number?,
	TextColor: Color3?,
	TextXAlignment: Enum.TextXAlignment?,
	ZIndex: number?,
	StrokeTransparency: number?,
}): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = props.Name or "Label"
	l.Size = props.Size or UDim2.new(1, 0, 1, 0)
	l.Position = props.Position or UDim2.new(0, 0, 0, 0)
	l.AnchorPoint = props.AnchorPoint or Vector2.new(0, 0)
	l.Text = props.Text or ""
	l.FontFace = props.FontFace or SERIF
	l.TextSize = props.TextSize or 14
	l.TextColor3 = props.TextColor or C.TextWhite
	l.TextXAlignment = props.TextXAlignment or Enum.TextXAlignment.Center
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = props.StrokeTransparency or 0.6
	l.BackgroundTransparency = 1
	l.BorderSizePixel = 0
	l.ZIndex = props.ZIndex or 1
	l.Parent = props.Parent
	return l
end

-- A small rotated-square ornament, centred on `pos`.
local function diamond(parent: Instance, size: number, pos: UDim2, z: number, fill: Color3?, stroke: Color3?): Frame
	local d = makeFrame({
		Name = "Diamond",
		Parent = parent,
		Size = UDim2.fromOffset(size, size),
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgColor = fill or C.StoneDark,
		BgTransparency = if fill then 0 else 0.1,
		ZIndex = z,
		Rotation = 45,
	})
	UITheme.AddStroke(d, stroke or C.Gold, 1, 0.1)
	return d
end

-- A thin filigree line that fades out at both ends.
local function fadeLine(parent: Instance, size: UDim2, pos: UDim2, z: number, color: Color3?, vertical: boolean?): Frame
	local line = makeFrame({
		Name = "Filigree",
		Parent = parent,
		Size = size,
		Position = pos,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgColor = color or C.Gold,
		ZIndex = z,
	})
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(0.18, 0.15),
		NumberSequenceKeypoint.new(0.82, 0.15),
		NumberSequenceKeypoint.new(1, 1),
	})
	g.Rotation = if vertical then 90 else 0
	g.Parent = line
	return line
end

-- Rectangular plate with a thin gold border and a dimmer inset border.
local function plate(parent: Instance, props: { Name: string, Size: UDim2, Position: UDim2, AnchorPoint: Vector2, ZIndex: number }): Frame
	local p = makeFrame({
		Name = props.Name,
		Parent = parent,
		Size = props.Size,
		Position = props.Position,
		AnchorPoint = props.AnchorPoint,
		BgColor = C.StoneDark,
		BgTransparency = 0.22,
		ZIndex = props.ZIndex,
	})
	UITheme.AddStroke(p, C.Gold, 1.2, 0.2)
	UITheme.AddGradient(p, C.StoneMid, C.StoneDark, 90)
	local inset = makeFrame({
		Name = "Inset",
		Parent = p,
		Size = UDim2.new(1, -8, 1, -8),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgTransparency = 1,
		ZIndex = props.ZIndex,
	})
	UITheme.AddStroke(inset, C.GoldDim, 1, 0.45)
	return p
end

-- ─── VIGNETTE ─────────────────────────────────────────────────
local function createVignette(playerGui: PlayerGui)
	vignetteGui = Instance.new("ScreenGui")
	vignetteGui.Name = "HUDVignette"
	vignetteGui.ResetOnSpawn = false
	vignetteGui.IgnoreGuiInset = true
	vignetteGui.DisplayOrder = -10 -- beneath every other UI
	vignetteGui.Enabled = false
	vignetteGui.Parent = playerGui

	local edges = {
		-- size, position, anchor, gradient rotation, transparency at gradient start → end
		{ UDim2.new(1, 0, 0.24, 0), UDim2.fromScale(0, 0), Vector2.new(0, 0), 90, 0.3, 1 },
		{ UDim2.new(1, 0, 0.3, 0), UDim2.fromScale(0, 1), Vector2.new(0, 1), 90, 1, 0.2 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(0, 0), Vector2.new(0, 0), 0, 0.3, 1 },
		{ UDim2.new(0.18, 0, 1, 0), UDim2.fromScale(1, 0), Vector2.new(1, 0), 0, 1, 0.3 },
	}
	for i, e in ipairs(edges) do
		local f = makeFrame({
			Name = `Edge{i}`,
			Parent = vignetteGui,
			Size = e[1],
			Position = e[2],
			AnchorPoint = e[3],
			BgColor = Color3.fromRGB(6, 3, 8),
		})
		local g = Instance.new("UIGradient")
		g.Rotation = e[4]
		g.Transparency = NumberSequence.new(e[5], e[6])
		g.Parent = f
	end
end

-- ─── HEALTH + CLASS EMBLEM ────────────────────────────────────
local function createClassEmblem(parent: Frame, center: UDim2)
	-- Outer gold diamond
	local outer = makeFrame({
		Name = "EmblemOuter",
		Parent = parent,
		Size = UDim2.fromOffset(EMBLEM_SIZE, EMBLEM_SIZE),
		Position = center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgColor = C.StoneDark,
		BgTransparency = 0.05,
		ZIndex = 20,
		Rotation = 45,
	})
	UITheme.AddStroke(outer, C.Gold, 2, 0.05)
	UITheme.AddGradient(outer, C.StoneMid, C.StoneDark, 45)

	-- Inner filigree diamond
	local inner = makeFrame({
		Name = "EmblemInner",
		Parent = parent,
		Size = UDim2.fromOffset(EMBLEM_SIZE - 16, EMBLEM_SIZE - 16),
		Position = center,
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgTransparency = 1,
		ZIndex = 21,
		Rotation = 45,
	})
	UITheme.AddStroke(inner, C.GoldDim, 1, 0.3)

	-- Four-pointed silver star: two tapered glowing strokes crossing.
	local starLen = EMBLEM_SIZE + 6
	fadeLine(parent, UDim2.fromOffset(4, starLen), center, 22, Color3.fromRGB(236, 232, 224), true)
	fadeLine(parent, UDim2.fromOffset(starLen - 18, 4), center, 22, Color3.fromRGB(236, 232, 224))
	fadeLine(parent, UDim2.fromOffset(2, starLen * 0.55), center, 22, C.GoldBright, true).Rotation = 45
	fadeLine(parent, UDim2.fromOffset(2, starLen * 0.55), center, 22, C.GoldBright, true).Rotation = -45
	diamond(parent, 9, center, 23, Color3.fromRGB(255, 250, 235), C.GoldBright)
end

local function createGoldCounter(parent: Frame)
	local pill = makeFrame({
		Name = "GoldCounter",
		Parent = parent,
		Size = UDim2.fromOffset(118, 26),
		Position = UDim2.new(0, 12, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BgColor = C.StoneDark,
		BgTransparency = 0.2,
		ZIndex = 10,
	})
	UITheme.AddStroke(pill, C.GoldDim, 1, 0.15)
	diamond(pill, 9, UDim2.fromScale(0, 0.5), 11)
	diamond(pill, 9, UDim2.fromScale(1, 0.5), 11)

	local coin = makeFrame({
		Name = "Coin",
		Parent = pill,
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.new(0, 12, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BgColor = Color3.new(1, 1, 1),
		ZIndex = 12,
	})
	UITheme.AddCorner(coin, 9)
	UITheme.AddStroke(coin, C.CoinEdge, 1, 0)
	UITheme.AddGradient(coin, C.CoinLight, C.CoinDark, 45)
	local coinRing = makeFrame({
		Name = "Ring",
		Parent = coin,
		Size = UDim2.fromOffset(10, 10),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgTransparency = 1,
		ZIndex = 13,
	})
	UITheme.AddCorner(coinRing, 5)
	UITheme.AddStroke(coinRing, C.CoinEdge, 1, 0.3)

	goldText = makeLabel({
		Name = "GoldText",
		Parent = pill,
		Size = UDim2.new(1, -40, 1, 0),
		Position = UDim2.new(0, 38, 0, 0),
		Text = "0",
		FontFace = SERIF_BOLD,
		TextSize = 16,
		TextColor = C.TextWhite,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 12,
	})
	goldScale = Instance.new("UIScale")
	goldScale.Parent = pill
end

local function createHealthBar(parent: Frame)
	local diag = EMBLEM_SIZE * math.sqrt(2)
	local section = makeFrame({
		Name = "HealthSection",
		Parent = parent,
		Size = UDim2.fromOffset(diag / 2 + HP_BAR_WIDTH + 40, diag + 30),
		Position = UDim2.new(0, 18, 1, -BOTTOM_MARGIN),
		AnchorPoint = Vector2.new(0, 1),
		BgTransparency = 1,
		ZIndex = 10,
	})
	local emblemCenter = UDim2.fromOffset(diag / 2 + 2, diag / 2 + 2)

	-- ═══ Bar frame (starts under the emblem's centre) ═══
	local bar = makeFrame({
		Name = "HealthBar",
		Parent = section,
		Size = UDim2.fromOffset(HP_BAR_WIDTH, HP_BAR_HEIGHT),
		Position = emblemCenter,
		AnchorPoint = Vector2.new(0, 0.5),
		BgColor = C.StoneDark,
		BgTransparency = 0.15,
		ZIndex = 11,
	})
	UITheme.AddStroke(bar, C.Gold, 1.2, 0.2)

	-- Pointed gold tip + trailing filigree on the right end
	diamond(bar, 14, UDim2.fromScale(1, 0.5), 15)
	fadeLine(bar, UDim2.fromOffset(46, 1), UDim2.new(1, 22, 0.5, 0), 14)
	-- Hairlines above and below the bar
	fadeLine(bar, UDim2.new(1, 20, 0, 1), UDim2.new(0.5, 10, 0, -5), 12, C.GoldDim)
	fadeLine(bar, UDim2.new(1, 20, 0, 1), UDim2.new(0.5, 10, 1, 5), 12, C.GoldDim)

	-- Fill area (clear of the emblem's right point)
	local fillArea = makeFrame({
		Name = "FillArea",
		Parent = bar,
		Size = UDim2.new(1, -58, 1, -8),
		Position = UDim2.new(0, 46, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BgColor = C.HealthBg,
		ZIndex = 12,
		ClipsDescendants = true,
	})

	-- Damage trail bar (gold bar that trails behind)
	hpTrail = makeFrame({
		Name = "HpTrail",
		Parent = fillArea,
		Size = UDim2.new(1, 0, 1, 0),
		BgColor = C.DamageTrail,
		BgTransparency = 0.2,
		ZIndex = 13,
	})

	-- Active HP fill (crimson)
	hpFill = makeFrame({
		Name = "HpFill",
		Parent = fillArea,
		Size = UDim2.new(1, 0, 1, 0),
		BgColor = Color3.new(1, 1, 1), -- white so the gradient shows its true colours
		ZIndex = 14,
	})
	UITheme.AddGradient(hpFill, C.HealthRed, C.HealthRedBright, 0)

	-- Shield HP (Shield Tomes): white, right after the red; it's lost first.
	shieldFill = makeFrame({
		Name = "ShieldFill",
		Parent = fillArea,
		Size = UDim2.new(0, 0, 1, 0),
		BgColor = Color3.fromRGB(240, 240, 245),
		ZIndex = 14,
	})

	-- Sheen along the top of the bar
	local sheen = makeFrame({
		Name = "Sheen",
		Parent = fillArea,
		Size = UDim2.new(1, 0, 0.4, 0),
		BgColor = Color3.fromRGB(255, 255, 255),
		BgTransparency = 0.85,
		ZIndex = 15,
	})
	local sheenGrad = Instance.new("UIGradient")
	sheenGrad.Rotation = 90
	sheenGrad.Transparency = NumberSequence.new(0.2, 1)
	sheenGrad.Parent = sheen

	-- ═══ HP Numeric Text ═══
	hpText = makeLabel({
		Name = "HpText",
		Parent = fillArea,
		Size = UDim2.new(1, -16, 1, 0),
		Position = UDim2.new(0, 16, 0, 0),
		Text = "100 / 100",
		FontFace = SERIF_BOLD,
		TextSize = 16,
		TextColor = C.TextWhite,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 16,
		StrokeTransparency = 0.4,
	})

	createClassEmblem(section, emblemCenter)
	createGoldCounter(section)
end

-- ─── SKILL SLOTS ──────────────────────────────────────────────
local function createSkillSlot(parent: Frame, index: number, keybind: string): {}
	local slotContainer = makeFrame({
		Name = "Skill_" .. index,
		Parent = parent,
		Size = UDim2.fromOffset(SKILL_SIZE, SKILL_SIZE + KEY_BADGE_SIZE / 2 + 4),
		BgTransparency = 1,
		ZIndex = 10,
		LayoutOrder = index,
	})

	-- Soft glow ring (pulses when the skill comes off cooldown)
	local glow = makeFrame({
		Name = "Glow",
		Parent = slotContainer,
		Size = UDim2.fromOffset(SKILL_SIZE + 8, SKILL_SIZE + 8),
		Position = UDim2.new(0.5, 0, 0, SKILL_SIZE / 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgTransparency = 1,
		ZIndex = 10,
	})
	UITheme.AddCorner(glow, (SKILL_SIZE + 8) / 2)
	local glowStroke = UITheme.AddStroke(glow, C.GoldBright, 2, 0.8)
	glowStroke.Name = "GlowStroke"

	-- Outer gold ring
	local ring = makeFrame({
		Name = "Ring",
		Parent = slotContainer,
		Size = UDim2.fromOffset(SKILL_SIZE, SKILL_SIZE),
		Position = UDim2.new(0.5, 0, 0, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		BgColor = C.SkillBg,
		ZIndex = 11,
	})
	UITheme.AddCorner(ring, SKILL_SIZE / 2)
	UITheme.AddStroke(ring, C.Gold, 2.5, 0.05)
	UITheme.AddGradient(ring, C.StoneMid, C.SkillBg, 90)

	-- Inner circle: a CanvasGroup so the icon and cooldown sweep clip to the circle
	local innerCircle = Instance.new("CanvasGroup")
	innerCircle.Name = "InnerCircle"
	innerCircle.Size = UDim2.new(1, -8, 1, -8)
	innerCircle.Position = UDim2.fromScale(0.5, 0.5)
	innerCircle.AnchorPoint = Vector2.new(0.5, 0.5)
	innerCircle.BackgroundColor3 = C.SkillBg
	innerCircle.BorderSizePixel = 0
	innerCircle.ZIndex = 12
	innerCircle.Parent = ring
	UITheme.AddCorner(innerCircle, (SKILL_SIZE - 8) / 2)
	UITheme.AddStroke(innerCircle, C.GoldDim, 1, 0.3)

	-- Skill icon image
	local skillIcon = Instance.new("ImageLabel")
	skillIcon.Name = "SkillIcon"
	skillIcon.Size = UDim2.new(1, 0, 1, 0)
	skillIcon.BackgroundTransparency = 1
	skillIcon.BorderSizePixel = 0
	skillIcon.ZIndex = 13
	skillIcon.ScaleType = Enum.ScaleType.Crop
	-- Icon image is assigned per-class after Init (see GameHUD.SetClassIcons)
	skillIcon.ImageColor3 = C.TextGold
	skillIcon.ImageTransparency = 0.6
	skillIcon.Parent = innerCircle

	-- Cooldown dark overlay, grows from the bottom up
	local cooldownOverlay = makeFrame({
		Name = "CooldownOverlay",
		Parent = innerCircle,
		Size = UDim2.new(1, 0, 0, 0),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BgColor = C.CooldownOverlay,
		BgTransparency = 0.3,
		ZIndex = 14,
	})

	-- Cooldown timer text
	local cooldownText = makeLabel({
		Name = "CooldownText",
		Parent = innerCircle,
		Text = "",
		FontFace = SERIF_BOLD,
		TextSize = 18,
		TextColor = C.TextWhite,
		ZIndex = 15,
		StrokeTransparency = 0.3,
	})

	-- Keybind badge overlapping the bottom of the ring
	local badge = makeFrame({
		Name = "KeyBadge",
		Parent = slotContainer,
		Size = UDim2.fromOffset(KEY_BADGE_SIZE, KEY_BADGE_SIZE),
		Position = UDim2.new(0.5, 0, 0, SKILL_SIZE + 2),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgColor = C.StoneDark,
		ZIndex = 16,
	})
	UITheme.AddCorner(badge, KEY_BADGE_SIZE / 2)
	UITheme.AddStroke(badge, C.Gold, 1.2, 0.1)
	local keybindLabel = makeLabel({
		Name = "KeybindLabel",
		Parent = badge,
		Text = keybind,
		FontFace = SERIF_BOLD,
		TextSize = 12,
		TextColor = C.TextKeybind,
		ZIndex = 17,
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
	local totalWidth = (SKILL_SIZE * 4) + (SKILL_GAP * 3)
	local height = SKILL_SIZE + KEY_BADGE_SIZE / 2 + 4
	local skillContainer = makeFrame({
		Name = "SkillBar",
		Parent = parent,
		Size = UDim2.fromOffset(totalWidth, height),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
		AnchorPoint = Vector2.new(0.5, 1),
		BgTransparency = 1,
		ZIndex = 10,
	})

	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.VerticalAlignment = Enum.VerticalAlignment.Top
	layout.Padding = UDim.new(0, SKILL_GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = skillContainer

	local keybinds = { "E", "F", "Q", "R" }
	for i = 1, 4 do
		createSkillSlot(skillContainer, i, keybinds[i])
	end

	-- Filigree baseline through the keybind badges, with diamond ornaments.
	local ornaments = makeFrame({
		Name = "SkillOrnaments",
		Parent = parent,
		Size = UDim2.fromOffset(totalWidth, height),
		Position = UDim2.new(0.5, 0, 1, -BOTTOM_MARGIN),
		AnchorPoint = Vector2.new(0.5, 1),
		BgTransparency = 1,
		ZIndex = 9,
	})
	local baseY = SKILL_SIZE + 2
	fadeLine(ornaments, UDim2.fromOffset(totalWidth + 360, 1), UDim2.fromOffset(totalWidth / 2, baseY), 9)
	diamond(ornaments, 8, UDim2.fromOffset(totalWidth / 2, baseY + 1), 10)
	-- Side ornaments level with the rings
	for _, x in ipairs({ -16, totalWidth + 16 }) do
		diamond(ornaments, 7, UDim2.fromOffset(x, SKILL_SIZE / 2), 10)
		fadeLine(ornaments, UDim2.fromOffset(28, 1), UDim2.fromOffset(x + (if x < 0 then -14 else 14), SKILL_SIZE / 2), 9)
	end
end

-- ─── GUNSLINGER AMMO CYLINDER ─────────────────────────────────
local AMMO_SIZE = 104

local gunslingerModule: any = nil
local function getGunslinger(): any
	if gunslingerModule then return gunslingerModule end
	local mod = script.Parent.Parent:FindFirstChild("GunslingerController")
	if not mod then return nil end
	local ok, res = pcall(require, mod)
	if ok then gunslingerModule = res end
	return gunslingerModule
end

local function buildChambers(count: number)
	for _, c in ipairs(chambers) do c:Destroy() end
	table.clear(chambers)
	local ringRadius = AMMO_SIZE * 0.31
	local size = if count > 6 then 17 else 20
	for i = 1, count do
		local a = (i - 1) / count * math.pi * 2 - math.pi / 2
		local c = makeFrame({
			Name = `Chamber{i}`,
			Parent = cylinderSpin,
			Size = UDim2.fromOffset(size, size),
			Position = UDim2.new(0.5, math.cos(a) * ringRadius, 0.5, math.sin(a) * ringRadius),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BgColor = C.GoldBright,
			ZIndex = 13,
		})
		UITheme.AddCorner(c, size / 2)
		UITheme.AddStroke(c, Color3.fromRGB(70, 48, 18), 1.5, 0)
		table.insert(chambers, c)
	end
end

local function createAmmoCylinder(parent: Frame)
	local totalWidth = (SKILL_SIZE * 4) + (SKILL_GAP * 3)
	ammoWidget = makeFrame({
		Name = "AmmoCylinder",
		Parent = parent,
		Size = UDim2.fromOffset(AMMO_SIZE, AMMO_SIZE + 34),
		Position = UDim2.new(0.5, totalWidth / 2 + 48, 1, -BOTTOM_MARGIN + 6),
		AnchorPoint = Vector2.new(0, 1),
		BgTransparency = 1,
		ZIndex = 10,
	})
	ammoWidget.Visible = false

	-- The cylinder face: dark iron disc with a brass rim.
	local disc = makeFrame({
		Name = "Disc",
		Parent = ammoWidget,
		Size = UDim2.fromOffset(AMMO_SIZE, AMMO_SIZE),
		BgColor = C.StoneDark,
		BgTransparency = 0.1,
		ZIndex = 11,
	})
	UITheme.AddCorner(disc, AMMO_SIZE / 2)
	UITheme.AddStroke(disc, C.Gold, 2.5, 0.05)
	cylinderSpin = makeFrame({
		Name = "Spin",
		Parent = disc,
		Size = UDim2.fromScale(1, 1),
		BgTransparency = 1,
		ZIndex = 12,
	})
	local hub = makeFrame({
		Name = "Hub",
		Parent = disc,
		Size = UDim2.fromOffset(18, 18),
		Position = UDim2.fromScale(0.5, 0.5),
		AnchorPoint = Vector2.new(0.5, 0.5),
		BgColor = C.GoldDim,
		ZIndex = 14,
	})
	UITheme.AddCorner(hub, 9)
	reloadLabel = makeLabel({
		Name = "Reload",
		Parent = disc,
		Size = UDim2.new(1, 0, 0, 18),
		Position = UDim2.new(0, 0, 0.5, 14),
		Text = "RELOAD",
		FontFace = SERIF_BOLD,
		TextSize = 13,
		TextColor = C.GoldBright,
		ZIndex = 15,
		StrokeTransparency = 0.2,
	})
	reloadLabel.Visible = false

	-- Deadeye meter under the cylinder.
	local bar = makeFrame({
		Name = "Deadeye",
		Parent = ammoWidget,
		Size = UDim2.new(1, 0, 0, 10),
		Position = UDim2.new(0, 0, 1, -16),
		BgColor = C.StoneDark,
		ZIndex = 11,
		ClipsDescendants = true,
	})
	deadeyeStroke = UITheme.AddStroke(bar, C.GoldDim, 1, 0.1)
	deadeyeFill = makeFrame({
		Name = "Fill",
		Parent = bar,
		Size = UDim2.new(0, 0, 1, 0),
		BgColor = Color3.new(1, 1, 1),
		ZIndex = 12,
	})
	UITheme.AddGradient(deadeyeFill, C.Gold, C.GoldBright, 0)
	deadeyeLabel = makeLabel({
		Name = "DeadeyeLabel",
		Parent = ammoWidget,
		Size = UDim2.new(1, 20, 0, 14),
		Position = UDim2.new(0.5, 0, 1, 0),
		AnchorPoint = Vector2.new(0.5, 0),
		Text = "DEADEYE",
		FontFace = SERIF_BOLD,
		TextSize = 11,
		TextColor = C.TextGold,
		ZIndex = 11,
	})
end

-- Called every frame: follows GunslingerController's (predicted) state.
local function updateAmmoCylinder(dt: number)
	if not ammoWidget then return end
	local isGs = player:GetAttribute("SelectedClass") == "gunslinger"
	ammoWidget.Visible = isGs
	if not isGs then return end
	local gs = getGunslinger()
	if not gs then return end
	local st = gs.GetState()
	if #chambers ~= st.max then
		buildChambers(st.max)
		shownAmmo = -1
	end

	if st.reloading then
		-- Spin while reloading; rounds reappear as the reload fills.
		cylinderAngle += dt * 720
		local loaded = math.floor(st.reloadProgress * st.max + 0.001)
		for i, c in ipairs(chambers) do
			c.BackgroundColor3 = if i <= loaded then C.GoldBright else Color3.fromRGB(12, 10, 14)
		end
		reloadLabel.Visible = true
		shownAmmo = -1
	else
		reloadLabel.Visible = false
		if st.ammo ~= shownAmmo then
			if shownAmmo > st.ammo and shownAmmo >= 0 then
				-- A shot: turn the cylinder one chamber.
				cylinderAngle += 360 / st.max
			end
			shownAmmo = st.ammo
			for i, c in ipairs(chambers) do
				local loaded = i <= st.ammo
				-- The final round glows red: that's the big one.
				c.BackgroundColor3 = if not loaded then Color3.fromRGB(12, 10, 14)
					elseif st.ammo == 1 then Color3.fromRGB(255, 90, 70) else C.GoldBright
			end
		end
	end
	cylinderSpin.Rotation += (cylinderAngle - cylinderSpin.Rotation) * math.clamp(dt * 18, 0, 1)

	local ready = st.deadeye >= 100
	deadeyeFill.Size = UDim2.new(math.clamp(st.deadeye / 100, 0, 1), 0, 1, 0)
	deadeyeLabel.Text = if ready then "DEADEYE READY" else "DEADEYE"
	local pulse = if ready then 0.5 + 0.5 * math.sin(os.clock() * 8) else 0
	deadeyeStroke.Color = if ready then C.GoldBright else C.GoldDim
	deadeyeStroke.Transparency = if ready then 0.4 * (1 - pulse) else 0.1
	deadeyeLabel.TextColor3 = if ready then Color3.fromRGB(255, 250, 220) else C.TextGold
end

-- ─── RUN TIMER ────────────────────────────────────────────────
local function createRunTimer(parent: Frame)
	local container = plate(parent, {
		Name = "RunTimer",
		Size = UDim2.fromOffset(236, 62),
		Position = UDim2.new(0.5, 0, 0, 12),
		AnchorPoint = Vector2.new(0.5, 0),
		ZIndex = 10,
	})
	diamond(container, 10, UDim2.fromScale(0, 0.5), 12)
	diamond(container, 10, UDim2.fromScale(1, 0.5), 12)
	diamond(container, 8, UDim2.fromScale(0.5, 0), 12)
	diamond(container, 8, UDim2.fromScale(0.5, 1), 12)

	makeLabel({
		Name = "Title",
		Parent = container,
		Size = UDim2.new(1, -12, 0, 16),
		Position = UDim2.new(0, 6, 0, 8),
		Text = "TIME SURVIVED",
		FontFace = SERIF,
		TextSize = 12,
		TextColor = C.TextGold,
		ZIndex = 11,
	})

	runTimerText = makeLabel({
		Name = "Time",
		Parent = container,
		Size = UDim2.new(1, -12, 0, 30),
		Position = UDim2.new(0, 6, 0, 24),
		Text = "00:00",
		FontFace = SERIF,
		TextSize = 28,
		TextColor = C.TextWhite,
		ZIndex = 11,
	})

	runTierText = makeLabel({
		Name = "Tier",
		Parent = container,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, 10),
		Text = "Threat I",
		FontFace = SERIF_BOLD,
		TextSize = 12,
		TextColor = C.Threat,
		ZIndex = 11,
		StrokeTransparency = 0.3,
	})
end

-- ─── MENU PLATE ───────────────────────────────────────────────
local function createMenuPlate(parent: Frame)
	local box = plate(parent, {
		Name = "MenuPlate",
		Size = UDim2.fromOffset(58, 66),
		Position = UDim2.new(1, -22, 1, -BOTTOM_MARGIN),
		AnchorPoint = Vector2.new(1, 1),
		ZIndex = 10,
	})
	diamond(box, 8, UDim2.fromScale(0.5, 0), 12)
	for i = -1, 1 do
		local bar = makeFrame({
			Name = "MenuBar",
			Parent = box,
			Size = UDim2.fromOffset(26, 3),
			Position = UDim2.new(0.5, 0, 0, 24 + i * 8),
			AnchorPoint = Vector2.new(0.5, 0.5),
			BgColor = C.Gold,
			ZIndex = 11,
		})
		UITheme.AddCorner(bar, 1)
	end
	makeLabel({
		Name = "Key",
		Parent = box,
		Size = UDim2.new(1, 0, 0, 16),
		Position = UDim2.new(0, 0, 1, -20),
		Text = "Tab",
		FontFace = SERIF,
		TextSize = 13,
		TextColor = C.TextKeybind,
		ZIndex = 11,
	})
	-- Clicking the plate does the same as pressing Tab: the full dungeon map.
	local hit = Instance.new("TextButton")
	hit.Name = "Click"
	hit.Size = UDim2.fromScale(1, 1)
	hit.BackgroundTransparency = 1
	hit.Text = ""
	hit.ZIndex = 12
	hit.Parent = box
	hit.Activated:Connect(function()
		local ok, MinimapUI = pcall(require, script.Parent:WaitForChild("MinimapUI"))
		if ok then MinimapUI.ToggleFullMap() end
	end)
end

-- ─── HP UPDATE LOGIC ──────────────────────────────────────────
local function updateHPDisplay(animate: boolean?)
	if not hpFill or not hpTrail or not hpText then return end

	-- The shield is the top part of max HP: red covers health up to the base
	-- max, white covers whatever is above it.
	local shield = math.clamp(tonumber(player:GetAttribute("Stat_shield")) or 0, 0, maxHP)
	local baseMax = maxHP - shield
	local redFraction = if maxHP > 0 then math.clamp(math.min(currentHP, baseMax) / maxHP, 0, 1) else 0
	local whiteFraction = if maxHP > 0 then math.clamp(math.max(0, currentHP - baseMax) / maxHP, 0, 1) else 0

	local tweenInfo = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(hpFill, tweenInfo, { Size = UDim2.new(redFraction, 0, 1, 0) }):Play()
	if shieldFill then
		TweenService:Create(shieldFill, tweenInfo, {
			Position = UDim2.new(redFraction, 0, 0, 0),
			Size = UDim2.new(whiteFraction, 0, 1, 0),
		}):Play()
	end

	hpText.Text = string.format("%d / %d", math.floor(currentHP), math.floor(maxHP))

	-- Flash effect on damage
	if animate and displayTrailHP > currentHP then
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

local ROMAN = { "I", "II", "III", "IV", "V", "VI", "VII", "VIII", "IX", "X" }
local function tierLabel(tier: number): string
	if tier <= 0 then return "Threat I" end
	if tier <= #ROMAN then return "Threat " .. ROMAN[tier] end
	return "Threat " .. tostring(tier + 1)
end

local function updateRunTimer()
	local elapsed = RunScope.Mine("RunElapsed") or 0
	local tier = RunScope.Mine("RunTier") or 0
	if runTimerText then
		local mins = math.floor(elapsed / 60)
		local secs = elapsed % 60
		runTimerText.Text = string.format("%02d:%02d", mins, secs)
	end
	if runTierText then
		runTierText.Text = tierLabel(tier)
	end
end

local function onHeartbeat(dt: number)
	updateRunTimer()
	updateAmmoCylinder(dt)
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
		local fraction = if maxHP > 0 then math.clamp(currentHP / maxHP, 0, 1) else 0
		hpTrail.Size = UDim2.new(fraction, 0, 1, 0)
	end
end

-- ─── GOLD ─────────────────────────────────────────────────────
-- Counts up/down to the new total with a green/red flash and a little pop.
local function onGoldChanged()
	local target = player:GetAttribute("Gold") or 0
	local gained = target > shownGold
	goldText.TextColor3 = if gained then Color3.fromRGB(150, 255, 150) else Color3.fromRGB(255, 120, 120)
	goldScale.Scale = if gained then 1.15 else 0.92
	TweenService:Create(goldScale, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	if countingGold then return end
	countingGold = true
	task.spawn(function()
		while shownGold ~= (player:GetAttribute("Gold") or 0) do
			local goal = player:GetAttribute("Gold") or 0
			local step = math.max(1, math.ceil(math.abs(goal - shownGold) / 8))
			shownGold += if goal > shownGold then step else -step
			if math.abs(goal - shownGold) < step then shownGold = goal end
			goldText.Text = tostring(shownGold)
			task.wait(0.025)
		end
		goldText.TextColor3 = C.TextWhite
		countingGold = false
	end)
end

-- ─── CHARACTER HEALTH BINDING ─────────────────────────────────
local function bindToCharacter(character: Model)
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
	humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		maxHP = humanoid.MaxHealth
		currentHP = humanoid.Health
		updateHPDisplay(false)
	end)
end

-- ─── PUBLIC API ───────────────────────────────────────────────

-- Apply the per-class skill icons (skillIndex 1-4) to the bar.
function GameHUD.SetClassIcons(classId: string?)
	for i = 1, 4 do
		local slot = skillSlots[i]
		if slot and slot.icon then
			local assetId = getSkillIcon(classId, i)
			if assetId and assetId ~= "" then
				slot.icon.Image = assetId
				slot.icon.ImageColor3 = Color3.new(1, 1, 1)
				slot.icon.ImageTransparency = 0
			else
				slot.icon.Image = ""
				slot.icon.ImageColor3 = C.TextGold
				slot.icon.ImageTransparency = 0.6
			end
		end
	end
end

-- ── Teammates' health ───────────────────────────────────────────────────────
-- For every co-op party member in the run: a small slanted green bar with
-- their HP number floating beside their character, and a green copy of our
-- own health bar stacked above the Tab plate (bottom-right).
local TEAM_GREEN = Color3.fromRGB(70, 200, 95)
local TEAM_GREEN_BRIGHT = Color3.fromRGB(150, 245, 150)
local TEAM_BAR_WIDTH = 250
local TEAM_BAR_HEIGHT = 24
local TEAM_BAR_GAP = 44

type TeamEntry = {
	player: Player,
	hud: Frame,
	hudFill: Frame,
	hudText: TextLabel,
	world: BillboardGui?,
	worldFill: Frame?,
	worldText: TextLabel?,
	conns: { RBXScriptConnection },
}
local teamEntries: { [number]: TeamEntry } = {}
local teamHudParent: Frame? = nil
local partyIds: { number } = {}

local function teamHudBar(parent: Frame, name: string): (Frame, Frame, TextLabel)
	local box = makeFrame({
		Name = "TeamBar",
		Parent = parent,
		Size = UDim2.fromOffset(TEAM_BAR_WIDTH, TEAM_BAR_HEIGHT + 18),
		AnchorPoint = Vector2.new(1, 1),
		BgTransparency = 1,
		ZIndex = 10,
	})
	makeLabel({
		Name = "Name",
		Parent = box,
		Size = UDim2.new(1, -8, 0, 16),
		Text = string.upper(name),
		FontFace = SERIF_BOLD,
		TextSize = 12,
		TextColor = C.TextGold,
		TextXAlignment = Enum.TextXAlignment.Right,
		ZIndex = 11,
		StrokeTransparency = 0.4,
	})
	local bar = makeFrame({
		Name = "Bar",
		Parent = box,
		Size = UDim2.fromOffset(TEAM_BAR_WIDTH, TEAM_BAR_HEIGHT),
		Position = UDim2.new(0, 0, 1, 0),
		AnchorPoint = Vector2.new(0, 1),
		BgColor = C.StoneDark,
		BgTransparency = 0.15,
		ZIndex = 11,
	})
	UITheme.AddStroke(bar, C.Gold, 1.2, 0.2)
	diamond(bar, 11, UDim2.fromScale(0, 0.5), 15)
	fadeLine(bar, UDim2.new(1, 16, 0, 1), UDim2.new(0.5, -8, 0, -4), 12, C.GoldDim)
	local area = makeFrame({
		Name = "FillArea",
		Parent = bar,
		Size = UDim2.new(1, -16, 1, -6),
		Position = UDim2.new(0, 10, 0.5, 0),
		AnchorPoint = Vector2.new(0, 0.5),
		BgColor = Color3.fromRGB(8, 26, 12),
		ZIndex = 12,
		ClipsDescendants = true,
	})
	local fill = makeFrame({
		Name = "Fill",
		Parent = area,
		Size = UDim2.fromScale(1, 1),
		BgColor = Color3.new(1, 1, 1),
		ZIndex = 13,
	})
	UITheme.AddGradient(fill, TEAM_GREEN, TEAM_GREEN_BRIGHT, 0)
	local text = makeLabel({
		Name = "HpText",
		Parent = area,
		Size = UDim2.new(1, -10, 1, 0),
		Position = UDim2.fromOffset(10, 0),
		FontFace = SERIF_BOLD,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 14,
		StrokeTransparency = 0.4,
	})
	return box, fill, text
end

-- The small slanted bar beside a teammate (like a shooter's ally marker).
local function teamWorldBar(root: BasePart): (BillboardGui, Frame, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Name = "TeamHealth"
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(54, 78)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 0.6, 0)
	bb.StudsOffset = Vector3.new(2.6, 0, 0) -- to the right, on screen
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.MaxDistance = 150
	bb.Parent = player:WaitForChild("PlayerGui")
	local frame = makeFrame({
		Name = "Slant",
		Parent = bb,
		Size = UDim2.fromOffset(12, 64),
		Position = UDim2.fromOffset(6, 6),
		BgColor = Color3.fromRGB(12, 14, 12),
		BgTransparency = 0.2,
		Rotation = 14,
		ZIndex = 2,
		ClipsDescendants = true,
	})
	UITheme.AddStroke(frame, Color3.new(1, 1, 1), 1.2, 0.2)
	local fill = makeFrame({
		Name = "Fill",
		Parent = frame,
		Size = UDim2.fromScale(1, 1),
		Position = UDim2.fromScale(0, 1),
		AnchorPoint = Vector2.new(0, 1),
		BgColor = TEAM_GREEN_BRIGHT,
		ZIndex = 3,
	})
	local text = makeLabel({
		Name = "Hp",
		Parent = bb,
		Size = UDim2.fromOffset(40, 18),
		Position = UDim2.fromOffset(18, 30),
		FontFace = SERIF_BOLD,
		TextSize = 15,
		TextXAlignment = Enum.TextXAlignment.Left,
		ZIndex = 4,
		StrokeTransparency = 0.2,
	})
	return bb, fill, text
end

local function layoutTeamBars()
	local i = 0
	for _, id in ipairs(partyIds) do
		local e = teamEntries[id]
		if e then
			e.hud.Position = UDim2.new(1, -22, 1, -(BOTTOM_MARGIN + 66 + 16 + i * TEAM_BAR_GAP))
			i += 1
		end
	end
end

local function dropTeammate(id: number)
	local e = teamEntries[id]
	if not e then return end
	for _, c in ipairs(e.conns) do c:Disconnect() end
	e.hud:Destroy()
	if e.world then e.world:Destroy() end
	teamEntries[id] = nil
end

local function bindTeamCharacter(e: TeamEntry, char: Model)
	if e.world then e.world:Destroy() e.world = nil end
	local hum = char:WaitForChild("Humanoid", 5) :: Humanoid?
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not hum or not root or not e.hud.Parent then return end
	local bb, fill, text = teamWorldBar(root)
	e.world, e.worldFill, e.worldText = bb, fill, text
	local function update()
		local frac = if hum.MaxHealth > 0 then math.clamp(hum.Health / hum.MaxHealth, 0, 1) else 0
		local ti = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(e.hudFill, ti, { Size = UDim2.fromScale(frac, 1) }):Play()
		e.hudText.Text = string.format("%d / %d", math.max(0, math.floor(hum.Health)), math.floor(hum.MaxHealth))
		TweenService:Create(fill, ti, { Size = UDim2.fromScale(1, frac) }):Play()
		text.Text = tostring(math.max(0, math.floor(hum.Health)))
		-- Down: grey it out.
		local down = hum.Health <= 0
		text.TextColor3 = if down then Color3.fromRGB(150, 150, 150) else C.TextWhite
		e.hudText.TextColor3 = text.TextColor3
	end
	table.insert(e.conns, hum.HealthChanged:Connect(update))
	table.insert(e.conns, hum:GetPropertyChangedSignal("MaxHealth"):Connect(update))
	update()
end

local function addTeammate(plr: Player)
	if teamEntries[plr.UserId] or not teamHudParent then return end
	local hud, fill, text = teamHudBar(teamHudParent, plr.DisplayName)
	local e: TeamEntry = { player = plr, hud = hud, hudFill = fill, hudText = text, conns = {} }
	teamEntries[plr.UserId] = e
	table.insert(e.conns, plr.CharacterAdded:Connect(function(c) bindTeamCharacter(e, c) end))
	if plr.Character then task.spawn(bindTeamCharacter, e, plr.Character) end
end

-- Party members (from PartyState) who are in the run, other than us.
local function refreshTeam()
	local want: { [number]: boolean } = {}
	for _, id in ipairs(partyIds) do
		local plr = Players:GetPlayerByUserId(id)
		if plr and plr ~= player and plr:GetAttribute("InLobby") == false then
			want[id] = true
			addTeammate(plr)
		end
	end
	for id in pairs(teamEntries) do
		if not want[id] then dropTeammate(id) end
	end
	layoutTeamBars()
end

local function createTeamBars(parent: Frame)
	teamHudParent = parent
	local Network = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Network"))
	Network.GetRemoteEvent(Network.Remotes.PartyState).OnClientEvent:Connect(function(payload: any)
		partyIds = {}
		if typeof(payload) == "table" and typeof(payload.members) == "table" then
			for _, m in ipairs(payload.members) do
				if typeof(m) == "table" and typeof(m.userId) == "number" then table.insert(partyIds, m.userId) end
			end
		end
		refreshTeam()
	end)
	Network.GetRemoteEvent(Network.Remotes.PartyAction):FireServer({ kind = "request" })
	-- Teammates entering / leaving the run.
	task.spawn(function()
		while true do
			task.wait(1)
			refreshTeam()
		end
	end)
	Players.PlayerRemoving:Connect(function(p) dropTeammate(p.UserId) end)
end

function GameHUD.Init()
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

	-- Create the ScreenGui (initially hidden until player spawns into map)
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "GameHUD"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 50
	screenGui.Enabled = false
	screenGui.Parent = playerGui

	createVignette(playerGui)

	-- Main HUD frame (full screen, invisible, just a container)
	hudFrame = makeFrame({
		Name = "HUDContainer",
		Parent = screenGui,
		Size = UDim2.new(1, 0, 1, 0),
		BgTransparency = 1,
		ZIndex = 1,
	})

	createHealthBar(hudFrame)
	-- Your tomes' logos, in a strip just above the health bar.
	pcall(function()
		local TomeIcons = require(script.Parent:WaitForChild("TomeIcons"))
		local row = TomeIcons.Row(hudFrame, 34)
		row.AnchorPoint = Vector2.new(0, 1)
		row.Position = UDim2.new(0, 70, 1, -(BOTTOM_MARGIN + EMBLEM_SIZE * math.sqrt(2) + 18))
		row.ZIndex = 12
	end)
	createSkillBar(hudFrame)
	createRunTimer(hudFrame)
	createMenuPlate(hudFrame)
	createTeamBars(hudFrame)
	createAmmoCylinder(hudFrame)

	-- Apply class-specific skill icons and keep them in sync when class changes
	GameHUD.SetClassIcons(player:GetAttribute("SelectedClass"))
	player:GetAttributeChangedSignal("SelectedClass"):Connect(function()
		GameHUD.SetClassIcons(player:GetAttribute("SelectedClass"))
	end)

	-- Gold
	shownGold = player:GetAttribute("Gold") or 0
	goldText.Text = tostring(shownGold)
	goldConn = player:GetAttributeChangedSignal("Gold"):Connect(onGoldChanged)

	-- Shield Tomes change how much of the bar is white.
	player:GetAttributeChangedSignal("Stat_shield"):Connect(function()
		updateHPDisplay(false)
	end)

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

	heartbeatConn = RunService.Heartbeat:Connect(onHeartbeat)

	print("[GameHUD] Initialized successfully.")
end

-- Set skill cooldown display (call from combat system)
-- skillIndex: 1-4, remaining: seconds left, total: total cooldown
function GameHUD.SetSkillCooldown(skillIndex: number, remaining: number, total: number)
	local slot = skillSlots[skillIndex]
	if not slot then return end

	if remaining <= 0 then
		-- Skill ready: pulse the glow ring
		slot.cooldownOverlay.Size = UDim2.new(1, 0, 0, 0)
		slot.cooldownText.Text = ""
		TweenService:Create(slot.glowStroke, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Transparency = 0.15,
		}):Play()
		task.delay(0.5, function()
			if slot.glowStroke then
				TweenService:Create(slot.glowStroke, TweenInfo.new(0.8), {
					Transparency = 0.8,
				}):Play()
			end
		end)
	else
		local fraction = math.clamp(remaining / total, 0, 1)
		slot.cooldownOverlay.Size = UDim2.new(1, 0, fraction, 0)
		slot.cooldownText.Text = string.format("%.1f", remaining)
		slot.glowStroke.Transparency = 1
	end
end

-- Set skill keybind labels on HUD
function GameHUD.SetKeybinds(keybinds: any)
	if typeof(keybinds) ~= "table" then return end
	for slotIndex = 1, 4 do
		local slot = skillSlots[slotIndex]
		if slot and slot.keybindLabel then
			local key = keybinds[`Skill{slotIndex}`] or (slotIndex == 1 and "E" or slotIndex == 2 and "F" or slotIndex == 3 and "Q" or "R")
			slot.keybindLabel.Text = key
		end
	end
end

-- Show / hide the HUD
function GameHUD.SetVisible(visible: boolean)
	if screenGui then
		screenGui.Enabled = visible
	end
	if vignetteGui then
		vignetteGui.Enabled = visible
	end
end

-- Cleanup
function GameHUD.Destroy()
	if heartbeatConn then heartbeatConn:Disconnect() end
	if healthConn then healthConn:Disconnect() end
	if characterConn then characterConn:Disconnect() end
	if goldConn then goldConn:Disconnect() end
	if screenGui then screenGui:Destroy() end
	if vignetteGui then vignetteGui:Destroy() end
	skillSlots = {}
end

return GameHUD
