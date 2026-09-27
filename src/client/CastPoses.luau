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

-- Pose value: { rx, ry, rz [, px, py, pz] } in degrees / studs.
-- +rx on a shoulder raises the arm forward; +rz raises the right arm sideways
-- (use -rz for the left arm); -rx on the waist leans forward.
type Pose = { [string]: { number } }
type Stage = { dur: number, pose: Pose, style: Enum.EasingStyle?, wobble: ((t: number) -> Pose)? }

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

-- Active sequence per character.
local active: { [Model]: any } = {}
local conn: RBXScriptConnection? = nil

local function ease(style: Enum.EasingStyle, a: number): number
	if style == Enum.EasingStyle.Back then
		local c1, c3 = 1.70158, 2.70158
		return 1 + c3 * (a - 1) ^ 3 + c1 * (a - 1) ^ 2
	elseif style == Enum.EasingStyle.Linear then
		return a
	elseif style == Enum.EasingStyle.Sine then
		return -(math.cos(math.pi * a) - 1) / 2
	end
	return 1 - (1 - a) ^ 3 -- Cubic out: snappy attack, soft settle
end

local function step()
	local now = os.clock()
	for char, seqState in pairs(active) do
		if not char.Parent then
			active[char] = nil
			continue
		end
		local stages: { Stage } = seqState.stages
		local elapsed = now - seqState.t0
		-- Find current stage.
		local acc = 0
		local idx = #stages
		for i, st in ipairs(stages) do
			if elapsed < acc + st.dur then
				idx = i
				break
			end
			acc += st.dur
			if i == #stages then acc -= st.dur end
		end
		local st = stages[idx]
		local a = math.clamp((elapsed - acc) / math.max(st.dur, 1e-3), 0, 1)
		local e = ease(st.style or Enum.EasingStyle.Cubic, a)
		local from: Pose = idx > 1 and stages[idx - 1].pose or seqState.fromPose
		local to: Pose = st.pose
		local wob: Pose? = st.wobble and st.wobble(elapsed) or nil

		local combined: { [Motor6D]: CFrame } = {}
		local current: Pose = {}
		for key, m in pairs(seqState.motors) do
			local cf = poseCF(from[key]):Lerp(poseCF(to[key]), e)
			if wob and wob[key] then cf *= poseCF(wob[key]) end
			-- Remember the blended value so an interrupting sequence starts from here.
			local rx, ry, rz = cf:ToEulerAnglesXYZ()
			current[key] = { math.deg(rx), math.deg(ry), math.deg(rz), cf.X, cf.Y, cf.Z }
			-- Character-space offset → motor C0 space.
			local local_ = m.basis:Inverse() * cf * m.basis
			combined[m.motor] = (combined[m.motor] or CFrame.identity) * local_
		end
		seqState.current = current
		for motor, cf in pairs(combined) do
			motor.Transform = motor.Transform * cf
		end

		if elapsed >= seqState.total then
			active[char] = nil
		end
	end
	if next(active) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

function CastPoses.play(char: Model?, stages: { Stage })
	if not char then return end
	local prev = active[char]
	local seqStages = table.clone(stages)
	table.insert(seqStages, { dur = 0.22, pose = {}, style = Enum.EasingStyle.Sine })
	local total = 0
	for _, st in ipairs(seqStages) do total += st.dur end
	active[char] = {
		t0 = os.clock(),
		stages = seqStages,
		total = total,
		fromPose = prev and prev.current or {},
		motors = prev and prev.motors or resolveMotors(char),
	}
	if not conn then
		-- Stepped runs after the Animator has applied this frame's tracks.
		conn = RunService.Stepped:Connect(step)
	end
end

function CastPoses.stop(char: Model?)
	if char and active[char] then
		local cur = active[char].current or {}
		CastPoses.play(char, { { dur = 0.01, pose = cur } })
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Pose library
-- ═════════════════════════════════════════════════════════════════════════════
local function tremble(amount: number, speed: number)
	return function(t: number): Pose
		local s = math.sin(t * speed) * amount
		local c = math.cos(t * speed * 1.3) * amount
		return { RS = { s, 0, c }, LS = { -s, 0, -c }, W = { c * 0.4, 0, 0 } }
	end
