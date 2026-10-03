--!strict
--[[
	FireFX.luau
	The Fire Knight's fire, drawn with real flame: the flipbook textures from
	the place's VFX library (ReplicatedStorage.Model.Anime: Fire-01/02/03,
	Fire-Slash-01, Crack-01, Realistic-Explosion-01, Shoot-01) instead of
	flat neon discs.

	  Flames(pos, o)            a one-shot burst of rolling flame
	  Explosion(pos, r, big)    flash, fireball, flame licks, embers, smoke,
	                            a shockwave on the floor and scorched cracks
	  Column(pos, h, w)         a jet of fire erupting out of the floor
	  Cracks(pos, r, life)      the floor split open, glowing from below
	  Burning(pos, r, life)     burning ground: cracks + flames + embers
	  Shockwave(pos, r)         a flat ring of force across the floor
	  FlameRing(pos, r, t)      a wall of fire bursting up round a circle
	  Slash(cf, r, arc, sweep)  a flaming slash: fire along the blade's path
	  Homing(from, getTarget)   a flame that flies to a moving point
	  Sigil(r)                  the Phoenix Slam's marker: rings, compass
	                            points and a phoenix drawn in light on the floor
	  Wings / Crown / Aura      phoenix wings, a crown of fire and a fire aura
	                            on a character
	  FeatherBurst, Rocks,      the crash: burning feathers, thrown-up rock,
	  Fissures, LightPillar     fire tearing through the floor, a pillar of light

	Everything is parented under ClassFX's folder (so VFX variants restyle it)
	and cleans itself up.
--]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local ClassFX = require(script.Parent:WaitForChild("ClassFX"))

local FireFX = {}

FireFX.FIRE = Color3.fromRGB(255, 120, 40)
FireFX.EMBER = Color3.fromRGB(255, 190, 90)
FireFX.HOT = Color3.fromRGB(255, 236, 170)
FireFX.DEEP = Color3.fromRGB(190, 45, 15)
local FIRE, EMBER, HOT, DEEP = FireFX.FIRE, FireFX.EMBER, FireFX.HOT, FireFX.DEEP

-- The library's textures (4×4 flipbooks unless noted).
local TEX = {
	flame = "rbxassetid://11395089850",     -- Fire-03: a stylised flame
	roll = "rbxassetid://16676544947",      -- Fire-02: a big rolling flame
	lick = "rbxassetid://13818306392",      -- Fire-01: a flame lick
	specs = "rbxassetid://11187840108",     -- Fire-01: embers (single frame)
	blast = "rbxassetid://12782553831",     -- Realistic-Explosion-01: the fireball
	smoke = "rbxassetid://17087884204",     -- Realistic-Explosion-01: smoke (single frame)
	slash = "rbxassetid://16951304645",     -- Fire-Slash-01: a burning slash
	slashSpecs = "rbxassetid://16951289316", -- Fire-Slash-01: its sparks
	crack = "rbxassetid://16937144632",     -- Crack-01: the floor cracked (single frame)
	crackCore = "rbxassetid://16937229477", -- Crack-01: the crater (single frame)
	shock = "rbxassetid://16477162837",     -- Shoot-01: a shockwave
	spark = "rbxasset://textures/particles/sparkles_main.dds",
}
FireFX.TEX = TEX

local rng = Random.new()

