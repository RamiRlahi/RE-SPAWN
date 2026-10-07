--!strict
--[[
	BerserkerController.luau
	Client side of the Berserker, the Crimson Ravager (server: BerserkerServer).
	Crimson energy, black smoke, fractured ground and red afterimages; heavy
	anticipation, explosive acceleration, impact pauses, camera kicks.

	  • The greatsword chain: your own swings are predicted (two-handed pose,
	    crimson trail, arc) on click; the server resolves hits and sends
	    everyone else's over BerserkerFX.
	  • E Rupture: crouch (the floor cracks red), leap, hang with the blade
	    overhead (debris pulled up below), crash: crimson flash, crater,
	    spreading fracture, shockwave, lingering dust and embers.
	  • F Bloodstorm: lean and drag the blade (a red streak ignites), then,
	    rooted to the spot, huge crimson crescents carved out in front: each
	    swing heaved round and hacked down, held a beat as it bites (the
	    hit-stop), the floor cracking and rock flying where it lands, a jolt
	    of the camera; then a spinning cleave with a big shockwave.
	  • Q Crimson Charge: a low lean (the floor splits under him), then a
	    headlong charge at the aim in a red streak, untouchable, enemies in
	    the path thrown aside; a crimson burst at the end blows the rest away.
	    The NEXT skill is Empowered (bigger and more violent).
	  • R Beast Awakening (a full Rage meter): he freezes, red lightning tears
	    out of him as the body distorts, the sword is flung aside to stick in
	    the floor, then the roar (a shockwave, the world flashing red). As the
	    BEAST (12 s; the body itself is the server's: BerserkerLook.DressBeast)
	    he hunches and bounds, lands heavy, and the blazing look runs: claws
	    (three red gashes a rake, then the maul), Beast Slam (an enormous leap,
	    a crash on all fours, three rings rolling out), Carnage (three huge
	    claw swipes, the last a rake down), Beast Charge (a gallop on all fours,
	    the biggest one hoisted overhead and hurled). Then down on one knee,
	    the sword reforming in his hand.
	  • The Rage meter above the skill bar ("RAGE FULL" when R is ready), the
	    beast's timer while it lasts.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local player = Players.LocalPlayer

local BerserkerController = {}

-- ── Tuning (mirrors BerserkerServer) ────────────────────────────────────────
local SWING_INTERVAL = 0.48
local COMBO_RESET = 1.2
-- Crimson Charge: the lean, then the run (mirrors BerserkerServer).
local CHARGE = { windup = 0.18, run = 0.45 }
local CHARGE_DIST = 28
local RUPTURE = { crouch = 0.32, rise = 0.3, hang = 0.18, fall = 0.14 }
RUPTURE.impact = RUPTURE.crouch + RUPTURE.rise + RUPTURE.hang + RUPTURE.fall
local RUPTURE_RANGE = 17 -- the furthest leap (to the cursor)
local RUPTURE_HEIGHT = 9
-- Rage and the Beast Awakening, and the beast's kit (mirrors BerserkerServer).
local RAGE_MAX = 100
local BEAST = { freeze = 0.45, mutate = 1.15, roar = 0.5 }
BEAST.change = BEAST.freeze + BEAST.mutate
BEAST.total = BEAST.change + BEAST.roar
local BEAST_TIME = 12
local BEAST_REVERT = 1.2
local CLAW_INTERVAL = 0.34
local CLAW_RESET = 1.0
local SLAM = { crouch = 0.2, rise = 0.42, hang = 0.12, fall = 0.16 }
SLAM.impact = SLAM.crouch + SLAM.rise + SLAM.hang + SLAM.fall
local SLAM_RANGE = 26
local SLAM_HEIGHT = 30
local CARNAGE = { 0.22, 0.5, 0.88 }
local BCHARGE = { crouch = 0.15, run = 0.6, grab = 0.45, throw = 0.25 }
local BCHARGE_DIST = 38

local CRIMSON = Color3.fromRGB(205, 14, 30)
local BLOOD = Color3.fromRGB(120, 6, 16)
local BLACK = Color3.fromRGB(14, 8, 10)
local HOT = Color3.fromRGB(255, 70, 80)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

type Deps = {
	shake: (number, number) -> (),
	fovPunch: (number, number) -> (),
	getAim: (BasePart) -> Vector3,
}
local deps: Deps

local localStep = 0
local lastSwing = 0
local busyUntil = 0
-- (Unchained keeps the blade's afterimage on)
local persistTrail: { [Model]: boolean } = {}

local function isBerserker(p: Player?): boolean
	return (p or player):GetAttribute("SelectedClass") == "berserker"
end

-- Seconds of Beast Form left (the blazing look runs while it lasts).
local function beastLeft(p: Player): number
	return (tonumber(p:GetAttribute("BR_BeastUntil")) or 0) - Workspace:GetServerTimeNow()
end

local function rageOf(p: Player): number
	return tonumber(p:GetAttribute("BR_Rage")) or 0
end

local function rootOf(char: Model?): BasePart?
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function charOf(p: Player?): Model?
	return p and p.Character or nil
end

local function flatDir(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else fallback
end

-- Players near enough to feel a blow (camera shake, flashes).
local function near(pos: Vector3, dist: number): boolean
	local r = rootOf(player.Character)
	return r ~= nil and (r.Position - pos).Magnitude < dist
end

-- ── VFX pieces (after the Berserker concept sheet) ─────────────────────────
-- Black and deep crimson only: glowing crimson ribbons with hot pink-white
-- cores, tall jagged crimson and black shards, black rock debris, jagged red
-- ground cracks, dark smoke and red sparks.
local SHARD_BLACK = Color3.fromRGB(24, 14, 17)
local ROCK = Color3.fromRGB(38, 30, 33)
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"

local CORE = Color3.fromRGB(255, 120, 130) -- the hot pink-red heart of every ribbon

local function arc(cf: CFrame, radius: number, span: number, color: Color3, width: number, life: number, sweep: number?, draw: number?)
	SwordFX.Arc({ cf = cf, radius = radius, arc = span, sweep = sweep, width = width, color = color, life = life, draw = draw, core = CORE })
end

local function smoke(pos: Vector3, count: number, size: number)
	ClassFX.Burst(pos, Color3.fromRGB(40, 6, 10), count, 5, TEX_SMOKE, size, 1.2)
end

local function sparks(pos: Vector3, count: number, speed: number)
	ClassFX.Burst(pos, CRIMSON, count, speed, ClassFX.TEX_SPARK, 0.4, 0.55)
end

-- Flying bits flung out from `pos`: small black and crimson chips, or
-- (rocks = true) chunks of black stone. Real physics, then they fade.
local function fling(pos: Vector3, count: number, speed: number, lift: number, rocks: boolean?)
	for i = 1, count do
		local p: BasePart = if rocks then Instance.new("Part") else Instance.new("WedgePart")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false, false
		p.Massless = true
		if rocks then
			local s = 0.5 + math.random() * 1.1
			p.Size = Vector3.new(s, s * (0.6 + math.random() * 0.5), s * (0.7 + math.random() * 0.4))
			p.Material = Enum.Material.Slate
			p.Color = ROCK
		else
			p.Size = Vector3.new(0.12, 0.4 + math.random() * 0.9, 0.3 + math.random() * 0.6)
			local glow = i % 3 == 0
			p.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
			p.Color = if glow then CRIMSON else SHARD_BLACK
		end
		p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = ClassFX.Folder()
		local a = math.random() * math.pi * 2
		p.AssemblyLinearVelocity = Vector3.new(math.cos(a), 0, math.sin(a)) * speed * (0.5 + math.random() * 0.7)
			+ Vector3.new(0, lift * (0.5 + math.random() * 0.8), 0)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, if rocks then 0.8 else 0.35),
			{ Transparency = 1 }):Play()
		Debris:AddItem(p, if rocks then 1.4 else 0.95)
	end
end

-- Jagged glowing red cracks running out across the ground from `pos`.
local function cracks(pos: Vector3, radius: number, count: number, life: number)
	local y = pos.Y + 0.08
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + math.random() * 0.5
		local at = Vector3.new(pos.X, y, pos.Z)
		local len = radius * (0.5 + math.random() * 0.5)
		local steps = 3 + math.random(0, 2)
		for s = 1, steps do
			a += (math.random() - 0.5) * 0.9
			local l = len / steps
			local nxt = at + Vector3.new(math.cos(a), 0, math.sin(a)) * l
			local mid = (at + nxt) / 2
			local w = 0.45 * (1 - (s - 1) / steps) + 0.1
			local c = ClassFX.Neon({ Size = Vector3.new(w, 0.06, l + 0.2), CFrame = CFrame.lookAt(mid, nxt), Color = CRIMSON, Transparency = 0.05 })
			TweenService:Create(c, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Color = BLOOD }):Play()
			Debris:AddItem(c, life + 0.05)
			at = nxt
		end
	end
end

-- Tall jagged shards bursting out of the ground and leaning away from `pos`:
-- glowing crimson crystals and black ones (the sheet's Bloodquake and final
-- slam). They punch up fast, hold, then sink back.
local function shards(pos: Vector3, radius: number, count: number, hMin: number, hMax: number, life: number?)
	local L = life or 0.8
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + math.random() * 0.6
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = pos + dir * radius * (0.3 + math.random() * 0.7)
		local h = hMin + math.random() * (hMax - hMin)
		local w = 0.7 + math.random() * h * 0.16
		local glow = math.random() < 0.62
		-- Top tipped outward 8–28°, a little twist.
		local rot = CFrame.lookAt(base, base + dir) * CFrame.Angles(-math.rad(8 + math.random() * 20), 0, 0)
			* CFrame.Angles(0, math.random() * 6, 0)
		-- A corner wedge: one sheer face and a sharp tip, like a broken crystal.
		local s = Instance.new("CornerWedgePart")
		s.Anchored, s.CanCollide, s.CanQuery, s.CanTouch, s.CastShadow = true, false, false, false, false
		s.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
		s.Color = if glow then (if math.random() < 0.7 then CRIMSON else BLOOD) else SHARD_BLACK
		local sunk = rot * CFrame.new(0, -h / 2, 0)
		local up = rot * CFrame.new(0, h / 2 - 0.4, 0)
		s.Size = Vector3.new(w, h, w)
		s.CFrame = sunk
		s.Parent = ClassFX.Folder()
		TweenService:Create(s, TweenInfo.new(0.09 + math.random() * 0.06, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = up }):Play()
		-- (sink after a pause: a second CFrame tween played now would cancel
		-- the rise straight away)
		task.delay(L * 0.6, function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = sunk, Transparency = 0.6 }):Play()
			end
		end)
		Debris:AddItem(s, L * 0.6 + 0.45)
	end
end

-- A faint, quick crimson pulse on the ground (the impact's glow; kept
-- subtle so the cracks and shards stay the bright part, as on the sheet).
local function groundFlash(pos: Vector3, radius: number)
	local d = ClassFX.Neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, radius * 0.4, radius * 0.4),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = BLOOD, Transparency = 0.7 })
	TweenService:Create(d, TweenInfo.new(0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.1, radius * 1.4, radius * 1.4), Transparency = 1 }):Play()
	Debris:AddItem(d, 0.25)
end

-- A shockwave: thin glowing rings racing outward along the ground (rings,
-- not filled discs, so the ground stays dark between them).
local function shockwave(pos: Vector3, radius: number, _char: Model?)
	local cf = CFrame.new(pos + Vector3.new(0, 0.25, 0))
	SwordFX.Arc({ cf = cf, radius = radius * 0.55, arc = 359, width = 1.1, color = CRIMSON, life = 0.35, draw = 0.001, grow = 0.85, core = CORE })
	task.delay(0.08, function()
		SwordFX.Arc({ cf = cf, radius = radius * 0.4, arc = 359, width = 0.6, color = BLOOD, life = 0.4, draw = 0.001, grow = 1.1, core = CRIMSON })
	end)
end

-- A crimson blast: a short sphere flash (quick, so it doesn't bury the
-- shards) with black smoke rolling out.
local function blast(pos: Vector3, radius: number)
	local b = ClassFX.Neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)),
		Color = CRIMSON, Transparency = 0.35 })
	TweenService:Create(b, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * radius * 0.9, Transparency = 1, Color = BLOOD }):Play()
	Debris:AddItem(b, 0.18)
	smoke(pos + Vector3.new(0, 1, 0), 18, 4)
	sparks(pos + Vector3.new(0, 1, 0), 36, 34)
end

-- A vertical column of red light (the final slam).
local function lightPillar(pos: Vector3, height: number, width: number, life: number)
	for _, layer in ipairs({ { w = width, c = CRIMSON, t = 0.35 }, { w = width * 0.3, c = HOT, t = 0 } }) do
		local p = ClassFX.Neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, layer.w, layer.w),
			CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = layer.c, Transparency = layer.t })
		TweenService:Create(p, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = Vector3.new(height, 0.05, 0.05), Transparency = 1 }):Play()
		Debris:AddItem(p, life + 0.05)
	end
end

-- A jagged crimson lightning bolt from a to b, flickering out.
local function bolt(a: Vector3, b: Vector3, width: number, life: number)
	local steps = 6
	local prev = a
	local dir = b - a
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 0.01 then side = Vector3.xAxis end
	side = side.Unit
	local side2 = dir.Unit:Cross(side)
	for s = 1, steps do
		local t = s / steps
		local nxt = if s == steps then b else a + dir * t + (side * (math.random() - 0.5) + side2 * (math.random() - 0.5)) * dir.Magnitude * 0.18
		local mid = (prev + nxt) / 2
		local len = (nxt - prev).Magnitude
		for _, layer in ipairs({ { w = width, c = CRIMSON, tr = 0.2 }, { w = width * 0.35, c = HOT, tr = 0 } }) do
			local seg = ClassFX.Neon({ Size = Vector3.new(layer.w, layer.w, len + layer.w), CFrame = CFrame.lookAt(mid, nxt), Color = layer.c, Transparency = layer.tr })
			TweenService:Create(seg, TweenInfo.new(life), { Transparency = 1 }):Play()
			Debris:AddItem(seg, life + 0.05)
		end
		prev = nxt
	end
end

