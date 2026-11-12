--!strict
--[[
	RoninStorm.luau
	The Ronin's ult on screen (client only; damage stays on RoninServer).
	Space around the Ronin cracks like a mirror, then fills with waves of thin
	white-blue cuts. On the sheathe click they all blow apart in one flash.

		local s = RoninStorm.Begin(char, center, { radius = 30, cinematic = true })
		s.Unleash()   -- the cut waves start (the slash_storm beat)
		s.Finish()    -- the sheathe click: flash, cuts burst, the shards shatter, it all fades
		s.Cancel()    -- cut short: everything fades out

	The pieces:
	  • Panes: triangular glass shards (two WedgeParts each, pooled) floating at
	    every depth around and above the Ronin. Pale glass and black mirror
	    "voids" are mixed together; some have bright edges, and cracks join near
	    neighbours.
	  • Floor: a reflective black glass disc with bright cracks across it.
	  • Cuts: long straight neon lines criss-crossing the space (a see-through
	    cyan glow bar round a white core bar, both Neon parts). Each one is
	    drawn end to end in a few frames, then hangs until the click.
	  • Grade: a cold blue-black colour grade, extra bloom, a blur pulse on
	    each wave, a dark vignette and a faint red/cyan fringe at the screen edges.
	  • Camera (caster only): a low close-up through the build-up, then a wide,
	    low shot from behind, slowly orbiting through the storm.

	Performance (CLAUDE.md): one RenderStepped drives a whole storm. Panes move
	with one BulkMoveTo, and so do the cuts still being drawn or bursting.
	Every cut and pane asks FxBudget first, and the counts shrink with frame
	pressure.
--]]

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local PackFX = require(script.Parent:WaitForChild("PackFX"))

local player = Players.LocalPlayer

local RoninStorm = {}

local BLUE = Color3.fromRGB(150, 225, 255)
local ICE = Color3.fromRGB(200, 228, 255)
local WHITE = Color3.new(1, 1, 1)
local INK = Color3.fromRGB(8, 8, 14)
local VOID = Color3.fromRGB(5, 7, 13)

