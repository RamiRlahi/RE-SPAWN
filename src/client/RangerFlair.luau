--[[
	RangerFlair.luau
	Rain of Arrows wind-up (1.6 s, its own cinematic camera: PlayCamera):

	  0.00  bow hoisted overhead
	  0.36  SLAM: a ring of light, cracks, dirt, leaves; a druid circle opens
	        and thorned vines burst up and lash like whips (high wide shot)
	  1.15  cut low behind him, looking up
	  1.35  he looses one arrow into the sky, green light spiralling after it
	  1.60  the vines sink as the arrow storm lands; back to the game camera
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local VariantFX = require(script.Parent:WaitForChild("VariantFX"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))

local BARK_DARK = Color3.fromRGB(46, 72, 32)
local BARK = Color3.fromRGB(64, 98, 44)
local LEAF = Color3.fromRGB(155, 245, 75)
local LEAF_GLOW = Color3.fromRGB(190, 255, 100)
local SPORE = Color3.fromRGB(210, 255, 140)
local DIRT = Color3.fromRGB(92, 70, 48)
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local RangerFlair = {}

RangerFlair.SLAM_AT = 0.36
RangerFlair.LOOSE_AT = 1.35
RangerFlair.WITHER_AT = 1.6 -- (the storm lands; the camera hands back)

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.LightInfluence = 0
	pe.Rate = 0
	for k, v in pairs(props) do
		(pe :: any)[k] = v
	end
	pe.Parent = parent
	return pe
end

local function seq(...): NumberSequence
	local a = { ... }
	local k = {}
	for i = 1, #a, 2 do table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1])) end
	return NumberSequence.new(k)
end

local function att(pos: Vector3): Attachment
	local a = Instance.new("Attachment")
	a.Parent = VariantFX.Root()
	a.WorldPosition = pos
	return a
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundAt(pos: Vector3): Vector3
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(list, plr.Character) end
	end
	for _, n in ipairs({ "Mobs", "Allies", "IceClones" }) do
		local f = Workspace:FindFirstChild(n)
		if f then table.insert(list, f) end
	end
	for _, c in ipairs(Workspace.Terrain:GetChildren()) do table.insert(list, c) end
	groundParams.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), groundParams)
	return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
end

local function fade(root: Instance, t: number)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("Light") then
			TweenService:Create(d, TweenInfo.new(t), { Brightness = 0 }):Play()
		end
	end
end

-- Segment between two points (a cylinder along the path).
local function segment(parent: Instance, a: Vector3, b: Vector3, thick: number, color: Color3, material: Enum.Material): BasePart
	local len = (b - a).Magnitude
	return part(parent, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(len + thick * 0.4, thick, thick),
		CFrame = CFrame.lookAt((a + b) * 0.5, b) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Material = material,
	})
end

-- ── Pieces ──────────────────────────────────────────────────────────────────
local function ringWave(parent: Instance, center: Vector3, r0: number, r1: number, t: number, color: Color3, thick: number)
	local segs = {}
	for i = 1, 36 do
		segs[i] = part(parent, { Color = color, Material = Enum.Material.Neon })
	end
	local t0 = os.clock()
	local c
	c = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / t, 0, 1)
		if a >= 1 then
			c:Disconnect()
			for _, s in ipairs(segs) do s:Destroy() end
			return
		end
		local r = r0 + (r1 - r0) * (1 - (1 - a) ^ 3)
		local segLen = 2 * math.pi * r / #segs * 1.12
		for i, s in ipairs(segs) do
			local ang = (i / #segs) * math.pi * 2
			local p = center + Vector3.new(math.cos(ang) * r, 0.15, math.sin(ang) * r)
			s.Size = Vector3.new(thick * (1 - a * 0.6), thick * 0.4, segLen)
			s.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(ang), 0, math.cos(ang)))
			s.Transparency = a
		end
	end)
end

local function cracks(parent: Instance, center: Vector3, count: number, length: number)
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + math.random() * 0.6
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local p = center
		for _ = 1, 3 do
			dir = (CFrame.Angles(0, (math.random() - 0.5) * 1.2, 0) * dir).Unit
			local nxt = p + dir * (length / 3) * (0.7 + math.random() * 0.6)
			local glow = segment(parent, p + Vector3.new(0, 0.08, 0), nxt + Vector3.new(0, 0.08, 0), 0.1, LEAF, Enum.Material.Neon)
			local dark = segment(parent, p + Vector3.new(0, 0.05, 0), nxt + Vector3.new(0, 0.05, 0), 0.5, BARK_DARK, Enum.Material.Ground)
			TweenService:Create(glow, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Color = BARK }):Play()
			TweenService:Create(dark, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
			p = nxt
		end
	end
end

local function dirtChunks(parent: Instance, center: Vector3, count: number)
	for _ = 1, count do
		local s = 0.4 + math.random() * 0.8
		local chunk = part(parent, {
			Size = Vector3.new(s, s * 0.7, s * 0.9),
			CFrame = CFrame.new(center + Vector3.new((math.random() - 0.5) * 3, 0.5, (math.random() - 0.5) * 3)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = math.random() < 0.3 and BARK or DIRT,
			Material = Enum.Material.Ground,
			Anchored = false,
			CanCollide = true,
		})
		local dir = Vector3.new(math.random() - 0.5, 1.4 + math.random(), math.random() - 0.5).Unit
		chunk.AssemblyLinearVelocity = dir * (20 + math.random() * 20)
		chunk.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		task.delay(1 + math.random() * 0.4, function()
			if chunk.Parent then TweenService:Create(chunk, TweenInfo.new(0.4), { Transparency = 1, Size = chunk.Size * 0.4 }):Play() end
		end)
		Debris:AddItem(chunk, 1.8)
	end
end

local function leafBurst(pos: Vector3, count: number, speed: number)
	local a = att(pos)
	emitter(a, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(LEAF_GLOW, LEAF),
		LightEmission = 0.8,
		Size = seq(0, 0.6, 1, 0),
		Lifetime = NumberRange.new(0.5, 1.1),
		Speed = NumberRange.new(speed * 0.4, speed),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, -18, 0),
		Drag = 2,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-300, 300),
	}):Emit(count)
	emitter(a, {
		Texture = TEX_SMOKE,
		Color = ColorSequence.new(Color3.fromRGB(140, 120, 90), Color3.fromRGB(110, 140, 80)),
		LightEmission = 0,
		Size = seq(0, 2, 1, 7),
		Transparency = seq(0, 0.45, 1, 1),
		Lifetime = NumberRange.new(0.7, 1.2),
		Speed = NumberRange.new(4, 9),
		SpreadAngle = Vector2.new(180, 15),
		Drag = 3,
		Rotation = NumberRange.new(0, 360),
	}):Emit(math.ceil(count / 4))
	Debris:AddItem(a, 1.6)
