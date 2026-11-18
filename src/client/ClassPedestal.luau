--!strict
--[[
	ClassPedestal.luau
	Class select: the round stone dais the menu hero stands on, its glowing
	rings in the class's colours, and an aura of the class's own effects
	around the hero and the dais (embers for the Fire Knight, sword-light and
	ink for the Ronin, frost for the Ice Mage, ...).

	  ClassPedestal.Show(hero, classId, locked)  lifts the hero onto the dais
	  ClassPedestal.Hide()                       takes it all away again

	Menu only: one dais, a handful of emitters and three orbiting wisps.
	Emission rates shrink with FxBudget's frame pressure when shown.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClassData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassData"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local ClassPedestal = {}

local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_GLOW = "rbxasset://textures/particles/forcefield_glow_main.dds"

local LIFT = 1.25 -- dais height (the hero is raised by this)
local R_BASE = 4.7 -- lower step radius
local R_TOP = 3.6 -- upper step radius
local STONE = Color3.fromRGB(34, 30, 33)
local STONE_TOP = Color3.fromRGB(44, 38, 40)
local LOCKED = Color3.fromRGB(110, 110, 118)

-- ── Small builders ─────────────────────────────────────────────────────────
local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- A flat disc (a cylinder on its side) centred at `at`, `h` tall.
local function disc(parent: Instance, at: Vector3, r: number, h: number, color: Color3, material: Enum.Material): BasePart
	return part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, r * 2, r * 2),
		CFrame = CFrame.new(at) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	})
end

local function seq(...: number): NumberSequence
	local a = { ... }
	local keys = {}
	for i = 1, #a, 2 do table.insert(keys, NumberSequenceKeypoint.new(a[i], a[i + 1])) end
	return NumberSequence.new(keys)
end

local function cseq(a: Color3, b: Color3?): ColorSequence
	return if b then ColorSequence.new(a, b) else ColorSequence.new(a)
end

-- ── Effect presets (each returns ParticleEmitter properties) ───────────────
type Spec = { at: string, props: { [string]: any } }

-- Sparks rising off the dais.
local function embers(c1: Color3, c2: Color3, rate: number): Spec
	return { at = "base", props = {
		Texture = TEX_SPARK, Color = cseq(c2, c1), LightEmission = 1,
		Size = seq(0, 0.42, 0.6, 0.28, 1, 0), Transparency = seq(0, 0, 0.8, 0.2, 1, 1),
		Lifetime = NumberRange.new(1.4, 2.6), Speed = NumberRange.new(2, 4.5),
		Acceleration = Vector3.new(0, 2.5, 0), SpreadAngle = Vector2.new(25, 25),
		RotSpeed = NumberRange.new(-120, 120), Rate = rate,
	} }
end

-- Flames licking up round the ring.
local function flames(c1: Color3, c2: Color3, rate: number): Spec
	return { at = "ring", props = {
		Texture = TEX_FIRE, Color = cseq(c2, c1), LightEmission = 0.9,
		Size = seq(0, 1.3, 0.5, 0.9, 1, 0), Transparency = seq(0, 0.15, 0.7, 0.45, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(12, 12), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-60, 60), Rate = rate,
	} }
end

-- Smoke or ink rolling off the dais. `glow` 0 keeps it dark (ink).
local function smoke(c: Color3, rate: number, glow: number, alpha: number): Spec
	return { at = "ring", props = {
		Texture = TEX_SMOKE, Color = cseq(c), LightEmission = glow, LightInfluence = if glow > 0 then 0 else 0.4,
		Size = seq(0, 1.2, 1, 3.2), Transparency = seq(0, 1, 0.15, alpha * 0.8, 1, 1),
		Lifetime = NumberRange.new(2, 3.2), Speed = NumberRange.new(0.4, 1.2),
		Acceleration = Vector3.new(0, 0.6, 0), SpreadAngle = Vector2.new(50, 50),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-25, 25), Rate = rate,
	} }
end

