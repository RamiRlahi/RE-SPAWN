--!strict
--[[
	AimStance.luau
	How every class stands in a run: the legs go the way you walk (WASD), the
	upper body turns to the cursor, a twist at the waist of up to 100 degrees
	either way (the feet come round past that); the legs turn as one, like a
	pelvis, the hips following the chest a quarter of the way. Backpedalling keeps the legs
	on the walking line; standing still, the feet only turn once the cursor
	swings past ~80 degrees. (The Ice Mage's skates steer the legs; only the
	twist is added.)

	Your client steers your body and works out the twist; the twist goes to the
	server (AimTwist), which puts it on your character for everyone else's
	client to pose you with. Off while a skill, the ultimate or a tumble drives
	the body, riding a mount, in the lobby, or with the shoulder (classic)
	camera.

	  AimStance.Init(getAim)   getAim(root) → the flat direction to the cursor
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))

local player = Players.LocalPlayer

local AimStance = {}

local MAX_TWIST = math.rad(100)
local FEET_TURN = math.cos(math.rad(80)) -- standing still: the feet turn past this
local BACKPEDAL = -0.35                  -- walking away from the cursor this much: legs on the line, backwards
local SEND_EVERY = 0.1                   -- seconds between twists sent
local SEND_STEP = 0.04                   -- (radians: smaller changes aren't sent)
local EASE = 12                          -- how quickly others' twists follow
local BEAST_TWIST = math.rad(30)         -- the Berserker's beast: only a little
local HIP_SHARE = 0.25                   -- the hips turn this much of the way with the chest

local getAim: ((BasePart) -> Vector3)? = nil
local twist = 0
local steering = false
local lastSent, lastSentAt = 0, 0
local shown: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

-- ── Steering your own body ─────────────────────────────────────────────────
local function steer(dt: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or not getAim then
		twist = 0
		return
	end
	-- Not in this mode at all: hand the turning back to the Humanoid.
	local on = player:GetAttribute("InLobby") == false and player:GetAttribute("Setting_classicCamera") ~= true
		and not char:GetAttribute("Riding") and hum.Health > 0
	if not on then
		twist = 0
		if steering then
			steering = false
			if not hum.PlatformStand then hum.AutoRotate = true end
		end
		return
	end
	-- Something else is driving the body for now (a skill, the ult, a
	-- planted swing, a tumble): leave it be.
	if char:GetAttribute("IsUltActive") == true or char:GetAttribute("IsSkillCasting") == true or char:GetAttribute("Rooted") == true
		or char:GetAttribute("Tumbling") or hum.PlatformStand or root.Anchored then
		twist = 0
		return
	end
	steering = true
	hum.AutoRotate = false
	local aim = (getAim :: (BasePart) -> Vector3)(root)
	aim = Vector3.new(aim.X, 0, aim.Z)
	if aim.Magnitude < 0.01 then return end
	aim = aim.Unit
	-- The Berserker's beast doesn't twist at the waist: standing, the whole
	-- body swings round hard to face the target (its claws step round, in
	-- BerserkerController); moving, it runs where it runs, the head and
	-- shoulders only half turned.
	local beast = (tonumber(player:GetAttribute("BR_BeastUntil")) or 0) > workspace:GetServerTimeNow()
	if beast then
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local move = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
		local body = if move.Magnitude > 0.1 then move.Unit else aim
		local newLook = if look:Dot(body) < -0.95 then body else look:Lerp(body, math.min(1, dt * 18)).Unit
		root.CFrame = CFrame.lookAt(root.Position, root.Position + newLook)
		local l = root.CFrame:VectorToObjectSpace(aim)
		twist = math.clamp(math.atan2(-l.X, -l.Z), -BEAST_TWIST, BEAST_TWIST)
		return
	end
	-- The legs (the skates steer an Ice Mage's themselves).
	if player:GetAttribute("SelectedClass") ~= "ice_mage" then
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
		local move = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
		local body = look
		if move.Magnitude > 0.1 then
			move = move.Unit
			body = if move:Dot(aim) < BACKPEDAL then -move else move
		elseif look:Dot(aim) < FEET_TURN then
			body = aim
		end
		local newLook = if look:Dot(body) < -0.95 then body else look:Lerp(body, math.min(1, dt * 14)).Unit
		root.CFrame = CFrame.lookAt(root.Position, root.Position + newLook)
	end
	-- The top half: what's left between the legs' facing and the cursor.
	local l = root.CFrame:VectorToObjectSpace(aim)
	twist = math.clamp(math.atan2(-l.X, -l.Z), -MAX_TWIST, MAX_TWIST)
end

-- Ours to the server now and then (only when it's moved).
local function send()
	local now = os.clock()
	if now - lastSentAt < SEND_EVERY or math.abs(twist - lastSent) < SEND_STEP then return end
	lastSent, lastSentAt = twist, now
	Network.GetRemoteEvent(Network.Remotes.AimTwist):FireServer(twist)
end

-- ── Posing everyone ────────────────────────────────────────────────────────
local function motor(char: Model, part: string, name: string): Motor6D?
	local limb = char:FindFirstChild(part)
	local m = limb and limb:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

-- Adds a yaw about the parent part's up axis on top of whatever the
-- Animator wrote this frame: at the joint itself, or (aroundCentre) about
-- the vertical line through the parent part's centre. If the Animator didn't
-- touch the joint since our last write, start again from its last animated
-- value so the twist never accumulates.
local written: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local animated: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local function yawOver(m: Motor6D, yaw: number, aroundCentre: boolean?)
	local cur = m.Transform
	if written[m] ~= cur then animated[m] = cur end
	local r = if aroundCentre then m.C0 else m.C0.Rotation
	local out = r:Inverse() * CFrame.Angles(0, yaw, 0) * r * (animated[m] or cur)
	m.Transform = out
	written[m] = out
end

-- The top half turned to `yaw`. The legs don't each swivel on their own hip
-- joint (that splays and crosses them): they turn together, as a pelvis
-- would, round the middle of the body, and the hips come a little way round
-- with the chest (HIP_SHARE) so the stance reads as one twisting body.
local function pose(char: Model, yaw: number)
	local root = motor(char, "HumanoidRootPart", "RootJoint")
	if root then
		yawOver(root, yaw)
		local back = -yaw * (1 - HIP_SHARE)
		local rh, lh = motor(char, "Torso", "Right Hip"), motor(char, "Torso", "Left Hip")
		if rh then yawOver(rh, back, true) end
		if lh then yawOver(lh, back, true) end
	else
		-- (R15: the hips are the lower torso; it takes its share, the waist the rest)
		local hip = motor(char, "LowerTorso", "Root")
		local waist = motor(char, "UpperTorso", "Waist")
		if hip then yawOver(hip, yaw * HIP_SHARE) end
		if waist then yawOver(waist, yaw * (1 - HIP_SHARE)) end
	end
end

local function poseAll(dt: number)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if not char then continue end
		local want: number
		if plr == player then
			want = twist
		else
			local a = char:GetAttribute("AimTwist")
			-- (theirs only counts in a run, on their feet, nothing else posing them)
			want = if typeof(a) == "number" and plr:GetAttribute("InLobby") == false and not char:GetAttribute("Riding")
				and not char:GetAttribute("Tumbling") and char:GetAttribute("IsUltActive") ~= true then a else 0
		end
		local cur = shown[char] or 0
		cur = if plr == player then want else cur + (want - cur) * math.min(1, dt * EASE)
		shown[char] = cur
		-- (the Berserker's beast poses its own body, legs and all)
		local beast = (tonumber(plr:GetAttribute("BR_BeastUntil")) or 0) > workspace:GetServerTimeNow()
		if math.abs(cur) > 0.01 and not char:GetAttribute("Tumbling") and not beast then pose(char, cur) end
	end
end

function AimStance.Init(aimFn: (BasePart) -> Vector3)
	getAim = aimFn
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(steer, dt)
		if not ok then warn("[AimStance]", err) end
		pcall(send)
	end)
	-- Stepped: after the Animator has posed the rig, before physics.
	RunService.Stepped:Connect(function(_, dt)
		local ok, err = pcall(poseAll, dt)
		if not ok then warn("[AimStance] pose", err) end
	end)
end

return AimStance