end

-- Slam shake — only for the caster's own camera.
local function shake(char: Model, intensity: number, duration: number)
	if char ~= Players.LocalPlayer.Character then return end
	local camera = Workspace.CurrentCamera
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local amp = intensity * (1 - (os.clock() - t0) / duration)
			camera.CFrame *= CFrame.new((math.random() - 0.5) * amp, (math.random() - 0.5) * amp * 0.6, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ── The wind-up ─────────────────────────────────────────────────────────────
-- After the reference: 1 · SUMMON (a high wide shot): the bow meets the
-- ground, a druid circle of thin green light opens round him and dark thorned
-- vines burst up and lash about like whips, leaves flying off them. 2 ·
-- RELEASE (low, behind him, looking up): he draws and looses one arrow into
-- the sky, green light spiralling up after it. Then back to the game camera
-- as the storm lands. Kept dark and fine, not bright: the green is in thin
-- lines and small leaves, the vines are wood.

-- A vine that whips: a chain of segments whose shape is worked out every
-- frame, rising from the ground with a lash, waving like a whip (a wave
-- running up it), the tip cracking out and curling back.
type Vine = { base: Vector3, out: Vector3, side: Vector3, height: number, phase: number, born: number, segs: { BasePart }, thorns: { BasePart } }
local VINE_SEGS = 10
local VINE_WOOD = Color3.fromRGB(58, 44, 32)
local VINE_DARK = Color3.fromRGB(34, 27, 22)
local function makeVine(parent: Instance, base: Vector3, center: Vector3, height: number, born: number): Vine
	local out = Vector3.new(base.X - center.X, 0, base.Z - center.Z)
	out = if out.Magnitude > 0.01 then out.Unit else Vector3.xAxis
	local side = Vector3.new(-out.Z, 0, out.X) * (if math.random() < 0.5 then 1 else -1)
	local segs, thorns = {}, {}
	for i = 1, VINE_SEGS do
		segs[i] = part(parent, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.1, 0.1),
			Color = if i % 2 == 0 then VINE_WOOD else VINE_DARK, Material = Enum.Material.Wood, Transparency = 1 })
		if i % 2 == 0 then
			thorns[#thorns + 1] = part(parent, { ClassName = "WedgePart", Size = Vector3.new(0.08, 0.4, 0.2),
				Color = VINE_DARK, Material = Enum.Material.Wood, Transparency = 1 })
		end
	end
	return { base = base, out = out, side = side, height = height, phase = math.random() * 6, born = born, segs = segs, thorns = thorns }
end

local function stepVine(v: Vine, t: number)
	local age = t - v.born
	if age < 0 then return end
	-- up out of the ground in a quarter second, overshooting a little
	local g = math.clamp(age / 0.25, 0, 1)
	local grow = 1 + 0.15 * math.sin(g * math.pi) - (1 - g) ^ 3
	local len = v.height * math.min(grow, 1.1)
	local pts = {}
	for i = 0, VINE_SEGS do
		local k = i / VINE_SEGS
		-- the whip: a wave running up it, stronger toward the tip; it leans in
		-- over him and the tip cracks outward
		local wave = math.sin(age * 9 - k * 4 + v.phase) * (k ^ 1.6) * 2.2
		local lash = math.sin(age * 4.5 + v.phase) * (k ^ 2) * 1.8
		local lean = -v.out * math.sin(k * math.pi) * 1.4 + v.out * (k ^ 2) * (1.2 + lash)
		pts[i] = v.base + Vector3.new(0, k * len, 0) + v.side * wave + lean
	end
	for i = 1, VINE_SEGS do
		local a, b = pts[i - 1], pts[i]
		local k = i / VINE_SEGS
		local thick = 0.55 * (1 - k * 0.8)
		local s = v.segs[i]
		local d = (b - a).Magnitude
		s.Size = Vector3.new(d + thick * 0.3, thick, thick)
		s.CFrame = CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
		s.Transparency = 0
	end
	for j, th in ipairs(v.thorns) do
		local i = j * 2
		local a, b = pts[i - 1], pts[i]
		local mid = (a + b) / 2
		local nrm = (b - a).Unit:Cross(Vector3.yAxis)
		nrm = if nrm.Magnitude > 0.01 then nrm.Unit else Vector3.xAxis
		th.CFrame = CFrame.lookAt(mid, mid + nrm * (if j % 2 == 0 then 1 else -1)) * CFrame.Angles(math.rad(-90), 0, 0)
		th.Transparency = 0
	end
end

