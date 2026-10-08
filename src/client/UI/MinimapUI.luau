--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- MinimapUI.luau
-- Top-Left Semi-Transparent Dungeon Map Overlay for SoloProject Roguelite
--   • a check mark over every room you've cleared (the run's ClearedRooms)
--   • your teammates in the run as little avatar icons (greyed while down)
-- ─────────────────────────────────────────────────────────────────────────────

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local TweenService      = game:GetService("TweenService")

local Shared  = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))

local MinimapUI = {}

local player = Players.LocalPlayer
local gui: ScreenGui? = nil
local containerFrame: Frame? = nil
local mapCanvas: Frame? = nil
local playerDot: Frame? = nil
local playerArrow: ImageLabel? = nil

local activeMapData: any = nil
local tileFrames: { [string]: Frame } = {}
local roomChecks: { [number]: { check: Frame, tiles: { Frame } } } = {}
local mateIcons: { [Player]: ImageLabel } = {}
local headshots: { [number]: string } = {}
local CHECK_GREEN = Color3.fromRGB(120, 255, 140)
local roomTypeColors = {
	Start    = Color3.fromRGB(46, 204, 113),   -- Emerald Green
	Combat   = Color3.fromRGB(74, 105, 189),   -- Steel Blue
	Treasure = Color3.fromRGB(241, 196, 15),   -- Gold
	Shop     = Color3.fromRGB(230, 126, 34),   -- Amber
	Elite    = Color3.fromRGB(155, 89, 182),   -- Purple
	Event    = Color3.fromRGB(52, 152, 219),   -- Light Blue
	Boss     = Color3.fromRGB(231, 76, 60),    -- Crimson
	Cursed   = Color3.fromRGB(170, 70, 230),   -- Dark Violet
	Purge    = Color3.fromRGB(200, 60, 80),    -- Ember Red
}

local MAP_SCALE = 3.2 -- pixels per 12-stud floor tile

local refreshCleared: () -> ()
local refreshMates: () -> ()
local lastCleared: string? = nil

-- ── UI Construction ──────────────────────────────────────────────────────────

