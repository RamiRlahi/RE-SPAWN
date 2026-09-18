local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local AtmosphereManager = require(Shared:WaitForChild("AtmosphereManager"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local ClassManager = require(script.Parent:WaitForChild("ClassManager"))
local AnimationManager = require(script.Parent:WaitForChild("AnimationManager"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))


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

	-- Attach player torch light & embers, and visual outline
	AtmosphereManager.AttachTorchLight(character)
	AtmosphereManager.AttachCharacterOutline(character)

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

	-- Handle attack from client
	local performAttackRemote = Network.GetRemoteEvent(Network.Remotes.PerformAttack)
	performAttackRemote.OnServerEvent:Connect(function(player: Player, attackData: any)
		if player:GetAttribute("InLobby") == true then return end
		local character = player.Character
		if not character then return end
		if character:GetAttribute("IsSkill1Active") == true or character:GetAttribute("IsSpinAttackActive") == true then return end
		print(`[PlayerManager] {player.Name} performed attack:`, attackData)

		if false and character:GetAttribute("IsMissileBuffActive") == true then
			local successMod, SkillManager = pcall(function()
				return require(script.Parent:WaitForChild("SkillManager"))
			end)
			if successMod and SkillManager and SkillManager.HandleMissileAttack then
				SkillManager.HandleMissileAttack(player, character)
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

-- Maps armor piece name -> R6 body part name it should be welded to
local ARMOR_WELD_MAP: { [string]: string } = {
	chestplate              = "Torso",
	gauntlet_heavyknight    = "Left Arm",
	leftarm_heavyknight     = "Left Arm",
	rightarm_heavyknight    = "Right Arm",
	heavyknight_BELT        = "Torso",
	leftleg                 = "Left Leg",
	rightleg                = "Right Leg",
	Accessory               = "Torso",
	Cape                    = "Torso",
	cape                    = "Torso",
	RangerCloak             = "Torso",
}

local ROT270 = CFrame.Angles(0, math.rad(270), 0)
local ROT90 = CFrame.Angles(0, math.rad(90), 0)


local ARMOR_CFRAME_OFFSETS: { [string]: CFrame } = {
	chestplate              = ROT270 * CFrame.new(0, 0, 0),
	gauntlet_heavyknight    = ROT90 * CFrame.new(0, 0, 0),
	leftarm_heavyknight     = ROT270 * CFrame.new(0, -0.2, 0),
	rightarm_heavyknight    = ROT270 * CFrame.new(0, -0.2, 0),
	heavyknight_BELT        = ROT270 * CFrame.new(0, -1.9, 0),
	leftleg                 = ROT270 * CFrame.Angles(0, 0, math.rad(10)) * CFrame.new(-0.1, 0, 0),
	rightleg                = ROT270 * CFrame.Angles(0, 0, math.rad(10)) * CFrame.new(-0.1, 0, 0),
	Accessory               = CFrame.new(0, -0.5, 1), -- Pushed outward so cape drapes OVER the armor
	Cape                    = ROT270 * CFrame.new(0, 0, 1),
	cape                    = ROT270 * CFrame.new(0, 0, 1),
	RangerCloak             = ROT90 * CFrame.new(0, 0, 0),
}


local ARMOR_SCALE = 1

local ARMOR_PIECE_SCALES: { [string]: number } = {
	leftleg  = 1.08, -- Slightly enlarged to fit over boots cleanly
	rightleg = 1.08,
}


local function scaleArmorPiece(piece: Instance, scale: number)
	if scale == 1 then return end
	if piece:IsA("Model") then
		local pivot = piece:GetPivot()
		for _, part in ipairs(piece:GetDescendants()) do
			if part:IsA("BasePart") then
				local relative = pivot:ToObjectSpace(part.CFrame)
				local scaledPos = relative.Position * scale
				local rot = relative - relative.Position
				part.Size *= scale
				part.CFrame = pivot * CFrame.new(scaledPos) * rot
			end
		end
	elseif piece:IsA("Accessory") then
		local handle = piece:FindFirstChild("Handle")
		if handle and handle:IsA("BasePart") then
			handle.Size *= scale
		end
	elseif piece:IsA("BasePart") then
		piece.Size *= scale
	end
end


local function weldArmorPiece(piece: Model | BasePart, targetPart: BasePart, pieceName: string)
	local pieceScale = ARMOR_PIECE_SCALES[pieceName] or ARMOR_SCALE
	scaleArmorPiece(piece, pieceScale)

	local parts: { BasePart } = {}
	if piece:IsA("BasePart") then
		table.insert(parts, piece)
	elseif piece:IsA("Model") then
		for _, desc in ipairs(piece:GetDescendants()) do
			if desc:IsA("BasePart") then
				table.insert(parts, desc)
			end
		end
	end

	if #parts == 0 then return end

	local offset = ARMOR_CFRAME_OFFSETS[pieceName] or CFrame.identity

	local pieceCFrame: CFrame
	if piece:IsA("Model") then
		local cf, _ = piece:GetBoundingBox()
		pieceCFrame = cf
	else
		pieceCFrame = piece.CFrame
	end

	local targetCF = targetPart.CFrame * offset
	local transform = targetCF * pieceCFrame:Inverse()

	for _, part in ipairs(parts) do
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Massless = true
		part.Anchored = false
		part.CFrame = transform * part.CFrame

		local weld = Instance.new("WeldConstraint")
		weld.Name = "ArmorWeld"
		weld.Part0 = targetPart
		weld.Part1 = part
		weld.Parent = part
	end
end


local ENABLE_CLASS_ARMOR = true

local function equipClassArmor(character: Model, classId: string)
	if not ENABLE_CLASS_ARMOR then return end

	local CLASS_ARMOR_FOLDERS = {
		heavy_knight = "heavy knight armor",
		ranger = "Ranger armor",
	}

	local folderName = CLASS_ARMOR_FOLDERS[classId]
	if not folderName then return end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local classes = assets and assets:FindFirstChild("Classes")
	local armorFolder = classes and classes:FindFirstChild(folderName)
	if not armorFolder then return end

	-- Position each armor piece individually on its target limb
	for _, piece in ipairs(armorFolder:GetChildren()) do
		if piece:IsA("Tool") then
			continue
		end

		print(`[ArmorEquip] Processing armor piece: "{piece.Name}" (ClassName: {piece.ClassName})`)
		local clone = piece:Clone()


		-- Scale first
		local pieceScale = ARMOR_PIECE_SCALES[piece.Name] or ARMOR_SCALE
		scaleArmorPiece(clone, pieceScale)

		-- RangerCloak has an authored "root" part. Align that root to the
		-- character root (with a small visual drop) instead of centering the
		-- whole model on the torso.
		local cloakRoot: BasePart? = nil
		local rootAlignedCloak = classId == "ranger" and piece.Name == "RangerCloak"
		if rootAlignedCloak then
			local foundRoot = clone:FindFirstChild("root", true)
			if foundRoot and foundRoot:IsA("BasePart") then
				cloakRoot = foundRoot
			else
				warn("[ArmorEquip] RangerCloak needs a BasePart named 'root'.")
				clone:Destroy()
				continue
			end
		end

		-- Determine target R6 limb
		local targetPartName = ARMOR_WELD_MAP[piece.Name] or "Torso"
		local targetPart = character:FindFirstChild(targetPartName) :: BasePart?
		if not targetPart then
			clone.Parent = character
			continue
		end

		-- Get the rotation offset for this piece
		local rotOffset = rootAlignedCloak and CFrame.new(0, 0.15, 0) or (ARMOR_CFRAME_OFFSETS[piece.Name] or CFrame.identity)

		-- Get the bounding box center of this piece
		local pieceCF: CFrame
		if rootAlignedCloak and cloakRoot then
			pieceCF = cloakRoot.CFrame
		elseif clone:IsA("Model") then
			pieceCF = clone:GetBoundingBox()
		elseif clone:IsA("Accessory") then
			local handle = clone:FindFirstChild("Handle") :: BasePart?
			if handle then
				pieceCF = handle.CFrame
			else
				pieceCF = CFrame.identity
			end
		elseif clone:IsA("BasePart") then
			pieceCF = clone.CFrame
		else
			clone.Parent = character
			continue
		end

		-- Snap the piece center to the limb center with rotation
		local targetCF = targetPart.CFrame * rotOffset
		local transform = targetCF * pieceCF:Inverse()

		-- Apply transform to all parts
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.CanTouch = false
				desc.CanQuery = false
				desc.Massless = true
				desc.Anchored = false
				desc.CFrame = transform * desc.CFrame
			end
		end
		if clone:IsA("BasePart") then
			local bp = clone :: BasePart
			bp.CanCollide = false
			bp.CanTouch = false
			bp.CanQuery = false
			bp.Massless = true
			bp.Anchored = false
			bp.CFrame = transform * bp.CFrame
		end

		clone.Parent = character

		-- Weld every BasePart in this piece to the target limb
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				local weld = Instance.new("WeldConstraint")
				weld.Name = "ArmorWeld"
				weld.Part0 = targetPart
				weld.Part1 = desc
				weld.Parent = desc
			end
		end
		if clone:IsA("BasePart") then
			local weld = Instance.new("WeldConstraint")
			weld.Name = "ArmorWeld"
			weld.Part0 = targetPart
			weld.Part1 = clone :: BasePart
			weld.Parent = clone
		end
	end

end



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

