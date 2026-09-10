--[[
	UltimateCameraChoreography.luau
	Client-side camera choreography controller for Ultimate attack cinematic.
	
	4-shot cinematic matching reference timeline (fast zoom-out + snappy slash):
	
	SHOT 1 (0.00–1.00s, 1.0s): Broad cinematic angle behind character showing full body + glowing sword.
	                           Windup animation (84579017139529) plays. Sword charges up with flame aura.
	
	SHOT 2 (1.00–1.50s, 0.5s): FAST dramatic zoom-out pullback. VFX slash launches at t=1.00s
	                           simultaneously with the zoom out. Slash animation begins.
	
	SHOT 3 (1.50–2.10s, 0.6s): Fast low-angle tracking shot following the traveling 'hk_ult_slash'
	                           speeding forward across the terrain (very fast travel).
	
	SHOT 4 (2.10–3.10s, 1.0s): Wide third-person view of the impact explosion — smaller and less
	                           blinding than before. Reduced shake and FOV pop.
	
	Hard cuts between all shots. Restores camera cleanly to gameplay view at t = 3.10s.
--]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local UltimateCameraChoreography = {}

local activeSequenceToken = 0

function UltimateCameraChoreography.PlaySequence(
	character: Model,
	aimDirection: Vector3,
	onImpact: (() -> ())?,
	onComplete: (() -> ())?,
	onSlashStart: (() -> ())?
)
	activeSequenceToken += 1
	local myToken = activeSequenceToken

	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	-- Pause IsometricCamera if active
	local successIso, IsometricCamera = pcall(function()
		return require(script.Parent:WaitForChild("IsometricCamera"))
	end)
	local wasIsoActive = false
	if successIso and IsometricCamera and IsometricCamera.IsActive and IsometricCamera.IsActive() then
		wasIsoActive = true
		IsometricCamera.Pause()
	end

	-- Take over camera
	camera.CameraType = Enum.CameraType.Scriptable

	local function isStillActive()
		return activeSequenceToken == myToken and character.Parent ~= nil and humanoid.Health > 0
	end

	-- Flatten aim direction
	local flatDir = Vector3.new(aimDirection.X, 0, aimDirection.Z)
	if flatDir.Magnitude < 0.001 then
		flatDir = rootPart.CFrame.LookVector
	end
	flatDir = flatDir.Unit

	local facingCF = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDir)
	local rightVec = facingCF.RightVector
	local lookVec = flatDir

	-- Find the sword/weapon part for tracking
	local function getSwordPart(): BasePart
		local tool = character:FindFirstChildOfClass("Tool")
		if tool then
			for _, desc in ipairs(tool:GetDescendants()) do
				if desc:IsA("MeshPart") or (desc:IsA("BasePart") and desc.Name ~= "Handle") then
					return desc
				end
			end
			if tool:FindFirstChild("Handle") then
				return tool.Handle :: BasePart
			end
		end
		return character:FindFirstChild("RightHand") or character:FindFirstChild("Right Arm") or rootPart
	end

	-- Camera shake helper
	local function triggerShake(intensity: number, duration: number)
		task.spawn(function()
			local startTime = os.clock()
			while os.clock() - startTime < duration and isStillActive() do
				local alpha = 1 - ((os.clock() - startTime) / duration)
				local cur = intensity * alpha
				local offset = Vector3.new(
					(math.random() - 0.5) * cur,
					(math.random() - 0.5) * cur * 0.6,
					(math.random() - 0.5) * cur
				)
				camera.CFrame = camera.CFrame * CFrame.new(offset)
				RunService.RenderStepped:Wait()
			end
		end)
	end

	-- Restore camera helper
	local function restoreCamera()
		if activeSequenceToken ~= myToken then return end
		if wasIsoActive and successIso and IsometricCamera then
			IsometricCamera.Resume(0.4)
		else
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			if humanoid then
				camera.CameraSubject = humanoid
			end
		end
		if onComplete then
			pcall(onComplete)
		end
	end

	task.spawn(function()
		-- =====================================================================
		-- SHOT 1: 0.00s – 1.00s | Front Close-Up View (1.0s)
		-- Camera in FRONT of character, slightly above and to the right,
		-- looking back at the character's face/upper body during windup.
		-- =====================================================================
		local charPos = rootPart.Position
		local swordPart = getSwordPart()

		-- Camera positioned in front of the character, slightly right and above
		local frontOffset = lookVec * 5.5 + rightVec * 2.5 + Vector3.new(0, 3.2, 0)
		local shot1Start = charPos + frontOffset
		-- Subtle drift: camera creeps slightly closer and lower over the 1s
		local shot1End = charPos + lookVec * 4.8 + rightVec * 2.2 + Vector3.new(0, 2.8, 0)

		-- Focus on character's upper body / face area
		local faceFocus = charPos + Vector3.new(0, 2.2, 0)

		camera.CFrame = CFrame.lookAt(shot1Start, faceFocus)
		camera.FieldOfView = 55

		local shot1Conn: RBXScriptConnection? = nil
		local shot1StartTime = os.clock()
		local SHOT1_DUR = 1.00

		shot1Conn = RunService.RenderStepped:Connect(function()
			if not isStillActive() or os.clock() - shot1StartTime >= SHOT1_DUR then
				if shot1Conn then shot1Conn:Disconnect() end
				return
			end
			local elapsed = os.clock() - shot1StartTime
			local alpha = math.clamp(elapsed / SHOT1_DUR, 0, 1)
			local smooth = 1 - math.pow(1 - alpha, 2)

			local curPos = shot1Start:Lerp(shot1End, smooth)
			-- Track the character's head/chest area as focus point
			local curFocus = rootPart.Position + Vector3.new(0, 2.2, 0)
			camera.CFrame = CFrame.lookAt(curPos, curFocus)
			camera.FieldOfView = 55 + (58 - 55) * smooth
		end)

		task.wait(SHOT1_DUR)
		if shot1Conn then shot1Conn:Disconnect() end
		if not isStillActive() then restoreCamera() return end

		-- =====================================================================
		-- SHOT 2: 1.00s – 1.50s | FAST Front Zoom-Out (0.50s)
		-- NO hard cut — continues from Shot 1's front position and rapidly
		-- pulls back and up, revealing the full character from the front.
		-- VFX slash launches simultaneously with the zoom out.
		-- =====================================================================
		local SHOT2_DUR = 0.50

		-- Fire slash start callback immediately — VFX launches WITH the zoom out
		if onSlashStart then
			pcall(onSlashStart)
		end

		-- Start from where Shot 1 ended (front of character, close)
		local shot2Start = rootPart.Position + lookVec * 4.8 + rightVec * 2.2 + Vector3.new(0, 2.8, 0)
		-- Pull way back and up from the front — dramatic fast zoom out
		local shot2End = rootPart.Position + lookVec * 14.0 + rightVec * 5.0 + Vector3.new(0, 8.0, 0)

		-- Focus stays on character
		local shot2Focus = rootPart.Position + Vector3.new(0, 2.0, 0)

		camera.CFrame = CFrame.lookAt(shot2Start, shot2Focus)
		camera.FieldOfView = 58

		local shot2Conn: RBXScriptConnection? = nil
		local shot2StartTime = os.clock()

		shot2Conn = RunService.RenderStepped:Connect(function()
			if not isStillActive() or os.clock() - shot2StartTime >= SHOT2_DUR then
				if shot2Conn then shot2Conn:Disconnect() end
				return
			end
			local elapsed = os.clock() - shot2StartTime
			local alpha = math.clamp(elapsed / SHOT2_DUR, 0, 1)
			-- Very aggressive easing for fast zoom-out feel
			local smooth = 1 - math.pow(1 - alpha, 4)

			local curPos = shot2Start:Lerp(shot2End, smooth)
			local curFocus = rootPart.Position + Vector3.new(0, 2.0 + 1.0 * smooth, 0)
			camera.CFrame = CFrame.lookAt(curPos, curFocus)
			-- Dramatic FOV ramp for zoom-out effect
			camera.FieldOfView = 58 + (80 - 58) * smooth
		end)

		task.wait(SHOT2_DUR)
		if shot2Conn then shot2Conn:Disconnect() end
		if not isStillActive() then restoreCamera() return end

		-- =====================================================================
		-- SHOT 3: 1.50s – 2.10s | Fast Low Tracking of 'hk_ult_slash' (0.6s)
		-- Hard cut. Fast tracking angle following the speeding slash wave.
		-- =====================================================================
		local SHOT3_DUR = 0.60

		local vfxStartPos = rootPart.Position + lookVec * 3.0
		local vfxEndPos = rootPart.Position + lookVec * 32.0
		local groundY = rootPart.Position.Y - 2.5
		local lowHeight = groundY + 2.0

		local cam3Offset = rightVec * 8.0 + Vector3.new(0, lowHeight - rootPart.Position.Y + 4.0, 0)

		-- Hard cut
		camera.FieldOfView = 70

		local shot3Conn: RBXScriptConnection? = nil
		local shot3StartTime = os.clock()

		shot3Conn = RunService.RenderStepped:Connect(function()
			if not isStillActive() or os.clock() - shot3StartTime >= SHOT3_DUR then
				if shot3Conn then shot3Conn:Disconnect() end
				return
			end
			local elapsed = os.clock() - shot3StartTime
			local alpha = math.clamp(elapsed / SHOT3_DUR, 0, 1)
			local smooth = alpha

			-- Current slash wave position moving forward fast
			local vfxPos = vfxStartPos:Lerp(vfxEndPos, smooth)

			-- Camera travels alongside
			local camPos = vfxPos + cam3Offset - lookVec * (7.5 + 3.0 * (1 - alpha))
			camPos = Vector3.new(camPos.X, lowHeight + math.sin(alpha * math.pi * 0.5) * 0.5, camPos.Z)

			-- Look ahead of traveling slash wave
			local lookTarget = vfxPos + lookVec * 6.0 + Vector3.new(0, 1.2, 0)

			camera.CFrame = CFrame.lookAt(camPos, lookTarget)
			camera.FieldOfView = 70 + (78 - 70) * (alpha * 0.8)

			-- Dynamic rumble as slash moves
			local shakeMag = 0.12 + 0.18 * alpha
			local shakeOff = Vector3.new(
				(math.random() - 0.5) * shakeMag,
				(math.random() - 0.5) * shakeMag * 0.4,
				(math.random() - 0.5) * shakeMag
			)
			camera.CFrame = camera.CFrame * CFrame.new(shakeOff)
		end)

		task.wait(SHOT3_DUR)
		if shot3Conn then shot3Conn:Disconnect() end
		if not isStillActive() then restoreCamera() return end

		-- =====================================================================
		-- SHOT 4: 2.10s – 3.10s | Impact Explosion View (1.0s)
		-- Hard cut. Wide view of the explosion — smaller and less blinding.
		-- Reduced FOV pop and shake intensity.
		-- =====================================================================
		local SHOT4_DUR = 1.00
		local impactPos = rootPart.Position + lookVec * 32.0

		-- Fire impact VFX callback at t = 2.10s
		if onImpact then
			pcall(onImpact)
		end

		local shoulderStart = rootPart.Position - lookVec * 11.5 + rightVec * 5.0 + Vector3.new(0, 6.0, 0)
		local shoulderEnd = rootPart.Position - lookVec * 9.5 + rightVec * 4.0 + Vector3.new(0, 5.0, 0)

		local explosionFocus = impactPos + Vector3.new(0, 1.8, 0)

		-- Hard cut
		camera.CFrame = CFrame.lookAt(shoulderStart, explosionFocus)
		camera.FieldOfView = 78

		-- Smaller FOV pop (was 85→72, now 78→70) — less blinding
		local fovTween = TweenService:Create(
			camera,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = 70 }
		)
		fovTween:Play()

		-- Reduced impact shake (was 1.3 intensity, now 0.7)
		triggerShake(0.7, 0.35)

		local shot4Conn: RBXScriptConnection? = nil
		local shot4StartTime = os.clock()

		shot4Conn = RunService.RenderStepped:Connect(function()
			if not isStillActive() or os.clock() - shot4StartTime >= SHOT4_DUR then
				if shot4Conn then shot4Conn:Disconnect() end
				return
			end
			local elapsed = os.clock() - shot4StartTime
			local alpha = math.clamp(elapsed / SHOT4_DUR, 0, 1)
			local smooth = 1 - math.pow(1 - alpha, 2)

			local curPos = shoulderStart:Lerp(shoulderEnd, smooth)
			local curFocus = explosionFocus + Vector3.new(0, -0.4 * smooth, 0)
			camera.CFrame = CFrame.lookAt(curPos, curFocus)
		end)

		task.wait(SHOT4_DUR)
		if shot4Conn then shot4Conn:Disconnect() end

		-- =====================================================================
		-- RESTORATION: Return camera control cleanly
		-- =====================================================================
		restoreCamera()
	end)
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
