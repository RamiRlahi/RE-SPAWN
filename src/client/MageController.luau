--!strict
--[[
	MageController.luau
	Client side of the Mage, "The Arcanist" (server: MageServer), after the
	class sheet: violet and blue arcane light, magic circles, chains of
	light, echoes of himself in blue.

	  • Your own casts start at once on your screen (the bolt leaves your hand,
	    the Shift blinks you there in the same frame); the server decides the
	    hits and sends every Mage's moments to everyone over MageFX.
	  • The grimoire floats open off his left side, pages turned to him, glyphs
	    circling it; when he casts it swings up, a leaf turns over and its
	    pages flare (every Mage, every client: its motors, MageLook).
	  • The Arcane Charge pips over the skill bar (MG_Charge; full = the next
	    ability is EMPOWERED, and a circle turns under his feet).

	The effects (one RenderStepped loop runs them all, `animate`):
	  bolt          a violet comet with a white core; a sigil flashes open at
	                the hand
	  black hole    the Burst: a sphere of nothing with a burning edge, a
	                tilted disk of light whirling round it, light and dust
	                drawn in from every side; it crushes to a point and pops
	  magicCircle   rings of light, an eight-pointed star and runes, turning
	                (the Prison's floor, the runes, the Apocalypse's array)
	  chains        links of spectral light: a cage leaning in round the
	                Prison, chains shot from the floor at the trapped
	  shell         a sphere of energy: the 3D shockwaves, the Prison's dome
	  echo          a blue copy of him drawn in light, waiting
	  the pack      ReplicatedStorage.VFXPack effects recoloured violet and
	                blue (PackFX): the vortex, the lightning, the explosion
	Per-hit effects go through FxBudget.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local MageLook = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("MageLook"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local PackFX = require(script.Parent:WaitForChild("PackFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))

local player = Players.LocalPlayer

local MageController = {}

-- ── Tuning (matches MageServer) ─────────────────────────────────────────────
local BOLT_INTERVAL = 0.42
local BOLT_SPEED = 120
local BOLT_RANGE = 55
local BOLT_SEEK = math.cos(math.rad(16))
local BOLT_FAN = math.rad(8)
local CHARGE_MAX = 100
local SHIFT_RANGE = 30
local SHIFT_WAVE = 0.12
local ULT_TOTAL = 3.4

local VIOLET = Color3.fromRGB(170, 90, 255)
local BLUE = Color3.fromRGB(96, 120, 255)
local PALE = Color3.fromRGB(232, 206, 255)
local DEEP = Color3.fromRGB(70, 30, 160)
local WHITE = Color3.new(1, 1, 1)

type Deps = { shake: (number, number) -> (), fovPunch: (number, number) -> (), getAim: (BasePart) -> Vector3 }
local deps: Deps

local lastBolt = 0
local busyUntil = 0

local function isMage(p: Player?): boolean
	return (p or player):GetAttribute("SelectedClass") == "mage"
end

local function charOf(p: any): Model?
	return if typeof(p) == "Instance" and p:IsA("Player") then p.Character else nil
end

local function rootOf(char: Model?): BasePart?
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function near(pos: Vector3, reach: number): boolean
	local r = rootOf(player.Character)
	return r ~= nil and (r.Position - pos).Magnitude < reach
end

local function part(props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = ClassFX.Folder()
	return p
end

-- ── One loop for every running effect ───────────────────────────────────────
-- `fn(a, dt)` gets 0..1 over `dur`; it's called a last time with a = 1.
-- (It can return true to finish early: the long-lived ones, done.)
local running: { { t0: number, dur: number, fn: (number, number) -> boolean? } } = {}
local function animate(dur: number, fn: (number, number) -> boolean?)
	table.insert(running, { t0 = os.clock(), dur = math.max(dur, 0.01), fn = fn })
end
local function stepAnims(dt: number)
	local now = os.clock()
	for i = #running, 1, -1 do
		local r = running[i]
		local a = math.min((now - r.t0) / r.dur, 1)
		local ok, res = pcall(r.fn, a, dt)
		if not ok then warn("[MageController] fx:", res) end
		if a >= 1 or not ok or res == true then table.remove(running, i) end
	end
end

local function easeOut(a: number): number return 1 - (1 - a) ^ 3 end

-- The floor under a point (ignoring bodies and effects).
local function ground(pos: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -30, 0), params)
	return if hit then hit.Position else pos - Vector3.new(0, 3, 0)
end

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- ── Small pieces of light ───────────────────────────────────────────────────
local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- (a cylinder laid flat)
-- (the pack's portals face forward like a doorway: this lays one flat on the floor)
local FLOOR_UP = CFrame.Angles(math.rad(90), 0, 0)

-- A flat ring of light on the floor, opening out and fading.
local function floorRing(pos: Vector3, radius: number, life: number, color: Color3?, width: number?)
	SwordFX.Arc({ cf = CFrame.new(pos + Vector3.new(0, 0.15, 0)), radius = radius * 0.6, arc = 359, width = width or 0.9,
		color = color or VIOLET, life = life, draw = 0.001, grow = 0.7, core = PALE })
end

-- A sphere of light swelling out and fading.
local function flare(pos: Vector3, size: number, life: number, color: Color3?)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.3, CFrame = CFrame.new(pos), Color = color or PALE, Transparency = 0.1 })
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size, Transparency = 1, Color = VIOLET }):Play()
	Debris:AddItem(b, life + 0.05)
end

-- A shell of energy (ForceField: bright at its edges, like a bubble) going
-- from `from` to `to` studs across and fading: swelling out, a 3D shockwave;
-- closing in (to < from), an implosion.
local function shell(pos: Vector3, from: number, to: number, life: number, color: Color3?)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * from, CFrame = CFrame.new(pos), Color = color or VIOLET,
		Material = Enum.Material.ForceField })
	TweenService:Create(b, TweenInfo.new(life, if to > from then Enum.EasingStyle.Quart else Enum.EasingStyle.Quad,
		if to > from then Enum.EasingDirection.Out else Enum.EasingDirection.In), { Size = Vector3.one * math.max(to, 0.05), Transparency = 1 }):Play()
	Debris:AddItem(b, life + 0.05)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function nseq(a: number, b: number): NumberSequence
	return NumberSequence.new(a, b)
end

local function sparks(pos: Vector3, count: number, speed: number, color: Color3?)
	ClassFX.Burst(pos, color or VIOLET, count, speed, ClassFX.TEX_SPARK, 0.35, 0.5)
end

-- A violet streak from a to b.
local function streak(a: Vector3, b: Vector3, width: number, life: number, color: Color3?)
	SwordFX.Streak(a, b, width, color or VIOLET, life, nil, PALE)
end

-- The world dimmed and tinged violet for a while (the Apocalypse).
local function tint(seconds: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MageApocalypse"
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.4), { Brightness = -0.1, Contrast = 0.18, Saturation = 0.1,
		TintColor = Color3.fromRGB(215, 196, 255) }):Play()
	task.delay(seconds, function()
		TweenService:Create(cc, TweenInfo.new(0.6), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }):Play()
		Debris:AddItem(cc, 0.65)
	end)
end

local function flash(t: number, from: number?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MageFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = PALE
	f.BackgroundTransparency = from or 0.3
	f.BorderSizePixel = 0
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, t + 0.05)
end

-- ── The magic circle ────────────────────────────────────────────────────────
-- Rings of light, an eight-pointed star between them, small diamond runes
-- round the edge, a rune in the middle: built in `cf`'s XZ plane (its up is
-- the circle's face), each ring turning its own way. Fades in (`grow`),
-- out (`fade`); `set(alpha, hot)` re-lights it (hot: toward white).
type Circle = { cf: CFrame, parts: { BasePart }, rel: { CFrame }, spin: { number }, angle: number,
	alpha: number, hot: number, alive: boolean, base: { Color3 } }

