--!strict
--[[
	Summons/Beasts.luau
	How each of the Summoner's beasts moves (SummonerController drives one
	animator per beast on the field, every frame):

	  local a = Beasts.new(kind, rig)
	  a:update(dt, ctx) → CFrame   writes the rig's pose; returns an extra
	                               offset for the whole beast (its arrival
	                               from the sky, the gate it rises from)
	  a:play(act, dur)             an attack (SummonerServer's "act")
	  a:signature(at, length, travel)  the baked GLB move from clock `at`
	  a:arrive(fall) / a:leave(how)

	The artist's stance (the first frame of each beast's baked move) is the
	base; everything here is turned on top of it, bone by bone, in degrees:
	X swings a hanging limb forward (and tips a torso or head back), Y turns
	it left, Z swings it to the beast's right.

	  Rockborn    a heavy plodding stride: hips and shoulders counter-turn,
	              the body drops onto each stamping foot, knees fold as the
	              leg comes through, fists swing; breathing at rest, the lava
	              in it pulsing. Hooks wind up through the hips and snap
	              across; the hammer arches back and comes down with the
	              whole body.
	  Skyfeather  flies: the inner wing beats and the outer half whips after
	              it; the body rises on each downstroke, pitches into speed,
	              banks into turns; glides now and then; hovers upright with
	              sweeping beats; head steady through all of it.
	  Lunari      walks in a four-beat step and bounds at speed (the hind
	              pair launches, the front pair lands a beat later, the body
	              rocking nose-up then nose-down), knees folding as each leg
	              swings through; grazes and looks round at rest; the tail
	              trails a spring behind the body.
	  Skyrockorn  its baked flight only.
--]]

local Beasts = {}

local A = {}
A.__index = A

local rad = math.rad
local sin, cos, abs, clamp, max, min = math.sin, math.cos, math.abs, math.clamp, math.max, math.min
local TAU = math.pi * 2

local function ang(x: number, y: number, z: number): CFrame
	return CFrame.Angles(rad(x), rad(y), rad(z))
end

local function smooth(a: number): number
	a = clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

-- Easing into a key: "out" decelerates (a wind-up settling), "in"
-- accelerates (a blow landing), "back" overshoots and settles, default
-- eases both ends.
local function ease(style: string?, a: number): number
	if style == "out" then return 1 - (1 - a) ^ 3 end
	if style == "in" then return a ^ 3 end
	if style == "lin" then return a end
	if style == "back" then
		local c = 1.9
		return 1 + (c + 1) * (a - 1) ^ 3 + c * (a - 1) ^ 2
	end
	return smooth(a)
end

-- A move as keys: { t (fraction of the move), pose = { [bone] = {x, y, z} },
-- e = easing into it }. "move" is the root's shift in studs.
type Key = { t: number, e: string?, p: { [string]: { number } } }

local function mirrorName(n: string): string
	if string.find(n, "Left") then return (string.gsub(n, "Left", "Right")) end
	if string.find(n, "Right") then return (string.gsub(n, "Right", "Left")) end
	return n
end

local function mirror(keys: { Key }): { Key }
	local out = {}
	for _, k in ipairs(keys) do
		local p = {}
		for n, v in pairs(k.p) do
			if n == "move" then
				p[n] = { -v[1], v[2], v[3] }
			else
				p[mirrorName(n)] = { v[1], -v[2], -v[3] }
			end
		end
		table.insert(out, { t = k.t, e = k.e, p = p })
	end
	return out
end

-- Every bone a move touches gets a value from every key (0 where unset).
local function prepare(keys: { Key }): { Key }
	local names = {}
	for _, k in ipairs(keys) do
		for n in pairs(k.p) do names[n] = true end
	end
	for _, k in ipairs(keys) do
		for n in pairs(names) do
			if not k.p[n] then k.p[n] = { 0, 0, 0 } end
		end
	end
	if keys[1].t > 0 then
		local zero = {}
		for n in pairs(names) do zero[n] = { 0, 0, 0 } end
		table.insert(keys, 1, { t = 0, p = zero })
	end
	return keys
end

-- ── The moves ───────────────────────────────────────────────────────────────
local ACTS: { [string]: { [string]: { Key } } } = { rock = {}, sky = {}, moon = {} }

