--!strict
--[[
	MartialController.luau
	Client side of the Martial Artist (server: MartialServer), after the class
	sheet: crimson energy and black ink, a crimson sash streaming behind him,
	lightning for the uppercut.

	  • Your own strikes, charges and leaps start at once on your screen; the
	    server decides the hits and sends every Martial Artist's moments to
	    everyone over MartialFX.
	  • Focus Strike is held: the charge runs while the key is down
	    (MartialController.Release, from SkillController, when it comes up)
	    and the release goes to the server over MartialInput.
	  • The sash tails sway and stream as he moves, and his fists leave
	    streaks of red when they strike (every Martial Artist, every client).
	  • The Qi Charge orbs over the skill bar fill one by one (MA_Charge; full
	    = the next ability is EMPOWERED, and his fists burn).

	The effects (one RenderStepped loop runs them all, `animate`):
	  ink           strokes of black ink (beams drawn on and drying away),
	                ink curling in to a fist, ink flung out in drops that
	                splatter the floor in pools, the pack's splashes in black
	  bolt          a jagged bolt of lightning (the uppercut, red sparks off
	                the Focus Strike and the Hadouken)
	  dragon        a dragon of crimson Qi (the palm strike, Ground Slam)
	  the ball      after the pack's Big/Ball-01 (its fire, ash, embers): the Hadouken
	  the pack      ReplicatedStorage.VFXPack effects recoloured: impacts,
	                explosions, cracks, smoke, lightning, ink splashes
	Per-hit effects go through FxBudget.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local PackFX = require(script.Parent:WaitForChild("PackFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local IsometricCamera: any = nil
pcall(function() IsometricCamera = require(script.Parent:WaitForChild("IsometricCamera")) end)

local player = Players.LocalPlayer

local MartialController = {}

-- ── Tuning (matches MartialServer) ──────────────────────────────────────────
local COMBO_INTERVAL = 0.3
local COMBO_RESET = 1.0
local CHARGE_MAX = 100
-- Focus Strike: fully charged after `full` seconds (Empowered: `empFull`),
-- off on its own after `hold`; the fist lands `hit` after the release, the
-- lunge behind it growing with the charge.
local FOCUS = { full = 1.1, empFull = 0.55, hold = 2.4, hit = 0.08, lunge = 1.5, fullLunge = 6, fullReach = 11, splash = 8,
	walk = 5 } -- (he can creep about while it charges: walk speed, normal is 16)
-- Electric Uppercut (matches MartialServer): the drop into a crouch, the
-- crouch dash in (`reach` studs), then, planted, the fist swung up from the
-- knee (`swing`: it lands `hit` in), carried on up (`rise`), a beat held,
-- back to guard. His feet stay on the floor throughout.
-- (`range`: the dash's longest; it stops `stopShort` before the first enemy
-- in a lane `lane` wide, like the server's)
local UPPER = { crouch = 0.05, dash = 0.14, swing = 0.08, rise = 0.08, hang = 0.12, fall = 0.15, hit = 0.27, total = 0.62, reach = 7,
	range = 24, lane = 3.5, stopShort = 2.5 }
-- Ground Slam: a leap straight up (rise), a beat hanging at the top
-- (dash), then a dive in a straight line down onto the spot (fall).
local ASCENT = { rise = 0.3, dash = 0.08, fall = 0.22 }
local ASCENT_HEIGHT = 14
-- Crimson Hadouken (matches MartialServer): the charge (the ult's
-- cinematic), then the thrust, held a beat; the sphere leaves the palms at
-- `v0` and surges up to the server's speed (`ramp`: how quickly).
local HADO = { charge = 1.3, hold = 0.45, v0 = 18, ramp = 0.3 }
-- The chain (matches MartialServer): how far each strike reaches (its blast
-- of air is drawn that far), how far it pushes him in behind it, and how
-- long his feet stay planted for it (at 1× attack speed).
local COMBO_RANGE = { 10, 10, 11, 10, 8.5, 10, 0 }
local LUNGE = { 1.2, 1.2, 0.8, 0.6, 1.2, 1.8, 2.4 }
local PLANTED = { 0.24, 0.24, 0.28, 0.3, 0.24, 0.3, 0.5 }
local PALM_RADIUS, PALM_AT, FINISH_RADIUS = 7.5, 5, 9.5
local COMBO_STEPS = 7
local FINISH_LAND = 0.16 -- the flying knee hits the floor (matches MartialServer)
local RECOVER = 0.5      -- the finisher, then back to guard

-- The palette (the class sheet): crimson energy and black ink; the
-- uppercut's lightning blue-white.
local CRIMSON = Color3.fromRGB(226, 26, 46)
local HOT = Color3.fromRGB(255, 108, 104)  -- the white-hot heart of the energy
local BLOOD = Color3.fromRGB(122, 6, 18)   -- its deep edges
local INK = Color3.fromRGB(10, 8, 12)
local WHITE = Color3.new(1, 1, 1)
local ROCK = Color3.fromRGB(58, 52, 50)
local VOLT = Color3.fromRGB(92, 136, 255)  -- lightning
local ARC = Color3.fromRGB(214, 228, 255)  -- its white core

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_WISPS = "rbxassetid://9541055154"  -- (the pack's beam textures: wavy wisps of flame,
local TEX_FLICKER = "rbxassetid://10365550877" -- and flickering streaks of energy)
local TEX_INK = "rbxassetid://16955854038"   -- (the pack's ash: black brush strokes, a 4x4 flipbook)
local TEX_FLAME = "rbxassetid://13818306392" -- (the pack's fire, a 4x4 flipbook)

type Deps = { shake: (number, number) -> (), fovPunch: (number, number) -> (), getAim: (BasePart) -> Vector3 }
local deps: Deps

local lastSwing = 0
local step = 0
local busyUntil = 0

local function isMartial(p: Player?): boolean
	return (p or player):GetAttribute("SelectedClass") == "martial_artist"
end

local function charOf(p: any): Model?
	return if typeof(p) == "Instance" and p:IsA("Player") then p.Character else nil
end

local function rootOf(char: Model?): BasePart?
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function near(pos: Vector3, reach: number): boolean
	local r = rootOf(player.Character)
	return r ~= nil and (r.Position - pos).Magnitude < reach
end

local function part(props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = ClassFX.Folder()
	return p
end

-- An invisible anchored point to hang trails and emitters on.
local function carrier(cf: CFrame): BasePart
	return part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = cf })
end

-- ── One loop for every running effect ───────────────────────────────────────
-- `fn(a, dt)` gets 0..1 over `dur` (called a last time with a = 1); it can
-- return true to finish early.
local running: { { t0: number, dur: number, fn: (number, number) -> boolean? } } = {}
local function animate(dur: number, fn: (number, number) -> boolean?)
	table.insert(running, { t0 = os.clock(), dur = math.max(dur, 0.01), fn = fn })
end
local function stepAnims(dt: number)
	local now = os.clock()
	for i = #running, 1, -1 do
		local r = running[i]
		local a = math.min((now - r.t0) / r.dur, 1)
		local ok, res = pcall(r.fn, a, dt)
		if not ok then warn("[MartialController] fx:", res) end
		if a >= 1 or not ok or res == true then table.remove(running, i) end
	end
end

local function easeOut(a: number): number return 1 - (1 - a) ^ 3 end
local function easeIn(a: number): number return a * a end

local function groundY(pos: Vector3): number
	return FireFX.GroundY(pos)
end

local function onGround(pos: Vector3): Vector3
	return Vector3.new(pos.X, groundY(pos), pos.Z)
end

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- ── Small pieces of light ───────────────────────────────────────────────────
local function floorRing(pos: Vector3, radius: number, life: number, color: Color3?, width: number?)
	SwordFX.Arc({ cf = CFrame.new(pos + Vector3.new(0, 0.15, 0)), radius = radius * 0.6, arc = 359, width = width or 0.9,
		color = color or CRIMSON, life = life, draw = 0.001, grow = 0.7, core = HOT })
end

local function flare(pos: Vector3, size: number, life: number, color: Color3?)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.3, CFrame = CFrame.new(pos), Color = color or HOT, Transparency = 0.1 })
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size, Transparency = 1, Color = BLOOD }):Play()
	Debris:AddItem(b, life + 0.05)
end

-- A shell of energy swelling out (the 3D shockwave).
local function shell(pos: Vector3, from: number, to: number, life: number, color: Color3?)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * from, CFrame = CFrame.new(pos), Color = color or CRIMSON,
		Material = Enum.Material.ForceField })
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * to, Transparency = 1 }):Play()
	Debris:AddItem(b, life + 0.05)
end

local function sparks(pos: Vector3, count: number, speed: number, color: Color3?)
	ClassFX.Burst(pos, color or CRIMSON, count, speed, ClassFX.TEX_SPARK, 0.35, 0.5)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function nseq(...: number): NumberSequence
	local v = { ... }
	if #v == 2 then return NumberSequence.new(v[1], v[2]) end
	local kps = {}
	for i = 1, #v, 2 do table.insert(kps, NumberSequenceKeypoint.new(v[i], v[i + 1])) end
	return NumberSequence.new(kps)
end

-- A ribbon of light following `on` as it moves (a Trail between two points
-- `width` apart across it, always turned to the camera).
local function ribbon(on: BasePart, at: Vector3, width: number, life: number, colors: ColorSequence, transp: NumberSequence,
	taper: NumberSequence?, texture: string?, texLength: number?, emission: number?): Trail
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = at + Vector3.new(0, width / 2, 0), at - Vector3.new(0, width / 2, 0)
	a0.Parent, a1.Parent = on, on
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = colors
	t.Transparency = transp
	t.LightEmission = emission or 1
	t.LightInfluence = 0
	t.FaceCamera = true
	t.Lifetime = life
	t.MinLength = 0.02
	if taper then t.WidthScale = taper end
	if texture then
		-- (tiled along the path in the world, so the body flows through it)
		t.Texture = texture
		t.TextureMode = Enum.TextureMode.Wrap
		t.TextureLength = texLength or 4
	end
	t.Parent = on
	return t
end

-- A slash of Qi from a to b: a streak that flares and fades.
local function streak(a: Vector3, b: Vector3, width: number, life: number, color: Color3?)
	SwordFX.Streak(a, b, width, color or CRIMSON, life, nil, HOT)
end

-- The world dimmed and reddened a little (the Crimson Hadouken).
local function tint(seconds: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MartialHado"
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.4), { Brightness = -0.12, Contrast = 0.2, Saturation = 0.1,
		TintColor = Color3.fromRGB(255, 206, 206) }):Play()
	task.delay(seconds, function()
		TweenService:Create(cc, TweenInfo.new(0.6), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }):Play()
		Debris:AddItem(cc, 0.65)
	end)
end

local function flash(t: number, from: number?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MartialFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = HOT
	f.BackgroundTransparency = from or 0.3
	f.BorderSizePixel = 0
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, t + 0.05)
end

-- A manga impact frame: the world thrown into stark, near-colourless
-- contrast for an instant (yours only: the full-charge splash).
local function impactFrame(t: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MartialImpact"
	cc.Saturation = -0.75
	cc.Contrast = 0.55
	cc.Brightness = 0.04
	cc.TintColor = Color3.fromRGB(255, 226, 226)
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, t * 0.6),
		{ Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE }):Play()
	Debris:AddItem(cc, t * 1.6 + 0.05)
end

-- Where a fist is right now (the end of the arm, as posed).
local function fistOf(char: Model, side: string): Vector3?
	local arm = char:FindFirstChild(side) :: BasePart?
	return if arm then (arm.CFrame * CFrame.new(0, -1.15, 0)).Position else nil
end

