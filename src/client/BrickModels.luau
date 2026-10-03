--[[
	BrickModels.luau
	Toy-brick (voxel + studs) 3D models for the selection screens
	(ChoiceScreen): one for every run relic, and a book for every tome / boon
	with its emblem raised on the cover. Everything is built from 1×1×1
	bricks with a stud on each brick whose top is open, so they read as a set.

	  • BrickModels.Relic(id)         → Model (or nil for an unknown relic)
	  • BrickModels.RelicInfo(id)     → { theme: Color3, rarity: string }
	  • BrickModels.RARITY            → rarity name → badge colour
	  • BrickModels.Tome(id, accent)  → Model (a book in the tome's colour)
	  • BrickModels.Pedestal(theme)   → Model (stone, glowing rim)

	Shapes are described as pixel sprites (extruded to a depth), lathes (round
	things: crowns, bells, coins), spheres and boxes, grouped with their own
	CFrame so pieces can be tilted (crossed swords, an arrow through a target).
--]]

local BrickModels = {}

BrickModels.RARITY = {
	Rare = Color3.fromRGB(70, 150, 255),
	Epic = Color3.fromRGB(235, 60, 150),
	Legendary = Color3.fromRGB(255, 195, 60),
}

local INFO: { [string]: { theme: Color3, rarity: string } } = {
	relic_dragons_heart = { theme = Color3.fromRGB(235, 50, 40), rarity = "Legendary" },
	relic_bloodied_crown = { theme = Color3.fromRGB(255, 190, 40), rarity = "Epic" },
	relic_frozen_soul = { theme = Color3.fromRGB(110, 205, 255), rarity = "Rare" },
	relic_berserkers_tooth = { theme = Color3.fromRGB(235, 90, 40), rarity = "Epic" },
	relic_shattered_mirror = { theme = Color3.fromRGB(175, 95, 255), rarity = "Epic" },
	relic_gamblers_coin = { theme = Color3.fromRGB(80, 220, 120), rarity = "Rare" },
	relic_hollow_lantern = { theme = Color3.fromRGB(255, 160, 50), rarity = "Rare" },
	relic_iron_vow = { theme = Color3.fromRGB(80, 140, 255), rarity = "Rare" },
	relic_vampire_fang = { theme = Color3.fromRGB(220, 20, 60), rarity = "Epic" },
	relic_storm_eye = { theme = Color3.fromRGB(130, 120, 255), rarity = "Legendary" },
	relic_frozen_heart = { theme = Color3.fromRGB(140, 230, 255), rarity = "Legendary" },
	relic_blood_oath = { theme = Color3.fromRGB(200, 25, 35), rarity = "Legendary" },
	relic_saints_bell = { theme = Color3.fromRGB(255, 225, 140), rarity = "Legendary" },
	relic_loaded_dice = { theme = Color3.fromRGB(255, 85, 85), rarity = "Legendary" },
	relic_ember_heart = { theme = Color3.fromRGB(255, 120, 30), rarity = "Legendary" },
	relic_duelists_mark = { theme = Color3.fromRGB(245, 225, 165), rarity = "Legendary" },
	relic_hunters_sigil = { theme = Color3.fromRGB(110, 210, 90), rarity = "Legendary" },
}

function BrickModels.RelicInfo(id: string): { theme: Color3, rarity: string }
	return INFO[id] or { theme = Color3.fromRGB(255, 213, 128), rarity = "Rare" }
end

-- ── Voxel groups ────────────────────────────────────────────────────────────
type Voxel = { x: number, y: number, z: number, color: Color3, neon: boolean, alpha: number }
type Group = { cf: CFrame, vox: { [string]: Voxel } }

local function group(cf: CFrame?): Group
	return { cf = cf or CFrame.new(), vox = {} }
end

local function key(x: number, y: number, z: number): string
	return `{x},{y},{z}`
end

local function set(g: Group, x: number, y: number, z: number, color: Color3, neon: boolean?, alpha: number?)
	g.vox[key(x, y, z)] = { x = x, y = y, z = z, color = color, neon = neon == true, alpha = alpha or 0 }
end

local function has(g: Group, x: number, y: number, z: number): boolean
	return g.vox[key(x, y, z)] ~= nil
end

type Paint = { color: Color3, neon: boolean?, alpha: number? }

-- A pixel sprite (rows top → bottom, '.' = empty) extruded `depth` bricks back
-- from z = z0, centred on x. Palette chars map to a colour (+ neon / alpha).
local function sprite(g: Group, rows: { string }, palette: { [string]: Paint }, depth: number?, z0: number?, xOff: number?, yOff: number?)
	local h = #rows
	local w = #rows[1]
	local cx = math.floor(w / 2)
	for r, row in ipairs(rows) do
		for c = 1, #row do
			local ch = string.sub(row, c, c)
			local p = palette[ch]
			if p then
				for d = 0, (depth or 1) - 1 do
					set(g, c - 1 - cx + (xOff or 0), h - r + (yOff or 0), (z0 or 0) - d, p.color, p.neon, p.alpha)
				end
			end
		end
	end
end

-- Round, upright things: `profile` is { y, outer radius, inner radius? }.
local function lathe(g: Group, profile: { { number } }, paint: (x: number, y: number, z: number, d: number) -> Paint?)
	for _, row in ipairs(profile) do
		local y, ro, ri = row[1], row[2], row[3] or 0
		local n = math.ceil(ro)
		for x = -n, n do
			for z = -n, n do
				local d = math.sqrt(x * x + z * z)
				if d <= ro + 0.25 and d >= ri - 0.25 then
					local p = paint(x, y, z, d)
					if p then set(g, x, y, z, p.color, p.neon, p.alpha) end
				end
			end
		end
	end
end

-- A flat disc facing the camera (XY plane), `depth` thick.
local function disc(g: Group, r: number, depth: number, paint: (x: number, y: number, d: number) -> Paint?)
	local n = math.ceil(r)
	for x = -n, n do
		for y = -n, n do
			local d = math.sqrt(x * x + y * y)
			if d <= r + 0.25 then
				local p = paint(x, y, d)
				if p then
					for z = 0, depth - 1 do set(g, x, y, -z, p.color, p.neon, p.alpha) end
				end
			end
		end
	end
end

local function sphere(g: Group, r: number, paint: (x: number, y: number, z: number) -> Paint?)
	local n = math.ceil(r)
	for x = -n, n do
		for y = -n, n do
			for z = -n, n do
				if math.sqrt(x * x + y * y + z * z) <= r + 0.2 then
					local p = paint(x, y, z)
					if p then set(g, x, y, z, p.color, p.neon, p.alpha) end
				end
			end
		end
	end
end

local function box(g: Group, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, p: Paint)
	for x = x0, x1 do
		for y = y0, y1 do
			for z = z0, z1 do
				set(g, x, y, z, p.color, p.neon, p.alpha)
			end
		end
	end
end

-- ── Rendering ───────────────────────────────────────────────────────────────
local STUD = Vector3.new(0.2, 0.62, 0.62)

local function brick(model: Model, cf: CFrame, size: Vector3, v: Voxel, shape: Enum.PartType?)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = v.color
	p.Material = if v.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Transparency = v.alpha
	p.Parent = model
end

local function same(a: Voxel, b: Voxel): boolean
	return a.color == b.color and a.neon == b.neon and a.alpha == b.alpha
end

-- A brick with solid bricks on all six sides can't be seen: skipped.
local function solid(g: Group, x: number, y: number, z: number): boolean
	local o = g.vox[key(x, y, z)]
	return o ~= nil and o.alpha == 0
end
local function hidden(g: Group, v: Voxel): boolean
	return solid(g, v.x + 1, v.y, v.z) and solid(g, v.x - 1, v.y, v.z)
		and solid(g, v.x, v.y + 1, v.z) and solid(g, v.x, v.y - 1, v.z)
		and solid(g, v.x, v.y, v.z + 1) and solid(g, v.x, v.y, v.z - 1)
end

local function render(name: string, groups: { Group }): Model
	local model = Instance.new("Model")
	model.Name = name
	for _, g in ipairs(groups) do
		local rows: { [string]: { Voxel } } = {}
		for _, v in pairs(g.vox) do
			if hidden(g, v) then continue end
			local k = `{v.y},{v.z}`
			rows[k] = rows[k] or {}
			table.insert(rows[k], v)
			-- a stud on every brick with nothing on top of it
			if not has(g, v.x, v.y + 1, v.z) then
				local cf = g.cf * CFrame.new(v.x, v.y + 0.6, v.z) * CFrame.Angles(0, 0, math.pi / 2)
				brick(model, cf, STUD, v, Enum.PartType.Cylinder)
			end
		end
		-- Runs of matching bricks along a row are one part (far fewer parts).
		for _, row in pairs(rows) do
			table.sort(row, function(p, q) return p.x < q.x end)
			local i = 1
			while i <= #row do
				local first = row[i]
				local j = i
				while j < #row and row[j + 1].x == row[j].x + 1 and same(row[j + 1], first) do j += 1 end
				local last = row[j]
				local cf = g.cf * CFrame.new((first.x + last.x) / 2, first.y, first.z)
				brick(model, cf, Vector3.new(last.x - first.x + 1, 1, 1), first)
				i = j + 1
			end
		end
	end
	-- Centred on its bounding box, so it spins in place.
	local bb = model:GetBoundingBox()
	local root = Instance.new("Part")
	root.Name = "Center"
	root.Anchored = true
	root.Transparency = 1
	root.CanCollide = false
	root.Size = Vector3.one * 0.1
	root.CFrame = CFrame.new(bb.Position)
	root.Parent = model
	model.PrimaryPart = root
	return model
end

-- ── Colours ─────────────────────────────────────────────────────────────────
local function c(r: number, g: number, b: number): Paint return { color = Color3.fromRGB(r, g, b) } end
local function n(r: number, g: number, b: number): Paint return { color = Color3.fromRGB(r, g, b), neon = true } end
local function t(r: number, g: number, b: number, a: number): Paint return { color = Color3.fromRGB(r, g, b), alpha = a } end

local GOLD, GOLD_D, GOLD_L = c(255, 190, 40), c(200, 130, 20), c(255, 230, 120)
local IVORY, BONE = c(245, 238, 215), c(220, 205, 170)
local STEEL, STEEL_D, STEEL_L = c(165, 175, 190), c(95, 105, 120), c(215, 225, 235)
local BLOOD = c(190, 20, 30)
local BLOOD_N = n(230, 20, 40)

local HEART = {
	".RRR...RRR.",
	"RHHRR.RRRRR",
	"RHRRRRRRRRR",
	"RRRRRRRRRRR",
	"RRRRRRRRRRR",
	".RRRRRRRRD.",
	"..RRRRRRD..",
	"...RRRRD...",
	"....RRD....",
	".....D.....",
}

-- ── The relics ──────────────────────────────────────────────────────────────
local BUILDERS: { [string]: () -> { Group } } = {}

-- A crimson dragon's heart with bone horns and an ember core.
BUILDERS.relic_dragons_heart = function()
	local g = group()
	local rows = table.clone(HEART)
	table.insert(rows, 1, ".B.......B.")
	table.insert(rows, 1, "B.........B")
	sprite(g, rows, { R = c(200, 30, 30), H = c(255, 90, 80), D = c(120, 15, 20), B = BONE }, 3, 1)
	sprite(g, { ".EYE.", "EYYYE", ".EYE." }, { E = n(255, 110, 20), Y = n(255, 220, 80) }, 1, 2, 0, 5)
	return { g }
end

-- A gold crown, rubies in the band, blood running from it.
BUILDERS.relic_bloodied_crown = function()
	local g = group()
	lathe(g, {
		{ 0, 3.6, 2.5 }, { 1, 3.6, 2.5 }, { 2, 3.6, 2.5 }, { 3, 3.6, 2.5 }, { 4, 3.6, 2.5 }, { -1, 3.6, 2.9 }, { -2, 3.6, 2.9 },
	}, function(x, y, z)
		local a = math.deg(math.atan2(z, x)) % 60
		local nearPoint = a < 12 or a > 48
		if y == 4 then return if a < 6 or a > 54 then GOLD_L else nil end
		if y >= 2 then return if nearPoint then GOLD else nil end
		if y == 1 and math.abs(a - 30) < 9 then return n(230, 20, 40) end
		if y == -1 then return if math.abs(a - 30) < 4 and z > 0 then BLOOD else nil end
		if y == -2 then return if math.abs(a - 30) < 2 and z > 1 then BLOOD else nil end
		return if y == 0 then GOLD_D else GOLD
	end)
	return { g }
end

-- Ice crystals around a glowing soul.
BUILDERS.relic_frozen_soul = function()
	local g = group()
	local ICE, ICE_L = t(140, 210, 255, 0.25), t(210, 245, 255, 0.15)
	for _, col in ipairs({ { 0, 0, 8, 1 }, { -2, 1, 5, 0 }, { 2, -1, 6, 0 }, { 1, 2, 4, 0 }, { -1, -2, 4, 0 }, { -3, -1, 3, 0 }, { 3, 2, 3, 0 } }) do
		local cx, cz, h, w = col[1], col[2], col[3], col[4]
		for y = 0, h do
			local ww = if y >= h - 1 then 0 else w
			for x = cx - ww, cx + ww do
				for z = cz - ww, cz + ww do
					local p = if y >= h - 1 then ICE_L else ICE
					set(g, x, y, z, p.color, false, p.alpha)
				end
			end
		end
	end
	box(g, 0, 2, 0, 0, 4, 0, n(120, 240, 255))
	return { g }
end

-- A great curved fang on a leather cord, its tip bloodied.
BUILDERS.relic_berserkers_tooth = function()
	local g = group()
	sprite(g, {
		".CCCCC.",
		"C.....C",
		".WWWWW.",
		".WWWWW.",
		"..WWWW.",
		"..WWWW.",
		"...WWW.",
		"...WWR.",
		"....RR.",
		"....R..",
	}, { C = c(110, 70, 40), W = IVORY, R = BLOOD }, 2, 0)
	return { g }
end

-- A hand mirror, its glass broken, shards hanging in the air.
BUILDERS.relic_shattered_mirror = function()
	local g = group()
	sprite(g, {
		"..FFF..",
		".FG.GF.",
		"FGGG.GF",
		"FG.GGGF",
		"FGG.GGF",
		"FGGG.GF",
		".FG.GF.",
		"..FFF..",
		"...H...",
		"...H...",
		"...H...",
		"..FFF..",
	}, { F = c(150, 110, 210), G = t(200, 170, 255, 0.2), H = c(70, 40, 110) }, 2, 0)
	local shards = group()
	for _, s in ipairs({ { -3, 9, 2 }, { 3, 8, 2 }, { -4, 6, 1 }, { 4, 5, 2 }, { 2, 10, 1 } }) do
		set(shards, s[1], s[2], s[3], Color3.fromRGB(225, 200, 255), true)
	end
	return { g, shards }
end

-- A gold coin with a clover, two smaller coins behind.
local function coin(cf: CFrame, r: number, emblem: boolean): Group
	local g = group(cf)
	disc(g, r, 2, function(_, _, d)
		return if d > r - 0.8 then GOLD_D else GOLD
	end)
	if emblem then
		sprite(g, { "..X..", ".XXX.", "XXXXX", "..X..", ".XXX." }, { X = c(60, 170, 90) }, 1, 1, 0, -2)
	end
	return g
end
BUILDERS.relic_gamblers_coin = function()
	local stacks = group()
	for _, st in ipairs({ { -4, 0, 3 }, { 4, -1, 2 } }) do
		for y = 0, st[3] - 1 do
			lathe(stacks, { { -6 + y, 1.6 } }, function(x, _, z, d)
				return if d > 1.1 then GOLD_D else GOLD
			end)
			-- (each stack shifted to its spot)
		end
	end
	local moved = group(CFrame.new())
	for _, v in pairs(stacks.vox) do
		local sx = if v.x <= 0 then -4 else 4
		set(moved, v.x + sx, v.y, v.z, v.color)
	end
	return { coin(CFrame.new(), 4, true), moved }
end

-- An iron lantern, hollow but for a flame.
BUILDERS.relic_hollow_lantern = function()
	local g = group()
	local IRON = c(55, 50, 55)
	box(g, -2, 0, -2, 2, 0, 2, IRON)
	box(g, -2, 6, -2, 2, 6, 2, IRON)
	box(g, -1, 7, -1, 1, 7, 1, IRON)
	set(g, 0, 8, 0, IRON.color)
	for _, p in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do box(g, p[1], 1, p[2], p[1], 5, p[2], IRON) end
	local PANE = t(255, 190, 90, 0.45)
	box(g, -1, 1, 2, 1, 5, 2, PANE)
	box(g, -1, 1, -2, 1, 5, -2, PANE)
	box(g, 2, 1, -1, 2, 5, 1, PANE)
	box(g, -2, 1, -1, -2, 5, 1, PANE)
	box(g, 0, 1, 0, 0, 2, 0, n(255, 120, 20))
	set(g, 0, 3, 0, Color3.fromRGB(255, 220, 90), true)
	set(g, -1, 9, 0, IRON.color)
	set(g, 1, 9, 0, IRON.color)
	box(g, -1, 10, 0, 1, 10, 0, IRON)
	return { g }
end

-- A kite shield with a cross and gold rivets.
BUILDERS.relic_iron_vow = function()
	local g = group()
	sprite(g, {
		"SSSSSSSSS",
		"SGBBBBBGS",
		"SBBBXBBBS",
		"SBBBXBBBS",
		"SBXXXXXBS",
		"SBBBXBBBS",
		".SBBXBBS.",
		".SGBXBGS.",
		"..SBBBS..",
		"...SBS...",
		"....S....",
	}, { S = STEEL_D, B = STEEL, X = c(40, 70, 160), G = GOLD }, 2, 0)
	return { g }
end

-- Two fangs, a drop of blood falling.
BUILDERS.relic_vampire_fang = function()
	local g = group()
	sprite(g, {
		"DDDDDDDDDDD",
		"DWWWDDDWWWD",
		".WWW...WWW.",
		".WWW...WWW.",
		"..WW...WW..",
		"..WR...RW..",
		"...R...R...",
		"...........",
		".......B...",
		"......BBB..",
		"......BBB..",
		".......B...",
	}, { D = c(110, 15, 35), W = IVORY, R = BLOOD, B = BLOOD_N }, 2, 0)
	return { g }
end

-- An eye in a storm-dark orb, a bolt crackling beside it.
BUILDERS.relic_storm_eye = function()
	local g = group()
	sphere(g, 3.5, function(x, y, z)
		local r = math.sqrt(x * x + y * y)
		if z >= 2 and r <= 0.8 then return c(15, 10, 30) end
		if z >= 2 and r <= 1.9 then return n(90, 220, 255) end
		return if (x + y + z) % 3 == 0 then c(60, 45, 140) else c(40, 30, 100)
	end)
	local bolt = group(CFrame.new(5, 1, 0))
	sprite(bolt, { "...YY", "..YY.", ".YY..", "YYYYY", "..YY.", ".YY..", "YY...", "Y...." }, { Y = n(255, 230, 80) }, 1, 0, 0, -4)
	return { g, bolt }
end

-- A heart of ice around a frozen glow.
BUILDERS.relic_frozen_heart = function()
	local g = group()
	sprite(g, HEART, { R = t(150, 220, 255, 0.25), H = t(230, 250, 255, 0.1), D = t(90, 160, 220, 0.25) }, 3, 1)
	box(g, -1, 4, 0, 1, 6, 0, n(120, 240, 255))
	return { g }
end

-- An oath sworn on a dagger: a ruby pommel and a bloodied blade.
BUILDERS.relic_blood_oath = function()
	local g = group()
	sprite(g, {
		"...R...",
		"..DDD..",
		"...D...",
		"...D...",
		"GGGGGGG",
		"..SSS..",
		"..SBS..",
		"..SSS..",
		"..SBS..",
		"..SSS..",
		"...B...",
		"...S...",
		".......",
		"...B...",
	}, { R = n(230, 20, 40), D = c(90, 20, 25), G = GOLD, S = STEEL_L, B = BLOOD_N }, 1, 0)
	return { g }
end

-- A golden bell under a white cross.
BUILDERS.relic_saints_bell = function()
	local g = group()
	lathe(g, {
		{ 8, 0 }, { 7, 1.5 }, { 6, 2.1 }, { 5, 2.3 }, { 4, 2.6, 1.5 }, { 3, 2.9, 1.8 }, { 2, 3.2, 2.1 }, { 1, 3.6, 2.5 }, { 0, 4.1, 3 },
	}, function(_, y, _, d)
		if y == 0 then return GOLD_D end
		if y == 6 and d > 1.6 then return GOLD_L end
		return GOLD
	end)
	set(g, 0, -1, 0, Color3.fromRGB(150, 100, 20))
	sprite(g, { ".W.", "WWW", ".W.", ".W." }, { W = n(255, 250, 230) }, 1, 0, 0, 9)
	return { g }
end

-- A pair of loaded dice.
local PIPS: { [number]: { { number } } } = {
	[1] = { { 0, 0 } },
	[2] = { { -2, -2 }, { 2, 2 } },
	[3] = { { -2, -2 }, { 0, 0 }, { 2, 2 } },
	[4] = { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } },
	[5] = { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 }, { 0, 0 } },
	[6] = { { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 }, { -2, 0 }, { 2, 0 } },
}
local function die(cf: CFrame): Group
	local g = group(cf)
	local pips: { [string]: boolean } = {}
	local function face(count: number, toKey: (u: number, v: number) -> string)
		for _, p in ipairs(PIPS[count]) do pips[toKey(p[1], p[2])] = true end
	end
	face(1, function(u, v) return key(u, v, 3) end)
	face(6, function(u, v) return key(u, v, -3) end)
	face(3, function(u, v) return key(3, v, u) end)
	face(4, function(u, v) return key(-3, v, u) end)
	face(5, function(u, v) return key(u, 3, v) end)
	face(2, function(u, v) return key(u, -3, v) end)
	for x = -3, 3 do
		for y = -3, 3 do
			for z = -3, 3 do
				if math.max(math.abs(x), math.abs(y), math.abs(z)) == 3 then
					local p = if pips[key(x, y, z)] then c(200, 25, 35) else IVORY
					set(g, x, y, z, p.color)
				end
			end
		end
	end
	return g
