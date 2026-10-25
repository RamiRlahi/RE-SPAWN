--[[
	Mounts/Epic.luau
	Epic mounts (×1.15): elemental or magical touches, one glowing feature,
	one animated effect.
--]]

return function(K: any): { [string]: () -> any }
	local Kit, rgb, glow, glass = K.Kit, K.rgb, K.glow, K.glass
	local W = K.W
	local M = {}

	-- 0 → 1, held, → 0 over [a, b] with quick ramps.
	local function hold(x: number?, a: number, b: number, ramp: number?): number
		if not x or x <= a or x >= b then return 0 end
		local r = ramp or 0.15
		return math.min(1, (x - a) / r, (b - x) / r)
	end

	-- Giant Spider: black, a purple hourglass on its abdomen, a cluster of
	-- glowing purple eyes; the saddle rides the abdomen. It skitters, trailing
	-- silk. Called: rears, front legs waving. Emote: its eyes blink one after
	-- another, front legs raised.
	function M.giant_spider()
		local b = K.new("giant_spider", { emoteLen = 2.4 })
		local CHIT, CHIT2, MARK = rgb(30, 26, 34), rgb(46, 38, 54), rgb(84, 54, 112)
		local LEGC, LEGT = rgb(38, 32, 44), rgb(18, 14, 22)
		local EYE, FANG = glow(205, 95, 255), rgb(190, 170, 200)
		local SEAT, TRIM = rgb(74, 46, 70), rgb(44, 26, 42)
		b:rearUp(3, 0.25)

		local EYES = { { -1, 4, -6 }, { 1, 4, -6 }, { -2, 3, -5 }, { 2, 3, -5 }, { -1, 5, -5 }, { 1, 5, -5 }, { -2, 5, -4 }, { 2, 5, -4 } }
		local body = Kit.group()
		K.ellipsoid(body, 0, 4, 1.5, 3, 2.6, 3.6, function(x, y, z)
			if y >= 1 and (x == 0 and math.abs(z) <= 2 or math.abs(x) == 1 and z == 0) then return MARK end
			return if y < -1 then CHIT2 else CHIT
		end)
		K.ellipsoid(body, 0, 3.5, -4, 2.2, 1.8, 2.2, function() return CHIT2 end) -- cephalothorax
		Kit.box(body, 0, 3, -2, 0, 4, -1, CHIT2)
		Kit.set(body, 0, 3, 5, MARK.color) -- spinneret
		Kit.box(body, -2, 6, -1, 2, 6, 2, SEAT) -- (a blanket under the saddle, over the curve)
		K.saddle(body, 2, 7, -1, 2, SEAT, TRIM, TRIM)
		K.carve(body, EYES)
		b:bodyPiece({ body })
		-- the eyes: each its own piece, to blink in turn
		for i, e in ipairs(EYES) do
			local g = Kit.group()
			Kit.set(g, e[1], e[2], e[3], EYE.color, true)
			local piece = b:onBody({ g })
			b:lamp(piece, function(t: number): boolean
				local p = b:emPhase(t)
				if p and p > 0.25 then
					-- (one after another, then back again)
					local k = math.floor((p - 0.25) / 0.14)
					local idx = if k < 8 then k + 1 else 16 - k
					return idx ~= i
				end
				return (t * 1.3 + i * 0.77) % 5.3 > 0.09
			end, CHIT2.color)
		end
		local fangs = Kit.group()
		for _, sx in ipairs({ -1, 1 }) do
			Kit.set(fangs, sx, 0, 0, CHIT2.color)
			Kit.set(fangs, sx, -1, 0, FANG.color)
		end
		b:piece({ fangs }, b:at(0, 2.5, -6), function(t: number): CFrame
			return CFrame.Angles(math.sin(t * 6) * 0.12, 0, 0)
		end)
		b:crawlLegs({ zs = { -6, -4.5, -3, -1.5 }, hipX = 2, hipY = 4, reach = 5, drop = 7, main = LEGC, dark = LEGT, joint = MARK, speed = 18,
			extra = function(t: number, _, i: number): number
				return (if i == 1 then b:em(t) * 0.7 else 0) + (if i <= 2 then b:mu(t) * (0.6 + math.sin(t * 14 + i) * 0.3) else 0)
			end })
		-- silk streaming from the spinneret as it goes
		b:trail(b.body, b:v(0, 3, 5.5), 0.25, Color3.fromRGB(235, 232, 245), 0.9)
		b:dust(8, 8, Color3.fromRGB(120, 110, 125))
		return b.rig
	end

	-- Frost Wolf: white and icy blue, ice-crystal spikes along its spine,
	-- frost misting from its jaws. Emote: breathes a frost cloud that freezes
	-- the ground ahead.
	function M.frost_wolf()
		local ICE = glass(170, 225, 255, 0.15)
		local b
		local breathe = function(t: number): number return hold(b:emPhase(t), 0.2, 1.8) end
		b = K.wolf("frost_wolf", {
			fur = rgb(232, 240, 246), fur2 = rgb(200, 222, 236), pale = rgb(250, 252, 255), dark = rgb(80, 110, 140),
			eye = glow(130, 225, 255), seat = rgb(60, 96, 140), trim = rgb(40, 64, 96), dustColor = Color3.fromRGB(220, 235, 245),
		}, {
			howl = false,
			-- (head low and jaws open for the frost breath)
			headExtra = function(t: number): number return -breathe(t) * 0.2 end,
			jaw = function(t: number): number return breathe(t) * 0.4 end,
			body = function(g: any)
				for _, s in ipairs({ { 0, 11, -6 }, { 0, 12, -5 }, { 0, 11, -4 }, { 0, 10, 3 }, { 0, 11, 4 }, { 0, 10, 5 } }) do
					Kit.set(g, s[1], s[2], s[3], ICE.color, nil, ICE.alpha)
				end
				Kit.set(g, -3, 9, -5, ICE.color, nil, ICE.alpha)
				Kit.set(g, 3, 9, -5, ICE.color, nil, ICE.alpha)
			end,
		})
		b.emoteLen = 2.6
		local V = b.V
		local mist = b:fx(b.headPiece, b:v(0, 0.5, -9), Vector3.one * 0.4, "frost", Color3.fromRGB(190, 240, 255))
		mist.Rate = 4
		mist.Speed = NumberRange.new(0.5, 1.5)
		mist.EmissionDirection = Enum.NormalId.Front
		local cloud = b:emitter(b.headPiece, b:v(0, 0.5, -9), Vector3.one * 0.3, {
			Texture = K.SMOKE, Color = ColorSequence.new(Color3.fromRGB(240, 250, 255), Color3.fromRGB(150, 210, 255)),
			LightEmission = 0.6, Size = K.seq(0.5, 2.4), Transparency = K.seq(0.3, 1), Lifetime = NumberRange.new(0.6, 0.9),
			Speed = NumberRange.new(10, 14), SpreadAngle = Vector2.new(18, 18), EmissionDirection = Enum.NormalId.Front,
			Drag = 2, RotSpeed = NumberRange.new(-90, 90),
		})
		b:whileEmote(cloud, 45, 0.3, 1.5)
		-- the ground freezing where it breathes: a patch of ice rising out of the floor
		local patch = Kit.group()
		for x = -3, 3 do
			for z = -2, 2 do
				if math.abs(x) + math.abs(z) < 5 then Kit.set(patch, x, 0, z, Color3.fromRGB(190, 235, 255), nil, 0.25) end
			end
		end
		for _, s in ipairs({ { -2, 1, -1 }, { 1, 1, 1 }, { 0, 1, -2 }, { 2, 1, 0 }, { 1, 2, 1 }, { -1, 1, 1 } }) do Kit.set(patch, s[1], s[2], s[3], Color3.fromRGB(150, 220, 255), true) end
		b:piece({ patch }, b:at(0, -2.2, -16), function(t: number): CFrame
			return CFrame.new(0, 2.2 * V * hold(b:emPhase(t), 0.6, 2.5, 0.3), 0)
		end)
		-- (wolf head: dips and opens its jaws while it breathes)
		b:move(function(t: number): CFrame
			local k = breathe(t)
			if k == 0 then return CFrame.identity end
			local front = Vector3.new(0, 0, -4 * V)
			return CFrame.new(front) * CFrame.Angles(-0.05 * k, 0, 0) * CFrame.new(-front)
		end)
		local burst = b:fx(b.body, Vector3.new(0, 0.3, 0), b:v(6, 0.5, 12), "frost", Color3.fromRGB(190, 240, 255))
		burst.Rate = 0
		b:atMount(b.mountLen * 0.9, function() burst:Emit(30) end)
		return b.rig
	end

	-- Dire Bear: a huge brown bear, bone shoulder armour carved with a glowing
	-- rune, a fur-lined saddle. Called: rears with a growl. Emote: rears up on
	-- its hind legs and roars.
	function M.dire_bear()
		local b = K.new("dire_bear", { gait = 9, emoteLen = 2.6 })
		local FUR, FUR2, MUZ, DARK = rgb(92, 62, 40), rgb(112, 78, 52), rgb(152, 116, 80), rgb(40, 28, 20)
		local BONE, BONE2 = rgb(226, 216, 190), rgb(196, 184, 156)
		local RUNE, EYE = glow(110, 225, 255), glow(255, 170, 60)
		local SEAT, FURTRIM, STRAP = rgb(104, 62, 34), rgb(226, 210, 182), rgb(62, 38, 22)
		local V = b.V
		local roar = function(t: number): number return hold(b:emPhase(t), 0.15, 2.3, 0.35) end
		b:gallop(7, 0.07)
		b:rearUp(4, 0.3)
		b:move(function(t: number): CFrame
			local a = roar(t) * 0.5
			if a == 0 then return CFrame.identity end
			local hind = Vector3.new(0, 0, 5 * V)
			return CFrame.new(hind) * CFrame.Angles(a, 0, 0) * CFrame.new(-hind)
		end)

		local body = Kit.group()
		Kit.box(body, -3, 4, -6, 3, 9, 6, FUR)
		Kit.box(body, -3, 4, -6, 3, 4, 6, FUR2)
		Kit.box(body, -2, 10, -6, 2, 10, -2, FUR) -- hump
		Kit.box(body, -1, 11, -5, 1, 11, -3, FUR2)
		for _, s in ipairs({ -1, 1 }) do -- bone pauldrons
			Kit.box(body, 4 * s, 7, -6, 4 * s, 10, -3, BONE)
			Kit.box(body, math.min(3 * s, 4 * s), 11, -6, math.max(3 * s, 4 * s), 11, -3, BONE2)
			Kit.set(body, 4 * s, 12, -5, BONE.color)
			Kit.set(body, 4 * s, 13, -5, BONE.color)
			Kit.set(body, 4 * s, 12, -4, BONE.color)
		end
		K.saddle(body, 3, 10, -1, 2, SEAT, STRAP, STRAP, rgb(96, 96, 104))
		Kit.box(body, -3, 10, -2, 3, 10, -2, FURTRIM) -- fur lining
		for _, sx in ipairs({ -4, 4 }) do Kit.box(body, sx, 10, -1, sx, 10, 2, FURTRIM) end
		b:bodyPiece({ body })
		-- the rune carved in each pauldron, pulsing
		local rune = Kit.group()
		for _, s in ipairs({ -1, 1 }) do
			for _, c in ipairs({ { 9, -5 }, { 8, -4 }, { 9, -4 }, { 10, -4 }, { 8, -5 } }) do Kit.set(rune, 5 * s, c[1], c[2], RUNE.color, true) end
		end
		local runePiece = b:onBody({ rune })
		b:glowUp(runePiece, function(t: number): number return 0.25 + math.sin(t * 2.6) * 0.25 + roar(t) * 0.5 end)

		local head = Kit.group()
		Kit.box(head, -2, -2, -4, 2, 2, 0, FUR)
		Kit.box(head, -1, -2, -7, 1, 0, -5, MUZ)
		Kit.box(head, -1, 0, -8, 1, 0, -8, DARK)
		Kit.set(head, 0, -1, -8, DARK.color)
		for _, sx in ipairs({ -2, 2 }) do Kit.set(head, sx, 1, -3, EYE.color, true) end
		b:head({ head }, 0, 8, -7, function(t: number): (number, number)
			return roar(t) * 0.55 + b:mu(t) * 0.25, 0
		end)
		local jaw = Kit.group()
		Kit.box(jaw, -1, -3, -7, 1, -3, -2, DARK)
		Kit.set(jaw, -1, -2, -7, BONE.color)
		Kit.set(jaw, 1, -2, -7, BONE.color)
		b:onHead({ jaw }, Vector3.new(0, -2.5, -2), function(t: number): CFrame
			return CFrame.Angles(-(roar(t) * 0.6 + b:mu(t) * 0.35), 0, 0)
		end)
		for i, sx in ipairs({ -2, 2 }) do
			local ear = Kit.group()
			Kit.set(ear, 0, 0, 0, FUR2.color)
			Kit.set(ear, 0, 1, 0, DARK.color)
			b:onHead({ ear }, Vector3.new(sx, 3, -1), function(t: number): CFrame
				local f = b:flick(t, i * 1.1)
				return CFrame.Angles(-f * 0.4 - roar(t) * 0.5, 0, 0)
			end)
			b:eyelid(sx, 1, -3, if sx > 0 then 1 else -1, FUR)
		end
		local breath = b:fx(b.headPiece, b:v(0, -1, -9), Vector3.one * 0.4, "dust", Color3.fromRGB(235, 230, 222))
		breath.Speed = NumberRange.new(5, 8)
		breath.EmissionDirection = Enum.NormalId.Front
		b:atEmote(0.55, function() breath:Emit(14) end)
		b:atMount(0.4, function() breath:Emit(8) end)

		b:legs4({ x = 2, front = -4, hind = 4, hip = 4, len = 4, w = 3, main = FUR, foot = DARK,
			extra = function(t: number, _, front: boolean): number
				return if front then roar(t) * (0.9 + math.sin(t * 9) * 0.35) else 0
			end })
		local tail = Kit.group()
		Kit.set(tail, 0, 0, 0, FUR2.color)
		Kit.set(tail, 0, 0, 1, FUR2.color)
		b:tail({ tail }, 0, 8, 7)
		b:dust(13, 7)
		return b.rig
	end

	-- Flame Ram: a charcoal ram, curled horns glowing orange-red, fire on its
	-- hooves. Emote: its horns flare up like torches.
	function M.flame_ram()
		local b = K.new("flame_ram", { gait = 11, emoteLen = 2.4 })
		local WOOL, WOOL2, SKIN, FACE, FACE2, DARK = rgb(58, 54, 54), rgb(80, 74, 72), rgb(44, 40, 40), rgb(70, 64, 62), rgb(92, 84, 80), rgb(24, 20, 20)
		local HOOF, HORN, HORNTIP, EYE = glow(255, 110, 30), glow(255, 116, 36), glow(255, 210, 100), glow(255, 150, 60)
		local SEAT, TRIM = rgb(112, 40, 30), rgb(62, 24, 18)
		local FLAME = Color3.fromRGB(255, 120, 30)
		local flare = function(t: number): number return hold(b:emPhase(t), 0.2, 2.1, 0.3) end
		b:gallop(5, 0.07)
		b:rearUp(4, 0.3)

		local body = Kit.group()
		Kit.box(body, -2, 3, -5, 2, 7, 5, SKIN)
		for x = -3, 3 do
			for y = 4, 8 do
				for z = -5, 5 do
					if math.abs(x) == 3 and (y == 8 or y == 4) then continue end
					Kit.set(body, x, y, z, ((x + y + z) % 3 == 0 and WOOL2 or WOOL).color)
				end
			end
		end
		K.saddle(body, 2, 9, -1, 2, SEAT, TRIM, TRIM)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -1, -1, -4, 1, 2, 0, FACE)
		Kit.box(head, -1, -1, -6, 1, 0, -5, FACE2)
		Kit.set(head, 0, 0, -7, DARK.color)
		Kit.box(head, -1, 3, -3, 1, 3, -1, WOOL2)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 1, -3, EYE.color, true) end
		b:head({ head }, 0, 7, -6, function(t: number): (number, number)
			local f = flare(t)
			return f * 0.3 + math.sin(t * 10) * 0.05 * f + b:mu(t) * 0.3, 0
		end)
		-- the curled horns: a piece of their own, to flare
		local horns = Kit.group()
		local curl = { { 2, 2, -2 }, { 2, 3, -1 }, { 3, 3, 0 }, { 3, 2, 1 }, { 3, 1, 1 }, { 3, 0, 0 }, { 3, 0, -1 }, { 2, -1, -2 } }
		for _, s in ipairs({ -1, 1 }) do
			for i, c in ipairs(curl) do
				local p = if i >= #curl - 1 then HORNTIP else HORN
				Kit.set(horns, c[1] * s, c[2], c[3], p.color, true)
			end
		end
		local hornPiece = b:onHead({ horns }, Vector3.zero, function(): CFrame return CFrame.identity end)
		b:glowUp(hornPiece, function(t: number): number return math.max(flare(t), b:mu(t)) * 0.8 end, Color3.fromRGB(255, 245, 200))
		for _, s in ipairs({ -1, 1 }) do
			local torch = b:fx(hornPiece, b:v(3 * s, 2, 0), b:v(1, 2, 2), "fire", FLAME)
			torch.Rate = 3
			b:every(function(t: number) torch.Rate = 3 + flare(t) * 45 end)
		end

		local legs = b:legs4({ x = 1.5, front = -4, hind = 4, hip = 3, len = 3, w = 2, main = SKIN, foot = HOOF })
		for _, lp in ipairs(legs) do
			local f = b:fx(lp, b:v(0, -3, 0), b:v(1.5, 0.5, 1.5), "fire", FLAME)
			f.Rate = 10
		end
		local tail = Kit.group()
		Kit.set(tail, 0, 0, 0, WOOL2.color)
		Kit.set(tail, 0, 0, 1, WOOL2.color)
		b:tail({ tail }, 0, 6, 6)
		b:runTrail(Vector3.new(0, 0.4, 0), b:v(5, 1, 10), "embers", FLAME, 16)
		b:dust(10, 6)
		return b.rig
	end

	-- Venom Scorpion: low and wide, toxic green and black, its glowing sting
	-- arched over the rider. Emote: the sting curls forward and drips venom
	-- into a glowing puddle.
	function M.venom_scorpion()
		local b = K.new("venom_scorpion", { emoteLen = 2.6 })
		local CHIT, PLATE, PLATE2, LEG, DARK = rgb(26, 32, 22), rgb(46, 68, 30), rgb(34, 48, 26), rgb(30, 38, 24), rgb(14, 18, 12)
		local STING, STING2, EYE = glow(140, 255, 60), glow(210, 255, 150), glow(170, 255, 90)
		local SEAT, TRIM = rgb(60, 44, 30), rgb(36, 26, 18)
		local VENOM = Color3.fromRGB(150, 255, 60)
		local V = b.V
		local drip = function(t: number): number return hold(b:emPhase(t), 0.15, 2.4, 0.3) end
		b:rearUp(4, 0.12)

		local body = Kit.group()
		Kit.box(body, -3, 2, -4, 3, 3, 4, CHIT)
		for x = -3, 3 do
			for z = -4, 4 do Kit.set(body, x, 4, z, (if z % 2 == 0 then PLATE else PLATE2).color) end
		end
		Kit.box(body, -2, 2, -6, 2, 3, -5, CHIT)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(body, sx, 4, -5, EYE.color, true) end
		K.saddle(body, 2, 5, -1, 2, SEAT, TRIM, TRIM)
		b:bodyPiece({ body })

		-- pincers
		for _, s in ipairs({ -1, 1 }) do
			local claw = Kit.group()
			Kit.set(claw, 0, 0, 0, PLATE.color)
			Kit.set(claw, 0, 0, -1, PLATE.color)
			Kit.set(claw, s, 0, -2, PLATE.color)
			Kit.box(claw, math.min(s, 2 * s), 0, -4, math.max(s, 2 * s), 1, -3, PLATE2)
			Kit.set(claw, s, 0, -5, DARK.color)
			Kit.set(claw, 2 * s, 1, -5, DARK.color)
			b:piece({ claw }, b:at(3 * s, 3, -5), function(t: number): CFrame
				local snap = if (t * 0.9 + s) % 3 < 0.25 then 0.25 else 0
				return CFrame.Angles(b:mu(t) * 0.5, s * (math.sin(t * 2) * 0.12 + snap + b:mu(t) * 0.4), 0)
			end)
		end

		-- the tail, arching up and over the rider
		local arc = { { 0, 0 }, { 1, 1 }, { 2, 2 }, { 3, 2 }, { 4, 2 }, { 5, 2 }, { 6, 1 }, { 7, 0 }, { 8, -1 }, { 9, -2 }, { 9, -3 }, { 9, -4 }, { 9, -5 } }
		local tail = Kit.group()
		for i, c in ipairs(arc) do
			local p = if i % 2 == 0 then PLATE else CHIT
			if i <= 6 then Kit.box(tail, -1, c[1], c[2], 1, c[1] + 1, c[2], p) else Kit.box(tail, 0, c[1], c[2], 0, c[1] + 1, c[2], p) end
		end
		Kit.set(tail, 0, 9, -6, STING.color, true)
		Kit.set(tail, 0, 8, -7, STING.color, true)
		Kit.set(tail, 0, 7, -7, STING2.color, true)
		local tailPiece = b:piece({ tail }, b:at(0, 4, 4), function(t: number, move: number): CFrame
			return CFrame.Angles(math.sin(t * 1.8) * 0.06 - drip(t) * 0.15 + math.sin(t * 9) * 0.03 * move, math.sin(t * 1.1) * 0.08, 0)
		end)
		local venom = b:fx(tailPiece, b:v(0, 6.6, -7), Vector3.one * 0.3, "drip", VENOM)
		venom.Rate = 3
		b:every(function(t: number) venom.Rate = 3 + drip(t) * 22 end)
		-- the puddle of venom it drips
		local puddle = Kit.group()
		for x = -2, 2 do
			for z = -2, 2 do
				if math.abs(x) + math.abs(z) <= 3 then Kit.set(puddle, x, 0, z, (if (x + z) % 2 == 0 then STING else STING2).color, true) end
			end
		end
		b:piece({ puddle }, b:at(0, -1.2, -3), function(t: number): CFrame
			return CFrame.new(0, 1.2 * V * hold(b:emPhase(t), 0.9, 2.5, 0.3), 0)
		end)

		b:crawlLegs({ zs = { -3, -1, 1, 3 }, hipX = 3, hipY = 3, reach = 3, drop = 4, main = LEG, dark = DARK, speed = 18 })
		b:dust(9, 8, Color3.fromRGB(110, 130, 80))
		return b.rig
	end

	-- Shadow Panther: sleek and black, violet eyes, smoky purple voxels
	-- trailing off it. Emote: melts into shadow and reforms.
	function M.shadow_panther()
		local b = K.new("shadow_panther", { gait = 11, emoteLen = 2.6 })
		local FUR, FUR2, DARK = rgb(22, 18, 28), rgb(36, 30, 46), rgb(12, 10, 16)
		local EYE, SEAT, TRIM = glow(190, 110, 255), rgb(54, 36, 76), rgb(30, 20, 44)
		local SMOKE = Color3.fromRGB(130, 70, 220)
		local V = b.V
		local melt = function(t: number): number return hold(b:emPhase(t), 0.2, 2.1, 0.45) end
		b:gallop(7, 0.09)
		b:rearUp(4, 0.25)
		b:move(function(t: number): CFrame
			local m = melt(t)
			return if m == 0 then CFrame.identity else CFrame.new(0, -0.5 * m, 0)
		end)

		local body = Kit.group()
		Kit.box(body, -2, 5, -7, 2, 8, 6, FUR)
		Kit.box(body, -2, 5, -7, 2, 5, 6, FUR2)
		Kit.box(body, -2, 9, -7, 2, 9, -5, FUR)
		K.saddle(body, 2, 9, -1, 2, SEAT, TRIM, TRIM)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -1, -2, -2, 1, 0, 0, FUR)
		Kit.box(head, -2, -1, -5, 2, 2, -2, FUR)
		Kit.box(head, -1, -1, -7, 1, 0, -6, FUR2)
		Kit.set(head, 0, 0, -8, DARK.color)
		for _, sx in ipairs({ -2, 2 }) do Kit.set(head, sx, 1, -4, EYE.color, true) end
		b:head({ head }, 0, 8, -7, function(t: number): (number, number) return b:mu(t) * 0.2, 0 end)
		local jaw = Kit.group()
		Kit.box(jaw, -1, -2, -7, 1, -2, -3, DARK)
		b:onHead({ jaw }, Vector3.new(0, -1.5, -3), function(t: number): CFrame return CFrame.Angles(-b:mu(t) * 0.45, 0, 0) end)
		for i, sx in ipairs({ -2, 2 }) do
			local ear = Kit.group()
			Kit.set(ear, 0, 0, 0, FUR.color)
			Kit.set(ear, 0, 1, 0, DARK.color)
			b:onHead({ ear }, Vector3.new(sx, 3, -2), function(t: number): CFrame
				local f = b:flick(t, i * 1.5)
				return CFrame.Angles(-f * 0.5 + b:mu(t) * 0.6, 0, 0)
			end)
			b:eyelid(sx, 1, -4, if sx > 0 then 1 else -1, FUR)
		end
		b:legs4({ x = 1.5, front = -5, hind = 4, hip = 5, len = 5, w = 2, main = FUR, foot = DARK })
		local tail = Kit.group()
		for i = 0, 8 do
			local y = math.floor(i * 0.25) + (if i > 6 then i - 6 else 0)
			Kit.set(tail, 0, y, i, (if i >= 7 then FUR2 else FUR).color)
		end
		b:tail({ tail }, 0, 7, 7)

		-- smoky voxels peeling off and drifting back, fading
		local drift = {}
		local spots = { { -2, 8, -3 }, { 2, 7, 0 }, { 0, 9, 3 }, { -2, 6, 4 }, { 2, 8, -5 }, { 1, 6, 2 } }
		for i, s in ipairs(spots) do
			local g = Kit.group()
			Kit.set(g, 0, 0, 0, Color3.fromRGB(96, 52, 170), true)
			local piece = b:piece({ g }, b:at(s[1], s[2], s[3]), function(t: number, move: number): CFrame
				local k = (t * (0.6 + move * 0.6) + i / #spots) % 1
				return CFrame.new(s[1] * 0.3 * V * k, k * 2.5 * V, k * (5 + move * 6) * V)
			end)
			drift[i] = { piece = piece, i = i }
		end
		b:every(function(t: number, move: number)
			for _, d in ipairs(drift) do
				local k = (t * (0.6 + move * 0.6) + d.i / #spots) % 1
				local p = d.piece.parts[1]
				if p then p.LocalTransparencyModifier = math.max(k, melt(t)) end
			end
		end)
		local smoke = b:fx(b.body, b:v(0, 7, 0), b:v(4, 3, 12), "smoke", SMOKE)
		smoke.Rate = 5
		b:every(function(t: number) smoke.Rate = 5 + melt(t) * 40 end)
		-- melting into shadow (every brick fades), reforming
		local bodyParts = {}
		for _, p in ipairs(b.rig.allParts) do table.insert(bodyParts, p) end
		b:fade(bodyParts, function(t: number): number return melt(t) * 0.95 end)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(4, 1, 12), "smoke", SMOKE, 12)
		b:dust(12, 5, Color3.fromRGB(80, 60, 110))
		return b.rig
	end

	-- Crystal Stag: tall, antlers of glowing cyan crystal, crystal shards on
	-- its flanks, motes of crystal circling the antlers. Emote: its antlers
	-- chime and blaze brighter.
	function M.crystal_stag()
		local b = K.new("crystal_stag", { gait = 10, emoteLen = 2.4 })
		local COAT, COAT2, CREAM, DARK, HOOF = rgb(150, 120, 92), rgb(126, 98, 72), rgb(228, 214, 190), rgb(46, 34, 26), rgb(60, 50, 44)
		local SHARD = glass(170, 230, 245, 0.2)
		local ANT, ANT2 = glow(90, 235, 255), glow(200, 250, 255)
		local SEAT, TRIM = rgb(90, 60, 40), rgb(60, 38, 24)
		local chime = function(t: number): number return hold(b:emPhase(t), 0.15, 2.2, 0.3) end
		b:gallop(7, 0.08)
		b:rearUp(4, 0.35)

		local body = Kit.group()
		Kit.box(body, -2, 6, -5, 2, 9, 5, COAT)
		Kit.box(body, -2, 6, -5, 2, 6, 5, CREAM)
		Kit.box(body, -1, 7, 5, 1, 8, 5, CREAM)
		for _, s in ipairs({ { -3, 8, -2 }, { 3, 7, 1 }, { -3, 7, 2 }, { 3, 9, -3 }, { 0, 10, 4 }, { -3, 9, -4 } }) do
			Kit.set(body, s[1], s[2], s[3], SHARD.color, nil, SHARD.alpha)
		end
		K.saddle(body, 2, 10, -1, 2, SEAT, TRIM, TRIM)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -1, 0, -2, 1, 4, 0, COAT)
		Kit.box(head, -1, 4, -5, 1, 6, -2, COAT)
		Kit.box(head, -1, 4, -7, 1, 5, -6, CREAM)
		Kit.set(head, 0, 5, -8, DARK.color)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 6, -4, DARK.color) end
		b:head({ head }, 0, 9, -5, function(t: number): (number, number)
			local c = chime(t)
			return b:mu(t) * 0.3 + c * 0.1, math.sin(t * 6) * 0.16 * c
		end)
		for i, sx in ipairs({ -2, 2 }) do
			local ear = Kit.group()
			Kit.set(ear, 0, 0, 0, COAT2.color)
			b:onHead({ ear }, Vector3.new(sx, 6, -2), function(t: number): CFrame
				local f = b:flick(t, i * 1.4)
				return CFrame.Angles(-f * 0.5, 0, (if sx > 0 then -1 else 1) * f * 0.4)
			end)
		end
		local ant = Kit.group()
		local trunk = { { 1, 7, -3 }, { 2, 8, -3 }, { 2, 9, -3 }, { 3, 10, -2 }, { 3, 11, -2 }, { 4, 12, -1 } }
		local tines = { { 2, 10, -4 }, { 3, 12, -3 }, { 4, 13, -2 }, { 5, 13, 0 }, { 1, 9, -2 } }
		for _, s in ipairs({ -1, 1 }) do
			for _, c in ipairs(trunk) do Kit.set(ant, c[1] * s, c[2], c[3], ANT.color, true) end
			for _, c in ipairs(tines) do Kit.set(ant, c[1] * s, c[2], c[3], ANT2.color, true) end
		end
		local antPiece = b:onHead({ ant }, Vector3.zero, function(): CFrame return CFrame.identity end)
		b:glowUp(antPiece, function(t: number): number return chime(t) * (0.6 + math.sin(t * 12) * 0.3) end)
		local chimes = b:fx(antPiece, b:v(0, 11, -2), b:v(9, 4, 3), "stars", Color3.fromRGB(170, 240, 255))
		b:whileEmote(chimes, 30, 0.2, 2.1)
		W.orbit(b.rig, b.headHome * b:at(0, 12, -2), 4, 4 * b.V, 0.8, b.V, function()
			return W.shard(SHARD, ANT2)
		end, 0.2, 0.3)

		b:legs4({ x = 1.5, front = -4, hind = 4, hip = 6, len = 6, w = 1, main = COAT2, foot = HOOF })
		local tail = Kit.group()
		Kit.set(tail, 0, 0, 0, CREAM.color)
		Kit.set(tail, 0, 1, 0, CREAM.color)
		b:tail({ tail }, 0, 9, 6, function(t: number): (number, number) return -0.3 + math.sin(t * 7) * 0.2, 0 end)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(4, 1, 10), "stars", Color3.fromRGB(170, 235, 255), 12)
		b:dust(10, 5)
		return b.rig
	end

	-- Magma Lizard: low and long, black rock skin split by glowing lava cracks
	-- that pulse. It sprawls along, body swinging. Called: two push-ups. Emote:
	-- the cracks pulse bright and vent steam.
	function M.magma_lizard()
		local b = K.new("magma_lizard", { emoteLen = 2.6 })
		local ROCK, ROCK2, BELLY = rgb(36, 30, 30), rgb(54, 46, 44), rgb(62, 42, 34)
		local LAVA, EYE = glow(255, 110, 30), glow(255, 200, 60)
		local SEAT, TRIM, TONGUE = rgb(82, 40, 26), rgb(50, 24, 16), rgb(205, 45, 55)
		local V = b.V
		local vent = function(t: number): number return hold(b:emPhase(t), 0.15, 2.4, 0.3) end
		-- sprawling swing, and the push-ups when called
		b:move(function(t: number, move: number): CFrame
			local wig = math.sin(t * 14) * 0.08 * math.min(move, 1.2)
			local s = b:since(t)
			local up = if s < b.mountLen then K.bump(s % (b.mountLen / 2), 0, b.mountLen / 2) * 0.35 else 0
			return CFrame.new(0, up + math.sin(t * 40) * 0.02 * vent(t), 0) * CFrame.Angles(-up * 0.12, wig, 0)
		end)

		local CRACKS = {}
		for _, c in ipairs({ { 0, 5, -6 }, { 0, 5, -5 }, { 1, 5, -4 }, { 1, 5, -3 }, { -1, 5, 3 }, { -1, 5, 4 }, { 0, 5, 5 } }) do table.insert(CRACKS, c) end
		for _, sx in ipairs({ -2, 2 }) do
			for _, c in ipairs({ { 4, -4 }, { 4, -3 }, { 3, -2 }, { 4, 1 }, { 4, 2 }, { 5, 4 } }) do table.insert(CRACKS, { sx, c[1], c[2] }) end
		end
		local body = Kit.group()
		Kit.box(body, -2, 3, -6, 2, 5, 6, ROCK)
		Kit.box(body, -2, 3, -6, 2, 3, 6, BELLY)
		for _, s in ipairs({ { -2, 6, -5 }, { 1, 6, -4 }, { 0, 6, 4 }, { -1, 6, 5 }, { 2, 6, 3 } }) do Kit.set(body, s[1], s[2], s[3], ROCK2.color) end
		K.saddle(body, 2, 6, -1, 2, SEAT, TRIM, TRIM)
		K.carve(body, CRACKS)
		b:bodyPiece({ body })
		local cracks = Kit.group()
		for _, c in ipairs(CRACKS) do Kit.set(cracks, c[1], c[2], c[3], LAVA.color, true) end
		local crackPiece = b:onBody({ cracks })
		b:glowUp(crackPiece, function(t: number): number
			return 0.2 + math.sin(t * 2.4) * 0.2 + vent(t) * (0.5 + math.sin(t * 9) * 0.3)
		end, Color3.fromRGB(255, 235, 150))
		local steam = b:emitter(b.body, b:v(0, 6, 0), b:v(4, 0.5, 11), {
			Texture = K.SMOKE, Color = ColorSequence.new(Color3.fromRGB(240, 236, 230)), LightEmission = 0.2,
			Size = K.seq(0.4, 1.8), Transparency = K.seq(0.35, 1), Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(5, 8), SpreadAngle = Vector2.new(12, 12), EmissionDirection = Enum.NormalId.Top,
			RotSpeed = NumberRange.new(-80, 80),
		})
		b:whileEmote(steam, 40, 0.4, 2.2)

		local head = Kit.group()
		Kit.box(head, -2, -1, -4, 2, 1, 0, ROCK)
		Kit.box(head, -1, -1, -7, 1, 0, -5, ROCK2)
		for _, sx in ipairs({ -2, 2 }) do
			Kit.set(head, sx, 1, -2, EYE.color, true)
			Kit.set(head, sx, 2, -2, ROCK2.color)
		end
		b:head({ head }, 0, 4, -7, function(t: number): (number, number) return b:mu(t) * 0.25 + vent(t) * 0.15, 0 end)
		local jaw = Kit.group()
		Kit.box(jaw, -1, -2, -7, 1, -2, -1, BELLY)
		b:onHead({ jaw }, Vector3.new(0, -1.5, -1), function(t: number): CFrame return CFrame.Angles(-b:mu(t) * 0.4, 0, 0) end)
		local tongue = Kit.group()
		Kit.set(tongue, 0, -1, -6, TONGUE.color)
		Kit.set(tongue, 0, -1, -7, TONGUE.color)
		b:onHead({ tongue }, Vector3.zero, function(t: number): CFrame
			local out = (t % 3.1) < 0.22
			return CFrame.new(0, 0.45 * V, if out then -2.4 * V else 0)
		end)
		b:crawlLegs({ zs = { -4, 4 }, hipX = 2, hipY = 3, reach = 2, drop = 4, main = ROCK, dark = ROCK2, speed = 14 })
		-- the tail: segments swinging in a wave
		for i = 1, 4 do
			local w = ({ 2, 1, 1, 0 })[i]
			local g = Kit.group()
			Kit.box(g, -w, -1, 0, w, 0, 2, ROCK)
			if i == 2 then Kit.set(g, 0, 0, 1, LAVA.color, true) end
			b:piece({ g }, b:at(0, 4, 7 + (i - 1) * 3), function(t: number, move: number): CFrame
				local a = math.sin(t * 7 - i * 0.8) * 0.12 * i * (0.4 + math.min(move, 1.2))
				return CFrame.new(math.sin(t * 7 - i * 0.8) * 0.1 * i * V * (0.4 + move), 0, 0) * CFrame.Angles(0, a, 0)
			end)
		end
		b:runTrail(Vector3.new(0, 0.4, 0), b:v(5, 1, 12), "embers", Color3.fromRGB(255, 120, 40), 16)
		b:dust(12, 6, Color3.fromRGB(80, 70, 66))
		return b.rig
	end

	-- Magician's Carpet: a floating purple-and-gold rug, tasselled corners, a
	-- gold medallion glowing at its heart, sparkles drifting off it; sat on
	-- cross-legged. Called: a spin. Emote: a loop-the-loop.
	function M.magic_carpet()
		local b = K.new("magic_carpet", { emoteLen = 2.4 })
		local PURP, PURP2 = rgb(92, 40, 140), rgb(122, 62, 172)
		local GOLD, GOLD2, GEM = rgb(226, 176, 62), rgb(250, 214, 110), glow(255, 215, 90)
		local V = b.V
		local yTop = W.RideData.BackHeight("magic_carpet") - 0.5 * V
		local HX, HZ = 6, 9
		local function paint(x: number, z: number): any
			local e = math.min(HX - math.abs(x), HZ - math.abs(z))
			if e == 0 then return GOLD end
			if e == 2 and (x + z) % 2 == 0 then return GOLD2 end
			if x == 0 and z == 0 then return GEM end
			if math.abs(x) + math.abs(z) * 0.7 < 3 then return GOLD end
			if (x + z) % 4 == 0 then return PURP2 end
			return PURP
		end
		b:spinUp(0.6)
		-- the loop-the-loop, round the rider
		local pivot = Vector3.new(0, yTop + 1.6, 0)
		b:move(function(t: number): CFrame
			local p = b:emPhase(t)
			if not p or p < 0.2 or p > 1.8 then return CFrame.identity end
			local a = K.ease((p - 0.2) / 1.6) * math.pi * 2
			return CFrame.new(pivot) * CFrame.Angles(a, 0, 0) * CFrame.new(-pivot)
		end)
		local ripple = W.runner(3, 3)
		local function wave(zc: number, t: number, move: number): CFrame
			local ph = ripple(t, move) + zc * 0.35
			local amp = (0.03 + 0.09 * math.abs(zc) / HZ) * (0.6 + math.min(move, 1.2) * 0.6)
			return W.hover(t, move) * CFrame.new(0, math.sin(ph) * amp, 0) * CFrame.Angles(math.cos(ph) * amp * 0.35, 0, 0)
		end
		local rear, mid
		for si, s in ipairs({ { -9, -7 }, { -6, -4 }, { -3, 3 }, { 4, 6 }, { 7, 9 } }) do
			local zc = (s[1] + s[2]) / 2
			local g = Kit.group()
			for x = -HX, HX do
				for z = s[1], s[2] do
					local p = paint(x, z)
					Kit.set(g, x, 0, z - zc, p.color, p.neon)
				end
			end
			local piece = b:piece({ g }, CFrame.new(0, yTop, zc * V), function(t: number, move: number): CFrame return wave(zc, t, move) end)
			if si == 5 then rear = piece end
			if si == 3 then mid = piece end
		end
		b.body = mid
		-- tassels bobbing at the corners
		for i, c in ipairs({ { -HX, -HZ }, { HX, -HZ }, { -HX, HZ }, { HX, HZ } }) do
			local g = Kit.group()
			Kit.set(g, 0, 0, 0, GOLD2.color)
			Kit.set(g, 0, -1, 0, GOLD.color)
			Kit.set(g, 0, -2, 0, GOLD2.color)
			b:piece({ g }, CFrame.new(c[1] * V, yTop - 0.6 * V, c[2] * V), function(t: number, move: number): CFrame
				return wave(c[2], t, move) * CFrame.Angles(math.sin(t * 3 + i) * 0.25, 0, math.sin(t * 2.3 + i) * 0.2)
			end)
		end
		b:fx(mid, Vector3.new(0, 0.6, 0), Vector3.new(HX * 2 * V, 0.4, 7 * V), "stars", Color3.fromRGB(255, 215, 120))
		for _, x in ipairs({ -HX, HX }) do b:trail(rear, Vector3.new(x * V, 0, 2 * V), 0.45, Color3.fromRGB(255, 200, 80), 0.6) end
		local sparkle = b:fx(mid, Vector3.new(0, 0.5, 0), Vector3.new(HX * 2 * V, 0.4, HZ * 2 * V), "stars", Color3.fromRGB(255, 230, 150))
		sparkle.Rate = 0
		b:atMount(0.2, function() sparkle:Emit(30) end)
		b:atEmote(0.25, function() sparkle:Emit(30) end)
		return b.rig
	end

	return M
end
