--!strict
--[[
	IslandGenerator.luau
	Builds The Forgotten Isle for a run (RunManager, MapData "isle"), in its
	own slot of the world (IslandConfig.Origin), and takes it down again.

	The ground is terrain, written in chunks (WriteVoxels) from one height
	field: a wandering coast round the Ancient Sanctuary's plateau, each
	region (IslandConfig.Regions) bending it its own way — the highlands and
	the cave ridge rise, the ruins sink into flooded basins, the forest rolls,
	the shore flattens into beaches — with the sea round it all. Then the
	Hollow Caves are carved through the ridge, the landmarks (IslandConfig
	.Pois) are levelled into it and built, each region scatters its props
	(IslandKit), and the ritual site is raised on the plateau.

	  IslandGenerator.Build(runId, slot, seed) → Island   (yields)
	  IslandGenerator.Get(runId) → Island?
	  IslandGenerator.Forget(runId)                       (clears the terrain too)

	An Island carries what the rest of the mode needs: where players arrive,
	the spawn sources, the chest spots, the landmarks, the altar and its
	statues, and RegionAt(pos) / GroundAt(pos).
--]]

local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local IslandKit = require(Shared:WaitForChild("IslandKit"))

local IslandGenerator = {}

export type Source = { pos: Vector3, region: string, kind: string }
export type ChestSpot = { cf: CFrame, kind: string, region: string }
export type Island = {
	runId: string,
	origin: Vector3,
	folder: Folder,
	spawn: CFrame,
	sources: { Source },
	chestSpots: { ChestSpot },
	pois: { { id: string, name: string, region: string, pos: Vector3, radius: number, xp: number } },
	altar: CFrame,             -- the altar's base, on the platform
	altarModel: Model,
	statues: { Model },
	runes: { BasePart },       -- the platform's ring of runes (dark until the ritual)
	cracks: { BasePart },      -- the glowing cracks under the stone
	shrineSpots: { CFrame },   -- where an Ancient Echo's shrine may rise (IslandEvents)
	RegionAt: (Vector3) -> string,
	GroundAt: (Vector3) -> number?,
}

local islands: { [string]: Island } = {}
local terrain = Workspace.Terrain

local SHAPE = IslandConfig.Shape
local PLATFORM_TOP = SHAPE.plateau.height + 2

-- ── The height field ────────────────────────────────────────────────────────
type Field = {
	coast: (number) -> number,
	height: (number, number) -> number,
	weights: (number, number) -> { [string]: number },
}

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end
local function angleDiff(a: number, b: number): number
	return (a - b + 180) % 360 - 180
end

local function makeField(seed: number): Field
	local rng = Random.new(seed)
	local s1, s2, s3, s4 = rng:NextNumber(0, 100), rng:NextNumber(0, 100), rng:NextNumber(0, 100), rng:NextNumber(0, 100)
	local R = SHAPE.radius
	local function coast(theta: number): number
		local c, s = math.cos(theta), math.sin(theta)
		return R * (1 + SHAPE.coastWobble * (math.noise(c * 1.3 + s1, s * 1.3 + s2) + 0.5 * math.noise(c * 3 + s3, s * 3 + s4)))
	end
	-- each region's pull at a point (0..1), by bearing and by distance out
	local function weights(x: number, z: number): { [string]: number }
		local r = math.sqrt(x * x + z * z)
		local theta = math.atan2(z, x)
		local t = r / coast(theta)
		local deg = math.deg(theta)
		local out = {}
		for _, id in ipairs(IslandConfig.RegionOrder) do
			local reg = IslandConfig.Regions[id]
			local aw = if reg.width >= 180 then 1 else math.clamp(1 - (math.abs(angleDiff(deg, reg.bearing)) - reg.width) / 22, 0, 1)
			local rw = math.clamp((t - reg.inner) / 0.08 + 1, 0, 1) * math.clamp((reg.outer - t) / 0.08 + 1, 0, 1)
			if id == "sanctuary" then rw = 1 - smooth((t - reg.outer) / 0.08) end
			out[id] = aw * rw
		end
		return out
	end
	local P = SHAPE.plateau
	local function height(x: number, z: number): number
		local r = math.sqrt(x * x + z * z)
		local theta = math.atan2(z, x)
		local c = coast(theta)
		local t = r / c
		local h: number
		if t >= 1 then
			h = SHAPE.seaFloor * smooth((t - 1) / 0.22) - 1.5 * (1 - smooth((t - 1) / 0.22))
		else
			local tp = P.radius / c
			local u = math.clamp((t - tp) / (1 - tp), 0, 1)
			h = P.height * (1 - u) ^ 1.45 - 1.5 * smooth((u - 0.85) / 0.15)
			-- each region's own bend, faded to nothing at the coast and at the plateau
			local w = weights(x, z)
			local fade = smooth((t - tp) / 0.12) * (1 - smooth((t - 0.86) / 0.14))
			for _, id in ipairs(IslandConfig.RegionOrder) do
				local reg = IslandConfig.Regions[id]
				local wt = w[id]
				if wt > 0 and id ~= "sanctuary" then
					local bell = math.sin(math.pi * math.clamp((t - reg.inner) / math.max(reg.outer - reg.inner, 0.05), 0, 1))
					h += wt * fade * (reg.height * bell + reg.rough * math.noise(x / 55 + s1, z / 55 + s2, id == "highlands" and 0.5 or 0.1))
				end
			end
		end
		-- the plateau: flat round the ritual site, blended into the slope
		local flat = 1 - smooth((r - P.radius) / 26)
		if flat > 0 then h = h + (P.height - h) * flat end
		return h
	end
	return { coast = coast, height = height, weights = weights }
