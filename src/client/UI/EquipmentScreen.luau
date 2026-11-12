--!strict
--[[
	EquipmentScreen.luau
	The Forgotten Isle's gear screen (G, from IslandHUD): what you wear and
	what's in your bag, every piece as its toy-brick model (GearModels) in
	its grade's colour, frame and label.

	  left    your character, live in a ViewportFrame (drag to turn it),
	          with the seven slots either side and what they add up to
	          underneath
	  right   the bag (10), then the piece you picked: its model turning, its
	          stats against what it would replace, its perk, and EQUIP /
	          SALVAGE (from the bag) or UNEQUIP (a slot)

	Every choice is the same IslandAction the server checks
	(EquipmentManager): equip { uid }, unequip { slot }, salvage { uid }.
	The screen redraws when the server's "gear" state comes back.

	Cheap: the viewports exist only while it's open (closing empties them);
	icons are clones of one template per item (GearModels), and a cell's
	model is only rebuilt when the piece in it changes.

	  EquipmentScreen.Init(ask)        ask(action, data?) → IslandAction
	  EquipmentScreen.SetState(bag, equipped)
	  EquipmentScreen.Open() / Close() / Toggle() / IsOpen()
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local EquipmentData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EquipmentData"))
local GearModels = require(script.Parent.Parent:WaitForChild("GearModels"))
local GearView = require(script.Parent:WaitForChild("GearView"))

local player = Players.LocalPlayer

local EquipmentScreen = {}

local C = GearView.C
local SERIF_BOLD = GearView.SERIF_BOLD
local new, label, button = GearView.new, GearView.label, GearView.button

local STAT_NAMES: { [string]: string } = {
	damage = "Damage", maxHealth = "Max Health", armor = "Armor", evasion = "Evasion", critChance = "Crit Chance",
	critDamage = "Crit Damage", abilityDamage = "Ability Damage", abilityCooldown = "Cooldowns", movementSpeed = "Speed",
	basicAttackSpeed = "Attack Speed", luck = "Luck", killHeal = "Heal on Kill", lifesteal = "Lifesteal", goldGain = "Gold",
	healthRegenPerMinute = "Regen / min", knockback = "Knockback", xpGain = "XP", shield = "Shield",
}

-- The slots round the character: left column, right column.
local LEFT = { "helmet", "armor", "gloves", "boots" }
local RIGHT = { "weapon", "accessory", "accessory2" }

type Owned = { uid: number, id: string }
type Cell = GearView.Cell

-- ── State ───────────────────────────────────────────────────────────────────
local ask: (string, { [string]: any }?) -> () = function() end
local bag: { Owned } = {}
local equipped: { [string]: Owned } = {}
local selected: { kind: string, uid: number?, slot: string? }? = nil
local hoverSlot: string? = nil

local gui: ScreenGui
local root: Frame
local slotCells: { [string]: Cell } = {}
local bagCells: { Cell } = {}
local bagTitle: TextLabel
local totalsL: TextLabel
local detail: Frame
local detailCell: Cell
local detailName: TextLabel
local detailGrade: TextLabel
local detailBody: TextLabel
local btnA: TextButton
local btnB: TextButton
local hintL: TextLabel
local preview: GearView.Preview
local open = false

local function pct(v: number): string
	local p = v * 100
	return if math.abs(p - math.floor(p + 0.5)) < 0.05 then tostring(math.floor(p + 0.5)) else string.format("%.1f", p)
end

-- One tome effect in words ("+8% Damage", "+40 Max Health").
local function effectText(stat: string, op: string, value: number): string
	local name = STAT_NAMES[stat] or stat
	local sign = if value >= 0 then "+" else "-"
	local v = math.abs(value)
	if op == "add" and v >= 1 then return `{sign}{math.floor(v + 0.5)} {name}` end
	if stat == "abilityCooldown" then return `{if value >= 0 then "-" else "+"}{pct(v)}% {name}` end
	return `{sign}{pct(v)}% {name}`
end

local function totals(items: { EquipmentData.Item }): ({ [string]: { op: string, value: number } }, { string })
	local out, order = {}, {}
	for _, item in ipairs(items) do
		for _, e in ipairs(item.stats) do
			local t = out[e.stat]
			if not t then
				t = { op = e.operation, value = 0 }
				out[e.stat] = t
				table.insert(order, e.stat)
			end
			t.value += e.value
		end
	end
	return out, order
end

-- ── Grades ──────────────────────────────────────────────────────────────────
local function rarityOf(item: EquipmentData.Item?): { order: number, color: Color3, salvage: number }?
	return if item then EquipmentData.Rarities[item.rarity] else nil
end

local function gradeColor(item: EquipmentData.Item?): Color3
	local r = rarityOf(item)
	return if r then r.color else C.faint
end

-- A cell in its grade (Rare, Epic, Legendary: 1–3 diamonds).
local function styleCell(cell: Cell, item: EquipmentData.Item?)
	local r = rarityOf(item)
	GearView.Style(cell, if r then r.color else nil, if r then r.order else 0, 3, item and item.rarity)
end

local function isWeapon(id: string): boolean
	local item = EquipmentData.Get(id)
	return item ~= nil and item.slot == "weapon"
end

local function setIcon(cell: Cell, id: string?)
	GearView.SetIcon(cell, id, function() return if id then GearModels.Icon(id) else nil end, id ~= nil and isWeapon(id))
end

-- ── Selection and the detail panel ──────────────────────────────────────────
local function findOwned(sel: { kind: string, uid: number?, slot: string? }): Owned?
	if sel.kind == "bag" then
		for _, o in ipairs(bag) do
			if o.uid == sel.uid then return o end
		end
		return nil
	end
	return if sel.slot then equipped[sel.slot] else nil
end

-- The slot a bag piece would go into (an accessory: the first empty of the two).
local function targetSlot(item: EquipmentData.Item): string
	local fits = EquipmentData.SlotFits[item.slot]
	if not fits then return item.slot end
	for _, s in ipairs(fits) do
		if not equipped[s] then return s end
	end
	return fits[1]
end

local function describe(item: EquipmentData.Item, against: EquipmentData.Item?): string
	local lines = {}
	table.insert(lines, `<font color="#b9aea0">{EquipmentData.SlotNames[item.slot] or item.slot}  ·  <i>{item.role}</i></font>`)
	local mine, order = totals({ item })
	local theirs = if against then (totals({ against })) else {}
	local stats = {}
	for _, stat in ipairs(order) do
		local t = mine[stat]
		local diff = ""
		if against then
			local d = t.value - (if theirs[stat] then theirs[stat].value else 0)
			if math.abs(d) > 1e-6 then
				diff = if d > 0 then ` <font color="#78e68c">({effectText(stat, t.op, d)})</font>` else ` <font color="#ff7a6a">({effectText(stat, t.op, d)})</font>`
			end
		end
		table.insert(stats, effectText(stat, t.op, t.value) .. diff)
	end
	if against then
		for stat, t in pairs(theirs) do
			if not mine[stat] then table.insert(stats, `<font color="#ff7a6a">({effectText(stat, t.op, -t.value)})</font>`) end
		end
	end
	table.insert(lines, table.concat(stats, "   "))
	table.insert(lines, `<font color="#ffde8c">PERK: {item.perk.text}</font>`)
	if against then
		table.insert(lines, `<font color="#9d93a8">Replaces {against.name}</font>`)
	end
	return table.concat(lines, "\n")
end

local refresh: () -> ()

local function showDetail()
	local sel = selected
	local o = sel and findOwned(sel)
	local item = o and EquipmentData.Get(o.id)
	if not sel or not o or not item then
		selected = nil
		setIcon(detailCell, nil)
		styleCell(detailCell, nil)
		detailName.Text = "Pick a piece"
		detailName.TextColor3 = C.dim
		detailGrade.Text = ""
		detailBody.Text = "Click a piece in your bag to compare it with what you wear, or a slot to see what's on.\nDouble-click a bag piece to wear it."
		btnA.Visible, btnB.Visible = false, false
		hintL.Text = ""
		return
	end
	setIcon(detailCell, item.id)
	styleCell(detailCell, item)
	local col = gradeColor(item)
	detailName.Text = item.name
	detailName.TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.15)
	detailGrade.Text = string.upper(item.rarity)
	detailGrade.TextColor3 = col
	local rar = rarityOf(item)
	local salvage = if rar then rar.salvage else 0
	if sel.kind == "bag" then
		local slot = targetSlot(item)
		local against = equipped[slot] and EquipmentData.Get(equipped[slot].id)
		detailBody.Text = describe(item, against)
		btnA.Text = "EQUIP"
		btnA.TextColor3 = C.green
		btnA.Visible = true
		btnB.Text = `SALVAGE  {salvage}g`
		btnB.Visible = true
		hintL.Text = ""
	else
		detailBody.Text = describe(item, nil)
		local full = #bag >= EquipmentData.BAG
		btnA.Text = "UNEQUIP"
		btnA.TextColor3 = if full then C.faint else C.gold
		btnA.Visible = true
		btnB.Visible = false
		hintL.Text = if full then "Your bag is full" else ""
	end
end

local function pick(sel: { kind: string, uid: number?, slot: string? }?)
	selected = sel
	refresh()
end

-- ── Redrawing ───────────────────────────────────────────────────────────────
refresh = function()
	if not open then return end
	-- the slots
	for _, slot in ipairs(EquipmentData.Slots) do
		local cell = slotCells[slot]
		local o = equipped[slot]
		local item = o and EquipmentData.Get(o.id)
		setIcon(cell, item and item.id)
		styleCell(cell, item)
		if cell.slotL then
			cell.slotL.Text = string.upper(EquipmentData.SlotNames[slot] or slot)
			cell.slotL.TextColor3 = if item then C.white else C.faint
		end
		local isSel = selected ~= nil and selected.kind == "slot" and selected.slot == slot
		if isSel or hoverSlot == slot then
			cell.stroke.Color = C.goldBright
			cell.stroke.Thickness = 3
			cell.stroke.Transparency = 0
		end
	end
	-- the bag
	bagTitle.Text = `BAG   {#bag} / {EquipmentData.BAG}`
	for i, cell in ipairs(bagCells) do
		local o = bag[i]
		local item = o and EquipmentData.Get(o.id)
		setIcon(cell, item and item.id)
		styleCell(cell, item)
		cell.button.AutoButtonColor = item ~= nil
		if cell.nameL then
			cell.nameL.Text = if item then item.name else "empty"
			cell.nameL.TextColor3 = if item then gradeColor(item):Lerp(Color3.new(1, 1, 1), 0.3) else C.faint
		end
		if cell.slotL then cell.slotL.Text = if item then string.upper(EquipmentData.SlotNames[item.slot] or item.slot) else "" end
		if selected and selected.kind == "bag" and o and selected.uid == o.uid then
			cell.stroke.Color = C.white
			cell.stroke.Thickness = 3
		end
	end
	-- what it all adds up to
	local items = {}
	for _, slot in ipairs(EquipmentData.Slots) do
		local it = equipped[slot] and EquipmentData.Get(equipped[slot].id)
		if it then table.insert(items, it) end
	end
	local sum, order = totals(items)
	local parts = {}
	for _, stat in ipairs(order) do table.insert(parts, effectText(stat, sum[stat].op, sum[stat].value)) end
	totalsL.Text = if #parts > 0 then table.concat(parts, "   ") else `<font color="#5a5260">Nothing worn yet: open chests, slay elites.</font>`
	showDetail()
end

-- ── Building it ─────────────────────────────────────────────────────────────
local W, H = 1100, 640
local SLOT = 100

local function slotCell(parent: Instance, slot: string, x: number, y: number)
	local cell = GearView.Cell(parent, { Name = "Slot_" .. slot, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(SLOT, SLOT) },
		{ Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 1, -26) })
	cell.slotL = label(cell.button, { Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 18), TextSize = 11, FontFace = SERIF_BOLD,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	cell.gradeL = label(cell.button, { Position = UDim2.fromOffset(6, 4), Size = UDim2.new(1, -12, 0, 12), TextSize = 9, FontFace = SERIF_BOLD,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	cell.pips = GearView.Pips(cell.button, { Position = UDim2.fromOffset(4, 3) })
	cell.button.MouseButton1Click:Connect(function()
		if equipped[slot] then pick({ kind = "slot", slot = slot }) else pick(nil) end
	end)
	slotCells[slot] = cell
end

local lastClick, lastClickUid = 0, -1

local function bagCell(parent: Instance, i: number)
	local cell = GearView.Cell(parent, { Name = "Bag" .. i, LayoutOrder = i, Size = UDim2.fromOffset(240, 70) },
		{ Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(64, 64) })
	cell.nameL = label(cell.button, { Position = UDim2.fromOffset(74, 8), Size = UDim2.new(1, -80, 0, 22), TextSize = 14, FontFace = SERIF_BOLD,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	cell.gradeL = label(cell.button, { Position = UDim2.fromOffset(74, 32), Size = UDim2.new(1, -80, 0, 14), TextSize = 11, FontFace = SERIF_BOLD, ZIndex = 4 })
	cell.slotL = label(cell.button, { Position = UDim2.fromOffset(74, 48), Size = UDim2.new(1, -80, 0, 14), TextSize = 10, TextColor3 = C.dim, ZIndex = 4 })
	cell.pips = GearView.Pips(cell.button, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -2, 0, 33) })
	cell.button.MouseButton1Click:Connect(function()
		local o = bag[i]
		if not o then
			pick(nil)
			return
		end
		local now = os.clock()
		if lastClickUid == o.uid and now - lastClick < 0.4 then
			-- (a double click: wear it)
			ask("equip", { uid = o.uid })
			selected = nil
			lastClickUid = -1
			return
		end
		lastClick, lastClickUid = now, o.uid
		pick({ kind = "bag", uid = o.uid })
	end)
	cell.button.MouseEnter:Connect(function()
		local o = bag[i]
		local item = o and EquipmentData.Get(o.id)
		hoverSlot = item and targetSlot(item)
		refresh()
	end)
	cell.button.MouseLeave:Connect(function()
		if hoverSlot then
			hoverSlot = nil
			refresh()
		end
	end)
	table.insert(bagCells, cell)
end

local function build()
	gui = new("ScreenGui", { Name = "EquipmentScreen", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 36, Enabled = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling }, player:WaitForChild("PlayerGui"))
	-- the world dimmed behind it
	local shade = new("TextButton", { BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.45, Size = UDim2.fromScale(1, 1),
		Text = "", AutoButtonColor = false }, gui)
	shade.MouseButton1Click:Connect(function() EquipmentScreen.Close() end)
	root = new("Frame", { Name = "Panel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
		BackgroundColor3 = C.stone, BackgroundTransparency = 0.04, BorderSizePixel = 0, Active = true }, gui)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, root)
	new("UIStroke", { Color = C.gold, Thickness = 1.6, Transparency = 0.15 }, root)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 160, 175)) }, root)
	local scale = new("UIScale", {}, root)
	local function fit()
		local vs = Workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vs.X - 24) / W, (vs.Y - 24) / H)
	end
	fit()
	Workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	-- header
	label(root, { Text = "EQUIPMENT", Position = UDim2.fromOffset(24, 12), Size = UDim2.fromOffset(400, 34), FontFace = SERIF_BOLD, TextSize = 28,
		TextColor3 = C.goldBright, TextStrokeTransparency = 0.3 })
	label(root, { Text = "The Forgotten Isle  ·  worn for this run only, lost when it ends", Position = UDim2.fromOffset(24, 46),
		Size = UDim2.fromOffset(600, 16), TextSize = 12, TextColor3 = C.dim })
	local close = button(root, "X", C.dim, { Name = "Close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(32, 32) })
	close.MouseButton1Click:Connect(function() EquipmentScreen.Close() end)
	label(root, { Text = "[G] close", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -56, 0, 22), Size = UDim2.fromOffset(100, 16),
		TextSize = 11, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Right })
	new("Frame", { BackgroundColor3 = C.gold, BackgroundTransparency = 0.6, BorderSizePixel = 0, Position = UDim2.fromOffset(24, 70),
		Size = UDim2.new(1, -48, 0, 1) }, root)

	-- the character and its slots
	local doll = new("Frame", { Name = "Doll", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 84), Size = UDim2.fromOffset(560, 540) }, root)
	for i, slot in ipairs(LEFT) do slotCell(doll, slot, 0, (i - 1) * (SLOT + 12)) end
	for i, slot in ipairs(RIGHT) do slotCell(doll, slot, 560 - SLOT, (i - 1) * (SLOT + 12)) end
	local stage = new("Frame", { Name = "Stage", BackgroundColor3 = Color3.fromRGB(22, 18, 28), BorderSizePixel = 0,
		Position = UDim2.fromOffset(SLOT + 12, 0), Size = UDim2.fromOffset(560 - 2 * SLOT - 24, 436), ClipsDescendants = true }, doll)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, stage)
	new("UIStroke", { Color = C.gold, Thickness = 1, Transparency = 0.55 }, stage)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(70, 58, 84), Color3.fromRGB(12, 10, 16)) }, stage)
	preview = GearView.Preview(stage)
	-- what it adds up to
	local sumBox = new("Frame", { BackgroundColor3 = C.stone2, BorderSizePixel = 0, Position = UDim2.fromOffset(SLOT + 12, 448),
		Size = UDim2.fromOffset(560 - SLOT - 12, 76) }, doll)
	new("UICorner", { CornerRadius = UDim.new(0, 5) }, sumBox)
	new("UIStroke", { Color = C.gold, Thickness = 1, Transparency = 0.6 }, sumBox)
	label(sumBox, { Text = "WORN BONUSES", Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(200, 14), TextSize = 11,
		FontFace = SERIF_BOLD, TextColor3 = C.gold })
	totalsL = label(sumBox, { Text = "", Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 1, -28), TextSize = 13, RichText = true,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.green })
	-- the grade key, under the left column
	local key = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 448), Size = UDim2.fromOffset(SLOT, 76) }, doll)
	new("UIListLayout", { Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, key)
	local names = {}
	for name, r in pairs(EquipmentData.Rarities) do table.insert(names, { name = name, r = r }) end
	table.sort(names, function(a, b) return a.r.order < b.r.order end)
	for _, e in ipairs(names) do
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(SLOT, 18), LayoutOrder = e.r.order }, key)
		local sw = new("Frame", { BackgroundColor3 = e.r.color, BorderSizePixel = 0, Size = UDim2.fromOffset(10, 10), Rotation = 45,
			Position = UDim2.fromOffset(3, 4) }, row)
		new("UIStroke", { Color = C.stone, Thickness = 1 }, sw)
		label(row, { Text = string.upper(e.name), Position = UDim2.fromOffset(20, 0), Size = UDim2.fromOffset(SLOT - 20, 18), TextSize = 11,
			FontFace = SERIF_BOLD, TextColor3 = e.r.color })
	end

	-- the bag
	local right = new("Frame", { Name = "Right", BackgroundTransparency = 1, Position = UDim2.fromOffset(600, 84), Size = UDim2.fromOffset(480, 540) }, root)
	bagTitle = label(right, { Text = "BAG", Position = UDim2.fromOffset(0, 0), Size = UDim2.fromOffset(240, 18), TextSize = 13, FontFace = SERIF_BOLD,
		TextColor3 = C.gold })
	label(right, { Text = "more than that is salvaged for gold", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 2),
		Size = UDim2.fromOffset(260, 14), TextSize = 10, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Right })
	local grid = new("Frame", { Name = "Bag", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 24), Size = UDim2.fromOffset(480, 382) }, right)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(236, 70), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i = 1, EquipmentData.BAG do bagCell(grid, i) end

	-- the piece picked
	detail = new("Frame", { Name = "Detail", BackgroundColor3 = C.stone2, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 414),
		Size = UDim2.fromOffset(480, 126) }, right)
	new("UICorner", { CornerRadius = UDim.new(0, 5) }, detail)
	new("UIStroke", { Color = C.gold, Thickness = 1, Transparency = 0.55 }, detail)
	detailCell = GearView.Cell(detail, { Name = "Icon", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(110, 110), Active = false },
		{ Position = UDim2.fromOffset(4, 4), Size = UDim2.new(1, -8, 1, -8) })
	detailCell.pips = GearView.Pips(detailCell.button, { Position = UDim2.fromOffset(4, 3) })
	detailName = label(detail, { Text = "", Position = UDim2.fromOffset(128, 6), Size = UDim2.fromOffset(220, 22), TextSize = 17, FontFace = SERIF_BOLD,
		TextTruncate = Enum.TextTruncate.AtEnd })
	detailGrade = label(detail, { Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(110, 16),
		TextSize = 12, FontFace = SERIF_BOLD, TextXAlignment = Enum.TextXAlignment.Right })
	detailBody = label(detail, { Text = "", Position = UDim2.fromOffset(128, 30), Size = UDim2.fromOffset(222, 92), TextSize = 11, RichText = true,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	btnA = button(detail, "EQUIP", C.green, { Name = "Primary", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 34), Size = UDim2.fromOffset(112, 36) })
	btnB = button(detail, "SALVAGE", C.red, { Name = "Secondary", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 78), Size = UDim2.fromOffset(112, 36), TextSize = 13 })
	hintL = label(detail, { Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 76), Size = UDim2.fromOffset(112, 16),
		TextSize = 10, TextColor3 = C.red, TextXAlignment = Enum.TextXAlignment.Center })
	btnA.MouseButton1Click:Connect(function()
		local sel = selected
		if not sel then return end
		if sel.kind == "bag" then
			ask("equip", { uid = sel.uid })
		else
			if #bag >= EquipmentData.BAG then return end
			ask("unequip", { slot = sel.slot })
		end
		selected = nil
		refresh()
	end)
	btnB.MouseButton1Click:Connect(function()
		local sel = selected
		if sel and sel.kind == "bag" then ask("salvage", { uid = sel.uid }) end
		selected = nil
		refresh()
	end)
