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
local TalentManager = require(script.Parent:WaitForChild("TalentManager"))
local GachaManager = require(script.Parent:WaitForChild("GachaManager"))
local PartyManager = require(script.Parent:WaitForChild("PartyManager"))

-- Cursed Tomes make mobs hit that player harder (their "difficulty" stat;
-- 1 = normal). The matching XP / gold bonus lives in the same tome.
local function curseScale(player: Player): number
	local d = PlayerStats.GetStat(player, "difficulty")
	return if d > 0 then d else 1
end
local DifficultyManager = require(script.Parent:WaitForChild("DifficultyManager"))
local BossAI = require(script.Parent:WaitForChild("BossAI"))
local DragonBoss = require(script.Parent:WaitForChild("DragonBoss"))
local MobKinds = require(script.Parent:WaitForChild("MobKinds"))
local TomeData = require(Shared:WaitForChild("TomeData"))

local MobManager = {}

local activeMobsFolder: Folder? = nil
local FLOOR_SIZE = 12
local MOBS_BASE = 7            -- mobs in a room at Threat I
local MOBS_PER_TIER = 2        -- +2 per Threat tier
local MOBS_MAX = 24
local ELITE_BASE_CHANCE = 0.03 -- per mob, at Threat I
local ELITE_CHANCE_PER_TIER = 0.01
local ELITE_MAX_CHANCE = 0.15
local ROOM_ACTIVATION_PADDING = 36
local ROOM_REFRESH_INTERVAL = 0.75

type MobRecord = {
	template: Model?,
	spawnCFrame: CFrame,
	isBoss: boolean,
	isElite: boolean?,
	bossKind: string?,
	kind: string?,  -- MobKinds id (its look, stats and moves)
	affix: string?, -- an elite's trait
	summoned: boolean?, -- brought by another mob (risen dead, slimelings)
	group: any,
	health: number,
	defeated: boolean,
	model: Model?,
}

