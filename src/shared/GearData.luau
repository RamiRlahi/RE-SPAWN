--!strict
--[[
	GearData.luau
	The Armory: gear you find in runs and wear to show off. Cosmetic (no
	stats), by rarity, worn by every class:

	  weapon  a finish for whatever weapon your class carries: its metal, its
	          colour, the glow of its edges and runes, its swing trail
	  aura    something rising off you (embers, frost, holy motes, a void rift)
	  title   a title under your name in the lobby and on your player card

	Drops come from runs (LootManager): elites, bosses, every floor cleared,
	more and rarer the deeper you go and the more corrupted the dungeon.
	A duplicate becomes souls instead.
--]]

local GearData = {}

export type Slot = "weapon" | "aura" | "title"
export type Item = {
	id: string,
	slot: Slot,
	name: string,
	rarity: string,
	glyph: string,
	description: string,
	-- weapon finishes
	color: Color3?,          -- the main metal / wood
	trim: Color3?,           -- the small pieces (guards, grips, rings)
	material: Enum.Material?,
	glow: Color3?,           -- its glowing parts (and the swing trail)
	sparkle: boolean?,       -- motes drifting off the weapon
	-- auras
	aura: string?,           -- the aura's look (GearLook)
	auraColor: Color3?,
	-- titles
	title: string?,
	titleColor: Color3?,
	dropOnly: boolean?,      -- (false: also from achievements, never random)
}

GearData.RARITIES = { "Common", "Uncommon", "Rare", "Epic", "Legendary", "Mythic" }
GearData.RARITY_COLOR = {
	Common = Color3.fromRGB(175, 175, 175),
	Uncommon = Color3.fromRGB(90, 205, 110),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(185, 100, 255),
	Legendary = Color3.fromRGB(255, 170, 40),
	Mythic = Color3.fromRGB(255, 70, 95),
} :: { [string]: Color3 }
-- Souls a duplicate is worth.
GearData.DUPLICATE_SOULS = { Common = 1, Uncommon = 2, Rare = 4, Epic = 8, Legendary = 16, Mythic = 32 } :: { [string]: number }

