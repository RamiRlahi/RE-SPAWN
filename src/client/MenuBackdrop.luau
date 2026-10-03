--!strict
--[[
	MenuBackdrop.luau
	The title screen's living sky kingdom, composed after the RE:SPAWN key art:
	  • foreground (lower right): a dark mossy hero platform with your
	    character idling beside a burning brazier and a planted sword, ruined
	    walls framing the left behind the menu, grass, embers, warm fire light
	  • the massive floating capital right of centre: gothic towers with
	    pointed roofs, pinnacles, buttresses and glowing windows, a pillar of
	    light and two counter-spinning runic halo rings
	  • keeps, ruins and groves on the user's "floating island" model (with
	    their "waterfall" asset), small spiked shards drifting through the sky
	  • a sunset grade (violet sky, warm horizon, dark foreground) applied
	    while the menu is up and restored afterwards

	Opening sequence: the loading screen fades onto the finished scene (every
	island and castle already in place and loaded) → the beam ignites → logo →
	menu (TitleScreen listens through MenuBackdrop.OnRevealed). Everything is
	built on the client around the fixed title shot and removed when you
	enter a run. Distant scenery is built nearer and smaller (see compress)
	so it's drawn at every graphics quality.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")

local ClassData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("ClassData"))

local MenuBackdrop = {}

local rng = Random.new(7)

-- The exact title shot, set in Studio: the camera stands at CAM_FROM and
-- looks at CAM_TO. The scene is laid out around this view.
local CAM_FROM = Vector3.new(399.016, 860.579, -104.064)
local CAM_TO = Vector3.new(-305.941, 890.45, 233.328)
-- The lobby spawn: nothing is placed near it (class select shows you there).
local LOBBY_SPAWN = Vector3.new(643.96, 857.16, -202.35)
local folder: Folder? = nil
local conn: RBXScriptConnection? = nil

-- ── Asset access ────────────────────────────────────────────────────────────
local DUNGEON = "dungeon assets"
local MAP2 = "map2assets"
local PREFIX1 = "Meshes/PolygonDungeon_Environments_01_SM_Env_"
local PREFIX2 = "Meshes/PolygonDungeon_Environments_02_SM_Env_"

local function find(path: { string }): BasePart?
	local cur: Instance? = ReplicatedStorage
	for _, seg in ipairs(path) do
		cur = cur and cur:FindFirstChild(seg)
	end
	return if cur and cur:IsA("BasePart") then cur else nil
end

-- A clone of an asset MeshPart, anchored and non-colliding.
local function mesh(path: { string }, parent: Instance, cf: CFrame, scale: number?): BasePart?
	local src = find(path)
	if not src then return nil end
	local p = src:Clone()
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	if scale and scale ~= 1 then p.Size = p.Size * scale end
	p.CFrame = cf
	p.Parent = parent
	return p
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

local GOLD = Color3.fromRGB(255, 214, 130)
local MOSS = Color3.fromRGB(66, 88, 54)
local RUIN = Color3.fromRGB(58, 48, 72)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
-- The game's default idle (character AnimationController, R6).
local HERO_IDLE = "rbxassetid://86968114690424"

local STATUES = { "Statue_01", "Statue_02", "Statue_03", "Statue_04" }
local TREES = { "Tree_Twisted_01", "Tree_Twisted_02" }

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

-- ── The menu's scene models ────────────────────────────────────────────────
-- They live in ReplicatedStorage/Preload/MenuAssets/Models (the menu's
-- critical assets, preloaded before the menu shows); older places keep them
-- at the root of ReplicatedStorage.
function MenuBackdrop.SceneModel(name: string): Model?
	local preload = ReplicatedStorage:FindFirstChild("Preload")
	local menuAssets = preload and preload:FindFirstChild("MenuAssets")
	local models = menuAssets and menuAssets:FindFirstChild("Models")
	local m = (models and models:FindFirstChild(name)) or ReplicatedStorage:FindFirstChild(name)
	return if m and m:IsA("Model") then m else nil
end

-- ── Island template: the user's "floating island" ──────────────────────────
local template: Model? = nil
local function getTemplate(): Model?
	if template and template.Parent then return template end
	local fi = MenuBackdrop.SceneModel("floating island")
	if fi and fi:IsA("Model") then
		template = fi
		return fi
	end
	-- Fallback: the low-poly island in Workspace.SpawnPoint.
	local sp = Workspace:FindFirstChild("SpawnPoint")
	if sp then
		for _, c in ipairs(sp:GetChildren()) do
			if c:IsA("Model") and c:FindFirstChild("Low-Poly Grass", true) then
				template = c
				return c
			end
		end
	end
	return nil
end

-- A copy of the template scaled to `width` studs across, recoloured to the
-- key art's dark violet stone with mossy tops, its top surface at y = 0 and
-- centred on the origin. Scripts stripped, all anchored.
local function islandBase(tpl: Model, width: number, parent: Model): Model
	local c = tpl:Clone()
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = true -- for the surface raycast below
			d.CastShadow = false
			if d:IsA("UnionOperation") then d.UsePartColor = true end
			if d.Material == Enum.Material.Grass or d.Material == Enum.Material.LeafyGrass then
				d.Color = MOSS
			elseif not d:IsA("MeshPart") then
				local v = rng:NextNumber(-9, 9)
				d.Color = Color3.fromRGB(84 + v, 68 + v * 0.8, 96 + v)
			end
		end
	end
	local _, size = c:GetBoundingBox()
	pcall(function() c:ScaleTo(c:GetScale() * width / math.max(size.X, size.Z)) end)
	local cf = c:GetBoundingBox()
	c:PivotTo(c:GetPivot() - cf.Position) -- bounding box centred on the origin
	c.Parent = parent
	-- Find the real walking surface at the centre and put it at y = 0.
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = { c }
	local _, s2 = c:GetBoundingBox()
	local hit = Workspace:Raycast(Vector3.new(0, s2.Y * 2, 0), Vector3.new(0, -s2.Y * 4, 0), params)
	local topY = if hit then hit.Position.Y else s2.Y / 2
	c:PivotTo(c:GetPivot() - Vector3.new(0, topY, 0))
	for _, d in ipairs(c:GetDescendants()) do
		if d:IsA("BasePart") then d.CanQuery = false end
	end
	return c
end

-- ── Castle pieces: pale stone, dark slate roofs, warm windows ─────────────
-- Built for silhouette: tall needles, pinnacles, balconies, buttresses.
local TOWER = Color3.fromRGB(184, 170, 200)
local TOWER_DARK = Color3.fromRGB(128, 114, 146)
local ROOF = Color3.fromRGB(52, 42, 78)
local WINDOW = Color3.fromRGB(255, 196, 110)
local UP = CFrame.Angles(0, 0, math.rad(90)) -- a Cylinder standing upright
local windows: { BasePart } = {} -- flickered in the render loop

-- An upright cylinder of radius r and height h standing on `at`.
local function cyl(m: Instance, at: Vector3, r: number, h: number, color: Color3, material: Enum.Material?): BasePart
	return part(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(h, r * 2, r * 2), CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0)) * UP,
		Color = color, Material = material or Enum.Material.Slate })
end

-- A pointed roof: a stack of shrinking discs standing on `at`.
local function cone(m: Instance, at: Vector3, r: number, h: number, color: Color3, steps: number)
	for s = 0, steps - 1 do
		local k = 1 - s / steps
		cyl(m, at + Vector3.new(0, s * h / steps, 0), math.max(r * k, 0.12), h / steps + 0.05, color)
	end
end

-- A gothic round tower of height h on (x, z): plinth, string courses, arched
-- glowing windows, a crenellated balcony, a pointed roof with a needle and
-- gold tip, and four pinnacles.
local function tower(m: Model, x: number, z: number, r: number, h: number, roofH: number?)
	local base = Vector3.new(x, 0, z)
	cyl(m, base, r * 1.25, r * 0.7, TOWER_DARK)
	cyl(m, base, r, h, TOWER)
	local courses = math.clamp(math.floor(h / (r * 4)), 1, 4)
	for i = 1, courses do
		cyl(m, base + Vector3.new(0, h * i / (courses + 1), 0), r * 1.06, r * 0.12, TOWER_DARK)
	end
	local spin = rng:NextNumber(0, math.pi * 2)
	for row = 1, math.min(courses, 3) do
		local y = h * row / (courses + 1)
		for c = 0, 2 do
			local cf = CFrame.new(x, y, z) * CFrame.Angles(0, spin + c * 2.094, 0) * CFrame.new(0, 0, -r * 0.98)
			local slit = part(m, { Size = Vector3.new(r * 0.26, r * 0.8, r * 0.14), CFrame = cf, Color = WINDOW, Material = Enum.Material.Neon })
			part(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * r * 0.26, CFrame = cf * CFrame.new(0, r * 0.4, 0), Color = WINDOW, Material = Enum.Material.Neon })
			table.insert(windows, slit)
		end
	end
	-- Balcony with merlons.
	cyl(m, base + Vector3.new(0, h, 0), r * 1.3, r * 0.18, TOWER_DARK)
	for i = 0, 7 do
		local a = i * math.pi / 4
		part(m, { Size = Vector3.new(r * 0.3, r * 0.35, r * 0.3),
			CFrame = CFrame.new(x + math.cos(a) * r * 1.2, h + r * 0.18 + r * 0.17, z + math.sin(a) * r * 1.2) * CFrame.Angles(0, -a, 0),
			Color = TOWER, Material = Enum.Material.Slate })
	end
	-- Roof, needle, gold tip.
	local rh = roofH or r * 3.2
	local roofBase = base + Vector3.new(0, h + r * 0.18, 0)
	cone(m, roofBase, r * 1.1, rh, ROOF, 10)
	cyl(m, roofBase + Vector3.new(0, rh, 0), math.max(r * 0.06, 0.1), rh * 0.35, ROOF)
	part(m, { Shape = Enum.PartType.Ball, Size = Vector3.one * math.max(0.6, r * 0.22),
		CFrame = CFrame.new(roofBase + Vector3.new(0, rh * 1.35, 0)), Color = GOLD, Material = Enum.Material.Neon })
	-- Pinnacles around the roof (big towers only; specks on small ones).
	for i = 0, if r > 4 then 3 else -1 do
		local a = i * math.pi / 2 + math.pi / 4
		cone(m, roofBase + Vector3.new(math.cos(a) * r * 1.15, r * 0.35, math.sin(a) * r * 1.15), r * 0.16, rh * 0.4, ROOF, 4)
	end
