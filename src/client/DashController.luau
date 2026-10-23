--!strict
--[[
	DashController.luau
	The dash: the "Dash" keybind (right click by default; SkillController
	hears it). A quick burst along the way you're moving (or toward the cursor
	standing still) that dodges whatever was about to land: the server gives a
	moment of i-frames (Dash.luau). Once every COOLDOWN seconds; not while
	riding, sat down, held still (a tome choice, a tutorial popup) or in an
	ultimate.

	The move is ours (our character's physics): a LinearVelocity flat along
	the floor, only as far as the way ahead is clear (a spherecast first, then
	a look ahead every frame), with a capped force: shoved into a wall, mob or
	prop at full force the body was flung into the air. Never leaves you
	rising either. Afterimages trail it (budgeted: FxBudget).

	  DashController.Init(getAim)   getAim(root) → the flat aim direction
	  DashController.Dash()         try to dash now
	  DashController.Ready() → 0..1 how far the cooldown has come back
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

local DashController = {}

local COOLDOWN = 1.1 -- (Dash.COOLDOWN on the server)
local DASH_TIME = 0.16
local SPEED = 100 -- studs a second: ~16 studs a dash
local RADIUS = 1.4 -- (the body's width, for the look ahead)
local STOP_SHORT = 1.5 -- studs short of whatever's in the way
local FORCE = 6000 -- (per unit of the body's mass: enough for SPEED in a frame, not to fling)
local GHOSTS = 3
local GHOST_COLOR = Color3.fromRGB(190, 225, 255)

local player = Players.LocalPlayer
local lastDash = -math.huge
local getAim: ((BasePart) -> Vector3)? = nil

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

function DashController.Dash()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not hum or not root then return end
	local now = os.clock()
	if now - lastDash < COOLDOWN or not canDash(char, hum, root) then return end
	-- which way: where you're walking, else toward the cursor
	local dir = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
	if dir.Magnitude < 0.1 and getAim then dir = (getAim :: (BasePart) -> Vector3)(root) end
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then dir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z) end
	if dir.Magnitude < 0.1 then return end
	dir = dir.Unit
	lastDash = now
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
	return math.clamp((os.clock() - lastDash) / COOLDOWN, 0, 1)
end

function DashController.Init(aim: (BasePart) -> Vector3)
	getAim = aim
end

return DashController
