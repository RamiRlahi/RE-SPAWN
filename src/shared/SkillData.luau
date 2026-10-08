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
			description = "Instantly dash forward, piercing all enemies in your path and leaving a lingering nature energy slash.",
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
			description = "Fire a special arrow that erupts into grasping vines, rooting all enemies in a small area.",
		},
		[3] = {
			name = "Seeker Barrage",
			slot = 3,
			keybind = "Q",
			cooldown = 12.0,
			damage = 35,
			duration = 8.0,
			description = "Buff: For 8 seconds, each attack launches homing nature missiles from your back that curve and seek out nearby enemies.",
		},
		[4] = {
			name = "Rain of Arrows",
			slot = 4,
			keybind = "R",
			cooldown = 30.0,
			damage = 24,
			range = 42,
			duration = 4.0,
			description = "Fire an arrow skyward to mark a large zone, then call down a repeated storm of arrows.",
		},
	},
	-- The Fire Knight (class id kept as heavy_knight; FireKnightServer).
	heavy_knight = {
		[1] = {
			name = "Blazing Charge",
			slot = 1,
			keybind = "E",
			cooldown = 7.0,
			damage = 40, -- on contact; the upward slash deals more
			dashDistance = 22,
			description = "Charge forward in flames, dragging enemies along, and finish with an upward slash that launches them. Overheated: a flaming bull rush that plows through everything and leaves the path burning.",
		},
		[2] = {
			name = "Phoenix Slam",
			slot = 2,
			keybind = "F",
			cooldown = 9.0,
			damage = 90, -- the impact (Overheated: flares go off round it too)
			range = 40, -- how far from where you take off you can land
			description = "Soar into the air and become a phoenix of fire. Move the marker to pick your landing spot and click (or press F again) to dive: an explosion that leaves the ground burning. Overheated: a bigger impact, more explosions and a lingering inferno.",
		},
		[3] = {
			name = "Infernal Earthshaker",
			slot = 3,
			keybind = "Q",
			cooldown = 11.0,
			damage = 70,
			range = 14,
			description = "Raise the sword and drive it into the ground: a giant explosion, aftershocks traveling outward, and patches of fire left behind. Overheated: three expanding rings of fire.",
		},
		[4] = {
			name = "Heart of the Inferno",
			slot = 4,
			keybind = "R",
			cooldown = 40.0,
			damage = 150,
			description = "Ultimate: plant the sword and awaken. For several seconds every attack explodes; then every flame is drawn into the sword for one enormous flame wave that erupts. At 100 Heat: the Primordial Inferno.",
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
		description = "Leap to the cursor (up to 17 studs) and crash down with the greatsword: the ground fractures in a crater and a shockwave knocks enemies up.",
	},
	[2] = {
		name = "Bloodstorm",
		slot = 2,
		keybind = "F",
		cooldown = 10.0,
		damage = 30,
		range = 30,
		description = "Plant your feet and carve huge crimson crescents in front of you, each blow landing with a jolt, then finish with a spinning cleave that throws enemies away. You take half damage during it.",
	},
	[3] = {
		name = "Crimson Charge",
		slot = 3,
		keybind = "Q",
		cooldown = 12.0,
		damage = 40,
		range = 28,
		description = "Charge headlong at the aim, untouchable the whole way: every enemy in your path is cut and thrown aside, and a burst at the end blows everything near away. Your next skill is Empowered.",
	},
	[4] = {
		name = "Beast Awakening",
		slot = 4,
		keybind = "R",
		cooldown = 4.0, -- (it needs a full Rage meter: that's the real wait)
		damage = 160,
		duration = 12,
		description = "Ultimate (full Rage): abandon your humanity. Your body tears open into a monster, the sword cast aside, and a roar blows everything near away. For 12 seconds you fight as the BEAST: claws instead of a sword, and every skill becomes a new one (Beast Slam, Carnage, Beast Charge), harder hitting and twice as fast to recharge.",
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
		description = "Send a bolt of sacred green fire that tracks and heals the lowest ally. Holds 3 charges.",
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
		description = "Release a concentrated beam of holy light, dealing heavy damage to enemies in a straight line.",
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
		description = "Bless the area with holy light, healing allies over time and removing negative effects.",
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
		description = "Ultimate: Kneel in prayer and call down the light. Fallen teammates rise beside you, the party is healed and cleansed, and nearby enemies are smitten.",
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
		description = "Send a racing line of crystalline spikes erupting from the floor, piercing and briefly freezing every enemy in its path.",
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
		description = "Channel a concentrated beam of absolute cold. It stops on the first enemy it touches, freezing and shredding it.",
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
		description = "Summon a crystalline clone (50 HP) that taunts nearby enemies. When destroyed it detonates in a freezing shockwave.",
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
		description = "Ultimate: Call down a raging blizzard over the battlefield, freezing every enemy and battering those inside with ice.",
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
		description = "Rapidly fire every bullet left in the revolver: huge short-range burst, empties the cylinder.",
	},
	[2] = {
		name = "Gunslinger's Roll",
		slot = 2,
		keybind = "F",
		cooldown = 3.2,
		damage = 0,
		dashDistance = 15,
		duration = 0.26, -- roll time; i-frames last a little longer
		description = "Roll a short distance with brief invulnerability, leaving a flashbang behind that stuns nearby enemies (not bosses; one more per Projectile Count), then fire one shot toward the cursor.",
	},
	[3] = {
		name = "Deadeye Ricochet",
		slot = 3,
		keybind = "Q",
		cooldown = 7.0,
		damage = 26, -- per ricochet projectile
		range = 24, -- coin throw distance
		duration = 2.6, -- how long the coin hangs in the air
		description = "Toss a spinning coin. Shoot it to split the bullet into ricochets that seek every enemy in the room.",
	},
	[4] = {
		name = "High Noon",
		slot = 4,
		keybind = "R",
		cooldown = 40.0,
		damage = 165, -- per marked target (×3 of the old 55); the execution shot deals far more
		range = 50,
		duration = 3.7, -- standoff + volley + execution (mobs are frozen through it)
		description = "Ultimate: time slows, every enemy in the room is marked, gunned down one by one, and the last is executed with a Deadeye shot.",
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
		description = "Dash forward through enemies with two rapid strikes. Enemies hit by both take extra damage. Empowered: longer dash, wider cut, a third strike.",
	},
	[2] = {
		name = "Parry",
		slot = 2,
		keybind = "F",
		cooldown = 8.0,
		damage = 90, -- the counter slash
		duration = 0.6, -- parry window
		range = 14,
		description = "Guard for a moment. Parry an attack to negate it, stun the attacker and counter with a huge upward slash. Empowered: longer window, bigger counter.",
	},
	[3] = {
		name = "Whirlwind",
		slot = 3,
		keybind = "Q",
		cooldown = 10.0,
		damage = 14, -- per spin hit; the last hit deals more and launches
		range = 13,
		duration = 1.2,
		description = "Spin with the blade out, hitting everything around you and dragging smaller foes in; the last cut launches them. Empowered: bigger and longer.",
	},
	[4] = {
		name = "Blade Storm",
		slot = 4,
		keybind = "R",
		cooldown = 35.0,
		damage = 60, -- per dash slash; the final X deals far more
		range = 45,
		description = "Ultimate: plant the sword and slow the world, flash to every enemy in the room in a chain of slashes, then carve a giant X that hits the whole room.",
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
		description = "Throw a dagger: it sticks in the first enemy it hits and marks them. Press again to Shadow Step to it, appearing behind a marked enemy for bonus damage. Works while invisible.",
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
		description = "Dash instantly in the aimed direction, slashing through every enemy on the way and applying the Shadow Mark. Holds 4 charges.",
	},
	[3] = {
		name = "Invisibility",
		slot = 3,
		keybind = "Q",
		cooldown = 20.0,
		damage = 0,
		duration = 6.0,
		description = "Become invisible for 6 seconds. Enemies lose you and you move faster. Attacking or taking damage ends it early.",
	},
	[4] = {
		name = "Shadow Execution",
		slot = 4,
		keybind = "R",
		cooldown = 60.0,
		damage = 40, -- per slash (five, through every enemy in the smoke); each leaves a mark that detonates for 1.5x; the final strike deals 3x
		range = 24,
		description = "Ultimate: throw a smoke bomb and vanish. Your afterimages strike every enemy in the smoke five times, marking them, then you reappear behind the nearest and detonate every mark at once.",
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
		description = "Fire a concentrated arcane projectile that explodes on impact, pulling nearby enemies towards the center and leaving an Arcane Rune. Empowered: three converging projectiles.",
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
		description = "Place a magic circle that traps enemies within spectral chains. The longer they remain, the more it charges before collapsing in a massive explosion. An Arcane Rune inside detonates too. Empowered: larger, pulls enemies in, explodes faster.",
	},
	[3] = {
		name = "Arcane Shift",
		slot = 3,
		keybind = "Q",
		cooldown = 9.0,
		damage = 35, -- the shockwave where you reappear
		range = 30,
		radius = 10,
		description = "Phase through space to the target location, untargetable. Reappear with a shockwave and leave an Arcane Echo that repeats your next ability with reduced power. Empowered: three Arcane Echoes.",
	},
	[4] = {
		name = "Apocalypse",
		slot = 4,
		keybind = "R",
		cooldown = 70.0,
		damage = 26, -- per falling bolt; every mark detonates for 6x
		radius = 45,
		description = "Ultimate: mark every enemy in a large radius, call down a storm of arcane projectiles, then every mark detonates in a massive explosion.",
	},
}

SkillData.martial_artist = {
	[1] = {
		name = "Dragon Fist",
		slot = 1,
		keybind = "E",
		cooldown = 6.0,
		damage = 70,
		range = 28, -- how far the dragon surges
		width = 6,
		description = "Channel Qi into your fists and release a flowing dragon of energy that surges forward, dealing heavy damage and pushing enemies back. Empowered: three dragon fists, greater range and damage.",
	},
	[2] = {
		name = "Qi Release",
		slot = 2,
		keybind = "F",
		cooldown = 14.0,
		damage = 20, -- the burst of Qi as it activates
		radius = 9,
		duration = 6.0,
		description = "Surround yourself with circulating Qi: more movement and attack speed, less damage taken, for a short time. Empowered: a larger aura, higher speed, stronger damage reduction.",
	},
	[3] = {
		name = "Dragon Ascent",
		slot = 3,
		keybind = "Q",
		cooldown = 9.0,
		damage = 55, -- the strike through enemies; the landing hits for 1.2x, the trail burns for 10% a tick
		range = 26,
		radius = 9,
		description = "Ride the flow of Qi: launch upward and dash through enemies on a dragon's energy, crash down in an explosive impact and leave a lingering trail. Empowered: multiple dragon strikes, more hits, wider area.",
	},
	[4] = {
		name = "Dragon Soul",
		slot = 4,
		keybind = "R",
		cooldown = 70.0,
		damage = 90, -- each of the dragon's passes through an enemy (three)
		range = 70,
		width = 22,
		description = "Ultimate: unleash the dragon within. A colossal dragon of Qi rises around you and sweeps through everything in its path.",
	},
}

local SkillModule = {}

function SkillModule.GetSkills(classId: string): ClassSkills?
	return SkillData[classId]
end

function SkillModule.GetSkill(classId: string, skillIndex: number): SkillConfig?
	local skills = SkillModule.GetSkills(classId)
	return skills and skills[skillIndex]
end

return SkillModule
