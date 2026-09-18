export type AbilityData = {
	name: string,
	description: string,
	tag: string,
}

export type ClassStats = {
	strength: number,   -- 1 to 5
	vitality: number,   -- 1 to 5
	defense: number,    -- 1 to 5
	agility: number,    -- 1 to 5
	maxHealth: number?, -- base max HP (e.g. 1000 for heavy knight)
	offense: number?,
	difficulty: number?,
}

export type EquipmentData = {
	name: string,
	slot: string,
	rarity: string,
	description: string,
	stats: { [string]: string },
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
	equipment: EquipmentData,
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
			strength = 5,
			vitality = 4,
			defense = 3,
			agility = 4,
			maxHealth = 100,
			offense = 5,
			difficulty = 2,
		},
		abilities = {
			{ name = "Heavy Jab", tag = "M1/Primary", description = "Deliver a bone-crushing punch with high poise damage." },
			{ name = "Seismic Slam", tag = "Skill 1", description = "Leap into the air and slam the ground, launching enemies upward." },
			{ name = "Flurry Rush", tag = "Skill 2", description = "Unleash a rapid sequence of devastating lightning punches." },
			{ name = "Titan Rampage", tag = "Ultimate", description = "Enter an enraged state, gaining immunity to stagger and 40% increased attack speed." },
		},
		equipment = {
			name = "Dragonbone Cestus & Iron Gauntlets",
			slot = "Dual Gauntlets",
			rarity = "Relic Weapon",
			description = "Reinforced knuckle braces carved from ancient dragonbone, converting physical impact into explosive shockwaves.",
			stats = {
				["Max Health"] = "100 HP",
				["Physical DMG"] = "+35%",
				["Attack Speed"] = "+20%",
				["Stun Power"] = "+40%",
			},
		},
	},

	["heavy_knight"] = {
		id = "heavy_knight",
		name = "Heavy Knight",
		title = "The Bastion of Honor",
		role = "Tank / Vanguard",
		description = "Clad in impervious plate armor and carrying a colossal greatsword. An unstoppable frontline fortress with unmatched survivability and raw physical might.",
		accentColor = Color3.fromRGB(230, 190, 80),
		stats = {
			strength = 5,
			vitality = 5,
			defense = 5,
			agility = 2,
			maxHealth = 1000,
			offense = 4,
			difficulty = 1,
		},
		abilities = {
			{ name = "Heavy Cleave", tag = "M1/Primary", description = "Slash with your colossal greatsword, dealing heavy wide-arc melee damage." },
			{ name = "Bulwark Stance", tag = "Skill 1", description = "Raise defensive stance to block incoming damage and reflect projectiles." },
			{ name = "Whirlwind Cleave", tag = "Skill 2", description = "Spin your greatsword in a 360-degree high-damage arc, pulling nearby foes in." },
			{ name = "Fortress of Valor", tag = "Ultimate", description = "Plant a sacred banner that grants a massive damage barrier to all nearby allies." },
		},
		equipment = {
			name = "Bastion Greatplate & Vanguard Greatsword",
			slot = "Heavy Plate & Greatsword",
			rarity = "Legendary Vanguard Gear",
			description = "Impervious gilded armor forged in sacred dragonfire. Grants impenetrable poise, colossal health pool, and absolute frontline dominion.",
			stats = {
				["Max Health"] = "1000 HP",
				["Strength"] = "+95% Power",
				["Vitality"] = "+90% Poise",
				["Damage Barrier"] = "+50%",
			},
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
			strength = 2,
			vitality = 2,
			defense = 1,
			agility = 3,
			maxHealth = 100,
			offense = 5,
			difficulty = 4,
		},
		abilities = {
			{ name = "Arcane Bolt", tag = "M1/Primary", description = "Fire homing ethereal projectiles that explode on impact." },
			{ name = "Dimensional Blink", tag = "Skill 1", description = "Teleport instantaneously in your movement direction, leaving an arcane vortex behind." },
			{ name = "Meteor Surge", tag = "Skill 2", description = "Call down burning astral energy that incinerates a targeted area." },
			{ name = "Astral Singularity", tag = "Ultimate", description = "Summon a black hole that pulls all enemies inward before violently detonating." },
		},
		equipment = {
			name = "Astral Singularity Staff & Arcane Grimoire",
			slot = "Two-Handed Catalyst",
			rarity = "Mythic Arcana",
			description = "A conduit crowned with a floating cosmic shard that continually funnels raw ether into spell damage.",
			stats = {
				["Max Health"] = "100 HP",
				["Magic Power"] = "+50%",
				["Mana Regen"] = "+30%",
				["Spell Radius"] = "+25%",
			},
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
			strength = 4,
			vitality = 2,
			defense = 1,
			agility = 5,
			maxHealth = 100,
			offense = 5,
			difficulty = 4,
		},
		abilities = {
			{ name = "Shadow Step", tag = "Skill 1", description = "Teleport directly behind the closest target and critically strike." },
			{ name = "Venom Daggers", tag = "Skill 2", description = "Hurl 3 poisoned blades that inflict progressive bleed and slow effects." },
			{ name = "Smoke Cloak", tag = "Skill 3", description = "Vanish into thick smoke, becoming invisible and gaining 30% speed for 4s." },
			{ name = "Deathmark Execute", tag = "Ultimate", description = "Mark a target for death, delivering a flurry of fatal strikes that bypasses armor." },
		},
		equipment = {
			name = "Shadowfang Dual Daggers & Twilight Cowl",
			slot = "Dual Blades & Cloak",
			rarity = "Shadow Relic",
			description = "Obsidian daggers dipped in basilisk venom that bypass armor on critical backstabs.",
			stats = {
				["Max Health"] = "100 HP",
				["Crit Chance"] = "+35%",
				["Crit DMG"] = "+75%",
				["Move Speed"] = "+15%",
			},
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
			strength = 2,
			vitality = 4,
			defense = 4,
			agility = 2,
			maxHealth = 100,
			offense = 2,
			difficulty = 2,
		},
		abilities = {
			{ name = "Radiant Smite", tag = "M1/Primary", description = "Cast a ray of holy light that damages enemies and restores ally vitality." },
			{ name = "Sanctuary Circle", tag = "Skill 1", description = "Form a consecrated circle on the ground providing continuous high healing." },
			{ name = "Divine Ward", tag = "Skill 2", description = "Encase yourself or an ally in a holy shield that cleanses crowd control." },
			{ name = "Heavenly Grace", tag = "Ultimate", description = "Release an immense burst of sacred light, fully rejuvenating the party and blinding foes." },
		},
		equipment = {
			name = "Sunfire Scepter & Radiant Scripture",
			slot = "Main Hand Scepter",
			rarity = "Sacred Relic",
			description = "An illuminated holy scepter channeling restorative sunburst pulses that cleanses all party debuffs.",
			stats = {
				["Max Health"] = "100 HP",
				["Healing Output"] = "+60%",
				["Aura Radius"] = "+40%",
				["Max Spirit"] = "+200",
			},
		},
	},

	["ranger"] = {
		id = "ranger",
		name = "Ranger",
		title = "The Verdant Venom",
		role = "Ranged DPS / Control",
		description = "A druidic archer who coats arrows in venom, commands grasping roots, and blankets the battlefield in toxic spores and arrow storms.",
		accentColor = Color3.fromRGB(70, 220, 105),
		stats = {
			strength = 3,
			vitality = 3,
			defense = 2,
			agility = 5,
			maxHealth = 100,
			offense = 4,
			difficulty = 3,
		},
		abilities = {
			{ name = "Venom Arrows", tag = "M1/Primary", description = "Fire poison-coated arrows as fast, readable ranged basic attacks." },
			{ name = "Thorn Barrage", tag = "Skill 1", description = "Fire exactly five arrows at once in a forward fan, each hitting independently." },
			{ name = "Entangling Arrow", tag = "Skill 2", description = "Launch a root-charged arrow that bursts into vines and holds enemies in place." },
			{ name = "Toxic Cloud", tag = "Skill 3", description = "Throw a spore pod that leaves a lingering poison cloud on the ground." },
			{ name = "Rain of Arrows", tag = "Ultimate", description = "Mark a large zone from above and flood it with repeated arrow impacts." },
		},
		equipment = {
			name = "Elderthorn Bow & Venomseed Quiver",
			slot = "Two-Handed Bow",
			rarity = "Ancient Druid Relic",
			description = "A living bow bent from elderwood and fed by venomous spores. Its arrows bloom into thorns, roots, and toxic clouds.",
			stats = {
				["Max Health"] = "100 HP",
				["Poison DMG"] = "+45%",
				["Root Duration"] = "+25%",
				["Projectile Speed"] = "+35%",
			},
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
			strength = 3,
			vitality = 3,
			defense = 2,
			agility = 5,
			maxHealth = 100,
			offense = 4,
			difficulty = 4,
		},
		abilities = {
			{ name = "Twin Revolvers", tag = "M1/Primary", description = "Fire consecutive rounds from dual revolvers with high critical rate." },
			{ name = "Fan the Hammer", tag = "Skill 1", description = "Rapidly empty both cylinders in a lightning-fast cone barrage." },
			{ name = "Acrobatic Vault", tag = "Skill 2", description = "Leap over enemies in bullet-time while firing downward." },
			{ name = "High Noon Barrage", tag = "Ultimate", description = "Lock onto all visible targets and unleash an instant series of lethal headshots." },
		},
		equipment = {
			name = "Twin Hellfire Revolvers & Bandit Bandolier",
			slot = "Dual Revolvers",
			rarity = "Outlaw Masterpiece",
			description = "Custom chrome-engraved six-shooters with lightning hammer actions and explosive fire-rounds.",
			stats = {
				["Max Health"] = "100 HP",
				["Fire Rate"] = "+40%",
				["Reload Speed"] = "+35%",
				["Headshot DMG"] = "+60%",
			},
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
			strength = 2,
			vitality = 3,
			defense = 3,
			agility = 2,
			maxHealth = 100,
			offense = 4,
			difficulty = 3,
		},
		abilities = {
			{ name = "Glacial Shard", tag = "M1/Primary", description = "Hurl sharp ice daggers that apply stacking Frost (slows targets up to 50%)." },
			{ name = "Frost Barrier", tag = "Skill 1", description = "Erect a massive ice wall that blocks incoming enemy attacks and movement." },
			{ name = "Flash Freeze", tag = "Skill 2", description = "Trigger a sudden temperature drop, freezing all frosted enemies in place for 2s." },
			{ name = "Absolute Blizzard", tag = "Ultimate", description = "Summon an apocalyptic blizzard that blankets the zone in blinding frost and heavy damage." },
		},
		equipment = {
			name = "Glacial Frostcore Orb & Permafrost Robes",
			slot = "Off-Hand Relic Orb",
			rarity = "Frozen Relic",
			description = "A floating sphere of pure unmelting absolute-zero ice that continually chills the surrounding atmosphere.",
			stats = {
				["Max Health"] = "100 HP",
				["Frost Slow Effect"] = "+30%",
				["Freeze Duration"] = "+1.5s",
				["Spell Area"] = "+35%",
			},
		},
	},
}

-- Array order for Carousel / UI display
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