-- Thin streaks of light flicking out from the hero (sword-light, glints).
local function streaks(c1: Color3, c2: Color3, rate: number): Spec
	return { at = "body", props = {
		Texture = TEX_GLOW, Color = cseq(c2, c1), LightEmission = 1,
		Size = seq(0, 0.9, 1, 0.15), Squash = seq(0, 3.5, 1, 3.5), Transparency = seq(0, 0, 1, 1),
		Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.35, 0.6), Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(180, 180), Rate = rate,
	} }
end

-- Slow motes drifting round the hero (sparkle, snow, leaves).
local function motes(c1: Color3, c2: Color3, rate: number, fall: number?): Spec
	return { at = "body", props = {
		Texture = TEX_SPARK, Color = cseq(c1, c2), LightEmission = 1,
		Size = seq(0, 0, 0.2, 0.36, 1, 0), Transparency = seq(0, 0.1, 1, 1),
		Lifetime = NumberRange.new(1.8, 3), Speed = NumberRange.new(0.3, 1.2),
		Acceleration = Vector3.new(0, fall or 0.6, 0), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), Rate = rate,
	} }
end

-- Soft glowing wisps rising (souls, light).
local function wisps(c: Color3, rate: number): Spec
	return { at = "base", props = {
		Texture = TEX_GLOW, Color = cseq(c), LightEmission = 1,
		Size = seq(0, 0, 0.3, 1.4, 1, 0), Transparency = seq(0, 0, 1, 1),
		Lifetime = NumberRange.new(1.6, 2.6), Speed = NumberRange.new(1.5, 3),
		SpreadAngle = Vector2.new(20, 20), Rate = rate,
	} }
end

-- The class's energy licking up round the hero's outline (every class).
local function auraFlame(c: Color3, rate: number): Spec
	return { at = "body", props = {
		Texture = TEX_FIRE, Color = cseq(c:Lerp(Color3.new(1, 1, 1), 0.25), c), LightEmission = 1,
		Size = seq(0, 1.6, 1, 0.2), Transparency = seq(0, 0.35, 0.5, 0.55, 1, 1),
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(0.6, 1.4),
		Acceleration = Vector3.new(0, 2, 0), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Top,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-50, 50), Rate = rate,
	} }
end

-- Dark ink curling up off the hero.
local function ink(c: Color3, rate: number): Spec
	return { at = "body", props = {
		Texture = TEX_SMOKE, Color = cseq(c), LightEmission = 0, LightInfluence = 0.3,
		Size = seq(0, 0.5, 1, 2.2), Transparency = seq(0, 1, 0.2, 0.2, 1, 1),
		Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(0.4, 1.4),
		Acceleration = Vector3.new(0, 1.4, 0), SpreadAngle = Vector2.new(180, 180),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-40, 40), Rate = rate,
	} }
end

type Orbit = { n: number, color: Color3, radius: number, speed: number, width: number, life: number }
-- `slashes`: crescents of sword-light cut the air round the hero now and then.
type Theme = { specs: { Spec }, orbit: Orbit?, slashes: Color3? }

