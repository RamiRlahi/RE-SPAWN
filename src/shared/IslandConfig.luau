--!strict
--[[
	IslandConfig.luau
	The Forgotten Isle (MapData "isle"): every number the mode runs on, kept
	apart from the code that runs it. The island itself (IslandGenerator),
	the survival loop (IslandMode), the chests (IslandChests), the ritual and
	its bosses (IslandRitual, IslandBosses) and the HUD (IslandHUD) all read
	from here; nothing else in the mode hardcodes these values.

	Island space: studs from the island's centre (IslandConfig.Origin(slot) in
	the world); +X east, +Z north, Y up from the sea's surface. Bearings in
	degrees from +X toward +Z (north is 90, west 180, south -90).
--]]

local IslandConfig = {}

-- ── Where it sits ───────────────────────────────────────────────────────────
-- Each run has its own slot (RunManager), 2040 studs apart along +X like the
-- dungeons; the island is built far out along +Z, clear of every dungeon and
-- of the lobby.
IslandConfig.SLOT_SPACING = 2040
IslandConfig.ORIGIN_Z = 6200
function IslandConfig.Origin(slot: number): Vector3
	return Vector3.new(slot * IslandConfig.SLOT_SPACING + 400, 0, IslandConfig.ORIGIN_Z)
end

-- ── Shape ───────────────────────────────────────────────────────────────────
IslandConfig.Shape = {
	radius = 430,          -- the coast, on average
	coastWobble = 0.14,    -- how far the coast wanders from the circle (fraction)
	seaFloor = -26,        -- the sea bed off the coast
	extent = 600,          -- half the square built (island and the sea round it)
	voxel = 4,             -- terrain resolution
	plateau = { radius = 78, height = 46 }, -- the Ancient Sanctuary's hill
}
-- The open sea round the built square, to the slot's edge (a shallow sheet
-- of water: nothing swims there, it only hides the end of the world)
IslandConfig.SEA = { halfX = 1000, halfZ = 1400, step = 200 }

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
	shore = {
		id = "shore", name = "The Forsaken Shore", bearing = -90, width = 50, inner = 0.55, outer = 1.05,
		danger = 1, height = -4, rough = 2.5, color = Color3.fromRGB(214, 196, 150),
	},
	forest = {
		id = "forest", name = "The Corrupted Forest", bearing = 180, width = 48, inner = 0.3, outer = 1.0,
		danger = 2, height = 2, rough = 6, color = Color3.fromRGB(120, 190, 90),
	},
	ruins = {
		id = "ruins", name = "The Sunken Ruins", bearing = 0, width = 48, inner = 0.3, outer = 1.0,
		danger = 3, height = -9, rough = 4, color = Color3.fromRGB(110, 170, 200),
	},
	highlands = {
		id = "highlands", name = "The Ashen Highlands", bearing = 70, width = 42, inner = 0.3, outer = 0.95,
		danger = 4, height = 22, rough = 9, color = Color3.fromRGB(255, 120, 60),
	},
	caves = {
		id = "caves", name = "The Hollow Caves", bearing = 128, width = 22, inner = 0.3, outer = 0.85,
		danger = 4, height = 34, rough = 7, color = Color3.fromRGB(150, 120, 255),
	},
	sanctuary = {
		id = "sanctuary", name = "The Ancient Sanctuary", bearing = 0, width = 180, inner = 0, outer = 0.2,
		danger = 3, height = 0, rough = 0, color = Color3.fromRGB(190, 90, 255),
	},
} :: { [string]: Region }
IslandConfig.RegionOrder = { "shore", "forest", "ruins", "highlands", "caves", "sanctuary" }

-- ── The Hollow Caves ────────────────────────────────────────────────────────
-- Tunnels through the ridge, each from a mouth on one side to a mouth on
-- another (bearing, fraction of the coast), its floor at `floor` studs, with
-- crystal halls along it (fraction of the way).
IslandConfig.Caves = {
	floor = 18, radius = 9, hallRadius = 17,
	tunnels = {
		{ from = { 152, 0.62 }, to = { 104, 0.6 }, halls = { 0.5 } },        -- forest ↔ highlands (a shortcut)
		{ from = { 140, 0.86 }, to = { 128, 0.34 }, halls = { 0.35, 0.72 } }, -- the coast ↔ the sanctuary's foot
	},
}

