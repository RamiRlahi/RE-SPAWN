--!strict
--[[
	RogueController.luau
	Client side of the Rogue, "The Shadow" (server: RogueServer).

	  • Your own moves happen at once on your screen (the dash and the Shadow
	    Step blink you there in the same frame; the server decides the hits).
	  • E twice: throw the Shadow Dagger, then press E again while it's out to
	    Shadow Step to it (behind the enemy it's stuck in). TryRecast catches
	    that second press before the cooldown check.
	  • Invisible Rogues vanish on other screens and are a faint shadow on
	    their own.
	  • Every Rogue effect for every player arrives over RogueFX.
	  • The Shadow Energy bar over the skill bar (RG_Energy, full = ENHANCED).

	The look is ink on paper: every effect is black and white only.
	  crescent    a white slash arc with a black outer rim, swept open in a
	              few frames, then thinning away
	  shards      white (and a few black) splinters flung outward
	  speedLines  white streaks along a motion
	  ink         black blots spreading and dissolving (smoke, the vanish)
	  ghost       a white afterimage of the Rogue dissolving upward (the
	              Shadow Step's departure, coming out of invisibility)
	  sigil       the Shadow Mark: an assassin's sigil (a blade between two
	              hooked prongs) floating over the enemy, trailing black smoke
	  longSlash   the Shadow Realm's cuts: long straight lines of white with a
	              black line beside them, criss-crossing the air
	All of them run off one RenderStepped loop (`animate`); the per-hit ones
	(realm slashes, marks) go through FxBudget.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local RogueLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RogueLook"))

local player = Players.LocalPlayer

local RogueController = {}

-- ── Tuning (matches RogueServer) ────────────────────────────────────────────
local SWING_INTERVAL = 0.26
local COMBO_RESET = 0.9
local ENERGY_MAX = 100

local INK = Color3.fromRGB(6, 6, 8)
local PAPER = Color3.new(1, 1, 1)
local ASH = Color3.fromRGB(150, 150, 156)

type Deps = { shake: (number, number) -> (), fovPunch: (number, number) -> (), getAim: (BasePart) -> Vector3 }
local deps: Deps

local localStep = 0
local lastSwing = 0
local busyUntil = 0

-- The dagger we threw (for the Shadow Step).
type MyDagger = { to: Vector3, stuck: Model?, landsAt: number, expires: number }
local myDagger: MyDagger? = nil

local function isRogue(): boolean
	return player:GetAttribute("SelectedClass") == "rogue"
end

local function charOf(p: any): Model?
	return if typeof(p) == "Instance" and p:IsA("Player") then p.Character else nil
end

local function rootOf(char: Model?): BasePart?
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function myRoot(): BasePart?
	return rootOf(player.Character)
end

local function near(pos: Vector3, reach: number): boolean
	local r = myRoot()
	return r ~= nil and (r.Position - pos).Magnitude <= reach
end

local function part(props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = ClassFX.Folder()
	return p
end

local function trailOn(char: Model, t: number)
	local tool = char:FindFirstChild("Shadowfang")
	local tr = tool and tool:FindFirstChild("DaggerTrail", true) :: Trail?
	if not tr then return end
	tr.Enabled = true
	task.delay(t, function() if tr.Parent then tr.Enabled = false end end)
end

-- ── One loop for every running effect ───────────────────────────────────────
-- `fn(a, dt)` gets 0..1 over `dur`; it's called a last time with a = 1.
local running: { { t0: number, dur: number, fn: (number, number) -> () } } = {}
local function animate(dur: number, fn: (number, number) -> ())
	table.insert(running, { t0 = os.clock(), dur = math.max(dur, 0.01), fn = fn })
end
local function stepAnims(dt: number)
	local now = os.clock()
	for i = #running, 1, -1 do
		local r = running[i]
		local a = math.min((now - r.t0) / r.dur, 1)
		local ok, err = pcall(r.fn, a, dt)
		if not ok then warn("[RogueController] fx:", err) end
		if a >= 1 or not ok then table.remove(running, i) end
	end
end

local function easeOut(a: number): number
	return 1 - (1 - a) ^ 3
end

-- ── Poses ───────────────────────────────────────────────────────────────────
local function swingPose(char: Model, step: number)
	if step == 1 then
		-- backhand: wound across the body, then whipped out wide
		CastPoses.play(char, {
			{ dur = 0.05, pose = { Root = { 0, 0, 0, 0, -0.45, 0.2 }, W = { 8, 50, 0 }, RS = { 35, 100, 0 }, LS = { 40, -20, -30 }, N = { 0, -25, 0 } } },
			{ dur = 0.07, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.35, -0.55 }, W = { -10, -55, 0 }, RS = { 15, -110, 0 }, LS = { -20, 0, -60 }, N = { 0, 22, 0 } } },
			{ dur = 0.12, pose = { Root = { 0, 0, 0, 0, -0.25, -0.35 }, W = { -5, -35, 0 }, RS = { 10, -75, 0 }, LS = { -10, 0, -40 } } },
		})
	elseif step == 2 then
		-- rising cut the other way
		CastPoses.play(char, {
			{ dur = 0.05, pose = { Root = { 0, 0, 0, 0, -0.55, 0 }, W = { 16, -50, 0 }, RS = { -15, -85, 0 }, LS = { 25, 0, -20 } } },
			{ dur = 0.07, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, 0.3, -0.35 }, W = { -20, 55, 0 }, RS = { 75, 100, 0 }, LS = { 45, 0, -70 }, N = { -12, 15, 0 } } },
			{ dur = 0.12, pose = { Root = { 0, 0, 0, 0, 0.1, -0.2 }, W = { -10, 30, 0 }, RS = { 50, 70, 0 }, LS = { 25, 0, -45 } } },
		})
	else
		-- the stab: drawn back low, then the whole body behind the point
		CastPoses.play(char, {
			{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.6, 0.4 }, W = { 12, 40, 0 }, RS = { -35, 20, 0, 0, 0, 0.8 }, LS = { 80, -10, -10 }, N = { 0, -30, 0 } } },
			{ dur = 0.07, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.9, -1.3 }, W = { -28, -12, 0 }, RS = { 8, 0, 0, 0, 0, -1.1 }, LS = { -35, 0, -55 }, RH = { -55, 0, 0 }, LH = { 45, 0, 0 } } },
			{ dur = 0.16, pose = { Root = { 0, 0, 0, 0, -0.55, -0.85 }, W = { -16, -8, 0 }, RS = { 6, 0, 0, 0, 0, -0.75 }, LS = { -20, 0, -40 } } },
		})
	end
end

local function throwPose(char: Model)
	-- coil back (the off hand points the way), then snap the arm over
	CastPoses.play(char, {
		{ dur = 0.09, pose = { Root = { 0, 0, 0, 0, -0.35, 0.5 }, W = { 10, 50, 0 }, RS = { 160, 40, 0 }, LS = { 90, -10, 0 }, N = { 0, -30, 0 } } },
		{ dur = 0.06, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.45, -0.7 }, W = { -18, -35, 0 }, RS = { 55, -25, 0 }, LS = { -25, 0, -55 }, N = { 0, 10, 0 } } },
		{ dur = 0.16, pose = { Root = { 0, 0, 0, 0, -0.25, -0.35 }, W = { -6, -15, 0 }, RS = { 40, -10, 0 }, LS = { -10, 0, -30 } } },
	})
end

-- Dash: a low lunge, the blade trailing behind.
local function dashPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.04, pose = { Root = { 0, 0, 0, 0, -0.9, 0 }, W = { -35, -10, 0 }, RS = { -40, 0, 30 }, LS = { -50, 0, -40 }, RH = { -40, 0, 0 }, LH = { 50, 0, 0 }, N = { 25, 0, 0 } } },
		{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, -0.9, 0 }, W = { -35, -10, 0 }, RS = { -40, 0, 30 }, LS = { -50, 0, -40 }, RH = { -40, 0, 0 }, LH = { 50, 0, 0 }, N = { 25, 0, 0 } } },
		{ dur = 0.1, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.5, 0 }, W = { -10, 60, 0 }, RS = { 20, 110, 0 }, LS = { -20, 0, -50 } } },
	})