local function themeFor(classId: string, c1: Color3, c2: Color3): Theme
	local W = Color3.new(1, 1, 1)
	if classId == "heavy_knight" then
		return { specs = { embers(c1, c2, 70), flames(c1, c2, 12), motes(c1, c2, 14, 2) },
			orbit = { n = 2, color = c1, radius = 2.6, speed = 1.6, width = 0.35, life = 0.5 } }
	elseif classId == "ronin" then
		return { specs = { streaks(c1, W, 26), smoke(c2, 9, 0, 0.2), ink(c2, 10), motes(c1, W, 14, 0.3) },
			orbit = { n = 3, color = c1, radius = 2.4, speed = 2.6, width = 0.22, life = 0.4 }, slashes = c1 }
	elseif classId == "berserker" then
		return { specs = { smoke(Color3.fromRGB(90, 8, 14), 6, 0, 0.35), embers(c1, c2, 30), streaks(c1, c2, 6) },
			orbit = { n = 2, color = c1, radius = 2.6, speed = 1.8, width = 0.3, life = 0.45 } }
	elseif classId == "mage" then
		return { specs = { motes(c1, c2, 22, 0.8), wisps(c1, 10), smoke(c1, 3, 0.6, 0.75) },
			orbit = { n = 3, color = c1, radius = 2.5, speed = 1.3, width = 0.2, life = 0.6 } }
	elseif classId == "rogue" then
		return { specs = { smoke(c2, 8, 0, 0.3), streaks(c1, W, 8), motes(c1, c1, 8, 0.4) },
			orbit = { n = 2, color = c1, radius = 2.3, speed = 2.4, width = 0.16, life = 0.35 } }
	elseif classId == "martial_artist" then
		return { specs = { flames(c1, c2, 9), streaks(c2, W, 10), embers(c1, c2, 20) },
			orbit = { n = 2, color = c1, radius = 2.4, speed = 2.2, width = 0.25, life = 0.4 } }
	elseif classId == "summoner" then
		return { specs = { wisps(c1, 10), motes(c2, c1, 16, 0.5), smoke(c1, 3, 0.5, 0.8) },
			orbit = { n = 3, color = c1, radius = 2.8, speed = 1.2, width = 0.22, life = 0.6 } }
	elseif classId == "death_knight" then
		return { specs = { smoke(c2, 9, 0, 0.2), flames(c1, W, 12), wisps(c1, 12), motes(c1, W, 10, 1) },
			orbit = { n = 2, color = c1, radius = 2.6, speed = 1.4, width = 0.25, life = 0.55 } }
	elseif classId == "ranger" then
		return { specs = { motes(c1, c2, 18, -0.4), smoke(Color3.fromRGB(70, 160, 70), 4, 0.3, 0.7), wisps(c2, 5) },
			orbit = { n = 2, color = c1, radius = 2.5, speed = 1.5, width = 0.2, life = 0.5 } }
	elseif classId == "cleric" then
		return { specs = { wisps(c1, 14), motes(c2, c1, 16, 0.8), embers(c1, c2, 12) },
			orbit = { n = 3, color = c1, radius = 2.6, speed = 1.1, width = 0.25, life = 0.6 } }
	elseif classId == "ice_mage" then
		return { specs = { motes(W, c1, 26, -1.2), smoke(c2, 5, 0.4, 0.6), streaks(c1, W, 6) },
			orbit = { n = 2, color = c1, radius = 2.5, speed = 1.3, width = 0.22, life = 0.55 } }
	elseif classId == "gunslinger" then
		return { specs = { embers(c1, c2, 26), streaks(c1, c2, 8), smoke(Color3.fromRGB(120, 90, 60), 3, 0, 0.6) },
			orbit = { n = 2, color = c1, radius = 2.5, speed = 1.9, width = 0.2, life = 0.4 } }
	elseif classId == "swordsman" then
		return { specs = { streaks(c1, W, 18), motes(c1, c2, 14, 0.5), wisps(c1, 5) },
			orbit = { n = 3, color = c1, radius = 2.4, speed = 2.2, width = 0.18, life = 0.35 }, slashes = c1 }
	end
	return { specs = { motes(c1, c2, 16, 0.6), wisps(c1, 6) } }
end

-- ── State ──────────────────────────────────────────────────────────────────
type State = {
	model: Model,
	center: Vector3, -- dais top centre
	hero: Model,
	heroBase: CFrame,
	glow: { BasePart }, -- neon rings recoloured per class
	spinner: BasePart, -- rune ring centre (welded links ride on it)
	auraParts: { Instance }, -- per-class emitters and wisps (cleared per class)
	orbiters: { { part: BasePart, phase: number } },
	orbit: Orbit?,
	conn: RBXScriptConnection?,
	locked: boolean,
	slashes: Color3?,
	nextSlash: number,
}
local state: State? = nil

local function groundOf(hero: Model): Vector3?
	local root = hero:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = hero:FindFirstChildOfClass("Humanoid")
	if not root or not hum then return nil end
	local lift = if hum.RigType == Enum.HumanoidRigType.R6 then root.Size.Y / 2 + 2 else hum.HipHeight + root.Size.Y / 2
	return root.Position - Vector3.new(0, lift, 0)
