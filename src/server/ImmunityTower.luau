--!strict
--[[
	ImmunityTower.luau
	The arcade's shield tower (ArcadeKit's "Tower_Immunity"). While it stands,
	every mob within its reach is IMMUNE: nothing the players do hurts it
	(SkillManager's dealDamage turns the hit away and says so), and a magenta
	bubble round it and a beam of light from the tower's crystal show which.
	So the tower has to be broken first: it's a target like a mob (a Humanoid
	and health, hit anywhere on its body), though it never moves or fights.
	Broken, it shatters and every shield it held drops. Bosses aren't shielded.

	  ImmunityTower.Spawn(cf, opts?) → Model    standing at `cf` (its base on
	      the floor). opts: radius (studs, 24), health (600), parent (Workspace)
	  ImmunityTower.SetupRooms(rooms, level, parent, rng)  the Neon Arcade's
	      towers, placed as DungeonGenerator builds one of its floors
	  ImmunityTower.Shielded(model) → boolean   (the attribute: "TowerShielded")

	Its reach is drawn on the floor: a faint disc and a rim of light.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local ArcadeKit = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ArcadeKit"))

local ImmunityTower = {}

local DEFAULT_RADIUS = 24
local DEFAULT_HEALTH = 600
local TICK = 0.25 -- (who's in reach, a few times a second)
local MAGENTA = Color3.fromRGB(255, 60, 210)
local SHIELD_ATTR = "TowerShielded"

type Tower = { model: Model, root: BasePart, core: BasePart, pos: Vector3, radius: number, alive: boolean }
type Shield = { tower: Tower, a0: Attachment, a1: Attachment, beam: Beam, bubble: BasePart }

local towers: { Tower } = {}
local shields: { [Model]: Shield } = {}
local stepping: RBXScriptConnection? = nil
local acc = 0

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function plain(p: BasePart)
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
end

-- ── Shields ─────────────────────────────────────────────────────────────────
local function shield(mob: Model, root: BasePart, t: Tower)
	local a1 = Instance.new("Attachment")
	a1.Name = "TowerShieldAtt"
	a1.Parent = root
	local a0 = Instance.new("Attachment")
	a0.Name = "TowerBeamAtt"
	a0.Parent = t.core
	local beam = Instance.new("Beam")
	beam.Attachment0, beam.Attachment1 = a0, a1
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 170, 245), MAGENTA)
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Width0, beam.Width1 = 0.5, 0.25
	beam.Transparency = NumberSequence.new(0.2, 0.55)
	beam.FaceCamera = true
	beam.Segments = 1
	beam.Parent = a1
	-- the bubble: a shimmering shell just bigger than the mob
	local size = mob:GetExtentsSize()
	local d = math.clamp(math.max(size.X, size.Y, size.Z) * 1.15, 4, 18)
	local bubble = Instance.new("Part")
	bubble.Name = "TowerShieldBubble"
	bubble.Shape = Enum.PartType.Ball
	bubble.Size = Vector3.one * d
	bubble.Material = Enum.Material.ForceField
	bubble.Color = MAGENTA
	bubble.CanCollide, bubble.CanQuery, bubble.CanTouch, bubble.CastShadow = false, false, false, false
	bubble.Massless = true
	bubble.CFrame = root.CFrame
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = root, bubble
	w.Parent = bubble
	bubble.Parent = mob
	mob:SetAttribute(SHIELD_ATTR, true)
	shields[mob] = { tower = t, a0 = a0, a1 = a1, beam = beam, bubble = bubble }
end

local function unshield(mob: Model)
	local s = shields[mob]
	if not s then return end
	shields[mob] = nil
	for _, i in ipairs({ s.a0, s.a1, s.bubble } :: { Instance }) do
		if i.Parent then i:Destroy() end
	end
	if mob.Parent then mob:SetAttribute(SHIELD_ATTR, nil) end
end

local function step(dt: number)
	acc += dt
	if acc < TICK then return end
	acc = 0
	-- which tower (if any) holds each mob now
	local want: { [Model]: Tower } = {}
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then
		for _, mob in ipairs(mobs:GetChildren()) do
			if not mob:IsA("Model") or mob:GetAttribute("IsBoss") == true then continue end
			local hum = mob:FindFirstChildOfClass("Humanoid")
			local root = mob:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not (hum and hum.Health > 0 and root) then continue end
			for _, t in ipairs(towers) do
				if t.alive and flatDist(root.Position, t.pos) <= t.radius then
					want[mob] = t
					break
				end
			end
		end
	end
	for mob, s in pairs(shields) do
		if want[mob] ~= s.tower or not mob.Parent then unshield(mob) end
	end
	for mob, t in pairs(want) do
		if not shields[mob] then
			local root = mob:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then shield(mob, root, t) end
		end
	end
	-- (nothing left to watch: stop)
	if #towers == 0 and next(shields) == nil and stepping then
		stepping:Disconnect()
		stepping = nil
	end
