--!strict
--[[
	SwordsmanController.luau
	Client side of the Swordsman (server: SwordsmanServer).

	  • The 4-hit rapier combo (lunge, riposte, double thrust, flèche): your
	    own are predicted (pose, blade trail, thrust / slash, whoosh) on
	    click; the server resolves hits and sends everyone else's over
	    SwordsmanFX.
	  • Skills: the dash for Sword Rush, the guard for Parry, the lunge for
	    Phantom Thrust (its echoes drawn as phantom blades down the line),
	    and Blade Storm: en garde with the camera at the rapier's point, then
	    the chain (you flash from enemy to enemy as the server's timings
	    arrive).
	  • Every Swordsman effect for every player, in blue: thrusts, crescents,
	    rush streaks, the parry flash + "PARRY!", the counter slash, the
	    phantom thrusts, the storm's lingering trails, darkened arena,
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

type GripState = { tool: Tool, base: CFrame, k: number, from: number, target: number, t0: number, dur: number }
local grips: { [Tool]: GripState } = {}

local function gripTo(char: Model, target: number, dur: number)
	local tool = char:FindFirstChild("Longsword")
	if not (tool and tool:IsA("Tool")) then return end
	local g = grips[tool]
	if not g then
		g = { tool = tool, base = tool.Grip, k = 0, from = 0, target = 0, t0 = 0, dur = 0 }
		grips[tool] = g
	end
	local s = g :: GripState
	s.from, s.target, s.t0, s.dur = s.k, target, os.clock(), math.max(dur, 0.01)
end

-- Back to the cutting hold after `after` seconds, unless another move has
-- taken the grip since.
local function gripBack(char: Model, after: number)
	local tool = char:FindFirstChild("Longsword")
	local g = tool and tool:IsA("Tool") and grips[tool]
	if not g then return end
	local stamp = g.t0
	task.delay(after, function()
		if grips[g.tool] == g and g.t0 == stamp then gripTo(char, 0, 0.12) end
	end)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for tool, g in pairs(grips) do
		if not tool.Parent then
			grips[tool] = nil
		elseif g.k ~= g.target then
			local a = math.clamp((now - g.t0) / g.dur, 0, 1)
			local e = -(math.cos(math.pi * a) - 1) / 2
			g.k = if a >= 1 then g.target else g.from + (g.target - g.from) * e
			tool.Grip = g.base * CFrame.Angles(math.rad(90) * g.k, 0, 0)
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

local function guardPose(char: Model, window: number)
	-- Parry guard: blade up and across the body (cutting hold), off hand
	-- raised behind, sunk into the knees.
	gripTo(char, 0, 0.04)
	local p = body(6, 25, 22, 22, { RS = { 72, -48, -10 }, LS = { 110, 0, -35 }, N = { -8, -20, 0 } }, 16)
	CastPoses.play(char, {
		{ dur = 0.06, style = Enum.EasingStyle.Back, pose = p },
		{ dur = window, pose = p, wobble = function(t: number)
			local b = math.sin(t * 3.2) * 1.2
			return { W = { b, 0, 0 }, N = { -b * 0.5, 0, 0 } }
		end },
	})
end

local function counterPose(char: Model)
	-- Drop, then launch upward into a rising cut, airborne, then land.
	gripTo(char, 0, 0.04)
	CastPoses.play(char, {
		{ dur = 0.05, style = QUAD, pose = body(22, 20, 36, 36,
			{ RS = { -65, 0, 20 }, LS = { 20, 0, -30 }, N = { -10, -15, 0 } }, 12) },
		{ dur = 0.14, style = QUART, pose = { Root = { 0, 0, 0, 0, 2.4, 0 }, W = { -28, -10, 0 }, RS = { 150, 0, -15 },
			LS = { -40, 0, -65 }, RH = { -65, 0, 6 }, LH = { 20, 0, -6 }, N = { -25, 0, 0 } } },
		{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, 1.6, 0 }, W = { -15, 0, 0 }, RS = { 125, 0, -10 },
			LS = { -20, 0, -50 }, RH = { -35, 0, 6 }, LH = { -10, 0, -6 }, N = { -15, 0, 0 } } },
		{ dur = 0.12, style = QUART, pose = body(-20, 0, 32, 32, { RS = { 40, 0, 0 }, LS = { 15, 0, -30 }, N = { 12, 0, 0 } }, 12) },
	}, 0.28)
