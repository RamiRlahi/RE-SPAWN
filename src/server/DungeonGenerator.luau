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
local SpecialRooms      = require(script.Parent:WaitForChild("SpecialRooms"))
local Hazards           = require(script.Parent:WaitForChild("Hazards"))
local AtmosphereManager = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AtmosphereManager"))
local MapData           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapData"))
local RunScope          = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
local Network           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))

local DungeonGenerator = {}

-- ── Constants ────────────────────────────────────────────────────────────────

local FLOOR_SIZE        = 12    -- Floor tile grid unit (12x12 studs)
local WALL_PIECE_LEN    = 17    -- Wall piece standard dimension (17x17 studs)
local FLOOR_COOL        = Color3.fromRGB(122, 132, 160) -- the cool stone some floor tiles lean toward
local CORRIDOR_WIDTH    = 2     -- 2 tiles wide = 24 studs for great action combat
local FLOOR_Y_OFFSET    = 4     -- Tier 0 floor tile elevation (4 studs)
local WALL_Y_OFFSET     = 11    -- Tier 0 wall elevation (11 studs)

-- Stair & Multi-Floor Dimensions (13 studs vertical rise, 21 studs length, 11 studs width)
local STAIR_WIDTH       = 11    -- Stair model width (studs)
local STAIR_HEIGHT      = 13    -- Vertical height per floor tier (13 studs rise)
local STAIR_LENGTH      = 21    -- Horizontal stair length (21 studs)

-- ── Types ────────────────────────────────────────────────────────────────────

export type RoomType = "Start" | "Combat" | "Rest" | "Treasure" | "Shop" | "Gamble" | "Elite" | "Event" | "Boss" | "Cursed"

