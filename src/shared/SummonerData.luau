--!strict
--[[
	SummonerData.luau
	Tuning the Summoner's server (SummonerServer) and client
	(SummonerController, Summons/Beasts) both read, so every hit lands on its
	animation's impact frame.

	The beasts (the artist's GLBs, Summons/Models):
	  rock   Rockborn     E   a lava-veined golem: meteor landing, taunts,
	                          hooks and hammer fists; recast: Ground Slam
	  sky    Skyfeather   F   a storm hawk: hovers, feather volleys, dives;
	                          recast: Wind Circle (a cyclone)
	  moon   Lunari       Q   a moon stag: heals in pulses, tramples through
	                          lines; recast: Radiant Bloom
	  fused  Skyrockorn   R   the three fused: Divine Cataclysm (the ult)

	Times are seconds from the start of a move; `hit` is the impact frame.
	Each beast's signature is its baked GLB move (`clip` seconds long).
--]]

local SummonerData = {}

SummonerData.KINDS = { "rock", "sky", "moon" }
SummonerData.SKILL_KIND = { "rock", "sky", "moon" } -- E, F, Q
SummonerData.KIND_SKILL = { rock = 1, sky = 2, moon = 3 }

SummonerData.MODEL = { rock = "Rockborn", sky = "Skyfeather", moon = "Lunari", fused = "Skyrockorn" }
SummonerData.TITLE = { rock = "ROCKBORN", sky = "SKYFEATHER", moon = "LUNARI", fused = "SKYROCKORN" }

-- Each beast's colours: its body's light (glow), and a pale core.
SummonerData.COLOR = {
	rock = Color3.fromRGB(255, 150, 40),
	sky = Color3.fromRGB(80, 225, 255),
	moon = Color3.fromRGB(255, 226, 90),
	fused = Color3.fromRGB(150, 240, 255),
	bond = Color3.fromRGB(130, 215, 255),
}
SummonerData.CORE = {
	rock = Color3.fromRGB(255, 226, 160),
	sky = Color3.fromRGB(220, 252, 255),
	moon = Color3.fromRGB(255, 250, 215),
	fused = Color3.fromRGB(240, 255, 255),
	bond = Color3.fromRGB(225, 245, 255),
}

-- The summon's root (the server's moving part) rides this far above the
-- beast's ground origin; the client puts the feet back down.
SummonerData.ROOT_LIFT = 1.5

SummonerData.BEAST = {
	rock = {
		scale = 1.0, speed = 15, accel = 40, turn = 7, fly = 0,
		reach = 6.5,   -- melee: it closes to this
		hp = 9,        -- × the Summoner's max health
		taunt = 26,    -- mobs this close attack it instead
		slot = Vector3.new(4.5, 0, 3.5), -- where it walks beside you (right, up, back)
		-- the hooks: left, right, then a two-fisted hammer
		attack = { every = 1.15, dur = 0.75, hit = 0.38, damage = 26, arc = 70, range = 8.5 },
		hammer = { dur = 1.0, hit = 0.55, damage = 48, radius = 9 },
		landing = { fall = 0.5, damage = 60, radius = 11 }, -- the meteor it arrives as
		sig = { clip = 3.4, leapFrom = 0.95, leapTo = 1.85, hit = 1.87, damage = 120, radius = 15, range = 32,
			fissures = 4, fissureLen = 18, fissureAt = 2.15, cooldown = 6 },
	},
	sky = {
		scale = 0.9, speed = 30, accel = 70, turn = 9, fly = 7,
		reach = 15,    -- it hangs back this far and shoots
		slot = Vector3.new(-3.5, 0, 2.5),
		attack = { every = 1.25, dur = 0.55, hit = 0.22, damage = 13, count = 3, speed = 110, spread = 9, range = 45 },
		dive = { every = 3, dur = 0.9, hit = 0.5, damage = 34, radius = 5.5 },
		landing = { fall = 0.55, damage = 30, radius = 8 }, -- the dive it arrives in
		sig = { clip = 4.0, dash = 0.35, from = 0.8, to = 3.05, hit = 3.1, tick = 0.2, tickDamage = 11, damage = 55,
			radius = 15, pull = 26, range = 40, travel = 2.3, cooldown = 6 },
	},
	moon = {
		scale = 1.0, speed = 24, accel = 55, turn = 6, fly = 0,
		reach = 5.5,
		slot = Vector3.new(-5, 0, 3.5),
		attack = { every = 1.4, dur = 0.7, hit = 0.32, damage = 22, arc = 60, range = 7 }, -- a horn jab
		charge = { every = 4.5, dur = 0.85, length = 22, width = 5, damage = 40, stun = 0.8 }, -- a trample through a line
		pulse = { every = 2.5, radius = 18, heal = 0.035 }, -- × max health
		landing = { fall = 0.6, heal = 0.08, radius = 16 },
		sig = { clip = 3.6, hit = 1.82, damage = 80, radius = 17, heal = 0.25, stun = 1.4, range = 30, cooldown = 7 },
	},
	fused = {
		scale = 1.6, speed = 0, accel = 0, turn = 4, fly = 0,
		travel = 0.75, -- its baked flight's circle, × this (rooms are only so big)
		sig = {
			clip = 8.0,
			gather = 1.1,          -- the beasts fly together and fuse before it
			rainFrom = 1.3, rainTo = 4.8, rainEvery = 0.11, rainDamage = 30, rainSplash = 5.5,
			raysFrom = 5.55, raysTo = 7.15, rayEvery = 0.2, rayDamage = 22, rays = 8,
			hit = 7.72, damage = 260, radius = 30,
			radius0 = 34, -- the rain falls within this of where it was cast
			-- its flight tears a crater trench into the floor beneath it…
			trenchFrom = 1.1, trenchTo = 4.85, trenchEvery = 0.1, trenchWidth = 7, trenchDamage = 34,
			-- …and drops tornadoes in its wake that wander, drag enemies in and cut them
			tornadoEvery = 0.55, tornadoLife = 3.6, tornadoRadius = 10, tornadoPull = 24,
			tornadoTick = 0.25, tornadoDamage = 9, tornadoDrift = 5,
			crater = 14, -- the crash's crater (radius, studs), left smoking a while
		},
	},
}

-- The Summoner's own Bond Bolt (M1).
SummonerData.BOLT = { interval = 0.48, damage = 18, speed = 115, range = 55, width = 2.2, fan = math.rad(8), focus = 4 }

-- Pack Bond: each other beast out makes every beast hit this much harder.
SummonerData.PACK_BONUS = 0.12

return SummonerData
