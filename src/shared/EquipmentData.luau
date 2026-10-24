--!strict
--[[
	EquipmentData.luau
	The Forgotten Isle's gear: what's found in its chests and dropped by its
	elites and bosses, worn for the run (EquipmentManager) — never kept after
	it, never saved. Unlike the Armory's cosmetic gear (GearData), each piece
	has stats and a perk that changes how you fight.

	  EquipmentData.Items[id]        an item
	  EquipmentData.Slots            the slots, in the order the HUD shows them
	  EquipmentData.Rarities[r]      a rarity's colour, order and salvage value
	  EquipmentData.Pool(opts)       ids that can drop (rarity, boss)

	An item's `stats` are tome effects (the same shape as TomeData's: stat,
	operation, value) folded into the run's stats by PlayerStats; its `perk`
	names the code that runs it (IslandPerks) and holds every number that
	code uses, so balancing is done here. Add an item by adding an entry:
	the loot rolls, the HUD and the perks read from this table.

	Combat sources: which damage sources count as basic attacks, as damage
	over time, as heavy hits (the perks that care).
--]]

local EquipmentData = {}

export type Effect = { stat: string, operation: string, value: number }
export type Item = {
	id: string,
	name: string,
	slot: string,       -- weapon / armor / helmet / accessory / boots / gloves
	rarity: string,     -- Rare / Epic / Legendary
	stats: { Effect },
	perk: { id: string, text: string, [string]: any },
	role: string,
	boss: string?,      -- only from this boss's Ritual Chest (IslandBosses)
	weight: number?,    -- how often it drops among its rarity (1 if nil)
}

EquipmentData.Slots = { "weapon", "armor", "helmet", "accessory", "accessory2", "boots", "gloves" }
EquipmentData.SlotNames = {
	weapon = "Weapon", armor = "Armor", helmet = "Helmet", accessory = "Accessory", accessory2 = "Accessory",
	boots = "Boots", gloves = "Gloves",
}
-- (an accessory goes in either accessory slot)
EquipmentData.SlotFits = { accessory = { "accessory", "accessory2" } }

EquipmentData.Rarities = {
	Rare = { order = 1, color = Color3.fromRGB(90, 160, 255), salvage = 35 },
	Epic = { order = 2, color = Color3.fromRGB(190, 100, 255), salvage = 80 },
	Legendary = { order = 3, color = Color3.fromRGB(255, 180, 50), salvage = 180 },
}

-- Most items one player carries (unequipped); more are salvaged for gold.
EquipmentData.BAG = 10

local function e(stat: string, op: string, value: number): Effect return { stat = stat, operation = op, value = value } end

