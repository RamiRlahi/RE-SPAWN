local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LobbyCamera = {}

local player = Players.LocalPlayer

local cameraConnection: RBXScriptConnection? = nil
local inTitleMode = false
local inClassSelectMode = false
local angle = 0

local function getCamera(): Camera
	local cam = Workspace.CurrentCamera
	while not cam do
		task.wait()
		cam = Workspace.CurrentCamera
	end
	return cam
end

local function getFocusPoint(): Vector3
	local churchSpawn = Workspace:FindFirstChild("ChurchSpawn", true)
	if churchSpawn and churchSpawn:IsA("BasePart") then
		return churchSpawn.Position + Vector3.new(0, 4, 0)
	end

	local char = player.Character
	if char then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			return root.Position + Vector3.new(0, 3, 0)
		end
	end

	return Vector3.new(0, 6, 0)
end

-- 1. Orbiting Camera for Title Screen
function LobbyCamera.StartTitleMode()
	if inTitleMode then return end
	inClassSelectMode = false
	inTitleMode = true

	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end

	local camera = getCamera()
	camera.CameraType = Enum.CameraType.Scriptable

	local radius = 18
	local height = 6

	cameraConnection = RunService.RenderStepped:Connect(function(dt)
		if not inTitleMode then return end
		angle += dt * 0.12

		local focus = getFocusPoint()
		local camPos = focus + Vector3.new(math.cos(angle) * radius, height + math.sin(angle * 0.5) * 1.5, math.sin(angle) * radius)
		camera.CFrame = CFrame.new(camPos, focus)
	end)
end

-- Backwards-compatible alias
function LobbyCamera.Start()
	LobbyCamera.StartTitleMode()
end

-- 2. Front-Facing Character View for Class Selection Carousel
function LobbyCamera.SetClassSelectView()
	inTitleMode = false
	inClassSelectMode = true

	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end

	local camera = getCamera()
	camera.CameraType = Enum.CameraType.Scriptable

	local character = player.Character or player.CharacterAdded:Wait()
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	if not root then return end

	-- Position camera in front of the character (facing character's chest/head)
	-- In Roblox CFrame, -Z is forward, so CFrame.new(0, 0.3, -7.5) is right in front of the character
	local targetEyePos = (root.CFrame * CFrame.new(0, 0.4, -7.2)).Position
	local lookAtPos = root.Position + Vector3.new(0, 0.4, 0)
	local targetCFrame = CFrame.new(targetEyePos, lookAtPos)

	local tween = TweenService:Create(
		camera,
		TweenInfo.new(0.8, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
		{ CFrame = targetCFrame }
	)
	tween:Play()

	-- Subtle cinematic breathing bobbing while in class selection
	local bobTime = 0
	cameraConnection = RunService.RenderStepped:Connect(function(dt)
		if not inClassSelectMode then return end
		bobTime += dt

		if root and root.Parent then
			local currentEye = (root.CFrame * CFrame.new(math.sin(bobTime * 0.5) * 0.15, 0.4 + math.sin(bobTime * 0.8) * 0.08, -7.2)).Position
			local currentLook = root.Position + Vector3.new(0, 0.4, 0)
			camera.CFrame = CFrame.new(currentEye, currentLook)
		end
	end)
end

function LobbyCamera.StopImmediate()
	inTitleMode = false
	inClassSelectMode = false

	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end
end

-- 3. Transition to standard Gameplay Camera
function LobbyCamera.Stop(onRestored: (() -> ())?)
	inTitleMode = false
	inClassSelectMode = false

	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end

	local camera = getCamera()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:WaitForChild("Humanoid", 5) :: Humanoid?
	local root = character:WaitForChild("HumanoidRootPart", 5) :: BasePart?

	if root and humanoid then
		local targetCF = root.CFrame * CFrame.new(0, 2.5, 8)
		local tween = TweenService:Create(
			camera,
			TweenInfo.new(1.0, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
			{ CFrame = targetCF }
		)
		tween.Completed:Once(function()
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
			if onRestored then
				onRestored()
			end
		end)
		tween:Play()
	else
		camera.CameraType = Enum.CameraType.Custom
		if humanoid then
			camera.CameraSubject = humanoid
		end
		if onRestored then
			onRestored()
		end
	end
end

return LobbyCamera
