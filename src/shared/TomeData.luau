--!strict
--[[
	TomeData
	Authoritative definitions for collectible run tomes. Stat systems should consume
	the `effects` values rather than parsing the display text.
--]]

export type TomeCategory = "Base" | "Unlockable"
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
}

local TomeData: { [string]: TomeDefinition } = {
	agility = {
		id = "agility", name = "Agility Tome", category = "Base", description = "+15% Movement Speed",
		effects = { { stat = "movementSpeed", operation = "percent", value = 0.15, description = "+15% Movement Speed" } },
	},
	attack_speed = {
		id = "attack_speed", name = "Attack Speed Tome", category = "Base", description = "+30% Basic Attack Speed",
		effects = { { stat = "basicAttackSpeed", operation = "percent", value = 0.30, description = "+30% Basic Attack Speed" } },
	},
	cooldown = {
		id = "cooldown", name = "Cooldown Tome", category = "Base", description = "Decreases Ability Cooldowns",
		effects = { { stat = "abilityCooldown", operation = "percent", value = 0.10, description = "-10% Ability Cooldowns" } },
	},
	damage = {
		id = "damage", name = "Damage Tome", category = "Base", description = "+0.08× Damage",
		effects = { { stat = "damage", operation = "multiplier", value = 0.08, description = "+0.08× Damage" } },
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
		id = "shield", name = "Shield Tome", category = "Base", description = "+25 Shield",
		effects = { { stat = "shield", operation = "add", value = 25, description = "+25 Shield" } },
	},
	silver = {
		id = "silver", name = "Silver Tome", category = "Base", description = "+12% Silver Gain",
		effects = { { stat = "silverGain", operation = "percent", value = 0.12, description = "+12% Silver Gain" } },
	},
	size = {
		id = "size", name = "Size Tome", category = "Base", description = "+10% Size",
		effects = { { stat = "size", operation = "percent", value = 0.10, description = "+10% Size" } },
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
		id = "cursed", name = "Cursed Tome", category = "Unlockable", description = "+3.5% Difficulty",
		effects = { { stat = "difficulty", operation = "percent", value = 0.035, description = "+3.5% Difficulty" } },
	},
	duration = {
		id = "duration", name = "Duration Tome", category = "Unlockable", description = "+15% Duration",
		effects = { { stat = "abilityDuration", operation = "percent", value = 0.15, description = "+15% Duration" } },
	},
	luck = {
		id = "luck", name = "Luck Tome", category = "Unlockable", description = "+7% Luck",
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
	xp = {
		id = "xp", name = "XP Tome", category = "Unlockable", description = "+7% XP Gain",
		effects = { { stat = "xpGain", operation = "percent", value = 0.07, description = "+7% XP Gain" } },
	},
}

local TomeOrder = {
	"agility", "attack_speed", "cooldown", "damage", "evasion", "gold", "health",
	"knockback", "precision", "projectile_speed", "regen", "shield", "silver", "size",
	"armor", "attraction", "bloody", "chaos", "cursed", "duration", "luck", "quantity",
	"thorns", "xp",
}

local TomeModule = {}

function TomeModule.GetTome(id: string): TomeDefinition?
	return TomeData[id]
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

TomeModule.Tomes = TomeData
TomeModule.Order = TomeOrder

return TomeModule
