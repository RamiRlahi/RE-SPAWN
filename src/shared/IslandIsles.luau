--!strict
--[[
	IslandIsles.luau
	RE — the six islands of a run, Level 1 to Level 6, after the world map
	concept: each its own landmass, coastline, landmark and biome, laid out in
	a serpentine along the run's slot (+Z, alternating ±X), each crossing to
	the next sealed until that island's guardian falls at its altar.

	  1  The Forgotten Isle   tropical: beaches, jungle tiers, a waterfall, temples
	  2  The Corrupted Isle   twisted violet forest, crystals, a great dead tree
	  3  The Infernal Isle    an erupting volcano, lava rivers, the citadel's gate
	  4  The Frozen Isle      ice cliffs, snow pines, frozen lakes and falls
	  5  The Sunken Isle      flooded temples, stepped pools, platforms in the sea
	  6  The Shattered Isle   fragments over a purple void, the Ancient Spire

	Each isle's land (after Megabonk's): a broad dome to its summit, long
	rolling hills, wide open stretches to fight in, plateaus on gentle skirts
	and only here and there a sheer cliff (`terrain`, `masses`: a mass marked
	`true` is a cliff).

	Each isle's `shape` is read through IslandConfig.Shape (its defaults: the
	sea floor, the voxel size, the paths' width and slope); every u, v is in
	that isle's own `radius` from its centre (u east, v north). Bearings in
	degrees from +X toward +Z. See IslandGenerator for how a shape is built.
--]]

export type Isle = {
	id: string,
	name: string,
	level: number,
	region: string,          -- its biome (IslandConfig.Regions)
	boss: string,            -- the guardian its altar raises (IslandBosses)
	offset: { number },      -- { x, z } from the run's origin
	crossing: string,        -- the kind of the crossing that leads to it (IslandScenery spans)
	tower: string,           -- the summit's landmark (IslandScenery)
	altar: { [string]: Color3 }, -- the ritual site's stone, trim, runes, cracks and beam
	shape: { [string]: any },
	pois: { any },
	props: { [string]: { [string]: number } },
	sources: { [string]: { [string]: number } },
	chests: { { kind: string, count: number, regions: { string } } },
	piers: { number }?,
	lava: { number }?,       -- bearings of lava rivers from the summit down
	void: boolean?,          -- a purple void instead of the sea round it
	frozen: boolean?,        -- its water frozen over, its falls ice
	lilies: boolean?,        -- lily pads on its pools
}

local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end

