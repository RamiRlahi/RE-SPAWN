--!strict
--[[
	DeathKnightController.luau
	Client side of the Death Knight, the Soul Reaper (server:
	DeathKnightServer). Heavy, brutal, ominous: black mist and dark smoke, cold
	steel, and only a little icy spectral blue (no glow on the smoke: it is
	drawn dark, not additive).

	  • The Graveblade chain: your own swings are predicted (two-handed poses,
	    a smoky trail, a dark crescent) on click; the server resolves the hits
	    and sends everyone else's over DeathKnightFX. The slam bursts into
	    black mist.
	  • E Blackwake: crouched, the hammer dragged behind him on the floor, then
	    one huge upward swing; the floor tears open in a cone of black stone
	    spikes (spectral light at their roots) and smoke, rippling out
	    (Dreadforged: a second wave of smoke behind). Doomfall's crash tears
	    up the same stone in a round crater.
	  • F Doomfall: crouch, leap high with the blade raised overhead while black
	    mist gathers on it, then down sword-first: a wide dark shockwave, rock
	    thrown up, and thick mist left lying on the spot.
	  • Q Grave Reversal: his free palm thrust out, a spectral chain shoots
	    from it and coils round the one it reaches; torn across past him and
	    smashed down behind him, dragged back round to in front of him, and
	    executed under the hammer; the chain dissolves into blue motes.
	  • R King of the Grave: chains spiral up round him as he raises the
	    hammer; a gigantic spectral warhammer forms over him, chained to his;
	    he launches up and it swings over, head first, into the floor: an
	    impact frame, a crater, pillars of blue light; giant spectral hands
	    claw up out of it, chains drag the survivors in and their Dread marks
	    burst; the hammer comes apart into blue motes.
	  • Dread: the meter above the skill bar. Dreadforged (every Death Knight,
	    every client): icy-blue ghostfire along the Graveblade, a spectral
	    sheath making it bigger and brighter, his mist thick and roiling,
	    faint spectral shockwaves pulsing round his plate.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local DeathKnightLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("DeathKnightLook"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local player = Players.LocalPlayer

local DeathKnightController = {}

-- ── Tuning (mirrors DeathKnightServer) ──────────────────────────────────────
local COMBO_RESET = 1.7 -- (past a swing's follow-through, the combo starts over)
local WAKE_WINDUP = 0.6   -- the head planted, then dragged forward along the floor
local WAKE_PLANT = 0.18  -- (of which: setting it down behind him)
local WAKE_STEP = 3.5    -- how far he walks it forward
local DOOM = { crouch = 0.24, rise = 0.38, hang = 0.3, fall = 0.14 }
DOOM.impact = DOOM.crouch + DOOM.rise + DOOM.hang + DOOM.fall
local DOOM_RANGE = 24     -- the furthest leap (to the cursor)
local DOOM_HEIGHT = 11
local KING = { pull = 0.3, summon = 1.0, rise = 2.0, fall = 2.6, impact = 2.85, drag = 3.35, burst = 4.25, fade = 4.4, done = 5.0 }
local KING_HIGH = 16 -- how high he launches
local KING_SLANT = 28 -- (degrees) how far over the spectral hammer comes down
local DREAD_MAX = 100
local DREAD_TIME = 8

-- The sheet's palette (80% black, 15% steel, 5% spectral blue).
local OBSIDIAN = DeathKnightLook.OBSIDIAN
local CHARCOAL = DeathKnightLook.CHARCOAL
local ASH = DeathKnightLook.ASH
local STEEL = DeathKnightLook.STEEL
local SPECTRAL = DeathKnightLook.SPECTRAL
local FROST = DeathKnightLook.FROST
local SMOKE_GREY = Color3.fromRGB(40, 46, 56)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

type Deps = {
	shake: (number, number) -> (),
	fovPunch: (number, number) -> (),
	getAim: (BasePart) -> Vector3,
}
local deps: Deps

local localStep = 0
local lastSwing = 0
local busyUntil = 0

local function isDK(p: Player?): boolean
	return (p or player):GetAttribute("SelectedClass") == "death_knight"
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

-- Players near enough to feel a blow (camera shake).
local function near(pos: Vector3, dist: number): boolean
	local r = rootOf(player.Character)
	return r ~= nil and (r.Position - pos).Magnitude < dist
end

local function dreadLeft(p: Player): number
	return (tonumber(p:GetAttribute("DK_DreadUntil")) or 0) - Workspace:GetServerTimeNow()
end

local function dreadOf(p: Player): number
	return tonumber(p:GetAttribute("DK_Dread")) or 0
end

local function groundAt(p: Vector3): Vector3
	return Vector3.new(p.X, FireFX.GroundY(p), p.Z)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- VFX pieces
-- ═════════════════════════════════════════════════════════════════════════════
-- Smoke is drawn dark (no light emission), so it reads as black mist and not
-- as a glow; only the thin spectral accents shine.

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = ClassFX.Folder()
	return p
end

local function kp(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

-- A one-shot puff of black smoke: `count` particles thrown out at `speed`,
-- growing from `size` as they fade.
local function darkSmoke(pos: Vector3, count: number, size: number, speed: number, life: number?, rise: number?)
	if count <= 0 then return end
	local anchor = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SMOKE
	e.Color = ColorSequence.new(OBSIDIAN, SMOKE_GREY)
	e.LightEmission = 0
	e.LightInfluence = 0.3
	e.Size = NumberSequence.new({ kp(0, size), kp(1, size * 2.3) })
	e.Transparency = NumberSequence.new({ kp(0, 0.15), kp(0.6, 0.55), kp(1, 1) })
	local L = life or 1
	e.Lifetime = NumberRange.new(L * 0.6, L)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3.5
	e.Acceleration = Vector3.new(0, rise or 1, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-40, 40)
	e.Rate = 0
	e.Parent = anchor
	e:Emit(count)
	Debris:AddItem(anchor, L + 0.3)
end

-- A ring of black smoke racing out flat along the ground from `center`.
local function smokeRing(center: Vector3, count: number, size: number, speed: number, life: number)
	local anchor = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(center) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SMOKE
	e.Color = ColorSequence.new(OBSIDIAN, SMOKE_GREY)
	e.LightEmission = 0
	e.LightInfluence = 0.3
	e.Size = NumberSequence.new({ kp(0, size), kp(1, size * 2) })
	e.Transparency = NumberSequence.new({ kp(0, 0.2), kp(0.7, 0.6), kp(1, 1) })
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Speed = NumberRange.new(speed * 0.8, speed)
	e.SpreadAngle = Vector2.new(6, 6)
	e.Drag = 2.5
	e.EmissionDirection = Enum.NormalId.Front
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.Rate = 0
	e.Parent = anchor
	-- (the emitter turned round the ring, a few particles each way)
	local per = math.max(1, math.floor(count / 18))
	for i = 1, 18 do
		local a = i / 18 * math.pi * 2
		anchor.CFrame = CFrame.lookAt(center, center + Vector3.new(math.cos(a), 0, math.sin(a)))
		e:Emit(per)
	end
	Debris:AddItem(anchor, life + 0.3)
end

-- A few icy-blue spectral motes (the 5%).
local function motes(pos: Vector3, count: number, speed: number)
	ClassFX.Burst(pos, SPECTRAL, count, speed, TEX_SPARK, 0.22, 0.6)
end

-- Chunks of dark stone flung up from `pos` (real physics, then they fade).
local function rocks(pos: Vector3, count: number, speed: number, lift: number)
	for _ = 1, count do
		local s = 0.4 + math.random() * 0.9
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false, false
		p.Massless = true
		p.Size = Vector3.new(s, s * (0.6 + math.random() * 0.5), s * (0.7 + math.random() * 0.4))
		p.Material = Enum.Material.Slate
		p.Color = if math.random() < 0.5 then CHARCOAL else ASH
		p.CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		p.Parent = ClassFX.Folder()
		local a = math.random() * math.pi * 2
		p.AssemblyLinearVelocity = Vector3.new(math.cos(a), 0, math.sin(a)) * speed * (0.5 + math.random() * 0.7)
			+ Vector3.new(0, lift * (0.5 + math.random() * 0.8), 0)
		p.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 25
		TweenService:Create(p, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.8), { Transparency = 1 }):Play()
		Debris:AddItem(p, 1.4)
	end
end

-- Jagged black shards punching up out of the ground round `pos`, a few with
-- a cold steel edge, then sinking back.
-- Iron grinding on stone: white-hot sparks spraying off `pos`, mostly along
-- `away`, falling under gravity, with a hot flash where they leave the floor.
local SPARK_HOT = Color3.fromRGB(255, 236, 190)
local SPARK_WARM = Color3.fromRGB(255, 150, 60)
local function grindSparks(pos: Vector3, away: Vector3, count: number, speed: number)
	ClassFX.Burst(pos, SPARK_HOT, math.ceil(count * 0.6), speed * 0.5, TEX_SPARK, 0.35, 0.3)
	local flat = Vector3.new(away.X, 0, away.Z)
	local d = if flat.Magnitude > 0.01 then flat.Unit else Vector3.zAxis
	for _ = 1, count do
		local s = part({ Size = Vector3.new(0.07, 0.07, 0.5 + math.random() * 0.5), Material = Enum.Material.Neon,
			Color = if math.random() < 0.5 then SPARK_HOT else SPARK_WARM, Anchored = false, Massless = true })
		local side = d:Cross(Vector3.yAxis) * (math.random() * 2 - 1) * 0.8
		local v = (d + side + Vector3.new(0, 0.5 + math.random() * 0.9, 0)).Unit * speed * (0.5 + math.random() * 0.7)
		s.CFrame = CFrame.lookAt(pos, pos + v)
		s.AssemblyLinearVelocity = v
		local life = 0.25 + math.random() * 0.3
		TweenService:Create(s, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Transparency = 1, Size = Vector3.new(0.03, 0.03, 0.2) }):Play()
		Debris:AddItem(s, life)
	end
end

local function shards(pos: Vector3, radius: number, count: number, hMin: number, hMax: number, life: number)
	for i = 1, count do
		local a = (i / count) * math.pi * 2 + math.random() * 0.6
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local base = pos + dir * radius * (0.35 + math.random() * 0.65)
		local h = hMin + math.random() * (hMax - hMin)
		local w = 0.6 + math.random() * h * 0.15
		local rot = CFrame.lookAt(base, base + dir) * CFrame.Angles(-math.rad(10 + math.random() * 22), 0, 0) * CFrame.Angles(0, math.random() * 6, 0)
		local s = Instance.new("CornerWedgePart")
		s.Anchored, s.CanCollide, s.CanQuery, s.CanTouch, s.CastShadow = true, false, false, false, false
		s.Material = Enum.Material.Slate
		s.Color = if math.random() < 0.25 then ASH else OBSIDIAN
		local sunk = rot * CFrame.new(0, -h / 2, 0)
		local up = rot * CFrame.new(0, h / 2 - 0.4, 0)
		s.Size = Vector3.new(w, h, w)
		s.CFrame = sunk
		s.Parent = ClassFX.Folder()
		TweenService:Create(s, TweenInfo.new(0.08 + math.random() * 0.06, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = up }):Play()
		task.delay(life * 0.65, function()
			if s.Parent then
				TweenService:Create(s, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = sunk, Transparency = 0.6 }):Play()
			end
		end)
		Debris:AddItem(s, life * 0.65 + 0.45)
	end
end

-- A dark disc spreading over the ground (the shockwave's shadow), with a thin
-- spectral rim racing out at its edge.
local function darkShockwave(g: Vector3, radius: number, life: number, rim: boolean?)
	local disc = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, radius * 0.4, radius * 0.4),
		CFrame = CFrame.new(g + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = OBSIDIAN, Transparency = 0.25 })
	TweenService:Create(disc, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.08, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(disc, life + 0.05)
	if rim ~= false then
		local cf = CFrame.new(g + Vector3.new(0, 0.3, 0))
		SwordFX.Arc({ cf = cf, radius = radius * 0.5, arc = 359, width = 0.55, color = SPECTRAL, life = life * 0.8, draw = 0.001, grow = 1, core = FROST })
	end
end

-- ── Dark ribbons ────────────────────────────────────────────────────────────
-- Beams drawn dark: smoke-textured, no light emission, facing the camera.
-- ── Grave stone: the craters ────────────────────────────────────────────────
-- (the Summoner's Rockborn craters, in his black stone) Jagged spikes of slate
-- bursting up out of the floor: four corner wedges each, their tips meeting
-- in one point, spectral light glowing in the cracks at the root of most of
-- them, black smoke torn up with them. They punch up with an overshoot, hold,
-- then crumble back into the floor.
local STONE = { OBSIDIAN, CHARCOAL, ASH, Color3.fromRGB(30, 36, 46), Color3.fromRGB(16, 20, 27) }
type Spike = { parts: { BasePart }, rel: { CFrame }, cf: CFrame, h: number, delay: number }

local function makeSpike(cf: CFrame, width: number, height: number, glow: boolean, delay: number): Spike
	local sp: Spike = { parts = {}, rel = {}, cf = cf, h = height, delay = delay }
	local tone = STONE[math.random(1, #STONE)]
	for k = 0, 3 do
		local ax = width * 0.5 * (0.7 + math.random() * 0.6)
		local az = width * 0.5 * (0.7 + math.random() * 0.6)
		local w = Instance.new("CornerWedgePart")
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch = true, false, false, false
		w.CastShadow = height > 3
		w.Size = Vector3.new(ax, height, az)
		w.Color = tone:Lerp(Color3.new(0, 0, 0), (k % 2) * 0.25)
		w.Material = Enum.Material.Slate
		w.CFrame = cf * CFrame.new(0, -height * 2, 0)
		w.Parent = ClassFX.Folder()
		table.insert(sp.parts, w)
		table.insert(sp.rel, CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(-ax / 2, height / 2, az / 2))
	end
	if glow then
		local g = part({ Size = Vector3.new(width * 0.6, 0.3, width * 0.6), Color = SPECTRAL, Material = Enum.Material.Neon,
			CFrame = cf * CFrame.new(0, -height * 2, 0) })
		table.insert(sp.parts, g)
		table.insert(sp.rel, CFrame.new(0, 0.12, 0) * CFrame.Angles(0, math.rad(45), 0))
	end
	return sp
end

local RISE, SINK = 0.13, 0.5
local function overshoot(a: number): number
	local c = 1.7
	return 1 + (c + 1) * (a - 1) ^ 3 + c * (a - 1) ^ 2
end
-- Erupts every spike (each after its own delay), holds them `hold` seconds,
-- then sinks them.
local function erupt(spikes: { Spike }, hold: number)
	local last = 0
	for _, sp in ipairs(spikes) do last = math.max(last, sp.delay) end
	local total = last + RISE + hold + SINK
	local all: { BasePart } = {}
	for _, sp in ipairs(spikes) do
		for _, p in ipairs(sp.parts) do table.insert(all, p) end
	end
	local cfs = table.create(#all)
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local age = os.clock() - t0
		local i = 0
		for _, sp in ipairs(spikes) do
			local t = age - sp.delay
			local rise = if t <= 0 then 0 else overshoot(math.min(t / RISE, 1))
			local sink = math.clamp((t - RISE - hold) / SINK, 0, 1)
			local at = sp.cf * CFrame.new(0, -sp.h * 1.05 * (1 - rise) - sp.h * 0.75 * sink * sink, 0)
			for k, rel in ipairs(sp.rel) do
				i += 1
				cfs[i] = at * rel
				if sink > 0 then sp.parts[k].Transparency = sink * sink end
			end
		end
		Workspace:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if age >= total then
			conn:Disconnect()
			for _, p in ipairs(all) do p:Destroy() end
		end
	end)
end

-- A spike leaning `lean` degrees along `out`, any which way round.
local function leaning(at: Vector3, out: Vector3, lean: number): CFrame
	out = Vector3.new(out.X, 0, out.Z)
	out = if out.Magnitude > 0.05 then out.Unit else Vector3.new(0, 0, -1)
	return CFrame.lookAt(at, at + out) * CFrame.Angles(math.rad(-lean), 0, 0) * CFrame.Angles(0, math.random() * 6.28, 0)
end

-- The crater's breath: black smoke and spectral motes torn up at `g`.
local function craterSmoke(g: Vector3, scale: number)
	if not FxBudget.Allow("dkCraterSmoke", 40) then return end
	darkSmoke(g + Vector3.new(0, 0.8, 0), math.floor(4 + scale * 3), 1.6 + scale, 5 + scale * 3, 0.9, 1.2)
	if math.random() < 0.5 then motes(g + Vector3.new(0, 1, 0), 4, 8) end
end

-- Blackwake's crater: a cone of spikes torn up from his feet out along `dir`,
-- rippling out row by row at `speed`, wider and taller the further out.
local function coneCrater(from: Vector3, dir: Vector3, half: number, range: number, speed: number)
	local spikes: { Spike } = {}
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local along = 3
	local row = 0
	while along <= range do
		row += 1
		local f = along / range
		local w = math.max(along * math.tan(half), 1.5)
		local n = math.max(1, math.floor(w * 2 / 3.2) + 1)
		local delay = along / speed
		for k = 0, n - 1 do
			local s = if n == 1 then 0 else -w + 2 * w * k / (n - 1)
			local at = groundAt(from + dir * (along + (math.random() - 0.5) * 1.2) + side * (s + (math.random() - 0.5) * 1.2)
				+ Vector3.new(0, 3, 0))
			local h = (2.6 + f * 5) * (0.7 + math.random() * 0.6)
			local out = dir * along + side * s
			table.insert(spikes, makeSpike(leaning(at, out, 12 + math.random() * 30), h * (0.42 + math.random() * 0.18), h,
				math.random() < 0.55, delay + math.random() * 0.03))
		end
		-- (the smoke and the spectral light torn up with each other row)
		if row % 2 == 1 then
			task.delay(delay, function()
				craterSmoke(groundAt(from + dir * along + Vector3.new(0, 3, 0)), 0.6 + f)
				if n > 2 then
					craterSmoke(groundAt(from + dir * along + side * w * 0.6 + Vector3.new(0, 3, 0)), 0.5 + f * 0.6)
					craterSmoke(groundAt(from + dir * along - side * w * 0.6 + Vector3.new(0, 3, 0)), 0.5 + f * 0.6)
				end
			end)
		end
		along += 2.8
	end
	erupt(spikes, 1.3)
end

-- Doomfall's crater: rings of spikes round where he lands, erupting outward,
-- leaning out of the bowl, bigger toward the rim.
local function roundCrater(center: Vector3, inner: number, outer: number, rings: number, height: number)
	local spikes: { Spike } = {}
	for ring = 1, rings do
		local f = if rings == 1 then 1 else (ring - 1) / (rings - 1)
		local r = inner + (outer - inner) * f
		local n = math.max(6, math.floor(r * 1.1))
		for k = 1, n do
			local a = (k + math.random() * 0.6) / n * math.pi * 2 + ring * 0.7
			local at = groundAt(center + Vector3.new(math.cos(a) * r, 3, math.sin(a) * r))
			local h = height * (0.55 + 0.45 * f) * (0.7 + math.random() * 0.6)
			table.insert(spikes, makeSpike(leaning(at, at - center, 10 + math.random() * 26), h * (0.42 + math.random() * 0.18), h,
				math.random() < 0.6, r / 90 + math.random() * 0.04))
		end
		task.delay(r / 90, function()
			for k = 0, 3 do
				local a = k * math.pi / 2 + ring
				craterSmoke(groundAt(center + Vector3.new(math.cos(a) * r, 3, math.sin(a) * r)), 0.7 + f)
			end
		end)
	end
	erupt(spikes, 1.4)
end

local function att(): Attachment
	local a = Instance.new("Attachment")
	a.Name = "DeathKnightFX"
	a.Parent = Workspace.Terrain
	return a
end

local function darkBeam(a0: Attachment, a1: Attachment, color: Color3, glow: number?): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightEmission = glow or 0
	b.LightInfluence = if glow and glow > 0 then 0 else 0.25
	b.Texture = TEX_SMOKE
	b.TextureMode = Enum.TextureMode.Stretch
	b.TextureSpeed = 0.6
	b.Segments = 8
	b.Color = ColorSequence.new(color)
	b.Parent = a0
	return b
end

-- A heavy crescent of black smoke carved through the air: centre and facing
-- `cf` (the arc bulges toward cf's -Z), drawn along the swing (`sweep` 1 =
-- right to left), its edges thin and fading, a cold steel edge on the
-- outside; then it drifts out a little and fades.
type ArcOpts = { cf: CFrame, radius: number, span: number, sweep: number?, width: number, life: number?, draw: number?, edge: boolean? }
local function smokeArc(o: ArcOpts)
	local life = o.life or 0.4
	local draw = o.draw or 0.1
	local sign = if (o.sweep or 1) >= 0 then 1 else -1
	local span = math.rad(o.span)
	local n = math.clamp(math.floor(o.span / 16), 6, 18)
	local core, outer, edges = {}, {}, {}
	local owned: { Instance } = {}
	local pts, epts = {}, {}
	for i = 1, n do
		pts[i] = att()
		epts[i] = att()
		table.insert(owned, pts[i])
		table.insert(owned, epts[i])
	end
	for i = 1, n - 1 do
		core[i] = darkBeam(pts[i], pts[i + 1], OBSIDIAN)
		outer[i] = darkBeam(pts[i], pts[i + 1], SMOKE_GREY)
		if o.edge ~= false then
			local e = darkBeam(epts[i], epts[i + 1], STEEL, 0.15)
			e.Texture = ""
			edges[i] = e
		end
	end
	local function at(f: number, r: number): Vector3
		local a = -sign * span / 2 + sign * span * f
		return o.cf:PointToWorldSpace(Vector3.new(-math.sin(a) * r, 0, -math.cos(a) * r))
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	local puffed = 0
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > draw + life then
			conn:Disconnect()
			for _, x in ipairs(owned) do x:Destroy() end
			return
		end
		local r = o.radius * (1 + 0.12 * t / (draw + life))
		for i = 1, n do
			local f = (i - 1) / (n - 1)
			pts[i].WorldPosition = at(f, r)
			epts[i].WorldPosition = at(f, r * 1.04)
		end
		for i = 1, n - 1 do
			local f0, f1 = (i - 1) / (n - 1), i / (n - 1)
			-- (each piece appears as the swing passes, then fades with age)
			local age = t - f0 * draw
			local opacity = if age < 0 then 0 else math.clamp(1 - age / life, 0, 1)
			local w0 = o.width * math.sin(math.pi * f0) ^ 0.7
			local w1 = o.width * math.sin(math.pi * f1) ^ 0.7
			local thin = 0.55 + 0.45 * opacity
			core[i].Width0, core[i].Width1 = w0 * thin, w1 * thin
			outer[i].Width0, outer[i].Width1 = w0 * 1.6 * thin, w1 * 1.6 * thin
			core[i].Transparency = NumberSequence.new(1 - 0.85 * opacity)
			outer[i].Transparency = NumberSequence.new(1 - 0.45 * opacity)
			local e = edges[i]
			if e then
				e.Width0, e.Width1 = 0.05 + w0 * 0.08, 0.05 + w1 * 0.08
				e.Transparency = NumberSequence.new(1 - 0.7 * opacity)
			end
		end
		-- a few puffs of smoke shed off the arc as it's drawn
		local drawn = math.clamp(t / draw, 0, 1)
		while puffed < 3 and drawn >= (puffed + 0.5) / 3 do
			puffed += 1
			darkSmoke(at((puffed - 0.5) / 3, r), 3, o.width * 0.6, 3, 0.7, 0.5)
		end
	end)
end

-- ── The swing trail ─────────────────────────────────────────────────────────
-- A smoky dark trail off the Graveblade's edge (icy at its root while
-- Dreadforged).
local function ensureTrail(char: Model): Trail?
	local tool = char:FindFirstChild("Graveblade")
	local a0 = tool and tool:FindFirstChild("GraveBase", true)
	local edge = a0 and a0.Parent
	if not edge then return nil end
	local t = edge:FindFirstChild("GraveTrail") :: Trail?
	if t then return t end
	local a1 = edge:FindFirstChild("GraveTip")
	if not (a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment")) then return nil end
	local tr = Instance.new("Trail")
	tr.Name = "GraveTrail"
	tr.Attachment0 = a0
	tr.Attachment1 = a1
	tr.Texture = TEX_SMOKE
	tr.TextureMode = Enum.TextureMode.Stretch
	tr.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, ASH), ColorSequenceKeypoint.new(0.4, CHARCOAL), ColorSequenceKeypoint.new(1, OBSIDIAN) })
	tr.Transparency = NumberSequence.new({ kp(0, 0.15), kp(1, 1) })
	tr.Lifetime = 0.32
	tr.MinLength = 0.05
	tr.LightEmission = 0
	tr.LightInfluence = 0.3
	tr.FaceCamera = false
	tr.Enabled = false
	tr.Parent = edge
	return tr
end

local function trail(char: Model, seconds: number)
	local t = ensureTrail(char)
	if t then
		t.Enabled = true
		task.delay(seconds, function() if t.Parent then t.Enabled = false end end)
	end
end

-- The Graveblade's tip in the world (where the chain leaves it).
local function bladeTip(char: Model): Vector3?
	local tool = char:FindFirstChild("Graveblade")
	local tip = tool and tool:FindFirstChild("GraveTip", true)
	if tip and tip:IsA("Attachment") then return tip.WorldPosition end
	local root = rootOf(char)
	return if root then root.Position + root.CFrame.LookVector * 3 else nil
end

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

-- ── Chains ──────────────────────────────────────────────────────────────────
-- A spectral chain: dark iron links strung between two moving points, a faint
-- icy-blue glow along it. `ends()` gives the two ends each frame (nil: gone).
-- Each link is a forged iron oval: four round rods (two sides, two rounded
-- ends), the next link threaded through it turned a quarter round.
local LINK = 0.9
local LINK_W = 0.44
local ROD = 0.13
local IRON = Color3.fromRGB(74, 76, 82)
local IRON_WORN = Color3.fromRGB(96, 92, 88)
local CYL_Z = CFrame.Angles(0, math.pi / 2, 0) -- (a cylinder's axis turned from X onto Z)
local function rod(len: number, color: Color3): BasePart
	return part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, ROD, ROD), Material = Enum.Material.Metal,
		Color = color, Reflectance = 0.12 })
