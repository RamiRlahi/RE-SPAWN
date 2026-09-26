--[[
	ClericFlair.luau
	Extra layers of holy spectacle on top of the Cleric's base VFX:

	  watchHalos        — persistent halo + drifting light motes on every cleric
	  smite             — M1 muzzle flare, light cross and sunburst on release
	  heal              — pillar from the heavens, rising halo rings, feathers
	  beamAura          — radiant sun-wheel behind the caster during Divine Beam
	  radiantGround     — rotating sacred sigil, rising light columns, triple bell toll
	  judgment          — Divine Ascent climax: sunburst, god rays, shockwave
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local HOLY_WHITE = Color3.fromRGB(255, 253, 240)
local HOLY_IVORY = Color3.fromRGB(255, 244, 210)
local HOLY_GOLD = Color3.fromRGB(255, 205, 95)
local HOLY_AMBER = Color3.fromRGB(255, 170, 50)
local HEAL_GREEN = Color3.fromRGB(150, 255, 170)

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_RAY = "rbxassetid://1053548563"

local ClericFlair = {}

-- ─── Helpers ────────────────────────────────────────────────────────────────
local function folder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = Workspace.Terrain
	return f
end

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.LightEmission = 1
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
	local kps = {}
	for i = 1, #a, 2 do
		table.insert(kps, NumberSequenceKeypoint.new(a[i], a[i + 1]))
	end
	return NumberSequence.new(kps)
end

local function att(pos: Vector3, parent: Instance?): Attachment
	local a = Instance.new("Attachment")
	a.Parent = parent or Workspace.Terrain
	a.WorldPosition = pos
	return a
end

local function light(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range, l.Shadows = color, brightness, range, false
	l.Parent = parent
	return l
end

local function flash(pos: Vector3, color: Color3, brightness: number, range: number, life: number)
	local a = att(pos)
	local l = light(a, color, brightness, range)
	TweenService:Create(l, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(a, life + 0.1)
end

local function fade(root: Instance, t: number)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
			d.Enabled = false
		elseif d:IsA("Light") then
			TweenService:Create(d, TweenInfo.new(t), { Brightness = 0 }):Play()
		end
	end
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true
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
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), groundParams)
	return hit and hit.Position or (pos - Vector3.new(0, 3, 0))
end

-- Ring of neon segments (constant stroke) we can re-lay at any radius.
local function ring(parent: Instance, n: number, color: Color3, transparency: number): { BasePart }
	local parts = {}
	for i = 1, n do
		parts[i] = part(parent, { Color = color, Transparency = transparency })
	end
	return parts
end

local function layRing(parts: { BasePart }, cf: CFrame, radius: number, thick: number)
	local segLen = 2 * math.pi * radius / #parts * 1.1
	for i, p in ipairs(parts) do
		local a = (i / #parts) * math.pi * 2
		local local_ = CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius)
		p.Size = Vector3.new(thick, thick * 0.5, math.max(segLen, 0.05))
		p.CFrame = cf * local_ * CFrame.Angles(0, -a, 0)
	end
end

local function shockwave(parent: Instance, cf: CFrame, r0: number, r1: number, t: number, color: Color3, thick: number)
	local holder = Instance.new("Folder")
	holder.Parent = parent
	local parts = ring(holder, 40, color, 0)
	layRing(parts, cf, r0, thick)
	local t0 = os.clock()
	local c
	c = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / t, 0, 1)
		if a >= 1 or not holder.Parent then
			c:Disconnect()
			holder:Destroy()
			return
		end
		local e = 1 - (1 - a) ^ 3
		layRing(parts, cf, r0 + (r1 - r0) * e, thick * (1 - a * 0.6))
		for _, p in ipairs(parts) do p.Transparency = a end
	end)
end

-- Feathers: thin twin-wedge vanes that drift down, swaying.
local function feathers(parent: Instance, center: Vector3, count: number, spread: number, height: number, life: number, color: Color3?)
	for _ = 1, count do
		local start = center + Vector3.new((math.random() - 0.5) * spread, height * (0.6 + math.random() * 0.6), (math.random() - 0.5) * spread)
		local vane = part(parent, {
			ClassName = "WedgePart",
			Size = Vector3.new(0.05, 1.1, 0.35),
			Color = color or HOLY_IVORY,
			Transparency = 0.1,
		})
		local phase = math.random() * 6.28
		local spin = (math.random() - 0.5) * 4
		local fall = height / life * (0.7 + math.random() * 0.5)
		local t0 = os.clock()
		local c
		c = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			if t > life or not vane.Parent then
				c:Disconnect()
				vane:Destroy()
				return
			end
			local sway = math.sin(t * 3 + phase) * 1.4
			vane.CFrame = CFrame.new(start + Vector3.new(sway, -fall * t, math.cos(t * 2.3 + phase) * 0.8))
				* CFrame.Angles(math.sin(t * 3 + phase) * 0.7, t * spin, 0.4)
			vane.Transparency = 0.1 + 0.9 * math.max(0, (t / life - 0.7) / 0.3)
		end)
	end
