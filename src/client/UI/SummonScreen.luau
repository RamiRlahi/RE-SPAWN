--[[
	SummonScreen.luau
	The summon page, styled like the title menu and class selection (MenuStyle:
	dark wood plaques, brass rails, crimson ribbons, parchment Antique text).

	  top      title, back button, currency pills
	  left     featured banner panel + Rates & Pity (odds disclosure generated
	           from GachaConfig, so it always matches the server)
	  right    Collection / Shop panel
	  bottom   the daily wish + SUMMON ×1 / ×10

	The banner panel shows pity as meters (the Legendary guarantee, with the
	point where its odds start rising) and the banner's Starlight, which the
	EXCHANGE panel spends on a reward of your choice. Collection lists the
	sets (GachaRewards.Sets) and their progress. Summons play
	ConstellationWish.

	Opening hides the class-selection screen and HUD so nothing overlaps.
	Results: click a card to preview that item on its character at the statue.

	SummonScreen.Open() / SummonScreen.Close()
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))
local MenuStyle = require(script.Parent:WaitForChild("MenuStyle"))
local SummonCinematic = require(script.Parent.Parent:WaitForChild("SummonCinematic"))
local ConstellationWish = require(script.Parent.Parent:WaitForChild("ConstellationWish"))
local LobbyCamera = require(script.Parent.Parent:WaitForChild("LobbyCamera"))

local player = Players.LocalPlayer
-- The guild-hall palette under the names this screen was written with.
local MC = MenuStyle.Colors
local C = {
	Surface = MC.Plaque,
	SurfaceAlt = MC.PlaqueDark,
	SurfaceSelected = MC.PlaqueHover,
	Border = MC.BrassDark,
	Gold = MC.BrassLight,
	GoldLight = Color3.fromRGB(255, 236, 194),
	TextPrimary = MC.Parchment,
	TextSecondary = Color3.fromRGB(222, 196, 156),
	TextMuted = MC.ParchmentMuted,
	BackgroundOverlay = Color3.fromRGB(10, 6, 5),
	Danger = Color3.fromRGB(235, 96, 74),
}
local FONT = MenuStyle.Font
local F = { Title = FONT, Header = FONT, Body = FONT, Sub = FONT, Button = FONT, Tag = FONT }

local SummonScreen = {}

local state: any = { currencies = {}, collection = { characters = {}, relics = {}, cosmetics = {} }, equipped = { relics = {}, variants = {} }, pity = {}, products = {} }
local gui: ScreenGui? = nil
local refreshers: { () -> () } = {}
local payWith = "tickets"
local pulling = false
local setComplete: (string) -> () = function(_setId: string) end

-- ─── Menu-style building blocks ─────────────────────────────────────────────
-- A wood plaque (no inner rail: most panels lay out their children in lists).
local function panel(parent: Instance, props: { [string]: any }): (Frame, UIStroke)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = C.Surface
	f.BackgroundTransparency = 0.06
	f.BorderSizePixel = 0
	for k, v in pairs(props) do (f :: any)[k] = v end
	f.Parent = parent
	UITheme.AddGradient(f, Color3.fromRGB(64, 47, 37), MC.PlaqueDark, 90)
	return f, UITheme.AddStroke(f, C.Border, 2, 0)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = F.Body
	t.TextColor3 = C.TextPrimary
	t.TextSize = 13
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	t.TextStrokeColor3 = MC.Ink
	t.TextStrokeTransparency = 0.35
	for k, v in pairs(props) do (t :: any)[k] = v end
	t.TextSize += 2 -- Antique runs smaller than the sizes this screen was laid out in
	t.Parent = parent
	return t
end

-- Small uppercase brass section tag, like "CLASS COMBAT SKILLS".
local function sectionTag(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local t = label(parent, { Text = string.upper(text), Font = F.Tag, TextSize = 12, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 18) })
	for k, v in pairs(props or {}) do (t :: any)[k] = v end
	return t
end

