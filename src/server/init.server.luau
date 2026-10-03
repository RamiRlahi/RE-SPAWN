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
DifficultyManager.Reset()

-- Generate initial procedural roguelite dungeon
task.spawn(function()
	DungeonGenerator.Generate({
		totalRooms = 18,
		minRoomTiles = 9,
		maxRoomTiles = 13,
		branchProbability = 0.8,
	})
end)

-- When a player confirms their class, equip their weapon and teleport into
-- the dungeon spawn. (The dim dungeon lighting is applied on that player's
-- client when they enter — MenuBackdrop — so players still in the menus keep
-- theirs.)
-- A run in progress: anyone (else) alive in the dungeon.
local function othersInRun(player: Player): boolean
	for _, p in ipairs(game:GetService("Players"):GetPlayers()) do
		if p ~= player and p:GetAttribute("InLobby") == false and p:GetAttribute("IsDead") ~= true then
			return true
		end
	end
	return false
end

-- Whether anyone has played the current dungeon yet (it's fresh at start-up).
local dungeonUsed = false

ClassManager.OnClassSelected(function(player: Player, classId: string)
	-- Every new run (first entry, a retry after dying, PLAY again from the
	-- menu) gets a brand-new dungeon, unless others are still playing this
	-- one (then you join them).
	if dungeonUsed and not othersInRun(player) then
		-- A fresh run: Threat, time survived and the level start over.
		DifficultyManager.Reset()
		local ok, err = pcall(function()
			DungeonGenerator.Generate({
				seed = os.time() + math.random(1, 100000),
				totalRooms = 18,
				minRoomTiles = 9,
				maxRoomTiles = 13,
				branchProbability = 0.8,
			})
		end)
		if not ok then warn("[Server] New run dungeon failed:", err) end
	end
	dungeonUsed = true
	WeaponManager.EquipWeapon(player, classId)

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:FindFirstChild("Shared")

	local char = player.Character
	if char then
		local spawnCF = DungeonGenerator.GetSpawnCFrame()
		if spawnCF == CFrame.identity then
			for _ = 1, 15 do
				task.wait(0.2)
				spawnCF = DungeonGenerator.GetSpawnCFrame()
				if spawnCF ~= CFrame.identity then break end
			end
		end

		if spawnCF ~= CFrame.identity then
			task.wait(0.2)
			char:PivotTo(spawnCF + Vector3.new(0, 2, 0))
			player:SetAttribute("SpawnedInMap", true)
			player:SetAttribute("InLobby", false)
			print(`[Server] Teleported {player.Name} to Dungeon Spawn room`)
		else
			player:SetAttribute("SpawnedInMap", true)
			player:SetAttribute("InLobby", false)
			warn(`[Server WARNING] Spawn CFrame not ready for {player.Name}`)
		end

		if Shared then
			local AtmosphereManager = require(Shared:FindFirstChild("AtmosphereManager") :: ModuleScript)
			AtmosphereManager.AttachTorchLight(char)
		end
	end

	-- Send active dungeon minimap payload to spawning player
	local payload = DungeonGenerator.GetMapPayload()
	if payload then
		local ReplicatedStorage = game:GetService("ReplicatedStorage")
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		if Shared then
			local Network = require(Shared:FindFirstChild("Network") :: ModuleScript)
			local mapRemote = Network.GetRemoteEvent(Network.Remotes.DungeonMapData)
			mapRemote:FireClient(player, payload)
		end
	end
end)

-- The whole party gave up (or left): the run is over. Back to Threat 0 and
-- the clock stopped right away; the next PLAY builds a fresh dungeon at level 1.
local Players = game:GetService("Players")
local function endRunIfEmpty()
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InLobby") == false then return end
	end
	DifficultyManager.Reset()
end
local function watchRun(p: Player)
	p:GetAttributeChangedSignal("InLobby"):Connect(function()
		if p:GetAttribute("InLobby") == true then endRunIfEmpty() end
	end)
end
for _, p in ipairs(Players:GetPlayers()) do watchRun(p) end
Players.PlayerAdded:Connect(watchRun)
Players.PlayerRemoving:Connect(function() task.defer(endRunIfEmpty) end)

print("[Server] Game Server initialized successfully. Ready for players.")
