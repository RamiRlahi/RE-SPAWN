--!strict
--[[
	SwordFX.luau
	Ribbon-light effects for the Swordsman, built from Beams so they read like
	painted light rather than blocks:
	  • Arc     a crescent slash: a curved ribbon with a thin fading tail and a
	            bright, thick head, drawn in along the swing, then fading and
	            easing outward. White core over a gold glow.
	  • Streak  a straight comet streak (dashes, Blade Storm trails), optionally
	            as a bundle of thin parallel speed lines.
	  • Rays    a radial burst of light rays + a thin ring (the parry flash).
	  • Blade   a long light blade, fattest at its centre, tapering to points
	            (the Blade Storm X).
	  • Spiral  concentric rotating arcs (Whirlwind).
	All beams face the camera, glow (LightEmission 1) and live in one folder.
	No lights.
--]]

local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local SwordFX = {}

SwordFX.WHITE = Color3.fromRGB(255, 255, 255)
SwordFX.GOLD = Color3.fromRGB(255, 200, 100)
SwordFX.PALE = Color3.fromRGB(255, 238, 200)

local rng = Random.new()

local function folder(): Instance
	return Workspace.Terrain
end

local function att(): Attachment
	local a = Instance.new("Attachment")
	a.Name = "SwordFX"
	a.Parent = folder()
	return a
end

local function beam(a0: Attachment, a1: Attachment, color: Color3): Beam
	local b = Instance.new("Beam")
	b.Attachment0 = a0
	b.Attachment1 = a1
	b.FaceCamera = true
	b.LightEmission = 1
	b.LightInfluence = 0
	b.Segments = 24
	b.Color = ColorSequence.new(color)
	b.Parent = a0
	return b
end

-- Transparency running tail → head: the tail is gone, the head is solid,
-- everything lifted by `fade` (0 = full, 1 = invisible).
local function tailFade(fromT: number, toT: number, fade: number, base: number): NumberSequence
	local function tr(x: number): number
		-- x: position along the whole stroke (0 tail … 1 head).
		local opacity = math.clamp((x - 0.05) / 0.75, 0, 1) * (1 - base) * (1 - fade)
		return math.clamp(1 - opacity, 0, 1)
	end
	return NumberSequence.new({
		NumberSequenceKeypoint.new(0, tr(fromT)),
		NumberSequenceKeypoint.new(1, tr(toT)),
	})
end

local function cleanup(parts: { Instance }, conn: RBXScriptConnection?)
	if conn then conn:Disconnect() end
	for _, p in ipairs(parts) do p:Destroy() end
end

-- ── Arc ─────────────────────────────────────────────────────────────────────
export type ArcOpts = {
	cf: CFrame,        -- centre + facing (arc bulges toward -Z in its XZ plane)
	radius: number,
	arc: number,       -- degrees
	sweep: number?,    -- 1 = right→left (default), -1 = left→right
	width: number,     -- head width (studs)
	color: Color3?,
	life: number?,     -- fade time after it's drawn
	draw: number?,     -- time to draw in along the swing
	grow: number?,     -- radius growth while fading (fraction)
	core: Color3?,     -- the thin bright core (default white)
}

-- Point on the arc at angle `a` (0 = forward, + = toward the left).
local function arcPoint(cf: CFrame, r: number, a: number): Vector3
	return cf:PointToWorldSpace(Vector3.new(-math.sin(a) * r, 0, -math.cos(a) * r))
end

local function arcTangent(cf: CFrame, a: number, sign: number): Vector3
	return cf:VectorToWorldSpace(Vector3.new(-math.cos(a), 0, math.sin(a))) * sign
end