end
-- (the link is its first side rod; the other three hang under it)
local function chainLink(): BasePart
	local color = if math.random() < 0.3 then IRON_WORN else IRON
	local l = rod(LINK * 0.72, color)
	for _, name in ipairs({ "Side", "End", "End" }) do
		local r = rod(if name == "Side" then LINK * 0.72 else LINK_W, color)
		r.Name = name
		r.Parent = l
	end
	return l
end

-- (the link's rods placed round its centre frame)
local function placeLink(l: BasePart, cf: CFrame)
	local sx = (LINK_W - ROD) / 2
	l.CFrame = cf * CFrame.new(-sx, 0, 0) * CYL_Z
	local e = 0
	for _, c in ipairs(l:GetChildren()) do
		if c.Name == "Side" then
			(c :: BasePart).CFrame = cf * CFrame.new(sx, 0, 0) * CYL_Z
		elseif c.Name == "End" then
			e += 1
			(c :: BasePart).CFrame = cf * CFrame.new(0, 0, (if e == 1 then -1 else 1) * (LINK * 0.5 - ROD / 2))
		end
	end
end

-- A forged iron hook: a shank, a ring for the chain, and a barbed bend.
-- Offsets are from the hook's frame (looking along the chain, the bend ahead).
local HOOK_PIECES = {
	{ size = Vector3.new(0.9, 0.2, 0.2), cf = CFrame.new(0, 0, 0) * CYL_Z, cyl = true },                    -- shank
	{ size = Vector3.new(0.3, 0.12, 0.12), cf = CFrame.new(0, 0.12, 0.45) * CFrame.Angles(0, 0, math.pi / 2), cyl = true }, -- eye
	{ size = Vector3.new(0.5, 0.2, 0.2), cf = CFrame.new(0, -0.18, -0.55) * CFrame.Angles(0, 0, math.pi / 2), cyl = true }, -- bend down
	{ size = Vector3.new(0.6, 0.2, 0.2), cf = CFrame.new(0, -0.42, -0.35) * CYL_Z * CFrame.Angles(0, 0, math.rad(-20)), cyl = true }, -- back up
	{ size = Vector3.new(0.12, 0.34, 0.12), cf = CFrame.new(0, -0.18, -0.05) * CFrame.Angles(math.rad(-35), 0, 0), cyl = false },  -- barb
}
local function buildHook(): { BasePart }
	local out = {}
	for _, h in ipairs(HOOK_PIECES) do
		local p = part({ Size = h.size, Material = Enum.Material.Metal, Color = STEEL, Reflectance = 0.18,
			Shape = if h.cyl then Enum.PartType.Cylinder else Enum.PartType.Block })
		table.insert(out, p)
	end
	return out
end

type Chain = { stop: () -> () }
-- (`plain`: bare iron, no spectral glow along it)
local function liveChain(ends: () -> (Vector3?, Vector3?), sag: number?, maxLinks: number?, plain: boolean?): Chain
	local links: { BasePart } = {}
	local a0, a1 = att(), att()
	if not plain then
		local glow = Instance.new("Beam")
		glow.Attachment0, glow.Attachment1 = a0, a1
		glow.FaceCamera = true
		glow.LightEmission = 1
		glow.LightInfluence = 0
		glow.Color = ColorSequence.new(SPECTRAL, FROST)
		glow.Transparency = NumberSequence.new(0.6)
		glow.Width0, glow.Width1 = 0.16, 0.1
		glow.Segments = 1
		glow.Parent = a0
	end
	local hookParts = buildHook()
	local cap = maxLinks or 48
	local conn: RBXScriptConnection
	local stopped = false
	local function stop()
		if stopped then return end
		stopped = true
		conn:Disconnect()
		for _, l in ipairs(links) do l:Destroy() end
		for _, h in ipairs(hookParts) do h:Destroy() end
		a0:Destroy()
		a1:Destroy()
	end
	conn = RunService.RenderStepped:Connect(function()
		local a, b = ends()
		if not a or not b then
			stop()
			return
		end
		local d = b - a
		local len = d.Magnitude
		local n = math.clamp(math.floor(len / (LINK * 0.78)), 1, cap)
		while #links < n do table.insert(links, chainLink()) end
		while #links > n do (table.remove(links) :: BasePart):Destroy() end
		local down = Vector3.new(0, -(sag or 0) * math.min(len, 30) * 0.06, 0)
		local prev = a
		for i = 1, n do
			local f = i / n
			local p = a + d * f + down * math.sin(f * math.pi)
			local mid = (prev + p) / 2
			if (p - prev).Magnitude > 0.01 then
				placeLink(links[i], CFrame.lookAt(mid, p) * CFrame.Angles(0, 0, if i % 2 == 0 then 0 else math.pi / 2))
			else
				placeLink(links[i], CFrame.new(p))
			end
			prev = p
		end
		a0.WorldPosition, a1.WorldPosition = a, b
		if len > 0.05 then
			local hcf = CFrame.lookAt(b, b + d.Unit)
			for k, h in ipairs(hookParts) do h.CFrame = hcf * HOOK_PIECES[k].cf end
		end
	end)
	return { stop = stop }
end

-- Chains bursting up out of the ground round `model` and holding it.
local function bindingChains(model: Model, hold: number)
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (root and root:IsA("BasePart")) then return end
	local r = root :: BasePart
	local g = groundAt(r.Position)
	local size = math.clamp(model:GetExtentsSize().Magnitude * 0.3, 2.5, 6)
	for k = 1, 2 do
		local a = math.random() * math.pi * 2 + k * math.pi
		local from = g + Vector3.new(math.cos(a), 0, math.sin(a)) * size
		local t0 = os.clock()
		local c = liveChain(function()
			if os.clock() - t0 > hold or not r.Parent then return nil, nil end
			local e = math.min((os.clock() - t0) / 0.18, 1)
			return from, from:Lerp(r.Position, e)
		end, 0, 14)
		task.delay(hold + 0.05, c.stop)
		darkSmoke(from, 3, 1.4, 4, 0.7)
	end
	-- a spectral ring under it
	SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.2, 0)), radius = size, arc = 359, width = 0.3, color = SPECTRAL, life = hold, draw = 0.15, core = FROST })
end

-- ═════════════════════════════════════════════════════════════════════════════
-- The wrist (every Death Knight, every client)
-- ═════════════════════════════════════════════════════════════════════════════
-- R6 has no wrists: the maul stands square to the arm, so a slam that ends
-- with the arms low would end with the head pointing up. The grip turns the
-- maul in the hand instead: at 0 it's square to the arm, at -90 it runs on
-- along the arm (the head driven down past the fists).
type Wrist = { a: number, from: number, to: number, t0: number, dur: number }
local wrists: { [Model]: Wrist } = setmetatable({}, { __mode = "k" }) :: any

-- Turn `char`'s maul in the hand to `to` degrees over `dur`, `delay` from now.
local function wristTo(char: Model, to: number, dur: number, delay: number?)
	local function go()
		local w = wrists[char] or { a = 0, from = 0, to = 0, t0 = 0, dur = 0 }
		w.from, w.to, w.t0, w.dur = w.a, to, os.clock(), math.max(dur, 0.01)
		wrists[char] = w
	end
	if delay and delay > 0 then task.delay(delay, go) else go() end
end

local function wristOf(char: Model): number
	local w = wrists[char]
	if not w then return 0 end
	local k = math.clamp((os.clock() - w.t0) / w.dur, 0, 1)
	w.a = w.from + (w.to - w.from) * (1 - (1 - k) ^ 2)
	return w.a
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Poses: two hands on the hilt (CastPoses character space)
-- ═════════════════════════════════════════════════════════════════════════════
-- (R6: the blade stands out of the fist square to the arm. Arm hanging, it
-- points ahead; arm raised forward, up; arm overhead, back. Rolled half
-- round (RS ry 180) it points the other way: arm forward, point down.)
local QUAD, QUART = Enum.EasingStyle.Quad, Enum.EasingStyle.Quart
local body = CastPoses.body

