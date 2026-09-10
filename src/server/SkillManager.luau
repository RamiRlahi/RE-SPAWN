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

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: Find VFX asset in ReplicatedStorage (server can read ReplicatedStorage)
-- ─────────────────────────────────────────────────────────────────────────────
local function findVFXAsset(name: string): Instance?
	local searchNames = {
		name,
		string.lower(name),
		string.upper(name),
		string.gsub(name, " ", "_"),
		string.gsub(name, "_", " "),
		string.gsub(string.lower(name), " ", "_"),
		string.gsub(string.lower(name), "_", " "),
	}

	local roots = {
		ReplicatedStorage:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("VFX"),
		ReplicatedStorage:FindFirstChild("VFX"),
		ReplicatedStorage:FindFirstChild("Assets"),
		ReplicatedStorage,
	}

	for _, folder in ipairs(roots) do
		if folder then
			for _, n in ipairs(searchNames) do
				local found = folder:FindFirstChild(n)
				if found then return found end
			end
			for _, child in ipairs(folder:GetChildren()) do
				for _, n in ipairs(searchNames) do
					if string.lower(child.Name) == string.lower(n) then
						return child
					end
				end
			end
		end
	end
	return nil
end

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
-- Hitbox: Skill 2 — Missile Barrage (Buff: Attacks launch guided missiles)
-- ─────────────────────────────────────────────────────────────────────────────
local function executeMissileBuff(player: Player, casterChar: Model, config: any)
	local duration = config.duration or 8.0
	casterChar:SetAttribute("IsMissileBuffActive", true)

	task.delay(duration, function()
		if casterChar and casterChar.Parent then
			casterChar:SetAttribute("IsMissileBuffActive", false)
		end
	end)

	print(`[SkillManager] {player.Name} activated Missile Barrage buff for {duration}s!`)
end

