--[[
	StarterCharacterScripts LocalScript — this is the file that uses the animation IDs.
	Cloned onto each character. Default Animate still handles idle / jump / fall.
--]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))

local player = Players.LocalPlayer
local character = script.Parent :: Model
local humanoid = character:WaitForChild("Humanoid") :: Humanoid
local animator = humanoid:WaitForChild("Animator") :: Animator

local WALK_ANIM_ID = "rbxassetid://99722016521113"
local SPRINT_ANIM_ID = "rbxassetid://91122724973926"

local WALK_SPEED = 16
local SPRINT_SPEED = 26

type MoveState = "Idle" | "Walk" | "Sprint"

local isSprinting = false
local currentMoveState: MoveState = "Idle"
local walkTrack: AnimationTrack? = nil
local sprintTrack: AnimationTrack? = nil

local AirborneState = {
	[Enum.HumanoidStateType.Freefall] = true,
	[Enum.HumanoidStateType.Jumping] = true,
	[Enum.HumanoidStateType.FallingDown] = true,
}

local function isTrackReady(track: AnimationTrack?): boolean
	return track ~= nil and track.Length > 0
end

local function loadTrack(animationId: string, name: string): AnimationTrack?
	local animation = Instance.new("Animation")
	animation.Name = name
	animation.AnimationId = animationId

	local ok, result = pcall(function()
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

	local deadline = os.clock() + 2
	while track.Length == 0 and os.clock() < deadline do
		task.wait(0.05)
	end

	if track.Length == 0 then
		warn("[AnimCtrl]", name, "did not load (Length 0). Leaving default Animate in charge for this clip.", animationId)
		return nil
	end

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
		if isTrackReady(walkTrack) then
			walkTrack:Play(0.15, 1, 1)
		end
	elseif newState == "Sprint" then
		if walkTrack and walkTrack.IsPlaying then
			walkTrack:Stop(0.15)
		end
		if isTrackReady(sprintTrack) then
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

walkTrack = loadTrack(WALK_ANIM_ID, "CustomWalk")
sprintTrack = loadTrack(SPRINT_ANIM_ID, "CustomSprint")

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

RunService.Heartbeat:Connect(function()
	if humanoid.Health <= 0 then
		return
	end

	if player:GetAttribute("InLobby") ~= false then
		setMovementState("Idle")
		return
	end

	local isMoving = humanoid.MoveDirection.Magnitude > 0.1
	local isGrounded = not AirborneState[humanoid:GetState()]

	if isMoving and isGrounded then
		if isSprinting then
			humanoid.WalkSpeed = SPRINT_SPEED
			setMovementState("Sprint")
		else
			humanoid.WalkSpeed = WALK_SPEED
			setMovementState("Walk")
		end
	else
		humanoid.WalkSpeed = WALK_SPEED
		setMovementState("Idle")
	end
end)
