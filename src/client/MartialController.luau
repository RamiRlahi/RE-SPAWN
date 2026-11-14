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
local VfxKit = require(script.Parent:WaitForChild("VfxKit"))
local VfxAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxAssets"))
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
-- Dragon Soul (matches MartialServer): the summoning (the ult's cinematic,
-- `rise` seconds); then strikes come `speed`x faster and the dragon lashes
-- out `reach` studs along each (out in `lash` seconds, back in `back`).
-- Between strikes it coils round him (`orbit` studs out, `height` up,
-- `spin` radians a second).
local DRAGON = { rise = 1.1, speed = 1.6, reach = 15, lash = 0.14, back = 0.3, orbit = 4.2, height = 3, spin = 2.6 }
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
-- (a dash cuts the move short: free to cast again at once)
(require(script.Parent:WaitForChild("DashController")) :: any).OnCancel(function(c: Model)
	if c == game:GetService("Players").LocalPlayer.Character then busyUntil = 0 end
end)

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

-- The world dimmed and reddened a little (the Dragon Soul's summoning).
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

-- Dragon Soul: crouched low, fists drawn in to the chest, trembling as the
-- dragon spirals up round him; then the roar: arms flung up and wide, head
-- thrown back, held a beat.
local function roarPose(char: Model)
	local gather = { Root = { 0, 0, 0, 0, -0.55, 0 }, W = { 22, 0, 0 }, N = { 18, 0, 0 }, RS = { 40, 0, 44 }, LS = { 40, 0, -44 },
		RH = { 34, 0, 8 }, LH = { -24, 0, -8 } }
	local roar = { Root = { 0, 0, 0, 0, -0.1, 0 }, W = { -14, 0, 0 }, N = { -32, 0, 0 }, RS = { 158, 0, 34 }, LS = { 158, 0, -34 },
		RH = { 4, 0, 10 }, LH = { -4, 0, -10 } }
	CastPoses.play(char, {
		{ dur = 0.2, pose = gather },
		{ dur = DRAGON.rise - 0.3, pose = gather, wobble = function(t: number)
			local s = math.sin(t * 50) * (0.6 + 2.4 * math.min(t / DRAGON.rise, 1))
			return { RS = { s, 0, 0 }, LS = { -s, 0, 0 } }
		end },
		{ dur = 0.1, style = Enum.EasingStyle.Quart, pose = roar },
		{ dur = 0.45, pose = roar },
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
-- ── E: Hundred Fists ────────────────────────────────────────────────────────
-- (matches MartialServer's BARRAGE) The barrage for `duration`, the power
-- punch landing at `punchAt`, back to guard at `total`.
local BARRAGE = { duration = 1.1, punchAt = 1.32, total = 1.65, cone = 18, half = math.rad(36),
	walk = 6 } -- (his walk through the barrage; normal is 16)

-- 1 · the barrage: a low wide stance, both fists hammering out in turn
-- faster than the eye (the arms blur between forward and drawn back), the
-- body rocking with it; 2 · the wind-up: the right fist pulled right back,
-- the body turned away; 3 · the power punch: driven straight out with
-- everything behind it, held.
local function barragePose(char: Model)
	local ready = { RS = { 80, 0, -4 }, LS = { 80, 0, 4 }, W = { -6, 0, 0 }, N = { 0, 0, 0 }, Root = { 0, 0, 0, 0, -0.5, 0 },
		LH = { 28, 0, -14 }, RH = { -20, 0, 14 } }
	local windup = { RS = { -30, 0, 20 }, LS = { 70, 0, -10 }, W = { 4, -42, 0 }, N = { 0, 34, 0 }, Root = { 0, 0, 0, 0, -0.7, 0.2 },
		LH = { 32, 0, -16 }, RH = { -24, 0, 18 } }
	local punch = { RS = { 98, 0, -6 }, LS = { -18, 0, -26 }, W = { -14, 38, 0 }, N = { 0, -26, 0 }, Root = { 0, 0, 0, 0, -0.55, -0.8 },
		LH = { 42, 0, -10 }, RH = { -42, 0, 12 } }
	local wind = BARRAGE.punchAt - BARRAGE.duration - 0.08
	CastPoses.play(char, {
		{ dur = 0.08, pose = ready },
		{ dur = BARRAGE.duration, pose = ready, wobble = function(t: number)
			local s = math.sin(t * 48)
			return {
				RS = { -55 * (0.5 + 0.5 * s), (math.random() - 0.5) * 16, 0 },
				LS = { -55 * (0.5 - 0.5 * s), (math.random() - 0.5) * 16, 0 },
				W = { 0, s * 8, 0 },
				Root = { 0, 0, 0, 0, math.abs(s) * 0.05, 0 },
			}
		end },
		{ dur = math.max(wind, 0.05), style = Enum.EasingStyle.Quad, pose = windup },
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = punch },
		{ dur = BARRAGE.total - BARRAGE.punchAt, pose = punch },
	}, 0.25)
end

-- A copy of his own arm (the arm's part as it is: its colour, its mesh, any
-- glove welded to it isn't carried) thrust out from the shoulder at `from`
-- along `dir`, `len` studs over `life`, fading; a white swish of air curling
-- round its fist. `scale` grows it (the power punch's great arm).
local function armCopy(arm: BasePart): BasePart
	local c = Instance.new("Part")
	c.Size = arm.Size
	c.Color = arm.Color
	c.Material = arm.Material
	c.Anchored, c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow = true, false, false, false, false
	for _, d in ipairs(arm:GetChildren()) do
		if d:IsA("SpecialMesh") or d:IsA("Decal") or d:IsA("Texture") then d:Clone().Parent = c end
	end
	c.Parent = ClassFX.Folder()
	return c
end

local function ghostArm(arm: BasePart?, from: Vector3, dir: Vector3, len: number, life: number, scale: number)
	if not arm then return end
	local c = armCopy(arm)
	c.Size = arm.Size * scale
	local mesh = c:FindFirstChildOfClass("SpecialMesh")
	if mesh then mesh.Scale *= scale end
	-- (an arm's hand is its -Y end: turned so it points along `dir`)
	local turn = CFrame.Angles(math.rad(90), 0, 0)
	local half = c.Size.Y / 2
	-- the swish: a thin white ring round the fist, opening as it flies
	local swish = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 1.2 * scale, 1.2 * scale), Color = WHITE, Transparency = 0.3 })
	animate(life, function(a)
		local d = len * easeOut(a)
		local base = CFrame.lookAt(from + dir * d, from + dir * (d + 1))
		c.CFrame = base * CFrame.new(0, 0, -half) * turn
		c.Transparency = 0.15 + 0.85 * a ^ 1.5
		local s = (1.2 + a * 1.6) * scale
		swish.Size = Vector3.new(0.08, s, s)
		swish.CFrame = base * CFrame.new(0, 0, -half * 2) * CFrame.Angles(0, math.rad(90), 0)
		swish.Transparency = 0.3 + 0.7 * a
		if a >= 1 then
			c:Destroy()
			swish:Destroy()
		end
		return nil
	end)
end

-- The ground under `pos`: where it is, its colour and material (the crater's
-- slabs are broken out of it).
local function groundUnder(pos: Vector3): (Vector3, Color3, Enum.Material)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), params)
	if hit then
		local col = hit.Instance.Color
		local mat = hit.Material
		if mat == Enum.Material.Neon or mat == Enum.Material.ForceField or mat == Enum.Material.Glass then mat = Enum.Material.Slate end
		-- (a glowing floor gives grey stone, not glowing slabs; and a dark
		-- floor gives pale stone, or the slabs vanish into it)
		if hit.Instance.Material == Enum.Material.Neon then col = ROCK end
		local lum = 0.3 * col.R + 0.59 * col.G + 0.11 * col.B
		if lum < 0.3 then col = Color3.fromRGB(138, 132, 156) end
		return hit.Position, col, mat
	end
	return onGround(pos), ROCK, Enum.Material.Slate
end

-- The crater: slabs of the floor wrenched up out of it in two ragged ridges
-- along the cone's edges, a V opening out from his fist, more broken out
-- along its middle; they burst up in a wave running outward, stand a while,
-- then sink back.
local function craterCone(at: Vector3, dir: Vector3, cone: number, half: number, mine: boolean)
	local g0, color, material = groundUnder(at)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local slabs: { BasePart } = {}
	local function slab(p: Vector3, outward: Vector3, size: Vector3, delay: number)
		local g = groundUnder(p)
		local tilt = math.rad(25 + math.random() * 30)
		local yaw = math.atan2(-outward.X, -outward.Z) + (math.random() - 0.5) * 0.6
		local rest = CFrame.new(g) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-tilt, 0, (math.random() - 0.5) * 0.5)
			* CFrame.new(0, size.Y * 0.25, 0)
		local shade = 0.8 + math.random() * 0.25
		local s = part({ Size = size, CFrame = rest * CFrame.new(0, -size.Y, 0),
			Color = Color3.new(math.min(color.R * shade, 1), math.min(color.G * shade, 1), math.min(color.B * shade, 1)),
			Material = material })
		table.insert(slabs, s)
		task.delay(delay, function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = rest }):Play()
			end
		end)
	end
	local speed = 70 -- studs a second the wave runs out
	-- the two ridges, along the edges of the cone
	for _, side in ipairs({ -1, 1 }) do
		local d = 2.5
		while d < cone do
			local w = math.tan(half) * d
			local out = (right * side + dir * 0.3).Unit
			local p = g0 + dir * d + right * side * (w + (math.random() - 0.5) * 1.2)
			local big = 2.6 + (d / cone) * 2.6
			slab(p, out, Vector3.new(big * (0.8 + math.random() * 0.5), big * (0.5 + math.random() * 0.3), big * (0.7 + math.random() * 0.5)), d / speed)
			d += 1.6 + math.random() * 1.0
		end
	end
	-- broken up along the middle too, fewer and lower
	local d = 4
	while d < cone * 0.95 do
		local w = math.tan(half) * d * 0.5
		local p = g0 + dir * d + right * (math.random() * 2 - 1) * w
		local s = 1.6 + math.random() * 1.6
		slab(p, (dir + right * (math.random() - 0.5)).Unit, Vector3.new(s * 1.2, s * 0.45, s), d / speed)
		d += 2.4 + math.random() * 1.6
	end
	-- dust and stone chips kicked up along it as the wave runs
	for k = 1, 5 do
		local p = g0 + dir * (cone * k / 5.5)
		task.delay(cone * k / 5.5 / speed, function()
			if mine or FxBudget.Allow("maCraterDust", 6) then
				ClassFX.Burst(p + Vector3.new(0, 1, 0), Color3.fromRGB(150, 140, 130), 8, 14, ClassFX.TEX_SPARK, 0.5, 0.6)
			end
		end)
	end
	-- they stand a while, then sink back into the floor
	task.delay(4, function()
		for _, s in ipairs(slabs) do
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = s.CFrame * CFrame.new(0, -s.Size.Y * 1.2, 0), Transparency = 1 }):Play()
				Debris:AddItem(s, 0.85)
			end
		end
	end)
	-- the blow itself: the flash at the fist, a ring of air
	local fistAt = g0 + dir * 2.2 + Vector3.new(0, 3, 0)
	flare(fistAt, 6, 0.16, HOT)
	punchRing(fistAt, dir, 2.2, 0.25, WHITE)
	if FxBudget.Allow("maCraterPack", 3) then
		PackFX.Burst("Anime/Smoke-01", CFrame.new(g0 + dir * cone * 0.5 + Vector3.new(0, 1, 0)), { color = Color3.fromRGB(140, 132, 124), scale = 1.1 })
	end
	ClassFX.Sound("punch", fistAt, 0.9, 0.7)
	ClassFX.Sound("thunder", fistAt, 0.4, 0.6)
	if mine and deps then
		deps.shake(0.6, 0.3)
		deps.fovPunch(7, 0.25)
	end