local ITEMS: { Item } = {
	-- ── Weapon finishes ──────────────────────────────────────────────────────
	{ id = "w_ashen", slot = "weapon", name = "Ashen", rarity = "Common", glyph = "⚔",
		description = "Soot-dark iron, worn smooth.", color = Color3.fromRGB(70, 68, 66), trim = Color3.fromRGB(40, 38, 36), material = Enum.Material.Metal },
	{ id = "w_bronze", slot = "weapon", name = "Old Bronze", rarity = "Common", glyph = "⚔",
		description = "Battle-worn bronze from a fallen legion.", color = Color3.fromRGB(150, 105, 60), trim = Color3.fromRGB(90, 60, 35), material = Enum.Material.Metal },
	{ id = "w_verdigris", slot = "weapon", name = "Verdigris", rarity = "Uncommon", glyph = "⚔",
		description = "Green-rusted copper from the sunken crypt.", color = Color3.fromRGB(80, 150, 125), trim = Color3.fromRGB(60, 80, 70), material = Enum.Material.CorrodedMetal },
	{ id = "w_obsidian", slot = "weapon", name = "Obsidian", rarity = "Uncommon", glyph = "⚔",
		description = "Black volcanic glass, edged sharp.", color = Color3.fromRGB(28, 26, 32), trim = Color3.fromRGB(70, 60, 80), material = Enum.Material.Glass },
	{ id = "w_frostforged", slot = "weapon", name = "Frostforged", rarity = "Rare", glyph = "❄",
		description = "Cold steel that never warms. Its edges glow pale blue.", color = Color3.fromRGB(170, 210, 235), trim = Color3.fromRGB(90, 120, 160),
		material = Enum.Material.Ice, glow = Color3.fromRGB(150, 220, 255) },
	{ id = "w_emberforged", slot = "weapon", name = "Emberforged", rarity = "Rare", glyph = "🔥",
		description = "Still hot from the Infernal Keep's forges.", color = Color3.fromRGB(80, 40, 30), trim = Color3.fromRGB(40, 22, 18),
		material = Enum.Material.Basalt, glow = Color3.fromRGB(255, 120, 40) },
	{ id = "w_bloodsteel", slot = "weapon", name = "Bloodsteel", rarity = "Epic", glyph = "🩸",
		description = "Crimson steel that drinks the light.", color = Color3.fromRGB(130, 18, 26), trim = Color3.fromRGB(40, 10, 14),
		material = Enum.Material.Metal, glow = Color3.fromRGB(255, 40, 60), sparkle = true },
	{ id = "w_runebound", slot = "weapon", name = "Runebound", rarity = "Epic", glyph = "⚡",
		description = "Etched with runes that hum when they're near the dead.", color = Color3.fromRGB(60, 64, 90), trim = Color3.fromRGB(30, 30, 48),
		material = Enum.Material.Slate, glow = Color3.fromRGB(120, 160, 255), sparkle = true },
	{ id = "w_sunforged", slot = "weapon", name = "Sunforged", rarity = "Legendary", glyph = "☀",
		description = "Gold forged at the top of the light. It burns with dawn.", color = Color3.fromRGB(240, 200, 100), trim = Color3.fromRGB(255, 240, 200),
		material = Enum.Material.Foil, glow = Color3.fromRGB(255, 220, 120), sparkle = true },
	{ id = "w_abyssal", slot = "weapon", name = "Abyssal", rarity = "Legendary", glyph = "🌊",
		description = "Brought up from beneath the lowest floor. Deep teal, cold light.", color = Color3.fromRGB(20, 60, 70), trim = Color3.fromRGB(10, 25, 30),
		material = Enum.Material.Metal, glow = Color3.fromRGB(60, 255, 220), sparkle = true },
	{ id = "w_voidtouched", slot = "weapon", name = "Voidtouched", rarity = "Mythic", glyph = "◆",
		description = "The dark between the stars, held in a hilt. It hungers.", color = Color3.fromRGB(14, 8, 22), trim = Color3.fromRGB(60, 20, 90),
		material = Enum.Material.Glass, glow = Color3.fromRGB(190, 80, 255), sparkle = true },

	-- ── Auras ────────────────────────────────────────────────────────────────
	{ id = "a_dust", slot = "aura", name = "Grave Dust", rarity = "Uncommon", glyph = "·",
		description = "A little of the crypt follows you around.", aura = "dust", auraColor = Color3.fromRGB(190, 180, 160) },
	{ id = "a_embers", slot = "aura", name = "Embers", rarity = "Rare", glyph = "🔥",
		description = "Sparks drifting up off you.", aura = "embers", auraColor = Color3.fromRGB(255, 140, 50) },
	{ id = "a_frost", slot = "aura", name = "Frost Mist", rarity = "Rare", glyph = "❄",
		description = "Cold mist curling at your feet.", aura = "frost", auraColor = Color3.fromRGB(170, 225, 255) },
	{ id = "a_holy", slot = "aura", name = "Holy Motes", rarity = "Epic", glyph = "☆",
		description = "Motes of light circling you.", aura = "holy", auraColor = Color3.fromRGB(255, 235, 160) },
	{ id = "a_blood", slot = "aura", name = "Blood Moon", rarity = "Legendary", glyph = "🌕",
		description = "A red haze, and a halo the colour of the blood moon.", aura = "blood", auraColor = Color3.fromRGB(230, 30, 50) },
	{ id = "a_starfall", slot = "aura", name = "Starfall", rarity = "Legendary", glyph = "🌠",
		description = "Little stars falling around you.", aura = "stars", auraColor = Color3.fromRGB(200, 220, 255) },
	{ id = "a_void", slot = "aura", name = "Void Rift", rarity = "Mythic", glyph = "🌀",
		description = "The air around you tears open.", aura = "void", auraColor = Color3.fromRGB(170, 70, 255) },

	-- ── Titles ───────────────────────────────────────────────────────────────
	{ id = "t_delver", slot = "title", name = "Delver", rarity = "Common", glyph = "✒", description = "A title.", title = "Delver" },
	{ id = "t_gravedigger", slot = "title", name = "Gravedigger", rarity = "Common", glyph = "✒", description = "A title.", title = "Gravedigger" },
	{ id = "t_bonebreaker", slot = "title", name = "Bonebreaker", rarity = "Uncommon", glyph = "✒", description = "A title.", title = "Bonebreaker" },
	{ id = "t_torchbearer", slot = "title", name = "Torchbearer", rarity = "Uncommon", glyph = "✒", description = "A title.", title = "Torchbearer" },
	{ id = "t_abyss_walker", slot = "title", name = "Abyss Walker", rarity = "Rare", glyph = "✒", description = "A title.", title = "Abyss Walker" },
	{ id = "t_eliteslayer", slot = "title", name = "Elite Slayer", rarity = "Rare", glyph = "✒", description = "A title.", title = "Elite Slayer" },
	{ id = "t_wyrmbane", slot = "title", name = "Wyrmbane", rarity = "Epic", glyph = "✒", description = "A title.", title = "Wyrmbane" },
	{ id = "t_deathless", slot = "title", name = "The Deathless", rarity = "Epic", glyph = "✒", description = "A title.", title = "The Deathless" },
	{ id = "t_crowned", slot = "title", name = "Crowned in Ash", rarity = "Legendary", glyph = "✒", description = "A title.", title = "Crowned in Ash" },
	{ id = "t_harbinger", slot = "title", name = "Harbinger", rarity = "Legendary", glyph = "✒", description = "A title.", title = "Harbinger" },
	{ id = "t_voidborn", slot = "title", name = "Voidborn", rarity = "Mythic", glyph = "✒", description = "A title.", title = "Voidborn" },
}

local byId: { [string]: Item } = {}
local byRarity: { [string]: { Item } } = {}
for _, it in ipairs(ITEMS) do
	byId[it.id] = it
	byRarity[it.rarity] = byRarity[it.rarity] or {}
	table.insert(byRarity[it.rarity], it)
	if it.slot == "title" then it.titleColor = GearData.RARITY_COLOR[it.rarity] end
end

GearData.Items = ITEMS

function GearData.Get(id: any): Item?
	return if typeof(id) == "string" then byId[id] else nil
end

function GearData.OfRarity(rarity: string): { Item }
	return byRarity[rarity] or {}
end

function GearData.RarityIndex(rarity: string): number
	return table.find(GearData.RARITIES, rarity) or 1
end

return GearData
