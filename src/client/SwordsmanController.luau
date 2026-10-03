--!strict
--[[
	SwordsmanController.luau
	Client side of the Swordsman (server: SwordsmanServer).

	  • The 4-hit combo: your own swings are predicted (pose, blade trail,
	    crescent slash, whoosh) on click; the server resolves hits and sends
	    everyone else's swings over SwordsmanFX.
	  • Skills: the dash for Sword Rush, the guard stance for Parry, the spin
	    for Whirlwind, and the Blade Storm chain (you flash from enemy to enemy
	    as the server's timings arrive).
	  • Every Swordsman effect for every player: crescents, rush streaks, the
	    parry flash + "PARRY!", the counter slash, the whirlwind disc, the
	    storm's lingering trails, darkened arena, outline and the giant X.
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
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local SwordModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SwordModel"))

local player = Players.LocalPlayer

local SwordsmanController = {}

-- ── Tuning (mirrors SwordsmanServer) ────────────────────────────────────────
local SWING_INTERVAL = 0.3
local COMBO_RESET = 1.0
local MOMENTUM_MAX = 10
local MOMENTUM_SPEED = 0.04
local STORM_WINDUP = 0.8

local WHITE = Color3.fromRGB(255, 255, 255)
local GOLD = Color3.fromRGB(255, 214, 120)
local PALE = Color3.fromRGB(255, 244, 214)

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
-- edge over a gold glow; it eases outward as it fades. `cf` is the arc's
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
	l.TextStrokeColor3 = Color3.fromRGB(40, 20, 0)
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

-- ── Poses (CastPoses: +rx raises the arm forward, ry turns about vertical) ──
-- The sword sticks out of the fist, so the blade points along the arm tilted
-- 90° forward: arm hanging (rx 0) = blade level and forward, arm raised
-- (rx 90) = blade straight up. Flat slashes keep the arm low and turn it.
-- Whole-body, duelist-style moves: the knees bend and the body dips (Root
-- py), the torso coils and uncoils (W ry), the free arm flings for balance,
-- the feet split into lunges (RH / LH), and the big moves leave the ground.
local ROOT_SPIN = function(t0: number, delay: number, dur: number, turns: number)
	return function()
		local a = math.clamp((os.clock() - t0 - delay) / dur, 0, 1)
		return { Root = { 0, -(1 - (1 - a) ^ 2) * 360 * turns, 0 } }
	end
end

local function swingPose(char: Model, step: number)
	if step == 1 then
		-- Step-in slash: coil low to the right, then unleash across to the
		-- left, stepping into it with the off arm flung back.
		CastPoses.play(char, {
			{ dur = 0.07, pose = { Root = { 0, 0, 0, 0, -0.5, 0.2 }, W = { 10, 55, 0 }, RS = { 35, 95, 0 },
				LS = { 45, -20, -30 }, RH = { -25, 0, 0 }, LH = { 30, 0, 0 }, N = { 0, -30, 0 } } },
			{ dur = 0.1, pose = { Root = { 0, 0, 0, 0, -0.35, -0.7 }, W = { -10, -60, 0 }, RS = { 20, -105, 0 },
				LS = { -25, 0, -65 }, RH = { 35, 0, 0 }, LH = { -40, 0, 0 }, N = { 0, 25, 0 } } },
			{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, -0.2, -0.4 }, W = { -5, -40, 0 }, RS = { 15, -80, 0 },
				LS = { -10, 0, -40 }, RH = { 20, 0, 0 }, LH = { -20, 0, 0 } } },
		})
	elseif step == 2 then
		-- Rising cross slash: drop low on the left, then rip up and across
		-- to the right onto the toes.
		CastPoses.play(char, {
			{ dur = 0.07, pose = { Root = { 0, 0, 0, 0, -0.7, 0 }, W = { 18, -55, 0 }, RS = { -15, -85, 0 },
				LS = { 30, 0, -20 }, RH = { 30, 0, 0 }, LH = { -30, 0, 0 } } },
			{ dur = 0.1, pose = { Root = { 0, 0, 0, 0, 0.45, -0.3 }, W = { -22, 60, 0 }, RS = { 75, 100, 0 },
				LS = { 50, 0, -75 }, N = { -18, 20, 0 }, RH = { -15, 0, 0 }, LH = { 10, 0, 0 } } },
			{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, 0.2, -0.2 }, W = { -12, 40, 0 }, RS = { 60, 80, 0 }, LS = { 30, 0, -50 } } },
		})
	elseif step == 3 then
		-- Lunging thrust: sight down the off hand, then explode forward into a
		-- deep split with the blade driven straight out.
		CastPoses.play(char, {
			{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.6, 0.4 }, W = { 12, 40, 0 }, RS = { -35, 25, 0, 0, 0, 0.9 },
				LS = { 85, -10, -10 }, RH = { -35, 0, 0 }, LH = { 35, 0, 0 }, N = { 0, -35, 0 } } },
			{ dur = 0.09, pose = { Root = { 0, 0, 0, 0, -0.9, -1.4 }, W = { -28, -15, 0 }, RS = { 8, 0, 0, 0, 0, -1.2 },
				LS = { -35, 0, -55 }, RH = { -60, 0, 0 }, LH = { 50, 0, 0 }, N = { 12, 10, 0 } } },
			{ dur = 0.16, pose = { Root = { 0, 0, 0, 0, -0.6, -1 }, W = { -18, -10, 0 }, RS = { 6, 0, 0, 0, 0, -0.8 },
				LS = { -20, 0, -40 }, RH = { -45, 0, 0 }, LH = { 38, 0, 0 } } },
		})
	else
		-- Leaping spin finisher: crouch, spring up spinning one and a half
		-- turns with the blade out wide and the legs tucked, then slam down
		-- into a low landing.
		local t0 = os.clock()
		CastPoses.play(char, {
			{ dur = 0.07, pose = { Root = { 0, 0, 0, 0, -0.9, 0 }, W = { 18, 45, 0 }, RS = { 20, 0, 75 },
				LS = { 20, 0, -40 }, RH = { -30, 0, 0 }, LH = { -30, 0, 0 } } },
			{ dur = 0.32, pose = { Root = { 0, 0, 0, 0, 2.2, 0 }, W = { -8, 0, 0 }, RS = { 30, 0, 88 },
				LS = { 25, 0, -85 }, RH = { -55, 0, 0 }, LH = { -45, 0, 0 } },
				wobble = ROOT_SPIN(t0, 0.07, 0.32, 1.5) },
			{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -1, 0 }, W = { 28, 0, 0 }, RS = { -45, 0, 20 },
				LS = { 30, 0, -60 }, RH = { -35, 0, 0 }, LH = { 40, 0, 0 } } },
			{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, -0.6, 0 }, W = { 18, 0, 0 }, RS = { -30, 0, 20 } } },
		})
	end
