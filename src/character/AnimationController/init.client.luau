local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))

local player = Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local animator = humanoid:WaitForChild("Animator") :: Animator

-- Disable default Roblox animation script so it doesn't fight with our custom animations
local defaultAnimate = character:WaitForChild("Animate", 3)
if defaultAnimate then
	defaultAnimate:Destroy()
	-- Stop any animation tracks already started by the default script
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		track:Stop(0)
	end
end

print("[AnimationController] Character Rig Type:", humanoid.RigType.Name)

local walkAnim = script:WaitForChild("walk")
local runAnim = script:WaitForChild("run")
local idleAnim = script:WaitForChild("idle")

local WalkTrack: AnimationTrack?, RunTrack: AnimationTrack?, IdleTrack: AnimationTrack?

-- ─────────────────────────────────────────────────────────────────────────────
-- Animation Configuration
-- ─────────────────────────────────────────────────────────────────────────────
local CLASS_ANIMATIONS = {
	default = {
		walk = "rbxassetid://109247200419554",
		run = "rbxassetid://79701746140908",
		idle = "rbxassetid://86968114690424",
	},
	heavy_knight = {
		walk = "rbxassetid://110753782425862",
		run = "rbxassetid://131143543582644",
		idle = "rbxassetid://79280836238386",
	},
}

local ATTACK_ANIMATIONS = {
	heavy_knight = {
		running = "rbxassetid://97959206991231",
		combo = {
			"rbxassetid://89799832930197",  -- Attack 1
			"rbxassetid://139832137467263", -- Attack 2
			"rbxassetid://88609851560221",  -- Attack 3
			"rbxassetid://86943794416151",  -- Attack 4
		},
	},
	default = {
		running = "rbxassetid://97959206991231",
		combo = {
			"rbxassetid://89799832930197",
			"rbxassetid://139832137467263",
			"rbxassetid://88609851560221",
			"rbxassetid://86943794416151",
		},
	},
}

-- ─────────────────────────────────────────────────────────────────────────────
-- Combat & Sprint State
-- ─────────────────────────────────────────────────────────────────────────────
local loadedComboTracks: { AnimationTrack } = {}
local loadedRunningTrack: AnimationTrack? = nil
local isAttacking = false
local currentAttackTrack: AnimationTrack? = nil
local comboIndex = 1
local lastAttackEndTime = 0
local COMBO_RESET_WINDOW = 1.3 -- Seconds to chain into next combo attack before resetting
local attackBuffered = false

local activeSpeedVFX: Instance? = nil

local WALK_SPEED = 16
local RUN_SPEED = 34

local AirborneState = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local isSprinting = false

-- Forward declarations
local UpdateMovement
local playIdle

-- ─────────────────────────────────────────────────────────────────────────────
-- Sprint & Dash VFX
-- ─────────────────────────────────────────────────────────────────────────────

local function findVFXAsset(name: string): Instance?
	local generalVFX = ReplicatedStorage:FindFirstChild("generalVFX")
	if generalVFX then
		local found = generalVFX:FindFirstChild(name)
			or generalVFX:FindFirstChild(string.lower(name))
			or generalVFX:FindFirstChild(string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2))
		if found then
			return found
		end
	end

	-- Fallback checks
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local vfxFolder = assets:FindFirstChild("generalVFX") or assets:FindFirstChild("VFX")
		if vfxFolder and vfxFolder:FindFirstChild(name) then
			return vfxFolder:FindFirstChild(name)
		end
	end
	if ReplicatedStorage:FindFirstChild(name) then
		return ReplicatedStorage:FindFirstChild(name)
	end
	return nil
end