function SwordFX.Arc(o: ArcOpts)
	local color = o.color or SwordFX.GOLD
	local life = o.life or 0.22
	local draw = o.draw or 0.07
	local grow = o.grow or 0.12
	local sign = if (o.sweep or 1) >= 0 then 1 else -1
	local span = math.rad(o.arc)
	local start = -sign * span / 2
	-- Up to 110° per beam piece keeps the Bézier on the circle.
	local pieces = math.max(1, math.ceil(o.arc / 110))
	local up = o.cf.UpVector

	local layers = {} -- { a0, a1, glowBeam, coreBeam } per piece
	local owned: { Instance } = {}
	for i = 1, pieces do
		local a0, a1 = att(), att()
		local c0, c1 = att(), att()
		table.insert(owned, a0); table.insert(owned, a1); table.insert(owned, c0); table.insert(owned, c1)
		layers[i] = { a0 = a0, a1 = a1, c0 = c0, c1 = c1, glow = beam(a0, a1, color), core = beam(c0, c1, o.core or SwordFX.WHITE) }
	end

	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local function step()
		local t = os.clock() - t0
		if t > draw + life then
			cleanup(owned, conn)
			return
		end
		local drawn = math.clamp(t / draw, 0.02, 1)
		local fade = if t > draw then (t - draw) / life else 0
		local r = o.radius * (1 + grow * fade)
		local total = span * drawn
		for i, L in ipairs(layers) do
			local f0, f1 = (i - 1) / pieces, i / pieces
			local ang0 = start + sign * total * f0
			local ang1 = start + sign * total * f1
			local seg = math.abs(ang1 - ang0)
			local handle = 4 / 3 * math.tan(seg / 4) * r
			local p0, p1 = arcPoint(o.cf, r, ang0), arcPoint(o.cf, r, ang1)
			local tan0, tan1 = arcTangent(o.cf, ang0, sign), arcTangent(o.cf, ang1, sign)
			local cf0 = CFrame.fromMatrix(p0, tan0, up)
			local cf1 = CFrame.fromMatrix(p1, tan1, up)
			L.a0.WorldCFrame, L.a1.WorldCFrame = cf0, cf1
			L.c0.WorldCFrame, L.c1.WorldCFrame = cf0, cf1
			-- Control points: A0 + axis0·CurveSize0 and A1 − axis1·CurveSize1,
			-- with both axes along the direction of travel.
			for _, b in ipairs({ L.glow, L.core }) do
				b.CurveSize0 = handle
				b.CurveSize1 = handle
			end
			-- Width grows from tail to head; the glow is wide and soft, the core thin.
			local w0, w1 = o.width * f0 ^ 1.3, o.width * f1 ^ 1.3
			local thin = 1 - fade * 0.7
			L.glow.Width0, L.glow.Width1 = w0 * thin, w1 * thin
			L.core.Width0, L.core.Width1 = w0 * 0.3 * thin, w1 * 0.3 * thin
			L.glow.Transparency = tailFade(f0, f1, fade, 0.35)
			L.core.Transparency = tailFade(f0, f1, fade, 0)
		end
	end
	step()
	conn = RunService.RenderStepped:Connect(step)
end

-- ── Sweep ───────────────────────────────────────────────────────────────────
-- The whole blade's path, not just its edge: a filled crescent band lying in
-- the swing's plane from `inner` (the hilt) to `outer` (the tip), drawn in
-- along the swing with a fading tail, then fading out. Pair it with an Arc
-- at the tip for the bright edge.
export type SweepOpts = {
	cf: CFrame,        -- centre + facing (as Arc)
	inner: number,     -- radius of the hilt
	outer: number,     -- radius of the tip
	arc: number,       -- degrees
	sweep: number?,    -- 1 = right→left (default), -1 = left→right
	color: Color3?,
	life: number?,
	draw: number?,
	opacity: number?,  -- 0..1 at the head (default 0.6)
}

function SwordFX.Sweep(o: SweepOpts)
	local color = o.color or SwordFX.GOLD
	local life = o.life or 0.25
	local draw = o.draw or 0.08
	local opacity = o.opacity or 0.6
	local sign = if (o.sweep or 1) >= 0 then 1 else -1
	local span = math.rad(o.arc)
	local start = -sign * span / 2
	local pieces = math.max(1, math.ceil(o.arc / 90))
	local mid = (o.inner + o.outer) / 2
	local band = o.outer - o.inner

	local layers = {}
	local owned: { Instance } = {}
	for i = 1, pieces do
		local a0, a1 = att(), att()
		table.insert(owned, a0); table.insert(owned, a1)
		local b = beam(a0, a1, color)
		b.FaceCamera = false -- lies flat in the swing's plane (width runs radially)
		b.Segments = 20
		layers[i] = { a0 = a0, a1 = a1, beam = b }
	end

	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local function step()
		local t = os.clock() - t0
		if t > draw + life then
			cleanup(owned, conn)
			return
		end
		local drawn = math.clamp(t / draw, 0.02, 1)
		local fade = if t > draw then (t - draw) / life else 0
		local total = span * drawn
		for i, L in ipairs(layers) do
			local f0, f1 = (i - 1) / pieces, i / pieces
			local ang0 = start + sign * total * f0
			local ang1 = start + sign * total * f1
			local seg = math.abs(ang1 - ang0)
			local handle = 4 / 3 * math.tan(seg / 4) * mid
			local p0, p1 = arcPoint(o.cf, mid, ang0), arcPoint(o.cf, mid, ang1)
			local tan0, tan1 = arcTangent(o.cf, ang0, sign), arcTangent(o.cf, ang1, sign)
			-- Y axis radial, so the beam's width spans hilt → tip.
			local rad0 = (p0 - o.cf.Position).Unit
			local rad1 = (p1 - o.cf.Position).Unit
			L.a0.WorldCFrame = CFrame.fromMatrix(p0, tan0, rad0)
			L.a1.WorldCFrame = CFrame.fromMatrix(p1, tan1, rad1)
			L.beam.CurveSize0 = handle
			L.beam.CurveSize1 = handle
			L.beam.Width0, L.beam.Width1 = band, band
			L.beam.Transparency = tailFade(f0, f1, fade, 1 - opacity)
		end
	end
	step()
	conn = RunService.RenderStepped:Connect(step)
