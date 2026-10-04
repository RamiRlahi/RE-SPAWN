--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- MinimapUI.luau
-- Top-left circular compass minimap (gold rings, N/E/S/W diamonds), plus a
-- zoomed-out full dungeon map toggled with Tab (drawn at 50% transparency).
-- ─────────────────────────────────────────────────────────────────────────────

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")
local Workspace         = game:GetService("Workspace")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local RunScope = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RunScope"))
local Network = require(Shared:WaitForChild("Network"))
local TomeData = require(Shared:WaitForChild("TomeData"))

local TomeController: any = nil
pcall(function()
	TomeController = require(script.Parent.Parent:WaitForChild("TomeController"))
end)
local TomeIcons = require(script.Parent:WaitForChild("TomeIcons"))

local MinimapUI = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local containerFrame: Frame? = nil
local mapCanvas: Frame? = nil

-- Player markers: each player's avatar headshot with a gold pointer riding
-- its edge in the direction they face. You sit at the minimap's centre;
-- teammates are drawn where they are (on both maps).
type Marker = { root: Frame, pivot: Frame }
local selfMarker: Marker? = nil
local mateMarkers: { [Player]: Marker } = {}
local fullMarkers: { [Player]: Marker } = {}

local activeMapData: any = nil

-- Full map (Tab)
local FULL_MAP_TRANSPARENCY = 0.5
local fullGui: ScreenGui? = nil
local fullGroup: CanvasGroup? = nil
local fullCanvas: Frame? = nil
local fullTiles: { Frame } = {}
local fullTileByKey: { [string]: Frame } = {}
-- Cleared rooms (server: Workspace.ClearedRooms): tiles dimmed, a check mark.
local CLEARED_COLOR = Color3.fromRGB(58, 74, 62)
local clearMarks: { Instance } = {}
local tomeList: ScrollingFrame? = nil
local fullBounds = { minX = 0, minZ = 0, w = 1, d = 1 }
local tileFrames: { [string]: Frame } = {}
local roomTypeColors = {
	Start    = Color3.fromRGB(46, 204, 113),   -- Emerald Green
	Combat   = Color3.fromRGB(74, 105, 189),   -- Steel Blue
	Rest     = Color3.fromRGB(52, 231, 228),   -- Healing Cyan
	Treasure = Color3.fromRGB(241, 196, 15),   -- Gold
	Shop     = Color3.fromRGB(230, 126, 34),   -- Amber
	Gamble   = Color3.fromRGB(200, 40, 90),    -- Casino Crimson
	Elite    = Color3.fromRGB(155, 89, 182),   -- Purple
	Event    = Color3.fromRGB(52, 152, 219),   -- Light Blue
	Boss     = Color3.fromRGB(231, 76, 60),    -- Crimson
}

local MAP_SCALE = 3.2 -- pixels per 12-stud floor tile
local MAP_SIZE = 190

-- Stone-grey map with only a hint of each room type's colour.
local TILE_BASE = Color3.fromRGB(96, 90, 104)
local CORRIDOR_COLOR = Color3.fromRGB(70, 66, 78)
local ROOM_TINT = 0.28

local GOLD = Color3.fromRGB(212, 172, 92)
local GOLD_BRIGHT = Color3.fromRGB(255, 222, 140)
local GOLD_DIM = Color3.fromRGB(128, 100, 52)
local STONE = Color3.fromRGB(14, 11, 17)
local SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

-- ── UI Construction ──────────────────────────────────────────────────────────

local function ring(parent: Instance, inset: number, color: Color3, thickness: number, transparency: number, z: number): Frame
	local r = Instance.new("Frame")
	r.Size = UDim2.new(1, -inset, 1, -inset)
	r.Position = UDim2.fromScale(0.5, 0.5)
	r.AnchorPoint = Vector2.new(0.5, 0.5)
	r.BackgroundTransparency = 1
	r.ZIndex = z
	r.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = r
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = thickness
	stroke.Transparency = transparency
	stroke.Parent = r
	return r
end

