--!strict
--[[
	Armory.luau
	Your gear (GearData) and what you wear, from the lobby's party panel:
	tabs for weapon finishes, auras and titles; everything in the game shown,
	what you own in full colour (with how many), what you don't as a locked
	silhouette of its rarity. Click to wear it; click again to take it off.

	Also the loot toasts: when something drops in a run (LootDrop), a card
	slides in on the right in its rarity's colour.

	Armory.Init()   Armory.Open()   Armory.Close()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GearData = require(Shared:WaitForChild("GearData"))

local player = Players.LocalPlayer

local Armory = {}

local GOLD = Color3.fromRGB(240, 196, 110)
local PARCH = Color3.fromRGB(238, 226, 204)
local MUTED = Color3.fromRGB(140, 130, 118)
local DARK = Color3.fromRGB(16, 12, 14)
local CARD = Color3.fromRGB(30, 24, 26)
local BODY = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

local SLOTS = { { id = "weapon", name = "WEAPON FINISHES" }, { id = "aura", name = "AURAS" }, { id = "title", name = "TITLES" } }

local owned: { [string]: number } = {}
local equipped: { [string]: string } = {}
local tab = "weapon"

local gui: ScreenGui? = nil
local grid: ScrollingFrame? = nil
local countLabel: TextLabel? = nil
local detail: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = BODY
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function corner(o: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function render()
	local gr = grid
	if not gr then return end
	for _, c in ipairs(gr:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local have, total = 0, 0
	local order = 0
	for ri = #GearData.RARITIES, 1, -1 do
		for _, item in ipairs(GearData.OfRarity(GearData.RARITIES[ri])) do
			if item.slot ~= tab then continue end
			total += 1
			order += 1
			local count = owned[item.id] or 0
			local mine = count > 0
			if mine then have += 1 end
			local col = GearData.RARITY_COLOR[item.rarity] or PARCH
			local worn = equipped[tab] == item.id
			local b = Instance.new("TextButton")
			b.Text = ""
			b.AutoButtonColor = false
			b.LayoutOrder = order
			b.BackgroundColor3 = if mine then col:Lerp(CARD, 0.78) else CARD
			b.Parent = gr
			corner(b, 8)
			local st = Instance.new("UIStroke")
			st.Color = if worn then Color3.new(1, 1, 1) elseif mine then col else Color3.fromRGB(60, 52, 52)
			st.Thickness = if worn then 2.5 else 1.4
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.Parent = b
			-- the swatch: a finish's colour and glow, an aura's colour, a title's glyph
			local sw = Instance.new("Frame")
			sw.Position = UDim2.fromOffset(10, 10)
			sw.Size = UDim2.fromOffset(36, 36)
			sw.BackgroundColor3 = if not mine then Color3.fromRGB(45, 40, 40) else (item.color or item.auraColor or col)
			sw.Parent = b
			corner(sw, 18)
			if mine and item.glow then
				local gs = Instance.new("UIStroke")
				gs.Color = item.glow
				gs.Thickness = 3
				gs.Parent = sw
			end
			label(sw, if mine then item.glyph else "?", 18, if mine then Color3.new(1, 1, 1) else MUTED,
				{ Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.5 })
			label(b, if mine then item.name else "Undiscovered", 14, if mine then Color3.new(1, 1, 1) else MUTED,
				{ FontFace = BOLD, Position = UDim2.fromOffset(54, 9), Size = UDim2.new(1, -60, 0, 18), TextTruncate = Enum.TextTruncate.AtEnd })
			label(b, string.upper(item.rarity) .. (if count > 1 then `  ·  ×{count}` else ""), 10, col,
				{ FontFace = BOLD, Position = UDim2.fromOffset(54, 28), Size = UDim2.new(1, -60, 0, 14), TextTransparency = if mine then 0 else 0.4 })
			if worn then
				label(b, "WORN", 10, Color3.new(1, 1, 1), { FontFace = BOLD, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 6), Size = UDim2.fromOffset(50, 12),
					TextXAlignment = Enum.TextXAlignment.Right })
			end
			b.MouseEnter:Connect(function()
				if detail then
					detail.Text = if mine then `{item.name}: {item.description}` else `A {string.lower(item.rarity)} {if tab == "weapon" then "weapon finish" else tab}. Find it in the dungeon.`
				end
			end)
			b.MouseButton1Click:Connect(function()
				if not mine then return end
				local to = if worn then nil else item.id
				Network.GetRemoteEvent(Network.Remotes.ArmoryAction):FireServer({ kind = "equip", slot = tab, id = to })
				equipped[tab] = to
				render()
			end)
		end
	end
	if countLabel then countLabel.Text = `{have} / {total} collected` end
	for id, tb in pairs(tabButtons) do
		tb.BackgroundColor3 = if id == tab then Color3.fromRGB(80, 60, 32) else Color3.fromRGB(36, 28, 26)
		tb.TextColor3 = if id == tab then GOLD else PARCH
	end
end

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "Armory"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 60
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = g
	dim.MouseButton1Click:Connect(Armory.Close)
	local W, H = 860, 580
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W, H)
	panel.BackgroundColor3 = DARK
	panel.Parent = g
	corner(panel, 12)
	local ps = Instance.new("UIStroke")
	ps.Color = GOLD
	ps.Transparency = 0.35
	ps.Parent = panel
	local sc = Instance.new("UIScale")
	sc.Parent = panel
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	sc.Scale = math.min(1, (vp.X - 40) / W, (vp.Y - 40) / H)
	label(panel, "THE ARMORY", 34, GOLD, { Font = Enum.Font.Antique, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	label(panel, "Gear found in the dungeon. Everyone sees what you wear.", 14, PARCH,
		{ Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.15 })
	for i, s in ipairs(SLOTS) do
		local tb = Instance.new("TextButton")
		tb.Position = UDim2.new(0.5, (i - 2) * 200 - 90, 0, 82)
		tb.Size = UDim2.fromOffset(180, 32)
		tb.FontFace = BOLD
		tb.TextSize = 14
		tb.Text = s.name
		tb.AutoButtonColor = false
		tb.Parent = panel
		corner(tb, 6)
		tb.MouseButton1Click:Connect(function()
			tab = s.id
			render()
		end)
		tabButtons[s.id] = tb
	end
	countLabel = label(panel, "", 13, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(0, 120), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
	local sf = Instance.new("ScrollingFrame")
	sf.Position = UDim2.fromOffset(24, 144)
	sf.Size = UDim2.new(1, -48, 1, -236)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 5
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new()
	sf.Parent = panel
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(1 / 3, -8, 0, 56)
	gl.CellPadding = UDim2.fromOffset(10, 10)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = sf
	grid = sf
	detail = label(panel, "Hover over a piece to read it. Click to wear it.", 13, PARCH,
		{ Position = UDim2.new(0, 30, 1, -88), Size = UDim2.new(1, -60, 0, 30), TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.1 })
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -14)
	close.Size = UDim2.fromOffset(180, 38)
	close.BackgroundColor3 = Color3.fromRGB(60, 40, 30)
	close.FontFace = BOLD
	close.TextSize = 16
	close.TextColor3 = GOLD
	close.Text = "CLOSE"
	close.Parent = panel
	corner(close, 6)
	close.MouseButton1Click:Connect(Armory.Close)
end

function Armory.Open()
	if not gui then build() end
	render()
	Network.GetRemoteEvent(Network.Remotes.RequestArmory):FireServer()
	local g = gui :: ScreenGui
	g.Enabled = true
end

function Armory.Close()
	if gui then gui.Enabled = false end
end

-- ── Loot toasts ───────────────────────────────────────────────────────────
local toastGui: ScreenGui? = nil
local toasts: { Frame } = {}

local function relayout()
	for i, f in ipairs(toasts) do
		TweenService:Create(f, TweenInfo.new(0.2), { Position = UDim2.new(1, -20, 0.3, (i - 1) * 74) }):Play()
	end
end

local function toast(d: any)
	if not toastGui then
		local g = Instance.new("ScreenGui")
		g.Name = "LootToasts"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 45
		g.Parent = player:WaitForChild("PlayerGui")
		toastGui = g
	end
	local col = GearData.RARITY_COLOR[tostring(d.rarity)] or PARCH
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(1, 0)
	f.Position = UDim2.new(1, 300, 0.3, #toasts * 74)
	f.Size = UDim2.fromOffset(290, 64)
	f.BackgroundColor3 = col:Lerp(DARK, 0.75)
	f.BackgroundTransparency = 0.05
	f.Parent = toastGui
	corner(f, 8)
	local st = Instance.new("UIStroke")
	st.Color = col
	st.Thickness = 2
	st.Parent = f
	label(f, tostring(d.glyph or "◆"), 26, col, { Position = UDim2.fromOffset(8, 0), Size = UDim2.fromOffset(40, 64), TextXAlignment = Enum.TextXAlignment.Center })
	local slot = if d.slot == "weapon" then "weapon finish" elseif d.slot == "aura" then "aura" else "title"
	label(f, string.upper(tostring(d.rarity)) .. "  ·  " .. string.upper(slot) .. (if d.isNew then "  ·  NEW!" else ""), 11, col,
		{ FontFace = BOLD, Position = UDim2.fromOffset(52, 10), Size = UDim2.fromOffset(230, 14) })
	label(f, tostring(d.name), 18, Color3.new(1, 1, 1), { FontFace = BOLD, Position = UDim2.fromOffset(52, 26), Size = UDim2.fromOffset(230, 22),
		TextTruncate = Enum.TextTruncate.AtEnd })
	label(f, "Carried: extract to keep it", 10, PARCH, { Position = UDim2.fromOffset(52, 46), Size = UDim2.fromOffset(230, 12), TextTransparency = 0.35 })
	table.insert(toasts, f)
	relayout()
	task.delay(5, function()
		local i = table.find(toasts, f)
		if i then table.remove(toasts, i) end
		TweenService:Create(f, TweenInfo.new(0.3), { Position = UDim2.new(1, 300, f.Position.Y.Scale, f.Position.Y.Offset) }):Play()
		task.delay(0.35, function() f:Destroy() end)
		relayout()
	end)
end

function Armory.Init()
	Network.GetRemoteEvent(Network.Remotes.ArmoryState).OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "table" then return end
		owned = if typeof(state.owned) == "table" then state.owned else {}
		equipped = if typeof(state.equipped) == "table" then state.equipped else {}
		if gui and gui.Enabled then render() end
	end)
	Network.GetRemoteEvent(Network.Remotes.LootDrop).OnClientEvent:Connect(function(d: any)
		if typeof(d) == "table" then pcall(toast, d) end
	end)
end

return Armory