-- The druid circle: thin rings of soft green light, glyph marks between them,
-- turning slowly (dim: lines, not slabs).
local function druidCircle(folder: Instance, center: Vector3): (number) -> ()
	local rings = { { r = 7.5, n = 44, w = 0.12, spin = 0.25 }, { r = 6.3, n = 38, w = 0.08, spin = -0.4 }, { r = 3.2, n = 22, w = 0.08, spin = 0.6 } }
	local segs: { { p: BasePart, ring: any, i: number } } = {}
	for _, ring in ipairs(rings) do
		for i = 1, ring.n do
			table.insert(segs, { p = part(folder, { Color = LEAF, Material = Enum.Material.Neon, Transparency = 1 }), ring = ring, i = i })
		end
	end
	-- glyphs: short marks round the band between the outer rings
	local glyphs: { { p: BasePart, a: number } } = {}
	for i = 1, 16 do
		table.insert(glyphs, { p = part(folder, { Color = LEAF_GLOW, Material = Enum.Material.Neon, Transparency = 1 }), a = i / 16 * math.pi * 2 })
	end
	return function(t: number)
		local grow = 1 - (1 - math.clamp(t / 0.3, 0, 1)) ^ 3
		local shown = 0.5 + 0.1 * math.sin(t * 6)
		for _, s in ipairs(segs) do
			local ring = s.ring
			local radius = ring.r * grow
			local a = (s.i / ring.n) * math.pi * 2 + t * ring.spin
			local p = center + Vector3.new(math.cos(a) * radius, 0.08, math.sin(a) * radius)
			local segLen = 2 * math.pi * radius / ring.n * 1.02
			s.p.Size = Vector3.new(ring.w, 0.04, math.max(segLen, 0.05))
			s.p.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
			s.p.Transparency = shown
		end
		for _, gl in ipairs(glyphs) do
			local a = gl.a - t * 0.3
			local p = center + Vector3.new(math.cos(a), 0, math.sin(a)) * 6.9 * grow + Vector3.new(0, 0.09, 0)
			gl.p.Size = Vector3.new(0.08, 0.04, 0.9)
			gl.p.CFrame = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a))) * CFrame.Angles(0, math.rad(25), 0)
			gl.p.Transparency = shown + 0.1
		end
	end
end

-- Little leaves flying off the vines (small, soft, not glowing blobs).
local function leafStream(at: Attachment, rate: number): ParticleEmitter
	return emitter(at, {
		Texture = TEX_SPARKLE, Color = ColorSequence.new(LEAF, BARK), LightEmission = 0.35,
		Size = seq(0, 0.28, 1, 0.1), Transparency = seq(0, 0.1, 1, 1),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(3, 8),
		SpreadAngle = Vector2.new(180, 60), Acceleration = Vector3.new(0, -4, 0), Drag = 1.5,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-200, 200), Rate = rate,
	})
end

function RangerFlair.playUltWindup(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local folder = Instance.new("Folder")
	folder.Name = "RangerUltWindup"
	folder.Parent = VariantFX.Root()
	local center = groundAt(root.Position)

	-- Gathering: a few green motes drawn into the bow before the slam.
	local gather = att(root.Position + Vector3.new(0, 2.5, 0))
	gather.Parent = folder
	emitter(gather, {
		Texture = TEX_SPARKLE, Color = ColorSequence.new(LEAF, BARK), LightEmission = 0.5,
		Size = seq(0, 0.3, 1, 0), Lifetime = NumberRange.new(0.3, 0.4), Speed = NumberRange.new(-12, -8),
		SpreadAngle = Vector2.new(180, 180), Rate = 30,
	})

	task.delay(RangerFlair.SLAM_AT, function()
		if not folder.Parent then return end
		gather:Destroy()
		-- SLAM: a thin ring of light out over the floor, cracks, dirt, leaves.
		ringWave(folder, center, 1, 12, 0.45, LEAF, 0.25)
		cracks(folder, center, 8, 7)
		dirtChunks(folder, center, 10)
		leafBurst(center + Vector3.new(0, 0.5, 0), 20, 18)
		shake(char, 0.6, 0.3)

		local circle = druidCircle(folder, center)
		-- the vines: a ring close round him, tall, and a looser ring further out
		local vines: { Vine } = {}
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2 + math.random() * 0.4
			local b = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (3 + math.random() * 1.2)
			table.insert(vines, makeVine(folder, b, center, 8 + math.random() * 3, math.random() * 0.12))
		end
		for i = 1, 6 do
			local a = (i / 6) * math.pi * 2 + math.random() * 0.5
			local b = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (6 + math.random() * 1.5)
			table.insert(vines, makeVine(folder, b, center, 4 + math.random() * 2.5, 0.05 + math.random() * 0.15))
		end
		local leaves = att(center + Vector3.new(0, 3, 0))
		leaves.Parent = folder
		local stream = leafStream(leaves, 45)
		local t0 = os.clock()
		local conn: RBXScriptConnection? = nil
		conn = RunService.RenderStepped:Connect(function()
			if not folder.Parent then
				if conn then conn:Disconnect() end
				return
			end
			local t = os.clock() - t0
			circle(t)
			for _, v in ipairs(vines) do stepVine(v, t) end
		end)
		-- at the cut to the release shot the vines whip back down into the
		-- ground (they'd fill the low camera's view)
		task.delay(RangerFlair.LOOSE_AT - 0.22 - RangerFlair.SLAM_AT, function()
			for _, v in ipairs(vines) do
				for _, q in ipairs(v.segs) do TweenService:Create(q, TweenInfo.new(0.12), { Transparency = 1 }):Play() end
				for _, q in ipairs(v.thorns) do TweenService:Create(q, TweenInfo.new(0.12), { Transparency = 1 }):Play() end
				v.born = math.huge -- (no longer drawn)
			end
		end)
		task.delay(RangerFlair.WITHER_AT - RangerFlair.SLAM_AT, function()
			stream.Enabled = false
			if conn then
				task.delay(0.9, function() if conn then conn:Disconnect() end end)
			end
		end)
	end)

	-- WITHER as the storm lands: the vines sink back into the ground.
	task.delay(RangerFlair.WITHER_AT, function()
		if not folder.Parent then return end
		fade(folder, 0.7)
		Debris:AddItem(folder, 1)
	end)
end

-- The cinematic camera (the caster's, or a teammate's when they watch it):
-- 1 · SUMMON, high and wide, looking down on the circle and the vines,
-- drifting round; 2 · RELEASE, low behind him, looking up past him into
-- the sky as he looses; then back to the game camera.
local cameraToken = 0
function RangerFlair.PlayCamera(char: Model, aimDir: Vector3)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not (root and hum) then return end
	cameraToken += 1
	local token = cameraToken
	local ok, Iso = pcall(function() return require(script.Parent:WaitForChild("IsometricCamera")) end)
	local wasIso = ok and Iso and Iso.IsActive and Iso.IsActive()
	if wasIso then Iso.Pause() end
	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable
	local fwd = Vector3.new(aimDir.X, 0, aimDir.Z)
	fwd = if fwd.Magnitude > 0.01 then fwd.Unit else root.CFrame.LookVector
	local right = fwd:Cross(Vector3.yAxis).Unit
	local c = root.Position
	local t0 = os.clock()
	local cut = RangerFlair.LOOSE_AT - 0.2
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if token ~= cameraToken or not root.Parent or t >= RangerFlair.WITHER_AT then
			if conn then conn:Disconnect() end
			if token == cameraToken then
				if wasIso then Iso.Resume(0.4) else cam.CameraType = Enum.CameraType.Custom; cam.CameraSubject = hum end
			end
			return
		end
		if t < cut then
			-- high and wide, drifting round from his front-right
			local a = math.rad(-35) + t * 0.18
			local dir = fwd * math.cos(a) + right * math.sin(a)
			local pos = c + dir * (18 - t * 2) + Vector3.new(0, 15 - t * 1.5, 0)
			cam.CFrame = CFrame.lookAt(pos, c + Vector3.new(0, 1, 0))
			cam.FieldOfView = 50
		else
			-- low in front of him, looking up past him at the plant behind as
			-- it spits the great arrow into the sky, following it up
			local k = math.clamp((t - cut) / (RangerFlair.WITHER_AT - cut), 0, 1)
			local plantTop = c - fwd * 9 + Vector3.new(0, 16, 0)
			local pos = c + fwd * 6 + right * 3 + Vector3.new(0, -1, 0)
			cam.CFrame = CFrame.lookAt(pos, plantTop + Vector3.new(0, k * 22, 0))
			cam.FieldOfView = 68
		end
	end)
