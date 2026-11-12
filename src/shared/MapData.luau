--!strict
--[[
	MapData.luau
	The maps a party can pick at the lobby's gates. Each is the same procedural
	dungeon with its own theme: the light (applied on entering), a tint over the
	stone, which room packs its mobs come in (MobKinds' PACKS, by index), and
	its bosses. Some bring their own pieces (`assets`) and rules: the Prison of
	Souls' searchlights, the Neon Arcade's neon rooms and immunity towers.

	  MapData.Maps          the list, in gate order (not the hidden ones: MapData.Hidden)
	  MapData.Get(id)       one map (nil for an unknown id)
	  MapData.DEFAULT       the map used when none was picked
	  MapData.MODES         the difficulty modes every map is played on:
	                        NORMAL, HARD, NIGHTMARE (mob health and damage
	                        × `health` / `damage`, gold, XP and souls × `reward`)
	  MapData.Mode(id)      one mode (NORMAL for an unknown id)
	  MapData.RecommendedPower(map, modeId)
	                        the POWER (PowerGear.Total) a party should bring:
	                        the map's `power`, one per mode
--]]

-- (every dungeon is lit bright and clear; a map tints the colour grade, and a
-- map whose art is its own glow can ask for the dark instead: the rest)
export type Lighting = {
	tint: Color3,           -- ColorCorrection tint
	saturation: number,
	clockTime: number?,     -- (the dark: night, so the neon shines)
	ambient: Color3?,
	outdoorAmbient: Color3?,
	brightness: number?,
	exposure: number?,
	-- its own fog (the Atmosphere): its colour, the colour it deepens to far
	-- off, how thick, how hazy
	fog: { color: Color3, decay: Color3, density: number, haze: number }?,
	-- its own bloom (every BloomEffect in Lighting): a neon map wants less,
	-- tighter, so each line keeps a crisp core
	bloom: { intensity: number, size: number, threshold: number }?,
}

export type Map = {
	id: string,
	name: string,
	subtitle: string,
	rank: string,           -- its difficulty on the quest board
	description: string,
	color: Color3,          -- the gate's glow, its card's accent
	stone: Color3,          -- multiplies the floor and wall colours
	packs: { number },      -- MobKinds PACKS indices its rooms draw from
	bosses: { string },     -- BossAI kinds for the other boss rooms
	lighting: Lighting,
	unlockFloor: number?,   -- your deepest floor must reach this to enter
	sealed: boolean?,       -- chained shut: on the picker (last, in chains) but never enterable
	hidden: boolean?,       -- taken out for now: no gate, not on the picker, never enterable (its code kept: MapData.Hidden)
	assets: string?,        -- its own dungeon pieces: a folder in ReplicatedStorage (DungeonGenerator)
	prison: boolean?,       -- the prison: spotlights hunt you, three sightings raise the alarm (Prison.luau)
	arcade: boolean?,       -- the arcade: neon rooms (no torches, candles or rubble) and immunity towers (ImmunityTower)
	keep: boolean?,         -- the Infernal Keep: KeepKit's fortress, lava pits, the lava sea and spires (DungeonGenerator keepDecor)
	-- The tutorial (MapData.Tutorial, never on the map picker): its rooms in
	-- this order, one after another (DungeonGenerator), weaker mobs and boss,
	-- popups in every room (Tutorial.luau, TutorialController).
	tutorial: boolean?,
	plan: { string }?,
	-- The Forgotten Isle: no dungeon at all, an open island (IslandGenerator)
	-- taken as an endless survival (IslandMode) with a ritual boss at its heart.
	island: boolean?,
	-- How its rooms are joined (DungeonGenerator): "stairs" (the default:
	-- corridors, stairs where they change height), "lift" (corridors, a lift
	-- at each change of height) or "portal" (no corridors, no map: the floor
	-- taken room by room, 1 → 2 choices → 3 → 2 → the boss, each room's portals
	-- opening when it's cleared, each saying what's through it: RoomPortals).
	transit: string?,
	-- The POWER recommended on each mode, in MapData.MODES order
	-- (NORMAL, HARD, NIGHTMARE).
	power: { number }?,
}

export type Mode = {
	id: string,
	name: string,
	health: number, -- × mob health
	damage: number, -- × mob damage
	reward: number, -- × gold, XP and souls
	color: Color3,
}

local MapData = {}

MapData.Maps = {
	{
		id = "crypt",
		power = { 100, 300, 600 }, -- recommended POWER: normal, hard, nightmare
		name = "The Prison of Souls",
		subtitle = "Stay out of the light",
		rank = "C",
		description = "A prison. Get spotted by searchlights 3 times and every inmate comes for you.",
		color = Color3.fromRGB(120, 230, 210),
		stone = Color3.fromRGB(200, 214, 210),
		packs = { 6 },
		bosses = { "fallen_angel", "colossus", "witch" },
		assets = "map:crypt assets",
		prison = true,
		transit = "lift",
		-- a dank green gloom: teal-green fog, a cold green cast, dim light
		lighting = {
			tint = Color3.fromRGB(200, 236, 220),
			saturation = 0.05,
			ambient = Color3.fromRGB(125, 155, 145),
			outdoorAmbient = Color3.fromRGB(110, 145, 135),
			brightness = 2.0,
			exposure = 0.15,
			fog = {
				color = Color3.fromRGB(70, 160, 135),
				decay = Color3.fromRGB(24, 70, 62),
				density = 0.28,
				haze = 1.6,
			},
		},
	},
	{
		id = "keep",
		power = { 200, 450, 800 }, -- recommended POWER: normal, hard, nightmare
		name = "The Infernal Keep",
		subtitle = "The Cinder Wyrm's lair",
		rank = "B",
		description = "A lava fortress. Boss: Ignarath.",
		color = Color3.fromRGB(255, 120, 50),
		stone = Color3.fromRGB(230, 200, 190),
		packs = { 2, 5, 3, 7 },
		bosses = { "warlord", "fallen_angel" },
		assets = "map:keep assets",
		keep = true,
		-- dusk in hell: a blood-red sky and haze, light glowing up off the
		-- lava, deep purple shadows
		lighting = {
			tint = Color3.fromRGB(255, 236, 222),
			saturation = 0.12,
			clockTime = 15.5,
			ambient = Color3.fromRGB(105, 82, 92),
			outdoorAmbient = Color3.fromRGB(135, 98, 92),
			brightness = 3,
			exposure = 0.35,
			bloom = { intensity = 0.5, size = 18, threshold = 1.35 },
			fog = {
				color = Color3.fromRGB(175, 62, 40),
				decay = Color3.fromRGB(60, 16, 20),
				density = 0.22,
				haze = 1.3,
			},
		},
	},
	{
		id = "arcade",
		power = { 350, 700, 1200 }, -- recommended POWER: normal, hard, nightmare
		name = "The Neon Arcade",
		subtitle = "Break the towers",
		rank = "S",
		description = "Clear a room to pick the next. Break the pink towers to remove enemy shields.",
		color = Color3.fromRGB(255, 70, 210),
		stone = Color3.fromRGB(255, 255, 255),
		packs = { 8 },
		bosses = { "djinn" },
		assets = "map:arcade assets",
		arcade = true,
		transit = "portal",
		lighting = {
			tint = Color3.fromRGB(222, 228, 255),
			saturation = 0.15,
			clockTime = 0,
			ambient = Color3.fromRGB(118, 120, 180),
			outdoorAmbient = Color3.fromRGB(96, 100, 160),
			brightness = 1.6,
			exposure = 0.35,
			bloom = { intensity = 0.35, size = 12, threshold = 1.6 },
			-- a violet haze the void fades into (the islands loom out of it)
			fog = {
				color = Color3.fromRGB(70, 46, 170),
				decay = Color3.fromRGB(22, 14, 64),
				density = 0.2,
				haze = 1.0,
			},
		},
	},
	{
		id = "isle",
		power = { 250, 550, 900 }, -- recommended POWER: normal, hard, nightmare
		name = "The Forgotten Isle",
		-- (taken out for now: its six islands, enemies and bosses stay in the
		-- code; drop this line to bring it back)
		hidden = true,
		subtitle = "Survive. Plunder. Summon.",
		rank = "A",
		description = "Open-world survival. Power up, then start the ritual to fight the bosses.",
		color = Color3.fromRGB(170, 100, 255),
		stone = Color3.fromRGB(255, 255, 255),
		packs = { 1 },
		bosses = {},
		island = true,
		-- a bright tropical day: a high sun, a clear blue haze over the sea
		lighting = {
			tint = Color3.fromRGB(255, 252, 240),
			saturation = 0.2,
			clockTime = 13.2,
			ambient = Color3.fromRGB(120, 128, 140),
			outdoorAmbient = Color3.fromRGB(150, 160, 176),
			brightness = 3,
			exposure = 0.15,
			bloom = { intensity = 0.3, size = 18, threshold = 1.6 },
			fog = {
				color = Color3.fromRGB(170, 210, 240),
				decay = Color3.fromRGB(90, 150, 210),
				density = 0.18,
				haze = 0.8,
			},
		},
	},
	{
		id = "frost",
		power = { 300, 650, 1000 }, -- recommended POWER: normal, hard, nightmare
		name = "The Frozen Halls",
		sealed = true, -- chained shut: shown last on the picker, can't be entered
		subtitle = "Silence beneath the ice",
		rank = "A",
		description = "Frozen halls. Boss: the Hex Witch.",
		color = Color3.fromRGB(130, 190, 255),
		stone = Color3.fromRGB(205, 220, 245),
		packs = { 4, 3, 1, 7 },
		bosses = { "witch", "colossus", "fallen_angel" },
		lighting = {
			tint = Color3.fromRGB(232, 242, 255),
			saturation = 0.15,
		},
	},
} :: { Map }

-- The tutorial: every kind of room in turn, in the Infernal Keep's burning
-- fortress, one hall leading to the next (the plan's order, no side rooms),
-- with a popup in each explaining it. Not on the map picker (its own button
-- there, and new players are sent in once: Tutorial.luau).
MapData.Tutorial = {
	id = "tutorial",
	name = "The Proving Grounds",
	subtitle = "Learn the ropes",
	rank = "-",
	description = "A short guided run with a weak boss.",
	color = Color3.fromRGB(255, 120, 50),
	stone = Color3.fromRGB(230, 200, 190),
	packs = { 5 },
	bosses = { "warlord" },
	assets = "map:keep assets",
	keep = true,
	tutorial = true,
	plan = { "Start", "Combat", "Treasure", "Elite", "Shop", "Gamble", "Rest", "Cursed", "Purge", "Boss" },
	-- (the Keep's own light: dusk in hell)
	lighting = {
		tint = Color3.fromRGB(255, 236, 222),
		saturation = 0.12,
		clockTime = 15.5,
		ambient = Color3.fromRGB(105, 82, 92),
		outdoorAmbient = Color3.fromRGB(135, 98, 92),
		brightness = 3,
		exposure = 0.35,
		bloom = { intensity = 0.5, size = 18, threshold = 1.35 },
		fog = {
			color = Color3.fromRGB(175, 62, 40),
			decay = Color3.fromRGB(60, 16, 20),
			density = 0.22,
			haze = 1.3,
		},
	},
} :: Map

MapData.DEFAULT = "keep"

-- The difficulty modes, easiest first (the map picker's buttons, top down).
MapData.MODES = {
	{ id = "normal", name = "NORMAL", health = 1, damage = 1, reward = 1, color = Color3.fromRGB(120, 210, 120) },
	{ id = "hard", name = "HARD", health = 1.6, damage = 1.3, reward = 1.5, color = Color3.fromRGB(255, 190, 70) },
	{ id = "nightmare", name = "NIGHTMARE", health = 2.5, damage = 1.7, reward = 2.25, color = Color3.fromRGB(235, 70, 80) },
} :: { Mode }

local modeById: { [string]: Mode } = {}
for _, m in ipairs(MapData.MODES) do modeById[m.id] = m end

function MapData.Mode(id: any): Mode
	return (if typeof(id) == "string" then modeById[id] else nil) or MapData.MODES[1]
end

function MapData.RecommendedPower(map: Map, modeId: string?): number
	local mode = MapData.Mode(modeId)
	local i = table.find(MapData.MODES, mode) or 1
	local list = map.power or { 100, 300, 600 }
	return list[i] or list[#list]
end

-- The lobby plaza's centre (LobbyManager builds it; clients draw its sky).
MapData.LOBBY_CENTER = Vector3.new(-4200, 300, 0)

-- (a hidden map leaves the list every gate and picker is built from, but
-- stays known by its id)
MapData.Hidden = {} :: { Map }
for i = #MapData.Maps, 1, -1 do
	local m = MapData.Maps[i]
	if m.hidden then table.insert(MapData.Hidden, 1, table.remove(MapData.Maps, i)) end
end

local byId: { [string]: Map } = {}
for _, m in ipairs(MapData.Maps) do byId[m.id] = m end
for _, m in ipairs(MapData.Hidden) do byId[m.id] = m end
byId[MapData.Tutorial.id] = MapData.Tutorial

function MapData.Get(id: any): Map?
	return if typeof(id) == "string" then byId[id] else nil
end

return MapData
