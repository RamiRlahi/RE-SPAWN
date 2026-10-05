--!strict
--[[
	RangerArrowData.luau
	The Ranger's basic arrows, shared by the server (which flies them for real
	and deals the damage when one arrives: SkillManager) and every client
	(which draws them: RangerArrows), so both agree on where they go.

	  RangerArrowData.SPEED, RANGE        studs/s (× Projectile Speed), studs
	  RangerArrowData.Directions(look, n) the fan of n arrows round `look`
	  RangerArrowData.Assist(origin, dir, targets, reach)
	      light aim assist: if nothing stands on the arrow's line, it flies at
	      the nearest target within ASSIST_DEG of it instead
	  RangerArrowData.Key(shot, index)    an arrow's id within its volley
--]]

local RangerArrowData = {}

RangerArrowData.SPEED = 180
RangerArrowData.RANGE = 70
RangerArrowData.SPREAD = 8      -- degrees between neighbouring arrows
RangerArrowData.ASSIST_DEG = 10
RangerArrowData.WIDTH = 3.5     -- the arrow's reach either side of its line (× Size)

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

function RangerArrowData.Directions(look: Vector3, count: number): { Vector3 }
	local base = flat(look)
	local out = {}
	local start = -(count - 1) * RangerArrowData.SPREAD / 2
	for i = 1, count do
		local a = math.rad(start + (i - 1) * RangerArrowData.SPREAD)
		table.insert(out, (CFrame.Angles(0, a, 0) * base).Unit)
	end
	return out
end

-- `targets`: positions of the living enemies; `reach(i)`: how far from the
-- line target i still counts as on it.
function RangerArrowData.Assist(origin: Vector3, dir: Vector3, targets: { Vector3 }, reach: (number) -> number): Vector3
	local range = RangerArrowData.RANGE
	for i, p in ipairs(targets) do
		local d = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
		local along = d:Dot(dir)
		if along >= 0 and along <= range and (d - dir * along).Magnitude <= reach(i) then
			return dir -- something's on the line already
		end
	end
	local best, bestD = nil, range
	local cosMax = math.cos(math.rad(RangerArrowData.ASSIST_DEG))
	for _, p in ipairs(targets) do
		local d = Vector3.new(p.X - origin.X, 0, p.Z - origin.Z)
		local m = d.Magnitude
		if m > 0.5 and m < bestD and d.Unit:Dot(dir) > cosMax then
			best, bestD = d.Unit, m
		end
	end
	return best or dir
end

function RangerArrowData.Key(shot: number, index: number): number
	return (shot % 1000000) * 32 + index
end

return RangerArrowData
