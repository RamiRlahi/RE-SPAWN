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

-- Model size: the rarer, the grander.
RideData.Scale = {
	venom_scorpion = 1.15, shadow_panther = 1.15, crystal_stag = 1.15, magma_lizard = 1.15,
	infernal_dragon = 1.3, storm_wyvern = 1.3, death_knight_horse = 1.3,
	void_serpent = 1.4, celestial_lion = 1.4, eclipse_dragon = 1.4,
	magic_carpet = 1.15, void_disc = 1.3, wishing_star = 1.4,
}

-- Height of the back (where the rider sits) above the ground, in studs.
RideData.Back = {
	dire_wolf = 3.8, war_boar = 3.8, skeleton_horse = 4.2, giant_spider = 3.9, frost_wolf = 3.4,
	dire_bear = 4.2, flame_ram = 3.4, venom_scorpion = 2.9, shadow_panther = 3.9, crystal_stag = 4.8,
	magma_lizard = 2.4, infernal_dragon = 5.5, storm_wyvern = 5.5, death_knight_horse = 6,
	void_serpent = 5.3, celestial_lion = 5.9, eclipse_dragon = 6.5,
	magic_carpet = 2.6, void_disc = 3.4, wishing_star = 3.2,
}

-- Floating platforms: sat on cross-legged, not straddled.
RideData.Flat = { magic_carpet = true, void_disc = true, wishing_star = true }

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