local function nsk(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

local function csk(t: number, c: Color3): ColorSequenceKeypoint
	return ColorSequenceKeypoint.new(t, c)
end

-- An invisible anchored holder for emitters.
local function anchor(cf: CFrame, size: Vector3?): BasePart
	return ClassFX.Neon({ Size = size or Vector3.one * 0.2, CFrame = cf, Transparency = 1 })
end

local FLIP4 = Enum.ParticleFlipbookLayout.Grid4x4

-- A particle emitter with the library's look (unlit, glowing).
local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.Rate = 0
	e.Rotation = NumberRange.new(-360, 360)
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function flip(e: ParticleEmitter): ParticleEmitter
	e.FlipbookLayout = FLIP4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	return e
end

-- The flame palette: white-hot at birth, flame, then deep ember.
local function flameColors(hot: boolean?): ColorSequence
	if hot then
		return ColorSequence.new({ csk(0, Color3.fromRGB(255, 250, 220)), csk(0.4, HOT), csk(1, FIRE) })
	end
	return ColorSequence.new({ csk(0, HOT), csk(0.35, Color3.fromRGB(255, 150, 60)), csk(1, DEEP) })
end
FireFX.Colors = flameColors

-- Emitters for each kind of fire, ready to Emit or run.
local KIND: { [string]: (Instance, number) -> ParticleEmitter } = {}

KIND.flame = function(parent, size)
	return flip(emitter(parent, {
		Name = "Flame", Texture = TEX.flame, Color = flameColors(), Brightness = 3.5, LightEmission = 0.4,
		Size = NumberSequence.new({ nsk(0, size * 0.55), nsk(0.35, size), nsk(1, size * 0.8) }),
		Transparency = NumberSequence.new({ nsk(0, 0.1), nsk(0.65, 0.15), nsk(0.85, 0.6), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.45, 0.6), Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, 6, 0),
		Drag = 3, RotSpeed = NumberRange.new(-30, 30), SpreadAngle = Vector2.new(25, 25), ZOffset = 0.5,
	}))
end

KIND.roll = function(parent, size)
	return flip(emitter(parent, {
		Name = "RollingFlame", Texture = TEX.roll, Color = flameColors(), Brightness = 4, LightEmission = 0.3,
		Size = NumberSequence.new({ nsk(0, size * 0.2), nsk(0.5, size), nsk(1, size * 1.05) }),
		Transparency = NumberSequence.new({ nsk(0, 0), nsk(0.35, 0), nsk(0.55, 0.5), nsk(0.8, 0.92), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.6, 0.75), Speed = NumberRange.new(0.5, 2), Acceleration = Vector3.new(0, 4, 0),
		RotSpeed = NumberRange.new(-20, 20), SpreadAngle = Vector2.new(15, 15), ZOffset = 0.8,
	}))
end

KIND.lick = function(parent, size)
	return flip(emitter(parent, {
		Name = "FlameLick", Texture = TEX.lick, Color = ColorSequence.new(Color3.fromRGB(255, 120, 40), Color3.fromRGB(255, 60, 15)),
		Brightness = 5, LightEmission = 0.15,
		Size = NumberSequence.new({ nsk(0, 0), nsk(0.15, size), nsk(1, 0) }),
		Transparency = NumberSequence.new(0),
		Lifetime = NumberRange.new(0.45, 0.6), Speed = NumberRange.new(4, 14), Drag = 6,
		SpreadAngle = Vector2.new(180, 180), ZOffset = 1,
	}))
end

KIND.embers = function(parent, size)
	return emitter(parent, {
		Name = "Embers", Texture = TEX.specs, Color = ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(255, 80, 20)),
		Brightness = 5, LightEmission = 1,
		Size = NumberSequence.new({ nsk(0, 0), nsk(0.2, size), nsk(1, 0) }),
		Transparency = NumberSequence.new(0),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(6, 16), Drag = 4, Acceleration = Vector3.new(0, 6, 0),
		SpreadAngle = Vector2.new(180, 180), ZOffset = 1.2,
	})
end

KIND.blast = function(parent, size)
	return flip(emitter(parent, {
		Name = "Fireball", Texture = TEX.blast, Color = ColorSequence.new(Color3.fromRGB(255, 220, 160), Color3.fromRGB(255, 140, 70)),
		Brightness = 2, LightEmission = 0.9,
		Size = NumberSequence.new({ nsk(0, size * 0.3), nsk(0.3, size * 0.85), nsk(1, size) }),
		Transparency = NumberSequence.new({ nsk(0, 0), nsk(0.75, 0), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.7, 0.8), Speed = NumberRange.new(0, 0), ZOffset = 1.5,
	}))
end

KIND.smoke = function(parent, size)
	return emitter(parent, {
		Name = "Smoke", Texture = TEX.smoke, Color = ColorSequence.new(Color3.fromRGB(70, 52, 46), Color3.fromRGB(30, 26, 26)),
		LightEmission = 0, LightInfluence = 0.4,
		Size = NumberSequence.new({ nsk(0, size * 0.4), nsk(1, size) }),
		Transparency = NumberSequence.new({ nsk(0, 0.35), nsk(0.6, 0.6), nsk(1, 1) }),
		Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(2, 6), Drag = 2.5, Acceleration = Vector3.new(0, 3, 0),
		SpreadAngle = Vector2.new(180, 180), RotSpeed = NumberRange.new(-20, 20),
	})
end

-- Flat on the floor (the holder's top faces up).
local FLAT_UP = Enum.ParticleOrientation.VelocityPerpendicular

KIND.crack = function(parent, size)
	return emitter(parent, {
		Name = "Cracks", Texture = TEX.crack, Orientation = FLAT_UP, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(Color3.fromRGB(255, 150, 60)), Brightness = 3, LightEmission = 1,
		Size = NumberSequence.new({ nsk(0, size * 0.7), nsk(0.12, size), nsk(1, size) }),
		Transparency = NumberSequence.new({ nsk(0, 1), nsk(0.06, 0), nsk(0.75, 0.2), nsk(1, 1) }),
		Lifetime = NumberRange.new(1, 1), Speed = NumberRange.new(0.001, 0.001), ZOffset = -0.5,
	})
end

KIND.crater = function(parent, size)
	return emitter(parent, {
		Name = "Crater", Texture = TEX.crackCore, Orientation = FLAT_UP, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(Color3.fromRGB(255, 190, 110)), Brightness = 4, LightEmission = 1,
		Size = NumberSequence.new({ nsk(0, size * 0.3), nsk(0.1, size), nsk(1, size) }),
		Transparency = NumberSequence.new({ nsk(0, 1), nsk(0.05, 0), nsk(0.7, 0.3), nsk(1, 1) }),
		Lifetime = NumberRange.new(1, 1), Speed = NumberRange.new(0.001, 0.001), ZOffset = -0.4,
	})
end

KIND.shock = function(parent, size)
	return flip(emitter(parent, {
		Name = "Shockwave", Texture = TEX.shock, Orientation = FLAT_UP, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 130), Color3.fromRGB(255, 110, 40)), Brightness = 3, LightEmission = 1,
		Size = NumberSequence.new({ nsk(0, size * 0.25), nsk(1, size) }),
		Transparency = NumberSequence.new({ nsk(0, 0), nsk(0.6, 0.2), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.4), Speed = NumberRange.new(0.001, 0.001), Rotation = NumberRange.new(0, 360),
	}))
end

KIND.slash = function(parent, size)
	return flip(emitter(parent, {
		Name = "FireSlash", Texture = TEX.slash, Orientation = FLAT_UP, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(Color3.fromRGB(255, 160, 70), Color3.fromRGB(255, 70, 20)), Brightness = 6, LightEmission = 0.5,
		Size = NumberSequence.new(size), Transparency = NumberSequence.new({ nsk(0, 0.2), nsk(0.5, 0), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.3, 0.3), Speed = NumberRange.new(0.001, 0.001), ZOffset = 1,
	}))
end

KIND.slashSpecs = function(parent, size)
	return flip(emitter(parent, {
		Name = "SlashSparks", Texture = TEX.slashSpecs, Orientation = FLAT_UP, EmissionDirection = Enum.NormalId.Top,
		Color = ColorSequence.new(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 90, 30)), Brightness = 8, LightEmission = 0.6,
		Size = NumberSequence.new(size * 1.25), Transparency = NumberSequence.new({ nsk(0, 1), nsk(0.3, 0.3), nsk(0.7, 0), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.32, 0.32), Speed = NumberRange.new(0.001, 0.001), ZOffset = 1.1,
	}))
end

FireFX.Emitter = function(kind: string, parent: Instance, size: number): ParticleEmitter
	return KIND[kind](parent, size)
end

-- Emit `n` of `kind` from a holder at `cf` (sized `box` for spawning over an
-- area), cleaned up after.
local function puff(kind: string, cf: CFrame, size: number, n: number, tweak: ((ParticleEmitter) -> ())?, box: Vector3?): ParticleEmitter
	local a = anchor(cf, box)
	local e = KIND[kind](a, size)
	if tweak then tweak(e) end
	e:Emit(n)
	Debris:AddItem(a, e.Lifetime.Max + 0.3)
	return e
end
FireFX.Puff = puff

-- ── Ground ──────────────────────────────────────────────────────────────────
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true

function FireFX.GroundY(pos: Vector3): number
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	for _, n in ipairs({ "Mobs", "Allies", "IceClones", "BossFX", "MobFX", "RoomEmblems" }) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(ignore, f) end
	end
	groundParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), groundParams)
	return if hit then hit.Position.Y else pos.Y - 3
end

local function ground(pos: Vector3): Vector3
	return Vector3.new(pos.X, FireFX.GroundY(pos), pos.Z)
end
FireFX.Ground = ground

-- ── Building blocks ─────────────────────────────────────────────────────────
-- A burst of rolling flame at `pos`.
function FireFX.Flames(pos: Vector3, size: number, count: number, spread: number?)
	local box = Vector3.one * (spread or 0.4)
	puff("roll", CFrame.new(pos), size, count, nil, box)
	puff("flame", CFrame.new(pos), size * 0.7, math.ceil(count * 0.7), nil, box)
end

-- The floor split open, glowing from below, for `life` seconds.
function FireFX.Cracks(pos: Vector3, radius: number, life: number, crater: boolean?)
	local g = ground(pos)
	local cf = CFrame.new(g + Vector3.new(0, 0.12, 0))
	puff("crack", cf, radius * 2.1, 1, function(e)
		e.Lifetime = NumberRange.new(life, life)
		e.Rotation = NumberRange.new(rng:NextNumber(0, 360))
	end)
	if crater ~= false then
		puff("crater", cf + Vector3.new(0, 0.02, 0), radius * 1.1, 1, function(e)
			e.Lifetime = NumberRange.new(life * 0.8, life * 0.8)
		end)
	end
end

-- A flat ring of force racing out across the floor.
function FireFX.Shockwave(pos: Vector3, radius: number)
	local g = ground(pos)
	puff("shock", CFrame.new(g + Vector3.new(0, 0.3, 0)), radius * 2.2, 1)
end

-- A jet of fire erupting out of the floor.
function FireFX.Column(pos: Vector3, height: number, width: number)
	local g = ground(pos)
	local a = anchor(CFrame.new(g + Vector3.new(0, 0.3, 0)), Vector3.new(width * 0.5, 0.2, width * 0.5))
	local up = KIND.roll(a, width * 1.4)
	up.EmissionDirection = Enum.NormalId.Top
	up.SpreadAngle = Vector2.new(6, 6)
	up.Speed = NumberRange.new(height * 1.6, height * 2.1)
	up.Drag = 2.2
	up.Acceleration = Vector3.zero
	up.Lifetime = NumberRange.new(0.5, 0.65)
	up:Emit(math.clamp(math.floor(height * 0.8), 4, 14))
	local base = KIND.flame(a, width * 1.2)
	base.SpreadAngle = Vector2.new(60, 60)
	base:Emit(4)
	local sp = KIND.embers(a, 0.35)
	sp.EmissionDirection = Enum.NormalId.Top
	sp.SpreadAngle = Vector2.new(25, 25)
	sp.Speed = NumberRange.new(height * 1.2, height * 2.2)
	sp:Emit(math.floor(height))
	Debris:AddItem(a, 1.6)
end

-- An explosion: a white flash, a fireball, flame licks, embers, smoke, a
-- shockwave across the floor and the floor scorched where it went off.
function FireFX.Explosion(pos: Vector3, radius: number, big: boolean?)
	local g = ground(pos)
	local center = Vector3.new(pos.X, math.max(pos.Y, g.Y + radius * 0.35), pos.Z)
	-- (the flash: a heartbeat of white-hot light)
	local flash = ClassFX.Neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * radius * 0.6, CFrame = CFrame.new(center),
		Color = Color3.fromRGB(255, 245, 210), Transparency = 0.1 })
	TweenService:Create(flash, TweenInfo.new(0.16, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.one * radius * 1.3, Transparency = 1 }):Play()
	Debris:AddItem(flash, 0.2)
	puff("blast", CFrame.new(center), radius * 2.3, if big then 3 else 2, function(e)
		e.Rotation = NumberRange.new(-360, 360)
	end, Vector3.one * radius * 0.2)
	puff("roll", CFrame.new(center), radius * 1.1, if big then 10 else 6, function(e)
		e.Speed = NumberRange.new(radius * 0.8, radius * 1.6)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Drag = 4
	end, Vector3.one * radius * 0.3)
	puff("lick", CFrame.new(center), radius * 0.45, if big then 26 else 14, function(e)
		e.Speed = NumberRange.new(radius * 1.5, radius * 3)
	end)
	puff("embers", CFrame.new(center), 0.35, if big then 30 else 16, function(e)
		e.Speed = NumberRange.new(radius * 1.5, radius * 3.5)
	end)
	puff("smoke", CFrame.new(center + Vector3.new(0, radius * 0.3, 0)), radius * 1.6, if big then 8 else 4)
	FireFX.Shockwave(g, radius * (if big then 1.4 else 1.1))
	FireFX.Cracks(g, radius * 0.75, if big then 2.4 else 1.3, big)
	ClassFX.Sound(if big then "boom" else "fireBurst", center, if big then 0.9 else 0.55, 1 + rng:NextNumber(-0.08, 0.08))
