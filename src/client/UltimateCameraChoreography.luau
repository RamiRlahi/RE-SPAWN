--[[
	UltimateCameraChoreography.luau
	Client-side camera choreography controller for Ultimate attack cinematic.
	
	Timeline:
	SHOT 1 (0.00–1.00s, 1.0s): Front close-up cinematic angle during windup animation.
	                           Sword charges up with flame aura.
	
	t = 1.00s: First animation finishes -> player begins slash animation.
	           Camera is immediately restored back to standard gameplay camera.
	
	t = 1.50s: Traveling slash VFX launches forward.
	t = 2.10s: Impact explosion occurs at target position.
--]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local UltimateCameraChoreography = {}

local activeSequenceToken = 0

-- ─────────────────────────────────────────────────────────────────────────────
-- Close-up: the shared "ult wind-up" shot every class uses.
-- The camera cuts to the front of the character (slightly right and above),
-- drifts in on the face for `duration`, then snaps back to the gameplay camera.
-- `onRelease` fires right before the hand-back (the ult's release moment).
-- Returns a function reporting whether this shot is still the active one.
--
-- `framing` overrides the shot: offsets are { forward, right, up } from the
-- character (forward = toward the camera side the character faces).
-- ─────────────────────────────────────────────────────────────────────────────
export type Framing = {
	startOffset: { number },
	endOffset: { number },
	focusHeight: number,
	fovStart: number,
	fovEnd: number,
}

local DEFAULT_FRAMING: Framing = {
	startOffset = { 5.5, 2.5, 3.2 },
	endOffset = { 4.8, 2.2, 2.8 },
	focusHeight = 2.2,
	fovStart = 55,
	fovEnd = 58,
}

function UltimateCameraChoreography.PlayCloseUp(
	character: Model,
	aimDirection: Vector3,
	duration: number?,
	onRelease: (() -> ())?,
	onComplete: (() -> ())?,
	framing: Framing?
): () -> boolean
	local frame = framing or DEFAULT_FRAMING
	activeSequenceToken += 1
	local myToken = activeSequenceToken
	local shotDur = duration or 1.0

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local function isStillActive(): boolean
		return activeSequenceToken == myToken and character.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
	end
	if not rootPart or not humanoid then return isStillActive end

	-- Pause IsometricCamera if active
	local successIso, IsometricCamera = pcall(function()
		return require(script.Parent:WaitForChild("IsometricCamera"))
	end)
	local wasIsoActive = false
	if successIso and IsometricCamera and IsometricCamera.IsActive and IsometricCamera.IsActive() then
		wasIsoActive = true
		IsometricCamera.Pause()
	end

	camera.CameraType = Enum.CameraType.Scriptable

	local flatDir = Vector3.new(aimDirection.X, 0, aimDirection.Z)
	if flatDir.Magnitude < 0.001 then
		flatDir = rootPart.CFrame.LookVector
	end
	flatDir = flatDir.Unit
	local rightVec = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDir).RightVector

	local function restoreCamera()
		if activeSequenceToken ~= myToken then return end
		if wasIsoActive and successIso and IsometricCamera then
			IsometricCamera.Resume(0.4)
		else
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			camera.CameraSubject = humanoid
		end
		if onComplete then
			pcall(onComplete)
		end
	end

	task.spawn(function()
		local charPos = rootPart.Position
		local function offset(o: { number }): Vector3
			return charPos + flatDir * o[1] + rightVec * o[2] + Vector3.new(0, o[3], 0)
		end
		local shotStart = offset(frame.startOffset)
		-- Subtle drift over the shot (by default: creeps slightly closer and lower)
		local shotEnd = offset(frame.endOffset)
		local focusUp = Vector3.new(0, frame.focusHeight, 0)
		camera.CFrame = CFrame.lookAt(shotStart, charPos + focusUp)
		camera.FieldOfView = frame.fovStart

		local t0 = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			if not isStillActive() or os.clock() - t0 >= shotDur then
				if conn then conn:Disconnect() end
				return
			end
			local alpha = math.clamp((os.clock() - t0) / shotDur, 0, 1)
			local smooth = 1 - math.pow(1 - alpha, 2)
			-- Track the character's head/chest area as focus point
			camera.CFrame = CFrame.lookAt(shotStart:Lerp(shotEnd, smooth), rootPart.Position + focusUp)
			camera.FieldOfView = frame.fovStart + (frame.fovEnd - frame.fovStart) * smooth
		end)

		task.wait(shotDur)
		if conn then conn:Disconnect() end
		if not isStillActive() then restoreCamera() return end

		if onRelease then
			local ok, err = pcall(onRelease)
			if not ok then
				warn("[UltimateCameraChoreography] onRelease failed:", err)
			end
		end
		restoreCamera()
	end)

	return isStillActive
end

-- Heavy Knight: close-up during the wind-up animation, slash starts on the
-- hand-back, impact explosion 1.10s later.
function UltimateCameraChoreography.PlaySequence(
	character: Model,
	aimDirection: Vector3,
	onImpact: (() -> ())?,
	onComplete: (() -> ())?,
	onSlashStart: (() -> ())?
)
	local isStillActive
	isStillActive = UltimateCameraChoreography.PlayCloseUp(character, aimDirection, 1.0, function()
		if onSlashStart then onSlashStart() end
		task.delay(1.10, function()
			if isStillActive() and onImpact then
				pcall(onImpact)
			end
		end)
	end, onComplete)
end

function UltimateCameraChoreography.StopSequence()
	activeSequenceToken += 1
	local successIso, IsometricCamera = pcall(function()
		return require(script.Parent:WaitForChild("IsometricCamera"))
	end)
	if successIso and IsometricCamera and IsometricCamera.IsPaused and IsometricCamera.IsPaused() then
		IsometricCamera.Resume(0.35)
	else
		camera.CameraType = Enum.CameraType.Custom
		camera.FieldOfView = 70
		local char = player.Character
		if char then
			local humanoid = char:FindFirstChildOfClass("Humanoid")
			if humanoid then camera.CameraSubject = humanoid end
		end
	end
end

return UltimateCameraChoreography