local function newCircle(cf: CFrame, radius: number, opts: { color: Color3?, glyphs: number?, star: boolean?, speed: number? }?): Circle
	local o = opts or {}
	local color = o.color or VIOLET
	local c: Circle = { cf = cf, parts = {}, rel = {}, spin = {}, angle = 0, alpha = 0, hot = 0, alive = true, base = {} }
	local function add(size: Vector3, rel: CFrame, spin: number, col: Color3)
		local p = part({ Size = size, Color = col, Transparency = 1, CFrame = cf * rel })
		table.insert(c.parts, p)
		table.insert(c.rel, rel)
		table.insert(c.spin, spin)
		table.insert(c.base, col)
	end
	local thick = math.clamp(radius * 0.03, 0.12, 0.6)
	-- the rings (outer, a thin second one, the inner)
	for _, ring in ipairs({ { r = 1, w = thick * 1.3, spin = 1, col = color }, { r = 0.9, w = thick * 0.6, spin = -1, col = PALE },
		{ r = 0.56, w = thick, spin = 1.6, col = color } }) do
		local n = math.clamp(math.floor(radius * ring.r * 2.2), 16, 48)
		local rr = radius * ring.r
		local seg = 2 * math.pi * rr / n * 1.08
		for k = 1, n do
			local a = k / n * math.pi * 2
			add(Vector3.new(seg, 0.05, ring.w), CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -rr), ring.spin, ring.col)
		end
	end
	-- the eight-pointed star (two squares turned 45°), between the rings
	if o.star ~= false then
		local sr = radius * 0.86
		for sq = 0, 1 do
			for k = 0, 3 do
				local a1 = (k / 4 + sq / 8) * math.pi * 2
				local a2 = ((k + 1) / 4 + sq / 8) * math.pi * 2
				local p1 = Vector3.new(math.sin(a1) * sr, 0, -math.cos(a1) * sr)
				local p2 = Vector3.new(math.sin(a2) * sr, 0, -math.cos(a2) * sr)
				local mid = (p1 + p2) / 2
				add(Vector3.new(thick * 0.7, 0.05, (p2 - p1).Magnitude), CFrame.lookAt(mid, p2), -0.6, color)
			end
		end
	end
	-- runes round the edge, and the middle one
	local glyphs = o.glyphs or 12
	-- (kept small on the big ones: the Apocalypse's hang close under the camera)
	local g = math.min(radius * 0.06 + 0.12, 0.8)
	for k = 1, glyphs do
		local a = (k + 0.5) / glyphs * math.pi * 2
		add(Vector3.new(g, 0.06, g), CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -radius * 0.95) * CFrame.Angles(0, math.rad(45), 0), 1, PALE)
	end
	local mid = math.min(radius * 0.22, 2.2)
	add(Vector3.new(mid, 0.06, mid), CFrame.Angles(0, math.rad(45), 0), -1, PALE)
	local speed = o.speed or 0.6
	animate(600, function(_, dt)
		if not c.alive then return true end
		c.angle += dt * speed
		local cfs = table.create(#c.parts)
		local tr = 1 - c.alpha
		for i, p in ipairs(c.parts) do
			cfs[i] = c.cf * CFrame.Angles(0, c.angle * c.spin[i], 0) * c.rel[i]
			p.Transparency = tr
			p.Color = c.base[i]:Lerp(WHITE, c.hot)
		end
		Workspace:BulkMoveTo(c.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		return nil
	end)
	return c
end

local function fadeCircle(c: Circle, to: number, t: number)
	local from = c.alpha
	animate(t, function(a)
		c.alpha = from + (to - from) * a
	end)
end

local function dropCircle(c: Circle, t: number)
	local from = c.alpha
	animate(t, function(a)
		c.alpha = from * (1 - a)
		if a >= 1 then
			c.alive = false
			for _, p in ipairs(c.parts) do p:Destroy() end
		end
	end)
end

-- ── The grimoire ────────────────────────────────────────────────────────────
-- Every Mage's book: floating off his left side, pages turned to him; on a
-- cast it swings to where the spell needs it, a leaf turns over (several
-- for the Apocalypse), its pages flare and the glyphs round it whirl, then
-- it drifts back.
local BOOK_HOLD = {
	-- held out before him at the left, open to him, read from
	read = CFrame.new(-2.9, 0.75, -1.5) * CFrame.Angles(0, math.rad(215), 0) * CFrame.Angles(math.rad(-55), 0, 0),
	-- lifted high in the left hand, still open to him
	raise = CFrame.new(-2.7, 2.6, -0.9) * CFrame.Angles(0, math.rad(200), 0) * CFrame.Angles(math.rad(-70), 0, 0),
	-- floating over his head, open to the sky
	sky = CFrame.new(0, 3.6, -1.2) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(math.rad(-15), 0, 0),
}
local LEAF_FLIP = 0.26 -- seconds to turn one leaf
type Book = { motor: Motor6D, rune: BasePart?, leaf: Motor6D?, leafParts: { BasePart }, glyphs: Motor6D?,
	mode: string?, untilT: number, k: number, phase: number, flipT: number, flips: number, spin: number, shown: boolean }
local books: { [Model]: Book } = {}

local function bookOf(char: Model): Book?
	local b = books[char]
	if b and b.motor.Parent then return b end
	for _, core in ipairs(CollectionService:GetTagged(MageLook.GRIMOIRE_TAG)) do
		if core:IsDescendantOf(char) then
			local m = core:FindFirstChild("GrimoireMotor")
			if m and m:IsA("Motor6D") then
				local rune: BasePart? = nil
				local leaf: Motor6D? = nil
				local glyphs: Motor6D? = nil
				local leafParts: { BasePart } = {}
				for _, d in ipairs(char:GetDescendants()) do
					if d.Name == "PageRune" and d:IsA("BasePart") and not rune then rune = d end
					if d.Name == "LeafMotor" and d:IsA("Motor6D") then leaf = d end
					if d.Name == "GlyphMotor" and d:IsA("Motor6D") then glyphs = d end
					if (d.Name == "GrimoireLeaf" or d.Name == "LeafRune") and d:IsA("BasePart") then table.insert(leafParts, d) end
				end
				local nb: Book = { motor = m, rune = rune, leaf = leaf, leafParts = leafParts, glyphs = glyphs, mode = nil,
					untilT = 0, k = 0, phase = math.random() * 6, flipT = -10, flips = 0, spin = 0, shown = false }
				books[char] = nb
				return nb
			end
		end
	end
	return nil
end

-- Swing `char`'s book up for a cast (`mode`: read / raise / sky) for `seconds`.
local function bookCast(char: Model?, mode: string, seconds: number)
	if not char then return end
	local b = bookOf(char)
	if not b then return end
	b.mode = mode
	b.untilT = os.clock() + seconds
	b.flipT = os.clock()
	b.flips = if mode == "sky" then 6 elseif mode == "raise" then 2 else 1
	if b.rune and b.rune.Parent then
		local rune = b.rune
		rune.Color = WHITE
		TweenService:Create(rune, TweenInfo.new(0.5), { Color = VIOLET }):Play()
		if FxBudget.Allow("mageBook", 8) then sparks(rune.Position, 8, 6, PALE) end
	end
end

local function stepBooks(dt: number)
	local now = os.clock()
	for _, core in ipairs(CollectionService:GetTagged(MageLook.GRIMOIRE_TAG)) do
		-- (the book is in his robes, in his character: the one with a Humanoid)
		local char: Instance? = core.Parent
		while char and not (char:IsA("Model") and char:FindFirstChildOfClass("Humanoid")) do
			char = char.Parent
		end
		if not (char and char:IsA("Model")) then continue end
		local b = bookOf(char)
		if not b then continue end
		local casting = b.mode ~= nil and now < b.untilT
		b.k += ((if casting then 1 else 0) - b.k) * math.min(dt * (if casting then 14 else 5), 1)
		local hold = BOOK_HOLD[b.mode or "read"] or BOOK_HOLD.read
		local rest = MageLook.GRIMOIRE_REST
		local at = rest:Lerp(hold, b.k)
		-- (bobbing, turning a little; held still while it's read from)
		local bob = CFrame.new(0, math.sin(now * 2.1 + b.phase) * 0.14 * (1 - b.k * 0.6), 0)
			* CFrame.Angles(0, math.sin(now * 0.8 + b.phase) * 0.12 * (1 - b.k), 0)
		if b.mode == "sky" and casting then bob = CFrame.Angles(0, now * 1.5, 0) end
		b.motor.Transform = b.motor.C0:Inverse() * at * bob
		-- the leaf turning over (shown only while it turns)
		local flipping = now - b.flipT < b.flips * LEAF_FLIP
		if b.leaf then
			local u = if flipping then ((now - b.flipT) / LEAF_FLIP) % 1 else 0
			u = u * u * (3 - 2 * u)
			b.leaf.Transform = CFrame.Angles(0, 0, math.rad(12) + (math.pi - math.rad(24)) * u)
		end
		if flipping ~= b.shown then
			b.shown = flipping
			for _, p in ipairs(b.leafParts) do
				p.Transparency = if not flipping then 1 elseif p.Name == "LeafRune" then 0.3 else 0
			end
		end
		-- the glyphs circling it, whirling while he casts
		if b.glyphs then
			b.spin += dt * (1.3 + 6 * b.k)
			b.glyphs.Transform = CFrame.Angles(0, b.spin, 0)
		end
	end
	for char in pairs(books) do
		if not char.Parent then books[char] = nil end
	end
end

-- ── Poses (the right hand casts; the left keeps the book) ───────────────────
local function boltPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.05, style = Enum.EasingStyle.Quart, pose = { RS = { 95, -8, 0 }, W = { -4, -14, 0 }, N = { 0, 10, 0 } } },
		{ dur = 0.14, pose = { RS = { 90, -6, 0 }, W = { -3, -12, 0 } } },
	}, 0.2)
end

local function burstPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.1, pose = { Root = { 0, 0, 0, 0, -0.2, 0.25 }, W = { 6, 28, 0 }, RS = { 70, 50, 0 }, LS = { 40, 0, -20 }, N = { 0, -20, 0 } } },
		{ dur = 0.07, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.3, -0.35 }, W = { -10, -22, 0 }, RS = { 98, -6, 0 },
			LS = { 30, 0, -25 }, RH = { 18, 0, 6 }, LH = { -16, 0, -6 }, N = { 6, 14, 0 } } },
		{ dur = 0.22, pose = { Root = { 0, 0, 0, 0, -0.25, -0.25 }, W = { -8, -18, 0 }, RS = { 92, -4, 0 }, LS = { 30, 0, -25 } } },
	}, 0.3)
end

local function prisonPose(char: Model)
	-- the book raised in the left hand, the right flung down at the ground
	CastPoses.play(char, {
		{ dur = 0.12, pose = { W = { 8, 0, 0 }, RS = { 150, 0, 25 }, LS = { 120, 0, -30 }, N = { -15, 0, 0 } } },
		{ dur = 0.1, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.35, 0 }, W = { -16, 0, 0 }, RS = { 40, 0, 18 },
			LS = { 140, 0, -24 }, N = { 18, 0, 0 } } },
		{ dur = 0.35, pose = { Root = { 0, 0, 0, 0, -0.3, 0 }, W = { -14, 0, 0 }, RS = { 38, 0, 16 }, LS = { 138, 0, -24 }, N = { 14, 0, 0 } } },
	}, 0.3)
end

local function shiftPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.04, pose = { Root = { 0, 0, 0, 0, -0.5, 0 }, W = { -22, 0, 0 }, RS = { -30, 0, 40 }, LS = { -30, 0, -40 }, N = { 20, 0, 0 } } },
		{ dur = 0.18, style = Enum.EasingStyle.Back, pose = { Root = { 0, 0, 0, 0, -0.3, 0 }, W = { -8, 0, 0 }, RS = { 60, 0, 70 },
			LS = { 60, 0, -70 }, N = { 0, 0, 0 } } },
	}, 0.3)
