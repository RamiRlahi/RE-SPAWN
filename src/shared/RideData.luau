--!strict
--[[
	RideData
	How each mount rides (shared by MountManager on the server and
	WingsMounts / RewardPreview on the clients): its size, how high its back
	is, and how much faster its rider walks in the lobby.

	The rider sits ON the back (WingsMounts.Seat bends their legs astride),
	so they're lifted until their hips are at the back's height.
--]]

local RideData = {}

-- Walk speed while riding, by the mount's rarity (the lobby's base is 16).
RideData.SpeedByRarity = { Common = 1.5, Rare = 1.6, Epic = 1.7, Legendary = 1.8, Mythic = 1.9 }

-- Model size: the rarer, the grander.
RideData.Scale = {
	venom_scorpion = 1.15, shadow_panther = 1.15, crystal_stag = 1.15, magma_lizard = 1.15,
	infernal_dragon = 1.3, storm_wyvern = 1.3, death_knight_horse = 1.3,
	void_serpent = 1.4, celestial_lion = 1.4, eclipse_dragon = 1.4,
}

-- Height of the back (where the rider sits) above the ground, in studs.
RideData.Back = {
	dire_wolf = 3.8, war_boar = 3.8, skeleton_horse = 4.2, giant_spider = 3.9, frost_wolf = 3.4,
	dire_bear = 4.2, flame_ram = 3.4, venom_scorpion = 2.9, shadow_panther = 3.9, crystal_stag = 4.8,
	magma_lizard = 2.4, infernal_dragon = 5.5, storm_wyvern = 5.5, death_knight_horse = 6,
	void_serpent = 5.3, celestial_lion = 5.9, eclipse_dragon = 6.5,
}

function RideData.ScaleOf(look: string?): number
	return (look and RideData.Scale[look]) or 1
end

function RideData.BackHeight(look: string?): number
	return (look and RideData.Back[look]) or 3.6
end

-- How much to raise a rider (HipHeight) whose legs are `legLen` long so they
-- sit on the back with their legs bent round it.
function RideData.SeatLift(look: string?, legLen: number): number
	return math.max(0.2, RideData.BackHeight(look) - legLen * 0.85)
end

-- (kept for older callers)
function RideData.RideHeight(look: string?): number
	return RideData.SeatLift(look, 2)
end

return RideData
