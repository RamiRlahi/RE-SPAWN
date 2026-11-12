--!strict
--[[
	SwordsmanController.luau
	Client side of the Swordsman (server: SwordsmanServer).

	  • The 4-hit rapier combo (lunge, riposte, double thrust, flèche): your
	    own are predicted (pose, blade trail, thrust / slash, whoosh) on
	    click; the server resolves hits and sends everyone else's over
	    SwordsmanFX.
	  • Skills: the dash for Sword Rush, the guard and riposte for Parry, the
	    held charge and needle lunge of Piercing Judgement (its echoes drawn
	    as phantom blades down the line),
	    and Blade Storm: en garde with the camera at the rapier's point, then
	    the chain (you flash from enemy to enemy as the server's timings
	    arrive).
	  • Every Swordsman effect for every player, in blue: thrusts, crescents,
	    rush streaks, the parry flash + "PARRY!", the pommel's impact, the
	    Judgement's charge and needle, the storm's lingering trails, darkened arena,
	    outline and the giant X.
	  • Momentum HUD: ten pips above the skill bar, "MOMENTUM MAX" at ten.
	Visuals are Neon + particles only (no lights).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local player = Players.LocalPlayer

local SwordsmanController = {}

-- ── Tuning (mirrors SwordsmanServer) ────────────────────────────────────────
local SWING_INTERVAL = 0.3
local COMBO_RESET = 1.0
local MOMENTUM_MAX = 10
local MOMENTUM_SPEED = 0.04
local STORM_WINDUP = 1.2
local RIPOSTE_REACH = 16     -- furthest the riposte's dash carries him
local RIPOSTE_TIME = 0.8     -- the riposte, recovery included

local WHITE = Color3.fromRGB(255, 255, 255)
local BLUE = Color3.fromRGB(90, 150, 255)
local FROST = Color3.fromRGB(195, 220, 255)

type Deps = {
	shake: (number, number) -> (),
	fovPunch: (number, number) -> (),
	getAim: (BasePart) -> Vector3,
}
local deps: Deps

local localStep = 0
local lastSwing = 0
local busyUntil = 0
-- (a dash cuts the move short: free to cast again at once)
(require(script.Parent:WaitForChild("DashController")) :: any).OnCancel(function(c: Model)
	if c == game:GetService("Players").LocalPlayer.Character then busyUntil = 0 end
end)
local guardToken = 0 -- (a riposte outlasts the guard's window)

local function momentum(): number
	return tonumber(player:GetAttribute("SW_Momentum")) or 0
end

local function isSwordsman(): boolean
	return player:GetAttribute("SelectedClass") == "swordsman"
end

-- ── VFX pieces ──────────────────────────────────────────────────────────────
local function neon(props: { [string]: any }): BasePart
	return ClassFX.Neon(props)
end

-- A crescent slash (SwordFX ribbon): drawn in along the swing (`sweep` 1 =
-- right→left, -1 = left→right), thin fading tail, bright thick head, white
-- edge over a blue glow; it eases outward as it fades. `cf` is the arc's
-- centre and facing (bulging toward cf's -Z; roll cf 90° about Z for a
-- vertical slash).
local function crescent(cf: CFrame, radius: number, arc: number, color: Color3, thickness: number, life: number, sweep: number?)
	SwordFX.Arc({ cf = cf, radius = radius, arc = arc, sweep = sweep, width = thickness * 2.4, color = color, life = life })
end

-- A comet streak (thrust, dashes, Blade Storm); `lines` adds speed lines.
local function streak(a: Vector3, b: Vector3, width: number, color: Color3, linger: number, lines: number?)
	SwordFX.Streak(a, b, width * 2, color, linger, lines)
end

local function trail(char: Model, seconds: number)
	local tool = char:FindFirstChild("Longsword")
	local t = tool and tool:FindFirstChild("SwordTrail", true)
	if t and t:IsA("Trail") then
		t.Enabled = true
		task.delay(seconds, function() if t.Parent then t.Enabled = false end end)
	end
end

local function rootOf(char: Model?): BasePart?
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- A pop-up word over a character ("PARRY!", "EMPOWERED").
local function popWord(char: Model, text: string, color: Color3, size: number)
	local root = rootOf(char)
	if not root then return end
	local bb = Instance.new("BillboardGui")
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(220, 60)
	bb.StudsOffset = Vector3.new(0, 4.2, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = ClassFX.Folder()
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.Arcade
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeColor3 = Color3.fromRGB(8, 14, 40)
	l.TextStrokeTransparency = 0.2
	l.Parent = bb
	local sc = Instance.new("UIScale")
	sc.Scale = 1.8
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.4),
		{ StudsOffset = Vector3.new(0, 6, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(bb, 1.1)
end

-- ── Poses (CastPoses character space) ──────────────────────────────────────
-- Signs: W ry + turns the torso LEFT (the hips turn back, so the feet stay
-- planted); RS ry + rolls the sword arm so the blade swings to the left;
-- RS rz - brings the arm in across the body (LS: rz +). A fencer stands side
-- on, right shoulder to the target (W +), the off hand raised up and back.
-- The legs come from CastPoses.body, so the feet stay on the floor.
--
-- The rapier's grip turns (gripTo) between two holds: k = 0, the blade out
-- of the fist at right angles to the arm (cuts, the riposte); k = 1, the
-- blade running on along the arm (thrusts and the guard: arm level = point
-- straight at the target).
local QUAD, QUART = Enum.EasingStyle.Quad, Enum.EasingStyle.Quart
local body = CastPoses.body

-- Each move that takes the grip gets a new `seq`; its later grip changes
-- (gripThen, gripBack) only happen if no other move has taken it since. A
-- `flourish` (the parry guard's wrist play) turns the blade on top of the
-- hold until the next move takes the grip.
type GripState = { tool: Tool, base: CFrame, k: number, from: number, target: number, t0: number, dur: number,
	seq: number, flourish: ((number) -> CFrame)?, f0: number, dirty: boolean }
local grips: { [Tool]: GripState } = {}

local function gripState(char: Model): GripState?
	local tool = char:FindFirstChild("Longsword")
	if not (tool and tool:IsA("Tool")) then return nil end
	local g = grips[tool]
	if not g then
		g = { tool = tool, base = tool.Grip, k = 0, from = 0, target = 0, t0 = 0, dur = 0, seq = 0, f0 = 0, dirty = false }
		grips[tool] = g
	end
	return g
end

local function setGrip(s: GripState, target: number, dur: number)
	s.from, s.target, s.t0, s.dur = s.k, target, os.clock(), math.max(dur, 0.01)
end

local function gripTo(char: Model, target: number, dur: number): number
	local s = gripState(char)
	if not s then return 0 end
	s.seq += 1
	if s.flourish then
		s.flourish = nil
		s.dirty = true
	end
	setGrip(s, target, dur)
	return s.seq
end

-- A later turn of the grip in the same move (`seq` from its gripTo).
local function gripThen(char: Model, seq: number, after: number, target: number, dur: number)
	task.delay(after, function()
		local s = gripState(char)
		if s and s.seq == seq then setGrip(s, target, dur) end
	end)
end

-- Back to the cutting hold after `after` seconds, unless another move has
-- taken the grip since.
local function gripBack(char: Model, after: number)
	local s = gripState(char)
	if s then gripThen(char, s.seq, after, 0, 0.12) end
end

local function gripFlourish(char: Model, fn: (number) -> CFrame)
	local s = gripState(char)
	if not s then return end
	s.flourish, s.f0 = fn, os.clock()
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for tool, g in pairs(grips) do
		if not tool.Parent then
			grips[tool] = nil
		elseif g.k ~= g.target or g.flourish or g.dirty then
			g.dirty = false
			local a = math.clamp((now - g.t0) / g.dur, 0, 1)
			local e = -(math.cos(math.pi * a) - 1) / 2
			g.k = if a >= 1 then g.target else g.from + (g.target - g.from) * e
			local cf = g.base * CFrame.Angles(math.rad(90) * g.k, 0, 0)
			local f = g.flourish
			if f then cf *= f(now - g.f0) end
			tool.Grip = cf
		end
	end
end)

-- ── Fencing ─────────────────────────────────────────────────────────────────
-- Real fencing form: side on to the target (torso turned left, right
-- shoulder forward), RIGHT foot leading. On guard the knees are bent, the
-- sword arm half-extended with the point at the target's chest and the back
-- arm curled up behind the head. The lunge: the arm extends FIRST, then the
-- front foot kicks out long and the back leg drives straight; the torso stays
-- upright, the arm locks level so the blade continues it straight at the
-- target, and the back arm snaps down along the back leg. Head on the
-- target throughout.
--
-- The arms are AIMED in world terms (`elev` from hanging: 90 = level; `yaw`
-- + = to the left of the target; `out` + = away from the body) and turned
-- back into the shoulder angles under whatever lean / twist the torso has,
-- so the point stays on the target however the body moves. The rapier's
-- blade runs along the arm for all of it (gripTo 1).
type Aim = { number } -- { elev, yaw, out }

local function aimed(lean: number, twist: number, aim: Aim, left: boolean?): { number }
	local out = if left then -(aim[3] or 0) else (aim[3] or 0)
	local world = CFrame.Angles(0, math.rad(aim[2] or 0), 0) * CFrame.Angles(math.rad(aim[1]), 0, 0)
		* CFrame.Angles(0, 0, math.rad(out))
	local torso = CFrame.fromEulerAnglesXYZ(math.rad(lean), math.rad(twist), 0)
	local rx, ry, rz = (torso:Inverse() * world):ToEulerAnglesXYZ()
	return { math.deg(rx), math.deg(ry), math.deg(rz) }
end

-- A fencer's body: right foot `fwd` degrees forward, left foot `back`
-- degrees back (negative swaps them: the flèche's crossover), the hips
-- dropping as far as the stride lowers them, the weight slid by `sz`.
local function fencer(lean: number, twist: number, fwd: number, back: number, sz: number, arm: Aim, off: Aim,
	headPitch: number?): { [string]: { number } }
	local p = body(lean, twist, -back, -fwd, nil, 7, 0, sz)
	p.RS = aimed(lean, twist, arm)
	p.LS = aimed(lean, twist, off, true)
	p.N = { (headPitch or 0) - lean * 0.6, -twist * 0.85, 0 }
	return p
end

-- The extension that starts every attack: arm straight, nothing else yet.
local EXTEND = fencer(-5, 62, 22, 26, 0, { 92, 0, 0 }, { 135, 10, 20 })
-- The lunge (depth 0..1): the front foot out long, the back leg straight.
local function lunge(depth: number): { [string]: { number } }
	return fencer(-8 - 8 * depth, 66, 34 + 22 * depth, 34 + 20 * depth, -0.6 - 0.9 * depth,
		{ 94, 0, 0 }, { -40, 6, 20 }, 4)
end
local function lungeHold(depth: number): { [string]: { number } }
	return fencer(-6 - 8 * depth, 64, 32 + 22 * depth, 32 + 20 * depth, -0.55 - 0.85 * depth,
		{ 92, 0, 0 }, { -32, 6, 18 }, 4)
end

local function swingPose(char: Model, step: number, speed: number?)
	local s = speed or 1
	local opts = { speed = s }
	gripTo(char, 1, 0.04 / s)
	if step == 1 then
		-- Extension, then the lunge.
		CastPoses.play(char, {
			{ dur = 0.06, style = QUAD, pose = EXTEND },
			{ dur = 0.07, style = QUART, pose = lunge(0.6) },
			{ dur = 0.15, pose = lungeHold(0.6) },
		}, 0.22, nil, opts)
	elseif step == 2 then
		-- Parry and riposte: the blade beats across to the inside (quarte),
		-- then a short straight riposte from guard, no full lunge.
		CastPoses.play(char, {
			{ dur = 0.06, style = QUAD, pose = fencer(-3, 60, 20, 24, 0.1, { 82, 28, 6 }, { 145, 10, 15 }) },
			{ dur = 0.06, style = QUART, pose = fencer(-7, 64, 30, 30, -0.45, { 93, -2, 0 }, { 120, 10, 20 }, 2) },
			{ dur = 0.15, pose = fencer(-6, 63, 28, 28, -0.4, { 91, 0, 0 }, { 125, 10, 20 }, 2) },
		}, 0.22, nil, opts)
	elseif step == 3 then
		-- One-two: a feint to the outside, the point slipping round under
		-- the parry (disengage), then the real lunge.
		CastPoses.play(char, {
			{ dur = 0.05, style = QUAD, pose = fencer(-5, 62, 24, 26, -0.1, { 90, -14, 0 }, { 135, 10, 20 }) },
			{ dur = 0.05, style = QUAD, pose = fencer(-5, 62, 24, 26, -0.1, { 86, 10, 0 }, { 135, 10, 20 }) },
			{ dur = 0.07, style = QUART, pose = lunge(0.75) },
			{ dur = 0.13, pose = lungeHold(0.75) },
		}, 0.22, nil, opts)
	else
		-- Flèche: arm extended first, then the body falls forward past the
		-- point and the back foot crosses over in front — a running attack
		-- (he's carried forward).
		local fleche = CastPoses.lift(fencer(-28, 55, -30, -38, -1.2, { 95, 0, 0 }, { -20, 0, 30 }, 10), 0.2)
		local landing = fencer(-20, 52, -24, -30, -1.1, { 92, 0, 0 }, { -15, 0, 28 }, 8)
		CastPoses.play(char, {
			{ dur = 0.07, style = QUAD, pose = EXTEND },
			{ dur = 0.07, style = QUART, pose = fleche },
			{ dur = 0.2, pose = landing },
		}, 0.3, nil, opts)
	end
	gripBack(char, 0.42 / s)
end

-- Skill poses (shared by your cast and everyone else's view of it).
local function rushPose(char: Model, t: number)
	-- A dashing cut: coiled low to the right, then flat through the target,
	-- the blade cutting right to left (as the cuts along the dash) and swept
	-- out behind on the left.
	gripTo(char, 0, 0.04)
	CastPoses.play(char, {
		{ dur = 0.05, style = QUAD, pose = body(18, -45, 30, 30,
			{ N = { 0, 35, 0 }, RS = { 25, -95, 30 }, LS = { 40, 0, 25 } }, 10, 0.15, 0.2) },
		{ dur = t, style = Enum.EasingStyle.Cubic, pose = body(-36, 35, 48, 52,
			{ N = { 22, -25, 0 }, RS = { 20, 115, -45 }, LS = { -45, 0, -70 } }, 8, 0, -0.6) },
		{ dur = 0.16, pose = body(-16, 28, 30, 30,
			{ N = { 10, -18, 0 }, RS = { 15, 90, -35 }, LS = { -20, 0, -45 } }, 8) },
	}, 0.24)
end

-- Parry. The guard: side on and sunk onto the back leg, the blade held out
-- diagonally at the target (point up), the free arm back for balance. Not
-- still: the wrist plays the point through small circles in front of him
-- (two a loop, tightening and opening every other loop), once a loop it
-- flicks out to the side and eases back; the arm and the upper body follow
-- it a little, the feet stay put. Every piece repeats on the loop, so it
-- runs seamlessly for as long as the guard is up.
local RIPOSTE_GUARD = fencer(4, 68, 24, 30, 0.35, { 96, 6, 4 }, { -35, 0, 30 }, -4)
local FLOURISH_LOOP = 1.2
-- (the flick: out fast over the first quarter of its stretch, back slower)
local function flourishFlick(t: number): number
	local u = (t % FLOURISH_LOOP) / FLOURISH_LOOP
	if u < 0.55 or u > 0.85 then return 0 end
	local x = (u - 0.55) / 0.3
	return if x < 0.25 then math.sin(x / 0.25 * math.pi / 2) else math.cos((x - 0.25) / 0.75 * math.pi / 2)
end
local function flourishGrip(t: number): CFrame
	local w = 2 * math.pi / (FLOURISH_LOOP / 2)
	local fade = math.min(t / 0.2, 1)
	local a = math.rad(9 + 5 * math.sin(math.pi * t / FLOURISH_LOOP)) * fade
	return CFrame.Angles(a * math.sin(w * t), a * math.cos(w * t) + math.rad(28) * flourishFlick(t) * fade, 0)
end
local function guardPose(char: Model, window: number)
	local seq = gripTo(char, 0.55, 0.06)
	gripFlourish(char, flourishGrip)
	local w = 2 * math.pi / (FLOURISH_LOOP / 2)
	CastPoses.play(char, {
		{ dur = 0.08, style = Enum.EasingStyle.Back, pose = RIPOSTE_GUARD },
		{ dur = window, pose = RIPOSTE_GUARD, wobble = function(t: number)
			local fade = math.min(t / 0.2, 1)
			local fl = flourishFlick(t)
			local c, s = math.cos(w * t + 0.6), math.sin(w * t + 0.6)
			return {
				RS = { 3 * s * fade, (4 * c + 8 * fl) * fade, 0 },
				W = { 0.6 * math.sin(w * t) * fade, (1.5 * math.sin(w * t / 2) + 2.5 * fl) * fade, 0 },
				N = { 0, -1.5 * fl * fade, 0 },
			}
		end },
	}, 0.2)
	-- (the window over and nothing came: back to the cutting hold)
	task.delay(window, function()
		local st = gripState(char)
		if st and st.seq == seq then gripTo(char, 0, 0.15) end
	end)
end

-- The riposte (a parry landed): a flick of the wrist beats the blow aside,
-- he sinks and drives off the back foot, low and leaning in with the sword
-- tucked close (the blade low along the arm) and the free arm flung back,
-- then plants the front foot and turns the shoulder through as the wrist
-- tips the blade back over the forearm, so the pommel leads into the chest.
-- Held, then back on guard. The pommel lands 0.3 s after the parry
-- (SwordsmanServer's RIPOSTE_HIT).
local RIPOSTE_DEFLECT = fencer(4, 76, 24, 30, 0.35, { 100, 24, 4 }, { -38, 0, 30 }, -4)
local RIPOSTE_SINK = fencer(-14, 52, 30, 38, 0.1, { 55, -6, 14 }, { -50, 0, 28 }, 4)
local RIPOSTE_DRIVE = fencer(-28, 38, 40, 48, -0.6, { 60, -6, 14 }, { -75, 0, 25 }, 4)
local RIPOSTE_STRIKE = fencer(-14, 80, 38, 34, -0.75, { 91, -4, 0 }, { -55, 0, 32 }, 2)
local RIPOSTE_HOLD = fencer(-12, 78, 36, 32, -0.7, { 89, -4, 0 }, { -50, 0, 30 }, 2)
local POMMEL_GRIP = -0.68 -- the blade back over the forearm, the pommel out front
local function ripostePose(char: Model)
	-- (the flourish stops dead: the wrist snaps to the parry)
	local seq = gripTo(char, 0.3, 0.04)
	gripThen(char, seq, 0.05, 0.75, 0.08)
	gripThen(char, seq, 0.21, POMMEL_GRIP, 0.08)
	CastPoses.play(char, {
		{ dur = 0.05, style = QUART, pose = RIPOSTE_DEFLECT },
		{ dur = 0.06, style = QUAD, pose = RIPOSTE_SINK },
		{ dur = 0.11, style = QUAD, pose = RIPOSTE_DRIVE },
		{ dur = 0.08, style = QUART, pose = RIPOSTE_STRIKE },
		{ dur = 0.22, pose = RIPOSTE_HOLD },
	}, 0.3)
	gripThen(char, seq, RIPOSTE_TIME - 0.2, 0, 0.2)
end

-- ── Q: Piercing Judgement ───────────────────────────────────────────────────
-- Held: a half step back into a duellist's guard (side on, knees bent, weight
-- on the back leg, the arm out straight so the point is aimed right down the
-- line, the free arm back for balance), quieter and quieter as the charge
-- builds until he's dead still at full. Released: the lunge (the back leg
-- drives, the torso tips in, the arm locks), held, then drawn back to guard.
local JUDGE = { full = 2.4, empFull = 1.4, still = 1.6, lunge = 4, fullLunge = 11,
	length = 16, fullLength = 32, hit = 0.07 } -- (mirrors SwordsmanServer)
local JUDGE_GUARD = fencer(-2, 66, 26, 30, 0.45, { 90, 0, 0 }, { -40, 0, 30 })
local judgeCharge: { [Model]: number } = {} -- 0..1 while a charge is held

local function judgeGuardPose(char: Model, seconds: number)
	gripTo(char, 1, 0.14)
	CastPoses.play(char, {
		{ dur = 0.18, style = Enum.EasingStyle.Sine, pose = JUDGE_GUARD },
		{ dur = seconds, pose = JUDGE_GUARD, wobble = function(t: number)
			local b = math.sin(t * 2.4) * 0.7 * (1 - (judgeCharge[char] or 0))
			return { W = { b, 0, 0 }, N = { -b * 0.5, 0, 0 } }
		end },
	}, 0.2)
end

local function judgeThrustPose(char: Model, c: number)
	gripTo(char, 1, 0.03)
	local d = 0.95 + 0.25 * c
	CastPoses.play(char, {
		{ dur = 0.07, style = QUART, pose = lunge(d) },
		{ dur = 0.3 + 0.1 * c, pose = lungeHold(d) },
		{ dur = 0.24, style = Enum.EasingStyle.Sine, pose = JUDGE_GUARD },
	}, 0.3)
	gripBack(char, 0.75)
end

-- Blade Storm's guard: on guard, the arm out straight so the point is aimed
-- right down the camera (which sits just past it).
local EN_GARDE = fencer(-3, 60, 22, 26, 0.1, { 90, 0, 0 }, { 150, 10, 15 })
local function enGardePose(char: Model, seconds: number)
	gripTo(char, 1, 0.15)
	CastPoses.play(char, {
		{ dur = 0.25, style = Enum.EasingStyle.Back, pose = EN_GARDE },
		{ dur = math.max(seconds - 0.25, 0.05), pose = EN_GARDE, wobble = function(t: number)
			local b = math.sin(t * 2.4) * 1
			return { W = { b, 0, 0 }, N = { -b * 0.5, 0, 0 } }
		end },
	}, 0.15)
end

-- A thrust: a streak of light shot out along the point, with a burst where
-- it ends.
local function thrustFX(root: BasePart, dir: Vector3, length: number, width: number, delay: number)
	task.delay(delay, function()
		if not root.Parent then return end
		local p = root.Position + Vector3.new(0, 0.6, 0)
		streak(p + dir * 2, p + dir * length, width, BLUE, 0.05)
		ClassFX.Burst(p + dir * length, FROST, 6, 10, ClassFX.TEX_SPARK, 0.25, 0.22)
	end)
end

-- What each combo hit leaves in front of the attacker.
local function comboVFX(char: Model, step: number, dir: Vector3)
	local root = rootOf(char)
	if not root then return end
	local look = CFrame.lookAt(root.Position, root.Position + dir)
	trail(char, 0.3)
	if step == 1 then
		thrustFX(root, dir, 13, 0.45, 0.07)
	elseif step == 2 then
		-- Right-to-left, tilted slightly.
		task.delay(0.06, crescent, look * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(-8)), 5.2, 140, BLUE, 0.7, 0.2, 1)
	elseif step == 3 then
		thrustFX(root, dir, 12, 0.4, 0.05)
		thrustFX(root, dir, 13, 0.45, 0.15)
	else
		-- The flèche: a long, heavy streak and a ring of light at the point.
		thrustFX(root, dir, 16, 0.65, 0.08)
		task.delay(0.12, function()
			if not root.Parent then return end
			SwordFX.Stars(root.Position + dir * 4 + Vector3.new(0, 0.6, 0), 10, 16, BLUE)
		end)
	end
end

-- ── Momentum HUD ────────────────────────────────────────────────────────────
local hud: ScreenGui? = nil
local pips: { Frame } = {}
local maxLabel: TextLabel? = nil

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "SwordsmanMomentum"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -128)
	row.Size = UDim2.fromOffset(10 * 22, 26)
	row.BackgroundTransparency = 1
	row.Parent = g
	for i = 1, MOMENTUM_MAX do
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.new(0, (i - 0.5) * 22, 0.5, 0)
		d.Size = UDim2.fromOffset(11, 11)
		d.Rotation = 45
		d.BackgroundColor3 = Color3.fromRGB(20, 24, 38)
		d.BorderSizePixel = 0
		d.Parent = row
		local s = Instance.new("UIStroke")
		s.Color = BLUE
		s.Thickness = 1.2
		s.Transparency = 0.3
		s.Parent = d
		pips[i] = d
	end
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 0, -2)
	lbl.Size = UDim2.fromOffset(260, 22)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Arcade
	lbl.TextSize = 20
	lbl.Text = "MOMENTUM MAX"
	lbl.TextColor3 = BLUE
	lbl.TextStrokeTransparency = 0.3
	lbl.Visible = false
	lbl.Parent = row
	maxLabel = lbl
end

local function refreshHud()
	if not hud then return end
	hud.Enabled = isSwordsman() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	local m = momentum()
	for i, d in ipairs(pips) do
		d.BackgroundColor3 = if i <= m then (if m >= MOMENTUM_MAX then WHITE else BLUE) else Color3.fromRGB(20, 24, 38)
	end
	if maxLabel then maxLabel.Visible = m >= MOMENTUM_MAX end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
-- Returns true when the Swordsman handled the click.
function SwordsmanController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1) * (1 + MOMENTUM_SPEED * momentum())
	if now - lastSwing < SWING_INTERVAL / speed then return true end
	localStep = if now - lastSwing > COMBO_RESET then 1 else (localStep % 4) + 1
	lastSwing = now
	local dir = deps.getAim(root)
	dir = Vector3.new(dir.X, 0, dir.Z)
	dir = if dir.Magnitude > 0.01 then dir.Unit else root.CFrame.LookVector
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	swingPose(char, localStep, speed)
	comboVFX(char, localStep, dir)
	ClassFX.Sound("whoosh", root, 0.6, if localStep == 4 then 0.85 else 1.1 + localStep * 0.05)
	-- The lunges carry him forward (not off a ledge); the flèche furthest.
	local push = if localStep == 4 then 46 elseif localStep == 2 then 0 else 22
	if push > 0 and SafeMove.ClampToFloor(root, dir, 4) >= 4 then
		root.AssemblyLinearVelocity = dir * push + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	end
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function SwordsmanController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- A horizontal-only dash, like the Gunslinger's roll. It stops short of
-- walls / steps in the way and of ledges / pits (never carries you off the
-- floor), holds its height for the dash and ends back on the floor.
local function dash(root: BasePart, dir: Vector3, dist: number, t: number)
	local stand = SafeMove.StandHeight(root)
	local start = root.CFrame
	local full = dist
	dist = math.min(SafeMove.ClampDash(root, dir, dist), SafeMove.ClampToFloor(root, dir, dist))
	-- (cut short: same speed, shorter dash)
	if full > 0 then t = t * math.max(dist / full, 0.25) end
	local holdY = RunService.Heartbeat:Connect(function()
		if not root.Parent then return end
		local v = root.AssemblyLinearVelocity
		if v.Y < 0 then root.AssemblyLinearVelocity = Vector3.new(v.X, 0, v.Z) end
	end)
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	lv.VectorVelocity = dir * (dist / t)
	lv.Parent = root
	task.delay(t, function()
		holdY:Disconnect()
		lv:Destroy()
		att:Destroy()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			SafeMove.SnapToFloor(root, stand)
			-- Last resort: no floor under the end of the dash at all → back to
			-- where it started instead of falling.
			if not SafeMove.HasFloor(root) then
				root.CFrame = start
				root.AssemblyLinearVelocity = Vector3.zero
			end
		end
	end)
end

-- An instant dash: there in the same frame (walls and ledges still stop it).
local function blink(root: BasePart, dir: Vector3, dist: number)
	local stand = SafeMove.StandHeight(root)
	local start = root.CFrame
	dist = math.min(SafeMove.ClampDash(root, dir, dist), SafeMove.ClampToFloor(root, dir, dist))
	root.CFrame = start + dir * dist
	root.AssemblyLinearVelocity = Vector3.new(0, math.max(root.AssemblyLinearVelocity.Y, 0), 0)
	SafeMove.SnapToFloor(root, stand)
	if not SafeMove.HasFloor(root) then
		root.CFrame = start
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

-- Blade Storm's wind-up shot: the camera just past the rapier's point,
-- looking back up the blade at his face, creeping in.
local function tipCamera(char: Model, seconds: number)
	local cam = Workspace.CurrentCamera
	local hum = char:FindFirstChildOfClass("Humanoid")
	local ok, Iso = pcall(function() return require(script.Parent:WaitForChild("IsometricCamera")) :: any end)
	local wasIso = ok and Iso and Iso.IsActive and Iso.IsActive()
	if wasIso then Iso.Pause() end
	cam.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	RunService:BindToRenderStep("SwordTipCam", Enum.RenderPriority.Camera.Value + 5, function()
		local tool = char:FindFirstChild("Longsword")
		local tip = tool and tool:FindFirstChild("BladeTip", true)
		local head = char:FindFirstChild("Head") :: BasePart?
		if not (tip and tip:IsA("Attachment") and head) then return end
		local a = math.clamp((os.clock() - t0) / seconds, 0, 1)
		local e = 1 - (1 - a) ^ 2
		local tipPos = tip.WorldPosition
		local back = head.Position - tipPos
		if back.Magnitude < 0.1 then return end
		local eye = tipPos - back.Unit * (2.2 - 1.2 * e) + Vector3.new(0, 0.3, 0)
		cam.CFrame = CFrame.lookAt(eye, head.Position)
		cam.FieldOfView = 55 - 15 * e
	end)
	task.delay(seconds, function()
		RunService:UnbindFromRenderStep("SwordTipCam")
		if wasIso then
			Iso.Resume(0.4)
		else
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = 70
			if hum then cam.CameraSubject = hum end
		end
	end)
end

-- ── Piercing Judgement: the charge ──────────────────────────────────────────
-- Everything gathers on the rapier's point and grows with the charge (c =
-- held / full):
--   from the start  specks of wind drifting in to the point, a faint ring of
--                   moving air round the blade, a pinprick of light;
--   c ≥ 0.2         thin streams of wind spiralling up the blade (then a
--                   second, wider helix turning the other way), long wind
--                   lines rushing in, motes of light orbiting the point, two
--                   slow outer rings, the edge glowing, a sigil drawing itself
--                   on the floor, gusts wrapping round him, light rising off
--                   him, dust lifting;
--   c ≥ 0.6         thin rings of energy turning round the blade near the
--                   point, everything faster and tighter, arcs and sparks
--                   crackling up the blade, a turning star at the blazing
--                   point, grit rising at his feet;
--   full            a white flash at the point, the rings pulled in tight,
--                   arcs leaping ring to ring, a shockwave round him, then a
--                   pulse from the point and the floor every beat it's held.
-- One set per charging character (not per hit), so nothing here is budgeted.
local PALE = Color3.fromRGB(215, 235, 255)
local ELECTRIC = Color3.fromRGB(60, 150, 255)
local TERRAIN = Workspace.Terrain

local function smooth(a: number, b: number, x: number): number
	local t = math.clamp((x - a) / (b - a), 0, 1)
	return t * t * (3 - 2 * t)
end

local function anchor(): Attachment
	local a = Instance.new("Attachment")
	a.Name = "JudgeFX"
	a.Parent = TERRAIN
	return a
end

local function glowBeam(a0: Attachment, a1: Attachment, color: Color3, width: number, segments: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = segments
	b.Width0, b.Width1 = width, width
	b.Color = ColorSequence.new(color)
	b.Transparency = NumberSequence.new(1)
	b.Parent = a0
	return b
end

-- A thin ring round the blade's axis: two half circles (Bézier beams).
type Ring = { a: Attachment, b: Attachment, h1: Beam, h2: Beam }
local function newRing(color: Color3, width: number): Ring
	local a, b = anchor(), anchor()
	local h1, h2 = glowBeam(a, b, color, width, 14), glowBeam(b, a, color, width, 14)
	return { a = a, b = b, h1 = h1, h2 = h2 }
end
-- `cf`: the ring's centre, its Z along the blade; `tr`: 1 = gone. The two
-- halves fade differently so the turning shows.
local function placeRing(r: Ring, cf: CFrame, radius: number, spin: number, tr: number)
	local c, s = math.cos(spin), math.sin(spin)
	local pa = Vector3.new(c, s, 0) * radius
	local t = Vector3.new(-s, c, 0)
	local k = radius * 4 / 3
	r.a.WorldCFrame = cf * CFrame.fromMatrix(pa, t, Vector3.zAxis)
	r.b.WorldCFrame = cf * CFrame.fromMatrix(-pa, t, Vector3.zAxis)
	r.h1.CurveSize0, r.h1.CurveSize1 = k, -k
	r.h2.CurveSize0, r.h2.CurveSize1 = -k, k
	r.h1.Transparency = NumberSequence.new(math.clamp(tr, 0, 1))
	r.h2.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, math.clamp(tr + 0.15, 0, 1)),
		NumberSequenceKeypoint.new(0.5, math.clamp(tr + 0.55, 0, 1)),
		NumberSequenceKeypoint.new(1, math.clamp(tr + 0.15, 0, 1)),
	})
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = ClassFX.TEX_SPARK
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function hidden(size: Vector3, cf: CFrame): BasePart
	return neon({ Size = size, Transparency = 1, CFrame = cf })