end

-- Everything you see of it (yours, or someone else's from the server).
local function barrageFx(char: Model?, dir: Vector3, cone: number, half: number, mine: boolean)
	if not char then return end
	local root = rootOf(char)
	if not root then return end
	local armR = char:FindFirstChild("Right Arm") :: BasePart?
	local armL = char:FindFirstChild("Left Arm") :: BasePart?
	ClassFX.Sound("whoosh", root.Position, 0.5, 1.6)
	-- his real arms (and whatever's fixed to them) vanish: only the blur of
	-- copies is seen, till he's back on guard
	local hidden: { BasePart } = {}
	for _, arm in ipairs({ armR, armL }) do
		if arm then
			table.insert(hidden, arm)
			for _, j in ipairs(arm:GetJoints()) do
				local other = if j:IsA("JointInstance") then (if j.Part0 == arm then j.Part1 else j.Part0)
					elseif j:IsA("WeldConstraint") then (if j.Part0 == arm then j.Part1 else j.Part0) else nil
				if other and other:IsA("BasePart") and other.Name ~= "Torso" and other.Name ~= "HumanoidRootPart" then
					table.insert(hidden, other)
				end
			end
		end
	end
	for _, p in ipairs(hidden) do p.LocalTransparencyModifier = 1 end
	task.delay(BARRAGE.total, function()
		for _, p in ipairs(hidden) do
			if p.Parent then p.LocalTransparencyModifier = 0 end
		end
	end)
	local t0 = os.clock()
	local nextArm, nextThud = 0, 0
	local right = Vector3.new(-dir.Z, 0, dir.X)
	animate(BARRAGE.duration, function()
		local t = os.clock() - t0
		local r = rootOf(char)
		if not r then return true end
		-- copies of his arms thrust out from each shoulder in turn, a storm of them
		-- (both arms every beat, each copy lingering: a dozen or so in the air
		-- at once)
		if t >= nextArm then
			nextArm = t + 0.02
			for _, side in ipairs({ -1, 1 }) do
				if mine or FxBudget.Allow("maBarrageArm", 100) then
					local shoulder = r.Position + right * side * 1.5 + Vector3.new(0, 0.5, 0)
					local from = shoulder + right * (math.random() - 0.5) * 1.6 + Vector3.new(0, (math.random() - 0.5) * 1.8, 0)
					local spread = CFrame.fromAxisAngle(Vector3.yAxis, (math.random() - 0.5) * 0.5):VectorToWorldSpace(dir)
					spread = (spread + Vector3.new(0, (math.random() - 0.5) * 0.25, 0)).Unit
					ghostArm(if side > 0 then armR else armL, from, spread, 2.5 + math.random() * 2.5, 0.16, 1)
				end
			end
		end
		if t >= nextThud then
			nextThud = t + 0.12
			local at = r.Position + dir * (4 + math.random() * 2) + Vector3.new(0, 0.5 + math.random(), 0)
			if mine or FxBudget.Allow("maBarrageSpark", 10) then sparks(at, 6, 18, WHITE) end
			ClassFX.Sound("punch", at, 0.25, 1.4 + math.random() * 0.3)
		end
		return nil
	end)
	-- the power punch: one great copy of his arm driven out along the cone
	task.delay(BARRAGE.punchAt - 0.04, function()
		local r = rootOf(char)
		if not r then return end
		ghostArm(armR, r.Position + right * 1.5 + Vector3.new(0, 0.5, 0), dir, cone * 0.6, 0.24, 2.6)
	end)
end

local function onBarrage(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	local char = charOf(owner)
	if char then barragePose(char) end
	barrageFx(char, flat(msg.dir :: Vector3), tonumber(msg.cone) or BARRAGE.cone, tonumber(msg.half) or BARRAGE.half, false)
end

local function onBarragePunch(msg: any)
	local mine = msg.attacker == player
	craterCone(msg.pos :: Vector3, flat(msg.dir :: Vector3), tonumber(msg.cone) or BARRAGE.cone, tonumber(msg.half) or BARRAGE.half, mine)
end

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

-- ── Q: Haymaker ─────────────────────────────────────────────────────────────
-- Built from the reference clip (@fadewhizz's Haymaker), stepped through at
-- 1/30 s from its top-down angle (the one closest to our camera). He stands
-- his ground; t = 0 is the release:
--   charge   4-5 thin bright blue lines run out along the floor ahead,
--            marking the lane (longer the longer he charges); a flat
--            whirlpool of blue-white crescents spins on the floor at his
--            feet with black ink shards flicking up out of it; a faint glassy
--            dome over him as it peaks
--   f0       a white flash card at the fist, speed lines behind it
--   f1-f3    a thick energy spear shoots down the lane; a ribbed glassy dome
--            wave bulges out ahead of the fist
--   f4-f8    the dome wave travels on down the lane, bright lane beams under it
--   f9-f14   it breaks into a row of glassy arcs along the lane, dark ink
--            flags and grey dust
--   after    a glowing line along the lane, then a dark scorch streak on the
--            floor that fades
-- (matches MartialServer's HAY)
local HAY = { full = 1.0, empFull = 0.5, hold = 2.2, length = 12, fullLength = 30, empLength = 1.2, half = 3.2, travel = 0.3, core = 1.3,
	gap = 5, after = 0.12, walk = 5 }
-- (Sett's W: the lane is a trapezoid, HAY.half x 0.35 wide either side at
-- his feet, x 1.3 at the far end; its centre strip HAY.core either side)
-- (from the League screenshot: half-widths a share of the lane's length L,
-- 0.14 L at his feet, 0.33 L at the far end; the strip as wide as the near end)
local function hayNear(L: number): number return math.max(L * 0.14, 1.6) end
local function hayFar(L: number): number return math.max(L * 0.33, 3) end
local HAY_BLUE = Color3.fromRGB(45, 95, 255)    -- (the clip's saturated blue)
local HAY_NAVY = Color3.fromRGB(22, 36, 120)    -- (the dark bodies in its whirlpool)
local HAY_ICE = Color3.fromRGB(210, 230, 255)
local HAY_TEX = VfxAssets.Energy.ice.id
local UP = Vector3.new(0, 1, 0)

local function hayLength(c: number, empowered: boolean): number
	local size = tonumber(player:GetAttribute("Stat_size")) or 1
	return (HAY.length + (HAY.fullLength - HAY.length) * c) * size * (if empowered then HAY.empLength else 1)
end

-- An attachment lying flat on the floor at `pos`, its beam running `along`.
local function flatAtt(h: BasePart, pos: Vector3, along: Vector3): Attachment
	local a = Instance.new("Attachment")
	local side = Vector3.new(-along.Z, 0, along.X)
	a.Parent = h
	a.WorldCFrame = CFrame.fromMatrix(pos, along, side)
	return a
end

local function newBeam(a0: Attachment, a1: Attachment, faceCamera: boolean, color: Color3, emission: number, tex: string?): Beam
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = faceCamera
	b.Texture = tex or HAY_TEX
	b.TextureMode = Enum.TextureMode.Wrap
	b.TextureLength = 4
	b.Color = ColorSequence.new(color)
	b.LightEmission = emission
	b.LightInfluence = 0
	b.Brightness = 2
	b.Segments = 6
	b.Parent = a0
	return b
end

-- The band pool: a band's holder, attachments and beam are made once and
-- handed back when it fades, so a burst of casts creates nothing new.
type PooledBand = { h: BasePart, a0: Attachment, a1: Attachment, bm: Beam }
local bandPool: { PooledBand } = {}
local function takeBand(): PooledBand
	local pb = table.remove(bandPool)
	if pb and pb.h.Parent then return pb end
	local h = carrier(CFrame.new())
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = h, h
	return { h = h, a0 = a0, a1 = a1, bm = newBeam(a0, a1, true, WHITE, 1) }
end
local function giveBand(pb: PooledBand)
	pb.bm.Transparency = NumberSequence.new(1)
	if #bandPool < 120 then table.insert(bandPool, pb) else pb.h:Destroy() end
end
-- A band from `a` to `b` (camera-facing unless `flatOnFloor`), fading over
-- `life`; `draw` seconds to run out from a to b.
local function hayBand(a: Vector3, b: Vector3, w0: number, w1: number, life: number, color: Color3, emission: number,
	flatOnFloor: boolean?, draw: number?, bend: number?)
	if not FxBudget.Allow("maHayBand", 90) then return end
	local d = (b - a)
	local along = if d.Magnitude > 0.01 then d.Unit else Vector3.xAxis
	-- (from the pool: a holder, two attachments and a beam made once, reused)
	local pb = takeBand()
	local a0, a1, bm = pb.a0, pb.a1, pb.bm
	if flatOnFloor then
		local sd = Vector3.new(-along.Z, 0, along.X)
		a0.WorldCFrame = CFrame.fromMatrix(a, along, sd)
		a1.WorldCFrame = CFrame.fromMatrix(a, along, sd)
	else
		a0.WorldCFrame, a1.WorldCFrame = CFrame.new(a), CFrame.new(a)
	end
	bm.FaceCamera = not flatOnFloor
	bm.Color = ColorSequence.new(color)
	bm.LightEmission = emission
	bm.CurveSize0, bm.CurveSize1 = 0, 0
	bm.Transparency = NumberSequence.new(0)
	bm.TextureSpeed = 6
	bm.Width0, bm.Width1 = w0, w1
	-- (`bend`: the band swings into an S: its bezier handles turned `bend`
	-- radians off the straight line, round the vertical)
	local hand = if bend then CFrame.Angles(0, bend, 0):VectorToWorldSpace(along) else along
	local function orient(att: Attachment, p: Vector3)
		local side = Vector3.new(-hand.Z, 0, hand.X)
		att.WorldCFrame = CFrame.fromMatrix(p, hand, if side.Magnitude > 0.01 then side.Unit else Vector3.zAxis)
	end
	if bend and not flatOnFloor then orient(a0, a) end
	local dr = draw or 0.001
	animate(life, function(x)
		local t = x * life
		local reach = math.min(t / dr, 1)
		local p = a:Lerp(b, easeOut(reach))
		if flatOnFloor then
			a1.WorldCFrame = CFrame.fromMatrix(p, along, Vector3.new(-along.Z, 0, along.X))
		elseif bend then
			orient(a1, p)
			local L = (p - a).Magnitude
			bm.CurveSize0, bm.CurveSize1 = L * 0.35, L * 0.35
		else
			a1.WorldPosition = p
		end
		bm.Transparency = NumberSequence.new(math.clamp((t - dr) / math.max(life - dr, 0.01), 0, 1) ^ 1.4)
		if x >= 1 then giveBand(pb) end
		return nil
	end)
end

-- A dark ink flag: one smooth curved ribbon rising `h` studs from `base`
-- along `up`, hooking over toward `over` at the top, `w` wide at the root
-- tapering to a point; grows over the first quarter of `life`, then fades.
local function inkFlag(base: Vector3, up: Vector3, over: Vector3, h: number, w: number, life: number)
	if not FxBudget.Allow("maHayBand", 90) then return end
	local hold = carrier(CFrame.new())
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Parent, a1.Parent = hold, hold
	local bm = newBeam(a0, a1, true, Color3.fromRGB(10, 14, 40), 0)
	bm.Segments = 12
	bm.Width0, bm.Width1 = w, 0.05
	animate(life, function(x)
		local g = easeOut(math.min(x / 0.25, 1))
		local tip = base + up * h * 0.75 * g + over * h * 0.55 * g
		local sideV = up:Cross(over)
		if sideV.Magnitude < 0.01 then sideV = Vector3.xAxis end
		-- (handles: straight up out of the root, then curving back over at the tip)
		a0.WorldCFrame = CFrame.fromMatrix(base, up, sideV.Unit)
		a1.WorldCFrame = CFrame.fromMatrix(tip, (-up * 0.3 + over).Unit, sideV.Unit)
		bm.CurveSize0 = h * 0.6 * g
		bm.CurveSize1 = -h * 0.35 * g
		bm.Transparency = NumberSequence.new(math.clamp((x - 0.45) / 0.55, 0, 1))
		if x >= 1 then hold:Destroy() end
		return nil
	end)
end
-- A frame standing upright on `at` in the plane of `dir`: an arc drawn with
-- it (VfxKit.Sweep) arches up over `at`.
local function upright(at: Vector3, dir: Vector3): CFrame
	local z = -UP
	return CFrame.fromMatrix(at, dir, z:Cross(dir), z)
end

-- ── The golden Haymaker ─────────────────────────────────────────────────────
-- The clip's shapes and timing (@fadewhizz's Sett-style Haymaker, 9.45-10.55,
-- release = t 0), built from Blender meshes (tools/blender/build_haymaker.py),
-- in gold, on Sett's W footprint: a trapezoid narrow at his feet and wide at
-- the far end (hayNear / hayFar), the area the server hits.
--   charge   a glass dome over him, a disk of blades spinning flat at his
--            feet, the trapezoid's lines fanning out ahead, energy drawn
--            into the fist, the fist glowing hotter
--   0.00     a big outlined fist shoots out of him, a star flash, dots,
--            speed lines
--   0.07     the torpedo stretches down the trapezoid's centre, portal rings
--            open at the fist
--   0.15     a glass dome shell bulges forward round the fist
--   0.45     it breaks into glass arches down the lane, each as wide as the
--            trapezoid there, dark ink ribbons curling over them
--   0.6+     the lines fade, a dark streak stays on the floor
local G_HOT = Color3.fromRGB(255, 247, 210)
local G_GOLD = Color3.fromRGB(255, 196, 55)
local G_ORANGE = Color3.fromRGB(255, 125, 30)
local G_OUTLINE = Color3.fromRGB(70, 18, 6)
local G_INK = Color3.fromRGB(26, 9, 5)
local G_TEX = VfxAssets.Energy.fire.id
local G_GLOW = VfxAssets.Glow.soft.id
local HT = VfxAssets.Hay

-- Where his punching fist is (the right arm's end), or a guess in front.
local function fistPos(char: Model?, root: BasePart, dir: Vector3): Vector3
	local arm = char and char:FindFirstChild("Right Arm") :: BasePart?
	if arm then return (arm.CFrame * CFrame.new(0, -1.15, 0)).Position end
	return root.Position + dir * 1.6 + UP * 0.3
end

-- A copy of one of the Haymaker's meshes (nil while it or its texture is
-- still loading: never a white shape). Kept out of VfxDetail's toning.
local function hayMesh(name: string, tex: string?, color: Color3?, outline: boolean?): MeshPart?
	if tex and not VfxKit.TexReady(tex) then return nil end
	local mp = VfxKit.Acquire(name, tex or "")
	if not mp then return nil end
	mp:SetAttribute("VfxToned", true)
	mp.DoubleSided = true -- (the template's; outlines turn it off below)
	mp.Material = Enum.Material.Neon
	if outline then
		-- the inverted hull: faces turned in, so only its far side draws, as an outline
		mp.Material = Enum.Material.SmoothPlastic
		mp.DoubleSided = false
		mp.Color = G_OUTLINE
	else
		mp.Material = Enum.Material.Neon
		mp.Color = color or Color3.new(1, 1, 1)
	end
	mp.Transparency = 1
	mp.Parent = ClassFX.Folder()
	return mp
end

-- (sizes are multiples of each mesh's native size)
local function sizeOf(name: string, k: Vector3): Vector3
	return VfxKit.MeshSize(name) * k
end

-- The trapezoid's floor lines (edges, inner fan lines, far end, centre strip).
type Lane = { set: (Vector3, Vector3, number, number, number) -> (), destroy: () -> () }
local function buildLane(): Lane
	local h = carrier(CFrame.new())
	type Line = { a0: Attachment, a1: Attachment, b: Beam, spec: { number }, kind: string }
	local lines: { Line } = {}
	local function add(kind: string, spec: { number }, color: Color3, w: number)
		local a0, a1 = flatAtt(h, Vector3.zero, Vector3.xAxis), flatAtt(h, Vector3.zero, Vector3.xAxis)
		local b = newBeam(a0, a1, false, color, 1, G_TEX)
		b.TextureSpeed = 8
		b.Width0, b.Width1 = w, w
		b.Transparency = NumberSequence.new(1)
		table.insert(lines, { a0 = a0, a1 = a1, b = b, spec = spec, kind = kind })
	end
	add("strip", { 0, 0, 1, 0 }, G_GOLD, 1)
	add("edge", { 0, -1, 1, -1 }, G_GOLD, 0.35)
	add("edge", { 0, 1, 1, 1 }, G_GOLD, 0.35)
	add("edge", { 0, -0.45, 1, -0.45 }, G_HOT, 0.18)
	add("edge", { 0, 0.45, 1, 0.45 }, G_HOT, 0.18)
	add("edge", { 1, -1, 1, 1 }, G_GOLD, 0.35)
	return {
		-- base: the lane's start on the floor; L: its length now; full: its
		-- full length (sets its widths); tr: transparency (the strip fainter)
		set = function(base: Vector3, dir: Vector3, L: number, full: number, tr: number)
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local near, far = hayNear(full), hayFar(full)
			for _, ln in ipairs(lines) do
				local sp = ln.spec
				local function w(a: number): number
					return if ln.kind == "strip" then near else near + (far - near) * a * L / math.max(full, 0.01)
				end
				local from = base + dir * (L * sp[1]) + side * sp[2] * w(sp[1])
				local to = base + dir * (L * sp[3]) + side * sp[4] * w(sp[3])
				local ad = if (to - from).Magnitude > 0.01 then (to - from).Unit else dir
				local sd = Vector3.new(-ad.Z, 0, ad.X)
				ln.a0.WorldCFrame = CFrame.fromMatrix(from, ad, sd)
				ln.a1.WorldCFrame = CFrame.fromMatrix(to, ad, sd)
				if ln.kind == "strip" then
					ln.b.Width0, ln.b.Width1 = near * 2, near * 2
					ln.b.Transparency = NumberSequence.new(math.clamp(tr + 0.8, 0, 1))
				else
					ln.b.Transparency = NumberSequence.new(tr)
				end
			end
		end,
		destroy = function()
			for _, ln in ipairs(lines) do ln.b.Transparency = NumberSequence.new(1) end
		end,
	}
end
-- (pooled: a lane's lines are made once; destroy() hides it and hands it back)
local lanePool: { Lane } = {}
local function hayLane(): Lane
	local lane = table.remove(lanePool) or buildLane()
	return {
		set = lane.set,
		destroy = function()
			lane.destroy()
			if #lanePool < 8 then table.insert(lanePool, lane) end
		end,
	}
end

-- 1 · The charge round `char`. `getDir()` gives the aim each frame.
type HayFx = { stop: (boolean) -> () }
local function haymakerChargeFx(char: Model, full: number, hold: number, empowered: boolean, mine: boolean,
	getDir: () -> Vector3): HayFx
	local root = rootOf(char)
	if not root then return { stop = function() end } end
	local lane = hayLane()
	local dome = hayMesh("hay_dome", HT.shell.id, G_GOLD)
	local whirl = hayMesh("hay_whirl", HT.whirl.id, G_GOLD)
	if dome then dome.DoubleSided = true end
	if whirl then whirl.DoubleSided = true end

	-- the fist: a hot glow that grows with the charge (and one short-lived light)
	local fistPart = part({ Size = Vector3.one * 0.2, Transparency = 1 })
	local fa = Instance.new("Attachment")
	fa.Parent = fistPart
	local fistGlow = emitter(fa, { Texture = G_GLOW, Color = ColorSequence.new(G_HOT, G_GOLD), LightEmission = 1, Brightness = 3,
		Size = nseq(0, 1.2, 1, 1.6), Transparency = nseq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.12), Speed = NumberRange.new(0),
		Rate = 40, LockedToPart = true, ZOffset = 1 })
	local light: PointLight? = nil
	if FxBudget.Light() then
		light = Instance.new("PointLight")
		light.Color, light.Range, light.Brightness, light.Shadows = G_GOLD, 10, 0.5, false
		light.Parent = fa
	end
	-- energy drawn into the fist
	local well = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Transparency = 1 })
	local gather = emitter(well, { Texture = TEX_SPARKLE, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, G_ORANGE),
			ColorSequenceKeypoint.new(0.6, G_GOLD), ColorSequenceKeypoint.new(1, G_HOT) }),
		LightEmission = 1, Brightness = 3, Size = nseq(0, 0.25, 0.5, 0.55, 1, 0.15), Transparency = nseq(0, 1, 0.2, 0, 1, 0),
		Lifetime = NumberRange.new(0.35, 0.45), Speed = NumberRange.new(9, 11), Rate = 0,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface,
		ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward, Orientation = Enum.ParticleOrientation.VelocityParallel })

	local t0 = os.clock()
	local alive = true
	local wasFull = false
	local nextShard = 0
	local spin = 0
	animate(hold + 0.3, function(_x, dt)
		if not alive or not root.Parent then return true end
		local t = os.clock() - t0
		local k = math.min(t / full, 1)
		local dir = flat(getDir())
		local g = onGround(root.Position)
		-- the trapezoid runs out ahead as it charges
		local fullL = hayLength(k, empowered)
		lane.set(g + UP * 0.15 + dir * 0.6, dir, 1 + fullL * math.clamp(k * 1.2, 0.08, 1), fullL, 0.5 - 0.35 * k)
		-- the blades spinning flat at his feet, opening as it builds
		spin += dt * (6 + 10 * k)
		if whirl then
			local R = 2 + 3 * k
			whirl.Size = sizeOf("hay_whirl", Vector3.new(R / 0.95, 1, R / 0.95))
			whirl.CFrame = CFrame.new(g + UP * 0.12) * CFrame.Angles(0, spin, 0)
			whirl.Transparency = 0.5 - 0.4 * k
		end
		-- the glass dome over him (pole up), faint, firming up as it peaks
		if dome then
			local R = 4 + 1.5 * k
			dome.Size = sizeOf("hay_dome", Vector3.new(R, R, R))
			dome.CFrame = CFrame.lookAt(g + UP * (R * 0.5), g + UP * (R * 0.5 + 1), dir)
			dome.Transparency = 0.85 - 0.3 * math.clamp((k - 0.3) / 0.7, 0, 1)
		end
		-- dark shards flicking up off the disk's edge
		if os.clock() >= nextShard and FxBudget.Allow("maHayShard", 30) then
			nextShard = os.clock() + 0.12 - 0.06 * k
			local a = math.random() * math.pi * 2
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			local p = g + out * (2 + 2.5 * k)
			hayBand(p, p + (out * 0.6 + UP).Unit * (1.5 + 2 * k), 0.4 + 0.4 * k, 0, 0.3, G_INK, 0, false, 0.08)
		end
		-- the fist grows brighter and hotter, energy drawn into it
		local fp = fistPos(char, root, dir)
		fistPart.CFrame = CFrame.new(fp)
		well.CFrame = CFrame.new(fp)
		well.Size = Vector3.one * (7 - 2.5 * k)
		local fs = 1 + 2.6 * k
		fistGlow.Size = nseq(0, fs, 1, fs * 1.3)
		fistGlow.Brightness = 2 + 4 * k
		if light then light.Brightness = 0.5 + 2.5 * k end
		gather.Rate = 25 + 70 * k
		if k >= 1 and not wasFull then
			wasFull = true
			VfxKit.Flash(fp, "fire", 6, 0.1, G_HOT)
			if mine then ClassFX.Sound("charge", root, 0.6, 1.4) end
		end
		return nil
	end)
	return {
		stop = function(_full: boolean)
			alive = false
			fistGlow.Enabled = false
			gather.Enabled = false
			if light then light:Destroy() end
			lane.destroy()
			VfxKit.Release(dome); VfxKit.Release(whirl)
			task.delay(0.5, function() fistPart:Destroy(); well:Destroy() end)
		end,
	}
end

-- 2 · The release (t = 0 at the clip's 9.65), down the trapezoid from
-- `origin` along `dir`. `slow` > 1 stretches every timing (Studio checks).
local function haymakerFire(origin: Vector3, dir: Vector3, c: number, length: number, _half: number, mine: boolean, slow: number?)
	local S = slow or 1
	local g = onGround(origin)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local fist = origin + dir * 1.6 + UP * 0.3
	local near, far = hayNear(length), hayFar(length)
	local function widthAt(d: number): number return near + (far - near) * math.clamp(d / length, 0, 1) end
	local face = function(p: Vector3): CFrame return CFrame.lookAt(p, p + dir) end
	local fin = g + dir * length

	-- the trapezoid on the floor, bright, fading after the arches
	local lane = hayLane()
	animate(1.0 * S, function(x)
		lane.set(g + UP * 0.15 + dir * 0.6, dir, length * easeOut(math.min(x * 1.0 / 0.3, 1)), length, 0.05 + 0.95 * math.clamp((x - 0.6) / 0.4, 0, 1))
		if x >= 1 then lane.destroy() end
		return nil
	end)

	-- 0.00: the fist shooting out, outlined; the star flash, dots, speed lines
	local F, FH = hayMesh("hay_fist", nil, G_GOLD), hayMesh("hay_fist_hull", nil, nil, true)
	animate(0.13 * S, function(x)
		local k = 1.6 + 1.2 * easeOut(math.min(x / 0.6, 1)) + 0.4 * c
		local p = fist + dir * (1 + 5 * easeOut(x)) + UP * 0.6
		local tr = math.clamp((x - 0.65) / 0.35, 0, 1)
		if F then F.Size = sizeOf("hay_fist", Vector3.one * k); F.CFrame = face(p); F.Transparency = 0.02 + 0.98 * tr end
		-- (the hull a touch bigger than the fist: the outline shows all round it)
		if FH then FH.Size = sizeOf("hay_fist_hull", Vector3.one * k * 1.06); FH.CFrame = face(p); FH.Transparency = tr end
		if x >= 1 then VfxKit.Release(F); VfxKit.Release(FH) end
		return nil
	end)
	VfxKit.Flash(fist + dir * 2 + UP * 0.6, "fire", 8 + 4 * c, 0.1 * S, G_HOT)
	do -- the clip's dots: a field of small hot specks thrown up round the fist
		local hold = carrier(CFrame.lookAt(fist + dir * 1.5 + UP, fist + dir * 2.5 + UP))
		hold.Size = Vector3.new(7, 4, 2)
		local e = emitter(hold, { Texture = TEX_SPARKLE, Color = ColorSequence.new(G_HOT, G_GOLD), LightEmission = 1, Brightness = 3,
			Size = nseq(0, 0.35, 1, 0.1), Lifetime = NumberRange.new(0.12 * S, 0.2 * S), Speed = NumberRange.new(0),
			Shape = Enum.ParticleEmitterShape.Box, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, Rate = 0 })
		e:Emit(36)
		Debris:AddItem(hold, 0.4 * S)
	end
	for _ = 1, 7 do
		local o = side * (math.random() - 0.5) * 6 + UP * (math.random() * 3 - 0.5)
		local p = fist + o
		hayBand(p, p - dir * (3 + math.random() * 4), 0.14, 0.02, 0.15 * S, G_HOT, 1)
	end

	-- 0.07: the torpedo down the centre, the portal rings at the fist
	local TP, TPH = hayMesh("hay_torpedo", HT.torpedo.id, G_GOLD), hayMesh("hay_torpedo_hull", nil, nil, true)
	local RG = hayMesh("hay_rings", nil, G_HOT)
	task.delay(0.07 * S, function()
		animate(0.33 * S, function(x)
			local L = math.max(length * 0.8 * easeOut(math.min(x / 0.55, 1)), 0.5)
			local w = (near * 1.5) / 0.2855 * (0.6 + 0.4 * easeOut(math.min(x / 0.3, 1)))
			local p = fist + UP * 0.3 + dir * (L * 0.5 + 0.5)
			local tr = math.clamp((x - 0.7) / 0.3, 0, 1)
			if TP then TP.Size = sizeOf("hay_torpedo", Vector3.new(w, w, L)); TP.CFrame = face(p); TP.Transparency = 0.02 + 0.98 * tr end
			if TPH then TPH.Size = sizeOf("hay_torpedo_hull", Vector3.new(w, w, L)); TPH.CFrame = face(p); TPH.Transparency = tr end
			if RG then
				local r = 1.3 + 1.6 * easeOut(x)
				RG.Size = sizeOf("hay_rings", Vector3.new(r, r, 1.5))
				RG.CFrame = face(fist + dir * 1.2 + UP * 0.4)
				RG.Transparency = 0.05 + 0.95 * math.clamp((x - 0.5) / 0.5, 0, 1)
			end
			if x >= 1 then VfxKit.Release(TP); VfxKit.Release(TPH); VfxKit.Release(RG) end
			return nil
		end)
	end)

	-- 0.15: the glass dome shell bulging forward round the fist, warm smoke
	local DM = hayMesh("hay_dome", HT.shell.id, G_HOT)
	if DM then DM.DoubleSided = true end
	task.delay(0.15 * S, function()
		VfxKit.Puffs({ fist + dir * 2 + UP, fist + dir * 3.5 + side * 1.5 + UP, fist + dir * 3.5 - side * 1.5 + UP }, "fire", 3.5, 0.6 * S)
		animate(0.42 * S, function(x)
			local R = math.max(near * 1.6, 4.5) * (0.55 + 0.45 * easeOut(math.min(x / 0.4, 1)))
			if DM then
				DM.Size = sizeOf("hay_dome", Vector3.new(R, R, R))
				DM.CFrame = face(fist + UP * 0.6 + dir * (R * 0.5 + 0.5))
				DM.Transparency = 0.15 + 0.85 * math.clamp((x - 0.6) / 0.4, 0, 1)
			end
			if x >= 1 then VfxKit.Release(DM) end
			return nil
		end)
	end)

	-- 0.45: the arches down the lane, each spanning the trapezoid there, ink curling over
	local n = 5
	for i = 1, n do
		local d = length * (0.12 + 0.82 * (i - 1) / (n - 1))
		task.delay((0.45 + 0.04 * (i - 1)) * S, function()
			local AR = hayMesh("hay_arch", HT.shell.id, G_HOT)
			if not AR then return end
			AR.DoubleSided = true
			local w = widthAt(d)
			local yaw = CFrame.Angles(0, math.rad(math.random(-10, 10)), 0)
			local at = onGround(origin + dir * d)
			animate(0.45 * S, function(x)
				local s = 0.7 + 0.3 * easeOut(math.min(x / 0.25, 1))
				local H = w * 0.85 * s
				AR.Size = sizeOf("hay_arch", Vector3.new(w * s, H, 1.6))
				AR.CFrame = face(at + UP * (H * 0.5)) * yaw
				AR.Transparency = 0.1 + 0.9 * math.clamp((x - 0.55) / 0.45, 0, 1)
				if x >= 1 then VfxKit.Release(AR) end
				return nil
			end)
			if i % 2 == 1 then
				local IK = hayMesh("hay_ink", nil, G_INK)
				if IK then
					IK.Material = Enum.Material.SmoothPlastic
					IK.DoubleSided = true
					local sg = if i % 4 == 1 then 1 else -1
					local base = at + side * sg * w * 0.8
					animate(0.5 * S, function(x)
						local s = 3 + 1.5 * easeOut(math.min(x / 0.3, 1))
						IK.Size = sizeOf("hay_ink", Vector3.one * s)
						IK.CFrame = CFrame.lookAt(base + UP * (s * 0.58), base + UP * (s * 0.58) + dir) * CFrame.Angles(0, math.rad(-25 * sg), 0)
						IK.Transparency = math.clamp((x - 0.55) / 0.45, 0, 1)
						if x >= 1 then VfxKit.Release(IK) end
						return nil
					end)
				end
			end
		end)
	end

	-- after: a dark streak on the floor down the lane, a glow under it
	VfxKit.FloorGlow(g + dir * length * 0.35, G_ORANGE, length * 0.55, 0.35 * S, false)
	task.delay(0.6 * S, function()
		hayBand(g + UP * 0.08 + dir * 1, fin + UP * 0.08, 1.5, 0.05, 1.8 * S, Color3.fromRGB(14, 6, 3), 0, true, 0.001)
		hayBand(g + UP * 0.07 + dir * 1.5, fin + UP * 0.07 - dir * 2, 2.6, 0.3, 1.4 * S, Color3.fromRGB(34, 14, 6), 0, true, 0.001)
	end)

	ClassFX.Sound("boom", origin, 0.8 + 0.3 * c, 1.1)
	ClassFX.Sound("whoosh", origin, 0.8, 0.7)
	if mine and deps and S == 1 then
		deps.shake(0.5 + 0.5 * c, 0.25)
		deps.fovPunch(5 + 4 * c, 0.25)
	end
end

type Haymaking = { t0: number, full: number, char: Model, root: BasePart, fx: HayFx, token: {}, empowered: boolean }
local haymaking: Haymaking? = nil
-- (a dash drops a charging Haymaker, as on the server: no punch goes off)
(require(script.Parent:WaitForChild("DashController")) :: any).OnCancel(function(c: Model)
	local h = haymaking
	if not h or c ~= player.Character then return end
	haymaking = nil
	h.fx.stop(false)
	c:SetAttribute("AllowSkillMovement", false)
	local hum = c:FindFirstChildOfClass("Humanoid")
	if hum and not hum.PlatformStand then hum.AutoRotate = true end
	CastPoses.stop(c)
end)

local function startHaymaker(char: Model, root: BasePart, empowered: boolean)
	local full = if empowered then HAY.empFull else HAY.full
	local token = {}
	busyUntil = math.huge
	focusPose(char, HAY.hold, full)
	haymaking = { t0 = os.clock(), full = full, char = char, root = root, token = token, empowered = empowered,
		fx = haymakerChargeFx(char, full, HAY.hold, empowered, true, function()
			return if deps and root.Parent then deps.getAim(root) else root.CFrame.LookVector
		end) }
	-- (creeping about at a slow walk while it charges, always turned to the aim)
	char:SetAttribute("AllowSkillMovement", true)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if hum then hum.AutoRotate = false end
	animate(HAY.hold, function()
		local f = haymaking
		if not f or f.token ~= token then return true end
		if hum then hum.WalkSpeed = HAY.walk end
		if root.Parent and deps then
			local d = flat(deps.getAim(root))
			root.CFrame = CFrame.lookAt(root.Position, root.Position + d)
		end
		return nil
	end)
	-- (held all the way: it goes off on its own)
	task.delay(HAY.hold, function()
		local f = haymaking
		if f and f.token == token then MartialController.Release(3) end
	end)
end

-- Everyone else's Haymaker: the charge, then the wave.
local hayCharging: { [Player]: HayFx } = {}
local function onHaymakerCharge(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	local char = charOf(owner)
	local root = rootOf(char)
	if not (char and root) then return end
	local full = tonumber(msg.full) or HAY.full
	focusPose(char, tonumber(msg.hold) or HAY.hold, full)
	local old = hayCharging[owner]
	if old then old.stop(false) end
	hayCharging[owner] = haymakerChargeFx(char, full, tonumber(msg.hold) or HAY.hold, msg.empowered == true, false,
		function() return root.CFrame.LookVector end)
end
local function onHaymakerRelease(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	local fx = hayCharging[owner]
	hayCharging[owner] = nil
	if fx then fx.stop(msg.full == true) end
	local char = charOf(owner)
	local c = tonumber(msg.charge) or 0
	if char then focusPunchPose(char, c) end
	haymakerFire(msg.pos :: Vector3, flat(msg.dir :: Vector3), c, tonumber(msg.length) or HAY.length,
		tonumber(msg.half) or HAY.half, false)
end
local function onHaymakerHit(_msg: any) end
-- (Studio checks: the wave on its own, from the command bar / test tools)
MartialController.DebugHaymaker = haymakerFire

-- ── (old) Q: Ground Slam ────────────────────────────────────────────────────
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

-- ── R: Dragon Soul ─────────────────────────────────────────────────────────
-- 1 · The summoning (the ult's cinematic): a crimson circle burns into the
-- floor, the rubble lifts, the world reddens, and a crimson Qi dragon
-- spirals up out of the floor round him to roar over his head; then it
-- bursts out (the server's roar). 2 · For the buff: the dragon coils round
-- him and, with every strike he throws, lashes out along it, jaws open, and
-- curls back.

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

-- Is `p`'s dragon out (the buff running)?
local function dragonActive(p: Player): boolean
	return (tonumber(p:GetAttribute("MA_DragonUntil")) or 0) > Workspace:GetServerTimeNow()
end

-- 1 · The summoning round `char` (facing `dir`) for `rise` seconds.
local function summonFx(char: Model, dir: Vector3, rise: number, mine: boolean)
	local root = rootOf(char)
	if not root then return end
	local pos = onGround(root.Position)
	if mine or near(pos, 90) then tint(rise + 0.7) end
	sigil(pos, rise + 0.5)
	PackFX.Burst("Big/Big-Crack-01", CFrame.new(pos + Vector3.new(0, 0.1, 0)), { color = CRIMSON, scale = 0.9 })
	PackFX.Burst("Anime/Smoke-01", CFrame.new(pos + Vector3.new(0, 0.6, 0)), { color = Color3.fromRGB(120, 112, 118), scale = 1.3 })
	local rocks = rubble(pos, 10, 9, 3)
	task.delay(rise, function() rocks.throw(dir) end)
	ClassFX.Sound("wind", pos, 0.7, 0.7, rise)
	-- the dragon spirals up round him, tightening, and rears over his head
	local dragon = newDragon(1.1, pos + Vector3.new(6, 0, 0), Vector3.yAxis, 0.5)
	animate(rise, function(a)
		if not root.Parent then
			dragon.destroy()
			return true
		end
		local c = root.Position
		local ang = a * math.pi * 3.5
		local r = 6.5 - 3.5 * easeOut(a)
		local h = -2.5 + 10 * easeOut(a)
		local p = c + Vector3.new(math.cos(ang) * r, h, math.sin(ang) * r)
		local tangent = Vector3.new(-math.sin(ang), 0.6, math.cos(ang))
		-- (at the top it turns to look down the aim)
		local look = tangent:Lerp(dir + Vector3.new(0, -0.3, 0), math.clamp((a - 0.75) / 0.25, 0, 1))
		dragon.move(p, look)
		dragon.set(math.min(a / 0.15, 1))
		dragon.jaw(math.clamp((a - 0.7) / 0.3, 0, 1))
		if a >= 1 then dragon.destroy() end
		return nil
	end)
	-- 2 · the roar: it bursts out round him
	task.delay(rise, function()
		local at = if root.Parent then root.Position else pos
		local g = onGround(at)
		flare(at + Vector3.new(0, 2, 0), 16, 0.35, HOT)
		shell(at, 2, 28, 0.45, CRIMSON)
		floorRing(g, 14, 0.5, CRIMSON, 1.2)
		task.delay(0.08, function() floorRing(g, 18, 0.5, HOT, 0.6) end)
		PackFX.Burst("Anime/Charge-01", CFrame.new(at), { color = CRIMSON, scale = 1.6 })
		PackFX.Burst("Big/Big-Crack-01", CFrame.new(g + Vector3.new(0, 0.1, 0)), { color = CRIMSON, scale = 1.3 })
		SwordFX.Rays(g + Vector3.new(0, 0.3, 0), 20, 16, CRIMSON, 0.35)
		sparks(at, 36, 32, HOT)
		ClassFX.Sound("fireBurst", at, 1, 0.6)
		ClassFX.Sound("boom", at, 0.9, 0.8)
		ClassFX.Sound("quake", at, 0.5, 1.1)
		if mine and deps then
			deps.shake(0.7, 0.3)
			deps.fovPunch(8, 0.3)
			flash(0.22, 0.65)
		elseif near(at, 50) and deps then
			deps.shake(0.3, 0.15)
		end
	end)
end

-- 2 · The coiling dragon, one per Martial Artist whose buff is running.
-- Each strike starts a cycle timed to end as the next strike comes (the
-- interval at his attack speed; for other players, the gap between their
-- last two lashes): the dragon lashes out along the strike (the first
-- LASH_SHARE of it), then sweeps a full circle round him back to its orbit
-- (the rest). Faster attacks, a faster loop: it always gets all the way
-- round between strikes. Without a new strike it coils on at DRAGON.spin.
local LASH_SHARE = 0.3
type Coil = { dragon: Dragon, angle: number, alpha: number, lashAt: number, lashDir: Vector3, lashReach: number,
	lashFrom: Vector3, at: Vector3, cycle: number, lastLash: number }
local coils: { [Player]: Coil } = {}

-- Send `p`'s dragon lashing out along `dir`.
local function lash(p: Player, dir: Vector3, reach: number)
	local c = coils[p]
	if not c then return end
	local now = os.clock()
	local interval
	if p == player then
		local s = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1) * DRAGON.speed
		interval = COMBO_INTERVAL / s
	else
		interval = if now - c.lastLash < 1.5 then now - c.lastLash else COMBO_INTERVAL / DRAGON.speed
	end
	c.cycle = math.clamp(interval, 0.1, 1.2)
	c.lastLash = now
	c.lashAt = now
	c.lashDir = flat(dir)
	c.lashReach = reach
	c.lashFrom = c.at
	local root = rootOf(charOf(p))
	if root and FxBudget.Allow("maDragonLash", 10) then
		local d = c.lashDir
		local tip = root.Position + d * reach + Vector3.new(0, 1, 0)
		task.delay(c.cycle * LASH_SHARE, function()
			flare(tip, 5, 0.2, HOT)
			sparks(tip, 10, 18, CRIMSON)
			if FxBudget.Allow("maDragonLashPack", 4) then
				PackFX.Burst("Anime/Punch-03", CFrame.lookAt(tip, tip + d), { color = CRIMSON, scale = 1.1 })
			end
		end)
		if p == player then ClassFX.Sound("whoosh", root, 0.5, 0.8) end
	end
end

local function stepCoils(dt: number)
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	for _, p in ipairs(Players:GetPlayers()) do
		local root = rootOf(charOf(p))
		local want = root ~= nil and isMartial(p) and dragonActive(p)
			and (cam == nil or (cam.CFrame.Position - (root :: BasePart).Position).Magnitude < 180)
		local c = coils[p]
		if want and not c and root then
			local start = root.Position + Vector3.new(DRAGON.orbit, DRAGON.height, 0)
			c = { dragon = newDragon(0.8, start, Vector3.zAxis, 0.45), angle = 0, alpha = 0, lashAt = -1, lashDir = Vector3.zAxis,
				lashReach = DRAGON.reach, lashFrom = start, at = start, cycle = COMBO_INTERVAL, lastLash = -10 }
			coils[p] = c
		end
		if c then
			c.alpha = math.clamp(c.alpha + (if want then dt * 3 else -dt * 2.5), 0, 1)
			if c.alpha <= 0 and not want then
				c.dragon.destroy()
				coils[p] = nil
			elseif root then
				local center = root.Position
				local u = (now - c.lashAt) / c.cycle
				local bob = math.sin(now * 3) * 0.5
				local pos, look, jaw
				local tip = center + c.lashDir * c.lashReach + Vector3.new(0, 1, 0)
				if u >= 0 and u < LASH_SHARE then
					-- the lash: out along the strike
					pos = c.lashFrom:Lerp(tip, easeOut(u / LASH_SHARE))
					look = c.lashDir
					jaw = 1
					-- (where the circle round him starts: the lash's own angle)
					c.angle = math.atan2(c.lashDir.Z, c.lashDir.X)
				elseif u >= LASH_SHARE and u < 1 then
					-- the circle: one full turn round him, drawing in from the
					-- lash's reach to its orbit and down to its height
					local k = (u - LASH_SHARE) / (1 - LASH_SHARE)
					local tipAngle = math.atan2(c.lashDir.Z, c.lashDir.X)
					c.angle = tipAngle + k * math.pi * 2
					local r = c.lashReach + (DRAGON.orbit - c.lashReach) * easeOut(math.min(k * 1.6, 1))
					local h = 1 + (DRAGON.height + bob - 1) * easeOut(k)
					pos = center + Vector3.new(math.cos(c.angle) * r, h, math.sin(c.angle) * r)
					look = Vector3.new(-math.sin(c.angle), 0, math.cos(c.angle))
					jaw = 1 - k * 0.75
				else
					-- coiling on round him till the next strike
					c.angle += DRAGON.spin * dt
					local a = c.angle
					pos = center + Vector3.new(math.cos(a) * DRAGON.orbit, DRAGON.height + bob, math.sin(a) * DRAGON.orbit)
					look = Vector3.new(-math.sin(a), math.cos(now * 3) * 0.15, math.cos(a))
					jaw = 0.25
				end
				c.at = pos
				c.dragon.move(pos, look)
				c.dragon.jaw(jaw)
				c.dragon.set(c.alpha)
			end
		end
	end
	for p, c in pairs(coils) do
		if not p.Parent then
			c.dragon.destroy()
			coils[p] = nil
		end
	end
end

-- Another Martial Artist's summoning (ours is drawn as it's cast).
local function onDragonSoul(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	local char = charOf(owner)
	if not char then return end
	roarPose(char)
	summonFx(char, flat(msg.dir :: Vector3), tonumber(msg.rise) or DRAGON.rise, false)
end

local function onDragonLash(msg: any)
	local owner = msg.attacker :: Player
	if owner == player then return end
	lash(owner, msg.dir :: Vector3, tonumber(msg.reach) or DRAGON.reach)
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
	barrage = onBarrage,
	barragePunch = onBarragePunch,
	focusCharge = onFocusCharge,
	focusRelease = onFocusRelease,
	focusLanded = onFocusLanded,
	uppercut = onUppercut,
	uppercutHit = onUppercutHit,
	ascent = onAscent,
	haymakerCharge = onHaymakerCharge,
	haymakerRelease = onHaymakerRelease,
	haymakerHit = onHaymakerHit,
	dragonSoul = onDragonSoul,
	dragonLash = onDragonLash,
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
	local s = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	-- (the Dragon Soul's haste)
	return if dragonActive(player) then s * DRAGON.speed else s
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
	-- (the Dragon Soul: it lashes out along the strike)
	if dragonActive(player) then lash(player, dir, DRAGON.reach * size) end
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
		-- Hundred Fists: planted for the barrage and the punch (the crater
		-- comes with the server's word that it landed)
		busyUntil = os.clock() + BARRAGE.total
		releaseAfter(char, BARRAGE.total)
		-- he can creep along at a slow walk through the barrage, still facing
		-- where it was aimed (the server hits along that); planted for the
		-- power punch
		char:SetAttribute("AllowSkillMovement", true)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.AutoRotate = false end
		animate(BARRAGE.duration, function(a)
			if hum then hum.WalkSpeed = BARRAGE.walk end
			if root.Parent then root.CFrame = CFrame.lookAt(root.Position, root.Position + dir) end
			if a >= 1 and char.Parent then
				char:SetAttribute("AllowSkillMovement", false)
				plant(char, BARRAGE.total - BARRAGE.duration)
			end
			return nil
		end)
		task.delay(BARRAGE.total, function()
			if hum and hum.Parent and not hum.PlatformStand then hum.AutoRotate = true end
		end)
		barragePose(char)
		local size = tonumber(player:GetAttribute("Stat_size")) or 1
		barrageFx(char, dir, BARRAGE.cone * size * (if empowered then 1.3 else 1), BARRAGE.half, true)
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
		-- Haymaker: held to charge (MartialController.Release(3) on key-up)
		startHaymaker(char, root, empowered)
		return nil
	elseif skillIndex == 4 then
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = os.clock() + DRAGON.rise
		roarPose(char)
		summonFx(char, dir, DRAGON.rise, true)
		releaseAfter(char, DRAGON.rise + 0.1)
		return nil
	end
	return nil
end

-- The Focus Strike's key came up (SkillController), or it was held all the
-- way: the punch, as hard as it got.
function MartialController.Release(skillIndex: number)
	if skillIndex == 3 then
		-- the Haymaker: the dash and the punch, as hard as it got
		local h = haymaking
		if not h then return end
		haymaking = nil
		local char, root = h.char, h.root
		local held = os.clock() - h.t0
		local c = math.clamp(held / h.full, 0, 1)
		local full = c >= 0.999
		local dir = if root.Parent and deps then flat(deps.getAim(root)) else flat(root.CFrame.LookVector)
		Network.GetRemoteEvent(Network.Remotes.MartialInput):FireServer({ kind = "release", held = held, dir = dir })
		h.fx.stop(full)
		char:SetAttribute("AllowSkillMovement", false)
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and not hum.PlatformStand then hum.AutoRotate = true end
		if not (char.Parent and root.Parent) then
			busyUntil = 0
			return
		end
		busyUntil = os.clock() + 0.45
		releaseAfter(char, 0.4)
		-- (he stands his ground: planted through the punch)
		plant(char, 0.4)
		root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
		focusPunchPose(char, c)
		haymakerFire(root.Position, dir, c, hayLength(c, h.empowered), HAY.half * (tonumber(player:GetAttribute("Stat_size")) or 1), true)
		return
	end
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

-- The ult's cinematic (ours): the summoning. Low from his front-right, the
-- whole stance in frame, tilting up after the dragon as it spirals up round
-- him and pushing in as it builds, the shake growing; on the roar it hands
-- straight back to the game camera.
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
		if not char.Parent or hum.Health <= 0 or t >= DRAGON.rise then
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
		local u = easeOut(t / DRAGON.rise)
		local off = CFrame.Angles(0, math.rad(10 * u), 0):VectorToWorldSpace(right * 7.5 + d * 6.5) * (1 - 0.1 * u)
		local p = base + off
		local look = base + Vector3.new(0, 1 + 4 * u, 0)
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
	-- (the Haymaker's meshes made up front, parked, so no cast has to make any)
	for name, n in pairs({ hay_fist = 2, hay_fist_hull = 2, hay_torpedo = 2, hay_torpedo_hull = 2, hay_rings = 2, hay_dome = 3,
		hay_whirl = 1, hay_arch = 10, hay_ink = 6 }) do
		VfxKit.Prewarm(name, n, ClassFX.Folder())
	end
	-- (Studio only: set "MA_DebugHay" to a charge 0..1 to fire the Haymaker's
	-- wave from where you stand, for checking its look without the cast)
	if RunService:IsStudio() then
		player:GetAttributeChangedSignal("MA_DebugHay"):Connect(function()
			local c = tonumber(player:GetAttribute("MA_DebugHay"))
			local root = rootOf(player.Character)
			if c and root then
				local size = tonumber(player:GetAttribute("Stat_size")) or 1
				haymakerFire(root.Position, flat(root.CFrame.LookVector), c, hayLength(c, false), HAY.half * size, false, tonumber(player:GetAttribute("MA_DebugHaySlow")))
			end
		end)
	end
	buildHud()
	refreshHud()
	RunService.RenderStepped:Connect(function(dt)
		stepBurning()
		stepAnims(dt)
		stepCoils(dt)
	end)
	-- (the tails sway after the animation and poses have written the frame)
	CastPoses.addPostHook(stepRigs)
	for _, a in ipairs({ "MA_Charge", "SelectedClass", "InLobby", "SettingsOpen" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshHud)
	end
	player.CharacterAdded:Connect(function()
		focusing = nil
		if haymaking then
			haymaking.fx.stop(false)
			haymaking = nil
		end
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
