--!strict
--[[
	TomeData
	Authoritative definitions for collectible run tomes. Stat systems should consume
	the `effects` values rather than parsing the display text.
--]]

export type TomeCategory = "Base" | "Unlockable" | "Gunslinger" | "Boon" | "Relic"
export type TomeEffect = {
	stat: string,
	operation: "add" | "percent" | "multiplier" | "random",
	value: number?,
	description: string,
}

export type TomeDefinition = {
	id: string,
	name: string,
	category: TomeCategory,
	description: string,
	effects: { TomeEffect },
	classId: string?, -- class-only upgrade (offered only to that class)
	-- Boons (they change how you fight, not just numbers): up to maxLevel
	-- levels, each level's text in `levels`; at max they can evolve (Evolutions).
	maxLevel: number?,
	levels: { string }?,
}

-- An evolution: a boon taken to its max level, plus a tome (`with`) or your
-- class (`classId`, and its signature skill), becomes something new. Found
-- ones are kept in the Build Codex.
export type Evolution = {
	id: string,
	name: string,
	boon: string,
	with: string?,      -- the tome that unlocks it (class-free evolutions)
	classId: string?,   -- the class whose skill it changes
	skill: string?,     -- that skill's name (for the text)
	description: string,
	color: Color3,
}

local TomeData: { [string]: TomeDefinition } = {
	agility = {
		id = "agility", name = "Agility Tome", category = "Base", description = "+15% Movement Speed",
		effects = { { stat = "movementSpeed", operation = "percent", value = 0.15, description = "+15% Movement Speed" } },
	},
	attack_speed = {
		id = "attack_speed", name = "Attack Speed Tome", category = "Base", description = "+15% Basic Attack Speed",
		effects = { { stat = "basicAttackSpeed", operation = "percent", value = 0.15, description = "+15% Basic Attack Speed" } },
	},
	cooldown = {
		id = "cooldown", name = "Cooldown Tome", category = "Base", description = "-8% Ability Cooldowns",
		effects = { { stat = "abilityCooldown", operation = "percent", value = 0.08, description = "-8% Ability Cooldowns" } },
	},
	damage = {
		id = "damage", name = "Damage Tome", category = "Base", description = "+15% Damage",
		effects = { { stat = "damage", operation = "multiplier", value = 0.15, description = "+15% Damage" } },
	},
	evasion = {
		id = "evasion", name = "Evasion Tome", category = "Base", description = "+10% Evasion",
		effects = { { stat = "evasion", operation = "percent", value = 0.10, description = "+10% Evasion" } },
	},
	gold = {
		id = "gold", name = "Golden Tome", category = "Base", description = "+12% Gold Gain",
		effects = { { stat = "goldGain", operation = "percent", value = 0.12, description = "+12% Gold Gain" } },
	},
	health = {
		id = "health", name = "Health Tome", category = "Base", description = "+25 Max HP",
		effects = { { stat = "maxHealth", operation = "add", value = 25, description = "+25 Max HP" } },
	},
	knockback = {
		id = "knockback", name = "Knockback Tome", category = "Base", description = "+20% Knockback",
		effects = { { stat = "knockback", operation = "percent", value = 0.20, description = "+20% Knockback" } },
	},
	precision = {
		id = "precision", name = "Precision Tome", category = "Base", description = "+7% Crit Chance",
		effects = { { stat = "critChance", operation = "percent", value = 0.07, description = "+7% Crit Chance" } },
	},
	projectile_speed = {
		id = "projectile_speed", name = "Projectile Speed Tome", category = "Base", description = "+15% Projectile Speed",
		effects = { { stat = "projectileSpeed", operation = "percent", value = 0.15, description = "+15% Projectile Speed" } },
	},
	regen = {
		id = "regen", name = "Regen Tome", category = "Base", description = "+40 HP Regen/min",
		effects = { { stat = "healthRegenPerMinute", operation = "add", value = 40, description = "+40 HP Regen/min" } },
	},
	shield = {
		-- Extra HP on top of max HP, drawn white in the health bar (lost first).
		id = "shield", name = "Shield Tome", category = "Base", description = "+25 Shield HP",
		effects = { { stat = "shield", operation = "add", value = 25, description = "+25 Shield HP" } },
	},
	silver = {
		id = "silver", name = "Silver Tome", category = "Base", description = "+12% Silver Gain",
		effects = { { stat = "silverGain", operation = "percent", value = 0.12, description = "+12% Silver Gain" } },
	},
	ricochet = {
		id = "ricochet", name = "Ricochet Tome", category = "Base", description = "+1 Ricochet",
		effects = { { stat = "ricochet", operation = "add", value = 1, description = "Projectiles bounce to +1 nearby enemy" } },
	},
	size = {
		id = "size", name = "Size Tome", category = "Base", description = "+30% Ability Size (max +75%)",
		effects = { { stat = "size", operation = "percent", value = 0.30, description = "+30% Ability Size" } },
	},
	armor = {
		id = "armor", name = "Armor Tome", category = "Unlockable", description = "+12% Armor",
		effects = { { stat = "armor", operation = "percent", value = 0.12, description = "+12% Armor" } },
	},
	attraction = {
		id = "attraction", name = "Attraction Tome", category = "Unlockable", description = "+75% Pickup Range",
		effects = { { stat = "pickupRange", operation = "percent", value = 0.75, description = "+75% Pickup Range" } },
	},
	bloody = {
		id = "bloody", name = "Bloody Tome", category = "Unlockable", description = "+10% Lifesteal",
		effects = { { stat = "lifesteal", operation = "percent", value = 0.10, description = "+10% Lifesteal" } },
	},
	chaos = {
		id = "chaos", name = "Chaos Tome", category = "Unlockable", description = "Random Stat Boost",
		effects = { { stat = "randomStat", operation = "random", description = "Random Stat Boost" } },
	},
	cursed = {
		-- Risk for reward: mobs hit you harder, you earn that much more gold.
		id = "cursed", name = "Cursed Tome", category = "Unlockable", description = "+15% Damage Taken, +15% Gold",
		effects = {
			{ stat = "difficulty", operation = "percent", value = 0.15, description = "+15% Damage Taken" },
			{ stat = "goldGain", operation = "percent", value = 0.15, description = "+15% Gold Gain" },
		},
	},
	duration = {
		id = "duration", name = "Duration Tome", category = "Unlockable", description = "+15% Duration",
		effects = { { stat = "abilityDuration", operation = "percent", value = 0.15, description = "+15% Duration" } },
	},
	luck = {
		-- Read by SpecialRooms: better odds at the wheel, coin and well, fewer
		-- chest traps, and higher-rank Vault chest loot.
		id = "luck", name = "Luck Tome", category = "Unlockable", description = "+7% Luck: better gambles & chest loot",
		effects = { { stat = "luck", operation = "percent", value = 0.07, description = "+7% Luck" } },
	},
	quantity = {
		id = "quantity", name = "Quantity Tome", category = "Unlockable", description = "+1 Projectile",
		effects = { { stat = "projectileCount", operation = "add", value = 1, description = "+1 Projectile" } },
	},
	thorns = {
		id = "thorns", name = "Thorns Tome", category = "Unlockable", description = "+15 Thorns Damage",
		effects = { { stat = "thornsDamage", operation = "add", value = 15, description = "+15 Thorns Damage" } },
	},

	-- ── Boons: they change how you fight (Boons.luau runs them) ──────────────
	-- Each level adds 1 to its stat (its level). Max level 3: then it can evolve.
	boon_ignite = {
		id = "boon_ignite", name = "Burning Blade", category = "Boon", maxLevel = 3,
		description = "Your hits can set enemies on fire.",
		levels = {
			"15% of your hits ignite: the enemy burns for 3s.",
			"25% of your hits ignite, and burns hit harder.",
			"35% of your hits ignite, burning harder still.",
		},
		effects = { { stat = "boon_ignite", operation = "add", value = 1, description = "Burning Blade" } },
	},
	boon_frost = {
		id = "boon_frost", name = "Frostbite", category = "Boon", maxLevel = 3,
		description = "Your hits can chill enemies; chilled enemies take more damage.",
		levels = {
			"12% of your hits chill (slowed for 2s). Chilled enemies take +15% damage.",
			"20% of your hits chill. Chilled enemies take +25% damage.",
			"28% of your hits chill. Chilled enemies take +35% damage.",
		},
		effects = { { stat = "boon_frost", operation = "add", value = 1, description = "Frostbite" } },
	},
	boon_chain = {
		id = "boon_chain", name = "Chain Lightning", category = "Boon", maxLevel = 3,
		description = "Critical hits arc lightning to nearby enemies.",
		levels = {
			"Your crits arc to 1 nearby enemy for 40% damage.",
			"Your crits arc to 2 nearby enemies for 40% damage.",
			"Your crits arc to 3 nearby enemies for 45% damage.",
		},
		effects = { { stat = "boon_chain", operation = "add", value = 1, description = "Chain Lightning" } },
	},
	boon_bloodlust = {
		id = "boon_bloodlust", name = "Bloodlust", category = "Boon", maxLevel = 3,
		description = "Kills drive you on: each one stacks bonus damage for a few seconds.",
		levels = {
			"Each kill: +6% damage for 5s (up to 3 stacks).",
			"Each kill: +6% damage for 5s (up to 5 stacks).",
			"Each kill: +7% damage for 6s (up to 7 stacks).",
		},
		effects = { { stat = "boon_bloodlust", operation = "add", value = 1, description = "Bloodlust" } },
	},
	boon_corpse = {
		id = "boon_corpse", name = "Volatile Corpses", category = "Boon", maxLevel = 3,
		description = "Enemies you kill can explode, hurting those around them.",
		levels = {
			"15% of your kills explode for half the killing blow.",
			"25% of your kills explode for half the killing blow.",
			"35% of your kills explode, wider and harder.",
		},
		effects = { { stat = "boon_corpse", operation = "add", value = 1, description = "Volatile Corpses" } },
	},
	boon_execute = {
		id = "boon_execute", name = "Executioner", category = "Boon", maxLevel = 3,
		description = "Finish them: big damage to wounded enemies; elite kills heal you.",
		levels = {
			"+30% damage to enemies under 30% HP. Elite kills heal 5% HP.",
			"+45% damage to enemies under 30% HP. Elite kills heal 8% HP.",
			"+60% damage to enemies under 30% HP. Elite kills heal 12% HP.",
		},
		effects = { { stat = "boon_execute", operation = "add", value = 1, description = "Executioner" } },
	},
	boon_thunder = {
		id = "boon_thunder", name = "Thunderstrike", category = "Boon", maxLevel = 3,
		description = "Every few hits, lightning strikes your target and those around it.",
		levels = {
			"Every 10th hit calls lightning: 120% damage around the target.",
			"Every 8th hit calls lightning.",
			"Every 6th hit calls lightning, in a wider strike.",
		},
		effects = { { stat = "boon_thunder", operation = "add", value = 1, description = "Thunderstrike" } },
	},
	-- ── Run relics: found (bosses, elites, cursed altars), never levelled. Each
	-- bends a build, most at a price. Their own slots (3), apart from the tomes.
	relic_dragons_heart = {
		id = "relic_dragons_heart", name = "Dragon's Heart", category = "Relic", maxLevel = 1,
		description = "-20% ability cooldowns. Every ability you use costs 4% of your health.",
		effects = { { stat = "abilityCooldown", operation = "percent", value = 0.20, description = "-20% Ability Cooldowns" },
			{ stat = "relic_dragons_heart", operation = "add", value = 1, description = "Abilities cost health" } },
	},
	relic_bloodied_crown = {
		id = "relic_bloodied_crown", name = "Bloodied Crown", category = "Relic", maxLevel = 1,
		description = "Elite and boss kills heal you 15%. You earn 25% less gold.",
		effects = { { stat = "goldGain", operation = "percent", value = -0.25, description = "-25% Gold" },
			{ stat = "relic_bloodied_crown", operation = "add", value = 1, description = "Elite kills heal" } },
	},
	relic_frozen_soul = {
		id = "relic_frozen_soul", name = "Frozen Soul", category = "Relic", maxLevel = 1,
		description = "10% of your hits chill. Chilled enemies explode into ice when they die.",
		effects = { { stat = "relic_frozen_soul", operation = "add", value = 1, description = "Chilled enemies explode" } },
	},
	relic_berserkers_tooth = {
		id = "relic_berserkers_tooth", name = "Berserker's Tooth", category = "Relic", maxLevel = 1,
		description = "Below 30% health: +40% damage. 10% less max health.",
		effects = { { stat = "maxHealth", operation = "percent", value = -0.10, description = "-10% Max HP" },
			{ stat = "relic_berserkers_tooth", operation = "add", value = 1, description = "Low health: more damage" } },
	},
	relic_shattered_mirror = {
		id = "relic_shattered_mirror", name = "Shattered Mirror", category = "Relic", maxLevel = 1,
		description = "+35% damage. 30% less max health.",
		effects = { { stat = "damage", operation = "multiplier", value = 0.35, description = "+0.35× Damage" },
			{ stat = "maxHealth", operation = "percent", value = -0.30, description = "-30% Max HP" } },
	},
	relic_gamblers_coin = {
		id = "relic_gamblers_coin", name = "Gambler's Coin", category = "Relic", maxLevel = 1,
		description = "+15% crit chance. One crit in ten costs you 5% of your health.",
		effects = { { stat = "critChance", operation = "percent", value = 0.15, description = "+15% Crit Chance" },
			{ stat = "relic_gamblers_coin", operation = "add", value = 1, description = "Crits can bite back" } },
	},
	relic_hollow_lantern = {
		id = "relic_hollow_lantern", name = "Hollow Lantern", category = "Relic", maxLevel = 1,
		description = "+50% gold and +10% luck. 12% slower.",
		effects = { { stat = "goldGain", operation = "percent", value = 0.5, description = "+50% Gold" },
			{ stat = "luck", operation = "percent", value = 0.1, description = "+10% Luck" },
			{ stat = "movementSpeed", operation = "percent", value = -0.12, description = "-12% Movement Speed" } },
	},
	relic_iron_vow = {
		id = "relic_iron_vow", name = "Iron Vow", category = "Relic", maxLevel = 1,
		description = "+60 shield. Ability cooldowns 10% longer.",
		effects = { { stat = "shield", operation = "add", value = 60, description = "+60 Shield" },
			{ stat = "abilityCooldown", operation = "percent", value = -0.10, description = "+10% Ability Cooldowns" } },
	},
	relic_vampire_fang = {
		id = "relic_vampire_fang", name = "Vampire Fang", category = "Relic", maxLevel = 1,
		description = "+8% lifesteal. Every other heal on you is halved.",
		effects = { { stat = "lifesteal", operation = "percent", value = 0.08, description = "+8% Lifesteal" },
			{ stat = "relic_vampire_fang", operation = "add", value = 1, description = "Other heals halved" } },
	},
	relic_storm_eye = {
		id = "relic_storm_eye", name = "Eye of the Storm", category = "Relic", maxLevel = 1,
		description = "Every 5th critical hit calls down lightning around its target.",
		effects = { { stat = "relic_storm_eye", operation = "add", value = 1, description = "Crits call lightning" } },
	},
	-- class relics (offered only to their class)
	relic_frozen_heart = {
		id = "relic_frozen_heart", name = "Frozen Heart", category = "Relic", maxLevel = 1, classId = "ice_mage",
		description = "Every third chilled enemy you kill bursts into ice spikes around it.",
		effects = { { stat = "relic_frozen_heart", operation = "add", value = 1, description = "Ice spikes" } },
	},
	relic_blood_oath = {
		id = "relic_blood_oath", name = "Blood Oath", category = "Relic", maxLevel = 1, classId = "berserker",
		description = "+1% damage for every 1% of health you're missing.",
		effects = { { stat = "relic_blood_oath", operation = "add", value = 1, description = "Damage as health falls" } },
	},
	relic_saints_bell = {
		id = "relic_saints_bell", name = "Saint's Bell", category = "Relic", maxLevel = 1, classId = "cleric",
		description = "Healing an ally shocks the enemies around them for twice the heal.",
		effects = { { stat = "relic_saints_bell", operation = "add", value = 1, description = "Heals shock" } },
	},
	relic_loaded_dice = {
		id = "relic_loaded_dice", name = "Loaded Dice", category = "Relic", maxLevel = 1, classId = "gunslinger",
		description = "Every 6th Six Shooter hit is a guaranteed critical hit.",
		effects = { { stat = "relic_loaded_dice", operation = "add", value = 1, description = "Every 6th shot crits" } },
	},
	relic_ember_heart = {
		id = "relic_ember_heart", name = "Ember Heart", category = "Relic", maxLevel = 1, classId = "heavy_knight",
		description = "20% of your hits ignite. Burning enemies explode when they die.",
		effects = { { stat = "relic_ember_heart", operation = "add", value = 1, description = "Burning enemies explode" } },
	},
	relic_duelists_mark = {
		id = "relic_duelists_mark", name = "Duelist's Mark", category = "Relic", maxLevel = 1, classId = "swordsman",
		description = "+30% damage to elites and bosses.",
		effects = { { stat = "relic_duelists_mark", operation = "add", value = 1, description = "+30% vs elites" } },
	},
	relic_hunters_sigil = {
		id = "relic_hunters_sigil", name = "Hunter's Sigil", category = "Relic", maxLevel = 1, classId = "ranger",
		description = "+25% damage to enemies more than 20 studs away.",
		effects = { { stat = "relic_hunters_sigil", operation = "add", value = 1, description = "+25% at range" } },
	},

	boon_secondwind = {
		id = "boon_secondwind", name = "Second Wind", category = "Boon", maxLevel = 3,
		description = "Fight harder near death: low on health, you hit harder and take less.",
		levels = {
			"Under 35% HP: +20% damage, 10% less damage taken.",
			"Under 35% HP: +30% damage, 15% less damage taken.",
			"Under 35% HP: +40% damage, 20% less damage taken.",
		},
		effects = { { stat = "boon_secondwind", operation = "add", value = 1, description = "Second Wind" } },
	},

}