-- ── Points of interest ──────────────────────────────────────────────────────
-- Named places: discovering one (coming within `radius`) gives XP once per
-- player and names it on screen. Each is built by IslandGenerator from its
-- `build` piece.
export type Poi = { id: string, name: string, region: string, bearing: number, dist: number, radius: number, build: string, xp: number }
IslandConfig.Pois = {
	{ id = "docks", name = "The Broken Docks", region = "shore", bearing = -90, dist = 0.93, radius = 40, build = "docks", xp = 0 },
	{ id = "wreck", name = "Wreck of the Grey Gull", region = "shore", bearing = -62, dist = 0.9, radius = 34, build = "shipwreck", xp = 40 },
	{ id = "grove", name = "The Twisted Grove", region = "forest", bearing = 196, dist = 0.62, radius = 40, build = "grove", xp = 60 },
	{ id = "hunter", name = "Hunter's Clearing", region = "forest", bearing = 160, dist = 0.82, radius = 32, build = "camp", xp = 50 },
	{ id = "temple", name = "The Drowned Temple", region = "ruins", bearing = 8, dist = 0.6, radius = 46, build = "temple", xp = 80 },
	{ id = "colossus", name = "The Fallen Colossus", region = "ruins", bearing = -24, dist = 0.82, radius = 36, build = "fallen_statue", xp = 70 },
	{ id = "fort", name = "The Ashen Fort", region = "highlands", bearing = 62, dist = 0.7, radius = 44, build = "fort", xp = 90 },
	{ id = "rift", name = "The Ember Rift", region = "highlands", bearing = 84, dist = 0.48, radius = 34, build = "ember_rift", xp = 90 },
	{ id = "hollow", name = "The Crystal Hollow", region = "caves", bearing = 128, dist = 0.6, radius = 30, build = "none", xp = 100 },
	{ id = "sanctuary", name = "The Ancient Sanctuary", region = "sanctuary", bearing = 0, dist = 0, radius = 70, build = "none", xp = 120 },
} :: { Poi }

-- ── Props ───────────────────────────────────────────────────────────────────
-- How many of each piece a region scatters (IslandKit builds them). Kept
-- modest: the generated island is terrain; parts are only what terrain
-- can't be.
IslandConfig.Props = {
	shore = { palm = 14, driftwood = 18, crate = 10, rock = 14 },
	forest = { tree = 110, deadtree = 26, mushroom = 34, log = 20, rock = 12 },
	ruins = { pillar = 40, wall = 22, statue = 6, rock = 10, deadtree = 10 },
	highlands = { spire = 22, crack = 26, deadtree = 18, rock = 18 },
	caves = { rock = 16, deadtree = 6 },
}

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
	DANGER_HEALTH = 0.1,              -- × each enemy's health per region danger past 1 (its XP too)
	AGGRO = 170,                      -- how far an island enemy notices you (the dungeon's is 70)
	ELITE_BASE = 0.03, ELITE_PER_WAVE = 0.012, ELITE_MAX = 0.22,
	BEHEMOTH_EVERY = 5,               -- a Cursed Behemoth every this many waves (from wave 5)
	SPAWN_MIN = 34, SPAWN_MAX = 105,  -- how far from a player a spawn source must be
	DESPAWN = 230,                    -- an enemy this far from every player is taken back
	BATCH = 4,                        -- most raised by one source in one pass
	LEVEL_XP = 140,                   -- the island's first level (a kill is ~25 XP x its kind's)
	LEVEL_GROWTH = 1.17,              -- each level asks this much more than the last
}

-- The roster: each archetype is an existing MobKinds kind under its island
-- name, raised from `from` wave on at its weight (scaled by the source's
-- region danger). `regions`: only there (any region if nil).
export type Archetype = { id: string, name: string, kind: string, from: number, weight: number, minDanger: number?, elite: boolean? }
IslandConfig.Enemies = {
	{ id = "thrall", name = "Hollow Thrall", kind = "zombie", from = 1, weight = 10 },
	{ id = "hound", name = "Plague Hound", kind = "ghoul", from = 1, weight = 5 },
	{ id = "archer", name = "Rot Archer", kind = "skeleton", from = 2, weight = 5 },
	{ id = "acolyte", name = "Corrupted Acolyte", kind = "necromancer", from = 3, weight = 3, minDanger = 2 },
	{ id = "brute", name = "Grave Brute", kind = "brute", from = 3, weight = 2.5, minDanger = 2 },
	{ id = "stalker", name = "Rift Stalker", kind = "wraith", from = 4, weight = 3, minDanger = 3 },
	{ id = "knight", name = "Ironbound Knight", kind = "executioner", from = 6, weight = 1.2, minDanger = 3, elite = true },
} :: { Archetype }
IslandConfig.Behemoth = { id = "behemoth", name = "Cursed Behemoth", kind = "crusher", scale = 1.35, health = 6, damage = 1.4, xp = 12 }

-- Spawn sources: places enemies climb out of (IslandGenerator places them,
-- each marked with a small piece of its kind). Count per region.
IslandConfig.SpawnSources = {
	shore = { clearing = 5, fissure = 2 },
	forest = { clearing = 8, rift = 2 },
	ruins = { ruin = 8, fissure = 2 },
	highlands = { fissure = 7, rift = 2, elite = 1 },
	caves = { cave = 6 },
	sanctuary = {},
}

-- ── Chests ──────────────────────────────────────────────────────────────────
-- How many of each kind the island scatters, and where (region ids).
IslandConfig.Chests = {
	common = { count = 22, regions = { "shore", "forest", "ruins" } },
	rare = { count = 9, regions = { "caves", "ruins", "highlands", "forest" } },
	cursed = { count = 4, regions = { "forest", "ruins", "highlands" } },
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