end

local function apocPose(char: Model)
	-- both arms thrown up to the sky, head back; held, trembling, through the
	-- rain; then flung down and out as every mark goes off
	local up = { W = { 14, 0, 0 }, RS = { 172, 0, 22 }, LS = { 172, 0, -22 }, N = { -28, 0, 0 } }
	CastPoses.play(char, {
		{ dur = 0.25, style = Enum.EasingStyle.Back, pose = up },
		{ dur = 2.65, pose = up, wobble = function(t: number)
			local s = math.sin(t * 40) * 1.5
			return { RS = { s, 0, 0 }, LS = { -s, 0, 0 } }
		end },
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.4, 0 }, W = { -18, 0, 0 }, RS = { 70, 0, 75 },
			LS = { 70, 0, -75 }, N = { 16, 0, 0 } } },
		{ dur = 0.4, pose = { Root = { 0, 0, 0, 0, -0.35, 0 }, W = { -14, 0, 0 }, RS = { 64, 0, 70 }, LS = { 64, 0, -70 } } },
	}, 0.4)
end

-- ── M1: the Arcane Bolt ─────────────────────────────────────────────────────
-- A violet orb with a white core and a trail, flying until it meets a body
-- (judged here, for the picture; the server decides the hit), a wall or the
-- end of its reach; a little burst where it stops.
local function boltBurst(at: Vector3)
	if not FxBudget.Allow("mageBoltHit", 14) then return end
	flare(at, 3, 0.18)
	sparks(at, 8, 14)
	if FxBudget.Allow("mageBoltPack", 6) then
		PackFX.Burst("Anime/Lighting-03", CFrame.new(at), { color = VIOLET, scale = 0.6, count = 0.5 })
	end
end

local function mobNear(pos: Vector3, reach: number): boolean
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return false end
	for _, m in ipairs(mobs:GetChildren()) do
		local r = m:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			local d = r.Position - pos
			if Vector3.new(d.X, 0, d.Z).Magnitude < reach and math.abs(d.Y) < 4 then return true end
		end
	end
	return false
end

local function wallDistance(from: Vector3, dir: Vector3, length: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local res = Workspace:Raycast(from, dir * length, params)
	return if res then res.Distance else length
end

-- A small sigil of light flashing open at the casting hand, facing the aim:
-- a ring of light and a square turned inside it, spinning apart.
local function handSigil(at: Vector3, dir: Vector3, size: number?)
	if not FxBudget.Allow("mageSigil", 8) then return end
	local s = size or 1
	local face = CFrame.lookAt(at, at + dir)
	local segs: { BasePart } = {}
	local n = 12
	for k = 1, n do
		table.insert(segs, part({ Size = Vector3.new(0.08, 0.5 * s, 0.04), Color = if k % 3 == 0 then WHITE else VIOLET, Transparency = 0.1, CFrame = face }))
	end
	for _ = 1, 4 do
		table.insert(segs, part({ Size = Vector3.new(0.06, 0.95 * s, 0.04), Color = PALE, Transparency = 0.1, CFrame = face }))
	end
	local cfs = table.create(#segs)
	animate(0.24, function(a)
		local r = (0.45 + 0.7 * easeOut(a)) * s
		for k = 1, n do
			cfs[k] = face * CFrame.Angles(0, 0, k / n * math.pi * 2 + a * 1.5) * CFrame.new(r, 0, 0)
		end
		for k = 1, 4 do
			cfs[n + k] = face * CFrame.Angles(0, 0, k / 4 * math.pi * 2 - a * 2 + math.rad(45)) * CFrame.new(r * 0.62, 0, 0)
		end
		Workspace:BulkMoveTo(segs, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		for _, p in ipairs(segs) do p.Transparency = 0.1 + 0.9 * a end
		if a >= 1 then
			for _, p in ipairs(segs) do p:Destroy() end
		end
		return nil
	end)
end

local function fireBolt(from: Vector3, dir: Vector3, speed: number, size: number?)
	local s = size or 1
	local length = wallDistance(from, dir, BOLT_RANGE)
	-- (a comet: the glow drawn out behind the white core)
	local glow = part({ Size = Vector3.one * 1.0 * s, Color = VIOLET, Transparency = 0.4, CFrame = CFrame.lookAt(from, from + dir) })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 1, 2.6)
	mesh.Parent = glow
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.42 * s, Color = WHITE, CFrame = CFrame.new(from) })
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = Vector3.new(0, 0.25 * s, 0), Vector3.new(0, -0.25 * s, 0)
	a0.Parent, a1.Parent = core, core
	local tr = Instance.new("Trail")
	tr.Attachment0, tr.Attachment1 = a0, a1
	tr.Color = ColorSequence.new(PALE, BLUE)
	tr.Transparency = NumberSequence.new(0.1, 1)
	tr.LightEmission = 1
	tr.FaceCamera = true
	tr.Lifetime = 0.18
	tr.Parent = core
	local flown = 0
	local done = false
	animate(length / speed + 0.05, function(a, dt)
		if done then return end
		flown = math.min(length, flown + speed * dt)
		local p = from + dir * flown
		glow.CFrame = CFrame.lookAt(p, p + dir) * CFrame.new(0, 0, 0.75 * s)
		core.CFrame = CFrame.new(p)
		local stop = flown >= length or a >= 1 or mobNear(p, 2.4 * s)
		if stop then
			done = true
			boltBurst(p)
			glow:Destroy()
			tr.Enabled = false
			core.Transparency = 1
			Debris:AddItem(core, 0.2)
		end
	end)
end

-- The aim the server will use: the enemy nearest the aim inside a cone.
local function boltAim(origin: Vector3, dir: Vector3): Vector3
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return dir end
	local best, bestScore = nil, math.huge
	for _, m in ipairs(mobs:GetChildren()) do
		local r = m:FindFirstChild("HumanoidRootPart")
		local hum = m:FindFirstChildOfClass("Humanoid")
		if r and r:IsA("BasePart") and hum and hum.Health > 0 then
			local d = Vector3.new(r.Position.X - origin.X, 0, r.Position.Z - origin.Z)
			local dist = d.Magnitude
			if dist > 1 and dist <= BOLT_RANGE then
				local dot = dir:Dot(d.Unit)
				if dot >= BOLT_SEEK then
					local score = dist * (2 - dot)
					if score < bestScore then best, bestScore = r, score end
				end
			end
		end
	end
	return if best then flat(best.Position - origin) else dir
end

local function onBolt(msg: any)
	if msg.attacker == player then return end -- (ours left our hand already)
	local char = charOf(msg.attacker)
	if char then
		boltPose(char)
		bookCast(char, "read", 0.35)
	end
	if msg.dirs and msg.dirs[1] then handSigil(msg.from, msg.dirs[1]) end
	for _, d in ipairs(msg.dirs or {}) do
		fireBolt(msg.from, d, tonumber(msg.speed) or BOLT_SPEED)
	end
end

-- ── E: Arcane Burst ─────────────────────────────────────────────────────────
-- The orbs: big, with a white core, motes spiralling off them, flying the
-- server's paths; each bursts when the server says it landed.
type Orb = { parts: { BasePart }, at: (number) -> Vector3, length: number, alive: boolean }
local orbs: { [Player]: { [number]: Orb } } = {}

local function onBurstCast(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	if char then
		if owner ~= player then burstPose(char) end
		bookCast(char, "read", 0.5)
		local hand = char:FindFirstChild("Right Arm") :: BasePart?
		if hand then PackFX.Burst("Anime/Charge-01", hand.CFrame * CFrame.new(0, -1.2, 0), { color = VIOLET, scale = 0.5 }) end
	end
	local from = msg.from :: Vector3
	local to = msg.to :: Vector3
	handSigil(from, flat(to - from), 1.8)
	local dir = flat(to - from)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local length = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
	local speed = tonumber(msg.speed) or 95
	local mine: { [number]: Orb } = {}
	orbs[owner] = mine
	for k, bow in ipairs(msg.bows or { 0 }) do
		local ctrl = from + dir * length * 0.5 + side * bow
		local function at(s: number): Vector3
			local u = math.clamp(s / math.max(length, 0.1), 0, 1)
			return from:Lerp(ctrl, u):Lerp(ctrl:Lerp(to, u), u)
		end
		-- (a small black hole already: a core of nothing in a burning shell)
		local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2.6, Color = VIOLET, Transparency = 0.72, CFrame = CFrame.new(from) })
		local rim = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.55, Color = PALE, Material = Enum.Material.ForceField,
			CFrame = CFrame.new(from) })
		local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.0, Color = Color3.new(0, 0, 0), CFrame = CFrame.new(from) })
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Position, a1.Position = Vector3.new(0, 0.45, 0), Vector3.new(0, -0.45, 0)
		a0.Parent, a1.Parent = core, core
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(PALE, DEEP)
		tr.Transparency = NumberSequence.new(0, 1)
		tr.LightEmission = 1
		tr.FaceCamera = true
		tr.Lifetime = 0.3
		tr.Parent = core
		local orb: Orb = { parts = { glow, rim, core }, at = at, length = length, alive = true }
		mine[k] = orb
		local flown = 0
		local spin = 0
		animate(length / speed + 1.5, function(_, dt)
			if not orb.alive then return true end
			flown = math.min(length, flown + speed * dt)
			spin += dt * 14
			local p = at(flown)
			glow.CFrame = CFrame.new(p)
			glow.Size = Vector3.one * (2.6 + math.sin(spin) * 0.3)
			rim.CFrame = CFrame.new(p)
			core.CFrame = CFrame.new(p)
			if FxBudget.Allow("mageOrbMote", 40) then
				local m = p + Vector3.new(math.cos(spin) * 1.2, math.sin(spin * 0.7) * 0.6, math.sin(spin) * 1.2)
				local mote = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.3, Color = PALE, CFrame = CFrame.new(m) })
				TweenService:Create(mote, TweenInfo.new(0.3), { Size = Vector3.zero, Transparency = 1 }):Play()
				Debris:AddItem(mote, 0.32)
			end
			return nil
		end)
	end
	ClassFX.Sound("magicBurst", from, 0.5, 1.2)