end
BUILDERS.relic_loaded_dice = function()
	return {
		-- (quarter turns about the vertical keep the bricks on the grid and the
		-- studs on top: the 4 and the 3 face front)
		die(CFrame.new(-4, 0, -1) * CFrame.Angles(0, math.pi / 2, 0)),
		die(CFrame.new(4, 0, 2) * CFrame.Angles(0, -math.pi / 2, 0)),
	}
end

-- A smouldering heart crowned with flame.
BUILDERS.relic_ember_heart = function()
	local g = group()
	sprite(g, HEART, { R = c(200, 70, 20), H = c(255, 150, 60), D = c(90, 25, 10) }, 3, 1)
	sprite(g, { "..Y..", ".YOY.", ".OYO.", "OYYYO", "OOYOO", ".OOO." }, { Y = n(255, 230, 90), O = n(255, 110, 20) }, 1, 0, 0, 9)
	return { g }
end

-- A diagonal line of bricks (pixel-art style, no rotated bricks).
local function diag(g: Group, x: number, y: number, dx: number, dy: number, len: number, z: number, p: Paint, thick: boolean?)
	for i = 0, len - 1 do
		set(g, x + dx * i, y + dy * i, z, p.color, p.neon, p.alpha)
		if thick then set(g, x + dx * i + dx, y + dy * i, z, p.color, p.neon, p.alpha) end
	end
