--[[
	WeaponManager
	Equips class weapons using Roblox's native Tool Grip system.

	Key Features:
	  1. Uses Roblox's built-in Tool Grip configured with Tool Grip Editor.
	  2. Welds loose MeshParts / BaseParts inside the Tool to Handle via WeldConstraint
	     so multi-part weapons (like Greatsword with a MeshPart blade) follow the Handle.
	  3. Humanoid:EquipTool() equips the tool natively and waits for Roblox's RightGrip weld.
	  4. Leaves RightGrip untouched without custom CFrame overrides.
	  5. Disables collisions (CanCollide = false, Massless = true) to prevent physics glitches.
	  6. Sets up the SlashTrail for melee swings.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- ─────────────────────────────────────────────────────────────────────────────
-- Configuration
-- ─────────────────────────────────────────────────────────────────────────────
local WEAPON_CONFIG: { [string]: { toolName: string } } = {
	heavy_knight = {
		toolName = "Greatsword",
	},
}

local WeaponManager = {}

-- ── helpers ───────────────────────────────────────────────────────────────────

-- Disable CanCollide and set Massless on every BasePart inside a tool.
local function disableCollision(root: Instance)
	if root:IsA("BasePart") then
		(root :: BasePart).CanCollide = false
		(root :: BasePart).Massless   = true
	end
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless   = true
		end
	end
end

-- Weld every BasePart in the tool (except Handle) TO the Handle.
-- This ensures that any MeshPart geometry parented to the Tool/Handle
-- stays locked to the Handle when equipped in the character's hand.
local function weldLoosePartsToHandle(tool: Tool, handle: BasePart)
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") and part ~= handle then
			-- Skip if already welded to something.
			local alreadyWelded = false
			for _, w in ipairs(part:GetChildren()) do
				if w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("Motor6D") then
					alreadyWelded = true
					break
				end
			end
			if not alreadyWelded then
				for _, w in ipairs(handle:GetChildren()) do
					if (w:IsA("Weld") or w:IsA("WeldConstraint"))
						and ((w :: Weld).Part0 == part or (w :: Weld).Part1 == part) then
						alreadyWelded = true
						break
					end
				end
			end

			if not alreadyWelded then
				local wc      = Instance.new("WeldConstraint")
				wc.Part0      = handle
				wc.Part1      = part :: BasePart
				wc.Parent     = handle
				print(`[WeaponManager]   Welded loose part '{part.Name}' ({part.ClassName}) to Handle`)
			end
		end
	end
end

local function findWeaponTemplate(name: string): Instance?
	local targetName = string.lower(name)
	local exact = ReplicatedStorage:FindFirstChild(name)
		or ReplicatedStorage:FindFirstChild(name, true)
	if exact then return exact end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local inAssets = assets:FindFirstChild(name) or assets:FindFirstChild(name, true)
		if inAssets then return inAssets end
	end

	for _, child in ipairs(ReplicatedStorage:GetDescendants()) do
		if string.lower(child.Name) == targetName then
			return child
		end
	end
	for _, child in ipairs(ReplicatedStorage:GetDescendants()) do
		local lower = string.lower(child.Name)
		if (child:IsA("Tool") or child:IsA("Model") or child:IsA("BasePart")) and (string.find(lower, "greatsword") or string.find(lower, "great_sword")) then
			return child
		end
	end
	return nil
end

-- ── main equip ────────────────────────────────────────────────────────────────

function WeaponManager.EquipWeapon(player: Player, classId: string)
	local config = WEAPON_CONFIG[classId]
	if not config then
		print(`[WeaponManager] No weapon config for '{classId}' — skipping.`)
		return
	end

	print(`[WeaponManager] Equipping weapon '{config.toolName}' for {player.Name}`)

	local character = player.Character
	if not character then
		warn("[WeaponManager] No character found.")
		return
	end

	-- 1. Remove any old tool or equipped weapon copies in character or backpack
	local oldEquipped = character:FindFirstChild("EquippedWeapon")
	if oldEquipped then oldEquipped:Destroy() end
	local oldCharTool = character:FindFirstChild(config.toolName)
	if oldCharTool then oldCharTool:Destroy() end
	local oldBackpackTool = player.Backpack:FindFirstChild(config.toolName)
	if oldBackpackTool then oldBackpackTool:Destroy() end

	-- 2. Fetch tool template directly from ReplicatedStorage
	local toolTemplate = findWeaponTemplate(config.toolName)

	if not toolTemplate then
		warn(`[WeaponManager] ❌ Tool '{config.toolName}' not found in ReplicatedStorage!`)
		for _, child in ipairs(ReplicatedStorage:GetChildren()) do
			warn(`   RS Child: "{child.Name}" ({child.ClassName})`)
		end
		return
	end

	print(`[WeaponManager] Found weapon template: '{toolTemplate:GetFullName()}' ({toolTemplate.ClassName})`)

	-- 3. Clone Tool
	local tool = toolTemplate:Clone()
	if not tool:IsA("Tool") then
		local innerTool = tool:FindFirstChildWhichIsA("Tool")
		if innerTool then
			tool = innerTool
		end
	end

	disableCollision(tool)

	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if not handle then
		handle = tool:FindFirstChildWhichIsA("BasePart")
	end

	-- 4. Verify & weld loose MeshParts/BaseParts to Handle
	if handle and tool:IsA("Tool") then
		weldLoosePartsToHandle(tool, handle)
	end

	-- 5. Equip Tool natively using Humanoid:EquipTool() and wait for RightGrip
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		warn(`[WeaponManager] No humanoid found on character {character.Name}`)
		tool.Parent = character
	else
		tool.Parent = player.Backpack
		humanoid:EquipTool(tool)

		-- Wait for Roblox to generate RightGrip using Tool Grip Editor configuration
		local rightLimb = character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm")
		if rightLimb then
			local grip = rightLimb:WaitForChild("RightGrip", 2)
			if grip then
				print(`[WeaponManager] RightGrip successfully created on {rightLimb.Name} for {tool.Name}`)
			else
				print(`[WeaponManager] RightGrip not immediately in limb, checking character hierarchy...`)
				local charGrip = character:FindFirstChild("RightGrip", true)
				if charGrip then
					print(`[WeaponManager] Found RightGrip inside {charGrip.Parent.Name}`)
				end
			end
		end
	end

	print(`[WeaponManager] Successfully equipped Tool '{config.toolName}' via Humanoid:EquipTool for {player.Name}`)

	-- 6. Setup sword swing trail
	local bladeMesh: BasePart = handle or tool:FindFirstChildWhichIsA("BasePart")
	if bladeMesh then
		for _, part in ipairs(tool:GetDescendants()) do
			if (part:IsA("MeshPart") or part:IsA("BasePart")) and part ~= handle and part.Size.Magnitude > (handle and handle.Size.Magnitude or 0) then
				bladeMesh = part
				break
			end
		end

		local startAtt: Attachment? = nil
		local endAtt: Attachment? = nil

		for _, desc in ipairs(tool:GetDescendants()) do
			if desc:IsA("Attachment") then
				local lower = string.lower(desc.Name)
				if string.find(lower, "start") or lower == "att0" or lower == "attachment0" or lower == "d1" or lower == "base" or lower == "hilt" then
					startAtt = desc
				elseif string.find(lower, "end") or lower == "att1" or lower == "attachment1" or lower == "d2" or lower == "tip" then
					endAtt = desc
				end
			end
		end

		if not startAtt or not endAtt or (startAtt.Position - endAtt.Position).Magnitude < 0.5 then
			local sz = bladeMesh.Size
			local halfY = sz.Y * 0.5
			local halfZ = sz.Z * 0.5
			local halfX = sz.X * 0.5

			local offsetStart = Vector3.new(0, -halfY * 0.7, 0)
			local offsetEnd = Vector3.new(0, halfY * 1.3, 0)

			if sz.Z > sz.Y and sz.Z > sz.X then
				offsetStart = Vector3.new(0, 0, -halfZ * 0.7)
				offsetEnd = Vector3.new(0, 0, halfZ * 1.3)
			elseif sz.X > sz.Y and sz.X > sz.Z then
				offsetStart = Vector3.new(-halfX * 0.7, 0, 0)
				offsetEnd = Vector3.new(halfX * 1.3, 0, 0)
			end

			if not startAtt then
				startAtt = Instance.new("Attachment")
				startAtt.Name = "AttachmentStart"
				startAtt.Parent = bladeMesh
			end
			startAtt.Position = offsetStart

			if not endAtt then
				endAtt = Instance.new("Attachment")
				endAtt.Name = "AttachmentEnd"
				endAtt.Parent = bladeMesh
			end
			endAtt.Position = offsetEnd
		else
			if startAtt.Parent == endAtt.Parent then
				local bladeVec = endAtt.Position - startAtt.Position
				if bladeVec.Magnitude > 0.1 then
					local bladeDir = bladeVec.Unit
					endAtt.Position = endAtt.Position + bladeDir * 1.8
					startAtt.Position = startAtt.Position - bladeDir * 0.4
				end
			end
		end

		local trail = tool:FindFirstChild("SlashTrail", true)
		if not trail or not trail:IsA("Trail") then
			trail = Instance.new("Trail")
			trail.Name = "SlashTrail"
			trail.Parent = bladeMesh
		end

		trail.Attachment0 = startAtt
		trail.Attachment1 = endAtt
		trail.Texture = "rbxassetid://11395089850"
		trail.TextureMode = Enum.TextureMode.Stretch
		trail.Lifetime = 0.65
		trail.MinLength = 0.01
		trail.MaxLength = 0
		trail.FaceCamera = true
		trail.LightEmission = 1
		trail.LightInfluence = 0
		trail.WidthScale = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1.5),
			NumberSequenceKeypoint.new(0.65, 1.2),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		trail.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 230)),
			ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 200, 60)),
			ColorSequenceKeypoint.new(0.65, Color3.fromRGB(255, 100, 15)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 20, 0)),
		})
		trail.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.75, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		trail.Enabled = false
	end

	print(`[WeaponManager] Weapon '{config.toolName}' successfully ready for {player.Name}`)
end

-- ── respawn ───────────────────────────────────────────────────────────────────

function WeaponManager.Init()
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(1.5)
			local classId = player:GetAttribute("SelectedClass")
			if classId then
				WeaponManager.EquipWeapon(player, classId)
			end
		end)
	end)
end

return WeaponManager