end

local function onBurstEnd(msg: any)
	local list = orbs[msg.attacker]
	local orb = list and list[tonumber(msg.k) or 1]
	if not orb or not orb.alive then return end
	orb.alive = false
	for _, p in ipairs(orb.parts) do
		p.Transparency = 1
		Debris:AddItem(p, 0.35)
	end
end

-- ── The black hole ──────────────────────────────────────────────────────────
-- Where a Burst lands: a sphere of nothing with a burning edge; a tilted
-- disk of light whirling round it (the inner rings fastest), wobbling as it
-- turns; a halo bent round its silhouette (always facing you); streaks and
-- dust drawn in from every side; sparks spiralling down into it. It swells
-- out of the blast, swallows for as long as the server pulls, then crushes
-- to a point and pops. Another Burst landing on it (Empowered, an Echo)
-- feeds it: it grows.
local TEX_GLOW = "rbxassetid://1084982817"   -- (the pack's soft round glow)
local TEX_LINE = "rbxassetid://16953209220"  -- (the pack's portal lines: streaks)
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local HOLE_DISK = {
	{ r = 1.45, n = 16, w = 0.5, speed = 7.5, color = WHITE, tr = 0.05 },
	{ r = 2.0, n = 20, w = 0.62, speed = 4.8, color = PALE, tr = 0.12 },
	{ r = 2.7, n = 26, w = 0.75, speed = 3.0, color = VIOLET, tr = 0.22 },
	{ r = 3.5, n = 30, w = 0.7, speed = 1.9, color = DEEP, tr = 0.4 },
}
local HOLE_HALO = {
	{ r = 1.12, n = 24, w = 0.16, color = WHITE, tr = 0.05 },
	{ r = 1.3, n = 28, w = 0.1, color = VIOLET, tr = 0.35 },
}
local HOLE_GROW = 0.25
local HOLE_CRUSH = 0.3

type Hole = { owner: Player, pos: Vector3, h: number, want: number, endT: number, collapsing: boolean }
local holes: { Hole } = {}

local function popHole(pos: Vector3, h: number)
	flare(pos, h * 4, 0.16, WHITE)
	shell(pos, h * 1.2, h * 9, 0.4, PALE)
	shell(pos, h, h * 6, 0.3, VIOLET)
	PackFX.Burst("Anime/ForceField-Break-01", CFrame.new(pos), { color = VIOLET, scale = h / 1.6 })
	SwordFX.Rays(pos, h * 5, 12, PALE, 0.3)
	sparks(pos, 30, 34, PALE)
	ClassFX.Sound("magicBurst", pos, 0.6, 1.5)
end

local function spawnHole(owner: Player, pos: Vector3, radius: number, reach: number, life: number)
	local h = math.max(1.2, radius * 0.2)
	local t0 = os.clock()
	local center = CFrame.new(pos)
	local hole: Hole = { owner = owner, pos = pos, h = h, want = 1, endT = t0 + life, collapsing = false }
	table.insert(holes, hole)
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.1, CFrame = center, Color = Color3.new(0, 0, 0) })
	local rim = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.1, CFrame = center, Color = VIOLET,
		Material = Enum.Material.ForceField })
	-- the glow behind it, showing round its edge
	emitter(core, { Texture = TEX_GLOW, Color = ColorSequence.new(VIOLET, BLUE), LightEmission = 1, LockedToPart = true,
		Size = nseq(h * 5.2, h * 5.8), Transparency = nseq(0.35, 0.7), Lifetime = NumberRange.new(0.3), Rate = 14,
		Speed = NumberRange.new(0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90), ZOffset = -h * 1.6 })
	-- streaks and dust drawn in from every side (each reaching the edge as it fades)
	local well = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * reach * 1.6, CFrame = center, Transparency = 1 })
	local fall = math.max(reach * 0.8 - h, 2)
	emitter(well, { Texture = TEX_LINE, Color = ColorSequence.new(PALE, VIOLET), LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.4), Speed = NumberRange.new(fall / 0.4 * 0.95, fall / 0.4 * 1.05),
		Size = nseq(h * 0.55, h * 0.12), Rate = 50,
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.15), NumberSequenceKeypoint.new(1, 0) }) })
	emitter(well, { Texture = TEX_SPARKLE, Color = ColorSequence.new(PALE, BLUE), LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Lifetime = NumberRange.new(0.8),
		Speed = NumberRange.new(fall / 0.8 * 0.55, fall / 0.8), Size = nseq(0.4, 0), Transparency = nseq(0.2, 0.5), Rate = 36 })
	-- everything that moves, moved together each frame
	local moving: { BasePart } = {}
	-- the disk: rings of light round it, a few gaps so it reads as a whirl
	local dA, dR, dS = {}, {}, {}
	for _, ring in ipairs(HOLE_DISK) do
		local seg = 2 * math.pi * ring.r * h / ring.n * 1.12
		for k = 1, ring.n do
			if math.random() < 0.12 then continue end
			table.insert(moving, part({ Size = Vector3.new(seg, 0.06, ring.w * h / 1.7 * (0.8 + math.random() * 0.4)), Color = ring.color,
				Transparency = math.min(0.9, ring.tr + math.random() * 0.3), CFrame = center }))
			table.insert(dA, k / ring.n * math.pi * 2)
			table.insert(dR, ring.r)
			table.insert(dS, ring.speed)
		end
	end
	local nDisk = #moving
	-- the halo round its edge
	local hA, hR = {}, {}
	for _, ring in ipairs(HOLE_HALO) do
		local seg = 2 * math.pi * ring.r * h / ring.n * 1.1
		for k = 1, ring.n do
			table.insert(moving, part({ Size = Vector3.new(ring.w * h / 1.7, seg, 0.05), Color = ring.color, Transparency = ring.tr, CFrame = center }))
			table.insert(hA, k / ring.n * math.pi * 2)
			table.insert(hR, ring.r)
		end
	end
	local nHalo = #moving - nDisk
	-- sparks on tilted orbits, spiralling down into it
	local mA, mR, mI = {}, {}, {}
	for k = 1, 8 do
		table.insert(moving, part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.32, Color = if k % 2 == 0 then PALE else VIOLET, CFrame = center }))
		table.insert(mA, math.random() * math.pi * 2)
		table.insert(mR, 3 + math.random() * 2.5)
		table.insert(mI, CFrame.Angles(math.rad(math.random(-60, 60)), math.random() * math.pi * 2, 0))
	end
	if FxBudget.Light() then
		local l = Instance.new("PointLight")
		l.Color = VIOLET
		l.Brightness = 3
		l.Range = h * 9
		l.Parent = rim
		FxBudget.TrackLight(l)
	end
	local tilt = math.rad(14 + math.random() * 4)
	local tiltRoll = math.rad((math.random() * 2 - 1) * 14)
	local scale, spin, crushFrom = 0, 0, 1
	local cfs = table.create(#moving)
	animate(600, function(_, dt)
		local now = os.clock()
		if now >= hole.endT - HOLE_CRUSH then
			-- crushing to a point, whirling faster and faster
			if not hole.collapsing then
				hole.collapsing = true
				crushFrom = scale
			end
			local u = math.clamp((now - (hole.endT - HOLE_CRUSH)) / HOLE_CRUSH, 0, 1)
			scale = crushFrom * (1 - u * u)
			spin += dt * (2 + 8 * u)
			if u >= 1 then
				for _, p in ipairs(moving) do p:Destroy() end
				core:Destroy()
				rim:Destroy()
				for _, e in ipairs(well:GetChildren()) do
					if e:IsA("ParticleEmitter") then e.Enabled = false end
				end
				Debris:AddItem(well, 1)
				local i = table.find(holes, hole)
				if i then table.remove(holes, i) end
				popHole(pos, h * hole.want)
				return true
			end
		else
			-- opening (overshooting a little), then following what feeds it
			local u = math.clamp((now - t0) / HOLE_GROW, 0, 1)
			local open = 1 + 2.7 * (u - 1) ^ 3 + 1.7 * (u - 1) ^ 2
			scale = if u < 1 then hole.want * open else scale + (hole.want - scale) * math.min(dt * 8, 1)
			spin += dt
		end
		local sh = scale * h
		core.Size = Vector3.one * math.max(2 * sh, 0.05)
		rim.Size = Vector3.one * math.max(2.15 * sh * (1 + math.sin(now * 14) * 0.03), 0.05)
		-- the disk, seen almost edge-on from wherever you look (a little from
		-- above, a little askew, wobbling): its near side crosses in front of
		-- the sphere, its far side goes behind it
		local cam = Workspace.CurrentCamera
		local face = if cam then CFrame.lookAt(pos, cam.CFrame.Position) else center
		local base = face * CFrame.Angles(-tilt + math.sin(now * 1.3) * 0.05, 0, tiltRoll + math.sin(now * 0.9) * 0.06)
		for i = 1, nDisk do
			cfs[i] = base * CFrame.Angles(0, dA[i] + spin * dS[i], 0) * CFrame.new(0, 0, -dR[i] * sh)
		end
		for j = 1, nHalo do
			cfs[nDisk + j] = face * CFrame.Angles(0, 0, hA[j] + now * 0.6) * CFrame.new(hR[j] * sh, 0, 0)
		end
		for m = 1, #mA do
			mR[m] -= dt * (0.8 + 2.4 / mR[m])
			mA[m] += dt * 6 / mR[m]
			if mR[m] < 1.1 then
				mR[m] = 3.5 + math.random() * 2
				mI[m] = CFrame.Angles(math.rad(math.random(-60, 60)), math.random() * math.pi * 2, 0)
			end
			cfs[nDisk + nHalo + m] = center * mI[m] * CFrame.new(math.cos(mA[m]) * mR[m] * sh, 0, math.sin(mA[m]) * mR[m] * sh)
		end
		Workspace:BulkMoveTo(moving, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		return nil
	end)
end

-- The burst: a flash and a shell of light bursting out, lightning, a ring on
-- the floor, and the black hole torn open in the middle of it.
local function onBurstBoom(msg: any)
	local owner = msg.attacker :: Player
	local pos = msg.pos :: Vector3
	local floor = (msg.floor :: Vector3?) or ground(pos)
	local radius = tonumber(msg.radius) or 10
	local reach = tonumber(msg.reach) or radius * 1.4
	local life = tonumber(msg.life) or 1.2
	-- (it hangs a little over the floor)
	local at = Vector3.new(pos.X, math.max(pos.Y, floor.Y + 3.2), pos.Z)
	-- a Burst landing on one already open feeds it
	for _, hole in ipairs(holes) do
		if hole.owner == owner and not hole.collapsing and (hole.pos - at).Magnitude < hole.h * 2.5 then
			hole.want = math.min(hole.want * 1.22, 1.75)
			hole.endT = math.max(hole.endT, os.clock() + life)
			flare(hole.pos, radius * 0.8, 0.22)
			shell(hole.pos, 2, radius * 1.6, 0.3, VIOLET)
			sparks(hole.pos, 16, 22, PALE)
			ClassFX.Sound("magicBurst", hole.pos, 0.6, 1.0)
			if owner == player and deps then deps.shake(0.35, 0.12) end
			return
		end
	end
	flare(at, radius * 1.1, 0.3)
	flare(at, radius * 0.5, 0.18, WHITE)
	shell(at, 2, radius * 2.3, 0.4, VIOLET)
	shell(at, 1, radius * 1.4, 0.3, PALE)
	PackFX.Burst("Anime/Lighting-03", CFrame.new(at), { color = PALE, scale = radius / 6 })
	floorRing(floor, radius, 0.4)
	sparks(at, 26, 26)
	spawnHole(owner, at, radius, reach, life)
	ClassFX.Sound("magicBurst", at, 0.85, 0.85)
	ClassFX.Sound("boom", at, 0.45, 1.3)
	if owner == player and deps then
		deps.shake(0.55, 0.18)
		deps.fovPunch(4, 0.18)
	end
end

-- The runes left behind: a small circle glowing on the floor.
local runes: { [Player]: { [number]: Circle } } = {}

local function onRune(msg: any)
	local owner = msg.attacker :: Player
	local list = runes[owner] or {}
	runes[owner] = list
	local c = newCircle(CFrame.new((msg.pos :: Vector3) + Vector3.new(0, 0.12, 0)), 3.2, { glyphs = 6, speed = 1.2 })
	list[msg.id] = c
	fadeCircle(c, 0.85, 0.3)
end

local function runeGone(owner: Player, id: number, burst: boolean)
	local list = runes[owner]
	local c = list and list[id]
	if not c then return end
	list[id] = nil
	if burst then
		local p = c.cf.Position
		c.hot = 1
		flare(p + Vector3.new(0, 1, 0), 12, 0.35)
		PackFX.Burst("Big/Lighting-01", CFrame.new(p), { color = VIOLET, scale = 0.45 })
		sparks(p + Vector3.new(0, 1, 0), 22, 24, PALE)
	end
	dropCircle(c, if burst then 0.15 else 0.4)
end

-- ── F: Astral Prison ────────────────────────────────────────────────────────
-- The circle forms; at the chains moment, chains of light rise round its edge
-- (and round everyone caught in it); while it holds, it brightens toward
-- white as it charges; then the chains snap and it collapses.
type Prison = { circle: Circle, links: { BasePart }, pos: Vector3, radius: number, t0: number, hold: number, chains: number,
	dome: BasePart? }
local prisons: { [Player]: { [number]: Prison } } = {}

-- A chain of light from `a` to `b`, its links shooting out from `a` one
-- after another.
local function chainLine(list: { BasePart }, a: Vector3, b: Vector3, color: Color3, delay: number, step: number?)
	local d = b - a
	local len = d.Magnitude
	if len < 0.5 then return end
	local n = math.max(3, math.floor(len / 0.75))
	local look = CFrame.lookAt(a, b, if math.abs(d.Unit.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis)
	for i = 1, n do
		local turn = if i % 2 == 0 then CFrame.Angles(0, 0, math.rad(90)) else CFrame.identity
		local link = part({ Size = Vector3.new(0.4, 0.12, 0.82), Color = color, Transparency = 1,
			CFrame = look * CFrame.new(0, 0, -(i - 0.5) * len / n) * turn })
		table.insert(list, link)
		task.delay(delay + i * (step or 0.015), function()
			if link.Parent then link.Transparency = 0.15 end
		end)
	end
end

local function onPrison(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	if char then
		if owner ~= player then prisonPose(char) end
		bookCast(char, "raise", 0.7)
	end
	local pos = msg.pos :: Vector3
	local radius = tonumber(msg.radius) or 12
	local chains = tonumber(msg.chains) or 0.6
	local hold = tonumber(msg.hold) or 3
	local color = if msg.echo then BLUE else VIOLET
	local circle = newCircle(CFrame.new(pos + Vector3.new(0, 0.12, 0)), radius, { color = color, glyphs = 16, speed = 0.5 })
	-- (drawn in over the delay)
	fadeCircle(circle, 0.9, chains)
	local pr: Prison = { circle = circle, links = {}, pos = pos, radius = radius, t0 = os.clock(), hold = hold, chains = chains }
	local list = prisons[owner] or {}
	prisons[owner] = list
	list[msg.id] = pr
	floorRing(pos, radius, chains, color, 0.6)
	ClassFX.Sound("chime", pos, 0.6, 0.8)
	-- the chains rise round the edge, leaning in: a cage; a dome of light
	-- closes over it
	task.delay(chains, function()
		if list[msg.id] ~= pr then return end
		local n = math.clamp(math.floor(radius * 0.9), 8, 18)
		for k = 1, n do
			local a = k / n * math.pi * 2
			local out = Vector3.new(math.cos(a), 0, math.sin(a))
			chainLine(pr.links, pos + out * radius * 0.92, pos + out * radius * 0.5 + Vector3.new(0, 9 + math.random() * 4, 0), color, 0, 0.012)
		end
		local dome = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(pos), Color = color,
			Material = Enum.Material.ForceField })
		pr.dome = dome
		TweenService:Create(dome, TweenInfo.new(0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2 }):Play()
		floorRing(pos, radius * 1.1, 0.3, PALE, 1.2)
		sparks(pos + Vector3.new(0, 1, 0), 30, 20, color)
		ClassFX.Sound("chime", pos, 0.8, 0.6)
		if owner == player and deps then deps.shake(0.35, 0.15) end
		-- (charging: brighter and brighter toward the collapse; at the very
		-- end the dome crushes in on them)
		animate(hold, function(a)
			if list[msg.id] ~= pr then return end
			circle.hot = a * 0.7
			local jitter = math.sin(os.clock() * 40) * 0.04 * a
			for _, l in ipairs(pr.links) do
				if l.Parent then l.Transparency = 0.15 - a * 0.1 + jitter end
			end
			if dome.Parent and a > 0.15 then
				dome.Color = color:Lerp(PALE, a)
				local crush = math.clamp((a - 0.86) / 0.14, 0, 1)
				dome.Size = Vector3.one * radius * 2 * (1 - 0.65 * crush * crush) * (1 + math.sin(os.clock() * 9) * 0.015 * (1 - crush))
			end
		end)
	end)
end

-- Someone caught: chains wrap round them, ground to over their head.
local function onPrisonChain(msg: any)
	local list = prisons[msg.attacker]
	local pr = list and list[msg.id]
	local m = msg.model
	if not pr or typeof(m) ~= "Instance" then return end
	local r = (m :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
	if not r then return end
	-- chains shot from the floor round them, and one from above, binding them
	local chest = r.Position + Vector3.new(0, 0.5, 0)
	local spin = math.random() * math.pi * 2
	for k = 0, 2 do
		local a = spin + k / 3 * math.pi * 2
		local anchor = Vector3.new(r.Position.X + math.cos(a) * 3.6, pr.pos.Y + 0.1, r.Position.Z + math.sin(a) * 3.6)
		chainLine(pr.links, anchor, chest, PALE, k * 0.04, 0.018)
		flare(anchor, 1.6, 0.25, PALE)
	end
	chainLine(pr.links, chest + Vector3.new(0, 8, 0), chest + Vector3.new(0, 0.8, 0), PALE, 0.1, 0.018)
	flare(r.Position, 4, 0.2)
end

-- The collapse: the chains snap and fly, the circle crushes inward to a point,
-- then a massive explosion (and every rune inside goes up with it).
local function onPrisonCollapse(msg: any)
	local owner = msg.attacker :: Player
	local list = prisons[owner]
	local pr = list and list[msg.id]
	local pos = msg.pos :: Vector3
	local radius = tonumber(msg.radius) or 12
	if pr and list then
		list[msg.id] = nil
		for _, l in ipairs(pr.links) do
			if l.Parent then
				local away = flat(l.Position - pos)
				local v = away * (20 + math.random() * 20) + Vector3.new(0, 10 + math.random() * 20, 0)
				local p0 = l.Position
				animate(0.5, function(a, dt)
					v += Vector3.new(0, -60 * dt, 0)
					p0 += v * dt
					l.CFrame = CFrame.new(p0) * l.CFrame.Rotation * CFrame.Angles(dt * 8, dt * 5, 0)
					l.Transparency = a
					if a >= 1 then l:Destroy() end
				end)
			end
		end
		pr.circle.hot = 1
		dropCircle(pr.circle, 0.25)
		if pr.dome then pr.dome:Destroy() end
	end
	local up = pos + Vector3.new(0, 2, 0)
	shell(up, radius * 0.6, radius * 3, 0.45, PALE)
	shell(up, radius * 0.4, radius * 2.2, 0.35, VIOLET)
	flare(up, radius * 2.4, 0.45)
	flare(up, radius * 1.2, 0.25, WHITE)
	PackFX.Burst("Big/Explosion-01", CFrame.new(up), { color = VIOLET, scale = radius / 9, count = 0.6 })
	PackFX.Burst("Anime/ForceField-Break-01", CFrame.new(up), { color = PALE, scale = radius / 4 })
	SwordFX.Rays(up, radius * 1.6, 14, PALE, 0.4)
	floorRing(pos, radius * 1.3, 0.45, PALE, 1.4)
	floorRing(pos, radius * 0.8, 0.35, VIOLET, 1)
	sparks(up, 60, 40, PALE)
	for _, r in ipairs(msg.runes or {}) do runeGone(owner, r.id, true) end
	ClassFX.Sound("boom", pos, 1, 0.75)
	ClassFX.Sound("magicBurst", pos, 1, 0.6)
	if near(pos, 60) then flash(0.25, 0.55) end
	if owner == player and deps then
		deps.shake(1.0, 0.3)
		deps.fovPunch(7, 0.25)
	elseif near(pos, 60) and deps then
		deps.shake(0.4, 0.2)
	end
end

-- ── Q: Arcane Shift and the Echoes ──────────────────────────────────────────
-- An echo of him drawn in blue light: his body's pieces as glowing blue
-- copies, standing where he was, a small circle under it, motes rising.
type Echo = { parts: { BasePart }, rel: { CFrame }, base: CFrame, circle: Circle, alive: boolean }
local echoes: { [Player]: { [number]: Echo } } = {}

local function makeEcho(char: Model, at: Vector3, look: Vector3, life: number): Echo?
	local root = rootOf(char)
	if not root then return nil end
	local parts, rel = {}, {}
	local rootCF = root.CFrame
	local base = CFrame.lookAt(at + Vector3.new(0, root.Size.Y * 1.5, 0), at + Vector3.new(0, root.Size.Y * 1.5, 0) + look)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 0.9 and d.Size.Magnitude > 0.45
			and not d:FindFirstAncestor("ClothCape") and d.Name ~= "GrimoireCore" then
			local r = rootCF:ToObjectSpace(d.CFrame)
			local g = part({ Size = d.Size, Color = if math.random() < 0.15 then PALE else BLUE, Transparency = 1,
				Material = Enum.Material.ForceField, CFrame = base * r }, if d:IsA("WedgePart") then "WedgePart" else "Part")
			table.insert(parts, g)
			table.insert(rel, r)
		end
	end
	local circle = newCircle(CFrame.new(at + Vector3.new(0, 0.12, 0)), 2.6, { color = BLUE, glyphs = 6, star = false, speed = 1.4 })
	local e: Echo = { parts = parts, rel = rel, base = base, circle = circle, alive = true }
	fadeCircle(circle, 0.8, 0.25)
	animate(0.25, function(a)
		for _, p in ipairs(parts) do p.Transparency = 1 - 0.75 * a end
	end)
	-- (hovering a little, motes drifting off it)
	animate(life + 0.5, function(_, _dt)
		if not e.alive then return true end
		local t = os.clock()
		local cf = e.base + Vector3.new(0, math.sin(t * 2.4) * 0.15, 0)
		local cfs = table.create(#parts)
		for i, r in ipairs(rel) do cfs[i] = cf * r end
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if FxBudget.Allow("mageEchoMote", 10) then sparks(at + Vector3.new(0, 2 + math.random() * 2, 0), 1, 2, BLUE) end
		return nil
	end)
	return e
end

local function echoFade(e: Echo, shatter: boolean)
	if not e.alive then return end
	e.alive = false
	dropCircle(e.circle, 0.3)
	local at = e.base.Position
	if shatter then
		sparks(at, 24, 18, BLUE)
		PackFX.Burst("Anime/Shield-Break-01", CFrame.new(at), { color = BLUE, scale = 0.8, count = 0.4 })
	end
	animate(0.3, function(a)
		for _, p in ipairs(e.parts) do p.Transparency = 0.25 + 0.75 * a end
		if a >= 1 then
			for _, p in ipairs(e.parts) do p:Destroy() end
		end
	end)
end

-- The shift: he phases out (a blue afterimage breaking up, a portal),
-- a streak of light to where he's gone, he phases in, and the shockwave.
local function onShift(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	local from = msg.from :: Vector3
	local to = msg.to :: Vector3
	local radius = tonumber(msg.radius) or 10
	local dir = flat(to - from)
	if char and owner ~= player then shiftPose(char) end
	if char then bookCast(char, "read", 0.3) end
	PackFX.Burst("Anime/Portal-Enter-01", CFrame.new(ground(from) + Vector3.new(0, 0.2, 0)) * FLOOR_UP, { color = BLUE, scale = 0.9 })
	shell(from, 7, 0.3, 0.2, BLUE)
	sparks(from, 20, 16, BLUE)
	for k = -1, 1 do
		local off = Vector3.new(-dir.Z, 0, dir.X) * k * 0.8 + Vector3.new(0, 0.5 + math.abs(k) * 0.4, 0)
		streak(from + off, to + off, 0.4 - math.abs(k) * 0.15, 0.3, if k == 0 then PALE else BLUE)
	end
	ClassFX.Sound("whoosh", from, 0.7, 1.4)
	task.delay(SHIFT_WAVE, function()
		local g = ground(to)
		PackFX.Burst("Anime/Portal-01", CFrame.new(g + Vector3.new(0, 0.2, 0)) * FLOOR_UP, { color = BLUE, scale = 1.1 })
		flare(to, radius * 1.4, 0.3, PALE)
		shell(to, 2, radius * 2.2, 0.35, BLUE)
		shell(to, 1, radius * 1.4, 0.25, PALE)
		floorRing(g, radius, 0.35, BLUE, 1.1)
		floorRing(g, radius * 0.6, 0.3, PALE, 0.6)
		PackFX.Burst("Anime/Lighting-03", CFrame.new(to), { color = BLUE, scale = radius / 6 })
		sparks(to, 30, 30, BLUE)
		ClassFX.Sound("magicBurst", to, 0.8, 1.1)
		if owner == player and deps then
			deps.shake(0.5, 0.15)
			deps.fovPunch(6, 0.2)
		end
	end)
	-- the echoes left behind
	local list = echoes[owner] or {}
	echoes[owner] = list
	if char then
		for _, e in ipairs(msg.echoes or {}) do
			local made = makeEcho(char, e.pos, dir, tonumber(msg.life) or 8)
			if made then list[e.id] = made end
		end
	end
end

local function onEchoGone(msg: any)
	local list = echoes[msg.attacker]
	local e = list and list[msg.id]
	if not e then return end
	list[msg.id] = nil
	echoFade(e, true)
end

-- An echo casting: it flares, a burst of blue at its hand toward the aim.
local function onEchoCast(msg: any)
	local list = echoes[msg.attacker]
	local e = list and list[msg.id]
	local at = (msg.pos :: Vector3) + Vector3.new(0, 3, 0)
	if e then
		for _, p in ipairs(e.parts) do
			p.Color = PALE
			TweenService:Create(p, TweenInfo.new(0.3), { Color = BLUE }):Play()
		end
	end
	flare(at, 5, 0.25, BLUE)
	sparks(at, 14, 14, BLUE)
	if msg.skill == 3 then
		task.delay(SHIFT_WAVE, function()
			local g = ground(msg.pos)
			floorRing(g, 8, 0.3, BLUE, 0.9)
			flare(g + Vector3.new(0, 1, 0), 10, 0.25, BLUE)
		end)
	end
end

-- ── R: Apocalypse ───────────────────────────────────────────────────────────
-- The sky circle opens above him, every enemy marked with a sigil of light,
-- a storm of bolts falls, then every mark detonates.
type Apoc = { sky: Circle, floor: Circle, layers: { Circle }, beam: { BasePart }, marks: { [Model]: { BasePart } }, alive: boolean }
local apocs: { [Player]: Apoc } = {}

local function clearMarks(ap: Apoc)
	for _, list in pairs(ap.marks) do
		for _, p in ipairs(list) do p:Destroy() end
	end
	table.clear(ap.marks)
end

local function onApoc(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	local pos = msg.pos :: Vector3
	local radius = tonumber(msg.radius) or 45
	if char then
		if owner ~= player then apocPose(char) end
		bookCast(char, "sky", ULT_TOTAL - 0.2)
	end
	local old = apocs[owner]
	if old then
		clearMarks(old)
		dropCircle(old.sky, 0.1)
		dropCircle(old.floor, 0.1)
		for _, l in ipairs(old.layers) do dropCircle(l, 0.1) end
		for _, b in ipairs(old.beam) do b:Destroy() end
	end
	-- (facing down at the battlefield, high over it)
	local sky = newCircle(CFrame.new(pos + Vector3.new(0, 30, 0)) * CFrame.Angles(math.pi, 0, 0), radius * 0.62,
		{ color = VIOLET, glyphs = 24, speed = 0.35 })
	local floorC = newCircle(CFrame.new(pos + Vector3.new(0, 0.15, 0)), radius, { color = DEEP, glyphs = 20, speed = -0.2 })
	-- two smaller circles stacked under it, narrowing down toward him, each
	-- turning its own way: the array
	local mid = newCircle(CFrame.new(pos + Vector3.new(0, 22, 0)) * CFrame.Angles(math.pi, 0, 0), radius * 0.3,
		{ color = PALE, glyphs = 12, speed = -0.9 })
	local low = newCircle(CFrame.new(pos + Vector3.new(0, 15, 0)) * CFrame.Angles(math.pi, 0, 0), radius * 0.14,
		{ color = VIOLET, glyphs = 8, speed = 1.8 })
	-- (see-through: the array hangs between the camera and the fight)
	fadeCircle(sky, 0.55, 0.8)
	fadeCircle(floorC, 0.5, 0.8)
	task.delay(0.15, function() fadeCircle(mid, 0.6, 0.5) end)
	task.delay(0.3, function() fadeCircle(low, 0.75, 0.4) end)
	-- a column of light from the book, up through the array to the sky
	local beam: { BasePart } = {}
	local root = rootOf(char)
	if root then
		local bottom = root.Position + Vector3.new(0, 4.6, 0)
		local top = pos + Vector3.new(0, 30, 0)
		local len = (top - bottom).Magnitude
		local cf = CFrame.lookAt((bottom + top) / 2, top) * CFrame.Angles(0, math.rad(90), 0)
		local inner = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 0.1, 0.1), CFrame = cf, Color = WHITE, Transparency = 0.05 })
		local outer = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(len, 0.1, 0.1), CFrame = cf, Color = VIOLET, Transparency = 0.55 })
		beam = { inner, outer }
		animate(ULT_TOTAL, function(a)
			if not inner.Parent then return true end
			local w = math.min(a / 0.08, 1) * (1 + math.sin(os.clock() * 30) * 0.12)
			inner.Size = Vector3.new(len, 0.5 * w, 0.5 * w)
			outer.Size = Vector3.new(len, 1.5 * w, 1.5 * w)
			if a >= 1 then
				inner:Destroy()
				outer:Destroy()
			end
			return nil
		end)
	end
	local ap: Apoc = { sky = sky, floor = floorC, layers = { mid, low }, beam = beam, marks = {}, alive = true }
	apocs[owner] = ap
	if owner == player or near(pos, radius + 30) then tint(ULT_TOTAL + 0.3) end
	ClassFX.Sound("choir", pos, 0.6, 0.8)
	ClassFX.Sound("charge", pos, 0.35, 0.6)
end

-- A mark: a ring of light round the chest, a line of light rising from the
-- head to a diamond, a crosshair across the ring.
local function onApocMarks(msg: any)
	local ap = apocs[msg.attacker]
	if not ap then return end
	for _, m in ipairs(msg.models or {}) do
		if typeof(m) ~= "Instance" then continue end
		local r = (m :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
		if not r then continue end
		local parts: { BasePart } = {}
		local n = 10
		for k = 1, n do
			table.insert(parts, part({ Size = Vector3.new(0.12, 0.12, 0.85), Color = Color3.fromRGB(255, 150, 230), Transparency = 1 }))
		end
		table.insert(parts, part({ Size = Vector3.new(0.14, 6, 0.14), Color = PALE, Transparency = 1 }))     -- the line up
		table.insert(parts, part({ Size = Vector3.new(0.5, 0.5, 0.12), Color = Color3.fromRGB(255, 150, 230), Transparency = 1 })) -- the diamond
		table.insert(parts, part({ Size = Vector3.new(3.6, 0.1, 0.1), Color = PALE, Transparency = 1 }))     -- the crosshair
		table.insert(parts, part({ Size = Vector3.new(0.1, 3.6, 0.1), Color = PALE, Transparency = 1 }))
		ap.marks[m :: Model] = parts
		local t0 = os.clock()
		animate(ULT_TOTAL, function(a)
			if not ap.marks[m :: Model] or not r.Parent then return end
			local cam = Workspace.CurrentCamera
			local c = r.Position + Vector3.new(0, 0.6, 0)
			local face = if cam then CFrame.lookAt(c, Vector3.new(cam.CFrame.Position.X, c.Y, cam.CFrame.Position.Z)) else CFrame.new(c)
			local tr = math.max(0.1, 1 - (os.clock() - t0) * 5)
			local spin = (os.clock() - t0) * 1.5
			for k = 1, n do
				local ang = k / n * math.pi * 2 + spin
				parts[k].CFrame = face * CFrame.new(math.cos(ang) * 1.9, math.sin(ang) * 1.9, 0) * CFrame.Angles(0, 0, ang) * CFrame.Angles(0, math.rad(90), 0)
				parts[k].Transparency = tr
			end
			parts[n + 1].CFrame = CFrame.new(c + Vector3.new(0, 5.5, 0))
			parts[n + 2].CFrame = CFrame.new(c + Vector3.new(0, 8.8, 0)) * face.Rotation * CFrame.Angles(0, 0, math.rad(45))
			parts[n + 3].CFrame = face
			parts[n + 4].CFrame = face
			for k = n + 1, n + 4 do parts[k].Transparency = tr + 0.15 end
			if a >= 1 then
				for _, p in ipairs(parts) do if p.Parent then p:Destroy() end end
			end
		end)
	end
	ClassFX.Sound("ding", rootOf(charOf(msg.attacker)) or Vector3.zero, 0.5, 0.8)
end

-- One bolt of the rain: a streak of light from the sky circle down to `pos`.
local function onApocBolt(msg: any)
	if not FxBudget.Allow("mageRain", 30) then return end
	local pos = msg.pos :: Vector3
	local top = pos + Vector3.new(math.random() * 6 - 3, 28, math.random() * 6 - 3)
	local dir = (pos - top).Unit
	local len = 7
	local body = part({ Size = Vector3.new(0.45, 0.45, len), Color = VIOLET, Transparency = 0.2 })
	local core = part({ Size = Vector3.new(0.18, 0.18, len), Color = WHITE })
	animate(0.12, function(a)
		local p = top:Lerp(pos, a)
		body.CFrame = CFrame.lookAt(p - dir * len * 0.5, p)
		core.CFrame = body.CFrame
		if a >= 1 then
			body:Destroy()
			core:Destroy()
			if FxBudget.Allow("mageRainHit", 24) then
				flare(pos + Vector3.new(0, 0.6, 0), 5, 0.22)
				floorRing(pos, 3.5, 0.25, VIOLET, 0.5)
				sparks(pos + Vector3.new(0, 0.5, 0), 6, 14, PALE)
			end
		end
	end)
end

-- Every mark at once: a column of light and lightning out of each, rays of
-- light bursting out, a shockwave over the whole battlefield, the sky
-- circle flaring white and gone.
local function onApocDetonate(msg: any)
	local owner = msg.attacker :: Player
	local ap = apocs[owner]
	local pos = msg.pos :: Vector3
	local radius = tonumber(msg.radius) or 45
	if ap then
		apocs[owner] = nil
		clearMarks(ap)
		ap.sky.hot = 1
		ap.floor.hot = 1
		dropCircle(ap.sky, 0.5)
		dropCircle(ap.floor, 0.5)
		for _, l in ipairs(ap.layers) do
			l.hot = 1
			dropCircle(l, 0.35)
		end
		for _, b in ipairs(ap.beam) do
			if b.Parent then
				b.Color = WHITE
				TweenService:Create(b, TweenInfo.new(0.3), { Transparency = 1, Size = b.Size * Vector3.new(1, 4, 4) }):Play()
				Debris:AddItem(b, 0.32)
			end
		end
	end
	for k, b in ipairs(msg.blasts or {}) do
		local p = (b.pos :: Vector3) + Vector3.new(0, 1, 0)
		local big = k <= 6
		if big or FxBudget.Allow("mageDetonate", 12) then
			flare(p, 14, 0.4)
			flare(p, 6, 0.2, WHITE)
			PackFX.Burst("Big/Lighting-01", CFrame.new(p), { color = VIOLET, scale = 0.6 })
			SwordFX.Rays(p, 12, 10, PALE, 0.35)
			streak(p - Vector3.new(0, 2, 0), p + Vector3.new(0, 20, 0), 1.2, 0.35, PALE)
			sparks(p, 24, 34, PALE)
		end
	end
	local g = ground(pos)
	-- a dome of light swelling over the whole battlefield
	shell(g, 6, radius * 2.2, 0.75, VIOLET)
	shell(g, 3, radius * 1.4, 0.5, PALE)
	floorRing(g, radius, 0.6, PALE, 2)
	floorRing(g, radius * 0.6, 0.5, VIOLET, 1.4)
	ClassFX.Sound("boom", pos, 1, 0.6)
	ClassFX.Sound("magicBurst", pos, 1, 0.5)
	ClassFX.Sound("thunder", pos, 0.6, 1.1)
	if owner == player or near(pos, radius + 20) then flash(0.45, 0.25) end
	if owner == player and deps then
		deps.shake(1.6, 0.45)
		deps.fovPunch(12, 0.35)
	elseif near(pos, radius + 20) and deps then
		deps.shake(0.7, 0.3)
	end
end

-- ── Arcane Charge: full, spent ──────────────────────────────────────────────
local function onChargeFull(msg: any)
	local root = rootOf(charOf(msg.attacker))
	if not root then return end
	floorRing(ground(root.Position), 5, 0.35, VIOLET, 0.6)
	sparks(root.Position, 16, 10, PALE)
	if msg.attacker == player then ClassFX.Sound("ding", root, 0.5, 1.2) end
end

local function onEmpowered(msg: any)
	local root = rootOf(charOf(msg.attacker))
	if not root then return end
	PackFX.Burst("Anime/Charge-01", root.CFrame, { color = VIOLET, scale = 1.1 })
	flare(root.Position, 9, 0.3)
	sparks(root.Position + Vector3.new(0, 1, 0), 30, 18, PALE)
	SwordFX.Spiral(function() return if root.Parent then root.Position - Vector3.new(0, 2.5, 0) else nil end, 3, 0.6, VIOLET)
end

-- While a Mage's Charge is full (every Mage, every client: MG_Charge).
type Aura = { circle: Circle, att: Attachment? }
local auras: { [Player]: Aura } = {}

local function stepAuras()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local root = if isMage(p) and (tonumber(p:GetAttribute("MG_Charge")) or 0) >= CHARGE_MAX then rootOf(char) else nil
		local a = auras[p]
		if root and char and not a then
			local c = newCircle(CFrame.new(root.Position - Vector3.new(0, 2.95, 0)), 3.4, { color = VIOLET, glyphs = 8, speed = 1.2 })
			fadeCircle(c, 0.7, 0.3)
			local att: Attachment? = nil
			local arm = char:FindFirstChild("Right Arm")
			if arm then
				att = Instance.new("Attachment")
				att.Name = "MageEmpowered"
				att.Position = Vector3.new(0, -1.05, 0)
				att.Parent = arm
				emitter(att :: Attachment, { Texture = TEX_SPARKLE, Color = ColorSequence.new(PALE, VIOLET), LightEmission = 1,
					Size = nseq(0.35, 0), Transparency = nseq(0, 1), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1, 3),
					SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 4, 0), Rate = 24 })
			end
			a = { circle = c, att = att }
			auras[p] = a
		elseif not root and a then
			dropCircle(a.circle, 0.3)
			if a.att then a.att:Destroy() end
			auras[p] = nil
			a = nil
		end
		if root and a then a.circle.cf = CFrame.new(root.Position - Vector3.new(0, 2.95, 0)) end
	end
	for p, a in pairs(auras) do
		if not p.Parent then
			dropCircle(a.circle, 0.1)
			auras[p] = nil
		end
	end