end

-- Shadow Step: the flying slash (the timings TryRecast keys off).
local STEP_AIR = 0.3     -- seconds from appearing to landing
local STEP_HEIGHT = 6.5

-- The flying slash, as a pose (also played for other players' steps).
local function flyingSlashPose(char: Model)
	local up = { RS = { 175, 0, 15 }, LS = { 120, 0, -40 }, RH = { 40, 0, 0 }, LH = { 60, 0, 0 }, N = { 15, 0, 0 } }
	local function air(rx: number, h: number, back: number): { [string]: { number } }
		local p = table.clone(up)
		p.Root = { rx, 0, 0, 0, h, back }
		return p
	end
	CastPoses.play(char, {
		{ dur = 0.01, pose = air(0, STEP_HEIGHT, 2.5) },
		{ dur = STEP_AIR * 0.3, pose = air(-120, STEP_HEIGHT * 0.8, 1.8) },
		{ dur = STEP_AIR * 0.3, pose = air(-240, STEP_HEIGHT * 0.45, 0.9) },
		{ dur = STEP_AIR * 0.25, style = Enum.EasingStyle.Quart, pose = { Root = { -360, 0, 0, 0, -0.8, -0.3 }, W = { -35, 0, 0 }, RS = { 20, 0, 0 }, LS = { 10, 0, -40 }, RH = { -40, 0, 0 }, LH = { 50, 0, 0 } } },
		{ dur = 0.2, pose = { Root = { 0, 0, 0, 0, -0.6, -0.2 }, W = { -22, 0, 0 }, RS = { 25, 0, 0 }, LS = { 10, 0, -30 } } },
	})
end

-- Vanish: crouch and pull the cloak across the face.
local function vanishPose(char: Model)
	local held = { Root = { 0, 0, 0, 0, -0.9, 0.2 }, W = { 25, 0, 0 }, RS = { 40, 30, 0 }, LS = { 100, 60, 0 }, RH = { 40, 0, 0 }, LH = { -20, 0, 0 }, N = { -15, 20, 0 } }
	CastPoses.play(char, {
		{ dur = 0.1, pose = held },
		{ dur = 0.2, pose = held },
	})
end

-- Shadow Realm: rising, arms spread low and wide, head back, adrift.
local function realmPose(char: Model, dur: number)
	local spread = { RS = { -10, 0, 70 }, LS = { -10, 0, -70 }, W = { 14, 0, 0 }, N = { 24, 0, 0 }, RH = { 10, 0, 6 }, LH = { -8, 0, -6 } }
	CastPoses.play(char, {
		{ dur = 0.2, pose = { RS = { 50, 0, -30 }, LS = { 50, 0, 30 }, W = { -20, 0, 0 }, N = { -20, 0, 0 } } },
		{ dur = 0.3, style = Enum.EasingStyle.Back, pose = spread },
		{ dur = math.max(dur - 0.75, 0.2), pose = spread, style = Enum.EasingStyle.Sine, wobble = function(t)
			local b = math.sin(t * 2.6) * 5
			return { RS = { 0, 0, b }, LS = { 0, 0, -b }, W = { b * 0.5, 0, 0 } }
		end },
		-- the release: arms flung out and forward
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { RS = { 80, 0, 80 }, LS = { 80, 0, -80 }, W = { -25, 0, 0 }, N = { -10, 0, 0 } } },
		{ dur = 0.2, pose = { RS = { 60, 0, 60 }, LS = { 60, 0, -60 }, W = { -15, 0, 0 } } },
	})
end

-- ── The ninja run ───────────────────────────────────────────────────────────
-- Every Rogue sprinting (every client): leaning hard into it, both arms swept
-- straight back, head up. The legs keep the run animation. Eases out for any
-- attack pose (CastPoses) and while standing, airborne or riding.
local RUN_ARMS = { RS = { -80, 0, 14 }, LS = { -80, 0, -14 } }
local RUN_LEAN = { W = { -26, 0, 0 }, N = { 20, 0, 0 } }
local runWeight: { [Model]: number } = {}

local function ninjaRunStep(dt: number)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not char or p:GetAttribute("SelectedClass") ~= "rogue" then
			if char then runWeight[char] = nil end
			continue
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		local root = rootOf(char)
		if not hum or not root or hum.Health <= 0 then continue end
		local speed = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z).Magnitude
		-- (sprinting only: walking keeps the normal walk)
		local running = p:GetAttribute("IsSprinting") == true and speed > 6 and hum.FloorMaterial ~= Enum.Material.Air and not hum.Sit and not root.Anchored
			and not CastPoses.isPlaying(char) and char:GetAttribute("Tumbling") ~= true
		local w = runWeight[char] or 0
		w = if running then math.min(1, w + dt * 8) else math.max(0, w - dt * 10)
		runWeight[char] = w
		if w <= 0 then continue end
		local motors = CastPoses.resolveMotors(char)
		for key, v in pairs(RUN_ARMS) do
			local m = motors[key]
			-- (a little sway, so the arms aren't frozen)
			local sway = math.sin(os.clock() * 14 + (if key == "RS" then 0 else math.pi)) * 6
			if m then m.motor.Transform = m.motor.Transform:Lerp(m.basis:Inverse() * CastPoses.poseCF({ v[1] + sway, v[2], v[3] }) * m.basis, w) end
		end
		for key, v in pairs(RUN_LEAN) do
			local m = motors[key]
			if m then
				local add = m.basis:Inverse() * CastPoses.poseCF({ v[1] * w, v[2] * w, v[3] * w }) * m.basis
				m.motor.Transform = m.motor.Transform * add
			end
		end
	end
	for char in pairs(runWeight) do
		if not char.Parent then runWeight[char] = nil end
	end
end

-- ── Movement ────────────────────────────────────────────────────────────────
-- There in the same frame (walls and ledges still stop it short).
local function blinkTo(root: BasePart, to: Vector3, face: Vector3?)
	local stand = SafeMove.StandHeight(root)
	local start = root.CFrame
	local dir = flat(to - root.Position)
	local dist = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z).Magnitude
	dist = math.min(SafeMove.ClampDash(root, dir, dist), SafeMove.ClampToFloor(root, dir, dist))
	local at = root.Position + dir * dist
	local look = face or dir
	root.CFrame = CFrame.lookAt(at, at + look)
	root.AssemblyLinearVelocity = Vector3.new(0, math.max(root.AssemblyLinearVelocity.Y, 0), 0)
	SafeMove.SnapToFloor(root, stand)
	if not SafeMove.HasFloor(root) then
		root.CFrame = start
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- ── Ink and paper ───────────────────────────────────────────────────────────
-- A slash arc: `cf` sits at the arc's centre, the arc lies in its XZ plane,
-- bulging toward its LookVector. White core, black outer rim; it sweeps open
-- from one end in `sweep` seconds, then thins away over `life`.
local CRESCENT_SEGS = 9
local function crescent(cf: CFrame, radius: number, arcDeg: number, thick: number, life: number?, sweep: number?, reverse: boolean?)
	local lifeT, sweepT = life or 0.28, sweep or 0.06
	local arc = math.rad(arcDeg)
	local segLen = radius * arc / CRESCENT_SEGS * 1.18
	local cores, rims = {}, {}
	local frames = {}
	for i = 1, CRESCENT_SEGS do
		local u = (i - 0.5) / CRESCENT_SEGS
		local th = (u - 0.5) * arc
		local w = thick * math.sin(math.pi * u) ^ 0.7 -- tapered at both tips
		local at = cf * CFrame.Angles(0, th, 0) * CFrame.new(0, 0, -radius)
		frames[i] = { at = at, w = w }
		rims[i] = part({ Size = Vector3.new(segLen, 0.05, w * 1.7 + 0.08), Color = INK, Material = Enum.Material.SmoothPlastic,
			Transparency = 1, CFrame = at * CFrame.new(0, -0.02, -w * 0.45) })
		cores[i] = part({ Size = Vector3.new(segLen, 0.07, w), Color = PAPER, Transparency = 1, CFrame = at })
	end
	animate(sweepT + lifeT, function(a)
		local t = a * (sweepT + lifeT)
		local shown = math.clamp(t / sweepT, 0, 1)
		local fade = math.clamp((t - sweepT) / lifeT, 0, 1)
		for i = 1, CRESCENT_SEGS do
			local k = if reverse then CRESCENT_SEGS + 1 - i else i
			local on = (k - 1) / CRESCENT_SEGS < shown
			local f = frames[i]
			local w = f.w * (1 - easeOut(fade) * 0.9)
			-- the leading tip is brightest; the far end goes first
			local tip = math.clamp(fade * 1.6 - (CRESCENT_SEGS - k) / CRESCENT_SEGS * 0.6, 0, 1)
			cores[i].Transparency = if on then tip else 1
			rims[i].Transparency = if on then 0.05 + tip * 0.95 else 1
			cores[i].Size = Vector3.new(segLen, 0.07, math.max(w, 0.02))
			rims[i].Size = Vector3.new(segLen, 0.05, math.max(w * 1.7, 0.02) + 0.08)
			rims[i].CFrame = f.at * CFrame.new(0, -0.02, -w * 0.45)
		end
		if a >= 1 then
			for i = 1, CRESCENT_SEGS do
				cores[i]:Destroy()
				rims[i]:Destroy()
			end
		end
	end)
