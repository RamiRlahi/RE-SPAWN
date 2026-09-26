--[[
	MobManager.luau
	Server-side procedural mob spawner, health tracking, physics/weld setup, and Blue Star Death VFX trigger.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))
local DifficultyManager = require(script.Parent:WaitForChild("DifficultyManager"))

local MobManager = {}

local activeMobsFolder: Folder? = nil
local FLOOR_SIZE = 12
local MOBS_PER_ROOM = 10
local ROOM_ACTIVATION_PADDING = 36
local ROOM_REFRESH_INTERVAL = 0.75

type MobRecord = {
	template: Model?,
	spawnCFrame: CFrame,
	isBoss: boolean,
	health: number,
	defeated: boolean,
	model: Model?,
}

type RoomMobGroup = {
	room: any,
	mobs: { MobRecord },
}

local roomMobGroups: { RoomMobGroup } = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: Fetch available top-level mob templates from ReplicatedStorage.Mobs
-- ─────────────────────────────────────────────────────────────────────────────
local function getMobTemplates(): ({ Model }, { Model })
	local normalList: { Model } = {}
	local bossList: { Model } = {}

	local mobsFolder = ReplicatedStorage:FindFirstChild("Mobs")
	if mobsFolder then
		for _, child in ipairs(mobsFolder:GetChildren()) do
			if child:IsA("Model") then
				local lowerName = string.lower(child.Name)
				if string.find(lowerName, "boss") then
					table.insert(bossList, child)
				else
					table.insert(normalList, child)
				end
			end
		end
	end
	return normalList, bossList
end

-- Fallback procedural Slime mob generator if no template exists
local function createFallbackMob(): Model
	local model = Instance.new("Model")
	model.Name = "Slime"

	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2.5, 2.5, 2.5)
	rootPart.Material = Enum.Material.Neon
	rootPart.Color = Color3.fromRGB(0, 180, 255)
	rootPart.CanCollide = true
	rootPart.Anchored = false
	rootPart.Transparency = 0.3
	rootPart.Parent = model
	model.PrimaryPart = rootPart

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1.5, 1.5, 1.5)
	head.Material = Enum.Material.SmoothPlastic
	head.Color = Color3.fromRGB(150, 230, 255)
	head.CanCollide = false
	head.Anchored = false
	head.CFrame = rootPart.CFrame * CFrame.new(0, 1.5, 0)
	head.Parent = model

	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = head
	weld.Parent = head

	local hum = Instance.new("Humanoid")
	hum.MaxHealth = 100
	hum.Health = 100
	hum.WalkSpeed = 12
	hum.RequiresNeck = false
	hum.Parent = model

	return model
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Blue Star Death VFX (client-only, so bursts do not replicate as world instances)
-- ─────────────────────────────────────────────────────────────────────────────
local function triggerBlueStarDeathVFX(position: Vector3)
	pcall(function()
		local deathRemote = Network.GetRemoteEvent(Network.Remotes.MobDeathVFX)
		for _, player in ipairs(Players:GetPlayers()) do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - position).Magnitude <= 100 then
				deathRemote:FireClient(player, { position = position })
			end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Mob Health Bar (BillboardGui over Mob Head)
