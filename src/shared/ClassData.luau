export type AbilityData = {
	name: string,
	description: string,
	tag: string,
	videoId: string?,
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
	["martial_artist"] = {
		id = "martial_artist",
		name = "Martial Artist",
		title = "Flow · Strike · Master",
		role = "Melee / Burst",
		description = "\"The body is the brush. Qi is the ink. The fight is the canvas.\" A bare-fisted master who channels golden Qi into dragons of living energy: fast, mobile, built on combos and huge bursts.",
		accentColor = Color3.fromRGB(255, 176, 60),
		stats = {
			strength = 4,
			vitality = 3,
			defense = 3,
			agility = 5,
			maxHealth = 140,
			offense = 5,
			difficulty = 3,
		},
		abilities = {
			{ name = "Flowing Fists", tag = "M1/Primary", description = "A 4-hit combo of Qi-charged strikes: a jab and a cross that throw flurries of phantom fists, a spinning roundhouse that hits all around you, and a dragon palm that bursts with Qi.", videoId = "" },
			{ name = "Qi Charge", tag = "Passive", description = "Build Qi Charge with your abilities and strikes. At 100 Charge your next ability becomes Empowered.", videoId = "" },
			{ name = "Dragon Fist", tag = "Skill 1 (E)", description = "Channel Qi into your fists, releasing a flowing dragon of energy that surges forward, dealing heavy damage and pushing enemies back. Empowered: three dragon fists, greater range and damage.", videoId = "" },
			{ name = "Qi Release", tag = "Skill 2 (F)", description = "Surround yourself with circulating Qi, increasing your movement speed and attack speed and reducing damage taken for a short time. Empowered: larger aura, higher speed, stronger damage reduction.", videoId = "" },
			{ name = "Dragon Ascent", tag = "Skill 3 (Q)", description = "Ride the flow of Qi, launching yourself upward with a dragon's energy, striking enemies in your path, landing with an explosive hit and leaving a lingering trail. Empowered: multiple dragon strikes, more hits, wider area.", videoId = "" },
			{ name = "Dragon Soul", tag = "Ultimate (R)", description = "Unleash the true power of the dragon within: summon a colossal dragon made of Qi that obliterates everything in its path.", videoId = "" },
		},
		equipment = {
			name = "Dragonheart Wraps & Red Sash",
			slot = "Bare Fists",
			rarity = "Legendary Discipline",
			description = "Hand wraps woven with golden thread and a crimson sash and headband. Qi flows through them as easily as breath.",
			stats = {
				["Max Health"] = "140 HP",
				["Qi Charge"] = "100 to Empower",
				["Qi Release"] = "-30% damage taken",
				["Combo"] = "4 hits",
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
			{ name = "Emberblade", tag = "M1/Primary", description = "A 4-hit sword combo forged in flame: Cinder Slash, Scorching Cross, Furnace Breaker, and the Infernal Execution slam with a line of fire.", videoId = "" },
			{ name = "Heat of War", tag = "Passive", description = "Every strike builds Heat. At 100 Heat you Overheat: bonus fire damage, burning ground, Empowered skills and no knockback, until the Heat crashes back down. Fire attacks stack Scorch; at 5 stacks an enemy Ignites and explodes, spreading Scorch.", videoId = "" },
			{ name = "Blazing Charge", tag = "Skill 1 (E)", description = "Charge forward in flames, dragging enemies along, and finish with an upward slash that launches them. Overheated: a bull rush through everyone that leaves the path burning.", videoId = "" },
			{ name = "Phoenix Slam", tag = "Skill 2 (F)", description = "Soar into the air as a phoenix of fire, pick your landing spot with the marker, and crash down in an explosion that leaves the ground burning.", videoId = "" },
			{ name = "Infernal Earthshaker", tag = "Skill 3 (Q)", description = "Drive the sword into the ground: a huge explosion, aftershocks rippling out and patches of fire. Overheated: three expanding rings of fire.", videoId = "" },
			{ name = "Heart of the Inferno", tag = "Ultimate (R)", description = "Plant the sword and become the fire: every attack explodes for several seconds, then every flame is drawn into the sword for one enormous flame wave. At 100 Heat it consumes Overheat and becomes the Primordial Inferno.", videoId = "" },
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
			{ name = "Greatsword", tag = "M1/Primary", description = "A heavy 3-hit chain: a diagonal cleave, a backhand, and an overhead smash that sends out a shockwave.", videoId = "" },
			{ name = "Rupture", tag = "Skill 1 (E)", description = "Leap to the cursor (up to 17 studs) and crash down: a crater, a spreading fracture and a shockwave that knocks enemies up. Empowered: bigger, with a second burst of crimson spikes.", videoId = "" },
			{ name = "Bloodstorm", tag = "Skill 2 (F)", description = "Plant your feet and carve huge crimson crescents in front of you, each blow landing with a jolt and a shove, then a spinning cleave that throws them out. Half damage taken meanwhile. Empowered: more slashes, bigger ones, a bigger finish.", videoId = "" },
			{ name = "Crimson Charge", tag = "Skill 3 (Q)", description = "Charge headlong at the aim, untouchable the whole way: every enemy in your path is cut and thrown aside, and a burst at the end blows everything near away. Your next skill is Empowered.", videoId = "" },
			{ name = "Beast Awakening", tag = "Ultimate (R)", description = "Fill your Rage (hit, cleave crowds, kill, take hits), then abandon your humanity: a roar, and for 12 s you are the BEAST. Claws: claw, claw, claw, a brutal maul. Beast Slam: a huge leap, a crash on all fours, three shockwave rings. Carnage: three enormous claw swipes that bleed and launch. Beast Charge: tear through everything on all fours, then hurl the biggest one into the rest.", videoId = "" },
		},
		equipment = {
			name = "Ragebringer",
			slot = "Greatsword (Two-Handed)",
			rarity = "Cursed Relic",
			description = "A blackened greatsword whose edge glows with the rage of every battle it has seen.",
			stats = {
				["Max Health"] = "260 HP",
				["Rage"] = "0 – 100",
				["Attack Speed"] = "+25% at full rage",
			},
		},
	},

	["mage"] = {
		id = "mage",
		name = "Mage",
		title = "The Arcanist",
		role = "Control / Arcane AoE",
		description = "Control. Manipulate. Destroy. The world is not broken, it's just a different form of magic: he traps whole groups in spectral chains, phases through space leaving echoes of himself behind, and calls down an arcane apocalypse from the sky.",
		accentColor = Color3.fromRGB(155, 85, 255),
		stats = {
			strength = 2,
			vitality = 2,
			defense = 2,
			agility = 3,
			maxHealth = 100,
			offense = 5,
			difficulty = 4,
		},
		abilities = {
			{ name = "Arcane Bolt", tag = "M1/Primary", description = "Fire bolts of arcane light that seek the enemy nearest your aim and burst where they hit.", videoId = "" },
			{ name = "Arcane Charge", tag = "Passive", description = "Your abilities build Arcane Charge: Arcane Burst +10, Astral Prison +20, Arcane Shift +15, Apocalypse +25. At 100 Charge your next ability is Empowered.", videoId = "" },
			{ name = "Arcane Burst", tag = "Skill 1 (E)", description = "Fire a concentrated arcane projectile that explodes on impact, pulling nearby enemies towards the center and leaving an Arcane Rune. Empowered: three converging projectiles.", videoId = "" },
			{ name = "Astral Prison", tag = "Skill 2 (F)", description = "Place a magic circle that, after a brief delay, traps enemies within spectral chains. The longer they remain, the more it charges before collapsing in a massive explosion. An Arcane Rune inside detonates too. Empowered: larger, pulls enemies in, explodes faster.", videoId = "" },
			{ name = "Arcane Shift", tag = "Skill 3 (Q)", description = "Phase through space to the target location, untargetable. Reappear with a shockwave and leave an Arcane Echo that repeats your next ability with reduced power. Empowered: three Arcane Echoes.", videoId = "" },
			{ name = "Apocalypse", tag = "Ultimate (R)", description = "Break the battlefield itself: mark every enemy in a large radius, call down a storm of arcane projectiles, then every mark detonates in a massive explosion.", videoId = "" },
		},
		equipment = {
			name = "Codex of the Unbroken Sky & Astral Robes",
			slot = "Floating Grimoire",
			rarity = "Mythic Arcana",
			description = "An ancient spellbook that floats open at the Mage's side, its pages burning with violet runes. Every spell he casts is read from it.",
			stats = {
				["Max Health"] = "100 HP",
				["Arcane Charge"] = "100 to Empower",
				["Echo Power"] = "50%",
				["Prison Charge"] = "up to 2.5x",
			},
		},
	},

	["rogue"] = {
		id = "rogue",
		name = "Rogue",
		title = "The Shadow",
		role = "Mobility / Burst",
		description = "Strike from the dark. Disappear. Repeat. A master of movement and deception who appears when you least expect it, leaving only chaos in their wake.",
		accentColor = Color3.fromRGB(215, 30, 60),
		stats = {
			strength = 4,
			vitality = 2,
			defense = 1,
			agility = 5,
			maxHealth = 95,
			offense = 5,
			difficulty = 4,
		},
		abilities = {
			{ name = "Shadow Dagger", tag = "Skill 1", description = "Throw a dagger that marks the first enemy it hits. Press again to Shadow Step to it: you appear behind a marked enemy for bonus damage. Works while invisible.", videoId = "" },
			{ name = "Dash", tag = "Skill 2", description = "Dash instantly in the aimed direction, slashing through every enemy on the way and applying the Shadow Mark.", videoId = "" },
			{ name = "Invisibility", tag = "Skill 3", description = "Vanish for 6 seconds: enemies lose you and you move faster. Attacking or taking damage ends it early.", videoId = "" },
			{ name = "Shadow Execution", tag = "Ultimate", description = "Throw a smoke bomb and vanish. Your afterimages strike every enemy in the smoke from all sides, marking them; then you reappear behind the target and detonate every mark at once.", videoId = "" },
		},
		equipment = {
			name = "Shadowfang & Crimson Cowl",
			slot = "Dagger & Hood",
			rarity = "Shadow Relic",
			description = "A black dagger with a crimson edge. Passive: dealing damage builds Shadow Energy; at full, your next ability is enhanced. Marked enemies take more damage, kills give a burst of speed, and cooldowns run faster while invisible.",
			stats = {
				["Max Health"] = "95 HP",
				["Marked Damage"] = "+25%",
				["Speed after a kill"] = "+25%",
				["Cooldowns while invisible"] = "x2 speed",
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
			{ name = "Radiant Smite", tag = "M1/Primary", description = "Cast a ray of holy light that damages enemies and restores ally vitality.", videoId = "" },
			{ name = "Sanctuary Circle", tag = "Skill 1 (E)", description = "Form a consecrated circle on the ground providing continuous high healing.", videoId = "" },
			{ name = "Divine Ward", tag = "Skill 2 (F)", description = "Encase yourself or an ally in a holy shield that cleanses crowd control.", videoId = "" },
			{ name = "Heavenly Grace", tag = "Ultimate (R)", description = "Release an immense burst of sacred light, fully rejuvenating the party and blinding foes.", videoId = "" },
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
			{ name = "Venom Arrows", tag = "M1/Primary", description = "Fire poison-coated arrows as fast, readable ranged basic attacks.", videoId = "" },
			{ name = "Verdant Slash", tag = "Skill 1 (E)", description = "Instantly dash through enemies, leaving a piercing nature energy slash that cuts all foes in your path.", videoId = "" },
			{ name = "Entangling Arrow", tag = "Skill 2 (F)", description = "Launch a root-charged arrow that bursts into vines and holds enemies in place.", videoId = "" },
			{ name = "Toxic Cloud", tag = "Skill 3 (Q)", description = "Throw a spore pod that leaves a lingering poison cloud on the ground.", videoId = "" },
			{ name = "Rain of Arrows", tag = "Ultimate (R)", description = "Mark a large zone from above and flood it with repeated arrow impacts.", videoId = "" },
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
			{ name = "Six Shooter", tag = "M1/Primary", description = "Six rounds, then a reload. The sixth shot hits hardest.", videoId = "" },
			{ name = "Deadeye", tag = "Passive", description = "Clean consecutive hits fill Deadeye. Full meter: your next hit is a piercing critical shot.", videoId = "" },
			{ name = "Fan the Hammer", tag = "Skill 1 (E)", description = "Empty every bullet left in the cylinder in a blistering short-range burst.", videoId = "" },
			{ name = "Gunslinger's Roll", tag = "Skill 2 (F / Space)", description = "Roll with brief invulnerability, dropping a flashbang that stuns nearby enemies (not bosses; more with Projectile Count), then fire one shot at the cursor as you land.", videoId = "" },
			{ name = "Deadeye Ricochet", tag = "Skill 3 (Q)", description = "Toss a spinning coin. Shoot it and the bullet splits into ricochets that seek every enemy in the room.", videoId = "" },
			{ name = "High Noon", tag = "Ultimate (R)", description = "Time slows. Mark every enemy in the room, gun them down one by one, then finish with a Deadeye execution.", videoId = "" },
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
			{ name = "Sword Combo", tag = "M1/Primary", description = "A 4-hit chain: slash, cross slash, thrust, and a spinning finisher that knocks enemies back.", videoId = "" },
			{ name = "Battle Momentum", tag = "Passive", description = "Every sword hit builds Momentum (up to 10) for faster attacks. At max, your next ability is Empowered.", videoId = "" },
			{ name = "Sword Rush", tag = "Skill 1 (E)", description = "Dash through enemies with two rapid strikes. Enemies hit by both take extra damage.", videoId = "" },
			{ name = "Parry", tag = "Skill 2 (F)", description = "A brief guard. Parry an attack to negate it, stun the attacker and answer with a huge upward slash.", videoId = "" },
			{ name = "Whirlwind", tag = "Skill 3 (Q)", description = "Spin with your blade out, dragging foes in, then launch them away on the last cut.", videoId = "" },
			{ name = "Blade Storm", tag = "Ultimate (R)", description = "Plant the sword, slow the world, then flash to every enemy in the room in a chain of slashes and end with a giant X that hits the whole room.", videoId = "" },
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
			{ name = "Ice Crystal", tag = "M1/Primary", description = "Fire a sleek ice crystal that shatters on the first enemy it hits.", videoId = "" },
			{ name = "Ice Spikes", tag = "Skill 1 (E)", description = "A racing line of crystalline spikes erupts from the floor, piercing and freezing all in its path.", videoId = "" },
			{ name = "Ice Beam", tag = "Skill 2 (F)", description = "Channel a blinding beam of absolute cold that stops on, and freezes, the first enemy it hits.", videoId = "" },
			{ name = "Ice Clone", tag = "Skill 3 (Q)", description = "Summon a crystalline clone that taunts foes, then explodes into a freezing shockwave.", videoId = "" },
			{ name = "Blizzard", tag = "Ultimate (R)", description = "Call down a raging blizzard that freezes the battlefield and batters enemies with ice.", videoId = "" },
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
	rogue = true,
	mage = true,
	martial_artist = true,
}

-- Array order for Carousel / UI display: playable classes first, locked after.
local ClassOrder: { string } = {
	"heavy_knight",
	"rogue",
	"mage",
	"martial_artist",
	"ranger",
	"cleric",
	"ice_mage",
	"gunslinger",
	"swordsman",
	"berserker",
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