end

-- A wall of fire bursting up round a circle (rings of fire).
function FireFX.FlameRing(pos: Vector3, radius: number, height: number)
	local g = ground(pos)
	local n = math.clamp(math.floor(radius * 1.1), 10, 34)
	local t0 = rng:NextNumber(0, math.pi * 2)
	for i = 1, n do
		local a = t0 + i / n * math.pi * 2
		local p = g + Vector3.new(math.cos(a) * radius, 0.3, math.sin(a) * radius)
		local h = anchor(CFrame.new(p))
		local e = KIND.roll(h, 2.4 + radius * 0.05)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(8, 8)
		e.Speed = NumberRange.new(height * 1.4, height * 1.9)
		e.Drag = 2.5
		e.Acceleration = Vector3.zero
		e:Emit(2)
		Debris:AddItem(h, 1)
	end
	FireFX.Shockwave(g, radius * 1.1)
end

-- A flaming slash along a circular arc, laid out like SwordFX's arcs: `cf`
-- is the swing's centre and plane (the arc bulges toward its -Z, in its XZ
-- plane), `radius` the blade's reach, `arc` degrees, `sweep` 1 = right to
-- left, -1 = left to right. Flames and sparks burst along the blade's path
-- as it passes, over `draw` seconds.
function FireFX.Slash(cf: CFrame, radius: number, arc: number, sweep: number, draw: number, hot: boolean?)
	local steps = math.clamp(math.floor(arc / 14), 6, 16)
	local sign = if sweep >= 0 then 1 else -1
	local span = math.rad(arc)
	for i = 0, steps do
		local a = -sign * span / 2 + sign * span * i / steps
		local pt = cf:PointToWorldSpace(Vector3.new(-math.sin(a) * radius * 0.85, 0, -math.cos(a) * radius * 0.85))
		task.delay(draw * i / steps, function()
			local h = anchor(CFrame.new(pt))
			local f = KIND.flame(h, 1.6 + radius * 0.12)
			if hot then f.Color = flameColors(true) end
			f.Speed = NumberRange.new(1, 4)
			f:Emit(2)
			local l = KIND.lick(h, 0.9)
			l.Speed = NumberRange.new(3, 8)
			l:Emit(3)
			Debris:AddItem(h, 1)
		end)
	end
	-- The burning slash itself, in the swing's plane.
	puff("slash", cf, radius * 2.1, 1, function(e)
		e.Rotation = NumberRange.new(if sweep > 0 then 90 else -90)
		e.RotSpeed = NumberRange.new(sweep * 500, sweep * 500)
	end)
	puff("slashSpecs", cf, radius * 2.1, 1)
