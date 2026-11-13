--!strict
--[[
	FireVortexConfig.luau
	Every tunable of the fire vortex (FireVortexFX) in one place. Sizes are
	multiples of the vortex radius R (studs) unless noted; times in seconds.

	Look: a compact, extremely bright fire core inside a chaotic sphere of
	sweeping energy ribbons (Beams), sharp streaks shooting past the
	silhouette, embers and sparks, and a wide ground ring with trails.
--]]

local FireVortexConfig = {}

FireVortexConfig.Colors = {
	-- (the ribbon texture carries the white-hot centre -> orange -> red-orange
	-- edges across its width; these tint it along the length: hot head, red tail)
	ribbonHead = Color3.fromRGB(255, 244, 205),
	ribbonMid = Color3.fromRGB(255, 176, 70),
	ribbonTail = Color3.fromRGB(255, 70, 30),
	streak = Color3.fromRGB(255, 120, 45),
	coreHot = Color3.fromRGB(255, 250, 225),
	coreFlame = Color3.fromRGB(255, 190, 80),
	ground = Color3.fromRGB(255, 90, 35),
	ember = Color3.fromRGB(255, 200, 110),
	smoke = Color3.fromRGB(60, 40, 34),
}

-- Phases (seconds from the cast): ignition -> formation -> sustain -> explosion
FireVortexConfig.Phases = {
	ignition = 0.22,  -- the core flashes up, the ground ring snaps out
	formation = 0.4,  -- the ribbons sweep in from the core to full size
	explosion = 0.3,  -- at the end: ribbons and streaks fling outward and burn out
}

-- The sphere: its centre sits this far over the floor (x R).
FireVortexConfig.CenterHeight = 0.85

FireVortexConfig.Core = {
	glowSize = 0.5,         -- the white-hot glow ball (x R), always on
	glowRate = 8,
	flameSize = 0.42,       -- upward flame tongues (x R)
	flameRate = 26,
	flameRise = 1.6,        -- their speed (x R per second)
	burstEvery = 0.35,      -- a smaller flame burst out of the core this often
	smokeRate = 3,          -- thin dark smoke on top (kept low: never hide the core)
}

FireVortexConfig.Ribbons = {
	count = 6,              -- 5-7
	points = 7,             -- attachments per ribbon (6 curved beam segments)
	arc = { 150, 220 },     -- degrees each ribbon spans
	radius = { 0.8, 1.05 }, -- its orbit (x R)
	spiralIn = 0.18,        -- the tail curls this much inward (x its radius)
	width = { 0.16, 0.26 }, -- head width (x R); tapers to 15% at the tail
	speed = { 1.3, 2.6 },   -- turns a second along its orbit
	precess = { 0.15, 0.45 }, -- turns a second its orbit plane tumbles
	wobble = 0.08,          -- radius breathing (x radius)
	-- orbit planes, mixed: "horizontal" (spins round the up axis), "vertical",
	-- "diagonal"; one per ribbon, cycled
	orientations = { "horizontal", "diagonal", "vertical", "diagonal", "horizontal", "vertical", "diagonal" },
	textureSpeed = 2.2,     -- the texture streams along each ribbon
	brightness = 1.5,
	lightEmission = 0.55,   -- (additive overlap of many ribbons whites out above ~0.6)
}

FireVortexConfig.Streaks = {
	count = 12,             -- 10-15
	from = { 0.75, 1.0 },   -- where they start (x R from the centre)
	length = { 0.8, 1.5 },  -- how far past that they reach (x R)
	width = { 0.045, 0.075 }, -- (x R): thin and sharp, but never a hairline
	life = { 0.22, 0.42 },  -- each one flicks out, then a new one somewhere else
	bend = 0.35,            -- sideways curl along the swirl (x length)
	brightness = 1.8,
}

FireVortexConfig.Particles = {
	embers = 26,            -- per second, flung out and rising
	sparks = 18,            -- per second, fast short streaks
	emberSize = 0.32,       -- studs
	sparkSpeed = { 18, 34 },
}

FireVortexConfig.Ground = {
	radius = 1.35,          -- the ring (x R)
	width = 0.12,           -- its band (x R)
	spin = 0.5,             -- turns a second
	trails = 3,             -- rotating energy trails on the floor inside the ring
	trailRadius = { 0.7, 1.15 },
	trailArc = 120,         -- degrees
	trailWidth = 0.09,      -- (x R)
	trailSpeed = { 1.4, 2.2 }, -- turns a second
	glowSize = 2.6,         -- the floor glow under it (x R): soft, not a disc
}

FireVortexConfig.Explosion = {
	fling = 1.9,            -- ribbons and streaks fly out to this (x their radius)
	burstStreaks = 14,      -- extra streaks shot out at the end
}

-- Low budget (FxBudget.Pressure() near 1): counts are scaled down by up to this.
FireVortexConfig.PressureCut = 0.5

return FireVortexConfig
