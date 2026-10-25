--!strict
--[[
	GachaRewards
	Registry of everything a summon can give. Add an entry to add a reward —
	the server, odds panel, collection and cinematic all read from here.

	types
	  character  — a normal character (one of the playable classes). The first
	               copy AWAKENS it (a small permanent passive for that class);
	               further copies become Soul Shards → Souls → talents.
	  variant    — a VFX variant: a cosmetic colour scheme for ability effects
	               (VFXPalettes). Class-bound variants recolour one class; a
	               variant with no classId can be equipped on any class. Equip
	               one per class in the Collection. No stats. Copies become
	               Soul Shards.
	  armor      — a class's armor set (cosmetic, no stats). Without it the class
	               wears your own avatar plus its weapon. The first copy
	               unlocks and equips it; copies become Soul Shards.
	  relic      — equipment with stat effects (3 slots). Copies raise its level
	               (stronger effects), then overflow into Relic Dust.
	  material   — a currency bundle (Soul Shards, Relic Dust, Tickets).
	  cosmetic   — a title; copies become Relic Dust.
	  wings      — wings worn on the back (cosmetic, animated); copies become
	               Soul Shards.
	  mount      — a mount: press B to ride it (faster than running; a hit throws you off);
	               copies become Soul Shards.

	Effects use the same stat vocabulary as tomes and talents.
--]]

export type Effect = { stat: string, operation: "add" | "percent" | "multiplier", value: number }
export type Reward = {
	id: string,
	type: "character" | "variant" | "armor" | "relic" | "material" | "cosmetic" | "wings" | "mount",
	look: string?,          -- wings / mount: which model (WingsMounts)
	rarity: string,
	name: string,
	description: string,
	glyph: string,
	classId: string?,       -- character / variant / armor (nil variant = any class)
	effects: { Effect }?,   -- relic effects, awakening
	title: string?,         -- variant / cosmetic
	accent: Color3?,        -- variant
	palette: string?,       -- variant: VFXPalettes id
	currency: string?,      -- material
	amount: number?,        -- material
	noDrop: boolean?,       -- never rolled from a banner (shop / sets only)
	weight: number?,        -- relative weight within its rarity in a pool (default 1)
	secret: boolean?,       -- hidden until owned (shown as ??? in lists)
}