end

local HANDLERS: { [string]: (any) -> () } = {
	bolt = onBolt,
	boltEnd = function(_msg) end, -- (each client judges its own bolt's end)
	burstCast = onBurstCast,
	burstEnd = onBurstEnd,
	burstBoom = onBurstBoom,
	rune = onRune,
	runeGone = function(msg) runeGone(msg.attacker, msg.id, false) end,
	prison = onPrison,
	prisonChain = onPrisonChain,
	prisonCollapse = onPrisonCollapse,
	shift = onShift,
	echoGone = onEchoGone,
	echoCast = onEchoCast,
	apoc = onApoc,
	apocMarks = onApocMarks,
	apocBolt = onApocBolt,
	apocDetonate = onApocDetonate,
	chargeFull = onChargeFull,
	empowered = onEmpowered,
}

-- ── HUD: Arcane Charge ──────────────────────────────────────────────────────
-- Five pips over the skill bar (each one 20 Charge), the count beside them;
-- full, they blaze and it reads EMPOWERED.
local hud: ScreenGui? = nil
local pips: { Frame } = {}
local countLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil

local function charge(): number
	return tonumber(player:GetAttribute("MG_Charge")) or 0
end

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "MageCharge"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -132)
	row.Size = UDim2.fromOffset(250, 22)
	row.BackgroundTransparency = 1
	row.Parent = g
	for k = 1, 5 do
		local p = Instance.new("Frame")
		p.Name = "Pip" .. k
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.new(0, 10 + (k - 1) * 28, 0.5, 0)
		p.Size = UDim2.fromOffset(18, 18)
		p.BackgroundColor3 = Color3.fromRGB(20, 16, 40)
		p.BorderSizePixel = 0
		p.Parent = row
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = p
		local s = Instance.new("UIStroke")
		s.Color = VIOLET
		s.Thickness = 1.5
		s.Parent = p
		table.insert(pips, p)
	end
	local n = Instance.new("TextLabel")
	n.AnchorPoint = Vector2.new(0, 0.5)
	n.Position = UDim2.new(0, 152, 0.5, 0)
	n.Size = UDim2.fromOffset(100, 20)
	n.BackgroundTransparency = 1
	n.Font = Enum.Font.Arcade
	n.TextSize = 18
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.TextColor3 = PALE
	n.TextStrokeColor3 = Color3.new(0, 0, 0)
	n.TextStrokeTransparency = 0.3
	n.Text = "0 / 100"
	n.Parent = row
	countLabel = n
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 0, -4)
	t.Size = UDim2.fromOffset(280, 20)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Arcade
	t.TextSize = 18
	t.TextColor3 = Color3.fromRGB(200, 180, 240)
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.TextStrokeTransparency = 0.3
	t.Text = "ARCANE CHARGE"
	t.Parent = row
	titleLabel = t