-- ─────────────────────────────────────────────────────────────────────────────
local function createMobHealthBar(mobModel: Model, humanoid: Humanoid, rootPart: BasePart, extents: Vector3, isBoss: boolean)
	local bb = Instance.new("BillboardGui")
	bb.Name = "MobHealthBar"
	bb.Adornee = rootPart
	bb.Size = isBoss and UDim2.new(0, 180, 0, 38) or UDim2.new(0, 132, 0, 30)
	bb.StudsOffset = Vector3.new(0, (extents.Y * 0.5) + (isBoss and 2.5 or 1.8), 0)
	bb.AlwaysOnTop = true
	-- A zero MaxDistance keeps every active mob's HP visible instead of hiding
	-- normal enemies once they are more than a short distance away.
	bb.MaxDistance = 0
	bb.Parent = mobModel

	-- Background frame
	local bg = Instance.new("Frame")
	bg.Name = "Background"
	bg.Size = UDim2.new(1, 0, 1, 0)
	bg.BackgroundColor3 = Color3.fromRGB(20, 20, 25)
	bg.BackgroundTransparency = 0.25
	bg.BorderSizePixel = 0
	bg.Parent = bb

	local bgCorner = Instance.new("UICorner")
	bgCorner.CornerRadius = UDim.new(0, 4)
	bgCorner.Parent = bg

	local bgStroke = Instance.new("UIStroke")
	bgStroke.Color = isBoss and Color3.fromRGB(255, 180, 50) or Color3.fromRGB(60, 60, 70)
	bgStroke.Thickness = isBoss and 1.5 or 1.0
	bgStroke.Parent = bg

	-- Fill bar
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.new(1, -6, 0, 8)
	fill.Position = UDim2.new(0, 3, 1, -11)
	fill.BackgroundColor3 = isBoss and Color3.fromRGB(255, 65, 50) or Color3.fromRGB(230, 45, 45)
	fill.BorderSizePixel = 0
	fill.Parent = bg

	local fillCorner = Instance.new("UICorner")
	fillCorner.CornerRadius = UDim.new(0, 3)
	fillCorner.Parent = fill

	-- Name & HP Text Label
	local nameLabel = Instance.new("TextLabel")
	nameLabel.Name = "MobName"
	nameLabel.Size = UDim2.new(1, -8, 1, -12)
	nameLabel.Position = UDim2.fromOffset(4, 1)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Enum.Font.GothamBold
	nameLabel.TextSize = isBoss and 13 or 10
	nameLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
	nameLabel.TextStrokeTransparency = 0.4
	nameLabel.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	nameLabel.Text = `{isBoss and "★ Slime Boss" or mobModel.Name}\n{math.ceil(humanoid.Health)} / {math.ceil(humanoid.MaxHealth)} HP`
	nameLabel.Parent = bg

	-- Update on health change
	humanoid.HealthChanged:Connect(function(health)
		local alpha = math.clamp(health / humanoid.MaxHealth, 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(alpha, -6, 0, 8)
		}):Play()
		nameLabel.Text = `{isBoss and "★ Slime Boss" or mobModel.Name}\n{math.max(0, math.ceil(health))} / {math.ceil(humanoid.MaxHealth)} HP`

		if health <= 0 then
			bb.Enabled = false
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Mob Setup, Weld Construction & Physics Alignment
-- ─────────────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────
-- Animated Mob Support (rigged Zombies / Skeletons with walk & attack anims)
-- ─────────────────────────────────────────────────────────────────────────────
local RunService = game:GetService("RunService")

-- Global mob freeze used by ultimates: while frozen, every mob AI loop halts.
local mobFreezeUntil = 0

local function mobsAreFrozen(): boolean
	return os.clock() < mobFreezeUntil
end

function MobManager.FreezeMobs(duration: number)
	local untilTime = os.clock() + (duration or 0)
	if untilTime > mobFreezeUntil then
		mobFreezeUntil = untilTime
	end
end

function MobManager.IsMobsFrozen(): boolean
	return mobsAreFrozen()
end