EquipmentData.Items = {
	-- ── Weapons ─────────────────────────────────────────────────────────────
	ashfang_greatsword = {
		id = "ashfang_greatsword", name = "Ashfang Greatsword", slot = "weapon", rarity = "Epic", role = "Strong openings on elites and bosses",
		stats = { e("damage", "multiplier", 0.12) },
		perk = { id = "heavy_opener", text = "Heavy hits deal 20% more damage to enemies above 70% health", threshold = 0.7, bonus = 0.2 },
	},
	wardens_edge = {
		id = "wardens_edge", name = "Warden's Edge", slot = "weapon", rarity = "Rare", role = "Steady melee",
		stats = { e("damage", "multiplier", 0.08) },
		perk = { id = "fifth_hit", text = "Every fifth hit in a row deals 60% more and staggers normal enemies", every = 5, bonus = 0.6, stagger = 0.7, window = 2.5 },
	},
	stormpiercer_rapier = {
		id = "stormpiercer_rapier", name = "Stormpiercer Rapier", slot = "weapon", rarity = "Epic", role = "Mobile duelling",
		stats = { e("basicAttackSpeed", "percent", 0.08), e("damage", "multiplier", 0.06) },
		perk = { id = "thrust_rush", text = "Three basic hits in a row grant +25% movement speed for 3s", hits = 3, speed = 0.25, duration = 3, window = 2, cooldown = 4 },
	},
	plaguewood_longbow = {
		id = "plaguewood_longbow", name = "Plaguewood Longbow", slot = "weapon", rarity = "Rare", role = "Sustained ranged damage",
		stats = { e("critChance", "percent", 0.04), e("damage", "multiplier", 0.05) },
		perk = { id = "crit_poison", text = "Critical hits poison the target (stacks up to 5, 4 damage per stack every 0.5s for 3s)", perStack = 4, maxStacks = 5, duration = 3 },
	},
	riftcaller_staff = {
		id = "riftcaller_staff", name = "Riftcaller Staff", slot = "weapon", rarity = "Epic", role = "Ability builds",
		stats = { e("abilityCooldown", "percent", 0.05), e("abilityDamage", "percent", 0.08) },
		perk = { id = "arcane_echo", text = "Every fourth ability cast fires an arcane bolt at the nearest enemy", every = 4, damage = 45, range = 70 },
	},
	sunken_kings_axe = {
		id = "sunken_kings_axe", name = "Sunken King's Axe", slot = "weapon", rarity = "Legendary", role = "Elite hunting",
		stats = { e("damage", "multiplier", 0.18) },
		perk = { id = "elite_fury", text = "Killing an elite grants +30% damage for 8s", bonus = 0.3, duration = 8 },
	},
	-- ── Armor ───────────────────────────────────────────────────────────────
	bastion_plate = {
		id = "bastion_plate", name = "Bastion Plate", slot = "armor", rarity = "Epic", role = "Heavy defence",
		stats = { e("maxHealth", "add", 40), e("armor", "percent", 0.06) },
		perk = { id = "bulwark", text = "A hit for 18%+ of your max health grants a shield of 25% max health for 5s (12s cooldown)", threshold = 0.18, shield = 0.25, duration = 5, cooldown = 12 },
	},
	ashen_mantle = {
		id = "ashen_mantle", name = "Ashen Mantle", slot = "armor", rarity = "Rare", role = "Emergency survival",
		stats = { e("maxHealth", "add", 25) },
		perk = { id = "last_stand", text = "Take 25% less damage while below 40% health", below = 0.4, reduction = 0.25 },
	},
	stalker_leathers = {
		id = "stalker_leathers", name = "Stalker Leathers", slot = "armor", rarity = "Rare", role = "Agile combat",
		stats = { e("movementSpeed", "percent", 0.05), e("evasion", "percent", 0.04) },
		perk = { id = "dodge_crit", text = "Dodging an attack grants +20% critical chance for 3s", crit = 0.2, duration = 3, cooldown = 2 },
	},
	wyrmhide_armor = {
		id = "wyrmhide_armor", name = "Wyrmhide Armor", slot = "armor", rarity = "Legendary", role = "Boss defence",
		stats = { e("maxHealth", "add", 50), e("armor", "percent", 0.08) },
		perk = { id = "dragonhide", text = "Boss attacks deal 15% less damage to you", reduction = 0.15 },
	},
	plagueweave_robes = {
		id = "plagueweave_robes", name = "Plagueweave Robes", slot = "armor", rarity = "Epic", role = "Damage over time",
		stats = { e("maxHealth", "add", 20), e("abilityDamage", "percent", 0.06) },
		perk = { id = "venom_focus", text = "Dealing damage over time grants +20% ability damage for 4s", bonus = 0.2, duration = 4 },
	},
	-- ── Helmets ─────────────────────────────────────────────────────────────
	hollow_kings_crown = {
		id = "hollow_kings_crown", name = "Hollow King's Crown", slot = "helmet", rarity = "Legendary", role = "Ultimate builds",
		stats = { e("critChance", "percent", 0.04), e("abilityCooldown", "percent", 0.05) },
		perk = { id = "crown_ult", text = "Elite kills take 6s off your ultimate's cooldown", seconds = 6 },
	},
	ashguard_helm = {
		id = "ashguard_helm", name = "Ashguard Helm", slot = "helmet", rarity = "Rare", role = "Projectile defence",
		stats = { e("maxHealth", "add", 15) },
		perk = { id = "arrow_ward", text = "Take 25% less damage from ranged enemies", reduction = 0.25 },
	},
	oracles_veil = {
		id = "oracles_veil", name = "Oracle's Veil", slot = "helmet", rarity = "Epic", role = "Exploration",
		stats = { e("luck", "percent", 0.05) },
		perk = { id = "oracle", text = "Reveals elites and chests within 120 studs", radius = 120 },
	},
	-- ── Accessories ─────────────────────────────────────────────────────────
	ring_of_embers = {
		id = "ring_of_embers", name = "Ring of Embers", slot = "accessory", rarity = "Epic", role = "Area damage",
		stats = { e("critChance", "percent", 0.03) },
		perk = { id = "ember_burst", text = "Critical hits have a 35% chance to explode, dealing 50% of the hit around the target", chance = 0.35, radius = 10, share = 0.5, cooldown = 0.4 },
	},
	riftglass_pendant = {
		id = "riftglass_pendant", name = "Riftglass Pendant", slot = "accessory", rarity = "Legendary", role = "Ability defence",
		stats = { e("abilityCooldown", "percent", 0.06) },
		perk = { id = "rift_shield", text = "Every third ability cast grants a shield of 15% max health for 5s", every = 3, shield = 0.15, duration = 5 },
	},
	hunters_sigil = {
		id = "hunters_sigil", name = "Hunter's Sigil", slot = "accessory", rarity = "Rare", role = "Elite and boss damage",
		stats = { e("damage", "multiplier", 0.04) },
		perk = { id = "hunter", text = "Deal 15% more damage to elites and bosses", bonus = 0.15 },
	},
	greedbound_coin = {
		id = "greedbound_coin", name = "Greedbound Coin", slot = "accessory", rarity = "Epic", role = "Risk and reward",
		stats = { e("goldGain", "percent", 0.4) },
		perk = { id = "greed", text = "+40% gold from kills, but consumables heal 15% less", healMult = 0.85 },
	},
	heartroot_charm = {
		id = "heartroot_charm", name = "Heartroot Charm", slot = "accessory", rarity = "Rare", role = "Exploring",
		stats = { e("healthRegenPerMinute", "add", 30) },
		perk = { id = "heartroot", text = "Healing received is 25% stronger outside boss fights", bonus = 0.25 },
	},
	soulkeeper_relic = {
		id = "soulkeeper_relic", name = "Soulkeeper Relic", slot = "accessory", rarity = "Legendary", role = "Emergency survival",
		stats = { e("maxHealth", "add", 20) },
		perk = { id = "soulkeeper", text = "Once per run, survive a lethal hit at 25% health and take 50% less damage for 4s", health = 0.25, reduction = 0.5, duration = 4 },
	},
	-- ── Boots ───────────────────────────────────────────────────────────────
	wayfarers_boots = {
		id = "wayfarers_boots", name = "Wayfarer's Boots", slot = "boots", rarity = "Rare", role = "Faster exploring",
		stats = { e("movementSpeed", "percent", 0.06) },
		perk = { id = "wayfarer", text = "Opening a chest grants +30% movement speed for 8s", speed = 0.3, duration = 8 },
	},
	riftwalker_greaves = {
		id = "riftwalker_greaves", name = "Riftwalker Greaves", slot = "boots", rarity = "Epic", role = "Aggressive mobility",
		stats = { e("movementSpeed", "percent", 0.05), e("evasion", "percent", 0.03) },
		perk = { id = "riftwalk", text = "Enemies you dash through take 30% more damage from you for 4s", bonus = 0.3, duration = 4, radius = 8 },
	},
	ironroot_sabatons = {
		id = "ironroot_sabatons", name = "Ironroot Sabatons", slot = "boots", rarity = "Epic", role = "Steady frontline",
		stats = { e("maxHealth", "add", 30), e("armor", "percent", 0.05) },
		perk = { id = "ironroot", text = "You can't be knocked back", knockback = 0 },
	},
	-- ── Gloves ──────────────────────────────────────────────────────────────
	gravegrip_gauntlets = {
		id = "gravegrip_gauntlets", name = "Gravegrip Gauntlets", slot = "gloves", rarity = "Rare", role = "Melee pressure",
		stats = { e("damage", "multiplier", 0.04) },
		perk = { id = "gravegrip", text = "Each melee hit in a row grants +3% attack speed (up to 6 stacks)", perStack = 0.03, maxStacks = 6, window = 2.5 },
	},
	tempest_grips = {
		id = "tempest_grips", name = "Tempest Grips", slot = "gloves", rarity = "Epic", role = "Crowd control",
		stats = { e("abilityDamage", "percent", 0.05), e("critChance", "percent", 0.02) },
		perk = { id = "tempest", text = "Ability hits have a 30% chance to chain lightning to 3 nearby enemies (40% of the hit)", chance = 0.3, bounces = 3, range = 18, share = 0.4, cooldown = 0.6 },
	},

	-- ── Boss-exclusive (each boss's Ritual Chest) ───────────────────────────
	tidebreaker_trident = {
		id = "tidebreaker_trident", name = "Tidebreaker Trident", slot = "weapon", rarity = "Legendary", role = "Control", boss = "drowned_sovereign",
		stats = { e("damage", "multiplier", 0.16), e("knockback", "percent", 0.3) },
		perk = { id = "tidal_wave", text = "Every sixth hit releases a wave dealing 80% of the hit around you", every = 6, share = 0.8, radius = 14, window = 3 },
	},
	colossus_core = {
		id = "colossus_core", name = "Molten Colossus Core", slot = "armor", rarity = "Legendary", role = "Fire and survival", boss = "ashen_colossus",
		stats = { e("maxHealth", "add", 70), e("armor", "percent", 0.1) },
		perk = { id = "magma_core", text = "Being hit erupts fire around you for 40 damage (3s cooldown)", damage = 40, radius = 12, cooldown = 3 },
	},
	saints_halo = {
		id = "saints_halo", name = "Halo of the Hollow Saint", slot = "helmet", rarity = "Legendary", role = "Healing and ultimates", boss = "hollow_saint",
		stats = { e("abilityCooldown", "percent", 0.1), e("healthRegenPerMinute", "add", 40) },
		perk = { id = "halo", text = "Every ability cast heals 4% of your max health", heal = 0.04 },
	},
	thornmother_grasp = {
		id = "thornmother_grasp", name = "Thornmother's Grasp", slot = "gloves", rarity = "Legendary", role = "Poison", boss = "thorn_matriarch",
		stats = { e("damage", "multiplier", 0.1), e("lifesteal", "percent", 0.03) },
		perk = { id = "thorn_venom", text = "Every hit poisons (stacks up to 6, 3 damage per stack every 0.5s for 4s)", perStack = 3, maxStacks = 6, duration = 4 },
	},
	riftbound_blade = {
		id = "riftbound_blade", name = "Riftbound Blade", slot = "weapon", rarity = "Legendary", role = "Mobility and crits", boss = "riftbound_knight",
		stats = { e("damage", "multiplier", 0.14), e("critChance", "percent", 0.06) },
		perk = { id = "rift_strike", text = "Your first hit after a dash is a guaranteed critical", window = 2 },
	},
	eclipse_scale = {
		id = "eclipse_scale", name = "Eclipse Scale", slot = "accessory", rarity = "Legendary", role = "Offence", boss = "eclipse_wyrm",
		stats = { e("damage", "multiplier", 0.15), e("critDamage", "add", 0.25) },
		perk = { id = "eclipse", text = "Critical hits against enemies below 50% health deal 25% more", below = 0.5, bonus = 0.25 },
	},
} :: { [string]: Item }

-- ── Consumables (used the moment they're found) ─────────────────────────────
export type Consumable = { id: string, name: string, text: string, color: Color3 }
EquipmentData.Consumables = {
	healing_draught = { id = "healing_draught", name = "Healing Draught", text = "Restores 40% of your health", color = Color3.fromRGB(255, 90, 100) },
	fury_tonic = { id = "fury_tonic", name = "Tonic of Fury", text = "+25% damage for 25s", color = Color3.fromRGB(255, 140, 60) },
	swift_tonic = { id = "swift_tonic", name = "Tonic of Swiftness", text = "+20% movement speed for 25s", color = Color3.fromRGB(120, 230, 255) },
	insight_scroll = { id = "insight_scroll", name = "Scroll of Insight", text = "+120 XP", color = Color3.fromRGB(190, 160, 255) },
} :: { [string]: Consumable }

-- ── Combat sources (the perks that care) ────────────────────────────────────
-- Every class's basic attack (and its combo's steps).
EquipmentData.BASIC = {
	["VENOM ARROWS"] = true, ["SIX SHOOTER"] = true, ["FINAL SHOT"] = true,
	["SWORD COMBO"] = true, ["SWORD FINISHER"] = true,
	["BERSERK CLEAVE"] = true, ["BERSERK SMASH"] = true, ["BEAST CLAW"] = true, ["BEAST MAUL"] = true,
	["FLOWING FISTS"] = true, ["POWER PUNCH"] = true, ["POWER KNEE"] = true,
	["DAGGER"] = true, ["DAGGER STAB"] = true, ["ARCANE BOLT"] = true, ["CINDER SLASH"] = true,
	["RADIANT BOLT"] = true, ["ICE CRYSTAL"] = true,
}
-- The basic attacks that are melee (Gravegrip's stacks).
EquipmentData.MELEE = {
	["SWORD COMBO"] = true, ["SWORD FINISHER"] = true, ["BERSERK CLEAVE"] = true, ["BERSERK SMASH"] = true,
	["BEAST CLAW"] = true, ["BEAST MAUL"] = true, ["FLOWING FISTS"] = true, ["POWER PUNCH"] = true,
	["POWER KNEE"] = true, ["DAGGER"] = true, ["DAGGER STAB"] = true, ["CINDER SLASH"] = true,
}
-- Damage over time (Plagueweave's focus; it never chains, explodes or echoes).
EquipmentData.DOT = {
	BLEED = true, ["BURNING GROUND"] = true, SCORCH = true, VENOM = true, ["SHADOW POISON"] = true, IGNITE = true,
	["FIRE LINE"] = true, BLIZZARD = true, ["ICE BEAM"] = true, POISON = true, ["THORN VENOM"] = true,
}
-- Heavy hits (the Ashfang Greatsword): a combo's finisher, a slam, an execution.
EquipmentData.HEAVY_WORDS = { "FINISH", "SMASH", "SLAM", "EXECUTION", "BREAKER", "MAUL", "QUAKE", "UPHEAVAL", "FINAL SHOT", "DEADEYE", "ERUPTION", "COLLAPSE", "APOCALYPSE" }
function EquipmentData.IsHeavy(source: string): boolean
	for _, w in ipairs(EquipmentData.HEAVY_WORDS) do
		if string.find(source, w, 1, true) then return true end
	end
	return false
end

-- ── Lookups ─────────────────────────────────────────────────────────────────
function EquipmentData.Get(id: any): Item?
	return if typeof(id) == "string" then EquipmentData.Items[id] else nil
end

-- The ids that can drop at a rarity (never a boss's own, unless `boss` names it).
function EquipmentData.Pool(rarity: string, boss: string?): { string }
	local out = {}
	for id, item in pairs(EquipmentData.Items) do
		if item.rarity == rarity and (item.boss == nil or item.boss == boss) then table.insert(out, id) end
	end
	table.sort(out)
	return out
end

return EquipmentData
