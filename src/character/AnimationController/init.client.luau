local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local player = game.Players.LocalPlayer
local character = script.Parent
local humanoid = character:WaitForChild("Humanoid")
local animator = humanoid:WaitForChild("Animator")

local walkAnim = script:WaitForChild("walk")
local runAnim = script:WaitForChild("run")
local idleAnim = script:WaitForChild("idle")

walkAnim.AnimationId = "rbxassetid://109247200419554"
runAnim.AnimationId = "rbxassetid://79701746140908"
idleAnim.AnimationId = "rbxassetid://86968114690424"

local WalkTrack = animator:LoadAnimation(walkAnim)
WalkTrack.Priority = Enum.AnimationPriority.Action
WalkTrack.Looped = true

local RunTrack = animator:LoadAnimation(runAnim)
RunTrack.Priority = Enum.AnimationPriority.Action
RunTrack.Looped = true

local IdleTrack = animator:LoadAnimation(idleAnim)
IdleTrack.Priority = Enum.AnimationPriority.Action
IdleTrack.Looped = true

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

local function playIdle()
	if WalkTrack.IsPlaying then
		WalkTrack:Stop(0.25)
	end
	if RunTrack.IsPlaying then
		RunTrack:Stop(0.25)
	end
	if not IdleTrack.IsPlaying then
		IdleTrack:Play(0.25)
	end
	IdleTrack:AdjustSpeed(1)
end

local function UpdateMovement()
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
				RunTrack:Play(0.25)
			end
			RunTrack:AdjustSpeed(1)
		else
			humanoid.WalkSpeed = WALK_SPEED
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
		else
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
		playIdle()
	end
end

RunService.Heartbeat:Connect(UpdateMovement)