-- Fire an arrow projectile from a ranged mob toward a target character.
local function fireArrow(originMob: Model, fromPos: Vector3, targetChar: Model, damage: number)
	local targetRoot = targetChar:FindFirstChild("HumanoidRootPart")
	if not targetRoot then return end

	local arrow = Instance.new("Part")
	arrow.Name = "SkeletonArrow"
	arrow.Size = Vector3.new(0.18, 0.18, 2.5)
	arrow.Color = Color3.fromRGB(95, 65, 35)
	arrow.Material = Enum.Material.Wood
	arrow.Anchored = true
	arrow.CanCollide = false
	arrow.CanQuery = false
	arrow.CanTouch = false
	arrow.CFrame = CFrame.lookAt(fromPos, targetRoot.Position)
	arrow.Parent = Workspace

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { originMob, arrow }

	local speed = 95
	local maxLife = 3
	local elapsed = 0
	local last = os.clock()

	local conn
	conn = RunService.Heartbeat:Connect(function()
		if not arrow.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local now = os.clock()
		local dt = math.min(now - last, 0.1)
		last = now
		elapsed += dt
		local move = speed * dt
		local result = Workspace:Raycast(arrow.Position, arrow.CFrame.LookVector * move, params)
		if result and result.Instance then
			local hitChar = result.Instance:FindFirstAncestorOfClass("Model")
			local hum = hitChar and hitChar:FindFirstChildOfClass("Humanoid")
			local plr = hitChar and Players:GetPlayerFromCharacter(hitChar)
			if hum and plr and plr:GetAttribute("InLobby") ~= true then
				hum:TakeDamage(damage)
			end
			arrow:Destroy()
			if conn then conn:Disconnect() end
			return
		end
		arrow.CFrame = arrow.CFrame + arrow.CFrame.LookVector * move
		if elapsed >= maxLife then
			arrow:Destroy()
			if conn then conn:Disconnect() end
		end
	end)
end