-- The sheet's slash ring: several crimson ribbons with hot cores at slightly
-- different radii, heights and tilts, swirling round in the swing's
-- direction, plus black chips thrown off. `cf` is the centre and facing (the
-- arc bulges toward cf's -Z).
local function slashRing(cf: CFrame, radius: number, span: number, sweep: number?, heavy: boolean?)
	local layers = if heavy then 4 else 3
	for i = 1, layers do
		local k = 0.86 + (i - 1) * 0.1
		local tilt = CFrame.Angles(math.rad((i - 2) * 3.5), 0, math.rad(if i % 2 == 0 then 3 else -3))
		task.delay((i - 1) * 0.03, arc, cf * CFrame.new(0, (i - 2) * 0.3, 0) * tilt, radius * k, span, CRIMSON,
			if i == 2 then radius * 0.32 else radius * 0.14, 0.26 + i * 0.05, sweep, 0.1)
	end
	-- A faint red sheen swept across the ground under it.
	SwordFX.Sweep({ cf = cf * CFrame.new(0, -2.4, 0), inner = radius * 0.25, outer = radius, arc = span, sweep = sweep,
		color = BLOOD, life = 0.3, draw = 0.1, opacity = 0.45 })
end

-- Black and crimson chips thrown off the rim of a ring swing.
local function rimChips(center: Vector3, radius: number, count: number)
	for i = 1, count do
		local a = math.random() * math.pi * 2
		fling(center + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * (0.8 + math.random() * 0.3), 1, 26, 8)
	end
end

-- The greatsword's crimson trail (built on the Ragebringer's edge).
local function ensureTrail(char: Model): Trail?
	local tool = char:FindFirstChild("Ragebringer")
	local a0 = tool and tool:FindFirstChild("RageBase", true)
	local edge = a0 and a0.Parent
	if not edge then return nil end
	local t = edge:FindFirstChild("RageTrail") :: Trail?
	if t then return t end
	local a1 = edge:FindFirstChild("RageTip")
	if not (a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment")) then return nil end
	local tr = Instance.new("Trail")
	tr.Name = "RageTrail"
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, HOT), ColorSequenceKeypoint.new(0.35, CRIMSON), ColorSequenceKeypoint.new(1, BLACK) })
	tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 1) })
	tr.Lifetime = 0.28
	tr.MinLength = 0.05
	tr.LightEmission = 0.8
	tr.FaceCamera = false
	tr.Enabled = false
	tr.Parent = edge
	return tr
end

local function trail(char: Model, seconds: number)
	local t = ensureTrail(char)
	if t then
		t.Enabled = true
		task.delay(seconds, function() if t.Parent and not persistTrail[char] then t.Enabled = false end end)
	end
end

local function popWord(char: Model, text: string, size: number)
	local root = rootOf(char)
	if not root then return end
	local bb = Instance.new("BillboardGui")
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(240, 60)
	bb.StudsOffset = Vector3.new(0, 4.4, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = ClassFX.Folder()
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.GothamBlack
	l.Text = text
	l.TextSize = size
	l.TextColor3 = CRIMSON
	l.TextStrokeColor3 = Color3.new(0, 0, 0)
	l.TextStrokeTransparency = 0
	l.Parent = bb
	local sc = Instance.new("UIScale")
	sc.Scale = 1.8
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(bb, 1.1)
end

-- ── Poses: two hands on the hilt (CastPoses: +rx raises an arm forward) ─────
-- Both arms reach to the grip: the left arm crosses in (LS ry +) to meet the
-- right. Heavy, grounded moves: wide stance, deep knees, the torso does the work.
local SPIN = function(t0: number, delay: number, dur: number, turns: number)
	return function()
		local a = math.clamp((os.clock() - t0 - delay) / dur, 0, 1)
		return { Root = { 0, -(1 - (1 - a) ^ 2) * 360 * turns, 0 } }
	end
end

local function swingPose(char: Model, step: number)
	if step == 1 then
		-- Diagonal cleave: wound high over the right shoulder, then hacked down
		-- and across to the left hip.
		CastPoses.play(char, {
			{ dur = 0.12, pose = { Root = { 0, 0, 0, 0, -0.4, 0.2 }, W = { 8, 50, 0 }, RS = { 150, 40, 0 }, LS = { 140, 60, 0 },
				RH = { -18, 0, 8 }, LH = { 22, 0, -8 }, N = { 0, -25, 0 } } },
			{ dur = 0.1, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.8, -0.6 }, W = { -22, -45, 0 }, RS = { 20, -60, 0 },
				LS = { 25, -30, 0 }, RH = { 30, 0, 8 }, LH = { -30, 0, -8 }, N = { 10, 20, 0 } } },
			{ dur = 0.22, pose = { Root = { 0, 0, 0, 0, -0.6, -0.4 }, W = { -15, -35, 0 }, RS = { 15, -50, 0 }, LS = { 20, -25, 0 },
				RH = { 20, 0, 8 }, LH = { -20, 0, -8 } } },
		}, 0.3)
	elseif step == 2 then
		-- Backhand: dragged low from the left and ripped up and across to the right.
		CastPoses.play(char, {
			{ dur = 0.1, pose = { Root = { 0, 0, 0, 0, -0.7, 0 }, W = { 15, -55, 0 }, RS = { 30, -80, 0 }, LS = { 35, -50, 0 },
				RH = { 25, 0, 8 }, LH = { -25, 0, -8 } } },
			{ dur = 0.1, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.2, -0.3 }, W = { -18, 60, 0 }, RS = { 80, 90, 0 },
				LS = { 70, 100, 0 }, RH = { -20, 0, 8 }, LH = { 20, 0, -8 }, N = { -10, -20, 0 } } },
			{ dur = 0.2, pose = { Root = { 0, 0, 0, 0, -0.3, -0.2 }, W = { -10, 45, 0 }, RS = { 65, 75, 0 }, LS = { 55, 85, 0 } } },
		}, 0.3)
	else
		-- Overhead smash: heaved high behind the head, then brought straight down
		-- into the ground.
		CastPoses.play(char, {
			{ dur = 0.18, pose = { Root = { 0, 0, 0, 0, -0.3, 0.3 }, W = { 22, 0, 0 }, RS = { 175, 10, 0 }, LS = { 170, -10, 0 },
				RH = { -12, 0, 10 }, LH = { 12, 0, -10 }, N = { -20, 0, 0 } } },
			{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -1.2, -0.5 }, W = { -40, 0, 0 }, RS = { 35, 0, 0 },
				LS = { 35, 0, 0 }, RH = { 35, 0, 12 }, LH = { -35, 0, -12 }, N = { 20, 0, 0 } } },
			{ dur = 0.28, pose = { Root = { 0, 0, 0, 0, -1, -0.4 }, W = { -32, 0, 0 }, RS = { 30, 0, 0 }, LS = { 30, 0, 0 },
				RH = { 30, 0, 12 }, LH = { -30, 0, -12 } } },
		}, 0.35)
	end
end

local function raisePose(char: Model, windup: number)
	-- Bloodquake: both hands heave the greatsword straight up, back arched...
	CastPoses.play(char, {
		{ dur = windup * 0.85, pose = { Root = { 0, 0, 0, 0, 0.2, 0 }, W = { 18, 0, 0 }, RS = { 178, 0, 0 }, LS = { 175, 0, 0 },
			RH = { -8, 0, 12 }, LH = { 8, 0, -12 }, N = { -25, 0, 0 } } },
		-- ...and drives it down into the ground in a deep crouch.
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -1.4, -0.4 }, W = { -45, 0, 0 }, RS = { 20, 0, 0 },
			LS = { 20, 0, 0 }, RH = { 45, 0, 14 }, LH = { -40, 0, -14 }, N = { 25, 0, 0 } } },
		{ dur = 0.35, pose = { Root = { 0, 0, 0, 0, -1.2, -0.4 }, W = { -38, 0, 0 }, RS = { 18, 0, 0 }, LS = { 18, 0, 0 },
			RH = { 40, 0, 14 }, LH = { -35, 0, -14 } } },
	}, 0.35)
end

local function cleavePose(char: Model)
	-- Crimson Cleave: a full turn with the blade held out wide in both hands.
	local t0 = os.clock()
	CastPoses.play(char, {
		{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.6, 0 }, W = { 12, 70, 0 }, RS = { 30, 0, 80 }, LS = { 40, 60, 0 },
			RH = { -20, 0, 10 }, LH = { 20, 0, -10 } } },
		{ dur = 0.3, pose = { Root = { 0, 0, 0, 0, -0.5, 0 }, W = { -5, 0, 0 }, RS = { 25, 0, 88 }, LS = { 30, 50, 30 },
			RH = { -15, 0, 12 }, LH = { 15, 0, -12 } }, wobble = SPIN(t0, 0.08, 0.3, 1) },
		{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, -0.6, 0 }, W = { 10, -30, 0 }, RS = { 20, -40, 0 }, LS = { 25, -20, 0 } } },
	}, 0.3)
end

local function ruinPose(char: Model)
	-- Ruinous Slash: a huge lunging swing from low right, flung forward.
	CastPoses.play(char, {
		{ dur = 0.1, pose = { Root = { 0, 0, 0, 0, -0.7, 0.3 }, W = { 20, 60, 0 }, RS = { 10, 90, 0 }, LS = { 20, 70, 0 },
			RH = { -35, 0, 10 }, LH = { 40, 0, -10 } } },
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.9, -1.2 }, W = { -35, -40, 0 }, RS = { 95, -30, 0 },
			LS = { 90, -10, 0 }, RH = { -55, 0, 10 }, LH = { 50, 0, -10 }, N = { 15, 15, 0 } } },
		{ dur = 0.25, pose = { Root = { 0, 0, 0, 0, -0.8, -1 }, W = { -28, -35, 0 }, RS = { 85, -25, 0 }, LS = { 80, -10, 0 },
			RH = { -45, 0, 10 }, LH = { 40, 0, -10 } } },
	}, 0.3)
end

-- ── Crimson flipbooks (the VFX library's explosion / crack / shock
-- textures, recoloured blood red) ───────────────────────────────────────────
local function seq(a: Color3, b: Color3?): ColorSequence
	return ColorSequence.new(a, b or a)
end

local function flipbook(kind: string, pos: Vector3, size: number, n: number, color: ColorSequence, brightness: number?)
	return FireFX.Puff(kind, CFrame.new(pos), size, n, function(e)
		e.Color = color
		if brightness then e.Brightness = brightness end
	end)
end

-- The crash: the fireball flash, the crater, the fractured floor and the
-- shock ring, all crimson.
local function crimsonImpact(g: Vector3, radius: number, big: boolean?)
	local up = g + Vector3.new(0, 0.15, 0)
	flipbook("crater", up, radius * 0.9, 1, seq(Color3.fromRGB(255, 60, 70)), 3)
	flipbook("crack", up, radius * 2, 1, seq(CRIMSON), 3)
	flipbook("shock", up + Vector3.new(0, 0.1, 0), radius * 2.4, 1, seq(Color3.fromRGB(255, 120, 120), CRIMSON), 3)
end

-- Dust and red embers that hang about a crater after the blow.
local function linger(g: Vector3, radius: number, seconds: number)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Transparency = 1
	a.Size = Vector3.new(radius * 1.4, 0.2, radius * 1.4)
	a.CFrame = CFrame.new(g + Vector3.new(0, 0.3, 0))
	a.Parent = ClassFX.Folder()
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = TEX_SMOKE
	dust.Color = seq(Color3.fromRGB(70, 46, 46), Color3.fromRGB(26, 16, 18))
	dust.LightInfluence = 0.5
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	dust.Lifetime = NumberRange.new(1.4, 2.2)
	dust.Speed = NumberRange.new(0.5, 2)
	dust.Acceleration = Vector3.new(0, 1.2, 0)
	dust.Rate = radius * 1.5
	dust.Parent = a
	local ember = Instance.new("ParticleEmitter")
	ember.Texture = ClassFX.TEX_SPARK
	ember.Color = seq(HOT, CRIMSON)
	ember.LightEmission = 1
	ember.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	ember.Lifetime = NumberRange.new(1.2, 2.2)
	ember.Speed = NumberRange.new(1, 3)
	ember.Acceleration = Vector3.new(0, 3, 0)
	ember.SpreadAngle = Vector2.new(30, 30)
	ember.Rate = radius * 2
	ember.Parent = a
	task.delay(seconds, function()
		dust.Enabled = false
		ember.Enabled = false
	end)
	Debris:AddItem(a, seconds + 2.4)
end

-- Chunks of floor torn loose and pulled up around `g` (before a blow lands):
-- they rise and spin in place; `release` flings them out (at the impact).
local function liftDebris(g: Vector3, radius: number, count: number, height: number, rise: number): () -> ()
	local rocks: { BasePart } = {}
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local at = g + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * (0.25 + math.random() * 0.75)
		local s = 0.4 + math.random() * 0.9
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Size = Vector3.new(s, s * 0.7, s * 0.9)
		p.Material = Enum.Material.Slate
		p.Color = Color3.fromRGB(46, 36, 38)
		p.CFrame = CFrame.new(at) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = ClassFX.Folder()
		local top = at + Vector3.new(0, height * (0.4 + math.random() * 0.6), 0)
		TweenService:Create(p, TweenInfo.new(rise * (0.7 + math.random() * 0.3), Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(top) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6) }):Play()
		Debris:AddItem(p, 6)
		table.insert(rocks, p)
	end
	return function()
		for _, p in ipairs(rocks) do
			if p.Parent then
				p.Anchored = false
				p.Massless = true
				local out = Vector3.new(p.Position.X - g.X, 0, p.Position.Z - g.Z)
				out = if out.Magnitude > 0.1 then out.Unit else Vector3.xAxis
				p.AssemblyLinearVelocity = out * (14 + math.random() * 14) + Vector3.new(0, 10 + math.random() * 22, 0)
				p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 24
				TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.1),
					{ Transparency = 1 }):Play()
				Debris:AddItem(p, 1.7)
			end
		end
	end
end

-- Red motes drawn in from all round toward `getAt()` (the Worldbreaker's
-- gathering).
local function motesIn(getAt: () -> Vector3, radius: number, count: number, dur: number)
	for i = 1, count do
		task.delay((i / count) * dur * 0.6, function()
			local c = getAt()
			local a = math.random() * math.pi * 2
			local from = c + Vector3.new(math.cos(a) * radius, math.random() * 3 - 1, math.sin(a) * radius)
			local m = ClassFX.Neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * (0.25 + math.random() * 0.3),
				CFrame = CFrame.new(from), Color = if math.random() < 0.3 then HOT else CRIMSON, Transparency = 0.1 })
			local t = dur * 0.4 + math.random() * 0.2
			local t0 = os.clock()
			local conn: RBXScriptConnection
			conn = RunService.RenderStepped:Connect(function()
				local k = math.clamp((os.clock() - t0) / t, 0, 1)
				local to = getAt()
				m.CFrame = CFrame.new(from:Lerp(to, k * k))
				m.Size = Vector3.one * (0.5 * (1 - k) + 0.08)
				if k >= 1 then
					conn:Disconnect()
					m:Destroy()
				end
			end)
		end)
	end