end

type JudgeFx = { stop: (released: boolean) -> () }

-- (`clock`: the time it reads, for tests that hold it at one stage)
local function judgeChargeFx(char: Model, full: number, clock: (() -> number)?): JudgeFx
	local now = clock or os.clock
	local tool = char:FindFirstChild("Longsword")
	local blade = tool and tool:FindFirstChild("Blade", true) :: BasePart?
	local tip = tool and tool:FindFirstChild("BladeTip", true) :: Attachment?
	local edge = tool and tool:FindFirstChild("Edge", true) :: BasePart?
	local root = rootOf(char)
	if not (blade and tip and root) then return { stop = function(_released: boolean) end } end
	local t0 = now()
	local owned: { Instance } = {}
	local function own<T>(x: T): T
		table.insert(owned, x :: any)
		return x
	end
	local emitters: { ParticleEmitter } = {}
	local function emit(parent: Instance, props: { [string]: any }): ParticleEmitter
		local e = emitter(parent, props)
		table.insert(emitters, e)
		return e
	end
	local function newTrail(a0: Attachment, a1: Attachment, life: number, color: Color3): Trail
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.FaceCamera = true
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.Lifetime = life
		tr.MinLength = 0
		tr.WidthScale = NumberSequence.new(1, 0.3)
		tr.Color = ColorSequence.new(WHITE, color)
		tr.Transparency = NumberSequence.new(1)
		tr.Enabled = false
		tr.Parent = a0
		return tr
	end
	local GLOW_TEX = "rbxasset://textures/particles/forcefield_glow_main.dds"

	-- ── at the point ──
	-- a hot core in a soft glow, and (overcharged) a turning star of light
	local point = own(neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.08, Color = WHITE, CFrame = tip.WorldCFrame }))
	local glow = emit(point, {
		Texture = GLOW_TEX, LockedToPart = true, Color = ColorSequence.new(WHITE, PALE),
		Lifetime = NumberRange.new(0.12), Speed = NumberRange.new(0), Rate = 40, Transparency = NumberSequence.new(0.25),
	})
	local star = emit(point, {
		LockedToPart = true, Color = ColorSequence.new(WHITE, PALE), Lifetime = NumberRange.new(0.3),
		Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 1) }),
	})
	-- specks of wind drawn in to the point, and long wind lines rushing in
	local well = own(hidden(Vector3.one * 3.2, tip.WorldCFrame))
	local specks = emit(well, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Color = ColorSequence.new(WHITE, PALE), Lifetime = NumberRange.new(0.4),
		Speed = NumberRange.new(4), Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(0.7, 0.18), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.2), NumberSequenceKeypoint.new(1, 0) }),
	})
	local wide = own(hidden(Vector3.one * 7, tip.WorldCFrame))
	local lines = emit(wide, {
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-2.2),
		Color = ColorSequence.new(WHITE, PALE), Lifetime = NumberRange.new(0.35),
		Speed = NumberRange.new(10), Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.12), NumberSequenceKeypoint.new(1, 0.02) }),
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 0.6) }),
	})
	-- motes of light on tilted orbits round the point
	type Mote = { part: BasePart, a0: Attachment, a1: Attachment, trail: Trail, tilt: CFrame, r: number, w: number, phase: number }
	local motes: { Mote } = {}
	for i = 1, 6 do
		local m = own(neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.09, Color = PALE, Transparency = 1, CFrame = tip.WorldCFrame }))
		local a0, a1 = own(anchor()), own(anchor())
		table.insert(motes, { part = m, a0 = a0, a1 = a1, trail = newTrail(a0, a1, 0.14, ELECTRIC),
			tilt = CFrame.Angles(math.rad(25 + i * 22), math.rad(i * 61), 0), r = 0.55 + 0.08 * (i % 3), w = 5 + i * 0.7 * (if i % 2 == 0 then -1 else 1),
			phase = i * 1.05 })
	end

	-- ── round the blade ──
	-- the ring of moving air, the energy rings (two big slow outer ones last)
	local air = newRing(PALE, 0.07)
	own(air.a); own(air.b)
	local RING_BACK = { 0.35, 0.8, 1.3, 1.9, 0.9 }
	local RING_RAD = { 0.3, 0.42, 0.55, 0.7, 0.95 }
	local rings = { newRing(ELECTRIC, 0.06), newRing(WHITE, 0.05), newRing(ELECTRIC, 0.05), newRing(PALE, 0.04), newRing(PALE, 0.035) }
	for _, r in ipairs(rings) do own(r.a); own(r.b) end
	-- the wind streams spiralling up the blade: an inner helix and an outer one
	-- turning the other way
	type Stream = { a0: Attachment, a1: Attachment, trail: Trail, u: number, phase: number, outer: boolean }
	local streams: { Stream } = {}
	for i = 1, 6 do
		local a0, a1 = own(anchor()), own(anchor())
		table.insert(streams, { a0 = a0, a1 = a1, trail = newTrail(a0, a1, 0.2, PALE), u = ((i - 1) % 3) / 3,
			phase = (i - 1) * math.pi * 2 / 3, outer = i > 3 })
	end
	-- fine arcs up the blade (and, at full, ring to ring), two at once
	local arcSets: { { pts: { Attachment }, beams: { Beam } } } = {}
	for _ = 1, 2 do
		local pts: { Attachment } = {}
		for _ = 1, 5 do table.insert(pts, own(anchor())) end
		local beams: { Beam } = {}
		for i = 1, 4 do table.insert(beams, glowBeam(pts[i], pts[i + 1], WHITE, 0.035, 1)) end
		table.insert(arcSets, { pts = pts, beams = beams })
	end
	-- electric sparks crackling along the blade
	local along_ = own(hidden(Vector3.new(0.15, 0.15, 3.6), blade.CFrame))
	local crackle = emit(along_, {
		Shape = Enum.ParticleEmitterShape.Box, Color = ColorSequence.new(WHITE, ELECTRIC),
		Lifetime = NumberRange.new(0.08, 0.18), Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) }),
		Drag = 6,
	})

	-- ── round him ──
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local down = Workspace:Raycast(root.Position, Vector3.new(0, -8, 0), params)
	local floorY = if down then down.Position.Y else root.Position.Y - 3
	local function floorAt(): Vector3 return Vector3.new(root.Position.X, floorY + 0.12, root.Position.Z) end
	-- a sigil on the floor: three rings, the middle one turning against the others
	local SIGIL_R = { 2.4, 3.1, 3.5 }
	local sigil = { newRing(ELECTRIC, 0.08), newRing(PALE, 0.05), newRing(ELECTRIC, 0.12) }
	for _, r in ipairs(sigil) do own(r.a); own(r.b) end
	-- wind wrapping round him
	type Gust = { a0: Attachment, a1: Attachment, trail: Trail, phase: number, h: number }
	local gusts: { Gust } = {}
	for i = 1, 3 do
		local a0, a1 = own(anchor()), own(anchor())
		table.insert(gusts, { a0 = a0, a1 = a1, trail = newTrail(a0, a1, 0.35, PALE), phase = i * 2.1, h = -1.6 + i * 1.1 })
	end
	-- light rising off him
	local aura = own(hidden(Vector3.new(2, 4.5, 1.2), root.CFrame))
	local rising = emit(aura, {
		Shape = Enum.ParticleEmitterShape.Box, Color = ColorSequence.new(PALE, ELECTRIC),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(1, 2.5), EmissionDirection = Enum.NormalId.Top,
		SpreadAngle = Vector2.new(10, 10), Acceleration = Vector3.new(0, 2, 0),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	})
	-- the floor: dust lifting, then grit, then a swirl of it
	local floor = own(hidden(Vector3.new(7, 0.2, 7), CFrame.new(floorAt())))
	local dust = emit(floor, {
		Color = ColorSequence.new(PALE), LightEmission = 0.6, Lifetime = NumberRange.new(0.9, 1.5),
		Speed = NumberRange.new(0.6, 1.6), Acceleration = Vector3.new(0, 1.2, 0), SpreadAngle = Vector2.new(15, 15),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0.1) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.4), NumberSequenceKeypoint.new(1, 1) }),
	})
	local grit = emit(floor, {
		Texture = "rbxasset://textures/particles/smoke_main.dds",
		Color = ColorSequence.new(Color3.fromRGB(120, 125, 135)), LightEmission = 0, LightInfluence = 1,
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(2, 4), Drag = 3,
		Acceleration = Vector3.new(0, 1.5, 0), SpreadAngle = Vector2.new(20, 20),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0.08) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) }),
	})
	-- the edge glowing (put back after)
	local edgeColor, edgeMat = if edge then edge.Color else WHITE, if edge then edge.Material else Enum.Material.Metal
	local EDGE_GLOW = Color3.fromRGB(190, 225, 255)
	local horizontal = function(p: Vector3): CFrame return CFrame.fromMatrix(p, Vector3.xAxis, Vector3.zAxis) end

	local flashed = false
	local nextKink = 0
	local nextPulse = 0
	local spinT = 0
	local conn = RunService.RenderStepped:Connect(function(dt: number)
		if not (blade.Parent and tip.Parent and root.Parent) then return end
		local c = math.clamp((now() - t0) / full, 0, 1)
		local max = c >= 1
		local acc = smooth(0.2, 0.5, c)    -- energy accumulation
		local over = smooth(0.6, 0.95, c)  -- overcharge
		local clk = os.clock()
		spinT += dt * (2 + 6 * over + (if max then 6 else 0))
		local tipPos = tip.WorldPosition
		local look = blade.CFrame.LookVector -- (toward the point)
		local axis = CFrame.lookAt(tipPos, tipPos + look) -- Z back up the blade
		local function along(back: number): CFrame return axis * CFrame.new(0, 0, back) end

		-- the point
		local flicker = 1 + 0.12 * math.sin(clk * 40) * over
		point.Size = Vector3.one * (0.08 + 0.06 * acc + 0.08 * over) * flicker
		point.CFrame = CFrame.new(tipPos)
		point.Transparency = 0.3 - 0.3 * acc
		glow.Size = NumberSequence.new((0.5 + 0.6 * acc + 0.9 * over + (if max then 0.8 else 0)) * flicker)
		star.Rate = if over > 0.05 then 12 else 0
		star.Size = NumberSequence.new(1.2 + 1.6 * over + (if max then 1 else 0))
		-- drawn in: specks, faster and thicker as it builds, and wind lines
		well.CFrame = CFrame.new(tipPos)
		wide.CFrame = CFrame.new(tipPos)
		local life = 0.45 - 0.2 * over - (if max then 0.08 else 0)
		specks.Lifetime = NumberRange.new(life)
		specks.Speed = NumberRange.new(1.6 / life)
		specks.Rate = 10 + 30 * acc + 50 * over + (if max then 50 else 0)
		local lineLife = 0.4 - 0.15 * over
		lines.Lifetime = NumberRange.new(lineLife)
		lines.Speed = NumberRange.new(3.4 / lineLife)
		lines.Rate = 14 * acc + 30 * over + (if max then 30 else 0)
		-- motes orbiting the point, trailing light
		for _, m in ipairs(motes) do
			local a = m.phase + clk * m.w * (1 + over)
			local r = m.r * (1 - 0.35 * over)
			local p = (CFrame.new(tipPos) * m.tilt):PointToWorldSpace(Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
			m.part.CFrame = CFrame.new(p)
			m.part.Transparency = 1 - acc
			m.a0.WorldPosition = p
			m.a1.WorldPosition = p + Vector3.new(0, 0.05, 0)
			m.trail.Enabled = acc > 0.05
			m.trail.Transparency = NumberSequence.new(1 - 0.8 * acc, 1)
		end
		-- the ring of air: faint, wavering, a stud behind the point
		placeRing(air, along(1 + 0.3 * math.sin(clk * 3)), 0.4 + 0.05 * math.sin(clk * 5), spinT * 0.6,
			0.86 - 0.1 * acc + 0.3 * over)
		-- energy rings: the inner three with the overcharge, the outer two
		-- from the accumulation; all pulled in tight at full
		local squeeze = if max then 0.55 else 1
		for i, r in ipairs(rings) do
			local back = RING_BACK[i] * squeeze
			local rad = RING_RAD[i] * (if max then 0.75 else 1) * (1 + 0.04 * math.sin(clk * 6 + i))
			local show = if i <= 3 then over * (0.95 - 0.12 * (i - 1)) else acc * 0.55 + over * 0.2
			local tiltCf = if i == 5 then along(back) * CFrame.Angles(0.35 * math.sin(clk * 1.3), 0.35 * math.cos(clk * 1.1), 0) else along(back)
			placeRing(r, tiltCf, rad, spinT * (if i % 2 == 0 then -1.4 else 1.1) + i, 1 - show)
		end
		-- streams spiralling up to the point
		for _, s in ipairs(streams) do
			local speed = (0.9 + 1.6 * over + (if max then 1 else 0)) * (if s.outer then 0.75 else 1)
			s.u += dt * speed
			local wrapped = false
			if s.u >= 1 then
				s.u -= 1
				wrapped = true
			end
			local back = 3.2 * (1 - s.u) + 0.1
			local width = if s.outer then 0.85 - 0.3 * over else 0.5 - 0.22 * over
			local rad = width * (0.35 + 0.65 * (1 - s.u))
			local turn = if s.outer then -1 else 1
			local ang = s.phase + turn * (s.u * math.pi * (3 + 2 * over) + spinT)
			local radial = Vector3.new(math.cos(ang), math.sin(ang), 0)
			local cf = along(back)
			s.a0.WorldPosition = cf:PointToWorldSpace(radial * rad)
			s.a1.WorldPosition = cf:PointToWorldSpace(radial * (rad + 0.08))
			if wrapped then s.trail:Clear() end
			local show = if s.outer then smooth(0.35, 0.6, c) else acc
			s.trail.Enabled = show > 0.02
			s.trail.Transparency = NumberSequence.new(1 - 0.75 * show, 1)
		end
		-- sparks along the blade
		along_.CFrame = blade.CFrame
		crackle.Rate = 25 * over + (if max then 35 else 0)
		-- the edge
		if edge then
			edge.Material = if acc > 0.05 then Enum.Material.Neon else edgeMat
			edge.Color = edgeColor:Lerp(EDGE_GLOW, acc)
		end
		-- round him: the sigil, the gusts, the light rising off him
		local fp = floorAt()
		for i, r in ipairs(sigil) do
			local show = if i == 2 then acc * 0.7 else smooth(0.3 + 0.15 * i, 0.6 + 0.15 * i, c) * 0.85
			placeRing(r, horizontal(fp), SIGIL_R[i] * (1 - 0.06 * over) + (if max then 0.08 * math.sin(clk * 12) else 0),
				spinT * (if i == 2 then -0.5 else 0.35), 1 - show)
		end
		for _, g in ipairs(gusts) do
			local a = g.phase + clk * (3 + 4 * over)
			local h = g.h + 0.4 * math.sin(clk * 2 + g.phase)
			local p = root.Position + Vector3.new(math.cos(a) * 2.3, h, math.sin(a) * 2.3)
			g.a0.WorldPosition = p
			g.a1.WorldPosition = p + Vector3.new(0, 0.1, 0)
			local show = smooth(0.3, 0.7, c)
			g.trail.Enabled = show > 0.02
			g.trail.Transparency = NumberSequence.new(1 - 0.6 * show, 1)
		end
		aura.CFrame = root.CFrame
		rising.Rate = 14 * acc + 16 * over
		-- the floor
		floor.CFrame = CFrame.new(fp)
		dust.Rate = 12 * acc + 14 * over
		grit.Rate = 16 * over + (if max then 12 else 0)
		-- arcs: every so often fresh crooked paths up the blade (at full, ring
		-- to ring)
		if clk >= nextKink then
			nextKink = clk + 0.05 + math.random() * 0.05
			for k, set in ipairs(arcSets) do
				local chance = (0.35 * over + (if max then 0.45 else 0)) * (if k == 2 then 0.6 else 1)
				local on = math.random() < chance
				for i = 1, 5 do
					local back, rad
					if max and i >= 2 and i <= 4 then
						-- (ring to ring: the outermost first)
						back, rad = RING_BACK[4 - i + 1] * squeeze, RING_RAD[4 - i + 1] * 0.75
					else
						back, rad = (if max then { 2.4, 0, 0, 0, 0 } else { 2.8, 2, 1.3, 0.6, 0 })[i], (if i == 5 then 0 else 0.14)
					end
					local a = math.random() * math.pi * 2
					set.pts[i].WorldPosition = along(back):PointToWorldSpace(Vector3.new(math.cos(a) * rad, math.sin(a) * rad, 0))
				end
				for _, b in ipairs(set.beams) do b.Transparency = NumberSequence.new(if on then 0 else 1) end
			end
		end
		-- full: the flash and the shockwave, then a pulse every beat it's held
		if max and not flashed then
			flashed = true
			nextPulse = clk + 0.45
			local f = neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.4, Color = WHITE, CFrame = CFrame.new(tipPos) })
			TweenService:Create(f, TweenInfo.new(0.16, Enum.EasingStyle.Quad), { Size = Vector3.one * 2.4, Transparency = 1 }):Play()
			Debris:AddItem(f, 0.2)
			SwordFX.Arc({ cf = CFrame.new(fp), radius = 2.5, arc = 359, width = 0.18, color = PALE, draw = 0.001, life = 0.35, grow = 1.6 })
			ClassFX.Burst(tipPos, WHITE, 14, 10, ClassFX.TEX_SPARK, 0.2, 0.3)
			ClassFX.Sound("chime", tipPos, 0.7, 1.6)
		elseif max and clk >= nextPulse then
			nextPulse = clk + 0.45
			local side = look:Cross(Vector3.yAxis)
			if side.Magnitude > 0.01 then
				SwordFX.Arc({ cf = CFrame.fromMatrix(tipPos, side.Unit, look), radius = 0.35, arc = 359, width = 0.08,
					color = WHITE, draw = 0.001, life = 0.22, grow = 2.2 })
			end
			SwordFX.Arc({ cf = CFrame.new(fp), radius = 1.6, arc = 359, width = 0.08, color = PALE, draw = 0.001, life = 0.3, grow = 1.4 })
		end
	end)

	local stopped = false
	return {
		stop = function(_released: boolean)
			if stopped then return end
			stopped = true
			conn:Disconnect()
			if edge and edge.Parent then
				edge.Material = edgeMat
				edge.Color = edgeColor
			end
			for _, e in ipairs(emitters) do e.Enabled = false end
			for _, s in ipairs(streams) do s.trail.Enabled = false end
			for _, g in ipairs(gusts) do g.trail.Enabled = false end
			for _, m in ipairs(motes) do
				m.trail.Enabled = false
				m.part.Transparency = 1
			end
			for _, set in ipairs(arcSets) do
				for _, b in ipairs(set.beams) do b.Transparency = NumberSequence.new(1) end
			end
			for _, list in ipairs({ rings, sigil, { air } }) do
				for _, r in ipairs(list) do r.h1.Transparency, r.h2.Transparency = NumberSequence.new(1), NumberSequence.new(1) end
			end
			point.Transparency = 1
			task.delay(1.6, function()
				for _, x in ipairs(owned) do x:Destroy() end
			end)
		end,
	}