-- Every swing: a long coil and a held beat; the torso unwinds first while the
-- arms stay back (the maul lagging behind the body); a violent strike; an
-- overshooting follow-through; the body settling against the weight; a slow
-- recovery. (SWING.land / SWING.free: mirrored in DeathKnightServer's COMBO.)
local SWING = {
	land = { 0.46, 0.44, 0.96 }, -- when each strike lands
	free = { 0.82, 0.8, 1.45 },  -- when the next swing may start
	held = { 0.7, 0.68, 1.3 },   -- how long his feet stay planted
}

local function swingPose(char: Model, step: number, speed: number?)
	local sp = speed or 1
	-- (carry: the joints drag behind and overshoot more: a heavy weapon)
	local opts = { speed = sp, carry = 1.6 }
	if step == 1 then
		-- A horizontal cleave, right to left at waist height.
		CastPoses.play(char, {
			-- coiled round to the right, weight sunk on the back foot...
			{ dur = 0.22, style = QUAD, pose = body(8, -68, 20, 16, { RS = { 78, -76, 32 }, LS = { 76, -60, 0 }, N = { 0, 38, 0 } }, 16, 0.3, 0.3) },
			-- ...held there, sinking a little deeper under the weight...
			{ dur = 0.07, style = Enum.EasingStyle.Sine, pose = body(10, -74, 22, 18, { RS = { 80, -82, 34 }, LS = { 78, -66, 0 }, N = { 0, 40, 0 } }, 16, 0.35, 0.35) },
			-- ...the hips and chest unwind first, the maul still trailing...
			{ dur = 0.09, style = QUAD, pose = body(-6, -12, 24, 24, { RS = { 80, -104, 30 }, LS = { 76, -92, 0 }, N = { 2, 14, 0 } }, 16, 0.05, -0.1) },
			-- ...then whipped through: the head tears across in front
			{ dur = 0.08, style = QUART, pose = body(-16, 58, 30, 30, { RS = { 78, 72, -30 }, LS = { 74, 60, 0 }, N = { 4, -26, 0 } }, 16, -0.25, -0.5) },
			-- carried on round past the line by its own weight...
			{ dur = 0.22, style = Enum.EasingStyle.Sine, pose = body(-14, 76, 30, 30, { RS = { 64, 94, -40 }, LS = { 58, 82, 0 }, N = { 4, -30, 0 } }, 16, -0.3, -0.45) },
			-- ...and dragging him with it before he reins it in
			{ dur = 0.16, style = QUAD, pose = body(-10, 66, 26, 26, { RS = { 68, 84, -36 }, LS = { 62, 72, 0 }, N = { 2, -26, 0 } }, 14, -0.2, -0.35) },
		}, 0.42, true, opts)
		task.delay(SWING.land[1] / sp, CastPoses.hitStop, char, 0.07)
	elseif step == 2 then
		-- A rising backhand: dragged low from the left, torn up across to the right.
		CastPoses.play(char, {
			-- gathered low on the left, the head near the floor...
			{ dur = 0.2, style = QUAD, pose = body(14, 62, 26, 26, { RS = { 28, 84, -42 }, LS = { 34, 54, 0 }, N = { -4, -32, 0 } }, 16, -0.3, 0.1) },
			-- ...a beat, sinking into the legs to heave it...
			{ dur = 0.07, style = Enum.EasingStyle.Sine, pose = body(18, 66, 28, 28, { RS = { 24, 88, -44 }, LS = { 30, 58, 0 }, N = { -4, -34, 0 } }, 16, -0.35, 0.15) },
			-- ...the body turns first, the maul dragged after it...
			{ dur = 0.09, style = QUAD, pose = body(-2, 8, 24, 24, { RS = { 40, 104, -30 }, LS = { 44, 76, 0 }, N = { 2, -6, 0 } }, 16, 0, 0) },
			-- ...then torn up and across
			{ dur = 0.08, style = QUART, pose = body(-16, -55, 22, 22, { RS = { 110, -90, 30 }, LS = { 100, -100, 0 }, N = { 6, 22, 0 } }, 16, 0.25, -0.3) },
			-- over-swung past the line, his weight thrown onto the right foot...
			{ dur = 0.22, style = Enum.EasingStyle.Sine, pose = body(-12, -74, 20, 20, { RS = { 112, -110, 44 }, LS = { 96, -106, 0 }, N = { 4, 28, 0 } }, 16, 0.3, -0.2) },
			-- ...and hauled back under control
			{ dur = 0.16, style = QUAD, pose = body(-8, -64, 20, 20, { RS = { 104, -100, 40 }, LS = { 92, -96, 0 }, N = { 4, 26, 0 } }, 14, 0.2, -0.2) },
		}, 0.42, true, opts)
		task.delay(SWING.land[2] / sp, CastPoses.hitStop, char, 0.07)
	else
		-- The finisher: a front flip with the maul, heaved up overhead out of
		-- it, hung there a beat, then brought down.
		-- (the body somersaults about its middle, lifted clear of the floor;
		-- whole turns between keys are kept, so it ends upright instead of
		-- flipping back)
		local function flip(p: any, pitch: number, lift: number): any
			p.Root = { pitch, 0, 0, 0, lift, 0 }
			return p
		end
		CastPoses.play(char, {
			-- crouched low, the maul hauled up behind his shoulders...
			{ dur = 0.24, style = QUAD, pose = flip(body(-12, 0, 34, 34, { RS = { 150, 0, 0 }, LS = { 146, 0, 0 }, N = { -12, 0, 0 } }, 18, 0, 0.2), 0, -0.6) },
			-- ...launched up and over, tucked, the maul carried round with him...
			{ dur = 0.2, style = QUAD, pose = flip(body(-10, 0, 70, -70, { RS = { 190, 0, 0 }, LS = { 186, 0, 0 }, N = { -20, 0, 0 } }, 10, 0, 0), -170, 3.4) },
			{ dur = 0.18, style = Enum.EasingStyle.Linear, pose = flip(body(-10, 0, 70, -70, { RS = { 190, 0, 0 }, LS = { 186, 0, 0 }, N = { -20, 0, 0 } }, 10, 0, 0), -330, 3.8) },
			-- ...unfolding out of it high, the maul heaved overhead, back arched...
			{ dur = 0.12, style = QUAD, pose = flip(body(24, 0, 14, 14, { RS = { 178, 8, 0 }, LS = { 172, -8, 0 }, N = { 12, 0, 0 } }, 14, 0, 0.35), -360, 3) },
			-- ...hung there for a heartbeat...
			{ dur = 0.12, style = Enum.EasingStyle.Sine, pose = flip(body(28, 0, 12, 12, { RS = { 184, 8, 0 }, LS = { 178, -8, 0 }, N = { 14, 0, 0 } }, 14, 0, 0.4), -360, 2.4) },
			-- ...and brought down with everything he has
			{ dur = 0.1, style = QUART, pose = flip(body(-44, 0, 46, 46, { RS = { 32, 0, 0 }, LS = { 32, 0, 0 }, N = { 22, 0, 0 } }, 16, 0, -0.6), -360, -0.75) },
			-- crouched over it as the floor gives
			{ dur = 0.3, style = Enum.EasingStyle.Sine, pose = flip(body(-38, 0, 44, 44, { RS = { 28, 0, 0 }, LS = { 28, 0, 0 }, N = { 16, 0, 0 } }, 16, 0, -0.5), -360, -0.7) },
		}, 0.55, true, opts)
		-- (the maul turned over in the hands as it comes down: head first into
		-- the floor, then righted again as he straightens)
		local land = SWING.land[3] / sp
		wristTo(char, -80, 0.08 / sp, land - 0.08 / sp)
		wristTo(char, 0, 0.3 / sp, land + 0.38 / sp)
		task.delay(land, CastPoses.hitStop, char, 0.16)
	end
end

local function blackwakePose(char: Model)
	-- (rolled half round, so the head trails behind the fists)
	CastPoses.play(char, {
		-- The head set down on the floor behind him, body bent over it...
		{ dur = WAKE_PLANT, style = QUAD, pose = body(-30, -14, 42, 42, { RS = { 26, 180, 0 }, LS = { 22, 180, 0 }, N = { 12, 8, 0 } }, 16, 0.1, 0.4) },
		-- ...dragged forward along the floor, every step a strain against it...
		{ dur = WAKE_WINDUP - WAKE_PLANT - 0.06, style = Enum.EasingStyle.Sine, pose = body(-38, -6, 48, 48, { RS = { 36, 180, 0 }, LS = { 32, 180, 0 }, N = { 16, 4, 0 } }, 16, 0, 0.8) },
		-- ...then heaved up from the floor and on over, the whole body behind it
		{ dur = 0.1, style = QUART, pose = body(18, 4, 26, 26, { RS = { 205, 180, 0 }, LS = { 200, 180, 0 }, N = { -18, 0, 0 } }, 14, 0, -0.6) },
		{ dur = 0.34, pose = body(14, 4, 24, 24, { RS = { 200, 180, 0 }, LS = { 196, 180, 0 }, N = { -14, 0, 0 } }, 14, 0, -0.5) },
	}, 0.45, true)
	-- (while the arms roll over, the maul is turned up along them, out of the
	-- floor's way; then lowered back behind him onto it)
	wristTo(char, 90, 0.07)
	wristTo(char, 0, WAKE_PLANT - 0.06, 0.08)
	task.delay(WAKE_WINDUP + 0.03, CastPoses.hitStop, char, 0.08)
end

local function doomPose(char: Model)
	local T = DOOM
	CastPoses.play(char, {
		-- the crouch, blade drawn back
		{ dur = T.crouch, style = QUAD, pose = body(-24, 0, 38, 38, { RS = { 150, 0, 10 }, LS = { 145, 0, -10 }, N = { 15, 0, 0 } }, 14, 0, 0.2) },
		-- the leap: up, the blade raised overhead
		{ dur = T.rise, style = QUAD, pose = { Root = { 0, 0, 0 }, W = { 12, 0, 0 }, RS = { 178, 0, 0 }, LS = { 174, 0, 0 },
			RH = { 28, 0, 6 }, LH = { -16, 0, -6 }, N = { -18, 0, 0 } } },
		-- the hang, arched back, mist gathering on it
		{ dur = T.hang, pose = { Root = { 0, 0, 0 }, W = { 18, 0, 0 }, RS = { 182, 0, 0 }, LS = { 178, 0, 0 },
			RH = { 40, 0, 8 }, LH = { -8, 0, -8 }, N = { -22, 0, 0 } } },
		-- the fall, turned over point-down: sword first
		{ dur = T.fall, style = QUART, pose = { Root = { 0, 0, 0 }, W = { -30, 0, 0 }, RS = { 104, 180, 0 }, LS = { 100, 180, 0 },
			RH = { 30, 0, 8 }, LH = { 18, 0, -8 }, N = { 22, 0, 0 } } },
		-- the landing: crouched over the planted blade
		{ dur = 0.32, pose = body(-34, 0, 44, 44, { RS = { 100, 180, 0 }, LS = { 96, 180, 0 }, N = { 18, 0, 0 } }, 14, 0, -0.3) },
	}, 0.38, true)
	task.delay(DOOM.impact, CastPoses.hitStop, char, 0.08)
end

-- Grave Reversal: the left palm thrust out at the target as the chain flies
-- (the left arm is aimed at it every frame: haulAim, in twoHandStep), the
-- maul trailing from the right hand, its head dragging on the floor behind
-- him (rolled half round: RS ry 180, as Blackwake plants it).
local DRAG_ARM = { 20, 180, 8 }
local function thrustPose(char: Model)
	CastPoses.play(char, {
		-- drawn back, the free hand cocked at the shoulder...
		{ dur = 0.12, style = QUAD, pose = body(6, 18, 24, 24, { RS = DRAG_ARM, LS = { 40, 30, -20 }, N = { 0, -10, 0 } }, 18, 0, 0.2) },
		-- ...and the palm driven out, left shoulder leading
		{ dur = 0.1, style = QUART, pose = body(-10, -16, 32, 30, { RS = DRAG_ARM, LS = { 92, 0, 0 }, N = { 4, 10, 0 } }, 18, 0, -0.4) },
		{ dur = 0.6, pose = body(-8, -16, 32, 30, { RS = DRAG_ARM, LS = { 92, 0, 0 }, N = { 4, 8, 0 } }, 18, 0, -0.3) },
	}, 0.3, true, { carry = 1.4 })
end

local SLAM1_STOP = 0.12 -- (the first blow's hit-stop)

-- From the bite on (the server's timeline: DeathKnightServer's SNATCH). The
-- body only: he's turned to face the one on the chain every frame, and the
-- left arm is aimed at it while it's being dragged.
local function reversalPose(char: Model, T: any)
	local slam1Wind = T.slam1 - T.wrap - T.pull - 0.1
	local hold2 = T.slam2 - T.back - T.reverse - 0.1
	CastPoses.play(char, {
		-- SNARE: braced, the fist closed on the chain as it draws taut
		{ dur = T.wrap, style = Enum.EasingStyle.Sine, pose = body(-8, -18, 32, 30, { RS = DRAG_ARM, LS = { 92, 0, 0 }, N = { 4, 8, 0 } }, 18, 0, -0.2) },
		-- PULL: sat back into it, then the whole body wrenched round, the left
		-- arm torn across him
		{ dur = 0.14, style = QUAD, pose = body(12, -24, 30, 34, { RS = { 24, 180, 10 }, LS = { 80, 0, 0 }, N = { -4, 10, 0 } }, 20, 0.2, 0.4) },
		{ dur = T.pull - 0.14, style = Enum.EasingStyle.Sine, pose = body(10, -40, 34, 30, { RS = { 26, 180, 14 }, LS = { 70, 0, 0 }, N = { 0, -24, 0 } }, 20, -0.3, 0.3) },
		-- SLAM: both hands back on the maul, heaved up over him...
		{ dur = slam1Wind, style = QUAD, pose = body(22, 0, 22, 22, { RS = { 172, 0, 0 }, LS = { 168, 0, 0 }, N = { -14, 0, 0 } }, 18, 0, 0.3) },
		-- ...and driven down onto it
		{ dur = 0.1, style = QUART, pose = body(-36, 0, 42, 42, { RS = { 36, 0, 0 }, LS = { 36, 0, 0 }, N = { 18, 0, 0 } }, 18, 0, -0.45) },
		-- (shorter by the hit-stop that freezes him on the blow, so the rest
		-- stays in step with the server)
		{ dur = T.back - T.slam1 - SLAM1_STOP * 0.96, style = Enum.EasingStyle.Sine, pose = body(-32, 0, 40, 40, { RS = { 32, 0, 0 }, LS = { 32, 0, 0 }, N = { 14, 0, 0 } }, 18, 0, -0.4) },
		-- REVERSAL: the chain wrenched back the other way, his body following
		-- it round, the maul swung up out of the crater
		{ dur = 0.12, style = QUAD, pose = body(10, 30, 30, 34, { RS = { 60, 0, 0 }, LS = { 80, 0, 0 }, N = { 0, -10, 0 } }, 20, -0.2, 0.3) },
		{ dur = T.reverse - 0.12, style = Enum.EasingStyle.Sine, pose = body(8, -30, 30, 30, { RS = { 140, 0, 0 }, LS = { 70, 0, 0 }, N = { -6, 14, 0 } }, 20, 0.2, 0.2) },
		-- EXECUTION: raised high with both hands, knees bent, held...
		{ dur = hold2 * 0.55, style = QUAD, pose = body(24, 0, 30, 30, { RS = { 182, 6, 0 }, LS = { 176, -6, 0 }, N = { -18, 0, 0 } }, 20, 0, 0.4) },
		{ dur = hold2 * 0.45, style = Enum.EasingStyle.Sine, pose = body(26, 0, 32, 32, { RS = { 186, 6, 0 }, LS = { 180, -6, 0 }, N = { -20, 0, 0 } }, 20, 0, 0.45) },
		-- ...brought down with everything he has
		{ dur = 0.1, style = QUART, pose = body(-48, 0, 50, 50, { RS = { 28, 0, 0 }, LS = { 28, 0, 0 }, N = { 24, 0, 0 } }, 20, 0, -0.65) },
		-- the maul left planted in the crater, then he slowly straightens
		{ dur = 0.36, style = Enum.EasingStyle.Sine, pose = body(-42, 0, 46, 46, { RS = { 26, 0, 0 }, LS = { 26, 0, 0 }, N = { 18, 0, 0 } }, 18, 0, -0.55) },
		{ dur = T.done - T.slam2 - 0.36, style = QUAD, pose = body(-18, 0, 28, 28, { RS = { 40, 0, 0 }, LS = { 38, 0, 0 }, N = { 6, 0, 0 } }, 16, 0, -0.3) },
	}, 0.6, true, { carry = 1.4 })
	-- (tipped down a little for both blows, so the head meets the floor on
	-- the body ahead of him rather than past it; righted as he rises)
	wristTo(char, -10, 0.1, T.slam1 - 0.12)
	wristTo(char, 0, 0.2, T.back)
	wristTo(char, -10, 0.1, T.slam2 - 0.12)
	wristTo(char, 0, 0.3, T.slam2 + 0.36)
	task.delay(T.slam1, CastPoses.hitStop, char, SLAM1_STOP)
	task.delay(T.slam2, CastPoses.hitStop, char, 0.2)
end

local function kingPose(char: Model)
	local T = KING
	-- (no roll here: arm forward, the head up; overhead, the head back)
	CastPoses.play(char, {
		-- 1 · feet planted, the hammer raised slowly before him
		{ dur = T.summon, style = QUAD, pose = body(-6, 0, 30, 30, { RS = { 110, 0, 0 }, LS = { 106, 0, 0 }, N = { -6, 0, 0 } }, 16, 0, 0) },
		-- 2 · held high overhead, looking up at what's forming over him
		{ dur = T.rise - T.summon, style = QUAD, pose = body(14, 0, 24, 24, { RS = { 172, 0, 0 }, LS = { 168, 0, 0 }, N = { -28, 0, 0 } }, 16, 0, 0.2) },
		-- 3 · launched up, both hands on it, arched back
		{ dur = T.fall - T.rise, style = QUAD, pose = { Root = { 0, 0, 0 }, W = { 20, 0, 0 }, RS = { 190, 0, 0 }, LS = { 186, 0, 0 },
			RH = { 40, 0, 8 }, LH = { -10, 0, -8 }, N = { -24, 0, 0 } } },
		-- 4 · brought down with everything he has
		{ dur = T.impact - T.fall, style = QUART, pose = body(-44, 0, 46, 46, { RS = { 30, 0, 0 }, LS = { 30, 0, 0 }, N = { 22, 0, 0 } }, 16, 0, -0.5) },
		-- 5 · crouched over the impact while the grave wakes
		{ dur = T.fade - T.impact, pose = body(-30, 0, 40, 40, { RS = { 36, 0, 0 }, LS = { 34, 0, 0 }, N = { 4, 0, 0 } }, 16, 0, -0.4) },
		-- 6 · stood, the hammer rested on his shoulder
		{ dur = T.done - T.fade + 0.3, style = QUAD, pose = body(4, -10, 10, 10, { RS = { 160, -20, -20 }, LS = { 120, -40, 0 }, N = { 0, 8, 0 } }, 12, 0, 0) },
	}, 0.4, true)
	wristTo(char, -80, T.impact - T.fall, T.fall)
	wristTo(char, 0, 0.3, T.fade)
	task.delay(KING.impact, CastPoses.hitStop, char, 0.12)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- The two-handed hold (every Death Knight, every client)
-- ═════════════════════════════════════════════════════════════════════════════
-- Out of attacks, both hands stay on the Graveblade's hilt, the blade held out
-- in front; in every pose the right arm leads and the left reaches after the
-- hilt (the same grip as the Berserker's).
-- The idle: the maul held across his body, low right hand by the hip, left
-- hand high up the haft toward the head, the head up and out past his left
-- shoulder and the spearhead down by his right knee; feet planted wide.
-- (Tuned in game against the reference, seen from the front: the right arm's
-- pose, how far the hands slide along the haft, how far up it the left sits.)
local HOLD_ARMS = { RS = { 85, 65, -55 }, LS = { 130, -50, 130 } }
local HOLD_TURN = { W = { 0, 15, 0 }, RH = { 0, -15, 0 }, LH = { 0, -15, 0 } }
-- (stood still: feet planted wide, the body lowered as far as the legs spread)
local HOLD_STANCE = { RH = { 0, 0, 24 }, LH = { 0, 0, -24 }, Root = { 0, 0, 0, 0, -0.17, 0 } }
local HOLD_SLIDE = -1.4 -- studs the hands sit further down the haft (-: up it, toward the head)
local HOLD_LEFT = -2.0  -- the left hand up the haft from the right (swings: LEFT_BEHIND)
local HOLD_WRIST = 0    -- the maul turned in the hand in the idle
local holdWeight: { [Model]: number } = {}
local stanceWeight: { [Model]: number } = {}

-- (Studio only: Workspace attributes DKHoldRS (Vector3), DKHoldSlide,
-- DKHoldLeft, DKHoldWrist override the idle's numbers live, to tune it)
local STUDIO = RunService:IsStudio()
local function tuned(name: string, default: any): any
	if not STUDIO then return default end
	local v = Workspace:GetAttribute(name)
	return if v ~= nil then v else default
end

local function holdStep(dt: number)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not (char and isDK(p) and char:FindFirstChild("Graveblade")) or (char and char:GetAttribute("Tumbling")) then
			if char then holdWeight[char] = nil end
			continue
		end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		local w = holdWeight[char] or 0
		-- (out quickly into an attack, but not in one frame: the hands slide back
		-- along the haft instead of jumping)
		w = if CastPoses.isPlaying(char) then math.max(0, w - dt * 16) else math.min(1, w + dt * 7)
		holdWeight[char] = w
		if w <= 0 then continue end
		local motors = CastPoses.resolveMotors(char)
		for key, v in pairs(HOLD_ARMS) do
			if key == "RS" then
				local o = tuned("DKHoldRS", nil)
				if typeof(o) == "Vector3" then v = { o.X, o.Y, o.Z } end
			end
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
		local still = stanceWeight[char] or 0
		still = if hum.MoveDirection.Magnitude < 0.1 then math.min(1, still + dt * 5) else math.max(0, still - dt * 8)
		stanceWeight[char] = still
		local k = w * still
		if k > 0 then
			for key, v in pairs(HOLD_STANCE) do
				local m = motors[key]
				if m then
					local scaled = { v[1] * k, v[2] * k, v[3] * k, (v[4] or 0) * k, (v[5] or 0) * k, (v[6] or 0) * k }
					m.motor.Transform = m.motor.Transform * (m.basis:Inverse() * CastPoses.poseCF(scaled) * m.basis)
				end
			end
		end
	end
	for char in pairs(holdWeight) do
		if not char.Parent then
			holdWeight[char] = nil
			stanceWeight[char] = nil
		end
	end
end

local REACH_SLACK = 0.97
local LEFT_BEHIND = 0.6 -- studs from the right hand toward the pommel
local bladeAxis: { [Tool]: Vector3 } = setmetatable({}, { __mode = "k" }) :: any

local function inside(p: Vector3, c: Vector3, r: number): Vector3
	local d = p - c
	return if d.Magnitude > r then c + d.Unit * r else p
end

local function turnBetween(a: Vector3, b: Vector3): CFrame
	local axis = a:Cross(b)
	local dot = math.clamp(a:Dot(b), -1, 1)
	if axis.Magnitude < 1e-5 then return CFrame.identity end
	return CFrame.fromAxisAngle(axis.Unit, math.acos(dot))
end

local function armIn(m: Motor6D): CFrame
	return m.C0 * m.Transform * m.C1:Inverse()
end

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
	local a0, a1 = tool:FindFirstChild("GraveBase", true), tool:FindFirstChild("GraveTip", true)
	local v = if a0 and a1 and a0:IsA("Attachment") and a1:IsA("Attachment")
		then handle.CFrame:VectorToObjectSpace(a1.WorldPosition - a0.WorldPosition)
		else Vector3.new(0, -1, 0)
	v = if v.Magnitude > 1e-3 then v.Unit else Vector3.new(0, -1, 0)
	bladeAxis[tool] = v
	return v
end

-- Where the left hand takes the haft (Torso space). R6 arms are rigid: the
-- hand always lands a full arm's length from the shoulder, so of the points
-- along the haft near `along` (studs from the right hand toward the butt)
-- it takes the one that arm's length reaches best, never one that would put
-- the hand inside the torso; then aims there.
local LEFT_SPAN = { -1.0, 1.6 } -- how far either side of `along` it may slide
local function torsoDepth(h: Vector3): number
	-- (the arm's thickness included: the hand clear of the chest by 1 stud)
	if math.abs(h.X) >= 1.5 or h.Y < -1.6 or h.Y > 1.4 then return 0 end
	return math.max(0, h.Z + 1.0)
end
local function leftGrip(g: Vector3, blade: Vector3, along: number, pL: Vector3, reachL: number): Vector3
	local best, bestScore = g - blade * along, math.huge
	for k = 0, 26 do
		local s = along + LEFT_SPAN[1] + (LEFT_SPAN[2] - LEFT_SPAN[1]) * k / 26
		local p = g - blade * s
		local off = p - pL
		local d = off.Magnitude
		if d < 1e-3 then continue end
		local hand = pL + off / d * reachL
		local score = math.abs(d - reachL) * 3 + math.abs(s - along) * 0.6 + torsoDepth(hand) * 12
		if score < bestScore then best, bestScore = p, score end
	end
	-- (still in the chest? pushed out in front of it)
	local off = best - pL
	local hand = pL + off.Unit * reachL
	local dep = torsoDepth(hand)
	if dep > 0 then
		best = Vector3.new(best.X, best.Y, math.min(best.Z, -1.05))
	end
	return best
end

local swingFree: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
-- (Grave Reversal: the one on the chain, the free hand aimed after it)
local haulAim: { [Model]: BasePart } = setmetatable({}, { __mode = "k" }) :: any
local function twoHandStep(dt: number)
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not (char and isDK(p)) or char:GetAttribute("Tumbling") then continue end
		local tool = char:FindFirstChild("Graveblade")
		local torso = char:FindFirstChild("Torso")
		local rArm, lArm = char:FindFirstChild("Right Arm"), char:FindFirstChild("Left Arm")
		if not (tool and tool:IsA("Tool") and torso and rArm and lArm) then continue end
		local rs, ls = torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder")
		local grip = rArm:FindFirstChild("RightGrip")
		local handle = tool:FindFirstChild("Handle")
		if not (rs and ls and grip and handle and rs:IsA("Motor6D") and ls:IsA("Motor6D") and grip:IsA("JointInstance") and handle:IsA("BasePart")) then continue end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then continue end
		-- (the wrist: the maul turned in the hand)
		-- (kept on the grip itself: a weak table keyed by an Instance can lose
		-- it to a GC pass, and the turned grip would then become the new rest)
		local base = grip:GetAttribute("DKGripBase") :: CFrame?
		if typeof(base) ~= "CFrame" then
			base = (grip :: any).C0 :: CFrame
			grip:SetAttribute("DKGripBase", base)
		end
		-- (in the idle hold the maul's turned in the hand and the hands sit
		-- further down the haft)
		local hw = holdWeight[char] or 0
		local turn = wristOf(char) + (tuned("DKHoldWrist", HOLD_WRIST) :: number) * hw
		local want = if turn ~= 0 then (base :: CFrame) * CFrame.Angles(math.rad(turn), 0, 0) else base :: CFrame
		if hw > 0 then
			local c1 = (grip :: any).C1 :: CFrame
			want = want * c1:Inverse() * CFrame.new(0, -(tuned("DKHoldSlide", HOLD_SLIDE) :: number) * hw, 0) * c1
		end
		if (grip :: any).C0 ~= want then (grip :: any).C0 = want end
		local leftAlong = LEFT_BEHIND + ((tuned("DKHoldLeft", HOLD_LEFT) :: number) - LEFT_BEHIND) * hw

		local handR = (base :: CFrame).Position
		local handL = Vector3.new(0, -1, 0)
		local reachR = (handR - rs.C1.Position).Magnitude * REACH_SLACK
		local reachL = (handL - ls.C1.Position).Magnitude * REACH_SLACK
		local pR, pL = rs.C0.Position, ls.C0.Position

		local aR = armIn(rs)
		local free = aR * handR
		local blade0 = (aR * grip.C0 * grip.C1:Inverse()):VectorToWorldSpace(bladeOf(tool, handle))
		local pL2 = pL + blade0 * leftAlong
		local held = free
		local across = pL2 - pR
		local d = across.Magnitude
		if d > 1e-3 and d < reachR + reachL and d > math.abs(reachR - reachL) then
			local n = across / d
			local a = (d * d + reachR * reachR - reachL * reachL) / (2 * d)
			local ring = math.sqrt(math.max(reachR * reachR - a * a, 0))
			local c = pR + n * a
			local off = free - c
			off -= n * off:Dot(n)
			if off.Magnitude < 1e-3 then
				local fwd = Vector3.new(0, -0.5, -1)
				off = fwd - n * fwd:Dot(n)
			end
			held = c + off.Unit * ring
		else
			for _ = 1, 4 do
				held = inside(held, pL2, reachL)
				held = inside(held, pR, reachR)
			end
		end
		local w = swingFree[char] or 0
		w = if CastPoses.isPlaying(char) then math.min(1, w + dt * 12) else math.max(0, w - dt * 6)
		swingFree[char] = w
		local g = held:Lerp(free, w)
		aR = aim(rs, aR, handR, g)
		rs.Transform = rs.C0:Inverse() * aR * rs.C1

		local handleCF = aR * grip.C0 * grip.C1:Inverse()
		local blade = handleCF:VectorToWorldSpace(bladeOf(tool, handle))
		local gl = leftGrip(g, blade, leftAlong, pL, reachL)
		-- (Grave Reversal: the free hand holding the chain, aimed at the one on it)
		local hauled = haulAim[char]
		if hauled and hauled.Parent and torso:IsA("BasePart") then
			local to = torso.CFrame:PointToObjectSpace(hauled.Position) - pL
			if to.Magnitude > 0.1 then gl = pL + to.Unit * reachL end
		end
		local aL = aim(ls, armIn(ls), handL, gl)
		ls.Transform = ls.C0:Inverse() * aL * ls.C1
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Moving the body (your own character: its movement replicates)
-- ═════════════════════════════════════════════════════════════════════════════
type Mover = { set: (Vector3) -> (), face: (Vector3) -> (), stop: (snap: boolean?) -> (), stand: number, alive: () -> boolean }

local function holdBody(char: Model, root: BasePart): Mover?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local stand = SafeMove.StandHeight(root)
	local a = Instance.new("Attachment")
	a.Name = "DeathKnightMove"
	a.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = a
	ap.RigidityEnabled = true
	ap.Position = root.Position
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = a
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
			a:Destroy()
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

local function timeline(duration: number, step: (number) -> (), done: () -> ())
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local ok, err = pcall(step, math.min(t, duration))
		if not ok then warn("[DeathKnightController] move", err) end
		if t >= duration or not ok then
			conn:Disconnect()
			done()
		end
	end)
end

local function easeOut(a: number): number return 1 - (1 - a) ^ 2 end
local function easeIn(a: number): number return a * a end

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

-- ═════════════════════════════════════════════════════════════════════════════
-- M1: the Graveblade
-- ═════════════════════════════════════════════════════════════════════════════
local function comboVFX(char: Model, step: number, dir: Vector3, speed: number)
	local root = rootOf(char)
	if not root then return end
	local look = CFrame.lookAt(root.Position, root.Position + dir)
	local strike = (SWING.land[step] - 0.1) / speed -- (the swing's fast part)
	if step == 3 then
		-- (the trail through the spin and the slam)
		task.delay(0.24 / speed, trail, char, (SWING.land[3] - 0.1) / speed)
		task.delay(0.26 / speed, function() if root.Parent then ClassFX.Sound("whoosh", root, 0.7, 0.5) end end)
	else
		task.delay(strike - 0.04 / speed, trail, char, 0.3 / speed)
	end
	task.delay(strike, function() if root.Parent then ClassFX.Sound("whoosh", root, 0.85, if step == 3 then 0.55 else 0.62) end end)
	if step == 1 then
		task.delay(strike, smokeArc, { cf = look * CFrame.new(0, -0.3, 0) * CFrame.Angles(0, 0, math.rad(-6)), radius = 8, span = 165,
			sweep = 1, width = 2.2, life = 0.38, draw = 0.1 })
	elseif step == 2 then
		task.delay(strike, smokeArc, { cf = look * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(28)), radius = 8, span = 160,
			sweep = -1, width = 2.2, life = 0.38, draw = 0.1 })
	end
end

-- Planted for the swing (he can't stroll while heaving it), stepping into
-- the strike; free to move again once it's followed through.
local m1Mover: Mover? = nil
local m1Token = 0
local function plantSwing(char: Model, root: BasePart, step: number, dir: Vector3, speed: number)
	m1Token += 1
	local my = m1Token
	if m1Mover then m1Mover.stop(false) end
	local m = holdBody(char, root)
	m1Mover = m
	if not m then return end
	local mv = m :: Mover
	mv.face(dir)
	local start = standAt(root.Position, mv.stand)
	-- (stepping into a swing; carried forward through the finisher's flip)
	local stepIn = if step == 3 then 2.5 else 0.7
	local to = standAt(start + dir * SafeMove.ClampDash(root, dir, stepIn), mv.stand)
	local land, held = SWING.land[step] / speed, SWING.held[step] / speed
	local from, span = land - 0.12 / speed, 0.2 / speed
	if step == 3 then from, span = 0.24 / speed, land - 0.24 / speed end
	timeline(held, function(t)
		if not mv.alive() then return end
		local a = math.clamp((t - from) / span, 0, 1)
		mv.set(start:Lerp(to, a * a * (3 - 2 * a)))
	end, function()
		if m1Token == my and m1Mover == m then m1Mover = nil end
		mv.stop(true)
	end)
end

function DeathKnightController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	-- (each swing has its own weight: the next waits for this one's follow-through)
	if localStep > 0 and now - lastSwing < SWING.free[localStep] / speed then return true end
	localStep = if now - lastSwing > COMBO_RESET or localStep >= 3 then 1 else localStep + 1
	lastSwing = now
	local dir = flatDir(deps.getAim(root), root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	swingPose(char, localStep, speed)
	comboVFX(char, localStep, dir, speed)
	plantSwing(char, root, localStep, dir, speed)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Skills (caster)
-- ═════════════════════════════════════════════════════════════════════════════
local doomLanding: Vector3? = nil -- (where our own Doomfall lands: the crash is drawn there)

local function doomLeap(char: Model, root: BasePart, dir: Vector3, cursor: Vector3?): Vector3?
	doomLanding = nil
	local mv = holdBody(char, root)
	if not mv then return nil end
	local m = mv :: Mover
	local origin = root.Position
	local want = 8
	if cursor then
		local d = Vector3.new(cursor.X - root.Position.X, 0, cursor.Z - root.Position.Z)
		want = math.min(d.Magnitude, DOOM_RANGE)
	end
	local dist = SafeMove.ClampDash(root, dir, want)
	local land = standAt(origin + dir * dist, m.stand)
	local apex = origin:Lerp(land, 0.5)
	apex = Vector3.new(apex.X, math.max(origin.Y, land.Y) + DOOM_HEIGHT + dist * 0.15, apex.Z)
	local apex2 = origin:Lerp(land, 0.7)
	apex2 = Vector3.new(apex2.X, apex.Y + 0.8, apex2.Z)
	m.face(dir)
	local T = DOOM
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
	doomLanding = land
	return land
end

-- Grave Reversal: held to the spot through the thrust; the server says what the
-- chain caught, and the haul's timeline comes with it (onSnatch).
local snatchMover: Mover? = nil
local snatchToken = 0

local kingMover: Mover? = nil

function DeathKnightController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

function DeathKnightController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, _config: any, cursor: Vector3?): Vector3?
	-- (a skill cuts a swing short: its plant lets go)
	m1Token += 1
	if m1Mover then
		m1Mover.stop(false)
		m1Mover = nil
	end
	local dir = flatDir(aimDir, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	char:SetAttribute("AllowSkillMovement", false)
	if skillIndex == 1 then
		busyUntil = os.clock() + WAKE_WINDUP + 0.3
		blackwakePose(char)
		local m = holdBody(char, root)
		if m then
			-- walked forward with it as it drags, heavy, then planted for the heave
			local mv = m :: Mover
			mv.face(dir)
			local start = standAt(root.Position, mv.stand)
			local to = standAt(start + dir * WAKE_STEP, mv.stand)
			timeline(WAKE_WINDUP + 0.25, function(t)
				if not mv.alive() then return end
				local a = math.clamp((t - WAKE_PLANT) / (WAKE_WINDUP - WAKE_PLANT - 0.04), 0, 1)
				mv.set(start:Lerp(to, a * a * (3 - 2 * a)))
			end, function() mv.stop(true) end)
		end
		releaseAfter(char, WAKE_WINDUP + 0.3)
	elseif skillIndex == 2 then
		busyUntil = os.clock() + DOOM.impact + 0.35
		doomPose(char)
		local land = doomLeap(char, root, dir, cursor)
		releaseAfter(char, DOOM.impact + 0.35)
		return land
	elseif skillIndex == 3 then
		-- (the real length comes with the server's answer; this is the fallback)
		busyUntil = os.clock() + 1.2
		thrustPose(char)
		snatchToken += 1
		local my = snatchToken
		if snatchMover then snatchMover.stop(false) end
		snatchMover = holdBody(char, root)
		if snatchMover then snatchMover.face(dir) end
		task.delay(1.4, function()
			-- the server never answered: let go
			if snatchToken == my and snatchMover then
				snatchMover.stop(true)
				snatchMover = nil
				releaseAfter(char, 0)
			end
		end)
	elseif skillIndex == 4 then
		busyUntil = os.clock() + KING.done
		kingPose(char)
		if kingMover then kingMover.stop(false) end
		kingMover = holdBody(char, root)
		local m = kingMover
		if m then
			-- planted; launched straight up; brought down onto the same spot
			local mv = m :: Mover
			mv.face(dir)
			local start = standAt(root.Position, mv.stand)
			local top = start + Vector3.new(0, KING_HIGH, 0)
			timeline(KING.done, function(t)
				if not mv.alive() then return end
				if t < KING.rise then
					mv.set(start)
				elseif t < KING.fall then
					mv.set(start:Lerp(top, easeOut((t - KING.rise) / (KING.fall - KING.rise))))
				elseif t < KING.impact then
					mv.set(top:Lerp(start, easeIn((t - KING.fall) / (KING.impact - KING.fall))))
				else
					mv.set(start)
				end
			end, function()
				mv.stop(true)
				if kingMover == m then kingMover = nil end
			end)
		end
		releaseAfter(char, KING.done)
	end
	return nil
end

-- The planted blade, seen close (the caster and everyone watching): low in
-- front of him as he drives it down, pulling back as the ghostfire spreads.
function DeathKnightController.PlayUltCutscene(char: Model, dir: Vector3)
	local root = rootOf(char)
	if not root then return end
	-- Close on him as he raises the hammer, then tilting up and out to the
	-- spectral warhammer forming over him.
	UltimateCameraChoreography.PlayCloseUp(char, dir, KING.rise, nil, nil, {
		startOffset = { 7, -1.4, 0.5 },
		endOffset = { 9, -2, 0.8 },
		focusHeight = 2.5,
		fovStart = 50,
		fovEnd = 56,
		pullAt = KING.summon * 0.9,
		pullOffset = { 34, -10, 2 },
		pullFocus = 30,
		pullFov = 80,
	})
	tint("DeathKnightGrave", { Brightness = -0.08, Saturation = -0.5, Contrast = 0.2, TintColor = Color3.fromRGB(180, 205, 240) },
		KING.fade, 0.3, 0.6)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Server moments (DeathKnightFX)
-- ═════════════════════════════════════════════════════════════════════════════
local function onCombo(msg: any)
	if msg.attacker == player then return end -- ours was predicted on click
	local char = charOf(msg.attacker)
	if not char or not FxBudget.Allow("dkSwing", 10) then return end
	swingPose(char, msg.step)
	comboVFX(char, msg.step, msg.dir, 1)
end

-- The overhead slam lands: the floor cracks, black mist bursts out of it.
local function onSmash(msg: any)
	local g = groundAt(msg.pos)
	local r = (msg.radius :: number) * 0.6
	-- the head driven into the floor: a small crater torn up round it, the
	-- air blown out, black smoke and rubble thrown high
	if FxBudget.Allow("dkSmashCrater", 3) then roundCrater(g, 1.2, r * 0.7, 2, 3.4) end
	darkShockwave(g, r, 0.35)
	task.delay(0.05, darkShockwave, g, r * 1.4, 0.45, false)
	SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.8, 0)), radius = 2, arc = 359, width = 0.9, color = FROST, life = 0.3,
		draw = 0.001, grow = (r * 1.3 - 2) / 2, core = Color3.new(1, 1, 1) })
	darkSmoke(g + Vector3.new(0, 0.6, 0), 16, 2.6, 12, 1, 0.8)
	if FxBudget.Allow("dkRocks", 6) then rocks(g + Vector3.new(0, 0.4, 0), 10, 24, 24) end
	shards(g, r * 0.35, 6, 1, 2.2, 0.7)
	motes(g + Vector3.new(0, 0.8, 0), 8, 12)
	ClassFX.Sound("rockHit", msg.pos, 1, 0.6)
	ClassFX.Sound("quake", msg.pos, 0.55, 1.1, 0.8)
	ClassFX.Sound("boom", msg.pos, 0.6, 0.85)
	if msg.attacker == player then
		deps.shake(1, 0.22)
		deps.fovPunch(5, 0.18)
	elseif near(g, 50) then
		deps.shake(0.3, 0.15)
	end
end

-- Dreadforged: a spectral shockwave rolling off where the blade landed.
local function onDreadWave(msg: any)
	if not FxBudget.Allow("dkDreadWave", 8) then return end
	local g = groundAt(msg.pos)
	SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.5, 0)), radius = msg.radius * 0.45, arc = 359, width = 0.7, color = SPECTRAL,
		life = 0.35, draw = 0.001, grow = 1.2, core = FROST })
	smokeRing(g + Vector3.new(0, 0.6, 0), 18, 1.4, msg.radius * 2.2, 0.45)
end

local function onBlackwake(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local mine = msg.attacker == player
	if not mine then blackwakePose(char) end
	local dir = msg.dir :: Vector3
	local from = groundAt(msg.from :: Vector3)
	trail(char, (msg.windup :: number) + 0.4)
	ClassFX.Sound("whoosh", root, 0.5, 0.45)
	-- The head set down with a thud, then scraping the floor behind him as he
	-- drags it: sparks and black dust kicked up all the way.
	task.delay(WAKE_PLANT, function()
		if not root.Parent then return end
		local tip = bladeTip(char) or (root.Position - dir * 3)
		ClassFX.Sound("rockHit", tip, 0.7, 0.55)
		darkSmoke(groundAt(tip) + Vector3.new(0, 0.3, 0), 6, 1.4, 4, 0.7, 0.4)
		if FxBudget.Allow("dkSparks", 4) then grindSparks(groundAt(tip) + Vector3.new(0, 0.2, 0), -dir, 22, 26) end
		if mine then deps.shake(0.35, 0.12) end
		local t0 = os.clock()
		while os.clock() - t0 < (msg.windup :: number) - WAKE_PLANT and root.Parent do
			if FxBudget.Allow("dkDrag", 30) then
				local g = groundAt(bladeTip(char) or (root.Position - dir * 3)) + Vector3.new(0, 0.2, 0)
				darkSmoke(g, 2, 1, 3, 0.5, 0.5)
				motes(g, 2, 7)
				-- (thrown back off the head as it's dragged forward)
				grindSparks(g, -dir, 5, 18)
			end
			task.wait(0.05)
		end
	end)
	task.delay(msg.windup, function()
		if not root.Parent then return end
		ClassFX.Sound("whoosh", root, 1, 0.5)
		ClassFX.Sound("boom", root, 0.8, 0.8)
		ClassFX.Sound("quake", from, 0.8, 1, 1.2)
		-- the swing itself, a black arc torn up from the floor and on overhead
		smokeArc({ cf = CFrame.lookAt(root.Position, root.Position + dir) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.new(1, 0, 0), radius = 6.5, span = 200,
			sweep = -1, width = 2.6, life = 0.45, draw = 0.1 }) -- (from the floor behind, up and on over)
		darkShockwave(from + dir * 2, 5, 0.35, false)
		darkSmoke(from + Vector3.new(0, 0.6, 0) + dir * 2, 12, 2.4, 10, 0.9, 0.6)
		motes(from + Vector3.new(0, 1, 0) + dir * 2, 8, 12)
		-- the crater: torn open in a cone out in front of him
		local half = msg.half :: number
		local range = msg.range :: number
		coneCrater(from, dir, half, range, msg.speed :: number)
		-- (Dreadforged: a second, shallower wave of black smoke rolls up it)
		for w = 2, (msg.waves :: number) do
			task.delay((w - 1) * (msg.gap :: number), function()
				local side = Vector3.new(-dir.Z, 0, dir.X)
				for a = 4, range, 4 do
					task.delay(a / (msg.speed :: number), function()
						local wd = a * math.tan(half) * 0.6
						craterSmoke(groundAt(from + dir * a + side * wd + Vector3.new(0, 3, 0)), 0.8)
						craterSmoke(groundAt(from + dir * a - side * wd + Vector3.new(0, 3, 0)), 0.8)
					end)
				end
			end)
		end
		if mine then
			deps.shake(1, 0.3)
			deps.fovPunch(6, 0.25)
		elseif near(from, 60) then
			deps.shake(0.4, 0.2)
		end
	end)
end

-- F · Doomfall: the crouch, the leap, mist gathering on the raised blade.
local function onDoomfall(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then doomPose(char) end
	local T = msg.t
	local origin = root.Position
	local g0 = groundAt(origin)
	trail(char, T.crouch + T.rise + T.hang + T.fall + 0.3)
	ClassFX.Sound("whoosh", root, 0.5, 0.45)
	task.delay(T.crouch, function()
		if not root.Parent then return end
		darkSmoke(g0 + Vector3.new(0, 0.4, 0), 10, 1.8, 9, 0.9, 0.2)
		rocks(g0 + Vector3.new(0, 0.3, 0), 5, 12, 10)
		darkShockwave(g0, 6, 0.3, false)
		ClassFX.Sound("whoosh", root, 0.9, 0.55)
		if msg.attacker == player then deps.fovPunch(6, 0.25) end
	end)
	-- the hang: black mist drawn in onto the raised blade
	task.delay(T.crouch + T.rise * 0.5, function()
		if not root.Parent then return end
		local holder = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 9, Transparency = 1 })
		local e = Instance.new("ParticleEmitter")
		e.Texture = TEX_SMOKE
		e.Color = ColorSequence.new(OBSIDIAN, CHARCOAL)
		e.LightEmission = 0
		e.LightInfluence = 0.3
		e.Size = NumberSequence.new({ kp(0, 2.4), kp(1, 0.6) })
		e.Transparency = NumberSequence.new({ kp(0, 1), kp(0.3, 0.3), kp(1, 0.6) })
		e.Lifetime = NumberRange.new(0.3, 0.4)
		e.Speed = NumberRange.new(12, 16)
		e.Shape = Enum.ParticleEmitterShape.Sphere
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
		e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
		e.Rotation = NumberRange.new(0, 360)
		e.Rate = 70
		e.Parent = holder
		local dur = T.rise * 0.5 + T.hang + T.fall * 0.5
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local p = bladeTip(char)
			if os.clock() - t0 > dur or not p then
				conn:Disconnect()
				e.Enabled = false
				Debris:AddItem(holder, 0.5)
				return
			end
			holder.CFrame = CFrame.new(p)
		end)
	end)
end

-- The crash: sword-first into the floor, a wide dark shockwave, shards and
-- rock, black smoke rolling out, and thick mist left lying on the spot.
local function onDoomImpact(msg: any)
	-- (our own leap's landing: drawn where the body comes down; used once)
	local pos = if msg.attacker == player and doomLanding then doomLanding :: Vector3 else msg.pos :: Vector3
	if msg.attacker == player then doomLanding = nil end
	local r = msg.radius :: number
	local g = groundAt(pos)
	roundCrater(g, r * 0.3, r * 0.8, 3, 6)
	darkShockwave(g, r, 0.5)
	task.delay(0.08, darkShockwave, g, r * 1.25, 0.6, false)
	smokeRing(g + Vector3.new(0, 0.7, 0), 54, 2.6, r * 2.4, 0.7)
	darkSmoke(g + Vector3.new(0, 1, 0), 16, 3, 8, 1.1, 1)
	shards(g, r * 0.55, if msg.dread then 14 else 10, 1.6, 3.6, 0.9)
	rocks(g + Vector3.new(0, 0.5, 0), 10, 24, 26)
	motes(g + Vector3.new(0, 1, 0), 14, 16)
	ClassFX.Sound("quake", pos, 0.9, 0.9, 1.4)
	ClassFX.Sound("boom", pos, 0.9, 0.8)
	ClassFX.Sound("boom", pos, 0.6, 0.6)
	if msg.attacker == player then
		deps.shake(1.3, 0.32)
		deps.fovPunch(8, 0.3)
	elseif near(pos, 60) then
		deps.shake(0.5, 0.25)
	end
	-- The mist lying on the spot, low and thick, for as long as it bites.
	local life = math.max(tonumber(msg.mist) or 3, 0.5)
	local pool = part({ Size = Vector3.new(r * 1.4, 0.5, r * 1.4), Transparency = 1, CFrame = CFrame.new(g + Vector3.new(0, 0.6, 0)) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SMOKE
	e.Color = ColorSequence.new(OBSIDIAN, CHARCOAL)
	e.LightEmission = 0
	e.LightInfluence = 0.4
	e.Size = NumberSequence.new({ kp(0, 2.5), kp(1, 5) })
	e.Transparency = NumberSequence.new({ kp(0, 1), kp(0.25, if msg.dread then 0.25 else 0.4), kp(1, 1) })
	e.Lifetime = NumberRange.new(1.2, 1.8)
	e.Speed = NumberRange.new(0.3, 1)
	e.SpreadAngle = Vector2.new(180, 10)
	e.Acceleration = Vector3.new(0, 0.4, 0)
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-15, 15)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Rate = 22
	e.Parent = pool
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = TEX_SPARK
	sp.Color = ColorSequence.new(SPECTRAL)
	sp.LightEmission = 1
	sp.Size = NumberSequence.new({ kp(0, 0.16), kp(1, 0) })
	sp.Lifetime = NumberRange.new(0.6, 1)
	sp.Speed = NumberRange.new(0.5, 1.5)
	sp.Acceleration = Vector3.new(0, 1.5, 0)
	sp.Shape = Enum.ParticleEmitterShape.Box
	sp.Rate = if msg.dread then 10 else 4
	sp.Parent = pool
	task.delay(life, function()
		e.Enabled = false
		sp.Enabled = false
	end)
	Debris:AddItem(pool, life + 2)
end

-- Q · Grave Reversal: the chain shoots from his left palm.
local snatches: { [Player]: { chain: Chain?, coil: Chain?, token: number, tip: (() -> Vector3?)?, victim: BasePart? } } = {}

-- The chain coiled round the one it caught: rings of iron links wound round
-- its chest and arms, following it, coiling on over `wind` seconds.
local COIL_RINGS = { { y = 0.55, tilt = 8 }, { y = 0.05, tilt = -6 }, { y = -0.45, tilt = 10 } }
local COIL_LINKS = 11
local function coil(victimRoot: BasePart, wind: number): Chain
	local links: { BasePart } = {}
	local t0 = os.clock()
	local conn: RBXScriptConnection
	local stopped = false
	local function stop()
		if stopped then return end
		stopped = true
		conn:Disconnect()
		for _, l in ipairs(links) do l:Destroy() end
	end
	-- (round the torso: R6's chest is 2 wide, 1 deep)
	local rx, rz = 1.25, 0.8
	conn = RunService.RenderStepped:Connect(function()
		if not victimRoot.Parent then
			stop()
			return
		end
		local total = #COIL_RINGS * COIL_LINKS
		local shown = math.clamp(math.floor(total * (os.clock() - t0) / wind), 0, total)
		while #links < shown do table.insert(links, chainLink()) end
		local cf = victimRoot.CFrame
		for i = 1, #links do
			local ring = COIL_RINGS[math.floor((i - 1) / COIL_LINKS) + 1]
			local k = (i - 1) % COIL_LINKS
			local a = 2 * math.pi * k / COIL_LINKS
			local a2 = 2 * math.pi * (k + 1) / COIL_LINKS
			local base = cf * CFrame.new(0, ring.y, 0) * CFrame.Angles(0, 0, math.rad(ring.tilt))
			local p = base * Vector3.new(math.cos(a) * rx, 0, math.sin(a) * rz)
			local q = base * Vector3.new(math.cos(a2) * rx, 0, math.sin(a2) * rz)
			placeLink(links[i], CFrame.lookAt((p + q) / 2, q) * CFrame.Angles(0, 0, if k % 2 == 0 then 0 else math.pi / 2))
		end
	end)
	return { stop = stop }
end

-- The left hand's palm, where the chain leaves him.
local function palm(char: Model): Vector3?
	local arm = char:FindFirstChild("Left Arm") :: BasePart?
	if arm then return arm.CFrame * Vector3.new(0, -arm.Size.Y / 2 - 0.1, 0) end
	local root = rootOf(char)
	return if root then root.Position + root.CFrame.LookVector * 2 else nil
end

local function onSnatch(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local attacker = msg.attacker :: Player
	local mine = attacker == player
	if not mine then thrustPose(char) end
	local old = snatches[attacker]
	if old then
		if old.chain then old.chain.stop() end
		if old.coil then old.coil.stop() end
	end
	local S = { chain = nil :: Chain?, coil = nil :: Chain?, token = (old and old.token or 0) + 1, tip = nil :: any, victim = nil :: BasePart? }
	snatches[attacker] = S
	local cast = msg.cast :: number
	local travel = math.max(msg.travel :: number, 0.03)
	local to = msg.to :: Vector3
	local model = msg.model :: Model?
	local victimRoot = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart?
	S.victim = victimRoot
	S.tip = function() return palm(char) end
	-- (the free hand reaching after it from the thrust on)
	if victimRoot then haulAim[char] = victimRoot end
	task.delay(cast * 0.8, function()
		if not root.Parent then return end
		ClassFX.Sound("whoosh", root, 0.8, 1.1)
		local p = palm(char)
		if p then motes(p, 8, 8) end
	end)
	-- The chain: out of the palm to the target, then (caught) held taut on it
	-- through both drags, or (missed) reeled back in.
	local t0 = os.clock() + cast
	S.chain = liveChain(function()
		if snatches[attacker] ~= S or not char.Parent then return nil, nil end
		local tip = palm(char)
		if not tip then return nil, nil end
		local t = os.clock() - t0
		if t < 0 then return tip, tip end
		if t < travel then
			local goal = if victimRoot and victimRoot.Parent then victimRoot.Position else to
			return tip, tip:Lerp(goal, t / travel)
		end
		if victimRoot then
			if not victimRoot.Parent then return nil, nil end
			return tip, victimRoot.Position
		end
		local back = math.clamp((t - travel) / travel, 0, 1)
		if back >= 1 then return nil, nil end
		return tip, to:Lerp(tip, back)
	end, if victimRoot then 0.06 else 0.2)
	if model and victimRoot then
		local T = msg.t
		task.delay(cast + travel, function()
			if snatches[attacker] ~= S or not victimRoot.Parent then return end
			-- the chain bites and coils round its chest
			local p = victimRoot.Position
			motes(p, 14, 10)
			darkSmoke(p, 6, 1.6, 6, 0.6)
			ClassFX.Sound("rockHit", p, 0.9, 0.5)
			ClassFX.Sound("punch", p, 0.7, 0.7)
			S.coil = coil(victimRoot, T.wrap * 0.8)
			-- drawn taut as the fist closes
			task.delay(T.wrap * 0.85, function()
				if snatches[attacker] ~= S then return end
				ClassFX.Sound("rockHit", root, 0.7, 0.75)
				if mine then deps.shake(0.4, 0.12) end
			end)
			reversalPose(char, T)
			-- the free hand on the chain while it drags, on the maul for the blows
			local function aimAt(on: boolean)
				if snatches[attacker] ~= S then return end
				haulAim[char] = if on then victimRoot else nil
			end
			task.delay(T.wrap + T.pull, aimAt, false)
			task.delay(T.back, aimAt, true)
			task.delay(T.back + T.reverse, aimAt, false)
			-- the drags: torn across and wrenched back, smoke off the body
			for _, at in ipairs({ T.wrap, T.back }) do
				task.delay(at, function()
					if snatches[attacker] ~= S then return end
					ClassFX.Sound("whoosh", root, 0.9, 0.55)
					if FxBudget.Allow("dkDragTrail", 4) then trail(char, 0.4) end
				end)
			end
		end)
	else
		haulAim[char] = nil
	end
	if not mine then return end

	-- Our own body: planted where it stands, turned to keep facing the one on
	-- the chain (the drags carry it round him: he pivots after it).
	snatchToken += 1
	local m = snatchMover
	snatchMover = nil
	if not m then return end
	local mv = m :: Mover
	mv.face(msg.dir)
	local start = standAt(root.Position, mv.stand)
	if not model then
		local total = cast + travel * 2
		busyUntil = os.clock() + total + 0.1
		releaseAfter(char, total + 0.05)
		task.delay(total, function() mv.stop(true) end)
		return
	end
	local T = msg.t
	local total = cast + travel + T.done
	busyUntil = os.clock() + total + 0.1
	releaseAfter(char, total + 0.05)
	local yaw = math.atan2(-(msg.dir :: Vector3).X, -(msg.dir :: Vector3).Z)
	local lastT = 0
	timeline(total, function(t)
		if not mv.alive() then return end
		local dt = t - lastT
		lastT = t
		mv.set(start)
		if t < cast + travel or not victimRoot or not victimRoot.Parent then return end
		local d = victimRoot.Position - root.Position
		if Vector3.new(d.X, 0, d.Z).Magnitude < 0.5 then return end
		-- (turned after it at a heavy body's pace, not snapped round)
		local want = math.atan2(-d.X, -d.Z)
		local diff = (want - yaw + math.pi) % (2 * math.pi) - math.pi
		yaw += math.clamp(diff, -9 * dt, 9 * dt)
		mv.face(Vector3.new(-math.sin(yaw), 0, -math.cos(yaw)))
	end, function()
		mv.stop(true)
	end)
end

-- The two blows: the first sharp and small, the execution enormous.
local function onSnatchSlam(msg: any)
	local g = msg.pos :: Vector3
	local r = msg.radius :: number
	local big = msg.i == 2
	local mine = msg.attacker == player
	if big then
		-- the execution: the floor caves in, a spectral shockwave tears out,
		-- chains burst from the crater and pin it
		if FxBudget.Allow("dkReversalCrater", 2) then roundCrater(g, 1.6, r * 0.45, 2, 1.7) end
		darkShockwave(g, r, 0.4)
		task.delay(0.06, darkShockwave, g, r * 1.5, 0.55, false)
		for i, h in ipairs({ 0.6, 2.4 }) do
			task.delay((i - 1) * 0.05, function()
				SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, h, 0)), radius = 2, arc = 359, width = 1.4 - i * 0.3, color = FROST, life = 0.45,
					draw = 0.001, grow = (r * 1.4 - 2) / 2, core = Color3.new(1, 1, 1) })
			end)
		end
		SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.3, 0)), radius = 2, arc = 359, width = 1.6, color = SPECTRAL, life = 0.55,
			draw = 0.001, grow = (r * 0.9 - 2) / 2, core = FROST })
		darkSmoke(g + Vector3.new(0, 0.8, 0), 22, 3, 14, 1.2, 0.9)
		smokeRing(g + Vector3.new(0, 0.5, 0), 40, 2.2, r * 3, 0.6)
		shards(g, r * 0.6, 14, 1.6, 3.6, 1)
		if FxBudget.Allow("dkRocks", 6) then rocks(g + Vector3.new(0, 0.4, 0), 14, 30, 30) end
		motes(g + Vector3.new(0, 1, 0), 18, 16)
		local model = msg.model :: Model?
		if model and model.Parent then bindingChains(model, 0.8) end
		ClassFX.Sound("rockHit", g, 1, 0.55)
		ClassFX.Sound("quake", g, 0.9, 0.8)
		ClassFX.Sound("boom", g, 1, 0.65)
		if mine then
			deps.shake(1.5, 0.32)
			deps.fovPunch(8, 0.26)
		elseif near(g, 60) then
			deps.shake(0.5, 0.22)
		end
	else
		-- the first: a small crater, a burst of spectral light, rubble
		if FxBudget.Allow("dkReversalCrater", 2) then roundCrater(g, 1, r * 0.3, 1, 1.1) end
		darkShockwave(g, r * 0.8, 0.35)
		SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.6, 0)), radius = 1.5, arc = 359, width = 0.9, color = FROST, life = 0.3,
			draw = 0.001, grow = (r - 1.5) / 1.5, core = Color3.new(1, 1, 1) })
		darkSmoke(g + Vector3.new(0, 0.6, 0), 12, 2, 9, 0.8, 0.5)
		shards(g, r * 0.4, 7, 1, 2.2, 0.7)
		if FxBudget.Allow("dkRocks", 6) then rocks(g + Vector3.new(0, 0.4, 0), 8, 20, 20) end
		motes(g + Vector3.new(0, 1, 0), 10, 12)
		ClassFX.Sound("rockHit", g, 1, 0.75)
		ClassFX.Sound("boom", g, 0.7, 0.95)
		if mine then
			deps.shake(0.85, 0.2)
			deps.fovPunch(4, 0.16)
		elseif near(g, 50) then
			deps.shake(0.3, 0.16)
		end
	end
