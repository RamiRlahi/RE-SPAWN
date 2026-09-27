--!strict
--[[
	GachaRewards
	Registry of everything a summon can give. Add an entry to add a reward —
	the server, odds panel, collection and cinematic all read from here.

	types
	  character  — a normal character (one of the playable classes). The first
	               copy AWAKENS it (a small permanent passive for that class);
	               further copies become Soul Shards → Souls → talents.
	  exclusive  — an exclusive character: a named, powerful variant of a class
	               with its own passive and colours. Equip one per class in the
	               Collection. Copies raise Ascension (stronger passive), then
	               overflow into Ascension Sigils.
	  relic      — equipment with stat effects (3 slots). Copies raise its level
	               (stronger effects), then overflow into Relic Dust.
	  material   — a currency bundle (Soul Shards, Relic Dust, Sigils, Tickets).
	  cosmetic   — a title; copies become Relic Dust.

	Effects use the same stat vocabulary as tomes and talents.
--]]

export type Effect = { stat: string, operation: "add" | "percent" | "multiplier", value: number }
export type Reward = {
	id: string,
	type: "character" | "exclusive" | "relic" | "material" | "cosmetic",
	rarity: string,
	name: string,
	description: string,
	glyph: string,
	classId: string?,       -- character / exclusive
	effects: { Effect }?,   -- exclusive passive, relic effects, awakening
	title: string?,         -- exclusive / cosmetic
	accent: Color3?,        -- exclusive
	currency: string?,      -- material
	amount: number?,        -- material
	weight: number?,        -- relative weight within its rarity in a pool (default 1)
	secret: boolean?,       -- hidden until owned (shown as ??? in lists)
}

