--!strict
--[[
	MenuForest.luau
	Low-poly pieces for the title screen's forest clearing (MenuBackdrop),
	after the golden-hour key art: faceted tree crowns, pines, rocks, a misty
	valley of round trees and the hill the castle stands on.

	Facets are real triangles (two WedgeParts each, flat SmoothPlastic), so
	every face catches the light on its own like the art's low-poly look.

	MenuForest.Tri(parent, a, b, c, color, material?)
	MenuForest.Blob(parent, center, size, color, rng, opts?)  -- a faceted ball
	MenuForest.Tree(parent, base, h, rng, opts?)              -- broadleaf
	MenuForest.Pine(parent, base, h, rng, opts?)
	MenuForest.Valley(parent, frame, rng) -> castle site      -- the far view
--]]

local MenuForest = {}

local THICK = 0.06
local SMOOTH = Enum.Material.SmoothPlastic

local function bare(className: string): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	return p
end

-- One flat triangle a-b-c.
function MenuForest.Tri(parent: Instance, a: Vector3, b: Vector3, c: Vector3, color: Color3, material: Enum.Material?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local cr = ac:Cross(ab)
	if cr.Magnitude < 1e-6 then return end
	local right = cr.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	if height < 0.02 then return end
	local mat = material or SMOOTH
	local w1 = bare("WedgePart")
	w1.Size = Vector3.new(THICK, height, math.max(math.abs(ab:Dot(back)), 0.02))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	w1.Color = color
	w1.Material = mat
	w1.Parent = parent
	local w2 = bare("WedgePart")
	w2.Size = Vector3.new(THICK, height, math.max(math.abs(ac:Dot(back)), 0.02))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	w2.Color = color
	w2.Material = mat
	w2.Parent = parent
end
local tri = MenuForest.Tri

-- A block from `p0` to `p1` (its long axis), `w` thick; with `oct`, a second
-- block turned 45° makes it an eight-sided post (a faceted trunk or branch).
function MenuForest.Post(parent: Instance, p0: Vector3, p1: Vector3, w: number, color: Color3, oct: boolean?): BasePart
	local dir = p1 - p0
	local len = dir.Magnitude
	local y = dir.Unit
	local x = y:Cross(Vector3.zAxis)
	if x.Magnitude < 0.1 then x = y:Cross(Vector3.xAxis) end
	x = x.Unit
	local cf = CFrame.fromMatrix((p0 + p1) / 2, x, y)
	local b = bare("Part")
	b.Size = Vector3.new(w, len, w)
	b.CFrame = cf
	b.Color = color
	b.Material = SMOOTH
	b.Parent = parent
	if oct then
		local b2 = bare("Part")
		b2.Size = Vector3.new(w, len, w)
		b2.CFrame = cf * CFrame.Angles(0, math.pi / 4, 0)
		b2.Color = color:Lerp(Color3.new(0, 0, 0), 0.12)
		b2.Material = SMOOTH
		b2.Parent = parent
	end
	return b
end
local post = MenuForest.Post

-- ── Faceted balls ───────────────────────────────────────────────────────────
local T = (1 + math.sqrt(5)) / 2
local ICO_V = {
	Vector3.new(-1, T, 0), Vector3.new(1, T, 0), Vector3.new(-1, -T, 0), Vector3.new(1, -T, 0),
	Vector3.new(0, -1, T), Vector3.new(0, 1, T), Vector3.new(0, -1, -T), Vector3.new(0, 1, -T),
	Vector3.new(T, 0, -1), Vector3.new(T, 0, 1), Vector3.new(-T, 0, -1), Vector3.new(-T, 0, 1),
}
local ICO_F = {
	{ 1, 12, 6 }, { 1, 6, 2 }, { 1, 2, 8 }, { 1, 8, 11 }, { 1, 11, 12 },
	{ 2, 6, 10 }, { 6, 12, 5 }, { 12, 11, 3 }, { 11, 8, 7 }, { 8, 2, 9 },
	{ 4, 10, 5 }, { 4, 5, 3 }, { 4, 3, 7 }, { 4, 7, 9 }, { 4, 9, 10 },
	{ 5, 10, 6 }, { 3, 5, 12 }, { 7, 3, 11 }, { 9, 7, 8 }, { 10, 9, 2 },
}
local OCT_V = {
	Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 1, 0),
	Vector3.new(0, -1, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1),
}
local OCT_F = {
	{ 3, 1, 5 }, { 3, 5, 2 }, { 3, 2, 6 }, { 3, 6, 1 },
	{ 4, 5, 1 }, { 4, 2, 5 }, { 4, 6, 2 }, { 4, 1, 6 },
}

