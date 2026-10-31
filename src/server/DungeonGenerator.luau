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
local TweenService      = game:GetService("TweenService")
local RunService        = game:GetService("RunService")
local SpecialRooms      = require(script.Parent:WaitForChild("SpecialRooms"))
local Hazards           = require(script.Parent:WaitForChild("Hazards"))
local AtmosphereManager = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AtmosphereManager"))
local MapData           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MapData"))
local RunScope          = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
local Network           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local ArcadeKit         = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArcadeKit"))
local KeepKit           = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("KeepKit"))

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

export type RoomType = "Start" | "Combat" | "Rest" | "Treasure" | "Shop" | "Gamble" | "Elite" | "Event" | "Boss" | "Cursed" | "Purge"

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
	toLower: Vector3, -- (flat) from the gap between the two floors toward the lower one
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
	local root: Instance? = ReplicatedStorage:FindFirstChild(folderName)
	-- (the Infernal Keep's pieces are built in code: KeepKit)
	if not root and folderName == "map:keep assets" then
		local f = Instance.new("Folder")
		f.Name = folderName
		for _, piece in ipairs(KeepKit.PIECES) do
			if piece.kind ~= "set" then piece.build().Parent = f end
		end
		root = f
	end
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

local function buildDungeonGraph(rng: Random, config: DungeonConfig, plan: { string }?): ({ RoomData }, { [string]: CellData }, { DoorwayData }, { StairData })
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
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2),
					toLower = if y1 < y2 then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1) })

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
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2),
					toLower = if y1 < y2 then Vector3.new(0, 0, -1) else Vector3.new(0, 0, 1) })

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
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2),
					toLower = if y1 < y2 then Vector3.new(-1, 0, 0) else Vector3.new(1, 0, 0) })

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
				table.insert(stairList, { cframe = stairCF, lowerFloorY = minFY, upperFloorY = math.max(y1, y2),
					toLower = if y1 < y2 then Vector3.new(1, 0, 0) else Vector3.new(-1, 0, 0) })

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
	-- (a plan, the tutorial's: exactly its rooms, in its order, one route)
	local criticalLength = if plan then #plan else math.max(6, math.floor(totalRooms * 0.55))
	local activeRoom = startRoom
	local function typeFor(i: number, isBoss: boolean): RoomType
		if plan then return (plan[i] or "Combat") :: RoomType end
		return if isBoss then "Boss" else "Combat"
	end

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
					roomType = typeFor(i, isBoss),
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
							roomType = typeFor(i, isBoss),
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

	-- (a plan has no spokes or side rooms: just its route)
	if plan then return rooms, floorGrid, doorwayList, stairList end

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
	-- (a purge shrine on ~33% of floors: sacrifice a tome)
	if rng:NextNumber() < 0.33 then table.insert(branchTypes, "Purge") end

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

-- ── 1b. A floor taken room by room (MapData transit "portal": the Neon Arcade)
-- No corridors and no map to explore: a path chosen one room at a time.
-- Layers of 1, 2, 3, 2 and 1 rooms (the start; then two to choose between,
-- three, two; then the boss), each room an island floating far from the rest
-- (out of sight of each other). Every room's exits lead to every room of the
-- next layer: RoomPortals puts a portal for each on its far wall, labelled
-- with what's through it, opening when the room is cleared.
local LAYERS_GAP = 30 -- tiles between layers (along +X) and between a layer's rooms (along Z)
-- The tutorial (MapData `plan`): one room a layer, in the plan's order, laid
-- out in rows of TUTORIAL_ROW (back and forth) so the floor fits its slot.
local TUTORIAL_ROW = 5
local function buildLayeredGraph(rng: Random, config: DungeonConfig, plan0: { string }?): ({ RoomData }, { [string]: CellData })
	local rooms: { RoomData } = {}
	local floorGrid: { [string]: CellData } = {}
	local function pick(list: { string }): string return list[rng:NextInteger(1, #list)] end
	local function shuffle(t: { string }): { string }
		for i = #t, 2, -1 do
			local j = rng:NextInteger(1, i)
			t[i], t[j] = t[j], t[i]
		end
		return t
	end
	local plan: { { string } } = {
		{ "Start" },
		shuffle({ "Combat", pick({ "Combat", "Elite", "Treasure" }) }),
		shuffle({ "Combat", pick({ "Combat", "Elite" }), pick({ "Shop", "Rest", "Gamble", "Treasure", "Event", "Cursed" }) }),
		shuffle({ pick({ "Combat", "Elite" }), pick({ "Rest", "Shop", "Event", "Purge" }) }),
		{ "Boss" },
	}
	if plan0 then
		plan = {}
		for _, rtype in ipairs(plan0) do table.insert(plan, { rtype }) end
	end
	local id = 0
	local prev: { RoomData } = {}
	for layer, types in ipairs(plan) do
		local this: { RoomData } = {}
		for k, rtype in ipairs(types) do
			id += 1
			-- (square and odd, one size per kind of room: a true middle tile, and
			-- the same room always looks the same size)
			local w = if rtype == "Boss" then 13 elseif rtype == "Combat" or rtype == "Elite" then 11 else 9
			local d = w
			local gx = (layer - 1) * LAYERS_GAP - math.floor(w / 2)
			local gz = math.floor((k - (#types + 1) / 2) * LAYERS_GAP) - math.floor(d / 2)
			if plan0 then
				local row = (layer - 1) // TUTORIAL_ROW
				local col = (layer - 1) % TUTORIAL_ROW
				if row % 2 == 1 then col = TUTORIAL_ROW - 1 - col end
				gx = col * LAYERS_GAP - math.floor(w / 2)
				gz = row * LAYERS_GAP - math.floor(d / 2)
			end
			local room: RoomData = {
				id = id,
				roomType = rtype :: RoomType,
				tier = 0,
				floorY = FLOOR_Y_OFFSET,
				wallY = WALL_Y_OFFSET,
				gx = gx,
				gz = gz,
				w = w,
				d = d,
				centerWorld = Vector3.new((gx + w / 2) * FLOOR_SIZE, FLOOR_Y_OFFSET, (gz + d / 2) * FLOOR_SIZE),
				connections = {},
			}
			for x = gx, gx + w - 1 do
				for z = gz, gz + d - 1 do
					floorGrid[x .. "_" .. z] = { floorY = FLOOR_Y_OFFSET, wallY = WALL_Y_OFFSET, tier = 0 }
				end
			end
			table.insert(rooms, room)
			table.insert(this, room)
		end
		for _, a in ipairs(prev) do
			for _, b in ipairs(this) do table.insert(a.connections, b.id) end
		end
		prev = this
	end
	return rooms, floorGrid
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

	-- 4. Corner Pillars wherever two walls meet: room corners, the corners of
	-- corridors, and the wall ends where a corridor meets a room (framing its
	-- doorway, and closing the seam there). Not round the lift shafts. The
	-- corridors' are half size (standing on the floor all the same).
	local function isRoomTile(gx: number, gz: number): boolean
		for _, room in ipairs(rooms) do
			if gx >= room.gx and gx < room.gx + room.w and gz >= room.gz and gz < room.gz + room.d then
				return true
			end
		end
		return false
	end
	local function isCorridorArea(pos: Vector3): boolean
		local gxCenter = math.floor(pos.X / FLOOR_SIZE + 0.5)
		local gzCenter = math.floor(pos.Z / FLOOR_SIZE + 0.5)
		for dx = -1, 1 do
			for dz = -1, 1 do
				if hasFloor(gxCenter + dx, gzCenter + dz) and not isRoomTile(gxCenter + dx, gzCenter + dz) then
					return true
				end
			end
		end
		return false
	end
	local CORRIDOR_PILLAR_SCALE = 0.5
	local function bottomOf(inst: Instance): number
		if inst:IsA("BasePart") then
			return inst.Position.Y - inst.Size.Y / 2
		end
		local cf, size = (inst :: Model):GetBoundingBox()
		return cf.Position.Y - size.Y / 2
	end
	for _, cornerPos in pairs(corners) do
		if not isNearStair(cornerPos, 13) then
			local pillarTemplate = pickRandom(assets.pillars, rng)
			if pillarTemplate then
				local pillar = spawnInstance(pillarTemplate, CFrame.new(cornerPos), wallsFolder)
				if isNearGate(cornerPos, 16) or isCorridorArea(cornerPos) then
					local floorAt = bottomOf(pillar)
					if pillar:IsA("Model") then
						pillar:ScaleTo(pillar:GetScale() * CORRIDOR_PILLAR_SCALE)
					elseif pillar:IsA("BasePart") then
						pillar.Size *= CORRIDOR_PILLAR_SCALE
					end
					-- (shrunk about its middle: set back down on the floor)
					local drop = Vector3.new(0, floorAt - bottomOf(pillar), 0)
					if pillar:IsA("Model") then
						pillar:PivotTo(pillar:GetPivot() + drop)
					elseif pillar:IsA("BasePart") then
						pillar.CFrame += drop
					end
				end
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
				-- (the arcade's alternate in turn: hex, circuit, hex...)
				local wallPiece = if arcadeTheme and #wallList > 0 then wallList[(i - 1) % #wallList + 1] else pickRandom(wallList, rng)
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
--   (Corruption.luau).
local GO_AFTER = 1.2      -- everyone in the same portal this long, then go (step out and it's off)
local EXTRACT_EVERY = 3   -- floors 3, 6, 9… offer extraction
DungeonGenerator.EXTRACT_EVERY = EXTRACT_EVERY

-- Set by Corruption.luau: what extracting does, and what going down does.
DungeonGenerator.Hooks = {
	extract = nil :: ((string, { Player }) -> ())?,
	descended = nil :: ((string, number, boolean) -> ())?, -- (runId, the floor left, it offered extraction)
}

-- rise: the lift's ride (yields until it's at the top), before the next floor.
type Portal = { part: BasePart, kind: string, text: TextLabel, bb: BillboardGui, rise: ((players: { Player }) -> ())? }

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
					pt.text.Text = if agreedOn == pt.kind then (if pt.kind == "extract" then "EXTRACTING..." else "GOING UP...")
						else `{n} / {total} {if pt.kind == "extract" then "EXTRACT" else "ON THE LIFT"}`
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
						-- The lift carries everyone up, then the next floor.
						for _, pt in ipairs(portals) do
							if pt.kind == "descend" and pt.rise then
								local ok, err = pcall(pt.rise, everyone)
								if not ok then warn("[DungeonGenerator] Lift ride failed:", err) end
								break
							end
						end
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

-- ── Room lifts (between two rooms on different floor heights) ──────────────
-- Where a corridor climbs to a room on the next height, the one-tile gap
-- between the two floors is a lift shaft: a wooden platform in a timber
-- frame, stone walls either side, a slatted wooden gate at each landing.
-- Step on and the gates close, it carries everyone on it to the other floor
-- and that landing's gate opens. Waiting at the far landing calls it over.
-- Riders are held to the platform for the ride (as the exit lift does).
local LIFT = {
	shaft = 12,         -- along the corridor (one floor tile)
	width = 23,         -- across it (the corridor, two tiles)
	rideTime = 2.4,
	depart = 0.8,       -- seconds someone stands on it before it goes
	gateTime = 0.45,
	gateUp = 8,         -- how far a gate slides up to open
	callReach = 9,      -- studs out from a landing's gate that call it over
}
local LIFT_WOOD = Color3.fromRGB(110, 76, 48)
local LIFT_WOOD_DARK = Color3.fromRGB(70, 48, 32)
local LIFT_ROPE = Color3.fromRGB(150, 128, 92)
local LIFT_STONE = Color3.fromRGB(58, 56, 62)

local function constructRoomLift(stair: StairData, parent: Instance, floorsFolder: Instance)
	local model = Instance.new("Model")
	model.Name = "RoomLift"
	model.Parent = parent
	local center = stair.cframe.Position
	local toLower = stair.toLower
	-- (the frame faces the lower landing: local -Z toward it, X across)
	local flatCenter = Vector3.new(center.X, 0, center.Z)
	local frame = CFrame.lookAt(flatCenter, flatCenter + toLower)
	local half = LIFT.shaft / 2

	-- where the two floors' tops really are
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { floorsFolder }
	local function floorTop(pos: Vector3, guess: number): number
		local hit = Workspace:Raycast(Vector3.new(pos.X, guess + 10, pos.Z), Vector3.new(0, -20, 0), params)
		return if hit then hit.Position.Y else guess
	end
	local lowTop = floorTop(center + toLower * (half + 3), stair.lowerFloorY)
	local highTop = floorTop(center - toLower * (half + 3), stair.upperFloorY)
	if highTop - lowTop < 2 then highTop = lowTop + (stair.upperFloorY - stair.lowerFloorY) end
	local rise = highTop - lowTop

	local function part(props: { [string]: any }): BasePart
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanTouch = false
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		for k, v in pairs(props) do (p :: any)[k] = v end
		p.Parent = model
		return p
	end
	-- a point in the shaft: x across, z along (- toward the lower landing), at height y
	local function at(x: number, y: number, z: number): CFrame
		return frame * CFrame.new(x, 0, z) + Vector3.new(0, y, 0)
	end

	-- the shaft: stone walls either side, a floor at the bottom, and the face
	-- of the upper floor at its far end
	local wallH = rise + 18
	for _, sx in ipairs({ -1, 1 }) do
		part({ Name = "ShaftWall", Size = Vector3.new(1.4, wallH, LIFT.shaft + 1.4), CFrame = at(sx * (LIFT.width / 2 + 0.7), lowTop - 1 + wallH / 2, 0),
			Material = Enum.Material.Slate, Color = LIFT_STONE })
	end
	part({ Name = "ShaftFloor", Size = Vector3.new(LIFT.width, 1, LIFT.shaft), CFrame = at(0, lowTop - 1.5, 0),
		Material = Enum.Material.Slate, Color = Color3.fromRGB(46, 44, 50) })
	part({ Name = "UpperFace", Size = Vector3.new(LIFT.width, rise + 1, 1), CFrame = at(0, lowTop + (rise - 1) / 2, half - 0.5),
		Material = Enum.Material.Slate, Color = LIFT_STONE })

	-- the timber frame: posts at the corners, beams over the top, a pulley
	local topY = highTop + 13
	for _, sx in ipairs({ -1, 1 }) do
		for _, sz in ipairs({ -1, 1 }) do
			part({ Name = "Post", Size = Vector3.new(1.2, topY - lowTop + 1, 1.2),
				CFrame = at(sx * (LIFT.width / 2 - 0.4), (lowTop + topY) / 2, sz * (half - 0.4)),
				Material = Enum.Material.Wood, Color = LIFT_WOOD_DARK })
		end
		part({ Name = "Beam", Size = Vector3.new(1.2, 1.2, LIFT.shaft), CFrame = at(sx * (LIFT.width / 2 - 0.4), topY, 0),
			Material = Enum.Material.Wood, Color = LIFT_WOOD_DARK })
	end
	part({ Name = "CrossBeam", Size = Vector3.new(LIFT.width, 1.4, 1.4), CFrame = at(0, topY + 0.6, 0),
		Material = Enum.Material.Wood, Color = LIFT_WOOD_DARK })
	part({ Name = "Pulley", Shape = Enum.PartType.Cylinder, Size = Vector3.new(1, 3.4, 3.4), CFrame = at(0, topY - 1.2, 0),
		Material = Enum.Material.Wood, Color = LIFT_WOOD, CanCollide = false })

	-- the car: the platform, a rail along each side; ropes up to the beam
	local car: { BasePart } = {}
	local function carPart(props: { [string]: any }): BasePart
		local p = part(props)
		table.insert(car, p)
		return p
	end
	local floor = carPart({ Name = "Platform", Size = Vector3.new(LIFT.width - 0.4, 1, LIFT.shaft - 1.4), CFrame = at(0, lowTop - 0.5, -0.5),
		Material = Enum.Material.WoodPlanks, Color = LIFT_WOOD })
	for _, sx in ipairs({ -1, 1 }) do
		carPart({ Name = "Rail", Size = Vector3.new(0.6, 3.5, LIFT.shaft - 1.6), CFrame = at(sx * (LIFT.width / 2 - 0.6), lowTop + 1.75, -0.5),
			Material = Enum.Material.Wood, Color = LIFT_WOOD_DARK })
	end
	local ropes: { { part: BasePart, x: number } } = {}
	for _, sx in ipairs({ -1, 1 }) do
		local r = part({ Name = "Rope", Size = Vector3.new(0.3, 1, 0.3), Material = Enum.Material.Fabric, Color = LIFT_ROPE, CanCollide = false })
		table.insert(ropes, { part = r, x = sx * (LIFT.width / 2 - 2) })
	end
	local function placeRopes(y: number)
		for _, r in ipairs(ropes) do
			local len = math.max(topY - 1.2 - y, 0.5)
			r.part.Size = Vector3.new(0.3, len, 0.3)
			r.part.CFrame = at(r.x, y + len / 2, -0.5)
		end
	end
	placeRopes(lowTop)

	-- a slatted wooden gate at each landing (closed: across the edge)
	type Gate = { parts: { BasePart }, closed: { CFrame } }
	local function gate(z: number, baseY: number): Gate
		local g: Gate = { parts = {}, closed = {} }
		local function add(p: BasePart)
			table.insert(g.parts, p)
			table.insert(g.closed, p.CFrame)
		end
		for _, y in ipairs({ 1.2, 5.6 }) do
			add(part({ Name = "GateBar", Size = Vector3.new(LIFT.width - 1.6, 0.6, 0.5), CFrame = at(0, baseY + y, z),
				Material = Enum.Material.Wood, Color = LIFT_WOOD_DARK, CanCollide = false }))
		end
		for k = -5, 5 do
			add(part({ Name = "GateSlat", Size = Vector3.new(0.8, 6.6, 0.3), CFrame = at(k * 2, baseY + 3.4, z),
				Material = Enum.Material.WoodPlanks, Color = LIFT_WOOD, CanCollide = false }))
		end
		-- (one unseen panel does the blocking)
		add(part({ Name = "GateBlock", Size = Vector3.new(LIFT.width - 1.6, 7, 0.4), CFrame = at(0, baseY + 3.5, z), Transparency = 1 }))
		return g
	end
	local lowGate = gate(-half + 0.3, lowTop)
	local highGate = gate(half - 0.3, highTop)
	local function setGate(g: Gate, open: boolean, instant: boolean?)
		for i, p in ipairs(g.parts) do
			local cf = g.closed[i] + Vector3.new(0, if open then LIFT.gateUp else 0, 0)
			if instant then
				p.CFrame = cf
			else
				TweenService:Create(p, TweenInfo.new(LIFT.gateTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = cf }):Play()
			end
			if p.Name == "GateBlock" then p.CanCollide = not open end
		end
	end
	setGate(lowGate, true, true)
	setGate(highGate, false, true)

	-- who's where
	local function playersIn(cf: CFrame, size: Vector3): { Player }
		local out = {}
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 and plr:GetAttribute("IsDead") ~= true then
				local rel = cf:PointToObjectSpace(root.Position)
				if math.abs(rel.X) <= size.X / 2 and math.abs(rel.Y) <= size.Y / 2 and math.abs(rel.Z) <= size.Z / 2 then
					table.insert(out, plr)
				end
			end
		end
		return out
	end
	local function onCar(): { Player }
		return playersIn(floor.CFrame * CFrame.new(0, 4, 0), Vector3.new(LIFT.width, 8, LIFT.shaft))
	end
	local function waitingAt(up: boolean): boolean
		local y = if up then highTop else lowTop
		local z = if up then half + LIFT.callReach / 2 else -half - LIFT.callReach / 2
		return #playersIn(at(0, y + 4, z), Vector3.new(LIFT.width, 9, LIFT.callReach)) > 0
	end

	local isUp = false
	local busy = false
	local armed = true -- (riders who've just arrived step off before it'll go again)
	local function travel()
		busy = true
		setGate(lowGate, false)
		setGate(highGate, false)
		task.wait(LIFT.gateTime + 0.1)
		local riders: { { root: BasePart, rel: CFrame } } = {}
		for _, plr in ipairs(onCar()) do
			local root = (plr.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart
			root.AssemblyLinearVelocity = Vector3.zero
			root.Anchored = true
			table.insert(riders, { root = root, rel = floor.CFrame:ToObjectSpace(root.CFrame) })
		end
		local start: { [BasePart]: CFrame } = {}
		for _, c in ipairs(car) do start[c] = c.CFrame end
		local floorStart = floor.CFrame
		local from, to = if isUp then rise else 0, if isUp then 0 else rise
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / LIFT.rideTime, 0, 1)
			local k = a * a * (3 - 2 * a) -- (eases off the mark and into the landing)
			local dy = from + (to - from) * k
			local move = Vector3.new(0, dy - from + math.sin(a * 50) * 0.03, 0)
			for c, cf in pairs(start) do
				if c.Parent then c.CFrame = cf + move end
			end
			local floorNow = floorStart + move
			for _, rd in ipairs(riders) do
				if rd.root.Parent then rd.root.CFrame = floorNow * rd.rel end
			end
			placeRopes(lowTop + dy)
			if a >= 1 or not model.Parent then break end
			RunService.Heartbeat:Wait()
		end
		for _, rd in ipairs(riders) do
			if rd.root.Parent then rd.root.Anchored = false end
		end
		isUp = not isUp
		armed = #riders == 0
		setGate(if isUp then highGate else lowGate, true)
		task.wait(LIFT.gateTime)
		busy = false
	end

	task.spawn(function()
		local since: number? = nil
		while model.Parent do
			task.wait(0.15)
			if busy then continue end
			if #onCar() == 0 then
				armed = true
				since = nil
				-- called from the other landing
				if waitingAt(not isUp) then task.spawn(travel) end
			elseif armed then
				since = since or os.clock()
				if os.clock() - since >= LIFT.depart then
					since = nil
					task.spawn(travel)
				end
			end
		end
	end)
end

-- ── The Infernal Keep's way down: the demon gate and a dark hallway ────────
-- Instead of the lift: the boss arena's demon-skull gate, set in a gap in one
-- of its walls. Once the boss falls its portcullis grinds up and the molten
-- glow behind it dies, showing a dark hallway running away from the keep:
-- walk down it into the dark (the descend vote, as on the lift). It stands
-- on the arena's +X or -Z wall (top right / top left on screen, facing the
-- camera, so the opening is seen), at the spot along them where the hallway,
-- and some way past its end, crosses no room, corridor or stair, and no
-- doorway is near: the middlest spot with plenty of room, the hallway as long
-- as fits (up to HALL_LEN). Under 36 studs to spare anywhere there: the lift.
local keepExitBuilt = false
local HALL_LEN = 64
local HALL_W = 12       -- inside

local function constructKeepExit(room: RoomData, floorGrid: { [string]: CellData }, doorways: { DoorwayData },
	stairs: { StairData }, wallsFolder: Folder, parentFolder: Folder, runId: string): CFrame?
	local minX, maxX = room.gx, room.gx + room.w - 1
	local minZ, maxZ = room.gz, room.gz + room.d - 1
	local top = room.floorY + 0.5 -- (the keep's floor pieces: their top)
	-- Where it can stand: on the arena's +X wall or its -Z wall, the two the
	-- camera faces (IsometricCamera sits off to -X, +Z): seen top right and
	-- top left on screen, the gate facing the player, the hallway running
	-- away into the screen. Along each wall, every cell clear of the corners,
	-- the middle ones first.
	local sides: { { Vector3 } } = {}
	local function along(n: number, mid: number, first: number, make: (number) -> { Vector3 })
		local spots = {}
		for k = first + 2, first + n - 3 do table.insert(spots, k) end
		table.sort(spots, function(a, b) return math.abs(a - mid) < math.abs(b - mid) end)
		for _, k in ipairs(spots) do table.insert(sides, make(k)) end
	end
	along(room.d, room.gz + (room.d - 1) / 2, room.gz, function(gz)
		return { Vector3.new(maxX * FLOOR_SIZE + FLOOR_SIZE / 2, top, gz * FLOOR_SIZE), Vector3.new(1, 0, 0) }
	end)
	along(room.w, room.gx + (room.w - 1) / 2, room.gx, function(gx)
		return { Vector3.new(gx * FLOOR_SIZE, top, minZ * FLOOR_SIZE - FLOOR_SIZE / 2), Vector3.new(0, 0, -1) }
	end)

	-- How far out from `at` the way is clear: no floor cell (room or corridor)
	-- or stair within the hallway's width (and a margin) up to there; 0 if a
	-- doorway is by the gate.
	local function clearFor(at: Vector3, out: Vector3): number
		for _, dw in ipairs(doorways) do
			if Vector2.new(dw.position.X - at.X, dw.position.Z - at.Z).Magnitude < 26 then return 0 end
		end
		local side = Vector3.new(out.Z, 0, -out.X)
		local halfW = HALL_W / 2 + 3 + 10
		local best = math.huge
		local function consider(px: number, pz: number, pad: number)
			local rel = Vector3.new(px - at.X, 0, pz - at.Z)
			local along, across = rel:Dot(out), rel:Dot(side)
			if along > 0.5 and math.abs(across) < halfW + pad then
				best = math.min(best, along - pad)
			end
		end
		for key in pairs(floorGrid) do
			local c = string.split(key, "_")
			consider((tonumber(c[1]) :: number) * FLOOR_SIZE, (tonumber(c[2]) :: number) * FLOOR_SIZE, FLOOR_SIZE * 0.75)
		end
		for _, st in ipairs(stairs) do consider(st.cframe.Position.X, st.cframe.Position.Z, 14) end
		return best
	end
	local pick: { Vector3 }? = nil
	local room0 = 0
	for _, sd in ipairs(sides) do
		-- (the first spot with plenty of room wins: the middlest)
		local c = clearFor(sd[1], sd[2])
		if c > room0 then
			room0 = c
			pick = sd
		end
		if room0 >= HALL_LEN + 40 then break end
	end
	-- (the hallway, with some open dark past its end; a short one if that's all there is)
	local hallLen = math.min(HALL_LEN, room0 - 24)
	print(`[DungeonGenerator] Keep exit: clearest side has {if room0 == math.huge then "open" else math.floor(room0)} studs: hallway {math.floor(hallLen)}`)
	if hallLen < 36 then pick = nil end
	if not pick then return nil end
	local at: Vector3, out: Vector3 = pick[1], pick[2]
	local into = -out
	local folder = Instance.new("Folder")
	folder.Name = "KeepExit"
	folder.Parent = parentFolder

	-- the gap in the wall (the piece there, and any pillar in the way)
	for _, piece in ipairs(wallsFolder:GetChildren()) do
		local pos = if piece:IsA("Model") then piece:GetPivot().Position elseif piece:IsA("BasePart") then piece.Position else nil
		if pos and math.abs(pos.Y - top) < 30 then
			local rel = Vector3.new(pos.X - at.X, 0, pos.Z - at.Z)
			if math.abs(rel:Dot(out)) < 4 and math.abs(rel:Dot(Vector3.new(out.Z, 0, -out.X))) < 7 then piece:Destroy() end
		end
	end

	-- the gate, its back to the wall line, facing into the arena
	local gate = KeepKit.Build("Demon_Gate") :: Model
	local gateCF = CFrame.lookAt(at + into * 3, at + into * 10)
	gate:PivotTo(gateCF)
	gate.Parent = folder
	local bars, glows = {}, {}
	for _, d in ipairs(gate:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Portcullis" then table.insert(bars, d) elseif d.Name == "GateGlow" then table.insert(glows, d) end
		end
	end
	-- (shut: nobody through until the boss is down)
	local blocker = Instance.new("Part")
	blocker.Name = "GateBlocker"
	blocker.Anchored, blocker.CanCollide, blocker.CanQuery, blocker.CanTouch = true, true, false, false
	blocker.Transparency = 1
	blocker.Size = Vector3.new(HALL_W + 2, 18, 1)
	blocker.CFrame = CFrame.lookAt(at + Vector3.new(0, 9, 0), at + Vector3.new(0, 9, 0) + out)
	blocker.Parent = folder

	-- the hallway: dark stone, no light, darkening to black, a roof over its far reach
	local cfHall = CFrame.lookAt(at, at + out) -- (-Z along the hallway)
	local function hallPart(name: string, size: Vector3, cf: CFrame, color: Color3, transparency: number?)
		local p = Instance.new("Part")
		p.Name = name
		p.Anchored, p.CanTouch = true, false
		p.Size, p.CFrame, p.Color = size, cf, color
		p.Material = Enum.Material.Slate
		p.Transparency = transparency or 0
		p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		p.Parent = folder
		return p
	end
	local DARK = Color3.fromRGB(22, 16, 20)
	hallPart("HallFloor", Vector3.new(HALL_W + 1, 1, hallLen), cfHall * CFrame.new(0, -0.5, -hallLen / 2), Color3.fromRGB(34, 26, 30))
	for _, sx in ipairs({ -1, 1 }) do
		hallPart("HallWall", Vector3.new(3, 24, hallLen), cfHall * CFrame.new(sx * (HALL_W / 2 + 1.5), 12, -hallLen / 2), DARK)
	end
	hallPart("HallRoof", Vector3.new(HALL_W + 6, 2, hallLen - 14), cfHall * CFrame.new(0, 24, -(14 + (hallLen - 14) / 2)), DARK)
	hallPart("HallEnd", Vector3.new(HALL_W + 6, 26, 2), cfHall * CFrame.new(0, 12, -hallLen - 1), Color3.new(0, 0, 0))
	-- the dark: veils of black across it, thicker the deeper in
	local veils = 6
	for k = 1, veils do
		local dist = 10 + (hallLen - 14) * (k - 1) / (veils - 1)
		local v = hallPart("Darkness", Vector3.new(HALL_W, 22, 0.2), cfHall * CFrame.new(0, 11, -dist), Color3.new(0, 0, 0),
			0.82 - 0.8 * (k - 1) / (veils - 1))
		v.Material = Enum.Material.SmoothPlastic
		v.CanCollide, v.CanQuery = false, false
		v.CastShadow = false
	end
	-- the way down: near the end, in the dark
	local zone = Instance.new("Part")
	zone.Name = "DescendZone"
	zone.Anchored, zone.CanCollide, zone.CanQuery, zone.CanTouch = true, false, false, false
	zone.Transparency = 1
	zone.Size = Vector3.new(HALL_W, 14, 20)
	zone.CFrame = cfHall * CFrame.new(0, 7, -(hallLen - 14))
	zone.Parent = folder

	-- opening, once the boss is down: the bars grind up, the glow dies
	local bossId = room.id
	task.spawn(function()
		while folder.Parent do
			local list = RunScope.Get(runId, "ClearedRooms")
			if typeof(list) == "string" and string.find(list, `|{bossId}|`, 1, true) then break end
			task.wait(0.5)
		end
		if not folder.Parent then return end
		for _, b in ipairs(bars) do
			TweenService:Create(b, TweenInfo.new(2.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = b.CFrame + Vector3.new(0, 15, 0) }):Play()
		end
		for _, g in ipairs(glows) do
			TweenService:Create(g, TweenInfo.new(2, Enum.EasingStyle.Quad), { Transparency = 1 }):Play()
		end
		task.wait(2.4)
		for _, b in ipairs(bars) do b.Transparency = 1 end
		blocker:Destroy()
	end)

	local portals: { Portal } = {}
	local bb, text = countBoard(zone)
	table.insert(portals, { part = zone, kind = "descend", bb = bb, text = text })
	local d = dungeons[runId]
	local level = if d then d.level else 1
	local extractFloor = level % EXTRACT_EVERY == 0 or RunScope.Get(runId, "Tutorial") == true
	if extractFloor then
		-- in the arena before the gate
		local base = at + into * 22
		local ez = buildExtractPortal(CFrame.lookAt(base, base + out), folder)
		local ebb, etext = countBoard(ez)
		table.insert(portals, { part = ez, kind = "extract", bb = ebb, text = etext })
	end
	watchPortals(runId, portals, extractFloor)
	keepExitBuilt = true
	return gateCF
end

local function constructDungeonLiftExit(liftCF: CFrame, parentFolder: Folder, runId: string)
	local exitModel = Instance.new("Folder")
	exitModel.Name = "DungeonLiftExit"
	exitModel.Parent = parentFolder

	local GOLD = Color3.fromRGB(245, 195, 95)
	local GOLD_BRIGHT = Color3.fromRGB(255, 225, 140)
	local IRON = Color3.fromRGB(45, 42, 48)
	local IRON_LIGHT = Color3.fromRGB(80, 75, 85)
	local WOOD = Color3.fromRGB(75, 52, 38)

	local function part(props: { [string]: any }): BasePart
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = true
		for k, v in pairs(props) do (p :: any)[k] = v end
		p.Parent = exitModel
		return p
	end
	-- The car: everything that rides up with the players.
	local car: { BasePart } = {}
	local function carPart(props: { [string]: any }): BasePart
		local p = part(props)
		table.insert(car, p)
		return p
	end

	-- 1. Lift Platform Floor
	local floor = carPart({
		Name = "LiftPlatform",
		Size = Vector3.new(22, 2, 22),
		CFrame = liftCF * CFrame.new(0, 0, 0),
		Color = WOOD,
		Material = Enum.Material.WoodPlanks,
		CanCollide = true,
	})
	carPart({
		Name = "LiftBorder",
		Size = Vector3.new(23, 2.2, 23),
		CFrame = liftCF * CFrame.new(0, -0.05, 0),
		Color = IRON,
		Material = Enum.Material.Metal,
		CanCollide = false,
	})

	-- 2. Glowing Magic Rune Ring in Center of Platform
	local runeCore = carPart({
		Name = "LiftRuneCore",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 14, 14),
		CFrame = liftCF * CFrame.new(0, 1.05, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD_BRIGHT,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})
	local runeRing = carPart({
		Name = "LiftRuneRing",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.35, 18, 18),
		CFrame = liftCF * CFrame.new(0, 1.02, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(180, 130, 45),
		Material = Enum.Material.Neon,
		Transparency = 0.6,
	})

	-- Upward ascension light motes (rising to next floor)
	local liftSparks = Instance.new("ParticleEmitter")
	liftSparks.Name = "LiftAscentParticles"
	liftSparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	liftSparks.Color = ColorSequence.new(GOLD_BRIGHT, Color3.fromRGB(255, 140, 40))
	liftSparks.LightEmission = 1
	liftSparks.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(0.6, 0.9),
		NumberSequenceKeypoint.new(1, 0),
	})
	liftSparks.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.8, 0.4),
		NumberSequenceKeypoint.new(1, 1),
	})
	liftSparks.Lifetime = NumberRange.new(1.8, 3.2)
	liftSparks.Rate = 35
	liftSparks.Speed = NumberRange.new(10, 22)
	liftSparks.SpreadAngle = Vector2.new(15, 15)
	liftSparks.EmissionDirection = Enum.NormalId.Top
	liftSparks.Parent = runeCore

	-- (no PointLight: the neon rune glows on its own)

	-- 3. Four Massive Guide Pillars & Overhead Mechanical Gantry
	local pillarPositions = {
		Vector3.new(-10.5, 18, -10.5),
		Vector3.new(10.5, 18, -10.5),
		Vector3.new(-10.5, 18, 10.5),
		Vector3.new(10.5, 18, 10.5),
	}
	for _, offset in ipairs(pillarPositions) do
		part({
			Name = "LiftPillar",
			Size = Vector3.new(2.4, 38, 2.4),
			CFrame = liftCF * CFrame.new(offset),
			Color = IRON,
			Material = Enum.Material.Metal,
			CanCollide = true,
		})
		-- Brass bracket on pillar
		part({
			Name = "LiftBracket",
			Size = Vector3.new(3, 1.2, 3),
			CFrame = liftCF * CFrame.new(offset.X, 2, offset.Z),
			Color = GOLD,
			Material = Enum.Material.Metal,
		})
		-- Suspension Chain hanging from top to platform
		part({
			Name = "LiftChain",
			Size = Vector3.new(0.6, 32, 0.6),
			CFrame = liftCF * CFrame.new(offset.X * 0.85, 17, offset.Z * 0.85),
			Color = IRON_LIGHT,
			Material = Enum.Material.CorrodedMetal,
		})
	end

	-- Overhead Crossbeams & Pulleys
	part({
		Name = "OverheadBeamX1",
		Size = Vector3.new(23.4, 2, 2),
		CFrame = liftCF * CFrame.new(0, 36, -10.5),
		Color = IRON,
		Material = Enum.Material.Metal,
	})
	part({
		Name = "OverheadBeamX2",
		Size = Vector3.new(23.4, 2, 2),
		CFrame = liftCF * CFrame.new(0, 36, 10.5),
		Color = IRON,
		Material = Enum.Material.Metal,
	})
	part({
		Name = "OverheadBeamZ1",
		Size = Vector3.new(2, 2, 23.4),
		CFrame = liftCF * CFrame.new(-10.5, 36, 0),
		Color = IRON,
		Material = Enum.Material.Metal,
	})
	part({
		Name = "OverheadBeamZ2",
		Size = Vector3.new(2, 2, 23.4),
		CFrame = liftCF * CFrame.new(10.5, 36, 0),
		Color = IRON,
		Material = Enum.Material.Metal,
	})

	-- Huge overhead pulley wheel in the middle
	part({
		Name = "CenterPulleyWheel",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(2.4, 7, 7),
		CFrame = liftCF * CFrame.new(0, 37.5, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = GOLD,
		Material = Enum.Material.Metal,
	})

	-- 4. Safety Railings around left, right, and back
	carPart({
		Name = "RailingLeft",
		Size = Vector3.new(0.8, 4.5, 21),
		CFrame = liftCF * CFrame.new(-10.5, 3.25, 0),
		Color = IRON,
		Material = Enum.Material.Metal,
		CanCollide = true,
	})
	carPart({
		Name = "RailingRight",
		Size = Vector3.new(0.8, 4.5, 21),
		CFrame = liftCF * CFrame.new(10.5, 3.25, 0),
		Color = IRON,
		Material = Enum.Material.Metal,
		CanCollide = true,
	})
	carPart({
		Name = "RailingBack",
		Size = Vector3.new(21, 4.5, 0.8),
		CFrame = liftCF * CFrame.new(0, 3.25, 10.5),
		Color = IRON,
		Material = Enum.Material.Metal,
		CanCollide = true,
	})

	-- 5. Trigger Zone for Standing on Lift
	local liftZone = Instance.new("Part")
	liftZone.Name = "LiftTriggerZone"
	liftZone.Size = Vector3.new(20, 16, 20)
	liftZone.CFrame = liftCF * CFrame.new(0, 8, 0)
	liftZone.Anchored = true
	liftZone.CanCollide = false
	liftZone.CanQuery = false
	liftZone.CanTouch = false
	liftZone.Transparency = 1
	liftZone.Parent = exitModel

	-- The gate: an iron grille over the open front, up in the gantry until
	-- the lift goes; then it drops shut and rides up with the car.
	local GATE_UP = 30
	local gate = part({
		Name = "LiftGate",
		Size = Vector3.new(21, 4.5, 0.5),
		CFrame = liftCF * CFrame.new(0, 3.25 + GATE_UP, -10.5),
		Color = IRON_LIGHT,
		Material = Enum.Material.DiamondPlate,
		Transparency = 0.15,
	})

	-- The ride: the gate drops, the car (and everyone standing on it) climbs
	-- the shaft with a rumble, and at the top the next floor takes over.
	local RISE, RISE_TIME = 24, 2.8
	local function rise(players: { Player })
		local riders: { { root: BasePart, rel: CFrame } } = {}
		for _, p in ipairs(players) do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and p:GetAttribute("IsDead") ~= true then
				local rel = liftZone.CFrame:PointToObjectSpace(root.Position)
				local h = liftZone.Size / 2 + Vector3.new(1.5, 2, 1.5)
				if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
					root.AssemblyLinearVelocity = Vector3.zero
					root.Anchored = true
					table.insert(riders, { root = root, rel = floor.CFrame:ToObjectSpace(root.CFrame) })
				end
			end
		end
		gate.CanCollide = true
		TweenService:Create(gate, TweenInfo.new(0.45, Enum.EasingStyle.Bounce, Enum.EasingDirection.Out),
			{ CFrame = liftCF * CFrame.new(0, 3.25, -10.5) }):Play()
		task.wait(0.6)
		table.insert(car, gate)
		local start: { [BasePart]: CFrame } = {}
		for _, c in ipairs(car) do start[c] = c.CFrame end
		local floorStart = floor.CFrame
		liftSparks.Rate = 90
		local t0 = os.clock()
		while true do
			local a = math.clamp((os.clock() - t0) / RISE_TIME, 0, 1)
			-- (a slow start, a steady climb, a little settle at the top)
			local k = if a < 0.2 then (a / 0.2) ^ 2 * 0.12 else 0.12 + (a - 0.2) / 0.8 * 0.88
			local up = Vector3.new(0, RISE * k + math.sin(a * 40) * 0.04, 0)
			for c, cf in pairs(start) do
				if c.Parent then c.CFrame = cf + up end
			end
			local floorNow = floorStart + up
			for _, rd in ipairs(riders) do
				if rd.root.Parent then rd.root.CFrame = floorNow * rd.rel end
			end
			if a >= 1 then break end
			RunService.Heartbeat:Wait()
		end
		task.wait(0.25)
	end

	local portals: { Portal } = {}
	-- (the tutorial ends here: its way out is the extraction portal alone)
	local tutorial = RunScope.Get(runId, "Tutorial") == true
	if not tutorial then
		local bb, text = countBoard(liftZone)
		table.insert(portals, { part = liftZone, kind = "descend", bb = bb, text = text, rise = rise })
	end

	-- (the floor's level: every third one offers extraction)
	local d = dungeons[runId]
	local level = if d then d.level else 1
	local extractFloor = level % EXTRACT_EVERY == 0 or tutorial
	if extractFloor then
		-- in front of the lift in the room
		local base = liftCF * CFrame.new(0, 0, -18)
		local zone = buildExtractPortal(CFrame.new(base.Position) * liftCF.Rotation, exitModel)
		local ebb, etext = countBoard(zone)
		table.insert(portals, { part = zone, kind = "extract", bb = ebb, text = etext })
	end
	watchPortals(runId, portals, extractFloor)
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
	Purge = { text = "PURGE SHRINE", sub = "sacrifice a tome", color = Color3.fromRGB(200, 60, 80) },
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

-- (the Neon Arcade's rooms, MapData.arcade: no rubble, stone cover, torch-lit
-- braziers, hanging fire or candles; its props stand on the floor, and its
-- corners burn violet)
local arcadeTheme = false

-- ── The arcade's rooms: no walls, an endless void, a barrier of light ──────
-- Each room is a floating platform in the dark: a lit lip round its edge
-- with a skirt hanging down under it, a low rail of light along the edge
-- and a faint shimmering sheet over it, with an invisible wall in it that
-- stops you leaving. Out in the violet fog round it float islands of voxel
-- stone pouring light, under a vast vortex (arcadeBackdrop): it reads
-- endless, and still a room.
local ARCADE_EDGE = {
	-- (Abyssal Neon: midnight, violet, arcane, ice cyan; amber for the way on)
	base = Color3.fromRGB(42, 46, 82),
	metal = Color3.fromRGB(48, 36, 91),
	cyan = Color3.fromRGB(66, 221, 245),
	purple = Color3.fromRGB(88, 64, 190),
	pink = Color3.fromRGB(120, 87, 255),
	amber = Color3.fromRGB(255, 198, 109),
	tower = Color3.fromRGB(10, 16, 32),
}

local function edgePart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, collide: boolean?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function arcadeEdges(room: RoomData, parent: Instance)
	local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE / 2
	local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE / 2
	local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE / 2
	local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE / 2
	local top = room.floorY + 0.5
	local NEON = Enum.Material.Neon
	-- each side: its middle, its length, which way is out
	local sides = {
		{ mid = Vector3.new((minX + maxX) / 2, 0, minZ), len = maxX - minX, out = -Vector3.zAxis },
		{ mid = Vector3.new((minX + maxX) / 2, 0, maxZ), len = maxX - minX, out = Vector3.zAxis },
		{ mid = Vector3.new(minX, 0, (minZ + maxZ) / 2), len = maxZ - minZ, out = -Vector3.xAxis },
		{ mid = Vector3.new(maxX, 0, (minZ + maxZ) / 2), len = maxZ - minZ, out = Vector3.xAxis },
	}
	for _, s in ipairs(sides) do
		local at = Vector3.new(s.mid.X, top, s.mid.Z)
		-- (+Z of this frame points out of the room; X runs along the side)
		local cf = CFrame.lookAt(at, at - s.out)
		local L = s.len + 1.6
		-- the lip and the skirt hanging under it
		edgePart(parent, Vector3.new(L, 4, 0.8), cf * CFrame.new(0, -2, 0.4), ARCADE_EDGE.base)
		edgePart(parent, Vector3.new(L, 0.3, 0.9), cf * CFrame.new(0, 0.15, 0.45), ARCADE_EDGE.metal)
		edgePart(parent, Vector3.new(L, 0.12, 0.14), cf * CFrame.new(0, 0.34, 0.85), ARCADE_EDGE.cyan, NEON)
		edgePart(parent, Vector3.new(L, 0.1, 0.1), cf * CFrame.new(0, -3.9, 0.82), ARCADE_EDGE.purple, NEON)
		-- the barrier: a low rail of light, a faint sheet over it, and the wall
		-- you can't see in it
		edgePart(parent, Vector3.new(L, 0.18, 0.18), cf * CFrame.new(0, 1.2, 0.5), ARCADE_EDGE.pink, NEON)
		edgePart(parent, Vector3.new(L, 0.1, 0.1), cf * CFrame.new(0, 0.7, 0.5), ARCADE_EDGE.purple, NEON)
		local sheet = edgePart(parent, Vector3.new(L, 5, 0.1), cf * CFrame.new(0, 3.6, 0.5), ARCADE_EDGE.purple, Enum.Material.ForceField)
		sheet.Transparency = 0.4
		local wall = edgePart(parent, Vector3.new(L, 30, 1), cf * CFrame.new(0, 15, 0.6), ARCADE_EDGE.base, nil, true)
		wall.Transparency = 1
		wall.Name = "ArcadeBarrier"
		-- posts along it, every two tiles
		local n = math.max(1, math.floor(s.len / (FLOOR_SIZE * 2)))
		for k = 0, n do
			local x = -s.len / 2 + k * s.len / n
			edgePart(parent, Vector3.new(0.4, 1.6, 0.4), cf * CFrame.new(x, 0.8, 0.5), ARCADE_EDGE.metal)
			edgePart(parent, Vector3.new(0.5, 0.3, 0.5), cf * CFrame.new(x, 1.7, 0.5), ARCADE_EDGE.cyan, NEON)
		end
	end
end

-- The void round a room, after the art: floating islands of dark voxel stone
-- (a lit rim on top, jagged blocks hanging under them), waterfalls of blue
-- light pouring off their edges into the fog, bridges between some, arcade
-- cabinets and a "GAME OVER?" sign standing on them, and high over it all a
-- vast swirling vortex ringed with drifting blocks. (Nothing here collides
-- or casts a shadow; the fog is the map's, MapData.)
local VOID_STONE = Color3.fromRGB(16, 14, 34)
local VOID_STONE_DARK = Color3.fromRGB(10, 9, 24)
local FALL_BLUE = Color3.fromRGB(70, 150, 255)

-- An island: a slab, its rim of light, voxel blocks hanging under it.
local function voidIsland(parent: Instance, cf: CFrame, w: number, d: number, rng: Random)
	local NEON = Enum.Material.Neon
	edgePart(parent, Vector3.new(w, 3, d), cf * CFrame.new(0, -1.5, 0), VOID_STONE)
	-- the rim: a line of light along two or more edges
	for _, e in ipairs({ { 0, -d / 2, w, 0 }, { 0, d / 2, w, 0 }, { -w / 2, 0, d, 90 }, { w / 2, 0, d, 90 } }) do
		if rng:NextNumber() < 0.75 then
			edgePart(parent, Vector3.new(e[3], 0.15, 0.2), cf * CFrame.new(e[1], 0.05, e[2]) * CFrame.Angles(0, math.rad(e[4]), 0),
				if rng:NextNumber() < 0.6 then ARCADE_EDGE.pink else ARCADE_EDGE.cyan, NEON)
		end
	end
	-- the underside: blocks, each smaller and lower, ragged like stalactites
	local layers = rng:NextInteger(3, 5)
	for l = 1, layers do
		local shrink = 1 - l / (layers + 1.5)
		for _ = 1, rng:NextInteger(3, 6) do
			local bw = w * shrink * rng:NextNumber(0.25, 0.55)
			local bd = d * shrink * rng:NextNumber(0.25, 0.55)
			local bh = rng:NextNumber(3, 7)
			local x = rng:NextNumber(-1, 1) * (w * shrink - bw) / 2
			local z = rng:NextNumber(-1, 1) * (d * shrink - bd) / 2
			edgePart(parent, Vector3.new(bw, bh, bd), cf * CFrame.new(x, -3 - (l - 1) * 4 - bh / 2, z), if l % 2 == 0 then VOID_STONE_DARK else VOID_STONE)
		end
	end
	-- a few blocks stepped on top, for the voxel look
	for _ = 1, rng:NextInteger(1, 3) do
		local s = rng:NextNumber(2, 5)
		edgePart(parent, Vector3.new(s, s * 0.6, s), cf * CFrame.new(rng:NextNumber(-0.35, 0.35) * w, s * 0.3, rng:NextNumber(-0.35, 0.35) * d), VOID_STONE)
	end
end

-- A waterfall of light pouring off `at` down into the fog.
local function lightFall(parent: Instance, at: Vector3, height: number)
	local NEON = Enum.Material.Neon
	local core = edgePart(parent, Vector3.new(1.2, height, 1.2), CFrame.new(at - Vector3.new(0, height / 2, 0)), FALL_BLUE, NEON)
	core.Transparency = 0.25
	local veil = edgePart(parent, Vector3.new(2.4, height, 2.4), CFrame.new(at - Vector3.new(0, height / 2, 0)), FALL_BLUE, NEON)
	veil.Transparency = 0.75
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	spray.Color = ColorSequence.new(Color3.fromRGB(180, 220, 255), FALL_BLUE)
	spray.LightEmission = 1
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	spray.Lifetime = NumberRange.new(1, 2)
	spray.Speed = NumberRange.new(10, 16)
	spray.EmissionDirection = Enum.NormalId.Bottom
	spray.SpreadAngle = Vector2.new(8, 8)
	spray.Rate = 3
	local top = edgePart(parent, Vector3.new(1.2, 0.2, 1.2), CFrame.new(at), FALL_BLUE, NEON)
	spray.Parent = top
end

-- The vortex: a vast swirl (it turns: PortalSpin) in the sky, its face to
-- the room, rings of dark blocks drifting round it.
local function vortex(parent: Instance, at: Vector3, face: Vector3, size: number, rng: Random)
	local cf = CFrame.lookAt(at, face)
	local disc = edgePart(parent, Vector3.new(size, size, 0.2), cf, Color3.fromRGB(40, 20, 90))
	disc.Transparency = 1
	for _, spec in ipairs({ { size, 40, Color3.fromRGB(170, 120, 255), 0.1 }, { size * 0.55, -70, Color3.fromRGB(220, 190, 255), 0.35 } }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = Enum.NormalId.Front
		sg.LightInfluence = 0
		sg.Brightness = 1.6
		sg.CanvasSize = Vector2.new(512, 512)
		sg.MaxDistance = 1000
		local img = Instance.new("ImageLabel")
		img.BackgroundTransparency = 1
		img.AnchorPoint = Vector2.new(0.5, 0.5)
		img.Position = UDim2.fromScale(0.5, 0.5)
		img.Size = UDim2.fromScale(spec[1] / size, spec[1] / size)
		img.Image = ArcadeKit.TEX.swirl
		img.ImageColor3 = spec[3]
		img.ImageTransparency = spec[4]
		img:SetAttribute("Spin", spec[2])
		img:AddTag("PortalSwirl")
		img.Parent = sg
		sg.Parent = disc
	end
	-- drifting rings of blocks round its rim
	for ringN = 1, 3 do
		local r = size * (0.42 + ringN * 0.07)
		local n = 18 + ringN * 6
		for k = 0, n - 1 do
			if rng:NextNumber() < 0.7 then
				local a = k / n * math.pi * 2 + rng:NextNumber(-0.05, 0.05)
				local s = rng:NextNumber(2, 6)
				local p = cf * CFrame.new(math.cos(a) * r, math.sin(a) * r, rng:NextNumber(-4, 4))
				edgePart(parent, Vector3.new(s, s * rng:NextNumber(0.6, 1.4), s), p * CFrame.Angles(rng:NextNumber(0, 1), rng:NextNumber(0, 1), a),
					if k % 5 == 0 then Color3.fromRGB(60, 40, 140) else VOID_STONE)
			end
		end
	end
end

-- A big neon sign standing on an island: "GAME OVER?" in pink pixels.
local function gameOverSign(parent: Instance, cf: CFrame)
	local board = edgePart(parent, Vector3.new(14, 9, 0.6), cf * CFrame.new(0, 7, 0), VOID_STONE_DARK)
	edgePart(parent, Vector3.new(14.4, 0.25, 0.3), cf * CFrame.new(0, 11.6, -0.3), ARCADE_EDGE.pink, Enum.Material.Neon)
	edgePart(parent, Vector3.new(14.4, 0.25, 0.3), cf * CFrame.new(0, 2.4, -0.3), ARCADE_EDGE.pink, Enum.Material.Neon)
	for _, x in ipairs({ -7.1, 7.1 }) do
		edgePart(parent, Vector3.new(0.25, 9.4, 0.3), cf * CFrame.new(x, 7, -0.3), ARCADE_EDGE.pink, Enum.Material.Neon)
		edgePart(parent, Vector3.new(0.6, 3, 0.6), cf * CFrame.new(x * 0.6, 1.5, 0), VOID_STONE)
	end
	local sg = Instance.new("SurfaceGui")
	sg.Face = Enum.NormalId.Front
	sg.LightInfluence = 0
	sg.Brightness = 2.2
	sg.CanvasSize = Vector2.new(560, 360)
	sg.MaxDistance = 600
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.fromScale(1, 1)
	text.Font = Enum.Font.Arcade
	text.Text = "GAME\nOVER?"
	text.TextScaled = true
	text.TextColor3 = Color3.fromRGB(255, 110, 220)
	text.Parent = sg
	sg.Parent = board
end

local function arcadeBackdrop(room: RoomData, parent: Instance, rng: Random)
	local cx = (room.gx + (room.w - 1) / 2) * FLOOR_SIZE
	local cz = (room.gz + (room.d - 1) / 2) * FLOOR_SIZE
	local half = room.w * FLOOR_SIZE / 2
	local y0 = room.floorY
	local center = Vector3.new(cx, y0, cz)
	-- the islands, in a loose ring round the room (none behind the portals'
	-- wall too close: the vortex hangs there)
	local count = 9
	local spots: { CFrame } = {}
	for k = 0, count - 1 do
		local a = (k + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local dist = half + rng:NextNumber(30, 70)
		local at = Vector3.new(cx + math.cos(a) * dist, y0 + rng:NextNumber(-14, 10), cz + math.sin(a) * dist)
		local cf = CFrame.lookAt(at, Vector3.new(cx, at.Y, cz))
		local w, d = rng:NextNumber(16, 30), rng:NextNumber(14, 26)
		voidIsland(parent, cf, w, d, rng)
		table.insert(spots, cf)
		-- a waterfall or two off its edge
		for _ = 1, rng:NextInteger(1, 2) do
			local edge = cf * CFrame.new(rng:NextNumber(-0.4, 0.4) * w, -1, (if rng:NextNumber() < 0.5 then -1 else 1) * (d / 2 + 0.6))
			lightFall(parent, edge.Position, rng:NextNumber(50, 80))
		end
		-- what stands on it: a cabinet or two facing the room, or the sign
		if k == 2 then
			gameOverSign(parent, cf)
		elseif rng:NextNumber() < 0.6 then
			local cab = ArcadeKit.Build("Arcade_Cabinet")
			if cab then
				for _, p in ipairs(cab:GetDescendants()) do
					if p:IsA("BasePart") then p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow, p.Anchored = false, false, false, false, true end
				end
				cab:PivotTo(cf * CFrame.new(rng:NextNumber(-4, 4), 0, -d * 0.2))
				cab:ScaleTo(1.6)
				cab.Parent = parent
			end
		end
	end
	-- bridges between neighbouring islands, now and then
	for k = 1, #spots do
		local a, b = spots[k].Position, spots[k % #spots + 1].Position
		if rng:NextNumber() < 0.35 and math.abs(a.Y - b.Y) < 8 then
			local mid = (a + b) / 2
			local len = (b - a).Magnitude
			edgePart(parent, Vector3.new(4, 1, len), CFrame.lookAt(mid, b) * CFrame.new(0, -0.5, 0), VOID_STONE)
			edgePart(parent, Vector3.new(0.15, 0.15, len), CFrame.lookAt(mid, b) * CFrame.new(1.9, 0.05, 0), ARCADE_EDGE.pink, Enum.Material.Neon)
		end
	end
	-- the vortex, high and far, off to one side behind the way in
	local vat = Vector3.new(cx - half - 90, y0 + 55, cz + (if rng:NextNumber() < 0.5 then -1 else 1) * half * 0.8)
	vortex(parent, vat, center + Vector3.new(0, 20, 0), 120, rng)
end

-- The arcade's floor: one platform per room, not a scatter of tiles, kept
-- quiet so the fight reads: a dark field, dim seams, and bright lines only
-- for boundaries (the arena's ring, the edge band, the way to the portals). (Its top is the tiles' height,
-- floorY + 0.5, so the portals and props stand on it as before.)
local function arcadeFloor(room: RoomData, parent: Instance)
	local cx = (room.gx + (room.w - 1) / 2) * FLOOR_SIZE
	local cz = (room.gz + (room.d - 1) / 2) * FLOOR_SIZE
	local W, D = room.w * FLOOR_SIZE, room.d * FLOOR_SIZE
	local top = room.floorY + 0.5
	local NEON = Enum.Material.Neon
	local slab = edgePart(parent, Vector3.new(W, 1, D), CFrame.new(cx, top - 0.5, cz), ARCADE_EDGE.base, nil, true)
	slab.Name = "ArcadeFloor"
	slab.CanQuery = true
	local y = top + 0.02
	local function line(a: Vector3, b: Vector3, width: number, color: Color3, transparency: number)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		if len < 0.1 then return end
		local p = edgePart(parent, Vector3.new(width, 0.04, len), CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z)), color, NEON)
		p.Transparency = transparency
	end
	-- Quiet underfoot: the fight is what should read. A dark field where you
	-- fight (darker than the rim, so bodies stand out against it), the grid
	-- barely there, and the only strong lines are boundaries: a thin ring
	-- marking the arena and a band round the edge. Lines are plastic, not
	-- neon (crisp, no bloom), but for the few that mark a boundary.
	local PLAIN = Enum.Material.SmoothPlastic
	local function flat(a: Vector3, b: Vector3, width: number, color: Color3, transparency: number, glow: boolean?)
		local mid = (a + b) / 2
		local len = (b - a).Magnitude
		if len < 0.1 then return end
		local p = edgePart(parent, Vector3.new(width, 0.04, len), CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(b.X, y, b.Z)),
			color, if glow then NEON else PLAIN)
		p.Transparency = transparency
	end
	local _ = line
	local c = Vector3.new(cx, 0, cz)
	local R = math.min(W, D) * 0.42
	-- the dark field: the combat area, a shade under the rest
	local field = edgePart(parent, Vector3.new(W - 14, 0.03, D - 14), CFrame.new(cx, top + 0.005, cz), Color3.fromRGB(30, 34, 64), PLAIN)
	field.Transparency = 0
	-- the grid: dim seams only
	local seam = Color3.fromRGB(70, 58, 128)
	for i = 1, room.w - 1 do
		local x = cx - W / 2 + i * FLOOR_SIZE
		flat(Vector3.new(x, 0, cz - D / 2), Vector3.new(x, 0, cz + D / 2), 0.1, seam, 0.35)
	end
	for j = 1, room.d - 1 do
		local z = cz - D / 2 + j * FLOOR_SIZE
		flat(Vector3.new(cx - W / 2, 0, z), Vector3.new(cx + W / 2, 0, z), 0.1, seam, 0.35)
	end
	-- the arena's boundary: one thin ring, softly lit
	local N = 40
	for k = 0, N - 1 do
		local a1, a2 = k / N * math.pi * 2, (k + 1) / N * math.pi * 2
		flat(c + Vector3.new(math.cos(a1), 0, math.sin(a1)) * R, c + Vector3.new(math.cos(a2), 0, math.sin(a2)) * R, 0.16, ARCADE_EDGE.pink, 0.55, true)
	end
	-- the edge band, just inside the barrier
	local inset = 3
	for _, s in ipairs({
		{ Vector3.new(cx - W / 2 + inset, 0, cz - D / 2 + inset), Vector3.new(cx + W / 2 - inset, 0, cz - D / 2 + inset) },
		{ Vector3.new(cx - W / 2 + inset, 0, cz + D / 2 - inset), Vector3.new(cx + W / 2 - inset, 0, cz + D / 2 - inset) },
		{ Vector3.new(cx - W / 2 + inset, 0, cz - D / 2 + inset), Vector3.new(cx - W / 2 + inset, 0, cz + D / 2 - inset) },
		{ Vector3.new(cx + W / 2 - inset, 0, cz - D / 2 + inset), Vector3.new(cx + W / 2 - inset, 0, cz + D / 2 - inset) },
	}) do
		flat(s[1], s[2], 0.2, ARCADE_EDGE.cyan, 0.5, true)
	end
	-- the path to the portals: faint chevrons down the middle toward +X
	for k = 1, 3 do
		local x = cx + R + 4 + k * 3.5
		if x < cx + W / 2 - inset - 1 then
			flat(Vector3.new(x - 1.4, 0, cz - 2), Vector3.new(x, 0, cz), 0.25, ARCADE_EDGE.amber, 0.35)
			flat(Vector3.new(x - 1.4, 0, cz + 2), Vector3.new(x, 0, cz), 0.25, ARCADE_EDGE.amber, 0.35)
		end
	end
end


-- The arcade's props, laid out the same way in every room, mirrored side to
-- side (you come in on the -X wall and leave by the portals on the +X wall):
-- a row of cabinets facing in along each side wall, hologram spectators
-- cheering between them, and the scoreboard over the entrance.
local function arcadeProps(room: RoomData, propsFolder: Folder)
	local byName: { [string]: Instance } = {}
	for _, c in ipairs(assets.cosmetics) do byName[c.Name] = c end
	local minX, maxX = room.gx, room.gx + room.w - 1
	local minZ, maxZ = room.gz, room.gz + room.d - 1
	local y = room.floorY + 0.5
	local inset = 2.5
	local zN = minZ * FLOOR_SIZE - FLOOR_SIZE / 2 + inset
	local zS = maxZ * FLOOR_SIZE + FLOOR_SIZE / 2 - inset
	local x0 = minX * FLOOR_SIZE - FLOOR_SIZE / 2
	local span = room.w * FLOOR_SIZE
	local function put(name: string, x: number, z: number, rotY: number)
		local t = byName[name]
		if t then spawnInstance(t, CFrame.new(x, y, z) * CFrame.Angles(0, math.rad(rotY), 0), propsFolder, true) end
	end
	-- Fights get the crowd; quiet rooms stay quiet (the shop, the rest).
	local busy = room.roomType == "Combat" or room.roomType == "Elite" or room.roomType == "Boss" or room.roomType == "Start"
	for _, k in ipairs(if busy then { 0.25, 0.75 } else { 0.5 }) do
		local x = x0 + span * k
		put("Arcade_Cabinet", x - 2, zN, 180)
		put("Arcade_Cabinet", x + 2, zN, 180)
		put("Arcade_Cabinet", x - 2, zS, 0)
		put("Arcade_Cabinet", x + 2, zS, 0)
	end
	if busy then
		put("Holo_Spectator_Cheer", x0 + span * 0.5 - 2, zN, 180)
		put("Holo_Spectator", x0 + span * 0.5 + 2, zN, 180)
		put("Holo_Spectator", x0 + span * 0.5 - 2, zS, 0)
		put("Holo_Spectator_Cheer", x0 + span * 0.5 + 2, zS, 0)
	end
	-- the scoreboard high over the way in, facing the room
	local zc = (room.gz + (room.d - 1) / 2) * FLOOR_SIZE
	put("Score_Board", x0 + inset, zc, -90)
end

-- ── The Prison of Souls' dressing (MapData.prison) ─────────────────────────
-- Built from parts, so it needs nothing in the place: on the walls (only
-- where there is wall: never across a doorway) barred cell fronts with a
-- prisoner's bones slumped behind them, shackles hanging on chains, and
-- lanterns burning a sickly green; in the room an iron cage hanging from out
-- of sight, floor grates breathing green mist, crates and barrels stacked in
-- the corners, bones scattered about. (No lights: the green is neon.)
local prisonTheme = false
local PRISON = {
	iron = Color3.fromRGB(46, 50, 52),
	rust = Color3.fromRGB(88, 62, 46),
	wood = Color3.fromRGB(92, 66, 44),
	woodDark = Color3.fromRGB(60, 42, 30),
	bone = Color3.fromRGB(214, 206, 180),
	soul = Color3.fromRGB(110, 255, 170),
	glass = Color3.fromRGB(150, 255, 190),
}

local function prisonPart(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?, collide: boolean?): BasePart
	local p = Instance.new("Part")
	if shape then p.Shape = shape end
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanTouch = false
	p.CanQuery = collide == true
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local UPRIGHT = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder standing up)

-- A heap of bones on the floor at `cf` (a skull, a ribcage, long bones).
local function bones(parent: Instance, cf: CFrame, rng: Random)
	prisonPart(parent, Vector3.one * 0.9, cf * CFrame.new(0, 0.45, 0) * CFrame.Angles(0, rng:NextNumber(0, 6), math.rad(15)), PRISON.bone, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	prisonPart(parent, Vector3.new(0.5, 0.4, 0.3), cf * CFrame.new(0, 0.25, -0.4), PRISON.bone, Enum.Material.SmoothPlastic)
	for k = 1, 3 do
		prisonPart(parent, Vector3.new(0.18, 0.18, 1.6), cf * CFrame.new(rng:NextNumber(-1, 1), 0.1, rng:NextNumber(-0.3, 1)) * CFrame.Angles(0, rng:NextNumber(0, 6), 0),
			PRISON.bone, Enum.Material.SmoothPlastic)
	end
	for k = 1, 3 do
		prisonPart(parent, Vector3.new(1.2, 0.12, 0.12), cf * CFrame.new(0.9, 0.5 + k * 0.22, 0.6) * CFrame.Angles(0, math.rad(30), math.rad(10)), PRISON.bone, Enum.Material.SmoothPlastic)
	end
end

-- A barred cell front standing out from the wall (`cf` on the floor at the
-- wall's face, -Z into the room), the bones of who's left in it.
local function cellFront(parent: Instance, cf: CFrame, rng: Random)
	local w, h, depth = 8, 9, 2.6
	local front = cf * CFrame.new(0, 0, -depth)
	prisonPart(parent, Vector3.new(w, 0.4, 0.4), front * CFrame.new(0, h, 0), PRISON.iron)
	prisonPart(parent, Vector3.new(w, 0.3, 0.3), front * CFrame.new(0, 0.2, 0), PRISON.iron)
	prisonPart(parent, Vector3.new(w, 0.25, 0.25), front * CFrame.new(0, h * 0.55, 0), PRISON.rust)
	for k = 0, 8 do
		local x = -w / 2 + 0.3 + k * (w - 0.6) / 8
		prisonPart(parent, Vector3.new(h, 0.22, 0.22), front * CFrame.new(x, h / 2, 0) * UPRIGHT, PRISON.iron, nil, Enum.PartType.Cylinder)
	end
	-- the sides back to the wall, and the bars' collision (you can't walk in)
	for _, side in ipairs({ -1, 1 }) do
		prisonPart(parent, Vector3.new(0.5, h, depth), cf * CFrame.new(side * w / 2, h / 2, -depth / 2), PRISON.iron)
	end
	local block = prisonPart(parent, Vector3.new(w, h, 0.4), front * CFrame.new(0, h / 2, 0), PRISON.iron, nil, nil, true)
	block.Transparency = 1
	bones(parent, cf * CFrame.new(rng:NextNumber(-2, 2), 0, -depth * 0.45), rng)
end

-- Shackles hanging on two chains from a ring in the wall.
local function shackles(parent: Instance, cf: CFrame)
	prisonPart(parent, Vector3.new(1.6, 0.3, 0.4), cf * CFrame.new(0, 7, -0.2), PRISON.iron)
	for _, side in ipairs({ -1, 1 }) do
		for k = 0, 4 do
			prisonPart(parent, Vector3.new(0.18, 0.5, 0.32), cf * CFrame.new(side * 0.6, 6.6 - k * 0.48, -0.3) * CFrame.Angles(0, if k % 2 == 0 then 0 else math.rad(90), 0), PRISON.iron)
		end
		prisonPart(parent, Vector3.new(0.18, 0.7, 0.7), cf * CFrame.new(side * 0.6, 4.0, -0.3) * CFrame.Angles(0, math.rad(90), 0), PRISON.rust, nil, Enum.PartType.Cylinder)
	end
end

-- A wall lantern: a bracket, an iron cage round green glass.
local function lantern(parent: Instance, cf: CFrame)
	local at = cf * CFrame.new(0, 8, -0.9)
	prisonPart(parent, Vector3.new(0.3, 0.3, 1.2), cf * CFrame.new(0, 8.9, -0.5), PRISON.iron)
	prisonPart(parent, Vector3.new(0.9, 1.2, 0.9), at, PRISON.glass, Enum.Material.Neon).Transparency = 0.15
	prisonPart(parent, Vector3.new(1.1, 0.2, 1.1), at * CFrame.new(0, 0.7, 0), PRISON.iron)
	prisonPart(parent, Vector3.new(1.1, 0.2, 1.1), at * CFrame.new(0, -0.7, 0), PRISON.iron)
	for _, x in ipairs({ -0.5, 0.5 }) do
		for _, z in ipairs({ -0.5, 0.5 }) do
			prisonPart(parent, Vector3.new(0.1, 1.3, 0.1), at * CFrame.new(x, 0, z), PRISON.iron)
		end
	end
	-- a glow on the wall behind it
	local halo = prisonPart(parent, Vector3.new(0.05, 3.5, 3.5), cf * CFrame.new(0, 8, -0.05) * CFrame.Angles(0, math.rad(90), 0), PRISON.soul, Enum.Material.Neon, Enum.PartType.Cylinder)
	halo.Transparency = 0.82
end

-- An iron cage hanging on a chain from out of sight.
local function hangingCage(parent: Instance, at: Vector3, rng: Random)
	local base = CFrame.new(at) * CFrame.Angles(0, rng:NextNumber(0, 6), 0)
	local h, r = 5, 2
	prisonPart(parent, Vector3.new(0.3, r * 2 + 0.4, r * 2 + 0.4), base * UPRIGHT, PRISON.iron, nil, Enum.PartType.Cylinder)
	prisonPart(parent, Vector3.new(0.3, r * 2 + 0.4, r * 2 + 0.4), base * CFrame.new(0, h, 0) * UPRIGHT, PRISON.iron, nil, Enum.PartType.Cylinder)
	for k = 0, 9 do
		local a = k / 10 * math.pi * 2
		prisonPart(parent, Vector3.new(0.16, h, 0.16), base * CFrame.new(math.cos(a) * r, h / 2, math.sin(a) * r), PRISON.iron)
	end
	prisonPart(parent, Vector3.new(0.25, 40, 0.25), base * CFrame.new(0, h + 20, 0), PRISON.iron)
	-- someone's still in it
	prisonPart(parent, Vector3.one * 0.8, base * CFrame.new(0.4, 1.2, 0), PRISON.bone, Enum.Material.SmoothPlastic, Enum.PartType.Ball)
	prisonPart(parent, Vector3.new(1, 0.15, 0.15), base * CFrame.new(-0.3, 0.5, 0.3) * CFrame.Angles(0, 0.6, 0), PRISON.bone, Enum.Material.SmoothPlastic)
end

-- A floor grate, green mist breathing up out of it.
local function grate(parent: Instance, at: Vector3)
	local cf = CFrame.new(at)
	prisonPart(parent, Vector3.new(5, 0.1, 5), cf * CFrame.new(0, 0.02, 0), Color3.fromRGB(6, 20, 14), Enum.Material.SmoothPlastic)
	prisonPart(parent, Vector3.new(4.4, 0.08, 4.4), cf * CFrame.new(0, 0.05, 0), PRISON.soul, Enum.Material.Neon).Transparency = 0.7
	for k = -2, 2 do
		prisonPart(parent, Vector3.new(5, 0.2, 0.25), cf * CFrame.new(0, 0.12, k), PRISON.iron)
		prisonPart(parent, Vector3.new(0.25, 0.2, 5), cf * CFrame.new(k, 0.12, 0), PRISON.iron)
	end
	local holder = prisonPart(parent, Vector3.new(4, 0.1, 4), cf * CFrame.new(0, 0.2, 0), PRISON.soul)
	holder.Transparency = 1
	local mist = Instance.new("ParticleEmitter")
	mist.Name = "GrateMist"
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(120, 255, 180), Color3.fromRGB(40, 120, 90))
	mist.LightEmission = 0.4
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.75), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 5) })
	mist.Lifetime = NumberRange.new(2.5, 4)
	mist.Speed = NumberRange.new(0.6, 1.4)
	mist.EmissionDirection = Enum.NormalId.Top
	mist.Shape = Enum.ParticleEmitterShape.Box
	mist.Rate = 2
	mist.Parent = holder
end

-- Crates and a barrel or two, stacked in a corner (they're solid).
local function stores(parent: Instance, cf: CFrame, rng: Random)
	for k = 0, rng:NextInteger(1, 3) do
		local s = rng:NextNumber(2.6, 3.4)
		local at = cf * CFrame.new(rng:NextNumber(-2.5, 2.5), s / 2, rng:NextNumber(-2.5, 2.5)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0)
		if k == 3 then at = cf * CFrame.new(0, 3.2 + s / 2, 0) end
		prisonPart(parent, Vector3.one * s, at, PRISON.wood, Enum.Material.WoodPlanks, nil, true)
		prisonPart(parent, Vector3.new(s + 0.08, 0.3, s + 0.08), at * CFrame.new(0, s * 0.3, 0), PRISON.woodDark, Enum.Material.Wood)
		prisonPart(parent, Vector3.new(s + 0.08, 0.3, s + 0.08), at * CFrame.new(0, -s * 0.3, 0), PRISON.woodDark, Enum.Material.Wood)
	end
	local b = cf * CFrame.new(rng:NextNumber(-3, 3), 1.6, rng:NextNumber(-3, 3))
	prisonPart(parent, Vector3.new(3.2, 2.4, 2.4), b * UPRIGHT, PRISON.woodDark, Enum.Material.Wood, Enum.PartType.Cylinder, true)
	for _, y in ipairs({ -1, 1 }) do
		prisonPart(parent, Vector3.new(0.2, 2.5, 2.5), b * CFrame.new(0, y * 1.0, 0) * UPRIGHT, PRISON.iron, nil, Enum.PartType.Cylinder)
	end
end

local function prisonDecor(room: RoomData, propsFolder: Folder, rng: Random)
	if room.w < 3 or room.d < 3 then return end
	local folder = Instance.new("Folder")
	folder.Name = "PrisonDecor"
	folder.Parent = propsFolder
	local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE / 2
	local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE / 2
	local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE / 2
	local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE / 2
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local fy = room.floorY + 0.5
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { propsFolder }

	-- A spot on a wall: from inside the room, out toward side `out` at `t`
	-- (0..1 along it); the wall's face as a frame (-Z into the room), or nil
	-- where there's no wall (a doorway).
	local function wallAt(out: Vector3, t: number): CFrame?
		local along = Vector3.new(out.Z, 0, -out.X)
		local span = if out.X ~= 0 then maxZ - minZ else maxX - minX
		local halfOut = if out.X ~= 0 then (maxX - minX) / 2 else (maxZ - minZ) / 2
		local from = Vector3.new(cx, fy + 4, cz) + along * (t - 0.5) * (span - 10) + out * (halfOut - 8)
		local hit = Workspace:Raycast(from, out * 14, params)
		if not hit or hit.Normal:Dot(-out) < 0.8 then return nil end
		-- (and wall a little to either side too: not the edge of a doorway)
		for _, s in ipairs({ -4.5, 4.5 }) do
			local h2 = Workspace:Raycast(from + along * s, out * 14, params)
			if not h2 or math.abs(h2.Distance - hit.Distance) > 1 then return nil end
		end
		local face = Vector3.new(hit.Position.X, fy, hit.Position.Z)
		return CFrame.lookAt(face, face - out)
	end
	local sides = { Vector3.xAxis, -Vector3.xAxis, Vector3.zAxis, -Vector3.zAxis }
	-- cell fronts on two walls, shackles and lanterns spread round them
	local used: { [string]: boolean } = {}
	local function place(kind: string, count: number, slots: { number })
		local placed = 0
		for _ = 1, 12 do
			if placed >= count then break end
			local si = rng:NextInteger(1, 4)
			local t = slots[rng:NextInteger(1, #slots)]
			local key = si .. ":" .. t
			if used[key] then continue end
			local cf = wallAt(sides[si], t)
			if cf then
				used[key] = true
				placed += 1
				if kind == "cell" then cellFront(folder, cf, rng)
				elseif kind == "shackles" then shackles(folder, cf)
				else lantern(folder, cf) end
			end
		end
	end
	local busy = room.roomType == "Combat" or room.roomType == "Elite" or room.roomType == "Start"
	place("cell", if busy then 2 else 1, { 0.25, 0.75 })
	place("lantern", 4, { 0.1, 0.5, 0.9 })
	place("shackles", 2, { 0.1, 0.4, 0.6, 0.9 })

	-- in the room: a cage over one side, a grate or two, stores in corners,
	-- bones about (clear of the middle, where the reward floats)
	if busy and room.w >= 6 and room.d >= 6 then
		local side = if rng:NextNumber() < 0.5 then -1 else 1
		hangingCage(folder, Vector3.new(cx + side * (maxX - minX) * 0.28, fy + 11, cz + rng:NextNumber(-1, 1) * (maxZ - minZ) * 0.2), rng)
	end
	for _ = 1, rng:NextInteger(1, 2) do
		local gx = cx + (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.2, 0.35) * (maxX - minX)
		local gz = cz + (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(0.2, 0.35) * (maxZ - minZ)
		grate(folder, Vector3.new(gx, fy, gz))
	end
	local corners = {
		Vector3.new(minX + 7, fy, minZ + 7), Vector3.new(maxX - 7, fy, minZ + 7),
		Vector3.new(minX + 7, fy, maxZ - 7), Vector3.new(maxX - 7, fy, maxZ - 7),
	}
	for k = 1, 2 do
		local c = table.remove(corners, rng:NextInteger(1, #corners)) :: Vector3
		-- only on open floor
		local hit = Workspace:Raycast(c + Vector3.new(0, 12, 0), Vector3.new(0, -16, 0), params)
		if hit and math.abs(hit.Position.Y - fy) < 1.5 then
			if k == 1 then stores(folder, CFrame.new(hit.Position), rng) else bones(folder, CFrame.new(hit.Position), rng) end
		end
	end
	for _ = 1, 2 do
		local at = Vector3.new(cx + rng:NextNumber(-0.4, 0.4) * (maxX - minX), fy, cz + rng:NextNumber(-0.4, 0.4) * (maxZ - minZ))
		if (at - Vector3.new(cx, fy, cz)).Magnitude > 12 then bones(folder, CFrame.new(at), rng) end
	end
end

-- ── The Infernal Keep (MapData "keep": KeepKit's pieces) ────────────────────
-- After its concept art: fire pedestals round each room's sigil dais, lava
-- pits sunk in two corners of the bigger rooms (their floor cells left open;
-- chains slung over them between stone posts; an invisible fence keeps
-- everyone out), the boss's demon-skull gate on a wall of its arena, and
-- outside the walls a lava sea far below with black spires rising from it.
local keepTheme = false
type Pit = { room: RoomData, cells: { string }, center: Vector3, size: Vector2, out: Vector2 }
local keepPits: { Pit } = {}
-- Per run: where the pits are ({ minX, maxX, minZ, maxZ }), so no mob spawns in one.
local keepBlocked: { [string]: { { number } } } = {}
local PIT_DEPTH = 9

function DungeonGenerator.Blocked(runId: string?): { { number } }
	return (runId and keepBlocked[runId]) or {}
end

-- Two opposite corners of each bigger room (not the boss's: its arena has
-- its own lava), 2 × 2 cells each, clear of doorways and stairs. Returns the
-- cells to leave without floor.
local keepDoors: { Vector3 } = {} -- (this floor's doorways: the boss gate keeps clear of them)
local function planKeepPits(rooms: { RoomData }, doorways: { DoorwayData }, stairs: { StairData }, rng: Random): { [string]: boolean }
	table.clear(keepPits)
	table.clear(keepDoors)
	for _, dw in ipairs(doorways) do table.insert(keepDoors, dw.position) end
	local cells: { [string]: boolean } = {}
	for _, room in ipairs(rooms) do
		if room.roomType == "Boss" or room.w < 9 or room.d < 9 then continue end
		local minX, maxX = room.gx, room.gx + room.w - 1
		local minZ, maxZ = room.gz, room.gz + room.d - 1
		local corners = if rng:NextInteger(0, 1) == 0
			then { { minX, minZ, -1, -1 }, { maxX - 1, maxZ - 1, 1, 1 } }
			else { { maxX - 1, minZ, 1, -1 }, { minX, maxZ - 1, -1, 1 } }
		for _, c in ipairs(corners) do
			local x0, z0 = c[1], c[2]
			local center = Vector3.new((x0 + 0.5) * FLOOR_SIZE, room.floorY, (z0 + 0.5) * FLOOR_SIZE)
			local clear = true
			for _, dw in ipairs(doorways) do
				if Vector2.new(dw.position.X - center.X, dw.position.Z - center.Z).Magnitude < 32 then clear = false break end
			end
			for _, st in ipairs(stairs) do
				local q = st.cframe.Position
				if Vector2.new(q.X - center.X, q.Z - center.Z).Magnitude < 36 then clear = false break end
			end
			if clear then
				local list = {}
				for dx = 0, 1 do
					for dz = 0, 1 do
						local k = (x0 + dx) .. "_" .. (z0 + dz)
						cells[k] = true
						table.insert(list, k)
					end
				end
				table.insert(keepPits, { room = room, cells = list, center = center, size = Vector2.new(24, 24), out = Vector2.new(c[3], c[4]) })
			end
		end
	end
	return cells
end

local function roomHasPit(room: RoomData): boolean
	for _, pit in ipairs(keepPits) do
		if pit.room == room then return true end
	end
	return false
end

local function onFloor(at: Vector3, floorY: number, exclude: Instance): Vector3?
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { exclude }
	local hit = Workspace:Raycast(at + Vector3.new(0, 12, 0), Vector3.new(0, -24, 0), rp)
	if hit and math.abs(hit.Position.Y - floorY) < 2 then return hit.Position end
	return nil
end

local function keepDecor(room: RoomData, propsFolder: Folder, rng: Random)
	local cx = (room.gx + (room.w - 1) / 2) * FLOOR_SIZE
	local cz = (room.gz + (room.d - 1) / 2) * FLOOR_SIZE
	-- fire pedestals at the corners of the sigil dais
	if room.w >= 5 and room.d >= 5 then
		local pedestal = KeepKit.Build("Fire_Pedestal")
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local at = onFloor(Vector3.new(cx + sx * 14, room.floorY, cz + sz * 14), room.floorY, propsFolder)
				if at and pedestal then spawnInstance(pedestal, CFrame.new(at), propsFolder, true) end
			end
		end
		if pedestal then pedestal:Destroy() end
	end
	-- the lava pits, chains slung over them
	for _, pit in ipairs(keepPits) do
		if pit.room ~= room then continue end
		local m = KeepKit.LavaPit(pit.size, PIT_DEPTH)
		m:PivotTo(CFrame.new(pit.center))
		m.Parent = propsFolder
		local half = pit.size.X / 2
		local o = Vector3.new(pit.out.X, 0, pit.out.Y)
		-- corners: the inner one (toward the room) and the two along the walls
		local inner = pit.center - o * half - o * 2
		local edgeA = pit.center + Vector3.new(o.X * half, 0, -o.Z * half) + Vector3.new(0, 0, -o.Z * 2)
		local edgeB = pit.center + Vector3.new(-o.X * half, 0, o.Z * half) + Vector3.new(-o.X * 2, 0, 0)
		local tops = {}
		for i, at in ipairs({ edgeA, inner, edgeB }) do
			local post = KeepKit.ChainPost()
			post:PivotTo(CFrame.new(at))
			post.Parent = propsFolder
			tops[i] = at + Vector3.new(0, KeepKit.CHAIN_Y, 0)
		end
		local chains = Instance.new("Model")
		chains.Name = "PitChains"
		KeepKit.Chain(tops[1], tops[2], 3.2, chains, 1.2)
		KeepKit.Chain(tops[2], tops[3], 3.2, chains, 1.2)
		chains.Parent = propsFolder
	end
	-- the boss's gate: against a wall of the arena with no doorway near (when
	-- it isn't already the way out: constructKeepExit)
	if room.roomType == "Boss" and not keepExitBuilt then
		local gate = KeepKit.Build("Demon_Gate")
		if not gate then return end
		local hx, hz = room.w * FLOOR_SIZE / 2, room.d * FLOOR_SIZE / 2
		local mx, mz = (room.gx + (room.w - 1) / 2) * FLOOR_SIZE, (room.gz + (room.d - 1) / 2) * FLOOR_SIZE
		-- (each side: where it stands, its turn so it faces into the room; the
		-- far +Z side is the lift's)
		local sides = {
			{ Vector3.new(mx, room.floorY, mz - hz + 3.5), math.pi },
			{ Vector3.new(mx - hx + 3.5, room.floorY, mz), -math.pi / 2 },
			{ Vector3.new(mx + hx - 3.5, room.floorY, mz), math.pi / 2 },
		}
		for _, side in ipairs(sides) do
			local at: Vector3 = side[1]
			local near = false
			for _, door in ipairs(keepDoors) do
				if Vector2.new(door.X - at.X, door.Z - at.Z).Magnitude < 30 then near = true break end
			end
			if not near then
				gate:PivotTo(CFrame.new(at) * CFrame.Angles(0, side[2], 0))
				gate.Parent = propsFolder
				return
			end
		end
		gate:Destroy()
	end
end

-- Outside the walls: a lava sea far below, black spires rising from it.
local function keepBackdrop(rooms: { RoomData }, parent: Instance, rng: Random)
	local folder = Instance.new("Folder")
	folder.Name = "KeepBackdrop"
	local minX, maxX, minZ, maxZ, minY = math.huge, -math.huge, math.huge, -math.huge, math.huge
	for _, r in ipairs(rooms) do
		minX = math.min(minX, r.gx * FLOOR_SIZE - FLOOR_SIZE / 2)
		maxX = math.max(maxX, (r.gx + r.w - 1) * FLOOR_SIZE + FLOOR_SIZE / 2)
		minZ = math.min(minZ, r.gz * FLOOR_SIZE - FLOOR_SIZE / 2)
		maxZ = math.max(maxZ, (r.gz + r.d - 1) * FLOOR_SIZE + FLOOR_SIZE / 2)
		minY = math.min(minY, r.floorY)
	end
	if minX == math.huge then return end
	local seaY = minY - 70
	local margin = 380
	local x0, x1, z0, z1 = minX - margin, maxX + margin, minZ - margin, maxZ + margin
	-- the lava sea, laid in tiles (a part can't be larger than 2048)
	local TILE = 600
	for x = x0, x1, TILE do
		for z = z0, z1, TILE do
			local w = math.min(TILE, x1 - x)
			local d = math.min(TILE, z1 - z)
			local crust = Instance.new("Part")
			crust.Name = "LavaSea"
			crust.Anchored, crust.CanCollide, crust.CanQuery, crust.CanTouch, crust.CastShadow = true, false, false, false, false
			crust.Material = Enum.Material.CrackedLava
			crust.Color = Color3.fromRGB(255, 104, 30)
			crust.Size = Vector3.new(w, 2, d)
			crust.CFrame = CFrame.new(x + w / 2, seaY, z + d / 2)
			crust.Parent = folder
			local glowSheet = crust:Clone()
			glowSheet.Name = "LavaGlow"
			glowSheet.Material = Enum.Material.Neon
			glowSheet.Color = Color3.fromRGB(200, 52, 10)
			glowSheet.CFrame = crust.CFrame - Vector3.new(0, 1.2, 0)
			glowSheet.Parent = folder
		end
	end
	-- spires round it, taller further out, never over the dungeon
	local c = Vector3.new((minX + maxX) / 2, seaY, (minZ + maxZ) / 2)
	local rx, rz = (maxX - minX) / 2, (maxZ - minZ) / 2
	local count = 26
	for k = 1, count do
		local a = (k + rng:NextNumber(-0.3, 0.3)) / count * math.pi * 2
		local push = rng:NextNumber(60, margin - 40)
		local at = c + Vector3.new(math.cos(a) * (rx + push), 0, math.sin(a) * (rz + push))
		local h = 120 + push * 0.55 + rng:NextNumber(0, 90)
		local spire = KeepKit.Spire(h, rng:NextInteger(1, 1e6))
		spire:PivotTo(CFrame.new(at - Vector3.new(0, 4, 0)) * CFrame.Angles(0, rng:NextNumber() * math.pi * 2, 0))
		spire.Parent = folder
	end
	folder.Parent = parent
end

local function decorateRooms(rooms: { RoomData }, propsFolder: Folder, rng: Random)
	local violet: Instance? = nil
	if arcadeTheme then
		for _, c in ipairs(assets.cosmetics) do
			if c.Name == "Brazier_Purple" then violet = c end
		end
	end
	for _, room in ipairs(rooms) do
		local minX, maxX = room.gx, room.gx + room.w - 1
		local minZ, maxZ = room.gz, room.gz + room.d - 1

		buildSpecialRoom(room, propsFolder, rng)
		if prisonTheme then prisonDecor(room, propsFolder, rng) end
		if keepTheme then keepDecor(room, propsFolder, rng) end

		-- Hazards: the boss arena gets lava, flame vents and cover pillars;
		-- about a third of the combat rooms get spike traps.
		-- (not in the arcade: its rooms are clean boards, and its boss turns
		-- the arena floor into one)
		-- (a map's own floor pieces sit their top half a stud over the room's
		-- floor height: the hazards go on that top, not inside the floor)
		local hazardRoom: any = room
		if (assets :: any).ownArt == true then
			hazardRoom = table.clone(room :: any)
			hazardRoom.floorY = room.floorY + 0.5
		end
		if arcadeTheme then
			-- nothing
		elseif room.roomType == "Boss" then
			Hazards.BuildBossArena(hazardRoom, propsFolder, rng)
		elseif room.id ~= 1 and ((room.roomType == "Combat" and rng:NextNumber() < 0.35) or (room.roomType == "Elite" and rng:NextNumber() < 0.5)) then
			-- (clear of the Infernal Keep's lava pits)
			Hazards.BuildTraps(hazardRoom, propsFolder, rng, if building then keepBlocked[building] else nil)
		end

		-- 1. Rubble: Generously placed along wall perimeters and in all room corners (raised +3 studs)
		if #assets.rubble > 0 and not arcadeTheme and not keepTheme then
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
		if #assets.barriers > 0 and not arcadeTheme and not keepTheme and (room.roomType == "Combat" or room.roomType == "Elite") then
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
		if arcadeTheme then
			arcadeProps(room, propsFolder)
		elseif #assets.cosmetics > 0 then
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

				-- (the arcade's props stand on the floor, their pivots at their base)
				if arcadeTheme or keepTheme then cosPos = Vector3.new(cosPos.X, room.floorY + (if keepTheme then 0 else 0.5), cosPos.Z) end
				local cf = CFrame.new(cosPos) * CFrame.Angles(0, math.rad(rotY), 0)
				spawnInstance(cosTemplate, cf, propsFolder, true)
			end
		end

		-- 3b. Hades set dressing: a gold-inlaid floor medallion under the room
		-- reward (combat rooms) and green-fire braziers in the corners.
		-- (not on a map with its own centre pieces: one already lies there)
		local ownCentre = (assets :: any).ownArt == true and #assets.centerPieces > 0
		if not ownCentre and (room.roomType == "Combat" or room.roomType == "Elite" or room.roomType == "Boss") then
			local center = Vector3.new((room.gx + (room.w - 1) / 2) * FLOOR_SIZE, room.floorY, (room.gz + (room.d - 1) / 2) * FLOOR_SIZE)
			AtmosphereManager.PlaceFloorMedallion(center, 7, propsFolder)
		end
		if room.w >= 3 and room.d >= 3 and not keepTheme then
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
					if not arcadeTheme then
						AtmosphereManager.PlaceBrazier(CFrame.new(hit.Position), propsFolder, rng)
					elseif violet then
						spawnInstance(violet, CFrame.new(hit.Position), propsFolder, true)
					end
				end
			end
		end

		-- 3c. Hanging fire bowls on chains that rise out of view, over the
		-- open floor either side of the room's centre (clear of the reward).
		if room.w >= 3 and room.d >= 3 and not arcadeTheme and not keepTheme then
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
		for _ = 1, if arcadeTheme or keepTheme then 0 else AtmosphereManager.Config.CandlesPerRoom do
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
	arcadeTheme = map ~= nil and map.arcade == true
	prisonTheme = map ~= nil and map.prison == true
	keepTheme = map ~= nil and map.keep == true

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
	-- How the rooms are joined (MapData.transit): corridors with stairs (the
	-- default) or lifts where they change height; or portals: a floor taken
	-- room by room (buildLayeredGraph, RoomPortals), no corridors at all.
	local transit = (map and map.transit) or "stairs"
	local layered = transit == "portal"
	local rooms, floorGrid0, doorwayList, stairList
	-- (the tutorial: its rooms in order, weaker foes, popups: Tutorial.luau)
	RunScope.Set(runId, "Tutorial", if map and map.tutorial then true else nil)
	if layered then
		rooms, floorGrid0 = buildLayeredGraph(rng, cfg, map and map.plan)
		doorwayList, stairList = {}, {}
	else
		rooms, floorGrid0, doorwayList, stairList = buildDungeonGraph(rng, cfg, map and map.plan)
	end
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
	-- (a map with its own art lays ONE centre piece over each room's floor instead:
	-- after the tiles, below)
	local oneCentre = (assets :: any).ownArt == true and #assets.centerPieces > 0
	if not keepTheme then table.clear(keepPits) end
	local pitCells: { [string]: boolean } = if keepTheme then planKeepPits(rooms, doorwayList, stairList, rng) else {}
	keepBlocked[runId] = {}
	for _, pit in ipairs(keepPits) do
		local h = pit.size / 2 + Vector2.new(2, 2)
		table.insert(keepBlocked[runId], { pit.center.X - h.X, pit.center.X + h.X, pit.center.Z - h.Y, pit.center.Z + h.Y })
	end
	for _, room in ipairs(rooms) do
		if oneCentre then break end
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

	-- The arcade's floors are laid to a plan, not shuffled: plain panels, with
	-- circuit tiles running round the room's edge and in a cross through its
	-- middle (each turned along its line), all one shade.
	local arcadePlan: { [string]: number } = {} -- key → the circuit tile's turn
	local arcadePanel, arcadeCircuit = nil, nil
	if arcadeTheme then
		for _, f in ipairs(assets.floors) do
			if f.Name == "Floor_Panel" then arcadePanel = f elseif f.Name == "Floor_Circuit" then arcadeCircuit = f end
		end
		for _, room in ipairs(rooms) do
			local minX, maxX = room.gx, room.gx + room.w - 1
			local minZ, maxZ = room.gz, room.gz + room.d - 1
			local cx, cz = room.gx + math.floor(room.w / 2), room.gz + math.floor(room.d / 2)
			for x = minX, maxX do
				for z = minZ, maxZ do
					local rot: number? = nil
					if z == minZ or z == maxZ then rot = 0
					elseif x == minX or x == maxX then rot = 90
					elseif z == cz then rot = 0
					elseif x == cx then rot = 90 end
					if rot then arcadePlan[x .. "_" .. z] = rot end
				end
			end
		end
	end

	if arcadeTheme then
		for _, room in ipairs(rooms) do arcadeFloor(room, floorsFolder) end
	end
	for key, cellData in pairs(floorGrid) do
		if arcadeTheme then break end
		local coords = string.split(key, "_")
		local gx = tonumber(coords[1]) :: number
		local gz = tonumber(coords[2]) :: number
		local cellFloorY = cellData.floorY or FLOOR_Y_OFFSET
		local pos = Vector3.new(gx * FLOOR_SIZE, cellFloorY, gz * FLOOR_SIZE)
		if pitCells[key] then continue end -- (a lava pit: keepDecor)

		local isCenterPiece = (centerPieceGrid[key] == true)
		local floorTemplate: Instance? = nil

		local planned = arcadePlan[key]
		if arcadeTheme and arcadePanel and arcadeCircuit then
			floorTemplate = if planned then arcadeCircuit else arcadePanel
		elseif isCenterPiece and #assets.centerPieces > 0 then
			floorTemplate = pickRandom(assets.centerPieces, rng)
		else
			floorTemplate = pickRandom(assets.floors, rng)
		end

		if floorTemplate and arcadeTheme and arcadePanel then
			spawnInstance(floorTemplate, CFrame.new(pos) * CFrame.Angles(0, math.rad(planned or 0), 0), floorsFolder, true)
		elseif floorTemplate then
			local rotY = rng:NextInteger(0, 3) * 90
			local cf = CFrame.new(pos) * CFrame.Angles(0, math.rad(rotY), 0)
			local tile = spawnInstance(floorTemplate, cf, floorsFolder, true)
			-- No two tiles quite alike: a little lighter or darker, some
			-- leaning cool (the stone reads less uniformly orange).
			local shade = if keepTheme then rng:NextNumber(0.92, 1.05) else rng:NextNumber(0.8, 1.06)
			local cool = if keepTheme then 0 else rng:NextNumber(0, 0.4)
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

	-- 2b. The map's own centre piece: one per room, over the floor tiles at the
	-- room's middle (tiles are centred on gx * FLOOR_SIZE), raised a hair so the
	-- two don't flicker. The room reward floats over it.
	if oneCentre then
		for _, room in ipairs(rooms) do
			if room.w < 3 or room.d < 3 then continue end
			local template = pickRandom(assets.centerPieces, rng)
			if template then
				local mid = Vector3.new((room.gx + (room.w - 1) / 2) * FLOOR_SIZE, room.floorY + 0.08, (room.gz + (room.d - 1) / 2) * FLOOR_SIZE)
				local turn = if arcadeTheme then 0 else rng:NextInteger(0, 3) * 90
				spawnInstance(template, CFrame.new(mid) * CFrame.Angles(0, math.rad(turn), 0), floorsFolder, true)
			end
		end
	end

	-- 3. Continuous Perimeter Wall, Pure Gate & Corner Pillar Construction
	if arcadeTheme then
		for _, room in ipairs(rooms) do
			arcadeEdges(room, wallsFolder)
			arcadeBackdrop(room, wallsFolder, rng)
		end
	else
		constructPerimeterWallsAndPillars(rooms, floorGrid, doorwayList, stairList, wallsFolder, rng)
	end

	-- 4. Between rooms on different heights (each corridor's gap): a lift
	-- (the Prison of Souls), or stairs
	if transit == "lift" and #stairList > 0 then
		local liftsFolder = Instance.new("Folder", dungeonFolder)
		liftsFolder.Name = "Lifts"
		for _, stairData in ipairs(stairList) do
			constructRoomLift(stairData, liftsFolder, floorsFolder)
		end
	elseif #stairList > 0 then
		for _, stairData in ipairs(stairList) do
			local stairTemplate = pickRandom(assets.stairs, rng)
			local heightDiff = stairData.upperFloorY - stairData.lowerFloorY
			-- (shifted 1 stud back along its orientation)
			local adjustedCF = stairData.cframe * CFrame.new(0, 0, 1)
			local stairPos = adjustedCF.Position
			local _, stairRotY, _ = adjustedCF:ToEulerAnglesYXZ()
			if stairTemplate then
				-- (raised by half the 14-stud model's height, so it stands on the floor)
				spawnInstance(stairTemplate, adjustedCF * CFrame.new(0, 7, 0), stairsFolder)
			else
				-- no stair pieces: a walkable ramp from the lower floor to the upper
				local rampLen = math.sqrt(STAIR_LENGTH * STAIR_LENGTH + heightDiff * heightDiff)
				local rampAngle = math.atan2(heightDiff, STAIR_LENGTH)
				local midY = (stairData.lowerFloorY + stairData.upperFloorY) / 2
				local ramp = Instance.new("Part")
				ramp.Name = "ProceduralStairRamp"
				ramp.Size = Vector3.new(STAIR_WIDTH, 2, rampLen)
				ramp.CFrame = CFrame.new(stairPos.X, midY, stairPos.Z) * CFrame.Angles(0, stairRotY, 0) * CFrame.Angles(-rampAngle, 0, 0)
				ramp.Anchored = true
				ramp.CanCollide = true
				ramp.Material = Enum.Material.Cobblestone
				ramp.Color = Color3.fromRGB(55, 55, 60)
				ramp.Parent = stairsFolder
			end
		end
	end
	-- (room by room: each room's exits, a portal for each room of the next layer)
	if layered then
		local ok, err = pcall(function()
			require(script.Parent:WaitForChild("RoomPortals")).Build(rooms :: any, runId, propsFolder)
		end)
		if not ok then warn("[DungeonGenerator] portals:", err) end
	end

	-- 5. Exit Lift (Elevator to next floor) in the Boss Chamber
	local liftPos = Vector3.new(
		(bossRoom.gx + bossRoom.w / 2) * FLOOR_SIZE,
		bossRoom.floorY,
		(bossRoom.gz + bossRoom.d - 1) * FLOOR_SIZE
	)
	local liftCF = CFrame.new(liftPos) * CFrame.Angles(0, 0, 0)
	d.exit = liftCF

	-- (the Infernal Keep: its demon gate and dark hallway instead, if a side is clear)
	keepExitBuilt = false
	local keepExit = if keepTheme then constructKeepExit(bossRoom, floorGrid, doorwayList, stairList, wallsFolder, stairsFolder, runId) else nil
	if keepExit then
		d.exit = keepExit
	else
		constructDungeonLiftExit(liftCF, stairsFolder, runId)
	end

	-- 5. Interior Decorating (Abundant Corner/Perimeter Rubble, Barriers, Cosmetics)
	decorateRooms(rooms, propsFolder, rng)
	if keepTheme then
		keepBackdrop(rooms, dungeonFolder, rng)
		-- (the default stairs, in the keep's stone)
		for _, d in ipairs(stairsFolder:GetDescendants()) do
			if d:IsA("BasePart") then
				local v = math.clamp((d.Color.R + d.Color.G + d.Color.B) / 3, 0.25, 1)
				d.Color = KeepKit.COLORS.STONE:Lerp(KeepKit.COLORS.STONE_HI, (v - 0.25) / 0.75)
				d.Material = Enum.Material.Slate
			end
		end
	end

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
	-- (room by room, the map is only ever the room you're in: the start, for now;
	-- RoomPortals sends each next one)
	if layered then
		local r = startRoom
		local grid = {}
		for x = r.gx, r.gx + r.w - 1 do
			for z = r.gz, r.gz + r.d - 1 do
				grid[x .. "_" .. z] = floorGrid[x .. "_" .. z]
			end
		end
		mapPayload = { tileSize = FLOOR_SIZE, grid = grid, rooms = { roomListPayload[1] } }
	end
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
	-- The arcade: immunity towers shielding the mobs in its combat rooms.
	if map and map.arcade then
		local ok, err = pcall(function()
			require(script.Parent:WaitForChild("ImmunityTower")).SetupRooms(rooms :: any, level, propsFolder, rng)
		end)
		if not ok then warn("[DungeonGenerator] towers:", err) end
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
	keepBlocked[runId] = nil
end

-- The room a position stands in (its id and kind), by the map's room
-- rectangles (nil in a corridor or off the map).
function DungeonGenerator.RoomAt(runId: string?, pos: Vector3): (number?, string?)
	local d = runId and dungeons[runId]
	local payload = d and d.payload
	if not payload then return nil, nil end
	local s = payload.tileSize
	for _, r in ipairs(payload.rooms) do
		if pos.X >= r.gx * s and pos.X <= (r.gx + r.w) * s and pos.Z >= r.gz * s and pos.Z <= (r.gz + r.d) * s then
			return r.id, r.roomType
		end
	end
	return nil, nil
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
-- (a new level's arrival: held until the client has the floor, at most this long)
local ARRIVE_MAX = 12
local floorReady: { [Player]: boolean } = {}
Network.GetRemoteEvent(Network.Remotes.FloorReady).OnServerEvent:Connect(function(plr: Player)
	if plr:GetAttribute("Arriving") == true then floorReady[plr] = true end
end)
Players.PlayerRemoving:Connect(function(plr) floorReady[plr] = nil end)

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
		local standCF = CFrame.new(base.X, y, base.Z) * spawnCF.Rotation
		if r.root.Parent then
			r.root.CFrame = standCF
			r.root.AssemblyLinearVelocity = Vector3.zero
		end
		-- Hold them on the new floor until their game has it (streamed in round
		-- the spawn), or they'd drop straight through a floor that hasn't
		-- arrived yet. A fixed wait wasn't enough when the network was busy
		-- (taking the lift mid-horde, dozens of mobs replicating): they fell
		-- under the map. So they're held until their game says the floor is
		-- under them ("Arriving": FloorReady, from init.client), or ARRIVE_MAX.
		-- Still falling after that? Back on the floor.
		task.spawn(function()
			local t0 = os.clock()
			floorReady[r.player] = nil
			r.player:SetAttribute("Arriving", true)
			pcall(function() r.player:RequestStreamAroundAsync(standCF.Position, 8) end)
			while os.clock() - t0 < ARRIVE_MAX and r.root.Parent and not (floorReady[r.player] and os.clock() - t0 >= 0.6) do
				task.wait(0.1)
			end
			r.player:SetAttribute("Arriving", nil)
			floorReady[r.player] = nil
			local char = r.root.Parent :: Model?
			if not char then return end
			r.root.AssemblyLinearVelocity = Vector3.zero
			r.root.CFrame = standCF
			r.root.Anchored = false
			for _ = 1, 40 do
				task.wait(0.5)
				if r.root.Parent ~= char or r.player.Character ~= char then return end
				if r.root.Position.Y < standCF.Position.Y - 25 then
					r.root.AssemblyLinearVelocity = Vector3.zero
					char:PivotTo(standCF)
				end
			end
		end)
	end
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
