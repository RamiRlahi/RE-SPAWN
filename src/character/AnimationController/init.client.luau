local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = game.Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

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

local WalkTrack, RunTrack, IdleTrack

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
	}
}

-- Forward declarations
local UpdateMovement
local playIdle

-- Verify if animations load successfully
local function monitorTrack(name, track)
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
	-- Stop any currently playing tracks
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

	-- Wait for all animation assets to finish downloading
	while WalkTrack.Length == 0 or RunTrack.Length == 0 or IdleTrack.Length == 0 do
		task.wait()
	end
	
	print(`[AnimationController] Animations loaded for class: {classId}`)
	if UpdateMovement then
		UpdateMovement()
	end
end




local WALK_SPEED = 16
local RUN_SPEED = 26

local AirborneState = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local isSprinting = false

UserInputService.InputBegan:Connect(function(input, gpe)
	if gpe then return end
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
		isSprinting = false
	end
end)

function playIdle()
	if WalkTrack.IsPlaying then
		WalkTrack:Stop(0.25)
	end
	if RunTrack.IsPlaying then
		RunTrack:Stop(0.25)
	end
	if not IdleTrack.IsPlaying then
		print("[AnimationController] Playing Idle | ID:", idleAnim.AnimationId)
		IdleTrack:Play(0.25)
	end
	IdleTrack:AdjustSpeed(1)
end

function UpdateMovement()
	if player:GetAttribute("InLobby") ~= false then
		playIdle()
		return
	end

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
				print("[AnimationController] Playing Run | ID:", runAnim.AnimationId)
				RunTrack:Play(0.25)
			end
			RunTrack:AdjustSpeed(1)
		else
			humanoid.WalkSpeed = WALK_SPEED
			if RunTrack.IsPlaying then
				RunTrack:Stop(0.25)
			end
			if not WalkTrack.IsPlaying then
				print("[AnimationController] Playing Walk | ID:", walkAnim.AnimationId)
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
				print("[AnimationController] Playing Run (Airborne) | ID:", runAnim.AnimationId)
				RunTrack:Play(0.25)
			end
			RunTrack:AdjustSpeed(0.25)
		else
			if RunTrack.IsPlaying then
				RunTrack:Stop(0.25)
			end
			if not WalkTrack.IsPlaying then
				print("[AnimationController] Playing Walk (Airborne) | ID:", walkAnim.AnimationId)
				WalkTrack:Play(0.25)
			end
			WalkTrack:AdjustSpeed(0.25)
		end
	else
		humanoid.WalkSpeed = WALK_SPEED
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
