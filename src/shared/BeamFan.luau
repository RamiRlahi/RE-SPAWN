--!strict
--[[
	BeamFan.luau
	How a channelled beam (the Cleric's Divine Beam, the Ice Mage's Ice Beam)
	splits with Projectile Count: one beam, plus one per extra projectile,
	STEP degrees apart round the aim. The fan keeps widening with every
	projectile until it would reach all the way round; from then on the
	beams close into a full ring, evenly spaced (and denser with each one
	after). The server (damage) and the clients (the beams drawn) both ask
	here, so they always agree.

	  BeamFan.Angles(projectileCount) → { degrees }
	      each beam's angle off the aim (0 for a lone beam)
	  BeamFan.Detailed(i, n) → boolean
	      is beam `i` of `n` drawn in full? Past FULL beams only that many
	      are (the aimed one and others spread evenly round): the rest are
	      plain glowing beams, so a ring of thirty doesn't cost thirty times
	      the parts, particles, lights and raycasts. Every beam still hits.
--]]

local BeamFan = {}

BeamFan.STEP = 12 -- degrees between beams (a full ring at 30)
BeamFan.FULL = 6  -- beams drawn in full detail, at most

function BeamFan.Angles(projectileCount: number?): { number }
	local n = 1 + math.max(0, math.floor(projectileCount or 0))
	-- (once they'd go all the way round, evenly round the circle instead)
	local step = if n * BeamFan.STEP >= 360 then 360 / n else BeamFan.STEP
	local angles = table.create(n)
	for i = 1, n do
		angles[i] = (i - 1 - (n - 1) / 2) * step
	end
	return angles
end

function BeamFan.Detailed(i: number, n: number): boolean
	if n <= BeamFan.FULL then return true end
	-- (a beam is detailed where the count of detailed beams so far, measured
	-- out from the middle one, ticks over: FULL of them, evenly spaced)
	local mid = (n + 1) // 2
	local k = BeamFan.FULL / n
	return math.floor((i - mid) * k) ~= math.floor((i - 1 - mid) * k)
end

return BeamFan