-- Rockborn: the left hook. The weight goes back and the hips and shoulders
-- coil to the right, the left fist drawn low; then everything uncoils at
-- once: the fist comes across, the body follows it through, a step in.
ACTS.rock.hookL = prepare({
	{ t = 0.36, e = "out", p = {
		LowerTorso = { 0, -12, 0 }, UpperTorso = { 6, -30, -4 }, Head = { -4, 18, 0 },
		LeftUpperArm = { -38, 10, -28 }, LeftLowerArm = { 55, 0, 0 },
		RightUpperArm = { 34, -10, 8 }, RightLowerArm = { 70, 0, 0 },
		LeftUpperLeg = { -8, 0, 0 }, RightUpperLeg = { 12, 0, 0 }, RightLowerLeg = { -14, 0, 0 },
		move = { 0, -0.25, 0.35 } } },
	{ t = 0.52, e = "in", p = {
		LowerTorso = { 0, 16, 0 }, UpperTorso = { -14, 40, 6 }, Head = { 6, -24, 0 },
		LeftUpperArm = { 96, -28, -8 }, LeftLowerArm = { 30, 0, 0 },
		RightUpperArm = { -16, 8, 10 }, RightLowerArm = { 62, 0, 0 },
		LeftUpperLeg = { 24, 0, 0 }, LeftLowerLeg = { -18, 0, 0 }, RightUpperLeg = { -18, 0, 0 },
		move = { 0, -0.45, -1.1 } } },
	{ t = 0.7, e = "out", p = {
		LowerTorso = { 0, 13, 0 }, UpperTorso = { -10, 34, 4 }, Head = { 4, -20, 0 },
		LeftUpperArm = { 88, -24, -6 }, LeftLowerArm = { 34, 0, 0 },
		RightUpperArm = { -10, 6, 8 }, RightLowerArm = { 60, 0, 0 },
		LeftUpperLeg = { 20, 0, 0 }, LeftLowerLeg = { -14, 0, 0 }, RightUpperLeg = { -14, 0, 0 },
		move = { 0, -0.35, -1.0 } } },
	{ t = 1, p = {} },
})
ACTS.rock.hookR = mirror(ACTS.rock.hookL)

-- The hammer: both fists swing up and back over the head, the chest arching;
-- then the whole body drops behind them into a crouch as they come down.
ACTS.rock.hammer = prepare({
	{ t = 0.36, e = "out", p = {
		UpperTorso = { 16, 0, 0 }, LowerTorso = { 4, 0, 0 }, Head = { 14, 0, 0 },
		LeftUpperArm = { 168, 0, -14 }, RightUpperArm = { 168, 0, 14 },
		LeftLowerArm = { 34, 0, 0 }, RightLowerArm = { 34, 0, 0 },
		LeftUpperLeg = { -4, 0, -4 }, RightUpperLeg = { -4, 0, 4 },
		move = { 0, 0.45, 0.3 } } },
	{ t = 0.55, e = "in", p = {
		UpperTorso = { -36, 0, 0 }, LowerTorso = { -10, 0, 0 }, Head = { -14, 0, 0 },
		LeftUpperArm = { 58, 0, 8 }, RightUpperArm = { 58, 0, -8 },
		LeftLowerArm = { 20, 0, 0 }, RightLowerArm = { 20, 0, 0 },
		LeftUpperLeg = { 34, 0, -6 }, RightUpperLeg = { 34, 0, 6 },
		LeftLowerLeg = { -52, 0, 0 }, RightLowerLeg = { -52, 0, 0 },
		LeftFoot = { 18, 0, 0 }, RightFoot = { 18, 0, 0 },
		move = { 0, -1.25, -0.7 } } },
	{ t = 0.74, e = "out", p = {
		UpperTorso = { -32, 0, 0 }, LowerTorso = { -9, 0, 0 }, Head = { -6, 0, 0 },
		LeftUpperArm = { 54, 0, 10 }, RightUpperArm = { 54, 0, -10 },
		LeftLowerArm = { 22, 0, 0 }, RightLowerArm = { 22, 0, 0 },
		LeftUpperLeg = { 30, 0, -6 }, RightUpperLeg = { 30, 0, 6 },
		LeftLowerLeg = { -46, 0, 0 }, RightLowerLeg = { -46, 0, 0 },
		LeftFoot = { 16, 0, 0 }, RightFoot = { 16, 0, 0 },
		move = { 0, -1.1, -0.65 } } },
	{ t = 1, p = {} },
})

-- Its arrival: curled up as it falls (handled in `arrive`), then it lands in
-- a deep crouch and rises with a roar, arms flung wide.
ACTS.rock.land = prepare({
	{ t = 0.0, p = {
		UpperTorso = { -40, 0, 0 }, Head = { -20, 0, 0 },
		LeftUpperArm = { 70, 0, 20 }, RightUpperArm = { 70, 0, -20 }, LeftLowerArm = { 60, 0, 0 }, RightLowerArm = { 60, 0, 0 },
		LeftUpperLeg = { 60, 0, 0 }, RightUpperLeg = { 60, 0, 0 }, LeftLowerLeg = { -90, 0, 0 }, RightLowerLeg = { -90, 0, 0 },
		move = { 0, 0, 0 } } },
	{ t = 0.12, e = "in", p = {
		UpperTorso = { -34, 0, 0 }, Head = { -10, 0, 0 },
		LeftUpperArm = { 40, 0, -40 }, RightUpperArm = { 40, 0, 40 }, LeftLowerArm = { 30, 0, 0 }, RightLowerArm = { 30, 0, 0 },
		LeftUpperLeg = { 50, 0, -10 }, RightUpperLeg = { 50, 0, 10 }, LeftLowerLeg = { -70, 0, 0 }, RightLowerLeg = { -70, 0, 0 },
		LeftFoot = { 20, 0, 0 }, RightFoot = { 20, 0, 0 },
		move = { 0, -1.7, 0 } } },
	{ t = 0.32, e = "out", p = {
		UpperTorso = { -30, 0, 0 }, Head = { -6, 0, 0 },
		LeftUpperArm = { 30, 0, -46 }, RightUpperArm = { 30, 0, 46 }, LeftLowerArm = { 26, 0, 0 }, RightLowerArm = { 26, 0, 0 },
		LeftUpperLeg = { 46, 0, -10 }, RightUpperLeg = { 46, 0, 10 }, LeftLowerLeg = { -66, 0, 0 }, RightLowerLeg = { -66, 0, 0 },
		LeftFoot = { 20, 0, 0 }, RightFoot = { 20, 0, 0 },
		move = { 0, -1.6, 0 } } },
	{ t = 0.62, e = "back", p = {
		UpperTorso = { 20, 0, 0 }, Head = { 28, 0, 0 },
		LeftUpperArm = { 40, 0, -78 }, RightUpperArm = { 40, 0, 78 }, LeftLowerArm = { 40, 0, 0 }, RightLowerArm = { 40, 0, 0 },
		move = { 0, 0.15, 0 } } },
	{ t = 0.8, p = {
		UpperTorso = { 18, 0, 0 }, Head = { 24, 0, 0 },
		LeftUpperArm = { 36, 0, -74 }, RightUpperArm = { 36, 0, 74 }, LeftLowerArm = { 44, 0, 0 }, RightLowerArm = { 44, 0, 0 },
		move = { 0, 0.1, 0 } } },
	{ t = 1, p = {} },
})