end

-- ── Streak ──────────────────────────────────────────────────────────────────
-- A comet streak from `a` (tail) to `b` (head). `lines` > 1 adds that many
-- thin parallel speed lines around it.
function SwordFX.Streak(a: Vector3, b: Vector3, width: number, color: Color3?, linger: number?, lines: number?, core: Color3?)
	local c = color or SwordFX.GOLD
	local hot = core or SwordFX.WHITE
	local hold = linger or 0.1
	local dir = b - a
	if dir.Magnitude < 0.2 then return end
	local side = dir.Unit:Cross(Vector3.yAxis)
	if side.Magnitude < 0.1 then side = Vector3.xAxis end
	side = side.Unit
	local owned: { Instance } = {}
	local set: { { beam: Beam, w: number, base: number } } = {}
	local function add(from: Vector3, to: Vector3, w: number, col: Color3, base: number)
		local a0, a1 = att(), att()
		a0.WorldPosition, a1.WorldPosition = from, to
		table.insert(owned, a0); table.insert(owned, a1)
		local bm = beam(a0, a1, col)
		bm.Segments = 2
		table.insert(set, { beam = bm, w = w, base = base })
	end
	add(a, b, width, c, 0.4)
	add(a, b, width * 0.3, hot, 0)
	for _ = 1, (lines or 1) - 1 do
		local off = side * rng:NextNumber(-width * 2.2, width * 2.2) + Vector3.new(0, rng:NextNumber(-0.6, 0.6), 0)
		local len0 = rng:NextNumber(0, 0.35)
		add(a:Lerp(b, len0) + off, b + off * 0.6, width * rng:NextNumber(0.08, 0.18), if rng:NextNumber() < 0.5 then hot else c, 0.1)
	end
	local life = 0.2
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local function step()
		local t = os.clock() - t0
		if t > hold + life then
			cleanup(owned, conn)
			return
		end
		local fade = math.clamp((t - hold) / life, 0, 1)
		for _, s in ipairs(set) do
			s.beam.Width0 = s.w * 0.05 * (1 - fade)
			s.beam.Width1 = s.w * (1 - fade * 0.8)
			s.beam.Transparency = tailFade(0, 1, fade, s.base)
		end
	end
	step()
	conn = RunService.RenderStepped:Connect(step)
end

-- ── Rays ────────────────────────────────────────────────────────────────────
-- A radial light burst at `pos` (flat on the ground plane) plus a thin ring.
function SwordFX.Rays(pos: Vector3, radius: number, count: number, color: Color3?, life: number?)
	local c = color or SwordFX.GOLD
	local dur = life or 0.35
	local owned: { Instance } = {}
	local rays: { { beam: Beam, a0: Attachment, a1: Attachment, dir: Vector3, len: number } } = {}
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local a0, a1 = att(), att()
		table.insert(owned, a0); table.insert(owned, a1)
		local bm = beam(a0, a1, if i % 2 == 0 then SwordFX.WHITE else c)
		bm.Segments = 2
		table.insert(rays, { beam = bm, a0 = a0, a1 = a1, dir = dir, len = radius * rng:NextNumber(0.6, 1) })
	end
	SwordFX.Arc({ cf = CFrame.new(pos), radius = radius * 0.55, arc = 359, width = 0.35, color = SwordFX.WHITE, draw = 0.001, life = dur, grow = 0.6 })
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local function step()
		local t = os.clock() - t0
		if t > dur then
			cleanup(owned, conn)
			return
		end
		local k = t / dur
		for _, r in ipairs(rays) do
			local inner = r.len * (0.15 + 0.5 * k)
			local outer = r.len * (0.45 + 0.55 * math.sqrt(k))
			r.a0.WorldPosition = pos + r.dir * inner
			r.a1.WorldPosition = pos + r.dir * outer
			r.beam.Width0, r.beam.Width1 = 0.5 * (1 - k), 0.05
			r.beam.Transparency = NumberSequence.new(k * 0.9, math.min(1, 0.3 + k))
		end
	end
	step()
	conn = RunService.RenderStepped:Connect(step)