end

-- A crescent aimed along `dir` at `at`, tilted by `roll` degrees.
local function slashAt(at: Vector3, dir: Vector3, radius: number, roll: number, arcDeg: number?, thick: number?, life: number?, reverse: boolean?)
	local d = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local cf = CFrame.lookAt(at - d * radius * 0.6, at - d * radius * 0.6 + d) * CFrame.Angles(0, 0, math.rad(roll))
	crescent(cf, radius, arcDeg or 130, thick or 0.55, life, nil, reverse)
end

-- White (and some black) splinters flung outward from `at`.
local function shards(at: Vector3, count: number, speed: number, size: number?, up: number?)
	local s = size or 1
	for _ = 1, count do
		local dir = Vector3.new(math.random() - 0.5, (math.random() - 0.2) * (up or 0.6), math.random() - 0.5)
		dir = if dir.Magnitude > 0.01 then dir.Unit else Vector3.yAxis
		local black = math.random() < 0.3
		local p = part({ Size = Vector3.new(0.1, 0.35 * s, (0.7 + math.random() * 0.9) * s), Color = if black then INK else PAPER,
			Material = if black then Enum.Material.SmoothPlastic else Enum.Material.Neon,
			CFrame = CFrame.lookAt(at, at + dir) }, "WedgePart")
		local spin = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 18
		local v = dir * speed * (0.6 + math.random() * 0.6)
		local life = 0.3 + math.random() * 0.25
		local pos = at
		local rot = p.CFrame.Rotation
		animate(life, function(a, dt)
			v = v * (1 - math.min(dt * 5, 0.5)) + Vector3.new(0, -30 * dt, 0)
			pos += v * dt
			rot = rot * CFrame.Angles(spin.X * dt, spin.Y * dt, spin.Z * dt)
			p.CFrame = CFrame.new(pos) * rot
			p.Transparency = a ^ 2
			if a >= 1 then p:Destroy() end
		end)
	end
end

-- White streaks running along `dir` around `at`.
local function speedLines(at: Vector3, dir: Vector3, count: number, length: number, spread: number?)
	local d = if dir.Magnitude > 0.01 then dir.Unit else Vector3.new(0, 0, -1)
	local side = d:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	local sp = spread or 2.5
	for _ = 1, count do
		local off = side * (math.random() - 0.5) * sp * 2 + Vector3.new(0, (math.random() - 0.3) * sp, 0)
		local len = length * (0.5 + math.random() * 0.6)
		local start = at + off - d * len * 0.3
		local black = math.random() < 0.25
		local p = part({ Size = Vector3.new(0.06, 0.06, len), Color = if black then INK else PAPER,
			Material = if black then Enum.Material.SmoothPlastic else Enum.Material.Neon,
			CFrame = CFrame.lookAt(start, start + d) })
		local life = 0.18 + math.random() * 0.12
		animate(life, function(a)
			local pos = start + d * len * 0.8 * easeOut(a)
			p.CFrame = CFrame.lookAt(pos, pos + d)
			p.Size = Vector3.new(0.06, 0.06, len * (1 - a * 0.7))
			p.Transparency = a
			if a >= 1 then p:Destroy() end
		end)
	end
end

-- Black blots spreading out and dissolving (smoke, the vanish).
local function ink(pos: Vector3, size: number?, rise: number?)
	local s = size or 1
	for i = 1, 7 do
		local a = (i / 7) * math.pi * 2 + math.random()
		local off = Vector3.new(math.cos(a) * 0.6 * s, 0.4 + math.random() * 1.6 * s, math.sin(a) * 0.6 * s)
		local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (1.5 * s), Material = Enum.Material.SmoothPlastic,
			Color = INK, Transparency = 0.05, CFrame = CFrame.new(pos + off) })
		local goal = b.CFrame + Vector3.new(math.cos(a) * 1.8 * s, (rise or 1.4) * s, math.sin(a) * 1.8 * s)
		TweenService:Create(b, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * (3.6 * s), Transparency = 1, CFrame = goal,
		}):Play()
		Debris:AddItem(b, 0.6)
	end
end

-- A flat ring on the floor: white core inside a black band, opening out.
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local function floorRing(pos: Vector3, radius: number, life: number, white: boolean?)
	local col = if white == false then INK else PAPER
	local r = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1, 1), Color = col,
		Material = if white == false then Enum.Material.SmoothPlastic else Enum.Material.Neon,
		Transparency = 0.1, CFrame = CFrame.new(pos) * FLAT })
	local inner = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.8, 0.8), Color = if white == false then PAPER else INK,
		Material = Enum.Material.SmoothPlastic, Transparency = 0.1, CFrame = CFrame.new(pos + Vector3.new(0, 0.01, 0)) * FLAT })
	animate(life, function(a)
		local e = easeOut(a)
		local d = 1 + radius * 2 * e
		r.Size = Vector3.new(0.12, d, d)
		inner.Size = Vector3.new(0.14, d * (0.6 + 0.35 * e), d * (0.6 + 0.35 * e))
		r.Transparency = 0.1 + a * 0.9
		inner.Transparency = 0.1 + a * 0.9
		if a >= 1 then
			r:Destroy()
			inner:Destroy()
		end
	end)
end

-- An afterimage of `char` posed at `cf`. "ink": black body, the one
-- Highlight on the set draws it a white outline; "paper": white, rising and
-- dissolving.
local function ghost(char: Model, cf: CFrame, style: "ink" | "paper", life: number, drift: Vector3?)
	local root = rootOf(char)
	if not root then return end
	local model = Instance.new("Model")
	model.Name = "RogueGhost"
	model.Parent = ClassFX.Folder()
	local parts: { { p: BasePart, rel: CFrame } } = {}
	local rootCF = root.CFrame
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and d.Size.Magnitude > 0.3 then
			local rel = rootCF:ToObjectSpace(d.CFrame)
			local g = Instance.new("Part")
			g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = true, false, false, false, false
			g.Material = if style == "paper" then Enum.Material.Neon else Enum.Material.SmoothPlastic
			g.Color = if style == "paper" then PAPER else INK
			g.Size = d.Size
			g.CFrame = cf * rel
			g.Transparency = 0.05
			g.Parent = model
			table.insert(parts, { p = g, rel = rel })
		end
	end
	local hl: Highlight? = nil
	if style == "ink" then
		local h = Instance.new("Highlight")
		h.FillTransparency = 1
		h.OutlineColor = PAPER
		h.OutlineTransparency = 0
		h.DepthMode = Enum.HighlightDepthMode.Occluded
		h.Adornee = model
		h.Parent = model
		hl = h
	end
	local move = drift or Vector3.zero
	animate(life, function(a)
		local e = easeOut(a)
		local at = cf + move * e
		for _, it in ipairs(parts) do
			it.p.CFrame = at * it.rel
			it.p.Transparency = 0.05 + a ^ 1.5 * 0.95
		end
		if hl then hl.OutlineTransparency = a end
		if a >= 1 then model:Destroy() end
	end)
