--!strict
--[[
	IslandVoxel.luau
	The Forgotten Isle's ground, built from blocks like the concept art (not
	terrain, which Roblox smooths at a distance): IslandGenerator's height
	field sampled on a CELL-stud grid, each cell a column of stone with its
	region's top (grass, sand, basalt...) as a cap. Heights are whole studs
	where the island is walked (beaches, lowlands, the mountain's paths: steps
	a character climbs) and the field's own terraces on the mountain (cliffs).
	Neighbouring cells of the same height and top are merged into one
	rectangle (greedy meshing) to keep the part count down. Below the sea's
	surface the columns run on down, so the shallows show sand under water.

	IslandVoxel.Build(origin, field, parent) → Folder (the ground: every
	ground check on the island raycasts against it)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local IslandConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IslandConfig"))

local IslandVoxel = {}

local CELL = 6
local BOTTOM = -14       -- the columns' feet (under the shallows)
local CAP = 1.4          -- the top layer's thickness

type Top = { id: string, top: Color3, body: Color3, mat: Enum.Material, cap: boolean, faces: { Color3 }? }
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end

-- The cliffs' faces, each biome's own patchwork (block by block)
local GREY = { rgb(92, 94, 112), rgb(80, 82, 100), rgb(102, 104, 118), rgb(78, 96, 72), rgb(88, 104, 80) }
local SANDSTONE = { rgb(186, 160, 118), rgb(168, 142, 104), rgb(196, 172, 128), rgb(176, 150, 112) }
local VIOLET = { rgb(56, 48, 66), rgb(44, 38, 54), rgb(66, 52, 80), rgb(50, 40, 62) }
local TEAL = { rgb(70, 118, 124), rgb(58, 100, 110), rgb(84, 132, 136), rgb(64, 110, 104) }
local OBSIDIAN = { rgb(34, 30, 40), rgb(26, 24, 32), rgb(44, 38, 50), rgb(38, 30, 36) }
local ICE = { rgb(170, 204, 230), rgb(150, 188, 220), rgb(190, 218, 238), rgb(140, 176, 206) }

local TOPS: { [string]: Top } = {
	sand = { id = "sand", top = rgb(236, 222, 176), body = rgb(214, 196, 150), mat = Enum.Material.Sand, cap = false },
	-- the Shipwreck Coast: dune grass on sandstone
	dune = { id = "dune", top = rgb(150, 178, 82), body = rgb(186, 160, 118), mat = Enum.Material.Grass, cap = true, faces = SANDSTONE },
	-- the Verdant Ruins: jungle green, moss, old paving, on grey stone
	grass = { id = "grass", top = rgb(80, 164, 52), body = rgb(96, 98, 114), mat = Enum.Material.Grass, cap = true, faces = GREY },
	moss = { id = "moss", top = rgb(98, 146, 64), body = rgb(110, 112, 124), mat = Enum.Material.Grass, cap = true, faces = GREY },
	stone = { id = "stone", top = rgb(120, 122, 132), body = rgb(92, 94, 110), mat = Enum.Material.Slate, cap = false },
	dirt = { id = "dirt", top = rgb(150, 116, 76), body = rgb(96, 98, 114), mat = Enum.Material.Ground, cap = true, faces = GREY },
	-- the Corrupted Forest: violet turf, black earth
	corrupt = { id = "corrupt", top = rgb(82, 54, 102), body = rgb(52, 44, 62), mat = Enum.Material.Grass, cap = true, faces = VIOLET },
	blight = { id = "blight", top = rgb(46, 36, 56), body = rgb(52, 44, 62), mat = Enum.Material.Ground, cap = true, faces = VIOLET },
	-- the Sunken Sanctuary: teal temple stone
	teal = { id = "teal", top = rgb(104, 158, 156), body = rgb(70, 118, 124), mat = Enum.Material.Slate, cap = true, faces = TEAL },
	tealmoss = { id = "tealmoss", top = rgb(80, 150, 120), body = rgb(70, 118, 124), mat = Enum.Material.Grass, cap = true, faces = TEAL },
	-- the Infernal Citadel
	basalt = { id = "basalt", top = rgb(46, 40, 44), body = rgb(34, 30, 34), mat = Enum.Material.Basalt, cap = false },
	ember = { id = "ember", top = rgb(70, 34, 28), body = rgb(34, 30, 34), mat = Enum.Material.CrackedLava, cap = true },
	-- the Ancient Spire: obsidian, veined red here and there
	obsidian = { id = "obsidian", top = rgb(40, 36, 46), body = rgb(30, 28, 36), mat = Enum.Material.Slate, cap = true, faces = OBSIDIAN },
	bloodstone = { id = "bloodstone", top = rgb(70, 26, 34), body = rgb(30, 28, 36), mat = Enum.Material.CrackedLava, cap = true, faces = OBSIDIAN },
	-- the Frozen Isle: snow over ice cliffs, bare blue ice here and there
	snow = { id = "snow", top = rgb(240, 246, 252), body = rgb(170, 204, 230), mat = Enum.Material.Snow, cap = true, faces = ICE },
	ice = { id = "ice", top = rgb(186, 220, 244), body = rgb(170, 204, 230), mat = Enum.Material.Ice, cap = true, faces = ICE },
	packed = { id = "packed", top = rgb(206, 214, 224), body = rgb(170, 204, 230), mat = Enum.Material.Snow, cap = true, faces = ICE },
	ash = { id = "ash", top = rgb(62, 56, 56), body = rgb(34, 30, 34), mat = Enum.Material.Ground, cap = false },
	-- (the river's bed: blue, the shallow water over it reads as river, not sand)
	bed = { id = "bed", top = rgb(40, 132, 196), body = rgb(92, 94, 110), mat = Enum.Material.Slate, cap = true, faces = GREY },
}
local CORNERS = { { -3, -3 }, { 3, -3 }, { -3, 3 }, { 3, 3 } }
local STEP = rgb(128, 126, 132)
local STEP2 = rgb(112, 110, 118)

-- The top of a cell from its biome, height and a little noise.
local function topFor(region: string, h: number, n: number, river: boolean, path: boolean, r: number, P: any): Top
	if river then return if region == "frozen" then TOPS.ice else TOPS.bed end
	if path then
		return if region == "sanctuary" then TOPS.obsidian elseif region == "forest" then TOPS.blight
			elseif region == "frozen" then TOPS.packed elseif region == "highlands" then TOPS.ash else TOPS.dirt
	end
	if h < 4.5 then
		return if region == "forest" then TOPS.blight elseif region == "frozen" then TOPS.snow elseif region == "highlands" then TOPS.ash
			elseif region == "sanctuary" then TOPS.obsidian else TOPS.sand
	end
	if r < P.radius + 2 then
		return if region == "frozen" then TOPS.ice elseif region == "ruins" or region == "shore" then TOPS.stone
			elseif region == "sunken" then TOPS.teal elseif region == "highlands" then TOPS.basalt elseif region == "forest" then TOPS.blight else TOPS.obsidian
	end
	if region == "frozen" then return if n > 0.38 then TOPS.ice else TOPS.snow end
	if region == "sanctuary" then return if n > 0.38 then TOPS.bloodstone else TOPS.obsidian end
	if region == "highlands" then return if n > 0.3 then TOPS.ember else TOPS.basalt end
	if region == "forest" then return if n > 0.25 then TOPS.blight else TOPS.corrupt end
	if region == "sunken" then return if n > 0.1 then TOPS.teal else TOPS.tealmoss end
	if region == "shore" then return TOPS.dune end
	return if n > 0.5 then TOPS.stone elseif n > 0.2 then TOPS.moss else TOPS.grass
end

function IslandVoxel.Build(origin: Vector3, field: any, parent: Instance): Folder
	local folder = Instance.new("Folder")
	folder.Name = "Ground"
	folder.Parent = parent
	local SHAPE = field.shape
	local E = SHAPE.extent
	local n = math.floor(E * 2 / CELL)
	local seed = (origin.X * 0.013) % 97
	-- sample every cell: its height (whole studs, or the terrace's) and top
	local hs: { { number } } = {}
	local keys: { { string } } = {}
	local tops: { { Top } } = {}
	for i = 1, n do
		hs[i], keys[i], tops[i] = {}, {}, {}
		for k = 1, n do
			local x = -E + (i - 0.5) * CELL
			local z = -E + (k - 0.5) * CELL
			local h = field.height(x, z)
			if h < -0.6 then
				keys[i][k] = ""
			else
				local rw = field.river(x, z)
				local path = field.onPath(x, z)
				-- (a path's cells sit under its stairs)
				if path then
					-- (just under the lowest stair crossing the cell, so no
					-- block shows through a step)
					local lo = h
					for _, o in ipairs(CORNERS) do lo = math.min(lo, field.height(x + o[1], z + o[2])) end
					h = math.floor(lo - 0.6)
				else
					h = math.floor(h + 0.5)
				end
				h = math.max(h, 0)
				local nz = math.noise(x / 30 + seed, z / 30, 0.7)
				local top = topFor(field.region(x, z), h, nz, rw > 0.5, path, math.sqrt(x * x + z * z), SHAPE.plateau)
				hs[i][k], tops[i][k] = h, top
				keys[i][k] = top.id .. "|" .. h
			end
		end
		if i % 20 == 0 then task.wait() end
	end
	-- greedy rectangles of equal key
	local done: { { boolean } } = {}
	for i = 1, n do done[i] = {} end
	local made = 0
	for k = 1, n do
		for i = 1, n do
			local key = keys[i][k]
			if key == "" or done[i][k] then continue end
			-- widen along i
			local w = 1
			while i + w <= n and not done[i + w][k] and keys[i + w][k] == key do w += 1 end
			-- then deepen along k while the whole span matches
			local d = 1
			while k + d <= n do
				local ok = true
				for ii = i, i + w - 1 do
					if done[ii][k + d] or keys[ii][k + d] ~= key then
						ok = false
						break
					end
				end
				if not ok then break end
				d += 1
			end
			for ii = i, i + w - 1 do
				for kk = k, k + d - 1 do done[ii][kk] = true end
			end
			local h, top = hs[i][k], tops[i][k]
			local cx = origin.X - E + (i - 1 + w / 2) * CELL
			local cz = origin.Z - E + (k - 1 + d / 2) * CELL
			local sx, sz = w * CELL, d * CELL
			-- (a slight shade per block, the concept's patchwork)
			local shade = 0.93 + ((i * 7 + k * 13) % 9) / 60
			local faces = top.faces
			local face = if faces then faces[(i * 5 + k * 11) % #faces + 1] else top.body
			local function tint(c: Color3): Color3
				return Color3.new(math.min(c.R * shade, 1), math.min(c.G * shade, 1), math.min(c.B * shade, 1))
			end
			local bodyTop = if top.cap then h - CAP else h
			local bh = bodyTop - BOTTOM
			if bh > 0.05 then
				local body = Instance.new("Part")
				body.Anchored, body.CanTouch = true, false
				body.TopSurface, body.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				body.Size = Vector3.new(sx, bh, sz)
				body.CFrame = CFrame.new(cx, BOTTOM + bh / 2, cz)
				body.Color = tint(if top.cap then face else top.top)
				body.Material = if top.cap then Enum.Material.Slate else top.mat
				body.CastShadow = sx * sz > 400
				body.Name = "Block"
				body.Parent = folder
				made += 1
			end
			if top.cap then
				local cap = Instance.new("Part")
				cap.Anchored, cap.CanTouch = true, false
				cap.TopSurface, cap.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				cap.Size = Vector3.new(sx, CAP, sz)
				cap.CFrame = CFrame.new(cx, h - CAP / 2, cz)
				cap.Color = tint(top.top)
				cap.Material = top.mat
				cap.CastShadow = false
				cap.Name = "Top"
				cap.Parent = folder
				made += 1
			end
			if made % 300 == 0 then task.wait() end
		end
	end
	-- the stairs up each path: a step every 2 studs, never more than a stud up
	for _, pts in ipairs(field.paths) do
		local W = SHAPE.pathWidth
		for i = 2, #pts - 1 do
			local a, b = pts[i - 1], pts[i + 1]
			-- (a step every 2 studs where it climbs, a flagstone every 4 where it's flat)
			local flatHere = math.abs(b.Y - a.Y) < 0.15
			if flatHere and i % 2 == 1 then continue end
			local p = pts[i]
			local world = origin + Vector3.new(p.X, p.Y - 2, p.Z)
			local step = Instance.new("Part")
			step.Anchored, step.CanTouch = true, false
			step.TopSurface, step.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
			step.Size = Vector3.new(W, 4, if flatHere then 4.15 else 2.15)
			step.CFrame = CFrame.lookAt(world, world + Vector3.new(b.X - a.X, 0, b.Z - a.Z))
			step.Color = if i % 2 == 0 then STEP else STEP2
			step.Material = Enum.Material.Slate
			step.CastShadow = false
			step.Name = "Step"
			step.Parent = folder
			made += 1
			if made % 300 == 0 then task.wait() end
		end
	end
	folder:SetAttribute("Parts", made)
	return folder
end

return IslandVoxel