end

-- A crimson spiral wound round a rising body (call each frame with its
-- position; it lays a ribbon that fades).
local function spiralStep(at: Vector3, angle: number, radius: number, last: { Vector3 }?): { Vector3 }
	local out = {}
	for k = 0, 1 do
		local a = angle + k * math.pi
		local p = at + Vector3.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		local prev = last and last[k + 1]
		if prev and (p - prev).Magnitude > 0.05 then
			local len = (p - prev).Magnitude
			for _, layer in ipairs({ { w = 0.9, c = CRIMSON, tr = 0.25 }, { w = 0.3, c = HOT, tr = 0 } }) do
				local seg = ClassFX.Neon({ Size = Vector3.new(layer.w, layer.w, len + layer.w),
					CFrame = CFrame.lookAt((p + prev) / 2, p), Color = layer.c, Transparency = layer.tr })
				TweenService:Create(seg, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Transparency = 1, Size = Vector3.new(0.05, 0.05, len) }):Play()
				Debris:AddItem(seg, 0.6)
			end
		end
		out[k + 1] = p
	end
	return out
end

-- A gigantic blade of red energy dragged behind the diver; returns its
-- updater (call with his body's CFrame) and a remover.
local function energyBlade(scale: number): ((CFrame) -> (), () -> ())
	local pieces: { { p: BasePart, off: CFrame } } = {}
	local function piece(size: Vector3, off: CFrame, color: Color3, tr: number, class: string?)
		local p = if class == "wedge" then Instance.new("WedgePart") else Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Size = size
		p.Color = color
		p.Transparency = tr
		p.Parent = ClassFX.Folder()
		table.insert(pieces, { p = p, off = off })
	end
	-- (held over his right shoulder, trailing up and back)
	local base = CFrame.new(1.2, 2, 1.5) * CFrame.Angles(math.rad(55), 0, math.rad(-10))
	piece(Vector3.new(0.5 * scale, 2.6 * scale, 16 * scale), base * CFrame.new(0, 0, 8 * scale), CRIMSON, 0.35)
	piece(Vector3.new(0.25 * scale, 1.1 * scale, 15 * scale), base * CFrame.new(0, 0, 7.6 * scale), HOT, 0.05)
	piece(Vector3.new(0.4 * scale, 2.6 * scale, 3 * scale), base * CFrame.new(0, 0, 17.4 * scale) * CFrame.Angles(0, math.pi, 0), CRIMSON, 0.35, "wedge")
	return function(cf: CFrame)
		for _, q in ipairs(pieces) do q.p.CFrame = cf * q.off end
	end, function()
		for _, q in ipairs(pieces) do
			TweenService:Create(q.p, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			Debris:AddItem(q.p, 0.25)
		end
	end
end

-- The screen flashes white, then red (the Worldbreaker's blow).
local function screenFlash(strength: number)
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local g = Instance.new("ScreenGui")
	g.Name = "BerserkerFlash"
	g.IgnoreGuiInset = true
	g.DisplayOrder = 90
	g.Parent = pg
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 0.92, 0.92)
	f.BackgroundTransparency = 1 - strength
	f.Parent = g
	TweenService:Create(f, TweenInfo.new(0.08), { BackgroundColor3 = CRIMSON }):Play()
	TweenService:Create(f, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, 0.08),
		{ BackgroundTransparency = 1 }):Play()
	Debris:AddItem(g, 0.6)
end

-- The room tinted dark and red for a moment (the roar's pulse, the dive's
-- slowed time).
local function tint(name: string, props: { [string]: any }, hold: number, fadeIn: number?, fadeOut: number?)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = name
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(fadeIn or 0.12), props):Play()
	task.delay(hold, function()
		TweenService:Create(cc, TweenInfo.new(fadeOut or 0.4),
			{ Brightness = 0, Saturation = 0, Contrast = 0, TintColor = Color3.new(1, 1, 1) }):Play()
		Debris:AddItem(cc, (fadeOut or 0.4) + 0.05)
	end)
end

-- A red streak burning along the floor from a to b.
local function groundStreak(a: Vector3, b: Vector3, width: number, life: number)
	local ga, gb = Vector3.new(a.X, FireFX.GroundY(a) + 0.1, a.Z), Vector3.new(b.X, FireFX.GroundY(b) + 0.1, b.Z)
	local len = (gb - ga).Magnitude
	if len < 0.2 then return end
	for _, layer in ipairs({ { w = width, c = CRIMSON, tr = 0.2 }, { w = width * 0.35, c = HOT, tr = 0 } }) do
		local s = ClassFX.Neon({ Size = Vector3.new(layer.w, 0.06, len), CFrame = CFrame.lookAt((ga + gb) / 2, gb),
			Color = layer.c, Transparency = layer.tr })
		TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1, Size = Vector3.new(0.05, 0.06, len) }):Play()
		Debris:AddItem(s, life + 0.05)
	end
end

-- ── New poses ───────────────────────────────────────────────────────────────
-- A random tremor (the Unchained build-up: shoulders shaking).
local function TREMBLE(amp: number)
	return function()
		local j = function() return (math.random() - 0.5) * amp end
		return { W = { j(), j(), j() }, RS = { j(), 0, j() }, LS = { j(), 0, j() }, N = { j(), j(), 0 } }
	end
end

-- Rupture: sink low gripping the blade, spring up with it raised, hang with
-- it overhead, smash it down into a deep crouch.
local function rupturePose(char: Model)
	CastPoses.play(char, {
		{ dur = RUPTURE.crouch, pose = { Root = { 0, 0, 0, 0, -1.1, 0.2 }, W = { -22, 0, 0 }, RS = { 40, 0, 0 }, LS = { 45, 0, 0 },
			RH = { 55, 0, 10 }, LH = { 50, 0, -10 }, N = { 15, 0, 0 } } },
		{ dur = RUPTURE.rise, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0 }, W = { 15, 0, 0 }, RS = { 165, 0, 0 },
			LS = { 160, 0, 0 }, RH = { -35, 0, 6 }, LH = { 20, 0, -6 }, N = { -15, 0, 0 } } },
		{ dur = RUPTURE.hang, pose = { Root = { 0, 0, 0 }, W = { 25, 0, 0 }, RS = { 190, 0, 0 }, LS = { 185, 0, 0 },
			RH = { -50, 0, 8 }, LH = { -20, 0, -8 }, N = { -25, 0, 0 } } },
		{ dur = RUPTURE.fall, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -1.3, -0.4 }, W = { -45, 0, 0 },
			RS = { 25, 0, 0 }, LS = { 25, 0, 0 }, RH = { 45, 0, 14 }, LH = { -40, 0, -14 }, N = { 25, 0, 0 } } },
		{ dur = 0.3, pose = { Root = { 0, 0, 0, 0, -1.2, -0.4 }, W = { -40, 0, 0 }, RS = { 20, 0, 0 }, LS = { 20, 0, 0 },
			RH = { 40, 0, 14 }, LH = { -35, 0, -14 } } },
	}, 0.35)
end

-- Bloodstorm's lean: bent forward, the blade dragged low behind.
local function stormLeanPose(char: Model, t: number)
	CastPoses.play(char, {
		{ dur = t, pose = { Root = { 0, 0, 0, 0, -0.8, 0 }, W = { -35, -20, 0 }, RS = { -25, -20, 30 }, LS = { -10, -40, 0 },
			RH = { 40, 0, 10 }, LH = { -30, 0, -10 }, N = { 25, 15, 0 } } },
	}, 0.1)
end

-- A Bloodstorm swing, alternately from either side: the greatsword heaved
-- high and far round, hacked across and down into a deep crouch with the
-- whole body behind it, then held there a beat as it bites (the hit-stop).
local function stormSwingPose(char: Model, i: number, dur: number, freeze: number)
	local s = if i % 2 == 1 then 1 else -1
	local hack = { Root = { 0, 0, 0, 0, -1.1, -0.45 }, W = { -28, -s * 60, 0 }, RS = { 30, -s * 70, 0 }, LS = { 35, -s * 50, 0 },
		RH = { 38, 0, 10 }, LH = { -36, 0, -10 }, N = { 15, s * 15, 0 } }
	CastPoses.play(char, {
		{ dur = dur * 0.62, style = Enum.EasingStyle.Sine, pose = { Root = { 0, 0, 0, 0, -0.5, 0.25 }, W = { 12, s * 70, 0 },
			RS = { 140, s * 75, 0 }, LS = { 130, s * 90, 0 }, RH = { -15, 0, 8 }, LH = { 18, 0, -8 }, N = { 0, -s * 20, 0 } } },
		{ dur = dur * 0.38, style = Enum.EasingStyle.Quart, pose = hack },
		{ dur = freeze, pose = hack },
	}, 0.2)
end

-- Crimson Charge: down low and leaning in, the greatsword dragged behind;
-- then driving forward.
local function chargePose(char: Model)
	CastPoses.play(char, {
		{ dur = CHARGE.windup, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.6, 0 }, W = { -30, 0, 0 },
			RS = { -50, 0, 35 }, LS = { -20, 0, -25 }, RH = { 35, 0, 8 }, LH = { -35, 0, -8 }, N = { 30, 0, 0 } } },
		{ dur = CHARGE.run, pose = { Root = { 0, 0, 0, 0, -0.4, 0 }, W = { -45, 0, 0 },
			RS = { -70, 0, 40 }, LS = { -30, 0, -30 }, RH = { 45, 0, 6 }, LH = { -40, 0, -6 }, N = { 40, 0, 0 } } },
	}, 0.25)
end

-- ── The beast's poses ───────────────────────────────────────────────────────
-- The awakening: he grips the sword and freezes; trembling, he doubles over
-- as the body distorts; then he throws his head back and roars.
local function awakenPose(char: Model)
	char:SetAttribute("BR_OneHand", true)
	CastPoses.play(char, {
		{ dur = BEAST.freeze, pose = { Root = { 0, 0, 0, 0, -0.2, 0 }, W = { -8, 0, 0 }, RS = { 40, 0, 10 }, LS = { 40, 0, -10 }, N = { -10, 0, 0 } },
			wobble = TREMBLE(2) },
		{ dur = BEAST.mutate * 0.6, pose = { Root = { 0, 0, 0, 0, -0.9, 0 }, W = { -35, 0, 0 }, RS = { -20, 0, 40 }, LS = { -20, 0, -40 },
			RH = { 30, 0, 10 }, LH = { -30, 0, -10 }, N = { 25, 0, 0 } }, wobble = TREMBLE(9) },
		{ dur = BEAST.mutate * 0.4, pose = { Root = { 0, 0, 0, 0, -1.0, 0 }, W = { -50, 0, 0 }, RS = { -40, 0, 60 }, LS = { -40, 0, -60 },
			RH = { 40, 0, 10 }, LH = { -40, 0, -10 }, N = { 35, 0, 0 } }, wobble = TREMBLE(14) },
		{ dur = BEAST.roar, style = Enum.EasingStyle.Back, pose = { Root = { 0, 0, 0, 0, -0.3, 0 }, W = { 25, 0, 0 }, RS = { 60, 0, 95 },
			LS = { 60, 0, -95 }, RH = { 10, 0, 14 }, LH = { -10, 0, -14 }, N = { -50, 0, 0 } }, wobble = TREMBLE(5) },
	}, 0.4)
	task.delay(BEAST.total + 0.5, function() char:SetAttribute("BR_OneHand", nil) end)
end

-- The claws: a rake right to left, one back left to right, one high to low,
-- then the maul: both claws raised overhead and brought down with the whole
-- body behind them.
local CLAW_SWING = {
	[1] = { wind = { W = { -10, 35, 0 }, RS = { 70, 0, 110 }, LS = { 20, 0, -15 } },
		hit = { W = { -20, -30, 0 }, RS = { 85, -60, 20 }, LS = { 15, 0, -20 } } },
	[2] = { wind = { W = { -10, -35, 0 }, LS = { 70, 0, -110 }, RS = { 20, 0, 15 } },
		hit = { W = { -20, 30, 0 }, LS = { 85, 60, -20 }, RS = { 15, 0, 20 } } },
	[3] = { wind = { W = { -5, 25, 0 }, RS = { 150, 0, 40 }, LS = { 60, 0, -40 } },
		hit = { W = { -30, -20, 0 }, RS = { 40, -40, 10 }, LS = { 90, 20, -30 } } },
	[4] = { wind = { Root = { 0, 0, 0, 0, 0.2, 0 }, W = { 18, 0, 0 }, RS = { 175, 0, 25 }, LS = { 175, 0, -25 }, N = { -20, 0, 0 } },
		hit = { Root = { 0, 0, 0, 0, -1.0, 0 }, W = { -55, 0, 0 }, RS = { 40, 0, 15 }, LS = { 40, 0, -15 }, RH = { 45, 0, 8 },
			LH = { -35, 0, -8 }, N = { 30, 0, 0 } } },
}

local function clawPose(char: Model, step: number)
	local c = CLAW_SWING[step] or CLAW_SWING[1]
	local heavy = step == 4
	CastPoses.play(char, {
		{ dur = if heavy then 0.14 else 0.07, style = Enum.EasingStyle.Quart, pose = c.wind },
		{ dur = if heavy then 0.1 else 0.08, style = Enum.EasingStyle.Quart, pose = c.hit },
		{ dur = if heavy then 0.16 else 0.08, pose = c.hit },
	}, 0.2)
end

-- Down on all fours: the body flat and low, claws on the floor, head up.
local ALL_FOURS = { Root = { 0, 0, 0, 0, -1.3, 0 }, W = { -75, 0, 0 }, N = { 55, 0, 0 }, RS = { 80, 0, 12 }, LS = { 80, 0, -12 },
	RH = { 55, 0, 6 }, LH = { 55, 0, -6 } }

