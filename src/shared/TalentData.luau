--!strict
--[[
	TalentData
	Per-class constellations for the class-selection talent trees.

	  lines  — the constellation's line-art, as segments in a 1×1 box
	           (x right, y down) — drawn as glowing lines in the UI
	  nodes  — talents placed on the art; each needs its `requires` node
	           unlocked first and costs `cost` souls. `effect` uses the same
	           stat/operation vocabulary as TomeData and is applied by
	           PlayerStats at the start of every run with that class.

	Only stats the game actually reads are used: damage, basicAttackSpeed,
	abilityCooldown, abilityDuration, size, critChance, lifesteal, knockback,
	projectileSpeed, projectileCount, maxHealth, movementSpeed, goldGain, xpGain.
--]]

export type TalentEffect = {
	stat: string,
	operation: "add" | "percent" | "multiplier",
	value: number,
}

export type TalentNode = {
	id: string,
	name: string,
	description: string,
	glyph: string,
	x: number,
	y: number,
	cost: number,
	requires: string?,
	effect: TalentEffect,
}

export type Constellation = {
	name: string,
	lines: { { number } }, -- { x1, y1, x2, y2 }
	nodes: { TalentNode },
}

-- Helpers to mirror line-art about the vertical centre line.
local function mirrored(segs: { { number } }): { { number } }
	local out = {}
	for _, s in ipairs(segs) do
		table.insert(out, s)
		table.insert(out, { 1 - s[1], s[2], 1 - s[3], s[4] })
	end
	return out
end

local function concat(...: { { number } }): { { number } }
	local out = {}
	for _, list in ipairs({ ... }) do
		for _, s in ipairs(list) do table.insert(out, s) end
	end
	return out
end

