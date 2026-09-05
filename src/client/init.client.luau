local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClassData = require(Shared:WaitForChild("ClassData"))

local player = Players.LocalPlayer

print("[Client] Initializing SoloProject Client...")

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