end

-- A crenellated curtain wall from a to b with glowing arrow slits.
local function wallBetween(m: Model, a: Vector3, b: Vector3, h: number)
	local len = (b - a).Magnitude
	local cf = CFrame.lookAt((a + b) / 2, b)
	local t = h * 0.22
	part(m, { Size = Vector3.new(t, h, len), CFrame = cf * CFrame.new(0, h / 2, 0), Color = TOWER, Material = Enum.Material.Slate })
	part(m, { Size = Vector3.new(t * 1.4, h * 0.08, len), CFrame = cf * CFrame.new(0, h, 0), Color = TOWER_DARK, Material = Enum.Material.Slate })
	local n = math.max(3, math.floor(len / (h * 0.3)))
	for i = 0, n - 1, 2 do
		part(m, { Size = Vector3.new(t * 1.2, h * 0.16, len / n),
			CFrame = cf * CFrame.new(0, h * 1.12, -len / 2 + (i + 0.5) * len / n), Color = TOWER, Material = Enum.Material.Slate })
	end
	for i = 1, 3 do
		table.insert(windows, part(m, { Size = Vector3.new(t * 1.05, h * 0.3, h * 0.08),
			CFrame = cf * CFrame.new(0, h * 0.55, -len / 2 + i * len / 4), Color = WINDOW, Material = Enum.Material.Neon }))
	end
end

-- A flying buttress: a slanted stone beam from one tower to another.
local function buttress(m: Model, from: Vector3, to: Vector3, w: number)
	part(m, { Size = Vector3.new(w, w * 0.8, (to - from).Magnitude), CFrame = CFrame.lookAt((from + to) / 2, to),
		Color = TOWER_DARK, Material = Enum.Material.Slate })
end

-- A ruined stone arch (one pillar broken when `broken`).
local function ruinArch(m: Model, at: Vector3, yaw: number, s: number, broken: boolean)
	local cf = CFrame.new(at) * CFrame.Angles(0, yaw, 0)
	local ph = 9 * s
	part(m, { Size = Vector3.new(1.5 * s, ph, 1.5 * s), CFrame = cf * CFrame.new(-3 * s, ph / 2, 0), Color = TOWER_DARK, Material = Enum.Material.Slate })
	local rh = if broken then ph * 0.55 else ph
	part(m, { Size = Vector3.new(1.5 * s, rh, 1.5 * s), CFrame = cf * CFrame.new(3 * s, rh / 2, 0), Color = TOWER_DARK, Material = Enum.Material.Slate })
	if not broken then
		part(m, { Size = Vector3.new(7.6 * s, 1.3 * s, 1.7 * s), CFrame = cf * CFrame.new(0, ph + 0.65 * s, 0), Color = TOWER, Material = Enum.Material.Slate })
		part(m, { Size = Vector3.new(1.3 * s, 1.3 * s, 1.8 * s), CFrame = cf * CFrame.new(0, ph + 1.3 * s, 0) * CFrame.Angles(0, 0, math.rad(45)),
			Color = TOWER, Material = Enum.Material.Slate })
	end
end

-- ── One floating island (top surface at y = 0, centred on the origin) ──────
-- kind: "spire" (the capital), "keep" (walled castle), "ruin" (broken
-- arches + statue), "grove" (trees + rune stones).
local function buildIsland(kind: string, width: number): Model
	local m = Instance.new("Model")
	m.Name = "SkyIsland"
	m.Parent = folder -- in the world, so the surface raycast can hit it
	local tpl = getTemplate()
	if tpl then
		islandBase(tpl, width, m)
	else
		cyl(m, Vector3.new(0, -width * 0.2, 0), width / 2, width * 0.2, Color3.fromRGB(84, 68, 96))
	end
	local s = width / 44 -- castle scale relative to a 44-stud island

	if kind == "spire" then
		-- The capital: a curtain wall, corner towers, a ring of tall towers
		-- braced to one great central spire.
		local half = 12 * s
		local corners = {
			Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half), Vector3.new(half, 0, half), Vector3.new(-half, 0, half),
		}
		for i = 1, 4 do wallBetween(m, corners[i], corners[(i % 4) + 1], 6 * s) end
		for i, c in ipairs(corners) do
			tower(m, c.X, c.Z, 2.4 * s, (11 + (i % 2) * 5) * s, 7 * s)
		end
		for i = 1, 6 do
			local a = i / 6 * math.pi * 2 + 0.3
			local h = (15 + (i % 3) * 4) * s
			local p = Vector3.new(math.cos(a) * 7.5 * s, 0, math.sin(a) * 7.5 * s)
			tower(m, p.X, p.Z, 1.9 * s, h, 8 * s)
			buttress(m, p + Vector3.new(0, h * 0.75, 0) * 1, Vector3.new(p.X * 0.45, h * 0.75 + 5 * s, p.Z * 0.45), 0.7 * s)
		end
		tower(m, 0, 0, 3.8 * s, 26 * s, 14 * s)
	elseif kind == "keep" then
		local half = 7 * s
		local corners = {
			Vector3.new(-half, 0, -half), Vector3.new(half, 0, -half), Vector3.new(half, 0, half), Vector3.new(-half, 0, half),
		}
		for i = 1, 4 do wallBetween(m, corners[i], corners[(i % 4) + 1], 4.5 * s) end
		for _, c in ipairs(corners) do tower(m, c.X, c.Z, 1.7 * s, 9 * s, 5 * s) end
		tower(m, 0, 0, 2.7 * s, 16 * s, 9 * s)
	elseif kind == "ruin" then
		for i = 0, 2 do
			local a = i * 2.1
			ruinArch(m, Vector3.new(math.cos(a) * 7 * s, 0, math.sin(a) * 7 * s), -a + math.pi / 2, s, i == 1)
		end
		mesh({ DUNGEON, "cosmetics", PREFIX2 .. pick(STATUES) }, m, CFrame.new(0, 7.8 * s * 0.9, 0), s * 0.9)
		cyl(m, Vector3.new(8 * s, 0, 5 * s), 2 * s, 7 * s, TOWER_DARK)
	else -- grove
		for _ = 1, 4 do
			local a = rng:NextNumber(0, math.pi * 2)
			local d = rng:NextNumber(2, 10) * s
			mesh({ MAP2, PREFIX2 .. pick(TREES) }, m, CFrame.new(math.cos(a) * d, 2.9 * 2.2 * s, math.sin(a) * d) * CFrame.Angles(0, a, 0), 2.2 * s)
		end
		for i = 1, 3 do
			local a = i * 2.1
			mesh({ DUNGEON, "rubble", PREFIX1 .. "Rune_Pillar_0" .. i }, m, CFrame.new(math.cos(a) * 6 * s, 4.1 * 1.4 * s, math.sin(a) * 6 * s), 1.4 * s)
		end
	end
	-- Waterfalls from the user's asset, pouring off the rim.
	local fallTpl = MenuBackdrop.SceneModel("waterfall")
	if fallTpl and fallTpl:IsA("Model") and kind ~= "grove" then
		for i = 1, if kind == "spire" then 3 else 1 do
			local fall = fallTpl:Clone()
			for _, d in ipairs(fall:GetDescendants()) do
				if d:IsA("LuaSourceContainer") then d:Destroy()
				elseif d:IsA("BasePart") then d.Anchored = true d.CanCollide = false d.CanQuery = false end
			end
			local _, fs = fall:GetBoundingBox()
			pcall(function() fall:ScaleTo(fall:GetScale() * (width * 1.6) / fs.Y) end)
			local cf, sz = fall:GetBoundingBox()
			local a = i * 2.1 + rng:NextNumber(-0.3, 0.3)
			local rim = Vector3.new(math.cos(a) * width * 0.42, 0, math.sin(a) * width * 0.42)
			-- Align the fall's top-centre with the rim point.
			local topOffset = cf.Position + Vector3.new(0, sz.Y / 2, 0) - fall:GetPivot().Position
			fall:PivotTo(CFrame.new(rim) * CFrame.Angles(0, -a, 0) * CFrame.new(-topOffset))
			fall.Parent = m
		end
	end
	m.WorldPivot = CFrame.new()
	return m
end

-- ── Distance compression ────────────────────────────────────────────────────
-- Roblox stops drawing parts past a distance set by the player's graphics
-- quality (~150–200 studs at the lowest, and Automatic starts low), so far
-- scenery would pop in late or never show. Everything distant is built
-- nearer instead, shrunk about the camera by the same factor: from the menu
-- shot it looks exactly as far and as massive, but it's always drawn.
-- Distances from 200 studs out map into 95–150 (nearer stays nearer).
local compressOrigin = Vector3.zero -- the title camera (set by Build)
local function compress(pos: Vector3): (Vector3, number)
	local off = pos - compressOrigin
	local d = off.Magnitude
	if d < 150 then return pos, 1 end
	local placed = 95 + 55 * (1 - 1 / (1 + math.max(d - 200, 0) / 300))
	local k = placed / d
	return compressOrigin + off * k, k