end

-- Two longswords crossed.
local function sword(g: Group, dx: number, z: number)
	-- tip top-outside, hilt bottom-inside → the blades cross in the middle
	local x0, y0 = -6 * dx, 6
	diag(g, x0, y0, dx, -1, 10, z, STEEL_L, true)
	local gx, gy = x0 + dx * 10, y0 - 10
	for i = -2, 2 do set(g, gx + i, gy - i * dx * dx, z, GOLD.color) end -- the guard, across the blade
	diag(g, gx + dx, gy - 1, dx, -1, 2, z, c(90, 55, 30))
	set(g, gx + dx * 3, gy - 3, z, GOLD.color)
end
BUILDERS.relic_duelists_mark = function()
	local g = group()
	for z = 0, 1 do
		sword(g, 1, -z)
	end
	for z = 2, 3 do
		sword(g, -1, -z)
	end
	return { g }
end

-- A hunter's target, an arrow driven through it.
BUILDERS.relic_hunters_sigil = function()
	local target = group()
	disc(target, 4, 2, function(_, _, d)
		if d <= 1 then return GOLD end
		if d <= 2.2 then return c(60, 150, 50) end
		if d <= 3.2 then return c(235, 225, 190) end
		return c(60, 150, 50)
	end)
	-- the arrow, driven in at an angle from the top right: shaft and fletching
	diag(target, 1, 1, 1, 1, 6, 1, c(130, 85, 45))
	diag(target, 1, 1, 1, 1, 4, 2, c(130, 85, 45))
	for _, f in ipairs({ { 7, 5 }, { 5, 7 }, { 7, 6 }, { 6, 7 }, { 8, 6 }, { 6, 8 } }) do
		set(target, f[1], f[2], 2, Color3.fromRGB(110, 210, 90))
	end
	return { target }