end

-- Skill poses (shared by your cast and everyone else's view of it).
local function rushPose(char: Model, t: number)
	-- Coiled low, then a flat sprinting lunge with the blade swept behind.
	CastPoses.play(char, {
		{ dur = 0.05, pose = { Root = { 0, 0, 0, 0, -0.8, 0 }, W = { 25, 45, 0 }, RS = { 25, 90, 0 }, LS = { 40, 0, -30 },
			RH = { -40, 0, 0 }, LH = { 40, 0, 0 } } },
		{ dur = t, pose = { Root = { 0, 0, 0, 0, -0.6, 0 }, W = { -38, -35, 0 }, RS = { 20, -115, 0 }, LS = { -40, 0, -70 },
			RH = { -60, 0, 0 }, LH = { 60, 0, 0 }, N = { 20, 20, 0 } } },
		{ dur = 0.16, pose = { Root = { 0, 0, 0, 0, -0.4, 0 }, W = { -15, -30, 0 }, RS = { 15, -85, 0 }, LS = { -20, 0, -45 },
			RH = { -30, 0, 0 }, LH = { 30, 0, 0 } } },
	})
end

local function guardPose(char: Model, window: number)
	-- A wide, low duelist's guard: blade upright across the body, off hand
	-- braced on the flat, head turned to the threat.
	local p = { Root = { 0, 0, 0, 0, -0.55, 0 }, W = { 6, 25, 0 }, RS = { 72, -48, 0 }, LS = { 58, 38, 0 },
		RH = { -12, 0, 16 }, LH = { 12, 0, -16 }, N = { -8, -20, 0 } }
	CastPoses.play(char, {
		{ dur = 0.06, style = Enum.EasingStyle.Back, pose = p },
		{ dur = window, pose = p },
	})
end

local function counterPose(char: Model)
	-- Drop, then launch upward into a rising uppercut slash, airborne, then
	-- land.
	CastPoses.play(char, {
		{ dur = 0.05, pose = { Root = { 0, 0, 0, 0, -1, 0 }, W = { 25, 20, 0 }, RS = { -65, 0, 0 }, LS = { 20, 0, -30 },
			RH = { -40, 0, 0 }, LH = { 35, 0, 0 } } },
		{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, 2.4, 0 }, W = { -28, -10, 0 }, RS = { 135, 0, 0 }, LS = { -40, 0, -65 },
			RH = { -65, 0, 0 }, LH = { 20, 0, 0 }, N = { -25, 0, 0 } } },
		{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, 1.6, 0 }, W = { -15, 0, 0 }, RS = { 115, 0, 0 }, LS = { -20, 0, -50 },
			RH = { -35, 0, 0 }, LH = { -10, 0, 0 } } },
		{ dur = 0.12, pose = { Root = { 0, 0, 0, 0, -0.5, 0 }, W = { 15, 0, 0 }, RS = { 40, 0, 0 } } },
	})