-- Between his two hands (the Hadouken's sphere).
local function handsOf(char: Model): Vector3?
	local r, l = fistOf(char, "Right Arm"), fistOf(char, "Left Arm")
	return if r and l then (r + l) / 2 else nil
end

-- A bolt of lightning from `a` to `b`: a jagged line (wildest in the middle)
-- of `color` round a white core, gone in a flicker.
local function bolt(a: Vector3, b: Vector3, width: number, life: number, color: Color3, kinks: number?)
	local d = b - a
	local len = d.Magnitude
	if len < 0.1 then return end
	local u = d / len
	local s1 = u:Cross(if math.abs(u.Y) < 0.9 then Vector3.yAxis else Vector3.xAxis).Unit
	local s2 = u:Cross(s1)
	local n = kinks or math.clamp(math.floor(len / 1.5), 3, 9)
	local pts = { a }
	for i = 1, n - 1 do
		local t = i / n
		local amp = len * 0.14 * math.sin(t * math.pi)
		table.insert(pts, a + d * t + s1 * (math.random() * 2 - 1) * amp + s2 * (math.random() * 2 - 1) * amp)
	end
	table.insert(pts, b)
	for i = 1, #pts - 1 do
		local p, q = pts[i], pts[i + 1]
		local cf = CFrame.lookAt((p + q) / 2, q)
		local seg = (q - p).Magnitude
		local glow = part({ Size = Vector3.new(width, width, seg + width * 0.6), CFrame = cf, Color = color, Transparency = 0.2 })
		local core = part({ Size = Vector3.new(width * 0.35, width * 0.35, seg + width * 0.3), CFrame = cf, Color = WHITE })
		TweenService:Create(glow, TweenInfo.new(life, Enum.EasingStyle.Quad), { Transparency = 1, Size = Vector3.new(width * 0.3, width * 0.3, glow.Size.Z) }):Play()
		TweenService:Create(core, TweenInfo.new(life * 0.8), { Transparency = 1 }):Play()
		Debris:AddItem(glow, life + 0.05)
		Debris:AddItem(core, life + 0.05)
	end
end

-- Lightning running over a spot for `seconds`; `launched`: following an
-- enemy thrown up by the uppercut (its arc up and back down).
local function crackle(at: Vector3, seconds: number, launched: boolean)
	local t0 = os.clock()
	local nextArc = 0
	animate(seconds, function()
		local t = os.clock() - t0
		if t >= nextArc then
			nextArc = t + 0.06
			local h = if launched then math.max(0, 52 * t - 98 * t * t) else 0
			local c = at + Vector3.new(0, h, 0)
			local function rnd(): Vector3
				return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 3
			end
			bolt(c + rnd(), c + rnd(), 0.08, 0.06, VOLT, 3)
		end
		return nil
	end)
end

-- Shards of light bursting up out of the floor round `at`, leaning out (the
-- uppercut's launch).
local function shards(at: Vector3, count: number, height: number, color: Color3)
	local g = onGround(at)
	local list: { { p: BasePart, base: Vector3, up: Vector3, h: number, w: number } } = {}
	for i = 1, count do
		local a = i / count * math.pi * 2 + math.random() * 0.4
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local lean = math.rad(14 + math.random() * 30)
		local up = (Vector3.yAxis * math.cos(lean) + out * math.sin(lean)).Unit
		local w = 0.25 + math.random() * 0.25
		local p = part({ Size = Vector3.new(w, w, 0.1), Color = if i % 3 == 0 then WHITE else color, Transparency = 0.1,
			CFrame = CFrame.lookAt(g, g + up) })
		table.insert(list, { p = p, base = g + out * (0.5 + math.random() * 1.4), up = up, h = height * (0.5 + math.random() * 0.6), w = w })
	end
	-- (they shoot up, then thin and fade)
	animate(0.32, function(k)
		local grow = easeOut(math.min(k / 0.35, 1))
		local fade = math.max(0, (k - 0.35) / 0.65)
		for _, s in ipairs(list) do
			local len = math.max(0.1, s.h * grow)
			local w = s.w * (1 - 0.7 * fade)
			s.p.Size = Vector3.new(w, w, len)
			s.p.CFrame = CFrame.lookAt(s.base + s.up * (len / 2), s.base + s.up * len)
			s.p.Transparency = 0.1 + 0.9 * fade
			if k >= 1 then s.p:Destroy() end
		end
		return nil
	end)
end

-- A stroke of black ink from `a` to `b`, drawn on over `draw` seconds and
-- bent `bend` studs to one side: thin where the brush comes in, pressed down
-- thick at the end; then it dries away over `life`.
local function inkStroke(a: Vector3, b: Vector3, width: number, life: number, bend: number?, draw: number?)
	local d = b - a
	if d.Magnitude < 0.1 then return end
	local side = d:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.05 then side.Unit else Vector3.xAxis
	local holder = carrier(CFrame.new(a))
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = holder, holder
	a0.WorldCFrame = CFrame.fromMatrix(a, side, d.Unit)
	a1.WorldCFrame = CFrame.fromMatrix(a, side, d.Unit)
	local bm = Instance.new("Beam")
	bm.Attachment0, bm.Attachment1 = a0, a1
	bm.Color = ColorSequence.new(INK)
	bm.LightEmission, bm.LightInfluence = 0, 0
	bm.FaceCamera = true
	bm.Segments = 12
	bm.Width0, bm.Width1 = width * 0.2, width
	bm.CurveSize0, bm.CurveSize1 = bend or 0, -(bend or 0) * 0.5
	bm.Transparency = nseq(0, 0.3, 0.8, 0, 1, 0.05)
	bm.Parent = holder
	local inT = draw or 0.06
	animate(inT + life, function(k)
		local t = k * (inT + life)
		a1.WorldCFrame = CFrame.fromMatrix(a:Lerp(b, easeOut(math.min(t / inT, 1))), side, d.Unit)
		if t > inT then
			local f = (t - inT) / life
			bm.Width0 = width * 0.2 * (1 - f)
			bm.Width1 = width * (1 - f * 0.6)
			bm.Transparency = nseq(0, 0.3 + 0.7 * f, 0.8, f, 1, 0.05 + 0.95 * f)
		end
		if k >= 1 then holder:Destroy() end
		return nil
	end)
end

-- One stroke of ink curling in to a fist: a point spiralling in from `r`
-- studs out round it, in a random plane, trailing ink. `kind` "energy": a
-- streak of crimson energy instead; "air": a streak of wind, in a flatter
-- plane (the air drawn in round him).
local function inkCurl(getFist: () -> Vector3?, r: number, width: number, dur: number, kind: string?)
	local f0 = getFist()
	if not f0 then return end
	local spin = if math.random() < 0.5 then -1 else 1
	local start = math.random() * math.pi * 2
	local tilt = if kind == "air" then 0.35 else 1
	local plane = CFrame.Angles((math.random() * 2 - 1) * tilt, math.random() * math.pi * 2, (math.random() * 2 - 1) * tilt)
	local function at(f: Vector3, k: number): Vector3
		local rr = r * (1 - easeIn(k)) + 0.15
		local ang = start + spin * k * math.pi * 2.4
		return f + plane:VectorToWorldSpace(Vector3.new(math.cos(ang) * rr, 0, math.sin(ang) * rr))
	end
	local c = carrier(CFrame.new(at(f0, 0)))
	local tr = if kind == "energy"
		then ribbon(c, Vector3.zero, width, 0.3, ColorSequence.new(HOT, CRIMSON), nseq(0, 0.1, 0.7, 0.4, 1, 1), nseq(0, 1, 1, 0), TEX_FLICKER, 3, 1)
		elseif kind == "air"
		then ribbon(c, Vector3.zero, width, 0.35, ColorSequence.new(WHITE), nseq(0, 0.45, 0.6, 0.7, 1, 1), nseq(0, 1, 1, 0), TEX_FLICKER, 4, 1)
		else ribbon(c, Vector3.zero, width, 0.2, ColorSequence.new(INK), nseq(0, 0.05, 0.7, 0.25, 1, 1), nseq(0, 1, 1, 0), nil, nil, 0)
	animate(dur, function(k)
		local f = getFist()
		if not f then
			c:Destroy()
			return true
		end
		c.CFrame = CFrame.new(at(f, k))
		if k >= 1 then
			tr.Enabled = false
			Debris:AddItem(c, 0.25)
		end
		return nil
	end)
end

-- A drop or pool of ink: a black ellipsoid `size` big.
local function blob(size: Vector3, cf: CFrame): BasePart
	local p = part({ Size = size, CFrame = cf, Color = INK, Material = Enum.Material.SmoothPlastic })
	local m = Instance.new("SpecialMesh")
	m.MeshType = Enum.MeshType.Sphere
	m.Parent = p
	return p
end

-- Ink flung out from `at` in `count` drops (mostly along `dir`), stretched
-- as they fly; where they hit the floor they splat into pools that dry away.
local function inkDrops(at: Vector3, count: number, radius: number, dir: Vector3)
	local gy = groundY(at)
	local drops: { { p: BasePart, v: Vector3, s: number } } = {}
	for _ = 1, count do
		local a = math.random() * math.pi * 2
		local out = (Vector3.new(math.cos(a), 0, math.sin(a)) + dir * 0.7).Unit
		local s = 0.3 + math.random() * 0.45
		table.insert(drops, { p = blob(Vector3.one * s, CFrame.new(at)), s = s,
			v = out * radius * (1.3 + math.random() * 1.5) + Vector3.new(0, 10 + math.random() * 16, 0) })
	end
	animate(1.4, function(k, dt)
		for _, d in ipairs(drops) do
			if not d.p.Parent then continue end
			d.v += Vector3.new(0, -90 * dt, 0)
			local pos = d.p.Position + d.v * dt
			if pos.Y <= gy + 0.05 then
				-- splat: a pool of ink on the floor, drying away
				local w = d.s * (2.6 + math.random() * 1.6)
				local pool = blob(Vector3.new(w, 0.06, w * (0.6 + math.random() * 0.5)),
					CFrame.new(pos.X, gy + 0.04, pos.Z) * CFrame.Angles(0, math.random() * math.pi * 2, 0))
				TweenService:Create(pool, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9), { Transparency = 1 }):Play()
				Debris:AddItem(pool, 1.9)
				d.p:Destroy()
			else
				d.p.Size = Vector3.new(d.s, d.s, d.s * (1 + d.v.Magnitude * 0.035))
				d.p.CFrame = CFrame.lookAt(pos, pos + d.v)
			end
		end
		if k >= 1 then
			for _, d in ipairs(drops) do
				if d.p.Parent then d.p:Destroy() end
			end
		end
		return nil
	end)
end

-- Rubble torn up off the floor round `center`: chunks of rock that rise and
-- hang turning in the air (the Crimson Hadouken's charge) until thrown.
type Rubble = { parts: { BasePart }, home: { Vector3 }, spin: { CFrame }, throw: (Vector3) -> (), drop: () -> () }
local function rubble(center: Vector3, count: number, radius: number, rise: number): Rubble
	local parts, home, spins = {}, {}, {}
	for k = 1, count do
		local a = k / count * math.pi * 2 + math.random() * 0.5
		local r = radius * (0.45 + math.random() * 0.55)
		local g = onGround(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		local s = 0.5 + math.random() * 1.2
		local p = part({ Size = Vector3.new(s, s * (0.6 + math.random() * 0.5), s * (0.7 + math.random() * 0.4)), Color = ROCK,
			Material = Enum.Material.Slate, CFrame = CFrame.new(g) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		table.insert(parts, p)
		table.insert(home, g + Vector3.new(0, 1.2 + math.random() * rise, 0))
		table.insert(spins, CFrame.Angles(math.random() * 0.03, math.random() * 0.04, math.random() * 0.03))
	end
	local state = "rise"
	local vel: { Vector3 } = {}
	local t0 = os.clock()
	animate(8, function(a, dt)
		if state == "gone" then return true end
		local t = os.clock() - t0
		for i, p in ipairs(parts) do
			if not p.Parent then continue end
			if state == "rise" then
				local u = math.min(t / 0.9, 1)
				local target = home[i] + Vector3.new(0, math.sin(t * 2 + i) * 0.25, 0)
				p.CFrame = (CFrame.new(p.Position:Lerp(target, math.min(dt * 3 * (0.4 + u), 1))) * p.CFrame.Rotation) * spins[i]
			else
				vel[i] += Vector3.new(0, -70 * dt, 0)
				p.CFrame = CFrame.new(p.Position + vel[i] * dt) * p.CFrame.Rotation * spins[i] * spins[i]
			end
		end
		if a >= 1 then
			for _, p in ipairs(parts) do p:Destroy() end
		end
		return nil
	end)
	local function fade()
		for _, p in ipairs(parts) do
			TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			Debris:AddItem(p, 0.55)
		end
		task.delay(0.6, function() state = "gone" end)
	end
	return {
		parts = parts,
		home = home,
		spin = spins,
		-- thrown along `dir`, scattering
		throw = function(dir: Vector3)
			state = "thrown"
			for i in ipairs(parts) do
				vel[i] = dir * (30 + math.random() * 30) + Vector3.new((math.random() - 0.5) * 20, 18 + math.random() * 22, (math.random() - 0.5) * 20)
			end
			task.delay(1.1, fade)
		end,
		drop = function()
			state = "thrown"
			for i in ipairs(parts) do vel[i] = Vector3.new(0, -2, 0) end
			task.delay(0.6, fade)
		end,
	}
end

-- ── The dragon ──────────────────────────────────────────────────────────────
-- A Chinese dragon of crimson Qi, `scale` big. Its body is flame: layered
-- ribbons of light that follow the path its head takes (as long as `life`
-- seconds of that path), two strands spiralling round them, fire pouring off
-- the head and lying along the path; plates down its spine, a crest of fins
-- and two pairs of claws ride the same path. Move it with move(pos, look)
-- every frame. set(alpha) fades it, jaw(k) opens the mouth (0..1),
-- destroy() clears it away (what it left on the path burns out on its own).
type Dragon = {
	move: (Vector3, Vector3) -> (),
	set: (number) -> (),
	jaw: (number) -> (),
	destroy: () -> (),
	head: () -> CFrame,
}

local HEAD = 1.55 -- (the head, big against the body as on the sheet)

local function newDragon(scale: number, start: Vector3, look: Vector3, life: number): Dragon
	local s = scale
	local hs = scale * HEAD
	local parts: { BasePart } = {}
	local base: { number } = {} -- each part's own transparency at full alpha
	local function add(p: BasePart, tr: number): BasePart
		table.insert(parts, p)
		table.insert(base, tr)
		p.Transparency = 1
		return p
	end
	-- The head (in its own frame, looking down -Z).
	local headParts: { BasePart } = {}
	local headRel: { CFrame } = {}
	local jawParts: { BasePart } = {}
	local jawRel: { CFrame } = {} -- relative to the hinge
	local function piece(size: Vector3, rel: CFrame, color: Color3, tr: number, onJaw: boolean?)
		local p = add(part({ Size = size * hs, Color = color }), tr)
		local cf = CFrame.new(rel.Position * hs) * rel.Rotation
		if onJaw then
			table.insert(jawParts, p)
			table.insert(jawRel, cf)
		else
			table.insert(headParts, p)
			table.insert(headRel, cf)
		end
	end
	local R = math.rad
	-- (the head in a deeper crimson, so it doesn't bloom into a blob:
	-- the bright ridges, horns, eyes and teeth stand out against it)
	local HIDE = Color3.fromRGB(196, 22, 40)
	local MOUTH = Color3.fromRGB(70, 4, 10)
	piece(Vector3.new(1.3, 1.0, 1.5), CFrame.new(0, 0.05, 0.1), HIDE, 0.02)                                       -- skull
	piece(Vector3.new(0.95, 0.5, 1.4), CFrame.new(0, -0.05, -1.25), HIDE, 0.02)                                   -- snout
	piece(Vector3.new(0.5, 0.16, 1.35), CFrame.new(0, 0.24, -1.2), HOT, 0.05)                                  -- the ridge of the nose
	piece(Vector3.new(0.75, 0.36, 0.26), CFrame.new(0, 0.04, -1.98), HOT, 0.02)                                -- nose pad
	for _, sx in ipairs({ -1, 1 }) do
		piece(Vector3.new(0.38, 0.16, 0.75), CFrame.new(sx * 0.42, 0.55, -0.38) * CFrame.Angles(R(-14), 0, R(sx * -16)), HOT, 0.02) -- brows
		piece(Vector3.new(0.3, 0.14, 0.26), CFrame.new(sx * 0.48, 0.3, -0.52), WHITE, 0)                         -- eyes
		piece(Vector3.new(0.18, 0.18, 1.9), CFrame.new(sx * 0.38, 0.62, 0.8) * CFrame.Angles(R(-28), R(sx * 14), 0), HOT, 0.02) -- horns
		piece(Vector3.new(0.12, 0.12, 0.8), CFrame.new(sx * 0.5, 0.98, 0.72) * CFrame.Angles(R(-62), R(sx * 26), 0), HOT, 0.02)  -- their branches
		for k = 0, 2 do                                                                                           -- cheek frills
			piece(Vector3.new(0.07, 0.7 - k * 0.12, 0.3), CFrame.new(sx * 0.68, -0.05, 0.15 + k * 0.22)
				* CFrame.Angles(R(-25 - k * 12), 0, R(sx * -(55 + k * 18))) * CFrame.new(0, 0.3, 0), CRIMSON, 0.12)
		end
		for k = 0, 2 do                                                                                           -- upper teeth
			piece(Vector3.new(0.08, 0.24, 0.08), CFrame.new(sx * (0.28 + k * 0.06), -0.36, -1.82 + k * 0.28), WHITE, 0)
		end
		for k = 0, 1 do                                                                                           -- lower teeth
			piece(Vector3.new(0.08, 0.2, 0.08), CFrame.new(sx * (0.26 + k * 0.06), 0.18, -1.3 + k * 0.3), WHITE, 0, true)
		end
	end
	piece(Vector3.new(0.88, 0.22, 1.45), CFrame.new(0, 0, -0.75), HIDE, 0.02, true)                                -- lower jaw
	piece(Vector3.new(0.6, 0.1, 1.25), CFrame.new(0, 0.12, -0.75), MOUTH, 0, true)                                -- inside the mouth
	piece(Vector3.new(0.7, 0.08, 1.1), CFrame.new(0, -0.3, -1.25), MOUTH, 0)                                      -- the roof of it
	local HINGE = CFrame.new(0, -0.32 * hs, -0.25 * hs)
	local jawOpen = 0.4

	-- The spine: plates, a crest of fins, two pairs of claws, riding the
	-- path the head has taken (by time, so they match the ribbons).
	local PLATES = 11
	local plates: { BasePart } = {}
	local fins: { BasePart } = {}
	local claws: { BasePart } = {}
	local clawAt: { number } = {}  -- which plate each claw rides
	local clawRel: { CFrame } = {}
	for k = 1, PLATES do
		local u = k / (PLATES + 1)
		local w = s * (0.85 - 0.55 * u)
		table.insert(plates, add(part({ Size = Vector3.new(w * 0.8, w * 0.8, 0.14 * s), Color = Color3.fromRGB(196, 22, 40):Lerp(BLOOD, u) }), 0.5 + u * 0.35))
		if k % 2 == 1 then
			-- (a crest standing up out of the flame)
			table.insert(fins, add(part({ Size = Vector3.new(0.07 * s, w * 1.3, w * 0.9), Color = HOT }), 0.1 + u * 0.45))
		end
	end
	for _, at in ipairs({ 3, 7 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local w = s * (0.85 - 0.55 * at / (PLATES + 1))
			-- the leg, reaching down out of the flame, then three talons splayed
			table.insert(claws, add(part({ Size = Vector3.new(0.18, 1.3, 0.18) * s, Color = CRIMSON }), 0.05))
			table.insert(clawAt, at)
			table.insert(clawRel, CFrame.new(sx * w * 0.7, -w * 0.4, 0) * CFrame.Angles(R(-35), 0, R(sx * 32)) * CFrame.new(0, -0.65 * s, 0))
			for t = -1, 1 do
				table.insert(claws, add(part({ Size = Vector3.new(0.09, 0.09, 0.6) * s, Color = WHITE }), 0))
				table.insert(clawAt, at)
				table.insert(clawRel, CFrame.new(sx * (w * 0.7 + 0.72 * s), -w * 0.4 - 1.0 * s, -0.55 * s) * CFrame.Angles(R(25), R(t * 32), 0)
					* CFrame.new(0, 0, -0.25 * s))
			end
		end
	end

	-- The body of flame: ribbons trailing the head.
	local core = headParts[1]
	local behind = Vector3.new(0, 0, 0.7 * hs)
	local trails: { Trail } = {}
	local trailBase: { NumberSequence } = {}
	local function body(t: Trail)
		table.insert(trails, t)
		table.insert(trailBase, t.Transparency)
	end
	-- (a deep orange under-layer that keeps it saturated, then the flame
	-- itself, wisps flowing through it, then flickering energy, then a thin
	-- bright line down the middle)
	body(ribbon(core, behind, 2.3 * s, life, ColorSequence.new(BLOOD, Color3.fromRGB(70, 4, 12)), nseq(0, 0.45, 0.7, 0.65, 1, 1),
		nseq(0, 1, 0.7, 0.8, 1, 0.2), nil, nil, 0.25))
	body(ribbon(core, behind, 1.75 * s, life, ColorSequence.new({ ColorSequenceKeypoint.new(0, HOT), ColorSequenceKeypoint.new(0.5, CRIMSON),
		ColorSequenceKeypoint.new(1, BLOOD) }), nseq(0, 0.05, 0.75, 0.35, 1, 1), nseq(0, 1, 0.8, 0.7, 1, 0.12), TEX_WISPS, 5 * s, 0.85))
	body(ribbon(core, behind, 1.2 * s, life * 0.9, ColorSequence.new(HOT, CRIMSON), nseq(0, 0.25, 1, 1), nseq(0, 1, 1, 0.15), TEX_FLICKER, 3 * s, 1))
	body(ribbon(core, behind, 0.22 * s, life * 0.8, ColorSequence.new(WHITE, HOT), nseq(0, 0.3, 1, 1), nseq(0, 1, 1, 0.2)))
	-- two strands spiralling round the body (carried round the head's axis)
	local strands: { BasePart } = {}
	for _ = 1, 2 do
		local c = carrier(CFrame.new(start))
		table.insert(strands, c)
		body(ribbon(c, Vector3.zero, 0.26 * s, life * 0.9, ColorSequence.new(HOT, BLOOD), nseq(0, 0.15, 1, 1), nseq(0, 1, 1, 0.3), nil, nil, 0.8))
	end
	-- the mane streaming back off the head, the beard, the whiskers
	for _, at in ipairs({ Vector3.new(0, 0.6, 0.5), Vector3.new(-0.55, 0.35, 0.6), Vector3.new(0.55, 0.35, 0.6) }) do
		body(ribbon(core, at * hs, 0.5 * hs, life * 0.35, ColorSequence.new(HOT, BLOOD), nseq(0, 0.1, 1, 1), nseq(0, 1, 1, 0.1), TEX_WISPS, 2 * hs, 0.9))
	end
	local snout = headParts[2]
	body(ribbon(snout, Vector3.new(0, -0.35, 0.2) * hs, 0.3 * hs, life * 0.25, ColorSequence.new(HOT, CRIMSON), nseq(0, 0.2, 1, 1), nseq(0, 1, 1, 0)))
	for _, sx in ipairs({ -1, 1 }) do
		body(ribbon(snout, Vector3.new(sx * 0.5, -0.1, -0.5) * hs, 0.07 * hs, life * 0.5, ColorSequence.new(WHITE, HOT), nseq(0, 0.05, 1, 1)))
	end
	-- fire pouring off the head, lying along the path; motes of light
	local fire = emitter(core, { Texture = TEX_FIRE, Color = ColorSequence.new(CRIMSON, BLOOD), LightEmission = 0.7,
		Size = nseq(0, 1.6 * s, 1, 0.3 * s), Transparency = nseq(0, 0.35, 1, 1), Lifetime = NumberRange.new(life * 0.6, life),
		Speed = NumberRange.new(0.5, 2.5), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Back,
		Rate = 50, RotSpeed = NumberRange.new(-150, 150), Rotation = NumberRange.new(0, 360), Drag = 2 })
	local motes = emitter(core, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, CRIMSON), LightEmission = 1,
		Size = nseq(0, 0.45 * s, 1, 0), Transparency = nseq(0, 0, 1, 1), Lifetime = NumberRange.new(life * 0.8, life * 1.4),
		Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Rate = 30 })
	if FxBudget.Light() then
		local l = Instance.new("PointLight")
		l.Color = CRIMSON
		l.Brightness = 2.5
		l.Range = 10 * math.min(s, 2.5)
		l.Parent = core
		FxBudget.TrackLight(l)
	end

	-- Where the head has been, newest first, by time.
	local hist: { { t: number, p: Vector3 } } = { { t = os.clock(), p = start } }
	local headCF = CFrame.lookAt(start, start + (if look.Magnitude > 0.01 then look else Vector3.zAxis))
	local alive = true
	local spin = 0
	local all: { BasePart } = {}
	for _, p in ipairs(headParts) do table.insert(all, p) end
	for _, p in ipairs(jawParts) do table.insert(all, p) end
	for _, p in ipairs(plates) do table.insert(all, p) end
	for _, p in ipairs(fins) do table.insert(all, p) end
	for _, p in ipairs(claws) do table.insert(all, p) end
	for _, p in ipairs(strands) do table.insert(all, p) end
	local cfs = table.create(#all)

	-- Where the head was `age` seconds ago, and which way it was going.
	local function past(age: number): (Vector3, Vector3)
		local want = os.clock() - age
		for i = 1, #hist - 1 do
			local a, b = hist[i], hist[i + 1]
			if b.t <= want then
				local k = if a.t > b.t then (a.t - want) / (a.t - b.t) else 0
				local d = a.p - b.p
				return a.p:Lerp(b.p, math.clamp(k, 0, 1)), if d.Magnitude > 0.001 then d.Unit else headCF.LookVector
			end
		end
		local last = hist[#hist]
		local d = if #hist > 1 then hist[#hist - 1].p - last.p else headCF.LookVector
		return last.p, if d.Magnitude > 0.001 then d.Unit else headCF.LookVector
	end

	local function place()
		local n = 0
		for _, rel in ipairs(headRel) do
			n += 1
			cfs[n] = headCF * rel
		end
		local hinge = headCF * HINGE * CFrame.Angles(math.rad(-(6 + 34 * jawOpen)), 0, 0)
		for _, rel in ipairs(jawRel) do
			n += 1
			-- (relative to the hinge: back out of the head frame first)
			cfs[n] = hinge * HINGE:Inverse() * rel
		end
		local plateCF = {}
		for k = 1, PLATES do
			local p, d = past(life * 0.92 * k / (PLATES + 1))
			-- (a slow roll along the body, so it reads as round)
			local cf = CFrame.lookAt(p, p + d, if math.abs(d.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis) * CFrame.Angles(0, 0, math.rad(45))
			plateCF[k] = cf * CFrame.Angles(0, 0, math.rad(-45))
			n += 1
			cfs[n] = cf
		end
		for k = 1, PLATES do
			if k % 2 == 1 then
				local u = k / (PLATES + 1)
				n += 1
				cfs[n] = plateCF[k] * CFrame.new(0, s * (0.85 - 0.55 * u) * 1.05, 0)
			end
		end
		for i, rel in ipairs(clawRel) do
			n += 1
			cfs[n] = plateCF[clawAt[i]] * rel
		end
		for i in ipairs(strands) do
			n += 1
			cfs[n] = headCF * CFrame.new(behind) * CFrame.Angles(0, 0, spin + i * math.pi) * CFrame.new(0, 0.95 * s, 0)
		end
		Workspace:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	local alphaNow = -1
	local d: Dragon = {
		move = function(pos: Vector3, lookDir: Vector3)
			if not alive then return end
			local lv = if lookDir.Magnitude > 0.01 then lookDir.Unit else headCF.LookVector
			headCF = CFrame.lookAt(pos, pos + lv, if math.abs(lv.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis)
			local now = os.clock()
			spin += 0.35
			table.insert(hist, 1, { t = now, p = pos })
			for i = #hist, 2, -1 do
				if now - hist[i - 1].t > life + 0.1 then hist[i] = nil else break end
			end
			place()
		end,
		set = function(alpha: number)
			if math.abs(alpha - alphaNow) < 0.02 then return end
			alphaNow = alpha
			for i, p in ipairs(parts) do
				p.Transparency = base[i] + (1 - base[i]) * (1 - alpha)
			end
			for i, t in ipairs(trails) do
				local kps = {}
				for _, kp in ipairs(trailBase[i].Keypoints) do
					table.insert(kps, NumberSequenceKeypoint.new(kp.Time, 1 - (1 - kp.Value) * alpha))
				end
				t.Transparency = NumberSequence.new(kps)
			end
			fire.Enabled = alpha > 0.3
			motes.Enabled = alpha > 0.3
		end,
		jaw = function(k: number) jawOpen = math.clamp(k, 0, 1) end,
		destroy = function()
			if not alive then return end
			alive = false
			fire.Enabled = false
			motes.Enabled = false
			for _, t in ipairs(trails) do t.Enabled = false end
			-- (the parts holding the ribbons and the fire stay, unseen, till
			-- what they left on the path has burnt out)
			for _, p in ipairs(parts) do
				if p == core or p == snout then
					p.Transparency = 1
					Debris:AddItem(p, life + 0.3)
				else
					p:Destroy()
				end
			end
			for _, c in ipairs(strands) do Debris:AddItem(c, life + 0.3) end
		end,
		head = function() return headCF end,
	}
	d.set(0)
	place()
	return d
end

-- ── Every Martial Artist: the tails, the fist streaks ───────────────────────
type Rig = { motors: { Motor6D }, phase: { number }, band: { boolean }, fists: { Trail } }
local rigs: { [Model]: Rig } = {}

local function rigOf(char: Model): Rig?
	local r = rigs[char]
	if r and r.motors[1] and r.motors[1].Parent then return r end
	local gi = char:FindFirstChild("MartialGi")
	if not gi then return nil end
	local nr: Rig = { motors = {}, phase = {}, band = {}, fists = {} }
	for _, d in ipairs(gi:GetDescendants()) do
		if d:IsA("Motor6D") and string.sub(d.Name, -5) == "Motor" then
			table.insert(nr.motors, d)
			table.insert(nr.phase, math.random() * 6)
			table.insert(nr.band, string.sub(d.Name, 1, 4) == "Band")
		end
	end
	if #nr.motors == 0 then return nil end
	-- a streak of Qi off each fist and the right foot (lit only while they strike)
	for _, side in ipairs({ "Right Arm", "Left Arm", "Right Leg" }) do
		local limb = char:FindFirstChild(side) :: BasePart?
		if limb then
			local old = limb:FindFirstChild("MartialFistTrail")
			if old then old:Destroy() end
			local t = ribbon(limb, Vector3.new(0, -0.95, 0), if side == "Right Leg" then 0.8 else 0.6, 0.18,
				ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.35, HOT), ColorSequenceKeypoint.new(1, BLOOD) }),
				nseq(0, 0, 1, 1), nseq(0, 1, 1, 0.2))
			t.Name = "MartialFistTrail"
			t.Enabled = false
			table.insert(nr.fists, t)
		end
	end
	rigs[char] = nr
	return nr
end

-- Light the streaks for `seconds` (`which`: "R", "L", "both" fists, or "kick").
local function fistStreak(char: Model, which: string, seconds: number)
	local r = rigOf(char)
	if not r then return end
	for i, t in ipairs(r.fists) do
		if (which == "both" and i <= 2) or (which == "R" and i == 1) or (which == "L" and i == 2) or (which == "kick" and i == 3) then
			t.Enabled = true
			task.delay(seconds, function() t.Enabled = false end)
		end
	end
end

local function stepRigs(_dt: number)
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not (char and isMartial(p)) then continue end
		local root = rootOf(char)
		local r = rigOf(char)
		if not (root and r) then continue end
		local v = root.AssemblyLinearVelocity
		local k = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / 22, 0, 1)
		local rise = math.clamp(-v.Y / 40, -0.5, 0.6)
		for i, m in ipairs(r.motors) do
			local ph = r.phase[i]
			if r.band[i] then
				-- (streaming out behind the head, fluttering harder the faster he goes)
				m.Transform = CFrame.Angles(-0.4 * k - rise * 0.5 + math.sin(now * (7 + 6 * k) + ph) * (0.07 + 0.2 * k), 0,
					math.sin(now * 5.3 + ph) * (0.1 + 0.15 * k))
			else
				-- (the sash's tails swing back as he runs)
				m.Transform = CFrame.Angles(-1.0 * k - rise * 0.8 + math.sin(now * 6 + ph) * (0.05 + 0.12 * k), 0,
					math.sin(now * 4.4 + ph) * 0.07)
			end
		end
	end
	for c in pairs(rigs) do
		if not c.Parent then rigs[c] = nil end
	end
end

-- ── Poses ───────────────────────────────────────────────────────────────────
-- (CastPoses character space.) The strikes and the uppercut stand on
-- CastPoses.body, so on R6 the feet stay on the floor whatever the lean, and
-- the hips turn back against the twist. Signs: `lean` - = forward; `twist`
-- + = the torso turned to his LEFT (right shoulder forward); `front` is the
-- left foot's angle forward, `back` the right foot's back (negative swaps
-- them: the right foot forward). The arms are AIMED in the world
-- ({ elev from hanging, 90 = level; yaw + = to his left; out + = away from
-- the body, - = across it }) and turned back into shoulder angles under the
-- torso's lean and twist, so a fist lands where it's aimed however hard the
-- body turns in behind it. The head stays on the target (`look` + = up).
local QUAD, QUART = Enum.EasingStyle.Quad, Enum.EasingStyle.Quart
type Pose = { [string]: { number } }
type Aim = { number } -- { elev, yaw, out }

-- (CastPoses blends each angle on its own, so of the two ways to write the
-- same turn, and whole turns either side, this takes the one nearest the
-- rough angles `guess`: an arm raised past the vertical then swings up
-- through the top instead of the long way round.)
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

local function aimed(lean: number, twist: number, aim: Aim, left: boolean?): { number }
	local out = if left then -(aim[3] or 0) else (aim[3] or 0)
	local world = CFrame.Angles(0, math.rad(aim[2] or 0), 0) * CFrame.Angles(math.rad(aim[1]), 0, 0)
		* CFrame.Angles(0, 0, math.rad(out))
	local torso = CFrame.fromEulerAnglesXYZ(math.rad(lean), math.rad(twist), 0)
	local rx, ry, rz = (torso:Inverse() * world):ToEulerAnglesXYZ()
	return nearest(math.deg(rx), math.deg(ry), math.deg(rz), { aim[1] - lean, (aim[2] or 0) - twist, out })
end

-- A fighter's whole body: the stance, both arms aimed, the head on the
-- target; `shiftZ` slides the weight (- = onto the front foot).
local function fighter(lean: number, twist: number, front: number, back: number, ra: Aim, la: Aim, look: number?,
	shiftZ: number?): Pose
	local p = CastPoses.body(lean, twist, front, back, nil, 7, 0, shiftZ)
	p.RS = aimed(lean, twist, ra)
	p.LS = aimed(lean, twist, la, true)
	p.N = { (look or 0) - lean * 0.6, -twist * 0.85, 0 }
	return p
end

-- `p` standing on its left leg, the right leg at `angle` (world: forward
-- from hanging) and `out` to the side.
local function onLeftLeg(p: Pose, lean: number, angle: number, out: number?): Pose
	p.RH = { angle - lean, 0, out or 6 }
	return p
end

-- `p` spun `yaw` degrees round (the whole body, feet and all).
local function spun(p: Pose, yaw: number): Pose
	local r = p.Root or { 0, 0, 0, 0, 0, 0 }
	p.Root = { r[1] or 0, yaw, r[3] or 0, r[4] or 0, r[5] or 0, r[6] or 0 }
	return p
end

-- Guard: left foot forward, fists up, the right at the chin.
local GUARD = fighter(-6, 12, 14, 18, { 70, 4, -22 }, { 76, -4, -26 }, 2)

-- The chain. Every strike: a quick wind-up (Quad), the blow (Quart: fastest
-- at the hit), held a beat, then back to guard. Each one steps in and his
-- feet stay planted till it's thrown (MartialController.Basic).
local STRIKES = {
	-- 1 · the jab: the right fist chambered at the hip, then snapped out level
	-- with the shoulders turning in behind it and the weight on the front
	-- (left) foot, the left fist kept up at the chin
	{ { dur = 0.045, style = QUAD, pose = fighter(-4, -16, 19, 16, { 20, 0, 12 }, { 74, 0, -26 }, 4) },
		{ dur = 0.055, style = QUART, pose = fighter(-12, 28, 26, 36, { 92, 20, 0 }, { 72, 0, -28 }, 4, -0.35) },
		{ dur = 0.08, pose = fighter(-10, 25, 24, 32, { 90, 20, 0 }, { 72, 0, -28 }, 4, -0.3) } },
	-- 2 · the cross: a step through onto the right foot, the hips whipped the
	-- other way and the left fist driven through, the right back at the chin
	{ { dur = 0.045, style = QUAD, pose = fighter(-4, 16, 6, 6, { 74, 0, -26 }, { 20, 0, 12 }, 4) },
		{ dur = 0.055, style = QUART, pose = fighter(-13, -30, -36, -24, { 72, 0, -28 }, { 93, -20, 0 }, 4, -0.4) },
		{ dur = 0.08, pose = fighter(-11, -27, -32, -22, { 72, 0, -28 }, { 91, -20, 0 }, 4, -0.35) } },
	-- 3 · the high kick: the right knee chambered up, then the leg snapped
	-- high in front, the body leaning back off the standing leg, the right
	-- arm thrown down for balance, the left fist kept up
	{ { dur = 0.06, style = QUAD, pose = onLeftLeg(fighter(2, 8, 4, 4, { 56, 0, -14 }, { 74, -4, -24 }, 4), 2, 60) },
		{ dur = 0.07, style = QUART, pose = onLeftLeg(fighter(14, 10, -4, 4, { 24, 0, 30 }, { 80, -4, -24 }, 12), 14, 140, 4) },
		{ dur = 0.1, pose = onLeftLeg(fighter(12, 10, -4, 4, { 26, 0, 30 }, { 78, -4, -24 }, 10), 12, 132, 4) } },
	-- 4 · the spinning strike: wound round to the right, then the whole body
	-- spins right round on the left foot, the right leg swept out level
	-- through everything round him, arms flung wide, the torso tipped away
	-- from the leg; it comes back square to the front inside the strike
	-- (the full turn ends at 360, which the recovery counts as no turn).
	(function()
		local sweep = function(yaw: number): Pose
			local p = spun(fighter(0, 0, -2, 2, { 78, 0, 78 }, { 70, 0, 78 }, 0), yaw)
			p.W = { 0, 0, 14 }               -- (tipped to his left, away from the leg)
			p.RH = { 0, 0, 76 }              -- level out to the side (with the tip: 90)
			p.LH = { 0, 0, -18 }             -- the standing leg kept straight under him
			p.Root[5] = 0.18                 -- (up on the standing leg)
			return p
		end
		return {
			{ dur = 0.05, style = QUAD, pose = spun(fighter(-8, -14, 20, 14, { 55, 0, 45 }, { 55, 0, 45 }, 0), -60) },
			{ dur = 0.08, style = QUART, pose = sweep(120) },
			{ dur = 0.07, pose = sweep(220) },
			{ dur = 0.08, style = QUAD, pose = spun(table.clone(GUARD), 360) },
		}
	end)(),
	-- 5 · the elbow: the right arm drawn back level and out, then whipped
	-- across the chest at shoulder height with a hard turn of the hips, low
	-- and close, the left fist up
	{ { dur = 0.05, style = QUAD, pose = fighter(-4, -30, 23, 18, { 86, -55, 0 }, { 74, 0, -26 }, 2) },
		{ dur = 0.05, style = QUART, pose = fighter(-12, 42, 26, 40, { 88, 55, 0 }, { 72, 0, -28 }, 2, -0.4) },
		{ dur = 0.1, pose = fighter(-10, 38, 23, 35, { 86, 50, 0 }, { 72, 0, -28 }, 2, -0.35) } },
	-- 6 · the palm strike: the hand coiled back at the hip, the body turned
	-- away and low, then the open palm driven out level in a deep lunge as the
	-- Qi bursts from it, the left fist pulled back
	{ { dur = 0.07, style = QUAD, pose = fighter(-2, -32, 22, 20, { 15, 0, 18 }, { 74, 0, -26 }, 4, 0.2) },
		{ dur = 0.06, style = QUART, pose = fighter(-15, 30, 30, 42, { 94, 18, 0 }, { 30, 0, -30 }, 4, -0.55) },
		{ dur = 0.14, pose = fighter(-13, 28, 30, 40, { 92, 18, 0 }, { 32, 0, -30 }, 4, -0.5) } },
	-- 7 · the finisher: a hop, the right knee driven high and both fists
	-- raised, then everything brought down into the floor, kneeling on the
	-- right knee with both fists driven down (the eruption, FINISH_LAND in);
	-- then back up into guard
	{ { dur = 0.07, style = QUAD, pose = CastPoses.lift(onLeftLeg(fighter(6, 0, -10, 10, { 150, 0, 14 }, { 150, 0, 14 }, 10), 6, 80), 0.8) },
		{ dur = 0.09, style = QUART, pose = fighter(-28, 0, 46, 46, { 28, 0, 10 }, { 28, 0, 10 }, -10, -0.2) },
		{ dur = 0.12, pose = fighter(-26, 0, 46, 46, { 30, 0, 10 }, { 30, 0, 10 }, -8, -0.2) },
		{ dur = 0.2, style = Enum.EasingStyle.Sine, pose = GUARD },
		{ dur = 0.12, pose = GUARD } },
}
local STRIKE_HAND = { "R", "L", "kick", "kick", "R", "R", "both" }

-- `speed`: attack speed; the whole strike plays that much faster, so it's
-- thrown in full (the spin comes back square) before the next one cuts in.
local function strikePose(char: Model, n: number, speed: number?)
	local s = math.max(speed or 1, 1)
	CastPoses.play(char, STRIKES[n] or STRIKES[1], if n == COMBO_STEPS then 0.25 else 0.18, nil, { speed = s })
	fistStreak(char, STRIKE_HAND[n] or "R", (if n >= 6 then 0.3 else 0.2) / s)
end

-- Focus Strike: 1 · Hold / charge (a wide low stance, left foot forward, the
-- body turned away, the right fist drawn back past the hip, the left arm
-- reaching out ahead to aim; shaking harder as the charge builds; `full`:
-- seconds to full charge).
local function focusPose(char: Model, hold: number, full: number)
	local coil = { RS = { -32, 0, 16 }, LS = { 82, 0, -14 }, Root = { 0, 0, 0, 0, -0.78, 0.3 }, W = { 4, -46, 0 }, N = { 0, 38, 0 },
		LH = { 32, 0, -16 }, RH = { -24, 0, 18 } }
	local root = rootOf(char)
	CastPoses.play(char, {
		{ dur = 0.16, pose = coil },
		{ dur = hold, pose = coil, wobble = function(t: number)
			local k = math.min(t / full, 1)
			local s = math.sin(t * 58) * (0.4 + 2.4 * k)
			-- (creeping about in the stance: short shuffling steps while he moves)
			local v = if root then root.AssemblyLinearVelocity else Vector3.zero
			local m = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / FOCUS.walk, 0, 1)
			local step = math.sin(t * 11) * 16 * m
			return { RS = { s, 0, 0 }, W = { 0, s * 0.4, 0 }, RH = { step, 0, 0 }, LH = { -step, 0, 0 },
				Root = { 0, 0, 0, 0, math.sin(t * 47) * 0.025 * k + math.abs(math.sin(t * 11)) * 0.08 * m, 0 } }
		end },
	}, 0.25)
end

-- 2 · Release: the right fist driven straight out with the whole body
-- behind it in a deep lunge, the left pulled back to the hip; held longer
-- the harder it was charged (`c`, 0..1).
local function focusPunchPose(char: Model, c: number)
	local punch = { RS = { 98, 0, -6 }, LS = { -18, 0, -26 }, W = { -14, 38, 0 }, N = { 0, -26, 0 }, Root = { 0, 0, 0, 0, -0.55, -0.7 },
		LH = { 42, 0, -10 }, RH = { -42, 0, 12 } }
	CastPoses.play(char, {
		{ dur = FOCUS.hit, style = Enum.EasingStyle.Quart, pose = punch },
		{ dur = 0.16 + 0.24 * c, pose = punch },
	}, 0.3)
	task.delay(FOCUS.hit * 0.3, function() fistStreak(char, "R", 0.25) end)
end

-- Electric Uppercut (after the Wind God Fist): first the dash, then the
-- punch. 1 · drop into a crouch → 2 · dash in low, bent right over in a long
-- running stride, the right fist dragged low behind by the knee, the left
-- up on guard, eyes up on them → 3 · planted: the right foot driven in
-- ahead, the left leg stretched long behind, and the fist swung up from the
-- knee past the outside of his head with the shoulders turning in behind
-- it (the hit) → 4 · carried on up at the sky, the left fist dropped by the
-- hip, eyes following them up → held → back to guard.
local function uppercutPose(char: Model)
	local U = UPPER
	local up = fighter(-6, 36, -37, -42, { 164, 4, 16 }, { 18, 0, -6 }, 16, -0.2)
	CastPoses.play(char, {
		{ dur = U.crouch, style = QUAD, pose = fighter(-24, -18, 40, 28, { -6, 0, 14 }, { 76, -10, -26 }, 14) },
		{ dur = U.dash, pose = fighter(-32, -22, 52, 37, { -26, 0, 12 }, { 84, -10, -26 }, 22) },
		{ dur = U.swing, style = QUART, pose = fighter(-12, 30, -33, -42, { 150, 6, 16 }, { 22, 0, -8 }, 12, -0.25) },
		{ dur = U.rise, pose = up },
		{ dur = U.hang, pose = up },
		{ dur = U.fall, style = QUAD, pose = fighter(-6, 14, 10, 16, { 100, 4, -10 }, { 56, 0, -24 }, 8) },
	}, 0.25)
end

-- Ground Slam: 1 · Ascend (a rising uppercut, straight up, a knee
-- tucked) → 2 · Strike (flying forward, the body flat behind the fist) →
-- 3 · Impact (a hero's landing: the fist driven into the ground).
local function ascentPose(char: Model)
	local T = ASCENT
	CastPoses.play(char, {
		{ dur = T.rise * 0.35, pose = { RS = { 60, 0, 10 }, LS = { 40, 0, -40 }, Root = { 0, 0, 0, 0, -0.6, 0 }, W = { 18, 0, 0 },
			RH = { 40, 0, 0 }, LH = { 30, 0, 0 } } },
		{ dur = T.rise * 0.65, style = Enum.EasingStyle.Quart, pose = { RS = { 172, 0, 6 }, LS = { 30, 0, -50 }, RH = { 80, 0, 0 },
			LH = { -6, 0, 0 }, W = { -6, 0, 0 }, N = { -24, 0, 0 } } },
		{ dur = T.dash, pose = { W = { 14, 0, 0 }, RS = { 40, 0, 30 }, LS = { 60, 0, -40 }, RH = { 95, 0, 10 }, LH = { 75, 0, -10 },
			N = { -12, 0, 0 } } },
		{ dur = T.fall * 0.35, style = Enum.EasingStyle.Quart, pose = { W = { -55, 0, 0 }, RS = { 168, 0, -6 }, LS = { 30, 0, -50 },
			RH = { 12, 0, 6 }, LH = { -20, 0, -6 }, N = { -30, 0, 0 } } },
		{ dur = T.fall * 0.65, pose = { W = { -58, 0, 0 }, RS = { 170, 0, -6 }, LS = { 28, 0, -52 }, RH = { 10, 0, 6 }, LH = { -22, 0, -6 },
			N = { -32, 0, 0 } } },
		{ dur = 0.3, pose = { Root = { 10, 0, 0, 0, -1.25, 0 }, RS = { 25, 0, -10 }, LS = { 50, 0, -60 }, W = { 32, 0, 0 }, N = { -20, 0, 0 },
			RH = { 85, 0, 10 }, LH = { -15, 0, -14 } } },
	}, 0.35)
	task.delay(T.rise * 0.3, function() fistStreak(char, "R", T.rise + T.dash + T.fall) end)
end

-- Crimson Hadouken (after the pose sheet, checked on an R6 rig: both feet
-- flat on the floor, the hands meeting round the sphere):
-- 1 · Charge: a wide low split stance, the right leg bent forward taking
-- the weight, the left stretched back; both arms brought in round the
-- sphere in front of the belly, the right a little higher and closer, the
-- left in front of it; head slightly down, eyes forward; the arms trembling
-- as it builds (no twist through the waist: on R6 that turns the legs too).
-- 2 · Thrust: both palms driven out together ahead, the body lunging in
-- behind them on the same stance → held.
local function hadoPose(char: Model)
	local cup = { Root = { 0, 0, 0, 0, -0.58, -0.15 }, W = { -4, -8, 0 }, N = { 12, 8, 0 }, RS = { 75, 0, -45 }, LS = { 65, 0, 40 },
		RH = { 44, 0, 30 }, LH = { -42, 0, -26 } }
	local thrust = { Root = { 0, 0, 0, 0, -0.46, -0.45 }, W = { -10, 4, 0 }, N = { 4, 0, 0 }, RS = { 88, 0, -40 }, LS = { 88, 0, 40 },
		RH = { 48, 0, 26 }, LH = { -29, 0, -24 } }
	CastPoses.play(char, {
		{ dur = 0.22, pose = cup },
		{ dur = HADO.charge - 0.22, pose = cup, wobble = function(t: number)
			local s = math.sin(t * 50) * (0.6 + 2.2 * math.min(t / HADO.charge, 1))
			return { RS = { s, 0, 0 }, LS = { -s, 0, 0 } }
		end },
		{ dur = 0.07, style = Enum.EasingStyle.Quart, pose = thrust },
		{ dur = HADO.hold, pose = thrust },
	}, 0.35)
end

-- ── M1: Flowing Fists ───────────────────────────────────────────────────────
-- Every strike drives air out to its full reach (rings of air racing along
-- the blow, speed lines; a ring swept round him for the spin and the knee),
-- so you can see how far it hits. 1 · jab and 2 · cross: a crescent of Qi
-- off the fist, a flurry of phantom fists thrown round the real one. 3 · the
-- high kick: a tall crescent of Qi swept up in front. 4 · the spinning
-- strike: a ring of Qi swept all the way round him, wind kicked up off the
-- floor. 5 · the elbow: a short starburst where it lands. 6 · the palm: a
-- small dragon bursts out of it, a shell of Qi, cracked ground. 7 · the
-- finisher: the floor erupts where the knee lands, rock thrown up, a
-- shockwave. Every strike stamps a ring of Qi at his feet.

-- A ring of air bursting off a punch, standing across the line of it.
local function punchRing(at: Vector3, dir: Vector3, radius: number, life: number, color: Color3?)
	SwordFX.Arc({ cf = CFrame.lookAt(at, at + dir) * CFrame.Angles(math.rad(90), 0, 0), radius = radius, arc = 359, width = 0.35,
		color = color or CRIMSON, life = life, draw = 0.001, grow = 1.1, core = WHITE })
end

-- A blast of air driven off a strike out to its full reach (so you see how
-- far it hits): rings of air racing out along the line, swelling as they
-- go, and speed lines streaking ahead. `k` sizes the rings.
local AIR = Color3.fromRGB(255, 232, 232)
local function airBlast(from: Vector3, dir: Vector3, reach: number, k: number)
	if reach < 1 or not FxBudget.Allow("maAir", 12) then return end
	for i = 1, 3 do
		local u = i / 3
		task.delay((i - 1) * 0.03, function()
			punchRing(from + dir * (0.6 + (reach - 0.6) * u), dir, (0.6 + 1.4 * u) * k, 0.14 + 0.06 * u, if i == 3 then AIR else HOT)
		end)
	end
	SwordFX.Streak(from, from + dir * reach, 0.45 * k, AIR, 0.06, 5, WHITE)
end

-- A ring of air swept flat round him out to `reach` (the spin, the knee).
local function airRing(at: Vector3, dir: Vector3, reach: number, draw: number)
	if not FxBudget.Allow("maAir", 12) then return end
	SwordFX.Arc({ cf = CFrame.lookAt(at, at + dir), radius = reach * 0.5, arc = 359, width = 0.55, color = AIR, life = 0.3,
		draw = draw, grow = 0.9, core = WHITE })
end

-- Chunks of the floor thrown up round `center` (the finisher).
local function chunks(center: Vector3, count: number, speed: number)
	for _ = 1, count do
		local sz = 0.4 + math.random() * 0.8
		local p = part({ Size = Vector3.new(sz, sz * 0.7, sz * 0.8), Color = ROCK, Material = Enum.Material.Slate,
			CFrame = CFrame.new(center + Vector3.new(0, 0.5, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6) })
		p.Anchored = false
		local a = math.random() * math.pi * 2
		p.AssemblyLinearVelocity = Vector3.new(math.cos(a), 0, math.sin(a)) * speed * (0.4 + math.random() * 0.6)
			+ Vector3.new(0, speed * (0.8 + math.random() * 0.6), 0)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		TweenService:Create(p, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.6), { Transparency = 1 }):Play()
		Debris:AddItem(p, 1.1)
	end
end

-- The finisher's knee hitting the floor: an eruption round it.
local function eruption(at: Vector3, radius: number, mine: boolean)
	local g = onGround(at)
	floorRing(g, radius, 0.35, CRIMSON, 1.1)
	task.delay(0.06, function() floorRing(g, radius * 1.3, 0.4, HOT, 0.6) end)
	shell(g + Vector3.new(0, 0.6, 0), 1, radius * 1.8, 0.35, CRIMSON)
	airRing(g + Vector3.new(0, 0.6, 0), Vector3.new(0, 0, -1), radius * 1.15, 0.001)
	flare(g + Vector3.new(0, 1, 0), radius * 0.9, 0.22, WHITE)
	PackFX.Burst("Anime/Crack-01", CFrame.new(g + Vector3.new(0, 0.1, 0)), { color = BLOOD, scale = 0.9 })
	if FxBudget.Allow("maFinishRocks", 3) then
		chunks(g, 10, 26)
		PackFX.Burst("Anime/Smoke-01", CFrame.new(g + Vector3.new(0, 0.5, 0)), { color = Color3.fromRGB(150, 130, 110), scale = 0.8 })
	end
	sparks(g + Vector3.new(0, 1, 0), 26, 30)
	ClassFX.Sound("boom", g, 0.6, 1.2)
	ClassFX.Sound("rockHit", g, 0.6, 0.9)
	if mine and deps then
		deps.shake(0.55, 0.2)
		deps.fovPunch(4, 0.2)
	end
end

-- Phantom fists: streaks of Qi thrown in a flurry round the real one.
local function phantoms(fist: Vector3, dir: Vector3, count: number, reach: number)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for i = 1, count do
		task.delay((i - 1) * 0.035, function()
			local off = side * (math.random() - 0.5) * 1.8 + Vector3.new(0, (math.random() - 0.5) * 1.3, 0)
			local a = fist + off - dir * 0.6
			local b = a + dir * reach * (0.7 + math.random() * 0.3)
			streak(a, b, 0.34, 0.13, if i % 2 == 0 then HOT else CRIMSON)
			flare(b, 1.8, 0.12)
		end)
	end
end

local function strikeFx(msg: any)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local n = tonumber(msg.step) or 1
	local mine = msg.attacker == nil or msg.attacker == player
	local fist = pos + dir * 2.6 + Vector3.new(0, 0.6, 0)
	local feet = onGround(pos)
	local reach = tonumber(msg.reach) or COMBO_RANGE[n] or 8
	if not FxBudget.Allow("maStrike", 14) then return end
	-- (a stamp of Qi at his feet)
	floorRing(feet, if n == 4 or n == 6 then 4.5 else 2.4, 0.25, CRIMSON, 0.45)
	if n == COMBO_STEPS then
		-- the flying knee: a streak of Qi up off the knee, then the eruption
		-- when it comes down
		local knee = pos + dir * 1.2 + Vector3.new(0, 1.5, 0)
		streak(knee - Vector3.new(0, 2, 0), knee + Vector3.new(0, 1.5, 0), 0.5, 0.15, HOT)
		ClassFX.Sound("whoosh", knee, 0.6, 0.75)
		local at = (msg.palm :: Vector3?) or (pos + dir * 2.5)
		local r = tonumber(msg.radius) or FINISH_RADIUS
		task.delay(FINISH_LAND, function() eruption(at, r, mine) end)
	elseif n == 3 then
		-- the high kick: a tall crescent of Qi swept up in front of him
		local c = pos + dir * 1.4 + Vector3.new(0, 0.8, 0)
		SwordFX.Arc({ cf = CFrame.lookAt(c, c + dir) * CFrame.Angles(0, 0, math.rad(90)), radius = 3.2, arc = 150, width = 0.9,
			color = CRIMSON, life = 0.24, draw = 0.06, grow = 0.35, core = WHITE, sweep = -1 })
		SwordFX.Arc({ cf = CFrame.lookAt(c, c + dir) * CFrame.Angles(0, 0, math.rad(80)), radius = 2.6, arc = 120, width = 0.45,
			color = HOT, life = 0.2, draw = 0.06, grow = 0.3, core = WHITE, sweep = -1 })
		-- (the air it throws off: a big crescent, a blast out to the reach)
		SwordFX.Arc({ cf = CFrame.lookAt(c, c + dir) * CFrame.Angles(0, 0, math.rad(90)), radius = 4.6, arc = 120, width = 0.5,
			color = AIR, life = 0.26, draw = 0.07, grow = 0.6, core = WHITE, sweep = -1 })
		airBlast(c + Vector3.new(0, 1.6, 0), dir, reach, 1.2)
		sparks(c + dir * 2 + Vector3.new(0, 2, 0), 10, 16)
		ClassFX.Sound("whoosh", c, 0.55, 0.9)
	elseif n == 5 then
		-- the elbow: a short, hard starburst where it lands
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local hit = pos + dir * 1.8 + side * 0.4 + Vector3.new(0, 0.9, 0)
		flare(hit, 3.6, 0.16, WHITE)
		punchRing(hit, dir, 1.3, 0.18, HOT)
		SwordFX.Arc({ cf = CFrame.lookAt(hit - dir * 0.6, hit + dir) * CFrame.Angles(0, 0, math.rad(-80)), radius = 1.6,
			arc = 140, width = 0.5, color = CRIMSON, life = 0.16, draw = 0.03, grow = 0.3, core = WHITE })
		airBlast(hit, dir, reach, 1.1)
		sparks(hit, 12, 20)
		ClassFX.Sound("punch", hit, 0.45, 0.8)
	elseif n == 1 or n == 2 then
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local hand = fist + side * (if n == 1 then 0.5 else -0.5)
		SwordFX.Arc({ cf = CFrame.lookAt(hand, hand + dir) * CFrame.Angles(0, 0, math.rad(if n == 1 then 70 else -70)), radius = 2.4,
			arc = 120, width = 0.6, color = CRIMSON, life = 0.2, draw = 0.04, grow = 0.35, core = WHITE })
		airBlast(hand, dir, reach, 1)
		if FxBudget.Allow("maPhantom", 8) then phantoms(hand, dir, if n == 1 then 3 else 4, reach * 0.7) end
		ClassFX.Sound("whoosh", hand, 0.4, 1 + n * 0.08)
	elseif n == 4 then
		-- the spinning strike: a full ring of Qi swept round him at the height
		-- of the kick, a thinner one just above it, wind off the floor
		local c = pos + Vector3.new(0, -0.4, 0)
		SwordFX.Arc({ cf = CFrame.lookAt(c, c + dir), radius = 3.4, arc = 359, width = 1.0, color = CRIMSON, life = 0.28, draw = 0.09,
			grow = 0.4, core = WHITE })
		SwordFX.Arc({ cf = CFrame.lookAt(c + Vector3.new(0, 0.6, 0), c + Vector3.new(0, 0.6, 0) + dir) * CFrame.Angles(0, 0, math.rad(8)),
			radius = 2.7, arc = 300, width = 0.5, color = HOT, life = 0.22, draw = 0.08, grow = 0.3, core = WHITE })
		airRing(c, dir, reach, 0.09)
		if FxBudget.Allow("maKickPack", 4) then
			PackFX.Burst("Anime/Wind-02", CFrame.new(feet + Vector3.new(0, 0.4, 0)), { color = CRIMSON, scale = 0.9 })
		end
		sparks(c, 14, 20)
		ClassFX.Sound("whoosh", c, 0.6, 0.8)
	elseif n == 6 then
		-- the palm strike
		local p = (msg.palm :: Vector3?) or (pos + dir * PALM_AT)
		local r = tonumber(msg.radius) or PALM_RADIUS
		local hands = pos + dir * 2.2 + Vector3.new(-dir.Z, 0, dir.X) * 0.5 + Vector3.new(0, 0.4, 0)
		flare(hands, 6, 0.2, WHITE)
		shell(p, 1, r * 2.2, 0.32, CRIMSON)
		flare(p, r * 1.3, 0.25)
		airBlast(hands, dir, reach + r * 0.5, 1.5)
		PackFX.Burst("Anime/Shoot-01", CFrame.lookAt(p, p + dir), { color = CRIMSON, scale = 1.1 })
		floorRing(onGround(p), r, 0.35, CRIMSON, 0.8)
		if FxBudget.Allow("maPalmDragon", 2) then
			local dragon = newDragon(0.7, hands, dir, 0.2)
			dragon.jaw(1)
			local len = r * 1.6
			animate(len / 42 + 0.15, function(a)
				local s = a * (len + 6)
				local q = hands + dir * s + Vector3.new(0, math.sin(s * 0.5) * 0.4, 0)
				dragon.move(q, dir)
				dragon.set(math.min(s / 1.5, 1) * (if s > len then math.max(0, 1 - (s - len) / 6) else 1))
				if a >= 1 then dragon.destroy() end
				return nil
			end)
			PackFX.Burst("Anime/Crack-01", CFrame.new(onGround(p) + Vector3.new(0, 0.1, 0)), { color = BLOOD, scale = 0.6 })
		end
		sparks(p, 22, 28)
		ClassFX.Sound("fireBurst", p, 0.6, 1.2)
		ClassFX.Sound("boom", p, 0.35, 1.5)
		if mine and deps then
			deps.shake(0.3, 0.12)
			deps.fovPunch(3, 0.18)
		end
	end
end

local function strikeLanded(msg: any)
	local n = tonumber(msg.step) or 1
	local dir = msg.dir :: Vector3
	local fist = (msg.pos :: Vector3) + dir * 3 + Vector3.new(0, 0.6, 0)
	flare(fist, 3.4, 0.16)
	punchRing(fist + dir * 0.4, dir, 1.8, 0.18, WHITE)
	sparks(fist, 10, 18)
	ClassFX.Sound("punch", fist, 0.6, 0.9 + n * 0.08)
	if FxBudget.Allow("maPunchPack", 6) then
		PackFX.Burst("Anime/Punch-0" .. tostring(((n - 1) % 3) + 1), CFrame.lookAt(fist, fist + dir), { color = CRIMSON, scale = 0.8 })
	end
	if msg.attacker == player and deps then deps.shake(if n >= 6 then 0.35 else 0.15, 0.07) end
end

local function onStrike(msg: any)
	if msg.attacker ~= player then
		local char = charOf(msg.attacker)
		if char then
			strikePose(char, tonumber(msg.step) or 1, tonumber(msg.attacker:GetAttribute("Stat_basicAttackSpeed")))
		end
		strikeFx(msg)
	end
	if msg.landed and FxBudget.Allow("maLanded", 14) then strikeLanded(msg) end
end

-- ── E: Focus Strike ─────────────────────────────────────────────────────────
-- 1 · Hold / charge, building in three stages: black ink strokes curl in
-- round his drawn-back arm and gather at the fist, where red energy glows at
-- the heart of them, bigger and fiercer the longer he holds; air is dragged
-- in round him; a dark aura of ink and crimson flame rises off him. At each
-- stage it surges: a shockwave over the floor, the ground cracking under
-- him; at the second his eyes ignite and rubble lifts round him, red
-- lightning crackling off the fist; at full it erupts: ink bursting out
-- round him, a ring of light over the floor, the world drained and reddened
-- (yours). 2 · Release: the lunge, strokes of ink dragged along it, rings of
-- air and a crimson crescent off the punch, ink bursting off the fist.
-- 3 · Impact (full charge): a dramatic ink splash: ink flung everywhere and
-- splattering the floor, the ground cracking red, an impact frame.

type Handle = { stop: (boolean) -> () }

-- The pack's flaming eyes (Heads/Flamming-Eyes-01) lit on his own head.
local function flameEyes(char: Model): { Instance }
	local head = char:FindFirstChild("Head") :: BasePart?
	local pack = ReplicatedStorage:FindFirstChild("VFXPack")
	local heads = pack and pack:FindFirstChild("Heads")
	local tpl = heads and heads:FindFirstChild("Flamming-Eyes-01")
	if not (head and tpl) then return {} end
	local made: { Instance } = {}
	for _, src in ipairs(tpl:GetChildren()) do
		if src:IsA("Attachment") then
			local a = Instance.new("Attachment")
			a.Name = "MartialEye"
			-- (on his own face's eyes, a little in front of it)
			a.Position = Vector3.new(if src.Position.X < 0 then -0.17 else 0.17, 0.12, -head.Size.Z / 2 - 0.05)
			for _, e in ipairs(src:GetChildren()) do
				if e:IsA("ParticleEmitter") then
					local c = e:Clone()
					c.Color = ColorSequence.new(CRIMSON)
					c.Rate = math.max(c.Rate, 1) * 6
					c.Enabled = true
					c.Parent = a
					c:Emit(4)
				end
			end
			a.Parent = head
			table.insert(made, a)
		end
	end
	return made
end

local function focusChargeFx(char: Model, full: number, hold: number, mine: boolean): Handle
	local function fist(): Vector3?
		return if char.Parent then fistOf(char, "Right Arm") else nil
	end
	local r0 = rootOf(char)
	local function body(): Vector3?
		return if r0 and r0.Parent then r0.Position else nil
	end
	local start = fist() or Vector3.zero
	local t0 = os.clock()
	local stopped = false
	local stage = 0
	-- the red heart of it: a white-hot core in a crimson glow, energy swirling round
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, Color = HOT, CFrame = CFrame.new(start) })
	local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.6, Color = CRIMSON, Transparency = 0.45, CFrame = CFrame.new(start) })
	local aura = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2, Color = CRIMSON, Material = Enum.Material.ForceField,
		Transparency = 0.15, CFrame = CFrame.new(start) })
	-- ink drawn in from all round the fist (the particles start on a sphere round it)
	local well = part({ Size = Vector3.one * 4.6, Transparency = 1, CFrame = CFrame.new(start) })
	local inkIn = emitter(well, { Texture = TEX_INK, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(INK), LightEmission = 0,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, LockedToPart = true, Size = nseq(0, 0.6, 0.5, 1.5, 1, 0.3),
		Transparency = nseq(0, 0.6, 0.25, 0, 1, 0.3), Lifetime = NumberRange.new(0.32, 0.4), Speed = NumberRange.new(5, 6.5),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-160, 160), Rate = 18, ZOffset = -0.3 })
	local flame = emitter(core, { Texture = TEX_FLAME, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(HOT, CRIMSON), LightEmission = 0.6,
		Size = nseq(0, 0.5, 0.3, 0.9, 1, 0), Lifetime = NumberRange.new(0.28, 0.4), Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Rate = 14, ZOffset = 0.4, LockedToPart = true })
	local motes = emitter(core, { Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, CRIMSON), LightEmission = 1, Size = nseq(0, 0.3, 1, 0),
		Lifetime = NumberRange.new(0.25, 0.4), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180), Drag = 5, Rate = 0 })
	-- the dark aura: ink and crimson flame rising off his whole body, growing with the charge
	local torso = char:FindFirstChild("Torso") :: BasePart?
	local auraAt: Attachment? = nil
	local inkAura: ParticleEmitter? = nil
	local fireAura: ParticleEmitter? = nil
	if torso then
		local at = Instance.new("Attachment")
		at.Name = "MartialFocusAura"
		at.Position = Vector3.new(0, -0.5, 0)
		at.Parent = torso
		auraAt = at
		inkAura = emitter(at, { Texture = TEX_INK, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			Color = ColorSequence.new(INK), LightEmission = 0, Size = nseq(0, 1.2, 0.5, 2.2, 1, 0.6), Transparency = nseq(0, 0.5, 0.3, 0.1, 1, 1),
			Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(35, 35), Acceleration = Vector3.new(0, 9, 0),
			Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), Rate = 0, ZOffset = -0.5 })
		fireAura = emitter(at, { Texture = TEX_FLAME, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
			Color = ColorSequence.new(CRIMSON, BLOOD), LightEmission = 0.4, Size = nseq(0, 1, 0.4, 1.8, 1, 0), Transparency = nseq(0, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, 10, 0),
			Rotation = NumberRange.new(0, 360), Rate = 0, ZOffset = -0.4 })
	end
	local eyes: { Instance } = {}
	-- yours: the world slowly drained and reddened as it builds
	local cc: ColorCorrectionEffect? = nil
	if mine then
		local e = Instance.new("ColorCorrectionEffect")
		e.Name = "MartialFocus"
		e.Parent = Lighting
		cc = e
	end
	local pos = if r0 then onGround(r0.Position) else start
	floorRing(pos, 3.2, 0.5, CRIMSON, 0.5)
	PackFX.Burst("Anime/Blood-01", CFrame.new(pos + Vector3.new(0, 0.1, 0)), { color = INK, scale = 1.3, light = 0 })
	ClassFX.Sound("charge", start, 0.6, 1.1 * FOCUS.full / full, full)
	local nextCurl, nextAir, nextBolt, lastStep = 0, 0, 0, -1
	local rocks: Rubble? = nil
	local function cleanup(burst: boolean)
		inkIn.Enabled, flame.Enabled = false, false
		for _, p in ipairs({ core, glow, aura }) do
			TweenService:Create(p, TweenInfo.new(0.12), { Size = p.Size * (if burst then 2.4 else 0.2), Transparency = 1 }):Play()
			Debris:AddItem(p, 0.15)
		end
		Debris:AddItem(well, 0.5)
		if inkAura then inkAura.Enabled = false end
		if fireAura then fireAura.Enabled = false end
		if auraAt then Debris:AddItem(auraAt, 1) end
		for _, a in ipairs(eyes) do
			for _, e in ipairs(a:GetChildren()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
			Debris:AddItem(a, 1)
		end
		if cc then
			TweenService:Create(cc, TweenInfo.new(0.25), { Saturation = 0, Contrast = 0, Brightness = 0, TintColor = WHITE }):Play()
			Debris:AddItem(cc, 0.3)
		end
		if rocks then rocks.drop() end
	end
	-- each stage of the charge surging in
	local function surge(n: number, f: Vector3)
		local g = if r0 then onGround(r0.Position) else pos
		floorRing(g, 3 + n * 2.2, 0.45, if n == 3 then HOT else CRIMSON, 0.5 + 0.25 * n)
		PackFX.Burst("Anime/Wind-02", CFrame.new(g + Vector3.new(0, 0.4, 0)), { scale = 0.6 + 0.35 * n })
		PackFX.Burst(if n >= 2 then "Big/Big-Crack-01" else "Anime/Crack-01", CFrame.new(g + Vector3.new(0, 0.1, 0)),
			{ color = CRIMSON, scale = if n >= 2 then 0.35 + 0.2 * n else 0.7 })
		PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(f, f + Vector3.yAxis), { color = INK, scale = 0.45 + 0.25 * n, light = 0 })
		flare(f, 2.5 + 1.5 * n, 0.18, HOT)
		motes:Emit(8 * n)
		ClassFX.Sound("fireBurst", f, 0.4 + 0.15 * n, 1.5 - 0.2 * n)
		if n == 2 then
			-- his eyes ignite; rubble lifts round him; lightning off the fist into the floor
			eyes = flameEyes(char)
			rocks = rubble(g, 8, 6, 2)
			for _ = 1, 3 do
				local o = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit * (1 + math.random() * 2)
				bolt(f, g + o, 0.14, 0.14, if math.random() < 0.3 then HOT else CRIMSON, 5)
			end
			ClassFX.Sound("thunder", f, 0.35, 1.6)
			ClassFX.Sound("rockHit", g, 0.5, 0.8)
		elseif n == 3 then
			-- full: it erupts
			shell(f, 1, 9, 0.3, CRIMSON)
			SwordFX.Rays(g + Vector3.new(0, 0.3, 0), 9, 14, CRIMSON, 0.35)
			PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(f, f + Vector3.yAxis), { color = INK, scale = 1.4, light = 0 })
			PackFX.Burst("Anime/Charge-01", CFrame.new(f), { color = CRIMSON, scale = 1.4 })
			punchRing(f, Vector3.yAxis, 2.6, 0.3, CRIMSON)
			ClassFX.Sound("ding", f, 0.6, 0.75)
			ClassFX.Sound("boom", f, 0.5, 1.4)
		end
		if mine and deps then
			deps.shake(0.08 + 0.1 * n, 0.12 + 0.04 * n)
			deps.fovPunch(2 + 2.5 * n, 0.35)
			if n == 3 then
				flash(0.15, 0.7)
				impactFrame(0.06)
			end
		end
	end
	animate(hold + 0.5, function()
		if stopped then return true end
		local f = fist()
		if not f then
			stopped = true
			cleanup(false)
			return true
		end
		local t = os.clock() - t0
		local c = math.min(t / full, 1)
		local pulse = 1 + math.sin(t * (14 + 18 * c)) * 0.12
		local cf = CFrame.new(f)
		core.CFrame, glow.CFrame, well.CFrame = cf, cf, cf
		aura.CFrame = cf * CFrame.Angles(t * 3, t * 7, 0)
		core.Size = Vector3.one * (0.3 + 0.9 * c) * pulse
		glow.Size = Vector3.one * (0.6 + 1.7 * c) * pulse
		aura.Size = Vector3.one * (1.2 + 2.6 * c)
		-- (more ink, more fire as it builds; the sequences only in steps)
		local stepK = math.floor(c * 4)
		if stepK ~= lastStep then
			lastStep = stepK
			local q = stepK / 4
			inkIn.Rate = 18 + 60 * q
			flame.Rate = 14 + 46 * q
			flame.Size = nseq(0, 0.5 + 0.6 * q, 0.3, 0.9 + 1.5 * q, 1, 0)
			if inkAura then inkAura.Rate = 50 * q end
			if fireAura then fireAura.Rate = 36 * q end
		end
		-- the three stages
		local want = if c >= 1 then 3 elseif c >= 0.66 then 2 elseif c >= 0.33 then 1 else 0
		while stage < want do
			stage += 1
			surge(stage, f)
		end
		if cc then
			cc.Saturation = -0.35 * c
			cc.Contrast = 0.25 * c
			cc.Brightness = -0.04 * c
			cc.TintColor = WHITE:Lerp(Color3.fromRGB(255, 205, 205), c)
		end
		-- ink strokes curling in round the arm
		if t >= nextCurl then
			nextCurl = t + 0.15 - 0.08 * c
			inkCurl(fist, 2.1 + math.random() * 0.9, 0.2 + 0.25 * c, 0.3)
		end
		-- air dragged in round him, harder as it builds
		if c > 0.15 and t >= nextAir then
			nextAir = t + 0.12 - 0.06 * c
			inkCurl(body, 5 + math.random() * 3, 0.18 + 0.15 * c, 0.42, "air")
		end
		-- red lightning crackling off it, from the first stage on
		if c > 0.33 and t >= nextBolt then
			nextBolt = t + 0.09 - 0.04 * c
			local out = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
			bolt(f + out * 0.4, f + out * (1.1 + 1.6 * c), 0.08 + 0.04 * c, 0.06, if math.random() < 0.3 then HOT else CRIMSON, 3)
		end
		return nil
	end)
	return {
		stop = function(burst: boolean)
			if stopped then return end
			stopped = true
			cleanup(burst)
		end,
	}
