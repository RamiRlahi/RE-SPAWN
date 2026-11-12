--!strict
--[[
	AimInput.luau
	Where the player is aiming, as a point on the screen: the mouse on a
	keyboard, and on a controller the right stick's aim (else the way you're
	walking, else the way you face), drawn to the enemy nearest that line if
	one is close (a soft lock), set out ahead of the character and seen from
	the camera. Every aim in the game reads the mouse's screen point; reading
	this instead, it works the same on either.

	  AimInput.ScreenPoint() → Vector2   (the mouse, or the controller's aim, in viewport pixels)
	  AimInput.UsingGamepad() → boolean  (the last input was a controller's)
	  AimInput.Ahead(origin, point) → Vector3  (a cursor point never behind you on the classic camera)
	  AimInput.PointerPoint() → Vector2  (the mouse or controller aim itself, ignoring a hard lock: for the cursor)

	A hard lock (LockOn: the middle mouse button, or the right stick click)
	overrides all of it: while one is on, ScreenPoint is the locked mob, as
	seen from the camera, so every class's aim goes to it.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LockOn = require(script.Parent:WaitForChild("LockOn"))

local AimInput = {}

local player = Players.LocalPlayer
local DEADZONE = 0.3      -- the right stick's (and the left's, for "the way you walk")
local REACH = 26          -- studs ahead the aim point sits with nothing to lock to
local LOCK_RANGE = 55     -- studs: the farthest an enemy is drawn in
local LOCK_CONE = math.cos(math.rad(32)) -- (how far off the aim line it may be)
local LOCK_EVERY = 0.12   -- seconds between looks for one

local gamepad = false
local function isPad(t: Enum.UserInputType): boolean
	return t.Name:sub(1, 7) == "Gamepad"
end
UserInputService.LastInputTypeChanged:Connect(function(t)
	if isPad(t) then
		gamepad = true
	elseif t == Enum.UserInputType.MouseMovement or t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Keyboard
		or t == Enum.UserInputType.MouseButton2 or t == Enum.UserInputType.Touch then
		gamepad = false
	end
end)
gamepad = isPad(UserInputService:GetLastInputType())

function AimInput.UsingGamepad(): boolean
	return gamepad
end

-- The right stick's latest position (set as it moves).
local stick = Vector2.zero
UserInputService.InputChanged:Connect(function(input)
	if input.KeyCode == Enum.KeyCode.Thumbstick2 then stick = Vector2.new(input.Position.X, input.Position.Y) end
end)

local aimDir = Vector3.new(0, 0, -1)
local lockTarget: BasePart? = nil
local lockAt = 0
local point = Vector2.zero
local lockedPoint: Vector2? = nil -- (the hard lock's mob on the screen, this frame)

-- a controller's right stick click: a hard lock from where it aims
UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.KeyCode == Enum.KeyCode.ButtonR3 and not gameProcessed then LockOn.Toggle(point) end
end)

-- The enemy nearest the aim line, within reach (Workspace.Mobs, never the
-- whole Workspace).
local function findLock(origin: Vector3, dir: Vector3): BasePart?
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return nil end
	local best, bestScore = nil, -math.huge
	for _, m in ipairs(mobs:GetChildren()) do
		local root = m:FindFirstChild("HumanoidRootPart")
		local hum = m:FindFirstChildOfClass("Humanoid")
		if not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then continue end
		local off = Vector3.new(root.Position.X - origin.X, 0, root.Position.Z - origin.Z)
		local d = off.Magnitude
		if d < 1 or d > LOCK_RANGE then continue end
		local along = off.Unit:Dot(dir)
		if along < LOCK_CONE then continue end
		local score = along * 2 - d / LOCK_RANGE
		if score > bestScore then best, bestScore = root, score end
	end
	return best
end

RunService:BindToRenderStep("AimInput", Enum.RenderPriority.Input.Value + 1, function()
	-- (a hard lock: where its mob is on the screen)
	local lp = LockOn.Point()
	local cam0 = Workspace.CurrentCamera
	if lp and cam0 then
		local v = cam0:WorldToViewportPoint(lp)
		lockedPoint = if v.Z > 0 then Vector2.new(v.X, v.Y) else nil
	else
		lockedPoint = nil
	end
	if not gamepad then
		point = UserInputService:GetMouseLocation()
		return
	end
	local cam = Workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not cam or not root then return end
	-- the stick, turned from the screen into the world (the camera's ground axes)
	local fwd = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	local right = Vector3.new(cam.CFrame.RightVector.X, 0, cam.CFrame.RightVector.Z)
	if fwd.Magnitude > 0.01 and right.Magnitude > 0.01 then
		fwd, right = fwd.Unit, right.Unit
		if stick.Magnitude > DEADZONE then
			aimDir = (right * stick.X + fwd * stick.Y).Unit
		else
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local move = if hum then Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z) else Vector3.zero
			if move.Magnitude > DEADZONE then aimDir = move.Unit end
		end
	end
	-- (the soft lock, looked for now and then)
	local now = os.clock()
	if now - lockAt > LOCK_EVERY then
		lockAt = now
		lockTarget = findLock(root.Position, aimDir)
	end
	local target = root.Position + aimDir * REACH - Vector3.new(0, 2.5, 0)
	local lock = lockTarget
	if lock and lock.Parent then target = lock.Position end
	local v = cam:WorldToViewportPoint(target)
	point = Vector2.new(v.X, v.Y)
end)

function AimInput.PointerPoint(): Vector2
	if not gamepad then return UserInputService:GetMouseLocation() end
	return point
end

function AimInput.ScreenPoint(): Vector2
	if lockedPoint and LockOn.Point() then return lockedPoint end
	return AimInput.PointerPoint()
end

-- The hard-locked mob's position, or nil (aim straight at it, past any wall
-- the screen point's ray would meet first).
function AimInput.LockPoint(): Vector3?
	return LockOn.Point()
end

-- On the classic camera (Settings > Gameplay) you aim where the camera looks,
-- the crosshair in the middle of the screen. Read off the crosshair's ray, the
-- point is wrong two ways: looking up, Roblox swings the camera down behind
-- you, so the ray climbs past you from below and crosses your height (or
-- meets a low ceiling) BEHIND you, and an aim read off it fires backwards;
-- and the camera sits out over your shoulder, so a point on the floor just
-- ahead lies well off to the side (aimed at, the body swings round 50°+). So
-- here the aim always runs the way the camera faces, as far out as the ray's
-- point was ahead of you (at least 4 studs; 40 if it was behind you), at its
-- height. On the top-down camera every point on the floor is a real aim:
-- untouched.
function AimInput.Ahead(origin: Vector3, at: Vector3): Vector3
	if LockOn.Point() then return at end -- (a hard lock aims at its mob on any camera)
	if player:GetAttribute("Setting_classicCamera") ~= true then return at end
	local cam = Workspace.CurrentCamera
	if not cam then return at end
	local look = cam.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.05 then return at end
	flat = flat.Unit
	local along = Vector3.new(at.X - origin.X, 0, at.Z - origin.Z):Dot(flat)
	local reach = if along > 0.5 then math.max(along, 4) else 40
	return Vector3.new(origin.X, at.Y, origin.Z) + flat * reach
end

return AimInput