end

-- The dash: clean. One white cut along the path over a black one, snapping
-- thin, a few streaks, a puff where you left.
local function dashFX(char: Model, from: Vector3, to: Vector3, enhanced: boolean)
	local root = rootOf(char)
	if not root then return end
	local dir = flat(to - from)
	local len = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	if len < 0.5 then return end
	local mid = (from + to) / 2 + Vector3.new(0, 0.2, 0)
	local cf = CFrame.lookAt(mid, mid + dir)
	local back = part({ Size = Vector3.new(0.5, 0.12, len), Color = INK, Material = Enum.Material.SmoothPlastic, CFrame = cf })
	local cut = part({ Size = Vector3.new(0.22, 0.14, len), Color = PAPER, CFrame = cf + Vector3.new(0, 0.02, 0) })
	local w = if enhanced then 1.5 else 1
	animate(0.28, function(a)
		local k = 1 - easeOut(a)
		back.Size = Vector3.new(0.5 * w * k + 0.01, 0.12, len)
		cut.Size = Vector3.new(0.22 * w * k + 0.01, 0.14, len)
		back.Transparency, cut.Transparency = a, a ^ 2
		if a >= 1 then
			back:Destroy()
			cut:Destroy()
		end
	end)
	speedLines(mid + Vector3.new(0, 1.2, 0), dir, if enhanced then 7 else 5, len * 0.5, 1.4)
	floorRing(Vector3.new(from.X, root.Position.Y - 2.8, from.Z), 2.5, 0.22, false)
end

local function flash(t: number, from: number?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "RogueFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = PAPER
	f.BackgroundTransparency = from or 0.2
	f.BorderSizePixel = 0
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, t + 0.05)
end

-- ── The thrown dagger ───────────────────────────────────────────────────────
-- (`to`, `stuck` and `travel` can be corrected in flight: daggerStop)
type FlyingDagger = { model: Model, conn: RBXScriptConnection?, to: Vector3, stuck: Model?, travel: number, t0: number, landed: boolean }
local daggers: { [Player]: FlyingDagger } = {}

local function dropDagger(owner: Player)
	local d = daggers[owner]
	if not d then return end
	daggers[owner] = nil
	if d.conn then d.conn:Disconnect() end
	local m = d.model
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
	end
	Debris:AddItem(m, 0.3)
end

-- The thrown dagger: Shadowfang itself (RogueLook), welded to one anchored
-- part that's all that moves, with a white glow and a white streak.
local function buildDagger(): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "ShadowDagger"
	local anchor = part({ Name = "Anchor", Size = Vector3.one * 0.2, Transparency = 1 })
	anchor.Parent = m
	RogueLook.BuildBlade(m, anchor)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") and d ~= anchor then
			d.Anchored = false
			d.CanQuery = false
		end
	end
	local glow = Instance.new("Part")
	glow.Name = "Glow"
	glow.Shape = Enum.PartType.Ball
	glow.Material = Enum.Material.Neon
	glow.Color = PAPER
	glow.Transparency = 0.7
	glow.Size = Vector3.one * 1.2
	glow.CanCollide, glow.CanQuery, glow.CanTouch, glow.CastShadow, glow.Massless = false, false, false, false, true
	glow.CFrame = anchor.CFrame * CFrame.new(0, 0, -1)
	local gw = Instance.new("WeldConstraint")
	gw.Part0, gw.Part1 = anchor, glow
	gw.Parent = glow
	glow.Parent = m
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.15, 0.6)
	a0.Parent = anchor
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.15, 0.6)
	a1.Parent = anchor
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Color = ColorSequence.new(PAPER, ASH)
	tr.Transparency = NumberSequence.new(0, 1)
	tr.Lifetime = 0.18
	tr.LightEmission = 1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Parent = anchor
	m.PrimaryPart = anchor
	m.Parent = ClassFX.Folder()
	return m, anchor
end

-- (`cf`: the blade's middle, its point along -Z)
local function placeDagger(m: Model, cf: CFrame)
	(m.PrimaryPart :: BasePart).CFrame = cf * CFrame.new(0, 0, 1)
end

local function onDagger(msg: any)
	local owner = msg.attacker :: Player
	dropDagger(owner)
	local from, to = msg.from :: Vector3, msg.to :: Vector3
	local travel = math.max(0.03, tonumber(msg.travel) or 0.2)
	local stuck = if typeof(msg.stuck) == "Instance" then msg.stuck :: Model else nil
	local life = tonumber(msg.life) or 4
	if owner == player then
		myDagger = { to = to, stuck = stuck, landsAt = os.clock() + travel, expires = os.clock() + travel + life }
	end
	local caster = charOf(owner)
	if caster and owner ~= player then throwPose(caster) end
	local m, _ = buildDagger()
	local d: FlyingDagger = { model = m, conn = nil, to = to, stuck = stuck, travel = travel, t0 = os.clock(), landed = false }
	daggers[owner] = d
	local dir = flat(to - from)
	local y = 1.6
	-- the release: a puff of lines off the hand
	speedLines(from + Vector3.new(0, y, 0) + dir * 2, dir, 6, 5, 0.8)
	floorRing(from + dir * 1.5 + Vector3.new(0, y, 0), 1.6, 0.18)
	local offset: CFrame? = nil
	local spin = 0
	d.conn = RunService.RenderStepped:Connect(function(dt)
		local a = (os.clock() - d.t0) / d.travel
		-- (corrections land it where the server says: read them each frame)
		to, stuck = d.to, d.stuck
		if a < 1 then
			spin += dt * 30
			local p = from:Lerp(to, a) + Vector3.new(0, y, 0)
			placeDagger(m, CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, spin))
			return
		end
		if not d.landed then
			d.landed = true
			offset = nil
			-- The hit: a white X of cuts, splinters, a blot of ink.
			local at = to + Vector3.new(0, y, 0)
			if stuck then
				slashAt(at, dir, 2.4, 45, 110, 0.4, 0.22)
				slashAt(at, dir, 2.4, -45, 110, 0.4, 0.22, true)
				shards(at, 10, 20, 0.8)
				ink(at - Vector3.new(0, 1, 0), 0.6, 0.6)
			else
				shards(to + Vector3.new(0, 0.6, 0), 5, 12, 0.6, 1.2)
				floorRing(to + Vector3.new(0, 0.1, 0), 2.2, 0.3)
			end
		end
		-- Landed: in the enemy (follows it) or in the floor, pulsing white.
		local sroot = stuck and rootOf(stuck)
		if sroot and stuck and stuck.Parent then
			if not offset then
				local at = to + Vector3.new(0, y, 0)
				offset = sroot.CFrame:ToObjectSpace(CFrame.lookAt(at, at + dir))
			end
			placeDagger(m, sroot.CFrame * (offset :: CFrame))
		elseif not offset then
			offset = CFrame.new()
			placeDagger(m, CFrame.new(to + Vector3.new(0, 0.6, 0)) * CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(math.rad(-60), 0, 0))
		end
		local g = m:FindFirstChild("Glow") :: BasePart?
		if g then
			local pulse = 0.5 + 0.5 * math.sin(os.clock() * 9)
			g.Transparency = 0.45 + 0.4 * pulse
			g.Size = Vector3.one * (1 + 0.6 * pulse)
		end
	end)
end

-- The server's flight stopped the dagger somewhere other than where it was
-- first drawn going (a mob stepped into its path, a big one's body was in the
-- way): land it there now.
local function onDaggerStop(msg: any)
	local owner = msg.attacker :: Player
	local d = daggers[owner]
	local to = msg.to :: Vector3
	local stuck = if typeof(msg.stuck) == "Instance" then msg.stuck :: Model else nil
	if d then
		d.to, d.stuck = to, stuck
		d.travel = math.max(0.03, os.clock() - d.t0) -- (lands this frame)
		d.landed = false
	end
	if owner == player and myDagger then
		myDagger.to, myDagger.stuck = to, stuck
		myDagger.landsAt = math.min(myDagger.landsAt, os.clock())
	end
end