end

local function whirlPose(char: Model, dur: number)
	-- Both arms flung wide, body leaning into the spin, hovering a little
	-- off the ground and spinning hard.
	local t0 = os.clock()
	CastPoses.play(char, {
		{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.5, 0 }, W = { 15, 40, 0 }, RS = { 25, 0, 88 }, LS = { 15, 0, -85 } } },
		{ dur = dur, pose = { Root = { -8, 0, 6, 0, 0.35, 0 }, W = { -10, 0, 0 }, RS = { 28, 0, 90 }, LS = { 18, 0, -88 },
			RH = { -15, 0, 12 }, LH = { 15, 0, -12 }, N = { 10, 0, 0 } },
			wobble = function() return { Root = { 0, -((os.clock() - t0) * 1300) % 360, 0 } } end },
	})
end

-- The slash shape each combo hit leaves in front of the attacker.
local function comboVFX(char: Model, step: number, dir: Vector3)
	local root = rootOf(char)
	if not root then return end
	local look = CFrame.lookAt(root.Position, root.Position + dir)
	trail(char, 0.3)
	if step == 1 then
		-- Right-to-left, tilted slightly.
		task.delay(0.06, crescent, look * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(-8)), 5.2, 140, GOLD, 0.7, 0.2, 1)
	elseif step == 2 then
		-- Left-to-right, rising.
		task.delay(0.06, crescent, look * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(14)), 5.2, 140, GOLD, 0.7, 0.2, -1)
	elseif step == 3 then
		task.delay(0.08, function()
			local p = root.Position + Vector3.new(0, 0.1, 0)
			streak(p + dir * 2, p + dir * 13, 0.5, GOLD, 0.04)
			ClassFX.Burst(p + dir * 13, PALE, 8, 12, ClassFX.TEX_SPARK, 0.3, 0.25)
		end)
	else
		-- A clean full-circle cut (the spin finisher) and a low ring.
		task.delay(0.1, function()
			crescent(CFrame.new(root.Position) * look.Rotation, 7, 340, GOLD, 1.1, 0.3, 1)
			ClassFX.Ring(root.Position, PALE, 11, 0.3, char)
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
		d.BackgroundColor3 = Color3.fromRGB(30, 26, 22)
		d.BorderSizePixel = 0
		d.Parent = row
		local s = Instance.new("UIStroke")
		s.Color = GOLD
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
	lbl.TextColor3 = GOLD
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
		d.BackgroundColor3 = if i <= m then (if m >= MOMENTUM_MAX then WHITE else GOLD) else Color3.fromRGB(30, 26, 22)
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
	swingPose(char, localStep)
	comboVFX(char, localStep, dir)
	ClassFX.Sound("whoosh", root, 0.6, if localStep == 4 then 0.85 else 1.1 + localStep * 0.05)
	if localStep == 3 then
		-- Short lunge with the thrust.
		root.AssemblyLinearVelocity = dir * 38 + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
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

-- A horizontal-only dash (gravity still works), like the Gunslinger's roll.
-- It stops short of walls / steps in the way and ends back on the floor.
local function dash(root: BasePart, dir: Vector3, dist: number, t: number)
	local stand = SafeMove.StandHeight(root)
	dist = SafeMove.ClampDash(root, dir, dist)
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
		lv:Destroy()
		att:Destroy()
		if root.Parent then
			root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			SafeMove.SnapToFloor(root, stand)
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
		local dist = (config.dashDistance or 20) * (if empowered then 1.5 else 1)
		local t = if empowered then 0.26 else 0.2
		if hum then hum.AutoRotate = false end
		dash(root, dir, dist, t)
		rushPose(char, t)
		trail(char, t + 0.25)
		ClassFX.Afterimages(char, PALE, 5, t / 5)
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
		-- Whirlwind: blade out wide, spinning; you can move while it runs.
		char:SetAttribute("AllowSkillMovement", true)
		local dur = config.duration or 1.2
		busyUntil = os.clock() + dur
		whirlPose(char, dur)
		trail(char, dur + 0.1)
		releaseAfter(char, dur)
	elseif skillIndex == 4 then
		-- Blade Storm: the wind-up close-up; the dash chain follows the
		-- server's "storm" moment (see onStorm).
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = math.huge
		UltimateCameraChoreography.PlayCloseUp(char, dir, STORM_WINDUP, nil, nil, {
			startOffset = { 7, 2.5, 1.2 },
			endOffset = { 5.2, 1.6, 0.8 },
			focusHeight = 1.4,
			fovStart = 50,
			fovEnd = 42,
		})
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

-- Another Swordsman's Blade Storm: the same wind-up close-up on them.
function SwordsmanController.PlayStormCutscene(char: Model, dir: Vector3)
	UltimateCameraChoreography.PlayCloseUp(char, dir, STORM_WINDUP, nil, nil, {
		startOffset = { 7, 2.5, 1.2 },
		endOffset = { 5.2, 1.6, 0.8 },
		focusHeight = 1.4,
		fovStart = 50,
		fovEnd = 42,
	})
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
	local color = if msg.empowered then WHITE else GOLD
	-- A bright comet along the dash wrapped in a bundle of thin speed lines.
	streak(from + Vector3.new(0, 1, 0), to + Vector3.new(0, 1, 0), if msg.empowered then 0.7 else 0.5, color, 0.25,
		if msg.empowered then 12 else 8)
	if char and msg.attacker ~= player then
		rushPose(char, if msg.empowered then 0.26 else 0.2)
		ClassFX.Afterimages(char, PALE, 5, 0.04)
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
		4.5, 130, if msg.empowered then WHITE else GOLD, 0.8, 0.22)
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
		width = 0.35, color = PALE, draw = msg.window, life = 0.15, grow = 0 })
	SwordFX.Stars(root.Position + root.CFrame.LookVector * 1.2 + Vector3.new(0, 2, 0), 4, 3)
