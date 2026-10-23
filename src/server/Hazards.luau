--!strict
--[[
	Hazards.luau
	Dungeon hazards, built with each level (DungeonGenerator) and torn down
	with it.

	  Boss arenas   a field of lava (3 × 2 floor cells, square to the grid, in the
	                quadrant nearest the camera): step in and you're STUCK,
	                sinking and burning, until you beat the quick-time
	                sequence of movement keys or a teammate pulls you out (E,
	                LavaController); flame vents (clear of the doors and
	                the centre), flame vents that erupt on a telegraphed cycle,
	                and broken stone pillars to hide behind.
	  Combat rooms  (about a third of them, and half the elite rooms) traps:
	                spike traps (a grate that glows and rattles, then shoots its
	                spikes up), blade sweepers (a low blade turning round a post:
	                jump it or keep out of its circle), burning traps (an iron
	                fire grate: it glows, then erupts: 25 and a Burn stack every
	                ~0.5 s you stand in it), explosive barrels (come near and the
	                fuse lights, a ring on the floor shows the blast: 2 s later,
	                50 to everyone in it, mobs too) and saw blades (a blade
	                running back and forth along a slot: 50 and a Bleed stack).

	Burn and Bleed on players (Hazards.Afflict): damage every half second
	while they last, flames / blood on the character.

	One server loop checks every player in the run against the live hazards:
	lava traps you, vents and spikes hit once per eruption.
	Dodge i-frames (InvulnerableUntil) are respected.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Hazards = {}

local FLOOR_SIZE = 12

-- (dark molten rock, not flat neon: bright neon pools drowned out the
-- player, the boss and every telegraph)
local LAVA = Color3.fromRGB(215, 72, 20)
local LAVA_DEEP = Color3.fromRGB(150, 36, 12)
local LAVA_GLOW = Color3.fromRGB(235, 74, 14) -- the pools' molten glow, under their crust
local CRUST = Color3.fromRGB(40, 22, 18)
local STONE = Color3.fromRGB(70, 64, 72)
local WARN = Color3.fromRGB(255, 60, 40)

local LAVA_DPS = 20          -- per second while stuck in lava
local VENT_DAMAGE = 30
local SPIKE_DAMAGE = 24
local SWEEP_DAMAGE = 22
local SWEEP_LEN = 8.5     -- the blade's reach from the post
local SWEEP_HEIGHT = 1.1  -- low enough to jump
local BURN_TRAP_DAMAGE = 25
local BURN_TRAP_HALF = 3.2 -- the grate's half width
local BARREL_DAMAGE = 50
local BARREL_FUSE = 2      -- seconds from lit to the blast
local BARREL_TRIGGER = 9   -- studs: this close and the fuse lights
local BARREL_RADIUS = 11
local SAW_DAMAGE = 50
local SAW_TRACK = 18       -- the slot's length
local SAW_RADIUS = 2.4
-- Burn / Bleed: per stack, every TICK seconds, while they last
local TICK = 0.5
local BURN_PER_STACK, BURN_LASTS, BURN_MAX = 2, 3, 6
local BLEED_PER_STACK, BLEED_LASTS, BLEED_MAX = 2.5, 4, 5

type Lava = { kind: "lava", center: Vector3, radius: number, hx: number, hz: number, floorY: number, part: BasePart }
type Vent = { kind: "vent", center: Vector3, radius: number, floorY: number, active: boolean, hit: { [Player]: boolean } }
type Spike = { kind: "spike", center: Vector3, half: number, floorY: number, active: boolean, hit: { [Player]: boolean } }
type Sweep = { kind: "sweep", center: Vector3, radius: number, floorY: number, phase: number, spin: number, last: { [Player]: number } }
type Fire = { kind: "fire", center: Vector3, half: number, floorY: number, active: boolean, hit: { [Player]: boolean }, lastBurn: { [Player]: number } }
type Saw = { kind: "saw", center: Vector3, floorY: number, dir: Vector3, phase: number, speed: number, last: { [Player]: number } }
type Hazard = Lava | Vent | Spike | Sweep | Fire | Saw

local hazards: { any } = {}
-- (each hazard belongs to the run whose dungeon was being built: runs are
-- torn down one at a time)
local buildingRun: string? = nil
function Hazards.SetRun(runId: string?)
	buildingRun = runId
end
local started = false

-- Every moving or glowing bit of a hazard is animated on each client
-- (HazardFX, tag "HazardFX"), not here: a part moved or tweened by the server
-- is sent to every player every frame, and on a poor connection that crowds
-- out what matters. The server only says what state each one is in (the
-- model's "State": rest / warn / active) and, for the ones that turn with the
-- clock, their phase and speed (the shared clock, GetServerTimeNow, so the
-- blade you see is the blade that hits).
local function animated(m: Model, attrs: { [string]: any })
	for k, v in pairs(attrs) do m:SetAttribute(k, v) end
	CollectionService:AddTag(m, "HazardFX")
end

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder lying flat

-- (every hazard's effects show the danger: never stopped by the client's
-- performance mode, PerfMode)
local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	e:SetAttribute("Gameplay", true)
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

-- ── Lava ────────────────────────────────────────────────────────────────────
-- An irregular pool: a few overlapping discs of glowing lava with a dark
-- crust rim, bubbling embers and heat smoke.
-- A field of lava, flush with the floor and square to its grid: a dark rim
-- of rock, the molten glow under a crust of cracked rock (the Infernal
-- Keep's lava, KeepKit.LavaPit), bubbles and heat. `hx`, `hz`: half its size.
local function lavaField(folder: Instance, center: Vector3, hx: number, hz: number)
	local pool = Instance.new("Model")
	pool.Name = "LavaField"
	pool.Parent = folder
	-- the rim
	for _, sd in ipairs({ { 0, 1 }, { 0, -1 }, { 1, 0 }, { -1, 0 } }) do
		local along = sd[1] == 0
		part(pool, { Name = "Rim", Size = if along then Vector3.new(hx * 2 + 2.4, 0.4, 1.2) else Vector3.new(1.2, 0.4, hz * 2 + 2.4),
			CFrame = CFrame.new(center + Vector3.new(sd[1] * (hx + 0.6), 0.2, sd[2] * (hz + 0.6))), Color = CRUST, Material = Enum.Material.Basalt })
	end
	local lava = part(pool, { Name = "Lava", Size = Vector3.new(hx * 2, 0.3, hz * 2), CFrame = CFrame.new(center + Vector3.new(0, 0.05, 0)),
		Color = LAVA_GLOW, Material = Enum.Material.Neon })
	part(pool, { Name = "LavaCrust", Size = Vector3.new(hx * 2, 0.2, hz * 2), CFrame = CFrame.new(center + Vector3.new(0, 0.15, 0)),
		Color = Color3.fromRGB(255, 132, 40), Material = Enum.Material.CrackedLava, Transparency = 0.35 })
	-- a second crust drifting slowly over it, back and forth: the surface flows
	local flow = part(pool, { Name = "LavaFlow",
		CFrame = CFrame.new(center + Vector3.new(-1, 0.27, -0.8)), Size = Vector3.new(hx * 2 - 2.4, 0.1, hz * 2 - 2),
		Color = Color3.fromRGB(255, 170, 70), Material = Enum.Material.CrackedLava, Transparency = 0.6 })
	animated(pool, { Center = center })
	emitter(lava, { Name = "Bubbles", Texture = "rbxasset://textures/particles/sparkles_main.dds", Shape = Enum.ParticleEmitterShape.Box,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), LAVA), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(30, 30),
		Acceleration = Vector3.new(0, -4, 0), Rate = hx * hz / 12 })
	emitter(lava, { Name = "Heat", Texture = "rbxasset://textures/particles/smoke_main.dds", Shape = Enum.ParticleEmitterShape.Box,
		Color = ColorSequence.new(Color3.fromRGB(90, 40, 30), Color3.fromRGB(30, 20, 20)),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 7) }),
		Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(1, 3), Rate = 3 })
	table.insert(hazards, { kind = "lava", center = center, radius = Vector2.new(hx, hz).Magnitude, hx = hx, hz = hz,
		floorY = center.Y, part = lava, runId = buildingRun } :: any)
