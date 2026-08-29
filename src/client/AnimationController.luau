--[[
	AnimationController (Client-Side)
	Disables default Animate (which only plays walk and scales it with speed)
	and drives distinct Walk / Sprint tracks from Shift.
--]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContentProvider = game:GetService("ContentProvider")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))

local player = Players.LocalPlayer

local WALK_ANIM_ID = "rbxassetid://99722016521113"
local SPRINT_ANIM_ID = "rbxassetid://91122724973926"

local WALK_SPEED = 16
local SPRINT_SPEED = 26

local AnimationController = {}

type MoveState = "Idle" | "Walk" | "Sprint"

local isSprinting = false
local currentMoveState: MoveState = "Idle"

local currentHumanoid: Humanoid? = nil
local currentAnimator: Animator? = nil
local walkTrack: AnimationTrack? = nil
local sprintTrack: AnimationTrack? = nil
local heartbeatConn: RBXScriptConnection? = nil
local animateAddedConn: RBXScriptConnection? = nil

local AirborneState = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local function disableDefaultAnimate(character: Model)
	if animateAddedConn then
		animateAddedConn:Disconnect()
		animateAddedConn = nil
	end

	local function disableIfAnimate(inst: Instance)
		if inst.Name == "Animate" and inst:IsA("BaseScript") then
			inst.Disabled = true
		end
	end

	for _, child in ipairs(character:GetChildren()) do
		disableIfAnimate(child)
	end

	animateAddedConn = character.ChildAdded:Connect(disableIfAnimate)
end

local function stopDefaultLocomotionTracks(animator: Animator)
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		if track ~= walkTrack and track ~= sprintTrack then
			local priority = track.Priority
			if priority == Enum.AnimationPriority.Core or priority == Enum.AnimationPriority.Idle or priority == Enum.AnimationPriority.Movement then
				track:Stop(0)
			end
		end
	end
end

local function loadTrack(animator: Animator, animationId: string, name: string): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId

	local ok, result = pcall(function()
		ContentProvider:PreloadAsync({ animation })
		return animator:LoadAnimation(animation)
	end)

	if not ok or typeof(result) ~= "Instance" then
		warn("[AnimCtrl] Failed to load", name, animationId, result)
		animation:Destroy()
		return nil
	end

	local track = result :: AnimationTrack
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = true
	return track
end

local function setMovementState(newState: MoveState)
	if currentMoveState == newState then
		return
	end

	currentMoveState = newState

	if newState == "Walk" then
		if sprintTrack and sprintTrack.IsPlaying then
			sprintTrack:Stop(0.15)
		end
		if walkTrack then
			walkTrack:Play(0.15, 1, 1)
		end
	elseif newState == "Sprint" then
		if walkTrack and walkTrack.IsPlaying then
			walkTrack:Stop(0.15)
		end
		if sprintTrack then
			sprintTrack:Play(0.15, 1, 1)
		end
	else
		if walkTrack and walkTrack.IsPlaying then
			walkTrack:Stop(0.15)
		end
		if sprintTrack and sprintTrack.IsPlaying then
			sprintTrack:Stop(0.15)
		end
	end
end

local function setupCharacter(character: Model)
	if heartbeatConn then
		heartbeatConn:Disconnect()
		heartbeatConn = nil
	end

	currentMoveState = "Idle"
	walkTrack = nil
	sprintTrack = nil

	local humanoid = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if not humanoid then
		return
	end
	currentHumanoid = humanoid

	local animator = humanoid:WaitForChild("Animator", 10) :: Animator?
	if not animator then
		return
	end
	currentAnimator = animator

	disableDefaultAnimate(character)
	stopDefaultLocomotionTracks(animator)

	walkTrack = loadTrack(animator, WALK_ANIM_ID, "CustomWalk")
	sprintTrack = loadTrack(animator, SPRINT_ANIM_ID, "CustomSprint")

	task.delay(1, function()
		if walkTrack and walkTrack.Length == 0 then
			warn("[AnimCtrl] Walk animation failed to load (Length 0). Check that asset", WALK_ANIM_ID, "is an R15 animation published for this experience.")
		end
		if sprintTrack and sprintTrack.Length == 0 then
			warn("[AnimCtrl] Sprint animation failed to load (Length 0). Check that asset", SPRINT_ANIM_ID, "is an R15 animation published for this experience.")
		end
	end)

	local function UpdateMovement()
		if not currentHumanoid or currentHumanoid.Health <= 0 then
			return
		end

		if player:GetAttribute("InLobby") ~= false then
			setMovementState("Idle")
			return
		end

		if currentAnimator then
			stopDefaultLocomotionTracks(currentAnimator)
		end

		local isMoving = currentHumanoid.MoveDirection.Magnitude > 0.1
		local isGrounded = not AirborneState[currentHumanoid:GetState()]

		if isMoving and isGrounded then
			if isSprinting then
				currentHumanoid.WalkSpeed = SPRINT_SPEED
				setMovementState("Sprint")
			else
				currentHumanoid.WalkSpeed = WALK_SPEED
				setMovementState("Walk")
			end
		else
			currentHumanoid.WalkSpeed = WALK_SPEED
			setMovementState("Idle")
		end
	end

	heartbeatConn = RunService.Heartbeat:Connect(UpdateMovement)
end

function AnimationController.Init()
	local setSprintRemote = Network.GetRemoteEvent(Network.Remotes.SetSprint)

	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then
			return
		end
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			isSprinting = true
			if setSprintRemote then
				setSprintRemote:FireServer(true)
			end
		end
	end)

	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.LeftShift or input.KeyCode == Enum.KeyCode.RightShift then
			isSprinting = false
			if setSprintRemote then
				setSprintRemote:FireServer(false)
			end
		end
	end)

	if player.Character then
		task.spawn(setupCharacter, player.Character)
	end
	player.CharacterAdded:Connect(setupCharacter)
end

return AnimationController
