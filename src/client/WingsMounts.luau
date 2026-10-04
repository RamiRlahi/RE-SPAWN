--[[
	WingsMounts.luau
	Wings and mounts (gacha rewards, GachaRewards types "wings" / "mount"),
	built from toy bricks (BrickModels.Kit) as small rigs of moving pieces and
	animated every frame:

	  wings    two wings on the back that flap (harder while you move); each
	           kind has its own shape, colours and particles
	  mounts   ridden in the lobby (MountManager lifts the rider and speeds
	           them up): legs walk in a gait matched to your speed, the head
	           bobs, the tail sways, the body breathes; spiders skitter,
	           scorpions curl their sting, the serpent swims through the air,
	           dragons beat their wings; floating platforms (carpet, star,
	           void disc) hover and are sat on, legs out in front

	Every client builds them locally on every player (from the player's
	"Wings" attribute and the character's "Riding" attribute), joints them to
	the character (Attach: drawn exactly with the body, no lag or jitter),
	and drops the ones far from the camera.

	  WingsMounts.Init()
	  WingsMounts.Build(rewardId) → rig      (for the selection screens)
	  WingsMounts.Pose(rig, cframe, t, move) (rig.world: the WorldRoot it lives in)
	  WingsMounts.Attach(rig, basePart, offset) + Animate(rig, t, move)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local BrickModels = require(script.Parent:WaitForChild("BrickModels"))
local RideData = require(Shared:WaitForChild("RideData"))

local Kit = BrickModels.Kit
local WingsMounts = {}

local VOX_WING = 0.26  -- studs per brick, wings on a character
local VOX_MOUNT = 0.42 -- studs per brick, mounts
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local FIRE_SPARK = "rbxasset://textures/particles/fire_sparks_main.dds"

type Paint = { color: Color3, neon: boolean?, alpha: number? }
type Piece = { parts: { BasePart }, offsets: { CFrame }, home: CFrame, anim: ((t: number, move: number) -> CFrame)?, motor: Motor6D? }
export type Rig = { model: Model, pieces: { Piece }, world: WorldRoot?, allParts: { BasePart }, cfs: { CFrame }, kind: string,
	base: BasePart?, baseOff: CFrame? }

local function rgb(r: number, g: number, b: number): Paint return { color = Color3.fromRGB(r, g, b) } end
local function glow(r: number, g: number, b: number): Paint return { color = Color3.fromRGB(r, g, b), neon = true } end
local function glass(r: number, g: number, b: number, a: number): Paint return { color = Color3.fromRGB(r, g, b), alpha = a } end

-- ─── Rig building ──────────────────────────────────────────────────────────
local function newRig(name: string, kind: string): Rig
	local m = Instance.new("Model")
	m.Name = name
	return { model = m, pieces = {}, world = nil, allParts = {}, cfs = {}, kind = kind }
end

-- Bricks of `groups` (built round their own origin) become one moving piece
-- of the rig, `scale` studs per brick, at `home` (studs, rig space).
local function addPiece(rig: Rig, groups: { any }, scale: number, home: CFrame, anim: ((number, number) -> CFrame)?): Piece
	local m = Kit.render("piece", groups, true)
	local piece: Piece = { parts = {}, offsets = {}, home = home, anim = anim }
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Center" then continue end
			local p = d :: BasePart
			local rot = p.CFrame.Rotation
			local pos = p.Position * scale
			p.Size *= scale
			p.CanQuery = false
			table.insert(piece.parts, p)
			table.insert(piece.offsets, CFrame.new(pos) * rot)
		end
	end
	for _, p in ipairs(piece.parts) do p.Parent = rig.model end
	m:Destroy()
	table.insert(rig.pieces, piece)
	for _, p in ipairs(piece.parts) do table.insert(rig.allParts, p) end
	return piece
end

-- An invisible anchor inside a piece for particles to pour from.
local function addEmitterAnchor(rig: Rig, piece: Piece, at: Vector3, size: Vector3): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Transparency = 1
	p.Size = size
	p.Parent = rig.model
	table.insert(piece.parts, p)
	table.insert(piece.offsets, CFrame.new(at))
	table.insert(rig.allParts, p)
	return p
end

local function seq(...: number): NumberSequence
	local v = { ... }
	local pts = {}
	for i, x in ipairs(v) do table.insert(pts, NumberSequenceKeypoint.new((i - 1) / math.max(1, #v - 1), x)) end
	return NumberSequence.new(pts)
end

-- Particle presets.
local function fx(anchor: BasePart, kind: string, color: Color3)
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	if kind == "fire" then
		e.Texture, e.Color, e.LightEmission = FIRE, ColorSequence.new(Color3.fromRGB(255, 220, 120), color), 1
		e.Size, e.Transparency = seq(0.6, 0.2), seq(0.2, 1)
		e.Lifetime, e.Speed, e.Rate = NumberRange.new(0.4, 0.7), NumberRange.new(1, 2.5), 22
		e.Acceleration = Vector3.new(0, 3, 0)
	elseif kind == "embers" then
		e.Texture, e.Color, e.LightEmission = FIRE_SPARK, ColorSequence.new(Color3.fromRGB(255, 230, 150), color), 1
		e.Size = seq(0.25, 0)
		e.Lifetime, e.Speed, e.Rate = NumberRange.new(0.8, 1.4), NumberRange.new(1, 3), 12
		e.Acceleration, e.SpreadAngle = Vector3.new(0, 2, 0), Vector2.new(40, 40)
	elseif kind == "frost" then
		e.Texture, e.Color, e.LightEmission = SPARK, ColorSequence.new(Color3.new(1, 1, 1), color), 0.8
		e.Size = seq(0.18, 0.12)
		e.Lifetime, e.Speed, e.Rate = NumberRange.new(1.2, 2), NumberRange.new(0.2, 0.6), 10
		e.Acceleration, e.RotSpeed = Vector3.new(0, -1, 0), NumberRange.new(-90, 90)
	elseif kind == "sparks" then
		e.Texture, e.Color, e.LightEmission = SPARK, ColorSequence.new(Color3.new(1, 1, 1), color), 1
		e.Size = seq(0.3, 0)
		e.Lifetime, e.Speed, e.Rate = NumberRange.new(0.1, 0.25), NumberRange.new(4, 8), 16
		e.SpreadAngle = Vector2.new(180, 180)
	elseif kind == "smoke" then
		e.Texture, e.Color, e.LightEmission = SMOKE, ColorSequence.new(color, Color3.fromRGB(15, 0, 30)), 0.3
		e.Size, e.Transparency = seq(0.6, 1.6), seq(0.45, 1)
		e.Lifetime, e.Speed, e.Rate = NumberRange.new(0.8, 1.4), NumberRange.new(0.2, 0.8), 10
		e.RotSpeed = NumberRange.new(-60, 60)
	elseif kind == "stars" then
		e.Texture, e.Color, e.LightEmission = SPARK, ColorSequence.new(Color3.new(1, 1, 1), color), 1
		e.Size = seq(0, 0.3, 0)
		e.Lifetime, e.Speed, e.Rate = NumberRange.new(0.8, 1.6), NumberRange.new(0, 0.3), 12
		e.RotSpeed = NumberRange.new(-180, 180)
	elseif kind == "drip" then
		e.Texture, e.Color, e.LightEmission = SPARK, ColorSequence.new(color), 0.6
		e.Size = seq(0.18, 0.1)
		e.Lifetime, e.Speed, e.Rate = NumberRange.new(0.6, 1), NumberRange.new(0, 0.1), 6
		e.Acceleration = Vector3.new(0, -9, 0)
	end
	e.Parent = anchor
end

-- ─── Showpieces (Epic and up) ───────────────────────────────────────────────
-- An empty moving piece, for lights and emitters to ride on.
local function addAnchorPiece(rig: Rig, home: CFrame, anim: ((number, number) -> CFrame)?): Piece
	local piece: Piece = { parts = {}, offsets = {}, home = home, anim = anim }
	table.insert(rig.pieces, piece)
	return piece
end

-- A ribbon of light streaming off a point of a piece as it moves.
local function addTrail(rig: Rig, piece: Piece, at: Vector3, width: number, color: Color3, life: number?): Trail
	local p = addEmitterAnchor(rig, piece, at, Vector3.one * 0.1)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, width / 2, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -width / 2, 0)
	a1.Parent = p
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	tr.Transparency = seq(0.1, 1)
	tr.Lifetime = life or 0.5
	tr.LightEmission = 1
	tr.LightInfluence = 0
	tr.FaceCamera = true
	tr.WidthScale = seq(1, 0)
	tr.MinLength = 0.02
	tr.Parent = p
	return tr
end

local function addLight(rig: Rig, piece: Piece, at: Vector3, color: Color3, range: number, brightness: number)
	local p = addEmitterAnchor(rig, piece, at, Vector3.one * 0.1)
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, brightness, false
	l.Parent = p
end

-- A ring of glowing bricks turning flat (dashed: every other block missing).
local function spinRing(rig: Rig, home: CFrame, radius: number, paint: Paint, speed: number, scale: number, dashed: boolean?): Piece
	local g = Kit.group()
	Kit.lathe(g, { { 0, radius, radius - 0.7 } }, function(x, _, z)
		if dashed and math.floor((math.atan2(z, x) + math.pi) / (math.pi * 2) * 28) % 2 == 0 then return nil end
		return paint
	end)
	return addPiece(rig, { g }, scale, home, function(t: number): CFrame
		return CFrame.Angles(0, t * speed, 0)
	end)
end

-- `n` things circling a point, bobbing and tumbling.
local function orbit(rig: Rig, home: CFrame, n: number, radius: number, speed: number, scale: number, make: (number) -> any, tilt: number?, bob: number?): { Piece }
	local out = {}
	for i = 1, n do
		local k = i
		table.insert(out, addPiece(rig, { make(i) }, scale, home, function(t: number): CFrame
			local a = t * speed + k / n * math.pi * 2
			return CFrame.Angles(tilt or 0, 0, 0) * CFrame.new(math.cos(a) * radius, math.sin(t * 2 + k) * (bob or 0), math.sin(a) * radius)
				* CFrame.Angles(t * 1.3, -a, 0)
		end))
	end
	return out
end

local function ball(r: number, paint: Paint): any
	local g = Kit.group()
	Kit.sphere(g, r, function() return paint end)
	return g
end

local function shard(paint: Paint, tip: Paint): any
	local g = Kit.group()
	Kit.box(g, 0, -1, 0, 0, 1, 0, paint)
	Kit.set(g, 0, 2, 0, tip.color, tip.neon)
	Kit.set(g, 0, -2, 0, tip.color, tip.neon)
	return g
end

-- Rays fanning out round a centre, turning (an eclipse's corona).
local function corona(rig: Rig, home: CFrame, n: number, inner: number, len: number, paint: Paint, speed: number, scale: number): Piece
	local g = Kit.group()
	for i = 1, n do
		local a = i / n * math.pi * 2
		local l = if i % 2 == 0 then len else math.floor(len * 0.6)
		for r = inner, inner + l do
			Kit.set(g, math.floor(math.cos(a) * r + 0.5), math.floor(math.sin(a) * r + 0.5), 0, paint.color, paint.neon)
		end
	end
	return addPiece(rig, { g }, scale, home, function(t: number): CFrame
		return CFrame.Angles(0, 0, t * speed)
	end)
end

-- Fire (or anything) breathed forward in bursts: on for `on` seconds every `period`.
local function breath(rig: Rig, home: CFrame, color: Color3, period: number, on: number, size: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	local piece = addAnchorPiece(rig, home, function(t: number): CFrame
		e.Enabled = (t % period) < on
		return CFrame.new()
	end)
	local anchor = addEmitterAnchor(rig, piece, Vector3.zero, Vector3.one * 0.4)
	e.Texture = FIRE
	e.Color = ColorSequence.new(Color3.fromRGB(255, 245, 200), color)
	e.LightEmission, e.LightInfluence = 1, 0
	e.Size = seq(0.4 * size, 2.6 * size)
	e.Transparency = seq(0.05, 1)
	e.Lifetime = NumberRange.new(0.45, 0.75)
	e.Speed = NumberRange.new(14 * size, 20 * size)
	e.SpreadAngle = Vector2.new(12, 12)
	e.EmissionDirection = Enum.NormalId.Front
	e.Acceleration = Vector3.new(0, 3, 0)
	e.Rate = 80
	e.Enabled = false
	e.Parent = anchor
	return e
end

-- Rarity of a wings / mount look: 1 Common .. 5 Mythic.
local ORDER = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
local function tierOf(kind: string, look: string): number
	for _, r in ipairs(GachaRewards.All) do
		if r.type == kind and r.look == look then return table.find(ORDER, r.rarity) or 1 end
	end
	return 1
end

local function mirror(g: any): any
	local m = Kit.group()
	for _, v in pairs(g.vox) do
		Kit.set(m, -v.x, v.y, v.z, v.color, v.neon, v.alpha)
	end
	return m
end

-- ─── Wings ─────────────────────────────────────────────────────────────────
-- Right-wing sprites; column 1 is the hinge at the back.
local SHAPES: { [string]: { string } } = {
	feather = {
		".........AB",
		"........AAB",
		"......AAAAB",
		"....AAAAAAB",
		"..AAAAAAAAB",
		".AAAAAAAAB.",
		"AAAAAAAAAB.",
		"AAAAAAAAB..",
		"AAAAAAAB...",
		"ABABABA....",
		"B.B.B.B....",
		".B..B......",
	},
	membrane = {
		"...........B",
		".........BB.",
		".......BBAB.",
		".....BBAAAB.",
		"...BBAAAAAB.",
		".BBAAAABAAB.",
		"BAAAAABAAAB.",
		"BAAAABAAAB..",
		"BAAABAAAB...",
		".AAB.AAB....",
		"..B...B.....",
	},
	insect = {
		"....AAAAA..",
		"..AAAGAAAA.",
		".AAAGAGAAAA",
		"AAAAAGAAAAA",
		"AAAAAAAAAA.",
		".AAAAAAA...",
		"..AAGAAA...",
		"...AAAA....",
		"....AA.....",
	},
	bolt = {
		".........GG",
		".......GGG.",
		".....GGGG..",
		"GGGGGGGG...",
		"...GGGGG...",
		".....GGG...",
		"......GG...",
		".......G...",
	},
}

type WingSpec = { shape: string, A: Paint?, B: Paint?, G: Paint?, left: { [string]: Paint }?, size: number?, fx: string?, fxColor: Color3?, stars: boolean?, extra: string? }
local WINGS: { [string]: WingSpec } = {
	raven = { shape = "feather", A = rgb(35, 35, 48), B = rgb(75, 75, 95) },
	bat = { shape = "membrane", A = rgb(95, 40, 130), B = rgb(45, 20, 60) },
	leaf = { shape = "insect", A = rgb(95, 190, 55), G = glow(170, 255, 120) },
	frost = { shape = "feather", A = glass(150, 220, 255, 0.25), B = glow(205, 245, 255), fx = "frost", fxColor = Color3.fromRGB(170, 230, 255) },
	ember = { shape = "feather", A = rgb(225, 85, 30), B = glow(255, 200, 80), fx = "embers", fxColor = Color3.fromRGB(255, 120, 40) },
	storm = { shape = "bolt", G = glow(110, 190, 255), fx = "sparks", fxColor = Color3.fromRGB(120, 190, 255) },
	moon = { shape = "feather", A = rgb(232, 234, 248), B = rgb(185, 195, 230), extra = "moon" },
	venom = { shape = "insect", A = rgb(55, 130, 40), G = glow(150, 255, 60), fx = "drip", fxColor = Color3.fromRGB(150, 255, 60) },
	void = { shape = "membrane", A = glass(100, 35, 180, 0.15), B = glow(190, 90, 255), fx = "smoke", fxColor = Color3.fromRGB(150, 60, 255) },
	celestial = { shape = "feather", A = rgb(255, 212, 105), B = glow(255, 245, 205), size = 1.25, fx = "stars", fxColor = Color3.fromRGB(255, 225, 140) },
	dragon = { shape = "membrane", A = rgb(170, 50, 30), B = rgb(60, 20, 15), size = 1.3, fx = "embers", fxColor = Color3.fromRGB(255, 110, 40) },
	eclipse = { shape = "feather", A = rgb(255, 200, 80), B = glow(255, 240, 180), left = { A = rgb(25, 20, 35), B = glow(255, 70, 120) }, size = 1.15, extra = "eclipse" },
	cosmic = { shape = "feather", A = glass(55, 25, 135, 0.1), B = glow(170, 120, 255), size = 1.2, stars = true, fx = "stars", fxColor = Color3.fromRGB(200, 170, 255) },
}

local function wingGroup(spec: WingSpec, palette: { [string]: Paint }): any
	local rows = SHAPES[spec.shape]
	local g = Kit.group()
	local w = #rows[1]
	Kit.sprite(g, rows, palette, 1, 0, math.floor(w / 2), -math.floor(#rows / 2))
	if spec.stars then
		for _, v in pairs(g.vox) do
			if (v.x * 7 + v.y * 3) % 6 == 0 then
				v.color, v.neon, v.alpha = Color3.new(1, 1, 1), true, 0
			end
		end
	end
	return g
end

-- Two wings on `rig` hinged at `at` (studs, rig space), angled back, flapping.
-- Returns each wing's piece, side and wingtip (in the piece's space).
type WingInfo = { piece: Piece, side: number, tip: Vector3, mid: Vector3 }
local function addWings(rig: Rig, spec: WingSpec, scale: number, at: Vector3, spread: number, speed: number, amp: number, palette0: { [string]: Paint }?): { WingInfo }
	local palette = palette0 or ({ A = spec.A, B = spec.B, G = spec.G } :: { [string]: Paint })
	local right = wingGroup(spec, palette)
	local left = mirror(wingGroup(spec, if spec.left then spec.left :: any else palette))
	local rows = SHAPES[spec.shape]
	local w, h = #rows[1], #rows
	local out = {}
	for side = -1, 1, 2 do
		local g = if side == 1 then right else left
		local home = CFrame.new(at + Vector3.new(side * 0.15, 0, 0)) * CFrame.Angles(0, -side * math.rad(spread), 0)
		local piece = addPiece(rig, { g }, scale, home, function(t: number, move: number): CFrame
			local f = speed * (1 + move * 0.9)
			local a = math.sin(t * f) * math.rad(amp * (0.6 + move * 0.7))
			return CFrame.Angles(0, -side * a * 0.35, side * a)
		end)
		if spec.fx then
			local anchor = addEmitterAnchor(rig, piece, Vector3.new(side * w * scale * 0.5, 0, 0), Vector3.new(w * scale * 0.8, h * scale * 0.6, 0.2))
			fx(anchor, spec.fx, spec.fxColor or Color3.new(1, 1, 1))
		end
		table.insert(out, { piece = piece, side = side, tip = Vector3.new(side * (w - 1) * scale, (h - 1 - math.floor(h / 2)) * scale, 0),
			mid = Vector3.new(side * w * scale * 0.5, 0, 0) })
	end
	return out
end

local function buildWings(look: string): Rig
	local spec = WINGS[look] or WINGS.raven
	local rig = newRig("Wings_" .. look, "wings")
	local tier = tierOf("wings", look)
	local grand = if tier >= 5 then 1.6 elseif tier == 4 then 1.5 elseif tier == 3 then 1.3 else 1
	local s = VOX_WING * (spec.size or 1) * grand
	local col = spec.fxColor or (spec.B and spec.B.color) or (spec.G and spec.G.color) or Color3.new(1, 1, 1)
	local palette = { A = spec.A, B = spec.B, G = spec.G } :: { [string]: Paint }
	if look == "dragon" then palette.B = glow(255, 110, 40) end -- (veins of fire)
	local main = addWings(rig, spec, s, Vector3.zero, 28, 3.6, 14, palette)
	if tier >= 3 then
		-- ribbons of light off the wingtips, and the wings light you up
		for _, wi in ipairs(main) do addTrail(rig, wi.piece, wi.tip, 0.35 * grand, col, 0.6) end
		addLight(rig, main[1].piece, Vector3.zero, col, 10, 1.4)
	end
	if tier >= 4 then
		-- a second, smaller pair beneath
		local lower = addWings(rig, spec, s * 0.62, Vector3.new(0, -0.55, 0.05), 46, 3.1, 18, palette)
		for _, wi in ipairs(lower) do addTrail(rig, wi.piece, wi.tip, 0.25 * grand, col, 0.45) end
	end
	if look == "dragon" then
		for _, wi in ipairs(main) do
			fx(addEmitterAnchor(rig, wi.piece, wi.tip, Vector3.one * 0.4), "fire", Color3.fromRGB(255, 110, 30))
		end
	end

	local V = VOX_WING
	if look == "venom" then
		-- toxic spores circling, a sickly mist
		orbit(rig, CFrame.new(0, 0.2, 0.4), 4, 1.9 * grand, 1.4, V, function() return ball(1, glow(150, 255, 60)) end, 0.2, 0.25)
		fx(addEmitterAnchor(rig, main[1].piece, Vector3.zero, Vector3.new(2, 2, 0.5)), "smoke", Color3.fromRGB(90, 200, 40))
	elseif look == "void" then
		-- a rift torn open behind you, shards of void circling it
		local rift = Kit.group()
		Kit.disc(rift, 6, 1, function(_, _, d)
			if d > 5.2 then return glow(190, 90, 255) end
			if d > 4.2 then return rgb(60, 20, 110) end
			return rgb(5, 0, 12)
		end)
		local riftPiece = addPiece(rig, { rift }, V, CFrame.new(0, 0.25, 0.55), function(t: number): CFrame
			return CFrame.Angles(0, 0, t * 0.9) * CFrame.new(0, 0, 0)
		end)
		fx(addEmitterAnchor(rig, riftPiece, Vector3.zero, Vector3.new(2, 2, 0.3)), "sparks", Color3.fromRGB(200, 120, 255))
		orbit(rig, CFrame.new(0, 0.25, 0.55), 3, 2.6, 0.9, V, function() return shard(rgb(40, 10, 70), glow(190, 90, 255)) end, 1.2, 0.1)
	elseif look == "celestial" then
		-- a golden halo, feathers of light circling
		spinRing(rig, CFrame.new(0, 2.25, -0.35) * CFrame.Angles(math.rad(14), 0, 0), 4, glow(255, 225, 130), 0.8, V)
		orbit(rig, CFrame.new(0, 0.6, 0.2), 6, 2.8, 0.6, V, function()
			local g = Kit.group()
			Kit.sprite(g, { ".#", "##", "##", "#." }, { ["#"] = glow(255, 235, 170) }, 1, 0, 0, -2)
			return g
		end, 0.25, 0.3)
	elseif look == "eclipse" then
		-- a great eclipse with a turning corona; a sun and a moon circling
		local disc = Kit.group()
		Kit.disc(disc, 6, 1, function(_, _, d)
			if d > 5.1 then return glow(255, 150, 90) end
			return rgb(8, 4, 12)
		end)
		addPiece(rig, { disc }, V, CFrame.new(0, 1, 0.45))
		corona(rig, CFrame.new(0, 1, 0.5), 16, 7, 5, glow(255, 200, 110), 0.35, V)
		local orb = orbit(rig, CFrame.new(0, 1, 0.45), 2, 3.4, 0.5, V, function(i)
			return if i == 1 then ball(1.6, glow(255, 210, 90)) else ball(1.4, glow(220, 225, 255))
		end, 1.35, 0)
		addLight(rig, orb[1], Vector3.zero, Color3.fromRGB(255, 190, 90), 12, 1.6)
	elseif look == "cosmic" then
		-- a turning galaxy behind, planets circling, the wings full of stars
		local gal = Kit.group()
		for arm = 0, 1 do
			for k = 0, 26 do
				local a = k * 0.32 + arm * math.pi
				local r = 1 + k * 0.32
				local paint = if k % 4 == 0 then glow(255, 255, 255) elseif arm == 0 then glow(170, 120, 255) else glow(255, 120, 220)
				Kit.set(gal, math.floor(math.cos(a) * r + 0.5), math.floor(math.sin(a) * r + 0.5), 0, paint.color, true)
			end
		end
		Kit.set(gal, 0, 0, 0, Color3.new(1, 1, 1), true)
		addPiece(rig, { gal }, V, CFrame.new(0, 0.8, 0.5), function(t: number): CFrame
			return CFrame.Angles(0, 0, t * 0.5)
		end)
		orbit(rig, CFrame.new(0, 0.6, 0.3), 3, 3.2, 0.4, V, function(i)
			local colors = { glow(120, 200, 255), glow(255, 160, 80), glow(200, 120, 255) }
			local g = ball(if i == 2 then 1.6 else 1.1, colors[i])
			if i == 2 then
				Kit.lathe(g, { { 0, 3, 2.2 } }, function() return rgb(230, 210, 255) end) -- a ringed planet
			end
			return g
		end, 0.35, 0.2)
	elseif spec.extra == "moon" then
		-- a crescent moon floating over the back
		local g = Kit.group()
		Kit.sprite(g, { ".##..", "##...", "#....", "##...", ".##.." }, { ["#"] = glow(235, 240, 255) }, 1, 0, 2, -2)
		addPiece(rig, { g }, VOX_WING, CFrame.new(0, 1.3, 0.3), function(t: number): CFrame
			return CFrame.new(0, math.sin(t * 1.5) * 0.08, 0)
		end)
	end
	return rig
end

-- ─── Mounts ────────────────────────────────────────────────────────────────
-- A four-legged (or two-legged) beast, in bricks: forward is -Z, the ground y = 0.
type Quad = {
	L: number, H: number, W: number, legLen: number, legT: number?, legs: number?,
	headL: number, headH: number, headW: number, snoutL: number, neckUp: number,
	ears: string?, horns: string?, tailLen: number, tailUp: number?, tailT: number?,
	main: Paint, belly: Paint?, dark: Paint, eye: Paint, hornC: Paint?, mane: Paint?, saddle: boolean?,
	pattern: ((x: number, y: number, z: number) -> Paint?)?, -- override the body's bricks (or leave holes: { color = nil })
	wings: string?, wingScale: number?, fx: { { any } }?, gait: number?, armor: Paint?, extra: string?, spikes: Paint?,
	glowC: Color3?,                                   -- Epic+: the colour of its trails, rings and light
	showy: ((rig: Rig, ctx: any) -> ())?,             -- Epic+: its own set-piece
}

local SADDLE, CLOTH = rgb(110, 60, 30), rgb(150, 30, 35)

local function buildQuad(look: string, q: Quad): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local V = VOX_MOUNT * RideData.ScaleOf(look)
	local tier = tierOf("mount", look)
	local legPieces: { Piece } = {}
	local hw = math.floor(q.W / 2)
	local x0, x1 = -hw, q.W - 1 - hw
	local zF, zB = -math.floor(q.L / 2), q.L - 1 - math.floor(q.L / 2)
	local y0, y1 = q.legLen, q.legLen + q.H - 1
	local gait = q.gait or 7

	-- Body
	local body = Kit.group()
	for x = x0, x1 do
		for y = y0, y1 do
			for z = zF, zB do
				local p: Paint? = if y == y0 and q.belly then q.belly else q.main
				if q.armor and y >= y1 - 1 and math.abs(x) < hw then p = q.armor end
				if q.pattern then
					local o = q.pattern(x, y, z)
					if o then p = o end
				end
				if p and p.color then Kit.set(body, x, y, z, p.color, p.neon, p.alpha) end
			end
		end
	end
	if q.saddle then
		for x = x0, x1 do
			for z = -1, 1 do Kit.set(body, x, y1 + 1, z, SADDLE.color) end
		end
		for y = y1 - 2, y1 do
			Kit.set(body, x0 - 1, y, 0, CLOTH.color)
			Kit.set(body, x1 + 1, y, 0, CLOTH.color)
		end
	end
	if q.spikes then
		for z = zF + 1, zB, 2 do Kit.set(body, 0, y1 + 1, z, q.spikes.color, q.spikes.neon) end
	end
	local bodyPiece = addPiece(rig, { body }, V, CFrame.new(), function(t: number, move: number): CFrame
		return CFrame.new(0, math.sin(t * gait * 2) * 0.05 * move + math.sin(t * 1.4) * 0.03, 0)
	end)

	-- Head (hinged at the neck)
	local head = Kit.group()
	local nw = math.max(0, math.floor(q.headW / 2) - 1)
	for x = -nw, nw do
		for y = -1, q.neckUp do
			for z = -2, 0 do Kit.set(head, x, y, z, q.main.color, q.main.neon, q.main.alpha) end
		end
	end
	local hh = math.floor(q.headW / 2)
	local hy0 = q.neckUp - 1
	local hy1 = hy0 + q.headH - 1
	local hz0, hz1 = -(1 + q.headL), -2
	for x = -hh, q.headW - 1 - hh do
		for y = hy0, hy1 do
			for z = hz0, hz1 do Kit.set(head, x, y, z, q.main.color, q.main.neon, q.main.alpha) end
		end
	end
	local sw = math.max(0, hh - 1)
	for x = -sw, sw do
		for y = hy0, hy0 + math.max(1, q.headH - 2) do
			for z = hz0 - q.snoutL, hz0 - 1 do Kit.set(head, x, y, z, q.main.color, q.main.neon, q.main.alpha) end
		end
	end
	Kit.set(head, 0, hy0 + math.max(1, q.headH - 2), hz0 - q.snoutL, q.dark.color) -- nose
	for _, ex in ipairs({ -hh, q.headW - 1 - hh }) do
		Kit.set(head, ex, hy1 - 1, hz0 + 1, q.eye.color, true)
	end
	if q.ears == "point" then
		for _, ex in ipairs({ -hh, q.headW - 1 - hh }) do
			Kit.set(head, ex, hy1 + 1, hz1, q.main.color)
			Kit.set(head, ex, hy1 + 2, hz1, q.dark.color)
		end
	elseif q.ears == "round" then
		for _, ex in ipairs({ -hh, q.headW - 1 - hh }) do Kit.set(head, ex, hy1 + 1, hz1, q.main.color) end
	end
	local hc = q.hornC or rgb(235, 225, 200)
	if q.horns == "tusk" then
		for _, ex in ipairs({ -sw - 1, sw + 1 }) do
			Kit.set(head, ex, hy0, hz0 - q.snoutL + 1, hc.color)
			Kit.set(head, ex, hy0 + 1, hz0 - q.snoutL, hc.color)
		end
	elseif q.horns == "curl" then
		for _, side in ipairs({ -1, 1 }) do
			local bx = side * (hh + 1)
			for _, o in ipairs({ { 0, 1, 0 }, { 0, 2, 1 }, { 0, 2, 2 }, { 0, 1, 3 }, { 0, 0, 2 }, { 0, -1, 1 } }) do
				Kit.set(head, bx + side * o[1], hy1 + o[2] - 1, hz1 - 1 + o[3] - 1, hc.color, hc.neon)
			end
		end
	elseif q.horns == "dragon" then
		for _, side in ipairs({ -1, 1 }) do
			for i = 0, 3 do Kit.set(head, side * hh, hy1 + 1 + math.floor(i / 2), hz1 + i, hc.color, hc.neon) end
		end
	elseif q.horns == "antler" then
		for _, side in ipairs({ -1, 1 }) do
			local bx = side * hh
			for i = 0, 4 do Kit.set(head, bx + side * math.floor(i / 2), hy1 + 1 + i, hz1 - 1, hc.color, true) end
			Kit.set(head, bx + side * 2, hy1 + 4, hz1 - 2, hc.color, true)
			Kit.set(head, bx, hy1 + 3, hz1 - 2, hc.color, true)
			Kit.set(head, bx + side * 3, hy1 + 6, hz1 - 1, hc.color, true)
		end
	end
	if q.mane then
		for y = 0, q.neckUp + 1 do Kit.set(head, 0, y, 1, q.mane.color, q.mane.neon) end
		for z = hz1 - 1, 1 do Kit.set(head, 0, hy1 + 1, z, q.mane.color, q.mane.neon) end
	end
	if q.extra == "lion_mane" then
		for x = -hh - 1, q.headW - hh do
			for y = hy0 - 1, hy1 + 1 do Kit.set(head, x, y, hz1 + 1, q.mane and q.mane.color or rgb(200, 120, 40).color) end
		end
	end
	local headPiece = addPiece(rig, { head }, V, CFrame.new(0, (y1 - 1) * V, zF * V), function(t: number, move: number): CFrame
		return CFrame.Angles(math.sin(t * gait * 2 + 0.6) * 0.06 * move + math.sin(t * 1.1) * 0.04, math.sin(t * 0.7) * 0.08, 0)
	end)

	-- Legs (hinged at the hips)
	local lt = q.legT or 2
	local lx = hw - math.floor(lt / 2)
	local legSpots = {}
	if (q.legs or 4) == 4 then
		legSpots = { { -lx, zF + 1, 0 }, { lx, zF + 1, math.pi }, { -lx, zB - 1, math.pi }, { lx, zB - 1, 0 } }
	else
		legSpots = { { -lx, zB - 2, 0 }, { lx, zB - 2, math.pi } }
	end
	for _, spot in ipairs(legSpots) do
		local leg = Kit.group()
		for x = 0, lt - 1 do
			for y = -q.legLen, -1 do
				for z = 0, lt - 1 do
					local p = if y == -q.legLen then q.dark else q.main
					Kit.set(leg, x - math.floor(lt / 2), y, z - math.floor(lt / 2), p.color, p.neon, p.alpha)
				end
			end
		end
		local phase = spot[3]
		legPieces[#legPieces + 1] = addPiece(rig, { leg }, V, CFrame.new(spot[1] * V, q.legLen * V, spot[2] * V), function(t: number, move: number): CFrame
			return CFrame.Angles(math.sin(t * gait + phase) * 0.55 * math.min(move, 1.2), 0, 0)
		end)
	end

	-- Tail (hinged at the rump)
	local tail = Kit.group()
	local tt = q.tailT or 1
	for i = 0, q.tailLen - 1 do
		local y = math.floor(i * (q.tailUp or 0.3))
		for x = 0, tt - 1 do
			for dy = 0, tt - 1 do
				Kit.set(tail, x - math.floor(tt / 2), y + dy, i, q.main.color, q.main.neon, q.main.alpha)
			end
		end
		if q.spikes and i % 2 == 1 then Kit.set(tail, 0, y + tt, i, q.spikes.color, q.spikes.neon) end
	end
	if q.mane and q.tailLen > 0 then
		Kit.set(tail, 0, math.floor((q.tailLen - 1) * (q.tailUp or 0.3)) - 1, q.tailLen - 1, q.mane.color, q.mane.neon)
	end
	local tailPiece = addPiece(rig, { tail }, V, CFrame.new(0, (y1 - 1) * V, (zB + 1) * V), function(t: number, move: number): CFrame
		return CFrame.Angles(math.sin(t * 2.2) * 0.08, math.sin(t * (2 + move * 3)) * 0.35, 0)
	end)
	local glowC = q.glowC or q.eye.color

	-- Wings
	if q.wings then
		local ws = WINGS[q.wings]
		local infos = addWings(rig, ws, V * (q.wingScale or 1), Vector3.new(0, (y1 + 1) * V, -1 * V), 18, 2.4, 22)
		if tier >= 3 then
			for _, wi in ipairs(infos) do addTrail(rig, wi.piece, wi.tip, 0.5 * V / VOX_MOUNT, glowC, 0.7) end
		end
	end

	-- Epic and up: glowing eyes that light the way, a trail off the tail,
	-- turning rune rings underfoot; Legendary+ trail light off every foot.
	local ctx = { V = V, y0 = y0, y1 = y1, zF = zF, zB = zB, W = q.W, H = q.H, L = q.L, tier = tier, glow = glowC,
		head = headPiece, body = bodyPiece, tail = tailPiece, legs = legPieces,
		snout = Vector3.new(0, (hy0 + 1) * V, (hz0 - q.snoutL) * V), headTop = Vector3.new(0, (hy1 + 2) * V, (hz1 - 1) * V),
		tailTip = Vector3.new(0, math.floor((q.tailLen - 1) * (q.tailUp or 0.3)) * V, (q.tailLen - 1) * V),
		foot = Vector3.new(0, -q.legLen * V, 0) }
	if tier >= 3 then
		addLight(rig, headPiece, ctx.snout, q.eye.color, 12, 1.6)
		if q.tailLen > 1 then addTrail(rig, tailPiece, ctx.tailTip, 0.45 * V / VOX_MOUNT, glowC, 0.6) end
		local r = math.max(q.W, math.floor(q.L * 0.55)) + 2
		spinRing(rig, CFrame.new(0, 0.12, 0), r, { color = glowC, neon = true }, 0.6, V, tier == 3)
		if tier >= 4 then
			spinRing(rig, CFrame.new(0, 0.14, 0), r - 2, { color = glowC:Lerp(Color3.new(1, 1, 1), 0.4), neon = true }, -0.9, V, true)
			for _, lp in ipairs(legPieces) do addTrail(rig, lp, ctx.foot, 0.35 * V / VOX_MOUNT, glowC, 0.4) end
		end
		if q.showy then q.showy(rig, ctx) end
	end
	-- Effects
	for _, f in ipairs(q.fx or {}) do
		local where = f[2] :: string
		local piece = if where == "head" then headPiece else bodyPiece
		local at = if where == "head" then Vector3.new(0, (hy0 + 1) * V, (hz0 - 1) * V)
			elseif where == "feet" then Vector3.new(0, 0.3, 0)
			else Vector3.new(0, (y0 + q.H / 2) * V, 0)
		local size = if where == "feet" then Vector3.new(q.W * V, 0.2, q.L * V) else Vector3.new(q.W * V, q.H * V, q.L * V)
		fx(addEmitterAnchor(rig, piece, at, size), f[1], f[3] or Color3.new(1, 1, 1))
	end
	if q.extra == "eclipse" then
		local g = Kit.group()
		Kit.disc(g, 7, 1, function(_, _, d)
			if d > 6.1 then return glow(255, 200, 80) end
			return rgb(8, 4, 12)
		end)
		local eh = CFrame.new(0, (y1 + 13) * V, (zB - 1) * V)
		addPiece(rig, { g }, V, eh, function(t: number): CFrame
			return CFrame.new(0, math.sin(t * 1.2) * 0.15, 0)
		end)
		corona(rig, eh * CFrame.new(0, 0, 0.05), 18, 8, 6, glow(255, 210, 120), 0.3, V)
	end
	return rig
end

-- Eight (or six) jointed legs splayed round a body: spiders and scorpions.
local function addCrawlerLegs(rig: Rig, pairsN: number, hipY: number, zs: { number }, reach: number, drop: number, color: Paint, dark: Paint, scale: number?)
	local VOX_MOUNT = scale or VOX_MOUNT
	for i = 1, pairsN do
		for _, side in ipairs({ -1, 1 }) do
			local g = Kit.group()
			for k = 0, reach do
				local y = math.floor(k * 0.6)
				Kit.set(g, side * k, y, 0, color.color)
			end
			for k = 0, drop do
				Kit.set(g, side * (reach + 1 + math.floor(k / 3)), math.floor(reach * 0.6) - k, 0, if k == drop then dark.color else color.color)
			end
			local phase = (i + (if side == 1 then 0.5 else 0)) * math.pi
			addPiece(rig, { g }, VOX_MOUNT, CFrame.new(side * 2 * VOX_MOUNT, hipY * VOX_MOUNT, zs[i] * VOX_MOUNT), function(t: number, move: number): CFrame
				local m = 0.15 + move * 0.5
				return CFrame.Angles(0, math.sin(t * 9 + phase) * 0.35 * m, side * math.max(0, math.sin(t * 9 + phase)) * 0.25 * m)
			end)
		end
	end
end

local function buildSpider(look: string): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local g = Kit.group()
	Kit.sphere(g, 3.4, function(x, y, z)
		if (x + z) % 4 == 0 and y > 1 then return rgb(140, 60, 140) end
		return rgb(70, 30, 75)
	end)
	local front = Kit.group()
	Kit.sphere(front, 2.2, function() return rgb(55, 25, 60) end)
	for _, e in ipairs({ { -1, 1 }, { 1, 1 }, { -1, 0 }, { 1, 0 } }) do Kit.set(front, e[1], e[2], -2, Color3.fromRGB(255, 40, 40), true) end
	local bodyPiece = addPiece(rig, { g }, VOX_MOUNT, CFrame.new(0, 6 * VOX_MOUNT, 2.4 * VOX_MOUNT), function(t: number, move: number): CFrame
		return CFrame.new(0, math.sin(t * 9) * 0.04 * move + math.sin(t * 1.6) * 0.04, 0)
	end)
	addPiece(rig, { front }, VOX_MOUNT, CFrame.new(0, 5.5 * VOX_MOUNT, -3 * VOX_MOUNT))
	addCrawlerLegs(rig, 4, 5, { -3, -1.5, 0, 1.5 }, 4, 6, rgb(60, 25, 65), rgb(30, 10, 35))
	fx(addEmitterAnchor(rig, bodyPiece, Vector3.zero, Vector3.one * 2), "smoke", Color3.fromRGB(120, 40, 140))
	return rig
end

local function buildScorpion(look: string): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local V = VOX_MOUNT * RideData.ScaleOf(look)
	local main, dark, venom = rgb(45, 90, 35), rgb(25, 45, 20), glow(150, 255, 60)
	local body = Kit.group()
	Kit.box(body, -2, 3, -4, 2, 5, 4, main)
	for z = -4, 4, 2 do Kit.set(body, 0, 6, z, venom.color, true) end
	local bodyPiece = addPiece(rig, { body }, V, CFrame.new(), function(t: number, move: number): CFrame
		return CFrame.new(0, math.sin(t * 9) * 0.03 * move, 0)
	end)
	-- claws
	for _, side in ipairs({ -1, 1 }) do
		local claw = Kit.group()
		for k = 0, 3 do Kit.set(claw, side * math.floor(k / 2), 0, -k, main.color) end
		Kit.box(claw, math.min(side, side * 2), 0, -6, math.max(side, side * 2), 1, -4, { color = main.color })
		Kit.set(claw, side * 1, 1, -7, dark.color)
		addPiece(rig, { claw }, V, CFrame.new(side * 2 * V, 4 * V, -4 * V), function(t: number): CFrame
			return CFrame.Angles(0, side * math.sin(t * 2 + side) * 0.15, 0)
		end)
	end
	-- the tail arcing up over the back, the sting glowing
	local tail = Kit.group()
	for i = 0, 10 do
		local a = i / 10 * math.pi * 0.95
		local z = math.floor(math.sin(a) * 5 + 0.5)
		local y = math.floor((1 - math.cos(a)) * 5 + 0.5)
		Kit.set(tail, 0, y, z, (if i == 10 then venom else main).color, i == 10)
		Kit.set(tail, 0, y + 1, z, main.color)
	end
	Kit.set(tail, 0, 9, -1, venom.color, true)
	local tailPiece = addPiece(rig, { tail }, V, CFrame.new(0, 5 * V, 4 * V), function(t: number): CFrame
		return CFrame.Angles(math.sin(t * 1.8) * 0.12, math.sin(t * 1.1) * 0.1, 0)
	end)
	fx(addEmitterAnchor(rig, tailPiece, Vector3.new(0, 9 * V, -1 * V), Vector3.one * 0.3), "drip", Color3.fromRGB(150, 255, 60))
	addCrawlerLegs(rig, 3, 4, { -2, 0, 2 }, 3, 4, main, dark, V)
	-- Epic: the sting trails venom light; spores circle; a toxic ring turns below
	addTrail(rig, tailPiece, Vector3.new(0, 9 * V, -1 * V), 0.6, Color3.fromRGB(150, 255, 60), 0.7)
	addLight(rig, tailPiece, Vector3.new(0, 9 * V, -1 * V), Color3.fromRGB(150, 255, 60), 12, 1.8)
	orbit(rig, CFrame.new(0, 7 * V, 0), 4, 4 * V, 1.1, V, function() return ball(1, glow(150, 255, 60)) end, 0.15, 0.3)
	spinRing(rig, CFrame.new(0, 0.12, 0), 7, glow(150, 255, 60), 0.7, V, true)
	fx(addEmitterAnchor(rig, bodyPiece, Vector3.new(0, 0.3, 0), Vector3.new(4 * V, 0.2, 6 * V)), "smoke", Color3.fromRGB(90, 200, 40))
	fx(addEmitterAnchor(rig, bodyPiece, Vector3.new(0, 1.6, 0), Vector3.new(2, 1, 3)), "stars", Color3.fromRGB(150, 255, 60))
	return rig
end

-- The Void Serpent: an eastern dragon. You sit on its neck behind the horned
-- head; its long body twirls in a living spiral behind you, clawed legs
-- grasping, glowing fins along its spine, its tail fin trailing light.
local function buildSerpent(look: string): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local V = VOX_MOUNT * RideData.ScaleOf(look)
	local BODY, BELLY, FIN = rgb(70, 25, 130), rgb(150, 110, 210), glow(200, 110, 255)
	local GOLD, EYE = glow(255, 215, 110), glow(255, 240, 150)
	local seatY = math.floor(RideData.BackHeight(look) / V + 0.5) -- (bricks: the neck sits at the back's height)

	-- the neck under the rider
	local neck = Kit.group()
	Kit.box(neck, -2, -3, -2, 2, -1, 2, BODY)
	for z = -2, 2 do Kit.set(neck, 0, 0, z, FIN.color, true) end
	Kit.box(neck, -2, -4, -2, 2, -4, 2, BELLY)
	local neckPiece = addPiece(rig, { neck }, V, CFrame.new(0, seatY * V, 0), function(t: number, move: number): CFrame
		return CFrame.new(0, math.sin(t * 1.6) * 0.12, 0) * CFrame.Angles(0, 0, math.sin(t * 1.1) * 0.04)
	end)

	-- the head, out in front
	local head = Kit.group()
	Kit.box(head, -2, -2, -4, 2, 1, 0, BODY)          -- skull
	Kit.box(head, -1, -2, -8, 1, 0, -5, BODY)         -- snout
	Kit.box(head, -1, -3, -7, 1, -3, -3, BELLY)       -- jaw
	Kit.set(head, -1, 0, -8, Color3.fromRGB(20, 0, 30)); Kit.set(head, 1, 0, -8, Color3.fromRGB(20, 0, 30)) -- nostrils
	for _, side in ipairs({ -1, 1 }) do
		Kit.set(head, side * 2, 0, -3, EYE.color, true)
		-- golden horns sweeping back
		for i = 0, 5 do Kit.set(head, side * (1 + math.floor(i / 3)), 2 + math.floor(i * 0.6), -1 + i, GOLD.color, true) end
		-- long glowing whiskers drooping from the snout
		for i = 0, 6 do Kit.set(head, side * (2 + math.floor(i / 2)), -1 - math.floor(i / 3), -7 + i, FIN.color, true) end
		-- the mane
		for z = -3, 0 do Kit.set(head, side * 2, 1, z, FIN.color, true) end
	end
	for z = -4, 0 do Kit.set(head, 0, 2, z, FIN.color, true) end
	local headPiece = addPiece(rig, { head }, V, CFrame.new(0, (seatY - 1) * V, -2.5 * V), function(t: number, move: number): CFrame
		return CFrame.new(0, math.sin(t * 1.6 + 0.4) * 0.15, 0) * CFrame.Angles(math.sin(t * 1.2) * 0.08, math.sin(t * 0.7) * 0.15, 0)
	end)
	addLight(rig, headPiece, Vector3.new(0, 0, -4 * V), Color3.fromRGB(200, 120, 255), 16, 2)
	fx(addEmitterAnchor(rig, headPiece, Vector3.new(0, -1 * V, -8 * V), Vector3.one * 0.6), "smoke", Color3.fromRGB(170, 70, 255))
	breath(rig, CFrame.new(0, (seatY - 2) * V, -11 * V), Color3.fromRGB(170, 60, 255), 5, 1.2, 1.2)

	-- the body: segments spiralling behind
	local N = 16
	local spacing = 3.1 * V
	local function at(i: number, t: number, move: number): Vector3
		local back = i * spacing
		local r = 3.6 * V * math.min(1, i / 4)                     -- (calm under the rider, coiling further back)
		local phi = t * (2 + move * 1.6) - i * 0.55
		local sway = math.sin(t * 0.8 + i * 0.25) * 0.8 * V
		return Vector3.new(math.cos(phi) * r + sway, (seatY - 2) * V + math.sin(phi) * r - i * 0.12 * V, back)
	end
	for i = 1, N do
		local k = i
		local size = math.max(1, math.floor(2.4 - i * 0.09))
		local g = Kit.group()
		Kit.box(g, -size, -size, -1, size, size, 1, BODY)
		for x = -size, size do Kit.set(g, x, -size, 0, BELLY.color) end
		-- a glowing fin along the spine
		Kit.set(g, 0, size + 1, 0, FIN.color, true)
		if i % 2 == 0 then Kit.set(g, 0, size + 2, 1, FIN.color, true) end
		-- clawed legs on two segments
		if i == 3 or i == 9 then
			for _, side in ipairs({ -1, 1 }) do
				for d = 0, 3 do Kit.set(g, side * (size + 1 + math.floor(d / 2)), -size - d, -1, BODY.color) end
				Kit.set(g, side * (size + 3), -size - 4, -2, GOLD.color, true)
				Kit.set(g, side * (size + 2), -size - 4, -2, GOLD.color, true)
			end
		end
		-- the tail fin
		if i == N then
			for y = -3, 3 do
				for z = 1, 3 - math.floor(math.abs(y) / 2) do Kit.set(g, 0, y, z, FIN.color, true) end
			end
		end
		local piece = addPiece(rig, { g }, V, CFrame.new(), function(t: number, move: number): CFrame
			local p = at(k, t, move)
			local prev = if k == 1 then Vector3.new(0, (seatY - 2) * V, 0) else at(k - 1, t, move)
			return CFrame.lookAt(p, prev)
		end)
		if i % 4 == 0 then fx(addEmitterAnchor(rig, piece, Vector3.zero, Vector3.one * (size * V)), "smoke", Color3.fromRGB(150, 60, 255)) end
		if i % 5 == 0 then fx(addEmitterAnchor(rig, piece, Vector3.zero, Vector3.one * (size * V)), "sparks", Color3.fromRGB(210, 150, 255)) end
		if i == N then addTrail(rig, piece, Vector3.new(0, 0, 2 * V), 1.4 * V / VOX_MOUNT, Color3.fromRGB(190, 90, 255), 0.9) end
		if i == math.floor(N / 2) then addLight(rig, piece, Vector3.zero, Color3.fromRGB(170, 70, 255), 14, 1.4) end
	end
	-- void runes circling, rune rings below
	orbit(rig, CFrame.new(0, seatY * V, 2 * V), 5, 5 * V, 0.6, V, function() return shard(rgb(40, 10, 70), glow(220, 150, 255)) end, 0.3, 0.4)
	spinRing(rig, CFrame.new(0, 0.12, 2 * V), 9, glow(190, 90, 255), 0.5, V)
	spinRing(rig, CFrame.new(0, 0.14, 2 * V), 6, glow(240, 200, 255), -0.8, V, true)
	return rig
end

-- ─── Floating platforms (sat on, not straddled: RideData.Flat) ───────────────
-- They hover with nothing under them, bob, and lean into the way you go.
local function hover(t: number, move: number, phase: number?): CFrame
	local p = phase or 0
	return CFrame.new(0, math.sin(t * 1.5 + p) * 0.14, 0) * CFrame.Angles(-0.06 * math.min(move, 1), 0, math.sin(t * 0.9 + p) * 0.03)
end

-- The Magician's Carpet: black, gold-fringed, a red frame and a white sash;
-- it ripples like cloth (still under the rider, fluttering at the ends),
-- a top hat rides on the back of it and playing cards circle round.
local function buildCarpet(look: string): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local V = VOX_MOUNT * RideData.ScaleOf(look)
	local GOLD, BLACK, RED, WHITE = rgb(255, 200, 45), rgb(25, 22, 32), rgb(175, 25, 40), rgb(235, 235, 242)
	local GEM = glow(90, 170, 255)
	local yTop = RideData.BackHeight(look) - 0.5 * V
	local HX, HZ = 6, 9
	local function paint(x: number, z: number): Paint
		local e = math.min(HX - math.abs(x), HZ - math.abs(z))
		if e == 0 then return GOLD end
		if e == 1 then return if (x + z) % 2 == 0 then GOLD else BLACK end
		if e == 3 then return RED end
		if e > 3 and math.abs(x + z * 0.6) < 1.3 then return WHITE end
		return BLACK
	end
	-- (the cloth waves more the further from the middle)
	local function wave(zc: number, t: number, move: number): CFrame
		local ph = t * (3 + move * 3) + zc * 0.35
		local amp = (0.03 + 0.09 * math.abs(zc) / HZ) * (0.6 + math.min(move, 1.2) * 0.6)
		return hover(t, move) * CFrame.new(0, math.sin(ph) * amp, 0) * CFrame.Angles(math.cos(ph) * amp * 0.35, 0, 0)
	end
	local strips = { { -9, -7 }, { -6, -4 }, { -3, 3 }, { 4, 6 }, { 7, 9 } }
	local rear: Piece? = nil
	for si, s in ipairs(strips) do
		local zc = (s[1] + s[2]) / 2
		local g = Kit.group()
		for x = -HX, HX do
			for z = s[1], s[2] do
				local p = paint(x, z)
				Kit.set(g, x, 0, z - zc, p.color, p.neon)
			end
		end
		-- gold tassels with blue gems hanging from the corners
		if si == 1 or si == #strips then
			local zEnd = (if si == 1 then s[1] else s[2]) - zc
			for _, x in ipairs({ -HX, HX }) do
				Kit.set(g, x, -1, zEnd, GOLD.color)
				Kit.set(g, x, -2, zEnd, GEM.color, true)
			end
		end
		local piece = addPiece(rig, { g }, V, CFrame.new(0, yTop, zc * V), function(t: number, move: number): CFrame
			return wave(zc, t, move)
		end)
		if si == #strips then rear = piece end
		if si == 3 then
			fx(addEmitterAnchor(rig, piece, Vector3.new(0, -0.6, 0), Vector3.new(HX * 2 * V, 0.2, 7 * V)), "stars", Color3.fromRGB(255, 210, 90))
			addLight(rig, piece, Vector3.new(0, -1, 0), Color3.fromRGB(255, 200, 110), 14, 1.4)
		end
	end
	-- the top hat, on the back corner: it hops and tips now and then
	local hat = Kit.group()
	Kit.lathe(hat, { { 0, 3, 0 } }, function() return BLACK end)
	Kit.lathe(hat, { { 1, 2, 0 } }, function() return RED end)
	Kit.lathe(hat, { { 2, 2, 0 }, { 3, 2, 0 }, { 4, 2, 0 }, { 5, 2, 0 } }, function() return BLACK end)
	local hatZ = 6
	local hatPiece = addPiece(rig, { hat }, V, CFrame.new(3 * V, yTop + 0.5 * V, hatZ * V), function(t: number, move: number): CFrame
		local k = t % 4
		local hop = if k < 0.5 then math.sin(k / 0.5 * math.pi) * 0.7 else 0
		return wave(hatZ, t, move) * CFrame.new(0, hop, 0) * CFrame.Angles(0, t * 0.4, if k < 0.5 then math.sin(k / 0.5 * math.pi) * 0.3 else 0)
	end)
	fx(addEmitterAnchor(rig, hatPiece, Vector3.new(0, 6 * V, 0), Vector3.new(1.5 * V, 0.2, 1.5 * V)), "stars", Color3.fromRGB(255, 230, 140))
	fx(addEmitterAnchor(rig, hatPiece, Vector3.new(0, 6 * V, 0), Vector3.new(1.2 * V, 0.2, 1.2 * V)), "embers", Color3.fromRGB(255, 120, 200))
	-- playing cards circling the rider
	orbit(rig, CFrame.new(0, yTop + 3.2, 0), 4, 9 * V, 0.9, V, function(i: number)
		local c = Kit.group()
		Kit.box(c, -1, -1, 0, 1, 2, 0, WHITE)
		Kit.set(c, 0, 1, 0, (if i % 2 == 0 then RED else BLACK).color, i % 2 == 0)
		Kit.set(c, 0, 0, 0, (if i % 2 == 0 then RED else BLACK).color, i % 2 == 0)
		return c
	end, 0.2, 0.5)
	-- Epic: gold ribbons off the back corners, a gold ring turning below
	if rear then
		for _, x in ipairs({ -HX, HX }) do addTrail(rig, rear, Vector3.new(x * V, 0, 2 * V), 0.5, Color3.fromRGB(255, 200, 60), 0.6) end
	end
	spinRing(rig, CFrame.new(0, 0.12, 0), 11, glow(255, 200, 60), 0.6, V, true)
	return rig
end

-- The Wishing Star: a fat golden star fallen from the wish sky. It turns
-- slowly under you, shedding sparkles, a rainbow streaming off it as you go.
local function buildStar(look: string): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local V = VOX_MOUNT * RideData.ScaleOf(look)
	local R, r = 9.5, 4.2
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
			local a, b = verts[i], verts[j]
			if (a.Y > z) ~= (b.Y > z) and x < (b.X - a.X) * (z - a.Y) / (b.Y - a.Y) + a.X then c = not c end
			j = i
		end
		return c
	end
	local g = Kit.group()
	local n = math.ceil(R)
	for x = -n, n do
		for z = -n, n do
			if not inside(x, z) then continue end
			local edge = not (inside(x + 1, z) and inside(x - 1, z) and inside(x, z + 1) and inside(x, z - 1))
			local f = 1 - math.sqrt(x * x + z * z) / R
			local yb, yt = -math.floor(f * 1.8), math.floor(f * 2.6)
			for y = yb, yt do
				local p = if edge then glow(255, 205, 40)
					elseif y == yt then rgb(255, 245, 150)
					elseif y == yb then rgb(235, 170, 20)
					else rgb(255, 222, 60)
				Kit.set(g, x, y, z, p.color, p.neon)
			end
		end
	end
	local top = 2.5 -- (the top face in the middle, bricks)
	local home = CFrame.new(0, RideData.BackHeight(look) - top * V, 0)
	local starPiece = addPiece(rig, { g }, V, home, function(t: number, move: number): CFrame
		return hover(t, move) * CFrame.Angles(0, t * 0.45, 0)
	end)
	addLight(rig, starPiece, Vector3.zero, Color3.fromRGB(255, 220, 110), 20, 2.2)
	fx(addEmitterAnchor(rig, starPiece, Vector3.zero, Vector3.new(12 * V, 1, 12 * V)), "stars", Color3.fromRGB(255, 235, 140))
	fx(addEmitterAnchor(rig, starPiece, Vector3.new(0, -1.5 * V, 0), Vector3.new(6 * V, 0.2, 6 * V)), "drip", Color3.fromRGB(255, 220, 90))
	-- the rainbow, streaming from behind
	local tail = addAnchorPiece(rig, home, function(t: number, move: number): CFrame return hover(t, move) end)
	local BOW = { { 255, 80, 90 }, { 255, 160, 60 }, { 255, 235, 90 }, { 110, 230, 120 }, { 90, 170, 255 }, { 180, 110, 255 } }
	for i, c in ipairs(BOW) do
		addTrail(rig, tail, Vector3.new((i - 3.5) * 0.55, 0, 6 * V), 0.6, Color3.fromRGB(c[1], c[2], c[3]), 1.1)
	end
	-- little stars circling, a halo of rays and two rings turning below
	orbit(rig, home * CFrame.new(0, 4.5 * V, 0), 5, 12 * V, 0.7, V, function()
		local s = Kit.group()
		for _, o in ipairs({ { 0, 0 }, { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do Kit.set(s, o[1], o[2], 0, Color3.fromRGB(255, 240, 140), true) end
		return s
	end, 0.25, 0.6)
	corona(rig, home * CFrame.new(0, -1.2 * V, 0) * CFrame.Angles(math.pi / 2, 0, 0), 10, 11, 4, glow(255, 230, 120), 0.35, V)
	spinRing(rig, CFrame.new(0, 0.12, 0), 12, glow(255, 215, 80), 0.5, V)
	spinRing(rig, CFrame.new(0, 0.14, 0), 8, glow(255, 250, 200), -0.9, V, true)
	return rig
end

-- The Void Disc: an obsidian bowl holding a swirling portal, crystals
-- hanging beneath; wisps race round its rim and the void boils up out of it.
local function buildVoidDisc(look: string): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local V = VOX_MOUNT * RideData.ScaleOf(look)
	local ROCK, ROCK2, RIM = rgb(38, 30, 52), rgb(60, 45, 85), glow(200, 140, 255)
	local home = CFrame.new(0, RideData.BackHeight(look) - 0.5 * V, 0)
	-- the bowl, its top the dark face of the portal inside a glowing rim
	local bowl = Kit.group()
	Kit.lathe(bowl, { { 0, 9.2 } }, function(_, _, _, d)
		if d >= 8.4 then return ROCK2 end
		if d >= 7.8 then return RIM end
		if d < 1.3 then return rgb(12, 4, 22) end
		if d < 3.2 then return rgb(55, 16, 100) end
		if d < 5.6 then return rgb(85, 30, 155) end
		return rgb(120, 55, 205)
	end)
	Kit.lathe(bowl, { { -1, 8.6 }, { -2, 6.8 }, { -3, 4.4 } }, function(x, y, z)
		if (x * 7 + z * 3 + y * 5) % 23 == 0 then return glow(150, 70, 230) end
		return if y % 2 == 0 then ROCK else ROCK2
	end)
	-- crystals hanging underneath
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		local x, z = math.floor(math.cos(a) * 5 + 0.5), math.floor(math.sin(a) * 5 + 0.5)
		for d = 0, i % 2 do Kit.set(bowl, math.floor(x * 0.8), -4 - d, math.floor(z * 0.8), Color3.fromRGB(170, 90, 255), true) end
	end
	local bowlPiece = addPiece(rig, { bowl }, V, home, function(t: number, move: number): CFrame return hover(t, move) end)
	-- the swirl: three glowing arms inlaid in the portal, turning
	local swirl = Kit.group()
	for k = 0, 2 do
		for d = 1.6, 7.4, 0.45 do
			local th = k * math.pi * 2 / 3 + d * 0.5
			local x, z = math.floor(math.cos(th) * d + 0.5), math.floor(math.sin(th) * d + 0.5)
			local c = if d > 5.5 then Color3.fromRGB(240, 215, 255) else Color3.fromRGB(185, 105, 255)
			Kit.set(swirl, x, 0, z, c, true)
		end
	end
	local portalPiece = addPiece(rig, { swirl }, V, home * CFrame.new(0, 0.05, 0), function(t: number, move: number): CFrame
		return hover(t, move) * CFrame.Angles(0, -t * 0.9, 0)
	end)
	addLight(rig, portalPiece, Vector3.new(0, 1, 0), Color3.fromRGB(170, 80, 255), 18, 2.2)
	local up = addEmitterAnchor(rig, portalPiece, Vector3.new(0, 0.6, 0), Vector3.new(11 * V, 0.2, 11 * V))
	fx(up, "smoke", Color3.fromRGB(150, 60, 255))
	fx(up, "stars", Color3.fromRGB(210, 150, 255))
	for i = 1, 6 do
		local a = i / 6 * math.pi * 2
		fx(addEmitterAnchor(rig, bowlPiece, Vector3.new(math.cos(a) * 4 * V, -5 * V, math.sin(a) * 4 * V), Vector3.one * 0.2), "drip", Color3.fromRGB(190, 120, 255))
	end
	-- wisps racing round the rim, leaving rings of light
	for k = 0, 2 do
		local w = addAnchorPiece(rig, home, function(t: number, move: number): CFrame
			return hover(t, move) * CFrame.Angles(0, t * 2.4 + k * math.pi * 2 / 3, 0)
		end)
		addTrail(rig, w, Vector3.new(8.6 * V, 0.3, 0), 0.5, Color3.fromRGB(200, 130, 255), 0.5)
	end
	-- void shards circling above, rune rings below
	orbit(rig, home * CFrame.new(0, 5 * V, 0), 5, 11 * V, 0.6, V, function() return shard(rgb(40, 10, 70), glow(220, 150, 255)) end, 0.3, 0.5)
	spinRing(rig, CFrame.new(0, 0.12, 0), 11, glow(170, 80, 255), 0.5, V)
	spinRing(rig, CFrame.new(0, 0.14, 0), 7, glow(230, 190, 255), -0.8, V, true)
	return rig
end

local DIRE = rgb(120, 120, 132)
local MOUNTS: { [string]: () -> Rig } = {
	dire_wolf = function() return buildQuad("dire_wolf", { L = 10, H = 4, W = 4, legLen = 4, headL = 3, headH = 3, headW = 4, snoutL = 2, neckUp = 2,
		ears = "point", tailLen = 5, tailUp = 0.5, tailT = 2, main = DIRE, belly = rgb(170, 170, 178), dark = rgb(50, 50, 55), eye = glow(255, 200, 80), saddle = true }) end,
	war_boar = function() return buildQuad("war_boar", { L = 9, H = 5, W = 5, legLen = 3, headL = 3, headH = 3, headW = 4, snoutL = 2, neckUp = 0,
		ears = "point", horns = "tusk", tailLen = 2, tailUp = 0.5, main = rgb(115, 75, 45), dark = rgb(55, 35, 20), eye = glow(255, 90, 50), saddle = true,
		mane = rgb(60, 40, 25), armor = rgb(110, 110, 120) }) end,
	skeleton_horse = function() return buildQuad("skeleton_horse", { L = 11, H = 5, W = 3, legLen = 5, legT = 1, headL = 4, headH = 2, headW = 3, snoutL = 2, neckUp = 4,
		ears = "point", tailLen = 4, tailUp = -0.4, main = rgb(230, 225, 205), dark = rgb(150, 145, 130), eye = glow(120, 255, 120), mane = glow(120, 255, 120),
		pattern = function(x, y, z) if z % 2 == 0 and y > 5 and y < 9 and x == 0 then return { color = nil :: any } end return nil end,
		fx = { { "fire", "head", Color3.fromRGB(120, 255, 120) } } }) end,
	giant_spider = function() return buildSpider("giant_spider") end,
	frost_wolf = function() return buildQuad("frost_wolf", { L = 10, H = 4, W = 4, legLen = 4, headL = 3, headH = 3, headW = 4, snoutL = 2, neckUp = 2,
		ears = "point", tailLen = 5, tailUp = 0.5, tailT = 2, main = glass(170, 225, 255, 0.2), belly = rgb(235, 248, 255), dark = rgb(120, 170, 220),
		eye = glow(140, 230, 255), mane = glow(210, 245, 255), fx = { { "frost", "body", Color3.fromRGB(180, 235, 255) } } }) end,
	dire_bear = function() return buildQuad("dire_bear", { L = 11, H = 6, W = 6, legLen = 3, legT = 2, headL = 3, headH = 4, headW = 4, snoutL = 1, neckUp = 1,
		ears = "round", tailLen = 1, main = rgb(90, 60, 40), dark = rgb(40, 28, 20), eye = glow(255, 160, 60), armor = rgb(120, 120, 130), saddle = true }) end,
	flame_ram = function() return buildQuad("flame_ram", { L = 9, H = 5, W = 5, legLen = 3, headL = 3, headH = 3, headW = 3, snoutL = 1, neckUp = 1,
		horns = "curl", hornC = rgb(255, 170, 60), tailLen = 1, main = rgb(240, 220, 190), dark = rgb(80, 50, 30), eye = glow(255, 120, 40),
		pattern = function(x, y, z) if (x + y + z) % 3 == 0 then return rgb(255, 245, 225) end return nil end,
		fx = { { "fire", "feet", Color3.fromRGB(255, 120, 30) }, { "embers", "body", Color3.fromRGB(255, 140, 50) } } }) end,
	venom_scorpion = function() return buildScorpion("venom_scorpion") end,
	shadow_panther = function() return buildQuad("shadow_panther", { L = 12, H = 4, W = 4, legLen = 4, headL = 3, headH = 3, headW = 4, snoutL = 1, neckUp = 1,
		ears = "point", tailLen = 9, tailUp = 0.25, main = rgb(48, 32, 78), belly = rgb(30, 20, 50), dark = rgb(18, 12, 30), eye = glow(200, 120, 255), gait = 8, spikes = glow(170, 90, 255),
		fx = { { "smoke", "body", Color3.fromRGB(140, 70, 255) } } ,
		glowC = Color3.fromRGB(170, 90, 255),
		showy = function(rig, ctx)
			-- an afterimage ribbon off its body, shadow pouring from its paws
			addTrail(rig, ctx.body, Vector3.new(0, (ctx.y0 + ctx.H / 2) * ctx.V, 0), ctx.H * ctx.V, Color3.fromRGB(110, 50, 200), 0.35)
			for _, lp in ipairs(ctx.legs) do fx(addEmitterAnchor(rig, lp, ctx.foot, Vector3.one * 0.5), "smoke", Color3.fromRGB(120, 60, 220)) end
		end }) end,
	crystal_stag = function() return buildQuad("crystal_stag", { L = 10, H = 4, W = 3, legLen = 6, legT = 1, headL = 3, headH = 2, headW = 3, snoutL = 2, neckUp = 4,
		ears = "point", horns = "antler", hornC = rgb(170, 225, 255), tailLen = 1, main = rgb(150, 190, 235), belly = rgb(225, 240, 255), dark = rgb(70, 100, 150),
		eye = glow(170, 230, 255), spikes = glow(190, 235, 255), fx = { { "stars", "body", Color3.fromRGB(170, 225, 255) } } ,
		glowC = Color3.fromRGB(170, 230, 255),
		showy = function(rig, ctx)
			-- crystal shards circling its antlers; frost where it steps
			orbit(rig, CFrame.new(0, (ctx.y1 + 9) * ctx.V, ctx.zF * ctx.V), 6, 3.2 * ctx.V, 0.8, ctx.V, function()
				return shard(glass(170, 225, 255, 0.2), glow(220, 245, 255))
			end, 0.2, 0.3)
			for _, lp in ipairs(ctx.legs) do fx(addEmitterAnchor(rig, lp, ctx.foot, Vector3.one * 0.5), "frost", Color3.fromRGB(190, 240, 255)) end
		end }) end,
	magma_lizard = function() return buildQuad("magma_lizard", { L = 12, H = 3, W = 5, legLen = 2, legT = 2, headL = 3, headH = 2, headW = 4, snoutL = 2, neckUp = 0,
		tailLen = 8, tailUp = 0, tailT = 2, main = rgb(45, 35, 35), dark = rgb(25, 18, 18), eye = glow(255, 200, 60), gait = 9,
		pattern = function(x, y, z) if (x * 3 + z) % 5 == 0 then return glow(255, 100, 20) end return nil end,
		fx = { { "embers", "body", Color3.fromRGB(255, 110, 30) } } ,
		glowC = Color3.fromRGB(255, 120, 30),
		showy = function(rig, ctx)
			-- lava bubbling up where it walks
			for _, lp in ipairs(ctx.legs) do fx(addEmitterAnchor(rig, lp, ctx.foot, Vector3.one * 0.6), "fire", Color3.fromRGB(255, 90, 20)) end
		end }) end,
	infernal_dragon = function() return buildQuad("infernal_dragon", { L = 12, H = 6, W = 5, legLen = 4, headL = 4, headH = 3, headW = 4, snoutL = 3, neckUp = 4,
		horns = "dragon", hornC = rgb(40, 20, 15), tailLen = 10, tailUp = 0.1, tailT = 2, main = rgb(175, 45, 25), belly = rgb(240, 160, 60),
		dark = rgb(50, 15, 10), eye = glow(255, 220, 80), spikes = rgb(60, 20, 15), wings = "dragon", wingScale = 1.4,
		fx = { { "fire", "head", Color3.fromRGB(255, 120, 30) }, { "embers", "body", Color3.fromRGB(255, 120, 30) } } ,
		glowC = Color3.fromRGB(255, 130, 40),
		showy = function(rig, ctx)
			-- fire breathed in great bursts; flames licking up from its feet
			breath(rig, CFrame.new(0, (ctx.y1 + 3) * ctx.V, (ctx.zF - 8) * ctx.V), Color3.fromRGB(255, 90, 20), 4, 1.1, 1.2)
			for _, lp in ipairs(ctx.legs) do fx(addEmitterAnchor(rig, lp, ctx.foot, Vector3.one * 0.6), "fire", Color3.fromRGB(255, 110, 30)) end
		end }) end,
	storm_wyvern = function() return buildQuad("storm_wyvern", { L = 11, H = 5, W = 4, legLen = 5, legs = 2, headL = 4, headH = 3, headW = 3, snoutL = 2, neckUp = 4,
		horns = "dragon", hornC = rgb(200, 230, 255), tailLen = 9, tailUp = 0.15, main = rgb(45, 90, 170), belly = rgb(150, 200, 255), dark = rgb(20, 40, 80),
		eye = glow(170, 230, 255), spikes = glow(140, 210, 255), wings = "storm", wingScale = 1.5,
		fx = { { "sparks", "body", Color3.fromRGB(140, 210, 255) } } ,
		glowC = Color3.fromRGB(130, 200, 255),
		showy = function(rig, ctx)
			-- a storm cloud riding over it, crackling; orbs of lightning circling
			local cloud = addAnchorPiece(rig, CFrame.new(0, (ctx.y1 + 14) * ctx.V, 0), function(t: number): CFrame
				return CFrame.new(math.sin(t * 0.6) * 0.3, math.sin(t * 0.9) * 0.2, 0)
			end)
			local c = addEmitterAnchor(rig, cloud, Vector3.zero, Vector3.new(6, 1.2, 6))
			fx(c, "smoke", Color3.fromRGB(60, 70, 100))
			fx(c, "sparks", Color3.fromRGB(150, 210, 255))
			addLight(rig, cloud, Vector3.zero, Color3.fromRGB(140, 200, 255), 18, 1.8)
			orbit(rig, CFrame.new(0, (ctx.y1 + 2) * ctx.V, 0), 3, 7 * ctx.V, 1.3, ctx.V, function() return ball(1.2, glow(170, 225, 255)) end, 0.25, 0.4)
		end }) end,
	death_knight_horse = function() return buildQuad("death_knight_horse", { L = 11, H = 5, W = 4, legLen = 5, headL = 4, headH = 2, headW = 3, snoutL = 2, neckUp = 4,
		ears = "point", tailLen = 5, tailUp = -0.3, main = rgb(25, 25, 32), dark = rgb(10, 10, 14), eye = glow(90, 170, 255), mane = glow(90, 170, 255),
		armor = rgb(80, 85, 100), saddle = true, fx = { { "fire", "head", Color3.fromRGB(80, 160, 255) }, { "smoke", "feet", Color3.fromRGB(40, 80, 160) } } ,
		glowC = Color3.fromRGB(90, 170, 255),
		showy = function(rig, ctx)
			-- ghost-fire hooves; spirit wisps circling the rider
			for _, lp in ipairs(ctx.legs) do fx(addEmitterAnchor(rig, lp, ctx.foot, Vector3.one * 0.6), "fire", Color3.fromRGB(70, 150, 255)) end
			local wisps = orbit(rig, CFrame.new(0, (ctx.y1 + 4) * ctx.V, 0), 3, 5 * ctx.V, 0.9, ctx.V, function() return ball(1, glow(140, 200, 255)) end, 0.3, 0.5)
			for _, w in ipairs(wisps) do addTrail(rig, w, Vector3.zero, 0.4, Color3.fromRGB(110, 180, 255), 0.6) end
		end }) end,
	void_serpent = function() return buildSerpent("void_serpent") end,
	magic_carpet = function() return buildCarpet("magic_carpet") end,
	wishing_star = function() return buildStar("wishing_star") end,
	void_disc = function() return buildVoidDisc("void_disc") end,
	celestial_lion = function() return buildQuad("celestial_lion", { L = 11, H = 5, W = 5, legLen = 5, headL = 3, headH = 4, headW = 4, snoutL = 1, neckUp = 1,
		ears = "round", tailLen = 6, tailUp = 0.3, main = rgb(240, 200, 110), dark = rgb(150, 100, 40), eye = glow(255, 255, 220), mane = rgb(255, 170, 60),
		extra = "lion_mane", wings = "celestial", wingScale = 1.4, fx = { { "stars", "body", Color3.fromRGB(255, 225, 140) } } ,
		glowC = Color3.fromRGB(255, 220, 130),
		showy = function(rig, ctx)
			-- a halo over its mane; orbs of light circling
			local halo = spinRing(rig, CFrame.new(0, (ctx.y1 + 8) * ctx.V, (ctx.zF - 1) * ctx.V) * CFrame.Angles(math.rad(10), 0, 0), 4, glow(255, 230, 140), 0.8, ctx.V)
			addLight(rig, halo, Vector3.zero, Color3.fromRGB(255, 220, 140), 14, 1.6)
			local orbs = orbit(rig, CFrame.new(0, (ctx.y1 + 3) * ctx.V, 0), 5, 6 * ctx.V, 0.6, ctx.V, function() return ball(1, glow(255, 240, 190)) end, 0.2, 0.4)
			for _, o in ipairs(orbs) do addTrail(rig, o, Vector3.zero, 0.3, Color3.fromRGB(255, 220, 130), 0.5) end
		end }) end,
	eclipse_dragon = function() return buildQuad("eclipse_dragon", { L = 12, H = 6, W = 5, legLen = 5, headL = 4, headH = 3, headW = 4, snoutL = 3, neckUp = 4,
		horns = "dragon", hornC = glow(255, 200, 80), tailLen = 10, tailUp = 0.1, tailT = 2, main = rgb(25, 20, 30), belly = rgb(60, 45, 30),
		dark = rgb(10, 8, 12), eye = glow(255, 200, 80), spikes = glow(255, 190, 70), wings = "eclipse", wingScale = 1.4, extra = "eclipse",
		fx = { { "embers", "body", Color3.fromRGB(255, 190, 70) } } ,
		glowC = Color3.fromRGB(255, 190, 80),
		showy = function(rig, ctx)
			-- dark fire breathed in bursts; a sun and a moon circling its eclipse
			breath(rig, CFrame.new(0, (ctx.y1 + 3) * ctx.V, (ctx.zF - 8) * ctx.V), Color3.fromRGB(150, 40, 200), 4.5, 1.2, 1.25)
			local orbs = orbit(rig, CFrame.new(0, (ctx.y1 + 13) * ctx.V, (ctx.zB - 1) * ctx.V), 2, 11 * ctx.V, 0.5, ctx.V, function(i)
				return if i == 1 then ball(1.8, glow(255, 210, 90)) else ball(1.6, glow(220, 225, 255))
			end, 1.4, 0)
			for _, o in ipairs(orbs) do addTrail(rig, o, Vector3.zero, 0.6, Color3.fromRGB(255, 200, 110), 0.8) end
			for _, lp in ipairs(ctx.legs) do fx(addEmitterAnchor(rig, lp, ctx.foot, Vector3.one * 0.6), "embers", Color3.fromRGB(255, 190, 70)) end
		end }) end,
}

-- ─── Public ────────────────────────────────────────────────────────────────
function WingsMounts.Build(rewardId: string): Rig?
	local r = GachaRewards.Get(rewardId)
	if not r or not r.look then return nil end
	if r.type == "wings" then return buildWings(r.look) end
	if r.type == "mount" and MOUNTS[r.look] then return MOUNTS[r.look]() end
	return nil
end

-- Put a rig at `cf` (wings: the back's attach point; mounts: on the ground,
-- facing the rider's way), animated for time `t` and movement 0..1+.
function WingsMounts.Pose(rig: Rig, cf: CFrame, t: number, move: number)
	local i = 0
	for _, piece in ipairs(rig.pieces) do
		local pcf = cf * piece.home
		if piece.anim then pcf *= piece.anim(t, move) end
		for k, off in ipairs(piece.offsets) do
			i += 1
			rig.allParts[i] = piece.parts[k]
			rig.cfs[i] = pcf * off
		end
	end
	local world = rig.world or Workspace
	world:BulkMoveTo(rig.allParts, rig.cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

-- Fixed to a character instead (the game's own wings and mounts): every
-- piece is welded to a pivot jointed to `base` by a Motor6D, so the rig is
-- part of the character's assembly and is drawn exactly where the body is
-- (moving anchored parts after it lags a frame behind and jitters while the
-- camera turns); the animation is played through the joints' Transforms.
local function makeLoose(p: BasePart)
	p.Anchored, p.Massless = false, true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
end

function WingsMounts.Attach(rig: Rig, base: BasePart, off: CFrame)
	if rig.base ~= base then
		rig.base = base
		for _, piece in ipairs(rig.pieces) do
			local motor = piece.motor
			if not motor then
				local pivot = Instance.new("Part")
				pivot.Name = "Pivot"
				pivot.Transparency, pivot.Size = 1, Vector3.one * 0.1
				makeLoose(pivot)
				pivot.CFrame = base.CFrame * off * piece.home
				for k, part in ipairs(piece.parts) do
					makeLoose(part)
					local w = Instance.new("Weld")
					w.Part0, w.Part1, w.C0 = pivot, part, piece.offsets[k]
					w.Parent = part
				end
				pivot.Parent = rig.model
				local m = Instance.new("Motor6D")
				m.Part1 = pivot
				m.Parent = pivot
				piece.motor = m
				motor = m
			end
			(motor :: Motor6D).Part0 = base
		end
		rig.baseOff = nil
	end
	if rig.baseOff ~= off then
		rig.baseOff = off
		for _, piece in ipairs(rig.pieces) do
			if piece.motor then piece.motor.C0 = off * piece.home end
		end
	end
end

-- Play an attached rig's animation for time `t` and movement 0..1+.
function WingsMounts.Animate(rig: Rig, t: number, move: number)
	for _, piece in ipairs(rig.pieces) do
		local m = piece.motor
		if m then m.Transform = if piece.anim then piece.anim(t, move) else CFrame.identity end
	end
end

-- ─── The riding pose ───────────────────────────────────────────────────────
-- Seated astride: thighs forward and spread round the mount, knees bent so
-- the shins hang down its sides, arms forward on the reins. Written over the
-- walk / idle animation each frame (after the Animator has posed the joints).
local R15_POSE = {
	LeftHip = CFrame.Angles(1.35, 0, 0) * CFrame.Angles(0, 0, -0.35),
	RightHip = CFrame.Angles(1.35, 0, 0) * CFrame.Angles(0, 0, 0.35),
	LeftKnee = CFrame.Angles(-1.45, 0, 0), RightKnee = CFrame.Angles(-1.45, 0, 0),
	LeftAnkle = CFrame.Angles(0.35, 0, 0), RightAnkle = CFrame.Angles(0.35, 0, 0),
	LeftShoulder = CFrame.Angles(0.75, 0, 0.12), RightShoulder = CFrame.Angles(0.75, 0, -0.12),
	LeftElbow = CFrame.Angles(0.55, 0, 0), RightElbow = CFrame.Angles(0.55, 0, 0),
}
-- (R6's hip and shoulder joints are turned a quarter: forward is about their Z)
local R6_POSE = {
	["Left Hip"] = CFrame.Angles(0, 0, -1.4), ["Right Hip"] = CFrame.Angles(0, 0, 1.4),
	["Left Shoulder"] = CFrame.Angles(0, 0, -0.8), ["Right Shoulder"] = CFrame.Angles(0, 0, 0.8),
}
-- On a floating platform: sat down, legs out in front, hands on the knees.
local FLAT_R15 = {
	LeftHip = CFrame.Angles(1.45, 0, 0) * CFrame.Angles(0, 0, -0.08),
	RightHip = CFrame.Angles(1.45, 0, 0) * CFrame.Angles(0, 0, 0.08),
	LeftKnee = CFrame.Angles(-0.2, 0, 0), RightKnee = CFrame.Angles(-0.2, 0, 0),
	LeftAnkle = CFrame.Angles(-0.25, 0, 0), RightAnkle = CFrame.Angles(-0.25, 0, 0),
	LeftShoulder = CFrame.Angles(0.55, 0, 0.1), RightShoulder = CFrame.Angles(0.55, 0, -0.1),
	LeftElbow = CFrame.Angles(0.3, 0, 0), RightElbow = CFrame.Angles(0.3, 0, 0),
}
local FLAT_R6 = {
	["Left Hip"] = CFrame.Angles(0, 0, -1.5), ["Right Hip"] = CFrame.Angles(0, 0, 1.5),
	["Left Shoulder"] = CFrame.Angles(0, 0, -0.6), ["Right Shoulder"] = CFrame.Angles(0, 0, 0.6),
}
local motorCache: { [Model]: { Motor6D } } = setmetatable({}, { __mode = "k" }) :: any

-- Pose a rider for one frame; `flat`: sat on a platform (RideData.IsFlat).
function WingsMounts.Seat(character: Model, flat: boolean?)
	local list = motorCache[character]
	if not list then
		list = {}
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("Motor6D") and (R15_POSE[d.Name] or R6_POSE[d.Name]) then table.insert(list, d) end
		end
		motorCache[character] = list
	end
	for _, m in ipairs(list) do
		if m.Parent then
			local pose = if flat then FLAT_R15[m.Name] or FLAT_R6[m.Name] else R15_POSE[m.Name] or R6_POSE[m.Name]
			if pose then m.Transform = pose end
		end
	end
end

-- ─── On every player ───────────────────────────────────────────────────────
type Entry = { char: Model?, wingsId: string?, wings: Rig?, mountId: string?, mount: Rig? }
local entries: { [Player]: Entry } = {}
local folder: Folder? = nil
local FAR = 170

local function holder(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "WingsMounts"
	f.Parent = Workspace
	folder = f
	return f
end

local function drop(rig: Rig?)
	if rig then rig.model:Destroy() end
end

local function step()
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local t = os.clock()
	for _, player in ipairs(Players:GetPlayers()) do
		local e = entries[player]
		if not e then
			e = {} :: Entry
			entries[player] = e
		end
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if char ~= e.char then
			drop(e.wings); drop(e.mount)
			e.wings, e.mount, e.wingsId, e.mountId = nil, nil, nil, nil
			e.char = char
		end
		if not char or not root or not hum then continue end
		-- (re)build when the equipped ones change
		local wid = player:GetAttribute("Wings")
		wid = if typeof(wid) == "string" then wid else nil
		if wid ~= e.wingsId then
			drop(e.wings)
			e.wingsId = wid
			e.wings = if wid then WingsMounts.Build(wid) else nil
		end
		local mid = char:GetAttribute("Riding")
		mid = if typeof(mid) == "string" then mid else nil
		if mid ~= e.mountId then
			drop(e.mount)
			e.mountId = mid
			e.mount = if mid then WingsMounts.Build(mid) else nil
		end
		local near = (root.Position - camPos).Magnitude < FAR and hum.Health > 0
		local v = root.AssemblyLinearVelocity
		local move = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / 16, 0, 1.6)
		for _, rig in ipairs({ e.wings, e.mount }) do
			if rig then
				local want = if near then holder() else nil
				if rig.model.Parent ~= want then rig.model.Parent = want end
			end
		end
		if not near then continue end
		if e.wings then
			local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
			if torso and torso:IsA("BasePart") then
				WingsMounts.Attach(e.wings, torso, CFrame.new(0, 0.35, torso.Size.Z / 2 + 0.08))
				WingsMounts.Animate(e.wings, t, move)
			end
		end
		if e.mount then
			-- feet on the ground under the rider (HipHeight was raised to ride)
			local legs = if hum.RigType == Enum.HumanoidRigType.R6 then 2 else 0
			local sink = math.floor((root.Size.Y / 2 + legs + hum.HipHeight) * 1000 + 0.5) / 1000
			WingsMounts.Attach(e.mount, root, CFrame.new(0, -sink, 0))
			WingsMounts.Animate(e.mount, t, move)
			local r = GachaRewards.Get(e.mountId :: string)
			WingsMounts.Seat(char, RideData.IsFlat(r and r.look))
		end
	end
	for player, e in pairs(entries) do
		if not player.Parent then
			drop(e.wings); drop(e.mount)
			entries[player] = nil
		end
	end
end

function WingsMounts.Init()
	RunService.RenderStepped:Connect(function()
		local ok, err = pcall(step)
		if not ok then warn("[WingsMounts]", err) end
	end)
end

return WingsMounts