end

-- ── Flame vents ─────────────────────────────────────────────────────────────
local function flameVent(folder: Instance, center: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "FlameVent"
	m.Parent = folder
	part(m, { Name = "Grate", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 5, 5),
		CFrame = CFrame.new(center + Vector3.new(0, 0.1, 0)) * FLAT, Color = Color3.fromRGB(30, 26, 28), Material = Enum.Material.DiamondPlate })
	local glow = part(m, { Name = "Glow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.32, 3, 3),
		CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)) * FLAT, Color = WARN, Material = Enum.Material.Neon, Transparency = 0.9 })
	local a = Instance.new("Attachment")
	a.Parent = glow
	a.Orientation = Vector3.new(0, 0, 90) -- emit straight up
	local fire = emitter(a, { Name = "Jet", Texture = "rbxasset://textures/particles/fire_main.dds",
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)), ColorSequenceKeypoint.new(0.4, LAVA),
			ColorSequenceKeypoint.new(1, LAVA_DEEP) }), LightEmission = 1,
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 0.5) }),
		Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) }),
		Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(26, 34), SpreadAngle = Vector2.new(8, 8),
		EmissionDirection = Enum.NormalId.Right, Rate = 0 })
	animated(m, { State = "rest" })
	local v: Vent = { kind = "vent", center = center, radius = 3.2, floorY = center.Y, active = false, hit = {} }
	(v :: any).runId = buildingRun
	table.insert(hazards, v :: any)
	-- Cycle: rest → glow warning → eruption.
	task.spawn(function()
		task.wait(rng:NextNumber(0, 4))
		while m.Parent do
			task.wait(3.2)
			if not m.Parent then break end
			m:SetAttribute("State", "warn")
			task.wait(0.8)
			if not m.Parent then break end
			v.hit = {}
			v.active = true
			fire.Rate = 90
			m:SetAttribute("State", "active")
			task.wait(1.1)
			v.active = false
			fire.Rate = 0
			m:SetAttribute("State", "rest")
		end
	end)
end

-- ── Spike traps ─────────────────────────────────────────────────────────────
local function spikeTrap(folder: Instance, center: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "SpikeTrap"
	m.Parent = folder
	local SIZE = 7
	part(m, { Name = "Plate", Size = Vector3.new(SIZE, 0.3, SIZE), CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)),
		Color = Color3.fromRGB(46, 42, 46), Material = Enum.Material.DiamondPlate })
	local warn = part(m, { Name = "Warn", Size = Vector3.new(SIZE - 0.6, 0.32, SIZE - 0.6), CFrame = CFrame.new(center + Vector3.new(0, 0.13, 0)),
		Color = WARN, Material = Enum.Material.Neon, Transparency = 1 })
	for x = -1, 1 do
		for z = -1, 1 do
			local base = center + Vector3.new(x * 2.1, 0, z * 2.1)
			part(m, { Name = "Spike", Size = Vector3.new(0.7, 2.6, 0.7), CFrame = CFrame.new(base + Vector3.new(0, -1.4, 0)),
				Color = Color3.fromRGB(190, 190, 200), Material = Enum.Material.Metal })
		end
	end
	animated(m, { State = "rest" })
	local t: Spike = { kind = "spike", center = center, half = SIZE / 2, floorY = center.Y, active = false, hit = {} }
	(t :: any).runId = buildingRun
	table.insert(hazards, t :: any)
	task.spawn(function()
		task.wait(rng:NextNumber(0, 3))
		while m.Parent do
			task.wait(2.6)
			if not m.Parent then break end
			m:SetAttribute("State", "warn")
			task.wait(0.65)
			if not m.Parent then break end
			t.hit = {}
			t.active = true
			m:SetAttribute("State", "active")
			task.wait(0.9)
			t.active = false
			m:SetAttribute("State", "rest")
		end
	end)
end

