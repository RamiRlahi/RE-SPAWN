--[[
	SummonScreen.luau
	The summon page: dark fantasy panels (deep black / violet, a little antique
	gold), rarity colours, the class-select fonts (KeepFont).

	  header   BACK, SUMMON, the banner tabs, the currency bar
	  left     the featured reward: a big live portrait (RewardPreview in a
	           ViewportFrame), its name, rarity, rate-up and time left, the
	           Legendary pity and Starlight meters, EXCHANGE and RATES
	  right    the class collection as portrait cards (3 x 2, paged), tabs
	           COLLECTION / SHOP / HISTORY; VIEW ALL CLASSES
	  bottom   the daily free wish and SUMMON ×1 / ×10 / ×25 (Pull Tickets)

	  pages    COLLECTION (every class card, sets, variants, armor, titles...),
	           SHOP (class unlocks, the Essence Shop, Pull Ticket packs) and
	           HISTORY: full-width pages that replace the panels while open

	Rates & Pity is generated from GachaConfig, so it always matches the
	server. Summons play ConstellationWish, then the results (click a card to
	preview it at the statue).

	Portraits are built only while the page is open (RewardPreview models in
	WorldModels) and cleaned up when it closes or the banner switches.

	Gamepad / keyboard: every button is selectable; B / Backspace backs out
	(overlay, then page, then the screen); LB / RB switch banners.

	SummonScreen.Open() / SummonScreen.Close()
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GuiService = game:GetService("GuiService")
local UserInputService = game:GetService("UserInputService")
local ContextActionService = game:GetService("ContextActionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local MapData = require(Shared:WaitForChild("MapData"))
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))
local SummonCinematic = require(script.Parent.Parent:WaitForChild("SummonCinematic"))
local ConstellationWish = require(script.Parent.Parent:WaitForChild("ConstellationWish"))
local LobbyCamera = require(script.Parent.Parent:WaitForChild("LobbyCamera"))
local RewardPreview = require(script.Parent.Parent:WaitForChild("RewardPreview"))

local player = Players.LocalPlayer
local areaCheckThread: thread? = nil

-- ─── Look ───────────────────────────────────────────────────────────────────
local C = {
	Panel = Color3.fromRGB(13, 10, 19),
	PanelTop = Color3.fromRGB(29, 19, 40),
	Inset = Color3.fromRGB(8, 6, 12),
	Raised = Color3.fromRGB(34, 25, 46),
	Line = Color3.fromRGB(74, 54, 98),
	Gold = Color3.fromRGB(214, 176, 104),
	GoldLight = Color3.fromRGB(255, 226, 160),
	GoldDim = Color3.fromRGB(128, 100, 62),
	Violet = Color3.fromRGB(160, 100, 255),
	Starlight = Color3.fromRGB(130, 150, 255),
	TextPrimary = Color3.fromRGB(242, 236, 248),
	TextSecondary = Color3.fromRGB(198, 186, 212),
	TextMuted = Color3.fromRGB(132, 120, 150),
	Ink = Color3.fromRGB(6, 4, 9),
	Danger = Color3.fromRGB(240, 100, 110),
}
local F = {
	Display = Font.new("rbxasset://fonts/families/AccanthisADFStd.json", Enum.FontWeight.Bold),
	Head = Font.new("rbxasset://fonts/families/AccanthisADFStd.json", Enum.FontWeight.Regular),
	UI = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Medium),
	UIBold = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold),
}
-- The layout is drawn on a DESIGN_W × DESIGN_H (or larger) canvas, scaled to fit.
local DESIGN_W, DESIGN_H = 1440, 820
-- Phones and other small windows: a tighter canvas (less room round you at the
-- statue, shorter panels) so the text stays readable.
local COMPACT_W, COMPACT_H = 1180, 640
local M = 24 -- edge margin
local HEADER_H = 64
local BOTTOM_H = 168 -- the summon bar's band
local CARDS_PER_PAGE = 6

local SummonScreen = {}

type Card = { button: TextButton, vp: ViewportFrame, entry: any, refresh: () -> (), key: any }
type Action = { text: string, onClick: () -> (), on: boolean?, gold: boolean? }

local state: any = { currencies = {}, collection = { characters = {}, relics = {}, cosmetics = {} }, equipped = { relics = {}, variants = {} }, pity = {}, products = {} }
local gui: ScreenGui? = nil
local refreshers: { () -> () } = {}
local pulling = false
-- The banner the page shows (its tabs switch it); each has its own pity.
local currentBanner = GachaConfig.DefaultBanner
local conns: { RBXScriptConnection } = {}
local isOpen = false
-- Live portrait cleanups (models in viewports), emptied on close / rebuild.
local portraitCleanups: { [any]: () -> () } = {}
-- Set by build(): the back action (overlay → page → close) and banner stepping.
local backAction: () -> () = function() end
local onOpened: () -> () = function() end
local onClosed: () -> () = function() end
local selectionFrame: Frame? = nil

local function bannerPity(): any
	return (state.pityAll and state.pityAll[currentBanner]) or (if currentBanner == GachaConfig.DefaultBanner then state.pity else nil) or {}
end
local setComplete: (string) -> () = function(_setId: string) end

-- ─── Small builders ─────────────────────────────────────────────────────────
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in pairs(props) do (i :: any)[k] = v end
	if parent then i.Parent = parent end
	return i
end
local function corner(p: Instance, r: number | UDim)
	return new("UICorner", { CornerRadius = if typeof(r) == "UDim" then r else UDim.new(0, r :: number) }, p)
end
local function stroke(p: Instance, color: Color3, thickness: number?, transparency: number?): UIStroke
	return new("UIStroke", { Color = color, Thickness = thickness or 1, Transparency = transparency or 0, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, p)
end
local function vgrad(p: Instance, top: Color3, bottom: Color3, rotation: number?): UIGradient
	return new("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = rotation or 90 }, p)
end
-- Transparency ramp that fades both ends (hairlines, glows).
local FADE_ENDS = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) })

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = F.UI, TextColor3 = C.TextPrimary, TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Center,
		TextStrokeColor3 = C.Ink, TextStrokeTransparency = 0.7,
	})
	for k, v in pairs(props) do (t :: any)[k] = v end
	t.Parent = parent
	return t
end
local function maxText(t: TextLabel | TextButton, max: number, min: number?)
	t.TextScaled = true
	new("UITextSizeConstraint", { MaxTextSize = max, MinTextSize = min or 8 }, t)
end

-- Tiny vector icons (Unicode symbols don't render in these fonts).
local function diamond(parent: Instance, size: number, color: Color3, props: { [string]: any }?): Frame
	local d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), Rotation = 45, BackgroundColor3 = color, BorderSizePixel = 0 }, nil)
	for k, v in pairs(props or {}) do (d :: any)[k] = v end
	d.Parent = parent
	return d
end
local function sparkle(parent: Instance, size: number, color: Color3, props: { [string]: any }?): Frame
	local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, nil)
	for k, v in pairs(props or {}) do (f :: any)[k] = v end
	diamond(f, size * 0.3, color, { Position = UDim2.fromScale(0.5, 0.5) })
	for _, horizontal in ipairs({ true, false }) do
		local bar = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = if horizontal then UDim2.new(1, 0, 0, 2) else UDim2.new(0, 2, 1, 0), BackgroundColor3 = color, BorderSizePixel = 0 }, f)
		new("UIGradient", { Transparency = FADE_ENDS, Rotation = if horizontal then 0 else 90 }, bar)
	end
	f.Parent = parent
	return f
end
local function chevron(parent: Instance, dir: string, size: number, color: Color3, props: { [string]: any }?): Frame
	local f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 }, nil)
	for k, v in pairs(props or {}) do (f :: any)[k] = v end
	local s = if dir == ">" then 1 else -1
	for i, rot in ipairs({ 45, -45 }) do
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.5, (if i == 1 then -1 else 1) * size * 0.2),
			Size = UDim2.fromOffset(size * 0.58, 2), Rotation = rot * s, BackgroundColor3 = color, BorderSizePixel = 0, Name = "Bar" }, f)
	end
	f.Parent = parent
	return f
end
local function currencyIcon(parent: Instance, key: string, props: { [string]: any }?): Frame
	local f = new("Frame", { Size = UDim2.fromOffset(22, 22), BackgroundTransparency = 1 }, nil)
	for k, v in pairs(props or {}) do (f :: any)[k] = v end
	if key == "tickets" then
		local t = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(20, 13), Rotation = -18,
			BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, f)
		corner(t, 2)
		vgrad(t, Color3.fromRGB(255, 226, 150), Color3.fromRGB(196, 140, 60))
		new("Frame", { Position = UDim2.new(0.3, 0, 0.15, 0), Size = UDim2.new(0, 1, 0.7, 0), BackgroundColor3 = Color3.fromRGB(110, 70, 30), BorderSizePixel = 0 }, t)
	elseif key == "soulEssence" then
		local d = diamond(f, 15, Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.5, 0.5) })
		vgrad(d, Color3.fromRGB(226, 170, 255), Color3.fromRGB(120, 60, 220), 45)
		diamond(f, 6, Color3.fromRGB(245, 225, 255), { Position = UDim2.new(0.5, -2, 0.5, -2) })
	elseif key == "soulShards" then
		local d = diamond(f, 14, Color3.new(1, 1, 1), { Position = UDim2.fromScale(0.5, 0.5) })
		vgrad(d, Color3.fromRGB(255, 220, 120), Color3.fromRGB(205, 130, 40), 45)
		new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(2, 18), BackgroundColor3 = Color3.fromRGB(255, 244, 210),
			BackgroundTransparency = 0.3, BorderSizePixel = 0 }, f)
	else -- relicDust: a little cluster of violet sparks
		sparkle(f, 18, Color3.fromRGB(200, 150, 255), { Position = UDim2.fromScale(0.42, 0.45) })
		diamond(f, 4, Color3.fromRGB(230, 200, 255), { Position = UDim2.fromScale(0.82, 0.8) })
		diamond(f, 3, Color3.fromRGB(230, 200, 255), { Position = UDim2.fromScale(0.15, 0.85) })
	end
	f.Parent = parent
	return f
end
local function lockIcon(parent: Instance, color: Color3, props: { [string]: any }?): Frame
	local f = new("Frame", { Size = UDim2.fromOffset(14, 17), BackgroundTransparency = 1 }, nil)
	for k, v in pairs(props or {}) do (f :: any)[k] = v end
	local sh = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.fromOffset(9, 10), BackgroundTransparency = 1 }, f)
	corner(sh, UDim.new(0.5, 0))
	stroke(sh, color, 2)
	local body = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.fromOffset(14, 10), BackgroundColor3 = color, BorderSizePixel = 0 }, f)
	corner(body, 2)
	f.Parent = parent
	return f
end
local function clockIcon(parent: Instance, color: Color3, props: { [string]: any }?): Frame
	local f = new("Frame", { Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1 }, nil)
	for k, v in pairs(props or {}) do (f :: any)[k] = v end
	corner(f, UDim.new(0.5, 0))
	stroke(f, color, 1.6)
	new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(2, 6), BackgroundColor3 = color, BorderSizePixel = 0 }, f)
	new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0.47, 0.5), Size = UDim2.fromOffset(5, 2), BackgroundColor3 = color, BorderSizePixel = 0 }, f)
	f.Parent = parent
	return f
end
-- A gold hairline fading out at both ends, with a small diamond in the middle.
local function ornamentRule(parent: Instance, props: { [string]: any }): Frame
	local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, 0, 0, 8) }, nil)
	for k, v in pairs(props) do (f :: any)[k] = v end
	local line = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.fromScale(0, 0.5), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Gold,
		BorderSizePixel = 0, BackgroundTransparency = 0.35 }, f)
	new("UIGradient", { Transparency = FADE_ENDS }, line)
	diamond(f, 5, C.Gold, { Position = UDim2.fromScale(0.5, 0.5) })
	f.Parent = parent
	return f
end

