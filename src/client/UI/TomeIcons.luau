--!strict
-- TomeIcons.luau
-- A logo for every tome (a coloured diamond with its symbol and a count
-- badge), the always-on row of your tomes above the health bar, and the
-- tooltips shown while Tab is held (the cursor comes back so you can hover
-- an icon to read what it does).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local TomeData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TomeData"))

local TomeController: any = nil
pcall(function()
	TomeController = require(script.Parent.Parent:WaitForChild("TomeController"))
end)

local player = Players.LocalPlayer

local TomeIcons = {}

local GOLD = Color3.fromRGB(255, 222, 140)
local PLAQUE = Color3.fromRGB(28, 20, 18)
local PARCHMENT = Color3.fromRGB(239, 213, 170)
local SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local SERIF = Font.new("rbxasset://fonts/families/Merriweather.json")

-- The symbol drawn on each tome's logo.
local GLYPHS: { [string]: string } = {
	agility = "AGI", attack_speed = "ATK", cooldown = "CD", damage = "DMG", evasion = "EVA",
	gold = "GLD", health = "HP", knockback = "KB", precision = "CRT", projectile_speed = "PRJ",
	regen = "REG", shield = "SHD", silver = "SLV", ricochet = "RIC", size = "SIZ",
	armor = "ARM", attraction = "MAG", bloody = "BLD", chaos = "CHS", cursed = "CRS",
	duration = "DUR", luck = "LCK", quantity = "QTY", thorns = "THN",
	gs_loaded_coin = "LC", gs_lucky_coin = "LK", gs_silver_dollar = "SD", gs_double_or_nothing = "DN",
	gs_explosive_ricochet = "ER", gs_marked_currency = "MC", gs_heads = "HD", gs_tails = "TL",
	gs_quick_hands = "QH", gs_extended_cylinder = "EC", gs_roll_reload = "RR", gs_piercing_rounds = "PR",
	gs_last_word = "LW", gs_steady_aim = "SA", gs_coin_collector = "CC",
}

function TomeIcons.Glyph(id: string): string
	if GLYPHS[id] then return GLYPHS[id] end
	-- (anything else: the first letters of its name)
	local tome = TomeData.GetTome and TomeData.GetTome(id)
	local name = if tome then string.gsub(tome.name, " Tome$", "") else id
	return string.upper(string.sub(name, 1, 3))
end

function TomeIcons.Accent(id: string): Color3
	if TomeController and TomeController.AccentFor then return TomeController.AccentFor(id) end
	return GOLD
end

-- ── Tooltip (shared) ────────────────────────────────────────────────────────
local tipGui: ScreenGui? = nil
local tip: Frame? = nil
local tipName: TextLabel? = nil
local tipDesc: TextLabel? = nil
local inspecting = false

local function ensureTip()
	if tipGui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "TomeTooltip"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 300
	g.Parent = player:WaitForChild("PlayerGui")
	tipGui = g
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(230, 64)
	f.BackgroundColor3 = PLAQUE
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = g
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 1.5
	st.Parent = f
	tip = f
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Position = UDim2.fromOffset(10, 6)
	n.Size = UDim2.new(1, -20, 0, 20)
	n.FontFace = SERIF_BOLD
	n.TextSize = 15
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.TextColor3 = GOLD
	n.Parent = f
	tipName = n
	local d = n:Clone()
	d.Position = UDim2.fromOffset(10, 28)
	d.Size = UDim2.new(1, -20, 0, 30)
	d.FontFace = SERIF
	d.TextSize = 12
	d.TextWrapped = true
	d.TextYAlignment = Enum.TextYAlignment.Top
	d.TextColor3 = PARCHMENT
	d.Parent = f
	tipDesc = d
end

local function showTip(id: string, count: number)
	if not inspecting then return end
	ensureTip()
	local tome = TomeData.GetTome(id)
	local accent = TomeIcons.Accent(id)
	;(tipName :: TextLabel).Text = `{TomeIcons.Glyph(id)}  {if tome then tome.name else id}  ×{count}`
	;(tipName :: TextLabel).TextColor3 = accent
	;(tipDesc :: TextLabel).Text = if tome then tome.description else ""
	local m = UserInputService:GetMouseLocation()
	local f = tip :: Frame
	f.Position = UDim2.fromOffset(m.X + 16, m.Y - 70)
	f.Visible = true