end

-- 3 · The full charge's ink splash where the fist lands.
local function inkSplash(at: Vector3, radius: number, dir: Vector3, mine: boolean)
	local g = onGround(at)
	local mid = Vector3.new(at.X, g.Y + 1.3, at.Z)
	PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(mid, mid + dir), { color = INK, scale = 1.6 + radius * 0.08, light = 0 })
	PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(mid, mid + Vector3.yAxis), { color = INK, scale = 1.3, light = 0 })
	PackFX.Burst("Anime/Blood-01", CFrame.new(g + Vector3.new(0, 0.1, 0)), { color = INK, scale = radius / 3, light = 0 })
	PackFX.Burst("Big/Big-Crack-01", CFrame.new(g + Vector3.new(0, 0.1, 0)), { color = CRIMSON, scale = radius / 10 })
	shell(mid, 1, radius * 2, 0.3, CRIMSON)
	flare(mid, radius * 1.1, 0.2, HOT)
	SwordFX.Rays(g + Vector3.new(0, 0.3, 0), radius * 1.4, 12, CRIMSON, 0.3)
	floorRing(g, radius, 0.4, CRIMSON, 1.0)
	-- great strokes of ink thrown out from it
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + math.random() * 0.5
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		inkStroke(mid + out * 0.6, mid + out * radius * (0.7 + math.random() * 0.4) + Vector3.new(0, (math.random() - 0.3) * 2, 0),
			0.9 + math.random() * 0.6, 0.45, (math.random() - 0.5) * 3, 0.07)
	end
	if FxBudget.Allow("maInkSplash", 3) then
		PackFX.Burst("Anime/Blood-02", CFrame.new(mid), { color = INK, scale = 1.4, count = 2, light = 0 })
		inkDrops(mid, 16, radius, dir)
	end
	ClassFX.Sound("boom", g, 0.7, 1.1)
	ClassFX.Sound("punch", g, 0.9, 0.6)
	ClassFX.Sound("fireBurst", g, 0.5, 0.9)
	if mine and deps then
		deps.shake(0.7, 0.25)
		deps.fovPunch(7, 0.25)
		impactFrame(0.09)
	end
