--!strict
--[[
	IslandConfig.luau
	RE's island run (MapData "isle"): six islands, Level 1 to Level 6
	(IslandIsles), every number the mode runs on kept apart from the code
	that runs it. The island itself (IslandGenerator),
	the survival loop (IslandMode), the chests (IslandChests), the ritual and
	its bosses (IslandRitual, IslandBosses) and the HUD (IslandHUD) all read
	from here; nothing else in the mode hardcodes these values.

	Island space: studs from an isle's centre (IslandConfig.Origin(slot) plus
	its offset, in the world); +X east, +Z north, Y up from the sea's surface. Bearings in
	degrees from +X toward +Z (north is 90, west 180, south -90).
--]]

local IslandConfig = {}

-- ── Where it sits ───────────────────────────────────────────────────────────
-- Each run has its own slot (RunManager), 2040 studs apart along +X like the
-- dungeons; its six isles run out along +Z from here (IslandIsles offsets),
-- clear of every dungeon and of the lobby.
IslandConfig.SLOT_SPACING = 2040
IslandConfig.ORIGIN_Z = 6200
function IslandConfig.Origin(slot: number): Vector3
	return Vector3.new(slot * IslandConfig.SLOT_SPACING + 400, 0, IslandConfig.ORIGIN_Z)
end