local function onStep(msg: any)
	local owner = msg.attacker :: Player
	dropDagger(owner)
	if owner == player then myDagger = nil end
	local from, to = msg.from :: Vector3, msg.to :: Vector3
	local char = charOf(owner)
	-- Where you were: a white ghost breaking up, and ink.
	ink(from - Vector3.new(0, 1.5, 0), 0.9, 1.2)
	shards(from, 6, 10, 0.7, 1.4)
	-- The line between: a white thread over a black one, snapping away.
	local dir = flat(to - from)
	local len = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	if len > 1 then
		local mid = (from + to) / 2 + Vector3.new(0, 0.5, 0)
		local back = part({ Size = Vector3.new(0.3, 0.3, len), Color = INK, Material = Enum.Material.SmoothPlastic,
			CFrame = CFrame.lookAt(mid, mid + dir) })
		local line = part({ Size = Vector3.new(0.14, 0.14, len), Color = PAPER, CFrame = CFrame.lookAt(mid, mid + dir) + Vector3.new(0, 0.05, 0) })
		animate(0.25, function(a)
			back.Size = Vector3.new(0.3 * (1 - a), 0.3 * (1 - a), len)
			line.Size = Vector3.new(0.14 * (1 - a) + 0.01, 0.14 * (1 - a) + 0.01, len)
			back.Transparency, line.Transparency = a, a
			if a >= 1 then
				back:Destroy()
				line:Destroy()
			end
		end)
		speedLines(mid + Vector3.new(0, 1, 0), dir, 8, math.min(len, 14), 1.5)
	end
	-- Behind them: two crossed cuts through the target, splinters, a ring.
	local target = if typeof(msg.target) == "Instance" then msg.target :: Model else nil
	local troot = rootOf(target)
	if troot then
		local at = troot.Position + Vector3.new(0, 1.2, 0)
		local into = flat(troot.Position - to)
		if owner ~= player then
			-- (our own flying cut is drawn as we land, in TryRecast)
			crescent(CFrame.lookAt(at + into * 2.5, at - into) * CFrame.Angles(0, 0, math.rad(90)), 4.2, 150, 0.85, 0.32, 0.05)
			shards(at, 12, 24, 1)
		end
		floorRing(Vector3.new(at.X, troot.Position.Y - 2.8, at.Z), 5, 0.35)
		ClassFX.Sound("swordHit", troot, 0.7, 0.9)
	else
		floorRing(to - Vector3.new(0, 2.8, 0), 3.5, 0.3)
	end
	if char then
		ink(to - Vector3.new(0, 1.5, 0), 0.7, 0.8)
		if owner ~= player then
			flyingSlashPose(char)
			trailOn(char, 0.4)
			local root = rootOf(char)
			if root then ClassFX.Sound("whoosh", root, 0.5, 1.3) end
		end
	end
end

-- ── Marks ───────────────────────────────────────────────────────────────────
-- The assassin's sigil over the marked enemy: a long blade, pointed both
-- ends, between two hooked prongs curving out and down, white with a black
-- outline, always turned to the camera. Black smoke trails off it and off the
-- enemy, and a ring pulses under its feet. All of it stays as long as the
-- mark does.
--
-- The shape is drawn from flat triangles (each one two WedgeParts), welded to
-- one anchor, so a frame costs one CFrame per mark.
local SIGIL_SCALE = 1.5   -- studs per unit of the outline below
local SIGIL_RISE = 6      -- studs over the enemy's root
local MAX_SIGILS = 8      -- (more marks than this keep only the ring)
type P = { number }
-- The centre blade, as triangles.
local BLADE: { { P } } = {
	{ { 0, 1.55 }, { -0.2, 0.55 }, { 0.2, 0.55 } },
	{ { -0.2, 0.55 }, { 0.2, 0.55 }, { 0.1, 0.24 } },
	{ { -0.2, 0.55 }, { 0.1, 0.24 }, { -0.1, 0.24 } },
	{ { -0.1, 0.24 }, { 0.1, 0.24 }, { 0.27, 0 } },
	{ { -0.1, 0.24 }, { 0.27, 0 }, { -0.27, 0 } },
	{ { -0.27, 0 }, { 0.27, 0 }, { 0, -1.7 } },
}
-- The right prong: its outer and inner edges, top to bottom (the left is the
-- mirror image).
local PRONG_OUT: { P } = { { 0.3, 1.02 }, { 0.62, 0.52 }, { 0.98, 0.02 }, { 0.64, -0.34 }, { 0.46, -0.98 } }
local PRONG_IN: { P } = { { 0.3, 1.02 }, { 0.44, 0.46 }, { 0.6, 0.04 }, { 0.43, -0.3 }, { 0.46, -0.98 } }

local function prongTris(side: number): { { P } }
	local out = {}
	local function m(p: P): P return { p[1] * side, p[2] } end
	for i = 1, #PRONG_OUT - 1 do
		local o1, o2, i1, i2 = m(PRONG_OUT[i]), m(PRONG_OUT[i + 1]), m(PRONG_IN[i]), m(PRONG_IN[i + 1])
		table.insert(out, { o1, o2, i2 })
		table.insert(out, { o1, i2, i1 })
	end
	return out
end
local SHAPES = { BLADE, prongTris(1), prongTris(-1) }

-- One flat triangle a, b, c (anchor space) as two wedges.
local function triangle(anchor: BasePart, parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3, neon: boolean)
	local ab, ac, bc = b - a, c - a, c - b
	if ab:Cross(ac).Magnitude < 1e-4 then return end -- (no area)
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	-- the longest side becomes b-c
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for i = 1, 2 do
		local w = Instance.new("WedgePart")
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch, w.CastShadow = false, false, false, false, false
		w.Massless = true
		w.Material = if neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
		w.Color = color
		if i == 1 then
			w.Size = Vector3.new(0.05, height, math.abs(ab:Dot(back)))
			w.CFrame = anchor.CFrame * CFrame.fromMatrix((a + b) / 2, right, up, back)
		else
			w.Size = Vector3.new(0.05, height, math.abs(ac:Dot(back)))
			w.CFrame = anchor.CFrame * CFrame.fromMatrix((a + c) / 2, -right, up, -back)
		end
		local weld = Instance.new("WeldConstraint")
		weld.Part0, weld.Part1 = anchor, w
		weld.Parent = w
		w.Parent = parent
	end
end

local function smokeEmitter(parent: Instance, rate: number, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Name = "MarkSmoke"
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(INK)
	e.LightEmission = 0
	e.LightInfluence = 0
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.25),
		NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size * 1.6) })
	e.Lifetime = NumberRange.new(0.9, 1.5)
	e.Speed = NumberRange.new(0.6, 1.8)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 2.5, 0)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Rotation = NumberRange.new(0, 360)
	e.Rate = rate
	e.Parent = parent
	return e
end

-- The sigil, built at the origin: returns its anchor (move only this).
local function buildSigil(): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = "AssassinSigil"
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch, anchor.CastShadow = true, false, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.identity
	anchor.Parent = model
	model.PrimaryPart = anchor
	for _, shape in ipairs(SHAPES) do
		-- the shape's middle, for its outline
		local cx, cy, n = 0, 0, 0
		for _, t in ipairs(shape) do
			for _, p in ipairs(t) do
				cx += p[1]
				cy += p[2]
				n += 1
			end
		end
		cx, cy = cx / n, cy / n
		for _, t in ipairs(shape) do
			-- the black outline: the same triangle a little bigger, just behind
			local pts: { Vector3 } = {}
			local white: { Vector3 } = {}
			for i, p in ipairs(t) do
				local x, y = p[1] * SIGIL_SCALE, p[2] * SIGIL_SCALE
				white[i] = Vector3.new(x, y, 0)
				local ox, oy = cx * SIGIL_SCALE, cy * SIGIL_SCALE
				pts[i] = Vector3.new(ox + (x - ox) * 1.16, oy + (y - oy) * 1.08, 0.07)
			end
			triangle(anchor, model, pts[1], pts[2], pts[3], INK, false)
			triangle(anchor, model, white[1], white[2], white[3], PAPER, true)
		end
	end
	local a = Instance.new("Attachment")
	a.Parent = anchor
	smokeEmitter(a, 10, 1.6)
	model.Parent = ClassFX.Folder()
	return model, anchor
end

