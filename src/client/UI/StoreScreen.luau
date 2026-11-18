--!strict
--[[
	StoreScreen.luau
	The lobby's two shops, plain Roblox-style windows, every item on a card
	with a live preview of it turning in a viewport (RewardPreview, as the
	summon banners show their featured reward):

	  "summon"   THE SUMMON SHOP: the classes still locked (Soul Essence, or
	             Robux where a class has a product), the Essence Shop's armours
	             and variant (Soul Essence / Relic Dust), Pull Ticket packs
	             (Robux; not where paid random items are restricted)
	  "mounts"   THE MOUNTS SHOP: every mount that can be summoned, for Robux
	             (StoreConfig: one Developer Product each; "SOON" while a
	             product id is 0)

	Eight cards a page (only those eight previews are alive at once). Closed
	by its X or a click outside it (ClickOutside).

	  StoreScreen.Open("summon" | "mounts") / Close()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local RewardPreview = require(script.Parent.Parent:WaitForChild("RewardPreview"))
local ClickOutside = require(script.Parent:WaitForChild("ClickOutside"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local player = Players.LocalPlayer

local StoreScreen = {}

local W, H = 900, 640
local PER_PAGE = 8
local BG = Color3.fromRGB(25, 27, 29)
local CARD = Color3.fromRGB(46, 48, 51)
local GREEN = Color3.fromRGB(0, 162, 95)
local GREY = Color3.fromRGB(80, 82, 86)
local FONT = Enum.Font.GothamMedium
local BOLD = Enum.Font.GothamBold
local FIGURE = { class = true, character = true, variant = true, armor = true }

-- A way to buy: enabled (green), or not: `poor` (can't afford it: the price
-- in red, Roblox's convention) or plain grey (owned, not on sale yet).
type Buy = { text: string, enabled: boolean, poor: boolean?, onClick: (() -> ())? }
type Item = { reward: any?, glyph: string?, name: string, sub: string, color: Color3, buys: { Buy }, locked: boolean?, best: boolean? }
local RED = Color3.fromRGB(255, 92, 92)

local gui: ScreenGui? = nil
local titleLabel: TextLabel? = nil
local grid: Frame? = nil
local pageLabel: TextLabel? = nil
local status: TextLabel? = nil
local mode = "summon"
local page = 1
local state: any = { currencies = {}, collection = { cosmetics = {}, characters = {}, relics = {} } }
local cleanups: { () -> () } = {}

local function corner(inst: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = inst
end

local function rarityColor(r: string?): Color3
	local info = r and (GachaConfig.Rarities :: any)[r]
	return if info then info.color else Color3.new(1, 1, 1)
end

local function owned(r: any): boolean
	local c = state.collection or {}
	if r.type == "class" then return state.classes ~= nil and state.classes[r.classId] == true end
	if r.type == "character" or r.type == "variant" then return (c.characters or {})[r.id] ~= nil end
	if r.type == "relic" then return (c.relics or {})[r.id] ~= nil end
	return (c.cosmetics or {})[r.id] == true
end

local function act(payload: any)
	Network.GetRemoteEvent(Network.Remotes.GachaAction):FireServer(payload)
end

local function say(text: string)
	if status then status.Text = text end
end

-- ── What's on sale ──────────────────────────────────────────────────────────
local function summonItems(): { Item }
	local out: { Item } = {}
	local cur = state.currencies or {}
	-- the classes still locked
	for _, r in ipairs(GachaRewards.All :: { any }) do
		if r.type == "class" and not owned(r) then
			local buys: { Buy } = {}
			local price = (GachaConfig.ClassEssencePrice :: any)[r.rarity]
			if price then
				local can = (cur.soulEssence or 0) >= price
				table.insert(buys, { text = `{price} Essence`, enabled = can, poor = not can, onClick = function()
					act({ kind = "unlockClass", classId = r.classId })
				end })
			end
			local robux = (state.classProducts or {})[r.classId]
			if robux then
				table.insert(buys, { text = `R$ {robux}`, enabled = true, onClick = function()
					act({ kind = "buyClassRobux", classId = r.classId })
				end })
			end
			table.insert(out, { reward = r, name = r.name, sub = `{r.rarity} class`, color = rarityColor(r.rarity), buys = buys })
		end
	end
	-- the Essence Shop
	for _, it in ipairs(GachaConfig.ShopItems :: { any }) do
		local r = GachaRewards.Get(it.id)
		if not r then continue end
		local buys: { Buy } = {}
		if owned(r) then
			table.insert(buys, { text = "Owned", enabled = false })
		else
			for _, currency in ipairs({ "soulEssence", "relicDust" }) do
				local price = it.price[currency]
				if price then
					local can = (cur[currency] or 0) >= price
					table.insert(buys, { text = `{price} {if currency == "soulEssence" then "Essence" else "Dust"}`,
						enabled = can, poor = not can, onClick = function()
							act({ kind = "buyShopItem", id = r.id, pay = currency })
						end })
				end
			end
		end
		table.insert(out, { reward = r, name = r.name, sub = r.rarity, color = rarityColor(r.rarity), buys = buys })
	end
	-- Pull Ticket packs
	if not state.paidRestricted then
		-- (the most tickets per Robux: marked BEST VALUE, as Roblox's guidance
		-- has the best bundle stand out)
		local bestId, bestRate = nil, 0
		for _, prod in ipairs(GachaConfig.TicketProducts :: { any }) do
			local rate = prod.tickets / prod.robux
			if rate > bestRate then bestId, bestRate = prod.id, rate end
		end
		for _, prod in ipairs(GachaConfig.TicketProducts :: { any }) do
			local live = prod.productId > 0
			table.insert(out, { glyph = "🎟", name = prod.label, sub = "Pull Tickets", color = Color3.fromRGB(255, 214, 110),
				locked = not live, best = prod.id == bestId, buys = {
				{ text = if live then `R$ {prod.robux}` else `R$ {prod.robux} · SOON`, enabled = live, onClick = function()
					act({ kind = "buyTickets", id = prod.id })
				end },
			} })
		end
	end
	return out
end

local function mountItems(): { Item }
	local out: { Item } = {}
	for _, m in ipairs(StoreConfig.Mounts) do
		local r = GachaRewards.Get(m.rewardId)
		if not r then continue end
		local buy: Buy
		local locked = false
		if owned(r) then
			buy = { text = "Owned", enabled = false }
		elseif m.productId <= 0 then
			buy = { text = `R$ {m.robux} · SOON`, enabled = false }
			locked = true
		else
			buy = { text = `R$ {m.robux}`, enabled = true, onClick = function()
				Network.GetRemoteEvent(Network.Remotes.StoreAction):FireServer({ kind = "buyMount", rewardId = m.rewardId })
			end }
		end
		table.insert(out, { reward = r, name = r.name, sub = `{r.rarity} mount`, color = rarityColor(r.rarity), buys = { buy }, locked = locked })
	end
	return out
end

-- ── A card's live preview ───────────────────────────────────────────────────
local function preview(vp: ViewportFrame, reward: any)
	local world = Instance.new("WorldModel")
	world.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local ok, model, cleanup = pcall(RewardPreview.Build, reward)
	if not ok or not model then return end
	if cleanup then table.insert(cleanups, cleanup) end
	if FIGURE[reward.type] then
		model:PivotTo(CFrame.Angles(0, math.pi + math.rad(18), 0))
	end
	model.Parent = world
	if FIGURE[reward.type] then
		local target = Vector3.new(0, 0.6, 0)
		cam.CFrame = CFrame.lookAt(target + Vector3.new(0, 0.5, 11), target)
	else
		local center, ext = model:GetBoundingBox()
		local size = math.max(ext.X, ext.Y, ext.Z, 3)
		cam.FieldOfView = 32
		cam.CFrame = CFrame.lookAt(center.Position + Vector3.new(0, size * 0.18, size * 1.8 + 2), center.Position)
	end
end

local function clearCards()
	for _, c in ipairs(cleanups) do pcall(c) end
	table.clear(cleanups)
	if grid then
		for _, ch in ipairs(grid:GetChildren()) do
			if ch:IsA("GuiObject") then ch:Destroy() end
		end
	end
end

local function render()
	local g = grid
	if not (g and gui and gui.Enabled) then return end
	clearCards()
	local items = if mode == "mounts" then mountItems() else summonItems()
	local pages = math.max(1, math.ceil(#items / PER_PAGE))
	page = math.clamp(page, 1, pages)
	if pageLabel then pageLabel.Text = `{page} / {pages}` end
	for i = (page - 1) * PER_PAGE + 1, math.min(#items, page * PER_PAGE) do
		local it = items[i]
		local card = Instance.new("Frame")
		card.Name = "Card"
		card.LayoutOrder = i
		card.BackgroundColor3 = CARD
		card.BorderSizePixel = 0
		card.Parent = g
		corner(card, 8)
		local st = Instance.new("UIStroke")
		st.Color = if it.best then Color3.fromRGB(255, 214, 110) else it.color
		st.Transparency = if it.best then 0 else 0.5
		st.Thickness = if it.best then 3 else 1
		st.Parent = card
		-- the preview, on a soft backdrop in its rarity's colour
		local vp = Instance.new("ViewportFrame")
		vp.Name = "Preview"
		vp.Position = UDim2.fromOffset(6, 6)
		vp.Size = UDim2.new(1, -12, 1, -96)
		vp.BackgroundColor3 = it.color:Lerp(Color3.new(0, 0, 0), 0.75)
		vp.BorderSizePixel = 0
		vp.Ambient = Color3.fromRGB(170, 170, 180)
		vp.LightColor = Color3.fromRGB(255, 250, 240)
		vp.LightDirection = Vector3.new(-1, -1, -1)
		vp.Parent = card
		corner(vp, 6)
		if it.reward then
			preview(vp, it.reward)
		else
			local gl = Instance.new("TextLabel")
			gl.BackgroundTransparency = 1
			gl.Size = UDim2.fromScale(1, 1)
			gl.Font = BOLD
			gl.TextScaled = true
			gl.Text = it.glyph or "?"
			gl.TextColor3 = it.color
			gl.Parent = vp
			local pad = Instance.new("UIPadding")
			pad.PaddingTop, pad.PaddingBottom = UDim.new(0.2, 0), UDim.new(0.2, 0)
			pad.Parent = gl
		end
		-- not on sale yet: a lock over the preview (Roblox's "not unlocked" sign)
		if it.locked then
			local shade = Instance.new("Frame")
			shade.Name = "Locked"
			shade.AnchorPoint = Vector2.new(1, 0)
			shade.Position = UDim2.new(1, -8, 0, 8)
			shade.Size = UDim2.fromOffset(34, 34)
			shade.BackgroundColor3 = Color3.new(0, 0, 0)
			shade.BackgroundTransparency = 0.35
			shade.ZIndex = 3
			shade.Parent = vp
			corner(shade, 8)
			local ic = Icons.Draw("lock", shade, nil, 24)
			ic.Size = UDim2.fromScale(0.7, 0.7)
			for _, d in ipairs(ic:GetDescendants()) do
				if d:IsA("GuiObject") then d.ZIndex = 4 end
			end
			ic.ZIndex = 4
		end
		if it.best then
			local tag = Instance.new("TextLabel")
			tag.Name = "BestValue"
			tag.Position = UDim2.fromOffset(8, 8)
			tag.Size = UDim2.fromOffset(96, 22)
			tag.BackgroundColor3 = Color3.fromRGB(255, 196, 60)
			tag.BorderSizePixel = 0
			tag.Font = BOLD
			tag.TextSize = 12
			tag.TextColor3 = Color3.fromRGB(40, 28, 0)
			tag.Text = "BEST VALUE"
			tag.ZIndex = 3
			tag.Parent = vp
			corner(tag, 6)
		end
		local function text(t: string, y: number, size: number, color: Color3, font: Enum.Font)
			local l = Instance.new("TextLabel")
			l.BackgroundTransparency = 1
			l.Position = UDim2.new(0, 8, 1, y)
			l.Size = UDim2.new(1, -16, 0, size + 4)
			l.Font = font
			l.TextSize = size
			l.TextColor3 = color
			l.TextXAlignment = Enum.TextXAlignment.Left
			l.TextTruncate = Enum.TextTruncate.AtEnd
			l.Text = t
			l.Parent = card
		end
		text(it.name, -86, 15, Color3.new(1, 1, 1), BOLD)
		text(it.sub, -66, 12, it.color, FONT)
		-- the ways to buy it, side by side
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Position = UDim2.new(0, 8, 1, -42)
		row.Size = UDim2.new(1, -16, 0, 34)
		row.Parent = card
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.Padding = UDim.new(0, 6)
		lay.Parent = row
		local n = math.max(#it.buys, 1)
		for _, b in ipairs(it.buys) do
			local btn = Instance.new("TextButton")
			btn.Name = "Buy"
			btn.Size = UDim2.new(1 / n, -6 * (n - 1) / n, 1, 0)
			btn.BackgroundColor3 = if b.enabled then GREEN elseif b.poor then Color3.fromRGB(36, 38, 41) else GREY
			btn.AutoButtonColor = b.enabled
			btn.BorderSizePixel = 0
			btn.Font = BOLD
			btn.TextSize = 13
			btn.TextColor3 = if b.poor then RED else Color3.new(1, 1, 1)
			btn.Text = b.text
			btn.Parent = row
			corner(btn, 6)
			if b.poor then
				local ps = Instance.new("UIStroke")
				ps.Color = RED
				ps.Transparency = 0.5
				ps.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				ps.Parent = btn
			end
			if b.enabled then Icons.Press(btn) end
			local fn = b.onClick
			if b.enabled and fn then
				btn.Activated:Connect(function()
					say("")
					fn()
				end)
			end
		end
	end
end

local function build(): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = "StoreScreen"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 40
	g.Enabled = false
	g:SetAttribute("KeepFont", true) -- (plain Roblox fonts)
	g.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Parent = g

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W, H)
	panel.BackgroundColor3 = BG
	panel.BackgroundTransparency = 0.04
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Parent = g
	corner(panel, 10)
	ClickOutside.Bind(dim, panel, StoreScreen.Close)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vs = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vs.X - 24) / W, (vs.Y - 24) / H)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(20, 14)
	title.Size = UDim2.new(1, -80, 0, 30)
	title.Font = BOLD
	title.TextSize = 22
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Parent = panel
	titleLabel = title

	local function button(name: string, text: string, pos: UDim2, size: UDim2, onClick: () -> ()): TextButton
		local b = Instance.new("TextButton")
		b.Name = name
		b.Position = pos
		b.Size = size
		b.BackgroundColor3 = Color3.fromRGB(57, 59, 61)
		b.BorderSizePixel = 0
		b.Font = BOLD
		b.TextSize = 18
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = text
		b.Parent = panel
		corner(b, 8)
		Icons.Press(b)
		b.Activated:Connect(onClick)
		return b
	end
	-- (Roblox's close button: square, red, a white X, top right)
	button("Close", "X", UDim2.new(1, -48, 0, 12), UDim2.fromOffset(36, 36), function() StoreScreen.Close() end).BackgroundColor3 = Icons.CLOSE_RED

	local gf = Instance.new("Frame")
	gf.Name = "Grid"
	gf.BackgroundTransparency = 1
	gf.Position = UDim2.fromOffset(20, 60)
	gf.Size = UDim2.new(1, -40, 1, -120)
	gf.Parent = panel
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.25, -12, 0.5, -8)
	gl.CellPadding = UDim2.fromOffset(16, 16)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = gf
	grid = gf

	button("Prev", "<", UDim2.new(0.5, -110, 1, -48), UDim2.fromOffset(40, 36), function()
		page -= 1
		render()
	end)
	button("Next", ">", UDim2.new(0.5, 70, 1, -48), UDim2.fromOffset(40, 36), function()
		page += 1
		render()
	end)
	local pl = Instance.new("TextLabel")
	pl.BackgroundTransparency = 1
	pl.AnchorPoint = Vector2.new(0.5, 0)
	pl.Position = UDim2.new(0.5, 0, 1, -48)
	pl.Size = UDim2.fromOffset(120, 36)
	pl.Font = FONT
	pl.TextSize = 15
	pl.TextColor3 = Color3.fromRGB(220, 220, 220)
	pl.Parent = panel
	pageLabel = pl
	local stl = Instance.new("TextLabel")
	stl.BackgroundTransparency = 1
	stl.Position = UDim2.new(0, 20, 1, -48)
	stl.Size = UDim2.new(0.5, -140, 0, 36)
	stl.Font = FONT
	stl.TextSize = 13
	stl.TextColor3 = Color3.fromRGB(255, 190, 120)
	stl.TextXAlignment = Enum.TextXAlignment.Left
	stl.TextWrapped = true
	stl.Parent = panel
	status = stl

	-- what you own and hold, from the summon system (GachaManager)
	Network.GetRemoteEvent(Network.Remotes.GachaState).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		state = payload
		state.currencies = state.currencies or {}
		state.collection = state.collection or {}
		render()
	end)
	Network.GetRemoteEvent(Network.Remotes.SummonResult).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.error) == "string" and g.Enabled then say(payload.error) end
	end)
	Network.GetRemoteEvent(Network.Remotes.StoreResult).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.message) == "string" and g.Enabled and payload.kind == "buyMount" then
			say(payload.message)
		end
	end)
	return g
end

function StoreScreen.Open(which: string)
	if not gui then gui = build() end
	mode = if which == "mounts" then "mounts" else "summon"
	page = 1
	if titleLabel then titleLabel.Text = if mode == "mounts" then "MOUNTS SHOP" else "SUMMON SHOP" end
	say("")
	;(gui :: ScreenGui).Enabled = true
	render()
	Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer()
end

function StoreScreen.Close()
	if gui then gui.Enabled = false end
	clearCards()
end

function StoreScreen.IsOpen(): boolean
	return gui ~= nil and gui.Enabled
end

return StoreScreen