end

-- 2 · The release (and, fully charged, the splash as the fist lands). `pos`
-- where he stood, `lunge` how far he goes, `c` the charge (0..1).
local function focusReleaseFx(pos: Vector3, dir: Vector3, c: number, full: boolean, lunge: number, splash: number, mine: boolean)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local fist = pos + dir * (lunge + 2.8) + Vector3.new(0, 0.6, 0)
	-- the lunge: strokes of ink dragged along it behind the fist
	local from = pos + Vector3.new(0, 0.6, 0) - dir
	for _ = 1, (if full then 3 else 2) do
		local off = side * (math.random() - 0.5) * 1.2 + Vector3.new(0, (math.random() - 0.5) * 0.8, 0)
		inkStroke(from + off, fist + off * 0.4, 0.45 + 0.55 * c, 0.3 + 0.25 * c, (math.random() - 0.5) * 2, FOCUS.hit)
	end
	ClassFX.Sound("whoosh", pos, 0.5, 0.85)
	task.delay(FOCUS.hit, function()
		-- the punch: rings of air bursting off it, a crimson crescent, ink off the fist
		punchRing(fist, dir, 1.1 + 0.8 * c, 0.2, CRIMSON)
		task.delay(0.04, function() punchRing(fist + dir * (1.4 + c), dir, 1.6 + 1.4 * c, 0.26, HOT) end)
		flare(fist, 2.5 + 3 * c, 0.16, HOT)
		SwordFX.Arc({ cf = CFrame.lookAt(fist - dir, fist + dir) * CFrame.Angles(0, 0, math.rad(80)), radius = 2 + c, arc = 130,
			width = 0.6 + 0.4 * c, color = CRIMSON, life = 0.2, draw = 0.04, grow = 0.4, core = HOT })
		PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(fist, fist + dir), { color = INK, scale = 0.45 + 0.5 * c, light = 0 })
		if FxBudget.Allow("maFocusPack", 4) then
			PackFX.Burst("Anime/Wind-02", CFrame.lookAt(fist, fist + dir), { color = CRIMSON, scale = 0.5 + 0.4 * c })
		end
		sparks(fist, 10 + math.floor(16 * c), 18 + 14 * c, CRIMSON)
		ClassFX.Sound("punch", fist, 0.6 + 0.3 * c, 1.05 - 0.3 * c)
		if mine and deps then
			deps.shake(0.15 + 0.3 * c, 0.1)
			deps.fovPunch(2 + 4 * c, 0.18)
		end
		if full then inkSplash(pos + dir * (lunge + 5), splash, dir, mine) end
	end)
