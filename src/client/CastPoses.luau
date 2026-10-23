--[[
	CastPoses.luau
	Procedural cast animations layered on top of whatever the Animator is playing.

	No uploaded animation assets are needed: every frame (after the Animator has
	written its pose) we multiply extra joint offsets onto each Motor6D.Transform.
	Poses are authored in "character space" degrees and converted into each
	motor's C0 frame, so the same pose works on R15 and (best-effort) R6 rigs.

	A pose sequence is a list of stages { dur, pose, style?, wobble? }. Each stage
	blends from the previous stage's pose to its own over `dur` seconds; the
	sequence always finishes with a blend back to neutral.

	Motion quality:
	  • Each joint value is blended per component (degrees / studs), so a
	    200° sweep goes the way it was authored, not the short way round.
	  • Secondary motion: the keyed curve is hit exactly on time, and a damped
	    spring per joint picks up part of every sudden change in speed. The
	    arms carry on past a hit and settle back (follow-through), lag a little
	    as a move starts (drag), and the head and arms trail the torso
	    (overlap). See DYN.
	  • R6 twist: on R6 the waist IS the root joint, so turning the torso would
	    turn the legs with it. The hips counter-turn (PLANT) so a W twist reads
	    as the torso coiling over planted feet; Root still turns everything.
	  • Interrupting a move (combo chains) carries on from where the body is,
	    speed included.
--]]

local RunService = game:GetService("RunService")

local CastPoses = {}

-- Short joint names → { R15 part, R15 motor, R6 part, R6 motor }
local JOINTS = {
	Root = { "LowerTorso", "Root", "HumanoidRootPart", "RootJoint" },
	W = { "UpperTorso", "Waist", "HumanoidRootPart", "RootJoint" },
	N = { "Head", "Neck", "Torso", "Neck" },
	RS = { "RightUpperArm", "RightShoulder", "Torso", "Right Shoulder" },
	LS = { "LeftUpperArm", "LeftShoulder", "Torso", "Left Shoulder" },
	RE = { "RightLowerArm", "RightElbow" },
	LE = { "LeftLowerArm", "LeftElbow" },
	RW = { "RightHand", "RightWrist" },
	LW = { "LeftHand", "LeftWrist" },
	RH = { "RightUpperLeg", "RightHip", "Torso", "Right Hip" },
	LH = { "LeftUpperLeg", "LeftHip", "Torso", "Left Hip" },
	RK = { "RightLowerLeg", "RightKnee" },
	LK = { "LeftLowerLeg", "LeftKnee" },
}
-- Fixed order: on R6 Root and W share the root joint, and Root (the whole
-- body) is applied before W (the torso on top of it).
local ORDER = { "Root", "W", "N", "RS", "LS", "RE", "LE", "RW", "LW", "RH", "LH", "RK", "LK" }
local LEGS = { RH = true, LH = true, RK = true, LK = true }

-- Secondary motion per joint. `carry`: the share of a sudden change in speed
-- the joint keeps (how far it swings past a hit / lags into a move);
-- `freq` (Hz) / `damp` (damping ratio): how that leftover swings out and
-- settles. Extremities carry more and swing slower than the core, so they
-- trail it; the legs barely move, so the feet stay planted.
local DYN = {
	Root = { carry = 0.08, freq = 6, damp = 0.6 },
	W = { carry = 0.08, freq = 5, damp = 0.55 },
	N = { carry = 0.16, freq = 3.5, damp = 0.5 },
	RS = { carry = 0.12, freq = 4.5, damp = 0.45 },
	LS = { carry = 0.12, freq = 4.5, damp = 0.45 },
	RE = { carry = 0.15, freq = 4, damp = 0.45 },
	LE = { carry = 0.15, freq = 4, damp = 0.45 },
	RW = { carry = 0.15, freq = 4, damp = 0.45 },
	LW = { carry = 0.15, freq = 4, damp = 0.45 },
	RH = { carry = 0.05, freq = 7, damp = 0.8 },
	LH = { carry = 0.05, freq = 7, damp = 0.8 },
	RK = { carry = 0.05, freq = 7, damp = 0.8 },
	LK = { carry = 0.05, freq = 7, damp = 0.8 },
}
local KICK_MAX = { 900, 900, 900, 6, 6, 6 } -- per component: deg/s, studs/s
local SUBSTEP = 1 / 240
-- Share of a W twist the R6 hips turn back (1 = feet dead ahead; a little
-- less lets the hips follow the shoulders slightly, as real hips do).
local PLANT = 0.8

-- Pose value: { rx, ry, rz [, px, py, pz] } in degrees / studs.
-- +rx on a shoulder raises the arm forward; +rz raises the right arm sideways
-- (use -rz for the left arm); -rx on the waist leans forward.
-- R6 has no elbows, wrists or knees: an arm crosses the body with rx (forward)
-- plus rz toward the other side (right arm -rz, left arm +rz); ry on a
-- lowered arm only rolls it about its own length (turning a held blade).
type Pose = { [string]: { number } }
type Stage = { dur: number, pose: Pose, style: Enum.EasingStyle?, wobble: ((t: number) -> Pose)? }
type Vec = { number }

local ZERO: Vec = { 0, 0, 0, 0, 0, 0 }

local function poseCF(v: { number }?): CFrame
	if not v then return CFrame.identity end
	return CFrame.new(v[4] or 0, v[5] or 0, v[6] or 0)
		* CFrame.fromEulerAnglesXYZ(math.rad(v[1] or 0), math.rad(v[2] or 0), math.rad(v[3] or 0))
end

local function resolveMotors(char: Model): { [string]: { motor: Motor6D, basis: CFrame } }
	local out = {}
	for key, spec in pairs(JOINTS) do
		local motor: Instance? = nil
		local part = char:FindFirstChild(spec[1])
		motor = part and part:FindFirstChild(spec[2])
		if not (motor and motor:IsA("Motor6D")) and spec[3] then
			local r6Part = char:FindFirstChild(spec[3])
			motor = r6Part and r6Part:FindFirstChild(spec[4])
		end
		if motor and motor:IsA("Motor6D") then
			out[key] = { motor = motor, basis = motor.C0.Rotation }
		end
	end
	return out
end

-- Shared with SkateController's continuous pose layer.
CastPoses.poseCF = poseCF
CastPoses.resolveMotors = resolveMotors

-- Stage easing (value, and its slope for the secondary motion). Beyond the defaults:
--   Quad  smooth in-out (weight shifts, wind-ups, recoveries)
--   Quart accelerating in (a strike: slow start, fastest at the hit)
local C1, C3 = 1.70158, 2.70158
local function ease(style: Enum.EasingStyle, a: number): (number, number)
	if style == Enum.EasingStyle.Back then
		return 1 + C3 * (a - 1) ^ 3 + C1 * (a - 1) ^ 2, 3 * C3 * (a - 1) ^ 2 + 2 * C1 * (a - 1)
	elseif style == Enum.EasingStyle.Linear then
		return a, 1
	elseif style == Enum.EasingStyle.Sine then
		return -(math.cos(math.pi * a) - 1) / 2, math.pi / 2 * math.sin(math.pi * a)
	elseif style == Enum.EasingStyle.Quad then
		if a < 0.5 then return 2 * a * a, 4 * a end
		return 1 - (-2 * a + 2) ^ 2 / 2, 4 * (1 - a)
	elseif style == Enum.EasingStyle.Quart then
		return a ^ 3, 3 * a * a
	end
	return 1 - (1 - a) ^ 3, 3 * (1 - a) ^ 2 -- Cubic out: snappy attack, soft settle
end

local function toVec(v: { number }?): Vec
	if not v then return ZERO end
	return { v[1] or 0, v[2] or 0, v[3] or 0, v[4] or 0, v[5] or 0, v[6] or 0 }
end

type Seq = {
	elapsed: number,
	starts: { number },
	stages: { Stage },
	vecs: { { [string]: Vec } },
	from: { [string]: Vec },
	v0: { [string]: Vec },
	total: number,
	idx: number,
	absolute: boolean,
	w0: number,
	plant: boolean,
	carry: number,
}
type State = {
	motors: { [string]: { motor: Motor6D, basis: CFrame } },
	r6: boolean,
	sx: { [string]: Vec }, -- secondary offset
	sv: { [string]: Vec }, -- and its speed
	curve: { [string]: Vec }, -- last keyed value
	curveVel: { [string]: Vec },
	seq: Seq?,
	weight: number,
	rate: number, -- playback speed (hit-stop)
	rateUntil: number?,
}

local states: { [Model]: State } = {}
local conn: RBXScriptConnection? = nil