-- Ribboned plaque action button, like "BEGIN EXPEDITION".
local function primaryButton(parent: Instance, text: string, props: { [string]: any }, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.Text = text
	MenuStyle.TextPlaque(b, true, onClick)
	for k, v in pairs(props) do (b :: any)[k] = v end
	b.Parent = parent
	return b
end

-- Plain plaque button (tabs, back, buy rows).
local function secondaryButton(parent: Instance, text: string, props: { [string]: any }, onClick: () -> ()): (TextButton, UIStroke)
	local b = Instance.new("TextButton")
	b.Text = text
	local s = MenuStyle.TextPlaque(b, false, function()
		SoundManager.PlaySelect()
		onClick()
	end)
	for k, v in pairs(props) do (b :: any)[k] = v end
	if props.TextSize then b.TextSize += 2 end -- Antique runs small
	b.Parent = parent
	return b, s
end

local function rarityColor(r: string): Color3
	return GachaConfig.Rarities[r] and GachaConfig.Rarities[r].color or C.TextPrimary
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
	if r.type == "character" or r.type == "variant" then return state.collection.characters[id] ~= nil end
	if r.type == "relic" then return state.collection.relics[id] ~= nil end
	if r.type == "cosmetic" or r.type == "armor" then return state.collection.cosmetics[id] == true end
	return false
end
local function displayName(r: any): string
	if r.secret and not owned(r.id) then return "??? (secret)" end
	return r.name
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

	-- Soft edge vignette like the menu backdrop.
	local vignette = Instance.new("Frame")
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = C.BackgroundOverlay
	vignette.BackgroundTransparency = 0.55
	vignette.Parent = sg
	local vg = Instance.new("UIGradient")
	vg.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0), Color3.fromRGB(50, 32, 23))
	vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.35, 1), NumberSequenceKeypoint.new(0.65, 1), NumberSequenceKeypoint.new(1, 0.2) })
	vg.Parent = vignette

	-- ── Top bar ──
	label(sg, { Text = "SUMMONING SANCTUM", Font = F.Title, TextSize = 30, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Center,
		TextStrokeColor3 = Color3.fromRGB(36, 8, 3), TextStrokeTransparency = 0.1,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 20), Size = UDim2.fromOffset(600, 34) })
	local banner = GachaConfig.Banners[GachaConfig.DefaultBanner]
	label(sg, { Text = string.upper(banner.name), Font = F.Tag, TextSize = 12, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(600, 16) })
	MenuStyle.Rule(sg, 76, 0.24)
	-- Below Roblox's top-left buttons.
	secondaryButton(sg, "< BACK", { Position = UDim2.fromOffset(24, 70), Size = UDim2.fromOffset(110, 44), TextSize = 14 }, function()
		SummonScreen.Close()
	end)
	local currencyRow = Instance.new("Frame")
	currencyRow.BackgroundTransparency = 1
	currencyRow.AnchorPoint = Vector2.new(1, 0)
	currencyRow.Position = UDim2.new(1, -24, 0, 22)
	currencyRow.Size = UDim2.fromOffset(560, 44)
	currencyRow.Parent = sg
	local crl = Instance.new("UIListLayout")
	crl.FillDirection = Enum.FillDirection.Horizontal
	crl.HorizontalAlignment = Enum.HorizontalAlignment.Right
	crl.Padding = UDim.new(0, 8)
	crl.Parent = currencyRow
	local pills: { [string]: TextLabel } = {}
	for _, key in ipairs({ "tickets", "crystals", "soulShards", "relicDust" }) do
		local pill = panel(currencyRow, { Size = UDim2.fromOffset(100, 44) })
		pills[key] = label(pill, { Font = F.Header, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
	end
	table.insert(refreshers, function()
		for key, t in pairs(pills) do
			t.Text = `{state.currencies[key] or 0} {GachaConfig.Currencies[key].glyph}`
		end
	end)

	-- ── Left: featured banner ──
	local featured = GachaRewards.Get(banner.featured)
	local fColor = featured and (featured.accent or rarityColor(featured.rarity)) or C.Gold
	local left, leftStroke = panel(sg, { Position = UDim2.fromOffset(24, 124), Size = UDim2.new(0, 340, 1, -240) })
	leftStroke.Color = fColor
	UITheme.AddPadding(left, 16, 16, 16, 16)
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 8)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = left
	sectionTag(left, "Featured", { LayoutOrder = 1 })
	if featured then
		label(left, { Text = featured.glyph, Font = Enum.Font.GothamBlack, TextColor3 = fColor, TextSize = 40, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 56), LayoutOrder = 2 })
		label(left, { Text = string.upper(featured.name), Font = F.Title, TextSize = 24, TextColor3 = fColor, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3 })
		label(left, { Text = `[{string.upper(featured.rarity)}]`, Font = F.Tag, TextSize = 12, TextColor3 = rarityColor(featured.rarity), Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 4 })
		label(left, { Text = featured.description, TextSize = 13, TextColor3 = C.TextSecondary, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
		sectionTag(left, "Rate-Up", { LayoutOrder = 6 })
		label(left, { Text = `When you summon a Legendary it is {featured.name} {math.floor(banner.featuredRate * 100)}% of the time. If it isn't, your next Legendary is guaranteed to be.`,
			TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7 })
	end
	-- A progress meter: a trough, a fill, its count on top, and an optional
	-- tick (where the Legendary odds start to rise).
	local function meter(order: number, color: Color3, tickAt: number?): (Frame, TextLabel)
		local trough = Instance.new("Frame")
		trough.Size = UDim2.new(1, 0, 0, 20)
		trough.BackgroundColor3 = Color3.fromRGB(16, 11, 9)
		trough.BorderSizePixel = 0
		trough.LayoutOrder = order
		trough.Parent = left
		UITheme.AddStroke(trough, C.Border, 1, 0.2)
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.Size = UDim2.fromScale(0, 1)
		fill.BackgroundColor3 = color
		fill.BorderSizePixel = 0
		fill.Parent = trough
		UITheme.AddGradient(fill, color:Lerp(Color3.new(1, 1, 1), 0.35), color, 90)
		if tickAt then
			local tick = Instance.new("Frame")
			tick.AnchorPoint = Vector2.new(0.5, 0)
			tick.Position = UDim2.fromScale(tickAt, 0)
			tick.Size = UDim2.new(0, 2, 1, 0)
			tick.BackgroundColor3 = C.GoldLight
			tick.BorderSizePixel = 0
			tick.ZIndex = 3
			tick.Parent = trough
		end
		local t = label(trough, { Font = F.Tag, TextSize = 11, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1), ZIndex = 4 })
		return fill, t
	end
	local P = GachaConfig.Pity
	sectionTag(left, "Legendary Guarantee", { LayoutOrder = 8 })
	local legFill, legText = meter(9, rarityColor("Legendary"), P.legendarySoftStart / P.legendaryHard)
	local pityText = label(left, { TextSize = 11, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 10 })
	sectionTag(left, "Starlight", { LayoutOrder = 11 })
	local sparkFill, sparkText = meter(12, Color3.fromRGB(150, 170, 255))
	local sparkBtn = secondaryButton(left, "EXCHANGE STARLIGHT", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 13 }, function() end)
	local ratesBtn = secondaryButton(left, "RATES & PITY", { Size = UDim2.new(1, 0, 0, 34), LayoutOrder = 14 }, function() end)
	table.insert(refreshers, function()
		local pity = state.pity or {}
		local since = pity.sinceLegendary or 0
		TweenService:Create(legFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(since / P.legendaryHard, 0, 1), 1) }):Play()
		legText.Text = `{since} / {P.legendaryHard}{if since >= P.legendarySoftStart then "  ·  ODDS RISING" else ""}`
		pityText.Text = `Epic or better within {math.max(0, P.epicEvery - (pity.sinceEpic or 0))} summons.{if pity.guaranteedFeatured then "\nYour next Legendary is the featured one." else ""}`
		local sl = pity.starlight or 0
		local cost = GachaConfig.Spark.cost
		TweenService:Create(sparkFill, TweenInfo.new(0.4), { Size = UDim2.fromScale(math.clamp(sl / cost, 0, 1), 1) }):Play()
		sparkText.Text = `{sl} / {cost}  ·  +{GachaConfig.Spark.perPull} PER SUMMON`
		sparkBtn.TextColor3 = if sl >= cost then C.GoldLight else C.TextMuted
	end)

	-- ── Right: collection / shop ──
	local right = panel(sg, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 124), Size = UDim2.new(0, 360, 1, -240) })
	UITheme.AddPadding(right, 12, 12, 12, 12)
	local rightTabs: { [string]: TextButton } = {}
	local rightPages: { [string]: ScrollingFrame } = {}
	local function showRight(name: string)
		for n, pg in pairs(rightPages) do pg.Visible = n == name end
		for n, b in pairs(rightTabs) do
			b.BackgroundColor3 = if n == name then C.SurfaceSelected else C.SurfaceAlt
			b.TextColor3 = if n == name then C.Gold else C.TextPrimary
		end
	end
	for i, name in ipairs({ "Collection", "Shop" }) do
		rightTabs[name] = secondaryButton(right, string.upper(name), { Position = UDim2.new((i - 1) * 0.5, if i == 2 then 4 else 0, 0, 0), Size = UDim2.new(0.5, -4, 0, 34) }, function()
			showRight(name)
		end)
		local pg = Instance.new("ScrollingFrame")
		pg.Name = name
		pg.BackgroundTransparency = 1
		pg.BorderSizePixel = 0
		pg.Position = UDim2.fromOffset(0, 44)
		pg.Size = UDim2.new(1, 0, 1, -44)
		pg.ScrollBarThickness = 4
		pg.ScrollBarImageColor3 = C.Border
		pg.AutomaticCanvasSize = Enum.AutomaticSize.Y
		pg.CanvasSize = UDim2.new()
		pg.Parent = right
		local l = Instance.new("UIListLayout")
		l.Padding = UDim.new(0, 6)
		l.SortOrder = Enum.SortOrder.LayoutOrder
		l.Parent = pg
		rightPages[name] = pg
	end

	local function act(payload: any)
		Network.GetRemoteEvent(Network.Remotes.GachaAction):FireServer(payload)
	end
	local function itemRow(parent: Instance, order: number, r: any, info: string, actionText: string?, onAction: (() -> ())?, active: boolean?)
		local row, rowStroke = panel(parent, { BackgroundColor3 = C.SurfaceAlt, Size = UDim2.new(1, -6, 0, 54), LayoutOrder = order })
		rowStroke.Color = if active then C.Gold else rarityColor(r.rarity)
		rowStroke.Transparency = if active then 0 else 0.5
		label(row, { Text = r.glyph, Font = Enum.Font.GothamBlack, TextColor3 = rarityColor(r.rarity), TextSize = 18, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(46, 54) })
		label(row, { Text = r.name, Font = F.Header, TextSize = 13, Position = UDim2.fromOffset(48, 6), Size = UDim2.new(1, -150, 0, 16) })
		label(row, { Text = info, Font = F.Tag, TextSize = 10, TextColor3 = rarityColor(r.rarity), Position = UDim2.fromOffset(48, 22), Size = UDim2.new(1, -150, 0, 12) })
		label(row, { Text = r.description, Font = F.Sub, TextSize = 10, TextColor3 = C.TextMuted, Position = UDim2.fromOffset(48, 35), Size = UDim2.new(1, -150, 0, 14),
			TextTruncate = Enum.TextTruncate.AtEnd })
		if actionText and onAction then
			secondaryButton(row, actionText, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(88, 30), TextSize = 11,
				TextColor3 = if active then C.TextSecondary else C.Gold }, onAction)
		end
	end

	table.insert(refreshers, function()
		local pg = rightPages.Collection
		for _, c in ipairs(pg:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local order = 0
		local function tag(text: string)
			order += 1
			sectionTag(pg, text, { LayoutOrder = order, Size = UDim2.new(1, 0, 0, 22) })
		end
		tag("Sets")
		for _, set in ipairs(GachaRewards.Sets) do
			local have = 0
			for _, id in ipairs(set.items) do
				if owned(id) then have += 1 end
			end
			local done = (state.setsDone or {})[set.id] == true
			local bonus = {}
			for currency, amount in pairs(set.bonus) do
				table.insert(bonus, `{amount} {GachaConfig.Currencies[currency] and GachaConfig.Currencies[currency].glyph or currency}`)
			end
			order += 1
			itemRow(pg, order, { glyph = set.glyph, name = set.name, rarity = if done then "Legendary" else "Rare",
				description = `{set.description} Bonus: {table.concat(bonus, " ")}` },
				if done then "COMPLETE" else `{have} / {#set.items} OWNED`, nil, nil, done)
		end
		tag("VFX Variants")
		local any = false
		local function variantRow(r: any, classId: string)
			local active = state.equipped.variants[classId] == r.id
			local className = (ClassData.GetClass(classId) or { name = classId }).name
			order += 1
			itemRow(pg, order, r, `{string.upper(className)} · {string.upper(r.rarity)}`,
				if active then "UNEQUIP" else "EQUIP", function()
					act({ kind = "equipVariant", classId = classId, id = if active then nil else r.id })
				end, active)
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
		if not any then
			order += 1
			label(pg, { Text = "None yet — summon to discover VFX variants.", TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order })
		end
		if hasRewardType("relic") then
			tag(`Relics · {#state.equipped.relics}/{GachaConfig.RelicSlots} Equipped`)
			for _, r in ipairs(GachaRewards.All) do
				local o = r.type == "relic" and state.collection.relics[r.id]
				if o then
					local active = table.find(state.equipped.relics, r.id) ~= nil
					order += 1
					itemRow(pg, order, r, `{string.upper(r.rarity)} · LEVEL {o.level}/{GachaConfig.Duplicates.maxRelicLevel}`,
						if active then "UNEQUIP" else "EQUIP", function()
							act({ kind = if active then "unequipRelic" else "equipRelic", id = r.id })
						end, active)
				end
			end
		end
		tag("Armor")
		local anyArmor = false
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "armor" and state.collection.cosmetics[r.id] then
				anyArmor = true
				local worn = (state.equipped.armor or {})[r.classId] == r.id
				local className = (ClassData.GetClass(r.classId :: string) or { name = r.classId }).name
				order += 1
				itemRow(pg, order, r, `{string.upper(className)} · {string.upper(r.rarity)}`,
					if worn then "UNEQUIP" else "EQUIP", function()
						act({ kind = "equipArmor", classId = r.classId, id = if worn then nil else r.id })
					end, worn)
			end
		end
		if not anyArmor then
			order += 1
			label(pg, { Text = "None yet — summon to win each class's armor.", TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order })
		end
		tag("Awakened Characters")
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "character" and state.collection.characters[r.id] then
				order += 1
				itemRow(pg, order, r, "AWAKENED")
			end
		end
		tag("Titles")
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "cosmetic" and state.collection.cosmetics[r.id] then
				order += 1
				itemRow(pg, order, r, string.upper(r.rarity))
			end
		end
		tag("Soul Shards")
		order += 1
		local per = GachaConfig.Duplicates.shardsPerSoul
		secondaryButton(pg, `REFINE · {per} SHARDS → 1 SOUL  ({state.currencies.soulShards or 0} SHARDS)`, { Size = UDim2.new(1, -6, 0, 38), LayoutOrder = order, TextColor3 = C.Gold }, function()
			act({ kind = "refineShards" })
		end)
	end)

	table.insert(refreshers, function()
		local pg = rightPages.Shop
		for _, c in ipairs(pg:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local order = 0
		local function nextOrder(): number
			order += 1
			return order
		end

		-- Direct purchases (fixed price, not random).
		sectionTag(pg, "Featured", { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 22) })
		for _, item in ipairs(GachaConfig.ShopItems) do
			local r = GachaRewards.Get(item.id)
			if r then
				itemRow(pg, nextOrder(), r, string.upper(r.rarity))
				if owned(r.id) then
					label(pg, { Text = "OWNED — equip it in the Collection.", Font = F.Tag, TextSize = 11, TextColor3 = C.Gold,
						Size = UDim2.new(1, 0, 0, 22), LayoutOrder = nextOrder() })
				else
					for _, currency in ipairs({ "crystals", "relicDust" }) do
						local price = item.price[currency]
						if price then
							local have = state.currencies[currency] or 0
							secondaryButton(pg, `BUY · {price} {GachaConfig.Currencies[currency].glyph}  (you have {have})`,
								{ Size = UDim2.new(1, -6, 0, 36), LayoutOrder = nextOrder(), TextColor3 = if have >= price then C.Gold else C.TextMuted }, function()
									SoundManager.PlayConfirm()
									act({ kind = "buyShopItem", id = r.id, pay = currency })
								end)
						end
					end
				end
			end
		end

		sectionTag(pg, "Crystals", { LayoutOrder = nextOrder(), Size = UDim2.new(1, 0, 0, 22) })
		if #state.products == 0 then
			label(pg, { Text = "Crystal packs are coming soon.\n\nSummon Tickets are earned from bosses and every few dozen kills.",
				TextSize = 13, TextColor3 = C.TextSecondary, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
		else
			label(pg, { Text = "Crystals are premium currency used for summons. See Rates & Pity for the exact odds before summoning.",
				TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = nextOrder() })
			for _, prod in ipairs(state.products) do
				primaryButton(pg, prod.label, { Size = UDim2.new(1, -6, 0, 44), LayoutOrder = nextOrder() }, function()
					SoundManager.PlayConfirm()
					Network.GetRemoteEvent(Network.Remotes.GachaAction):FireServer({ kind = "buyCrystals", id = prod.id })
				end)
			end
		end
	end)

	-- ── Bottom: summon bar ──
	local bottom = Instance.new("Frame")
	bottom.BackgroundTransparency = 1
	bottom.AnchorPoint = Vector2.new(0.5, 1)
	bottom.Position = UDim2.new(0.5, 0, 1, -24)
	bottom.Size = UDim2.fromOffset(700, 90)
	bottom.Parent = sg
	local msg = label(bottom, { TextXAlignment = Enum.TextXAlignment.Center, TextColor3 = C.Danger, TextSize = 13, Size = UDim2.new(1, 0, 0, 18) })
	local payBtn = secondaryButton(bottom, "", { Position = UDim2.fromOffset(0, 30), Size = UDim2.fromOffset(150, 56) }, function()
		payWith = if payWith == "tickets" then "crystals" else "tickets"
		for _, f in ipairs(refreshers) do f() end
	end)
	local function doPull(count: number)
		if pulling then return end
		pulling = true
		msg.Text = ""
		SoundManager.PlayConfirm()
		Network.GetRemoteEvent(Network.Remotes.Summon):FireServer({ banner = GachaConfig.DefaultBanner, count = count, pay = payWith })
		task.delay(8, function() pulling = false end) -- safety if the server never answers
	end
	local pull1 = primaryButton(bottom, "", { Position = UDim2.fromOffset(160, 30), Size = UDim2.fromOffset(260, 56) }, function() doPull(1) end)
	local pull10 = primaryButton(bottom, "", { Position = UDim2.fromOffset(430, 30), Size = UDim2.fromOffset(270, 56) }, function() doPull(10) end)
	table.insert(refreshers, function()
		local free = GachaConfig.FREE_SUMMONS
		payBtn.Visible = not free
		if state.paidRestricted and payWith == "crystals" then payWith = "tickets" end
		local g = GachaConfig.Currencies[payWith].glyph
		payBtn.Text = `PAY WITH\n{string.upper(GachaConfig.Currencies[payWith].name)}S`
		pull1.Text = if free then "SUMMON ×1  ·  FREE" else `SUMMON ×1  ·  {GachaConfig.Cost.single[payWith]} {g}`
		pull10.Text = if free then "SUMMON ×10  ·  FREE" else `SUMMON ×10  ·  {GachaConfig.Cost.multi[payWith]} {g}`
		if free then
			pull1.Position, pull10.Position = UDim2.fromOffset(75, 30), UDim2.fromOffset(345, 30)
		else
			pull1.Position, pull10.Position = UDim2.fromOffset(160, 30), UDim2.fromOffset(430, 30)
		end
		msg.Text = if state.paidRestricted then "Crystal summons are unavailable in your region — Summon Tickets still work." else msg.Text
	end)

	-- ── The daily wish ──
	local dailyBtn = primaryButton(sg, "", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -124), Size = UDim2.fromOffset(320, 44) }, function()
		if pulling or not state.freeAvailable then return end
		pulling = true
		msg.Text = ""
		SoundManager.PlayConfirm()
		Network.GetRemoteEvent(Network.Remotes.Summon):FireServer({ banner = GachaConfig.DefaultBanner, count = 1, free = true })
		task.delay(8, function() pulling = false end)
	end)
	local syncedAt = os.clock()
	table.insert(refreshers, function()
		syncedAt = os.clock()
		dailyBtn.Visible = GachaConfig.DailyFree.enabled
	end)
	task.spawn(function()
		while sg.Parent do
			if state.freeAvailable then
				dailyBtn.Text = "DAILY WISH  ·  FREE"
				dailyBtn.TextColor3 = C.GoldLight
			else
				local left2 = math.max(0, (state.nextFreeIn or 0) - (os.clock() - syncedAt))
				dailyBtn.Text = string.format("NEXT DAILY WISH IN %dh %02dm", math.floor(left2 / 3600), math.floor(left2 % 3600 / 60))
				dailyBtn.TextColor3 = C.TextMuted
				if left2 <= 0 and sg.Enabled then Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer() end
			end
			task.wait(1)
		end
	end)

	-- ── Starlight exchange ──
	local spark = panel(sg, { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 520, 0.72, 0),
		BackgroundTransparency = 0.02, ZIndex = 20 })
	label(spark, { Text = "STARLIGHT EXCHANGE", Font = F.Title, TextSize = 22, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 14), ZIndex = 21 })
	local sparkSub = label(spark, { TextSize = 12, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -40, 0, 32), Position = UDim2.fromOffset(20, 44), ZIndex = 21 })
	local sparkList = Instance.new("ScrollingFrame")
	sparkList.BackgroundTransparency = 1
	sparkList.BorderSizePixel = 0
	sparkList.Position = UDim2.fromOffset(18, 82)
	sparkList.Size = UDim2.new(1, -36, 1, -150)
	sparkList.ScrollBarThickness = 4
	sparkList.ScrollBarImageColor3 = C.Border
	sparkList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sparkList.CanvasSize = UDim2.new()
	sparkList.ZIndex = 21
	sparkList.Parent = spark
	local sll = Instance.new("UIListLayout")
	sll.Padding = UDim.new(0, 6)
	sll.SortOrder = Enum.SortOrder.LayoutOrder
	sll.Parent = sparkList
	primaryButton(spark, "CLOSE", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(180, 44), ZIndex = 21 }, function()
		spark.Visible = false
	end)
	local function buildSpark()
		for _, c in ipairs(sparkList:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local have = (state.pity or {}).starlight or 0
		local cost = GachaConfig.Spark.cost
		sparkSub.Text = `You have {have} Starlight. Every summon on this banner adds {GachaConfig.Spark.perPull}; spend {cost} on any {GachaConfig.Spark.minRarity}-or-better reward you don't own yet.`
		local minIdx = table.find(GachaConfig.RarityOrder, GachaConfig.Spark.minRarity) or 3
		local order = 0
		for _, id in ipairs(GachaRewards.Pool(banner.pool)) do
			local r = GachaRewards.Get(id)
			if r and r.type ~= "material" and (table.find(GachaConfig.RarityOrder, r.rarity) or 1) >= minIdx then
				order += 1
				local mine = owned(r.id)
				local row = Instance.new("Frame")
				row.BackgroundTransparency = 1
				row.Size = UDim2.new(1, -6, 0, 54)
				row.LayoutOrder = order
				row.ZIndex = 22
				row.Parent = sparkList
				itemRow(row, 0, r, `{string.upper(r.rarity)}{if mine then "  ·  OWNED" else ""}`,
					if mine then nil else `{cost} STARLIGHT`, if mine then nil else function()
						if have < cost then return end
						spark.Visible = false
						pulling = true
						act({ kind = "spark", id = r.id, banner = GachaConfig.DefaultBanner })
						task.delay(8, function() pulling = false end)
					end)
				for _, d in ipairs(row:GetDescendants()) do
					if d:IsA("GuiObject") then d.ZIndex = 23 end
				end
			end
		end
	end
	sparkBtn.MouseButton1Click:Connect(function()
		buildSpark()
		spark.Visible = true
	end)

	-- ── "SET COMPLETE" banner ──
	setComplete = function(setId: string)
		local set
		for _, s2 in ipairs(GachaRewards.Sets) do
			if s2.id == setId then set = s2 end
		end
		if not set then return end
		local toast = panel(sg, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, -90), Size = UDim2.fromOffset(460, 76), ZIndex = 40 })
		label(toast, { Text = "SET COMPLETE", Font = F.Tag, TextSize = 13, TextColor3 = C.GoldLight, TextXAlignment = Enum.TextXAlignment.Center,
			Size = UDim2.new(1, 0, 0, 22), Position = UDim2.fromOffset(0, 10), ZIndex = 41 })
		local bonus = {}
		for currency, amount in pairs(set.bonus) do
			table.insert(bonus, `+{amount} {GachaConfig.Currencies[currency] and GachaConfig.Currencies[currency].glyph or currency}`)
		end
		label(toast, { Text = `{string.upper(set.name)}   {table.concat(bonus, "  ")}`, Font = F.Title, TextSize = 18, TextColor3 = C.Gold,
			TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 34), ZIndex = 41 })
		SoundManager.PlayConfirm()
		TweenService:Create(toast, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 90) }):Play()
		task.delay(4, function()
			TweenService:Create(toast, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
			task.delay(0.45, function() toast:Destroy() end)
		end)
	end

	-- ── Rates & Pity (odds disclosure) ──
	local rates = panel(sg, { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 560, 0.78, 0),
		BackgroundTransparency = 0.02, ZIndex = 20 })
	local ratesScroll = Instance.new("ScrollingFrame")
	ratesScroll.BackgroundTransparency = 1
	ratesScroll.BorderSizePixel = 0
	ratesScroll.Position = UDim2.fromOffset(18, 16)
	ratesScroll.Size = UDim2.new(1, -36, 1, -84)
	ratesScroll.ScrollBarThickness = 4
	ratesScroll.ScrollBarImageColor3 = C.Border
	ratesScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	ratesScroll.CanvasSize = UDim2.new()
	ratesScroll.ZIndex = 21
	ratesScroll.Parent = rates
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 4)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = ratesScroll
	primaryButton(rates, "CLOSE", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Size = UDim2.fromOffset(180, 44), ZIndex = 21 }, function()
		rates.Visible = false
	end)
	local rOrder = 0
	local function rline(text: string, color: Color3?, font: Enum.Font?, size: number?)
		rOrder += 1
		label(ratesScroll, { Text = text, TextColor3 = color or C.TextSecondary, Font = font or F.Body, TextSize = size or 13,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = rOrder, ZIndex = 22 })
	end
	local function buildRates()
		for _, c in ipairs(ratesScroll:GetChildren()) do
			if c:IsA("TextLabel") then c:Destroy() end
		end
		rOrder = 0
		rline("RATES & PITY", C.Gold, F.Title, 22)
		rline(`{banner.name}. Every summon is random; these are the exact odds the server uses.`, C.TextMuted)
		rline("BASE RARITY ODDS (PER SUMMON)", C.Gold, F.Tag, 12)
		for _, r in ipairs(GachaConfig.RarityOrder) do
			rline(`{r} — {GachaConfig.Rarities[r].odds}%`, rarityColor(r), F.Header, 14)
		end
		rline("PITY", C.Gold, F.Tag, 12)
		local P = GachaConfig.Pity
		rline(`• At least one Epic or better within every {P.epicEvery} summons.`)
		rline(`• From summon #{P.legendarySoftStart} without a Legendary, Legendary odds rise by {P.legendarySoftStep}% per summon; summon #{P.legendaryHard} is a guaranteed Legendary or better.`)
		rline(`• Every ×10 summon contains at least one {P.multiGuarantee} or better.`)
		if featured then
			rline(`• A Legendary is {featured.name} {math.floor(banner.featuredRate * 100)}% of the time; if not, the next Legendary is guaranteed to be {featured.name}.`)
		end
		rline("• Pity is tracked per banner and carries over between sessions.")
		rline(`• Starlight: every summon adds {GachaConfig.Spark.perPull}; {GachaConfig.Spark.cost} buys any {GachaConfig.Spark.minRarity}-or-better reward of this banner you don't own.`)
		if GachaConfig.DailyFree.enabled then
			rline("• Daily wish: one free single summon per day (resets at 00:00 UTC). It counts towards pity and Starlight.")
		end
		rline("DUPLICATES", C.Gold, F.Tag, 12)
		local D = GachaConfig.Duplicates
		rline(`• Characters: the first copy Awakens them; further copies become Soul Shards ({D.shardsPerSoul} Shards = 1 Soul).`)
		rline("• VFX variants: cosmetic only; copies become Soul Shards.")
		if hasRewardType("relic") then
			rline(`• Relics: copies raise level (max {D.maxRelicLevel}), then become Relic Dust.`)
		end
		rline("• Titles: copies become Relic Dust.")
		rline("INDIVIDUAL REWARD ODDS (PER SUMMON, BEFORE PITY)", C.Gold, F.Tag, 12)
		for _, rarity in ipairs(GachaConfig.RarityOrder) do
			local list = GachaRewards.InPoolByRarity(banner.pool, rarity)
			local total = 0
			for _, r in ipairs(list) do total += (r.weight or 1) end
			for _, r in ipairs(list) do
				local pct = GachaConfig.Rarities[rarity].odds * (r.weight or 1) / math.max(total, 1)
				if rarity == "Legendary" and featured and #list > 1 then
					pct = GachaConfig.Rarities[rarity].odds * (if r.id == featured.id then banner.featuredRate else (1 - banner.featuredRate) / (#list - 1))
				end
				rline(`{displayName(r)} ({rarity}) — {string.format("%.3f", pct)}%`, rarityColor(rarity))
			end
		end
	end
	ratesBtn.MouseButton1Click:Connect(function()
		buildRates()
		rates.Visible = true
	end)

	-- ── Results ──
	local results = panel(sg, { Visible = false, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(0, 900, 0, 470),
		BackgroundTransparency = 0.02, ZIndex = 30 })
	label(results, { Text = "SUMMON RESULTS", Font = F.Title, TextSize = 22, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 16), ZIndex = 31 })
	label(results, { Text = "CLICK AN ITEM TO SEE IT ON ITS CHARACTER", Font = F.Tag, TextSize = 11, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 14), Position = UDim2.fromOffset(0, 46), ZIndex = 31 })
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(24, 72)
	grid.Size = UDim2.new(1, -48, 1, -140)
	grid.ZIndex = 31
	grid.Parent = results
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.19, 0, 0.48, 0)
	gl.CellPadding = UDim2.new(0.0125, 0, 0.04, 0)
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = grid
	primaryButton(results, "CONTINUE", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(220, 46), ZIndex = 31 }, function()
		results.Visible = false
	end)
	local function showcase(r: any)
		sg.Enabled = false
		LobbyCamera.StopImmediate()
		SummonCinematic.Showcase(r, function()
			sg.Enabled = true
			LobbyCamera.SetClassSelectView()
		end)
	end
	local function showResults(list: { any })
		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		for i, res in ipairs(list) do
			local r = GachaRewards.Get(res.id)
			if r then
				local card = Instance.new("TextButton")
				card.AutoButtonColor = false
				card.Text = ""
				card.BackgroundColor3 = C.SurfaceAlt
				card.BorderSizePixel = 0
				card.LayoutOrder = i
				card.ZIndex = 32
				card.Parent = grid
				UITheme.AddGradient(card, Color3.fromRGB(64, 47, 37), MC.PlaqueDark, 90)
				UITheme.AddStroke(card, rarityColor(r.rarity), 2, 0.1)
				card.MouseEnter:Connect(function()
					SoundManager.PlayHover()
					card.BackgroundColor3 = C.SurfaceSelected
				end)
				card.MouseLeave:Connect(function()
					card.BackgroundColor3 = C.SurfaceAlt
				end)
				card.Activated:Connect(function()
					SoundManager.PlaySelect()
					showcase(r)
				end)
				label(card, { Text = r.glyph, Font = Enum.Font.GothamBlack, TextColor3 = rarityColor(r.rarity), TextSize = 30, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0.44, 0), ZIndex = 33 })
				label(card, { Text = r.name, Font = F.Header, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.44), Size = UDim2.new(1, 0, 0.2, 0), ZIndex = 33 })
				label(card, { Text = `[{string.upper(r.rarity)}]`, Font = F.Tag, TextSize = 10, TextColor3 = rarityColor(r.rarity), TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.64), Size = UDim2.new(1, 0, 0.12, 0), ZIndex = 33 })
				label(card, { Text = res.note or "", Font = F.Tag, TextSize = 10, TextColor3 = if res.isNew then C.GoldLight else C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.78), Size = UDim2.new(1, 0, 0.18, 0), ZIndex = 33 })
				card.BackgroundTransparency = 1
				TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, i * 0.06), { BackgroundTransparency = 0 }):Play()
			end
		end
		results.Visible = true
	end

	-- ── Networking ──
	Network.GetRemoteEvent(Network.Remotes.GachaState).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		state = payload
		state.currencies = state.currencies or {}
		state.products = state.products or {}
		for _, f in ipairs(refreshers) do f() end
	end)
	Network.GetRemoteEvent(Network.Remotes.SummonResult).OnClientEvent:Connect(function(payload)
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
		ConstellationWish.Play(best, pulled, function()
			sg.Enabled = true
			LobbyCamera.SetClassSelectView()
			showResults(list)
			pulling = false
			for _, setId in ipairs(payload.sets or {}) do setComplete(setId) end
		end)
	end)

	showRight("Collection")
	for _, f in ipairs(refreshers) do f() end
	return sg
end

function SummonScreen.Open()
	if not gui then gui = build() end
	hideOtherGuis(true)
	local sg = gui :: ScreenGui
	sg.Enabled = true
	Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer()
end

function SummonScreen.Close()
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
