--[[
	IsometricCamera (Client-Side)
	
	Features:
	  1. Authentic Hades-style 3/4 isometric ARPG camera view.
	  2. Smooth cinematic transition from lobby camera into isometric gameplay view.
	  3. Dynamic Mouse Lead & Drag:
	     - Camera subtly leads in the direction the player is aiming with the mouse.
	  4. Natural Head Aiming (Clamped to ±90° maximum):
	     - Character's head smoothly turns towards the mouse cursor up to ±90° left/right.
	     - Lower body and legs walk freely in the movement direction without restriction.
	  5. Custom Medieval Reticle Cursor:
	     - Replaces default OS cursor with a crisp, stylish ARPG crosshair reticle.
	  6. Dynamic Occlusion Solver:
	     - Automatically fades any walls or obstructions between camera & player.
--]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local IsometricCamera = {}

-- ─────────────────────────────────────────────────────────────────────────────
-- Isometric Camera Settings (Hades Style)
-- ─────────────────────────────────────────────────────────────────────────────
local CAMERA_OFFSET     = Vector3.new(-26, 36, 26) -- Hades 3/4 top-down angle
local CAMERA_FOV        = 45                        -- Flat, authentic isometric feel
local SMOOTHNESS        = 14                        -- Lerp speed for butter-smooth tracking
local TARGET_HEIGHT     = 2.5                       -- Focus height relative to root part
local MOUSE_LEAD_FACTOR = 0.20                      -- Strength of mouse drag on camera (20%)
local MAX_MOUSE_LEAD    = 8.0                       -- Max camera drag distance in studs
local AIM_SMOOTHNESS    = 20                        -- Head rotation smoothness
local MAX_HEAD_YAW      = math.rad(90)              -- Maximum 90° turn left and right

-- Transparency for obstructing ceilings / walls
local OBSTACLE_TRANSPARENCY = 1.0
local OCCLUSION_RADIUS      = 3.0 -- Tight character-sized radius along camera sightlines

-- ─────────────────────────────────────────────────────────────────────────────

local isActive = false
local renderConnection: RBXScriptConnection? = nil
local currentFocusPos: Vector3? = nil

-- Head aiming state
local origNeckC0: CFrame? = nil
local currentAimYaw = 0
local currentAimPitch = 0

-- Custom Cursor UI
local cursorGui: ScreenGui? = nil
local cursorFrame: Frame? = nil
local inputBeganConn: RBXScriptConnection? = nil

-- Occlusion tracking with cooldown to prevent flickering
type OccludedPartInfo = {
	originalTransparency: number,
	lastHitTime: number,          -- os.clock() of last detection
	currentTransparency: number,  -- smoothly interpolated value
}
local occludedParts: { [BasePart]: OccludedPartInfo } = {}

local OCCLUSION_HOLD_TIME  = 0.5  -- Keep parts faded for 0.5s after last detection
local FADE_OUT_SPEED       = 12   -- How fast parts fade to transparent (per second)
local FADE_IN_SPEED        = 4    -- How fast parts restore (slower = smoother reappearance)

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

-- ── 1. Custom Aiming Reticle Cursor GUI ────────────────────────────────────────

local function createAimCursor(): (ScreenGui, Frame)
	local pGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local existing = pGui:FindFirstChild("AimReticleGui")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "AimReticleGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = pGui

	local container = Instance.new("Frame")
	container.Name = "ReticleContainer"
	container.Size = UDim2.fromOffset(36, 36)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.Position = UDim2.fromOffset(-100, -100)
	container.Parent = gui

	-- Outer Ring
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromOffset(22, 22)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundTransparency = 1
	ring.Parent = container

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(255, 235, 190)
	ringStroke.Thickness = 2.2
	ringStroke.Transparency = 0.05
	ringStroke.Parent = ring

	-- Center Dot
	local dot = Instance.new("Frame")
	dot.Name = "CenterDot"
	dot.Size = UDim2.fromOffset(5, 5)
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.BackgroundColor3 = Color3.fromRGB(255, 240, 200)
	dot.BorderSizePixel = 0
	dot.Parent = container

	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = dot

	local dotStroke = Instance.new("UIStroke")
	dotStroke.Color = Color3.fromRGB(20, 20, 25)
	dotStroke.Thickness = 1.2
	dotStroke.Parent = dot

	-- 4 Crosshair Tick Lines (Top, Bottom, Left, Right)
	local function createTick(size: UDim2, pos: UDim2, anchor: Vector2)
		local tick = Instance.new("Frame")
		tick.Size = size
		tick.Position = pos
		tick.AnchorPoint = anchor
		tick.BackgroundColor3 = Color3.fromRGB(255, 235, 190)
		tick.BorderSizePixel = 0
		tick.Parent = container

		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(20, 20, 25)
		stroke.Thickness = 1
		stroke.Parent = tick
		return tick
	end

	-- Top Tick
	createTick(UDim2.fromOffset(2.5, 7), UDim2.new(0.5, 0, 0.5, -11), Vector2.new(0.5, 1))
	-- Bottom Tick
	createTick(UDim2.fromOffset(2.5, 7), UDim2.new(0.5, 0, 0.5, 11), Vector2.new(0.5, 0))
	-- Left Tick
	createTick(UDim2.fromOffset(7, 2.5), UDim2.new(0.5, -11, 0.5, 0), Vector2.new(1, 0.5))
	-- Right Tick
	createTick(UDim2.fromOffset(7, 2.5), UDim2.new(0.5, 11, 0.5, 0), Vector2.new(0, 0.5))

	return gui, container
end

local function getMouseWorldPosition(planeY: number): Vector3?
	local mousePos = UserInputService:GetMouseLocation()
	local cam = Workspace.CurrentCamera
	if not cam then return nil end

	local unitRay = cam:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rayOrigin = unitRay.Origin
	local rayDir = unitRay.Direction

	if math.abs(rayDir.Y) < 1e-4 then
		return rayOrigin + rayDir * 50
	end

	local t = (planeY - rayOrigin.Y) / rayDir.Y
	if t <= 0 then
		return rayOrigin + rayDir * 50
	end

	return rayOrigin + rayDir * t
end

-- ── 2. Natural Head Aiming Solver (Clamped to ±90° Maximum) ───────────────────

local function findNeckMotor(char: Model): Motor6D?
	local head = char:FindFirstChild("Head")
	if head then
		local neck = head:FindFirstChild("Neck")
		if neck and neck:IsA("Motor6D") then return neck end
	end
	local upperTorso = char:FindFirstChild("UpperTorso")
	if upperTorso then
		local neck = upperTorso:FindFirstChild("Neck")
		if neck and neck:IsA("Motor6D") then return neck end
	end
	local torso = char:FindFirstChild("Torso")
	if torso then
		local neck = torso:FindFirstChild("Neck")
		if neck and neck:IsA("Motor6D") then return neck end
	end
	local found = char:FindFirstChild("Neck", true)
	if found and found:IsA("Motor6D") then return found end
	return nil
end

local function updateHeadAim(char: Model, rootPart: BasePart, mouseWorldPos: Vector3, dt: number)
	local neck = findNeckMotor(char)
	if not neck then return end

	if not origNeckC0 then
		origNeckC0 = neck.C0
	end

	local toMouse = (mouseWorldPos - rootPart.Position)
	local toMouseXZ = Vector3.new(toMouse.X, 0, toMouse.Z)

	if toMouseXZ.Magnitude > 0.5 then
		local rootCFrame = rootPart.CFrame
		local localDir = rootCFrame:VectorToObjectSpace(toMouseXZ.Unit)

		-- Calculate horizontal turn angle relative to character facing direction
		local rawYaw = math.atan2(localDir.X, -localDir.Z)
		-- Clamp to maximum 90° left and 90° right so turning looks natural
		local targetYaw = math.clamp(rawYaw, -MAX_HEAD_YAW, MAX_HEAD_YAW)
		local targetPitch = math.clamp(math.atan2(toMouse.Y, toMouseXZ.Magnitude), -0.25, 0.25)

		currentAimYaw = currentAimYaw + (targetYaw - currentAimYaw) * math.clamp(dt * AIM_SMOOTHNESS, 0, 1)
		currentAimPitch = currentAimPitch + (targetPitch - currentAimPitch) * math.clamp(dt * AIM_SMOOTHNESS, 0, 1)

		local isR15 = char:FindFirstChild("UpperTorso") ~= nil
		if isR15 then
			neck.C0 = (origNeckC0 :: CFrame) * CFrame.Angles(currentAimPitch, currentAimYaw, 0)
		else
			neck.C0 = (origNeckC0 :: CFrame) * CFrame.Angles(0, 0, -currentAimYaw) * CFrame.Angles(currentAimPitch, 0, 0)
		end
	end
end

local function resetHeadAim()
	local char = player.Character
	if not char then return end

	local neck = findNeckMotor(char)
	if neck and origNeckC0 then
		neck.C0 = origNeckC0
	end

	origNeckC0 = nil
	currentAimYaw = 0
	currentAimPitch = 0
end

-- ── 3. Occlusion Solver (Fades Obstacles Strictly Between Camera & Player) ────

local function markHit(hitPart: BasePart, currentlyHit: { [BasePart]: boolean })
	currentlyHit[hitPart] = true
	local info = occludedParts[hitPart]
	if not info then
		occludedParts[hitPart] = {
			originalTransparency = hitPart.LocalTransparencyModifier,
			lastHitTime = os.clock(),
			currentTransparency = hitPart.LocalTransparencyModifier,
		}
	else
		info.lastHitTime = os.clock()
	end
end

local function updateOcclusion(camPos: Vector3, targetPos: Vector3, character: Model, dt: number?)
	local stepDt = dt or 0.01666
	raycastParams.FilterDescendantsInstances = { character }

	local currentlyHit: { [BasePart]: boolean } = {}

	local camDir = (targetPos - camPos).Unit
	local camRight = camDir:Cross(Vector3.new(0, 1, 0)).Unit

	-- Target sightline points on and immediately around the character
	local targetPoints = {
		targetPos,                                      -- Character center / torso
		targetPos + Vector3.new(0, 2.2, 0),             -- Head
		targetPos + Vector3.new(0, -1.0, 0),            -- Lower torso
		targetPos + camRight * 2.0,                     -- Right shoulder
		targetPos - camRight * 2.0,                     -- Left shoulder
		targetPos + Vector3.new(0, 3.5, 0),             -- Low ceiling overhead
	}

	for _, tPt in ipairs(targetPoints) do
		local origin = camPos
		local direction = (tPt - origin)
		local totalDistance = direction.Magnitude
		local currentOrigin = origin
		local dirUnit = direction.Unit

		local rayResult = Workspace:Spherecast(currentOrigin, OCCLUSION_RADIUS, dirUnit * totalDistance, raycastParams)
		local iterations = 0

		while rayResult and rayResult.Instance and iterations < 10 do
			iterations += 1
			local hitPart = rayResult.Instance
			if hitPart:IsA("BasePart") and hitPart.Transparency < 1 then
				-- Only fade objects above floor level (never fade the ground under the player)
				local isGround = rayResult.Position.Y < (targetPos.Y - 1.5)
				if not isGround then
					markHit(hitPart, currentlyHit)
				end
			end
			local advanceDist = rayResult.Distance + 0.3
			currentOrigin = currentOrigin + dirUnit * advanceDist
			local remainingDist = (tPt - currentOrigin).Magnitude
			if remainingDist <= 0.8 then break end
			rayResult = Workspace:Spherecast(currentOrigin, OCCLUSION_RADIUS, dirUnit * remainingDist, raycastParams)
		end
	end

	-- ── Smooth transparency updates with cooldown ──
	local now = os.clock()
	for part, info in pairs(occludedParts) do
		if not part or not part.Parent then
			occludedParts[part] = nil
			continue
		end

		local timeSinceHit = now - info.lastHitTime
		local isStillActive = currentlyHit[part] or (timeSinceHit < OCCLUSION_HOLD_TIME)

		if isStillActive then
			-- Smoothly fade TO transparent
			info.currentTransparency = math.min(
				info.currentTransparency + stepDt * FADE_OUT_SPEED,
				OBSTACLE_TRANSPARENCY
			)
		else
			-- Smoothly fade BACK to original
			info.currentTransparency = math.max(
				info.currentTransparency - stepDt * FADE_IN_SPEED,
				info.originalTransparency
			)
			-- Fully restored → remove from tracking
			if math.abs(info.currentTransparency - info.originalTransparency) < 0.01 then
				part.LocalTransparencyModifier = info.originalTransparency
				occludedParts[part] = nil
				continue
			end
		end

		part.LocalTransparencyModifier = info.currentTransparency
	end
end

-- Restore all transparent parts when camera stops
local function clearAllOcclusions()
	for part, info in pairs(occludedParts) do
		if part and part.Parent then
			part.LocalTransparencyModifier = info.originalTransparency
		end
	end
	occludedParts = {}
end

-- ── 4. Public API ─────────────────────────────────────────────────────────────

function IsometricCamera.Start(transitionDuration: number?)
	if isActive then return end
	isActive = true

	local cam = getCamera()
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = CAMERA_FOV

	local root, humanoid = getCharacterRoot()
	if not root then return end

	-- Initialize Custom Reticle Cursor
	if not cursorGui or not cursorFrame then
		cursorGui, cursorFrame = createAimCursor()
	end
	if cursorGui then cursorGui.Enabled = true end
	UserInputService.MouseIconEnabled = false

	-- Setup click pulse feedback
	if inputBeganConn then inputBeganConn:Disconnect() end
	inputBeganConn = UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 and cursorFrame then
			local pulseTween = TweenService:Create(
				cursorFrame,
				TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = UDim2.fromOffset(28, 28) }
			)
			pulseTween:Play()
			pulseTween.Completed:Connect(function()
				TweenService:Create(
					cursorFrame,
					TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
					{ Size = UDim2.fromOffset(36, 36) }
				):Play()
			end)
		end
	end)

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
		local mousePos = UserInputService:GetMouseLocation()

		-- Update Custom Cursor Screen Position
		if cursorFrame then
			cursorFrame.Position = UDim2.fromOffset(mousePos.X, mousePos.Y)
		end

		-- Calculate Mouse World Aim & Dynamic Look-Ahead Drag
		local mouseWorldPos = getMouseWorldPosition(rawTargetPos.Y)
		local leadOffset = Vector3.zero

		if mouseWorldPos then
			local aimDelta = mouseWorldPos - rawTargetPos
			local aimDist = aimDelta.Magnitude
			if aimDist > 0.5 then
				local leadDist = math.min(aimDist * MOUSE_LEAD_FACTOR, MAX_MOUSE_LEAD)
				leadOffset = aimDelta.Unit * leadDist
			end

			-- Update Head Aiming toward cursor (clamped to ±90° maximum)
			if player.Character then
				updateHeadAim(player.Character, currentRoot, mouseWorldPos, dt)
			end
		end

		local desiredFocusPos = rawTargetPos + leadOffset

		-- Smooth focus interpolation
		if not currentFocusPos then
			currentFocusPos = desiredFocusPos
		else
			currentFocusPos = currentFocusPos:Lerp(desiredFocusPos, math.clamp(dt * SMOOTHNESS, 0, 1))
		end

		local camPos = currentFocusPos + CAMERA_OFFSET
		cam.CFrame = CFrame.lookAt(camPos, currentFocusPos)

		-- Update ceiling/obstacle transparency solver
		if player.Character then
			updateOcclusion(camPos, currentFocusPos, player.Character, dt)
		end
	end)

	print("[IsometricCamera] Hades-style camera + Head Aiming active.")
end

-- Re-hook on respawn if active
player.CharacterAdded:Connect(function()
	if isActive then
		currentFocusPos = nil
		resetHeadAim()
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

	if inputBeganConn then
		inputBeganConn:Disconnect()
		inputBeganConn = nil
	end

	if cursorGui then
		cursorGui.Enabled = false
	end
	UserInputService.MouseIconEnabled = true

	resetHeadAim()
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
