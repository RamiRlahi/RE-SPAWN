--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- DungeonGenerator.luau
-- Procedural Medieval Roguelite Dungeon Generator for Roblox
-- 
-- System Architecture:
-- 1. Graph & Floorplan Phase: Generates a deterministic layout (Start → Combat →
--    Branches/Shop/Treasure/Elite → Boss) with guaranteed reachability.
-- 2. Floor Construction: Exact 12x12 stud snapped floor tile placement (Floor Y = 4).
-- 3. Seamless 17-Stud Wall Construction: Continuous wall runs placed edge-to-edge
--    so walls are stuck together with no gaps (Wall/Pillar Y = 11).
-- 4. Pure Gate Corridor Entrances: Uses ONLY Gate models from walls/gates at
--    corridor entrances with zero pillars in gates. Corner Pillars for room corners.
-- 5. Rich Decor & Rubble: Abundant rubble along perimeters and corners; cosmetics
--    (chests, sconces, pillars, barrels) across all rooms; barriers as cover.
-- 6. Pitch-Black Abyss Exit at the final Boss room staircase.
-- ─────────────────────────────────────────────────────────────────────────────

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace         = game:GetService("Workspace")

local DungeonGenerator = {}

-- ── Constants ────────────────────────────────────────────────────────────────

local FLOOR_SIZE        = 12    -- Floor tile grid unit (12x12 studs)
local WALL_PIECE_LEN    = 17    -- Wall piece standard dimension (17x17 studs)
local CORRIDOR_WIDTH    = 2     -- 2 tiles wide = 24 studs for great action combat
local FLOOR_Y_OFFSET    = 4     -- Floor tile vertical elevation (lowered by 4 studs)
local WALL_Y_OFFSET     = 11    -- Wall & Pillar vertical elevation (lowered by 1 stud)

-- ── Types ────────────────────────────────────────────────────────────────────

export type RoomType = "Start" | "Combat" | "Treasure" | "Shop" | "Elite" | "Event" | "Boss"

export type DungeonConfig = {
	seed: number?,
	totalRooms: number?,
	minRoomTiles: number?,    -- in 12-stud floor tiles (e.g. 5 = 60 studs)
	maxRoomTiles: number?,    -- in 12-stud floor tiles (e.g. 8 = 96 studs)
	branchProbability: number?,
}

type DoorwayData = {
	position: Vector3,
	rotY: number,
}

type RoomData = {
	id: number,
	roomType: RoomType,
	gx: number,
	gz: number,
	w: number,
	d: number,
	centerWorld: Vector3,
	connections: { number },
}

-- ── Module State ─────────────────────────────────────────────────────────────

local currentDungeonFolder: Folder? = nil
local cachedSpawnCFrame: CFrame = CFrame.identity
local cachedBossCFrame: CFrame = CFrame.identity
local cachedExitCFrame: CFrame = CFrame.identity
local cachedMapPayload: any = nil
local activeSeed: number = 0

-- Asset Cache
local assets = {
	floors    = {} :: { Instance },
	walls     = {} :: { Instance },
	pillars   = {} :: { Instance },
	gates     = {} :: { Instance },
	barriers  = {} :: { Instance },
	rubble    = {} :: { Instance },
	stairs    = {} :: { Instance },
	cosmetics = {} :: { Instance },
}

-- ── Asset Discovery & Category Separation ────────────────────────────────────

local function loadAssets()
	table.clear(assets.floors)
	table.clear(assets.walls)
	table.clear(assets.pillars)
	table.clear(assets.gates)
	table.clear(assets.barriers)
	table.clear(assets.rubble)
	table.clear(assets.stairs)
	table.clear(assets.cosmetics)

	local root = ReplicatedStorage:WaitForChild("dungeon assets", 5)
	if not root then
		warn("[DungeonGenerator] 'dungeon assets' folder not found in ReplicatedStorage!")
		return
	end

	local function scanFolder(folderName: string, targetList: { Instance })
		for _, child in ipairs(root:GetChildren()) do
			if string.lower(child.Name) == string.lower(folderName) then
				for _, item in ipairs(child:GetChildren()) do
					if item:IsA("Model") or item:IsA("BasePart") then
						table.insert(targetList, item)
					end
				end
			end
		end
	end

	scanFolder("Floor", assets.floors)
	scanFolder("barriers (low level)", assets.barriers)
	scanFolder("rubble", assets.rubble)
	scanFolder("stairs", assets.stairs)
	scanFolder("cosmetics", assets.cosmetics)

	-- Discover Walls, Pillars, and Gates
	local wallsFolder = root:FindFirstChild("walls") or root:FindFirstChild("Walls")
	if wallsFolder then
		local function scanWallsFolder(parent: Instance)
			for _, item in ipairs(parent:GetChildren()) do
				if item:IsA("Folder") then
					scanWallsFolder(item)
				elseif item:IsA("Model") or item:IsA("BasePart") then
					local lowerName = string.lower(item.Name)
					local fullHierarchyName = string.lower(item:GetFullName())
					if lowerName:find("pillar") or fullHierarchyName:find("pillar") then
						table.insert(assets.pillars, item)
					elseif lowerName:find("gate") or lowerName:find("arch") or fullHierarchyName:find("gate") or fullHierarchyName:find("arch") then
						table.insert(assets.gates, item)
					else
						table.insert(assets.walls, item)
					end
				end
			end
		end
		scanWallsFolder(wallsFolder)
	end

	print(`[DungeonGenerator] Assets Cataloged:`)
	print(`  • Floors: { #assets.floors } (12x12, Y={FLOOR_Y_OFFSET})`)
	print(`  • Walls: { #assets.walls } (17x17, Y={WALL_Y_OFFSET})`)
	print(`  • Pillars: { #assets.pillars } (Corner columns)`)
	print(`  • Gates: { #assets.gates } (Pure corridor archways, no pillars)`)
	print(`  • Stairs: { #assets.stairs }`)
	print(`  • Barriers: { #assets.barriers }`)
	print(`  • Rubble: { #assets.rubble }`)
	print(`  • Cosmetics: { #assets.cosmetics }`)
