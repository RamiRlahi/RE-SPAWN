local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local AtmosphereManager = require(Shared:WaitForChild("AtmosphereManager"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local ClassManager = require(script.Parent:WaitForChild("ClassManager"))
local AnimationManager = require(script.Parent:WaitForChild("AnimationManager"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))
local ClassArmor = require(Shared:WaitForChild("ClassArmor"))
local IceCape = require(Shared:WaitForChild("IceCape"))

-- Class armor (the Ice Mage's is its cape) is a summon reward: without it the
-- character keeps its own avatar (the weapon is equipped by WeaponManager).
local function equipClassArmor(character: Model, classId: string)
	local player = Players:GetPlayerFromCharacter(character)
	if not player or player:GetAttribute(`Armor_{classId}`) ~= true then return end
	ClassArmor.Equip(character, classId)
	if classId == "ice_mage" then
		IceCape.Attach(character)
	end
end


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
			local classInfo = ClassData.GetClass(selectedClass)
			local maxHp = (classInfo and classInfo.stats and classInfo.stats.maxHealth) or 100
			humanoid.MaxHealth = maxHp
			humanoid.Health = maxHp
			task.spawn(equipClassArmor, character, selectedClass)
		end
		rootPart.Anchored = false
		humanoid.WalkSpeed = 16
		humanoid.JumpPower = 50
			humanoid.JumpHeight = 7.2
			PlayerStats.RefreshCharacter(player)
	end
end


function PlayerManager.Init()
	AtmosphereManager.ApplyLobbyLighting()

	-- Settings are saved on each player's account (PlayerData), so they follow
	-- them to any server and device. Checked here (SettingsConfig.Sanitize):
	-- only known settings of the right type are kept.
	local lastSave: { [Player]: number } = {}
	Players.PlayerRemoving:Connect(function(p) lastSave[p] = nil end)
	local saveSettingsRemote = Network.GetRemoteEvent(Network.Remotes.SaveSettings)
	saveSettingsRemote.OnServerEvent:Connect(function(player: Player, clientSettings: any)
		if typeof(clientSettings) ~= "table" then return end
		local now = os.clock()
		if now - (lastSave[player] or 0) < 0.5 then return end
		lastSave[player] = now
		local profile = PlayerData.Await(player, 10)
		if not profile then return end
		profile.settings = SettingsConfig.Sanitize(clientSettings) :: any
		PlayerData.MarkDirty(player)
	end)
	-- The client asks for its saved settings as it starts.
	local syncRemote = Network.GetRemoteEvent(Network.Remotes.SettingsSync)
	syncRemote.OnServerEvent:Connect(function(player: Player)
		local profile = PlayerData.Await(player, 15)
		if not profile or not player.Parent then return end
		local saved = if next(profile.settings) ~= nil then SettingsConfig.Sanitize(profile.settings) else nil
		syncRemote:FireClient(player, saved)
	end)

	-- Handle sprint toggle from client
	local setSprintRemote = Network.GetRemoteEvent(Network.Remotes.SetSprint)
	setSprintRemote.OnServerEvent:Connect(function(player: Player, sprinting: any)
		if typeof(sprinting) ~= "boolean" then return end
		if player:GetAttribute("InLobby") == true then return end
		player:SetAttribute("IsSprinting", sprinting)

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			if humanoid and humanoid.Health > 0 then
				local baseSpeed = PlayerStats.GetStat(player, "movementSpeed")
				humanoid.WalkSpeed = sprinting and baseSpeed * (34 / 16) or baseSpeed
			end
		end
	end)

	-- The upper body's turn to the cursor (AimStance): onto the character, for
	-- everyone else's client to pose it with.
	Network.GetRemoteEvent(Network.Remotes.AimTwist).OnServerEvent:Connect(function(player: Player, twist: any)
		if typeof(twist) ~= "number" or twist ~= twist then return end
		local character = player.Character
		if not character then return end
		character:SetAttribute("AimTwist", math.floor(math.clamp(twist, -1.8, 1.8) * 100 + 0.5) / 100)
	end)

	-- Handle attack from client
	local performAttackRemote = Network.GetRemoteEvent(Network.Remotes.PerformAttack)
	performAttackRemote.OnServerEvent:Connect(function(player: Player, attackData: any)
		if player:GetAttribute("InLobby") == true then return end
		local character = player.Character
		if not character then return end
		if character:GetAttribute("IsSkill1Active") == true or character:GetAttribute("IsSpinAttackActive") == true then return end
		print(`[PlayerManager] {player.Name} performed attack:`, attackData)
	end)

	-- Handle player joining
	Players.PlayerAdded:Connect(function(player: Player)
		player:SetAttribute("InLobby", true)
		player:SetAttribute("SpawnedInMap", false)

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

		local character = player.Character
		if character then
			local humanoid = character:FindFirstChildOfClass("Humanoid")
			local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?

			if rootPart then
				rootPart.Anchored = false
			end
			if humanoid then
				local classInfo = ClassData.GetClass(classId)
				local maxHp = (classInfo and classInfo.stats and classInfo.stats.maxHealth) or 100
				humanoid.MaxHealth = maxHp
				humanoid.Health = maxHp
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end

			-- Equip permanent server-side armor
			equipClassArmor(character, classId)
		end
		PlayerStats.StartRun(player)


		print(`[PlayerManager] {player.Name} successfully entered the game as {classId}`)
	end)
end

return PlayerManager