end

-- ── Blade ───────────────────────────────────────────────────────────────────
-- A long blade of light through `center` along `dir`, fattest in the middle
-- and tapering to points; it slashes out from the centre, holds, then thins.
function SwordFX.Blade(center: Vector3, dir: Vector3, length: number, width: number, color: Color3?, hold: number?)
	local c = color or SwordFX.GOLD
	local keep = hold or 0.3
	local owned: { Instance } = {}
	local halves = {}
	for _, s in ipairs({ 1, -1 }) do
		local a0, a1 = att(), att()
		local c0, c1 = att(), att()
		table.insert(owned, a0); table.insert(owned, a1); table.insert(owned, c0); table.insert(owned, c1)
		local g, k = beam(a0, a1, c), beam(c0, c1, SwordFX.WHITE)
		g.Segments, k.Segments = 2, 2
		table.insert(halves, { s = s, a0 = a0, a1 = a1, c0 = c0, c1 = c1, g = g, k = k })
	end
	local open, fadeT = 0.1, 0.35
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local function step()
		local t = os.clock() - t0
		if t > open + keep + fadeT then
			cleanup(owned, conn)
			return
		end
		local grow = math.clamp(t / open, 0, 1)
		local fade = math.clamp((t - open - keep) / fadeT, 0, 1)
		for _, h in ipairs(halves) do
			local tip = center + dir * h.s * (length / 2) * (1 - (1 - grow) ^ 3)
			h.a0.WorldPosition, h.a1.WorldPosition = center, tip
			h.c0.WorldPosition, h.c1.WorldPosition = center, tip
			h.g.Width0, h.g.Width1 = width * (1 - fade * 0.8), 0
			h.k.Width0, h.k.Width1 = width * 0.35 * (1 - fade), 0
			h.g.Transparency = NumberSequence.new(0.25 + fade * 0.75, 1)
			h.k.Transparency = NumberSequence.new(fade, math.min(1, 0.4 + fade))
		end
	end
	step()
	conn = RunService.RenderStepped:Connect(step)
end

-- ── Spiral ──────────────────────────────────────────────────────────────────
-- Concentric arcs whirling round `getCenter()` for `duration` (Whirlwind).
function SwordFX.Spiral(getCenter: () -> Vector3?, radius: number, duration: number, color: Color3?)
	local c = color or SwordFX.GOLD
	local t0 = os.clock()
	local rings = { 0.45, 0.72, 1 }
	task.spawn(function()
		local i = 0
		while os.clock() - t0 < duration do
			local center = getCenter()
			if not center then return end
			i += 1
			local r = rings[(i % #rings) + 1]
			local spin = (os.clock() - t0) * 900 + i * 47
			SwordFX.Arc({
				cf = CFrame.new(center) * CFrame.Angles(0, math.rad(spin), 0),
				radius = radius * r, arc = 170, sweep = 1, width = 0.9 * r + 0.3,
				color = if i % 3 == 0 then SwordFX.WHITE else c, draw = 0.06, life = 0.2, grow = 0.08,
			})
			task.wait(0.06)
		end
	end)
end

-- Sparkle stars flying outward (debris / glints).
function SwordFX.Stars(pos: Vector3, count: number, speed: number, color: Color3?)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = pos
	anchor.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(SwordFX.WHITE, color or SwordFX.GOLD)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.3, 0.6)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 30)
	e.Drag = 4
	e.Rate = 0
	e.Parent = anchor
	e:Emit(count)
	Debris:AddItem(anchor, 1)
end

return SwordFX