local function playDashShockwaveVFX()
	if player:GetAttribute("InLobby") == true then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local dashTemplate = findVFXAsset("Dash")
	if not dashTemplate then
		warn("[VFX] 'Dash' not found in ReplicatedStorage.generalVFX")
		return
	end

	local clone = dashTemplate:Clone()

	local moveDir = (humanoid and humanoid.MoveDirection.Magnitude > 0.1) and humanoid.MoveDirection.Unit or rootPart.CFrame.LookVector
	local flatLook = CFrame.lookAt(rootPart.Position, rootPart.Position + Vector3.new(moveDir.X, 0, moveDir.Z))
	local groundCF = flatLook * CFrame.new(0, -2.4, 0) * CFrame.Angles(math.rad(90), 0, 0)

	if clone:IsA("BasePart") then
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.Massless = true
		clone.Anchored = true
		clone.CFrame = groundCF
		clone.Parent = workspace

		-- Look for child wave mesh or SpecialMesh inside Dash
		local specialMesh = clone:FindFirstChildOfClass("SpecialMesh")
		local waveChild = clone:FindFirstChild("Wave", true) or clone:FindFirstChild("wave", true) or clone:FindFirstChild("Mesh", true)

		if specialMesh then
			-- Animate SpecialMesh scale & Dash transparency (halved size)
			local origScale = specialMesh.Scale
			local targetScale = (origScale.Magnitude > 3) and (origScale * 1.75) or Vector3.new(12, 0.6, 12)
			specialMesh.Scale = Vector3.new(0.25, 0.05, 0.25)
			clone.Transparency = 0

			TweenService:Create(
				specialMesh,
				TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Scale = targetScale }
			):Play()

			TweenService:Create(
				clone,
				TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			):Play()
		elseif waveChild and waveChild:IsA("BasePart") then
			-- If Wave is a child MeshPart/Part inside Dash
			clone.Transparency = 1 -- Hide carrier
			waveChild.CanCollide = false
			waveChild.Anchored = true
			waveChild.CFrame = groundCF

			local initialSize = waveChild.Size
			local targetSize = (initialSize.Magnitude > 3) and (initialSize * 1.6) or Vector3.new(9, 0.15, 9)
			waveChild.Size = Vector3.new(0.5, 0.05, 0.5)
			waveChild.Transparency = 0

			TweenService:Create(
				waveChild,
				TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = targetSize, Transparency = 1 }
			):Play()
		else
			-- Animate Dash BasePart directly
			local initialSize = clone.Size
			local targetSize = (initialSize.Magnitude > 3) and (initialSize * 1.6) or Vector3.new(9, 0.15, 9)
			clone.Size = Vector3.new(0.5, 0.05, 0.5)
			clone.Transparency = 0

			TweenService:Create(
				clone,
				TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = targetSize, Transparency = 1 }
			):Play()
		end

		-- Also animate any other SpecialMeshes or child parts & burst particles
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("SpecialMesh") and desc ~= specialMesh then
				local targetScale = (desc.Scale.Magnitude > 3) and (desc.Scale * 1.75) or Vector3.new(12, 0.6, 12)
				desc.Scale = Vector3.new(0.25, 0.05, 0.25)
				TweenService:Create(
					desc,
					TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Scale = targetScale }
				):Play()
			elseif desc:IsA("BasePart") and desc ~= clone and desc ~= waveChild then
				desc.CanCollide = false
				desc.Anchored = true
				local targetSize = (desc.Size.Magnitude > 3) and (desc.Size * 1.6) or Vector3.new(9, 0.15, 9)
				desc.Size = Vector3.new(0.5, 0.05, 0.5)
				desc.Transparency = 0
				TweenService:Create(
					desc,
					TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = targetSize, Transparency = 1 }
				):Play()
			elseif desc:IsA("ParticleEmitter") then
				local count = desc:GetAttribute("EmitCount") or 25
				desc:Emit(count)
			end
		end

		Debris:AddItem(clone, 0.8)
	elseif clone:IsA("Model") then
		clone:PivotTo(groundCF)
		clone.Parent = workspace

		for _, part in ipairs(clone:GetDescendants()) do
			if part:IsA("BasePart") then
				part.CanCollide = false
				part.Anchored = true
				local targetSize = (part.Size.Magnitude > 3) and (part.Size * 1.6) or Vector3.new(9, 0.15, 9)
				part.Size = Vector3.new(0.5, 0.05, 0.5)
				part.Transparency = 0
				TweenService:Create(
					part,
					TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Size = targetSize, Transparency = 1 }
				):Play()
			elseif part:IsA("SpecialMesh") then
				local targetScale = (part.Scale.Magnitude > 3) and (part.Scale * 1.75) or Vector3.new(12, 0.6, 12)
				part.Scale = Vector3.new(0.25, 0.05, 0.25)
				TweenService:Create(
					part,
					TweenInfo.new(0.38, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ Scale = targetScale }
				):Play()
			elseif part:IsA("ParticleEmitter") then
				part:Emit(part:GetAttribute("EmitCount") or 25)
			end
		end

		Debris:AddItem(clone, 0.8)
	end