export type DungeonConfig = {
	seed: number?,
	totalRooms: number?,
	minRoomTiles: number?,    -- in 12-stud floor tiles (e.g. 9 = 108 studs)
	maxRoomTiles: number?,    -- in 12-stud floor tiles (e.g. 13 = 156 studs)
	branchProbability: number?,
	level: number?,           -- which level of the run this is (1 = a fresh run; picks the boss)
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

-- Every party's run has its own dungeon (RunManager), built in its own slot:
-- the whole layout shifted SLOT_TILES grid cells along +X per slot, so runs
-- never overlap. Its folder, spawn / boss / exit, minimap and level live here.
type RunDungeon = {
	folder: Folder?,
	spawn: CFrame,
	boss: CFrame,
	exit: CFrame,
	payload: any,
	seed: number,
	level: number,
	slot: number,
	mapId: string,
	transitioning: boolean, -- one level change at a time
}
local SLOT_TILES = 170 -- 2040 studs between runs (a dungeon spans ~80 cells)
local dungeons: { [string]: RunDungeon } = {}
local building: string? = nil -- the run being generated now (one build at a time)
local buildLock = false

-- (the run the generator is building: SpecialRooms / Hazards tag what they make)
function DungeonGenerator.BuildingRun(): string?
	return building
end

-- Asset Cache (the default set; a map with its own assets swaps in a merged
-- set while its dungeon is built: see mapAssetSet)
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

-- ── A map's own asset set ─────────────────────────────────────────────────────
-- A map can bring its own pieces (MapData.assets: a folder in ReplicatedStorage,
-- e.g. "map:crypt assets"): models named floor*, center*, wall*, pillar*,
-- gate*/arch*, stair*, rubble*, barrier*, anything else a cosmetic (loose or in
-- subfolders). They can be any size and built facing any way: each one is
-- measured (its bounding box) and its pivot reset to what the generator places
-- by: floors with their top at the standard floor top, walls / pillars / gates
-- standing on the floor, a wall's length along its X. Walls are tiled by their
-- own measured length. Pieces the map doesn't have come from the default set
-- (stairs, rubble, barriers; not its walls, floors, pillars, gates or cosmetics).
local FLOOR_TOP = FLOOR_Y_OFFSET + 0.5        -- where the standard floor's top is
local WALL_BASE = WALL_Y_OFFSET - FLOOR_Y_OFFSET -- a wall's pivot sits this far above the floor

type AssetSet = typeof(assets) & { wallLen: number, ownArt: boolean, bigPillars: boolean }
local mapSets: { [string]: AssetSet } = {}
local defaultAssets = assets
local wallPieceLen = WALL_PIECE_LEN

local function normalize(template: Instance, kind: string): Instance?
	local model: Model
	if template:IsA("Model") then
		model = template:Clone()
	elseif template:IsA("BasePart") then
		model = Instance.new("Model")
		model.Name = template.Name
		local p = template:Clone()
		p.Parent = model
	else
		return nil
	end
	-- (measured along the world's axes, whatever its saved pivot or PrimaryPart)
	model.PrimaryPart = nil
	model.WorldPivot = CFrame.new(model:GetPivot().Position)
	local box, size = model:GetBoundingBox()
	-- (lying along Z: turn it so its length runs along X)
	local turn = if kind == "wall" and size.Z > size.X then CFrame.Angles(0, math.rad(90), 0) else CFrame.identity
	local c = box.Position
	local pivotY = if kind == "floor" then c.Y + size.Y / 2 - 0.5 else c.Y - size.Y / 2 + WALL_BASE
	model.WorldPivot = CFrame.new(c.X, pivotY, c.Z) * turn
	return model
end

local function kindOfAsset(name: string): string
	local n = string.lower(name)
	if string.find(n, "floor") or string.find(n, "center") then return if string.find(n, "center") then "center" else "floor" end
	if string.find(n, "pillar") then return "pillar" end
	if string.find(n, "gate") or string.find(n, "arch") then return "gate" end
	if string.find(n, "wall") then return "wall" end
	if string.find(n, "stair") then return "stair" end
	if string.find(n, "rubble") then return "rubble" end
	if string.find(n, "barrier") then return "barrier" end
	return "cosmetic"
end

local function mapAssetSet(folderName: string): AssetSet?
	if mapSets[folderName] then return mapSets[folderName] end
	local root = ReplicatedStorage:FindFirstChild(folderName)
	if not root then
		warn(`[DungeonGenerator] map assets '{folderName}' not found: the default set is used`)
		return nil
	end
	local set: any = {
		floors = {}, centerPieces = {}, walls = {}, pillars = {}, gates = {},
		barriers = {}, rubble = {}, stairs = {}, cosmetics = {},
		wallLen = WALL_PIECE_LEN, ownArt = true, bigPillars = false,
	}
	local longest = 0
	local function scan(parent: Instance, folderKind: string?)
		for _, item in ipairs(parent:GetChildren()) do
			if item:IsA("Folder") then
				scan(item, kindOfAsset(item.Name))
			elseif item:IsA("Model") or item:IsA("BasePart") then
				local k = kindOfAsset(item.Name)
				if k == "cosmetic" and folderKind then k = folderKind end
				local list = ({
					floor = set.floors, center = set.centerPieces, wall = set.walls, pillar = set.pillars, gate = set.gates,
					stair = set.stairs, rubble = set.rubble, barrier = set.barriers, cosmetic = set.cosmetics,
				})[k]
				-- (stairs, rubble, barriers keep their own pivots: the generator places them like the defaults)
				local piece = if k == "floor" or k == "center" then normalize(item, "floor")
					elseif k == "wall" or k == "pillar" or k == "gate" then normalize(item, if k == "wall" then "wall" else "post")
					else item
				if piece and list then
					table.insert(list, piece)
					if k == "wall" then
						local _, size = (piece :: Model):GetBoundingBox()
						longest = math.max(longest, math.max(size.X, size.Z))
					elseif k == "pillar" then
						local _, size = (piece :: Model):GetBoundingBox()
						if math.max(size.X, size.Z) > 6 then set.bigPillars = true end
					end
				end
			end
		end
	end
	scan(root, nil)
	if longest > 0 then set.wallLen = longest end
	-- (what the map lacks: the default stairs, rubble and barriers)
	for _, k in ipairs({ "stairs", "rubble", "barriers" }) do
		if #set[k] == 0 then set[k] = assets[k] end
	end
	if #set.floors == 0 then set.floors = assets.floors end
	if #set.walls == 0 then set.walls = assets.walls; set.wallLen = WALL_PIECE_LEN end
	print(`[DungeonGenerator] Map assets '{folderName}': {#set.floors} floors, {#set.centerPieces} centre pieces, {#set.walls} walls ({math.floor(set.wallLen)} long), {#set.pillars} pillars, {#set.gates} gates, {#set.cosmetics} cosmetics`)
	mapSets[folderName] = set
	return set
end

-- ── Geometry & Cloner Helpers ────────────────────────────────────────────────

-- (performance: nothing in the game listens for touches on the dungeon, so
-- its parts don't generate them; `noShadow`: floors and small props cast no
-- shadow, which keeps the shadow pass to the walls and big pieces)
local function spawnInstance(template: Instance, cf: CFrame, parent: Instance, noShadow: boolean?): Instance
	local clone = template:Clone()
	local function setup(part: BasePart)
		part.Anchored = true
		part.CanCollide = true
		part.CanTouch = false
		if noShadow then part.CastShadow = false end
	end
	if clone:IsA("Model") then
		clone:PivotTo(cf)
		for _, desc in ipairs(clone:GetDescendants()) do
			if desc:IsA("BasePart") then setup(desc) end
		end
	elseif clone:IsA("BasePart") then
		clone.CFrame = cf
		setup(clone)
	end
	clone.Parent = parent
	return clone
end

local wallFeature: (string, Instance, CFrame, number, Vector3, Vector3, Instance, Random) -> ()

local function pickRandom(list: { Instance }, rng: Random): Instance?
	if #list == 0 then return nil end
	return list[rng:NextInteger(1, #list)]
end

-- ── 1. Graph & Layout Generation (Deterministic Critical Path + Branches) ────

local function buildDungeonGraph(rng: Random, config: DungeonConfig): ({ RoomData }, { [string]: CellData }, { DoorwayData }, { StairData })
	-- Large, readable arenas make the dungeon feel like a place to explore rather
	-- than a chain of small fighting boxes. The start is an intentionally larger hub.
	local totalRooms = config.totalRooms or rng:NextInteger(16, 20)
	local minTiles = config.minRoomTiles or 9
	local maxTiles = config.maxRoomTiles or 13
	local branchProb = config.branchProbability or 0.8

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
	local startW = rng:NextInteger(minTiles + 2, maxTiles + 2)
	local startD = rng:NextInteger(minTiles + 2, maxTiles + 2)
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
	local criticalLength = math.max(6, math.floor(totalRooms * 0.55))
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

	-- 3. Spawn hub spokes. Every run begins with at least three viable directions:
	-- the critical route plus two guaranteed side routes. This removes the old
	-- single-door spawn experience while still allowing a clear route to the boss.
	local nextId = #rooms + 1
	local spawnSpokesPlaced = 0
	local spawnDirections = { 0, 1, 2, 3 }
	for i = #spawnDirections, 2, -1 do
		local j = rng:NextInteger(1, i)
		spawnDirections[i], spawnDirections[j] = spawnDirections[j], spawnDirections[i]
	end

	for _, dir in ipairs(spawnDirections) do
		if spawnSpokesPlaced >= 2 or nextId > totalRooms then break end

		local spokeW = rng:NextInteger(minTiles, maxTiles)
		local spokeD = rng:NextInteger(minTiles, maxTiles)
		local corrLen = rng:NextInteger(4, 6)
		local candidateGX = startRoom.gx
		local candidateGZ = startRoom.gz

		if dir == 0 then candidateGZ = startRoom.gz - corrLen - spokeD
		elseif dir == 1 then candidateGZ = startRoom.gz + startRoom.d + corrLen
		elseif dir == 2 then candidateGX = startRoom.gx + startRoom.w + corrLen
		else candidateGX = startRoom.gx - corrLen - spokeW end

		if not doesRoomOverlap(candidateGX, candidateGZ, spokeW, spokeD, 2) then
			carveCorridor(startRoom, 0, FLOOR_Y_OFFSET, WALL_Y_OFFSET, candidateGX, candidateGZ, spokeW, spokeD, dir, corrLen)
			local spokeRoom: RoomData = {
				id = nextId,
				roomType = "Combat",
				tier = 0,
				floorY = FLOOR_Y_OFFSET,
				wallY = WALL_Y_OFFSET,
				gx = candidateGX,
				gz = candidateGZ,
				w = spokeW,
				d = spokeD,
				centerWorld = Vector3.new((candidateGX + spokeW / 2) * FLOOR_SIZE, FLOOR_Y_OFFSET, (candidateGZ + spokeD / 2) * FLOOR_SIZE),
				connections = { startRoom.id },
			}
			table.insert(startRoom.connections, nextId)
			table.insert(rooms, spokeRoom)
			for x = candidateGX, candidateGX + spokeW - 1 do
				for z = candidateGZ, candidateGZ + spokeD - 1 do
					markFloor(x, z, FLOOR_Y_OFFSET, WALL_Y_OFFSET, 0)
				end
			end
			nextId += 1
			spawnSpokesPlaced += 1
		end
	end

	-- 4. Side Branches across Multi-Floor Tiers
	local branchTypes: { RoomType } = { "Rest", "Treasure", "Shop", "Gamble", "Elite", "Event" }
	-- (a cursed altar on some floors: a gamble with your health)
	if rng:NextNumber() < 0.6 then table.insert(branchTypes, "Cursed") end

	for _, mainRoom in ipairs(rooms) do
		if nextId > totalRooms then break end
		if mainRoom.roomType == "Combat" and rng:NextNumber() < branchProb then
			local bType: RoomType = "Combat"
			if #branchTypes > 0 then
				bType = table.remove(branchTypes, rng:NextInteger(1, #branchTypes)) :: RoomType
			end
			local bW = rng:NextInteger(minTiles, maxTiles)
			local bD = rng:NextInteger(minTiles, maxTiles)

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

-- ── Wall features: arched alcoves and broken stretches ───────────────────────
local WALL_STONE = Color3.fromRGB(70, 68, 74)

local function stoneBlock(folder: Instance, size: Vector3, cf: CFrame, rng: Random, wedge: boolean?): BasePart
	local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Anchored = true
	p.Material = Enum.Material.Slate
	p.Color = WALL_STONE:Lerp(Color3.fromRGB(40, 44, 58), rng:NextNumber(0, 0.5))
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	p.CFrame = cf
	p.Parent = folder
	return p
end

-- One wall piece's place along a perimeter wall, built as an `alcove` (the
-- piece set back, side walls, pillars and an arch over the opening) or as a
-- `broken` stretch (the piece crumbled low with jagged stones along its top,
-- the deeper wall standing behind it, fallen blocks on the floor). `normal`
-- points out of the room.
wallFeature = function(kind: string, template: Instance, wallCF: CFrame, step: number, normal: Vector3, tangent: Vector3, folder: Instance, rng: Random)
	local clone = spawnInstance(template, wallCF, folder)
	local bcf: CFrame, bsize: Vector3
	if clone:IsA("Model") then
		bcf, bsize = clone:GetBoundingBox()
	else
		bcf, bsize = (clone :: BasePart).CFrame, (clone :: BasePart).Size
	end
	local H = bsize.Y
	local T = math.max(math.min(bsize.X, bsize.Z), 1)
	local baseY = bcf.Position.Y - H / 2
	local topY = baseY + H
	local floorY = wallCF.Position.Y - (WALL_Y_OFFSET - FLOOR_Y_OFFSET) + 0.5
	local c = Vector3.new(wallCF.Position.X, 0, wallCF.Position.Z)
	local function at(along: number, out: number, y: number): Vector3
		return c + tangent * along + normal * out + Vector3.new(0, y, 0)
	end
	local function flat(pos: Vector3): CFrame
		return CFrame.fromMatrix(pos, tangent, Vector3.yAxis)
	end
	local function move(by: Vector3)
		if clone:IsA("Model") then
			clone:PivotTo(clone:GetPivot() + by)
		else
			(clone :: BasePart).CFrame += by
		end
	end
	-- the recess's side walls, from the wall line back to `depth`
	local function sides(depth: number, height: number)
		for _, sgn in ipairs({ -1, 1 }) do
			stoneBlock(folder, Vector3.new(1.4, height, depth + T),
				flat(at(sgn * (step / 2 - 0.7), depth / 2, baseY + height / 2)), rng)
		end
	end
	local function pillarsAt(out: number)
		if #assets.pillars == 0 then return end
		for _, sgn in ipairs({ -1, 1 }) do
			local t = pickRandom(assets.pillars, rng)
			if t then
				spawnInstance(t, CFrame.new(at(sgn * step / 2, out, wallCF.Position.Y)) * wallCF.Rotation, folder)
			end
		end
	end

	if kind == "alcove" then
		local depth = 4.5
		move(normal * depth)
		sides(depth, H)
		pillarsAt(-0.4)
		-- the arch: a lintel across the top and a curved springer in each corner
		local archH = H * 0.3
		local lintel = archH * 0.4
		stoneBlock(folder, Vector3.new(step, lintel, T + 0.8), flat(at(0, 0, topY - lintel / 2)), rng)
		for _, sgn in ipairs({ -1, 1 }) do
			local z = tangent * sgn
			local x = Vector3.yAxis:Cross(z)
			local len = step * 0.32
			local pos = at(sgn * (step / 2 - 1.4 - len / 2), 0, topY - lintel - (archH - lintel) / 2)
			stoneBlock(folder, Vector3.new(T + 0.6, archH - lintel, len),
				CFrame.fromMatrix(pos, x, Vector3.yAxis, z) * CFrame.Angles(0, 0, math.pi), rng, true)
		end
	else
		-- crumbled low...
		local sink = H * rng:NextNumber(0.45, 0.6)
		move(Vector3.new(0, -sink, 0))
		local brokenTop = topY - sink
		-- ...jagged stones left standing along the break
		local n = 6
		for k = 1, n do
			local along = -step / 2 + (k - 0.5) * step / n + rng:NextNumber(-0.4, 0.4)
			local h = rng:NextNumber(0.4, 3.2)
			stoneBlock(folder, Vector3.new(step / n + 0.5, h, T * rng:NextNumber(0.7, 1)),
				flat(at(along, 0, brokenTop + h / 2 - 0.4)) * CFrame.Angles(rng:NextNumber(-0.1, 0.1), 0, rng:NextNumber(-0.18, 0.18)), rng)
		end
		-- ...the deeper wall standing behind it
		local back = 7
		spawnInstance(template, wallCF + normal * back, folder)
		sides(back, H)
		pillarsAt(-0.4)
		-- ...and fallen blocks scattered on the floor in front
		for _ = 1, rng:NextInteger(3, 5) do
			local sz = rng:NextNumber(1, 2.4)
			stoneBlock(folder, Vector3.new(sz * rng:NextNumber(1, 1.6), sz * 0.7, sz),
				CFrame.new(at(rng:NextNumber(-step / 2 + 2, step / 2 - 2), -rng:NextNumber(1.2, 4), floorY + sz * 0.3))
					* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)), rng)
		end
	end
end

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
	local windowWalls: { { cf: CFrame, openings: any } } = {}
	for _, seg in ipairs(segments) do
		local vec = seg.p2 - seg.p1
		local length = vec.Magnitude
		local tangent = vec.Unit

		local ownArt = (assets :: any).ownArt == true
		-- (a stretch shorter than the map's own wall: the standard short pieces,
		-- or the long one would poke out across the doorways at its ends)
		local short = ownArt and length < wallPieceLen
		local pieceLen = if short then WALL_PIECE_LEN else wallPieceLen
		local wallList = if short then defaultAssets.walls else assets.walls
		local numWalls = math.max(1, math.ceil(length / pieceLen))
		local step = length / numWalls
		-- (a map's own long walls: the first flush with the segment's start, the
		-- last with its end, the rest spread between, so none pokes past the
		-- segment into a doorway; consecutive ones overlap a little)
		local flush = ownArt and not short and numWalls > 1

		local lastVaried = -10
		for i = 1, numWalls do
			local wallCenter = if flush
				then seg.p1 + tangent * (wallPieceLen / 2 + (i - 1) * (length - wallPieceLen) / (numWalls - 1))
				else seg.p1 + tangent * ((i - 0.5) * step)
			-- (overlapping pieces: every other one a hair further out, no flicker)
			if flush and i % 2 == 0 then wallCenter += seg.normal * 0.06 end
			if not isNearGate(wallCenter, 12) and not isBlockingStairOpening(wallCenter, seg.normal) then
				local wallCF = CFrame.new(wallCenter) * CFrame.Angles(0, math.rad(seg.rotY), 0)
				local wallPiece = pickRandom(wallList, rng)
				-- Architectural variation instead of one long flat wall: an
				-- arched alcove set back into it, or a broken stretch with the
				-- deeper wall behind showing, and pilasters at the joints.
				local plain = not ownArt and wallPiece ~= nil and AtmosphereManager.WindowOpenings(wallPiece.Name) == nil
					and numWalls >= 3 and i > 1 and i < numWalls and i - lastVaried > 1
					and not isNearGate(wallCenter, 22) and not isNearStair(wallCenter, 26)
				local roll = rng:NextNumber()
				if wallPiece and plain and roll < 0.2 then
					lastVaried = i
					wallFeature("alcove", wallPiece, wallCF, step, seg.normal, tangent, wallsFolder, rng)
				elseif wallPiece and plain and roll < 0.34 then
					lastVaried = i
					wallFeature("broken", wallPiece, wallCF, step, seg.normal, tangent, wallsFolder, rng)
				elseif wallPiece then
					spawnInstance(wallPiece, wallCF, wallsFolder)
					-- a pilaster at every other joint along a long wall
					if i < numWalls and i % 2 == 0 and i - lastVaried > 1 and #assets.pillars > 0 and not (assets :: any).bigPillars
						and not isNearGate(wallCenter + tangent * step * 0.5, 16) and not isNearStair(wallCenter, 22) then
						local at = wallCenter + tangent * (step * 0.5) - seg.normal * 0.6
						spawnInstance(pickRandom(assets.pillars, rng) :: Instance, CFrame.new(at) * CFrame.Angles(0, math.rad(seg.rotY), 0), wallsFolder)
					end
				end
				if wallPiece then
					-- Window walls let the daylight in (local +Z faces out of the room).
					local openings = AtmosphereManager.WindowOpenings(wallPiece.Name)
					if openings then
						table.insert(windowWalls, { cf = wallCF, openings = openings })
					end
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

	-- 6. Daylight through every window, once all the walls are up (each shaft
	-- is measured to where it lands on the floor).
	for _, w in ipairs(windowWalls) do
		AtmosphereManager.PlaceWindowLight(w.cf, w.openings, wallsFolder)
	end
end

-- ── 3. Pitch-Black Abyss Exit Construction ───────────────────────────────────

-- Every third floor is a choice: beside the Abyss Gate (down, deeper) stands
-- an Extraction portal (out, with everything you carry). Standing in a portal
-- is choosing it; the party goes only when every living player stands in the
-- same one (the dead come back on the next floor). A count hangs over each
-- portal, and each player's screen shows it too (FloorPortal).
--   Descending past an extraction floor wakes the dungeon's Corruption
--   (Corruption.luau); when it collapses, an escape portal opens where the
--   floor began.
local GO_AFTER = 1.2      -- everyone in the same portal this long, then go (step out and it's off)
local EXTRACT_EVERY = 3   -- floors 3, 6, 9… offer extraction
DungeonGenerator.EXTRACT_EVERY = EXTRACT_EVERY

-- Set by Corruption.luau: what extracting does, and what going down does.
DungeonGenerator.Hooks = {
	extract = nil :: ((string, { Player }) -> ())?,
	descended = nil :: ((string, number, boolean) -> ())?, -- (runId, the floor left, it offered extraction)
}

type Portal = { part: BasePart, kind: string, text: TextLabel, bb: BillboardGui }

local function countBoard(part: BasePart): (BillboardGui, TextLabel)
	local bb = Instance.new("BillboardGui")
	bb.Name = "ReadyCount"
	bb.Size = UDim2.fromScale(16, 4)
	bb.StudsOffsetWorldSpace = Vector3.new(0, part.Size.Y / 2 + 4, 0)
	bb.MaxDistance = 160
	bb.LightInfluence = 0
	bb.Enabled = false
	bb.Parent = part
	local text = Instance.new("TextLabel")
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.Antique
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(240, 214, 160)
	text.TextStrokeTransparency = 0.2
	text.Parent = bb
	return bb, text
end

local function watchPortals(runId: string, portals: { Portal }, extractFloor: boolean)
	local remote = Network.GetRemoteEvent(Network.Remotes.FloorPortal)
	local function inside(part: BasePart, root: BasePart): boolean
		local rel = part.CFrame:PointToObjectSpace(root.Position)
		local h = part.Size / 2 + Vector3.new(1.5, 2, 1.5)
		return math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z
	end
	local function send(to: { Player }, state: any)
		for _, p in ipairs(to) do
			if p.Parent then remote:FireClient(p, state) end
		end
	end
	local function alivePortals(): boolean
		for _, pt in ipairs(portals) do
			if pt.part.Parent then return true end
		end
		return false
	end

	task.spawn(function()
		local lastKey = ""
		local agreedSince: number? = nil
		local agreedOn: string? = nil
		local members: { Player } = {}
		local level = (dungeons[runId] and dungeons[runId].level) or 1
		while alivePortals() do
			local d = dungeons[runId]
			if not d or d.level ~= level then break end
			table.clear(members)
			local counts: { [string]: number } = {}
			local readyIds, waiting = {}, {}
			local choice: { [Player]: string } = {}
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("RunId") ~= runId or p:GetAttribute("InLobby") ~= false then continue end
				table.insert(members, p)
				local char = p.Character
				local hum = char and char:FindFirstChildOfClass("Humanoid")
				local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
				local alive = hum ~= nil and hum.Health > 0 and root ~= nil
					and p:GetAttribute("IsDead") ~= true and p:GetAttribute("Spectating") ~= true
				if not alive then continue end
				for _, pt in ipairs(portals) do
					if pt.part.Parent and inside(pt.part, root :: BasePart) then
						choice[p] = pt.kind
						break
					end
				end
				if choice[p] then
					table.insert(readyIds, p.UserId)
					counts[choice[p]] = (counts[choice[p]] or 0) + 1
				else
					table.insert(waiting, p.DisplayName)
				end
			end
			local total = #readyIds + #waiting
			-- everyone living in one portal?
			local unanimous: string? = nil
			if total > 0 and #waiting == 0 and not d.transitioning then
				for kind, n in pairs(counts) do
					if n == total then unanimous = kind end
				end
			end
			if unanimous and unanimous == agreedOn then
				-- (still agreed)
			elseif unanimous then
				agreedOn, agreedSince = unanimous, os.clock()
			else
				agreedOn, agreedSince = nil, nil
			end
			local go = agreedSince ~= nil and os.clock() - (agreedSince :: number) >= GO_AFTER
			local key = `{table.concat(readyIds, ",")}|{table.concat(waiting, ",")}|{counts.descend or 0}|{counts.extract or 0}|{agreedOn or ""}`
			if key ~= lastKey or go then
				lastKey = key
				for _, pt in ipairs(portals) do
					local n = counts[pt.kind] or 0
					pt.bb.Enabled = #readyIds > 0
					pt.text.Text = if agreedOn == pt.kind then (if pt.kind == "extract" then "EXTRACTING..." else "DESCENDING...")
						else `{n} / {total} {if pt.kind == "extract" then "EXTRACT" else "DESCEND"}`
				end
				send(members, {
					ready = #readyIds, total = total, readyIds = readyIds, waiting = waiting,
					counts = counts, extractFloor = extractFloor, going = agreedOn,
					descending = agreedOn == "descend", extracting = agreedOn == "extract",
				})
			end
			if go and agreedOn then
				d.transitioning = true
				local everyone = table.clone(members)
				if agreedOn == "extract" then
					print(`[Roguelite] Run {runId}: the party extracts on floor {level}.`)
					local hook = DungeonGenerator.Hooks.extract
					if hook then task.spawn(hook, runId, everyone) end
					send(everyone, { ready = 0, total = 0, readyIds = {}, waiting = {}, counts = {} })
				else
					print(`[Roguelite] Run {runId}: everyone is in the abyss. Generating the next level...`)
					-- (every floor cleared is worth a drop each)
					pcall(function()
						local LootManager = require(script.Parent:WaitForChild("LootManager")) :: any
						for _, p in ipairs(everyone) do LootManager.Drop(p, "floor") end
					end)
					task.spawn(function()
						DungeonGenerator.NextLevel(runId)
						send(everyone, { ready = 0, total = 0, readyIds = {}, waiting = {}, counts = {} })
						local hook = DungeonGenerator.Hooks.descended
						if hook then hook(runId, level, extractFloor) end
					end)
				end
				break
			end
			task.wait(0.2)
		end
	end)
end

-- The Extraction portal: a standing ring of gold light over a glowing disc.
local function buildExtractPortal(cf: CFrame, parent: Instance): BasePart
	local GOLD = Color3.fromRGB(255, 205, 110)
	local model = Instance.new("Model")
	model.Name = "ExtractionPortal"
	model.Parent = parent
	local zone = Instance.new("Part")
	zone.Name = "ExtractZone"
	zone.Size = Vector3.new(12, 14, 8)
	zone.CFrame = cf * CFrame.new(0, 7, 0)
	zone.Anchored = true
	zone.CanCollide = false
	zone.CanQuery = false
	zone.CanTouch = false
	zone.Transparency = 1
	zone.Parent = model
	local function deco(props: { [string]: any }): BasePart
		local pt = Instance.new("Part")
		pt.Anchored = true
		pt.CanCollide = false
		pt.CanQuery = false
		pt.CanTouch = false
		pt.CastShadow = false
		pt.Material = Enum.Material.Neon
		for k, v in pairs(props) do (pt :: any)[k] = v end
		pt.Parent = model
		return pt
	end
	-- the ring of light, standing
	local n, r = 28, 5.5
	for i = 1, n do
		local a = i / n * math.pi * 2
		local p = cf * CFrame.new(math.cos(a) * r, 7 + math.sin(a) * r, 0)
		deco({ Size = Vector3.new(0.6, r * 2 * math.pi / n + 0.1, 0.6), CFrame = p * CFrame.Angles(0, 0, a), Color = GOLD })
	end
	-- the light inside it
	local veil = deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, r * 2 - 0.6, r * 2 - 0.6), CFrame = cf * CFrame.new(0, 7, 0) * CFrame.Angles(0, math.rad(90), 0),
		Color = Color3.fromRGB(255, 225, 160), Transparency = 0.72 })
	deco({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 12, 12), CFrame = cf * CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD, Transparency = 0.5 })
	local up = Instance.new("ParticleEmitter")
	up.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	up.Color = ColorSequence.new(GOLD)
	up.LightEmission = 1
	up.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	up.Lifetime = NumberRange.new(1, 2)
	up.Speed = NumberRange.new(2, 5)
	up.SpreadAngle = Vector2.new(25, 25)
	up.EmissionDirection = Enum.NormalId.Top
	up.Rate = 25
	up.Parent = veil
	local sign = Instance.new("BillboardGui")
	sign.Size = UDim2.fromScale(12, 2.2)
	sign.StudsOffsetWorldSpace = Vector3.new(0, 15.5, 0)
	sign.MaxDistance = 140
	sign.LightInfluence = 0
	sign.Parent = zone
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Antique
	t.TextScaled = true
	t.Text = "EXTRACT"
	t.TextColor3 = GOLD
	t.TextStrokeTransparency = 0.2
	t.Parent = sign
	return zone