-- Compass point: a gold-edged diamond with its letter on top.
local function compassPoint(parent: Instance, letter: string, pos: UDim2)
	local d = Instance.new("Frame")
	d.Size = UDim2.fromOffset(20, 20)
	d.Position = pos
	d.AnchorPoint = Vector2.new(0.5, 0.5)
	d.Rotation = 45
	d.BackgroundColor3 = STONE
	d.BorderSizePixel = 0
	d.ZIndex = 12
	d.Parent = parent
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.2
	stroke.Parent = d

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromOffset(20, 20)
	label.Position = pos
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.BackgroundTransparency = 1
	label.Text = letter
	label.FontFace = SERIF_BOLD
	label.TextSize = 11
	label.TextColor3 = GOLD_BRIGHT
	label.ZIndex = 13
	label.Parent = parent
end

-- A player's map marker: their headshot in a gold ring, and a pointer
-- (turned with `pivot.Rotation`, 0 = north) showing which way they face.
local function makeMarker(parent: Instance, userId: number, size: number, z: number): Marker
	local root = Instance.new("Frame")
	root.Name = `Marker_{userId}`
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Size = UDim2.fromOffset(size, size)
	root.BackgroundTransparency = 1
	root.ZIndex = z
	root.Parent = parent
	local pivot = Instance.new("Frame")
	pivot.AnchorPoint = Vector2.new(0.5, 0.5)
	pivot.Position = UDim2.fromScale(0.5, 0.5)
	pivot.Size = UDim2.fromScale(1, 1)
	pivot.BackgroundTransparency = 1
	pivot.ZIndex = z
	pivot.Parent = root
	local tip = Instance.new("Frame")
	tip.AnchorPoint = Vector2.new(0.5, 0.5)
	tip.Position = UDim2.new(0.5, 0, 0, -1)
	tip.Size = UDim2.fromOffset(math.floor(size * 0.45), math.floor(size * 0.45))
	tip.Rotation = 45
	tip.BackgroundColor3 = GOLD_BRIGHT
	tip.BorderSizePixel = 0
	tip.ZIndex = z
	tip.Parent = pivot
	local head = Instance.new("ImageLabel")
	head.AnchorPoint = Vector2.new(0.5, 0.5)
	head.Position = UDim2.fromScale(0.5, 0.5)
	head.Size = UDim2.fromScale(1, 1)
	head.BackgroundColor3 = STONE
	head.Image = `rbxthumb://type=AvatarHeadShot&id={userId}&w=48&h=48`
	head.ZIndex = z + 1
	head.Parent = root
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(1, 0)
	corner.Parent = head
	local stroke = Instance.new("UIStroke")
	stroke.Color = if userId == player.UserId then GOLD_BRIGHT else Color3.fromRGB(150, 210, 255)
	stroke.Thickness = 2
	stroke.Parent = head
	return { root = root, pivot = pivot }
end

-- Map rotation (clockwise degrees, 0 = north / -Z) for a facing direction.
local function facingAngle(look: Vector3): number
	return math.deg(math.atan2(look.X, -look.Z))
end