-- ── Blade sweepers ──────────────────────────────────────────────────────────
-- An iron post with a long blade arm turning low over the floor: a red
-- stripe runs along its edge. Jump it, or keep out of its circle. Its angle
-- is a pure function of the clock (`phase + spin * t`), so the damage loop
-- needs no state from the part.
local function sweeper(folder: Instance, center: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "BladeSweeper"
	m.Parent = folder
	local len = SWEEP_LEN
	part(m, { Name = "Base", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, len * 2 + 1, len * 2 + 1),
		CFrame = CFrame.new(center + Vector3.new(0, 0.08, 0)) * FLAT, Color = Color3.fromRGB(34, 30, 34),
		Material = Enum.Material.Slate, Transparency = 0.35 })
	local post = part(m, { Name = "Post", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3, 1.6, 1.6),
		CFrame = CFrame.new(center + Vector3.new(0, 1.5, 0)) * FLAT, Color = Color3.fromRGB(60, 58, 66), Material = Enum.Material.Metal })
	post.CanCollide = true
	part(m, { Name = "Blade", Size = Vector3.new(len, 0.5, 1.1), Color = Color3.fromRGB(170, 170, 180), Material = Enum.Material.Metal,
		CFrame = CFrame.new(center + Vector3.new(len / 2 + 0.6, SWEEP_HEIGHT, 0)) })
	part(m, { Name = "Edge", Size = Vector3.new(len, 0.2, 0.15), Color = WARN, Material = Enum.Material.Neon,
		CFrame = CFrame.new(center + Vector3.new(len / 2 + 0.6, SWEEP_HEIGHT, 0)) })
	local sweep: Sweep = { kind = "sweep", center = center, radius = len + 0.5, floorY = center.Y,
		phase = rng:NextNumber(0, math.pi * 2), spin = (if rng:NextNumber() < 0.5 then -1 else 1) * rng:NextNumber(1.3, 1.9),
		last = {} }
	(sweep :: any).runId = buildingRun
	table.insert(hazards, sweep :: any)
	animated(m, { Center = center + Vector3.new(0, SWEEP_HEIGHT, 0), Phase = sweep.phase, Spin = sweep.spin, Length = len })
end

-- ── Burning traps ───────────────────────────────────────────────────────────
-- A square iron fire grate set in the floor, coals glowing in the pit under
-- it. Every few seconds it glows (the warning), then flames roar up out of
-- it: caught in them, 25 at once, and a Burn stack every ~0.5 s you stay.
local function burningTrap(folder: Instance, center: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "BurningTrap"
	m.Parent = folder
	local S = BURN_TRAP_HALF * 2
	local IRON = Color3.fromRGB(38, 32, 34)
	part(m, { Name = "Frame", Size = Vector3.new(S + 1.2, 0.35, S + 1.2), CFrame = CFrame.new(center + Vector3.new(0, 0.12, 0)),
		Color = IRON, Material = Enum.Material.Metal })
	local pit = part(m, { Name = "Coals", Size = Vector3.new(S, 0.36, S), CFrame = CFrame.new(center + Vector3.new(0, 0.14, 0)),
		Color = Color3.fromRGB(120, 28, 8), Material = Enum.Material.Neon })
	-- the grate bars over it
	for k = -2, 2 do
		part(m, { Name = "Bar", Size = Vector3.new(S, 0.25, 0.35), CFrame = CFrame.new(center + Vector3.new(0, 0.36, k * S / 5)),
			Color = IRON, Material = Enum.Material.Metal })
		part(m, { Name = "Bar", Size = Vector3.new(0.35, 0.25, S), CFrame = CFrame.new(center + Vector3.new(k * S / 5, 0.36, 0)),
			Color = IRON, Material = Enum.Material.Metal })
	end
	-- bolts at the corners
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		part(m, { Name = "Bolt", Size = Vector3.new(1, 0.5, 1), CFrame = CFrame.new(center + Vector3.new(c[1] * (S / 2 + 0.2), 0.3, c[2] * (S / 2 + 0.2))),
			Color = Color3.fromRGB(70, 60, 58), Material = Enum.Material.Metal })
	end
	local flames = emitter(pit, {
		Texture = "rbxasset://textures/particles/fire_main.dds", LightEmission = 1, Rate = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 70, 20)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 1) }),
		Transparency = NumberSequence.new(0.1, 1), Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(10, 16),
		SpreadAngle = Vector2.new(10, 10), Acceleration = Vector3.new(0, 6, 0), Shape = Enum.ParticleEmitterShape.Box,
	})
	local smoulder = emitter(pit, {
		Texture = "rbxasset://textures/particles/fire_main.dds", LightEmission = 1, Rate = 6,
		Color = ColorSequence.new(Color3.fromRGB(255, 120, 40)), Size = NumberSequence.new(0.8, 0.2),
		Transparency = NumberSequence.new(0.4, 1), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1, 2),
		Shape = Enum.ParticleEmitterShape.Box,
	})
	animated(m, { State = "rest" })
	local t: Fire = { kind = "fire", center = center, half = BURN_TRAP_HALF, floorY = center.Y, active = false, hit = {}, lastBurn = {} }
	(t :: any).runId = buildingRun
	table.insert(hazards, t :: any)
	task.spawn(function()
		task.wait(rng:NextNumber(0, 3))
		while m.Parent do
			task.wait(2.8)
			if not m.Parent then break end
			-- the warning: the coals flare
			m:SetAttribute("State", "warn")
			smoulder.Rate = 30
			task.wait(0.7)
			if not m.Parent then break end
			t.hit = {}
			t.active = true
			flames.Rate = 90
			m:SetAttribute("State", "active")
			task.wait(1.6)
			t.active = false
			flames.Rate = 0
			smoulder.Rate = 6
			m:SetAttribute("State", "rest")
		end
	end)
end

