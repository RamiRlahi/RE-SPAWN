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
		-- Hold the crouch as the vines spiral up, breathing hard.
		{ dur = 0.49, pose = crouch, wobble = function(t)
			local b = math.sin(t * 9) * 2
			return { W = { b, 0, 0 }, RS = { 0, 0, b } }
		end },
		-- Spring up and draw skyward (the draw hand pulled in under the bow)...
		{ dur = 0.07, style = Enum.EasingStyle.Back, pose = body(22, -15, 10, 8,
			{ LS = { 155, 0, -10 }, RS = { 140, 0, -15 }, N = { 30, -10, 0 } }, 8) },
		-- ...and loose (0.95s): the draw hand snaps back and out.
		{ dur = 0.05, style = Enum.EasingStyle.Back, pose = body(26, -18, 10, 8,
			{ LS = { 155, 0, -10 }, RS = { 100, 0, 60 }, N = { 32, -10, 0 } }, 8) },
		{ dur = 0.3, pose = body(18, -12, 8, 6, { LS = { 130, 0, -8 }, RS = { 70, 0, 45 }, N = { 25, -8, 0 } }, 8) },
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
-- Class-selection preview: hold each class's ultimate pose until stopped.
-- (Heavy Knight uses its uploaded ult animation instead.)
-- ═════════════════════════════════════════════════════════════════════════════
local ULT_PREVIEW_POSES: { [string]: Pose } = {
	-- Rain of Arrows: bow raised to the sky at full draw.
	ranger = { LS = { 155, 0, -10 }, LE = { 5, 0, 0 }, RS = { 125, 0, 30 }, RE = { 125, 0, 0 },
		W = { 22, -15, 0 }, N = { 30, -10, 0 }, RH = { 14, 0, 6 }, LH = { -8, 0, -6 } },
	-- Divine Ascent: kneeling in prayer, hands clasped at the chin.
	cleric = (function(): Pose
		local p = CastPoses.kneelOnOneKnee(-22)
		p.N = { -36, 0, 0 }
		p.RS, p.LS = { 102, 0, -36 }, { 102, 0, 36 }
		p.RE, p.LE = { 115, 0, 0 }, { 115, 0, 0 }
		return p
	end)(),
	-- Blizzard: standing still and menacing, staring ahead.
	ice_mage = MENACE,
	-- High Noon: revolver arm straight out, off hand hovering over the hammer,
	-- chin down under the hat brim, feet planted wide.
	gunslinger = { RS = { 90, 0, 0 }, LS = { 42, 0, 28 }, LE = { 30, 0, 0 },
		W = { 0, -18, 0 }, N = { -10, 16, 0 }, RH = { 6, 0, 10 }, LH = { -6, 0, -10 } },
	-- Blade Storm: the sword planted point-down in front (ClassSelectionScreen
	-- stands it there), both hands folded on the hilt, looking straight ahead, feet
	-- together. The arms are aimed so the hands meet at the grip.
	swordsman = { RS = { 67.9, -4, -42.8 }, LS = { 67.9, 4, 42.8 },
		W = { -4, 0, 0 }, N = { 4, 0, 0 } },
}

function CastPoses.holdUltPreview(char: Model?, classId: string): boolean
	local pose = ULT_PREVIEW_POSES[classId]
	if not char or not pose then return false end
	CastPoses.play(char, {
		{ dur = 0.35, style = Enum.EasingStyle.Back, pose = pose },
		{ dur = 1e6, pose = pose }, -- held until CastPoses.stop
	})
	return true
end

return CastPoses