export type BlobOpts = {
	octa: boolean?,     -- 8 faces instead of 20 (small or far things)
	jitter: number?,    -- how lumpy (0.18 default)
	top: Color3?,       -- the colour the upward faces lean to (sunlit)
	material: Enum.Material?,
}

-- A lumpy faceted ball filling `size`, centred on `center`.
function MenuForest.Blob(parent: Instance, center: Vector3, size: Vector3, color: Color3, rng: Random, opts: BlobOpts?)
	local o: BlobOpts = opts or {}
	local vs = if o.octa then OCT_V else ICO_V
	local fs = if o.octa then OCT_F else ICO_F
	local j = o.jitter or 0.18
	local spin = CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3))
	local top = o.top or color:Lerp(Color3.fromRGB(235, 205, 120), 0.45)
	local pts: { Vector3 } = {}
	for i, v in ipairs(vs) do
		local u = spin * v.Unit * (1 + rng:NextNumber(-j, j))
		pts[i] = center + Vector3.new(u.X * size.X, u.Y * size.Y, u.Z * size.Z) / 2
	end
	for _, f in ipairs(fs) do
		local a, b, c = pts[f[1]], pts[f[2]], pts[f[3]]
		local n = ((a + b + c) / 3 - center).Unit
		local shade = if n.Y > 0 then color:Lerp(top, n.Y * 0.8) else color:Lerp(Color3.new(0, 0, 0), -n.Y * 0.45)
		shade = shade:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.12))
		tri(parent, a, b, c, shade, o.material)
	end
end
local blob = MenuForest.Blob

-- ── Trees ───────────────────────────────────────────────────────────────────
local BARK = Color3.fromRGB(86, 70, 56)
local LEAF = Color3.fromRGB(70, 86, 40)

export type TreeOpts = {
	crown: number?,    -- crown radius (h * 0.32 default)
	reach: Vector3?,   -- where the crown leans (the art's trees overhang the view)
	blobs: number?,
	color: Color3?,
	octa: boolean?,
	shadow: boolean?,  -- casts shadows (the big near trees)
}

local function castShadows(m: Model)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.CastShadow = true end
	end
end

-- A broadleaf tree: a faceted trunk forking into branches under a layered
-- crown of faceted balls in a few shades of green. Its pivot is the foot of
-- the trunk (MenuBackdrop sways it from there).
function MenuForest.Tree(parent: Instance, base: Vector3, h: number, rng: Random, opts: TreeOpts?): Model
	local o: TreeOpts = opts or {}
	local m = Instance.new("Model")
	m.Name = "Tree"
	local R = o.crown or h * 0.32
	local reach = o.reach or Vector3.zero
	local crownC = base + Vector3.new(0, h * 0.74, 0) + reach
	local w = math.max(h * 0.075, 0.5)
	local fork = base + Vector3.new(0, h * 0.5, 0) + reach * 0.35
	local bark = BARK:Lerp(Color3.fromRGB(60, 42, 30), rng:NextNumber(0, 0.4))
	post(m, base - Vector3.new(0, 0.5, 0), base + Vector3.new(0, h * 0.25, 0) + reach * 0.15, w * 1.25, bark, true)
	post(m, base + Vector3.new(0, h * 0.24, 0) + reach * 0.14, fork, w, bark, true)
	-- roots flaring at the foot
	for i = 0, 3 do
		local a = i * math.pi / 2 + rng:NextNumber(-0.4, 0.4)
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		post(m, base + out * w * 1.6 - Vector3.new(0, 0.2, 0), base + out * w * 0.2 + Vector3.new(0, w * 1.4, 0), w * 0.45, bark)
	end
	local n = o.blobs or 6
	local leaf = o.color or LEAF
	-- (three shades: deep in the crown, mid, and the sunlit outer lumps)
	local shades = { leaf:Lerp(Color3.fromRGB(34, 48, 30), 0.45), leaf, leaf:Lerp(Color3.fromRGB(120, 128, 60), 0.3) }
	for i = 1, n do
		local a = (i / n) * math.pi * 2 + rng:NextNumber(-0.4, 0.4)
		local rr = if i == 1 then 0 else R * rng:NextNumber(0.45, 0.8)
		local c = crownC + Vector3.new(math.cos(a) * rr, rng:NextNumber(-0.25, 0.35) * R, math.sin(a) * rr)
		if i > 1 then
			-- a branch out to each outer lump
			post(m, fork, c - Vector3.new(0, R * 0.25, 0), w * 0.5, bark, true)
		end
		local s = R * rng:NextNumber(0.8, 1.15) * (if i == 1 then 1.25 else 1)
		local shade = shades[if i == 1 then 1 else rng:NextInteger(2, 3)]
		blob(m, c, Vector3.new(s * 1.15, s * rng:NextNumber(0.8, 1), s * 1.15), shade:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.12)), rng,
			{ octa = o.octa })
	end
	if o.shadow then castShadows(m) end
	m.WorldPivot = CFrame.new(base)
	m.Parent = parent
	return m
