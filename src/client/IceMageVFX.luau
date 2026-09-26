--[[
	IceMageVFX.luau
	Client-side visuals for the Ice Mage kit. Everything is built procedurally from
	layered crystal geometry (glass shell + neon core), particles, lights and
	shockwaves so it needs no uploaded assets.

	  playCrystalBolt   — M1: a single sleek ice crystal
	  playIceSpikes     — Skill 1: racing line of spikes erupting from the floor
	  playIceBeam       — Skill 2: channelled beam that stops on the first enemy
	  decorateClone     — Skill 3: crystalline body, core, aura, orbiting shards
	  playCloneShatter  — Skill 3: death explosion + freezing shockwave
	  playBlizzard      — Ultimate: storm zone
	  playChill         — frozen-target feedback (sent by the server)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

-- ─── Palette ────────────────────────────────────────────────────────────────
local ICE_WHITE = Color3.fromRGB(240, 252, 255)
local ICE_PALE = Color3.fromRGB(190, 240, 255)
local ICE_CYAN = Color3.fromRGB(90, 220, 255)
local ICE_BLUE = Color3.fromRGB(60, 150, 255)
local ICE_DEEP = Color3.fromRGB(35, 90, 200)

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_STREAK = "rbxassetid://1053548563"

local IceMageVFX = {}
local shakeFn: ((number, number) -> ())? = nil

-- ─── Generic helpers ────────────────────────────────────────────────────────
local function vfxFolder(name: string): Folder
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = Workspace.Terrain
	return f
end

local function newPart(parent: Instance, props: { [string]: any }): BasePart
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

local function newEmitter(parent: Instance, props: { [string]: any }): ParticleEmitter
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
	local args = { ... }
	local kps = {}
	for i = 1, #args, 2 do
		table.insert(kps, NumberSequenceKeypoint.new(args[i], args[i + 1]))
	end
	return NumberSequence.new(kps)
end

local function colors(a: Color3, b: Color3): ColorSequence
	return ColorSequence.new(a, b)
end

local function attachmentAt(pos: Vector3): Attachment
	local att = Instance.new("Attachment")
	att.Parent = Workspace.Terrain
	att.WorldPosition = pos
	return att
end

local function flashLight(pos: Vector3, color: Color3, brightness: number, range: number, life: number)
	local att = attachmentAt(pos)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Shadows = false
	light.Parent = att
	TweenService:Create(light, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Brightness = 0 }):Play()
	Debris:AddItem(att, life + 0.1)
end

local function fadeOut(root: Instance, t: number, extra: { [string]: any }?)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1 }):Play()
		elseif d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") then
			d.Enabled = false
		elseif d:IsA("Light") then
			TweenService:Create(d, TweenInfo.new(t), { Brightness = 0 }):Play()
		end
	end
	if root:IsA("BasePart") then
		TweenService:Create(root, TweenInfo.new(t), { Transparency = 1 }):Play()
	end
end

local function shake(intensity: number, duration: number, pos: Vector3?)
	if not shakeFn then return end
	if pos then
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then return end
		local d = (root.Position - pos).Magnitude
		if d > 90 then return end
		intensity *= math.clamp(1 - d / 90, 0.2, 1)
	end
	shakeFn(intensity, duration)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.IgnoreWater = true

-- Floor/wall probes ignore characters, mobs, ice clones and VFX (which live
-- under Terrain — Terrain itself stays hittable as a floor).
local function nonWorldInstances(): { Instance }
	local list = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(list, plr.Character) end
	end
	for _, name in ipairs({ "IceClones", "Mobs" }) do
		local f = Workspace:FindFirstChild(name)
		if f then table.insert(list, f) end
	end
	for _, child in ipairs(Workspace.Terrain:GetChildren()) do
		table.insert(list, child)
	end
	return list
end

local function refreshGroundFilter()
	groundParams.FilterDescendantsInstances = nonWorldInstances()
end

local function groundAt(pos: Vector3, fallbackY: number?): (Vector3, Vector3)
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), groundParams)
	if hit then
		return hit.Position, hit.Normal
	end
	return Vector3.new(pos.X, fallbackY or (pos.Y - 3), pos.Z), Vector3.yAxis
end

local function flatUnit(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 0.001 then return Vector3.new(0, 0, -1) end
	return f.Unit
end

-- Living enemies the client can see (mobs); excludes players and ice clones.
local function getEnemyRoots(exclude: Model?): { BasePart }
	local out = {}
	for _, d in ipairs(Workspace:GetDescendants()) do
		if d:IsA("Humanoid") and d.Health > 0 then
			local m = d.Parent
			if m and m:IsA("Model") and m ~= exclude and not Players:GetPlayerFromCharacter(m)
				and m:GetAttribute("IsDecoy") ~= true and not m:FindFirstAncestorOfClass("Accessory") then
				local r = m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart
				if r and r:IsA("BasePart") then table.insert(out, r) end
			end
		end
	end
	return out
end

-- First enemy along a flat ray; returns distance along the ray and its root.
local function firstEnemyOnLine(roots: { BasePart }, origin: Vector3, dir: Vector3, range: number, halfWidth: number): (number?, BasePart?)
	local best, bestRoot = nil, nil
	for _, r in ipairs(roots) do
		if r.Parent then
			local off = r.Position - origin
			local flat = Vector3.new(off.X, 0, off.Z)
			local along = flat:Dot(dir)
			if along >= 0 and along <= range and (flat - dir * along).Magnitude <= halfWidth and math.abs(off.Y) < 8 then
				if not best or along < best then
					best, bestRoot = along, r
				end
			end
		end
	end
	return best, bestRoot
end

-- ─── Crystal geometry ───────────────────────────────────────────────────────
-- A crystal is two crossed "blades" (pairs of back-to-back wedges) giving a
-- four-ridged tapering spike; a thinner neon copy inside forms the glowing core.
-- Everything is welded to an invisible anchored hub at the crystal's base, so
-- moving the hub moves the whole crystal.
local function addBlade(hub: BasePart, baseCF: CFrame, w: number, h: number, depth: number, color: Color3, material: Enum.Material, transparency: number)
	for side = -1, 1, 2 do
		local cf = baseCF * CFrame.new(0, h * 0.5, side * depth * 0.25)
		if side == 1 then cf *= CFrame.Angles(0, math.pi, 0) end
		local wedge = newPart(hub, {
			ClassName = "WedgePart",
			Size = Vector3.new(w, h, depth * 0.5),
			CFrame = cf,
			Color = color,
			Material = material,
			Transparency = transparency,
			Reflectance = material == Enum.Material.Glass and 0.2 or 0,
			Anchored = false,
			Massless = true,
		})
		local weld = Instance.new("WeldConstraint")
		weld.Part0 = hub
		weld.Part1 = wedge
		weld.Parent = wedge
	end
end

local function makeCrystal(parent: Instance, cf: CFrame, width: number, height: number, withCore: boolean?, tint: Color3?): BasePart
	local hub = newPart(parent, {
		Name = "Crystal",
		Size = Vector3.new(0.1, 0.1, 0.1),
		Transparency = 1,
		CFrame = cf,
	})
	local shell = tint or ICE_PALE
	addBlade(hub, cf, width * 0.35, height, width, shell, Enum.Material.Glass, 0.25)
	addBlade(hub, cf * CFrame.Angles(0, math.pi / 2, 0), width * 0.35, height, width, shell, Enum.Material.Glass, 0.25)
	if withCore ~= false then
		addBlade(hub, cf * CFrame.Angles(0, math.pi / 4, 0), width * 0.12, height * 0.86, width * 0.45, ICE_WHITE, Enum.Material.Neon, 0.1)
		addBlade(hub, cf * CFrame.Angles(0, -math.pi / 4, 0), width * 0.12, height * 0.86, width * 0.45, ICE_CYAN, Enum.Material.Neon, 0.2)
	end
	return hub
end

-- Rise a crystal out of the ground (hub starts sunk below the surface).
local function eruptCrystal(hub: BasePart, targetCF: CFrame, height: number, t: number)
	hub.CFrame = targetCF * CFrame.new(0, -height * 1.05, 0)
	TweenService:Create(hub, TweenInfo.new(t, Enum.EasingStyle.Back, Enum.EasingDirection.Out, 0, false, 0), { CFrame = targetCF }):Play()
end

local function sinkAndFade(hub: BasePart, height: number, t: number)
	TweenService:Create(hub, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		CFrame = hub.CFrame * CFrame.new(0, -height * 0.6, 0),
	}):Play()
	fadeOut(hub, t)
end

-- Flat decal-like disc on the floor.
local function groundDisc(parent: Instance, center: Vector3, diameter: number, color: Color3, material: Enum.Material, transparency: number): BasePart
	return newPart(parent, {
		Name = "FrostDisc",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, diameter, diameter),
		CFrame = CFrame.new(center + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
		Transparency = transparency,
	})
end