end

-- Everyone's: the ink bursting off whoever the fist hit.
local function onFocusLanded(msg: any)
	local dir = flat((msg.dir :: Vector3?) or Vector3.new(0, 0, -1))
	local c = tonumber(msg.charge) or 0
	local hits = msg.hits or {}
	for i, p in ipairs(hits) do
		if i > 6 or not FxBudget.Allow("maInkHit", 16) then break end
		local at = (p :: Vector3) + Vector3.new(0, 0.5, 0)
		PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(at, at + dir), { color = INK, scale = 0.7 + 0.5 * c, light = 0 })
		flare(at, 2.5 + 2 * c, 0.14, HOT)
		sparks(at, 8, 16, CRIMSON)
		if FxBudget.Allow("maPunchPack", 6) then
			PackFX.Burst("Anime/Punch-02", CFrame.lookAt(at, at + dir), { color = CRIMSON, scale = 0.8 })
		end
	end
	if #hits > 0 and msg.attacker == player and deps then deps.shake(0.2 + 0.3 * c, 0.08) end
end

-- Everyone else's Focus Strike: the charge, then the release.
local charging: { [Player]: Handle } = {}
local function onFocusCharge(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	local char = charOf(owner)
	if not char then return end
	local full = tonumber(msg.full) or FOCUS.full
	local hold = tonumber(msg.hold) or FOCUS.hold
	focusPose(char, hold, full)
	local old = charging[owner]
	if old then old.stop(false) end
	charging[owner] = focusChargeFx(char, full, hold, false)
end

local function onFocusRelease(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	local c = tonumber(msg.charge) or 0
	local full = msg.full == true
	local h = charging[owner]
	charging[owner] = nil
	if h then h.stop(full) end
	local char = charOf(owner)
	if char then focusPunchPose(char, c) end
	focusReleaseFx(msg.pos :: Vector3, flat(msg.dir :: Vector3), c, full, tonumber(msg.lunge) or 0, tonumber(msg.splash) or FOCUS.splash, false)
end

-- Ours: charged while the key is down.
type Focusing = { t0: number, full: number, char: Model, root: BasePart, fx: Handle, token: {} }
local focusing: Focusing? = nil

local function startFocus(char: Model, root: BasePart, empowered: boolean)
	local full = if empowered then FOCUS.empFull else FOCUS.full
	local token = {}
	busyUntil = math.huge
	focusPose(char, FOCUS.hold, full)
	focusing = { t0 = os.clock(), full = full, char = char, root = root, fx = focusChargeFx(char, full, FOCUS.hold, true), token = token }
	-- (creeping about at a slow walk while it charges, always turned to the aim)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.AutoRotate = false end
	animate(FOCUS.hold, function()
		local f = focusing
		if not f or f.token ~= token then return true end
		if hum then hum.WalkSpeed = FOCUS.walk end
		if root.Parent and deps then
			local d = flat(deps.getAim(root))
			root.CFrame = CFrame.lookAt(root.Position, root.Position + d)
		end
		return nil
	end)
	-- (held all the way: it goes off on its own)
	task.delay(FOCUS.hold, function()
		local f = focusing
		if f and f.token == token then MartialController.Release(1) end
	end)
end

-- ── Q: Ground Slam ──────────────────────────────────────────────────────────
-- His flight (every client draws it from the same numbers): straight up,
-- along over the path, down onto the landing.
-- The flight: up (drifting a little toward the spot, slowing at the top),
-- a beat hanging there, then a dive in a straight diagonal line onto the
-- spot, faster and faster.
local function ascentPath(from: Vector3, to: Vector3, stand: number): (number) -> Vector3
	local T = ASCENT
	local o = from + Vector3.new(0, stand, 0)
	local land = to + Vector3.new(0, stand, 0)
	local apex = o + flat(to - from) * math.min(1.5, Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude * 0.2)
		+ Vector3.new(0, ASCENT_HEIGHT, 0)
	local top = apex + Vector3.new(0, 0.6, 0)
	return function(t: number): Vector3
		if t < T.rise then
			return o:Lerp(apex, easeOut(t / T.rise))
		elseif t < T.rise + T.dash then
			return apex:Lerp(top, (t - T.rise) / T.dash)
		else
			return top:Lerp(land, easeIn(math.min((t - T.rise - T.dash) / T.fall, 1)))
		end
	end
end

type Mover = { set: (Vector3) -> (), face: (Vector3) -> (), stop: () -> (), alive: () -> boolean, stand: number }
local function holdBody(char: Model, root: BasePart): Mover?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local stand = SafeMove.StandHeight(root)
	local att = Instance.new("Attachment")
	att.Name = "MartialMove"
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
		set = function(p: Vector3)
			if stopped then return end
			ap.Position = p
			if root.Parent then root.CFrame = CFrame.new(p) * root.CFrame.Rotation end
		end,
		face = function(d: Vector3)
			local f = Vector3.new(d.X, 0, d.Z)
			if f.Magnitude > 0.05 and not stopped then ao.CFrame = CFrame.lookAt(Vector3.zero, f.Unit) end
		end,
		alive = function() return not stopped and root.Parent ~= nil and hum.Health > 0 end,
		stop = function()
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
				SafeMove.SnapToFloor(root, stand)
			end
		end,
	}
end

-- (ours: flown on our screen, the landing returned for the server)
local function ascentFly(char: Model, root: BasePart, dir: Vector3, cursor: Vector3?, range: number): Vector3?
	local mv = holdBody(char, root)
	if not mv then return nil end
	local origin = root.Position
	local want = range
	if cursor then
		want = math.min(Vector3.new(cursor.X - origin.X, 0, cursor.Z - origin.Z).Magnitude, range)
	end
	local dist = math.min(SafeMove.ClampDash(root, dir, want), SafeMove.ClampToFloor(root, dir, want))
	local landXZ = origin + dir * dist
	local from = onGround(origin)
	local to = onGround(landXZ)
	local path = ascentPath(from, to, mv.stand)
	mv.face(dir)
	local T = ASCENT
	local total = T.rise + T.dash + T.fall
	-- (the camera keeps the floor in view while he's up there)
	if IsometricCamera then pcall(IsometricCamera.SetFocusYLock, origin.Y + 2) end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.min(os.clock() - t0, total)
		if mv.alive() then mv.set(path(t)) end
		if t >= total then
			conn:Disconnect()
			mv.set(path(total))
			mv.stop()
			if IsometricCamera then pcall(IsometricCamera.SetFocusYLock, nil) end
		end
	end)
	return to
end

-- 1 · Ascend: a pillar of Qi under him, light streaming up, the dragon
-- spiralling up round him. 2 · Strike: he rides it over the path, a slash
-- of light through everything on it (Empowered: three dragons crossing).
-- 3 · Impact: an explosion where he lands. 4 · End: the dragon's path
-- hangs in the air as a ribbon of fire, and the ground burns along it.
local function onAscent(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	if char and owner ~= player then ascentPose(char) end
	local from = msg.from :: Vector3
	local to = msg.to :: Vector3
	local radius = tonumber(msg.radius) or 9
	local width = tonumber(msg.width) or 4
	local trailFor = tonumber(msg.trail) or 2.5
	local emp = msg.empowered == true
	local T = ASCENT
	local total = T.rise + T.dash + T.fall
	local dir = flat(to - from)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local path = ascentPath(from, to, 3)
	-- 1 · the pillar
	local tall = ASCENT_HEIGHT + 6
	local pillar = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(tall, 3, 3), Color = HOT, Transparency = 0.2,
		CFrame = CFrame.new(from + Vector3.new(0, tall / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	local glow = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(tall, 6, 6), Color = CRIMSON, Transparency = 0.6,
		Material = Enum.Material.ForceField, CFrame = pillar.CFrame })
	TweenService:Create(pillar, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(tall + 4, 0.1, 0.1), Transparency = 1 }):Play()
	TweenService:Create(glow, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(tall + 4, 9, 9), Transparency = 1 }):Play()
	Debris:AddItem(pillar, 0.5)
	Debris:AddItem(glow, 0.55)
	local pad = part({ Size = Vector3.new(4, 0.2, 4), CFrame = CFrame.new(from + Vector3.new(0, 0.2, 0)), Transparency = 1 })
	local rising = emitter(pad, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, CRIMSON), LightEmission = 1,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Size = nseq(0, 0.5, 1, 0.1), Lifetime = NumberRange.new(0.35, 0.5),
		Speed = NumberRange.new(26, 34), SpreadAngle = Vector2.new(6, 6), EmissionDirection = Enum.NormalId.Top, Rate = 90,
		Shape = Enum.ParticleEmitterShape.Box })
	task.delay(T.rise + 0.05, function() rising.Enabled = false end)
	Debris:AddItem(pad, 1)
	floorRing(from, 4.5, 0.35, CRIMSON, 0.8)
	PackFX.Burst("Anime/Wind-02", CFrame.new(from + Vector3.new(0, 0.3, 0)), { color = CRIMSON, scale = 0.9 })
	PackFX.Burst("Anime/Crack-01", CFrame.new(from + Vector3.new(0, 0.1, 0)), { color = CRIMSON, scale = 0.5 })
	ClassFX.Sound("whoosh", from, 0.8, 0.8)
	ClassFX.Sound("fireWhoosh", from, 0.6, 1)
	-- the dragons (the middle one also draws the trail of fire that hangs
	-- in the air after it, all the way round the spiral and over the path)
	local count = if emp then 3 else 1
	local linger = carrier(CFrame.new(from))
	ribbon(linger, Vector3.zero, 2.2, trailFor, ColorSequence.new({ ColorSequenceKeypoint.new(0, HOT), ColorSequenceKeypoint.new(0.4, CRIMSON),
		ColorSequenceKeypoint.new(1, BLOOD) }), nseq(0, 0.1, 0.6, 0.35, 1, 1), nseq(0, 0.8, 0.5, 1, 1, 0.3), TEX_WISPS, 4, 0.9)
	ribbon(linger, Vector3.zero, 0.9, trailFor, ColorSequence.new(CRIMSON, BLOOD), nseq(0, 0.25, 0.7, 0.55, 1, 1), nseq(0, 0.6, 0.4, 1, 1, 0.2), nil, nil, 0.7)
	ribbon(linger, Vector3.zero, 0.35, trailFor * 0.8, ColorSequence.new(WHITE, CRIMSON), nseq(0, 0.2, 1, 1), nil, TEX_FLICKER, 3)
	Debris:AddItem(linger, total + trailFor + 0.5)
	for k = 1, count do
		local off = (k - (count + 1) / 2) * 3.2
		local phase = k * 2.1
		local dragon = newDragon(if k == math.ceil(count / 2) then 0.85 else 0.65, from, Vector3.yAxis, 0.32)
		dragon.jaw(0.8)
		local main = k == math.ceil(count / 2)
		local function headAt(t: number): Vector3
			if t < T.rise then
				local u = t / T.rise
				local ang = u * math.pi * 2.4 + phase
				return from + Vector3.new(math.cos(ang) * 2.6, 0.5 + u * (ASCENT_HEIGHT + 2.5), math.sin(ang) * 2.6)
			elseif t < total then
				local u = math.min((t - T.rise) / (T.dash + T.fall), 1)
				local p = path(math.min(t + 0.06, total))
				-- (the outer two cross over the path, side to side)
				return p + dir * 2.5 + side * off * math.cos(u * math.pi)
			else
				-- into the ground and gone
				local u = (t - total) / 0.3
				return to + dir * (2.5 + u * 3) + Vector3.new(0, 1.5 - u * 5, 0)
			end
		end
		animate(total + 0.35, function(a)
			local t = a * (total + 0.35)
			local p = headAt(t)
			local q = headAt(t + 0.03)
			dragon.move(p, q - p)
			dragon.set(math.min(t / 0.06, 1) * (if t > total then 1 - (t - total) / 0.35 else 1))
			if main and t <= total + 0.05 then linger.CFrame = CFrame.new(p) end
			if a >= 1 then dragon.destroy() end
			return nil
		end)
	end
	-- 2 · the slash of light through the path, as he dives
	task.delay(T.rise + T.dash + T.fall * 0.5, function()
		streak(from + Vector3.new(0, 1.2, 0), to + Vector3.new(0, 1.2, 0), width * 0.5, 0.35, CRIMSON)
		if emp then
			streak(from + side * 3 + Vector3.new(0, 1.2, 0), to - side * 3 + Vector3.new(0, 1.2, 0), width * 0.35, 0.35, HOT)
			streak(from - side * 3 + Vector3.new(0, 1.2, 0), to + side * 3 + Vector3.new(0, 1.2, 0), width * 0.35, 0.35, HOT)
		end
		ClassFX.Sound("swordHit", to, 0.5, 1.3)
	end)
	-- 3 · the landing, 4 · the lingering trail
	task.delay(total, function()
		local g = to + Vector3.new(0, 0.2, 0)
		shell(g, 2, radius * 2.4, 0.4, CRIMSON)
		flare(g + Vector3.new(0, 1, 0), radius * 1.4, 0.3)
		floorRing(to, radius, 0.45, CRIMSON, 1.2)
		floorRing(to, radius * 0.6, 0.35, HOT, 0.8)
		PackFX.Burst("Big/Explosion-01", CFrame.new(g), { color = CRIMSON, scale = radius / 10, count = 0.6 })
		PackFX.Burst("Big/Big-Crack-01", CFrame.new(g), { color = BLOOD, scale = radius / 12 })
		SwordFX.Rays(g + Vector3.new(0, 0.5, 0), radius * 1.4, 14, HOT, 0.35)
		sparks(g, 40, 34)
		ClassFX.Sound("quake", g, 0.7, 1.1)
		ClassFX.Sound("boom", g, 0.8, 1)
		if owner == player and deps then
			deps.shake(0.9, 0.25)
			deps.fovPunch(6, 0.25)
		elseif near(g, 50) and deps then
			deps.shake(0.3, 0.15)
		end
		-- the ground burning along the path (the fire in the air hangs on
		-- the middle dragon's trail)
		local len = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
		local n = math.clamp(math.floor(len / 3.5), 1, 9)
		for i = 1, n do
			local p = onGround(from:Lerp(to, (i - 0.5) / n)) + Vector3.new(0, 0.3, 0)
			PackFX.Run("Anime/Fire-02", CFrame.new(p), trailFor * (0.7 + math.random() * 0.3), { color = CRIMSON, scale = width / 5 })
		end
	end)
end

-- ── F: Electric Uppercut ────────────────────────────────────────────────────
-- After the Wind God Fist. 1 · Crouch dash: he drops and darts in low, a
-- trail of afterimages behind him, lightning dragged along the floor and
-- crackling round the fist down by his knee. 2 · Uppercut: up out of the
-- crouch, the fist driven at the sky wrapped in arcs of blue and red
-- lightning. 3 · Impact + launch: a sharp white flash, a pillar of
-- lightning, shards of light bursting up out of the floor; everyone hit is
-- thrown up with lightning running over them (and, Empowered, jumping on to
-- the next).

-- His move (ours: moved on our screen): in place for the drop, the dash in
-- low, a short step on into the uppercut; never off the floor. Returns how
-- far the dash went.
local function uppercutFly(char: Model, root: BasePart, dir: Vector3): number
	local U = UPPER
	local mv = holdBody(char, root)
	if not mv then return 0 end
	local reach = math.min(SafeMove.ClampDash(root, dir, U.range + 0.5), SafeMove.ClampToFloor(root, dir, U.range + 0.5))
	local dash = math.min(reach, U.range)
	local o = root.Position
	-- the first enemy in the lane stops it, just short of them
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then
		for _, m in ipairs(mobs:GetChildren()) do
			local hum = m:FindFirstChildOfClass("Humanoid")
			local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and r and hum.Health > 0 then
				local rel = Vector3.new(r.Position.X - o.X, 0, r.Position.Z - o.Z)
				local along = rel:Dot(dir)
				if along > 0 and along <= dash + U.stopShort and (rel - dir * along).Magnitude <= U.lane + r.Size.X * 0.5
					and math.abs(r.Position.Y - o.Y) < 7 then
					dash = math.clamp(along - U.stopShort, 0, dash)
				end
			end
		end
	end
	local dashEnd = o + dir * dash
	local stepEnd = o + dir * math.min(reach, dash + 0.5)
	mv.face(dir)
	local t0 = os.clock()
	local a1 = U.crouch
	local a2 = a1 + U.dash
	animate(U.total, function()
		local t = os.clock() - t0
		local p: Vector3
		if t < a1 then
			p = o
		elseif t < a2 then
			p = o:Lerp(dashEnd, easeOut((t - a1) / U.dash))
		else
			p = dashEnd:Lerp(stepEnd, easeOut(math.min((t - a2) / U.swing, 1)))
		end
		if mv.alive() then mv.set(p) end
		if t >= U.total then
			mv.stop()
			return true
		end
		return nil
	end)
	return dash
end

-- Blue lightning, now and then red (the Wind God Fist's).
local function voltColor(): Color3
	local r = math.random()
	return if r < 0.25 then CRIMSON elseif r < 0.45 then ARC else VOLT
end

-- "kaz electric": the effect the user made for the uppercut (in the place,
-- not in code: found by name in ReplicatedStorage, or the VFX showcase in
-- Workspace, once). A copy rides on him through the dash and the rise,
-- every emitter and beam in it lit, then dies away.
local kazTemplate: Instance? = nil
local kazSearched = false
local function findKaz(): Instance?
	if kazTemplate and kazTemplate.Parent then return kazTemplate end
	if kazSearched then return nil end
	kazSearched = true
	local function named(inst: Instance): boolean
		local n = string.lower(inst.Name)
		return string.find(n, "kaz", 1, true) ~= nil and (inst:IsA("BasePart") or inst:IsA("Model") or inst:IsA("Attachment") or inst:IsA("Folder"))
	end
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if named(d) then kazTemplate = d return d end
	end
	-- (the showcase in the sky: only two levels down, never the whole Workspace)
	for _, c in ipairs(Workspace:GetChildren()) do
		if named(c) then kazTemplate = c return c end
		if c:IsA("Folder") or c:IsA("Model") then
			for _, cc in ipairs(c:GetChildren()) do
				if named(cc) then kazTemplate = cc return cc end
			end
		end
	end
	warn("[MartialController] no 'kaz electric' effect found in ReplicatedStorage or Workspace")
	return nil
end

local function kazFx(char: Model, seconds: number)
	local t = findKaz()
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (t and root) then return end
	local holder = Instance.new("Part")
	holder.Name = "KazElectric"
	holder.Size = Vector3.one * 0.2
	holder.Transparency = 1
	holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow, holder.Massless = false, false, false, false, true
	holder.CFrame = root.CFrame
	local c = t:Clone()
	local emitters: { ParticleEmitter } = {}
	local longest = 0
	local function take(d: Instance)
		if d:IsA("ParticleEmitter") then
			table.insert(emitters, d)
			longest = math.max(longest, d.Lifetime.Max)
		elseif d:IsA("Beam") or d:IsA("Trail") then
			(d :: any).Enabled = true
		elseif d:IsA("Light") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.Transparency = 1
			d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow, d.Massless = false, false, false, false, true
		end
	end
	if c:IsA("BasePart") then
		take(c)
		for _, d in ipairs(c:GetDescendants()) do take(d) end
		c.CFrame = root.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = holder, c
		w.Parent = c
		c.Parent = holder
	elseif c:IsA("Model") then
		for _, d in ipairs(c:GetDescendants()) do take(d) end
		c:PivotTo(root.CFrame)
		for _, d in ipairs(c:GetDescendants()) do
			if d:IsA("BasePart") then
				local w = Instance.new("WeldConstraint")
				w.Part0, w.Part1 = holder, d
				w.Parent = d
			end
		end
		c.Parent = holder
	else
		-- an attachment or a folder of them: hung on the holder as they are
		for _, d in ipairs(c:GetDescendants()) do take(d) end
		take(c)
		c.Parent = holder
		if c:IsA("Attachment") then c.CFrame = CFrame.identity end
	end
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = root, holder
	weld.Parent = holder
	holder.Parent = char
	for _, e in ipairs(emitters) do
		e.Enabled = true
		local n = tonumber(e:GetAttribute("EmitCount"))
		if n and n > 0 then e:Emit(n) end
	end
	task.delay(seconds, function()
		for _, e in ipairs(emitters) do
			if e.Parent then e.Enabled = false end
		end
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("Beam") or d:IsA("Trail") then (d :: any).Enabled = false end
		end
		Debris:AddItem(holder, longest + 0.2)
	end)
end

local function uppercutFx(char: Model?, pos: Vector3, dir: Vector3, dash: number, mine: boolean)
	local U = UPPER
	if char then kazFx(char, U.crouch + U.dash + U.swing + U.rise + U.hang + 0.15) end
	local g0 = onGround(pos)
	local g = onGround(pos + dir * dash)
	local hitAt = g + dir * 1.2 + Vector3.new(0, 4.5, 0)
	-- 1 · the drop: a crack of lightning at the fist, dust and a ring off the floor
	if char then
		local f = fistOf(char, "Right Arm")
		if f then
			PackFX.Burst("Anime/Lighting-03", CFrame.new(f), { color = VOLT, scale = 0.6 })
			bolt(f, g0 + dir * 0.5, 0.12, 0.08, VOLT, 3)
		end
		local arm = char:FindFirstChild("Right Arm") :: BasePart?
		if arm then
			local tr = ribbon(arm, Vector3.new(0, -0.95, 0), 0.8, 0.22, ColorSequence.new(ARC, VOLT), nseq(0, 0, 1, 1), nseq(0, 1, 1, 0.2),
				TEX_FLICKER, 2, 1)
			task.delay(U.total, function()
				tr.Enabled = false
				for _, a in ipairs({ tr.Attachment0, tr.Attachment1 }) do
					if a then Debris:AddItem(a, 0.3) end
				end
				Debris:AddItem(tr, 0.3)
			end)
		end
	end
	floorRing(g0, 2.6, 0.25, VOLT, 0.5)
	if FxBudget.Allow("maDashDust", 4) then
		PackFX.Burst("Anime/Smoke-01", CFrame.new(g0 + Vector3.new(0, 0.4, 0)), { color = Color3.fromRGB(120, 120, 140), scale = 0.5 })
	end
	ClassFX.Sound("whoosh", pos, 0.6, 1.3)
	ClassFX.Sound("charge", pos, 0.3, 2.2, 0.3)
	-- 2 · the crouch dash: afterimages behind him, lightning dragged along
	-- the floor under him and crackling round the low fist
	task.delay(U.crouch, function()
		if char then ClassFX.Afterimages(char, VOLT, 4, U.dash / 4) end
		local a, b = g0 + Vector3.new(0, 0.3, 0), g + Vector3.new(0, 0.3, 0)
		bolt(a, b, 0.2, 0.22, VOLT, 7)
		bolt(a, b, 0.09, 0.18, CRIMSON, 7)
		SwordFX.Streak(a + Vector3.new(0, 0.5, 0), b + Vector3.new(0, 0.5, 0), 0.6, VOLT, 0.1, 4, ARC)
	end)
	-- arcs of lightning round the fist through the dash, then wrapped round
	-- him as he rises
	local t0 = os.clock()
	local nextArc = 0
	animate(U.crouch + U.dash + U.swing + U.rise + U.hang, function()
		local t = os.clock() - t0
		if t < nextArc or not char then return nil end
		nextArc = t + 0.035
		if t < U.crouch + U.dash then
			local f = fistOf(char, "Right Arm")
			if f then
				for _ = 1, 2 do
					local out = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
					bolt(f + out * 0.3, f + out * (1 + math.random()), 0.09, 0.06, voltColor(), 3)
				end
			end
		else
			local r = rootOf(char)
			if r then
				for _ = 1, 2 do
					local q1 = math.random() * math.pi * 2
					local q2 = q1 + (math.random() - 0.5) * 2.2
					local p1 = r.Position + Vector3.new(math.cos(q1) * 1.5, -2 + math.random() * 2, math.sin(q1) * 1.5)
					local p2 = r.Position + Vector3.new(math.cos(q2) * 1.7, 0.5 + math.random() * 3, math.sin(q2) * 1.7)
					bolt(p1, p2, 0.11, 0.07, voltColor(), 4)
				end
			end
		end
		return nil
	end)
	-- 3 · the impact: the flash, the pillar of lightning, shards out of the floor
	task.delay(U.hit, function()
		flare(hitAt, 6.5, 0.12, ARC)
		shell(hitAt, 1, 7, 0.2, VOLT)
		PackFX.Burst("Big/Lighting-01", CFrame.new(g + Vector3.new(0, 0.2, 0)), { color = VOLT, scale = 0.45 })
		PackFX.Burst("Anime/Lighting-02", CFrame.new(hitAt), { color = CRIMSON, scale = 0.8 })
		for k = 1, 4 do
			local o = Vector3.new((math.random() - 0.5) * 1.4, 0, (math.random() - 0.5) * 1.4)
			bolt(g + o, hitAt + o + Vector3.new(0, 6 + math.random() * 4, 0), if k == 1 then 0.35 else 0.15, 0.2,
				if k == 4 then CRIMSON else VOLT, 7)
		end
		shards(g + dir * 1.2, 11, 4.5, VOLT)
		punchRing(hitAt, Vector3.yAxis, 1.7, 0.22, ARC)
		floorRing(g, 4, 0.3, VOLT, 0.7)
		sparks(hitAt, 22, 26, ARC)
		ClassFX.Sound("thunder", hitAt, 0.7, 1.25)
		ClassFX.Sound("punch", hitAt, 0.6, 0.9)
		if mine and deps then
			deps.shake(0.35, 0.14)
			deps.fovPunch(5, 0.2)
		end
	end)
end

local function onUppercut(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	local char = charOf(owner)
	if char then uppercutPose(char) end
	uppercutFx(char, msg.pos :: Vector3, flat(msg.dir :: Vector3), tonumber(msg.dash) or UPPER.reach, false)
end

-- Everyone it hit: lightning from the fist to them, thrown up with lightning
-- running over them; the chain jumping on from one to the next.
local function onUppercutHit(msg: any)
	local at = (msg.pos :: Vector3) + Vector3.new(0, 1.5, 0)
	local hits = msg.hits or {}
	for i, p in ipairs(hits) do
		if i > 6 or not FxBudget.Allow("maVolt", 14) then break end
		local tp = p :: Vector3
		bolt(at, tp + Vector3.new(0, 1, 0), 0.22, 0.12, VOLT, 5)
		PackFX.Burst("Anime/Lighting-01", CFrame.new(tp), { color = VOLT, scale = 0.7 })
		SwordFX.Streak(tp - Vector3.new(0, 1.5, 0), tp + Vector3.new(0, 7, 0), 0.5, VOLT, 0.12, 3, ARC)
		floorRing(onGround(tp), 2.2, 0.3, VOLT, 0.5)
		crackle(tp, 0.6, true)
		sparks(tp, 12, 18, ARC)
	end
	for i, l in ipairs(msg.links or {}) do
		local a, b = (l[1] :: Vector3) + Vector3.new(0, 1, 0), (l[2] :: Vector3) + Vector3.new(0, 1, 0)
		task.delay((i - 1) * 0.06, function()
			if not FxBudget.Allow("maChain", 20) then return end
			bolt(a, b, 0.25, 0.16, VOLT, 6)
			bolt(a, b, 0.1, 0.12, ARC, 6)
			PackFX.Burst("Anime/Lighting-03", CFrame.new(b), { color = VOLT, scale = 0.6 })
			crackle(b, 0.4, false)
			ClassFX.Sound("thunder", b, 0.35, 1.5)
		end)
	end
	if #hits > 0 and msg.attacker == player and deps then deps.shake(0.25, 0.1) end
end

-- ── R: Crimson Hadouken ─────────────────────────────────────────────────────
-- 1 · Charge: crouched and wound away, the sphere forming in his right hand
-- (fire and black ink round a white-hot core, red lightning cracking off
-- it), red energy and ink swirling in to it, and the air going wild round
-- him: a column of wind spinning up off the floor, air drawn in to him in
-- streaks from all round, pressure pulsing out over the floor, a crimson
-- circle burning in round an ink pool, the rubble lifting. 2 · Thrust: both
-- palms driven forward, an air blast off them, the rubble thrown after it.
-- 3 · Projectile: one big sphere after the pack's Ball-01 (its fire, black
-- ash and embers round a white-hot heart), its tail streaming out behind
-- it, rings of air and streaks of wind thrown off it, dust torn up off the
-- floor, red lightning lashing off it, the floor scorched under it;
-- everyone it passes through bursts in ink; it explodes where it ends.

-- A circle of crimson burning into the floor round `pos` for `dur` (two
-- rings, the spokes between them, turning), round a ring of ink.
local function sigil(pos: Vector3, dur: number)
	local parts: { BasePart } = {}
	local rel: { CFrame } = {}
	for i, r in ipairs({ 5, 9 }) do
		local n = math.floor(r * 4)
		for j = 1, n do
			local a = j / n * math.pi * 2
			table.insert(parts, part({ Size = Vector3.new(2 * math.pi * r / n * 1.12, 0.06, 0.45 - i * 0.1), Color = if i == 1 then HOT else CRIMSON,
				Transparency = 1 }))
			table.insert(rel, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r))
		end
	end
	for j = 1, 8 do
		local a = j / 8 * math.pi * 2
		table.insert(parts, part({ Size = Vector3.new(0.2, 0.06, 4), Color = CRIMSON, Transparency = 1 }))
		table.insert(rel, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -7))
	end
	local cfs = table.create(#parts)
	animate(dur, function(a)
		local t = a * dur
		local alpha = if t < 0.25 then t / 0.25 elseif t < dur - 0.4 then 1 else math.max(0, (dur - t) / 0.4)
		local pulse = 0.25 + math.sin(t * 16) * 0.1
		local base = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, t * 1.2, 0)
		for i, p in ipairs(parts) do
			cfs[i] = base * rel[i]
			p.Transparency = 1 - (1 - pulse) * alpha
		end
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if a >= 1 then
			for _, p in ipairs(parts) do p:Destroy() end
		end
		return nil
	end)