end

-- ── Cleric ──────────────────────────────────────────────────────────────────
function CastPoses.clericSmite(char: Model?)
	CastPoses.play(char, {
		-- Wind up: scepter hand drawn high and back, torso coils.
		{ dur = 0.07, pose = { RS = { 150, 0, 25 }, RE = { 30, 0, 0 }, W = { 8, 20, 0 }, N = { 0, -12, 0 } } },
		-- Sweep: arm cuts forward across the body as the smite leaves.
		{ dur = 0.09, style = Enum.EasingStyle.Back, pose = { RS = { 80, 0, -20 }, RE = { 5, 0, 0 }, W = { -10, -25, 0 }, N = { 0, 15, 0 }, LS = { 20, 0, -15 } } },
		{ dur = 0.12, pose = { RS = { 70, 0, -15 }, W = { -6, -18, 0 }, N = { 0, 10, 0 }, LS = { 15, 0, -12 } } },
	})
end

function CastPoses.clericHeal(char: Model?)
	CastPoses.play(char, {
		-- Hand to heart, gathering light.
		{ dur = 0.12, pose = { RS = { 40, 0, -30 }, RE = { 95, 0, 0 }, LS = { 10, 0, -10 }, N = { -10, 0, 0 } } },
		-- Open palm offered toward the ally.
		{ dur = 0.14, style = Enum.EasingStyle.Back, pose = { RS = { 95, 0, 5 }, RE = { 10, 0, 0 }, RW = { -30, 0, 0 }, LS = { 25, 0, -20 }, LE = { 30, 0, 0 }, W = { -6, 0, 0 } } },
		{ dur = 0.2, pose = { RS = { 90, 0, 5 }, RE = { 12, 0, 0 }, RW = { -30, 0, 0 }, LS = { 20, 0, -18 }, W = { -4, 0, 0 } } },
	})
end

function CastPoses.clericBeam(char: Model?, duration: number)
	local hold = { RS = { 92, 0, -8 }, LS = { 92, 0, 8 }, RE = { 8, 0, 0 }, LE = { 8, 0, 0 }, RW = { -45, 0, 0 }, LW = { -45, 0, 0 },
		W = { 10, 0, 0 }, Root = { 0, 0, 0, 0, -0.25, 0 }, RH = { 18, 0, 0 }, LH = { -8, 0, 0 }, RK = { -20, 0, 0 } }
	CastPoses.play(char, {
		-- Draw both hands to the chest, then thrust them out as the beam fires.
		{ dur = 0.12, pose = { RS = { 50, 0, -35 }, LS = { 50, 0, 35 }, RE = { 90, 0, 0 }, LE = { 90, 0, 0 }, W = { -8, 0, 0 } } },
		{ dur = 0.1, style = Enum.EasingStyle.Back, pose = hold },
		-- Braced against the recoil for the whole channel.
		{ dur = math.max(duration - 0.22, 0.1), pose = hold, wobble = tremble(1.6, 38) },
	})
end

