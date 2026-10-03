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

	Effects use the same stat vocabulary as tomes and talents.
--]]

export type Effect = { stat: string, operation: "add" | "percent" | "multiplier", value: number }
export type Reward = {
	id: string,
	type: "character" | "variant" | "armor" | "relic" | "material" | "cosmetic",
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
	weight: number?,        -- relative weight within its rarity in a pool (default 1)
	secret: boolean?,       -- hidden until owned (shown as ??? in lists)
}

local R: { Reward } = {
	-- ── Normal characters (the playable classes) ─────────────────────────────
	{ id = "char_heavy_knight", type = "character", classId = "heavy_knight", rarity = "Rare", glyph = "⚔️",
		name = "Fire Knight", description = "Awakens the Fire Knight: +0.04× Damage as the Fire Knight.",
		effects = { { stat = "damage", operation = "multiplier", value = 0.04 } } },
	{ id = "char_ranger", type = "character", classId = "ranger", rarity = "Rare", glyph = "🏹",
		name = "Ranger", description = "Awakens the Ranger: +4% Crit Chance as the Ranger.",
		effects = { { stat = "critChance", operation = "percent", value = 0.04 } } },
	{ id = "char_cleric", type = "character", classId = "cleric", rarity = "Rare", glyph = "🕊️",
		name = "Cleric", description = "Awakens the Cleric: +40 Max HP as the Cleric.",
		effects = { { stat = "maxHealth", operation = "add", value = 40 } } },
	{ id = "char_ice_mage", type = "character", classId = "ice_mage", rarity = "Rare", glyph = "❄️",
		name = "Ice Mage", description = "Awakens the Ice Mage: +8% Ability Area as the Ice Mage.",
		effects = { { stat = "size", operation = "percent", value = 0.08 } } },
	{ id = "char_gunslinger", type = "character", classId = "gunslinger", rarity = "Rare", glyph = "🤠",
		name = "Gunslinger", description = "Awakens the Gunslinger: +4% Crit Chance as the Gunslinger.",
		effects = { { stat = "critChance", operation = "percent", value = 0.04 } } },
	{ id = "char_swordsman", type = "character", classId = "swordsman", rarity = "Rare", glyph = "🗡️",
		name = "Sword Master", description = "Awakens the Sword Master: +8% Attack Speed as the Sword Master.",
		effects = { { stat = "basicAttackSpeed", operation = "percent", value = 0.08 } } },

	-- ── VFX variants (cosmetic colour schemes for ability effects) ──────────
	{ id = "dark_variant", type = "variant", rarity = "Legendary", glyph = "🌑", palette = "dark",
		name = "Dark", title = "Dark", accent = Color3.fromRGB(225, 225, 232),
		description = "Any class VFX variant: abilities turn black, outlined in white." },

	-- ── Class armor (cosmetic) ─────────────────────────────────────────────────
	{ id = "armor_heavy_knight", type = "armor", classId = "heavy_knight", rarity = "Epic", glyph = "🛡️",
		name = "Knight's Mantle", description = "Fire Knight outfit: a crimson cloth cape with a black fur mantle." },
	{ id = "armor_ranger", type = "armor", classId = "ranger", rarity = "Epic", glyph = "🧥",
		name = "Ranger's Cloak", description = "Ranger armor: the hooded hunting cloak." },
	{ id = "armor_cleric", type = "armor", classId = "cleric", rarity = "Epic", glyph = "🕊️",
		name = "Cleric's Vestments", description = "Cleric armor: holy vestments." },
	{ id = "armor_ice_mage", type = "armor", classId = "ice_mage", rarity = "Epic", glyph = "❄️",
		name = "Winter Cape", description = "Ice Mage armor: the flowing frost cape." },
	{ id = "armor_gunslinger", type = "armor", classId = "gunslinger", rarity = "Epic", glyph = "🤠",
		name = "Outlaw's Hat", description = "Gunslinger outfit: cowboy hat and spurred boots." },

	-- ── Materials ─────────────────────────────────────────────────────────────
	{ id = "shard_pouch", type = "material", rarity = "Common", glyph = "🔮", name = "Soul Shard Pouch",
		description = "10 Soul Shards (refine into Souls for talents).", currency = "soulShards", amount = 10, weight = 2 },
	{ id = "dust_pile", type = "material", rarity = "Common", glyph = "✨", name = "Relic Dust",
		description = "15 Relic Dust.", currency = "relicDust", amount = 15, weight = 2 },
	{ id = "ticket_single", type = "material", rarity = "Rare", glyph = "🎟️", name = "Summon Ticket",
		description = "1 Summon Ticket.", currency = "tickets", amount = 1 },

	-- ── Cosmetics ─────────────────────────────────────────────────────────────
	{ id = "title_wanderer", type = "cosmetic", rarity = "Rare", glyph = "🧭", name = "Title: Wanderer",
		title = "Wanderer", description = "A title for your profile." },
	{ id = "title_starborn", type = "cosmetic", rarity = "Epic", glyph = "🌠", name = "Title: Starborn",
		title = "Starborn", description = "A title for your profile." },
}

local byId: { [string]: Reward } = {}
for _, r in ipairs(R) do byId[r.id] = r end

-- Exclusive characters always wear their outfit; their armor is never a
-- summon reward. (The Sword Master's outfit is his fur-collared cloth cape,
-- which every client simulates locally: ClothCape / ClassCapes.)
local BUILT_IN_ARMOR: { [string]: boolean } = { ice_mage = true, gunslinger = true, swordsman = true }

-- Pools: which rewards a banner draws from (all by default).
local Pools: { [string]: { string } } = {
	standard = (function()
		local ids = {}
		for _, r in ipairs(R) do
			if not (r.type == "armor" and r.classId and BUILT_IN_ARMOR[r.classId]) then
				table.insert(ids, r.id)
			end
		end
		return ids
	end)(),
}

local GachaRewards = {}
GachaRewards.All = R
GachaRewards.BuiltInArmor = BUILT_IN_ARMOR

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