local function createMinimapGui()
	local playerGui = player:WaitForChild("PlayerGui")
	local existing = playerGui:FindFirstChild("DungeonMinimapGui")
	if existing then existing:Destroy() end

	local screenGui = Instance.new("ScreenGui")
	screenGui.Name = "DungeonMinimapGui"
	screenGui.ResetOnSpawn = false
	screenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screenGui.Parent = playerGui
	gui = screenGui

	-- Top-Left Container Frame
	local container = Instance.new("Frame")
	container.Name = "MinimapContainer"
	container.Size = UDim2.new(0, 175, 0, 175)
	container.Position = UDim2.new(0, 20, 0, 20)
	container.BackgroundColor3 = Color3.fromRGB(12, 16, 24)
	container.BackgroundTransparency = 0.35 -- Semi-transparent overlay
	container.ClipsDescendants = true
	container.Parent = screenGui
	containerFrame = container

	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 16)
	corner.Parent = container

	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(100, 210, 255)
	stroke.Transparency = 0.45
	stroke.Thickness = 2
	stroke.Parent = container

	-- Header Title Label
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "MapTitle"
	titleLabel.Size = UDim2.new(1, 0, 0, 20)
	titleLabel.Position = UDim2.new(0, 0, 0, 4)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Text = "DUNGEON MAP"
	titleLabel.TextColor3 = Color3.fromRGB(180, 225, 255)
	titleLabel.TextTransparency = 0.2
	titleLabel.Font = Enum.Font.GothamBold
	titleLabel.TextSize = 10
	titleLabel.ZIndex = 5
	titleLabel.Parent = container

	-- Map Canvas (Translates as player moves)
	local canvas = Instance.new("Frame")
	canvas.Name = "MapCanvas"
	canvas.Size = UDim2.new(1, 0, 1, 0)
	canvas.Position = UDim2.new(0.5, 0, 0.5, 0)
	canvas.BackgroundTransparency = 1
	canvas.Parent = container
	mapCanvas = canvas

	-- Player Marker Frame (Centered in container)
	local marker = Instance.new("Frame")
	marker.Name = "PlayerMarker"
	marker.Size = UDim2.new(0, 10, 0, 10)
	marker.Position = UDim2.new(0.5, -5, 0.5, -5)
	marker.BackgroundColor3 = Color3.fromRGB(255, 230, 80)
	marker.ZIndex = 10
	marker.Parent = container

	local markerCorner = Instance.new("UICorner")
	markerCorner.CornerRadius = UDim.new(1, 0)
	markerCorner.Parent = marker

	local markerStroke = Instance.new("UIStroke")
	markerStroke.Color = Color3.fromRGB(255, 255, 255)
	markerStroke.Thickness = 1.5
	markerStroke.Parent = marker
	playerDot = marker

	-- Direction Arrow Indicator
	local arrow = Instance.new("ImageLabel")
	arrow.Name = "DirectionArrow"
	arrow.Size = UDim2.new(0, 16, 0, 16)
	arrow.Position = UDim2.new(0.5, -8, 0.5, -8)
	arrow.BackgroundTransparency = 1
	arrow.Image = "rbxassetid://6034818372" -- Direction pointer arrow
	arrow.ImageColor3 = Color3.fromRGB(255, 230, 80)
	arrow.ZIndex = 11
	arrow.Parent = container
	playerArrow = arrow
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
	for _, rc in pairs(roomChecks) do rc.check:Destroy() end
	table.clear(roomChecks)

	if not mapData or not mapData.grid then return end

	-- Room Type Color lookup map by cell
	local roomColorGrid: { [string]: Color3 } = {}
	if mapData.rooms then
		for _, room in ipairs(mapData.rooms) do
			local col = roomTypeColors[room.roomType] or Color3.fromRGB(74, 105, 189)
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
			
			local tileColor = roomColorGrid[key] or Color3.fromRGB(50, 65, 85)
			tileFrame.BackgroundColor3 = tileColor
			tileFrame.BackgroundTransparency = 0.35 -- Semi-transparent room tiles
			tileFrame.BorderSizePixel = 0
			tileFrame.Parent = mapCanvas

			tileFrames[key] = tileFrame
		end
	end

	-- A check mark over each room, shown once it's cleared (its tiles dim too).
	for _, room in ipairs(mapData.rooms or {}) do
		if typeof(room.id) ~= "number" then continue end
		local size = math.clamp(math.min(room.w, room.d) * MAP_SCALE * 0.55, 12, 22)
		local check = Instance.new("Frame")
		check.Name = `Cleared_{room.id}`
		check.AnchorPoint = Vector2.new(0.5, 0.5)
		check.Size = UDim2.fromOffset(size, size)
		check.Position = UDim2.fromOffset((room.gx + room.w / 2) * MAP_SCALE, (room.gz + room.d / 2) * MAP_SCALE)
		check.BackgroundTransparency = 1
		check.ZIndex = 6
		check.Visible = false
		check.Parent = mapCanvas
		-- (drawn from two bars, a short one and a long one, meeting at the bottom)
		for _, bar in ipairs({
			{ len = 0.42, x = 0.3, y = 0.62, rot = 45 },
			{ len = 0.78, x = 0.6, y = 0.48, rot = -50 },
		}) do
			local b = Instance.new("Frame")
			b.AnchorPoint = Vector2.new(0.5, 0.5)
			b.Size = UDim2.new(bar.len, 0, 0, math.max(2, size * 0.16))
			b.Position = UDim2.fromScale(bar.x, bar.y)
			b.Rotation = bar.rot
			b.BackgroundColor3 = CHECK_GREEN
			b.BorderSizePixel = 0
			b.ZIndex = 6
			b.Parent = check
			local st = Instance.new("UIStroke")
			st.Color = Color3.fromRGB(10, 30, 14)
			st.Thickness = 1
			st.Parent = b
		end
		local tiles = {}
		for rx = room.gx, room.gx + room.w - 1 do
			for rz = room.gz, room.gz + room.d - 1 do
				local t = tileFrames[`{rx}_{rz}`]
				if t then table.insert(tiles, t) end
			end
		end
		roomChecks[room.id] = { check = check, tiles = tiles }
	end
	lastCleared = nil -- (show the checks again for the new map)
end

-- ── Cleared rooms ────────────────────────────────────────────────────────────
refreshCleared = function()
	local list = RunScope.Mine("ClearedRooms")
	local s = if typeof(list) == "string" then list else "|"
	if s == lastCleared then return end
	lastCleared = s
	for id, rc in pairs(roomChecks) do
		local done = string.find(s, `|{id}|`, 1, true) ~= nil
		if rc.check.Visible ~= done then
			rc.check.Visible = done
			for _, t in ipairs(rc.tiles) do t.BackgroundTransparency = if done then 0.6 else 0.35 end
		end
	end
end

