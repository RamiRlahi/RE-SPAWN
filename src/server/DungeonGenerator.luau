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
local FLOOR_Y_OFFSET    = 4     -- Tier 0 floor tile elevation (4 studs)
local WALL_Y_OFFSET     = 11    -- Tier 0 wall elevation (11 studs)

-- Stair & Multi-Floor Dimensions (13 studs vertical rise, 21 studs length, 11 studs width)
local STAIR_WIDTH       = 11    -- Stair model width (studs)
local STAIR_HEIGHT      = 13    -- Vertical height per floor tier (13 studs rise)
local STAIR_LENGTH      = 21    -- Horizontal stair length (21 studs)

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

type StairData = {
	cframe: CFrame,
	lowerFloorY: number,
	upperFloorY: number,
}

type CellData = {
	floorY: number,
	wallY: number,
	tier: number,
}

type RoomData = {
	id: number,
	roomType: RoomType,
	tier: number,             -- Vertical floor level (0, 1, 2, etc.)
	floorY: number,           -- Base floor Y elevation for this room
	wallY: number,            -- Base wall Y elevation for this room
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
	floors       = {} :: { Instance },
	centerPieces = {} :: { Instance },
	walls        = {} :: { Instance },
	pillars      = {} :: { Instance },
	gates        = {} :: { Instance },
	barriers     = {} :: { Instance },
	rubble       = {} :: { Instance },
	stairs       = {} :: { Instance },
	cosmetics    = {} :: { Instance },
}

-- ── Asset Discovery & Category Separation ────────────────────────────────────

local function loadAssets()
	table.clear(assets.floors)
	table.clear(assets.centerPieces)
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

	-- Discover Floors & Center Pieces (subfolder under Floor as well as root level)
	local floorFolder = nil
	for _, child in ipairs(root:GetChildren()) do
		if string.lower(child.Name) == "floor" or string.lower(child.Name) == "floors" then
			floorFolder = child
			break
		end
	end

	if floorFolder then
		for _, item in ipairs(floorFolder:GetChildren()) do
			if item:IsA("Folder") and string.lower(item.Name):find("center") then
				for _, cp in ipairs(item:GetChildren()) do
					if cp:IsA("Model") or cp:IsA("BasePart") then
						table.insert(assets.centerPieces, cp)
					end
				end
			elseif item:IsA("Model") or item:IsA("BasePart") then
				table.insert(assets.floors, item)
			end
		end
	end

	-- Also scan root-level center pieces folder if present outside Floor
	for _, child in ipairs(root:GetChildren()) do
		if child:IsA("Folder") and string.lower(child.Name):find("center") and child ~= floorFolder then
			for _, cp in ipairs(child:GetChildren()) do
				if cp:IsA("Model") or cp:IsA("BasePart") then
					table.insert(assets.centerPieces, cp)
				end
			end
		end
	end

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
	print(`  • Center Pieces: { #assets.centerPieces } (Center floor tiles)`)
	print(`  • Walls: { #assets.walls } (17x17, Y={WALL_Y_OFFSET})`)
	print(`  • Pillars: { #assets.pillars } (Corner columns)`)
	print(`  • Gates: { #assets.gates } (Pure corridor archways, no pillars)`)
	print(`  • Stairs: { #assets.stairs }`)
	print(`  • Barriers: { #assets.barriers }`)
	print(`  • Rubble: { #assets.rubble }`)
	print(`  • Cosmetics: { #assets.cosmetics } (Raised +3.2 studs near walls/center)`)
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