end

local function dominant(w: { [string]: number }): string
	local best, bw = "shore", -1
	for id, v in pairs(w) do
		if v > bw then best, bw = id, v end
	end
	return best
end

-- ── Terrain ─────────────────────────────────────────────────────────────────
local MAT = Enum.Material
local function materialFor(region: string, h: number, slope: number, n: number): Enum.Material
	if h < 0.5 then return if n > 0.1 then MAT.Mud else MAT.Sand end
	if slope > 1.05 then return if region == "highlands" then MAT.Basalt else MAT.Rock end
	if region == "sanctuary" then return if n > 0.25 then MAT.Cobblestone else MAT.Slate end
	if region == "shore" then return if h < 6 then MAT.Sand elseif n > 0.2 then MAT.Ground else MAT.Grass end
	if h < 2.5 then return MAT.Sand end
	if region == "forest" then return if n > 0.28 then MAT.Mud elseif n < -0.25 then MAT.Grass else MAT.LeafyGrass end
	if region == "ruins" then return if n > 0.2 then MAT.Slate elseif h < 5 then MAT.Mud else MAT.Ground end
	if region == "highlands" then return if math.abs(n) < 0.05 then MAT.CrackedLava elseif slope > 0.7 then MAT.Rock else MAT.Basalt end
	if region == "caves" then return if n > 0 then MAT.Rock else MAT.Slate end
	return MAT.Grass
end