end

-- Burning ground: glowing cracks, flames licking up across it and embers,
-- for `life` seconds. Returns a handle (`stop()` puts it out early).
export type Burn = { pos: Vector3, radius: number, stop: () -> (), holder: BasePart }

function FireFX.Burning(pos: Vector3, radius: number, life: number): Burn
	local g = ground(pos)
	local cf = CFrame.new(g + Vector3.new(0, 0.12, 0))
	FireFX.Cracks(g, radius, life + 0.4, false)
	local h = anchor(cf, Vector3.new(radius * 1.5, 0.1, radius * 1.5))
	local f = KIND.flame(h, 1.5 + radius * 0.22)
	f.EmissionDirection = Enum.NormalId.Top
	f.SpreadAngle = Vector2.new(10, 10)
	f.Speed = NumberRange.new(1.5, 3.5)
	f.Rate = 5 + radius * 3.5
	local r = KIND.roll(h, 1.4 + radius * 0.2)
	r.EmissionDirection = Enum.NormalId.Top
	r.Speed = NumberRange.new(1, 3)
	r.Rate = 2 + radius
	local e = KIND.embers(h, 0.22)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(20, 20)
	e.Speed = NumberRange.new(2, 6)
	e.Rate = 4 + radius * 2
	local done = false
	local function stop()
		if done then return end
		done = true
		f.Enabled, r.Enabled, e.Enabled = false, false, false
		Debris:AddItem(h, 1.4)
	end
	task.delay(life, stop)
	Debris:AddItem(h, life + 1.6)
	return { pos = g, radius = radius, stop = stop, holder = h }
end

-- A flame that flies from `from` to wherever `getTarget()` is (re-aimed every
-- frame, so it follows a moving sword), arcing out first. Calls `arrive` when
-- it gets there.
function FireFX.Homing(from: Vector3, getTarget: () -> Vector3?, dur: number, size: number, arrive: ((Vector3) -> ())?)
	local h = anchor(CFrame.new(from))
	local core = KIND.flame(h, size)
	core.Rate = 40
	core.LockedToPart = false
	core.Speed = NumberRange.new(0, 0.5)
	core.Acceleration = Vector3.zero
	core.Lifetime = NumberRange.new(0.25, 0.35)
	local sp = KIND.embers(h, 0.25)
	sp.Rate = 20
	sp.Speed = NumberRange.new(0.5, 2)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, size * 0.25, 0)
	a0.Parent = h
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -size * 0.25, 0)
	a1.Parent = h
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Color = ColorSequence.new({ csk(0, HOT), csk(0.5, FIRE), csk(1, DEEP) })
	tr.Transparency = NumberSequence.new({ nsk(0, 0.1), nsk(1, 1) })
	tr.LightEmission = 1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.Lifetime = 0.22
	tr.WidthScale = NumberSequence.new({ nsk(0, 1), nsk(1, 0) })
	tr.Parent = h
	-- (out and up first, then pulled in: a curve, not a line)
	local side = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
	side = if side.Magnitude > 0.01 then side.Unit else Vector3.xAxis
	local bulge = side * rng:NextNumber(2, 5) + Vector3.new(0, rng:NextNumber(3, 7), 0)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local a = math.min((os.clock() - t0) / dur, 1)
		local target = getTarget() or from
		-- quadratic curve from → (midpoint + bulge) → target, easing in
		local e = a * a * (3 - 2 * a)
		local mid = (from + target) / 2 + bulge
		local p = from:Lerp(mid, e):Lerp(mid:Lerp(target, e), e)
		h.CFrame = CFrame.new(p)
		if a >= 1 then
			if conn then conn:Disconnect() end
			core.Enabled, sp.Enabled = false, false
			Debris:AddItem(h, 0.4)
			if arrive then arrive(target) end
		end
	end)