local function createMinimapGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DungeonMinimapGui")
	if existing then existing:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DungeonMinimapGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	-- The map is built early so it can receive dungeon data, but it stays hidden
	-- until the player has left the lobby and entered the run.
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	gui = screenGui

	-- Top-left compass (below Roblox's top bar)
	local container = Instance.new("Frame")
	container.Name = "MinimapContainer"
	container.Size = UDim2.fromOffset(MAP_SIZE, MAP_SIZE)
	container.Position = UDim2.new(0, 26, 0, 16)
	container.BackgroundTransparency = 1
	container.Parent = screenGui
	containerFrame = container

	-- Circular map window: a CanvasGroup clips the tiles to its rounded corner.
	local window = Instance.new("CanvasGroup")
	window.Name = "MapWindow"
	window.Size = UDim2.new(1, -20, 1, -20)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.BackgroundColor3 = Color3.fromRGB(10, 8, 14)
	window.BackgroundTransparency = 0.3
	window.BorderSizePixel = 0
	window.ZIndex = 2
	window.Parent = container
	local windowCorner = Instance.new("UICorner")
	windowCorner.CornerRadius = UDim.new(1, 0)
	windowCorner.Parent = window

	-- Map Canvas (Translates as player moves)
	local canvas = Instance.new("Frame")
	canvas.Name = "MapCanvas"
	canvas.Size = UDim2.new(1, 0, 1, 0)
	canvas.Position = UDim2.new(0.5, 0, 0.5, 0)
	canvas.BackgroundTransparency = 1
	canvas.Parent = window
	mapCanvas = canvas

	-- Gold rings: bright outer, dim inner edge of the map window.
	ring(container, 0, GOLD, 1.5, 0.1, 10)
	ring(container, 20, GOLD_DIM, 1, 0.35, 10)

	compassPoint(container, "N", UDim2.fromScale(0.5, 0))
	compassPoint(container, "E", UDim2.fromScale(1, 0.5))
	compassPoint(container, "S", UDim2.fromScale(0.5, 1))
	compassPoint(container, "W", UDim2.fromScale(0, 0.5))

	-- You, at the centre.
	local m = makeMarker(container, player.UserId, 26, 11)
	m.root.Position = UDim2.fromScale(0.5, 0.5)
	selfMarker = m
end

local function createFullMapGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DungeonFullMapGui")
	if existing then existing:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DungeonFullMapGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 60
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Enabled = false
	screenGui.Parent = playerGui
	fullGui = screenGui

	-- The whole map is one CanvasGroup so it fades as a unit.
	local group = Instance.new("CanvasGroup")
	group.Name = "FullMap"
	group.AnchorPoint = Vector2.new(0.5, 0.5)
	group.Position = UDim2.fromScale(0.5, 0.41)
	group.Size = UDim2.fromScale(0.62, 0.68)
	group.BackgroundColor3 = STONE
	group.BackgroundTransparency = 0.15
	group.BorderSizePixel = 0
	group.GroupTransparency = FULL_MAP_TRANSPARENCY
	group.Parent = screenGui
	fullGroup = group
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 2
	stroke.Parent = group

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 34)
	title.Position = UDim2.fromOffset(0, 10)
	title.Text = "DUNGEON MAP"
	title.FontFace = SERIF_BOLD
	title.TextSize = 24
	title.TextColor3 = GOLD_BRIGHT
	title.Parent = group
	local hint = title:Clone()
	hint.Text = "Release Tab to close"
	hint.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json")
	hint.TextSize = 13
	hint.TextColor3 = GOLD
	hint.Position = UDim2.new(0, 0, 1, -30)
	hint.Size = UDim2.new(1, 0, 0, 20)
	hint.Parent = group

	-- Tiles are placed in scale units on a canvas locked to the dungeon's
	-- aspect ratio, so the whole dungeon always fits.
	local area = Instance.new("Frame")
	area.BackgroundTransparency = 1
	area.Position = UDim2.fromOffset(24, 50)
	area.Size = UDim2.new(1, -48, 1, -90)
	area.Parent = group
	local canvas = Instance.new("Frame")
	canvas.Name = "Canvas"
	canvas.AnchorPoint = Vector2.new(0.5, 0.5)
	canvas.Position = UDim2.fromScale(0.5, 0.5)
	canvas.Size = UDim2.fromScale(1, 1)
	canvas.BackgroundTransparency = 1
	canvas.Parent = area
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.Name = "Aspect"
	aspect.Parent = canvas
	fullCanvas = canvas


	-- Your tomes this run, under the map (kept opaque so they're readable).
	local tomes = Instance.new("Frame")
	tomes.Name = "Tomes"
	tomes.AnchorPoint = Vector2.new(0.5, 0)
	tomes.Position = UDim2.fromScale(0.5, 0.765)
	tomes.Size = UDim2.fromScale(0.62, 0.215)
	tomes.BackgroundColor3 = STONE
	tomes.BackgroundTransparency = 0.2
	tomes.BorderSizePixel = 0
	tomes.Parent = screenGui
	local tStroke = Instance.new("UIStroke")
	tStroke.Color = GOLD
	tStroke.Thickness = 2
	tStroke.Parent = tomes
	local tTitle = title:Clone()
	tTitle.Text = "YOUR TOMES"
	tTitle.TextSize = 18
	tTitle.Size = UDim2.new(1, 0, 0, 22)
	tTitle.Position = UDim2.fromOffset(0, 6)
	tTitle.Parent = tomes
	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(12, 32)
	list.Size = UDim2.new(1, -24, 1, -40)
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = GOLD
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = tomes
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(210, 46)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = list
	tomeList = list
end

-- Rebuild the tome cards from the Tome_<id> attributes the server keeps.
local function refreshTomes()
	local list = tomeList
	if not list then return end
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("Frame") or c:IsA("TextLabel") then c:Destroy() end
	end
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
	if #owned == 0 then
		local none = Instance.new("TextLabel")
		none.BackgroundTransparency = 1
		none.Size = UDim2.fromOffset(360, 30)
		none.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json")
		none.TextSize = 14
		none.TextColor3 = GOLD
		none.Text = "No tomes yet. Clear a room to choose one."
		none.Parent = list
		return
	end
	for i, t in ipairs(owned) do
		local tome = TomeData.GetTome(t.id)
		local accent = if TomeController and TomeController.AccentFor then TomeController.AccentFor(t.id) else GOLD_BRIGHT
		local card = Instance.new("Frame")
		card.LayoutOrder = i
		card.BackgroundColor3 = Color3.fromRGB(37, 28, 24)
		card.BorderSizePixel = 0
		card.Parent = list
		local cs = Instance.new("UIStroke")
		cs.Color = accent
		cs.Thickness = 1.5
		cs.Parent = card
		local logo = TomeIcons.Make(card, t.id, 1, 40)
		logo.Position = UDim2.fromOffset(3, 3)
		local name = Instance.new("TextLabel")
		name.BackgroundTransparency = 1
		name.Position = UDim2.fromOffset(46, 3)
		name.Size = UDim2.new(1, -88, 0, 20)
		name.FontFace = SERIF_BOLD
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextTruncate = Enum.TextTruncate.AtEnd
		name.TextColor3 = accent
		name.Text = if tome then string.gsub(tome.name, " Tome$", "") else t.id
		name.Parent = card
		local desc = name:Clone()
		desc.Position = UDim2.fromOffset(46, 23)
		desc.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json")
		desc.TextSize = 11
		desc.TextColor3 = Color3.fromRGB(239, 213, 170)
		desc.Text = if tome then tome.description else ""
		desc.Parent = card
		local count = name:Clone()
		count.AnchorPoint = Vector2.new(1, 0.5)
		count.Position = UDim2.new(1, -8, 0.5, 0)
		count.Size = UDim2.fromOffset(40, 24)
		count.TextSize = 18
		count.TextXAlignment = Enum.TextXAlignment.Right
		count.TextColor3 = GOLD_BRIGHT
		count.Text = `×{t.count}`
		count.Parent = card
	end
end

local function renderFullMap(mapData: any, roomColorGrid: { [string]: Color3 })
	local canvas = fullCanvas
	if not canvas then return end
	for _, f in ipairs(fullTiles) do f:Destroy() end
	table.clear(fullTiles)
	table.clear(fullTileByKey)

	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	local cells = {}
	for key in pairs(mapData.grid) do
		local coords = string.split(key, "_")
		local gx, gz = tonumber(coords[1]), tonumber(coords[2])
		if gx and gz then
			table.insert(cells, { gx, gz, key })
			minX, minZ = math.min(minX, gx), math.min(minZ, gz)
			maxX, maxZ = math.max(maxX, gx), math.max(maxZ, gz)
		end
	end
	if #cells == 0 then return end
	local w, d = maxX - minX + 1, maxZ - minZ + 1
	fullBounds = { minX = minX, minZ = minZ, w = w, d = d }
	local aspect = canvas:FindFirstChild("Aspect") :: UIAspectRatioConstraint
	aspect.AspectRatio = w / d

	for _, cell in ipairs(cells) do
		local tile = Instance.new("Frame")
		tile.BorderSizePixel = 0
		-- Slight overlap hides hairline seams between tiles at odd scales.
		tile.Size = UDim2.new(1 / w, 1, 1 / d, 1)
		tile.Position = UDim2.fromScale((cell[1] - minX) / w, (cell[2] - minZ) / d)
		tile.BackgroundColor3 = roomColorGrid[cell[3]] or CORRIDOR_COLOR
		tile.Parent = canvas
		table.insert(fullTiles, tile)
		fullTileByKey[cell[3]] = tile
	end
end

-- ── Cleared rooms ────────────────────────────────────────────────────────────
-- A room whose mobs are all dead: its tiles dim to a mossy grey and a gold
-- check mark sits in its middle (minimap and Tab map).
local function checkMark(parent: Instance, size: number): TextLabel
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 0.5)
	l.Size = UDim2.fromOffset(size * 2, size * 2)
	l.BackgroundTransparency = 1
	l.Text = "✓"
	l.FontFace = SERIF_BOLD
	l.TextSize = size
	l.TextColor3 = GOLD_BRIGHT
	l.TextStrokeColor3 = STONE
	l.TextStrokeTransparency = 0.2
	l.ZIndex = 4
	l.Parent = parent
	table.insert(clearMarks, l)
	return l
