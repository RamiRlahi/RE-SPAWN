--[[
	RangerFlair.luau
	Rain of Arrows wind-up (the 1s ult close-up):

	  0.00  bow hoisted overhead
	  0.36  SLAM — shockwave, glowing cracks, dirt chunks, leaf burst
	  0.36+ a ring of thorned vines spirals up around the ranger; druid runes turn
	  0.95  the ranger springs up and looses a glowing arrow into the sky
	  1.05  vines wither as the arrow storm lands
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

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
RangerFlair.LOOSE_AT = 0.95
RangerFlair.WITHER_AT = 1.05

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
	a.Parent = Workspace.Terrain
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
			local glow = segment(parent, p + Vector3.new(0, 0.08, 0), nxt + Vector3.new(0, 0.08, 0), 0.18, LEAF_GLOW, Enum.Material.Neon)
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

-- One vine: a curling spiral path that grows from the ground tip-first,
-- tapering, with thorns and glowing leaves along it.
local function growVine(parent: Instance, base: Vector3, center: Vector3, height: number, delay: number, growTime: number)
	local out = Vector3.new(base.X - center.X, 0, base.Z - center.Z)
	out = out.Magnitude > 0.01 and out.Unit or Vector3.xAxis
	local side = Vector3.new(-out.Z, 0, out.X) * (math.random() < 0.5 and 1 or -1)
	local N = 11
	local pts = {}
	for i = 0, N do
		local k = i / N
		-- Leans in toward the ranger, then curls outward at the top.
		local curl = math.sin(k * math.pi * 1.4) * 1.6
		local lean = -out * math.sin(k * math.pi) * 1.2 + out * (k ^ 2) * 1.8
		pts[i] = base + Vector3.new(0, k * height, 0) + side * curl + lean
	end
	task.delay(delay, function()
		if not parent.Parent then return end
		for i = 1, N do
			task.delay((i - 1) / N * growTime, function()
				if not parent.Parent then return end
				local k = i / N
				local thick = 0.75 * (1 - k * 0.75)
				local s = segment(parent, pts[i - 1], pts[i], thick, i % 2 == 0 and BARK or BARK_DARK, Enum.Material.Wood)
				-- Pop in: grow the segment's length from nothing.
				local full = s.Size
				s.Size = Vector3.new(0.05, full.Y, full.Z)
				TweenService:Create(s, TweenInfo.new(growTime / N * 1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = full }):Play()
				-- Glowing sap line on alternate segments.
				if i % 2 == 1 then
					segment(parent, pts[i - 1], pts[i], thick * 0.35, LEAF_GLOW, Enum.Material.Neon).Transparency = 0.2
				end
				-- Thorn.
				local mid = (pts[i - 1] + pts[i]) * 0.5
				local dir = (pts[i] - pts[i - 1]).Unit
				local nrm = dir:Cross(Vector3.yAxis)
				nrm = nrm.Magnitude > 0.01 and nrm.Unit or Vector3.xAxis
				part(parent, {
					ClassName = "WedgePart",
					Size = Vector3.new(0.12, 0.6 * (1 - k * 0.5), 0.3),
					CFrame = CFrame.lookAt(mid, mid + nrm * (i % 2 == 0 and 1 or -1)) * CFrame.Angles(math.rad(-90), 0, 0),
					Color = BARK_DARK,
					Material = Enum.Material.Wood,
				})
				-- Leaf pair every few segments.
				if i % 3 == 0 then
					for s2 = -1, 1, 2 do
						local leaf = part(parent, {
							Size = Vector3.new(0.05, 0.9, 0.5),
							CFrame = CFrame.lookAt(mid, mid + nrm * s2 + Vector3.new(0, 0.6, 0)) * CFrame.new(0, 0, -0.45) * CFrame.Angles(math.rad(70), 0, 0),
							Color = LEAF,
							Material = Enum.Material.Neon,
							Transparency = 0.15,
						})
						local full2 = leaf.Size
						leaf.Size = Vector3.new(0.05, 0.1, 0.1)
						TweenService:Create(leaf, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = full2 }):Play()
					end
				end
				-- Bud of light at the growing tip.
				if i == N then
					local bud = part(parent, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.8, 0.8, 0.8), CFrame = CFrame.new(pts[N]), Color = LEAF_GLOW, Material = Enum.Material.Neon })
					local l = Instance.new("PointLight")
					l.Color, l.Brightness, l.Range = LEAF_GLOW, 1.5, 8
					l.Parent = bud
					emitter(bud, {
						Texture = TEX_SPARKLE, Color = ColorSequence.new(SPORE), LightEmission = 1,
						Size = seq(0, 0.3, 1, 0), Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(1, 3),
						SpreadAngle = Vector2.new(180, 180), Rate = 12,
					})
				end
			end)
		end
	end)
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
function RangerFlair.playUltWindup(char: Model)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local folder = Instance.new("Folder")
	folder.Name = "RangerUltWindup"
	folder.Parent = Workspace.Terrain
	local center = groundAt(root.Position)

	-- Gathering: green motes spiral into the bow before the slam.
	local gather = att(root.Position + Vector3.new(0, 2.5, 0))
	gather.Parent = folder
	emitter(gather, {
		Texture = TEX_SPARKLE, Color = ColorSequence.new(LEAF_GLOW, LEAF), LightEmission = 1,
		Size = seq(0, 0.5, 1, 0), Lifetime = NumberRange.new(0.3, 0.4), Speed = NumberRange.new(-14, -10),
		SpreadAngle = Vector2.new(180, 180), Rate = 70,
	})

	task.delay(RangerFlair.SLAM_AT, function()
		if not folder.Parent then return end
		gather:Destroy()
		-- SLAM.
		ringWave(folder, center, 1, 16, 0.5, LEAF_GLOW, 0.9)
		task.delay(0.07, function() ringWave(folder, center, 1, 11, 0.45, BARK, 1.3) end)
		cracks(folder, center, 9, 9)
		dirtChunks(folder, center, 14)
		leafBurst(center + Vector3.new(0, 0.5, 0), 40, 26)
		local flash = att(center + Vector3.new(0, 2, 0))
		flash.Parent = folder
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range = LEAF_GLOW, 7, 30
		l.Parent = flash
		TweenService:Create(l, TweenInfo.new(0.6), { Brightness = 1.5 }):Play()
		shake(char, 0.7, 0.35)

		-- Druidic rune circle: two counter-rotating rings of leaf-green light.
		local runes = {}
		for r = 1, 2 do
			local segs = {}
			for i = 1, 30 do
				segs[i] = part(folder, { Color = r == 1 and LEAF or LEAF_GLOW, Material = Enum.Material.Neon, Transparency = 0.35 })
			end
			runes[r] = segs
		end
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			if not folder.Parent then conn:Disconnect() return end
			local t = os.clock() - t0
			local grow = 1 - (1 - math.clamp(t / 0.3, 0, 1)) ^ 3
			for r, segs in ipairs(runes) do
				local radius = (r == 1 and 7 or 5.2) * grow
				local spin = t * (r == 1 and 0.8 or -1.3)
				local segLen = 2 * math.pi * radius / #segs * 0.7 -- dashed ring
				for i, s in ipairs(segs) do
					local a = (i / #segs) * math.pi * 2 + spin
					local p = center + Vector3.new(math.cos(a) * radius, 0.1, math.sin(a) * radius)
					s.Size = Vector3.new(r == 1 and 0.3 or 0.18, 0.05, math.max(segLen, 0.05))
					s.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
				end
			end
		end)

		-- The vines: an inner ring of tall vines and an outer ring of short ones.
		for i = 1, 7 do
			local a = (i / 7) * math.pi * 2 + math.random() * 0.3
			local b = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (3.2 + math.random() * 0.8)
			growVine(folder, b, center, 7 + math.random() * 3, math.random() * 0.06, 0.38)
		end
		for i = 1, 9 do
			local a = (i / 9) * math.pi * 2 + math.random() * 0.4
			local b = center + Vector3.new(math.cos(a), 0, math.sin(a)) * (6.5 + math.random() * 2)
			growVine(folder, b, center, 3 + math.random() * 2, 0.05 + math.random() * 0.1, 0.3)
		end

		-- Drifting spores through the vines.
		local sporeAtt = att(center + Vector3.new(0, 1, 0))
		sporeAtt.Parent = folder
		emitter(sporeAtt, {
			Texture = TEX_SPARKLE, Color = ColorSequence.new(SPORE, LEAF), LightEmission = 1,
			Size = seq(0, 0.35, 1, 0), Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(70, 70), EmissionDirection = Enum.NormalId.Top, Rate = 40,
		})
	end)

	-- LOOSE: a glowing arrow streaks into the sky.
	task.delay(RangerFlair.LOOSE_AT, function()
		if not folder.Parent or not root.Parent then return end
		local from = root.Position + Vector3.new(0, 3, 0)
		local arrow = part(folder, { Size = Vector3.new(0.35, 0.35, 5), CFrame = CFrame.lookAt(from, from + Vector3.yAxis), Color = LEAF_GLOW, Material = Enum.Material.Neon })
		local a0 = Instance.new("Attachment"); a0.Position = Vector3.new(0.3, 0, 2); a0.Parent = arrow
		local a1 = Instance.new("Attachment"); a1.Position = Vector3.new(-0.3, 0, 2); a1.Parent = arrow
		local trail = Instance.new("Trail")
		trail.Attachment0, trail.Attachment1 = a0, a1
		trail.Color = ColorSequence.new(LEAF_GLOW, LEAF)
		trail.LightEmission = 1
		trail.Lifetime = 0.35
		trail.FaceCamera = true
		trail.Transparency = seq(0, 0, 1, 1)
		trail.Parent = arrow
		TweenService:Create(arrow, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = arrow.CFrame + Vector3.new(0, 90, 0) }):Play()
		ringWave(folder, root.Position - Vector3.new(0, 2.6, 0), 0.5, 6, 0.3, LEAF_GLOW, 0.4)
		leafBurst(root.Position + Vector3.new(0, 2, 0), 16, 16)
	end)

	-- WITHER as the storm lands.
	task.delay(RangerFlair.WITHER_AT, function()
		if not folder.Parent then return end
		for _, d in ipairs(folder:GetDescendants()) do
			if d:IsA("BasePart") and d.Material == Enum.Material.Wood then
				TweenService:Create(d, TweenInfo.new(0.8), { Color = Color3.fromRGB(70, 55, 35) }):Play()
			end
		end
		task.wait(0.5)
		fade(folder, 0.7)
		Debris:AddItem(folder, 1)
	end)
end

return RangerFlair