end


-- ─── The colossal plant (Rain of Arrows) ───────────────────────────────────
-- After the "Giant Plant Boss" sheet: a thick leafy trunk standing on a mass
-- of thorned roots spread over the floor, two thorned tendrils curling up
-- either side, and on top a great flower head: green leaves behind it, a ring
-- of crimson petals cupped forward, a red lip, two rings of cream fangs round
-- a glowing green throat. The head turns to its target and its mouth gapes
-- as it sprays venom like a flamethrower (RangerFlair.Venom); it spits the
-- great arrow into the sky at the start. It sinks back when the storm ends.
-- Drawn from the server's word (SkillVFX rangerPlant / rangerVenom / rangerWhip).
local PL_TRUNK = Color3.fromRGB(64, 104, 46)
local PL_TRUNK_DARK = Color3.fromRGB(44, 78, 34)
local PL_LEAF = Color3.fromRGB(96, 168, 58)
local PL_LEAF_DARK = Color3.fromRGB(62, 122, 40)
local PL_PETAL = Color3.fromRGB(176, 42, 64)
local PL_PETAL_DARK = Color3.fromRGB(128, 26, 46)
local PL_FANG = Color3.fromRGB(236, 222, 182)
local PL_THORN = Color3.fromRGB(196, 168, 112)
local PL_THROAT = Color3.fromRGB(30, 60, 26)
local PL_GLOW = Color3.fromRGB(150, 255, 70)
local HEAD_H = 16

type Piece = { p: BasePart, cf: CFrame } -- (cf: local to its frame)
type Plant = { mouth: Vector3, base: Vector3, aim: Vector3?, open: number, lash: (Vector3) -> (), spewUntil: number }
-- (a solid thing, not a spell: kept out of the ability-effects folder, where
-- an effect variant would restyle it, and named without "fx"/"effect", or
-- VfxDetail fades it like a skill effect)
local function plantFolder(): Instance
	local f = Workspace:FindFirstChild("RangerFlora")
	if not f then
		f = Instance.new("Folder")
		f.Name = "RangerFlora"
		f.Parent = Workspace
	end
	return f :: Instance
end
local plants: { Plant } = {}

local function ppart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- A pointed blade (leaf, petal, fang, thorn): two wedges mirrored, pointing
-- along its -Z, flat in its YZ plane (`len` long, `w` wide, `t` thick).
-- Returns its two pieces, local to the blade's own frame.
local function blade(parent: Instance, len: number, w: number, t: number, color: Color3, material: Enum.Material?): { Piece }
	local m = material or Enum.Material.SmoothPlastic
	local a = ppart(parent, { ClassName = "WedgePart", Size = Vector3.new(t, w / 2, len), Color = color, Material = m })
	local b = ppart(parent, { ClassName = "WedgePart", Size = Vector3.new(t, w / 2, len), Color = color, Material = m })
	return { { p = a, cf = CFrame.new(0, w / 4, 0) }, { p = b, cf = CFrame.new(0, -w / 4, 0) * CFrame.Angles(0, 0, math.pi) } }
end