end

-- ── Breaking ────────────────────────────────────────────────────────────────
-- The tower gone (broken, or its room cleared away): its shields drop.
local function retire(t: Tower): boolean
	if not t.alive then return false end
	t.alive = false
	local i = table.find(towers, t)
	if i then table.remove(towers, i) end
	for mob, s in pairs(shields) do
		if s.tower == t then unshield(mob) end
	end
	return true
end

-- Broken: it shatters, its pieces thrown out and tumbling (away into the
-- void, off a floating floor), a flash of magenta light.
local function shatter(t: Tower)
	if not retire(t) then return end
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Material = Enum.Material.Neon
	flash.Color = Color3.fromRGB(255, 150, 240)
	flash.Size = Vector3.one * 3
	plain(flash)
	flash.CFrame = t.core.CFrame
	flash.Parent = t.model
	TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * 22, Transparency = 1 }):Play()
	local center = t.pos + Vector3.new(0, 6, 0)
	for _, d in ipairs(t.model:GetDescendants()) do
		if d:IsA("BasePart") and d ~= flash then
			if d.Name == "ReachDisc" or d.Name == "ReachRim" or d.Transparency >= 1 then
				d:Destroy()
			else
				d.Anchored = false
				d.CanCollide = true
				d.CanQuery = false
				local out = d.Position - center
				out = if out.Magnitude > 0.1 then out.Unit else Vector3.yAxis
				d.AssemblyLinearVelocity = out * (18 + math.random() * 22) + Vector3.new(0, 14 + math.random() * 10, 0)
				d.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 12
			end
		elseif d:IsA("ParticleEmitter") or d:IsA("BillboardGui") then
			d:Destroy()
		end
	end
	Debris:AddItem(t.model, 3)
end

-- ── Spawning ────────────────────────────────────────────────────────────────
export type Options = { radius: number?, health: number?, parent: Instance? }