local function writeTerrain(origin: Vector3, field: Field, seed: number)
	local V = SHAPE.voxel
	local E = SHAPE.extent
	local Y0, Y1 = SHAPE.seaFloor - 10, 84
	Y0 = math.floor(Y0 / V) * V
	Y1 = math.ceil(Y1 / V) * V
	local ny = (Y1 - Y0) // V
	local CH = 16 -- voxels per chunk side
	local ox = math.floor((origin.X - E) / V) * V
	local oz = math.floor((origin.Z - E) / V) * V
	local nChunks = math.ceil(E * 2 / V / CH)
	local s5 = Random.new(seed + 7):NextNumber(0, 100)
	for cx = 0, nChunks - 1 do
		for cz = 0, nChunks - 1 do
			local x0 = ox + cx * CH * V
			local z0 = oz + cz * CH * V
			-- heights with a one-voxel margin (for the slope)
			local hs = {}
			for i = -1, CH do
				hs[i] = {}
				for k = -1, CH do
					hs[i][k] = field.height(x0 + (i + 0.5) * V - origin.X, z0 + (k + 0.5) * V - origin.Z)
				end
			end
			local mats, occ = {}, {}
			for i = 1, CH do
				mats[i], occ[i] = {}, {}
				for j = 1, ny do mats[i][j], occ[i][j] = {}, {} end
			end
			for i = 0, CH - 1 do
				for k = 0, CH - 1 do
					local h = hs[i][k]
					local lx, lz = x0 + (i + 0.5) * V - origin.X, z0 + (k + 0.5) * V - origin.Z
					local slope = math.max(math.abs(hs[i + 1][k] - hs[i - 1][k]), math.abs(hs[i][k + 1] - hs[i][k - 1])) / (2 * V)
					local region = dominant(field.weights(lx, lz))
					local n = math.noise(lx / 38 + s5, lz / 38, 0.3)
					local mat = materialFor(region, h, slope, n)
					local under = if region == "highlands" then MAT.Basalt elseif region == "sanctuary" then MAT.Slate else MAT.Rock
					for j = 0, ny - 1 do
						local yb = Y0 + j * V -- the voxel's bottom
						local fill = math.clamp((h - yb) / V, 0, 1)
						if fill > 0 then
							mats[i + 1][j + 1][k + 1] = if h - yb > V * 2 then under else mat
							occ[i + 1][j + 1][k + 1] = fill
						elseif yb < 0 then
							mats[i + 1][j + 1][k + 1] = MAT.Water
							occ[i + 1][j + 1][k + 1] = 1
						else
							mats[i + 1][j + 1][k + 1] = MAT.Air
							occ[i + 1][j + 1][k + 1] = 0
						end
					end
				end
			end
			local region = Region3.new(Vector3.new(x0, Y0, z0), Vector3.new(x0 + CH * V, Y1, z0 + CH * V)):ExpandToGrid(V)
			terrain:WriteVoxels(region, V, mats, occ)
			task.wait()
		end
	end
end

-- ── Placement ───────────────────────────────────────────────────────────────
local terrainOnly = RaycastParams.new()
terrainOnly.FilterType = Enum.RaycastFilterType.Include
terrainOnly.FilterDescendantsInstances = { terrain }
terrainOnly.IgnoreWater = true

local function groundAt(pos: Vector3, from: number?): number?
	local hit = Workspace:Raycast(Vector3.new(pos.X, from or 140, pos.Z), Vector3.new(0, -260, 0), terrainOnly)
	return hit and hit.Position.Y or nil
end

-- A spot in a region (island space → world), dry, not too steep, clear of
-- the spots already taken (`taken`, each with its own clearance).
type Taken = { { pos: Vector3, r: number } }
local function findSpot(rng: Random, origin: Vector3, field: Field, regionId: string, taken: Taken, clear: number, opts: { minH: number?, maxSlope: number? }?): Vector3?
	local reg = IslandConfig.Regions[regionId]
	local o = opts or {}
	for _ = 1, 40 do
		local theta = math.rad(reg.bearing + rng:NextNumber(-reg.width, reg.width) * 0.9)
		local tt = rng:NextNumber(reg.inner + 0.04, reg.outer - 0.06)
		local c = field.coast(theta)
		local x, z = math.cos(theta) * c * tt, math.sin(theta) * c * tt
		if regionId == "sanctuary" then
			local a = rng:NextNumber(0, math.pi * 2)
			local rr = rng:NextNumber(70, 95)
			x, z = math.cos(a) * rr, math.sin(a) * rr
		end
		if dominant(field.weights(x, z)) ~= regionId then continue end
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

-- Level the ground round a landmark: clear above `y`, fill below it.
local function level(pos: Vector3, radius: number, y: number, mat: Enum.Material)
	terrain:FillCylinder(CFrame.new(pos.X, y + 20, pos.Z), 40, radius, MAT.Air)
	terrain:FillCylinder(CFrame.new(pos.X, y - 6, pos.Z), 12, radius + 2, mat)
end

