local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local ClassManager = require(script.Parent:WaitForChild("ClassManager"))
local AnimationManager = require(script.Parent:WaitForChild("AnimationManager"))

local PlayerManager = {}

local DEFAULT_CHURCH_SPAWN_CRAME = CFrame.new(0, 5, 0)

local function getChurchSpawnCFrame(): CFrame
	local churchSpawn = Workspace:FindFirstChild("ChurchSpawn", true)
	if churchSpawn and churchSpawn:IsA("BasePart") then
		return churchSpawn.CFrame + Vector3.new(0, 3, 0)
	end
	
	local spawnLocation = Workspace:FindFirstChildWhichIsA("SpawnLocation", true)
	if spawnLocation then
		return spawnLocation.CFrame + Vector3.new(0, 3, 0)
	end

	return DEFAULT_CHURCH_SPAWN_CRAME
end

local function setupCharacter(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	local rootPart = character:WaitForChild("HumanoidRootPart", 10) :: BasePart?

	if not humanoid or not rootPart then return end

	local inLobby = player:GetAttribute("InLobby")
	if inLobby == nil or inLobby == true then
		-- Position in church / lobby
		local spawnCF = getChurchSpawnCFrame()
		character:PivotTo(spawnCF)

		-- Lock movement while in login/lobby menu
		humanoid.WalkSpeed = 0
		humanoid.JumpPower = 0
		humanoid.JumpHeight = 0
		rootPart.Anchored = true
	else
		-- Already picked class (e.g. respawn)
		local selectedClass = player:GetAttribute("SelectedClass")
		if selectedClass then
			character:SetAttribute("Class", selectedClass)
		end
		rootPart.Anchored = false
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
		humanoid.JumpHeight = 7.2
	end
end

function PlayerManager.Init()
	-- Listen for settings save from client
	local saveSettingsRemote = Network.GetRemoteEvent(Network.Remotes.SaveSettings)
	saveSettingsRemote.OnServerEvent:Connect(function(player: Player, clientSettings: any)
		if typeof(clientSettings) == "table" then
			print(`[PlayerManager] Saved settings updated for {player.Name}`)
		end
	end)

	-- Handle sprint toggle from client
	local setSprintRemote = Network.GetRemoteEvent(Network.Remotes.SetSprint)
	setSprintRemote.OnServerEvent:Connect(function(player: Player, sprinting: any)
		if typeof(sprinting) ~= "boolean" then return end
		if player:GetAttribute("InLobby") == true then return end

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				humanoid.WalkSpeed = sprinting and 26 or 16
			end
		end
	end)

	-- Handle player joining
	Players.PlayerAdded:Connect(function(player: Player)
		player:SetAttribute("InLobby", true)

		player.CharacterAdded:Connect(function(character)
			setupCharacter(player, character)
		end)

		if player.Character then
			setupCharacter(player, player.Character)
		end
	end)

	-- Handle character removal or player leaving
	Players.PlayerRemoving:Connect(function(player: Player)
		print(`[PlayerManager] {player.Name} left the game.`)
	end)

	-- Listen for class selection completion
	ClassManager.OnClassSelected(function(player: Player, classId: string)
		player:SetAttribute("InLobby", false)

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

			if rootPart then
				rootPart.Anchored = false
			end
			if humanoid then
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end
		end

		print(`[PlayerManager] {player.Name} successfully entered the game as {classId}`)
	end)
end

return PlayerManager