-- Skyfeather: the volley. Wings flung up and back with the chest rearing,
-- then one hard beat down that throws the feathers.
ACTS.sky.volley = prepare({
	{ t = 0.3, e = "out", p = {
		HumanoidRootPart = { 26, 0, 0 }, Head = { -18, 0, 0 }, Tail = { 20, 0, 0 },
		LeftWing1 = { 0, 18, -72 }, RightWing1 = { 0, -18, 72 }, LeftWing2 = { 0, 10, -30 }, RightWing2 = { 0, -10, 30 },
		move = { 0, 0.4, 0.4 } } },
	{ t = 0.46, e = "in", p = {
		HumanoidRootPart = { -12, 0, 0 }, Head = { 10, 0, 0 }, Tail = { -10, 0, 0 },
		LeftWing1 = { 0, -24, 62 }, RightWing1 = { 0, 24, -62 }, LeftWing2 = { 0, -10, 44 }, RightWing2 = { 0, 10, -44 },
		move = { 0, 0.8, 0.9 } } },
	{ t = 1, p = {} },
})

-- Lunari: the horn jab. Head drops and the body sits back on its haunches,
-- then it drives forward and flicks the antlers up through the target.
ACTS.moon.jab = prepare({
	{ t = 0.28, e = "out", p = {
		Neck = { -38, 0, 0 }, Head = { -16, 0, 0 }, HumanoidRootPart = { 6, 0, 0 },
		LeftFrontUpperLeg = { -12, 0, 0 }, RightFrontUpperLeg = { -12, 0, 0 },
		LeftBackUpperLeg = { 16, 0, 0 }, RightBackUpperLeg = { 16, 0, 0 },
		LeftBackLowerLeg = { -24, 0, 0 }, RightBackLowerLeg = { -24, 0, 0 },
		Tail1 = { -10, 0, 0 },
		move = { 0, -0.35, 0.7 } } },
	{ t = 0.46, e = "in", p = {
		Neck = { 26, 0, 0 }, Head = { 14, 0, 0 }, HumanoidRootPart = { -8, 0, 0 },
		LeftFrontUpperLeg = { 22, 0, 0 }, RightFrontUpperLeg = { 14, 0, 0 },
		LeftBackUpperLeg = { -24, 0, 0 }, RightBackUpperLeg = { -20, 0, 0 },
		Tail1 = { -24, 0, 0 },
		move = { 0, 0.15, -1.5 } } },
	{ t = 0.62, e = "out", p = {
		Neck = { 20, 0, 0 }, Head = { 10, 0, 0 }, HumanoidRootPart = { -5, 0, 0 },
		LeftFrontUpperLeg = { 16, 0, 0 }, RightFrontUpperLeg = { 10, 0, 0 },
		LeftBackUpperLeg = { -16, 0, 0 }, RightBackUpperLeg = { -14, 0, 0 },
		Tail1 = { -18, 0, 0 },
		move = { 0, 0.05, -1.2 } } },
	{ t = 1, p = {} },
})

-- Its healing pulse: a toss of the head.
ACTS.moon.pulse = prepare({
	{ t = 0.35, e = "out", p = { Neck = { 18, 0, 0 }, Head = { 12, 0, 0 }, Tail1 = { -16, 0, 0 } } },
	{ t = 1, p = {} },
})

