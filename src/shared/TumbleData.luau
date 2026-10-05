--!strict
--[[
	TumbleData
	Thrown off a mount by a hit: how the tumble plays out from the momentum
	the rider had (MountManager on the server, Tumble on the clients).

	It goes: thrown clear of the mount (through the air), tucked rolls along
	the way they were riding, one after another and slower each time, a flop
	flat on the face as the momentum dies, a moment lying there, then the
	stand-up (a second: hands, right leg, left leg). The faster they were
	going, the further they go and the more times they roll; standing still
	they just fall over.

	  Plan(speed, room?) → plan   how far and how many rolls (`room`: how far
	                              they can go before a wall or a ledge)
	  Times(plan) → times         how long each part takes
	  Travel(u) → 0..1            how far along at fraction u of the move
	                              (fast at first, slowing to a stop)
--]]

local TumbleData = {}

TumbleData.STAND = 1.0      -- the stand-up
TumbleData.LIE = 0.45       -- face down, dazed, before getting up
TumbleData.MAX_SPEED = 60
TumbleData.SLOW = 10        -- below this they just fall over: no rolling
local ROLL_LENGTH = 11      -- studs of ground covered per roll

export type Plan = { speed: number, dist: number, rolls: number }
export type Times = { move: number, air: number, lie: number, stand: number, total: number }

function TumbleData.Plan(speed: number, room: number?): Plan
	speed = math.clamp(speed, 0, TumbleData.MAX_SPEED)
	local dist = if speed < TumbleData.SLOW then 1 + speed * 0.3 else speed * 0.8
	if room then dist = math.clamp(dist, 0, math.max(room, 0)) end
	local rolls = if speed < TumbleData.SLOW then 0 else math.clamp(math.floor(dist / ROLL_LENGTH + 0.5), 0, 4)
	return { speed = speed, dist = dist, rolls = rolls }
end

function TumbleData.Times(plan: Plan): Times
	-- (moving: from the momentum's speed down to a stop, Travel's curve)
	local move = if plan.speed < TumbleData.SLOW then 0.75
		else math.clamp(2 * plan.dist / math.max(plan.speed, 1), 0.75, 2.2)
	local air = math.min(0.3, move * 0.22)
	return { move = move, air = air, lie = TumbleData.LIE, stand = TumbleData.STAND,
		total = move + TumbleData.LIE + TumbleData.STAND }
end

-- Fraction of the way travelled at fraction `u` of the move: it starts at the
-- rider's speed and slows evenly to a stop.
function TumbleData.Travel(u: number): number
	u = math.clamp(u, 0, 1)
	return 1 - (1 - u) ^ 2
end

return TumbleData