end

export type PineOpts = { color: Color3?, shadow: boolean? }

-- A low-poly pine with an irregular silhouette: a thin trunk and three or
-- four stacked seven-sided cones, each a little off-centre and uneven.
function MenuForest.Pine(parent: Instance, base: Vector3, h: number, rng: Random, opts: PineOpts?): Model
	local o: PineOpts = opts or {}
	local m = Instance.new("Model")
	m.Name = "Pine"
	post(m, base - Vector3.new(0, 0.3, 0), base + Vector3.new(0, h * 0.4, 0), math.max(h * 0.05, 0.3), BARK, true)
	local green = (o.color or Color3.fromRGB(52, 74, 40)):Lerp(Color3.fromRGB(32, 50, 32), rng:NextNumber(0, 0.5))
	local SIDES = 7
	local spin = rng:NextNumber(0, 6.28)
	local tiers = rng:NextInteger(3, 4)
	local girth = rng:NextNumber(0.8, 1.2)
	local lean = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1)) * h * 0.02
	for tier = 0, tiers - 1 do
		local k = tier / tiers
		local r = h * (0.28 - k * 0.2) * girth * rng:NextNumber(0.9, 1.1)
		local y0 = h * (0.18 + k * 0.62)
		local off = lean * tier + Vector3.new(rng:NextNumber(-0.3, 0.3), 0, rng:NextNumber(-0.3, 0.3))
		local apex = base + off + Vector3.new(0, y0 + h * (0.34 - k * 0.08), 0)
		local ring: { Vector3 } = {}
		for i = 1, SIDES do
			local a = spin + tier * 0.4 + i / SIDES * math.pi * 2
			local rr = r * rng:NextNumber(0.78, 1.15)
			ring[i] = base + off + Vector3.new(math.cos(a) * rr, y0 + rng:NextNumber(-0.12, 0.12) * r, math.sin(a) * rr)
		end
		for i = 1, SIDES do
			local a, b = ring[i], ring[i % SIDES + 1]
			local mid = (a + b) / 2 - base
			local lit = math.clamp(-mid.Unit.Z * 0.5 + 0.5, 0, 1) -- (faces turned to the camera a touch lighter)
			tri(m, apex, a, b, green:Lerp(Color3.fromRGB(120, 124, 64), lit * 0.22 + rng:NextNumber(0, 0.08)))
		end
	end
	if o.shadow then castShadows(m) end
	m.WorldPivot = CFrame.new(base)
	m.Parent = parent
	return m
end

-- ── The far view ────────────────────────────────────────────────────────────
-- Laid out in `frame` (the title camera, level: x right, -z ahead), all of it
-- within ~165 studs so it's drawn at every graphics quality; the haze makes it
-- read as miles of valley.
local CASTLE_X, CASTLE_D = 12, 132

local function smooth(e0: number, e1: number, x: number): number
	local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
	return t * t * (3 - 2 * t)
end

-- Ground height at (x, d): d = distance ahead of the camera.
local function H(x: number, d: number): number
	local y = -27 + math.noise(x / 38, d / 38, 0.3) * 7 + math.noise(x / 14, d / 14, 2.1) * 1.5
	-- the clearing's edge, falling away into the valley
	y += (1 - smooth(34, 52, d)) * 16
	-- the castle hill
	local dx, dd = x - CASTLE_X, d - CASTLE_D
	y += 10 * math.exp(-(dx * dx + dd * dd * 1.3) / (2 * 24 * 24))
	-- hills rising at the sides and ridges far off
	y += smooth(55, 140, math.abs(x)) * 16
	y += smooth(132, 162, d) * (16 + math.noise(x / 30, 7.7) * 8)
	return y
end
MenuForest.GroundHeight = H

