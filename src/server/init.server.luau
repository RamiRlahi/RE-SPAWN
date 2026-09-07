local ClassManager      = require(script:WaitForChild("ClassManager"))
local PlayerManager     = require(script:WaitForChild("PlayerManager"))
local WeaponManager     = require(script:WaitForChild("WeaponManager"))
local AnimationManager  = require(script:WaitForChild("AnimationManager"))
local SkillManager      = require(script:WaitForChild("SkillManager"))
local DungeonGenerator  = require(script:WaitForChild("DungeonGenerator"))

print("[Server] Initializing SoloProject Game Server...")

ClassManager.Init()
PlayerManager.Init()
WeaponManager.Init()
AnimationManager.Init()
SkillManager.Init()

-- Generate initial procedural roguelite dungeon
task.spawn(function()
	DungeonGenerator.Generate({
		totalRooms = 9,
		minRoomTiles = 5,
		maxRoomTiles = 8,
		branchProbability = 0.45,
	})
end)

-- When a player confirms their class, equip their weapon, apply dungeon lighting and teleport into dungeon spawn
ClassManager.OnClassSelected(function(player: Player, classId: string)
	WeaponManager.EquipWeapon(player, classId)

	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Shared = ReplicatedStorage:FindFirstChild("Shared")
	if Shared then
		local AtmosphereManager = require(Shared:FindFirstChild("AtmosphereManager") :: ModuleScript)
		AtmosphereManager.ApplyDungeonLighting()
	end

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
			char:PivotTo(spawnCF)
			print(`[Server] Teleported {player.Name} to Dungeon Spawn room`)
		else
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

print("[Server] Game Server initialized successfully. Ready for players.")
