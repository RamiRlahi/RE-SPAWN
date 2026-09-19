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
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local SkillManager = {}
local basicAttackTimes: { [Player]: number } = {}

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
	local addedSet: { [Model]: boolean } = {}

	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc ~= casterChar and not addedSet[desc] then
			-- Don't consider accessories or player character sub-models
			if desc:FindFirstAncestorOfClass("Accessory") then continue end
			if desc:IsDescendantOf(casterChar) then continue end

			local hum = desc:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local root: BasePart? = (desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")) :: BasePart?
				if root then
					addedSet[desc] = true
					table.insert(targets, {
						character = desc,
						humanoid = hum,
						rootPart = root,
					})
				end
			end
		end
	end

	return targets
end

-- Keep combat authoritative while giving the attacking player immediate, exact
-- feedback about the damage that was actually applied to a target.
local function dealDamage(player: Player, target: { character: Model, humanoid: Humanoid, rootPart: BasePart }, amount: number, source: string)
	local finalAmount = math.max(0, math.floor(amount))
	if finalAmount <= 0 or target.humanoid.Health <= 0 then return end

	local isCrit = false
	local critChance = PlayerStats.GetStat(player, "critChance")
	if critChance > 0 and math.random() < critChance then
		isCrit = true
		finalAmount = math.floor(finalAmount * 1.5)
	end

	target.humanoid:TakeDamage(finalAmount)

	local lifesteal = PlayerStats.GetStat(player, "lifesteal")
	if lifesteal > 0 then
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local heal = math.floor(finalAmount * lifesteal)
			if heal > 0 then
				hum.Health = math.min(hum.MaxHealth, hum.Health + heal)
			end
		end
	end

	Network.GetRemoteEvent(Network.Remotes.DamageDealt):FireClient(player, {
		position = target.rootPart.Position + Vector3.new(0, 2.5, 0),
		amount = finalAmount,
		source = isCrit and (`{source} CRIT`) or source,
	})
end

local function rotateFlatDirection(direction: Vector3, degrees: number): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	return (CFrame.Angles(0, math.rad(degrees), 0) * flat.Unit).Unit
end

local function getRangerCursorTarget(origin: Vector3, lookDir: Vector3, requestedTarget: any, maxRange: number): Vector3
	local offset: Vector3? = nil
	if typeof(requestedTarget) == "Vector3" then
		offset = Vector3.new(requestedTarget.X - origin.X, 0, requestedTarget.Z - origin.Z)
	end
	if not offset or offset.Magnitude < 0.5 then
		offset = rotateFlatDirection(lookDir, 0)
	end
	return origin + offset.Unit * math.min(offset.Magnitude, maxRange)
end

local function damageFirstTargetOnLine(player: Player, casterChar: Model, origin: Vector3, direction: Vector3, range: number, width: number, damage: number, source: string)
	local bestTarget = nil
	local bestAlong = range
	local flatDir = rotateFlatDirection(direction, 0)

	for _, target in ipairs(getPotentialTargets(casterChar)) do
		local diff = target.rootPart.Position - origin
		local flatDiff = Vector3.new(diff.X, 0, diff.Z)
		local along = flatDiff:Dot(flatDir)
		if along >= 0 and along <= range then
			local closest = origin + flatDir * along
			local lateral = (Vector3.new(target.rootPart.Position.X, origin.Y, target.rootPart.Position.Z) - closest).Magnitude
			if lateral <= width and along < bestAlong then
				bestAlong = along
				bestTarget = target
			end
		end
	end

	if bestTarget then
		dealDamage(player, bestTarget, damage, source)
		return bestTarget, bestAlong
	end

	return nil, nil
end

local function findRangerArrowTemplate(): Instance?
	-- Prefer the dedicated projectile asset placed directly in ReplicatedStorage.
	-- The recursive lookup keeps this resilient if it is later organized into a
	-- different ReplicatedStorage folder.
	local arrow = ReplicatedStorage:FindFirstChild("Arrow") or ReplicatedStorage:FindFirstChild("arrow")
	if arrow and (arrow:IsA("Model") or arrow:IsA("BasePart")) then return arrow end
	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if string.lower(descendant.Name) == "arrow" and (descendant:IsA("Model") or descendant:IsA("BasePart")) then
			return descendant
		end
	end

	-- Backwards-compatible fallback for the original Ranger armor location.
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local classes = assets and assets:FindFirstChild("Classes")
	local rangerArmor = classes and classes:FindFirstChild("Ranger armor")
	if not rangerArmor then return nil end

	arrow = rangerArmor:FindFirstChild("Arrow") or rangerArmor:FindFirstChild("arrow")
	if arrow and (arrow:IsA("Model") or arrow:IsA("BasePart")) then return arrow end
	for _, child in ipairs(rangerArmor:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and string.find(string.lower(child.Name), "arrow") then
			return child
		end
	end
	return nil
end

local function fireRangerArrowVisual(origin: Vector3, direction: Vector3, distance: number, speedMultiplier: number?)
	local template = findRangerArrowTemplate()
	if not template then
		warn("[SkillManager] Ranger Arrow model not found in ReplicatedStorage.")
		return
	end

	local arrow = template:Clone()
	local function positionArrow(cframe: CFrame)
		if arrow:IsA("Model") then
			arrow:PivotTo(cframe)
		elseif arrow:IsA("BasePart") then
			arrow.CFrame = cframe
		end
	end
	for _, descendant in ipairs(arrow:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	if arrow:IsA("BasePart") then
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.CanTouch = false
		arrow.CanQuery = false
	end

	arrow.Name = "RangerArrowProjectile"
	arrow.Parent = Workspace
	local flatDirection = rotateFlatDirection(direction, 0)
	local validDistance = (typeof(distance) == "number" and distance > 0) and distance or 70
	local mult = (typeof(speedMultiplier) == "number" and speedMultiplier > 0) and speedMultiplier or 1
	local travelTime = math.max(0.05, validDistance / (180 * mult))
	local baseOrigin = typeof(origin) == "Vector3" and origin or Vector3.zero
	task.spawn(function()
		local startTime = os.clock()
		while arrow.Parent do
			local progress = math.clamp((os.clock() - startTime) / travelTime, 0, 1)
			local position = baseOrigin + flatDirection * (validDistance * progress)
			local lookCF = CFrame.lookAt(position, position + flatDirection)
			positionArrow(lookCF * CFrame.Angles(0, math.rad(-90), 0))
			if progress >= 1 then break end
			task.wait()
		end
		if arrow.Parent then arrow:Destroy() end
	end)
end

local function applyRangerArrowKnockback(target: any, direction: Vector3, multiplier: number)
	if not target then return end
	local pushDirection = (rotateFlatDirection(direction, 0) + Vector3.new(0, 0.12, 0)).Unit
	target.rootPart:ApplyImpulse(pushDirection * (target.rootPart.AssemblyMass * 8 * multiplier))
end

local function rootTarget(target: { character: Model, humanoid: Humanoid, rootPart: BasePart }, duration: number)
	local root = target.rootPart
	local oldWalkSpeed = target.humanoid.WalkSpeed
	local oldJumpPower = target.humanoid.JumpPower
	root.Anchored = true
	target.humanoid.WalkSpeed = 0
	target.humanoid.JumpPower = 0
	task.delay(duration, function()
		if root and root.Parent then
			root.Anchored = false
		end
		if target.character and target.character.Parent and target.humanoid and target.humanoid.Health > 0 then
			target.humanoid.WalkSpeed = oldWalkSpeed
			target.humanoid.JumpPower = oldJumpPower
		end
	end)
end

local function executeRangerThornBarrage(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local damage = config.damage or 22
	local range = config.range or 64
	local spread = config.angle or 38
	local baseCount = 5
	local extraProjectiles = math.max(0, math.floor(PlayerStats.GetStat(player, "projectileCount")))
	local totalProjectiles = baseCount + extraProjectiles
	local baseAngleStep = spread / math.max(baseCount - 1, 1) -- ~9.5 degrees
	local totalSpread = (totalProjectiles - 1) * baseAngleStep
	local startAngle = -totalSpread / 2
	local width = 2.4 * (config.areaMultiplier or 1)
	local knockback = PlayerStats.GetStat(player, "knockback")
	local projectileSpeed = PlayerStats.GetStat(player, "projectileSpeed")
	local arrowOrigin = origin + Vector3.new(0, 1.2, 0)

	for index = 1, totalProjectiles do
		local angle = startAngle + (index - 1) * baseAngleStep
		local direction = rotateFlatDirection(lookDir, angle)
		local target, hitDistance = damageFirstTargetOnLine(player, casterChar, arrowOrigin, direction, range, width, damage, "THORN BARRAGE")
		applyRangerArrowKnockback(target, direction, knockback)
		fireRangerArrowVisual(arrowOrigin, direction, hitDistance or range, projectileSpeed)
	end
end

local function executeRangerEntanglingArrow(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local flatDir = rotateFlatDirection(lookDir, 0)
	local range = config.range or 44
	local arrowOrigin = origin + Vector3.new(0, 1.2, 0)
	local directHit, hitDistance = damageFirstTargetOnLine(player, casterChar, arrowOrigin, flatDir, range, 2.8 * (config.areaMultiplier or 1), config.damage or 30, "ENTANGLING ARROW")
	local projectileSpeed = PlayerStats.GetStat(player, "projectileSpeed")
	fireRangerArrowVisual(arrowOrigin, flatDir, hitDistance or range, projectileSpeed)
	local impactPos = directHit and directHit.rootPart.Position or (origin + flatDir * range)
	local radius = 10 * (config.areaMultiplier or 1)
	local damage = math.floor((config.damage or 30) * 0.75)
	local rootDuration = config.duration or 2.6

	for _, target in ipairs(getPotentialTargets(casterChar)) do
		local dist = (target.rootPart.Position - impactPos).Magnitude
		if dist <= radius then
			if target.character ~= (directHit and directHit.character) then
				dealDamage(player, target, damage, "ENTANGLING ARROW")
			end
			rootTarget(target, rootDuration)
		end
	end

	print(`[SkillManager] Entangling Arrow impacted at {math.floor(hitDistance or range)} studs.`)
end

local function executeRangerToxicCloud(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, targetPosition: any, config: any)
	local impactPos = getRangerCursorTarget(origin, lookDir, targetPosition, config.range or 34)
	local radius = 13 * (config.areaMultiplier or 1)
	local duration = config.duration or 6.0
	local tickInterval = 0.6
	local damage = config.damage or 12

	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			if not casterChar or not casterChar.Parent then break end
			for _, target in ipairs(getPotentialTargets(casterChar)) do
				if (target.rootPart.Position - impactPos).Magnitude <= radius then
					dealDamage(player, target, damage, "TOXIC CLOUD")
				end
			end
			task.wait(tickInterval)
		end
	end)
end

local function executeRangerRainOfArrows(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, targetPosition: any, config: any)
	local center = getRangerCursorTarget(origin, lookDir, targetPosition, config.range or 42)
	local radius = 18 * (config.areaMultiplier or 1)
	local damage = config.damage or 24
	local duration = config.duration or 4.0

	task.spawn(function()
		task.wait(1.05)
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			if not casterChar or not casterChar.Parent then break end
			for _, target in ipairs(getPotentialTargets(casterChar)) do
				if (target.rootPart.Position - center).Magnitude <= radius then
					dealDamage(player, target, damage, "RAIN OF ARROWS")
					local push = Vector3.new(0, 1, 0)
					target.rootPart:ApplyImpulse(push * (target.rootPart.AssemblyMass * 8))
				end
			end
			task.wait(0.45)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hitbox: Skill 1 — Spin Attack (5s Continuous AoE Whirlwind)
-- ─────────────────────────────────────────────────────────────────────────────
local function executeSpinAttack(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local duration = config.duration or 5.0
	local damage = config.damage or 16
	local radius = (config.range or 14) * (config.areaMultiplier or 1)
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
					dealDamage(player, target, damage, "WHIRLWIND")

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
		local extraProjectiles = math.max(0, math.floor(PlayerStats.GetStat(player, "projectileCount") or 0))
		local missileCount = 5 + extraProjectiles
		for i = 1, missileCount do
			task.wait(i == 1 and 0.28 or 0.055)
			if not casterChar or not casterChar.Parent then break end

			local targets = getPotentialTargets(casterChar)
			local closestTarget = nil
			local closestDist = 95

			for _, t in ipairs(targets) do
				local d = (t.rootPart.Position - origin).Magnitude
				if d < closestDist then
					closestDist = d
					closestTarget = t
				end
			end

			if closestTarget and closestTarget.humanoid and closestTarget.humanoid.Health > 0 then
				local damage = 16 -- 16 damage per missile (total 80 damage across 5 missiles)
				dealDamage(player, closestTarget, damage, "MISSILE")
				local kbDir = (closestTarget.rootPart.Position - origin).Unit + Vector3.new(0, 0.2, 0)
				closestTarget.rootPart:ApplyImpulse(kbDir.Unit * (closestTarget.rootPart.AssemblyMass * 8))
				print(`[SkillManager] Guided Missile #{i} struck {closestTarget.character.Name} for {damage} damage!`)
			end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hitbox: Skill 3 — Phoenix Dash (Dash + Whirlwind)
-- ─────────────────────────────────────────────────────────────────────────────
local function executePhoenixDash(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local dashDist = config.dashDistance or 24
	local damage = config.damage or 25
	local radius = (config.range or 8) * (config.areaMultiplier or 1)
	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit

	local hitTargets: { [Model]: boolean } = {}
	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?

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
						dealDamage(player, target, damage, "PHOENIX DASH")
						
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
	local radius = (config.range or 24) * (config.areaMultiplier or 1)
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
		else
			-- Server procedural slash wave fallback
			local slashPart = Instance.new("Part")
			slashPart.Name = "ProceduralSlashWave"
			slashPart.Size = Vector3.new(12, 1.5, 4)
			slashPart.Transparency = 0.25
			slashPart.Material = Enum.Material.Neon
			slashPart.Color = Color3.fromRGB(255, 115, 25)
			slashPart.CanCollide = false
			slashPart.CanTouch = false
			slashPart.CanQuery = false
			slashPart.Anchored = true
			slashPart.CFrame = CFrame.lookAt(slashStartPos, slashStartPos + flatDir)

			local slashMesh = Instance.new("SpecialMesh")
			slashMesh.MeshType = Enum.MeshType.Sphere
			slashMesh.Scale = Vector3.new(1, 0.15, 0.6)
			slashMesh.Parent = slashPart

			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 90)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 90, 20)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 20, 10)),
			})
			pe.LightEmission = 1
			pe.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 3.5),
				NumberSequenceKeypoint.new(1, 0.5),
			})
			pe.Lifetime = NumberRange.new(0.2, 0.45)
			pe.Rate = 90
			pe.Speed = NumberRange.new(6, 16)
			pe.SpreadAngle = Vector2.new(30, 15)
			pe.Orientation = Enum.ParticleOrientation.VelocityParallel
			pe.Parent = slashPart

			local pLight = Instance.new("PointLight")
			pLight.Color = Color3.fromRGB(255, 120, 30)
			pLight.Range = 16
			pLight.Brightness = 3
			pLight.Parent = slashPart

			slashPart.Parent = Workspace.Terrain
			slashClone = slashPart
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
						dealDamage(player, target, math.floor(damage * 0.4), "INFERNAL WRATH")
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
				dealDamage(player, target, finalDmg, "INFERNAL WRATH")
				
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

	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" then return end
	local config = SkillData.GetSkill(classId, skillIndex)
	if not config then return end
	local effectiveConfig = table.clone(config)
	effectiveConfig.damage *= PlayerStats.GetStat(player, "damage")
	effectiveConfig.cooldown *= PlayerStats.GetStat(player, "abilityCooldown")
	if effectiveConfig.duration then
		effectiveConfig.duration *= PlayerStats.GetStat(player, "abilityDuration")
	end
	if effectiveConfig.projectileSpeed then
		effectiveConfig.projectileSpeed *= PlayerStats.GetStat(player, "projectileSpeed")
	end
	effectiveConfig.areaMultiplier = PlayerStats.GetStat(player, "size")
	effectiveConfig.projectileCount = math.max(0, math.floor(PlayerStats.GetStat(player, "projectileCount")))

	-- Validate Cooldown
	local now = os.clock()
	if not playerCooldowns[player] then
		playerCooldowns[player] = {}
	end

	local lastUsed = playerCooldowns[player][skillIndex] or 0
	local cdBuffer = 0.12 -- 120ms leeway for latency
	if now - lastUsed < (effectiveConfig.cooldown - cdBuffer) then
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
	local targetPosition = payload.targetPosition
	if classId == "ranger" and (skillIndex == 3 or skillIndex == 4) then
		targetPosition = getRangerCursorTarget(origin, direction, targetPosition, effectiveConfig.range or 42)
	end

	-- Execute authoritative skill logic
	if classId == "ranger" then
		if skillIndex == 1 then
			executeRangerThornBarrage(player, char, origin, direction, effectiveConfig)
		elseif skillIndex == 2 then
			executeRangerEntanglingArrow(player, char, origin, direction, effectiveConfig)
		elseif skillIndex == 3 then
			executeRangerToxicCloud(player, char, origin, direction, targetPosition, effectiveConfig)
		elseif skillIndex == 4 then
			executeRangerRainOfArrows(player, char, origin, direction, targetPosition, effectiveConfig)
		end
	elseif classId == "heavy_knight" and skillIndex == 1 then
		executeSpinAttack(player, char, origin, direction, effectiveConfig)
	elseif classId == "heavy_knight" and skillIndex == 2 then
		executeMissileBuff(player, char, effectiveConfig)
	elseif classId == "heavy_knight" and skillIndex == 3 then
		executePhoenixDash(player, char, origin, direction, effectiveConfig)
	elseif classId == "heavy_knight" and skillIndex == 4 then
		executeInfernalWrath(player, char, origin, direction, effectiveConfig)
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
					targetPosition = targetPosition,
					projectileCount = effectiveConfig.projectileCount,
				})
			end
		end
	end

	-- Confirm Cooldown to Caster
	local cdRemote = Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate)
	cdRemote:FireClient(player, {
		skillIndex = skillIndex,
		cooldown = effectiveConfig.cooldown,
	})

	print(`[SkillManager] {player.Name} successfully cast Skill {skillIndex} ({config.name})`)