end

function BrickModels.Relic(id: string): Model?
	local b = BUILDERS[id]
	if not b then return nil end
	return render(id, b())
end

-- ── Tomes ───────────────────────────────────────────────────────────────────
-- Each tome's emblem, 7 wide: '#' its colour (glowing), 'o' a second glow.
local EMBLEMS: { [string]: { string } } = {
	agility = { "#......", "##.....", "###....", ".####..", "..#####", "...####", "....##." },
	attack_speed = { "#..#...", ".#..#..", "..#..#.", "...#..#", "..#..#.", ".#..#..", "#..#..." },
	cooldown = { "#######", ".#...#.", "..#.#..", "...#...", "..#o#..", ".#ooo#.", "#######" },
	damage = { "...#...", "..##.#.", ".####..", ".#####.", "###o###", "##ooo##", ".#####." },
	evasion = { ".#####.", "#######", "##o#o##", "#######", "#######", "#.#.#.#" },
	gold = { "..###..", ".#ooo#.", "#oo#oo#", "#o###o#", "#oo#oo#", ".#ooo#.", "..###.." },
	health = { ".##.##.", "#######", "#######", ".#####.", "..###..", "...#..." },
	knockback = { "##...#.", ".##..#.", "..##.#.", ".##..#.", "##...#." },
	precision = { "...#...", ".#####.", ".#...#.", "###o###", ".#...#.", ".#####.", "...#..." },
	projectile_speed = { "....#..", "#...##.", ".######", "#...##.", "....#.." },
	regen = { "..###..", "..###..", "#######", "#######", "#######", "..###..", "..###.." },
	shield = { "#######", "##o#o##", "#######", ".#####.", ".#####.", "..###..", "...#..." },
	silver = { ".#####.", "#######", ".#####.", "..###..", "...#..." },
	ricochet = { "#.....#", "#.....#", "#..#..#", ".#.#.#.", ".##.##.", "..#.#.." },
	size = { "###.###", "##...##", "#.....#", "...o...", "#.....#", "##...##", "###.###" },
	armor = { ".#####.", "#######", "###.###", "#.....#", "###.###", "###.###" },
	attraction = { "oo...oo", "##...##", "##...##", "##...##", "##...##", ".#####.", "..###.." },
	bloody = { "...#...", "..###..", ".#####.", ".#####.", "#######", "#######", ".#####.", "..###.." },
	chaos = { "#######", "#o...o#", "#.....#", "#..o..#", "#.....#", "#o...o#", "#######" },
	cursed = { ".#####.", "#######", "#oo#oo#", "#######", ".##.##.", ".#.#.#." },
	duration = { "..###..", ".#...#.", "#..o..#", "#..oo.#", "#.....#", ".#...#.", "..###.." },
	luck = { ".##.##.", "###.###", ".#####.", "###.###", ".##.##.", "...#...", "..#...." },
	quantity = { "##...##", "##...##", ".......", "..###..", "..###.." },
	thorns = { "#..#..#", ".#####.", "##...##", ".#...#.", "##...##", ".#####.", "#..#..#" },
	boon_ignite = { "...o...", "..ooo..", "...#...", "...#...", "...#...", ".#####.", "...#...", "...#..." },
	boon_frost = { "#..#..#", ".#.#.#.", "..###..", "###o###", "..###..", ".#.#.#.", "#..#..#" },
	boon_chain = { "....##.", "...##..", "..##...", ".#####.", "...##..", "..##...", ".##...." },
	boon_bloodlust = { ".#...#.", ".#...#.", "###.###", "###.###", ".#...#." },
	boon_corpse = { "#..#..#", ".#.#.#.", "..ooo..", "##ooo##", "..ooo..", ".#.#.#.", "#..#..#" },
	boon_execute = { ".##....", "####...", "#####..", "####.#.", ".##...#", "......#" },
	boon_thunder = { ".####..", "######.", "..oo...", ".oo....", "oooo...", "..o....", ".o....." },
	boon_secondwind = { "#####..", ".....#.", "####.#.", "....#..", "######." },
}
local DEFAULT_EMBLEM = { "...#...", "..###..", "#######", ".#####.", "..###..", ".##.##.", "#.....#" }