end

-- Soft cloud banks (particles), tinted warm on top, violet underneath.
local function cloudBank(parent: Instance, center: Vector3, spread: number, size: number, rate: number)
	local near, k = compress(center)
	center = near
	spread *= k
	size *= k
	local p = part(parent, { Size = Vector3.new(spread, 4 * k, spread), CFrame = CFrame.new(center), Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SMOKE
	e.Color = ColorSequence.new(Color3.fromRGB(250, 190, 170), Color3.fromRGB(130, 96, 160))
	e.LightInfluence = 0.4
	e.LightEmission = 0.05
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.6), NumberSequenceKeypoint.new(1, size) })
	e.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.5), NumberSequenceKeypoint.new(0.75, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	e.Lifetime = NumberRange.new(18, 26)
	e.Speed = NumberRange.new(1.5 * k, 4 * k)
	e.SpreadAngle = Vector2.new(15, 180)
	e.EmissionDirection = Enum.NormalId.Right
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-4, 4)
	e.Rate = rate
	e.Parent = p
	-- Pre-fill so the sky isn't empty when the menu opens.
	e:Emit(math.floor(rate * 18))
end

-- ── Build state ────────────────────────────────────────────────────────────
type Floater = { model: Model, base: CFrame, amp: number, speed: number, phase: number, yaw: number }
local floaters: { Floater } = {}
local beamCore: BasePart? = nil
local beamSheath: BasePart? = nil
local beamRise: ParticleEmitter? = nil
local hero: Model? = nil

local function float(m: Model, base: CFrame, amp: number)
	m:PivotTo(base)
	table.insert(floaters, { model = m, base = base, amp = amp, speed = rng:NextNumber(0.25, 0.45),
		phase = rng:NextNumber(0, 6.28), yaw = rng:NextNumber(-0.01, 0.01) })
end

-- `pos` / `scale` as seen from the camera; built nearer and smaller (compress).
local function place(kind: string, pos: Vector3, scale: number): Model
	local near, k = compress(pos)
	local width = (if kind == "spire" then 68 else 44) * scale * k
	local m = buildIsland(kind, width)
	float(m, CFrame.new(near) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(2.5, 6) * k)
	return m
end

-- A small spiked shard of the island model drifting in the sky.
local function shard(pos: Vector3, width: number)
	local tpl = getTemplate()
	if not tpl then return end
	local near, k = compress(pos)
	local m = Instance.new("Model")
	m.Name = "SkyShard"
	m.Parent = folder
	islandBase(tpl, width * k, m)
	m.WorldPivot = CFrame.new()
	float(m, CFrame.new(near) * CFrame.Angles(0, rng:NextNumber(0, math.pi * 2), 0), rng:NextNumber(1.5, 4) * k)
end

-- The title-screen camera shot (nil until built). LobbyCamera holds it.
local vista: CFrame? = nil
function MenuBackdrop.Vista(): CFrame?
	return vista
end

-- ── Sunset grade: violet sky, warm horizon, dark foreground ────────────────
local savedLighting: { [string]: any }? = nil
local gradeFx: { Instance } = {}

-- Put the real sun low on the horizon along `dir` (so sun rays and rim light
-- come from the painted sunset), searching clock time × latitude.
local function alignSun(dir: Vector3)
	local bestT, bestLat, bestDot = Lighting.ClockTime, Lighting.GeographicLatitude, -2
	for lat = -60, 60, 10 do
		Lighting.GeographicLatitude = lat
		for _, range in ipairs({ { 5.6, 7.6 }, { 16.4, 18.4 } }) do
			for t = range[1], range[2], 0.1 do
				Lighting.ClockTime = t
				local s = Lighting:GetSunDirection()
				if s.Y > 0.03 and s.Y < 0.2 then
					local d = s:Dot(dir)
					if d > bestDot then bestDot, bestT, bestLat = d, t, lat end
				end
			end
		end
	end
	Lighting.GeographicLatitude = bestLat
	Lighting.ClockTime = bestT
end

-- The grade's Lighting values (re-asserted by EnsureGrade if anything resets
-- them while the menu is up).
local GRADE = {
	Ambient = Color3.fromRGB(58, 48, 86), -- cool, dim fill: the foreground reads dark violet
	OutdoorAmbient = Color3.fromRGB(92, 72, 124),
	ColorShift_Top = Color3.fromRGB(150, 112, 96), -- warm key light (stronger blew the lit sides out to white)
	ColorShift_Bottom = Color3.fromRGB(60, 40, 100),
	Brightness = 1.15,
	ExposureCompensation = -0.2,
	EnvironmentDiffuseScale = 0.3,
}
local gradeSun: { ClockTime: number, GeographicLatitude: number }? = nil

local function setGrade()
	for k, v in pairs(GRADE) do (Lighting :: any)[k] = v end
	if gradeSun then
		Lighting.ClockTime = gradeSun.ClockTime
		Lighting.GeographicLatitude = gradeSun.GeographicLatitude
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm then
		-- Thin, coloured depth haze: far islands soften, nothing washes out.
		atm.Color = Color3.fromRGB(230, 150, 150)
		atm.Decay = Color3.fromRGB(80, 56, 124)
		atm.Density = 0.07
		atm.Haze = 0.4
		atm.Glare = 0.35
		atm.Offset = 0.2
	end
	for _, e in ipairs(gradeFx) do e:Destroy() end
	table.clear(gradeFx)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = Color3.fromRGB(255, 236, 228)
	cc.Saturation = 0.08
	cc.Contrast = 0.08
	cc.Brightness = -0.03
	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.6
	bloom.Size = 30
	bloom.Threshold = 0.95
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = 0.1
	rays.Spread = 0.55
	-- Hero sharpest, castle soft, far islands softer.
	local dof = Instance.new("DepthOfFieldEffect")
	dof.FocusDistance = 25
	dof.InFocusRadius = 12
	dof.FarIntensity = 0.16
	dof.NearIntensity = 0.25
	for _, e in ipairs({ cc, bloom, rays, dof } :: { Instance }) do
		e.Name = "MenuGrade"
		e.Parent = Lighting
		table.insert(gradeFx, e)
	end
end

local function applyGrade(sunDir: Vector3)
	if savedLighting then return end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	savedLighting = {
		Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, Brightness = Lighting.Brightness,
		ColorShift_Top = Lighting.ColorShift_Top, ColorShift_Bottom = Lighting.ColorShift_Bottom,
		ExposureCompensation = Lighting.ExposureCompensation, ClockTime = Lighting.ClockTime,
		GeographicLatitude = Lighting.GeographicLatitude, EnvironmentDiffuseScale = Lighting.EnvironmentDiffuseScale,
		atm = if atm then { Color = atm.Color, Decay = atm.Decay, Density = atm.Density, Haze = atm.Haze, Glare = atm.Glare, Offset = atm.Offset } else nil,
	}
	alignSun(sunDir)
	gradeSun = { ClockTime = Lighting.ClockTime, GeographicLatitude = Lighting.GeographicLatitude }
	setGrade()
end

-- Puts the menu's grade back if anything replaced the lighting or removed
-- its effects while the menu is up.
function MenuBackdrop.EnsureGrade()
	if not savedLighting then return end
	local ok = Lighting.Ambient == GRADE.Ambient and Lighting.Brightness == GRADE.Brightness and #gradeFx > 0
	for _, e in ipairs(gradeFx) do
		if e.Parent ~= Lighting then ok = false end
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm and math.abs(atm.Density - 0.07) > 0.001 then ok = false end
	if not ok then setGrade() end
end

local function clearGrade()
	for _, e in ipairs(gradeFx) do e:Destroy() end
	table.clear(gradeFx)
	gradeSun = nil
	local sv = savedLighting
	if not sv then return end
	savedLighting = nil
	for k, v in pairs(sv) do
		if k ~= "atm" then (Lighting :: any)[k] = v end
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm and sv.atm then
		for k, v in pairs(sv.atm) do (atm :: any)[k] = v end
	end
end

-- ── The runic halo: rings of glowing links with rune knots and sparkle ────
local haloRings: { { model: Model, center: CFrame, speed: number } } = {}
local ringParts: { { part: BasePart, base: number } } = {} -- faded in as the beam ignites
local function runeRing(parent: Instance, center: CFrame, radius: number, n: number, color: Color3, speed: number, k: number?)
	local m = Instance.new("Model")
	m.Name = "RuneRing"
	-- `k`: the ring's distance compression (keeps the links as thin as before).
	local thick = math.max(1.4 * (k or 1), radius / 110)
	for i = 1, n do
		local a = i / n * math.pi * 2
		local seg = part(m, { Size = Vector3.new(thick, thick, radius * 2 * math.pi / n * 0.8),
			CFrame = CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius) * CFrame.Angles(0, -a, 0),
			Color = color, Material = Enum.Material.Neon, Transparency = 0.15 })
		table.insert(ringParts, { part = seg, base = 0.15 })
		if i % 3 == 0 then
			local knot = part(m, { Size = Vector3.new(thick * 3, thick * 3, thick * 0.5), CFrame = seg.CFrame * CFrame.Angles(0, math.rad(90), math.rad(45)),
				Color = Color3.fromRGB(200, 220, 255), Material = Enum.Material.Neon })
			table.insert(ringParts, { part = knot, base = 0 })
		end
		if i % 6 == 0 then
			local att = Instance.new("Attachment")
			att.Parent = seg
			local e = Instance.new("ParticleEmitter")
			e.Texture = TEX_SPARK
			e.Color = ColorSequence.new(color)
			e.LightEmission = 1
			e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, thick * 2), NumberSequenceKeypoint.new(1, 0) })
			e.Lifetime = NumberRange.new(1.5, 3)
			e.Speed = NumberRange.new(1, 3)
			e.SpreadAngle = Vector2.new(180, 180)
			e.Rate = 6
			e.Parent = att
		end
	end
	for _, rp in ipairs(ringParts) do rp.part.Transparency = 1 end
	m.WorldPivot = CFrame.new()
	m:PivotTo(center)
	m.Parent = parent
	table.insert(haloRings, { model = m, center = center, speed = speed })