-- A dark panel: violet-black gradient, a fine violet border; `gold` adds a gold
-- hairline along the top and small corner brackets (the main panels only).
local function panel(parent: Instance, props: { [string]: any }, gold: boolean?): (Frame, UIStroke)
	local f = new("Frame", { BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.06, BorderSizePixel = 0 }, nil)
	for k, v in pairs(props) do (f :: any)[k] = v end
	corner(f, 6)
	vgrad(f, C.PanelTop, C.Panel)
	local s = stroke(f, C.Line, 1, 0.15)
	if gold then
		local top = new("Frame", { Name = "GoldLine", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0), Size = UDim2.new(0.8, 0, 0, 1),
			BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, f)
		new("UIGradient", { Transparency = FADE_ENDS }, top)
		for _, c in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
			local holder = new("Frame", { Name = "Bracket", AnchorPoint = c, Position = UDim2.new(c.X, if c.X == 0 then -3 else 3, c.Y, if c.Y == 0 then -3 else 3),
				Size = UDim2.fromOffset(16, 16), BackgroundTransparency = 1 }, f)
			new("Frame", { AnchorPoint = Vector2.new(c.X, c.Y), Position = UDim2.fromScale(c.X, c.Y), Size = UDim2.new(1, 0, 0, 2), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, holder)
			new("Frame", { AnchorPoint = Vector2.new(c.X, c.Y), Position = UDim2.fromScale(c.X, c.Y), Size = UDim2.new(0, 2, 1, 0), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, holder)
		end
	end
	f.Parent = parent
	return f, s
end

-- Buttons. kind: "gold" (the main action), "dark" (secondary), "tab".
type ButtonKind = "gold" | "dark" | "tab"
local function setButtonEnabled(b: GuiButton, on: boolean)
	b:SetAttribute("Disabled", not on)
	local t = b :: any
	if b:IsA("TextButton") then t.TextTransparency = if on then 0 else 0.45 end
end
local function button(parent: Instance, text: string, kind: ButtonKind, props: { [string]: any }, onClick: () -> ()): (TextButton, UIStroke)
	local b = new("TextButton", { AutoButtonColor = false, Text = text, FontFace = F.UIBold, TextSize = 14, BorderSizePixel = 0,
		BackgroundColor3 = Color3.new(1, 1, 1), TextColor3 = C.TextPrimary, Selectable = true }, nil)
	corner(b, 4)
	local s: UIStroke
	if kind == "gold" then
		vgrad(b, Color3.fromRGB(255, 222, 150), Color3.fromRGB(172, 120, 50))
		s = stroke(b, C.GoldLight, 1.5, 0.1)
		b.TextColor3 = Color3.fromRGB(40, 22, 8)
	elseif kind == "tab" then
		b.BackgroundTransparency = 1
		b.TextColor3 = C.TextSecondary
		b.TextStrokeColor3 = C.Ink
		b.TextStrokeTransparency = 0.35
		s = stroke(b, C.Line, 1, 1)
	else
		-- (solid: a UIGradient on a TextButton would tint its text too)
		b.BackgroundColor3 = Color3.fromRGB(27, 20, 37)
		s = stroke(b, C.Line, 1, 0)
	end
	for k, v in pairs(props) do (b :: any)[k] = v end
	local sc = new("UIScale", {}, b)
	if selectionFrame then b.SelectionImageObject = selectionFrame end
	local baseT = s.Transparency
	b.MouseEnter:Connect(function()
		if b:GetAttribute("Disabled") then return end
		SoundManager.PlayHover()
		TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1.03 }):Play()
		s.Transparency = 0
		if kind ~= "gold" then s.Color = C.Gold end
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play()
		s.Transparency = baseT
		if kind ~= "gold" then s.Color = C.Line end
	end)
	b.MouseButton1Down:Connect(function()
		if b:GetAttribute("Disabled") then return end
		TweenService:Create(sc, TweenInfo.new(0.06), { Scale = 0.97 }):Play()
	end)
	b.Activated:Connect(function()
		TweenService:Create(sc, TweenInfo.new(0.1), { Scale = 1 }):Play()
		if b:GetAttribute("Disabled") then return end
		SoundManager.PlaySelect()
		onClick()
	end)
	b.Parent = parent
	return b, s
end

local function rarityColor(r: string?): Color3
	return r and GachaConfig.Rarities[r] and GachaConfig.Rarities[r].color or C.TextSecondary
end
-- Whether any reward of this type is currently in the game (relics are
-- switched off for now; their section and rules hide while none exist).
local function hasRewardType(kind: string): boolean
	for _, r in ipairs(GachaRewards.All) do
		if r.type == kind then return true end
	end
	return false
end

local function owned(id: string): boolean
	local r = GachaRewards.Get(id)
	if not r then return false end
	if r.type == "class" then return (state.classes or {})[r.classId] == true end
	if r.type == "character" or r.type == "variant" then return state.collection.characters[id] ~= nil end
	if r.type == "relic" then return state.collection.relics[id] ~= nil end
	if r.type == "cosmetic" or r.type == "armor" or r.type == "wings" or r.type == "mount" then return state.collection.cosmetics[id] == true end
	return false
end
local function displayName(r: any): string
	if r.secret and not owned(r.id) then return "??? (secret)" end
	return r.name
end

-- A starter's two letters (they have no gacha glyph): initials, or the first
-- and third letter when that would clash with a gacha class's glyph.
local function fallbackGlyph(name: string): string
	local words = string.split(name, " ")
	local g = if #words > 1 then string.sub(words[1], 1, 1) .. string.sub(words[2], 1, 1) else string.sub(name, 1, 2)
	g = string.upper(g)
	for _, r in ipairs(GachaRewards.All) do
		if r.glyph == g then return string.upper(string.sub(name, 1, 1) .. string.sub(name, 3, 3)) end
	end
	return g
end

-- Every playable class with its gacha reward (nil for the starters).
local function classEntries(): { any }
	local list = {}
	for _, classId in ipairs(ClassData.Order) do
		local info = ClassData.GetClass(classId)
		if info and ClassData.IsPlayable(classId) then
			local cr
			for _, r in ipairs(GachaRewards.All) do
				if r.type == "class" and r.classId == classId then cr = r end
			end
			table.insert(list, {
				classId = classId, name = info.name, reward = cr,
				rarity = if cr then cr.rarity else "Common",
				glyph = if cr then cr.glyph else fallbackGlyph(info.name),
				starter = table.find(ClassData.Starter, classId) ~= nil,
			})
		end
	end
	return list
end

-- While the summon page is open, every other ScreenGui is hidden (no overlap).
local hiddenGuis: { ScreenGui } = {}
local function hideOtherGuis(hide: boolean)
	if hide then
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and g ~= gui then
				g.Enabled = false
				table.insert(hiddenGuis, g)
			end
		end
	else
		for _, g in ipairs(hiddenGuis) do
			if g.Parent then g.Enabled = true end
		end
		table.clear(hiddenGuis)
	end
end

-- ─── Portraits ──────────────────────────────────────────────────────────────
-- A reward's showcase model (RewardPreview) live in a viewport. "bust" frames
-- head and shoulders (the cards), "full" the whole figure (the featured panel).
local function clearPortrait(key: any)
	local c = portraitCleanups[key]
	if c then
		portraitCleanups[key] = nil
		pcall(c)
	end
end
local function clearAllPortraits()
	for key in pairs(portraitCleanups) do clearPortrait(key) end
end
local FIGURE_TYPES = { class = true, character = true, variant = true, armor = true }
local function setPortrait(key: any, vp: ViewportFrame, reward: any, mode: string)
	clearPortrait(key)
	local world = vp:FindFirstChildOfClass("WorldModel") or new("WorldModel", {}, vp)
	local cam = vp.CurrentCamera
	if not cam then
		cam = new("Camera", { FieldOfView = 30 }, vp)
		vp.CurrentCamera = cam
	end
	local ok, model, cleanup = pcall(RewardPreview.Build, reward)
	if not ok or not model then return end
	portraitCleanups[key] = cleanup
	local figure = FIGURE_TYPES[reward.type] == true
	if figure then
		-- (rigs face -Z: turned to the camera, a little to the side)
		model:PivotTo(CFrame.Angles(0, math.pi + math.rad(if mode == "bust" then 16 else 22), 0))
	end
	model.Parent = world -- (poses once it's in a world)
	local camera = cam :: Camera
	if figure then
		if mode == "bust" then
			camera.FieldOfView = 30
			local target = Vector3.new(0, 1.2, 0)
			camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 0.3, 7.6), target)
		else
			camera.FieldOfView = 30
			local target = Vector3.new(0, 0.1, 0)
			camera.CFrame = CFrame.lookAt(target + Vector3.new(0, 0.8, 15.5), target)
		end
	else
		local center, ext = model:GetBoundingBox()
		local size = math.max(ext.X, ext.Y, ext.Z, 3)
		camera.FieldOfView = 32
		-- (as the Wardrobe frames them: straight on, far enough for the whole span)
		camera.CFrame = CFrame.lookAt(center.Position + Vector3.new(0, size * 0.18, size * (if mode == "bust" then 1.6 else 2.0) + 2), center.Position)
	end
end