end

local function startSpeedSprintVFX()
	if activeSpeedVFX then return end
	if player:GetAttribute("InLobby") == true then return end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local speedTemplate = findVFXAsset("Speed") or findVFXAsset("speed")
	if not speedTemplate then
		warn("[VFX] 'Speed' not found in ReplicatedStorage.generalVFX")
		return
	end

	local clone = speedTemplate:Clone()
	-- Position speed streaks to stream backwards behind the character
	local speedCF = rootPart.CFrame * CFrame.new(0, 0, 0.5) * CFrame.Angles(math.rad(90), 0, 0)

	if clone:IsA("Attachment") then
		clone.CFrame = CFrame.Angles(math.rad(90), 0, 0)
		clone.Parent = rootPart
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = true
			end
		end
		if clone:IsA("ParticleEmitter") then
			clone.Enabled = true
		end
		activeSpeedVFX = clone
	elseif clone:IsA("BasePart") then
		clone.CanCollide = false
		clone.CanTouch = false
		clone.CanQuery = false
		clone.Massless = true
		clone.CFrame = speedCF
		clone.Parent = character

		local weld = Instance.new("WeldConstraint")
		weld.Part0 = rootPart
		weld.Part1 = clone
		weld.Parent = clone

		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("ParticleEmitter") then
				desc.Enabled = true
			end
		end
		activeSpeedVFX = clone
	elseif clone:IsA("Model") then
		clone:PivotTo(speedCF)
		clone.Parent = character
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.CanCollide = false
				desc.Massless = true
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rootPart
				weld.Part1 = desc
				weld.Parent = desc
			elseif desc:IsA("ParticleEmitter") then
				desc.Enabled = true
			end
		end
		activeSpeedVFX = clone
	end
end

local function stopSpeedSprintVFX()
	if not activeSpeedVFX then return end
	local vfx = activeSpeedVFX
	activeSpeedVFX = nil

	for _, desc in ipairs(vfx:GetDescendants()) do
		if desc:IsA("ParticleEmitter") then
			desc.Enabled = false
		elseif desc:IsA("BasePart") then
			TweenService:Create(
				desc,
				TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Transparency = 1 }
			):Play()
		end
	end
	if vfx:IsA("ParticleEmitter") then
		vfx.Enabled = false
	end

	Debris:AddItem(vfx, 1.2)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Track Loading & Verification
-- ─────────────────────────────────────────────────────────────────────────────

local function setWeaponTrailEnabled(enabled: boolean)
	local char = character or player.Character
	if not char then return end

	local count = 0
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("Trail") then
			desc.Enabled = enabled
			count += 1
		end
	end

	if count == 0 and enabled then
		local tool = char:FindFirstChildOfClass("Tool") or player.Backpack:FindFirstChildOfClass("Tool")
		if tool then
			for _, desc in ipairs(tool:GetDescendants()) do
				if desc:IsA("Trail") then
					desc.Enabled = enabled
					count += 1
				end
			end
		end
	end
end

local function monitorTrack(name: string, track: AnimationTrack)
	task.spawn(function()
		local startTime = os.clock()
		while track.Length == 0 do
			task.wait(0.1)
			if os.clock() - startTime > 5 then
				warn(`[AnimationController] {name} animation failed to load within 5 seconds (asset permissions/moderation?)`)
				return
			end
		end
		print(`[AnimationController] {name} animation loaded successfully. Length: {track.Length}s`)
	end)
end

