--!strict
--[[
	MobAnimator.luau
	The dungeon mobs' bodies, posed every frame on each client.

	Rigs (tag "MobRig": the R6 Zombie, Skeleton and NPCghost templates and
	every kind dressed on them; MobManager plays no animation tracks on
	them). Each joint is posed on its own, never the whole body turned stiff:

	  walking   the stride runs off the distance really covered (no feet
	            skating): the legs swing about the hips and the body sinks
	            as they open so the feet stay on the floor; the arms swing
	            against the legs; the torso rolls onto each step and twists
	            against the hips; it leans into its speed and into its turns
	            (shuffling its feet round turning on the spot); the head
	            steadies against all of it and follows you
	  standing  breathing, the weight shifting, the head looking about
	  attacking read off the body, not just the floor: MobManager stamps
	            "AttackAt" (server time) and "AttackWindup" as a swing
	            starts. The wind-up runs the whole windup (the tell: the
	            weight goes back, the arms draw back, a tremble at the end),
	            the strike whips through as the hit lands, follows through
	            and recovers. Archers ("DrawAt", "DrawTime"): side-on, the bow
	            arm raised at you, the string drawn back to the cheek,
	            trembling, loosed (the hand snapping back), recovered
	  hit       a flinch: the body knocked back, the head snapping
	  dying     slumping forward and down as it fades

	Gaits, by kind:
	  shamble   zombie, risen, shackled soul: bent over at the back, one leg
	            stiff and dragged, lurching and rolling onto each step, one
	            arm reaching for you and the other hanging loose, the head
	            lolling. Swing: both arms thrown up and back, then brought
	            down together in a lunge
	  feral     ghoul: low and fast, a long loping stride, arms pumping.
	            Swing: coiled low, the claw drawn back, then a raking swipe
	            across with the body twisting through
	  heavy     brute, executioner, ogre crusher: slow, wide, heavy stomps,
	            the body rolling with the weight. Swing: both arms raised high
	            over the head, leaning back, then smashed down into the floor
	  march     skeleton archers, sniper, bombardier: upright and stiff, a
	            rattling march. Shot: the draw
	  robed     bone mage, necromancer, jailer: short gliding steps, arms
	            held in before the body
	  float     wraith: drifting above the floor, legs trailing limp, leaning
	            into the glide, arms trailing. Swing: rearing up with both
	            arms swept back, then lunging in with a crossing double rake

	While one of its signature moves runs (MobBusy, posed by MobKinds) only
	the legs keep walking under it. Only near the camera.

	Blobs (tag "MobBlob": the slimes). Their parts are welded to an
	invisible root, so each slime is drawn here as a copy of itself (the real
	parts hidden on this client, the copy following them) that squashes and
	stretches: crouching, springing up stretched, falling, landing squashed,
	hop after hop as it moves; standing, it wobbles.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local MobAnimator = {}

local RIG_TAG = "MobRig"
local BLOB_TAG = "MobBlob"
local RANGE = 150 -- further off than this from the camera: left as it is

-- ── Gaits ───────────────────────────────────────────────────────────────────
-- Angles in degrees, in the body's own space (the CastPoses conventions):
-- Root (the torso on the root): -rx leans forward, +ry turns left (right
-- shoulder forward), rz rolls; px/py/pz shift it. RS/LS: +rx raises the arm
-- forward, RS +rz / LS -rz raises it out to the side. RH/LH the same for the
-- legs. N: +rx looks down, +ry looks left.
type Gait = {
	stride: number,  -- studs covered per full stride (both feet)
	swing: number,   -- leg swing at a full stride
	arm: number,     -- arm swing
	lean: number,    -- forward lean at speed
	stand: number,   -- forward lean standing
	roll: number,    -- torso roll onto each step
	twist: number,   -- torso twist against the hips
	armsOut: number, -- arms held out from the sides
	armRest: number, -- arms held forward
	jitter: number,  -- a bony rattle
	float: boolean,  -- drifts above the floor, legs trailing
	limp: boolean,   -- one leg dragged, one arm reaching, the head lolling
}

local GAITS: { [string]: Gait } = {
	shamble = { stride = 4.4, swing = 24, arm = 8, lean = 26, stand = 20, roll = 10, twist = 6, armsOut = 8, armRest = 0, jitter = 0,
		float = false, limp = true },
	feral = { stride = 7, swing = 38, arm = 36, lean = 28, stand = 22, roll = 6, twist = 12, armsOut = 14, armRest = 10, jitter = 0,
		float = false, limp = false },
	heavy = { stride = 5, swing = 24, arm = 16, lean = 12, stand = 8, roll = 8, twist = 8, armsOut = 18, armRest = 4, jitter = 0,
		float = false, limp = false },
	march = { stride = 4.6, swing = 30, arm = 26, lean = 6, stand = 2, roll = 3, twist = 9, armsOut = 5, armRest = 0, jitter = 1,
		float = false, limp = false },
	robed = { stride = 3.8, swing = 20, arm = 6, lean = 7, stand = 4, roll = 2, twist = 4, armsOut = 8, armRest = 24, jitter = 0.4,
		float = false, limp = false },
	float = { stride = 8, swing = 0, arm = 10, lean = 26, stand = 8, roll = 4, twist = 4, armsOut = 18, armRest = -12, jitter = 0,
		float = true, limp = false },
}

local GAIT_OF: { [string]: string } = {
	zombie = "shamble", risen = "shamble", shackled = "shamble",
	ghoul = "feral",
	brute = "heavy", executioner = "heavy", crusher = "heavy",
	skeleton = "march", sniper = "march", bombardier = "march",
	bonemage = "robed", necromancer = "robed", jailer = "robed",
	wraith = "float",
}
local GAIT_OF_TEMPLATE: { [string]: string } = { Zombie = "shamble", Skeleton = "march", NPCghost = "float" }

-- ── Swings: the wind-up (held through the windup) and the strike ────────────
type Pose = { [string]: { number } }
type Swing = { windup: Pose, strike: Pose }

local SWINGS: { [string]: Swing } = {
	shamble = {
		windup = { Root = { 14, 0, 0, 0, 0, 0.35 }, RS = { 155, 0, 18 }, LS = { 155, 0, -18 }, N = { -18, 0, 0 }, RH = { -10, 0, 4 }, LH = { 16, 0, -4 } },
		strike = { Root = { -38, 0, 0, 0, -0.35, -0.7 }, RS = { 55, 0, -6 }, LS = { 55, 0, 6 }, N = { 20, 0, 0 }, RH = { 30, 0, 4 }, LH = { -22, 0, -4 } },
	},
	feral = {
		windup = { Root = { -30, -28, 0, 0, -0.45, 0.35 }, RS = { -40, 0, 38 }, LS = { 62, 0, -22 }, N = { -26, 22, 0 }, RH = { -22, 0, 6 }, LH = { 34, 0, -6 } },
		strike = { Root = { -24, 32, 0, 0, -0.35, -0.9 }, RS = { 108, 0, -58 }, LS = { -24, 0, -30 }, N = { -14, -16, 0 }, RH = { 38, 0, 6 }, LH = { -32, 0, -6 } },
	},
	heavy = {
		windup = { Root = { 16, 0, 0, 0, 0, 0.4 }, RS = { 172, 0, 10 }, LS = { 172, 0, -10 }, N = { -22, 0, 0 }, RH = { -12, 0, 8 }, LH = { 20, 0, -8 } },
		strike = { Root = { -46, 0, 0, 0, -0.55, -0.6 }, RS = { 38, 0, -10 }, LS = { 38, 0, 10 }, N = { 26, 0, 0 }, RH = { 36, 0, 8 }, LH = { -28, 0, -8 } },
	},
	march = {
		windup = { Root = { 4, -32, 0, 0, 0, 0.2 }, RS = { 150, 0, 40 }, LS = { 40, 0, -22 }, N = { -6, 26, 0 }, RH = { -10, 0, 6 }, LH = { 16, 0, -6 } },
		strike = { Root = { -16, 34, 0, 0, -0.2, -0.45 }, RS = { 62, 0, -48 }, LS = { 8, 0, -30 }, N = { 8, -20, 0 }, RH = { 26, 0, 6 }, LH = { -20, 0, -6 } },
	},
	robed = {
		windup = { Root = { 8, -14, 0, 0, 0, 0.2 }, RS = { 130, 0, 14 }, LS = { 70, 0, -16 }, N = { -10, 10, 0 } },
		strike = { Root = { -18, 14, 0, 0, -0.15, -0.4 }, RS = { 80, 0, -12 }, LS = { 50, 0, -14 }, N = { 8, -6, 0 } },
	},
	float = {
		windup = { Root = { 18, 0, 0, 0, 0.6, 0.6 }, RS = { -40, 0, 72 }, LS = { -40, 0, -72 }, N = { -22, 0, 0 }, RH = { -30, 0, 6 }, LH = { -42, 0, -6 } },
		strike = { Root = { -42, 0, 0, 0, -0.15, -1.2 }, RS = { 112, 0, -56 }, LS = { 112, 0, 56 }, N = { 26, 0, 0 }, RH = { -52, 0, 6 }, LH = { -64, 0, -6 } },
	},
}

-- The archer's draw: side-on, the bow (right hand) raised at you, the left
-- hand drawing the string back to the cheek; the loose: the hand snapping
-- back.
local DRAW_RAISE: Pose = { Root = { 0, 72, 0, 0, -0.1, 0 }, RS = { 18, 0, 84 }, LS = { 88, 0, 86 }, N = { -4, -62, 0 }, RH = { 2, 0, 12 }, LH = { -4, 0, -12 } }
local DRAW_FULL: Pose = { Root = { 5, 76, 0, 0, -0.1, 0.1 }, RS = { 16, 0, 88 }, LS = { 86, 0, 40 }, N = { -2, -66, 0 }, RH = { 2, 0, 12 }, LH = { -4, 0, -12 } }
local DRAW_LOOSE: Pose = { Root = { -4, 70, 0, 0, -0.1, -0.05 }, RS = { 24, 0, 90 }, LS = { 60, 0, -28 }, N = { -2, -62, 0 }, RH = { 2, 0, 12 }, LH = { -4, 0, -12 } }

local STRIKE = 0.1   -- seconds the strike whips through
local HOLD = 0.14    -- held at the end of the strike
local RECOVER = 0.45 -- back to the walk
local FLINCH = 0.28  -- a hit's flinch
local SLUMP = 0.5    -- collapsing as it dies

local KEYS = { "Root", "N", "RS", "LS", "RH", "LH" }
local PART_OF: { [string]: string } = { Torso = "Root", Head = "N", ["Right Arm"] = "RS", ["Left Arm"] = "LS", ["Right Leg"] = "RH", ["Left Leg"] = "LH" }

type Body = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	motors: { [string]: Motor6D },
	basis: { [string]: CFrame },
	gait: Gait,
	swing: Swing,
	scale: number,
	phase: number,
	seed: number,
	limpSide: number, -- 1: drags the right leg, -1: the left
	speed: number,    -- smoothed
	yaw: number,
	yawRate: number,  -- smoothed, degrees a second
	lookYaw: number,  -- the head's, smoothed
	lookPitch: number,
	health: number,
	flinchAt: number,
	flinchRoll: number,
	diedAt: number?,
	slumpRoll: number,
	busy: number,     -- 0..1, a signature move driving it
	pose: { [string]: { number } },
}

local bodies: { [Model]: Body } = {}

local function gaitName(model: Model): string
	local kind = model:GetAttribute("MobKind")
	return (typeof(kind) == "string" and GAIT_OF[kind]) or GAIT_OF_TEMPLATE[model.Name] or "march"
end

local function bodyOf(model: Model): Body?
	local b = bodies[model]
	if b and b.motors.Root and b.motors.Root.Parent then return b end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (hum and root) then return nil end
	local motors: { [string]: Motor6D } = {}
	local basis: { [string]: CFrame } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 then
			local key = PART_OF[d.Part1.Name]
			if key and not motors[key] then
				motors[key] = d
				basis[key] = d.C0.Rotation
			end
		end
	end
	for _, k in ipairs(KEYS) do
		if not motors[k] then return nil end
	end
	local name = gaitName(model)
	local rng = Random.new()
	local look = root.CFrame.LookVector
	local pose = {}
	for _, k in ipairs(KEYS) do pose[k] = { 0, 0, 0, 0, 0, 0 } end
	local nb: Body = {
		model = model, hum = hum, root = root, motors = motors, basis = basis,
		gait = GAITS[name], swing = SWINGS[name] or SWINGS.march,
		scale = model:GetScale(),
		phase = rng:NextNumber(0, math.pi * 2), seed = rng:NextNumber(0, 100),
		limpSide = if rng:NextNumber() < 0.5 then 1 else -1,
		speed = 0, yaw = math.atan2(-look.X, -look.Z), yawRate = 0, lookYaw = 0, lookPitch = 0,
		health = hum.Health, flinchAt = -10, flinchRoll = 0, diedAt = nil, slumpRoll = rng:NextNumber(-12, 12),
		busy = 0, pose = pose,
	}
	bodies[model] = nb
	return nb
end

-- ── Pose arithmetic ─────────────────────────────────────────────────────────
local function clear(p: { [string]: { number } })
	for _, k in ipairs(KEYS) do
		local v = p[k]
		v[1], v[2], v[3], v[4], v[5], v[6] = 0, 0, 0, 0, 0, 0
	end
end

-- p += q * w
local function add(p: { [string]: { number } }, q: Pose, w: number)
	for k, a in pairs(q) do
		local v = p[k]
		if v then
			for i = 1, #a do v[i] += a[i] * w end
		end
	end
end

-- p = p * (1 - w) + q * w (keys q has; the rest fade toward rest by w)
local function blend(p: { [string]: { number } }, q: Pose, w: number)
	if w <= 0 then return end
	for _, k in ipairs(KEYS) do
		local v = p[k]
		local a = q[k]
		for i = 1, 6 do
			v[i] = v[i] * (1 - w) + (if a then a[i] or 0 else 0) * w
		end
	end
end

local function lerpPose(a: Pose, b: Pose, k: number): Pose
	local out: Pose = {}
	for _, key in ipairs(KEYS) do
		local x, y = a[key], b[key]
		if x or y then
			local v = {}
			for i = 1, 6 do
				local xa = if x then x[i] or 0 else 0
				local yb = if y then y[i] or 0 else 0
				v[i] = xa + (yb - xa) * k
			end
			out[key] = v
		end
	end
	return out
end

local function easeInOut(a: number): number
	return if a < 0.5 then 2 * a * a else 1 - (-2 * a + 2) ^ 2 / 2
end
local function easeOut(a: number): number
	return 1 - (1 - a) ^ 3
end

-- The swing (or the draw) at `a` seconds in: its pose and how much of the
-- body it owns.
local function swingPose(sw: Swing, a: number, windup: number): (Pose?, number)
	if a < 0 then return nil, 0 end
	if a < windup then
		local k = easeInOut(a / windup)
		-- (the tell: a tremble as it's about to come)
		local shake = math.max(0, (a / windup - 0.65) / 0.35)
		local p = lerpPose({}, sw.windup, k)
		if shake > 0 then
			local s = math.sin(a * 70) * 2.5 * shake
			for _, key in ipairs({ "RS", "LS", "Root" }) do
				local v = p[key]
				if v then v[1] += s end
			end
		end
		return p, math.min(1, a / 0.12)
	end
	a -= windup
	if a < STRIKE then return lerpPose(sw.windup, sw.strike, easeOut(a / STRIKE)), 1 end
	a -= STRIKE
	if a < HOLD then return sw.strike, 1 end
	a -= HOLD
	if a < RECOVER then return sw.strike, 1 - easeInOut(a / RECOVER) end
	return nil, 0
end

local function drawPose(a: number, draw: number): (Pose?, number)
	if a < 0 then return nil, 0 end
	local raise = draw * 0.4
	if a < raise then return DRAW_RAISE, easeInOut(a / raise) end
	if a < draw then
		local k = easeInOut((a - raise) / (draw - raise))
		local p = lerpPose(DRAW_RAISE, DRAW_FULL, k)
		-- (holding the draw: the arm trembling)
		local s = math.sin(a * 60) * 1.8 * k
		p.LS[1] += s
		return p, 1
	end
	a -= draw
	if a < 0.08 then return lerpPose(DRAW_FULL, DRAW_LOOSE, easeOut(a / 0.08)), 1 end
	a -= 0.08
	if a < 0.12 then return DRAW_LOOSE, 1 end
	a -= 0.12
	if a < RECOVER then return DRAW_LOOSE, 1 - easeInOut(a / RECOVER) end
	return nil, 0
end

-- ── A rig, this frame ───────────────────────────────────────────────────────
local function nearestPlayer(pos: Vector3): Vector3?
	local best: Vector3? = nil
	local bestD = 60
	for _, plr in ipairs(Players:GetPlayers()) do
		local c = plr.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			local d = (r.Position - pos).Magnitude
			if d < bestD then best, bestD = r.Position, d end
		end
	end
	return best
end

local function wrap(a: number): number
	return (a + math.pi) % (math.pi * 2) - math.pi
end

local function animate(b: Body, dt: number, now: number, serverNow: number)
	local g = b.gait
	local P = b.pose
	clear(P)
	local t = now + b.seed
	local root = b.root
	local sc = b.scale

	-- how it's moving
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude / sc
	b.speed += (speed - b.speed) * math.min(1, dt * 10)
	local look = root.CFrame.LookVector
	local yaw = math.atan2(-look.X, -look.Z)
	local dYaw = wrap(yaw - b.yaw)
	b.yaw = yaw
	b.yawRate += (math.deg(dYaw) / math.max(dt, 1e-3) - b.yawRate) * math.min(1, dt * 8)
	local turning = math.clamp(math.abs(b.yawRate) / 180, 0, 1)
	local w = math.clamp(b.speed / 4, 0, 1)
	local moving = math.max(w, turning * 0.6)

	-- the stride: on with the distance covered (and shuffling round on a turn)
	local cycles = b.speed / g.stride + turning * 1.2
	b.phase += cycles * dt * math.pi * 2
	local ph = b.phase
	local s = math.sin(ph)
	local swingAmt = g.swing * math.clamp(b.speed / (g.stride * 1.4), 0.25, 1) * moving

	-- hit: a flinch
	local h = b.hum.Health
	if h < b.health - 0.5 then
		b.flinchAt = now
		b.flinchRoll = (math.random() - 0.5) * 16
	end
	b.health = h

	local R, N, RS, LS, RH, LH = P.Root, P.N, P.RS, P.LS, P.RH, P.LH

	if g.float then
		-- drifting above the floor: a slow bob, leaning into the glide, legs
		-- trailing limp behind, arms trailing out
		R[5] += 0.45 + 0.18 * math.sin(t * 2.1)
		R[1] -= g.stand + (g.lean - g.stand) * w
		R[3] += math.sin(t * 1.3) * 3 - b.yawRate * 0.03
		RH[1] += -18 - 22 * w + math.sin(t * 2.1) * 7
		LH[1] += -26 - 22 * w + math.sin(t * 2.1 + 1.1) * 7
		RS[1] += g.armRest - 22 * w + math.sin(t * 1.6) * 8
		LS[1] += g.armRest - 22 * w + math.sin(t * 1.6 + 2) * 8
		RS[3] += g.armsOut + math.sin(t * 1.2) * 6
		LS[3] -= g.armsOut + math.sin(t * 1.2 + 1) * 6
	else
		-- the legs swing about the hips, against each other
		RH[1] += swingAmt * s
		LH[1] -= swingAmt * s
		-- the arms swing against the legs
		RS[1] += -g.arm * s * w + g.armRest
		LS[1] += g.arm * s * w + g.armRest
		RS[3] += g.armsOut
		LS[3] -= g.armsOut
		-- the torso: leaning into its speed, rolling onto each step, twisting
		-- against the hips (the hips turned back so the legs stay straight),
		-- leaning into a turn
		R[1] -= g.stand + (g.lean - g.stand) * w
		R[2] += -g.twist * s * w
		RH[2] += g.twist * s * w
		LH[2] += g.twist * s * w
		R[3] += g.roll * s * w + math.clamp(-b.yawRate * 0.04, -12, 12)
		-- standing: breathing, the weight shifting from foot to foot
		local idle = 1 - w
		R[1] += math.sin(t * 1.7) * 1.4 * idle
		R[4] += math.sin(t * 0.55) * 0.08 * idle * sc
		R[3] += math.sin(t * 0.55) * 2.5 * idle
		RS[3] += math.sin(t * 1.7) * 2 * idle
		LS[3] -= math.sin(t * 1.7 + 0.4) * 2 * idle
	end

	if g.limp then
		-- the shamble: one leg barely swings and drags behind, the body lurches
		-- and sags onto it; one arm reaches out for you, unsteady, the other
		-- hangs loose and flops; the head lolls
		local bad = if b.limpSide > 0 then RH else LH
		bad[1] = bad[1] * 0.35 - 10 * w
		local onBad = math.max(0, s * b.limpSide)
		R[3] += 9 * onBad * b.limpSide * w + math.noise(t * 0.4, b.seed) * 8
		R[1] -= 5 * math.abs(s) * w
		R[5] -= 0.25 * onBad * w * sc
		local reach = if b.limpSide > 0 then LS else RS
		local hang = if b.limpSide > 0 then RS else LS
		reach[1] += 62 * w + 26 * (1 - w) + math.sin(t * 1.1) * 7
		hang[1] += 18 * math.sin(ph + 1.2) * w + math.sin(t * 2.3) * 5
		N[3] += math.sin(t * 0.9) * 18 - 14 * s * w
		N[2] += math.sin(t * 0.6 + 1.7) * 12
	end
	if g.jitter > 0 then
		-- (a bony rattle)
		local j = g.jitter * (0.6 + w)
		RS[3] += math.noise(t * 18, b.seed) * 4 * j
		LS[3] -= math.noise(t * 18, b.seed + 3) * 4 * j
		N[3] += math.noise(t * 14, b.seed + 6) * 5 * j
	end

	-- the head: steady against the lean, turned to the nearest player
	N[1] += (g.stand + (g.lean - g.stand) * w) * 0.7
	local target = nearestPlayer(root.Position)
	local wantYaw, wantPitch = math.sin(t * 0.37) * 25, 0
	if target then
		local off = root.CFrame:PointToObjectSpace(target)
		wantYaw = math.deg(math.atan2(-off.X, -off.Z))
		wantPitch = math.deg(math.atan2(off.Y - 1.5 * sc, Vector3.new(off.X, 0, off.Z).Magnitude))
	end
	b.lookYaw += (math.clamp(wantYaw, -60, 60) - b.lookYaw) * math.min(1, dt * 6)
	b.lookPitch += (math.clamp(wantPitch, -30, 30) - b.lookPitch) * math.min(1, dt * 6)
	N[2] += b.lookYaw
	N[1] -= b.lookPitch

	-- a signature move driving it (MobKinds poses it): only the legs walk on
	local busy = if b.model:GetAttribute("MobBusy") == true then 1 else 0
	b.busy += (busy - b.busy) * math.min(1, dt * 10)
	if b.busy > 0.01 then
		local keep = 1 - b.busy
		for _, k in ipairs({ "Root", "N", "RS", "LS" }) do
			local x = P[k]
			for i = 1, 6 do x[i] *= keep end
		end
	end

	-- the swing / the draw
	if b.busy < 0.5 then
		local at = b.model:GetAttribute("AttackAt")
		if typeof(at) == "number" then
			local windup = tonumber(b.model:GetAttribute("AttackWindup")) or 0.45
			local sp, sw = swingPose(b.swing, serverNow - at, windup)
			if sp and sw > 0 then blend(P, sp, sw) end
		end
		local drawAt = b.model:GetAttribute("DrawAt")
		if typeof(drawAt) == "number" then
			local dp, dw = drawPose(serverNow - drawAt, tonumber(b.model:GetAttribute("DrawTime")) or 0.6)
			if dp and dw > 0 then blend(P, dp, dw) end
		end
	end

	-- the flinch
	local fa = now - b.flinchAt
	if fa < FLINCH then
		local k = math.sin(fa / FLINCH * math.pi) * (1 - fa / FLINCH * 0.4)
		add(P, { Root = { 12, 0, b.flinchRoll, 0, 0, 0.18 * sc }, N = { -20, b.flinchRoll, 0 }, RS = { 22, 0, 14 }, LS = { 22, 0, -14 } }, k)
	end

	-- keep the feet on the floor: the legs turned back against the torso's
	-- lean and roll, the body lowered as they open (and as the lean lifts the hips)
	if not g.float then
		local pitch, roll = R[1], R[3]
		RH[1] -= pitch
		LH[1] -= pitch
		RH[3] -= roll
		LH[3] -= roll
		local open = math.rad(math.max(math.abs(RH[1] + pitch), math.abs(LH[1] + pitch)))
		R[5] -= (2 * (1 - math.cos(open)) + (1 - math.cos(math.rad(pitch)))) * sc
	end

	-- dying: slumping forward and down
	if b.diedAt then
		local k = easeInOut(math.min((now - b.diedAt) / SLUMP, 1))
		blend(P, { Root = { -70, 0, b.slumpRoll, 0, -2 * sc, -0.8 * sc }, N = { 30, 0, b.slumpRoll }, RS = { 30, 0, 10 }, LS = { 30, 0, -10 },
			RH = { 60, 0, 10 }, LH = { 50, 0, -10 } }, k)
	end

	for _, k in ipairs(KEYS) do
		local m = b.motors[k]
		local x = P[k]
		local cf = CFrame.new(x[4], x[5], x[6]) * CFrame.fromEulerAnglesXYZ(math.rad(x[1]), math.rad(x[2]), math.rad(x[3]))
		local basis = b.basis[k]
		m.Transform = basis:Inverse() * cf * basis
	end
end

-- ── Blobs: the slimes' squash and stretch ───────────────────────────────────
type BlobPart = { real: BasePart, vis: BasePart }
type Blob = {
	model: Model,
	root: BasePart,
	parts: { BlobPart },
	bottom: number,  -- the lowest point under the root (root space)
	scale: number,
	hop: number,     -- 0..1 through the current hop
	speed: number,
	seed: number,
	shown: boolean,
}

local blobs: { [Model]: Blob } = {}
local visFolder: Folder? = nil
local function folder(): Folder
	local f = visFolder
	if f and f.Parent then return f end
	local nf = Instance.new("Folder")
	nf.Name = "MobBlobs"
	nf.Parent = Workspace
	visFolder = nf
	return nf
end

local function blobOf(model: Model): Blob?
	local b = blobs[model]
	if b then return b end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local parts: { BlobPart } = {}
	local bottom = 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= root and d.Transparency < 0.98 then
			local vis = d:Clone()
			for _, c in ipairs(vis:GetChildren()) do
				if not (c:IsA("SpecialMesh") or c:IsA("Decal") or c:IsA("Texture") or c:IsA("SurfaceAppearance")) then c:Destroy() end
			end
			vis.Anchored = true
			vis.CanCollide, vis.CanQuery, vis.CanTouch = false, false, false
			vis.Massless = true
			vis.Parent = folder()
			table.insert(parts, { real = d, vis = vis })
			local rel = root.CFrame:PointToObjectSpace(d.Position)
			bottom = math.min(bottom, rel.Y - d.Size.Y / 2)
		end
	end
	if #parts == 0 then return nil end
	local nb: Blob = { model = model, root = root, parts = parts, bottom = bottom, scale = model:GetScale(), hop = 0, speed = 0,
		seed = math.random() * 100, shown = false }
	blobs[model] = nb
	return nb
end

local function dropBlob(model: Model)
	local b = blobs[model]
	if not b then return end
	blobs[model] = nil
	for _, p in ipairs(b.parts) do
		p.vis:Destroy()
		if p.real.Parent then p.real.LocalTransparencyModifier = 0 end
	end
end

local function showBlob(b: Blob, on: boolean)
	if b.shown == on then return end
	b.shown = on
	for _, p in ipairs(b.parts) do
		p.real.LocalTransparencyModifier = if on then 1 else 0
		if not on then p.vis.Transparency = 1 end
	end
end

local blobParts: { BasePart } = {}
local blobCFs: { CFrame } = {}

local function animateBlob(b: Blob, dt: number, now: number)
	local root = b.root
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude / b.scale
	b.speed += (speed - b.speed) * math.min(1, dt * 8)
	-- hop after hop as it moves (finishing the hop it's in when it stops)
	local hopLen = 4.5
	if b.speed > 1 or b.hop > 0.001 then
		b.hop += math.max(b.speed / hopLen, if b.hop > 0 then 1.6 else 0) * dt
		if b.hop >= 1 then b.hop = if b.speed > 1 then b.hop % 1 else 0 end
	end
	local u = b.hop
	local sx, sy, lift = 1, 1, 0
	local H = 1.3
	if u <= 0 then
		-- standing: a wobble
		local t = now + b.seed
		sy = 1 + 0.05 * math.sin(t * 2.6)
		sx = 1 - 0.03 * math.sin(t * 2.6)
	elseif u < 0.15 then
		local k = u / 0.15                 -- crouching for the spring
		sy, sx = 1 - 0.25 * k, 1 + 0.16 * k
	elseif u < 0.5 then
		local k = (u - 0.15) / 0.35        -- springing up, stretched
		sy = 0.75 + 0.47 * easeOut(math.min(k * 2, 1))
		sx = 1.16 - 0.26 * easeOut(math.min(k * 2, 1))
		lift = math.sin(k * math.pi / 2) * H
	elseif u < 0.85 then
		local k = (u - 0.5) / 0.35         -- falling, easing back round
		sy, sx = 1.22 - 0.17 * k, 0.9 + 0.07 * k
		lift = math.cos(k * math.pi / 2) * H
	else
		local k = (u - 0.85) / 0.15        -- landing squashed
		sy = 1.05 - 0.05 * k - 0.3 * math.sin(k * math.pi)
		sx = 0.97 + 0.03 * k + 0.2 * math.sin(k * math.pi)
	end
	local frame = root.CFrame
	local bottom = b.bottom
	for _, p in ipairs(b.parts) do
		local real = p.real
		if real.Parent then
			local rel = frame:ToObjectSpace(real.CFrame)
			local pos = rel.Position
			local at = Vector3.new(pos.X * sx, (pos.Y - bottom) * sy + bottom + lift * b.scale, pos.Z * sx)
			table.insert(blobParts, p.vis)
			table.insert(blobCFs, frame * CFrame.new(at) * rel.Rotation)
			p.vis.Size = real.Size * Vector3.new(sx, sy, sx)
			p.vis.Transparency = real.Transparency
			p.vis.Color = real.Color
		end
	end
end

-- ── The loop ────────────────────────────────────────────────────────────────
function MobAnimator.Init()
	CollectionService:GetInstanceRemovedSignal(RIG_TAG):Connect(function(inst)
		if inst:IsA("Model") then bodies[inst] = nil end
	end)
	CollectionService:GetInstanceRemovedSignal(BLOB_TAG):Connect(function(inst)
		if inst:IsA("Model") then dropBlob(inst) end
	end)
	-- (after the Animator has stepped: what's set here is what's drawn)
	RunService.Stepped:Connect(function(_, dt)
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		local now = os.clock()
		local serverNow = Workspace:GetServerTimeNow()
		for _, inst in ipairs(CollectionService:GetTagged(RIG_TAG)) do
			if not inst:IsA("Model") or not inst:IsDescendantOf(Workspace) then continue end
			local model = inst :: Model
			local b = bodyOf(model)
			if not b then continue end
			if (b.root.Position - camPos).Magnitude > RANGE then continue end
			if b.hum.Health <= 0 then
				if not b.diedAt then b.diedAt = now end
				if now - b.diedAt > 1.2 then continue end
			end
			local ok, err = pcall(animate, b, dt, now, serverNow)
			if not ok then
				warn("[MobAnimator]", model.Name, err)
				bodies[model] = nil
			end
		end
		for model in pairs(bodies) do
			if not model.Parent then bodies[model] = nil end
		end

		table.clear(blobParts)
		table.clear(blobCFs)
		for _, inst in ipairs(CollectionService:GetTagged(BLOB_TAG)) do
			if not inst:IsA("Model") or not inst:IsDescendantOf(Workspace) then continue end
			local model = inst :: Model
			local b = blobOf(model)
			if not b then continue end
			local near = b.root.Parent ~= nil and (b.root.Position - camPos).Magnitude <= RANGE
			showBlob(b, near)
			if near then animateBlob(b, dt, now) end
		end
		if #blobParts > 0 then
			Workspace:BulkMoveTo(blobParts, blobCFs, Enum.BulkMoveMode.FireCFrameChanged)
		end
		for model in pairs(blobs) do
			if not model.Parent then dropBlob(model) end
		end
	end)
end

return MobAnimator