type RoomMobGroup = {
	room: any,
	mobs: { MobRecord },
	planned: boolean,
	emblem: any,
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
local function triggerBlueStarDeathVFX(position: Vector3, isBoss: boolean?)
	pcall(function()
		local deathRemote = Network.GetRemoteEvent(Network.Remotes.MobDeathVFX)
		for _, player in ipairs(Players:GetPlayers()) do
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and (root.Position - position).Magnitude <= 100 then
				deathRemote:FireClient(player, { position = position, isBoss = isBoss == true })
			end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Mob Health Bar (BillboardGui over Mob Head)
-- ─────────────────────────────────────────────────────────────────────────────
local function displayName(mobModel: Model, isBoss: boolean): string
	local named = mobModel:GetAttribute("DisplayName")
	if typeof(named) == "string" then return named end
	if isBoss then return "★ Slime Boss" end
	return if mobModel:GetAttribute("IsElite") == true then `Elite {mobModel.Name}` else mobModel.Name
end

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
	bgStroke.Color = if isBoss then Color3.fromRGB(255, 180, 50)
		elseif mobModel:GetAttribute("IsElite") == true then Color3.fromRGB(170, 70, 255)
		else Color3.fromRGB(60, 60, 70)
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
	nameLabel.Text = `{displayName(mobModel, isBoss)}\n{math.ceil(humanoid.Health)} / {math.ceil(humanoid.MaxHealth)} HP`
	nameLabel.Parent = bg

	-- Update on health change
	humanoid.HealthChanged:Connect(function(health)
		local alpha = math.clamp(health / humanoid.MaxHealth, 0, 1)
		TweenService:Create(fill, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = UDim2.new(alpha, -6, 0, 8)
		}):Play()
		nameLabel.Text = `{displayName(mobModel, isBoss)}\n{math.max(0, math.ceil(health))} / {math.ceil(humanoid.MaxHealth)} HP`

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

-- ─────────────────────────────────────────────────────────────────────────────
-- Decoys (e.g. Ice Mage clone): any mob within a decoy's taunt radius drops its
-- current target and attacks the decoy instead.
-- ─────────────────────────────────────────────────────────────────────────────
local decoys: { [Model]: number } = {}

function MobManager.RegisterDecoy(model: Model, tauntRadius: number)
	decoys[model] = tauntRadius
	model.AncestryChanged:Connect(function(_, parent)
		if not parent then decoys[model] = nil end
	end)
end

function MobManager.UnregisterDecoy(model: Model)
	decoys[model] = nil
end

local function findDecoyTarget(mobPos: Vector3): (Model?, number)
	local best, bestDist = nil, math.huge
	for model, radius in pairs(decoys) do
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if model.Parent and hum and root and hum.Health > 0 then
			local d = (root.Position - mobPos).Magnitude
			if d <= radius and d < bestDist then
				best, bestDist = model, d
			end
		end
	end
	return best, bestDist
end

local function isDecoy(model: Model?): boolean
	return model ~= nil and decoys[model] ~= nil
end

-- Parry (Swordsman, Fire Knight): class servers register hooks that return
-- true when `targetChar` is mid-parry for their class; the attack is then
-- negated and the hook handles the stun + counter on `attacker`.
local parryHooks: { (Model, Model?) -> boolean } = {}
function MobManager.SetParryHook(fn: (Model, Model?) -> boolean)
	table.insert(parryHooks, fn)
end
MobManager.AddParryHook = MobManager.SetParryHook
local function parried(targetChar: Model, attacker: Model?): boolean
	if (targetChar:GetAttribute("ParryUntil") or 0) <= os.clock() then return false end
	for _, hook in ipairs(parryHooks) do
		if hook(targetChar, attacker) then return true end
	end
	return false
end

-- Incoming damage to a player (e.g. the Fire Knight's guard soaking hits into
-- Heat): each hook may return a reduced amount.
local incomingHooks: { (Player, Model, number) -> number } = {}
function MobManager.AddIncomingHook(fn: (Player, Model, number) -> number)
	table.insert(incomingHooks, fn)
end
local function incoming(plr: Player, targetChar: Model, damage: number): number
	for _, hook in ipairs(incomingHooks) do
		damage = hook(plr, targetChar, damage)
	end
	return damage
end

-- An Overheated Fire Knight can't be knocked around ("Unstoppable").
local function knockable(targetChar: Model): boolean
	return targetChar:GetAttribute("Unstoppable") ~= true
end

-- Freeze a single mob solid for a moment (Ice Mage spikes/beam/clone shockwave).
function MobManager.ChillMob(mobModel: Model, duration: number)
	local rootPart = mobModel:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = mobModel:FindFirstChildOfClass("Humanoid")
	if not rootPart or not hum or hum.Health <= 0 then return end
	if Players:GetPlayerFromCharacter(mobModel) or isDecoy(mobModel) then return end
	local untilTime = os.clock() + duration
	if (mobModel:GetAttribute("ChilledUntil") or 0) >= untilTime then return end
	mobModel:SetAttribute("ChilledUntil", untilTime)
	rootPart.Anchored = true
	task.delay(duration, function()
		if not rootPart.Parent then return end
		if (mobModel:GetAttribute("ChilledUntil") or 0) > os.clock() then return end
		if Workspace:GetAttribute("TomesPaused") == true then return end
		rootPart.Anchored = false
	end)
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
	arrow:AddTag("EnemyProjectile") -- (outlined white on every client: readable in the dark)
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
			if hum and ((plr and plr:GetAttribute("InLobby") ~= true) or isDecoy(hitChar)) then
				if not (plr and hitChar and parried(hitChar, originMob)) then
					hum:TakeDamage(if plr and hitChar then incoming(plr, hitChar, damage) else damage)
				end
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

	-- Scale with the run difficulty tier (and elite / boss multipliers).
	local diffScale = DifficultyManager.GetMobScale()
	damage = damage * diffScale.damage * (mobModel:GetAttribute("DamageMult") or 1)
	xpReward *= mobModel:GetAttribute("XPMult") or 1
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
		local decoy, decoyDist = findDecoyTarget(mobPos)
		if decoy then return decoy, decoyDist end
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
		if isDecoy(targetChar) then
			hum:TakeDamage(damage)
			return
		end
		local plr = Players:GetPlayerFromCharacter(targetChar)
		if not plr or plr:GetAttribute("InLobby") == true then return end
		if (targetChar:GetAttribute("InvulnerableUntil") or 0) > os.clock() then return end -- dodge i-frames
		if parried(targetChar, mobModel) then return end
		local dealt = incoming(plr, targetChar, damage * curseScale(plr))
		hum:TakeDamage(dealt)
		MobKinds.OnDealt(mobModel, dealt)
		if not knockable(targetChar) then return end
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

			if (mobModel:GetAttribute("ChilledUntil") or 0) > os.clock() then
				setWalk(false)
				continue
			end
			-- Staggered by a hit: skip the turn so MoveTo doesn't cancel the knockback.
			if (mobModel:GetAttribute("StaggerUntil") or 0) > os.clock() then
				setWalk(false)
				continue
			end
			-- A boss (BossAI) or a mob (MobKinds) mid-move drives itself.
			if mobModel:GetAttribute("BossBusy") == true or mobModel:GetAttribute("MobBusy") == true then
				setWalk(false)
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
						-- (casters throw their own spells: MobKinds)
						if mobModel:GetAttribute("NoArrows") ~= true and dist <= preferredRange + 15 and now - lastAttack >= cooldown then
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
		local pos = (rootPart and rootPart.Position) or mobModel:GetPivot().Position
		-- (before the room counts it: what it leaves behind keeps the room open)
		MobKinds.OnDied(mobModel, pos)
		if onDied then onDied() end

		triggerBlueStarDeathVFX(pos, isBoss)
		-- XP is shared: nearby players plus their co-op party members in the run.
		local nearby: { Player } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if player:GetAttribute("InLobby") ~= true and playerRoot and (playerRoot.Position - pos).Magnitude <= 120 then
				table.insert(nearby, player)
			end
		end
		for _, player in ipairs(PartyManager.XPRecipients(nearby)) do
			PlayerStats.AwardXP(player, xpReward)
		end
		for _, player in ipairs(nearby) do
			-- Gold funds the shop and the gambling den.
			PlayerStats.AwardGold(player, if isBoss then math.random(60, 90) elseif mobModel:GetAttribute("IsElite") == true then math.random(15, 25) else math.random(3, 7))
			TalentManager.OnMobKilled(player, isBoss)
			GachaManager.OnMobKilled(player, isBoss)
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
	local walkSpeed = (mobModel:GetAttribute("WalkSpeed") or (isBoss and 10 or 14)) * diffScale.speed
	humanoid.WalkSpeed = walkSpeed
	humanoid.PlatformStand = false
	local baseMax = (isBoss and 400 or 100) * (mobModel:GetAttribute("HealthMult") or 1)
	local maxHp = math.floor(baseMax * diffScale.health)
	humanoid.MaxHealth = maxHp
	local startHealth = initialHealth or math.huge
	if startHealth >= maxHp then
		humanoid.Health = maxHp
	else
		humanoid.Health = math.clamp(math.floor(startHealth), 1, maxHp)
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
		local decoyTarget = isDecoy(targetChar)
		if not decoyTarget and (not plr or plr:GetAttribute("InLobby") == true) then return end

		local now = os.clock()
		if now - lastAttackTime < 0.85 then return end
		lastAttackTime = now

		if not decoyTarget and (targetChar:GetAttribute("InvulnerableUntil") or 0) > os.clock() then return end -- dodge i-frames
		if not decoyTarget and parried(targetChar, mobModel) then return end
		local damage = (isBoss and 25 or 10) * DifficultyManager.GetMobScale().damage * (mobModel:GetAttribute("DamageMult") or 1)
		if plr and not decoyTarget then damage = incoming(plr, targetChar, damage * curseScale(plr)) end
		hum:TakeDamage(damage)
		MobKinds.OnDealt(mobModel, damage)
		if decoyTarget or not knockable(targetChar) then return end

		-- Apply knockback push to player
		local diff = pRoot.Position - rootPart.Position
		local pushDir = diff.Magnitude > 0.1 and diff.Unit or Vector3.new(1, 0, 0)
		pRoot:ApplyImpulse((pushDir + Vector3.new(0, 0.25, 0)).Unit * (pRoot.AssemblyMass * 14))
		print(`[MobManager] Mob '{mobModel.Name}' hit player {(plr :: Player).Name} for {damage} damage!`)
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
					humanoid.WalkSpeed = walkSpeed
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

			if (mobModel:GetAttribute("ChilledUntil") or 0) > os.clock() then continue end
			if (mobModel:GetAttribute("StaggerUntil") or 0) > os.clock() then continue end
			if mobModel:GetAttribute("BossBusy") == true or mobModel:GetAttribute("MobBusy") == true then continue end

			local mobPos = rootPart.Position
			local closestPlayerChar: Model? = nil
			local closestDist = 75 -- Aggro range

			local decoy = findDecoyTarget(mobPos)
			if decoy then closestPlayerChar = decoy end

			for _, plr in ipairs(if decoy then {} else Players:GetPlayers()) do
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

					-- If in close contact range, deal damage (a Magma Slime
					-- only hurts when it bursts)
					local hitRadius = (isBoss and 7.5 or 4.5) * mobModel:GetScale()
					if mobModel:GetAttribute("NoContact") ~= true and (pRoot.Position - mobPos).Magnitude <= hitRadius then
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
		local pos = (rootPart and rootPart.Position) or mobModel:GetPivot().Position
		MobKinds.OnDied(mobModel, pos)
		if onDied then
			onDied()
		end

		print(`[MobManager] Mob '{mobModel.Name}' died at {pos} — spawning Blue Star VFX!`)

		triggerBlueStarDeathVFX(pos, isBoss)
		local xpReward = (isBoss and 100 or 25) * (mobModel:GetAttribute("XPMult") or 1)
		-- XP is shared: nearby players plus their co-op party members in the run.
		local nearby: { Player } = {}
		for _, player in ipairs(Players:GetPlayers()) do
			local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if player:GetAttribute("InLobby") ~= true and playerRoot and (playerRoot.Position - pos).Magnitude <= 120 then
				table.insert(nearby, player)
			end
		end
		for _, player in ipairs(PartyManager.XPRecipients(nearby)) do
			PlayerStats.AwardXP(player, xpReward)
		end
		for _, player in ipairs(nearby) do
			-- Gold funds the shop and the gambling den.
			PlayerStats.AwardGold(player, if isBoss then math.random(60, 90) elseif mobModel:GetAttribute("IsElite") == true then math.random(15, 25) else math.random(3, 7))
			TalentManager.OnMobKilled(player, isBoss)
			GachaManager.OnMobKilled(player, isBoss)
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

-- Elites: tougher, hit harder, a bit bigger, wreathed in purple flames.
local ELITE_HEALTH = 3
local ELITE_DAMAGE = 1.6
local ELITE_XP = 3
local ELITE_SCALE = 1.2
local ELITE_PURPLE = Color3.fromRGB(170, 70, 255)

local function addEliteAura(model: Model)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root or not root:IsA("BasePart") then return end
	local fire = Instance.new("Fire")
	fire.Name = "EliteFlames"
	fire.Color = ELITE_PURPLE
	fire.SecondaryColor = Color3.fromRGB(60, 10, 120)
	fire.Size = 7
	fire.Heat = 12
	fire.Parent = root
	local att = Instance.new("Attachment")
	att.Name = "EliteAura"
	att.Position = Vector3.new(0, -1.5, 0)
	att.Parent = root
	local wisps = Instance.new("ParticleEmitter")
	wisps.Texture = "rbxasset://textures/particles/fire_main.dds"
	wisps.Color = ColorSequence.new(Color3.fromRGB(215, 140, 255), ELITE_PURPLE)
	wisps.LightEmission = 1
	wisps.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0) })
	wisps.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	wisps.Lifetime = NumberRange.new(0.5, 0.9)
	wisps.Speed = NumberRange.new(3, 6)
	wisps.SpreadAngle = Vector2.new(25, 25)
	wisps.Acceleration = Vector3.new(0, 6, 0)
	wisps.Rate = 30
	wisps.Parent = att
	local light = Instance.new("PointLight")
	light.Color = ELITE_PURPLE
	light.Brightness = 2
	light.Range = 12
	light.Parent = root
	local outline = Instance.new("Highlight")
	outline.Name = "EliteOutline"
	outline.FillTransparency = 1
	outline.OutlineColor = ELITE_PURPLE
	outline.OutlineTransparency = 0.2
	outline.Parent = model