-- ── Explosive barrels ───────────────────────────────────────────────────────
-- A squat red barrel, iron-banded, light leaking through the slits in its
-- bands. Come within BARREL_TRIGGER and its fuse lights: it blinks and
-- hisses while a ring of warning spreads on the floor to the blast's edge,
-- then after BARREL_FUSE it blows: 50 to every player inside (the dash's
-- i-frames dodge it) and to every mob too.
local function explosiveBarrel(folder: Instance, center: Vector3)
	local m = Instance.new("Model")
	m.Name = "ExplosiveBarrel"
	m.Parent = folder
	local body = part(m, { Name = "Body", Shape = Enum.PartType.Cylinder, Size = Vector3.new(3.2, 2.6, 2.6),
		CFrame = CFrame.new(center + Vector3.new(0, 1.6, 0)) * FLAT, Color = Color3.fromRGB(120, 22, 18), Material = Enum.Material.Wood })
	body.CanCollide = true
	animated(m, { Fuse = BARREL_FUSE, Radius = BARREL_RADIUS })
	for _, y in ipairs({ 0.55, 2.65 }) do
		part(m, { Name = "Band", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.45, 2.75, 2.75),
			CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * FLAT, Color = Color3.fromRGB(40, 34, 34), Material = Enum.Material.Metal })
		part(m, { Name = "Slit", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 2.8, 2.8),
			CFrame = CFrame.new(center + Vector3.new(0, y, 0)) * FLAT, Color = Color3.fromRGB(255, 110, 30), Material = Enum.Material.Neon })
	end
	part(m, { Name = "Lid", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.3, 2.3),
		CFrame = CFrame.new(center + Vector3.new(0, 3.25, 0)) * FLAT, Color = Color3.fromRGB(160, 40, 30), Material = Enum.Material.Metal })
	local fuse = part(m, { Name = "Fuse", Size = Vector3.new(0.2, 0.9, 0.2), CFrame = CFrame.new(center + Vector3.new(0.5, 3.8, 0)),
		Color = Color3.fromRGB(60, 50, 40), Material = Enum.Material.Fabric })
	local sparks = emitter(fuse, {
		Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 1, Rate = 0,
		Color = ColorSequence.new(Color3.fromRGB(255, 220, 120)), Size = NumberSequence.new(0.4, 0),
		Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(4, 8), SpreadAngle = Vector2.new(60, 60),
	})
	local runId = buildingRun
	local lit = false
	local function blow()
		local at = center + Vector3.new(0, 1.6, 0)
		local boom = Instance.new("Explosion")
		boom.Position = at
		boom.BlastRadius = BARREL_RADIUS
		boom.BlastPressure = 0
		boom.DestroyJointRadiusPercent = 0
		boom.ExplosionType = Enum.ExplosionType.NoCraters
		boom.Parent = workspace
		local now = os.clock()
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if plr:GetAttribute("InLobby") ~= false or not (root and hum) or hum.Health <= 0 then continue end
			if (char:GetAttribute("InvulnerableUntil") or 0) > now then continue end
			if (root.Position - at).Magnitude <= BARREL_RADIUS then
				hum:TakeDamage(BARREL_DAMAGE)
				root.AssemblyLinearVelocity += ((root.Position - at) * Vector3.new(1, 0, 1)).Unit * 40 + Vector3.new(0, 30, 0)
			end
		end
		-- and the mobs round it
		local mobs = workspace:FindFirstChild("Mobs")
		if mobs then
			for _, mob in ipairs(mobs:GetChildren()) do
				local hum = mob:FindFirstChildOfClass("Humanoid")
				local r = mob:FindFirstChild("HumanoidRootPart") :: BasePart?
				if hum and r and hum.Health > 0 and (r.Position - at).Magnitude <= BARREL_RADIUS and mob:GetAttribute("IsBoss") ~= true then
					hum:TakeDamage(BARREL_DAMAGE * 2)
				end
			end
		end
		m:Destroy()
	end
	local watch: RBXScriptConnection
	watch = RunService.Heartbeat:Connect(function()
		if not m.Parent then
			watch:Disconnect()
			return
		end
		if lit then return end
		for _, plr in ipairs(Players:GetPlayers()) do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and plr:GetAttribute("InLobby") == false and plr:GetAttribute("RunId") == runId
				and (root.Position - center).Magnitude <= BARREL_TRIGGER then
				lit = true
				break
			end
		end
		if not lit then return end
		watch:Disconnect()
		sparks.Rate = 40
		-- the warning ring spreading to the blast's edge, the blinking: the
		-- client's (HazardFX), from when it was lit
		part(m, { Name = "Warning", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, BARREL_RADIUS * 2, BARREL_RADIUS * 2),
			CFrame = CFrame.new(center + Vector3.new(0, 0.18, 0)) * FLAT, Color = Color3.fromRGB(255, 40, 30),
			Material = Enum.Material.Neon, Transparency = 0.45 })
		m:SetAttribute("LitAt", workspace:GetServerTimeNow())
		task.delay(BARREL_FUSE, function()
			if m.Parent then blow() end
		end)
	end)
end

