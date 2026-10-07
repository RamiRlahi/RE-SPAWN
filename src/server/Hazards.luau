--!strict
--[[
	Hazards.luau
	Dungeon hazards, built with each level (DungeonGenerator) and torn down
	with it.

	  Boss arenas   lava pools in the four quadrants (clear of the doors and
	                the centre), flame vents that erupt on a telegraphed cycle,
	                and broken stone pillars to hide behind.
	  Combat rooms  (about a third of them) spike traps: a grate that glows
	                and rattles, then shoots its spikes up.

	One server loop checks every player in the run against the live hazards:
	lava burns while you stand in it, vents and spikes hit once per eruption.
	Dodge i-frames (InvulnerableUntil) are respected.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Hazards = {}

local FLOOR_SIZE = 12

-- (dark molten rock, not flat neon: bright neon pools drowned out the
-- player, the boss and every telegraph)
local LAVA = Color3.fromRGB(215, 72, 20)
local LAVA_DEEP = Color3.fromRGB(150, 36, 12)
local CRUST = Color3.fromRGB(40, 22, 18)
local STONE = Color3.fromRGB(70, 64, 72)
local WARN = Color3.fromRGB(255, 60, 40)

local LAVA_DPS = 28          -- per second standing in lava
local VENT_DAMAGE = 30
local SPIKE_DAMAGE = 24

type Lava = { kind: "lava", center: Vector3, radius: number, floorY: number, part: BasePart }
type Vent = { kind: "vent", center: Vector3, radius: number, floorY: number, active: boolean, hit: { [Player]: boolean } }
type Spike = { kind: "spike", center: Vector3, half: number, floorY: number, active: boolean, hit: { [Player]: boolean } }
type Hazard = Lava | Vent | Spike

local hazards: { any } = {}
-- (each hazard belongs to the run whose dungeon was being built: runs are
-- torn down one at a time)
local buildingRun: string? = nil
function Hazards.SetRun(runId: string?)
	buildingRun = runId
end
local started = false

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

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

-- ── Lava ────────────────────────────────────────────────────────────────────
-- An irregular pool: a few overlapping discs of glowing lava with a dark
-- crust rim, bubbling embers and heat smoke.
local function lavaPool(folder: Instance, center: Vector3, radius: number, rng: Random)
	local pool = Instance.new("Model")
	pool.Name = "LavaPool"
	pool.Parent = folder
	local blobs = rng:NextInteger(2, 4)
	for i = 1, blobs do
		local off = if i == 1 then Vector3.zero else Vector3.new(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5)) * radius
		local r = if i == 1 then radius else radius * rng:NextNumber(0.5, 0.75)
		local c = center + off
		part(pool, { Name = "Crust", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, r * 2 + 2.2, r * 2 + 2.2),
			CFrame = CFrame.new(c + Vector3.new(0, 0.06, 0)) * FLAT, Color = CRUST, Material = Enum.Material.Basalt })
		local lava = part(pool, { Name = "Lava", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.34, r * 2, r * 2),
			CFrame = CFrame.new(c + Vector3.new(0, 0.1, 0)) * FLAT, Color = LAVA, Material = Enum.Material.CrackedLava })
		table.insert(hazards, { kind = "lava", center = c, radius = r, floorY = center.Y, part = lava, runId = buildingRun } :: any)
		if i == 1 then
			local a = Instance.new("Attachment")
			a.Parent = lava
			emitter(a, { Name = "Bubbles", Texture = "rbxasset://textures/particles/sparkles_main.dds",
				Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), LAVA), LightEmission = 1,
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) }),
				Lifetime = NumberRange.new(0.8, 1.6), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(30, 30),
				Acceleration = Vector3.new(0, -4, 0), Rate = r * 2 })
			emitter(a, { Name = "Heat", Texture = "rbxasset://textures/particles/smoke_main.dds",
				Color = ColorSequence.new(Color3.fromRGB(90, 40, 30), Color3.fromRGB(30, 20, 20)),
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.7), NumberSequenceKeypoint.new(1, 1) }),
				Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, r * 0.4), NumberSequenceKeypoint.new(1, r * 0.9) }),
				Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(1, 3), Rate = 3 })
		end
	end
	-- A slow glow pulse.
	for _, l in ipairs(pool:GetChildren()) do
		if l.Name == "Lava" and l:IsA("BasePart") then
			TweenService:Create(l, TweenInfo.new(1.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
				{ Color = LAVA_DEEP }):Play()
		end
	end
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
	local v: Vent = { kind = "vent", center = center, radius = 3.2, floorY = center.Y, active = false, hit = {} }
	(v :: any).runId = buildingRun
	table.insert(hazards, v :: any)
	-- Cycle: rest → glow warning → eruption.
	task.spawn(function()
		task.wait(rng:NextNumber(0, 4))
		while m.Parent do
			task.wait(3.2)
			if not m.Parent then break end
			TweenService:Create(glow, TweenInfo.new(0.7), { Transparency = 0.1 }):Play()
			task.wait(0.8)
			if not m.Parent then break end
			v.hit = {}
			v.active = true
			fire.Rate = 90
			task.wait(1.1)
			v.active = false
			fire.Rate = 0
			TweenService:Create(glow, TweenInfo.new(0.5), { Transparency = 0.9 }):Play()
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
	local spikes: { BasePart } = {}
	for x = -1, 1 do
		for z = -1, 1 do
			local base = center + Vector3.new(x * 2.1, 0, z * 2.1)
			local s = part(m, { Name = "Spike", Size = Vector3.new(0.7, 2.6, 0.7), CFrame = CFrame.new(base + Vector3.new(0, -1.4, 0)),
				Color = Color3.fromRGB(190, 190, 200), Material = Enum.Material.Metal })
			table.insert(spikes, s)
		end
	end
	local t: Spike = { kind = "spike", center = center, half = SIZE / 2, floorY = center.Y, active = false, hit = {} }
	(t :: any).runId = buildingRun
	table.insert(hazards, t :: any)
	task.spawn(function()
		task.wait(rng:NextNumber(0, 3))
		while m.Parent do
			task.wait(2.6)
			if not m.Parent then break end
			TweenService:Create(warn, TweenInfo.new(0.5), { Transparency = 0.25 }):Play()
			task.wait(0.65)
			if not m.Parent then break end
			t.hit = {}
			t.active = true
			for _, s in ipairs(spikes) do
				TweenService:Create(s, TweenInfo.new(0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
					{ CFrame = CFrame.new(s.Position.X, center.Y + 1.2, s.Position.Z) }):Play()
			end
			task.wait(0.9)
			t.active = false
			TweenService:Create(warn, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			for _, s in ipairs(spikes) do
				TweenService:Create(s, TweenInfo.new(0.4), { CFrame = CFrame.new(s.Position.X, center.Y - 1.4, s.Position.Z) }):Play()
			end
		end
	end)
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

-- The boss arena: lava in each quadrant, vents between them, pillars for cover.
function Hazards.BuildBossArena(room: Room, folder: Instance, rng: Random)
	local minX, maxX, minZ, maxZ = bounds(room)
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local hx, hz = (maxX - minX) / 2, (maxZ - minZ) / 2
	local y = room.floorY
	local f = Instance.new("Folder")
	f.Name = "ArenaHazards"
	f.Parent = folder
	-- Lava: in the quadrants, off the diagonals' ends (so the doors, on the
	-- walls' middles, and the centre stay clear).
	for _, q in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		local c = Vector3.new(cx + q[1] * hx * 0.5, y, cz + q[2] * hz * 0.5)
		lavaPool(f, c, math.min(hx, hz) * rng:NextNumber(0.16, 0.22), rng)
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

-- A few spike traps scattered on a combat room's open floor.
function Hazards.BuildTraps(room: Room, folder: Instance, rng: Random)
	local minX, maxX, minZ, maxZ = bounds(room)
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local f = Instance.new("Folder")
	f.Name = "Traps"
	f.Parent = folder
	local n = rng:NextInteger(3, 6)
	local placed: { Vector3 } = {}
	local tries = 0
	while #placed < n and tries < 60 do
		tries += 1
		local p = Vector3.new(rng:NextNumber(minX + 14, maxX - 14), room.floorY, rng:NextNumber(minZ + 14, maxZ - 14))
		-- Keep clear of the centre (the reward) and of each other.
		local ok = (Vector3.new(p.X - cx, 0, p.Z - cz)).Magnitude > 12
		for _, o in ipairs(placed) do
			if (p - o).Magnitude < 10 then ok = false end
		end
		if ok then
			table.insert(placed, p)
			spikeTrap(f, p, rng)
		end
	end
end

-- ── The damage loop ─────────────────────────────────────────────────────────
local function step(dt: number)
	local now = os.clock()
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
				if flat.Magnitude <= h.radius then
					hum:TakeDamage(LAVA_DPS * dt)
					char:SetAttribute("InLava", now)
				end
			elseif h.kind == "vent" then
				if h.active and not h.hit[plr] and flat.Magnitude <= h.radius then
					h.hit[plr] = true
					hum:TakeDamage(VENT_DAMAGE)
					root.AssemblyLinearVelocity += Vector3.new(0, 38, 0)
				end
			elseif h.kind == "spike" then
				if h.active and not h.hit[plr] and math.abs(flat.X) <= h.half and math.abs(flat.Z) <= h.half then
					h.hit[plr] = true
					hum:TakeDamage(SPIKE_DAMAGE)
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
end

return Hazards