end

local function applyCleared()
	for _, m in ipairs(clearMarks) do m:Destroy() end
	table.clear(clearMarks)
	local data = activeMapData
	local list = RunScope.Mine("ClearedRooms")
	if not data or not data.rooms or typeof(list) ~= "string" then return end
	for _, room in ipairs(data.rooms) do
		if not string.find(list, `|{room.id}|`, 1, true) then continue end
		for rx = room.gx, room.gx + room.w - 1 do
			for rz = room.gz, room.gz + room.d - 1 do
				local key = `{rx}_{rz}`
				local t = tileFrames[key]
				if t then t.BackgroundColor3 = CLEARED_COLOR end
				local f = fullTileByKey[key]
				if f then f.BackgroundColor3 = CLEARED_COLOR end
			end
		end
		local cx, cz = room.gx + room.w / 2, room.gz + room.d / 2
		if mapCanvas then
			checkMark(mapCanvas, 14).Position = UDim2.fromOffset(cx * MAP_SCALE, cz * MAP_SCALE)
		end
		if fullCanvas then
			local b = fullBounds
			checkMark(fullCanvas, 22).Position = UDim2.fromScale((cx - b.minX) / b.w, (cz - b.minZ) / b.d)
		end
	end
end

-- ── Map Data Rendering ───────────────────────────────────────────────────────