end

-- 1 · The charge round `char` (facing `dir`) for `charge` seconds.
local function hadoChargeFx(char: Model, dir: Vector3, charge: number, mine: boolean)
	local root = rootOf(char)
	if not root then return end
	local pos = onGround(root.Position)
	-- (the sphere cupped between his hands in front of his belly)
	local function hands(): Vector3?
		return if char.Parent then handsOf(char) else nil
	end
	local function body(): Vector3?
		return if root.Parent then root.Position else nil
	end
	if mine or near(pos, 90) then tint(charge + 0.7) end
	sigil(pos, charge + 0.5)
	PackFX.Burst("Anime/Blood-01", CFrame.new(pos + Vector3.new(0, 0.1, 0)), { color = INK, scale = 3, light = 0 })
	PackFX.Burst("Big/Big-Crack-01", CFrame.new(pos + Vector3.new(0, 0.1, 0)), { color = CRIMSON, scale = 0.9 })
	PackFX.Burst("Anime/Smoke-01", CFrame.new(pos + Vector3.new(0, 0.6, 0)), { color = Color3.fromRGB(120, 112, 118), scale = 1.3 })
	local rocks = rubble(pos, 12, 11, 3.5)
	task.delay(charge, function() rocks.throw(dir) end)
	-- the air: a column of wind spinning up off the floor round him (the
	-- pack's tornado, turned over to rise from his feet)
	PackFX.Run("Big/Tornado-01", CFrame.new(pos + Vector3.new(0, 0.4, 0)) * CFrame.Angles(math.pi, 0, 0), charge, { scale = 0.55 })
	-- light and ink rushing in to him from all round
	local gather = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 18, CFrame = CFrame.new(pos + Vector3.new(0, 2.5, 0)), Transparency = 1 })
	local inward = emitter(gather, { Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, CRIMSON), LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.4), Speed = NumberRange.new(20, 23), Size = nseq(0, 0.5, 1, 0.1), Transparency = nseq(0, 0.6, 1, 0), Rate = 70 })
	local inkward = emitter(gather, { Texture = TEX_INK, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(INK), LightEmission = 0,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Lifetime = NumberRange.new(0.45), Speed = NumberRange.new(18, 20),
		Size = nseq(0, 1.2, 1, 2.2), Transparency = nseq(0, 0.7, 0.4, 0.1, 1, 0.5), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-100, 100), Rate = 26 })
	task.delay(charge, function()
		inward.Enabled, inkward.Enabled = false, false
		Debris:AddItem(gather, 0.6)
	end)
	-- the sphere forming between his hands
	local at = hands() or root.Position
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, Color = HOT, CFrame = CFrame.new(at) })
	local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, Color = CRIMSON, Transparency = 0.55, CFrame = CFrame.new(at) })
	local field = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.9, Color = CRIMSON, Material = Enum.Material.ForceField,
		Transparency = 0.1, CFrame = CFrame.new(at) })
	local fire = emitter(core, { Texture = TEX_FLAME, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(CRIMSON), LightEmission = 0.3,
		Size = nseq(0, 0.6, 0.3, 1.2, 1, 0), Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Rate = 30, LockedToPart = true, ZOffset = 0.3 })
	local ash = emitter(core, { Texture = TEX_INK, FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4,
		FlipbookMode = Enum.ParticleFlipbookMode.OneShot, Color = ColorSequence.new(INK), LightEmission = 0,
		Size = nseq(0, 0.6, 0.3, 1.2, 1, 0), Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 180), Rotation = NumberRange.new(0, 360), Rate = 18, LockedToPart = true, ZOffset = 0.2 })
	PackFX.Burst("Anime/Charge-01", CFrame.new(at), { color = CRIMSON, scale = 1.2 })
	ClassFX.Sound("charge", at, 0.7, 0.75, charge)
	ClassFX.Sound("fireWhoosh", pos, 0.6, 0.6)
	ClassFX.Sound("wind", pos, 0.6, 1.2, charge)
	local t0 = os.clock()
	local nextBolt, nextSwirl, nextAir, nextPulse, lastStep = 0, 0, 0, 0.15, -1
	animate(charge, function(a)
		local h = hands()
		if not h then
			a = 1
		else
			local t = os.clock() - t0
			local u = easeOut(a)
			local pulse = 1 + math.sin(t * 22) * 0.1
			local c = CFrame.new(h)
			core.CFrame, glow.CFrame = c, c
			field.CFrame = c * CFrame.Angles(t * 4, t * 9, 0)
			core.Size = Vector3.one * (0.3 + 0.7 * u) * pulse
			glow.Size = Vector3.one * (0.5 + 1.0 * u) * pulse
			field.Size = Vector3.one * (0.9 + 1.4 * u)
			local stepK = math.floor(u * 4)
			if stepK ~= lastStep then
				lastStep = stepK
				local q = stepK / 4
				fire.Size = nseq(0, 0.6 + 0.6 * q, 0.3, 1.2 + 1.4 * q, 1, 0)
				ash.Size = nseq(0, 0.6 + 0.5 * q, 0.3, 1.2 + 1.2 * q, 1, 0)
			end
			-- red energy swirling in to his hand from all round him, and ink
			if t >= nextSwirl then
				nextSwirl = t + 0.06
				inkCurl(hands, 3.5 + math.random() * 3, 0.3 + 0.35 * u, 0.42, if math.random() < 0.75 then "energy" else nil)
			end
			-- air drawn in to him in long streaks from all round, faster as it builds
			if t >= nextAir then
				nextAir = t + 0.07 - 0.03 * u
				inkCurl(body, 7 + math.random() * 4, 0.22 + 0.2 * u, 0.5, "air")
			end
			-- pressure pulsing out of him over the floor, harder each time
			if t >= nextPulse then
				nextPulse = t + 0.3 - 0.12 * u
				floorRing(pos, 3 + 2 * u, 0.4, WHITE, 0.25 + 0.3 * u)
				if FxBudget.Allow("maHadoPulse", 8) then
					PackFX.Burst("Anime/Wind-02", CFrame.new(pos + Vector3.new(0, 0.4, 0)), { scale = 0.7 + 0.6 * u })
				end
				if mine and deps then deps.shake(0.06 + 0.12 * u, 0.12) end
			end
			-- red lightning cracking between his hands and off the sphere
			if t >= nextBolt then
				nextBolt = t + 0.05
				local r, l = fistOf(char, "Right Arm"), fistOf(char, "Left Arm")
				if r and l then bolt(r, l, 0.09, 0.06, CRIMSON, 3) end
				local out = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5).Unit
				bolt(h + out * 0.6 * u, h + out * (1.5 + 2 * u), 0.1, 0.07, if math.random() < 0.3 then HOT else CRIMSON, 3)
			end
		end
		if a >= 1 then
			fire.Enabled, ash.Enabled = false, false
			for _, p in ipairs({ core, glow, field }) do
				TweenService:Create(p, TweenInfo.new(0.1), { Transparency = 1 }):Play()
				Debris:AddItem(p, 0.5)
			end
			return true
		end
		return nil
	end)