-- ── Saw blades ──────────────────────────────────────────────────────────────
-- A slot cut in the floor, iron rails along it, and a toothed blade standing
-- up out of it, spinning as it runs back and forth: 50 and a Bleed stack.
local function sawBlade(folder: Instance, center: Vector3, rng: Random)
	local m = Instance.new("Model")
	m.Name = "SawBlade"
	m.Parent = folder
	local yaw = rng:NextInteger(0, 1) * math.pi / 2
	local dir = (CFrame.Angles(0, yaw, 0) * Vector3.new(1, 0, 0))
	local base = CFrame.new(center) * CFrame.Angles(0, yaw, 0)
	part(m, { Name = "Slot", Size = Vector3.new(SAW_TRACK + 1, 0.3, 1.4), CFrame = base * CFrame.new(0, 0.12, 0),
		Color = Color3.fromRGB(14, 10, 12), Material = Enum.Material.Slate })
	for _, sz in ipairs({ -1, 1 }) do
		part(m, { Name = "Rail", Size = Vector3.new(SAW_TRACK + 1.6, 0.35, 0.4), CFrame = base * CFrame.new(0, 0.2, sz * 0.9),
			Color = Color3.fromRGB(60, 54, 56), Material = Enum.Material.Metal })
	end
	-- a red glow along the slot (where the blade runs)
	part(m, { Name = "Glow", Size = Vector3.new(SAW_TRACK, 0.32, 0.5), CFrame = base * CFrame.new(0, 0.13, 0),
		Color = Color3.fromRGB(200, 30, 20), Material = Enum.Material.Neon, Transparency = 0.3 })
	-- the blade: a steel disc, two square plates turned 45° for its teeth, a red hub
	local disc = part(m, { Name = "Disc", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, SAW_RADIUS * 2 - 0.4, SAW_RADIUS * 2 - 0.4),
		Color = Color3.fromRGB(170, 170, 178), Material = Enum.Material.Metal })
	local teethA = part(m, { Name = "Teeth", Size = Vector3.new(0.18, SAW_RADIUS * 1.42, SAW_RADIUS * 1.42), Color = Color3.fromRGB(120, 116, 122), Material = Enum.Material.Metal })
	local teethB = part(m, { Name = "Teeth", Size = Vector3.new(0.18, SAW_RADIUS * 1.42, SAW_RADIUS * 1.42), Color = Color3.fromRGB(120, 116, 122), Material = Enum.Material.Metal })
	local hub = part(m, { Name = "Hub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 0.9, 0.9), Color = Color3.fromRGB(200, 30, 20), Material = Enum.Material.Neon })
	-- sparks where the teeth bite the slot, thrown up and back against its run
	local grind = part(m, { Name = "Grind", Size = Vector3.new(0.4, 0.4, 0.4), Transparency = 1 })
	local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
	-- streaks: long bright sparks stretched along their flight, a fountain of them
	emitter(grind, {
		Name = "Sparks", Texture = SPARK, LightEmission = 1, Rate = 140, Orientation = Enum.ParticleOrientation.VelocityParallel,
		Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 230)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 200, 90)), ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 20)) }),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 0.1) }),
		Squash = NumberSequence.new(-1.6), -- (stretched into streaks)
		Lifetime = NumberRange.new(0.35, 0.7), Speed = NumberRange.new(22, 38), SpreadAngle = Vector2.new(35, 22),
		Acceleration = Vector3.new(0, -60, 0), Drag = 1.2, EmissionDirection = Enum.NormalId.Front,
	})
	-- embers: slower fat sparks that fall and bounce off the floor glowing
	emitter(grind, {
		Name = "Embers", Texture = SPARK, LightEmission = 1, Rate = 40,
		Color = ColorSequence.new(Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 60, 10)),
		Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) }),
		Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(8, 16), SpreadAngle = Vector2.new(70, 50),
		Acceleration = Vector3.new(0, -40, 0), EmissionDirection = Enum.NormalId.Front,
	})
	-- the bite itself: a white-hot flare and a glowing ball of heat
	emitter(grind, {
		Texture = SPARK, LightEmission = 1, Rate = 40,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 160)), Size = NumberSequence.new(2.4, 0),
		Lifetime = NumberRange.new(0.06, 0.12), Speed = NumberRange.new(0, 0), Transparency = NumberSequence.new(0.1, 1),
	})
	local heat = part(m, { Name = "Heat", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.1, Color = Color3.fromRGB(255, 150, 40),
		Material = Enum.Material.Neon, Transparency = 0.25 })
	local saw: Saw = { kind = "saw", center = center, floorY = center.Y, dir = dir, phase = rng:NextNumber(0, math.pi * 2),
		speed = rng:NextNumber(0.9, 1.3), last = {} }
	(saw :: any).runId = buildingRun
	table.insert(hazards, saw :: any)
	-- (where it is at rest, until the client takes it over)
	local cf = base * CFrame.new(0, SAW_RADIUS * 0.55, 0) * CFrame.Angles(0, math.pi / 2, 0)
	disc.CFrame, teethA.CFrame, hub.CFrame = cf, cf, cf
	teethB.CFrame = cf * CFrame.Angles(math.rad(45), 0, 0)
	grind.CFrame = base * CFrame.new(0, 0.35, 0)
	heat.CFrame = grind.CFrame
	animated(m, { Yaw = yaw, Center = center, Phase = saw.phase, Speed = saw.speed,
		Reach = SAW_TRACK / 2 - SAW_RADIUS * 0.6, Radius = SAW_RADIUS })
end

-- ── Burn and Bleed ──────────────────────────────────────────────────────────
-- Stacks on a player, each dealing its share every TICK while it lasts (a
-- new Burn stack keeps them all burning; Bleed stacks run out one by one).
type Affliction = { burn: number, burnUntil: number, bleeds: { number }, nextTick: number }
local afflicted: { [Player]: Affliction } = {}

local function afflictionFx(char: Model, name: string, on: boolean, kind: string)
	local root = char:FindFirstChild("HumanoidRootPart")
	if not root then return end
	local fx = root:FindFirstChild(name) :: ParticleEmitter?
	if on and not fx then
		if kind == "burn" then
			emitter(root, { Name = name, Texture = "rbxasset://textures/particles/fire_main.dds", LightEmission = 1, Rate = 22,
				Color = ColorSequence.new(Color3.fromRGB(255, 200, 100), Color3.fromRGB(255, 70, 20)),
				Size = NumberSequence.new(1.6, 0.3), Transparency = NumberSequence.new(0.2, 1), Lifetime = NumberRange.new(0.4, 0.7),
				Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 6, 0), Shape = Enum.ParticleEmitterShape.Box })
		else
			emitter(root, { Name = name, Texture = "rbxasset://textures/particles/sparkles_main.dds", LightEmission = 0, Rate = 14,
				Color = ColorSequence.new(Color3.fromRGB(170, 10, 16)), Size = NumberSequence.new(0.35, 0.15),
				Lifetime = NumberRange.new(0.5, 0.8), Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, -30, 0),
				SpreadAngle = Vector2.new(60, 60) })
		end
	elseif not on and fx then
		fx:Destroy()
	end
end