end

-- ── Geometry & Cloner Helpers ────────────────────────────────────────────────

local function spawnInstance(template: Instance, cf: CFrame, parent: Instance): Instance
	local clone = template:Clone()
	if clone:IsA("Model") then
		clone:PivotTo(cf)
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then
				desc.Anchored = true
				desc.CanCollide = true
			end
		end
	elseif clone:IsA("BasePart") then
		clone.CFrame = cf
		clone.Anchored = true
		clone.CanCollide = true
	end
	clone.Parent = parent
	return clone
end

local function pickRandom(list: { Instance }, rng: Random): Instance?
	if #list == 0 then return nil end
	return list[rng:NextInteger(1, #list)]
end

-- ── 1. Graph & Layout Generation (Deterministic Critical Path + Branches) ────

local function buildDungeonGraph(rng: Random, config: DungeonConfig): ({ RoomData }, { [string]: boolean }, { DoorwayData })
	local totalRooms = config.totalRooms or rng:NextInteger(8, 11)
	local minTiles = config.minRoomTiles or 5
	local maxTiles = config.maxRoomTiles or 8
	local branchProb = config.branchProbability or 0.45

	local rooms: { RoomData } = {}
	local floorGrid: { [string]: boolean } = {}
	local doorwayList: { DoorwayData } = {}

	local function markFloor(x: number, z: number)
		floorGrid[`{x}_{z}`] = true
	end

	local function markDoorway(pos: Vector3, rotY: number)
		table.insert(doorwayList, { position = pos, rotY = rotY })
	end

	local function doesRoomOverlap(gx: number, gz: number, w: number, d: number, padding: number): boolean
		local pad = padding or 2
		for _, r in ipairs(rooms) do
			if not (gx + w + pad <= r.gx or gx >= r.gx + r.w + pad or gz + d + pad <= r.gz or gz >= r.gz + r.d + pad) then
				return true
			end
		end
		return false
	end

	-- 1. Create Start Room
	local startW = rng:NextInteger(minTiles, minTiles + 1)
	local startD = rng:NextInteger(minTiles, minTiles + 1)
	local startRoom: RoomData = {
		id = 1,
		roomType = "Start",
		gx = 0,
		gz = 0,
		w = startW,
		d = startD,
		centerWorld = Vector3.new((startW / 2) * FLOOR_SIZE, FLOOR_Y_OFFSET, (startD / 2) * FLOOR_SIZE),
		connections = {},
	}
	table.insert(rooms, startRoom)
	for x = 0, startW - 1 do
		for z = 0, startD - 1 do
			markFloor(x, z)
		end
	end

	-- Corridor carver with gate/doorway placement
	local function carveCorridor(fromRoom: RoomData, toGX: number, toGZ: number, toW: number, toD: number, dir: number, corridorLen: number)
		if dir == 0 then -- North (-Z)
			local startX = fromRoom.gx + math.floor((fromRoom.w - CORRIDOR_WIDTH) / 2)
			for step = 1, corridorLen do
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fx = startX + offset
					local fz = fromRoom.gz - step
					markFloor(fx, fz)
				end
			end
			local gatePos = Vector3.new((startX + 0.5) * FLOOR_SIZE, WALL_Y_OFFSET, (fromRoom.gz - 0.5) * FLOOR_SIZE)
			markDoorway(gatePos, 180)
		elseif dir == 1 then -- South (+Z)
			local startX = fromRoom.gx + math.floor((fromRoom.w - CORRIDOR_WIDTH) / 2)
			for step = 1, corridorLen do
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fx = startX + offset
					local fz = fromRoom.gz + fromRoom.d + step - 1
					markFloor(fx, fz)
				end
			end
			local gatePos = Vector3.new((startX + 0.5) * FLOOR_SIZE, WALL_Y_OFFSET, (fromRoom.gz + fromRoom.d - 0.5) * FLOOR_SIZE)
			markDoorway(gatePos, 0)
		elseif dir == 2 then -- East (+X)
			local startZ = fromRoom.gz + math.floor((fromRoom.d - CORRIDOR_WIDTH) / 2)
			for step = 1, corridorLen do
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fx = fromRoom.gx + fromRoom.w + step - 1
					local fz = startZ + offset
					markFloor(fx, fz)
				end
			end
			local gatePos = Vector3.new((fromRoom.gx + fromRoom.w - 0.5) * FLOOR_SIZE, WALL_Y_OFFSET, (startZ + 0.5) * FLOOR_SIZE)
			markDoorway(gatePos, 90)
		else -- West (-X)
			local startZ = fromRoom.gz + math.floor((fromRoom.d - CORRIDOR_WIDTH) / 2)
			for step = 1, corridorLen do
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fx = fromRoom.gx - step
					local fz = startZ + offset
					markFloor(fx, fz)
				end
			end
			local gatePos = Vector3.new((fromRoom.gx - 0.5) * FLOOR_SIZE, WALL_Y_OFFSET, (startZ + 0.5) * FLOOR_SIZE)
			markDoorway(gatePos, -90)
		end
	end

	-- 2. Build Critical Path
	local criticalLength = math.max(4, totalRooms - 3)
	local activeRoom = startRoom

	for i = 2, criticalLength do
		local rW = rng:NextInteger(minTiles, maxTiles)
		local rD = rng:NextInteger(minTiles, maxTiles)
		local isBoss = (i == criticalLength)
		if isBoss then
			rW = maxTiles + 1
			rD = maxTiles + 1
		end

		local placed = false
		local directions = { 0, 1, 2, 3 }
		for d = #directions, 2, -1 do
			local j = rng:NextInteger(1, d)
			directions[d], directions[j] = directions[j], directions[d]
		end

		for _, dir in ipairs(directions) do
			local corrLen = rng:NextInteger(3, 5)
			local candidateGX = activeRoom.gx
			local candidateGZ = activeRoom.gz

			if dir == 0 then candidateGZ = activeRoom.gz - corrLen - rD
			elseif dir == 1 then candidateGZ = activeRoom.gz + activeRoom.d + corrLen
			elseif dir == 2 then candidateGX = activeRoom.gx + activeRoom.w + corrLen
			else candidateGX = activeRoom.gx - corrLen - rW end

			if not doesRoomOverlap(candidateGX, candidateGZ, rW, rD, 2) then
				carveCorridor(activeRoom, candidateGX, candidateGZ, rW, rD, dir, corrLen)
				local newRoom: RoomData = {
					id = i,
					roomType = isBoss and "Boss" or "Combat",
					gx = candidateGX,
					gz = candidateGZ,
					w = rW,
					d = rD,
					centerWorld = Vector3.new((candidateGX + rW / 2) * FLOOR_SIZE, FLOOR_Y_OFFSET, (candidateGZ + rD / 2) * FLOOR_SIZE),
					connections = { activeRoom.id },
				}
				table.insert(activeRoom.connections, i)
				table.insert(rooms, newRoom)

				for x = candidateGX, candidateGX + rW - 1 do
					for z = candidateGZ, candidateGZ + rD - 1 do
						markFloor(x, z)
					end
				end

				activeRoom = newRoom
				placed = true
				break
			end
		end

		if not placed then
			local corrLen = 4
			local candidateGX = activeRoom.gx + activeRoom.w + corrLen
			local candidateGZ = activeRoom.gz
			carveCorridor(activeRoom, candidateGX, candidateGZ, rW, rD, 2, corrLen)
			local newRoom: RoomData = {
				id = i,
				roomType = isBoss and "Boss" or "Combat",
				gx = candidateGX,
				gz = candidateGZ,
				w = rW,
				d = rD,
				centerWorld = Vector3.new((candidateGX + rW / 2) * FLOOR_SIZE, FLOOR_Y_OFFSET, (candidateGZ + rD / 2) * FLOOR_SIZE),
				connections = { activeRoom.id },
			}
			table.insert(activeRoom.connections, i)
			table.insert(rooms, newRoom)
			for x = candidateGX, candidateGX + rW - 1 do
				for z = candidateGZ, candidateGZ + rD - 1 do
					markFloor(x, z)
				end
			end
			activeRoom = newRoom
		end
	end

	-- 3. Side Branches (Treasure, Shop, Elite, Event)
	local branchTypes: { RoomType } = { "Treasure", "Shop", "Elite", "Event" }
	local nextId = #rooms + 1

	for _, mainRoom in ipairs(rooms) do
		if nextId > totalRooms then break end
		if mainRoom.roomType == "Combat" and rng:NextNumber() < branchProb then
			local bType = table.remove(branchTypes, rng:NextInteger(1, #branchTypes)) or "Combat"
			local bW = rng:NextInteger(minTiles, minTiles + 2)
			local bD = rng:NextInteger(minTiles, minTiles + 2)

			for dir = 0, 3 do
				local corrLen = rng:NextInteger(3, 4)
				local candidateGX = mainRoom.gx
				local candidateGZ = mainRoom.gz

				if dir == 0 then candidateGZ = mainRoom.gz - corrLen - bD
				elseif dir == 1 then candidateGZ = mainRoom.gz + mainRoom.d + corrLen
				elseif dir == 2 then candidateGX = mainRoom.gx + mainRoom.w + corrLen
				else candidateGX = mainRoom.gx - corrLen - bW end

				if not doesRoomOverlap(candidateGX, candidateGZ, bW, bD, 2) then
					carveCorridor(mainRoom, candidateGX, candidateGZ, bW, bD, dir, corrLen)
					local branchRoom: RoomData = {
						id = nextId,
						roomType = bType,
						gx = candidateGX,
						gz = candidateGZ,
						w = bW,
						d = bD,
						centerWorld = Vector3.new((candidateGX + bW / 2) * FLOOR_SIZE, FLOOR_Y_OFFSET, (candidateGZ + bD / 2) * FLOOR_SIZE),
						connections = { mainRoom.id },
					}
					table.insert(mainRoom.connections, nextId)
					table.insert(rooms, branchRoom)

					for x = candidateGX, candidateGX + bW - 1 do
						for z = candidateGZ, candidateGZ + bD - 1 do
							markFloor(x, z)
						end
					end

					nextId += 1
					break
				end
			end
		end
	end

	return rooms, floorGrid, doorwayList
end

-- ── 2. Seamless Wall, Pure Gate & Pillar Placement ────────────────────────────

local function constructPerimeterWallsAndPillars(
	rooms: { RoomData },
	floorGrid: { [string]: boolean },
	doorwayList: { DoorwayData },
	wallsFolder: Folder,
	rng: Random
)
	local function hasFloor(gx: number, gz: number): boolean
		return floorGrid[`{gx}_{gz}`] == true
	end

	-- 1. Spawn Pure Gate Models at Corridor Entrances (NO pillars in gates)
	local gatePositions: { Vector3 } = {}
	for _, door in ipairs(doorwayList) do
		local doorPosWorld = Vector3.new(door.position.X, WALL_Y_OFFSET, door.position.Z)
		table.insert(gatePositions, doorPosWorld)

		local gateTemplate = pickRandom(assets.gates, rng)
		if gateTemplate then
			local gateCF = CFrame.new(doorPosWorld) * CFrame.Angles(0, math.rad(door.rotY), 0)
			spawnInstance(gateTemplate, gateCF, wallsFolder)
		end
	end

	local function isNearGate(pos: Vector3, maxDist: number): boolean
		for _, gPos in ipairs(gatePositions) do
			if (pos - gPos).Magnitude < maxDist then
				return true
			end
		end
		return false
	end

	-- 2. Identify 12-stud outer boundary edge faces
	local northEdges: { [number]: { [number]: boolean } } = {}
	local southEdges: { [number]: { [number]: boolean } } = {}
	local eastEdges: { [number]: { [number]: boolean } } = {}
	local westEdges: { [number]: { [number]: boolean } } = {}

	local corners: { [string]: Vector3 } = {}

	for key, _ in pairs(floorGrid) do
		local coords = string.split(key, "_")
		local gx = tonumber(coords[1]) :: number
		local gz = tonumber(coords[2]) :: number

		if not hasFloor(gx, gz - 1) then
			if not northEdges[gz] then northEdges[gz] = {} end
			northEdges[gz][gx] = true
		end
		if not hasFloor(gx, gz + 1) then
			if not southEdges[gz] then southEdges[gz] = {} end
			southEdges[gz][gx] = true
		end
		if not hasFloor(gx + 1, gz) then
			if not eastEdges[gx] then eastEdges[gx] = {} end
			eastEdges[gx][gz] = true
		end
		if not hasFloor(gx - 1, gz) then
			if not westEdges[gx] then westEdges[gx] = {} end
			westEdges[gx][gz] = true
		end
	end

	-- 3. Aggregate consecutive 12-stud edge tiles into continuous straight segments
	type LineSegment = {
		p1: Vector3,
		p2: Vector3,
		normal: Vector3,
		rotY: number,
	}

	local segments: { LineSegment } = {}

	local function processHorizontalEdges(edgeMap: { [number]: { [number]: boolean } }, normal: Vector3, rotY: number, zOffset: number)
		for gz, gxSet in pairs(edgeMap) do
			local gxList = {}
			for gx, _ in pairs(gxSet) do
				table.insert(gxList, gx)
			end
			table.sort(gxList)

			local i = 1
			while i <= #gxList do
				local startX = gxList[i]
				local endX = startX
				while i + 1 <= #gxList and gxList[i + 1] == endX + 1 do
					i += 1
					endX = gxList[i]
				end

				local p1 = Vector3.new((startX - 0.5) * FLOOR_SIZE, WALL_Y_OFFSET, (gz + zOffset) * FLOOR_SIZE)
				local p2 = Vector3.new((endX + 0.5) * FLOOR_SIZE, WALL_Y_OFFSET, (gz + zOffset) * FLOOR_SIZE)

				table.insert(segments, { p1 = p1, p2 = p2, normal = normal, rotY = rotY })
				corners[`{math.round(p1.X)}_{math.round(p1.Z)}`] = p1
				corners[`{math.round(p2.X)}_{math.round(p2.Z)}`] = p2

				i += 1
			end
		end
	end

	local function processVerticalEdges(edgeMap: { [number]: { [number]: boolean } }, normal: Vector3, rotY: number, xOffset: number)
		for gx, gzSet in pairs(edgeMap) do
			local gzList = {}
			for gz, _ in pairs(gzSet) do
				table.insert(gzList, gz)
			end
			table.sort(gzList)

			local i = 1
			while i <= #gzList do
				local startZ = gzList[i]
				local endZ = startZ
				while i + 1 <= #gzList and gzList[i + 1] == endZ + 1 do
					i += 1
					endZ = gzList[i]
				end

				local p1 = Vector3.new((gx + xOffset) * FLOOR_SIZE, WALL_Y_OFFSET, (startZ - 0.5) * FLOOR_SIZE)
				local p2 = Vector3.new((gx + xOffset) * FLOOR_SIZE, WALL_Y_OFFSET, (endZ + 0.5) * FLOOR_SIZE)

				table.insert(segments, { p1 = p1, p2 = p2, normal = normal, rotY = rotY })
				corners[`{math.round(p1.X)}_{math.round(p1.Z)}`] = p1
				corners[`{math.round(p2.X)}_{math.round(p2.Z)}`] = p2

				i += 1
			end
		end
	end

	processHorizontalEdges(northEdges, Vector3.new(0, 0, -1), 180, -0.5)
	processHorizontalEdges(southEdges, Vector3.new(0, 0, 1), 0, 0.5)
	processVerticalEdges(eastEdges, Vector3.new(1, 0, 0), 90, 0.5)
	processVerticalEdges(westEdges, Vector3.new(-1, 0, 0), -90, -0.5)

	local function isRoomTile(gx: number, gz: number): boolean
		for _, room in ipairs(rooms) do
			if gx >= room.gx and gx < room.gx + room.w and gz >= room.gz and gz < room.gz + room.d then
				return true
			end
		end
		return false
	end

	local function isCorridorTile(gx: number, gz: number): boolean
		return hasFloor(gx, gz) and not isRoomTile(gx, gz)
	end

	local function isCorridorArea(pos: Vector3): boolean
		local gxCenter = math.floor(pos.X / FLOOR_SIZE + 0.5)
		local gzCenter = math.floor(pos.Z / FLOOR_SIZE + 0.5)
		for dx = -1, 1 do
			for dz = -1, 1 do
				if isCorridorTile(gxCenter + dx, gzCenter + dz) then
					return true
				end
			end
		end
		return false
	end

	-- 4. Spawn Corner Pillars ONLY at room corners (strictly NO pillars in corridors/hallways or near gates)
	for _, cornerPos in pairs(corners) do
		if not isNearGate(cornerPos, 16) and not isCorridorArea(cornerPos) then
			local pillarTemplate = pickRandom(assets.pillars, rng)
			if pillarTemplate then
				local pillarCF = CFrame.new(cornerPos)
				spawnInstance(pillarTemplate, pillarCF, wallsFolder)
			end
		end
	end

	-- 5. Tile 17-stud Wall Pieces end-to-end along each segment with zero gaps
	for _, seg in ipairs(segments) do
		local vec = seg.p2 - seg.p1
		local length = vec.Magnitude
		local tangent = vec.Unit

		local numWalls = math.max(1, math.ceil(length / WALL_PIECE_LEN))
		local step = length / numWalls

		for i = 1, numWalls do
			local wallCenter = seg.p1 + tangent * ((i - 0.5) * step)
			if not isNearGate(wallCenter, 10) then
				local wallCF = CFrame.new(wallCenter) * CFrame.Angles(0, math.rad(seg.rotY), 0)
				local wallPiece = pickRandom(assets.walls, rng)
				if wallPiece then
					spawnInstance(wallPiece, wallCF, wallsFolder)
				else
					local p = Instance.new("Part")
					p.Size = Vector3.new(step + 1, 14, 2)
					p.CFrame = wallCF * CFrame.new(0, 7, 0)
					p.Anchored = true
					p.Material = Enum.Material.Stone
					p.Color = Color3.fromRGB(48, 48, 52)
					p.Parent = wallsFolder
				end
			end
		end
	end
end

-- ── 3. Pitch-Black Abyss Exit Construction ───────────────────────────────────

local function constructPitchBlackExit(stairCF: CFrame, parentFolder: Folder)
	local exitModel = Instance.new("Folder")
	exitModel.Name = "AbyssExit"
	exitModel.Parent = parentFolder

	local voidPortal = Instance.new("Part")
	voidPortal.Name = "AbyssVoidGate"
	voidPortal.Size = Vector3.new(22, 18, 26)
	voidPortal.CFrame = stairCF * CFrame.new(0, 4, 15)
	voidPortal.Anchored = true
	voidPortal.CanCollide = false
	voidPortal.CastShadow = true
	voidPortal.Material = Enum.Material.SmoothPlastic
	voidPortal.Color = Color3.fromRGB(0, 0, 0)
	voidPortal.Transparency = 0.05
	voidPortal.Parent = exitModel

	local voidFloor = Instance.new("Part")
	voidFloor.Name = "AbyssFloor"
	voidFloor.Size = Vector3.new(22, 2, 26)
	voidFloor.CFrame = stairCF * CFrame.new(0, -7, 15)
	voidFloor.Anchored = true
	voidFloor.CanCollide = true
	voidFloor.Color = Color3.fromRGB(0, 0, 0)
	voidFloor.Parent = exitModel

	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, -2, 4)
	att.Parent = voidPortal

	local abyssFog = Instance.new("ParticleEmitter")
	abyssFog.Name = "DarkAbyssParticles"
	abyssFog.Texture = "rbxassetid://243098098"
	abyssFog.Color = ColorSequence.new(Color3.fromRGB(0, 0, 0))
	abyssFog.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.5, 0.02),
		NumberSequenceKeypoint.new(1, 0.8),
	})
	abyssFog.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 10),
		NumberSequenceKeypoint.new(1, 24),
	})
	abyssFog.Lifetime = NumberRange.new(2.5, 4.5)
	abyssFog.Rate = 24
	abyssFog.Speed = NumberRange.new(0.5, 2.5)
	abyssFog.SpreadAngle = Vector2.new(180, 180)
	abyssFog.Parent = att

	voidPortal.Touched:Connect(function(hit)
		local char = hit.Parent
		if char and char:FindFirstChild("Humanoid") then
			local player = game:GetService("Players"):GetPlayerFromCharacter(char)
			if player and not player:GetAttribute("TransitioningFloor") then
				player:SetAttribute("TransitioningFloor", true)
				print(`[Roguelite] {player.Name} entered the Abyss Staircase! Generating Next Level...`)
				task.delay(1.2, function()
					player:SetAttribute("TransitioningFloor", nil)
					local newSeed = os.time() + math.random(1, 100000)
					DungeonGenerator.Generate({ seed = newSeed })
					local newSpawn = DungeonGenerator.GetSpawnCFrame()
					if char:FindFirstChild("HumanoidRootPart") then
						char:PivotTo(newSpawn)
					end
				end)
			end
		end
	end)