end

function SkillManager.HandleBasicAttack(player: Player, payload: any)
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end
	if player:GetAttribute("InLobby") == true then return end
	local now = os.clock()
	local attackInterval = 0.38 / math.max(PlayerStats.GetStat(player, "basicAttackSpeed"), 0.1)
	if now - (basicAttackTimes[player] or 0) < attackInterval then return end
	basicAttackTimes[player] = now

	local origin = rootPart.Position
	local lookDir = rootPart.CFrame.LookVector
	if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then
		local requestedDirection = Vector3.new(payload.direction.X, 0, payload.direction.Z)
		if requestedDirection.Magnitude > 0.1 then
			lookDir = requestedDirection.Unit
		end
	end
	local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" then return end

	if classId == "ranger" then
		local damage = math.floor(24 * PlayerStats.GetStat(player, "damage"))
		local arrowOrigin = origin + Vector3.new(0, 1.2, 0)
		local extraProjectiles = math.max(0, math.floor(PlayerStats.GetStat(player, "projectileCount")))
		local projectileCount = 1 + extraProjectiles
		local hitWidth = 2.0 * PlayerStats.GetStat(player, "size")
		local knockback = PlayerStats.GetStat(player, "knockback")
		local projectileSpeed = PlayerStats.GetStat(player, "projectileSpeed")
		local spreadStep = 8 -- 8 degrees between adjacent arrows
		local totalSpread = (projectileCount - 1) * spreadStep
		local startAngle = -totalSpread / 2
		for index = 1, projectileCount do
			local angle = startAngle + (index - 1) * spreadStep
			local direction = rotateFlatDirection(flatLook, angle)
			local target, hitDistance = damageFirstTargetOnLine(player, char, arrowOrigin, direction, 70, hitWidth, damage, "VENOM ARROWS")
			applyRangerArrowKnockback(target, direction, knockback)
			fireRangerArrowVisual(arrowOrigin, direction, hitDistance or 70, projectileSpeed)
		end
		return
	end
	if classId ~= "heavy_knight" then return end

	local targets = getPotentialTargets(char)
	local hitCount = 0

	for _, target in ipairs(targets) do
		local diff = target.rootPart.Position - origin
		local dist = diff.Magnitude
		if dist <= 14.0 then
			local flatDiff = Vector3.new(diff.X, 0, diff.Z).Unit
			local dot = flatLook:Dot(flatDiff)
			if dot > -0.1 or dist <= 6.0 then
				local damage = math.floor(35 * PlayerStats.GetStat(player, "damage"))
				dealDamage(player, target, damage, "BASIC ATTACK")
				hitCount += 1

				local kbDir = (flatLook + Vector3.new(0, 0.25, 0)).Unit
				target.rootPart:ApplyImpulse(kbDir * (target.rootPart.AssemblyMass * 16))
				print(`[SkillManager] Basic Attack hit {target.character.Name} for {damage} damage!`)
			end
		end
	end

	-- If Missile Barrage buff is active, launch missile damage on server
	if char:GetAttribute("IsMissileBuffActive") == true then
		SkillManager.HandleMissileAttack(player, char)
	end
end

function SkillManager.Init()
	local useSkillRemote = Network.GetRemoteEvent(Network.Remotes.UseSkill)
	useSkillRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		SkillManager.HandleSkillUse(player, payload)
	end)

	local performAttackRemote = Network.GetRemoteEvent(Network.Remotes.PerformAttack)
	performAttackRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		SkillManager.HandleBasicAttack(player, payload)
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		playerCooldowns[player] = nil
		basicAttackTimes[player] = nil
	end)

	print("[SkillManager] Server SkillManager initialized.")
end

return SkillManager
