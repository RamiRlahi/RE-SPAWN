--[[
	Mounts/BeastKit.luau
	Shared building blocks for the reworked mounts (Mounts/<Tier>.luau): a
	builder for one mount's rig with the common parts and moves, so each
	mount's own code is mostly its voxel art.

	  local b = K.new(look, opts?)   b.rig, b.V (studs per brick), b.tier
	  b:piece(groups, home, anim)    a moving piece (b:at(x, y, z): a home in bricks)
	  b:bodyPiece(groups)            the body (breathes at rest)
	  b:head(groups, x, y, z, extra) the head, steady against the gallop
	  b:onHead(groups, hinge, own)   jaw / ear / horn riding the head
	  b:legs4{...} / b:crawlLegs{...} / b:wing(...)
	  b:gallop / b:rearUp / b:spinUp / b:hopUp / b:move(fn)  whole-rig moves

	Every mount follows the same rules: legged runners bound (the hind legs
	launch, the front pair lands a beat later to catch the body, which rocks
	nose-up then nose-down), cycles are brisk; the mount-up flourish plays
	for b.mountLen seconds after it is called (rig.born) and its special
	emote loops while the rider emotes (rig.emoteAt).
--]]

return function(W: any)
	local Kit = W.Kit
	local rgb, glow, glass = W.rgb, W.glow, W.glass
	local RideData = W.RideData
	local GachaRewards = W.GachaRewards

	local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
	local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
	local FIRE = "rbxasset://textures/particles/fire_main.dds"

	local K: any = { Kit = Kit, rgb = rgb, glow = glow, glass = glass, W = W, SPARK = SPARK, SMOKE = SMOKE, FIRE = FIRE }
	K.FRONT_LAG, K.SIDE_LAG = 1.4, 0.3
	K.GOLD, K.GOLD2 = rgb(222, 172, 58), glow(255, 205, 80)

	-- A 0 → 1 → 0 bump while x is between a and b; smoothstep.
	local function bump(x: number, a: number, b: number): number
		if x <= a or x >= b then return 0 end
		return math.sin((x - a) / (b - a) * math.pi)
	end
	local function ease(x: number): number
		x = math.clamp(x, 0, 1)
		return x * x * (3 - 2 * x)
	end
	K.bump, K.ease = bump, ease

	-- A solid ellipsoid centred at (cx, cy, cz); paint(x, y, z) by the offset
	-- from the centre (nil: leave it empty).
	function K.ellipsoid(g: any, cx: number, cy: number, cz: number, rx: number, ry: number, rz: number, paint: (number, number, number) -> any)
		for x = -math.ceil(rx), math.ceil(rx) do
			for y = -math.ceil(ry), math.ceil(ry) do
				for z = -math.ceil(rz), math.ceil(rz) do
					if (x / rx) ^ 2 + (y / ry) ^ 2 + (z / rz) ^ 2 <= 1.05 then
						local p = paint(x, y, z)
						if p then Kit.set(g, cx + x, cy + y, cz + z, p.color, p.neon, p.alpha) end
					end
				end
			end
		end
	end
	-- Take bricks out of a group (where a separate piece goes instead).
	function K.carve(g: any, list: { { number } })
		for _, c in ipairs(list) do g.vox[`{c[1]},{c[2]},{c[3]}`] = nil end
	end

	function K.mirror(g: any): any
		local m = Kit.group()
		for _, v in pairs(g.vox) do Kit.set(m, -v.x, v.y, v.z, v.color, v.neon, v.alpha) end
		return m
	end

	-- A straight leg `len` bricks long and `w` thick, hanging from y = -1 down,
	-- its foot (`footH` bricks of `foot`) at the bottom.
	function K.legGroup(len: number, w: number, main: any, foot: any?, footH: number?): any
		local g = Kit.group()
		local a = -math.floor(w / 2)
		local b = a + w - 1
		Kit.box(g, a, -len, a, b, -1, b, main)
		if foot then Kit.box(g, a, -len, a, b, -len + (footH or 1) - 1, b, foot) end
		return g
	end

	-- A saddle on top of a body: seat across x = -hw..hw at height y from z0 to
	-- z1 (rear), a cantle behind, a pommel in front, straps and stirrups.
	function K.saddle(g: any, hw: number, y: number, z0: number, z1: number, seat: any, trim: any, strap: any?, iron: any?)
		Kit.box(g, -hw, y, z0, hw, y, z1, seat)
		Kit.box(g, -hw + 1, y + 1, z1, hw - 1, y + 1, z1 + 1, trim)
		Kit.set(g, 0, y + 1, z0, trim.color, trim.neon)
		local zs = math.floor((z0 + z1) / 2)
		for _, sx in ipairs({ -hw - 1, hw + 1 }) do
			Kit.box(g, sx, y - 3, zs, sx, y, zs, strap or trim)
			if iron then Kit.set(g, sx, y - 4, zs, iron.color, iron.neon) end
		end
	end

	-- A heavy ornate saddle (Legendary): gold-trimmed edges, a gem on the pommel.
	function K.ornateSaddle(g: any, hw: number, y: number, z0: number, z1: number, seat: any, gem: any)
		local GOLD = K.GOLD
		Kit.box(g, -hw, y, z0, hw, y, z1, seat)
		for x = -hw, hw do
			Kit.set(g, x, y, z0 - 1, GOLD.color)
			Kit.set(g, x, y, z1 + 1, GOLD.color)
		end
		Kit.box(g, -hw, y + 1, z1 + 1, hw, y + 2, z1 + 1, seat)
		Kit.box(g, -hw, y + 3, z1 + 1, hw, y + 3, z1 + 1, GOLD)
		Kit.box(g, 0, y + 1, z0 - 1, 0, y + 2, z0 - 1, GOLD)
		Kit.set(g, 0, y + 3, z0 - 1, gem.color, true)
		local zs = math.floor((z0 + z1) / 2)
		for _, sx in ipairs({ -hw - 1, hw + 1 }) do
			Kit.box(g, sx, y - 3, z0, sx, y, z1, seat)
			for z = z0, z1 do Kit.set(g, sx, y - 3, z, GOLD.color) end
			Kit.set(g, sx, y - 1, zs, gem.color, true)
		end
	end

	-- A throne (Mythic): a gold-trimmed seat with a tall back and arm rests.
	function K.throne(g: any, hw: number, y: number, z0: number, z1: number, base: any, accent: any)
		local GOLD = K.GOLD
		Kit.box(g, -hw, y, z0, hw, y, z1, base)
		for x = -hw, hw do Kit.set(g, x, y, z0 - 1, GOLD.color) end
		Kit.box(g, -hw, y + 1, z1 + 1, hw, y + 5, z1 + 1, base)
		Kit.box(g, -hw, y + 6, z1 + 1, hw, y + 6, z1 + 1, GOLD)
		Kit.box(g, -hw - 1, y + 1, z1 + 1, -hw - 1, y + 6, z1 + 1, GOLD)
		Kit.box(g, hw + 1, y + 1, z1 + 1, hw + 1, y + 6, z1 + 1, GOLD)
		Kit.set(g, 0, y + 7, z1 + 1, accent.color, true)
		Kit.box(g, -hw - 1, y + 1, z0, -hw - 1, y + 2, z1, GOLD)
		Kit.box(g, hw + 1, y + 1, z0, hw + 1, y + 2, z1, GOLD)
	end

	local function rewardOf(look: string): any
		for _, r in ipairs(GachaRewards.All) do
			if r.type == "mount" and r.look == look then return r end
		end
		return nil
	end
	local TIER = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }

	local B: any = {}
	B.__index = B

	function K.new(look: string, opts: any?): any
		local o = opts or {}
		local r = rewardOf(look)
		local rig = W.newRig("Mount_" .. look, "mount")
		local self = setmetatable({
			rig = rig, look = look, V = W.VOX_MOUNT * RideData.ScaleOf(look),
			tier = r and TIER[r.rarity] or 2, secret = r ~= nil and r.secret == true,
			gait = o.gait or 10, mountLen = o.mountLen or 1.1, emoteLen = o.emoteLen or 2.6,
			moves = {}, pitchAmp = 0, bounding = false, rearing = false,
		}, B)
		rig.whole = function(t: number, move: number): CFrame
			local cf = CFrame.identity
			for _, m in ipairs(self.moves) do cf *= m(t, move) end
			return cf
		end
		return self
	end

	-- ── Basics ────────────────────────────────────────────────────────────────
	function B:at(x: number, y: number, z: number): CFrame
		local V = self.V
		return CFrame.new(x * V, y * V, z * V)
	end
	function B:v(x: number, y: number, z: number): Vector3
		local V = self.V
		return Vector3.new(x * V, y * V, z * V)
	end
	function B:piece(groups: { any }, home: CFrame, anim: any?): any
		if self.smooth then return self:smoothPiece(groups, home, anim) end
		return W.addPiece(self.rig, groups, self.V, home, anim)
	end
	-- A piece built without studs (the Mythic tier's clean voxel look, and
	-- far fewer parts): runs of matching bricks merge along x, then equal
	-- runs in neighbouring rows merge along z; bricks buried on all six sides
	-- are skipped. (b.smooth = true makes every piece of a mount this way.)
	function B:smoothPiece(groups: { any }, home: CFrame, anim: any?): any
		local V = self.V
		local piece = { parts = {}, offsets = {}, home = home, anim = anim }
		local all, rows = {}, {}
		for _, g in ipairs(groups) do
			for k, v in pairs(g.vox) do all[k] = v end
		end
		local function solid(x: number, y: number, z: number): boolean
			local o = all[`{x},{y},{z}`]
			return o ~= nil and o.alpha == 0
		end
		for _, v in pairs(all) do
			if solid(v.x + 1, v.y, v.z) and solid(v.x - 1, v.y, v.z) and solid(v.x, v.y + 1, v.z)
				and solid(v.x, v.y - 1, v.z) and solid(v.x, v.y, v.z + 1) and solid(v.x, v.y, v.z - 1) then continue end
			local k = `{v.y},{v.z}`
			rows[k] = rows[k] or {}
			table.insert(rows[k], v)
		end
		local runs = {}
		for _, row in pairs(rows) do
			table.sort(row, function(a, b) return a.x < b.x end)
			local i = 1
			while i <= #row do
				local first = row[i]
				local j = i
				while j < #row and row[j + 1].x == row[j].x + 1 and row[j + 1].color == first.color
					and row[j + 1].neon == first.neon and row[j + 1].alpha == first.alpha do j += 1 end
				local key = `{first.y}|{first.x}|{row[j].x}|{first.color}|{first.neon}|{first.alpha}`
				runs[key] = runs[key] or {}
				table.insert(runs[key], { z = first.z, v = first, x1 = row[j].x })
				i = j + 1
			end
		end
		for _, list in pairs(runs) do
			table.sort(list, function(a, b) return a.z < b.z end)
			local i = 1
			while i <= #list do
				local j = i
				while j < #list and list[j + 1].z == list[j].z + 1 do j += 1 end
				local v = list[i].v
				local x0, x1, z0, z1 = v.x, list[i].x1, list[i].z, list[j].z
				local p = Instance.new("Part")
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
				p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				p.Size = Vector3.new(x1 - x0 + 1, 1, z1 - z0 + 1) * V
				p.Color = v.color
				p.Material = if v.neon then Enum.Material.Neon else Enum.Material.SmoothPlastic
				p.Transparency = v.alpha
				p.Parent = self.rig.model
				table.insert(piece.parts, p)
				table.insert(piece.offsets, CFrame.new((x0 + x1) / 2 * V, v.y * V, (z0 + z1) / 2 * V))
				table.insert(self.rig.allParts, p)
				i = j + 1
			end
		end
		table.insert(self.rig.pieces, piece)
		return piece
	end
	-- An imported voxel model (Mounts/Models: tools/mounts/export.py from a
	-- GLB): each of its pieces built as merged boxes at its pivot, scaled so
	-- the body's top is the rider's seat. b.V becomes studs per model voxel
	-- (b.artV keeps the brick size, for the kit's own brick-built extras:
	-- b:legacy), so b:at / b:v and the whole-rig moves work in model units.
	-- anims[name](t, move) → that piece's own turn about its pivot; a piece
	-- follows its parent's motion (a shin its thigh, the head its neck). The
	-- body's home stays at the ground (its bricks offset up), so the kit's
	-- effects on b.body sit where they always have.
	-- opts.longer: model voxels added at each end of the body (its middle
	-- stretched, the front half (neck, front legs) moved forward, the back
	-- half (tail, hind legs) back), so the rider sits clear of mane and tail;
	-- opts.clearSeat: mane and tail bricks still within this many voxels of
	-- the seat (front to back) are left out. The seat is RideData.SeatBack
	-- behind the middle; wings are rooted behind it.
	-- → { [name]: piece }, { [name]: home (Vector3, rig space) }
	local NEON_PIECES = { gem = true, lanL = true, lanR = true }
	local SEAT_CLIP = { mane = true, tail = true }
	local BACK_HALF = { wingL = true, wingR = true }
	function B:model(data: any, anims: { [string]: (number, number) -> CFrame }, opts: any?): ({ [string]: any }, { [string]: Vector3 })
		local o = opts or {}
		local ext = o.longer or 0
		self.artV = self.artV or self.V
		local s = RideData.BackHeight(self.look) / data.back
		self.V = s
		local seat = RideData.SeatBackOf(self.look) / s -- (voxels behind the middle)
		local pieces, homes, pivots, animOf = {}, {}, {}, {}
		for _, pd in ipairs(data.pieces) do
			local pz = pd.pivot[3]
			-- (wings go with the back half: rooted behind the rider, not at the seat)
			if pd.parent == "body" then
				pz += if BACK_HALF[pd.name] then ext + seat elseif pz > 0 then ext elseif pz < 0 then -ext else 0
			end
			local pivot = (if pd.parent then pivots[pd.parent] else Vector3.zero) + Vector3.new(pd.pivot[1], pd.pivot[2], pz) * s
			pivots[pd.name] = pivot
			local home = if pd.parent then pivot else Vector3.zero
			homes[pd.name] = home
			local own = anims[pd.name]
			local parentAnim = if pd.parent then animOf[pd.parent] else nil
			local anim: ((number, number) -> CFrame)? = own
			if parentAnim then
				local rel = home - homes[pd.parent]
				anim = function(t: number, move: number): CFrame
					local cf = CFrame.new(-rel) * parentAnim(t, move) * CFrame.new(rel)
					return if own then cf * own(t, move) else cf
				end
			end
			animOf[pd.name] = anim or function(): CFrame return CFrame.identity end
			local piece = { parts = {}, offsets = {}, home = CFrame.new(home), anim = anim }
			local shift = pivot - home
			for _, bx in ipairs(pd.boxes) do
				local z0, z1 = bx[3], bx[6]
				if pd.name == "body" and ext > 0 then
					if z0 < 0 and z1 > 0 then z0, z1 = z0 - ext, z1 + ext
					elseif z0 >= 0 then z0, z1 = z0 + ext, z1 + ext
					else z0, z1 = z0 - ext, z1 - ext end
				end
				if o.clearSeat and SEAT_CLIP[pd.name] then
					local at = pivot.Z / s
					if at + z1 > seat - o.clearSeat and at + z0 < seat + o.clearSeat then continue end
				end
				local c = data.palette[bx[7]]
				local p = Instance.new("Part")
				p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
				p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
				p.Size = Vector3.new(bx[4] - bx[1], bx[5] - bx[2], z1 - z0) * s
				p.Color = Color3.fromRGB(c[1], c[2], c[3])
				-- (the model's glow: Neon only on its accents (the gem, lanterns,
				-- single bricks on the head: the eyes), never manes, tails or
				-- wings, or the bloom drowns the whole mount)
				local brick = math.max(bx[4] - bx[1], bx[5] - bx[2], bx[6] - bx[3]) <= 3
				p.Material = if c[4] and (NEON_PIECES[pd.name] or (pd.name == "head" and brick)) then Enum.Material.Neon else Enum.Material.SmoothPlastic
				p.Parent = self.rig.model
				table.insert(piece.parts, p)
				table.insert(piece.offsets, CFrame.new(shift + Vector3.new(bx[1] + bx[4], bx[2] + bx[5], z0 + z1) * (s / 2)))
				table.insert(self.rig.allParts, p)
			end
			table.insert(self.rig.pieces, piece)
			pieces[pd.name] = piece
		end
		self.body, self.bodyAnim = pieces.body, animOf.body
		if pieces.head then
			self.headPiece, self.headHome, self.headAnim = pieces.head, CFrame.new(homes.head), animOf.head
		end
		return pieces, homes
	end
	-- The moves of an imported four-legged model (its pieces named as the
	-- exporter's GLBs name them): thighs "lFL" "lFR" "lBL" "lBR" bounding like
	-- b:leg, their shins ("…2") folding at the knee as each leg swings
	-- forward; the neck steady against the gallop and looking round at rest,
	-- the head nodding (o.head(t, move) → more pitch), the mane rippling, the
	-- tail swishing (o.tail(t, move) → more pitch). Merge your own into it.
	function B:horseAnims(o: any?): { [string]: (number, number) -> CFrame }
		local opts = o or {}
		local a: { [string]: (number, number) -> CFrame } = {}
		for _, front in ipairs({ true, false }) do
			for _, side in ipairs({ -1, 1 }) do
				-- (the GLBs' left legs are on rig +x)
				local name = "l" .. (if front then "F" else "B") .. (if side > 0 then "L" else "R")
				local phase = (if front then K.FRONT_LAG else 0) + (if side > 0 then K.SIDE_LAG else 0)
				local amp = if front then 0.5 else 0.6
				a[name] = function(t: number, move: number): CFrame
					local swing = math.sin(t * self.gait - phase) * amp * math.min(move, 1.2)
					if front and self.rearing then swing += self:mu(t) * (0.7 + math.sin(t * 16 + phase) * 0.4) end
					return CFrame.Angles(swing, 0, 0)
				end
				a[name .. "2"] = function(t: number, move: number): CFrame
					-- (folds while the leg swings forward: the hoof tucked back and up)
					local k = math.max(0, math.cos(t * self.gait - phase)) * (if front then 0.95 else 0.7) * math.min(move, 1.2)
					if front and self.rearing then k += self:mu(t) * (1 + math.sin(t * 16 + phase) * 0.3) end
					return CFrame.Angles(-k, 0, 0)
				end
			end
		end
		a.neck = function(t: number, move: number): CFrame
			local rest = math.max(0, 1 - move)
			return CFrame.Angles(-self:pitch(t, move) * 0.6 + math.sin(t * 1.1) * 0.04 * rest, math.sin(t * 0.7) * 0.12 * rest, 0)
		end
		a.head = function(t: number, move: number): CFrame
			local extra = if opts.head then opts.head(t, move) else 0
			return CFrame.Angles(math.sin(t * 1.3 + 0.6) * 0.05 + math.sin(t * self.gait) * 0.06 * math.min(move, 1) + extra, 0, 0)
		end
		a.mane = function(t: number, move: number): CFrame
			return CFrame.Angles(math.sin(t * 2.4) * 0.03 + math.min(move, 1) * 0.12, 0, math.sin(t * 1.9) * 0.03)
		end
		local swish = W.runner(2, 3)
		a.tail = function(t: number, move: number): CFrame
			local extra = if opts.tail then opts.tail(t, move) else 0
			-- (raised as it runs: a turn about x lowers what trails behind)
			return CFrame.Angles(math.sin(t * 2.2) * 0.08 - math.min(move, 1) * 0.25 + extra, math.sin(swish(t, move)) * 0.3, 0)
		end
		return a
	end
	-- Run `fn` with b.V back at the kit's brick size (the brick-built extras:
	-- rune circles, orbiting motes) on an imported model.
	function B:legacy(fn: () -> ())
		local v = self.V
		self.V = self.artV or v
		fn()
		self.V = v
	end
	function B:anchor(home: CFrame, anim: any?): any
		return W.addAnchorPiece(self.rig, home, anim)
	end
	function B:fx(piece: any, at: Vector3, size: Vector3, kind: string, color: Color3): ParticleEmitter
		return W.fx(W.addEmitterAnchor(self.rig, piece, at, size), kind, color)
	end
	function B:trail(piece: any, at: Vector3, width: number, color: Color3, life: number?): Trail
		return W.addTrail(self.rig, piece, at, width, color, life)
	end
	-- Run `fn(t, move)` every frame.
	function B:every(fn: (number, number) -> ())
		self:anchor(CFrame.new(), function(t: number, move: number): CFrame
			fn(t, move)
			return CFrame.identity
		end)
	end
	-- A whole-rig move (rig space), multiplied in after the others.
	function B:move(fn: (number, number) -> CFrame)
		table.insert(self.moves, fn)
	end
	-- A piece hinged on another: follows `parent`'s motion, then turns by its
	-- own about `hinge` (bricks, parent space).
	function B:follow(parent: any, hinge: Vector3, own: any): any
		local h = hinge * self.V
		return function(t: number, move: number): CFrame
			return parent(t, move) * CFrame.new(h) * own(t, move) * CFrame.new(-h)
		end
	end

	-- ── Mount-up and emote clocks ────────────────────────────────────────────
	-- 0..1..0 over the mount-up flourish.
	function B:mu(t: number): number
		return if self.rig.born then bump(t - self.rig.born, 0, self.mountLen) else 0
	end
	-- Seconds since it was called (huge before / in previews).
	function B:since(t: number): number
		return if self.rig.born then t - self.rig.born else math.huge
	end
	-- Held near 1 through each emote loop while the rider emotes.
	function B:em(t: number): number
		if not self.rig.emoteAt then return 0 end
		return math.sqrt(bump((t - self.rig.emoteAt) % self.emoteLen, 0.1, self.emoteLen - 0.2))
	end
	-- Seconds into the current emote loop, or nil.
	function B:emPhase(t: number): number?
		if not self.rig.emoteAt then return nil end
		return (t - self.rig.emoteAt) % self.emoteLen
	end
	-- `fn()` once, `when` seconds into each mount-up.
	function B:atMount(when: number, fn: () -> ())
		local last = nil
		self:every(function(t: number)
			local born = self.rig.born
			if born and last ~= born and t - born >= when then
				last = born
				if t - born < when + 0.5 then fn() end
			end
		end)
	end
	-- `fn()` once per emote loop, `when` seconds into it.
	function B:atEmote(when: number, fn: () -> ())
		local lastLoop = nil
		self:every(function(t: number)
			local at = self.rig.emoteAt
			if not at then
				lastLoop = nil
				return
			end
			local loop = math.floor((t - at) / self.emoteLen)
			if (t - at) % self.emoteLen >= when and lastLoop ~= loop then
				lastLoop = loop
				fn()
			end
		end)
	end
	-- An emitter pouring at `rate` from `from` to `to` seconds into each emote loop.
	function B:whileEmote(e: ParticleEmitter, rate: number, from: number?, to: number?)
		e.Rate = 0
		self:every(function(t: number)
			local p = self:emPhase(t)
			e.Rate = if p and p >= (from or 0.2) and p <= (to or self.emoteLen - 0.3) then rate else 0
		end)
	end
	-- An emitter pouring while it runs, harder the faster it goes.
	function B:whileRunning(e: ParticleEmitter, rate: number)
		e.Rate = 0
		self:every(function(_, move: number)
			e.Rate = if move > 0.35 then rate * move else 0
		end)
	end

	-- ── Colour tricks (written only when they change) ──────────────────────
	-- Brighten a piece's bricks toward `to` (white) by k(t) 0..1.
	function B:glowUp(piece: any, k: (number) -> number, to: Color3?)
		local base = {}
		for i, p in ipairs(piece.parts) do base[i] = p.Color end
		local target = to or Color3.new(1, 1, 1)
		local last = -1
		self:every(function(t: number)
			local v = math.floor(math.clamp(k(t), 0, 1) * 20 + 0.5) / 20
			if v == last then return end
			last = v
			for i, p in ipairs(piece.parts) do
				if base[i] then p.Color = base[i]:Lerp(target, v) end
			end
		end)
	end
	-- Fade a piece (or every part of the rig) out by k(t) 0..1.
	function B:fade(parts: { BasePart }?, k: (number) -> number)
		local last = -1
		self:every(function(t: number)
			local v = math.floor(math.clamp(k(t), 0, 1) * 20 + 0.5) / 20
			if v == last then return end
			last = v
			for _, p in ipairs(parts or self.rig.allParts) do p.LocalTransparencyModifier = v end
		end)
	end
	-- Light (neon, its colour) or dark (`off` colour) one piece, by on(t).
	function B:lamp(piece: any, on: (number) -> boolean, off: Color3)
		local base = {}
		for i, p in ipairs(piece.parts) do base[i] = p.Color end
		local last = nil
		self:every(function(t: number)
			local v = on(t)
			if v == last then return end
			last = v
			for i, p in ipairs(piece.parts) do
				p.Color = if v then base[i] else off
				p.Material = if v then Enum.Material.Neon else Enum.Material.SmoothPlastic
			end
		end)
	end

	-- A particle emitter from a table of settings.
	function B:emitter(piece: any, at: Vector3, size: Vector3, props: { [string]: any }): ParticleEmitter
		local anchor = W.addEmitterAnchor(self.rig, piece, at, size)
		local e = Instance.new("ParticleEmitter")
		e.LightInfluence = 0
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		for k, v in pairs(props) do (e :: any)[k] = v end
		e.Parent = anchor
		return e
	end
	function K.seq(...: number): NumberSequence
		local v = { ... }
		local pts = {}
		for i, x in ipairs(v) do table.insert(pts, NumberSequenceKeypoint.new((i - 1) / math.max(1, #v - 1), x)) end
		return NumberSequence.new(pts)
	end

	-- ── Body, head, tail ─────────────────────────────────────────────────────
	function B:bodyPiece(groups: { any }, anim: any?): any
		self.bodyAnim = anim or function(t: number, move: number): CFrame
			return CFrame.new(0, math.sin(t * 1.6) * 0.025 * math.max(0, 1 - move), 0)
		end
		self.body = self:piece(groups, CFrame.new(), self.bodyAnim)
		return self.body
	end
	-- A separate piece moving with the body (for colour tricks, or its own wobble).
	function B:onBody(groups: { any }, own: any?): any
		return self:piece(groups, CFrame.new(), function(t: number, move: number): CFrame
			local cf = self.bodyAnim(t, move)
			return if own then cf * own(t, move) else cf
		end)
	end

	-- The head hinged at (x, y, z): holds steady against the gallop's rock,
	-- looks round at rest; `extra(t, move)` → its own pitch, yaw.
	function B:head(groups: { any }, x: number, y: number, z: number, extra: any?): any
		local anim = function(t: number, move: number): CFrame
			local p, yw = 0, 0
			if extra then p, yw = extra(t, move) end
			local rest = math.max(0, 1 - move)
			return CFrame.Angles(-self:pitch(t, move) * 0.6 + math.sin(t * 1.1) * 0.04 * rest + (p or 0),
				math.sin(t * 0.7) * 0.12 * rest + (yw or 0), 0)
		end
		self.headHome, self.headAnim = self:at(x, y, z), anim
		self.headPiece = self:piece(groups, self.headHome, anim)
		return anim
	end
	-- A part riding the head, turning about `hinge` (bricks, head space).
	function B:onHead(groups: { any }, hinge: Vector3, own: any): any
		return self:piece(groups, self.headHome, self:follow(self.headAnim, hinge, own))
	end
	-- An eyelid for the eye at (x, y, z) (head space) on `side`: tucked inside
	-- the head, slid out over the eye to blink.
	function B:eyelid(x: number, y: number, z: number, side: number, color: any, shut: ((number) -> boolean)?)
		local g = Kit.group()
		Kit.set(g, 0, 0, 0, color.color)
		local ph = math.abs(x) * 0.07 + y * 0.03
		local V = self.V
		self:piece({ g }, self.headHome, function(t: number, move: number): CFrame
			local closed = (t + ph) % 4.2 < 0.13 or (shut ~= nil and shut(t))
			return self.headAnim(t, move) * CFrame.new((x - side + (if closed then side * 1.06 else 0)) * V, y * V, z * V)
		end)
	end
	-- An ear flick now and then (radians, 0..1 shape).
	function B:flick(t: number, phase: number): number
		return bump((t + phase) % 3.7, 0, 0.25)
	end
	function B:tail(groups: { any }, x: number, y: number, z: number, extra: any?): any
		local swish = W.runner(2, 3)
		return self:piece(groups, self:at(x, y, z), function(t: number, move: number): CFrame
			local p, yw = 0, 0
			if extra then p, yw = extra(t, move) end
			return CFrame.Angles(math.sin(t * 2.2) * 0.08 + (p or 0), math.sin(swish(t, move)) * 0.35 + (yw or 0), 0)
		end)
	end

	-- ── Locomotion ───────────────────────────────────────────────────────────
	-- The bounding gallop's rock: nose-up after the hind legs push, nose-down
	-- as the front pair lands.
	function B:pitch(t: number, move: number): number
		if not self.bounding then return 0 end
		return math.cos(t * self.gait - math.pi - 0.5) * self.pitchAmp * math.min(move, 1.2)
	end
	-- Rock and lift the whole rig with the gallop about height `midY` (bricks).
	function B:gallop(midY: number, pitchAmp: number?, lift: number?)
		self.bounding, self.pitchAmp = true, pitchAmp or 0.08
		local mid = Vector3.new(0, midY * self.V, 0)
		local up = (lift or 0.14) * self.V / W.VOX_MOUNT
		self:move(function(t: number, move: number): CFrame
			local m = math.min(move, 1.2)
			if m < 0.01 then return CFrame.identity end
			local y = math.max(0, math.cos(t * self.gait - math.pi - 0.3)) * up * m
			return CFrame.new(0, y, 0) * CFrame.new(mid) * CFrame.Angles(self:pitch(t, move), 0, 0) * CFrame.new(-mid)
		end)
	end
	-- How far into flight a flier is (0 standing .. 1 flying): legs tuck, wings beat.
	function B:flying(move: number): number
		return if self.flier then math.clamp((move - 0.25) / 0.4, 0, 1) else 0
	end

	-- A leg hinged at the hip (x, y, z), bounding: the front pair lags the hind
	-- push; it paws the air on a rear-up; a flier tucks it back in flight.
	function B:leg(group: any, x: number, y: number, z: number, front: boolean, side: number, o: any?): any
		local opts = o or {}
		local phase = (if front then K.FRONT_LAG else 0) + (if side > 0 then K.SIDE_LAG else 0) + (opts.phase or 0)
		local amp = opts.amp or (if front then 0.5 else 0.65)
		return self:piece({ group }, self:at(x, y, z), function(t: number, move: number): CFrame
			local walk = math.sin(t * self.gait - phase) * amp * math.min(move, 1.2)
			local fly = self:flying(move)
			local a = walk * (1 - fly) + fly * (if front then -0.9 else 1.0)
			if front and self.rearing then a += self:mu(t) * (0.7 + math.sin(t * 16 + phase) * 0.4) end
			if opts.extra then a += opts.extra(t, move) end
			return CFrame.Angles(a, 0, 0)
		end)
	end
	-- Four legs: x = half the spread, front / hind = z, hip = y; `make(front, side)`
	-- builds a leg (else a straight one: len, w, main, foot, footH).
	function B:legs4(o: any): { any }
		local w = o.w or 2
		local off = if w % 2 == 0 then 0.5 else 0
		local pieces = {}
		for _, front in ipairs({ true, false }) do
			for _, side in ipairs({ -1, 1 }) do
				local g = if o.make then o.make(front, side) else K.legGroup(o.len, w, if front and o.frontMain then o.frontMain else o.main, o.foot, o.footH)
				local extra = o.extra and function(t: number, move: number): number return o.extra(t, move, front, side) end or nil
				-- (an even-width leg's bricks run -w/2 .. w/2-1: shifted half a brick to centre it)
				table.insert(pieces, self:leg(g, side * o.x + off, o.hip, if front then o.front else o.hind, front, side, { extra = extra, amp = o.amp }))
			end
		end
		return pieces
	end
	-- Jointed crawler legs splayed out to the sides; alternate legs step
	-- together (a quick tripod skitter). zs: each pair's z; hipX, hipY; reach,
	-- drop (bricks); main, dark; extra(t, move, i, side) → more lift.
	function B:crawlLegs(o: any)
		local spd = o.speed or 16
		for i, z in ipairs(o.zs) do
			for _, side in ipairs({ -1, 1 }) do
				local g = Kit.group()
				for k = 0, o.reach do Kit.set(g, side * k, math.floor(k * 0.6), 0, o.main.color, o.main.neon) end
				local top = math.floor(o.reach * 0.6)
				for k = 0, o.drop do
					local p = if k == o.drop then o.dark else o.main
					Kit.set(g, side * (o.reach + 1 + math.floor(k / 3)), top - k, 0, p.color, p.neon)
				end
				if o.joint then Kit.set(g, side * (o.reach + 1), top + 1, 0, o.joint.color, o.joint.neon) end
				local phase = ((i + (if side == 1 then 1 else 0)) % 2) * math.pi
				self:piece({ g }, self:at(side * o.hipX, o.hipY, z), function(t: number, move: number): CFrame
					local m = 0.12 + math.min(move, 1.2) * 0.6
					local s = t * spd + phase
					local lift = math.max(0, -math.cos(s)) * 0.35 * m
					if o.extra then lift += o.extra(t, move, i, side) end
					return CFrame.Angles(0, math.sin(s) * 0.4 * m, side * lift)
				end)
			end
		end
	end
	-- A wing (built along +x for side 1) hinged at (x, y, z): folded back at
	-- rest, beating hard in flight; spread(t) 0..1 throws it wide open.
	function B:wing(group: any, x: number, y: number, z: number, side: number, o: any?): any
		local opts = o or {}
		local flap = W.runner(opts.rest or 1.4, opts.beat or 10)
		return self:piece({ group }, self:at(x, y, z), function(t: number, move: number): CFrame
			local fly = math.max(self:flying(move), if self.flier then 0 else math.min(move, 1) * 0.6)
			local sp = if opts.spread then opts.spread(t) else 0
			local open = math.max(fly, sp)
			local a = -0.35 * (1 - open) + 0.1 * open + math.sin(flap(t, move)) * (0.05 + 0.6 * fly) + sp * 0.45
			return CFrame.Angles(0, -side * 0.6 * (1 - open), side * a)
		end)
	end

	-- ── Whole-rig flourishes ─────────────────────────────────────────────────
	-- Rear up about the hind feet (z, bricks) when called.
	function B:rearUp(hindZ: number, angle: number?)
		self.rearing = true
		local hind = Vector3.new(0, 0, hindZ * self.V)
		self:move(function(t: number): CFrame
			local a = self:mu(t) * (angle or 0.35)
			if a == 0 then return CFrame.identity end
			return CFrame.new(hind) * CFrame.Angles(a, 0, 0) * CFrame.new(-hind)
		end)
	end
	-- A full turn in place, rising a little, when called.
	function B:spinUp(height: number?)
		self:move(function(t: number): CFrame
			local s = self:since(t)
			if s >= self.mountLen then return CFrame.identity end
			return CFrame.new(0, bump(s, 0, self.mountLen) * (height or 0.8), 0) * CFrame.Angles(0, ease(s / self.mountLen) * math.pi * 2, 0)
		end)
	end
	-- Two bouncy hops (the Secret minis), when called.
	function B:hopUp(height: number?)
		self:move(function(t: number): CFrame
			local s = self:since(t)
			if s >= self.mountLen then return CFrame.identity end
			local k = (s / self.mountLen * 2) % 1
			return CFrame.new(0, math.sin(k * math.pi) * (height or 1.2), 0) * CFrame.Angles(math.sin(k * math.pi * 2) * 0.12, 0, 0)
		end)
	end
	-- Hover: bob and lean into the way it goes (floating platforms and swimmers).
	function B:hoverMove(amp: number?)
		self:move(function(t: number, move: number): CFrame
			return CFrame.new(0, math.sin(t * 1.5) * (amp or 0.14), 0) * CFrame.Angles(-0.07 * math.min(move, 1), 0, math.sin(t * 0.9) * 0.03)
		end)
	end

	-- ── Running effects ──────────────────────────────────────────────────────
	-- Dust from the feet while it runs, and a puff where it lands from the
	-- mount-up. (len, width: the footprint, bricks.)
	function B:dust(len: number, width: number, color: Color3?): ParticleEmitter
		local e = self:fx(self.body, Vector3.new(0, 0.2, 0), Vector3.new(width * self.V, 0.2, len * self.V), "dust", color or Color3.fromRGB(150, 135, 115))
		self:whileRunning(e, 16)
		self:atMount(self.mountLen * 0.9, function() e:Emit(14) end)
		return e
	end
	-- A trail of some other stuff (embers, petals, pixels…) off the body while it runs.
	function B:runTrail(at: Vector3, size: Vector3, kind: string, color: Color3, rate: number?): ParticleEmitter
		local e = self:fx(self.body, at, size, kind, color)
		self:whileRunning(e, rate or 14)
		return e
	end

	-- ── Tier extras ──────────────────────────────────────────────────────────
	-- Legendary: particles clinging all over the body, always.
	function B:aura(size: Vector3, at: Vector3, kind: string, color: Color3, rate: number?): ParticleEmitter
		local e = self:fx(self.body, at, size, kind, color)
		if rate then e.Rate = rate end
		return e
	end
	-- Mythic: a glowing rune circle turning on the ground below.
	function B:runeCircle(radius: number, color: Color3)
		W.spinRing(self.rig, CFrame.new(0, 0.12, 0), radius, { color = color, neon = true }, 0.45, self.V)
		W.spinRing(self.rig, CFrame.new(0, 0.14, 0), radius - 2, { color = color:Lerp(Color3.new(1, 1, 1), 0.45), neon = true }, -0.8, self.V, true)
		-- rune marks round the outside, turning the other way
		local g = Kit.group()
		for i = 0, 11 do
			local a = i / 12 * math.pi * 2
			local x, z = math.floor(math.cos(a) * (radius + 1.5) + 0.5), math.floor(math.sin(a) * (radius + 1.5) + 0.5)
			Kit.set(g, x, 0, z, color, true)
			if i % 2 == 0 then Kit.set(g, x + (if i % 4 == 0 then 1 else 0), 0, z + (if i % 4 == 0 then 0 else 1), color, true) end
		end
		self:piece({ g }, CFrame.new(0, 0.13, 0), function(t: number): CFrame return CFrame.Angles(0, -t * 0.25, 0) end)
	end
	-- Mythic: the emblem floating behind the rider (built in the XY plane).
	function B:emblem(group: any, x: number, y: number, z: number): any
		return self:piece({ group }, self:at(x, y, z), function(t: number): CFrame
			return CFrame.new(0, math.sin(t * 1.8) * 0.12, 0) * CFrame.Angles(0, math.sin(t * 0.6) * 0.35, 0)
		end)
	end
	-- A running total of rate(t, move) per second (a turn that speeds up and
	-- slows down without jumping); returns a getter.
	function B:accum(rate: (number, number) -> number): () -> number
		local v, last = 0, nil
		self:every(function(t: number, move: number)
			if last then v += math.clamp(t - last, 0, 0.1) * rate(t, move) end
			last = t
		end)
		return function(): number return v end
	end
	-- `n` things circling `home` at speed(t) (radians per second), bobbing and tumbling.
	function B:orbitVar(home: CFrame, n: number, radius: number, speed: (number) -> number, make: (number) -> any, tilt: number?, bob: number?): { any }
		local turn = self:accum(function(t: number): number return speed(t) end)
		local out = {}
		for i = 1, n do
			local k = i
			table.insert(out, self:piece({ make(i) }, home, function(t: number): CFrame
				local a = turn() + k / n * math.pi * 2
				return CFrame.Angles(tilt or 0, 0, 0) * CFrame.new(math.cos(a) * radius, math.sin(t * 2 + k) * (bob or 0), math.sin(a) * radius)
					* CFrame.Angles(t * 1.3, -a, 0)
			end))
		end
		return out
	end

	-- Pieces bobbing on their own, out of step (detached voxels).
	function B:floater(group: any, home: CFrame, phase: number, amp: number?, spin: number?): any
		return self:piece({ group }, home, function(t: number): CFrame
			return CFrame.new(0, math.sin(t * 1.9 + phase) * (amp or 0.18), 0) * CFrame.Angles(0, (spin or 0) * t, 0)
		end)
	end
	-- Secret: the boss-trophy frame. A small gold crown floats over the seat,
	-- a trophy plate sits on the saddle's flank, a flickering black-gold
	-- aura glitches round it. (seat: bricks; hw: half the saddle's width)
	function B:trophy(sx: number, sy: number, sz: number, hw: number)
		local GOLD, RUBY, BLACK = glow(255, 200, 60), glow(255, 50, 70), rgb(12, 10, 14)
		local crown = Kit.group()
		for x = -2, 2 do
			for z = -2, 2 do
				if math.abs(x) == 2 or math.abs(z) == 2 then Kit.set(crown, x, 0, z, GOLD.color, true) end
			end
		end
		for _, c in ipairs({ { -2, -2 }, { 2, -2 }, { -2, 2 }, { 2, 2 }, { 0, -2 }, { 0, 2 }, { -2, 0 }, { 2, 0 } }) do
			Kit.set(crown, c[1], 1, c[2], GOLD.color, true)
		end
		Kit.set(crown, 0, 2, -2, RUBY.color, true)
		Kit.set(crown, 0, 2, 2, RUBY.color, true)
		local crownPiece = self:piece({ crown }, self:at(sx, sy + 10, sz), function(t: number): CFrame
			-- (now and then it glitches a brick sideways)
			local g = if math.noise(t * 3, 7.3) > 0.42 then 0.18 else 0
			return CFrame.new(g, math.sin(t * 2.2) * 0.12, 0) * CFrame.Angles(0, t * 0.8, 0)
		end)
		self:fx(crownPiece, Vector3.zero, Vector3.new(1, 0.4, 1), "stars", Color3.fromRGB(255, 215, 90))
		-- the trophy plate
		local plate = Kit.group()
		Kit.box(plate, 0, -1, -1, 0, 1, 1, GOLD)
		Kit.box(plate, 0, 0, 0, 0, 0, 0, { color = BLACK.color })
		self:piece({ plate }, self:at(sx + hw + 1.6, sy - 1, sz), function(t: number, move: number): CFrame
			return CFrame.new(0, math.sin(t * 1.6) * 0.025 * math.max(0, 1 - move), 0)
		end)
		-- the glitching black-gold aura: a dashed ring that flickers, black
		-- and gold motes clinging on
		local ring = W.spinRing(self.rig, CFrame.new(0, 0.12, 0), 7, GOLD, 0.9, self.V, true)
		local last = nil
		self:every(function(t: number)
			local on = math.noise(t * 8, 1.7) > -0.25
			if on == last then return end
			last = on
			for _, p in ipairs(ring.parts) do p.LocalTransparencyModifier = if on then 0 else 0.85 end
		end)
		local anchor = self.body or crownPiece
		local gold = self:fx(anchor, self:v(0, sy - 3, sz), self:v(hw * 2 + 3, 5, 9), "sparks", Color3.fromRGB(255, 205, 70))
		gold.Rate = 6
		local dark = self:fx(anchor, self:v(0, sy - 3, sz), self:v(hw * 2 + 3, 5, 9), "smoke", Color3.fromRGB(20, 12, 20))
		dark.Rate = 4
	end

	-- ── Wolves (Frost Wolf, Blood Moon Warg) ─────────────────────────────────
	-- The Dire Wolf's frame in another coat. P: fur, fur2, pale, dark, eye,
	-- seat, trim (saddle); opts.ornate: a Legendary saddle (gem = P.gem).
	-- Returns the builder with b.howl(t) (its emote, 0..1) for extras.
	function K.wolf(look: string, P: any, opts: any?): any
		local o = opts or {}
		local b = K.new(look, { gait = 10, emoteLen = 2.8 })
		local V = b.V
		local howl = function(t: number): number return if o.howl == false then 0 else b:em(t) end
		b:gallop(6)
		b:rearUp(5, 0.35)
		b:move(function(t: number): CFrame
			local a = howl(t) * 0.1
			if a == 0 then return CFrame.identity end
			local hind = Vector3.new(0, 0, 5 * V)
			return CFrame.new(hind) * CFrame.Angles(a, 0, 0) * CFrame.new(-hind)
		end)
		local body = Kit.group()
		Kit.box(body, -2, 5, -6, 2, 8, 5, P.fur)
		Kit.box(body, -2, 5, -6, 2, 5, 5, P.pale)
		Kit.box(body, -2, 4, -7, 2, 8, -7, P.pale)
		Kit.box(body, -2, 9, -6, 2, 9, -4, P.fur2)
		Kit.box(body, -1, 10, -6, 1, 10, -5, P.fur2)
		Kit.box(body, -1, 9, 4, 1, 9, 5, P.fur2)
		for _, sx in ipairs({ -3, 3 }) do Kit.box(body, sx, 6, -6, sx, 8, -4, P.fur2) end
		if o.ornate then
			K.ornateSaddle(body, 2, 9, -2, 1, P.seat, P.gem)
		else
			K.saddle(body, 2, 9, -2, 1, P.seat, P.trim, P.trim, rgb(96, 96, 104))
		end
		if o.body then o.body(body) end
		b:bodyPiece({ body })
		local head = Kit.group()
		Kit.box(head, -1, -2, -2, 1, 1, 0, P.fur)
		Kit.box(head, -2, 0, -5, 2, 3, -2, P.fur)
		Kit.box(head, -2, 3, -5, 2, 3, -3, P.fur2)
		Kit.box(head, -1, 0, -8, 1, 1, -6, P.pale)
		Kit.box(head, -1, 2, -6, 1, 2, -6, P.fur)
		Kit.set(head, 0, 1, -9, P.dark.color)
		for _, sx in ipairs({ -3, 3 }) do Kit.box(head, sx, 0, -3, sx, 1, -2, P.fur2) end
		for _, sx in ipairs({ -2, 2 }) do Kit.set(head, sx, 2, -4, P.eye.color, true) end
		if o.head then o.head(head) end
		b:head({ head }, 0, 8, -6, function(t: number): (number, number)
			local h = howl(t)
			return h * 0.95 + b:mu(t) * 0.35 + (if o.headExtra then o.headExtra(t) else 0), -math.sin(t * 0.7) * 0.12 * h
		end)
		local jaw = Kit.group()
		Kit.box(jaw, -1, -1, -7, 1, -1, -3, P.dark)
		Kit.set(jaw, 0, -1, -8, P.pale.color)
		b:onHead({ jaw }, Vector3.new(0, -0.5, -3), function(t: number): CFrame
			return CFrame.Angles(-(howl(t) * 0.45 + b:mu(t) * 0.25 + (o.jaw and o.jaw(t) or 0)), 0, 0)
		end)
		for i, sx in ipairs({ -2, 2 }) do
			local ear = Kit.group()
			Kit.set(ear, 0, 0, 0, P.fur.color)
			Kit.set(ear, 0, 1, 0, P.dark.color)
			b:onHead({ ear }, Vector3.new(sx, 4, -2), function(t: number): CFrame
				local f = b:flick(t, i * 1.3)
				return CFrame.Angles(-f * 0.5 - howl(t) * 0.4, 0, (if sx > 0 then -1 else 1) * f * 0.3)
			end)
			b:eyelid(sx, 2, -4, if sx > 0 then 1 else -1, P.fur, function(t: number): boolean return howl(t) > 0.5 end)
		end
		b:legs4({ x = 1.5, front = -4, hind = 5, hip = 5, len = 5, w = 2, main = P.fur, foot = P.dark })
		local tail = Kit.group()
		for i = 0, 5 do
			local y = math.floor(i * 0.5)
			Kit.box(tail, -1, y, i, 0, y + 1, i, if i >= 4 then P.pale elseif i >= 2 then P.fur2 else P.fur)
		end
		b.tailPiece = b:tail({ tail }, 0.5, 7, 6, function(t: number): (number, number) return howl(t) * 0.5, 0 end)
		b:dust(12, 5, P.dustColor)
		b.howl = howl
		b.seat = Vector3.new(0, 10, 0)
		return b
	end

	return K
end