function CastPoses.clericRadiantGround(char: Model?)
	CastPoses.play(char, {
		-- Scepter lifted to the heavens as the ray is called down.
		{ dur = 0.16, pose = { RS = { 170, 0, 10 }, LS = { 160, 0, -10 }, W = { 14, 0, 0 }, N = { 20, 0, 0 }, Root = { 0, 0, 0, 0, 0.2, 0 } } },
		-- Drive it into the floor: crouch and slam.
		{ dur = 0.08, style = Enum.EasingStyle.Linear, pose = { RS = { 35, 0, 0 }, LS = { 25, 0, 0 }, RE = { 20, 0, 0 }, W = { -28, 0, 0 }, N = { -12, 0, 0 },
			Root = { 0, 0, 0, 0, -0.8, 0 }, RH = { 45, 0, 0 }, LH = { 45, 0, 0 }, RK = { -70, 0, 0 }, LK = { -70, 0, 0 } } },
		{ dur = 0.22, pose = { RS = { 30, 0, 0 }, LS = { 20, 0, 0 }, W = { -22, 0, 0 },
			Root = { 0, 0, 0, 0, -0.65, 0 }, RH = { 38, 0, 0 }, LH = { 38, 0, 0 }, RK = { -58, 0, 0 }, LK = { -58, 0, 0 } } },
	})
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
-- the hips drop, the SUPPORT leg (left) angles forward to plant its foot in
-- front, and the KNEELING leg (right) points straight down — its lower end sinks
-- a little into the floor, reading as the knee down with the shin folded behind.
-- R6 legs hang off the torso, so leaning the upper body also tilts the legs;
-- `lean` (waist pitch, negative = forward) is compensated in the hip angles so
-- the feet stay planted. R15 rigs also bend the knees.
local KNEEL_DROP = 0.6        -- studs the hips sink
local KNEEL_LEG_ANGLE = 46    -- degrees each leg angles off vertical (acos(1.4 / 2) for R6 legs)
function CastPoses.kneelOnOneKnee(lean: number): Pose
	return {
		Root = { 0, 0, 0, 0, -KNEEL_DROP, 0 },
		W = { lean, 0, 0 },
		LH = { KNEEL_LEG_ANGLE - lean, 0, -4 },  -- support: foot planted in front
		RH = { -lean, 0, 3 },                    -- kneeling: straight down, knee on the floor
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
	local crouch = { Root = { 0, 0, 0, 0, -1.3, 0 }, W = { -40, 0, 0 }, N = { -10, 0, 0 },
		RS = { 45, 0, 20 }, RE = { 10, 0, 0 }, RW = { 45, 0, 0 }, LS = { 30, 0, -45 }, LE = { 20, 0, 0 },
		RH = { 85, 0, 12 }, LH = { 20, 0, -18 }, RK = { -100, 0, 0 }, LK = { -60, 0, 0 } }
	CastPoses.play(char, {
		-- Hoist: bow raised overhead in both hands, rising on the toes.
		{ dur = 0.28, style = Enum.EasingStyle.Sine, pose = { RS = { 170, 0, -10 }, LS = { 170, 0, 10 }, RE = { 25, 0, 0 }, LE = { 25, 0, 0 },
			W = { 14, 0, 0 }, N = { 18, 0, 0 }, Root = { 0, 0, 0, 0, 0.35, 0 } } },
		-- SMASH (impact at 0.36s).
		{ dur = 0.08, style = Enum.EasingStyle.Linear, pose = crouch },
		-- Hold the crouch as the vines spiral up, breathing hard.
		{ dur = 0.49, pose = crouch, wobble = function(t)
			local b = math.sin(t * 9) * 2
			return { W = { b, 0, 0 }, RS = { 0, 0, b } }
		end },
		-- Spring up and draw skyward...
		{ dur = 0.07, style = Enum.EasingStyle.Back, pose = { LS = { 155, 0, -10 }, LE = { 5, 0, 0 }, RS = { 125, 0, 30 }, RE = { 125, 0, 0 },
			W = { 22, -15, 0 }, N = { 30, -10, 0 }, Root = { 0, 0, 0, 0, 0.1, 0 } } },
		-- ...and loose (0.95s): draw hand snaps back open.
		{ dur = 0.05, style = Enum.EasingStyle.Back, pose = { LS = { 155, 0, -10 }, RS = { 100, 0, 60 }, RE = { 30, 0, 0 },
			W = { 26, -18, 0 }, N = { 32, -10, 0 }, Root = { 0, 0, 0, 0, 0, 0 } } },
		{ dur = 0.3, pose = { LS = { 130, 0, -8 }, RS = { 70, 0, 45 }, W = { 18, -12, 0 }, N = { 25, -8, 0 } } },
	})
end

-- ── Ice Mage ────────────────────────────────────────────────────────────────
function CastPoses.iceBolt(char: Model?)
	CastPoses.play(char, {
		{ dur = 0.05, pose = { RS = { 60, 0, 30 }, RE = { 70, 0, 0 }, W = { 0, 14, 0 } } },
		-- Flick: arm snaps straight and the crystal leaves the fingertips.
		{ dur = 0.06, style = Enum.EasingStyle.Back, pose = { RS = { 92, 0, -6 }, RE = { 0, 0, 0 }, RW = { -20, 0, 0 }, W = { -4, -10, 0 } } },
		{ dur = 0.08, pose = { RS = { 85, 0, -4 }, RW = { -12, 0, 0 }, W = { -2, -6, 0 } } },
	})
end

CastPoses.ICE_SPIKES_IMPACT = 0.16
function CastPoses.iceSpikes(char: Model?)
	CastPoses.play(char, {
		-- Rear up, frost gathering in the raised hand...
		{ dur = 0.1, pose = { RS = { 150, 0, 30 }, RE = { 40, 0, 0 }, LS = { 30, 0, -40 }, W = { 12, 15, 0 }, Root = { 0, 0, 0, 0, 0.15, 0 } } },
		-- ...then drop and slam the palm into the floor (impact at 0.16s).
		{ dur = 0.06, style = Enum.EasingStyle.Linear, pose = { RS = { 55, 0, 12 }, RE = { 5, 0, 0 }, RW = { 40, 0, 0 }, LS = { 20, 0, -55 }, W = { -35, -5, 0 }, N = { -10, 0, 0 },
			Root = { 0, 0, 0, 0, -1.0, 0 }, RH = { 70, 0, 0 }, LH = { 15, 0, -8 }, RK = { -85, 0, 0 }, LK = { -45, 0, 0 } } },
		{ dur = 0.2, pose = { RS = { 50, 0, 12 }, RW = { 35, 0, 0 }, LS = { 18, 0, -50 }, W = { -30, -5, 0 },
			Root = { 0, 0, 0, 0, -0.9, 0 }, RH = { 62, 0, 0 }, LH = { 12, 0, -8 }, RK = { -78, 0, 0 }, LK = { -40, 0, 0 } } },
	})
end

function CastPoses.iceBeam(char: Model?, duration: number)
	local hold = { RS = { 90, 0, -12 }, LS = { 90, 0, 12 }, RE = { 5, 0, 0 }, LE = { 5, 0, 0 }, RW = { -60, 0, 0 }, LW = { -60, 0, 0 },
		W = { 8, 0, 0 }, N = { -4, 0, 0 } } -- legs are left to the skating layer
	CastPoses.play(char, {
		-- Palms cup a charging orb at the hip...
		{ dur = 0.1, pose = { RS = { 30, 0, -20 }, LS = { 30, 0, 20 }, RE = { 85, 0, 0 }, LE = { 85, 0, 0 }, W = { 4, 30, 0 }, Root = { 0, 0, 0, 0, -0.2, 0 } } },
		-- ...and thrust forward as the beam erupts.
		{ dur = 0.08, style = Enum.EasingStyle.Back, pose = hold },
		{ dur = math.max(duration - 0.18, 0.1), pose = hold, wobble = tremble(1.3, 44) },
	})
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
local MENACE = { N = { -12, 0, 0 }, W = { 3, 0, 0 }, RS = { 4, 0, 14 }, LS = { 4, 0, -14 }, RE = { 12, 0, 0 }, LE = { 12, 0, 0 },
	RH = { 0, 0, 4 }, LH = { 0, 0, -4 }, Root = { 0, 0, 0, 0, 0.05, 0 } }
function CastPoses.iceBlizzard(char: Model?)
	local stare = table.clone(MENACE)
	stare.N = { 2, 0, 0 }
	local tensed = table.clone(MENACE)
	tensed.N = { 4, 0, 0 }
	tensed.W = { 6, 0, 0 }
	tensed.RS, tensed.LS = { -6, 0, 24 }, { -6, 0, -24 }
	tensed.RH, tensed.LH = { 0, 0, 8 }, { 0, 0, -8 }
	tensed.Root = { 0, 0, 0, 0, -0.1, 0 }
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