end

-- ── While open: the turning character, the turning piece, the shimmer ─────
local function step(dt: number)
	if not open then return end
	preview:Step(dt)
	local m = detailCell.model
	if m and detailCell.key then
		GearView.FrameIcon(m, detailCell.cam, isWeapon(detailCell.key), (os.clock() * 0.9) % (math.pi * 2))
	end
	local cells = { detailCell }
	for _, cell in pairs(slotCells) do table.insert(cells, cell) end
	for _, cell in ipairs(bagCells) do table.insert(cells, cell) end
	GearView.Shimmer(cells)
end

-- ── API ─────────────────────────────────────────────────────────────────────
function EquipmentScreen.SetState(newBag: { Owned }?, newEquipped: { [string]: Owned }?)
	bag = newBag or {}
	equipped = newEquipped or {}
	if selected and not findOwned(selected) then selected = nil end
	refresh()
end

function EquipmentScreen.IsOpen(): boolean
	return open
end

function EquipmentScreen.Open()
	if open then return end
	open = true
	gui.Enabled = true
	selected = nil
	hoverSlot = nil
	preview:Show()
	ask("gear")
	refresh()
	root.Position = UDim2.new(0.5, 0, 0.5, 18)
	TweenService:Create(root, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.fromScale(0.5, 0.5) }):Play()
end

function EquipmentScreen.Close()
	if not open then return end
	open = false
	gui.Enabled = false
	selected = nil
	hoverSlot = nil
	-- (the viewports emptied: nothing renders while it's shut)
	preview:Hide()
	for _, cell in pairs(slotCells) do setIcon(cell, nil) end
	for _, cell in ipairs(bagCells) do setIcon(cell, nil) end
	setIcon(detailCell, nil)
end

function EquipmentScreen.Toggle()
	if open then EquipmentScreen.Close() else EquipmentScreen.Open() end
end

function EquipmentScreen.Init(askFn: (string, { [string]: any }?) -> ())
	ask = askFn
	build()
	RunService.Heartbeat:Connect(step)
end

return EquipmentScreen