end

local function sparkBurst(pos: Vector3, count: number, speed: number, color: Color3, size: number)
	local a = att(pos)
	emitter(a, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(HOLY_WHITE, color),
		Size = seq(0, size, 1, 0),
		Lifetime = NumberRange.new(0.35, 0.8),
		Speed = NumberRange.new(speed * 0.4, speed),
		SpreadAngle = Vector2.new(180, 180),
		Drag = 4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-200, 200),
	}):Emit(count)
	Debris:AddItem(a, 1.2)
end

-- Radiating sun-wheel of light spokes (flat, facing `cf`'s look direction).
local function sunWheel(parent: Instance, spokes: number, len: number, color: Color3, transparency: number): { BasePart }
	local parts = {}
	for i = 1, spokes do
		parts[i] = part(parent, {
			Size = Vector3.new(0.12, len * (i % 2 == 0 and 0.6 or 1), 0.12),
			Color = color,
			Transparency = transparency,
		})
	end
	return parts
end

local function laySunWheel(parts: { BasePart }, cf: CFrame, inner: number, spin: number)
	for i, p in ipairs(parts) do
		local a = (i / #parts) * math.pi * 2 + spin
		p.CFrame = cf * CFrame.Angles(0, 0, a) * CFrame.new(0, inner + p.Size.Y * 0.5, 0)
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Persistent halo on every cleric
-- ═════════════════════════════════════════════════════════════════════════════
local halos: { [Model]: Folder } = {}

local function attachHalo(char: Model)
	if halos[char] then return end
	local head = char:WaitForChild("Head", 5) :: BasePart?
	if not head then return end
	local f = folder("ClericHalo")
	halos[char] = f
	local parts = ring(f, 22, HOLY_GOLD, 0.05)
	local inner = ring(f, 22, HOLY_WHITE, 0.35)
	local glow = part(f, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
	light(glow, HOLY_GOLD, 0.9, 7)
	local motes = emitter(glow, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(HOLY_WHITE, HOLY_GOLD),
		Size = seq(0, 0.25, 1, 0),
		Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(0.5, 1.5),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -1.5, 0),
		Rate = 6,
	})
	local t0 = os.clock()
	local c
	c = RunService.RenderStepped:Connect(function()
		if not char.Parent or not head.Parent then
			c:Disconnect()
			halos[char] = nil
			f:Destroy()
			return
		end
		local t = os.clock() - t0
		local cf = head.CFrame * CFrame.new(0, 1.15 + math.sin(t * 2) * 0.08, 0.1) * CFrame.Angles(math.rad(-12), t * 0.8, 0)
		layRing(parts, cf, 0.95, 0.14)
		layRing(inner, cf, 0.8, 0.07)
		glow.CFrame = cf
		motes.Enabled = true
		-- Hide the halo during the Divine Ascent cutscene (angel wings take over).
		local hidden = char:GetAttribute("HideHalo") == true
		for _, p in ipairs(parts) do p.LocalTransparencyModifier = hidden and 1 or 0 end
		for _, p in ipairs(inner) do p.LocalTransparencyModifier = hidden and 1 or 0 end
	end)
end

function ClericFlair.watchHalos()
	local function hook(plr: Player)
		local function refresh()
			local char = plr.Character
			if char and plr:GetAttribute("SelectedClass") == "cleric" then
				task.spawn(attachHalo, char)
			elseif char and halos[char] then
				halos[char]:Destroy()
				halos[char] = nil
			end
		end
		plr.CharacterAdded:Connect(function() task.defer(refresh) end)
		plr:GetAttributeChangedSignal("SelectedClass"):Connect(refresh)
		refresh()
	end
	for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
	Players.PlayerAdded:Connect(hook)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- M1: Radiant Smite flourish
-- ═════════════════════════════════════════════════════════════════════════════
function ClericFlair.smite(char: Model, dir: Vector3)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = flat.Magnitude > 0.01 and flat.Unit or root.CFrame.LookVector
	local pos = root.Position + Vector3.new(0, 0.6, 0) + flat * 2.4
	local f = folder("SmiteFlair")
	local face = CFrame.lookAt(pos, pos + flat)

	-- Light cross stamped in the air at the release point.
	local v = part(f, { Size = Vector3.new(0.35, 3.2, 0.1), Color = HOLY_WHITE, CFrame = face })
	local h = part(f, { Size = Vector3.new(2.1, 0.35, 0.1), Color = HOLY_WHITE, CFrame = face * CFrame.new(0, 0.55, 0) })
	for _, p in ipairs({ v, h }) do
		TweenService:Create(p, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = p.Size * 1.6, Transparency = 1, Color = HOLY_GOLD }):Play()
	end
	local spokes = sunWheel(f, 12, 1.4, HOLY_GOLD, 0.2)
	laySunWheel(spokes, face, 0.6, 0)
	for _, p in ipairs(spokes) do
		TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play()
	end
	shockwave(f, face * CFrame.Angles(math.rad(90), 0, 0), 0.4, 2.8, 0.25, HOLY_GOLD, 0.12)
	sparkBurst(pos, 8, 10, HOLY_GOLD, 0.6)
	flash(pos, HOLY_GOLD, 3, 12, 0.25)
	Debris:AddItem(f, 0.45)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Heal: pillar from the heavens, ascending halos, feathers
