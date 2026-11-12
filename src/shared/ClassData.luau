export type AbilityData = {
	name: string,
	description: string,
	summary: string?,
	tag: string,
	icon: string?,
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

-- Class-select ratings, 0 to 100.
export type ClassRatings = {
	damage: number,
	survivability: number,
	mobility: number,
	range: number,
	difficulty: number,
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
	-- Class select (filled in from DISPLAY below):
	tagline: string?,      -- "The Infernal Vanguard"
	roles: { string }?,    -- { "Bruiser", "Vanguard" }
	ratings: ClassRatings?,
	emblem: string?,       -- a glyph over the name
	glowColor: Color3?,    -- second colour for the pedestal and aura
}

local ClassData: { [string]: ClassInfo } = {
	["martial_artist"] = {
		id = "martial_artist",
		name = "Martial Artist",
		title = "Flow · Strike · Master",
		role = "Melee / Burst",
		description = "Fast, mobile brawler. Long combos and big bursts.",
		accentColor = Color3.fromRGB(226, 26, 46),
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
			{ name = "Flowing Fists", tag = "M1/Primary", summary = "7-hit combo ending in a shockwave.", icon = "rbxassetid://81505553763631", description = "7-hit combo. Hit 3 launches, hit 4 hits all around, the last hit erupts the ground.", videoId = "" },
			{ name = "Qi Charge", tag = "Passive", summary = "At 100 Qi, your next ability is Empowered.", icon = "rbxassetid://135519619953111", description = "Hits and abilities build Qi. At 100, your next ability is Empowered.", videoId = "" },
			{ name = "Hundred Fists", tag = "Skill 1 (E)", summary = "Punch barrage, then a cone blast.", icon = "rbxassetid://74728376681187", description = "Barrage hits everything in front, then a cone blast knocks back. Empowered: more damage, longer cone.", videoId = "" },
			{ name = "Electric Uppercut", tag = "Skill 2 (F)", summary = "Lightning uppercut that launches. 3 charges.", icon = "rbxassetid://90742192763242", description = "3 charges. Dash into an uppercut that launches and shocks. Empowered: lightning chains to more enemies.", videoId = "" },
			{ name = "Ground Slam", tag = "Skill 3 (Q)", summary = "Leap and slam down. Leaves fire.", icon = "rbxassetid://81505553763631", description = "Leap and dive onto the target, hitting along the way. Leaves a burning trail. Empowered: 3 strikes, wider area.", videoId = "" },
			{ name = "Dragon Soul", tag = "Ultimate (R)", summary = "+60% attack speed. A dragon strikes with you.", icon = "rbxassetid://130269422401080", description = "Summon a crimson dragon for 10s: +60% attack speed, and the dragon lashes out along every strike you throw. Empowered: lasts longer, hits harder.", videoId = "" },
		},
		equipment = {
			name = "Ink-Stained Braces & Red Sash",
			slot = "Bare Fists",
			rarity = "Legendary Discipline",
			description = "Red-striped fist braces.",
			stats = {
				["Max Health"] = "140 HP",
				["Qi Charge"] = "100 to Empower",
				["Hundred Fists"] = "2.4x punch",
				["Combo"] = "7 hits",
			},
		},
	},

	["heavy_knight"] = {
		id = "heavy_knight",
		name = "Fire Knight",
		title = "The Infernal Vanguard",
		role = "Bruiser / Vanguard",
		description = "Hits build Heat. Overheat for stronger skills. Burns everything.",
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
			{ name = "Emberblade", tag = "M1/Primary", summary = "4-hit fire combo ending in a slam.", icon = "rbxassetid://16951304645", description = "4-hit combo. The last hit slams and sends out a line of fire.", videoId = "" },
			{ name = "Heat of War", tag = "Passive", summary = "At 100 Heat, Overheat: more fire, no knockback.", icon = "rbxassetid://79763025422259", description = "Hits build Heat. At 100, Overheat: bonus fire damage, burning ground, Empowered skills, no knockback. 5 Scorch stacks make an enemy explode.", videoId = "" },
			{ name = "Fire Tornado", tag = "Skill 1 (E)", summary = "Fire tornado that pulls in and burns.", icon = "rbxassetid://132155579159537", description = "A fire tornado follows you, pulling in and burning enemies, then bursts. Overheated: bigger, longer, burns the ground.", videoId = "" },
			{ name = "Phoenix Slam", tag = "Skill 2 (F)", summary = "Fly up and dive-bomb a spot.", icon = "rbxassetid://91314905448390", description = "Fly up, aim the marker, crash down in an explosion. Leaves burning ground.", videoId = "" },
			{ name = "Infernal Earthshaker", tag = "Skill 3 (Q)", summary = "Ground stab with fire shockwaves.", icon = "rbxassetid://131134579080569", description = "Big explosion, aftershocks and fire patches. Overheated: 3 fire rings.", videoId = "" },
			{ name = "Excalibur", tag = "Ultimate (R)", summary = "Giant fire wave down a line.", icon = "rbxassetid://73181276426858", description = "Charge, then send a fire wave down a long line. Leaves burning ground. Stronger at 75 Heat; at Overheat, uses it all for the biggest wave.", videoId = "" },
		},
		equipment = {
			name = "Emberblade Greatsword",
			slot = "Greatsword",
			rarity = "Infernal Relic",
			description = "Flames grow with every hit.",
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
		description = "Greatsword brawler. Builds Rage to turn into a Beast.",
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
			{ name = "Greatsword", tag = "M1/Primary", summary = "3-hit combo ending in a shockwave.", icon = "rbxassetid://16951304645", description = "3 heavy hits. The last one sends a shockwave.", videoId = "" },
			{ name = "Rupture", tag = "Skill 1 (E)", summary = "Leap and slam. Knocks enemies up.", icon = "rbxassetid://76976244029000", description = "Leap to the cursor (17 studs) and slam, knocking enemies up. Empowered: bigger, plus a spike burst.", videoId = "" },
			{ name = "Bloodstorm", tag = "Skill 2 (F)", summary = "Rapid slashes. 50% less damage taken.", icon = "rbxassetid://103491694383784", description = "Slash in front repeatedly, then a spin that knocks back. Take half damage. Empowered: more and bigger slashes.", videoId = "" },
			{ name = "Crimson Charge", tag = "Skill 3 (Q)", summary = "Unstoppable charge. Empowers next skill.", icon = "rbxassetid://80913065419728", description = "Charge forward, immune. Hits and tosses everything in the path, then bursts. Empowers your next skill.", videoId = "" },
			{ name = "Beast Awakening", tag = "Ultimate (R)", summary = "Become the Beast for 12s.", icon = "rbxassetid://74715237240108", description = "Needs full Rage (hit, kill, take damage). Become the Beast for 12s with new skills: Claws (4-hit combo), Beast Slam (leap, 3 shockwaves), Carnage (3 bleeding swipes), Beast Charge (rush, then throw).", videoId = "" },
		},
		equipment = {
			name = "Ragebringer",
			slot = "Greatsword (Two-Handed)",
			rarity = "Cursed Relic",
			description = "A black greatsword.",
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
		description = "Crowd control caster. Traps groups, teleports, big AoE.",
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
			{ name = "Arcane Bolt", tag = "M1/Primary", summary = "Homing bolts.", icon = "rbxassetid://137276181827966", description = "Bolts home in on the enemy nearest your aim.", videoId = "" },
			{ name = "Arcane Charge", tag = "Passive", summary = "At 100 Charge, your next cast is Empowered.", icon = "rbxassetid://103445564097184", description = "Abilities build Charge: Burst +10, Prison +20, Shift +15, Apocalypse +25. At 100, your next ability is Empowered.", videoId = "" },
			{ name = "Arcane Burst", tag = "Skill 1 (E)", summary = "Pulls enemies in. Leaves a Rune.", icon = "rbxassetid://88301943962437", description = "Explodes on hit, pulls enemies in and leaves a Rune. Empowered: 3 projectiles.", videoId = "" },
			{ name = "Astral Prison", tag = "Skill 2 (F)", summary = "Chain enemies, then explode.", icon = "rbxassetid://75801188793124", description = "A circle chains enemies in place and charges up, then explodes. Detonates Runes inside. Empowered: bigger, pulls in, faster.", videoId = "" },
			{ name = "Arcane Shift", tag = "Skill 3 (Q)", summary = "Teleport. Leaves an Echo that copies your next spell.", icon = "rbxassetid://124123608046140", description = "Teleport to the target (untargetable) with a shockwave. Your Echo repeats your next ability at reduced power. Empowered: 3 Echoes.", videoId = "" },
			{ name = "Apocalypse", tag = "Ultimate (R)", summary = "Mark all enemies, rain bolts, detonate.", icon = "rbxassetid://102883539726716", description = "Mark every enemy in a large radius, rain bolts on them, then all marks explode.", videoId = "" },
		},
		equipment = {
			name = "Codex of the Unbroken Sky & Astral Robes",
			slot = "Floating Grimoire",
			rarity = "Mythic Arcana",
			description = "A floating spellbook.",
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
		description = "Mobile assassin. Mark, vanish, strike from behind.",
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
			{ name = "Shadow Dagger", tag = "Skill 1 (E)", summary = "Throw a dagger. Recast to teleport behind the target.", icon = "rbxassetid://76025835812755", description = "Marks the first enemy hit. Press again to teleport behind it for bonus damage. Works while invisible.", videoId = "" },
			{ name = "Dash", tag = "Skill 2 (F)", summary = "Dash through enemies and Mark them.", icon = "rbxassetid://126886113502981", description = "Dash in the aimed direction, hitting and Marking every enemy on the way.", videoId = "" },
			{ name = "Invisibility", tag = "Skill 3 (Q)", summary = "Go invisible for 6s. Faster movement and cooldowns.", icon = "rbxassetid://96103077837816", description = "Invisible for 6s and move faster. Ends early if you attack or get hit.", videoId = "" },
			{ name = "Shadow Execution", tag = "Ultimate (R)", summary = "Smoke bomb. Hits everything inside, detonates Marks.", icon = "rbxassetid://90722823590745", description = "Vanish in smoke. Every enemy inside is hit and Marked, then you reappear and detonate all Marks.", videoId = "" },
		},
		equipment = {
			name = "Shadowfang & Crimson Cowl",
			slot = "Dagger & Hood",
			rarity = "Shadow Relic",
			description = "A dagger that drinks from the shadows.",
			stats = {
				["Max Health"] = "95 HP",
				["Marked Damage"] = "+25%",
				["Speed after a kill"] = "+25%",
				["Cooldowns while invisible"] = "x2 speed",
			},
		},
	},

	["summoner"] = {
		id = "summoner",
		name = "Summoner",
		title = "The Beastcaller",
		role = "Summons / Control",
		description = "Summons 3 beasts: a golem, a hawk and a healing stag.",
		accentColor = Color3.fromRGB(130, 215, 255),
		stats = {
			strength = 3,
			vitality = 3,
			defense = 2,
			agility = 3,
			maxHealth = 110,
			offense = 4,
			difficulty = 3,
		},
		abilities = {
			{ name = "Bond Bolt", tag = "M1/Primary", summary = "Bolts. Your beasts attack what you hit.", icon = "rbxassetid://137276181827966", description = "The enemy you hit becomes every beast's target.", videoId = "" },
			{ name = "Pack Bond", tag = "Passive", summary = "+12% beast damage per other beast out.", icon = "rbxassetid://103445564097184", description = "Beasts fight on their own. Each other beast out gives all of them +12% damage.", videoId = "" },
			{ name = "Rockborn", tag = "Skill 1 (E)", summary = "Lava golem tank. Recast: Ground Slam.", icon = "rbxassetid://131134579080569", description = "Summon a golem where you aim. It taunts and punches. Press again: it leaps to the cursor and slams, leaving lava cracks.", videoId = "" },
			{ name = "Skyfeather", tag = "Skill 2 (F)", summary = "Ranged hawk. Recast: Wind Circle.", icon = "rbxassetid://85167837069373", description = "Summon a hawk that shoots feathers and dives on enemies. Press again: a cyclone at the cursor pulls enemies in, then bursts.", videoId = "" },
			{ name = "Lunari", tag = "Skill 3 (Q)", summary = "Healing stag. Recast: Radiant Bloom.", icon = "rbxassetid://83970690874192", description = "Summon a stag that heals the party and tramples enemies. Press again: it stomps at the cursor, healing the party and stunning enemies.", videoId = "" },
			{ name = "Divine Cataclysm", tag = "Ultimate (R)", summary = "Fuse all beasts into one giant attack.", icon = "rbxassetid://102883539726716", description = "Your beasts fuse into the Skyrockorn. It rains fire, hits every enemy with rays, then crashes down. The beasts return after.", videoId = "" },
		},
		equipment = {
			name = "Bondgauntlet",
			slot = "Gauntlet",
			rarity = "Bond Relic",
			description = "A rune gauntlet with a stone for each beast.",
			stats = {
				["Max Health"] = "110 HP",
				["Beasts"] = "3 + the fusion",
				["Pack Bond"] = "+12% per beast",
				["Summon Time"] = "16 s",
			},
		},
	},

	["death_knight"] = {
		id = "death_knight",
		name = "Death Knight",
		title = "The Soul Reaper",
		role = "Bruiser / Control",
		description = "Heavy greatsword knight. Chains enemies in, builds Dread.",
		accentColor = Color3.fromRGB(112, 201, 245),
		stats = {
			strength = 5,
			vitality = 5,
			defense = 4,
			agility = 2,
			maxHealth = 280,
			offense = 4,
			difficulty = 3,
		},
		abilities = {
			{ name = "Graveblade", tag = "M1/Primary", summary = "3-hit combo ending in a slam.", icon = "rbxassetid://16951304645", description = "3 heavy hits. The last one bursts into mist.", videoId = "" },
			{ name = "Dread", tag = "Passive", summary = "At 100 Dread: +20% damage, bigger skills.", icon = "rbxassetid://103445564097184", description = "Hits and kills build Dread. At 100, Dreadforged for 8s: +20% damage, swings send shockwaves, bigger skills.", videoId = "" },
			{ name = "Blackwake", tag = "Skill 1 (E)", summary = "Wide swing that sends a smoke wave.", icon = "rbxassetid://103491694383784", description = "A smoke wave rolls forward, hitting and pushing enemies. Dreadforged: wider, plus a second wave.", videoId = "" },
			{ name = "Doomfall", tag = "Skill 2 (F)", summary = "Leap and slam. Leaves damaging mist.", icon = "rbxassetid://76976244029000", description = "Leap and slam at the cursor. Leaves mist that damages enemies. Dreadforged: bigger, stronger mist.", videoId = "" },
			{ name = "Grave Reversal", tag = "Skill 3 (Q)", summary = "Chain an enemy, slam it twice.", icon = "rbxassetid://80913065419728", description = "Chain the first enemy hit, slam it behind you, pull it back and slam it again. Bosses don't move but take both hits.", videoId = "" },
			{ name = "King of the Grave", tag = "Ultimate (R)", summary = "Bind every enemy nearby, then hit them all.", icon = "rbxassetid://74715237240108", description = "Chains bind every enemy nearby. Giant blades sweep the area, then a final blast.", videoId = "" },
		},
		equipment = {
			name = "The Graveblade & Soul Reaper Plate",
			slot = "Greatsword (Two-Handed)",
			rarity = "Grave Relic",
			description = "A chained greatsword.",
			stats = {
				["Max Health"] = "280 HP",
				["Dread"] = "0 – 100",
				["Dreadforged"] = "8 s",
				["Grave Reversal"] = "2 slams, behind and in front",
			},
		},
	},

	["ronin"] = {
		id = "ronin",
		name = "Ronin",
		title = "The Severing Edge",
		role = "Duelist / Burst",
		description = "Fast katana fighter. Every skill is a draw from the scabbard.",
		accentColor = Color3.fromRGB(150, 225, 255),
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
			{ name = "Edge", tag = "M1/Primary", summary = "3 quick cuts. You keep moving.", icon = "rbxassetid://16951304645", description = "Two flat cuts and a rising finisher.", videoId = "" },
			{ name = "Distant Cut", tag = "Skill 1 (E)", summary = "Cuts land on the cursor.", icon = "rbxassetid://103491694383784", description = "A quick draw. A sphere of cuts hits at the cursor when the blade clicks home.", videoId = "" },
			{ name = "Rising Cut", tag = "Skill 2 (F)", summary = "Upward draw. Launches enemies.", icon = "rbxassetid://76976244029000", description = "A low draw sweeping straight up through what's in front.", videoId = "" },
			{ name = "Falling Heaven", tag = "Skill 3 (Q)", summary = "Air cuts, then a flip and a slam.", icon = "rbxassetid://80913065419728", description = "Leap, cut twice and spin, then flip into a downward cut that slams the area.", videoId = "" },
			{ name = "Thousand Cuts", tag = "Ultimate (R)", summary = "A storm of cuts. All land on the click.", icon = "rbxassetid://74715237240108", description = "Stillness, a held draw, a storm of cuts. Every cut lands when the blade is sheathed.", videoId = "" },
		},
		equipment = {
			name = "The Severing Edge",
			slot = "Katana & Scabbard",
			rarity = "Blade Relic",
			description = "A katana, always sheathed between cuts.",
			stats = {
				["Max Health"] = "150 HP",
				["Distant Cut"] = "Up to 40 studs",
				["Thousand Cuts"] = "30 stud radius",
			},
		},
	},

	["cleric"] = {
		id = "cleric",
		name = "Cleric",
		title = "The Radiant Herald",
		role = "Support / Healer",
		description = "Heals and cleanses the party.",
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
			{ name = "Radiant Smite", tag = "M1/Primary", summary = "Damages enemies, heals allies.", icon = "rbxassetid://1053548563", description = "A beam that damages enemies and heals allies.", videoId = "" },
			{ name = "Sanctuary Circle", tag = "Skill 1 (E)", summary = "Healing zone.", icon = "rbxassetid://83970690874192", description = "A circle that heals allies inside.", videoId = "" },
			{ name = "Divine Ward", tag = "Skill 2 (F)", summary = "Shield that removes stuns.", icon = "rbxassetid://79167595723607", description = "Shield yourself or an ally and remove crowd control.", videoId = "" },
			{ name = "Heavenly Grace", tag = "Ultimate (R)", summary = "Full party heal. Blinds enemies.", icon = "rbxassetid://85719690091163", description = "Fully heals the party and blinds enemies.", videoId = "" },
		},
		equipment = {
			name = "Sunfire Scepter & Radiant Scripture",
			slot = "Main Hand Scepter",
			rarity = "Sacred Relic",
			description = "Pulses cleanse party debuffs.",
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
		description = "Ranged poison archer. Roots and poison clouds.",
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
			{ name = "Venom Arrows", tag = "M1/Primary", summary = "Poison arrows.", icon = "rbxassetid://71390904975203", description = "Fast arrows that poison.", videoId = "" },
			{ name = "Verdant Slash", tag = "Skill 1 (E)", summary = "Dash through enemies.", icon = "rbxassetid://71390904975203", description = "Dash forward, hitting every enemy in the path.", videoId = "" },
			{ name = "Entangling Arrow", tag = "Skill 2 (F)", summary = "Arrow that roots enemies.", icon = "rbxassetid://116665007054306", description = "Bursts into vines that root enemies.", videoId = "" },
			{ name = "Toxic Cloud", tag = "Skill 3 (Q)", summary = "Poison cloud.", icon = "rbxassetid://94605725583145", description = "Leaves a poison cloud on the ground.", videoId = "" },
			{ name = "Rain of Arrows", tag = "Ultimate (R)", summary = "Giant plant: arrow rain, poison, knockback.", icon = "rbxassetid://123385594261124", description = "Summon a giant plant. It rains arrows, pulls enemies in, poisons them and knocks back any that get close.", videoId = "" },
		},
		equipment = {
			name = "Elderthorn Bow & Venomseed Quiver",
			slot = "Two-Handed Bow",
			rarity = "Ancient Druid Relic",
			description = "A living bow.",
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
		description = "Revolver burst. Builds Deadeye for crits and ricochets.",
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
			{ name = "Six Shooter", tag = "M1/Primary", summary = "6 shots. The 6th crits.", icon = "rbxassetid://94409821434570", description = "6 shots, then reload. The 6th hits hardest.", videoId = "" },
			{ name = "Deadeye", tag = "Passive", summary = "Full Deadeye: next shot pierces and crits.", icon = "rbxassetid://115132974561524", description = "Hits in a row fill Deadeye. When full, your next hit pierces and crits.", videoId = "" },
			{ name = "Fan the Hammer", tag = "Skill 1 (E)", summary = "Fire all remaining shots.", icon = "rbxassetid://94409821434570", description = "Fire every remaining bullet in a short-range burst.", videoId = "" },
			{ name = "Gunslinger's Roll", tag = "Skill 2 (F)", summary = "Roll, stun, shoot.", icon = "rbxassetid://132307778799944", description = "Invulnerable roll. Drops a flashbang that stuns (not bosses), then shoots at the cursor.", videoId = "" },
			{ name = "Deadeye Ricochet", tag = "Skill 3 (Q)", summary = "Shoot a coin to hit every enemy.", icon = "rbxassetid://74725489937058", description = "Toss a coin. Shoot it to ricochet into every enemy in the room.", videoId = "" },
			{ name = "High Noon", tag = "Ultimate (R)", summary = "Slow time, shoot every enemy.", icon = "rbxassetid://73749330909862", description = "Slow time, shoot every enemy in the room, then a Deadeye finisher.", videoId = "" },
		},
		equipment = {
			name = "The Last Word & Outlaw's Coat",
			slot = "Engraved Revolver",
			rarity = "Outlaw Relic",
			description = "An engraved six-shooter.",
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
		description = "Fast rapier duelist. Combos, dashes and parries.",
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
			{ name = "Rapier Combo", tag = "M1/Primary", summary = "4-hit combo. Builds Momentum.", icon = "rbxassetid://81023610019830", description = "4-hit combo. The last hit lunges forward.", videoId = "" },
			{ name = "Battle Momentum", tag = "Passive", summary = "Hits build Momentum for faster attacks.", icon = "rbxassetid://138073571091241", description = "Hits build Momentum (max 10) for faster attacks. At 10, your next ability is Empowered.", videoId = "" },
			{ name = "Sword Rush", tag = "Skill 1 (E)", summary = "Dash with 2 hits.", icon = "rbxassetid://81023610019830", description = "Dash with 2 strikes. Enemies hit by both take extra damage.", videoId = "" },
			{ name = "Parry", tag = "Skill 2 (F)", summary = "Block a hit, stun, counter.", icon = "rbxassetid://135280785520672", description = "Block an attack, stun the attacker and counter.", videoId = "" },
			{ name = "Piercing Judgement", tag = "Skill 3 (Q)", summary = "Charge, then a piercing lunge.", icon = "rbxassetid://84667638225077", description = "Hold to charge, release to lunge through a line. Longer charge = longer, stronger. Extra projectiles add echoes.", videoId = "" },
			{ name = "Blade Storm", tag = "Ultimate (R)", summary = "Slash every enemy in the room.", icon = "rbxassetid://88484267696144", description = "Slow time, hit every enemy in the room (8+ hits), then a finisher that hits the whole room.", videoId = "" },
		},
		equipment = {
			name = "Dawnsteel Longsword",
			slot = "Longsword",
			rarity = "Duelist Relic",
			description = "A gold-guard rapier.",
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
		description = "Frost caster. Freezes and roots enemies.",
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
			{ name = "Ice Crystal", tag = "M1/Primary", summary = "Ice shards that Chill.", icon = "rbxassetid://110861546175994", description = "Shatters on the first enemy hit.", videoId = "" },
			{ name = "Ice Spikes", tag = "Skill 1 (E)", summary = "Line of spikes that freeze.", icon = "rbxassetid://110861546175994", description = "Spikes erupt in a line, freezing everything they hit.", videoId = "" },
			{ name = "Ice Beam", tag = "Skill 2 (F)", summary = "Beam that freezes.", icon = "rbxassetid://85167837069373", description = "A beam that freezes the first enemy it hits.", videoId = "" },
			{ name = "Ice Clone", tag = "Skill 3 (Q)", summary = "Decoy that taunts, then freezes.", icon = "rbxassetid://122144064327132", description = "A clone taunts enemies, then explodes and freezes them.", videoId = "" },
			{ name = "Blizzard", tag = "Ultimate (R)", summary = "Blizzard that freezes the room.", icon = "rbxassetid://76962430268191", description = "A blizzard that freezes and damages everything in the area.", videoId = "" },
		},
		equipment = {
			name = "Glacial Frostcore Orb & Permafrost Robes",
			slot = "Off-Hand Relic Orb",
			rarity = "Frozen Relic",
			description = "A floating ice orb.",
			stats = {
				["Max Health"] = "100 HP",
				["Frost Slow Effect"] = "+30%",
				["Freeze Duration"] = "+1.5s",
				["Spell Area"] = "+35%",
			},
		},
	},
}