end


local claimEmblem: (any, Player) -> ()

-- ── Room rewards ────────────────────────────────────────────────────────────
-- Each combat room holds a reward orb at its centre (Hades-boon style): a
-- glowing orb with a sigil inside and a beam of light, tinted by the blend of
-- the three buffs (tomes) it will offer. Every kill in the room charges it;
-- once the room is clear it blazes, and LEFT-CLICKING it shatters it into
-- sparks of its colour and gives every living player a level, offering those
-- buffs first.
local EMBLEM_DIM = Color3.fromRGB(70, 75, 95)
local SIGIL_INK = Color3.fromRGB(35, 12, 10)
local ORB_Y = 3.6

local function emblemPart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- The sigil: a ring, a six-pointed star of bars and a centre diamond, drawn
-- dark on the bright orb.
local function makeSigil(orb: BasePart)
	local bb = Instance.new("BillboardGui")
	bb.Name = "Sigil"
	bb.Size = UDim2.fromScale(2.6, 2.6)
	bb.LightInfluence = 0
	bb.AlwaysOnTop = false
	bb.Adornee = orb
	bb.Parent = orb
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.86, 0.86)
	ring.BackgroundTransparency = 1
	ring.Parent = bb
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.5, 0)
	rc.Parent = ring
	local rs = Instance.new("UIStroke")
	rs.Color = SIGIL_INK
	rs.Thickness = 3
	rs.Transparency = 0.15
	rs.Parent = ring
	for i = 0, 2 do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.new(0.08, 0, 0.72, 0)
		bar.Rotation = i * 60
		bar.BackgroundColor3 = SIGIL_INK
		bar.BackgroundTransparency = 0.1
		bar.BorderSizePixel = 0
		bar.Parent = bb
	end
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.26, 0.26)
	core.Rotation = 45
	core.BackgroundColor3 = SIGIL_INK
	core.BorderSizePixel = 0
	core.Parent = bb