end

local function refreshHud()
	if not hud then return end
	hud.Enabled = isMage() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	local c = charge()
	local full = c >= CHARGE_MAX
	for k, p in ipairs(pips) do
		local lit = c >= k * 20
		p.BackgroundColor3 = if full then PALE elseif lit then VIOLET else Color3.fromRGB(20, 16, 40)
	end
	if countLabel then
		local txt = `{math.floor(c)} / {CHARGE_MAX}`
		if countLabel.Text ~= txt then countLabel.Text = txt end
	end
	if titleLabel then
		local txt = if full then "EMPOWERED: NEXT ABILITY" else "ARCANE CHARGE"
		if titleLabel.Text ~= txt then titleLabel.Text = txt end
		titleLabel.TextColor3 = if full then PALE else Color3.fromRGB(200, 180, 240)
	end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
function MageController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	if now - lastBolt < BOLT_INTERVAL / speed then return true end
	lastBolt = now
	local dir = flat(deps.getAim(root))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	boltPose(char)
	bookCast(char, "read", 0.35)
	-- (ours leave our hand now; the server sends everyone else theirs)
	local origin = root.Position + dir * 1.4 + Vector3.new(0, 0.6, 0)
	local aim = boltAim(origin, dir)
	local count = 1 + math.max(0, math.floor(tonumber(player:GetAttribute("Stat_projectileCount")) or 0))
	local boltSpeed = BOLT_SPEED * (tonumber(player:GetAttribute("Stat_projectileSpeed")) or 1)
	for k = 1, count do
		local a = (k - (count + 1) / 2) * BOLT_FAN
		local d = flat((CFrame.Angles(0, a, 0) * CFrame.new(Vector3.zero, aim)).LookVector)
		fireBolt(origin, d, boltSpeed)
	end
	flare(origin, 2.4, 0.15)
	handSigil(origin, aim)
	ClassFX.Sound("poof", root, 0.45, 1.3)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function MageController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

