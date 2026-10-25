--!strict
--[[
	MountController.luau
	Riding (MountManager on the server): the mount key (B by default, Settings
	> Keybinds) calls your equipped mount, and sends it away again. Riding is
	faster than running; attacking or casting sends the mount away too.

	A hit while riding throws you off (MountManager → "thrown"): the tumble is
	worked out here from your momentum (Tumble.Plan), played, and the plan sent
	back so everyone else sees the same tumble ("tumble").

	Flight (the lobby only): mounted, double-tap Space to take off. WASD steers
	(camera-relative), hold Space to climb, Ctrl or Q to descend; the mount
	banks into turns and pitches with the climb. Come down onto the ground (or
	press the mount key) to land. Capped at FLY_CEILING over the plaza; ends
	if you dismount, die, are thrown or leave the lobby. Your client owns your
	character, so everyone else sees the flight through ordinary replication.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local Tumble = require(script.Parent:WaitForChild("Tumble"))
local RideData = require(Shared:WaitForChild("RideData"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local MapData = require(Shared:WaitForChild("MapData"))

local player = Players.LocalPlayer

local MountController = {}

local STILL = 6          -- slower than this: thrown off the front, the way you face

-- ── Flight ──────────────────────────────────────────────────────────────────
local DOUBLE_TAP = 0.3    -- seconds between the two Space presses to take off
local FLY_SPEED = 1.35    -- × the mount's riding speed, flat
local CLIMB = 26          -- studs/s up / down
local ACCEL = 4           -- how quickly the speed follows the controls (1/s)
local FLY_CEILING = 140   -- studs over the plaza
local LAND_GAP = 3.2      -- this close over the ground going down: landed

type Flight = { att: Attachment, lv: LinearVelocity, ao: AlignOrientation, conn: RBXScriptConnection,
	vel: Vector3, yaw: number, bank: number }
local flight: Flight? = nil
local lastSpace = 0
local controls: any = nil

local function moveVector(): Vector3
	if not controls then
		local ok, pm = pcall(function()
			return require((player:WaitForChild("PlayerScripts") :: any):WaitForChild("PlayerModule") :: any)
		end)
		controls = if ok and pm then pm:GetControls() else false
	end
	local mv = if controls then controls:GetMoveVector() else Vector3.zero
	if mv.Magnitude < 0.05 then return Vector3.zero end
	-- (camera-relative, flat)
	local cam = Workspace.CurrentCamera
	local look = Vector3.new(cam.CFrame.LookVector.X, 0, cam.CFrame.LookVector.Z)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, -1)
	local right = Vector3.new(-look.Z, 0, look.X)
	local v = right * mv.X - look * mv.Z
	return if v.Magnitude > 1 then v.Unit else v
end

-- (Space from the take-off's second tap isn't a climb: it only counts once
-- it's been let go)
local spaceArmed = false

local function vertical(): number
	if not UserInputService:IsKeyDown(Enum.KeyCode.Space) then spaceArmed = true end
	local up = spaceArmed and UserInputService:IsKeyDown(Enum.KeyCode.Space)
	local down = UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) or UserInputService:IsKeyDown(Enum.KeyCode.Q)
	return (if up then 1 else 0) - (if down then 1 else 0)
end

local function groundBelow(root: BasePart, char: Model): number?
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local hit = Workspace:Raycast(root.Position, Vector3.new(0, -400, 0), params)
	return hit and (root.Position.Y - hit.Position.Y) or nil
end

local function land()
	local f = flight
	if not f then return end
	flight = nil
	f.conn:Disconnect()
	f.lv:Destroy()
	f.ao:Destroy()
	f.att:Destroy()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.Freefall)
	end
	if char then char:SetAttribute("Flying", nil) end
end

local function takeOff()
	if flight then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (char and hum and root) or hum.Health <= 0 then return end
	if player:GetAttribute("InHub") ~= true then return end
	local riding = char:GetAttribute("Riding")
	if typeof(riding) ~= "string" or char:GetAttribute("Tumbling") then return end
	local reward = GachaRewards.Get(riding)
	local flat = RideData.Speed(reward and reward.rarity) * FLY_SPEED

	local att = Instance.new("Attachment")
	att.Name = "FlightAttachment"
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.MaxForce = 1e7
	lv.VectorVelocity = Vector3.zero
	lv.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = 1e7
	ao.Responsiveness = 18
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root
	hum.PlatformStand = true
	char:SetAttribute("Flying", true)

	local _, yaw = root.CFrame:ToOrientation()
	-- (it takes off into a hover: climbing is holding Space, after letting go)
	spaceArmed = false
	-- (a hop up off the floor, easing into the hover a few studs up)
	local f: Flight = { att = att, lv = lv, ao = ao, conn = nil :: any, vel = Vector3.new(0, 18, 0), yaw = yaw, bank = 0 }
	local liftOff = os.clock()
	f.conn = RunService.Heartbeat:Connect(function(dt)
		if not root.Parent or hum.Health <= 0 or char:GetAttribute("Riding") == nil or char:GetAttribute("Tumbling")
			or player:GetAttribute("InHub") ~= true then
			land()
			return
		end
		-- the controls → the wanted velocity, eased toward
		local move = moveVector()
		local vy = vertical() * CLIMB
		local ceiling = MapData.LOBBY_CENTER.Y + FLY_CEILING
		if root.Position.Y > ceiling and vy > 0 then vy = 0 end
		local want = move * flat + Vector3.new(0, vy, 0)
		f.vel = f.vel:Lerp(want, 1 - math.exp(-ACCEL * dt))
		lv.VectorVelocity = f.vel
		-- facing the way we fly; banking into turns, pitching with the climb
		local hv = Vector3.new(f.vel.X, 0, f.vel.Z)
		local turn = 0
		if hv.Magnitude > 2 then
			local want_yaw = math.atan2(-hv.X, -hv.Z)
			local d = (want_yaw - f.yaw + math.pi) % (2 * math.pi) - math.pi
			local step = math.clamp(d, -5 * dt, 5 * dt)
			f.yaw += step
			turn = step / math.max(dt, 1e-3)
		end
		f.bank += (math.clamp(-turn * 0.35, -0.6, 0.6) - f.bank) * (1 - math.exp(-6 * dt))
		local pitch = math.clamp(f.vel.Y / CLIMB, -1, 1) * 0.3
		ao.CFrame = CFrame.Angles(0, f.yaw, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, f.bank)
		-- flown down onto the ground (holding descend): landed
		if os.clock() - liftOff > 0.6 and vy < 0 then
			local gap = groundBelow(root, char)
			if gap and gap < hum.HipHeight + LAND_GAP then land() end
		end
	end)
	flight = f
end

function MountController.IsFlying(): boolean
	return flight ~= nil
end

local function isMountKey(input: InputObject): boolean
	local keyName = player:GetAttribute("Keybind_Mount") or SettingsConfig.DefaultSettings.keybinds.Mount
	if typeof(keyName) ~= "string" or keyName == "" or keyName == "None" then return false end
	if input.UserInputType == Enum.UserInputType.Keyboard then return input.KeyCode.Name == keyName end
	return input.UserInputType.Name == keyName
end

local function toggle()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 or char:GetAttribute("Tumbling") then return end
	-- (only in the lobby plaza: never in a run or the menus)
	if player:GetAttribute("InHub") ~= true then return end
	if flight then
		land()
		return
	end
	local riding = char:GetAttribute("Riding") ~= nil
	if not riding and typeof(player:GetAttribute("Mount")) ~= "string" then return end
	Network.GetRemoteEvent(Network.Remotes.MountToggle):FireServer(not riding)
end

-- Thrown off: the tumble goes the way we were going, as far as that speed carries us.
local function thrown()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or hum.Health <= 0 then return end
	land()
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local speed = flat.Magnitude
	local dir = if speed > STILL then flat.Unit else root.CFrame.LookVector
	local plan = Tumble.Plan(char, root, dir, speed)
	Tumble.Play(char, plan, true)
	Network.GetRemoteEvent(Network.Remotes.TumblePlan):FireServer(plan)
end

function MountController.Init()
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or player:GetAttribute("SettingsOpen") == true then return end
		if isMountKey(input) then toggle() end
		-- double-tap Space while riding: take off
		if input.KeyCode == Enum.KeyCode.Space and not flight then
			local now = os.clock()
			local char = player.Character
			if char and char:GetAttribute("Riding") ~= nil and now - lastSpace < DOUBLE_TAP then
				lastSpace = 0
				takeOff()
			else
				lastSpace = now
			end
		end
	end)
	player.CharacterRemoving:Connect(land)
	Network.GetRemoteEvent(Network.Remotes.MountFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		if msg.kind == "thrown" then
			local ok, err = pcall(thrown)
			if not ok then warn("[MountController] thrown", err) end
		elseif msg.kind == "tumble" and typeof(msg.player) == "Instance" and msg.player:IsA("Player") and typeof(msg.plan) == "table" then
			local char = msg.player.Character
			if char then
				local ok, err = pcall(Tumble.Play, char, msg.plan, false)
				if not ok then warn("[MountController] tumble", err) end
			end
		end
	end)
end

return MountController
