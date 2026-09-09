--[[
	SkillManager.luau
	Server-authoritative combat skill execution, cooldown tracking, hitbox detection,
	and visual event replication.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SkillData = require(Shared:WaitForChild("SkillData"))

local SkillManager = {}

-- playerCooldowns[player][skillIndex] = lastCastTime
local playerCooldowns: { [Player]: { [number]: number } } = {}

-- Character visibility storage for skill 3 (Phoenix Dash invisibility)
local savedTransparencies: { [Model]: { [Instance]: number } } = {}

local function setCharacterVisibility(char: Model, visible: boolean)
	if not char then return end

	if not visible then
		local charSaved = savedTransparencies[char]
		if not charSaved then
			charSaved = {}
			savedTransparencies[char] = charSaved
		end

		for _, desc in ipairs(char:GetDescendants()) do
			if desc:IsA("BasePart") then
				if charSaved[desc] == nil then
					charSaved[desc] = desc.Transparency
				end
				desc.Transparency = 1
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				if charSaved[desc] == nil then
					charSaved[desc] = desc.Transparency
				end
				desc.Transparency = 1
			end
		end
	else
		local charSaved = savedTransparencies[char]
		if charSaved then
			for inst, origTrans in pairs(charSaved) do
				if inst and inst.Parent then
					inst.Transparency = origTrans
				end
			end
			savedTransparencies[char] = nil
		else
			for _, desc in ipairs(char:GetDescendants()) do
				if desc:IsA("BasePart") then
					if desc.Name == "HumanoidRootPart" then
						desc.Transparency = 1
					else
						desc.Transparency = 0
					end
				elseif desc:IsA("Decal") or desc:IsA("Texture") then
					desc.Transparency = 0
				end
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: Find all target humanoids in workspace (excluding caster)
-- ─────────────────────────────────────────────────────────────────────────────
local function getPotentialTargets(casterChar: Model): { { character: Model, humanoid: Humanoid, rootPart: BasePart } }
	local targets = {}
	
	for _, inst in ipairs(Workspace:GetChildren()) do
		if inst:IsA("Model") and inst ~= casterChar then
			local hum = inst:FindFirstChildOfClass("Humanoid")
			local root = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
			if hum and root and hum.Health > 0 then
				table.insert(targets, {
					character = inst,
					humanoid = hum,
					rootPart = root :: BasePart,
				})
			end
		end
	end

	-- Also check any subfolders like "Enemies" or "Dungeon" or "NPCs"
	for _, folder in ipairs(Workspace:GetDescendants()) do
		if folder:IsA("Folder") or folder:IsA("Model") then
			for _, inst in ipairs(folder:GetChildren()) do
				if inst:IsA("Model") and inst ~= casterChar and not table.find(targets, inst) then
					local hum = inst:FindFirstChildOfClass("Humanoid")
					local root = inst:FindFirstChild("HumanoidRootPart") or inst.PrimaryPart
					if hum and root and hum.Health > 0 then
						-- Ensure we haven't already included this character
						local alreadyAdded = false
						for _, entry in ipairs(targets) do
							if entry.character == inst then
								alreadyAdded = true
								break
							end
						end
						if not alreadyAdded then
							table.insert(targets, {
								character = inst,
								humanoid = hum,
								rootPart = root :: BasePart,
							})
						end
					end
				end
			end
		end
	end

	return targets
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hitbox: Skill 1 — Spin Attack (5s Continuous AoE Whirlwind)
-- ─────────────────────────────────────────────────────────────────────────────
local function executeSpinAttack(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local duration = config.duration or 5.0
	local damage = config.damage or 16
	local radius = config.range or 14
	local tickInterval = 0.4
	local totalTicks = math.floor(duration / tickInterval)
	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	casterChar:SetAttribute("IsSkill1Active", true)
	casterChar:SetAttribute("IsSpinAttackActive", true)

	task.spawn(function()
		for i = 1, totalTicks do
			if not casterChar or not casterChar.Parent then break end
			local hum = casterChar:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then break end

			local currentPos = casterRoot and casterRoot.Position or origin
			local targets = getPotentialTargets(casterChar)

			for _, target in ipairs(targets) do
				local dist = (target.rootPart.Position - currentPos).Magnitude
				if dist <= radius then
					target.humanoid:TakeDamage(damage)

					-- Outward centrifugal impulse
					local diff = target.rootPart.Position - currentPos
					local flatDiff = Vector3.new(diff.X, 0, diff.Z)
					local pushDir = flatDiff.Magnitude > 0.1 and flatDiff.Unit or Vector3.new(1, 0, 0)
					local kbDir = (pushDir + Vector3.new(0, 0.25, 0)).Unit
					target.rootPart:ApplyImpulse(kbDir * (target.rootPart.AssemblyMass * 12))
					print(`[SkillManager] Spin Attack hit {target.character.Name} for {damage} damage!`)
				end
			end

			task.wait(tickInterval)
		end

		if casterChar and casterChar.Parent then
			casterChar:SetAttribute("IsSkill1Active", false)
			casterChar:SetAttribute("IsSpinAttackActive", false)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hitbox: Skill 2 — Flame Slash (Ranged Projectile)
-- ─────────────────────────────────────────────────────────────────────────────
local function executeFlameSlash(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local range = config.range or 45
	local speed = config.projectileSpeed or 70
	local damage = config.damage or 30
	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit

	local travelDuration = range / speed
	local startTime = os.clock()
	local hitTargets: { [Model]: boolean } = {}

	task.spawn(function()
		local elapsed = 0
		local stepInterval = 0.05
		local lastPos = origin

		while elapsed < travelDuration do
			task.wait(stepInterval)
			elapsed = os.clock() - startTime
			local currentDist = math.min(elapsed * speed, range)
			local currentPos = origin + flatDir * currentDist

			-- Raycast segment to check wall collision
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { casterChar }
			local rayResult = Workspace:Raycast(lastPos, currentPos - lastPos, raycastParams)

			local targets = getPotentialTargets(casterChar)
			for _, target in ipairs(targets) do
				if not hitTargets[target.character] then
					local targetPos = target.rootPart.Position
					local distToLine = (targetPos - currentPos).Magnitude
					if distToLine <= 5.5 then
						hitTargets[target.character] = true
						target.humanoid:TakeDamage(damage)
						
						-- Knockback along projectile path
						local kbDir = (flatDir + Vector3.new(0, 0.25, 0)).Unit
						target.rootPart:ApplyImpulse(kbDir * (target.rootPart.AssemblyMass * 25))
						print(`[SkillManager] Flame Slash pierced {target.character.Name} for {damage} damage!`)
					end
				end
			end

			if rayResult and rayResult.Instance and rayResult.Instance.CanCollide then
				-- Hit a wall or obstacle
				break
			end

			lastPos = currentPos
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hitbox: Skill 3 — Phoenix Dash (Dash + Whirlwind)
-- ─────────────────────────────────────────────────────────────────────────────
local function executePhoenixDash(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local dashDist = config.dashDistance or 24
	local damage = config.damage or 25
	local radius = config.range or 8
	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit

	local hitTargets: { [Model]: boolean } = {}
	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?

	-- Make caster invisible during the dash
	setCharacterVisibility(casterChar, false)

	-- Check hits continuously during the 0.35s dash
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < 0.35 do
			local currentPos = casterRoot and casterRoot.Position or origin
			local targets = getPotentialTargets(casterChar)
			for _, target in ipairs(targets) do
				if not hitTargets[target.character] then
					local dist = (target.rootPart.Position - currentPos).Magnitude
					if dist <= radius then
						hitTargets[target.character] = true
						target.humanoid:TakeDamage(damage)
						
						-- Whirlwind upward burst
						local outwardDir = (target.rootPart.Position - currentPos)
						local flatOutward = Vector3.new(outwardDir.X, 0, outwardDir.Z)
						local kbDir = (flatOutward.Magnitude > 0.1 and flatOutward.Unit or flatDir) + Vector3.new(0, 0.6, 0)
						target.rootPart:ApplyImpulse(kbDir.Unit * (target.rootPart.AssemblyMass * 30))
						print(`[SkillManager] Phoenix Dash hit {target.character.Name} for {damage} damage!`)
					end
				end
			end
			task.wait(0.05)
		end
		-- Restore caster visibility when dash completes
		setCharacterVisibility(casterChar, true)
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hitbox: Skill 4 — Infernal Wrath (Ultimate: High Damage Impact Slash)
-- ─────────────────────────────────────────────────────────────────────────────
local function executeInfernalWrath(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local damage = config.damage or 100
	local radius = config.range or 24
	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local travelDist = 28.0
	local impactPos = origin + flatDir * travelDist

	task.spawn(function()
		-- Wait 2.0s for windup + swing, then track travel across 3.0s
		task.wait(2.0)
		if not casterChar or not casterChar.Parent then return end

		local hitDuringTravel: { [Model]: boolean } = {}
		local travelStartTime = os.clock()
		local travelDur = 3.0
		local slashStartPos = origin + flatDir * 3.0

		while os.clock() - travelStartTime < travelDur do
			local alpha = math.clamp((os.clock() - travelStartTime) / travelDur, 0, 1)
			local curPos = slashStartPos:Lerp(impactPos, alpha)

			local targets = getPotentialTargets(casterChar)
			for _, target in ipairs(targets) do
				if not hitDuringTravel[target.character] then
					local dist = (target.rootPart.Position - curPos).Magnitude
					if dist <= 8.0 then
						hitDuringTravel[target.character] = true
						target.humanoid:TakeDamage(math.floor(damage * 0.4))
						local kbDir = (flatDir + Vector3.new(0, 0.4, 0)).Unit
						target.rootPart:ApplyImpulse(kbDir * (target.rootPart.AssemblyMass * 25))
						print(`[SkillManager] Infernal Wrath Slash Wave hit {target.character.Name}!`)
					end
				end
			end
			task.wait(0.06)
		end

		-- Explosion Impact at t = 5.0s
		if not casterChar or not casterChar.Parent then return end
		local targets = getPotentialTargets(casterChar)
		for _, target in ipairs(targets) do
			local dist = (target.rootPart.Position - impactPos).Magnitude
			if dist <= radius then
				local finalDmg = hitDuringTravel[target.character] and math.floor(damage * 0.6) or damage
				target.humanoid:TakeDamage(finalDmg)
				
				-- Heavy explosive knockback upward and outward
				local outward = (target.rootPart.Position - impactPos)
				local flatOutward = Vector3.new(outward.X, 0, outward.Z)
				local kbDir = (flatOutward.Magnitude > 0.1 and flatOutward.Unit or flatDir) + Vector3.new(0, 0.7, 0)
				target.rootPart:ApplyImpulse(kbDir.Unit * (target.rootPart.AssemblyMass * 45))
				print(`[SkillManager] Infernal Wrath (Ultimate Impact) hit {target.character.Name} for {finalDmg} damage!`)
			end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Skill Request Handler
-- ─────────────────────────────────────────────────────────────────────────────
function SkillManager.HandleSkillUse(player: Player, payload: any)
	if typeof(payload) ~= "table" then return end

	local skillIndex = payload.skillIndex
	if typeof(skillIndex) ~= "number" or skillIndex < 1 or skillIndex > 4 then return end

	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end

	-- Block skills in lobby
	if player:GetAttribute("InLobby") == true then return end

	-- Block skill use while Skill 1 (Spin Attack) is active
	if char:GetAttribute("IsSkill1Active") == true or char:GetAttribute("IsSpinAttackActive") == true then
		warn(`[SkillManager] {player.Name} attempted to cast skill while Skill 1 was active!`)
		return
	end

	local classId = player:GetAttribute("SelectedClass") or "heavy_knight"
	local config = SkillData.GetSkill(classId, skillIndex)
	if not config then return end

	-- Validate Cooldown
	local now = os.clock()
	if not playerCooldowns[player] then
		playerCooldowns[player] = {}
	end

	local lastUsed = playerCooldowns[player][skillIndex] or 0
	local cdBuffer = 0.12 -- 120ms leeway for latency
	if now - lastUsed < (config.cooldown - cdBuffer) then
		warn(`[SkillManager] {player.Name} attempted to use Skill {skillIndex} before cooldown expired!`)
		return
	end

	-- Mark cooldown
	playerCooldowns[player][skillIndex] = now

	-- Direction and origin extraction
	local clientOrigin = typeof(payload.origin) == "Vector3" and payload.origin or rootPart.Position
	local origin = rootPart.Position
	-- Check for reasonable origin proximity
	if (clientOrigin - rootPart.Position).Magnitude < 10 then
		origin = clientOrigin
	end

	local direction = rootPart.CFrame.LookVector
	if typeof(payload.direction) == "Vector3" and payload.direction.Magnitude > 0.1 then
		direction = Vector3.new(payload.direction.X, 0, payload.direction.Z).Unit
	end

	-- Execute authoritative skill logic
	if skillIndex == 1 then
		executeSpinAttack(player, char, origin, direction, config)
	elseif skillIndex == 2 then
		executeFlameSlash(player, char, origin, direction, config)
	elseif skillIndex == 3 then
		executePhoenixDash(player, char, origin, direction, config)
	elseif skillIndex == 4 then
		executeInfernalWrath(player, char, origin, direction, config)
	end

	-- Replicate VFX to other players
	local vfxRemote = Network.GetRemoteEvent(Network.Remotes.SkillVFX)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		if otherPlayer ~= player then
			vfxRemote:FireClient(otherPlayer, {
				player = player,
				skillIndex = skillIndex,
				origin = origin,
				direction = direction,
			})
		end
	end

	-- Confirm Cooldown to Caster
	local cdRemote = Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate)
	cdRemote:FireClient(player, {
		skillIndex = skillIndex,
		cooldown = config.cooldown,
	})

	print(`[SkillManager] {player.Name} successfully cast Skill {skillIndex} ({config.name})`)
end

function SkillManager.Init()
	local useSkillRemote = Network.GetRemoteEvent(Network.Remotes.UseSkill)
	useSkillRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		SkillManager.HandleSkillUse(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		playerCooldowns[player] = nil
	end)

	print("[SkillManager] Server SkillManager initialized.")
end

return SkillManager
