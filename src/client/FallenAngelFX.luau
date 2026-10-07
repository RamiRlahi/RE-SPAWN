--!strict
--[[
	FallenAngelFX.luau
	Brings the Fallen Angel's body (BossAI.BuildFallenAngel) to life on every
	client. Every piece of it hangs on a Motor6D; here their Transform is set
	each frame (local only, nothing replicates):

	  Body            hovering: a slow rise and fall, breathing; leaning into
	                  its flight (forward as it dives, back as it rises)
	  Head            turned to watch you, tipped down at you
	  ArmL / ArmR     a slow sway, the sword arm carried forward; then into
	                  each attack's pose ("AngelPose", from BossAI): the sword
	                  drawn back (windup), swung across (slash), driven down
	                  (plunge, slam), both arms raised (cast), flung back (dash)
	  LegL / LegR     hanging loose and swaying, trailing behind as it flies
	  WingL / WingR   a slow, heavy beat (faster enraged or rushing); spread
	                  wide to rise or cast, swept back to dive or dash
	  Halo            turning slowly round its tilted axis, bobbing
	  Cloth           every strip swaying in a gusting wind, streaming out
	                  behind it the faster it moves

	Poses are eased into (snapped, for a slash or a slam). Angels far from
	the camera are left as they hang.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FallenAngelFX = {}

local CULL_DIST = 320
local player = Players.LocalPlayer

type Joint = { motor: Motor6D, cur: CFrame }
type Cloth = { motor: Motor6D, phase: number, back: boolean }
type Rig = {
	model: Model,
	root: BasePart,
	scale: number,
	joints: { [string]: Joint },
	cloth: { Cloth },
}

local rigs: { [Model]: Rig } = {}

local rad = math.rad

-- Each pose, in degrees: the arms (x forward / up, y across to the left,
-- z out to the side), the body (lean back, twist left, lift in units), the
-- legs (forward, spread) and the wings (lift, sweep back, beat, beat rate).
type Pose = {
	armR: { number }, armL: { number },
	body: { number }, leg: { number },
	wing: { number }, head: number?, snap: boolean?,
}
local IDLE: Pose = {
	armR = { 0, 0, 0 }, armL = { 0, 0, 0 },
	body = { 0, 0, 0 }, leg = { 4, 2 },
	wing = { 0, 0, 1, 1 },
}
local POSES: { [string]: Pose } = {
	windup = { armR = { 125, -30, 35 }, armL = { 20, 0, -25 }, body = { 8, -25, 0 }, leg = { 0, 4 }, wing = { 8, 0, 1, 1.2 } },
	slash = { armR = { 55, 75, -10 }, armL = { -15, 0, -30 }, body = { -10, 30, -0.1 }, leg = { 6, 5 }, wing = { 5, 12, 1, 1.4 }, snap = true },
	plunge = { armR = { -20, 15, 5 }, armL = { -10, 0, -20 }, body = { -22, 0, -0.3 }, leg = { 18, 6 }, wing = { 18, -6, 0.6, 1 }, head = -20, snap = true },
	slam = { armR = { -25, 0, 10 }, armL = { -25, 0, -10 }, body = { -15, 0, -0.35 }, leg = { 18, 8 }, wing = { 30, -5, 0.2, 1 }, head = -15, snap = true },
	cast = { armR = { 160, 0, 20 }, armL = { 160, 0, -20 }, body = { 12, 0, 0.2 }, leg = { -10, 8 }, wing = { 28, -12, 0.5, 0.8 }, head = 20 },
	rise = { armR = { 20, 0, 45 }, armL = { 20, 0, -45 }, body = { 10, 0, 0 }, leg = { -15, 6 }, wing = { 22, -8, 1.4, 1.6 } },
	dive = { armR = { 150, 0, 10 }, armL = { 150, 0, -10 }, body = { -35, 0, 0 }, leg = { -40, 2 }, wing = { -10, 50, 0.3, 1 }, head = -25 },
	volley = { armR = { 80, 10, 0 }, armL = { 60, -20, -20 }, body = { 6, 0, 0 }, leg = { 0, 4 }, wing = { 25, -10, 0.6, 1 } },
	dash = { armR = { -40, 0, 15 }, armL = { -40, 0, -15 }, body = { -30, 0, 0 }, leg = { -50, 0 }, wing = { -8, 60, 0.2, 1 } },
}

local function rigOf(model: Model): Rig?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local scale = model:GetAttribute("AngelScale")
	local r: Rig = {
		model = model, root = root,
		scale = if typeof(scale) == "number" then scale else root.Size.Y / 2.2,
		joints = {}, cloth = {},
	}
	for _, j in ipairs(model:GetDescendants()) do
		if j:IsA("Motor6D") then
			if j.Name == "Cloth" then
				-- (strips on its back stream out further than the front ones)
				table.insert(r.cloth, { motor = j, phase = math.random() * 10, back = j.C0.Position.Z > 0 })
			else
				r.joints[j.Name] = { motor = j, cur = CFrame.identity }
			end
		end
	end
	if next(r.joints) == nil and #r.cloth == 0 then return nil end
	return r
end

local function scan()
	for model in pairs(rigs) do
		if not model.Parent then rigs[model] = nil end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return end
	for _, m in ipairs(mobs:GetChildren()) do
		if m:IsA("Model") and not rigs[m] and m:GetAttribute("AngelBuilt") == true then
			local r = rigOf(m)
			if r then rigs[m] = r end
		end
	end
end

local function angles(v: { number }, mirror: number?): CFrame
	local s = mirror or 1
	return CFrame.Angles(rad(v[1]), rad(v[2]) * s, rad(v[3]) * s)
end

-- Ease joint `name` toward `target`; false if the joint is gone (re-rig).
local function drive(r: Rig, name: string, target: CFrame, alpha: number): boolean
	local j = r.joints[name]
	if not j then return true end
	if not j.motor.Parent then return false end
	j.cur = j.cur:Lerp(target, alpha)
	j.motor.Transform = j.cur
	return true
end

local function animate(r: Rig, t: number, dt: number): boolean
	local S = r.scale
	local enraged = r.model:GetAttribute("Enraged") == true
	local poseName = r.model:GetAttribute("AngelPose")
	local p = (typeof(poseName) == "string" and POSES[poseName]) or IDLE
	local vel = r.root.AssemblyLinearVelocity
	local localVel = r.root.CFrame:VectorToObjectSpace(vel) -- (-Z is forward)
	local rush = math.clamp(Vector3.new(vel.X, 0, vel.Z).Magnitude / 40, 0, 1)
	local fwd = math.clamp(-localVel.Z / 30, -1, 1)
	local sideways = math.clamp(localVel.X / 30, -1, 1)
	local alpha = 1 - math.exp(-dt * (if p.snap then 26 else 9))
	local breath = math.sin(t * 1.7)

	-- Body: hovering and breathing, leaning into its flight.
	local body = CFrame.new(0, (0.05 + 0.12 * breath + p.body[3]) * S, 0)
		* CFrame.Angles(rad(p.body[1]) + rad(1.5) * math.sin(t * 1.7 + 1) - rad(14) * fwd, rad(p.body[2]), -rad(10) * sideways)
	if not drive(r, "Body", body, alpha) then return false end

	-- Head: watching you (when it isn't looking up or down for a move).
	local look = CFrame.identity
	local char = player.Character
	local me = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local headJoint = r.joints.Head
	if me and headJoint and headJoint.motor.Part1 then
		local d = r.root.CFrame:VectorToObjectSpace(me.Position - (headJoint.motor.Part1 :: BasePart).Position)
		local yaw = math.clamp(math.atan2(-d.X, -d.Z), rad(-50), rad(50))
		local pitch = math.clamp(math.atan2(d.Y, Vector3.new(d.X, 0, d.Z).Magnitude), rad(-30), rad(15))
		look = CFrame.Angles(0, yaw - rad(p.body[2]), 0) * CFrame.Angles(pitch, 0, 0)
	end
	if p.head then look = CFrame.Angles(rad(p.head), 0, 0) end
	if not drive(r, "Head", look * CFrame.Angles(rad(2) * math.sin(t * 0.9), 0, rad(2) * math.sin(t * 0.6)), alpha) then return false end

	-- Arms: a slow sway, trailing a little as it flies; then the pose.
	local trail = -rad(15) * rush
	if not drive(r, "ArmR", angles(p.armR) * CFrame.Angles(rad(4) * math.sin(t * 1.7 + 0.5) + trail, 0, 0), alpha) then return false end
	if not drive(r, "ArmL", angles(p.armL) * CFrame.Angles(rad(5) * math.sin(t * 1.7 + 2) + trail, 0, 0), alpha) then return false end

	-- Legs: hanging loose, trailing behind in flight.
	for _, side in ipairs({ -1, 1 }) do
		local swing = rad(p.leg[1]) + rad(5) * math.sin(t * 1.3 + side) - rad(35) * rush
		local target = CFrame.Angles(swing, 0, rad(p.leg[2]) * side)
		if not drive(r, if side < 0 then "LegL" else "LegR", target, alpha) then return false end
	end

	-- Wings: one heavy beat every ~2.6 s, faster enraged or rushing; spread
	-- or swept by the pose.
	local w = p.wing
	local rate = (if enraged then 3.2 else 2.4) * w[4]
	local beat = math.sin(t * rate) * w[3]
	local lift = rad(if enraged then 13 else 9) * (beat * 0.5 + 0.5) + rad(w[1])
	local sweep = rad(8) * beat + rad(18) * rush + rad(w[2])
	for _, side in ipairs({ -1, 1 }) do
		-- (about its base: Z lifts it, Y sweeps it back)
		local target = CFrame.Angles(rad(3) * beat, side * sweep, side * lift)
		if not drive(r, if side < 0 then "WingL" else "WingR", target, 1 - math.exp(-dt * 12)) then return false end
	end

	-- Halo: turning, bobbing.
	local halo = r.joints.Halo
	if halo then
		if not halo.motor.Parent then return false end
		halo.motor.Transform = CFrame.new(0, math.sin(t * 1.3) * 0.15 * S, 0) * CFrame.Angles(0, t * (if enraged then 1.2 else 0.5), 0)
	end

	-- Cloth: a gusting breeze from one side, and the air it moves through.
	local gust = 0.6 + 0.4 * math.max(math.sin(t * 0.7), 0) ^ 2
	local stream = math.max(fwd, 0)
	for _, c in ipairs(r.cloth) do
		if not c.motor.Parent then return false end
		local flutter = math.sin(t * 3.1 + c.phase) * 0.6 + math.sin(t * 5.3 + c.phase * 1.7) * 0.4
		-- (+X swings the hem forward: the back strips stream out behind; the
		-- front ones only press flat against the body)
		local base = if c.back then -rad(6) else rad(4)
		local pitch = base - rad(if c.back then 55 else 4) * stream + rad(5) * flutter * gust
		local roll = rad(9) * gust * math.sin(t * 1.1 + c.phase) - rad(30) * sideways
		c.motor.Transform = CFrame.Angles(pitch, 0, roll)
	end
	return true
end

function FallenAngelFX.Init()
	task.spawn(function()
		while true do
			pcall(scan)
			task.wait(1)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if next(rigs) == nil then return end
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		local t = os.clock()
		for model, r in pairs(rigs) do
			if not model.Parent or not r.root.Parent then
				rigs[model] = nil
				continue
			end
			if (r.root.Position - camPos).Magnitude > CULL_DIST then continue end
			local ok, res = pcall(animate, r, t, dt)
			if not ok then
				warn("[FallenAngelFX]", res)
				rigs[model] = nil
			elseif not res then
				rigs[model] = nil -- (a joint streamed away: rigged again on the next scan)
			end
		end
	end)
end

return FallenAngelFX