-- Returns where the skill is aimed (sent to the server).
function MageController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any, cursor: Vector3?): Vector3?
	local dir = flat(aimDir)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local range = config.range or 40
	local target = root.Position + dir * range
	if cursor then
		local d = Vector3.new(cursor.X - root.Position.X, 0, cursor.Z - root.Position.Z)
		target = root.Position + (if d.Magnitude > range then d.Unit * range else d)
		target = Vector3.new(target.X, cursor.Y, target.Z)
	end
	if skillIndex == 1 then
		char:SetAttribute("AllowSkillMovement", true)
		burstPose(char)
		bookCast(char, "read", 0.5)
		releaseAfter(char, 0.3)
		return target
	elseif skillIndex == 2 then
		char:SetAttribute("AllowSkillMovement", true)
		prisonPose(char)
		bookCast(char, "raise", 0.7)
		releaseAfter(char, 0.4)
		return target
	elseif skillIndex == 3 then
		-- Arcane Shift: there in the same frame (walls and ledges stop it short).
		char:SetAttribute("AllowSkillMovement", false)
		local hum = char:FindFirstChildOfClass("Humanoid")
		local want = math.min(Vector3.new(target.X - root.Position.X, 0, target.Z - root.Position.Z).Magnitude, SHIFT_RANGE)
		local stand = SafeMove.StandHeight(root)
		local start = root.CFrame
		local dist = math.min(SafeMove.ClampDash(root, dir, want), SafeMove.ClampToFloor(root, dir, want))
		local at = root.Position + dir * dist
		root.CFrame = CFrame.lookAt(at, at + dir)
		root.AssemblyLinearVelocity = Vector3.new(0, math.max(root.AssemblyLinearVelocity.Y, 0), 0)
		SafeMove.SnapToFloor(root, stand)
		if not SafeMove.HasFloor(root) then
			root.CFrame = start
			root.AssemblyLinearVelocity = Vector3.zero
		end
		if hum then hum.AutoRotate = false end
		task.delay(0.15, function() if hum then hum.AutoRotate = true end end)
		shiftPose(char)
		if deps then deps.fovPunch(8, 0.22) end
		busyUntil = os.clock() + 0.12
		releaseAfter(char, 0.15)
		return root.Position
	elseif skillIndex == 4 then
		-- Apocalypse: rooted, arms to the sky, until every mark has gone off.
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = os.clock() + ULT_TOTAL
		apocPose(char)
		bookCast(char, "sky", ULT_TOTAL - 0.2)
		releaseAfter(char, ULT_TOTAL)
		return root.Position
	end
	return nil
end

-- The Apocalypse's opening, seen close: low, looking up past him at the sky.
function MageController.PlayUltCutscene(char: Model, dir: Vector3)
	UltimateCameraChoreography.PlayCloseUp(char, dir, 0.8, nil, nil, {
		startOffset = { 7, -2, 1 },
		endOffset = { 10, -3, 2.5 },
		focusHeight = 3,
		fovStart = 52,
		fovEnd = 66,
	})
end

function MageController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	RunService.RenderStepped:Connect(function(dt)
		stepAuras()
		stepAnims(dt)
	end)
	-- (the books bob after the animation and poses have written the frame)
	CastPoses.addPostHook(stepBooks)
	for _, a in ipairs({ "MG_Charge", "SelectedClass", "InLobby", "SettingsOpen" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshHud)
	end
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		lastBolt = 0
	end)
	Network.GetRemoteEvent(Network.Remotes.MageFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[MageController]", msg.kind, err) end
		end
	end)
end

return MageController