-- Tomes that can be offered, granted or rolled (level-ups, the Wheel of Fate,
-- the Chaos Tome all draw from this list). Disabled: armor, attraction and
-- thorns (their stats aren't used in-game yet) and silver (no silver currency).
local TomeOrder = {
	"agility", "attack_speed", "cooldown", "damage", "evasion", "gold", "health",
	"knockback", "precision", "projectile_speed", "regen", "ricochet", "shield", "size",
	"bloody", "chaos", "cursed", "duration", "luck", "quantity",
	"boon_ignite", "boon_frost", "boon_chain", "boon_bloodlust", "boon_corpse", "boon_execute", "boon_thunder", "boon_secondwind",
}

-- Run relics, in the order they're offered from (TomeModule.RelicOrder).
local RelicOrder = {
	"relic_dragons_heart", "relic_bloodied_crown", "relic_frozen_soul", "relic_berserkers_tooth", "relic_shattered_mirror",
	"relic_gamblers_coin", "relic_hollow_lantern", "relic_iron_vow", "relic_vampire_fang", "relic_storm_eye",
	"relic_frozen_heart", "relic_blood_oath", "relic_saints_bell", "relic_loaded_dice", "relic_ember_heart", "relic_duelists_mark", "relic_hunters_sigil",
}

-- ── Evolutions ──────────────────────────────────────────────────────────────
local Evolutions: { Evolution } = {
	-- Class-free: a maxed boon + a tome.
	{ id = "evo_inferno", name = "Inferno", boon = "boon_ignite", with = "damage", color = Color3.fromRGB(255, 110, 30),
		description = "Burns deal double, and a burning enemy that dies sets everything around it alight." },
	{ id = "evo_glacial_shatter", name = "Glacial Shatter", boon = "boon_frost", with = "size", color = Color3.fromRGB(150, 225, 255),
		description = "Chilled enemies you kill shatter: an icy blast that hurts and chills everything nearby." },
	{ id = "evo_stormcaller", name = "Stormcaller", boon = "boon_chain", with = "precision", color = Color3.fromRGB(150, 190, 255),
		description = "Lightning arcs to 6 enemies at 60% damage, and every arc can crit." },
	{ id = "evo_blood_frenzy", name = "Blood Frenzy", boon = "boon_bloodlust", with = "attack_speed", color = Color3.fromRGB(220, 30, 50),
		description = "Bloodlust stacks to 12, and every kill heals you 1.5% of your max HP." },
	{ id = "evo_chain_reaction", name = "Chain Reaction", boon = "boon_corpse", with = "quantity", color = Color3.fromRGB(255, 160, 60),
		description = "Every kill explodes, and enemies killed by explosions explode too." },
	{ id = "evo_reaper", name = "Reaper", boon = "boon_execute", with = "bloody", color = Color3.fromRGB(150, 40, 70),
		description = "Your hits execute normal enemies under 15% HP outright." },
	{ id = "evo_judgement", name = "Judgement", boon = "boon_thunder", with = "cooldown", color = Color3.fromRGB(255, 235, 140),
		description = "Lightning falls every 4th hit, wider, and stuns what it strikes." },
	{ id = "evo_undying", name = "Undying", boon = "boon_secondwind", with = "health", color = Color3.fromRGB(255, 200, 120),
		description = "Once per floor, a killing blow leaves you at 1 HP, untouchable for 2s." },

	-- A maxed boon on the right class changes its signature skill.
	{ id = "evo_glacial_ray", name = "Glacial Ray", boon = "boon_frost", classId = "ice_mage", skill = "Ice Beam", color = Color3.fromRGB(170, 235, 255),
		description = "Ice Beam always chills, and enemies it kills burst into freezing shards." },
	{ id = "evo_infernal_blade", name = "Infernal Blade", boon = "boon_ignite", classId = "heavy_knight", skill = "Emberblade", color = Color3.fromRGB(255, 90, 20),
		description = "Every Emberblade hit ignites, and burning enemies take +25% from it." },
	{ id = "evo_thunder_rounds", name = "Thunder Rounds", boon = "boon_chain", classId = "gunslinger", skill = "Six Shooter", color = Color3.fromRGB(255, 220, 120),
		description = "Every Six Shooter hit arcs lightning to 2 enemies, crit or not." },
	{ id = "evo_bloodbath", name = "Bloodbath", boon = "boon_bloodlust", classId = "berserker", skill = "Berserk combo", color = Color3.fromRGB(200, 20, 40),
		description = "Combo kills give 2 Bloodlust stacks and heal you 2% of your max HP." },
	{ id = "evo_plague_volley", name = "Plague Volley", boon = "boon_corpse", classId = "ranger", skill = "Venom Arrows", color = Color3.fromRGB(140, 230, 90),
		description = "Enemies killed by Venom Arrows always burst in a poison blast." },
	{ id = "evo_judgement_ray", name = "Judgement Ray", boon = "boon_thunder", classId = "cleric", skill = "Radiant strikes", color = Color3.fromRGB(255, 240, 170),
		description = "Radiant hits count three times toward Thunderstrike, and each strike heals allies near it 3%." },
	{ id = "evo_deathblow", name = "Deathblow", boon = "boon_execute", classId = "swordsman", skill = "Sword finisher", color = Color3.fromRGB(230, 230, 255),
		description = "Your sword finisher executes enemies under 25% HP (elites under 10%)." },
}
local evoById: { [string]: Evolution } = {}
for _, e in ipairs(Evolutions) do evoById[e.id] = e end

local TomeModule = {}

function TomeModule.GetTome(id: string): TomeDefinition?
	return TomeData[id]
end

-- Whether a tome can be offered to someone playing `classId` (class-only
-- upgrades only go to their class).
function TomeModule.IsForClass(id: string, classId: any): boolean
	local tome = TomeData[id]
	return tome ~= nil and (tome.classId == nil or tome.classId == classId)
end

function TomeModule.GetAll(includeUnlockable: boolean?): { TomeDefinition }
	local tomes: { TomeDefinition } = {}
	for _, id in ipairs(TomeOrder) do
		local tome = TomeData[id]
		if tome and (includeUnlockable or tome.category == "Base") then
			table.insert(tomes, tome)
		end
	end
	return tomes
end

-- Distinct accent colour per buff (keyed by tome id).
local BUFF_COLORS: { [string]: Color3 } = {
	agility = Color3.fromRGB(120, 230, 140),
	attack_speed = Color3.fromRGB(255, 160, 90),
	cooldown = Color3.fromRGB(120, 190, 255),
	damage = Color3.fromRGB(255, 100, 100),
	evasion = Color3.fromRGB(185, 160, 255),
	gold = Color3.fromRGB(255, 205, 80),
	health = Color3.fromRGB(255, 120, 150),
	knockback = Color3.fromRGB(205, 170, 120),
	precision = Color3.fromRGB(255, 230, 120),
	projectile_speed = Color3.fromRGB(130, 230, 230),
	ricochet = Color3.fromRGB(255, 190, 90),
	regen = Color3.fromRGB(120, 245, 180),
	shield = Color3.fromRGB(150, 200, 255),
	silver = Color3.fromRGB(210, 215, 230),
	size = Color3.fromRGB(230, 170, 255),
	armor = Color3.fromRGB(170, 190, 210),
	attraction = Color3.fromRGB(255, 140, 220),
	bloody = Color3.fromRGB(205, 45, 55),
	chaos = Color3.fromRGB(200, 120, 255),
	cursed = Color3.fromRGB(150, 85, 190),
	duration = Color3.fromRGB(255, 180, 80),
	luck = Color3.fromRGB(130, 230, 120),
	quantity = Color3.fromRGB(255, 210, 140),
	thorns = Color3.fromRGB(120, 180, 90),
	boon_ignite = Color3.fromRGB(255, 120, 40),
	boon_frost = Color3.fromRGB(150, 220, 255),
	boon_chain = Color3.fromRGB(140, 180, 255),
	boon_bloodlust = Color3.fromRGB(220, 40, 60),
	boon_corpse = Color3.fromRGB(255, 170, 70),
	boon_execute = Color3.fromRGB(170, 50, 80),
	boon_thunder = Color3.fromRGB(255, 230, 120),
	boon_secondwind = Color3.fromRGB(255, 200, 140),
}
-- (every run relic: an old-gold accent)
for _, id in ipairs(RelicOrder) do BUFF_COLORS[id] = Color3.fromRGB(230, 170, 90) end

function TomeModule.AccentFor(id: string?): Color3
	if id and BUFF_COLORS[id] then return BUFF_COLORS[id] end
	-- Gunslinger upgrades share a gunmetal-brass accent.
	if id and string.sub(id, 1, 3) == "gs_" then return Color3.fromRGB(255, 176, 70) end
	return Color3.fromRGB(255, 213, 128)
end


-- The blended colour of several tomes (e.g. a room reward offering them).
function TomeModule.BlendColor(ids: { string }): Color3
	if #ids == 0 then return Color3.fromRGB(255, 213, 128) end
	local r, g, b = 0, 0, 0
	for _, id in ipairs(ids) do
		local c = TomeModule.AccentFor(id)
		r += c.R
		g += c.G
		b += c.B
	end
	local c = Color3.new(r / #ids, g / #ids, b / #ids)
	-- Averaging dulls colours; push saturation back up.
	local h, sat, v = c:ToHSV()
	return Color3.fromHSV(h, math.min(1, sat * 1.4 + 0.1), math.max(v, 0.85))
end

TomeModule.Tomes = TomeData
TomeModule.Order = TomeOrder
TomeModule.Evolutions = Evolutions
TomeModule.RelicOrder = RelicOrder

function TomeModule.IsRelic(id: string): boolean
	local t = TomeData[id]
	return t ~= nil and t.category == "Relic"
end

function TomeModule.GetEvolution(id: string): Evolution?
	return evoById[id]
end

function TomeModule.IsBoon(id: string): boolean
	local t = TomeData[id]
	return t ~= nil and t.category == "Boon"
end

-- The most levels a tome can take (boons: their max; tomes: no limit).
function TomeModule.MaxLevel(id: string): number
	local t = TomeData[id]
	return if t and t.maxLevel then t.maxLevel else math.huge
end

-- What a boon's evolutions need, as a hint for its card ("Evolves with ...").
function TomeModule.EvolveHint(id: string, classId: any): string?
	local bits = {}
	for _, e in ipairs(Evolutions) do
		if e.boon == id then
			if e.with then
				local w = TomeData[e.with]
				if w then table.insert(bits, `{e.name} (+ {w.name})`) end
			elseif e.classId == classId then
				table.insert(bits, `{e.name} ({e.skill})`)
			end
		end
	end
	return if #bits > 0 then "Max level evolves: " .. table.concat(bits, ", ") else nil
end

return TomeModule
