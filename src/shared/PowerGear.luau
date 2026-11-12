--!strict
--[[
	PowerGear.luau
	The gear that makes you stronger, run after run: what you EXTRACT with
	(LootManager) and wear for good. Four slots, each piece rolled when it
	drops:

	  weapon  Damage        armor  Max Health
	  ring    Crit Chance   charm  Skill Damage
	  (the slot's main stat, doubled), plus 0–4 more stats by rarity, all
	  scaled by the item level: deeper floors and more Corruption roll
	  higher item levels, so the best gear only drops deep.

	POWER is one number for all of it: 100, plus 5 a hero (account) level,
	plus every worn piece's power. It's what the HUD shows and what each drop
	is measured against (▲ +38 POWER).

	The hero level also gives a little on its own: +0.5% damage and max
	health a level past the first (+49.5% at 100).

	Stats are tome effects (TomeData's shape: stat, operation, value), so
	PlayerStats folds them in with the class talents at the start of a run.

	PowerGear.Roll(rarity, ilvl, slot?)  → Item
	PowerGear.Effects(item)              → { effect }
	PowerGear.ItemPower(item)            → number
	PowerGear.HeroEffects(level)         → { effect }
	PowerGear.Total(worn, level)         → number
	PowerGear.Describe(affix, item?)     → "+12% Damage"

	The forge (the Armory's POWER GEAR tab): a piece can be upgraded from +1
	to +10 with scrap, each step +8% to all its stats (+80% at +10); a spare
	piece can be salvaged for scrap (its rarity's worth, and half the scrap
	spent upgrading it back). The worn weapon's level shows on the weapon
	itself (WeaponForgeFX): sparks from +3, embers from +6, flames at +9.

	PowerGear.Title(item)                → "Keen Talon +4"
	PowerGear.UpgradeCost(item)          → scrap (nil at +10)
	PowerGear.SalvageValue(item)         → scrap

	Forging a new piece (the forge's minigame, ForgeMinigame): CRAFT_COST
	scrap for a piece of the slot you pick, at the item level of your best
	floor. The minigame's score (0..1: the heat held, the hammer's timing)
	picks the rarity table it's rolled on; only a near-perfect forging can
	make a Mythic.

	PowerGear.CraftRarity(score)         → rarity
--]]

local PowerGear = {}

export type Affix = { stat: string, value: number, main: boolean? }
export type Item = {
	uid: string?,
	plus: number?,  -- forge level, 0..PLUS_MAX
	spent: number?, -- scrap spent upgrading it (half comes back on salvage)
	slot: string,
	rarity: string,
	ilvl: number,
	name: string,
	glyph: string,
	affixes: { Affix },
}

PowerGear.SLOTS = { "weapon", "armor", "ring", "charm" }
PowerGear.SLOT_NAME = { weapon = "Weapon", armor = "Armor", ring = "Ring", charm = "Charm" }
PowerGear.MAIN = { weapon = "damage", armor = "maxHealth", ring = "critChance", charm = "abilityDamage" }
PowerGear.MAX_ILVL = 40
PowerGear.BASE_POWER = 100
PowerGear.POWER_PER_LEVEL = 5
PowerGear.INVENTORY = 60 -- pieces kept (the weakest spare is salvaged past this)
PowerGear.PLUS_MAX = 10
PowerGear.PLUS_STEP = 0.08 -- each forge level: +8% to every stat on the piece

-- Each stat: its value at item level 1 on a Common (`base`), how it applies
-- (a tome effect's operation) and how it reads.
PowerGear.STATS = {
	damage           = { base = 0.04,  op = "percent", label = "Damage",        pct = true, prefix = "Savage" },
	maxHealth        = { base = 0.05,  op = "percent", label = "Max Health",    pct = true, prefix = "Stalwart" },
	critChance       = { base = 0.02,  op = "percent", label = "Crit Chance",   pct = true, prefix = "Keen" },
	critDamage       = { base = 0.08,  op = "add",     label = "Crit Damage",   pct = true, prefix = "Brutal" },
	basicAttackSpeed = { base = 0.03,  op = "percent", label = "Attack Speed",  pct = true, prefix = "Swift" },
	abilityCooldown  = { base = 0.025, op = "percent", label = "Cooldown Cut",  pct = true, prefix = "Arcane" },
	abilityDamage    = { base = 0.04,  op = "percent", label = "Skill Damage",  pct = true, prefix = "Runed" },
	movementSpeed    = { base = 0.02,  op = "percent", label = "Move Speed",    pct = true, prefix = "Fleet" },
	lifesteal        = { base = 0.008, op = "percent", label = "Lifesteal",     pct = true, prefix = "Vampiric" },
}
local STAT_IDS = { "damage", "maxHealth", "critChance", "critDamage", "basicAttackSpeed", "abilityCooldown", "abilityDamage", "movementSpeed", "lifesteal" }

PowerGear.RARITY_MULT = { Common = 1, Uncommon = 1.2, Rare = 1.45, Epic = 1.75, Legendary = 2.1, Mythic = 2.6 }
PowerGear.EXTRA_AFFIXES = { Common = 0, Uncommon = 1, Rare = 2, Epic = 3, Legendary = 3, Mythic = 4 }
-- (spare pieces salvaged become scrap: the forge's material)
PowerGear.SCRAP = { Common = 2, Uncommon = 5, Rare = 12, Epic = 30, Legendary = 75, Mythic = 200 }

PowerGear.CRAFT_COST = 60
-- score at least `min` → the odds of each rarity (they add to 1)
local CRAFT_TABLE = {
	{ min = 0.95, odds = { Legendary = 0.7, Mythic = 0.3 } },
	{ min = 0.8, odds = { Epic = 0.5, Legendary = 0.45, Mythic = 0.05 } },
	{ min = 0.6, odds = { Rare = 0.5, Epic = 0.4, Legendary = 0.1 } },
	{ min = 0.35, odds = { Uncommon = 0.5, Rare = 0.45, Epic = 0.05 } },
	{ min = 0, odds = { Common = 0.6, Uncommon = 0.4 } },
}
PowerGear.CRAFT_TABLE = CRAFT_TABLE
local ORDER = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }

function PowerGear.CraftRarity(score: number): string
	score = math.clamp(score, 0, 1)
	for _, row in ipairs(CRAFT_TABLE) do
		if score >= row.min then
			local r = math.random()
			local acc = 0
			for _, rarity in ipairs(ORDER) do
				acc += row.odds[rarity] or 0
				if r < acc then return rarity end
			end
			return "Common"
		end
	end
	return "Common"
end

local BASES = {
	weapon = { "Fang", "Edge", "Talon", "Reaver", "Cleaver" },
	armor = { "Plate", "Mantle", "Hauberk", "Aegis", "Cuirass" },
	ring = { "Band", "Loop", "Signet", "Coil" },
	charm = { "Idol", "Sigil", "Totem", "Relic" },
}

local function scale(ilvl: number): number
	return 1 + 0.08 * (math.clamp(ilvl, 1, PowerGear.MAX_ILVL) - 1)
end

local function round3(x: number): number
	return math.floor(x * 1000 + 0.5) / 1000
end

function PowerGear.Roll(rarity: string, ilvl: number, slot: string?): Item
	local rng = Random.new()
	local s = slot or PowerGear.SLOTS[rng:NextInteger(1, #PowerGear.SLOTS)]
	ilvl = math.clamp(math.floor(ilvl), 1, PowerGear.MAX_ILVL)
	local mult = (PowerGear.RARITY_MULT[rarity] or 1) * scale(ilvl)
	local main = PowerGear.MAIN[s]
	local affixes: { Affix } = {
		{ stat = main, value = round3(PowerGear.STATS[main].base * 2 * mult * rng:NextNumber(0.9, 1.1)), main = true },
	}
	local pool = {}
	for _, id in ipairs(STAT_IDS) do
		if id ~= main then table.insert(pool, id) end
	end
	for _ = 1, PowerGear.EXTRA_AFFIXES[rarity] or 0 do
		local id = table.remove(pool, rng:NextInteger(1, #pool))
		table.insert(affixes, { stat = id, value = round3(PowerGear.STATS[id].base * mult * rng:NextNumber(0.85, 1.15)) })
	end
	local bases = BASES[s]
	local base = bases[rng:NextInteger(1, #bases)]
	local name = if affixes[2] then `{PowerGear.STATS[affixes[2].stat].prefix} {base}` else base
	return {
		slot = s, rarity = rarity, ilvl = ilvl, name = name,
		glyph = string.upper(string.sub(base, 1, 2)), affixes = affixes,
	}
end

-- The forge's boost on a piece's stats.
function PowerGear.Boost(item: Item?): number
	return 1 + PowerGear.PLUS_STEP * math.clamp((item and item.plus) or 0, 0, PowerGear.PLUS_MAX)
end

function PowerGear.Effects(item: Item): { any }
	local out = {}
	local boost = PowerGear.Boost(item)
	for _, a in ipairs(item.affixes) do
		local def = PowerGear.STATS[a.stat]
		if def then table.insert(out, { stat = a.stat, operation = def.op, value = a.value * boost }) end
	end
	return out
end

-- How strong a piece is: each stat counted against its Common, level-1 value.
function PowerGear.ItemPower(item: Item?): number
	if not item then return 0 end
	local w = 0
	for _, a in ipairs(item.affixes) do
		local def = PowerGear.STATS[a.stat]
		if def then w += a.value / def.base end
	end
	return math.floor(10 * w * PowerGear.Boost(item) + 0.5)
end

function PowerGear.Title(item: Item): string
	local plus = item.plus or 0
	return if plus > 0 then `{item.name} +{plus}` else item.name
end

-- Scrap for the next forge level (nil when it's maxed).
function PowerGear.UpgradeCost(item: Item): number?
	local plus = item.plus or 0
	if plus >= PowerGear.PLUS_MAX then return nil end
	local base = PowerGear.SCRAP[item.rarity] or 2
	return math.floor(base * (plus + 1) ^ 1.4 + 6 * (plus + 1))
end

function PowerGear.SalvageValue(item: Item): number
	return (PowerGear.SCRAP[item.rarity] or 1) + math.floor((item.spent or 0) / 2)
end

function PowerGear.HeroEffects(level: number): { any }
	local bonus = 0.005 * math.max(0, level - 1)
	if bonus <= 0 then return {} end
	return {
		{ stat = "damage", operation = "percent", value = bonus },
		{ stat = "maxHealth", operation = "percent", value = bonus },
	}
end

function PowerGear.Total(worn: { Item }, level: number): number
	local total = PowerGear.BASE_POWER + PowerGear.POWER_PER_LEVEL * math.max(0, level - 1)
	for _, item in ipairs(worn) do total += PowerGear.ItemPower(item) end
	return total
end

function PowerGear.Describe(a: Affix, item: Item?): string
	local def = PowerGear.STATS[a.stat]
	if not def then return a.stat end
	local v = a.value * PowerGear.Boost(item) * 100
	local text = if v >= 10 then tostring(math.floor(v + 0.5)) else string.format("%.1f", v)
	return `+{text}% {def.label}`
end

return PowerGear