-- Jagged glowing cracks radiating across the floor.
local function spawnCracks(parent: Instance, center: Vector3, count: number, length: number, life: number)
	for i = 1, count do
		local ang = (i / count) * math.pi * 2 + math.random() * 0.8
		local pos = center
		local dir = Vector3.new(math.cos(ang), 0, math.sin(ang))
		local segs = math.random(2, 4)
		for _ = 1, segs do
			dir = (CFrame.Angles(0, (math.random() - 0.5) * 1.1, 0) * dir).Unit
			local segLen = length / segs * (0.7 + math.random() * 0.6)
			local nextPos = pos + dir * segLen
			local mid = (pos + nextPos) * 0.5
			local crack = newPart(parent, {
				Name = "Crack",
				Size = Vector3.new(0.14, 0.05, segLen),
				CFrame = CFrame.lookAt(mid + Vector3.new(0, 0.07, 0), nextPos + Vector3.new(0, 0.07, 0)),
				Color = ICE_CYAN,
				Material = Enum.Material.Neon,
				Transparency = 0.05,
			})
			TweenService:Create(crack, TweenInfo.new(life, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Color = ICE_DEEP }):Play()
			pos = nextPos
		end
	end
end

-- Ring of neon segments on the floor; placeRing re-lays it at any radius while
-- keeping the stroke thickness constant.
local RING_SEGS = 40
local function buildRing(parent: Instance, color: Color3, transparency: number): { BasePart }
	local parts = {}
	for i = 1, RING_SEGS do
		parts[i] = newPart(parent, { Name = "RingSeg", Color = color, Material = Enum.Material.Neon, Transparency = transparency })
	end
	return parts
end

local function placeRing(parts: { BasePart }, center: Vector3, radius: number, thickness: number)
	local segLen = 2 * math.pi * radius / #parts * 1.12
	for i, p in ipairs(parts) do
		local a = (i / #parts) * math.pi * 2
		local pos = center + Vector3.new(math.cos(a), 0, math.sin(a)) * radius
		p.Size = Vector3.new(thickness, thickness * 0.6, math.max(segLen, 0.05))
		p.CFrame = CFrame.lookAt(pos, pos + Vector3.new(-math.sin(a), 0, math.cos(a)))
	end
end

-- Expanding (or collapsing) shockwave ring that fades as it travels.
local function shockwave(parent: Instance, center: Vector3, fromRadius: number, toRadius: number, t: number, color: Color3, thickness: number?)
	local holder = Instance.new("Folder")
	holder.Name = "Shockwave"
	holder.Parent = parent
	local th = thickness or 0.5
	local parts = buildRing(holder, color, 0.05)
	placeRing(parts, center, fromRadius, th)
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / t, 0, 1)
		if not holder.Parent or a >= 1 then
			conn:Disconnect()
			holder:Destroy()
			return
		end
		local e = 1 - (1 - a) ^ 3
		placeRing(parts, center, fromRadius + (toRadius - fromRadius) * e, th * (1 - a * 0.5))
		for _, p in ipairs(parts) do
			p.Transparency = 0.05 + 0.95 * a
		end
	end)
end

local function snowBurst(pos: Vector3, count: number, speed: number, size: number)
	local att = attachmentAt(pos)
	newEmitter(att, {
		Texture = TEX_SPARKLE,
		Color = colors(ICE_WHITE, ICE_CYAN),
		Size = seq(0, size, 1, 0),
		Transparency = seq(0, 0, 0.7, 0.2, 1, 1),
		Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(speed * 0.4, speed),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -30, 0),
		Drag = 3,
		RotSpeed = NumberRange.new(-300, 300),
		Rotation = NumberRange.new(0, 360),
	}):Emit(count)
	local mist = newEmitter(att, {
		Texture = TEX_SMOKE,
		Color = colors(ICE_WHITE, ICE_PALE),
		Size = seq(0, size * 2, 1, size * 6),
		Transparency = seq(0, 0.55, 1, 1),
		Lifetime = NumberRange.new(0.6, 1.1),
		Speed = NumberRange.new(speed * 0.1, speed * 0.3),
		SpreadAngle = Vector2.new(180, 30),
		Drag = 4,
		LightEmission = 0.4,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40),
	})
	mist:Emit(math.max(2, math.floor(count / 4)))
	Debris:AddItem(att, 1.4)
end