-- A closed book standing up, its cover in the tome's colour with gold
-- corners, page edges, a ribbon, and the emblem raised on the front.
function BrickModels.Tome(id: string, accent: Color3): Model
	local g = group()
	local h, s, v = accent:ToHSV()
	local sat = math.min(1, s * 1.1 + 0.1)
	local cover = Color3.fromHSV(h, sat, math.clamp(v * 0.62, 0.25, 0.7))
	local coverDark = Color3.fromHSV(h, sat, math.clamp(v * 0.4, 0.15, 0.5))
	local glowC = Color3.fromHSV(h, math.min(1, s * 0.9 + 0.1), 1)
	local line = accent:Lerp(Color3.new(1, 1, 1), 0.2)
	local X0, X1, Y0, Y1 = -5, 6, -6, 6
	-- covers (front z = 2, back z = -2) and the spine
	for x = X0, X1 do
		for y = Y0, Y1 do
			set(g, x, y, 2, cover)
			set(g, x, y, -2, coverDark)
		end
	end
	for y = Y0, Y1 do
		for z = -1, 1 do set(g, X0, y, z, coverDark) end
	end
	-- pages, set in from the covers' edges
	for x = X0 + 1, X1 - 1 do
		for y = Y0 + 1, Y1 - 1 do
			for z = -1, 1 do
				set(g, x, y, z, if y % 2 == 0 then Color3.fromRGB(240, 230, 200) else Color3.fromRGB(212, 198, 165))
			end
		end
	end
	-- an engraved frame round the emblem
	for x = -3, 5 do
		for y = -5, 5 do
			if x == -3 or x == 5 or y == -5 or y == 5 then set(g, x, y, 2, line) end
		end
	end
	-- gold corners, raised on the front, flush on the back
	for _, cn in ipairs({ { X0, Y1, 1, -1 }, { X1, Y1, -1, -1 }, { X0, Y0, 1, 1 }, { X1, Y0, -1, 1 } }) do
		local cx, cy, sx, sy = cn[1], cn[2], cn[3], cn[4]
		for _, o in ipairs({ { 0, 0 }, { sx, 0 }, { 0, sy } }) do
			set(g, cx + o[1], cy + o[2], 3, GOLD.color)
			set(g, cx + o[1], cy + o[2], 2, GOLD_D.color)
			set(g, cx + o[1], cy + o[2], -2, GOLD.color)
		end
	end
	-- the ribbon hanging out of the bottom
	for _, y in ipairs({ Y0, Y0 - 1, Y0 - 2 }) do set(g, 3, y, 0, Color3.fromRGB(190, 35, 45)) end
	-- the emblem, glowing, raised off the cover (centred in the frame)
	local rows = EMBLEMS[id] or DEFAULT_EMBLEM
	sprite(g, rows, {
		["#"] = { color = glowC, neon = true },
		o = { color = Color3.fromRGB(255, 245, 220), neon = true },
	}, 1, 3, 1, -math.floor(#rows / 2))
	return render(id, { g })
end

-- A stone pedestal with a glowing rim in the relic's colour.
function BrickModels.Pedestal(theme: Color3): Model
	local g = group()
	local STONE, STONE_D = c(70, 70, 80), c(45, 45, 55)
	box(g, -4, 0, -4, 4, 0, 4, STONE_D)
	box(g, -3, 1, -3, 3, 1, 3, STONE)
	for x = -3, 3 do
		for z = -3, 3 do
			if math.max(math.abs(x), math.abs(z)) == 3 then
				set(g, x, 2, z, theme, true)
			end
		end
	end
	return render("Pedestal", { g })
end

return BrickModels