local R: { Reward } = {
	-- ── Normal characters (the playable classes) ─────────────────────────────
	{ id = "char_heavy_knight", type = "character", classId = "heavy_knight", rarity = "Rare", glyph = "⚔️",
		name = "Heavy Knight", description = "Awakens the Heavy Knight: +0.04× Damage as the Knight.",
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

	-- ── Exclusive characters ─────────────────────────────────────────────────
	{ id = "ashen_warlord", type = "exclusive", classId = "heavy_knight", rarity = "Epic", glyph = "🔥",
		name = "Ashen Warlord", title = "Ashen Warlord", accent = Color3.fromRGB(255, 110, 40),
		description = "Heavy Knight variant. +0.08× Damage, +4% Lifesteal.",
		effects = { { stat = "damage", operation = "multiplier", value = 0.08 }, { stat = "lifesteal", operation = "percent", value = 0.04 } } },
	{ id = "thornwarden", type = "exclusive", classId = "ranger", rarity = "Epic", glyph = "🌿",
		name = "Thornwarden", title = "Thornwarden", accent = Color3.fromRGB(120, 230, 90),
		description = "Ranger variant. +8% Crit Chance, +15% Projectile Speed.",
		effects = { { stat = "critChance", operation = "percent", value = 0.08 }, { stat = "projectileSpeed", operation = "percent", value = 0.15 } } },
	{ id = "divine_judgement", type = "exclusive", classId = "cleric", rarity = "Legendary", glyph = "⚖️",
		name = "Divine Judgement", title = "Divine Judgement", accent = Color3.fromRGB(255, 215, 110),
		description = "Cleric variant. −12% Ability Cooldowns, +60 Max HP, +0.06× Damage.",
		effects = { { stat = "abilityCooldown", operation = "percent", value = 0.12 }, { stat = "maxHealth", operation = "add", value = 60 },
			{ stat = "damage", operation = "multiplier", value = 0.06 } } },
	{ id = "winter_sovereign", type = "exclusive", classId = "ice_mage", rarity = "Mythic", glyph = "👁️", secret = true,
		name = "Winter Sovereign", title = "Winter Sovereign", accent = Color3.fromRGB(150, 210, 255),
		description = "Ice Mage variant. +0.15× Damage, +12% Ability Area, +15% Ability Duration.",
		effects = { { stat = "damage", operation = "multiplier", value = 0.15 }, { stat = "size", operation = "percent", value = 0.12 },
			{ stat = "abilityDuration", operation = "percent", value = 0.15 } } },

	-- ── Relics ────────────────────────────────────────────────────────────────
	{ id = "cracked_sigil", type = "relic", rarity = "Common", glyph = "💠", name = "Cracked Sigil",
		description = "+20 Max HP.", effects = { { stat = "maxHealth", operation = "add", value = 20 } } },
	{ id = "worn_charm", type = "relic", rarity = "Common", glyph = "🧿", name = "Worn Charm",
		description = "+4% Move Speed.", effects = { { stat = "movementSpeed", operation = "percent", value = 0.04 } } },
	{ id = "ember_fragment", type = "relic", rarity = "Common", glyph = "🌋", name = "Ember Fragment",
		description = "+0.03× Damage.", effects = { { stat = "damage", operation = "multiplier", value = 0.03 } } },
	{ id = "hunters_talisman", type = "relic", rarity = "Rare", glyph = "🎯", name = "Hunter's Talisman",
		description = "+4% Crit Chance.", effects = { { stat = "critChance", operation = "percent", value = 0.04 } } },
	{ id = "quickened_hourglass", type = "relic", rarity = "Rare", glyph = "⏳", name = "Quickened Hourglass",
		description = "+8% Attack Speed.", effects = { { stat = "basicAttackSpeed", operation = "percent", value = 0.08 } } },
	{ id = "warding_idol", type = "relic", rarity = "Rare", glyph = "🛡️", name = "Warding Idol",
		description = "+40 Max HP.", effects = { { stat = "maxHealth", operation = "add", value = 40 } } },
	{ id = "heart_of_winter", type = "relic", rarity = "Epic", glyph = "💙", name = "Heart of Winter",
		description = "−8% Ability Cooldowns.", effects = { { stat = "abilityCooldown", operation = "percent", value = 0.08 } } },
	{ id = "bloodstone", type = "relic", rarity = "Epic", glyph = "🩸", name = "Bloodstone",
		description = "+4% Lifesteal.", effects = { { stat = "lifesteal", operation = "percent", value = 0.04 } } },
	{ id = "colossus_seal", type = "relic", rarity = "Epic", glyph = "🗿", name = "Colossus Seal",
		description = "+10% Ability Area.", effects = { { stat = "size", operation = "percent", value = 0.1 } } },
	{ id = "crown_of_the_sun", type = "relic", rarity = "Legendary", glyph = "👑", name = "Crown of the Sun",
		description = "+0.1× Damage, +5% Crit Chance.",
		effects = { { stat = "damage", operation = "multiplier", value = 0.1 }, { stat = "critChance", operation = "percent", value = 0.05 } } },

	-- ── Materials ─────────────────────────────────────────────────────────────
	{ id = "shard_pouch", type = "material", rarity = "Common", glyph = "🔮", name = "Soul Shard Pouch",
		description = "10 Soul Shards (refine into Souls for talents).", currency = "soulShards", amount = 10, weight = 2 },
	{ id = "dust_pile", type = "material", rarity = "Common", glyph = "✨", name = "Relic Dust",
		description = "15 Relic Dust.", currency = "relicDust", amount = 15, weight = 2 },
	{ id = "ticket_single", type = "material", rarity = "Rare", glyph = "🎟️", name = "Summon Ticket",
		description = "1 Summon Ticket.", currency = "tickets", amount = 1 },
	{ id = "ascension_sigil", type = "material", rarity = "Rare", glyph = "🌟", name = "Ascension Sigil",
		description = "1 Ascension Sigil (ascends exclusive characters).", currency = "ascension", amount = 1 },

	-- ── Cosmetics ─────────────────────────────────────────────────────────────
	{ id = "title_wanderer", type = "cosmetic", rarity = "Rare", glyph = "🧭", name = "Title: Wanderer",
		title = "Wanderer", description = "A title for your profile." },
	{ id = "title_starborn", type = "cosmetic", rarity = "Epic", glyph = "🌠", name = "Title: Starborn",
		title = "Starborn", description = "A title for your profile." },
}

local byId: { [string]: Reward } = {}
for _, r in ipairs(R) do byId[r.id] = r end

-- Pools: which rewards a banner draws from (all by default).
local Pools: { [string]: { string } } = {
	standard = (function()
		local ids = {}
		for _, r in ipairs(R) do table.insert(ids, r.id) end
		return ids
	end)(),
}

local GachaRewards = {}
GachaRewards.All = R

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