-- Physical shards that fly outward, tumble and fade (explosions).
local function flingShards(parent: Instance, center: Vector3, count: number, speed: number, sizeScale: number)
	for _ = 1, count do
		local s = (0.35 + math.random() * 0.7) * sizeScale
		local shard = newPart(parent, {
			ClassName = "WedgePart",
			Size = Vector3.new(s * 0.4, s * 1.6, s),
			CFrame = CFrame.new(center) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = math.random() < 0.5 and ICE_PALE or ICE_WHITE,
			Material = math.random() < 0.3 and Enum.Material.Neon or Enum.Material.Glass,
			Transparency = 0.15,
			Reflectance = 0.2,
			Anchored = false,
		})
		local dir = Vector3.new(math.random() - 0.5, 0.35 + math.random() * 0.6, math.random() - 0.5).Unit
		shard.AssemblyLinearVelocity = dir * speed * (0.6 + math.random() * 0.6)
		shard.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 25
		task.delay(0.7 + math.random() * 0.4, function()
			if shard.Parent then
				TweenService:Create(shard, TweenInfo.new(0.5), { Transparency = 1, Size = shard.Size * 0.3 }):Play()
			end
		end)
		Debris:AddItem(shard, 1.6)
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- M1: Ice Crystal (deliberately minimal)
-- ═════════════════════════════════════════════════════════════════════════════
function IceMageVFX.playCrystalBolt(char: Model, lookDir: Vector3)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local dir = flatUnit(lookDir)
	local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
	local start = root.Position + Vector3.new(0, 1.4, 0) + dir * 1.6
	if hand and hand:IsA("BasePart") then
		start = Vector3.new(start.X, hand.Position.Y + 0.2, start.Z)
	end

	local range = 60
	local dist = firstEnemyOnLine(getEnemyRoots(char), root.Position, dir, range, 2.4)
	refreshGroundFilter()
	local wall = Workspace:Raycast(start, dir * range, groundParams)
	local travel = math.min(dist or range, wall and wall.Distance or range)

	local folder = vfxFolder("IceCrystalBolt")
	local bolt = newPart(folder, {
		Name = "Bolt",
		Size = Vector3.new(0.42, 0.42, 1.9),
		Color = ICE_PALE,
		Material = Enum.Material.Glass,
		Transparency = 0.2,
		Reflectance = 0.3,
		CFrame = CFrame.lookAt(start, start + dir) * CFrame.Angles(0, 0, math.rad(45)),
	})
	local core = newPart(bolt, {
		Size = Vector3.new(0.18, 0.18, 2.2),
		Color = ICE_WHITE,
		Material = Enum.Material.Neon,
		Anchored = false,
		Massless = true,
		CFrame = bolt.CFrame,
	})
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = bolt, core
	w.Parent = core
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0.12, 0, 0.8)
	a0.Parent = bolt
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(-0.12, 0, 0.8)
	a1.Parent = bolt
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = colors(ICE_WHITE, ICE_CYAN)
	trail.Transparency = seq(0, 0.2, 1, 1)
	trail.Lifetime = 0.12
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.WidthScale = seq(0, 1, 1, 0)
	trail.Parent = bolt

	local speed = 170
	local t0 = os.clock()
	local startCF = bolt.CFrame
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local d = (os.clock() - t0) * speed
		if d >= travel then
			conn:Disconnect()
			local hitPos = start + dir * travel
			bolt.Transparency = 1
			core.Transparency = 1
			local att = attachmentAt(hitPos)
			newEmitter(att, {
				Texture = TEX_SPARKLE,
				Color = colors(ICE_WHITE, ICE_CYAN),
				Size = seq(0, 0.9, 1, 0),
				Lifetime = NumberRange.new(0.18, 0.35),
				Speed = NumberRange.new(8, 16),
				SpreadAngle = Vector2.new(180, 180),
				Drag = 6,
			}):Emit(8)
			Debris:AddItem(att, 0.5)
			flashLight(hitPos, ICE_CYAN, 2, 8, 0.2)
			Debris:AddItem(folder, 0.2)
			return
		end
		bolt.CFrame = startCF + dir * d
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Skill 1: Ice Spikes
-- ═════════════════════════════════════════════════════════════════════════════
function IceMageVFX.playIceSpikes(char: Model, origin: Vector3, lookDir: Vector3, range: number, speed: number, areaMult: number?)
	local dir = flatUnit(lookDir)
	local scale = areaMult or 1
	refreshGroundFilter()
	local folder = vfxFolder("IceSpikes")
	local right = dir:Cross(Vector3.yAxis).Unit
	local groundStart = groundAt(origin)

	-- Cast: frost sigil flash under the caster.
	local sigil = groundDisc(folder, groundStart, 7 * scale, ICE_CYAN, Enum.Material.Neon, 0.35)
	TweenService:Create(sigil, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.08, 10 * scale, 10 * scale), Transparency = 1,
	}):Play()
	snowBurst(groundStart + Vector3.new(0, 0.5, 0), 12, 14, 0.6)

	-- The frost runner: a bright streak racing ahead of the eruptions.
	local runner = newPart(folder, {
		Name = "FrostRunner",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(1.2, 1.2, 1.2),
		Color = ICE_WHITE,
		Material = Enum.Material.Neon,
		CFrame = CFrame.new(groundStart + Vector3.new(0, 0.6, 0)),
	})
	local ra0 = Instance.new("Attachment")
	ra0.Position = Vector3.new(0, 0.5, 0)
	ra0.Parent = runner
	local ra1 = Instance.new("Attachment")
	ra1.Position = Vector3.new(0, -0.5, 0)
	ra1.Parent = runner
	local rTrail = Instance.new("Trail")
	rTrail.Attachment0, rTrail.Attachment1 = ra0, ra1
	rTrail.Color = colors(ICE_WHITE, ICE_BLUE)
	rTrail.Transparency = seq(0, 0, 1, 1)
	rTrail.Lifetime = 0.35
	rTrail.LightEmission = 1
	rTrail.WidthScale = seq(0, 1.6, 1, 0.2)
	rTrail.Parent = runner
	local rLight = Instance.new("PointLight")
	rLight.Color = ICE_CYAN
	rLight.Brightness = 3
	rLight.Range = 14
	rLight.Parent = runner
	newEmitter(runner, {
		Texture = TEX_SPARKLE,
		Color = colors(ICE_WHITE, ICE_CYAN),
		Size = seq(0, 0.5, 1, 0),
		Lifetime = NumberRange.new(0.3, 0.6),
		Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 4, 0),
		Rate = 90,
	})

	local STEP = 3.2
	local steps = math.floor(range / STEP)
	local lastGround = groundStart
	local stoppedAt = steps
	for i = 1, steps do
		local along = i * STEP
		local flatPos = origin + dir * along
		-- Stop the line at walls.
		local blocked = Workspace:Raycast(lastGround + Vector3.new(0, 1.5, 0), (Vector3.new(flatPos.X, lastGround.Y + 1.5, flatPos.Z) - (lastGround + Vector3.new(0, 1.5, 0))), groundParams)
		if blocked then
			stoppedAt = i - 1
			break
		end
		local g = groundAt(flatPos, lastGround.Y)
		lastGround = g
		local t = i / steps
		local delayT = along / speed

		task.delay(delayT, function()
			if not folder.Parent then return end
			local h = (4.2 + t * 3.4) * scale * (0.85 + math.random() * 0.3)
			local w = (1.5 + t * 0.6) * scale
			local lean = CFrame.Angles(math.rad(-12 - math.random() * 14), 0, math.rad((math.random() - 0.5) * 18))
			local lateral = right * ((math.random() - 0.5) * 0.9)
			local baseCF = CFrame.lookAt(g + lateral, g + lateral + dir) * lean * CFrame.Angles(0, math.random() * 6.28, 0)
			local main = makeCrystal(folder, baseCF, w, h, true)
			eruptCrystal(main, baseCF, h, 0.12)

			-- Two smaller flanking shards splaying outward.
			local sides = {}
			for side = -1, 1, 2 do
				local sp = g + right * side * (w * 0.8) - dir * 0.4
				local sh = h * (0.4 + math.random() * 0.2)
				local scf = CFrame.lookAt(sp, sp + dir) * CFrame.Angles(0, 0, math.rad(-side * (25 + math.random() * 15))) * CFrame.Angles(math.rad(-10), math.random() * 6.28, 0)
				local c = makeCrystal(folder, scf, w * 0.55, sh, false, ICE_CYAN)
				eruptCrystal(c, scf, sh, 0.1)
				table.insert(sides, { c, sh })
			end

			-- Ground frost patch + cracks.
			local patch = groundDisc(folder, g, 1, ICE_WHITE, Enum.Material.Glass, 0.35)
			TweenService:Create(patch, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.08, 5.2 * scale, 5.2 * scale),
			}):Play()
			spawnCracks(folder, g, 3, 3.2 * scale, 1.1)

			-- Eruption burst: shards up, frozen mist rolling low.
			local att = attachmentAt(g + Vector3.new(0, 0.4, 0))
			newEmitter(att, {
				Texture = TEX_SPARKLE,
				Color = colors(ICE_WHITE, ICE_CYAN),
				Size = seq(0, 0.7, 1, 0),
				Lifetime = NumberRange.new(0.35, 0.7),
				Speed = NumberRange.new(12, 24),
				SpreadAngle = Vector2.new(35, 35),
				EmissionDirection = Enum.NormalId.Top,
				Acceleration = Vector3.new(0, -45, 0),
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-400, 400),
			}):Emit(10)
			newEmitter(att, {
				Texture = TEX_SMOKE,
				Color = colors(ICE_WHITE, ICE_PALE),
				Size = seq(0, 1.5, 1, 4.5),
				Transparency = seq(0, 0.5, 1, 1),
				Lifetime = NumberRange.new(0.7, 1.1),
				Speed = NumberRange.new(2, 5),
				SpreadAngle = Vector2.new(180, 10),
				Drag = 3,
				LightEmission = 0.3,
				Rotation = NumberRange.new(0, 360),
			}):Emit(3)
			Debris:AddItem(att, 1.3)
			if i % 3 == 0 then
				flashLight(g + Vector3.new(0, 2, 0), ICE_CYAN, 3, 16, 0.35)
			end

			-- Hold, then crumble.
			task.delay(0.75, function()
				sinkAndFade(main, h, 0.35)
				for _, s in ipairs(sides) do sinkAndFade(s[1], s[2], 0.3) end
				TweenService:Create(patch, TweenInfo.new(0.6), { Transparency = 1 }):Play()
				snowBurst(g + Vector3.new(0, h * 0.4, 0), 5, 10, 0.4)
			end)
		end)
	end

	-- Drive the runner along the line, then pop it at the end.
	local endAlong = math.max(stoppedAt, 1) * STEP
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local d = (os.clock() - t0) * speed
		if d >= endAlong or not runner.Parent then
			conn:Disconnect()
			local p = runner.Position
			runner:Destroy()
			snowBurst(p, 14, 18, 0.7)
			flashLight(p, ICE_WHITE, 4, 18, 0.3)
			return
		end
		local p = origin + dir * d
		local g = groundAt(p, groundStart.Y)
		runner.CFrame = CFrame.new(g + Vector3.new(0, 0.6, 0))
	end)

	shake(0.35, 0.25)
	Debris:AddItem(folder, endAlong / speed + 1.8)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Skill 2: Ice Beam
-- ═════════════════════════════════════════════════════════════════════════════
local function getCursorAim(rootPart: BasePart): Vector3
	local camera = Workspace.CurrentCamera
	local mp = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mp.X, mp.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = nonWorldInstances()
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
	local pos
	if hit then
		pos = hit.Position
	elseif math.abs(ray.Direction.Y) > 0.001 then
		pos = ray.Origin + ray.Direction * ((rootPart.Position.Y - ray.Origin.Y) / ray.Direction.Y)
	else
		return rootPart.CFrame.LookVector
	end
	local flat = Vector3.new(pos.X - rootPart.Position.X, 0, pos.Z - rootPart.Position.Z)
	return flat.Magnitude > 0.5 and flat.Unit or rootPart.CFrame.LookVector
end

