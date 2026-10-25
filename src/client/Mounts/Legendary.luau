--[[
	Mounts/Legendary.luau
	Legendary mounts (×1.3): armoured or elemental, one strong glowing element,
	a heavy ornate saddle, and a constant aura of particles clinging on.
--]]

return function(K: any): { [string]: () -> any }
	local Kit, rgb, glow, glass = K.Kit, K.rgb, K.glow, K.glass
	local W = K.W
	local M = {}

	local function hold(x: number?, a: number, b: number, ramp: number?): number
		if not x or x <= a or x >= b then return 0 end
		local r = ramp or 0.15
		return math.min(1, (x - a) / r, (b - x) / r)
	end

	-- A bat-like wing lying flat (XZ), reaching out along +x from the hinge:
	-- a leading bone, finger bones fanning back, membrane between them.
	-- depth[x]: how far back the membrane runs at each column.
	local function membraneWing(depth: { number }, memb: any, bone: any, finger: any, claw: any?): any
		local g = Kit.group()
		for x = 1, #depth do
			for z = 1, depth[x] do Kit.set(g, x, 0, z, memb.color, memb.neon, memb.alpha) end
		end
		for x = 0, #depth do Kit.set(g, x, 0, 0, bone.color, bone.neon) end
		for _, fx in ipairs({ math.floor(#depth / 3), math.floor(#depth * 2 / 3), #depth }) do
			for z = 1, depth[fx] do Kit.set(g, fx, 0, z, finger.color, finger.neon) end
		end
		if claw then Kit.set(g, #depth + 1, 0, 0, claw.color, claw.neon) end
		return g
	end

	-- A tail of `n` segments swinging in a travelling wave behind (x, y, z).
	local function waveTail(b: any, n: number, y: number, z: number, make: (number) -> any, gap: number?, amp: number?): { any }
		local out = {}
		for i = 1, n do
			local k = i
			table.insert(out, b:piece({ make(i) }, b:at(0, y - (i - 1) * 0.25, z + (i - 1) * (gap or 3)), function(t: number, move: number): CFrame
				local ph = t * 3.2 - k * 0.6
				return CFrame.new(math.sin(ph) * 0.12 * k * b.V, 0, 0) * CFrame.Angles(math.sin(ph * 0.8) * 0.04 * k, math.sin(ph) * (amp or 0.08) * k * (0.6 + math.min(move, 1) * 0.4), 0)
			end))
		end
		return out
	end

	-- Infernal Dragon: red-black, folded bat wings, horns, a lava-glow belly,
	-- embers clinging all over. Flies with its legs tucked. Called: rears,
	-- wings thrown open. Emote: breathes a burst of fire into the sky.
	function M.infernal_dragon()
		local b = K.new("infernal_dragon", { gait = 9, emoteLen = 2.8 })
		b.flier = true
		local SCALE, SCALE2, DARK = rgb(120, 24, 20), rgb(150, 36, 26), rgb(36, 14, 14)
		local BELLY, BELLY2, EYE = glow(255, 110, 30), glow(255, 170, 60), glow(255, 220, 80)
		local HORN, CLAW, MEMB, BONEW = rgb(30, 22, 22), rgb(220, 210, 190), rgb(110, 22, 20), rgb(52, 16, 14)
		local SEAT, GEM = rgb(40, 30, 30), glow(255, 60, 40)
		local FLAME = Color3.fromRGB(255, 120, 30)
		local V = b.V
		local roar = function(t: number): number return hold(b:emPhase(t), 0.2, 2.5, 0.35) end
		b:gallop(7, 0.06)
		b:rearUp(4, 0.35)
		b:move(function(t: number, move: number): CFrame
			local fly = b:flying(move)
			return CFrame.new(0, math.sin(t * 10) * 0.1 * fly, 0)
		end)

		local body = Kit.group()
		Kit.box(body, -3, 5, -6, 3, 9, 6, SCALE)
		for x = -2, 2 do
			for z = -6, 6 do Kit.set(body, x, 5, z, (if z % 2 == 0 then BELLY else BELLY2).color, true) end
		end
		for _, z in ipairs({ -6, -5, -4, -3, 3, 4, 5, 6 }) do Kit.set(body, 0, 10, z, DARK.color) end
		for _, sx in ipairs({ -3, 3 }) do Kit.box(body, sx, 6, -6, sx, 6, 6, SCALE2) end
		K.ornateSaddle(body, 2, 10, -1, 2, SEAT, GEM)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -1, -1, -3, 1, 2, 0, SCALE)
		Kit.box(head, -2, 2, -7, 2, 4, -3, SCALE)
		Kit.box(head, -1, 2, -10, 1, 3, -8, SCALE2)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 3, -10, DARK.color) end
		for _, sx in ipairs({ -2, 2 }) do
			Kit.set(head, sx, 4, -5, EYE.color, true)
			Kit.set(head, sx, 5, -5, DARK.color)
			Kit.set(head, sx, 5, -4, DARK.color)
			for i, c in ipairs({ { 5, -3 }, { 6, -2 }, { 7, -1 }, { 8, 0 } }) do Kit.set(head, sx + (if i > 2 then (if sx > 0 then 1 else -1) else 0), c[1], c[2], HORN.color) end
		end
		b:head({ head }, 0, 9, -6, function(t: number): (number, number) return roar(t) * 0.85 + b:mu(t) * 0.3, 0 end)
		local jaw = Kit.group()
		Kit.box(jaw, -1, 1, -10, 1, 1, -4, rgb(80, 18, 16))
		for _, sx in ipairs({ -1, 1 }) do Kit.set(jaw, sx, 2, -9, CLAW.color) end
		b:onHead({ jaw }, Vector3.new(0, 1.5, -4), function(t: number): CFrame
			return CFrame.Angles(-(roar(t) * 0.55 + b:mu(t) * 0.4), 0, 0)
		end)
		local fire = b:emitter(b.headPiece, b:v(0, 2.5, -11), Vector3.one * 0.5, {
			Texture = K.FIRE, Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), FLAME), LightEmission = 1,
			Size = K.seq(0.7, 3.4), Transparency = K.seq(0.05, 1), Lifetime = NumberRange.new(0.5, 0.75),
			Speed = NumberRange.new(20, 26), SpreadAngle = Vector2.new(10, 10), EmissionDirection = Enum.NormalId.Front,
			Acceleration = Vector3.new(0, 4, 0),
		})
		b:whileEmote(fire, 70, 0.6, 2.3)
		local smoke = b:fx(b.headPiece, b:v(0, 3, -10), Vector3.one * 0.3, "smoke", Color3.fromRGB(60, 40, 36))
		smoke.Rate = 2

		local depth = { 3, 5, 6, 7, 7, 6, 6, 5, 3 }
		local right = membraneWing(depth, MEMB, BONEW, BONEW, CLAW)
		for _, side in ipairs({ -1, 1 }) do
			b:wing(if side > 0 then right else K.mirror(right), side * 3, 9, -2, side, {
				spread = function(t: number): number return math.max(b:mu(t), roar(t) * 0.6) end,
			})
		end
		b:legs4({ x = 2.5, front = -4, hind = 4, hip = 5, len = 5, w = 2, main = SCALE, foot = CLAW })
		local tail = waveTail(b, 5, 7, 7, function(i: number): any
			local g = Kit.group()
			local w = if i <= 2 then 1 else 0
			Kit.box(g, -w, -1, 0, w, 0, 2, SCALE)
			Kit.set(g, 0, 1, 1, DARK.color)
			if i == 5 then
				Kit.set(g, 0, 0, 3, BELLY.color, true)
				Kit.set(g, 0, 1, 3, BELLY2.color, true)
			end
			return g
		end)
		b:fx(tail[5], b:v(0, 0.5, 3), Vector3.one * 0.5, "fire", FLAME).Rate = 14
		b:aura(b:v(6, 5, 12), b:v(0, 7, 0), "embers", FLAME, 14)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(6, 1, 12), "embers", FLAME, 16)
		b:dust(12, 7)
		return b.rig
	end

	-- Storm Wyvern: slate-blue and white, two legs and great wings veined with
	-- lightning, sparks crackling all over. Emote: a lightning bolt strikes
	-- its spread wings.
	function M.storm_wyvern()
		local b = K.new("storm_wyvern", { gait = 12, emoteLen = 2.6 })
		b.flier = true
		local SLATE, SLATE2, WHITE, DARK = rgb(64, 84, 112), rgb(86, 108, 138), rgb(222, 230, 240), rgb(30, 38, 52)
		local VEIN, EYE, HORN = glow(255, 230, 80), glow(255, 240, 140), rgb(220, 226, 236)
		local SEAT, GEM = rgb(40, 50, 70), glow(255, 230, 80)
		local SPARK = Color3.fromRGB(255, 235, 120)
		local V = b.V
		local strike = function(t: number): number return hold(b:emPhase(t), 0.2, 2.3, 0.3) end
		b:rearUp(3, 0.3)
		b:move(function(t: number, move: number): CFrame
			local fly = b:flying(move)
			local walk = (1 - fly) * math.min(move, 1.2)
			-- (two legs: a bob each step)
			return CFrame.new(0, math.sin(t * 10) * 0.1 * fly + math.abs(math.sin(t * b.gait)) * 0.1 * walk, 0)
		end)

		local body = Kit.group()
		Kit.box(body, -2, 5, -5, 2, 9, 5, SLATE)
		Kit.box(body, -2, 5, -5, 2, 5, 5, WHITE)
		Kit.box(body, -1, 6, -6, 1, 8, -6, WHITE)
		for _, z in ipairs({ -5, -4, -3, 3, 4, 5 }) do Kit.set(body, 0, 10, z, SLATE2.color) end
		K.ornateSaddle(body, 2, 10, -1, 2, SEAT, GEM)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -1, -1, -3, 1, 3, 0, SLATE)
		Kit.box(head, -1, 3, -7, 1, 5, -3, SLATE)
		Kit.box(head, -1, 3, -9, 1, 4, -8, SLATE2)
		for _, sx in ipairs({ -1, 1 }) do
			Kit.set(head, sx, 5, -5, EYE.color, true)
			for _, c in ipairs({ { 6, -3 }, { 6, -2 }, { 7, -1 }, { 7, 0 } }) do Kit.set(head, sx, c[1], c[2], HORN.color) end
		end
		b:head({ head }, 0, 9, -5, function(t: number): (number, number) return strike(t) * 0.6 + b:mu(t) * 0.3, 0 end)
		local jaw = Kit.group()
		Kit.box(jaw, -1, 2, -9, 1, 2, -4, WHITE)
		b:onHead({ jaw }, Vector3.new(0, 2.5, -4), function(t: number): CFrame
			return CFrame.Angles(-(strike(t) * 0.45 + b:mu(t) * 0.35), 0, 0)
		end)

		local depth = { 3, 5, 7, 8, 8, 8, 7, 6, 5, 3 }
		local right = membraneWing(depth, SLATE2, SLATE, VEIN, WHITE)
		for _, side in ipairs({ -1, 1 }) do
			b:wing(if side > 0 then right else K.mirror(right), side * 2.5, 9, -2, side, {
				spread = function(t: number): number return math.max(b:mu(t), strike(t)) end,
			})
		end
		-- two legs, stepping in turn
		for _, side in ipairs({ -1, 1 }) do
			b:leg(K.legGroup(5, 2, SLATE, WHITE), side * 2 + 0.5, 5, 3, false, side, { phase = if side > 0 then math.pi - K.SIDE_LAG else 0, amp = 0.6 })
		end
		waveTail(b, 5, 7, 6, function(i: number): any
			local g = Kit.group()
			local w = if i <= 2 then 1 else 0
			Kit.box(g, -w, -1, 0, w, 0, 2, SLATE)
			if i == 5 then
				for _, c in ipairs({ { -1, 0, 3 }, { 1, 0, 3 }, { 0, 0, 4 } }) do Kit.set(g, c[1], c[2], c[3], VEIN.color, true) end
			end
			return g
		end)
		-- the bolt: a zigzag of light above it, flashing in when it strikes
		local bolt = Kit.group()
		local x, z = 0, 0
		for y = 0, 22 do
			Kit.set(bolt, x, y, z, (if y % 3 == 0 then Color3.fromRGB(255, 255, 230) else Color3.fromRGB(255, 232, 110)), true)
			if y % 4 == 3 then x += (if (y // 4) % 2 == 0 then 1 else -1) end
		end
		local boltPiece = b:piece({ bolt }, b:at(0, 11, 0))
		b:fade(boltPiece.parts, function(t: number): number
			local p = b:emPhase(t)
			local on = p ~= nil and ((p > 0.55 and p < 0.75) or (p > 0.85 and p < 0.98))
			return if on then 0 else 1
		end)
		local sparks = b:aura(b:v(5, 5, 11), b:v(0, 7, 0), "sparks", SPARK, 10)
		b:atEmote(0.56, function() sparks:Emit(40) end)
		b:atMount(0.4, function() sparks:Emit(25) end)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(5, 1, 10), "sparks", SPARK, 14)
		b:dust(10, 5)
		return b.rig
	end

	-- Death Knight Horse: a huge black warhorse in spiked plate barding, blue-
	-- white soul fire for eyes and mane. Called: rears in a burst of soul fire.
	-- Emote: rears up as its soul fire blazes higher.
	function M.death_knight_horse()
		local b = K.new("death_knight_horse", { gait = 10, emoteLen = 2.6 })
		local HIDE, HIDE2, PLATE, PLATE2, SPIKE = rgb(30, 28, 34), rgb(46, 42, 52), rgb(70, 74, 86), rgb(100, 104, 118), rgb(160, 166, 178)
		local SOUL, SOUL2, HOOF = glow(120, 190, 255), glow(225, 240, 255), rgb(30, 30, 36)
		local SEAT, GEM = rgb(96, 22, 28), glow(120, 190, 255)
		local FIRE = Color3.fromRGB(110, 180, 255)
		local V = b.V
		local blaze = function(t: number): number return hold(b:emPhase(t), 0.15, 2.4, 0.35) end
		b:gallop(8, 0.07)
		b:rearUp(5, 0.35)
		b:move(function(t: number): CFrame
			local a = blaze(t) * 0.45
			if a == 0 then return CFrame.identity end
			local hind = Vector3.new(0, 0, 5 * V)
			return CFrame.new(hind) * CFrame.Angles(a, 0, 0) * CFrame.new(-hind)
		end)

		local body = Kit.group()
		Kit.box(body, -2, 6, -6, 2, 10, 6, HIDE)
		for _, sx in ipairs({ -3, 3 }) do
			Kit.box(body, sx, 6, -6, sx, 9, 5, PLATE)
			Kit.box(body, sx, 9, -6, sx, 9, 5, PLATE2)
			for _, z in ipairs({ -5, -1, 3 }) do Kit.set(body, sx + (if sx > 0 then 1 else -1), 8, z, SPIKE.color) end
		end
		Kit.box(body, -2, 11, 3, 2, 11, 6, PLATE)
		Kit.set(body, 0, 12, 5, SPIKE.color)
		Kit.box(body, -2, 7, -7, 2, 10, -7, PLATE) -- peytral
		Kit.set(body, 0, 9, -8, SPIKE.color)
		K.ornateSaddle(body, 2, 11, -1, 2, SEAT, GEM)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -1, 0, -3, 1, 4, 0, HIDE)
		Kit.box(head, -1, 4, -8, 1, 6, -4, HIDE)
		Kit.box(head, -1, 4, -10, 1, 5, -9, HIDE2)
		Kit.box(head, -1, 6, -9, 1, 6, -4, PLATE) -- chamfron
		Kit.box(head, 0, 7, -8, 0, 8, -8, SPIKE)
		for _, sx in ipairs({ -1, 1 }) do
			Kit.set(head, sx, 5, -6, SOUL.color, true)
			Kit.set(head, sx, 7, -4, PLATE2.color)
		end
		b:head({ head }, 0, 10, -6, function(t: number): (number, number) return blaze(t) * 0.4 + b:mu(t) * 0.35, 0 end)
		local mane = Kit.group()
		for i, c in ipairs({ { 1, 1 }, { 2, 1 }, { 3, 0 }, { 4, 0 }, { 5, -1 }, { 6, -2 }, { 7, -3 } }) do
			Kit.set(mane, 0, c[1], c[2], (if i % 2 == 0 then SOUL2 else SOUL).color, true)
		end
		local manePiece = b:onHead({ mane }, Vector3.new(0, 1, 0), function(t: number): CFrame
			return CFrame.Angles(math.sin(t * 6) * 0.05, 0, math.sin(t * 8.3) * 0.04)
		end)
		b:glowUp(manePiece, function(t: number): number return blaze(t) * 0.8 end)
		local soul = b:fx(manePiece, b:v(0, 4, -1), b:v(1, 6, 3), "fire", FIRE)
		soul.Rate = 16
		b:every(function(t: number) soul.Rate = 16 + blaze(t) * 50 end)
		b:atMount(0.25, function() soul:Emit(30) end)

		local legs = b:legs4({ x = 1.5, front = -4, hind = 5, hip = 6, len = 6, w = 2, main = HIDE, foot = HOOF })
		for _, lp in ipairs(legs) do
			local f = b:fx(lp, b:v(0, -5.5, 0), b:v(1.6, 0.6, 1.6), "fire", FIRE)
			f.Rate = 8
		end
		local tail = Kit.group()
		for i, c in ipairs({ { 0, 0 }, { -1, 1 }, { -2, 2 }, { -3, 2 }, { -4, 3 } }) do
			Kit.set(tail, 0, c[1], c[2], (if i % 2 == 0 then SOUL2 else SOUL).color, true)
		end
		local tailPiece = b:tail({ tail }, 0, 10, 7)
		b:fx(tailPiece, b:v(0, -2, 2), b:v(1, 3, 2), "fire", FIRE).Rate = 10
		b:aura(b:v(5, 5, 12), b:v(0, 8, 0), "smoke", Color3.fromRGB(40, 70, 140), 6)
		b:runTrail(Vector3.new(0, 0.4, 0), b:v(5, 1, 12), "fire", FIRE, 12)
		b:dust(12, 5, Color3.fromRGB(70, 80, 100))
		return b.rig
	end

	-- Void Disc: a floating black rune disc, a purple glowing ring, shards
	-- circling; sat on cross-legged. Called: a spin. Emote: its runes light up
	-- one by one round the ring as it spins faster.
	function M.void_disc()
		local b = K.new("void_disc", { emoteLen = 2.8 })
		local BLACK, BLACK2, RUNE_OFF = rgb(18, 14, 26), rgb(30, 24, 42), rgb(64, 38, 100)
		local RING, RUNE, VELVET, GEM = glow(180, 90, 255), glow(225, 175, 255), rgb(60, 30, 90), glow(200, 120, 255)
		local V = b.V
		local home = CFrame.new(0, W.RideData.BackHeight("void_disc") - 1.5 * V, 0)
		b:spinUp(0.7)
		-- (it turns slowly, faster while the runes light)
		local spin, last = 0, nil
		b:every(function(t: number)
			if last then spin += math.clamp(t - last, 0, 0.1) * (0.35 + b:em(t) * 2.5) end
			last = t
		end)
		local function discAnim(t: number, move: number): CFrame
			return W.hover(t, move) * CFrame.Angles(0, spin, 0)
		end
		local RUNES = {}
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			local x, z = math.floor(math.cos(a) * 6 + 0.5), math.floor(math.sin(a) * 6 + 0.5)
			table.insert(RUNES, { x, z })
		end
		local disc = Kit.group()
		Kit.lathe(disc, { { 0, 8 } }, function(x, _, z, d)
			if d >= 7.2 then return RING end
			if d >= 5.4 and d <= 6.6 then return RUNE_OFF end
			return if (x + z) % 3 == 0 then BLACK2 else BLACK
		end)
		Kit.lathe(disc, { { -1, 7 }, { -2, 5 }, { -3, 3 } }, function() return BLACK2 end)
		Kit.box(disc, 0, -5, 0, 0, -4, 0, GEM)
		local carve = {}
		for _, r in ipairs(RUNES) do table.insert(carve, { r[1], 0, r[2] }) end
		K.carve(disc, carve)
		-- the cushion
		Kit.box(disc, -2, 1, -2, 2, 1, 2, VELVET)
		for _, c in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 } }) do Kit.set(disc, c[1], 1, c[2], K.GOLD.color) end
		Kit.set(disc, 0, 1, 3, GEM.color, true)
		local discPiece = b:piece({ disc }, home, discAnim)
		b.body = discPiece
		for i, r in ipairs(RUNES) do
			local g = Kit.group()
			Kit.set(g, r[1], 0, r[2], RUNE.color, true)
			local piece = b:piece({ g }, home, discAnim)
			b:lamp(piece, function(t: number): boolean
				local p = b:emPhase(t)
				if p then return p > 0.2 + (i - 1) * 0.13 and p < 2.6 end
				return math.floor(t * 2) % 12 == i - 1
			end, RUNE_OFF.color)
		end
		W.orbit(b.rig, home * CFrame.new(0, 4 * V, 0), 5, 10 * V, 0.6, V, function() return W.shard(rgb(40, 10, 70), glow(220, 150, 255)) end, 0.3, 0.5)
		b:aura(Vector3.new(13 * V, 0.4, 13 * V), Vector3.new(0, 0.6, 0), "stars", Color3.fromRGB(210, 150, 255), 10)
		local up = b:fx(discPiece, Vector3.new(0, 0.6, 0), Vector3.new(12 * V, 0.2, 12 * V), "smoke", Color3.fromRGB(150, 60, 255))
		up.Rate = 4
		for k = 0, 2 do
			local w = b:anchor(home, function(t: number, move: number): CFrame
				return W.hover(t, move) * CFrame.Angles(0, t * 2.4 + k * math.pi * 2 / 3, 0)
			end)
			b:trail(w, Vector3.new(7.6 * V, 0.2, 0), 0.4, Color3.fromRGB(200, 130, 255), 0.5)
		end
		return b.rig
	end

	-- Ossuary Beetle: a rhino beetle whose shell is fused from skulls and ribs,
	-- a femur for a horn, green soul fire leaking from every joint. Called:
	-- tosses its horn. Emote: the skulls on its shell chatter their jaws.
	function M.ossuary_beetle()
		local b = K.new("ossuary_beetle", { emoteLen = 2.4 })
		local BONE, BONE2, SOCKET, DARK = rgb(226, 218, 196), rgb(196, 188, 164), rgb(40, 36, 30), rgb(62, 58, 50)
		local SOUL, SOUL2 = glow(110, 255, 140), glow(200, 255, 210)
		local SEAT, GEM = rgb(60, 40, 30), glow(110, 255, 140)
		local GREEN = Color3.fromRGB(110, 255, 140)
		local chatter = function(t: number): number return hold(b:emPhase(t), 0.15, 2.2, 0.2) end
		b:rearUp(4, 0.2)

		local body = Kit.group()
		K.ellipsoid(body, 0, 4, 1, 4, 3.2, 5, function(x, y, z)
			if y < -1 then return DARK end
			if x == 0 and y >= 2 then return SOUL end
			if z % 2 == 0 and math.abs(x) >= 3 then return BONE2 end
			return BONE
		end)
		local SKULLS = { { -1, -3 }, { 1, -3 }, { -1, 2 }, { 1, 2 } }
		for _, s in ipairs(SKULLS) do
			local sx = s[1] * 5
			Kit.box(body, sx, 3, s[2], sx, 5, s[2] + 2, BONE)
			Kit.set(body, sx, 4, s[2], SOCKET.color)
			Kit.set(body, sx, 4, s[2] + 2, SOCKET.color)
			Kit.set(body, sx, 3, s[2] + 1, SOCKET.color)
		end
		Kit.box(body, -2, 7, -1, 2, 7, 2, SEAT)
		K.ornateSaddle(body, 2, 8, -1, 2, SEAT, GEM)
		b:bodyPiece({ body })
		-- the skulls' jaws
		for i, s in ipairs(SKULLS) do
			local g = Kit.group()
			for z = 0, 2 do Kit.set(g, 0, 0, z, (if z == 1 then BONE2 else BONE).color) end
			local sx = s[1] * 5
			b:piece({ g }, b:at(sx, 2, s[2]), function(t: number, move: number): CFrame
				local c = chatter(t)
				local open = c * (0.2 + math.max(0, math.sin(t * 30 + i * 1.7)) * 0.45)
				return b.bodyAnim(t, move) * CFrame.new(0, 0.5 * b.V, 0) * CFrame.Angles(0, 0, s[1] * open) * CFrame.new(0, -0.5 * b.V, 0)
			end)
		end

		local head = Kit.group()
		Kit.box(head, -2, -1, -3, 2, 1, 0, BONE2)
		for _, sx in ipairs({ -2, 2 }) do
			Kit.set(head, sx, 1, -2, SOUL.color, true)
			Kit.set(head, sx, -1, -4, BONE2.color)
			Kit.set(head, sx - (if sx > 0 then 1 else -1), -1, -5, BONE2.color)
		end
		for _, c in ipairs({ { 2, -3 }, { 3, -3 }, { 4, -4 }, { 5, -4 }, { 6, -5 }, { 7, -5 } }) do Kit.set(head, 0, c[1], c[2], BONE.color) end
		Kit.box(head, -1, 8, -6, 1, 8, -5, BONE) -- the femur's knob
		Kit.box(head, -1, 1, -3, 1, 1, -3, BONE)
		b:head({ head }, 0, 4, -5, function(t: number): (number, number)
			return b:mu(t) * 0.45 + chatter(t) * math.sin(t * 9) * 0.08, 0
		end)
		b:crawlLegs({ zs = { -3, 0, 3 }, hipX = 3, hipY = 3, reach = 3, drop = 4, main = BONE2, dark = DARK, joint = SOUL, speed = 15 })
		local flame = b:aura(b:v(7, 5, 9), b:v(0, 5, 1), "fire", GREEN, 10)
		b:every(function(t: number) flame.Rate = 10 + chatter(t) * 20 end)
		b:runTrail(Vector3.new(0, 0.4, 0), b:v(7, 1, 9), "fire", GREEN, 10)
		b:dust(10, 8, Color3.fromRGB(150, 145, 125))
		return b.rig
	end

	-- Tidal Hippocampus: half horse, half fish, teal scales, a see-through
	-- water-blue fin mane and tail, droplets circling its hooves. It swims
	-- through the air. Called: rears in a splash. Emote: sprays a fountain of
	-- water from its fins.
	function M.tidal_hippocampus()
		local b = K.new("tidal_hippocampus", { emoteLen = 2.6 })
		local SCALE, SCALE2, BELLY = rgb(40, 150, 150), rgb(62, 182, 172), rgb(182, 232, 222)
		local FIN, FIN2, EYE = glass(110, 200, 255, 0.35), glow(150, 232, 255), glow(200, 255, 255)
		local SEAT, GEM = rgb(20, 80, 90), glow(120, 230, 255)
		local WATER = Color3.fromRGB(140, 215, 255)
		local V = b.V
		local spray = function(t: number): number return hold(b:emPhase(t), 0.2, 2.3, 0.3) end
		b:hoverMove(0.18)
		b:rearUp(3, 0.3)
		b:move(function(t: number, move: number): CFrame
			return CFrame.Angles(math.sin(t * 2.4) * 0.03 * (0.5 + move), 0, 0)
		end)

		local body = Kit.group()
		for x = -2, 2 do
			for y = 4, 7 do
				for z = -4, 3 do
					local p = if y == 4 then BELLY elseif (x + z) % 2 == 0 and math.abs(x) == 2 then SCALE2 else SCALE
					Kit.set(body, x, y, z, p.color)
				end
			end
		end
		K.ornateSaddle(body, 2, 8, -1, 2, SEAT, GEM)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -1, 0, -2, 1, 4, 0, SCALE)
		Kit.box(head, -1, 4, -6, 1, 6, -2, SCALE)
		Kit.box(head, -1, 4, -8, 1, 5, -7, SCALE2)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 6, -4, EYE.color, true) end
		b:head({ head }, 0, 7, -4, function(t: number): (number, number) return spray(t) * 0.35 + b:mu(t) * 0.3, 0 end)
		local mane = Kit.group()
		for i, c in ipairs({ { 1, 1 }, { 2, 1 }, { 3, 1 }, { 4, 0 }, { 5, 0 }, { 6, -1 }, { 7, -2 } }) do
			Kit.set(mane, 0, c[1], c[2], FIN.color, nil, FIN.alpha)
			Kit.set(mane, 0, c[1], c[2] + 1, (if i % 2 == 0 then FIN2 else FIN).color, i % 2 == 0, if i % 2 == 0 then 0 else FIN.alpha)
		end
		for _, sx in ipairs({ -2, 2 }) do
			Kit.set(mane, sx, 6, -2, FIN.color, nil, FIN.alpha)
			Kit.set(mane, sx, 7, -2, FIN2.color, true)
		end
		local manePiece = b:onHead({ mane }, Vector3.new(0, 1, 1), function(t: number): CFrame
			return CFrame.Angles(math.sin(t * 4) * 0.08, 0, math.sin(t * 5.3) * 0.06)
		end)
		local fountain = b:emitter(manePiece, b:v(0, 6, 0), b:v(3, 1, 3), {
			Texture = K.SPARK, Color = ColorSequence.new(Color3.new(1, 1, 1), WATER), LightEmission = 0.5,
			Size = K.seq(0.35, 0.15), Transparency = K.seq(0, 0.6), Lifetime = NumberRange.new(0.9, 1.3),
			Speed = NumberRange.new(14, 20), SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Top,
			Acceleration = Vector3.new(0, -30, 0),
		})
		b:whileEmote(fountain, 80, 0.4, 2.1)
		-- forelegs paddling, fins for hooves
		for _, side in ipairs({ -1, 1 }) do
			local g = K.legGroup(3, 1, SCALE, nil)
			Kit.set(g, 0, -4, 0, FIN2.color, true)
			Kit.set(g, 0, -4, 1, FIN.color, nil, FIN.alpha)
			Kit.set(g, side, -3, 1, FIN.color, nil, FIN.alpha)
			b:piece({ g }, b:at(side * 1.5, 4, -3), function(t: number, move: number): CFrame
				return CFrame.Angles(math.sin(t * 6 + side) * (0.35 + 0.35 * math.min(move, 1)) + b:mu(t) * 0.8, 0, 0)
			end)
		end
		-- the fish tail, curling down and back, its fin see-through
		for i = 1, 5 do
			local w = ({ 2, 1, 1, 0, 0 })[i]
			local g = Kit.group()
			Kit.box(g, -w, -1, 0, w, 0, 2, if i % 2 == 0 then SCALE2 else SCALE)
			if i == 5 then
				for y = -3, 2 do
					for z = 2, 4 - math.floor(math.abs(y + 0.5) / 2) do Kit.set(g, 0, y, z, FIN.color, nil, FIN.alpha) end
				end
				Kit.set(g, 0, 2, 3, FIN2.color, true)
				Kit.set(g, 0, -3, 3, FIN2.color, true)
			end
			local k = i
			b:piece({ g }, b:at(0, 5 - i * 0.9, 4 + (i - 1) * 2.4), function(t: number, move: number): CFrame
				local ph = t * 4 - k * 0.7
				return CFrame.new(0, math.sin(ph) * 0.1 * k * V, 0) * CFrame.Angles(math.sin(ph) * 0.12 * k * (0.6 + math.min(move, 1) * 0.5), 0, 0)
			end)
		end
		-- droplets circling its hooves
		W.orbit(b.rig, b:at(0, 0.6, -3), 6, 3.2 * V, 1.4, V, function()
			local g = Kit.group()
			Kit.set(g, 0, 0, 0, Color3.fromRGB(150, 220, 255), nil, 0.3)
			return g
		end, 0.15, 0.3)
		b:aura(b:v(5, 4, 9), b:v(0, 6, 0), "stars", WATER, 8)
		local splash = b:fx(b.body, b:v(0, 2, -2), b:v(5, 1, 6), "drip", WATER)
		splash.Rate = 0
		b:atMount(0.2, function() splash:Emit(30) end)
		b:runTrail(b:v(0, 3, 4), b:v(3, 2, 6), "drip", WATER, 14)
		return b.rig
	end

	-- Clockwork Gryphon: brass and bronze, rivets, wings of brass plates with
	-- turning gears, a spinning cog heart glowing in its chest, steam puffing.
	-- Emote: every gear spins up and it whistles steam.
	function M.clockwork_gryphon()
		local b = K.new("clockwork_gryphon", { gait = 10, emoteLen = 2.4 })
		b.flier = true
		local BRASS, BRASS2, BRONZE, IRON, RIVET = rgb(196, 146, 62), rgb(222, 178, 88), rgb(150, 96, 46), rgb(64, 58, 52), rgb(92, 80, 66)
		local CORE, BEAK, EYE = glow(255, 170, 60), rgb(240, 200, 90), glow(120, 220, 255)
		local SEAT, GEM = rgb(90, 40, 30), glow(255, 170, 60)
		local V = b.V
		local whistle = function(t: number): number return hold(b:emPhase(t), 0.15, 2.2, 0.25) end
		b:gallop(7, 0.06)
		b:rearUp(4, 0.3)
		-- (every gear's turn: faster while it whistles)
		local turn, last = 0, nil
		b:every(function(t: number, move: number)
			if last then turn += math.clamp(t - last, 0, 0.1) * (1.2 + move * 1.5 + whistle(t) * 12) end
			last = t
		end)

		local body = Kit.group()
		Kit.box(body, -2, 5, -5, 2, 9, 5, BRONZE)
		for _, sx in ipairs({ -2, 2 }) do
			Kit.box(body, sx, 6, -4, sx, 8, 4, BRASS)
			for z = -4, 4, 2 do Kit.set(body, sx, 9, z, RIVET.color) end
		end
		Kit.box(body, -1, 6, -6, 1, 8, -6, IRON) -- the chest window's frame
		K.ornateSaddle(body, 2, 10, -1, 2, SEAT, GEM)
		b:bodyPiece({ body })
		-- the cog heart, turning in its chest
		local cog = Kit.group()
		for x = -2, 2 do
			for y = -2, 2 do
				local d = math.sqrt(x * x + y * y)
				if d < 0.5 then Kit.set(cog, x, y, 0, CORE.color, true)
				elseif d < 2.4 and (d > 1.5 or (x == 0 or y == 0)) then Kit.set(cog, x, y, 0, BRASS2.color) end
			end
		end
		for _, c in ipairs({ { 3, 0 }, { -3, 0 }, { 0, 3 }, { 0, -3 } }) do Kit.set(cog, c[1], c[2], 0, BRASS2.color) end
		b:onBody({ cog }, function(): CFrame return CFrame.new(0, 7 * V, -7 * V) * CFrame.Angles(0, 0, turn * 2) end)

		local head = Kit.group()
		Kit.box(head, -1, 0, -2, 1, 3, 0, BRASS)
		Kit.box(head, -2, 3, -6, 2, 6, -2, BRASS)
		Kit.box(head, -1, 3, -8, 1, 4, -7, BEAK)
		Kit.set(head, 0, 2, -8, BEAK.color)
		for _, sx in ipairs({ -2, 2 }) do Kit.set(head, sx, 5, -4, EYE.color, true) end
		for z = -3, 0 do Kit.set(head, 0, 7, z, (if z % 2 == 0 then BRASS2 else RIVET).color) end
		b:head({ head }, 0, 9, -5, function(t: number): (number, number)
			local w = whistle(t)
			return b:mu(t) * 0.3 + w * 0.3 + math.sin(t * 16) * 0.05 * w, 0
		end)

		-- the wings: brass plates on an iron spar, gears turning on them
		local wingG = Kit.group()
		for x = 0, 9 do Kit.set(wingG, x, 0, 0, IRON.color) end
		local depth = { 3, 4, 5, 6, 6, 6, 5, 4, 3 }
		for x = 1, #depth do
			for z = 1, depth[x] do Kit.set(wingG, x, 0, z, (if x % 2 == 0 then BRASS else BRASS2).color) end
		end
		for _, side in ipairs({ -1, 1 }) do
			local wp = b:wing(if side > 0 then wingG else K.mirror(wingG), side * 2.5, 9, -2, side, {
				spread = function(t: number): number return math.max(b:mu(t), whistle(t) * 0.7) end,
			})
			for gi, gx in ipairs({ 3, 6 }) do
				local gear = Kit.group()
				for x = -1, 1 do
					for z = -1, 1 do
						if x ~= 0 or z ~= 0 then Kit.set(gear, x, 1, z, (if gi == 1 then BRASS2 else BRONZE).color) end
					end
				end
				Kit.set(gear, 0, 1, 0, CORE.color, true)
				for _, c in ipairs({ { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }) do Kit.set(gear, c[1], 1, c[2], IRON.color) end
				b:piece({ gear }, b:at(side * 2.5, 9, -2), b:follow(wp.anim, Vector3.new(side * gx, 0, 3), function(): CFrame
					return CFrame.Angles(0, turn * (if gi == 1 then 3 else -3), 0)
				end))
			end
		end
		b:legs4({ x = 1.5, front = -4, hind = 4, hip = 5, len = 5, w = 2,
			make = function(front: boolean): any
				return if front then K.legGroup(5, 2, BRASS2, IRON) else K.legGroup(5, 2, BRONZE, IRON)
			end })
		local tail = Kit.group()
		for i = 0, 5 do Kit.set(tail, 0, math.floor(i * 0.4), i, BRONZE.color) end
		Kit.box(tail, -1, 2, 5, 1, 3, 6, BRASS2)
		b:tail({ tail }, 0, 8, 6)
		-- steam: puffing always, a whistling jet from its back on the emote
		b:aura(b:v(5, 4, 10), b:v(0, 8, 0), "smoke", Color3.fromRGB(230, 226, 220), 5)
		local jet = b:emitter(b.body, b:v(0, 10, 4), b:v(2, 0.5, 1), {
			Texture = K.SMOKE, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(220, 220, 225)), LightEmission = 0.3,
			Size = K.seq(0.4, 2.2), Transparency = K.seq(0.2, 1), Lifetime = NumberRange.new(0.5, 0.9),
			Speed = NumberRange.new(14, 18), SpreadAngle = Vector2.new(8, 8), EmissionDirection = Enum.NormalId.Top,
		})
		b:whileEmote(jet, 50, 0.3, 2.1)
		local sparks = b:fx(b.body, b:v(0, 7, -6), b:v(2, 2, 1), "sparks", Color3.fromRGB(255, 200, 100))
		sparks.Rate = 2
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(5, 1, 10), "sparks", Color3.fromRGB(255, 190, 90), 10)
		b:dust(10, 5)
		return b.rig
	end

	-- Blood Moon Warg: a crimson-black wolf, scarred muzzle, chains wrapped
	-- round its body, a red moon crescent glowing on its brow. Emote: it howls,
	-- the chains rattling loose as the moon mark flares.
	function M.blood_moon_warg()
		local IRON, IRON2, SCAR, MOON = rgb(70, 70, 76), rgb(110, 110, 118), rgb(150, 90, 90), glow(255, 40, 50)
		local b = K.wolf("blood_moon_warg", {
			fur = rgb(44, 18, 20), fur2 = rgb(76, 24, 26), pale = rgb(112, 40, 40), dark = rgb(20, 8, 10),
			eye = glow(255, 60, 50), seat = rgb(30, 14, 16), trim = rgb(20, 8, 10), gem = glow(255, 40, 50),
			dustColor = Color3.fromRGB(90, 40, 40),
		}, {
			ornate = true,
			head = function(g: any)
				Kit.set(g, -1, 2, -7, SCAR.color)
				Kit.set(g, 0, 2, -6, SCAR.color)
				Kit.set(g, 1, 1, -8, SCAR.color)
			end,
		})
		local V = b.V
		local rattle = function(t: number): number return b.howl(t) end
		-- the chains, rattling loose on the emote
		local chains = Kit.group()
		for _, z in ipairs({ -3, 3 }) do
			for y = 5, 8 do
				Kit.set(chains, -3, y, z, (if y % 2 == 0 then IRON else IRON2).color)
				Kit.set(chains, 3, y, z, (if y % 2 == 0 then IRON2 else IRON).color)
			end
			for x = -2, 2 do Kit.set(chains, x, 4, z, (if x % 2 == 0 then IRON else IRON2).color) end
			if z == 3 then for x = -2, 2 do Kit.set(chains, x, 9, z, (if x % 2 == 0 then IRON2 else IRON).color) end end
		end
		for _, c in ipairs({ { -3, 4, -2 }, { -3, 3, -1 }, { 3, 4, 4 }, { 3, 3, 5 } }) do Kit.set(chains, c[1], c[2], c[3], IRON2.color) end -- loose ends
		b:onBody({ chains }, function(t: number): CFrame
			local r = rattle(t)
			return CFrame.new(math.sin(t * 37) * 0.05 * r, -math.abs(math.sin(t * 23)) * 0.08 * r, 0) * CFrame.Angles(0, 0, math.sin(t * 29) * 0.04 * r)
		end)
		local moon = Kit.group()
		for _, c in ipairs({ { -2, 4, -4 }, { -1, 4, -5 }, { 0, 4, -5 }, { 1, 4, -4 } }) do Kit.set(moon, c[1], c[2], c[3], MOON.color, true) end
		local moonPiece = b:onHead({ moon }, Vector3.zero, function(): CFrame return CFrame.identity end)
		b:glowUp(moonPiece, function(t: number): number return rattle(t) * 0.7 + math.sin(t * 2) * 0.1 + 0.1 end, Color3.fromRGB(255, 220, 220))
		local flare = b:fx(moonPiece, b:v(0, 4.5, -4.5), Vector3.one * 0.5, "embers", Color3.fromRGB(255, 50, 50))
		b:whileEmote(flare, 30, 0.3, 2.4)
		b:aura(b:v(5, 4, 12), b:v(0, 7, 0), "embers", Color3.fromRGB(255, 50, 40), 10)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(5, 1, 12), "embers", Color3.fromRGB(255, 60, 40), 12)
		return b.rig
	end

	return M
end