-- ── The caves ───────────────────────────────────────────────────────────────
local function carveCaves(origin: Vector3, field: Field, rng: Random, parent: Instance, taken: Taken): ({ CFrame }, { Vector3 })
	local C = IslandConfig.Caves
	local hallSpots: { CFrame } = {}
	local mouths: { Vector3 } = {}
	local function at(spec: { number }): Vector3
		local theta = math.rad(spec[1])
		local c = field.coast(theta)
		return Vector3.new(math.cos(theta) * c * spec[2], 0, math.sin(theta) * c * spec[2])
	end
	for _, tun in ipairs(C.tunnels) do
		local a, b = at(tun.from), at(tun.to)
		local len = (b - a).Magnitude
		local steps = math.ceil(len / 4)
		for s = 0, steps do
			local f = s / steps
			local p = a:Lerp(b, f)
			-- (a little wander)
			local side = Vector3.new(-(b - a).Z, 0, (b - a).X).Unit
			p += side * math.sin(f * math.pi * 2.2) * 8
			local h = field.height(p.X, p.Z)
			local floor = math.min(h - 1.5, C.floor)
			terrain:FillBall(origin + Vector3.new(p.X, floor + C.radius * 0.8, p.Z), C.radius, MAT.Air)
			table.insert(taken, { pos = origin + p, r = C.radius + 2 })
			if s == 0 or s == steps then table.insert(mouths, origin + Vector3.new(p.X, floor, p.Z)) end
		end
		for _, hf in ipairs(tun.halls) do
			local p = a:Lerp(b, hf)
			local center = origin + Vector3.new(p.X, C.floor + C.hallRadius * 0.6, p.Z)
			terrain:FillBall(center, C.hallRadius, MAT.Air)
			local floorY = groundAt(center, center.Y) or (C.floor)
			local floorPos = Vector3.new(center.X, floorY, center.Z)
			table.insert(hallSpots, CFrame.new(floorPos))
			table.insert(taken, { pos = floorPos, r = C.hallRadius })
			-- crystals round the hall's walls
			for k = 0, 6 do
				local ang = k / 7 * math.pi * 2 + rng:NextNumber(0, 0.4)
				local wallAt = floorPos + Vector3.new(math.cos(ang), 0, math.sin(ang)) * (C.hallRadius * 0.7)
				local y = groundAt(wallAt, center.Y) or floorY
				IslandKit.Build("crystal", CFrame.new(wallAt.X, y, wallAt.Z), rng, parent)
			end
		end
		task.wait()
	end
	return hallSpots, mouths
end

-- ── The Ancient Sanctuary ───────────────────────────────────────────────────
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