-- Turns that lay a blade in a face plane (the head's XY), pointing out from
-- its middle at angle `a`, `r` out, tipped forward (-Z) by `tilt`; `inward`
-- points it back in at the middle (the fangs).
local function radial(a: number, r: number, tilt: number, inward: boolean?): CFrame
	local pitch = if inward then -(math.pi / 2 - tilt) else (math.pi / 2 - tilt)
	return CFrame.Angles(0, 0, a) * CFrame.new(0, r, 0) * CFrame.Angles(pitch, 0, 0) * CFrame.Angles(0, 0, math.pi / 2)
end

local VENOM = Color3.fromRGB(160, 230, 40)
local VENOM_DARK = Color3.fromRGB(110, 60, 150)

-- The great arrow: spat from the plant's mouth straight up into the sky over
-- the zone, where it shatters into many (they fall as the arrow rain).
local function skyArrow(from: Vector3, zone: Vector3)
	local folder = plantFolder()
	local top = zone + Vector3.new(0, 48, 0)
	local shaft = ppart(folder, { Color = LEAF_GLOW, Material = Enum.Material.Neon, Size = Vector3.new(0.5, 0.5, 7) })
	local head = ppart(folder, { ClassName = "WedgePart", Color = Color3.fromRGB(230, 255, 190), Material = Enum.Material.Neon, Size = Vector3.new(0.6, 1.4, 2) })
	local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0.3, 0, 3.5); a0.Parent = shaft
	local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(-0.3, 0, 3.5); a1.Parent = shaft
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(LEAF_GLOW, LEAF)
	trail.LightEmission = 0.8
	trail.Lifetime = 0.35
	trail.FaceCamera = true
	trail.WidthScale = seq(0, 3, 1, 0.2)
	trail.Transparency = seq(0, 0, 1, 1)
	trail.Parent = shaft
	local t0 = os.clock()
	local flight = 0.38
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local k = math.min((os.clock() - t0) / flight, 1)
		local p = from:Lerp(top, k * k)
		local cf = CFrame.lookAt(p, p + (top - from).Unit)
		shaft.CFrame = cf
		head.CFrame = cf * CFrame.new(0, 0, -4.4) * CFrame.Angles(0, 0, math.pi / 2)
		if k >= 1 then
			if conn then conn:Disconnect() end
			shaft:Destroy()
			head:Destroy()
			-- it shatters: a flash, shards of it flying out to fall as the rain
			local flash = ppart(folder, { Shape = Enum.PartType.Ball, Color = LEAF_GLOW, Material = Enum.Material.Neon, Size = Vector3.one * 2, CFrame = CFrame.new(top), Transparency = 0.1 })
			TweenService:Create(flash, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 14, Transparency = 1 }):Play()
			Debris:AddItem(flash, 0.35)
			for i = 1, 14 do
				local a = i / 14 * math.pi * 2
				local d = Vector3.new(math.cos(a), -0.35, math.sin(a)).Unit
				local shard = ppart(folder, { Color = LEAF_GLOW, Material = Enum.Material.Neon, Size = Vector3.new(0.25, 0.25, 3), CFrame = CFrame.lookAt(top, top + d) })
				TweenService:Create(shard, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.lookAt(top + d * 12, top + d * 13), Transparency = 1 }):Play()
				Debris:AddItem(shard, 0.4)
			end
		end
	end)
	ClassFX.Sound("whoosh", from, 0.8, 0.7)
end

