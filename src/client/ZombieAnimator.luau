--!strict
--[[
	ZombieAnimator.luau
	The zombies' bodies (plain zombies, ghouls, brutes, the risen: every mob
	tagged "Shambler" by MobManager), posed every frame on each client:

	  walking   a limping shamble: the right leg stiff and dragged, the body
	            lurching onto each step, hunched, arms reaching out ahead at
	            uneven heights, the head lolling and twitching
	  standing  swaying where it stands, arms half raised and drifting, the
	            head rolling on its neck
	  attacking (MobManager's "AttackAt") both arms thrown up and brought
	            down in a lunge, the body pitching in behind them

	Each zombie has its own limp, reach and rhythm, so a crowd doesn't move in
	step. Only near the camera; not while a move of its own drives it
	(MobBusy) or once it's dead. R6 bodies.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ZombieAnimator = {}

local TAG = "Shambler"
local RANGE = 140   -- further off than this from the camera: left as it is
local LUNGE = 0.6   -- seconds the attack takes

type Body = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	rootJ: Motor6D,
	neck: Motor6D,
	ls: Motor6D, rs: Motor6D,
	lh: Motor6D, rh: Motor6D,
	phase: number,
	seed: number,
	limp: number,   -- 1: drags the right leg, -1: the left
	reachL: number, reachR: number,
	gait: number,   -- steps per stud walked
	twitchAt: number,
	twitch: number,
	speed: number,  -- smoothed
}

local bodies: { [Model]: Body } = {}

local function motor(parent: Instance?, name: string): Motor6D?
	local m = parent and parent:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

local function bodyOf(model: Model): Body?
	local b = bodies[model]
	if b and b.rootJ.Parent and b.neck.Parent then return b end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local torso = model:FindFirstChild("Torso")
	local rootJ = motor(root, "RootJoint")
	local neck, ls, rs = motor(torso, "Neck"), motor(torso, "Left Shoulder"), motor(torso, "Right Shoulder")
	local lh, rh = motor(torso, "Left Hip"), motor(torso, "Right Hip")
	if not (hum and root and rootJ and neck and ls and rs and lh and rh) then return nil end
	local rng = Random.new()
	local nb: Body = {
		model = model, hum = hum :: Humanoid, root = root :: BasePart,
		rootJ = rootJ :: Motor6D, neck = neck :: Motor6D, ls = ls :: Motor6D, rs = rs :: Motor6D, lh = lh :: Motor6D, rh = rh :: Motor6D,
		phase = rng:NextNumber(0, math.pi * 2),
		seed = rng:NextNumber(0, 100),
		limp = if rng:NextNumber() < 0.5 then 1 else -1,
		reachL = rng:NextNumber(1.05, 1.45), reachR = rng:NextNumber(1.2, 1.6),
		gait = rng:NextNumber(0.13, 0.17),
		twitchAt = os.clock() + rng:NextNumber(1, 4),
		twitch = 0,
		speed = 0,
	}
	bodies[model] = nb
	return nb
end

local function clamp01(x: number): number
	return math.clamp(x, 0, 1)
end

-- Arms: + swings the right arm forward, - the left (R6 joints mirror).
-- Legs: the same. RootJoint and Neck: (pitch, roll, yaw), Z up.
local function pose(b: Body, dt: number, now: number, serverNow: number)
	local v = b.root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	b.speed += (speed - b.speed) * clamp01(dt * 8)
	local walk = clamp01(b.speed / 5)
	-- step on with the distance walked (a slow, uneven cadence)
	b.phase += b.speed * dt * b.gait * math.pi * 2
	local ph = b.phase
	local step = math.sin(ph)
	local t = now + b.seed

	-- the occasional twitch: a jerk of the head and an arm
	if now >= b.twitchAt then
		b.twitch = 1
		b.twitchAt = now + 1.5 + (math.noise(t, 3) + 1) * 2.5
	end
	b.twitch = math.max(0, b.twitch - dt * 5)
	local jerk = b.twitch * math.sin(now * 60)

	-- The lunge: arms up (0 → 0.4), then down and in (0.4 → 1).
	local at = b.model:GetAttribute("AttackAt")
	local a = if typeof(at) == "number" then (serverNow - at) / LUNGE else 2
	local lunge = 0
	local raise = 0
	if a >= 0 and a <= 1 then
		lunge = math.sin(a * math.pi)              -- in and out
		raise = if a < 0.4 then math.sin(a / 0.4 * math.pi / 2) else 1 - (a - 0.4) / 0.6
	end

	-- The legs: the bad leg barely swings and drags; the good one takes the stride.
	local good, bad = 0.55, 0.2
	local ampR = if b.limp > 0 then bad else good
	local ampL = if b.limp > 0 then good else bad
	local idleShift = math.sin(t * 0.7) * 0.06 * (1 - walk)
	local rhA = (ampR * step) * walk + idleShift
	local lhA = (ampL * step) * walk + idleShift
	-- (the dragged leg trails a little behind the body)
	if b.limp > 0 then rhA -= 0.12 * walk else lhA += 0.12 * walk end

	-- The body: hunched, dipping and rolling onto the bad leg as weight goes on it.
	local onBad = math.max(0, step * b.limp)
	local hunch = 0.28 + 0.05 * math.sin(ph * 2) * walk + lunge * 0.45 + math.sin(t * 0.9) * 0.03 * (1 - walk)
	local roll = (0.14 * step * walk + 0.1 * onBad * b.limp * walk) + math.sin(t * 0.8) * 0.07 * (1 - walk)
	local yaw = 0.1 * step * walk + math.sin(t * 0.5) * 0.05 * (1 - walk)
	local bob = -0.28 * onBad * onBad * walk - 0.15 * lunge

	-- The arms: reaching out ahead, uneven, bobbing with the steps; drifting
	-- half up standing; thrown up and down in the lunge.
	local reachR = b.reachR * walk + (0.55 + 0.12 * math.sin(t * 1.1)) * (1 - walk)
	local reachL = b.reachL * walk + (0.4 + 0.12 * math.sin(t * 0.9 + 1.3)) * (1 - walk)
	local swayR = 0.12 * math.sin(ph + 0.6) * walk
	local swayL = 0.12 * math.sin(ph + 2.2) * walk
	local up = raise * 1.4
	local rsA = reachR + swayR + up + 0.25 * jerk
	local lsA = -(reachL + swayL + up)

	-- The head: lolling on its neck, hanging forward, jerking.
	local hPitch = 0.22 + 0.1 * math.sin(t * 1.3) + 0.15 * lunge
	local hRoll = 0.3 * math.sin(t * 0.9) + 0.4 * jerk
	local hYaw = 0.25 * math.sin(t * 0.6 + 1.7) + 0.15 * jerk

	b.rootJ.Transform = CFrame.new(0, 0, bob) * CFrame.Angles(-hunch, roll, yaw)
	b.neck.Transform = CFrame.Angles(-hPitch, hRoll, hYaw)
	b.rs.Transform = CFrame.Angles(0, 0, rsA)
	b.ls.Transform = CFrame.Angles(0, 0, lsA)
	-- (the legs swing back under the hunch so the feet stay under it)
	b.rh.Transform = CFrame.Angles(0, 0, rhA + hunch * 0.6)
	b.lh.Transform = CFrame.Angles(0, 0, lhA - hunch * 0.6)
end

function ZombieAnimator.Init()
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		if inst:IsA("Model") then bodies[inst] = nil end
	end)
	-- (after the Animator has stepped: what's set here is what's drawn)
	RunService.Stepped:Connect(function(_, dt)
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		local now = os.clock()
		local serverNow = Workspace:GetServerTimeNow()
		for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
			if not inst:IsA("Model") or not inst:IsDescendantOf(Workspace) then continue end
			local model = inst :: Model
			if model:GetAttribute("MobBusy") == true then continue end
			local b = bodyOf(model)
			if not b or b.hum.Health <= 0 then continue end
			if (b.root.Position - camPos).Magnitude > RANGE then continue end
			pose(b, dt, now, serverNow)
		end
		for model in pairs(bodies) do
			if not model.Parent then bodies[model] = nil end
		end
	end)
end

return ZombieAnimator