function ImmunityTower.Spawn(cf: CFrame, opts: Options?): Model
	local o = opts or {}
	local radius = o.radius or DEFAULT_RADIUS
	local health = o.health or DEFAULT_HEALTH
	local m = ArcadeKit.Build("Tower_Immunity") :: Model
	m.Name = "ImmunityTower"
	m:PivotTo(cf)
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then d.Anchored = true end
	end
	local core = m:FindFirstChild("Core") :: BasePart
	-- a target like a mob: a root in its middle, health, hit anywhere within 3
	-- studs of its middle (SkillManager's HitRadius / HitProxy)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(4, 12, 4)
	root.Transparency = 1
	plain(root)
	root.CanQuery = true
	root.CFrame = cf * CFrame.new(0, 6, 0)
	root.Parent = m
	m.PrimaryPart = root
	local proxy = Instance.new("Part")
	proxy.Name = "HitProxy"
	proxy.Size = Vector3.one
	proxy.Transparency = 1
	plain(proxy)
	proxy.CFrame = root.CFrame
	proxy.Parent = m
	m:SetAttribute("HitRadius", 3)
	m:SetAttribute("IsTower", true)
	local hum = Instance.new("Humanoid")
	hum.RequiresNeck = false
	hum.BreakJointsOnDeath = false
	hum.EvaluateStateMachine = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.MaxHealth = health
	hum.Health = health
	hum.Parent = m
	-- its name and health over it
	local bb = Instance.new("BillboardGui")
	bb.Name = "TowerBar"
	bb.Size = UDim2.fromOffset(170, 34)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 10, 0)
	bb.MaxDistance = 140
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 16)
	label.BackgroundTransparency = 1
	label.Text = "IMMUNITY TOWER"
	label.Font = Enum.Font.Arcade
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 190, 245)
	label.TextStrokeTransparency = 0.3
	label.Parent = bb
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 20)
	back.Size = UDim2.new(1, 0, 0, 10)
	back.BackgroundColor3 = Color3.fromRGB(30, 10, 34)
	back.BorderSizePixel = 0
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = MAGENTA
	fill.BorderSizePixel = 0
	fill.Parent = back
	bb.Parent = root
	-- (its health bar; and at nothing, it breaks: its Humanoid runs no state
	-- machine, so it never "dies" on its own)
	local t: Tower
	hum.HealthChanged:Connect(function(h)
		fill.Size = UDim2.fromScale(math.clamp(h / math.max(hum.MaxHealth, 1), 0, 1), 1)
		if h <= 0 and t then shatter(t) end
	end)
	-- its reach on the floor
	local floorCf = CFrame.new(cf.Position)
	local disc = Instance.new("Part")
	disc.Name = "ReachDisc"
	disc.Shape = Enum.PartType.Cylinder
	disc.Material = Enum.Material.Neon
	disc.Color = MAGENTA
	disc.Transparency = 0.95
	disc.Size = Vector3.new(0.06, radius * 2, radius * 2)
	plain(disc)
	disc.CFrame = floorCf * CFrame.new(0, 0.04, 0) * CFrame.Angles(0, 0, math.rad(90))
	disc.Parent = m
	local n = math.clamp(math.floor(radius * 1.1), 24, 60)
	for k = 0, n - 1 do
		local a = (k + 0.5) / n * math.pi * 2
		local p = floorCf * Vector3.new(math.cos(a) * radius, 0.08, math.sin(a) * radius)
		local seg = Instance.new("Part")
		seg.Name = "ReachRim"
		seg.Material = Enum.Material.Neon
		seg.Color = MAGENTA
		seg.Transparency = 0.25
		seg.Size = Vector3.new(0.2, 0.06, 2 * radius * math.sin(math.pi / n) * 0.75)
		plain(seg)
		seg.CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a)))
		seg.Parent = m
	end
	m.Parent = o.parent or Workspace
	t = { model = m, root = root, core = core, pos = cf.Position, radius = radius, alive = true }
	table.insert(towers, t)
	m.AncestryChanged:Connect(function(_, parent)
		if not parent then retire(t) end
	end)
	if not stepping then
		acc = TICK
		stepping = RunService.Heartbeat:Connect(step)
	end
	return m
end

-- The Neon Arcade's towers (DungeonGenerator, as it builds a floor): one in
-- about half its combat rooms and in every elite room (two in a big one),
-- off to one side of the middle (clear of the room's reward), on open floor;
-- tougher deeper down, reaching over most of the room. Returns how many.
local TILE = 12 -- (DungeonGenerator's FLOOR_SIZE)
function ImmunityTower.SetupRooms(rooms: { any }, level: number, parent: Instance, rng: Random): number
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	local placed = 0
	for _, room in ipairs(rooms) do
		local kind = room.roomType
		if room.id == 1 or not (kind == "Combat" or kind == "Elite") then continue end
		if kind == "Combat" and rng:NextNumber() > 0.5 then continue end
		local n = if kind == "Elite" and room.w * room.d >= 30 then 2 else 1
		local cx = (room.gx + (room.w - 1) / 2) * TILE
		local cz = (room.gz + (room.d - 1) / 2) * TILE
		local hx, hz = room.w * TILE / 2, room.d * TILE / 2
		local top = room.floorY + 0.5
		local a0 = rng:NextNumber() * math.pi * 2
		for k = 1, n do
			local a = a0 + (k - 1) * math.pi
			-- (a few tries for a spot of bare floor: not a wall, a prop or a trap)
			for _ = 1, 6 do
				local r = rng:NextNumber(0.35, 0.55)
				local x, z = cx + math.cos(a) * hx * r, cz + math.sin(a) * hz * r
				local hit = Workspace:Raycast(Vector3.new(x, top + 14, z), Vector3.new(0, -28, 0), rp)
				if hit and math.abs(hit.Position.Y - top) < 1.5 then
					local floor = hit.Position
					ImmunityTower.Spawn(CFrame.lookAt(floor, Vector3.new(cx, floor.Y, cz)), {
						health = 450 + 150 * level,
						radius = math.clamp(math.min(hx, hz) * 0.75, 18, 26),
						parent = parent,
					})
					placed += 1
					break
				end
				a += 0.6
			end
		end
	end
	return placed
end

function ImmunityTower.Shielded(model: Model): boolean
	return model:GetAttribute(SHIELD_ATTR) == true
end

return ImmunityTower