type Mark = { sigil: Model?, anchor: BasePart?, ring: BasePart, band: BasePart, root: BasePart, smoke: Attachment, token: number, born: number }
local marks: { [Model]: Mark } = {}
local sigilCount = 0

local function dropMark(model: Model)
	local m = marks[model]
	if not m then return end
	marks[model] = nil
	if m.sigil then
		sigilCount -= 1
		local sigil = m.sigil
		for _, d in ipairs(sigil:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "Anchor" then
				TweenService:Create(d, TweenInfo.new(0.2), { Transparency = 1 }):Play()
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		Debris:AddItem(sigil, 1.6)
	end
	for _, d in ipairs(m.smoke:GetChildren()) do
		if d:IsA("ParticleEmitter") then d.Enabled = false end
	end
	Debris:AddItem(m.smoke, 1.6)
	for _, p in ipairs({ m.ring, m.band }) do
		TweenService:Create(p, TweenInfo.new(0.2), { Transparency = 1 }):Play()
		Debris:AddItem(p, 0.25)
	end
end

local function onMark(msg: any)
	local model = msg.model
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then return end
	local dur = tonumber(msg.duration) or 5
	local mk = marks[model]
	if not mk or not mk.ring.Parent then
		if not FxBudget.Allow("rogueMark", 12) then return end
		local root = rootOf(model)
		if not root then return end
		local sigil, anchor = nil, nil
		if sigilCount < MAX_SIGILS then
			sigil, anchor = buildSigil()
			sigilCount += 1
		end
		local smoke = Instance.new("Attachment")
		smoke.Name = "ShadowMarkSmoke"
		smoke.Parent = root
		smokeEmitter(smoke, 12, 2.4)
		local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 5, 5), Color = PAPER, Transparency = 0.15 })
		local band = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 4.2, 4.2), Color = INK,
			Material = Enum.Material.SmoothPlastic, Transparency = 0.25 })
		mk = { sigil = sigil, anchor = anchor, ring = ring, band = band, root = root, smoke = smoke, token = 0, born = os.clock() }
		marks[model] = mk
		shards(root.Position + Vector3.new(0, SIGIL_RISE, 0), 6, 10, 0.5, 1.5)
		ink(root.Position + Vector3.new(0, SIGIL_RISE - 1, 0), 0.6, 0.8)
	end
	local mine = mk :: Mark
	mine.token += 1
	local token = mine.token
	task.delay(dur, function()
		if marks[model] == mine and mine.token == token then dropMark(model) end
	end)
end

-- Every mark: the sigil over its enemy facing the camera (slammed in from
-- big, then bobbing), the ring under its feet.
local function stepMarks()
	local now = os.clock()
	local cam = workspace.CurrentCamera
	for model, m in pairs(marks) do
		if not model.Parent or not m.root.Parent then
			dropMark(model)
			continue
		end
		local hum = model:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health <= 0 then
			dropMark(model)
			continue
		end
		local feet = m.root.Position - Vector3.new(0, m.root.Size.Y / 2 + (if hum then hum.HipHeight else 2) - 0.12, 0)
		local pulse = 0.5 + 0.5 * math.sin(now * 7)
		local d = 4.6 + pulse * 0.8
		m.ring.Size = Vector3.new(0.08, d, d)
		m.band.Size = Vector3.new(0.1, d - 0.7, d - 0.7)
		m.ring.CFrame = CFrame.new(feet) * FLAT
		m.band.CFrame = CFrame.new(feet + Vector3.new(0, 0.01, 0)) * FLAT
		if m.anchor and cam then
			local age = now - m.born
			-- dropped in from above with a spin, then a slow bob
			local slam = 1 - easeOut(math.min(age / 0.25, 1))
			local at = m.root.Position + Vector3.new(0, SIGIL_RISE + slam * 3 + math.sin(now * 2.4) * 0.15, 0)
			-- (turned square to the camera, tilt and all: the top-down camera
			-- would see a merely upright one edge-on)
			local camUp = cam.CFrame.UpVector
			local face = CFrame.lookAt(at, cam.CFrame.Position, camUp)
			m.anchor.CFrame = face * CFrame.Angles(0, slam * math.pi * 2, 0)
		end
	end
end

-- ── Invisibility ────────────────────────────────────────────────────────────
local hidden: { [Model]: { conn: RBXScriptConnection, amount: number } } = {}

local function fadeOne(d: Instance, amount: number)
	if d:IsA("BasePart") or d:IsA("Decal") then
		(d :: any).LocalTransparencyModifier = amount
	end
end

-- Fade `char` to `amount` (0 = seen) over `t`.
local function setHidden(char: Model, on: boolean, amount: number, t: number?)
	local h = hidden[char]
	if h then
		h.conn:Disconnect()
		hidden[char] = nil
	end
	local goal = if on then amount else 0
	if on then
		hidden[char] = { amount = amount, conn = char.DescendantAdded:Connect(function(d) fadeOne(d, amount) end) }
	end
	local dur = t or 0
	if dur <= 0 then
		for _, d in ipairs(char:GetDescendants()) do fadeOne(d, goal) end
		return
	end
	local start = if on then 0 else (h and h.amount or 0)
	local list = char:GetDescendants()
	animate(dur, function(a)
		local v = start + (goal - start) * easeOut(a)
		for _, d in ipairs(list) do
			if d.Parent then fadeOne(d, v) end
		end
	end)
end

local function onHidden(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	if not char then return end
	local root = rootOf(char)
	local on = msg.on == true
	if root then
		local feet = root.Position - Vector3.new(0, 2.6, 0)
		if on then
			-- ink rising round you as you sink into it, motes of white blown off
			ink(feet + Vector3.new(0, 0.5, 0), 1.1, 2.4)
			floorRing(feet + Vector3.new(0, 0.1, 0), 4.5, 0.4, false)
			shards(root.Position, 8, 8, 0.6, 2)
			if owner ~= player then vanishPose(char) end
		else
			-- out of nowhere: a white ring snapping outward and splinters
			floorRing(feet + Vector3.new(0, 0.1, 0), 5, 0.3)
			shards(root.Position, 8, 18, 0.7)
			ghost(char, root.CFrame, "paper", 0.3, Vector3.new(0, 1.5, 0))
		end
	end
	-- Others lose sight of you completely; you see your own faint shadow.
	setHidden(char, on, if owner == player then 0.7 else 1, if on then 0.35 else 0.15)
	if owner == player and on and deps then deps.fovPunch(4, 0.3) end
end

-- ── Shadow Realm ────────────────────────────────────────────────────────────
-- Long straight cuts criss-cross the air
-- around the hovering Rogue: each one a white blade of light with a black
-- line running beside it, ripped across in an instant, then thinning out.
-- A few four-point glints flash where they cross. Nothing on the floor.

-- One cut through `through` along `dir` (any angle, `len` long).
local function longSlash(through: Vector3, dir: Vector3, len: number, thick: number, life: number)
	local d = if dir.Magnitude > 0.01 then dir.Unit else Vector3.xAxis
	local from = through - d * len / 2
	local side = d:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.zAxis
	local gap = side * thick * 1.6
	local core = part({ Size = Vector3.new(thick, thick, 0.1), Color = PAPER, Transparency = 0 })
	local shadow = part({ Size = Vector3.new(thick * 0.8, thick * 0.8, 0.1), Color = INK, Material = Enum.Material.SmoothPlastic })
	local rip = 0.06
	animate(rip + life, function(a)
		local t = a * (rip + life)
		local grow = easeOut(math.clamp(t / rip, 0, 1))
		local fade = math.clamp((t - rip) / life, 0, 1)
		local l = math.max(len * grow, 0.1)
		local w = thick * (1 - fade * 0.85)
		local mid = from + d * l / 2
		core.Size = Vector3.new(w, w, l)
		core.CFrame = CFrame.lookAt(mid, mid + d)
		shadow.Size = Vector3.new(w * 0.8, w * 0.8, l)
		shadow.CFrame = CFrame.lookAt(mid + gap, mid + gap + d)
		core.Transparency = fade ^ 1.5
		shadow.Transparency = 0.1 + fade * 0.9
		if a >= 1 then
			core:Destroy()
			shadow:Destroy()
		end
	end)
end

-- A four-point star of light (two thin crossed bars), flashing out.
local function glint(at: Vector3, size: number)
	local bars = {}
	for i = 0, 1 do
		bars[i + 1] = part({ Size = Vector3.new(0.08, 0.08, size), Color = PAPER,
			CFrame = CFrame.new(at) * CFrame.Angles(if i == 0 then 0 else math.rad(90), 0, 0) })
	end
	animate(0.25, function(a)
		local k = math.sin(a * math.pi)
		for _, b in ipairs(bars) do
			b.Size = Vector3.new(0.12 * k + 0.01, 0.12 * k + 0.01, size * k + 0.05)
			b.Transparency = 1 - k
			if a >= 1 then b:Destroy() end
		end
	end)
end

-- A random cut passing near `center` (mostly flat-ish, some steep).
local function randomCut(center: Vector3, spread: number, len: number, thick: number, life: number)
	local yaw = math.random() * math.pi * 2
	local pitch = (math.random() - 0.5) * (if math.random() < 0.3 then 2.2 else 0.9)
	local dir = Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), math.sin(yaw) * math.cos(pitch))
	local off = Vector3.new((math.random() - 0.5) * 2, (math.random() - 0.2) * 0.7, (math.random() - 0.5) * 2) * spread
	longSlash(center + off, dir, len * (0.7 + math.random() * 0.6), thick * (0.6 + math.random() * 0.8), life)