end

-- A low sun on the horizon: a soft glow and a bright band on the cloud sea.
local function sunset(parent: Instance, pos: Vector3)
	local near, k = compress(pos)
	local sun = part(parent, { Shape = Enum.PartType.Ball, Size = Vector3.one * 60 * k, CFrame = CFrame.new(near),
		Color = Color3.fromRGB(255, 200, 120), Material = Enum.Material.Neon })
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromScale(600 * k, 600 * k)
	bb.LightInfluence = 0
	bb.Parent = sun
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.Image = TEX_SPARK
	img.ImageColor3 = Color3.fromRGB(255, 160, 90)
	img.ImageTransparency = 0.35
	img.Parent = bb
end

-- ── The hero and the campfire circle ──────────────────────────────────────
-- Your character idles at your seat until you sit; party members who've
-- taken their seat (CampfireState) sit around the brazier, each in a different
-- pose. When everyone is ready a red portal tears open and they walk in.
local CastPoses: any = nil
pcall(function() CastPoses = require(script.Parent:WaitForChild("CastPoses", 5) :: any) end)
local ClassLook: any = nil
pcall(function() ClassLook = require(script.Parent:WaitForChild("ClassLook", 5) :: any) end)

local WALK_ANIM = "rbxassetid://109247200419554" -- the game's default walk (R6)
local PORTAL_RED = Color3.fromRGB(255, 40, 30)

-- Seats around the brazier, in the foreground frame (x right, -z into the
-- scene), each sat a different way. Seat 3 is up on the low ruined wall
-- (`ledge` studs up, `edge` studs out to its front edge). Players pick and
-- swap seats (CampfireManager keeps who sits where). The portal opens
-- behind the circle.
type SeatDef = { x: number, z: number, pose: string, ledge: number?, edge: number? }
local SEATS: { SeatDef } = {
	{ x = 4.6, z = -15.0, pose = "rock" },                         -- right of the fire, on a stone
	{ x = 1.2, z = -18.4, pose = "cross" },                        -- behind the fire, cross-legged
	{ x = -8.2, z = -20.8, pose = "ledge", ledge = 3.6, edge = 1.0 }, -- on the ruined wall, legs dangling
	{ x = -5.4, z = -11.8, pose = "lean" },                        -- front left, leaning back on the hands
}
local PORTAL_SPOT = { x = -3.5, z = -23 }

-- Poses in CastPoses' character-space degrees; `drop` lowers the body.
local POSES: { [string]: { drop: number, pose: { [string]: { number } } } } = {
	rock = { drop = 0.7, pose = { W = { -14, 0, 0 }, RH = { 62, 0, 6 }, LH = { 62, 0, -6 }, RS = { 48, 0, -6 }, LS = { 48, 0, 6 } } },
	cross = { drop = 1.45, pose = { W = { -6, 0, 0 }, RH = { 88, 0, 14 }, LH = { 88, 0, -14 }, RS = { 32, 0, -14 }, LS = { 32, 0, 14 } } },
	lean = { drop = 1.35, pose = { W = { 20, 0, 0 }, RH = { 70, 0, 6 }, LH = { 68, 0, -8 }, RS = { -38, 0, 14 }, LS = { -38, 0, -14 } } },
	ledge = { drop = 2.0, pose = { W = { -8, 0, 0 }, RH = { 22, 0, 4 }, LH = { 14, 0, -4 }, RS = { 38, 0, -8 }, LS = { 12, 0, 18 } } },
}

type FgInfo = { fg: Model, upright: (number, number, number, number?) -> CFrame, bowl: Vector3 }
local fgInfo: FgInfo? = nil

type Sitter = {
	model: Model, root: BasePart, hum: Humanoid, seat: number, pose: string, motors: any,
	seatCF: CFrame, lift: number, weight: number, walking: boolean, phase: number, rock: BasePart?,
	classId: string?, ledge: number,
}
local seatMarkers: { BasePart } = {}
local sitters: { [number]: Sitter } = {} -- by userId
local campMembers: { any } = {}
local poseConn: RBXScriptConnection? = nil
local portalConn: RBXScriptConnection? = nil
local portalRunning = false
local campfirePush = 0

local heroGround: CFrame? = nil
local heroHome: Instance? = nil
local heroHidden = false
local heroConns: { RBXScriptConnection } = {}
local heroRefresh: (() -> ())? = nil
local heroChanged: { (Model) -> () } = {}

-- The standing copy of you in the menu (class select dresses it).
function MenuBackdrop.Hero(): Model?
	return hero
end

-- cb(hero) whenever the copy is (re)made.
function MenuBackdrop.OnHeroChanged(cb: (Model) -> ())
	table.insert(heroChanged, cb)
end