-- Add `n` stacks of "burn" or "bleed" to a player (attributes Burn / Bleed:
-- the stacks, for the HUD).
function Hazards.Afflict(plr: Player, kind: string, n: number?)
	local a = afflicted[plr]
	if not a then
		a = { burn = 0, burnUntil = 0, bleeds = {}, nextTick = os.clock() + TICK }
		afflicted[plr] = a
	end
	local now = os.clock()
	for _ = 1, n or 1 do
		if kind == "burn" then
			a.burn = math.min(BURN_MAX, a.burn + 1)
			a.burnUntil = now + BURN_LASTS
		elseif #a.bleeds < BLEED_MAX then
			table.insert(a.bleeds, now + BLEED_LASTS)
		end
	end
end

local function tickAfflictions(now: number)
	for plr, a in pairs(afflicted) do
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not plr.Parent or not char or not hum or hum.Health <= 0 or plr:GetAttribute("InLobby") ~= false then
			if char then
				afflictionFx(char, "HazardBurn", false, "burn")
				afflictionFx(char, "HazardBleed", false, "bleed")
			end
			plr:SetAttribute("Burn", nil)
			plr:SetAttribute("Bleed", nil)
			afflicted[plr] = nil
			continue
		end
		if now < a.nextTick then continue end
		a.nextTick = now + TICK
		if a.burnUntil <= now then a.burn = 0 end
		for i = #a.bleeds, 1, -1 do
			if a.bleeds[i] <= now then table.remove(a.bleeds, i) end
		end
		local dmg = a.burn * BURN_PER_STACK + #a.bleeds * BLEED_PER_STACK
		if dmg > 0 then hum:TakeDamage(dmg) end
		plr:SetAttribute("Burn", if a.burn > 0 then a.burn else nil)
		plr:SetAttribute("Bleed", if #a.bleeds > 0 then #a.bleeds else nil)
		afflictionFx(char, "HazardBurn", a.burn > 0, "burn")
		afflictionFx(char, "HazardBleed", #a.bleeds > 0, "bleed")
		if a.burn == 0 and #a.bleeds == 0 then afflicted[plr] = nil end
	end
end

-- ── Pillars (cover) ─────────────────────────────────────────────────────────
local function pillar(folder: Instance, center: Vector3, rng: Random)
	local h = rng:NextNumber(6, 10) -- broken stumps: low enough for the dragon's wings to pass over
	local p = part(folder, { Name = "ArenaPillar", Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, 5, 5),
		CFrame = CFrame.new(center + Vector3.new(0, h / 2, 0)) * FLAT, Color = STONE, Material = Enum.Material.Slate })
	p.CanCollide = true
	p.CanQuery = true
	part(folder, { Name = "PillarBase", Size = Vector3.new(6.4, 1.2, 6.4), CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0)),
		Color = Color3.fromRGB(56, 50, 58), Material = Enum.Material.Slate, CanCollide = true })
	-- A broken, tilted cap.
	part(folder, { Name = "PillarCap", Size = Vector3.new(5.6, 1, 5.6),
		CFrame = CFrame.new(center + Vector3.new(0, h + 0.3, 0)) * CFrame.Angles(math.rad(rng:NextNumber(-12, 12)), 0, math.rad(rng:NextNumber(-12, 12))),
		Color = Color3.fromRGB(56, 50, 58), Material = Enum.Material.Slate, CanCollide = true })
end

type Room = { gx: number, gz: number, w: number, d: number, floorY: number }

local function bounds(room: Room)
	local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE / 2
	local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE / 2
	local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE / 2
	local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE / 2
	return minX, maxX, minZ, maxZ
end

