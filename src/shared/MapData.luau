--!strict
--[[
	MapData.luau
	The maps a party can pick at the lobby's gates. Each is the same procedural
	dungeon with its own theme: the light (applied on entering), a tint over the
	stone, which room packs its mobs come in (MobKinds' PACKS, by index), and
	its bosses.

	  MapData.Maps          the list, in gate order
	  MapData.Get(id)       one map (nil for an unknown id)
	  MapData.DEFAULT       the map used when none was picked
--]]

-- (every dungeon is lit bright and clear; a map only tints the colour grade)
export type Lighting = {
	tint: Color3,           -- ColorCorrection tint
	saturation: number,
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
		bosses = { "colossus", "witch" },
		assets = "map:crypt assets",
		prison = true,
		lighting = {
			tint = Color3.fromRGB(226, 242, 238),
			saturation = 0.1,
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
		packs = { 2, 5, 3 },
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
		packs = { 4, 3, 1 },
		bosses = { "witch", "colossus", "fallen_angel" },
		lighting = {
			tint = Color3.fromRGB(232, 242, 255),
			saturation = 0.15,
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
		packs = { 1, 2, 3, 4, 5 },
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