function IceMageVFX.playIceBeam(char: Model, range: number, duration: number, isLocal: boolean)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local folder = vfxFolder("IceBeam")
	refreshGroundFilter()

	local function beamLayer(name, size, color, material, transparency)
		return newPart(folder, {
			Name = name,
			Shape = Enum.PartType.Cylinder,
			Size = Vector3.new(0.1, size, size),
			Color = color,
			Material = material,
			Transparency = transparency,
		})
	end
	local halo = beamLayer("Halo", 4.6, ICE_BLUE, Enum.Material.Neon, 0.9)
	local outer = beamLayer("Outer", 2.6, ICE_CYAN, Enum.Material.Neon, 0.72)
	local shell = beamLayer("Shell", 1.7, ICE_PALE, Enum.Material.Glass, 0.45)
	local core = beamLayer("Core", 0.85, ICE_WHITE, Enum.Material.Neon, 0)

	-- Muzzle orb.
	local orb = newPart(folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.8, 1.8, 1.8), Color = ICE_WHITE, Material = Enum.Material.Neon })
	local orbShell = newPart(folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Color = ICE_CYAN, Material = Enum.Material.Neon, Transparency = 0.75 })
	local muzzleLight = Instance.new("PointLight")
	muzzleLight.Color, muzzleLight.Brightness, muzzleLight.Range = ICE_CYAN, 4, 20
	muzzleLight.Parent = orb

	-- Frost flowing down the beam: particle lifetime is set each frame so the
	-- stream ends exactly at the beam tip.
	local hub = newPart(folder, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
	local flowAtt = Instance.new("Attachment")
	flowAtt.Parent = hub
	local FLOW_SPEED = 90
	local flow = newEmitter(flowAtt, {
		Texture = TEX_SPARKLE,
		Color = colors(ICE_WHITE, ICE_CYAN),
		Size = seq(0, 0.9, 0.5, 0.6, 1, 0.2),
		Transparency = seq(0, 0, 1, 0.4),
		Speed = NumberRange.new(FLOW_SPEED),
		SpreadAngle = Vector2.new(4, 4),
		EmissionDirection = Enum.NormalId.Front,
		Rate = 160,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-360, 360),
	})
	local streak = newEmitter(flowAtt, {
		Texture = TEX_STREAK,
		Color = colors(ICE_WHITE, ICE_PALE),
		Size = seq(0, 1.4, 1, 0.8),
		Transparency = seq(0, 0.3, 1, 0.8),
		Speed = NumberRange.new(FLOW_SPEED * 1.3),
		SpreadAngle = Vector2.new(2, 2),
		EmissionDirection = Enum.NormalId.Front,
		Rate = 45,
		Orientation = Enum.ParticleOrientation.VelocityParallel,
	})

	-- Spiralling crystal rings that sweep along the beam.
	local rings = {}
	for r = 1, 3 do
		local ringHub = newPart(folder, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
		local n = 6
		for k = 1, n do
			local a = (k / n) * math.pi * 2
			local offs = CFrame.Angles(0, 0, a) * CFrame.new(0, 1.55, 0)
			local shard = newPart(folder, {
				ClassName = "WedgePart",
				Size = Vector3.new(0.14, 0.55, 0.9),
				Color = k % 2 == 0 and ICE_WHITE or ICE_CYAN,
				Material = Enum.Material.Neon,
				Transparency = 0.1,
				Anchored = false,
				Massless = true,
				CFrame = offs,
			})
			shard.CFrame = ringHub.CFrame * offs
			local wc = Instance.new("WeldConstraint")
			wc.Part0, wc.Part1 = ringHub, shard
			wc.Parent = shard
		end
		rings[r] = { hub = ringHub, phase = (r - 1) / 3, spin = r % 2 == 0 and 5 or -6 }
	end

	-- Impact: crystalline burst growing at the stopping point.
	local impact = newPart(folder, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
	local impactAtt = Instance.new("Attachment")
	impactAtt.Parent = impact
	local impactShards = newEmitter(impactAtt, {
		Texture = TEX_SPARKLE,
		Color = colors(ICE_WHITE, ICE_CYAN),
		Size = seq(0, 1.1, 1, 0),
		Lifetime = NumberRange.new(0.25, 0.5),
		Speed = NumberRange.new(14, 30),
		SpreadAngle = Vector2.new(70, 70),
		EmissionDirection = Enum.NormalId.Back,
		Acceleration = Vector3.new(0, -35, 0),
		Rate = 110,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-500, 500),
	})
	local impactMist = newEmitter(impactAtt, {
		Texture = TEX_SMOKE,
		Color = colors(ICE_WHITE, ICE_PALE),
		Size = seq(0, 2, 1, 5),
		Transparency = seq(0, 0.6, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(180, 180),
		LightEmission = 0.4,
		Rate = 14,
		Rotation = NumberRange.new(0, 360),
	})
	local impactLight = Instance.new("PointLight")
	impactLight.Color, impactLight.Brightness, impactLight.Range = ICE_WHITE, 5, 22
	impactLight.Parent = impact
	local impactBloom = newPart(folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Color = ICE_WHITE, Material = Enum.Material.Neon, Transparency = 0.35 })
	local impactCrystals = {}
	for k = 1, 5 do
		local c = makeCrystal(folder, CFrame.new(), 0.9, 2.2, true)
		impactCrystals[k] = { hub = c, a = (k / 5) * math.pi * 2 }
	end

	-- Frost streak along the floor under the beam.
	local floorFrost = newPart(folder, { Size = Vector3.new(2.4, 0.06, 1), Color = ICE_PALE, Material = Enum.Material.Glass, Transparency = 0.45 })

	local t0 = os.clock()
	local lastT = t0
	local length = 0
	local roots = getEnemyRoots(char)
	local lastScan = t0
	local wasHitting = false
	local active = true
	local conn

	conn = RunService.RenderStepped:Connect(function()
		if not active then return end
		local now = os.clock()
		local dt = now - lastT
		lastT = now
		local elapsed = now - t0
		if not (char.Parent and root.Parent) or elapsed >= duration then
			active = false
			conn:Disconnect()
			if isLocal and char.Parent then
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end
			local tip = impact.Position
			snowBurst(tip, 16, 20, 0.8)
			fadeOut(folder, 0.3)
			Debris:AddItem(folder, 0.5)
			return
		end

		local dir
		if isLocal then
			dir = getCursorAim(root)
			root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
		else
			dir = flatUnit(root.CFrame.LookVector)
		end

		if now - lastScan > 0.15 then
			lastScan = now
			roots = getEnemyRoots(char)
		end

		local hand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		local startPos = root.Position + Vector3.new(0, 1.1, 0) + dir * 2
		if hand and hand:IsA("BasePart") then
			startPos = Vector3.new(startPos.X, hand.Position.Y + 0.3, startPos.Z)
		end

		-- Where does the beam want to end? First enemy, else wall, else max range.
		local enemyDist, enemyRoot = firstEnemyOnLine(roots, root.Position, dir, range, 2.2)
		local wall = Workspace:Raycast(startPos, dir * range, groundParams)
		local targetLen = range
		if wall then targetLen = wall.Distance end
		local hitting = false
		if enemyDist and enemyDist - 1 < targetLen then
			targetLen = math.max(enemyDist - 1.2, 1)
			hitting = true
		end
		-- Travels forward continuously, but snaps back the instant something is hit.
		if targetLen > length then
			length = math.min(targetLen, length + 240 * dt)
		else
			length = targetLen
		end
		if hitting and not wasHitting then
			flashLight(startPos + dir * length, ICE_WHITE, 6, 24, 0.25)
			shockwave(folder, startPos + dir * length, 0.5, 5, 0.3, ICE_WHITE, 0.25)
		end
		wasHitting = hitting and length >= targetLen - 0.01

		local pulse = 1 + math.sin(elapsed * 22) * 0.1 + math.sin(elapsed * 57) * 0.04
		local grow = math.clamp(elapsed / 0.12, 0.2, 1)
		local mid = startPos + dir * (length * 0.5)
		local basis = CFrame.lookAt(mid, mid + dir) * CFrame.Angles(0, math.rad(90), 0)
		halo.CFrame, halo.Size = basis, Vector3.new(length, 4.6 * pulse * grow, 4.6 * pulse * grow)
		outer.CFrame, outer.Size = basis, Vector3.new(length, 2.6 * pulse * grow, 2.6 * pulse * grow)
		shell.CFrame, shell.Size = basis, Vector3.new(length, 1.7 * grow, 1.7 * grow)
		core.CFrame, core.Size = basis, Vector3.new(length, 0.85 * pulse * grow, 0.85 * pulse * grow)

		orb.CFrame = CFrame.new(startPos)
		orb.Size = Vector3.one * (1.8 * pulse)
		orbShell.CFrame = CFrame.new(startPos)
		orbShell.Size = Vector3.one * (3 + math.sin(elapsed * 9) * 0.4)

		hub.CFrame = CFrame.lookAt(startPos, startPos + dir)
		flow.Lifetime = NumberRange.new(length / FLOW_SPEED)
		streak.Lifetime = NumberRange.new(length / (FLOW_SPEED * 1.3))

		for _, r in ipairs(rings) do
			local f = ((elapsed * 0.9) + r.phase) % 1
			local p = startPos + dir * (f * length)
			r.hub.CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, elapsed * r.spin)
		end

		local tip = startPos + dir * length
		impact.CFrame = CFrame.lookAt(tip, tip + dir)
		impactShards.Rate = hitting and 110 or 45
		impactMist.Rate = hitting and 18 or 6
		impactLight.Brightness = hitting and 6 or 3
		impactBloom.CFrame = CFrame.new(tip)
		local bloomSize = (hitting and 3.4 or 2.2) * (1 + math.sin(elapsed * 30) * 0.12)
		impactBloom.Size = Vector3.one * bloomSize
		for k, c in ipairs(impactCrystals) do
			local vis = hitting
			local a = c.a + elapsed * 2.5
			local cf = CFrame.lookAt(tip, tip - dir) * CFrame.Angles(0, 0, a) * CFrame.Angles(math.rad(-65), 0, 0)
			c.hub.CFrame = vis and cf or cf * CFrame.new(0, -50, 0)
			for _, p in ipairs(c.hub:GetChildren()) do
				if p:IsA("BasePart") then
					p.LocalTransparencyModifier = vis and 0 or 1
				end
			end
		end

		local gStart = groundAt(startPos, root.Position.Y - 3)
		local gEnd = gStart + dir * length
		floorFrost.Size = Vector3.new(2.6 * grow, 0.06, length)
		floorFrost.CFrame = CFrame.lookAt((gStart + gEnd) * 0.5 + Vector3.new(0, 0.07, 0), gEnd + Vector3.new(0, 0.07, 0))
	end)

	if isLocal then shake(0.2, 0.2) end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Skill 3: Ice Clone
-- ═════════════════════════════════════════════════════════════════════════════
local decorated: { [Model]: boolean } = {}