end

-- ── 4. Rich Cosmetics, Rubble & Barriers Placement ──────────────────────────

local function decorateRooms(rooms: { RoomData }, propsFolder: Folder, rng: Random)
	for _, room in ipairs(rooms) do
		local minX, maxX = room.gx, room.gx + room.w - 1
		local minZ, maxZ = room.gz, room.gz + room.d - 1

		-- 1. Rubble: Generously placed along wall perimeters and in all room corners
		if #assets.rubble > 0 then
			local rubbleClusters = rng:NextInteger(3, 6)
			for _ = 1, rubbleClusters do
				local side = rng:NextInteger(1, 4)
				local rx = (side == 1 and minX) or (side == 2 and maxX) or rng:NextInteger(minX, maxX)
				local rz = (side == 3 and minZ) or (side == 4 and maxZ) or rng:NextInteger(minZ, maxZ)
				local rubPos = Vector3.new(rx * FLOOR_SIZE, FLOOR_Y_OFFSET + 0.2, rz * FLOOR_SIZE)
				local rubTemplate = pickRandom(assets.rubble, rng)
				if rubTemplate then
					local cf = CFrame.new(rubPos) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
					spawnInstance(rubTemplate, cf, propsFolder)
				end
			end
		end

		-- 2. Barriers: Placed as tactical cover inside combat/elite rooms
		if #assets.barriers > 0 and (room.roomType == "Combat" or room.roomType == "Elite") then
			local barrierCount = rng:NextInteger(2, 4)
			for _ = 1, barrierCount do
				local bx = rng:NextInteger(minX + 1, maxX - 1)
				local bz = rng:NextInteger(minZ + 1, maxZ - 1)
				local bPos = Vector3.new(bx * FLOOR_SIZE, FLOOR_Y_OFFSET + 0.2, bz * FLOOR_SIZE)
				local barTemplate = pickRandom(assets.barriers, rng)
				if barTemplate then
					local cf = CFrame.new(bPos) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
					spawnInstance(barTemplate, cf, propsFolder)
				end
			end
		end

		-- 3. Cosmetics: Placed abundantly across all rooms (torches, pillars, chests, urns, crates)
		if #assets.cosmetics > 0 then
			if room.roomType == "Start" then
				for _ = 1, rng:NextInteger(2, 3) do
					local cosPos = room.centerWorld + Vector3.new(rng:NextInteger(-6, 6), 0.2, rng:NextInteger(-6, 6))
					local cosTemplate = pickRandom(assets.cosmetics, rng)
					if cosTemplate then
						local cf = CFrame.new(cosPos) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
						spawnInstance(cosTemplate, cf, propsFolder)
					end
				end
			elseif room.roomType == "Combat" or room.roomType == "Elite" then
				for _ = 1, rng:NextInteger(3, 5) do
					local side = rng:NextInteger(1, 4)
					local cx = (side == 1 and minX) or (side == 2 and maxX) or rng:NextInteger(minX, maxX)
					local cz = (side == 3 and minZ) or (side == 4 and maxZ) or rng:NextInteger(minZ, maxZ)
					local cosPos = Vector3.new(cx * FLOOR_SIZE, FLOOR_Y_OFFSET + 0.2, cz * FLOOR_SIZE)
					local cosTemplate = pickRandom(assets.cosmetics, rng)
					if cosTemplate then
						local cf = CFrame.new(cosPos) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
						spawnInstance(cosTemplate, cf, propsFolder)
					end
				end
			elseif room.roomType == "Treasure" or room.roomType == "Shop" or room.roomType == "Boss" then
				for _ = 1, rng:NextInteger(4, 6) do
					local offset = Vector3.new(rng:NextInteger(-8, 8), 0.2, rng:NextInteger(-8, 8))
					local cosPos = room.centerWorld + offset
					local cosTemplate = pickRandom(assets.cosmetics, rng)
					if cosTemplate then
						local cf = CFrame.new(cosPos) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
						spawnInstance(cosTemplate, cf, propsFolder)
					end
				end
			end
		end
	end