end

local function thrustPose(char: Model)
	-- Phantom Thrust: the extension, then the deepest lunge, held while the
	-- echoes fire.
	gripTo(char, 1, 0.05)
	CastPoses.play(char, {
		{ dur = 0.06, style = QUAD, pose = EXTEND },
		{ dur = 0.07, style = QUART, pose = lunge(1.1) },
		{ dur = 0.3, pose = lungeHold(1.1) },
	}, 0.3)
	gripBack(char, 0.6)
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

function SwordsmanController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local empowered = momentum() >= MOMENTUM_MAX
	local dir = Vector3.new(aimDir.X, 0, aimDir.Z)
	dir = if dir.Magnitude > 0.01 then dir.Unit else root.CFrame.LookVector
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
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
		-- Parry: sword raised across the body for the window.
		char:SetAttribute("AllowSkillMovement", false)
		local window = (config.duration or 0.6) * (if empowered then 1.6 else 1)
		guardPose(char, window)
		releaseAfter(char, window)
	elseif skillIndex == 3 then
		-- Phantom Thrust: a deep lunge that carries him a few studs forward.
		char:SetAttribute("AllowSkillMovement", false)
		thrustPose(char)
		trail(char, 0.35)
		dash(root, dir, config.nudge or 5, 0.1)
		busyUntil = os.clock() + 0.35
		releaseAfter(char, 0.35)
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
		deps.shake(0.8, 0.2)
		deps.fovPunch(-6, 0.25)
	end
end

local function onCounter(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	if char then
		counterPose(char)
		trail(char, 0.35)
	end
	-- A huge sweeping crescent rising up and forward in front (the upward
	-- slash), plus glints where it lands.
	local base = CFrame.lookAt(pos + Vector3.new(0, 1, 0), pos + Vector3.new(0, 1, 0) + dir)
	crescent(base * CFrame.Angles(0, 0, math.rad(-60)), if msg.empowered then 9 else 7.5, 170,
		if msg.empowered then WHITE else BLUE, 1.6, 0.32, -1)
	SwordFX.Stars(pos + dir * 5 + Vector3.new(0, 2, 0), 12, 16, BLUE)
	ClassFX.Sound("swordHit", pos, 1, 0.8)
	ClassFX.Sound("whoosh", pos, 0.9, 0.7)
	if msg.attacker == player then deps.shake(1, 0.25) end
end

-- Phantom Thrust: the thrust, then each echo a beat later — a phantom rapier
-- of light stabbing down the same line (budgeted: big Projectile Count
-- builds stack a lot of them).
local function onThrust(msg: any)
	local char = charOf(msg.attacker)
	local from, dir, length = msg.from :: Vector3, msg.dir :: Vector3, msg.length :: number
	if char and msg.attacker ~= player then
		thrustPose(char)
		trail(char, 0.35)
	end
	for n = 0, msg.echoes do
		task.delay(0.08 + n * msg.step, function()
			if n > 0 and not FxBudget.Allow("swordEcho", 14) then return end
			local p = from + Vector3.new(0, 0.6, 0)
			local main = n == 0
			SwordFX.Blade(p + dir * length * 0.5, dir, length, if main then 1.1 else 0.75,
				if main then BLUE else FROST, if main then 0.12 else 0.06)
			streak(p, p + dir * length, if main then 0.6 else 0.35, if msg.empowered then WHITE else BLUE, 0.04)
			ClassFX.Burst(p + dir * length, FROST, if main then 10 else 5, 12, ClassFX.TEX_SPARK, 0.25, 0.25)
			ClassFX.Sound("swordHit", p + dir * length * 0.5, if main then 0.8 else 0.4, 1.2 + n * 0.06)
		end)
	end
	if msg.attacker == player then deps.shake(0.4, 0.12) end
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
	thrust = onThrust,
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
	counter = counterPose,
	thrust = thrustPose,
	enGarde = enGardePose,
}

return SwordsmanController
