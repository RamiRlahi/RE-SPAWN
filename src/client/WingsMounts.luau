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
	           dragons beat their wings

	Every client builds them locally on every player (from the player's
	"Wings" attribute and the character's "Riding" attribute), and stops
	moving the ones far from the camera.

	  WingsMounts.Init()
	  WingsMounts.Build(rewardId) → rig      (for the selection screens)
	  WingsMounts.Pose(rig, cframe, t, move) (rig.world: the WorldRoot it lives in)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local BrickModels = require(script.Parent:WaitForChild("BrickModels"))

local Kit = BrickModels.Kit
local WingsMounts = {}

local VOX_WING = 0.26  -- studs per brick, wings on a character
local VOX_MOUNT = 0.42 -- studs per brick, mounts
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local FIRE_SPARK = "rbxasset://textures/particles/fire_sparks_main.dds"

type Paint = { color: Color3, neon: boolean?, alpha: number? }
type Piece = { parts: { BasePart }, offsets: { CFrame }, home: CFrame, anim: ((t: number, move: number) -> CFrame)? }
export type Rig = { model: Model, pieces: { Piece }, world: WorldRoot?, allParts: { BasePart }, cfs: { CFrame }, kind: string }

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
local function addWings(rig: Rig, spec: WingSpec, scale: number, at: Vector3, spread: number, speed: number, amp: number)
	local palette = { A = spec.A, B = spec.B, G = spec.G } :: { [string]: Paint }
	local right = wingGroup(spec, palette)
	local left = mirror(wingGroup(spec, if spec.left then spec.left :: any else palette))
	for side = -1, 1, 2 do
		local g = if side == 1 then right else left
		local home = CFrame.new(at + Vector3.new(side * 0.15, 0, 0)) * CFrame.Angles(0, -side * math.rad(spread), 0)
		local piece = addPiece(rig, { g }, scale, home, function(t: number, move: number): CFrame
			local f = speed * (1 + move * 0.9)
			local a = math.sin(t * f) * math.rad(amp * (0.6 + move * 0.7))
			return CFrame.Angles(0, -side * a * 0.35, side * a)
		end)
		if spec.fx then
			local w = #SHAPES[spec.shape][1]
			local anchor = addEmitterAnchor(rig, piece, Vector3.new(side * w * scale * 0.5, 0, 0), Vector3.new(w * scale * 0.8, #SHAPES[spec.shape] * scale * 0.6, 0.2))
			fx(anchor, spec.fx, spec.fxColor or Color3.new(1, 1, 1))
		end
	end
end

local function buildWings(look: string): Rig
	local spec = WINGS[look] or WINGS.raven
	local rig = newRig("Wings_" .. look, "wings")
	local s = VOX_WING * (spec.size or 1)
	addWings(rig, spec, s, Vector3.zero, 28, 3.6, 14)
	if spec.extra == "moon" then
		-- a crescent moon floating over the back
		local g = Kit.group()
		Kit.sprite(g, { ".##..", "##...", "#....", "##...", ".##.." }, { ["#"] = glow(235, 240, 255) }, 1, 0, 2, -2)
		addPiece(rig, { g }, VOX_WING, CFrame.new(0, 1.3, 0.3), function(t: number): CFrame
			return CFrame.new(0, math.sin(t * 1.5) * 0.08, 0)
		end)
	elseif spec.extra == "eclipse" then
		-- an eclipse behind: a black disc in a ring of fire
		local g = Kit.group()
		Kit.disc(g, 4, 1, function(_, _, d)
			if d > 3.2 then return glow(255, 120, 80) end
			return rgb(10, 5, 15)
		end)
		addPiece(rig, { g }, VOX_WING, CFrame.new(0, 0.9, 0.35), function(t: number): CFrame
			return CFrame.Angles(0, 0, t * 0.4)
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
}

local SADDLE, CLOTH = rgb(110, 60, 30), rgb(150, 30, 35)

local function buildQuad(look: string, q: Quad): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local V = VOX_MOUNT
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
		addPiece(rig, { leg }, V, CFrame.new(spot[1] * V, q.legLen * V, spot[2] * V), function(t: number, move: number): CFrame
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
	addPiece(rig, { tail }, V, CFrame.new(0, (y1 - 1) * V, (zB + 1) * V), function(t: number, move: number): CFrame
		return CFrame.Angles(math.sin(t * 2.2) * 0.08, math.sin(t * (2 + move * 3)) * 0.35, 0)
	end)

	-- Wings
	if q.wings then
		local ws = WINGS[q.wings]
		addWings(rig, ws, V * (q.wingScale or 1), Vector3.new(0, (y1 + 1) * V, -1 * V), 18, 2.4, 22)
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
		Kit.disc(g, 5, 1, function(_, _, d)
			if d > 4.1 then return glow(255, 200, 80) end
			return rgb(8, 4, 12)
		end)
		addPiece(rig, { g }, V, CFrame.new(0, (y1 + 9) * V, (zB - 1) * V), function(t: number): CFrame
			return CFrame.new(0, math.sin(t * 1.2) * 0.15, 0) * CFrame.Angles(0, 0, t * 0.3)
		end)
	end
	return rig
end

-- Eight (or six) jointed legs splayed round a body: spiders and scorpions.
local function addCrawlerLegs(rig: Rig, pairsN: number, hipY: number, zs: { number }, reach: number, drop: number, color: Paint, dark: Paint)
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
	local main, dark, venom = rgb(45, 90, 35), rgb(25, 45, 20), glow(150, 255, 60)
	local body = Kit.group()
	Kit.box(body, -2, 3, -4, 2, 5, 4, main)
	for z = -4, 4, 2 do Kit.set(body, 0, 6, z, venom.color, true) end
	local bodyPiece = addPiece(rig, { body }, VOX_MOUNT, CFrame.new(), function(t: number, move: number): CFrame
		return CFrame.new(0, math.sin(t * 9) * 0.03 * move, 0)
	end)
	-- claws
	for _, side in ipairs({ -1, 1 }) do
		local claw = Kit.group()
		for k = 0, 3 do Kit.set(claw, side * math.floor(k / 2), 0, -k, main.color) end
		Kit.box(claw, math.min(side, side * 2), 0, -6, math.max(side, side * 2), 1, -4, { color = main.color })
		Kit.set(claw, side * 1, 1, -7, dark.color)
		addPiece(rig, { claw }, VOX_MOUNT, CFrame.new(side * 2 * VOX_MOUNT, 4 * VOX_MOUNT, -4 * VOX_MOUNT), function(t: number): CFrame
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
	local tailPiece = addPiece(rig, { tail }, VOX_MOUNT, CFrame.new(0, 5 * VOX_MOUNT, 4 * VOX_MOUNT), function(t: number): CFrame
		return CFrame.Angles(math.sin(t * 1.8) * 0.12, math.sin(t * 1.1) * 0.1, 0)
	end)
	fx(addEmitterAnchor(rig, tailPiece, Vector3.new(0, 9 * VOX_MOUNT, -1 * VOX_MOUNT), Vector3.one * 0.3), "drip", Color3.fromRGB(150, 255, 60))
	addCrawlerLegs(rig, 3, 4, { -2, 0, 2 }, 3, 4, main, dark)
	fx(addEmitterAnchor(rig, bodyPiece, Vector3.new(0, 1.6, 0), Vector3.new(2, 1, 3)), "stars", Color3.fromRGB(150, 255, 60))
	return rig
end

local function buildSerpent(look: string): Rig
	local rig = newRig("Mount_" .. look, "mount")
	local base = 7 * VOX_MOUNT
	local n = 10
	for i = 1, n do
		local g = Kit.group()
		local isHead = i == 1
		local r = if isHead then 2 else 1
		Kit.box(g, -r, -r, -1, r, r, 1, rgb(80, 30, 140))
		for x = -r, r do Kit.set(g, x, r, 0, Color3.fromRGB(200, 120, 255), true) end -- glowing ridge
		Kit.set(g, 0, r + 1, 0, Color3.fromRGB(230, 170, 255), true)
		if isHead then
			Kit.box(g, -1, -1, -4, 1, 1, -2, rgb(80, 30, 140))
			Kit.set(g, -2, 1, -2, Color3.fromRGB(255, 230, 120), true)
			Kit.set(g, 2, 1, -2, Color3.fromRGB(255, 230, 120), true)
			for k = 0, 2 do
				Kit.set(g, -2, 2 + k, 1 + k, Color3.fromRGB(230, 210, 255))
				Kit.set(g, 2, 2 + k, 1 + k, Color3.fromRGB(230, 210, 255))
			end
		end
		local z = (i - 4) * 3.4 * VOX_MOUNT
		local k = i
		local piece = addPiece(rig, { g }, VOX_MOUNT, CFrame.new(0, base, z), function(t: number, move: number): CFrame
			local w = 2.2 + move * 2
			return CFrame.new(math.sin(t * w * 0.6 - k * 0.5) * 0.35, math.sin(t * w - k * 0.6) * 0.45, 0)
		end)
		if i % 3 == 0 then fx(addEmitterAnchor(rig, piece, Vector3.zero, Vector3.one), "smoke", Color3.fromRGB(150, 60, 255)) end
	end
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
		fx = { { "smoke", "body", Color3.fromRGB(140, 70, 255) } } }) end,
	crystal_stag = function() return buildQuad("crystal_stag", { L = 10, H = 4, W = 3, legLen = 6, legT = 1, headL = 3, headH = 2, headW = 3, snoutL = 2, neckUp = 4,
		ears = "point", horns = "antler", hornC = rgb(170, 225, 255), tailLen = 1, main = rgb(150, 190, 235), belly = rgb(225, 240, 255), dark = rgb(70, 100, 150),
		eye = glow(170, 230, 255), spikes = glow(190, 235, 255), fx = { { "stars", "body", Color3.fromRGB(170, 225, 255) } } }) end,
	magma_lizard = function() return buildQuad("magma_lizard", { L = 12, H = 3, W = 5, legLen = 2, legT = 2, headL = 3, headH = 2, headW = 4, snoutL = 2, neckUp = 0,
		tailLen = 8, tailUp = 0, tailT = 2, main = rgb(45, 35, 35), dark = rgb(25, 18, 18), eye = glow(255, 200, 60), gait = 9,
		pattern = function(x, y, z) if (x * 3 + z) % 5 == 0 then return glow(255, 100, 20) end return nil end,
		fx = { { "embers", "body", Color3.fromRGB(255, 110, 30) } } }) end,
	infernal_dragon = function() return buildQuad("infernal_dragon", { L = 12, H = 6, W = 5, legLen = 4, headL = 4, headH = 3, headW = 4, snoutL = 3, neckUp = 4,
		horns = "dragon", hornC = rgb(40, 20, 15), tailLen = 10, tailUp = 0.1, tailT = 2, main = rgb(175, 45, 25), belly = rgb(240, 160, 60),
		dark = rgb(50, 15, 10), eye = glow(255, 220, 80), spikes = rgb(60, 20, 15), wings = "dragon", wingScale = 1.4,
		fx = { { "fire", "head", Color3.fromRGB(255, 120, 30) }, { "embers", "body", Color3.fromRGB(255, 120, 30) } } }) end,
	storm_wyvern = function() return buildQuad("storm_wyvern", { L = 11, H = 5, W = 4, legLen = 5, legs = 2, headL = 4, headH = 3, headW = 3, snoutL = 2, neckUp = 4,
		horns = "dragon", hornC = rgb(200, 230, 255), tailLen = 9, tailUp = 0.15, main = rgb(45, 90, 170), belly = rgb(150, 200, 255), dark = rgb(20, 40, 80),
		eye = glow(170, 230, 255), spikes = glow(140, 210, 255), wings = "storm", wingScale = 1.5,
		fx = { { "sparks", "body", Color3.fromRGB(140, 210, 255) } } }) end,
	death_knight_horse = function() return buildQuad("death_knight_horse", { L = 11, H = 5, W = 4, legLen = 5, headL = 4, headH = 2, headW = 3, snoutL = 2, neckUp = 4,
		ears = "point", tailLen = 5, tailUp = -0.3, main = rgb(25, 25, 32), dark = rgb(10, 10, 14), eye = glow(90, 170, 255), mane = glow(90, 170, 255),
		armor = rgb(80, 85, 100), saddle = true, fx = { { "fire", "head", Color3.fromRGB(80, 160, 255) }, { "smoke", "feet", Color3.fromRGB(40, 80, 160) } } }) end,
	void_serpent = function() return buildSerpent("void_serpent") end,
	celestial_lion = function() return buildQuad("celestial_lion", { L = 11, H = 5, W = 5, legLen = 5, headL = 3, headH = 4, headW = 4, snoutL = 1, neckUp = 1,
		ears = "round", tailLen = 6, tailUp = 0.3, main = rgb(240, 200, 110), dark = rgb(150, 100, 40), eye = glow(255, 255, 220), mane = rgb(255, 170, 60),
		extra = "lion_mane", wings = "celestial", wingScale = 1.4, fx = { { "stars", "body", Color3.fromRGB(255, 225, 140) } } }) end,
	eclipse_dragon = function() return buildQuad("eclipse_dragon", { L = 12, H = 6, W = 5, legLen = 5, headL = 4, headH = 3, headW = 4, snoutL = 3, neckUp = 4,
		horns = "dragon", hornC = glow(255, 200, 80), tailLen = 10, tailUp = 0.1, tailT = 2, main = rgb(25, 20, 30), belly = rgb(60, 45, 30),
		dark = rgb(10, 8, 12), eye = glow(255, 200, 80), spikes = glow(255, 190, 70), wings = "eclipse", wingScale = 1.4, extra = "eclipse",
		fx = { { "embers", "body", Color3.fromRGB(255, 190, 70) } } }) end,
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
				WingsMounts.Pose(e.wings, torso.CFrame * CFrame.new(0, 0.35, torso.Size.Z / 2 + 0.08), t, move)
			end
		end
		if e.mount then
			-- feet on the ground under the rider (HipHeight was raised to ride)
			local legs = if hum.RigType == Enum.HumanoidRigType.R6 then 2 else 0
			local ground = root.Position.Y - root.Size.Y / 2 - legs - hum.HipHeight
			local look = root.CFrame.LookVector
			local yaw = CFrame.lookAt(Vector3.zero, Vector3.new(look.X, 0, look.Z))
			WingsMounts.Pose(e.mount, CFrame.new(root.Position.X, ground, root.Position.Z) * yaw, t, move)
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
