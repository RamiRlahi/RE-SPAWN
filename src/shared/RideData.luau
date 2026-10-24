--!strict
--[[
	RideData
	How each mount rides (shared by MountManager on the server and
	WingsMounts / RewardPreview / the AnimationController on the clients):
	its size, how high its back is, and how fast it carries you (faster than
	running).

	The rider sits ON the back (WingsMounts.Seat bends their legs astride, or
	cross-legged on a flat platform), so they're lifted until their hips are
	at the back's height.
--]]

local RideData = {}

-- Speed while riding, by the mount's rarity (studs/s: walking is 16, running 34).
RideData.SpeedByRarity = { Common = 40, Rare = 42, Epic = 44, Legendary = 46, Mythic = 48 }

function RideData.Speed(rarity: string?): number
	return (rarity and RideData.SpeedByRarity[rarity]) or 40
end

-- Model size by tier (Rare ×1.0, Epic ×1.15, Legendary ×1.3, Mythic ×1.4;
-- the Secret boss-trophy minis are horse-sized, ×1.0).
RideData.Scale = {
	giant_spider = 1.15, frost_wolf = 1.15, dire_bear = 1.15, flame_ram = 1.15, venom_scorpion = 1.15,
	shadow_panther = 1.15, crystal_stag = 1.15, magma_lizard = 1.15, magic_carpet = 1.15,
	infernal_dragon = 1.3, storm_wyvern = 1.3, death_knight_horse = 1.3, void_disc = 1.3,
	ossuary_beetle = 1.3, tidal_hippocampus = 1.3, clockwork_gryphon = 1.3, blood_moon_warg = 1.3,
	void_serpent = 1.4, celestial_lion = 1.4, eclipse_dragon = 1.4, wishing_star = 1.4, abyssal_leviathan_ray = 1.4,
	seraph_steed = 1.4, chronos_tortoise = 1.4, nebula_kirin = 1.4, bloomheart_stag = 1.4,
}

-- Height of the back (where the rider sits: the top of the saddle) above
-- the ground, in studs.
RideData.Back = {
	dire_wolf = 4.0, war_boar = 4.0, skeleton_horse = 4.8,
	giant_spider = 3.6, frost_wolf = 4.6, dire_bear = 5.1, flame_ram = 4.6, venom_scorpion = 2.7,
	shadow_panther = 4.6, crystal_stag = 5.1, magma_lizard = 3.1, magic_carpet = 2.6,
	infernal_dragon = 5.7, storm_wyvern = 5.7, death_knight_horse = 6.3, void_disc = 3.4,
	ossuary_beetle = 4.6, tidal_hippocampus = 4.6, clockwork_gryphon = 5.7, blood_moon_warg = 5.2,
	void_serpent = 5.6, celestial_lion = 7.4, eclipse_dragon = 7.9, wishing_star = 5.2, abyssal_leviathan_ray = 3.8,
	seraph_steed = 6.8, chronos_tortoise = 6.2, nebula_kirin = 6.8, bloomheart_stag = 6.8,
	mini_ignarath = 3.2, mini_zar0 = 2.7, mini_malakor = 3.2, mini_bone_colossus = 4.8, mini_iron_warlord = 3.2, mini_hex_witch = 4.4,
}

-- Floating platforms: sat on cross-legged, not straddled.
RideData.Flat = { magic_carpet = true, void_disc = true, wishing_star = true, abyssal_leviathan_ray = true, mini_zar0 = true }

function RideData.ScaleOf(look: string?): number
	return (look and RideData.Scale[look]) or 1
end

function RideData.IsFlat(look: string?): boolean
	return look ~= nil and RideData.Flat[look] == true
end

function RideData.BackHeight(look: string?): number
	return (look and RideData.Back[look]) or 3.6
end

-- How much to raise a rider (HipHeight) whose legs are `legLen` long so they
-- sit on the back with their legs bent round it.
function RideData.SeatLift(look: string?, legLen: number): number
	local lift = RideData.BackHeight(look) - legLen * 0.85
	-- (cross-legged on a platform: the legs lie on top of it, not round it)
	if RideData.IsFlat(look) then lift += 0.7 end
	return math.max(0.2, lift)
end

-- (kept for older callers)
function RideData.RideHeight(look: string?): number
	return RideData.SeatLift(look, 2)
end

return RideData
