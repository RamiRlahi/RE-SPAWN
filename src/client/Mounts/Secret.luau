--[[
	Mounts/Secret.luau
	Secret mounts: boss trophies, horse-sized (×1.0). Miniature chibi bosses,
	big heads on short stubby bodies, tamed and loyal, each in its boss's
	colours. Every one wears the black-and-gold "SECRET" frame (BeastKit's
	trophy: a floating gold crown over the saddle, a trophy plate, a flickering
	black-gold aura) and moves in exaggerated, bouncy chibi motion.
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

	-- Bouncy chibi motion: a big hop each step, a sway, a squash at rest.
	local function bouncy(b: any, amp: number?)
		b:move(function(t: number, move: number): CFrame
			local m = math.min(move, 1.2)
			return CFrame.new(0, math.abs(math.sin(t * b.gait)) * (amp or 0.3) * m + math.max(0, math.sin(t * 3)) * 0.03, 0)
				* CFrame.Angles(0, 0, math.sin(t * b.gait) * 0.07 * m)
		end)
	end
	-- The big chibi head: it squashes down on every step and bobs at rest.
	-- extra(t, move) → pitch, yaw, roll.
	local function chibiHead(b: any, groups: { any }, x: number, y: number, z: number, extra: any?): any
		local anim = function(t: number, move: number): CFrame
			local m = math.min(move, 1.2)
			local squish = -math.abs(math.sin(t * b.gait)) * 0.12 * m + math.sin(t * 3) * 0.04
			local p, yw, rl = 0, 0, 0
			if extra then p, yw, rl = extra(t, move) end
			return CFrame.new(0, squish, 0) * CFrame.Angles(math.sin(t * b.gait * 2) * 0.05 * m + (p or 0),
				math.sin(t * 0.8) * 0.15 * math.max(0, 1 - move) + (yw or 0), rl or 0)
		end
		b.headHome, b.headAnim = b:at(x, y, z), anim
		b.headPiece = b:piece(groups, b.headHome, anim)
		return anim
	end
	-- Four stubby legs in a quick trot (diagonal pairs together).
	local function trot4(b: any, o: any): { any }
		local TROT = { [true] = { [-1] = 0, [1] = math.pi }, [false] = { [-1] = math.pi, [1] = 0 } }
		local out = {}
		local w = o.w or 2
		local off = if w % 2 == 0 then 0.5 else 0
		for _, front in ipairs({ true, false }) do
			for _, side in ipairs({ -1, 1 }) do
				local base = (if front then K.FRONT_LAG else 0) + (if side > 0 then K.SIDE_LAG else 0)
				local g = K.legGroup(o.len, w, o.main, o.foot)
				table.insert(out, b:leg(g, side * o.x + off, o.hip, if front then o.front else o.hind, front, side,
					{ phase = TROT[front][side] - base, amp = 0.75, extra = o.extra and function(t: number, move: number): number return o.extra(t, move, front, side) end or nil }))
			end
		end
		return out
	end
	-- Big round chibi eyes on a face at depth z (white, pupil, glint).
	local function eyes(g: any, xs: { number }, y: number, z: number, white: Color3, pupil: Color3)
		for _, x in ipairs(xs) do
			local s = if x > 0 then 1 else -1
			Kit.box(g, math.min(x, x + s), y, z, math.max(x, x + s), y + 1, z, { color = white })
			Kit.set(g, x, y, z, pupil)
		end
	end

	-- Mini Ignarath, the Cinder Wyrmling: a tiny red dragon, oversized horns,
	-- stubby folded wings, a lava-cracked glowing belly, ember puffs from its
	-- nostrils, a flame on its tail. Emote: tries to breathe fire and coughs
	-- out a smoke ring.
	function M.mini_ignarath()
		local b = K.new("mini_ignarath", { gait = 13, emoteLen = 2.6, mountLen = 1.0 })
		local RED, RED2, DARK, HORN = rgb(200, 50, 30), rgb(232, 82, 42), rgb(60, 20, 16), rgb(242, 222, 184)
		local BELLY, BELLY2, FLAME = glow(255, 130, 40), glow(255, 200, 90), Color3.fromRGB(255, 120, 30)
		local V = b.V
		local inhale = function(t: number): number return hold(b:emPhase(t), 0.1, 0.8, 0.3) end
		local cough = function(t: number): number
			local p = b:emPhase(t)
			return if p and p > 0.8 and p < 1.9 then math.abs(math.sin((p - 0.8) * 14)) * (1.9 - p) else 0
		end
		bouncy(b, 0.35)
		b:hopUp(1.1)
		b:move(function(t: number): CFrame return CFrame.new(0, cough(t) * 0.15, 0) * CFrame.Angles(-cough(t) * 0.12, 0, 0) end)

		local body = Kit.group()
		Kit.box(body, -2, 3, -3, 2, 6, 3, RED)
		for x = -1, 1 do
			for y = 3, 5 do Kit.set(body, x, y, -4, (if (x + y) % 2 == 0 then BELLY else BELLY2).color, true) end
		end
		for z = -2, 2, 2 do Kit.set(body, 0, 3, z, BELLY.color, true) end
		K.saddle(body, 2, 7, -1, 1, rgb(90, 40, 30), DARK, DARK)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -3, 0, -6, 3, 5, 0, RED)
		Kit.box(head, -2, 0, -8, 2, 2, -7, RED2)
		for _, sx in ipairs({ -1, 1 }) do Kit.set(head, sx, 2, -8, DARK.color) end
		eyes(head, { -2, 2 }, 3, -7, Color3.new(1, 1, 1), Color3.fromRGB(20, 10, 10))
		for _, s in ipairs({ -1, 1 }) do
			for _, c in ipairs({ { 2, 6, -2 }, { 2, 7, -1 }, { 3, 8, 0 }, { 3, 9, 1 }, { 3, 10, 1 } }) do Kit.set(head, c[1] * s, c[2], c[3], HORN.color) end
		end
		chibiHead(b, { head }, 0, 6, -3, function(t: number): (number, number, number)
			return inhale(t) * 0.35 - cough(t) * 0.25 + b:mu(t) * 0.3, 0, 0
		end)
		local puff = b:fx(b.headPiece, b:v(0, 2, -9), Vector3.one * 0.3, "embers", FLAME)
		puff.Rate = 3
		-- the smoke ring it coughs out, drifting forward and up
		local ring = Kit.group()
		for i = 0, 7 do
			local a = i / 8 * math.pi * 2
			Kit.set(ring, math.floor(math.cos(a) * 2 + 0.5), math.floor(math.sin(a) * 2 + 0.5), 0, Color3.fromRGB(120, 115, 112))
		end
		local ringPiece = b:piece({ ring }, b:at(0, 7, -12), function(t: number): CFrame
			local p = b:emPhase(t) or 0
			local k = math.clamp((p - 0.85) / 1.4, 0, 1)
			return CFrame.new(0, k * 4 * V, -k * 6 * V) * CFrame.Angles(0, 0, k * 2)
		end)
		b:fade(ringPiece.parts, function(t: number): number
			local p = b:emPhase(t)
			if not p or p < 0.85 then return 1 end
			return math.clamp((p - 0.85) / 1.4, 0, 1)
		end)
		local smoke = b:fx(b.headPiece, b:v(0, 2, -9), Vector3.one * 0.3, "smoke", Color3.fromRGB(110, 105, 100))
		b:whileEmote(smoke, 25, 0.85, 1.6)

		local depth = { 2, 3, 3, 2 }
		local wing = Kit.group()
		for x = 1, #depth do for z = 1, depth[x] do Kit.set(wing, x, 0, z, RED2.color) end end
		for x = 0, #depth do Kit.set(wing, x, 0, 0, DARK.color) end
		for _, side in ipairs({ -1, 1 }) do
			b:wing(if side > 0 then wing else K.mirror(wing), side * 2.5, 7, -1, side, { beat = 16,
				spread = function(t: number): number return math.max(b:mu(t), inhale(t)) end })
		end
		trot4(b, { x = 1.5, front = -2, hind = 2, hip = 3, len = 3, w = 2, main = RED, foot = DARK })
		local tail = Kit.group()
		Kit.box(tail, -1, 0, 0, 0, 1, 1, RED)
		Kit.set(tail, 0, 1, 2, RED.color)
		Kit.set(tail, 0, 2, 3, BELLY.color, true)
		Kit.set(tail, 0, 3, 3, BELLY2.color, true)
		local tp = b:tail({ tail }, 0.5, 4, 3, function(t: number): (number, number) return 0, math.sin(t * 10) * 0.25 end)
		b:fx(tp, b:v(0, 3, 3), Vector3.one * 0.4, "fire", FLAME).Rate = 12
		b:trophy(0, 7, 0, 2)
		b:runTrail(Vector3.new(0, 0.4, 0), b:v(4, 1, 6), "embers", FLAME, 12)
		b:dust(6, 5)
		return b.rig
	end

	-- Mini ZAR-0, the Arcade Djinn: a tiny floating magenta djinn with an
	-- arcade-cabinet body, a pixel-screen face with 8-bit eyes, big chunky
	-- floating hands, a pink-cyan pixel smoke tail. You sit cross-legged on
	-- its joystick deck; gold coins circle it. Emote: its screen flashes 1UP
	-- and it spits out coins.
	function M.mini_zar0()
		local b = K.new("mini_zar0", { emoteLen = 2.6, mountLen = 1.0 })
		local MAG, MAG2, BLACK, SCREEN = rgb(230, 40, 170), rgb(255, 92, 202), rgb(20, 16, 24), rgb(16, 8, 26)
		local CYAN, PIX, GOLDC, RED = glow(60, 240, 255), glow(60, 240, 255), glow(255, 200, 40), glow(255, 60, 60)
		local V = b.V
		local oneUp = function(t: number): boolean
			local p = b:emPhase(t)
			return p ~= nil and p > 0.2 and p < 1.6 and math.floor(p * 6) % 2 == 0
		end
		b:hoverMove(0.2)
		b:spinUp(0.6)

		-- the joystick deck you sit on, the cabinet rising behind you
		local body = Kit.group()
		Kit.box(body, -3, 6, -3, 3, 6, 2, BLACK)
		for x = -3, 3 do
			Kit.set(body, x, 6, -4, MAG2.color)
			Kit.set(body, x, 6, 3, MAG2.color)
		end
		Kit.box(body, 0, 7, -4, 0, 8, -4, BLACK) -- joystick
		Kit.set(body, 0, 9, -4, RED.color, true)
		Kit.set(body, -2, 7, -4, CYAN.color, true)
		Kit.set(body, 2, 7, -4, MAG2.color, true)
		Kit.box(body, -3, 7, 3, 3, 21, 6, MAG) -- the cabinet
		Kit.box(body, -3, 22, 3, 3, 22, 6, MAG2) -- marquee
		Kit.box(body, -2, 15, 2, 2, 19, 2, SCREEN) -- the screen
		Kit.set(body, 0, 12, 2, GOLDC.color, true) -- coin slot
		b:bodyPiece({ body })
		-- the face: 8-bit eyes and a grin, or 1UP
		local face = Kit.group()
		for _, c in ipairs({ { -1, 18 }, { 1, 18 }, { -1, 17 }, { 1, 17 }, { -2, 16 }, { 2, 16 }, { -1, 15 }, { 0, 15 }, { 1, 15 } }) do Kit.set(face, c[1], c[2], 1.9, PIX.color, true) end
		local facePiece = b:onBody({ face })
		local up = Kit.group()
		for _, c in ipairs({ { -2, 19 }, { -2, 18 }, { -2, 17 }, { -2, 16 }, { -2, 15 }, { 0, 18 }, { 0, 17 }, { 0, 16 }, { 1, 15 }, { 2, 16 }, { 2, 17 }, { 2, 18 }, { 1, 19 }, { 2, 19 } }) do
			Kit.set(up, c[1], c[2], 1.9, Color3.fromRGB(255, 230, 60), true)
		end
		local upPiece = b:onBody({ up })
		b:fade(facePiece.parts, function(t: number): number return if oneUp(t) then 1 else 0 end)
		b:fade(upPiece.parts, function(t: number): number return if oneUp(t) then 0 else 1 end)
		-- big chunky floating hands
		for _, side in ipairs({ -1, 1 }) do
			local h = Kit.group()
			Kit.box(h, -1, -1, -1, 1, 1, 1, MAG2)
			for _, fz in ipairs({ -1, 1 }) do Kit.set(h, side * 2, 0, fz, MAG2.color) end
			Kit.set(h, 0, 2, -1, MAG.color)
			b:piece({ h }, b:at(side * 6, 13, 1), function(t: number, move: number): CFrame
				local wave = b:emPhase(t) and math.sin(t * 12) * 0.4 or 0
				return CFrame.new(0, math.sin(t * 2.2 + side) * 0.3, -math.min(move, 1) * 0.4) * CFrame.Angles(math.sin(t * 1.7 + side) * 0.2 + wave, 0, side * 0.2)
			end)
		end
		-- the pixel smoke tail, trailing down under it
		for i = 1, 6 do
			local k = i
			b:piece({ (function()
				local g = Kit.group()
				Kit.set(g, 0, 0, 0, (if i % 2 == 0 then CYAN else MAG2).color, i % 2 == 0)
				return g
			end)() }, b:at(0, 6 - i * 0.9, 4 + i * 0.8), function(t: number, move: number): CFrame
				return CFrame.new(math.sin(t * 3 - k * 0.7) * 0.3 * k * V, math.sin(t * 2 + k) * 0.1, math.min(move, 1) * k * 0.15)
			end)
		end
		-- coins spat from the slot: each flies out in an arc
		for i = 1, 5 do
			local c = Kit.group()
			Kit.box(c, -1, -1, 0, 1, 1, 0, GOLDC)
			local cp = b:piece({ c }, b:at(0, 12, 1), function(t: number): CFrame
				local p = (b:emPhase(t) or 0) - 0.3 - i * 0.15
				local k = math.clamp(p / 0.9, 0, 1)
				local a = (i - 3) * 0.5
				return CFrame.new(math.sin(a) * k * 8 * V, (k * 10 - k * k * 16) * V, -math.cos(a) * k * 8 * V) * CFrame.Angles(0, t * 8, 0)
			end)
			b:fade(cp.parts, function(t: number): number
				local p = (b:emPhase(t) or 0) - 0.3 - i * 0.15
				return if p > 0 and p < 0.9 then 0 else 1
			end)
		end
		b:orbitVar(b:at(0, 12, 2), 5, 9 * V, function(): number return 1.1 end, function()
			local c = Kit.group()
			Kit.box(c, 0, -1, -1, 0, 1, 1, GOLDC)
			return c
		end, 0.2, 0.4)
		local bits = b:fx(b.body, b:v(0, 4, 5), b:v(3, 3, 3), "sparks", Color3.fromRGB(255, 90, 210))
		bits.Rate = 6
		b:trophy(0, 6, 0, 3)
		return b.rig
	end

	-- Mini Malakor, the Fallen Angel: a small dark armoured winged knight-
	-- beast on all fours, crimson eyes, a cracked black halo, tattered black
	-- and red feather wings. Emote: tries to look menacing, and its halo
	-- slips over one eye.
	function M.mini_malakor()
		local b = K.new("mini_malakor", { gait = 13, emoteLen = 2.8, mountLen = 1.0 })
		local ARMOR, ARMOR2, DARK = rgb(30, 28, 36), rgb(52, 48, 60), rgb(12, 10, 14)
		local RED, FEATHER, FEATHER2 = glow(230, 20, 40), rgb(22, 18, 22), rgb(130, 22, 32)
		local V = b.V
		local menace = function(t: number): number return hold(b:emPhase(t), 0.1, 1.1, 0.25) end
		local slip = function(t: number): number return hold(b:emPhase(t), 0.9, 2.6, 0.3) end
		bouncy(b, 0.32)
		b:hopUp(1.1)
		b:rearUp(2, 0)
		b:move(function(t: number): CFrame
			local m = menace(t)
			if m == 0 then return CFrame.identity end
			return CFrame.new(0, 0, 2 * V) * CFrame.Angles(0.2 * m, 0, 0) * CFrame.new(0, 0, -2 * V)
		end)

		local body = Kit.group()
		Kit.box(body, -2, 3, -3, 2, 6, 3, ARMOR)
		Kit.box(body, -2, 6, -3, 2, 6, -2, ARMOR2)
		Kit.box(body, -2, 6, 2, 2, 6, 3, ARMOR2)
		K.saddle(body, 2, 7, -1, 1, rgb(70, 16, 22), DARK, DARK)
		b:bodyPiece({ body })

		local head = Kit.group()
		Kit.box(head, -3, 0, -6, 3, 5, 0, ARMOR)
		Kit.box(head, -3, 5, -6, 3, 5, -1, ARMOR2)
		Kit.box(head, -2, 3, -7, 2, 3, -7, DARK)
		for _, sx in ipairs({ -1, 1 }) do
			Kit.set(head, sx, 3, -7, RED.color, true)
			Kit.set(head, sx * 3, 6, -2, ARMOR2.color)
			Kit.set(head, sx * 3, 7, -1, ARMOR2.color)
		end
		chibiHead(b, { head }, 0, 6, -3, function(t: number): (number, number, number)
			-- (chin up to look tough; then a sheepish tilt as the halo slips)
			return menace(t) * 0.25 - slip(t) * 0.1 + b:mu(t) * 0.3, 0, slip(t) * 0.25
		end)
		-- the cracked black halo, floating over its helm
		local halo = Kit.group()
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			local cracked = i == 2 or i == 7
			Kit.set(halo, math.floor(math.cos(a) * 3 + 0.5), 0, math.floor(math.sin(a) * 3 + 0.5), (if cracked then RED else DARK).color, cracked)
		end
		b:onHead({ halo }, Vector3.new(0, 9, -3), function(t: number): CFrame
			local s = slip(t)
			return CFrame.new(-1.2 * V * s, (math.sin(t * 2.4) * 0.15 * (1 - s)) - 5.5 * V * s, -3.2 * V * s) * CFrame.Angles(1.3 * s, t * 0.6 * (1 - s), 0.5 * s)
		end)
		-- tattered feather wings
		local wing = Kit.group()
		local depth = { 3, 4, 4, 3, 2 }
		for x = 1, #depth do
			for z = 1, depth[x] do
				if (x + z) % 4 ~= 0 then Kit.set(wing, x, 0, z, (if z == depth[x] then FEATHER2 else FEATHER).color) end
			end
		end
		for x = 0, #depth do Kit.set(wing, x, 0, 0, ARMOR2.color) end
		for _, side in ipairs({ -1, 1 }) do
			b:wing(if side > 0 then wing else K.mirror(wing), side * 2.5, 7, -1, side, { beat = 15,
				spread = function(t: number): number return math.max(b:mu(t), menace(t)) end })
		end
		trot4(b, { x = 1.5, front = -2, hind = 2, hip = 3, len = 3, w = 2, main = ARMOR, foot = ARMOR2 })
		local tail = Kit.group()
		Kit.box(tail, -1, 0, 0, 0, 1, 1, ARMOR)
		Kit.set(tail, 0, 1, 2, ARMOR2.color)
		Kit.set(tail, 0, 2, 3, RED.color, true)
		b:tail({ tail }, 0.5, 4, 3)
		b:fx(b.body, b:v(0, 6, 0), b:v(5, 3, 6), "embers", Color3.fromRGB(220, 30, 40)).Rate = 4
		b:trophy(0, 7, 0, 2)
		b:dust(6, 5, Color3.fromRGB(70, 60, 70))
		return b.rig
	end

	-- Mini Bone Colossus: a squat bone golem, a big skull you sit on top of,
	-- ribs, huge shoulders, short legs, an ember core glowing in its ribcage.
	-- Emote: it stomps, and a tiny meteor drops beside it.
	function M.mini_bone_colossus()
		local b = K.new("mini_bone_colossus", { gait = 11, emoteLen = 2.6, mountLen = 1.0 })
		local BONE, BONE2, SOCKET = rgb(226, 218, 196), rgb(196, 188, 164), rgb(40, 36, 30)
		local EMBER, EMBER2 = glow(255, 130, 40), glow(255, 200, 90)
		local FIRE = Color3.fromRGB(255, 130, 40)
		local V = b.V
		local stomp = function(t: number): number
			local p = b:emPhase(t)
			return if p then K.bump(p, 0.15, 0.55) else 0
		end
		bouncy(b, 0.25)
		b:hopUp(1)
		b:move(function(t: number, move: number): CFrame
			local m = math.min(move, 1.2)
			return CFrame.new(0, stomp(t) * 0.8, 0) * CFrame.Angles(0, 0, math.sin(t * b.gait) * 0.08 * m)
		end)

		local body = Kit.group()
		Kit.box(body, -4, 5, -4, 4, 10, 4, BONE) -- the skull
		for _, sx in ipairs({ -3, 2 }) do
			Kit.box(body, sx, 7, -5, sx + 1, 8, -5, SOCKET)
			Kit.set(body, sx + (if sx < 0 then 1 else 0), 7, -5, EMBER.color, true)
		end
		Kit.set(body, 0, 6, -5, SOCKET.color)
		for x = -3, 3 do Kit.set(body, x, 5, -5, (if x % 2 == 0 then BONE else SOCKET).color) end
		for _, z in ipairs({ -2, 0, 2 }) do -- the ribs under it
			for _, sx in ipairs({ -3, 3 }) do Kit.box(body, sx, 2, z, sx, 4, z, BONE2) end
			Kit.box(body, -2, 2, z, 2, 2, z, BONE2)
		end
		Kit.box(body, 0, 2, -2, 0, 4, 2, BONE2) -- spine
		for _, s in ipairs({ -1, 1 }) do Kit.box(body, math.min(5 * s, 6 * s), 7, -2, math.max(5 * s, 6 * s), 9, 2, BONE2) end -- shoulders
		K.saddle(body, 3, 11, -1, 1, rgb(80, 50, 34), rgb(50, 30, 20), rgb(50, 30, 20))
		b:bodyPiece({ body })
		local core = Kit.group()
		Kit.set(core, 0, 3, 0, EMBER2.color, true)
		Kit.set(core, 0, 3, -1, EMBER.color, true)
		Kit.set(core, 0, 4, 0, EMBER.color, true)
		local corePiece = b:onBody({ core })
		b:glowUp(corePiece, function(t: number): number return 0.2 + math.sin(t * 3) * 0.2 + stomp(t) * 0.5 end)
		b:fx(corePiece, b:v(0, 3.5, 0), b:v(2, 2, 2), "embers", FIRE).Rate = 6
		-- the arms, swinging; the jaw
		for _, side in ipairs({ -1, 1 }) do
			local arm = Kit.group()
			Kit.box(arm, 0, -4, 0, 0, -1, 0, BONE2)
			Kit.box(arm, -1, -6, -1, 1, -5, 1, BONE)
			b:piece({ arm }, b:at(side * 5.5, 7, 0), function(t: number, move: number): CFrame
				return CFrame.Angles(math.sin(t * b.gait + (if side > 0 then math.pi else 0)) * 0.5 * math.min(move, 1.2) - stomp(t) * 1.2, 0, side * (0.1 + stomp(t) * 0.3))
			end)
		end
		local jaw = Kit.group()
		Kit.box(jaw, -3, 4, -5, 3, 4, -3, BONE2)
		b:piece({ jaw }, CFrame.new(), function(t: number, move: number): CFrame
			local open = (math.sin(t * 2) * 0.5 + 0.5) * 0.06 + stomp(t) * 0.35
			return b.bodyAnim(t, move) * CFrame.new(0, 4.5 * V, -3 * V) * CFrame.Angles(-open, 0, 0) * CFrame.new(0, -4.5 * V, 3 * V)
		end)
		-- two short legs, stepping in turn
		for _, side in ipairs({ -1, 1 }) do
			b:leg(K.legGroup(2, 2, BONE2, BONE), side * 2 + 0.5, 2, 0, false, side, { phase = if side > 0 then math.pi - K.SIDE_LAG else 0, amp = 0.8 })
		end
		-- the tiny meteor: drops from the sky beside it, bursts into embers
		local rock = Kit.group()
		Kit.box(rock, -1, -1, -1, 1, 1, 1, rgb(60, 44, 36))
		Kit.set(rock, 0, 0, -2, EMBER.color, true)
		Kit.set(rock, 1, 1, 1, EMBER2.color, true)
		local rockPiece = b:piece({ rock }, b:at(7, 1, -3), function(t: number): CFrame
			local p = b:emPhase(t) or 0
			local k = math.clamp((p - 0.5) / 0.5, 0, 1)
			return CFrame.new(0, (1 - k) * 26 * V, 0) * CFrame.Angles(t * 5, t * 3, 0)
		end)
		b:fade(rockPiece.parts, function(t: number): number
			local p = b:emPhase(t)
			return if p and p > 0.45 and p < 1.4 then 0 else 1
		end)
		b:trail(rockPiece, Vector3.zero, 0.6, FIRE, 0.4)
		local boom = b:fx(b.body, b:v(7, 1, -3), b:v(2, 1, 2), "fire", FIRE)
		boom.Rate = 0
		b:atEmote(1.0, function() boom:Emit(30) end)
		local dust = b:dust(8, 8, Color3.fromRGB(170, 160, 140))
		b:atEmote(0.55, function() dust:Emit(16) end)
		b:trophy(0, 11, 0, 3)
		return b.rig
	end

	-- Mini Iron Warlord: a stubby armoured war-beast in dark iron plates and
	-- spikes, a horned helm with glowing visor slits, banners behind the
	-- saddle. Emote: a tiny whirlwind spin, and it gets dizzy.
	function M.mini_iron_warlord()
		local b = K.new("mini_iron_warlord", { gait = 13, emoteLen = 2.8, mountLen = 1.0 })
		local IRON, IRON2, SPIKE, DARK = rgb(52, 50, 56), rgb(82, 80, 88), rgb(150, 150, 158), rgb(24, 22, 26)
		local VISOR, BANNER, GOLD, POLE = glow(255, 130, 40), rgb(170, 30, 30), K.GOLD, rgb(70, 50, 30)
		local V = b.V
		local whirl = function(t: number): number
			local p = b:emPhase(t)
			return if p then math.clamp((p - 0.15) / 0.8, 0, 1) else 0
		end
		local dizzy = function(t: number): number return hold(b:emPhase(t), 0.95, 2.7, 0.3) end
		bouncy(b, 0.32)
		b:hopUp(1.1)
		b:move(function(t: number): CFrame
			local w = whirl(t)
			local d = dizzy(t)
			if w == 0 and d == 0 then return CFrame.identity end
			return CFrame.Angles(math.sin(t * 5) * 0.08 * d, K.ease(w) * math.pi * 6, math.cos(t * 5) * 0.1 * d)
		end)

		local body = Kit.group()
		Kit.box(body, -2, 3, -3, 2, 6, 3, IRON)
		for _, sx in ipairs({ -3, 3 }) do
			Kit.box(body, sx, 4, -3, sx, 5, 3, IRON2)
			for _, z in ipairs({ -2, 0, 2 }) do Kit.set(body, sx + (if sx > 0 then 1 else -1), 5, z, SPIKE.color) end
		end
		K.saddle(body, 2, 7, -1, 1, rgb(90, 30, 26), DARK, DARK)
		-- banner poles behind the saddle
		for _, sx in ipairs({ -2, 2 }) do Kit.box(body, sx, 8, 3, sx, 17, 3, POLE) end
		b:bodyPiece({ body })
		for i, sx in ipairs({ -2, 2 }) do
			local flag = Kit.group()
			Kit.box(flag, 0, -3, 1, 0, 0, 4, BANNER)
			Kit.set(flag, 0, -2, 2, GOLD.color)
			Kit.set(flag, 0, -1, 3, GOLD.color)
			Kit.set(flag, 0, -2, 3, GOLD.color)
			b:piece({ flag }, b:at(sx, 17, 3), function(t: number, move: number): CFrame
				return b.bodyAnim(t, move) * CFrame.Angles(0, math.sin(t * (4 + move * 6) + i) * (0.2 + move * 0.25), 0)
			end)
		end

		local head = Kit.group()
		Kit.box(head, -3, 0, -6, 3, 5, 0, IRON)
		Kit.box(head, -2, 3, -7, -1, 3, -7, VISOR)
		Kit.box(head, 1, 3, -7, 2, 3, -7, VISOR)
		Kit.box(head, -3, 2, -7, 3, 2, -7, IRON2)
		for _, s in ipairs({ -1, 1 }) do
			for _, c in ipairs({ { 3, 5, -2 }, { 4, 6, -2 }, { 4, 7, -1 }, { 4, 8, 0 } }) do Kit.set(head, c[1] * s, c[2], c[3], SPIKE.color) end
		end
		for z = -5, -1 do Kit.set(head, 0, 6, z, (if z % 2 == 0 then SPIKE else IRON2).color) end
		chibiHead(b, { head }, 0, 6, -3, function(t: number): (number, number, number)
			local d = dizzy(t)
			return b:mu(t) * 0.3 + math.sin(t * 6) * 0.15 * d, 0, math.cos(t * 6) * 0.2 * d
		end)
		-- dizzy stars circling its helm
		local stars = b:orbitVar(b.headHome * b:at(0, 8, -3), 3, 3 * V, function(): number return 4 end, function()
			local s = Kit.group()
			for _, o in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do Kit.set(s, o[1], o[2], 0, Color3.fromRGB(255, 230, 80), true) end
			return s
		end, 0.2, 0.2)
		for _, s in ipairs(stars) do b:fade(s.parts, function(t: number): number return 1 - dizzy(t) end) end
		local wind = b:fx(b.body, b:v(0, 2, 0), b:v(8, 3, 8), "smoke", Color3.fromRGB(200, 195, 190))
		b:whileEmote(wind, 30, 0.15, 0.95)
		trot4(b, { x = 1.5, front = -2, hind = 2, hip = 3, len = 3, w = 2, main = IRON2, foot = DARK })
		local tail = Kit.group()
		Kit.box(tail, -1, 0, 0, 0, 1, 1, IRON)
		Kit.set(tail, 0, 2, 2, SPIKE.color)
		b:tail({ tail }, 0.5, 4, 3)
		b:fx(b.headPiece, b:v(0, 3, -7), b:v(4, 0.5, 0.3), "embers", Color3.fromRGB(255, 130, 40)).Rate = 3
		b:trophy(0, 7, 0, 2)
		b:dust(6, 5, Color3.fromRGB(110, 100, 90))
		return b.rig
	end

	-- Mini Hex Witch: a walking cauldron on chicken legs, bubbling toxic-green
	-- brew, a giant floating crooked witch hat, hex runes circling. You sit on
	-- a plank across its rim. Emote: the brew bubbles over into a puff of
	-- green hearts.
	function M.mini_hex_witch()
		local b = K.new("mini_hex_witch", { gait = 14, emoteLen = 2.8, mountLen = 1.0 })
		local CAULD, CAULD2, RIM = rgb(40, 40, 46), rgb(62, 62, 70), rgb(92, 92, 102)
		local BREW, BREW2, LEG = glow(120, 255, 90), glow(190, 255, 140), rgb(232, 170, 62)
		local HAT, HAT2, BAND, PLANK = rgb(42, 22, 62), rgb(58, 32, 84), rgb(140, 60, 200), rgb(110, 76, 44)
		local GREEN = Color3.fromRGB(130, 255, 90)
		local V = b.V
		local boil = function(t: number): number return hold(b:emPhase(t), 0.15, 2.6, 0.3) end
		bouncy(b, 0.4)
		b:hopUp(1.2)
		b:move(function(t: number): CFrame return CFrame.new(0, math.sin(t * 30) * 0.03 * boil(t), 0) end)

		local body = Kit.group()
		Kit.lathe(body, { { 4, 2.5 }, { 5, 3.5 }, { 6, 4.2 }, { 7, 4.4 }, { 8, 4.2, 3.2 }, { 9, 4.6, 3.6 } }, function(_, y, _, d)
			if y == 9 then return RIM end
			return if d > 3.9 and y % 2 == 0 then CAULD2 else CAULD
		end)
		Kit.box(body, -4, 10, -1, 4, 10, 1, PLANK) -- the plank you sit on
		b:bodyPiece({ body })
		-- the brew, bubbling
		local brew = Kit.group()
		Kit.lathe(brew, { { 0, 3.2 } }, function(x, _, z) return if (x + z) % 3 == 0 then BREW2 else BREW end)
		local brewPiece = b:onBody({ brew }, function(t: number): CFrame return CFrame.new(0, (8 + math.sin(t * 6) * 0.15 + boil(t) * 0.8) * V, 0) end)
		b:glowUp(brewPiece, function(t: number): number return boil(t) * 0.4 end)
		for i = 1, 4 do
			local a = i / 4 * math.pi * 2
			b:onBody({ (function()
				local g = Kit.group()
				Kit.set(g, 0, 0, 0, BREW2.color, true)
				return g
			end)() }, function(t: number): CFrame
				local k = (t * (0.7 + boil(t) * 2) + i * 0.27) % 1
				return CFrame.new(math.cos(a) * 2 * V, (8.5 + k * 2) * V, math.sin(a) * 2 * V)
			end)
		end
		local bubbles = b:fx(brewPiece, Vector3.zero, b:v(6, 0.5, 6), "stars", GREEN)
		bubbles.Rate = 6
		local over = b:fx(b.body, b:v(0, 8, 0), b:v(9, 1, 9), "drip", GREEN)
		b:whileEmote(over, 30, 0.6, 2.4)
		-- green hearts puffing up out of the brew
		for i = 1, 5 do
			local h = Kit.group()
			for _, c in ipairs({ { -1, 1 }, { 1, 1 }, { -1, 0 }, { 0, 0 }, { 1, 0 }, { 0, -1 } }) do Kit.set(h, c[1], c[2], 0, (if i % 2 == 0 then BREW2 else BREW).color, true) end
			local ox, oz = math.cos(i * 1.3) * 2.5, math.sin(i * 1.3) * 2.5
			local hp = b:piece({ h }, b:at(ox, 10, oz), function(t: number): CFrame
				local p = (b:emPhase(t) or 0) - 0.6 - i * 0.18
				local k = math.clamp(p / 1.2, 0, 1)
				return CFrame.new(math.sin(t * 3 + i) * 0.2, k * 9 * V, 0) * CFrame.Angles(0, math.sin(t * 2 + i) * 0.6, 0)
			end)
			b:fade(hp.parts, function(t: number): number
				local p = (b:emPhase(t) or 0) - 0.6 - i * 0.18
				return if p > 0 and p < 1.2 then p / 1.2 else 1
			end)
		end
		-- the giant crooked hat, floating over it
		local hat = Kit.group()
		Kit.lathe(hat, { { 0, 5.5, 0 } }, function(x, _, z) return if (x + z) % 4 == 0 then HAT2 else HAT end)
		Kit.lathe(hat, { { 1, 3 }, { 2, 2.6 } }, function() return HAT end)
		Kit.lathe(hat, { { 1, 3.2, 2.6 } }, function() return BAND end)
		local tip = { { 0, 3, 0 }, { 0, 4, 0 }, { 1, 5, 0 }, { 1, 6, 1 }, { 2, 7, 1 }, { 3, 8, 1 }, { 4, 8, 2 } }
		for i, c in ipairs(tip) do
			local r = if i <= 2 then 1 else 0
			Kit.box(hat, c[1] - r, c[2], c[3] - r, c[1] + r, c[2], c[3] + r, HAT)
		end
		Kit.set(hat, 0, 1, -3, BREW.color, true) -- the buckle
		b:piece({ hat }, b:at(0, 19, 3), function(t: number): CFrame
			return CFrame.new(0, math.sin(t * 1.8) * 0.25 + boil(t) * 0.4, 0) * CFrame.Angles(math.sin(t * 1.3) * 0.08, t * 0.3, math.sin(t * 1.1) * 0.08)
		end)
		-- hex runes circling
		b:orbitVar(b:at(0, 9, 0), 5, 8 * V, function(t: number): number return 0.9 + boil(t) * 3 end, function(i: number)
			local g = Kit.group()
			local shapes = { { { 0, 0 }, { 1, 1 }, { -1, 1 } }, { { 0, 0 }, { 0, 1 }, { 1, 1 } }, { { -1, 0 }, { 1, 0 }, { 0, 1 } } }
			for _, c in ipairs(shapes[(i - 1) % 3 + 1]) do Kit.set(g, c[1], c[2], 0, GREEN, true) end
			return g
		end, 0.2, 0.5)
		-- chicken legs, strutting
		for _, side in ipairs({ -1, 1 }) do
			local g = Kit.group()
			Kit.box(g, 0, -4, 0, 0, -1, 0, LEG)
			Kit.set(g, 0, -2, 1, LEG.color)
			for _, c in ipairs({ { -1, -4, -1 }, { 0, -4, -2 }, { 1, -4, -1 }, { 0, -4, 1 } }) do Kit.set(g, c[1], c[2], c[3], LEG.color) end
			b:leg(g, side * 2, 4, 0, false, side, { phase = if side > 0 then math.pi - K.SIDE_LAG else 0, amp = 0.8 })
		end
		b:trophy(0, 10, 0, 4)
		b:runTrail(Vector3.new(0, 0.4, 0), b:v(4, 1, 4), "drip", GREEN, 10)
		b:dust(6, 6, Color3.fromRGB(120, 110, 90))
		return b.rig
	end

	return M
end
