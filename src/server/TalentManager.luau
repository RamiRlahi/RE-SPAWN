--[[
	TalentManager.luau
	Souls and class talent trees (see shared TalentData). Stored in the shared
	PlayerData profile (profile.souls, profile.unlocked).

	  • Souls: bosses give BOSS_SOULS; every KILLS_PER_SOUL kills gives 1;
	    every floor cleared (going down to the next) gives FLOOR_SOULS; all
	    × the run's difficulty mode's reward (MapData.MODES). The gacha also
	    grants souls (refined Soul Shards).
	  • UnlockTalent (client → server) is fully validated here.
	  • GetEffects(player, classId) feeds PlayerStats at the start of a run.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local TalentData = require(Shared:WaitForChild("TalentData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local RunStats = require(script.Parent:WaitForChild("RunStats"))

local TalentManager = {}

-- (raised so the talent trees fill in at a better pace: a node costs 1-6)
local BOSS_SOULS = 10
local KILLS_PER_SOUL = 3
local FLOOR_SOULS = 3

local killCounters: { [Player]: number } = {}

local function sync(player: Player)
	local p = PlayerData.Get(player)
	if not p then return end
	player:SetAttribute("Souls", p.souls)
	Network.GetRemoteEvent(Network.Remotes.TalentState):FireClient(player, {
		souls = p.souls,
		unlocked = p.unlocked,
	})
end
TalentManager.Sync = sync

function TalentManager.AwardSouls(player: Player, amount: number)
	local p = PlayerData.Get(player)
	if not p or amount <= 0 then return end
	p.souls += amount
	RunStats.Add(player, "souls", amount)
	sync(player)
	PlayerData.MarkDirty(player)
end

-- Called by MobManager for every player credited with a kill (`mult`: the
-- run's difficulty mode's reward; a kill counts that much toward a soul).
function TalentManager.OnMobKilled(player: Player, isBoss: boolean, mult: number?)
	local m = mult or 1
	if isBoss then
		TalentManager.AwardSouls(player, math.floor(BOSS_SOULS * m + 0.5))
		return
	end
	local count = (killCounters[player] or 0) + m
	local souls = math.floor(count / KILLS_PER_SOUL)
	killCounters[player] = count - souls * KILLS_PER_SOUL
	if souls > 0 then TalentManager.AwardSouls(player, souls) end
end

-- A floor cleared: the party goes down to the next (DungeonGenerator.NextLevel).
function TalentManager.OnFloorCleared(player: Player, mult: number?)
	TalentManager.AwardSouls(player, math.floor(FLOOR_SOULS * (mult or 1) + 0.5))
end

-- Unlocked talent effects for a class (applied by PlayerStats each run).
function TalentManager.GetEffects(player: Player, classId: string): { any }
	local out = {}
	local p = PlayerData.Get(player)
	local owned = p and p.unlocked[classId]
	if not owned then return out end
	for nodeId in pairs(owned) do
		local node = TalentData.GetNode(classId, nodeId)
		if node then table.insert(out, node.effect) end
	end
	return out
end

local function tryUnlock(player: Player, classId: any, nodeId: any): boolean
	if typeof(classId) ~= "string" or typeof(nodeId) ~= "string" then return false end
	local p = PlayerData.Get(player)
	local node = TalentData.GetNode(classId, nodeId)
	if not p or not node then return false end
	local owned = p.unlocked[classId] or {}
	if owned[nodeId] then return false end
	if node.requires and not owned[node.requires] then return false end
	if p.souls < node.cost then return false end
	p.souls -= node.cost
	owned[nodeId] = true
	p.unlocked[classId] = owned
	sync(player)
	PlayerData.MarkDirty(player)
	return true
end

function TalentManager.Init()
	Network.GetRemoteEvent(Network.Remotes.UnlockTalent).OnServerEvent:Connect(function(player, payload)
		if typeof(payload) ~= "table" then return end
		if not tryUnlock(player, payload.classId, payload.nodeId) then
			sync(player) -- resync so the UI never shows a stale state
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.RequestTalents).OnServerEvent:Connect(function(player)
		sync(player)
	end)
	PlayerData.OnLoaded(function(player)
		sync(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		killCounters[player] = nil
	end)
	print("[TalentManager] initialized.")
end

return TalentManager
