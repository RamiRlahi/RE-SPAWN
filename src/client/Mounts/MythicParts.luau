--[[
	Mounts/MythicParts.luau
	Shared pieces for the Mythic mounts (MythicCosmic, MythicDivine): the
	carved gold throne, the jewelled saddle, the rune circle (double ring,
	glyphs and a star), and small drawing helpers. Built for studless
	mounts (b.smooth), in the clean MagicaVoxel look of their references.
--]]

return function(K: any): any
	local Kit, rgb, glow = K.Kit, K.rgb, K.glow
	local P: any = {}
	local WHITE = Color3.new(1, 1, 1)

	-- 0 → 1, held, → 0 over [a, b] with quick ramps.
	function P.hold(x: number?, a: number, b: number, ramp: number?): number
		if not x or x <= a or x >= b then return 0 end
		local r = ramp or 0.15
		return math.min(1, (x - a) / r, (b - x) / r)
	end

	-- One brick, as a group (a mote, a star, a petal).
	function P.dot(color: Color3, neon: boolean?, alpha: number?): any
		local g = Kit.group()
		Kit.set(g, 0, 0, 0, color, neon, alpha)
		return g
	end

	-- A straight line of bricks from a to b (bricks).
	function P.line(g: any, a: Vector3, b: Vector3, paint: any)
		local d = b - a
		local n = math.max(1, math.ceil(math.max(math.abs(d.X), math.abs(d.Y), math.abs(d.Z))))
		for i = 0, n do
			local p = a + d * (i / n)
			Kit.set(g, math.floor(p.X + 0.5), math.floor(p.Y + 0.5), math.floor(p.Z + 0.5), paint.color, paint.neon, paint.alpha)
		end
	end

	-- A bar along +x, `len` long, `thick` high, coloured in bands (paints
	-- listed root → tip). Turned into place, a bar merges to a few parts.
	function P.bar(len: number, thick: number, paints: { any }): any
		local g = Kit.group()
		for x = 0, len - 1 do
			local p = paints[math.min(#paints, math.floor(x / len * #paints) + 1)]
			for y = 0, thick - 1 do Kit.set(g, x, y, 0, p.color, p.neon, p.alpha) end
		end
		return g
	end

	-- A ring lying flat (XZ) or standing (XY) of radius r, w thick.
	function P.ring(g: any, r: number, w: number, paint: any, standing: boolean?, at: number?)
		local n = math.ceil(r + w)
		for a = -n, n do
			for b = -n, n do
				local d = math.sqrt(a * a + b * b)
				if d <= r + w / 2 and d >= r - w / 2 then
					if standing then Kit.set(g, a, b, at or 0, paint.color, paint.neon, paint.alpha) else Kit.set(g, a, at or 0, b, paint.color, paint.neon, paint.alpha) end
				end
			end
		end
	end
	-- A filled disc standing in XY (paint by distance from the middle).
	function P.disc(g: any, r: number, paint: (number, number, number) -> any, z: number?)
		local n = math.ceil(r)
		for x = -n, n do
			for y = -n, n do
				local d = math.sqrt(x * x + y * y)
				if d <= r + 0.25 then
					local p = paint(x, y, d)
					if p then Kit.set(g, x, y, z or 0, p.color, p.neon, p.alpha) end
				end
			end
		end
	end
	-- A chunky five-pointed star standing in XY, `depth` thick.
	function P.star(g: any, R: number, r: number, depth: number, paint: any, edge: any?)
		local verts = {}
		for k = 0, 9 do
			local a = k * math.pi / 5
			local rad = if k % 2 == 0 then R else r
			table.insert(verts, Vector2.new(math.sin(a) * rad, math.cos(a) * rad))
		end
		local function inside(x: number, y: number): boolean
			local c = false
			local j = #verts
			for i = 1, #verts do
				local p, q = verts[i], verts[j]
				if (p.Y > y) ~= (q.Y > y) and x < (q.X - p.X) * (y - p.Y) / (q.Y - p.Y) + p.X then c = not c end
				j = i
			end
			return c
		end
		local n = math.ceil(R)
		for x = -n, n do
			for y = -n, n do
				if inside(x, y) then
					local isEdge = not (inside(x + 1, y) and inside(x - 1, y) and inside(x, y + 1) and inside(x, y - 1))
					local p = if isEdge and edge then edge else paint
					for z = 0, depth - 1 do Kit.set(g, x, y, z, p.color, p.neon, p.alpha) end
				end
			end
		end
	end
	-- A five-petal blossom round (x, y, z): a pale heart, petals out on every side.
	function P.blossom(g: any, x: number, y: number, z: number, petal: any, heart: any, petal2: any?)
		Kit.set(g, x, y, z, heart.color, heart.neon)
		for i, o in ipairs({ { 1, 0, 0 }, { -1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 }, { 0, 0, -1 } }) do
			local p = if petal2 and i % 2 == 0 then petal2 else petal
			Kit.set(g, x + o[1], y + o[2], z + o[3], p.color, p.neon)
		end
	end

	-- The carved throne: a buttoned velvet cushion on a gold apron, padded gold
	-- arm rests with jewelled finials, a tall velvet back in a gold frame with
	-- an arched crest, a gold diamond inlay round the accent jewel. Seat at
	-- height y from z0 to z1 (the back stands at z1 + 1). T: velvet, back,
	-- frame, gem, accent, button (optional), backing (optional).
	function P.throne(g: any, y: number, z0: number, z1: number, T: any)
		local F = T.frame
		Kit.box(g, -2, y, z0, 2, y, z1, T.velvet)
		if T.button then
			for _, c in ipairs({ { -1, z0 }, { 1, z0 }, { 0, z0 + 1 }, { -1, z1 }, { 1, z1 } }) do Kit.set(g, c[1], y, c[2], T.button.color) end
		end
		Kit.box(g, -2, y - 1, z0, 2, y - 1, z1, T.back)
		for x = -3, 3 do Kit.set(g, x, y - 1, z0 - 1, F.color) end
		for _, s in ipairs({ -1, 1 }) do
			Kit.box(g, 3 * s, y - 1, z0, 3 * s, y - 1, z1, F)
			Kit.box(g, 3 * s, y, z0, 3 * s, y + 1, z0, F)
			Kit.box(g, 3 * s, y + 2, z0, 3 * s, y + 2, z1 + 1, F)
			Kit.box(g, 3 * s, y + 1, z0 + 1, 3 * s, y + 1, z1, T.velvet)
			Kit.set(g, 3 * s, y + 3, z0, T.gem.color, true)
		end
		local zb = z1 + 1
		Kit.box(g, -2, y + 1, zb, 2, y + 8, zb, T.back)
		Kit.box(g, -3, y, zb + 1, 3, y + 9, zb + 1, T.backing or T.back)
		for _, s in ipairs({ -1, 1 }) do
			Kit.box(g, 3 * s, y, zb, 3 * s, y + 9, zb, F)
			Kit.set(g, 3 * s, y + 10, zb, F.color)
			Kit.set(g, 3 * s, y + 11, zb, T.gem.color, true)
		end
		Kit.box(g, -2, y + 9, zb, 2, y + 9, zb, F)
		Kit.box(g, -1, y + 10, zb, 1, y + 10, zb, F)
		Kit.set(g, 0, y + 11, zb, F.color)
		Kit.set(g, 0, y + 12, zb, T.gem.color, true)
		for _, c in ipairs({ { 0, 7 }, { -1, 6 }, { 1, 6 }, { -1, 4 }, { 1, 4 }, { 0, 3 }, { -1, 5 }, { 1, 5 } }) do
			Kit.set(g, c[1], y + c[2], zb, (if math.abs(c[1]) == 1 and c[2] == 5 then T.back else F).color)
		end
		Kit.set(g, 0, y + 5, zb, T.accent.color, true)
		Kit.set(g, 0, y + 6, zb, T.accent.color, true)
		Kit.set(g, 0, y + 4, zb, T.accent.color, true)
	end

	-- A jewelled saddle (for the mounts drawn without a throne): a seat on a
	-- gold-rimmed tree, a tall gold cantle and pommel set with jewels, cloth
	-- drapes down both flanks hemmed in gold with a jewelled medallion.
	-- T: seat, frame, gem, cloth.
	function P.saddle(g: any, hw: number, y: number, z0: number, z1: number, T: any)
		local F = T.frame
		Kit.box(g, -hw, y, z0, hw, y, z1, T.seat)
		for x = -hw, hw do
			Kit.set(g, x, y, z0 - 1, F.color)
			Kit.set(g, x, y, z1 + 1, F.color)
		end
		Kit.box(g, -hw + 1, y + 1, z1 + 1, hw - 1, y + 2, z1 + 1, F)
		Kit.set(g, 0, y + 3, z1 + 1, F.color)
		Kit.set(g, 0, y + 2, z1 + 2, T.gem.color, true)
		Kit.box(g, 0, y + 1, z0 - 1, 0, y + 2, z0 - 1, F)
		Kit.set(g, 0, y + 3, z0 - 1, T.gem.color, true)
		local zm = math.floor((z0 + z1) / 2)
		for _, s in ipairs({ -1, 1 }) do
			local x = (hw + 1) * s
			Kit.box(g, x, y - 4, z0, x, y, z1, T.cloth)
			for z = z0, z1 do Kit.set(g, x, y - 4, z, F.color) end
			for _, c in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do Kit.set(g, x, y - 2 + c[1], zm + c[2], F.color) end
			Kit.set(g, x, y - 2, zm, T.gem.color, true)
		end
	end

	-- The rune circle: two glowing rings with glyph marks between them turning
	-- one way, a star (or diamond) inside with a small ring turning the other,
	-- motes rising off it. kind: "hex" (six-pointed), "star" (five), "diamond".
	function P.runes(b: any, R: number, color: Color3, kind: string?)
		local hi = color:Lerp(WHITE, 0.45)
		local C, H = { color = color, neon = true }, { color = hi, neon = true }
		local outer = Kit.group()
		P.ring(outer, R, 1, C)
		P.ring(outer, R - 2.4, 1, H)
		for i = 0, 23 do
			local a = i / 24 * math.pi * 2
			local r = R - 1.2
			local x, z = math.floor(math.cos(a) * r + 0.5), math.floor(math.sin(a) * r + 0.5)
			if i % 3 ~= 1 then Kit.set(outer, x, 0, z, hi, true) end
		end
		b:piece({ outer }, CFrame.new(0, 0.08, 0), function(t: number): CFrame return CFrame.Angles(0, t * 0.12, 0) end)
		local inner = Kit.group()
		local r = R - 3.2
		local n = if kind == "star" then 5 elseif kind == "diamond" then 4 else 6
		local step = if n == 4 then 1 else 2
		local verts = {}
		for k = 0, n - 1 do
			local a = k / n * math.pi * 2 - math.pi / 2
			verts[k] = Vector3.new(math.cos(a) * r, 0, math.sin(a) * r)
		end
		for k = 0, n - 1 do P.line(inner, verts[k], verts[(k + step) % n], C) end
		if n == 4 then
			for k = 0, 3 do P.line(inner, verts[k] * 0.55, verts[(k + 1) % 4] * 0.55, H) end
		end
		P.ring(inner, 2, 1, H)
		Kit.set(inner, 0, 0, 0, hi, true)
		b:piece({ inner }, CFrame.new(0, 0.1, 0), function(t: number): CFrame return CFrame.Angles(0, -t * 0.22, 0) end)
		local a = b:anchor(CFrame.new())
		local motes = b:fx(a, Vector3.new(0, 0.3, 0), Vector3.new(R * 1.8 * b.V, 0.2, R * 1.8 * b.V), "stars", color)
		motes.Rate = 6
	end

	-- A gold-set jewel on a flat face: the jewel, gold round it (in the plane
	-- `axis` faces: "x" or "z").
	function P.jewel(g: any, x: number, y: number, z: number, gem: any, gold: any, axis: string)
		Kit.set(g, x, y, z, gem.color, true)
		for _, o in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
			if axis == "x" then Kit.set(g, x, y + o[1], z + o[2], gold.color) else Kit.set(g, x + o[1], y + o[2], z, gold.color) end
		end
	end

	-- A flowing ribbon: `n` small pieces trailing from a base point, waving
	-- (manes, tails, wing ribbons). pos(j, t, move) → Vector3 (bricks) in the
	-- space of `follow` (an anim, or nil: rig space). paints cycle along it.
	function P.ribbon(b: any, home: CFrame, n: number, paints: { any }, pos: any, follow: any?, size: number?)
		local out = {}
		for j = 1, n do
			local k = j
			local p = paints[(j - 1) % #paints + 1]
			local g = Kit.group()
			Kit.set(g, 0, 0, 0, p.color, p.neon, p.alpha)
			if (size or 1) > 1 then Kit.set(g, 0, 1, 0, p.color, p.neon, p.alpha) end
			table.insert(out, b:piece({ g }, home, function(t: number, move: number): CFrame
				local at = pos(k, t, move) * b.V
				local cf = CFrame.new(at)
				return if follow then follow(t, move) * cf else cf
			end))
		end
		return out
	end

	return P
end
