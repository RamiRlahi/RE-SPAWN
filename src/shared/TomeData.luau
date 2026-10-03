--!strict
--[[
	TomeData
	Authoritative definitions for collectible run tomes. Stat systems should consume
	the `effects` values rather than parsing the display text.
--]]

export type TomeCategory = "Base" | "Unlockable" | "Gunslinger"
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
}

local TomeData: { [string]: TomeDefinition } = {
	agility = {
		id = "agility", name = "Agility Tome", category = "Base", description = "+15% Movement Speed",
		effects = { { stat = "movementSpeed", operation = "percent", value = 0.15, description = "+15% Movement Speed" } },
	},
	attack_speed = {
		id = "attack_speed", name = "Attack Speed Tome", category = "Base", description = "+15% Basic Attack Speed (max 2×)",
		effects = { { stat = "basicAttackSpeed", operation = "percent", value = 0.15, description = "+15% Basic Attack Speed" } },
	},
	cooldown = {
		id = "cooldown", name = "Cooldown Tome", category = "Base", description = "-8% Ability Cooldowns (max -50%)",
		effects = { { stat = "abilityCooldown", operation = "percent", value = 0.08, description = "-8% Ability Cooldowns" } },
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

}

-- Tomes that can be offered, granted or rolled (level-ups, the Wheel of Fate,
-- the Chaos Tome all draw from this list). Disabled: armor, attraction and
-- thorns (their stats aren't used in-game yet) and silver (no silver currency).
local TomeOrder = {
	"agility", "attack_speed", "cooldown", "damage", "evasion", "gold", "health",
	"knockback", "precision", "projectile_speed", "regen", "ricochet", "shield", "size",
	"bloody", "chaos", "cursed", "duration", "luck", "quantity",
}

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
}

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

return TomeModule