local function buildDungeonGraph(rng: Random, config: DungeonConfig): ({ RoomData }, { [string]: CellData }, { DoorwayData }, { StairData })
	local totalRooms = config.totalRooms or rng:NextInteger(8, 11)
	local minTiles = config.minRoomTiles or 5
	local maxTiles = config.maxRoomTiles or 8
	local branchProb = config.branchProbability or 0.45

	local rooms: { RoomData } = {}
	local floorGrid: { [string]: CellData } = {}
	local doorwayList: { DoorwayData } = {}
	local stairList: { StairData } = {}

	local function markFloor(x: number, z: number, floorY: number, wallY: number, tier: number)
		floorGrid[`{x}_{z}`] = {
			floorY = floorY,
			wallY = wallY,
			tier = tier,
		}
	end

	local function hasFloor(x: number, z: number): boolean
		return floorGrid[`{x}_{z}`] ~= nil
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

	-- 1. Create Start Room (Tier 0)
	local startW = rng:NextInteger(minTiles, minTiles + 1)
	local startD = rng:NextInteger(minTiles, minTiles + 1)
	local startRoom: RoomData = {
		id = 1,
		roomType = "Start",
		tier = 0,
		floorY = FLOOR_Y_OFFSET,
		wallY = WALL_Y_OFFSET,
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
			markFloor(x, z, FLOOR_Y_OFFSET, WALL_Y_OFFSET, 0)
		end
	end

	-- Multi-floor corridor carver with inter-floor stair placement
	local function carveCorridor(
		fromRoom: RoomData,
		toRoomTier: number,
		toRoomFloorY: number,
		toRoomWallY: number,
		toGX: number,
		toGZ: number,
		toW: number,
		toD: number,
		dir: number,
		corridorLen: number
	)
		local t1, y1, wY1 = fromRoom.tier, fromRoom.floorY, fromRoom.wallY
		local t2, y2, wY2 = toRoomTier, toRoomFloorY, toRoomWallY
		local isStair = (t1 ~= t2)
		local midStep = math.floor(corridorLen / 2)

		if dir == 0 then -- North (-Z)
			local startX = fromRoom.gx + math.floor((fromRoom.w - CORRIDOR_WIDTH) / 2)
			if isStair then
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fx = startX + offset
					markFloor(fx, fromRoom.gz - 1, y1, wY1, t1)
					for step = 3, corridorLen do
						markFloor(fx, fromRoom.gz - step, y2, wY2, t2)
					end
				end

				local gatePos = Vector3.new((startX + 0.5) * FLOOR_SIZE, wY1, (fromRoom.gz - 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = 180 })

				local minFY = math.min(y1, y2)
				local stairZ = (fromRoom.gz - 2) * FLOOR_SIZE
				local stairX = (startX + (CORRIDOR_WIDTH / 2) - 0.5) * FLOOR_SIZE
				local rotY = (t2 > t1) and 180 or 0
				local stairCF = CFrame.new(stairX, minFY, stairZ) * CFrame.Angles(0, math.rad(rotY), 0)
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2) })

				local archwayPos = Vector3.new(stairX, wY2, (fromRoom.gz - 2.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = archwayPos, rotY = 180 })
			else
				for step = 1, corridorLen do
					for offset = 0, CORRIDOR_WIDTH - 1 do
						markFloor(startX + offset, fromRoom.gz - step, y1, wY1, t1)
					end
				end
				local gatePos = Vector3.new((startX + 0.5) * FLOOR_SIZE, wY1, (fromRoom.gz - 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = 180 })
			end

		elseif dir == 1 then -- South (+Z)
			local startX = fromRoom.gx + math.floor((fromRoom.w - CORRIDOR_WIDTH) / 2)
			if isStair then
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fx = startX + offset
					markFloor(fx, fromRoom.gz + fromRoom.d, y1, wY1, t1)
					for step = 3, corridorLen do
						markFloor(fx, fromRoom.gz + fromRoom.d + step - 1, y2, wY2, t2)
					end
				end

				local gatePos = Vector3.new((startX + 0.5) * FLOOR_SIZE, wY1, (fromRoom.gz + fromRoom.d - 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = 0 })

				local minFY = math.min(y1, y2)
				local stairZ = (fromRoom.gz + fromRoom.d + 1) * FLOOR_SIZE
				local stairX = (startX + (CORRIDOR_WIDTH / 2) - 0.5) * FLOOR_SIZE
				local rotY = (t2 > t1) and 0 or 180
				local stairCF = CFrame.new(stairX, minFY, stairZ) * CFrame.Angles(0, math.rad(rotY), 0)
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2) })

				local archwayPos = Vector3.new(stairX, wY2, (fromRoom.gz + fromRoom.d + 1.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = archwayPos, rotY = 0 })
			else
				for step = 1, corridorLen do
					for offset = 0, CORRIDOR_WIDTH - 1 do
						markFloor(startX + offset, fromRoom.gz + fromRoom.d + step - 1, y1, wY1, t1)
					end
				end
				local gatePos = Vector3.new((startX + 0.5) * FLOOR_SIZE, wY1, (fromRoom.gz + fromRoom.d - 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = 0 })
			end

		elseif dir == 2 then -- East (+X)
			local startZ = fromRoom.gz + math.floor((fromRoom.d - CORRIDOR_WIDTH) / 2)
			if isStair then
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fz = startZ + offset
					markFloor(fromRoom.gx + fromRoom.w, fz, y1, wY1, t1)
					for step = 3, corridorLen do
						markFloor(fromRoom.gx + fromRoom.w + step - 1, fz, y2, wY2, t2)
					end
				end

				local gatePos = Vector3.new((fromRoom.gx + fromRoom.w - 0.5) * FLOOR_SIZE, wY1, (startZ + 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = 90 })

				local minFY = math.min(y1, y2)
				local stairX = (fromRoom.gx + fromRoom.w + 1) * FLOOR_SIZE
				local stairZ = (startZ + (CORRIDOR_WIDTH / 2) - 0.5) * FLOOR_SIZE
				local rotY = (t2 > t1) and 90 or -90
				local stairCF = CFrame.new(stairX, minFY, stairZ) * CFrame.Angles(0, math.rad(rotY), 0)
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2) })

				local archwayPos = Vector3.new((fromRoom.gx + fromRoom.w + 1.5) * FLOOR_SIZE, wY2, stairZ)
				table.insert(doorwayList, { position = archwayPos, rotY = 90 })
			else
				for step = 1, corridorLen do
					for offset = 0, CORRIDOR_WIDTH - 1 do
						markFloor(fromRoom.gx + fromRoom.w + step - 1, startZ + offset, y1, wY1, t1)
					end
				end
				local gatePos = Vector3.new((fromRoom.gx + fromRoom.w - 0.5) * FLOOR_SIZE, wY1, (startZ + 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = 90 })
			end

		else -- West (-X)
			local startZ = fromRoom.gz + math.floor((fromRoom.d - CORRIDOR_WIDTH) / 2)
			if isStair then
				for offset = 0, CORRIDOR_WIDTH - 1 do
					local fz = startZ + offset
					markFloor(fromRoom.gx - 1, fz, y1, wY1, t1)
					for step = 3, corridorLen do
						markFloor(fromRoom.gx - step, fz, y2, wY2, t2)
					end
				end

				local gatePos = Vector3.new((fromRoom.gx - 0.5) * FLOOR_SIZE, wY1, (startZ + 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = -90 })

				local minFY = math.min(y1, y2)
				local stairX = (fromRoom.gx - 2) * FLOOR_SIZE
				local stairZ = (startZ + (CORRIDOR_WIDTH / 2) - 0.5) * FLOOR_SIZE
				local rotY = (t2 > t1) and -90 or 90
				local stairCF = CFrame.new(stairX, minFY, stairZ) * CFrame.Angles(0, math.rad(rotY), 0)
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2) })

				local archwayPos = Vector3.new((fromRoom.gx - 2.5) * FLOOR_SIZE, wY2, stairZ)
				table.insert(doorwayList, { position = archwayPos, rotY = -90 })
			else
				for step = 1, corridorLen do
					for offset = 0, CORRIDOR_WIDTH - 1 do
						markFloor(fromRoom.gx - step, startZ + offset, y1, wY1, t1)
					end
				end
				local gatePos = Vector3.new((fromRoom.gx - 0.5) * FLOOR_SIZE, wY1, (startZ + 0.5) * FLOOR_SIZE)
				table.insert(doorwayList, { position = gatePos, rotY = -90 })
			end
		end
	end

	-- 2. Build Critical Path across Multi-Floor Tiers
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

		-- Progress vertical tier every 2 rooms (Tier 0 -> Tier 1 -> Tier 2...)
		local nextTier = math.floor((i - 1) / 2)
		local nextFY = FLOOR_Y_OFFSET + (nextTier * STAIR_HEIGHT)
		local nextWY = WALL_Y_OFFSET + (nextTier * STAIR_HEIGHT)

		local placed = false
		local directions = { 0, 1, 2, 3 }
		for d = #directions, 2, -1 do
			local j = rng:NextInteger(1, d)
			directions[d], directions[j] = directions[j], directions[d]
		end

		for _, dir in ipairs(directions) do
			local corrLen = (nextTier ~= activeRoom.tier) and 4 or rng:NextInteger(3, 5)
			local candidateGX = activeRoom.gx
			local candidateGZ = activeRoom.gz

			if dir == 0 then candidateGZ = activeRoom.gz - corrLen - rD
			elseif dir == 1 then candidateGZ = activeRoom.gz + activeRoom.d + corrLen
			elseif dir == 2 then candidateGX = activeRoom.gx + activeRoom.w + corrLen
			else candidateGX = activeRoom.gx - corrLen - rW end

			if not doesRoomOverlap(candidateGX, candidateGZ, rW, rD, 2) then
				carveCorridor(activeRoom, nextTier, nextFY, nextWY, candidateGX, candidateGZ, rW, rD, dir, corrLen)
				local newRoom: RoomData = {
					id = i,
					roomType = isBoss and "Boss" or "Combat",
					tier = nextTier,
					floorY = nextFY,
					wallY = nextWY,
					gx = candidateGX,
					gz = candidateGZ,
					w = rW,
					d = rD,
					centerWorld = Vector3.new((candidateGX + rW / 2) * FLOOR_SIZE, nextFY, (candidateGZ + rD / 2) * FLOOR_SIZE),
					connections = { activeRoom.id },
				}
				table.insert(activeRoom.connections, i)
				table.insert(rooms, newRoom)

				for x = candidateGX, candidateGX + rW - 1 do
					for z = candidateGZ, candidateGZ + rD - 1 do
						markFloor(x, z, nextFY, nextWY, nextTier)
					end
				end

				activeRoom = newRoom
				placed = true
				break
			end
		end

		if not placed then
			-- Fallback: try progressively larger offsets in all 4 directions to find non-overlapping XZ position
			local fallbackDirs = { 2, 1, 0, 3 } -- East, South, North, West
			local fallbackPlaced = false

			for _, fbDir in ipairs(fallbackDirs) do
				for offsetMul = 1, 4 do
					local corrLen = 4 + offsetMul
					local candidateGX = activeRoom.gx
					local candidateGZ = activeRoom.gz

					if fbDir == 0 then candidateGZ = activeRoom.gz - corrLen - rD
					elseif fbDir == 1 then candidateGZ = activeRoom.gz + activeRoom.d + corrLen
					elseif fbDir == 2 then candidateGX = activeRoom.gx + activeRoom.w + corrLen
					else candidateGX = activeRoom.gx - corrLen - rW end

					if not doesRoomOverlap(candidateGX, candidateGZ, rW, rD, 2) then
						carveCorridor(activeRoom, nextTier, nextFY, nextWY, candidateGX, candidateGZ, rW, rD, fbDir, corrLen)
						local newRoom: RoomData = {
							id = i,
							roomType = isBoss and "Boss" or "Combat",
							tier = nextTier,
							floorY = nextFY,
							wallY = nextWY,
							gx = candidateGX,
							gz = candidateGZ,
							w = rW,
							d = rD,
							centerWorld = Vector3.new((candidateGX + rW / 2) * FLOOR_SIZE, nextFY, (candidateGZ + rD / 2) * FLOOR_SIZE),
							connections = { activeRoom.id },
						}
						table.insert(activeRoom.connections, i)
						table.insert(rooms, newRoom)
						for x = candidateGX, candidateGX + rW - 1 do
							for z = candidateGZ, candidateGZ + rD - 1 do
								markFloor(x, z, nextFY, nextWY, nextTier)
							end
						end
						activeRoom = newRoom
						fallbackPlaced = true
						break
					end
				end
				if fallbackPlaced then break end
			end

			if not fallbackPlaced then
				warn(`[DungeonGenerator] Could not place room #{i} without XZ overlap — skipping.`)
			end
		end
	end

	-- 3. Side Branches across Multi-Floor Tiers
	local branchTypes: { RoomType } = { "Treasure", "Shop", "Elite", "Event" }
	local nextId = #rooms + 1

	for _, mainRoom in ipairs(rooms) do
		if nextId > totalRooms then break end
		if mainRoom.roomType == "Combat" and rng:NextNumber() < branchProb then
			local bType = table.remove(branchTypes, rng:NextInteger(1, #branchTypes)) or "Combat"
			local bW = rng:NextInteger(minTiles, minTiles + 2)
			local bD = rng:NextInteger(minTiles, minTiles + 2)

			local branchTier = mainRoom.tier + (rng:NextNumber() < 0.5 and 1 or 0)
			local bFY = FLOOR_Y_OFFSET + (branchTier * STAIR_HEIGHT)
			local bWY = WALL_Y_OFFSET + (branchTier * STAIR_HEIGHT)

			for dir = 0, 3 do
				local corrLen = (branchTier ~= mainRoom.tier) and 4 or rng:NextInteger(3, 4)
				local candidateGX = mainRoom.gx
				local candidateGZ = mainRoom.gz

				if dir == 0 then candidateGZ = mainRoom.gz - corrLen - bD
				elseif dir == 1 then candidateGZ = mainRoom.gz + mainRoom.d + corrLen
				elseif dir == 2 then candidateGX = mainRoom.gx + mainRoom.w + corrLen
				else candidateGX = mainRoom.gx - corrLen - bW end

				if not doesRoomOverlap(candidateGX, candidateGZ, bW, bD, 2) then
					carveCorridor(mainRoom, branchTier, bFY, bWY, candidateGX, candidateGZ, bW, bD, dir, corrLen)
					local branchRoom: RoomData = {
						id = nextId,
						roomType = bType,
						tier = branchTier,
						floorY = bFY,
						wallY = bWY,
						gx = candidateGX,
						gz = candidateGZ,
						w = bW,
						d = bD,
						centerWorld = Vector3.new((candidateGX + bW / 2) * FLOOR_SIZE, bFY, (candidateGZ + bD / 2) * FLOOR_SIZE),
						connections = { mainRoom.id },
					}
					table.insert(mainRoom.connections, nextId)
					table.insert(rooms, branchRoom)

					for x = candidateGX, candidateGX + bW - 1 do
						for z = candidateGZ, candidateGZ + bD - 1 do
							markFloor(x, z, bFY, bWY, branchTier)
						end
					end

					nextId += 1
					break
				end
			end
		end
	end

	return rooms, floorGrid, doorwayList, stairList
end

-- ── 2. Seamless Wall, Pure Gate & Pillar Placement ────────────────────────────

local function constructPerimeterWallsAndPillars(
	rooms: { RoomData },
	floorGrid: { [string]: CellData },
	doorwayList: { DoorwayData },
	stairList: { StairData },
	wallsFolder: Folder,
	rng: Random
)
	local function hasFloor(gx: number, gz: number): boolean
		return floorGrid[`{gx}_{gz}`] ~= nil
	end

	-- Helper: Check if a wall piece is blocking the entrance or exit opening of a staircase
	local function isBlockingStairOpening(pos: Vector3, normal: Vector3): boolean
		for _, stair in ipairs(stairList) do
			local stairPos = stair.cframe.Position
			local stairDir = (stair.cframe * CFrame.new(0, 0, -1)).Position - stairPos
			local dirNorm = Vector3.new(stairDir.X, 0, stairDir.Z).Unit

			-- Wall normal parallel to the stair length direction means it cuts across the walking path
			local dot = math.abs(normal.X * dirNorm.X + normal.Z * dirNorm.Z)
			if dot > 0.5 then
				local dx = pos.X - stairPos.X
				local dz = pos.Z - stairPos.Z
				if math.sqrt(dx * dx + dz * dz) < 24 then
					return true
				end
			end
		end
		return false
	end

	local function isNearStair(pos: Vector3, maxDist: number): boolean
		for _, stair in ipairs(stairList) do
			local stairPos = stair.cframe.Position
			local dx = pos.X - stairPos.X
			local dz = pos.Z - stairPos.Z
			if math.sqrt(dx * dx + dz * dz) < maxDist then
				return true
			end
		end
		return false
	end

	-- Helper: Get wallY for a given grid cell (uses cell's tier-based wallY)
	local function getWallY(gx: number, gz: number): number
		local cell = floorGrid[`{gx}_{gz}`]
		if cell then
			return cell.wallY or WALL_Y_OFFSET
		end
		return WALL_Y_OFFSET
	end

	-- 1. Spawn Pure Gate Models at Corridor Entrances (NO pillars in gates)
	local gatePositions: { Vector3 } = {}
	for _, door in ipairs(doorwayList) do
		-- Use the door's own Y from the corridor carver (already tier-aware)
		local doorPosWorld = door.position
		table.insert(gatePositions, doorPosWorld)

		local gateTemplate = pickRandom(assets.gates, rng)
		if gateTemplate then
			local gateCF = CFrame.new(doorPosWorld) * CFrame.Angles(0, math.rad(door.rotY), 0)
			spawnInstance(gateTemplate, gateCF, wallsFolder)
		end
	end

	local function isNearGate(pos: Vector3, maxDist: number): boolean
		for _, gPos in ipairs(gatePositions) do
			-- Compare only XZ distance for multi-floor (ignore Y difference)
			local dx = pos.X - gPos.X
			local dz = pos.Z - gPos.Z
			if math.sqrt(dx * dx + dz * dz) < maxDist then
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

	-- 3. Aggregate consecutive 12-stud edge tiles into continuous straight segments (per-tier wallY)
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
				-- Only merge consecutive tiles that share the same tier wallY
				local segWallY = getWallY(startX, gz)
				while i + 1 <= #gxList and gxList[i + 1] == endX + 1 and getWallY(gxList[i + 1], gz) == segWallY do
					i += 1
					endX = gxList[i]
				end

				local p1 = Vector3.new((startX - 0.5) * FLOOR_SIZE, segWallY, (gz + zOffset) * FLOOR_SIZE)
				local p2 = Vector3.new((endX + 0.5) * FLOOR_SIZE, segWallY, (gz + zOffset) * FLOOR_SIZE)

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
				-- Only merge consecutive tiles that share the same tier wallY
				local segWallY = getWallY(gx, startZ)
				while i + 1 <= #gzList and gzList[i + 1] == endZ + 1 and getWallY(gx, gzList[i + 1]) == segWallY do
					i += 1
					endZ = gzList[i]
				end

				local p1 = Vector3.new((gx + xOffset) * FLOOR_SIZE, segWallY, (startZ - 0.5) * FLOOR_SIZE)
				local p2 = Vector3.new((gx + xOffset) * FLOOR_SIZE, segWallY, (endZ + 0.5) * FLOOR_SIZE)

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

	-- 4. Spawn Corner Pillars ONLY at room corners (strictly NO pillars in corridors/hallways, near gates, or near stairs)
	for _, cornerPos in pairs(corners) do
		if not isNearGate(cornerPos, 16) and not isCorridorArea(cornerPos) and not isNearStair(cornerPos, 18) then
			local pillarTemplate = pickRandom(assets.pillars, rng)
			if pillarTemplate then
				local pillarCF = CFrame.new(cornerPos)
				spawnInstance(pillarTemplate, pillarCF, wallsFolder)
			end
		end
	end

	-- 5. Tile 17-stud Wall Pieces end-to-end along each segment with zero gaps (filtering out walls across stair openings)
	for _, seg in ipairs(segments) do
		local vec = seg.p2 - seg.p1
		local length = vec.Magnitude
		local tangent = vec.Unit

		local numWalls = math.max(1, math.ceil(length / WALL_PIECE_LEN))
		local step = length / numWalls

		for i = 1, numWalls do
			local wallCenter = seg.p1 + tangent * ((i - 0.5) * step)
			if not isNearGate(wallCenter, 12) and not isBlockingStairOpening(wallCenter, seg.normal) then
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

		-- 1. Rubble: Generously placed along wall perimeters and in all room corners (raised +3 studs)
		if #assets.rubble > 0 then
			local rubbleClusters = rng:NextInteger(3, 6)
			for _ = 1, rubbleClusters do
				local side = rng:NextInteger(1, 4)
				local rx = (side == 1 and minX) or (side == 2 and maxX) or rng:NextInteger(minX, maxX)
				local rz = (side == 3 and minZ) or (side == 4 and maxZ) or rng:NextInteger(minZ, maxZ)
				local rubPos = Vector3.new(rx * FLOOR_SIZE, room.floorY + 3.2, rz * FLOOR_SIZE)
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
				local bPos = Vector3.new(bx * FLOOR_SIZE, room.floorY + 0.2, bz * FLOOR_SIZE)
				local barTemplate = pickRandom(assets.barriers, rng)
				if barTemplate then
					local cf = CFrame.new(bPos) * CFrame.Angles(0, math.rad(rng:NextInteger(0, 3) * 90), 0)
					spawnInstance(barTemplate, cf, propsFolder)
				end
			end
		end

		-- 3. Cosmetics: Exactly 1 per room, placed near a wall facing opposite of the wall (into the room), raised by +6.2 studs (+3 studs higher)
		if #assets.cosmetics > 0 then
			local cosTemplate = pickRandom(assets.cosmetics, rng)
			if cosTemplate then
				local wallSide = rng:NextInteger(1, 4)
				local offsetFromWall = 2.0 -- 2 studs inward from wall edge
				local cosPos: Vector3
				local rotY: number

				if wallSide == 1 then
					-- North wall (minZ): placed near North wall, facing South (+Z into room)
					local rx = rng:NextInteger(minX + 1, maxX - 1)
					cosPos = Vector3.new(rx * FLOOR_SIZE, room.floorY + 6.2, (minZ * FLOOR_SIZE) + offsetFromWall)
					rotY = 180
				elseif wallSide == 2 then
					-- South wall (maxZ): placed near South wall, facing North (-Z into room)
					local rx = rng:NextInteger(minX + 1, maxX - 1)
					cosPos = Vector3.new(rx * FLOOR_SIZE, room.floorY + 6.2, (maxZ * FLOOR_SIZE) - offsetFromWall)
					rotY = 0
				elseif wallSide == 3 then
					-- West wall (minX): placed near West wall, facing East (+X into room)
					local rz = rng:NextInteger(minZ + 1, maxZ - 1)
					cosPos = Vector3.new((minX * FLOOR_SIZE) + offsetFromWall, room.floorY + 6.2, rz * FLOOR_SIZE)
					rotY = -90
				else
					-- East wall (maxX): placed near East wall, facing West (-X into room)
					local rz = rng:NextInteger(minZ + 1, maxZ - 1)
					cosPos = Vector3.new((maxX * FLOOR_SIZE) - offsetFromWall, room.floorY + 6.2, rz * FLOOR_SIZE)
					rotY = 90
				end

				local cf = CFrame.new(cosPos) * CFrame.Angles(0, math.rad(rotY), 0)
				spawnInstance(cosTemplate, cf, propsFolder)
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
	local rooms, floorGrid, doorwayList, stairList = buildDungeonGraph(rng, cfg)
	local startRoom = rooms[1]
	local bossRoom = rooms[#rooms]

	cachedSpawnCFrame = CFrame.new(startRoom.centerWorld + Vector3.new(0, 3, 0))
	cachedBossCFrame  = CFrame.new(bossRoom.centerWorld + Vector3.new(0, 3, 0))

	-- 2. Floor Placement (Exact 12x12 Snapping at FLOOR_Y_OFFSET = 4 with Center Pieces)
	local centerPieceGrid: { [string]: boolean } = {}
	for _, room in ipairs(rooms) do
		local centerGX = room.gx + math.floor((room.w - 1) / 2)
		local centerGZ = room.gz + math.floor((room.d - 1) / 2)
		local patternChoice = rng:NextInteger(1, 4)

		if patternChoice == 1 then
			-- 1 piece in center
			centerPieceGrid[`{centerGX}_{centerGZ}`] = true
		elseif patternChoice == 2 and room.w >= 4 and room.d >= 4 then
			-- 2x2 block (4 pieces) in center
			for dx = 0, 1 do
				for dz = 0, 1 do
					centerPieceGrid[`{centerGX + dx}_{centerGZ + dz}`] = true
				end
			end
		elseif patternChoice == 3 and room.w >= 6 and room.d >= 6 then
			-- 4x4 block (16 pieces) in center
			local startX = centerGX - 1
			local startZ = centerGZ - 1
			for dx = 0, 3 do
				for dz = 0, 3 do
					centerPieceGrid[`{startX + dx}_{startZ + dz}`] = true
				end
			end
		else
			-- Circle / Ring pattern around center
			local cxFloat = room.gx + (room.w / 2) - 0.5
			local czFloat = room.gz + (room.d / 2) - 0.5
			local radius = (math.min(room.w, room.d) >= 6) and 1.8 or 1.2
			for x = room.gx, room.gx + room.w - 1 do
				for z = room.gz, room.gz + room.d - 1 do
					local dist = math.sqrt((x - cxFloat) ^ 2 + (z - czFloat) ^ 2)
					if dist <= radius then
						centerPieceGrid[`{x}_{z}`] = true
					end
				end
			end
		end
	end

	for key, cellData in pairs(floorGrid) do
		local coords = string.split(key, "_")
		local gx = tonumber(coords[1]) :: number
		local gz = tonumber(coords[2]) :: number
		local cellFloorY = cellData.floorY or FLOOR_Y_OFFSET
		local pos = Vector3.new(gx * FLOOR_SIZE, cellFloorY, gz * FLOOR_SIZE)

		local isCenterPiece = (centerPieceGrid[key] == true)
		local floorTemplate: Instance? = nil

		if isCenterPiece and #assets.centerPieces > 0 then
			floorTemplate = pickRandom(assets.centerPieces, rng)
		else
			floorTemplate = pickRandom(assets.floors, rng)
		end

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
	constructPerimeterWallsAndPillars(rooms, floorGrid, doorwayList, stairList, wallsFolder, rng)

	-- 4. Inter-Floor Staircase Placement (connecting tiers)
	if #stairList > 0 then
		print(`[DungeonGenerator] Placing {#stairList} inter-floor staircase(s)...`)
		for idx, stairData in ipairs(stairList) do
			local stairTemplate = pickRandom(assets.stairs, rng)
			local heightDiff = stairData.upperFloorY - stairData.lowerFloorY
			print(`[DungeonGenerator]   Stair #{idx}: LowerY={stairData.lowerFloorY}, UpperY={stairData.upperFloorY}, HeightDiff={heightDiff}, Pos={stairData.cframe.Position}`)

			-- Shift stair 1 stud back along its orientation
			local adjustedCF = stairData.cframe * CFrame.new(0, 0, 1)
			local stairPos = adjustedCF.Position
			local _, stairRotY, _ = adjustedCF:ToEulerAnglesYXZ()

			if stairTemplate then
				-- Raise by +7 studs (half of 14-stud model height) so bottom sits on the floor
				local raisedCF = adjustedCF * CFrame.new(0, 7, 0)
				spawnInstance(stairTemplate, raisedCF, stairsFolder)
				print(`[DungeonGenerator]   → Placed stair asset: {stairTemplate.Name} (raised +7, pushed back 1 stud)`)
			else
				-- Fallback: procedural walkable ramp connecting lower to upper floor
				local rampLen = math.sqrt(STAIR_LENGTH * STAIR_LENGTH + heightDiff * heightDiff)
				local rampAngle = math.atan2(heightDiff, STAIR_LENGTH)

				-- Position ramp at midpoint between lower and upper floor
				local midY = (stairData.lowerFloorY + stairData.upperFloorY) / 2

				local ramp = Instance.new("Part")
				ramp.Name = "ProceduralStairRamp"
				ramp.Size = Vector3.new(STAIR_WIDTH, 2, rampLen)
				-- Position at stair XZ, midpoint Y, then rotate by corridor direction, then tilt by slope angle
				ramp.CFrame = CFrame.new(stairPos.X, midY, stairPos.Z)
					* CFrame.Angles(0, stairRotY, 0)
					* CFrame.Angles(-rampAngle, 0, 0)
				ramp.Anchored = true
				ramp.CanCollide = true
				ramp.Material = Enum.Material.Cobblestone
				ramp.Color = Color3.fromRGB(55, 55, 60)
				ramp.Parent = stairsFolder
				print(`[DungeonGenerator]   → Placed fallback ramp (no stair assets found). Size={ramp.Size}`)
			end
		end
	else
		print("[DungeonGenerator] No inter-floor stairs generated (all rooms may be on same tier).")
	end

	-- 5. Exit Staircase & Pitch-Black Abyss in the Boss Chamber
	local exitStairTemplate = pickRandom(assets.stairs, rng)
	local stairPos = Vector3.new(
		(bossRoom.gx + bossRoom.w / 2) * FLOOR_SIZE,
		bossRoom.floorY + 7, -- Raise by +7 (half of 14-stud model height)
		(bossRoom.gz + bossRoom.d - 1) * FLOOR_SIZE
	)
	local stairCF = CFrame.new(stairPos) * CFrame.Angles(0, 0, 0)
	cachedExitCFrame = stairCF

	if exitStairTemplate then
		spawnInstance(exitStairTemplate, stairCF, stairsFolder)
	end
	constructPitchBlackExit(stairCF, stairsFolder)

	-- 5. Interior Decorating (Abundant Corner/Perimeter Rubble, Barriers, Cosmetics)
	decorateRooms(rooms, propsFolder, rng)

	-- Debug: Log each room's tier and elevation
	print("[DungeonGenerator] Room Layout Summary:")
	for _, rm in ipairs(rooms) do
		print(`  Room #{rm.id} ({rm.roomType}): Tier={rm.tier}, FloorY={rm.floorY}, WallY={rm.wallY}, Grid=({rm.gx},{rm.gz}), Size={rm.w}x{rm.d}`)
	end

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
