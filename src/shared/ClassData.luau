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
	maxHealth: number?, -- base max HP (e.g. 300 for heavy knight)
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
		name = "Fire Knight",
		title = "The Infernal Vanguard",
		role = "Bruiser / Vanguard",
		description = "\"The longer the fight continues, the hotter the battlefield becomes.\" Every strike builds Heat until he Overheats, and everything he touches is Scorched until it Ignites.",
		accentColor = Color3.fromRGB(255, 120, 40),
		stats = {
			strength = 5,
			vitality = 5,
			defense = 5,
			agility = 2,
			maxHealth = 300,
			offense = 4,
			difficulty = 1,
		},
		abilities = {
			{ name = "Emberblade", tag = "M1/Primary", description = "A 4-hit sword combo forged in flame: Cinder Slash, Scorching Cross, Furnace Breaker, and the Infernal Execution slam with a line of fire." },
			{ name = "Heat of War", tag = "Passive", description = "Every strike builds Heat. At 100 Heat you Overheat: bonus fire damage, burning ground, Empowered skills and no knockback, until the Heat crashes back down. Fire attacks stack Scorch; at 5 stacks an enemy Ignites and explodes, spreading Scorch." },
			{ name = "Blazing Charge", tag = "Skill 1 (E)", description = "Charge forward in flames, dragging enemies along, and finish with an upward slash that launches them. Overheated: a bull rush through everyone that leaves the path burning." },
			{ name = "Phoenix Slam", tag = "Skill 2 (F)", description = "Soar into the air as a phoenix of fire, pick your landing spot with the marker, and crash down in an explosion that leaves the ground burning." },
			{ name = "Infernal Earthshaker", tag = "Skill 3 (Q)", description = "Drive the sword into the ground: a huge explosion, aftershocks rippling out and patches of fire. Overheated: three expanding rings of fire." },
			{ name = "Heart of the Inferno", tag = "Ultimate (R)", description = "Plant the sword and become the fire: every attack explodes for several seconds, then every flame is drawn into the sword for one enormous flame wave. At 100 Heat it consumes Overheat and becomes the Primordial Inferno." },
		},
		equipment = {
			name = "Emberblade Greatsword",
			slot = "Greatsword",
			rarity = "Infernal Relic",
			description = "A colossal blade that drinks the heat of battle. Its flames grow with every strike until the whole blade burns.",
			stats = {
				["Max Health"] = "300 HP",
				["Heat"] = "0 – 100",
				["Overheat"] = "6 s",
				["Scorch"] = "Ignite at 5",
			},
		},
	},

	["berserker"] = {
		id = "berserker",
		name = "Berserker",
		title = "The Crimson Ravager",
		role = "Melee / High Damage",
		description = "\"Rage fuels strength. Strength feeds rage.\" A black-armored warrior with an enormous greatsword who turns momentum into ever more violent attacks, until he tears the battlefield apart.",
		accentColor = Color3.fromRGB(200, 20, 36),
		stats = {
			strength = 5,
			vitality = 4,
			defense = 3,
			agility = 3,
			maxHealth = 260,
			offense = 5,
			difficulty = 2,
		},
		abilities = {
			{ name = "Greatsword", tag = "M1/Primary", description = "A heavy 3-hit chain: a diagonal cleave, a backhand, and an overhead smash that sends out a shockwave." },
			{ name = "Rupture", tag = "Skill 1 (E)", description = "Leap to the cursor (up to 17 studs) and crash down: a crater, a spreading fracture and a shockwave that knocks enemies up. Empowered: bigger, with a second burst of crimson spikes." },
			{ name = "Bloodstorm", tag = "Skill 2 (F)", description = "Dash between nearby enemies with ever faster slashes, red afterimages behind you, then a spinning cleave that throws them out. Half damage taken meanwhile. Empowered: more dashes, a bigger finish." },
			{ name = "Bloodrage: Unchained", tag = "Skill 3 (Q)", description = "Plant the sword and roar: a crimson pulse, then faster, harder attacks for 8 s, red lightning and smoke pouring off you. Your next skill is Empowered." },
			{ name = "Worldbreaker", tag = "Ultimate (R)", description = "Gather, launch into the sky and dive onto the aimed spot dragging a giant crimson blade: a cataclysmic impact, then a second explosion that executes the badly wounded." },
		},
		equipment = {
			name = "Ragebringer",
			slot = "Greatsword (Two-Handed)",
			rarity = "Cursed Relic",
			description = "A blackened greatsword whose edge glows with the rage of every battle it has seen.",
			stats = {
				["Max Health"] = "260 HP",
				["Bloodrage"] = "0 – 100",
				["Attack Speed"] = "+25% at full rage",
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
			{ name = "Verdant Slash", tag = "Skill 1", description = "Instantly dash through enemies, leaving a piercing nature energy slash that cuts all foes in your path." },
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
		title = "The Deadeye Outlaw",
		role = "Ranged DPS / Burst",
		description = "A dark-frontier trick-shooter with a single engraved six-shooter. Every bullet counts: build Deadeye with clean hits, toss a coin into the crowd, and split one perfect shot into a storm of ricochets.",
		accentColor = Color3.fromRGB(255, 186, 70),
		stats = {
			strength = 3,
			vitality = 2,
			defense = 2,
			agility = 5,
			maxHealth = 100,
			offense = 5,
			difficulty = 5,
		},
		abilities = {
			{ name = "Six Shooter", tag = "M1/Primary", description = "Six rounds, then a reload. The sixth shot hits hardest." },
			{ name = "Deadeye", tag = "Passive", description = "Clean consecutive hits fill Deadeye. Full meter: your next hit is a piercing critical shot." },
			{ name = "Fan the Hammer", tag = "Skill 1 (E)", description = "Empty every bullet left in the cylinder in a blistering short-range burst." },
			{ name = "Gunslinger's Roll", tag = "Skill 2 (F / Space)", description = "Roll with brief invulnerability, then fire one shot at the cursor as you land." },
			{ name = "Deadeye Ricochet", tag = "Skill 3 (Q)", description = "Toss a spinning coin. Shoot it and the bullet splits into ricochets that seek nearby enemies." },
			{ name = "High Noon", tag = "Ultimate (R)", description = "Time slows. Mark every enemy in range, gun them down one by one, then finish with a Deadeye execution." },
		},
		equipment = {
			name = "The Last Word & Outlaw's Coat",
			slot = "Engraved Revolver",
			rarity = "Outlaw Relic",
			description = "A six-shooter etched with golden runes that hum when a shot is lined up. Its brass cylinder never quite stops turning.",
			stats = {
				["Max Health"] = "100 HP",
				["Cylinder"] = "6 rounds",
				["Final Shot"] = "+80% DMG",
				["Deadeye Shot"] = "Pierce + Crit",
			},
		},
	},

	["swordsman"] = {
		id = "swordsman",
		name = "Sword Master",
		title = "The Blade Dancer",
		role = "Melee DPS / Duelist",
		description = "A fast, precise duelist with a longsword. Chain combos to build Momentum, dash through the line, parry what would kill you, and end it all in a storm of blades.",
		accentColor = Color3.fromRGB(245, 225, 165),
		stats = {
			strength = 4,
			vitality = 3,
			defense = 2,
			agility = 5,
			maxHealth = 150,
			offense = 5,
			difficulty = 3,
		},
		abilities = {
			{ name = "Sword Combo", tag = "M1/Primary", description = "A 4-hit chain: slash, cross slash, thrust, and a spinning finisher that knocks enemies back." },
			{ name = "Battle Momentum", tag = "Passive", description = "Every sword hit builds Momentum (up to 10) for faster attacks. At max, your next ability is Empowered." },
			{ name = "Sword Rush", tag = "Skill 1 (E)", description = "Dash through enemies with two rapid strikes. Enemies hit by both take extra damage." },
			{ name = "Parry", tag = "Skill 2 (F)", description = "A brief guard. Parry an attack to negate it, stun the attacker and answer with a huge upward slash." },
			{ name = "Whirlwind", tag = "Skill 3 (Q)", description = "Spin with your blade out, dragging foes in, then launch them away on the last cut." },
			{ name = "Blade Storm", tag = "Ultimate (R)", description = "Plant the sword, slow the world, then flash to every enemy in the room in a chain of slashes and end with a giant X that hits the whole room." },
		},
		equipment = {
			name = "Dawnsteel Longsword",
			slot = "Longsword",
			rarity = "Duelist Relic",
			description = "A balanced blade with a gilded guard. It sings faster the longer the fight goes on.",
			stats = {
				["Max Health"] = "150 HP",
				["Combo"] = "4 hits",
				["Momentum"] = "10 stacks",
				["Parry"] = "Stun + Counter",
			},
		},
	},

	["ice_mage"] = {
		id = "ice_mage",
		name = "Ice Mage",
		title = "The Cryo Sorceress",
		role = "Control / AoE Frost",
		description = "Weaves crystalline frost into spikes, beams and living ice. Pins enemies in place, baits them with a shattering clone, and buries the battlefield in a blizzard.",
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
			{ name = "Ice Crystal", tag = "M1/Primary", description = "Fire a sleek ice crystal that shatters on the first enemy it hits." },
			{ name = "Ice Spikes", tag = "Skill 1 (E)", description = "A racing line of crystalline spikes erupts from the floor, piercing and freezing all in its path." },
			{ name = "Ice Beam", tag = "Skill 2 (F)", description = "Channel a blinding beam of absolute cold that stops on, and freezes, the first enemy it hits." },
			{ name = "Ice Clone", tag = "Skill 3 (Q)", description = "Summon a crystalline clone that taunts foes, then explodes into a freezing shockwave." },
			{ name = "Blizzard", tag = "Ultimate (R)", description = "Call down a raging blizzard that freezes the battlefield and batters enemies with ice." },
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

-- Classes with a finished kit. The rest are shown locked in class selection
-- and rejected by the server.
local PlayableClasses: { [string]: boolean } = {
	heavy_knight = true,
	ranger = true,
	cleric = true,
	ice_mage = true,
	gunslinger = true,
	swordsman = true,
	berserker = true,
}

-- Array order for Carousel / UI display: playable classes first, locked after.
local ClassOrder: { string } = {
	"heavy_knight",
	"ranger",
	"cleric",
	"ice_mage",
	"gunslinger",
	"swordsman",
	"berserker",
	"brawler",
	"sorcerer",
	"assassin",
}

return {
	Classes = ClassData,
	Order = ClassOrder,
	GetClass = function(id: string): ClassInfo?
		return ClassData[id]
	end,
	IsPlayable = function(id: string): boolean
		return PlayableClasses[id] == true
	end,
}
