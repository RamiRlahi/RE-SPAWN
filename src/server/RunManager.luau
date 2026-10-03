--!strict
--[[
	RunManager.luau
	Every party's run is its own: its own dungeon (built in its own slot of the
	world, so runs never overlap), map, Threat clock, levels and revives.

	  RunManager.Start(players, mapId)   a new run for these players (a party
	                                     leaving the campfire): its dungeon is
	                                     built, then each is sent in
	  RunManager.RunOf(player)           the run a player is in (or nil)
	  RunManager.SpawnFor(player)        where they enter it

	A player's run is the "RunId" attribute; the run's shared state is its
	RunScope folder. Once nobody in it is still in the dungeon (all gave up,
	left, or went back to the lobby) the run is torn down and its slot freed.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RunScope = require(Shared:WaitForChild("RunScope"))
local MapData = require(Shared:WaitForChild("MapData"))
local DungeonGenerator = require(script.Parent:WaitForChild("DungeonGenerator"))
local DifficultyManager = require(script.Parent:WaitForChild("DifficultyManager"))

local RunManager = {}

type Run = { id: string, mapId: string, slot: number, ready: boolean }
local runs: { [string]: Run } = {}

-- The lowest slot no run is using.
local function freeSlot(): number
	local used: { [number]: boolean } = {}
	for _, r in pairs(runs) do used[r.slot] = true end
	local i = 0
	while used[i] do i += 1 end
	return i
end

function RunManager.RunOf(player: Player): string?
	local id = player:GetAttribute("RunId")
	return if typeof(id) == "string" and runs[id] then id else nil
end

function RunManager.MapOf(runId: string?): string
	local r = runId and runs[runId]
	return if r then r.mapId else MapData.DEFAULT
end

-- Make a run on `mapId` for `players` and build its first level. Yields until
-- its dungeon is ready. Returns the run id.
function RunManager.Start(players: { Player }, mapId: string?): string
	local id = "run_" .. string.sub(HttpService:GenerateGUID(false), 1, 8)
	local map = MapData.Get(mapId) or MapData.Get(MapData.DEFAULT)
	local run: Run = { id = id, mapId = (map :: any).id, slot = freeSlot(), ready = false }
	runs[id] = run
	RunScope.Create(id)
	RunScope.Set(id, "MapId", run.mapId)
	for _, p in ipairs(players) do
		if p.Parent then p:SetAttribute("RunId", id) end
	end
	DifficultyManager.Reset(id)
	local ok, err = pcall(function()
		DungeonGenerator.Generate({
			runId = id,
			slot = run.slot,
			mapId = run.mapId,
			level = 1,
			seed = os.time() + math.random(1, 100000),
			totalRooms = 18,
			minRoomTiles = 9,
			maxRoomTiles = 13,
			branchProbability = 0.8,
		})
	end)
	if not ok then warn("[RunManager] Building run " .. id .. " failed:", err) end
	run.ready = true
	print(`[RunManager] Run {id} started on {run.mapId} (slot {run.slot}) for {#players} player(s).`)
	return id
end

-- Where `player` enters their run's dungeon (identity if it isn't ready).
function RunManager.SpawnFor(player: Player): CFrame
	local id = RunManager.RunOf(player)
	if not id then return CFrame.identity end
	local r = runs[id]
	local t0 = os.clock()
	while r and not r.ready and os.clock() - t0 < 20 do task.wait(0.1) end
	return DungeonGenerator.GetSpawnCFrame(id)
end

-- Tear a run down once nobody is left playing it.
local function endIfEmpty(id: string)
	if not runs[id] then return end
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("RunId") == id and p:GetAttribute("InLobby") == false then return end
	end
	runs[id] = nil
	DungeonGenerator.Forget(id)
	DifficultyManager.Forget(id)
	RunScope.Destroy(id)
	print(`[RunManager] Run {id} ended.`)
end

function RunManager.Init()
	local function watch(p: Player)
		-- Back in the lobby (gave up, left, quit): out of the run; the run
		-- ends when its last player is out. (Deferred: the death screen tells
		-- the spectators first.)
		p:GetAttributeChangedSignal("InLobby"):Connect(function()
			if p:GetAttribute("InLobby") ~= true then return end
			local id = p:GetAttribute("RunId")
			task.defer(function()
				if p.Parent and p:GetAttribute("InLobby") == true then p:SetAttribute("RunId", nil) end
				if typeof(id) == "string" then endIfEmpty(id) end
			end)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		local id = p:GetAttribute("RunId")
		if typeof(id) == "string" then task.defer(endIfEmpty, id) end
	end)
end

return RunManager