-- ═════════════════════════════════════════════════════════════════════════════
function ClericFlair.heal(targetPos: Vector3)
	local f = folder("HealFlair")
	local g = groundAt(targetPos)

	-- Pillar of light slams down, then thins away.
	local pillar = part(f, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(120, 3.6, 3.6),
		CFrame = CFrame.new(g + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = HOLY_WHITE,
		Transparency = 0.15,
	})
	local sleeve = part(f, {
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(120, 7, 7),
		CFrame = pillar.CFrame,
		Color = HEAL_GREEN,
		Transparency = 0.75,
	})
	TweenService:Create(pillar, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(120, 0.1, 0.1), Transparency = 1 }):Play()
	TweenService:Create(sleeve, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(120, 0.4, 0.4), Transparency = 1 }):Play()

	-- Three halo rings climb the body, spinning.
	for k = 1, 3 do
		task.delay((k - 1) * 0.09, function()
			local parts = ring(f, 24, k == 2 and HOLY_GOLD or HEAL_GREEN, 0.05)
			local t0 = os.clock()
			local c
			c = RunService.RenderStepped:Connect(function()
				local a = math.clamp((os.clock() - t0) / 0.7, 0, 1)
				if a >= 1 then
					c:Disconnect()
					for _, p in ipairs(parts) do p:Destroy() end
					return
				end
				local e = 1 - (1 - a) ^ 2
				local cf = CFrame.new(g + Vector3.new(0, 0.3 + e * 6.5, 0)) * CFrame.Angles(0, a * 5, 0)
				layRing(parts, cf, 2.6 - e * 1.2, 0.18)
				for _, p in ipairs(parts) do p.Transparency = 0.05 + a * 0.95 end
			end)
		end)
	end

	shockwave(f, CFrame.new(g + Vector3.new(0, 0.2, 0)), 0.5, 7, 0.45, HEAL_GREEN, 0.3)
	local a = att(g + Vector3.new(0, 0.5, 0))
	emitter(a, {
		Texture = TEX_SPARKLE,
		Color = ColorSequence.new(HOLY_WHITE, HEAL_GREEN),
		Size = seq(0, 0.5, 1, 0),
		Lifetime = NumberRange.new(0.8, 1.3),
		Speed = NumberRange.new(5, 10),
		SpreadAngle = Vector2.new(12, 12),
		EmissionDirection = Enum.NormalId.Top,
		Acceleration = Vector3.new(0, 4, 0),
		Rotation = NumberRange.new(0, 360),
	}):Emit(26)
	Debris:AddItem(a, 1.5)
	feathers(f, g, 6, 5, 7, 1.6)
	flash(g + Vector3.new(0, 3, 0), HEAL_GREEN, 5, 18, 0.6)
	Debris:AddItem(f, 2)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Divine Beam: sun-wheel halo behind the caster, sigil, drifting feathers