end

local function build(hero: Model, ground: Vector3): State
	local model = Instance.new("Model")
	model.Name = "ClassPedestal"
	local glow: { BasePart } = {}
	local g = ground - Vector3.new(0, 0.05, 0) -- sink a hair into the floor
	-- Two stone steps, each with a rim of slightly lighter stone.
	disc(model, g + Vector3.new(0, 0.35, 0), R_BASE, 0.7, STONE, Enum.Material.Slate)
	disc(model, g + Vector3.new(0, 0.66, 0), R_BASE - 0.15, 0.1, STONE_TOP, Enum.Material.Slate)
	local top = disc(model, g + Vector3.new(0, 0.7 + 0.275, 0), R_TOP, 0.55, STONE_TOP, Enum.Material.Slate)
	top.CanQuery = true -- (the ultimate previews find their ground on it)
	-- The glowing seam where the upper step meets the lower one.
	table.insert(glow, disc(model, g + Vector3.new(0, 0.72, 0), R_TOP + 0.28, 0.06, Color3.new(1, 1, 1), Enum.Material.Neon))
	-- A glowing band round the lower step's face.
	table.insert(glow, disc(model, g + Vector3.new(0, 0.42, 0), R_BASE + 0.03, 0.07, Color3.new(1, 1, 1), Enum.Material.Neon))
	-- Rings on the top: an outer ring and an inner one round the feet (a neon
	-- disc with a stone disc just above it leaves a glowing ring).
	local y = g.Y + LIFT
	table.insert(glow, disc(model, Vector3.new(g.X, y + 0.015, g.Z), R_TOP - 0.35, 0.03, Color3.new(1, 1, 1), Enum.Material.Neon))
	disc(model, Vector3.new(g.X, y + 0.03, g.Z), R_TOP - 0.55, 0.03, STONE_TOP, Enum.Material.Slate)
	table.insert(glow, disc(model, Vector3.new(g.X, y + 0.045, g.Z), 1.75, 0.03, Color3.new(1, 1, 1), Enum.Material.Neon))
	disc(model, Vector3.new(g.X, y + 0.06, g.Z), 1.6, 0.03, STONE_TOP, Enum.Material.Slate)
	-- The turning rune ring between them: links and knots welded to a centre.
	local center = Vector3.new(g.X, y + 0.05, g.Z)
	local spinner = part(model, { Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(center), Transparency = 1 })
	local n = 18
	local ringR = 2.35
	for i = 1, n do
		local a = i / n * math.pi * 2
		local p = center + Vector3.new(math.cos(a) * ringR, 0, math.sin(a) * ringR)
		local link = part(model, {
			Size = if i % 3 == 0 then Vector3.new(0.34, 0.04, 0.34) else Vector3.new(0.09, 0.04, ringR * 2 * math.pi / n * 0.62),
			CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))) * (if i % 3 == 0 then CFrame.Angles(0, math.rad(45), 0) else CFrame.identity),
			Material = Enum.Material.Neon, Color = Color3.new(1, 1, 1), Anchored = false, Massless = true,
		})
		local w = Instance.new("WeldConstraint")
		w.Part0 = spinner
		w.Part1 = link
		w.Parent = link
		table.insert(glow, link)
	end
	model.Parent = Workspace
	return {
		model = model, center = center, hero = hero, heroBase = hero:GetPivot(),
		glow = glow, spinner = spinner, auraParts = {}, orbiters = {}, orbit = nil, conn = nil, locked = false, slashes = nil, nextSlash = 0,
	}
end

local function clearAura(s: State)
	for _, inst in ipairs(s.auraParts) do inst:Destroy() end
	table.clear(s.auraParts)
	table.clear(s.orbiters)
	s.orbit = nil
	s.slashes = nil
end