-- What class select shows beside the model: tagline, role tags, the five
-- 0–100 ratings (damage, survivability, mobility, range, difficulty), an
-- emblem and the aura's second colour.
local DISPLAY: { [string]: { tagline: string, roles: { string }, ratings: { number }, emblem: string, glowColor: Color3 } } = {
	heavy_knight = { tagline = "The Infernal Vanguard", roles = { "Bruiser", "Vanguard" }, ratings = { 90, 85, 45, 30, 65 }, emblem = "✹", glowColor = Color3.fromRGB(255, 200, 80) },
	rogue = { tagline = "The Shadow", roles = { "Assassin", "Burst" }, ratings = { 85, 35, 95, 40, 80 }, emblem = "☾", glowColor = Color3.fromRGB(90, 30, 120) },
	mage = { tagline = "The Arcanist", roles = { "Caster", "Control" }, ratings = { 80, 35, 55, 85, 75 }, emblem = "✧", glowColor = Color3.fromRGB(110, 200, 255) },
	martial_artist = { tagline = "The Crimson Fist", roles = { "Brawler", "Burst" }, ratings = { 85, 55, 90, 35, 60 }, emblem = "☯", glowColor = Color3.fromRGB(255, 220, 120) },
	summoner = { tagline = "The Beastcaller", roles = { "Summoner", "Control" }, ratings = { 70, 55, 50, 80, 60 }, emblem = "❂", glowColor = Color3.fromRGB(170, 255, 200) },
	death_knight = { tagline = "The Soul Reaper", roles = { "Bruiser", "Control" }, ratings = { 85, 90, 35, 40, 60 }, emblem = "✠", glowColor = Color3.fromRGB(40, 70, 110) },
	ronin = { tagline = "The Severing Edge", roles = { "Duelist", "Burst" }, ratings = { 90, 50, 85, 55, 70 }, emblem = "⚔", glowColor = Color3.fromRGB(20, 26, 40) },
	ranger = { tagline = "The Verdant Venom", roles = { "Marksman", "Control" }, ratings = { 75, 45, 80, 95, 55 }, emblem = "❦", glowColor = Color3.fromRGB(190, 255, 90) },
	cleric = { tagline = "The Radiant Herald", roles = { "Support", "Healer" }, ratings = { 40, 75, 40, 70, 35 }, emblem = "☀", glowColor = Color3.fromRGB(255, 250, 220) },
	ice_mage = { tagline = "The Cryo Sorceress", roles = { "Caster", "Frost" }, ratings = { 75, 50, 40, 85, 60 }, emblem = "❄", glowColor = Color3.fromRGB(220, 250, 255) },
	gunslinger = { tagline = "The Deadeye Outlaw", roles = { "Marksman", "Burst" }, ratings = { 85, 35, 80, 90, 90 }, emblem = "✪", glowColor = Color3.fromRGB(255, 240, 190) },
	swordsman = { tagline = "The Blade Dancer", roles = { "Duelist", "Skirmisher" }, ratings = { 85, 50, 90, 35, 65 }, emblem = "⚜", glowColor = Color3.fromRGB(255, 255, 235) },
	berserker = { tagline = "The Crimson Ravager", roles = { "Bruiser", "Slayer" }, ratings = { 95, 75, 55, 30, 40 }, emblem = "☠", glowColor = Color3.fromRGB(255, 90, 60) },
}
for id, d in pairs(DISPLAY) do
	local info = ClassData[id]
	if info then
		info.tagline = d.tagline
		info.roles = d.roles
		info.ratings = { damage = d.ratings[1], survivability = d.ratings[2], mobility = d.ratings[3], range = d.ratings[4], difficulty = d.ratings[5] }
		info.emblem = d.emblem
		info.glowColor = d.glowColor
	end