end

local function onRealm(msg: any)
	local owner = msg.attacker :: Player
	local pos = msg.pos :: Vector3
	local dur = tonumber(msg.duration) or 4
	local range = tonumber(msg.range) or 24
	local centre = pos + Vector3.new(0, 2.5, 0)
	-- The opening: a fan of cuts all at once.
	for _ = 1, 8 do randomCut(centre, range * 0.25, range * 1.6, 0.35, 0.35) end
	-- Then the storm, for as long as it lasts.
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur - 0.1 do
			if FxBudget.Allow("rogueRealmStorm", 22) then
				randomCut(centre, range * 0.35, range * 1.5, 0.28, 0.3)
			end
			if math.random() < 0.18 then
				glint(centre + Vector3.new((math.random() - 0.5) * range, math.random() * 8, (math.random() - 0.5) * range), 3 + math.random() * 2)
			end
			task.wait(0.06)
		end
	end)
	local char = charOf(owner)
	if char then
		-- The Rogue becomes a shade in the middle of it all.
		setHidden(char, true, if owner == player then 0.45 else 0.6, 0.3)
		if owner ~= player then realmPose(char, dur) end
		task.delay(dur, function()
			if char.Parent and not (hidden[char] and hidden[char].amount == 1) then setHidden(char, false, 0, 0.2) end
		end)
	end
	if owner == player and deps then deps.shake(0.4, 0.4) end
end

-- A strike on one enemy: two long cuts crossing through it.
local function onRealmSlash(msg: any)
	if not FxBudget.Allow("rogueRealmSlash", 14) then return end
	local at = (msg.pos :: Vector3) + Vector3.new(0, 1.2, 0)
	local yaw = math.random() * math.pi * 2
	for i = 0, 1 do
		local y = yaw + (if i == 0 then 0 else math.rad(70 + math.random() * 40))
		local pitch = (math.random() - 0.5) * 0.8
		longSlash(at, Vector3.new(math.cos(y), pitch, math.sin(y)), 16 + math.random() * 8, 0.4, 0.3)
	end
	if FxBudget.Allow("rogueRealmShards", 8) then shards(at, 5, 18, 0.8) end
end

-- The release: a burst of long cuts through the whole area at once, splinters,
-- a white flash.
local function onRealmBurst(msg: any)
	local pos = msg.pos :: Vector3
	local range = tonumber(msg.range) or 24
	local centre = pos + Vector3.new(0, 1.5, 0)
	for i = 1, 20 do
		task.delay((i % 4) * 0.025, function()
			randomCut(centre, range * 0.3, range * 2.2, 0.6, 0.5)
		end)
	end
	for _ = 1, 4 do
		glint(centre + Vector3.new((math.random() - 0.5) * range, math.random() * 6, (math.random() - 0.5) * range), 5)
	end
	shards(centre, 26, 40, 1.4, 1)
	if msg.attacker == player or near(pos, range + 6) then flash(0.35, 0.15) end
	if msg.attacker == player and deps then
		deps.shake(1.2, 0.4)
		deps.fovPunch(10, 0.35)
	end
end

-- ── Others' moments ─────────────────────────────────────────────────────────
-- The combo's cut, drawn the same for you and for others.
local function comboFX(root: BasePart, dir: Vector3, step: number)
	-- (sized to the doubled reach: 18 studs, the stab 22)
	local at = root.Position + dir * 5 + Vector3.new(0, 0.6, 0)
	if step == 1 then
		slashAt(at, dir, 7, -14, 140, 0.8, 0.22)
	elseif step == 2 then
		slashAt(at, dir, 7, 28, 140, 0.8, 0.22, true)
	else
		-- the stab: a white spike thrust out along the aim, splinters at its point
		local from = root.Position + dir * 1.5 + Vector3.new(0, 0.6, 0)
		local back = part({ Size = Vector3.new(0.5, 0.5, 0.2), Color = INK, Material = Enum.Material.SmoothPlastic, CFrame = CFrame.lookAt(from, from + dir) })
		local spike = part({ Size = Vector3.new(0.25, 0.25, 0.2), Color = PAPER, CFrame = CFrame.lookAt(from, from + dir) })
		animate(0.22, function(a)
			local len = 12 * easeOut(math.min(a * 3, 1))
			local cf = CFrame.lookAt(from, from + dir) * CFrame.new(0, 0, -len / 2)
			local thin = 1 - math.max(a - 0.3, 0) / 0.7
			back.Size = Vector3.new(0.5 * thin, 0.5 * thin, len + 0.3)
			spike.Size = Vector3.new(0.25 * thin, 0.25 * thin, len)
			back.CFrame, spike.CFrame = cf, cf
			if a >= 1 then
				back:Destroy()
				spike:Destroy()
			end
		end)
		shards(from + dir * 12, 6, 16, 0.6)
		speedLines(from + dir * 6, dir, 5, 8, 0.6)
	end
end

local function onCombo(msg: any)
	if msg.attacker == player then return end
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if not FxBudget.Allow("rogueCombo", 20) then return end
	swingPose(char, msg.step or 1)
	trailOn(char, 0.18)
	comboFX(root, flat(if typeof(msg.dir) == "Vector3" then msg.dir else root.CFrame.LookVector), msg.step or 1)
end

local function onDash(msg: any)
	if msg.attacker == player then return end -- (drawn the moment we pressed it)
	local char = charOf(msg.attacker)
	if char then
		dashPose(char)
		dashFX(char, msg.from, msg.to, msg.enhanced == true)
	end
end

-- Enhanced: a black ring with a white one inside, and splinters.
local function onEnhanced(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if root then
		floorRing(root.Position - Vector3.new(0, 2.7, 0), 6, 0.35, false)
		floorRing(root.Position - Vector3.new(0, 2.65, 0), 4, 0.3)
		shards(root.Position, 8, 14, 0.7, 1.5)
	end
end

local HANDLERS: { [string]: (any) -> () } = {
	combo = onCombo,
	dagger = onDagger,
	daggerStop = onDaggerStop,
	daggerGone = function(msg) dropDagger(msg.attacker); if msg.attacker == player then myDagger = nil end end,
	step = onStep,
	dash = onDash,
	hidden = onHidden,
	realm = onRealm,
	realmSlash = onRealmSlash,
	realmBurst = onRealmBurst,
	mark = onMark,
	enhanced = onEnhanced,
	energyFull = function(msg)
		local root = rootOf(charOf(msg.attacker))
		if root and msg.attacker == player then
			floorRing(root.Position - Vector3.new(0, 2.7, 0), 5, 0.3)
			shards(root.Position, 6, 10, 0.5, 2)
		end
	end,
}

-- ── HUD: Shadow Energy ──────────────────────────────────────────────────────
local hud: ScreenGui? = nil
local fill: Frame? = nil
local fullLabel: TextLabel? = nil
local stroke: UIStroke? = nil

local function energy(): number
	return tonumber(player:GetAttribute("RG_Energy")) or 0
end

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "RogueEnergy"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -132)
	back.Size = UDim2.fromOffset(220, 10)
	back.BackgroundColor3 = INK
	back.BorderSizePixel = 0
	back.Parent = g
	local s = Instance.new("UIStroke")
	s.Color = PAPER
	s.Thickness = 1.2
	s.Transparency = 0.4
	s.Parent = back
	stroke = s
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(0, 1)
	f.BackgroundColor3 = ASH
	f.BorderSizePixel = 0
	f.Parent = back
	fill = f
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 0, -3)
	lbl.Size = UDim2.fromOffset(260, 20)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Arcade
	lbl.TextSize = 18
	lbl.Text = "SHADOW ENERGY"
	lbl.TextColor3 = Color3.fromRGB(200, 200, 205)
	lbl.TextStrokeColor3 = INK
	lbl.TextStrokeTransparency = 0.2
	lbl.Parent = back
	fullLabel = lbl
