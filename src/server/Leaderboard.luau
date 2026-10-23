--!strict
--[[
	Leaderboard.luau
	A player's bests as attributes, for the map picker: BestFloor (the
	deepest floor reached in any dungeon; a map with `unlockFloor` opens on
	it). Synced when their data loads and after every run (RunStats).
--]]

local Players = game:GetService("Players")

local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local Leaderboard = {}

local function syncBests(player: Player)
	local p = PlayerData.Get(player) :: any
	local r = p and p.records or {}
	player:SetAttribute("BestFloor", r.bestFloor or 0)
end
Leaderboard.SyncBests = syncBests

function Leaderboard.Init()
	PlayerData.OnLoaded(function(player: Player) syncBests(player) end)
	for _, p in ipairs(Players:GetPlayers()) do
		if PlayerData.Get(p) then syncBests(p) end
	end
end

return Leaderboard
