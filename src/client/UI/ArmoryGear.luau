--!strict
--[[
	ArmoryGear.luau
	The Armory's first tab, EQUIPMENT: the gear you keep (PowerGear), shown
	the way the Forgotten Isle's gear screen is (GearView). Two modes:
	"equip" (the Armory, E: WEAR) and "forge" (the village forge: FORGE NEW,
	UPGRADE, SALVAGE, SALVAGE WEAKER).

	  left    your character, live (drag to turn it), the four slots round
	          it (weapon, armor, ring, charm), your POWER, the grade key and
	          what the worn pieces add up to
	  right   the bag as brick models in their grades, strongest first (a
	          filter by slot, eight to a page), FORGE NEW and SALVAGE WEAKER,
	          then the piece picked: its model turning, its stats, its power
	          against what's worn, and WEAR / UPGRADE / SALVAGE

	Every choice is the Armory's own ArmoryAction (LootManager): equipPower,
	upgrade, salvage, salvageWeaker, and FORGE NEW through ForgeMinigame. A
	double click on a bag piece wears it.

	Cheap: the viewports are filled only while the tab shows (Hide empties
	them); a page holds at most 8 bag models; models are clones of one
	template per shape and grade (GearModels.PowerIcon).

	  ArmoryGear.Build(parent, actions)   actions: { wear, upgrade, salvage,
	                                       salvageWeaker, forgeNew(slot) }
	  ArmoryGear.SetState(power)          power = { items, equipped, scrap }
	  ArmoryGear.SetMode("equip" | "forge")
	  ArmoryGear.Show() / Hide() / Render()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PowerGear = require(Shared:WaitForChild("PowerGear"))
local GearData = require(Shared:WaitForChild("GearData"))
local GearModels = require(script.Parent.Parent:WaitForChild("GearModels"))
local GearView = require(script.Parent:WaitForChild("GearView"))

local player = Players.LocalPlayer

local ArmoryGear = {}

local C = GearView.C
local SERIF_BOLD = GearView.SERIF_BOLD
local new, label, button = GearView.new, GearView.label, GearView.button
type Cell = GearView.Cell
type Item = PowerGear.Item

local PER_PAGE = 8
local FILTERS = { "all", "weapon", "armor", "ring", "charm" }

-- ── State ───────────────────────────────────────────────────────────────────
local power: { items: { [string]: Item }, equipped: { [string]: string }, scrap: number } = { items = {}, equipped = {}, scrap = 0 }
local actions: { [string]: any } = {}
local selected: string? = nil
local hoverSlot: string? = nil
local filter = "all"
local page = 1
local shown = false
local mode = "equip"
local forgeRow: Frame
local built = false

local slotCells: { [string]: Cell } = {}
local bagCells: { Cell } = {}
local bagList: { Item } = {}
local filterButtons: { [string]: TextButton } = {}
local pageL: TextLabel
local prevB: TextButton
local nextB: TextButton
local powerL: TextLabel
local scrapL: TextLabel
local totalsL: TextLabel
local forgeButtons: { TextButton } = {}
local weakerB: TextButton
local detailCell: Cell
local detailName: TextLabel
local detailGrade: TextLabel
local detailBody: TextLabel
local wearB: TextButton
local upgradeB: TextButton
local salvageB: TextButton
local preview: GearView.Preview

-- ── Grades ──────────────────────────────────────────────────────────────────
local function tierOf(item: Item?): number
	return if item then (table.find(GearData.RARITIES, item.rarity) or 1) else 0
end

local function colorOf(item: Item?): Color3?
	return if item then (GearData.RARITY_COLOR[item.rarity] or C.dim) else nil
end

local function styleCell(cell: Cell, item: Item?)
	GearView.Style(cell, colorOf(item), tierOf(item), #GearData.RARITIES, item and item.rarity)
end

local function setIcon(cell: Cell, item: Item?)
	local key = if item then (select(1, GearModels.PowerLook(item))) else nil
	GearView.SetIcon(cell, key, function() return if item then GearModels.PowerIcon(item) else nil end, item ~= nil and item.slot == "weapon")
end

local function worn(slot: string): Item?
	local uid = power.equipped[slot]
	return if uid then power.items[uid] else nil
end

local function isWorn(item: Item): boolean
	return item.uid ~= nil and power.equipped[item.slot] == item.uid
end

local function statLines(item: Item): string
	local lines = {}
	for _, a in ipairs(item.affixes or {}) do
		local t = PowerGear.Describe(a, item)
		table.insert(lines, if a.main then `<b>{t}</b>` else t)
	end
	return table.concat(lines, "   ")
end

-- ── Drawing ─────────────────────────────────────────────────────────────────
local function showDetail()
	local item = if selected then power.items[selected] else nil
	if not item then
		selected = nil
		GearView.SetIcon(detailCell, nil, function() return nil end)
		styleCell(detailCell, nil)
		detailName.Text = "Pick a piece"
		detailName.TextColor3 = C.dim
		detailGrade.Text = ""
		detailBody.Text = if mode == "forge" then "Pick a piece to upgrade or salvage it, or forge a new one below the bag."
			else "Click a piece in your bag to compare it with what you wear, or a slot to see what's on.\nDouble-click a bag piece to wear it."
		wearB.Visible, upgradeB.Visible, salvageB.Visible = false, false, false
		return
	end
	setIcon(detailCell, item)
	styleCell(detailCell, item)
	local col = colorOf(item) or C.dim
	detailName.Text = PowerGear.Title(item)
	detailName.TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.15)
	detailGrade.Text = string.upper(item.rarity)
	detailGrade.TextColor3 = col
	local ip = PowerGear.ItemPower(item)
	local lines = { `<font color="#b9aea0">{PowerGear.SLOT_NAME[item.slot] or item.slot}  ·  iLvl {item.ilvl}</font>   <font color="#ffde8c"><b>{ip} POWER</b></font>` }
	table.insert(lines, statLines(item))
	local wearing = isWorn(item)
	local cur = worn(item.slot)
	if wearing then
		table.insert(lines, `<font color="#9d93a8">Worn.</font>`)
	elseif cur then
		local d = ip - PowerGear.ItemPower(cur)
		local diff = if d > 0 then `<font color="#78e68c">▲ +{d} POWER</font>` elseif d < 0 then `<font color="#ff7a6a">▼ {d} POWER</font>` else "= the same POWER"
		table.insert(lines, `{diff}  <font color="#9d93a8">against {PowerGear.Title(cur)}</font>`)
	else
		table.insert(lines, `<font color="#78e68c">▲ +{ip} POWER</font>  <font color="#9d93a8">(nothing worn there)</font>`)
	end
	detailBody.Text = table.concat(lines, "\n")
	local cost = PowerGear.UpgradeCost(item)
	local forging = mode == "forge"
	wearB.Visible, upgradeB.Visible, salvageB.Visible = not forging, forging, forging
	wearB.Text = if wearing then "WORN" else "WEAR"
	GearView.Enable(wearB, not wearing)
	upgradeB.Text = if cost then `UPGRADE +{(item.plus or 0) + 1}  ·  {cost}` else "MAXED +10"
	GearView.Enable(upgradeB, cost ~= nil and (power.scrap or 0) >= cost)
	salvageB.Text = if wearing then "SALVAGE" else `SALVAGE  +{PowerGear.SalvageValue(item)}`
	GearView.Enable(salvageB, not wearing)
end

local function render()
	if not built or not shown then return end
	-- the slots
	local wornList = {}
	for _, slot in ipairs(PowerGear.SLOTS) do
		local cell = slotCells[slot]
		local item = worn(slot)
		if item then table.insert(wornList, item) end
		setIcon(cell, item)
		styleCell(cell, item)
		if cell.slotL then
			cell.slotL.Text = string.upper(PowerGear.SLOT_NAME[slot] or slot)
			cell.slotL.TextColor3 = if item then C.white else C.faint
		end
		if cell.extraL then
			cell.extraL.Text = if item then `{PowerGear.ItemPower(item)}` else ""
		end
		if cell.gradeL and item and (item.plus or 0) > 0 then
			cell.gradeL.Text ..= `  +{item.plus}`
		end
		if (item and item.uid == selected) or hoverSlot == slot then
			cell.stroke.Color = C.goldBright
			cell.stroke.Thickness = 3
			cell.stroke.Transparency = 0
		end
	end
	local lv = player:GetAttribute("AccountLevel")
	powerL.Text = tostring(PowerGear.Total(wornList, if typeof(lv) == "number" then lv else 1))
	scrapL.Text = `{power.scrap or 0} scrap`
	-- what the worn pieces add up to
	local sum, order = {}, {}
	for _, item in ipairs(wornList) do
		for _, a in ipairs(item.affixes or {}) do
			if not sum[a.stat] then
				sum[a.stat] = 0
				table.insert(order, a.stat)
			end
			sum[a.stat] += a.value * PowerGear.Boost(item)
		end
	end
	local parts = {}
	for _, stat in ipairs(order) do table.insert(parts, PowerGear.Describe({ stat = stat, value = sum[stat] }, nil)) end
	totalsL.Text = if #parts > 0 then table.concat(parts, "   ") else `<font color="#5a5260">Nothing worn yet: extract with gear, or forge some.</font>`
	-- the bag: what's not worn, this filter, strongest first
	table.clear(bagList)
	local weaker = 0
	for _, item in pairs(power.items or {}) do
		if isWorn(item) then continue end
		local cur = worn(item.slot)
		if cur and PowerGear.ItemPower(item) < PowerGear.ItemPower(cur) then weaker += 1 end
		if filter == "all" or item.slot == filter then table.insert(bagList, item) end
	end
	table.sort(bagList, function(a, b)
		local pa, pb = PowerGear.ItemPower(a), PowerGear.ItemPower(b)
		if pa ~= pb then return pa > pb end
		return (a.uid or "") < (b.uid or "")
	end)
	local pages = math.max(1, math.ceil(#bagList / PER_PAGE))
	page = math.clamp(page, 1, pages)
	pageL.Text = `{page} / {pages}`
	GearView.Enable(prevB, page > 1)
	GearView.Enable(nextB, page < pages)
	for i, cell in ipairs(bagCells) do
		local item = bagList[(page - 1) * PER_PAGE + i]
		setIcon(cell, item)
		styleCell(cell, item)
		cell.button.Visible = true
		if cell.nameL then
			cell.nameL.Text = if item then PowerGear.Title(item) else ""
			cell.nameL.TextColor3 = if item then (colorOf(item) :: Color3):Lerp(Color3.new(1, 1, 1), 0.3) else C.faint
		end
		if cell.slotL then cell.slotL.Text = if item then `{string.upper(PowerGear.SLOT_NAME[item.slot] or "")}  ·  iLvl {item.ilvl}` else "" end
		if cell.extraL then
			if item then
				local ip = PowerGear.ItemPower(item)
				local cur = worn(item.slot)
				local d = ip - PowerGear.ItemPower(cur)
				local arrow = if d > 0 then `<font color="#78e68c">▲{d}</font>` elseif d < 0 then `<font color="#ff7a6a">▼{-d}</font>` else `<font color="#9d93a8">=</font>`
				cell.extraL.Text = `<font color="#ffde8c">{ip}</font>  {arrow}`
			else
				cell.extraL.Text = ""
			end
		end
		if item and item.uid == selected then
			cell.stroke.Color = C.white
			cell.stroke.Thickness = 3
		end
	end
	for id, fb in pairs(filterButtons) do
		fb.BackgroundColor3 = if id == filter then Color3.fromRGB(80, 60, 32) else C.stone2
		fb.TextColor3 = if id == filter then C.goldBright else C.dim
	end
	-- the forge's own buttons
	local canForge = (power.scrap or 0) >= PowerGear.CRAFT_COST
	for _, fb in ipairs(forgeButtons) do GearView.Enable(fb, canForge) end
	weakerB.Text = `SALVAGE {weaker} WEAKER`
	weakerB.Visible = weaker > 0 and mode == "forge"
	forgeRow.Visible = mode == "forge"
	showDetail()
end

local function pick(uid: string?)
	selected = uid
	render()
end

-- ── Building it ─────────────────────────────────────────────────────────────
local SLOT = 100

local function slotCell(parent: Instance, slot: string, x: number, y: number)
	local cell = GearView.Cell(parent, { Name = "Slot_" .. slot, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(SLOT, SLOT) },
		{ Position = UDim2.fromOffset(6, 16), Size = UDim2.new(1, -12, 1, -50) })
	-- (top: the diamonds and its power; bottom: its grade, then the slot)
	cell.slotL = label(cell.button, { Position = UDim2.new(0, 0, 1, -18), Size = UDim2.new(1, 0, 0, 16), TextSize = 11, FontFace = SERIF_BOLD,
		TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	cell.gradeL = label(cell.button, { Position = UDim2.new(0, 0, 1, -32), Size = UDim2.new(1, 0, 0, 13), TextSize = 10,
		FontFace = SERIF_BOLD, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 4 })
	cell.extraL = label(cell.button, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -5, 0, 2), Size = UDim2.fromOffset(60, 13), TextSize = 10,
		FontFace = SERIF_BOLD, TextColor3 = C.goldBright, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	cell.pips = GearView.Pips(cell.button, { Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(50, 12) })
	cell.button.MouseButton1Click:Connect(function()
		local item = worn(slot)
		pick(if item then item.uid else nil)
	end)
	slotCells[slot] = cell
end

local lastClick, lastUid = 0, ""

local function bagCell(parent: Instance, i: number)
	local cell = GearView.Cell(parent, { Name = "Bag" .. i, LayoutOrder = i, Size = UDim2.fromOffset(250, 66) },
		{ Position = UDim2.fromOffset(4, 3), Size = UDim2.fromOffset(60, 60) })
	cell.nameL = label(cell.button, { Position = UDim2.fromOffset(70, 6), Size = UDim2.new(1, -76, 0, 20), TextSize = 13, FontFace = SERIF_BOLD,
		TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 4 })
	cell.gradeL = label(cell.button, { Position = UDim2.fromOffset(70, 27), Size = UDim2.fromOffset(100, 14), TextSize = 10, FontFace = SERIF_BOLD, ZIndex = 4 })
	cell.slotL = label(cell.button, { Position = UDim2.fromOffset(70, 44), Size = UDim2.fromOffset(110, 14), TextSize = 10, TextColor3 = C.dim, ZIndex = 4 })
	cell.extraL = label(cell.button, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 42), Size = UDim2.fromOffset(80, 16), TextSize = 12,
		FontFace = SERIF_BOLD, RichText = true, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
	cell.pips = GearView.Pips(cell.button, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -6, 0, 28), Size = UDim2.fromOffset(66, 12) })
	cell.button.MouseButton1Click:Connect(function()
		local item = bagList[(page - 1) * PER_PAGE + i]
		if not item or not item.uid then
			pick(nil)
			return
		end
		local uid = item.uid :: string
		local now = os.clock()
		if mode == "equip" and lastUid == uid and now - lastClick < 0.4 then
			-- (a double click: wear it)
			lastUid = ""
			actions.wear(uid)
			return
		end
		lastClick, lastUid = now, uid
		pick(uid)
	end)
	cell.button.MouseEnter:Connect(function()
		local item = bagList[(page - 1) * PER_PAGE + i]
		hoverSlot = item and item.slot
		render()
	end)
	cell.button.MouseLeave:Connect(function()
		if hoverSlot then
			hoverSlot = nil
			render()
		end
	end)
	table.insert(bagCells, cell)
end

-- The tab's contents, in `parent` (about 1052 × 494).
function ArmoryGear.Build(parent: Frame, acts: { [string]: any })
	actions = acts
	-- the character and its slots
	local doll = new("Frame", { Name = "Doll", BackgroundTransparency = 1, Size = UDim2.fromOffset(520, 494) }, parent)
	slotCell(doll, "weapon", 0, 0)
	slotCell(doll, "armor", 0, SLOT + 12)
	slotCell(doll, "ring", 520 - SLOT, 0)
	slotCell(doll, "charm", 520 - SLOT, SLOT + 12)
	local stage = new("Frame", { Name = "Stage", BackgroundColor3 = Color3.fromRGB(22, 18, 28), BorderSizePixel = 0,
		Position = UDim2.fromOffset(SLOT + 12, 0), Size = UDim2.fromOffset(520 - 2 * SLOT - 24, 400), ClipsDescendants = true }, doll)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, stage)
	new("UIStroke", { Color = C.gold, Thickness = 1, Transparency = 0.55 }, stage)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(70, 58, 84), Color3.fromRGB(12, 10, 16)) }, stage)
	preview = GearView.Preview(stage)
	-- POWER, under the right column
	local pw = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(520 - SLOT, 2 * (SLOT + 12)), Size = UDim2.fromOffset(SLOT, 90) }, doll)
	label(pw, { Text = "POWER", Size = UDim2.new(1, 0, 0, 14), TextSize = 11, FontFace = SERIF_BOLD, TextColor3 = C.gold,
		TextXAlignment = Enum.TextXAlignment.Center })
	powerL = label(pw, { Text = "", Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 30), TextSize = 26, FontFace = SERIF_BOLD,
		TextColor3 = C.goldBright, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 })
	scrapL = label(pw, { Text = "", Position = UDim2.fromOffset(0, 48), Size = UDim2.new(1, 0, 0, 14), TextSize = 11, TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Center })
	-- the grade key, under the left column
	local key = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(4, 2 * (SLOT + 12)), Size = UDim2.fromOffset(SLOT, 120) }, doll)
	new("UIListLayout", { Padding = UDim.new(0, 2), SortOrder = Enum.SortOrder.LayoutOrder }, key)
	for i, name in ipairs(GearData.RARITIES) do
		local col = GearData.RARITY_COLOR[name]
		local row = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(SLOT, 17), LayoutOrder = i }, key)
		local sw = new("Frame", { BackgroundColor3 = col, BorderSizePixel = 0, Size = UDim2.fromOffset(9, 9), Rotation = 45, Position = UDim2.fromOffset(3, 4) }, row)
		new("UIStroke", { Color = C.stone, Thickness = 1 }, sw)
		label(row, { Text = string.upper(name), Position = UDim2.fromOffset(19, 0), Size = UDim2.fromOffset(SLOT - 19, 17), TextSize = 10,
			FontFace = SERIF_BOLD, TextColor3 = col })
	end
	-- what it adds up to
	local sumBox = new("Frame", { BackgroundColor3 = C.stone2, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 410), Size = UDim2.fromOffset(520, 84) }, doll)
	new("UICorner", { CornerRadius = UDim.new(0, 5) }, sumBox)
	new("UIStroke", { Color = C.gold, Thickness = 1, Transparency = 0.6 }, sumBox)
	label(sumBox, { Text = "WORN BONUSES  ·  from your next run", Position = UDim2.fromOffset(10, 6), Size = UDim2.fromOffset(400, 14), TextSize = 11,
		FontFace = SERIF_BOLD, TextColor3 = C.gold })
	totalsL = label(sumBox, { Text = "", Position = UDim2.fromOffset(10, 24), Size = UDim2.new(1, -20, 1, -28), TextSize = 13, RichText = true,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextColor3 = C.green })

	-- the bag
	local right = new("Frame", { Name = "Right", BackgroundTransparency = 1, Position = UDim2.fromOffset(540, 0), Size = UDim2.fromOffset(512, 494) }, parent)
	local chips = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(330, 22) }, right)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }, chips)
	for i, f in ipairs(FILTERS) do
		local fb = button(chips, if f == "all" then "ALL" else string.upper(PowerGear.SLOT_NAME[f]), C.dim,
			{ Name = "Filter_" .. f, LayoutOrder = i, Size = UDim2.fromOffset(if f == "all" then 46 else 64, 22), TextSize = 11 })
		fb.MouseButton1Click:Connect(function()
			filter = f
			page = 1
			render()
		end)
		filterButtons[f] = fb
	end
	prevB = button(right, "<", C.gold, { Name = "Prev", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -30, 0, 0), Size = UDim2.fromOffset(24, 22), TextSize = 13 })
	nextB = button(right, ">", C.gold, { Name = "Next", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 0), Size = UDim2.fromOffset(24, 22), TextSize = 13 })
	pageL = label(right, { Text = "", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -58, 0, 4), Size = UDim2.fromOffset(60, 14), TextSize = 10,
		TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Right })
	prevB.MouseButton1Click:Connect(function()
		page -= 1
		render()
	end)
	nextB.MouseButton1Click:Connect(function()
		page += 1
		render()
	end)
	local grid = new("Frame", { Name = "Bag", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 28), Size = UDim2.fromOffset(512, 290) }, right)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(252, 66), CellPadding = UDim2.fromOffset(8, 7), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	for i = 1, PER_PAGE do bagCell(grid, i) end
	-- the forge
	forgeRow = new("Frame", { Name = "ForgeNew", BackgroundTransparency = 1, Position = UDim2.fromOffset(0, 324), Size = UDim2.fromOffset(512, 22) }, right)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		VerticalAlignment = Enum.VerticalAlignment.Center }, forgeRow)
	label(forgeRow, { Text = `FORGE NEW  ·  {PowerGear.CRAFT_COST}`, Size = UDim2.fromOffset(112, 22), TextSize = 11, FontFace = SERIF_BOLD,
		TextColor3 = C.gold, LayoutOrder = 0 })
	for i, slot in ipairs(PowerGear.SLOTS) do
		local fb = button(forgeRow, string.upper(PowerGear.SLOT_NAME[slot]), C.goldBright,
			{ Name = "Forge_" .. slot, LayoutOrder = i, Size = UDim2.fromOffset(62, 22), TextSize = 11, BackgroundColor3 = Color3.fromRGB(70, 46, 22) })
		fb.MouseButton1Click:Connect(function()
			if not fb.Active then return end
			actions.forgeNew(slot)
		end)
		table.insert(forgeButtons, fb)
	end
	weakerB = button(right, "SALVAGE WEAKER", C.red, { Name = "SalvageWeaker", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, 0, 0, 324),
		Size = UDim2.fromOffset(134, 22), TextSize = 10, Visible = false })
	weakerB.MouseButton1Click:Connect(function() actions.salvageWeaker() end)
	-- the piece picked
	local detail = new("Frame", { Name = "Detail", BackgroundColor3 = C.stone2, BorderSizePixel = 0, Position = UDim2.fromOffset(0, 352),
		Size = UDim2.fromOffset(512, 142) }, right)
	new("UICorner", { CornerRadius = UDim.new(0, 5) }, detail)
	new("UIStroke", { Color = C.gold, Thickness = 1, Transparency = 0.55 }, detail)
	detailCell = GearView.Cell(detail, { Name = "Icon", Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(126, 126), Active = false },
		{ Position = UDim2.fromOffset(4, 14), Size = UDim2.new(1, -8, 1, -18) })
	detailCell.pips = GearView.Pips(detailCell.button, { Position = UDim2.fromOffset(5, 3), Size = UDim2.fromOffset(66, 12) })
	detailName = label(detail, { Text = "", Position = UDim2.fromOffset(144, 6), Size = UDim2.fromOffset(220, 22), TextSize = 16, FontFace = SERIF_BOLD,
		TextTruncate = Enum.TextTruncate.AtEnd })
	detailGrade = label(detail, { Text = "", Position = UDim2.fromOffset(144, 28), Size = UDim2.fromOffset(150, 14), TextSize = 11, FontFace = SERIF_BOLD })
	detailBody = label(detail, { Text = "", Position = UDim2.fromOffset(144, 46), Size = UDim2.fromOffset(222, 92), TextSize = 11, RichText = true,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	wearB = button(detail, "WEAR", C.green, { Name = "Wear", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8), Size = UDim2.fromOffset(132, 38) })
	upgradeB = button(detail, "UPGRADE", C.goldBright, { Name = "Upgrade", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 8),
		Size = UDim2.fromOffset(132, 38), TextSize = 12, BackgroundColor3 = Color3.fromRGB(70, 46, 22) })
	salvageB = button(detail, "SALVAGE", C.red, { Name = "Salvage", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -8, 0, 52),
		Size = UDim2.fromOffset(132, 38), TextSize = 12 })
	wearB.MouseButton1Click:Connect(function()
		if wearB.Active and selected then actions.wear(selected) end
	end)
	upgradeB.MouseButton1Click:Connect(function()
		if upgradeB.Active and selected then actions.upgrade(selected) end
	end)
	salvageB.MouseButton1Click:Connect(function()
		if salvageB.Active and selected then
			actions.salvage(selected)
			selected = nil
			render()
		end
	end)
	RunService.Heartbeat:Connect(function(dt)
		if not shown then return end
		preview:Step(dt)
		local m = detailCell.model
		if m then
			local item = if selected then power.items[selected] else nil
			GearView.FrameIcon(m, detailCell.cam, item ~= nil and item.slot == "weapon", (os.clock() * 0.9) % (math.pi * 2))
		end
		local cells = { detailCell }
		for _, cell in pairs(slotCells) do table.insert(cells, cell) end
		for _, cell in ipairs(bagCells) do table.insert(cells, cell) end
		GearView.Shimmer(cells)
	end)
	built = true
end

function ArmoryGear.SetState(p: any)
	if typeof(p) ~= "table" then return end
	power = p
	power.items = power.items or {}
	power.equipped = power.equipped or {}
	if selected and not power.items[selected] then selected = nil end
	render()
end

-- (worn at once on this screen, before the server's state comes back)
function ArmoryGear.WearNow(uid: string)
	local item = power.items[uid]
	if item then power.equipped[item.slot] = uid end
	render()
end

function ArmoryGear.SetMode(m: string)
	if m == mode then return end
	mode = m
	selected = nil
	render()
end

function ArmoryGear.Show()
	if not built or shown then return end
	shown = true
	preview:Show()
	render()
end

function ArmoryGear.Hide()
	if not built or not shown then return end
	shown = false
	hoverSlot = nil
	-- (the viewports emptied: nothing renders while it's hidden)
	preview:Hide()
	for _, cell in pairs(slotCells) do GearView.SetIcon(cell, nil, function() return nil end) end
	for _, cell in ipairs(bagCells) do GearView.SetIcon(cell, nil, function() return nil end) end
	GearView.SetIcon(detailCell, nil, function() return nil end)
end

function ArmoryGear.Render()
	render()
end

return ArmoryGear