end

local function refreshHud()
	if not hud then return end
	hud.Enabled = isRogue() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	local e = energy()
	local full = e >= ENERGY_MAX
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(e / ENERGY_MAX, 0, 1), 1)
		fill.BackgroundColor3 = if full then PAPER else ASH
	end
	if stroke then stroke.Transparency = if full then 0 else 0.4 end
	if fullLabel then
		local text = if full then "ENHANCED: NEXT ABILITY" else "SHADOW ENERGY"
		if fullLabel.Text ~= text then fullLabel.Text = text end
		fullLabel.TextColor3 = if full then PAPER else Color3.fromRGB(200, 200, 205)
	end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
function RogueController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	if now - lastSwing < SWING_INTERVAL / speed then return true end
	localStep = if now - lastSwing > COMBO_RESET then 1 else (localStep % 3) + 1
	lastSwing = now
	local dir = flat(deps.getAim(root))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	swingPose(char, localStep)
	trailOn(char, 0.18)
	comboFX(root, dir, localStep)
	ClassFX.Sound("whoosh", root, 0.5, 1.25 + localStep * 0.06)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function RogueController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

-- E while our dagger is out: Shadow Step to it (no cooldown). Returns true
-- when the press was used up here.
-- You come out of the step in the air above and behind them, flip forward
-- with the blade over your head, cut down through them and land. The flight
-- is drawn on the body's pose only (the root joint's offset): the character
-- itself is already standing on the floor behind them, so physics and
-- control carry straight on. The server's hit is sent at the moment of the cut.
function RogueController.TryRecast(skillIndex: number, char: Model, root: BasePart): boolean
	if skillIndex ~= 1 then return false end
	local d = myDagger
	if not d or os.clock() > d.expires then return false end
	if os.clock() < d.landsAt then return true end -- (still flying)
	myDagger = nil
	local to = d.to
	local face: Vector3? = nil
	local stuck = d.stuck
	local sroot = stuck and stuck.Parent and rootOf(stuck)
	if sroot then
		-- Behind them, facing their back.
		local away = flat(sroot.Position - root.Position)
		to = sroot.Position + away * 3.5
		face = -away
	end
	local from = root.Position
	ghost(char, root.CFrame, "paper", 0.35, Vector3.new(0, 2, 0))
	ink(from - Vector3.new(0, 1.5, 0), 0.8, 1)
	blinkTo(root, to, face)
	root.AssemblyLinearVelocity = Vector3.zero
	local land = root.CFrame
	local look = land.LookVector
	-- (held still for the flip only; never anchored)
	char:SetAttribute("IsSkillCasting", true)
	busyUntil = os.clock() + STEP_AIR
	trailOn(char, STEP_AIR + 0.15)
	flyingSlashPose(char)
	ClassFX.Sound("whoosh", root, 0.6, 1.4)
	if deps then deps.fovPunch(7, 0.25) end
	task.delay(STEP_AIR * 0.62, function()
		-- the cut: one tall white crescent straight down through them
		local at = if sroot and sroot.Parent then sroot.Position + Vector3.new(0, 1, 0) else land.Position + look * 2
		crescent(CFrame.lookAt(at - look * 2.5, at + look) * CFrame.Angles(0, 0, math.rad(90)), 4.2, 150, 0.85, 0.32, 0.05)
		shards(at, 12, 24, 1)
		Network.GetRemoteEvent(Network.Remotes.UseSkill):FireServer({
			skillIndex = 1, origin = root.Position, direction = look,
		})
	end)
	task.delay(STEP_AIR, function()
		if root.Parent then
			floorRing(root.Position - Vector3.new(0, 2.8, 0), 4.5, 0.3)
			ink(root.Position - Vector3.new(0, 2, 0), 0.6, 0.5)
			if deps then deps.shake(0.45, 0.18) end
		end
		if char.Parent then char:SetAttribute("IsSkillCasting", false) end
	end)
	return true
end

function RogueController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local dir = flat(aimDir)
	local enhanced = energy() >= ENERGY_MAX
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	if skillIndex == 1 then
		-- Shadow Dagger: a coiled overhand throw (the dagger itself flies on RogueFX).
		char:SetAttribute("AllowSkillMovement", true)
		throwPose(char)
		trailOn(char, 0.2)
		ClassFX.Sound("whoosh", root, 0.6, 1.5)
		releaseAfter(char, 0.2)
	elseif skillIndex == 2 then
		-- Dash: instant.
		char:SetAttribute("AllowSkillMovement", false)
		local dist = (config.dashDistance or 22) * (if enhanced then 1.5 else 1)
		local from = root.Position
		if hum then hum.AutoRotate = false end
		blinkTo(root, from + dir * dist)
		dashFX(char, from, root.Position, enhanced)
		dashPose(char)
		trailOn(char, 0.3)
		ClassFX.Sound("whoosh", root, 0.7, 1.15)
		if deps then
			deps.fovPunch(if enhanced then 9 else 6, 0.22)
			deps.shake(0.25, 0.15)
		end
		busyUntil = os.clock() + 0.1
		releaseAfter(char, 0.12)
		task.delay(0.15, function() if hum then hum.AutoRotate = true end end)
	elseif skillIndex == 3 then
		-- Invisibility: a crouch into the ink (the fade comes on RogueFX).
		char:SetAttribute("AllowSkillMovement", true)
		vanishPose(char)
		releaseAfter(char, 0.25)
	elseif skillIndex == 4 then
		-- Shadow Realm: rise, arms spread, and hang there till it bursts.
		char:SetAttribute("AllowSkillMovement", false)
		local dur = (config.duration or 4) * (if enhanced then 1.5 else 1)
		busyUntil = os.clock() + dur
		realmPose(char, dur)
		root.Anchored = true
		local base = root.CFrame
		-- (up, then a slow turn while adrift)
		local spun = 0
		animate(dur - 0.3, function(a, dt)
			if not root.Anchored then return end
			spun += dt
			root.CFrame = (base + Vector3.new(0, 3.5 * easeOut(math.min(spun / 0.5, 1)) + math.sin(spun * 2.4) * 0.3, 0))
				* CFrame.Angles(0, spun * 0.6, 0)
		end)
		task.delay(dur, function()
			if root.Parent then
				root.CFrame = base
				root.Anchored = false
			end
		end)
		releaseAfter(char, dur)
	end
end

function RogueController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	RunService.RenderStepped:Connect(function(dt)
		stepAnims(dt)
		stepMarks()
	end)
	CastPoses.addPostHook(ninjaRunStep)
	player:GetAttributeChangedSignal("RG_Energy"):Connect(refreshHud)
	player:GetAttributeChangedSignal("SelectedClass"):Connect(refreshHud)
	player:GetAttributeChangedSignal("InLobby"):Connect(refreshHud)
	player:GetAttributeChangedSignal("SettingsOpen"):Connect(refreshHud)
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localStep = 0
		myDagger = nil
	end)
	Network.GetRemoteEvent(Network.Remotes.RogueFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[RogueController]", msg.kind, err) end
		end
	end)
end

return RogueController
