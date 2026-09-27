--[[
	SummonScreen.luau
	The summon page, styled like the class-selection menu (UITheme panels, gold
	section tags, gold gradient action buttons, carousel-style back button).

	  top      title, back button, currency pills
	  left     featured banner panel + Rates & Pity (odds disclosure generated
	           from GachaConfig, so it always matches the server)
	  right    Collection / Shop panel
	  bottom   pity status + SUMMON ×1 / ×10

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
local SummonCinematic = require(script.Parent.Parent:WaitForChild("SummonCinematic"))
local LobbyCamera = require(script.Parent.Parent:WaitForChild("LobbyCamera"))

local player = Players.LocalPlayer
local C = UITheme.Colors
local F = UITheme.Fonts

local SummonScreen = {}

local state: any = { currencies = {}, collection = { characters = {}, relics = {}, cosmetics = {} }, equipped = { relics = {}, variants = {} }, pity = {}, products = {} }
local gui: ScreenGui? = nil
local refreshers: { () -> () } = {}
local payWith = "tickets"
local pulling = false

-- ─── Menu-style building blocks ─────────────────────────────────────────────
local function panel(parent: Instance, props: { [string]: any }): (Frame, UIStroke)
	local f = Instance.new("Frame")
	f.BackgroundColor3 = C.Surface
	f.BackgroundTransparency = 0.15
	for k, v in pairs(props) do (f :: any)[k] = v end
	f.Parent = parent
	UITheme.AddCorner(f, 10)
	return f, UITheme.AddStroke(f, C.Border, 1.5, 0.4)
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = F.Body
	t.TextColor3 = C.TextPrimary
	t.TextSize = 13
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextWrapped = true
	for k, v in pairs(props) do (t :: any)[k] = v end
	t.Parent = parent
	return t
end

-- Small uppercase gold section tag, like "CLASS COMBAT SKILLS".
local function sectionTag(parent: Instance, text: string, props: { [string]: any }?): TextLabel
	local t = label(parent, { Text = string.upper(text), Font = F.Tag, TextSize = 12, TextColor3 = C.Gold, Size = UDim2.new(1, 0, 0, 18) })
	for k, v in pairs(props or {}) do (t :: any)[k] = v end
	return t
end

-- Gold gradient action button, like "CONFIRM & ENTER WORLD".
local function primaryButton(parent: Instance, text: string, props: { [string]: any }, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = C.Gold
	b.Font = F.Button
	b.TextSize = 16
	b.TextColor3 = Color3.fromRGB(20, 15, 10)
	b.Text = text
	for k, v in pairs(props) do (b :: any)[k] = v end
	b.Parent = parent
	UITheme.AddCorner(b, 8)
	local s = UITheme.AddStroke(b, C.GoldLight, 2, 0)
	UITheme.AddGradient(b, C.GoldLight, C.Gold, 90)
	UITheme.MakeButtonInteractive(b, s, C.GoldLight, SoundManager.PlayHover, onClick)
	return b
end

-- Dark secondary button, like the carousel arrows / tabs.
local function secondaryButton(parent: Instance, text: string, props: { [string]: any }, onClick: () -> ()): (TextButton, UIStroke)
	local b = Instance.new("TextButton")
	b.AutoButtonColor = false
	b.BackgroundColor3 = C.SurfaceAlt
	b.Font = F.Button
	b.TextSize = 13
	b.TextColor3 = C.TextPrimary
	b.Text = text
	for k, v in pairs(props) do (b :: any)[k] = v end
	b.Parent = parent
	UITheme.AddCorner(b, 8)
	local s = UITheme.AddStroke(b, C.Border, 1.5, 0.2)
	UITheme.MakeButtonInteractive(b, s, C.Gold, SoundManager.PlayHover, function()
		SoundManager.PlaySelect()
		onClick()
	end)
	return b, s
end

local function rarityColor(r: string): Color3
	return GachaConfig.Rarities[r] and GachaConfig.Rarities[r].color or C.TextPrimary
end
local function owned(id: string): boolean
	local r = GachaRewards.Get(id)
	if not r then return false end
	if r.type == "character" or r.type == "exclusive" then return state.collection.characters[id] ~= nil end
	if r.type == "relic" then return state.collection.relics[id] ~= nil end
	if r.type == "cosmetic" then return state.collection.cosmetics[id] == true end
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
	vg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(0.35, 1), NumberSequenceKeypoint.new(0.65, 1), NumberSequenceKeypoint.new(1, 0.2) })
	vg.Parent = vignette

	-- ── Top bar ──
	label(sg, { Text = "SUMMONING SANCTUM", Font = F.Title, TextSize = 26, TextColor3 = C.Gold, TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 22), Size = UDim2.fromOffset(600, 32) })
	local banner = GachaConfig.Banners[GachaConfig.DefaultBanner]
	label(sg, { Text = string.upper(banner.name), Font = F.Tag, TextSize = 12, TextColor3 = C.TextMuted, TextXAlignment = Enum.TextXAlignment.Center,
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 54), Size = UDim2.fromOffset(600, 16) })
	secondaryButton(sg, "◀  BACK", { Position = UDim2.fromOffset(24, 22), Size = UDim2.fromOffset(110, 44), TextSize = 14 }, function()
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
	for _, key in ipairs({ "tickets", "crystals", "soulShards", "relicDust", "ascension" }) do
		local pill = panel(currencyRow, { Size = UDim2.fromOffset(100, 44) })
		pills[key] = label(pill, { Font = F.Header, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromScale(1, 1) })
	end
	table.insert(refreshers, function()
		for key, t in pairs(pills) do
			t.Text = `{GachaConfig.Currencies[key].glyph} {state.currencies[key] or 0}`
		end
	end)

	-- ── Left: featured banner ──
	local featured = GachaRewards.Get(banner.featured)
	local fColor = featured and (featured.accent or rarityColor(featured.rarity)) or C.Gold
	local left, leftStroke = panel(sg, { Position = UDim2.fromOffset(24, 84), Size = UDim2.new(0, 340, 1, -200) })
	leftStroke.Color = fColor
	UITheme.AddPadding(left, 16, 16, 16, 16)
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 8)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = left
	sectionTag(left, "Featured", { LayoutOrder = 1 })
	if featured then
		label(left, { Text = featured.glyph, TextSize = 64, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0, 80), LayoutOrder = 2 })
		label(left, { Text = string.upper(featured.name), Font = F.Title, TextSize = 24, TextColor3 = fColor, Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 3 })
		label(left, { Text = `[{string.upper(featured.rarity)}]`, Font = F.Tag, TextSize = 12, TextColor3 = rarityColor(featured.rarity), Size = UDim2.new(1, 0, 0, 16), LayoutOrder = 4 })
		label(left, { Text = featured.description, TextSize = 13, TextColor3 = C.TextSecondary, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 5 })
		sectionTag(left, "Rate-Up", { LayoutOrder = 6 })
		label(left, { Text = `When you summon a Legendary it is {featured.name} {math.floor(banner.featuredRate * 100)}% of the time. If it isn't, your next Legendary is guaranteed to be.`,
			TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 7 })
	end
	sectionTag(left, "Pity", { LayoutOrder = 8 })
	local pityText = label(left, { TextSize = 12, TextColor3 = C.TextSecondary, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 9 })
	local ratesBtn = secondaryButton(left, "RATES & PITY", { Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 10 }, function() end)
	table.insert(refreshers, function()
		local pity = state.pity or {}
		pityText.Text = `Epic or better within {math.max(0, GachaConfig.Pity.epicEvery - (pity.sinceEpic or 0))} summons.\nLegendary guaranteed within {math.max(0, GachaConfig.Pity.legendaryHard - (pity.sinceLegendary or 0))} summons.{if pity.guaranteedFeatured then "\nYour next Legendary is the featured one." else ""}`
	end)

	-- ── Right: collection / shop ──
	local right = panel(sg, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 84), Size = UDim2.new(0, 360, 1, -200) })
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
		label(row, { Text = r.glyph, TextSize = 24, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(46, 54) })
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
		tag("Exclusive Characters")
		local any = false
		for _, r in ipairs(GachaRewards.All) do
			local o = r.type == "exclusive" and state.collection.characters[r.id]
			if o then
				any = true
				local active = state.equipped.variants[r.classId] == r.id
				local className = (ClassData.GetClass(r.classId :: string) or { name = r.classId }).name
				order += 1
				itemRow(pg, order, r, `{string.upper(className)} · ASCENSION {o.ascension}/{GachaConfig.Duplicates.maxAscension}`,
					if active then "UNEQUIP" else "EQUIP", function()
						act({ kind = "equipVariant", classId = r.classId, id = if active then nil else r.id })
					end, active)
			end
		end
		if not any then
			order += 1
			label(pg, { Text = "None yet — summon to discover exclusive characters.", TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 20), LayoutOrder = order })
		end
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
		secondaryButton(pg, `REFINE · {per} SHARDS → 1 SOUL  ({state.currencies.soulShards or 0} 🔮)`, { Size = UDim2.new(1, -6, 0, 38), LayoutOrder = order, TextColor3 = C.Gold }, function()
			act({ kind = "refineShards" })
		end)
	end)

	table.insert(refreshers, function()
		local pg = rightPages.Shop
		for _, c in ipairs(pg:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		sectionTag(pg, "Crystals", { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 22) })
		if #state.products == 0 then
			label(pg, { Text = "Crystal packs are coming soon.\n\nSummon Tickets are earned from bosses and every few dozen kills.",
				TextSize = 13, TextColor3 = C.TextSecondary, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
		else
			label(pg, { Text = "Crystals are premium currency used for summons. See Rates & Pity for the exact odds before summoning.",
				TextSize = 12, TextColor3 = C.TextMuted, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2 })
			for i, prod in ipairs(state.products) do
				primaryButton(pg, `💎 {prod.label}`, { Size = UDim2.new(1, -6, 0, 44), LayoutOrder = 2 + i }, function()
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
		rline("DUPLICATES", C.Gold, F.Tag, 12)
		local D = GachaConfig.Duplicates
		rline(`• Characters: the first copy Awakens them; further copies become Soul Shards ({D.shardsPerSoul} Shards = 1 Soul).`)
		rline(`• Exclusive characters: copies raise Ascension (max {D.maxAscension}), then become Ascension Sigils.`)
		rline(`• Relics: copies raise level (max {D.maxRelicLevel}), then become Relic Dust. Titles: copies become Relic Dust.`)
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
				rline(`{r.glyph} {displayName(r)} ({rarity}) — {string.format("%.3f", pct)}%`, rarityColor(rarity))
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
				card.LayoutOrder = i
				card.ZIndex = 32
				card.Parent = grid
				UITheme.AddCorner(card, 8)
				local s = UITheme.AddStroke(card, rarityColor(r.rarity), 2, 0.1)
				UITheme.MakeButtonInteractive(card, s, C.GoldLight, SoundManager.PlayHover, function()
					SoundManager.PlaySelect()
					showcase(r)
				end)
				label(card, { Text = r.glyph, TextSize = 38, TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.new(1, 0, 0.44, 0), ZIndex = 33 })
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
		for _, res in ipairs(list) do
			local r = GachaRewards.Get(res.id)
			if r and (not best or (table.find(GachaConfig.RarityOrder, r.rarity) or 0) > (table.find(GachaConfig.RarityOrder, best.rarity) or 0)) then best = r end
		end
		if not best then
			pulling = false
			return
		end
		sg.Enabled = false
		LobbyCamera.StopImmediate()
		SummonCinematic.Play(best, function()
			sg.Enabled = true
			LobbyCamera.SetClassSelectView()
			showResults(list)
			pulling = false
		end)
	end)

	showRight("Collection")
	for _, f in ipairs(refreshers) do f() end
	return sg
end

function SummonScreen.Open()
	if not gui then gui = build() end
	hideOtherGuis(true)
	(gui :: ScreenGui).Enabled = true
	Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer()
end

function SummonScreen.Close()
	if gui then gui.Enabled = false end
	hideOtherGuis(false)
end

return SummonScreen