local function loadClassAnimations(classId: string)
	-- Stop any currently playing locomotion tracks
	if WalkTrack then WalkTrack:Stop(0) end
	if RunTrack then RunTrack:Stop(0) end
	if IdleTrack then IdleTrack:Stop(0) end

	local anims = CLASS_ANIMATIONS[classId] or CLASS_ANIMATIONS.default
	walkAnim.AnimationId = anims.walk
	runAnim.AnimationId = anims.run
	idleAnim.AnimationId = anims.idle

	WalkTrack = animator:LoadAnimation(walkAnim)
	WalkTrack.Priority = Enum.AnimationPriority.Action
	WalkTrack.Looped = true

	RunTrack = animator:LoadAnimation(runAnim)
	RunTrack.Priority = Enum.AnimationPriority.Action
	RunTrack.Looped = true

	IdleTrack = animator:LoadAnimation(idleAnim)
	IdleTrack.Priority = Enum.AnimationPriority.Action
	IdleTrack.Looped = true

	-- Monitor loading progress
	monitorTrack("Walk", WalkTrack)
	monitorTrack("Run", RunTrack)
	monitorTrack("Idle", IdleTrack)

	-- Stop any active attack
	if currentAttackTrack then
		currentAttackTrack:Stop(0)
		currentAttackTrack = nil
	end
	setWeaponTrailEnabled(false)
	isAttacking = false
	attackBuffered = false
	comboIndex = 1

	-- Load Attack animations
	loadedComboTracks = {}
	loadedRunningTrack = nil

	local attackSet = ATTACK_ANIMATIONS[classId] or ATTACK_ANIMATIONS.default
	for i, attackId in ipairs(attackSet.combo) do
		local animObj = Instance.new("Animation")
		animObj.Name = `Attack{i}`
		animObj.AnimationId = attackId
		local track = animator:LoadAnimation(animObj)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		table.insert(loadedComboTracks, track)
		monitorTrack(`Attack{i}`, track)
	end

	if attackSet.running then
		local animObj = Instance.new("Animation")
		animObj.Name = "RunningAttack"
		animObj.AnimationId = attackSet.running
		local track = animator:LoadAnimation(animObj)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		loadedRunningTrack = track
		monitorTrack("RunningAttack", track)
	end

	-- Wait for locomotion animation assets to finish downloading
	while WalkTrack.Length == 0 or RunTrack.Length == 0 or IdleTrack.Length == 0 do
		task.wait()
	end

	print(`[AnimationController] Animations & Attacks loaded for class: {classId}`)
	if UpdateMovement then
		UpdateMovement()
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Combat Execution
-- ─────────────────────────────────────────────────────────────────────────────

local function applyAttackNudge(rootPart: BasePart, lookDir: Vector3, speed: number, duration: number)
	local oldAttachment = rootPart:FindFirstChild("AttackNudgeAttachment")
	if oldAttachment then oldAttachment:Destroy() end
	local oldLV = rootPart:FindFirstChild("AttackLinearVelocity")
	if oldLV then oldLV:Destroy() end

	local att = Instance.new("Attachment")
	att.Name = "AttackNudgeAttachment"
	att.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = "AttackLinearVelocity"
	lv.Attachment0 = att
	lv.MaxForce = 150000
	lv.VectorVelocity = Vector3.new(lookDir.X * speed, 0, lookDir.Z * speed)
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = rootPart

	task.delay(duration, function()
		if lv and lv.Parent then lv:Destroy() end
		if att and att.Parent then att:Destroy() end
	end)
end

