--[[
	Mounts/Rare.luau
	Rare mounts (×1.0): natural beasts, simple leather saddles, no glow but the
	eyes, subtle motion. (The Dire Wolf lives in WingsMounts.)
--]]

return function(K: any): { [string]: () -> any }
	local Kit, rgb, glow = K.Kit, K.rgb, K.glow
	local M = {}

	-- 0 → 1, held, → 0 over [a, b] with quick ramps (a held look).
	local function bump01(x: number, a: number, b: number): number
		if x <= a or x >= b then return 0 end
		return math.min(1, (x - a) / 0.15, (b - x) / 0.15)
	end

	-- War Boar: a stocky dark-brown boar, ivory tusks, iron head plate and
	-- flank plates, a spiked collar. Called: bucks with a snort. Emote: snorts
	-- and paws the ground, head down, ready to charge.
	function M.war_boar()
		local b = K.new("war_boar", { gait = 12, emoteLen = 2.2 })
		local HIDE, BELLY, BRISTLE = rgb(82, 56, 40), rgb(112, 82, 60), rgb(46, 32, 24)
		local LEGC, HOOF = rgb(68, 46, 33), rgb(38, 28, 22)
		local SNOUT, NOSE, DARK = rgb(150, 110, 95), rgb(120, 80, 70), rgb(40, 26, 22)
		local TUSK, IRON, IRON2, SPIKE = rgb(238, 228, 205), rgb(92, 96, 104), rgb(122, 126, 134), rgb(170, 175, 182)
		local LEATHER, STRAP, COLLAR = rgb(118, 66, 34), rgb(72, 40, 26), rgb(40, 40, 44)
		local EYE = glow(255, 120, 50)
		local charge = function(t: number): number return b:em(t) end

		b:gallop(6, 0.06)
		b:rearUp(4, 0.22)
		-- head down, weight forward, quivering: ready to charge
		b:move(function(t: number): CFrame
			local c = charge(t)
			if c == 0 then return CFrame.identity end
			local front = Vector3.new(0, 0, -4 * b.V)
			return CFrame.new(math.sin(t * 41) * 0.025 * c, 0, 0) * CFrame.new(front) * CFrame.Angles(-0.07 * c, 0, 0) * CFrame.new(-front)
		end)

		local body = Kit.group()
		Kit.box(body, -3, 3, -5, 3, 8, 5, HIDE)
		Kit.box(body, -3, 3, -5, 3, 3, 5, BELLY)
		Kit.box(body, -2, 9, -5, 2, 9, -2, HIDE) -- shoulder hump
		Kit.box(body, 0, 10, -5, 0, 10, -2, BRISTLE) -- bristle ridge
		Kit.box(body, 0, 9, 4, 0, 9, 5, BRISTLE)
		for _, sx in ipairs({ -4, 4 }) do
			Kit.box(body, sx, 5, -5, sx, 7, -2, IRON) -- flank plate
			Kit.set(body, sx, 6, -4, SPIKE.color)
			Kit.set(body, sx, 6, -3, SPIKE.color)
		end
		Kit.box(body, -3, 4, -6, 3, 8, -6, COLLAR) -- spiked collar
		for _, s in ipairs({ { -4, 6 }, { 4, 6 }, { -4, 8 }, { 4, 8 }, { -2, 9 }, { 0, 9 }, { 2, 9 } }) do Kit.set(body, s[1], s[2], -6, SPIKE.color) end
		K.saddle(body, 2, 9, -1, 2, LEATHER, STRAP, STRAP, IRON)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -2, -3, -4, 2, 1, 0, HIDE)
		Kit.box(head, -2, 2, -4, 2, 2, -1, IRON) -- head plate
		Kit.box(head, 0, 3, -3, 0, 3, -1, IRON2)
		Kit.box(head, -1, -3, -7, 1, -1, -5, SNOUT)
		Kit.box(head, -1, -3, -8, 1, -1, -8, NOSE)
		Kit.set(head, -1, -2, -8, DARK.color)
		Kit.set(head, 1, -2, -8, DARK.color)
		for _, sx in ipairs({ -2, 2 }) do
			Kit.set(head, sx, -3, -6, TUSK.color)
			Kit.set(head, sx, -2, -7, TUSK.color)
			Kit.set(head, sx, -1, -7, TUSK.color)
			Kit.set(head, sx, 0, -3, EYE.color, true)
		end
		b:head({ head }, 0, 7, -6, function(t: number): (number, number)
			local c = charge(t)
			-- (head down, tossing with each snort)
			return -0.3 * c + math.max(0, math.sin(t * 6)) * 0.12 * c + b:mu(t) * 0.3, 0
		end)
		for i, sx in ipairs({ -2, 2 }) do
			local ear = Kit.group()
			Kit.set(ear, 0, 0, 0, HIDE.color)
			Kit.set(ear, 0, 1, 0, BRISTLE.color)
			b:onHead({ ear }, Vector3.new(sx, 2, 0), function(t: number): CFrame
				local f = b:flick(t, i * 1.7)
				return CFrame.Angles(-f * 0.5 + charge(t) * 0.5, 0, (if sx > 0 then -1 else 1) * f * 0.3)
			end)
			b:eyelid(sx, 0, -3, if sx > 0 then 1 else -1, HIDE)
		end
		-- snorts: puffs from the nostrils
		local snort = b:fx(b.headPiece, b:v(0, -2, -9), Vector3.one * 0.3, "dust", Color3.fromRGB(235, 230, 222))
		snort.Speed = NumberRange.new(3, 5)
		snort.EmissionDirection = Enum.NormalId.Front
		b:atEmote(0.35, function() snort:Emit(6) end)
		b:atEmote(1.25, function() snort:Emit(6) end)
		b:atMount(0.5, function() snort:Emit(8) end)

		b:legs4({ x = 2.5, front = -3, hind = 4, hip = 3, len = 3, w = 2, main = LEGC, foot = HOOF,
			-- (pawing the ground with the near front hoof)
			extra = function(t: number, _, front: boolean, side: number): number
				return if front and side > 0 then charge(t) * math.sin(t * 9) * 0.6 else 0
			end })
		local tail = Kit.group()
		Kit.set(tail, 0, 0, 0, HIDE.color)
		Kit.set(tail, 0, 1, 1, HIDE.color)
		Kit.set(tail, 0, 0, 2, BRISTLE.color)
		b:tail({ tail }, 0, 7, 6, function(t: number): (number, number) return 0, math.sin(t * 9) * 0.3 end)
		local dust = b:dust(11, 7)
		b:atEmote(0.6, function() dust:Emit(5) end)
		b:atEmote(1.5, function() dust:Emit(5) end)
		return b.rig
	end

	-- Skeleton Horse: bone-white, a hollow ribcage, pale green ghost-fire eyes,
	-- mane and tail. Called: rears in a flare of ghost fire. Emote: its jaw
	-- drops off, it looks down at it, puzzled, and snaps it back on.
	function M.skeleton_horse()
		local b = K.new("skeleton_horse", { gait = 10, emoteLen = 2.4 })
		local BONE, BONE2, SHADE, HOOF = rgb(232, 226, 206), rgb(205, 198, 176), rgb(120, 114, 98), rgb(80, 78, 72)
		local GHOST, GHOST2 = glow(110, 255, 150), glow(200, 255, 215)
		local LEATHER, STRAP, IRON = rgb(84, 64, 46), rgb(56, 42, 30), rgb(110, 108, 100)
		local GREEN = Color3.fromRGB(110, 255, 150)

		b:gallop(8, 0.07)
		b:rearUp(5, 0.35)

		local body = Kit.group()
		Kit.box(body, -2, 8, 3, 2, 10, 6, BONE2) -- pelvis
		Kit.box(body, -2, 8, -6, 2, 10, -4, BONE2) -- shoulder blades
		Kit.box(body, 0, 10, -3, 0, 10, 2, BONE) -- spine
		for _, z in ipairs({ -3, -1, 1 }) do -- the hollow ribcage
			for _, sx in ipairs({ -2, 2 }) do Kit.box(body, sx, 7, z, sx, 9, z, BONE) end
			Kit.box(body, -1, 6, z, 1, 6, z, BONE)
			Kit.box(body, -1, 10, z, 1, 10, z, BONE)
		end
		Kit.box(body, 0, 6, -3, 0, 6, 1, BONE2) -- breastbone
		K.saddle(body, 2, 11, -1, 2, LEATHER, STRAP, STRAP, IRON)
		b:bodyPiece({ body })
		-- a ghost flame flickering inside the ribs
		b:fx(b.body, b:v(0, 8, -1), b:v(2, 2, 3), "fire", GREEN).Rate = 6

		local head = Kit.group()
		for i, p in ipairs({ { 0, -1 }, { 1, -1 }, { 2, -2 }, { 3, -2 }, { 4, -3 } }) do
			Kit.set(head, 0, p[1], p[2], (if i % 2 == 0 then BONE2 else BONE).color) -- neck bones
		end
		Kit.box(head, -1, 4, -7, 1, 6, -3, BONE) -- skull
		Kit.box(head, -1, 4, -9, 1, 5, -8, BONE2) -- muzzle
		Kit.set(head, 0, 5, -9, SHADE.color)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 5, -5, GHOST.color, true) end -- eye sockets
		local function jawGone(t: number): number -- 0..1: how far it's looking down at its jaw
			local p = b:emPhase(t)
			return if p then bump01(p, 0.45, 1.75) else 0
		end
		b:head({ head }, 0, 10, -6, function(t: number): (number, number)
			local p = b:emPhase(t) or 0
			local puzzled = if p > 0.9 and p < 1.5 then math.sin(t * 14) * 0.18 else 0
			return -0.35 * jawGone(t) + b:mu(t) * 0.35, puzzled
		end)
		-- the jaw: drops to the ground, lies there, flies back on
		local jaw = Kit.group()
		Kit.box(jaw, -1, 3, -9, 1, 3, -4, BONE2)
		Kit.set(jaw, -1, 3, -9, BONE.color)
		Kit.set(jaw, 1, 3, -9, BONE.color)
		b:onHead({ jaw }, Vector3.new(0, 3.5, -4), function(t: number): CFrame
			local p = b:emPhase(t)
			if not p or p < 0.15 or p > 2.0 then return CFrame.identity end
			local k
			if p < 0.55 then
				k = K.ease((p - 0.15) / 0.4)
			elseif p < 1.7 then
				k = 1 - K.bump(p, 0.55, 0.75) * 0.08
			else
				k = 1 - K.ease((p - 1.7) / 0.3)
			end
			return CFrame.new(0, -11.5 * b.V * k, -0.6 * b.V * k) * CFrame.Angles(0.55 * k, 0.4 * k, 0)
		end)
		-- the ghost-fire mane
		local mane = Kit.group()
		Kit.box(mane, 0, 1, 0, 0, 3, 0, GHOST)
		Kit.set(mane, 0, 4, 0, GHOST2.color, true)
		Kit.set(mane, 0, 5, -1, GHOST.color, true)
		Kit.set(mane, 0, 6, -2, GHOST.color, true)
		Kit.set(mane, 0, 7, -2, GHOST2.color, true)
		local manePiece = b:onHead({ mane }, Vector3.new(0, 1, 0), function(t: number): CFrame
			return CFrame.Angles(math.sin(t * 5) * 0.06, 0, math.sin(t * 7.3) * 0.05)
		end)
		local flame = b:fx(manePiece, b:v(0, 4, -1), b:v(1, 4, 2), "fire", GREEN)
		flame.Rate = 14
		b:atMount(0.25, function() flame:Emit(24) end)

		b:legs4({ x = 2, front = -5, hind = 5, hip = 8, w = 1,
			make = function(front: boolean): any
				local g = K.legGroup(8, 1, BONE, HOOF)
				Kit.set(g, 0, -4, if front then -1 else 1, BONE2.color) -- knee / hock
				return g
			end })
		local tail = Kit.group()
		Kit.set(tail, 0, 0, 0, BONE.color)
		Kit.set(tail, 0, -1, 1, BONE.color)
		Kit.set(tail, 0, -1, 2, GHOST.color, true)
		Kit.set(tail, 0, -2, 2, GHOST.color, true)
		Kit.set(tail, 0, -3, 3, GHOST2.color, true)
		local tailPiece = b:tail({ tail }, 0, 9, 7)
		b:fx(tailPiece, b:v(0, -2, 2.5), Vector3.one * 0.4, "fire", GREEN).Rate = 8
		local wisps = b:runTrail(Vector3.new(0, 0.3, 0), b:v(4, 0.5, 11), "fire", GREEN, 10)
		b:atMount(b.mountLen * 0.9, function() wisps:Emit(12) end)
		return b.rig
	end

	return M
end