-- Beast Charge: drop to all fours and gallop (a bounding wobble).
local function allFoursPose(char: Model, dur: number)
	CastPoses.play(char, {
		{ dur = 0.12, style = Enum.EasingStyle.Quart, pose = ALL_FOURS },
		{ dur = math.max(dur - 0.12, 0.05), pose = ALL_FOURS, wobble = function(t: number)
			local s = math.sin(t * 22)
			return { W = { s * 8, 0, 0 }, RS = { s * 35, 0, 0 }, LS = { -s * 35, 0, 0 }, RH = { -s * 30, 0, 0 }, LH = { s * 30, 0, 0 } }
		end },
	}, 0.25)
end

-- Beast Slam: crouched on all fours, then stretched out as he launches, a
-- tuck at the top, and down on all fours in the crash.
local function beastSlamPose(char: Model)
	CastPoses.play(char, {
		{ dur = SLAM.crouch, pose = ALL_FOURS },
		{ dur = SLAM.rise, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0 }, W = { 15, 0, 0 }, RS = { 170, 0, 20 },
			LS = { 170, 0, -20 }, RH = { -30, 0, 6 }, LH = { -30, 0, -6 }, N = { -20, 0, 0 } } },
		{ dur = SLAM.hang, pose = { Root = { 0, 0, 0 }, W = { -25, 0, 0 }, RS = { 120, 0, 30 }, LS = { 120, 0, -30 },
			RH = { 60, 0, 6 }, LH = { 60, 0, -6 }, N = { 20, 0, 0 } } },
		{ dur = SLAM.fall, style = Enum.EasingStyle.Quart, pose = ALL_FOURS },
		{ dur = 0.35, pose = ALL_FOURS },
	}, 0.35)
end

-- Carnage: three claws (across, back, a rake down), timed to land with the
-- server's CARNAGE.
local CARNAGE_SWING = {
	{ wind = { W = { -10, 40, 0 }, RS = { 90, 0, 100 }, LS = { 30, 0, -20 } },
		hit = { W = { -20, -40, 0 }, RS = { 90, -80, 0 }, LS = { 20, 0, -20 } } },
	{ wind = { W = { -10, -40, 0 }, LS = { 90, 0, -100 }, RS = { 30, 0, 20 } },
		hit = { W = { -20, 40, 0 }, LS = { 90, 80, 0 }, RS = { 20, 0, 20 } } },
	{ wind = { Root = { 0, 0, 0, 0, 0.2, 0 }, W = { 15, 25, 0 }, RS = { 170, 0, 60 }, LS = { 150, 0, -30 }, N = { -15, 0, 0 } },
		hit = { Root = { 0, 0, 0, 0, -1.0, 0 }, W = { -50, -25, 0 }, RS = { 30, -30, 0 }, LS = { 40, 20, 0 }, RH = { 45, 0, 8 },
			LH = { -35, 0, -8 }, N = { 25, 0, 0 } } },
}

local function carnagePose(char: Model)
	local stages = {}
	local t = 0
	for i, at in ipairs(CARNAGE) do
		local hitDur = if i == 3 then 0.14 else 0.1
		table.insert(stages, { dur = math.max(at - t - hitDur, 0.05), style = Enum.EasingStyle.Quart, pose = CARNAGE_SWING[i].wind })
		table.insert(stages, { dur = hitDur, style = Enum.EasingStyle.Quart, pose = CARNAGE_SWING[i].hit })
		t = at
	end
	table.insert(stages, { dur = 0.25, pose = CARNAGE_SWING[3].hit })
	CastPoses.play(char, stages, 0.3)
end

-- The grab: the victim hoisted overhead in both claws; the throw: hurled
-- forward and down.
local function grabPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.15, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.4, 0 }, W = { 10, 0, 0 }, RS = { 170, 0, 20 },
			LS = { 170, 0, -20 }, N = { -25, 0, 0 } } },
		{ dur = BCHARGE.grab - 0.15, pose = { Root = { 0, 0, 0, 0, -0.3, 0 }, W = { 15, 0, 0 }, RS = { 175, 0, 15 }, LS = { 175, 0, -15 },
			N = { -30, 0, 0 } }, wobble = TREMBLE(3) },
	}, 0.2)
end

local function throwPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.12, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.7, 0 }, W = { -45, 0, 0 }, RS = { 60, 0, 10 },
			LS = { 60, 0, -10 }, RH = { 35, 0, 8 }, LH = { -30, 0, -8 }, N = { 20, 0, 0 } } },
		{ dur = BCHARGE.throw, pose = { Root = { 0, 0, 0, 0, -0.7, 0 }, W = { -40, 0, 0 }, RS = { 50, 0, 10 }, LS = { 50, 0, -10 },
			RH = { 35, 0, 8 }, LH = { -30, 0, -8 } } },
	}, 0.3)
end

-- The change ends: down on one knee as the body shrinks back.
local function revertPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.25, style = Enum.EasingStyle.Quart, pose = CastPoses.kneelOnOneKnee(25) },
		{ dur = BEAST_REVERT - 0.25, pose = CastPoses.kneelOnOneKnee(15), wobble = TREMBLE(3) },
	}, 0.4)
end

-- ── The beast's body (every Berserker in Beast Form, every client) ──────────
-- Out of his attacks the beast never stands like a man: hunched forward,
-- head thrust out, arms hanging long; running, he leans right into it and
-- bounds, now and then a claw dropping to the ground mid-stride. Layered on
-- the walk / idle animation (attack poses take over while they play).
local beastMotors: { [Model]: any } = {}
local beastWeight: { [Model]: number } = {}

local function beastPosture(speed: number, t: number, phase: number): { [string]: { number } }
	local bob = math.sin(t * 9 + phase) * 4 * speed
	-- (mid-sprint, now and then, the right claw drops toward the ground)
	local touch = if speed > 0.7 then math.max(0, math.sin(t * 2.3 + phase)) ^ 6 else 0
	return {
		Root = { 0, 0, 0, 0, -0.35 - 0.25 * speed, 0 },
		W = { -22 - 20 * speed + bob - 12 * touch, 0, 0 },
		N = { 18 + 10 * speed, 0, 0 },
		RS = { 25 + 45 * touch, 0, 12 },
		LS = { 25, 0, -12 },
	}
end

local function beastStep(dt: number)
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not char then continue end
		local on = beastLeft(p) > 0 and char:GetAttribute("Tumbling") ~= true
		local w = math.clamp((beastWeight[char] or 0) + (if on then dt else -dt) * 4, 0, 1)
		beastWeight[char] = if w > 0 then w else nil
		if w <= 0 or CastPoses.isPlaying(char) then continue end
		local motors = beastMotors[char]
		if not motors then
			motors = CastPoses.resolveMotors(char)
			beastMotors[char] = motors
		end
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local v = if root then root.AssemblyLinearVelocity else Vector3.zero
		local speed = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / 22, 0, 1)
		local combined: { [Motor6D]: CFrame } = {}
		for key, val in pairs(beastPosture(speed, now, (p.UserId % 7) * 0.9)) do
			local m = motors[key]
			if m and m.motor.Parent then
				local cf = CFrame.identity:Lerp(CastPoses.poseCF(val), w)
				combined[m.motor] = (combined[m.motor] or CFrame.identity) * (m.basis:Inverse() * cf * m.basis)
			end
		end
		for motor, cf in pairs(combined) do motor.Transform = motor.Transform * cf end
	end
	for char in pairs(beastMotors) do
		if not char.Parent or not beastWeight[char] then beastMotors[char] = nil end
	end
end

-- The beast lands heavy: dust thrown out, the floor cracking, a thud.
local function watchLandings()
	local function hook(p: Player, char: Model)
		local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
		if not hum then return end
		hum.StateChanged:Connect(function(_, new)
			if new ~= Enum.HumanoidStateType.Landed or beastLeft(p) <= 0 then return end
			local root = rootOf(char)
			if not root then return end
			local g = Vector3.new(root.Position.X, FireFX.GroundY(root.Position), root.Position.Z)
			smoke(g + Vector3.new(0, 0.5, 0), 6, 2.4)
			fling(g + Vector3.new(0, 0.3, 0), 5, 12, 8, true)
			cracks(g, 3, 5, 0.9)
			if p == player then deps.shake(0.45, 0.15) end
		end)
	end
	local function watch(p: Player)
		p.CharacterAdded:Connect(function(c) hook(p, c) end)
		if p.Character then task.spawn(hook, p, p.Character) end
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
end

