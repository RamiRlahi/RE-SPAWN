--[[
	SkillData.luau
	Shared configuration for class skills, stats, cooldowns, and visual parameters.
--]]

export type SkillConfig = {
	name: string,
	slot: number,
	keybind: string,
	cooldown: number,
	damage: number,
	description: string,
	hint: string?, -- one sentence, for the skill bar's hover tip (TIPS below)
	tomes: { string }?, -- tome ids that work well with it (TIPS below)
	animationId: string?,
	slashAnimationId: string?,
	range: number?,
	angle: number?,
	projectileSpeed: number?,
	dashDistance: number?,
	dashSpeed: number?,
	duration: number?,
	width: number?,
	radius: number?,
}

export type ClassSkills = {
	[number]: SkillConfig
}

local SkillData: { [string]: ClassSkills } = {
	ranger = {
		[1] = {
			name = "Verdant Slash",
			slot = 1,
			keybind = "E",
			cooldown = 5.0,
			damage = 38,
			range = 32,
			dashDistance = 32,
			width = 6.0,
			description = "Dash forward, hitting every enemy in the path.",
			animationId = "rbxassetid://139832137467263",
		},
		[2] = {
			name = "Entangling Arrow",
			slot = 2,
			keybind = "F",
			cooldown = 10.0,
			damage = 30,
			range = 44,
			duration = 2.6,
			description = "Arrow that roots enemies in a small area.",
		},
		[3] = {
			name = "Seeker Barrage",
			slot = 3,
			keybind = "Q",
			cooldown = 12.0,
			damage = 35,
			duration = 8.0,
			description = "For 8s, every attack also fires homing missiles.",
		},
		[4] = {
			name = "Rain of Arrows",
			slot = 4,
			keybind = "R",
			cooldown = 30.0,
			damage = 24,
			range = 42,
			duration = 4.0,
			description = "Ultimate: summon a giant plant. It rains arrows on a large area, taunts and poisons enemies, and knocks back any that get close.",
		},
	},
	-- The Fire Knight (class id kept as heavy_knight; FireKnightServer).
	heavy_knight = {
		[1] = {
			name = "Fire Tornado",
			slot = 1,
			keybind = "E",
			cooldown = 9.0,
			damage = 40, -- each tick inside hits for 32% of this, the burst at the end for 160%
			description = "A fire tornado follows you, pulling in and Scorching enemies, then bursts. Overheated: bigger, longer, burns the ground.",
		},
		[2] = {
			name = "Phoenix Slam",
			slot = 2,
			keybind = "F",
			cooldown = 9.0,
			damage = 90, -- the impact (Overheated: flares go off round it too)
			range = 40, -- how far from where you take off you can land
			description = "Fly up, aim the marker, click (or F) to dive. Explodes and burns the ground. Overheated: bigger, more explosions.",
		},
		[3] = {
			name = "Infernal Earthshaker",
			slot = 3,
			keybind = "Q",
			cooldown = 11.0,
			damage = 70,
			range = 14,
			description = "Big explosion, aftershocks and fire patches. Overheated: 3 fire rings.",
		},
		[4] = {
			name = "Excalibur",
			slot = 4,
			keybind = "R",
			cooldown = 40.0,
			damage = 150,
			description = "Ultimate: a fire wave down a long line. Leaves burning ground. Stronger at 75 Heat; at Overheat, uses it all for the biggest wave.",
		},
	},
}

