--!strict
--[[
	Leaderboard.luau
	The Hall of the Deep: the deepest floors reached in the Endless Abyss,
	every server's, kept in an OrderedDataStore. A board in the lobby plaza
	lists the top ten (refreshed every minute).

	  Leaderboard.Submit(player, floor)   an Endless run ended this deep
	  (and the BestFloor / BestEndless player attributes, for the map picker's lock)

	In Studio without API access the store isn't there: the board says so,
	and nothing breaks.
--]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local MapData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Leaderboard = {}

local STORE = "EndlessDeepest_v1"
local REFRESH = 60
local TOP = 10

local store: OrderedDataStore? = nil
pcall(function() store = DataStoreService:GetOrderedDataStore(STORE) end)

-- A player's bests, as attributes (the map picker locks the Endless Abyss on them).
local function syncBests(player: Player)
	local p = PlayerData.Get(player) :: any
	local r = p and p.records or {}
	player:SetAttribute("BestFloor", r.bestFloor or 0)
	player:SetAttribute("BestEndless", r.bestEndless or 0)
end
Leaderboard.SyncBests = syncBests

function Leaderboard.Submit(player: Player, floor: number)
	local p = PlayerData.Get(player) :: any
	if p then
		p.records = p.records or {}
		if floor > (p.records.bestEndless or 0) then
			p.records.bestEndless = floor
			PlayerData.MarkDirty(player)
		end
	end
	syncBests(player)
	local s = store
	if not s then return end
	local userId = player.UserId
	task.spawn(function()
		pcall(function()
			(s :: OrderedDataStore):UpdateAsync(tostring(userId), function(old: any)
				local o = tonumber(old) or 0
				return if floor > o then floor else nil
			end)
		end)
	end)
end

-- ── The board in the lobby ────────────────────────────────────────────────
local names: { [number]: string } = {}
local function nameOf(userId: number): string
	if names[userId] then return names[userId] end
	local ok, n = pcall(function() return Players:GetNameFromUserIdAsync(userId) end)
	names[userId] = if ok and typeof(n) == "string" then n else ("#" .. tostring(userId))
	return names[userId]
end

local function buildBoard(): Frame?
	local lobby = Workspace:WaitForChild("Lobby", 60)
	if not lobby then return nil end
	local C = MapData.LOBBY_CENTER
	local pos = C + Vector3.new(-26, 0, -34)
	local face = CFrame.lookAt(pos, Vector3.new(C.X, pos.Y, C.Z))
	local model = Instance.new("Model")
	model.Name = "HallOfTheDeep"
	local function part(props: { [string]: any }): BasePart
		local pt = Instance.new("Part")
		pt.Anchored = true
		pt.TopSurface = Enum.SurfaceType.Smooth
		pt.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props) do (pt :: any)[k] = v end
		pt.Parent = model
		return pt
	end
	for _, sx in ipairs({ -1, 1 }) do
		part({ Name = "Post", Size = Vector3.new(1.2, 13, 1.2), CFrame = face * CFrame.new(sx * 6.6, 6.5, 0), Color = Color3.fromRGB(34, 28, 40), Material = Enum.Material.Slate })
	end
	local board = part({ Name = "Board", Size = Vector3.new(12, 10, 0.5), CFrame = face * CFrame.new(0, 7.4, 0), Color = Color3.fromRGB(22, 14, 32), Material = Enum.Material.Slate })
	part({ Name = "Crest", Size = Vector3.new(13.4, 0.8, 1), CFrame = face * CFrame.new(0, 12.8, 0), Color = Color3.fromRGB(180, 90, 255), Material = Enum.Material.Neon, Transparency = 0.3 })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(180, 90, 255)
	light.Range = 18
	light.Brightness = 1.2
	light.Parent = board
	model.Parent = lobby
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.CanvasSize = Vector2.new(600, 500)
	sg.LightInfluence = 0
	sg.Parent = board
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 70)
	title.Font = Enum.Font.Antique
	title.TextScaled = true
	title.TextColor3 = Color3.fromRGB(210, 160, 255)
	title.Text = "HALL OF THE DEEP"
	title.Parent = sg
	local sub = title:Clone()
	sub.Position = UDim2.fromOffset(0, 66)
	sub.Size = UDim2.new(1, 0, 0, 26)
	sub.TextColor3 = Color3.fromRGB(235, 225, 210)
	sub.Text = "Deepest floors in the Endless Abyss"
	sub.Parent = sg
	local list = Instance.new("Frame")
	list.Name = "Rows"
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(30, 104)
	list.Size = UDim2.new(1, -60, 1, -114)
	list.Parent = sg
	return list
end

local function refresh(list: Frame)
	for _, c in ipairs(list:GetChildren()) do c:Destroy() end
	local rows: { { name: string, floor: number } } = {}
	local s = store
	local ok = false
	if s then
		ok = pcall(function()
			local pages = (s :: OrderedDataStore):GetSortedAsync(false, TOP)
			for _, entry in ipairs(pages:GetCurrentPage()) do
				table.insert(rows, { name = nameOf(tonumber(entry.key) or 0), floor = entry.value })
			end
		end)
	end
	local function row(i: number, left: string, right: string, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(0, (i - 1) * 36)
		l.Size = UDim2.new(1, 0, 0, 34)
		l.Font = Enum.Font.Antique
		l.TextScaled = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color
		l.Text = left
		l.Parent = list
		local r = l:Clone()
		r.TextXAlignment = Enum.TextXAlignment.Right
		r.Text = right
		r.Parent = list
	end
	if not ok then
		row(1, "The hall is sealed here (no data store).", "", Color3.fromRGB(170, 160, 150))
		return
	end
	if #rows == 0 then
		row(1, "No one has gone down yet. Be the first.", "", Color3.fromRGB(200, 190, 175))
		return
	end
	local medal = { Color3.fromRGB(255, 210, 90), Color3.fromRGB(215, 220, 230), Color3.fromRGB(220, 150, 90) }
	for i, r in ipairs(rows) do
		row(i, `{i}.  {r.name}`, `Floor {r.floor}`, medal[i] or Color3.fromRGB(235, 225, 210))
	end
end

function Leaderboard.Init()
	PlayerData.OnLoaded(function(player: Player) syncBests(player) end)
	for _, p in ipairs(Players:GetPlayers()) do
		if PlayerData.Get(p) then syncBests(p) end
	end
	task.spawn(function()
		local list = buildBoard()
		if not list then return end
		while true do
			pcall(refresh, list)
			task.wait(REFRESH)
		end
	end)
end

return Leaderboard