end

-- ── Piercing Judgement: the thrust ──────────────────────────────────────────
-- A needle, not an explosion: a long thin streak from the point down the
-- line, narrow rings of air punched out along it, a sharp white flash where
-- it ends and a spray of specks flung on along the line.
local function judgeThrustFx(char: Model?, from: Vector3, dir: Vector3, c: number, length: number, empowered: boolean)
	local tool = char and char:FindFirstChild("Longsword")
	local tip = tool and tool:FindFirstChild("BladeTip", true) :: Attachment?
	local y = if tip then tip.WorldPosition.Y else from.Y + 0.6
	local start = Vector3.new(from.X, y, from.Z) + dir * 2
	local finish = Vector3.new(from.X, y, from.Z) + dir * length
	local side = dir:Cross(Vector3.yAxis).Unit
	local core = if empowered then WHITE else PALE
	task.delay(JUDGE.hit * 0.5, function()
		SwordFX.Blade((start + finish) / 2, dir, (finish - start).Magnitude, 0.3 + 0.3 * c, ELECTRIC, 0.05 + 0.05 * c)
		streak(start, finish, 0.16 + 0.14 * c, core, 0.12 + 0.1 * c)
		-- rings of air punched out along the line
		local n = 2 + math.floor(3 * c + 0.5)
		for i = 1, n do
			task.delay(i * 0.02, function()
				local p = start + dir * ((finish - start).Magnitude * (i / (n + 1)) * 0.7)
				SwordFX.Arc({ cf = CFrame.fromMatrix(p, side, dir), radius = 0.45 + 0.15 * i, arc = 359, width = 0.1,
					color = PALE, draw = 0.001, life = 0.16, grow = 1.4 })
			end)
		end
		-- the flash where it ends, and specks flung on
		local f = neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Color = WHITE, CFrame = CFrame.new(finish) })
		TweenService:Create(f, TweenInfo.new(0.12, Enum.EasingStyle.Quad), { Size = Vector3.one * (2.5 + 2 * c), Transparency = 1 }):Play()
		Debris:AddItem(f, 0.15)
		SwordFX.Arc({ cf = CFrame.fromMatrix(finish, side, dir), radius = 0.8 + 0.6 * c, arc = 359, width = 0.14,
			color = WHITE, draw = 0.001, life = 0.2, grow = 1.8 })
		ClassFX.Burst(finish, FROST, 8 + math.floor(10 * c), 14 + 10 * c, ClassFX.TEX_SPARK, 0.22, 0.3)
	end)
	ClassFX.Sound("whoosh", from, 1, 1.5 + 0.2 * c)
	ClassFX.Sound("swordIn", from, 0.6 + 0.3 * c, 1.3)
	if c >= 0.999 then ClassFX.Sound("thunder", from, 0.35, 1.6) end
	if char then trail(char, 0.45) end