-- Configure a rigged, animation-driven mob (melee chaser or ranged archer).
local function configureAnimatedMob(mobModel: Model, humanoid: Humanoid, targetCFrame: CFrame, isBoss: boolean, onDied: (() -> ())?)
	local mobType = mobModel:GetAttribute("MobType") or "Melee"
	local damage = mobModel:GetAttribute("Damage") or (isBoss and 25 or 10)
	local walkSpeed = mobModel:GetAttribute("WalkSpeed") or (isBoss and 10 or 12)
	local aggroRange = mobModel:GetAttribute("AggroRange") or 70
	local attackRange = mobModel:GetAttribute("AttackRange") or 5
	local preferredRange = mobModel:GetAttribute("PreferredRange") or 35
	local cooldown = mobModel:GetAttribute("AttackCooldown") or 1
	local xpReward = mobModel:GetAttribute("XP") or (isBoss and 100 or 25)

	-- Scale with the run difficulty tier.
	local diffScale = DifficultyManager.GetMobScale()
	damage = damage * diffScale.damage
	walkSpeed = walkSpeed * diffScale.speed
	xpReward = math.floor(xpReward * (1 + diffScale.tier * 0.15))

	humanoid.WalkSpeed = walkSpeed
	humanoid.RequiresNeck = false
	humanoid.PlatformStand = false

	local rootPart = mobModel:FindFirstChild("HumanoidRootPart")
	if not rootPart then
		rootPart = mobModel.PrimaryPart
	end
	if not rootPart then
		local boundCF = mobModel:GetBoundingBox()
		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2, 2, 1)
		rootPart.Transparency = 1
		rootPart.CFrame = boundCF
		rootPart.Parent = mobModel
	end
	mobModel.PrimaryPart = rootPart
	rootPart.CanQuery = true

	for _, part in ipairs(mobModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	local _, extents = mobModel:GetBoundingBox()
	local finalPos = targetCFrame.Position + Vector3.new(0, (extents.Y * 0.5) + 1, 0)
	mobModel:PivotTo(CFrame.new(finalPos) * targetCFrame.Rotation)
	humanoid.HipHeight = 0

	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local animFolder = mobModel:FindFirstChild("Animations")
	local walkAnim = animFolder and animFolder:FindFirstChild("Walk")
	local attackAnim = animFolder and animFolder:FindFirstChild("Attack")

	local walkTrack = nil
	local attackTrack = nil
	if walkAnim and walkAnim:IsA("Animation") then
		walkTrack = animator:LoadAnimation(walkAnim)
		walkTrack.Priority = Enum.AnimationPriority.Movement
		walkTrack.Looped = true
	end
	if attackAnim and attackAnim:IsA("Animation") then
		attackTrack = animator:LoadAnimation(attackAnim)
		attackTrack.Priority = Enum.AnimationPriority.Action
		attackTrack.Looped = false
	end

	-- Ranged mobs get a bow welded to their right hand, unless the template already ships one
	if mobType == "Ranged" and mobModel:FindFirstChild("Bow") == nil then
		local hand = mobModel:FindFirstChild("RightHand") or mobModel:FindFirstChild("Right Arm") or mobModel:FindFirstChild("RightLowerArm")
		if hand and hand:IsA("BasePart") then
			local bow = Instance.new("Part")
			bow.Name = "Bow"
			bow.Size = Vector3.new(0.25, 3, 0.25)
			bow.Color = Color3.fromRGB(80, 55, 30)
			bow.Material = Enum.Material.Wood
			bow.CanCollide = false
			bow.Massless = true
			bow.CFrame = hand.CFrame
			bow.Parent = mobModel
			local wc = Instance.new("WeldConstraint")
			wc.Part0 = hand
			wc.Part1 = bow
			wc.Parent = bow
		end
	end

	createMobHealthBar(mobModel, humanoid, rootPart, extents, isBoss)

	local lastAttack = 0
	local lastRepath = 0
	local lastTick = os.clock()
	local walkPlaying = false
	local function setWalk(on)
		if not walkTrack then return end
		if on and not walkPlaying then
			walkTrack:Play()
			walkPlaying = true
		elseif not on and walkPlaying then
			walkTrack:Stop()
			walkPlaying = false
		end
	end

	local function getTarget()
		local mobPos = rootPart.Position
		local closest = nil
		local closestDist = aggroRange
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr:GetAttribute("InLobby") ~= true then
				local char = plr.Character
				if char and char.Parent then
					local hum = char:FindFirstChildOfClass("Humanoid")
					local pr = char:FindFirstChild("HumanoidRootPart")
					if hum and pr and hum.Health > 0 then
						local d = (pr.Position - mobPos).Magnitude
						if d < closestDist then
							closestDist = d
							closest = char
						end
					end
				end
			end
		end
		return closest, closestDist
	end

	local function damagePlayer(targetChar: Model)
		local hum = targetChar:FindFirstChildOfClass("Humanoid")
		local pr = targetChar:FindFirstChild("HumanoidRootPart")
		if not hum or not pr or hum.Health <= 0 then return end
		local plr = Players:GetPlayerFromCharacter(targetChar)
		if not plr or plr:GetAttribute("InLobby") == true then return end
		hum:TakeDamage(damage)
		local diff = pr.Position - rootPart.Position
		local pushDir = diff.Magnitude > 0.1 and diff.Unit or Vector3.new(1, 0, 0)
		pr:ApplyImpulse((pushDir + Vector3.new(0, 0.25, 0)).Unit * (pr.AssemblyMass * 12))
	end

	task.spawn(function()
		while mobModel.Parent and humanoid.Health > 0 do
			task.wait(0.2)
			if not rootPart.Parent then break end
			if mobsAreFrozen() then
				humanoid:Move(Vector3.zero)
				humanoid.WalkSpeed = 0
				setWalk(false)
				repeat task.wait(0.1) until not mobsAreFrozen() or not mobModel.Parent or humanoid.Health <= 0
				if mobModel.Parent and humanoid.Health > 0 then
					humanoid.WalkSpeed = walkSpeed
				end
				continue
			end
			if Workspace:GetAttribute("TomesPaused") == true then
				humanoid:Move(Vector3.zero)
				humanoid.WalkSpeed = 0
				setWalk(false)
				rootPart.Anchored = true
				repeat task.wait(0.1) until Workspace:GetAttribute("TomesPaused") ~= true or not mobModel.Parent or humanoid.Health <= 0
				if mobModel.Parent and humanoid.Health > 0 and rootPart.Parent then
					humanoid.WalkSpeed = walkSpeed
					rootPart.Anchored = false
				end
				continue
			end

			local target, dist = getTarget()
			if target then
				local tRoot = target:FindFirstChild("HumanoidRootPart")
				if tRoot then
					if mobType == "Ranged" then
						local tnow = os.clock()
						local dt = math.max(tnow - lastTick, 0.001)
						lastTick = tnow

						-- Commit to a destination and only repath every ~0.6s so the mob walks a
						-- smooth path instead of live-tracking the player's position every tick.
						local moving = false
						if dist > preferredRange + 4 then
							if tnow - lastRepath >= 0.6 then
								humanoid:MoveTo(tRoot.Position)
								lastRepath = tnow
							end
							moving = true
							setWalk(true)
						elseif dist < preferredRange - 8 then
							if tnow - lastRepath >= 0.6 then
								local away = rootPart.Position + (rootPart.Position - tRoot.Position).Unit * 14
								humanoid:MoveTo(away)
								lastRepath = tnow
							end
							moving = true
							setWalk(true)
						else
							humanoid:Move(Vector3.zero)
							setWalk(false)
						end

						-- Smoothly turn to face the target while holding position, instead of
						-- snapping the CFrame every tick. While walking, the Humanoid rotates us.
						if not moving then
							local flat = Vector3.new(tRoot.Position.X, rootPart.Position.Y, tRoot.Position.Z)
							if (flat - rootPart.Position).Magnitude > 0.1 then
								local desiredRot = CFrame.lookAt(rootPart.Position, flat) - rootPart.Position
								local currentRot = rootPart.CFrame - rootPart.Position
								local alpha = 1 - math.exp(-4 * dt)
								rootPart.CFrame = CFrame.new(rootPart.Position) * currentRot:Lerp(desiredRot, alpha)
							end
						end

						local now = os.clock()
						if dist <= preferredRange + 15 and now - lastAttack >= cooldown then
							lastAttack = now
							humanoid:Move(Vector3.zero)
							setWalk(false)
							if attackTrack then attackTrack:Play() end
							task.delay(0.4, function()
								if mobModel.Parent and humanoid.Health > 0 and rootPart.Parent then
									fireArrow(mobModel, rootPart.Position + rootPart.CFrame.LookVector * 2 + Vector3.new(0, 1, 0), target, damage)
								end
							end)
						end
					else
						humanoid:MoveTo(tRoot.Position)
						setWalk(true)
						if dist <= attackRange then
							humanoid:Move(Vector3.zero)
							setWalk(false)
							local now = os.clock()
							if now - lastAttack >= cooldown then
								lastAttack = now
								if attackTrack then attackTrack:Play() end
								damagePlayer(target)
							end
						end
					end
				end
			else
				setWalk(false)
			end
		end
	end)

	local deadTriggered = false
	humanoid.Died:Connect(function()
		if deadTriggered then return end
		deadTriggered = true
		setWalk(false)
		if onDied then onDied() end

		local pos = (rootPart and rootPart.Position) or mobModel:GetPivot().Position
		triggerBlueStarDeathVFX(pos)
		for _, player in ipairs(Players:GetPlayers()) do
			local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if player:GetAttribute("InLobby") ~= true and playerRoot and (playerRoot.Position - pos).Magnitude <= 120 then
				PlayerStats.AwardXP(player, xpReward)
			end
		end

		task.spawn(function()
			for _, desc in ipairs(mobModel:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.CanCollide = false
					TweenService:Create(desc, TweenInfo.new(0.8), { Transparency = 1 }):Play()
				end
			end
			task.wait(0.9)
			if mobModel and mobModel.Parent then
				mobModel:Destroy()
			end
		end)
	end)
end

local function configureMob(mobModel: Model, targetCFrame: CFrame, isBoss: boolean, initialHealth: number?, onDied: (() -> ())?)
	-- 1. Humanoid Setup
	local humanoid = mobModel:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		humanoid = Instance.new("Humanoid")
		humanoid.Parent = mobModel
	end

	humanoid.RequiresNeck = false
	local diffScale = DifficultyManager.GetMobScale()
	humanoid.WalkSpeed = (isBoss and 10 or 14) * diffScale.speed
	humanoid.PlatformStand = false
	local baseMax = isBoss and 400 or 100
	local maxHp = math.floor(baseMax * diffScale.health)
	humanoid.MaxHealth = maxHp
	local startHealth = initialHealth or baseMax
	if startHealth >= baseMax then
		humanoid.Health = maxHp
	else
		humanoid.Health = math.clamp(math.floor(startHealth * diffScale.health), 1, maxHp)
	end

	if mobModel:GetAttribute("MobType") ~= nil then
		configureAnimatedMob(mobModel, humanoid, targetCFrame, isBoss, onDied)
		return
	end

	-- 2. Find or Create HumanoidRootPart anchored at bounding box center
	local boundCF, extents = mobModel:GetBoundingBox()
	local rootPart = mobModel:FindFirstChild("HumanoidRootPart") :: BasePart?

	if not rootPart then
		rootPart = Instance.new("Part")
		rootPart.Name = "HumanoidRootPart"
		rootPart.Size = Vector3.new(2.5, 2.5, 2.5)
		rootPart.Transparency = 1
		rootPart.CanCollide = true
		rootPart.Massless = false
		rootPart.Anchored = true
		rootPart.CFrame = boundCF
		rootPart.Parent = mobModel
		mobModel.PrimaryPart = rootPart
	else
		mobModel.PrimaryPart = rootPart
		rootPart.CanCollide = true
		rootPart.Massless = false
		rootPart.Anchored = true
	end
	rootPart.CanTouch = false
	rootPart.CanQuery = true

	-- 3. Weld EVERY MeshPart/BasePart to HumanoidRootPart while still at original relative positions
	for _, part in ipairs(mobModel:GetDescendants()) do
		if part:IsA("BasePart") and part ~= rootPart then
			part.Massless = true
			part.CanCollide = false
			part.CanTouch = false
			part.CanQuery = false

			local alreadyWelded = false
			for _, child in ipairs(part:GetChildren()) do
				if (child:IsA("WeldConstraint") or child:IsA("Weld") or child:IsA("Motor6D")) and (child.Part0 == rootPart or child.Part1 == rootPart) then
					alreadyWelded = true
					break
				end
			end
			if not alreadyWelded then
				for _, child in ipairs(rootPart:GetChildren()) do
					if (child:IsA("WeldConstraint") or child:IsA("Weld")) and (child.Part0 == part or child.Part1 == part) then
						alreadyWelded = true
						break
					end
				end
			end

			if not alreadyWelded then
				local wc = Instance.new("WeldConstraint")
				wc.Part0 = rootPart
				wc.Part1 = part
				wc.Parent = rootPart
			end
		end
	end

	-- 4. Move model to destination spawn CFrame (raising 2 studs above floor)
	local heightOffsetY = (extents.Y * 0.5) + 0.5
	local finalPos = targetCFrame.Position + Vector3.new(0, heightOffsetY, 0)
	local finalCF = CFrame.new(finalPos) * targetCFrame.Rotation
	mobModel:PivotTo(finalCF)

	-- 5. Unanchor everything now that all parts are securely welded together
	for _, part in ipairs(mobModel:GetDescendants()) do
		if part:IsA("BasePart") then
			part.Anchored = false
		end
	end

	humanoid.HipHeight = 0.5

	-- Attach overhead Health Bar
	createMobHealthBar(mobModel, humanoid, rootPart, extents, isBoss)

	-- 6. Mob Chase AI & Contact Touch Damage
	local lastAttackTime = 0
	local function tryDealDamage(targetChar: Model)
		local hum = targetChar:FindFirstChildOfClass("Humanoid")
		local pRoot = targetChar:FindFirstChild("HumanoidRootPart")
		if not hum or not pRoot or hum.Health <= 0 then return end

		local plr = Players:GetPlayerFromCharacter(targetChar)
		if not plr or plr:GetAttribute("InLobby") == true then return end

		local now = os.clock()
		if now - lastAttackTime < 0.85 then return end
		lastAttackTime = now

		local damage = (isBoss and 25 or 10) * DifficultyManager.GetMobScale().damage
		hum:TakeDamage(damage)

		-- Apply knockback push to player
		local diff = pRoot.Position - rootPart.Position
		local pushDir = diff.Magnitude > 0.1 and diff.Unit or Vector3.new(1, 0, 0)
		pRoot:ApplyImpulse((pushDir + Vector3.new(0, 0.25, 0)).Unit * (pRoot.AssemblyMass * 14))
		print(`[MobManager] Mob '{mobModel.Name}' hit player {plr.Name} for {damage} damage!`)
	end

	-- Run Chase AI Loop
	task.spawn(function()
		while mobModel.Parent and humanoid.Health > 0 do
			task.wait(0.35)
			if not rootPart.Parent then break end
			if mobsAreFrozen() then
				humanoid:Move(Vector3.zero)
				humanoid.WalkSpeed = 0
				rootPart.Anchored = true
				repeat task.wait(0.1) until not mobsAreFrozen() or not mobModel.Parent or humanoid.Health <= 0
				if mobModel.Parent and humanoid.Health > 0 and rootPart.Parent then
					humanoid.WalkSpeed = isBoss and 10 or 14
					rootPart.Anchored = false
				end
				continue
			end
			if Workspace:GetAttribute("TomesPaused") == true then
				humanoid:Move(Vector3.zero)
				rootPart.Anchored = true
				repeat task.wait(0.1) until Workspace:GetAttribute("TomesPaused") ~= true or not mobModel.Parent or humanoid.Health <= 0
				if rootPart.Parent then rootPart.Anchored = false end
				continue
			end

			local mobPos = rootPart.Position
			local closestPlayerChar: Model? = nil
			local closestDist = 75 -- Aggro range

			for _, plr in ipairs(Players:GetPlayers()) do
				if plr:GetAttribute("InLobby") ~= true then
					local char = plr.Character
					if char and char.Parent then
						local hum = char:FindFirstChildOfClass("Humanoid")
						local pRoot = char:FindFirstChild("HumanoidRootPart")
						if hum and pRoot and hum.Health > 0 then
							local dist = (pRoot.Position - mobPos).Magnitude
							if dist < closestDist then
								closestDist = dist
								closestPlayerChar = char
							end
						end
					end
				end
			end

			if closestPlayerChar and closestPlayerChar.Parent then
				local pRoot = closestPlayerChar:FindFirstChild("HumanoidRootPart")
				if pRoot then
					humanoid:MoveTo(pRoot.Position)

					-- If in close contact range, deal damage
					local hitRadius = isBoss and 7.5 or 4.5
					if (pRoot.Position - mobPos).Magnitude <= hitRadius then
						tryDealDamage(closestPlayerChar)
					end
				end
			end
		end
	end)

	-- 7. Connect death event for Blue Star VFX
	local deadTriggered = false
	humanoid.Died:Connect(function()
		if deadTriggered then return end
		deadTriggered = true
		if onDied then
			onDied()
		end

		local pos = (rootPart and rootPart.Position) or mobModel:GetPivot().Position
		print(`[MobManager] Mob '{mobModel.Name}' died at {pos} — spawning Blue Star VFX!`)

		triggerBlueStarDeathVFX(pos)
		local xpReward = isBoss and 100 or 25
		for _, player in ipairs(Players:GetPlayers()) do
			local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if player:GetAttribute("InLobby") ~= true and playerRoot and (playerRoot.Position - pos).Magnitude <= 120 then
				PlayerStats.AwardXP(player, xpReward)
			end
		end

		task.spawn(function()
			for _, desc in ipairs(mobModel:GetDescendants()) do
				if desc:IsA("BasePart") then
					desc.CanCollide = false
					TweenService:Create(desc, TweenInfo.new(0.8), { Transparency = 1 }):Play()
				end
			end
			task.wait(0.9)
			if mobModel and mobModel.Parent then
				mobModel:Destroy()
			end
		end)
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Room-aware spawning. Only rooms near a non-lobby player have live mob instances.
-- ─────────────────────────────────────────────────────────────────────────────
local function roomIsNearAnActivePlayer(room: any): boolean
	local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE * 0.5 - ROOM_ACTIVATION_PADDING
	local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5 + ROOM_ACTIVATION_PADDING
	local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE * 0.5 - ROOM_ACTIVATION_PADDING
	local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5 + ROOM_ACTIVATION_PADDING

	for _, player in ipairs(Players:GetPlayers()) do
		if player:GetAttribute("InLobby") ~= true then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and root.Position.X >= minX and root.Position.X <= maxX and root.Position.Z >= minZ and root.Position.Z <= maxZ then
				return true
			end
		end
	end
	return false
end

local function activateMob(record: MobRecord)
	if record.defeated or record.model or not activeMobsFolder then return end

	local model = record.template and record.template:Clone() or createFallbackMob()
	model.Parent = activeMobsFolder
	record.model = model
	configureMob(model, record.spawnCFrame, record.isBoss, record.health, function()
		record.defeated = true
		record.model = nil
	end)
end

local function deactivateMob(record: MobRecord)
	local model = record.model
	if not model then return end

	local humanoid = model:FindFirstChildOfClass("Humanoid")
	if humanoid and humanoid.Health > 0 then
		record.health = humanoid.Health
	end
	record.model = nil
	model:Destroy()
end

local function refreshActiveRooms()
	for _, group in ipairs(roomMobGroups) do
		local shouldBeActive = roomIsNearAnActivePlayer(group.room)
		for _, record in ipairs(group.mobs) do
			if shouldBeActive then
				activateMob(record)
			else
				deactivateMob(record)
			end
		end
	end
end

function MobManager.SpawnRoomMobs(rooms: { any })
	MobManager.Clear()

	local mobsFolder = Instance.new("Folder")
	mobsFolder.Name = "Mobs"
	mobsFolder.Parent = Workspace
	activeMobsFolder = mobsFolder

	local normalTemplates, bossTemplates = getMobTemplates()
	local plannedCount = 0
	for _, room in ipairs(rooms) do
		if room.id == 1 or room.roomType == "Start" or room.roomType == "Rest" or room.roomType == "Treasure" or room.roomType == "Shop" then continue end

		local group: RoomMobGroup = { room = room, mobs = {} }
		table.insert(roomMobGroups, group)
		local minX = room.gx * FLOOR_SIZE + 4
		local maxX = (room.gx + room.w - 1) * FLOOR_SIZE - 4
		local minZ = room.gz * FLOOR_SIZE + 4
		local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE - 4
		local remaining = MOBS_PER_ROOM

		if room.roomType == "Boss" and #bossTemplates > 0 then
			table.insert(group.mobs, {
				template = bossTemplates[math.random(1, #bossTemplates)],
				spawnCFrame = CFrame.new((room.gx + room.w / 2) * FLOOR_SIZE, room.floorY, (room.gz + room.d / 2) * FLOOR_SIZE),
				isBoss = true,
				health = 400,
				defeated = false,
				model = nil,
			})
			remaining -= 1
		end

		for _ = 1, remaining do
			table.insert(group.mobs, {
				template = #normalTemplates > 0 and normalTemplates[math.random(1, #normalTemplates)] or nil,
				spawnCFrame = CFrame.new(math.random(math.floor(minX), math.floor(maxX)), room.floorY, math.random(math.floor(minZ), math.floor(maxZ))) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0),
				isBoss = false,
				health = 100,
				defeated = false,
				model = nil,
			})
		end
		plannedCount += #group.mobs
	end

	refreshActiveRooms()
	task.spawn(function()
		while activeMobsFolder == mobsFolder and mobsFolder.Parent do
			task.wait(ROOM_REFRESH_INTERVAL)
			refreshActiveRooms()
		end
	end)
	print(`[MobManager] Prepared {plannedCount} mobs; only nearby rooms are active ({MOBS_PER_ROOM} per room).`)
end

function MobManager.Clear()
	roomMobGroups = {}
	if activeMobsFolder and activeMobsFolder.Parent then
		activeMobsFolder:Destroy()
		activeMobsFolder = nil
	end
	local existing = Workspace:FindFirstChild("Mobs")
	if existing then
		existing:Destroy()
	end
end

function MobManager.Init()
	print("[MobManager] Server MobManager initialized.")
end

return MobManager