function RangerFlair.Plant(center: Vector3, duration: number, zone: Vector3?)
	local folder = Instance.new("Folder")
	folder.Name = "RangerPlant"
	folder.Parent = plantFolder()
	local g = groundAt(center + Vector3.new(0, 2, 0))
	local rng = Random.new()

	-- ground frame pieces (roots), trunk pieces, tendril pieces, head pieces
	local ground: { { p: BasePart, cf: CFrame } } = {}
	local trunk: { { p: BasePart, cf: CFrame } } = {}
	local head: { Piece } = {}
	type Tendril = { segs: { BasePart }, thorns: { { Piece } }, tip: { Piece }, side: number, phase: number,
		lashAt: number, lashTo: Vector3? }
	local tendrils: { Tendril } = {}

	local function place(list: { any }, pieces: { Piece }, at: CFrame)
		for _, q in ipairs(pieces) do table.insert(list, { p = q.p, cf = at * q.cf }) end
	end
	local function cyl(a: Vector3, b: Vector3, thick: number, color: Color3, mat: Enum.Material): (BasePart, CFrame)
		local p = ppart(folder, { Shape = Enum.PartType.Cylinder, Color = color, Material = mat,
			Size = Vector3.new((b - a).Magnitude + thick * 0.35, thick, thick) })
		return p, CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0)
	end

	-- ── the roots: thick tentacles snaking out over the floor, thorned ──
	for i = 1, 8 do
		local ang = i / 8 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		local out = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local side = Vector3.new(-out.Z, 0, out.X)
		local len = rng:NextNumber(9, 13)
		local curl = rng:NextNumber(-1, 1)
		local prev = out * 1.2 + Vector3.new(0, 1.6, 0)
		for k = 1, 6 do
			local u = k / 6
			local pt = out * (1.2 + u * len) + side * math.sin(u * 3) * curl * 2 + Vector3.new(0, 1.6 * (1 - u) ^ 1.5 + math.sin(u * math.pi) * 0.8, 0)
			local thick = 2.6 * (1 - u * 0.75)
			local p, cf = cyl(prev, pt, thick, if k % 2 == 0 then PL_TRUNK else PL_TRUNK_DARK, Enum.Material.Grass)
			table.insert(ground, { p = p, cf = cf })
			if k <= 5 then
				local th = blade(folder, 0.9 * (1 - u * 0.5) + 0.3, 0.45, 0.25, PL_THORN)
				place(ground, th, CFrame.lookAt(pt + Vector3.new(0, thick * 0.45, 0), pt + Vector3.new(0, 5, 0) + side * (if k % 2 == 0 then 1 else -1)) * CFrame.new(0, 0, -0.3))
			end
			prev = pt
		end
	end
	-- leaves lying round its foot
	for i = 1, 7 do
		local ang = i / 7 * math.pi * 2 + 0.3
		local out = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local at = out * 3 + Vector3.new(0, 0.6, 0)
		place(ground, blade(folder, 5, 2.4, 0.3, if i % 2 == 0 then PL_LEAF else PL_LEAF_DARK, Enum.Material.Grass),
			CFrame.lookAt(at, at + out + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.new(0, 0, -2.4))
	end

	-- ── the trunk: thick, bending a little, leaves all up it ──
	local tpts = {}
	for k = 0, 6 do
		local u = k / 6
		tpts[k] = Vector3.new(math.sin(u * math.pi) * 1.0, u * (HEAD_H - 2.5), math.sin(u * math.pi * 1.6) * 0.6)
	end
	for k = 1, 6 do
		local thick = 4.8 * (1 - (k / 6) * 0.45)
		local p, cf = cyl(tpts[k - 1], tpts[k], thick, if k % 2 == 0 then PL_TRUNK else PL_TRUNK_DARK, Enum.Material.Grass)
		table.insert(trunk, { p = p, cf = cf })
	end
	for i = 1, 16 do
		local k = 1 + (i - 1) % 5
		local u = (k - 0.3) / 6
		local ang = i * 2.4
		local out = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local at = tpts[0]:Lerp(tpts[6], u) + out * (2.2 * (1 - u * 0.45))
		place(trunk, blade(folder, rng:NextNumber(2.4, 3.4), rng:NextNumber(1.4, 1.9), 0.3, if i % 3 == 0 then PL_LEAF else PL_LEAF_DARK, Enum.Material.Grass),
			CFrame.lookAt(at, at + out + Vector3.new(0, -0.5, 0)) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.new(0, 0, -1))
		if i % 2 == 0 then
			place(trunk, blade(folder, 0.9, 0.5, 0.3, PL_THORN), CFrame.lookAt(at, at + out + Vector3.new(0, 0.6, 0)) * CFrame.new(0, 0, -0.3))
		end
	end

	-- ── the tendrils: up out of the trunk either side, curling round at the
	-- top, thorned, a leaf at the tip ──
	for _, side in ipairs({ -1, 1 }) do
		local T: Tendril = { segs = {}, thorns = {}, tip = blade(folder, 2.6, 1.6, 0.3, PL_LEAF, Enum.Material.Grass), side = side, phase = rng:NextNumber(0, 6),
			lashAt = -10, lashTo = nil }
		for k = 1, 9 do
			T.segs[k] = ppart(folder, { Shape = Enum.PartType.Cylinder, Color = if k % 2 == 0 then PL_TRUNK else PL_TRUNK_DARK,
				Material = Enum.Material.Grass, Size = Vector3.one })
			if k % 2 == 1 then T.thorns[#T.thorns + 1] = blade(folder, 0.8, 0.45, 0.25, PL_THORN) end
		end
		table.insert(tendrils, T)
	end

	-- ── the head (its frame: the mouth faces -Z) ──
	-- leaves fanned behind
	for i = 1, 9 do
		local a = i / 9 * math.pi * 2 + 0.2
		place(head, blade(folder, 4.2, 2.6, 0.35, if i % 2 == 0 then PL_LEAF else PL_LEAF_DARK, Enum.Material.Grass),
			CFrame.new(0, 0, 1.2) * radial(a, 3.4, math.rad(-25)) * CFrame.new(0, 0, -2))
	end
	-- the crimson petals, cupped forward
	for i = 1, 11 do
		local a = i / 11 * math.pi * 2
		place(head, blade(folder, 3.4, 2.4, 0.45, if i % 2 == 0 then PL_PETAL else PL_PETAL_DARK),
			CFrame.new(0, 0, 0.2) * radial(a, 3.1, math.rad(30)) * CFrame.new(0, 0, -1.6))
	end
	-- the lip: a ring round the mouth
	for i = 1, 20 do
		local a = i / 20 * math.pi * 2
		local seg = ppart(folder, { Color = PL_PETAL, Material = Enum.Material.SmoothPlastic, Size = Vector3.new(1.15, 1.1, 1.0) })
		table.insert(head, { p = seg, cf = CFrame.Angles(0, 0, a) * CFrame.new(0, 2.85, -0.4) })
	end
	-- the throat: dark, a glowing green heart
	local throat = ppart(folder, { Shape = Enum.PartType.Cylinder, Color = PL_THROAT, Material = Enum.Material.SmoothPlastic, Size = Vector3.new(0.6, 5.2, 5.2) })
	table.insert(head, { p = throat, cf = CFrame.new(0, 0, 0.1) * CFrame.Angles(0, math.rad(90), 0) })
	local glowOuter = ppart(folder, { Shape = Enum.PartType.Ball, Color = PL_GLOW, Material = Enum.Material.Neon, Size = Vector3.one * 2.6, Transparency = 0.55 })
	table.insert(head, { p = glowOuter, cf = CFrame.new(0, 0, -0.3) })
	local glowCore = ppart(folder, { Shape = Enum.PartType.Ball, Color = Color3.fromRGB(220, 255, 170), Material = Enum.Material.Neon, Size = Vector3.one * 1.2 })
	table.insert(head, { p = glowCore, cf = CFrame.new(0, 0, -0.5) })
	-- the fangs: an outer ring and an inner ring, pointing in at the throat
	local fangs: { { pieces: { Piece }, a: number, r: number, inner: boolean } } = {}
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		table.insert(fangs, { pieces = blade(folder, 1.4, 0.75, 0.55, PL_FANG), a = a, r = 2.55, inner = false })
	end
	for i = 1, 11 do
		local a = i / 11 * math.pi * 2 + 0.15
		table.insert(fangs, { pieces = blade(folder, 1.0, 0.55, 0.45, PL_FANG), a = a, r = 1.75, inner = true })
	end

	local bodyNow = CFrame.new(g)
	local P: Plant = { mouth = g + Vector3.new(0, HEAD_H, 0), base = g, aim = nil, open = 0, lash = function(_: Vector3) end, spewUntil = 0 }
	-- the venom: a holder at the mouth (it moves with the head), the goo
	-- sprayed out of its front like a flamethrower
	local nozzle = ppart(folder, { Size = Vector3.one * 0.2, Transparency = 1 })
	table.insert(head, { p = nozzle, cf = CFrame.new(0, 0, -2) })
	local goo = emitter(nozzle, {
		Texture = TEX_SMOKE, Color = ColorSequence.new(VENOM, VENOM_DARK), LightEmission = 0, LightInfluence = 0.4,
		Size = seq(0, 1.6, 0.5, 3.6, 1, 5), Transparency = seq(0, 0, 0.6, 0.05, 1, 1), ZOffset = 1,
		Lifetime = NumberRange.new(0.45, 0.65), Speed = NumberRange.new(42, 55), SpreadAngle = Vector2.new(9, 9),
		EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, -30, 0), Drag = 1.2,
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-120, 120), Rate = 0,
	})
	local drops = emitter(nozzle, {
		Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(210, 255, 90)), LightEmission = 0.6,
		Size = seq(0, 0.5, 1, 0.2), Lifetime = NumberRange.new(0.4, 0.6), Speed = NumberRange.new(45, 60),
		SpreadAngle = Vector2.new(6, 6), EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, -40, 0), Rate = 0,
	})
	local nextPuddle = 0
	-- a whip: the tendril on that side lashes out at `to`
	P.lash = function(to: Vector3)
		local loc = bodyNow:PointToObjectSpace(to)
		local best = tendrils[1]
		for _, T in ipairs(tendrils) do
			if (loc.X >= 0) == (T.side > 0) then best = T end
		end
		-- (the other one if this one's mid-lash)
		if os.clock() - best.lashAt < 0.4 then
			for _, T in ipairs(tendrils) do if T ~= best then best = T end end
		end
		best.lashAt = os.clock()
		best.lashTo = to
		ClassFX.Sound("whoosh", to, 0.6, 1.3)
	end
	table.insert(plants, P)

	-- the great arrow into the sky (the cinematic's release shot)
	if zone then
		task.delay(RangerFlair.LOOSE_AT - RangerFlair.SLAM_AT - 0.14, function()
			if not folder.Parent then return end
			P.open = 1
			P.aim = zone + Vector3.new(0, 60, 0)
			skyArrow(P.mouth + Vector3.new(0, 1.5, 0), zone)
			task.delay(0.6, function() P.aim = nil end)
		end)
	end
	-- the burst out of the ground
	ringWave(folder, g, 1, 12, 0.5, LEAF, 0.3)
	cracks(folder, g, 9, 8)
	dirtChunks(folder, g, 16)
	leafBurst(g + Vector3.new(0, 1, 0), 24, 18)

	local yaw = math.random() * math.pi * 2
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	conn = RunService.RenderStepped:Connect(function(dt)
		local t = os.clock() - t0
		if not folder.Parent then
			if conn then conn:Disconnect() end
			return
		end
		-- up out of the ground in half a second (overshooting), down over the
		-- last half second
		local rise = math.clamp(t / 0.5, 0, 1)
		local up = 1 + 0.08 * math.sin(rise * math.pi) - (1 - rise) ^ 3
		local sink = math.clamp((t - duration) / 0.5, 0, 1)
		local lift = -(HEAD_H + 4) * (1 - math.min(up, 1) * (1 - sink))
		P.open = math.max(P.open - dt * 3, 0)
		table.clear(parts)
		table.clear(cfs)
		local base = CFrame.new(g)
		local rootGrow = math.min(up, 1) * (1 - sink)
		for _, q in ipairs(ground) do
			table.insert(parts, q.p)
			-- (the roots sink into the floor with it)
			table.insert(cfs, base * CFrame.new(0, (rootGrow - 1) * 3, 0) * q.cf)
		end
		-- the body sways a little; the head bobs
		local sway = math.sin(t * 1.3) * 0.04
		local body = base * CFrame.new(0, lift, 0) * CFrame.Angles(sway, 0, sway * 0.6)
		bodyNow = body
		for _, q in ipairs(trunk) do
			table.insert(parts, q.p)
			table.insert(cfs, body * q.cf)
		end
		-- the tendrils: out and up, curling round at the top, waving
		for _, T in ipairs(tendrils) do
			local s = T.side
			local pts = {}
			-- (out of the trunk's side, arching up and over outward, the tip
			-- curling under: a hook, like the sheet's; a whip wave always
			-- running up it)
			for k = 0, 9 do
				local u = k / 9
				local th = u * math.pi * 1.35
				local R = 4.5 * (1 - 0.45 * u)
				local wave = math.sin(t * 4 + T.phase - u * 4) * 1.4 * u ^ 1.5
				pts[k] = Vector3.new(s * (1.8 + 4.5 - R * math.cos(th) + wave), 5.5 + R * math.sin(th) + u * 4, math.sin(th * 0.5) * 1.2 + wave * 0.6)
			end
			-- the lash: it uncoils and cracks out straight at its mark, a wave
			-- snapping down it, then coils back
			local lk = (os.clock() - T.lashAt) / 0.45
			if T.lashTo and lk < 1 then
				local w = math.sin(math.min(lk, 1) * math.pi)
				local from = pts[0]
				local target = body:PointToObjectSpace(T.lashTo) + Vector3.new(0, 1, 0)
				local dir = target - from
				local perp = dir:Cross(Vector3.yAxis)
				perp = if perp.Magnitude > 0.01 then perp.Unit else Vector3.xAxis
				for k = 1, 9 do
					local u = k / 9
					local straight = from + dir * u + perp * math.sin(u * math.pi * 2 - lk * 10) * (1 - lk) * 1.5 * u
						+ Vector3.new(0, math.sin(u * math.pi) * 2.5, 0)
					pts[k] = pts[k]:Lerp(straight, w)
				end
			end
			for k = 1, 9 do
				local a, b = pts[k - 1], pts[k]
				local thick = 1.5 * (1 - (k / 9) * 0.6)
				local seg = T.segs[k]
				seg.Size = Vector3.new((b - a).Magnitude + thick * 0.35, thick, thick)
				table.insert(parts, seg)
				table.insert(cfs, body * CFrame.lookAt((a + b) / 2, b) * CFrame.Angles(0, math.rad(90), 0))
			end
			for j, th in ipairs(T.thorns) do
				local k = j * 2 - 1
				local mid = (pts[k - 1] + pts[k]) / 2
				local dir = (pts[k] - pts[k - 1]).Unit
				local nrm = dir:Cross(Vector3.zAxis)
				nrm = if nrm.Magnitude > 0.01 then nrm.Unit else Vector3.xAxis
				local at = CFrame.lookAt(mid, mid + nrm * (if j % 2 == 0 then 1 else -1)) * CFrame.new(0, 0, -0.5)
				for _, q in ipairs(th) do
					table.insert(parts, q.p)
					table.insert(cfs, body * at * q.cf)
				end
			end
			local tipAt = CFrame.lookAt(pts[9], pts[9] + (pts[9] - pts[8])) * CFrame.Angles(0, 0, math.pi / 2) * CFrame.new(0, 0, -1.2)
			for _, q in ipairs(T.tip) do
				table.insert(parts, q.p)
				table.insert(cfs, body * tipAt * q.cf)
			end
		end
		-- the head: turned to what it's aiming at, tipped down a little, rearing
		-- back as it spits
		local hpos = (body * CFrame.new(tpts[6] + Vector3.new(0, 2.6, 0))).Position
		P.mouth = hpos
		if P.aim then
			local d = P.aim - hpos
			local want = math.atan2(-d.X, -d.Z)
			local diff = (want - yaw + math.pi) % (math.pi * 2) - math.pi
			yaw += diff * math.min(dt * 8, 1)
		else
			yaw += dt * 0.4
		end
		local pitchTo = math.rad(-14)
		if P.aim then
			local d = P.aim - hpos
			pitchTo = math.clamp(math.atan2(d.Y, Vector3.new(d.X, 0, d.Z).Magnitude), math.rad(-35), math.rad(75))
		end
		local headCF = CFrame.new(hpos) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitchTo + P.open * math.rad(10), 0, 0)
			* CFrame.new(0, math.sin(t * 2) * 0.2, 0)
		for _, q in ipairs(head) do
			table.insert(parts, q.p)
			table.insert(cfs, headCF * q.cf)
		end
		-- (the fangs spread as it gapes)
		local spread = 1 + 0.18 * P.open
		for _, f in ipairs(fangs) do
			local at = headCF * CFrame.new(0, 0, -0.6) * radial(f.a, f.r * spread, math.rad(if f.inner then 25 else 40), true) * CFrame.new(0, 0, -0.5)
			for _, q in ipairs(f.pieces) do
				table.insert(parts, q.p)
				table.insert(cfs, at * q.cf)
			end
		end
		glowOuter.Transparency = 0.55 - 0.3 * P.open - 0.08 * math.sin(t * 6)
		local spewing = os.clock() < P.spewUntil and sink <= 0
		goo.Rate = if spewing then 140 else 0
		drops.Rate = if spewing then 40 else 0
		if spewing then
			P.open = math.max(P.open, 0.7)
			if P.aim and os.clock() >= nextPuddle then
				nextPuddle = os.clock() + 0.3
				local pg = groundAt(P.aim + Vector3.new(math.random(-3, 3), 2, math.random(-3, 3)))
				local puddle = ppart(folder, { Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(96, 150, 30), Material = Enum.Material.Glass, Transparency = 0.15,
					Size = Vector3.new(0.12, 1, 1), CFrame = CFrame.new(pg + Vector3.new(0, 0.07, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
				local r = math.random(30, 50) / 10
				TweenService:Create(puddle, TweenInfo.new(0.25), { Size = Vector3.new(0.12, r, r) }):Play()
				task.delay(1.4, function()
					if puddle.Parent then TweenService:Create(puddle, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
				end)
				Debris:AddItem(puddle, 2.1)
			end
		end
		Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if sink >= 1 then
			if conn then conn:Disconnect() end
			folder:Destroy()
			local idx = table.find(plants, P)
			if idx then table.remove(plants, idx) end
		end
	end)
end

-- A whip landing (the server's word): the nearest plant lashes at `to`, a
-- crack of green where it lands.
function RangerFlair.Whip(center: Vector3, to: Vector3)
	for _, P in ipairs(plants) do
		if (P.base - center).Magnitude < 8 then P.lash(to) end
	end
	task.delay(0.12, function()
		local g = groundAt(to + Vector3.new(0, 2, 0))
		ringWave(plantFolder(), g, 0.5, 5, 0.25, LEAF, 0.25)
		leafBurst(g + Vector3.new(0, 1, 0), 10, 16)
	end)
end

-- The venom (the server's word): the nearest plant turns to `to` and sprays
-- goo at it for `dur` seconds.
function RangerFlair.Venom(center: Vector3, to: Vector3, dur: number)
	for _, P in ipairs(plants) do
		if (P.base - center).Magnitude < 8 then
			P.aim = to
			P.spewUntil = os.clock() + dur
		end
	end
end

return RangerFlair