local function renderMap(mapData: any)
	if not mapCanvas then return end
	activeMapData = mapData

	-- Clear previous rendered tiles
	for _, frame in pairs(tileFrames) do
		frame:Destroy()
	end
	table.clear(tileFrames)

	if not mapData or not mapData.grid then return end

	-- Room Type Color lookup map by cell
	local roomColorGrid: { [string]: Color3 } = {}
	if mapData.rooms then
		for _, room in ipairs(mapData.rooms) do
			local col = TILE_BASE:Lerp(roomTypeColors[room.roomType] or TILE_BASE, ROOM_TINT)
			for rx = room.gx, room.gx + room.w - 1 do
				for rz = room.gz, room.gz + room.d - 1 do
					roomColorGrid[`{rx}_{rz}`] = col
				end
			end
		end
	end

	-- Render each floor tile onto canvas
	for key, _ in pairs(mapData.grid) do
		local coords = string.split(key, "_")
		local gx = tonumber(coords[1])
		local gz = tonumber(coords[2])

		if gx and gz then
			local tileFrame = Instance.new("Frame")
			tileFrame.Name = `Tile_{gx}_{gz}`
			tileFrame.Size = UDim2.new(0, MAP_SCALE, 0, MAP_SCALE)
			tileFrame.Position = UDim2.new(0, gx * MAP_SCALE, 0, gz * MAP_SCALE)
			
			local tileColor = roomColorGrid[key] or CORRIDOR_COLOR
			tileFrame.BackgroundColor3 = tileColor
			tileFrame.BackgroundTransparency = 0.25
			tileFrame.BorderSizePixel = 0
			tileFrame.Parent = mapCanvas

			tileFrames[key] = tileFrame
		end
	end

	renderFullMap(mapData, roomColorGrid)
	applyCleared()
end

-- ── Real-Time Tracking Loop ──────────────────────────────────────────────────