-- ── Shape ───────────────────────────────────────────────────────────────────
-- What every isle's shape shares (IslandIsles: each isle's own shape reads
-- through to these).
IslandConfig.Shape = {
	coastWobble = 0,       -- (the land is the islets: no single coast)
	seaFloor = -26,        -- the sea bed between and round them
	voxel = 4,             -- terrain resolution (the water)
	pathWidth = 10,        -- the stair paths
	pathSlope = 0.5,       -- (climbing no steeper)
	spireFrom = math.huge, -- (an isle's summit region only if it sets one)
}
-- The isles, in order: Level 1 to Level 6.
IslandConfig.Isles = require(script.Parent:WaitForChild("IslandIsles"))
-- The open sea round the route, past every isle (studs).
IslandConfig.SEA_MARGIN = 320

-- ── Biomes ──────────────────────────────────────────────────────────────────
-- Each region is a sector of the island round its bearing (width: degrees
-- either side, blended at the edges) between two fractions of the coast's
-- radius. `danger` sets which enemies its sources raise and its chests'
-- odds; `height` and `rough` shape its ground.
export type Region = {
	id: string,
	name: string,
	bearing: number,
	width: number,
	inner: number,
	outer: number,
	danger: number,      -- 1 (the shore) .. 4 (the highlands, the caves)
	height: number,      -- added to the island's height there
	rough: number,       -- noise amplitude
	color: Color3,       -- its accent on the HUD
}
IslandConfig.Regions = {
	-- (bearing, width, inner, outer, height, rough: unused now that each
	-- islet is its own biome; kept for the type)
	shore = {
		id = "shore", name = "The Shipwreck Coast", bearing = 0, width = 180, inner = 0, outer = 1,
		danger = 1, height = 0, rough = 0, color = Color3.fromRGB(110, 220, 220),
	},
	ruins = {
		id = "ruins", name = "The Forgotten Isle", bearing = 0, width = 180, inner = 0, outer = 1,
		danger = 1, height = 0, rough = 0, color = Color3.fromRGB(130, 210, 90),
	},
	forest = {
		id = "forest", name = "The Corrupted Isle", bearing = 0, width = 180, inner = 0, outer = 1,
		danger = 2, height = 0, rough = 0, color = Color3.fromRGB(200, 90, 255),
	},
	highlands = {
		id = "highlands", name = "The Infernal Isle", bearing = 0, width = 180, inner = 0, outer = 1,
		danger = 3, height = 0, rough = 0, color = Color3.fromRGB(255, 120, 50),
	},
	frozen = {
		id = "frozen", name = "The Frozen Isle", bearing = 0, width = 180, inner = 0, outer = 1,
		danger = 4, height = 0, rough = 0, color = Color3.fromRGB(150, 215, 255),
	},
	sunken = {
		id = "sunken", name = "The Sunken Isle", bearing = 0, width = 180, inner = 0, outer = 1,
		danger = 5, height = 0, rough = 0, color = Color3.fromRGB(90, 230, 240),
	},
	sanctuary = {
		id = "sanctuary", name = "The Shattered Isle", bearing = 0, width = 180, inner = 0, outer = 1,
		danger = 6, height = 0, rough = 0, color = Color3.fromRGB(230, 50, 60),
	},
} :: { [string]: Region }
IslandConfig.RegionOrder = { "shore", "ruins", "forest", "highlands", "frozen", "sunken", "sanctuary" }

-- ── Survival ────────────────────────────────────────────────────────────────
-- A wave every WAVE_SECONDS of the run's clock (DifficultyManager: the same
-- clock as the HUD's TIME SURVIVED): how many enemies are out at once, which
-- kinds, and how often elites come all climb with it. Each enemy's own
-- health and damage climb with the run's Threat tier, as in every dungeon
-- (DifficultyManager.GetMobScale), not twice. Solo is the baseline; every
-- extra player adds a share of the population and of each enemy's health,
-- not a full copy of either.
IslandConfig.Survival = {
	WAVE_SECONDS = 50,
	SPAWN_TICK = 1.6,                 -- seconds between spawn passes
	ALIVE_BASE = 14,                  -- enemies alive at once on wave 1, solo
	ALIVE_PER_WAVE = 2.2,
	ALIVE_MAX = 60,
	ALIVE_PER_EXTRA_PLAYER = 0.45,    -- × the population, for each player past the first
	HEALTH_PER_EXTRA_PLAYER = 0.25,   -- × each enemy's health, for each player past the first
	DANGER_HEALTH = 0.2,              -- × each enemy's health per level past 1 (its XP too)
	DANGER_DAMAGE = 0.12,             -- × each enemy's damage per level past 1
	AGGRO = 170,                      -- how far an island enemy notices you (the dungeon's is 70)
	ELITE_BASE = 0.03, ELITE_PER_WAVE = 0.012, ELITE_MAX = 0.22,
	BEHEMOTH_EVERY = 5,               -- a Cursed Behemoth every this many waves (from wave 5)
	SPAWN_MIN = 34, SPAWN_MAX = 105,  -- how far from a player a spawn source must be
	DESPAWN = 230,                    -- an enemy this far from every player is taken back
	BATCH = 4,                        -- most raised by one source in one pass
	LEVEL_XP = 140,                   -- the island's first level (a kill is ~25 XP x its kind's)
	LEVEL_GROWTH = 1.17,              -- each level asks this much more than the last
}

-- The roster: four of each biome's own (IslandMobs registers their kinds),
-- each raised from `from` wave on at its weight, only from sources in its
-- `regions` (the Hollow Caves raise the Corrupted Forest's).
export type Archetype = { id: string, name: string, kind: string, from: number, weight: number, minDanger: number?, elite: boolean?, regions: { string }? }
local SHORE, RUINS, FOREST, SUNKEN, HIGH, SPIRE = { "shore" }, { "ruins" }, { "forest" }, { "sunken" }, { "highlands" }, { "sanctuary" }
local FROZEN = { "frozen" }
IslandConfig.Enemies = {
	-- the Shipwreck Coast
	{ id = "raider", name = "Pirate Raider", kind = "pirate_raider", from = 1, weight = 10, regions = SHORE },
	{ id = "gunner", name = "Pirate Gunner", kind = "pirate_gunner", from = 1, weight = 5, regions = SHORE },
	{ id = "shark", name = "Reef Shark", kind = "reef_shark", from = 2, weight = 5, regions = SHORE },
	{ id = "crab", name = "Crustacean Brute", kind = "crustacean_brute", from = 3, weight = 2, regions = SHORE },
	-- the Verdant Ruins
	{ id = "warrior", name = "Jungle Warrior", kind = "jungle_warrior", from = 1, weight = 10, regions = RUINS },
	{ id = "jarcher", name = "Jungle Archer", kind = "jungle_archer", from = 1, weight = 5, regions = RUINS },
	{ id = "vine", name = "Vine Crawler", kind = "vine_crawler", from = 2, weight = 5, regions = RUINS },
	{ id = "guardian", name = "Stone Guardian", kind = "stone_guardian", from = 3, weight = 2, regions = RUINS },
	-- the Corrupted Forest
	{ id = "stalker", name = "Corrupted Stalker", kind = "corrupted_stalker", from = 1, weight = 9, regions = FOREST },
	{ id = "varcher", name = "Void Archer", kind = "void_archer", from = 1, weight = 5, regions = FOREST },
	{ id = "wisp", name = "Shadow Wisp", kind = "shadow_wisp", from = 2, weight = 5, regions = FOREST },
	{ id = "cbrute", name = "Corrupted Brute", kind = "corrupted_brute", from = 3, weight = 2.2, regions = FOREST },
	-- the Frozen Isle
	{ id = "wolf", name = "Frost Wolf", kind = "frost_wolf", from = 1, weight = 9, regions = FROZEN },
	{ id = "iarcher", name = "Ice Archer", kind = "ice_archer", from = 1, weight = 5, regions = FROZEN },
	{ id = "fwraith", name = "Frost Wraith", kind = "frost_wraith", from = 2, weight = 4, regions = FROZEN },
	{ id = "yeti", name = "Yeti Brute", kind = "yeti_brute", from = 3, weight = 2.2, regions = FROZEN },
	-- the Sunken Sanctuary
	{ id = "sprite", name = "Water Sprite", kind = "water_sprite", from = 1, weight = 9, regions = SUNKEN },
	{ id = "tarcher", name = "Tide Archer", kind = "tide_archer", from = 1, weight = 5, regions = SUNKEN },
	{ id = "sentinel", name = "Aqua Sentinel", kind = "aqua_sentinel", from = 2, weight = 4, regions = SUNKEN },
	{ id = "leviathan", name = "Guardian Leviathan", kind = "guardian_leviathan", from = 4, weight = 1.5, regions = SUNKEN },
	-- the Infernal Citadel
	{ id = "imp", name = "Lava Imp", kind = "lava_imp", from = 1, weight = 10, regions = HIGH },
	{ id = "farcher", name = "Fire Archer", kind = "fire_archer", from = 1, weight = 5, regions = HIGH },
	{ id = "flame", name = "Flame Elemental", kind = "flame_elemental", from = 2, weight = 4, regions = HIGH },
	{ id = "magma", name = "Magma Brute", kind = "magma_brute", from = 3, weight = 2.4, regions = HIGH },
	-- the Ancient Spire
	{ id = "drone", name = "Rift Drone", kind = "rift_drone", from = 1, weight = 8, regions = SPIRE },
	{ id = "mage", name = "Arcane Mage", kind = "arcane_mage", from = 1, weight = 5, regions = SPIRE },
	{ id = "golem", name = "Void Golem", kind = "void_golem", from = 3, weight = 2, regions = SPIRE },
	{ id = "knight", name = "Spire Knight", kind = "spire_knight", from = 5, weight = 1.2, regions = SPIRE, elite = true },
} :: { Archetype }
IslandConfig.Behemoth = { id = "behemoth", name = "Cursed Behemoth", kind = "crusher", scale = 1.35, health = 6, damage = 1.4, xp = 12 }

-- Spawn sources (places enemies climb out of) are each isle's own:
-- IslandIsles `sources`.

-- ── Chests ──────────────────────────────────────────────────────────────────
-- (how many of each kind, and where: each isle's own, IslandIsles `chests`)
IslandConfig.Chests = {
	respawnAfter = 150, -- seconds after a common chest is opened before another appears elsewhere
}

-- ── Loot ────────────────────────────────────────────────────────────────────
-- What each chest gives every player who's near when it opens (each their
-- own roll: no one takes another's). gear: the chance of a piece of
-- equipment (extra: a second); rarity: its odds (Luck and the island's
-- events tip them toward the rarer); gold: a range; consumable: the chance
-- of a draught or tonic; tome: the chance of a tome (PlayerStats.GrantTome);
-- bossItem: the chance the gear is the boss's own (a Ritual Chest).
export type LootTable = { gear: number, extra: number?, rarity: { [string]: number }, gold: { number }, consumable: number, tome: number, bossItem: number? }
IslandConfig.Loot = {
	tables = {
		common = { gear = 0.2, rarity = { Rare = 1 }, gold = { 25, 45 }, consumable = 0.65, tome = 0.08 },
		rare = { gear = 0.8, rarity = { Rare = 0.6, Epic = 0.34, Legendary = 0.06 }, gold = { 50, 90 }, consumable = 0.5, tome = 0.2 },
		cursed = { gear = 1, rarity = { Rare = 0.2, Epic = 0.55, Legendary = 0.25 }, gold = { 90, 150 }, consumable = 0.6, tome = 0.4 },
		elite = { gear = 1, rarity = { Rare = 0.45, Epic = 0.45, Legendary = 0.1 }, gold = { 60, 110 }, consumable = 0.4, tome = 0.25 },
		ritual = { gear = 1, extra = 1, rarity = { Epic = 0.5, Legendary = 0.5 }, gold = { 220, 340 }, consumable = 1, tome = 1, bossItem = 0.6 },
	} :: { [string]: LootTable },
	shareRadius = 70,          -- players this near a chest when it opens each get its loot
	eliteChestChance = 0.3,    -- an elite leaves an Elite Chest (a Behemoth always does)
	luckTilt = 2.5,            -- how far each point of Luck tips the odds toward the rarer
	cursedAmbush = { base = 5, perWave = 0.5, max = 10 },
}

-- ── The ritual ──────────────────────────────────────────────────────────────
IslandConfig.Ritual = {
	platformRadius = 62,
	statueRing = 40,
	sequenceSeconds = 7,     -- statues lighting in turn, the runes, the convergence
	cooldown = 90,           -- after a boss falls, before the altar answers again
	arenaRadius = 70,        -- the boss is held within this of the altar
	minWave = 3,             -- the altar is dormant until the island has stirred this long
}

-- ── Events ──────────────────────────────────────────────────────────────────
IslandConfig.Events = {
	firstAfter = 150,        -- seconds into the run before the first
	every = { 120, 170 },    -- seconds between events
	list = {
		rift_surge = { weight = 3, duration = 45, name = "RIFT SURGE", line = "Rifts tear open across the island: more enemies, more XP and loot" },
		cursed_treasure = { weight = 2, duration = 90, name = "CURSED TREASURE", line = "A cursed chest has surfaced, guarded by the island's dead" },
		ancient_echo = { weight = 2, duration = 90, name = "ANCIENT ECHO", line = "A forgotten shrine has awoken: a blessing, or a curse" },
		elite_hunt = { weight = 2, duration = 120, name = "ELITE HUNT", line = "A great beast roams the island: slay it for a prize" },
		blood_moon = { weight = 1, duration = 50, name = "BLOOD MOON", line = "The moon bleeds: enemies grow savage, rewards grow rich" },
	},
}

-- ── Lookups ─────────────────────────────────────────────────────────────────
function IslandConfig.Region(id: string?): Region?
	return if id then IslandConfig.Regions[id] else nil
end

return IslandConfig