-- ─── Build ──────────────────────────────────────────────────────────────────
local function build(): ScreenGui
	local sg = Instance.new("ScreenGui")
	sg.Name = "SummonScreen"
	sg.DisplayOrder = 50
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Enabled = false
	sg.Parent = player:WaitForChild("PlayerGui")

	-- The gamepad's selection outline (gold).
	local sel = new("Frame", { Name = "Selection", BackgroundTransparency = 1, Size = UDim2.new(1, 8, 1, 8), Position = UDim2.fromOffset(-4, -4) }, nil)
	corner(sel, 6)
	stroke(sel, C.GoldLight, 2.5, 0)
	selectionFrame = sel

	-- Darkened edges so the panels read; the middle (you, at the statue) stays clear.
	for _, side in ipairs({ 0, 1 }) do
		local v = new("Frame", { AnchorPoint = Vector2.new(side, 0), Position = UDim2.fromScale(side, 0), Size = UDim2.fromScale(0.42, 1),
			BackgroundColor3 = C.Ink, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, sg)
		new("UIGradient", { Rotation = if side == 0 then 0 else 180,
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(0.6, 0.75), NumberSequenceKeypoint.new(1, 1) }) }, v)
	end
	local topShade = new("Frame", { Size = UDim2.new(1, 0, 0, 150), BackgroundColor3 = C.Ink, BackgroundTransparency = 0.2, BorderSizePixel = 0 }, sg)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new(0.1, 1) }, topShade)
	local bottomShade = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 220), BackgroundColor3 = C.Ink,
		BackgroundTransparency = 0.2, BorderSizePixel = 0 }, sg)
	new("UIGradient", { Rotation = -90, Transparency = NumberSequence.new(0.15, 1) }, bottomShade)

	-- The canvas: below Roblox's top bar, scaled so DESIGN_W × DESIGN_H always fits.
	local root = new("Frame", { Name = "Root", BackgroundTransparency = 1 }, sg)
	root:SetAttribute("KeepFont", true) -- (FontStyle: this screen keeps its own fonts)
	local rootScale = new("UIScale", {}, root)
	local canvas = Vector2.new(DESIGN_W, DESIGN_H)
	local relayoutCbs: { () -> () } = {}
	local function relayout()
		local cam = workspace.CurrentCamera
		if not cam then return end
		local vs = cam.ViewportSize
		local inset = GuiService:GetGuiInset()
		local w, h = vs.X, math.max(1, vs.Y - inset.Y)
		local dw, dh = DESIGN_W, DESIGN_H
		if h < 600 or w < 1000 then dw, dh = COMPACT_W, COMPACT_H end
		local s = math.clamp(math.min(w / dw, h / dh), 0.4, 1.6)
		rootScale.Scale = s
		root.Position = UDim2.fromOffset(0, inset.Y)
		canvas = Vector2.new(w / s, h / s)
		root.Size = UDim2.fromOffset(canvas.X, canvas.Y)
		for _, f in ipairs(relayoutCbs) do f() end
	end
	if workspace.CurrentCamera then
		table.insert(conns, workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout))
	end

	local function act(payload: any)
		Network.GetRemoteEvent(Network.Remotes.GachaAction):FireServer(payload)
	end

	-- ── Header ──
	local header = new("Frame", { Name = "Header", BackgroundTransparency = 1, Position = UDim2.fromOffset(M, 6), Size = UDim2.new(1, -2 * M, 0, HEADER_H - 10) }, root)
	local backBtn = button(header, "BACK", "dark", { Name = "Back", Position = UDim2.new(0, 0, 0.5, -20), Size = UDim2.fromOffset(92, 40), TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right }, function() backAction() end)
	new("UIPadding", { PaddingRight = UDim.new(0, 16) }, backBtn)
	chevron(backBtn, "<", 14, C.TextSecondary, { Position = UDim2.new(0, 18, 0.5, 0) })
	sparkle(header, 34, C.Gold, { Position = UDim2.new(0, 124, 0.5, 0) })
	local title = label(header, { Text = "SUMMON", FontFace = F.Display, TextSize = 34, TextColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(146, 0), Size = UDim2.new(0, 160, 1, 0), TextStrokeTransparency = 0.4 })
	vgrad(title, Color3.fromRGB(255, 236, 190), Color3.fromRGB(205, 150, 70))
	new("Frame", { Position = UDim2.new(0, 304, 0.5, -16), Size = UDim2.fromOffset(1, 32), BackgroundColor3 = C.GoldDim, BorderSizePixel = 0, BackgroundTransparency = 0.3 }, header)

	-- Banner tabs: each banner keeps its own pity, shown on its page.
	local tabs = new("Frame", { Name = "BannerTabs", BackgroundTransparency = 1, Position = UDim2.fromOffset(318, 0), Size = UDim2.new(0, 640, 1, 0) }, header)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center }, tabs)
	local bannerTabs: { [string]: TextButton } = {}
	for i, id in ipairs(GachaConfig.BannerOrder) do
		local b = GachaConfig.Banners[id]
		if b then
			local active = id == currentBanner
			local tab = button(tabs, string.upper(b.name), "tab", { Name = "Banner_" .. id, Size = UDim2.fromOffset(196, 40), TextSize = 13, LayoutOrder = i,
				TextColor3 = if active then C.GoldLight else C.TextSecondary }, function()
				if pulling or id == currentBanner then return end
				SummonScreen.SetBanner(id)
			end)
			bannerTabs[id] = tab
			tab.TextWrapped = true
			if active then
				local u = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.86, 0, 0, 2), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, tab)
				new("UIGradient", { Transparency = FADE_ENDS }, u)
				local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(1, 0, 1, 0), BackgroundColor3 = C.Gold,
					BackgroundTransparency = 0.82, BorderSizePixel = 0, ZIndex = 0 }, tab)
				new("UIGradient", { Rotation = -90, Transparency = NumberSequence.new(0.2, 1) }, glow)
				diamond(tab, 6, C.GoldLight, { Position = UDim2.new(0.5, 0, 1, 0) })
			end
		end
	end

	-- Currency bar: one compact strip, icon + amount + label per currency.
	local currencyBar = new("Frame", { Name = "Currencies", AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(0, 46),
		AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.1, BorderSizePixel = 0 }, header)
	corner(currencyBar, 6)
	vgrad(currencyBar, Color3.fromRGB(26, 18, 36), Color3.fromRGB(12, 9, 18))
	stroke(currencyBar, C.Line, 1, 0.1)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, SortOrder = Enum.SortOrder.LayoutOrder, VerticalAlignment = Enum.VerticalAlignment.Center }, currencyBar)
	new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, currencyBar)
	local amounts: { [string]: TextLabel } = {}
	local CURRENCY_LABEL = { tickets = "TICKETS", soulEssence = "ESSENCE", soulShards = "SHARDS", relicDust = "DUST" }
	for i, key in ipairs({ "tickets", "soulEssence", "soulShards", "relicDust" }) do
		if i > 1 then
			new("Frame", { LayoutOrder = i * 2 - 1, Size = UDim2.fromOffset(1, 26), BackgroundColor3 = C.Line, BorderSizePixel = 0, BackgroundTransparency = 0.2 }, currencyBar)
		end
		local cell = new("Frame", { Name = key, LayoutOrder = i * 2, Size = UDim2.fromOffset(108, 46), BackgroundTransparency = 1 }, currencyBar)
		currencyIcon(cell, key, { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0) })
		amounts[key] = label(cell, { Text = "0", FontFace = F.UIBold, TextSize = 17, Position = UDim2.fromOffset(40, 6), Size = UDim2.new(1, -44, 0, 20) })
		label(cell, { Text = CURRENCY_LABEL[key], FontFace = F.UIBold, TextSize = 9, TextColor3 = C.TextMuted, Position = UDim2.fromOffset(40, 26), Size = UDim2.new(1, -44, 0, 12) })
	end
	table.insert(refreshers, function()
		for key, t in pairs(amounts) do
			local n = state.currencies[key] or 0
			t.Text = if n >= 100000 then string.format("%.1fk", n / 1000) else tostring(n)
		end
	end)
	-- (narrow canvases: the tabs shrink so they never run under the currency bar)
	table.insert(relayoutCbs, function()
		local room = canvas.X - 2 * M - 318 - currencyBar.AbsoluteSize.X / rootScale.Scale - 16
		local w = math.clamp(math.floor((room - 8) / 3), 84, 196)
		for _, t in pairs(bannerTabs) do
			t.Size = UDim2.fromOffset(w, 40)
			-- (narrow tabs: smaller type, long names wrap onto two lines)
			t.TextSize = if w >= 170 then 13 elseif w >= 130 then 11 else 10
		end
	end)
	currencyBar:GetPropertyChangedSignal("AbsoluteSize"):Connect(relayout)

	-- ── Left: the featured reward ──
	local banner = GachaConfig.Banners[currentBanner]
	local featuredId = GachaConfig.FeaturedFor(currentBanner)
	local featured = featuredId and GachaRewards.Get(featuredId)
	local featuredRarity = banner.featuredRarity or "Legendary"
	local SPARK = GachaConfig.SparkFor(currentBanner)
	local P = GachaConfig.PityFor(currentBanner)
	local ODDS = GachaConfig.OddsFor(currentBanner)
	local fColor = featured and (featured.accent or rarityColor(featured.rarity)) or C.Gold
	local fRarityColor = featured and rarityColor(featured.rarity) or C.Gold

	local PANEL_TOP = HEADER_H + 10
	local left = panel(root, { Name = "Featured", Position = UDim2.fromOffset(M, PANEL_TOP), Size = UDim2.new(0, 392, 1, -(PANEL_TOP + BOTTOM_H)) }, true)
	label(left, { Text = "FEATURED", FontFace = F.UIBold, TextSize = 14, Position = UDim2.fromOffset(16, 10), Size = UDim2.fromOffset(160, 24) })
	if banner.featuredRotation then
		local days = math.ceil(GachaConfig.RotationIn() / 86400)
		local timeRow = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -16, 0, 10), Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 1 }, left)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center,
			SortOrder = Enum.SortOrder.LayoutOrder }, timeRow)
		clockIcon(timeRow, C.GoldLight, { LayoutOrder = 1 })
		label(timeRow, { LayoutOrder = 2, Text = `{days}d left`, FontFace = F.UIBold, TextSize = 13, TextColor3 = C.GoldLight, Size = UDim2.fromOffset(0, 24),
			AutomaticSize = Enum.AutomaticSize.X })
	end
	-- The portrait stage: an energy backdrop in the featured colour, the figure
	-- live in a viewport, the name over a dark fade at its foot.
	local STATS_H = 186
	local stage = new("Frame", { Name = "Stage", Position = UDim2.fromOffset(10, 40), Size = UDim2.new(1, -20, 1, -(40 + STATS_H)), BackgroundColor3 = C.Inset,
		BorderSizePixel = 0, ClipsDescendants = true }, left)
	corner(stage, 4)
	stroke(stage, fColor, 1, 0.55)
	local wash = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, stage)
	new("UIGradient", { Rotation = 115, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, fColor:Lerp(C.Ink, 0.35)), ColorSequenceKeypoint.new(0.55, fColor:Lerp(C.Ink, 0.78)),
		ColorSequenceKeypoint.new(1, C.Ink) }) }, wash)
	for i, spec in ipairs({ { 0.18, 0.2, 3 }, { 0.62, 0.35, 2 }, { 0.82, 0.62, 5 }, { 0.3, 0.75, 2 } }) do
		local streak = new("Frame", { Name = "Streak" .. i, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(spec[1], spec[2]), Size = UDim2.new(1.4, 0, 0, spec[3]),
			Rotation = -32, BackgroundColor3 = fColor:Lerp(Color3.new(1, 1, 1), 0.3), BackgroundTransparency = 0.55, BorderSizePixel = 0 }, stage)
		new("UIGradient", { Transparency = FADE_ENDS }, streak)
	end
	local floorGlow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.86), Size = UDim2.new(0.8, 0, 0, 60), BackgroundColor3 = fColor,
		BackgroundTransparency = 0.45, BorderSizePixel = 0 }, stage)
	corner(floorGlow, UDim.new(0.5, 0))
	new("UIGradient", { Transparency = FADE_ENDS }, floorGlow)
	local featuredVp = new("ViewportFrame", { Name = "Portrait", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 135, 170),
		LightColor = Color3.fromRGB(255, 240, 225), LightDirection = Vector3.new(-0.5, -0.8, -0.6) }, stage)
	local fade = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0.5), BackgroundColor3 = C.Ink, BorderSizePixel = 0 }, stage)
	new("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.55, 0.45), NumberSequenceKeypoint.new(1, 1) }) }, fade)
	if featured then
		local glyph = label(stage, { Text = featured.glyph, FontFace = F.Display, TextSize = 64, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -64), Size = UDim2.new(1, 0, 0, 60), TextStrokeTransparency = 0.3 })
		vgrad(glyph, Color3.new(1, 1, 1):Lerp(fRarityColor, 0.35), fRarityColor)
		local name = label(stage, { Text = string.upper(featured.name), FontFace = F.Display, TextColor3 = C.TextPrimary, TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -36), Size = UDim2.new(1, -20, 0, 30), TextStrokeTransparency = 0.4 })
		maxText(name, 28, 14)
		local pill = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = fRarityColor:Lerp(C.Ink, 0.75), BackgroundTransparency = 0.1, BorderSizePixel = 0 }, stage)
		corner(pill, UDim.new(0.5, 0))
		stroke(pill, fRarityColor, 1, 0.3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14) }, pill)
		label(pill, { Text = `{string.upper(featured.rarity)}   ·   RATE UP {math.floor(banner.featuredRate * 100)}%`, FontFace = F.UIBold, TextSize = 12,
			TextColor3 = fRarityColor:Lerp(Color3.new(1, 1, 1), 0.25), Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X })
	end

	-- Pity + Starlight + EXCHANGE / RATES.
	local stats = new("Frame", { Name = "Stats", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 16, 1, -12), Size = UDim2.new(1, -32, 0, STATS_H - 22),
		BackgroundTransparency = 1 }, left)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, stats)
	-- A meter row: its title and count over a rounded bar (an optional tick
	-- where the Legendary odds start to rise).
	local function meter(order: number, titleText: string, color: Color3, tickAt: number?): (Frame, TextLabel, TextLabel)
		local row = new("Frame", { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 34), BackgroundTransparency = 1 }, stats)
		local tag = label(row, { Text = titleText, FontFace = F.UIBold, TextSize = 11, TextColor3 = C.TextSecondary, Size = UDim2.new(0.6, 0, 0, 16) })
		local count = label(row, { FontFace = F.UIBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Right, AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.4, 0, 0, 16) })
		local trough = new("Frame", { Position = UDim2.fromOffset(0, 20), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = C.Inset, BorderSizePixel = 0 }, row)
		corner(trough, UDim.new(0.5, 0))
		stroke(trough, C.Line, 1, 0.3)
		local fill = new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, trough)
		corner(fill, UDim.new(0.5, 0))
		vgrad(fill, color:Lerp(Color3.new(1, 1, 1), 0.3), color:Lerp(C.Ink, 0.15), 0)
		local shine = new("Frame", { Size = UDim2.new(1, 0, 0.4, 0), Position = UDim2.fromScale(0, 0.12), BackgroundColor3 = Color3.new(1, 1, 1), BackgroundTransparency = 0.7, BorderSizePixel = 0 }, fill)
		corner(shine, UDim.new(0.5, 0))
		if tickAt then
			new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(tickAt, 0.5), Size = UDim2.new(0, 2, 1, 6), BackgroundColor3 = C.GoldLight,
				BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 3 }, trough)
		end
		return fill, count, tag
	end
	local legFill, legText, legTag = meter(1, "LEGENDARY PITY", rarityColor("Legendary"), P.legendarySoftStart / P.legendaryHard)
	local pityText = label(stats, { LayoutOrder = 2, TextSize = 11, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 14) })
	local sparkFill, sparkText = meter(3, "STARLIGHT", C.Starlight)
	local btnRow = new("Frame", { Name = "Buttons", LayoutOrder = 4, Size = UDim2.new(1, 0, 0, 42), BackgroundTransparency = 1 }, stats)
	new("Frame", { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 2), BackgroundTransparency = 1 }, stats)
	local sparkBtn = button(btnRow, "EXCHANGE", "dark", { Name = "Exchange", Position = UDim2.fromOffset(0, 4), Size = UDim2.new(0.5, -5, 0, 38), TextSize = 13 }, function() end)
	local ratesBtn = button(btnRow, "RATES & DETAILS", "dark", { Name = "Rates", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.new(0.5, -5, 0, 38),
		TextSize = 13 }, function() end)
	table.insert(refreshers, function()
		local pity = bannerPity()
		local since = pity.sinceLegendary or 0
		TweenService:Create(legFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(since / P.legendaryHard, 0.001, 1), 1) }):Play()
		legText.Text = `{since} / {P.legendaryHard}`
		local rising = since >= P.legendarySoftStart
		legTag.Text = if rising then "LEGENDARY PITY  ·  ODDS RISING" else "LEGENDARY PITY"
		legTag.TextColor3 = if rising then C.GoldLight else C.TextSecondary
		local bits = { `Epic in {math.max(0, P.epicEvery - (pity.sinceEpic or 0))}` }
		if P.mythicHard then table.insert(bits, `Mythic in {math.max(0, P.mythicHard - (pity.sinceMythic or 0))}`) end
		if pity.guaranteedFeatured then table.insert(bits, `next {featuredRarity} is featured`) end
		pityText.Text = table.concat(bits, "   ·   ")
		local sl = pity.starlight or 0
		local cost = SPARK.cost
		TweenService:Create(sparkFill, TweenInfo.new(0.4, Enum.EasingStyle.Quad), { Size = UDim2.fromScale(math.clamp(sl / cost, 0.001, 1), 1) }):Play()
		sparkText.Text = `{sl} / {cost}`
		sparkBtn.TextColor3 = if sl >= cost then C.GoldLight else C.TextPrimary
	end)

	-- ── Right: the collection ──
	local right = panel(root, { Name = "Collection", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -M, 0, PANEL_TOP), Size = UDim2.new(0, 452, 1, -(PANEL_TOP + BOTTOM_H)) }, true)
	local showPage: (string) -> () = function(_name: string) end
	-- COLLECTION / SHOP / HISTORY: a tab strip (here and on the pages).
	local function tabStrip(parent: Instance, active: string, props: { [string]: any }): Frame
		local strip = new("Frame", { BackgroundTransparency = 1 }, nil)
		for k, v in pairs(props) do (strip :: any)[k] = v end
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, strip)
		for i, name in ipairs({ "Collection", "Shop", "History" }) do
			local on = name == active
			local b, s = button(strip, string.upper(name), "dark", { Name = "Tab_" .. name, LayoutOrder = i, Size = UDim2.new(1 / 3, -4, 1, 0), TextSize = 13,
				TextColor3 = if on then C.GoldLight else C.TextSecondary }, function()
				showPage(name)
			end)
			if on then
				s.Color = C.Gold
				s.Transparency = 0.2
				local u = new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.7, 0, 0, 2), BackgroundColor3 = C.Gold, BorderSizePixel = 0 }, b)
				new("UIGradient", { Transparency = FADE_ENDS }, u)
			end
		end
		strip.Parent = parent
		return strip
	end
	tabStrip(right, "Collection", { Name = "Tabs", Position = UDim2.fromOffset(14, 14), Size = UDim2.new(1, -28, 0, 40) })

	-- A class portrait card. Owned: full colour; locked: darkened figure + a
	-- lock; starter / in use: a small tag; focused: a gold ring, raised.
	local focusClass: string? = nil
	local cardsByClass: { [string]: { Card } } = {}
	local infoRefresh: () -> () = function() end
	local function classCard(parent: Instance, entry: any, order: number, key: any): Card
		local col = rarityColor(entry.rarity)
		local b = new("TextButton", { Name = "Card_" .. entry.classId, LayoutOrder = order, AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0, Selectable = true, SelectionImageObject = selectionFrame }, parent)
		corner(b, 5)
		local bg = vgrad(b, col:Lerp(C.Ink, 0.55), C.Inset)
		bg.Transparency = NumberSequence.new(0)
		local s = stroke(b, col, 1.5, 0.2)
		local sc = new("UIScale", {}, b)
		local vp = new("ViewportFrame", { Name = "Portrait", Size = UDim2.new(1, 0, 1, -52), BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 135, 170),
			LightColor = Color3.fromRGB(255, 240, 225), LightDirection = Vector3.new(-0.5, -0.8, -0.6) }, b)
		local fadeF = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 92), BackgroundColor3 = C.Ink, BorderSizePixel = 0 }, b)
		corner(fadeF, 5)
		new("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1) }) }, fadeF)
		local glyph = label(b, { Text = entry.glyph, FontFace = F.Display, TextSize = 26, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.new(1, 0, 0, 26), TextStrokeTransparency = 0.3 })
		local nameL = label(b, { Text = string.upper(entry.name), FontFace = F.UIBold, TextColor3 = C.TextPrimary, TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -17), Size = UDim2.new(1, -8, 0, 13) })
		maxText(nameL, 11, 7)
		local rar = label(b, { Text = string.upper(entry.rarity), FontFace = F.UIBold, TextSize = 10, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, 0, 0, 12) })
		local tag = new("Frame", { Name = "Tag", Position = UDim2.fromOffset(5, 5), Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundColor3 = C.Ink, BackgroundTransparency = 0.25, BorderSizePixel = 0, Visible = false }, b)
		corner(tag, 3)
		new("UIPadding", { PaddingLeft = UDim.new(0, 5), PaddingRight = UDim.new(0, 5) }, tag)
		local tagL = label(tag, { FontFace = F.UIBold, TextSize = 9, Size = UDim2.fromOffset(0, 16), AutomaticSize = Enum.AutomaticSize.X })
		local lock = lockIcon(b, C.TextSecondary, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -7, 0, 7), Visible = false })
		local ring = new("Frame", { Name = "Ring", BackgroundTransparency = 1, Position = UDim2.fromOffset(-4, -4), Size = UDim2.new(1, 8, 1, 8), Visible = false }, b)
		corner(ring, 8)
		local ringS = stroke(ring, C.GoldLight, 2, 0)
		local pip = diamond(b, 9, C.GoldLight, { Position = UDim2.new(0.5, 0, 0, 0), Visible = false })
		local hovered = false
		local pulse: Tween? = nil
		local card: Card
		local function refresh()
			local have = entry.starter or (state.classes or {})[entry.classId] == true
			local focused = focusClass == entry.classId
			local inUse = player:GetAttribute("SelectedClass") == entry.classId
			vp.ImageColor3 = if have then Color3.new(1, 1, 1) else Color3.fromRGB(58, 52, 70)
			glyph.TextColor3 = if have then col else col:Lerp(C.TextMuted, 0.55)
			nameL.TextColor3 = if have then C.TextPrimary else C.TextMuted
			rar.Text = if have then string.upper(entry.rarity) else `{string.upper(entry.rarity)} · LOCKED`
			bg.Color = ColorSequence.new(if have then col:Lerp(C.Ink, 0.55) else col:Lerp(C.Ink, 0.85), C.Inset)
			lock.Visible = not have
			tag.Visible = inUse or entry.starter
			tagL.Text = if inUse then "IN USE" else "STARTER"
			tagL.TextColor3 = if inUse then C.GoldLight else C.TextSecondary
			s.Transparency = if focused or hovered then 0 elseif have then 0.25 else 0.6
			s.Thickness = if focused then 2 else 1.5
			ring.Visible = focused
			pip.Visible = focused
			if focused and not pulse then
				ringS.Transparency = 0
				pulse = TweenService:Create(ringS, TweenInfo.new(0.9, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.65 })
				;(pulse :: Tween):Play()
			elseif not focused and pulse then
				pulse:Cancel()
				pulse = nil
			end
			TweenService:Create(sc, TweenInfo.new(0.14), { Scale = if focused then 1.04 elseif hovered then 1.025 else 1 }):Play()
		end
		b.MouseEnter:Connect(function()
			hovered = true
			SoundManager.PlayHover()
			refresh()
		end)
		b.MouseLeave:Connect(function()
			hovered = false
			refresh()
		end)
		local function focus()
			if focusClass == entry.classId then return end
			focusClass = entry.classId
			for _, list in pairs(cardsByClass) do
				for _, c in ipairs(list) do c.refresh() end
			end
			infoRefresh()
		end
		b.SelectionGained:Connect(focus)
		b.Activated:Connect(function()
			SoundManager.PlaySelect()
			focus()
		end)
		card = { button = b, vp = vp, entry = entry, refresh = refresh, key = key }
		cardsByClass[entry.classId] = cardsByClass[entry.classId] or {}
		table.insert(cardsByClass[entry.classId], card)
		refresh()
		return card
	end
	local function dropCards(list: { Card })
		for _, c in ipairs(list) do
			clearPortrait(c.key)
			local l = cardsByClass[c.entry.classId]
			if l then
				local i = table.find(l, c)
				if i then table.remove(l, i) end
			end
			c.button:Destroy()
		end
		table.clear(list)
	end
	-- Fill cards' portraits a few per frame (a character copy each).
	local portraitGen = 0
	local function fillPortraits(list: { Card })
		portraitGen += 1
		local gen = portraitGen
		task.spawn(function()
			for _, c in ipairs(list) do
				if gen ~= portraitGen or not c.button.Parent or not isOpen then return end
				local reward = c.entry.reward or { id = "portrait_" .. c.entry.classId, type = "character", classId = c.entry.classId,
					rarity = c.entry.rarity, name = c.entry.name }
				setPortrait(c.key, c.vp, reward, "bust")
				task.wait()
			end
		end)
	end

	local GRID_TOP = 14 + 40 + 12
	local FOOTER_H = 72
	local grid = new("Frame", { Name = "Grid", Position = UDim2.fromOffset(14, GRID_TOP), Size = UDim2.new(1, -28, 1, -(GRID_TOP + FOOTER_H)), BackgroundTransparency = 1 }, right)
	new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -7, 0.5, -5), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center }, grid)
	local footer = new("Frame", { Name = "Footer", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 14, 1, -10), Size = UDim2.new(1, -28, 0, FOOTER_H - 14),
		BackgroundTransparency = 1 }, right)
	local infoL = label(footer, { TextSize = 12, TextColor3 = C.TextSecondary, Position = UDim2.fromOffset(0, 3), Size = UDim2.new(1, -120, 0, 22), TextTruncate = Enum.TextTruncate.AtEnd })
	local infoBtn = button(footer, "UNLOCK", "dark", { Name = "InfoAction", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 3), Size = UDim2.fromOffset(110, 24),
		TextSize = 11, TextColor3 = C.GoldLight, Visible = false }, function() showPage("Shop") end)
	local pageL = label(footer, { FontFace = F.UIBold, TextSize = 11, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
		Position = UDim2.fromOffset(34, 30), Size = UDim2.fromOffset(40, 28) })
	local prevBtn = button(footer, "", "dark", { Name = "PrevPage", Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(30, 28) }, function() end)
	chevron(prevBtn, "<", 12, C.TextSecondary, { Position = UDim2.fromScale(0.5, 0.5) })
	local nextBtn = button(footer, "", "dark", { Name = "NextPage", Position = UDim2.fromOffset(78, 30), Size = UDim2.fromOffset(30, 28) }, function() end)
	chevron(nextBtn, ">", 12, C.TextSecondary, { Position = UDim2.fromScale(0.5, 0.5) })
	local viewAll = button(footer, "VIEW ALL CLASSES", "tab", { Name = "ViewAll", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -22, 0, 30),
		Size = UDim2.fromOffset(200, 28), TextSize = 12, TextColor3 = C.TextPrimary, TextXAlignment = Enum.TextXAlignment.Right }, function() showPage("Collection") end)
	chevron(footer, ">", 12, C.Gold, { Position = UDim2.new(1, -8, 0, 44) })
	local vaLine = new("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -170 - 22, 0, 44), Size = UDim2.fromOffset(70, 1), BackgroundColor3 = C.Gold,
		BorderSizePixel = 0, BackgroundTransparency = 0.4 }, footer)
	new("UIGradient", { Transparency = NumberSequence.new(1, 0) }, vaLine)
	local _ = viewAll

	local homePage = 1
	local homeCards: { Card } = {}
	local function pageCount(): number
		return math.max(1, math.ceil(#classEntries() / CARDS_PER_PAGE))
	end
	local function buildHomeGrid()
		dropCards(homeCards)
		local all = classEntries()
		homePage = math.clamp(homePage, 1, pageCount())
		for i = (homePage - 1) * CARDS_PER_PAGE + 1, math.min(#all, homePage * CARDS_PER_PAGE) do
			table.insert(homeCards, classCard(grid, all[i], i, "home" .. i))
		end
		pageL.Text = `{homePage} / {pageCount()}`
		setButtonEnabled(prevBtn, homePage > 1)
		setButtonEnabled(nextBtn, homePage < pageCount())
		if isOpen then fillPortraits(homeCards) end
	end
	prevBtn.Activated:Connect(function()
		if homePage > 1 then
			homePage -= 1
			buildHomeGrid()
		end
	end)
	nextBtn.Activated:Connect(function()
		if homePage < pageCount() then
			homePage += 1
			buildHomeGrid()
		end
	end)
	infoRefresh = function()
		local entry
		for _, e in ipairs(classEntries()) do
			if e.classId == focusClass then entry = e end
		end
		if not entry then
			infoL.Text = "Select a class to see how to get it."
			infoL.TextColor3 = C.TextMuted
			infoBtn.Visible = false
			return
		end
		local have = entry.starter or (state.classes or {})[entry.classId] == true
		local status = if entry.starter then "starter class" elseif have then "owned · pick it at class selection" else "locked"
		infoL.Text = `{string.upper(entry.name)}  ·  {status}`
		infoL.TextColor3 = if have then C.TextSecondary else C.TextPrimary
		infoBtn.Visible = not have and entry.reward ~= nil
	end
	-- (class ownership changes the cards' look, not the cards)
	table.insert(refreshers, function()
		for _, list in pairs(cardsByClass) do
			for _, c in ipairs(list) do c.refresh() end
		end
		infoRefresh()
	end)
	table.insert(conns, player:GetAttributeChangedSignal("SelectedClass"):Connect(function()
		for _, list in pairs(cardsByClass) do
			for _, c in ipairs(list) do c.refresh() end
		end
	end))

	-- ── Rows (shop, history, the collection's other sections) ──
	local function sectionTag(parent: Instance, text: string, order: number)
		local f = new("Frame", { LayoutOrder = order, Size = UDim2.new(1, -6, 0, 28), BackgroundTransparency = 1 }, parent)
		label(f, { Text = string.upper(text), FontFace = F.UIBold, TextSize = 12, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(2, 2) })
		local u = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.GoldDim, BorderSizePixel = 0 }, f)
		new("UIGradient", { Transparency = NumberSequence.new(0, 1) }, u)
	end
	local function note(parent: Instance, text: string, order: number, color: Color3?)
		label(parent, { Text = text, TextSize = 12, TextColor3 = color or C.TextMuted, TextWrapped = true, LayoutOrder = order,
			Size = UDim2.new(1, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y })
	end
	local function itemRow(parent: Instance, order: number, r: any, info: string, actions: { Action }?, active: boolean?): Frame
		local col = rarityColor(r.rarity)
		local h = if actions and #actions > 1 then 70 else 56
		local row = new("Frame", { Name = "Row_" .. tostring(r.id or r.name), LayoutOrder = order, Size = UDim2.new(1, -6, 0, h), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, parent)
		corner(row, 4)
		vgrad(row, Color3.fromRGB(28, 21, 38), Color3.fromRGB(16, 12, 23), 0)
		stroke(row, if active then C.Gold else C.Line, 1, if active then 0 else 0.2)
		local badge = new("Frame", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 8, 0.5, 0), Size = UDim2.fromOffset(40, 40), BackgroundColor3 = Color3.new(1, 1, 1),
			BorderSizePixel = 0 }, row)
		corner(badge, 4)
		vgrad(badge, col:Lerp(C.Ink, 0.5), col:Lerp(C.Ink, 0.85))
		stroke(badge, col, 1, 0.25)
		local g = label(badge, { Text = r.glyph or "", FontFace = F.Display, TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.15), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
		maxText(g, 18, 8)
		local textW = if actions and #actions > 0 then -(58 + 140) else -66
		local n = label(row, { Text = displayName(r), FontFace = F.UIBold, TextSize = 13, Position = UDim2.new(0, 58, 0.5, -17), Size = UDim2.new(1, textW, 0, 18),
			TextTruncate = Enum.TextTruncate.AtEnd })
		local _ = n
		label(row, { Text = info, FontFace = F.UIBold, TextSize = 10, TextColor3 = col, Position = UDim2.new(0, 58, 0.5, 3), Size = UDim2.new(1, textW, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd })
		if actions then
			local n2 = #actions
			for i, a in ipairs(actions) do
				local bh = if n2 > 1 then 26 else 30
				local y = if n2 > 1 then (i - 1) * 30 - 28 else -15
				local b = button(row, a.text, if a.gold then "gold" else "dark", { Name = "Action" .. i, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0.5, y),
					Size = UDim2.fromOffset(132, bh), TextSize = 11, TextColor3 = if a.gold then Color3.fromRGB(40, 22, 8) elseif a.on == false then C.TextMuted else C.GoldLight }, a.onClick)
				maxText(b, 11, 7)
				new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, b)
			end
		end
		return row
	end
	local function scroller(parent: Instance, props: { [string]: any }, padding: number?): ScrollingFrame
		local s = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.GoldDim,
			AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y, Selectable = false }, nil)
		for k, v in pairs(props) do (s :: any)[k] = v end
		new("UIListLayout", { Padding = UDim.new(0, padding or 6), SortOrder = Enum.SortOrder.LayoutOrder }, s)
		new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingBottom = UDim.new(0, 8) }, s)
		s.Parent = parent
		return s
	end
	local function clear(f: Instance)
		for _, c in ipairs(f:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
	end

	-- ── Pages: COLLECTION / SHOP / HISTORY ──
	local pageFrame = panel(root, { Name = "Pages", Visible = false, Position = UDim2.fromOffset(M, PANEL_TOP), Size = UDim2.new(1, -2 * M, 1, -(PANEL_TOP + M)) }, true)
	local pageStrips: { [string]: Frame } = {}
	local pageBodies: { [string]: Frame } = {}
	for _, name in ipairs({ "Collection", "Shop", "History" }) do
		pageStrips[name] = tabStrip(pageFrame, name, { Name = "Tabs_" .. name, Visible = false, Position = UDim2.fromOffset(18, 16), Size = UDim2.fromOffset(540, 40) })
		pageBodies[name] = new("Frame", { Name = name, Visible = false, Position = UDim2.fromOffset(18, 70), Size = UDim2.new(1, -36, 1, -86), BackgroundTransparency = 1 }, pageFrame)
	end
	local toSummon = button(pageFrame, "BACK TO SUMMON", "dark", { Name = "BackToSummon", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 16),
		Size = UDim2.fromOffset(190, 40), TextSize = 13, TextXAlignment = Enum.TextXAlignment.Right }, function() showPage("Home") end)
	new("UIPadding", { PaddingRight = UDim.new(0, 18) }, toSummon)
	chevron(toSummon, "<", 12, C.TextSecondary, { Position = UDim2.new(0, 18, 0.5, 0) })

	-- COLLECTION page: every class card (left), the rest of the collection (right).
	local colBody = pageBodies.Collection
	local classHead = label(colBody, { FontFace = F.UIBold, TextSize = 13, TextColor3 = C.Gold, Size = UDim2.new(1, -470, 0, 22) })
	local classScroll = new("ScrollingFrame", { Name = "Classes", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, -470, 1, -30), BackgroundTransparency = 1,
		BorderSizePixel = 0, ScrollBarThickness = 4, ScrollBarImageColor3 = C.GoldDim, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y, Selectable = false }, colBody)
	local classGrid = new("UIGridLayout", { CellSize = UDim2.new(1 / 6, -12, 0, 226), CellPadding = UDim2.fromOffset(12, 12), SortOrder = Enum.SortOrder.LayoutOrder }, classScroll)
	-- (cards keep their shape whatever the page's width)
	new("UIAspectRatioConstraint", { AspectRatio = 0.63 }, classGrid)
	new("UIPadding", { PaddingTop = UDim.new(0, 6), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6), PaddingBottom = UDim.new(0, 8) }, classScroll)
	new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -452, 0, 0), Size = UDim2.new(0, 1, 1, 0), BackgroundColor3 = C.Line, BorderSizePixel = 0 }, colBody)
	local extras = scroller(colBody, { Name = "Extras", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 436, 1, 0) })
	local allCards: { Card } = {}
	local function buildAllCards()
		dropCards(allCards)
		local all = classEntries()
		local have = 0
		for i, e in ipairs(all) do
			if e.starter or (state.classes or {})[e.classId] == true then have += 1 end
			table.insert(allCards, classCard(classScroll, e, i, "all" .. i))
		end
		classHead.Text = `CLASSES  ·  {have} / {#all} OWNED`
		fillPortraits(allCards)
	end
	table.insert(refreshers, function()
		if colBody.Visible then
			local all = classEntries()
			local have = 0
			for _, e in ipairs(all) do
				if e.starter or (state.classes or {})[e.classId] == true then have += 1 end
			end
			classHead.Text = `CLASSES  ·  {have} / {#all} OWNED`
		end
	end)
	table.insert(refreshers, function()
		local pg = extras
		clear(pg)
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		sectionTag(pg, "Sets", nextOrder())
		for _, set in ipairs(GachaRewards.Sets) do
			local have = 0
			for _, id in ipairs(set.items) do
				if owned(id) then have += 1 end
			end
			local done = (state.setsDone or {})[set.id] == true
			itemRow(pg, nextOrder(), { glyph = set.glyph, name = set.name, rarity = if done then "Legendary" else "Rare" },
				if done then "COMPLETE" else `{have} / {#set.items} OWNED`, nil, done)
		end
		sectionTag(pg, "VFX Variants", nextOrder())
		local any = false
		local function variantRow(r: any, classId: string)
			local active = state.equipped.variants[classId] == r.id
			local className = (ClassData.GetClass(classId) or { name = classId }).name
			itemRow(pg, nextOrder(), r, `{string.upper(className)} · {string.upper(r.rarity)}`, { {
				text = if active then "UNEQUIP" else "EQUIP", on = true,
				onClick = function() act({ kind = "equipVariant", classId = classId, id = if active then nil else r.id }) end,
			} }, active)
		end
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "variant" and state.collection.characters[r.id] then
				any = true
				if r.classId then
					variantRow(r, r.classId)
				else
					-- Universal variant: one equip row per playable class.
					for _, classId in ipairs(ClassData.Order) do
						if ClassData.IsPlayable(classId) then variantRow(r, classId) end
					end
				end
			end
		end
		if not any then note(pg, "None yet. Summon to discover VFX variants.", nextOrder()) end
		if hasRewardType("relic") then
			sectionTag(pg, `Relics · {#state.equipped.relics}/{GachaConfig.RelicSlots} Equipped`, nextOrder())
			for _, r in ipairs(GachaRewards.All) do
				local o = r.type == "relic" and state.collection.relics[r.id]
				if o then
					local active = table.find(state.equipped.relics, r.id) ~= nil
					itemRow(pg, nextOrder(), r, `{string.upper(r.rarity)} · LEVEL {o.level}/{GachaConfig.Duplicates.maxRelicLevel}`, { {
						text = if active then "UNEQUIP" else "EQUIP", on = true,
						onClick = function() act({ kind = if active then "unequipRelic" else "equipRelic", id = r.id }) end,
					} }, active)
				end
			end
		end
		sectionTag(pg, "Armor", nextOrder())
		local anyArmor = false
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "armor" and state.collection.cosmetics[r.id] then
				anyArmor = true
				local worn = (state.equipped.armor or {})[r.classId] == r.id
				local className = (ClassData.GetClass(r.classId :: string) or { name = r.classId }).name
				itemRow(pg, nextOrder(), r, `{string.upper(className)} · {string.upper(r.rarity)}`, { {
					text = if worn then "UNEQUIP" else "EQUIP", on = true,
					onClick = function() act({ kind = "equipArmor", classId = r.classId, id = if worn then nil else r.id }) end,
				} }, worn)
			end
		end
		if not anyArmor then note(pg, "None yet. Summon to win each class's armor.", nextOrder()) end
		local awakened = false
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "character" and state.collection.characters[r.id] then
				if not awakened then sectionTag(pg, "Awakened Characters", nextOrder()) end
				awakened = true
				itemRow(pg, nextOrder(), r, "AWAKENED")
			end
		end
		local titles = false
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "cosmetic" and state.collection.cosmetics[r.id] then
				if not titles then sectionTag(pg, "Titles", nextOrder()) end
				titles = true
				itemRow(pg, nextOrder(), r, string.upper(r.rarity))
			end
		end
		sectionTag(pg, "Soul Shards", nextOrder())
		local per = GachaConfig.Duplicates.shardsPerSoul
		local shards = state.currencies.soulShards or 0
		local refine = button(pg, `REFINE  ·  {per} SHARDS → 1 SOUL   ({shards})`, "dark", { Name = "Refine", LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 38), TextSize = 12,
			TextColor3 = if shards >= per then C.GoldLight else C.TextMuted }, function()
			act({ kind = "refineShards" })
		end)
		maxText(refine, 12, 8)
	end)

	-- SHOP page: three columns.
	local shopBody = pageBodies.Shop
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 18), SortOrder = Enum.SortOrder.LayoutOrder }, shopBody)
	local shopCols: { ScrollingFrame } = {}
	for i = 1, 3 do
		local colF = new("Frame", { Name = ({ "Classes", "Essence", "Tickets" })[i], LayoutOrder = i, Size = UDim2.new(1 / 3, -12, 1, 0), BackgroundColor3 = C.Inset, BackgroundTransparency = 0.35, BorderSizePixel = 0 }, shopBody)
		corner(colF, 5)
		stroke(colF, C.Line, 1, 0.35)
		shopCols[i] = scroller(colF, { Name = "List", Position = UDim2.fromOffset(12, 10), Size = UDim2.new(1, -18, 1, -16) })
	end
	table.insert(refreshers, function()
		for _, c in ipairs(shopCols) do clear(c) end
		-- Direct class unlocks (fixed price, not random): Soul Essence or Robux.
		local pg = shopCols[1]
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end
		sectionTag(pg, "Unlock a Class", nextOrder())
		note(pg, "Fixed price, not random. Essence comes from duplicates.", nextOrder())
		local anyLocked = false
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "class" and not owned(r.id) then
				anyLocked = true
				local actions: { Action } = {}
				local price = GachaConfig.ClassEssencePrice[r.rarity]
				local have = state.currencies.soulEssence or 0
				if price then
					table.insert(actions, { text = `{price} ESSENCE`, on = have >= price, onClick = function()
						SoundManager.PlayConfirm()
						act({ kind = "unlockClass", classId = r.classId })
					end })
				end
				local robux = (state.classProducts or {})[r.classId]
				if robux then
					table.insert(actions, { text = `R$ {robux}`, on = true, onClick = function()
						SoundManager.PlayConfirm()
						act({ kind = "buyClassRobux", classId = r.classId })
					end })
				end
				itemRow(pg, nextOrder(), r, string.upper(r.rarity), actions)
			end
		end
		if not anyLocked then note(pg, "Every class is yours.", nextOrder(), C.Gold) end

		-- The Essence Shop (fixed price, not random).
		pg = shopCols[2]
		order = 0
		sectionTag(pg, "Essence Shop", nextOrder())
		for _, item in ipairs(GachaConfig.ShopItems) do
			local r = GachaRewards.Get(item.id)
			if r then
				if owned(r.id) then
					itemRow(pg, nextOrder(), r, `{string.upper(r.rarity)} · OWNED`, nil, true)
				else
					local actions: { Action } = {}
					for _, currency in ipairs({ "soulEssence", "relicDust" }) do
						local price = item.price[currency]
						if price then
							local have = state.currencies[currency] or 0
							table.insert(actions, { text = `{price} {GachaConfig.Currencies[currency].glyph}`, on = have >= price, onClick = function()
								SoundManager.PlayConfirm()
								act({ kind = "buyShopItem", id = r.id, pay = currency })
							end })
						end
					end
					itemRow(pg, nextOrder(), r, string.upper(r.rarity), actions)
				end
			end
		end

		pg = shopCols[3]
		order = 0
		sectionTag(pg, "Pull Tickets", nextOrder())
		local D = GachaConfig.TicketDrops
		local earn = `Ticket drops: mob 1/{math.floor(1 / D.normal + 0.5)}, elite 1/{math.floor(1 / D.elite + 0.5)}, Behemoth 1/{math.floor(1 / D.miniboss + 0.5)}, boss 1/{math.floor(1 / D.boss + 0.5)}.`
		if state.paidRestricted then
			note(pg, `Pull Ticket packs aren't available in your region.\n\n{earn}`, nextOrder(), C.TextSecondary)
		elseif #state.products == 0 then
			note(pg, `Pull Ticket packs are coming soon.\n\n{earn}`, nextOrder(), C.TextSecondary)
		else
			note(pg, earn, nextOrder())
			for _, prod in ipairs(state.products) do
				local row = new("Frame", { LayoutOrder = nextOrder(), Size = UDim2.new(1, -6, 0, 58), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0 }, pg)
				corner(row, 4)
				vgrad(row, Color3.fromRGB(30, 22, 40), Color3.fromRGB(16, 12, 23), 0)
				stroke(row, C.Line, 1, 0.2)
				currencyIcon(row, "tickets", { AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0) })
				label(row, { Text = prod.label, FontFace = F.UIBold, TextSize = 14, Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -170, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
				button(row, `R$ {prod.robux}`, "gold", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(110, 36), TextSize = 14 }, function()
					SoundManager.PlayConfirm()
					act({ kind = "buyTickets", id = prod.id })
				end)
			end
		end
	end)

	-- HISTORY page: the last summons, newest first.
	local histBody = pageBodies.History
	local histHead = label(histBody, { FontFace = F.UIBold, TextSize = 13, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 22) })
	local histScroll = new("ScrollingFrame", { Name = "List", Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 1, -30), BackgroundTransparency = 1, BorderSizePixel = 0,
		ScrollBarThickness = 4, ScrollBarImageColor3 = C.GoldDim, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(),
		ScrollingDirection = Enum.ScrollingDirection.Y, Selectable = false }, histBody)
	new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -10, 0, 56), CellPadding = UDim2.fromOffset(10, 8), SortOrder = Enum.SortOrder.LayoutOrder }, histScroll)
	new("UIPadding", { PaddingTop = UDim.new(0, 2), PaddingLeft = UDim.new(0, 2), PaddingRight = UDim.new(0, 8) }, histScroll)
	table.insert(refreshers, function()
		clear(histScroll)
		local list = state.history or {}
		histHead.Text = `LAST {#list} SUMMONS   ·   {state.altarPulls or 0} AT THE ALTAR`
		if #list == 0 then
			note(histScroll, "No summons yet.", 1)
		end
		for i = #list, 1, -1 do
			local h = list[i]
			local r = GachaRewards.Get(h.id)
			if r then
				local b = GachaConfig.Banners[h.banner]
				local where = if b then b.name elseif h.banner == "robux" then "Robux unlock" else ""
				local row = itemRow(histScroll, #list - i + 1, r, `{string.upper(r.rarity)} · {string.upper(where)}`)
				row.Size = UDim2.fromScale(1, 1)
				label(row, { Text = os.date("!%d %b  %H:%M", h.time), TextSize = 10, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Right,
					AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 8), Size = UDim2.fromOffset(90, 14) })
			end
		end
	end)

	-- ── Bottom: the daily wish and the summon buttons ──
	local bottom = new("Frame", { Name = "SummonBar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14),
		Size = UDim2.fromOffset(940, BOTTOM_H - 20) }, root)
	local msg = label(bottom, { Text = "", TextXAlignment = Enum.TextXAlignment.Center, FontFace = F.UIBold, TextColor3 = C.Danger, TextSize = 13,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -6), Size = UDim2.new(0, 600, 0, 18) })
	local function doPull(count: number)
		if pulling then return end
		pulling = true
		msg.Text = ""
		SoundManager.PlayConfirm()
		Network.GetRemoteEvent(Network.Remotes.Summon):FireServer({ banner = currentBanner, count = count })
		task.delay(8, function() pulling = false end) -- safety if the server never answers
	end
	-- the rail the buttons sit on
	local rail = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -44), Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = C.Gold,
		BorderSizePixel = 0, BackgroundTransparency = 0.3 }, bottom)
	new("UIGradient", { Transparency = FADE_ENDS }, rail)
	diamond(bottom, 8, C.Gold, { Position = UDim2.new(0, 22, 1, -44) })
	diamond(bottom, 8, C.Gold, { Position = UDim2.new(1, -22, 1, -44) })
	local pulls: { [number]: { button: TextButton, cost: TextLabel, icon: Frame } } = {}
	local COSTS = { GachaConfig.Cost.single, GachaConfig.Cost.multi, GachaConfig.Cost.big }
	local slotX = { -290, 0, 290 }
	for i, cost in ipairs(COSTS) do
		local main = i == 2
		local w, h = if main then 290 else 250, if main then 84 else 72
		local b = button(bottom, "", if main then "gold" else "dark", { Name = `Summon{cost.count}`, AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, slotX[i], 1, -44), Size = UDim2.fromOffset(w, h) }, function() doPull(cost.count) end)
		if not main then
			local s = b:FindFirstChildOfClass("UIStroke") :: UIStroke
			s.Color = C.GoldDim
		else
			-- a soft glow round the main button
			local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 40, 1, 30), BackgroundColor3 = C.Gold,
				BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 0 }, bottom)
			corner(glow, 18)
			new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, glow)
			glow.Position = b.Position
			TweenService:Create(glow, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { BackgroundTransparency = 0.92 }):Play()
		end
		local textCol = if main then Color3.fromRGB(44, 24, 8) else C.TextPrimary
		label(b, { Text = `SUMMON ×{cost.count}`, FontFace = F.Display, TextSize = if main then 25 else 21, TextColor3 = textCol, TextXAlignment = Enum.TextXAlignment.Center,
			Position = UDim2.new(0, 0, 0.5, if main then -30 else -26), Size = UDim2.new(1, 0, 0, 30), TextStrokeTransparency = if main then 1 else 0.6 })
		local costRow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.5, 4), Size = UDim2.fromOffset(0, 22), AutomaticSize = Enum.AutomaticSize.X,
			BackgroundTransparency = 1 }, b)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, costRow)
		local icon = currencyIcon(costRow, "tickets", { LayoutOrder = 1 })
		local costL = label(costRow, { LayoutOrder = 2, Text = tostring(cost.tickets), FontFace = F.UIBold, TextSize = 16, TextColor3 = textCol, Size = UDim2.fromOffset(0, 22),
			AutomaticSize = Enum.AutomaticSize.X, TextStrokeTransparency = 1 })
		pulls[cost.count] = { button = b, cost = costL, icon = icon }
	end
	table.insert(refreshers, function()
		local free = GachaConfig.FREE_SUMMONS
		local have = state.currencies.tickets or 0
		for i, cost in ipairs(COSTS) do
			local p = pulls[cost.count]
			local can = free or have >= cost.tickets
			p.cost.Text = if free then "FREE" else tostring(cost.tickets)
			p.icon.Visible = not free
			p.cost.TextColor3 = if can then (if i == 2 then Color3.fromRGB(44, 24, 8) else C.TextPrimary) elseif i == 2 then Color3.fromRGB(150, 28, 36) else C.Danger
		end
	end)

	-- The daily wish: a pill over the buttons.
	local daily = new("TextButton", { Name = "Daily", AutoButtonColor = false, Text = "", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 14),
		Size = UDim2.fromOffset(330, 34), BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, Selectable = true, SelectionImageObject = selectionFrame }, bottom)
	corner(daily, 6)
	vgrad(daily, Color3.fromRGB(40, 26, 50), Color3.fromRGB(16, 11, 22))
	local dailyStroke = stroke(daily, C.GoldDim, 1, 0)
	local dailySpark = sparkle(daily, 22, C.Violet, { Position = UDim2.new(0, 22, 0.5, 0) })
	local dailyL = label(daily, { FontFace = F.UIBold, TextSize = 14, TextXAlignment = Enum.TextXAlignment.Center, Position = UDim2.fromOffset(30, 0), Size = UDim2.new(1, -44, 1, 0) })
	local dailyScale = new("UIScale", {}, daily)
	daily.MouseEnter:Connect(function()
		if state.freeAvailable then
			SoundManager.PlayHover()
			TweenService:Create(dailyScale, TweenInfo.new(0.12), { Scale = 1.04 }):Play()
		end
	end)
	daily.MouseLeave:Connect(function()
		TweenService:Create(dailyScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
	end)
	daily.Activated:Connect(function()
		if pulling or not state.freeAvailable then return end
		pulling = true
		msg.Text = ""
		SoundManager.PlayConfirm()
		Network.GetRemoteEvent(Network.Remotes.Summon):FireServer({ banner = currentBanner, count = 1, free = true })
		task.delay(8, function() pulling = false end)
	end)
	local syncedAt = os.clock()
	table.insert(refreshers, function()
		syncedAt = os.clock()
		daily.Visible = GachaConfig.DailyFree.enabled and bottom.Visible
	end)
	task.spawn(function()
		local lastFree: boolean? = nil
		while sg.Parent do
			if state.freeAvailable then
				dailyL.Text = "DAILY FREE AVAILABLE"
				dailyL.TextColor3 = C.GoldLight
			else
				local left2 = math.max(0, (state.nextFreeIn or 0) - (os.clock() - syncedAt))
				dailyL.Text = string.format("DAILY FREE IN  %dh %02dm", math.floor(left2 / 3600), math.floor(left2 % 3600 / 60))
				dailyL.TextColor3 = C.TextMuted
				if left2 <= 0 and sg.Enabled then Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer() end
			end
			local free = state.freeAvailable == true
			if free ~= lastFree then
				lastFree = free
				dailyStroke.Color = if free then C.Gold else C.Line
				for _, d in ipairs(dailySpark:GetDescendants()) do
					if d:IsA("Frame") then d.BackgroundColor3 = if free then C.GoldLight else C.TextMuted end
				end
			end
			task.wait(1)
		end
	end)

	-- ── Overlays (exchange, rates, results): a dimmed backdrop + a panel ──
	local overlays: { Frame } = {}
	local function overlay(name: string, size: UDim2, z: number): (Frame, Frame)
		local dim = new("TextButton", { Name = name, Visible = false, AutoButtonColor = false, Text = "", Size = UDim2.fromScale(1, 1), BackgroundColor3 = C.Ink,
			BackgroundTransparency = 0.22, BorderSizePixel = 0, ZIndex = z, Selectable = false }, root)
		local p = panel(dim, { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = size, ZIndex = z + 1, Active = true }, true)
		table.insert(overlays, dim)
		return dim, p
	end
	local function zAll(f: Instance, z: number)
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("GuiObject") and d.ZIndex < z then d.ZIndex = z end
		end
	end
	local function openOverlay(dim: Frame, focus: GuiObject?)
		dim.Visible = true
		local p = dim:FindFirstChildWhichIsA("Frame")
		if p then
			local sc = p:FindFirstChildOfClass("UIScale") or new("UIScale", {}, p)
			sc.Scale = 0.94
			TweenService:Create(sc, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end
		if focus and UserInputService.GamepadEnabled then GuiService.SelectedObject = focus end
	end

	-- Starlight exchange
	local sparkDim, spark = overlay("Exchange", UDim2.fromOffset(560, 600), 20)
	label(spark, { Text = "STARLIGHT EXCHANGE", FontFace = F.Display, TextSize = 26, TextColor3 = C.GoldLight, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 16) })
	local sparkSub = label(spark, { TextSize = 12, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
		Size = UDim2.new(1, -40, 0, 32), Position = UDim2.fromOffset(20, 50) })
	local sparkList = scroller(spark, { Position = UDim2.fromOffset(20, 88), Size = UDim2.new(1, -40, 1, -160) })
	local sparkClose = button(spark, "CLOSE", "dark", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(180, 42) }, function()
		sparkDim.Visible = false
	end)
	zAll(sparkDim, 21)
	local function buildSpark()
		clear(sparkList)
		local have = bannerPity().starlight or 0
		local cost = SPARK.cost
		sparkSub.Text = `{have} Starlight (+{SPARK.perPull} per summon). {cost} buys any unowned {SPARK.minRarity}+ reward.`
		local minIdx = table.find(GachaConfig.RarityOrder, SPARK.minRarity) or 3
		local order = 0
		for _, id in ipairs(GachaRewards.Pool(banner.pool)) do
			local r = GachaRewards.Get(id)
			if r and r.type ~= "material" and (table.find(GachaConfig.RarityOrder, r.rarity) or 1) >= minIdx then
				order += 1
				local mine = owned(r.id)
				itemRow(sparkList, order, r, `{string.upper(r.rarity)}{if mine then "  ·  OWNED" else ""}`,
					if mine then nil else { { text = `{cost} STARLIGHT`, on = have >= cost, onClick = function()
						if have < cost then return end
						sparkDim.Visible = false
						pulling = true
						act({ kind = "spark", id = r.id, banner = currentBanner })
						task.delay(8, function() pulling = false end)
					end } }, mine)
			end
		end
		zAll(sparkList, 22)
	end
	sparkBtn.Activated:Connect(function()
		buildSpark()
		openOverlay(sparkDim, sparkClose)
	end)

	-- "SET COMPLETE" banner
	setComplete = function(setId: string)
		local set
		for _, s2 in ipairs(GachaRewards.Sets) do
			if s2.id == setId then set = s2 end
		end
		if not set then return end
		local toast = panel(root, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -90), Size = UDim2.fromOffset(460, 76), ZIndex = 40 }, true)
		label(toast, { Text = "SET COMPLETE", FontFace = F.UIBold, TextSize = 13, TextColor3 = C.GoldLight, TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 10), ZIndex = 41 })
		local bonus = {}
		for currency, amount in pairs(set.bonus) do
			table.insert(bonus, `+{amount} {GachaConfig.Currencies[currency] and GachaConfig.Currencies[currency].glyph or currency}`)
		end
		label(toast, { Text = `{string.upper(set.name)}   {table.concat(bonus, "  ")}`, FontFace = F.Display, TextSize = 20, TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 34), ZIndex = 41 })
		zAll(toast, 41)
		SoundManager.PlayConfirm()
		TweenService:Create(toast, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 90) }):Play()
		task.delay(4, function()
			TweenService:Create(toast, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
			task.delay(0.45, function() toast:Destroy() end)
		end)
	end

	-- Rates & Pity (odds disclosure)
	local ratesDim, rates = overlay("Rates", UDim2.new(0, 600, 1, -120), 20)
	local ratesScroll = scroller(rates, { Position = UDim2.fromOffset(22, 18), Size = UDim2.new(1, -44, 1, -86) }, 4)
	local ratesClose = button(rates, "CLOSE", "dark", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(180, 42) }, function()
		ratesDim.Visible = false
	end)
	zAll(ratesDim, 21)
	local rOrder = 0
	local function rline(text: string, color: Color3?, font: Font?, size: number?)
		rOrder += 1
		local l = label(ratesScroll, { Text = text, TextColor3 = color or C.TextSecondary, FontFace = font or F.UI, TextSize = size or 13, TextWrapped = true,
			Size = UDim2.new(1, -8, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = rOrder, ZIndex = 22 })
		-- (a little air above each section heading)
		if font == F.UIBold and color == C.Gold then new("UIPadding", { PaddingTop = UDim.new(0, 10) }, l) end
	end
	local function buildRates()
		clear(ratesScroll)
		rOrder = 0
		rline("RATES & PITY", C.GoldLight, F.Display, 26)
		rline(`{banner.name}: exact odds.`, C.TextMuted)
		rline("BASE RARITY ODDS (PER SUMMON)", C.Gold, F.UIBold, 12)
		for _, r in ipairs(GachaConfig.RarityOrder) do
			rline(`{r} — {ODDS[r]}%`, rarityColor(r), F.UIBold, 14)
		end
		rline("PITY", C.Gold, F.UIBold, 12)
		rline(`• At least one Epic or better within every {P.epicEvery} summons.`)
		rline(`• From summon #{P.legendarySoftStart} without a Legendary, Legendary odds rise by {P.legendarySoftStep}% per summon; summon #{P.legendaryHard} is a guaranteed Legendary or better.`)
		if P.mythicHard then
			rline(`• Summon #{P.mythicHard} without a Mythic is a guaranteed Mythic.`)
		end
		rline(`• Every ×10 summon contains at least one {P.multiGuarantee} or better; every ×25 at least one {P.bigGuarantee} or better.`)
		if featured then
			rline(`• {if featuredRarity == "Epic" then "An" else "A"} {featuredRarity} is {featured.name} {math.floor(banner.featuredRate * 100)}% of the time; if not, the next {featuredRarity} is guaranteed to be {featured.name}.{if banner.featuredRotation then " The featured class changes every Monday 00:00 UTC." else ""}`)
		end
		rline("• Pity is tracked per banner and carries over between sessions.")
		rline(`• Starlight: every summon adds {SPARK.perPull}; {SPARK.cost} buys any {SPARK.minRarity}-or-better reward of this banner you don't own.`)
		if GachaConfig.DailyFree.enabled then
			rline("• Daily wish: 1 free summon per day (resets 00:00 UTC). Counts toward pity and Starlight.")
		end
		rline("DUPLICATES", C.Gold, F.UIBold, 12)
		local D = GachaConfig.Duplicates
		if banner.pool == "classes" then
			rline(`• Classes: the first copy unlocks the class for good; each copy after that becomes Soul Essence (Rare {D.classEssence.Rare}, Epic {D.classEssence.Epic}, Legendary {D.classEssence.Legendary}, Mythic {D.classEssence.Mythic}).`)
			local ms = {}
			for _, m in ipairs(GachaConfig.AltarMilestones) do table.insert(ms, `{m.at}: +{m.soulEssence}`) end
			rline(`• Altar milestones (lifetime summons here, Soul Essence): {table.concat(ms, ", ")}.`)
		end
		rline(`• Characters: the first copy Awakens them; further copies become Soul Shards ({D.shardsPerSoul} Shards = 1 Soul).`)
		rline("• VFX variants: cosmetic only; copies become Soul Shards.")
		if hasRewardType("relic") then
			rline(`• Relics: copies raise level (max {D.maxRelicLevel}), then become Relic Dust.`)
		end
		rline("• Titles: copies become Relic Dust.")
		rline("• Wings and mounts: copies become Soul Shards. Mounts work in the lobby only.")
		rline("INDIVIDUAL REWARD ODDS (PER SUMMON, BEFORE PITY)", C.Gold, F.UIBold, 12)
		for _, rarity in ipairs(GachaConfig.RarityOrder) do
			local list = GachaRewards.InPoolByRarity(banner.pool, rarity)
			local total = 0
			for _, r in ipairs(list) do total += (r.weight or 1) end
			for _, r in ipairs(list) do
				local pct = ODDS[rarity] * (r.weight or 1) / math.max(total, 1)
				if rarity == featuredRarity and featured and #list > 1 then
					pct = ODDS[rarity] * (if r.id == featured.id then banner.featuredRate else (1 - banner.featuredRate) / (#list - 1))
				end
				rline(`{displayName(r)} ({rarity}) — {string.format("%.3f", pct)}%`, rarityColor(rarity))
			end
		end
	end
	ratesBtn.Activated:Connect(function()
		buildRates()
		openOverlay(ratesDim, ratesClose)
	end)

	-- Results
	local resultsDim, results = overlay("Results", UDim2.fromOffset(940, 500), 30)
	label(results, { Text = "RESULTS", FontFace = F.Display, TextSize = 28, TextColor3 = C.GoldLight, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 32), Position = UDim2.fromOffset(0, 16) })
	label(results, { Text = "CLICK ONE TO PREVIEW", FontFace = F.UIBold, TextSize = 10, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 50) })
	-- (a ×25 pull is more than fits: the cards scroll, two rows of five in view)
	local rgrid = new("ScrollingFrame", { BackgroundTransparency = 1, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 76), Size = UDim2.new(1, -48, 1, -146),
		CanvasSize = UDim2.new(), AutomaticCanvasSize = Enum.AutomaticSize.Y, ScrollingDirection = Enum.ScrollingDirection.Y, ScrollBarThickness = 5,
		ScrollBarImageColor3 = C.Gold, Selectable = false }, results)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(160, 128), CellPadding = UDim2.fromOffset(10, 10), HorizontalAlignment = Enum.HorizontalAlignment.Center,
		SortOrder = Enum.SortOrder.LayoutOrder }, rgrid)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, rgrid)
	local continueBtn = button(results, "CONTINUE", "gold", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(220, 46), TextSize = 15 }, function()
		resultsDim.Visible = false
	end)
	zAll(resultsDim, 31)
	local function showcase(r: any)
		sg.Enabled = false
		LobbyCamera.StopImmediate()
		SummonCinematic.Showcase(r, function()
			if not isOpen then return end
			sg.Enabled = true
			LobbyCamera.SetClassSelectView()
		end)
	end
	local function showResults(list: { any })
		clear(rgrid)
		for i, res in ipairs(list) do
			local r = GachaRewards.Get(res.id)
			if r then
				local col = rarityColor(r.rarity)
				local card = new("TextButton", { AutoButtonColor = false, Text = "", BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, LayoutOrder = i, ZIndex = 32,
					SelectionImageObject = selectionFrame }, rgrid)
				corner(card, 5)
				vgrad(card, col:Lerp(C.Ink, 0.6), C.Inset)
				local s = stroke(card, col, 1.5, 0.15)
				local sc = new("UIScale", {}, card)
				card.MouseEnter:Connect(function()
					SoundManager.PlayHover()
					s.Transparency = 0
					TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1.04 }):Play()
				end)
				card.MouseLeave:Connect(function()
					s.Transparency = 0.15
					TweenService:Create(sc, TweenInfo.new(0.12), { Scale = 1 }):Play()
				end)
				card.Activated:Connect(function()
					SoundManager.PlaySelect()
					showcase(r)
				end)
				label(card, { Text = r.glyph, FontFace = F.Display, TextColor3 = col, TextSize = 34, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0.44, 0), ZIndex = 33 })
				local nm = label(card, { Text = r.name, FontFace = F.UIBold, TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.new(0, 4, 0.44, 0), Size = UDim2.new(1, -8, 0.18, 0), ZIndex = 33 })
				maxText(nm, 13, 8)
				label(card, { Text = string.upper(r.rarity), FontFace = F.UIBold, TextSize = 10, TextColor3 = col, TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.62), Size = UDim2.new(1, 0, 0.12, 0), ZIndex = 33 })
				label(card, { Text = res.note or "", FontFace = F.UIBold, TextSize = 10, TextColor3 = if res.isNew then C.GoldLight else C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = true, Position = UDim2.new(0, 4, 0.76, 0), Size = UDim2.new(1, -8, 0.2, 0), ZIndex = 33 })
				sc.Scale = 0.85
				TweenService:Create(sc, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, math.min(i, 10) * 0.05), { Scale = 1 }):Play()
			end
		end
		-- (as tall as its rows: one row for a single summon, two for ×10 and up)
		local rows = math.clamp(math.ceil(#list / 5), 1, 2)
		results.Size = UDim2.fromOffset(940, 76 + rows * 138 + 76)
		openOverlay(resultsDim, continueBtn)
		-- (from the top, once the layout has sized the canvas)
		rgrid.CanvasPosition = Vector2.zero
		task.defer(function() rgrid.CanvasPosition = Vector2.zero end)
	end

	-- ── Page switching ──
	local currentPage = "Home"
	local function setHomeVisible(on: boolean)
		left.Visible = on
		right.Visible = on
		bottom.Visible = on
		daily.Visible = on and GachaConfig.DailyFree.enabled
	end
	showPage = function(name: string)
		if name == currentPage then return end
		currentPage = name
		if name == "Home" then
			pageFrame.Visible = false
			dropCards(allCards)
			setHomeVisible(true)
			if UserInputService.GamepadEnabled then GuiService.SelectedObject = pulls[10].button end
			return
		end
		setHomeVisible(false)
		pageFrame.Visible = true
		local sc = pageFrame:FindFirstChildOfClass("UIScale") or new("UIScale", {}, pageFrame)
		sc.Scale = 0.98
		TweenService:Create(sc, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
		for n, strip in pairs(pageStrips) do strip.Visible = n == name end
		for n, body in pairs(pageBodies) do body.Visible = n == name end
		if name == "Collection" then
			if #allCards == 0 then buildAllCards() end
			for _, f in ipairs(refreshers) do f() end
		else
			dropCards(allCards)
		end
		if UserInputService.GamepadEnabled then
			GuiService.SelectedObject = pageStrips[name]:FindFirstChild("Tab_" .. name) :: GuiObject?
		end
	end

	-- Back: an overlay, then a page, then the screen.
	backAction = function()
		for _, o in ipairs(overlays) do
			if o.Visible then
				o.Visible = false
				return
			end
		end
		if currentPage ~= "Home" then
			showPage("Home")
			return
		end
		SummonScreen.Close()
	end
	for _, o in ipairs(overlays) do
		(o :: any).Activated:Connect(function()
			if o.Name ~= "Results" then o.Visible = false end
		end)
	end

	onOpened = function()
		buildHomeGrid()
		if featured then setPortrait("featured", featuredVp, featured, "full") end
		relayout()
		if UserInputService.GamepadEnabled then GuiService.SelectedObject = pulls[10].button end
	end
	onClosed = function()
		portraitGen += 1
		clearAllPortraits()
		if currentPage ~= "Home" then showPage("Home") end
		for _, o in ipairs(overlays) do o.Visible = false end
		if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(sg) then GuiService.SelectedObject = nil end
	end

	-- ── Networking ──
	table.insert(conns, Network.GetRemoteEvent(Network.Remotes.GachaState).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		state = payload
		state.currencies = state.currencies or {}
		state.products = state.products or {}
		for _, f in ipairs(refreshers) do f() end
	end))
	table.insert(conns, Network.GetRemoteEvent(Network.Remotes.SummonResult).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		if payload.error then
			pulling = false
			msg.Text = payload.error
			return
		end
		local list = payload.results or {}
		local best = nil
		local pulled = {}
		for _, res in ipairs(list) do
			local r = GachaRewards.Get(res.id)
			if r then table.insert(pulled, r) end
			if r and (not best or (table.find(GachaConfig.RarityOrder, r.rarity) or 0) > (table.find(GachaConfig.RarityOrder, best.rarity) or 0)) then best = r end
		end
		if not best then
			pulling = false
			return
		end
		sg.Enabled = false
		LobbyCamera.StopImmediate()
		-- (the music cut from the first pull till the page is left)
		player:SetAttribute("MusicCut", true)
		-- (a ×25 pull would fill the sky: the cinematic shows the best
		-- SHOW_MAX of them, in pull order; the results list has them all)
		local SHOW_MAX = 10
		if #pulled > SHOW_MAX then
			local order = {}
			for i, r in ipairs(pulled) do table.insert(order, { i = i, r = r, k = table.find(GachaConfig.RarityOrder, r.rarity) or 0 }) end
			table.sort(order, function(a, b) if a.k ~= b.k then return a.k > b.k end return a.i < b.i end)
			local keep = {}
			for j = 1, SHOW_MAX do keep[order[j].i] = true end
			local shown = {}
			for i, r in ipairs(pulled) do if keep[i] then table.insert(shown, r) end end
			pulled = shown
		end
		ConstellationWish.Play(best, pulled, function()
			pulling = false
			-- (walked away from the tent meanwhile: the page stays shut)
			if not isOpen then return end
			sg.Enabled = true
			LobbyCamera.SetClassSelectView()
			showResults(list)
			for _, setId in ipairs(payload.sets or {}) do setComplete(setId) end
		end)
	end))

	relayout()
	buildHomeGrid()
	for _, f in ipairs(refreshers) do f() end
	return sg
end

-- ─── Input: B / Backspace back out, LB / RB switch banners ──────────────────
local ACTION_BACK, ACTION_BANNER = "SummonScreenBack", "SummonScreenBanner"
local function stepBanner(dir: number)
	if pulling then return end
	local order = GachaConfig.BannerOrder
	local i = table.find(order, currentBanner) or 1
	local nextId = order[((i - 1 + dir) % #order) + 1]
	if nextId and nextId ~= currentBanner then
		SoundManager.PlaySelect()
		SummonScreen.SetBanner(nextId)
	end
end
local function bindInput()
	ContextActionService:BindActionAtPriority(ACTION_BACK, function(_, inputState)
		if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		if not (gui and gui.Enabled) then return Enum.ContextActionResult.Pass end
		-- (typing in a box: Backspace is text editing)
		if UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		backAction()
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonB, Enum.KeyCode.Backspace)
	ContextActionService:BindActionAtPriority(ACTION_BANNER, function(_, inputState, input)
		if inputState ~= Enum.UserInputState.Begin then return Enum.ContextActionResult.Pass end
		if not (gui and gui.Enabled) or UserInputService:GetFocusedTextBox() then return Enum.ContextActionResult.Pass end
		stepBanner(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)
end
local function unbindInput()
	ContextActionService:UnbindAction(ACTION_BACK)
	ContextActionService:UnbindAction(ACTION_BANNER)
end

function SummonScreen.Open()
	if not gui then gui = build() end
	isOpen = true
	hideOtherGuis(true)
	local sg = gui :: ScreenGui
	sg.Enabled = true
	onOpened()
	bindInput()
	Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer()

	-- Walk out of the GACHA tent (or leave the lobby) and the page shuts.
	-- Keyed on isOpen, not sg.Enabled: the page hides itself during a
	-- summon's cinematic, which used to end this check for good.
	if areaCheckThread then task.cancel(areaCheckThread) end
	areaCheckThread = task.spawn(function()
		local gachaPos = MapData.LOBBY_CENTER + Vector3.new(34, 0, -12)
		while isOpen do
			task.wait(0.3)
			if not isOpen then break end
			if player:GetAttribute("InHub") == true then
				local char = player.Character
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local flat = root and Vector3.new(root.Position.X - gachaPos.X, 0, root.Position.Z - gachaPos.Z)
				if flat and flat.Magnitude > 24 then
					areaCheckThread = nil
					SummonScreen.Close()
					break
				end
			end
		end
	end)
end

-- Switch the page to another banner (rebuilt for it, same state).
function SummonScreen.SetBanner(id: string)
	if not GachaConfig.Banners[id] then return end
	currentBanner = id
	onClosed()
	for _, c in ipairs(conns) do c:Disconnect() end
	table.clear(conns)
	table.clear(refreshers)
	local wasEnabled = gui ~= nil and gui.Enabled
	if gui then gui:Destroy() end
	gui = build()
	if wasEnabled then
		(gui :: ScreenGui).Enabled = true
		onOpened()
	end
end

function SummonScreen.Close()
	isOpen = false
	unbindInput()
	onClosed()
	-- (the normal music back)
	player:SetAttribute("MusicCut", nil)
	if areaCheckThread and areaCheckThread ~= coroutine.running() then
		task.cancel(areaCheckThread)
		areaCheckThread = nil
	end
	if gui then gui.Enabled = false end
	hideOtherGuis(false)
	-- Opened at the lobby's GACHA tent: the camera back on you, walking.
	local plr = game:GetService("Players").LocalPlayer
	if plr:GetAttribute("InHub") == true then
		LobbyCamera.StopImmediate()
		local cam = workspace.CurrentCamera
		local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		if hum then cam.CameraSubject = hum end
	end
end

return SummonScreen