end

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
	summoner = true,
	death_knight = true,
	ronin = true,
}

-- Array order for Carousel / UI display: playable classes first, locked after.
local ClassOrder: { string } = {
	"heavy_knight",
	"rogue",
	"mage",
	"martial_artist",
	"summoner",
	"death_knight",
	"ronin",
	"ranger",
	"cleric",
	"ice_mage",
	"gunslinger",
	"swordsman",
	"berserker",
}

-- Every new profile owns these; every other class is unlocked at the Altar of
-- Souls (GachaManager) and stays unlocked for good.
local StarterClasses: { string } = { "ranger", "swordsman", "cleric", "mage", "rogue" }

return {
	Classes = ClassData,
	Order = ClassOrder,
	Starter = StarterClasses,
	-- Whether `player` may play `classId`: a finished kit they own. The server
	-- keeps "OwnedClasses" (",id,id,") on the player (GachaManager) and
	-- ClassManager refuses anything else.
	IsOwnedBy = function(player: Player, id: string): boolean
		if PlayableClasses[id] ~= true then return false end
		local owned = player:GetAttribute("OwnedClasses")
		if typeof(owned) ~= "string" then return table.find(StarterClasses, id) ~= nil end
		return string.find(owned, "," .. id .. ",", 1, true) ~= nil
	end,
	GetClass = function(id: string): ClassInfo?
		return ClassData[id]
	end,
	IsPlayable = function(id: string): boolean
		return PlayableClasses[id] == true
	end,
}
