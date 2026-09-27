--[[
	SummonScreen.luau
	The summon overlay: banner + summon buttons, Rates & Pity (generated from
	GachaConfig, so displayed odds always match the server), results grid,
	collection (equip relics, choose exclusive characters, refine shards) and
	the crystal shop (only products with a configured id are shown).

	SummonScreen.Open() / SummonScreen.Close()
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local SummonCinematic = require(script.Parent.Parent:WaitForChild("SummonCinematic"))
local LobbyCamera = require(script.Parent.Parent:WaitForChild("LobbyCamera"))

local player = Players.LocalPlayer

local SummonScreen = {}

local BG = Color3.fromRGB(14, 13, 20)
local PANEL = Color3.fromRGB(24, 22, 32)
local TEXT = Color3.fromRGB(235, 232, 240)
local MUTED = Color3.fromRGB(150, 146, 160)
local GOLD = Color3.fromRGB(235, 195, 90)

local state: any = { currencies = {}, collection = { characters = {}, relics = {}, cosmetics = {} }, equipped = { relics = {}, variants = {} }, pity = {}, products = {} }
local gui: ScreenGui? = nil
local refreshers: { () -> () } = {}
local payWith = "tickets"
local pulling = false

-- ─── UI helpers ─────────────────────────────────────────────────────────────
local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
end
local function stroke(p: Instance, color: Color3, th: number, tr: number?): UIStroke
	local s = Instance.new("UIStroke")
	s.Color, s.Thickness, s.Transparency = color, th, tr or 0
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = p
	return s
end
local function text(parent: Instance, props: { [string]: any }): TextLabel
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.GothamMedium
	t.TextColor3 = TEXT
	t.TextSize = 14
	t.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props) do (t :: any)[k] = v end
	t.Parent = parent
	return t
end
local function button(parent: Instance, label: string, color: Color3, props: { [string]: any }): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.Font = Enum.Font.GothamBold
	b.TextSize = 15
	b.TextColor3 = Color3.fromRGB(20, 16, 12)
	b.Text = label
	for k, v in pairs(props) do (b :: any)[k] = v end
	b.Parent = parent
	corner(b, 8)
	return b
end
local function rarityColor(r: string): Color3
	return GachaConfig.Rarities[r] and GachaConfig.Rarities[r].color or TEXT
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
	if r.secret and not owned(r.id) then return "???" end
	return r.name
end

-- Hide every other ScreenGui during the cinematic (restored afterwards).
local hiddenGuis: { ScreenGui } = {}
local function hideOtherGuis(hide: boolean)
	if hide then
		for _, g in ipairs(player.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and g.Name ~= "SummonCinematicGui" then
				g.Enabled = false
				table.insert(hiddenGuis, g)
			end
		end
	else
		for _, g in ipairs(hiddenGuis) do g.Enabled = true end
		table.clear(hiddenGuis)
	end
end

-- ─── Build ──────────────────────────────────────────────────────────────────
local function build()
	local sg = Instance.new("ScreenGui")
	sg.Name = "SummonScreen"
	sg.DisplayOrder = 50
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.Enabled = false
	sg.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("Frame")
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.35
	dim.Parent = sg

	local main = Instance.new("Frame")
	main.AnchorPoint = Vector2.new(0.5, 0.5)
	main.Position = UDim2.fromScale(0.5, 0.5)
	main.Size = UDim2.new(0.72, 0, 0.8, 0)
	main.BackgroundColor3 = BG
	main.Parent = sg
	corner(main, 12)
	stroke(main, GOLD, 1.5, 0.3)

	-- Header: tabs, currencies, close.
	local header = Instance.new("Frame")
	header.BackgroundTransparency = 1
	header.Size = UDim2.new(1, -24, 0, 44)
	header.Position = UDim2.fromOffset(12, 10)
	header.Parent = main
	local tabs: { [string]: TextButton } = {}
	local pages: { [string]: Frame } = {}
	local function showTab(name: string)
		for n, pg in pairs(pages) do pg.Visible = n == name end
		for n, b in pairs(tabs) do
			b.BackgroundColor3 = if n == name then GOLD else PANEL
			b.TextColor3 = if n == name then Color3.fromRGB(20, 16, 12) else TEXT
		end
	end
	for i, name in ipairs({ "Summon", "Collection", "Shop" }) do
		tabs[name] = button(header, string.upper(name), PANEL, { Size = UDim2.fromOffset(120, 34), Position = UDim2.fromOffset((i - 1) * 128, 4) })
		tabs[name].MouseButton1Click:Connect(function() showTab(name) end)
	end
	local currencyBar = text(header, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -48, 0, 4), Size = UDim2.fromOffset(460, 34),
		TextXAlignment = Enum.TextXAlignment.Right, Font = Enum.Font.GothamBold, TextSize = 15 })
	local close = button(header, "✕", Color3.fromRGB(70, 60, 70), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 4), Size = UDim2.fromOffset(38, 34), TextColor3 = TEXT })
	close.MouseButton1Click:Connect(function() SummonScreen.Close() end)
	table.insert(refreshers, function()
		local c = state.currencies
		local C = GachaConfig.Currencies
		currencyBar.Text = `{C.tickets.glyph} {c.tickets or 0}   {C.crystals.glyph} {c.crystals or 0}   {C.soulShards.glyph} {c.soulShards or 0}   {C.relicDust.glyph} {c.relicDust or 0}   {C.ascension.glyph} {c.ascension or 0}`
	end)

	local body = Instance.new("Frame")
	body.BackgroundTransparency = 1
	body.Position = UDim2.fromOffset(12, 62)
	body.Size = UDim2.new(1, -24, 1, -74)
	body.Parent = main
	for _, name in ipairs({ "Summon", "Collection", "Shop" }) do
		local pg = Instance.new("Frame")
		pg.Name = name
		pg.BackgroundTransparency = 1
		pg.Size = UDim2.fromScale(1, 1)
		pg.Parent = body
		pages[name] = pg
	end

	-- ── Summon tab ──
	local banner = GachaConfig.Banners[GachaConfig.DefaultBanner]
	local featured = GachaRewards.Get(banner.featured)
	local bannerCard = Instance.new("Frame")
	bannerCard.Size = UDim2.new(1, 0, 0.62, 0)
	bannerCard.BackgroundColor3 = PANEL
	bannerCard.Parent = pages.Summon
	corner(bannerCard, 10)
	local fColor = featured and (featured.accent or rarityColor(featured.rarity)) or GOLD
	stroke(bannerCard, fColor, 2, 0.2)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(40, 32, 20), Color3.fromRGB(18, 16, 26))
	grad.Rotation = 90
	grad.Parent = bannerCard
	text(bannerCard, { Text = string.upper(banner.name), Font = Enum.Font.Antique, TextSize = 38, TextColor3 = GOLD, Position = UDim2.fromOffset(24, 18), Size = UDim2.new(1, -48, 0, 44) })
	text(bannerCard, { Text = banner.subtitle, TextSize = 18, TextColor3 = MUTED, Position = UDim2.fromOffset(24, 62), Size = UDim2.new(1, -48, 0, 24) })
	if featured then
		text(bannerCard, { Text = featured.glyph, TextSize = 120, TextColor3 = fColor, TextXAlignment = Enum.TextXAlignment.Center,
			AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -40, 0.55, 0), Size = UDim2.fromOffset(200, 160) })
		text(bannerCard, { Text = `✦ {featured.name} ✦`, Font = Enum.Font.Antique, TextSize = 30, TextColor3 = fColor, Position = UDim2.fromOffset(24, 110), Size = UDim2.new(0.6, 0, 0, 34) })
		text(bannerCard, { Text = `{string.upper(featured.rarity)} · {featured.description}`, TextSize = 15, TextColor3 = TEXT, TextWrapped = true,
			Position = UDim2.fromOffset(24, 148), Size = UDim2.new(0.58, 0, 0, 44), TextYAlignment = Enum.TextYAlignment.Top })
		text(bannerCard, { Text = `Rate-up: a Legendary is {featured.name} {math.floor(banner.featuredRate * 100)}% of the time — if not, the next Legendary is guaranteed to be.`,
			TextSize = 13, TextColor3 = MUTED, TextWrapped = true, Position = UDim2.new(0, 24, 1, -52), Size = UDim2.new(0.62, 0, 0, 40), TextYAlignment = Enum.TextYAlignment.Top })
	end

	local pityLabel = text(pages.Summon, { Position = UDim2.new(0, 0, 0.64, 4), Size = UDim2.new(1, 0, 0, 22), TextColor3 = MUTED, TextSize = 14 })
	local msgLabel = text(pages.Summon, { Position = UDim2.new(0, 0, 0.64, 28), Size = UDim2.new(1, 0, 0, 22), TextColor3 = Color3.fromRGB(255, 120, 120), TextSize = 14 })
	local payToggle = button(pages.Summon, "", PANEL, { Position = UDim2.new(0, 0, 1, -58), Size = UDim2.fromOffset(170, 50), TextColor3 = TEXT, TextSize = 14 })
	payToggle.MouseButton1Click:Connect(function()
		payWith = if payWith == "tickets" then "crystals" else "tickets"
		for _, f in ipairs(refreshers) do f() end
	end)
	local ratesBtn = button(pages.Summon, "RATES & PITY", PANEL, { Position = UDim2.new(0, 180, 1, -58), Size = UDim2.fromOffset(150, 50), TextColor3 = TEXT, TextSize = 14 })
	local pull1 = button(pages.Summon, "", GOLD, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -236, 1, -58), Size = UDim2.fromOffset(220, 50) })
	local pull10 = button(pages.Summon, "", Color3.fromRGB(255, 170, 60), { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 1, -58), Size = UDim2.fromOffset(226, 50) })
	table.insert(refreshers, function()
		local pity = state.pity or {}
		pityLabel.Text = `Pity — Epic+ in {math.max(0, GachaConfig.Pity.epicEvery - (pity.sinceEpic or 0))} · Legendary+ guaranteed in {math.max(0, GachaConfig.Pity.legendaryHard - (pity.sinceLegendary or 0))}{if pity.guaranteedFeatured then " · next Legendary is FEATURED" else ""}`
		local free = GachaConfig.FREE_SUMMONS
		payToggle.Visible = not free
		if state.paidRestricted and payWith == "crystals" then payWith = "tickets" end
		local g = GachaConfig.Currencies[payWith].glyph
		payToggle.Text = `Pay with: {GachaConfig.Currencies[payWith].name}s`
		pull1.Text = if free then "SUMMON ×1 · FREE" else `SUMMON ×1 · {GachaConfig.Cost.single[payWith]} {g}`
		pull10.Text = if free then "SUMMON ×10 · FREE" else `SUMMON ×10 · {GachaConfig.Cost.multi[payWith]} {g}`
		msgLabel.Text = if state.paidRestricted then "Crystal summons are unavailable in your region; Summon Tickets still work." else ""
	end)
	local function doPull(count: number)
		if pulling then return end
		pulling = true
		msgLabel.Text = ""
		Network.GetRemoteEvent(Network.Remotes.Summon):FireServer({ banner = GachaConfig.DefaultBanner, count = count, pay = payWith })
		task.delay(6, function() pulling = false end) -- safety if the server never answers
	end
	pull1.MouseButton1Click:Connect(function() doPull(1) end)
	pull10.MouseButton1Click:Connect(function() doPull(10) end)

	-- ── Rates & Pity panel (odds disclosure) ──
	local rates = Instance.new("ScrollingFrame")
	rates.Visible = false
	rates.AnchorPoint = Vector2.new(0.5, 0.5)
	rates.Position = UDim2.fromScale(0.5, 0.5)
	rates.Size = UDim2.new(0.6, 0, 0.8, 0)
	rates.BackgroundColor3 = BG
	rates.ScrollBarThickness = 6
	rates.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rates.CanvasSize = UDim2.new()
	rates.ZIndex = 20
	rates.Parent = sg
	corner(rates, 10)
	stroke(rates, GOLD, 1.5)
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 4)
	rl.Parent = rates
	local rp = Instance.new("UIPadding")
	rp.PaddingLeft, rp.PaddingRight, rp.PaddingTop, rp.PaddingBottom = UDim.new(0, 18), UDim.new(0, 18), UDim.new(0, 14), UDim.new(0, 14)
	rp.Parent = rates
	local function rline(str: string, color: Color3?, size: number?, bold: boolean?)
		text(rates, { Text = str, TextColor3 = color or TEXT, TextSize = size or 14, Font = if bold then Enum.Font.GothamBold else Enum.Font.GothamMedium,
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, TextWrapped = true, ZIndex = 21 })
	end
	local function buildRates()
		for _, c in ipairs(rates:GetChildren()) do
			if c:IsA("TextLabel") or c:IsA("TextButton") then c:Destroy() end
		end
		rline("RATES & PITY", GOLD, 24, true)
		rline(`Banner: {banner.name}. Every summon is random. These are the exact odds the server uses.`, MUTED)
		rline("Base rarity odds (per summon)", GOLD, 17, true)
		for _, r in ipairs(GachaConfig.RarityOrder) do
			rline(`{r}: {GachaConfig.Rarities[r].odds}%`, rarityColor(r), 15, true)
		end
		rline("Pity rules", GOLD, 17, true)
		local P = GachaConfig.Pity
		rline(`• At least one Epic or better within every {P.epicEvery} summons.`)
		rline(`• From summon #{P.legendarySoftStart} without a Legendary, Legendary odds rise by {P.legendarySoftStep}% per summon; summon #{P.legendaryHard} is a guaranteed Legendary or better.`)
		rline(`• Every ×10 summon contains at least one {P.multiGuarantee} or better.`)
		if featured then
			rline(`• When you get a Legendary, it is {featured.name} {math.floor(banner.featuredRate * 100)}% of the time. If it isn't, your next Legendary is guaranteed to be {featured.name}.`)
		end
		rline("• Pity is tracked per banner and carries over between sessions.")
		rline("Duplicates", GOLD, 17, true)
		local D = GachaConfig.Duplicates
		rline(`• Characters: first copy Awakens them; further copies become Soul Shards ({D.shardsPerSoul} Shards = 1 Soul for talents).`)
		rline(`• Exclusive characters: copies raise Ascension (max {D.maxAscension}), then become Ascension Sigils.`)
		rline(`• Relics: copies raise level (max {D.maxRelicLevel}), then become Relic Dust. Titles: copies become Relic Dust.`)
		rline("Individual reward odds (per summon, before pity)", GOLD, 17, true)
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
		local closeRates = button(rates, "CLOSE", GOLD, { Size = UDim2.fromOffset(140, 40), ZIndex = 21 })
		closeRates.MouseButton1Click:Connect(function() rates.Visible = false end)
	end
	ratesBtn.MouseButton1Click:Connect(function()
		buildRates()
		rates.Visible = true
	end)

	-- ── Results panel ──
	local results = Instance.new("Frame")
	results.Visible = false
	results.AnchorPoint = Vector2.new(0.5, 0.5)
	results.Position = UDim2.fromScale(0.5, 0.5)
	results.Size = UDim2.new(0.72, 0, 0.6, 0)
	results.BackgroundColor3 = BG
	results.ZIndex = 30
	results.Parent = sg
	corner(results, 12)
	stroke(results, GOLD, 1.5)
	text(results, { Text = "SUMMON RESULTS", Font = Enum.Font.Antique, TextSize = 30, TextColor3 = GOLD, TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 10), ZIndex = 31 })
	local grid = Instance.new("Frame")
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(20, 60)
	grid.Size = UDim2.new(1, -40, 1, -130)
	grid.ZIndex = 31
	grid.Parent = results
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.19, 0, 0.48, 0)
	gl.CellPadding = UDim2.new(0.0125, 0, 0.04, 0)
	gl.HorizontalAlignment = Enum.HorizontalAlignment.Center
	gl.Parent = grid
	local cont = button(results, "CONTINUE", GOLD, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(200, 46), ZIndex = 31 })
	cont.MouseButton1Click:Connect(function() results.Visible = false end)
	local function showResults(list: { any })
		for _, c in ipairs(grid:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, res in ipairs(list) do
			local r = GachaRewards.Get(res.id)
			if r then
				local card = Instance.new("Frame")
				card.BackgroundColor3 = PANEL
				card.ZIndex = 32
				card.LayoutOrder = i
				card.Parent = grid
				corner(card, 8)
				stroke(card, rarityColor(r.rarity), 2)
				text(card, { Text = r.glyph, TextSize = 40, TextColor3 = r.accent or rarityColor(r.rarity), TextXAlignment = Enum.TextXAlignment.Center,
					Size = UDim2.new(1, 0, 0.45, 0), ZIndex = 33 })
				text(card, { Text = r.name, Font = Enum.Font.GothamBold, TextSize = 13, TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true,
					Position = UDim2.fromScale(0, 0.45), Size = UDim2.new(1, 0, 0.22, 0), ZIndex = 33 })
				text(card, { Text = string.upper(r.rarity), TextSize = 11, TextColor3 = rarityColor(r.rarity), TextXAlignment = Enum.TextXAlignment.Center,
					Position = UDim2.fromScale(0, 0.66), Size = UDim2.new(1, 0, 0.12, 0), ZIndex = 33 })
				text(card, { Text = res.note or "", TextSize = 11, TextColor3 = if res.isNew then GOLD else MUTED, TextXAlignment = Enum.TextXAlignment.Center,
					TextWrapped = true, Position = UDim2.fromScale(0, 0.8), Size = UDim2.new(1, 0, 0.18, 0), ZIndex = 33 })
				card.BackgroundTransparency = 1
				TweenService:Create(card, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, i * 0.06), { BackgroundTransparency = 0 }):Play()
			end
		end
		results.Visible = true
	end

	-- ── Collection tab ──
	local coll = Instance.new("ScrollingFrame")
	coll.BackgroundTransparency = 1
	coll.Size = UDim2.fromScale(1, 1)
	coll.ScrollBarThickness = 6
	coll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	coll.CanvasSize = UDim2.new()
	coll.Parent = pages.Collection
	local cl = Instance.new("UIListLayout")
	cl.Padding = UDim.new(0, 6)
	cl.SortOrder = Enum.SortOrder.LayoutOrder
	cl.Parent = coll
	local function rebuildCollection()
		for _, c in ipairs(coll:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local order = 0
		local function heading(str: string)
			order += 1
			text(coll, { Text = str, Font = Enum.Font.GothamBold, TextSize = 18, TextColor3 = GOLD, Size = UDim2.new(1, 0, 0, 28), LayoutOrder = order })
		end
		local function row(r: any, info: string, actionLabel: string?, onAction: (() -> ())?, active: boolean?)
			order += 1
			local f = Instance.new("Frame")
			f.BackgroundColor3 = PANEL
			f.Size = UDim2.new(1, -10, 0, 44)
			f.LayoutOrder = order
			f.Parent = coll
			corner(f, 6)
			stroke(f, if active then GOLD else rarityColor(r.rarity), if active then 2 else 1, if active then 0 else 0.5)
			text(f, { Text = r.glyph, TextSize = 24, TextColor3 = r.accent or rarityColor(r.rarity), TextXAlignment = Enum.TextXAlignment.Center, Size = UDim2.fromOffset(44, 44) })
			text(f, { Text = `{r.name}  ·  {info}`, Font = Enum.Font.GothamBold, Position = UDim2.fromOffset(48, 2), Size = UDim2.new(1, -200, 0, 20) })
			text(f, { Text = r.description, TextSize = 12, TextColor3 = MUTED, Position = UDim2.fromOffset(48, 22), Size = UDim2.new(1, -200, 0, 18) })
			if actionLabel and onAction then
				local b = button(f, actionLabel, if active then Color3.fromRGB(80, 70, 80) else GOLD, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(130, 32), TextSize = 13,
					TextColor3 = if active then TEXT else Color3.fromRGB(20, 16, 12) })
				b.MouseButton1Click:Connect(onAction)
			end
		end
		local function act(payload: any)
			Network.GetRemoteEvent(Network.Remotes.GachaAction):FireServer(payload)
		end

		heading(`Exclusive Characters — equip one per class (active in runs as that class)`)
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "exclusive" then
				local o = state.collection.characters[r.id]
				if o then
					local active = state.equipped.variants[r.classId] == r.id
					local className = (ClassData.GetClass(r.classId :: string) or { name = r.classId }).name
					row(r, `{className} · Ascension {o.ascension}/{GachaConfig.Duplicates.maxAscension}`, if active then "UNEQUIP" else "EQUIP", function()
						act({ kind = "equipVariant", classId = r.classId, id = if active then nil else r.id })
					end, active)
				end
			end
		end
		heading(`Relics — up to {GachaConfig.RelicSlots} equipped (active in every run)`)
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "relic" then
				local o = state.collection.relics[r.id]
				if o then
					local active = table.find(state.equipped.relics, r.id) ~= nil
					row(r, `Level {o.level}/{GachaConfig.Duplicates.maxRelicLevel}`, if active then "UNEQUIP" else "EQUIP", function()
						act({ kind = if active then "unequipRelic" else "equipRelic", id = r.id })
					end, active)
				end
			end
		end
		heading("Awakened Characters")
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "character" and state.collection.characters[r.id] then
				row(r, "Awakened")
			end
		end
		heading("Titles")
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "cosmetic" and state.collection.cosmetics[r.id] then row(r, "Owned") end
		end
		heading("Soul Shards")
		order += 1
		local per = GachaConfig.Duplicates.shardsPerSoul
		local refine = button(coll, `REFINE SHARDS → SOULS  ({per} Shards = 1 Soul, have {state.currencies.soulShards or 0})`, GOLD,
			{ Size = UDim2.new(1, -10, 0, 40), LayoutOrder = order, TextSize = 14 })
		refine.MouseButton1Click:Connect(function() act({ kind = "refineShards" }) end)
	end
	table.insert(refreshers, rebuildCollection)

	-- ── Shop tab ──
	local shopInfo = text(pages.Shop, { Size = UDim2.new(1, 0, 0, 60), TextWrapped = true, TextColor3 = MUTED, TextYAlignment = Enum.TextYAlignment.Top })
	local shopList = Instance.new("Frame")
	shopList.BackgroundTransparency = 1
	shopList.Position = UDim2.fromOffset(0, 70)
	shopList.Size = UDim2.new(1, 0, 1, -70)
	shopList.Parent = pages.Shop
	local sl = Instance.new("UIListLayout")
	sl.Padding = UDim.new(0, 8)
	sl.Parent = shopList
	table.insert(refreshers, function()
		for _, c in ipairs(shopList:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		if #state.products == 0 then
			shopInfo.Text = "Crystal packs are coming soon. Summon Tickets are earned from bosses and every few dozen kills."
		else
			shopInfo.Text = "Crystals are premium currency used for summons. Check Rates & Pity for the exact odds before summoning."
			for _, prod in ipairs(state.products) do
				local b = button(shopList, `💎 {prod.label}`, GOLD, { Size = UDim2.new(0, 320, 0, 46) })
				b.MouseButton1Click:Connect(function()
					Network.GetRemoteEvent(Network.Remotes.GachaAction):FireServer({ kind = "buyCrystals", id = prod.id })
				end)
			end
		end
	end)

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
			msgLabel.Text = payload.error
			return
		end
		local list = payload.results or {}
		-- Cinematic for the best pull, then the results grid.
		local best = nil
		for _, res in ipairs(list) do
			local r = GachaRewards.Get(res.id)
			if r and (not best or table.find(GachaConfig.RarityOrder, r.rarity) > table.find(GachaConfig.RarityOrder, best.rarity)) then best = r end
		end
		if not best then
			pulling = false
			return
		end
		sg.Enabled = false
		hideOtherGuis(true)
		LobbyCamera.StopImmediate()
		SummonCinematic.Play(best, function()
			hideOtherGuis(false)
			sg.Enabled = true
			LobbyCamera.SetClassSelectView()
			showResults(list)
			pulling = false
		end)
	end)
	Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer()

	showTab("Summon")
	for _, f in ipairs(refreshers) do f() end
	return sg
end

function SummonScreen.Open()
	if not gui then gui = build() end
	(gui :: ScreenGui).Enabled = true
	Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer()
end

function SummonScreen.Close()
	if gui then gui.Enabled = false end
end

return SummonScreen
