local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local TomeController = require(script:WaitForChild("TomeController"))
local VariantFX = require(script:WaitForChild("VariantFX"))

local player = Players.LocalPlayer
local StarterGui = game:GetService("StarterGui")

print("[Client] Initializing SoloProject Client...")

-- Every word in the Arcade font (but the map's), from the start.
do
	local ok, err = pcall(function() require(script:WaitForChild("FontStyle")).Init() end)
	if not ok then warn("[Client] FontStyle failed:", err) end
end

-- The loading screen first: it covers the start-up, loads the sky-kingdom
-- menu scene, and keeps it loaded (rebuilding it if it ever goes missing).
pcall(function()
	require(script:WaitForChild("MenuLoader")).Init()
end)

TomeController.Init()
VariantFX.Init() -- recolours ability VFX with each player's equipped VFX variant
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("PurgeScreen")).Init()
end)
pcall(function()
	require(script:WaitForChild("WingsMounts")).Init() -- everyone's wings and mounts, built and animated here
end)
do
	local ok, err = pcall(function()
		require(script:WaitForChild("MountController")).Init() -- B to ride; thrown off (and tumbling) when hit
	end)
	if not ok then warn("[Client] MountController failed:", err) end
end
pcall(function()
	require(script:WaitForChild("SummonAnnouncer")).Init() -- others' Legendary wishes: a banner + a beam on them
end)

-- Disable default Roblox Backpack UI
task.spawn(function()
	local maxAttempts = 20
	local attempts = 0
	while attempts < maxAttempts do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if success then
			print("[Client] Default Backpack UI disabled successfully.")
			break
		end
		attempts += 1
		task.wait(0.2)
	end
end)

-- Safely require UIManager
local successUI, UIManager = pcall(function()
	return require(script:WaitForChild("UI"):WaitForChild("UIManager"))
end)

if not successUI then
	warn("[Client ERROR] Failed to load UIManager:", UIManager)
end

-- Safely require LobbyCamera
local successCam, LobbyCamera = pcall(function()
	return require(script:WaitForChild("LobbyCamera"))
end)

if not successCam then
	warn("[Client ERROR] Failed to load LobbyCamera:", LobbyCamera)
end

if successCam and LobbyCamera then
	pcall(function()
		LobbyCamera.Start()
	end)
end

-- Safely require IsometricCamera
local successIso, IsometricCamera = pcall(function()
	return require(script:WaitForChild("IsometricCamera"))
end)

if not successIso then
	warn("[Client ERROR] Failed to load IsometricCamera:", IsometricCamera)
end

-- Safely require TorchLightController
local successTorch, TorchLightController = pcall(function()
	return require(script:WaitForChild("TorchLightController"))
end)

if successTorch and TorchLightController then
	pcall(function()
		TorchLightController.Start()
	end)
end

-- Safely require SkillController
local successSkill, SkillController = pcall(function()
	return require(script:WaitForChild("SkillController"))
end)

if successSkill and SkillController then
	pcall(function()
		SkillController.Init()
	end)
else
	warn("[Client ERROR] Failed to load SkillController:", SkillController)
end

-- Safely require RoomFX (special-room motion, reward pop-ups, gold counter)

-- Pops the character back onto the floor if it ever gets stuck in geometry.
pcall(function()
	require(script:WaitForChild("SafeMove")).Init()
end)

-- Hades-style "boon acquired" sparkle when anyone picks a tome.
pcall(function()
	require(script:WaitForChild("BoonSparkle")).Init()
end)

-- The dragon boss: its animation, fire, health bar and the shield minigame.
pcall(function()
	require(script:WaitForChild("DragonBossFX")).Init()
end)

-- The other bosses: intro cinematic, signature moves, the Fallen Angel's pillars.
pcall(function()
	require(script:WaitForChild("BossCinematic")).Init()
end)

-- The Fallen Angel's body in motion (hovering, its sword arm, wings, halo,
-- cloth), and the pictures of its attacks.
pcall(function()
	require(script:WaitForChild("FallenAngelFX")).Init()
end)
pcall(function()
	require(script:WaitForChild("AngelAttackFX")).Init()
end)
-- Cloth capes on every Sword Master and armored Fire Knight in the world.
pcall(function()
	require(script:WaitForChild("ClassCapes")).Init()
	require(script:WaitForChild("EnemyProjectiles")).Init()
	require(script:WaitForChild("ZombieAnimator")).Init()
	require(script:WaitForChild("VfxDetail")).Init()
	require(script:WaitForChild("PerfMode")).Init() -- low frame rate: shadows and scenery effects off
	require(script:WaitForChild("PrisonFX")).Init() -- the prison map's searchlights and alarm
	-- The lobby: party panel, invite prompts, its menu states.
	require(script:WaitForChild("UI"):WaitForChild("LobbyHUD")).Init(if successUI then UIManager else nil)
end)

-- Menu and lobby music.
pcall(function()
	require(script:WaitForChild("MusicController")).Init()
end)

-- The Armory (gear you wear) and the loot toasts.
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("Armory")).Init()
end)

-- Evolutions: the banner when one happens, and the Build Codex.
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("BuildCodex")).Init()
end)

-- The end-of-run summary (stats, rewards, loot, the party).
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("RunSummary")).Init()
end)

-- Horde events: the countdown, the red light.
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("HordeHUD")).Init()
end)

-- Corruption: the meter, the collapse.
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("CorruptionHUD")).Init()
end)

-- The count at the floor's exit (everyone in before the run goes down).
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("FloorPortalHUD")).Init()
end)

-- "Left click to interact" bubble + prompt near a ready room reward.
pcall(function()
	require(script:WaitForChild("UI"):WaitForChild("EmblemPrompt")).Init()
end)

local successRoomFX, RoomFX = pcall(function()
	return require(script:WaitForChild("RoomFX"))
end)

if successRoomFX and RoomFX then
	pcall(function()
		RoomFX.Init()
	end)
else
	warn("[Client ERROR] Failed to load RoomFX:", RoomFX)
end

if successUI and UIManager then
	local successInit, err = pcall(function()
		UIManager.Init(function(selectedClassId: string)
			local classInfo = ClassData.GetClass(selectedClassId)
			local className = classInfo and classInfo.name or selectedClassId
			print(`[Client] Entering sanctuary as {className}...`)
		end)
	end)

	if not successInit then
		warn("[Client ERROR] UIManager.Init failed:", err)
	end

	-- Death screen: respawn / main menu, or spectate / leave in co-op.
	local okDeath, DeathScreen = pcall(function()
		return require(script:WaitForChild("UI"):WaitForChild("DeathScreen"))
	end)
	if okDeath and DeathScreen then
		DeathScreen.Init({
			onMenu = function()
				if successIso and IsometricCamera then IsometricCamera.Stop() end
				UIManager.ReturnToMenu()
			end,
		})
	else
		warn("[Client ERROR] Failed to load DeathScreen:", DeathScreen)
	end

	local classConfirmedRemote = Network.GetRemoteEvent(Network.Remotes.ClassConfirmed)
	classConfirmedRemote.OnClientEvent:Connect(function(confirmedClassId: string)
		local classInfo = ClassData.GetClass(confirmedClassId)
		local className = classInfo and classInfo.name or confirmedClassId
		print(`[Client] Class confirmed by server: {className}`)

		UIManager.FadeOutToGame(function()
			if successCam and LobbyCamera then
				LobbyCamera.StopImmediate()
			end
			if successIso and IsometricCamera then
				IsometricCamera.Start(1.2)
			end
		end)
	end)
end

print("[Client] SoloProject Client bootstrap complete.")