end

local function onParry(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	-- The perfect-parry flash: a circle of light with rays bursting out of
	-- it, a small bright core and glinting stars.
	local center = pos + Vector3.new(0, 0.4, 0)
	SwordFX.Rays(center, 10, 18, GOLD, 0.4)
	SwordFX.Arc({ cf = CFrame.new(center), radius = 3.2, arc = 359, width = 0.5, color = WHITE, draw = 0.001, life = 0.3, grow = 0.4 })
	SwordFX.Stars(center, 18, 22)
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
		if msg.empowered then WHITE else GOLD, 1.6, 0.32, -1)
	SwordFX.Stars(pos + dir * 5 + Vector3.new(0, 2, 0), 12, 16)
	ClassFX.Sound("swordHit", pos, 1, 0.8)
	ClassFX.Sound("whoosh", pos, 0.9, 0.7)
	if msg.attacker == player then deps.shake(1, 0.25) end
end

local function onWhirl(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then
		whirlPose(char, msg.duration)
		trail(char, msg.duration + 0.1)
	end
	-- A vortex of light: concentric arcs whirling round the Swordsman for the
	-- whole spin.
	SwordFX.Spiral(function()
		return if root.Parent then root.Position - Vector3.new(0, 0.8, 0) else nil
	end, msg.radius, msg.duration, GOLD)
end

local function onWhirlEnd(msg: any)
	local root = rootOf(charOf(msg.attacker))
	if not root then return end
	-- The launching last cut: one wide ring of light flung outward.
	crescent(CFrame.new(root.Position - Vector3.new(0, 0.6, 0)) * root.CFrame.Rotation, msg.radius * 0.9, 350, GOLD, 1.3, 0.3)
	SwordFX.Stars(root.Position, 16, 26)
	ClassFX.Sound("swordHit", root, 0.9, 0.85)
	if msg.attacker == player then deps.shake(0.6, 0.18) end
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

	-- The arena darkens; the Swordsman burns white-gold.
	local myRoot = rootOf(player.Character)
	if isMine or (myRoot and (myRoot.Position - root.Position).Magnitude < 90) then darken(total) end
	local hl = Instance.new("Highlight")
	hl.FillColor = GOLD
	hl.FillTransparency = 0.7
	hl.OutlineColor = WHITE
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	hl.Adornee = char
	hl.Parent = ClassFX.Folder()
	Debris:AddItem(hl, total)
	-- Sword planted point-down, both hands on the pommel, head bowed; a
	-- burst at the feet during the wind-up.
	local planted = { RS = { 75, 0, -18 }, LS = { 75, 0, 18 },
		W = { -12, 0, 0 }, N = { -24, 0, 0 }, RH = { -6, 0, 12 }, LH = { 6, 0, -12 } }
	CastPoses.play(char, {
		{ dur = 0.15, style = Enum.EasingStyle.Back, pose = planted },
		{ dur = math.max(msg.windup - 0.15, 0.05), pose = planted },
	})
	-- Reverse the grip for the wind-up (blade out of the bottom of the fist =
	-- point-down in front with the hands at the chest), then restore it.
	local tool = char:FindFirstChild("Longsword")
	if tool and tool:IsA("Tool") then
		local normal = tool.Grip
		tool.Grip = SwordModel.FlippedGrip(normal)
		task.delay(msg.windup, function() if tool.Parent then tool.Grip = normal end end)
	end
	-- Energy gathers: a column of light through the planted blade and a
	-- circle of light drawn round the feet.
	local feet = root.Position - Vector3.new(0, 2.6, 0)
	SwordFX.Streak(feet, feet + Vector3.new(0, 16, 0), 1.2, GOLD, msg.windup - 0.1)
	SwordFX.Arc({ cf = CFrame.new(feet + Vector3.new(0, 0.2, 0)), radius = 4.5, arc = 359, width = 0.6, color = GOLD,
		draw = msg.windup * 0.6, life = 0.4, grow = 0.2 })
	SwordFX.Stars(feet + Vector3.new(0, 1, 0), 14, 6)
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
			ClassFX.Afterimages(char, PALE, 2, 0.03)
			-- Long crossing streaks that hang in the air ~0.3 s, a slash on
			-- the target and a few glints.
			streak(prev + Vector3.new(0, 1.2, 0), land + Vector3.new(0, 1.2, 0), 0.55, GOLD, 0.3, 3)
			crescent(CFrame.lookAt(t.Position, t.Position + d) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 30 else -30)),
				4.5, 130, WHITE, 0.9, 0.22, if i % 2 == 0 then -1 else 1)
			SwordFX.Stars(t.Position, 6, 14)
			ClassFX.Sound("swordHit", t.Position, 0.7, 1 + i * 0.05)
			prev = land
			-- Flourishes everyone sees: alternating slashes, and a leaping
			-- spin on every fourth cut.
			swingPose(char, if i % 4 == 0 then 4 else ((i - 1) % 2) + 1)
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
		SwordFX.Blade(c, d, r * 2.6, 3.2, GOLD, 0.35)
	end
	task.delay(0.05, function()
		for _, ang in ipairs({ 38, -52 }) do
			SwordFX.Blade(c, CFrame.Angles(0, math.rad(ang), 0) * flatDir, r * 1.8, 1.2, WHITE, 0.2)
		end
	end)
	SwordFX.Stars(c, 50, 45)
	ClassFX.Burst(c, PALE, 30, 30, ClassFX.TEX_SPARK, 0.5, 0.6)
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
	if msg.attacker == player then popWord(char, "MOMENTUM MAX", GOLD, 24) end
end

local function onEmpowered(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	ClassFX.Ring(root.Position, WHITE, 8, 0.3, char)
	ClassFX.Burst(root.Position + Vector3.new(0, 1, 0), GOLD, 30, 18, ClassFX.TEX_SPARK, 0.6, 0.5)
	popWord(char, "EMPOWERED", WHITE, 22)
end

local HANDLERS: { [string]: (any) -> () } = {
	combo = onCombo,
	rush = onRush,
	rushCut = onRushCut,
	guard = onGuard,
	parry = onParry,
	counter = onCounter,
	whirl = onWhirl,
	whirlEnd = onWhirlEnd,
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

return SwordsmanController