-- A lobby-safe copy of a character: scripts, name tags, lights and sounds
-- stripped, non-colliding, root anchored. Not parented.
local function cloneCharacter(char: Model): (Model?, Humanoid?, BasePart?)
	if not char:FindFirstChildOfClass("Humanoid") or not char:FindFirstChild("HumanoidRootPart") then return nil, nil, nil end
	local was = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not clone then return nil, nil, nil end
	local h = clone :: Model
	-- No weapon from a past run: the copy is dressed by ClassLook (the class
	-- being shown), so a Tool still on the character would double up.
	for _, t in ipairs(h:GetChildren()) do
		if t:IsA("Tool") then t:Destroy() end
	end
	for _, d in ipairs(h:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("BillboardGui") or d:IsA("ForceField") or d:IsA("Sound") or d:IsA("Light") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Anchored = false
		end
	end
	local hum = h:FindFirstChildOfClass("Humanoid")
	local root = h:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then h:Destroy() return nil, nil, nil end
	root.Anchored = true
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	h.PrimaryPart = root
	if not hum:FindFirstChildOfClass("Animator") then
		Instance.new("Animator").Parent = hum
	end
	return h, hum, root
end

-- Height of the root above the ground when standing.
local function standLift(hum: Humanoid, root: BasePart): number
	return if hum.RigType == Enum.HumanoidRigType.R6 then root.Size.Y / 2 + 2 else hum.HipHeight + root.Size.Y / 2
end

local function playAnim(hum: Humanoid, id: string, fade: number?): AnimationTrack?
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return nil end
	local anim = Instance.new("Animation")
	anim.AnimationId = id
	local ok, track = pcall(function() return (animator :: Animator):LoadAnimation(anim) end)
	if not ok or not track then return nil end
	track.Looped = true
	track:Play(fade or 0.3)
	return track
end

-- Where the standing hero waits at seat i (three-quarters to the camera;
-- on top of the wall for the ledge seat).
local function standSpot(i: number): CFrame?
	local info = fgInfo
	if not info then return nil end
	local s = SEATS[math.clamp(i, 1, #SEATS)]
	return info.upright(s.x, -9, s.z, math.pi - 0.5) + Vector3.new(0, s.ledge or 0, 0)
end

local function cloneHero()
	if heroHidden or not heroGround or not heroHome or not heroHome.Parent then return end
	local char = Players.LocalPlayer.Character
	if not char then return end
	local h, hum, root = cloneCharacter(char)
	if not h or not hum or not root then return end
	h.Name = "MenuHero"
	h:PivotTo((heroGround :: CFrame) * CFrame.new(0, standLift(hum, root), 0))
	if hero then hero:Destroy() end
	h.Parent = heroHome
	hero = h
	playAnim(hum, HERO_IDLE)
	-- Dressed as your chosen class (class select previews over this).
	local player = Players.LocalPlayer
	local classId = player:GetAttribute("SelectedClass")
	if ClassLook and typeof(classId) == "string" then
		ClassLook.Apply(h, classId, { armor = player:GetAttribute(`Armor_{classId}`) == true })
	end
	for _, cb in ipairs(heroChanged) do task.spawn(cb, h) end
end

-- Keeps the standing copy in step with your avatar: re-copied (debounced)
-- when the appearance finishes loading or clothes/cosmetics change.
local function heroShowcase()
	local player = Players.LocalPlayer
	local pending = false
	local function refresh()
		if pending then return end
		pending = true
		task.delay(0.6, function()
			pending = false
			cloneHero()
		end)
	end
	heroRefresh = refresh
	local function watch(char: Model)
		table.insert(heroConns, char.ChildAdded:Connect(refresh))
		table.insert(heroConns, char.ChildRemoved:Connect(refresh))
		refresh()
	end
	if player.Character then watch(player.Character) end
	table.insert(heroConns, player.CharacterAdded:Connect(watch))
	table.insert(heroConns, player.CharacterAppearanceLoaded:Connect(function() refresh() end))
end

local function setHeroHidden(v: boolean)
	heroHidden = v
	if v then
		if hero then hero:Destroy() end
		hero = nil
	elseif not hero and heroRefresh then
		heroRefresh()
	end
end

-- Seated poses are written every frame after the Animator (no tracks play
-- on a seated copy), with a slow breath on top.
local function stepPoses()
	if not CastPoses then return end
	local t = os.clock()
	for _, s in pairs(sitters) do
		if s.walking or not s.model.Parent then continue end
		local def = POSES[s.pose]
		local combined: { [Motor6D]: CFrame } = {}
		for key, m in pairs(s.motors) do
			local v = def.pose[key]
			local cf = if v then CastPoses.poseCF(v) else CFrame.identity
			if key == "W" then cf *= CFrame.Angles(math.rad(math.sin(t * 1.6 + s.phase) * 1.4), 0, 0) end
			cf = CFrame.identity:Lerp(cf, s.weight)
			combined[m.motor] = (combined[m.motor] or CFrame.identity) * (m.basis:Inverse() * cf * m.basis)
		end
		for motor, cf in pairs(combined) do motor.Transform = cf end
	end
end

-- A small tag over a seated hero: their class, and their name and level.
local function nameTag(model: Model, name: string, classId: string?, level: number?)
	local head = model:FindFirstChild("Head")
	if not head then return end
	local bb = Instance.new("BillboardGui")
	bb.Name = "CampfireTag"
	bb.Size = UDim2.fromOffset(170, 38)
	bb.StudsOffset = Vector3.new(0, 2.1, 0)
	bb.MaxDistance = 80
	bb.LightInfluence = 0
	bb.Adornee = head
	local bold = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
	local info = if classId then ClassData.GetClass(classId) else nil
	local c = Instance.new("TextLabel")
	c.BackgroundTransparency = 1
	c.Size = UDim2.new(1, 0, 0, 18)
	c.FontFace = bold
	c.TextSize = 14
	c.TextColor3 = GOLD
	c.TextStrokeTransparency = 0.4
	c.Text = if info then string.upper(info.name) else ""
	c.Parent = bb
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Position = UDim2.fromOffset(0, 18)
	n.Size = UDim2.new(1, 0, 0, 16)
	n.FontFace = bold
	n.TextSize = 12
	n.TextColor3 = Color3.fromRGB(232, 222, 204)
	n.TextStrokeTransparency = 0.5
	n.Text = if level then `{name}   •   LV {level}` else name
	n.Parent = bb
	bb.Parent = model
end

local function seatMember(userId: number, idx: number, classId: string?)
	local info = fgInfo
	local plr = Players:GetPlayerByUserId(userId)
	if not info or not plr then return end
	local char = plr.Character
	if not char then return end
	local h, hum, root = cloneCharacter(char)
	if not h or not hum or not root then return end
	local seat = SEATS[idx]
	local pos = info.upright(seat.x, -9, seat.z).Position + Vector3.new(0, seat.ledge or 0, 0)
	local toBowl = Vector3.new(info.bowl.X - pos.X, 0, info.bowl.Z - pos.Z).Unit
	pos += toBowl * (seat.edge or 0)
	local facing = CFrame.lookAt(pos, pos + toBowl)
	local def = POSES[seat.pose]
	local lift = standLift(hum, root)
	h.Name = "Sitter_" .. userId
	h:PivotTo(facing * CFrame.new(0, lift - def.drop, 0))
	h.Parent = info.fg
	local rock = if seat.pose == "rock" then part(info.fg, { Size = Vector3.new(1.9, 1.3, 1.6), CFrame = facing * CFrame.new(0, 0.65, 0.25),
		Color = Color3.fromRGB(62, 54, 78), Material = Enum.Material.Slate }) else nil
	-- Their class: weapon in hand, and armor if they own and wear it.
	if ClassLook and classId then
		-- Swords are slung across the back while they sit; anything else
		-- rests in the hand (out toward the fire), the seat's pose driving the
		-- arms.
		ClassLook.Apply(h, classId, {
			armor = plr:GetAttribute(`Armor_{classId}`) == true,
			handTilt = CFrame.identity,
			onBack = ClassLook.SWORD_CLASSES[classId] == true,
		})
	end
	nameTag(h, plr.DisplayName, classId, plr:GetAttribute("AccountLevel"))
	sitters[userId] = {
		model = h, root = root, hum = hum, seat = idx, pose = seat.pose,
		motors = if CastPoses then CastPoses.resolveMotors(h) else {},
		seatCF = facing, lift = lift, weight = 1, walking = false, phase = rng:NextNumber(0, 6.28), rock = rock,
		classId = classId, ledge = seat.ledge or 0,
	}
	if not poseConn then poseConn = RunService.Stepped:Connect(stepPoses) end
end

-- Match the circle to the latest CampfireState members list.
local function refreshCampfire()
	if not fgInfo or portalRunning then return end
	local me = Players.LocalPlayer.UserId
	local wanted: { [number]: number } = {}
	local classOf: { [number]: string? } = {}
	local used: { [number]: boolean } = {}
	for i, m in ipairs(campMembers) do
		local seat = if typeof(m.seat) == "number" then m.seat else i
		if m.seated and seat >= 1 and seat <= #SEATS then
			wanted[m.userId] = seat
			classOf[m.userId] = m.classId
			used[seat] = true
		end
	end
	-- Your seat, or the first free one while you're still choosing.
	local myIdx = wanted[me]
	if not myIdx then
		myIdx = 1
		for i = 1, #SEATS do
			if not used[i] then
				myIdx = i
				break
			end
		end
	end
	-- Re-seat anyone who moved seats or changed class.
	for uid, s in pairs(sitters) do
		if wanted[uid] ~= s.seat or classOf[uid] ~= s.classId then
			s.model:Destroy()
			if s.rock then s.rock:Destroy() end
			sitters[uid] = nil
		end
	end
	for uid, idx in pairs(wanted) do
		if not sitters[uid] then seatMember(uid, idx, classOf[uid]) end
	end
	-- Your standing copy waits at your seat until you sit down.
	heroGround = standSpot(myIdx)
	if hero and heroGround then
		local hum = hero:FindFirstChildOfClass("Humanoid")
		local root = hero.PrimaryPart
		if hum and root then hero:PivotTo((heroGround :: CFrame) * CFrame.new(0, standLift(hum, root), 0)) end
	end
	setHeroHidden(wanted[me] ~= nil)
	-- While you're seated, the empty seats glow faintly: click one to move.
	for _, m in ipairs(seatMarkers) do m:Destroy() end
	table.clear(seatMarkers)
	local info = fgInfo
	if info and wanted[me] then
		for i = 1, #SEATS do
			local spot = standSpot(i)
			if spot and not used[i] then
				table.insert(seatMarkers, part(info.fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 1.8, 1.8),
					CFrame = CFrame.new(spot.Position + Vector3.new(0, 0.06, 0)) * UP, Color = Color3.fromRGB(200, 150, 80), Material = Enum.Material.Neon, Transparency = 0.8 }))
			end
		end
	end
end

-- The seat under a screen point (viewport pixels), if one is close.
function MenuBackdrop.SeatAtScreen(pos: Vector2): number?
	local cam = Workspace.CurrentCamera
	if not cam or not fgInfo then return nil end
	local best, bestD = nil, 90
	for i = 1, #SEATS do
		local spot = standSpot(i)
		if spot then
			local p, onScreen = cam:WorldToViewportPoint(spot.Position + Vector3.new(0, 2, 0))
			local d = (Vector2.new(p.X, p.Y) - pos).Magnitude
			if onScreen and d < bestD then best, bestD = i, d end
		end
	end
	return best
end

function MenuBackdrop.SetCampfire(members: { any })
	campMembers = members
	refreshCampfire()
end

-- Class select: a front view of the standing hero, from the title camera's
-- side so the scene stays behind them.
function MenuBackdrop.HeroView(): CFrame?
	local v = vista
	if not v then return nil end
	local root = hero and hero.PrimaryPart
	local base = if root then root.Position elseif heroGround then (heroGround :: CFrame).Position + Vector3.new(0, 3, 0) else nil
	if not base then return nil end
	local toCam = Vector3.new(v.Position.X - base.X, 0, v.Position.Z - base.Z).Unit
	return CFrame.lookAt(base + toCam * 11 + Vector3.new(0, 1.2, 0), base + Vector3.new(0, 0.5, 0))
end

-- The camera shot while gathered: a little closer and lower than the title
-- shot, looking down at the circle; it pushes toward the portal as it opens.
function MenuBackdrop.CampfireView(): CFrame?
	local v = vista
	if not v then return nil end
	return v * CFrame.new(0.4 - 0.6 * campfirePush, -1.4, -5 - 1.5 * campfirePush) * CFrame.Angles(math.rad(-7), 0, 0)
end

-- ── The red portal ─────────────────────────────────────────────────────────
type Portal = { model: Model, center: CFrame, mesh: SpecialMesh, innerMesh: SpecialMesh, light: PointLight,
	rim: { BasePart }, floor: BasePart, swirl: ParticleEmitter, sparks: ParticleEmitter }

local function buildPortal(parent: Instance, center: CFrame): Portal
	local m = Instance.new("Model")
	m.Name = "RedPortal"
	m.Parent = parent
	-- A glowing red rim (the outer ellipse) around a dark rift (the inner
	-- ellipse, toward the camera), with a swirl of red smoke over it.
	local core = part(m, { Size = Vector3.one, CFrame = center, Color = Color3.fromRGB(190, 18, 16), Material = Enum.Material.Neon, Transparency = 0.3 })
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(0, 0, 0.15)
	mesh.Parent = core
	local inner = part(m, { Size = Vector3.one, CFrame = center * CFrame.new(0, 0, 0.12), Color = Color3.fromRGB(12, 0, 5), Material = Enum.Material.Neon })
	local innerMesh = Instance.new("SpecialMesh")
	innerMesh.MeshType = Enum.MeshType.Sphere
	innerMesh.Scale = Vector3.new(0, 0, 0.15)
	innerMesh.Parent = inner
	local rim: { BasePart } = {}
	local n = 40
	for i = 1, n do
		local a, a2 = i / n * math.pi * 2, (i + 1) / n * math.pi * 2
		local p = Vector3.new(math.cos(a) * 3.4, math.sin(a) * 4.8, 0)
		local q = Vector3.new(math.cos(a2) * 3.4, math.sin(a2) * 4.8, 0)
		table.insert(rim, part(m, { Size = Vector3.new(0.35, 0.35, (q - p).Magnitude * 1.08), CFrame = center * CFrame.lookAt((p + q) / 2, q),
			Color = PORTAL_RED, Material = Enum.Material.Neon, Transparency = 1 }))
	end
	local plane = part(m, { Size = Vector3.new(5.2, 7.8, 0.2), CFrame = center * CFrame.new(0, 0, 0.3), Transparency = 1 })
	local swirl = Instance.new("ParticleEmitter")
	swirl.Texture = TEX_SMOKE
	swirl.Color = ColorSequence.new(Color3.fromRGB(255, 70, 50), Color3.fromRGB(120, 0, 10))
	swirl.LightEmission = 0.9
	swirl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.4), NumberSequenceKeypoint.new(1, 0.6) })
	swirl.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.35), NumberSequenceKeypoint.new(1, 1) })
	swirl.Lifetime = NumberRange.new(0.6, 1.1)
	swirl.Speed = NumberRange.new(0.3, 0.8)
	swirl.Rotation = NumberRange.new(0, 360)
	swirl.RotSpeed = NumberRange.new(160, 260)
	swirl.Rate = 70
	swirl.Enabled = false
	swirl.Parent = plane
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = TEX_SPARK
	sparks.Color = ColorSequence.new(Color3.fromRGB(255, 200, 150), PORTAL_RED)
	sparks.LightEmission = 1
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.5, 1.2)
	sparks.Speed = NumberRange.new(2, 6)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Acceleration = Vector3.new(0, 3, 0)
	sparks.Rate = 40
	sparks.Enabled = false
	sparks.Parent = plane
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 60, 40)
	light.Range = 0
	light.Brightness = 1.6
	light.Parent = core
	local floor = part(m, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 8, 8), CFrame = center * CFrame.new(0, -4.7, 1) * UP,
		Color = PORTAL_RED, Material = Enum.Material.Neon, Transparency = 1 })
	return { model = m, center = center, mesh = mesh, innerMesh = innerMesh, light = light, rim = rim, floor = floor, swirl = swirl, sparks = sparks }