local function addAura(s: State, classId: string, c1: Color3, c2: Color3, locked: boolean)
	clearAura(s)
	local theme = if locked
		then { specs = { smoke(Color3.fromRGB(60, 60, 66), 5, 0, 0.45), motes(LOCKED, LOCKED, 6, 0.4) } } :: Theme
		else themeFor(classId, c1, c2)
	if not locked then table.insert(theme.specs, auraFlame(c1, 20)) end
	local mult = 1 - 0.5 * FxBudget.Pressure()
	-- Emitter hosts: the dais top (base), round the ring (ring) and the body.
	local c = s.center
	local base = part(s.model, { Size = Vector3.new(R_TOP * 1.4, 0.1, R_TOP * 1.4), CFrame = CFrame.new(c + Vector3.new(0, 0.1, 0)), Transparency = 1 })
	local body = part(s.model, { Size = Vector3.new(3.6, 5, 2.6), CFrame = CFrame.new(c + Vector3.new(0, 2.6, 0)), Transparency = 1 })
	local ringHosts: { Attachment } = {}
	local ringHost = part(s.model, { Size = Vector3.new(0.2, 0.2, 0.2), CFrame = CFrame.new(c), Transparency = 1 })
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2 + 0.3
		local att = Instance.new("Attachment")
		att.Position = Vector3.new(math.cos(a) * (R_TOP - 0.2), 0, math.sin(a) * (R_TOP - 0.2))
		att.Parent = ringHost
		table.insert(ringHosts, att)
	end
	table.insert(s.auraParts, base)
	table.insert(s.auraParts, body)
	table.insert(s.auraParts, ringHost)
	for _, spec in ipairs(theme.specs) do
		local hosts: { Instance } = if spec.at == "ring" then ringHosts :: any elseif spec.at == "body" then { body } else { base }
		for _, host in ipairs(hosts) do
			local e = Instance.new("ParticleEmitter")
			for k, v in pairs(spec.props) do (e :: any)[k] = v end
			if spec.at == "ring" then e.Rate = math.max(1, spec.props.Rate * mult / 6 * 4) else e.Rate = spec.props.Rate * mult end
			e.Parent = host
		end
	end
	s.slashes = theme.slashes
	-- Wisps orbiting the hero, each trailing light.
	local orbit = theme.orbit
	if orbit then
		s.orbit = orbit
		for i = 1, orbit.n do
			local p = part(s.model, { Shape = Enum.PartType.Ball, Size = Vector3.one * orbit.width * 0.7, Material = Enum.Material.Neon,
				Color = orbit.color, CFrame = CFrame.new(c) })
			local a0 = Instance.new("Attachment")
			a0.Position = Vector3.new(0, orbit.width, 0)
			a0.Parent = p
			local a1 = Instance.new("Attachment")
			a1.Position = Vector3.new(0, -orbit.width, 0)
			a1.Parent = p
			local tr = Instance.new("Trail")
			tr.Attachment0 = a0
			tr.Attachment1 = a1
			tr.Lifetime = orbit.life * 1.6
			tr.LightEmission = 1
			tr.FaceCamera = true
			tr.Color = cseq(Color3.new(1, 1, 1), orbit.color)
			tr.Transparency = seq(0, 0, 1, 1)
			tr.WidthScale = seq(0, 1, 1, 0)
			tr.Parent = p
			table.insert(s.auraParts, p)
			table.insert(s.orbiters, { part = p, phase = (i - 1) / orbit.n * math.pi * 2 })
		end
	end
end