end

-- 2 · The thrust: an air blast off his palms, a wave of dust over the floor.
local function hadoThrust(char: Model?, pos: Vector3, dir: Vector3, mine: boolean)
	local h = (char and handsOf(char)) or (pos + dir * 2 + Vector3.new(0, 0.2, 0))
	local at = h + dir * 1.5
	local g = onGround(pos)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	flare(at, 9, 0.25, HOT)
	shell(at, 1, 9, 0.28, CRIMSON)
	PackFX.Burst("Anime/Shoot-01", CFrame.lookAt(at, at + dir), { color = CRIMSON, scale = 1.4 })
	PackFX.Burst("Anime/Wind-02", CFrame.lookAt(at, at + dir), { scale = 1.6 })
	PackFX.Burst("Anime/Wind-02", CFrame.new(g + Vector3.new(0, 0.4, 0)), { scale = 1.4 })
	punchRing(at + dir, dir, 2.4, 0.3, CRIMSON)
	task.delay(0.05, function() punchRing(at + dir * 3.5, dir, 3.6, 0.35, WHITE) end)
	task.delay(0.1, function() punchRing(at + dir * 6.5, dir, 5, 0.4, HOT) end)
	floorRing(g, 6, 0.45, WHITE, 0.6)
	-- streaks of air blasted out ahead of him
	for _ = 1, 10 do
		local off = side * (math.random() - 0.5) * 6 + Vector3.new(0, (math.random() - 0.5) * 4, 0)
		SwordFX.Streak(at + off * 0.3, at + off + dir * (12 + math.random() * 8), 0.18, WHITE, 0.08, 1, WHITE)
	end
	sparks(at, 30, 30, CRIMSON)
	ClassFX.Sound("fireBurst", at, 1, 0.7)
	ClassFX.Sound("boom", at, 0.8, 1.1)
	ClassFX.Sound("whoosh", at, 0.9, 0.55)
	ClassFX.Sound("wind", at, 0.7, 1.6, 0.4)
	if mine and deps then
		deps.shake(0.7, 0.3)
		deps.fovPunch(8, 0.3)
		flash(0.22, 0.65)
	end
end

-- How far the sphere has flown `t` seconds after the thrust (matches
-- MartialServer): off the palms at HADO.v0, surging up to `speed`.
local function hadoDist(t: number, speed: number): number
	return speed * t - (speed - HADO.v0) * HADO.ramp * (1 - math.exp(-t / HADO.ramp))
end

-- The sphere itself, after the pack's Ball-01 (its fire, its black ash, its
-- embers, its red): a dense ball of them churning round a white-hot heart,
-- `s` big. Some of the fire and ash is left hanging in the air as it goes,
-- so its tail streams out behind it along its path whichever way it flies.
-- move(pos) it each frame; stop() lets it burn out.
local BALL_RED = Color3.fromRGB(255, 52, 11)   -- (Ball-01's own red,
local SPECK_RED = Color3.fromRGB(206, 57, 15)  -- and its embers')
local TEX_SPECK = "rbxassetid://11187840108"   -- (the pack's ember)
type FireBall = { move: (Vector3) -> (), stop: () -> () }
local function fireBall(at: Vector3, s: number): FireBall
	local head = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 3.6 * s, Transparency = 1, CFrame = CFrame.new(at) })
	local heart = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2 * s, Color = WHITE, Transparency = 0.05, CFrame = CFrame.new(at) })
	local function flame(props: { [string]: any }): ParticleEmitter
		props.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
		props.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		props.Shape = Enum.ParticleEmitterShape.Sphere
		props.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		props.Rotation = NumberRange.new(-360, 360)
		return emitter(head, props)
	end
	-- the ball: fire and ash churning, held to it (three times the pack's emission)
	flame({ Texture = TEX_FLAME, Color = ColorSequence.new(BALL_RED), LightEmission = 0.15, LockedToPart = true,
		Size = nseq(0, 1.8 * s, 0.28, 3.4 * s, 1, 0), Lifetime = NumberRange.new(0.45, 0.65), Speed = NumberRange.new(2, 5), Rate = 450, ZOffset = 0.5 })
	flame({ Texture = TEX_INK, Color = ColorSequence.new(INK), LightEmission = 0, LockedToPart = true,
		Size = nseq(0, 1.8 * s, 0.28, 3.4 * s, 1, 0), Lifetime = NumberRange.new(0.45, 0.65), Speed = NumberRange.new(2, 5), Rate = 300, ZOffset = 0.45 })
	-- the tail: the same fire and ash, left hanging where it was as the ball goes on
	flame({ Texture = TEX_FLAME, Color = ColorSequence.new(BALL_RED), LightEmission = 0.15, Size = nseq(0, 3 * s, 1, 0),
		Lifetime = NumberRange.new(0.35, 0.5), Speed = NumberRange.new(0, 1), Rate = 360, ZOffset = 0.3 })
	flame({ Texture = TEX_INK, Color = ColorSequence.new(INK), LightEmission = 0, Size = nseq(0, 2.6 * s, 1, 0),
		Lifetime = NumberRange.new(0.3, 0.45), Speed = NumberRange.new(0, 1), Rate = 240, ZOffset = 0.25 })
	-- embers thrown off it
	emitter(head, { Texture = TEX_SPECK, Color = ColorSequence.new(SPECK_RED), LightEmission = 0, Size = nseq(0, 0, 0.26, 1.2 * s, 1, 0),
		Lifetime = NumberRange.new(0.5, 0.75), Speed = NumberRange.new(6, 14), SpreadAngle = Vector2.new(180, 180), Drag = 2, Rate = 120 })
	local stopped = false
	return {
		move = function(p: Vector3)
			if stopped then return end
			head.CFrame = CFrame.new(p)
			heart.CFrame = CFrame.new(p)
		end,
		stop = function()
			if stopped then return end
			stopped = true
			for _, e in ipairs(head:GetChildren()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
			Debris:AddItem(head, 0.8)
			TweenService:Create(heart, TweenInfo.new(0.12), { Size = heart.Size * 2.2, Transparency = 1 }):Play()
			Debris:AddItem(heart, 0.15)
		end,
	}
end

-- 3 · The sphere in flight: from `origin` along `d` for `length`, up to
-- `speed`, `s` its size (the Size stat grows it).
local function hadoShot(origin: Vector3, d: Vector3, length: number, speed: number, s: number)
	local side = d:Cross(Vector3.yAxis)
	side = if side.Magnitude > 0.05 then side.Unit else Vector3.xAxis
	local up = side:Cross(d).Unit
	-- (big: it should fill the screen from the game camera)
	local ball = fireBall(origin, 1.6 * s)
	-- the floor scorched under it: a flat trail of red into black
	local gy = groundY(origin)
	local floorAt = Vector3.new(origin.X, gy + 0.12, origin.Z)
	local scorch = carrier(CFrame.lookAt(floorAt, floorAt + d))
	local s0, s1 = Instance.new("Attachment"), Instance.new("Attachment")
	s0.Position, s1.Position = Vector3.new(2.6 * s, 0, 0), Vector3.new(-2.6 * s, 0, 0)
	s0.Parent, s1.Parent = scorch, scorch
	local burn = Instance.new("Trail")
	burn.Attachment0, burn.Attachment1 = s0, s1
	burn.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, CRIMSON), ColorSequenceKeypoint.new(0.25, BLOOD), ColorSequenceKeypoint.new(1, INK) })
	burn.Transparency = nseq(0, 0.2, 0.6, 0.5, 1, 1)
	burn.LightEmission, burn.LightInfluence = 0.4, 0
	burn.Lifetime = 0.9
	burn.MinLength = 0.1
	burn.Parent = scorch
	local t0 = os.clock()
	local nextArc, nextFloor, nextRing, nextWind, nextDust = 0, 0, 0, 0, 0
	local rings = 0
	animate((length + (speed - HADO.v0) * HADO.ramp) / speed + 0.5, function(a)
		local t = os.clock() - t0
		local dist = math.min(hadoDist(t, speed), length)
		local p = origin + d * dist
		ball.move(p)
		if t >= nextFloor then
			nextFloor = t + 0.1
			gy = groundY(p)
		end
		local fp = Vector3.new(p.X, gy + 0.12, p.Z)
		scorch.CFrame = CFrame.lookAt(fp, fp + d)
		-- rings of air thrown off it, white and crimson by turns
		if t >= nextRing and FxBudget.Allow("maHadoRing", 16) then
			nextRing = t + 0.07
			rings += 1
			punchRing(p - d * 2.4 * s, d, 2.6 * s, 0.3, if rings % 2 == 0 then WHITE else CRIMSON)
		end
		-- streaks of wind tearing past it
		if t >= nextWind and FxBudget.Allow("maHadoWind", 30) then
			nextWind = t + 0.04
			local off = (side * (math.random() - 0.5) + up * (math.random() - 0.5)).Unit * (3 + math.random() * 2) * s
			SwordFX.Streak(p + off - d * 9 * s, p + off - d * s, 0.12 * s, WHITE, 0.04, 1, WHITE)
		end
		-- dust torn up off the floor under it
		if t >= nextDust and FxBudget.Allow("maHadoDust", 8) then
			nextDust = t + 0.12
			PackFX.Burst("Anime/Wind-02", CFrame.new(fp + Vector3.new(0, 0.3, 0)), { scale = 0.8 })
		end
		-- red lightning lashing off it, back along its path
		if t >= nextArc and FxBudget.Allow("maHadoArc", 40) then
			nextArc = t + 0.05
			local out = (side * (math.random() - 0.5) + up * (math.random() - 0.5)).Unit
			bolt(p + out * 2.5 * s, p - d * (4 + math.random() * 5) * s + out * (2.5 + math.random() * 2) * s, 0.16 * s, 0.08,
				if math.random() < 0.3 then HOT else CRIMSON, 4)
		end
		if a >= 1 or dist >= length then
			ball.stop()
			Debris:AddItem(scorch, 1)
			return true
		end
		return nil
	end)