end

local function constructPitchBlackExit(stairCF: CFrame, parentFolder: Folder, runId: string)
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

	local portals: { Portal } = {}
	local bb, text = countBoard(voidPortal)
	table.insert(portals, { part = voidPortal, kind = "descend", bb = bb, text = text })
	-- (the floor's level: every third one offers extraction)
	local d = dungeons[runId]
	local level = if d then d.level else 1
	local map = MapData.Get(RunScope.Get(runId, "MapId"))
	local every = if map and map.endless then 5 else EXTRACT_EVERY
	local extractFloor = level % every == 0
	if extractFloor then
		-- in front of the stairs, in the room (floor level: the stair's base)
		local base = stairCF * CFrame.new(0, -7, -16)
		local zone = buildExtractPortal(CFrame.new(base.Position) * stairCF.Rotation, exitModel)
		local ebb, etext = countBoard(zone)
		table.insert(portals, { part = zone, kind = "extract", bb = ebb, text = etext })
	end
	watchPortals(runId, portals, extractFloor)
end

-- The dungeon is collapsing (Corruption.luau): an escape portal where the
-- floor began. All living players in it: they extract.
function DungeonGenerator.OpenEscapePortal(runId: string)
	local d = dungeons[runId]
	if not d or not d.spawn then return end
	local holder = Instance.new("Folder")
	holder.Name = "EscapePortal"
	holder.Parent = d.folder
	local spawnPos = d.spawn.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars = {}
	for _, p in ipairs(Players:GetPlayers()) do if p.Character then table.insert(chars, p.Character) end end
	params.FilterDescendantsInstances = chars
	local hit = Workspace:Raycast(spawnPos + Vector3.new(6, 10, 0), Vector3.new(0, -40, 0), params)
	local floorPos = if hit then hit.Position else spawnPos - Vector3.new(0, 3, 0)
	local zone = buildExtractPortal(CFrame.new(floorPos) * d.spawn.Rotation, holder)
	local bb, text = countBoard(zone)
	watchPortals(runId, { { part = zone, kind = "extract", bb = bb, text = text } }, true)
	-- (gone with the level)
	task.spawn(function()
		local level = d.level
		while holder.Parent and dungeons[runId] and dungeons[runId].level == level do task.wait(0.5) end
		holder:Destroy()
	end)
end

-- ── 4. Special Room Gameplay + Rich Cosmetics ───────────────────────────────

-- Rest / Treasure / Shop / Gamble rooms are built and run by SpecialRooms.
-- A sign floating high over each special room (seen through the walls,
-- from down the corridors): what's in there, so the party picks its path.
local ROOM_SIGNS: { [string]: { text: string, sub: string, color: Color3 } } = {
	Elite = { text = "ELITE", sub = "a hard fight · relics and gear", color = Color3.fromRGB(200, 110, 255) },
	Treasure = { text = "TREASURE", sub = "chests (and traps)", color = Color3.fromRGB(255, 210, 90) },
	Shop = { text = "SHOP", sub = "spend your gold", color = Color3.fromRGB(120, 220, 140) },
	Rest = { text = "MOONWELL", sub = "rest and heal", color = Color3.fromRGB(150, 200, 255) },
	Gamble = { text = "GAMBLING DEN", sub = "risk your gold", color = Color3.fromRGB(255, 160, 80) },
	Cursed = { text = "CURSED ALTAR", sub = "pay in health · take a relic", color = Color3.fromRGB(170, 70, 230) },
}

local function roomSign(room: RoomData, parent: Instance)
	local def = ROOM_SIGNS[room.roomType]
	if not def then return end
	local anchor = Instance.new("Part")
	anchor.Name = "RoomSign"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one
	anchor.CFrame = CFrame.new(room.centerWorld + Vector3.new(0, 18, 0))
	anchor.Parent = parent
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 52)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 140
	bb.LightInfluence = 0
	bb.Parent = anchor
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.new(1, 0, 0, 30)
	t.Font = Enum.Font.Antique
	t.TextSize = 26
	t.TextColor3 = def.color
	t.TextStrokeTransparency = 0.2
	t.Text = def.text
	t.Parent = bb
	local s = Instance.new("TextLabel")
	s.BackgroundTransparency = 1
	s.Position = UDim2.fromOffset(0, 30)
	s.Size = UDim2.new(1, 0, 0, 18)
	s.Font = Enum.Font.GothamMedium
	s.TextSize = 13
	s.TextColor3 = Color3.fromRGB(235, 228, 215)
	s.TextStrokeTransparency = 0.35
	s.Text = def.sub
	s.Parent = bb
end

local function buildSpecialRoom(room: RoomData, propsFolder: Folder, rng: Random)
	SpecialRooms.Build(room :: any, propsFolder, rng)
	roomSign(room, propsFolder)
end

-- ── 4b. Rich Cosmetics, Rubble & Barriers Placement ─────────────────────────

local function decorateRooms(rooms: { RoomData }, propsFolder: Folder, rng: Random)
	for _, room in ipairs(rooms) do
		local minX, maxX = room.gx, room.gx + room.w - 1
		local minZ, maxZ = room.gz, room.gz + room.d - 1

		buildSpecialRoom(room, propsFolder, rng)

		-- Hazards: the boss arena gets lava, flame vents and cover pillars;
		-- about a third of the combat rooms get spike traps.
		if room.roomType == "Boss" then
			Hazards.BuildBossArena(room :: any, propsFolder, rng)
		elseif room.roomType == "Combat" and room.id ~= 1 and rng:NextNumber() < 0.35 then
			Hazards.BuildTraps(room :: any, propsFolder, rng)
		end

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
					spawnInstance(rubTemplate, cf, propsFolder, true)
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
					spawnInstance(barTemplate, cf, propsFolder, true)
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
				spawnInstance(cosTemplate, cf, propsFolder, true)
			end
		end

		-- 3b. Hades set dressing: a gold-inlaid floor medallion under the room
		-- reward (combat rooms) and green-fire braziers in the corners.
		if room.roomType == "Combat" or room.roomType == "Elite" or room.roomType == "Boss" then
			local center = Vector3.new((room.gx + room.w / 2) * FLOOR_SIZE, room.floorY, (room.gz + room.d / 2) * FLOOR_SIZE)
			AtmosphereManager.PlaceFloorMedallion(center, 7, propsFolder)
		end
		if room.w >= 3 and room.d >= 3 then
			local inset = 5
			local corners = {
				Vector3.new(minX * FLOOR_SIZE - FLOOR_SIZE / 2 + inset, room.floorY, minZ * FLOOR_SIZE - FLOOR_SIZE / 2 + inset),
				Vector3.new(maxX * FLOOR_SIZE + FLOOR_SIZE / 2 - inset, room.floorY, minZ * FLOOR_SIZE - FLOOR_SIZE / 2 + inset),
				Vector3.new(minX * FLOOR_SIZE - FLOOR_SIZE / 2 + inset, room.floorY, maxZ * FLOOR_SIZE + FLOOR_SIZE / 2 - inset),
				Vector3.new(maxX * FLOOR_SIZE + FLOOR_SIZE / 2 - inset, room.floorY, maxZ * FLOOR_SIZE + FLOOR_SIZE / 2 - inset),
			}
			local cornerParams = RaycastParams.new()
			cornerParams.FilterType = Enum.RaycastFilterType.Exclude
			cornerParams.FilterDescendantsInstances = { propsFolder }
			for _, p in ipairs(corners) do
				-- Only on open floor (not inside a wall or doorway prop).
				local hit = Workspace:Raycast(p + Vector3.new(0, 12, 0), Vector3.new(0, -24, 0), cornerParams)
				if hit and math.abs(hit.Position.Y - room.floorY) < 4 then
					AtmosphereManager.PlaceBrazier(CFrame.new(hit.Position), propsFolder, rng)
				end
			end
		end

		-- 3c. Hanging fire bowls on chains that rise out of view, over the
		-- open floor either side of the room's centre (clear of the reward).
		if room.w >= 3 and room.d >= 3 then
			local cx = (room.gx + room.w / 2) * FLOOR_SIZE
			local cz = (room.gz + room.d / 2) * FLOOR_SIZE
			local spreadX = room.w * FLOOR_SIZE * 0.26
			local spreadZ = room.d * FLOOR_SIZE * 0.26
			local spots = if rng:NextInteger(0, 1) == 0
				then { Vector3.new(cx - spreadX, 0, cz - spreadZ), Vector3.new(cx + spreadX, 0, cz + spreadZ) }
				else { Vector3.new(cx + spreadX, 0, cz - spreadZ), Vector3.new(cx - spreadX, 0, cz + spreadZ) }
			for _, s in ipairs(spots) do
				AtmosphereManager.PlaceHangingBrazier(Vector3.new(s.X, room.floorY + 12, s.Z), propsFolder, rng)
			end
		end

		-- 4. Candle clusters: warm pools of light hugging the walls.
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { propsFolder }
		for _ = 1, AtmosphereManager.Config.CandlesPerRoom do
			local side = rng:NextInteger(1, 4)
			local inset = 3.2
			local x, z
			if side == 1 then
				x, z = rng:NextInteger(minX, maxX) * FLOOR_SIZE, minZ * FLOOR_SIZE - FLOOR_SIZE / 2 + inset
			elseif side == 2 then
				x, z = rng:NextInteger(minX, maxX) * FLOOR_SIZE, maxZ * FLOOR_SIZE + FLOOR_SIZE / 2 - inset
			elseif side == 3 then
				x, z = minX * FLOOR_SIZE - FLOOR_SIZE / 2 + inset, rng:NextInteger(minZ, maxZ) * FLOOR_SIZE
			else
				x, z = maxX * FLOOR_SIZE + FLOOR_SIZE / 2 - inset, rng:NextInteger(minZ, maxZ) * FLOOR_SIZE
			end
			-- Sit on the actual floor surface; skip spots covered by walls or props.
			local hit = Workspace:Raycast(Vector3.new(x, room.floorY + 12, z), Vector3.new(0, -24, 0), rayParams)
			if hit and math.abs(hit.Position.Y - room.floorY) < 4 then
				AtmosphereManager.PlaceCandleCluster(CFrame.new(hit.Position), propsFolder, rng)
			end
		end
	end
end

-- ── 5. Main Generator Lifecycle ──────────────────────────────────────────────

-- Shift a whole layout `off` grid cells along +X (its run's slot).
local function shiftLayout(off: number, rooms: { RoomData }, floorGrid: { [string]: CellData }, doorways: { DoorwayData }, stairs: { StairData }): { [string]: CellData }
	if off == 0 then return floorGrid end
	local dx = Vector3.new(off * FLOOR_SIZE, 0, 0)
	for _, r in ipairs(rooms) do
		r.gx += off
		r.centerWorld += dx
	end
	local moved: { [string]: CellData } = {}
	for key, cell in pairs(floorGrid) do
		local c = string.split(key, "_")
		moved[`{(tonumber(c[1]) :: number) + off}_{c[2]}`] = cell
	end
	for _, dw in ipairs(doorways) do dw.position += dx end
	for _, st in ipairs(stairs) do st.cframe += dx end
	return moved
end

local build: (string, any) -> (CFrame, CFrame, CFrame)

-- Build the dungeon of run `cfg.runId` (replacing its previous level) in its
-- slot, themed for its map. Returns its spawn, boss and exit.
function DungeonGenerator.Generate(config: DungeonConfig?): (CFrame, CFrame, CFrame)
	loadAssets()
	local cfg: any = config or {}
	local runId: string = cfg.runId or "solo"
	-- (one build at a time: SpecialRooms / Hazards / mobs learn the run from `building`)
	while buildLock do task.wait() end
	buildLock = true
	local ok, a, b, c = pcall(build, runId, cfg)
	-- (back to the default set for the next build)
	assets = defaultAssets
	wallPieceLen = WALL_PIECE_LEN
	building = nil
	buildLock = false
	if not ok then error(a) end
	return a, b, c
end

build = function(runId: string, cfg: any): (CFrame, CFrame, CFrame)
	local prev = dungeons[runId]
	local slot = cfg.slot or (prev and prev.slot) or 0
	local mapId = cfg.mapId or (prev and prev.mapId) or MapData.DEFAULT
	local map = MapData.Get(mapId) or MapData.Get(MapData.DEFAULT)
	local level = cfg.level or 1
	local seed = cfg.seed or os.time()
	local rng = Random.new(seed)
	RunScope.Set(runId, "RunLevel", level)
	RunScope.Set(runId, "MapId", mapId)
	-- The map's own pieces, if it has them (MapData.assets).
	local own = map and map.assets and mapAssetSet(map.assets)
	if own then
		assets = own :: any
		wallPieceLen = own.wallLen
	end

	-- Clean this run's previous level
	DungeonGenerator.Clear(runId)
	building = runId
	Hazards.SetRun(runId)

	local dungeonFolder = Instance.new("Folder")
	dungeonFolder.Name = "GeneratedDungeon"
	dungeonFolder:SetAttribute("RunId", runId)
	dungeonFolder.Parent = Workspace
	local d: RunDungeon = {
		folder = dungeonFolder, spawn = CFrame.identity, boss = CFrame.identity, exit = CFrame.identity,
		payload = nil, seed = seed, level = level, slot = slot, mapId = mapId, transitioning = false,
	}
	dungeons[runId] = d

	local floorsFolder = Instance.new("Folder", dungeonFolder); floorsFolder.Name = "Floors"
	local wallsFolder  = Instance.new("Folder", dungeonFolder); wallsFolder.Name = "Walls"
	local stairsFolder = Instance.new("Folder", dungeonFolder); stairsFolder.Name = "Stairs"
	local propsFolder  = Instance.new("Folder", dungeonFolder); propsFolder.Name = "Props"

	print(`[DungeonGenerator] ─── Building Roguelite Dungeon (Seed: {seed}, Floor Y: {FLOOR_Y_OFFSET}, Wall Y: {WALL_Y_OFFSET}) ───`)

	-- 1. Graph Layout Construction
	local rooms, floorGrid0, doorwayList, stairList = buildDungeonGraph(rng, cfg)
	-- (into this run's slot)
	local floorGrid = shiftLayout(slot * SLOT_TILES, rooms, floorGrid0, doorwayList, stairList)
	local startRoom = rooms[1]
	local bossRoom = rooms[#rooms]
	for _, room in ipairs(rooms) do
		if room.roomType == "Boss" then
			bossRoom = room
			break
		end
	end

	d.spawn = CFrame.new(startRoom.centerWorld + Vector3.new(0, 8, 0))
	d.boss  = CFrame.new(bossRoom.centerWorld + Vector3.new(0, 8, 0))

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
			local tile = spawnInstance(floorTemplate, cf, floorsFolder, true)
			-- No two tiles quite alike: a little lighter or darker, some
			-- leaning cool (the stone reads less uniformly orange).
			local shade = rng:NextNumber(0.8, 1.06)
			local cool = rng:NextNumber(0, 0.4)
			local parts = if tile:IsA("BasePart") then { tile } else tile:GetDescendants()
			for _, d in ipairs(parts) do
				if d:IsA("BasePart") then
					local c = d.Color:Lerp(FLOOR_COOL, cool)
					d.Color = Color3.new(math.min(c.R * shade, 1), math.min(c.G * shade, 1), math.min(c.B * shade, 1))
				end
			end
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
	d.exit = stairCF

	if exitStairTemplate then
		spawnInstance(exitStairTemplate, stairCF, stairsFolder)
	end
	constructPitchBlackExit(stairCF, stairsFolder, runId)

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
	d.payload = mapPayload

	-- The map's stone: its tint over every floor and wall (not over a map's
	-- own pieces: their colours are already the art).
	if map and not own then
		local tint = map.stone
		for _, f in ipairs({ floorsFolder, wallsFolder, stairsFolder }) do
			for _, part in ipairs(f:GetDescendants()) do
				if part:IsA("BasePart") and part.Material ~= Enum.Material.Neon then
					local col = part.Color
					part.Color = Color3.new(col.R * tint.R, col.G * tint.G, col.B * tint.B)
				end
			end
		end
	end

	-- (the minimap: to this run's players)
	pcall(function()
		local Shared = ReplicatedStorage:FindFirstChild("Shared")
		if Shared then
			local Network = require(Shared:FindFirstChild("Network") :: ModuleScript)
			local mapRemote = Network.GetRemoteEvent(Network.Remotes.DungeonMapData)
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr:GetAttribute("RunId") == runId then mapRemote:FireClient(plr, mapPayload) end
			end
		end
	end)

	-- The mobs (each room fills as players come near) via MobManager
	pcall(function()
		local MobManager = require(script.Parent:WaitForChild("MobManager"))
		MobManager.SpawnRoomMobs(rooms, runId)
	end)
	-- The prison: a searchlight hunting through every combat room (Prison.luau).
	if map and map.prison then
		local ok, err = pcall(function()
			require(script.Parent:WaitForChild("Prison")).Setup(rooms, runId, propsFolder)
		end)
		if not ok then warn("[DungeonGenerator] prison:", err) end
	else
		RunScope.Set(runId, "Prison", nil)
	end

	print(`[DungeonGenerator] Dungeon ready for run {runId} ({if map then map.name else mapId}, level {level}, slot {slot}): {#rooms} rooms.`)
	print(`  • Spawn: {d.spawn.Position}`)
	print(`  • Boss:  {d.boss.Position}`)
	print(`  • Exit:  {d.exit.Position}`)

	return d.spawn, d.boss, d.exit
end

-- ── Public API ───────────────────────────────────────────────────────────────

-- Tear down a run's dungeon (its mobs, hazards and level), or every run's.
function DungeonGenerator.Clear(runId: string?)
	local ids = {}
	if runId then table.insert(ids, runId) else for id in pairs(dungeons) do table.insert(ids, id) end end
	for _, id in ipairs(ids) do
		Hazards.Clear(id)
		pcall(function()
			local MobManager = require(script.Parent:WaitForChild("MobManager"))
			MobManager.Clear(id)
		end)
		local d = dungeons[id]
		if d and d.folder and d.folder.Parent then d.folder:Destroy() end
		if d then d.folder = nil end
		for _, f in ipairs(Workspace:GetChildren()) do
			if f.Name == "GeneratedDungeon" and f:GetAttribute("RunId") == id then f:Destroy() end
		end
	end
end

-- The run is over: forget it entirely.
function DungeonGenerator.Forget(runId: string)
	DungeonGenerator.Clear(runId)
	dungeons[runId] = nil
end

function DungeonGenerator.GetSpawnCFrame(runId: string?): CFrame
	local d = runId and dungeons[runId]
	return if d then d.spawn else CFrame.identity
end

function DungeonGenerator.GetBossCFrame(runId: string?): CFrame
	local d = runId and dungeons[runId]
	return if d then d.boss else CFrame.identity
end

function DungeonGenerator.GetExitCFrame(runId: string?): CFrame
	local d = runId and dungeons[runId]
	return if d then d.exit else CFrame.identity
end

function DungeonGenerator.GetActiveSeed(runId: string?): number
	local d = runId and dungeons[runId]
	return if d then d.seed else 0
end

function DungeonGenerator.GetLevel(runId: string?): number
	local d = runId and dungeons[runId]
	return if d then d.level else 1
end

-- The whole run moves to a fresh level together. Everyone in the dungeon is
-- held in place while the old level is torn down and the new one is built
-- (so nobody falls into the void), then set down on the new spawn's floor,
-- side by side. Fallen teammates come back there too.
function DungeonGenerator.NextLevel(runId: string)
	local d = dungeons[runId]
	if not d then return end
	local runners: { { player: Player, root: BasePart } } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if p:GetAttribute("InLobby") == false and p:GetAttribute("RunId") == runId and root then
			root.Anchored = true
			root.AssemblyLinearVelocity = Vector3.zero
			table.insert(runners, { player = p, root = root })
		end
	end

	local ok, err = pcall(function()
		DungeonGenerator.Generate({
			runId = runId,
			seed = os.time() + math.random(1, 100000),
			level = d.level + 1,
		})
	end)
	if not ok then warn("[DungeonGenerator] Next level failed:", err) end

	local spawnCF = DungeonGenerator.GetSpawnCFrame(runId)
	-- Stand on the actual floor under the spawn point.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local chars = {}
	for _, r in ipairs(runners) do
		if r.player.Character then table.insert(chars, r.player.Character) end
	end
	params.FilterDescendantsInstances = chars
	for i, r in ipairs(runners) do
		local offset = Vector3.new(((i - 1) % 3 - 1) * 4, 0, math.floor((i - 1) / 3) * 4)
		local base = spawnCF.Position + offset
		local hit = Workspace:Raycast(base + Vector3.new(0, 20, 0), Vector3.new(0, -60, 0), params)
		local y = if hit then hit.Position.Y + 3.5 else spawnCF.Position.Y + 5
		if r.root.Parent then
			r.root.CFrame = CFrame.new(base.X, y, base.Z) * spawnCF.Rotation
			r.root.AssemblyLinearVelocity = Vector3.zero
		end
	end
	-- Hold everyone on the new floor a moment longer, so their game has
	-- received the new level before they can fall (or they'd drop straight
	-- through a floor that hasn't arrived yet).
	task.delay(1.5, function()
		for _, r in ipairs(runners) do
			if r.root.Parent then
				r.root.AssemblyLinearVelocity = Vector3.zero
				r.root.Anchored = false
			end
		end
	end)
	-- Anyone who was dead joins the party on the new level.
	pcall(function()
		local DeathManager = require(script.Parent:WaitForChild("DeathManager"))
		DeathManager.ReviveAllAt(spawnCF.Position + Vector3.new(0, 3, 0), runId)
	end)
	local nd = dungeons[runId]
	if nd then nd.transitioning = false end
end

function DungeonGenerator.GetMapPayload(runId: string?): any
	local d = runId and dungeons[runId]
	return if d then d.payload else nil
end

return DungeonGenerator