end

-- One hero stands up, walks to the portal and is pulled in.
local function walkIn(s: Sitter, portalGround: Vector3, standTime: number, walkTime: number)
	local def = POSES[s.pose]
	-- Stand up: the pose relaxes as the body rises.
	local w = Instance.new("NumberValue")
	w.Value = 1
	w.Changed:Connect(function(v)
		s.weight = v
		if s.root.Parent then s.root.CFrame = s.seatCF * CFrame.new(0, s.lift - def.drop * v, 0) end
	end)
	TweenService:Create(w, TweenInfo.new(standTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Value = 0 }):Play()
	task.wait(standTime)
	if not s.model.Parent then return end
	s.walking = true
	for _, m in pairs(s.motors) do m.motor.Transform = CFrame.identity end
	playAnim(s.hum, WALK_ANIM, 0.15)
	local from = s.root.Position
	local walkDur = math.max(0.3, walkTime - 0.4)
	if s.ledge > 0 then
		-- Hop down off the wall first.
		local ahead = Vector3.new(portalGround.X - from.X, 0, portalGround.Z - from.Z).Unit
		local down = from + ahead * 1.6 - Vector3.new(0, s.ledge, 0)
		TweenService:Create(s.root, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = CFrame.lookAt(down, down + ahead) }):Play()
		task.wait(0.3)
		if not s.model.Parent then return end
		from = down
		walkDur = math.max(0.3, walkDur - 0.3)
	end
	local to = Vector3.new(portalGround.X, from.Y, portalGround.Z)
	s.root.CFrame = CFrame.lookAt(from, to)
	TweenService:Create(s.root, TweenInfo.new(walkDur, Enum.EasingStyle.Linear), { CFrame = CFrame.lookAt(to, to + (to - from).Unit) }):Play()
	task.wait(walkDur)
	if not s.model.Parent then return end
	-- Pulled in: shrink and fade with a burst of red sparks.
	local burst = part(s.model.Parent :: Instance, { Size = Vector3.one, CFrame = s.root.CFrame, Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SPARK
	e.Color = ColorSequence.new(Color3.fromRGB(255, 200, 150), PORTAL_RED)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.4, 0.8)
	e.Speed = NumberRange.new(4, 10)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Enabled = false
	e.Parent = burst
	e:Emit(40)
	local sc = Instance.new("NumberValue")
	sc.Value = 1
	sc.Changed:Connect(function(v)
		if s.model.Parent then
			pcall(function() s.model:ScaleTo(math.max(v, 0.05)) end)
			for _, d in ipairs(s.model:GetDescendants()) do
				if d:IsA("BasePart") then d.LocalTransparencyModifier = 1 - v end
			end
		end
	end)
	TweenService:Create(sc, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Value = 0.05 }):Play()
	task.wait(0.42)
	s.model:Destroy()
	task.delay(1, function() burst:Destroy() end)
end

-- Plays the portal from `p.portalAt` (server time): it opens, the heroes
-- walk in one after another in seat order, then it flares.
function MenuBackdrop.OpenPortal(p: any)
	local info = fgInfo
	if not info or portalRunning or typeof(p.portalAt) ~= "number" then return end
	portalRunning = true
	local open, stagger, walk = tonumber(p.open) or 1.1, tonumber(p.stagger) or 0.5, tonumber(p.walk) or 1.9
	local order: { number } = {}
	for _, m in ipairs(p.members or {}) do
		if m.seated then table.insert(order, m.userId) end
	end
	task.delay(math.max(0, p.portalAt - Workspace:GetServerTimeNow()), function()
		if fgInfo ~= info then return end
		local ground = info.upright(PORTAL_SPOT.x, -9, PORTAL_SPOT.z)
		local portal = buildPortal(info.fg, ground * CFrame.new(0, 4.9, 0))
		local flareAt = open + stagger * math.max(#order - 1, 0) + walk
		local t0 = os.clock()
		local push = Instance.new("NumberValue")
		push.Changed:Connect(function(v) campfirePush = v end)
		TweenService:Create(push, TweenInfo.new(flareAt + 0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut), { Value = 1 }):Play()
		portalConn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			local k = math.clamp(t / open, 0, 1)
			local e = if k < 1 then 1 + 2.70158 * (k - 1) ^ 3 + 1.70158 * (k - 1) ^ 2 else 1 -- back-out
			local pulse = 1 + math.sin(t * 6) * 0.025
			local flare = math.clamp((t - flareAt) / 0.35, 0, 1)
			local size = e * pulse * (1 + 0.3 * flare)
			portal.mesh.Scale = Vector3.new(6.8 * size, 9.6 * size, 0.15)
			portal.innerMesh.Scale = Vector3.new(5.5 * size, 8.0 * size, 0.15)
			portal.light.Range = 16 * e
			portal.light.Brightness = 1.6 + 5 * flare
			portal.floor.Transparency = 1 - 0.55 * e
			for i, seg in ipairs(portal.rim) do
				seg.Transparency = if i / #portal.rim <= k * 1.15 then 0.05 else 1
			end
			portal.swirl.Enabled = k > 0.4
			portal.sparks.Enabled = k > 0.2
		end)
		for i, uid in ipairs(order) do
			task.delay(open + stagger * (i - 1), function()
				local s = sitters[uid]
				if s and s.model.Parent then walkIn(s, ground.Position, 0.35, walk - 0.35) end
			end)
		end
	end)
end