local function buildSanctuary(origin: Vector3, field: Field, rng: Random, parent: Instance): (CFrame, Model, { Model }, { BasePart }, { BasePart })
	local R = IslandConfig.Ritual
	local m = Instance.new("Model")
	m.Name = "AncientSanctuary"
	-- (always on every client: the island's landmark, seen from anywhere)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	m.Parent = parent
	local center = origin + Vector3.new(0, PLATFORM_TOP, 0)
	local DARK, DARK2, TRIM = rgb(36, 32, 42), rgb(48, 43, 56), rgb(80, 70, 96)
	local VIOLET = rgb(180, 90, 255)
	-- the platform: a great disc of dark stone, a raised rim, its trim
	local disc = sp(m, Vector3.new(4, R.platformRadius * 2, R.platformRadius * 2), CFrame.new(center - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), DARK, MAT.Slate)
	disc.Shape = Enum.PartType.Cylinder
	disc.Name = "Platform"
	local rimN = 36
	for k = 0, rimN - 1 do
		local a = k / rimN * math.pi * 2
		local seg = 2 * math.pi * R.platformRadius / rimN
		if k % 9 == 4 then continue end -- (four gaps: the ways up)
		sp(m, Vector3.new(seg + 0.4, 1.2, 2.4), CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0.6, -R.platformRadius + 1), DARK2, MAT.Slate)
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
			VIOLET, MAT.Neon, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.82 })
		r.Name = "Rune"
		table.insert(runes, r)
	end
	-- cracks in the stone, energy glowing beneath them
	local cracks: { BasePart } = {}
	for k = 0, 13 do
		local a = rng:NextNumber(0, math.pi * 2)
		local r0 = rng:NextNumber(8, 52)
		for s = 0, 2 do
			local c = sp(m, Vector3.new(rng:NextNumber(0.4, 0.9), 0.12, 4), CFrame.new(center) * CFrame.Angles(0, -a, 0) * CFrame.new(0, 0.1, -r0 - s * 3.6) * CFrame.Angles(0, rng:NextNumber(-0.5, 0.5), 0),
				VIOLET, MAT.Neon, { CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.55 })
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
	for k = 0, 11 do
		local a = rng:NextNumber(0, math.pi * 2)
		local pos = center + Vector3.new(math.sin(a), 0, -math.cos(a)) * rng:NextNumber(12, 55)
		if rng:NextNumber() < 0.5 then
			local skull = sp(m, Vector3.one * 1.1, CFrame.new(pos + Vector3.new(0, 0.5, 0)), rgb(214, 204, 184), MAT.SmoothPlastic, { CanCollide = false, Shape = Enum.PartType.Ball })
			skull.CastShadow = false
		else
			for c = 0, 2 do
				local off = Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
				local h = rng:NextNumber(0.6, 1.4)
				sp(m, Vector3.new(0.4, h, 0.4), CFrame.new(pos + off + Vector3.new(0, h / 2, 0)), rgb(220, 210, 180), MAT.SmoothPlastic, { CanCollide = false })
				local fl = sp(m, Vector3.new(0.2, 0.35, 0.2), CFrame.new(pos + off + Vector3.new(0, h + 0.2, 0)), rgb(255, 190, 90), MAT.Neon, { CanCollide = false, CanQuery = false, CastShadow = false })
				fl.Name = "Candle"
			end
		end
	end
	-- the ways up: broken stone stairs down the plateau toward the shore and the ruins
	for _, bearing in ipairs({ -90, 0, 180, 70 }) do
		local dir = Vector3.new(math.cos(math.rad(bearing)), 0, math.sin(math.rad(bearing)))
		for s = 0, 13 do
			local d = R.platformRadius + 2 + s * 4
			if s > 4 and rng:NextNumber() < 0.18 then continue end -- (worn away)
			local lp = dir * d
			local y = field.height(lp.X, lp.Z)
			local pos = origin + Vector3.new(lp.X, y, lp.Z)
			sp(m, Vector3.new(10, 1.4, 4.2), CFrame.lookAt(pos, pos + dir) * CFrame.Angles(math.rad(rng:NextNumber(-2, 2)), 0, math.rad(rng:NextNumber(-3, 3))), if s % 2 == 0 then DARK2 else DARK, MAT.Slate)
		end
	end
	-- floating motes over it all, and a pale shaft of light up from the altar:
	-- the island's landmark, seen from the shore
	local motes = sp(m, Vector3.new(R.platformRadius * 1.6, 12, R.platformRadius * 1.6), CFrame.new(center + Vector3.new(0, 14, 0)), VIOLET, MAT.SmoothPlastic,
		{ Transparency = 1, CanCollide = false, CanQuery = false, CastShadow = false })
	motes.Name = "Motes"
	local e = Instance.new("ParticleEmitter")
	e.Texture = IslandKit.SPARK
	e.Color = ColorSequence.new(rgb(200, 140, 255), rgb(120, 220, 255))
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
	local beam = sp(m, Vector3.new(3, 260, 3), CFrame.new(center + Vector3.new(0, 140, 0)), rgb(170, 110, 255), MAT.Neon,
		{ CanCollide = false, CanQuery = false, CastShadow = false, Transparency = 0.7 })
	beam.Name = "Beacon"
	return altarCF, altar, statues, runes, cracks
end