end

local function createEmblem(group: RoomMobGroup)
	local room = group.room
	local pos = Vector3.new((room.gx + room.w / 2) * FLOOR_SIZE, room.floorY, (room.gz + room.d / 2) * FLOOR_SIZE)
	local buffs = PlayerStats.RollRewardBuffs()
	local color = TomeData.BlendColor(buffs)
	local model = Instance.new("Model")
	model.Name = "RoomReward"
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local base = emblemPart(model, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 6, 6),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.08, 0)) * flat, Color = EMBLEM_DIM, Transparency = 0.7 })
	local orb = emblemPart(model, { Name = "Orb", Shape = Enum.PartType.Ball, Size = Vector3.one * 3.2,
		CFrame = CFrame.new(pos + Vector3.new(0, ORB_Y, 0)), Color = EMBLEM_DIM, Transparency = 0.45 })
	orb.CanQuery = true -- clickable
	local core = emblemPart(model, { Name = "Core", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.8,
		CFrame = orb.CFrame, Color = EMBLEM_DIM:Lerp(Color3.new(1, 1, 1), 0.5), Transparency = 0.4 })
	local beam = emblemPart(model, { Name = "Beam", Shape = Enum.PartType.Cylinder, Size = Vector3.new(70, 0.35, 0.35),
		CFrame = CFrame.new(pos + Vector3.new(0, ORB_Y + 35, 0)) * flat, Color = color, Transparency = 0.9 })
	makeSigil(orb)
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, 0.4, 8
	light.Parent = orb
	local att = Instance.new("Attachment")
	att.Parent = orb
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.6, 1.2)
	sparks.Speed = NumberRange.new(2, 5)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 2
	sparks.Parent = att

	local click = Instance.new("ClickDetector")
	click.MaxActivationDistance = 40
	click.CursorIcon = ""
	click.Parent = orb

	model.PrimaryPart = orb
	local folder = Workspace:FindFirstChild("RoomEmblems")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "RoomEmblems"
		folder.Parent = Workspace
	end
	model.Parent = folder
	local e = { model = model, orb = orb, core = core, base = base, beam = beam, light = light, sparks = sparks,
		pos = pos, color = color, buffs = buffs, charge = 0, charged = false, claimed = false }
	group.emblem = e

	click.MouseClick:Connect(function(plr: Player)
		claimEmblem(group, plr)
	end)
	e.group = group

	-- Gentle bob; the core pulses faster as it charges.
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		if not model.Parent or e.claimed then
			if conn then conn:Disconnect() end
			return
		end
		local t = os.clock() - t0
		local cf = CFrame.new(pos + Vector3.new(0, ORB_Y + math.sin(t * 2) * 0.3, 0))
		orb.CFrame = cf
		local pulse = 1 + math.sin(t * (3 + e.charge * 6)) * 0.08 * (0.3 + e.charge)
		core.Size = Vector3.one * 1.8 * pulse
		core.CFrame = cf
	end)