-- ── Foreground: the hero platform, lower right of the frame ───────────────
-- Laid out in the frame `cam` (x right, -z into the scene). A prop authored
-- at height y sits y + 9 above the platform surface under it.
local function buildForeground(parent: Instance, cam: CFrame)
	local fg = Instance.new("Model")
	fg.Name = "TitleForeground"
	fg.Parent = parent
	local flatCam = CFrame.new(cam.Position) * CFrame.Angles(0, select(2, cam:ToEulerAnglesYXZ()), 0)

	-- The hero platform: a dark rock shelf floored with ruined flagstones,
	-- moss showing through the gaps, stepping down at the front edge. Its
	-- surface is at y = -6 in the camera frame.
	local ledge = Instance.new("Model")
	ledge.Name = "HeroPlatform"
	ledge.Parent = fg
	local G = CFrame.new((cam * CFrame.new(0, -6, 0)).Position) * flatCam.Rotation
	local ROCK = Color3.fromRGB(44, 38, 58)
	for _ = 1, 7 do
		local h = rng:NextNumber(8, 12)
		part(ledge, { Size = Vector3.new(rng:NextNumber(10, 16), h, rng:NextNumber(8, 14)),
			CFrame = G * CFrame.new(rng:NextNumber(-16, 18), -h / 2 - 0.3, rng:NextNumber(-30, -13)) * CFrame.Angles(0, rng:NextNumber(-0.4, 0.4), 0),
			Color = ROCK, Material = Enum.Material.Slate })
	end
	-- Two broken steps down at the front edge.
	part(ledge, { Size = Vector3.new(26, 1.2, 3), CFrame = G * CFrame.new(3, -0.9, -10.3) * CFrame.Angles(0, 0.04, 0), Color = ROCK, Material = Enum.Material.Slate })
	part(ledge, { Size = Vector3.new(22, 1.2, 3), CFrame = G * CFrame.new(4, -2.1, -8.2) * CFrame.Angles(0, -0.05, 0), Color = ROCK, Material = Enum.Material.Slate })
	part(ledge, { Size = Vector3.new(36, 0.4, 20), CFrame = G * CFrame.new(1, -0.25, -21), Color = MOSS, Material = Enum.Material.Grass })
	for gx = -16, 17, 3.6 do
		for gz = -12, -29, -3.6 do
			if rng:NextNumber() > 0.16 then
				local k = rng:NextNumber()
				local tilt = if rng:NextNumber() < 0.12 then rng:NextNumber(0.08, 0.2) else 0
				part(ledge, { Size = Vector3.new(rng:NextNumber(3, 3.5), 0.5, rng:NextNumber(3, 3.5)),
					CFrame = G * CFrame.new(gx + rng:NextNumber(-0.2, 0.2), rng:NextNumber(-0.08, 0.1) + tilt, gz + rng:NextNumber(-0.2, 0.2))
						* CFrame.Angles(tilt, rng:NextNumber(-0.08, 0.08), tilt * 0.5),
					Color = Color3.fromRGB(66 + 20 * k, 58 + 18 * k, 82 + 18 * k), Material = Enum.Material.Slate })
			end
		end
	end
	for _, d in ipairs(ledge:GetDescendants()) do
		if d:IsA("BasePart") then d.CanQuery = true end
	end
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { ledge }
	local fallbackY = G.Position.Y
	local function upright(x: number, y: number, z: number, yaw: number?): CFrame
		local p = (cam * CFrame.new(x, y, z)).Position
		local hit = Workspace:Raycast(Vector3.new(p.X, fallbackY + 40, p.Z), Vector3.new(0, -120, 0), rp)
		local g = if hit then hit.Position.Y else fallbackY
		return CFrame.new(p.X, g + (y + 9), p.Z) * flatCam.Rotation * CFrame.Angles(0, yaw or 0, 0)
	end
	local function block(x: number, z: number, sx: number, sy: number, sz: number, yaw: number, lift: number?)
		part(fg, { Size = Vector3.new(sx, sy, sz), CFrame = upright(x, -9 + sy / 2 + (lift or 0), z, yaw) * CFrame.Angles(0, 0, rng:NextNumber(-0.05, 0.05)),
			Color = RUIN, Material = Enum.Material.Slate })
	end

	-- Ruined walls framing the left, a dark silhouette behind the menu.
	block(-13.5, -23, 3, 11, 2.4, 0.3)
	block(-12.5, -22.4, 6, 1.3, 2.6, 0.3, 11)
	block(-10.4, -21.6, 2.6, 7, 2.2, 0.3)
	block(-8.2, -20.8, 2.2, 3.6, 2.1, 0.3)
	block(-16.5, -24, 2.6, 6, 2.2, 0.35)
	for _, spot in ipairs({ { -6.5, -18 }, { 13, -21 }, { 0.5, -22 } }) do
		local s = rng:NextNumber(0.8, 1.3)
		block(spot[1], spot[2], s * 1.3, s, s, rng:NextNumber(0, 6.28))
	end

	-- The brazier: an iron bowl on a tripod, a living fire, embers, warm light.
	local IRON = Color3.fromRGB(40, 30, 28)
	local bowlCF = upright(0.5, -6.4, -13.5)
	part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.8, 2.8), CFrame = bowlCF * UP, Color = IRON, Material = Enum.Material.Metal })
	part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 3.1, 3.1), CFrame = bowlCF * CFrame.new(0, 0.45, 0) * UP, Color = IRON, Material = Enum.Material.Metal })
	local coals = part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 2.3, 2.3),
		CFrame = bowlCF * CFrame.new(0, 0.4, 0) * UP, Color = Color3.fromRGB(255, 120, 40), Material = Enum.Material.Neon })
	for i = 0, 2 do
		local a = i * 2.094
		part(fg, { Size = Vector3.new(0.22, 2.9, 0.22), CFrame = bowlCF * CFrame.Angles(0, a, 0) * CFrame.new(0, -1.3, 0.75) * CFrame.Angles(math.rad(-18), 0, 0),
			Color = IRON, Material = Enum.Material.Metal })
	end
	local fire = Instance.new("Fire")
	fire.Color = Color3.fromRGB(255, 150, 50)
	fire.SecondaryColor = Color3.fromRGB(220, 50, 10)
	fire.Size = 4
	fire.Heat = 9
	fire.Parent = coals
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 70)
	glow.Range = 16
	glow.Brightness = 1.3
	glow.Parent = coals
	local sparkAtt = Instance.new("Attachment")
	sparkAtt.Parent = coals
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = TEX_SPARK
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 90, 30))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(1.2, 2.4)
	embers.Speed = NumberRange.new(2, 4)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Acceleration = Vector3.new(1.5, 2, 0)
	embers.Rate = 12
	embers.Parent = sparkAtt
	-- Floating embers drifting over the whole platform.
	local drift = part(fg, { Size = Vector3.new(16, 1, 9), CFrame = upright(2, -7, -15), Transparency = 1 })
	local de = embers:Clone()
	de.Rate = 5
	de.Lifetime = NumberRange.new(3, 5)
	de.Speed = NumberRange.new(0.5, 2)
	de.Acceleration = Vector3.new(0.8, 1.2, 0)
	de.SpreadAngle = Vector2.new(60, 60)
	de.Parent = drift

	-- The longsword, planted point-down beside the fire, leaning slightly.
	pcall(function()
		local SwordModel = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SwordModel") :: any)
		local tool = SwordModel.Build()
		local bladeUp = tool:GetAttribute("BladeAxis") == "+Y"
		local sword = Instance.new("Model")
		sword.Name = "PlantedSword"
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		for _, d in ipairs(tool:GetDescendants()) do
			if d:IsA("BasePart") then
				d.Anchored = true
				d.CanCollide = false
			end
		end
		for _, c in ipairs(tool:GetChildren()) do
			if c:IsA("BasePart") then c.Parent = sword end
		end
		tool:Destroy()
		if handle then
			sword.PrimaryPart = handle
			-- Point the blade down, a little tilted: the asset's blade runs up
			-- the handle's +Y, the built fallback's along -Z.
			local down = if bladeUp then CFrame.Angles(math.rad(180 - 12), 0, math.rad(8))
				else CFrame.Angles(math.rad(-90 + 12), 0, math.rad(8))
			sword:PivotTo(upright(6.7, -3.4, -14.2, 0.5) * down) -- beside seat 1, clear of the circle
			pcall(function() sword:ScaleTo(1.6) end)
		end
		sword.Parent = fg
	end)

	-- The campfire circle: your hero waits standing at your seat (three-
	-- quarters to the camera) until you sit; the party sits around the fire.
	fgInfo = { fg = fg, upright = upright, bowl = bowlCF.Position }
	heroHome = fg
	heroGround = standSpot(1)
	heroShowcase()
	refreshCampfire()
	-- A cool rim light from behind the circle.
	local rim = part(fg, { Size = Vector3.one, CFrame = upright(6.4, -4, -18.5), Transparency = 1 })
	local rl = Instance.new("PointLight")
	rl.Color = Color3.fromRGB(160, 140, 255)
	rl.Range = 9
	rl.Brightness = 1.4
	rl.Parent = rim
end

-- ── Opening sequence ────────────────────────────────────────────────────────
local revealedAt: number? = nil
local revealWaiters: { (number) -> () } = {}
local function markRevealed()
	revealedAt = os.clock()
	local list = revealWaiters
	revealWaiters = {}
	for _, cb in ipairs(list) do task.spawn(cb, 0) end
end

-- cb(secondsSinceReveal) runs once the black cover starts lifting.
function MenuBackdrop.OnRevealed(cb: (number) -> ())
	if revealedAt then
		task.spawn(cb, os.clock() - (revealedAt :: number))
	else
		table.insert(revealWaiters, cb)
	end
end

-- Starts the opening sequence (the beam ignites, then the title UI).
-- MenuLoader calls this as its loading screen starts to lift.
function MenuBackdrop.Reveal()
	if not revealedAt then markRevealed() end
end