end

-- The chain lets go: it comes apart into blue motes along its length, the
-- coil with it.
local function dropSnatch(attacker: Player?)
	local char = charOf(attacker)
	if char then haulAim[char] = nil end
	local S = attacker and snatches[attacker]
	if S then
		local a = S.tip and S.tip()
		local b = S.victim and S.victim.Parent and S.victim.Position
		if a and b and FxBudget.Allow("dkChainDust", 4) then
			local n = math.clamp(math.floor((b - a).Magnitude / 1.5), 2, 16)
			for i = 0, n do motes(a:Lerp(b, i / n), 2, 3) end
			if S.victim then motes(S.victim.Position, 12, 5) end
		end
		if S.chain then S.chain.stop() end
		if S.coil then S.coil.stop() end
	end
	if attacker then snatches[attacker] = nil end
end

local function onSnatchRelease(msg: any)
	dropSnatch(msg.attacker)
end

-- R · King of the Grave: the crater's glow.
local function ghostfireRing(g: Vector3, radius: number, life: number)
	-- A ring of icy ghostfire racing out over the floor, a darkness spreading
	-- under it that stays for the whole ult.
	local dark = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 2, 2),
		CFrame = CFrame.new(g + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = OBSIDIAN, Transparency = 0.3 })
	TweenService:Create(dark, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.06, radius * 2, radius * 2), Transparency = 0.45 }):Play()
	task.delay(life, function()
		if dark.Parent then TweenService:Create(dark, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
	end)
	Debris:AddItem(dark, life + 0.7)
	SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.4, 0)), radius = 2, arc = 359, width = 1.4, color = SPECTRAL, life = 0.5,
		draw = 0.001, grow = (radius - 2) / 2, core = FROST })
	-- flames licking up round the edge as it goes
	local holder = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(g) })
	local fire = Instance.new("ParticleEmitter")
	fire.Texture = TEX_FIRE
	fire.Color = ColorSequence.new(FROST, SPECTRAL)
	fire.LightEmission = 0.6
	fire.LightInfluence = 0
	fire.Size = NumberSequence.new({ kp(0, 1.4), kp(1, 0) })
	fire.Transparency = NumberSequence.new({ kp(0, 0.4), kp(1, 1) })
	fire.Lifetime = NumberRange.new(0.5, 0.8)
	fire.Speed = NumberRange.new(1, 2)
	fire.EmissionDirection = Enum.NormalId.Top
	fire.Acceleration = Vector3.new(0, 6, 0)
	fire.SpreadAngle = Vector2.new(15, 15)
	fire.Rate = 0
	fire.Parent = holder
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		local t = os.clock() - t0
		if t > 0.5 then
			conn:Disconnect()
			Debris:AddItem(holder, 1)
			return
		end
		local r = 2 + (radius - 2) * easeOut(t / 0.5)
		for i = 1, 10 do
			local a = math.random() * math.pi * 2
			holder.CFrame = CFrame.new(g + Vector3.new(math.cos(a) * r, 0.3, math.sin(a) * r))
			fire:Emit(1)
		end
	end)