-- One crescent of sword-light round the hero at a random tilt, fading fast.
local function slash(s: State, color: Color3)
	local cf = CFrame.new(s.center + Vector3.new(0, 2.6, 0))
		* CFrame.Angles(0, math.random() * math.pi * 2, 0)
		* CFrame.Angles((math.random() - 0.5) * 1.6, 0, (math.random() - 0.5) * 1.8)
	local n, r, sweep = 12, 2.5 + math.random() * 0.6, math.rad(150)
	local start = math.random() * math.pi * 2
	local info = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for i = 1, n do
		local a = start + (i - 0.5) / n * sweep
		local w = 0.05 + 0.24 * math.sin(math.pi * (i - 0.5) / n)
		local p = cf * Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		local tangent = cf:VectorToWorldSpace(Vector3.new(-math.sin(a), 0, math.cos(a)))
		local seg = part(s.model, { Size = Vector3.new(w, 0.04, r * sweep / n * 1.1), CFrame = CFrame.lookAt(p, p + tangent, cf.UpVector),
			Material = Enum.Material.Neon, Color = color:Lerp(Color3.new(1, 1, 1), 0.2 + 0.5 * math.sin(math.pi * i / n)), Transparency = 0 })
		local tw = TweenService:Create(seg, info, { Transparency = 1 })
		tw.Completed:Connect(function() seg:Destroy() end)
		task.delay((i - 1) * 0.012, function() tw:Play() end)
	end
end

local function step(s: State)
	local t = os.clock()
	s.spinner.CFrame = CFrame.new(s.center) * CFrame.Angles(0, t * 0.35, 0)
	-- (the rings breathe)
	local pulse = if s.locked then 0.6 else 0.08 + 0.12 * (0.5 + 0.5 * math.sin(t * 2.2))
	for i, g in ipairs(s.glow) do
		if i <= 4 then g.Transparency = pulse end
	end
	local sc = s.slashes
	if sc and t >= s.nextSlash then
		s.nextSlash = t + 0.4 + math.random() * 0.45
		if FxBudget.Allow("pedestal_slash", 3) then slash(s, sc) end
	end
	local orbit = s.orbit
	if orbit then
		for i, o in ipairs(s.orbiters) do
			local a = t * orbit.speed + o.phase
			local h = 1.6 + 1.5 * math.sin(t * 0.9 + o.phase * 1.7) + (i - 1) * 0.4
			local r = orbit.radius * (0.85 + 0.15 * math.sin(t * 1.3 + o.phase))
			o.part.CFrame = CFrame.new(s.center + Vector3.new(math.cos(a) * r, h, math.sin(a) * r))
		end
	end
end

-- Pale accents (the Ronin's ice blue, the Sword Master's cream) wash out to
-- white as neon: deepen them a little for the glow.
local function vivid(c: Color3): Color3
	local h, sat, v = c:ToHSV()
	return Color3.fromHSV(h, math.max(sat, 0.62), math.max(v, 0.9))
end

-- ── API ────────────────────────────────────────────────────────────────────
function ClassPedestal.Show(hero: Model?, classId: string, locked: boolean)
	if not hero or not hero.Parent then
		ClassPedestal.Hide()
		return
	end
	local s = state
	if s and s.hero ~= hero then
		ClassPedestal.Hide()
		s = nil
	end
	if not s then
		local ground = groundOf(hero)
		if not ground then return end
		s = build(hero, ground)
		state = s
		hero:PivotTo(s.heroBase + Vector3.new(0, LIFT, 0))
		local st = s
		st.conn = RunService.RenderStepped:Connect(function()
			if state ~= st then return end
			step(st)
		end)
	end
	local st = s :: State
	local info = ClassData.GetClass(classId)
	local c1 = if locked then LOCKED elseif info then vivid(info.accentColor) else Color3.new(1, 1, 1)
	local c2 = if locked then LOCKED elseif info and info.glowColor then info.glowColor else c1
	for i, g in ipairs(st.glow) do
		-- (the knots on the rune ring take the second colour)
		g.Color = if i > 4 and (i - 4) % 3 == 0 then c2:Lerp(Color3.new(1, 1, 1), 0.3) else c1
		g.Transparency = if locked then 0.6 else 0
	end
	st.locked = locked
	addAura(st, classId, c1, c2, locked)
end

function ClassPedestal.Hide()
	local s = state
	if not s then return end
	state = nil
	if s.conn then s.conn:Disconnect() end
	if s.hero.Parent then s.hero:PivotTo(s.heroBase) end
	s.model:Destroy()
end

-- (the hero is the local player's copy; drop the dais when they leave)
Players.LocalPlayer.AncestryChanged:Connect(function()
	ClassPedestal.Hide()
end)

return ClassPedestal