-- (the run's six, in order)
local ISLES: { Isle } = {
	-- ── 1 · The Forgotten Isle ─────────────────────────────────────────────
	{
		id = "forgotten", name = "The Forgotten Isle", level = 1, region = "ruins", boss = "thorn_matriarch",
		offset = { -320, 0 }, crossing = "wood", tower = "temple",
		altar = { dark = rgb(70, 72, 82), dark2 = rgb(92, 96, 104), pave = rgb(118, 122, 126), pave2 = rgb(100, 106, 108),
			rune = rgb(110, 255, 140), crack = rgb(110, 255, 140), beam = rgb(120, 255, 160) },
		shape = {
			radius = 420, extent = 546,
			plateau = { radius = 70, height = 46 },
			islets = { { "main", 0.0, 0.02, 0.9 } },
			isletRegion = { main = "ruins" }, beachRegion = "shore",
			bridges = {},
			-- a broad green dome to the temple, rolling jungle round it, wide open
			-- lowlands; a broken ridge in the west, bluffs east and at the river's mouth
			terrain = { slope = 0.36, hills = 10, hillScale = 210, open = 0.5 },
			masses = {
				-- (plateaus: flat tops on long gentle skirts)
				{ 0.40, 0.38, 0.17, 30 }, { -0.42, 0.04, 0.15, 24 }, { -0.2, 0.5, 0.16, 20 }, { 0.25, 0.68, 0.1, 16 },
				-- (cliffs: sheer rock, never across the ways up)
				{ -0.6, -0.25, 0.07, 26, true }, { -0.52, -0.36, 0.06, 22, true }, { 0.16, -0.84, 0.09, 20, true },
				{ 0.62, 0.18, 0.06, 22, true }, { 0.5, 0.55, 0.05, 40, true },
			},
			climbs = { { 34, -56 }, { 178, 88 }, { 240, 190 } },
			paths = {},
			river = { width = 11, depth = 3, line = { { 0.0, -0.17 }, { -0.02, -0.40 }, { 0.03, -0.62 }, { 0.02, -1.1 } } },
			pools = { { -0.01, -0.29, 0.05 }, { -0.01, -0.46, 0.045 }, { 0.03, -0.58, 0.04 } },
			stacks = { { 130, 1.18, 24, 52 }, { 165, 1.16, 18, 44 }, { 100, 1.2, 20, 56, true }, { 30, 1.16, 14, 30 }, { -25, 1.14, 16, 40 }, { -125, 1.16, 12, 24 }, { -150, 1.2, 18, 34 } },
		},
		pois = {
			{ id = "docks", name = "The Broken Docks", region = "shore", bearing = -102, dist = 0.9, radius = 40, build = "docks", xp = 0 },
			{ id = "wreck", name = "Wreck of the Grey Gull", region = "shore", bearing = -4, dist = 0.92, radius = 34, build = "shipwreck", xp = 40 },
			{ id = "hunter", name = "Hunter's Clearing", region = "shore", bearing = -52, dist = 0.8, radius = 32, build = "camp", xp = 50 },
			{ id = "temple", name = "The Mossbound Arcade", region = "ruins", bearing = 44, dist = 0.56, radius = 46, build = "arches", xp = 80 },
			{ id = "circle", name = "The Ember Ring", region = "ruins", bearing = 178, dist = 0.42, radius = 34, build = "stone_circle", xp = 70 },
			{ id = "colossus", name = "The Fallen Colossus", region = "ruins", bearing = 75, dist = 0.86, radius = 36, build = "fallen_statue", xp = 70 },
			{ id = "summit", name = "The Mossbound Temple", region = "ruins", bearing = 0, dist = 0, radius = 70, build = "none", xp = 120 },
		},
		piers = { -36, -64, -20 },
		props = {
			shore = { palm = 50, driftwood = 16, crate = 12, barrel = 14, rock = 10, anchor = 3, net = 5, tidepool = 8, shell = 18, watchtower = 3, rowboat_chest = 1 },
			ruins = { pillar = 20, wall = 10, statue = 6, fern = 50, flower = 46, stoneface = 4, glyph = 12, rock = 8 },
		},
		sources = { shore = { clearing = 9, fissure = 3 }, ruins = { ruin = 16, fissure = 4 } },
		chests = {
			{ kind = "common", count = 20, regions = { "shore", "ruins" } },
			{ kind = "rare", count = 7, regions = { "ruins", "shore" } },
			{ kind = "cursed", count = 3, regions = { "ruins", "shore" } },
		},
	},

	-- ── 2 · The Corrupted Isle ─────────────────────────────────────────────
	{
		id = "corrupted", name = "The Corrupted Isle", level = 2, region = "forest", boss = "hollow_saint",
		offset = { 320, 1000 }, crossing = "wood", tower = "corrupt",
		altar = { dark = rgb(40, 30, 50), dark2 = rgb(56, 44, 68), pave = rgb(60, 48, 74), pave2 = rgb(46, 36, 58),
			rune = rgb(200, 90, 255), crack = rgb(255, 60, 200), beam = rgb(220, 80, 255) },
		shape = {
			radius = 400, extent = 520,
			plateau = { radius = 70, height = 40 },
			islets = {
				{ "main", 0.0, 0.0, 0.62 }, { "hollow", 0.58, 0.55, 0.24 }, { "shrine", -0.66, 0.36, 0.2 }, { "thorn", 0.12, -0.8, 0.18 },
			},
			isletRegion = { main = "forest", hollow = "forest", shrine = "forest", thorn = "forest" },
			bridges = { { "main", "hollow", "wood" }, { "main", "shrine", "stone" }, { "main", "thorn", "wood" } },
			-- a low blighted dome, the forest heaving in tight hummocks, black crags
			-- breaking through it
			terrain = { slope = 0.34, hills = 12, hillScale = 150, open = 0.4 },
			masses = {
				{ -0.25, 0.22, 0.14, 24 }, { 0.24, -0.22, 0.12, 18 },
				-- the satellites' woods, the great tree's rise
				{ 0.58, 0.55, 0.12, 20 }, { 0.6, 0.57, 0.06, 26 }, { -0.66, 0.36, 0.1, 16 }, { 0.12, -0.8, 0.08, 12 },
				-- black crags through the forest
				{ -0.36, -0.2, 0.05, 36, true }, { 0.38, 0.1, 0.04, 32, true }, { -0.1, -0.42, 0.045, 28, true }, { 0.05, 0.45, 0.05, 30, true },
			},
			climbs = { { 20, -70 }, { 150, 60 }, { 260, 190 } },
			paths = {},
			pools = {},
			stacks = { { 10, 1.2, 16, 36 }, { -40, 1.18, 14, 28 }, { 200, 1.18, 18, 40 }, { -150, 1.16, 12, 26 } },
		},
		pois = {
			{ id = "heart", name = "The Hollow Heart", region = "forest", bearing = 43.5, dist = 0.8, radius = 40, build = "grove", xp = 80 },
			{ id = "chapel", name = "The Rotting Chapel", region = "forest", bearing = 151.4, dist = 0.75, radius = 40, build = "corrupt_temple", xp = 80 },
			{ id = "thorns", name = "The Thornwall", region = "forest", bearing = -81.5, dist = 0.81, radius = 34, build = "thorn_ruins", xp = 70 },
			{ id = "summit", name = "The Blighted Altar", region = "forest", bearing = 0, dist = 0, radius = 70, build = "none", xp = 140 },
		},
		props = {
			forest = { corrupt_crystal = 40, roots = 26, mushroom = 40, shrine = 4, broken_statue = 6, floatrock = 18, darkpool = 8, thorns = 18, deadtree = 14 },
		},
		sources = { forest = { clearing = 18, rift = 5 } },
		chests = {
			{ kind = "common", count = 18, regions = { "forest" } },
			{ kind = "rare", count = 7, regions = { "forest" } },
			{ kind = "cursed", count = 4, regions = { "forest" } },
		},
	},

	-- ── 3 · The Infernal Isle ──────────────────────────────────────────────
	{
		id = "infernal", name = "The Infernal Isle", level = 3, region = "highlands", boss = "ashen_colossus",
		offset = { -320, 2000 }, crossing = "basalt", tower = "volcano",
		altar = { dark = rgb(34, 28, 30), dark2 = rgb(52, 42, 44), pave = rgb(48, 40, 40), pave2 = rgb(36, 30, 32),
			rune = rgb(255, 120, 40), crack = rgb(255, 90, 30), beam = rgb(255, 110, 40) },
		shape = {
			radius = 400, extent = 520,
			-- (the crater: the altar on its floor, its rim round it)
			plateau = { radius = 72, height = 58 },
			islets = { { "main", 0.0, 0.0, 0.84 }, { "forge", -0.7, -0.5, 0.18 } },
			isletRegion = { main = "highlands", forge = "highlands" },
			bridges = { { "main", "forge", "basalt" } },
			-- the volcano: one great cone (its crater the summit), steeper than the
			-- rest, jagged basalt crags on its flanks, shelves at its foot
			terrain = { slope = 0.42, hills = 6, hillScale = 120, open = 0.45 },
			masses = {
				-- the citadel's shelf, the forge islet
				{ 0.0, -0.6, 0.14, 22 }, { -0.7, -0.5, 0.1, 16 },
				-- crags on the cone's flanks
				{ 0.4, 0.22, 0.05, 44, true }, { -0.36, 0.3, 0.06, 48, true }, { 0.22, -0.4, 0.05, 40, true },
				{ -0.5, -0.1, 0.05, 34, true }, { 0.6, -0.2, 0.05, 26, true }, { -0.12, 0.6, 0.05, 30, true },
			},
			climbs = { { -30, -120 }, { 80, 170 }, { 200, 280 } },
			paths = {},
			pools = {},
			stacks = { { 30, 1.2, 18, 44 }, { 120, 1.18, 16, 40 }, { -60, 1.2, 14, 34 }, { 200, 1.18, 20, 48 } },
		},
		pois = {
			{ id = "citadel", name = "The Infernal Gate", region = "highlands", bearing = -90, dist = 0.6, radius = 44, build = "citadel", xp = 100 },
			{ id = "rift", name = "The Ember Rift", region = "highlands", bearing = 40, dist = 0.56, radius = 34, build = "ember_rift", xp = 80 },
			{ id = "forge", name = "The Black Forge", region = "highlands", bearing = -144.5, dist = 0.86, radius = 30, build = "forge", xp = 80 },
			{ id = "summit", name = "The Caldera", region = "highlands", bearing = 0, dist = 0, radius = 72, build = "none", xp = 160 },
		},
		lava = { 15, 95, 160, 235, 320 },
		props = {
			highlands = { spire = 30, crack = 34, vent = 16, barricade = 12, banner = 12, furnace = 6, demon_statue = 4, siege = 4, chains = 6, deadtree = 16 },
		},
		sources = { highlands = { fissure = 18, rift = 4, elite = 2 } },
		chests = {
			{ kind = "common", count = 16, regions = { "highlands" } },
			{ kind = "rare", count = 8, regions = { "highlands" } },
			{ kind = "cursed", count = 4, regions = { "highlands" } },
		},
	},

	-- ── 4 · The Frozen Isle ────────────────────────────────────────────────
	{
		id = "frozen", name = "The Frozen Isle", level = 4, region = "frozen", boss = "eclipse_wyrm",
		offset = { 320, 3000 }, crossing = "ice", tower = "ice", frozen = true,
		altar = { dark = rgb(150, 170, 190), dark2 = rgb(176, 196, 214), pave = rgb(200, 218, 232), pave2 = rgb(170, 192, 212),
			rune = rgb(110, 200, 255), crack = rgb(120, 220, 255), beam = rgb(140, 220, 255) },
		shape = {
			radius = 400, extent = 520,
			plateau = { radius = 70, height = 50 },
			islets = { { "main", 0.0, 0.0, 0.74 }, { "wreck", 0.66, -0.52, 0.18 }, { "village", -0.64, 0.46, 0.22 } },
			isletRegion = { main = "frozen", wreck = "frozen", village = "frozen" },
			bridges = { { "main", "wreck", "ice" }, { "main", "village", "ice" } },
			-- long snow dunes, broad and smooth, a high ice bluff and spires of ice
			terrain = { slope = 0.34, hills = 16, hillScale = 260, open = 0.45 },
			masses = {
				-- the temple's rise, a snowfield shelf
				{ 0.24, 0.42, 0.14, 28 }, { -0.22, -0.15, 0.16, 22 },
				-- the ice bluff, ice spires
				{ 0.45, 0.18, 0.08, 40, true }, { -0.45, 0.2, 0.05, 46, true }, { 0.5, -0.12, 0.05, 38, true }, { 0.1, 0.64, 0.04, 34, true },
				{ 0.66, -0.52, 0.08, 10 }, { -0.64, 0.46, 0.12, 14 },
			},
			climbs = { { 10, -80 }, { 140, 50 }, { 250, 170 } },
			paths = {},
			-- a frozen river: its falls ice, its lakes frozen over
			river = { width = 12, depth = 3, line = { { 0.04, -0.17 }, { 0.12, -0.36 }, { 0.08, -0.56 }, { 0.14, -0.8 } } },
			pools = { { 0.1, -0.3, 0.06 }, { 0.1, -0.47, 0.055 }, { -0.3, 0.12, 0.07, 4 }, { 0.32, 0.18, 0.06, 4 } },
			stacks = { { 20, 1.18, 16, 40 }, { 90, 1.2, 18, 48, true }, { -100, 1.18, 14, 32 }, { 200, 1.16, 16, 36 } },
		},
		pois = {
			{ id = "temple", name = "The Frostbound Temple", region = "frozen", bearing = 60, dist = 0.48, radius = 46, build = "frost_temple", xp = 110 },
			{ id = "wreck", name = "The Icebound Galleon", region = "frozen", bearing = -38.2, dist = 0.84, radius = 34, build = "frozen_wreck", xp = 90 },
			{ id = "village", name = "Hollowfrost", region = "frozen", bearing = 144.3, dist = 0.79, radius = 40, build = "frost_village", xp = 90 },
			{ id = "arch", name = "The Glass Arch", region = "frozen", bearing = -150, dist = 0.58, radius = 30, build = "ice_arch", xp = 70 },
			{ id = "summit", name = "The Rime Altar", region = "frozen", bearing = 0, dist = 0, radius = 70, build = "none", xp = 180 },
		},
		props = {
			frozen = { ice_crystal = 36, snow_drift = 30, rune_stone = 12, ice_arch = 2, frost_hut = 4, rock = 10, frozen_statue = 6 },
		},
		sources = { frozen = { clearing = 16, rift = 4, elite = 1 } },
		chests = {
			{ kind = "common", count = 16, regions = { "frozen" } },
			{ kind = "rare", count = 8, regions = { "frozen" } },
			{ kind = "cursed", count = 4, regions = { "frozen" } },
		},
	},

	-- ── 5 · The Sunken Isle ────────────────────────────────────────────────
	{
		id = "sunken", name = "The Sunken Isle", level = 5, region = "sunken", boss = "drowned_sovereign",
		offset = { -320, 4000 }, crossing = "stone", tower = "sunken", lilies = true,
		altar = { dark = rgb(50, 96, 104), dark2 = rgb(70, 124, 130), pave = rgb(96, 150, 150), pave2 = rgb(76, 128, 132),
			rune = rgb(90, 240, 255), crack = rgb(90, 240, 255), beam = rgb(110, 240, 255) },
		shape = {
			radius = 420, extent = 546,
			plateau = { radius = 70, height = 36 },
			islets = {
				{ "main", 0.0, 0.0, 0.7 }, { "east", 0.7, 0.32, 0.16 }, { "southwest", -0.62, -0.48, 0.17 }, { "north", 0.18, 0.82, 0.15 }, { "west", -0.76, 0.36, 0.14 },
			},
			isletRegion = { main = "sunken", east = "sunken", southwest = "sunken", north = "sunken", west = "sunken" },
			bridges = { { "main", "east", "stone" }, { "main", "southwest", "stone" }, { "main", "north", "stone" }, { "main", "west", "stone" } },
			-- low and open: gentle swells between the pools, the temples' platforms
			-- standing out of the sea
			terrain = { slope = 0.3, hills = 6, hillScale = 220, open = 0.6 },
			masses = {
				-- the basin's shelf, the aqueduct's rise
				{ 0.36, 0.06, 0.14, 16 }, { -0.22, 0.34, 0.12, 18 },
				-- the platforms rising from the sea
				{ 0.7, 0.32, 0.1, 12 }, { -0.62, -0.48, 0.11, 14 }, { 0.18, 0.82, 0.09, 12 }, { -0.76, 0.36, 0.08, 16 },
				-- (a few broken sea-cliffs)
				{ -0.3, -0.3, 0.05, 24, true }, { 0.45, 0.45, 0.04, 22, true },
			},
			climbs = { { 30, -60 }, { 160, 70 }, { 270, 180 } },
			paths = {},
			-- pools stepping down the tiers, a waterfall between each, and the
			-- great flooded basin on the east shelf
			river = { width = 12, depth = 3, line = { { 0.0, -0.17 }, { 0.05, -0.35 }, { -0.02, -0.55 }, { 0.0, -0.86 } } },
			pools = { { 0.0, -0.27, 0.06 }, { 0.04, -0.44, 0.06 }, { -0.01, -0.62, 0.05 }, { 0.36, 0.06, 0.1, 13 } },
			stacks = { { 60, 1.2, 14, 30 }, { -30, 1.16, 16, 34 }, { 200, 1.18, 14, 28 } },
		},
		pois = {
			{ id = "gate", name = "The Drowned Gate", region = "sunken", bearing = 9.5, dist = 0.365, radius = 44, build = "sunken_temple", xp = 120 },
			{ id = "aqueduct", name = "The Broken Aqueduct", region = "sunken", bearing = 125, dist = 0.42, radius = 46, build = "sunken_aqueduct", xp = 100 },
			{ id = "garden", name = "The Coral Garden", region = "sunken", bearing = -142, dist = 0.79, radius = 30, build = "fountain", xp = 80 },
			{ id = "summit", name = "The Tidal Altar", region = "sunken", bearing = 0, dist = 0, radius = 70, build = "none", xp = 200 },
		},
		props = {
			sunken = { sunk_column = 26, blue_crystal = 24, broken_statue = 6, kelp = 30, glyph = 6 },
		},
		sources = { sunken = { ruin = 16, rift = 4, elite = 1 } },
		chests = {
			{ kind = "common", count = 16, regions = { "sunken" } },
			{ kind = "rare", count = 9, regions = { "sunken" } },
			{ kind = "cursed", count = 4, regions = { "sunken" } },
		},
	},

	-- ── 6 · The Shattered Isle ─────────────────────────────────────────────
	{
		id = "shattered", name = "The Shattered Isle", level = 6, region = "sanctuary", boss = "riftbound_knight",
		offset = { 320, 5000 }, crossing = "obsidian", tower = "spire", void = true,
		altar = { dark = rgb(34, 30, 40), dark2 = rgb(48, 40, 54), pave = rgb(40, 36, 46), pave2 = rgb(30, 28, 36),
			rune = rgb(190, 90, 255), crack = rgb(235, 40, 55), beam = rgb(235, 40, 55) },
		shape = {
			radius = 420, extent = 546,
			plateau = { radius = 70, height = 60 },
			islets = {
				{ "main", 0.0, 0.0, 0.44 }, { "east", 0.62, 0.25, 0.2 }, { "north", 0.05, 0.78, 0.17 }, { "west", -0.52, 0.46, 0.2 },
				{ "southwest", -0.64, -0.22, 0.18 }, { "southeast", 0.46, -0.56, 0.18 },
			},
			isletRegion = { main = "sanctuary", east = "sanctuary", north = "sanctuary", west = "sanctuary", southwest = "sanctuary", southeast = "sanctuary" },
			bridges = {
				{ "main", "east", "obsidian" }, { "main", "north", "obsidian" }, { "main", "west", "obsidian" }, { "main", "southwest", "obsidian" },
				{ "main", "southeast", "obsidian" }, { "east", "north", "obsidian" },
			},
			-- the central mass a dome under the fortress, sheered off at its coast;
			-- the fragments sheer-sided plateaus, crags jutting from them
			terrain = { slope = 0.4, hills = 8, hillScale = 140, open = 0.4 },
			masses = {
				-- the fragments, each its own height
				{ 0.62, 0.25, 0.13, 26, true }, { 0.05, 0.78, 0.11, 22, true }, { -0.52, 0.46, 0.13, 30, true },
				{ -0.64, -0.22, 0.12, 20, true }, { 0.46, -0.56, 0.12, 24, true },
				-- (crags at the fragments' edges, clear of the stairs to their tops)
				{ 0.74, 0.17, 0.05, 46, true }, { -0.62, 0.57, 0.05, 52, true }, { 0.53, -0.67, 0.04, 42, true }, { -0.75, -0.13, 0.04, 36, true },
			},
			climbs = { { 30, -60 }, { 150, 60 }, { 270, 180 } },
			paths = {},
			pools = {},
			stacks = {},
		},
		pois = {
			{ id = "portal_e", name = "The Crimson Rift", region = "sanctuary", bearing = 22, dist = 0.67, radius = 30, build = "crimson_portal", xp = 120 },
			{ id = "portal_w", name = "The Weeping Rift", region = "sanctuary", bearing = 138.5, dist = 0.69, radius = 30, build = "crimson_portal", xp = 120 },
			{ id = "temple", name = "The Shattered Temple", region = "sanctuary", bearing = -50.6, dist = 0.72, radius = 40, build = "shattered_temple", xp = 120 },
			{ id = "summit", name = "The Ancient Spire", region = "sanctuary", bearing = 0, dist = 0, radius = 70, build = "none", xp = 250 },
		},
		props = {
			sanctuary = { red_crystal = 30, floatrock = 20, broken_statue = 8, chains = 8, rift_crack = 24, banner = 6 },
		},
		sources = { sanctuary = { ruin = 14, rift = 8, elite = 2 } },
		chests = {
			{ kind = "common", count = 14, regions = { "sanctuary" } },
			{ kind = "rare", count = 10, regions = { "sanctuary" } },
			{ kind = "cursed", count = 5, regions = { "sanctuary" } },
		},
	},
}

return ISLES