-- Whether the scene is still whole: the folder is in the world and hasn't
-- lost a big share of what was built (MenuLoader's watchdog rebuilds if not).
local builtCount = 0
function MenuBackdrop.Folder(): Folder?
	return folder
end
function MenuBackdrop.IsHealthy(): boolean
	local f = folder
	if not f or f.Parent ~= Workspace or not vista then return false end
	if builtCount > 0 and #f:GetDescendants() < builtCount * 0.7 then return false end
	return true
end

-- ── Build ───────────────────────────────────────────────────────────────────
function MenuBackdrop.Build(_focus: Vector3?)
	MenuBackdrop.Destroy()
	local f = Instance.new("Folder")
	f.Name = "MenuBackdrop"
	f.Parent = Workspace
	folder = f

	local camPos, target = CAM_FROM, CAM_TO
	compressOrigin = camPos
	vista = CFrame.lookAt(camPos, target)
	local fwd = Vector3.new(target.X - camPos.X, 0, target.Z - camPos.Z).Unit
	local function dirAt(yawDeg: number): Vector3 -- + = left of centre, - = right
		return CFrame.Angles(0, math.rad(yawDeg), 0) * fwd
	end
	-- Keep clear of the camera and the lobby spawn (class select shows you there).
	local keepClear = { camPos, LOBBY_SPAWN }
	local function clear(pos: Vector3, radius: number): boolean
		for _, p in ipairs(keepClear) do
			if (Vector3.new(pos.X - p.X, 0, pos.Z - p.Z)).Magnitude < radius then return false end
		end
		return true
	end
	-- Everything generated claims a footprint (centre + radius, measured flat
	-- so tall castles can't poke into islands above/below); nothing overlaps.
	local occupied: { { p: Vector3, r: number } } = {}
	local function free(pos: Vector3, r: number): boolean
		for _, o in ipairs(occupied) do
			if (Vector3.new(pos.X - o.p.X, 0, pos.Z - o.p.Z)).Magnitude < r + o.r + 12 then return false end
		end
		return true
	end
	local function claim(pos: Vector3, r: number)
		table.insert(occupied, { p = pos, r = r })
	end

	-- Sunset grade, the real sun low on the horizon to the right.
	local sunDir = (dirAt(-40) + Vector3.new(0, 0.1, 0)).Unit
	applyGrade(sunDir)
	sunset(f, camPos + sunDir * 2600)

	-- The capital: right of centre, far off and massive. Kept within ~600
	-- studs (farther parts drop out at lower graphics settings); its size
	-- does the work.
	local capScale = 3.4
	local spireFar = camPos + dirAt(-19) * 600 + Vector3.new(0, -20, 0)
	place("spire", spireFar, capScale)
	claim(spireFar, 68 * capScale / 2 + 30)
	-- Where it's actually built (see compress), for the beam and the halo.
	local spirePos, ck = compress(spireFar)
	local s = 68 * capScale * ck / 44
	-- The pillar of light rising from the great spire's tip.
	local tip = spirePos + Vector3.new(0, 45 * s, 0)
	local beamLen = 2048 * ck
	beamCore = part(f, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(beamLen, 1.4 * s, 1.4 * s),
		CFrame = CFrame.new(tip + Vector3.new(0, beamLen / 2, 0)) * UP, Color = GOLD, Material = Enum.Material.Neon, Transparency = 1 })
	beamSheath = part(f, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(beamLen, 4.5 * s, 4.5 * s),
		CFrame = CFrame.new(tip + Vector3.new(0, beamLen / 2, 0)) * UP, Color = Color3.fromRGB(255, 170, 70), Material = Enum.Material.Neon, Transparency = 1 })
	local rise = Instance.new("ParticleEmitter")
	rise.Texture = TEX_SPARK
	rise.Color = ColorSequence.new(GOLD)
	rise.LightEmission = 1
	rise.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6 * s), NumberSequenceKeypoint.new(1, 0) })
	rise.Lifetime = NumberRange.new(4, 7)
	rise.Speed = NumberRange.new(30 * ck, 60 * ck)
	rise.EmissionDirection = Enum.NormalId.Right
	rise.Rate = 25
	rise.Enabled = false
	rise.Parent = beamSheath
	beamRise = rise
	-- The runic halo above the castle, two counter-spinning rings.
	local tilt = CFrame.Angles(math.rad(10), 0, math.rad(-4))
	runeRing(f, CFrame.new(spirePos + Vector3.new(0, 40 * s, 0)) * tilt, 34 * s, 96, Color3.fromRGB(110, 150, 255), 0.08, ck)
	runeRing(f, CFrame.new(spirePos + Vector3.new(0, 42 * s, 0)) * tilt, 30 * s, 84, Color3.fromRGB(170, 130, 255), -0.12, ck)

	-- Foreground: the hero platform just ahead of and below the camera.
	buildForeground(f, vista :: CFrame * CFrame.new(0, -3, -10))
	claim((vista :: CFrame * CFrame.new(4, 0, -30)).Position, 45)

	-- Mid-distance islands spread across the view, out of the line to the
	-- capital; the farther ones are bigger so none shrink to specks.
	local kinds = { "keep", "ruin", "keep", "ruin", "keep", "ruin", "keep", "ruin", "keep" }
	local placed = 0
	local tries = 0
	while placed < #kinds and tries < 800 do
		tries += 1
		local yaw = rng:NextNumber(-44, 22) -- right of the menu (it covers ~+19° to +45°)
		local dist = rng:NextNumber(220, 560)
		local pos = camPos + dirAt(yaw) * dist + Vector3.new(0, rng:NextNumber(-0.19, 0.03) * dist, 0)
		local scale = rng:NextNumber(1.6, 3.2) * dist / 450
		local R = 22 * scale
		local footprint = R
		if clear(pos, 150 + R) and math.abs(yaw + 19) > 13 and free(pos, footprint) then
			claim(pos, footprint)
			placed += 1
			place(kinds[placed], pos, scale)
		end
	end

	-- Small spiked shards drifting high and low through the sky.
	local shards = 0
	for _ = 1, 60 do
		if shards >= 12 then break end
		local dist = rng:NextNumber(260, 620)
		local pos = camPos + dirAt(rng:NextNumber(-46, 16)) * dist + Vector3.new(0, rng:NextNumber(-0.05, 0.4) * dist, 0)
		local w = rng:NextNumber(10, 24) * dist / 500
		if clear(pos, 150) and free(pos, w * 0.6) then
			claim(pos, w * 0.6)
			shard(pos, w)
			shards += 1
		end
	end

	-- A cloud sea well below the islands, and a few banks far behind them.
	for i = 1, 8 do
		local yaw = -90 + (i - 1) * (180 / 7)
		cloudBank(f, camPos + dirAt(yaw) * 460 + Vector3.new(0, -260, 0), 420, 170, 1.0)
	end
	for i = 1, 4 do
		local yaw = -60 + (i - 1) * 40
		cloudBank(f, camPos + dirAt(yaw) * 780 + Vector3.new(0, -120, 0), 260, 200, 0.4)
	end
	-- Stars twinkling in the upper sky.
	local starPos, sk = compress(camPos + fwd * 650 + Vector3.new(0, 420, 0))
	local starField = part(f, { Size = Vector3.new(1400 * sk, 1, 500 * sk), CFrame = CFrame.new(starPos), Transparency = 1 })
	local stars = Instance.new("ParticleEmitter")
	stars.Texture = TEX_SPARK
	stars.Color = ColorSequence.new(Color3.fromRGB(220, 230, 255))
	stars.LightEmission = 1
	stars.Size = NumberSequence.new(3 * sk)
	stars.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.1), NumberSequenceKeypoint.new(1, 1) })
	stars.Lifetime = NumberRange.new(2, 4)
	stars.Speed = NumberRange.new(0)
	stars.Rate = 30
	stars.Parent = starField
	-- Golden motes drifting across in front of the camera.
	local motes = part(f, { Size = Vector3.new(120, 2, 120), CFrame = CFrame.new(camPos + fwd * 70 - Vector3.new(0, 30, 0)), Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SPARK
	e.Color = ColorSequence.new(GOLD, Color3.fromRGB(255, 240, 220))
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(8, 12)
	e.Speed = NumberRange.new(2, 5)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(25, 25)
	e.Rate = 12
	e.Parent = motes

	builtCount = #f:GetDescendants()

	-- Keep it alive.
	local t0 = os.clock()
	local ringsDone = false
	local frame = 0
	conn = RunService.RenderStepped:Connect(function()
		frame += 1
		local now = os.clock()
		local t = now - t0
		local since = if revealedAt then now - (revealedAt :: number) else -1
		-- Opening: the beam ignites and the halo lights (0.4–1.0s). The islands
		-- and castles are already in place, fully loaded, when the loading
		-- screen lifts.
		local ign = if since < 0 then 0 else math.clamp((since - 0.4) / 0.6, 0, 1)
		-- The islands bob slowly, so each one only needs moving every third
		-- frame (staggered).
		for i, fl in ipairs(floaters) do
			if fl.model.Parent and (i + frame) % 3 == 0 then
				local bob = math.sin(t * fl.speed + fl.phase) * fl.amp
				fl.model:PivotTo(fl.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * fl.yaw, math.sin(t * fl.speed * 0.7 + fl.phase) * 0.012))
			end
		end
		for _, r in ipairs(haloRings) do
			if r.model.Parent then r.model:PivotTo(r.center * CFrame.Angles(0, t * r.speed, 0)) end
		end
		if not ringsDone then
			for _, rp in ipairs(ringParts) do
				rp.part.Transparency = 1 - (1 - rp.base) * ign
			end
			ringsDone = ign >= 1
		end
		if beamCore and beamSheath then
			local pulse = 0.25 + math.sin(t * 1.3) * 0.12
			beamCore.Transparency = 1 - (1 - pulse) * ign
			beamSheath.Transparency = 1 - 0.22 * ign
			if beamRise then beamRise.Enabled = ign > 0.5 end
		end
		-- Castle windows flicker like candlelight.
		if #windows > 0 then
			for _ = 1, 6 do
				local w = windows[rng:NextInteger(1, #windows)]
				if w.Parent then w.Transparency = rng:NextNumber(0, 0.45) end
			end
		end
	end)
end

function MenuBackdrop.Destroy()
	if conn then conn:Disconnect() conn = nil end
	if poseConn then poseConn:Disconnect() poseConn = nil end
	if portalConn then portalConn:Disconnect() portalConn = nil end
	for _, c in ipairs(heroConns) do c:Disconnect() end
	table.clear(heroConns)
	table.clear(sitters)
	table.clear(seatMarkers)
	fgInfo, heroGround, heroHome, heroRefresh = nil, nil, nil, nil
	-- (a run started from the campfire: you were seated, so your standing
	-- copy was hidden. Coming back to the menu you're standing again, and
	-- the old circle is stale until the server sends the new one; kept, they
	-- left the menu with no hero at all, or the old seated copy.)
	heroHidden = false
	campMembers = {}
	portalRunning = false
	campfirePush = 0
	table.clear(floaters)
	table.clear(windows)
	table.clear(haloRings)
	table.clear(ringParts)
	if folder then folder:Destroy() folder = nil end
	beamCore, beamSheath, beamRise, hero = nil, nil, nil, nil
	revealedAt = nil
	clearGrade()
	vista = nil
end

-- Building, keeping and tearing down the scene (and switching between lobby
-- and dungeon lighting) is MenuLoader's job.

return MenuBackdrop
