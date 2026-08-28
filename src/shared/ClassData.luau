export type AbilityData = {
	name: string,
	description: string,
	tag: string,
}

export type ClassStats = {
	offense: number,   -- 1 to 5
	defense: number,   -- 1 to 5
	agility: number,   -- 1 to 5
	difficulty: number -- 1 to 5
}

export type ClassInfo = {
	id: string,
	name: string,
	title: string,
	role: string,
	description: string,
	accentColor: Color3,
	stats: ClassStats,
	abilities: { AbilityData },
}

local ClassData: { [string]: ClassInfo } = {
	["brawler"] = {
		id = "brawler",
		name = "Brawler",
		title = "The Unyielding Striker",
		role = "Bruiser / Melee",
		description = "A fierce martial artist fighting with bare fists and brass fury. Masters stagger combos and close-quarters shockwaves to crush enemy formations.",
		accentColor = Color3.fromRGB(245, 100, 45),
		stats = {
			offense = 5,
			defense = 3,
			agility = 4,
			difficulty = 2,
		},
		abilities = {
			{ name = "Heavy Jab", tag = "M1/Primary", description = "Deliver a bone-crushing punch with high poise damage." },
			{ name = "Seismic Slam", tag = "Skill 1", description = "Leap into the air and slam the ground, launching enemies upward." },
			{ name = "Flurry Rush", tag = "Skill 2", description = "Unleash a rapid sequence of devastating lightning punches." },
			{ name = "Titan Rampage", tag = "Ultimate", description = "Enter an enraged state, gaining immunity to stagger and 40% increased attack speed." },
		},
	},

	["heavy_knight"] = {
		id = "heavy_knight",
		name = "Heavy Knight",
		title = "The Bastion of Honor",
		role = "Tank / Vanguard",
		description = "Clad in impervious plate armor and carrying a massive tower shield. An unstoppable frontline fortress that protects allies and controls the battlefield.",
		accentColor = Color3.fromRGB(230, 190, 80),
		stats = {
			offense = 3,
			defense = 5,
			agility = 2,
			difficulty = 1,
		},
		abilities = {
			{ name = "Shield Bash", tag = "M1/Primary", description = "Strike with your heavy shield, stunning targets for a brief duration." },
			{ name = "Bulwark Stance", tag = "Skill 1", description = "Raise shield to block 70% of incoming damage and reflect projectiles." },
			{ name = "Whirlwind Cleave", tag = "Skill 2", description = "Spin your greatsword in a 360-degree arc, pulling nearby foes in." },
			{ name = "Fortress of Valor", tag = "Ultimate", description = "Plant a sacred banner that grants a massive damage barrier to all nearby allies." },
		},
	},

	["sorcerer"] = {
		id = "sorcerer",
		name = "Sorcerer",
		title = "The Arcane Prodigy",
		role = "Magic Burst / Caster",
		description = "Wields raw, unbridled arcane energy. Capable of obliterating entire enemy groups from afar with devastating cataclysms and dimensional shifts.",
		accentColor = Color3.fromRGB(175, 80, 255),
		stats = {
			offense = 5,
			defense = 1,
			agility = 3,
			difficulty = 4,
		},
		abilities = {
			{ name = "Arcane Bolt", tag = "M1/Primary", description = "Fire homing ethereal projectiles that explode on impact." },
			{ name = "Dimensional Blink", tag = "Skill 1", description = "Teleport instantaneously in your movement direction, leaving an arcane vortex behind." },
			{ name = "Meteor Surge", tag = "Skill 2", description = "Call down burning astral energy that incinerates a targeted area." },
			{ name = "Astral Singularity", tag = "Ultimate", description = "Summon a black hole that pulls all enemies inward before violently detonating." },
		},
	},

	["assassin"] = {
		id = "assassin",
		name = "Assassin",
		title = "The Shadow Phantom",
		role = "Infiltrator / Burst",
		description = "A swift shadow stalker lethal from behind. Uses deception, smoke, and venom-coated daggers to assassinate priority targets in seconds.",
		accentColor = Color3.fromRGB(235, 45, 85),
		stats = {
			offense = 5,
			defense = 1,
			agility = 5,
			difficulty = 4,
		},
		abilities = {
			{ name = "Shadow Step", tag = "Skill 1", description = "Teleport directly behind the closest target and critically strike." },
			{ name = "Venom Daggers", tag = "Skill 2", description = "Hurl 3 poisoned blades that inflict progressive bleed and slow effects." },
			{ name = "Smoke Cloak", tag = "Skill 3", description = "Vanish into thick smoke, becoming invisible and gaining 30% speed for 4s." },
			{ name = "Deathmark Execute", tag = "Ultimate", description = "Mark a target for death, delivering a flurry of fatal strikes that bypasses armor." },
		},
	},

	["cleric"] = {
		id = "cleric",
		name = "Cleric",
		title = "The Radiant Herald",
		role = "Support / Healer",
		description = "Channels the holy light of the divine to mend allies' wounds, cleanse curses, and smite unholy adversaries with sacred righteous power.",
		accentColor = Color3.fromRGB(255, 220, 110),
		stats = {
			offense = 2,
			defense = 4,
			agility = 2,
			difficulty = 2,
		},
		abilities = {
			{ name = "Radiant Smite", tag = "M1/Primary", description = "Cast a ray of holy light that damages enemies and restores ally vitality." },
			{ name = "Sanctuary Circle", tag = "Skill 1", description = "Form a consecrated circle on the ground providing continuous high healing." },
			{ name = "Divine Ward", tag = "Skill 2", description = "Encase yourself or an ally in a holy shield that cleanses crowd control." },
			{ name = "Heavenly Grace", tag = "Ultimate", description = "Release an immense burst of sacred light, fully rejuvenating the party and blinding foes." },
		},
	},

	["ranger"] = {
		id = "ranger",
		name = "Ranger",
		title = "The Apex Marksman",
		role = "Ranged DPS / Tracker",
		description = "A master of the wild who commands high-precision bows and cunning traps. Dominates long-range engagements with pinpoint accuracy.",
		accentColor = Color3.fromRGB(60, 210, 120),
		stats = {
			offense = 4,
			defense = 2,
			agility = 5,
			difficulty = 3,
		},
		abilities = {
			{ name = "Piercing Arrow", tag = "M1/Primary", description = "Charge and fire a high-velocity arrow that pierces multiple targets." },
			{ name = "Evasive Roll", tag = "Skill 1", description = "Quickly roll away from danger while firing a spread of slowing arrows." },
			{ name = "Bramble Snare", tag = "Skill 2", description = "Deploy a hidden trap that roots anyone who steps inside for 2.5s." },
			{ name = "Arrow Tempest", tag = "Ultimate", description = "Rain thousands of arrows over a vast area, decimating enemy legions." },
		},
	},

	["gunslinger"] = {
		id = "gunslinger",
		name = "Gunslinger",
		title = "The Maverick Outlaw",
		role = "Ranged Combo / Gun-Kata",
		description = "A stylish dual-revolver daredevil. Blends agile acrobatics with rapid-fire bullet storms to execute high-octane trick shots.",
		accentColor = Color3.fromRGB(250, 150, 50),
		stats = {
			offense = 4,
			defense = 2,
			agility = 5,
			difficulty = 4,
		},
		abilities = {
			{ name = "Twin Revolvers", tag = "M1/Primary", description = "Fire consecutive rounds from dual revolvers with high critical rate." },
			{ name = "Fan the Hammer", tag = "Skill 1", description = "Rapidly empty both cylinders in a lightning-fast cone barrage." },
			{ name = "Acrobatic Vault", tag = "Skill 2", description = "Leap over enemies in bullet-time while firing downward." },
			{ name = "High Noon Barrage", tag = "Ultimate", description = "Lock onto all visible targets and unleash an instant series of lethal headshots." },
		},
	},

	["ice_mage"] = {
		id = "ice_mage",
		name = "Ice Mage",
		title = "The Cryo Sorceress",
		role = "Control / AoE Frost",
		description = "Harnesses sub-zero arctic blizzards to lock down battlefield zones, construct impenetrable glacial barriers, and freeze enemies solid.",
		accentColor = Color3.fromRGB(70, 220, 255),
		stats = {
			offense = 4,
			defense = 3,
			agility = 2,
			difficulty = 3,
		},
		abilities = {
			{ name = "Glacial Shard", tag = "M1/Primary", description = "Hurl sharp ice daggers that apply stacking Frost (slows targets up to 50%)." },
			{ name = "Frost Barrier", tag = "Skill 1", description = "Erect a massive ice wall that blocks incoming enemy attacks and movement." },
			{ name = "Flash Freeze", tag = "Skill 2", description = "Trigger a sudden temperature drop, freezing all frosted enemies in place for 2s." },
			{ name = "Absolute Blizzard", tag = "Ultimate", description = "Summon an apocalyptic blizzard that blankets the zone in blinding frost and heavy damage." },
		},
	},
}

-- Array order for UI display
local ClassOrder: { string } = {
	"brawler",
	"heavy_knight",
	"sorcerer",
	"assassin",
	"cleric",
	"ranger",
	"gunslinger",
	"ice_mage",
}

return {
	Classes = ClassData,
	Order = ClassOrder,
	GetClass = function(id: string): ClassInfo?
		return ClassData[id]
	end,
}