local function performAttack()
	if player:GetAttribute("InLobby") == true then return end
	if humanoid.Health <= 0 then return end

	-- Block attacks while using the 1st ability (Spin Attack) or casting skills
	if character:GetAttribute("IsSkill1Active") == true
		or character:GetAttribute("IsSpinAttackActive") == true
		or character:GetAttribute("IsSkillCasting") == true then
		return
	end

	local now = os.clock()

	-- If currently in an attack swing, buffer the input if we're past 40% of the animation
	if isAttacking and currentAttackTrack then
		local trackLength = currentAttackTrack.Length
		if trackLength > 0 and (currentAttackTrack.TimePosition / trackLength) > 0.4 then
			attackBuffered = true
		end
		return
	end

	local isRunning = isSprinting and humanoid.MoveDirection.Magnitude > 0.1
	local trackToPlay: AnimationTrack? = nil
	local attackType = "combo"
	local currentCombo = comboIndex

	if isRunning and loadedRunningTrack then
		trackToPlay = loadedRunningTrack
		attackType = "running"
		comboIndex = 1 -- Reset combo counter after running attack
	else
		if #loadedComboTracks == 0 then return end
		-- Reset combo back to step 1 if the chain window expired
		if now - lastAttackEndTime > COMBO_RESET_WINDOW then
			comboIndex = 1
		end
		currentCombo = comboIndex
		trackToPlay = loadedComboTracks[comboIndex]
		comboIndex = (comboIndex % #loadedComboTracks) + 1
	end

	if not trackToPlay then return end

	isAttacking = true
	attackBuffered = false
	currentAttackTrack = trackToPlay

	-- Stop movement during attack & activate weapon slash trail
	humanoid.WalkSpeed = 0
	stopSpeedSprintVFX()
	setWeaponTrailEnabled(true)

	-- Fade out locomotion tracks during attack
	if WalkTrack and WalkTrack.IsPlaying then WalkTrack:Stop(0.1) end
	if RunTrack and RunTrack.IsPlaying then RunTrack:Stop(0.1) end
	if IdleTrack and IdleTrack.IsPlaying then IdleTrack:Stop(0.1) end

	-- Notify server
	pcall(function()
		local performAttackRemote = Network.GetRemoteEvent(Network.Remotes.PerformAttack)
		performAttackRemote:FireServer({
			attackType = attackType,
			comboStep = currentCombo,
		})
	end)

	-- If Missile Barrage Buff is active, launch a guided missile
	if character:GetAttribute("IsMissileBuffActive") == true then
		local PlayerScripts = player:FindFirstChild("PlayerScripts")
		local clientScript = PlayerScripts and (PlayerScripts:FindFirstChild("SoloProjectClient") or PlayerScripts:FindFirstChild("client"))
		local skillModule = clientScript and clientScript:FindFirstChild("SkillController")
		if skillModule then
			local success, mod = pcall(require, skillModule)
			if success and mod and mod.LaunchMissile then
				mod.LaunchMissile(character)
			end
		end
	end

	-- Apply a physical forward nudge using LinearVelocity constraint
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if rootPart then
		local lookDir = rootPart.CFrame.LookVector
		local nudgeSpeed = isRunning and 32 or 16
		local nudgeDuration = isRunning and 0.22 or 0.14
		applyAttackNudge(rootPart, lookDir, nudgeSpeed, nudgeDuration)
	end

	trackToPlay:Play(0.1)
	print(`[Combat] Executed {attackType} attack (Hit: {currentCombo})`)

	-- Attack completion handler
	local stoppedConn: RBXScriptConnection? = nil
	stoppedConn = trackToPlay.Stopped:Connect(function()
		if stoppedConn then
			stoppedConn:Disconnect()
			stoppedConn = nil
		end

		if currentAttackTrack == trackToPlay then
			setWeaponTrailEnabled(false)
			isAttacking = false
			currentAttackTrack = nil
			lastAttackEndTime = os.clock()

			-- If the player queued an attack during recovery frames, fire next attack immediately
			if attackBuffered then
				attackBuffered = false
				task.defer(performAttack)
			else
				humanoid.WalkSpeed = isSprinting and RUN_SPEED or WALK_SPEED
				UpdateMovement()
			end
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Input Handling
-- ─────────────────────────────────────────────────────────────────────────────

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end

	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		if not isSprinting then
			isSprinting = true
			playDashShockwaveVFX()
			pcall(function()
				local setSprintRemote = Network.GetRemoteEvent(Network.Remotes.SetSprint)
				setSprintRemote:FireServer(true)
			end)
		end
	elseif input.UserInputType == Enum.UserInputType.MouseButton1 or input.KeyCode == Enum.KeyCode.ButtonR2 then
		performAttack()
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = false
		stopSpeedSprintVFX()
		pcall(function()
			local setSprintRemote = Network.GetRemoteEvent(Network.Remotes.SetSprint)
			setSprintRemote:FireServer(false)
		end)
	end
end)

-- Cleanup on death
humanoid.Died:Connect(function()
	stopSpeedSprintVFX()
	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if rootPart then
		local oldAttachment = rootPart:FindFirstChild("AttackNudgeAttachment")
		if oldAttachment then oldAttachment:Destroy() end
		local oldLV = rootPart:FindFirstChild("AttackLinearVelocity")
		if oldLV then oldLV:Destroy() end
	end
end)

-- ─────────────────────────────────────────────────────────────────────────────
-- Locomotion Update Loop
-- ─────────────────────────────────────────────────────────────────────────────

function playIdle()
	if isAttacking then return end
	if WalkTrack and WalkTrack.IsPlaying then
		WalkTrack:Stop(0.25)
	end
	if RunTrack and RunTrack.IsPlaying then
		RunTrack:Stop(0.25)
	end
	if IdleTrack and not IdleTrack.IsPlaying then
		IdleTrack:Play(0.25)
	end
	if IdleTrack then
		IdleTrack:AdjustSpeed(1)
	end
end

function UpdateMovement()
	if player:GetAttribute("InLobby") ~= false then
		stopSpeedSprintVFX()
		playIdle()
		return
	end

	-- During attack swing or skill cast, keep character stationary (unless skill manages velocity)
	if isAttacking or character:GetAttribute("IsSkillCasting") == true then
		if character:GetAttribute("IsSkillCasting") == true and character:GetAttribute("AllowSkillMovement") == true then
			-- Skill allows movement (e.g. spin attack or dash)
			if humanoid.WalkSpeed == 0 then
				humanoid.WalkSpeed = WALK_SPEED
			end
		else
			humanoid.WalkSpeed = 0
		end
		stopSpeedSprintVFX()
		return
	end

	if not WalkTrack or not RunTrack or not IdleTrack then return end

	local isMoving = humanoid.MoveDirection.Magnitude > 0
	local isGrounded = not AirborneState[humanoid:GetState()]

	if isMoving and isGrounded then
		if IdleTrack.IsPlaying then
			IdleTrack:Stop(0.25)
		end
		if isSprinting then
			humanoid.WalkSpeed = RUN_SPEED
			if WalkTrack.IsPlaying then
				WalkTrack:Stop(0.25)
			end
			if not RunTrack.IsPlaying then
				RunTrack:Play(0.25)
			end
			RunTrack:AdjustSpeed(1)
			startSpeedSprintVFX()
		else
			humanoid.WalkSpeed = WALK_SPEED
			stopSpeedSprintVFX()
			if RunTrack.IsPlaying then
				RunTrack:Stop(0.25)
			end
			if not WalkTrack.IsPlaying then
				WalkTrack:Play(0.25)
			end
			WalkTrack:AdjustSpeed(1)
		end
	elseif isMoving and not isGrounded then
		if IdleTrack.IsPlaying then
			IdleTrack:Stop(0.25)
		end
		if isSprinting then
			if WalkTrack.IsPlaying then
				WalkTrack:Stop(0.25)
			end
			if not RunTrack.IsPlaying then
				RunTrack:Play(0.25)
			end
			RunTrack:AdjustSpeed(0.25)
			startSpeedSprintVFX()
		else
			stopSpeedSprintVFX()
			if RunTrack.IsPlaying then
				RunTrack:Stop(0.25)
			end
			if not WalkTrack.IsPlaying then
				WalkTrack:Play(0.25)
			end
			WalkTrack:AdjustSpeed(0.25)
		end
	else
		humanoid.WalkSpeed = WALK_SPEED
		stopSpeedSprintVFX()
		playIdle()
	end
end

RunService.Heartbeat:Connect(UpdateMovement)

-- Load initial animations and listen for class changes
task.spawn(function()
	local currentClass = player:GetAttribute("SelectedClass") or "default"
	loadClassAnimations(currentClass)

	player:GetAttributeChangedSignal("SelectedClass"):Connect(function()
		local newClass = player:GetAttribute("SelectedClass") or "default"
		loadClassAnimations(newClass)
	end)
end)