-- Out of the moon gate: it rises from below already leaping, lands, and
-- rears up once.
ACTS.moon.land = prepare({
	{ t = 0.0, p = {
		HumanoidRootPart = { 18, 0, 0 },
		LeftFrontUpperLeg = { 50, 0, 0 }, RightFrontUpperLeg = { 50, 0, 0 }, LeftFrontLowerLeg = { -95, 0, 0 }, RightFrontLowerLeg = { -95, 0, 0 },
		LeftBackUpperLeg = { -40, 0, 0 }, RightBackUpperLeg = { -40, 0, 0 }, LeftBackLowerLeg = { 30, 0, 0 }, RightBackLowerLeg = { 30, 0, 0 },
		Neck = { 14, 0, 0 }, Tail1 = { -30, 0, 0 } } },
	{ t = 0.3, e = "in", p = {
		HumanoidRootPart = { -6, 0, 0 },
		LeftFrontUpperLeg = { 10, 0, 0 }, RightFrontUpperLeg = { 10, 0, 0 }, LeftFrontLowerLeg = { -20, 0, 0 }, RightFrontLowerLeg = { -20, 0, 0 },
		LeftBackUpperLeg = { 18, 0, 0 }, RightBackUpperLeg = { 18, 0, 0 }, LeftBackLowerLeg = { -30, 0, 0 }, RightBackLowerLeg = { -30, 0, 0 },
		Neck = { -16, 0, 0 },
		move = { 0, -0.7, 0 } } },
	{ t = 0.55, e = "out", p = {
		HumanoidRootPart = { 30, 0, 0 },
		LeftFrontUpperLeg = { 60, 0, 0 }, RightFrontUpperLeg = { 40, 0, 0 }, LeftFrontLowerLeg = { -100, 0, 0 }, RightFrontLowerLeg = { -80, 0, 0 },
		LeftBackUpperLeg = { -26, 0, 0 }, RightBackUpperLeg = { -26, 0, 0 }, LeftBackLowerLeg = { 10, 0, 0 }, RightBackLowerLeg = { 10, 0, 0 },
		Neck = { 10, 0, 0 }, Head = { -14, 0, 0 }, Tail1 = { -20, 0, 0 },
		move = { 0, 0.9, 0.9 } } },
	{ t = 0.72, p = {
		HumanoidRootPart = { 26, 0, 0 },
		LeftFrontUpperLeg = { 30, 0, 0 }, RightFrontUpperLeg = { 66, 0, 0 }, LeftFrontLowerLeg = { -90, 0, 0 }, RightFrontLowerLeg = { -104, 0, 0 },
		LeftBackUpperLeg = { -24, 0, 0 }, RightBackUpperLeg = { -24, 0, 0 },
		Neck = { 14, 0, 0 }, Head = { -10, 0, 0 }, Tail1 = { -18, 0, 0 },
		move = { 0, 0.8, 0.8 } } },
	{ t = 1, e = "in", p = {} },
})

-- ── Small helpers ───────────────────────────────────────────────────────────
-- A damped spring toward a moving goal (secondary motion: heads, tails).
local function spring(s: { x: number, v: number }, goal: number, freq: number, damp: number, dt: number): number
	local w = TAU * freq
	local f = w * w * (goal - s.x) - 2 * damp * w * s.v
	s.v += f * dt
	s.x += s.v * dt
	return s.x
end