-- ── The Unchained look (every Berserker, every client) ──────────────────────
-- Unchained: an outline and a red aura flowing off him, black smoke off the
-- shoulders, eyes and armour cracks blazing, red lightning on the arms and
-- blade, glowing fractures under his feet, a persistent blade afterimage.
-- Empowered (the charged next skill): the blade's edge smoulders.
type Look = {
	char: Model,
	hl: Highlight,
	aura: ParticleEmitter,
	energy: ParticleEmitter,
	smokes: { ParticleEmitter },
	edge: ParticleEmitter?,
	eyeLight: PointLight?,
	glows: { [BasePart]: Color3 },
	level: number,
	nextBolt: number,
	nextStep: number,
	stepSide: number,
}
local looks: { [Player]: Look } = {}

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function buildLook(char: Model): Look?
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	if not (torso and torso:IsA("BasePart")) then return nil end
	local hl = Instance.new("Highlight")
	hl.Name = "UnchainedAura"
	hl.FillColor = CRIMSON
	hl.OutlineColor = CRIMSON
	hl.FillTransparency = 1
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = char
	-- the aura: crimson flame flowing up off the whole body
	local aura = emitter(torso, { Name = "UnchainedFlow", Texture = "rbxasset://textures/particles/fire_main.dds", LightEmission = 1,
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, HOT), ColorSequenceKeypoint.new(0.35, CRIMSON), ColorSequenceKeypoint.new(1, BLOOD) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(0.7, 0.65), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.6), NumberSequenceKeypoint.new(1, 0.3) }),
		Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 8, 0),
		SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-90, 90), Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume })
	-- red energy leaking out of the armour
	local en = emitter(torso, { Name = "UnchainedEnergy", Texture = ClassFX.TEX_SPARK, LightEmission = 1,
		Color = ColorSequence.new(HOT, CRIMSON), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(3, 8), SpreadAngle = Vector2.new(180, 180),
		Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume })
	-- black smoke trailing off each shoulder
	local smokes = {}
	for _, sx in ipairs({ -1, 1 }) do
		local a = Instance.new("Attachment")
		a.Name = "UnchainedShoulder"
		a.Position = Vector3.new(sx * 1.1, 1.1, 0.2)
		a.Parent = torso
		table.insert(smokes, emitter(a, { Name = "UnchainedSmoke", Texture = TEX_SMOKE,
			Color = ColorSequence.new(Color3.fromRGB(40, 6, 10), Color3.fromRGB(8, 4, 5)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.8) }),
			Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(1, 2.5), Acceleration = Vector3.new(0, 3.5, 0),
			Drag = 1, SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top, RotSpeed = NumberRange.new(-40, 40) }))
	end
	-- (the armour's glowing parts: the visor slit, chest cracks, gauntlet rims)
	local glows = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Material == Enum.Material.Neon and (d.Name == "Visor" or d.Name == "Crack" or d.Name == "GauntletRim") then
			glows[d] = d.Color
		end
	end
	local head = char:FindFirstChild("Head")
	local eyeLight: PointLight? = nil
	if head then
		local l = Instance.new("PointLight")
		l.Name = "UnchainedEyes"
		l.Color = CRIMSON
		l.Range = 7
		l.Brightness = 0
		l.Shadows = false
		l.Parent = head
		eyeLight = l
	end
	-- the Empowered blade: a smoulder along its edge
	local edge: ParticleEmitter? = nil
	local tool = char:FindFirstChild("Ragebringer")
	local tip = tool and tool:FindFirstChild("RageTip", true)
	if tip and tip:IsA("Attachment") and tip.Parent then
		edge = emitter(tip.Parent, { Name = "EmpoweredEdge", Texture = ClassFX.TEX_SPARK, LightEmission = 1,
			Color = ColorSequence.new(HOT, CRIMSON), Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(0.5, 2), Acceleration = Vector3.new(0, 4, 0),
			SpreadAngle = Vector2.new(180, 180), Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume })
	end
	return { char = char, hl = hl, aura = aura, energy = en, smokes = smokes, edge = edge, eyeLight = eyeLight,
		glows = glows, level = -1, nextBolt = 0, nextStep = 0, stepSide = 1 }
end

local function dropLook(L: Look)
	L.hl:Destroy()
	L.aura:Destroy()
	L.energy:Destroy()
	for _, s in ipairs(L.smokes) do
		if s.Parent then s.Parent:Destroy() end
	end
	if L.edge then L.edge:Destroy() end
	if L.eyeLight then L.eyeLight:Destroy() end
	for part, c in pairs(L.glows) do
		if part.Parent then part.Color = c end
	end
	persistTrail[L.char] = nil
end

-- (forward: ensureTrail is defined with the helpers)
local function setPersistentTrail(char: Model, on: boolean)
	persistTrail[char] = if on then true else nil
	local t = ensureTrail(char)
	if t then
		t.Lifetime = if on then 0.55 else 0.28
		t.Enabled = on
	end
end

local function refreshLook(p: Player)
	local char = p.Character
	local want = char ~= nil and isBerserker(p) and p:GetAttribute("InLobby") == false
	local L = looks[p]
	if L and (not want or L.char ~= char or not L.hl.Parent) then
		dropLook(L)
		looks[p] = nil
		L = nil
	end
	if not want or not char then return end
	if not L then
		local built = buildLook(char)
		if not built then return end
		looks[p] = built
		L = built
	end
	local level = if beastLeft(p) > 0 then 2 elseif p:GetAttribute("BR_Empowered") == true then 1 else 0
	if level == L.level then return end
	L.level = level
	local on = level == 2
	L.hl.OutlineTransparency = if on then 0.1 else 1
	L.hl.FillTransparency = if on then 0.82 else 1
	L.aura.Rate = if on then 30 else 0
	L.energy.Rate = if on then 22 else 0
	for _, s in ipairs(L.smokes) do s.Rate = if on then 16 else 0 end
	if L.edge then L.edge.Rate = if level >= 1 then 26 else 0 end
	if L.eyeLight then L.eyeLight.Brightness = if on then 3 else 0 end
	if not on then
		for part, c in pairs(L.glows) do
			if part.Parent then part.Color = c end
		end
	end
	setPersistentTrail(char, on)
end

-- Every frame while Unchained: the blazing cracks pulse, red lightning arcs
-- round the arms and blade, and each step cracks the floor.
local function unchainedStep(now: number)
	for _, L in pairs(looks) do
		if L.level ~= 2 or not L.char.Parent then continue end
		local pulse = 0.5 + 0.5 * math.sin(now * 14)
		for part in pairs(L.glows) do
			if part.Parent then part.Color = CRIMSON:Lerp(HOT, pulse) end
		end
		if now >= L.nextBolt then
			L.nextBolt = now + 0.1 + math.random() * 0.12
			local arm = L.char:FindFirstChild(if math.random() < 0.5 then "Right Arm" else "Left Arm")
			local tool = L.char:FindFirstChild("Ragebringer")
			local tip = tool and tool:FindFirstChild("RageTip", true)
			if arm and arm:IsA("BasePart") then
				local from = arm.Position + Vector3.new((math.random() - 0.5) * 1.2, (math.random() - 0.5) * 1.6, (math.random() - 0.5) * 1.2)
				local to = if tip and tip:IsA("Attachment") and math.random() < 0.6
					then tip.WorldPosition:Lerp(from, math.random() * 0.5)
					else from + Vector3.new((math.random() - 0.5) * 3, (math.random() - 0.5) * 2.5, (math.random() - 0.5) * 3)
				bolt(from, to, 0.12, 0.1)
			end
		end
		local root = rootOf(L.char)
		if root and now >= L.nextStep then
			local v = root.AssemblyLinearVelocity
			if Vector3.new(v.X, 0, v.Z).Magnitude > 4 then
				L.nextStep = now + 0.3
				L.stepSide = -L.stepSide
				local side = root.CFrame.RightVector * 0.5 * L.stepSide
				local g = Vector3.new(root.Position.X, FireFX.GroundY(root.Position), root.Position.Z) + side
				cracks(g, 2.2, 4, 0.9)
				-- (the beast's tread: dust off every step, and you feel your own)
				smoke(g + Vector3.new(0, 0.4, 0), 2, 1.6)
				if L.char == player.Character then deps.shake(0.12, 0.08) end
			end
		end
	end
end

-- ── The Unchained gauge ─────────────────────────────────────────────────────
local hud: ScreenGui? = nil
local gaugeBack: Frame? = nil
local fill: Frame? = nil
local label: TextLabel? = nil
local unchainedFor = BEAST_TIME

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "BerserkerUnchained"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -132)
	back.Size = UDim2.fromOffset(300, 10)
	back.BackgroundColor3 = Color3.fromRGB(12, 6, 8)
	back.BorderSizePixel = 0
	back.Parent = g
	gaugeBack = back
	local s = Instance.new("UIStroke")
	s.Color = Color3.fromRGB(110, 14, 22)
	s.Thickness = 1.5
	s.Parent = back
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(0, 1)
	f.BackgroundColor3 = CRIMSON
	f.BorderSizePixel = 0
	f.Parent = back
	fill = f
	local l = Instance.new("TextLabel")
	l.AnchorPoint = Vector2.new(0.5, 1)
	l.Position = UDim2.new(0.5, 0, 0, -3)
	l.Size = UDim2.fromOffset(300, 18)
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.GothamBlack
	l.TextSize = 14
	l.TextColor3 = CRIMSON
	l.TextStrokeTransparency = 0.2
	l.Text = ""
	l.Parent = back
	label = l
end

-- The Rage meter (full: R awakens the beast), and as the beast its timer.
local function refreshHud()
	if not hud then return end
	local left = beastLeft(player)
	local rage = rageOf(player)
	local empowered = player:GetAttribute("BR_Empowered") == true
	hud.Enabled = isBerserker() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	if fill then
		fill.Size = UDim2.fromScale(if left > 0 then math.clamp(left / unchainedFor, 0, 1) else math.clamp(rage / RAGE_MAX, 0, 1), 1)
		fill.BackgroundColor3 = if left > 0 or rage >= RAGE_MAX then HOT else CRIMSON
	end
	if gaugeBack then gaugeBack.BackgroundTransparency = 0 end
	if label then
		label.Text = if left > 0 then "BEAST FORM"
			elseif rage >= RAGE_MAX then "RAGE FULL  ·  R: BEAST AWAKENING"
			elseif empowered then `RAGE {math.floor(rage)}  ·  NEXT SKILL EMPOWERED`
			else `RAGE {math.floor(rage)}`
	end
end


-- ── The two-handed hold (every Berserker, every client) ──────────────────────
-- Out of attacks, both hands stay on the greatsword's hilt: the blade held out
-- in front and up, the torso turned a little so the left hand reaches the
-- grip. Arms replace the walk / idle animation; the torso turn is added on top
-- (the hips turn back so the feet keep walking straight). Attack poses
-- (CastPoses) take over while they play; the hold eases back in after.
local HOLD_ARMS = { RS = { 40, -10, -50 }, LS = { 130, -50, 130 } }
local HOLD_TURN = { W = { 0, 15, 0 }, RH = { 0, -15, 0 }, LH = { 0, -15, 0 } }
local holdWeight: { [Model]: number } = {}

local function holdStep(dt: number)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		-- (thrown off a mount: the tumble poses the whole body)
		if not (char and isBerserker(p) and char:FindFirstChild("Ragebringer")) or (char and (char:GetAttribute("BR_OneHand") or char:GetAttribute("Tumbling"))) then
			if char then holdWeight[char] = nil end
			continue
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local playing = CastPoses.isPlaying(char)
		local w = holdWeight[char] or 0
		w = if playing then 0 else math.min(1, w + dt * 7)
		holdWeight[char] = w
		if w <= 0 then continue end
		local motors = CastPoses.resolveMotors(char)
		for key, v in pairs(HOLD_ARMS) do
			local m = motors[key]
			if m then m.motor.Transform = m.motor.Transform:Lerp(m.basis:Inverse() * CastPoses.poseCF(v) * m.basis, w) end
		end
		for key, v in pairs(HOLD_TURN) do
			local m = motors[key]
			if m then
				local add = m.basis:Inverse() * CastPoses.poseCF({ v[1] * w, v[2] * w, v[3] * w }) * m.basis
				m.motor.Transform = m.motor.Transform * add
			end
		end
	end
	for char in pairs(holdWeight) do
		if not char.Parent then holdWeight[char] = nil end
	end
end

-- ── Both hands on the hilt, always ──────────────────────────────────────────
-- Runs after every pose (idle hold, walk, every attack): wherever the pose
-- put the right hand, the grip is drawn to the nearest point BOTH arms can
-- reach (R6 arms are short, so that's in front of / above the chest's
-- middle), the right arm re-aims there, and the left arm reaches for the
-- hilt just behind it (toward the pommel). So every swing, slam and spin is
-- two-handed.
local REACH_SLACK = 0.97
local LEFT_BEHIND = 0.55 -- studs from the right hand toward the pommel
local bladeAxis: { [Tool]: Vector3 } = {}

-- A point pulled inside the sphere (center c, radius r).
local function inside(p: Vector3, c: Vector3, r: number): Vector3
	local d = p - c
	return if d.Magnitude > r then c + d.Unit * r else p
end

-- The smallest rotation turning direction a into b.
local function turnBetween(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-5 then return CFrame.identity end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

-- Arm (Part1) CFrame in torso space from its motor.
local function armIn(m: Motor6D): CFrame
	return m.C0 * m.Transform * m.C1:Inverse()
end

-- Re-aim an arm (torso-space CFrame `a`) about its shoulder pivot so the point
-- `handLocal` (arm space) lands as close as it can to `target`.
local function aim(m: Motor6D, a: CFrame, handLocal: Vector3, target: Vector3): CFrame
	local pivot = m.C0.Position
	local from = (a * handLocal - pivot)
	local to = target - pivot
	if from.Magnitude < 1e-3 or to.Magnitude < 1e-3 then return a end
	local r = turnBetween(from.Unit, to.Unit)
	return CFrame.new(pivot) * r * CFrame.new(-pivot) * a
end

local function bladeOf(tool: Tool, handle: BasePart): Vector3
	local cached = bladeAxis[tool]
	if cached then return cached end
	local a0, a1 = tool:FindFirstChild("RageBase", true), tool:FindFirstChild("RageTip", true)
	local v = if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment")
		then handle.CFrame:VectorToObjectSpace(a1.WorldPosition - a0.WorldPosition)
		else Vector3.new(0, 0, -1)
	v = if v.Magnitude > 1e-3 then v.Unit else Vector3.new(0, 0, -1)
	bladeAxis[tool] = v
	return v
end

local function twoHandStep()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not (char and isBerserker(p)) or char:GetAttribute("BR_OneHand") or char:GetAttribute("Tumbling") then continue end
		local tool = char:FindFirstChild("Ragebringer")
		local torso = char:FindFirstChild("Torso")
		local rArm, lArm = char:FindFirstChild("Right Arm"), char:FindFirstChild("Left Arm")
		if not (tool and tool:IsA("Tool") and torso and rArm and lArm) then continue end
		local rs, ls = torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder")
		local grip = rArm:FindFirstChild("RightGrip")
		local handle = tool:FindFirstChild("Handle")
		-- (RightGrip is a Weld, not a Motor6D)
		if not (rs and ls and grip and handle and rs:IsA("Motor6D") and ls:IsA("Motor6D") and grip:IsA("JointInstance") and handle:IsA("BasePart")) then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end

		local handR = grip.C0.Position                 -- where the right hand holds
		local handL = Vector3.new(0, -1, 0)            -- the left hand's palm
		local reachR = (handR - rs.C1.Position).Magnitude * REACH_SLACK
		local reachL = (handL - ls.C1.Position).Magnitude * REACH_SLACK
		local pR, pL = rs.C0.Position, ls.C0.Position

		-- The grip: where the pose put the right hand, pulled into reach of both.
		local aR = armIn(rs)
		local g = aR * handR
		for _ = 1, 4 do
			g = inside(g, pL, reachL)
			g = inside(g, pR, reachR)
		end
		aR = aim(rs, aR, handR, g)
		rs.Transform = rs.C0:Inverse() * aR * rs.C1

		-- The left hand on the hilt, just behind the right toward the pommel.
		local handleCF = aR * grip.C0 * grip.C1:Inverse()
		local blade = handleCF:VectorToWorldSpace(bladeOf(tool, handle))
		local gl = inside(g - blade * LEFT_BEHIND, pL, reachL)
		local aL = aim(ls, armIn(ls), handL, gl)
		ls.Transform = ls.C0:Inverse() * aL * ls.C1
	end
end

-- ── The ground, the eruption, the combo ─────────────────────────────────────
-- The floor under a point (ground effects sit on it, not at waist height).
local function ground(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local hit = workspace:Raycast(pos + Vector3.new(0, 2, 0), Vector3.new(0, -14, 0), params)
	return if hit then hit.Position else pos - Vector3.new(0, 3, 0)
end

-- The ground eruption shared by the Bloodquake, the smash and the final slam:
-- a red flash, tall shards leaning outward, black rock flying, jagged cracks,
-- a shockwave, dark smoke and red sparks.
local function eruption(at: Vector3, radius: number, size: number, char: Model?)
	local g = ground(at)
	groundFlash(g, radius)
	shards(g, radius * 0.85, math.floor(8 + 10 * size), 2 + 2.5 * size, 4 + 5 * size, 0.7 + 0.25 * size)
	fling(g + Vector3.new(0, 0.5, 0), math.floor(6 + 12 * size), 24, 26, true)
	fling(g + Vector3.new(0, 1, 0), math.floor(8 + 10 * size), 30, 18)
	cracks(g, radius * 1.05, math.floor(6 + 6 * size), 1 + 0.4 * size)
	shockwave(g, radius, char)
	smoke(g + Vector3.new(0, 1, 0), math.floor(6 + 10 * size), 2.5 + size)
	sparks(g + Vector3.new(0, 1, 0), math.floor(16 + 20 * size), 20 + 12 * size)
end

-- ── The greatsword chain ────────────────────────────────────────────────────
local function comboVFX(char: Model, step: number, dir: Vector3)
	local root = rootOf(char)
	if not root then return end
	local look = CFrame.lookAt(root.Position, root.Position + dir)
	trail(char, 0.4)
	if step == 1 then
		-- a diagonal crimson crescent, high right to low left
		task.delay(0.13, function()
			slashRing(look * CFrame.new(0, 0.4, 0) * CFrame.Angles(0, 0, math.rad(-32)), 7, 160, 1)
		end)
	elseif step == 2 then
		task.delay(0.11, function()
			slashRing(look * CFrame.new(0, 0.3, 0) * CFrame.Angles(0, 0, math.rad(24)), 7, 160, -1)
		end)
	end
end

-- ── The beast's claws ───────────────────────────────────────────────────────
-- Every rake is three parallel red gashes torn through the air (the middle
-- one white-hot); the maul's picture comes with its hit (onMaul).
local function clawMarks(cf: CFrame, radius: number, span: number, sweep: number, heavy: boolean?)
	for k = -1, 1 do
		task.delay((k + 1) * 0.015, arc, cf * CFrame.new(0, k * (if heavy then 0.8 else 0.55), 0), radius * (1 - math.abs(k) * 0.06), span,
			if k == 0 then HOT else CRIMSON, if heavy then 0.55 else 0.32, if heavy then 0.38 else 0.28, sweep, 0.08)
	end
end

local function clawVFX(char: Model, step: number, dir: Vector3)
	local root = rootOf(char)
	if not root then return end
	local look = CFrame.lookAt(root.Position, root.Position + dir)
	if step == 1 then
		task.delay(0.08, clawMarks, look * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(-15)), 9, 150, 1)
	elseif step == 2 then
		task.delay(0.08, clawMarks, look * CFrame.new(0, 0.5, 0) * CFrame.Angles(0, 0, math.rad(15)), 9, 150, -1)
	elseif step == 3 then
		task.delay(0.08, clawMarks, look * CFrame.new(0, 0.8, 0) * CFrame.Angles(0, 0, math.rad(-60)), 9, 140, 1)
	end
end

function BerserkerController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	if beastLeft(player) > 0 then
		-- The beast: claw, claw, claw, maul.
		if now - lastSwing < CLAW_INTERVAL / speed then return true end
		localStep = if now - lastSwing > CLAW_RESET or localStep > 4 then 1 else (localStep % 4) + 1
		lastSwing = now
		local dir = flatDir(deps.getAim(root), root.CFrame.LookVector)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
		clawPose(char, localStep)
		clawVFX(char, localStep, dir)
		ClassFX.Sound("whoosh", root, 0.8, if localStep == 4 then 0.55 else 0.75)
		Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
		return true
	end
	if now - lastSwing < SWING_INTERVAL / speed then return true end
	localStep = if now - lastSwing > COMBO_RESET or localStep > 3 then 1 else (localStep % 3) + 1
	lastSwing = now
	local dir = flatDir(deps.getAim(root), root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	swingPose(char, localStep)
	comboVFX(char, localStep, dir)
	ClassFX.Sound("whoosh", root, 0.7, if localStep == 3 then 0.7 else 0.85)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Moving the body (your own character: its movement replicates) ──────────
-- Held by movers along a scripted path (an anchored root wouldn't replicate).
type Mover = { set: (Vector3) -> (), face: (Vector3) -> (), stop: (snap: boolean?) -> (), stand: number, alive: () -> boolean }

local function holdBody(char: Model, root: BasePart): Mover?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local stand = SafeMove.StandHeight(root)
	local att = Instance.new("Attachment")
	att.Name = "BerserkerMove"
	att.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.RigidityEnabled = true
	ap.Position = root.Position
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root
	hum.AutoRotate = false
	hum.PlatformStand = true
	local stopped = false
	return {
		stand = stand,
		set = function(p: Vector3) if not stopped then ap.Position = p end end,
		face = function(d: Vector3)
			local f = Vector3.new(d.X, 0, d.Z)
			if f.Magnitude > 0.05 and not stopped then ao.CFrame = CFrame.lookAt(Vector3.zero, f.Unit) end
		end,
		alive = function() return not stopped and root.Parent ~= nil and hum.Health > 0 end,
		stop = function(snap: boolean?)
			if stopped then return end
			stopped = true
			ap:Destroy()
			ao:Destroy()
			att:Destroy()
			if hum.Parent then
				hum.PlatformStand = false
				hum.AutoRotate = true
			end
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.zero
				if snap then SafeMove.SnapToFloor(root, stand) end
			end
		end,
	}
end

-- Run `step(t)` every frame for `duration` seconds, then `done()`.
local function timeline(duration: number, step: (number) -> (), done: () -> ())
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local ok, err = pcall(step, math.min(t, duration))
		if not ok then warn("[BerserkerController] move", err) end
		if t >= duration or not ok then
			conn:Disconnect()
			done()
		end
	end)
end

local function easeOut(a: number): number return 1 - (1 - a) ^ 2 end
local function easeIn(a: number): number return a * a end

-- A standing spot over the floor at `p`.
local function standAt(p: Vector3, stand: number): Vector3
	return Vector3.new(p.X, FireFX.GroundY(p) + stand, p.Z)
end

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- ── E: Rupture (caster) ─────────────────────────────────────────────────────
local ruptureLanding: Vector3? = nil -- (where our own leap lands: the crash is drawn there)

local function ruptureLeap(char: Model, root: BasePart, dir: Vector3, cursor: Vector3?): Vector3?
	local mv = holdBody(char, root)
	if not mv then return end
	local m = mv :: Mover
	local origin = root.Position
	-- to the cursor, no further than RUPTURE_RANGE (and not through walls)
	local want = 8
	if cursor then
		local d = Vector3.new(cursor.X - root.Position.X, 0, cursor.Z - root.Position.Z)
		want = math.min(d.Magnitude, RUPTURE_RANGE)
	end
	local dist = SafeMove.ClampDash(root, dir, want)
	local land = standAt(origin + dir * dist, m.stand)
	local apex = origin:Lerp(land, 0.55) + Vector3.new(0, RUPTURE_HEIGHT, 0)
	-- (a longer leap arcs higher)
	apex = Vector3.new(apex.X, math.max(origin.Y, land.Y) + RUPTURE_HEIGHT + dist * 0.18, apex.Z)
	local apex2 = origin:Lerp(land, 0.72) + Vector3.new(0, 0, 0)
	apex2 = Vector3.new(apex2.X, apex.Y + 0.6, apex2.Z)
	m.face(dir)
	local T = RUPTURE
	timeline(T.impact, function(t)
		if not m.alive() then return end
		if t < T.crouch then
			m.set(origin)
		elseif t < T.crouch + T.rise then
			m.set(origin:Lerp(apex, easeOut((t - T.crouch) / T.rise)))
		elseif t < T.crouch + T.rise + T.hang then
			m.set(apex:Lerp(apex2, (t - T.crouch - T.rise) / T.hang))
		else
			m.set(apex2:Lerp(land, easeIn((t - T.crouch - T.rise - T.hang) / T.fall)))
		end
	end, function()
		m.set(land)
		m.stop(true)
	end)
	ruptureLanding = land
	return land
end

-- ── Q: Crimson Charge (caster) ──────────────────────────────────────────────
-- A short step back as he leans in, then the run (short of walls), his feet
-- on the floor all the way.
local function chargeRun(char: Model, root: BasePart, dir: Vector3)
	local mv = holdBody(char, root)
	if not mv then return end
	local m = mv :: Mover
	local origin = root.Position
	local dist = SafeMove.ClampDash(root, dir, CHARGE_DIST)
	local stop = standAt(origin + dir * dist, m.stand)
	m.face(dir)
	timeline(CHARGE.windup + CHARGE.run, function(t)
		if not m.alive() then return end
		if t < CHARGE.windup then
			m.set(origin - dir * 0.6 * (t / CHARGE.windup))
		else
			m.set(standAt(origin:Lerp(stop, easeOut((t - CHARGE.windup) / CHARGE.run)), m.stand))
		end
	end, function()
		m.set(stop)
		m.stop(true)
	end)
end

-- ── F: Bloodstorm (caster) ──────────────────────────────────────────────────
-- Held to the spot from the lean to the last swing.
local stormMover: Mover? = nil
local stormToken = 0

-- ── The beast's moves (caster) ──────────────────────────────────────────────
local IsometricCamera: any = nil
pcall(function() IsometricCamera = require(script.Parent:WaitForChild("IsometricCamera")) end)

local slamLanding: Vector3? = nil -- (where our own Beast Slam lands: the crash is drawn there)

-- E · Beast Slam: crouched on all fours, an enormous leap at the cursor (not
-- through walls), a crash.
local function beastSlamLeap(char: Model, root: BasePart, dir: Vector3, cursor: Vector3?): Vector3?
	local mv = holdBody(char, root)
	if not mv then return nil end
	local m = mv :: Mover
	local origin = root.Position
	local want = 12
	if cursor then
		want = math.min(Vector3.new(cursor.X - origin.X, 0, cursor.Z - origin.Z).Magnitude, SLAM_RANGE)
	end
	local dist = SafeMove.ClampDash(root, dir, want)
	local land = standAt(origin + dir * dist, m.stand)
	local mid = origin:Lerp(land, 0.5)
	local apex = Vector3.new(mid.X, math.max(origin.Y, land.Y) + SLAM_HEIGHT, mid.Z)
	local apex2 = apex + (land - origin) * 0.12 + Vector3.new(0, 0.8, 0)
	m.face(dir)
	-- (the camera keeps the floor in view while he's up there)
	if IsometricCamera then pcall(IsometricCamera.SetFocusYLock, origin.Y + 7) end
	local T = SLAM
	timeline(T.impact, function(t)
		if not m.alive() then return end
		if t < T.crouch then
			m.set(origin)
		elseif t < T.crouch + T.rise then
			m.set(origin:Lerp(apex, easeOut((t - T.crouch) / T.rise)))
		elseif t < T.crouch + T.rise + T.hang then
			m.set(apex:Lerp(apex2, (t - T.crouch - T.rise) / T.hang))
		else
			m.set(apex2:Lerp(land, easeIn((t - T.crouch - T.rise - T.hang) / T.fall)))
		end
	end, function()
		m.set(land)
		m.stop(true)
		if IsometricCamera then pcall(IsometricCamera.SetFocusYLock, nil) end
	end)
	slamLanding = land
	return land
end

-- Q · Beast Charge: a gallop on all fours (short of walls), then held there
-- through the grab and the throw.
local function beastChargeRun(char: Model, root: BasePart, dir: Vector3)
	local mv = holdBody(char, root)
	if not mv then return end
	local m = mv :: Mover
	local origin = root.Position
	local dist = SafeMove.ClampDash(root, dir, BCHARGE_DIST)
	local stop = standAt(origin + dir * dist, m.stand)
	m.face(dir)
	timeline(BCHARGE.crouch + BCHARGE.run, function(t)
		if not m.alive() then return end
		if t < BCHARGE.crouch then
			m.set(origin)
		else
			m.set(standAt(origin:Lerp(stop, (t - BCHARGE.crouch) / BCHARGE.run), m.stand))
		end
	end, function()
		m.set(stop)
		task.delay(BCHARGE.grab + BCHARGE.throw, function() m.stop(true) end)
	end)
end

-- As the beast, the skills are the beast's: E Beast Slam, F Carnage, Q Beast
-- Charge (R does nothing: CanCast).
local function beastCast(skillIndex: number, char: Model, root: BasePart, dir: Vector3, cursor: Vector3?): Vector3?
	if skillIndex == 1 then
		busyUntil = os.clock() + SLAM.impact + 0.45
		beastSlamPose(char)
		local land = beastSlamLeap(char, root, dir, cursor)
		releaseAfter(char, SLAM.impact + 0.4)
		return land
	elseif skillIndex == 2 then
		busyUntil = os.clock() + CARNAGE[3] + 0.35
		carnagePose(char)
		local mv = holdBody(char, root)
		if mv then mv.face(dir) end
		task.delay(CARNAGE[3] + 0.3, function() if mv then mv.stop(true) end end)
		releaseAfter(char, CARNAGE[3] + 0.3)
	elseif skillIndex == 3 then
		local total = BCHARGE.crouch + BCHARGE.run + BCHARGE.grab + BCHARGE.throw
		busyUntil = os.clock() + total + 0.1
		allFoursPose(char, BCHARGE.crouch + BCHARGE.run)
		beastChargeRun(char, root, dir)
		releaseAfter(char, total)
	end
	return nil
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function BerserkerController.CanCast(skillIndex: number): boolean
	if os.clock() < busyUntil then return false end
	-- The awakening needs a full Rage meter (and not while already the beast).
	if skillIndex == 4 then return beastLeft(player) <= 0 and rageOf(player) >= RAGE_MAX end
	return true
end

function BerserkerController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, _config: any, cursor: Vector3?): Vector3?
	local dir = flatDir(aimDir, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	char:SetAttribute("AllowSkillMovement", false)
	if beastLeft(player) > 0 then
		return beastCast(skillIndex, char, root, dir, cursor)
	end
	if skillIndex == 1 then
		busyUntil = os.clock() + RUPTURE.impact + 0.3
		rupturePose(char)
		local land = ruptureLeap(char, root, dir, cursor)
		releaseAfter(char, RUPTURE.impact + 0.3)
		return land
	elseif skillIndex == 2 then
		-- (the real length comes with the swings; this is the fallback)
		busyUntil = os.clock() + 1.4
		stormLeanPose(char, 0.35)
		stormToken += 1
		local my = stormToken
		if stormMover then stormMover.stop(false) end
		stormMover = holdBody(char, root)
		task.delay(1.2, function()
			-- the server never answered: let go
			if stormToken == my and stormMover then
				stormMover.stop(true)
				stormMover = nil
				releaseAfter(char, 0)
			end
		end)
	elseif skillIndex == 3 then
		busyUntil = os.clock() + CHARGE.windup + CHARGE.run + 0.15
		chargePose(char)
		chargeRun(char, root, dir)
		releaseAfter(char, CHARGE.windup + CHARGE.run + 0.1)
	elseif skillIndex == 4 then
		-- The awakening: held to the spot through the change and the roar.
		busyUntil = os.clock() + BEAST.total + 0.1
		awakenPose(char)
		local mv = holdBody(char, root)
		task.delay(BEAST.total, function() if mv then mv.stop(true) end end)
		releaseAfter(char, BEAST.total + 0.05)
	end
	return nil
end

-- The gathering, seen close (the caster and everyone watching).
-- The red-moon shot: low behind him, looking up past the raised blade at a
-- vast red moon, the sky stained red.
function BerserkerController.PlayUltCutscene(char: Model, dir: Vector3)
	local root = rootOf(char)
	if not root then return end
	-- Close on him, low and in front, as the change takes him; pulled back
	-- for the roar. The world goes dark and red.
	UltimateCameraChoreography.PlayCloseUp(char, dir, BEAST.total, nil, nil, {
		startOffset = { 7.5, -1.5, 0.6 },
		endOffset = { 11, -2.5, 1.4 },
		focusHeight = 2.2,
		fovStart = 50,
		fovEnd = 62,
	})
	tint("BerserkerAwakening", { Brightness = -0.12, Saturation = 0.2, Contrast = 0.35, TintColor = Color3.fromRGB(255, 110, 110) },
		BEAST.total, 0.3, 0.5)
end

-- ── Server moments (BerserkerFX) ────────────────────────────────────────────
local function onCombo(msg: any)
	if msg.attacker == player then return end -- ours was predicted on click
	local char = charOf(msg.attacker)
	if not char then return end
	swingPose(char, msg.step)
	comboVFX(char, msg.step, msg.dir)
end

local function onSmash(msg: any)
	eruption(msg.pos, msg.radius * 0.7, 0.3, charOf(msg.attacker))
	ClassFX.Sound("rockHit", msg.pos, 0.8, 0.85)
	if msg.attacker == player then deps.shake(0.5, 0.15) end
end

-- E · Rupture: the crouch (red cracks under him), the leap (crimson
-- trails), the hang (debris torn up under him).
local function onRupture(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then rupturePose(char) end
	local T = msg.t
	local r = msg.radius :: number
	local origin = root.Position
	local dir = msg.dir :: Vector3
	trail(char, T.crouch + T.rise + T.hang + T.fall + 0.3)
	-- crouch: the floor splits red under his feet, rage gathers in the blade
	local g0 = Vector3.new(origin.X, FireFX.GroundY(origin), origin.Z)
	cracks(g0, 3.5, 7, 1.1)
	groundFlash(g0, 5)
	ClassFX.Sound("charge", root, 0.5, 1.4)
	-- the leap: a burst off the floor and red streaks rising with him
	task.delay(T.crouch, function()
		if not root.Parent then return end
		smoke(g0 + Vector3.new(0, 0.5, 0), 8, 2.2)
		shockwave(g0, 5, char)
		fling(g0 + Vector3.new(0, 0.3, 0), 6, 16, 10, true)
		for i = 1, 4 do
			local off = Vector3.new(math.cos(i * 1.6), 0, math.sin(i * 1.6)) * 0.9
			SwordFX.Streak(origin + off - Vector3.new(0, 2, 0), origin + off + Vector3.new(0, RUPTURE_HEIGHT, 0), 0.35, CRIMSON, 0.35, nil, CORE)
		end
		ClassFX.Sound("whoosh", root, 0.9, 0.6)
		if msg.attacker == player then deps.fovPunch(6, 0.25) end
	end)
	-- the hang: chunks of floor torn up where he'll land
	task.delay(T.crouch + T.rise * 0.6, function()
		if not root.Parent then return end
		local landG = (msg.land :: Vector3?) or origin + dir * 8
		landG = Vector3.new(landG.X, FireFX.GroundY(landG), landG.Z)
		local release = liftDebris(landG, r * 0.7, if msg.empowered then 14 else 9, 0.8, T.rise * 0.4 + T.hang + T.fall)
		task.delay(T.rise * 0.4 + T.hang + T.fall, release)
	end)
end

-- The crash: a crimson flash, the crater, the fracture racing outward, the
-- shockwave, and dust and embers settling (Empowered: shards too).
local function onRuptureImpact(msg: any)
	local pos = if msg.attacker == player and ruptureLanding then ruptureLanding else msg.pos :: Vector3
	local r = msg.radius :: number
	local g = Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
	crimsonImpact(g, r, msg.empowered)
	groundFlash(g, r)
	shockwave(g, r, charOf(msg.attacker))
	cracks(g, r * 1.25, if msg.empowered then 16 else 11, 1.8)
	linger(g, r * 0.6, 1.6)
	ClassFX.Sound("quake", pos, 0.9, 1.1, 1.5)
	ClassFX.Sound("boom", pos, 0.8, 0.95)
	if msg.attacker == player then
		deps.shake(1.3, 0.3)
		deps.fovPunch(8, 0.3)
	elseif near(pos, 60) then
		deps.shake(0.5, 0.25)
	end
end

-- Empowered Rupture's second burst: a wider ring of crimson spikes.
local function onRuptureEcho(msg: any)
	local pos = msg.pos :: Vector3
	local g = Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
	shards(g, msg.radius, 24, 2, 4, 1)
	shockwave(g, msg.radius, charOf(msg.attacker))
	flipbook("shock", g + Vector3.new(0, 0.25, 0), msg.radius * 2.6, 1, seq(Color3.fromRGB(255, 120, 120), CRIMSON), 3)
	ClassFX.Sound("boom", pos, 0.8, 0.8)
	if msg.attacker == player then deps.shake(0.8, 0.25) end
end

-- F · Bloodstorm: the lean (a red streak ignites under him), then each
-- swing on the spot: heave, hack, hold (the crescent itself comes with the
-- blow, stormHit).
local function onStorm(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local mine = msg.attacker == player
	local swings = msg.swings :: { any }
	local dir = msg.dir :: Vector3
	local freeze = (msg.freeze :: number?) or 0.1
	local start = root.Position
	if not mine then stormLeanPose(char, 0.35) end
	-- the drag: a streak igniting under him, sparks off the dragged blade
	groundStreak(start - dir * 3, start + dir * 1, 0.8, 0.6)
	sparks(start - dir * 2 - Vector3.new(0, 2, 0), 14, 10)
	ClassFX.Sound("charge", root, 0.5, 1.2)
	trail(char, (msg.finalAt :: number) + 0.3)

	for i, s in ipairs(swings) do
		local dur = (s.arrive :: number) - (s.leave :: number)
		task.delay(s.leave, function()
			if not char.Parent then return end
			stormSwingPose(char, i, dur, freeze)
			-- (a heavy blade: a low whoosh as it comes round)
			task.delay(dur * 0.55, function()
				if root.Parent then ClassFX.Sound("whoosh", root, 0.8, 0.6 + i * 0.04) end
			end)
		end)
	end

	if not mine then return end
	-- Our own body: held where it stands, facing the swing, till the cleave.
	stormToken += 1
	local m = stormMover
	stormMover = nil
	if not m then return end
	local mv = m :: Mover
	busyUntil = os.clock() + (msg.finalAt :: number) + 0.35
	releaseAfter(char, (msg.finalAt :: number) + 0.3)
	mv.set(standAt(start, mv.stand))
	mv.face(dir)
	task.delay((msg.finalAt :: number) + 0.2, function()
		mv.stop(true)
	end)
end

-- Each Bloodstorm blow: a huge crimson crescent out in front, the floor
-- cracking and rock thrown up where the blade lands, and (on a hit) a heavy
-- crunch and a jolt of the camera.
local function onStormHit(msg: any)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local r = msg.radius :: number
	local i = msg.i :: number
	local s = if i % 2 == 1 then 1 else -1
	-- (alternately flat and a little diagonal, like the swings)
	local tilt = CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then s * 14 else s * 5))
	slashRing(CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 0.3, 0) * tilt, r, 170, s, i >= 3)
	-- where the blade comes down: off to the side the swing ends on
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local land = ground(pos + dir * r * 0.5 - side * s * r * 0.3)
	cracks(land, r * 0.3, 5, 0.9)
	fling(land + Vector3.new(0, 0.5, 0), 6, 22, 16, true)
	smoke(land + Vector3.new(0, 1, 0), 6, 4)
	if msg.hit then
		sparks(pos + dir * r * 0.4, 26, 30)
		ClassFX.Sound("swordHit", pos, 1, 0.62 + i * 0.03)
		ClassFX.Sound("boom", pos, 0.45, 1.25)
	end
	if msg.attacker == player then
		deps.shake(if msg.hit then 0.75 else 0.4, 0.12)
		deps.fovPunch(if msg.hit then 3 else 1.5, 0.12)
	end
end

-- The spinning cleave that ends it: rings all the way round, a big
-- shockwave, enemies thrown out.
local function onStormFinal(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local r = msg.radius :: number
	cleavePose(char)
	local cf = CFrame.new(root.Position - Vector3.new(0, 0.6, 0)) * root.CFrame.Rotation
	slashRing(cf, r, 355, 1, true)
	rimChips(root.Position, r, if msg.empowered then 24 else 16)
	local g = Vector3.new(root.Position.X, FireFX.GroundY(root.Position), root.Position.Z)
	shockwave(g, r * 1.1, char)
	flipbook("shock", g + Vector3.new(0, 0.2, 0), r * 1.6, 1, seq(Color3.fromRGB(255, 120, 120), CRIMSON), 3)
	cracks(g, r * 0.45, 8, 1.2)
	fling(g + Vector3.new(0, 0.5, 0), 10, 30, 20, true)
	smoke(g + Vector3.new(0, 1, 0), 12, 4)
	sparks(root.Position, 30, 30)
	ClassFX.Sound("swordHit", root, 1, 0.7)
	ClassFX.Sound("whoosh", root, 1, 0.55)
	ClassFX.Sound("boom", root, 0.7, 0.9)
	if msg.attacker == player then
		deps.shake(1.1, 0.3)
		deps.fovPunch(6, 0.25)
	end
end

-- Q · Crimson Charge: the floor splits under his lean, then he tears down
-- the path in a red streak (afterimages, embers); the burst at the end.
local function onCharge(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then chargePose(char) end
	local T = msg.t
	local dir = msg.dir :: Vector3
	local from = msg.from :: Vector3
	local g0 = Vector3.new(from.X, FireFX.GroundY(from), from.Z)
	trail(char, T.windup + T.run + 0.3)
	cracks(g0, 3, 6, 1)
	groundFlash(g0, 4)
	ClassFX.Sound("charge", root, 0.7, 1.3)
	task.delay(T.windup, function()
		if not root.Parent then return end
		smoke(g0 + Vector3.new(0, 0.5, 0), 8, 2.4)
		fling(g0 + Vector3.new(0, 0.3, 0), 5, 14, 8, true)
		ClassFX.Sound("whoosh", root, 1, 0.7)
		if msg.attacker == player then deps.fovPunch(8, 0.3) end
		-- the streak and the afterimages, drawn where he actually goes
		local last = root.Position
		for k = 1, 5 do
			task.delay(T.run * k / 5, function()
				if not root.Parent then return end
				local now = root.Position
				groundStreak(last, now, 3, 0.7)
				SwordFX.Streak(last + Vector3.new(0, 0.5, 0), now + Vector3.new(0, 0.5, 0), 0.4, CRIMSON, 0.3, nil, HOT)
				sparks(now, 6, 10)
				last = now
			end)
		end
	end)
	-- (the look's EMPOWERED state arrives with the burst)
	task.delay(T.windup + T.run + 0.2, function()
		local p = msg.attacker :: Player
		if p and p.Parent then pcall(refreshLook, p) end
		refreshHud()
	end)
end

-- The burst at the end of the charge: a crimson shockwave, the floor
-- cracking, rocks thrown out.
local function onChargeEnd(msg: any)
	local pos = msg.pos :: Vector3
	local r = msg.radius :: number
	local g = Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
	shockwave(g, r, charOf(msg.attacker))
	blast(g, r * 0.5)
	cracks(g, r, 10, 1.6)
	fling(g + Vector3.new(0, 0.3, 0), 8, 22, 12, true)
	smoke(g + Vector3.new(0, 0.5, 0), 10, 3)
	ClassFX.Sound("boom", pos, 0.8, 0.8)
	if msg.attacker == player then
		deps.shake(0.9, 0.3)
		deps.fovPunch(6, 0.25)
	end
end

-- ── Beast Form: the server's moments ────────────────────────────────────────
-- M1 · the claws, seen by everyone else (ours were drawn on the click).
local function onClaw(msg: any)
	if msg.attacker == player then return end
	local char = charOf(msg.attacker)
	if not char then return end
	clawPose(char, msg.step)
	clawVFX(char, msg.step, msg.dir)
end

-- The maul lands: three gashes torn straight down, the floor bursting.
local function onMaul(msg: any)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local r = msg.radius :: number
	local char = charOf(msg.attacker)
	clawMarks(CFrame.lookAt(pos, pos + dir) * CFrame.new(0, 1.2, -1) * CFrame.Angles(0, 0, math.rad(-85)), r * 0.55, 120, 1, true)
	eruption(pos, r * 0.55, 0.6, char)
	ClassFX.Sound("rockHit", pos, 0.9, 0.7)
	if msg.attacker == player then
		deps.shake(0.7, 0.18)
		deps.fovPunch(4, 0.15)
	end
end

-- R · the awakening: he freezes, sparks crawling over him; the body
-- distorts (red lightning tearing out of it, the floor splitting, smoke
-- pouring off); the sword is cast aside; then the roar (onRoar).
local function onAwaken(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local mine = msg.attacker == player
	local T = msg.t
	if not mine then awakenPose(char) end
	local g = Vector3.new(root.Position.X, FireFX.GroundY(root.Position), root.Position.Z)
	ClassFX.Sound("charge", root, 1, 0.45)
	sparks(root.Position + Vector3.new(0, 1, 0), 18, 6)
	-- the distortion
	local n = 10
	for k = 1, n do
		task.delay(T.freeze + (k - 1) * (T.mutate / n), function()
			if not root.Parent then return end
			local a = math.random() * math.pi * 2
			local from = root.Position + Vector3.new(0, 1 + math.random(), 0)
			bolt(from, from + Vector3.new(math.cos(a) * (3 + k * 0.3), math.random() * 3 - 0.5, math.sin(a) * (3 + k * 0.3)), 0.16 + k * 0.01, 0.12)
			sparks(from, 6 + k, 8 + k)
			if k % 3 == 0 then
				cracks(g, 2 + k * 0.5, 5, 1.6)
				smoke(g + Vector3.new(0, 1, 0), 4, 2 + k * 0.2)
			end
			if mine then deps.shake(0.15 + k * 0.05, 0.12) end
		end)
	end
	if near(root.Position, 70) then
		tint("BerserkerChange", { Brightness = -0.1, Saturation = -0.3, Contrast = 0.3, TintColor = Color3.fromRGB(255, 150, 150) }, T.mutate, T.freeze, 0.2)
	end
	-- The sword, cast aside: flung away to stick in the floor beside him.
	task.delay(T.change - 0.05, function()
		local tool = char:FindFirstChild("Ragebringer")
		if not (tool and root.Parent) then return end
		local copy = Instance.new("Model")
		copy.Name = "CastAsideSword"
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 then
				local c = d:Clone()
				for _, j in ipairs(c:GetChildren()) do
					if j:IsA("JointInstance") or j:IsA("WeldConstraint") or j:IsA("Attachment") or j:IsA("Trail") then j:Destroy() end
				end
				c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch = true, false, false, false
				c.Parent = copy
			end
		end
		if #copy:GetChildren() == 0 then copy:Destroy() return end
		copy.Parent = ClassFX.Folder()
		local start = copy:GetPivot()
		local side = root.CFrame.RightVector * (if math.random() < 0.5 then 1 else -1)
		local stuck = CFrame.new(ground(root.Position + side * 7 - root.CFrame.LookVector * 2) + Vector3.new(0, 2.2, 0))
			* CFrame.Angles(math.rad(180 + math.random(-15, 15)), math.random() * 6, 0)
		local v = Instance.new("CFrameValue")
		v.Value = start
		v.Changed:Connect(function(cf) if copy.Parent then copy:PivotTo(cf) end end)
		TweenService:Create(v, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = stuck }):Play()
		task.delay(0.36, function()
			v:Destroy()
			if not copy.Parent then return end
			local gp = ground(stuck.Position)
			cracks(gp, 2, 4, 1.2)
			smoke(gp + Vector3.new(0, 0.5, 0), 3, 1.5)
		end)
		task.delay(BEAST_TIME * 0.6, function()
			for _, p in ipairs(copy:GetChildren()) do
				if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
			end
			Debris:AddItem(copy, 0.7)
		end)
	end)
end

-- The roar: a red shockwave bursts out, the world flashes, the floor
-- splits wide, rock is thrown; he is the BEAST.
local function onRoar(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	local r = msg.radius :: number
	local g = Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
	shockwave(g, r, char)
	task.delay(0.12, function() shockwave(g, r * 1.4, char) end)
	flipbook("shock", g + Vector3.new(0, 0.2, 0), r * 2.6, 1, seq(Color3.fromRGB(255, 110, 110), CRIMSON), 3)
	blast(g, r * 0.5)
	cracks(g, r * 1.3, 18, 2.8)
	fling(g + Vector3.new(0, 0.5, 0), 14, 30, 20, true)
	smoke(g + Vector3.new(0, 1, 0), 12, 4)
	for i = 1, 8 do
		local a = i / 8 * math.pi * 2 + math.random() * 0.3
		bolt(pos + Vector3.new(0, 1.5, 0), g + Vector3.new(math.cos(a) * r * 0.6, 0.3, math.sin(a) * r * 0.6), 0.22, 0.22)
	end
	ClassFX.Sound("boom", pos, 1, 0.5)
	ClassFX.Sound("charge", pos, 0.8, 0.35)
	if near(pos, 80) then
		screenFlash(0.35)
		tint("BerserkerRoar", { Brightness = -0.2, Saturation = -0.3, Contrast = 0.4, TintColor = Color3.fromRGB(255, 140, 140) }, 0.3, 0.05, 0.7)
		deps.shake(if msg.attacker == player then 1.6 else 0.8, 0.5)
	end
	if msg.attacker == player then
		deps.fovPunch(12, 0.4)
		if char then popWord(char, "BEAST AWAKENING", 34) end
	end
	task.defer(function()
		local p = msg.attacker :: Player
		if p and p.Parent then pcall(refreshLook, p) end
		refreshHud()
	end)
end

-- The change ends: down on one knee, red mist boiling off him as he
-- shrinks, the sword reforming in his hand in a streak of light.
local function onRevert(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local T = msg.t :: number
	revertPose(char)
	smoke(root.Position, 12, 3)
	sparks(root.Position + Vector3.new(0, 1, 0), 20, 10)
	task.delay(T * 0.55, function()
		if not root.Parent then return end
		local arm = char:FindFirstChild("Right Arm") :: BasePart?
		local hand = if arm then arm.Position - arm.CFrame.UpVector * 1.2 else root.Position
		SwordFX.Streak(hand, hand + root.CFrame.LookVector * 6 + Vector3.new(0, 2, 0), 0.5, HOT, 0.4, nil, CRIMSON)
		groundFlash(Vector3.new(root.Position.X, FireFX.GroundY(root.Position), root.Position.Z), 4)
		ClassFX.Sound("charge", root, 0.6, 1.1)
		if msg.attacker == player then deps.shake(0.4, 0.15) end
	end)
	task.defer(function()
		local p = msg.attacker :: Player
		if p and p.Parent then pcall(refreshLook, p) end
		refreshHud()
	end)
end

-- E · Beast Slam: the crouch splits the floor; the launch blasts it; chunks
-- of floor torn up where he'll land.
local function onBeastSlam(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then beastSlamPose(char) end
	local T = msg.t
	local origin = root.Position
	local g0 = Vector3.new(origin.X, FireFX.GroundY(origin), origin.Z)
	cracks(g0, 4, 8, 1.2)
	groundFlash(g0, 6)
	ClassFX.Sound("charge", root, 0.6, 0.8)
	task.delay(T.crouch, function()
		if not root.Parent then return end
		smoke(g0 + Vector3.new(0, 0.5, 0), 12, 3)
		shockwave(g0, 9, char)
		fling(g0 + Vector3.new(0, 0.3, 0), 10, 22, 16, true)
		for i = 1, 5 do
			local off = Vector3.new(math.cos(i * 1.3), 0, math.sin(i * 1.3)) * 1.2
			SwordFX.Streak(origin + off - Vector3.new(0, 2, 0), origin + off + Vector3.new(0, SLAM_HEIGHT * 0.8, 0), 0.45, CRIMSON, 0.4, nil, CORE)
		end
		ClassFX.Sound("whoosh", root, 1, 0.5)
		if msg.attacker == player then deps.fovPunch(8, 0.3) end
	end)
	task.delay(T.crouch + T.rise * 0.5, function()
		local landG = (msg.land :: Vector3?) or origin
		landG = Vector3.new(landG.X, FireFX.GroundY(landG), landG.Z)
		local release = liftDebris(landG, 10, 14, 1, T.rise * 0.5 + T.hang + T.fall)
		task.delay(T.rise * 0.5 + T.hang + T.fall, release)
	end)
end

-- The crash on all fours: a white-red flash, a crater, everything under him
-- crushed.
local function onBeastSlamImpact(msg: any)
	local pos = if msg.attacker == player and slamLanding then slamLanding else msg.pos :: Vector3
	local r = msg.radius :: number
	local g = Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
	crimsonImpact(g, r, true)
	eruption(g, r, 1.4, charOf(msg.attacker))
	linger(g, r * 0.8, 2.5)
	ClassFX.Sound("boom", pos, 1, 0.55)
	if near(pos, 80) then screenFlash(0.25) end
	if msg.attacker == player then
		deps.shake(1.5, 0.35)
		deps.fovPunch(10, 0.3)
	elseif near(pos, 80) then
		deps.shake(0.6, 0.25)
	end
end

-- The three rings rolling out: knocked back, launched (spikes burst up),
-- then a last great wave over the whole area.
local function onBeastRing(msg: any)
	local pos = if msg.attacker == player and slamLanding then slamLanding else msg.pos :: Vector3
	local r = msg.radius :: number
	local i = msg.i :: number
	local g = Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
	shockwave(g, r, charOf(msg.attacker))
	flipbook("shock", g + Vector3.new(0, 0.2, 0), r * 2.1, 1, seq(Color3.fromRGB(255, 120, 120), CRIMSON), 2.5)
	cracks(g, r, 8 + i * 4, 1.4)
	if i == 2 then shards(g, r * 0.9, 16, 2, 4.5, 0.9) end
	fling(g + Vector3.new(0, 0.4, 0), 6 + i * 3, 20 + i * 4, 14 + i * 3, true)
	ClassFX.Sound("rockHit", pos, 0.8, 0.9 - i * 0.1)
	if msg.attacker == player then deps.shake(0.9 - i * 0.15, 0.2) end
end

-- F · Carnage: the claws (poses); each swipe's gashes come with its hit.
local function onCarnage(msg: any)
	if msg.attacker == player then return end
	local char = charOf(msg.attacker)
	if char then carnagePose(char) end
end

-- Each swipe: three huge gashes across the front (the last a great rake
-- down, the floor torn open where it lands).
local function onCarnageHit(msg: any)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local r = msg.radius :: number
	local i = msg.i :: number
	local look = CFrame.lookAt(pos, pos + dir)
	if i == 1 then
		clawMarks(look * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(-8)), r, 170, 1, true)
	elseif i == 2 then
		clawMarks(look * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(8)), r, 170, -1, true)
	else
		clawMarks(look * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(-55)), r, 150, 1, true)
		local land = ground(pos + dir * r * 0.55)
		cracks(land, r * 0.4, 10, 1.4)
		shards(land, r * 0.35, 10, 1.5, 3.5, 0.8)
		fling(land + Vector3.new(0, 0.5, 0), 10, 26, 18, true)
		flipbook("shock", land + Vector3.new(0, 0.2, 0), r * 1.2, 1, seq(Color3.fromRGB(255, 120, 120), CRIMSON), 3)
	end
	sparks(pos + dir * r * 0.4, 14 + i * 6, 24)
	ClassFX.Sound("swordHit", pos, 0.9, 0.55 + i * 0.05)
	if msg.attacker == player then
		deps.shake(0.45 + i * 0.2, 0.14)
		deps.fovPunch(2 + i * 2, 0.14)
	end
end

-- Bleeding: blood dripping off them for a while.
local function onBleed(msg: any)
	local m = msg.model
	if typeof(m) ~= "Instance" or not m:IsA("Model") or not FxBudget.Allow("berserkerBleed", 6) then return end
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local e = Instance.new("ParticleEmitter")
	e.Name = "BeastBleed"
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(200, 10, 20), Color3.fromRGB(90, 0, 8))
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.1) })
	e.Lifetime = NumberRange.new(0.5, 0.8)
	e.Speed = NumberRange.new(1, 3)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Rate = 18
	e.Parent = root
	Debris:AddItem(e, tonumber(msg.duration) or 2.5)
end

-- Q · Beast Charge: a red streak and dust torn up down the path he gallops.
local function onBeastCharge(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local T = msg.t
	if msg.attacker ~= player then allFoursPose(char, T.crouch + T.run) end
	local from = msg.from :: Vector3
	local g0 = Vector3.new(from.X, FireFX.GroundY(from), from.Z)
	cracks(g0, 3, 6, 1)
	ClassFX.Sound("charge", root, 0.7, 0.9)
	task.delay(T.crouch, function()
		if not root.Parent then return end
		smoke(g0 + Vector3.new(0, 0.5, 0), 8, 2.6)
		fling(g0 + Vector3.new(0, 0.3, 0), 6, 16, 8, true)
		ClassFX.Sound("whoosh", root, 1, 0.55)
		if msg.attacker == player then deps.fovPunch(10, 0.35) end
		local last = root.Position
		for k = 1, 6 do
			task.delay(T.run * k / 6, function()
				if not root.Parent then return end
				local now = root.Position
				groundStreak(last, now, 4, 0.8)
				SwordFX.Streak(last + Vector3.new(0, 0.6, 0), now + Vector3.new(0, 0.6, 0), 0.6, CRIMSON, 0.35, nil, HOT)
				smoke(Vector3.new(now.X, FireFX.GroundY(now), now.Z) + Vector3.new(0, 0.4, 0), 2, 1.8)
				cracks(Vector3.new(now.X, FireFX.GroundY(now), now.Z), 2, 3, 0.8)
				last = now
				if msg.attacker == player then deps.shake(0.25, 0.08) end
			end)
		end
	end)
end

-- The grab: the biggest one hoisted overhead, red lightning crackling off it.
local function onBeastGrab(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	grabPose(char)
	local m = msg.model
	local vr = if typeof(m) == "Instance" then m:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	ClassFX.Sound("rockHit", root, 0.8, 0.6)
	for k = 1, 4 do
		task.delay((k - 1) * 0.1, function()
			if vr and vr.Parent and root.Parent then
				bolt(root.Position + Vector3.new(0, 2, 0), vr.Position, 0.18, 0.12)
				sparks(vr.Position, 8, 10)
			end
		end)
	end
end

-- The throw: hurled forward, a red streak trailing the body.
local function onBeastThrow(msg: any)
	local char = charOf(msg.attacker)
	if char then throwPose(char) end
	local m = msg.model
	local vr = if typeof(m) == "Instance" then m:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
	if not vr then return end
	ClassFX.Sound("whoosh", vr, 1, 0.5)
	if msg.attacker == player then deps.shake(0.6, 0.2) end
	local last = vr.Position
	for k = 1, 10 do
		task.delay(k * 0.08, function()
			if not vr.Parent then return end
			local now = vr.Position
			SwordFX.Streak(last, now, 0.8, CRIMSON, 0.3, nil, HOT)
			if k % 3 == 0 then smoke(now, 2, 2) end
			last = now
		end)
	end
end

-- The thrown body bowling another over.
local function onThrowHit(msg: any)
	if not FxBudget.Allow("berserkerThrowHit", 8) then return end
	local pos = msg.pos :: Vector3
	sparks(pos, 16, 20)
	local g = Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
	shockwave(g, 5, nil)
	ClassFX.Sound("rockHit", pos, 0.7, 1)
end

-- The Unchained charge spent on a skill: a burst off his body.
local function onEmpowered(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local g = Vector3.new(root.Position.X, FireFX.GroundY(root.Position), root.Position.Z)
	shockwave(g, 8, char)
	sparks(root.Position + Vector3.new(0, 1, 0), 30, 20)
	smoke(root.Position, 12, 2.5)
	for _ = 1, 3 do
		local a = math.random() * math.pi * 2
		bolt(root.Position + Vector3.new(0, 1.5, 0), root.Position + Vector3.new(math.cos(a) * 3.5, math.random() * 3, math.sin(a) * 3.5), 0.18, 0.15)
	end
end

local HANDLERS: { [string]: (any) -> () } = {
	combo = onCombo,
	smash = onSmash,
	rupture = onRupture,
	ruptureImpact = onRuptureImpact,
	ruptureEcho = onRuptureEcho,
	storm = onStorm,
	stormHit = onStormHit,
	stormFinal = onStormFinal,
	charge = onCharge,
	chargeEnd = onChargeEnd,
	claw = onClaw,
	maul = onMaul,
	awaken = onAwaken,
	roar = onRoar,
	revert = onRevert,
	beastSlam = onBeastSlam,
	beastSlamImpact = onBeastSlamImpact,
	beastRing = onBeastRing,
	carnage = onCarnage,
	carnageHit = onCarnageHit,
	bleed = onBleed,
	beastCharge = onBeastCharge,
	beastGrab = onBeastGrab,
	beastThrow = onBeastThrow,
	throwHit = onThrowHit,
	empowered = onEmpowered,
}

function BerserkerController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	for _, a in ipairs({ "BR_BeastUntil", "BR_Rage", "BR_Empowered", "SelectedClass", "InLobby", "SettingsOpen" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshHud)
	end
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localStep = 0
		if stormMover then
			stormMover.stop(false)
			stormMover = nil
		end
	end)
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		unchainedStep(now)
		-- (the gauge drains while Unchained)
		if hud and hud.Enabled and beastLeft(player) > 0 and fill then
			fill.Size = UDim2.fromScale(math.clamp(beastLeft(player) / unchainedFor, 0, 1), 1)
		end
	end)
	-- Both hands on the greatsword: the idle hold, then the two-handed grip
	-- enforced on whatever pose is playing (after every attack pose).
	CastPoses.addPostHook(function(dt)
		holdStep(dt)
		twoHandStep()
		beastStep(dt)
	end)
	watchLandings()
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(refreshLook, p)
				if not ok then warn("[BerserkerController] look", err) end
			end
			for p, L in pairs(looks) do
				if not p.Parent then
					dropLook(L)
					looks[p] = nil
				end
			end
			-- (the beast's timer running out: back to the Rage meter)
			if hud and hud.Enabled then refreshHud() end
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.BerserkerFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[BerserkerController]", msg.kind, err) end
		end
	end)
end

return BerserkerController