end

local function hideTip()
	if tip then tip.Visible = false end
end

-- Tab held: bring the cursor back and allow hovering the icons.
local savedMouseIcon: boolean? = nil
function TomeIcons.SetInspecting(on: boolean)
	if on == inspecting then return end
	inspecting = on
	if on then
		savedMouseIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
	else
		hideTip()
		if savedMouseIcon ~= nil then UserInputService.MouseIconEnabled = savedMouseIcon end
		savedMouseIcon = nil
	end
end

-- ── One logo ────────────────────────────────────────────────────────────────
function TomeIcons.Make(parent: Instance, id: string, count: number, size: number): Frame
	local accent = TomeIcons.Accent(id)
	local holder = Instance.new("Frame")
	holder.Name = `TomeIcon_{id}`
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundTransparency = 1
	holder.Parent = parent

	local diamond = Instance.new("Frame")
	diamond.AnchorPoint = Vector2.new(0.5, 0.5)
	diamond.Position = UDim2.fromScale(0.5, 0.5)
	diamond.Size = UDim2.fromScale(0.7, 0.7)
	diamond.Rotation = 45
	diamond.BackgroundColor3 = PLAQUE
	diamond.BorderSizePixel = 0
	diamond.Parent = holder
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(accent:Lerp(PLAQUE, 0.55), PLAQUE)
	grad.Rotation = 45
	grad.Parent = diamond
	local st = Instance.new("UIStroke")
	st.Color = accent
	st.Thickness = 1.5
	st.Parent = diamond

	local glyph = Instance.new("TextLabel")
	glyph.BackgroundTransparency = 1
	glyph.Size = UDim2.fromScale(1, 1)
	glyph.Text = TomeIcons.Glyph(id)
	glyph.TextScaled = true
	glyph.Font = Enum.Font.GothamBold
	glyph.TextColor3 = accent
	glyph.ZIndex = 2
	glyph.Parent = holder
	local pad = Instance.new("UIPadding")
	local p = math.floor(size * 0.24)
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, p), UDim.new(0, p)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, p), UDim.new(0, p)
	pad.Parent = glyph

	if count > 1 then
		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.fromScale(1, 1)
		badge.Size = UDim2.fromOffset(math.max(16, size * 0.42), math.max(14, size * 0.34))
		badge.BackgroundColor3 = accent
		badge.BorderSizePixel = 0
		badge.FontFace = SERIF_BOLD
		badge.TextScaled = true
		badge.TextColor3 = PLAQUE
		badge.Text = tostring(count)
		badge.ZIndex = 3
		badge.Parent = holder
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = badge
	end

	holder.MouseEnter:Connect(function() showTip(id, count) end)
	holder.MouseMoved:Connect(function() showTip(id, count) end)
	holder.MouseLeave:Connect(hideTip)
	return holder
end

-- Your tomes this run (from the Tome_<id> attributes), most-taken first.
function TomeIcons.Owned(): { { id: string, count: number } }
	local owned = {}
	for name, count in pairs(player:GetAttributes()) do
		if string.sub(name, 1, 5) == "Tome_" and typeof(count) == "number" and count > 0 then
			table.insert(owned, { id = string.sub(name, 6), count = count })
		end
	end
	table.sort(owned, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.id < b.id
	end)
	return owned
end

-- A self-updating row of logos (the HUD strip above the health bar).
function TomeIcons.Row(parent: Instance, size: number): Frame
	local row = Instance.new("Frame")
	row.Name = "TomeRow"
	row.BackgroundTransparency = 1
	row.AutomaticSize = Enum.AutomaticSize.XY
	row.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.Padding = UDim.new(0, 2)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = row
	local function refresh()
		for _, c in ipairs(row:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		for i, t in ipairs(TomeIcons.Owned()) do
			TomeIcons.Make(row, t.id, t.count, size).LayoutOrder = i
		end
	end
	refresh()
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Tome_" then refresh() end
	end)
	return row
end

return TomeIcons