local function sampleKeys(keys: { Key }, a: number, out: { [string]: { number } })
	a = clamp(a, 0, 1)
	local i = 1
	while i < #keys and keys[i + 1].t < a do i += 1 end
	local k0, k1 = keys[i], keys[min(i + 1, #keys)]
	local span = k1.t - k0.t
	local u = if span > 0 then ease(k1.e, (a - k0.t) / span) else 1
	for n, v0 in pairs(k0.p) do
		local v1 = k1.p[n] or v0
		local o = out[n]
		if not o then
			o = { 0, 0, 0 }
			out[n] = o
		end
		o[1] += v0[1] + (v1[1] - v0[1]) * u
		o[2] += v0[2] + (v1[2] - v0[2]) * u
		o[3] += v0[3] + (v1[3] - v0[3]) * u
	end
end

local function add(out: { [string]: { number } }, n: string, x: number, y: number, z: number)
	local o = out[n]
	if not o then
		o = { 0, 0, 0 }
		out[n] = o
	end
	o[1] += x
	o[2] += y
	o[3] += z
end

-- ── The animator ────────────────────────────────────────────────────────────
export type Ctx = {
	clock: number,
	speed: number,      -- flat speed, studs/s
	climb: number,      -- vertical speed
	yawRate: number,    -- turning, rad/s (+ is left)
	look: number,       -- the turn from its facing to what it watches (rad, + left)
	pitch: number?,     -- (fliers) how steeply it's heading down (deg, + nose down)
}

function Beasts.new(kind: string, rig: any): any
	rig:reset()
	if kind ~= "fused" then rig:clip(0, 1) end
	local base = table.clone(rig.L)
	local baseMove = rig.move
	if kind == "sky" then
		-- In the air: wings out flat (as modelled), feet tucked up under the tail.
		for _, n in ipairs({ "LeftWing1", "LeftWing2", "RightWing1", "RightWing2" }) do
			local i = rig:bone(n)
			if i then base[i] = CFrame.identity end
		end
		for _, side in ipairs({ "Left", "Right" }) do
			local u, l = rig:bone(side .. "UpperLeg"), rig:bone(side .. "LowerLeg")
			if u then base[u] = ang(-62, 0, 0) end
			if l then base[l] = ang(84, 0, 0) end
		end
		local h = rig:bone("HumanoidRootPart")
		if h then base[h] = CFrame.identity end
		baseMove = CFrame.identity
	end
	local self = setmetatable({
		kind = kind, rig = rig, base = base, baseMove = baseMove,
		phase = 0, gaitW = 0, gallop = 0, flap = 0, flapAmp = 1, glide = 0, glideT = 0,
		t = 0, act = nil, sig = nil, arriving = nil, leaving = nil,
		off = {} :: { [string]: { number } },
		head = { x = 0, v = 0 }, headP = { x = 0, v = 0 }, tail = { x = 0, v = 0 }, tail2 = { x = 0, v = 0 },
		bank = { x = 0, v = 0 }, pitchS = { x = 0, v = 0 },
		lastStep = 0, onStep = nil :: ((string) -> ())?,
		grazeAt = 6 + math.random() * 6, grazing = 0,
		lookAround = 0, lookAt = 0,
	}, A)
	return self
end

function A:play(name: string, dur: number, data: any?)
	local keys = ACTS[self.kind] and ACTS[self.kind][name]
	self.act = { name = name, t0 = self.t, dur = math.max(dur, 0.05), keys = keys, data = data }
end

function A:signature(startIn: number, length: number, travel: Vector3?)
	self.sig = { t0 = self.t + startIn, len = length, travel = travel, lead = startIn }
	self.act = nil
end

function A:arrive(fall: number)
	self.arriving = { t0 = self.t, fall = fall }
	if self.kind == "rock" or self.kind == "moon" then
		self.act = { name = "land", t0 = self.t + fall, dur = if self.kind == "rock" then 1.5 else 1.1, keys = ACTS[self.kind].land }
	end
end

function A:leave(how: string)
	self.leaving = { t0 = self.t, how = how }
end

function A:sigActive(): boolean
	local s = self.sig
	return s ~= nil and self.t < s.t0 + s.len
end

-- ── Rockborn ────────────────────────────────────────────────────────────────
local function rockMove(self: any, dt: number, c: Ctx, off: { [string]: { number } }): Vector3
	local speed = c.speed
	self.gaitW += (clamp(speed / 7, 0, 1) - self.gaitW) * min(1, dt * 6)
	local w = self.gaitW
	-- (a heavy stride: about two steps a second; faster, it reaches further
	-- rather than scurrying, so the feet stay planted)
	local stride = 5.6 + max(0, speed - 10) * 0.35
	self.phase = (self.phase + dt * max(speed, w * 3) / stride * TAU) % TAU
	local ph = self.phase
	local s, co = sin(ph), cos(ph)
	local hipA = (26 + clamp((speed - 8) * 1.6, 0, 16)) * w
	add(off, "LeftUpperLeg", hipA * s, 0, 0)
	add(off, "RightUpperLeg", -hipA * s, 0, 0)
	-- knees fold as each leg comes through (moving forward), feet kept flat
	local kL = -40 * w * max(0, co) ^ 1.3
	local kR = -40 * w * max(0, -co) ^ 1.3
	add(off, "LeftLowerLeg", kL, 0, 0)
	add(off, "RightLowerLeg", kR, 0, 0)
	add(off, "LeftFoot", -(hipA * s + kL) * 0.7, 0, 0)
	add(off, "RightFoot", -(-hipA * s + kR) * 0.7, 0, 0)
	-- the body drops onto each stamping foot and rolls over it
	local y = -0.5 * w * s * s
	add(off, "HumanoidRootPart", 0, 0, 5 * w * co)
	-- hips turn with the legs, shoulders against them, a lean into the walk
	add(off, "LowerTorso", 0, 8 * w * s, 0)
	add(off, "UpperTorso", -9 * w, -15 * w * s, -3 * w * co)
	add(off, "Head", 6 * w, 10 * w * s, 3 * w * co)
	-- fists swing against the legs, elbows bending on the way forward
	add(off, "LeftUpperArm", -26 * w * s, 0, -4 * w)
	add(off, "RightUpperArm", 26 * w * s, 0, 4 * w)
	add(off, "LeftLowerArm", 18 * w * max(0, -s), 0, 0)
	add(off, "RightLowerArm", 18 * w * max(0, s), 0, 0)
	-- a stamp on each footfall
	local foot = if s > 0.97 then "L" elseif s < -0.97 then "R" else nil
	if foot and w > 0.4 and self.t - self.lastStep > 0.25 then
		self.lastStep = self.t
		if self.onStep then self.onStep(foot) end
	end
	-- at rest: slow heavy breathing, a weight shift, the arms hanging loose
	local idle = 1 - w
	local br = sin(self.t * 1.7)
	add(off, "UpperTorso", 2.5 * idle * br, 0, 1.5 * idle * sin(self.t * 0.45))
	add(off, "LeftUpperArm", 3 * idle * br, 0, -3 * idle * (0.5 + 0.5 * br))
	add(off, "RightUpperArm", 3 * idle * br, 0, 3 * idle * (0.5 + 0.5 * br))
	add(off, "Head", -2 * idle * br, 0, 0)
	local sway = 0.12 * idle * sin(self.t * 0.45)
	-- the head turns to what it's watching (a spring: it trails the body)
	local look = spring(self.head, clamp(math.deg(c.look), -55, 55), 2.2, 0.75, dt)
	add(off, "Head", 0, look * 0.6, 0)
	add(off, "UpperTorso", 0, look * 0.25, 0)
	-- the lava in it breathes
	self.rig:glow(0.1 + 0.12 * (0.5 + 0.5 * sin(self.t * 2.2)))
	return Vector3.new(sway, y, 0)
end

-- ── Skyfeather ──────────────────────────────────────────────────────────────
local function skyMove(self: any, dt: number, c: Ctx, off: { [string]: { number } }): Vector3
	local speed = c.speed
	local hover = clamp(1 - speed / 10, 0, 1)
	-- glides now and then when cruising fast
	self.glideT -= dt
	if self.glideT <= 0 then
		self.glideT = 2.4 + math.random() * 1.6
		if speed > 16 and abs(c.climb) < 3 then self.glideLeft = 0.75 end
	end
	self.glideLeft = max(0, (self.glideLeft or 0) - dt)
	local wantGlide = if self.glideLeft > 0 and speed > 12 then 1 else 0
	self.glide += (wantGlide - self.glide) * min(1, dt * 5)
	local gl = self.glide
	-- beats faster to hover or climb
	local freq = 2.7 + 1.5 * hover + clamp(c.climb * 0.1, 0, 1)
	self.flap = (self.flap + dt * freq * TAU) % TAU
	local ph = self.flap
	local amp = (1 - gl * 0.85) * self.flapAmp
	local beat = sin(ph)
	local whip = sin(ph - 0.95)
	-- inner wing beats (+ is down for the left wing), the outer half whips after
	local inner = 46 * amp * beat - 6 * gl
	local outer = 30 * amp * whip - 4 * gl
	-- (hovering: the beat sweeps forward and back as well)
	local sweep = 26 * hover * amp * cos(ph)
	add(off, "LeftWing1", 0, -sweep, inner)
	add(off, "RightWing1", 0, sweep, -inner)
	add(off, "LeftWing2", 0, -sweep * 0.4, outer)
	add(off, "RightWing2", 0, sweep * 0.4, -outer)
	-- the body rises on the downstroke
	local bob = 0.32 * amp * beat
	-- pitch: nose down into speed, back and upright to hover
	local wantPitch = -min(28, speed * 1.1) + 18 * hover - clamp(c.climb * 1.8, -20, 20) + (c.pitch or 0) * -1
	local pitch = spring(self.pitchS, wantPitch, 1.6, 0.8, dt)
	-- bank into turns
	local bank = spring(self.bank, clamp(math.deg(c.yawRate) * 0.45, -42, 42), 1.8, 0.7, dt)
	add(off, "HumanoidRootPart", pitch, 0, bank)
	-- head steady against it all, turned to its target
	local look = spring(self.head, clamp(math.deg(c.look), -60, 60), 2.6, 0.8, dt)
	add(off, "Head", -pitch * 0.75 - 4 * amp * beat, look * 0.7, -bank * 0.6)
	add(off, "UpperTorso", -3 * amp * beat, look * 0.2, 0)
	-- tail: a rudder against the turn, fanning down to brake into a hover
	local tailY = spring(self.tail, -math.deg(c.yawRate) * 0.25, 2.4, 0.6, dt)
	add(off, "Tail", -pitch * 0.3 + 14 * hover + 5 * amp * beat, tailY, 0)
	-- legs hang a little forward when it hovers (ready to land / strike)
	add(off, "LeftUpperLeg", 40 * hover, 0, 0)
	add(off, "RightUpperLeg", 40 * hover, 0, 0)
	add(off, "LeftLowerLeg", -50 * hover, 0, 0)
	add(off, "RightLowerLeg", -50 * hover, 0, 0)
	return Vector3.new(0, bob, 0)
end

-- ── Lunari ──────────────────────────────────────────────────────────────────
-- Leg phases: a four-beat walk, and the bounding gallop (hind pair first,
-- the front pair a beat later to catch the body).
local LEGS = {
	{ n = "LeftBack", walk = 0, gallop = 0, front = false },
	{ n = "RightBack", walk = math.pi, gallop = 0.3, front = false },
	{ n = "LeftFront", walk = math.pi * 0.5, gallop = 1.4, front = true },
	{ n = "RightFront", walk = math.pi * 1.5, gallop = 1.7, front = true },
}

local function moonMove(self: any, dt: number, c: Ctx, off: { [string]: { number } }): Vector3
	local speed = c.speed
	self.gaitW += (clamp(speed / 4, 0, 1) - self.gaitW) * min(1, dt * 7)
	self.gallop += (clamp((speed - 9) / 7, 0, 1) - self.gallop) * min(1, dt * 4)
	local w, g = self.gaitW, self.gallop
	-- walk: 4.4 studs a cycle; gallop: 11 (brisk either way)
	local cycle = 4.4 + 6.6 * g
	self.phase = (self.phase + dt * max(speed, w * 2) / cycle * TAU) % TAU
	local ph = self.phase
	local hipA = (20 + 20 * g) * w
	local fold = (34 + 40 * g) * w
	for _, L in ipairs(LEGS) do
		local o = L.walk + (L.gallop - L.walk) * g
		local p = ph - o
		local hip = hipA * sin(p)
		-- the knee folds as the leg swings through (hoof tucked back)
		local knee = -fold * max(0, cos(p)) ^ 1.2
		add(off, L.n .. "UpperLeg", hip, 0, 0)
		add(off, L.n .. "LowerLeg", knee, 0, 0)
		add(off, L.n .. "Hoof", -knee * 0.55 - hip * 0.3, 0, 0)
	end
	-- the body: a light bob at a walk; at the gallop it's thrown up after the
	-- hind push and rocks nose-up, then nose-down onto the front pair
	local walkBob = 0.1 * w * (1 - g) * sin(ph * 2)
	local air = 0.55 * g * max(0, sin(ph - 0.6))
	local rock = 7 * g * sin(ph - 0.2)
	add(off, "HumanoidRootPart", rock, 0, 0)
	-- the neck stretches out into the gallop and holds the head level
	local nod = 3.5 * w * (1 - g) * sin(ph * 2 + 0.6)
	local look = spring(self.head, clamp(math.deg(c.look), -50, 50), 2.0, 0.75, dt)
	add(off, "Neck", -rock * 0.8 - 14 * g + nod, look * 0.55, 0)
	add(off, "Head", -rock * 0.2 + 6 * g, look * 0.45, 0)
	-- leaning into turns
	add(off, "HumanoidRootPart", 0, 0, clamp(math.deg(c.yawRate) * 0.12 * w, -10, 10))
	-- the tail: raised at speed, trailing the body on a spring
	local tailGoal = -math.deg(c.yawRate) * 0.2 + 8 * sin(self.t * 1.3) * (1 - w)
	local t1 = spring(self.tail, tailGoal, 1.8, 0.45, dt)
	local t2 = spring(self.tail2, t1, 1.6, 0.4, dt)
	add(off, "Tail1", -22 * g - 4 * w + 3 * sin(ph * 2), t1, 0)
	add(off, "Tail2", -6 * g + 4 * sin(ph * 2 - 0.8), t2 * 0.8, 0)
	add(off, "Tail3", 3 * sin(ph * 2 - 1.6), t2 * 0.6, 0)
	-- at rest: breathing, a weight shift, grazing now and then
	local idle = 1 - w
	add(off, "UpperTorso", 1.5 * idle * sin(self.t * 1.5), 0, 0)
	if idle > 0.9 and abs(c.look) < 0.2 then
		self.grazeAt -= dt
		if self.grazeAt <= 0 then
			self.grazeAt = 8 + math.random() * 7
			self.grazing = 2.2
		end
	end
	if self.grazing > 0 then
		self.grazing -= dt
		local k = smooth(min(1, (2.2 - self.grazing) / 0.5)) * smooth(min(1, self.grazing / 0.5))
		add(off, "Neck", -58 * k, 0, 0)
		add(off, "Head", -14 * k + 6 * k * sin(self.t * 9), 0, 0)
		add(off, "LeftFrontUpperLeg", 6 * k, 0, 0)
		if speed > 2 or abs(c.look) > 0.3 then self.grazing = min(self.grazing, 0.5) end
	end
	-- the antlers' glow breathes
	self.rig:glow(0.15 + 0.15 * (0.5 + 0.5 * sin(self.t * 1.6)))
	return Vector3.new(0, walkBob + air, 0)
end

local MOVES = { rock = rockMove, sky = skyMove, moon = moonMove }

-- ── The frame ───────────────────────────────────────────────────────────────
function A:update(dt: number, c: Ctx): CFrame
	self.t = c.clock
	local rig, base, off = self.rig, self.base, self.off
	for _, v in pairs(off) do v[1], v[2], v[3] = 0, 0, 0 end
	local L = rig.L
	for i = 1, #L do L[i] = base[i] end
	local shift = Vector3.zero
	local extra = CFrame.identity

	-- the move it's making (attacks, the landing) and how much it owns the
	-- body (locomotion fades under it)
	local act = self.act
	local actW = 0
	if act then
		local a = (self.t - act.t0) / act.dur
		if a >= 1 then
			self.act = nil
			act = nil
		elseif a >= 0 then
			actW = smooth(min(a / 0.12, 1)) * smooth(min((1 - a) / 0.15, 1))
		end
	end

	if self.kind ~= "fused" then
		local saved = self.flapAmp
		if self.kind == "sky" and act and act.name ~= "dive" then self.flapAmp = 1 - actW * 0.7 end
		shift = MOVES[self.kind](self, dt, c, off)
		self.flapAmp = saved
	end

	if act and act.keys and self.t >= act.t0 then
		local a = clamp((self.t - act.t0) / act.dur, 0, 1)
		sampleKeys(act.keys, a, off)
	end

	-- Skyfeather's dive: wings swept back and the beak pointed down the
	-- line; it flares, talons out, at the strike, then beats back up.
	if act and self.kind == "sky" and act.name == "dive" then
		local a = (self.t - act.t0) / act.dur
		local hitA = 0.5 / 0.9
		local fold = smooth(min(a / 0.25, 1)) * (1 - smooth((a - hitA + 0.08) / 0.1))
		local flare = smooth((a - hitA + 0.1) / 0.12) * (1 - smooth((a - 0.8) / 0.2))
		add(off, "LeftWing1", 0, 62 * fold - 18 * flare, 22 * fold - 46 * flare)
		add(off, "RightWing1", 0, -62 * fold + 18 * flare, -22 * fold + 46 * flare)
		add(off, "LeftWing2", 0, 30 * fold, 10 * fold - 20 * flare)
		add(off, "RightWing2", 0, -30 * fold, -10 * fold + 20 * flare)
		add(off, "HumanoidRootPart", -48 * fold + 38 * flare, 0, 0)
		add(off, "Head", 30 * fold - 20 * flare, 0, 0)
		add(off, "LeftUpperLeg", 90 * flare, 0, 0)
		add(off, "RightUpperLeg", 90 * flare, 0, 0)
		add(off, "LeftLowerLeg", -70 * flare, 0, 0)
		add(off, "RightLowerLeg", -70 * flare, 0, 0)
		self.flapAmp = 1 - fold
	end

	-- Lunari's trample: head down, antlers leading
	if act and self.kind == "moon" and act.name == "charge" then
		add(off, "Neck", -30 * actW, 0, 0)
		add(off, "Head", -12 * actW, 0, 0)
	end

	-- the arrivals
	local arr = self.arriving
	if arr then
		local u = (self.t - arr.t0) / arr.fall
		if u >= 1 then
			if self.t - arr.t0 > arr.fall + 1.6 then self.arriving = nil end
		elseif self.kind == "rock" then
			-- a meteor: from high up, curled, tumbling forward, faster and faster
			extra = CFrame.new(0, 46 * (1 - u * u), 18 * (1 - u)) * CFrame.Angles(-u * TAU * 0.75, 0, 0)
			sampleKeys(ACTS.rock.land, 0, off)
		elseif self.kind == "sky" then
			-- a dive in from high behind, wings folded
			local k = 1 - u
			extra = CFrame.new(0, 34 * k * k, 26 * k) * CFrame.Angles(-rad(50) * k, 0, 0)
			add(off, "LeftWing1", 0, 60 * k, 20 * k)
			add(off, "RightWing1", 0, -60 * k, -20 * k)
			add(off, "LeftWing2", 0, 30 * k, 0)
			add(off, "RightWing2", 0, -30 * k, 0)
		elseif self.kind == "moon" then
			-- up out of the gate below
			extra = CFrame.new(0, -9 * (1 - u) ^ 2, 0)
			sampleKeys(ACTS.moon.land, 0, off)
		end
	end

	-- the pose
	local byName = rig.byName
	local mv = Vector3.zero
	for n, v in pairs(off) do
		if n == "move" then
			mv = Vector3.new(v[1], v[2], v[3])
		elseif v[1] ~= 0 or v[2] ~= 0 or v[3] ~= 0 then
			local i = byName[n]
			if i then L[i] = base[i] * ang(v[1], v[2], v[3]) end
		end
	end
	rig.move = self.baseMove * CFrame.new((shift + mv) * rig.scale)

	-- the baked signature, blended over all of it
	local sig = self.sig
	if sig then
		local st = self.t - sig.t0
		if st >= sig.len + 0.3 then
			self.sig = nil
		elseif st >= 0 then
			local wIn = if self.kind == "fused" then 1 else smooth(st / 0.22)
			local wOut = smooth((sig.len - st) / 0.28)
			rig:clip(min(st, sig.len), wIn * (if st > sig.len then 0 else wOut), sig.travel)
		elseif self.kind == "sky" then
			-- (the dash to the spot: diving, wings back)
			local k = smooth(min((self.t - (sig.t0 - sig.lead)) / 0.1, 1))
			local i1, i2 = byName.LeftWing1, byName.RightWing1
			if i1 and i2 then
				L[i1] = L[i1] * ang(0, 55 * k, 15 * k)
				L[i2] = L[i2] * ang(0, -55 * k, -15 * k)
			end
		end
	end

	-- the leaving
	local lv = self.leaving
	if lv then
		local u = clamp((self.t - lv.t0) / 0.9, 0, 1)
		if lv.how == "fuse" then
			rig:fade(u)
			rig:tint(Color3.new(1, 1, 1), u)
		elseif lv.how == "unfuse" then
			rig:fade(u)
			rig:tint(Color3.new(1, 1, 1), u)
			extra *= CFrame.new(0, 3 * u, 0)
		elseif lv.how == "break" then
			rig:fade(u * u)
			extra *= CFrame.new(0, -2.5 * u * u, 0) * CFrame.Angles(rad(12) * u, 0, rad(8) * u)
		else
			-- dissolving into motes, sinking a little
			rig:fade(u)
			extra *= CFrame.new(0, if self.kind == "sky" then 2 * u else -1.2 * u, 0)
		end
	end
	return extra
end

Beasts.ACTS = ACTS
return Beasts