function IceMageVFX.decorateClone(clone: Model)
	if decorated[clone] then return end
	decorated[clone] = true
	local root = clone:WaitForChild("HumanoidRootPart", 3) :: BasePart?
	if not root then return end
	local torso = (clone:FindFirstChild("UpperTorso") or clone:FindFirstChild("Torso") or root) :: BasePart
	local folder = vfxFolder("IceCloneFX")
	refreshGroundFilter()
	local ground = groundAt(root.Position)

	-- Summon: a burst of crystals erupts and shatters into the clone.
	for k = 1, 7 do
		local a = (k / 7) * math.pi * 2
		local p = ground + Vector3.new(math.cos(a), 0, math.sin(a)) * 1.6
		local cf = CFrame.lookAt(p, p + Vector3.new(math.cos(a), 0, math.sin(a))) * CFrame.Angles(math.rad(-25), 0, 0)
		local h = 4 + math.random() * 2.5
		local c = makeCrystal(folder, cf, 1.2, h, true)
		eruptCrystal(c, cf, h, 0.14)
		task.delay(0.35, function()
			fadeOut(c, 0.25)
		end)
	end
	shockwave(folder, ground + Vector3.new(0, 0.2, 0), 1, 9, 0.45, ICE_CYAN, 0.35)
	snowBurst(root.Position, 22, 20, 0.8)
	flashLight(root.Position, ICE_WHITE, 7, 26, 0.5)
	spawnCracks(folder, ground, 6, 5, 1.2)

	-- Fresnel-style rim glow for the crystalline body.
	local hl = Instance.new("Highlight")
	hl.FillColor = ICE_CYAN
	hl.FillTransparency = 0.72
	hl.OutlineColor = ICE_WHITE
	hl.OutlineTransparency = 0.15
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = clone
	hl.Parent = folder

	-- Glowing core in the chest.
	local coreOuter = newPart(folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(1.6, 1.6, 1.6), Color = ICE_CYAN, Material = Enum.Material.Neon, Transparency = 0.55 })
	local coreInner = makeCrystal(folder, CFrame.new(), 0.7, 1.1, true)
	local coreLight = Instance.new("PointLight")
	coreLight.Color, coreLight.Brightness, coreLight.Range = ICE_CYAN, 3, 16
	coreLight.Parent = coreOuter

	-- Frost aura: low rolling mist + motes drifting upward.
	local auraAtt = Instance.new("Attachment")
	auraAtt.Position = Vector3.new(0, -2.6, 0)
	auraAtt.Parent = root
	local mist = newEmitter(auraAtt, {
		Texture = TEX_SMOKE,
		Color = colors(ICE_WHITE, ICE_PALE),
		Size = seq(0, 1.5, 1, 4),
		Transparency = seq(0, 0.7, 0.5, 0.6, 1, 1),
		Lifetime = NumberRange.new(1.2, 1.8),
		Speed = NumberRange.new(1, 3),
		SpreadAngle = Vector2.new(180, 5),
		LightEmission = 0.3,
		Rate = 10,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-20, 20),
	})
	local motes = newEmitter(auraAtt, {
		Texture = TEX_SPARKLE,
		Color = colors(ICE_WHITE, ICE_CYAN),
		Size = seq(0, 0.35, 1, 0),
		Lifetime = NumberRange.new(1, 1.8),
		Speed = NumberRange.new(2, 4),
		SpreadAngle = Vector2.new(25, 25),
		EmissionDirection = Enum.NormalId.Top,
		Rate = 22,
		Rotation = NumberRange.new(0, 360),
	})

	-- Frost rune under the feet and orbiting shards.
	local rune = groundDisc(folder, ground, 6, ICE_CYAN, Enum.Material.Neon, 0.7)
	local runeRing = groundDisc(folder, ground, 6.6, ICE_WHITE, Enum.Material.Neon, 0.85)
	local orbit = {}
	for k = 1, 6 do
		orbit[k] = { hub = makeCrystal(folder, CFrame.new(), 0.5, 1.2, k % 2 == 0), a = (k / 6) * math.pi * 2, y = (k % 3) * 0.7 }
	end

	local tauntRadius = clone:GetAttribute("TauntRadius") or 34
	local lastPulse = 0
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not clone.Parent or not root.Parent then
			conn:Disconnect()
			decorated[clone] = nil
			mist.Enabled = false
			motes.Enabled = false
			folder:Destroy()
			return
		end
		local t = os.clock() - t0
		local c = torso.Position
		local beat = 1 + math.sin(t * 6) * 0.15
		coreOuter.CFrame = CFrame.new(c)
		coreOuter.Size = Vector3.one * 1.6 * beat
		coreInner.CFrame = CFrame.new(c - Vector3.new(0, 0.55, 0)) * CFrame.Angles(0, t * 3, 0)
		coreLight.Brightness = 2.5 + math.sin(t * 6) * 1
		for _, o in ipairs(orbit) do
			local a = o.a + t * 1.8
			local p = c + Vector3.new(math.cos(a) * 2.8, o.y - 0.6 + math.sin(t * 2 + o.a) * 0.4, math.sin(a) * 2.8)
			o.hub.CFrame = CFrame.lookAt(p, c) * CFrame.Angles(math.rad(90), 0, 0) * CFrame.new(0, -0.6, 0)
		end
		rune.CFrame = CFrame.new(ground + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, t * 0.8, math.rad(90))
		runeRing.CFrame = CFrame.new(ground + Vector3.new(0, 0.05, 0)) * CFrame.Angles(0, -t * 0.5, math.rad(90))

		-- Taunt pulse: a faint ring sweeping out to the taunt radius every 1.6s.
		if t - lastPulse > 1.6 then
			lastPulse = t
			shockwave(folder, ground + Vector3.new(0, 0.3, 0), 2, tauntRadius, 1.0, ICE_CYAN, 0.18)
		end
	end)
end

function IceMageVFX.playCloneShatter(position: Vector3, radius: number)
	refreshGroundFilter()
	local folder = vfxFolder("IceCloneShatter")
	local ground = groundAt(position)

	-- Blinding core flash.
	local flash = newPart(folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), Color = ICE_WHITE, Material = Enum.Material.Neon, CFrame = CFrame.new(position) })
	TweenService:Create(flash, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * 11, Transparency = 1 }):Play()
	local sphere = newPart(folder, { Shape = Enum.PartType.Ball, Size = Vector3.new(3, 3, 3), Color = ICE_CYAN, Material = Enum.Material.ForceField, Transparency = 0.1, CFrame = CFrame.new(position) })
	TweenService:Create(sphere, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	flashLight(position, ICE_WHITE, 10, radius * 2.5, 0.7)

	-- Violent shard spray.
	flingShards(folder, position, 26, 55, 1.3)
	snowBurst(position, 40, 40, 1.1)

	-- Freezing shockwave: double ring racing across the floor, frost bloom behind it.
	shockwave(folder, ground + Vector3.new(0, 0.3, 0), 1, radius, 0.45, ICE_WHITE, 0.6)
	task.delay(0.08, function()
		shockwave(folder, ground + Vector3.new(0, 0.2, 0), 1, radius * 0.85, 0.5, ICE_CYAN, 0.4)
	end)
	local frost = groundDisc(folder, ground, 2, ICE_WHITE, Enum.Material.Glass, 0.3)
	TweenService:Create(frost, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.08, radius * 2, radius * 2) }):Play()
	spawnCracks(folder, ground, 10, radius * 0.9, 1.6)

	-- Ring of spikes erupting at the shockwave's edge.
	for k = 1, 12 do
		local a = (k / 12) * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = groundAt(ground + out * radius * 0.75, ground.Y)
		local h = 3 + math.random() * 2
		local cf = CFrame.lookAt(p, p + out) * CFrame.Angles(math.rad(-35), 0, 0)
		task.delay(0.2, function()
			local c = makeCrystal(folder, cf, 1.2, h, true)
			eruptCrystal(c, cf, h, 0.1)
			task.delay(0.7, function() sinkAndFade(c, h, 0.35) end)
		end)
	end

	task.delay(1.1, function()
		TweenService:Create(frost, TweenInfo.new(0.8), { Transparency = 1 }):Play()
	end)
	shake(0.9, 0.4, position)
	Debris:AddItem(folder, 2.2)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Chill feedback (targets frozen by spikes / beam / shatter)
-- ═════════════════════════════════════════════════════════════════════════════
local chilled: { [Model]: { expires: number, folder: Folder } } = {}