end

-- ── The awakening ──
-- Cracks of spectral light racing out over the floor from `g`.
local function groundCracks(g: Vector3, n: number, len: number, life: number)
	for i = 1, n do
		local a = (i + math.random() * 0.5) / n * math.pi * 2
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local L = len * (0.6 + math.random() * 0.6)
		local y = Vector3.new(0, 0.06, 0)
		local seg = part({ Size = Vector3.new(0.25, 0.08, 0.1), Material = Enum.Material.Neon, Color = SPECTRAL,
			CFrame = CFrame.lookAt(g + y, g + y + d) })
		local mid = g + y + d * L / 2
		TweenService:Create(seg, TweenInfo.new(life * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.25, 0.08, L), CFrame = CFrame.lookAt(mid, mid + d) }):Play()
		task.delay(life, function()
			if seg.Parent then TweenService:Create(seg, TweenInfo.new(0.4), { Transparency = 1 }):Play() end
		end)
		Debris:AddItem(seg, life + 0.5)
	end
end

-- ── The spectral warhammer ──
-- His own maul built again GIANT times over, every piece a translucent ghost
-- of blue light (no chain links: far too many parts), moved as one.
local GIANT = 5
local HEAD_DROP = 5.2 * 0.8 * GIANT -- the handle to the head's middle (DeathKnightLook's layout)
local BUTT_UP = 8.5 * 0.8 * GIANT   -- the handle to the butt's tip
local HEAD_HALF = 1.5 * 0.8 * GIANT -- the head's half-height along the haft