-- Whether a pose sequence is running on `char` (continuous pose layers, like
-- the Berserker's two-handed hold, step aside for it).
function CastPoses.isPlaying(char: Model): boolean
	local s = states[char]
	return s ~= nil and s.seq ~= nil
end

-- Layers that run every frame right after the sequences have posed the body
-- (e.g. the Berserker keeping both hands on his greatsword in every attack).
local postHooks: { (number) -> () } = {}
local lastStep = os.clock()

-- The keyed value and speed of `key` in stage `i` at progress `a`.
local function keyed(seq: Seq, key: string, i: number, a: number): (Vec, Vec)
	local st = seq.stages[i]
	local from = (if i > 1 then seq.vecs[i - 1][key] else seq.from[key]) or ZERO
	local to = seq.vecs[i][key] or ZERO
	local e, de = ease(st.style or Enum.EasingStyle.Cubic, a)
	local k = de / math.max(st.dur, 1e-3)
	local v, s = table.create(6), table.create(6)
	for c = 1, 6 do
		local d = to[c] - from[c]
		-- Whole turns between two keys are no turn at all (a flip keyed
		-- 0 → -360 → 0 doesn't spin back); a sweep under 360° goes the way
		-- it was authored.
		if c <= 3 and math.abs(d) >= 360 then
			d -= 360 * (if d > 0 then math.floor(d / 360) else math.ceil(d / 360))
		end
		v[c] = from[c] + d * e
		s[c] = d * k
	end
	return v, s
end

-- Entering stage `i`: every joint keeps `carry` of the jump in speed between
-- the end of the last stage (or the interrupted move) and the start of this one.
local function kick(S: State, seq: Seq, i: number)
	for key in pairs(S.motors) do
		local dyn = DYN[key]
		local vEnd: Vec = seq.v0[key] or ZERO
		if i > 1 then
			_, vEnd = keyed(seq, key, i - 1, 1)
		end
		local _, vStart = keyed(seq, key, i, 0)
		local sv = S.sv[key]
		local carry = dyn.carry * seq.carry
		for c = 1, 6 do
			local m = KICK_MAX[c]
			sv[c] += math.clamp((vEnd[c] - vStart[c]) * carry, -m, m)
		end
	end
end

local function newState(char: Model): State
	local motors = resolveMotors(char)
	local S: State = {
		motors = motors,
		r6 = motors.W ~= nil and motors.Root ~= nil and motors.W.motor == motors.Root.motor,
		sx = {}, sv = {}, curve = {}, curveVel = {},
		seq = nil,
		weight = 0,
		rate = 1,
		rateUntil = nil,
	}
	for key in pairs(motors) do
		S.sx[key] = table.clone(ZERO)
		S.sv[key] = table.clone(ZERO)
		S.curve[key] = ZERO
		S.curveVel[key] = ZERO
	end
	return S
end

local function step()
	local now = os.clock()
	local dt = math.min(now - lastStep, 0.1)
	lastStep = now

	for char, S in pairs(states) do
		if not char.Parent then
			states[char] = nil
			continue
		end
		if S.rateUntil and now >= S.rateUntil then
			S.rate, S.rateUntil = 1, nil
		end
		local sdt = dt * S.rate
		local seq = S.seq
		local wob: Pose? = nil
		local w = 1
		local elapsed = 0
		if seq then
			seq.elapsed += sdt
			elapsed = seq.elapsed
			local idx = #seq.stages
			for i = 1, #seq.stages do
				if elapsed < seq.starts[i] + seq.stages[i].dur then
					idx = i
					break
				end
			end
			-- Stages entered since last frame (short ones can be skipped over).
			while seq.idx < idx do
				seq.idx += 1
				kick(S, seq, seq.idx)
			end
			local st = seq.stages[idx]
			local a = math.clamp((elapsed - seq.starts[idx]) / math.max(st.dur, 1e-3), 0, 1)
			for key in pairs(S.motors) do
				S.curve[key], S.curveVel[key] = keyed(seq, key, idx, a)
			end
			wob = st.wobble and st.wobble(elapsed) or nil
			if seq.absolute then
				-- Absolute: the pose replaces the animation, blended in over the
				-- first stage and back out to the animation over the recovery.
				local e = ease(st.style or Enum.EasingStyle.Cubic, a)
				if idx == 1 then
					w = seq.w0 + (1 - seq.w0) * e
				elseif idx == #seq.stages then
					w = 1 - e
				end
			end
			S.weight = w
		else
			for key in pairs(S.motors) do
				S.curve[key], S.curveVel[key] = ZERO, ZERO
			end
		end

		-- Secondary motion: each joint's leftover swings back to the keyed curve.
		local n = math.max(1, math.ceil(sdt / SUBSTEP))
		local h = sdt / n
		local resting = true
		for key in pairs(S.motors) do
			local dyn = DYN[key]
			local om = 2 * math.pi * dyn.freq
			local k2, k1 = om * om, 2 * dyn.damp * om
			local x, v = S.sx[key], S.sv[key]
			for c = 1, 6 do
				local xc, vc = x[c], v[c]
				if xc ~= 0 or vc ~= 0 then
					for _ = 1, n do
						vc += (-k2 * xc - k1 * vc) * h
						xc += vc * h
					end
					if math.abs(xc) < 1e-3 and math.abs(vc) < 1e-2 then xc, vc = 0, 0 end
					x[c], v[c] = xc, vc
					if xc ~= 0 then resting = false end
				end
			end
		end

		local plantTurn = 0
		if S.r6 and (not seq or seq.plant) and S.motors.W then
			plantTurn = S.curve.W[2] + S.sx.W[2] + (wob and wob.W and wob.W[2] or 0)
		end

		local combined: { [Motor6D]: CFrame } = {}
		for _, key in ipairs(ORDER) do
			local m = S.motors[key]
			if not m then continue end
			local cv, sx = S.curve[key], S.sx[key]
			local cf = CFrame.new(cv[4] + sx[4], cv[5] + sx[5], cv[6] + sx[6])
				* CFrame.fromEulerAnglesXYZ(math.rad(cv[1] + sx[1]), math.rad(cv[2] + sx[2]), math.rad(cv[3] + sx[3]))
			if wob and wob[key] then cf *= poseCF(wob[key]) end
			if plantTurn ~= 0 and LEGS[key] then
				cf = CFrame.Angles(0, -math.rad(plantTurn) * PLANT, 0) * cf
			end
			-- Character-space offset → motor C0 space.
			local local_ = m.basis:Inverse() * cf * m.basis
			combined[m.motor] = (combined[m.motor] or CFrame.identity) * local_
		end
		if seq and seq.absolute then
			for motor, cf in pairs(combined) do
				motor.Transform = motor.Transform:Lerp(cf, w)
			end
		else
			for motor, cf in pairs(combined) do
				motor.Transform = motor.Transform * cf
			end
		end

		if seq and elapsed >= seq.total then
			S.seq = nil
			-- An absolute move has already blended fully back to the animation.
			if seq.absolute then states[char] = nil end
		elseif not seq and resting then
			states[char] = nil
		end
	end

	for _, hook in ipairs(postHooks) do
		local ok, err = pcall(hook, dt)
		if not ok then warn("[CastPoses] post hook:", err) end
	end
	if next(states) == nil and #postHooks == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function ensureStepping()
	if not conn then
		-- Stepped runs after the Animator has applied this frame's tracks.
		lastStep = os.clock()
		conn = RunService.Stepped:Connect(step)
	end
end

function CastPoses.addPostHook(fn: (number) -> ())
	table.insert(postHooks, fn)
	ensureStepping()
end

export type PlayOptions = {
	-- R6: turn the hips back against a W twist (default true).
	plant: boolean?,
	-- Scales the follow-through / drag of every joint (default 1; 0 = none).
	carry: number?,
	-- Plays the whole move this much faster (attack speed), so a fast combo's
	-- strike still lands before the next swing cuts it off.
	speed: number?,
}

-- `recover`: seconds to ease back to neutral afterwards (default 0.22; heavy
-- weapons settle slower).
-- `absolute`: the pose REPLACES the playing animation on every joint (blended
-- in over the first stage, back out over the recovery) instead of being added
-- on top of it: for full-body moves on characters whose own animations hold
-- the limbs far from neutral (e.g. the Fire Knight carrying his greatsword).
function CastPoses.play(char: Model?, stages: { Stage }, recover: number?, absolute: boolean?, opts: PlayOptions?)
	if not char then return end
	local S = states[char]
	local prev = S and S.seq
	if not S then
		S = newState(char)
		states[char] = S
	end
	local s = S :: State
	local seqStages = table.clone(stages)
	table.insert(seqStages, { dur = recover or 0.22, pose = {}, style = Enum.EasingStyle.Sine })
	local speed = math.max(opts and opts.speed or 1, 0.05)
	if speed ~= 1 then
		for i, st in ipairs(seqStages) do
			local c = table.clone(st)
			c.dur = st.dur / speed
			seqStages[i] = c
		end
	end
	local starts, vecs = {}, {}
	local total = 0
	for i, st in ipairs(seqStages) do
		starts[i] = total
		total += st.dur
		local vs = {}
		for key, v in pairs(st.pose) do vs[key] = toVec(v) end
		vecs[i] = vs
	end
	-- Carry on from where the body is (and how fast it's moving).
	local from, v0 = {}, {}
	for key in pairs(s.motors) do
		from[key] = s.curve[key] or ZERO
		v0[key] = s.curveVel[key] or ZERO
	end
	s.seq = {
		elapsed = 0,
		starts = starts,
		stages = seqStages,
		vecs = vecs,
		from = from,
		v0 = v0,
		total = total,
		idx = 0,
		absolute = absolute == true,
		-- An absolute move interrupting another carries on from its weight.
		w0 = if prev and prev.absolute then s.weight else 0,
		plant = not (opts and opts.plant == false),
		carry = opts and opts.carry or 1,
	}
	ensureStepping()
end

-- Playback speed of `char`'s poses (1 = normal, 0 = frozen), back to normal
-- after `seconds` if given.
function CastPoses.setRate(char: Model?, rate: number, seconds: number?)
	local S = char and states[char]
	if not S then return end
	S.rate = math.max(rate, 0)
	S.rateUntil = if seconds then os.clock() + seconds else nil
end

-- Hit-stop: the pose all but freezes for a beat as a blow lands, then runs on
-- (the hit itself isn't delayed, only the follow-through).
function CastPoses.hitStop(char: Model?, seconds: number?)
	CastPoses.setRate(char, 0.04, seconds or 0.06)
end

function CastPoses.stop(char: Model?)
	local S = char and states[char]
	if S and S.seq then
		local cur: Pose = {}
		for key, v in pairs(S.curve) do cur[key] = v end
		CastPoses.play(char, { { dur = 0.01, pose = cur } })
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Pose helpers
-- ═════════════════════════════════════════════════════════════════════════════

-- A grounded lower body for R6 (one rigid piece per leg, no knees). The torso
-- leans (`lean`, - = forward) and twists (`twist`, + = to the left; the hips
-- turn back so the feet keep pointing ahead); the legs are set by their WORLD
-- angle — left foot `front` degrees forward, right foot `back` degrees back
-- (negative swaps them), `spread` out to the sides — with the lean cancelled
-- at the hips, and the body drops exactly as far as the angled legs lower the
-- hips, so the feet stay on the floor instead of sinking into it. `shiftX` /
-- `shiftZ` slide the weight (studs; + = right / back).
function CastPoses.stance(p: Pose, lean: number, twist: number, front: number, back: number, spread: number?,
	shiftX: number?, shiftZ: number?): Pose
	local sp = spread or 6
	p.W = { lean, twist, 0 }
	p.LH = { front - lean, 0, -sp }
	p.RH = { -back - lean, 0, sp }
	local legs = math.rad((math.abs(front) + math.abs(back)) / 2)
	local drop = (1 - math.cos(math.rad(lean))) + 2 * (1 - math.cos(legs)) + 2 * (1 - math.cos(math.rad(sp)))
	p.Root = { 0, 0, 0, shiftX or 0, -drop, shiftZ or 0 }
	return p
end

-- A grounded body plus the upper-body joints in `upper` (N, RS, LS, ...).
function CastPoses.body(lean: number, twist: number, front: number, back: number, upper: Pose?, spread: number?,
	shiftX: number?, shiftZ: number?): Pose
	local p = CastPoses.stance({}, lean, twist, front, back, spread, shiftX, shiftZ)
	if upper then
		for k, v in pairs(upper) do p[k] = v end
	end
	return p
end

-- `p` lifted off the floor by `y` studs (a hop, a leap).
function CastPoses.lift(p: Pose, y: number): Pose
	local r = p.Root or { 0, 0, 0, 0, 0, 0 }
	p.Root = { r[1] or 0, r[2] or 0, r[3] or 0, r[4] or 0, (r[5] or 0) + y, r[6] or 0 }
	return p
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Pose library
-- ═════════════════════════════════════════════════════════════════════════════
-- ── Cleric ──────────────────────────────────────────────────────────────────
-- (R6 has no elbows or wrists: a hand comes to the chest with the arm raised
-- forward and turned in across the body, RS rz - / LS rz +.)
local QUAD, QUART = Enum.EasingStyle.Quad, Enum.EasingStyle.Quart
local body, lift = CastPoses.body, CastPoses.lift

function CastPoses.clericSmite(char: Model?)
	CastPoses.play(char, {
		-- Wind up: scepter drawn high and back over the right shoulder, the
		-- torso coiled to the right.
		{ dur = 0.07, style = QUAD, pose = body(6, -25, 10, 10,
			{ RS = { 150, 0, 30 }, LS = { 30, 0, -20 }, N = { 0, 15, 0 } }, 8, 0.1, 0.1) },
		-- Smite: the arm whips forward and across the body as it leaves.
		{ dur = 0.08, style = QUART, pose = body(-10, 25, 18, 16,
			{ RS = { 85, 0, -35 }, LS = { 10, 0, -30 }, N = { 0, -12, 0 } }, 8, -0.05, -0.3) },
		{ dur = 0.14, pose = body(-8, 30, 18, 16,
			{ RS = { 65, 0, -45 }, LS = { 5, 0, -25 }, N = { 0, -10, 0 } }, 8, -0.05, -0.3) },
	}, 0.24)
end

function CastPoses.clericHeal(char: Model?)
	CastPoses.play(char, {
		-- Hand to the heart, gathering light, head bowed.
		{ dur = 0.12, style = QUAD, pose = body(4, 15, 10, 10,
			{ RS = { 55, 0, -60 }, LS = { 20, 0, 15 }, N = { -12, 0, 0 } }, 8) },
		-- The open palm thrown out toward the ally.
		{ dur = 0.14, style = Enum.EasingStyle.Back, pose = body(-6, -15, 14, 12,
			{ RS = { 95, 0, 10 }, LS = { 30, 0, -25 }, N = { 2, 0, 0 } }, 8, 0, -0.2) },
		{ dur = 0.2, pose = body(-4, -12, 14, 12, { RS = { 90, 0, 8 }, LS = { 25, 0, -22 } }, 8, 0, -0.2) },
	}, 0.26)
end

local function tremble(amount: number, speed: number)
	return function(t: number): Pose
		local s = math.sin(t * speed) * amount
		local c = math.cos(t * speed * 1.3) * amount
		return { RS = { s, 0, c }, LS = { -s, 0, -c }, W = { c * 0.4, 0, 0 } }
	end
end

function CastPoses.clericBeam(char: Model?, duration: number)
	-- Braced against the recoil: leaning back a little over a wide stance,
	-- both arms locked straight out.
	local hold = body(8, 0, 24, 18, { RS = { 92, 0, -8 }, LS = { 92, 0, 8 }, N = { -4, 0, 0 } }, 12)
	CastPoses.play(char, {
		-- Both hands drawn in to the chest...
		{ dur = 0.12, style = QUAD, pose = body(-6, 0, 12, 10, { RS = { 50, 0, -45 }, LS = { 50, 0, 45 }, N = { -8, 0, 0 } }, 8) },
		-- ...then thrust out as the beam fires.
		{ dur = 0.1, style = Enum.EasingStyle.Back, pose = hold },
		{ dur = math.max(duration - 0.22, 0.1), pose = hold, wobble = tremble(1.6, 38) },
	}, 0.3)
end

function CastPoses.clericRadiantGround(char: Model?)
	CastPoses.play(char, {
		-- Scepter lifted to the heavens as the ray is called down, rising
		-- onto the toes.
		{ dur = 0.16, style = QUAD, pose = lift(body(14, 0, 6, 6,
			{ RS = { 170, 0, 10 }, LS = { 160, 0, -10 }, N = { 20, 0, 0 } }, 8), 0.15) },
		-- Driven into the floor: down into a wide crouch.
		{ dur = 0.08, style = QUART, pose = body(-30, 0, 38, 38,
			{ RS = { 55, 0, -10 }, LS = { 45, 0, 10 }, N = { -5, 0, 0 } }, 14) },
		{ dur = 0.22, pose = body(-24, 0, 36, 36, { RS = { 50, 0, -8 }, LS = { 40, 0, 8 }, N = { -2, 0, 0 } }, 14) },
	}, 0.3)
	task.delay(0.24, CastPoses.hitStop, char, 0.06)
end

function CastPoses.clericAscent(char: Model?, duration: number)
	local spread = { RS = { 25, 0, 95 }, LS = { 25, 0, -95 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 }, RW = { 0, 0, 20 }, LW = { 0, 0, -20 },
		W = { 16, 0, 0 }, N = { 28, 0, 0 }, RH = { 6, 0, 0 }, LH = { -4, 0, 0 }, RK = { -14, 0, 0 }, LK = { -24, 0, 0 } }
	CastPoses.play(char, {
		{ dur = 0.3, pose = { RS = { 45, 0, -30 }, LS = { 45, 0, 30 }, RE = { 100, 0, 0 }, LE = { 100, 0, 0 }, W = { -14, 0, 0 }, N = { -18, 0, 0 } } },
		{ dur = 0.35, style = Enum.EasingStyle.Back, pose = spread },
		{ dur = math.max(duration - 0.65, 0.2), pose = spread, style = Enum.EasingStyle.Sine, wobble = function(t)
			local b = math.sin(t * 2.2) * 4
			return { RS = { 0, 0, b }, LS = { 0, 0, -b }, W = { b * 0.4, 0, 0 } }
		end },
	})
end

-- Kneeling on one knee. On R6 each leg is one rigid piece (no knee joint), so:
-- the hips drop, the right leg points straight down, and the KNEELING leg (left)
-- angles back so its end rests on the floor behind — the knee down.
-- R6 legs hang off the torso, so leaning the upper body also tilts the legs;
-- `lean` (waist pitch, negative = forward) is compensated in the hip angles so
-- the feet stay planted. R15 rigs also bend the knees.
local KNEEL_DROP = 0.6        -- studs the hips sink
local KNEEL_LEG_ANGLE = 46    -- degrees each leg angles off vertical (acos(1.4 / 2) for R6 legs)
function CastPoses.kneelOnOneKnee(lean: number): Pose
	return {
		Root = { 0, 0, 0, 0, -KNEEL_DROP, 0 },
		W = { lean, 0, 0 },
		LH = { -KNEEL_LEG_ANGLE - lean, 0, -5 }, -- kneeling: angled back, knee on the floor
		RH = { -lean, 0, 3 },                    -- straight down
		LK = { -60, 0, 0 },
		RK = { -70, 0, 0 },
	}
end

-- Divine Ascent: kneel in prayer, then look up and open the arms to the light
-- as the allies are revived. `reviveAt` matches DivineAscentCutscene.REVIVE_AT.
function CastPoses.clericPrayer(char: Model?, duration: number, reviveAt: number)
	local function merge(a: Pose, b: Pose): Pose
		local out = table.clone(a)
		for k, v in pairs(b) do out[k] = v end
		return out
	end
	-- Hunched forward over clasped hands raised to the chin, head bowed deep.
	local prayer = merge(CastPoses.kneelOnOneKnee(-22), { N = { -36, 0, 0 },
		RS = { 102, 0, -36 }, LS = { 102, 0, 36 }, RE = { 115, 0, 0 }, LE = { 115, 0, 0 } })
	-- Revival: face lifted to the light, arms opening outward and up.
	local blessed = merge(CastPoses.kneelOnOneKnee(12), { N = { 22, 0, 0 },
		RS = { 125, 0, 42 }, LS = { 125, 0, -42 }, RE = { 10, 0, 0 }, LE = { 10, 0, 0 } })
	local prayHold = math.max(reviveAt - 0.1 - 0.45, 0.2)
	CastPoses.play(char, {
		{ dur = 0.45, style = Enum.EasingStyle.Sine, pose = prayer },
		{ dur = prayHold, pose = prayer, wobble = function(t)
			local b = math.sin(t * 2.4) * 1.5
			return { W = { b, 0, 0 }, N = { -b * 0.6, 0, 0 } }
		end },
		{ dur = 0.45, style = Enum.EasingStyle.Back, pose = blessed },
		{ dur = math.max(duration - (0.45 + prayHold + 0.45), 0.2), pose = blessed, wobble = function(t)
			local b = math.sin(t * 1.8) * 3
			return { RS = { b, 0, 0 }, LS = { b, 0, 0 } }
		end },
	})
end

-- ── Ranger ────────────────────────────────────────────────────────────────
-- Rain of Arrows wind-up (matches RangerFlair: slam 0.36s, loose 0.95s):
-- hoist the bow overhead, smash down into a crouch as vines erupt, then spring
-- up and loose an arrow into the sky.
function CastPoses.rangerSkyShot(char: Model?)
	local crouch = body(-40, 0, 46, 30, { RS = { 50, 0, 20 }, LS = { 35, 0, -45 }, N = { 12, 0, 0 } }, 16)
	CastPoses.play(char, {
		-- Hoist: bow raised overhead in both hands, rising on the toes.
		{ dur = 0.28, style = Enum.EasingStyle.Sine, pose = lift(body(14, 0, 6, 6,
			{ RS = { 170, 0, -10 }, LS = { 170, 0, 10 }, N = { 18, 0, 0 } }, 8), 0.2) },
		-- SMASH (impact at 0.36s).
		{ dur = 0.08, style = QUART, pose = crouch },
		-- Hold the crouch as the vines lash up round him, breathing hard.
		{ dur = 0.8, pose = crouch, wobble = function(t)
			local b = math.sin(t * 9) * 2
			return { W = { b, 0, 0 }, RS = { 0, 0, b } }
		end },
		-- Spring up and thrust the bow to the sky: the plant behind him spits
		-- the great arrow up (1.35s, RangerFlair)...
		{ dur = 0.14, style = Enum.EasingStyle.Back, pose = body(18, 0, 8, 8,
			{ LS = { 172, 0, -6 }, RS = { 35, 0, 30 }, N = { 30, 0, 0 } }, 8) },
		{ dur = 0.5, pose = body(18, 0, 8, 8, { LS = { 168, 0, -8 }, RS = { 30, 0, 32 }, N = { 32, 0, 0 } }, 8) },
	}, 0.3)
end

-- ── Ice Mage ────────────────────────────────────────────────────────────────
-- Upper body only (W, arms, head) except the floor slam: the skating layer
-- owns her legs while she moves.
function CastPoses.iceBolt(char: Model?)
	CastPoses.play(char, {
		-- Cocked: the casting hand drawn back by the ear, torso turned away.
		{ dur = 0.05, style = QUAD, pose = { RS = { 55, 0, 35 }, LS = { 20, 0, -15 }, W = { 0, -16, 0 }, N = { 0, 12, 0 } } },
		-- Flick: the right shoulder drives round and the arm snaps straight
		-- as the crystal leaves the fingertips.
		{ dur = 0.06, style = QUART, pose = { RS = { 92, 0, -8 }, LS = { -10, 0, -25 }, W = { -4, 14, 0 }, N = { 0, -8, 0 } } },
		{ dur = 0.1, pose = { RS = { 84, 0, -12 }, LS = { -5, 0, -20 }, W = { -2, 16, 0 }, N = { 0, -8, 0 } } },
	}, 0.22)
end

CastPoses.ICE_SPIKES_IMPACT = 0.16
function CastPoses.iceSpikes(char: Model?)
	CastPoses.play(char, {
		-- Rear up, frost gathering in the raised hand...
		{ dur = 0.1, style = QUAD, pose = lift(body(12, -15, 8, 8,
			{ RS = { 150, 0, 30 }, LS = { 30, 0, -40 }, N = { 12, 0, 0 } }, 8), 0.15) },
		-- ...then drop and slam the palm into the floor (impact at 0.16s).
		{ dur = 0.06, style = QUART, pose = body(-35, 5, 42, 30,
			{ RS = { -10, 0, 10 }, LS = { 20, 0, -55 }, N = { -6, 0, 0 } }, 12) },
		{ dur = 0.2, pose = body(-30, 5, 40, 28, { RS = { -8, 0, 10 }, LS = { 18, 0, -50 }, N = { -4, 0, 0 } }, 12) },
	}, 0.3)
	task.delay(CastPoses.ICE_SPIKES_IMPACT, CastPoses.hitStop, char, 0.05)
end

function CastPoses.iceBeam(char: Model?, duration: number)
	local hold = { RS = { 90, 0, -12 }, LS = { 90, 0, 12 }, W = { 8, 0, 0 }, N = { -4, 0, 0 } }
	CastPoses.play(char, {
		-- Palms cupping a charging orb at the right hip, the torso wound
		-- back to the right...
		{ dur = 0.1, style = QUAD, pose = { RS = { 25, 0, 10 }, LS = { 40, 0, 45 }, W = { 4, -30, 0 }, N = { 0, 20, 0 } } },
		-- ...and thrust straight out as the beam erupts.
		{ dur = 0.08, style = Enum.EasingStyle.Back, pose = hold },
		{ dur = math.max(duration - 0.18, 0.1), pose = hold, wobble = tremble(1.3, 44) },
	}, 0.28)
end

CastPoses.ICE_CLONE_SPAWN = 0.2
function CastPoses.iceClone(char: Model?)
	CastPoses.play(char, {
		-- Draw a crystal from the chest...
		{ dur = 0.12, pose = { LS = { 40, 0, 20 }, LE = { 110, 0, 0 }, RS = { 20, 0, 20 }, W = { 0, -20, 0 } } },
		-- ...and cast it outward where the clone forms (spawn at 0.2s).
		{ dur = 0.08, style = Enum.EasingStyle.Back, pose = { LS = { 95, 0, -30 }, LE = { 0, 0, 0 }, LW = { -35, 0, 0 }, RS = { 15, 0, 35 }, W = { -6, 22, 0 }, N = { 0, 15, 0 } } },
		{ dur = 0.3, pose = { LS = { 90, 0, -28 }, LW = { -30, 0, 0 }, RS = { 12, 0, 30 }, W = { -4, 18, 0 }, N = { 0, 12, 0 } } },
	})
end

-- "The frozen one" reveal (Blizzard wind-up, 1.5s): no reach — the mage just
-- stands there, squared up and still, head slightly lowered, breathing slow and
-- heavy. The head lifts to stare into the camera as the eyes flare (1.0s); at
-- the release (1.5s) the whole body tenses once as the storm breaks.
CastPoses.ICE_BLIZZARD_EYES = 1.0
CastPoses.ICE_BLIZZARD_RELEASE = 1.5
-- Hunched forward with the shoulders hiked, arms hanging forward so the hands
-- sit in front at waist height (legs compensate the lean to stay planted).
local MENACE = { N = { 4, 0, 0 }, W = { -16, 0, 0 }, RS = { 32, 0, 12 }, LS = { 32, 0, -12 }, RE = { 35, 0, 0 }, LE = { 35, 0, 0 },
	RH = { 16, 0, 5 }, LH = { 16, 0, -5 }, Root = { 0, 0, 0, 0, -0.1, 0 } }
function CastPoses.iceBlizzard(char: Model?)
	local stare = table.clone(MENACE)
	stare.N = { 12, 0, 0 } -- head up, glaring into the lens
	local tensed = table.clone(MENACE)
	tensed.N = { 14, 0, 0 }
	tensed.W = { -20, 0, 0 }
	tensed.RS, tensed.LS = { 40, 0, 26 }, { 40, 0, -26 } -- claws flare out
	tensed.RH, tensed.LH = { 20, 0, 9 }, { 20, 0, -9 }
	tensed.Root = { 0, 0, 0, 0, -0.2, 0 }
	local breathe = function(t: number): Pose
		local b = math.sin(t * 2.6) * 1.4
		return { W = { b, 0, 0 }, RS = { 0, 0, b * 0.6 }, LS = { 0, 0, -b * 0.6 } }
	end
	CastPoses.play(char, {
		{ dur = 0.3, style = Enum.EasingStyle.Sine, pose = MENACE },
		{ dur = 0.7, pose = MENACE, wobble = breathe },
		-- Eyes flare: the head comes up to stare into the lens.
		{ dur = 0.35, style = Enum.EasingStyle.Sine, pose = stare, wobble = breathe },
		{ dur = 0.07, pose = stare },
		-- Release: one hard flex of the whole body as the storm erupts.
		{ dur = 0.08, style = Enum.EasingStyle.Back, pose = tensed },
		{ dur = 0.45, pose = tensed },
	})
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Class-selection preview (and the summon reward's): each class makes an
-- entrance (a little piece of theatre in character), lands in its signature
-- pose, and then keeps living in it (breathing, shifting its weight, a
-- flourish now and then) until stopped. The poses replace whatever the rig is
-- animating (a held weapon's arm, the idle), so they read as authored.
-- Entrances that come in from the side come from the screen's right (the
-- caller passes the camera's right; without it, the model's own left). Each
-- entrance names its moments (`beats`, seconds from the start) for
-- UltPreviewFX to put its effects on: CastPoses.previewBeats(classId).
-- (The Fire Knight plays its uploaded ultimate animation instead.)
-- ═════════════════════════════════════════════════════════════════════════════
local SINE, BACK, LINEAR = Enum.EasingStyle.Sine, Enum.EasingStyle.Back, Enum.EasingStyle.Linear

-- ── Building blocks ─────────────────────────────────────────────────────────
-- (CastPoses blends each angle on its own: of the two ways to write a turn,
-- and whole turns either side, take the one nearest the rough angles.)
local function nearest(rx: number, ry: number, rz: number, guess: { number }): { number }
	local function near(a: number, ref: number): number
		return a + 360 * math.floor((ref - a) / 360 + 0.5)
	end
	local best: { number } = {}
	local bestD = math.huge
	for _, c in ipairs({ { rx, ry, rz }, { rx + 180, 180 - ry, rz + 180 } }) do
		local v = { near(c[1], guess[1]), near(c[2], guess[2]), near(c[3], guess[3]) }
		local d = math.abs(v[1] - guess[1]) + math.abs(v[2] - guess[2]) + math.abs(v[3] - guess[3])
		if d < bestD then best, bestD = v, d end
	end
	return best
end

-- An arm AIMED in the world ({ elev from hanging, 90 = level; yaw + = to his
-- left; out + = away from the body, - = across it }), turned back into
-- shoulder angles under the torso's lean and twist.
local function aimArm(lean: number, twist: number, aim: { number }, left: boolean?): { number }
	local out = if left then -(aim[3] or 0) else (aim[3] or 0)
	local world = CFrame.Angles(0, math.rad(aim[2] or 0), 0) * CFrame.Angles(math.rad(aim[1]), 0, 0) * CFrame.Angles(0, 0, math.rad(out))
	local torso = CFrame.fromEulerAnglesXYZ(math.rad(lean), math.rad(twist), 0)
	local rx, ry, rz = (torso:Inverse() * world):ToEulerAnglesXYZ()
	return nearest(math.deg(rx), math.deg(ry), math.deg(rz), { aim[1] - lean, (aim[2] or 0) - twist, out })
end

-- A grounded figure (CastPoses.body: left foot `front` forward, right foot
-- `back` back) with both arms aimed and the head on what's ahead.
local function figure(lean: number, twist: number, front: number, back: number, ra: { number }, la: { number }, look: number?,
	shiftZ: number?): Pose
	local p = CastPoses.body(lean, twist, front, back, nil, 7, 0, shiftZ)
	p.RS = aimArm(lean, twist, ra)
	p.LS = aimArm(lean, twist, la, true)
	p.N = { (look or 0) - lean * 0.6, -twist * 0.85, 0 }
	return p
end

-- `p` with some joints changed.
local function with(p: Pose, changes: Pose): Pose
	local out = table.clone(p)
	for k, v in pairs(changes) do out[k] = v end
	return out
end

-- `p` with one joint's angles moved by `d` (the arm's roll for a twirl, ...).
local function nudged(p: Pose, key: string, d: { number }): Pose
	local v = p[key] or { 0, 0, 0 }
	local out = table.clone(p)
	out[key] = { (v[1] or 0) + (d[1] or 0), (v[2] or 0) + (d[2] or 0), (v[3] or 0) + (d[3] or 0), v[4] or 0, v[5] or 0, v[6] or 0 }
	return out
end

-- `p` carried to `offset` (studs, the model's own space) and turned `yaw`
-- degrees (the whole body: an entrance from somewhere else).
local function placed(p: Pose, offset: Vector3, yaw: number?): Pose
	local r = p.Root or { 0, 0, 0, 0, 0, 0 }
	local out = table.clone(p)
	out.Root = { r[1] or 0, yaw or (r[2] or 0), r[3] or 0, (r[4] or 0) + offset.X, (r[5] or 0) + offset.Y, (r[6] or 0) + offset.Z }
	return out
end

-- The yaw that faces the body along `dir` (the model's own space).
local function yawFor(dir: Vector3): number
	return math.deg(math.atan2(-dir.X, -dir.Z))
end

-- A walking stride (for an entrance's wobble): legs and the free arm swinging,
-- a bob. `rate` radians a second, `stride` degrees.
local function stride(t: number, rate: number, deg: number, arms: boolean?): Pose
	local s = math.sin(t * rate)
	local p: Pose = { RH = { s * deg, 0, 0 }, LH = { -s * deg, 0, 0 },
		Root = { 0, 0, 0, 0, math.abs(math.cos(t * rate)) * 0.12, 0 } }
	if arms ~= false then p.LS = { s * deg * 0.6, 0, 0 } end
	return p
end

-- 0..1 now and then: every `period` seconds, rising over `up` from `at`,
-- held `hold`, settling back over `down`.
local function beat(t: number, period: number, at: number, up: number, hold: number, down: number): number
	local u = (t % period) - at
	if u < 0 then return 0 end
	if u < up then return math.sin(u / up * math.pi / 2) end
	u -= up
	if u < hold then return 1 end
	u -= hold
	if u < down then return math.cos(u / down * math.pi / 2) end
	return 0
end

-- ── The signature poses ─────────────────────────────────────────────────────
local GUNSLINGER_POSE: Pose = { RS = { 90, 0, 0 }, LS = { 42, 0, 28 }, LE = { 30, 0, 0 },
	W = { 0, -18, 0 }, N = { -10, 16, 0 }, RH = { 6, 0, 10 }, LH = { -6, 0, -10 } }
-- (en garde: SwordsmanController's fencer(-3, 60, 22, 26, 0.1, { 90, 0, 0 }, { 150, 10, 15 }))
local SWORDSMAN_POSE: Pose = (function(): Pose
	local p = CastPoses.body(-3, 60, -26, -22, nil, 7, 0, 0.1)
	p.RS, p.LS, p.N = aimArm(-3, 60, { 90, 0, 0 }), aimArm(-3, 60, { 150, 10, 15 }, true), { 1.8, -51, 0 }
	return p
end)()
local ROGUE_POSE: Pose = { Root = { 0, 0, 0, 0, -0.7, 0 }, W = { -24, 28, 0 }, N = { -14, -24, 0 },
	RS = { 62, 0, 22 }, RE = { 55, 0, 0 }, LS = { -28, 0, -48 }, LE = { 40, 0, 0 },
	RH = { -32, 0, 8 }, LH = { 34, 0, -10 }, RK = { 40, 0, 0 }, LK = { 55, 0, 0 } }
local MAGE_POSE: Pose = { W = { 6, -12, 0 }, N = { -12, 10, 0 }, RS = { 150, 0, 28 }, LS = { 30, 0, -32 },
	RH = { 4, 0, 9 }, LH = { -4, 0, -9 } }
local BERSERKER_POSE: Pose = { Root = { 0, 0, 0, 0, -0.35, 0 }, W = { -18, -22, 0 }, N = { 14, 18, 0 },
	RS = { -12, 0, 50 }, LS = { 38, 0, -32 }, RH = { 18, 0, 14 }, LH = { -16, 0, -14 } }
-- The Martial Artist's guard: a front stance, left foot and left fist leading
-- at shoulder height, the right fist held in front of the chest.
local KARATE_POSE: Pose = figure(-6, -20, 28, 26, { 55, 14, -28 }, { 82, 6, -10 }, 2)
-- The Cleric standing composed, the scepter held upright before him in both
-- hands: the fists side by side at his belly, just right of centre (so the
-- scepter, leaning a touch outward, stands beside his face, not over it).
local SCEPTER_POSE: Pose = { W = { 2, 0, 0 }, N = { 4, 0, 0 }, RS = { 60, 0, -40 }, LS = { 55, 0, 60 },
	RH = { 0, 0, 3 }, LH = { 0, 0, -3 } }
-- The Ranger low and side on, the bow held out level, arrows drawn to the
-- cheek; `yaw` turns the aim (and her head) left (+) or right.
local function rangerAim(yaw: number): Pose
	local twist = -62 + yaw * 0.6
	local p = figure(-10, twist, 30, 30, { 95, 52 + yaw, 0 }, { 92, yaw - 4, 0 }, 4)
	p.N = { 8, (yaw - twist) * 0.95, 0 }
	return p
end
local RANGER_POSE: Pose = rangerAim(0)

type Preview = { intro: { Stage }, pose: Pose, idle: (number) -> Pose, beats: { [string]: number }? }
-- (an entrance from the side is built from where the screen's right is, in
-- the model's own space: `right`, and `toward` the camera)
type PreviewCtx = { right: Vector3, toward: Vector3 }
local PREVIEWS: { [string]: Preview | (PreviewCtx) -> Preview } = {}

-- ── Martial Artist ──────────────────────────────────────────────────────────
-- He steps forward and plants his feet (black ink bursting off the floor as
-- he lands it, crimson energy kindling round his fists), raises his fists into
-- his guard, and settles it with one small, controlled adjustment. He holds it,
-- breathing; now and then a sharp kiai tightens everything.
PREVIEWS.martial_artist = (function(): Preview
	local relaxed: Pose = { Root = { 0, 0, 0, 0, 0, 2.5 }, RS = { 6, 0, 6 }, LS = { 6, 0, -6 } }
	local striding: Pose = { Root = { 0, 0, 0, 0, -0.05, 1.2 }, LH = { 28, 0, -4 }, RH = { -18, 0, 4 }, RS = { -12, 0, 6 }, LS = { 16, 0, -6 } }
	local planted = figure(-4, -16, 26, 24, { 12, 0, 10 }, { 12, 0, -10 }, 0)
	local raised = figure(-7, -26, 28, 26, { 50, 18, -30 }, { 78, 12, -8 }, 0)
	return {
		intro = {
			{ dur = 0.3, style = SINE, pose = relaxed },
			{ dur = 0.25, style = SINE, pose = striding },
			{ dur = 0.2, style = QUART, pose = planted },
			{ dur = 0.3, style = BACK, pose = raised },
			{ dur = 0.35, style = SINE, pose = KARATE_POSE },
		},
		pose = KARATE_POSE,
		beats = { ink = 0.75, fists = 0.75 },
		idle = function(t)
			local kiai = beat(t, 5, 2.5, 0.06, 0.15, 0.35)
			local b = math.sin(t * 1.7)
			return {
				W = { b * 1.1, 0, 0 },
				RS = { b - 5 * kiai, 0, 0 },
				LS = { math.sin(t * 1.7 + 1) + 4 * kiai, 0, 0 },
				N = { -4 * kiai, 0, 0 },
			}
		end,
	}
end)()

-- ── Rogue ───────────────────────────────────────────────────────────────────
-- Smoke bursts across the platform; he rises out of it in a crouch and steps
-- clear, flicks his dagger up into the air, crosses and uncrosses his hands in
-- a quick trick while it spins, catches it (UltPreviewFX flies the dagger) and
-- drops into his crouch. His weight shifts side to side, his eyes scan, and now
-- and then the dagger flips over in his hand (UltPreviewFX turns it).
PREVIEWS.rogue = (function(): Preview
	local hidden: Pose = { Root = { 0, 0, 0, 0, -1.1, 1.5 }, W = { -30, 0, 0 }, N = { -10, 0, 0 }, RS = { 20, 0, 10 }, LS = { 20, 0, -10 },
		RH = { 55, 0, 6 }, LH = { 20, 0, -6 } }
	local risen: Pose = { Root = { 0, 0, 0, 0, 0, 0.4 }, W = { -4, 10, 0 }, N = { 0, -8, 0 }, RS = { 30, 0, 8 }, LS = { 12, 0, -10 },
		RH = { 8, 0, 4 }, LH = { -6, 0, -4 } }
	return {
		intro = {
			{ dur = 0.05, pose = hidden },
			{ dur = 0.45, pose = hidden },
			{ dur = 0.45, style = SINE, pose = risen },
			{ dur = 0.12, style = QUAD, pose = with(risen, { RS = { 10, 0, 10 }, N = { 4, -8, 0 } }) },
			{ dur = 0.1, style = QUART, pose = with(risen, { RS = { 160, 0, 8 }, N = { 18, -6, 0 } }) },
			{ dur = 0.18, style = QUAD, pose = with(risen, { RS = { 65, 0, -50 }, LS = { 65, 0, 50 }, N = { 26, 0, 0 } }) },
			{ dur = 0.18, style = QUAD, pose = with(risen, { RS = { 70, 0, 25 }, LS = { 70, 0, -25 }, N = { 22, 0, 0 } }) },
			{ dur = 0.14, style = SINE, pose = with(risen, { RS = { 135, 0, 5 }, LS = { 20, 0, -12 }, N = { 16, 0, 0 } }) },
			{ dur = 0.28, style = BACK, pose = ROGUE_POSE },
		},
		pose = ROGUE_POSE,
		-- (from `idle` the dagger flips every 4.5 s, 2.5 s in, over 0.4 s)
		beats = { smoke = 0, toss = 1.12, catch = 1.67, idle = 1.95 },
		idle = function(t)
			local shift = math.sin(t * 1.3)
			return {
				Root = { 0, 0, 0, shift * 0.15, math.sin(t * 2.6) * 0.04, 0 },
				W = { math.sin(t * 2) * 1, shift * 4, 0 },
				N = { 0, math.sin(t * 0.8) * 12, 0 },
			}
		end,
	}
end)()

-- ── Mage ────────────────────────────────────────────────────────────────────
-- He floats down from above with his spellbook beside him, arms a little out,
-- watching the ground come up; lands softly on the platform (a rune flashing
-- out round his feet), straightens, and raises his hand as the book flares.
-- The raised hand slowly circles; every few seconds a pulse of power.
PREVIEWS.mage = (function(): Preview
	local high: Pose = { Root = { 0, 0, 0, 0, 16, 0 }, W = { 6, 0, 0 }, N = { -20, 0, 0 }, RS = { 30, 0, 35 }, LS = { 30, 0, -35 },
		RH = { -6, 0, 4 }, LH = { 4, 0, -4 } }
	return {
		intro = {
			{ dur = 0.05, pose = high },
			{ dur = 1.2, pose = with(high, { Root = { 0, 0, 0, 0, 2.2, 0 }, N = { -12, 0, 0 }, RS = { 22, 0, 28 }, LS = { 22, 0, -28 } }) },
			{ dur = 0.5, style = SINE, pose = { Root = { 0, 0, 0, 0, -0.35, 0 }, W = { -10, 0, 0 }, N = { -8, 0, 0 }, RS = { 18, 0, 22 },
				LS = { 18, 0, -22 }, RH = { 10, 0, 3 }, LH = { 10, 0, -3 } } },
			{ dur = 0.4, style = SINE, pose = { RS = { 8, 0, 8 }, LS = { 8, 0, -8 } } },
			{ dur = 0.35, style = BACK, pose = MAGE_POSE },
		},
		pose = MAGE_POSE,
		beats = { descend = 0, land = 1.75, open = 2.3 },
		idle = function(t)
			local push = beat(t, 5, 2.5, 0.12, 0.15, 0.5)
			return {
				W = { math.sin(t * 1.8) * 1.2 - 3 * push, 0, 0 },
				N = { 4 * push, 0, 0 },
				RS = { math.sin(t * 1.6) * 5 + 8 * push, 0, math.cos(t * 1.6) * 5 },
				LS = { 0, 0, -15 * push },
			}
		end,
	}
end)()

-- ── Gunslinger ──────────────────────────────────────────────────────────────
-- He walks in from the right, unhurried, the revolver spinning round his finger
-- down by his hip (UltPreviewFX spins the gun in his hand; the arm stays put);
-- stops in the middle, turns to face front, catches it (a glint) and settles
-- into High Noon. Every so often he fans the hammer (or the gun twirls again).
local GS = { walk = 2.2, dist = 11 }
PREVIEWS.gunslinger = function(ctx: PreviewCtx): Preview
	local yawW = yawFor(-ctx.right)
	local walking: Pose = { RS = { 30, 0, 8 }, LS = { 0, 0, -6 }, N = { -12, 0, 0 } }
	local standing: Pose = { RS = { 40, 0, 8 }, LS = { 6, 0, -6 }, N = { -14, 0, 0 } }
	return {
		intro = {
			{ dur = 0.05, pose = placed(walking, ctx.right * GS.dist, yawW) },
			{ dur = GS.walk, style = LINEAR, pose = placed(walking, Vector3.zero, yawW), wobble = function(t)
				return stride(math.max(t - 0.05, 0), 7, 26)
			end },
			{ dur = 0.3, style = SINE, pose = standing },
			{ dur = 0.08, pose = with(standing, { RS = { 48, 0, 8 } }) },
			{ dur = 0.3, style = BACK, pose = GUNSLINGER_POSE },
		},
		pose = GUNSLINGER_POSE,
		-- (the gun spins from `walk` till `catch`; from `idle` it twirls now and
		-- then, on the same 6 s round as the hammer fanning)
		beats = { walk = 0.05, catch = 0.05 + GS.walk + 0.3, idle = 0.05 + GS.walk + 0.3 + 0.08 + 0.3 },
		idle = function(t)
			-- fanning the hammer: three slaps of the off hand, the gun kicking with each
			local fan = beat(t, 6, 1.8, 0.04, 0.02, 0.08) + beat(t, 6, 1.95, 0.04, 0.02, 0.08) + beat(t, 6, 2.1, 0.04, 0.02, 0.08)
			return {
				W = { math.sin(t * 2) * 1, math.sin(t * 0.7) * 3, 0 },
				N = { 0, 0, math.sin(t * 0.5) * 3 },
				RS = { 9 * fan + math.sin(t * 1.3) * 1.5, 0, 0 },
				LS = { 22 * fan, 0, 0 },
			}
		end,
	}
end

-- ── Ranger ──────────────────────────────────────────────────────────────────
-- She leaps in from the left, facing the way she's going, and lands low
-- (leaves scattering); reaches over her shoulder for three arrows (they glow
-- green in her hand), raises the bow and draws them onto it (UltPreviewFX lays
-- them on), aiming off to the screen's right, her chest to you; slowly scans
-- left... and right for a target, then holds her aim. The string trembles; the
-- aim drifts a little.
PREVIEWS.ranger = function(ctx: PreviewCtx): Preview
	-- (a right-handed archer's chest faces a quarter turn right of her aim: aim
	-- off to the screen's right, a little toward the camera, and it's hers you see)
	local yawJ = yawFor(ctx.right)
	local yawA = yawJ - 12
	local function facing(p: Pose): Pose return placed(p, Vector3.zero, yawA) end
	local tucked: Pose = { W = { -10, 0, 0 }, N = { -10, 0, 0 }, RS = { 40, 0, 40 }, LS = { 60, 0, -30 }, RH = { 50, 0, 6 }, LH = { 20, 0, -6 } }
	local landed = placed(figure(-22, 0, 30, 34, { 30, 0, 40 }, { 60, 0, -30 }, -6), Vector3.new(0, -0.4, 0), yawJ)
	local crouched = facing(figure(-14, -20, 28, 30, { 25, 0, 20 }, { 55, 0, -20 }, 0))
	local aim = facing(RANGER_POSE)
	return {
		intro = {
			{ dur = 0.05, pose = placed(tucked, -ctx.right * 9 + Vector3.new(0, 5, 0), yawJ) },
			{ dur = 0.3, pose = placed(with(tucked, { RH = { 75, 0, 6 }, LH = { 55, 0, -6 } }), -ctx.right * 4 + Vector3.new(0, 6, 0), yawJ) },
			{ dur = 0.28, style = QUART, pose = landed },
			{ dur = 0.22, style = SINE, pose = crouched },
			{ dur = 0.3, style = QUAD, pose = with(crouched, { RS = aimArm(-14, -20, { 205, 0, 20 }), N = { 10, 30, 0 } }) },
			{ dur = 0.35, style = SINE, pose = aim },
			{ dur = 0.9, style = SINE, pose = facing(rangerAim(22)) },
			{ dur = 1.1, style = SINE, pose = facing(rangerAim(-26)) },
			{ dur = 0.6, style = SINE, pose = aim },
		},
		pose = aim,
		-- (`arrows`: drawn from the quiver into her hand; `nock`: laid on the bow)
		beats = { land = 0.63, arrows = 1.15, nock = 1.3 },
		idle = function(t)
			local drift = math.sin(t * 0.6)
			return {
				W = { math.sin(t * 2) * 1, drift * 3, 0 },
				RS = { math.sin(t * 31) * 0.5, 0, math.cos(t * 27) * 0.4 },
				LS = { math.sin(t * 2) * 0.6, 0, 0 },
			}
		end,
	}
end

-- ── Cleric ──────────────────────────────────────────────────────────────────
-- He kneels, head bowed in prayer; golden light comes down round him and a
-- scepter forms in it, hanging in the air before him. He slowly rises, reaches
-- out and takes it (UltPreviewFX puts it in his hand), and holds it upright in
-- both hands, composed. He breathes; now and then he lifts his eyes.
PREVIEWS.cleric = (function(): Preview
	local kneel = CastPoses.kneelOnOneKnee(-22)
	kneel.N = { -36, 0, 0 }
	kneel.RS, kneel.LS = { 102, 0, -36 }, { 102, 0, 36 }
	kneel.RE, kneel.LE = { 115, 0, 0 }, { 115, 0, 0 }
	local standing: Pose = { N = { 6, 0, 0 }, RS = { 20, 0, -14 }, LS = { 20, 0, 14 }, RH = { 0, 0, 3 }, LH = { 0, 0, -3 } }
	return {
		intro = {
			{ dur = 0.45, style = SINE, pose = kneel },
			{ dur = 1.2, pose = kneel, wobble = function(t) return { W = { math.sin(t * 2) * 1.2, 0, 0 } } end },
			{ dur = 0.9, style = SINE, pose = standing },
			{ dur = 0.4, style = SINE, pose = with(standing, { RS = { 80, 0, -36 }, N = { 0, 0, 0 } }) },
			{ dur = 0.35, style = SINE, pose = SCEPTER_POSE },
		},
		pose = SCEPTER_POSE,
		beats = { light = 0.5, scepter = 1.3, grab = 2.95 },
		idle = function(t)
			local up = beat(t, 6, 2, 0.7, 0.9, 0.9)
			local b = math.sin(t * 1.8)
			return {
				W = { b * 1.2, 0, 0 },
				N = { 26 * up, 0, 0 },
				RS = { b * 0.8, 0, 0 },
				LS = { b * 0.8, 0, 0 },
			}
		end,
	}
end)()

-- ── Ice Mage ────────────────────────────────────────────────────────────────
-- Frozen enemies stand round the platform (UltPreviewFX). She walks in from the
-- right, calm and unhurried, between them, frost trailing behind her and ice
-- spreading over each as she passes, stops in the middle and turns to face you.
-- Her head tilts slowly; her hands flex now and then.
local ICE = { walk = 3, dist = 12 }
PREVIEWS.ice_mage = function(ctx: PreviewCtx): Preview
	local yawW = yawFor(-ctx.right)
	local yawT = yawFor(ctx.toward)
	local walking: Pose = { W = { -2, 0, 0 }, N = { -6, 0, 0 }, RS = { 14, 0, 14 }, LS = { 14, 0, -14 } }
	local facing = placed(MENACE, Vector3.zero, yawT)
	return {
		intro = {
			{ dur = 0.05, pose = placed(walking, ctx.right * ICE.dist, yawW) },
			{ dur = ICE.walk, style = LINEAR, pose = placed(walking, Vector3.zero, yawW), wobble = function(t)
				return stride(math.max(t - 0.05, 0), 5.2, 18, false)
			end },
			{ dur = 0.45, style = SINE, pose = facing },
		},
		pose = facing,
		beats = { walk = 0.05, arrive = 0.05 + ICE.walk },
		idle = function(t)
			local b = math.sin(t * 2.6) * 1.4
			local flex = beat(t, 4, 1.2, 0.18, 0.25, 0.4)
			return {
				W = { b, 0, 0 },
				N = { 0, 0, math.sin(t * 0.7) * 8 },
				RS = { 0, 0, b * 0.6 + 10 * flex },
				LS = { 0, 0, -b * 0.6 - 10 * flex },
			}
		end,
	}
end
-- (how far she walks and in how long: UltPreviewFX times the ice to it)
CastPoses.ICE_WALK = ICE

-- ── Sword Master ────────────────────────────────────────────────────────────
-- A duelist's salute (standing tall, the blade raised straight up before his
-- face, then swept down and out to the side), then he drops into en garde. He
-- keeps light on his feet, the point making small circles; every few seconds a
-- feint.
PREVIEWS.swordsman = (function(): Preview
	local rest: Pose = { RS = { 22, 0, 10 }, LS = { 10, 0, -10 }, N = { -20, 0, 0 } }
	local salute: Pose = { RS = { 165, 0, -20 }, LS = { 8, 0, -8 }, N = { -6, 0, 0 } }
	return {
		intro = {
			{ dur = 0.4, style = SINE, pose = rest },
			{ dur = 0.4, style = SINE, pose = salute },
			{ dur = 0.3, pose = salute },
			{ dur = 0.25, style = QUAD, pose = { RS = { 35, 0, 42 }, LS = { 8, 0, -8 }, N = { -12, 0, 0 } } },
			{ dur = 0.3, style = BACK, pose = SWORDSMAN_POSE },
		},
		pose = SWORDSMAN_POSE,
		idle = function(t)
			local feint = beat(t, 4, 2, 0.07, 0.06, 0.25)
			return {
				Root = { 0, 0, 0, 0, math.abs(math.sin(t * 4.5)) * 0.1 - 0.05, -0.35 * feint },
				W = { math.sin(t * 2) * 0.8, 6 * feint, 0 },
				RS = { math.sin(t * 3) * 3 - 6 * feint, 0, math.cos(t * 3) * 3 },
			}
		end,
	}
end)()

-- ── Berserker ───────────────────────────────────────────────────────────────
-- After the storyboard. He walks in from the right, slow and heavy, hunched,
-- the greatsword dragging behind him (UltPreviewFX lays the blade back along
-- the floor, sparks scraping off its point); stops in the middle and turns to
-- face you; throws his arms wide and roars, shaking with it, red energy
-- bursting round him; then the change takes him and he doubles over, and his
-- body tears open into the beast (UltPreviewFX dresses it and the beast's own
-- body takes over: low on all fours as it changes, then up into its stance).
-- (Without UltPreviewFX, the summon reward's, he settles into his stance.)
local BR = { walk = 2.6, dist = 10 }
PREVIEWS.berserker = function(ctx: PreviewCtx): Preview
	local yawW = yawFor(-ctx.right)
	local trudge: Pose = { W = { -14, 0, 0 }, N = { 10, 0, 0 }, RS = { -16, 0, 10 }, LS = { 6, 0, -8 } }
	local halt: Pose = { Root = { 0, 0, 0, 0, -0.1, 0 }, W = { -16, 0, 0 }, N = { 12, 0, 0 }, RS = { -10, 0, 12 }, LS = { 14, 0, -12 },
		RH = { 6, 0, 8 }, LH = { 6, 0, -8 } }
	local roar: Pose = { Root = { 0, 0, 0, 0, -0.15, 0.15 }, W = { 16, 0, 0 }, N = { 12, 0, 0 }, RS = { 22, 0, 82 }, LS = { 22, 0, -82 },
		RH = { -4, 0, 14 }, LH = { -4, 0, -14 } }
	local doubled: Pose = { Root = { 0, 0, 0, 0, -0.6, 0.1 }, W = { -45, 0, 0 }, N = { 30, 0, 0 }, RS = { 60, 0, -25 }, LS = { 60, 0, 25 },
		RH = { 25, 0, 10 }, LH = { 25, 0, -10 } }
	-- (the whole body shaking with the roar)
	local function shaking(t: number): Pose
		local a, b = math.sin(t * 43) * 3, math.sin(t * 37 + 1) * 3
		return { W = { a * 0.5, b * 0.6, 0 }, N = { b, a, 0 }, RS = { a, 0, b }, LS = { b, 0, a } }
	end
	local halted = 0.05 + BR.walk
	local roared = halted + 0.45 + 0.25
	return {
		intro = {
			{ dur = 0.05, pose = placed(trudge, ctx.right * BR.dist, yawW) },
			{ dur = BR.walk, style = LINEAR, pose = placed(trudge, Vector3.zero, yawW), wobble = function(t)
				local u = math.max(t - 0.05, 0)
				local p = stride(u, 4.6, 20, false)
				-- the free arm swings; the shoulders roll under the weight
				p.LS = { math.sin(u * 4.6) * 14, 0, 0 }
				p.W = { 0, math.sin(u * 4.6) * 6, 0 }
				return p
			end },
			{ dur = 0.45, style = SINE, pose = halt },
			{ dur = 0.25, pose = halt },
			{ dur = 0.18, style = BACK, pose = roar },
			{ dur = 0.85, pose = roar, wobble = shaking },
			{ dur = 0.3, style = QUART, pose = doubled, wobble = shaking },
		},
		pose = BERSERKER_POSE,
		-- (`walk`: the sword drags; `halt`: he stops; `roar`: the arms fly open;
		-- `change`: the beast)
		beats = { walk = 0.05, halt = halted, roar = roared, change = roared + 0.18 + 0.85 + 0.3 },
		idle = function(t)
			local snarl = beat(t, 5, 2.5, 0.08, 0.35, 0.3)
			return {
				W = { math.sin(t * 1.6) * 3, 0, 0 },
				N = { -8 * snarl, math.sin(t * 0.6) * 4, math.sin(t * 30) * 4 * snarl },
				LS = { math.sin(t * 25) * 0.8 + 4 * snarl, 0, 0 },
			}
		end,
	}
end

local function resolvePreview(classId: string, ctx: PreviewCtx): Preview?
	local def = PREVIEWS[classId]
	if type(def) == "function" then return def(ctx) end
	return def :: Preview?
end

-- Where the screen's right is, and toward the camera, in `root`'s own space
-- (`right`: the camera's right in the world; without it, the model's left).
local function previewCtx(root: BasePart?, right: Vector3?): PreviewCtx
	local r = Vector3.new(-1, 0, 0)
	if root and right then
		local l = root.CFrame:VectorToObjectSpace(right)
		l = Vector3.new(l.X, 0, l.Z)
		if l.Magnitude > 0.01 then r = l.Unit end
	end
	return { right = r, toward = r:Cross(Vector3.yAxis) }
end

-- The entrance's moments for `classId` (seconds from the start; empty if none).
function CastPoses.previewBeats(classId: string): { [string]: number }
	local def = resolvePreview(classId, previewCtx(nil, nil))
	return if def and def.beats then def.beats else {}
end

export type PreviewOptions = { right: Vector3? }

function CastPoses.holdUltPreview(char: Model?, classId: string, opts: PreviewOptions?): boolean
	if not char then return false end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local def = resolvePreview(classId, previewCtx(root, opts and opts.right))
	if not def then return false end
	local stages = table.clone(def.intro)
	local introLen = 0
	for _, st in ipairs(stages) do introLen += st.dur end
	-- held, alive, until CastPoses.stop
	local idle = def.idle
	table.insert(stages, { dur = 1e6, pose = def.pose, wobble = function(t: number)
		return idle(math.max(t - introLen, 0))
	end })
	CastPoses.play(char, stages, nil, true)
	return true
end

return CastPoses
