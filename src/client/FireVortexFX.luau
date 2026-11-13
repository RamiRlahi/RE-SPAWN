--!strict
--[[
	FireVortexFX.luau
	The fire vortex (the Fire Knight's Fire Tornado): a compact, extremely
	bright fire core inside a chaotic sphere of sweeping energy ribbons, sharp
	streaks shooting past the silhouette, embers and sparks, and a wide ground
	ring with energy trails turning on the floor. Tuned in FireVortexConfig.

	  local h = FireVortexFX.Start(getFloor, R, dur)
	      getFloor() -> the floor point under it each frame (nil = it ends)
	      R          the vortex radius (studs)
	      dur        seconds until it explodes on its own
	  h.stop()       explode now

	Sequence: ignition (the core flashes up, the ground ring snaps out) ->
	formation (the ribbons sweep in from the core) -> sustain -> explosion
	(ribbons and streaks fling outward and burn out, the ring blows out).

	Built from:
	  ribbons  Beams on Attachments: each ribbon is a smooth arc of curved Beam
	           segments (bezier handles along each attachment's X axis), its own
	           orbit plane (horizontal / vertical / diagonal), speed, tumble and
	           phase; the Energy texture (yellow-white centre -> orange body ->
	           red-orange edges) streams along it
	  streaks  thin two-segment Beams flicking out past the silhouette
	  core     ParticleEmitters: a white-hot glow, upward flame tongues, a
	           little smoke, embers and sparks; small flame bursts
	  ground   a flat ring and flat trails (FaceCamera off) turning on the floor

	Budget (CLAUDE.md): one vortex per cast, not per hit; counts and rates
	shrink with FxBudget.Pressure() and Low Detail VFX. Its instances opt out
	of VfxDetail's blanket toning (VfxToned set up front: it would fade the
	ribbons to near-invisible) and are all destroyed when it ends.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxAssets"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local VariantFX = require(script.Parent:WaitForChild("VariantFX"))
local VfxKit = require(script.Parent:WaitForChild("VfxKit"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local Config = require(script.Parent:WaitForChild("FireVortexConfig"))

local FireVortexFX = {}

local player = Players.LocalPlayer
local TAU = math.pi * 2
local rng = Random.new()

local function nsk(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end
local function csk(t: number, c: Color3): ColorSequenceKeypoint
	return ColorSequenceKeypoint.new(t, c)
end
local function range(r: { number }): number
	return rng:NextNumber(r[1], r[2])
end
local function ease(t: number): number -- quart out
	return 1 - (1 - math.clamp(t, 0, 1)) ^ 4
end

-- (VfxDetail tones what it hasn't seen yet; this marks an instance as done)
local function untoned(inst: Instance)
	inst:SetAttribute("VfxToned", true)
end

local function newBeam(a0: Attachment, a1: Attachment, texture: string, faceCamera: boolean): Beam
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = faceCamera
	b.Texture = texture
	b.TextureMode = Enum.TextureMode.Wrap
	b.LightInfluence = 0
	b.Segments = 10
	untoned(b)
	b.Parent = a0
	return b
end

local function lerpColor(stops: { Color3 }, x: number): Color3
	local n = #stops - 1
	local f = math.clamp(x, 0, 1) * n
	local i = math.min(math.floor(f), n - 1)
	return stops[i + 1]:Lerp(stops[i + 2], f - i)
end

-- An orbit plane for a ribbon: rotation only; the orbit is its XZ plane.
local function orbitFrame(kind: string): CFrame
	local yaw = rng:NextNumber(0, TAU)
	local tilt
	if kind == "horizontal" then
		tilt = rng:NextNumber(-15, 15)
	elseif kind == "vertical" then
		tilt = 90 + rng:NextNumber(-15, 15)
	else
		tilt = (if rng:NextNumber() < 0.5 then 1 else -1) * rng:NextNumber(35, 55)
	end
	return CFrame.Angles(0, yaw, 0) * CFrame.Angles(math.rad(tilt), 0, 0)
end

function FireVortexFX.Start(getFloor: () -> Vector3?, R: number, dur: number): { stop: () -> () }
	local floor0 = getFloor()
	if not floor0 then return { stop = function() end } end

	-- the caster's VFX variant (the ink "dark" one gets the ink ribbons)
	local owner = VariantFX.OwnerNear(floor0)
	local pal = owner and VariantFX.PaletteFor(owner)
	local ink = pal ~= nil and pal.ink == true
	local energyTex = ((VfxAssets :: any).Energy[if ink then "ink" else "fire"] or (VfxAssets :: any).Energy.fire).id

	-- how much of it to draw (frame-rate pressure, Low Detail VFX)
	local low = player:GetAttribute("Setting_lowDetailVFX") == true or player:GetAttribute("PerfMode") == true
	local cut = 1 - Config.PressureCut * math.max(FxBudget.Pressure(), if low then 0.7 else 0)

	local C = Config
	local folder = Instance.new("Folder")
	folder.Name = "FireVortexFX"
	-- one anchored holder at the origin: every attachment's CFrame is world space
	local holder = Instance.new("Part")
	holder.Name = "Holder"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.identity
	untoned(holder)
	holder.Parent = folder

	local function att(): Attachment
		local a = Instance.new("Attachment")
		a.Parent = holder
		return a
	end

	local ribbonStops = if ink then { Color3.new(1, 1, 1), Color3.new(1, 1, 1), Color3.new(1, 1, 1) }
		else { C.Colors.ribbonHead, C.Colors.ribbonMid, C.Colors.ribbonTail }

	-- ── ribbons ─────────────────────────────────────────────────────────────
	type Ribbon = {
		atts: { Attachment }, beams: { Beam }, frame: CFrame, axis: Vector3, precess: number,
		radius: number, arc: number, speed: number, phase: number, width: number, wob: number,
	}
	local ribbons: { Ribbon } = {}
	local RC = C.Ribbons
	local nRibbons = math.max(5, math.floor(RC.count * cut + 0.5))
	for k = 1, nRibbons do
		local r: Ribbon = {
			atts = {}, beams = {},
			frame = orbitFrame(RC.orientations[(k - 1) % #RC.orientations + 1]),
			axis = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-1, 1), rng:NextNumber(-1, 1)).Unit,
			precess = range(RC.precess) * TAU * (if rng:NextNumber() < 0.5 then 1 else -1),
			radius = range(RC.radius) * R,
			arc = math.rad(range(RC.arc)),
			speed = range(RC.speed) * TAU * (if k % 3 == 0 then -1 else 1),
			phase = rng:NextNumber(0, TAU),
			width = range(RC.width) * R,
			wob = rng:NextNumber(0, TAU),
		}
		for _ = 1, RC.points do table.insert(r.atts, att()) end
		local P = RC.points
		-- a crescent: pointed at the head, fullest a third along, tapering to a
		-- thin tail (never a plank of even width)
		local function widthAt(x: number): number
			return r.width * (0.06 + 0.94 * math.sin(math.pi * x ^ 0.75) ^ 0.9 * (1 - 0.55 * x))
		end
		for i = 1, P - 1 do
			local x0, x1 = (i - 1) / (P - 1), i / (P - 1)
			local b = newBeam(r.atts[i], r.atts[i + 1], energyTex, true)
			b.Width0 = widthAt(x0)
			b.Width1 = widthAt(x1)
			b.Color = ColorSequence.new(lerpColor(ribbonStops, x0), lerpColor(ribbonStops, x1))
			b.Brightness = RC.brightness
			b.LightEmission = if ink then 0 else RC.lightEmission
			b.TextureLength = R * 0.9
			b.TextureSpeed = RC.textureSpeed
			table.insert(r.beams, b)
		end
		table.insert(ribbons, r)
	end

	-- ── streaks ─────────────────────────────────────────────────────────────
	type Streak = { atts: { Attachment }, beams: { Beam }, dir: Vector3, curl: Vector3, from: number, len: number,
		width: number, age: number, life: number, burst: boolean }
	local streaks: { Streak } = {}
	local SC = C.Streaks
	local streakColor = if ink then Color3.new(1, 1, 1) else C.Colors.streak
	local function rollStreak(s: Streak, burst: boolean)
		local d = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.55, 0.75), rng:NextNumber(-1, 1))
		s.dir = if d.Magnitude > 0.05 then d.Unit else Vector3.xAxis
		local side = Vector3.yAxis:Cross(s.dir)
		s.curl = (if side.Magnitude > 0.05 then side.Unit else Vector3.zAxis) * SC.bend
		s.from = range(SC.from) * R
		s.len = range(SC.length) * R * (if burst then 1.6 else 1)
		s.width = range(SC.width) * R
		s.age = 0
		s.life = range(SC.life) * (if burst then 1.3 else 1)
		s.burst = burst
		s.beams[1].Width0, s.beams[1].Width1 = s.width, s.width * 0.6
		s.beams[2].Width0, s.beams[2].Width1 = s.width * 0.6, 0
	end
	local function newStreak(burst: boolean): Streak
		local s: Streak = { atts = { att(), att(), att() }, beams = {}, dir = Vector3.xAxis, curl = Vector3.zero,
			from = 0, len = 0, width = 0, age = 0, life = 1, burst = burst }
		for i = 1, 2 do
			local b = newBeam(s.atts[i], s.atts[i + 1], energyTex, true)
			b.Color = ColorSequence.new(streakColor)
			b.Brightness = SC.brightness
			b.LightEmission = if ink then 0 else 1
			b.TextureLength = R
			b.TextureSpeed = 4
			b.Segments = 2
			table.insert(s.beams, b)
		end
		rollStreak(s, burst)
		s.age = if burst then 0 else rng:NextNumber(0, s.life)
		table.insert(streaks, s)
		return s
	end
	for _ = 1, math.floor(SC.count * cut + 0.5) do newStreak(false) end

	-- ── core ────────────────────────────────────────────────────────────────
	local CC = C.Core
	local core = Instance.new("Part")
	core.Name = "Core"
	core.Anchored, core.CanCollide, core.CanQuery, core.CanTouch, core.CastShadow = true, false, false, false, false
	core.Transparency = 1
	core.Size = Vector3.new(R * 0.45, R * 0.35, R * 0.45)
	untoned(core)
	core.Parent = folder
	local emitters: { ParticleEmitter } = {}
	local function emitter(props: { [string]: any }): ParticleEmitter
		local e = Instance.new("ParticleEmitter")
		e.LightInfluence = 0
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		for k, v in pairs(props) do (e :: any)[k] = v end
		untoned(e)
		e.Parent = core
		table.insert(emitters, e)
		return e
	end
	local glow = emitter({
		Name = "CoreGlow", Texture = VfxAssets.Glow.soft.id, Color = ColorSequence.new(C.Colors.coreHot),
		LightEmission = 1, Brightness = 2.2, ZOffset = 0.6,
		Size = NumberSequence.new({ nsk(0, R * CC.glowSize * 0.8), nsk(0.5, R * CC.glowSize), nsk(1, R * CC.glowSize * 0.85) }),
		Transparency = NumberSequence.new({ nsk(0, 0.25), nsk(0.5, 0.15), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.25, 0.35), Speed = NumberRange.new(0), Rate = CC.glowRate,
	})
	local flames = emitter({
		Name = "CoreFlames", Texture = FireFX.TEX.flame,
		FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4, FlipbookMode = Enum.ParticleFlipbookMode.OneShot,
		Color = ColorSequence.new({ csk(0, C.Colors.coreHot), csk(0.4, C.Colors.coreFlame), csk(1, C.Colors.ribbonTail) }),
		LightEmission = 0.4, Brightness = 2.4, ZOffset = 0.4,
		Size = NumberSequence.new({ nsk(0, R * CC.flameSize * 0.6), nsk(0.35, R * CC.flameSize), nsk(1, R * CC.flameSize * 0.5) }),
		Transparency = NumberSequence.new({ nsk(0, 0.05), nsk(0.7, 0.2), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.4, 0.6), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(14, 14),
		Speed = NumberRange.new(R * CC.flameRise * 0.6, R * CC.flameRise), Acceleration = Vector3.new(0, R * 0.8, 0),
		Drag = 1.5, Rotation = NumberRange.new(-10, 10), Rate = CC.flameRate * cut,
	})
	emitter({
		Name = "CoreSmoke", Texture = FireFX.TEX.smoke, Color = ColorSequence.new(C.Colors.smoke),
		LightEmission = 0, Size = NumberSequence.new({ nsk(0, R * 0.5), nsk(1, R * 0.9) }),
		Transparency = NumberSequence.new({ nsk(0, 0.7), nsk(1, 1) }),
		Lifetime = NumberRange.new(0.8, 1.2), EmissionDirection = Enum.NormalId.Top, SpreadAngle = Vector2.new(20, 20),
		Speed = NumberRange.new(R * 1.2, R * 1.8), Rate = CC.smokeRate * cut,
	})
	local PC = C.Particles
	emitter({
		Name = "Embers", Texture = FireFX.TEX.specs, Color = ColorSequence.new(C.Colors.ember, C.Colors.ribbonTail),
		LightEmission = 1, Brightness = 4, Size = NumberSequence.new({ nsk(0, 0), nsk(0.2, PC.emberSize), nsk(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.1), SpreadAngle = Vector2.new(180, 180),
		Speed = NumberRange.new(R * 0.8, R * 2.2), Drag = 2, Acceleration = Vector3.new(0, R * 0.6, 0),
		Rate = PC.embers * cut,
	})
	emitter({
		Name = "Sparks", Texture = (VfxAssets.Spark :: any)[if ink then "ink" else "fire"].id,
		Color = ColorSequence.new(Color3.new(1, 1, 1)), LightEmission = 1, Brightness = 4,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Rotation = NumberRange.new(90),
		Size = NumberSequence.new({ nsk(0, 1.4), nsk(1, 0.3) }),
		Lifetime = NumberRange.new(0.15, 0.3), SpreadAngle = Vector2.new(180, 180),
		Speed = NumberRange.new(PC.sparkSpeed[1], PC.sparkSpeed[2]), Drag = 3, Rate = PC.sparks * cut,
	})

	-- ── ground ──────────────────────────────────────────────────────────────
	local GC = C.Ground
	local groundColor = if ink then Color3.new(1, 1, 1) else C.Colors.ground
	local RING_N = 8
	local ringAtts: { Attachment } = {}
	for _ = 1, RING_N do table.insert(ringAtts, att()) end
	local ringBeams: { Beam } = {}
	for i = 1, RING_N do
		local b = newBeam(ringAtts[i], ringAtts[i % RING_N + 1], energyTex, false)
		b.Width0, b.Width1 = GC.width * R, GC.width * R
		b.Color = ColorSequence.new(groundColor)
		b.Brightness = 2
		b.LightEmission = if ink then 0 else 1
		b.TextureLength = R * 1.2
		b.TextureSpeed = 2
		table.insert(ringBeams, b)
	end
	type Trail = { atts: { Attachment }, beams: { Beam }, radius: number, speed: number, phase: number }
	local trails: { Trail } = {}
	for k = 1, GC.trails do
		local tr: Trail = { atts = { att(), att(), att(), att() }, beams = {}, radius = range(GC.trailRadius) * R,
			speed = range(GC.trailSpeed) * TAU, phase = k / GC.trails * TAU }
		for i = 1, 3 do
			local b = newBeam(tr.atts[i], tr.atts[i + 1], energyTex, false)
			local x0, x1 = (i - 1) / 3, i / 3
			b.Width0, b.Width1 = GC.trailWidth * R * (1 - 0.8 * x0), GC.trailWidth * R * (1 - 0.8 * x1)
			b.Color = ColorSequence.new(lerpColor(ribbonStops, x0), lerpColor(ribbonStops, x1))
			b.Brightness = 2.2
			b.LightEmission = if ink then 0 else 1
			b.TextureLength = R
			b.TextureSpeed = 3
			table.insert(tr.beams, b)
		end
		table.insert(trails, tr)
	end
	-- a soft glow on the floor under it (not a disc: a faint, fading tint)
	local floorGlow = Instance.new("ParticleEmitter")
	floorGlow.Texture = VfxAssets.Glow.wide.id
	floorGlow.Color = ColorSequence.new(if ink then Color3.new(0, 0, 0) else C.Colors.ground)
	floorGlow.LightEmission = if ink then 0 else 1
	floorGlow.LightInfluence = 0
	floorGlow.Brightness = 1.2
	floorGlow.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	floorGlow.EmissionDirection = Enum.NormalId.Top
	floorGlow.Speed = NumberRange.new(0.01)
	floorGlow.SpreadAngle = Vector2.zero
	floorGlow.Size = NumberSequence.new(R * GC.glowSize)
	floorGlow.Transparency = NumberSequence.new({ nsk(0, 0.6), nsk(0.5, 0.65), nsk(1, 1) })
	floorGlow.Lifetime = NumberRange.new(0.5)
	floorGlow.Rate = 6
	floorGlow.LockedToPart = false
	untoned(floorGlow)
	local floorAtt = att()
	floorGlow.Parent = floorAtt
	table.insert(emitters, floorGlow)

	folder.Parent = Workspace

	-- ── animation ───────────────────────────────────────────────────────────
	local PH = C.Phases
	local endAt = dur
	local now = 0
	local exploded = false
	local nextBurst = PH.ignition
	local lastTr = -1
	local spin = 0
	VfxKit.Flash(floor0 + Vector3.new(0, R * C.CenterHeight, 0), if ink then "ink" else "fire", R * 2.2, 0.12)

	local function setTransparency(beams: { Beam }, tr: number)
		local seq = NumberSequence.new(tr)
		for _, b in ipairs(beams) do b.Transparency = seq end
	end

	local conn: RBXScriptConnection
	local function cleanup()
		conn:Disconnect()
		for _, e in ipairs(emitters) do e.Enabled = false end
		task.delay(1.3, function() folder:Destroy() end)
	end

	conn = RunService.RenderStepped:Connect(function(dt)
		now += dt
		local t = now
		local floor = getFloor()
		if not floor then
			endAt = math.min(endAt, t)
			floor = floor0
		end
		floor0 = floor :: Vector3
		local center = floor0 + Vector3.new(0, R * C.CenterHeight, 0)
		core.CFrame = CFrame.new(center)
		floorAtt.WorldPosition = floor0 + Vector3.new(0, 0.15, 0)

		-- phase envelopes
		local ign = ease(t / PH.ignition)
		local form = ease((t - PH.ignition) / PH.formation)
		local boom = math.clamp((t - endAt) / PH.explosion, 0, 1)
		if t >= endAt and not exploded then
			exploded = true
			for _, e in ipairs(emitters) do e.Enabled = false end
			for _ = 1, math.floor(C.Explosion.burstStreaks * cut) do newStreak(true) end
			VfxKit.Flash(center, if ink then "ink" else "fire", R * 2.6, 0.13)
		end
		if boom >= 1 then
			cleanup()
			return
		end
		local fling = 1 + (C.Explosion.fling - 1) * ease(boom)
		local fade = boom ^ 0.8

		-- the core: swells past full on ignition (1.3x), settles
		local coreK = (0.3 + 1.0 * ign) * (1 + 0.3 * math.max(0, 1 - t / (PH.ignition * 2.5)))
		glow.Size = NumberSequence.new({ nsk(0, R * CC.glowSize * 0.8 * coreK), nsk(0.5, R * CC.glowSize * coreK), nsk(1, R * CC.glowSize * 0.85 * coreK) })
		if not exploded and t >= nextBurst then
			nextBurst = t + CC.burstEvery * rng:NextNumber(0.7, 1.3)
			local o = Vector3.new(rng:NextNumber(-1, 1), rng:NextNumber(-0.3, 1), rng:NextNumber(-1, 1)) * R * 0.35
			VfxKit.Puffs({ center + o }, if ink then "ink" else "fire", R * 0.55, 0.4)
		end

		-- ribbons
		local P = RC.points
		local trR = math.max(1 - form, fade)
		for _, r in ipairs(ribbons) do
			local O = CFrame.fromAxisAngle(r.axis, r.precess * t) * r.frame
			local up = O.UpVector
			local head = r.phase + r.speed * t
			local arc = r.arc * (0.3 + 0.7 * form)
			local rad = r.radius * (0.2 + 0.8 * form) * fling * (1 + RC.wobble * math.sin(t * 3.1 + r.wob))
			local step = arc / (P - 1)
			local handle = 4 / 3 * math.tan(step / 4)
			for j = 1, P do
				local x = (j - 1) / (P - 1)
				local th = head - arc * x
				local rj = rad * (1 - RC.spiralIn * x)
				local pos = center + O:VectorToWorldSpace(Vector3.new(math.cos(th) * rj, 0, math.sin(th) * rj))
				local along = O:VectorToWorldSpace(Vector3.new(math.sin(th), 0, -math.cos(th)))
				r.atts[j].WorldCFrame = CFrame.fromMatrix(pos, along, up)
			end
			for _, b in ipairs(r.beams) do
				b.CurveSize0 = handle * rad
				b.CurveSize1 = handle * rad * (1 - RC.spiralIn / (P - 1))
			end
		end
		-- (transparency only written while it changes: formation, explosion)
		local q = math.floor(trR * 20 + 0.5) / 20
		if q ~= lastTr then
			lastTr = q
			for _, r in ipairs(ribbons) do setTransparency(r.beams, q) end
			for _, tr in ipairs(trails) do setTransparency(tr.beams, q) end
		end

		-- streaks: flick out, hold, fade; then again somewhere else
		for i = #streaks, 1, -1 do
			local s = streaks[i]
			s.age += dt
			if s.age >= s.life then
				if s.burst or exploded then
					for _, a in ipairs(s.atts) do a:Destroy() end
					table.remove(streaks, i)
					continue
				end
				rollStreak(s, false)
			end
			local x = s.age / s.life
			local grow = ease(x / 0.3)
			local a0 = center + s.dir * s.from * (if s.burst then 1 else fling)
			local reach = s.len * grow
			local a2 = a0 + (s.dir + s.curl).Unit * reach
			local a1 = a0:Lerp(a2, 0.5) + s.curl * reach * 0.25
			s.atts[1].WorldPosition, s.atts[2].WorldPosition, s.atts[3].WorldPosition = a0, a1, a2
			local str = math.clamp(math.max(1 - form, (x - 0.6) / 0.4, if s.burst then 0 else fade), 0, 1)
			local seq = NumberSequence.new(str)
			s.beams[1].Transparency, s.beams[2].Transparency = seq, seq
		end

		-- the ground: a ring snapping out on ignition and blowing out at the end,
		-- trails chasing round inside it
		spin += dt * GC.spin * TAU
		local ringR = GC.radius * R * (0.4 + 0.6 * ign) * (1 + 0.5 * ease(boom))
		local gy = floor0.Y + 0.2
		local segA = TAU / RING_N
		local ringHandle = 4 / 3 * math.tan(segA / 4) * ringR
		for i = 1, RING_N do
			local a = spin + (i - 1) * segA
			local pos = Vector3.new(floor0.X + math.cos(a) * ringR, gy, floor0.Z + math.sin(a) * ringR)
			local tang = Vector3.new(-math.sin(a), 0, math.cos(a))
			ringAtts[i].WorldCFrame = CFrame.fromMatrix(pos, tang, Vector3.new(-tang.Z, 0, tang.X))
		end
		local ringTr = math.max(1 - ign, fade)
		for _, b in ipairs(ringBeams) do
			b.CurveSize0, b.CurveSize1 = ringHandle, ringHandle
			b.Transparency = NumberSequence.new(0.1 + 0.9 * ringTr)
		end
		local tArc = math.rad(GC.trailArc)
		for _, tr in ipairs(trails) do
			local headA = tr.phase + tr.speed * t
			local tr_r = tr.radius * (0.4 + 0.6 * ign) * fling
			local stepA = tArc / 3
			local h = 4 / 3 * math.tan(stepA / 4) * tr_r
			for j = 1, 4 do
				local a = headA - stepA * (j - 1)
				local pos = Vector3.new(floor0.X + math.cos(a) * tr_r, gy + 0.05, floor0.Z + math.sin(a) * tr_r)
				local tang = Vector3.new(math.sin(a), 0, -math.cos(a))
				tr.atts[j].WorldCFrame = CFrame.fromMatrix(pos, tang, Vector3.new(-tang.Z, 0, tang.X))
			end
			for _, b in ipairs(tr.beams) do b.CurveSize0, b.CurveSize1 = h, h end
		end
	end)

	return {
		stop = function()
			endAt = math.min(endAt, now)
		end,
	}
end

return FireVortexFX
