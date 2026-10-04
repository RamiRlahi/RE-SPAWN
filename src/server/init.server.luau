local ClassManager      = require(script:WaitForChild("ClassManager"))
local PlayerManager     = require(script:WaitForChild("PlayerManager"))
local WeaponManager     = require(script:WaitForChild("WeaponManager"))
local AnimationManager  = require(script:WaitForChild("AnimationManager"))
local SkillManager      = require(script:WaitForChild("SkillManager"))
local DungeonGenerator  = require(script:WaitForChild("DungeonGenerator"))
local MobManager        = require(script:WaitForChild("MobManager"))
local PlayerStats       = require(script:WaitForChild("PlayerStats"))
local AllyManager      = require(script:WaitForChild("AllyManager"))
local DifficultyManager = require(script:WaitForChild("DifficultyManager"))
local PlayerData        = require(script:WaitForChild("PlayerData"))
local TalentManager     = require(script:WaitForChild("TalentManager"))
local GachaManager      = require(script:WaitForChild("GachaManager"))
local PartyManager      = require(script:WaitForChild("PartyManager"))
local DeathManager      = require(script:WaitForChild("DeathManager"))
local CampfireManager   = require(script:WaitForChild("CampfireManager"))
local AccountManager    = require(script:WaitForChild("AccountManager"))
local RunManager        = require(script:WaitForChild("RunManager"))
local LobbyManager      = require(script:WaitForChild("LobbyManager"))

print("[Server] Initializing SoloProject Game Server...")

ClassManager.Init()
PlayerStats.Init()
TalentManager.Init()
GachaManager.Init()
PartyManager.Init()
CampfireManager.Init()
DeathManager.Init()
AccountManager.Init()
PlayerData.Init() -- after the systems above have registered their OnLoaded hooks
PlayerManager.Init()
WeaponManager.Init()
AnimationManager.Init()
SkillManager.Init()
MobManager.Init()
require(script:WaitForChild("Hazards")).Init()
AllyManager.Init()
RunManager.Init()
LobbyManager.Init()
local RunStats = require(script:WaitForChild("RunStats"))
RunStats.Init()
require(script:WaitForChild("LootManager")).Init()
require(script:WaitForChild("MountManager")).Init() -- riding mounts in the lobby
require(script:WaitForChild("Corruption")).Init()
require(script:WaitForChild("Horde")).Init()
require(script:WaitForChild("Leaderboard")).Init()
require(script:WaitForChild("DevHooks")).Init() -- (Studio only)

-- Sent into the dungeon (the campfire's portal, ClassManager.Enter): into
-- their run's dungeon (RunManager: every party's run is its own), weapon in
-- hand. Someone arriving with no run gets one of their own.
ClassManager.OnClassSelected(function(player: Player, classId: string)
	if not RunManager.RunOf(player) then
		local mapId = player:GetAttribute("LobbyMap")
		RunManager.Start({ player }, if typeof(mapId) == "string" then mapId else nil)
	end
	local runId = RunManager.RunOf(player)
	if runId then RunStats.Begin(player, runId) end
	WeaponManager.EquipWeapon(player, classId)

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:FindFirstChild("Shared")

	local char = player.Character
	if char then
		local spawnCF = RunManager.SpawnFor(player)
		-- (streaming: the dungeon around the spawn before they land in it)
		if spawnCF ~= CFrame.identity then
			pcall(function() player:RequestStreamAroundAsync(spawnCF.Position, 6) end)
		end
		task.wait(0.2)
		if spawnCF ~= CFrame.identity then
			char:PivotTo(spawnCF + Vector3.new(0, 2, 0))
		else
			warn(`[Server WARNING] Spawn CFrame not ready for {player.Name}`)
		end
		player:SetAttribute("SpawnedInMap", true)
		player:SetAttribute("InLobby", false)
		print(`[Server] Sent {player.Name} into run {runId}`)
	end

	-- Their run's minimap
	local payload = DungeonGenerator.GetMapPayload(runId)
	if payload and Shared then
		local Network = require(Shared:FindFirstChild("Network") :: ModuleScript)
		Network.GetRemoteEvent(Network.Remotes.DungeonMapData):FireClient(player, payload)
	end
end)

print("[Server] Game Server initialized successfully. Ready for players.")
