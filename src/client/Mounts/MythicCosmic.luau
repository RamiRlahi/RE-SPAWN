--[[
	Mounts/MythicCosmic.luau
	The cosmic Mythic mounts (×1.4), rebuilt to their reference art: Void
	Serpent, Eclipse Dragon, Wishing Star, Abyssal Leviathan Ray, Nebula
	Kirin. Studless voxels (b.smooth), glowing seams, floating pieces,
	carved thrones, rune circles. (The divine four: MythicDivine.)
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
	-- (the seat height of a mount, from RideData)
	local function W_back(look: string): number return K.W.RideData.BackHeight(look) end

	-- Deterministic randomness (the same mount looks the same every time).
	local function rng(seed: number): () -> number
		local s = seed
		return function(): number
			s = (s * 1103515245 + 12345) % 2147483648
			return s / 2147483648
		end
	end
	-- Glowing cracks wandering over a face: put(a, b) → x, y, z for a point
	-- of the face; `n` short random walks inside a0..a1 × b0..b1.
	local function cracks(g: any, put: (number, number) -> (number, number, number), a0: number, a1: number, b0: number, b1: number, n: number, paints: { any }, seed: number)
		local r = rng(seed)
		for _ = 1, n do
			local a = math.floor(a0 + r() * (a1 - a0 + 1))
			local bb = math.floor(b0 + r() * (b1 - b0 + 1))
			for _ = 1, 4 + math.floor(r() * 5) do
				local p = paints[1 + math.floor(r() * #paints)]
				local x, y, z = put(a, bb)
				Kit.set(g, x, y, z, p.color, true)
				if r() < 0.5 then a = math.clamp(a + (if r() < 0.5 then 1 else -1), a0, a1) else bb = math.clamp(bb + (if r() < 0.5 then 1 else -1), b0, b1) end
			end
		end
	end

	-- ── 21 · Void Serpent ────────────────────────────────────────────────────
	-- A horned eastern serpent of indigo-black plates that loops round under
	-- the throne in a great coil, every segment floating apart from the next
	-- with a violet seam of light and a scatter of stars in the gap; the neck
	-- rises in front to a crested head with white-hot eyes and long beaded
	-- whiskers, a crown of crystal shards turning over it; the tail breaks up
	-- into drifting cubes. Emote: it coils tighter and rises, the crown spinning.
	function M.void_serpent()
		local b = K.new("void_serpent", { emoteLen = 3 })
		b.smooth = true
		local VOID, VOID2, VOID3, BELLY = rgb(22, 14, 38), rgb(38, 26, 64), rgb(58, 38, 98), rgb(74, 52, 118)
		local ACC, ACC2, STAR, EYE, PALE = glow(112, 64, 255), glow(150, 122, 255), glow(205, 200, 255), glow(240, 244, 255), glow(196, 186, 255)
		local V = b.V
		local coil = function(t: number): number return hold(b:emPhase(t), 0.2, 2.8, 0.5) end
		b:hoverMove(0.1)
		b:spinUp(0.8)
		local wave = b:accum(function(t: number, move: number): number return 0.8 + move * 2.5 + coil(t) * 2 end)

		local function segment(s: number, i: number): any
			local g = Kit.group()
			Kit.box(g, -s, -s, -1, s, s, 1, VOID)
			for x = -s, s do
				Kit.set(g, x, s, -1, VOID2.color)
				Kit.set(g, x, s, 0, VOID2.color)
				for z = -1, 1 do Kit.set(g, x, -s, z, BELLY.color) end
			end
			for x = -s, s do
				for y = -s, s do
					if math.abs(x) == s or math.abs(y) == s then Kit.set(g, x, y, 1, ACC.color, true) end
				end
			end
			Kit.set(g, 0, s + 1, -1, VOID3.color)
			Kit.set(g, 0, s + 1, 0, VOID3.color)
			Kit.set(g, 0, s + 2, 0, (if i % 2 == 0 then ACC2 else VOID3).color, i % 2 == 0)
			for _, sx in ipairs({ -s - 1, s + 1 }) do
				Kit.set(g, sx, 0, 0, VOID3.color)
				Kit.set(g, sx, 1, -1, VOID2.color)
			end
			return g
		end

		-- the throne, on the first coil under the rider
		local body = Kit.group()
		P.throne(body, 9, -1, 1, { velvet = VOID3, back = VOID2, frame = GOLD, gem = ACC, accent = ACC2, button = GOLD, backing = VOID })
		Kit.box(body, 0, 22, 2, 0, 23, 2, GOLD)
		b:bodyPiece({ body })
		b:piece({ segment(2, 0) }, b:at(0, 6, 0) * CFrame.Angles(0, math.pi / 2, 0), function(t: number): CFrame
			return CFrame.new(0, math.sin(wave() * 1.3 + 0.6) * 0.3 * V, 0)
		end)
		-- the eye emblem over the throne
		local e = Kit.group()
		P.ring(e, 3, 1, ACC2, true)
		for k = 0, 7 do
			local a = k / 8 * math.pi * 2
			P.line(e, Vector3.new(math.cos(a) * 4, math.sin(a) * 4, 0), Vector3.new(math.cos(a) * 5.4, math.sin(a) * 5.4, 0), ACC)
		end
		for _, c in ipairs({ { -2, 0 }, { -1, 0 }, { 1, 0 }, { 2, 0 }, { -1, 1 }, { 0, 1 }, { 1, 1 }, { -1, -1 }, { 0, -1 }, { 1, -1 } }) do Kit.set(e, c[1], c[2], 0, PALE.color, true) end
		Kit.set(e, 0, 0, -0.2, ACC.color, true)
		b:emblem(e, 0, 27, 2)

		-- the coil: floating segments looping round, stars in every gap
		local N = 18
		local function at(i: number, t: number): Vector3
			local c = coil(t)
			local w = wave()
			local a = -math.pi / 2 + (i - 1) / N * 2.25 * math.pi + math.sin(w + i * 0.45) * 0.05
			local r = (7.6 - (i - 1) * 0.12) * (1 - 0.22 * c) + (if i > N - 4 then (i - (N - 4)) * 0.9 else 0)
			local y = 4 + 2 * math.cos(a + math.pi / 2) - (i - 1) * 0.1 + math.sin(w * 1.3 + i * 0.6) * 0.3 + c * 1.2
			return Vector3.new(math.cos(a) * r, y, 7.6 + math.sin(a) * r)
		end
		for i = 2, N do
			local k = i
			local g
			if i <= N - 4 then
				g = segment(if i <= N - 7 then 2 else 1, i)
			else
				-- the tail breaking up into loose cubes
				g = Kit.group()
				local spread = i - (N - 4)
				Kit.set(g, 0, 0, 0, VOID2.color)
				Kit.set(g, spread, 1, 0, ACC.color, true)
				Kit.set(g, -spread, -1, 1, VOID3.color)
				Kit.set(g, 0, spread, -1, ACC2.color, true)
			end
			b:piece({ g }, CFrame.new(), function(t: number): CFrame
				local cf = CFrame.lookAt(at(k, t) * V, at(k - 1, t) * V)
				if k > N - 4 then cf *= CFrame.Angles(t * 1.6 + k, t * 1.1, 0) end
				return cf
			end)
			b:piece({ dot((if k % 3 == 0 then STAR else ACC2).color, true) }, CFrame.new(), function(t: number): CFrame
				local m = (at(k, t) + at(k - 1, t)) / 2
				return CFrame.new((m + Vector3.new(math.sin(t * 2 + k * 3) * 0.6, math.cos(t * 1.7 + k) * 0.6, 0)) * V)
			end)
		end
		-- cubes drifting off the end of the tail, fading
		local drift = {}
		for j = 1, 8 do
			local piece = b:piece({ dot((if j % 2 == 0 then ACC else VOID3).color, j % 2 == 0) }, CFrame.new(), function(t: number): CFrame
				local k = (t * 0.35 + j / 8) % 1
				local a = j * 2.4
				return CFrame.new((at(N, t) + Vector3.new(math.cos(a) * k * 5, k * 3, math.sin(a) * k * 5)) * V) * CFrame.Angles(t, t * 0.7, 0)
			end)
			drift[j] = piece
		end
		b:every(function(t: number)
			for j, piece in ipairs(drift) do
				local p = piece.parts[1]
				if p then p.LocalTransparencyModifier = (t * 0.35 + j / 8) % 1 end
			end
		end)

		-- the neck, rising in front, and the head
		local function neckAt(s: number, t: number): Vector3
			local a, c, d = Vector3.new(0, 6, -2), Vector3.new(0, 5, -13), Vector3.new(0, 17, -13)
			local p = a * (1 - s) ^ 2 + c * 2 * s * (1 - s) + d * s * s
			return p + Vector3.new(math.sin(t * 1.1 + s * 3) * 0.4 * s, coil(t) * 1.5 * s, 0)
		end
		for k = 1, 4 do
			local s = k / 5
			b:piece({ segment(if k < 4 then 2 else 1, k) }, CFrame.new(), function(t: number): CFrame
				return CFrame.lookAt(neckAt(s, t) * V, neckAt(s + 0.2, t) * V) * CFrame.Angles(0, math.pi, 0)
			end)
		end
		local head = Kit.group()
		Kit.box(head, -2, -1, -4, 2, 2, 1, VOID)
		Kit.box(head, -2, 3, -3, 2, 3, 0, VOID2)
		Kit.box(head, -1, -1, -9, 1, 1, -5, VOID2)
		Kit.box(head, -1, 2, -8, 1, 2, -5, VOID3)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 1, -10, ACC2.color, true) end
		for _, sx in ipairs({ -2, 2 }) do
			local s = if sx > 0 then 1 else -1
			Kit.set(head, sx, 1, -3, EYE.color, true)
			Kit.set(head, sx, 1, -2, ACC.color, true)
			for i, c in ipairs({ { 2, 3, -1 }, { 2, 4, 0 }, { 3, 5, 1 }, { 3, 6, 2 }, { 3, 7, 4 }, { 4, 8, 5 } }) do
				Kit.set(head, c[1] * s, c[2], c[3], (if i >= 5 then ACC2 else VOID3).color, i >= 5)
			end
			for i, c in ipairs({ { 3, 0, -1 }, { 3, 1, 0 }, { 4, 1, 1 }, { 4, 0, 2 }, { 3, -1, 1 }, { 4, 2, 1 } }) do
				Kit.set(head, c[1] * s, c[2], c[3], (if i == 6 then ACC2 else VOID3).color, i == 6)
			end
		end
		for i, c in ipairs({ { 4, 0 }, { 5, 1 }, { 4, 2 }, { 5, 3 }, { 6, 2 }, { 6, 4 } }) do Kit.set(head, 0, c[1], c[2], (if i % 3 == 0 then ACC else VOID3).color, i % 3 == 0) end
		for _, c in ipairs({ { -3, -6 }, { -4, -5 }, { -3, -4 } }) do Kit.set(head, 0, c[1], c[2], VOID3.color) end
		b:head({ head }, 0, 19, -13, function(t: number): (number, number)
			return math.sin(t * 1.2) * 0.06 + coil(t) * 0.25 + b:mu(t) * 0.3, math.sin(t * 0.7) * 0.15
		end)
		local jaw = Kit.group()
		Kit.box(jaw, -1, -2, -8, 1, -2, -3, BELLY)
		Kit.set(jaw, -1, -2, -8, PALE.color, true)
		Kit.set(jaw, 1, -2, -8, PALE.color, true)
		b:onHead({ jaw }, Vector3.new(0, -1.5, -3), function(t: number): CFrame return CFrame.Angles(-(coil(t) * 0.35 + b:mu(t) * 0.3), 0, 0) end)
		-- long beaded whiskers, swaying
		for _, s in ipairs({ -1, 1 }) do
			local w = Kit.group()
			for i, c in ipairs({ { 0, 0 }, { -1, 0 }, { -2, 1 }, { -3, 2 }, { -4, 3 } }) do
				Kit.set(w, s, c[1], -10 + c[2], (if i == 5 then ACC2 else VOID3).color, i == 5)
			end
			b:onHead({ w }, Vector3.new(s, 0, -10), function(t: number): CFrame
				return CFrame.Angles(math.sin(t * 1.7 + s) * 0.25, 0, math.sin(t * 1.3 + s) * 0.2)
			end)
		end
		-- the crown of shards
		b:orbitVar(b:at(0, 28, -14), 5, 3.2 * V, function(t: number): number return 1.1 + coil(t) * 5 end, function()
			local g = Kit.group()
			for y = -2, 2 do Kit.set(g, 0, y, 0, (if math.abs(y) == 2 then ACC2 else ACC).color, true) end
			for _, c in ipairs({ { 1, 0 }, { -1, 0 } }) do Kit.set(g, c[1], 0, 0, ACC.color, true) end
			Kit.set(g, 0, 0, 1, PALE.color, true)
			return g
		end, 0.12, 0.3)
		b:orbitVar(b:at(0, 6, 7), 10, 12 * V, function(t: number): number return 0.35 + coil(t) end, function(i: number)
			return dot((if i % 2 == 0 then ACC else VOID3).color, i % 2 == 0)
		end, 0.15, 1.2)
		P.runes(b, 13, Color3.fromRGB(112, 64, 255), "hex")
		b:aura(b:v(5, 3, 5), b:v(0, 6, 0), "stars", Color3.fromRGB(210, 160, 255), 6)
		return b.rig
	end

	-- ── 23 · Eclipse Dragon ──────────────────────────────────────────────────
	-- The largest mount: a hulking pitch-black dragon veined all over with
	-- glowing gold cracks, a crown of back-swept horns, a heart core blazing
	-- in its chest; wings of long gold flame blades fanned up like solar
	-- flares; a black eclipse disc with a burning gold rim and corona over its
	-- back. Emote: the eclipse goes total, the corona erupts and it breathes
	-- golden fire skyward.
	function M.eclipse_dragon()
		local b = K.new("eclipse_dragon", { gait = 9, emoteLen = 3 })
		b.smooth = true
		b.flier = true
		local BLACK, BLACK2, BLACK3 = rgb(16, 14, 20), rgb(30, 26, 36), rgb(44, 38, 50)
		local VEIN, VEIN2, CORE, EYE = glow(255, 160, 40), glow(255, 205, 80), glow(255, 240, 170), glow(255, 210, 90)
		local DEEP, PALEG = glow(230, 110, 30), glow(255, 244, 190)
		local V = b.V
		local total = function(t: number): number return hold(b:emPhase(t), 0.3, 2.8, 0.5) end
		local VEINS = { VEIN, VEIN2, DEEP }
		b:gallop(8, 0.05)
		b:rearUp(5, 0.3)
		b:move(function(t: number, move: number): CFrame return CFrame.new(0, math.sin(t * 9) * 0.12 * b:flying(move), 0) end)

		local body = Kit.group()
		Kit.box(body, -4, 6, -9, 4, 12, -3, BLACK) -- chest
		Kit.box(body, -4, 7, -3, 4, 12, 4, BLACK) -- torso
		Kit.box(body, -4, 7, 4, 4, 11, 8, BLACK) -- hips
		for z = -9, 8 do
			for x = -3, 3 do Kit.set(body, x, if z < -2 then 6 else 7, z, (if z % 2 == 0 then BLACK2 else BLACK3).color) end
		end
		for z = -8, 8, 2 do
			Kit.set(body, 0, 13, z, BLACK2.color)
			if z % 4 == 0 then Kit.set(body, 0, 14, z, BLACK3.color) end
		end
		for _, sx in ipairs({ -4, 4 }) do
			cracks(body, function(a, c) return sx, a, c end, 7, 12, -9, 8, 9, VEINS, if sx > 0 then 11 else 23)
		end
		cracks(body, function(a, c) return a, 12, c end, -3, 3, -9, -3, 3, VEINS, 37)
		P.throne(body, 13, -1, 1, { velvet = BLACK3, back = BLACK2, frame = GOLD, gem = VEIN2, accent = CORE, button = GOLD, backing = BLACK })
		b:bodyPiece({ body })
		-- the heart core and the crack running down to it
		local heart = Kit.group()
		Kit.box(heart, -1, 8, -10, 1, 9, -10, CORE)
		Kit.set(heart, 0, 10, -10, VEIN2.color, true)
		Kit.set(heart, 1, 11, -10, VEIN.color, true)
		Kit.set(heart, 0, 12, -10, VEIN2.color, true)
		Kit.set(heart, -1, 7, -10, VEIN.color, true)
		Kit.set(heart, 1, 7, -10, DEEP.color, true)
		local heartPiece = b:onBody({ heart })
		b:glowUp(heartPiece, function(t: number): number return 0.15 + math.sin(t * 2.2) * 0.15 + total(t) * 0.7 end)

		-- neck and head
		local function neckAt(s: number, t: number): Vector3
			return Vector3.new(math.sin(t * 0.9 + s * 2) * 0.3 * s, 11 + 6 * s + total(t) * 1.5 * s, -9 - 4 * s)
		end
		for k = 1, 3 do
			local s = k / 4
			local g = Kit.group()
			Kit.box(g, -2, -2, -1, 2, 2, 1, BLACK)
			Kit.set(g, 0, 3, 0, BLACK3.color)
			cracks(g, function(a, c) return 2, a, c end, -2, 2, -1, 1, 1, VEINS, 50 + k)
			cracks(g, function(a, c) return -2, a, c end, -2, 2, -1, 1, 1, VEINS, 60 + k)
			b:piece({ g }, CFrame.new(), function(t: number): CFrame
				return CFrame.lookAt(neckAt(s, t) * V, neckAt(s + 0.25, t) * V) * CFrame.Angles(0, math.pi, 0)
			end)
		end
		local head = Kit.group()
		Kit.box(head, -3, -1, -5, 3, 3, 0, BLACK)
		Kit.box(head, -2, -1, -10, 2, 1, -6, BLACK2)
		Kit.box(head, -3, 4, -4, 3, 4, -2, BLACK2)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 1, -11, VEIN.color, true) end
		for _, s in ipairs({ -1, 1 }) do
			Kit.set(head, 3 * s, 2, -4, EYE.color, true)
			for i, c in ipairs({ { 2, 4, -1 }, { 3, 5, 0 }, { 3, 6, 1 }, { 4, 7, 2 }, { 4, 8, 4 }, { 5, 9, 5 } }) do
				Kit.set(head, c[1] * s, c[2], c[3], (if i >= 5 then VEIN2 else BLACK3).color, i >= 5)
			end
			for _, c in ipairs({ { 1, 5, -2 }, { 1, 6, -1 } }) do Kit.set(head, c[1] * s, c[2], c[3], BLACK3.color) end
		end
		cracks(head, function(a, c) return 3, a, c end, -1, 3, -5, 0, 2, VEINS, 71)
		cracks(head, function(a, c) return -3, a, c end, -1, 3, -5, 0, 2, VEINS, 73)
		b:head({ head }, 0, 17, -13, function(t: number): (number, number) return total(t) * 0.6 + b:mu(t) * 0.3, 0 end)
		local jaw = Kit.group()
		Kit.box(jaw, -2, -2, -10, 2, -2, -4, BLACK2)
		for _, c in ipairs({ { -2, -9 }, { 2, -9 }, { -2, -7 }, { 2, -7 } }) do Kit.set(jaw, c[1], -1, c[2], PALEG.color, true) end
		b:onHead({ jaw }, Vector3.new(0, -1.5, -4), function(t: number): CFrame return CFrame.Angles(-(total(t) * 0.45 + b:mu(t) * 0.35), 0, 0) end)
		local fire = b:emitter(b.headPiece, b:v(0, 0, -11), Vector3.one * 0.6, {
			Texture = K.FIRE, Color = ColorSequence.new(Color3.fromRGB(255, 250, 210), Color3.fromRGB(255, 170, 40)), LightEmission = 1,
			Size = K.seq(0.8, 4), Transparency = K.seq(0.05, 1), Lifetime = NumberRange.new(0.5, 0.8),
			Speed = NumberRange.new(22, 28), SpreadAngle = Vector2.new(9, 9), EmissionDirection = Enum.NormalId.Front,
			Acceleration = Vector3.new(0, 5, 0),
		})
		b:whileEmote(fire, 70, 1.0, 2.5)

		-- wings: fans of gold flame blades
		local flap = b:accum(function(_, move: number): number return 1.4 + 8 * b:flying(move) end)
		for _, side in ipairs({ -1, 1 }) do
			local function root(t: number, move: number): CFrame
				local open = math.max(b:flying(move), b:mu(t), total(t))
				return CFrame.Angles(0, -side * 0.35 * (1 - open), side * (0.15 + math.sin(flap()) * 0.3 * b:flying(move) + open * 0.2))
			end
			for k = 1, 7 do
				local len = 9 + (k % 3) * 3 + (if k == 4 then 3 else 0)
				local bar = P.bar(len, 2, { DEEP, VEIN, VEIN2, PALEG })
				local g = if side > 0 then bar else K.mirror(bar)
				local th = math.rad(-6 + (k - 1) * 16)
				b:piece({ g }, b:at(side * 4, 12, -4), function(t: number, move: number): CFrame
					return root(t, move) * CFrame.Angles(0, -side * math.rad(k * 5), side * (th + math.sin(t * 3 + k) * 0.02 + total(t) * 0.08))
				end)
			end
			b:fx(b.body, b:v(side * 8, 16, -2), b:v(8, 8, 4), "embers", Color3.fromRGB(255, 180, 70)).Rate = 6
		end

		-- the eclipse
		local discHome = b:at(0, 29, 8)
		local disc = Kit.group()
		P.disc(disc, 8, function(_, _, d)
			if d > 7.2 then return VEIN2 end
			if d > 6.4 then return DEEP end
			return rgb(6, 4, 10)
		end)
		local discPiece = b:piece({ disc }, discHome, function(t: number): CFrame return CFrame.new(0, math.sin(t * 1.2) * 0.2, 0) end)
		b:glowUp(discPiece, function(t: number): number return total(t) * 0.7 end, Color3.fromRGB(255, 250, 220))
		local spin = b:accum(function(t: number): number return 0.25 + total(t) * 1.4 end)
		for i = 0, 19 do
			local a = i / 20 * math.pi * 2
			local bar = P.bar(if i % 2 == 0 then 6 else 3, 1, { VEIN, VEIN2, PALEG })
			b:piece({ bar }, discHome, function(t: number): CFrame
				local out = 8.6 + total(t) * 3 + math.sin(t * 3 + i) * 0.3
				return CFrame.new(0, math.sin(t * 1.2) * 0.2, 0) * CFrame.Angles(0, 0, a + spin()) * CFrame.new(out * V, 0, 0.3 * V)
			end)
		end
		local burst = b:fx(discPiece, Vector3.zero, b:v(16, 16, 1), "stars", Color3.fromRGB(255, 220, 140))
		b:whileEmote(burst, 60, 0.6, 2.4)

		b:legs4({ x = 3, front = -6, hind = 5, hip = 6, w = 3,
			make = function(front: boolean, side: number): any
				local g = Kit.group()
				Kit.box(g, -1, -3, -1, 1, -1, 1, BLACK)
				Kit.box(g, -1, -5, -1, 0, -4, 0, BLACK2)
				Kit.box(g, -1, -6, -2, 1, -6, 0, BLACK)
				for _, x in ipairs({ -1, 0, 1 }) do Kit.set(g, x, -6, -3, VEIN2.color, true) end
				cracks(g, function(a, c) return side, a, c end, -5, -1, -1, 1, 1, VEINS, if front then 81 else 91)
				return g
			end })
		for i = 1, 7 do
			local k = i
			local g = Kit.group()
			local w = if i <= 2 then 2 elseif i <= 4 then 1 else 0
			Kit.box(g, -w, -1, 0, w, 1, 2, BLACK)
			Kit.set(g, 0, 2, 1, BLACK3.color)
			if i % 2 == 0 then Kit.set(g, w, 0, 1, VEIN.color, true) end
			if i == 7 then
				for _, c in ipairs({ { -1, 3 }, { 1, 3 }, { 0, 4 }, { 0, 3 } }) do Kit.set(g, c[1], 0, c[2], VEIN2.color, true) end
			end
			b:piece({ g }, b:at(0, 9 - (i - 1) * 0.4, 9 + (i - 1) * 3), function(t: number, move: number): CFrame
				local ph = t * 3 - k * 0.6
				return CFrame.new(math.sin(ph) * 0.12 * k * V, 0, 0) * CFrame.Angles(0, math.sin(ph) * 0.07 * k * (0.6 + math.min(move, 1) * 0.4), 0)
			end)
		end
		P.runes(b, 13, Color3.fromRGB(255, 180, 60), "hex")
		b:aura(b:v(8, 6, 16), b:v(0, 9, 0), "embers", Color3.fromRGB(255, 190, 70), 10)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(8, 1, 16), "embers", Color3.fromRGB(255, 190, 70), 14)
		b:dust(16, 8, Color3.fromRGB(60, 54, 50))
		return b.rig
	end

	-- ── 24 · Wishing Star ────────────────────────────────────────────────────
	-- A plump faceted star floating like a little cloud-boat, cream-white top,
	-- deep gold sides, glowing gold edges, its core shining through seams; a
	-- tufted white armchair with a gold frame for you to sit in cross-legged;
	-- little gold stars bobbing round it, a rainbow comet trail, drips of light
	-- hanging beneath. Emote: it spins and showers sparkles.
	function M.wishing_star()
		local b = K.new("wishing_star", { emoteLen = 2.6 })
		b.smooth = true
		local TOP, SIDE, LOW = rgb(255, 246, 214), rgb(255, 222, 116), rgb(232, 170, 38)
		local EDGE, RIDGE, CORE = rgb(255, 196, 52), glow(255, 226, 120), glow(255, 252, 228)
		local CREAM, BUTTON = rgb(246, 241, 232), rgb(220, 208, 190)
		local V = b.V
		local shower = function(t: number): number return hold(b:emPhase(t), 0.2, 2.4, 0.3) end
		b:spinUp(0.8)
		local R, r = 11.5, 5.2
		local verts = {}
		for k = 0, 9 do
			local a = k * math.pi / 5
			local rad = if k % 2 == 0 then R else r
			table.insert(verts, Vector2.new(math.sin(a) * rad, -math.cos(a) * rad))
		end
		local function inside(x: number, z: number): boolean
			local c = false
			local j = #verts
			for i = 1, #verts do
				local p, q = verts[i], verts[j]
				if (p.Y > z) ~= (q.Y > z) and x < (q.X - p.X) * (z - p.Y) / (q.Y - p.Y) + p.X then c = not c end
				j = i
			end
			return c
		end
		local g = Kit.group()
		local GAPS = {}
		local n = math.ceil(R)
		for x = -n, n do
			for z = -n, n do
				if not inside(x, z) then continue end
				local edge = not (inside(x + 1, z) and inside(x - 1, z) and inside(x, z + 1) and inside(x, z - 1))
				local f = 1 - math.sqrt(x * x + z * z) / R
				local yb, yt = -math.floor(f * 2.4), math.floor(f * 3.2) + 1
				-- the five ridges running out to the points
				local ridge = false
				for k = 0, 4 do
					local a = k * 2 * math.pi / 5
					local dx, dz = math.sin(a), -math.cos(a)
					local along = x * dx + z * dz
					if along > 0.5 and math.abs(x * dz - z * dx) < 0.55 then ridge = true end
				end
				for y = yb, yt do
					local p = if edge then EDGE elseif y == yt then (if ridge then RIDGE else TOP) elseif y >= 0 then SIDE else LOW
					Kit.set(g, x, y, z, p.color, p.neon)
				end
				local d = math.sqrt(x * x + z * z)
				if not edge and not ridge and d > 2.6 and d < 5.8 and (x * 3 + z * 7) % 5 == 0 then table.insert(GAPS, { x, yt, z }) end
			end
		end
		K.carve(g, GAPS)
		-- the tufted armchair
		Kit.box(g, -2, 5, -1, 2, 5, 1, CREAM)
		for _, c in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do Kit.set(g, c[1], 5, c[2], BUTTON.color) end
		for _, s in ipairs({ -1, 1 }) do
			Kit.box(g, 3 * s, 5, -1, 3 * s, 6, 1, CREAM)
			Kit.box(g, 3 * s, 7, -1, 3 * s, 7, 1, GOLD)
			Kit.set(g, 3 * s, 6, -2, GOLD.color)
			Kit.set(g, 3 * s, 5, -2, GOLD.color)
		end
		Kit.box(g, -2, 6, 2, 2, 10, 2, CREAM)
		for _, c in ipairs({ { -1, 7 }, { 1, 7 }, { 0, 8 }, { -1, 9 }, { 1, 9 } }) do Kit.set(g, c[1], c[2], 2, BUTTON.color) end
		Kit.box(g, -3, 5, 2, -3, 10, 2, GOLD)
		Kit.box(g, 3, 5, 2, 3, 10, 2, GOLD)
		Kit.box(g, -2, 11, 2, 2, 11, 2, GOLD)
		Kit.box(g, -1, 12, 2, 1, 12, 2, GOLD)
		Kit.set(g, 0, 13, 2, EDGE.color, true)
		Kit.box(g, -3, 5, 3, 3, 11, 3, GOLD)
		local home = CFrame.new(0, W_back("wishing_star") - 5.5 * V, 0)
		local spin = b:accum(function(t: number): number return 0.4 + shower(t) * 6 end)
		local function starAnim(t: number, move: number): CFrame
			return K.W.hover(t, move) * CFrame.Angles(0, spin(), 0)
		end
		local starPiece = b:piece({ g }, home, starAnim)
		b.body = starPiece
		local core = Kit.group()
		for _, c in ipairs(GAPS) do Kit.set(core, c[1], c[2], c[3], CORE.color, true) end
		local corePiece = b:piece({ core }, home, starAnim)
		b:glowUp(corePiece, function(t: number): number return 0.3 + math.sin(t * 3) * 0.3 end)
		-- drips of light hanging under it
		for k = 0, 4 do
			local a = k * 2 * math.pi / 5 + math.pi / 5
			local x, z = math.sin(a) * 3.5, -math.cos(a) * 3.5
			local d = Kit.group()
			local len = 2 + k % 3
			for y = 0, len do Kit.set(d, 0, -y, 0, (if y == len then CORE else RIDGE).color, true) end
			b:piece({ d }, home, function(t: number, move: number): CFrame
				return starAnim(t, move) * CFrame.new(x * V, (-1.5 + math.sin(t * 2 + k) * 0.3) * V, z * V)
			end)
		end
		b:fx(starPiece, Vector3.new(0, -1.2 * V, 0), Vector3.new(7 * V, 0.2, 7 * V), "drip", Color3.fromRGB(255, 230, 140)).Rate = 6
		b:fx(starPiece, Vector3.zero, Vector3.new(12 * V, 1, 12 * V), "stars", Color3.fromRGB(255, 235, 140))
		local sparkle = b:fx(starPiece, Vector3.new(0, 1, 0), Vector3.new(16 * V, 1, 16 * V), "stars", Color3.fromRGB(255, 250, 200))
		b:whileEmote(sparkle, 80, 0.3, 2.3)
		local tail = b:anchor(home, function(t: number, move: number): CFrame return K.W.hover(t, move) end)
		local BOW = { { 255, 80, 90 }, { 255, 160, 60 }, { 255, 235, 90 }, { 110, 230, 120 }, { 90, 170, 255 }, { 180, 110, 255 } }
		for i, c in ipairs(BOW) do b:trail(tail, Vector3.new((i - 3.5) * 0.55, 0.3, 7 * V), 0.6, Color3.fromRGB(c[1], c[2], c[3]), 1.2) end
		-- little gold stars bobbing round it
		b:orbitVar(home * CFrame.new(0, 9 * V, 0), 5, 10 * V, function(t: number): number return 0.5 + shower(t) * 4 end, function()
			local s = Kit.group()
			P.star(s, 2.6, 1.1, 2, RIDGE, EDGE)
			return s
		end, 0.2, 0.8)
		P.runes(b, 12, Color3.fromRGB(255, 220, 110), "star")
		return b.rig
	end

	-- ── 25 · Abyssal Leviathan Ray ───────────────────────────────────────────
	-- A gigantic manta gliding on the air, deep navy fading to blue at the
	-- wing edges, its back starred with rows of bioluminescent cyan dots, the
	-- trailing edges of its wings unravelling into long flowing ribbons that
	-- curl up behind; a carved throne in the middle, an ancient eye opening in
	-- front of it, a long whip tail. Emote: the eye opens wide and the dots
	-- pulse out across the wings in a wave.
	function M.abyssal_leviathan_ray()
		local b = K.new("abyssal_leviathan_ray", { emoteLen = 3 })
		b.smooth = true
		local NAVY, NAVY2, BLUE, EDGE, BELLY = rgb(12, 22, 52), rgb(20, 38, 86), rgb(32, 70, 142), rgb(52, 110, 196), rgb(112, 144, 190)
		local CYAN, CYAN2, IRIS, PUPIL = glow(60, 225, 255), glow(170, 245, 255), glow(110, 240, 255), rgb(6, 10, 18)
		local RIB = glass(80, 160, 255, 0.35)
		local V = b.V
		local yTop = W_back("abyssal_leviathan_ray") - 0.5 * V
		local stare = function(t: number): number return hold(b:emPhase(t), 0.3, 2.7, 0.4) end
		b:spinUp(0.5)
		local swim = b:accum(function(_, move: number): number return 2.2 + move * 2 end)
		local function wave(xc: number, t: number, move: number): CFrame
			local ph = swim() - math.abs(xc) * 0.35
			local amp = math.abs(xc) / 12 * (0.5 + math.min(move, 1) * 0.4)
			return K.W.hover(t, move) * CFrame.new(0, math.sin(ph) * amp, 0) * CFrame.Angles(0, 0, -math.sign(xc) * math.cos(ph) * amp * 0.08)
		end
		local function halfW(z: number): number return 13 - math.abs(z + 1) * 1.45 end
		local strips = { { -13, -10 }, { -9, -6 }, { -5, 5 }, { 6, 9 }, { 10, 13 } }
		local mid
		for si, s in ipairs(strips) do
			local xc = (s[1] + s[2]) / 2
			local g = Kit.group()
			local dotsIn, dotsOut = Kit.group(), Kit.group()
			for x = s[1], s[2] do
				for z = -9, 8 do
					local hw = halfW(z)
					if math.abs(x) <= hw then
						local e = hw - math.abs(x)
						local top = if e < 1.2 then EDGE elseif e < 3 then BLUE elseif math.abs(x) > 5 then NAVY2 else NAVY
						Kit.set(g, x - xc, 0, z, top.color)
						Kit.set(g, x - xc, -1, z, BELLY.color)
						if math.abs(x) <= 4 and math.abs(z) <= 5 then Kit.set(g, x - xc, -2, z, BELLY.color) end
						-- rows of glowing dots
						if math.abs(x) > 3 and (x + (if z % 2 == 0 then 0 else 1)) % 2 == 0 and z % 2 == 0 then
							local d = if math.abs(x) > 8 then dotsOut else dotsIn
							Kit.set(d, x - xc, 0.12, z, (if (x * 3 + z) % 7 == 0 then CYAN2 else CYAN).color, true)
						end
					end
				end
			end
			if xc == 0 then
				for _, sx in ipairs({ -3, 3 }) do -- cephalic fins curling forward
					local s = if sx > 0 then 1 else -1
					for _, c in ipairs({ { 0, 0, -10 }, { 0, 0, -11 }, { -1, 1, -12 }, { -1, 1, -11 } }) do Kit.set(g, sx + c[1] * s, c[2], c[3], NAVY2.color) end
				end
				P.throne(g, 1, -1, 1, { velvet = rgb(24, 52, 104), back = NAVY2, frame = GOLD, gem = CYAN, accent = CYAN2, button = GOLD, backing = NAVY })
			end
			local function anim(t: number, move: number): CFrame return wave(xc, t, move) end
			local piece = b:piece({ g }, CFrame.new(xc * V, yTop, 0), anim)
			if xc == 0 then mid = piece end
			for di, d in ipairs({ dotsIn, dotsOut }) do
				local dp = b:piece({ d }, CFrame.new(xc * V, yTop, 0), anim)
				local band = math.abs(xc) / 4 + di
				b:glowUp(dp, function(t: number): number
					local p = b:emPhase(t)
					local w = if p then math.max(0, math.sin(p * 6 - band * 0.8)) * stare(t) else 0
					return math.max(w, math.max(0, math.sin(t * 1.4 - band * 0.6)) * 0.3)
				end)
			end
		end
		b.body = mid
		-- the ancient eye in front of the throne, heavy lids sliding open
		local eye = Kit.group()
		Kit.box(eye, -2, 0, -6, 2, 0, -4, IRIS)
		Kit.set(eye, -2, 0, -6, NAVY2.color)
		Kit.set(eye, 2, 0, -6, NAVY2.color)
		Kit.set(eye, -2, 0, -4, NAVY2.color)
		Kit.set(eye, 2, 0, -4, NAVY2.color)
		Kit.set(eye, 0, 0, -5, PUPIL.color)
		b:piece({ eye }, CFrame.new(0, yTop + 0.06, 0), function(t: number, move: number): CFrame return wave(0, t, move) end)
		for _, side in ipairs({ -1, 1 }) do
			local lid = Kit.group()
			Kit.box(lid, -3, 0, 0, 3, 0, 1, NAVY2)
			b:piece({ lid }, CFrame.new(0, yTop + 0.5 * V, -5.5 * V + side * 0.5 * V), function(t: number, move: number): CFrame
				local open = math.max(stare(t), if (t % 6) < 1.5 then 0.35 else 0)
				return wave(0, t, move) * CFrame.new(0, 0, side * (open * 2 - 0.5) * V)
			end)
		end
		-- ribbons unravelling from the trailing edges, curling up behind
		for ri, base in ipairs({ { -11, 4 }, { -7, 6 }, { -3, 7 }, { 3, 7 }, { 7, 6 }, { 11, 4 } }) do
			local bx, bz = base[1], base[2]
			P.ribbon(b, CFrame.new(0, yTop, 0), 10, { RIB, CYAN, RIB, RIB }, function(j: number, t: number): Vector3
				local w = swim() - j * 0.5 + ri
				return Vector3.new(bx + math.sin(w) * j * 0.18, j ^ 1.25 * 0.42 + math.sin(w * 0.8) * 0.4, bz + j * 1.5)
			end, function(t: number, move: number): CFrame return K.W.hover(t, move) end, 2)
		end
		-- the whip tail
		P.ribbon(b, CFrame.new(0, yTop - 0.5 * V, 0), 12, { NAVY2, NAVY2, BLUE, CYAN }, function(j: number, t: number): Vector3
			return Vector3.new(math.sin(swim() - j * 0.6) * j * 0.12, -0.3 * j * 0.2, 8 + j * 1.4)
		end, function(t: number, move: number): CFrame return K.W.hover(t, move) end)
		b:orbitVar(CFrame.new(0, yTop + 2, 0), 12, 15 * V, function(): number return 0.35 end, function(i: number)
			return dot((if i % 3 == 0 then CYAN2 else CYAN).color, true)
		end, 0.1, 1)
		P.runes(b, 13, Color3.fromRGB(60, 210, 255), "diamond")
		b:aura(Vector3.new(22 * V, 1, 16 * V), Vector3.zero, "stars", Color3.fromRGB(80, 220, 255), 8)
		return b.rig
	end

	-- ── 28 · Nebula Kirin ────────────────────────────────────────────────────
	-- A slender deer-dragon of deep indigo starred with sparkles, gold antlers,
	-- gold armour set with blue crystals, a crystal on its chest, and a great
	-- flowing mane and tail of nebula in violet, blue and white
	-- (Models/nebula_kirin: the artist's voxel model, tools/mounts/export.py).
	-- Emote: its mane and tail swirl round like a galaxy.
	function M.nebula_kirin()
		local b = K.new("nebula_kirin", { gait = 10, emoteLen = 2.8 })
		local swirl = function(t: number): number return hold(b:emPhase(t), 0.2, 2.6, 0.45) end
		b:gallop(8, 0.08)
		b:rearUp(5, 0.35)
		local a = b:horseAnims({ head = function(t: number): number return swirl(t) * 0.25 + b:mu(t) * 0.3 end })
		-- the mane and tail stream and, on the emote, whirl round
		local mane0, tail0 = a.mane, a.tail
		a.mane = function(t: number, move: number): CFrame
			return mane0(t, move) * CFrame.Angles(0, math.sin(t * 3) * swirl(t) * 0.45, math.sin(t * 2.3) * 0.05)
		end
		a.tail = function(t: number, move: number): CFrame
			local sw = swirl(t)
			return tail0(t, move) * CFrame.Angles(-sw * 0.4, math.sin(t * 4) * sw * 0.7, 0)
		end
		local pieces = b:model(require(script.Parent:WaitForChild("Models"):WaitForChild("nebula_kirin")), a, LONGER)
		if pieces.gem then b:glowUp(pieces.gem, function(t: number): number return 0.15 + math.sin(t * 2.2) * 0.15 + swirl(t) * 0.5 end) end
		if pieces.mane then b:glowUp(pieces.mane, function(t: number): number return swirl(t) * 0.35 end, Color3.fromRGB(235, 225, 255)) end
		b:legacy(function()
			b:orbitVar(b:at(0, 10, 0), 10, 10 * b.V, function(t: number): number return 0.5 + swirl(t) * 3 end, function(i: number)
				return dot((if i % 3 == 0 then glow(255, 120, 230) elseif i % 2 == 0 then glow(255, 255, 255) else glow(96, 140, 255)).color, true)
			end, 0.2, 1)
		end)
		b:runTrail(Vector3.new(0, 0.5, 0), b:v(25, 4, 60), "stars", Color3.fromRGB(170, 140, 255), 16)
		local sparkle = b:fx(b.body, b:v(0, 38, 0), b:v(20, 15, 60), "stars", Color3.fromRGB(190, 160, 255))
		sparkle.Rate = 0
		b:atMount(0.3, function() sparkle:Emit(30) end)
		b:dust(60, 25, Color3.fromRGB(120, 110, 160))
		return b.rig
	end

	return M
end
