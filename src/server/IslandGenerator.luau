--!strict
--[[
	IslandGenerator.luau
	Builds a run's islands (RunManager, MapData "isle"): RE's six, Level 1 to
	Level 6 (IslandIsles), laid out along the run's slot of the world
	(IslandConfig.Origin plus each isle's offset), and takes them down again.

	Each isle is built from its own height field: islets with ragged coasts,
	cliff-sided masses of rock stepping up to a summit where its ritual site
	stands, stair paths cut into the cliffs, a river falling tier to tier
	into its pools, sea stacks offshore. The land is blocks (IslandVoxel),
	terrain only the water. Then its landmarks are built (each isle's `pois`),
	its ritual site raised on the summit, its scenery placed (IslandScenery:
	falls, bridges, lava, the summit's landmark, trees, ...), and its spawn
	sources, chest spots and props scattered.

	A run is on one isle at a time, all six built in the same place, the
	run's own: it starts on Isle 1, and Advance (the isle's guardian slain
	at its altar) takes that isle down and raises the next in its place (its
	sources, chests and altar the run's from then on).

	  IslandGenerator.Build(runId, slot, seed, opts?) → Island   (yields; opts.isle: start on that isle, a preview)
	  IslandGenerator.Advance(runId) → (number?, number?)       (yields: the new isle, its first chest spot)
	  IslandGenerator.Get(runId) → Island?
	  IslandGenerator.Forget(runId)                             (clears the terrain too)

	An Island carries what the rest of the mode needs: where players arrive,
	the spawn sources, the chest spots, the landmarks, the current altar and
	its statues, and RegionAt(pos) / GroundAt(pos).
--]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local IslandKit = require(Shared:WaitForChild("IslandKit"))
local IslandScenery = require(script.Parent:WaitForChild("IslandScenery"))
local IslandVoxel = require(script.Parent:WaitForChild("IslandVoxel"))

local IslandGenerator = {}

export type Source = { pos: Vector3, region: string, kind: string, gone: boolean? }
export type ChestSpot = { cf: CFrame, kind: string, region: string, gone: boolean? }
export type Poi = { id: string, name: string, region: string, pos: Vector3, radius: number, xp: number }
export type Isle = {
	n: number,
	def: any,
	origin: Vector3,
	field: any,
	folder: Folder?,
	ground: Instance?,
	ready: boolean,
	gone: boolean,
	sources: { Source },
	chestSpots: { ChestSpot },
	pois: { Poi },
	shrineSpots: { CFrame },
	arrival: CFrame?,          -- where players stand on it (the docks; its southern shore)
	altar: CFrame?,
	altarModel: Model?,
	statues: { Model },
	runes: { BasePart },
	cracks: { BasePart },
}
export type Island = {
	runId: string,
	origin: Vector3,           -- the run's origin (Isle 1 at its offset from it)
	folder: Folder,
	seed: number,
	spawn: CFrame,
	sources: { Source },
	chestSpots: { ChestSpot },
	pois: { Poi },
	altar: CFrame,             -- the current isle's altar base, on its platform
	altarModel: Model,
	statues: { Model },
	runes: { BasePart },       -- its platform's ring of runes (dark until the ritual)
	cracks: { BasePart },      -- the glowing cracks under its stone
	shrineSpots: { CFrame },   -- where an Ancient Echo's shrine may rise (IslandEvents)
	current: number,           -- the isle being played (1..6)
	isles: { Isle },
	RegionAt: (Vector3) -> string,
	GroundAt: (Vector3) -> number?,
}

local islands: { [string]: Island } = {}
local terrain = Workspace.Terrain
local ISLES = IslandConfig.Isles
local BASE = IslandConfig.Shape

-- An isle's shape, reading through to the shared defaults.
local shapes: { [any]: any } = {}
local function shapeOf(def: any): any
	local s = shapes[def]
	if not s then
		s = setmetatable(def.shape, { __index = BASE })
		shapes[def] = s
	end
	return s
end

-- ── The height field ────────────────────────────────────────────────────────
type Field = {
	shape: any,
	def: any,
	coast: (number) -> number,
	height: (number, number) -> number,
	weights: (number, number) -> { [string]: number },
	river: (number, number) -> (number, number, number?), -- how much of the river is here (0..1), its water's surface, a pool's depth
	blocky: (number, number) -> boolean, -- (the land is all blocks: always true)
	region: (number, number) -> string, -- the region that holds a point
	onPath: (number, number) -> boolean, -- on one of the stair paths
	-- each path's line every 2 studs (x, the stairs' height, z), isle space
	paths: { { Vector3 } },
	-- the river's line every 2 studs (x, its water's surface, z)
	riverLine: { Vector3 },
	-- the bridges between the islets: their ends on each cliff-top, their kind
	bridges: { { a: Vector3, b: Vector3, kind: string } },
	-- the pools (their centre, radius, water's surface)
	pools: { { x: number, z: number, r: number, y: number, depth: number? } },
	islet: (number, number) -> string?, -- the islet that holds a point (nil: the sea)
	-- a random point (isle space) on one of a region's islets, or nil
	sample: (string, Random) -> (number?, number?),
	-- where the main islet's high ground ends walking out from its centre
	-- toward a direction (isle space, at the ground's height there)
	edge: (Vector3) -> Vector3,
}
local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

local function makeField(seed: number, def: any): Field
	local SHAPE = shapeOf(def)
	local rng = Random.new(seed)
	local s1, s2, s3, s4 = rng:NextNumber(0, 100), rng:NextNumber(0, 100), rng:NextNumber(0, 100), rng:NextNumber(0, 100)
	local R = SHAPE.radius
	local function coast(theta: number): number
		local c, s = math.cos(theta), math.sin(theta)
		return R * (1 + SHAPE.coastWobble * (math.noise(c * 1.3 + s1, s * 1.3 + s2) + 0.5 * math.noise(c * 3 + s3, s * 3 + s4)))
	end
	-- each region's pull at a point: the biome of the islet it's on (or
	-- nearest), a beach's own where the isle has one
	local regionAt: (number, number) -> string
	local function weights(x: number, z: number): { [string]: number }
		return { [regionAt(x, z)] = 1 }
	end
	local P = SHAPE.plateau

	-- the islets, in studs, each with its own ragged coast
	local islets = {}
	local isletById = {}
	for i, it in ipairs(SHAPE.islets) do
		local rec = { id = it[1], x = it[2] * R, z = it[3] * R, r = it[4] * R, o = i * 3.7 + s2 }
		table.insert(islets, rec)
		isletById[rec.id] = rec
	end
	-- how far into its nearest islet a point is (under 1: land), and which
	local function nearest(x: number, z: number): (number, any)
		local best, which = math.huge, nil
		for _, it in ipairs(islets) do
			local dx, dz = x - it.x, z - it.z
			if math.abs(dx) > it.r * 1.6 or math.abs(dz) > it.r * 1.6 then continue end
			local d = (0.66 * math.sqrt(dx * dx + dz * dz) + 0.34 * math.max(math.abs(dx), math.abs(dz))) / it.r
				+ 0.06 * math.noise(x / 40 + it.o, z / 40) + 0.03 * math.noise(x / 13, z / 13 + it.o)
			if d < best then best, which = d, it end
		end
		return best, which
	end
	-- the masses of rock, in studs: broad plateaus with long gentle skirts,
	-- or (marked) cliffs, their edges sheer
	local masses = {}
	for i, m in ipairs(SHAPE.masses) do
		table.insert(masses, { x = m[1] * R, z = m[2] * R, r = m[3] * R, h = m[4], cliff = m[5] == true, o = i * 7.31 + s1 })
	end
	-- the isle's lie of the land (IslandIsles `terrain`): how steep its slopes
	-- may be, its rolling hills (height, breadth), how much is left open
	local TER = SHAPE.terrain or {}
	local SLOPE = TER.slope or 0.34
	local HILLS, HSCALE, OPEN = TER.hills or 8, TER.hillScale or 200, TER.open or 0.45
	-- the landmarks' sites, levelled (centre, radius, the height there), set
	-- below once height exists
	local flats: { { x: number, z: number, r: number, y: number } } = {}

	-- the ground before the paths and the river cut it
	local function raw(x: number, z: number): number
		local r = math.sqrt(x * x + z * z)
		local t = nearest(x, z)
		-- the islet's beach out to its coast, then the sea floor
		local h = if t < 1 then 1 + 2.2 * (1 - smooth((t - 0.6) / 0.4))
			else SHAPE.seaFloor * smooth((t - 1) / 0.3) - 1.5 * (1 - smooth((t - 1) / 0.3))
		if t >= 0.97 then
			-- (sea stacks round the isle)
			if t > 0.98 then
				for _, st in ipairs(SHAPE.stacks) do
					local th = math.rad(st[1])
					local cr = coast(th) * st[2]
					local dx, dz = x - math.cos(th) * cr, z - math.sin(th) * cr
					local d = math.sqrt(dx * dx + dz * dz) / st[3] + 0.12 * math.noise(x / 12 + s3, z / 12)
					if d < 1 then
						-- (stepped: a broad foot, a narrower top)
						local hs = if d < 0.62 then st[4] else st[4] * 0.45
						h = math.max(h, 4 * math.floor(hs / 4 + 0.5))
					end
				end
			end
			return h
		end
		-- broad rolling hills, fading toward the coasts, and wide stretches left
		-- open (flat) to fight in
		local inland = smooth((0.92 - t) / 0.3)
		if inland > 0 then
			local n = math.noise(x / HSCALE + s1, z / HSCALE + s2) + 0.5 * math.noise(x / (HSCALE * 0.45) + s3, z / (HSCALE * 0.45) + s4)
			local open = smooth((math.noise(x / (HSCALE * 1.8) + s4, z / (HSCALE * 1.8) + s1) + 0.5 - OPEN) / 0.35)
			h += HILLS * smooth(n * 0.7 + 0.5) * open * inland
		end
		-- the summit: a flat crown on a broad dome, its sides never steeper than SLOPE
		local sq = 0.7 * r + 0.3 * math.max(math.abs(x), math.abs(z))
		local crown = P.radius * (1 + 0.08 * math.noise(x / 60 + s2, z / 60))
		local dome = if sq <= crown then P.height else P.height * (1 - smooth((sq - crown) / (P.height * 1.5 / SLOPE)))
		h = math.max(h, dome)
		-- the masses: plateaus on gentle skirts, or cliffs
		local n1 = 0.08 * math.noise(x / 60 + s3, z / 60 + s4)
		for _, m in ipairs(masses) do
			local dx, dz = x - m.x, z - m.z
			local reach = if m.cliff then m.r * 1.3 else m.r + m.h * 1.5 / SLOPE
			if math.abs(dx) > reach or math.abs(dz) > reach then continue end
			local dist = 0.75 * math.sqrt(dx * dx + dz * dz) + 0.25 * math.max(math.abs(dx), math.abs(dz))
			local v: number
			if m.cliff then
				local d = dist / m.r + n1 + 0.04 * math.noise(x / 16 + m.o, z / 16)
				v = m.h * (1 - smooth((d - 1) * m.r / 4))
			else
				local d = dist / m.r + n1
				v = if d <= 1 then m.h else m.h * (1 - smooth((d - 1) * m.r / (m.h * 1.5 / SLOPE)))
			end
			if v > h then h = v end
		end
		-- the landmarks' sites and the pools' basins, levelled
		for _, f in ipairs(flats) do
			local d = math.sqrt((x - f.x) ^ 2 + (z - f.z) ^ 2)
			if d < f.r + 10 then h += (f.y - h) * (1 - smooth((d - f.r) / 10)) end
		end
		return h
	end

	regionAt = function(x: number, z: number): string
		local t, it = nearest(x, z)
		if not it then return def.region end
		if SHAPE.beachRegion and t < 1 and raw(x, z) < 5 then return SHAPE.beachRegion end
		return SHAPE.isletRegion[it.id] or def.region
	end
	-- (level each pool's basin, and each built landmark's site, at the
	-- height its centre had)
	for _, pl in ipairs(SHAPE.pools) do
		local px, pz = pl[1] * R, pl[2] * R
		table.insert(flats, { x = px, z = pz, r = pl[3] * R + 6, y = math.floor(raw(px, pz) + 0.5) })
	end
	for _, poi in ipairs(def.pois) do
		if poi.build ~= "none" and poi.build ~= "docks" and poi.build ~= "shipwreck" and poi.dist > 0 then
			local th = math.rad(poi.bearing)
			local c = coast(th)
			local px, pz = math.cos(th) * c * poi.dist, math.sin(th) * c * poi.dist
			local y = math.max(math.floor(raw(px, pz) + 0.5), 2)
			table.insert(flats, { x = px, z = pz, r = poi.radius * 0.55, y = y })
		end
	end
	-- a line (u, v in radii) sampled every 2 studs
	local function sample(line: { { number } }): { Vector3 }
		local pts: { Vector3 } = {}
		for i = 1, #line - 1 do
			local a = Vector3.new(line[i][1] * R, 0, line[i][2] * R)
			local b = Vector3.new(line[i + 1][1] * R, 0, line[i + 1][2] * R)
			local n = math.max(1, math.floor((b - a).Magnitude / 2))
			for k = (if i == 1 then 0 else 1), n do table.insert(pts, a:Lerp(b, k / n)) end
		end
		return pts
	end
	-- the bridges: each from one islet's cliff-top to the other's, along the
	-- line between their centres (its ends where the high ground gives out)
	local bridges: { { a: Vector3, b: Vector3, kind: string } } = {}
	local lines: { { { number } } } = {}
	for _, l in ipairs(SHAPE.paths) do table.insert(lines, l) end
	local function walkOut(from: any, dir: Vector3, maxD: number): Vector3
		local a = Vector3.new(from.x, 0, from.z)
		local d, last = 0, a
		while d < maxD do
			local q = a + dir * d
			local qt, qi = nearest(q.X, q.Z)
			if qt >= 0.97 or qi ~= from or raw(q.X, q.Z) < 10 then break end
			last = q
			d += 2
		end
		last -= dir * 3 -- (set back from the edge)
		return Vector3.new(last.X, raw(last.X, last.Z), last.Z)
	end
	local function landing(from: any, to: any): Vector3
		local a, b = Vector3.new(from.x, 0, from.z), Vector3.new(to.x, 0, to.z)
		return walkOut(from, (b - a).Unit, (b - a).Magnitude)
	end
	local MAIN = isletById.main or islets[1]
	for _, br in ipairs(SHAPE.bridges) do
		local A, B = isletById[br[1]], isletById[br[2]]
		local a, b = landing(A, B), landing(B, A)
		table.insert(bridges, { a = a, b = b, kind = br[3] })
		-- (on an islet whose top stands above its landing, stairs up to its top)
		for _, e in ipairs({ { A, a }, { B, b } }) do
			local it, at = e[1], e[2]
			if it ~= MAIN and raw(it.x, it.z) > at.Y + 4 then
				table.insert(lines, { { at.X / R, at.Z / R }, { it.x / R, it.z / R } })
			end
		end
	end
	-- the main islet's spiral stairs, the summit's edge down to its rim
	for _, cl in ipairs(SHAPE.climbs) do
		local line = {}
		for k = 0, 6 do
			local f = k / 6
			local ang = math.rad(cl[1] + (cl[2] - cl[1]) * f)
			local rr = (P.radius - 12) + (MAIN.r - 16 - (P.radius - 12)) * f
			table.insert(line, { (MAIN.x + math.cos(ang) * rr) / R, (MAIN.z + math.sin(ang) * rr) / R })
		end
		table.insert(lines, line)
	end
	-- the stair paths: the lowest ramp over the ground that never climbs or
	-- falls more steeply than pathSlope (a stone causeway where the ground
	-- drops away beneath it), so every stair reaches both its ends
	local paths: { { Vector3 } } = {}
	for _, line in ipairs(lines) do
		local pts = sample(line)
		local hs = {}
		for i, p in ipairs(pts) do hs[i] = raw(p.X, p.Z) end
		for i = 2, #pts do
			hs[i] = math.max(hs[i], hs[i - 1] - SHAPE.pathSlope * (pts[i] - pts[i - 1]).Magnitude)
		end
		for i = #pts - 1, 1, -1 do
			hs[i] = math.max(hs[i], hs[i + 1] - SHAPE.pathSlope * (pts[i + 1] - pts[i]).Magnitude)
		end
		local out: { Vector3 } = {}
		for i, p in ipairs(pts) do out[i] = Vector3.new(p.X, hs[i], p.Z) end
		table.insert(paths, out)
	end
	local boxes = {}
	for i, pts in ipairs(paths) do
		local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
		for _, p in ipairs(pts) do
			x0, x1, z0, z1 = math.min(x0, p.X), math.max(x1, p.X), math.min(z0, p.Z), math.max(z1, p.Z)
		end
		boxes[i] = { x0, x1, z0, z1 }
	end
	-- where a point is on a path: the stairs' height there (or nil)
	local HALF = SHAPE.pathWidth / 2 + 2
	local function pathAt(x: number, z: number): number?
		local best, bh = HALF * HALF, nil
		for pi, pts in ipairs(paths) do
			local bx = boxes[pi]
			if x < bx[1] - HALF or x > bx[2] + HALF or z < bx[3] - HALF or z > bx[4] + HALF then continue end
			-- (a coarse pass, then the points round the nearest)
			for i = 1, #pts, 4 do
				local p = pts[i]
				local dx, dz = x - p.X, z - p.Z
				local d2 = dx * dx + dz * dz
				if d2 < (HALF + 8) ^ 2 then
					for k = math.max(1, i - 4), math.min(#pts, i + 4) do
						local q = pts[k]
						local ex, ez = x - q.X, z - q.Z
						local e2 = ex * ex + ez * ez
						if e2 < best then best, bh = e2, q.Y end
					end
				end
			end
		end
		return bh
	end

	-- the river: its line, its water's surface the ground's under the line
	-- (so it falls at every cliff), its pools
	local RV = SHAPE.river
	local riverLine: { Vector3 } = {}
	if RV then
		for _, p in ipairs(sample(RV.line)) do
			-- (it meanders a little on its way down)
			local q = p + Vector3.new(math.sin(p.Z / 26 + s1) * 2.5, 0, 0)
			table.insert(riverLine, Vector3.new(q.X, raw(q.X, q.Z) - 1, q.Z))
		end
	end
	local RIVER_W = if RV then RV.width else 10
	local RIVER_D = if RV then RV.depth else 3
	local pools = {}
	for _, pl in ipairs(SHAPE.pools) do
		local x, z = pl[1] * R, pl[2] * R
		table.insert(pools, { x = x, z = z, r = pl[3] * R, y = raw(x, z) - 1, depth = pl[4] })
	end
	local rx0, rx1, rz0, rz1 = math.huge, -math.huge, math.huge, -math.huge
	for _, p in ipairs(riverLine) do
		rx0, rx1, rz0, rz1 = math.min(rx0, p.X), math.max(rx1, p.X), math.min(rz0, p.Z), math.max(rz1, p.Z)
	end
	local function river(x: number, z: number): (number, number, number?)
		for _, pl in ipairs(pools) do
			local d = math.sqrt((x - pl.x) ^ 2 + (z - pl.z) ^ 2) + 2 * math.noise(x / 9, z / 9)
			if d < pl.r then return 1, pl.y, pl.depth end
		end
		if #riverLine == 0 or x < rx0 - 40 or x > rx1 + 40 or z < rz0 - 40 or z > rz1 + 40 then return 0, 0 end
		local best, by = math.huge, 0
		for i = 1, #riverLine, 3 do
			local p = riverLine[i]
			local dx, dz = x - p.X, z - p.Z
			local d2 = dx * dx + dz * dz
			if d2 < best then best, by = d2, p.Y end
		end
		local w = 1 - smooth((math.sqrt(best) - RIVER_W / 2) / 3)
		if w <= 0 then return 0, 0 end
		return w, by
	end

	local function height(x: number, z: number): number
		local ph = pathAt(x, z)
		if ph then return ph end
		local h = raw(x, z)
		local w, surface, depth = river(x, z)
		if w > 0.5 then return math.min(h, surface + 1) - (depth or RIVER_D) end
		return h
	end
	local function blocky(_x: number, _z: number): boolean
		return true
	end
	local function onPath(x: number, z: number): boolean
		return pathAt(x, z) ~= nil
	end
	local function region(x: number, z: number): string
		return regionAt(x, z)
	end
	local function sampleRegion(regionId: string, r: Random): (number?, number?)
		local mine = {}
		for _, it in ipairs(islets) do
			if SHAPE.isletRegion[it.id] == regionId or SHAPE.beachRegion == regionId then table.insert(mine, it) end
		end
		if #mine == 0 then return nil, nil end
		for _ = 1, 12 do
			local it = mine[r:NextInteger(1, #mine)]
			local a = r:NextNumber(0, math.pi * 2)
			local d = math.sqrt(r:NextNumber()) * it.r * 0.92
			local x, z = it.x + math.cos(a) * d, it.z + math.sin(a) * d
			if math.sqrt(x * x + z * z) < P.radius + 4 then continue end -- (the ritual's own floor)
			if regionAt(x, z) == regionId then return x, z end
		end
		return nil, nil
	end
	local function islet(x: number, z: number): string?
		local t, it = nearest(x, z)
		return if t < 1 and it then it.id else nil
	end
	local function edge(dir: Vector3): Vector3
		local flat = Vector3.new(dir.X, 0, dir.Z)
		return walkOut(MAIN, if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, 1), R * 2)
	end
	return {
		shape = SHAPE, def = def,
		coast = coast, height = height, weights = weights, river = river, blocky = blocky, region = region, onPath = onPath,
		paths = paths, riverLine = riverLine, bridges = bridges, pools = pools, islet = islet, sample = sampleRegion, edge = edge,
	}
end

local function dominant(w: { [string]: number }): string
	local best, bw = "ruins", -1
	for id, v in pairs(w) do
		if v > bw then best, bw = id, v end
	end
	return best
end

-- ── Terrain ─────────────────────────────────────────────────────────────────
-- (the land is blocks, IslandVoxel: terrain only holds the water, and the
-- sea floor past and under the blocks' columns)
local MAT = Enum.Material
local SKY = 320 -- (above every isle's highest ground)

local function writeTerrain(origin: Vector3, field: Field)
	local SHAPE = field.shape
	local V = SHAPE.voxel
	local E = SHAPE.extent
	local Y0, Y1 = SHAPE.seaFloor - 10, SHAPE.plateau.height + 40
	Y0 = math.floor(Y0 / V) * V
	Y1 = math.ceil(Y1 / V) * V
	local ny = (Y1 - Y0) // V
	local CH = 16 -- voxels per chunk side
	local ox = math.floor((origin.X - E) / V) * V
	local oz = math.floor((origin.Z - E) / V) * V
	local nChunks = math.ceil(E * 2 / V / CH)
	for cx = 0, nChunks - 1 do
		for cz = 0, nChunks - 1 do
			local x0 = ox + cx * CH * V
			local z0 = oz + cz * CH * V
			local mats, occ = {}, {}
			for i = 1, CH do
				mats[i], occ[i] = {}, {}
				for j = 1, ny do mats[i][j], occ[i][j] = {}, {} end
			end
			for i = 0, CH - 1 do
				for k = 0, CH - 1 do
					local lx, lz = x0 + (i + 0.5) * V - origin.X, z0 + (k + 0.5) * V - origin.Z
					local h = field.height(lx, lz)
					local rw, surface = field.river(lx, lz)
					for j = 0, ny - 1 do
						local yb = Y0 + j * V -- the voxel's bottom
						local fill = math.clamp((h - yb) / V, 0, 1)
						local m, o = MAT.Air, 0
						if fill > 0 and (h < -0.6 or yb + V <= -14) then
							m, o = MAT.Sand, fill
						elseif fill < 1 and (yb < 0 or (rw > 0.5 and yb < surface)) then
							m, o = MAT.Water, 1
						end
						mats[i + 1][j + 1][k + 1] = m
						occ[i + 1][j + 1][k + 1] = o
					end
				end
			end
			local region = Region3.new(Vector3.new(x0, Y0, z0), Vector3.new(x0 + CH * V, Y1, z0 + CH * V)):ExpandToGrid(V)
			terrain:WriteVoxels(region, V, mats, occ)
			task.wait()
		end
	end
end

-- The run's sea: the largest isle's square and the open sea round it
-- (world X, Z bounds), kept inside the run's own slot.
local function routeBounds(base: Vector3): (number, number, number, number)
	local E = 0
	for _, def in ipairs(ISLES) do E = math.max(E, def.shape.extent) end
	E += IslandConfig.SEA_MARGIN
	local half = IslandConfig.SLOT_SPACING / 2 - 20
	local ex = math.min(E, half)
	return base.X - ex, base.X + ex, base.Z - E, base.Z + E
end

-- ── Placement ───────────────────────────────────────────────────────────────
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { terrain }
terrainOnly.IgnoreWater = true
-- (every isle's ground: IslandVoxel's blocks)
local grounds: { Instance } = {}
local function setGrounds()
	local list: { Instance } = { terrain }
	for _, g in ipairs(grounds) do table.insert(list, g) end
	terrainOnly.FilterDescendantsInstances = list
end

local function groundAt(pos: Vector3, from: number?): number?
	local hit = Workspace:Raycast(Vector3.new(pos.X, from or SKY, pos.Z), Vector3.new(0, -(from or SKY) - 60, 0), terrainOnly)
	return hit and hit.Position.Y or nil
end

-- A spot in a region (isle space → world), dry, not too steep, clear of
-- the spots already taken (`taken`, each with its own clearance).
type Taken = { { pos: Vector3, r: number } }
local function findSpot(rng: Random, origin: Vector3, field: Field, regionId: string, taken: Taken, clear: number, opts: { minH: number?, maxSlope: number? }?): Vector3?
	local o = opts or {}
	for _ = 1, 60 do
		local x, z = field.sample(regionId, rng)
		if not x or not z then continue end
		local h = field.height(x, z)
		if h < (o.minH or 1.2) then continue end
		local dx = field.height(x + 4, z) - field.height(x - 4, z)
		local dz = field.height(x, z + 4) - field.height(x, z - 4)
		if math.sqrt(dx * dx + dz * dz) / 8 > (o.maxSlope or 0.6) then continue end
		local world = origin + Vector3.new(x, 0, z)
		local ok = true
		for _, t in ipairs(taken) do
			if (Vector3.new(t.pos.X, 0, t.pos.Z) - Vector3.new(world.X, 0, world.Z)).Magnitude < t.r + clear then
				ok = false
				break
			end
		end
		if not ok then continue end
		local y = groundAt(world)
		if not y or y < 0.8 then continue end
		return Vector3.new(world.X, y, world.Z)
	end
	return nil
end

-- ── The ritual site ─────────────────────────────────────────────────────────
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end
local function sp(parent: Instance, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, props: { [string]: any }?): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanTouch = true, false
	p.CastShadow = size.Magnitude > 10
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Size, p.CFrame, p.Color, p.Material = size, cf, color, mat
	if props then for k, v in pairs(props) do (p :: any)[k] = v end end
	p.Parent = parent
	return p
end

-- The isle's ritual site on its summit, in its own stone (`look`).
local function buildSanctuary(origin: Vector3, field: Field, rng: Random, parent: Instance): (CFrame, Model, { Model }, { BasePart }, { BasePart })
	local R = IslandConfig.Ritual
	local look = field.def.altar
	local m = Instance.new("Model")
	m.Name = "RitualSite"
	-- (always on every client: the isle's landmark, seen from anywhere)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m.Parent = parent
	local center = origin + Vector3.new(0, field.shape.plateau.height + 2, 0)
	local DARK, DARK2, TRIM, RUNE = look.dark, look.dark2, look.pave, look.rune
	-- the paving: big square flagstones, worn away at its ragged edge
	local TILE = 15.5
	local NT = math.floor(R.platformRadius * 2 / TILE)
	local PAVE = { look.pave, look.pave2, DARK2 }
	for i = 0, NT - 1 do
		for k = 0, NT - 1 do
			local px = (i - (NT - 1) / 2) * TILE
			local pz = (k - (NT - 1) / 2) * TILE
			local edge = math.max(math.abs(px), math.abs(pz))
			if edge > R.platformRadius - 14 and rng:NextNumber() < 0.45 then continue end
			local tile = sp(m, Vector3.new(TILE - 0.4, 2, TILE - 0.4), CFrame.new(center + Vector3.new(px, -1, pz)), PAVE[(i * 3 + k) % 3 + 1], MAT.Slate)
			tile.Name = "Paving"
		end
	end
	-- the inner circle: rings of paving and the runes round them
	for _, rr in ipairs({ 30, 50 }) do
		local ring = sp(m, Vector3.new(0.1, rr * 2, rr * 2), CFrame.new(center + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)), TRIM, MAT.Slate, { CanCollide = false })
		ring.Shape = Enum.PartType.Cylinder
		local inner = sp(m, Vector3.new(0.12, rr * 2 - 3, rr * 2 - 3), CFrame.new(center + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90)), DARK, MAT.Slate, { CanCollide = false })
		inner.Shape = Enum.PartType.Cylinder
	end
	local runes: { BasePart } = {}
	local runeN = 32
	for k = 0, runeN - 1 do
		local a = k / runeN * math.pi * 2
		local r = sp(m, Vector3.new(1.6, 0.14, if k % 2 == 0 then 3 else 1.6), CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0.12, -40) * CFrame.Angles(0, (k % 3) * 0.6, 0),
			RUNE, MAT.Neon, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.82 })
		r.Name = "Rune"
		table.insert(runes, r)
	end
	-- cracks in the stone, energy glowing beneath them
	local cracks: { BasePart } = {}
	for _ = 0, 13 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r0 = rng:NextNumber(8, 52)
		for s = 0, 2 do
			local c = sp(m, Vector3.new(rng:NextNumber(0.4, 0.9), 0.12, 4), CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0.1, -r0 - s * 3.6) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0),
				look.crack, MAT.Neon, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.55 })
			c.Name = "Crack"
			table.insert(cracks, c)
		end
	end
	-- the altar
	local altarCF = CFrame.new(center) * CFrame.Angles(0, math.rad(90), 0)
	local altar = IslandKit.Altar(CFrame.new(center), m)
	-- the eight statues, facing in
	local statues: { Model } = {}
	for i = 1, 8 do
		local a = (i - 1) / 8 * math.pi * 2
		local pos = center + Vector3.new(math.sin(a), 0, -math.cos(a)) * R.statueRing
		table.insert(statues, IslandKit.Statue(i, CFrame.lookAt(pos, Vector3.new(center.X, pos.Y, center.Z)), m))
	end
	-- broken pillars round the edge, chains between some, skulls and candles
	local pillars = {}
	for k = 0, 15 do
		local a = (k + 0.5) / 16 * math.pi * 2
		local pos = center + Vector3.new(math.sin(a), 0, -math.cos(a)) * (R.platformRadius - 5)
		local h = if rng:NextNumber() < 0.4 then rng:NextNumber(5, 10) else rng:NextNumber(14, 20)
		local p = sp(m, Vector3.new(3, h, 3), CFrame.new(pos + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, a, math.rad(rng:NextNumber(-3, 3))), DARK2, MAT.Slate)
		table.insert(pillars, { pos = pos, h = h, part = p })
	end
	for k = 1, #pillars do
		local a, b = pillars[k], pillars[k % #pillars + 1]
		if a.h > 12 and b.h > 12 and rng:NextNumber() < 0.7 then
			local top = math.min(a.h, b.h) - 2
			local pa, pb = a.pos + Vector3.new(0, top, 0), b.pos + Vector3.new(0, top, 0)
			local mid = (pa + pb) / 2 - Vector3.new(0, 2.2, 0)
			for _, seg in ipairs({ { pa, mid }, { mid, pb } }) do
				local l = (seg[2] - seg[1]).Magnitude
				sp(m, Vector3.new(0.35, 0.35, l), CFrame.lookAt((seg[1] + seg[2]) / 2, seg[2]), rgb(28, 26, 30), MAT.Metal, { CanCollide = false, CastShadow = false })
			end
		end
	end
	for _ = 0, 11 do
		local a = rng:NextNumber(0, math.pi * 2)
		local pos = center + Vector3.new(math.sin(a), 0, -math.cos(a)) * rng:NextNumber(12, 55)
		if rng:NextNumber() < 0.5 then
			local skull = sp(m, Vector3.one * 1.1, CFrame.new(pos + Vector3.new(0, 0.5, 0)), rgb(214, 204, 184), MAT.SmoothPlastic, { CanCollide = false, Shape = Enum.PartType.Ball })
			skull.CastShadow = false
		else
			for _ = 0, 2 do
				local off = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
				local h = rng:NextNumber(0.6, 1.4)
				sp(m, Vector3.new(0.4, h, 0.4), CFrame.new(pos + off + Vector3.new(0, h / 2, 0)), rgb(220, 210, 180), MAT.SmoothPlastic, { CanCollide = false })
				local fl = sp(m, Vector3.new(0.2, 0.35, 0.2), CFrame.new(pos + off + Vector3.new(0, h + 0.2, 0)), rgb(255, 190, 90), MAT.Neon, { CanCollide = false, CanQuery = false, CastShadow = false })
				fl.Name = "Candle"
			end
		end
	end
	-- floating motes over it all, and a shaft of light up from the altar:
	-- the isle's landmark, seen from the shore and from the isle before it
	local motes = sp(m, Vector3.new(R.platformRadius * 1.6, 12, R.platformRadius * 1.6), CFrame.new(center + Vector3.new(0, 14, 0)), RUNE, MAT.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	motes.Name = "Motes"
	local e = Instance.new("ParticleEmitter")
	e.Texture = IslandKit.SPARK
	e.Color = ColorSequence.new(RUNE, look.beam)
	e.Size = NumberSequence.new(0.5, 0)
	e.Transparency = NumberSequence.new(0.1, 1)
	e.Lifetime = NumberRange.new(3, 5)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.Rate = 10
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e:SetAttribute("Gameplay", true) -- (a landmark: PerfMode leaves it)
	e.Parent = motes
	local beam = sp(m, Vector3.new(4, 260, 4), CFrame.new(center + Vector3.new(0, 140, 0)), look.beam, MAT.Neon,
		{ CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.7 })
	beam.Name = "Beacon"
	return altarCF, altar, statues, runes, cracks
end

-- ── An isle ─────────────────────────────────────────────────────────────────
local function isleOrigin(island: Island, _n: number): Vector3
	-- (one isle at a time, each in the run's own place)
	return island.origin
end

local function build(island: Island, n: number): Isle
	local t0 = os.clock()
	local def = ISLES[n]
	local isle = island.isles[n]
	local origin = isle.origin
	local field = makeField(island.seed + n * 101, def)
	isle.field = field
	local rng = Random.new(island.seed + n * 7)
	local folder = Instance.new("Folder")
	folder.Name = "Isle_" .. n .. "_" .. def.id
	folder.Parent = island.folder
	isle.folder = folder

	writeTerrain(origin, field)
	-- the ground, in blocks
	local ground = IslandVoxel.Build(origin, field, folder)
	isle.ground = ground
	table.insert(grounds, ground)
	setGrounds()
	task.wait()

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	local P = field.shape.plateau
	local taken: Taken = { { pos = origin, r = P.radius + 22 } } -- (the summit and its stairs)

	-- the landmarks
	for _, poi in ipairs(def.pois) do
		local theta = math.rad(poi.bearing)
		local c = field.coast(theta)
		local lp = Vector3.new(math.cos(theta) * c * poi.dist, 0, math.sin(theta) * c * poi.dist)
		local pos = origin + lp
		if poi.dist <= 0 then
			pos = origin + Vector3.new(0, P.height + 2, 0)
		else
			local y = groundAt(pos) or field.height(lp.X, lp.Z)
			-- (the docks and the wreck stand at the water's edge)
			if poi.build == "docks" or poi.build == "shipwreck" then y = math.max(y, 0.2)
			elseif poi.build ~= "none" then y = math.max(y, 1) end
			pos = Vector3.new(pos.X, y, pos.Z)
			if poi.build ~= "none" then
				local face = CFrame.lookAt(pos, Vector3.new(origin.X, pos.Y, origin.Z))
				IslandKit.Build(poi.build, face, rng, props)
			end
		end
		table.insert(isle.pois, { id = def.id .. "_" .. poi.id, name = poi.name, region = poi.region, pos = pos, radius = poi.radius, xp = poi.xp })
		table.insert(taken, { pos = pos, r = poi.radius * 0.7 })
		if poi.build == "docks" then
			-- arriving at the land end of the docks, facing the isle
			local inland = (Vector3.new(origin.X, 0, origin.Z) - Vector3.new(pos.X, 0, pos.Z)).Unit
			local at = pos + inland * 22
			local y = groundAt(at) or 4
			isle.arrival = CFrame.lookAt(Vector3.new(at.X, y + 3, at.Z), Vector3.new(origin.X, y + 3, origin.Z))
		end
	end
	task.wait()

	-- piers off the beaches (bearings, at the water's edge)
	for _, bearing in ipairs(def.piers or {}) do
		local theta = math.rad(bearing)
		local c = field.coast(theta) * 1.15
		for _ = 1, 30 do
			-- (walk in from the sea to the first dry ground)
			local lp = Vector3.new(math.cos(theta), 0, math.sin(theta)) * c
			local h = field.height(lp.X, lp.Z)
			if h > 4 then break end -- (a cliff: no pier)
			if h > 0 then
				local pos = origin + lp
				local face = CFrame.lookAt(Vector3.new(pos.X, 0.2, pos.Z), Vector3.new(origin.X, 0.2, origin.Z))
				IslandKit.Build("pier", face, rng, props)
				table.insert(taken, { pos = pos, r = 10 })
				break
			end
			c -= 4
		end
	end

	-- the ritual site
	local altarCF, altarModel, statues, runes, cracks = buildSanctuary(origin, field, rng, folder)
	isle.altar, isle.altarModel, isle.statues, isle.runes, isle.cracks = altarCF, altarModel, statues, runes, cracks
	task.wait()
	-- the scenery: falls, bridges, lava, the summit's landmark, trees, ...
	IslandScenery.Build(origin, field, rng, props, groundAt, taken)
	task.wait()

	-- spawn sources (before the props, so they have their spots)
	local srcFolder = Instance.new("Folder")
	srcFolder.Name = "SpawnSources"
	srcFolder.Parent = folder
	for regionId, counts in pairs(def.sources) do
		for kind, count in pairs(counts) do
			for _ = 1, count do
				local pos = findSpot(rng, origin, field, regionId, taken, 14)
				if pos then
					IslandKit.Build("src_" .. kind, CFrame.new(pos), rng, srcFolder)
					table.insert(isle.sources, { pos = pos, region = regionId, kind = kind })
					table.insert(taken, { pos = pos, r = 6 })
				end
			end
		end
	end
	-- chest spots (IslandChests fills them)
	for _, spec in ipairs(def.chests) do
		for i = 1, spec.count do
			local regionId = spec.regions[(i - 1) % #spec.regions + 1]
			local pos = findSpot(rng, origin, field, regionId, taken, 8)
			if pos then
				table.insert(isle.chestSpots, { cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), kind = spec.kind, region = regionId })
				table.insert(taken, { pos = pos, r = 4 })
			end
		end
	end
	-- where an Ancient Echo's shrine may rise
	for regionId in pairs(def.props) do
		for _ = 1, 2 do
			local pos = findSpot(rng, origin, field, regionId, taken, 12)
			if pos then
				table.insert(isle.shrineSpots, CFrame.new(pos))
				table.insert(taken, { pos = pos, r = 8 })
			end
		end
	end
	-- props (after the sources, the chests and the shrines have their spots)
	for regionId, counts in pairs(def.props) do
		for name, count in pairs(counts) do
			local clear = if name == "tree" or name == "palm" then 7 elseif name == "wall" or name == "log" then 9 elseif name == "crack" or name == "mushroom" then 3 else 5
			for _ = 1, count do
				local pos = findSpot(rng, origin, field, regionId, taken, clear, { maxSlope = if name == "spire" or name == "rock" then 0.9 else 0.55 })
				if pos then
					IslandKit.Build(name, CFrame.new(pos - Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng, props)
					table.insert(taken, { pos = pos, r = clear * 0.5 })
				end
			end
		end
		task.wait()
	end

	-- (an isle without docks: players land on its southern shore, facing in)
	if not isle.arrival then
		local e = field.edge(Vector3.new(0, 0, -1))
		local at = origin + e + Vector3.new(0, 0, 10)
		local y = groundAt(at) or e.Y
		isle.arrival = CFrame.lookAt(Vector3.new(at.X, y + 3, at.Z), Vector3.new(origin.X, y + 3, origin.Z))
	end
	isle.ready = true
	print(string.format("[IslandGenerator] %s: isle %d (%s) built in %.1fs: %d props, %d sources, %d chest spots",
		island.runId, n, def.name, os.clock() - t0, #props:GetChildren(), #isle.sources, #isle.chestSpots))
	return isle
end

-- Build isle `n` if no one has (or wait for whoever is).
local function prepare(island: Island, n: number): Isle?
	local isle = island.isles[n]
	if not isle then return nil end
	if isle.ready then return isle end
	if isle.folder then
		-- (another thread is building it)
		local t0 = os.clock()
		while not isle.ready and not isle.gone and os.clock() - t0 < 60 do task.wait(0.2) end
		return if isle.ready then isle else nil
	end
	local ok, err = pcall(build, island, n)
	if not ok then
		warn("[IslandGenerator] isle " .. n .. ":", err)
		return nil
	end
	return isle
end

-- The isle the run plays now: its sources, chests, landmarks and altar
-- become the run's.
local function activate(island: Island, n: number): number
	local isle = island.isles[n]
	local first = #island.chestSpots + 1
	table.clear(island.sources)
	table.clear(island.pois)
	table.clear(island.shrineSpots)
	for _, s in ipairs(isle.sources) do table.insert(island.sources, s) end
	for _, c in ipairs(isle.chestSpots) do table.insert(island.chestSpots, c) end
	for _, p in ipairs(isle.pois) do table.insert(island.pois, p) end
	for _, s in ipairs(isle.shrineSpots) do table.insert(island.shrineSpots, s) end
	if isle.altar and isle.altarModel then
		island.altar, island.altarModel = isle.altar, isle.altarModel
		island.statues, island.runes, island.cracks = isle.statues, isle.runes, isle.cracks
	end
	if isle.arrival then island.spawn = isle.arrival end
	island.current = n
	return first
end

-- Take an isle down: its parts and its place in the run's lists (its chest
-- spots stay, marked gone: IslandChests counts them by index).
local function unload(island: Island, n: number)
	local isle = island.isles[n]
	if not isle or isle.gone or not isle.ready then return end
	isle.gone = true
	local gi = isle.ground and table.find(grounds, isle.ground)
	if gi then table.remove(grounds, gi) end
	setGrounds()
	for _, c in ipairs(isle.chestSpots) do c.gone = true end
	for _, s in ipairs(isle.sources) do s.gone = true end
	local function keep(list: { any }, own: { any })
		for i = #list, 1, -1 do
			if table.find(own, list[i]) then table.remove(list, i) end
		end
	end
	keep(island.sources, isle.sources)
	keep(island.pois, isle.pois)
	keep(island.shrineSpots, isle.shrineSpots)
	if isle.folder then isle.folder:Destroy() end
end

-- ── Build ───────────────────────────────────────────────────────────────────
function IslandGenerator.Build(runId: string, slot: number, seed: number, opts: { isle: number? }?): Island
	local t0 = os.clock()
	IslandGenerator.Forget(runId)
	local base = IslandConfig.Origin(slot)
	local folder = Instance.new("Folder")
	folder.Name = "Island_" .. runId
	folder.Parent = Workspace

	local island: Island
	island = {
		runId = runId,
		origin = base,
		folder = folder,
		seed = seed,
		spawn = CFrame.new(base + Vector3.new(0, 30, -300)),
		sources = {},
		chestSpots = {},
		pois = {},
		altar = CFrame.new(base),
		altarModel = nil :: any,
		statues = {},
		runes = {},
		cracks = {},
		shrineSpots = {},
		current = 1,
		isles = {},
		RegionAt = function(pos: Vector3): string
			-- (the nearest built isle's)
			local best, bd = nil, math.huge
			for _, isle in ipairs(island.isles) do
				if not isle.ready or isle.gone then continue end
				local d = (Vector3.new(pos.X, 0, pos.Z) - Vector3.new(isle.origin.X, 0, isle.origin.Z)).Magnitude
				if d < bd then best, bd = isle, d end
			end
			if not best then return ISLES[1].region end
			local lp = pos - best.origin
			return dominant(best.field.weights(lp.X, lp.Z))
		end,
		GroundAt = function(pos: Vector3): number?
			return groundAt(pos, pos.Y + 6)
		end,
	}
	for n = 1, #ISLES do
		island.isles[n] = {
			n = n, def = ISLES[n], origin = isleOrigin(island, n), field = nil, folder = nil, ground = nil,
			ready = false, gone = false, sources = {}, chestSpots = {}, pois = {}, shrineSpots = {},
			statues = {}, runes = {}, cracks = {},
		}
	end
	islands[runId] = island

	-- the open sea under the whole route (each isle writes its own square
	-- over it as it's built)
	local x0, x1, z0, z1 = routeBounds(base)
	local STEP = 200
	for x = x0, x1 - 1, STEP do
		for z = z0, z1 - 1, STEP do
			local w, d = math.min(STEP, x1 - x), math.min(STEP, z1 - z)
			terrain:FillBlock(CFrame.new(x + w / 2, -6, z + d / 2), Vector3.new(w, 12, d), MAT.Water)
		end
		task.wait()
	end
	-- a bright sea, white sand, dark stone (terrain's look is one for the
	-- whole world: only the islands have any)
	terrain.WaterColor = Color3.fromRGB(22, 118, 190)
	terrain.WaterTransparency = 0.5
	terrain.WaterReflectance = 0.2
	terrain.WaterWaveSize = 0.15
	terrain.WaterWaveSpeed = 10
	terrain:SetMaterialColor(MAT.Sand, Color3.fromRGB(238, 226, 186))

	-- the first isle (or, for a preview, the one asked for)
	local n0 = math.clamp(if opts and opts.isle then opts.isle else 1, 1, #ISLES)
	prepare(island, n0)
	activate(island, n0)
	print(string.format("[IslandGenerator] %s: isle %d of %d raised in %.1fs", runId, island.current, #ISLES, os.clock() - t0))
	return island
end

-- The current isle's guardian is slain: the isle is taken down and the next
-- raised in its place (yields while it's built). Returns the new isle's
-- number and the index of its first chest spot (nil: the last isle was
-- already the current one).
function IslandGenerator.Advance(runId: string): (number?, number?)
	local island = islands[runId]
	if not island then return nil, nil end
	local n = island.current
	if n >= #ISLES then return nil, nil end
	unload(island, n)
	local nextIsle = prepare(island, n + 1)
	if not nextIsle or islands[runId] ~= island then return nil, nil end
	return n + 1, activate(island, n + 1)
end

function IslandGenerator.Get(runId: string?): Island?
	return if runId then islands[runId] else nil
end

-- Take a run's islands down: their parts, and the terrain back to empty air.
function IslandGenerator.Forget(runId: string)
	local island = islands[runId]
	if not island then return end
	islands[runId] = nil
	for _, isle in ipairs(island.isles) do
		isle.gone = true
		local gi = isle.ground and table.find(grounds, isle.ground)
		if gi then table.remove(grounds, gi) end
	end
	setGrounds()
	island.folder:Destroy()
	local x0, x1, z0, z1 = routeBounds(island.origin)
	task.spawn(function()
		local STEP = 200
		for x = x0, x1 - 1, STEP do
			for z = z0, z1 - 1, STEP do
				local w, d = math.min(STEP, x1 - x), math.min(STEP, z1 - z)
				terrain:FillBlock(CFrame.new(x + w / 2, (SKY - 60) / 2, z + d / 2), Vector3.new(w, SKY + 60, d), MAT.Air)
				task.wait()
			end
		end
	end)
end

return IslandGenerator