function SkillManager.HandleMissileAttack(player: Player, casterChar: Model)
	local root = casterChar:FindFirstChild("HumanoidRootPart") or casterChar.PrimaryPart
	if not root then return end
	local origin = root.Position

	task.spawn(function()
		-- Give missile travel delay before server impact evaluation
		task.wait(0.35)
		if not casterChar or not casterChar.Parent then return end

		local targets = getPotentialTargets(casterChar)
		local closestTarget = nil
		local closestDist = 55

		for _, t in ipairs(targets) do
			local d = (t.rootPart.Position - origin).Magnitude
			if d < closestDist then
				closestDist = d
				closestTarget = t
			end
		end

		if closestTarget and closestTarget.humanoid and closestTarget.humanoid.Health > 0 then
			local damage = 35
			closestTarget.humanoid:TakeDamage(damage)
			local kbDir = (closestTarget.rootPart.Position - origin).Unit + Vector3.new(0, 0.35, 0)
			closestTarget.rootPart:ApplyImpulse(kbDir.Unit * (closestTarget.rootPart.AssemblyMass * 20))
			print(`[SkillManager] Guided Missile struck {closestTarget.character.Name} for {damage} damage!`)
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
-- Server-authoritative hitboxes + server-side VFX spawning for all-player visibility.
--
-- Timeline:
--   t=0.00–1.00s : Windup (client camera Shot 1)
--   t=1.00–1.60s : Slash travels fast (0.60s). Server spawns hk_ult_slash in Workspace.
--   t=1.60s       : Explosion impact. Server spawns Light Explosion VFX in Workspace.
-- ─────────────────────────────────────────────────────────────────────────────
local Debris = game:GetService("Debris")

local function executeInfernalWrath(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local damage = config.damage or 100
	local radius = config.range or 24
	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local travelDist = 32.0
	local impactPos = origin + flatDir * travelDist

	task.spawn(function()
		-- Wait 1.50s for windup + slash animation, then slash wave travels fast across 0.60s
		task.wait(1.50)
		if not casterChar or not casterChar.Parent then return end

		-- ── Server-side Slash VFX (visible to all players) ──
		local slashStartPos = origin + flatDir * 3.0 + Vector3.new(0, 1.2, 0)
		local slashEndPos = impactPos + Vector3.new(0, 1.2, 0)
		local slashTemplate = findVFXAsset("hk_ult_slash") or findVFXAsset("hk_ult") or findVFXAsset("ult_slash")
		local slashClone: Instance? = nil

		if slashTemplate then
			slashClone = slashTemplate:Clone()
			if slashClone:IsA("Model") then
				local prim = slashClone.PrimaryPart or slashClone:FindFirstChildWhichIsA("BasePart")
				if prim then
					prim.CanCollide = false
					prim.CanTouch = false
					prim.CanQuery = false
					prim.Anchored = true
					slashClone:PivotTo(CFrame.lookAt(slashStartPos, slashStartPos + flatDir))
				end
				for _, d in ipairs(slashClone:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
						d.CanTouch = false
						d.CanQuery = false
						d.Anchored = true
					elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
						d.Enabled = true
					end
				end
			elseif slashClone:IsA("BasePart") then
				slashClone.CanCollide = false
				slashClone.CanTouch = false
				slashClone.CanQuery = false
				slashClone.Anchored = true
				slashClone.CFrame = CFrame.lookAt(slashStartPos, slashStartPos + flatDir)
				for _, d in ipairs(slashClone:GetDescendants()) do
					if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
						d.Enabled = true
					end
				end
			end
			slashClone.Parent = Workspace.Terrain
		end

		-- ── Hitbox: Fast slash travel across 0.60s ──
		local hitDuringTravel: { [Model]: boolean } = {}
		local travelStartTime = os.clock()
		local travelDur = 0.60

		while os.clock() - travelStartTime < travelDur do
			local alpha = math.clamp((os.clock() - travelStartTime) / travelDur, 0, 1)
			local curPos = slashStartPos:Lerp(slashEndPos, alpha)

			-- Move the server-side slash VFX model
			if slashClone and slashClone.Parent then
				local orientCF = CFrame.lookAt(curPos, curPos + flatDir)
				if slashClone:IsA("Model") then
					slashClone:PivotTo(orientCF)
				elseif slashClone:IsA("BasePart") then
					slashClone.CFrame = orientCF
				end
			end

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
			task.wait(0.04)
		end

		-- Cleanup slash VFX
		if slashClone and slashClone.Parent then
			for _, d in ipairs(slashClone:GetDescendants()) do
				if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
					d.Enabled = false
				end
			end
			Debris:AddItem(slashClone, 0.4)
		end

		-- ── Explosion Impact at t ≈ 1.60s ──
		if not casterChar or not casterChar.Parent then return end

		-- Server-side Explosion VFX (visible to all players)
		local explTemplate = findVFXAsset("Light Explosion VFX") or findVFXAsset("Light Explosion") or findVFXAsset("Light_Explosion_VFX") or findVFXAsset("Explosion")
		if explTemplate then
			local explClone = explTemplate:Clone()
			if explClone:IsA("Model") then
				explClone:PivotTo(CFrame.new(impactPos))
				for _, d in ipairs(explClone:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
						d.CanTouch = false
						d.CanQuery = false
						d.Anchored = true
					elseif d:IsA("ParticleEmitter") then
						d.Enabled = true
						d:Emit(15)
					elseif d:IsA("Beam") or d:IsA("Trail") then
						d.Enabled = true
					end
				end
			elseif explClone:IsA("BasePart") then
				explClone.CanCollide = false
				explClone.Anchored = true
				explClone.CFrame = CFrame.new(impactPos)
				for _, d in ipairs(explClone:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						d.Enabled = true
						d:Emit(15)
					end
				end
			end
			explClone.Parent = Workspace.Terrain

			-- Cleanup explosion after it fades
			task.delay(1.2, function()
				if explClone and explClone.Parent then
					for _, d in ipairs(explClone:GetDescendants()) do
						if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
							d.Enabled = false
						end
					end
					Debris:AddItem(explClone, 0.5)
				end
			end)
		end

		-- Hitbox: Explosion damage
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
		executeMissileBuff(player, char, config)
	elseif skillIndex == 3 then
		executePhoenixDash(player, char, origin, direction, config)
	elseif skillIndex == 4 then
		executeInfernalWrath(player, char, origin, direction, config)
	end

	-- Replicate VFX to other players (for Skill 4, fire to ALL including caster
	-- since server handles the main VFX and caster needs client-side camera/particles)
	local vfxRemote = Network.GetRemoteEvent(Network.Remotes.SkillVFX)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		-- For skill 4: server spawns main VFX, so only send for client-side extras
		-- For other skills: send to everyone except caster (caster already plays locally)
		if otherPlayer ~= player or skillIndex == 4 then
			if skillIndex ~= 4 or otherPlayer ~= player then
				vfxRemote:FireClient(otherPlayer, {
					player = player,
					skillIndex = skillIndex,
					origin = origin,
					direction = direction,
				})
			end
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
