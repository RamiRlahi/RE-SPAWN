local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local LobbyCamera = {}

local player = Players.LocalPlayer

local cameraConnection: RBXScriptConnection? = nil
local inTitleMode = false
local inClassSelectMode = false
local angle = 0

-- Class-select orbit: the camera swings around the character (drag to orbit).
-- It's anchored to the character's facing captured when the view opens, so
-- the character itself never turns to follow the camera.
local orbitYaw = 0
local orbitVelocity = 0

function LobbyCamera.AddOrbit(deltaYaw: number)
	orbitYaw += deltaYaw
	orbitVelocity = deltaYaw * 60
end

function LobbyCamera.ReleaseOrbit()
	-- Keep the current velocity so the camera glides to a stop.
end

function LobbyCamera.HoldOrbit()
	orbitVelocity = 0
end

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

-- Menus use the normal mouse cursor: hide the gameplay aim reticle.
local function menuCursor()
	UserInputService.MouseIconEnabled = true
	local pg = player:FindFirstChildOfClass("PlayerGui")
	local reticle = pg and pg:FindFirstChild("AimReticleGui")
	if reticle and reticle:IsA("ScreenGui") then reticle.Enabled = false end
end

-- The sky-kingdom backdrop owns the title shot (MenuBackdrop.Vista).
local MenuBackdrop: any = nil
pcall(function()
	MenuBackdrop = require(script.Parent:WaitForChild("MenuBackdrop"))
end)

-- Title and campfire: fixed cinematic shots from the backdrop that barely
-- breathe (a slow drift and sway) so the scene reads as alive. Switching
-- shots blends from wherever the camera is. Falls back to a slow orbit only
-- if the backdrop isn't built yet.
local vistaMode: string? = nil
local function startVista(mode: string, getView: () -> CFrame?)
	if inTitleMode and vistaMode == mode then return end
	inClassSelectMode = false
	inTitleMode = true
	vistaMode = mode

	if cameraConnection then
		cameraConnection:Disconnect()
		cameraConnection = nil
	end

	local camera = getCamera()
	camera.CameraType = Enum.CameraType.Scriptable
	menuCursor()

	local radius = 18
	local height = 6
	local t = 0
	local from = camera.CFrame
	local blend = 0

	cameraConnection = RunService.RenderStepped:Connect(function(dt)
		if not inTitleMode then return end
		t += dt
		-- Hold the shot even if the camera is replaced or reset (respawns,
		-- the default camera scripts): always drive the current one.
		local current = Workspace.CurrentCamera
		if not current then return end
		if current ~= camera then
			camera = current
			from = camera.CFrame
			blend = 1
		end
		if camera.CameraType ~= Enum.CameraType.Scriptable then
			camera.CameraType = Enum.CameraType.Scriptable
		end
		local view = getView()
		if view then
			camera.FieldOfView = 50 -- tight on the brazier; the far castles read huge
			local drift = CFrame.new(math.sin(t * 0.13) * 1.6, math.sin(t * 0.21) * 0.7, math.sin(t * 0.09) * 1.2)
			local sway = CFrame.Angles(math.sin(t * 0.17) * 0.012, math.sin(t * 0.11) * 0.02, math.sin(t * 0.07) * 0.006)
			local target = view * drift * sway
			blend = math.min(1, blend + dt / 1.1)
			local e = -(math.cos(math.pi * blend) - 1) / 2
			camera.CFrame = if blend < 1 then from:Lerp(target, e) else target
			return
		end
		angle += dt * 0.12
		local focus = getFocusPoint()
		local camPos = focus + Vector3.new(math.cos(angle) * radius, height + math.sin(angle * 0.5) * 1.5, math.sin(angle) * radius)
		camera.CFrame = CFrame.new(camPos, focus)
	end)
end

-- 1. Title screen: out over the sky kingdom (castle right, menu left).
function LobbyCamera.StartTitleMode()
	startVista("title", function()
		return if MenuBackdrop and MenuBackdrop.Vista then MenuBackdrop.Vista() else nil
	end)
end

-- 1a. Class select: a front view of the hero standing in the scene (one
-- gentle move from the title shot; no orbiting).
function LobbyCamera.StartHeroMode()
	startVista("hero", function()
		return if MenuBackdrop and MenuBackdrop.HeroView then MenuBackdrop.HeroView() else nil
	end)
end

-- 1b. The campfire: closer and lower, looking down at the circle.
function LobbyCamera.StartCampfireMode()
	startVista("campfire", function()
		return if MenuBackdrop and MenuBackdrop.CampfireView then MenuBackdrop.CampfireView() else nil
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
	menuCursor()
	camera.FieldOfView = 70 -- the title shot uses a narrower lens

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

	-- Subtle cinematic breathing bobbing while in class selection, orbiting by
	-- orbitYaw around a base angle fixed now (not the character's live facing).
	local bobTime = 0
	local baseRotation = root.CFrame.Rotation
	local startTime = os.clock()
	cameraConnection = RunService.RenderStepped:Connect(function(dt)
		if not inClassSelectMode then return end
		bobTime += dt
		if math.abs(orbitVelocity) > 0.01 then
			orbitYaw += orbitVelocity * dt
			orbitVelocity *= math.exp(-5 * dt)
		end

		-- Let the opening tween finish before taking over the camera.
		if os.clock() - startTime < 0.8 then return end
		if root and root.Parent then
			local orbitCF = CFrame.new(root.Position) * baseRotation * CFrame.Angles(0, orbitYaw, 0)
			local currentEye = (orbitCF * CFrame.new(math.sin(bobTime * 0.5) * 0.15, 0.4 + math.sin(bobTime * 0.8) * 0.08, -7.2)).Position
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