-- ═════════════════════════════════════════════════════════════════════════════
function ClericFlair.beamAura(char: Model, duration: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local f = folder("BeamAura")
	local outer = ring(f, 36, HOLY_GOLD, 0.1)
	local innerRing = ring(f, 30, HOLY_WHITE, 0.3)
	local spokes = sunWheel(f, 24, 2.6, HOLY_GOLD, 0.35)
	local glow = part(f, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
	local l = light(glow, HOLY_GOLD, 3, 20)
	local rays = emitter(glow, {
		Texture = TEX_RAY,
		Color = ColorSequence.new(HOLY_WHITE, HOLY_GOLD),
		Size = seq(0, 3, 1, 0.5),
		Transparency = seq(0, 0.4, 1, 1),
		Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(6, 10),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 22,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})
	-- Ground sigil: counter-rotating rings.
	local sig1 = ring(f, 40, HOLY_GOLD, 0.35)
	local sig2 = ring(f, 32, HOLY_IVORY, 0.5)
	local ground = groundAt(root.Position)

	local t0 = os.clock()
	local c
	c = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > duration or not char.Parent or not root.Parent then
			c:Disconnect()
			fade(f, 0.35)
			Debris:AddItem(f, 0.5)
			return
		end
		local grow = math.clamp(t / 0.25, 0, 1)
		local pulse = 1 + math.sin(t * 9) * 0.05
		local back = root.CFrame * CFrame.new(0, 1.6, 1.6)
		layRing(outer, back * CFrame.Angles(math.rad(90), 0, 0), 3.2 * grow * pulse, 0.2)
		layRing(innerRing, back * CFrame.Angles(math.rad(90), 0, 0), 2.3 * grow, 0.1)
		laySunWheel(spokes, back, 2.4 * grow, t * 0.9)
		for _, p in ipairs(spokes) do p.LocalTransparencyModifier = 1 - grow end
		glow.CFrame = back
		l.Brightness = 3 + math.sin(t * 9) * 0.8
		local gcf = CFrame.new(Vector3.new(root.Position.X, ground.Y + 0.1, root.Position.Z))
		layRing(sig1, gcf * CFrame.Angles(0, t * 0.7, 0), 5.5 * grow, 0.22)
		layRing(sig2, gcf * CFrame.Angles(0, -t * 1.1, 0), 4.2 * grow, 0.12)
		rays.Enabled = grow >= 1
	end)
	task.spawn(function()
		local t0b = os.clock()
		while os.clock() - t0b < duration and f.Parent do
			feathers(f, root.Position, 2, 6, 5, 1.6, HOLY_IVORY)
			task.wait(0.35)
		end
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Radiant Ground: sacred sigil, light columns, triple bell toll
-- ═════════════════════════════════════════════════════════════════════════════
function ClericFlair.radiantGround(origin: Vector3, radius: number)
	local f = folder("RadiantFlair")
	local g = groundAt(origin) + Vector3.new(0, 0.12, 0)
	local base = CFrame.new(g)

	local outer = ring(f, 56, HOLY_GOLD, 0.1)
	local mid = ring(f, 44, HOLY_IVORY, 0.3)
	local inner = ring(f, 30, HOLY_GOLD, 0.2)
	-- Hexagram: two interlocking triangles of light.
	local tri = {}
	for i = 1, 6 do
		tri[i] = part(f, { Size = Vector3.new(0.18, 0.08, 1), Color = HOLY_WHITE, Transparency = 0.15 })
	end
	local function layTri(r: number, spin: number)
		for k = 0, 1 do
			for i = 0, 2 do
				local a1 = spin + k * math.pi / 3 + i * (2 * math.pi / 3)
				local a2 = a1 + 2 * math.pi / 3
				local p1 = g + Vector3.new(math.cos(a1), 0, math.sin(a1)) * r
				local p2 = g + Vector3.new(math.cos(a2), 0, math.sin(a2)) * r
				local p = tri[k * 3 + i + 1]
				p.Size = Vector3.new(0.18, 0.08, (p2 - p1).Magnitude)
				p.CFrame = CFrame.lookAt((p1 + p2) * 0.5, p2)
			end
		end
	end

	-- Light columns erupting around the edge.
	local columns = {}
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		local pos = g + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.92
		local col = part(f, {
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, 1.1, 1.1),
			CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
			Color = HOLY_IVORY,
			Transparency = 0.2,
		})
		columns[i] = { part = col, pos = pos, h = 14 + math.random() * 8 }
	end

	local t0 = os.clock()
	local LIFE = 2.4
	local c
	c = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > LIFE then
			c:Disconnect()
			fade(f, 0.5)
			Debris:AddItem(f, 0.7)
			return
		end
		local grow = 1 - (1 - math.clamp(t / 0.35, 0, 1)) ^ 3
		layRing(outer, base * CFrame.Angles(0, t * 0.5, 0), radius * grow, 0.4)
		layRing(mid, base * CFrame.Angles(0, -t * 0.8, 0), radius * 0.78 * grow, 0.18)
		layRing(inner, base * CFrame.Angles(0, t * 1.2, 0), radius * 0.4 * grow, 0.25)
		layTri(radius * 0.76 * grow, t * 0.6)
		for i, col in ipairs(columns) do
			local ct = math.clamp((t - 0.15 - i * 0.03) / 0.25, 0, 1)
			local h = col.h * (1 - (1 - ct) ^ 3)
			col.part.Size = Vector3.new(math.max(h, 0.1), 1.1 * (1 - math.max(0, t - 1.2) / 1.2), 1.1 * (1 - math.max(0, t - 1.2) / 1.2))
			col.part.CFrame = CFrame.new(col.pos + Vector3.new(0, h * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		end
	end)

	-- Triple bell toll: three expanding shockwaves.
	for k = 0, 2 do
		task.delay(0.12 + k * 0.28, function()
			shockwave(f, base * CFrame.new(0, 0.2, 0), 1, radius * (1.05 + k * 0.1), 0.55, k == 1 and HOLY_WHITE or HOLY_GOLD, 0.5 - k * 0.1)
			flash(g + Vector3.new(0, 4, 0), HOLY_GOLD, 6 - k * 1.5, radius * 2, 0.4)
		end)
	end
	feathers(f, g, 14, radius * 1.6, 12, 2.2)
	sparkBurst(g + Vector3.new(0, 1, 0), 30, 24, HOLY_GOLD, 0.8)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Divine Ascent climax: judgment sunburst in the sky
-- ═════════════════════════════════════════════════════════════════════════════
function ClericFlair.judgment(center: Vector3, faceToward: Vector3)
	local f = folder("JudgmentFlair")
	local face = CFrame.lookAt(center, faceToward)

	-- White-hot core.
	local core = part(f, { Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), CFrame = CFrame.new(center), Color = HOLY_WHITE })
	TweenService:Create(core, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * 34, Transparency = 1 }):Play()
	local shell = part(f, { Shape = Enum.PartType.Ball, Size = Vector3.new(6, 6, 6), CFrame = CFrame.new(center), Color = HOLY_GOLD, Material = Enum.Material.ForceField, Transparency = 0 })
	TweenService:Create(shell, TweenInfo.new(1.2, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * 70, Transparency = 1 }):Play()

	-- Giant rotating sunburst facing the camera.
	local spokes = sunWheel(f, 32, 26, HOLY_GOLD, 0.1)
	local t0 = os.clock()
	local c
	c = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > 1.6 then
			c:Disconnect()
			return
		end
		local e = 1 - (1 - math.clamp(t / 0.5, 0, 1)) ^ 3
		laySunWheel(spokes, face, 2 + e * 6, t * 0.6)
		for _, p in ipairs(spokes) do p.Transparency = 0.1 + math.clamp((t - 0.6) / 1, 0, 1) * 0.9 end
	end)

	-- Stacked shockwaves in three planes.
	shockwave(f, CFrame.new(center), 2, 60, 0.9, HOLY_WHITE, 1.2)
	shockwave(f, face * CFrame.Angles(math.rad(90), 0, 0), 2, 45, 0.8, HOLY_GOLD, 0.9)
	task.delay(0.15, function() shockwave(f, CFrame.new(center) * CFrame.Angles(0, 0, math.rad(35)), 2, 50, 0.9, HOLY_AMBER, 0.8) end)

	-- God rays lancing down to the world below.
	for i = 1, 8 do
		task.delay(i * 0.04, function()
			local a = (i / 8) * math.pi * 2
			local top = center + Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6)
			local bottom = top + Vector3.new(math.cos(a) * 30, -170, math.sin(a) * 30)
			local len = (bottom - top).Magnitude
			local ray = part(f, { Size = Vector3.new(1.6, 1.6, len), CFrame = CFrame.lookAt((top + bottom) * 0.5, bottom), Color = HOLY_IVORY, Transparency = 0.2 })
			TweenService:Create(ray, TweenInfo.new(1.1, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(0.1, 0.1, len), Transparency = 1 }):Play()
		end)
	end
	sparkBurst(center, 80, 70, HOLY_GOLD, 2.2)
	feathers(f, center, 30, 50, 10, 2.8)
	flash(center, HOLY_WHITE, 14, 120, 1.2)
	Debris:AddItem(f, 3.2)
end

return ClericFlair
