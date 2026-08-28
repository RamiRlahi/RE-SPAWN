local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local LobbyCamera = {}

local player = Players.LocalPlayer

local cameraConnection: RBXScriptConnection? = nil
local inLobbyMode = false
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

function LobbyCamera.Start()
	if inLobbyMode then return end
	inLobbyMode = true

	local camera = getCamera()
	camera.CameraType = Enum.CameraType.Scriptable

	local radius = 18
	local height = 6

	cameraConnection = RunService.RenderStepped:Connect(function(dt)
		if not inLobbyMode then return end
		angle += dt * 0.12

		local focus = getFocusPoint()
		local camPos = focus + Vector3.new(math.cos(angle) * radius, height + math.sin(angle * 0.5) * 1.5, math.sin(angle) * radius)
		camera.CFrame = CFrame.new(camPos, focus)
	end)
end

function LobbyCamera.Stop(onRestored: (() -> ())?)
	if not inLobbyMode then return end
	inLobbyMode = false

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