local TalentData: { [string]: Constellation } = {
	-- ── Heavy Knight: The Greatsword, wreathed in flame ─────────────────────
	heavy_knight = {
		name = "The Greatsword",
		lines = concat(
			{
				{ 0.5, 0.04, 0.46, 0.12 }, { 0.5, 0.04, 0.54, 0.12 },      -- tip
				{ 0.46, 0.12, 0.46, 0.64 }, { 0.54, 0.12, 0.54, 0.64 },    -- blade
				{ 0.5, 0.14, 0.5, 0.6 },                                   -- fuller
				{ 0.28, 0.66, 0.72, 0.66 }, { 0.28, 0.66, 0.3, 0.7 }, { 0.72, 0.66, 0.7, 0.7 }, -- crossguard
				{ 0.46, 0.64, 0.54, 0.64 },
				{ 0.47, 0.7, 0.47, 0.86 }, { 0.53, 0.7, 0.53, 0.86 },      -- grip
				{ 0.5, 0.86, 0.46, 0.9 }, { 0.46, 0.9, 0.5, 0.95 }, { 0.5, 0.95, 0.54, 0.9 }, { 0.54, 0.9, 0.5, 0.86 }, -- pommel
			},
			mirrored({
				{ 0.4, 0.64, 0.33, 0.52 }, { 0.33, 0.52, 0.38, 0.4 }, { 0.38, 0.4, 0.32, 0.28 }, -- flame tongues
				{ 0.32, 0.28, 0.4, 0.18 },
			})
		),
		nodes = {
			{ id = "iron_will", name = "Iron Will", glyph = "IW", x = 0.5, y = 0.9, cost = 1,
				description = "+50 Max HP", effect = { stat = "maxHealth", operation = "add", value = 50 } },
			{ id = "heavy_blows", name = "Heavy Blows", glyph = "HB", x = 0.5, y = 0.66, cost = 2, requires = "iron_will",
				description = "+0.06× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
			{ id = "shield_bash", name = "Crushing Force", glyph = "CF", x = 0.28, y = 0.66, cost = 2, requires = "heavy_blows",
				description = "+25% Knockback", effect = { stat = "knockback", operation = "percent", value = 0.25 } },
			{ id = "battle_rhythm", name = "Battle Rhythm", glyph = "BR", x = 0.72, y = 0.66, cost = 3, requires = "heavy_blows",
				description = "+12% Attack Speed", effect = { stat = "basicAttackSpeed", operation = "percent", value = 0.12 } },
			{ id = "wide_arcs", name = "Wide Arcs", glyph = "WA", x = 0.33, y = 0.46, cost = 3, requires = "shield_bash",
				description = "+12% Ability Area", effect = { stat = "size", operation = "percent", value = 0.12 } },
			{ id = "blood_oath", name = "Blood Oath", glyph = "BO", x = 0.67, y = 0.46, cost = 4, requires = "battle_rhythm",
				description = "+5% Lifesteal", effect = { stat = "lifesteal", operation = "percent", value = 0.05 } },
			{ id = "tempered", name = "Tempered Edge", glyph = "TE", x = 0.5, y = 0.32, cost = 4, requires = "wide_arcs",
				description = "+0.08× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.08 } },
			{ id = "infernal_heart", name = "Infernal Heart", glyph = "IH", x = 0.5, y = 0.06, cost = 6, requires = "tempered",
				description = "−12% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.12 } },
		},
	},

	-- ── Ranger: The Stag ────────────────────────────────────────────────────
	ranger = {
		name = "The Stag",
		lines = mirrored({
			{ 0.5, 0.86, 0.43, 0.72 }, { 0.43, 0.72, 0.41, 0.58 },   -- muzzle / cheek
			{ 0.41, 0.58, 0.44, 0.5 }, { 0.44, 0.5, 0.5, 0.48 },     -- brow
			{ 0.41, 0.56, 0.3, 0.52 }, { 0.3, 0.52, 0.38, 0.6 },     -- ear
			{ 0.44, 0.5, 0.4, 0.36 }, { 0.4, 0.36, 0.33, 0.2 }, { 0.33, 0.2, 0.3, 0.06 }, -- main beam
			{ 0.4, 0.36, 0.26, 0.34 }, { 0.26, 0.34, 0.16, 0.26 },   -- brow tine
			{ 0.36, 0.27, 0.24, 0.16 },                             -- bez tine
			{ 0.33, 0.2, 0.38, 0.1 },                               -- crown tine
			{ 0.46, 0.66, 0.48, 0.62 },                              -- nostril hint
		}),
		nodes = {
			{ id = "keen_eye", name = "Keen Eye", glyph = "KE", x = 0.5, y = 0.8, cost = 1,
				description = "+5% Crit Chance", effect = { stat = "critChance", operation = "percent", value = 0.05 } },
			{ id = "swift_feet", name = "Swift Feet", glyph = "SF", x = 0.36, y = 0.6, cost = 2, requires = "keen_eye",
				description = "+8% Move Speed", effect = { stat = "movementSpeed", operation = "percent", value = 0.08 } },
			{ id = "fletcher", name = "Fletcher", glyph = "FL", x = 0.64, y = 0.6, cost = 2, requires = "keen_eye",
				description = "+15% Projectile Speed", effect = { stat = "projectileSpeed", operation = "percent", value = 0.15 } },
			{ id = "rapid_draw", name = "Rapid Draw", glyph = "RD", x = 0.4, y = 0.36, cost = 3, requires = "swift_feet",
				description = "+12% Attack Speed", effect = { stat = "basicAttackSpeed", operation = "percent", value = 0.12 } },
			{ id = "venom_tips", name = "Venom Tips", glyph = "VT", x = 0.6, y = 0.36, cost = 3, requires = "fletcher",
				description = "+0.06× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
			{ id = "wild_growth", name = "Wild Growth", glyph = "WG", x = 0.26, y = 0.34, cost = 4, requires = "rapid_draw",
				description = "+15% Ability Duration", effect = { stat = "abilityDuration", operation = "percent", value = 0.15 } },
			{ id = "hunters_mark", name = "Hunter's Mark", glyph = "HM", x = 0.74, y = 0.34, cost = 4, requires = "venom_tips",
				description = "+8% Crit Chance", effect = { stat = "critChance", operation = "percent", value = 0.08 } },
			{ id = "split_shot", name = "Split Shot", glyph = "SS", x = 0.3, y = 0.06, cost = 6, requires = "wild_growth",
				description = "+1 Projectile", effect = { stat = "projectileCount", operation = "add", value = 1 } },
		},
	},

	-- ── Cleric: The Open Hands, beneath a cross ─────────────────────────────
	cleric = {
		name = "The Open Hands",
		lines = concat(
			{
				{ 0.5, 0.04, 0.5, 0.34 }, { 0.4, 0.13, 0.6, 0.13 },       -- cross
				{ 0.5, 0.42, 0.5, 0.9 },                                  -- stem
			},
			mirrored({
				{ 0.5, 0.9, 0.36, 0.84 }, { 0.36, 0.84, 0.24, 0.72 },     -- palm base
				{ 0.24, 0.72, 0.2, 0.58 }, { 0.2, 0.58, 0.14, 0.44 },     -- palm edge / thumb
				{ 0.24, 0.72, 0.28, 0.46 }, { 0.28, 0.46, 0.28, 0.36 },   -- fingers
				{ 0.32, 0.7, 0.36, 0.44 }, { 0.36, 0.44, 0.38, 0.34 },
				{ 0.4, 0.74, 0.44, 0.48 }, { 0.44, 0.48, 0.46, 0.4 },
				{ 0.36, 0.2, 0.3, 0.26 },                                -- light rays
				{ 0.4, 0.28, 0.34, 0.32 },
			})
		),
		nodes = {
			{ id = "devotion", name = "Devotion", glyph = "DE", x = 0.5, y = 0.88, cost = 1,
				description = "+40 Max HP", effect = { stat = "maxHealth", operation = "add", value = 40 } },
			{ id = "blessed_aura", name = "Blessed Aura", glyph = "BA", x = 0.3, y = 0.7, cost = 2, requires = "devotion",
				description = "+15% Ability Area", effect = { stat = "size", operation = "percent", value = 0.15 } },
			{ id = "faith", name = "Faith", glyph = "FA", x = 0.7, y = 0.7, cost = 2, requires = "devotion",
				description = "−8% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.08 } },
			{ id = "grace", name = "Grace", glyph = "GR", x = 0.2, y = 0.46, cost = 3, requires = "blessed_aura",
				description = "+15% Ability Duration", effect = { stat = "abilityDuration", operation = "percent", value = 0.15 } },
			{ id = "radiance", name = "Radiance", glyph = "RA", x = 0.8, y = 0.46, cost = 3, requires = "faith",
				description = "+0.06× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
			{ id = "mercy", name = "Mercy", glyph = "ME", x = 0.5, y = 0.5, cost = 4, requires = "grace",
				description = "+5% Lifesteal", effect = { stat = "lifesteal", operation = "percent", value = 0.05 } },
			{ id = "pilgrim", name = "Pilgrim", glyph = "PI", x = 0.4, y = 0.13, cost = 4, requires = "radiance",
				description = "+10% Move Speed", effect = { stat = "movementSpeed", operation = "percent", value = 0.1 } },
			{ id = "ascension", name = "Ascension", glyph = "AS", x = 0.5, y = 0.04, cost = 6, requires = "pilgrim",
				description = "−12% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.12 } },
		},
	},

	-- ── Ice Mage: The Snowflake ─────────────────────────────────────────────
	ice_mage = {
		name = "The Snowflake",
		lines = (function(): { { number } }
			local out = {}
			local cx, cy, r = 0.5, 0.5, 0.42
			for i = 0, 5 do
				local a = math.rad(i * 60 - 90)
				local dx, dy = math.cos(a), math.sin(a)
				table.insert(out, { cx, cy, cx + dx * r, cy + dy * r })
				-- two pairs of branches on each arm
				for _, t in ipairs({ 0.45, 0.72 }) do
					local bx, by = cx + dx * r * t, cy + dy * r * t
					local len = r * (t < 0.6 and 0.22 or 0.16)
					for _, s in ipairs({ -1, 1 }) do
						local ba = a + s * math.rad(40)
						table.insert(out, { bx, by, bx + math.cos(ba) * len, by + math.sin(ba) * len })
					end
				end
			end
			-- inner hexagon
			for i = 0, 5 do
				local a1, a2 = math.rad(i * 60 - 60), math.rad(i * 60)
				table.insert(out, { cx + math.cos(a1) * 0.12, cy + math.sin(a1) * 0.12, cx + math.cos(a2) * 0.12, cy + math.sin(a2) * 0.12 })
			end
			return out
		end)(),
		nodes = {
			{ id = "cold_core", name = "Cold Core", glyph = "CC", x = 0.5, y = 0.5, cost = 1,
				description = "+40 Max HP", effect = { stat = "maxHealth", operation = "add", value = 40 } },
			{ id = "frostbite", name = "Frostbite", glyph = "FR", x = 0.5, y = 0.2, cost = 2, requires = "cold_core",
				description = "+0.06× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
			{ id = "glacial_reach", name = "Glacial Reach", glyph = "GR", x = 0.24, y = 0.35, cost = 2, requires = "cold_core",
				description = "+12% Ability Area", effect = { stat = "size", operation = "percent", value = 0.12 } },
			{ id = "long_winter", name = "Long Winter", glyph = "LW", x = 0.76, y = 0.35, cost = 3, requires = "cold_core",
				description = "+15% Ability Duration", effect = { stat = "abilityDuration", operation = "percent", value = 0.15 } },
			{ id = "shatterpoint", name = "Shatterpoint", glyph = "SH", x = 0.24, y = 0.65, cost = 3, requires = "glacial_reach",
				description = "+6% Crit Chance", effect = { stat = "critChance", operation = "percent", value = 0.06 } },
			{ id = "deep_freeze", name = "Deep Freeze", glyph = "DF", x = 0.76, y = 0.65, cost = 4, requires = "long_winter",
				description = "−10% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.1 } },
			{ id = "glide", name = "Frictionless", glyph = "FR", x = 0.5, y = 0.8, cost = 4, requires = "shatterpoint",
				description = "+10% Move Speed", effect = { stat = "movementSpeed", operation = "percent", value = 0.1 } },
			{ id = "absolute_zero", name = "Absolute Zero", glyph = "AZ", x = 0.5, y = 0.08, cost = 6, requires = "frostbite",
				description = "+0.1× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.1 } },
		},
	},
}

-- Gunslinger: a revolver in profile — barrel, cylinder and raked grip.
TalentData.gunslinger = {
	name = "The Last Word",
	lines = (function()
		local out = {
			{ 0.12, 0.36, 0.62, 0.36 }, -- barrel top
			{ 0.12, 0.44, 0.62, 0.44 }, -- barrel bottom
			{ 0.12, 0.36, 0.12, 0.44 }, -- muzzle
			{ 0.62, 0.3, 0.8, 0.3 },    -- frame top
			{ 0.8, 0.3, 0.84, 0.46 },   -- hammer back
			{ 0.84, 0.46, 0.9, 0.82 },  -- grip back
			{ 0.9, 0.82, 0.74, 0.86 },  -- grip butt
			{ 0.74, 0.86, 0.68, 0.52 }, -- grip front
			{ 0.68, 0.52, 0.6, 0.6 },   -- trigger guard
			{ 0.6, 0.6, 0.54, 0.52 },
			{ 0.8, 0.3, 0.86, 0.24 },   -- hammer spur
		}
		-- cylinder: a hexagon around (0.62, 0.44)
		local cx, cy, r = 0.62, 0.44, 0.1
		for i = 0, 5 do
			local a1, a2 = math.rad(i * 60), math.rad(i * 60 + 60)
			table.insert(out, { cx + math.cos(a1) * r, cy + math.sin(a1) * r, cx + math.cos(a2) * r, cy + math.sin(a2) * r })
		end
		return out
	end)(),
	nodes = {
		{ id = "steady_hand", name = "Steady Hand", glyph = "SH", x = 0.62, y = 0.44, cost = 1,
			description = "+5% Crit Chance", effect = { stat = "critChance", operation = "percent", value = 0.05 } },
		{ id = "hot_barrel", name = "Hot Barrel", glyph = "HB", x = 0.4, y = 0.4, cost = 2, requires = "steady_hand",
			description = "+0.06× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
		{ id = "quick_draw", name = "Quick Draw", glyph = "QD", x = 0.84, y = 0.24, cost = 2, requires = "steady_hand",
			description = "+12% Attack Speed", effect = { stat = "basicAttackSpeed", operation = "percent", value = 0.12 } },
		{ id = "high_velocity", name = "High Velocity", glyph = "HV", x = 0.12, y = 0.4, cost = 3, requires = "hot_barrel",
			description = "+15% Projectile Speed", effect = { stat = "projectileSpeed", operation = "percent", value = 0.15 } },
		{ id = "light_boots", name = "Light Boots", glyph = "LB", x = 0.6, y = 0.6, cost = 3, requires = "steady_hand",
			description = "+10% Move Speed", effect = { stat = "movementSpeed", operation = "percent", value = 0.1 } },
		{ id = "trick_shooter", name = "Trick Shooter", glyph = "TS", x = 0.9, y = 0.82, cost = 4, requires = "quick_draw",
			description = "−10% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.1 } },
		{ id = "tough_hide", name = "Tough Hide", glyph = "TH", x = 0.74, y = 0.86, cost = 4, requires = "light_boots",
			description = "+40 Max HP", effect = { stat = "maxHealth", operation = "add", value = 40 } },
		{ id = "deadeye_legend", name = "Deadeye Legend", glyph = "DL", x = 0.12, y = 0.36, cost = 6, requires = "high_velocity",
			description = "+0.1× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.1 } },
	},
}

-- Swordsman: a longsword pointing up — blade, crossguard, grip and pommel.
TalentData.swordsman = {
	name = "Dawnsteel",
	lines = {
		{ 0.5, 0.06, 0.44, 0.14 }, { 0.5, 0.06, 0.56, 0.14 }, -- tip
		{ 0.44, 0.14, 0.44, 0.64 }, { 0.56, 0.14, 0.56, 0.64 }, -- blade edges
		{ 0.5, 0.18, 0.5, 0.6 },                                 -- fuller
		{ 0.24, 0.64, 0.76, 0.64 }, { 0.24, 0.64, 0.2, 0.6 }, { 0.76, 0.64, 0.8, 0.6 }, -- crossguard
		{ 0.46, 0.64, 0.46, 0.84 }, { 0.54, 0.64, 0.54, 0.84 }, -- grip
		{ 0.46, 0.84, 0.5, 0.9 }, { 0.54, 0.84, 0.5, 0.9 },     -- pommel
	},
	nodes = {
		{ id = "keen_edge", name = "Keen Edge", glyph = "KE", x = 0.5, y = 0.64, cost = 1,
			description = "+0.06× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
		{ id = "flowing_form", name = "Flowing Form", glyph = "FF", x = 0.5, y = 0.4, cost = 2, requires = "keen_edge",
			description = "+12% Attack Speed", effect = { stat = "basicAttackSpeed", operation = "percent", value = 0.12 } },
		{ id = "duelist_step", name = "Duelist's Step", glyph = "DS", x = 0.24, y = 0.64, cost = 2, requires = "keen_edge",
			description = "+10% Move Speed", effect = { stat = "movementSpeed", operation = "percent", value = 0.1 } },
		{ id = "iron_grip", name = "Iron Grip", glyph = "IG", x = 0.5, y = 0.84, cost = 2, requires = "keen_edge",
			description = "+40 Max HP", effect = { stat = "maxHealth", operation = "add", value = 40 } },
		{ id = "precise_cuts", name = "Precise Cuts", glyph = "PC", x = 0.76, y = 0.64, cost = 3, requires = "keen_edge",
			description = "+5% Crit Chance", effect = { stat = "critChance", operation = "percent", value = 0.05 } },
		{ id = "blood_price", name = "Blood Price", glyph = "BP", x = 0.5, y = 0.9, cost = 4, requires = "iron_grip",
			description = "+4% Lifesteal", effect = { stat = "lifesteal", operation = "percent", value = 0.04 } },
		{ id = "tempo", name = "Tempo", glyph = "TE", x = 0.5, y = 0.18, cost = 4, requires = "flowing_form",
			description = "−10% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.1 } },
		{ id = "blade_saint", name = "Blade Saint", glyph = "BS", x = 0.5, y = 0.06, cost = 6, requires = "tempo",
			description = "+0.1× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.1 } },
	},
}

-- Rogue: a dagger pointing up, with a crescent of shadow behind it.
TalentData.rogue = {
	name = "Nightblade",
	lines = {
		{ 0.5, 0.08, 0.44, 0.2 }, { 0.5, 0.08, 0.56, 0.2 },     -- tip
		{ 0.44, 0.2, 0.46, 0.58 }, { 0.56, 0.2, 0.54, 0.58 },   -- blade
		{ 0.32, 0.58, 0.68, 0.58 },                             -- guard
		{ 0.5, 0.58, 0.5, 0.84 },                               -- grip
		{ 0.22, 0.3, 0.2, 0.6 }, { 0.2, 0.6, 0.32, 0.86 },      -- shadow crescent
	},
	nodes = {
		{ id = "sharpened", name = "Sharpened", glyph = "SH", x = 0.5, y = 0.58, cost = 1,
			description = "+0.06× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
		{ id = "quick_hands", name = "Quick Hands", glyph = "QH", x = 0.5, y = 0.38, cost = 2, requires = "sharpened",
			description = "+12% Attack Speed", effect = { stat = "basicAttackSpeed", operation = "percent", value = 0.12 } },
		{ id = "light_step", name = "Light Step", glyph = "LS", x = 0.32, y = 0.58, cost = 2, requires = "sharpened",
			description = "+10% Move Speed", effect = { stat = "movementSpeed", operation = "percent", value = 0.1 } },
		{ id = "weak_spot", name = "Weak Spot", glyph = "WS", x = 0.68, y = 0.58, cost = 2, requires = "sharpened",
			description = "+6% Crit Chance", effect = { stat = "critChance", operation = "percent", value = 0.06 } },
		{ id = "padded_cowl", name = "Padded Cowl", glyph = "PC", x = 0.5, y = 0.84, cost = 3, requires = "sharpened",
			description = "+35 Max HP", effect = { stat = "maxHealth", operation = "add", value = 35 } },
		{ id = "night_hunger", name = "Night Hunger", glyph = "NH", x = 0.22, y = 0.3, cost = 4, requires = "light_step",
			description = "+4% Lifesteal", effect = { stat = "lifesteal", operation = "percent", value = 0.04 } },
		{ id = "fade", name = "Fade", glyph = "FA", x = 0.5, y = 0.2, cost = 4, requires = "quick_hands",
			description = "−10% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.1 } },
		{ id = "the_shadow", name = "The Shadow", glyph = "TS", x = 0.5, y = 0.08, cost = 6, requires = "fade",
			description = "+0.1× Damage", effect = { stat = "damage", operation = "multiplier", value = 0.1 } },
	},
}

-- Mage: an eight-pointed arcane star (the sheet's sigil): four long points
-- and four short diagonals round the middle.
TalentData.mage = {
	name = "The Unbroken Sky",
	lines = {
		{ 0.5, 0.06, 0.56, 0.44 }, { 0.5, 0.06, 0.44, 0.44 },   -- north point
		{ 0.5, 0.94, 0.56, 0.56 }, { 0.5, 0.94, 0.44, 0.56 },   -- south point
		{ 0.06, 0.5, 0.44, 0.44 }, { 0.06, 0.5, 0.44, 0.56 },   -- west point
		{ 0.94, 0.5, 0.56, 0.44 }, { 0.94, 0.5, 0.56, 0.56 },   -- east point
		{ 0.26, 0.26, 0.42, 0.42 }, { 0.74, 0.26, 0.58, 0.42 }, -- the short diagonals
		{ 0.26, 0.74, 0.42, 0.58 }, { 0.74, 0.74, 0.58, 0.58 },
	},
	nodes = {
		{ id = "focus", name = "Focus", glyph = "FO", x = 0.5, y = 0.5, cost = 1,
			description = "+0.06x Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
		{ id = "quick_tongue", name = "Quick Tongue", glyph = "QT", x = 0.5, y = 0.28, cost = 2, requires = "focus",
			description = "+12% Attack Speed", effect = { stat = "basicAttackSpeed", operation = "percent", value = 0.12 } },
		{ id = "wide_circle", name = "Wide Circle", glyph = "WC", x = 0.28, y = 0.5, cost = 2, requires = "focus",
			description = "+10% Ability Size", effect = { stat = "size", operation = "percent", value = 0.1 } },
		{ id = "long_echo", name = "Long Echo", glyph = "LE", x = 0.72, y = 0.5, cost = 2, requires = "focus",
			description = "+12% Ability Duration", effect = { stat = "abilityDuration", operation = "percent", value = 0.12 } },
		{ id = "warded_robes", name = "Warded Robes", glyph = "WR", x = 0.5, y = 0.72, cost = 3, requires = "focus",
			description = "+35 Max HP", effect = { stat = "maxHealth", operation = "add", value = 35 } },
		{ id = "second_bolt", name = "Second Bolt", glyph = "SB", x = 0.06, y = 0.5, cost = 4, requires = "wide_circle",
			description = "+1 Projectile", effect = { stat = "projectileCount", operation = "add", value = 1 } },
		{ id = "turning_pages", name = "Turning Pages", glyph = "TP", x = 0.5, y = 0.06, cost = 4, requires = "quick_tongue",
			description = "-10% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.1 } },
		{ id = "the_sky_obeys", name = "The Sky Obeys", glyph = "SO", x = 0.94, y = 0.5, cost = 6, requires = "long_echo",
			description = "+0.1x Damage", effect = { stat = "damage", operation = "multiplier", value = 0.1 } },
	},
}

-- Martial Artist: a dragon coiling up from below (the sheet's emblem): its
-- tail low on the left, the body winding up through the middle, the head at
-- the top right.
TalentData.martial_artist = {
	name = "The Coiled Dragon",
	lines = {
		{ 0.12, 0.88, 0.3, 0.7 }, { 0.3, 0.7, 0.5, 0.5 },       -- the tail up to the heart
		{ 0.5, 0.5, 0.3, 0.32 }, { 0.3, 0.32, 0.5, 0.16 },      -- the coil round to the crown
		{ 0.5, 0.16, 0.76, 0.24 }, { 0.76, 0.24, 0.92, 0.12 },   -- the neck to the head
		{ 0.5, 0.5, 0.74, 0.62 }, { 0.74, 0.62, 0.88, 0.86 },    -- a claw reaching down
	},
	nodes = {
		{ id = "centred", name = "Centred", glyph = "CE", x = 0.5, y = 0.5, cost = 1,
			description = "+0.06x Damage", effect = { stat = "damage", operation = "multiplier", value = 0.06 } },
		{ id = "swift_hands", name = "Swift Hands", glyph = "SH", x = 0.3, y = 0.32, cost = 2, requires = "centred",
			description = "+12% Attack Speed", effect = { stat = "basicAttackSpeed", operation = "percent", value = 0.12 } },
		{ id = "iron_body", name = "Iron Body", glyph = "IB", x = 0.3, y = 0.7, cost = 2, requires = "centred",
			description = "+35 Max HP", effect = { stat = "maxHealth", operation = "add", value = 35 } },
		{ id = "deep_breath", name = "Deep Breath", glyph = "DB", x = 0.74, y = 0.62, cost = 2, requires = "centred",
			description = "+12% Ability Duration", effect = { stat = "abilityDuration", operation = "percent", value = 0.12 } },
		{ id = "wide_stance", name = "Wide Stance", glyph = "WS", x = 0.12, y = 0.88, cost = 3, requires = "iron_body",
			description = "+10% Ability Size", effect = { stat = "size", operation = "percent", value = 0.1 } },
		{ id = "flowing_qi", name = "Flowing Qi", glyph = "FQ", x = 0.5, y = 0.16, cost = 4, requires = "swift_hands",
			description = "-10% Ability Cooldowns", effect = { stat = "abilityCooldown", operation = "percent", value = 0.1 } },
		{ id = "twin_dragons", name = "Twin Dragons", glyph = "TD", x = 0.88, y = 0.86, cost = 4, requires = "deep_breath",
			description = "+1 Projectile", effect = { stat = "projectileCount", operation = "add", value = 1 } },
		{ id = "dragon_soul", name = "Dragon Soul", glyph = "DS", x = 0.92, y = 0.12, cost = 6, requires = "flowing_qi",
			description = "+0.1x Damage", effect = { stat = "damage", operation = "multiplier", value = 0.1 } },
	},
}

local TalentModule = {}

function TalentModule.Get(classId: string): Constellation?
	return TalentData[classId]
end

function TalentModule.GetNode(classId: string, nodeId: string): TalentNode?
	local c = TalentData[classId]
	if not c then return nil end
	for _, n in ipairs(c.nodes) do
		if n.id == nodeId then return n end
	end
	return nil
end

return TalentModule
