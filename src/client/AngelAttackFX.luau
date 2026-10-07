--!strict
--[[
	AngelAttackFX.luau
	The pictures of the Fallen Angel's attacks (BossAI), on every client in
	the run. The server draws the red telegraphs and deals the damage; this
	draws the rest, from BossFX events:

	  kind "angel"
	    descent  rise: a void sigil turning where it will land under a column
	             of crimson light; impact: a crater of void fire (a flash,
	             rings, black shards bursting up, rocks, embers, feathers);
	             aftershock: a wall of fire rolling out past it
	    feather  a feather blade forming at its wings, then thrown at its
	             mark (a trail, sparks, the blade left stuck in the floor)
	    cross    warn: a sigil under it, the arms' cracks glowing; erupt:
	             columns of void fire bursting up along each arm in turn
	    dash     warn: shadow streaming down the line; go: afterimages of it
	             along the path, a black-red streak, feathers
	    sweep    warn: the sword glowing; slash: a crescent of light through
	             the fan, sparks, a scar on the floor
	  kind "judgement"
	    pillars  a beam of gold from the sky onto each spot, dust and rock as
	             each pillar lands
	    charge   the whole room tinted red, and behind every pillar its
	             shelter lit in gold; the void gathering over the angel
	    strike   the wave: a wall of void fire rolling out over the whole
	             room, broken behind each pillar (they flare gold as it hits);
	             a blast where it lands

	Boss attacks are warnings the player must see: none of it asks the
	FxBudget, but for the short flash lights (FxBudget.Light).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local BossCinematic: any = nil
pcall(function() BossCinematic = require(script.Parent:WaitForChild("BossCinematic")) end)

local AngelAttackFX = {}

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local CRIMSON = Color3.fromRGB(225, 35, 45)
local BLOOD = Color3.fromRGB(150, 16, 22)
local VOID = Color3.fromRGB(16, 6, 10)
local HOT = Color3.fromRGB(255, 228, 220)
local GOLD = Color3.fromRGB(255, 215, 130)
local ROCK = Color3.fromRGB(44, 38, 42)
local FEATHER = Color3.fromRGB(220, 216, 214)
-- (a cylinder's length runs along X: this turn lays a short one flat as a
-- disc, and stands a long one up as a column)
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local TAU = math.pi * 2

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function folder(): Instance
	local f = Workspace:FindFirstChild("AngelClientFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "AngelClientFX"
		f.Parent = Workspace
	end
	return f :: Instance
end

local function part(props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = folder()
	return p
end

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function ns(a: number, b: number): NumberSequence
	return NumberSequence.new({ NumberSequenceKeypoint.new(0, a), NumberSequenceKeypoint.new(1, b) })
end

local function myRoot(): BasePart?
	local char = Players.LocalPlayer.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

-- The camera shakes for those near enough to feel it.
local function shakeNear(pos: Vector3, power: number, duration: number, range: number?)
	local r = myRoot()
	if r and (r.Position - pos).Magnitude < (range or 80) and BossCinematic and BossCinematic.Shake then
		BossCinematic.Shake(power, duration)
	end
end

local function dirAt(a: number): Vector3
	return Vector3.new(math.cos(a), 0, math.sin(a))
end

-- A one-off burst of particles at `pos`.
local function burst(pos: Vector3, n: number, props: { [string]: any })
	local holder = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = holder
	e:Emit(n)
	Debris:AddItem(holder, e.Lifetime.Max + 0.2)
end

local function sparks(pos: Vector3, n: number, color: Color3, speed: number, size: number?)
	burst(pos, n, {
		Texture = SPARK, LightEmission = 1, Color = ColorSequence.new(HOT, color),
		Size = ns(size or 0.8, 0), Lifetime = NumberRange.new(0.4, 0.9),
		Speed = NumberRange.new(speed * 0.5, speed), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, -30, 0), Drag = 2,
	})
end

local function smoke(pos: Vector3, n: number, color: Color3, size: number)
	burst(pos, n, {
		Texture = SMOKE, LightEmission = 0, Color = ColorSequence.new(color),
		Transparency = ns(0.3, 1), Size = ns(size, size * 2.4), Lifetime = NumberRange.new(0.8, 1.6),
		Speed = NumberRange.new(5, 14), SpreadAngle = Vector2.new(75, 75), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-40, 40), Drag = 3, Acceleration = Vector3.new(0, 3, 0),
	})
end

local function flames(pos: Vector3, n: number, size: number, speed: number)
	burst(pos, n, {
		Texture = FIRE, LightEmission = 0.7, Color = ColorSequence.new(CRIMSON, VOID),
		Transparency = ns(0.1, 1), Size = ns(size, size * 0.3), Lifetime = NumberRange.new(0.35, 0.6),
		Speed = NumberRange.new(speed * 0.6, speed), SpreadAngle = Vector2.new(14, 14), Rotation = NumberRange.new(0, 360),
	})
end

-- A short flash of light (budgeted: lights are the dearest effect).
local function flashLight(pos: Vector3, color: Color3, range: number, brightness: number, life: number)
	if not FxBudget.Light() then return end
	local holder = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight")
	l.Color, l.Range, l.Brightness, l.Shadows = color, range, brightness, false
	l.Parent = holder
	FxBudget.TrackLight(l)
	tween(l, life, { Brightness = 0 })
	Debris:AddItem(holder, life + 0.05)
end

-- A flat disc on the floor growing from `from` to `to` studs across and fading.
local function ring(pos: Vector3, from: number, to: number, t: number, color: Color3)
	local r = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, from * 2, from * 2),
		CFrame = CFrame.new(pos) * FLAT, Color = color, Transparency = 0.15 })
	tween(r, t, { Size = Vector3.new(0.05, to * 2, to * 2), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(r, t + 0.05)
end

local function orb(pos: Vector3, from: number, to: number, t: number, color: Color3, material: Enum.Material?)
	local s = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * from, CFrame = CFrame.new(pos), Color = color,
		Transparency = 0.1, Material = material or Enum.Material.Neon })
	tween(s, t, { Size = Vector3.one * to, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(s, t + 0.05)
end

-- A flat triangle a-b-c, out of two wedges.
local function triangle(a: Vector3, b: Vector3, c: Vector3, props: { [string]: any }): { BasePart }
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
	local w1 = part(props, "WedgePart")
	w1.Size = Vector3.new(0.1, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local w2 = part(props, "WedgePart")
	w2.Size = Vector3.new(0.1, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	return { w1, w2 }
end

-- A glowing bar on the floor from `a` to `b`.
local function line(a: Vector3, b: Vector3, width: number, color: Color3, transparency: number): BasePart
	return part({ Size = Vector3.new(width, 0.12, (b - a).Magnitude), CFrame = CFrame.lookAt((a + b) / 2, b),
		Color = color, Transparency = transparency })
end

-- A turning sigil on the floor: a bright rim and four spokes (an outline,
-- so the red telegraph filling up under it still shows).
local function sigil(pos: Vector3, radius: number, life: number, color: Color3): { BasePart }
	local y = pos + Vector3.new(0, 0.16, 0)
	local out = {}
	local n = 28
	for k = 0, n - 1 do
		local a1, a2 = k / n * TAU, (k + 1) / n * TAU
		local rim = line(y + dirAt(a1) * radius, y + dirAt(a2) * radius, 0.45, HOT, 1)
		tween(rim, 0.25, { Transparency = 0.1 })
		table.insert(out, rim)
	end
	for k = 0, 3 do
		local a = k * math.pi / 4
		local spoke = part({ Size = Vector3.new(0.3, 0.14, radius * 1.9), CFrame = CFrame.new(y + Vector3.new(0, 0.02, 0)) * CFrame.Angles(0, a, 0),
			Color = color, Transparency = 1 })
		tween(spoke, 0.25, { Transparency = 0.15 })
		tween(spoke, life, { CFrame = spoke.CFrame * CFrame.Angles(0, math.rad(90), 0) }, Enum.EasingStyle.Linear)
		table.insert(out, spoke)
	end
	for _, p in ipairs(out) do Debris:AddItem(p, life + 0.3) end
	task.delay(life, function()
		for _, p in ipairs(out) do
			if p.Parent then tween(p, 0.25, { Transparency = 1 }) end
		end
	end)
	return out
end

-- ── Things thrown about (rocks, feathers), stepped together ─────────────────
type Flier = { p: BasePart, v: Vector3, spin: Vector3, t: number, life: number, floorY: number, g: number, drag: number, sway: number }
local fliers: { Flier } = {}

local function fling(p: BasePart, v: Vector3, life: number, floorY: number, g: number, drag: number, sway: number)
	table.insert(fliers, { p = p, v = v, spin = Vector3.new(math.random() * 8 - 4, math.random() * 8 - 4, 0), t = 0,
		life = life, floorY = floorY, g = g, drag = drag, sway = sway })
end

local function stepFliers(dt: number)
	for i = #fliers, 1, -1 do
		local f = fliers[i]
		f.t += dt
		if not f.p.Parent or f.t > f.life then
			f.p:Destroy()
			table.remove(fliers, i)
			continue
		end
		f.v = (f.v + Vector3.new(0, -f.g * dt, 0)) * (1 - math.min(f.drag * dt, 0.5))
		local swayV = if f.sway > 0 then Vector3.new(math.sin(f.t * 4 + i) * f.sway, 0, math.cos(f.t * 3 + i) * f.sway) else Vector3.zero
		local cf = f.p.CFrame + (f.v + swayV) * dt
		local bottom = f.floorY + f.p.Size.Y / 2
		if cf.Position.Y < bottom then
			cf += Vector3.new(0, bottom - cf.Position.Y, 0)
			f.v = Vector3.new(f.v.X * 0.45, math.abs(f.v.Y) * 0.3, f.v.Z * 0.45)
			f.spin *= 0.5
		end
		f.p.CFrame = cf * CFrame.Angles(f.spin.X * dt, f.spin.Y * dt, 0)
		if f.t > f.life - 0.4 then f.p.Transparency = math.max(f.p.Transparency, (f.t - (f.life - 0.4)) / 0.4) end
	end
end

local function rocks(pos: Vector3, n: number, speed: number)
	for _ = 1, n do
		local a = math.random() * TAU
		local s = 0.5 + math.random() * 0.9
		local p = part({ Size = Vector3.one * s, Color = ROCK, Material = Enum.Material.Slate,
			CFrame = CFrame.new(pos + Vector3.new(0, 1, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		local k = 0.4 + math.random() * 0.6
		fling(p, Vector3.new(math.cos(a) * speed * k, speed * (0.6 + math.random() * 0.6), math.sin(a) * speed * k), 1.4, pos.Y, 80, 0.2, 0)
	end
end

-- Feathers puffed into the air: white with a red tip, drifting down.
local function feathers(pos: Vector3, n: number, speed: number)
	for _ = 1, n do
		local a = math.random() * TAU
		local p = part({ Size = Vector3.new(0.35, 0.05, 1.1), Color = if math.random() < 0.3 then BLOOD else FEATHER,
			Material = Enum.Material.SmoothPlastic, CFrame = CFrame.new(pos + Vector3.new(0, 2, 0)) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		fling(p, Vector3.new(math.cos(a) * speed, speed * (0.6 + math.random() * 0.8), math.sin(a) * speed), 2.2, pos.Y, 9, 2.5, 3)
	end
end

-- Black, red-edged shards bursting up out of the floor round `pos`.
local function shards(pos: Vector3, radius: number, n: number, height: number)
	for i = 1, n do
		local a = (i / n) * TAU + math.random() * 0.4
		local base = pos + dirAt(a) * radius * (0.45 + math.random() * 0.5)
		local h = height * (0.6 + math.random() * 0.6)
		-- (leaning outward)
		local tilt = CFrame.lookAt(base, base + dirAt(a)) * CFrame.Angles(-math.rad(22 + math.random() * 18), 0, 0)
		local shard = part({ Size = Vector3.new(1, 0.2, 1), Color = VOID, Material = Enum.Material.Slate, CFrame = tilt })
		local edge = part({ Size = Vector3.new(0.35, 0.2, 1.06), Color = CRIMSON, CFrame = tilt })
		tween(shard, 0.14, { Size = Vector3.new(1, h, 1), CFrame = tilt * CFrame.new(0, h / 2, 0) }, Enum.EasingStyle.Back)
		tween(edge, 0.14, { Size = Vector3.new(0.35, h * 0.92, 1.06), CFrame = tilt * CFrame.new(0, h * 0.46, 0) }, Enum.EasingStyle.Back)
		task.delay(0.55 + math.random() * 0.2, function()
			tween(shard, 0.4, { CFrame = tilt * CFrame.new(0, -h * 0.2, 0), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(edge, 0.35, { Transparency = 1 })
		end)
		Debris:AddItem(shard, 1.3)
		Debris:AddItem(edge, 1.3)
	end
end

-- A wall of void fire rolling out from `center` at `speed`, from `r0` to
-- `reach`. `limit(angle)` stops it short in that direction (a wall, the
-- shelter of a pillar). Scorched floor trails behind it.
local function rollingWall(center: Vector3, r0: number, speed: number, reach: number, height: number, segs: number, limit: ((number) -> number)?)
	local walls: { BasePart } = {}
	local scorch: { BasePart } = {}
	local stopAt: { number } = {}
	for i = 1, segs do
		local a = (i - 0.5) / segs * TAU
		stopAt[i] = if limit then math.min(reach, limit(a)) else reach
		walls[i] = part({ Size = Vector3.new(1, height, 1.4), Color = CRIMSON, Transparency = 0.12 })
		scorch[i] = part({ Size = Vector3.new(1, 0.15, 4), Color = BLOOD, Transparency = 0.45 })
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local r = r0 + (os.clock() - t0) * speed
		local moved: { BasePart } = {}
		local cfs: { CFrame } = {}
		local live = false
		local fade = math.clamp((r - r0) / math.max(reach - r0, 1), 0, 1)
		for i = 1, segs do
			local w, s = walls[i], scorch[i]
			if r <= stopAt[i] then
				live = true
				local a = (i - 0.5) / segs * TAU
				local d = dirAt(a)
				local width = TAU * math.max(r, 1) / segs * 1.08
				local h = height * (1 - 0.4 * fade)
				w.Size = Vector3.new(width, h, 1.4)
				s.Size = Vector3.new(width, 0.15, 4)
				w.Transparency = 0.12 + 0.35 * fade
				local p = center + d * r
				table.insert(moved, w)
				table.insert(cfs, CFrame.lookAt(p + Vector3.new(0, h / 2, 0), p + Vector3.new(0, h / 2, 0) + d))
				table.insert(moved, s)
				table.insert(cfs, CFrame.lookAt(p - d * 2.2 + Vector3.new(0, 0.12, 0), p + Vector3.new(0, 0.12, 0)))
			elseif w.Transparency < 1 then
				w.Transparency = 1
				tween(s, 0.5, { Transparency = 1 })
			end
		end
		if #moved > 0 then Workspace:BulkMoveTo(moved, cfs, Enum.BulkMoveMode.FireCFrameChanged) end
		if not live then
			conn:Disconnect()
			for i = 1, segs do
				walls[i]:Destroy()
				Debris:AddItem(scorch[i], 0.6)
			end
		end
	end)
end

-- ── The Fallen Angel's attacks ──────────────────────────────────────────────
local ANGEL: { [string]: (any) -> () } = {}

ANGEL.descent = function(data)
	local pos: Vector3 = data.pos
	local radius: number = data.radius or 10
	if data.phase == "rise" then
		local life: number = data.duration or 1.2
		sigil(pos, radius, life, CRIMSON)
		-- a column of crimson light falling on the spot
		local col = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(70, 1, 1), CFrame = CFrame.new(pos + Vector3.new(0, 35, 0)) * FLAT,
			Color = CRIMSON, Transparency = 0.85 })
		tween(col, life, { Size = Vector3.new(70, radius * 0.6, radius * 0.6), Transparency = 0.55 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		Debris:AddItem(col, life + 0.05)
		-- embers rising off it
		local disc = part({ Size = Vector3.new(radius * 1.6, 0.2, radius * 1.6), CFrame = CFrame.new(pos + Vector3.new(0, 0.2, 0)), Transparency = 1 })
		local e = Instance.new("ParticleEmitter")
		e.Texture, e.LightEmission, e.LightInfluence = SPARK, 1, 0
		e.Color = ColorSequence.new(HOT, CRIMSON)
		e.Size = ns(0.6, 0)
		e.Lifetime = NumberRange.new(0.6, 1.1)
		e.Speed = NumberRange.new(6, 14)
		e.EmissionDirection = Enum.NormalId.Top
		e.Rate = 40
		e.Parent = disc
		Debris:AddItem(disc, life + 0.1)
	elseif data.phase == "impact" then
		local at = pos + Vector3.new(0, 1.5, 0)
		orb(at, 2, radius * 1.4, 0.3, HOT)
		orb(at, 3, radius * 2, 0.55, CRIMSON)
		ring(pos + Vector3.new(0, 0.3, 0), 2, radius * 1.3, 0.4, HOT)
		ring(pos + Vector3.new(0, 0.25, 0), 3, radius * 2.1, 0.75, BLOOD)
		shards(pos, radius, 10, 7)
		rocks(pos, 10, 40)
		feathers(pos, 8, 14)
		sparks(at, 40, CRIMSON, 50, 1.2)
		smoke(pos, 12, Color3.fromRGB(40, 24, 28), 4)
		flames(pos, 10, 4, 22)
		flashLight(at + Vector3.new(0, 3, 0), CRIMSON, 36, 5, 0.45)
		shakeNear(pos, 1.4, 0.4)
	elseif data.phase == "aftershock" then
		rollingWall(pos, radius * 0.4, 46, radius, 3.5, 40, nil)
		sparks(pos + Vector3.new(0, 1, 0), 20, CRIMSON, 35)
		shakeNear(pos, 0.7, 0.3)
	end
end

ANGEL.feather = function(data)
	local from: Vector3 = data.from
	local to: Vector3 = data.pos + Vector3.new(0, 0.6, 0)
	local delay: number = data.delay or 0.5
	local flight: number = data.flight or 0.3
	-- the blade: a long black feather with a red edge, a white tip
	local aim = CFrame.lookAt(from, to)
	local blade = part({ Size = Vector3.new(0.55, 0.14, 3.6), Color = VOID, Material = Enum.Material.SmoothPlastic, CFrame = aim, Transparency = 1 })
	local edge = part({ Size = Vector3.new(0.2, 0.16, 3.8), Color = CRIMSON, CFrame = aim * CFrame.new(0.22, 0, 0), Transparency = 1 })
	local tip = part({ Size = Vector3.new(0.3, 0.17, 0.8), Color = HOT, CFrame = aim * CFrame.new(0, 0, -1.6), Transparency = 1 })
	local pieces = { { blade, CFrame.identity }, { edge, CFrame.new(0.22, 0, 0) }, { tip, CFrame.new(0, 0, -1.6) } }
	for _, pc in ipairs(pieces) do tween(pc[1], 0.2, { Transparency = if pc[1] == blade then 0 else 0.05 }) end
	sparks(from, 8, CRIMSON, 8, 0.5)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, 1.6)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, -1.6)
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(CRIMSON, BLOOD)
	trail.Transparency = ns(0.2, 1)
	trail.Lifetime = 0.18
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.Enabled = false
	trail.Parent = blade
	local function place(cf: CFrame)
		for _, pc in ipairs(pieces) do pc[1].CFrame = cf * pc[2] end
	end
	task.spawn(function()
		-- hovering at the wing, quivering, then thrown
		local t0 = os.clock()
		while os.clock() - t0 < delay do
			local k = os.clock() - t0
			place(CFrame.lookAt(from + Vector3.new(0, math.sin(k * 20) * 0.08, 0), to))
			RunService.RenderStepped:Wait()
		end
		trail.Enabled = true
		t0 = os.clock()
		while os.clock() - t0 < flight do
			local k = (os.clock() - t0) / flight
			local p = from:Lerp(to, k) + Vector3.new(0, math.sin(k * math.pi) * 2, 0)
			place(CFrame.lookAt(p, to))
			RunService.RenderStepped:Wait()
		end
		-- stuck in the floor where it lands
		place(CFrame.lookAt(to, to + (to - from).Unit) * CFrame.new(0, 0, 1.2))
		trail.Enabled = false
		sparks(to, 14, CRIMSON, 22, 0.7)
		smoke(data.pos, 4, Color3.fromRGB(40, 24, 28), 2)
		ring(data.pos + Vector3.new(0, 0.2, 0), 1, (data.radius or 4.5) * 1.1, 0.3, CRIMSON)
		flashLight(to + Vector3.new(0, 2, 0), CRIMSON, 14, 2, 0.25)
		task.wait(0.7)
		for _, pc in ipairs(pieces) do tween(pc[1], 0.35, { Transparency = 1 }) end
		task.wait(0.4)
		for _, pc in ipairs(pieces) do pc[1]:Destroy() end
	end)
end

-- A column of void fire bursting up at `pos` (a red sheath, a black heart).
local function column(pos: Vector3, width: number)
	local w = width * (0.55 + math.random() * 0.2)
	local h = 9 + math.random() * 5
	local base = CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi, 0)
	local outer = part({ Size = Vector3.new(w, 0.4, w), CFrame = base, Color = CRIMSON, Transparency = 0.15 })
	local core = part({ Size = Vector3.new(w * 0.5, 0.4, w * 0.5), CFrame = base, Color = VOID, Material = Enum.Material.SmoothPlastic })
	tween(outer, 0.12, { Size = Vector3.new(w, h, w), CFrame = base + Vector3.new(0, h / 2, 0) })
	tween(core, 0.12, { Size = Vector3.new(w * 0.5, h * 1.12, w * 0.5), CFrame = base + Vector3.new(0, h * 0.56, 0) })
	task.delay(0.16, function()
		tween(outer, 0.35, { Size = Vector3.new(w * 0.15, h * 1.25, w * 0.15), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(core, 0.3, { Size = Vector3.new(0.1, h, 0.1), Transparency = 1 })
	end)
	Debris:AddItem(outer, 0.6)
	Debris:AddItem(core, 0.6)
	flames(pos + Vector3.new(0, 1, 0), 3, 3.5, 22)
end

ANGEL.cross = function(data)
	local center: Vector3 = data.pos
	local width: number = data.width or 8
	local arms = if typeof(data.arms) == "table" then data.arms else {}
	if data.phase == "warn" then
		local life: number = data.duration or 1
		sigil(center, width * 0.9, life, CRIMSON)
		-- cracks glowing down every arm
		for _, arm in ipairs(arms) do
			local len: number = arm.len
			local crack = line(center + Vector3.new(0, 0.18, 0), center + arm.dir * len + Vector3.new(0, 0.18, 0), 0.5, HOT, 1)
			tween(crack, life, { Transparency = 0.15, Size = Vector3.new(1.1, 0.12, len) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(crack, life + 0.1)
		end
	elseif data.phase == "erupt" then
		local speed: number = data.speed or 85
		orb(center + Vector3.new(0, 2, 0), 2, width * 1.6, 0.35, HOT)
		sparks(center + Vector3.new(0, 1, 0), 30, CRIMSON, 40, 1)
		flashLight(center + Vector3.new(0, 4, 0), CRIMSON, 30, 4, 0.5)
		shakeNear(center, 1, 0.5)
		for _, arm in ipairs(arms) do
			local len: number = arm.len
			local d = 1.5
			while d <= len do
				local at = center + arm.dir * d
				task.delay(d / speed, column, at, width)
				d += 3.6
			end
			-- a scorched scar down the arm, fading
			local scar = line(center + Vector3.new(0, 0.15, 0), center + arm.dir * len + Vector3.new(0, 0.15, 0), width * 0.5, BLOOD, 0.35)
			scar.Material = Enum.Material.Neon
			task.delay(len / speed + 0.2, function() tween(scar, 0.9, { Transparency = 1 }) end)
			Debris:AddItem(scar, len / speed + 1.2)
		end
	end
end

-- The parts its afterimages are cast from (its silhouette, not every feather).
local SILHOUETTE = {
	Torso = true, Head = true, HoodBack = true, ArmL = true, ArmR = true, LegL = true, LegR = true,
	Pauldron = true, WingBone = true, Covert = true, SwordBlade = true,
}

ANGEL.dash = function(data)
	if data.phase == "warn" then
		local from: Vector3 = data.from
		local dir: Vector3 = data.dir
		local len: number = data.len or 30
		local life: number = data.duration or 0.9
		local floorY = from.Y - 3
		local mid = from + dir * (len / 2)
		local lane = part({ Size = Vector3.new(data.width or 9, 1, len), Transparency = 1,
			CFrame = CFrame.lookAt(Vector3.new(mid.X, floorY + 1.5, mid.Z), Vector3.new(mid.X, floorY + 1.5, mid.Z) + dir) })
		local e = Instance.new("ParticleEmitter")
		e.Texture, e.LightEmission, e.LightInfluence = SMOKE, 0.3, 0
		e.Color = ColorSequence.new(CRIMSON, VOID)
		e.Transparency = ns(0.35, 1)
		e.Size = ns(2.2, 0.6)
		e.Lifetime = NumberRange.new(0.3, 0.6)
		e.Speed = NumberRange.new(25, 45)
		e.EmissionDirection = Enum.NormalId.Front
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 70
		e.Parent = lane
		task.delay(life, function() e.Enabled = false end)
		Debris:AddItem(lane, life + 0.7)
	elseif data.phase == "go" then
		local from: Vector3 = data.from
		local to: Vector3 = data.to
		local dur: number = data.duration or 0.32
		local model: Instance? = if typeof(data.model) == "Instance" then data.model else nil
		-- a black-red streak down the path
		local streak = part({ Size = Vector3.new(2.4, 2.4, (to - from).Magnitude), CFrame = CFrame.lookAt((from + to) / 2, to), Color = CRIMSON, Transparency = 0.3 })
		local core = part({ Size = Vector3.new(1.1, 1.1, (to - from).Magnitude), CFrame = streak.CFrame, Color = VOID, Material = Enum.Material.SmoothPlastic, Transparency = 0.2 })
		tween(streak, 0.5, { Size = Vector3.new(0.1, 0.1, streak.Size.Z), Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		tween(core, 0.4, { Size = Vector3.new(0.05, 0.05, core.Size.Z), Transparency = 1 })
		Debris:AddItem(streak, 0.55)
		Debris:AddItem(core, 0.45)
		feathers(from - Vector3.new(0, 2, 0), 8, 12)
		sparks(from, 14, CRIMSON, 20)
		-- afterimages along the way
		if model then
			local src: { BasePart } = {}
			for _, d in ipairs(model:GetDescendants()) do
				if d:IsA("BasePart") and SILHOUETTE[d.Name] then table.insert(src, d) end
			end
			for k = 1, 4 do
				task.delay(dur * k / 5, function()
					for _, s in ipairs(src) do
						if s.Parent then
							local ghost = part({ Size = s.Size, CFrame = s.CFrame, Color = if k % 2 == 0 then CRIMSON else BLOOD, Transparency = 0.45 })
							tween(ghost, 0.45, { Transparency = 1 })
							Debris:AddItem(ghost, 0.5)
						end
					end
				end)
			end
		end
		task.delay(dur, function()
			feathers(to - Vector3.new(0, 2, 0), 10, 16)
			sparks(to, 24, CRIMSON, 30)
			ring(Vector3.new(to.X, from.Y - 2.8, to.Z), 2, 9, 0.4, CRIMSON)
			shakeNear(to, 0.8, 0.3)
		end)
	end
end

ANGEL.sweep = function(data)
	local origin: Vector3 = data.pos
	local dir: Vector3 = data.dir
	local radius: number = data.radius or 18
	local half: number = data.half or math.rad(65)
	local side: number = data.side or 1
	local model: Instance? = if typeof(data.model) == "Instance" then data.model else nil
	if data.phase == "warn" then
		-- the sword gathers light
		local blade = model and model:FindFirstChild("SwordBlade", true) :: BasePart?
		if blade then
			local e = Instance.new("ParticleEmitter")
			e.Name = "AngelSwordGlow"
			e.Texture, e.LightEmission, e.LightInfluence = SPARK, 1, 0
			e.Color = ColorSequence.new(HOT, CRIMSON)
			e.Size = ns(0.7, 0)
			e.Lifetime = NumberRange.new(0.3, 0.5)
			e.Speed = NumberRange.new(1, 3)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.Rate = 60
			e.Parent = blade
			Debris:AddItem(e, (data.duration or 0.9) + 0.2)
		end
		-- the fan's edge traced in light
		local o = Vector3.new(origin.X, origin.Y + 0.2, origin.Z)
		local base = math.atan2(dir.Z, dir.X)
		local n = 14
		for i = 0, n - 1 do
			local a1 = base - half + (i / n) * half * 2
			local a2 = base - half + ((i + 1) / n) * half * 2
			local seg = line(o + dirAt(a1) * radius, o + dirAt(a2) * radius, 0.4, HOT, 1)
			tween(seg, data.duration or 0.9, { Transparency = 0.2 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(seg, (data.duration or 0.9) + 0.05)
		end
	elseif data.phase == "slash" then
		-- a crescent of light sweeping through the fan
		local base = math.atan2(dir.Z, dir.X)
		local a0 = base + side * half
		local a1 = base - side * half
		local n = 16
		local sweepT = 0.14
		local y = origin.Y + 2.6
		for i = 0, n - 1 do
			task.delay(sweepT * i / n, function()
				local a = a0 + (a1 - a0) * (i + 0.5) / n
				local d = dirAt(a)
				local rm = radius * 0.72
				local arcW = radius * math.abs(a1 - a0) / n * 1.15
				local p = Vector3.new(origin.X, y, origin.Z) + d * rm
				local blade = part({ Size = Vector3.new(arcW, 0.5, radius * 0.5), CFrame = CFrame.lookAt(p, p + d), Color = HOT, Transparency = 0.05 })
				local glow = part({ Size = Vector3.new(arcW, 1.6, radius * 0.62), CFrame = blade.CFrame, Color = CRIMSON, Transparency = 0.5 })
				tween(blade, 0.3, { Size = Vector3.new(arcW, 0.05, radius * 0.2), Transparency = 1, Color = CRIMSON })
				tween(glow, 0.35, { Transparency = 1 })
				Debris:AddItem(blade, 0.35)
				Debris:AddItem(glow, 0.4)
				-- a scar on the floor under it
				local fp = Vector3.new(origin.X, origin.Y + 0.15, origin.Z) + d * rm
				local scar = part({ Size = Vector3.new(arcW, 0.1, radius * 0.35), CFrame = CFrame.lookAt(fp, fp + d), Color = BLOOD, Transparency = 0.3 })
				task.delay(0.4, function() tween(scar, 0.9, { Transparency = 1 }) end)
				Debris:AddItem(scar, 1.4)
			end)
		end
		task.delay(sweepT, function()
			local endPos = Vector3.new(origin.X, y, origin.Z) + dirAt(a1) * radius * 0.8
			sparks(endPos, 26, CRIMSON, 34, 0.9)
			flashLight(endPos, CRIMSON, 22, 3, 0.3)
		end)
		shakeNear(origin, 0.9, 0.25)
	end
end

-- ── JUDGEMENT ───────────────────────────────────────────────────────────────
type Shadow = { theta: number, half: number, dist: number, radius: number, pos: Vector3 }

local function angleDiff(a: number, b: number): number
	return math.abs((a - b + math.pi) % TAU - math.pi)
end

-- The arc of the room each pillar shelters, seen from `mid`.
local function shadows(mid: Vector3, covers: any): { Shadow }
	local out = {}
	for _, c in ipairs(if typeof(covers) == "table" then covers else {}) do
		local d = Vector3.new(c.pos.X - mid.X, 0, c.pos.Z - mid.Z)
		local D = d.Magnitude
		if D > c.radius + 0.5 then
			table.insert(out, { theta = math.atan2(d.Z, d.X), half = math.asin(math.min(1, c.radius / D)), dist = D, radius = c.radius, pos = c.pos })
		end
	end
	return out
end

-- How far it is from `mid` to the room's edge going along angle `a`.
local function edgeDist(mid: Vector3, a: number, bounds: any): number
	if typeof(bounds) ~= "table" then return 100 end
	local dx, dz = math.cos(a), math.sin(a)
	local t = math.huge
	if dx > 1e-4 then t = math.min(t, (bounds.maxX - mid.X) / dx) elseif dx < -1e-4 then t = math.min(t, (bounds.minX - mid.X) / dx) end
	if dz > 1e-4 then t = math.min(t, (bounds.maxZ - mid.Z) / dz) elseif dz < -1e-4 then t = math.min(t, (bounds.minZ - mid.Z) / dz) end
	return math.max(0, t)
end

local judgementFx: { BasePart } = {} -- the red room and the gold shelters
local judgementOrb: { BasePart } = {} -- the void gathering over the angel

local function clearJudgement(t: number)
	for _, p in ipairs(judgementFx) do
		if p.Parent then
			tween(p, t, { Transparency = 1 })
			Debris:AddItem(p, t + 0.05)
		end
	end
	table.clear(judgementFx)
end

local JUDGEMENT: { [string]: (any) -> () } = {}

JUDGEMENT.pillars = function(data)
	local fall: number = data.fall or 0.5
	local height: number = data.height or 18
	for _, drop in ipairs(if typeof(data.drops) == "table" then data.drops else {}) do
		local pos: Vector3 = drop.pos
		task.delay(drop.at or 0, function()
			-- a beam of gold from the sky onto the spot
			local beam = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(90, 0.6, 0.6), CFrame = CFrame.new(pos + Vector3.new(0, 45, 0)) * FLAT,
				Color = GOLD, Transparency = 0.6 })
			tween(beam, fall, { Size = Vector3.new(90, 7, 7), Transparency = 0.3 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			task.delay(fall, function()
				tween(beam, 0.4, { Size = Vector3.new(90, 0.1, 0.1), Transparency = 1 })
				Debris:AddItem(beam, 0.45)
				-- the landing: dust, rock, a gold ring
				smoke(pos, 14, Color3.fromRGB(150, 140, 150), 4)
				rocks(pos, 6, 28)
				ring(pos + Vector3.new(0, 0.3, 0), 3, 11, 0.45, GOLD)
				sparks(pos + Vector3.new(0, height * 0.9, 0), 16, GOLD, 18, 0.8)
				flashLight(pos + Vector3.new(0, 4, 0), GOLD, 24, 3, 0.4)
				shakeNear(pos, 0.7, 0.25, 70)
			end)
		end)
	end
end

JUDGEMENT.charge = function(data)
	clearJudgement(0.1)
	local mid: Vector3 = data.pos
	local life: number = data.duration or 3.6
	local bounds = data.bounds
	local y = mid.Y
	-- The whole room goes red...
	local overlay
	if typeof(bounds) == "table" then
		overlay = part({ Size = Vector3.new(bounds.maxX - bounds.minX, 0.1, bounds.maxZ - bounds.minZ),
			CFrame = CFrame.new((bounds.minX + bounds.maxX) / 2, y + 0.12, (bounds.minZ + bounds.maxZ) / 2), Color = BLOOD, Transparency = 1 })
	else
		overlay = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 200, 200), CFrame = CFrame.new(mid + Vector3.new(0, 0.12, 0)) * FLAT,
			Color = BLOOD, Transparency = 1 })
	end
	-- (red at once, then deepening as the void gathers)
	TweenService:Create(overlay, TweenInfo.new(0.5), { Transparency = 0.78 }):Play()
	task.delay(0.5, function()
		if overlay.Parent then tween(overlay, math.max(life - 0.5, 0.1), { Transparency = 0.6 }, Enum.EasingStyle.Linear) end
	end)
	table.insert(judgementFx, overlay)
	-- ...but for the shelter behind every pillar, in gold.
	for _, s in ipairs(shadows(mid, data.covers)) do
		local half = s.half * 0.85 -- (drawn a touch inside the true shelter)
		local r1 = s.dist + s.radius * 0.6
		local r2 = edgeDist(mid, s.theta, bounds) - 1
		if r2 > r1 + 2 then
			local fy = Vector3.new(0, y + 0.2, 0)
			local function at(r: number, a: number): Vector3
				return Vector3.new(mid.X, 0, mid.Z) + dirAt(a) * r + fy
			end
			local p1, p2 = at(r1, s.theta - half), at(r1, s.theta + half)
			local p3, p4 = at(r2, s.theta + half), at(r2, s.theta - half)
			local zone = triangle(p1, p2, p3, { Color = GOLD, Transparency = 1 })
			for _, w in ipairs(triangle(p1, p3, p4, { Color = GOLD, Transparency = 1 })) do table.insert(zone, w) end
			table.insert(zone, line(p1 + Vector3.new(0, 0.02, 0), p4 + Vector3.new(0, 0.02, 0), 0.35, HOT, 1))
			table.insert(zone, line(p2 + Vector3.new(0, 0.02, 0), p3 + Vector3.new(0, 0.02, 0), 0.35, HOT, 1))
			for _, w in ipairs(zone) do
				-- (in, then pulsing so the eye finds it)
				local edge = w:IsA("Part")
				local fadeIn = TweenService:Create(w, TweenInfo.new(0.35), { Transparency = if edge then 0.15 else 0.5 })
				fadeIn.Completed:Connect(function(state)
					if state ~= Enum.PlaybackState.Completed or not w.Parent then return end
					TweenService:Create(w, TweenInfo.new(0.5, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
						{ Transparency = if edge then 0 else 0.3 }):Play()
				end)
				fadeIn:Play()
				table.insert(judgementFx, w)
			end
		end
		-- a gold ring round the pillar's foot
		local foot = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, s.radius * 2 + 3, s.radius * 2 + 3),
			CFrame = CFrame.new(s.pos.X, y + 0.22, s.pos.Z) * FLAT, Color = GOLD, Transparency = 1 })
		tween(foot, 0.4, { Transparency = 0.35 })
		table.insert(judgementFx, foot)
	end
	-- The void gathers over the angel.
	local model: Instance? = if typeof(data.model) == "Instance" then data.model else nil
	local top = mid + Vector3.new(0, 26, 0)
	if model and model:IsA("Model") then
		local box, size = model:GetBoundingBox()
		top = box.Position + Vector3.new(0, size.Y / 2 + 3, 0)
	end
	local shell = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(top), Color = CRIMSON,
		Material = Enum.Material.ForceField, Transparency = 0.1 })
	local heart = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = CFrame.new(top), Color = VOID, Material = Enum.Material.SmoothPlastic })
	tween(shell, life, { Size = Vector3.one * 10 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	tween(heart, life, { Size = Vector3.one * 6 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	local pull = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 44, CFrame = CFrame.new(top), Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture, e.LightEmission, e.LightInfluence = SPARK, 1, 0
	e.Color = ColorSequence.new(CRIMSON, HOT)
	e.Size = ns(0.3, 1.2)
	e.Lifetime = NumberRange.new(0.7, 0.8)
	e.Speed = NumberRange.new(28, 32)
	e.Shape = Enum.ParticleEmitterShape.Sphere
	e.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.Rate = 70
	e.Parent = pull
	for _, p in ipairs({ shell, heart, pull }) do table.insert(judgementOrb, p) end
	-- (gone anyway if the slam never comes)
	for _, p in ipairs(judgementFx) do Debris:AddItem(p, life + 4) end
	for _, p in ipairs(judgementOrb) do Debris:AddItem(p, life + 1) end
end

JUDGEMENT.strike = function(data)
	local mid: Vector3 = data.pos
	local speed: number = data.speed or 70
	local bounds = data.bounds
	local shade = shadows(mid, data.covers)
	for _, p in ipairs(judgementOrb) do p:Destroy() end
	table.clear(judgementOrb)
	-- The blast where it lands.
	local at = mid + Vector3.new(0, 2, 0)
	orb(at, 3, 30, 0.5, HOT)
	orb(at, 4, 44, 0.9, CRIMSON)
	orb(at, 2, 18, 1.1, VOID, Enum.Material.SmoothPlastic)
	ring(mid + Vector3.new(0, 0.3, 0), 4, 26, 0.5, HOT)
	shards(mid, 16, 14, 10)
	rocks(mid, 16, 50)
	feathers(mid, 14, 20)
	sparks(at, 60, CRIMSON, 70, 1.6)
	smoke(mid, 18, Color3.fromRGB(30, 18, 22), 7)
	flashLight(at + Vector3.new(0, 6, 0), CRIMSON, 60, 7, 0.8)
	shakeNear(mid, 2.4, 0.7, 160)
	-- The wave: out to the room's walls, stopped behind every pillar.
	local reach = 0
	for k = 0, 35 do reach = math.max(reach, edgeDist(mid, k / 36 * TAU, bounds)) end
	-- (the red and the gold stay until the wave has passed)
	task.delay(reach / speed, clearJudgement, 0.5)
	rollingWall(Vector3.new(mid.X, mid.Y, mid.Z), 3, speed, reach, 6, 96, function(a: number): number
		local stop = edgeDist(mid, a, bounds)
		for _, s in ipairs(shade) do
			if angleDiff(a, s.theta) < s.half then stop = math.min(stop, s.dist - s.radius * 0.5) end
		end
		return stop
	end)
	-- Each pillar flares gold as the wave breaks on it.
	for _, s in ipairs(shade) do
		task.delay(math.max(0, s.dist - s.radius) / speed, function()
			local face = s.pos - dirAt(s.theta) * s.radius
			sparks(Vector3.new(face.X, mid.Y + 3, face.Z), 24, GOLD, 26, 1)
			orb(Vector3.new(face.X, mid.Y + 3, face.Z), 2, 9, 0.35, GOLD)
		end)
	end
end

local function onFX(data: any)
	if typeof(data) ~= "table" then return end
	local handler = if data.kind == "angel" then ANGEL[data.move]
		elseif data.kind == "judgement" then JUDGEMENT[data.phase]
		else nil
	if not handler then return end
	local ok, err = pcall(handler, data)
	if not ok then warn("[AngelAttackFX]", data.kind, data.move or data.phase, err) end
end

function AngelAttackFX.Init()
	Network.GetRemoteEvent(Network.Remotes.BossFX).OnClientEvent:Connect(onFX)
	RunService.Heartbeat:Connect(function(dt)
		if #fliers > 0 then stepFliers(dt) end
	end)
end

return AngelAttackFX
