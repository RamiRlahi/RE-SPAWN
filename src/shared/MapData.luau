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

export type Lighting = {
	ambient: Color3,
	outdoorAmbient: Color3,
	colorShiftTop: Color3,
	colorShiftBottom: Color3,
	brightness: number,
	tint: Color3,           -- ColorCorrection tint
	saturation: number,
	torch: Color3,          -- the player's torch light
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
	dragonChance: number,   -- chance a level's boss is the dragon (level 1 always is, where allowed)
	dragonFirst: boolean,   -- the dragon guards the first level
	bosses: { string },     -- BossAI kinds for the other boss rooms
	lighting: Lighting,
	endless: boolean?,      -- the Endless Abyss: no collapse, its leaderboard (Leaderboard.luau)
	unlockFloor: number?,   -- your deepest floor must reach this to enter
}

local MapData = {}

MapData.Maps = {
	{
		id = "crypt",
		name = "The Sunken Crypt",
		subtitle = "Where the dead do not rest",
		rank = "C",
		description = "Cold green halls of bone and grave dust. Zombies, ghouls and necromancers raising the fallen.",
		color = Color3.fromRGB(110, 220, 170),
		stone = Color3.fromRGB(200, 214, 210),
		packs = { 1, 3, 4 },
		dragonChance = 0,
		dragonFirst = false,
		bosses = { "colossus", "witch" },
		lighting = {
			ambient = Color3.fromRGB(26, 46, 52),
			outdoorAmbient = Color3.fromRGB(40, 66, 72),
			colorShiftTop = Color3.fromRGB(20, 40, 34),
			colorShiftBottom = Color3.fromRGB(10, 32, 36),
			brightness = 0.7,
			tint = Color3.fromRGB(228, 248, 240),
			saturation = 0.2,
			torch = Color3.fromRGB(210, 240, 220),
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
		dragonChance = 0.35,
		dragonFirst = true,
		bosses = { "warlord", "slime" },
		lighting = {
			ambient = Color3.fromRGB(52, 30, 30),
			outdoorAmbient = Color3.fromRGB(74, 44, 40),
			colorShiftTop = Color3.fromRGB(70, 34, 14),
			colorShiftBottom = Color3.fromRGB(40, 12, 12),
			brightness = 0.8,
			tint = Color3.fromRGB(255, 238, 228),
			saturation = 0.35,
			torch = Color3.fromRGB(255, 180, 120),
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
		dragonChance = 0,
		dragonFirst = false,
		bosses = { "witch", "colossus", "warlord" },
		lighting = {
			ambient = Color3.fromRGB(30, 42, 74),
			outdoorAmbient = Color3.fromRGB(48, 64, 104),
			colorShiftTop = Color3.fromRGB(30, 38, 56),
			colorShiftBottom = Color3.fromRGB(14, 24, 56),
			brightness = 0.85,
			tint = Color3.fromRGB(232, 242, 255),
			saturation = 0.15,
			torch = Color3.fromRGB(215, 230, 255),
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
		dragonChance = 0.25,
		dragonFirst = false,
		bosses = { "colossus", "witch", "warlord", "slime" },
		endless = true,
		unlockFloor = 6,
		lighting = {
			ambient = Color3.fromRGB(40, 26, 60),
			outdoorAmbient = Color3.fromRGB(60, 40, 86),
			colorShiftTop = Color3.fromRGB(50, 24, 70),
			colorShiftBottom = Color3.fromRGB(24, 10, 44),
			brightness = 0.75,
			tint = Color3.fromRGB(240, 228, 255),
			saturation = 0.25,
			torch = Color3.fromRGB(230, 200, 255),
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