end

-- When ours was cast (our charge started on our screen, not the server's word).
local hadoCastAt = 0

local function onHado(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	local dir = flat(msg.dir :: Vector3)
	local mine = owner == player
	local charge = tonumber(msg.charge) or HADO.charge
	local after = charge
	if mine then
		after = math.max(0, charge - (os.clock() - hadoCastAt))
	elseif char then
		hadoPose(char)
		hadoChargeFx(char, dir, charge, false)
	end
	local from = msg.from :: Vector3
	local speed = tonumber(msg.speed) or 60
	local scale = tonumber(msg.scale) or 1
	local length = tonumber(msg.length) or 70
	task.delay(after, function()
		hadoThrust(char, msg.pos :: Vector3, dir, mine)
		hadoShot(from + dir * 2.5, dir, length, speed, scale)
	end)
end

-- Everyone it passes through bursts in ink.
local function onHadoHit(msg: any)
	local d = flat((msg.dir :: Vector3?) or Vector3.new(0, 0, -1))
	for i, p in ipairs(msg.hits or {}) do
		if i > 5 or not FxBudget.Allow("maHadoInk", 14) then break end
		local at = (p :: Vector3) + Vector3.new(0, 0.6, 0)
		PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(at, at + d), { color = INK, scale = 1.1, light = 0 })
		flare(at, 4, 0.16, HOT)
		sparks(at, 12, 22, CRIMSON)
		if FxBudget.Allow("maPunchPack", 6) then
			PackFX.Burst("Anime/Punch-03", CFrame.lookAt(at, at + d), { color = CRIMSON, scale = 1 })
		end
	end
	if msg.attacker == player and deps then deps.shake(0.2, 0.08) end
end

-- It bursts where it ends.
local function onHadoEnd(msg: any)
	local pos = msg.pos :: Vector3
	local r = tonumber(msg.radius) or 12
	local d = flat((msg.dir :: Vector3?) or Vector3.new(0, 0, -1))
	local mine = msg.attacker == player
	local g = onGround(pos)
	PackFX.Burst("Big/Explosion-01", CFrame.new(pos), { color = CRIMSON, scale = r / 12 })
	PackFX.Burst("Big/Big-Crack-01", CFrame.new(g + Vector3.new(0, 0.1, 0)), { color = CRIMSON, scale = r / 10 })
	PackFX.Burst("Anime/Blood-Punch-01", CFrame.lookAt(pos, pos + d), { color = INK, scale = 2.4, light = 0 })
	PackFX.Burst("Anime/Blood-01", CFrame.new(g + Vector3.new(0, 0.1, 0)), { color = INK, scale = r / 3, light = 0 })
	shell(pos, 2, r * 2.2, 0.4, CRIMSON)
	flare(pos, r * 1.4, 0.3, HOT)
	SwordFX.Rays(g + Vector3.new(0, 0.3, 0), r * 1.6, 16, CRIMSON, 0.35)
	floorRing(g, r, 0.5, CRIMSON, 1.2)
	task.delay(0.08, function() floorRing(g, r * 1.4, 0.5, HOT, 0.6) end)
	if FxBudget.Allow("maHadoEnd", 4) then
		inkDrops(pos, 18, r, d)
		chunks(g, 12, 30)
		PackFX.Burst("Anime/Smoke-01", CFrame.new(g + Vector3.new(0, 1, 0)), { color = Color3.fromRGB(70, 40, 44), scale = 1.4 })
	end
	ClassFX.Sound("boom", pos, 1, 0.8)
	ClassFX.Sound("quake", pos, 0.5, 1.1)
	ClassFX.Sound("fireBurst", pos, 0.7, 0.6)
	if mine and deps then
		deps.shake(0.8, 0.3)
		deps.fovPunch(6, 0.3)
	elseif near(pos, 50) and deps then
		deps.shake(0.4, 0.2)
	end
end

-- ── Qi Charge: full, spent ──────────────────────────────────────────────────
local function onChargeFull(msg: any)
	local root = rootOf(charOf(msg.attacker))
	if not root then return end
	floorRing(onGround(root.Position), 5, 0.35, CRIMSON, 0.6)
	sparks(root.Position, 16, 10, HOT)
	if msg.attacker == player then ClassFX.Sound("ding", root, 0.5, 1.1) end
end

local function onEmpowered(msg: any)
	local root = rootOf(charOf(msg.attacker))
	if not root then return end
	PackFX.Burst("Anime/Charge-01", root.CFrame, { color = CRIMSON, scale = 1.1 })
	flare(root.Position, 9, 0.3)
	sparks(root.Position + Vector3.new(0, 1, 0), 30, 18, HOT)
	SwordFX.Spiral(function() return if root.Parent then root.Position - Vector3.new(0, 2.5, 0) else nil end, 3, 0.6, CRIMSON)
end

local HANDLERS: { [string]: (any) -> () } = {
	strike = onStrike,
	strikeLanded = function(msg)
		if FxBudget.Allow("maLanded", 14) then strikeLanded(msg) end
	end,
	focusCharge = onFocusCharge,
	focusRelease = onFocusRelease,
	focusLanded = onFocusLanded,
	uppercut = onUppercut,
	uppercutHit = onUppercutHit,
	ascent = onAscent,
	hado = onHado,
	hadoHit = onHadoHit,
	hadoEnd = onHadoEnd,
	chargeFull = onChargeFull,
	empowered = onEmpowered,
}

-- While a Martial Artist's Charge is full: his fists burn with Qi.
local burning: { [Player]: { Attachment } } = {}
local function stepBurning()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local want = char ~= nil and isMartial(p) and (tonumber(p:GetAttribute("MA_Charge")) or 0) >= CHARGE_MAX
		local have = burning[p]
		if want and not have and char then
			local list = {}
			for _, side in ipairs({ "Right Arm", "Left Arm" }) do
				local arm = char:FindFirstChild(side)
				if arm then
					local att = Instance.new("Attachment")
					att.Name = "MartialEmpowered"
					att.Position = Vector3.new(0, -1.05, 0)
					att.Parent = arm
					emitter(att, { Texture = TEX_FIRE, Color = ColorSequence.new(HOT, BLOOD), LightEmission = 1,
						Size = nseq(0, 1, 1, 0), Transparency = nseq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.25, 0.45),
						Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 6, 0), Rate = 32,
						RotSpeed = NumberRange.new(-150, 150) })
					table.insert(list, att)
				end
			end
			burning[p] = list
		elseif not want and have then
			for _, a in ipairs(have) do a:Destroy() end
			burning[p] = nil
		end
	end
	for p, list in pairs(burning) do
		if not p.Parent then
			for _, a in ipairs(list) do a:Destroy() end
			burning[p] = nil
		end
	end
end

-- ── HUD: Qi Charge ──────────────────────────────────────────────────────────
-- Five crimson orbs over the skill bar, each filling as its 20 Charge comes in
-- (the sheet's: three full, the fourth half), the count beside them; full,
-- they blaze and it reads EMPOWERED.
local hud: ScreenGui? = nil
local fills: { Frame } = {}
local pipFrames: { Frame } = {}
local countLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil

local function charge(): number
	return tonumber(player:GetAttribute("MA_Charge")) or 0
end

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "MartialCharge"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -132)
	row.Size = UDim2.fromOffset(250, 22)
	row.BackgroundTransparency = 1
	row.Parent = g
	for k = 1, 5 do
		local p = Instance.new("Frame")
		p.Name = "Orb" .. k
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.new(0, 10 + (k - 1) * 28, 0.5, 0)
		p.Size = UDim2.fromOffset(20, 20)
		p.BackgroundColor3 = Color3.fromRGB(24, 10, 12)
		p.BorderSizePixel = 0
		p.ClipsDescendants = true
		p.Parent = row
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = p
		local s = Instance.new("UIStroke")
		s.Color = CRIMSON
		s.Thickness = 1.5
		s.Parent = p
		-- the fill, rising from the bottom
		local f = Instance.new("Frame")
		f.Name = "Fill"
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.fromScale(0, 1)
		f.Size = UDim2.fromScale(1, 0)
		f.BackgroundColor3 = CRIMSON
		f.BorderSizePixel = 0
		f.Parent = p
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(1, 0)
		fc.Parent = f
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(HOT, BLOOD)
		grad.Parent = f
		table.insert(pipFrames, p)
		table.insert(fills, f)
	end
	local n = Instance.new("TextLabel")
	n.AnchorPoint = Vector2.new(0, 0.5)
	n.Position = UDim2.new(0, 152, 0.5, 0)
	n.Size = UDim2.fromOffset(100, 20)
	n.BackgroundTransparency = 1
	n.Font = Enum.Font.Arcade
	n.TextSize = 18
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.TextColor3 = HOT
	n.TextStrokeColor3 = Color3.new(0, 0, 0)
	n.TextStrokeTransparency = 0.3
	n.Text = "0 / 100"
	n.Parent = row
	countLabel = n
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 0, -4)
	t.Size = UDim2.fromOffset(280, 20)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Arcade
	t.TextSize = 18
	t.TextColor3 = Color3.fromRGB(240, 190, 190)
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.TextStrokeTransparency = 0.3
	t.Text = "QI CHARGE"
	t.Parent = row
	titleLabel = t
end

local function refreshHud()
	if not hud then return end
	hud.Enabled = isMartial() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	local c = charge()
	local full = c >= CHARGE_MAX
	for k, f in ipairs(fills) do
		local frac = math.clamp((c - (k - 1) * 20) / 20, 0, 1)
		f.Size = UDim2.fromScale(1, frac)
		f.BackgroundColor3 = if full then WHITE else CRIMSON
	end
	if countLabel then
		local txt = `{math.floor(c)} / {CHARGE_MAX}`
		if countLabel.Text ~= txt then countLabel.Text = txt end
	end
	if titleLabel then
		local txt = if full then "EMPOWERED: NEXT ABILITY" else "QI CHARGE"
		if titleLabel.Text ~= txt then titleLabel.Text = txt end
		titleLabel.TextColor3 = if full then HOT else Color3.fromRGB(240, 190, 190)
	end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
local function attackSpeed(): number
	return math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
end

-- Feet planted: a Rooted character can't walk (AnimationController holds it
-- still and stops the walk cycle under the pose). Each strike keeps it going,
-- so a chain of them stays planted till the last is thrown.
local plantToken = 0
local function plant(char: Model, seconds: number)
	plantToken += 1
	local token = plantToken
	char:SetAttribute("Rooted", true)
	task.delay(seconds, function()
		if plantToken == token and char.Parent then char:SetAttribute("Rooted", nil) end
	end)
end

-- A push in behind a strike: carried `dist` studs along `dir` over `t`
-- seconds, level (short of walls and ledges), then stopped dead. Returns how
-- far it goes.
local function nudge(root: BasePart, dir: Vector3, dist: number, t: number): number
	local old = root:FindFirstChild("MartialNudge")
	if old then old:Destroy() end
	dist = math.min(SafeMove.ClampDash(root, dir, dist), SafeMove.ClampToFloor(root, dir, dist))
	if dist < 0.05 then return 0 end
	local att = Instance.new("Attachment")
	att.Name = "MartialNudge"
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(1e5, 0, 1e5)
	lv.VectorVelocity = dir * (dist / t)
	lv.Parent = att
	att.Parent = root
	task.delay(t, function()
		if not att.Parent then return end -- (a newer push took over)
		att:Destroy()
		if root.Parent then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
		end
	end)
	return dist
end

function MartialController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = attackSpeed()
	if now - lastSwing < COMBO_INTERVAL / speed then return true end
	if now - lastSwing > COMBO_RESET then step = 0 end
	step = step % COMBO_STEPS + 1
	lastSwing = now
	-- (after the finisher: a beat to recover, then the chain starts over)
	if step == COMBO_STEPS then
		busyUntil = now + RECOVER / speed
	end
	local dir = flat(deps.getAim(root))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	-- No walking through a strike: the feet planted till it's thrown, and a
	-- push in behind it.
	local fast = math.max(speed, 1)
	plant(char, PLANTED[step] / fast)
	local lunge = nudge(root, dir, LUNGE[step], 0.1 / fast)
	strikePose(char, step, speed)
	-- (the swing is drawn now, from partway along the push; the hits come
	-- back from the server)
	local size = tonumber(player:GetAttribute("Stat_size")) or 1
	local at = root.Position + dir * lunge * 0.5
	strikeFx({ pos = at, dir = dir, step = step, landed = false, reach = COMBO_RANGE[step] * size,
		palm = if step == 6 then at + dir * PALM_AT elseif step == COMBO_STEPS then at + dir * 2.5 else nil,
		radius = (if step == COMBO_STEPS then FINISH_RADIUS else PALM_RADIUS) * size })
	if step == COMBO_STEPS then step = 0 end
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function MartialController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

-- Returns where the skill is aimed (sent to the server).
function MartialController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any, cursor: Vector3?): Vector3?
	local dir = flat(aimDir)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	-- (a full Charge: the server spends it on this one)
	local empowered = (tonumber(player:GetAttribute("MA_Charge")) or 0) >= CHARGE_MAX
	if skillIndex == 1 then
		-- (held: it charges till the key comes up, MartialController.Release;
		-- he can walk slowly meanwhile)
		char:SetAttribute("AllowSkillMovement", true)
		startFocus(char, root, empowered)
		return nil
	elseif skillIndex == 2 then
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = os.clock() + UPPER.total
		releaseAfter(char, UPPER.total + 0.05)
		plant(char, UPPER.total)
		uppercutPose(char)
		local origin = root.Position
		local dash = uppercutFly(char, root, dir)
		uppercutFx(char, origin, dir, dash, true)
		return nil
	elseif skillIndex == 3 then
		char:SetAttribute("AllowSkillMovement", false)
		ascentPose(char)
		local T = ASCENT
		local total = T.rise + T.dash + T.fall
		busyUntil = os.clock() + total + 0.15
		releaseAfter(char, total + 0.2)
		return ascentFly(char, root, dir, cursor, config.range or 26)
	elseif skillIndex == 4 then
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = os.clock() + HADO.charge + HADO.hold
		hadoCastAt = os.clock()
		hadoPose(char)
		hadoChargeFx(char, dir, HADO.charge, true)
		releaseAfter(char, HADO.charge + HADO.hold)
		return nil
	end
	return nil
end

-- The Focus Strike's key came up (SkillController), or it was held all the
-- way: the punch, as hard as it got.
function MartialController.Release(skillIndex: number)
	if skillIndex ~= 1 then return end
	local f = focusing
	if not f then return end
	focusing = nil
	local char, root = f.char, f.root
	local held = os.clock() - f.t0
	local c = math.clamp(held / f.full, 0, 1)
	local full = c >= 0.999
	local dir = if root.Parent and deps then flat(deps.getAim(root)) else flat(root.CFrame.LookVector)
	Network.GetRemoteEvent(Network.Remotes.MartialInput):FireServer({ kind = "release", held = held, dir = dir })
	f.fx.stop(full)
	-- (planted for the punch; his own turning back after)
	char:SetAttribute("AllowSkillMovement", false)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum and not hum.PlatformStand then hum.AutoRotate = true end
	if not (char.Parent and root.Parent) then
		busyUntil = 0
		return
	end
	local want = FOCUS.lunge + (FOCUS.fullLunge - FOCUS.lunge) * c
	local lunge = math.min(SafeMove.ClampDash(root, dir, want), SafeMove.ClampToFloor(root, dir, want))
	busyUntil = os.clock() + FOCUS.hit + 0.3
	releaseAfter(char, FOCUS.hit + 0.28)
	focusPunchPose(char, c)
	-- the lunge: a burst forward into the punch
	local from = root.Position
	animate(FOCUS.hit, function(a)
		if root.Parent then
			local p = from + dir * lunge * easeOut(a)
			root.CFrame = CFrame.lookAt(p, p + dir)
		end
		return nil
	end)
	-- (Empowered: the faster charge, the bigger splash)
	local size = tonumber(player:GetAttribute("Stat_size")) or 1
	local splash = FOCUS.splash * size * (if f.full < FOCUS.full then 1.4 else 1)
	focusReleaseFx(from, dir, c, full, lunge, splash, true)
end

-- The ult's cinematic (ours): only the charge. The pose sheet's view: low
-- from his front-right, the whole stance in frame with the sphere between
-- his hands, drifting a little round him and pushing in as it builds, the
-- shake growing; on the thrust it hands straight back to the game camera to
-- watch the sphere fly.
function MartialController.PlayUltCutscene(char: Model, dir: Vector3)
	local root = rootOf(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return end
	local cam = Workspace.CurrentCamera
	local iso = IsometricCamera
	local wasIso = iso ~= nil and iso.IsActive() and not iso.IsPaused()
	if wasIso then iso.Pause() end
	cam.CameraType = Enum.CameraType.Scriptable
	local d = flat(dir)
	local right = d:Cross(Vector3.yAxis).Unit
	local base = root.Position
	local floor = groundY(base)
	-- (pulled in short of any wall between it and what it's looking at)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local function clear(look: Vector3, want: Vector3): Vector3
		local res = Workspace:Raycast(look, want - look, params)
		return if res then res.Position + (look - want).Unit * 0.6 else want
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if not char.Parent or hum.Health <= 0 or t >= HADO.charge then
			conn:Disconnect()
			if wasIso and iso then
				iso.Resume(0.35)
			else
				cam.CameraType = Enum.CameraType.Custom
				cam.FieldOfView = 70
				cam.CameraSubject = hum
			end
			return
		end
		local u = easeOut(t / HADO.charge)
		local orb = handsOf(char) or base
		local off = CFrame.Angles(0, math.rad(10 * u), 0):VectorToWorldSpace(right * 6.2 + d * 5.4) * (1 - 0.15 * u)
		local p = base + off
		local look = orb:Lerp(base, 0.35)
		local at = clear(look, Vector3.new(p.X, floor + 2, p.Z))
		local quake = 0.05 + 0.4 * u * u
		local n = os.clock() * 22
		local shake = CFrame.Angles(math.noise(n, 1.3) * quake * 0.05, math.noise(n, 7.1) * quake * 0.05, math.noise(n, 3.7) * quake * 0.025)
		cam.CFrame = CFrame.lookAt(at, look) * shake
		cam.FieldOfView = 58 - 6 * u
	end)
end

function MartialController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	RunService.RenderStepped:Connect(function(dt)
		stepBurning()
		stepAnims(dt)
	end)
	-- (the tails sway after the animation and poses have written the frame)
	CastPoses.addPostHook(stepRigs)
	for _, a in ipairs({ "MA_Charge", "SelectedClass", "InLobby", "SettingsOpen" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshHud)
	end
	player.CharacterAdded:Connect(function()
		focusing = nil
		busyUntil = 0
		lastSwing = 0
		step = 0
	end)
	Network.GetRemoteEvent(Network.Remotes.MartialFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[MartialController]", msg.kind, err) end
		end
	end)
end

return MartialController