local function startTrackingLoop()
	RunService.RenderStepped:Connect(function()
		local canvas = mapCanvas
		if not canvas or not activeMapData then return end
		local tileSize = activeMapData.tileSize or 12

		-- The minimap scrolls so you stay centred; your pointer turns with you.
		local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if myRoot then
			local gx, gz = myRoot.Position.X / tileSize, myRoot.Position.Z / tileSize
			canvas.Position = UDim2.new(0.5, -gx * MAP_SCALE, 0.5, -gz * MAP_SCALE)
			if selfMarker then selfMarker.pivot.Rotation = facingAngle(myRoot.CFrame.LookVector) end
		end

		-- Everyone in the run: teammates on the minimap, all players on the
		-- Tab map (tile gx covers world X gx*tileSize ± half a tile there).
		local full = if fullGui and fullGui.Enabled then fullCanvas else nil
		local seen: { [Player]: boolean } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not r or p:GetAttribute("InLobby") ~= false then continue end
			seen[p] = true
			local gx, gz = r.Position.X / tileSize, r.Position.Z / tileSize
			local angle = facingAngle(r.CFrame.LookVector)
			if p ~= player then
				local m = mateMarkers[p] or makeMarker(canvas, p.UserId, 20, 6)
				mateMarkers[p] = m
				m.root.Position = UDim2.fromOffset(gx * MAP_SCALE, gz * MAP_SCALE)
				m.pivot.Rotation = angle
			end
			if full then
				local fm = fullMarkers[p] or makeMarker(full, p.UserId, if p == player then 28 else 24, 5)
				fullMarkers[p] = fm
				local b = fullBounds
				fm.root.Position = UDim2.fromScale((gx + 0.5 - b.minX) / b.w, (gz + 0.5 - b.minZ) / b.d)
				fm.pivot.Rotation = angle
			end
		end
		for p, m in pairs(mateMarkers) do
			if not seen[p] then m.root:Destroy(); mateMarkers[p] = nil end
		end
		for p, m in pairs(fullMarkers) do
			if not seen[p] then m.root:Destroy(); fullMarkers[p] = nil end
		end
	end)
	-- (the run's cleared rooms live on its RunScope folder: re-checked often)
	local lastCleared: any = nil
	task.spawn(function()
		while true do
			task.wait(0.5)
			local now = RunScope.Mine("ClearedRooms")
			if now ~= lastCleared then
				lastCleared = now
				applyCleared()
			end
		end
	end)
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- Show / hide the zoomed-out map (only during a run, when the minimap is up).
function MinimapUI.ToggleFullMap(open: boolean?)
	if not fullGui then return end
	local show = if open ~= nil then open else not fullGui.Enabled
	if show and not (gui and gui.Enabled) then return end
	fullGui.Enabled = show
	if show then refreshTomes() end
	-- Cursor back while the map is up, so tome logos can be hovered.
	TomeIcons.SetInspecting(show)
	if show and fullGroup then
		-- Quick fade in to the map's resting transparency.
		fullGroup.GroupTransparency = 1
		TweenService:Create(fullGroup, TweenInfo.new(0.15), { GroupTransparency = FULL_MAP_TRANSPARENCY }):Play()
	end
end

function MinimapUI.Init()
	createMinimapGui()
	createFullMapGui()

	-- Tab opens the map, so Roblox's player list (also on Tab) is turned off.
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
	-- Hold Tab: map + your tomes; let go to close.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if input.KeyCode ~= Enum.KeyCode.Tab then return end
		if gameProcessed and UserInputService:GetFocusedTextBox() then return end
		MinimapUI.ToggleFullMap(true)
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.Tab then MinimapUI.ToggleFullMap(false) end
	end)

	-- Listen for DungeonMapData remote from server
	local mapRemote = Network.GetRemoteEvent(Network.Remotes.DungeonMapData)
	mapRemote.OnClientEvent:Connect(function(mapData: any)
		print("[MinimapUI] Received updated Dungeon Map Payload from server!")
		renderMap(mapData)
	end)

	startTrackingLoop()
	print("[MinimapUI] Top-Left Minimap Overlay initialized successfully.")
end

function MinimapUI.SetVisible(visible: boolean)
	if gui then
		gui.Enabled = visible
	end
	if not visible then
		MinimapUI.ToggleFullMap(false)
	end
end

return MinimapUI
