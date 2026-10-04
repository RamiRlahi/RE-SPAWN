--!strict
--[[
	RideData
	How each mount rides (shared by MountManager on the server and
	WingsMounts on the clients): how high it lifts its rider and how much
	faster they walk while riding it in the lobby.
--]]

local RideData = {}

-- Walk speed while riding, by the mount's rarity (the lobby's base is 16).
RideData.SpeedByRarity = { Common = 1.5, Rare = 1.6, Epic = 1.7, Legendary = 1.8, Mythic = 1.9 }

-- Studs the rider is lifted (their HipHeight is raised by this).
RideData.Ride = {
	dire_wolf = 2.4, war_boar = 2.2, skeleton_horse = 3, giant_spider = 2.4, frost_wolf = 2.4,
	dire_bear = 2.8, flame_ram = 2.4, venom_scorpion = 2, shadow_panther = 2.4, crystal_stag = 3,
	magma_lizard = 1.8, infernal_dragon = 3.2, storm_wyvern = 3.2, death_knight_horse = 3.2,
	void_serpent = 3, celestial_lion = 3, eclipse_dragon = 3.4,
}

function RideData.RideHeight(look: string?): number
	return (look and RideData.Ride[look]) or 2.4
end

return RideData