end

-- ── 5. Main Generator Lifecycle ──────────────────────────────────────────────

function DungeonGenerator.Generate(config: DungeonConfig?): (CFrame, CFrame, CFrame)
	loadAssets()

	local cfg = config or {}
	local seed = cfg.seed or os.time()
	activeSeed = seed
	local rng = Random.new(seed)

	-- Clean previous dungeon instance
	DungeonGenerator.Clear()

	local dungeonFolder = Instance.new("Folder")
	dungeonFolder.Name = "GeneratedDungeon"
	dungeonFolder.Parent = Workspace
	currentDungeonFolder = dungeonFolder

	local floorsFolder = Instance.new("Folder", dungeonFolder); floorsFolder.Name = "Floors"
	local wallsFolder  = Instance.new("Folder", dungeonFolder); wallsFolder.Name = "Walls"
	local stairsFolder = Instance.new("Folder", dungeonFolder); stairsFolder.Name = "Stairs"
	local propsFolder  = Instance.new("Folder", dungeonFolder); propsFolder.Name = "Props"

	print(`[DungeonGenerator] ─── Building Roguelite Dungeon (Seed: {seed}, Floor Y: {FLOOR_Y_OFFSET}, Wall Y: {WALL_Y_OFFSET}) ───`)

	-- 1. Graph Layout Construction
	local rooms, floorGrid, doorwayList = buildDungeonGraph(rng, cfg)
	local startRoom = rooms[1]
	local bossRoom = rooms[#rooms]

	cachedSpawnCFrame = CFrame.new(startRoom.centerWorld + Vector3.new(0, 3, 0))
	cachedBossCFrame  = CFrame.new(bossRoom.centerWorld + Vector3.new(0, 3, 0))

	-- 2. Floor Placement (Exact 12x12 Snapping at FLOOR_Y_OFFSET = 4)
	for key, _ in pairs(floorGrid) do
		local coords = string.split(key, "_")
		local gx = tonumber(coords[1]) :: number
		local gz = tonumber(coords[2]) :: number
		local pos = Vector3.new(gx * FLOOR_SIZE, FLOOR_Y_OFFSET, gz * FLOOR_SIZE)

		local floorTemplate = pickRandom(assets.floors, rng)
		if floorTemplate then
			local rotY = rng:NextInteger(0, 3) * 90
			local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0)
			spawnInstance(floorTemplate, cf, floorsFolder)
		else
			local p = Instance.new("Part")
			p.Size = Vector3.new(FLOOR_SIZE, 1, FLOOR_SIZE)
			p.Position = pos
			p.Anchored = true
			p.Material = Enum.Material.Cobblestone
			p.Color = Color3.fromRGB(60, 60, 65)
			p.Parent = floorsFolder
		end
	end

	-- 3. Continuous Perimeter Wall, Pure Gate & Corner Pillar Construction
	constructPerimeterWallsAndPillars(rooms, floorGrid, doorwayList, wallsFolder, rng)

	-- 4. Exit Staircase & Pitch-Black Abyss in the Boss Chamber
	local stairsTemplate = pickRandom(assets.stairs, rng)
	local stairPos = Vector3.new(
		(bossRoom.gx + bossRoom.w / 2) * FLOOR_SIZE,
		FLOOR_Y_OFFSET,
		(bossRoom.gz + bossRoom.d - 1) * FLOOR_SIZE
	)
	local stairCF = CFrame.new(stairPos) * CFrame.Angles(0, 0, 0)
	cachedExitCFrame = stairCF

	if stairsTemplate then
		spawnInstance(stairsTemplate, stairCF, stairsFolder)
	end
	constructPitchBlackExit(stairCF, stairsFolder)

	-- 5. Interior Decorating (Abundant Corner/Perimeter Rubble, Barriers, Cosmetics)
	decorateRooms(rooms, propsFolder, rng)

	-- Broadcast map grid payload to clients for minimap overlay
	local roomListPayload = {}
	for _, rm in ipairs(rooms) do
		table.insert(roomListPayload, {
			id = rm.id,
			roomType = rm.roomType,
			gx = rm.gx,
			gz = rm.gz,
			w = rm.w,
			d = rm.d,
		})
	end

	local mapPayload = {
		tileSize = FLOOR_SIZE,
		grid = floorGrid,
		rooms = roomListPayload,
	}
	cachedMapPayload = mapPayload

	pcall(function()
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		if Shared then
			local Network = require(Shared:FindFirstChild("Network") :: ModuleScript)
			local mapRemote = Network.GetRemoteEvent(Network.Remotes.DungeonMapData)
			mapRemote:FireAllClients(mapPayload)
		end
	end)

	print(`[DungeonGenerator] ✅ Procedural Dungeon Ready! ({#rooms} rooms generated).`)
	print(`  • Spawn: {cachedSpawnCFrame.Position}`)
	print(`  • Boss:  {cachedBossCFrame.Position}`)
	print(`  • Exit:  {cachedExitCFrame.Position}`)

	return cachedSpawnCFrame, cachedBossCFrame, cachedExitCFrame
