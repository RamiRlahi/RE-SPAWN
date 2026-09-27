--[[
	TalentManager.luau
	Souls and class talent trees (see shared TalentData).

	  • Profile per player: { souls, unlocked = { [classId] = { [nodeId] = true } } },
	    saved to a DataStore (loaded on join; saved after changes, on leave and at
	    shutdown). If DataStores are unavailable (e.g. Studio without API access)
	    it warns and keeps progress in memory for the session.
	  • Souls: bosses give BOSS_SOULS; every KILLS_PER_SOUL kills gives 1.
	  • UnlockTalent (client → server) is fully validated here.
	  • GetEffects(player, classId) feeds PlayerStats at the start of a run.
--]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local TalentData = require(Shared:WaitForChild("TalentData"))

local TalentManager = {}

local STORE_NAME = "ClassTalents_v1"
local STARTING_SOULS = 3
local BOSS_SOULS = 6
local KILLS_PER_SOUL = 6
local SAVE_DEBOUNCE = 8

type Profile = { souls: number, unlocked: { [string]: { [string]: boolean } } }

local profiles: { [Player]: Profile } = {}
local killCounters: { [Player]: number } = {}
local dirty: { [Player]: boolean } = {}
local store: DataStore? = nil

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
	else
		warn("[TalentManager] DataStore unavailable — talents will not persist this session:", result)
	end
end

local function sync(player: Player)
	local p = profiles[player]
	if not p then return end
	player:SetAttribute("Souls", p.souls)
	Network.GetRemoteEvent(Network.Remotes.TalentState):FireClient(player, {
		souls = p.souls,
		unlocked = p.unlocked,
	})
end

local function save(player: Player)
	local p = profiles[player]
	if not p or not store then return end
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(`u_{player.UserId}`, p)
	end)
	if ok then
		dirty[player] = nil
	else
		warn("[TalentManager] Save failed for", player.Name, err)
	end
end

local function markDirty(player: Player)
	if dirty[player] then return end
	dirty[player] = true
	task.delay(SAVE_DEBOUNCE, function()
		if dirty[player] and player.Parent then save(player) end
	end)
end

local function load(player: Player)
	local data: any = nil
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return (store :: DataStore):GetAsync(`u_{player.UserId}`)
			end)
			if ok then
				data = result
				break
			end
			warn(`[TalentManager] Load attempt {attempt} failed for {player.Name}:`, result)
			task.wait(1)
		end
	end
	local profile: Profile = { souls = STARTING_SOULS, unlocked = {} }
	if typeof(data) == "table" then
		profile.souls = tonumber(data.souls) or STARTING_SOULS
		if typeof(data.unlocked) == "table" then
			for classId, nodes in pairs(data.unlocked) do
				if typeof(nodes) == "table" and TalentData.Get(classId) then
					profile.unlocked[classId] = {}
					for nodeId, v in pairs(nodes) do
						if v == true and TalentData.GetNode(classId, nodeId) then
							profile.unlocked[classId][nodeId] = true
						end
					end
				end
			end
		end
	end
	profiles[player] = profile
	sync(player)
end

function TalentManager.AwardSouls(player: Player, amount: number)
	local p = profiles[player]
	if not p or amount <= 0 then return end
	p.souls += amount
	sync(player)
	markDirty(player)
end

-- Called by MobManager for every player credited with a kill.
function TalentManager.OnMobKilled(player: Player, isBoss: boolean)
	if isBoss then
		TalentManager.AwardSouls(player, BOSS_SOULS)
		return
	end
	killCounters[player] = (killCounters[player] or 0) + 1
	if killCounters[player] >= KILLS_PER_SOUL then
		killCounters[player] = 0
		TalentManager.AwardSouls(player, 1)
	end
end

-- Unlocked talent effects for a class (applied by PlayerStats each run).
function TalentManager.GetEffects(player: Player, classId: string): { any }
	local out = {}
	local p = profiles[player]
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
	local p = profiles[player]
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
	markDirty(player)
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

	Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
	for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		killCounters[player] = nil
		dirty[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do save(player) end
	end)
	print("[TalentManager] initialized.")
end

return TalentManager