end

local function roomProgress(group: RoomMobGroup): (number, number)
	local total, cleared = 0, 0
	for _, r in ipairs(group.mobs) do
		total += 1
		if r.defeated then cleared += 1 end
	end
	return cleared, total
end

local function playersNearRoom(group: RoomMobGroup): { Player }
	local out = {}
	local room = group.room
	local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE * 0.5
	local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
	local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE * 0.5
	local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
	for _, plr in ipairs(Players:GetPlayers()) do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if plr:GetAttribute("InLobby") ~= true and root and root.Position.X >= minX and root.Position.X <= maxX
			and root.Position.Z >= minZ and root.Position.Z <= maxZ and math.abs(root.Position.Y - room.floorY) < 12 then
			table.insert(out, plr)
		end
	end
	return out
end

-- Kills only move the room's progress bar. The reward itself doesn't exist
-- until the room is clear: then it appears — a flash of light, the orb
-- swelling up out of the floor in its colour, the beam shooting up — already
-- blazing and ready to claim.
-- Rooms whose mobs are all dead, for the map ("|3|7|", room ids).
local function markCleared(group: RoomMobGroup)
	local list = Workspace:GetAttribute("ClearedRooms")
	local s = if typeof(list) == "string" then list else "|"
	local tag = `|{group.room.id}|`
	if not string.find(s, tag, 1, true) then
		Workspace:SetAttribute("ClearedRooms", s .. `{group.room.id}|`)
	end
end

local function updateEmblem(group: RoomMobGroup)
	local cleared, total = roomProgress(group)
	for _, plr in ipairs(playersNearRoom(group)) do
		PlayerStats.SetRoomProgress(plr, cleared, total)
	end
	if cleared < total or group.emblem then return end
	markCleared(group)

	createEmblem(group)
	local e = group.emblem
	if not e then return end
	e.charge = 1
	e.charged = true
	e.model:SetAttribute("Charged", true) -- clients show the interact prompt
	local color = e.color
	e.orb.Color, e.orb.Transparency = color, 0.15
	e.core.Color, e.core.Transparency = color:Lerp(Color3.new(1, 1, 1), 0.55), 0
	e.base.Color, e.base.Transparency = color, 0.4
	e.light.Color, e.light.Brightness, e.light.Range = color, 5, 28
	e.sparks.Rate = 50
	e.sparks:Emit(60)
	-- Appear: the orb swells up from nothing, the beam and base flash in.
	e.orb.Size = Vector3.one * 0.3
	TweenService:Create(e.orb, TweenInfo.new(0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * 3.2 }):Play()
	e.beam.Transparency, e.beam.Size = 0, Vector3.new(70, 3, 3)
	TweenService:Create(e.beam, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Transparency = 0.25, Size = Vector3.new(70, 0.6, 0.6) }):Play()
	e.base.Size = Vector3.new(0.12, 0.5, 0.5)
	TweenService:Create(e.base, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.12, 6, 6) }):Play()
end

