--!strict
--[[
	AccountLevel.luau
	The account level curve, shared so the client can draw the same numbers
	the server saves. Levels 1..100; each level asks for more XP than the one
	before (100 XP for level 2, ~860 at level 10, ~8,200 at level 50, ~21,600
	for the last one; ~900k XP from 1 to 100).
--]]

local AccountLevel = {}

AccountLevel.MAX = 100

-- XP needed to go from `level` to `level + 1` (0 at the cap).
function AccountLevel.XpToNext(level: number): number
	if level >= AccountLevel.MAX then return 0 end
	return math.floor(100 + 35 * math.max(level - 1, 0) ^ 1.4)
end

return AccountLevel