-- ── Build ───────────────────────────────────────────────────────────────────
function IslandGenerator.Build(runId: string, slot: number, seed: number): Island
	local t0 = os.clock()
	IslandGenerator.Forget(runId)
	local origin = IslandConfig.Origin(slot)
	local field = makeField(seed)
	local rng = Random.new(seed)
	local folder = Instance.new("Folder")
	folder.Name = "Island_" .. runId
	folder.Parent = Workspace

	writeTerrain(origin, field, seed)
	-- the open sea beyond what was written, out to the edge of the slot (so
	-- no edge of the world shows from the island)
	local SEA = IslandConfig.SEA
	for x = -SEA.halfX, SEA.halfX - 1, SEA.step do
		for z = -SEA.halfZ, SEA.halfZ - 1, SEA.step do
			if math.abs(x + SEA.step / 2) < SHAPE.extent and math.abs(z + SEA.step / 2) < SHAPE.extent then continue end
			terrain:FillBlock(CFrame.new(origin.X + x + SEA.step / 2, -6, origin.Z + z + SEA.step / 2), Vector3.new(SEA.step, 12, SEA.step), MAT.Water)
		end
		task.wait()
	end
	-- a dark, cold sea (terrain's water is one look for the whole world:
	-- only the island has any)
	terrain.WaterColor = Color3.fromRGB(26, 52, 66)
	terrain.WaterTransparency = 0.55
	terrain.WaterReflectance = 0.25
	terrain.WaterWaveSize = 0.18
	terrain.WaterWaveSpeed = 8

	local props = Instance.new("Folder")
	props.Name = "Props"
	props.Parent = folder
	local taken: Taken = { { pos = origin, r = SHAPE.plateau.radius + 22 } } -- (the plateau and its stairs)

	-- the caves first (props and landmarks keep off their tunnels)
	local hallSpots, caveMouths = carveCaves(origin, field, rng, props, taken)

	-- the landmarks
	local pois = {}
	local spawn: CFrame? = nil
	for _, poi in ipairs(IslandConfig.Pois) do
		local theta = math.rad(poi.bearing)
		local c = field.coast(theta)
		local lp = Vector3.new(math.cos(theta) * c * poi.dist, 0, math.sin(theta) * c * poi.dist)
		local pos = origin + lp
		if poi.id == "hollow" and hallSpots[1] then
			pos = hallSpots[1].Position
		elseif poi.id == "sanctuary" then
			pos = origin + Vector3.new(0, PLATFORM_TOP, 0)
		else
			local y = groundAt(pos) or field.height(lp.X, lp.Z)
			-- (the docks and the wreck stand at the water's edge; the temple half in it)
			if poi.build == "docks" or poi.build == "shipwreck" then y = math.max(y, 0.2)
			elseif poi.build == "temple" then y = math.max(y, -1.5)
			elseif poi.build ~= "none" then
				y = math.max(y, 1)
				level(Vector3.new(pos.X, y, pos.Z), poi.radius * 0.55, y, if poi.region == "highlands" then MAT.Basalt else MAT.Ground)
			end
			pos = Vector3.new(pos.X, y, pos.Z)
			if poi.build ~= "none" then
				local face = CFrame.lookAt(pos, Vector3.new(origin.X, pos.Y, origin.Z))
				IslandKit.Build(poi.build, face, rng, props)
			end
		end
		table.insert(pois, { id = poi.id, name = poi.name, region = poi.region, pos = pos, radius = poi.radius, xp = poi.xp })
		table.insert(taken, { pos = pos, r = poi.radius * 0.7 })
		if poi.id == "docks" then
			-- arriving at the land end of the docks, facing the island
			local inland = (Vector3.new(origin.X, 0, origin.Z) - Vector3.new(pos.X, 0, pos.Z)).Unit
			local at = pos + inland * 22
			local y = groundAt(at) or 4
			spawn = CFrame.lookAt(Vector3.new(at.X, y + 3, at.Z), Vector3.new(origin.X, y + 3, origin.Z))
		end
	end
	task.wait()

	-- the ritual site
	local altarCF, altarModel, statues, runes, cracks = buildSanctuary(origin, field, rng, folder)
	task.wait()

	-- props
	for regionId, counts in pairs(IslandConfig.Props) do
		for name, n in pairs(counts) do
			local clear = if name == "tree" or name == "palm" then 7 elseif name == "wall" or name == "log" then 9 elseif name == "crack" or name == "mushroom" then 3 else 5
			for _ = 1, n do
				local pos = findSpot(rng, origin, field, regionId, taken, clear, { maxSlope = if name == "spire" or name == "rock" then 0.9 else 0.55 })
				if pos then
					IslandKit.Build(name, CFrame.new(pos - Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng, props)
					table.insert(taken, { pos = pos, r = clear * 0.5 })
				end
			end
		end
		task.wait()
	end

	-- spawn sources
	local sources: { Source } = {}
	local srcFolder = Instance.new("Folder")
	srcFolder.Name = "SpawnSources"
	srcFolder.Parent = folder
	for regionId, counts in pairs(IslandConfig.SpawnSources) do
		for kind, n in pairs(counts) do
			for _ = 1, n do
				local pos: Vector3? = nil
				if kind == "cave" then
					local mouth = caveMouths[rng:NextInteger(1, math.max(#caveMouths, 1))]
					if mouth then
						local y = groundAt(mouth, mouth.Y + 10)
						pos = Vector3.new(mouth.X + rng:NextNumber(-6, 6), (y or mouth.Y), mouth.Z + rng:NextNumber(-6, 6))
					end
				else
					pos = findSpot(rng, origin, field, regionId, taken, 14)
				end
				if pos then
					IslandKit.Build("src_" .. kind, CFrame.new(pos), rng, srcFolder)
					table.insert(sources, { pos = pos, region = regionId, kind = kind })
					table.insert(taken, { pos = pos, r = 6 })
				end
			end
		end
	end
	-- (the cave halls raise their own)
	for _, h in ipairs(hallSpots) do table.insert(sources, { pos = h.Position, region = "caves", kind = "cave" }) end

	-- chest spots (IslandChests fills them)
	local chestSpots: { ChestSpot } = {}
	for kind, spec in pairs(IslandConfig.Chests) do
		if typeof(spec) ~= "table" then continue end
		for i = 1, spec.count do
			local regionId = spec.regions[(i - 1) % #spec.regions + 1]
			local pos: Vector3? = nil
			if regionId == "caves" and kind == "rare" and hallSpots[(i % #hallSpots) + 1] then
				local h = hallSpots[(i % #hallSpots) + 1].Position
				pos = h + Vector3.new(rng:NextNumber(-5, 5), 0, rng:NextNumber(-5, 5))
				pos = Vector3.new(pos.X, groundAt(pos, h.Y + 8) or h.Y, pos.Z)
			else
				pos = findSpot(rng, origin, field, regionId, taken, 8)
			end
			if pos then
				table.insert(chestSpots, { cf = CFrame.new(pos) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), kind = kind, region = regionId })
				table.insert(taken, { pos = pos, r = 4 })
			end
		end
	end

	-- where an Ancient Echo's shrine may rise
	local shrineSpots: { CFrame } = {}
	for _, regionId in ipairs({ "forest", "ruins", "highlands", "shore" }) do
		local pos = findSpot(rng, origin, field, regionId, taken, 12)
		if pos then
			table.insert(shrineSpots, CFrame.new(pos))
			table.insert(taken, { pos = pos, r = 8 })
		end
	end

	local island: Island = {
		runId = runId,
		origin = origin,
		folder = folder,
		spawn = spawn or CFrame.new(origin + Vector3.new(0, 30, -300)),
		sources = sources,
		chestSpots = chestSpots,
		pois = pois,
		altar = altarCF,
		altarModel = altarModel,
		statues = statues,
		runes = runes,
		cracks = cracks,
		shrineSpots = shrineSpots,
		RegionAt = function(pos: Vector3): string
			local lp = pos - origin
			return dominant(field.weights(lp.X, lp.Z))
		end,
		GroundAt = function(pos: Vector3): number?
			return groundAt(pos, pos.Y + 6)
		end,
	}
	islands[runId] = island
	print(string.format("[IslandGenerator] %s: the Forgotten Isle built in %.1fs: %d props, %d spawn sources, %d chest spots, %d landmarks",
		runId, os.clock() - t0, #props:GetChildren(), #sources, #chestSpots, #pois))
	return island
end

function IslandGenerator.Get(runId: string?): Island?
	return if runId then islands[runId] else nil
end

-- Take a run's island down: its parts, and its terrain back to empty air.
function IslandGenerator.Forget(runId: string)
	local island = islands[runId]
	if not island then return end
	islands[runId] = nil
	island.folder:Destroy()
	local E = SHAPE.extent
	local SEA = IslandConfig.SEA
	local o = island.origin
	task.spawn(function()
		local step = 200
		for x = -E, E - 1, step do
			for z = -E, E - 1, step do
				terrain:FillBlock(CFrame.new(o.X + x + step / 2, 20, o.Z + z + step / 2), Vector3.new(step, 132, step), MAT.Air)
				task.wait()
			end
		end
		for x = -SEA.halfX, SEA.halfX - 1, SEA.step do
			for z = -SEA.halfZ, SEA.halfZ - 1, SEA.step do
				terrain:FillBlock(CFrame.new(o.X + x + SEA.step / 2, -6, o.Z + z + SEA.step / 2), Vector3.new(SEA.step, 12, SEA.step), MAT.Air)
			end
			task.wait()
		end
	end)
end

return IslandGenerator