-- Returns where the castle stands: the hilltop, level, facing the camera.
function MenuForest.Valley(parent: Instance, frame: CFrame, rng: Random): CFrame
	local m = Instance.new("Model")
	m.Name = "Valley"
	local function at(x: number, d: number, y: number?): Vector3
		return (frame * CFrame.new(x, y or H(x, d), -d)).Position
	end
	-- The ground: a faceted sheet, wider the farther it goes.
	local NU, ND = 22, 12
	local D0, D1 = 30, 168
	local grid: { { Vector3 } } = {}
	for j = 0, ND do
		local t = j / ND
		local d = D0 + (D1 - D0) * (t ^ 1.25)
		local row: { Vector3 } = {}
		for i = 0, NU do
			local u = i / NU * 2 - 1
			local x = u * (45 + 1.3 * d) + (if i > 0 and i < NU then rng:NextNumber(-2, 2) else 0)
			row[i] = at(x, d)
		end
		grid[j] = row
	end
	local GRASS_LIT = Color3.fromRGB(150, 140, 74)
	local GRASS = Color3.fromRGB(96, 104, 56)
	local GRASS_DARK = Color3.fromRGB(64, 76, 46)
	local baseY = frame.Position.Y
	local function groundColor(a: Vector3, b: Vector3, c: Vector3): Color3
		local n = (b - a):Cross(c - a).Unit
		if n.Y < 0 then n = -n end
		local hgt = ((a.Y + b.Y + c.Y) / 3 - baseY + 27) / 30
		local col = GRASS:Lerp(GRASS_DARK, math.clamp(1 - n.Y, 0, 1) * 1.6)
		col = col:Lerp(GRASS_LIT, math.clamp(hgt, 0, 1) * 0.5)
		return col:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.08))
	end
	for j = 0, ND - 1 do
		for i = 0, NU - 1 do
			local a, b, c, d = grid[j][i], grid[j][i + 1], grid[j + 1][i], grid[j + 1][i + 1]
			tri(m, a, b, c, groundColor(a, b, c))
			tri(m, b, d, c, groundColor(b, d, c))
		end
	end

	-- The castle's hilltop (MenuBackdrop builds the castle there).
	local site = frame * CFrame.new(CASTLE_X, H(CASTLE_X, CASTLE_D) + 1.5, -CASTLE_D)

	-- Woods: round trees all over the valley floor and slopes (clear of the
	-- castle's hilltop), each a trunk and a faceted crown.
	local placed = 0
	for _ = 1, 900 do
		if placed >= 190 then break end
		local d = rng:NextNumber(36, 160)
		local x = rng:NextNumber(-1, 1) * (40 + 1.25 * d)
		local dx, dd = x - CASTLE_X, d - CASTLE_D
		if dx * dx + dd * dd > 30 * 30 then
			placed += 1
			local y = H(x, d)
			local s = rng:NextNumber(3.6, 6.2) * (0.8 + d / 260)
			local foot = at(x, d, y)
			local tone = Color3.fromRGB(120, 116, 58):Lerp(Color3.fromRGB(74, 86, 44), rng:NextNumber())
			if rng:NextNumber() < 0.15 then tone = Color3.fromRGB(150, 110, 60) end -- a few turning
			local trunk = bare("Part")
			trunk.Size = Vector3.new(s * 0.12, s * 0.7, s * 0.12)
			trunk.CFrame = CFrame.new(foot + Vector3.new(0, s * 0.35, 0))
			trunk.Color = Color3.fromRGB(72, 58, 46)
			trunk.Material = SMOOTH
			trunk.Parent = m
			local c = foot + Vector3.new(0, s * 0.95, 0)
			blob(m, c, Vector3.new(s * 1.1, s * 0.9, s * 1.1), tone, rng, { octa = true, jitter = 0.12 })
		end
	end

	-- Mist lying in the valley, warm where the sun catches it.
	for k = 1, 9 do
		local d = 55 + (k - 1) * 11
		local x = rng:NextNumber(-60, 60)
		local p = bare("Part")
		p.Size = Vector3.new(90, 2, 18)
		p.CFrame = CFrame.new(at(x, d, H(x, d) + 4))
		p.Transparency = 1
		p.Parent = m
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/smoke_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 232, 196), Color3.fromRGB(230, 196, 160))
		e.LightInfluence = 0.2
		e.LightEmission = 0.15
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 22), NumberSequenceKeypoint.new(1, 38) })
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.78), NumberSequenceKeypoint.new(0.7, 0.8), NumberSequenceKeypoint.new(1, 1),
		})
		e.Lifetime = NumberRange.new(22, 30)
		e.Speed = NumberRange.new(0.4, 1.2)
		e.SpreadAngle = Vector2.new(10, 180)
		e.EmissionDirection = Enum.NormalId.Right
		e.Rotation = NumberRange.new(0, 360)
		e.RotSpeed = NumberRange.new(-2, 2)
		e.Rate = 0.5
		e.Parent = p
		e:Emit(12)
	end
	m.Parent = parent
	return site
end

return MenuForest