-- The boss arena: a lava field, vents on the cross, pillars for cover.
function Hazards.BuildBossArena(room: Room, folder: Instance, rng: Random)
	local minX, maxX, minZ, maxZ = bounds(room)
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local hx, hz = (maxX - minX) / 2, (maxZ - minZ) / 2
	local y = room.floorY
	local f = Instance.new("Folder")
	f.Name = "ArenaHazards"
	f.Parent = folder
	-- Lava: one field, 3 cells by 2, in the quadrant toward the camera (-X,
	-- +Z: the bottom left of the screen, in full view; the exit gate is on
	-- the far walls), clear of the centre, the doors and the pillars; its
	-- edges on the floor's tile edges.
	do
		local lhx, lhz = FLOOR_SIZE * 1.5, FLOOR_SIZE
		local x = cx - hx * 0.58
		local z = cz + hz * 0.58
		x = math.floor(x / FLOOR_SIZE + 0.5) * FLOOR_SIZE                         -- (3 wide: on a cell's middle)
		z = math.floor((z - FLOOR_SIZE / 2) / FLOOR_SIZE + 0.5) * FLOOR_SIZE + FLOOR_SIZE / 2 -- (2 deep: on a cell's edge)
		lavaField(f, Vector3.new(x, y, z), lhx, lhz)
	end
	-- Vents on the cross between the centre and the walls.
	for _, q in ipairs({ { 0, -1 }, { 0, 1 }, { -1, 0 }, { 1, 0 } }) do
		flameVent(f, Vector3.new(cx + q[1] * hx * 0.42, y, cz + q[2] * hz * 0.42), rng)
	end
	-- Pillars between vents and lava (cover from breath and beams).
	for _, q in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		pillar(f, Vector3.new(cx + q[1] * hx * 0.26, y, cz + q[2] * hz * 0.26), rng)
	end
end

-- Is `pos` within `pad` studs of a lava pool or a flame vent on its floor?
-- (BossAI keeps the Fallen Angel's Judgement pillars off them.)
function Hazards.Near(pos: Vector3, pad: number): boolean
	for _, h in ipairs(hazards) do
		if (h.kind == "lava" or h.kind == "vent") and math.abs(pos.Y - h.floorY) < 6 then
			if Vector3.new(pos.X - h.center.X, 0, pos.Z - h.center.Z).Magnitude <= h.radius + pad then return true end
		end
	end
	return false
end

-- A few traps scattered on a combat room's open floor (`blocked`: spots to
-- keep off, { minX, maxX, minZ, maxZ }: the Infernal Keep's lava pits).
function Hazards.BuildTraps(room: Room, folder: Instance, rng: Random, blocked: { { number } }?)
	local minX, maxX, minZ, maxZ = bounds(room)
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local f = Instance.new("Folder")
	f.Name = "Traps"
	f.Parent = folder
	-- The room's theme: spikes, blades, fire, saws, barrels, or a mix.
	local spikes, blades, fires, saws, barrels = 0, 0, 0, 0, 0
	local theme = rng:NextInteger(1, 6)
	if theme == 1 then
		spikes = rng:NextInteger(3, 5)
	elseif theme == 2 then
		blades = rng:NextInteger(2, 3)
	elseif theme == 3 then
		fires = rng:NextInteger(3, 5)
	elseif theme == 4 then
		saws = rng:NextInteger(2, 3)
	elseif theme == 5 then
		barrels = rng:NextInteger(3, 5)
	else
		fires, saws, barrels = rng:NextInteger(1, 2), 1, rng:NextInteger(1, 2)
	end
	local placed: { Vector3 } = {}
	local function place(gap: number, margin: number): Vector3?
		for _ = 1, 40 do
			local p = Vector3.new(rng:NextNumber(minX + margin, maxX - margin), room.floorY, rng:NextNumber(minZ + margin, maxZ - margin))
			-- Keep clear of the centre (the reward), of each other and of the blocked spots.
			local ok = (Vector3.new(p.X - cx, 0, p.Z - cz)).Magnitude > 12 + gap / 2
			for _, o in ipairs(placed) do
				if (p - o).Magnitude < gap then ok = false end
			end
			for _, b in ipairs(blocked or {}) do
				if p.X > b[1] - gap / 2 and p.X < b[2] + gap / 2 and p.Z > b[3] - gap / 2 and p.Z < b[4] + gap / 2 then ok = false end
			end
			if ok then
				table.insert(placed, p)
				return p
			end
		end
		return nil
	end
	for _ = 1, blades do
		local p = place(SWEEP_LEN * 2 + 4, SWEEP_LEN + 6)
		if p then sweeper(f, p, rng) end
	end
	for _ = 1, spikes do
		local p = place(10, 14)
		if p then spikeTrap(f, p, rng) end
	end
	for _ = 1, saws do
		local p = place(SAW_TRACK + 4, SAW_TRACK / 2 + 6)
		if p then sawBlade(f, p, rng) end
	end
	for _ = 1, fires do
		local p = place(11, 12)
		if p then burningTrap(f, p, rng) end
	end
	for _ = 1, barrels do
		local p = place(BARREL_RADIUS + 4, 10)
		if p then explosiveBarrel(f, p) end
	end
end

-- One of each new trap round `at` (Studio: DevHooks "traps"), for a look.
function Hazards.Showcase(at: Vector3, folder: Instance, runId: string?)
	local prev = buildingRun
	buildingRun = runId
	local rng = Random.new()
	local f = Instance.new("Folder")
	f.Name = "TrapShowcase"
	f.Parent = folder
	burningTrap(f, at + Vector3.new(14, 0, 0), rng)
	sawBlade(f, at + Vector3.new(-16, 0, 0), rng)
	explosiveBarrel(f, at + Vector3.new(0, 0, 18))
	buildingRun = prev
end

-- ── Stuck in lava ────────────────────────────────────────────────────────────
-- Stepping into a lava field: you're held there sunk to the waist, burning
-- (LAVA_DPS), until you beat the quick-time sequence (the client's
-- LavaController sends LavaEscape) or a teammate within HELP_RANGE presses E
-- on you (LavaHelp). Out, you're thrown onto the nearest edge, and the lava
-- leaves you be for a moment. The character carries "LavaStuck" meanwhile.
local HELP_RANGE = 12
local SINK = 2.2 -- (in to the waist: the legs under the surface, torso, raised arms and head out)
type Stuck = { lava: Lava, char: Model, since: number }
local stuck: { [Player]: Stuck } = {}
local lavaSafe: { [Player]: number } = {}

local function release(plr: Player, how: string)
	local st = stuck[plr]
	stuck[plr] = nil
	if not st then return end
	local char = st.char
	char:SetAttribute("LavaStuck", nil)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or not char.Parent then return end
	local now = os.clock()
	lavaSafe[plr] = now + 1.6
	char:SetAttribute("InvulnerableUntil", math.max(char:GetAttribute("InvulnerableUntil") or 0, now + 0.6))
	-- onto the nearest edge, a little past the rim
	local h = st.lava
	local rel = root.Position - h.center
	local ex, ez = h.hx - math.abs(rel.X), h.hz - math.abs(rel.Z)
	local out = if ex < ez then Vector3.new(math.sign(rel.X) * (h.hx + 3) - rel.X, 0, 0) else Vector3.new(0, 0, math.sign(rel.Z) * (h.hz + 3) - rel.Z)
	if out.Magnitude < 0.1 then out = Vector3.new(h.hx + 3, 0, 0) end
	local to = Vector3.new(root.Position.X, h.floorY + 3, root.Position.Z) + out
	root.CFrame = CFrame.new(to) * root.CFrame.Rotation
	root.Anchored = false
	root.AssemblyLinearVelocity = out.Unit * 20 + Vector3.new(0, 30, 0)
	char:SetAttribute("LavaFreedBy", how) -- (clients: the splash out, LavaController)
end

local function holdStuck(plr: Player, st: Stuck, dt: number)
	local char = st.char
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if plr.Character ~= char or not root or not hum or hum.Health <= 0 or plr:GetAttribute("InLobby") ~= false then
		stuck[plr] = nil
		-- (fell in it: revived where they fell, they get a moment to walk out)
		lavaSafe[plr] = os.clock() + 8
		char:SetAttribute("LavaStuck", nil)
		if root and root.Parent then root.Anchored = false end
		return
	end
	-- (something else let go of it: a tome choice ending unanchors everyone)
	if not root.Anchored then root.Anchored = true end
	hum:TakeDamage(LAVA_DPS * dt)
end

-- ── The damage loop ─────────────────────────────────────────────────────────
local function step(dt: number)
	local now = os.clock()
	local clock = workspace:GetServerTimeNow() -- (what the clients turn the blades by: HazardFX)
	tickAfflictions(now)
	for plr, st in pairs(stuck) do holdStuck(plr, st, dt) end
	for i = #hazards, 1, -1 do
		local h = hazards[i]
		if h.kind == "lava" and not h.part.Parent then table.remove(hazards, i) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("InLobby") ~= false then continue end
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (char and root and hum) or hum.Health <= 0 then continue end
		if (char:GetAttribute("InvulnerableUntil") or 0) > now then continue end
		local pos = root.Position
		for _, h in ipairs(hazards) do
			if math.abs(pos.Y - (h.floorY + 3)) > 3.5 then continue end
			local flat = Vector3.new(pos.X - h.center.X, 0, pos.Z - h.center.Z)
			if h.kind == "lava" then
				-- in: stuck (sunk to the knees, held, burning: holdStuck)
				if not stuck[plr] and (lavaSafe[plr] or 0) < now and math.abs(flat.X) <= h.hx and math.abs(flat.Z) <= h.hz then
					stuck[plr] = { lava = h, char = char, since = now }
					root.AssemblyLinearVelocity = Vector3.zero
					root.Anchored = true
					root.CFrame = CFrame.new(pos.X, h.floorY + 3 - SINK, pos.Z) * root.CFrame.Rotation
					char:SetAttribute("LavaStuck", true)
				end
			elseif h.kind == "vent" then
				if h.active and not h.hit[plr] and flat.Magnitude <= h.radius then
					h.hit[plr] = true
					hum:TakeDamage(VENT_DAMAGE)
					root.AssemblyLinearVelocity += Vector3.new(0, 38, 0)
				end
			elseif h.kind == "sweep" then
				local d = flat.Magnitude
				if d <= h.radius and d >= 0.8 and pos.Y - h.floorY < 4.6 and now - (h.last[plr] or 0) > 0.8 then
					-- The blade's direction now vs. yours from the post.
					local a = h.phase + h.spin * clock
					local blade = Vector3.new(math.cos(a), 0, -math.sin(a))
					local u = flat / d
					local side = blade:Cross(u).Y
					local ahead = blade:Dot(u)
					if ahead > 0 and math.abs(side) * d <= 1.6 then
						h.last[plr] = now
						hum:TakeDamage(SWEEP_DAMAGE)
						-- knocked along the way it's turning
						local push = Vector3.new(0, 1, 0):Cross(blade) * math.sign(h.spin)
						root.AssemblyLinearVelocity = push * 40 + Vector3.new(0, 18, 0)
					end
				end
			elseif h.kind == "spike" then
				if h.active and not h.hit[plr] and math.abs(flat.X) <= h.half and math.abs(flat.Z) <= h.half then
					h.hit[plr] = true
					hum:TakeDamage(SPIKE_DAMAGE)
				end
			elseif h.kind == "fire" then
				if h.active and math.abs(flat.X) <= h.half + 0.5 and math.abs(flat.Z) <= h.half + 0.5 then
					if not h.hit[plr] then
						h.hit[plr] = true
						hum:TakeDamage(BURN_TRAP_DAMAGE)
					end
					if now - (h.lastBurn[plr] or 0) >= 0.5 then
						h.lastBurn[plr] = now
						Hazards.Afflict(plr, "burn")
					end
				end
			elseif h.kind == "saw" then
				local along = math.sin(h.phase + h.speed * clock) * (SAW_TRACK / 2 - SAW_RADIUS * 0.6)
				local blade = h.center + h.dir * along
				local off = Vector3.new(pos.X - blade.X, 0, pos.Z - blade.Z)
				if off.Magnitude <= SAW_RADIUS + 0.4 and pos.Y - h.floorY < 5 and now - (h.last[plr] or 0) > 0.9 then
					h.last[plr] = now
					hum:TakeDamage(SAW_DAMAGE)
					Hazards.Afflict(plr, "bleed")
					local push = if off.Magnitude > 0.1 then off.Unit else Vector3.new(1, 0, 0)
					root.AssemblyLinearVelocity = push * 34 + Vector3.new(0, 16, 0)
				end
			end
		end
	end
end

-- Forget a run's hazards (a new level replaces them), or every run's.
function Hazards.Clear(runId: string?)
	if not runId then
		table.clear(hazards)
		return
	end
	for i = #hazards, 1, -1 do
		if hazards[i].runId == runId then table.remove(hazards, i) end
	end
end

function Hazards.Init()
	if started then return end
	started = true
	RunService.Heartbeat:Connect(step)
	-- out of the lava: the quick-time sequence beaten (not the instant it caught you)
	Network.GetRemoteEvent(Network.Remotes.LavaEscape).OnServerEvent:Connect(function(plr: Player)
		local st = stuck[plr]
		if st and os.clock() - st.since >= 0.8 then release(plr, "self") end
	end)
	-- or pulled out by a teammate beside you
	Network.GetRemoteEvent(Network.Remotes.LavaHelp).OnServerEvent:Connect(function(helper: Player, userId: any)
		local target = if typeof(userId) == "number" then Players:GetPlayerByUserId(userId) else nil
		if not target or target == helper or not stuck[target] or stuck[helper] then return end
		if helper:GetAttribute("RunId") ~= target:GetAttribute("RunId") or helper:GetAttribute("InLobby") ~= false then return end
		local a = helper.Character and helper.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local b = target.Character and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = helper.Character and helper.Character:FindFirstChildOfClass("Humanoid")
		if not (a and b and hum) or hum.Health <= 0 then return end
		if (Vector3.new(a.Position.X - b.Position.X, 0, a.Position.Z - b.Position.Z)).Magnitude > HELP_RANGE + 3 then return end
		release(target, "help")
	end)
	Players.PlayerRemoving:Connect(function(p)
		stuck[p] = nil
		lavaSafe[p] = nil
	end)
end

return Hazards