local R: { Reward } = {
	-- ── Normal characters (the playable classes) ─────────────────────────────
	{ id = "char_heavy_knight", type = "character", classId = "heavy_knight", rarity = "Rare", glyph = "FK",
		name = "Fire Knight", description = "Awakens the Fire Knight: +0.04× Damage as the Fire Knight.",
		effects = { { stat = "damage", operation = "multiplier", value = 0.04 } } },
	{ id = "char_ranger", type = "character", classId = "ranger", rarity = "Rare", glyph = "RA",
		name = "Ranger", description = "Awakens the Ranger: +4% Crit Chance as the Ranger.",
		effects = { { stat = "critChance", operation = "percent", value = 0.04 } } },
	{ id = "char_cleric", type = "character", classId = "cleric", rarity = "Rare", glyph = "CL",
		name = "Cleric", description = "Awakens the Cleric: +40 Max HP as the Cleric.",
		effects = { { stat = "maxHealth", operation = "add", value = 40 } } },
	{ id = "char_ice_mage", type = "character", classId = "ice_mage", rarity = "Rare", glyph = "IM",
		name = "Ice Mage", description = "Awakens the Ice Mage: +8% Ability Area as the Ice Mage.",
		effects = { { stat = "size", operation = "percent", value = 0.08 } } },
	{ id = "char_gunslinger", type = "character", classId = "gunslinger", rarity = "Rare", glyph = "GU",
		name = "Gunslinger", description = "Awakens the Gunslinger: +4% Crit Chance as the Gunslinger.",
		effects = { { stat = "critChance", operation = "percent", value = 0.04 } } },
	{ id = "char_swordsman", type = "character", classId = "swordsman", rarity = "Rare", glyph = "SM",
		name = "Sword Master", description = "Awakens the Sword Master: +8% Attack Speed as the Sword Master.",
		effects = { { stat = "basicAttackSpeed", operation = "percent", value = 0.08 } } },

	-- ── VFX variants (cosmetic colour schemes for ability effects) ──────────
	{ id = "dark_variant", type = "variant", rarity = "Legendary", glyph = "DA", palette = "dark",
		name = "Dark", title = "Dark", accent = Color3.fromRGB(225, 225, 232), noDrop = true,
		description = "Any class VFX variant: abilities turn black, outlined in white." },

	-- ── Class armor (cosmetic) ─────────────────────────────────────────────────
	{ id = "armor_heavy_knight", type = "armor", classId = "heavy_knight", rarity = "Epic", glyph = "KM",
		name = "Knight's Mantle", description = "Fire Knight outfit: a crimson cloth cape with a black fur mantle." },
	{ id = "armor_ranger", type = "armor", classId = "ranger", rarity = "Epic", glyph = "RC",
		name = "Ranger's Cloak", description = "Ranger armor: the hooded hunting cloak." },
	{ id = "armor_cleric", type = "armor", classId = "cleric", rarity = "Epic", glyph = "CV",
		name = "Cleric's Vestments", description = "Cleric armor: holy vestments." },
	{ id = "armor_ice_mage", type = "armor", classId = "ice_mage", rarity = "Epic", glyph = "WC",
		name = "Winter Cape", description = "Ice Mage armor: the flowing frost cape." },
	{ id = "armor_gunslinger", type = "armor", classId = "gunslinger", rarity = "Epic", glyph = "OH",
		name = "Outlaw's Hat", description = "Gunslinger outfit: cowboy hat and spurred boots." },
	{ id = "armor_swordsman", type = "armor", classId = "swordsman", rarity = "Epic", glyph = "SC",
		name = "Sword Master's Cape", description = "Swordsman outfit: the long fur-collared cloth cape." },
	{ id = "armor_rogue", type = "armor", classId = "rogue", rarity = "Epic", glyph = "SS",
		name = "Shadow Scarf", description = "Rogue outfit: the long scarf over the mouth, its tails streaming in the wind." },
	{ id = "armor_mage", type = "armor", classId = "mage", rarity = "Epic", glyph = "AR",
		name = "Arcanist's Robes", description = "Mage outfit: the gold-trimmed hooded robe with glowing eyes, and the long cloak." },
	{ id = "armor_martial_artist", type = "armor", classId = "martial_artist", rarity = "Epic", glyph = "FG",
		name = "Fighter's Gi", description = "Martial Artist outfit: the gi, the sash and the headband." },
	{ id = "armor_berserker", type = "armor", classId = "berserker", rarity = "Epic", glyph = "RV",
		name = "Ravager's Cape", description = "Berserker outfit: the ragged crimson feather cape." },


	-- ── Wings (cosmetic, worn everywhere; WingsMounts builds and animates them) ──
	{ id = "wings_raven", type = "wings", look = "raven", rarity = "Common", glyph = "RA", name = "Raven Wings",
		accent = Color3.fromRGB(40, 40, 55), description = "Black feathered wings." },
	{ id = "wings_bat", type = "wings", look = "bat", rarity = "Common", glyph = "BA", name = "Bat Wings",
		accent = Color3.fromRGB(120, 50, 170), description = "Leathery wings of the crypt bats." },
	{ id = "wings_leaf", type = "wings", look = "leaf", rarity = "Common", glyph = "LE", name = "Leaf Wings",
		accent = Color3.fromRGB(110, 210, 70), description = "Wings of living leaves." },
	{ id = "wings_frost", type = "wings", look = "frost", rarity = "Rare", glyph = "FR", name = "Frost Wings",
		accent = Color3.fromRGB(120, 210, 255), description = "Wings of glittering ice." },
	{ id = "wings_ember", type = "wings", look = "ember", rarity = "Rare", glyph = "EM", name = "Ember Wings",
		accent = Color3.fromRGB(255, 120, 40), description = "Burning wings that shed sparks." },
	{ id = "wings_storm", type = "wings", look = "storm", rarity = "Rare", glyph = "ST", name = "Storm Wings",
		accent = Color3.fromRGB(80, 160, 255), description = "Crackling wings of lightning." },
	{ id = "wings_moon", type = "wings", look = "moon", rarity = "Rare", glyph = "MO", name = "Moon Wings",
		accent = Color3.fromRGB(225, 230, 255), description = "Pale wings under a crescent moon." },
	{ id = "wings_venom", type = "wings", look = "venom", rarity = "Epic", glyph = "VE", name = "Venom Wings",
		accent = Color3.fromRGB(120, 230, 60), description = "Dripping wings of a venom moth." },
	{ id = "wings_void", type = "wings", look = "void", rarity = "Epic", glyph = "VO", name = "Void Wings",
		accent = Color3.fromRGB(170, 60, 255), description = "Torn wings leaking the void." },
	{ id = "wings_celestial", type = "wings", look = "celestial", rarity = "Legendary", glyph = "CE", name = "Celestial Wings",
		accent = Color3.fromRGB(255, 215, 110), description = "Radiant golden wings." },
	{ id = "wings_dragon", type = "wings", look = "dragon", rarity = "Legendary", glyph = "DR", name = "Dragon Wings",
		accent = Color3.fromRGB(220, 90, 40), description = "Great scaled wings of a dragon." },
	{ id = "wings_eclipse", type = "wings", look = "eclipse", rarity = "Mythic", glyph = "EC", name = "Eclipse Wings",
		accent = Color3.fromRGB(255, 70, 120), description = "One wing of night, one of day." },
	{ id = "wings_cosmic", type = "wings", look = "cosmic", rarity = "Mythic", glyph = "CO", name = "Cosmic Wings",
		accent = Color3.fromRGB(150, 90, 255), description = "Wings full of stars." },

	-- ── Mounts (B to ride, faster than running; WingsMounts builds them) ──
	{ id = "mount_dire_wolf", type = "mount", look = "dire_wolf", rarity = "Rare", glyph = "DW", name = "Dire Wolf",
		weight = 0.5, accent = Color3.fromRGB(120, 120, 130), description = "A grey wolf with a saddle. Press B to ride it, faster than running." },
	{ id = "mount_war_boar", type = "mount", look = "war_boar", rarity = "Rare", glyph = "WB", name = "War Boar",
		weight = 0.5, accent = Color3.fromRGB(120, 80, 50), description = "A tusked boar in war harness. Press B to ride it, faster than running." },
	{ id = "mount_skeleton_horse", type = "mount", look = "skeleton_horse", rarity = "Rare", glyph = "SH", name = "Skeleton Horse",
		weight = 0.5, accent = Color3.fromRGB(230, 225, 205), description = "Bones held together by green fire. Press B to ride it, faster than running." },
	{ id = "mount_giant_spider", type = "mount", look = "giant_spider", rarity = "Epic", glyph = "GS", name = "Giant Spider",
		weight = 0.35, accent = Color3.fromRGB(90, 40, 90), description = "Eight legs and too many eyes. Press B to ride it, faster than running." },
	{ id = "mount_frost_wolf", type = "mount", look = "frost_wolf", rarity = "Epic", glyph = "FW", name = "Frost Wolf",
		weight = 0.35, accent = Color3.fromRGB(160, 215, 255), description = "A wolf carved from winter. Press B to ride it, faster than running." },
	{ id = "mount_dire_bear", type = "mount", look = "dire_bear", rarity = "Epic", glyph = "DB", name = "Dire Bear",
		weight = 0.35, accent = Color3.fromRGB(90, 60, 40), description = "An armoured bear. Press B to ride it, faster than running." },
	{ id = "mount_flame_ram", type = "mount", look = "flame_ram", rarity = "Epic", glyph = "FR", name = "Flame Ram",
		weight = 0.35, accent = Color3.fromRGB(255, 140, 50), description = "Curled horns wreathed in fire. Press B to ride it, faster than running." },
	{ id = "mount_venom_scorpion", type = "mount", look = "venom_scorpion", rarity = "Epic", glyph = "VS", name = "Venom Scorpion",
		weight = 0.3, accent = Color3.fromRGB(110, 220, 60), description = "A scorpion with a glowing sting. Press B to ride it, faster than running." },
	{ id = "mount_shadow_panther", type = "mount", look = "shadow_panther", rarity = "Epic", glyph = "SP", name = "Shadow Panther",
		weight = 0.3, accent = Color3.fromRGB(150, 80, 255), description = "A panther made of shadow. Press B to ride it, faster than running." },
	{ id = "mount_crystal_stag", type = "mount", look = "crystal_stag", rarity = "Epic", glyph = "CS", name = "Crystal Stag",
		weight = 0.3, accent = Color3.fromRGB(150, 200, 255), description = "A stag with antlers of crystal. Press B to ride it, faster than running." },
	{ id = "mount_magma_lizard", type = "mount", look = "magma_lizard", rarity = "Epic", glyph = "ML", name = "Magma Lizard",
		weight = 0.3, accent = Color3.fromRGB(255, 90, 30), description = "A lizard with cracks of magma. Press B to ride it, faster than running." },
	{ id = "mount_magic_carpet", type = "mount", look = "magic_carpet", rarity = "Epic", glyph = "MC", name = "Magician's Carpet",
		weight = 0.25, accent = Color3.fromRGB(255, 200, 45), description = "A floating purple-and-gold carpet with tasselled corners. Press B to sit on it, faster than running." },
	{ id = "mount_infernal_dragon", type = "mount", look = "infernal_dragon", rarity = "Legendary", glyph = "ID", name = "Infernal Dragon",
		weight = 0.25, accent = Color3.fromRGB(230, 60, 30), description = "A dragon of fire. Press B to ride it, faster than running." },
	{ id = "mount_storm_wyvern", type = "mount", look = "storm_wyvern", rarity = "Legendary", glyph = "SW", name = "Storm Wyvern",
		weight = 0.25, accent = Color3.fromRGB(70, 150, 255), description = "A wyvern trailing lightning. Press B to ride it, faster than running." },
	{ id = "mount_death_knight_horse", type = "mount", look = "death_knight_horse", rarity = "Legendary", glyph = "DK", name = "Death Knight Horse",
		weight = 0.25, accent = Color3.fromRGB(60, 140, 255), description = "An armoured black steed with a blue-fire mane. Press B to ride it, faster than running." },
	{ id = "mount_void_disc", type = "mount", look = "void_disc", rarity = "Legendary", glyph = "VD", name = "Void Disc",
		weight = 0.25, accent = Color3.fromRGB(170, 80, 255), description = "A floating black rune disc ringed in violet light, shards circling it. Press B to sit on it, faster than running." },
	{ id = "mount_void_serpent", type = "mount", look = "void_serpent", rarity = "Mythic", glyph = "VS", name = "Void Serpent",
		weight = 0.15, accent = Color3.fromRGB(170, 70, 255), description = "A coiling void serpent whose body breaks into floating segments of starlit void. You ride on its neck. Press B to ride it, faster than running." },
	{ id = "mount_celestial_lion", type = "mount", look = "celestial_lion", rarity = "Mythic", glyph = "CL", name = "Celestial Lion",
		weight = 0.15, accent = Color3.fromRGB(255, 220, 120), description = "A winged golden lion. Press B to ride it, faster than running." },
	{ id = "mount_eclipse_dragon", type = "mount", look = "eclipse_dragon", rarity = "Mythic", glyph = "ED", name = "Eclipse Dragon",
		weight = 0.15, accent = Color3.fromRGB(255, 190, 70), description = "A black dragon crowned by an eclipse. Press B to ride it, faster than running." },
	{ id = "mount_wishing_star", type = "mount", look = "wishing_star", rarity = "Mythic", glyph = "WS", name = "Wishing Star",
		weight = 0.15, accent = Color3.fromRGB(255, 220, 90), description = "A star fallen from the wish sky, trailing a rainbow. Press B to sit on it, faster than running." },
	{ id = "mount_ossuary_beetle", type = "mount", look = "ossuary_beetle", rarity = "Legendary", glyph = "OB", name = "Ossuary Beetle",
		weight = 0.25, accent = Color3.fromRGB(110, 255, 140), description = "A rhino beetle whose shell is fused from skulls and ribs, leaking green soul fire. Press B to ride it, faster than running." },
	{ id = "mount_tidal_hippocampus", type = "mount", look = "tidal_hippocampus", rarity = "Legendary", glyph = "TH", name = "Tidal Hippocampus",
		weight = 0.25, accent = Color3.fromRGB(110, 210, 230), description = "Half horse, half fish, swimming through the air on a ring of droplets. Press B to ride it, faster than running." },
	{ id = "mount_clockwork_gryphon", type = "mount", look = "clockwork_gryphon", rarity = "Legendary", glyph = "CG", name = "Clockwork Gryphon",
		weight = 0.25, accent = Color3.fromRGB(230, 170, 70), description = "A brass gryphon with gear wings and a spinning cog heart. Press B to ride it, faster than running." },
	{ id = "mount_blood_moon_warg", type = "mount", look = "blood_moon_warg", rarity = "Legendary", glyph = "BW", name = "Blood Moon Warg",
		weight = 0.25, accent = Color3.fromRGB(220, 40, 50), description = "A chained crimson wolf with a blood moon burning on its brow. Press B to ride it, faster than running." },
	{ id = "mount_abyssal_leviathan_ray", type = "mount", look = "abyssal_leviathan_ray", rarity = "Mythic", glyph = "LR", name = "Abyssal Leviathan Ray",
		weight = 0.15, accent = Color3.fromRGB(60, 220, 255), description = "A colossal manta from the abyss, glowing spots rippling down its wings, an ancient eye beneath you. Press B to sit on it, faster than running." },
	{ id = "mount_seraph_steed", type = "mount", look = "seraph_steed", rarity = "Mythic", glyph = "SS", name = "Seraph Steed",
		weight = 0.15, accent = Color3.fromRGB(255, 235, 180), description = "A white horse with six floating wings, a face of light and a golden halo. Press B to ride it, faster than running." },
	{ id = "mount_chronos_tortoise", type = "mount", look = "chronos_tortoise", rarity = "Mythic", glyph = "CT", name = "Chronos Tortoise",
		weight = 0.15, accent = Color3.fromRGB(230, 190, 110), description = "An ancient stone tortoise with a clock turning over its shell. Press B to ride it, faster than running." },
	{ id = "mount_nebula_kirin", type = "mount", look = "nebula_kirin", rarity = "Mythic", glyph = "NK", name = "Nebula Kirin",
		weight = 0.15, accent = Color3.fromRGB(230, 90, 220), description = "A glass deer-dragon with a galaxy swirling inside it. Press B to ride it, faster than running." },
	{ id = "mount_bloomheart_stag", type = "mount", look = "bloomheart_stag", rarity = "Mythic", glyph = "BS", name = "Bloomheart Stag",
		weight = 0.15, accent = Color3.fromRGB(90, 230, 150), description = "A white stag with blossoming antlers and a glowing flower for a heart. Press B to ride it, faster than running." },

	-- ── Secret mounts: boss trophies (never rolled; hidden until owned) ──────
	{ id = "mount_mini_ignarath", type = "mount", look = "mini_ignarath", rarity = "Mythic", secret = true, noDrop = true, glyph = "MI",
		name = "Mini Ignarath", accent = Color3.fromRGB(255, 120, 40), description = "Ignarath's Cinder Wyrmling: a tamed little dragon that tries its best to breathe fire. Press B to ride it, faster than running." },
	{ id = "mount_mini_zar0", type = "mount", look = "mini_zar0", rarity = "Mythic", secret = true, noDrop = true, glyph = "MZ",
		name = "Mini ZAR-0", accent = Color3.fromRGB(255, 60, 200), description = "ZAR-0, the Arcade Djinn, shrunk down and spitting coins. Press B to sit on it, faster than running." },
	{ id = "mount_mini_malakor", type = "mount", look = "mini_malakor", rarity = "Mythic", secret = true, noDrop = true, glyph = "MM",
		name = "Mini Malakor", accent = Color3.fromRGB(200, 20, 40), description = "Malakor, the Fallen Angel, small and loyal, its cracked halo always slipping. Press B to ride it, faster than running." },
	{ id = "mount_mini_bone_colossus", type = "mount", look = "mini_bone_colossus", rarity = "Mythic", secret = true, noDrop = true, glyph = "BC",
		name = "Mini Bone Colossus", accent = Color3.fromRGB(255, 140, 50), description = "A squat little bone golem with an ember for a heart. Press B to ride it, faster than running." },
	{ id = "mount_mini_iron_warlord", type = "mount", look = "mini_iron_warlord", rarity = "Mythic", secret = true, noDrop = true, glyph = "IW",
		name = "Mini Iron Warlord", accent = Color3.fromRGB(255, 130, 40), description = "A stubby iron war-beast flying the Warlord's banners. Press B to ride it, faster than running." },
	{ id = "mount_mini_hex_witch", type = "mount", look = "mini_hex_witch", rarity = "Mythic", secret = true, noDrop = true, glyph = "HW",
		name = "Mini Hex Witch", accent = Color3.fromRGB(120, 255, 90), description = "The Hex Witch's cauldron, walking on chicken legs under a giant hat. Press B to ride it, faster than running." },

	-- ── Materials ─────────────────────────────────────────────────────────────
	{ id = "shard_pouch", type = "material", rarity = "Common", glyph = "SS", name = "Soul Shard Pouch",
		description = "10 Soul Shards (refine into Souls for talents).", currency = "soulShards", amount = 10, weight = 2 },
	{ id = "dust_pile", type = "material", rarity = "Common", glyph = "RD", name = "Relic Dust",
		description = "15 Relic Dust.", currency = "relicDust", amount = 15, weight = 2 },
	{ id = "ticket_single", type = "material", rarity = "Rare", glyph = "ST", name = "Summon Ticket",
		description = "1 Summon Ticket.", currency = "tickets", amount = 1 },

	-- ── Cosmetics ─────────────────────────────────────────────────────────────
	{ id = "title_wanderer", type = "cosmetic", rarity = "Rare", glyph = "WA", name = "Title: Wanderer",
		title = "Wanderer", description = "A title for your profile." },
	{ id = "title_starborn", type = "cosmetic", rarity = "Epic", glyph = "ST", name = "Title: Starborn",
		title = "Starborn", description = "A title for your profile." },
}