type Giant = { parts: { BasePart }, rel: { CFrame }, base: { number }, cfs: { CFrame }, alpha: number,
	core: BasePart?, haft: BasePart?, butt: Vector3, alive: boolean }

local function buildGiant(): Giant
	local tool = DeathKnightLook.BuildGraveblade()
	local handle = tool:FindFirstChild("Handle") :: BasePart
	local G: Giant = { parts = {}, rel = {}, base = {}, cfs = {}, alpha = -1, core = nil, haft = nil, butt = Vector3.zero, alive = true }
	for _, d in ipairs(tool:GetChildren()) do
		if not d:IsA("BasePart") or d == handle or d.Name == "ChainLink" then continue end
		local rel = handle.CFrame:ToObjectSpace(d.CFrame)
		for _, c in ipairs(d:GetChildren()) do c:Destroy() end
		d.Anchored = true
		d.Size *= GIANT
		local glow = d.Material == Enum.Material.Neon
		if not glow then
			d.Material = Enum.Material.ForceField
			d.Color = SPECTRAL
		end
		d.CastShadow = false
		d.Transparency = 1
		d.Parent = ClassFX.Folder()
		table.insert(G.parts, d)
		table.insert(G.rel, CFrame.new(rel.Position * GIANT) * rel.Rotation)
		table.insert(G.base, if glow then 0.3 else 0)
		if d.Name == "Blade" then G.core = d end
		if d.Name == "Haft" then G.haft = d end
	end
	tool:Destroy()
	-- ghostfire pouring off the head, and souls swirling round it
	local core = G.core
	if core then
		local fire = Instance.new("ParticleEmitter")
		fire.Texture = TEX_FIRE
		fire.Color = ColorSequence.new(FROST, SPECTRAL)
		fire.LightEmission = 0.6
		fire.LightInfluence = 0
		fire.Size = NumberSequence.new({ kp(0, 6), kp(1, 0) })
		fire.Transparency = NumberSequence.new({ kp(0, 0.35), kp(1, 1) })
		fire.Lifetime = NumberRange.new(0.5, 0.9)
		fire.Speed = NumberRange.new(2, 5)
		fire.Acceleration = Vector3.new(0, 10, 0)
		fire.Rotation = NumberRange.new(0, 360)
		fire.Shape = Enum.ParticleEmitterShape.Box
		fire.Rate = 40
		fire.Parent = core
		local souls = Instance.new("ParticleEmitter")
		souls.Texture = TEX_SMOKE
		souls.Color = ColorSequence.new(FROST, SPECTRAL)
		souls.LightEmission = 0.5
		souls.LightInfluence = 0
		souls.Size = NumberSequence.new({ kp(0, 2), kp(1, 5) })
		souls.Transparency = NumberSequence.new({ kp(0, 1), kp(0.2, 0.45), kp(1, 1) })
		souls.Lifetime = NumberRange.new(1, 1.6)
		souls.Speed = NumberRange.new(8, 12)
		souls.SpreadAngle = Vector2.new(180, 180)
		souls.Drag = 2
		souls.Rotation = NumberRange.new(0, 360)
		souls.RotSpeed = NumberRange.new(-200, 200)
		souls.Rate = 14
		souls.Parent = core
	end
	return G
end

local function giantPlace(G: Giant, anchor: CFrame, alpha: number)
	for i, rel in ipairs(G.rel) do G.cfs[i] = anchor * rel end
	Workspace:BulkMoveTo(G.parts, G.cfs, Enum.BulkMoveMode.FireCFrameChanged)
	G.butt = anchor * Vector3.new(0, BUTT_UP, 0)
	if math.abs(G.alpha - alpha) > 0.02 or (alpha == 0) ~= (G.alpha == 0) then
		G.alpha = alpha
		for i, p in ipairs(G.parts) do p.Transparency = 1 - (1 - G.base[i]) * alpha end
	end
end

-- Hundreds of blue motes as it comes apart.
local function dissolve(G: Giant)
	for _, src in ipairs({ G.core, G.haft }) do
		if not src then continue end
		local s = src :: BasePart
		local holder = part({ Size = s.Size, Transparency = 1, CFrame = s.CFrame })
		local e = Instance.new("ParticleEmitter")
		e.Texture = TEX_SPARK
		e.Color = ColorSequence.new(FROST, SPECTRAL)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ kp(0, 0.7), kp(1, 0) })
		e.Lifetime = NumberRange.new(0.8, 1.5)
		e.Speed = NumberRange.new(4, 12)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 5, 0)
		e.Drag = 1.2
		e.Shape = Enum.ParticleEmitterShape.Box
		e.Rate = 0
		e.Parent = holder
		e:Emit(if s == G.core then 160 else 70)
		Debris:AddItem(holder, 1.8)
	end
end

