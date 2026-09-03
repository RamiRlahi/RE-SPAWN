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
			task.spawn(equipClassArmor, character, selectedClass)
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
}

local ROT270 = CFrame.Angles(0, math.rad(270), 0)
local ROT90 = CFrame.Angles(0, math.rad(90), 0)


local ARMOR_CFRAME_OFFSETS: { [string]: CFrame } = {
	chestplate              = ROT270 * CFrame.new(0, 0, 0),
	gauntlet_heavyknight    = ROT90 * CFrame.new(0, 0, 0),
	leftarm_heavyknight     = ROT270 * CFrame.new(0, -0.2, 0),
	rightarm_heavyknight    = ROT270 * CFrame.new(0, -0.2, 0),
	heavyknight_BELT        = ROT270 * CFrame.new(0, -1.9, 0),
	leftleg                 = ROT270 * CFrame.new(-0.5, 0, 0), -- 1 stud forward
	rightleg                = ROT270 * CFrame.new(-0.5, 0, 0), -- 1 stud forward
	Accessory               = CFrame.new(0, -0.5, 1), -- Pushed outward so cape drapes OVER the armor
	Cape                    = ROT270 * CFrame.new(0, 0, 1),
	cape                    = ROT270 * CFrame.new(0, 0, 1),
}


local ARMOR_SCALE = 1


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
	scaleArmorPiece(piece, ARMOR_SCALE)

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
		part.CFrame = transform * part.CFrame

		local weld = Instance.new("WeldConstraint")
		weld.Name = "ArmorWeld"
		weld.Part0 = targetPart
		weld.Part1 = part
		weld.Parent = part
	end
end


local function equipClassArmor(character: Model, classId: string)
	local CLASS_ARMOR_FOLDERS = {
		heavy_knight = "heavy knight armor",
	}

	local folderName = CLASS_ARMOR_FOLDERS[classId]
	if not folderName then return end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local classes = assets and assets:FindFirstChild("Classes")
	local armorFolder = classes and classes:FindFirstChild(folderName)
	if not armorFolder then return end

	-- Position each armor piece individually on its target limb
	for _, piece in ipairs(armorFolder:GetChildren()) do
		print(`[ArmorEquip] Processing armor piece: "{piece.Name}" (ClassName: {piece.ClassName})`)
		local clone = piece:Clone()


		-- Scale first
		scaleArmorPiece(clone, ARMOR_SCALE)

		-- Determine target R6 limb
		local targetPartName = ARMOR_WELD_MAP[piece.Name] or "Torso"
		local targetPart = character:FindFirstChild(targetPartName) :: BasePart?
		if not targetPart then
			clone.Parent = character
			continue
		end

		-- Get the rotation offset for this piece
		local rotOffset = ARMOR_CFRAME_OFFSETS[piece.Name] or CFrame.identity

		-- Get the bounding box center of this piece
		local pieceCF: CFrame
		if clone:IsA("Model") then
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
				desc.CFrame = transform * desc.CFrame
			end
		end
		if clone:IsA("BasePart") then
			local bp = clone :: BasePart
			bp.CanCollide = false
			bp.CanTouch = false
			bp.CanQuery = false
			bp.Massless = true
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
				humanoid.WalkSpeed = 16
				humanoid.JumpPower = 50
				humanoid.JumpHeight = 7.2
			end

			-- Equip permanent server-side armor
			equipClassArmor(character, classId)
		end


		print(`[PlayerManager] {player.Name} successfully entered the game as {classId}`)
	end)
end

return PlayerManager