end

-- Send cached map payload when a player joins late
Players.PlayerAdded:Connect(function(plr: Player)
	if cachedMapPayload then
		pcall(function()
			local Shared = ReplicatedStorage:FindFirstChild("Shared")
			if Shared then
				local Network = require(Shared:FindFirstChild("Network") :: ModuleScript)
				local mapRemote = Network.GetRemoteEvent(Network.Remotes.DungeonMapData)
				mapRemote:FireClient(plr, cachedMapPayload)
			end
		end)
	end
end)

-- ── Public API ───────────────────────────────────────────────────────────────

function DungeonGenerator.Clear()
	if currentDungeonFolder and currentDungeonFolder.Parent then
		currentDungeonFolder:Destroy()
		currentDungeonFolder = nil
	end
	local existing = Workspace:FindFirstChild("GeneratedDungeon") or Workspace:FindFirstChild("Dungeon")
	if existing then
		existing:Destroy()
	end
end

function DungeonGenerator.GetSpawnCFrame(): CFrame
	return cachedSpawnCFrame
end

function DungeonGenerator.GetBossCFrame(): CFrame
	return cachedBossCFrame
end

function DungeonGenerator.GetExitCFrame(): CFrame
	return cachedExitCFrame
end

function DungeonGenerator.GetActiveSeed(): number
	return activeSeed
end

function DungeonGenerator.GetMapPayload(): any
	return cachedMapPayload
end

return DungeonGenerator