-- Blue lightning crackling round `c`.
local function bolt(c: Vector3, reach: number)
	if not FxBudget.Allow("dkBolt", 12) then return end
	local function rnd(): Vector3
		return Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
	end
	local a, b = c + rnd() * reach * 2, c + rnd() * reach * 2
	local prev = a
	for i = 1, 4 do
		local q = if i == 4 then b else a:Lerp(b, i / 4) + rnd() * reach * 0.3
		local len = (q - prev).Magnitude
		if len > 0.05 then
			local s = part({ Size = Vector3.new(0.3, 0.3, len), Material = Enum.Material.Neon, Color = FROST, CFrame = CFrame.lookAt((prev + q) / 2, q) })
			Debris:AddItem(s, 0.09)
		end
		prev = q
	end
end

-- Air torn open round the falling hammer: a ring of wind across its path and
-- a streak along it.
local function airRing(pos: Vector3, vel: Vector3, radius: number)
	if vel.Magnitude < 1 or not FxBudget.Allow("dkAirRing", 24) then return end
	local d = vel.Unit
	-- (the arc lies in its frame's XZ plane: turned to stand across the path)
	local cf = CFrame.lookAt(pos, pos + d) * CFrame.Angles(math.pi / 2, 0, 0)
	SwordFX.Arc({ cf = cf, radius = radius, arc = 359, width = 0.6, color = FROST, life = 0.22, draw = 0.001, grow = 0.6, core = Color3.new(1, 1, 1) })
	local len = math.min(vel.Magnitude * 0.08, 14)
	local streak = part({ Size = Vector3.new(0.18, 0.18, len), Material = Enum.Material.Neon, Color = FROST, Transparency = 0.35,
		CFrame = CFrame.lookAt(pos - d * len / 2, pos) * CFrame.new(math.random() * 4 - 2, math.random() * 4 - 2, 0) })
	TweenService:Create(streak, TweenInfo.new(0.16), { Transparency = 1 }):Play()
	Debris:AddItem(streak, 0.18)
end

-- The air blown out from the impact: a shell of it racing out, rings of
-- wind skimming the floor.
local function airBlast(g: Vector3, r: number)
	local shell = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4, CFrame = CFrame.new(g + Vector3.new(0, 1, 0)),
		Material = Enum.Material.ForceField, Color = FROST, Transparency = 0 })
	TweenService:Create(shell, TweenInfo.new(0.4, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * r * 2.6, Transparency = 1 }):Play()
	Debris:AddItem(shell, 0.45)
	for i, h in ipairs({ 0.6, 3, 6.5 }) do
		task.delay((i - 1) * 0.04, function()
			SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, h, 0)), radius = 4, arc = 359, width = 1.6 - i * 0.3, color = FROST, life = 0.45,
				draw = 0.001, grow = (r * (1.3 - i * 0.12) - 4) / 4, core = Color3.new(1, 1, 1) })
		end)
	end
end

-- ── The grave awakens ──
-- A giant spectral hand: it bursts up out of the floor at `at`, palm toward
-- `face`, fingers clawing closed, then sinks back.
local function spectralHand(at: Vector3, face: Vector3, life: number, scale: number)
	local parts: { BasePart } = {}
	local rel: { CFrame } = {}
	local finger: { boolean } = {}
	local function add(size: Vector3, cf: CFrame, isFinger: boolean)
		table.insert(parts, part({ Size = size * scale, Material = Enum.Material.ForceField, Color = SPECTRAL }))
		table.insert(rel, CFrame.new(cf.Position * scale) * cf.Rotation)
		table.insert(finger, isFinger)
	end
	add(Vector3.new(1.6, 3.2, 1.2), CFrame.new(0, -1.6, 0), false)  -- the forearm
	add(Vector3.new(2.2, 2.4, 0.7), CFrame.new(0, 1.2, 0), false)   -- the palm
	for i = 1, 4 do
		-- (each finger's frame sits at its knuckle; the part runs up from it)
		add(Vector3.new(0.42, 2.2, 0.42), CFrame.new(-0.82 + (i - 1) * 0.55, 2.4, 0), true)
	end
	add(Vector3.new(0.45, 1.6, 0.45), CFrame.new(1.25, 1.1, 0) * CFrame.Angles(0, 0, math.rad(-50)), false) -- the thumb
	local base = CFrame.lookAt(at, at + Vector3.new(face.X, 0, face.Z))
	local cfs = table.create(#parts)
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local up = math.min(t / 0.35, 1)
		local down = math.clamp((t - life + 0.4) / 0.4, 0, 1)
		local h = -7 * scale * (1 - overshoot(up)) - 7 * scale * down * down
		local curl = math.rad(-70) * math.clamp((t - 0.3) / 0.5, 0, 1)
		local root = base * CFrame.new(0, h + 1.5 * scale, 0)
		for i, r in ipairs(rel) do
			cfs[i] = if finger[i] then root * r * CFrame.Angles(curl, 0, 0) * CFrame.new(0, 1.1 * scale, 0) else root * r
			if down > 0 then parts[i].Transparency = down end
		end
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if t >= life then
			conn:Disconnect()
			for _, p in ipairs(parts) do p:Destroy() end
		end
	end)
	darkSmoke(at + Vector3.new(0, 0.5, 0), 6, 2, 6, 0.8, 0.8)
end

-- The Dread mark over a body: a spectral gem turning, swelling till it bursts.
local function dreadMark(model: Model, life: number)
	local r = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not (r and r:IsA("BasePart")) then return end
	local root = r :: BasePart
	local up = model:GetExtentsSize().Y * 0.5 + 1.6
	local gem = part({ Size = Vector3.one * 0.9, Material = Enum.Material.Neon, Color = SPECTRAL })
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 2.4, 2.4), Material = Enum.Material.Neon, Color = FROST, Transparency = 0.45 })
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > life or not root.Parent then
			conn:Disconnect()
			gem:Destroy()
			ring:Destroy()
			return
		end
		local c = root.Position + Vector3.new(0, up + math.sin(t * 6) * 0.2, 0)
		local k = t / life
		gem.Size = Vector3.one * (0.9 + k * 0.7)
		gem.CFrame = CFrame.new(c) * CFrame.Angles(0, t * 4, 0) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		ring.CFrame = CFrame.new(c) * CFrame.Angles(0, t * -3, math.rad(90))
	end)
end

-- A white-blue impact frame, a blink long.
local function impactFrame()
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "DeathKnightImpact"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 50
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = Color3.new(1, 1, 1)
	f.BackgroundTransparency = 0.3
	f.Parent = gui
	gui.Parent = pg
	task.delay(0.05, function()
		TweenService:Create(f, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ BackgroundTransparency = 1, BackgroundColor3 = SPECTRAL }):Play()
	end)
	Debris:AddItem(gui, 0.45)
end

-- Blue energy erupting straight up out of the floor.
local function energyPillar(g: Vector3, h: number, w: number, delay: number)
	task.delay(delay, function()
		local turn = CFrame.Angles(0, 0, math.rad(90))
		local p = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, w, w), Material = Enum.Material.Neon, Color = SPECTRAL,
			Transparency = 0.25, CFrame = CFrame.new(g) * turn })
		TweenService:Create(p, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(h, w, w), CFrame = CFrame.new(g + Vector3.new(0, h / 2, 0)) * turn }):Play()
		task.delay(0.18, function()
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1, Size = Vector3.new(h * 1.1, w * 0.2, w * 0.2) }):Play()
			end
		end)
		Debris:AddItem(p, 0.75)
	end)
end

-- ── R · King of the Grave ──
local function onKing(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then kingPose(char) end
	local r = msg.radius :: number
	local dir = msg.dir :: Vector3
	local g = groundAt(msg.pos)
	local center = groundAt(msg.center)
	local t0 = os.clock()
	ClassFX.Sound("quake", g, 0.6, 0.6, 1.5)

	-- 1 · The awakening: the floor cracking with blue light under him, chains
	-- rising round him in a spiral, the maul's cracks blazing.
	groundCracks(g, 12, r * 0.45, KING.rise)
	darkSmoke(g + Vector3.new(0, 0.5, 0), 10, 2, 5, 1.2, 0.4)
	for k = 1, 3 do
		local a0 = k * math.pi * 2 / 3
		liveChain(function()
			local t = os.clock() - t0
			if t > KING.rise or not root.Parent then return nil, nil end
			local spin = a0 + t * 3
			local floor = groundAt(root.Position)
			local from = floor + Vector3.new(math.cos(spin) * 4.5, 0, math.sin(spin) * 4.5)
			local rise = math.min(t / 0.5, 1)
			local to = root.Position + Vector3.new(math.cos(spin + 2.2) * 3, -2.5 + rise * 5, math.sin(spin + 2.2) * 3)
			return from, to
		end, 0.2, 24)
	end
	local tool = char:FindFirstChild("Graveblade")
	if tool then
		for _, e in ipairs(tool:GetDescendants()) do
			if e:IsA("ParticleEmitter") and (e.Name == "Ghostflame" or e.Name == "Ghostwisp") then
				local was = e.Rate
				e.Rate = was * 3
				task.delay(KING.done, function() if e.Parent then e.Rate = was end end)
			end
		end
	end

	-- 3 · The ascension: the battlefield darkens.
	task.delay(KING.rise, function()
		tint("DeathKnightGraveDark", { Brightness = -0.14, Contrast = 0.15 }, KING.fade - KING.rise, 0.3, 0.6)
		if root.Parent then
			ClassFX.Sound("whoosh", root, 1, 0.4)
			darkSmoke(groundAt(root.Position) + Vector3.new(0, 0.5, 0), 12, 2.4, 9, 0.9, 0.5)
			darkShockwave(groundAt(root.Position), 7, 0.35, false)
		end
	end)

	-- 2 · The summoning: the spectral warhammer forms over him, chained to his
	-- own; it follows him up, swings over and comes down head first (4), lies
	-- in the crater (5), and comes apart (6).
	task.delay(KING.summon, function()
		if not root.Parent then return end
		ClassFX.Sound("thunder", g, 0.45, 0.5)
		ClassFX.Sound("quake", g, 0.7, 0.5, 2)
		local G = buildGiant()
		local yaw = CFrame.lookAt(Vector3.zero, dir)
		local hx = Vector3.new(center.X, g.Y, center.Z)
		local summonUp = BUTT_UP + 4
		-- (it lands tipped over sideways, the head buried a little on the spot)
		local slant = yaw * CFrame.Angles(0, 0, math.rad(KING_SLANT))
		local headAt = hx + Vector3.new(0, HEAD_HALF - 2, 0)
		local downAt = headAt - slant:VectorToWorldSpace(Vector3.new(0, -HEAD_DROP, 0))
		local lastHead: Vector3? = nil
		local chain = liveChain(function()
			if not G.alive or os.clock() - t0 > KING.fade then return nil, nil end
			local tip = bladeTip(char)
			if not tip or G.alpha <= 0 then return nil, nil end
			return tip, G.butt
		end, 0.25, 60)
		local lastBolt = 0
		local dissolved = false
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			local anchor: CFrame
			local alpha = 1
			if t < KING.rise then
				local a = math.clamp((t - KING.summon) / (KING.rise - KING.summon), 0, 1)
				anchor = CFrame.new(hx + Vector3.new(0, summonUp - 8 * (1 - easeOut(a)), 0)) * yaw
					* CFrame.Angles(0, math.rad(40) * (1 - a), 0) * CFrame.Angles(math.pi, 0, 0)
				alpha = easeOut(a)
			elseif t < KING.fall then
				local a = (t - KING.rise) / (KING.fall - KING.rise)
				anchor = CFrame.new(hx + Vector3.new(0, summonUp + KING_HIGH * easeOut(a), 0)) * yaw * CFrame.Angles(math.pi, 0, 0)
			elseif t < KING.impact then
				-- (swung over forward and tipped over sideways, head first, down
				-- onto the spot, tearing the air open round it)
				local a = easeIn((t - KING.fall) / (KING.impact - KING.fall))
				local top = hx + Vector3.new(0, summonUp + KING_HIGH, 0)
				anchor = CFrame.new(top:Lerp(downAt, a)) * yaw * CFrame.Angles(0, 0, math.rad(KING_SLANT) * a)
					* CFrame.Angles(math.pi * (1 - a), 0, 0)
				local head = anchor * Vector3.new(0, -HEAD_DROP, 0)
				if lastHead then airRing(head, (head - (lastHead :: Vector3)) / math.max(1 / 60, 0.001), 9) end
				lastHead = head
			elseif t < KING.fade then
				anchor = CFrame.new(downAt) * slant
			else
				local a = math.clamp((t - KING.fade) / (KING.done - KING.fade), 0, 1)
				anchor = CFrame.new(downAt + Vector3.new(0, a * 3, 0)) * slant
				alpha = 1 - a
				if not dissolved then
					dissolved = true
					dissolve(G)
				end
			end
			giantPlace(G, anchor, alpha)
			if t < KING.impact and t - lastBolt > 0.12 and G.core then
				lastBolt = t
				bolt((G.core :: BasePart).Position, 12)
			end
			if t >= KING.done then
				conn:Disconnect()
				G.alive = false
				chain.stop()
				for _, p in ipairs(G.parts) do p:Destroy() end
			end
		end)
	end)
end

local function onKingBind(msg: any)
	local hold = tonumber(msg.hold) or 1
	local shown = 0
	for _, m in ipairs(msg.models or {}) do
		if typeof(m) == "Instance" and m:IsA("Model") and m.Parent then
			-- (budgeted: a room full of mobs gets chains on the first dozen)
			if shown < 12 then
				shown += 1
				bindingChains(m, hold)
			end
		end
	end
	ClassFX.Sound("rockHit", msg.pos, 0.8, 0.5)
end

-- 4 · The execution.
local function onKingFinal(msg: any)
	local g = groundAt(msg.pos)
	local r = msg.radius :: number
	if near(g, 90) then impactFrame() end
	airBlast(g, r)
	roundCrater(g, r * 0.2, r * 0.7, 4, 9)
	-- (the crater glowing with blue necromantic energy till it's over)
	ghostfireRing(g, r * 0.8, KING.fade - KING.impact + 0.3)
	darkShockwave(g, r, 0.6)
	task.delay(0.08, darkShockwave, g, r * 1.3, 0.8, false)
	SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.5, 0)), radius = 3, arc = 359, width = 2, color = SPECTRAL, life = 0.5,
		draw = 0.001, grow = (r * 1.2 - 3) / 3, core = FROST })
	smokeRing(g + Vector3.new(0, 1, 0), 90, 4, r * 2.2, 0.9)
	darkSmoke(g + Vector3.new(0, 2, 0), 26, 4.5, 14, 1.6, 1.5)
	energyPillar(g, 70, 9, 0)
	for i = 1, 9 do
		local a = math.random() * math.pi * 2
		local d = r * (0.2 + math.random() * 0.5)
		energyPillar(groundAt(g + Vector3.new(math.cos(a) * d, 3, math.sin(a) * d)), 25 + math.random() * 30, 1.5 + math.random() * 2, 0.03 + math.random() * 0.2)
	end
	shards(g, r * 0.6, 22, 2, 5, 1.2)
	rocks(g + Vector3.new(0, 0.5, 0), 16, 34, 34)
	motes(g + Vector3.new(0, 2, 0), 30, 30)
	-- chains bursting out of the impact
	for _ = 1, 12 do
		local l = chainLink()
		local d = Vector3.new(math.random() - 0.5, 0, math.random() - 0.5)
		d = if d.Magnitude > 0.05 then d.Unit else Vector3.xAxis
		local to = g + d * r * (0.3 + math.random() * 0.4) + Vector3.new(0, 4 + math.random() * 8, 0)
		l.Size *= 3
		l.CFrame = CFrame.new(g + Vector3.new(0, 1, 0))
		TweenService:Create(l, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = CFrame.new(to) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 0.7 }):Play()
		Debris:AddItem(l, 0.65)
	end
	ClassFX.Sound("quake", g, 1, 0.7, 2)
	ClassFX.Sound("boom", g, 1, 0.55)
	ClassFX.Sound("thunder", g, 0.4, 0.6)
	if msg.attacker == player then
		deps.shake(1.8, 0.5)
		deps.fovPunch(12, 0.4)
	elseif near(g, 80) then
		deps.shake(0.8, 0.3)
	end
	-- 5 · The grave awakens: giant spectral hands clawing up round the crater.
	task.delay(0.15, function()
		for k = 1, 4 do
			local a = k * math.pi / 2 + math.random() * 0.6
			local at = groundAt(g + Vector3.new(math.cos(a), 0, math.sin(a)) * r * 0.55 + Vector3.new(0, 3, 0))
			spectralHand(at, g - at, KING.fade - KING.impact - 0.1, 2.4)
		end
	end)
end

-- 5 · Chains drag what's left into the crater, each marked with Dread.
local function onKingDrag(msg: any)
	local hold = tonumber(msg.hold) or 0.9
	local from = groundAt(msg.pos)
	local shown = 0
	for _, m in ipairs(msg.models or {}) do
		if not (typeof(m) == "Instance" and m:IsA("Model") and m.Parent) then continue end
		if shown >= 10 then break end
		shown += 1
		local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		if r and r:IsA("BasePart") then
			local rp = r :: BasePart
			local t0 = os.clock()
			liveChain(function()
				if os.clock() - t0 > hold or not rp.Parent then return nil, nil end
				return from, rp.Position
			end, 0.1, 40)
		end
		dreadMark(m, hold + 0.05)
	end
	ClassFX.Sound("whoosh", msg.pos, 0.8, 0.45)
end

-- ...and the marks burst: blue soul explosions.
local function onKingBurst(msg: any)
	for _, m in ipairs(msg.models or {}) do
		if not (typeof(m) == "Instance" and m:IsA("Model")) then continue end
		local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
		if not (r and r:IsA("BasePart")) or not FxBudget.Allow("dkSoulBurst", 20) then continue end
		local p = (r :: BasePart).Position
		local flash = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(p), Material = Enum.Material.Neon,
			Color = FROST, Transparency = 0.2 })
		TweenService:Create(flash, TweenInfo.new(0.25, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = Vector3.one * 9, Transparency = 1, Color = SPECTRAL }):Play()
		Debris:AddItem(flash, 0.3)
		motes(p, 10, 18)
		darkSmoke(p, 6, 2, 8, 0.8, 0.6)
		ClassFX.Sound("boom", p, 0.5, 0.9)
	end
