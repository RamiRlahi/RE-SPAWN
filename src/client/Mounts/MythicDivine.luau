--[[
	Mounts/MythicDivine.luau
	The divine and ancient Mythic mounts (×1.4), rebuilt to their reference
	art: Celestial Lion, Seraph Steed, Chronos Tortoise, Bloomheart Stag.
	Studless voxels (b.smooth), gold and jewels, floating pieces, rune
	circles. (The cosmic five: MythicCosmic.)
--]]

return function(K: any): { [string]: () -> any }
	local Kit, rgb, glow, glass = K.Kit, K.rgb, K.glow, K.glass
	local P = require(script.Parent:WaitForChild("MythicParts"))(K)
	local hold, dot = P.hold, P.dot
	local GOLD = K.GOLD
	local M = {}
	-- (the imported voxel models: bodies lengthened, the seat kept clear of mane
	-- and tail: BeastKit B:model)
	local LONGER = { longer = 6, clearSeat = 6 }

	-- ── 22 · Celestial Lion ──────────────────────────────────────────────────
	-- A great white-marble lion veined with glowing gold, strapped in gold
	-- armour, a small gold crown on its brow and a huge sunburst mane of
	-- floating gold blocks blazing round its head; feathered wings of white
	-- and gold hover over its back; a carved throne under a gold compass-star
	-- emblem. Emote: it roars and the sunburst flares out like a sunrise.
	function M.celestial_lion()
		local b = K.new("celestial_lion", { gait = 10, emoteLen = 2.6 })
		b.smooth = true
		local MARBLE, MARBLE2, MARBLE3, STONE = rgb(240, 236, 228), rgb(218, 212, 202), rgb(196, 190, 180), rgb(110, 104, 98)
		local VEIN, RAY, RAY2, EYE = glow(255, 200, 70), glow(255, 196, 60), glow(255, 238, 160), glow(255, 236, 160)
		local V = b.V
		local roar = function(t: number): number return hold(b:emPhase(t), 0.2, 2.3, 0.3) end
		b:gallop(9, 0.08)
		b:rearUp(5, 0.3)

		local body = Kit.group()
		Kit.box(body, -3, 6, -7, 3, 12, -3, MARBLE)
		Kit.box(body, -3, 7, -3, 3, 11, 3, MARBLE)
		Kit.box(body, -3, 7, 3, 3, 11, 7, MARBLE)
		for _, c in ipairs({ { -3, 11, 7 }, { 3, 11, 7 }, { -3, 12, -7 }, { 3, 12, -7 } }) do K.carve(body, { c }) end
		for z = -7, 7 do for x = -2, 2 do Kit.set(body, x, if z < -2 then 6 else 7, z, MARBLE2.color) end end
		-- gold veins over the marble, constellation stars at their joints
		for _, sx in ipairs({ -3, 3 }) do
			for i, c in ipairs({ { 11, -6 }, { 10, -5 }, { 10, -4 }, { 9, -3 }, { 9, -2 }, { 8, -1 }, { 8, 0 }, { 9, 1 }, { 10, 2 }, { 10, 3 }, { 9, 4 }, { 8, 5 }, { 11, 1 }, { 9, -6 }, { 8, -6 } }) do
				Kit.set(body, sx, c[1], c[2], (if i % 5 == 0 then RAY2 else VEIN).color, true)
			end
		end
		for _, c in ipairs({ { -1, 9 }, { 0, 10 }, { 1, 9 }, { 1, 8 }, { -1, 11 } }) do Kit.set(body, c[1], c[2], -7, VEIN.color, true) end
		-- gold harness: girth bands, pauldrons, the breastplate
		for _, z in ipairs({ -2, 2 }) do
			for y = 7, 11 do
				Kit.set(body, -4, y, z, GOLD.color)
				Kit.set(body, 4, y, z, GOLD.color)
			end
			for x = -3, 3 do Kit.set(body, x, 6, z, GOLD.color) end
		end
		for _, s in ipairs({ -1, 1 }) do
			Kit.box(body, 4 * s, 10, -7, 4 * s, 12, -4, GOLD)
			Kit.box(body, 4 * s, 11, -6, 4 * s, 11, -5, MARBLE)
			Kit.set(body, 5 * s, 11, -5, RAY.color, true)
		end
		for x = -2, 2 do for y = 7, 11 do if math.abs(x) == 2 or y == 7 or y == 11 then Kit.set(body, x, y, -8, GOLD.color) end end end
		Kit.set(body, 0, 9, -8, RAY2.color, true)
		P.throne(body, 12, -1, 1, { velvet = rgb(30, 26, 40), back = rgb(22, 20, 30), frame = GOLD, gem = RAY, accent = RAY2, button = GOLD, backing = MARBLE2 })
		Kit.box(body, 0, 25, 2, 0, 26, 2, GOLD)
		b:bodyPiece({ body })
		-- the compass-star emblem
		local e = Kit.group()
		P.ring(e, 3.5, 1, GOLD, true)
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			local len = if k % 2 == 0 then 6 else 4
			P.line(e, Vector3.new(0, 0, 0), Vector3.new(math.cos(a) * len, math.sin(a) * len, 0), if k % 2 == 0 then RAY else RAY2)
		end
		Kit.set(e, 0, 0, -0.5, RAY2.color, true)
		b:emblem(e, 0, 30, 2)

		local head = Kit.group()
		Kit.box(head, -3, -2, -5, 3, 3, 0, MARBLE)
		Kit.box(head, -2, 4, -4, 2, 4, -1, MARBLE)
		Kit.box(head, -2, -2, -8, 2, 0, -6, MARBLE2)
		Kit.box(head, -1, 1, -7, 1, 1, -6, MARBLE)
		Kit.box(head, -1, 0, -9, 1, 0, -9, STONE)
		Kit.set(head, 0, -1, -9, STONE.color)
		for _, s in ipairs({ -1, 1 }) do
			Kit.set(head, 2 * s, 1, -6, EYE.color, true)
			Kit.set(head, 2 * s, 2, -6, MARBLE3.color)
			Kit.box(head, 3 * s, 4, -2, 3 * s, 5, -2, MARBLE)
			Kit.set(head, 3 * s, 4, -3, GOLD.color)
			Kit.set(head, 1 * s, 2, -5, VEIN.color, true)
		end
		-- the crown
		for x = -2, 2 do for z = -4, 0 do if math.abs(x) == 2 or z == -4 or z == 0 then Kit.set(head, x, 5, z, GOLD.color) end end end
		for _, c in ipairs({ { -2, -4 }, { 0, -4 }, { 2, -4 }, { -2, 0 }, { 2, 0 } }) do Kit.set(head, c[1], 6, c[2], GOLD.color) end
		Kit.set(head, 0, 7, -4, RAY2.color, true)
		b:head({ head }, 0, 12, -8, function(t: number): (number, number) return roar(t) * 0.45 + b:mu(t) * 0.3, 0 end)
		local jaw = Kit.group()
		Kit.box(jaw, -2, -3, -7, 2, -3, -2, MARBLE2)
		Kit.set(jaw, -1, -2, -7, MARBLE.color)
		Kit.set(jaw, 1, -2, -7, MARBLE.color)
		b:onHead({ jaw }, Vector3.new(0, -2.5, -2), function(t: number): CFrame return CFrame.Angles(-(roar(t) * 0.6 + b:mu(t) * 0.3), 0, 0) end)
		-- the sunburst mane: gold blocks floating round the head in two layers
		for i = 0, 27 do
			local a = i / 28 * math.pi * 2
			local len = 4 + (i % 3) * 2 + (i % 2)
			local bar = P.bar(len, 2, { rgb(240, 172, 40), RAY, RAY2 })
			local depth = if i % 2 == 0 then 0.5 else 2
			local ray = b:piece({ bar }, b.headHome, function(t: number, move: number): CFrame
				local out = 3.6 + math.sin(t * 2 + i) * 0.2 + roar(t) * 2.2
				return b.headAnim(t, move) * CFrame.new(0, 0.5 * V, depth * V) * CFrame.Angles(0, 0, a) * CFrame.new(out * V, -0.5 * V, 0)
			end)
			if i % 4 == 0 then b:glowUp(ray, function(t: number): number return roar(t) end, Color3.fromRGB(255, 252, 235)) end
		end
		-- feathered wings hovering over its back
		local wing = Kit.group()
		local depth = { 3, 4, 5, 6, 7, 8, 8, 7, 6, 5, 3 }
		for x = 0, #depth do Kit.set(wing, x, 0, 0, GOLD.color) end
		for x = 1, #depth do
			for z = 1, depth[x] do
				local p = if z == depth[x] then RAY elseif z <= 2 then MARBLE else (if x % 2 == 0 then MARBLE2 else MARBLE)
				Kit.set(wing, x, 0, z, p.color, p.neon)
			end
		end
		for _, side in ipairs({ -1, 1 }) do
			b:piece({ if side > 0 then wing else K.mirror(wing) }, b:at(side * 4, 15, 1), function(t: number, move: number): CFrame
				local flap = math.sin(t * (2.5 + move * 5) + side) * (0.15 + move * 0.25) + roar(t) * 0.4
				return CFrame.new(0, math.sin(t * 1.9 + side) * 0.15, 0) * CFrame.Angles(0, -side * 0.5, side * (0.55 + flap))
			end)
		end
		b:legs4({ x = 2, front = -5, hind = 5, hip = 7, w = 3,
			make = function(front: boolean): any
				local g = Kit.group()
				Kit.box(g, -1, -3, -1, 1, -1, 1, MARBLE)
				Kit.box(g, -1, -6, -1, 0, -4, 0, MARBLE)
				Kit.box(g, -1, -5, -1, 0, -5, 0, GOLD)
				Kit.box(g, -1, -7, -2, 1, -7, 0, MARBLE2)
				for _, x in ipairs({ -1, 0, 1 }) do Kit.set(g, x, -7, -3, GOLD.color) end
				Kit.set(g, if front then -1 else 1, -2, -2, VEIN.color, true)
				return g
			end })
		local tail = Kit.group()
		for i = 0, 7 do Kit.set(tail, 0, math.floor(i * 0.5), i, (if i % 3 == 2 then GOLD else MARBLE).color) end
		Kit.box(tail, -1, 4, 7, 1, 5, 9, RAY)
		Kit.set(tail, 0, 6, 9, RAY2.color, true)
		b:tail({ tail }, 0, 10, 7)
		b:orbitVar(b:at(0, 11, 0), 10, 11 * V, function(t: number): number return 0.4 + roar(t) * 2 end, function(i: number)
			local g = Kit.group()
			Kit.set(g, 0, 0, 0, (if i % 2 == 0 then RAY else RAY2).color, true)
			if i % 3 == 0 then Kit.set(g, 1, 0, 0, RAY.color, true) end
			return g
		end, 0.15, 1)
		P.runes(b, 12, Color3.fromRGB(255, 200, 70), "star")
		local flash = b:fx(b.headPiece, b:v(0, 0.5, 1), b:v(14, 14, 1), "stars", Color3.fromRGB(255, 230, 150))
		b:whileEmote(flash, 60, 0.3, 1.8)
		b:aura(b:v(7, 6, 14), b:v(0, 9, 0), "stars", Color3.fromRGB(255, 220, 130), 8)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(7, 1, 14), "stars", Color3.fromRGB(255, 220, 130), 14)
		b:dust(14, 7, Color3.fromRGB(230, 220, 190))
		return b.rig
	end

	-- ── 26 · Seraph Steed ────────────────────────────────────────────────────
	-- A white warhorse in gold armour set with blue crystals, a gold mane and
	-- tail, a crystal on its chest, and immense feathered wings raised high
	-- (Models/seraph_steed: the artist's voxel model, tools/mounts/export.py);
	-- golden feathers drift down round it. Called: it rears, wings spread.
	-- Emote: its wings open wide in a burst of light.
	function M.seraph_steed()
		local b = K.new("seraph_steed", { gait = 10, emoteLen = 2.6 })
		local burst = function(t: number): number return hold(b:emPhase(t), 0.2, 2.3, 0.25) end
		b:gallop(8, 0.06)
		b:rearUp(5, 0.4)
		b:move(function(t: number): CFrame
			local a = burst(t) * 0.3
			if a == 0 then return CFrame.identity end
			local hind = Vector3.new(0, 0, 5 * b.artV)
			return CFrame.new(hind) * CFrame.Angles(a, 0, 0) * CFrame.new(-hind)
		end)
		local a = b:horseAnims({ head = function(t: number): number return burst(t) * 0.3 + b:mu(t) * 0.35 end })
		-- the wings: a slow beat at rest, harder at a run; thrown wide open
		-- when called and on the emote (a turn about z tips them out)
		local beat = K.W.runner(2.2, 7)
		for _, side in ipairs({ 1, -1 }) do
			a[if side > 0 then "wingL" else "wingR"] = function(t: number, move: number): CFrame
				local open = math.max(burst(t), b:mu(t))
				local flap = math.sin(beat(t, move)) * (0.06 + math.min(move, 1) * 0.28) * (1 - open)
				return CFrame.Angles(0, side * open * 0.25, -side * (flap + open * 0.5))
			end
		end
		local pieces = b:model(require(script.Parent:WaitForChild("Models"):WaitForChild("seraph_steed")), a, LONGER)
		if pieces.gem then b:glowUp(pieces.gem, function(t: number): number return 0.15 + math.sin(t * 2.4) * 0.15 + burst(t) * 0.5 end) end
		-- golden feathers drifting down round it
		local feathers = b:emitter(b.body, b:v(0, 72, 6), b:v(90, 4, 60), {
			Texture = K.SPARK, Color = ColorSequence.new(Color3.fromRGB(255, 240, 190), Color3.fromRGB(255, 205, 90)), LightEmission = 0.8,
			Size = K.seq(0.35, 0.25), Transparency = K.seq(0, 1), Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(0.5, 1),
			Acceleration = Vector3.new(0, -2, 0), RotSpeed = NumberRange.new(-90, 90), Rate = 6,
		})
		local light = b:fx(b.body, b:v(0, 45, 6), b:v(80, 30, 50), "stars", Color3.fromRGB(255, 245, 210))
		b:whileEmote(light, 80, 0.3, 1.2)
		b:atEmote(0.3, function() feathers:Emit(30) end)
		b:atMount(0.3, function() feathers:Emit(20) end)
		b:legacy(function()
			b:orbitVar(b:at(0, 12, 0), 8, 10 * b.V, function(t: number): number return 0.4 + burst(t) * 2 end, function()
				local g = Kit.group()
				Kit.set(g, 0, 0, 0, Color3.fromRGB(250, 232, 182))
				Kit.set(g, 1, 0, 0, Color3.fromRGB(255, 214, 100), true)
				return g
			end, 0.25, 1.2)
		end)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(25, 4, 60), "stars", Color3.fromRGB(255, 240, 200), 14)
		b:dust(60, 25, Color3.fromRGB(240, 235, 220))
		return b.rig
	end

	-- ── 27 · Chronos Tortoise ────────────────────────────────────────────────
	-- An ancient tortoise of dark slate stone bound in gold, little gold-capped
	-- towers on its shell round a great gold-framed hourglass of glowing blue
	-- sand, a clock dial set in each flank with an hourglass at its heart and
	-- gold hands turning, blue rings of light circling it, blue crystals in
	-- its stone. Emote: the hands spin backwards, the rings race and the sand
	-- flows up.
	function M.chronos_tortoise()
		local b = K.new("chronos_tortoise", { gait = 7, emoteLen = 3 })
		b.smooth = true
		local STONE, STONE2, STONE3, UNDER = rgb(40, 46, 66), rgb(54, 60, 84), rgb(70, 76, 100), rgb(58, 54, 50)
		local BLUE, BLUE2, GLASS = glow(70, 160, 255), glow(170, 220, 255), glass(170, 215, 255, 0.55)
		local GOLD2 = glow(255, 205, 80)
		local V = b.V
		local rewind = function(t: number): number return hold(b:emPhase(t), 0.2, 2.8, 0.4) end
		b:rearUp(4, 0.12)
		b:move(function(t: number, move: number): CFrame
			local m = math.min(move, 1.2)
			return CFrame.new(0, math.abs(math.sin(t * b.gait)) * 0.08 * m, 0) * CFrame.Angles(0, 0, math.sin(t * b.gait) * 0.03 * m)
		end)

		local shell = Kit.group()
		K.ellipsoid(shell, 0, 5, 1, 6, 4.5, 7, function(x, y, z)
			local wy = y + 5
			if wy <= 2 then return if wy == 2 then GOLD else UNDER end
			if (x % 4 == 0 or (z + 1) % 4 == 0) and wy >= 6 then return GOLD end
			if (x * 5 + z * 3 + y) % 13 == 0 then return BLUE end
			return if (math.floor(x / 2) + math.floor(z / 2)) % 2 == 0 then STONE else STONE2
		end)
		-- the towers
		for _, c in ipairs({ { -4, -3 }, { 4, -3 }, { -4, 5 }, { 4, 5 } }) do
			local tx, tz = c[1], c[2]
			Kit.box(shell, tx, 8, tz, tx + (if tx > 0 then -1 else 1), 11, tz + 1, STONE3)
			Kit.set(shell, tx, 10, tz, BLUE.color, true)
			Kit.box(shell, math.min(tx, tx + (if tx > 0 then -1 else 1)), 12, tz, math.max(tx, tx + (if tx > 0 then -1 else 1)), 12, tz + 1, GOLD)
			Kit.set(shell, tx, 13, tz, GOLD.color)
			Kit.set(shell, tx, 14, tz, GOLD2.color, true)
		end
		-- the great hourglass behind the seat
		local hz = 6
		for _, c in ipairs({ { -2, hz - 2 }, { 2, hz - 2 }, { -2, hz + 2 }, { 2, hz + 2 } }) do Kit.box(shell, c[1], 10, c[2], c[1], 17, c[2], GOLD) end
		Kit.box(shell, -2, 9, hz - 2, 2, 9, hz + 2, GOLD)
		Kit.box(shell, -2, 18, hz - 2, 2, 18, hz + 2, GOLD)
		Kit.set(shell, 0, 19, hz, GOLD2.color, true)
		for y = 10, 17 do
			local w = math.abs(y - 13.5) > 2.5 and 1 or 0
			if y == 13 or y == 14 then w = 0 end
			Kit.box(shell, -w, y, hz - w, w, y, hz + w, GLASS)
		end
		Kit.box(shell, -1, 10, hz - 1, 1, 10, hz + 1, BLUE)
		Kit.set(shell, 0, 11, hz, BLUE2.color, true)
		Kit.set(shell, 0, 16, hz, BLUE.color, true)
		P.saddle(shell, 2, 10, -2, 1, { seat = rgb(30, 50, 90), frame = GOLD, gem = BLUE, cloth = STONE3 })
		b:bodyPiece({ shell })
		-- the clock dials in its flanks, their hands turning
		local hands = b:accum(function(t: number): number return 0.8 - rewind(t) * 14 end)
		for _, s in ipairs({ -1, 1 }) do
			local dial = Kit.group()
			for y = -4, 4 do
				for z = -4, 4 do
					local d = math.sqrt(y * y + z * z)
					if d <= 4.3 then Kit.set(dial, 0, y, z, (if d > 3.4 then GOLD elseif d > 2.6 then STONE3 else rgb(20, 24, 40)).color) end
				end
			end
			for i = 0, 11 do
				local a = i / 12 * math.pi * 2
				Kit.set(dial, s * 0.4, math.floor(math.cos(a) * 3 + 0.5), math.floor(math.sin(a) * 3 + 0.5), BLUE2.color, true)
			end
			Kit.set(dial, s * 0.4, 1, 0, BLUE.color, true)
			Kit.set(dial, s * 0.4, -1, 0, BLUE.color, true)
			Kit.set(dial, s * 0.4, 0, 0, BLUE2.color, true)
			b:onBody({ dial }, function(): CFrame return CFrame.new(s * 6.4 * V, 5 * V, 1 * V) end)
			for hi, len in ipairs({ 3, 2 }) do
				local h = Kit.group()
				for r = 1, len do Kit.set(h, 0, r, 0, (if r == len then GOLD2 else GOLD).color, r == len) end
				b:onBody({ h }, function(): CFrame
					return CFrame.new(s * 6.9 * V, 5 * V, 1 * V) * CFrame.Angles(s * hands() * (if hi == 1 then 1 else 1 / 12), 0, 0)
				end)
			end
		end
		-- the head, peering out
		local head = Kit.group()
		Kit.box(head, -1, -1, -2, 1, 1, 0, STONE2)
		Kit.box(head, -2, 0, -6, 2, 3, -2, STONE2)
		Kit.box(head, -2, 3, -6, 2, 3, -3, GOLD)
		Kit.box(head, -1, 0, -7, 1, 1, -7, UNDER)
		for _, s in ipairs({ -2, 2 }) do
			Kit.set(head, s, 2, -5, BLUE2.color, true)
			Kit.set(head, s, 2, -4, GOLD.color)
		end
		b:head({ head }, 0, 5, -8, function(t: number): (number, number) return b:mu(t) * 0.3, math.sin(t * 0.5) * 0.2 end)
		-- thick legs bound in gold, a steady trot
		local TROT = { [true] = { [-1] = 0, [1] = math.pi }, [false] = { [-1] = math.pi, [1] = 0 } }
		for _, front in ipairs({ true, false }) do
			for _, side in ipairs({ -1, 1 }) do
				local g = K.legGroup(5, 3, STONE, STONE3)
				Kit.box(g, -1, -2, -1, 1, -2, 1, GOLD)
				Kit.set(g, side, -3, -1, BLUE.color, true)
				for _, x in ipairs({ -1, 0, 1 }) do Kit.set(g, x, -5, -2, GOLD.color) end
				local base = (if front then K.FRONT_LAG else 0) + (if side > 0 then K.SIDE_LAG else 0)
				b:leg(g, side * 4, 5, if front then -4 else 5, front, side, { phase = TROT[front][side] - base, amp = 0.4 })
			end
		end
		local tail = Kit.group()
		Kit.set(tail, 0, 0, 0, STONE2.color)
		Kit.set(tail, 0, -1, 1, STONE2.color)
		b:tail({ tail }, 0, 3, 8)
		-- rings of blue light circling it
		local ringSpin = b:accum(function(t: number): number return 0.6 + rewind(t) * -6 end)
		for i, tilt in ipairs({ 0.3, -0.45, 0.1 }) do
			local ring = Kit.group()
			local r = 9 + i
			for k = 0, 47 do
				if k % 8 < 5 then
					local a = k / 48 * math.pi * 2
					Kit.set(ring, math.floor(math.cos(a) * r + 0.5), 0, math.floor(math.sin(a) * r + 0.5), (if k % 8 == 2 then BLUE2 else BLUE).color, true)
				end
			end
			b:piece({ ring }, b:at(0, 6, 1), function(): CFrame
				return CFrame.Angles(tilt, 0, 0.15 * i) * CFrame.Angles(0, ringSpin() * (if i == 2 then -1 else 1) + i, 0)
			end)
		end
		-- sand: falling in the hourglass, flowing up on the emote
		local sand = b:emitter(b.body, b:v(0, 15, hz), b:v(0.6, 0.4, 0.6), {
			Texture = K.SPARK, Color = ColorSequence.new(Color3.fromRGB(150, 210, 255)), LightEmission = 1,
			Size = K.seq(0.15, 0.1), Lifetime = NumberRange.new(0.6, 0.8), Speed = NumberRange.new(0, 0.1), Rate = 14,
			Acceleration = Vector3.new(0, -6, 0),
		})
		b:every(function(t: number) sand.Acceleration = Vector3.new(0, -6 + rewind(t) * 14, 0) end)
		b:orbitVar(b:at(0, 8, 1), 8, 12 * V, function(t: number): number return 0.4 - rewind(t) * 3 end, function(i: number)
			return dot((if i % 2 == 0 then BLUE2 else BLUE).color, true)
		end, 0.1, 1)
		P.runes(b, 12, Color3.fromRGB(80, 160, 255), "hex")
		b:dust(14, 12, Color3.fromRGB(120, 125, 140))
		return b.rig
	end

	-- ── 29 · Bloomheart Stag ─────────────────────────────────────────────────
	-- A graceful white stag wound with vines and blossom, great branching
	-- antlers of living wood heavy with cherry blossom and hung with glowing
	-- lanterns (Models/bloomheart_stag: the artist's voxel model,
	-- tools/mounts/export.py); petals drift round it. Emote: its antlers burst
	-- into bloom, the lanterns blaze.
	function M.bloomheart_stag()
		local b = K.new("bloomheart_stag", { gait = 10, emoteLen = 2.8 })
		local bloom = function(t: number): number return hold(b:emPhase(t), 0.2, 2.6, 0.35) end
		b:gallop(8, 0.08)
		b:rearUp(4, 0.35)
		local a = b:horseAnims({
			head = function(t: number): number return bloom(t) * 0.2 + b:mu(t) * 0.3 end,
			-- (a deer's flicking scut)
			tail = function(t: number): number return -0.2 + math.sin(t * 7) * 0.12 end,
		})
		-- the lanterns swing from the antler tips (trailing back at a run)
		for i, n in ipairs({ "lanL", "lanR" }) do
			a[n] = function(t: number, move: number): CFrame
				return CFrame.Angles(math.sin(t * 2.2 + i) * 0.25 - math.min(move, 1) * 0.3, 0, math.sin(t * 1.7 + i) * 0.2)
			end
		end
		-- (its antlers sweep back: a little longer still)
		local pieces = b:model(require(script.Parent:WaitForChild("Models"):WaitForChild("bloomheart_stag")), a, { longer = 9, clearSeat = 6 })
		for i, n in ipairs({ "lanL", "lanR" }) do
			if pieces[n] then
				b:glowUp(pieces[n], function(t: number): number return bloom(t) * 0.5 + math.sin(t * 3 + i) * 0.1 + 0.1 end, Color3.fromRGB(255, 240, 200))
			end
		end
		if pieces.blooms then b:glowUp(pieces.blooms, function(t: number): number return bloom(t) * 0.55 end, Color3.fromRGB(255, 225, 240)) end
		local petals = b:fx(b.headPiece, b:v(0, 12, 0), b:v(60, 14, 30), "stars", Color3.fromRGB(255, 180, 210))
		b:whileEmote(petals, 50, 0.3, 2.4)
		b:legacy(function()
			b:orbitVar(b:at(0, 11, 0), 10, 9 * b.V, function(t: number): number return 0.7 + bloom(t) * 3 end, function(i: number)
				return dot((if i % 3 == 0 then rgb(255, 235, 120) elseif i % 2 == 0 then rgb(255, 138, 184) else rgb(255, 168, 200)).color, i % 3 == 0)
			end, 0.25, 1.2)
		end)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(25, 4, 60), "stars", Color3.fromRGB(255, 190, 220), 14)
		b:dust(60, 25, Color3.fromRGB(240, 235, 220))
		return b.rig
	end

	return M
end