-- ── Teammates ────────────────────────────────────────────────────────────────
-- Everyone else in your run, as a round avatar icon where they stand.
local function headshot(userId: number): string
	local got = headshots[userId]
	if got then return got end
	headshots[userId] = "" -- (one request at a time)
	task.spawn(function()
		local ok, img = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size48x48)
		end)
		headshots[userId] = if ok then img else ""
		for p, icon in pairs(mateIcons) do
			if p.UserId == userId and icon.Parent then icon.Image = headshots[userId] end
		end
	end)
	return ""
end

local function mateIcon(p: Player): ImageLabel
	local icon = mateIcons[p]
	if icon and icon.Parent then return icon end
	local img = Instance.new("ImageLabel")
	img.Name = `Mate_{p.UserId}`
	img.AnchorPoint = Vector2.new(0.5, 0.5)
	img.Size = UDim2.fromOffset(16, 16)
	img.BackgroundColor3 = Color3.fromRGB(40, 60, 90)
	img.Image = headshot(p.UserId)
	img.ZIndex = 9
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(1, 0)
	c.Parent = img
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(110, 220, 255)
	st.Thickness = 1.5
	st.Parent = img
	img.Parent = mapCanvas
	mateIcons[p] = img
	return img
end

refreshMates = function()
	if not mapCanvas or not activeMapData then return end
	local tileSize = activeMapData.tileSize or 12
	local myRun = player:GetAttribute("RunId")
	local seen: { [Player]: boolean } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p == player or myRun == nil or p:GetAttribute("RunId") ~= myRun or p:GetAttribute("InLobby") ~= false then continue end
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then continue end -- (streamed out: far away on the map)
		seen[p] = true
		local icon = mateIcon(p)
		local pos = root.Position / tileSize
		icon.Position = UDim2.fromOffset(pos.X * MAP_SCALE, pos.Z * MAP_SCALE)
		local down = p:GetAttribute("IsDead") == true
		icon.ImageTransparency = if down then 0.6 else 0
		local st = icon:FindFirstChildOfClass("UIStroke")
		if st then st.Color = if down then Color3.fromRGB(150, 150, 150) else Color3.fromRGB(110, 220, 255) end
	end
	for p, icon in pairs(mateIcons) do
		if not seen[p] then
			icon:Destroy()
			mateIcons[p] = nil
		end
	end
end

-- ── Real-Time Tracking Loop ──────────────────────────────────────────────────

local function startTrackingLoop()
	-- (checks and teammates a few times a second; the map follows you every frame)
	local nextSlow = 0
	RunService.RenderStepped:Connect(function()
		if os.clock() >= nextSlow and mapCanvas and activeMapData then
			nextSlow = os.clock() + 0.25
			refreshCleared()
			refreshMates()
		end
		if not player.Character or not mapCanvas or not activeMapData then return end
		local rootPart = player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not rootPart then return end

		-- Convert World Position to Grid Coordinates
		local worldPos = rootPart.Position
		local tileSize = activeMapData.tileSize or 12
		local gx = worldPos.X / tileSize
		local gz = worldPos.Z / tileSize

		-- Offset Map Canvas so Player stays centered in top-left minimap frame
		local canvasX = -gx * MAP_SCALE
		local canvasZ = -gz * MAP_SCALE
		mapCanvas.Position = UDim2.new(0.5, canvasX, 0.5, canvasZ)

		-- Rotate Direction Arrow matching character LookVector
		local camera = workspace.CurrentCamera
		if camera and playerArrow then
			local lookVec = rootPart.CFrame.LookVector
			local angle = math.deg(math.atan2(-lookVec.X, -lookVec.Z))
			playerArrow.Rotation = angle
		end
	end)
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- The map only shows inside the dungeon (never in the lobby or sanctuary).
local function refreshVisible()
	if gui then gui.Enabled = player:GetAttribute("InLobby") == false end
end

function MinimapUI.Init()
	createMinimapGui()
	refreshVisible()
	player:GetAttributeChangedSignal("InLobby"):Connect(refreshVisible)

	-- Listen for DungeonMapData remote from server
	local mapRemote = Network.GetRemoteEvent(Network.Remotes.DungeonMapData)
	mapRemote.OnClientEvent:Connect(function(mapData: any)
		print("[MinimapUI] Received updated Dungeon Map Payload from server!")
		renderMap(mapData)
	end)

	startTrackingLoop()
	print("[MinimapUI] Top-Left Minimap Overlay initialized successfully.")
end

return MinimapUI