end

-- Yours: held from the cast until the key comes up (SkillController →
-- Release) or it goes by itself a beat after full.
type Judging = { t0: number, full: number, char: Model, root: BasePart, fx: JudgeFx, token: {}, conn: RBXScriptConnection }
local judging: Judging? = nil

local function flatDir(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else fallback
end

local function startJudge(char: Model, root: BasePart, dir: Vector3, empowered: boolean)
	local full = if empowered then JUDGE.empFull else JUDGE.full
	local hum = char:FindFirstChildOfClass("Humanoid")
	busyUntil = math.huge
	char:SetAttribute("AllowSkillMovement", false)
	if hum then hum.AutoRotate = false end
	judgeCharge[char] = 0
	-- the half step back onto the back foot
	dash(root, -dir, 1.2, 0.16)
	judgeGuardPose(char, full + JUDGE.still + 1)
	local token = {}
	local t0 = os.clock()
	-- the point stays on the aim the whole time
	local conn = RunService.Heartbeat:Connect(function()
		local j = judging
		if not j or j.token ~= token then return end
		judgeCharge[char] = math.clamp((os.clock() - t0) / full, 0, 1)
		if root.Parent and deps then
			local d = flatDir(deps.getAim(root), root.CFrame.LookVector)
			root.CFrame = CFrame.lookAt(root.Position, root.Position + d)
		end
		if os.clock() - t0 >= full + JUDGE.still then SwordsmanController.Release(3) end
	end)
	judging = { t0 = t0, full = full, char = char, root = root, fx = judgeChargeFx(char, full), token = token, conn = conn }
	ClassFX.Sound("wind", root, 0.35, 1.5)
end

function SwordsmanController.Release(skillIndex: number)
	if skillIndex ~= 3 then return end
	local j = judging
	if not j then return end
	judging = nil
	j.conn:Disconnect()
	local char, root = j.char, j.root
	local held = os.clock() - j.t0
	local c = math.clamp(held / j.full, 0, 1)
	local dir = if root.Parent and deps then flatDir(deps.getAim(root), root.CFrame.LookVector) else root.CFrame.LookVector
	Network.GetRemoteEvent(Network.Remotes.SwordsmanInput):FireServer({ kind = "release", held = held, dir = dir })
	j.fx.stop(true)
	judgeCharge[char] = nil
	local hum = char:FindFirstChildOfClass("Humanoid")
	busyUntil = os.clock() + 0.7
	releaseAfter(char, 0.62)
	task.delay(0.62, function() if hum then hum.AutoRotate = true end end)
	if not (char.Parent and root.Parent) then return end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local empowered = j.full < JUDGE.full
	local size = tonumber(player:GetAttribute("Stat_size")) or 1
	local length = (JUDGE.length + (JUDGE.fullLength - JUDGE.length) * c) * size * (if empowered then 1.3 else 1)
	local from = root.Position
	judgeThrustPose(char, c)
	dash(root, dir, JUDGE.lunge + (JUDGE.fullLunge - JUDGE.lunge) * c, 0.14)
	judgeThrustFx(char, from, dir, c, length, empowered)
end

function SwordsmanController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local empowered = momentum() >= MOMENTUM_MAX
	local dir = Vector3.new(aimDir.X, 0, aimDir.Z)
	dir = if dir.Magnitude > 0.01 then dir.Unit else root.CFrame.LookVector
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	guardToken += 1 -- (a guard still pending lets go of nothing now)
	if skillIndex == 1 then
		-- Sword Rush.
		char:SetAttribute("AllowSkillMovement", false)
		-- Instant: a blink with afterimages left along the way (three
		-- charges, so it can be chained: SkillData `charges`).
		local dist = (config.dashDistance or 20) * (if empowered then 1.5 else 1)
		local t = 0.08
		if hum then hum.AutoRotate = false end
		ClassFX.Afterimages(char, FROST, 4, 0.01)
		blink(root, dir, dist)
		rushPose(char, 0.12)
		trail(char, 0.3)
		busyUntil = os.clock() + t
		releaseAfter(char, t + 0.05)
		task.delay(t + 0.05, function() if hum then hum.AutoRotate = true end end)
	elseif skillIndex == 2 then
		-- Parry: on guard for the window (a parry turns it into the riposte:
		-- onParry).
		char:SetAttribute("AllowSkillMovement", false)
		local window = (config.duration or 1.2) * (if empowered then 1.6 else 1)
		guardPose(char, window)
		busyUntil = os.clock() + window -- (committed to the guard)
		guardToken += 1
		local token = guardToken
		task.delay(window, function()
			if guardToken == token then releaseAfter(char, 0) end
		end)
	elseif skillIndex == 3 then
		-- Piercing Judgement: held (the thrust goes on Release).
		startJudge(char, root, dir, empowered)
	elseif skillIndex == 4 then
		-- Blade Storm: the wind-up close-up; the dash chain follows the
		-- server's "storm" moment (see onStorm).
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = math.huge
		enGardePose(char, STORM_WINDUP)
		tipCamera(char, STORM_WINDUP)
		task.delay(12, function()
			-- Safety net if the storm moment never arrives.
			if busyUntil == math.huge then
				busyUntil = 0
				releaseAfter(char, 0)
			end
		end)
	end
	return nil
end

-- Another Swordsman's Blade Storm (teammate cinematics): the same shot.
function SwordsmanController.PlayStormCutscene(char: Model, _dir: Vector3)
	tipCamera(char, STORM_WINDUP)
end

-- ── Server moments (SwordsmanFX) ────────────────────────────────────────────
local function charOf(p: Player?): Model?
	return p and p.Character or nil
end

local function onCombo(msg: any)
	if msg.attacker == player then return end -- ours was predicted on click
	local char = charOf(msg.attacker)
	if not char then return end
	swingPose(char, msg.step)
	comboVFX(char, msg.step, msg.dir)
	local root = rootOf(char)
	if root then ClassFX.Sound("whoosh", root, 0.5, 1.1) end
end

local function onRush(msg: any)
	local char = charOf(msg.attacker)
	local from, to = msg.from :: Vector3, msg.to :: Vector3
	local color = if msg.empowered then WHITE else BLUE
	-- A bright comet along the dash wrapped in a bundle of thin speed lines.
	streak(from + Vector3.new(0, 1, 0), to + Vector3.new(0, 1, 0), if msg.empowered then 0.7 else 0.5, color, 0.25,
		if msg.empowered then 12 else 8)
	if char and msg.attacker ~= player then
		rushPose(char, if msg.empowered then 0.26 else 0.2)
		ClassFX.Afterimages(char, FROST, 5, 0.04)
		trail(char, 0.4)
	end
end

local function onRushCut(msg: any)
	local from, to = msg.from :: Vector3, msg.to :: Vector3
	local mid = from:Lerp(to, 0.35 + 0.25 * (msg.n - 1))
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if dir.Magnitude < 0.1 then return end
	local roll = if msg.n % 2 == 1 then 25 else -25
	crescent(CFrame.lookAt(mid + Vector3.new(0, 1, 0), mid + Vector3.new(0, 1, 0) + dir.Unit) * CFrame.Angles(0, 0, math.rad(roll)),
		4.5, 130, if msg.empowered then WHITE else BLUE, 0.8, 0.22)
	ClassFX.Sound("swordHit", mid, 0.6, 1 + msg.n * 0.08)
end

local function onGuard(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then
		guardPose(char, msg.window)
	end
	-- A thin circle of light drawing itself round the feet over the window
	-- (the guard's timer), plus a glint on the raised blade.
	SwordFX.Arc({ cf = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * root.CFrame.Rotation, radius = 3.4, arc = 359,
		width = 0.35, color = FROST, draw = msg.window, life = 0.15, grow = 0 })
	SwordFX.Stars(root.Position + root.CFrame.LookVector * 1.2 + Vector3.new(0, 2, 0), 4, 3, BLUE)
end

-- Your riposte: facing the attacker, the dash in so the pommel meets its
-- chest (stopping short of walls and ledges as every dash does).
local POMMEL_REACH = 3.4 -- root to pommel in RIPOSTE_STRIKE (measured in Studio)
local function riposte(char: Model, root: BasePart, msg: any)
	local hum = char:FindFirstChildOfClass("Humanoid")
	guardToken += 1
	busyUntil = os.clock() + RIPOSTE_TIME
	char:SetAttribute("IsSkillCasting", true)
	char:SetAttribute("AllowSkillMovement", false)
	releaseAfter(char, RIPOSTE_TIME)
	if hum then
		hum.AutoRotate = false
		task.delay(RIPOSTE_TIME, function() hum.AutoRotate = true end)
	end
	local dir = Vector3.new((msg.dir :: Vector3).X, 0, (msg.dir :: Vector3).Z)
	dir = if dir.Magnitude > 0.01 then dir.Unit else root.CFrame.LookVector
	local gap = 0
	local to = msg.to :: Vector3?
	if to then
		-- (up to its front: half its width)
		local target = msg.target :: Model?
		local half = 0.5
		if target and target.Parent then
			local size = target:GetExtentsSize()
			half = math.clamp(math.min(size.X, size.Z) / 2, 0.5, 4)
		end
		local flat = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
		dir = if flat.Magnitude > 0.01 then flat.Unit else dir
		gap = math.clamp(flat.Magnitude - half - POMMEL_REACH, 0, RIPOSTE_REACH)
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	ripostePose(char)
	if gap > 0.3 then
		task.delay(0.09, function()
			if root.Parent then dash(root, dir, gap, 0.2) end
		end)
	end
end

local function onParry(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	-- The perfect-parry flash: a circle of light with rays bursting out of
	-- it, a small bright core and glinting stars.
	local center = pos + Vector3.new(0, 0.4, 0)
	SwordFX.Rays(center, 10, 18, BLUE, 0.4)
	SwordFX.Arc({ cf = CFrame.new(center), radius = 3.2, arc = 359, width = 0.5, color = WHITE, draw = 0.001, life = 0.3, grow = 0.4 })
	SwordFX.Stars(center, 18, 22, BLUE)
	ClassFX.Sound("clang", pos, 1, 1.1)
	if char then popWord(char, "PARRY!", WHITE, 34) end
	if msg.attacker == player then
		local root = rootOf(char)
		if char and root then riposte(char, root, msg) end
		deps.shake(0.8, 0.2)
		deps.fovPunch(-6, 0.25)
	elseif char then
		ripostePose(char) -- (their dash comes over with their character)
	end
end

-- The pommel lands: a hard, small burst where it meets the chest.
local function onCounter(msg: any)
	local char = charOf(msg.attacker)
	local at = (msg.pos :: Vector3) + Vector3.new(0, 1, 0)
	local tool = char and char:FindFirstChild("Longsword")
	local pommel = tool and tool:FindFirstChild("Pommel", true)
	if pommel and pommel:IsA("BasePart") and (pommel.Position - at).Magnitude < 8 then at = pommel.Position end
	local dir = msg.dir :: Vector3
	SwordFX.Arc({ cf = CFrame.lookAt(at, at + dir), radius = if msg.empowered then 2.2 else 1.6, arc = 359, width = 0.3,
		color = WHITE, draw = 0.001, life = 0.18, grow = 1.2 })
	SwordFX.Stars(at, if msg.empowered then 14 else 10, 20, BLUE)
	ClassFX.Sound("punch", at, 1, 0.8)
	ClassFX.Sound("clang", at, 0.5, 0.7)
	if char then CastPoses.hitStop(char, 0.06) end
	if msg.attacker == player then deps.shake(1.1, 0.22) end
end

-- Piercing Judgement, someone else's: the guard and the charge (till their
-- release comes, or a beat past when it would have gone by itself).
local othersJudging: { [Model]: JudgeFx } = {}
local function onJudgeCharge(msg: any)
	if msg.attacker == player then return end -- ours started on the key
	local char = charOf(msg.attacker)
	if not char then return end
	local full = tonumber(msg.full) or JUDGE.full
	local was = othersJudging[char]
	if was then was.stop(false) end
	judgeCharge[char] = 0
	judgeGuardPose(char, full + JUDGE.still + 1)
	local h = judgeChargeFx(char, full)
	othersJudging[char] = h
	local t0 = os.clock()
	task.spawn(function()
		while othersJudging[char] == h and os.clock() - t0 < full + JUDGE.still + 0.6 do
			judgeCharge[char] = math.clamp((os.clock() - t0) / full, 0, 1)
			task.wait()
		end
		if othersJudging[char] == h then
			othersJudging[char] = nil
			judgeCharge[char] = nil
			h.stop(false)
		end
	end)
end

-- The release: their lunge and needle (ours were drawn on the key), then
-- every phantom echo down the same line a beat apart, for everyone
-- (budgeted: big Projectile Count builds stack a lot of them).
local function onJudgeRelease(msg: any)
	local char = charOf(msg.attacker)
	local from, dir, length = msg.from :: Vector3, msg.dir :: Vector3, msg.length :: number
	local c = tonumber(msg.charge) or 0
	if char and msg.attacker ~= player then
		local h = othersJudging[char]
		othersJudging[char] = nil
		judgeCharge[char] = nil
		if h then h.stop(true) end
		judgeThrustPose(char, c)
		judgeThrustFx(char, from, dir, c, length, msg.empowered == true)
	end
	local tool = char and char:FindFirstChild("Longsword")
	local tip = tool and tool:FindFirstChild("BladeTip", true) :: Attachment?
	local y = if tip then tip.WorldPosition.Y else from.Y + 0.6
	for n = 1, msg.echoes do
		task.delay(JUDGE.hit + n * msg.step, function()
			if not FxBudget.Allow("swordEcho", 14) then return end
			local p = Vector3.new(from.X, y, from.Z) + dir * 2
			SwordFX.Blade(p + dir * length * 0.5, dir, length, 0.4, FROST, 0.05)
			streak(p, p + dir * length, 0.18, if msg.empowered then WHITE else BLUE, 0.04)
			ClassFX.Burst(p + dir * length, FROST, 5, 12, ClassFX.TEX_SPARK, 0.2, 0.25)
			ClassFX.Sound("swordHit", p + dir * length * 0.5, 0.4, 1.3 + n * 0.06)
		end)
	end
end

-- The point going through someone: a pinprick flash and specks thrown out
-- the far side (budgeted: a long line can run through a crowd).
local function onJudgePierced(msg: any)
	local dir = msg.dir :: Vector3
	local side = dir:Cross(Vector3.yAxis).Unit
	for _, pos in ipairs(msg.hits or {}) do
		if not FxBudget.Allow("swordPierce", 24) then break end
		local p = (pos :: Vector3) + Vector3.new(0, 0.6, 0)
		SwordFX.Arc({ cf = CFrame.fromMatrix(p, side, dir), radius = 0.7, arc = 359, width = 0.1,
			color = WHITE, draw = 0.001, life = 0.14, grow = 1.5 })
		ClassFX.Burst(p + dir * 0.8, FROST, 6, 14, ClassFX.TEX_SPARK, 0.18, 0.22)
	end
end

local function darken(seconds: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "BladeStormDark"
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.2), { Brightness = -0.22, Saturation = -0.35, Contrast = 0.2 }):Play()
	task.delay(seconds, function()
		TweenService:Create(cc, TweenInfo.new(0.4), { Brightness = 0, Saturation = 0, Contrast = 0 }):Play()
		Debris:AddItem(cc, 0.45)
	end)
end

local function onStorm(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local targets: { Model } = msg.targets or {}
	local total = msg.windup + #targets * msg.step + 0.7
	local isMine = msg.attacker == player

	-- The arena darkens; the Swordsman burns white-blue.
	local myRoot = rootOf(player.Character)
	if isMine or (myRoot and (myRoot.Position - root.Position).Magnitude < 90) then darken(total) end
	local hl = Instance.new("Highlight")
	hl.FillColor = BLUE
	hl.FillTransparency = 0.7
	hl.OutlineColor = WHITE
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = char
	hl.Parent = ClassFX.Folder()
	Debris:AddItem(hl, total)
	-- En garde: side on, the rapier held straight out (your own was posed
	-- on cast); a circle of light drawing itself round the feet and motes
	-- rising round him during the wind-up.
	if not isMine then enGardePose(char, msg.windup) end
	local feet = root.Position - Vector3.new(0, 2.6, 0)
	SwordFX.Arc({ cf = CFrame.new(feet + Vector3.new(0, 0.2, 0)), radius = 4.5, arc = 359, width = 0.6, color = BLUE,
		draw = msg.windup * 0.6, life = 0.4, grow = 0.2 })
	SwordFX.Stars(feet + Vector3.new(0, 1, 0), 14, 6, BLUE)
	ClassFX.Sound("rockHit", root, 0.7, 0.9)

	local prev = root.Position
	for i, model in ipairs(targets) do
		task.delay(msg.windup + (i - 1) * msg.step, function()
			local t = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart?
			if not t or not root.Parent then return end
			local toward = Vector3.new(t.Position.X - prev.X, 0, t.Position.Z - prev.Z)
			local d = if toward.Magnitude > 0.1 then toward.Unit else root.CFrame.LookVector
			-- Land just past the target, facing through it.
			local land = Vector3.new(t.Position.X, root.Position.Y, t.Position.Z) + d * 3.5
			if isMine then
				local stand = SafeMove.StandHeight(root)
				root.CFrame = CFrame.lookAt(land, land + d)
				root.AssemblyLinearVelocity = Vector3.zero
				-- Targets on steps / ramps: land on the floor there, not in it.
				SafeMove.SnapToFloor(root, stand)
				deps.shake(0.35, 0.08)
			end
			ClassFX.Afterimages(char, FROST, 2, 0.03)
			-- Long crossing streaks that hang in the air ~0.3 s, a slash on
			-- the target and a few glints.
			streak(prev + Vector3.new(0, 1.2, 0), land + Vector3.new(0, 1.2, 0), 0.55, BLUE, 0.3, 3)
			crescent(CFrame.lookAt(t.Position, t.Position + d) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 30 else -30)),
				4.5, 130, WHITE, 0.9, 0.22, if i % 2 == 0 then -1 else 1)
			SwordFX.Stars(t.Position, 6, 14, BLUE)
			ClassFX.Sound("swordHit", t.Position, 0.7, 1 + i * 0.05)
			prev = land
			-- Flourishes everyone sees: lunge, riposte, double thrust in turn.
			swingPose(char, ((i - 1) % 3) + 1)
			trail(char, 0.25)
		end)
	end
	if isMine then
		task.delay(total, function()
			busyUntil = 0
			releaseAfter(char, 0)
		end)
	end
end

local function onStormX(msg: any)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local r = msg.radius :: number
	-- The giant luminous X: two long light blades slashing out from the
	-- centre (fattest in the middle, tapering to points), a secondary pair
	-- of thinner blades, and stars / debris flying outward.
	local flatDir = Vector3.new(dir.X, 0, dir.Z)
	flatDir = if flatDir.Magnitude > 0.01 then flatDir.Unit else Vector3.new(0, 0, -1)
	local c = pos + Vector3.new(0, 0.5, 0)
	for _, ang in ipairs({ 45, -45 }) do
		local d = (CFrame.Angles(0, math.rad(ang), 0) * flatDir)
		SwordFX.Blade(c, d, r * 2.6, 3.2, BLUE, 0.35)
	end
	task.delay(0.05, function()
		for _, ang in ipairs({ 38, -52 }) do
			SwordFX.Blade(c, CFrame.Angles(0, math.rad(ang), 0) * flatDir, r * 1.8, 1.2, WHITE, 0.2)
		end
	end)
	SwordFX.Stars(c, 50, 45, BLUE)
	ClassFX.Burst(c, FROST, 30, 30, ClassFX.TEX_SPARK, 0.5, 0.6)
	ClassFX.Sound("quake", pos, 0.9, 1.2, 1.5)
	ClassFX.Sound("swordHit", pos, 1, 0.7)
	local myRoot = rootOf(player.Character)
	if myRoot and (myRoot.Position - pos).Magnitude < 80 then
		deps.shake(if msg.attacker == player then 1.3 else 0.6, 0.35)
	end
	if msg.attacker == player then deps.fovPunch(10, 0.35) end
end

local function onMomentumMax(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	ClassFX.Burst(root.Position + Vector3.new(0, 1, 0), WHITE, 24, 14, ClassFX.TEX_SPARK, 0.5, 0.5)
	ClassFX.Sound("ding", root, 0.6, 1.1)
	if msg.attacker == player then popWord(char, "MOMENTUM MAX", BLUE, 24) end
end

local function onEmpowered(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	ClassFX.Ring(root.Position, WHITE, 8, 0.3, char)
	ClassFX.Burst(root.Position + Vector3.new(0, 1, 0), BLUE, 30, 18, ClassFX.TEX_SPARK, 0.6, 0.5)
	popWord(char, "EMPOWERED", WHITE, 22)
end

local HANDLERS: { [string]: (any) -> () } = {
	combo = onCombo,
	rush = onRush,
	rushCut = onRushCut,
	guard = onGuard,
	parry = onParry,
	counter = onCounter,
	judgeCharge = onJudgeCharge,
	judgeRelease = onJudgeRelease,
	judgePierced = onJudgePierced,
	storm = onStorm,
	stormX = onStormX,
	momentumMax = onMomentumMax,
	empowered = onEmpowered,
}

function SwordsmanController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	player:GetAttributeChangedSignal("SW_Momentum"):Connect(refreshHud)
	player:GetAttributeChangedSignal("SelectedClass"):Connect(refreshHud)
	player:GetAttributeChangedSignal("InLobby"):Connect(refreshHud)
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localStep = 0
		local j = judging
		if j then
			judging = nil
			j.conn:Disconnect()
			j.fx.stop(false)
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.SwordsmanFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[SwordsmanController]", msg.kind, err) end
		end
	end)
end

-- The pose functions, for previews and tests (they pose any character model).
SwordsmanController.Poses = {
	swing = swingPose,
	rush = rushPose,
	guard = guardPose,
	riposte = ripostePose,
	judgeGuard = judgeGuardPose,
	judgeThrust = judgeThrustPose,
	enGarde = enGardePose,
}
-- (and the Judgement's effects, for the same)
SwordsmanController.JudgeChargeFx = judgeChargeFx
SwordsmanController.JudgeThrustFx = judgeThrustFx

return SwordsmanController