end

-- ── Flat glowing lines on the floor (the Phoenix Slam's sigil) ──────────────
-- Beams lying flat in a holder part's XZ plane: their attachments' X axis
-- runs along the line, Y spans the width (SwordFX.Sweep's trick), so they
-- read as painted light on the ground and move with the holder.
local function flatBeam(a0: Attachment, a1: Attachment, w0: number, w1: number, color: ColorSequence, tr: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = false
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Brightness = 1.4
	b.Segments = 20
	b.Width0, b.Width1 = w0, w1
	b.Color = color
	b.Transparency = NumberSequence.new(tr)
	b.Parent = a0
	return b
end

local function flatAtt(holder: BasePart, pos: Vector3, along: Vector3): Attachment
	local a = Instance.new("Attachment")
	local side = Vector3.new(-along.Z, 0, along.X)
	a.CFrame = CFrame.fromMatrix(pos, along, side)
	a.Parent = holder
	return a
end

-- A ring of light `width` wide, radius `r`, round the holder's centre (at
-- height `y`).
function FireFX.FlatRing(holder: BasePart, r: number, width: number, color: ColorSequence, tr: number, y: number?): { Beam }
	local out = {}
	local h = y or 0
	local handle = 4 / 3 * math.tan(math.rad(90) / 4) * r
	for i = 0, 3 do
		local a0, a1 = math.rad(i * 90), math.rad(i * 90 + 90)
		local p0 = Vector3.new(math.cos(a0) * r, h, math.sin(a0) * r)
		local p1 = Vector3.new(math.cos(a1) * r, h, math.sin(a1) * r)
		local t0 = Vector3.new(-math.sin(a0), 0, math.cos(a0))
		local t1 = Vector3.new(-math.sin(a1), 0, math.cos(a1))
		local b = flatBeam(flatAtt(holder, p0, t0), flatAtt(holder, p1, t1), width, width, color, tr)
		b.CurveSize0, b.CurveSize1 = handle, handle
		table.insert(out, b)
	end
	return out
end

-- A flat blade of light from `a` to `b` (holder space), `w0` wide at `a`
-- tapering to `w1`: spikes, star points, arrows, feathers.
function FireFX.FlatSpike(holder: BasePart, a: Vector3, b: Vector3, w0: number, w1: number, color: ColorSequence, tr: number): Beam
	local d = b - a
	local along = Vector3.new(d.X, 0, d.Z)
	along = if along.Magnitude > 1e-3 then along.Unit else Vector3.xAxis
	return flatBeam(flatAtt(holder, a, along), flatAtt(holder, b, along), w0, w1, color, tr)
end

-- (deep: the bloom lifts them; anything paler blows out to white)
local GOLD_LINE = ColorSequence.new(Color3.fromRGB(255, 190, 95), Color3.fromRGB(255, 115, 30))
local FLAME_LINE = ColorSequence.new(Color3.fromRGB(255, 110, 35), Color3.fromRGB(200, 40, 12))

-- The Phoenix Slam's sigil: rings within rings, four long compass points
-- and four short ones, arrows round the rim, and the phoenix in the middle,
-- all drawn in light on the floor, flames licking round the rim.
export type Sigil = {
	move: (Vector3) -> (),
	lock: () -> (),      -- chosen: it flares
	destroy: (number?) -> (), -- burn out over `t`
	center: () -> Vector3,
}

function FireFX.Sigil(radius: number): Sigil
	local r = radius
	local outer = ClassFX.Neon({ Size = Vector3.one * 0.2, Transparency = 1 })
	local inner = ClassFX.Neon({ Size = Vector3.one * 0.2, Transparency = 1 }) -- turns slowly
	local beams: { Beam } = {}
	local function add(list: { Beam }) for _, b in ipairs(list) do table.insert(beams, b) end end
	-- rings
	add(FireFX.FlatRing(outer, r, 0.42, GOLD_LINE, 0.05))
	add(FireFX.FlatRing(outer, r * 0.93, 0.14, FLAME_LINE, 0.25))
	add(FireFX.FlatRing(inner, r * 0.58, 0.3, GOLD_LINE, 0.1))
	add(FireFX.FlatRing(inner, r * 0.5, 0.1, FLAME_LINE, 0.3))
	-- the compass: four long points reaching past the rim, four short ones
	for k = 0, 7 do
		local a = math.rad(k * 45)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		local long = k % 2 == 0
		local from, to = dir * r * 0.5, dir * r * (if long then 1.42 else 1.05)
		local w = if long then 1.1 else 0.55
		local mid = from:Lerp(to, 0.3)
		table.insert(beams, FireFX.FlatSpike(outer, from, mid, 0.05, w, GOLD_LINE, 0.05))
		table.insert(beams, FireFX.FlatSpike(outer, mid, to, w, 0.02, GOLD_LINE, 0.05))
		if long then
			-- a thin ray carrying on out past the point
			table.insert(beams, FireFX.FlatSpike(outer, to, dir * r * 1.75, 0.18, 0.01, FLAME_LINE, 0.3))
		end
	end
	-- arrows round the rim, pointing in
	for k = 0, 3 do
		local a = math.rad(k * 90 + 45)
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		table.insert(beams, FireFX.FlatSpike(outer, dir * r * 1.12, dir * r * 0.86, 1.1, 0.02, FLAME_LINE, 0.1))
	end
	-- the phoenix: a body, swept wings of three feathers each, a forked tail
	local s = r * 0.42
	local up = Vector3.new(0, 0, -1)
	table.insert(beams, FireFX.FlatSpike(inner, up * s * 0.55, -up * s * 0.35, 0.02, s * 0.32, GOLD_LINE, 0)) -- head to chest
	table.insert(beams, FireFX.FlatSpike(inner, -up * s * 0.35, -up * s * 0.95, s * 0.32, 0.02, GOLD_LINE, 0)) -- tail
	for _, side in ipairs({ -1, 1 }) do
		local base = Vector3.new(side * s * 0.08, 0, s * 0.05)
		for i, feather in ipairs({
			Vector3.new(side * s * 1.05, 0, -s * 0.75),
			Vector3.new(side * s * 0.95, 0, -s * 0.35),
			Vector3.new(side * s * 0.75, 0, s * 0.05),
		}) do
			table.insert(beams, FireFX.FlatSpike(inner, base, feather, s * (0.36 - i * 0.06), 0.02, GOLD_LINE, 0.02))
		end
		-- the tail's fork
		table.insert(beams, FireFX.FlatSpike(inner, -up * s * 0.3, Vector3.new(side * s * 0.45, 0, s * 0.95), s * 0.14, 0.02, FLAME_LINE, 0.1))
	end
	-- flames licking round the rim, embers rising off it
	local flames: { ParticleEmitter } = {}
	local n = math.clamp(math.floor(r * 1.4), 10, 24)
	for i = 1, n do
		local a = i / n * math.pi * 2
		local at = Instance.new("Attachment")
		at.Position = Vector3.new(math.cos(a) * r, 0.2, math.sin(a) * r)
		at.Parent = outer
		local e = KIND.flame(at, 1.3)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(6, 6)
		e.Speed = NumberRange.new(2, 4)
		e.LockedToPart = true
		e.Rate = 4
		table.insert(flames, e)
	end
	-- (embers rise from all over it: the holder spans the circle)
	outer.Size = Vector3.new(r * 1.6, 0.1, r * 1.6)
	local motes = KIND.embers(outer, 0.28)
	motes.EmissionDirection = Enum.NormalId.Top
	motes.Shape = Enum.ParticleEmitterShape.Box
	motes.SpreadAngle = Vector2.new(10, 10)
	motes.Speed = NumberRange.new(4, 9)
	motes.Rate = 14

	local at = Vector3.zero
	local spin = 0
	local spinRate = 0.5
	local alive = true
	local conn = RunService.RenderStepped:Connect(function(dt)
		spin += dt * spinRate
		outer.CFrame = CFrame.new(at + Vector3.new(0, 0.14, 0))
		inner.CFrame = CFrame.new(at + Vector3.new(0, 0.16, 0)) * CFrame.Angles(0, spin, 0)
	end)
	return {
		move = function(p: Vector3) at = p end,
		center = function() return at end,
		lock = function()
			spinRate = 4
			for _, b in ipairs(beams) do b.Brightness = 2.6 end
			for _, e in ipairs(flames) do e.Rate = 16 end
			motes.Rate = 50
		end,
		destroy = function(t: number?)
			if not alive then return end
			alive = false
			local life = t or 0.3
			for _, e in ipairs(flames) do e.Enabled = false end
			motes.Enabled = false
			for k = 1, 8 do
				task.delay(life * k / 8, function()
					for _, b in ipairs(beams) do
						if b.Parent then b.Transparency = NumberSequence.new(math.min(1, k / 8 + 0.05)) end
					end
				end)
			end
			task.delay(life + 0.05, function()
				conn:Disconnect()
				outer:Destroy()
				inner:Destroy()
			end)
		end,
	}
end

-- ── Phoenix wings, a crown of fire, a fire aura (on a character) ───────────
-- Great wings of flame sprouting from the back: a leading edge of light
-- rising out and up, long flight feathers of fire fanning down and out from
-- it, shorter coverts over them, flames riding the bones and streaming off
-- the feather tips. They unfurl, beat slowly, sweep back for a dive.
export type Wings = {
	beat: (number) -> (),   -- wingbeat speed (1 = hovering)
	sweep: (number) -> (),  -- 0 = spread, 1 = swept back (diving)
	fade: (number) -> (),
}

local WING_FEATHER = ColorSequence.new({ csk(0, Color3.fromRGB(255, 180, 75)), csk(0.4, Color3.fromRGB(255, 105, 30)), csk(1, Color3.fromRGB(170, 28, 10)) })
local WING_EDGE = ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(255, 115, 35))
local FEATHER_TEX = "rbxassetid://140565630584580" -- library (UltAtmosphere) feather

function FireFX.Wings(char: Model, scale: number): Wings?
	local torso = (char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")) :: BasePart?
	if not torso then return nil end
	local S = scale
	local made: { Instance } = {}
	local function att(): Attachment
		local a = Instance.new("Attachment")
		a.Name = "FKWing"
		a.Parent = torso
		table.insert(made, a)
		return a
	end
	local function beam(a0: Attachment, a1: Attachment, w0: number, w1: number, color: ColorSequence, tr: NumberSequence): Beam
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = 1.1
		b.Segments = 8
		b.Width0, b.Width1 = w0, w1
		b.Color = color
		b.Transparency = tr
		b.Parent = a0
		return b
	end
	local BONES = 8
	type Wing = { side: number, bones: { Attachment }, tips: { Attachment }, coverts: { Attachment } }
	local wings: { Wing } = {}
	local emitters: { ParticleEmitter } = {}
	for _, side in ipairs({ -1, 1 }) do
		local w: Wing = { side = side, bones = { att() }, tips = {}, coverts = {} }
		for i = 1, BONES do
			local b, tip, cov = att(), att(), att()
			table.insert(w.bones, b)
			table.insert(w.tips, tip)
			table.insert(w.coverts, cov)
			local f = i / BONES
			beam(w.bones[i], b, (0.75 - f * 0.4) * S, (0.75 - (f + 1 / BONES) * 0.4) * S, WING_EDGE, NumberSequence.new(0.05, 0.2))
			beam(b, tip, (1.5 - f * 0.5) * S, 0.08 * S, WING_FEATHER, NumberSequence.new({ nsk(0, 0.1), nsk(0.7, 0.35), nsk(1, 0.85) }))
			beam(b, cov, (1.2 - f * 0.4) * S, 0.25 * S, WING_FEATHER, NumberSequence.new(0.35, 0.8))
			local e = KIND.flame(b, (2.5 - f * 1.1) * S)
			e.Brightness = 1.8
			e.Rate = 14
			e.LockedToPart = true
			e.Speed = NumberRange.new(0.5, 2)
			e.Lifetime = NumberRange.new(0.35, 0.5)
			table.insert(emitters, e)
			if i % 2 == 0 then
				local t = KIND.flame(tip, (1.9 - f * 0.4) * S)
				t.Brightness = 1.6
				t.Rate = 8
				t.LockedToPart = false
				t.Speed = NumberRange.new(0.5, 1.5)
				table.insert(emitters, t)
			end
		end
		table.insert(wings, w)
	end
	-- burning feathers shed from the wings, drifting down
	local shed = Instance.new("Attachment")
	shed.Position = Vector3.new(0, 2 * S, 1)
	shed.Parent = torso
	table.insert(made, shed)
	local fe = emitter(shed, {
		Name = "FlamingFeathers", Texture = FEATHER_TEX, Color = ColorSequence.new(Color3.fromRGB(255, 215, 120), Color3.fromRGB(255, 80, 20)),
		LightEmission = 1, Brightness = 3, Size = NumberSequence.new({ nsk(0, 0.9), nsk(1, 0.6) }),
		Transparency = NumberSequence.new({ nsk(0, 0), nsk(0.75, 0.2), nsk(1, 1) }),
		Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(70, 70),
		Acceleration = Vector3.new(0, -5, 0), Drag = 1.5, RotSpeed = NumberRange.new(-80, 80), Rate = 10,
		Shape = Enum.ParticleEmitterShape.Box,
	})
	table.insert(emitters, fe)

	local speed, swept, grow = 1, 0, 0
	local phase = 0
	local alive = true
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function(dt)
		if not alive then return end
		phase += dt * 4.2 * speed
		grow = math.min((os.clock() - t0) / 0.35, 1) -- unfurling
		local g = grow * (2 - grow)
		for _, w in ipairs(wings) do
			local s = w.side
			local px, py, pz = s * 0.45, 0.65, 0.55
			w.bones[1].Position = Vector3.new(px, py, pz)
			local seg = 9.5 * S / BONES * g
			for i = 1, BONES do
				local f = i / BONES
				local flap = math.sin(phase - f * 0.9)
				-- the leading edge arches: steep near the back, levelling out
				-- (up and out in a V, like the art; flattening toward the tips)
				local el = math.rad((78 - 50 * f) * (1 - swept * 0.6) + flap * (12 + 12 * f) * (1 - swept))
				px += s * seg * math.cos(el) * (1 - swept * 0.45)
				py += seg * math.sin(el)
				pz += seg * (0.1 + swept * 0.7)
				w.bones[i + 1].Position = Vector3.new(px, py, pz)
				-- feathers: inner ones hang down, outer ones fan out
				local fan = math.rad(8 + 78 * f - swept * 30)
				local L = (2 + 3.4 * math.sin(f * math.pi * 0.85)) * S * g
				local fd = Vector3.new(s * math.sin(fan), -math.cos(fan), 0.25 + swept)
				w.tips[i].Position = Vector3.new(px, py, pz) + fd.Unit * L
				w.coverts[i].Position = Vector3.new(px, py, pz) + fd.Unit * L * 0.5 + Vector3.new(0, 0.2 * S, 0)
			end
		end
	end)
	return {
		beat = function(v: number) speed = v end,
		sweep = function(v: number) swept = math.clamp(v, 0, 1) end,
		fade = function(t: number)
			if not alive then return end
			for _, e in ipairs(emitters) do e.Enabled = false end
			for k = 1, 8 do
				task.delay(t * k / 8, function()
					for _, a in ipairs(made) do
						for _, b in ipairs(a:GetChildren()) do
							if b:IsA("Beam") then b.Transparency = NumberSequence.new(math.min(1, k / 8 + 0.1)) end
						end
					end
				end)
			end
			task.delay(t + 0.05, function()
				alive = false
				conn:Disconnect()
				for _, a in ipairs(made) do
					for _, b in ipairs(a:GetChildren()) do
						if b:IsA("Beam") then b:Destroy() end
					end
				end
				task.delay(1, function() for _, a in ipairs(made) do a:Destroy() end end)
			end)
		end,
	}
end

-- A crown of fire over the head: a ring of light and flames standing up off it.
function FireFX.Crown(char: Model): (() -> ())?
	local head = char:FindFirstChild("Head") :: BasePart?
	if not head then return nil end
	local made: { Instance } = {}
	local ringBeams = FireFX.FlatRing(head, 0.85, 0.12, GOLD_LINE, 0.1, 1.15)
	for _, b in ipairs(ringBeams) do
		b.FaceCamera = false
		table.insert(made, b.Attachment0 :: Attachment)
		table.insert(made, b.Attachment1 :: Attachment)
	end
	for i = 1, 7 do
		local a = i / 7 * math.pi * 2
		local at = Instance.new("Attachment")
		at.Position = Vector3.new(math.cos(a) * 0.85, 1.2, math.sin(a) * 0.85)
		at.Parent = head
		table.insert(made, at)
		local e = KIND.flame(at, 0.9)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(5, 5)
		e.Speed = NumberRange.new(1.5, 3)
		e.LockedToPart = true
		e.Rate = 10
	end
	return function()
		for _, m in ipairs(made) do
			for _, e in ipairs(m:GetChildren()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
		end
		task.delay(0.6, function() for _, m in ipairs(made) do m:Destroy() end end)
	end
end

-- Wreathe a character in the library's fire aura (Auras/Fire-Aura-01's
-- emitters, limb by limb). Returns a function that puts it out.
function FireFX.Aura(char: Model): () -> ()
	local lib = game:GetService("ReplicatedStorage"):FindFirstChild("Model")
	local auras = lib and lib:FindFirstChild("Auras")
	local src = auras and auras:FindFirstChild("Fire-Aura-01")
	local added: { ParticleEmitter } = {}
	if src then
		for _, limb in ipairs(src:GetChildren()) do
			local part = char:FindFirstChild(limb.Name)
			if part and part:IsA("BasePart") then
				for _, e in ipairs(limb:GetDescendants()) do
					if e:IsA("ParticleEmitter") then
						local c = e:Clone()
						c.Enabled = true
						c.Parent = part
						table.insert(added, c)
					end
				end
			end
		end
	end
	return function()
		for _, e in ipairs(added) do
			e.Enabled = false
			Debris:AddItem(e, 1)
		end
	end
end

-- ── The crash ───────────────────────────────────────────────────────────────
-- Burning feathers bursting out from `pos`.
function FireFX.FeatherBurst(pos: Vector3, count: number, speed: number)
	puff("embers", CFrame.new(pos), 0.3, 1, function(e)
		e.Texture = FEATHER_TEX
		e.Color = ColorSequence.new(Color3.fromRGB(255, 215, 120), Color3.fromRGB(255, 80, 20))
		e.Brightness = 3
		e.Size = NumberSequence.new({ nsk(0, 1.1), nsk(1, 0.7) })
		e.Transparency = NumberSequence.new({ nsk(0, 0), nsk(0.7, 0.2), nsk(1, 1) })
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(speed * 0.5, speed)
		e.Acceleration = Vector3.new(0, -6, 0)
		e.Drag = 2
		e.RotSpeed = NumberRange.new(-120, 120)
		e:Emit(count)
	end)
end

-- Chunks of floor thrown up by the crash, glowing on their broken faces.
function FireFX.Rocks(pos: Vector3, count: number, power: number)
	local g = ground(pos)
	for _ = 1, count do
		local size = Vector3.new(rng:NextNumber(0.6, 1.5), rng:NextNumber(0.5, 1.2), rng:NextNumber(0.6, 1.5))
		local rock = ClassFX.Neon({ Size = size, Material = Enum.Material.Slate, Color = Color3.fromRGB(46, 38, 40),
			CFrame = CFrame.new(g + Vector3.new(0, 0.5, 0)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0) })
		rock.CastShadow = true
		-- (a glowing ember core showing through)
		local glow = ClassFX.Neon({ Size = size * 0.55, Color = Color3.fromRGB(255, 110, 30), CFrame = rock.CFrame })
		local a = rng:NextNumber(0, math.pi * 2)
		local out = Vector3.new(math.cos(a), 0, math.sin(a)) * power * rng:NextNumber(0.4, 1)
		local v = out + Vector3.new(0, power * rng:NextNumber(0.9, 1.6), 0)
		local spin = Vector3.new(rng:NextNumber(-8, 8), rng:NextNumber(-8, 8), rng:NextNumber(-8, 8))
		local start = rock.Position
		local trail = KIND.flame(glow, 0.8)
		trail.Rate = 18
		trail.LockedToPart = false
		trail.Speed = NumberRange.new(0, 0.5)
		local t0 = os.clock()
		local life = rng:NextNumber(0.8, 1.2)
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			local p = start + v * t + Vector3.new(0, -60, 0) * t * t * 0.5
			if p.Y < g.Y + size.Y * 0.4 then p = Vector3.new(p.X, g.Y + size.Y * 0.4, p.Z) end
			local cf = CFrame.new(p) * CFrame.Angles(spin.X * t, spin.Y * t, spin.Z * t)
			rock.CFrame, glow.CFrame = cf, cf
			if t > life then
				if conn then conn:Disconnect() end
				trail.Enabled = false
				TweenService:Create(rock, TweenInfo.new(0.4), { Transparency = 1 }):Play()
				TweenService:Create(glow, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				Debris:AddItem(rock, 0.45)
				Debris:AddItem(glow, 0.8)
			end
		end)
	end
end

-- Fissures of fire tearing outward through the floor from `pos`.
function FireFX.Fissures(pos: Vector3, radius: number, life: number)
	local g = ground(pos) + Vector3.new(0, 0.08, 0)
	local n = 10
	for i = 1, n do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local p = g
		local segs = 4
		for k = 1, segs do
			local len = radius / segs * rng:NextNumber(0.8, 1.25)
			a += rng:NextNumber(-0.4, 0.4)
			local q = p + Vector3.new(math.cos(a), 0, math.sin(a)) * len
			local w = 0.45 * (1 - (k - 1) / segs) + 0.08
			local seg = ClassFX.Neon({ Size = Vector3.new(w, 0.05, len + w), CFrame = CFrame.lookAt((p + q) / 2, q),
				Color = Color3.fromRGB(255, 200, 110), Transparency = 1 })
			TweenService:Create(seg, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, false, k * 0.04),
				{ Transparency = 0 }):Play()
			TweenService:Create(seg, TweenInfo.new(life * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.4),
				{ Transparency = 1, Color = DEEP }):Play()
			Debris:AddItem(seg, life + 0.1)
			if k == segs or rng:NextNumber() < 0.3 then
				-- (fire breaking out along it)
				task.delay(k * 0.05, function()
					puff("flame", CFrame.new(q + Vector3.new(0, 0.5, 0)), 1.5, 1, function(e)
						e.EmissionDirection = Enum.NormalId.Top
						e.Speed = NumberRange.new(2, 5)
					end)
				end)
			end
			p = q
		end
	end
	FireFX.Cracks(g, radius, life, true)
end

-- A pillar of light and fire standing up out of the floor.
function FireFX.LightPillar(pos: Vector3, height: number, width: number, life: number)
	local g = ground(pos)
	local function col(w: number, color: Color3, tr: number)
		local c = ClassFX.Neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, w, w),
			CFrame = CFrame.new(g + Vector3.new(0, height / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = tr })
		TweenService:Create(c, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ Size = Vector3.new(height * 1.15, 0.05, 0.05), Transparency = 1 }):Play()
		Debris:AddItem(c, life + 0.05)
	end
	col(width * 0.35, Color3.fromRGB(255, 240, 200), 0.05)
	col(width, Color3.fromRGB(255, 130, 40), 0.55)
	FireFX.Column(g, height * 0.7, width)
end

return FireFX
