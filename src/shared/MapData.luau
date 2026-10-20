--!strict
--[[
	MapData.luau
	The maps a party can pick at the lobby's gates. Each is the same procedural
	dungeon with its own theme: the light (applied on entering), a tint over the
	stone, which room packs its mobs come in (MobKinds' PACKS, by index), and
	its bosses. Some bring their own pieces (`assets`) and rules: the Prison of
	Souls' searchlights, the Neon Arcade's neon rooms and immunity towers.

	  MapData.Maps          the list, in gate order
	  MapData.Get(id)       one map (nil for an unknown id)
	  MapData.DEFAULT       the map used when none was picked
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
	endless: boolean?,      -- the Endless Abyss: no collapse, its leaderboard (Leaderboard.luau)
	unlockFloor: number?,   -- your deepest floor must reach this to enter
	assets: string?,        -- its own dungeon pieces: a folder in ReplicatedStorage (DungeonGenerator)
	prison: boolean?,       -- the prison: spotlights hunt you, three sightings raise the alarm (Prison.luau)
	arcade: boolean?,       -- the arcade: neon rooms (no torches, candles or rubble) and immunity towers (ImmunityTower)
	-- How its rooms are joined (DungeonGenerator): "stairs" (the default:
	-- corridors, stairs where they change height), "lift" (corridors, a lift
	-- at each change of height) or "portal" (no corridors, no map: the floor
	-- taken room by room, 1 → 2 choices → 3 → 2 → the boss, each room's portals
	-- opening when it's cleared, each saying what's through it: RoomPortals).
	transit: string?,
}

local MapData = {}

MapData.Maps = {
	{
		id = "crypt",
		name = "The Prison of Souls",
		subtitle = "Stay out of the light",
		rank = "C",
		description = "A prison for the damned. Searchlights sweep every hall: be seen three times and the wardens send every inmate down the lifts after you. Shackled souls, jailers and executioners.",
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
			ambient = Color3.fromRGB(58, 92, 84),
			outdoorAmbient = Color3.fromRGB(46, 84, 76),
			brightness = 1.4,
			exposure = -0.15,
			fog = {
				color = Color3.fromRGB(70, 160, 135),
				decay = Color3.fromRGB(24, 70, 62),
				density = 0.42,
				haze = 2.6,
			},
		},
	},
	{
		id = "keep",
		name = "The Infernal Keep",
		subtitle = "The Cinder Wyrm's lair",
		rank = "B",
		description = "A burning fortress over rivers of lava. Magma slimes, brutes and Ignarath, the Cinder Wyrm.",
		color = Color3.fromRGB(255, 120, 50),
		stone = Color3.fromRGB(230, 200, 190),
		packs = { 2, 5, 3, 7 },
		bosses = { "warlord", "fallen_angel" },
		lighting = {
			tint = Color3.fromRGB(255, 238, 228),
			saturation = 0.35,
		},
	},
	{
		id = "frost",
		name = "The Frozen Halls",
		subtitle = "Silence beneath the ice",
		rank = "A",
		description = "Hushed blue halls rimed with frost. Wraiths, bone mages and the Hex Witch in the cold.",
		color = Color3.fromRGB(130, 190, 255),
		stone = Color3.fromRGB(205, 220, 245),
		packs = { 4, 3, 1, 7 },
		bosses = { "witch", "colossus", "fallen_angel" },
		lighting = {
			tint = Color3.fromRGB(232, 242, 255),
			saturation = 0.15,
		},
	},
	{
		id = "arcade",
		name = "The Neon Arcade",
		subtitle = "Break the towers",
		rank = "S",
		description = "A floating arcade in the void, taken room by room: clear a room and its portals light, each showing what waits beyond. Towers of magenta light make the monsters round them untouchable: shatter a tower and its shields fall.",
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
			ambient = Color3.fromRGB(58, 62, 120),
			outdoorAmbient = Color3.fromRGB(40, 48, 96),
			brightness = 1,
			exposure = 0.1,
			bloom = { intensity = 0.35, size = 12, threshold = 1.6 },
			-- a violet haze the void fades into (the islands loom out of it)
			fog = {
				color = Color3.fromRGB(70, 46, 170),
				decay = Color3.fromRGB(22, 14, 64),
				density = 0.32,
				haze = 1.6,
			},
		},
	},
	{
		id = "endless",
		name = "The Endless Abyss",
		subtitle = "How deep can you go?",
		rank = "∞",
		description = "Every horror of every dungeon, floor after floor, the Corruption rising from the first step. It never collapses. Extract every 5th floor, or keep going for the Hall of the Deep.",
		color = Color3.fromRGB(180, 90, 255),
		stone = Color3.fromRGB(190, 180, 215),
		packs = { 1, 2, 3, 4, 5, 7 },
		bosses = { "colossus", "witch", "warlord", "fallen_angel" },
		endless = true,
		unlockFloor = 6,
		lighting = {
			tint = Color3.fromRGB(240, 228, 255),
			saturation = 0.25,
		},
	},
} :: { Map }

MapData.DEFAULT = "keep"

-- The lobby plaza's centre (LobbyManager builds it; clients draw its sky).
MapData.LOBBY_CENTER = Vector3.new(-4200, 300, 0)

local byId: { [string]: Map } = {}
for _, m in ipairs(MapData.Maps) do byId[m.id] = m end

function MapData.Get(id: any): Map?
	return if typeof(id) == "string" then byId[id] else nil
end

return MapData
