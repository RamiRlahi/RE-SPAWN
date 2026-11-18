--!strict
--[[
	DashController.luau
	The dash: the "Dash" keybind (right click by default; SkillController
	hears it). A quick burst along the way you're moving (or toward the cursor
	standing still) that dodges whatever was about to land: the server gives a
	moment of i-frames (Dash.luau). MAX_CHARGES dashes held, each coming back
	COOLDOWN seconds after the one before it refilled; not while
	riding, sat down, held still (a tome choice, a tutorial popup) or in an
	ultimate.

	The move is ours (our character's physics): a LinearVelocity flat along
	the floor, only as far as the way ahead is clear (a spherecast first, then
	a look ahead every frame), with a capped force: shoved into a wall, mob or
	prop at full force the body was flung into the air. Never leaves you
	rising either. Afterimages trail it (budgeted: FxBudget).

	A dash cancels whatever skill or attack is playing (not an ultimate): the
	pose lets go, whatever holds the body still lets go, and you're free to act.
	Hits the move already started on the server still land.

	  DashController.Init(getAim)   getAim(root) → the flat aim direction
	  DashController.Dash()         try to dash now
	  DashController.Ready() → 0..1 how far the next charge has come back (1: one's ready)
	  DashController.Charges() → (stock, max)  stock 0..max, fractional while one refills
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))

local DashController = {}

local COOLDOWN = 1.1 -- seconds for one charge to come back (Dash.COOLDOWN on the server)
local MAX_CHARGES = 3 -- (Dash.CHARGES on the server)
local GAP = 0.22      -- at least this long between two dashes (no double-tap blur)
local DASH_TIME = 0.16
local SPEED = 100 -- studs a second: ~16 studs a dash
local RADIUS = 1.4 -- (the body's width, for the look ahead)
local STOP_SHORT = 1.5 -- studs short of whatever's in the way
local FORCE = 6000 -- (per unit of the body's mass: enough for SPEED in a frame, not to fling)
local GHOSTS = 3
local GHOST_COLOR = Color3.fromRGB(190, 225, 255)

local player = Players.LocalPlayer
local lastDash = -math.huge
local stock, stockAt = MAX_CHARGES, os.clock()
local function refill(now: number)
	stock = math.min(MAX_CHARGES, stock + (now - stockAt) / COOLDOWN)
	stockAt = now
end
local getAim: ((BasePart) -> Vector3)? = nil
local cancelHooks: { (Model) -> () } = {}

local function fxFolder(): Instance
	local f = Workspace:FindFirstChild("DashTrails")
	if f then return f end
	local nf = Instance.new("Folder")
	nf.Name = "DashTrails"
	nf.Parent = Workspace
	return nf
end

-- A see-through copy of the body where it is now, fading out.
local function ghost(char: Model)
	if not FxBudget.Allow("dashGhost", 12) then return end
	local folder = fxFolder()
	for _, d in ipairs(char:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
			local g = Instance.new("Part")
			g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = true, false, false, false, false
			g.Size, g.CFrame = d.Size, d.CFrame
			g.Material = Enum.Material.Neon
			g.Color = GHOST_COLOR
			g.Transparency = 0.55
			g.Parent = folder
			TweenService:Create(g, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1 }):Play()
			Debris:AddItem(g, 0.3)
		end
	end
end

local function canDash(char: Model, hum: Humanoid, root: BasePart): boolean
	if player:GetAttribute("InLobby") ~= false or player:GetAttribute("SettingsOpen") == true then return false end
	if hum.Health <= 0 or hum.Sit or root.Anchored then return false end
	if RunScope.Mine("TomesPaused") == true then return false end
	if char:GetAttribute("IsUltActive") == true or char:GetAttribute("Riding") ~= nil then return false end
	return true
end

-- What a skill holds the body with (on the root): let go so the dash can move it.
local HOLDS = { AlignPosition = true, AlignOrientation = true, LinearVelocity = true, BodyVelocity = true,
	BodyPosition = true, BodyGyro = true, VectorForce = true }

-- Out of whatever skill or attack is playing: the pose, the held body, the
-- cast flags, any action animation on the Animator.
local function cancelMove(char: Model, hum: Humanoid, root: BasePart)
	CastPoses.stop(char)
	for _, d in ipairs(root:GetChildren()) do
		if HOLDS[d.ClassName] then d:Destroy() end
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if animator then
		for _, tr in ipairs(animator:GetPlayingAnimationTracks()) do
			if tr.Priority.Value >= Enum.AnimationPriority.Action.Value then tr:Stop(0.08) end
		end
	end
	if hum.PlatformStand then hum.PlatformStand = false end
	hum.AutoRotate = true
	char:SetAttribute("IsSkillCasting", false)
	char:SetAttribute("AllowSkillMovement", false)
	for _, fn in ipairs(cancelHooks) do task.spawn(fn, char) end
end

function DashController.Dash()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not hum or not root then return end
	local now = os.clock()
	refill(now)
	if stock < 1 or now - lastDash < GAP or not canDash(char, hum, root) then return end
	-- which way: where you're walking, else toward the cursor
	local dir = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
	if dir.Magnitude < 0.1 and getAim then dir = (getAim :: (BasePart) -> Vector3)(root) end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then dir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) end
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit
	lastDash = now
	stock -= 1
	cancelMove(char, hum, root)
	Network.GetRemoteEvent(Network.Remotes.Dash):FireServer()

	-- how far the way is clear (walls, props, mobs: not ourselves, not effects)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char, fxFolder() }
	params.RespectCanCollide = true
	local function clearAhead(from: Vector3, dist: number): number
		local hit = Workspace:Spherecast(from, RADIUS, dir * dist, params)
		return if hit then math.max(0, hit.Distance - STOP_SHORT) else dist
	end
	local free = clearAhead(root.Position, SPEED * DASH_TIME + STOP_SHORT)
	local dashTime = math.min(DASH_TIME, free / SPEED)

	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Plane
	lv.PrimaryTangentAxis = Vector3.xAxis
	lv.SecondaryTangentAxis = Vector3.zAxis
	lv.PlaneVelocity = Vector2.new(dir.X, dir.Z) * SPEED
	lv.MaxForce = FORCE * root.AssemblyMass
	lv.Parent = root
	-- (facing the way it goes)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	ClassFX.Sound("whoosh", root, 0.7, 1.25)
	task.spawn(function()
		for i = 1, GHOSTS do
			if not char.Parent then break end
			ghost(char)
			task.wait(DASH_TIME / GHOSTS)
		end
	end)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dashTime and root.Parent and lv.Parent do
			-- (something stepped in the way: stop here)
			if clearAhead(root.Position, 3) < 1 then break end
			RunService.Heartbeat:Wait()
		end
		lv:Destroy()
		att:Destroy()
		-- (out of it at walking pace, not sliding on, and never thrown upward)
		if root.Parent then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X * 0.25, math.min(v.Y, 0), v.Z * 0.25)
			root.AssemblyAngularVelocity = Vector3.zero
		end
	end)
end

function DashController.Ready(): number
	refill(os.clock())
	return if stock >= 1 then 1 else stock
end

-- `fn(char)` runs when a dash cuts a move short (a class controller drops
-- what it was holding: its busy timer, its body mover).
function DashController.OnCancel(fn: (Model) -> ())
	table.insert(cancelHooks, fn)
end

function DashController.Charges(): (number, number)
	refill(os.clock())
	return stock, MAX_CHARGES
end

function DashController.Init(aim: (BasePart) -> Vector3)
	getAim = aim
	-- (a fresh body starts with every charge)
	player.CharacterAdded:Connect(function()
		stock, stockAt = MAX_CHARGES, os.clock()
	end)
end

return DashController
