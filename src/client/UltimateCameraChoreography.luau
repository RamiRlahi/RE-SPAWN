--[[
	UltimateCameraChoreography.luau
	Client-side camera choreography controller for Ultimate attack cinematic.
	
	4-shot cinematic matching reference timeline (faster projectile & wide framing):
	
	SHOT 1 (0.00–1.00s, 1.0s): Broad cinematic angle behind character showing full body + glowing sword.
	                           Windup animation (84579017139529) plays. Sword charges up with flame aura.
	
	SHOT 2 (1.00–1.70s, 0.7s): Wide-angle dynamic pullback showing character mid-swing + slash start.
	                           Slash animation (108875775887071) begins.
	
	SHOT 3 (1.70–2.80s, 1.1s): Fast low-angle tracking shot following the traveling 'hk_ult_slash'
	                           speeding forward across the terrain.
	
	SHOT 4 (2.80–4.00s, 1.2s): Wide third-person view looking down the corridor at the 'Light Explosion VFX'
	                           impact explosion and shockwave.
	
	Hard cuts between all shots. Restores camera cleanly to gameplay view at t = 4.00s.
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
		-- SHOT 1: 0.00s – 1.00s | Wide Over-Shoulder Charge View
		-- Generous camera distance showing full character stance + glowing sword.
		-- =====================================================================
		local charPos = rootPart.Position
		local swordPart = getSwordPart()

		local swordFocus = swordPart.Position
		local behindOffset = -lookVec * 8.5 + rightVec * 4.0 + Vector3.new(0, 4.8, 0)
		local shot1Start = charPos + behindOffset
		local shot1End = charPos + behindOffset + lookVec * 1.2 - Vector3.new(0, 0.4, 0)

		camera.CFrame = CFrame.lookAt(shot1Start, swordFocus)
		camera.FieldOfView = 60

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
			local curSwordPos = swordPart and swordPart.Position or (rootPart.Position + Vector3.new(0, 3, 0))
			camera.CFrame = CFrame.lookAt(curPos, curSwordPos)
			camera.FieldOfView = 60 + (64 - 60) * smooth
		end)

		task.wait(SHOT1_DUR)
		if shot1Conn then shot1Conn:Disconnect() end
		if not isStillActive() then restoreCamera() return end

		-- =====================================================================
		-- SHOT 2: 1.00s – 1.70s | Wide Dynamic Swing Pullback
		-- Hard cut. Wide angle showing full character mid-swing.
		-- =====================================================================
		local SHOT2_DUR = 0.70

		if onSlashStart then
			pcall(onSlashStart)
		end

		local swingFocus = rootPart.Position + Vector3.new(0, 2.0, 0) + lookVec * 3.0
		local shot2Start = rootPart.Position - lookVec * 10.0 + rightVec * 7.5 + Vector3.new(0, 5.5, 0)
		local shot2End = rootPart.Position - lookVec * 14.0 + rightVec * 10.0 + Vector3.new(0, 7.0, 0)

		-- Hard cut
		camera.CFrame = CFrame.lookAt(shot2Start, swingFocus)
		camera.FieldOfView = 66

		local shot2Conn: RBXScriptConnection? = nil
		local shot2StartTime = os.clock()

		shot2Conn = RunService.RenderStepped:Connect(function()
			if not isStillActive() or os.clock() - shot2StartTime >= SHOT2_DUR then
				if shot2Conn then shot2Conn:Disconnect() end
				return
			end
			local elapsed = os.clock() - shot2StartTime
			local alpha = math.clamp(elapsed / SHOT2_DUR, 0, 1)
			local smooth = 1 - math.pow(1 - alpha, 3)

			local curPos = shot2Start:Lerp(shot2End, smooth)
			local curFocus = rootPart.Position + Vector3.new(0, 2.2, 0) + lookVec * (3.0 + 4.0 * smooth)
			camera.CFrame = CFrame.lookAt(curPos, curFocus)
			camera.FieldOfView = 66 + (76 - 66) * smooth
		end)

		task.wait(SHOT2_DUR)
		if shot2Conn then shot2Conn:Disconnect() end
		if not isStillActive() then restoreCamera() return end

		-- =====================================================================
		-- SHOT 3: 1.70s – 2.80s | Fast Low Tracking of 'hk_ult_slash' (1.1s)
		-- Hard cut. Fast tracking angle following the speeding slash wave.
		-- =====================================================================
		local SHOT3_DUR = 1.10

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
		-- SHOT 4: 2.80s – 4.00s | Wide Corridor Impact View (Light Explosion VFX)
		-- Hard cut. Wide view looking down the corridor at the explosion.
		-- FOV pop on impact + camera shake.
		-- =====================================================================
		local SHOT4_DUR = 1.20
		local impactPos = rootPart.Position + lookVec * 32.0

		-- Fire impact VFX callback at t = 2.80s
		if onImpact then
			pcall(onImpact)
		end

		local shoulderStart = rootPart.Position - lookVec * 11.5 + rightVec * 5.0 + Vector3.new(0, 6.0, 0)
		local shoulderEnd = rootPart.Position - lookVec * 9.5 + rightVec * 4.0 + Vector3.new(0, 5.0, 0)

		local explosionFocus = impactPos + Vector3.new(0, 1.8, 0)

		-- Hard cut
		camera.CFrame = CFrame.lookAt(shoulderStart, explosionFocus)
		camera.FieldOfView = 85

		local fovTween = TweenService:Create(
			camera,
			TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ FieldOfView = 72 }
		)
		fovTween:Play()

		-- Strong impact shake
		triggerShake(1.3, 0.4)

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