-- Left-click a blazing reward: it shatters into sparks of its colour and
-- every living player in the run levels up (offered the reward's buffs).
claimEmblem = function(group: RoomMobGroup, plr: Player)
	local e = group.emblem
	if not e or not e.charged or e.claimed then return end
	local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 or plr:GetAttribute("InLobby") ~= false then return end
	if (root.Position - e.orb.Position).Magnitude > 22 then return end
	e.claimed = true
	e.model:SetAttribute("Claimed", true)
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("InLobby") == false and p:GetAttribute("IsDead") ~= true then
			PlayerStats.LevelUp(p, e.buffs)
		end
	end

	local center = e.orb.Position
	local click = e.orb:FindFirstChildOfClass("ClickDetector")
	if click then click:Destroy() end
	local sigil = e.orb:FindFirstChild("Sigil")
	if sigil then sigil:Destroy() end
	e.orb.Transparency, e.core.Transparency = 1, 1
	-- Flash.
	local flash = emblemPart(e.model, { Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(center),
		Color = Color3.new(1, 1, 1), Transparency = 0 })
	TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 12, Transparency = 1, Color = e.color }):Play()
	-- Shards flying out in every direction.
	for _ = 1, 26 do
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.9 - 0.2, math.random() - 0.5)
		dir = if dir.Magnitude > 0.05 then dir.Unit else Vector3.yAxis
		local shard = emblemPart(e.model, { Size = Vector3.new(0.25, 0.25, 0.9),
			CFrame = CFrame.lookAt(center, center + dir), Color = if math.random() < 0.3 then Color3.new(1, 1, 1) else e.color })
		local dist = 6 + math.random() * 8
		TweenService:Create(shard, TweenInfo.new(0.5 + math.random() * 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			CFrame = CFrame.lookAt(center + dir * dist, center + dir * (dist + 1)) * CFrame.Angles(math.random() * 3, 0, 0),
			Size = Vector3.new(0.08, 0.08, 0.3),
			Transparency = 1,
		}):Play()
	end
	e.sparks.Speed = NumberRange.new(12, 26)
	e.sparks.Lifetime = NumberRange.new(0.5, 1.1)
	e.sparks:Emit(140)
	e.sparks.Enabled = false
	e.light.Brightness, e.light.Range = 10, 40
	TweenService:Create(e.light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	TweenService:Create(e.beam, TweenInfo.new(0.15), { Size = Vector3.new(70, 3, 3), Transparency = 0 }):Play()
	task.delay(0.15, function()
		TweenService:Create(e.beam, TweenInfo.new(0.6), { Size = Vector3.new(70, 0.1, 0.1), Transparency = 1 }):Play()
	end)
	TweenService:Create(e.base, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	local model = e.model
	task.delay(1.5, function() model:Destroy() end)
end

-- A boss falls: every fallen player still in the run (not given up) stands
-- back up in its room. (The only way back besides your own one revive.)
local function bossDown(record: MobRecord)
	if not record.isBoss then return end
	local at = record.spawnCFrame.Position + Vector3.new(0, 3, 0)
	pcall(function()
		local DeathManager = require(script.Parent:WaitForChild("DeathManager"))
		DeathManager.ReviveAllAt(at)
	end)
end

local function activateMob(record: MobRecord)
	if record.defeated or record.model or not activeMobsFolder then return end

	-- The dragon flies its own fight (DragonBoss).
	if record.bossKind == "dragon" and record.group then
		record.model = DragonBoss.Spawn(activeMobsFolder, record.group.room, record.health, function()
			record.defeated = true
			record.model = nil
			if record.group then updateEmblem(record.group) end
			bossDown(record)
		end)
		if record.model then return end
		record.bossKind = "warlord" -- (no dragon model in this place: a normal boss instead)
	end

	local model = record.template and record.template:Clone() or createFallbackMob()
	-- Rank tags for abilities that care (e.g. the Gunslinger's Silver Dollar).
	model:SetAttribute("IsBoss", record.isBoss)
	model:SetAttribute("IsElite", record.isElite == true)
	model:SetAttribute("FloorY", record.spawnCFrame.Position.Y)
	-- Its kind: the look, stats and moves (MobKinds).
	if record.kind and record.template then
		MobKinds.Prepare(model, record.kind, if record.isElite then record.affix else nil)
		-- (the risen dead climb out of the floor, the first time)
		if record.summoned and record.kind == "risen" and record.health == math.huge then model:SetAttribute("Rising", true) end
	end
	if record.isElite and not record.isBoss then
		model:SetAttribute("HealthMult", (model:GetAttribute("HealthMult") or 1) * ELITE_HEALTH)
		model:SetAttribute("DamageMult", (model:GetAttribute("DamageMult") or 1) * ELITE_DAMAGE)
		model:SetAttribute("XPMult", (model:GetAttribute("XPMult") or 1) * ELITE_XP)
		pcall(function() model:ScaleTo(model:GetScale() * ELITE_SCALE) end)
	end
	local kind = record.bossKind and BossAI.Kinds[record.bossKind]
	if kind then
		model:SetAttribute("DisplayName", kind.name)
		model:SetAttribute("HealthMult", kind.health)
		model:SetAttribute("DamageMult", kind.damage)
		model:SetAttribute("XPMult", kind.xp)
	end
	model.Parent = activeMobsFolder
	record.model = model
	configureMob(model, record.spawnCFrame, record.isBoss, record.health, function()
		record.defeated = true
		record.model = nil
		if record.group then updateEmblem(record.group) end
		bossDown(record)
	end)
	if record.isElite and not record.isBoss then addEliteAura(model) end
	if kind then BossAI.Attach(model, record.bossKind :: string) end
	if record.kind and record.template then MobKinds.Attach(model, record.kind) end
	-- The server owns mob physics; otherwise Roblox hands each mob to the
	-- nearest player and server-side knockback impulses are ignored.
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root.Anchored then
		pcall(function() root:SetNetworkOwner(nil) end)
	end
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

-- Rooms are filled the first time a player comes near, using the Threat
-- tier at that moment: more mobs at higher Threat, and each one has a small
-- (growing) chance to be a purple-flame elite.
local function mobCountFor(tier: number): number
	return math.min(MOBS_BASE + tier * MOBS_PER_TIER, MOBS_MAX)
end

local function eliteChanceFor(tier: number): number
	return math.min(ELITE_BASE_CHANCE + tier * ELITE_CHANCE_PER_TIER, ELITE_MAX_CHANCE)
end

local function planRoom(group: RoomMobGroup)
	if group.planned then return end
	group.planned = true
	local room = group.room
	local normalTemplates, bossTemplates = getMobTemplates()
	local tier = DifficultyManager.GetTier()
	local minX = room.gx * FLOOR_SIZE + 4
	local maxX = (room.gx + room.w - 1) * FLOOR_SIZE - 4
	local minZ = room.gz * FLOOR_SIZE + 4
	local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE - 4
	local remaining = mobCountFor(tier)

	-- The dragon rules every run's first level (and turns up now and then later).
	local level = Workspace:GetAttribute("RunLevel") or 1
	if room.roomType == "Boss" and DragonBoss.Available() and (level <= 1 or math.random() < 0.35) then
		table.insert(group.mobs, {
			template = nil,
			spawnCFrame = CFrame.new((room.gx + room.w / 2) * FLOOR_SIZE, room.floorY, (room.gz + room.d / 2) * FLOOR_SIZE),
			isBoss = true,
			bossKind = "dragon",
			health = math.huge,
			defeated = false,
			model = nil,
		})
		remaining = 0 -- the dragon (and its arena) is the fight
	elseif room.roomType == "Boss" then
		-- A slime-looking boss (or the fallback slime) fights as the Slime
		-- King; any other boss model gets one of the other kits.
		local template = if #bossTemplates > 0 then bossTemplates[math.random(1, #bossTemplates)] else nil
		local isSlime = template == nil or string.find(string.lower(template.Name), "slime") ~= nil
		local kinds = {}
		for _, id in ipairs(BossAI.KindIds()) do
			if (id == "slime") == isSlime then table.insert(kinds, id) end
		end
		table.insert(group.mobs, {
			template = template,
			spawnCFrame = CFrame.new((room.gx + room.w / 2) * FLOOR_SIZE, room.floorY, (room.gz + room.d / 2) * FLOOR_SIZE),
			isBoss = true,
			bossKind = kinds[math.random(1, #kinds)],
			health = math.huge,
			defeated = false,
			model = nil,
		})
		remaining = math.max(2, math.floor(remaining / 2)) -- the boss is the fight
	end

	for _, r in ipairs(group.mobs) do r.group = group end -- the boss
	local eliteChance = eliteChanceFor(tier)
	-- A themed pack for the room (MobKinds): ghouls and wraiths in a crypt,
	-- magma and bloat slimes in a slime pit, and so on.
	for _, kindId in ipairs(MobKinds.PlanRoom(remaining, level)) do
		local template = MobKinds.Template(kindId)
		if not template and #normalTemplates > 0 then template = normalTemplates[math.random(1, #normalTemplates)] end
		local elite = room.roomType == "Elite" or math.random() < eliteChance
		table.insert(group.mobs, {
			template = template,
			kind = kindId,
			affix = if elite then MobKinds.RollAffix() else nil,
			spawnCFrame = CFrame.new(math.random(math.floor(minX), math.floor(maxX)), room.floorY, math.random(math.floor(minZ), math.floor(maxZ))) * CFrame.Angles(0, math.rad(math.random(0, 360)), 0),
			isBoss = false,
			isElite = elite,
			group = group,
			health = math.huge,
			defeated = false,
			model = nil,
		})
	end
end

local function refreshActiveRooms()
	for _, group in ipairs(roomMobGroups) do
		local shouldBeActive = roomIsNearAnActivePlayer(group.room)
		if shouldBeActive and not group.planned then
			planRoom(group)
			updateEmblem(group) -- progress bar only; the reward appears on clear
		end
		for _, record in ipairs(group.mobs) do
			if shouldBeActive then
				activateMob(record)
			else
				deactivateMob(record)
			end
		end
	end
end

-- A boss's summoned minion: a normal mob at `pos`, not tied to any room.
-- The combat room containing `pos` (flat bounds + floor height), or nil.
-- Used by room-wide abilities (the Swordsman's Blade Storm).
function MobManager.RoomBoundsAt(pos: Vector3): { minX: number, maxX: number, minZ: number, maxZ: number, floorY: number }?
	for _, group in ipairs(roomMobGroups) do
		local room = group.room
		local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE * 0.5
		local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
		local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE * 0.5
		local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
		if pos.X >= minX and pos.X <= maxX and pos.Z >= minZ and pos.Z <= maxZ and math.abs(pos.Y - room.floorY) < 12 then
			return { minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, floorY = room.floorY }
		end
	end
	return nil
end

function MobManager.SpawnMinion(pos: Vector3): Model?
	if not activeMobsFolder then return nil end
	local kindId = MobKinds.MINIONS[math.random(1, #MobKinds.MINIONS)]
	local template = MobKinds.Template(kindId)
	local model = if template then template:Clone() else createFallbackMob()
	if template then MobKinds.Prepare(model, kindId) end
	model:SetAttribute("IsBoss", false)
	model:SetAttribute("IsElite", false)
	model:SetAttribute("XPMult", (model:GetAttribute("XPMult") or 1) * 0.4)
	model:SetAttribute("FloorY", pos.Y)
	model.Parent = activeMobsFolder
	configureMob(model, CFrame.new(pos), false, nil, nil)
	if template then MobKinds.Attach(model, kindId) end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") and not root.Anchored then
		pcall(function() root:SetNetworkOwner(nil) end)
	end
	return model
end

-- A mob another mob brings with it (a bloat's slimelings, a necromancer's
-- risen dead): it joins `near`'s room, so the room isn't clear until it's
-- dead too.
local function spawnKind(kindId: string, cf: CFrame, near: Model?): Model?
	if not activeMobsFolder then return nil end
	local group: RoomMobGroup? = nil
	if near then
		for _, g in ipairs(roomMobGroups) do
			for _, r in ipairs(g.mobs) do
				if r.model == near then group = g end
			end
			if group then break end
		end
	end
	local record: MobRecord = {
		template = MobKinds.Template(kindId),
		kind = kindId,
		spawnCFrame = cf,
		isBoss = false,
		isElite = false,
		group = group,
		health = math.huge,
		defeated = false,
		model = nil,
		summoned = true,
	}
	if group then table.insert(group.mobs, record) end
	activateMob(record)
	if group then updateEmblem(group) end
	return record.model
end

function MobManager.SpawnRoomMobs(rooms: { any })
	MobManager.Clear()
	Workspace:SetAttribute("ClearedRooms", "|") -- a fresh dungeon: nothing cleared

	local mobsFolder = Instance.new("Folder")
	mobsFolder.Name = "Mobs"
	mobsFolder.Parent = Workspace
	activeMobsFolder = mobsFolder

	local roomCount = 0
	for _, room in ipairs(rooms) do
		if room.id == 1 or room.roomType == "Start" or room.roomType == "Rest" or room.roomType == "Treasure" or room.roomType == "Shop" or room.roomType == "Gamble" then continue end
		table.insert(roomMobGroups, { room = room, mobs = {}, planned = false })
		roomCount += 1
	end

	refreshActiveRooms()
	task.spawn(function()
		while activeMobsFolder == mobsFolder and mobsFolder.Parent do
			task.wait(ROOM_REFRESH_INTERVAL)
			refreshActiveRooms()
		end
	end)
	print(`[MobManager] {roomCount} combat rooms; each fills with mobs (scaled by Threat) when a player gets near.`)
end

function MobManager.Clear()
	roomMobGroups = {}
	local emblems = Workspace:FindFirstChild("RoomEmblems")
	if emblems then emblems:Destroy() end
	if activeMobsFolder and activeMobsFolder.Parent then
		activeMobsFolder:Destroy()
		activeMobsFolder = nil
	end
	local existing = Workspace:FindFirstChild("Mobs")
	if existing then
		existing:Destroy()
	end
end

-- Damage a player (or decoy) from a boss attack: respects dodge i-frames,
-- lobby players and Cursed Tomes; knocks them away from `from`.
-- `attacker` (a mob's moves) is who a parry stuns. Returns the damage that
-- landed.
local function hurtPlayer(targetChar: Model, damage: number, from: Vector3?, attacker: Model?): number
	local hum = targetChar:FindFirstChildOfClass("Humanoid")
	local root = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then return 0 end
	if isDecoy(targetChar) then
		hum:TakeDamage(damage)
		return damage
	end
	local plr = Players:GetPlayerFromCharacter(targetChar)
	if not plr or plr:GetAttribute("InLobby") == true then return 0 end
	if (targetChar:GetAttribute("InvulnerableUntil") or 0) > os.clock() then return 0 end
	-- Boss attacks can be parried too (no single attacker to stun, but the
	-- counter still fires).
	if parried(targetChar, attacker) then return 0 end
	local dealt = incoming(plr, targetChar, damage * curseScale(plr))
	hum:TakeDamage(dealt)
	if from and knockable(targetChar) then
		local diff = Vector3.new(root.Position.X - from.X, 0, root.Position.Z - from.Z)
		local dir = if diff.Magnitude > 0.1 then diff.Unit else Vector3.xAxis
		root:ApplyImpulse((dir + Vector3.new(0, 0.35, 0)).Unit * root.AssemblyMass * 22)
	end
	return dealt
end

-- A boss kill's drops (the dragon's; the other mobs do the same in their
-- Died handlers): shared XP, gold and soul / summon rolls for everyone near.
local function grantBossRewards(model: Model, pos: Vector3, xpReward: number)
	triggerBlueStarDeathVFX(pos, true)
	local nearby: { Player } = {}
	for _, player in ipairs(Players:GetPlayers()) do
		local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if player:GetAttribute("InLobby") ~= true and playerRoot and (playerRoot.Position - pos).Magnitude <= 160 then
			table.insert(nearby, player)
		end
	end
	for _, player in ipairs(PartyManager.XPRecipients(nearby)) do
		PlayerStats.AwardXP(player, xpReward)
	end
	for _, player in ipairs(nearby) do
		PlayerStats.AwardGold(player, math.random(90, 130))
		TalentManager.OnMobKilled(player, true)
		GachaManager.OnMobKilled(player, true)
	end
end

local function bossCanAct(model: Model): boolean
	return not mobsAreFrozen()
		and Workspace:GetAttribute("TomesPaused") ~= true
		and (model:GetAttribute("ChilledUntil") or 0) <= os.clock()
		-- (no stagger check: bosses shrug off hit-stagger, or constant
		-- hits would stop them from ever attacking)
end

function MobManager.Init()
	-- Left click near a ready reward (EmblemPrompt sends which one).
	Network.GetRemoteEvent(Network.Remotes.ClaimReward).OnServerEvent:Connect(function(plr: Player, model: any)
		if typeof(model) ~= "Instance" then return end
		for _, group in ipairs(roomMobGroups) do
			if group.emblem and group.emblem.model == model then
				claimEmblem(group, plr)
				return
			end
		end
	end)
	BossAI.Init({
		canAct = bossCanAct,
		hurt = hurtPlayer,
		spawnMinion = MobManager.SpawnMinion,
	})
	DragonBoss.Init({
		canAct = bossCanAct,
		hurt = hurtPlayer,
		reward = grantBossRewards,
	})
	MobKinds.Init({
		canAct = bossCanAct,
		hurt = hurtPlayer,
		spawnKind = spawnKind,
		damageScale = function(): number
			return DifficultyManager.GetMobScale().damage
		end,
	})
	print("[MobManager] Server MobManager initialized.")
end

return MobManager