-- The Berserker, the Crimson Ravager (BerserkerServer).
SkillData.berserker = {
	[1] = {
		name = "Rupture",
		slot = 1,
		keybind = "E",
		cooldown = 8.0,
		damage = 75,
		range = 14,
		description = "Leap to the cursor (17 studs) and slam, knocking enemies up.",
	},
	[2] = {
		name = "Bloodstorm",
		slot = 2,
		keybind = "F",
		cooldown = 10.0,
		damage = 30,
		range = 30,
		description = "Slash in front repeatedly, then a spin that knocks back. Take half damage.",
	},
	[3] = {
		name = "Crimson Charge",
		slot = 3,
		keybind = "Q",
		cooldown = 12.0,
		damage = 40,
		range = 28,
		description = "Charge forward, immune. Hits and tosses everything in the path, then bursts. Empowers your next skill.",
	},
	[4] = {
		name = "Beast Awakening",
		slot = 4,
		keybind = "R",
		cooldown = 4.0, -- (it needs a full Rage meter: that's the real wait)
		damage = 160,
		duration = 12,
		description = "Ultimate (full Rage): become the Beast for 12s. New skills, more damage, 2x faster cooldowns.",
	},
}

SkillData.cleric = {
	[1] = {
		name = "Heal",
		slot = 1,
		keybind = "E",
		cooldown = 3.0,
		damage = 0,
		healAmount = 70,
		maxCharges = 3,
		description = "Homing bolt that heals the lowest ally. 3 charges.",
	},
	[2] = {
		name = "Divine Beam",
		slot = 2,
		keybind = "F",
		cooldown = 15.0,
		damage = 190, -- over the whole channel
		range = 60,
		width = 4.5,
		duration = 5.0,
		description = "Beam that deals heavy damage in a line.",
	},
	[3] = {
		name = "Radiant Ground",
		slot = 3,
		keybind = "Q",
		cooldown = 20.0,
		damage = 16,
		range = 16,
		duration = 5.0,
		healAmount = 12,
		description = "Heals allies over time and removes debuffs.",
	},
	[4] = {
		name = "Divine Ascent",
		slot = 4,
		keybind = "R",
		cooldown = 60.0,
		damage = 160,
		range = 30,
		duration = 2.0, -- length of the ascension cinematic
		reviveTime = 1.2, -- the revival beat of the cinematic (DivineAscentCutscene.REVIVE_AT)
		healAmount = 100,
		description = "Ultimate: revive fallen allies, heal and cleanse the party, damage nearby enemies.",
	},
}

SkillData.ice_mage = {
	[1] = {
		name = "Ice Spikes",
		slot = 1,
		keybind = "E",
		cooldown = 6.0,
		damage = 45,
		range = 42,
		width = 4.0,
		projectileSpeed = 95, -- how fast the spike line races across the floor (studs/s)
		castDelay = 0.16, -- palm-slam frame of the cast pose; spikes + damage start here
		description = "Spikes erupt in a line, freezing everything they hit.",
	},
	[2] = {
		name = "Ice Beam",
		slot = 2,
		keybind = "F",
		cooldown = 10.0,
		damage = 120,
		range = 55,
		width = 3.0,
		duration = 3.0,
		description = "A beam that freezes and damages the first enemy hit.",
	},
	[3] = {
		name = "Ice Clone",
		slot = 3,
		keybind = "Q",
		cooldown = 18.0,
		damage = 60,
		range = 34, -- taunt radius
		duration = 10.0,
		cloneHealth = 50,
		castDelay = 0.2, -- clone forms as the cast pose flings the crystal
		explosionRadius = 14,
		description = "A clone (50 HP) taunts enemies. Explodes and freezes when destroyed.",
	},
	[4] = {
		name = "Blizzard",
		slot = 4,
		keybind = "R",
		cooldown = 45.0,
		damage = 200,
		range = 48,
		duration = 6.0,
		castDelay = 1.5, -- "frozen one" reveal close-up; the storm breaks as it cuts back
		description = "Ultimate: a blizzard that freezes and damages every enemy inside.",
	},
}

SkillData.gunslinger = {
	[1] = {
		name = "Fan the Hammer",
		slot = 1,
		keybind = "E",
		cooldown = 6.0,
		damage = 18, -- per bullet; fires every bullet left in the cylinder
		range = 34,
		description = "Fire every remaining bullet in a short-range burst.",
	},
	[2] = {
		name = "Gunslinger's Roll",
		slot = 2,
		keybind = "F",
		cooldown = 3.2,
		damage = 0,
		dashDistance = 15,
		duration = 0.26, -- roll time; i-frames last a little longer
		description = "Invulnerable roll. Drops a flashbang that stuns (not bosses), then shoots at the cursor.",
	},
	[3] = {
		name = "Deadeye Ricochet",
		slot = 3,
		keybind = "Q",
		cooldown = 7.0,
		damage = 26, -- per ricochet projectile
		range = 24, -- coin throw distance
		duration = 2.6, -- how long the coin hangs in the air
		description = "Toss a coin. Shoot it to ricochet into every enemy in the room.",
	},
	[4] = {
		name = "High Noon",
		slot = 4,
		keybind = "R",
		cooldown = 40.0,
		damage = 165, -- per marked target (×3 of the old 55); the execution shot deals far more
		range = 50,
		duration = 3.7, -- standoff + volley + execution (mobs are frozen through it)
		description = "Ultimate: slow time and shoot every enemy in the room.",
	},
}

SkillData.swordsman = {
	[1] = {
		name = "Sword Rush",
		slot = 1,
		keybind = "E",
		cooldown = 6.0, -- per charge
		charges = 3, -- up to three rushes back to back; each recharges in `cooldown`
		damage = 30, -- per strike; the second strike is stronger on enemies hit by both
		dashDistance = 20,
		width = 6.0,
		description = "Dash with 2 strikes. Enemies hit by both take extra damage. Empowered: longer, wider, 3rd strike.",
	},
	[2] = {
		name = "Parry",
		slot = 2,
		keybind = "F",
		cooldown = 8.0,
		damage = 90, -- the riposte's pommel strike
		duration = 1.2, -- parry window (the guard's flourish; nothing else can be cast over it)
		range = 14,
		description = "Block an attack, stun the attacker and counter. Empowered: longer window, harder counter.",
	},
	[3] = {
		name = "Piercing Judgement",
		slot = 3,
		keybind = "Q",
		cooldown = 7.0,
		damage = 45, -- the thrust uncharged (x3 fully charged); each phantom echo deals 60%
		width = 3.5,
		-- (held to charge: the line, lunge and timings are SwordsmanServer's JUDGE)
		description = "Hold to charge, release to lunge through a line. Longer charge = longer, stronger. Extra projectiles add echoes. Empowered: faster charge, +2 echoes.",
	},
	[4] = {
		name = "Blade Storm",
		slot = 4,
		keybind = "R",
		cooldown = 35.0,
		damage = 60, -- per dash slash; the final X deals far more
		range = 45,
		description = "Ultimate: slow time, hit every enemy in the room (8+ hits), then a finisher on the whole room.",
	},
}

SkillData.rogue = {
	[1] = {
		name = "Shadow Dagger",
		slot = 1,
		keybind = "E",
		cooldown = 6.0,
		damage = 34,
		range = 75, -- how far the dagger flies
		projectileSpeed = 150,
		duration = 4.0, -- how long the dagger waits to be stepped to
		description = "Marks the first enemy hit. Press again to teleport behind it for bonus damage. Works while invisible.",
	},
	[2] = {
		name = "Dash",
		slot = 2,
		keybind = "F",
		cooldown = 8.0, -- per charge
		charges = 4, -- up to four dashes back to back; each recharges in `cooldown`
		damage = 30,
		dashDistance = 22,
		width = 5,
		description = "Dash, hitting and Marking every enemy on the way. 4 charges.",
	},
	[3] = {
		name = "Invisibility",
		slot = 3,
		keybind = "Q",
		cooldown = 20.0,
		damage = 0,
		duration = 6.0,
		description = "Invisible for 6s and move faster. Ends early if you attack or get hit.",
	},
	[4] = {
		name = "Shadow Execution",
		slot = 4,
		keybind = "R",
		cooldown = 60.0,
		damage = 40, -- per slash (five, through every enemy in the smoke); each leaves a mark that detonates for 1.5x; the final strike deals 3x
		range = 24,
		description = "Ultimate: vanish in smoke. Hit every enemy inside 5 times, then detonate all Marks.",
	},
}

SkillData.mage = {
	[1] = {
		name = "Arcane Burst",
		slot = 1,
		keybind = "E",
		cooldown = 6.0,
		damage = 45,
		range = 60, -- how far the projectile flies (to the cursor)
		projectileSpeed = 95,
		radius = 10, -- the explosion; everything within 1.4x is pulled to its centre
		description = "Explodes on hit, pulls enemies in and leaves a Rune. Empowered: 3 projectiles.",
	},
	[2] = {
		name = "Astral Prison",
		slot = 2,
		keybind = "F",
		cooldown = 12.0,
		damage = 70, -- the collapse (up to 2.5x for those held the whole time); the chains squeeze for 10% twice a second
		range = 45,
		radius = 12,
		duration = 3.0, -- how long the chains hold before the collapse
		description = "A circle chains enemies in place and charges up, then explodes. Detonates Runes inside. Empowered: bigger, pulls in, faster.",
	},
	[3] = {
		name = "Arcane Shift",
		slot = 3,
		keybind = "Q",
		cooldown = 9.0,
		damage = 35, -- the shockwave where you reappear
		range = 30,
		radius = 10,
		description = "Teleport to the target (untargetable) with a shockwave. Your Echo repeats your next ability at reduced power. Empowered: 3 Echoes.",
	},
	[4] = {
		name = "Apocalypse",
		slot = 4,
		keybind = "R",
		cooldown = 70.0,
		damage = 26, -- per falling bolt; every mark detonates for 6x
		radius = 45,
		description = "Ultimate: mark every enemy in a large radius, rain bolts, then all marks explode.",
	},
}

SkillData.martial_artist = {
	[1] = {
		name = "Hundred Fists",
		slot = 1,
		keybind = "E",
		cooldown = 7.0,
		damage = 70, -- each barrage blow 0.2x (about 11 of them), the power punch 2.4x
		range = 9,
		description = "Barrage hits and holds everything in front, then a cone blast knocks back. Empowered: more damage, longer cone.",
	},
	[2] = {
		name = "Electric Uppercut",
		slot = 2,
		keybind = "F",
		cooldown = 8.0, -- per charge
		charges = 3, -- up to three uppercuts back to back; each recharges in `cooldown`
		damage = 65,
		range = 7,
		description = "3 charges. Dash into an uppercut that launches and shocks. Empowered and extra projectiles: chains to more enemies.",
	},
	[3] = {
		name = "Haymaker",
		slot = 3,
		keybind = "Q",
		cooldown = 9.0,
		damage = 80, -- the wave, up to 3.2x fully charged; each glassy arc behind it 0.45x
		range = 30, -- the lane at full charge (12 uncharged)
		description = "Hold to charge, release a haymaker that drives a wave down a lane. The longer the charge, the longer the lane and the harder the hit; arcs burst up along it. Empowered: faster charge, longer, harder.",
	},
	[4] = {
		name = "Dragon Soul",
		slot = 4,
		keybind = "R",
		cooldown = 60.0,
		damage = 160, -- the roar round him as the dragon bursts out (Size grows it)
		duration = 10, -- seconds of haste (Empowered: 1.4x)
		range = 15, -- how far the dragon lashes along each strike (grows with Size)
		description = "Ultimate: summon a crimson dragon for 10s. +60% attack speed, and the dragon lashes out with every strike.",
	},
}

-- The Summoner, the Beastcaller (SummonerServer; the beasts' tuning is
-- SummonerData). E / F / Q call a beast for `duration` seconds; pressed
-- again while it's out, it makes its signature move (sigDamage) on its own
-- short recharge, the skill's cooldown untouched.
SkillData.summoner = {
	[1] = {
		name = "Rockborn",
		slot = 1,
		keybind = "E",
		cooldown = 20.0,
		damage = 60, -- the meteor it lands as
		sigDamage = 120, -- Ground Slam (each fissure 50%)
		range = 30,
		duration = 16,
		description = "Summon a golem where you aim. It taunts and punches. Recast: it leaps to the cursor and slams, leaving lava cracks.",
	},
	[2] = {
		name = "Skyfeather",
		slot = 2,
		keybind = "F",
		cooldown = 20.0,
		damage = 30, -- the dive it arrives in
		sigDamage = 55, -- Wind Circle's burst (the cyclone cuts for 11 a tick)
		range = 30,
		duration = 16,
		description = "Summon a hawk that shoots feathers and dives on enemies. Recast: a cyclone at the cursor pulls enemies in, then bursts.",
	},
	[3] = {
		name = "Lunari",
		slot = 3,
		keybind = "Q",
		cooldown = 22.0,
		damage = 0,
		sigDamage = 80, -- Radiant Bloom (and it heals the party 25%)
		range = 24,
		duration = 16,
		description = "Summon a stag that heals the party and tramples enemies. Recast: it stomps, healing the party and stunning enemies.",
	},
	[4] = {
		name = "Divine Cataclysm",
		slot = 4,
		keybind = "R",
		cooldown = 60.0,
		damage = 260, -- the crash; the starfire hits for 30, the judgement rays for 22
		description = "Ultimate: your beasts fuse into the Skyrockorn. It rains fire, hits every enemy with rays, then crashes down.",
	},
}

-- The Death Knight, the Soul Reaper (DeathKnightServer). Dread (the
-- passive) is built by his hits; Dreadforged, his skills grow.
SkillData.death_knight = {
	[1] = {
		name = "Blackwake",
		slot = 1,
		keybind = "E",
		cooldown = 7.0,
		damage = 70,
		range = 30, -- how far the crater tears out in front of him
		angle = 70, -- the cone's width in degrees (grows with Size)
		projectileSpeed = 70, -- how fast the crater ripples out
		description = "Smash a huge cone in front of you. Dreadforged: longer, plus a second wave.",
	},
	[2] = {
		name = "Doomfall",
		slot = 2,
		keybind = "F",
		cooldown = 10.0,
		damage = 110, -- the crash; the mist left behind bites for 12% a tick
		range = 24, -- the furthest leap (to the cursor)
		radius = 14,
		duration = 3.0, -- how long the mist lingers
		description = "Leap and slam at the cursor. Leaves damaging mist. Dreadforged: bigger, stronger mist.",
	},
	[3] = {
		name = "Grave Reversal",
		slot = 3,
		keybind = "Q",
		cooldown = 11.0,
		damage = 55, -- the snare 0.4x; the first slam 1x, the execution 2.6x (round them: 0.5x, 0.8x)
		range = 34, -- how far the chain reaches
		projectileSpeed = 140,
		description = "Chain the first enemy hit, swing it over your head into the floor behind you, then fling it away. Bosses don't move but take both hits.",
	},
	[4] = {
		name = "King of the Grave",
		slot = 4,
		keybind = "R",
		cooldown = 70.0,
		damage = 60, -- the chains 0.4x, the impact 4.5x, the Dread marks 2.5x
		radius = 32,
		description = "Ultimate: leap and slam a giant hammer, launching every enemy nearby. Chains pull survivors in, then they explode.",
	},
}

-- The Ronin (RoninServer). Every skill is a draw from the scabbard; hits
-- land on the beats of the baked moves (RoninMoves).
SkillData.ronin = {
	[1] = {
		name = "Distant Cut",
		slot = 1,
		keybind = "E",
		cooldown = 6.0,
		damage = 27, -- each of the five bursts of cuts (the same total as three of 45)
		range = 40, -- how far the cursor may be
		radius = 9,
		description = "A quick draw. When the blade clicks home, a flurry of cuts keeps hitting at the cursor for a moment.",
	},
	[2] = {
		name = "Rising Cut",
		slot = 2,
		keybind = "F",
		cooldown = 7.0,
		damage = 85, -- stage 1; x1.7 at stage 2, x2.8 at stage 3 (RoninServer RISE_SCALE)
		range = 20, -- stage 1; x1.35, x1.8
		description = "Hold to charge through three stages, release: a draw-cut that rolls forward, further, harder and wider each stage.",
	},
	[3] = {
		name = "Falling Heaven",
		slot = 3,
		keybind = "Q",
		cooldown = 10.0,
		damage = 35, -- each air cut; the slam 3.2x
		radius = 12,
		description = "Leap, cut twice and spin, then flip into a downward cut that slams the area.",
	},
	[4] = {
		name = "Thousand Cuts",
		slot = 4,
		keybind = "R",
		cooldown = 65.0,
		damage = 300, -- the click; the storm's four waves 0.06x each
		radius = 30,
		description = "Ultimate: a storm of cuts over everything near. Every cut lands when the blade is sheathed.",
	},
}

-- The skill bar's hover tip: one sentence on what the skill does, and the
-- tomes that make it better (only ones its code actually reads: Size for its
-- area, Duration for how long it lasts, Quantity for extra projectiles or
-- echoes, Ricochet for skills whose hits bounce, and so on).
local TIPS: { [string]: { { any } } } = {
	ranger = {
		{ "Dash forward, cutting through every enemy in your path.", { "size", "cooldown", "damage" } },
		{ "Root a group of enemies in place with bursting vines.", { "duration", "size", "cooldown" } },
		{ "For 8 seconds every attack also fires homing missiles.", { "duration", "quantity", "attack_speed" } },
		{ "Summon a giant plant that taunts and whips enemies while arrows rain down.", { "size", "duration", "knockback" } },
	},
	heavy_knight = {
		{ "Spin inside a tornado of fire that drags enemies along and burns them.", { "size", "knockback", "damage" } },
		{ "Fly up as a phoenix and dive onto the spot you choose.", { "size", "damage", "cooldown" } },
		{ "Drive the sword down for a huge explosion and rolling aftershocks.", { "size", "damage", "cooldown" } },
		{ "Bring down a sword of golden fire that sends a vast wave down a line.", { "size", "damage", "cooldown" } },
	},
	berserker = {
		{ "Leap to the cursor and crash down, knocking enemies into the air.", { "size", "knockback", "cooldown" } },
		{ "Carve crimson crescents in front of you while taking half damage.", { "size", "bloody", "armor" } },
		{ "Charge through enemies untouchable and Empower your next skill.", { "size", "knockback", "cooldown" } },
		{ "At full Rage, become a beast whose skills hit harder and recharge faster.", { "duration", "size", "bloody" } },
	},
	cleric = {
		{ "Send a homing bolt of green fire that heals the most wounded ally.", { "cooldown", "regen" } },
		{ "Fire a beam of holy light that hits everything in a line.", { "quantity", "size", "duration" } },
		{ "Bless an area that heals and cleanses allies standing in it.", { "size", "duration", "cooldown" } },
		{ "Revive fallen teammates, heal the party and smite enemies nearby.", { "size", "cooldown" } },
	},
	ice_mage = {
		{ "Send a line of spikes that pierces and briefly freezes enemies.", { "quantity", "size", "cooldown" } },
		{ "Channel a freezing beam into the first enemy it touches.", { "quantity", "duration", "size" } },
		{ "Summon a clone that taunts enemies and bursts into frost when broken.", { "size", "cooldown" } },
		{ "Call down a blizzard that freezes and batters every enemy inside.", { "size", "duration", "cooldown" } },
	},
	gunslinger = {
		{ "Empty the revolver in one fast, short-range burst.", { "quantity", "ricochet", "size" } },
		{ "Roll away untouchable, drop a stunning flashbang and fire a shot.", { "quantity", "size", "cooldown" } },
		{ "Toss a coin and shoot it to split your bullet across the room.", { "quantity", "ricochet", "duration" } },
		{ "Slow time, mark every enemy and gun them down one by one.", { "quantity", "size", "precision" } },
	},
	swordsman = {
		{ "Dash through enemies with two quick strikes.", { "size", "cooldown", "damage" } },
		{ "Block an attack, stun the attacker and riposte with a pommel strike.", { "duration", "size", "cooldown" } },
		{ "Charge the rapier's point, then lunge with a thrust that pierces a whole line.", { "quantity", "size", "cooldown" } },
		{ "Slow the world and flash between every enemy in a chain of cuts.", { "size", "damage", "precision" } },
	},
	rogue = {
		{ "Throw a dagger that marks an enemy, then step into the shadows behind it.", { "duration", "size", "projectile_speed" } },
		{ "Dash through enemies, slashing and marking them as you go.", { "size", "cooldown", "precision" } },
		{ "Vanish and move faster while enemies lose track of you.", { "duration", "agility", "cooldown" } },
		{ "Vanish in smoke as afterimages strike everything, then detonate every mark.", { "size", "precision", "damage" } },
	},
	mage = {
		{ "Fire an arcane bolt that explodes and pulls enemies together.", { "quantity", "size", "projectile_speed" } },
		{ "Trap enemies in a circle that charges up and explodes.", { "size", "duration", "cooldown" } },
		{ "Teleport to a spot, leaving a shockwave and an echo of your next spell.", { "size", "cooldown" } },
		{ "Mark every enemy nearby, rain arcane bolts on them, then detonate the marks.", { "size", "damage", "cooldown" } },
	},
	summoner = {
		{ "Drop a lava golem that taunts and pummels; recast for a lava Ground Slam.", { "duration", "size", "damage" } },
		{ "Call a storm hawk that fires feathers; recast for a cyclone.", { "quantity", "duration", "size" } },
		{ "Call a moon stag that heals the party; recast for a healing bloom.", { "duration", "size", "cooldown" } },
		{ "Fuse every beast into the Skyrockorn for a storm of starfire and a crash.", { "size", "damage", "cooldown" } },
	},
	death_knight = {
		{ "Swing wide and send a huge crescent of black smoke rolling forward.", { "size", "knockback", "damage" } },
		{ "Leap up and crash down sword-first, leaving a pool of biting mist.", { "size", "duration", "cooldown" } },
		{ "Hook an enemy with a chain, swing it overhead into the floor and fling it away.", { "damage", "knockback", "cooldown" } },
		{ "Plant the blade: chains bind every enemy near, spectral sweeps, a final impact.", { "size", "damage", "cooldown" } },
	},
	ronin = {
		{ "Quick-draw: a sphere of cuts lands on the cursor as the blade clicks home.", { "size", "damage", "cooldown" } },
		{ "A low draw sweeping straight up, launching what's in front.", { "size", "damage", "cooldown" } },
		{ "Leap, cut in the air, then flip into a slam.", { "size", "damage", "cooldown" } },
		{ "A storm of cuts; every one lands when the blade is sheathed.", { "size", "damage", "cooldown" } },
	},
	martial_artist = {
		{ "Hammer out a barrage of punches, then finish with a punch that craters a cone.", { "size", "knockback", "ricochet" } },
		{ "Dash in and launch enemies with an uppercut of chaining lightning.", { "quantity", "ricochet", "size" } },
		{ "Hold to charge a haymaker, release a wave down the lane.", { "size", "damage", "cooldown" } },
		{ "Awaken the dragon: faster strikes, and it lashes out along every one.", { "attack_speed", "size", "damage" } },
	},
}
for classId, list in pairs(TIPS) do
	local skills = SkillData[classId]
	if skills then
		for i, tip in ipairs(list) do
			local config = skills[i]
			if config then
				config.hint = tip[1]
				config.tomes = tip[2]
			end
		end
	end
end

local SkillModule = {}

function SkillModule.GetSkills(classId: string): ClassSkills?
	return SkillData[classId]
end

function SkillModule.GetSkill(classId: string, skillIndex: number): SkillConfig?
	local skills = SkillModule.GetSkills(classId)
	return skills and skills[skillIndex]
end

return SkillModule