function IceMageVFX.playChill(model: Model, duration: number)
	if not model or not model.Parent then return end
	local root = (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart?
	if not root then return end
	local expires = os.clock() + duration
	local existing = chilled[model]
	if existing then
		existing.expires = math.max(existing.expires, expires)
		return
	end

	local folder = vfxFolder("Chill")
	local entry = { expires = expires, folder = folder }
	chilled[model] = entry

	local _, size = model:GetBoundingBox()
	local ground = groundAt(root.Position, root.Position.Y - size.Y * 0.5)
	local hl = Instance.new("Highlight")
	hl.FillColor = ICE_CYAN
	hl.FillTransparency = 0.55
	hl.OutlineColor = ICE_WHITE
	hl.OutlineTransparency = 0.3
	hl.Adornee = model
	hl.Parent = folder

	-- Crystals clamping the feet.
	local r = math.max(size.X, size.Z) * 0.45
	for k = 1, 5 do
		local a = (k / 5) * math.pi * 2 + math.random()
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local p = ground + out * r
		local h = math.clamp(size.Y * 0.45, 1.5, 4) * (0.8 + math.random() * 0.4)
		local cf = CFrame.lookAt(p, p + out) * CFrame.Angles(math.rad(-30 + math.random() * 10), 0, 0)
		local c = makeCrystal(folder, cf, 0.9, h, k % 2 == 1)
		eruptCrystal(c, cf, h, 0.08)
	end
	groundDisc(folder, ground, r * 2 + 3, ICE_WHITE, Enum.Material.Glass, 0.4)
	local att = attachmentAt(root.Position)
	att.Parent = folder
	newEmitter(att, {
		Texture = TEX_SPARKLE,
		Color = colors(ICE_WHITE, ICE_CYAN),
		Size = seq(0, 0.3, 1, 0),
		Lifetime = NumberRange.new(0.5, 1),
		Speed = NumberRange.new(1, 2),
		SpreadAngle = Vector2.new(180, 180),
		Rate = 14,
	})

	task.spawn(function()
		while os.clock() < entry.expires and model.Parent do
			task.wait(0.1)
		end
		chilled[model] = nil
		if root.Parent then snowBurst(root.Position, 10, 14, 0.5) end
		fadeOut(folder, 0.25)
		TweenService:Create(hl, TweenInfo.new(0.25), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		Debris:AddItem(folder, 0.4)
		Debris:AddItem(att, 0.4)
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Ultimate: Blizzard
-- ═════════════════════════════════════════════════════════════════════════════
local function iceLightning(parent: Instance, groundPos: Vector3)
	local top = groundPos + Vector3.new((math.random() - 0.5) * 10, 55, (math.random() - 0.5) * 10)
	local pts = { top }
	local segs = 7
	for i = 1, segs do
		local t = i / segs
		local p = top:Lerp(groundPos, t)
		if i < segs then
			p += Vector3.new((math.random() - 0.5) * 5, 0, (math.random() - 0.5) * 5)
		end
		table.insert(pts, p)
	end
	local bolt = Instance.new("Folder")
	bolt.Parent = parent
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local len = (b - a).Magnitude
		for _, layer in ipairs({ { 0.35, ICE_WHITE, 0 }, { 1.2, ICE_CYAN, 0.6 } }) do
			newPart(bolt, {
				Size = Vector3.new(layer[1], layer[1], len),
				CFrame = CFrame.lookAt((a + b) * 0.5, b),
				Color = layer[2],
				Material = Enum.Material.Neon,
				Transparency = layer[3],
			})
		end
	end
	flashLight(groundPos + Vector3.new(0, 6, 0), ICE_WHITE, 12, 60, 0.35)
	shockwave(parent, groundPos + Vector3.new(0, 0.3, 0), 0.5, 7, 0.35, ICE_WHITE, 0.3)
	snowBurst(groundPos, 16, 26, 0.8)
	spawnCracks(parent, groundPos, 5, 4, 1)
	task.delay(0.07, function() fadeOut(bolt, 0.18) end)
	Debris:AddItem(bolt, 0.4)
end

function IceMageVFX.playBlizzard(center: Vector3, radius: number, duration: number)
	refreshGroundFilter()
	local folder = vfxFolder("Blizzard")
	local ground = groundAt(center)
	local active = true

	-- ── Opening: frost detonation from the caster ──
	flashLight(ground + Vector3.new(0, 5, 0), ICE_WHITE, 12, 70, 1)
	shockwave(folder, ground + Vector3.new(0, 0.4, 0), 2, radius, 0.8, ICE_WHITE, 0.8)
	task.delay(0.12, function() shockwave(folder, ground + Vector3.new(0, 0.3, 0), 2, radius * 0.9, 0.9, ICE_CYAN, 0.5) end)
	snowBurst(ground + Vector3.new(0, 2, 0), 50, 45, 1.3)
	spawnCracks(folder, ground, 14, radius * 0.6, duration)
	local pillar = newPart(folder, {
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(160, 5, 5),
		CFrame = CFrame.new(ground + Vector3.new(0, 80, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = ICE_WHITE, Material = Enum.Material.Neon, Transparency = 0.1,
	})
	TweenService:Create(pillar, TweenInfo.new(0.7, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(160, 0.2, 0.2), Transparency = 1 }):Play()

	-- ── Ground frost: the whole battlefield ices over ──
	local frost = groundDisc(folder, ground, 4, ICE_PALE, Enum.Material.Ice, 0.45)
	TweenService:Create(frost, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.08, radius * 2, radius * 2) }):Play()
	local frostGlow = groundDisc(folder, ground + Vector3.new(0, 0.02, 0), 4, ICE_CYAN, Enum.Material.Neon, 0.88)
	TweenService:Create(frostGlow, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.08, radius * 2, radius * 2) }):Play()

	-- ── Storm edge: glowing boundary ring + a curtain of wind-mist (zone readability) ──
	local edgeFolder = Instance.new("Folder")
	edgeFolder.Parent = folder
	local edgeParts = buildRing(edgeFolder, ICE_CYAN, 0.25)
	placeRing(edgeParts, ground + Vector3.new(0, 0.15, 0), radius, 0.7)
	local edgeHub = newPart(folder, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(ground) })
	local edgeEmitters = {}
	for k = 1, 16 do
		local a = (k / 16) * math.pi * 2
		local att = Instance.new("Attachment")
		-- Facing along the tangent so the curtain whips around the storm.
		att.CFrame = CFrame.new(math.cos(a) * radius, 3, math.sin(a) * radius) * CFrame.Angles(0, -a, 0)
		att.Parent = edgeHub
		table.insert(edgeEmitters, newEmitter(att, {
			Texture = TEX_SMOKE,
			Color = colors(ICE_WHITE, ICE_PALE),
			Size = seq(0, 3, 1, 8),
			Transparency = seq(0, 1, 0.2, 0.6, 1, 1),
			Lifetime = NumberRange.new(1, 1.6),
			Speed = NumberRange.new(14, 22),
			SpreadAngle = Vector2.new(10, 30),
			EmissionDirection = Enum.NormalId.Front,
			Acceleration = Vector3.new(0, 5, 0),
			LightEmission = 0.4,
			Rate = 8,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-40, 40),
		}))
	end

	-- ── The swirl: a spinning hub carrying emitters at several radii. Particles
	-- are world-space, so the rotating sources paint spiralling snow bands. ──
	local swirlHub = newPart(folder, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(ground + Vector3.new(0, 8, 0)) })
	local swirlEmitters = {}
	for k = 1, 10 do
		local a = (k / 10) * math.pi * 2
		local rr = radius * (0.25 + (k % 3) * 0.25)
		local att = Instance.new("Attachment")
		att.CFrame = CFrame.new(math.cos(a) * rr, (k % 4) * 3, math.sin(a) * rr) * CFrame.Angles(0, -a, 0)
		att.Parent = swirlHub
		table.insert(swirlEmitters, newEmitter(att, {
			Texture = TEX_SPARKLE,
			Color = colors(ICE_WHITE, ICE_PALE),
			Size = seq(0, 0.5, 1, 0.3),
			Transparency = seq(0, 0.1, 1, 0.8),
			Lifetime = NumberRange.new(1.2, 2),
			Speed = NumberRange.new(18, 30),
			SpreadAngle = Vector2.new(25, 15),
			EmissionDirection = Enum.NormalId.Front,
			Acceleration = Vector3.new(0, -6, 0),
			Rate = 55,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-200, 200),
		}))
		table.insert(swirlEmitters, newEmitter(att, {
			Texture = TEX_STREAK,
			Color = colors(ICE_WHITE, ICE_CYAN),
			Size = seq(0, 2.2, 1, 1),
			Transparency = seq(0, 0.55, 1, 1),
			Lifetime = NumberRange.new(0.4, 0.7),
			Speed = NumberRange.new(45, 60),
			SpreadAngle = Vector2.new(8, 5),
			EmissionDirection = Enum.NormalId.Front,
			Orientation = Enum.ParticleOrientation.VelocityParallel,
			Rate = 10,
		}))
	end

	-- Heavy snowfall from above the whole zone + low frozen mist.
	local sky = newPart(folder, { Size = Vector3.new(radius * 1.8, 1, radius * 1.8), Transparency = 1, CFrame = CFrame.new(ground + Vector3.new(0, 40, 0)) })
	local snowfall = newEmitter(sky, {
		Texture = TEX_SPARKLE,
		Color = colors(ICE_WHITE, ICE_PALE),
		Size = seq(0, 0.45, 1, 0.35),
		Transparency = seq(0, 0.2, 1, 0.6),
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(16, 24),
		EmissionDirection = Enum.NormalId.Bottom,
		Acceleration = Vector3.new(14, 0, 6),
		Rate = 260,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-120, 120),
		LightEmission = 0.6,
	})
	local floorMistPart = newPart(folder, { Size = Vector3.new(radius * 1.8, 1, radius * 1.8), Transparency = 1, CFrame = CFrame.new(ground + Vector3.new(0, 1, 0)) })
	local floorMist = newEmitter(floorMistPart, {
		Texture = TEX_SMOKE,
		Color = colors(ICE_WHITE, ICE_PALE),
		Size = seq(0, 5, 1, 12),
		Transparency = seq(0, 1, 0.25, 0.7, 0.75, 0.75, 1, 1),
		Lifetime = NumberRange.new(2, 3),
		Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(90, 0),
		EmissionDirection = Enum.NormalId.Front,
		Acceleration = Vector3.new(4, 0, 2),
		Rate = 30,
		LightEmission = 0.35,
		Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-25, 25),
	})

	local stormLight = Instance.new("PointLight")
	stormLight.Color, stormLight.Brightness, stormLight.Range = ICE_CYAN, 2, radius
	stormLight.Parent = swirlHub

	-- Cinematic cold grade for anyone standing inside the storm.
	local grade = Instance.new("ColorCorrectionEffect")
	grade.Name = "BlizzardGrade"
	grade.TintColor = Color3.new(1, 1, 1)
	grade.Parent = Lighting
	local function playerInside(): boolean
		local c = player.Character
		local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not r then return false end
		local off = r.Position - ground
		return Vector3.new(off.X, 0, off.Z).Magnitude <= radius + 6
	end
	if playerInside() then
		TweenService:Create(grade, TweenInfo.new(0.6), { TintColor = Color3.fromRGB(205, 228, 255), Contrast = 0.12, Saturation = -0.15, Brightness = 0.03 }):Play()
		shake(1.1, 0.6)
	end

	-- ── Falling ice shards + icy lightning, spawned until the storm ends ──
	task.spawn(function()
		local nextBolt = os.clock() + 0.6
		while active do
			local a = math.random() * math.pi * 2
			local rr = math.sqrt(math.random()) * radius * 0.95
			local target = groundAt(ground + Vector3.new(math.cos(a) * rr, 0, math.sin(a) * rr), ground.Y)
			local fallDir = Vector3.new(-0.35, -1, -0.15).Unit
			local start = target - fallDir * 45
			local h = 2.2 + math.random() * 1.8
			local shard = makeCrystal(folder, CFrame.lookAt(start, start + fallDir) * CFrame.Angles(math.rad(-90), 0, 0), 0.9, h, true)
			-- Crystal "up" points along the fall: tip leads.
			local endCF = CFrame.lookAt(target, target + fallDir) * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, -h * 0.55, 0)
			local tw = TweenService:Create(shard, TweenInfo.new(0.42, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = endCF })
			tw:Play()
			tw.Completed:Connect(function()
				if not folder.Parent then return end
				local att = attachmentAt(target + Vector3.new(0, 0.3, 0))
				newEmitter(att, {
					Texture = TEX_SPARKLE,
					Color = colors(ICE_WHITE, ICE_CYAN),
					Size = seq(0, 0.6, 1, 0),
					Lifetime = NumberRange.new(0.25, 0.5),
					Speed = NumberRange.new(8, 16),
					SpreadAngle = Vector2.new(60, 60),
					EmissionDirection = Enum.NormalId.Top,
					Acceleration = Vector3.new(0, -40, 0),
				}):Emit(7)
				Debris:AddItem(att, 0.7)
				task.delay(0.5, function() sinkAndFade(shard, h, 0.3) end)
			end)
			if os.clock() >= nextBolt then
				nextBolt = os.clock() + 0.7 + math.random() * 0.6
				local ba = math.random() * math.pi * 2
				local br = math.sqrt(math.random()) * radius * 0.85
				iceLightning(folder, groundAt(ground + Vector3.new(math.cos(ba) * br, 0, math.sin(ba) * br), ground.Y))
			end
			task.wait(0.07)
		end
	end)

	-- ── Per-frame: spin the storm, keep the cold grade in sync with position ──
	local t0 = os.clock()
	local inside = playerInside()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		swirlHub.CFrame = CFrame.new(ground + Vector3.new(0, 6, 0)) * CFrame.Angles(0, -t * 1.4, 0)
		edgeHub.CFrame = CFrame.new(ground) * CFrame.Angles(0, -t * 0.9, 0)
		for _, p in ipairs(edgeParts) do
			p.Transparency = 0.25 + math.sin(t * 5) * 0.15
		end
		stormLight.Brightness = 2 + math.sin(t * 7) * 0.6
		local nowInside = playerInside()
		if nowInside ~= inside then
			inside = nowInside
			TweenService:Create(grade, TweenInfo.new(0.5), nowInside
				and { TintColor = Color3.fromRGB(205, 228, 255), Contrast = 0.12, Saturation = -0.15, Brightness = 0.03 }
				or { TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0, Brightness = 0 }):Play()
		end
	end)

	task.delay(duration, function()
		active = false
		conn:Disconnect()
		for _, e in ipairs(swirlEmitters) do e.Enabled = false end
		for _, e in ipairs(edgeEmitters) do e.Enabled = false end
		snowfall.Enabled = false
		floorMist.Enabled = false
		shockwave(folder, ground + Vector3.new(0, 0.3, 0), radius, radius * 0.1, 0.5, ICE_CYAN, 0.5)
		snowBurst(ground + Vector3.new(0, 3, 0), 30, 30, 1)
		TweenService:Create(grade, TweenInfo.new(1), { TintColor = Color3.new(1, 1, 1), Contrast = 0, Saturation = 0, Brightness = 0 }):Play()
		Debris:AddItem(grade, 1.1)
		task.wait(0.3)
		fadeOut(folder, 1.2)
		Debris:AddItem(folder, 3.2)
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Blizzard wind-up: "the frozen one" reveal
-- A near-black silhouette with glowing white eyes looming out of a blizzard,
-- giant ice formations behind, heavy fog, snow streaking across the frame and
-- a cold desaturated grade. The eyes flare as the head rises at `eyeFlareAt`;
-- everything breaks apart at `duration` as the storm is released.
-- Silhouette + eyes play for everyone; the environment/grade only for the caster.
-- ═════════════════════════════════════════════════════════════════════════════
local SILHOUETTE = Color3.fromRGB(5, 7, 13)
local EYE_BLUE = Color3.fromRGB(70, 175, 255)
local EYE_CORE = Color3.fromRGB(200, 235, 255)
local RIM = Color3.fromRGB(170, 215, 255)

function IceMageVFX.playBlizzardReveal(char: Model, duration: number, eyeFlareAt: number, isLocal: boolean)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local head = char:FindFirstChild("Head") :: BasePart?
	if not root or not head then return end
	local folder = vfxFolder("BlizzardReveal")
	refreshGroundFilter()
	local ground = groundAt(root.Position)
	local look = flatUnit(root.CFrame.LookVector)
	local right = look:Cross(Vector3.yAxis).Unit

	-- ── Silhouette: the body becomes a dark shape with a faint frost rim ──
	local hl = Instance.new("Highlight")
	hl.Adornee = char
	hl.FillColor = SILHOUETTE
	hl.FillTransparency = 1
	hl.OutlineColor = RIM
	hl.OutlineTransparency = 1
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Parent = folder
	TweenService:Create(hl, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 0.04, OutlineTransparency = 0.55 }):Play()

	-- Don't rely on the Highlight alone (the per-part outlines can exhaust
	-- Roblox's highlight budget): darken the body itself on this client, hide
	-- the face, and pause this character's outlines. Restored on release.
	local darkened: { [Instance]: { [string]: any } } = {}
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 and not d:IsDescendantOf(folder) then
			local saved: { [string]: any } = { Color = d.Color, Material = d.Material }
			if d:IsA("MeshPart") then saved.TextureID = d.TextureID end
			darkened[d] = saved
			d.Color = SILHOUETTE
			d.Material = Enum.Material.SmoothPlastic
			if d:IsA("MeshPart") then d.TextureID = "" end
		elseif d:IsA("Decal") or d:IsA("Texture") then
			darkened[d] = { Transparency = d.Transparency }
			d.Transparency = 1
		elseif d:IsA("Highlight") and d.Name == "PartOutline" then
			darkened[d] = { Enabled = d.Enabled }
			d.Enabled = false
		elseif d:IsA("SpecialMesh") and d.TextureId ~= "" then
			darkened[d] = { TextureId = d.TextureId }
			d.TextureId = ""
		end
	end
	local restored = false
	local function restoreBody()
		if restored then return end
		restored = true
		for inst, props in pairs(darkened) do
			if inst.Parent then
				for k, v in pairs(props) do (inst :: any)[k] = v end
			end
		end
	end

	-- Shadow wisps streaming off the body give the silhouette a ragged,
	-- shaggy edge (like the fur mantle in the reference).
	local wisps = {}
	for _, spec in ipairs({
		{ "UpperTorso", "Torso", 3.2, 40 }, { "LowerTorso", "Torso", 3.6, 30 },
		{ "RightUpperArm", "Right Arm", 1.8, 14 }, { "LeftUpperArm", "Left Arm", 1.8, 14 },
		{ "RightLowerArm", "", 1.4, 10 }, { "LeftLowerArm", "", 1.4, 10 },
		{ "Head", "Head", 2.2, 16 }, { "RightUpperLeg", "Right Leg", 2.4, 12 }, { "LeftUpperLeg", "Left Leg", 2.4, 12 },
	}) do
		local limb = char:FindFirstChild(spec[1]) or (spec[2] ~= "" and char:FindFirstChild(spec[2])) or nil
		if limb and limb:IsA("BasePart") then
			local a = Instance.new("Attachment")
			a.Name = "ShadowWisps"
			a.Parent = limb
			local pe = newEmitter(a, {
				Texture = TEX_SMOKE,
				Color = colors(Color3.fromRGB(6, 8, 14), Color3.fromRGB(20, 28, 48)),
				LightEmission = 0,
				Size = seq(0, spec[3] * 0.6, 0.5, spec[3], 1, spec[3] * 1.3),
				Transparency = seq(0, 1, 0.15, 0.25, 0.7, 0.55, 1, 1),
				Lifetime = NumberRange.new(0.5, 0.9),
				Speed = NumberRange.new(0.5, 2.5),
				SpreadAngle = Vector2.new(180, 180),
				Acceleration = Vector3.new(0, 2.5, 0) + right * 2,
				Rotation = NumberRange.new(0, 360),
				RotSpeed = NumberRange.new(-60, 60),
				Rate = spec[4],
			})
			table.insert(wisps, { att = a, pe = pe })
		end
	end

	-- ── Eyes: two icy-blue points on the face, dim at first ──
	local eyes = {}
	for side = -1, 1, 2 do
		local offs = CFrame.new(side * head.Size.X * 0.17, head.Size.Y * 0.08, -head.Size.Z * 0.5 - 0.02)
		local eye = newPart(folder, {
			Name = "Eye",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(0.16, 0.16, 0.16),
			Color = EYE_BLUE,
			Material = Enum.Material.Neon,
			Transparency = 0.6,
			Anchored = false,
			Massless = true,
			CFrame = head.CFrame * offs,
		})
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = head, eye
		w.Parent = eye
		-- Horizontal glint streak across each eye.
		local glint = newPart(folder, {
			Name = "EyeGlint",
			Size = Vector3.new(0.9, 0.03, 0.03),
			Color = EYE_BLUE,
			Material = Enum.Material.Neon,
			Transparency = 1,
			Anchored = false,
			Massless = true,
			CFrame = eye.CFrame,
		})
		local gw = Instance.new("WeldConstraint")
		gw.Part0, gw.Part1 = eye, glint
		gw.Parent = glint
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range, l.Shadows = EYE_BLUE, 0.5, 4, false
		l.Parent = eye
		local glow = newEmitter(eye, {
			Texture = TEX_SPARKLE,
			Color = colors(EYE_CORE, EYE_BLUE),
			Size = seq(0, 0.5, 1, 0.3),
			Transparency = seq(0, 0.3, 1, 1),
			Lifetime = NumberRange.new(0.08, 0.12),
			Speed = NumberRange.new(0),
			Rate = 40,
			LockedToPart = true,
		})
		table.insert(eyes, { eye = eye, glint = glint, light = l, glow = glow })
	end

	task.delay(eyeFlareAt, function()
		if not folder.Parent then return end
		for _, e in ipairs(eyes) do
			e.eye.Transparency = 0
			e.eye.Size = Vector3.new(0.2, 0.2, 0.2)
			e.light.Brightness, e.light.Range = 4, 10
			e.glow.Size = seq(0, 1.2, 1, 0.6)
			-- Glint flashes wide, then settles.
			e.glint.Transparency = 0
			e.glint.Size = Vector3.new(2.4, 0.05, 0.05)
			TweenService:Create(e.glint, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.8, 0.03, 0.03), Transparency = 0.3 }):Play()
		end
		if isLocal then shake(0.25, 0.2) end
	end)

	-- ── Caster-only: the frozen wasteland around them ──
	local grade: ColorCorrectionEffect? = nil
	local dof: DepthOfFieldEffect? = nil
	if isLocal then
		-- Giant ice formations erupting behind and to the sides.
		for k = 1, 9 do
			local a = math.rad(-80 + (k - 1) * 20) + (math.random() - 0.5) * 0.2
			local dist = 11 + math.random() * 14
			local dir = (-look * math.cos(a) + right * math.sin(a)).Unit
			local p = groundAt(ground + dir * dist, ground.Y)
			local h = 10 + math.random() * 16
			local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(math.rad(-10 - math.random() * 20), 0, math.rad((math.random() - 0.5) * 20))
			task.delay(k * 0.03, function()
				if not folder.Parent then return end
				local c = makeCrystal(folder, cf, 3 + math.random() * 3, h, true)
				eruptCrystal(c, cf, h, 0.25)
			end)
		end
		-- Frost sheet across the ground.
		local sheet = groundDisc(folder, ground, 4, ICE_PALE, Enum.Material.Ice, 0.35)
		TweenService:Create(sheet, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.08, 70, 70) }):Play()

		-- Dense rolling fog around and behind the mage.
		local fogPart = newPart(folder, { Size = Vector3.new(34, 1, 34), Transparency = 1, CFrame = CFrame.new(ground + Vector3.new(0, 1.5, 0) - look * 6) })
		newEmitter(fogPart, {
			Texture = TEX_SMOKE,
			Color = colors(Color3.fromRGB(220, 235, 255), Color3.fromRGB(150, 180, 220)),
			Size = seq(0, 6, 1, 14),
			Transparency = seq(0, 1, 0.3, 0.45, 0.8, 0.55, 1, 1),
			Lifetime = NumberRange.new(1.4, 2.2),
			Speed = NumberRange.new(2, 5),
			SpreadAngle = Vector2.new(180, 10),
			Acceleration = Vector3.new(0, 1, 0) + right * 3,
			LightEmission = 0.15,
			Rate = 45,
			Rotation = NumberRange.new(0, 360),
			RotSpeed = NumberRange.new(-15, 15),
		}):Emit(20)
		-- Snow streaking sideways across the whole frame (also between camera and mage).
		local snowPart = newPart(folder, { Size = Vector3.new(4, 16, 40), Transparency = 1,
			-- Volume on the left of the frame; emits along +right across it.
			CFrame = CFrame.lookAt(root.Position + look * 3 - right * 16 + Vector3.new(0, 4, 0), root.Position + look * 3 - right * 16 + Vector3.new(0, 4, 0) + look) })
		newEmitter(snowPart, {
			Texture = TEX_SPARKLE,
			Color = colors(ICE_WHITE, ICE_PALE),
			Size = seq(0, 0.25, 1, 0.15),
			Transparency = seq(0, 0.15, 1, 0.6),
			Lifetime = NumberRange.new(0.9, 1.4),
			Speed = NumberRange.new(30, 45),
			SpreadAngle = Vector2.new(6, 6),
			EmissionDirection = Enum.NormalId.Right,
			Acceleration = Vector3.new(0, -6, 0),
			LightEmission = 0.5,
			Rate = 260,
		})

		-- Cold backlight: carves the silhouette out of the fog.
		local back = newPart(folder, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(root.Position - look * 7 + Vector3.new(0, 3, 0)) })
		local bl = Instance.new("PointLight")
		bl.Color, bl.Brightness, bl.Range, bl.Shadows = RIM, 6, 26, false
		bl.Parent = back

		-- Grade: cold, desaturated, contrasty — plus a shallow focus on the mage.
		grade = Instance.new("ColorCorrectionEffect")
		grade.Name = "BlizzardRevealGrade"
		grade.Parent = Lighting
		TweenService:Create(grade, TweenInfo.new(0.3), { TintColor = Color3.fromRGB(190, 212, 255), Saturation = -0.55, Contrast = 0.25, Brightness = -0.03 }):Play()
		dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "BlizzardRevealDOF"
		dof.FocusDistance = 7
		dof.InFocusRadius = 5
		dof.NearIntensity = 0.2
		dof.FarIntensity = 0
		dof.Parent = Lighting
		TweenService:Create(dof, TweenInfo.new(0.4), { FarIntensity = 0.55 }):Play()
	end

	-- ── Release: the silhouette shatters away as the storm breaks ──
	task.delay(duration, function()
		if not folder.Parent then return end
		for _, e in ipairs(eyes) do
			flashLight(e.eye.Position, EYE_BLUE, 6, 16, 0.4)
			e.glow.Enabled = false
		end
		snowBurst(root.Position, 26, 30, 0.9)
		restoreBody()
		for _, w in ipairs(wisps) do
			w.pe.Enabled = false
			Debris:AddItem(w.att, 1)
		end
		TweenService:Create(hl, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FillTransparency = 1, OutlineTransparency = 1 }):Play()
		if grade then
			TweenService:Create(grade, TweenInfo.new(0.5), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 }):Play()
			Debris:AddItem(grade, 0.6)
		end
		if dof then
			TweenService:Create(dof, TweenInfo.new(0.3), { FarIntensity = 0, NearIntensity = 0 }):Play()
			Debris:AddItem(dof, 0.4)
		end
		-- The formations crumble into the storm.
		for _, c in ipairs(folder:GetChildren()) do
			if c.Name == "Crystal" and c:IsA("BasePart") then
				task.delay(math.random() * 0.3, function()
					if c.Parent then
						flingShards(folder, c.Position + Vector3.new(0, 4, 0), 4, 30, 1.4)
						sinkAndFade(c, 12, 0.45)
					end
				end)
			end
		end
		fadeOut(folder, 0.9)
		Debris:AddItem(folder, 1.6)
	end)
	-- Safety: never leave the grade/DOF/wisps behind if the caster dies mid-reveal.
	task.delay(duration + 2, function()
		for _, w in ipairs(wisps) do
			if w.att.Parent then w.att:Destroy() end
		end
		restoreBody()
		if grade and grade.Parent then grade:Destroy() end
		if dof and dof.Parent then dof:Destroy() end
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Init
-- ═════════════════════════════════════════════════════════════════════════════
function IceMageVFX.Init(cameraShake: (number, number) -> ())
	shakeFn = cameraShake
	local Network = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("Network"))
	Network.GetRemoteEvent(Network.Remotes.IceMageEvent).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		if payload.kind == "CloneShatter" and typeof(payload.position) == "Vector3" then
			IceMageVFX.playCloneShatter(payload.position, payload.radius or 14)
		elseif payload.kind == "Chill" and typeof(payload.model) == "Instance" then
			IceMageVFX.playChill(payload.model, payload.duration or 1)
		end
	end)

	local function watch(folder: Instance)
		for _, c in ipairs(folder:GetChildren()) do
			if c:IsA("Model") then task.spawn(IceMageVFX.decorateClone, c) end
		end
		folder.ChildAdded:Connect(function(c)
			if c:IsA("Model") then task.spawn(IceMageVFX.decorateClone, c) end
		end)
	end
	local existing = Workspace:FindFirstChild("IceClones")
	if existing then watch(existing) end
	Workspace.ChildAdded:Connect(function(c)
		if c.Name == "IceClones" then watch(c) end
	end)
end

return IceMageVFX
