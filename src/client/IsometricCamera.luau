--[[
	IsometricCamera (Client-Side)
	
	Features:
	  1. Authentic Hades-style 3/4 isometric ARPG camera view.
	  2. Smooth cinematic transition from lobby camera into isometric gameplay view.
	  3. Full obstacle & ceiling penetration:
	     - Camera ignores all collision (never forces zoom-in).
	     - Dynamic Occlusion Solver: Automatically fades any ceilings, roofs, or walls
	       between the camera and the player to transparent.
--]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local IsometricCamera = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Isometric Camera Settings (Hades Style)
-- ─────────────────────────────────────────────────────────────────────────────
local CAMERA_OFFSET = Vector3.new(-26, 36, 26) -- Hades 3/4 top-down angle
local CAMERA_FOV    = 45                        -- Flat, authentic isometric feel
local SMOOTHNESS    = 14                        -- Lerp speed for butter-smooth tracking
local TARGET_HEIGHT = 2.5                       -- Focus height relative to root part

-- Transparency for obstructing ceilings / walls
local OBSTACLE_TRANSPARENCY = 0.85
local OCCLUSION_RADIUS      = 4.0 -- Sweeping radius to fade nearby obstacles

-- ─────────────────────────────────────────────────────────────────────────────

local isActive = false
local renderConnection: RBXScriptConnection? = nil
local currentFocusPos: Vector3? = nil

-- Occlusion tracking
local transparentParts: { [BasePart]: number } = {} -- [part] = original LocalTransparencyModifier
local raycastParams = RaycastParams.new()
raycastParams.FilterType = Enum.RaycastFilterType.Exclude
raycastParams.IgnoreWater = true

local function getCamera(): Camera
	local cam = Workspace.CurrentCamera
	while not cam do
		task.wait()
		cam = Workspace.CurrentCamera
	end
	return cam
end

local function getCharacterRoot(): (BasePart?, Humanoid?)
	local char = player.Character
	if not char then return nil, nil end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	return root, humanoid
end

-- ── Occlusion Solver (Fades Ceilings & Walls) ──────────────────────────────────

local function updateOcclusion(camPos: Vector3, targetPos: Vector3, character: Model)
	raycastParams.FilterDescendantsInstances = { character }

	local currentlyHit: { [BasePart]: boolean } = {}
	local origin = camPos
	local direction = (targetPos - origin)
	local distance = direction.Magnitude

	-- Sweep a sphere from camera to player to catch nearby obstructing walls/ceilings
	local currentOrigin = origin
	local rayResult = Workspace:Spherecast(currentOrigin, OCCLUSION_RADIUS, direction.Unit * distance, raycastParams)
	local iterations = 0

	-- Cast through multiple layers (e.g. roof + ceiling + wall)
	while rayResult and rayResult.Instance and iterations < 10 do
		iterations += 1
		local hitPart = rayResult.Instance
		
		if hitPart:IsA("BasePart") and hitPart.Transparency < 1 then
			-- Avoid fading the floor / ground (anything below the player's knees/feet)
			local isGround = rayResult.Position.Y < targetPos.Y - 5
			if not isGround then
				currentlyHit[hitPart] = true

				-- Save original modifier if newly obstructing
				if transparentParts[hitPart] == nil then
					transparentParts[hitPart] = hitPart.LocalTransparencyModifier
				end

				-- Fade to transparent
				hitPart.LocalTransparencyModifier = OBSTACLE_TRANSPARENCY
			end
		end

		-- Advance currentOrigin past the hit point along the sweep path
		local advanceDist = rayResult.Distance + 0.2
		currentOrigin = currentOrigin + direction.Unit * advanceDist

		local remainingDist = (targetPos - currentOrigin).Magnitude
		if remainingDist <= 0.5 then break end

		rayResult = Workspace:Spherecast(currentOrigin, OCCLUSION_RADIUS, direction.Unit * remainingDist, raycastParams)
	end

	-- Restore parts that are no longer obstructing
	for part, origVal in pairs(transparentParts) do
		if not currentlyHit[part] then
			if part and part.Parent then
				part.LocalTransparencyModifier = origVal
			end
			transparentParts[part] = nil
		end
	end
end

-- Restore all transparent parts when camera stops
local function clearAllOcclusions()
	for part, origVal in pairs(transparentParts) do
		if part and part.Parent then
			part.LocalTransparencyModifier = origVal
		end
	end
	transparentParts = {}
end

-- ── Public API ────────────────────────────────────────────────────────────────

function IsometricCamera.Start(transitionDuration: number?)
	if isActive then return end
	isActive = true

	local cam = getCamera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = CAMERA_FOV

	local root, humanoid = getCharacterRoot()
	if not root then return end

	local targetPos = root.Position + Vector3.new(0, TARGET_HEIGHT, 0)
	currentFocusPos = targetPos
	local finalCFrame = CFrame.lookAt(targetPos + CAMERA_OFFSET, targetPos)

	local duration = transitionDuration or 1.2

	-- Smooth cinematic transition to Hades Isometric angle
	local tween = TweenService:Create(
		cam,
		TweenInfo.new(duration, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
		{ CFrame = finalCFrame, FieldOfView = CAMERA_FOV }
	)
	tween:Play()

	-- Start live RenderStepped tracking loop
	if renderConnection then renderConnection:Disconnect() end

	renderConnection = RunService.RenderStepped:Connect(function(dt)
		if not isActive then return end

		local currentRoot, _ = getCharacterRoot()
		if not currentRoot then return end

		local rawTargetPos = currentRoot.Position + Vector3.new(0, TARGET_HEIGHT, 0)

		-- Smooth focus interpolation
		if not currentFocusPos then
			currentFocusPos = rawTargetPos
		else
			currentFocusPos = currentFocusPos:Lerp(rawTargetPos, math.clamp(dt * SMOOTHNESS, 0, 1))
		end

		local camPos = currentFocusPos + CAMERA_OFFSET
		cam.CFrame = CFrame.lookAt(camPos, currentFocusPos)

		-- Update ceiling/obstacle transparency solver
		if player.Character then
			updateOcclusion(camPos, currentFocusPos, player.Character)
		end
	end)

	print("[IsometricCamera] Hades-style camera active.")
end

-- Re-hook on respawn if active
player.CharacterAdded:Connect(function()
	if isActive then
		currentFocusPos = nil
		clearAllOcclusions()
	end
end)

function IsometricCamera.Stop()
	if not isActive then return end
	isActive = false

	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end

	clearAllOcclusions()
	currentFocusPos = nil

	local cam = getCamera()
	cam.CameraType = Enum.CameraType.Custom
	cam.FieldOfView = 70

	local _, humanoid = getCharacterRoot()
	if humanoid then
		cam.CameraSubject = humanoid
	end

	print("[IsometricCamera] Stopped.")
end

return IsometricCamera