export type Config = {
	radius: number?,       -- how far the storm reaches (studs)
	cinematic: boolean?,   -- take the camera (the caster)
	grade: boolean?,       -- the colour grade and screen treatment (the caster and anyone close)
	build: number?,        -- seconds from Begin to the space being fully cracked
	waves: number?,        -- how many waves of cuts
	waveGap: number?,      -- seconds between waves
	perWave: number?,      -- cuts per wave
	waveSpread: number?,   -- seconds over which one wave's cuts land
	panes: number?,        -- shards by the end
	stormLength: number?,  -- seconds from Unleash to the click (for the camera's orbit)
	maxLife: number?,      -- safety: everything fades by then even with no click
}

RoninStorm.DEFAULTS = {
	radius = 30,
	build = 0.9,
	waves = 5,
	waveGap = 0.48,
	perWave = 30,
	waveSpread = 0.32,
	panes = 30,
	stormLength = 2.48,
	maxLife = 8,
}

local function cfg(c: Config?, k: string): any
	local v = c and (c :: any)[k]
	if v == nil then v = (RoninStorm.DEFAULTS :: any)[k] end
	return v
end

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

local function randUnit(): Vector3
	local z = rand(-1, 1)
	local a = rand(0, math.pi * 2)
	local r = math.sqrt(1 - z * z)
	return Vector3.new(r * math.cos(a), z, r * math.sin(a))
end

local function groundAt(p: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(ex, pl.Character) end end
	params.FilterDescendantsInstances = ex
	local hit = Workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position else p - Vector3.new(0, 3, 0)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Pools
-- ═════════════════════════════════════════════════════════════════════════════
local folder: Folder? = nil
local function fxFolder(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "RoninStormFX"
	f.Parent = Workspace
	folder = f
	return f
end

local wedgePool: { WedgePart } = {}
local function takeWedge(): WedgePart
	local w = table.remove(wedgePool)
	if not w then
		w = Instance.new("WedgePart")
		w.Name = "Pane"
		w.Anchored, w.CanCollide, w.CanQuery, w.CanTouch = true, false, false, false
		w.CastShadow = false
		w.TopSurface, w.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	end
	return w :: WedgePart
end
local function giveWedge(w: WedgePart)
	for _, ch in ipairs(w:GetChildren()) do ch:Destroy() end
	w.Parent = nil
	if #wedgePool < 160 then table.insert(wedgePool, w) else w:Destroy() end
end

local function att(parent: Instance, pos: Vector3?): Attachment
	local a = Instance.new("Attachment")
	a.Name = "RoninStorm"
	if pos then a.Position = pos end
	a.Parent = parent
	return a
end

local function beam(a0: Attachment, a1: Attachment, color: Color3, width: number, emit: number): Beam
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = true
	b.LightEmission, b.LightInfluence = emit, 0
	b.Segments = 1
	b.Color = ColorSequence.new(color)
	b.Width0, b.Width1 = width, width
	b.Parent = a0
	return b
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Panes: a triangle out of two wedges, in the pane's own space
-- ═════════════════════════════════════════════════════════════════════════════
-- (returns each wedge's size and its CFrame relative to the pane's centre)
local function triangle(a: Vector3, b: Vector3, c: Vector3, thick: number): (Vector3, CFrame, Vector3, CFrame)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local s0 = Vector3.new(thick, height, math.abs(ab:Dot(back)))
	local c0 = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local s1 = Vector3.new(thick, height, math.abs(ac:Dot(back)))
	local c1 = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	return s0, c0, s1, c1
end

type Pane = {
	w0: WedgePart, w1: WedgePart, c0: CFrame, c1: CFrame,
	cf: CFrame, vel: Vector3, spinAxis: Vector3, spin: number,
	alpha: number, t0: number, verts: { Attachment },
	edges: { Beam }, boom: number?,
}

-- ═════════════════════════════════════════════════════════════════════════════
-- Cuts: thin straight lines that hang
-- ═════════════════════════════════════════════════════════════════════════════
-- (neon parts, not beams: a beam this long and thin reads as a hairline on
-- screen, a neon bar glows and blooms like the lit tube it's meant to be)
type Cut = {
	core: BasePart, glow: BasePart,
	from: Vector3, to: Vector3, width: number, t0: number, draw: number,
	boom: number?, phase: number, glowT: number,
}
local CUT_FLARE, CUT_FADE = 0.07, 0.24

local function neonBar(color: Color3, transparency: number, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = "RoninCut"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Size = Vector3.new(0.05, 0.05, 0.05)
	p:SetAttribute("VfxToned", true)
	p.Parent = parent
	return p
end

-- a bar of cross-section `w` from `a` to `b`, rolled a little so the square
-- edge never faces the camera flat
local function barCF(a: Vector3, b: Vector3): CFrame
	local mid = (a + b) / 2
	if (b - a).Magnitude < 0.01 then return CFrame.new(mid) end
	return CFrame.lookAt(mid, b) * CFrame.Angles(0, 0, math.rad(45))
end

-- ═════════════════════════════════════════════════════════════════════════════
-- The grade (one at a time; the newest storm owns it)
-- ═════════════════════════════════════════════════════════════════════════════
type Grade = { cc: ColorCorrectionEffect, bloom: BloomEffect, blur: BlurEffect, gui: ScreenGui,
	fringe: { Frame }, vignette: { Frame } }

local function edge(parent: Instance, name: string, color: Color3, side: string, size: number, rot: number): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1
	if side == "L" then
		f.Size, f.Position = UDim2.fromScale(size, 1), UDim2.fromScale(0, 0)
	elseif side == "R" then
		f.Size, f.Position = UDim2.fromScale(size, 1), UDim2.fromScale(1 - size, 0)
	elseif side == "T" then
		f.Size, f.Position = UDim2.fromScale(1, size), UDim2.fromScale(0, 0)
	else
		f.Size, f.Position = UDim2.fromScale(1, size), UDim2.fromScale(0, 1 - size)
	end
	local g = Instance.new("UIGradient")
	g.Rotation = rot
	g.Transparency = NumberSequence.new(0, 1)
	g.Parent = f
	f.Parent = parent
	return f
end

local function makeGrade(): Grade
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "RoninStormGrade"
	cc.Parent = Lighting
	local bloom = Instance.new("BloomEffect")
	bloom.Name = "RoninStormBloom"
	bloom.Intensity, bloom.Size, bloom.Threshold = 0, 32, 0.9
	bloom.Parent = Lighting
	local blur = Instance.new("BlurEffect")
	blur.Name = "RoninStormBlur"
	blur.Size = 0
	blur.Parent = Lighting
	local gui = Instance.new("ScreenGui")
	gui.Name = "RoninStormScreen"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 45
	gui.ResetOnSpawn = false
	local vignette = {
		edge(gui, "VL", Color3.new(0, 0, 0), "L", 0.22, 0),
		edge(gui, "VR", Color3.new(0, 0, 0), "R", 0.22, 180),
		edge(gui, "VT", Color3.new(0, 0, 0), "T", 0.2, 90),
		edge(gui, "VB", Color3.new(0, 0, 0), "B", 0.2, 270),
	}
	-- (the RGB split: red creeping in from one side, cyan from the other)
	local fringe = {
		edge(gui, "FR", Color3.fromRGB(255, 40, 60), "L", 0.05, 0),
		edge(gui, "FC", Color3.fromRGB(40, 220, 255), "R", 0.05, 180),
	}
	local pl = player:FindFirstChildOfClass("PlayerGui")
	gui.Parent = pl
	return { cc = cc, bloom = bloom, blur = blur, gui = gui, fringe = fringe, vignette = vignette }
end

local function dropGrade(g: Grade)
	g.cc:Destroy(); g.bloom:Destroy(); g.blur:Destroy(); g.gui:Destroy()
end

-- k = 0..1 how strong; pulse = 0..1 a wave's kick; t = time (for the jitter)
local function applyGrade(g: Grade, k: number, pulse: number, t: number)
	g.cc.Brightness = -0.16 * k + 0.08 * pulse
	g.cc.Contrast = 0.32 * k
	g.cc.Saturation = -0.75 * k
	g.cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(176, 204, 255), k)
	g.bloom.Intensity = 1.1 * k + 0.8 * pulse
	g.blur.Size = 1.5 * k + 7 * pulse
	for _, v in ipairs(g.vignette) do v.BackgroundTransparency = 1 - 0.75 * k end
	local jit = 0.004 * (k + 2 * pulse) * math.sin(t * 53)
	for i, f in ipairs(g.fringe) do
		f.BackgroundTransparency = 1 - (0.28 * k + 0.4 * pulse)
		local s = if i == 1 then 1 else -1
		f.Position = UDim2.fromScale((if i == 1 then 0 else 0.95) + s * jit, 0)
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- A storm
-- ═════════════════════════════════════════════════════════════════════════════
export type Storm = { Unleash: () -> (), Finish: () -> (), Cancel: () -> () }

local activeGrade: { owner: any, g: Grade }? = nil

function RoninStorm.Begin(char: Model, center: Vector3, conf: Config?): Storm
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local radius = cfg(conf, "radius") :: number
	local build = cfg(conf, "build") :: number
	local maxLife = cfg(conf, "maxLife") :: number
	local fxF = fxFolder()
	local t0 = os.clock()
	local ground = groundAt(center)
	local scale = 1 - 0.6 * FxBudget.Pressure() -- (fewer of everything when frames are dear)

	local token = {}
	local panes: { Pane } = {}
	local cuts: { Cut } = {}
	local cracks: { Beam } = {}
	local owned: { Instance } = {}
	local unleashedAt: number? = nil
	local finishedAt: number? = nil
	local pulseAt = -10
	local camOn = cfg(conf, "cinematic") == true and root ~= nil
	local gradeOn = cfg(conf, "grade") ~= false

	-- the grade: this storm takes it over (an older storm's just stops driving it)
	local grade: Grade? = nil
	if gradeOn then
		if activeGrade then dropGrade(activeGrade.g) end
		grade = makeGrade()
		activeGrade = { owner = token, g = grade :: Grade }
	end

	-- ── The floor: black mirror glass with bright cracks ──
	local floor = Instance.new("Part")
	floor.Name = "MirrorFloor"
	floor.Shape = Enum.PartType.Cylinder
	floor.Anchored, floor.CanCollide, floor.CanQuery, floor.CanTouch = true, false, false, false
	floor.CastShadow = false
	floor.Material = Enum.Material.SmoothPlastic -- (not Glass: it would hide the cuts seen through it)
	floor.Color = Color3.fromRGB(10, 16, 30)
	floor.Reflectance = 0.55
	floor.Transparency = 1
	floor.Size = Vector3.new(0.12, radius * 2.2, radius * 2.2)
	floor.CFrame = CFrame.new(ground + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90))
	floor.Parent = fxF
	table.insert(owned, floor)
	-- cracks across the floor: radial runs with a few chords, flat on the glass
	local crackN = math.floor(16 * scale + 0.5)
	for i = 1, crackN do
		local a = (i / crackN) * math.pi * 2 + rand(-0.2, 0.2)
		local d = Vector3.new(math.cos(a), 0, math.sin(a))
		local r0, r1 = rand(0, radius * 0.25), rand(radius * 0.45, radius * 1.05)
		local p0 = ground + d * r0 + Vector3.new(0, 0.12, 0)
		local bend = d:Cross(Vector3.yAxis) * rand(-3, 3)
		local p1 = ground + d * r1 + bend + Vector3.new(0, 0.12, 0)
		local a0, a1 = att(Workspace.Terrain), att(Workspace.Terrain)
		a0.WorldPosition, a1.WorldPosition = p0, p1
		table.insert(owned, a0); table.insert(owned, a1)
		local b = beam(a0, a1, ICE, rand(0.08, 0.18), 1)
		b.Transparency = NumberSequence.new(1)
		table.insert(cracks, b)
	end

	-- ── Panes ──
	local paneGoal = math.floor((cfg(conf, "panes") :: number) * scale + 0.5)
	local function addPane()
		if #panes >= paneGoal or not FxBudget.Allow("roninPane", 80, 20) then return end
		-- where: anywhere round the Ronin and up above, mostly in a shell, a few close
		local yaw = rand(0, math.pi * 2)
		local dist = if math.random() < 0.2 then rand(5, 10) else rand(10, radius * 1.05)
		local high = if math.random() < 0.25 then rand(12, 26) else rand(0.5, 14)
		local pos = ground + Vector3.new(math.cos(yaw) * dist, high, math.sin(yaw) * dist)
		-- shape: a long, sharp, irregular triangle
		local size = rand(2.5, 9) * (if dist > radius * 0.7 then 1.4 else 1)
		local A = Vector3.new(rand(-0.3, 0.3), rand(0.6, 1.2), 0) * size
		local B = Vector3.new(rand(-1.0, -0.4), rand(-0.9, -0.2), 0) * size
		local C = Vector3.new(rand(0.4, 1.0), rand(-0.8, 0.1), 0) * size
		local s0, c0, s1, c1 = triangle(A, B, C, 0.06)
		-- facing: roughly toward the centre, tipped at random
		local face = CFrame.lookAt(pos, center + Vector3.new(0, 3, 0))
			* CFrame.Angles(rand(-0.6, 0.6), rand(-0.9, 0.9), rand(0, math.pi * 2))
		-- (black mirror shards: a few, and see-through, so the cuts behind still show)
		local void = math.random() < 0.22
		local w0, w1 = takeWedge(), takeWedge()
		for _, w in ipairs({ w0, w1 }) do
			-- (never Glass: Roblox hides every beam and particle behind Glass, the cuts included)
			w.Material = Enum.Material.SmoothPlastic
			w.Color = if void then VOID else Color3.fromRGB(170, 200, 240):Lerp(WHITE, rand(0, 0.4))
			w.Reflectance = if void then 0.5 else 0.3
			w.Transparency = 1
			w.Parent = fxF
		end
		w0.Size, w1.Size = s0, s1
		local p: Pane = {
			w0 = w0, w1 = w1, c0 = c0, c1 = c1, cf = face,
			vel = (pos - center).Unit * rand(0.1, 0.5) + Vector3.new(0, rand(-0.2, 0.3), 0),
			spinAxis = randUnit(), spin = rand(-0.25, 0.25),
			alpha = if void then 0.4 else rand(0.45, 0.65), t0 = os.clock(), verts = {}, edges = {}, boom = nil,
		}
		w0.CFrame, w1.CFrame = face * c0, face * c1
		-- bright edges on some (the vertices ride on w0)
		if math.random() < (if void then 0.85 else 0.45) then
			local vs = { A, B, C }
			for i = 1, 3 do table.insert(p.verts, att(w0, c0:PointToObjectSpace(vs[i]))) end
			local n = if math.random() < 0.5 then 3 else 2
			for i = 1, n do
				local e = beam(p.verts[i], p.verts[i % 3 + 1], if void then BLUE else WHITE, rand(0.05, 0.12), 1)
				e.Transparency = NumberSequence.new(1)
				table.insert(p.edges, e)
			end
			-- a crack over to a near neighbour
			for j = #panes, math.max(1, #panes - 8), -1 do
				local q = panes[j]
				if #q.verts > 0 and (q.cf.Position - pos).Magnitude < 16 then
					local e = beam(p.verts[math.random(1, 3)], q.verts[math.random(1, 3)], ICE, 0.05, 1)
					e.Transparency = NumberSequence.new(1)
					table.insert(p.edges, e)
					break
				end
			end
		end
		table.insert(panes, p)
	end

	-- ── Cuts ──
	local cutCap = math.max(12, math.floor(28 * scale + 0.5))
	local function addCut(from: Vector3, to: Vector3, width: number, draw: number)
		-- (neon blooms: past a few dozen hanging at once the screen goes to a wash)
		if #cuts >= cutCap or not FxBudget.Allow("roninStorm", 140, 60) then return end
		-- A neon tube of light: a white-hot core inside a see-through cyan glow
		-- (both Neon, so they bloom through the dark grade)
		local glowT = rand(0.55, 0.7)
		local glow = neonBar(Color3.fromRGB(120, 210, 255), glowT, fxF)
		local core = neonBar(WHITE, 0, fxF)
		glow.Size = Vector3.new(width, width, 0.05)
		core.Size = Vector3.new(width * 0.4, width * 0.4, 0.05)
		glow.CFrame, core.CFrame = CFrame.new(from), CFrame.new(from)
		table.insert(cuts, { core = core, glow = glow, from = from, to = to,
			width = width, t0 = os.clock(), draw = draw, boom = nil, phase = 0, glowT = glowT })
	end

	-- one cut somewhere in the storm: across the arena, round the Ronin, overhead
	-- (`draw`: how long it takes to be drawn end to end; nil = its own quick stroke)
	local function randomCut(draw: number?)
		local mid
		local roll = math.random()
		if roll < 0.45 then
			mid = center + Vector3.new(rand(-7, 7), rand(0.5, 8), rand(-7, 7)) -- right round the Ronin
		elseif roll < 0.85 then
			local a, d = rand(0, math.pi * 2), math.sqrt(math.random()) * radius
			mid = ground + Vector3.new(math.cos(a) * d, rand(0.5, 16), math.sin(a) * d)
		else
			mid = ground + Vector3.new(rand(-radius, radius) * 0.6, rand(14, 26), rand(-radius, radius) * 0.6) -- overhead
		end
		-- mostly flat and diagonal, some steep
		local yaw = rand(0, math.pi * 2)
		local pitch = math.rad(if math.random() < 0.3 then rand(-75, 75) else rand(-28, 28))
		local dir = Vector3.new(math.cos(yaw) * math.cos(pitch), math.sin(pitch), math.sin(yaw) * math.cos(pitch))
		-- (mostly long lines right across the space, as if the air itself was cut)
		local long = math.random() < 0.6
		local len = if long then rand(radius * 1.3, radius * 2.6) else rand(12, 34)
		local width = if long then rand(0.28, 0.45) else rand(0.16, 0.3)
		local flip = if math.random() < 0.5 then 1 else -1
		addCut(mid - dir * len * 0.5 * flip, mid + dir * len * 0.5 * flip, width,
			draw or (if long then rand(0.07, 0.12) else rand(0.03, 0.07)))
	end

	-- ── The camera (the caster) ──
	local cam = Workspace.CurrentCamera
	local iso: any = nil
	local camWas: Enum.CameraType? = nil
	local camReleased = false
	local look = if root then Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit else Vector3.zAxis
	local right = look:Cross(Vector3.yAxis)
	if camOn then
		local ok, mod = pcall(function() return require(script.Parent:WaitForChild("IsometricCamera")) :: any end)
		if ok and mod and mod.IsActive and mod.IsActive() then
			iso = mod
			mod.Pause()
		end
		camWas = cam.CameraType
		cam.CameraType = Enum.CameraType.Scriptable
	end
	local function releaseCam()
		if not camOn or camReleased then return end
		camReleased = true
		if iso then
			iso.Resume(0.5)
		else
			cam.CameraType = camWas or Enum.CameraType.Custom
			cam.FieldOfView = 70
		end
	end

	local function driveCam(now: number)
		if not camOn or camReleased or not root or not root.Parent then return end
		local body = root.Position
		if not unleashedAt then
			-- the build: low, in front and a little to the side, creeping in on the face
			local k = math.clamp((now - t0) / build, 0, 1)
			local e = 1 - (1 - k) ^ 2
			local from = body + look * (7 - 1.6 * e) + right * (2.6 - 0.6 * e) + Vector3.new(0, 0.2 + 0.4 * e, 0)
			cam.CFrame = CFrame.lookAt(from, body + Vector3.new(0, 1.3, 0)) * CFrame.Angles(0, 0, math.rad(-6))
			cam.FieldOfView = 48 - 6 * e
		else
			-- the storm: wide and low behind, looking slightly up into it, orbiting slowly
			local u = unleashedAt :: number
			local len = cfg(conf, "stormLength") :: number
			local k = math.clamp((now - u) / len, 0, 1.3)
			local e = 1 - (1 - math.min(k * 3, 1)) ^ 3 -- (the cut out to wide)
			local orbit = math.rad(-28 + 50 * k)
			local back = (CFrame.fromAxisAngle(Vector3.yAxis, orbit):VectorToWorldSpace(-look))
			-- (the Ronin stays in the middle of the frame, the storm all round him)
			local dist = 10 + 8 * e
			local from = body + back * dist + Vector3.new(0, 1.0 + 1.2 * e, 0)
			local at = body - back * 8 + Vector3.new(0, 3.2, 0)
			local kick = math.max(0, 1 - (now - pulseAt) / 0.18)
			cam.CFrame = CFrame.lookAt(from, at) * CFrame.Angles(0, 0, math.rad(4 * math.sin(k * 3)))
				* CFrame.new(rand(-1, 1) * 0.12 * kick, rand(-1, 1) * 0.12 * kick, 0)
			cam.FieldOfView = 66 + 10 * e + 5 * kick
		end
	end

	local storm: Storm = {} :: any

	-- ── Everything, every frame ──
	local conn: RBXScriptConnection
	local moveParts: { BasePart } = {}
	local moveCFs: { CFrame } = {}
	local ended = false

	local function cleanup()
		if ended then return end
		ended = true
		conn:Disconnect()
		for _, p in ipairs(panes) do
			for _, e in ipairs(p.edges) do e:Destroy() end
			giveWedge(p.w0); giveWedge(p.w1)
		end
		for _, c in ipairs(cuts) do c.core:Destroy(); c.glow:Destroy() end
		for _, o in ipairs(owned) do o:Destroy() end
		if grade and activeGrade and activeGrade.owner == token then
			dropGrade(grade)
			activeGrade = nil
		end
		releaseCam()
	end

	local lastPane = 0
	local function step()
		local now = os.clock()
		local age = now - t0
		if not finishedAt and (age > maxLife or (root and not root.Parent)) then storm.Cancel() end
		local f = finishedAt
		-- how strong the whole thing is: builds in, holds, fades out after the click
		local k = math.clamp(age / build, 0, 1)
		local out = if f then math.clamp((now - f - 0.35) / 1.1, 0, 1) else 0
		local strength = k * (1 - out)
		local pulse = math.max(0, 1 - (now - pulseAt) / 0.22)
		if f then pulse = math.max(pulse, math.max(0, 1 - (now - f) / 0.5)) end

		if grade and activeGrade and activeGrade.owner == token then
			applyGrade(grade, strength, pulse, now)
		end
		driveCam(now)
		if f and now - f > 0.7 then releaseCam() end

		-- the floor and its cracks
		floor.Transparency = 1 - 0.75 * strength
		local crackT = 1 - (0.15 + 0.7 * math.min(1, (if unleashedAt then 1 else 0) + k * 0.4)) * (1 - out)
		for _, b in ipairs(cracks) do b.Transparency = NumberSequence.new(math.clamp(crackT - pulse * 0.2, 0, 1)) end

		-- panes: more crack open as it builds, more with each wave
		local want = math.floor(paneGoal * (0.35 * k + (if unleashedAt then 0.65 * math.clamp((now - (unleashedAt :: number)) / 1.8, 0, 1) else 0)))
		if not f and #panes < want and now - lastPane > 0.015 then
			lastPane = now
			addPane()
		end
		table.clear(moveParts); table.clear(moveCFs)
		local dt = 1 / 60
		for i = #panes, 1, -1 do
			local p = panes[i]
			local tIn = math.clamp((now - p.t0) / 0.18, 0, 1)
			local vis = tIn
			if p.boom then
				local b = now - p.boom
				if b > 0.9 then
					for _, e in ipairs(p.edges) do e:Destroy() end
					giveWedge(p.w0); giveWedge(p.w1)
					table.remove(panes, i)
					continue
				end
				vis = math.max(0, 1 - b / 0.9)
			end
			p.cf = (p.cf + p.vel * dt) * CFrame.fromAxisAngle(p.spinAxis, p.spin * dt)
			if p.boom then p.vel *= 0.96 end
			local tr = 1 - (1 - p.alpha) * vis * (1 - out)
			-- (a quick flicker as it cracks in)
			if tIn < 1 and math.random() < 0.3 then tr = math.min(1, tr + 0.4) end
			p.w0.Transparency, p.w1.Transparency = tr, tr
			local et = 1 - vis * (1 - out) * (0.75 + 0.25 * pulse)
			for _, e in ipairs(p.edges) do e.Transparency = NumberSequence.new(math.clamp(et, 0, 1)) end
			table.insert(moveParts, p.w0); table.insert(moveCFs, p.cf * p.c0)
			table.insert(moveParts, p.w1); table.insert(moveCFs, p.cf * p.c1)
		end
		if #moveParts > 0 then
			Workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
		end

		-- cuts: drawn end to end, hang shimmering, flare and burst on the click
		-- (only the ones that move or resize this frame are written)
		table.clear(moveParts); table.clear(moveCFs)
		for i = #cuts, 1, -1 do
			local c = cuts[i]
			local t = now - c.t0
			if c.boom and now >= c.boom then
				local b = now - c.boom
				if b > CUT_FLARE + CUT_FADE then
					c.core:Destroy(); c.glow:Destroy()
					table.remove(cuts, i)
					continue
				end
				local mid = (c.from + c.to) / 2
				local half = (c.to - c.from) / 2
				local w, fade
				if b < CUT_FLARE then
					local q = b / CUT_FLARE
					w = c.width * (1 + 2.2 * q)
					half *= 1 + 0.12 * q
					fade = 0
				else
					local q = (b - CUT_FLARE) / CUT_FADE
					w = c.width * 3.2 * (1 - q) ^ 2 + 0.02
					half *= 1.12 + 0.2 * q
					fade = q
				end
				local len = (half.Magnitude * 2)
				c.glow.Size = Vector3.new(w, w, len)
				c.core.Size = Vector3.new(w * 0.4, w * 0.4, len)
				c.glow.Transparency = c.glowT + (1 - c.glowT) * fade
				c.core.Transparency = fade
				local cf = barCF(mid - half, mid + half)
				table.insert(moveParts, c.glow); table.insert(moveCFs, cf)
				table.insert(moveParts, c.core); table.insert(moveCFs, cf)
			else
				local d = math.clamp(t / c.draw, 0, 1)
				local w = c.width * (1 + 0.5 * pulse)
				if d < 1 or c.phase == 0 then
					if d >= 1 then c.phase = 1 end
					local tip = c.from:Lerp(c.to, 1 - (1 - d) ^ 3)
					local len = math.max(0.05, (tip - c.from).Magnitude)
					c.glow.Size = Vector3.new(w, w, len)
					c.core.Size = Vector3.new(w * 0.4, w * 0.4, len)
					local cf = barCF(c.from, tip)
					table.insert(moveParts, c.glow); table.insert(moveCFs, cf)
					table.insert(moveParts, c.core); table.insert(moveCFs, cf)
				elseif pulse > 0 or c.phase == 1 then
					-- (brighter and fatter on each wave, settling back after)
					c.phase = if pulse > 0 then 1 else 3
					local len = (c.to - c.from).Magnitude
					c.glow.Size = Vector3.new(w, w, len)
					c.core.Size = Vector3.new(w * 0.4, w * 0.4, len)
				end
				-- (hanging: a shimmer in the glow)
				c.glow.Transparency = c.glowT + 0.12 * math.sin(now * 31 + c.width * 90) - 0.25 * pulse
			end
		end
		if #moveParts > 0 then
			Workspace:BulkMoveTo(moveParts, moveCFs, Enum.BulkMoveMode.FireCFrameChanged)
		end

		if f and now - f > 1.6 and #cuts == 0 then cleanup() end
	end
	conn = RunService.RenderStepped:Connect(function()
		local ok, err = pcall(step)
		if not ok then
			warn("[RoninStorm]", err)
			cleanup()
		end
	end)

	-- ── The beats ──
	-- the cuts are already hanging there when the wide shot opens: they start
	-- appearing through the build (behind the close-up), and on the Unleash
	-- a dense set lands all at once, already drawn
	local preCuts = math.max(8, math.floor(16 * scale + 0.5))
	for i = 1, math.floor(preCuts * 0.5) do
		task.delay(build * 0.35 + (i - 1) * (build * 0.6) / preCuts, function()
			if not ended and not finishedAt and not unleashedAt then randomCut(0.001) end
		end)
	end

	function storm.Unleash()
		if ended or unleashedAt then return end
		unleashedAt = os.clock()
		for _ = 1, math.ceil(preCuts * 0.5) do randomCut(0.001) end
		local waves = cfg(conf, "waves") :: number
		local gap = cfg(conf, "waveGap") :: number
		local per = math.max(4, math.floor((cfg(conf, "perWave") :: number) * scale + 0.5))
		local spread = cfg(conf, "waveSpread") :: number
		for w = 1, waves do
			task.delay((w - 1) * gap, function()
				if ended or finishedAt then return end
				pulseAt = os.clock()
				-- each wave a little bigger than the last
				local n = math.floor(per * (0.7 + 0.15 * w) + 0.5)
				for i = 1, n do
					task.delay((i - 1) * spread / n, function()
						if not ended and not finishedAt then randomCut() end
					end)
				end
				if FxBudget.Allow("roninStormStars", 6) then
					SwordFX.Stars(center + Vector3.new(0, 3, 0), 10, 40, BLUE)
				end
			end)
		end
	end

	function storm.Finish()
		if ended or finishedAt then return end
		local now = os.clock()
		finishedAt = now
		pulseAt = now
		-- every cut flares and bursts, close ones first rolling outward
		for _, c in ipairs(cuts) do
			local d = (((c.from + c.to) / 2) - center).Magnitude
			c.boom = now + math.clamp(d / radius, 0, 1) * 0.22 + math.random() * 0.06
		end
		-- the panes blow outward and fade
		for _, p in ipairs(panes) do
			local away = p.cf.Position - center
			p.boom = now + math.clamp(away.Magnitude / radius, 0, 1) * 0.2
			p.vel = away.Unit * rand(18, 40) + Vector3.new(0, rand(-4, 10), 0)
			p.spin = rand(-6, 6)
		end
		if FxBudget.Allow("roninStormStars", 6) then SwordFX.Stars(center + Vector3.new(0, 3, 0), 26, 70, BLUE) end
		-- (the pack's blast and hit flash under it all)
		PackFX.Burst("Explosions/Explosion (*)", CFrame.new(center + Vector3.new(0, 3, 0)), { scale = 4, color = BLUE, key = "roninStormBoom", perSecond = 2 })
		PackFX.Burst("Explosions/Hit", CFrame.new(center + Vector3.new(0, 3, 0)), { scale = 3, color = BLUE, key = "roninStormBoom2", perSecond = 2 })
	end

	function storm.Cancel()
		if ended then return end
		if not finishedAt then
			finishedAt = os.clock()
			for _, c in ipairs(cuts) do c.boom = finishedAt end
			for _, p in ipairs(panes) do p.boom = finishedAt end
		end
	end

	-- safety: gone after maxLife no matter what
	task.delay(maxLife + 3, function() if not ended then cleanup() end end)
	return storm
end

return RoninStorm