end

-- 6 · The aftermath (the hammer comes apart on its own timeline: onKing).
local function onKingEnd(msg: any)
	local g = groundAt(msg.pos)
	darkSmoke(g + Vector3.new(0, 1, 0), 10, 3, 4, 1.4, 0.6)
	ClassFX.Sound("whoosh", g, 0.6, 0.35)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Dread: the look (every Death Knight, every client) and the meter
-- ═════════════════════════════════════════════════════════════════════════════
type Look = { char: Model, tool: Instance?, owned: { Instance }, nextPulse: number }
local looks: { [Player]: Look } = {}

local function mistOf(char: Model): { ParticleEmitter }
	local out = {}
	local plate = char:FindFirstChild("SoulReaperPlate")
	if plate then
		for _, d in ipairs(plate:GetDescendants()) do
			if d:IsA("ParticleEmitter") and d.Name == DeathKnightLook.MIST then table.insert(out, d) end
		end
	end
	return out
end

local function dropLook(L: Look)
	for _, x in ipairs(L.owned) do x:Destroy() end
	if L.char.Parent then
		for _, e in ipairs(mistOf(L.char)) do
			local base = e:GetAttribute("BaseRate")
			if typeof(base) == "number" then e.Rate = base end
		end
	end
end

-- Dreadforged: icy ghostfire up the blade, a spectral sheath round it (the
-- blade bigger and brighter), the plate's mist thick and roiling.
local function buildLook(char: Model): Look
	local L: Look = { char = char, tool = nil, owned = {}, nextPulse = 0 }
	local tool = char:FindFirstChild("Graveblade")
	local blade = tool and tool:FindFirstChild("Blade")
	if blade and blade:IsA("BasePart") then
		L.tool = tool
		local fire = Instance.new("ParticleEmitter")
		fire.Name = "Ghostfire"
		fire.Texture = TEX_FIRE
		fire.Color = ColorSequence.new(FROST, SPECTRAL)
		fire.LightEmission = 0.55
		fire.LightInfluence = 0
		fire.Size = NumberSequence.new({ kp(0, 0.75), kp(1, 0) })
		fire.Transparency = NumberSequence.new({ kp(0, 0.35), kp(1, 1) })
		fire.Lifetime = NumberRange.new(0.3, 0.55)
		fire.Speed = NumberRange.new(0.4, 1.2)
		fire.Acceleration = Vector3.new(0, 5, 0)
		fire.Shape = Enum.ParticleEmitterShape.Box
		fire.Rate = 30
		fire.Parent = blade
		table.insert(L.owned, fire)
		-- the sheath: a ghost of the blade, a size bigger, shimmering
		local sheath = Instance.new("Part")
		sheath.Name = "SpectralSheath"
		sheath.Size = blade.Size * Vector3.new(1.16, 1.06, 1.6) + Vector3.new(0.12, 0.2, 0.08)
		sheath.Material = Enum.Material.ForceField
		sheath.Color = SPECTRAL
		sheath.Transparency = 0.25
		sheath.CanCollide, sheath.CanQuery, sheath.CanTouch, sheath.Massless, sheath.CastShadow = false, false, false, true, false
		sheath.CFrame = blade.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = blade, sheath
		w.Parent = sheath
		sheath.Parent = tool
		table.insert(L.owned, sheath)
	end
	for _, e in ipairs(mistOf(char)) do
		local base = e:GetAttribute("BaseRate")
		if typeof(base) == "number" then e.Rate = base * 2.6 end
	end
	return L
end

local function refreshLook(p: Player)
	local char = p.Character
	local L = looks[p]
	local want = char ~= nil and isDK(p) and dreadLeft(p) > 0
	-- (rebuilt for a new body, or once the weapon is back in hand)
	if L and (not want or L.char ~= char or (L.tool == nil and char and char:FindFirstChild("Graveblade"))
		or (L.tool ~= nil and not (L.tool :: Instance):IsDescendantOf(L.char))) then
		dropLook(L)
		looks[p] = nil
		L = nil
	end
	if want and not L and char then
		looks[p] = buildLook(char)
	end
end

-- Faint spectral shockwaves pulsing round his plate while Dreadforged.
local function dreadStep(now: number)
	for p, L in pairs(looks) do
		if now < L.nextPulse then continue end
		L.nextPulse = now + 1.3
		local root = rootOf(L.char)
		if root and FxBudget.Allow("dkPulse", 4) then
			local g = groundAt(root.Position)
			SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.3, 0)), radius = 2.4, arc = 359, width = 0.32, color = SPECTRAL, life = 0.5,
				draw = 0.001, grow = 1.1, core = FROST })
		end
		if not p.Parent then
			dropLook(L)
			looks[p] = nil
		end
	end
end

-- Dreadforged begins: a burst of spectral force off him.
local function onDread(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local g = groundAt(root.Position)
	SwordFX.Arc({ cf = CFrame.new(g + Vector3.new(0, 0.5, 0)), radius = 3, arc = 359, width = 1, color = SPECTRAL, life = 0.5, draw = 0.001,
		grow = 3, core = FROST })
	smokeRing(g + Vector3.new(0, 0.8, 0), 36, 2, 26, 0.6)
	motes(root.Position, 20, 14)
	ClassFX.Sound("whoosh", root, 0.5, 0.45)
	ClassFX.Sound("boom", root, 0.5, 1.2)
	pcall(refreshLook, msg.attacker)
	if msg.attacker == player then
		deps.shake(0.6, 0.2)
		tint("DreadForged", { Saturation = -0.3, Contrast = 0.15, TintColor = Color3.fromRGB(205, 225, 245) }, 0.35, 0.08, 0.5)
	end
end

-- ── The meter ───────────────────────────────────────────────────────────────
local hud: ScreenGui? = nil
local fill: Frame? = nil
local label: TextLabel? = nil
local dreadFor = DREAD_TIME

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "DeathKnightDread"
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
	back.BackgroundColor3 = OBSIDIAN
	back.BorderSizePixel = 0
	back.Parent = g
	local s = Instance.new("UIStroke")
	s.Color = ASH
	s.Thickness = 1.5
	s.Parent = back
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(0, 1)
	f.BackgroundColor3 = STEEL
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
	l.TextColor3 = FROST
	l.TextStrokeTransparency = 0.2
	l.Text = ""
	l.Parent = back
	label = l
end

local function refreshHud()
	if not hud then return end
	local left = dreadLeft(player)
	local dread = dreadOf(player)
	hud.Enabled = isDK() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	if fill then
		fill.Size = UDim2.fromScale(if left > 0 then math.clamp(left / dreadFor, 0, 1) else math.clamp(dread / DREAD_MAX, 0, 1), 1)
		fill.BackgroundColor3 = if left > 0 then SPECTRAL else STEEL
	end
	if label then
		label.Text = if left > 0 then "DREADFORGED" else `DREAD {math.floor(dread)}`
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
local HANDLERS: { [string]: (any) -> () } = {
	combo = onCombo,
	smash = onSmash,
	dreadWave = onDreadWave,
	blackwake = onBlackwake,
	doomfall = onDoomfall,
	doomImpact = onDoomImpact,
	snatch = onSnatch,
	snatchSlam = onSnatchSlam,
	snatchRelease = onSnatchRelease,
	king = onKing,
	kingBind = onKingBind,
	kingFinal = onKingFinal,
	kingDrag = onKingDrag,
	kingBurst = onKingBurst,
	kingEnd = onKingEnd,
	dread = function(msg: any)
		if msg.attacker == player then dreadFor = tonumber(msg.seconds) or DREAD_TIME end
		onDread(msg)
	end,
}

-- ═════════════════════════════════════════════════════════════════════════════
-- The maul's lightning (every Death Knight's, every client)
-- ═════════════════════════════════════════════════════════════════════════════
-- Thin, jagged, unstable bolts crawling over the head: jumping between its
-- spikes, edges and plates with white-blue flashes where they touch; now and
-- then a bigger discharge out into the flames; small arcs running down the
-- haft. Pooled beams on attachments in the head (nothing is made or destroyed
-- while it runs), budgeted, and only near the camera.
local ARC_POOL = 7
local ARC_SEGS = 5
local ARC_RANGE = 140
local ARC_RATE = 10 -- bolts a second per idle slot
local ARC_WHITE = Color3.fromRGB(235, 250, 255)
local ARC_BLUE = Color3.fromRGB(70, 190, 255)
type Arc = { at: { Attachment }, beams: { Beam }, flashes: { ParticleEmitter }, live: boolean, ends: number, jolt: number,
	from: Vector3, to: Vector3, amp: number }
type ArcSet = { core: BasePart, anchors: { Vector3 }, haftA: Vector3, haftB: Vector3, arcs: { Arc } }
local arcSets: { [Tool]: ArcSet } = {}

local function newArcSet(tool: Tool): ArcSet?
	local core = tool:FindFirstChild("Blade", true)
	if not (core and core:IsA("BasePart")) then return nil end
	local cf = core.CFrame
	-- where bolts land: the spikes, the striking faces' corners, the blocks' edges
	local anchors: { Vector3 } = {}
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and (d.Name == "HeadSpike" or d.Name == "FaceSpike" or d.Name == "HeadBlock" or d.Name == "Face") then
			local p = cf:PointToObjectSpace(d.Position)
			if d.Name == "HeadBlock" then p = p * 1.15 end -- (out at its outer edge)
			table.insert(anchors, p)
		end
	end
	if #anchors < 2 then return nil end
	local haft = tool:FindFirstChild("Haft", true) :: BasePart?
	local haftA, haftB = Vector3.zero, Vector3.zero
	if haft then
		local up = haft.CFrame.UpVector * haft.Size.Y / 2
		haftA, haftB = cf:PointToObjectSpace(haft.Position + up * 0.9), cf:PointToObjectSpace(haft.Position - up * 0.9)
		-- (the end nearer the head first)
		if haftB.Magnitude < haftA.Magnitude then haftA, haftB = haftB, haftA end
	end
	local arcs: { Arc } = {}
	for _ = 1, ARC_POOL do
		local at, beams, flashes = {}, {}, {}
		for i = 1, ARC_SEGS do
			local a = Instance.new("Attachment")
			a.Name = "Arc"
			a.Parent = core
			at[i] = a
			if i > 1 then
				local b = Instance.new("Beam")
				b.Attachment0, b.Attachment1 = at[i - 1], a
				b.Color = ColorSequence.new(ARC_WHITE, ARC_BLUE)
				b.LightEmission = 1
				b.LightInfluence = 0
				b.Brightness = 4
				b.Transparency = NumberSequence.new(0)
				b.FaceCamera = true
				b.Segments = 1
				b.Width0, b.Width1 = 0.09, 0.06
				b.Enabled = false
				b.Parent = core
				table.insert(beams, b)
			end
		end
		for _, i in ipairs({ 1, ARC_SEGS }) do
			local e = Instance.new("ParticleEmitter")
			e.Texture = TEX_SPARK
			e.Color = ColorSequence.new(ARC_WHITE, ARC_BLUE)
			e.LightEmission = 1
			e.LightInfluence = 0
			e.Size = NumberSequence.new({ kp(0, 0.7), kp(1, 0) })
			e.Transparency = NumberSequence.new(0)
			e.Lifetime = NumberRange.new(0.06, 0.1)
			e.Speed = NumberRange.new(0)
			e.Rate = 0
			e.LockedToPart = true
			e.Parent = at[i]
			table.insert(flashes, e)
		end
		table.insert(arcs, { at = at, beams = beams, flashes = flashes, live = false, ends = 0, jolt = 0,
			from = Vector3.zero, to = Vector3.zero, amp = 0 })
	end
	return { core = core, anchors = anchors, haftA = haftA, haftB = haftB, arcs = arcs }
end

-- (a jagged line from `from` to `to`, kinked off it by up to `amp`)
local function shapeArc(arc: Arc)
	local d = arc.to - arc.from
	local side = d:Cross(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5))
	side = if side.Magnitude > 1e-3 then side.Unit else Vector3.xAxis
	local side2 = d.Unit:Cross(side)
	for i = 1, ARC_SEGS do
		local f = (i - 1) / (ARC_SEGS - 1)
		local kink = if i == 1 or i == ARC_SEGS then Vector3.zero
			else (side * (math.random() * 2 - 1) + side2 * (math.random() * 2 - 1)) * arc.amp
		arc.at[i].Position = arc.from + d * f + kink
	end
end

local function fireArc(set: ArcSet, arc: Arc, now: number)
	local A = set.anchors
	local roll = math.random()
	local width = 0.09
	if roll < 0.1 and set.haftA ~= set.haftB then
		-- a small arc running down the haft
		local f = math.random() * 0.6
		arc.from = set.haftA:Lerp(set.haftB, f)
		arc.to = set.haftA:Lerp(set.haftB, f + 0.15 + math.random() * 0.2)
		arc.amp = 0.12
		width = 0.06
	elseif roll < 0.25 then
		-- a bigger discharge, branching out into the aura
		local p = A[math.random(#A)]
		local out = if p.Magnitude > 1e-3 then p.Unit else Vector3.yAxis
		arc.from = p
		arc.to = p + (out + Vector3.new(math.random() - 0.5, math.random() * 0.6, math.random() - 0.5)).Unit * (1.4 + math.random() * 1.4)
		arc.amp = 0.35
		width = 0.13
	else
		-- crawling across the metal, spike to spike, edge to edge
		local p = A[math.random(#A)]
		local q = A[math.random(#A)]
		for _ = 1, 4 do
			local dq = (q - p).Magnitude
			if dq > 0.6 and dq < 3.2 then break end
			q = A[math.random(#A)]
		end
		arc.from, arc.to = p, q
		arc.amp = math.clamp((q - p).Magnitude * 0.16, 0.08, 0.4)
	end
	shapeArc(arc)
	for _, b in ipairs(arc.beams) do
		b.Width0, b.Width1 = width, width * 0.7
		b.Enabled = true
	end
	for _, e in ipairs(arc.flashes) do e:Emit(1) end
	arc.live = true
	local life = 0.05 + math.random() * 0.09
	arc.ends = now + life
	arc.jolt = now + life * 0.5
end

local function hideArcs(set: ArcSet)
	for _, arc in ipairs(set.arcs) do
		if arc.live then
			arc.live = false
			for _, b in ipairs(arc.beams) do b.Enabled = false end
		end
	end
end

local function arcStep(dt: number)
	local now = os.clock()
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local seen: { [Tool]: boolean } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local tool = char and char:FindFirstChild("Graveblade")
		if not (tool and tool:IsA("Tool")) then continue end
		seen[tool] = true
		local set = arcSets[tool]
		if not set then
			set = newArcSet(tool)
			if not set then continue end
			arcSets[tool] = set
		end
		local S = set :: ArcSet
		if not S.core.Parent or (S.core.Position - camPos).Magnitude > ARC_RANGE then
			hideArcs(S)
			continue
		end
		for _, arc in ipairs(S.arcs) do
			if arc.live then
				if now >= arc.ends then
					arc.live = false
					for _, b in ipairs(arc.beams) do b.Enabled = false end
				elseif now >= arc.jolt then
					-- (it flickers: kinked again once before it dies)
					arc.jolt = math.huge
					shapeArc(arc)
				end
			elseif math.random() < ARC_RATE * dt and FxBudget.Allow("dkMaulArc", 120) then
				fireArc(S, arc, now)
			end
		end
	end
	for tool in pairs(arcSets) do
		if not seen[tool] or not tool.Parent then
			if tool.Parent then hideArcs(arcSets[tool]) end
			arcSets[tool] = nil
		end
	end
end

function DeathKnightController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	for _, a in ipairs({ "DK_Dread", "DK_DreadUntil", "SelectedClass", "InLobby", "SettingsOpen" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshHud)
	end
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localStep = 0
		m1Mover = nil
		if snatchMover then
			snatchMover.stop(false)
			snatchMover = nil
		end
		if kingMover then
			kingMover.stop(false)
			kingMover = nil
		end
	end)
	RunService.Heartbeat:Connect(function()
		dreadStep(os.clock())
		-- (the meter drains while Dreadforged)
		if hud and hud.Enabled and fill and dreadLeft(player) > 0 then
			fill.Size = UDim2.fromScale(math.clamp(dreadLeft(player) / dreadFor, 0, 1), 1)
		end
	end)
	-- Both hands on the Graveblade: the idle hold, then the two-handed grip
	-- kept on whatever pose is playing.
	CastPoses.addPostHook(function(dt)
		holdStep(dt)
		twoHandStep(dt)
	end)
	RunService.Heartbeat:Connect(function(dt)
		local ok, err = pcall(arcStep, dt)
		if not ok then warn("[DeathKnightController] arcs", err) end
	end)
	task.spawn(function()
		while true do
			task.wait(0.25)
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(refreshLook, p)
				if not ok then warn("[DeathKnightController] look", err) end
			end
			for p, L in pairs(looks) do
				if not p.Parent then
					dropLook(L)
					looks[p] = nil
				end
			end
			-- (Dreadforged running out: back to the meter)
			if hud and hud.Enabled then refreshHud() end
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.DeathKnightFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[DeathKnightController]", msg.kind, err) end
		end
	end)
end

-- The pose functions, for previews and tests (they pose any character model).
DeathKnightController.Poses = {
	swing = swingPose,
	blackwake = blackwakePose,
	doom = doomPose,
	thrust = thrustPose,
	king = kingPose,
}

return DeathKnightController