local byId: { [string]: Reward } = {}
for _, r in ipairs(R) do byId[r.id] = r end

-- Classes that always wear their outfit, its armor never a summon reward.
-- (None now: every class's outfit is an armor reward, worn from the Wardrobe.)
local BUILT_IN_ARMOR: { [string]: boolean } = {}

-- Pools: which rewards a banner draws from.
local Pools: { [string]: { string } } = {
	standard = (function()
		local ids = {}
		for _, r in ipairs(R) do
			-- (mounts live on their own banner, with its own odds and pity)
			if not (r.type == "armor" and r.classId and BUILT_IN_ARMOR[r.classId]) and r.type ~= "mount" and not r.noDrop then
				table.insert(ids, r.id)
			end
		end
		return ids
	end)(),
	mounts = (function()
		local ids = {}
		for _, r in ipairs(R) do
			if (r.type == "mount" or r.type == "material" or r.type == "cosmetic") and not r.noDrop then
				table.insert(ids, r.id)
			end
		end
		return ids
	end)(),
}

-- ── Collection sets ──────────────────────────────────────────────────────────
-- Owning every item of a set completes it: a one-time bonus and a badge in the
-- Collection. `items` lists reward ids; sets built from a type pick up new
-- rewards of that type automatically.
export type Set = { id: string, name: string, glyph: string, description: string, items: { string }, bonus: { [string]: number } }
local function idsWhere(pred: (Reward) -> boolean): { string }
	local out = {}
	for _, r in ipairs(R) do
		if pred(r) then table.insert(out, r.id) end
	end
	return out
end
local Sets: { Set } = {
	{ id = "set_heroes", name = "Heroes Awakened", glyph = "HA", description = "Awaken every class.",
		items = idsWhere(function(r) return r.type == "character" end), bonus = { tickets = 10 } },
	{ id = "set_vanguard", name = "Armored Vanguard", glyph = "AV", description = "Every class armor from the summons.",
		items = idsWhere(function(r) return r.type == "armor" and not (r.classId and BUILT_IN_ARMOR[r.classId]) end), bonus = { tickets = 10 } },
	{ id = "set_skyborne", name = "Skyborne", glyph = "SK", description = "Every pair of wings.",
		items = idsWhere(function(r) return r.type == "wings" end), bonus = { tickets = 15, crystals = 300 } },
	{ id = "set_beastmaster", name = "Beastmaster", glyph = "BM", description = "Every mount.",
		items = idsWhere(function(r) return r.type == "mount" and not r.secret end), bonus = { tickets = 20, crystals = 500 } },
	{ id = "set_night_sky", name = "Child of the Night Sky", glyph = "CN", description = "The Dark variant and both star-touched titles.",
		items = { "dark_variant", "title_wanderer", "title_starborn" }, bonus = { tickets = 5, relicDust = 200 } },
}

local GachaRewards = {}
GachaRewards.All = R
GachaRewards.BuiltInArmor = BUILT_IN_ARMOR
GachaRewards.Sets = Sets

function GachaRewards.Get(id: string): Reward?
	return byId[id]
end

function GachaRewards.Pool(poolId: string): { string }
	return Pools[poolId] or Pools.standard
end

-- Rewards of one rarity within a pool.
function GachaRewards.InPoolByRarity(poolId: string, rarity: string): { Reward }
	local out = {}
	for _, id in ipairs(GachaRewards.Pool(poolId)) do
		local r = byId[id]
		if r and r.rarity == rarity then table.insert(out, r) end
	end
	return out
end

return GachaRewards
