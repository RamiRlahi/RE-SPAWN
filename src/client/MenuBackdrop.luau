--!strict
--[[
	MenuBackdrop.luau
	The title screen: a low-poly forest clearing at golden hour (pieces in
	MenuForest):
	  • foreground: a grassy rise with your character by a campfire (a pot of
	    stew on a spit), the party's seats around it (a stone, the grass, a
	    log bench), ferns and flowering bushes, a fallen log, two big faceted
	    trees framing the shot and pines round the edge
	  • beyond it a misty valley of round trees and a ruined castle on a hill,
	    ridges fading into golden haze, the low sun beside the castle
	  • a golden-hour grade (warm fill, thick gold haze, a plain sky) applied
	    while the menu is up and restored afterwards
	The lobby plaza's sky (BuildHubSky) is still the floating kingdom (its
	islands, halo and sunset helpers below).

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
local MenuForest = require(script.Parent:WaitForChild("MenuForest"))

local MenuBackdrop = {}

local rng = Random.new(7)

-- The exact title shot: the camera stands at CAM_FROM and looks at CAM_TO,
-- tipped ~12° down into the valley (horizon in the upper third). The scene
-- is laid out around this view.
local CAM_FROM = Vector3.new(399.016, 860.579, -104.064)
local CAM_TO = Vector3.new(-305.941, 694.6, 233.328)
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
-- `grounded`: just the buildings, no island under them (the title's
-- castle stands on a hill).
local function buildIsland(kind: string, width: number, grounded: boolean?): Model
	local m = Instance.new("Model")
	m.Name = "SkyIsland"
	m.Parent = folder -- in the world, so the surface raycast can hit it
	local tpl = getTemplate()
	if grounded then
		-- (nothing under it)
	elseif tpl then
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
	if fallTpl and fallTpl:IsA("Model") and kind ~= "grove" and not grounded then
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
-- (1 for the title shot; the lobby's sky is drawn at a larger scale, since
-- you walk about in it: BuildHubSky)
local compressScale = 1
local function compress(pos: Vector3): (Vector3, number)
	local off = pos - compressOrigin
	local d = off.Magnitude
	local cs = compressScale
	if d < 150 * cs then return pos, 1 end
	local placed = (95 + 55 * (1 - 1 / (1 + math.max(d - 200 * cs, 0) / (300 * cs)))) * cs
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
-- Building the lobby's sky: its islands stay still (far off, a bob can't be
-- seen, and moving thousands of parts every frame cost the plaza its frame
-- rate) and its halo rings turn only while you're on the plaza.
local buildingHub = false
local beamCore: BasePart? = nil
local beamSheath: BasePart? = nil
local beamRise: ParticleEmitter? = nil
local hero: Model? = nil

local function float(m: Model, base: CFrame, amp: number)
	m:PivotTo(base)
	if buildingHub then return end
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
-- The title's: golden hour, a warm amber fill (the low sun is ahead, so the
-- faces turned to the camera live on it) and a gold key on the tops.
local GRADE = {
	Ambient = Color3.fromRGB(78, 70, 60),          -- (darker shadows in the foreground)
	OutdoorAmbient = Color3.fromRGB(104, 96, 80),
	ColorShift_Top = Color3.fromRGB(236, 184, 128), -- warm sun on the tops
	ColorShift_Bottom = Color3.fromRGB(58, 64, 44),  -- green bounce under the trees
	Brightness = 1.7,
	ExposureCompensation = -0.1,
	EnvironmentDiffuseScale = 0.35,
}
-- The haze each scene wants: the title valley drowns in golden air (it's
-- only ~165 studs deep, so the haze is thick to read as miles); the plaza
-- keeps its thin violet dusk.
local TITLE_ATM = {
	Color = Color3.fromRGB(240, 214, 182), Decay = Color3.fromRGB(196, 146, 104),
	Density = 0.33, Haze = 2, Glare = 0.8, Offset = 0.05,
}
local HUB_ATM = {
	Color = Color3.fromRGB(230, 150, 150), Decay = Color3.fromRGB(80, 56, 124),
	Density = 0.07, Haze = 0.4, Glare = 0.35, Offset = 0.2,
}
-- The lobby plaza's: the same dusk, lifted (you walk about in it, among
-- lanterns and strings of lights): a warmer, brighter fill, the far blur
-- eased off.
local HUB_GRADE = {
	Ambient = Color3.fromRGB(76, 64, 98),
	OutdoorAmbient = Color3.fromRGB(110, 92, 134),
	ColorShift_Top = Color3.fromRGB(166, 124, 100),
	ColorShift_Bottom = Color3.fromRGB(66, 48, 102),
	Brightness = 1.25,
	ExposureCompensation = -0.25,
	EnvironmentDiffuseScale = 0.4,
}
local onPlaza = false
local function activeGrade(): { [string]: any }
	return if onPlaza then HUB_GRADE else GRADE
end
local gradeSun: { ClockTime: number, GeographicLatitude: number }? = nil
local menuSky: Sky? = nil
local menuAtm: Atmosphere? = nil
local stashedSkies: { Instance } = {}
local function restoreSkies()
	if menuSky then menuSky.Parent = nil end
	for _, s in ipairs(stashedSkies) do s.Parent = Lighting end
	table.clear(stashedSkies)
end

local function setGrade()
	for k, v in pairs(activeGrade()) do (Lighting :: any)[k] = v end
	if gradeSun then
		Lighting.ClockTime = gradeSun.ClockTime
		Lighting.GeographicLatitude = gradeSun.GeographicLatitude
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		-- (the place has none: the menu brings its own, removed with the grade)
		local a = Instance.new("Atmosphere")
		a.Name = "MenuAtmosphere"
		a.Parent = Lighting
		menuAtm = a
		atm = a
	end
	if atm then
		for k, v in pairs(if onPlaza then HUB_ATM else TITLE_ATM) do (atm :: any)[k] = v end
	end
	-- The title wants a plain sky the haze can turn gold (the place keeps
	-- several skyboxes, and Roblox shows any one of them): the others are put
	-- aside while the title is up, and come back on the plaza or in a run.
	if not onPlaza then
		for _, s in ipairs(Lighting:GetChildren()) do
			if s:IsA("Sky") and s ~= menuSky then
				table.insert(stashedSkies, s)
				s.Parent = nil
			end
		end
		if not menuSky then
			local sky = Instance.new("Sky")
			sky.Name = "MenuSky"
			sky.StarCount = 0
			sky.SunAngularSize = 14
			sky.MoonAngularSize = 0
			menuSky = sky
		end
		(menuSky :: Sky).Parent = Lighting
	else
		restoreSkies()
	end
	for _, e in ipairs(gradeFx) do e:Destroy() end
	table.clear(gradeFx)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.TintColor = if onPlaza then Color3.fromRGB(255, 236, 228) else Color3.fromRGB(255, 246, 236)
	cc.Saturation = if onPlaza then 0.08 else 0.04
	cc.Contrast = if onPlaza then 0.08 else 0.14
	cc.Brightness = if onPlaza then -0.03 else 0
	local bloom = Instance.new("BloomEffect")
	-- (the plaza is full of lamps and bulbs: a big soft bloom smears them
	-- into one glow there, so it's kept small and only on the brightest)
	bloom.Intensity = if onPlaza then 0.25 else 0.6
	bloom.Size = if onPlaza then 12 else 30
	bloom.Threshold = if onPlaza then 1.6 else 0.95
	-- (only a touch on the title, for the fire, lantern and beam; none on
	-- the plaza)
	bloom.Enabled = not onPlaza
	if not onPlaza then
		bloom.Intensity = 0.3
		bloom.Size = 20
		bloom.Threshold = 1.2
	end
	local rays = Instance.new("SunRaysEffect")
	rays.Intensity = if onPlaza then 0.1 else 0.13
	rays.Spread = 0.55
	-- The circle sharp, the valley a touch soft.
	local dof = Instance.new("DepthOfFieldEffect")
	dof.FocusDistance = if onPlaza then 40 else 25
	dof.InFocusRadius = if onPlaza then 60 else 30
	dof.FarIntensity = if onPlaza then 0.08 else 0.1
	dof.NearIntensity = 0
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
	local g = activeGrade()
	-- (near enough, not ==: Lighting keeps 1.15 as 1.1499999…, and an exact
	-- test rebuilt the grade, effects and all, every second)
	local amb = Lighting.Ambient
	local ok = math.abs(amb.R - g.Ambient.R) + math.abs(amb.G - g.Ambient.G) + math.abs(amb.B - g.Ambient.B) < 0.01
		and math.abs(Lighting.Brightness - g.Brightness) < 0.001 and #gradeFx > 0
	for _, e in ipairs(gradeFx) do
		if e.Parent ~= Lighting then ok = false end
	end
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if atm and math.abs(atm.Density - (if onPlaza then HUB_ATM else TITLE_ATM).Density) > 0.001 then ok = false end
	if not onPlaza and (not menuSky or menuSky.Parent ~= Lighting) then ok = false end
	if not ok then setGrade() end
end

-- On the lobby plaza (or not): its grade, and only the scene you're in kept
-- in the world. The title scene (its islands bob, its castles flicker, its
-- particles drift) is parked out of the world while you walk the plaza, and
-- the plaza's sky while you're in the menus: each is thousands of parts.
local stashed = false
local stashToken = 0
local hubSky: Folder? = nil
function MenuBackdrop.SetInHub(on: boolean)
	if onPlaza ~= on then
		onPlaza = on
		if savedLighting then setGrade() end
	end
	stashToken += 1
	local token = stashToken
	if on then
		if hubSky then hubSky.Parent = Workspace end
		-- (once the fade to the plaza has covered the screen)
		task.delay(0.6, function()
			if stashToken ~= token or not onPlaza then return end
			local f = folder
			if f and f.Parent == Workspace then
				f.Parent = nil
				stashed = true
			end
		end)
	else
		if stashed then
			stashed = false
			if folder then folder.Parent = Workspace end
		end
		if hubSky then hubSky.Parent = nil end
	end
end

local function clearGrade()
	for _, e in ipairs(gradeFx) do e:Destroy() end
	table.clear(gradeFx)
	gradeSun = nil
	restoreSkies()
	if menuAtm then menuAtm:Destroy() menuAtm = nil end
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
local haloRings: { { model: Model, center: CFrame, speed: number, hub: boolean } } = {}
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
	table.insert(haloRings, { model = m, center = center, speed = speed, hub = buildingHub })
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
	{ x = -8.2, z = -20.8, pose = "ledge", ledge = 1.4, edge = 0.3 }, -- on the log bench
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
-- Ambient motion in the title scene (driven by the render loop): trees
-- swaying from the foot, the fire's light flickering.
local swayers: { { model: Model, base: CFrame, amt: number, phase: number } } = {}
local fireLight: PointLight? = nil
local castleDir: Vector3? = nil -- (where your hero glances now and then)

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
	-- No weapon from a past run (or carried round the lobby): the copy is
	-- dressed by ClassLook (the class being shown), so it would double up.
	for _, t in ipairs(h:GetChildren()) do
		if t:IsA("Tool") or t.Name == "StowedWeapon" then t:Destroy() end
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
	-- Presentation: a soft contact shadow, a violet rim light from behind and
	-- a few magic motes drifting round you.
	local feet = (heroGround :: CFrame).Position
	part(h, { Name = "ContactShadow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 3.6, 3.2),
		CFrame = CFrame.new(feet + Vector3.new(0, 0.06, 0)) * UP, Color = Color3.fromRGB(20, 16, 12), Material = Enum.Material.SmoothPlastic, Transparency = 0.55 })
	local back = part(h, { Name = "RimLight", Size = Vector3.one * 0.2, Transparency = 1,
		CFrame = (heroGround :: CFrame) * CFrame.new(0, 4, 3.5) })
	local rim = Instance.new("PointLight")
	rim.Color = Color3.fromRGB(170, 110, 255)
	rim.Range = 8
	rim.Brightness = 1.6
	rim.Parent = back
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = TEX_SPARK
	motes.Color = ColorSequence.new(Color3.fromRGB(200, 150, 255), Color3.fromRGB(140, 90, 255))
	motes.LightEmission = 1
	motes.LightInfluence = 0
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.18), NumberSequenceKeypoint.new(1, 0) })
	motes.Lifetime = NumberRange.new(2.5, 4)
	motes.Speed = NumberRange.new(0.3, 0.8)
	motes.SpreadAngle = Vector2.new(180, 180)
	motes.Acceleration = Vector3.new(0, 0.5, 0)
	motes.Rate = 4
	motes.Parent = root -- (spawning through the root's box, round the body)
	-- Dressed as your chosen class (class select previews over this).
	local player = Players.LocalPlayer
	local classId = player:GetAttribute("SelectedClass")
	if ClassLook and typeof(classId) == "string" then
		ClassLook.Apply(h, classId, { armor = player:GetAttribute(`Armor_{classId}`) == true,
			finish = player:GetAttribute("Gear_weapon"), aura = player:GetAttribute("Gear_aura") })
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
		Color = Color3.fromRGB(128, 118, 104), Material = Enum.Material.SmoothPlastic }) else nil
	-- Their class: weapon in hand, and armor if they own and wear it.
	if ClassLook and classId then
		-- Swords are slung across the back while they sit; anything else
		-- rests in the hand (out toward the fire), the seat's pose driving the
		-- arms.
		ClassLook.Apply(h, classId, {
			armor = plr:GetAttribute(`Armor_{classId}`) == true,
			handTilt = CFrame.identity,
			onBack = ClassLook.SWORD_CLASSES[classId] == true,
			finish = plr:GetAttribute("Gear_weapon"), aura = plr:GetAttribute("Gear_aura"),
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
	-- (far enough back for the whole figure and the pedestal under it, the
	-- figure a little above the middle of the screen, clear of the buttons)
	-- Low, about waist height, so the pedestal reads as a dais, not a plate.
	-- Far enough back that a raised weapon still fits above the head.
	-- (from above head height, looking a little down on the figure)
	return CFrame.lookAt(base + toCam * 19 + Vector3.new(0, 4, 0), base + Vector3.new(0, -1.4, 0))
end

-- The camera shot while gathered: a little closer and lower than the title
-- shot, looking down at the circle; it pushes toward the portal as it opens.
function MenuBackdrop.CampfireView(): CFrame?
	local v = vista
	if not v then return nil end
	return v * CFrame.new(0.4 - 0.6 * campfirePush, -1.4, -5 - 1.5 * campfirePush) * CFrame.Angles(math.rad(4), 0, 0)
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

	-- The clearing (after the golden-hour key art): a faceted grass floor on
	-- a rise above the valley with patches, earth and a stone path, trees
	-- framing the shot (broadleaf and pine), ferns and flowers, and a campsite
	-- round the fire. Its surface is at y = -6 in the camera frame.
	local ledge = Instance.new("Model")
	ledge.Name = "HeroPlatform"
	ledge.Parent = fg
	local G = CFrame.new((cam * CFrame.new(0, -6, 0)).Position) * flatCam.Rotation
	local fire = Vector3.new(0.5, 0, -13.5) -- (x, -, z) in the camera frame
	local TREE_L, TREE_R = Vector2.new(-17, -19), Vector2.new(22, -14)

	-- Ground height (camera frame): flat round the camp, gently rolling
	-- beyond, rising at the sides and rolling down toward the valley at the back.
	local function smooth(e0: number, e1: number, x: number): number
		local t = math.clamp((x - e0) / (e1 - e0), 0, 1)
		return t * t * (3 - 2 * t)
	end
	local function lift(x: number, z: number): number
		local dc = Vector2.new(x - fire.X, z - fire.Z).Magnitude
		local roll = (math.noise(x / 9, z / 9, 1.7) * 1.3 + math.noise(x / 4, z / 4, 4.2) * 0.3) * smooth(8, 17, dc)
		local sides = smooth(16, 32, math.abs(x - 2)) * 1.6
		local back = math.max(0, -z - 27) * 0.35
		return roll + sides - back
	end

	-- The palette (the art's greens, yellow only as an accent).
	local GRASS = Color3.fromRGB(105, 123, 61)      -- #697B3D
	local GRASS_DARK = Color3.fromRGB(57, 77, 45)   -- #394D2D
	local EARTH = Color3.fromRGB(118, 84, 58)       -- #76543A
	local STONE = Color3.fromRGB(119, 113, 107)     -- #77716B
	local WARM = Color3.fromRGB(185, 160, 95)       -- #B9A05F
	-- The stone path: from the camp out toward the front right.
	local PATH = { Vector2.new(3.2, -10.6), Vector2.new(5.2, -8.4), Vector2.new(7.6, -6.6), Vector2.new(10.4, -5.2) }
	local function pathDist(x: number, z: number): number
		local best = math.huge
		for i = 1, #PATH - 1 do
			local a, b = PATH[i], PATH[i + 1]
			local ab = b - a
			local t = math.clamp((Vector2.new(x, z) - a):Dot(ab) / ab:Dot(ab), 0, 1)
			best = math.min(best, (Vector2.new(x, z) - (a + ab * t)).Magnitude)
		end
		return best
	end

	-- The grass floor: faceted, in irregular patches of light and dark grass,
	-- worn to earth round the fire and along the path, darker under the trees.
	do
		local NX, NZ = 24, 12
		local X0, X1, Z0, Z1 = -38, 40, -3, -33
		local pts: { { Vector3 } } = {}
		for j = 0, NZ do
			local row: { Vector3 } = {}
			for i = 0, NX do
				local x = X0 + (X1 - X0) * i / NX + (if i > 0 and i < NX then rng:NextNumber(-1, 1) else 0)
				local z = Z0 + (Z1 - Z0) * j / NZ + (if j > 0 and j < NZ then rng:NextNumber(-1, 1) else 0)
				row[i] = (G * CFrame.new(x, rng:NextNumber(-0.08, 0.08) + lift(x, z), z)).Position
			end
			pts[j] = row
		end
		local function col(a: Vector3, b: Vector3, c: Vector3): Color3
			local m = G:PointToObjectSpace((a + b + c) / 3)
			local x, z = m.X, m.Z
			local patch = math.noise(x / 7, z / 7, 5.3)
			local cc = GRASS:Lerp(GRASS_DARK, math.clamp(-patch * 2.2, 0, 0.8))
			local warm = math.noise(x / 5, z / 5, 9.1)
			if warm > 0.25 then cc = cc:Lerp(WARM, math.clamp((warm - 0.25) * 1.6, 0, 0.45)) end
			-- shade under the two big crowns
			for _, t in ipairs({ TREE_L, TREE_R }) do
				local d = (Vector2.new(x, z) - t).Magnitude
				if d < 8 then cc = cc:Lerp(GRASS_DARK, (1 - d / 8) * 0.6) end
			end
			local toFire = Vector2.new(x - fire.X, z - fire.Z).Magnitude
			if toFire < 6 then cc = cc:Lerp(EARTH, math.clamp((1 - toFire / 6) * 1.3, 0, 0.9)) end
			local pd = pathDist(x, z)
			if pd < 1.6 then cc = cc:Lerp(EARTH, (1 - pd / 1.6) * 0.7) end
			return cc:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.08))
		end
		for j = 0, NZ - 1 do
			for i = 0, NX - 1 do
				local a, b, c, d = pts[j][i], pts[j][i + 1], pts[j + 1][i], pts[j + 1][i + 1]
				MenuForest.Tri(ledge, a, b, c, col(a, b, c))
				MenuForest.Tri(ledge, b, d, c, col(b, d, c))
			end
		end
		-- (the floor is what props are stood on)
		for _, d in ipairs(ledge:GetDescendants()) do
			if d:IsA("BasePart") then d.CanQuery = true end
		end
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
	local function ground(x: number, z: number): Vector3
		return upright(x, -9, z).Position
	end
	local function nearSeat(x: number, z: number, r: number): boolean
		if (Vector2.new(x - fire.X, z - fire.Z)).Magnitude < r + 4 then return true end
		for _, s in ipairs(SEATS) do
			if (Vector2.new(x - s.x, z - s.z)).Magnitude < r + 1.8 then return true end
		end
		if pathDist(x, z) < r + 0.6 then return true end
		return (Vector2.new(x - PORTAL_SPOT.x, z - PORTAL_SPOT.z)).Magnitude < r + 3
	end

	-- The stone path: flat slabs set in the earth.
	for i = 1, #PATH - 1 do
		local a, b = PATH[i], PATH[i + 1]
		local n = math.max(1, math.floor((b - a).Magnitude / 1.5))
		for k = 0, n - 1 do
			local p = a + (b - a) * ((k + rng:NextNumber(0.3, 0.7)) / n)
			local s = rng:NextNumber(0.9, 1.25)
			part(fg, { Size = Vector3.new(s * 1.3, 0.22, s), CFrame = upright(p.X + rng:NextNumber(-0.3, 0.3), -9 + 0.06, p.Y, rng:NextNumber(0, 6.28))
				* CFrame.Angles(rng:NextNumber(-0.04, 0.04), 0, rng:NextNumber(-0.04, 0.04)),
				Color = STONE:Lerp(WARM, rng:NextNumber(0, 0.15)):Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.12)), Material = Enum.Material.SmoothPlastic })
		end
	end
	-- Rocks along the clearing's lip and a few in the grass.
	for i = 0, 13 do
		local x = -30 + i * 5 + rng:NextNumber(-1.5, 1.5)
		if math.abs(x - PORTAL_SPOT.x) > 4 then
			local s = rng:NextNumber(1.4, 2.8)
			MenuForest.Blob(fg, ground(x, -31 + rng:NextNumber(-1, 1)) + Vector3.new(0, s * 0.2, 0), Vector3.new(s * 1.4, s * 0.8, s), STONE, rng, { jitter = 0.14 })
		end
	end
	for _ = 1, 10 do
		local x, z = rng:NextNumber(-22, 26), rng:NextNumber(-28, -6)
		if not nearSeat(x, z, 1) then
			local s = rng:NextNumber(0.5, 1.2)
			MenuForest.Blob(fg, ground(x, z) + Vector3.new(0, s * 0.1, 0), Vector3.new(s * 1.3, s * 0.6, s), STONE, rng, { jitter = 0.12 })
		end
	end

	-- The trees. Two broadleaf trees frame the shot (kept clear of the logo
	-- and pulled back from the camp), pines of different heights and girths
	-- and a few smaller broadleafs round the edge; the middle stays open on
	-- the valley and the castle.
	local function sway(m: Model, amt: number)
		table.insert(swayers, { model = m, base = m:GetPivot(), amt = amt, phase = rng:NextNumber(0, 6.28) })
	end
	sway(MenuForest.Tree(fg, ground(TREE_L.X, TREE_L.Y), 17, rng, { crown = 8.6, reach = Vector3.new(3, 0, -1), blobs = 6, shadow = true }), 1)
	sway(MenuForest.Tree(fg, ground(TREE_R.X, TREE_R.Y), 18, rng,
		{ crown = 9.4, reach = Vector3.new(-4, 0, -2), blobs = 7, color = Color3.fromRGB(78, 94, 44), shadow = true }), 1)
	sway(MenuForest.Tree(fg, ground(27, -27), 14, rng, { crown = 5, blobs = 4, octa = true, color = Color3.fromRGB(88, 100, 46) }), 0.7)
	sway(MenuForest.Tree(fg, ground(-25, -29), 15, rng, { crown = 5.5, blobs = 4, octa = true, color = Color3.fromRGB(64, 84, 42) }), 0.7)
	MenuForest.Tree(fg, ground(12, -31), 10, rng, { crown = 3.6, blobs = 3, octa = true, color = Color3.fromRGB(96, 104, 50) })
	for _, t in ipairs({ { -21, -24, 15 }, { -11, -29, 10 }, { -28, -18, 18 }, { -15.5, -32, 13 }, { 31, -19, 17 }, { 17, -30, 9 }, { 33, -27, 12 }, { -6, -31.5, 7 } }) do
		sway(MenuForest.Pine(fg, ground(t[1], t[2]), t[3] * rng:NextNumber(0.9, 1.1), rng, { shadow = t[3] > 14 }), 0.6)
	end

	-- Small vegetation: ferns, bushes, flowers and grass clusters, in clumps
	-- (never on the camp, the seats or the path).
	local FERN = Color3.fromRGB(86, 112, 44)
	local function fern(x: number, z: number, s: number)
		local base = ground(x, z)
		local n = rng:NextInteger(6, 8)
		local spin = rng:NextNumber(0, 6.28)
		for i = 1, n do
			local a = spin + i / n * math.pi * 2 + rng:NextNumber(-0.25, 0.25)
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local side = Vector3.new(-dir.Z, 0, dir.X)
			local len = s * rng:NextNumber(0.75, 1.2)
			local tip = base + dir * len + Vector3.new(0, s * rng:NextNumber(0.2, 0.45), 0)
			local mid = base + dir * len * 0.45 + Vector3.new(0, s * 0.55, 0)
			local c = FERN:Lerp(GRASS_DARK, rng:NextNumber(0, 0.4))
			MenuForest.Tri(fg, base, mid + side * s * 0.18, tip, c)
			MenuForest.Tri(fg, base, mid - side * s * 0.18, tip, c:Lerp(Color3.new(0, 0, 0), 0.2))
		end
	end
	local FLOWER = { Color3.fromRGB(250, 238, 232), Color3.fromRGB(240, 186, 196), Color3.fromRGB(196, 170, 236), Color3.fromRGB(250, 214, 120) }
	local function flowers(c: Vector3, r: number, stems: boolean?)
		local tint = FLOWER[rng:NextInteger(1, #FLOWER)]
		for _ = 1, rng:NextInteger(3, 6) do
			local a = rng:NextNumber(0, 6.28)
			local p = c + Vector3.new(math.cos(a) * r * rng:NextNumber(0.2, 0.9), (if stems then 0 else r * rng:NextNumber(0.3, 0.8)), math.sin(a) * r * rng:NextNumber(0.2, 0.9))
			if stems then
				local h = rng:NextNumber(0.5, 0.9)
				part(fg, { Size = Vector3.new(0.06, h, 0.06), CFrame = CFrame.new(p + Vector3.new(0, h / 2, 0)), Color = GRASS_DARK, Material = Enum.Material.SmoothPlastic })
				p += Vector3.new(0, h, 0)
			end
			part(fg, { Shape = Enum.PartType.Ball, Size = Vector3.one * rng:NextNumber(0.26, 0.4), CFrame = CFrame.new(p),
				Color = tint, Material = Enum.Material.SmoothPlastic })
		end
	end
	local function bush(x: number, z: number, s: number, bloom: boolean?)
		local c = ground(x, z) + Vector3.new(0, s * 0.32, 0)
		MenuForest.Blob(fg, c, Vector3.new(s * 1.45, s * rng:NextNumber(0.85, 1.1), s * 1.3),
			Color3.fromRGB(72, 94, 44):Lerp(GRASS_DARK, rng:NextNumber(0, 0.5)), rng, { octa = true })
		if bloom then flowers(c, s * 0.7) end
	end
	local function tuft(x: number, z: number, s: number)
		local base = ground(x, z)
		for _ = 1, rng:NextInteger(3, 5) do
			local a = rng:NextNumber(0, 6.28)
			local off = Vector3.new(math.cos(a), 0, math.sin(a)) * s * 0.16
			local lean = Vector3.new(rng:NextNumber(-0.35, 0.35), 0, rng:NextNumber(-0.35, 0.35)) * s
			MenuForest.Tri(fg, base + off, base - off, base + lean + Vector3.new(0, s * rng:NextNumber(0.7, 1.3), 0),
				GRASS:Lerp(GRASS_DARK, rng:NextNumber(0, 0.6)):Lerp(WARM, rng:NextNumber(0, 0.15)))
		end
	end
	-- the back edge, behind the circle: bushes and ferns, some in flower
	for x = -16, 8, 2.6 do
		local z = -26.5 + rng:NextNumber(-1.5, 1.5)
		if not nearSeat(x, z, 1.5) then
			if rng:NextNumber() < 0.5 then bush(x, z, rng:NextNumber(1.6, 2.5), rng:NextNumber() < 0.5) else fern(x, z, rng:NextNumber(1.8, 2.7)) end
		end
	end
	-- the near corners frame the bottom of the shot
	for _, b in ipairs({ { 14, -7.5, 2.4, true }, { 19, -9.5, 2.9, false }, { 23.5, -8, 3, true }, { -8, -7, 2.1, false } }) do
		bush(b[1], b[2], b[3], b[4])
	end
	for _, f in ipairs({ { -12, -9.5 }, { 11.5, -7 }, { 17, -24 }, { -18, -12 }, { 9, -27 }, { 16.5, -6.5 }, { -3.5, -7 }, { 20, -11.5 }, { -14, -24 } }) do
		fern(f[1], f[2], rng:NextNumber(1.7, 2.7))
	end
	-- flower patches and grass clusters, in clumps
	for _ = 1, 9 do
		local x, z = rng:NextNumber(-20, 26), rng:NextNumber(-27, -7)
		if not nearSeat(x, z, 1) then flowers(ground(x, z), 1.1, true) end
	end
	for _ = 1, 22 do
		local cx, cz = rng:NextNumber(-22, 28), rng:NextNumber(-28, -6)
		for _ = 1, rng:NextInteger(2, 5) do
			local x, z = cx + rng:NextNumber(-1.6, 1.6), cz + rng:NextNumber(-1.2, 1.2)
			if not nearSeat(x, z, 0.4) then tuft(x, z, rng:NextNumber(0.6, 1.15)) end
		end
	end

	-- Logs: the bench at seat 3 and a fallen trunk across the right of the
	-- clearing.
	local LOG = Color3.fromRGB(104, 72, 46)
	local CUT = Color3.fromRGB(196, 158, 108)
	local function log(a: Vector3, b: Vector3, w: number)
		MenuForest.Post(fg, a, b, w, LOG:Lerp(Color3.fromRGB(70, 48, 32), rng:NextNumber(0, 0.4)), true)
		for _, e in ipairs({ a, b }) do -- (pale cut ends)
			local dir = (b - a).Unit
			local p = e + (if e == a then -dir else dir) * 0.03
			part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, w * 1.05, w * 1.05), CFrame = CFrame.lookAt(p, p + dir) * CFrame.Angles(0, math.rad(90), 0),
				Color = CUT, Material = Enum.Material.SmoothPlastic })
		end
	end
	local s3 = SEATS[3]
	log(ground(s3.x - 3, s3.z - 0.6) + Vector3.new(0, 0.7, 0), ground(s3.x + 2.6, s3.z + 0.8) + Vector3.new(0, 0.7, 0), 1.4)
	log(ground(10, -25) + Vector3.new(0, 0.8, 0), ground(21, -19.5) + Vector3.new(0, 0.9, 0), 1.6)
	MenuForest.Post(fg, ground(15.5, -22.2) + Vector3.new(0, 1, 0), ground(17.5, -25) + Vector3.new(0, 2.8, 0), 0.5, LOG, true) -- (a broken branch)

	-- ── The campsite ─────────────────────────────────────────────────────
	local bowlCF = upright(fire.X, -8.7, fire.Z) -- (the coals, just above the ground)
	-- The firepit: an ash bed inside two rings of stones.
	part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 3.4, 3.4), CFrame = bowlCF * CFrame.new(0, -0.25, 0) * UP,
		Color = Color3.fromRGB(58, 52, 50), Material = Enum.Material.SmoothPlastic })
	for i = 0, 10 do
		local a = i / 11 * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local s = rng:NextNumber(0.62, 0.85)
		MenuForest.Blob(fg, (bowlCF * CFrame.new(math.cos(a) * 1.85, 0.05, math.sin(a) * 1.85)).Position, Vector3.new(s * 1.2, s * 0.85, s),
			STONE:Lerp(Color3.fromRGB(70, 64, 60), rng:NextNumber(0, 0.4)), rng, { octa = true })
	end
	for i = 0, 13 do
		local a = (i + 0.5) / 14 * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
		local s = rng:NextNumber(0.45, 0.65)
		MenuForest.Blob(fg, (bowlCF * CFrame.new(math.cos(a) * 2.45, -0.15, math.sin(a) * 2.45)).Position, Vector3.new(s * 1.2, s * 0.7, s),
			STONE:Lerp(WARM, rng:NextNumber(0, 0.2)), rng, { octa = true })
	end
	local coals = part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2.3, 2.3),
		CFrame = bowlCF * UP, Color = Color3.fromRGB(255, 110, 35), Material = Enum.Material.Neon })
	for i = 0, 4 do
		local a = i * 2 * math.pi / 5 + 0.3
		part(fg, { Size = Vector3.new(2.5, 0.42, 0.42),
			CFrame = bowlCF * CFrame.Angles(0, a, 0) * CFrame.new(0.55, 0.65, 0) * CFrame.Angles(0, 0, math.rad(-45)),
			Color = LOG:Lerp(Color3.fromRGB(34, 20, 14), rng:NextNumber(0.3, 0.7)), Material = Enum.Material.SmoothPlastic })
	end
	-- Layered flames: the Fire, a bright core and licking tongues.
	local flame = Instance.new("Fire")
	flame.Color = Color3.fromRGB(255, 160, 60)
	flame.SecondaryColor = Color3.fromRGB(230, 70, 20)
	flame.Size = 3
	flame.Heat = 6
	flame.Parent = coals
	local flameAtt = Instance.new("Attachment")
	flameAtt.Position = Vector3.new(0.2, 0, 0) -- (the cylinder's axis is X: a little above the coals)
	flameAtt.Parent = coals
	local function flameLayer(size: number, life: number, speed: number, rate: number, c0: Color3, c1: Color3)
		local e = Instance.new("ParticleEmitter")
		e.Texture = "rbxasset://textures/particles/fire_main.dds"
		e.Color = ColorSequence.new(c0, c1)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size), NumberSequenceKeypoint.new(0.4, size * 0.8), NumberSequenceKeypoint.new(1, 0) })
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(0.2, 0.15), NumberSequenceKeypoint.new(1, 1) })
		e.Lifetime = NumberRange.new(life * 0.7, life)
		e.Speed = NumberRange.new(speed * 0.6, speed)
		e.SpreadAngle = Vector2.new(14, 14)
		e.Rotation = NumberRange.new(-20, 20)
		e.RotSpeed = NumberRange.new(-40, 40)
		e.EmissionDirection = Enum.NormalId.Right -- (up, along the cylinder's axis)
		e.Rate = rate
		e.Parent = flameAtt
	end
	flameLayer(1.6, 0.7, 2.6, 14, Color3.fromRGB(255, 236, 160), Color3.fromRGB(255, 150, 50))
	flameLayer(1.1, 1.0, 3.6, 10, Color3.fromRGB(255, 170, 70), Color3.fromRGB(220, 60, 20))
	-- Embers rising, and a thin smoke trailing off.
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = TEX_SPARK
	embers.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 90, 30))
	embers.LightEmission = 1
	embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) })
	embers.Lifetime = NumberRange.new(1.6, 3)
	embers.Speed = NumberRange.new(2, 4)
	embers.SpreadAngle = Vector2.new(25, 25)
	embers.Acceleration = Vector3.new(1.2, 1.5, 0)
	embers.EmissionDirection = Enum.NormalId.Right
	embers.Rate = 9
	embers.Parent = flameAtt
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = TEX_SMOKE
	smoke.Color = ColorSequence.new(Color3.fromRGB(120, 112, 108), Color3.fromRGB(190, 182, 172))
	smoke.LightInfluence = 0.7
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 5) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.82), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(5, 7)
	smoke.Speed = NumberRange.new(2, 3)
	smoke.Acceleration = Vector3.new(0.6, 0.2, 0)
	smoke.SpreadAngle = Vector2.new(8, 8)
	smoke.EmissionDirection = Enum.NormalId.Right
	smoke.Rate = 1.5
	smoke.Parent = flameAtt
	-- The fire's warm light (flickered in the render loop).
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 150, 70)
	glow.Range = 18
	glow.Brightness = 1.6
	glow.Shadows = true
	glow.Parent = coals
	fireLight = glow

	-- The cooking tripod: three poles lashed at the top, a chain down to the
	-- pot of stew.
	local STICK = Color3.fromRGB(96, 66, 42)
	local IRON = Color3.fromRGB(44, 36, 34)
	local apex = (bowlCF * CFrame.new(0, 4.6, 0)).Position
	for i = 0, 2 do
		local a = i / 3 * math.pi * 2 + 0.5
		local foot = (bowlCF * CFrame.new(math.cos(a) * 2.2, -0.35, math.sin(a) * 2.2)).Position
		MenuForest.Post(fg, foot, apex + (apex - foot).Unit * 0.5, 0.22, STICK:Lerp(Color3.fromRGB(70, 46, 30), rng:NextNumber(0, 0.3)), true)
	end
	part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 0.34, 0.34), CFrame = CFrame.new(apex) * UP, Color = Color3.fromRGB(150, 120, 80), Material = Enum.Material.SmoothPlastic }) -- (the lashing)
	local potCF = bowlCF * CFrame.new(0, 2.05, 0)
	for k = 0, 4 do -- the chain
		part(fg, { Size = Vector3.new(0.1, 0.42, 0.18), CFrame = CFrame.new(apex - Vector3.new(0, 0.3 + k * 0.4, 0)) * CFrame.Angles(0, (k % 2) * math.pi / 2, 0),
			Color = IRON, Material = Enum.Material.Metal })
	end
	part(fg, { Size = Vector3.new(0.08, 0.5, 0.08), CFrame = potCF * CFrame.new(0, 0.95, 0), Color = IRON, Material = Enum.Material.Metal })
	part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.15, 1.5, 1.5), CFrame = potCF * UP, Color = IRON, Material = Enum.Material.Metal })
	part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 1.25, 1.25), CFrame = potCF * CFrame.new(0, -0.65, 0) * UP, Color = IRON, Material = Enum.Material.Metal })
	part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.16, 1.64, 1.64), CFrame = potCF * CFrame.new(0, 0.58, 0) * UP, Color = IRON, Material = Enum.Material.Metal })
	for _, sx in ipairs({ -0.82, 0.82 }) do
		part(fg, { Size = Vector3.new(0.18, 0.18, 0.3), CFrame = potCF * CFrame.new(sx, 0.4, 0), Color = IRON, Material = Enum.Material.Metal })
	end
	local stew = part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.05, 1.3, 1.3), CFrame = potCF * CFrame.new(0, 0.6, 0) * UP,
		Color = Color3.fromRGB(150, 60, 34), Material = Enum.Material.SmoothPlastic })
	local steamAtt = Instance.new("Attachment")
	steamAtt.Parent = stew
	local steam = Instance.new("ParticleEmitter")
	steam.Texture = TEX_SMOKE
	steam.Color = ColorSequence.new(Color3.fromRGB(240, 232, 224))
	steam.LightInfluence = 0.6
	steam.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 2.6) })
	steam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.15, 0.75), NumberSequenceKeypoint.new(1, 1) })
	steam.Lifetime = NumberRange.new(2.5, 4)
	steam.Speed = NumberRange.new(1, 1.6)
	steam.Acceleration = Vector3.new(0.6, 0.3, 0)
	steam.SpreadAngle = Vector2.new(10, 10)
	steam.Rate = 2
	steam.Parent = steamAtt

	-- Four logs round the fire (in the gaps between the seats), cut ends up.
	for _, a in ipairs({ 40, 125, 205, 262 }) do
		local r = math.rad(a)
		local c = Vector2.new(fire.X + math.cos(r) * 3.6, fire.Z + math.sin(r) * 3.6)
		local t = Vector2.new(-math.sin(r), math.cos(r)) * 0.95
		log(ground(c.X - t.X, c.Y - t.Y) + Vector3.new(0, 0.34, 0), ground(c.X + t.X, c.Y + t.Y) + Vector3.new(0, 0.34, 0), 0.68)
	end

	-- Camp supplies, kept to the edges of the circle.
	local WOOD = Color3.fromRGB(150, 108, 68)
	local function crate(at: Vector3, s: number, yaw: number): CFrame
		local cf = CFrame.new(at + Vector3.new(0, s / 2, 0)) * flatCam.Rotation * CFrame.Angles(0, yaw, 0)
		part(fg, { Size = Vector3.one * s, CFrame = cf, Color = WOOD:Lerp(Color3.fromRGB(110, 76, 46), rng:NextNumber(0, 0.4)), Material = Enum.Material.SmoothPlastic })
		for _, face in ipairs({ Vector3.new(0, 0, 1), Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0) }) do
			local side = Vector3.new(face.Z, 0, -face.X)
			for _, y in ipairs({ -0.42, 0.42 }) do -- (dark frame boards)
				part(fg, { Size = Vector3.new(math.abs(side.X) * s * 1.02 + 0.08, s * 0.12, math.abs(side.Z) * s * 1.02 + 0.08),
					CFrame = cf * CFrame.new(face * s * 0.5 + Vector3.new(0, y * s, 0)), Color = Color3.fromRGB(92, 62, 38), Material = Enum.Material.SmoothPlastic })
			end
		end
		return cf
	end
	local c1 = crate(ground(14.5, -17.5), 1.7, 0.3)
	crate(ground(16.2, -16.8), 1.4, -0.2)
	crate((c1 * CFrame.new(0, 0.85, 0)).Position + Vector3.new(0, 0.05, 0), 1.2, 0.7)
	-- The lantern on the top crate: a warm glass in a dark cage.
	local lan = c1 * CFrame.new(0.1, 0.85 + 1.25, 0.1)
	part(fg, { Size = Vector3.new(0.7, 0.12, 0.7), CFrame = lan * CFrame.new(0, -0.45, 0), Color = IRON, Material = Enum.Material.Metal })
	part(fg, { Size = Vector3.new(0.48, 0.66, 0.48), CFrame = lan, Color = Color3.fromRGB(255, 200, 110), Material = Enum.Material.Neon })
	for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
		part(fg, { Size = Vector3.new(0.07, 0.8, 0.07), CFrame = lan * CFrame.new(c[1] * 0.28, 0, c[2] * 0.28), Color = IRON, Material = Enum.Material.Metal })
	end
	MenuForest.Blob(fg, (lan * CFrame.new(0, 0.48, 0)).Position, Vector3.new(0.85, 0.35, 0.85), IRON, rng, { octa = true, jitter = 0 })
	part(fg, { Size = Vector3.new(0.06, 0.4, 0.4), CFrame = lan * CFrame.new(0, 0.8, 0), Color = IRON, Material = Enum.Material.Metal })
	-- Two small stools.
	local function stool(x: number, z: number)
		local at = ground(x, z)
		part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 1.1, 1.1), CFrame = CFrame.new(at + Vector3.new(0, 0.95, 0)) * UP,
			Color = WOOD, Material = Enum.Material.SmoothPlastic })
		for i = 0, 2 do
			local a = i / 3 * math.pi * 2 + rng:NextNumber(0, 1)
			local foot = at + Vector3.new(math.cos(a) * 0.55, 0, math.sin(a) * 0.55)
			MenuForest.Post(fg, foot, at + Vector3.new(math.cos(a) * 0.25, 0.9, math.sin(a) * 0.25), 0.13, Color3.fromRGB(96, 66, 42))
		end
	end
	stool(11.8, -15.6)
	stool(-4.5, -18.6)
	-- The adventurer's pack against the fallen trunk: a body, a flap, a
	-- rolled blanket on top and two straps.
	do
		local at = ground(12.6, -21.8)
		local cf = CFrame.new(at + Vector3.new(0, 0.85, 0)) * flatCam.Rotation * CFrame.Angles(math.rad(-12), 0.5, 0)
		local LEATHER = Color3.fromRGB(122, 80, 50)
		part(fg, { Size = Vector3.new(1.5, 1.7, 0.9), CFrame = cf, Color = LEATHER, Material = Enum.Material.SmoothPlastic })
		part(fg, { Size = Vector3.new(1.55, 0.7, 0.95), CFrame = cf * CFrame.new(0, 0.62, 0.04), Color = LEATHER:Lerp(Color3.new(0, 0, 0), 0.2), Material = Enum.Material.SmoothPlastic })
		part(fg, { Size = Vector3.new(1.1, 0.6, 0.25), CFrame = cf * CFrame.new(0, -0.35, 0.52), Color = LEATHER:Lerp(Color3.new(0, 0, 0), 0.1), Material = Enum.Material.SmoothPlastic })
		part(fg, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.9, 0.62, 0.62), CFrame = cf * CFrame.new(0, 1.15, 0), Color = Color3.fromRGB(150, 60, 50), Material = Enum.Material.SmoothPlastic })
		for _, sx in ipairs({ -0.4, 0.4 }) do
			part(fg, { Size = Vector3.new(0.14, 1.8, 0.05), CFrame = cf * CFrame.new(sx, 0.05, 0.47), Color = Color3.fromRGB(70, 46, 30), Material = Enum.Material.SmoothPlastic })
		end
	end
	-- A sword planted in the ground beside the crates (well clear of the
	-- hero, so it never reads as a weapon slipping from your hand in class
	-- select): a low-poly blade leaning a little, a crossguard, a wrapped
	-- grip and a pommel.
	do
		local at = ground(18.8, -16.8)
		local cf = CFrame.new(at) * flatCam.Rotation * CFrame.Angles(0, 0.6, 0) * CFrame.Angles(math.rad(8), 0, math.rad(-10))
		local STEEL = Color3.fromRGB(196, 200, 206)
		part(fg, { Size = Vector3.new(0.42, 3.2, 0.1), CFrame = cf * CFrame.new(0, 1.2, 0), Color = STEEL, Material = Enum.Material.Metal })
		part(fg, { Size = Vector3.new(0.14, 3.2, 0.12), CFrame = cf * CFrame.new(0, 1.2, 0), Color = STEEL:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Metal }) -- (the fuller's ridge)
		part(fg, { Size = Vector3.new(1.5, 0.2, 0.24), CFrame = cf * CFrame.new(0, 2.88, 0), Color = Color3.fromRGB(150, 116, 60), Material = Enum.Material.Metal })
		part(fg, { Size = Vector3.new(0.2, 0.95, 0.2), CFrame = cf * CFrame.new(0, 3.45, 0), Color = Color3.fromRGB(72, 44, 30), Material = Enum.Material.SmoothPlastic })
		MenuForest.Blob(fg, (cf * CFrame.new(0, 4.0, 0)).Position, Vector3.new(0.34, 0.34, 0.34), Color3.fromRGB(170, 134, 70), rng, { octa = true, jitter = 0 })
		MenuForest.Blob(fg, at + Vector3.new(0, 0.05, 0), Vector3.new(1.1, 0.25, 0.9), EARTH, rng, { octa = true }) -- (turned earth at the blade)
	end

	-- Fireflies drifting round the camp at dusk.
	local ffBox = part(fg, { Size = Vector3.new(26, 4, 16), CFrame = upright(3, -6.5, -17), Transparency = 1 })
	local ff = Instance.new("ParticleEmitter")
	ff.Texture = TEX_SPARK
	ff.Color = ColorSequence.new(Color3.fromRGB(230, 255, 140))
	ff.LightEmission = 1
	ff.LightInfluence = 0
	ff.Size = NumberSequence.new(0.22)
	ff.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(0.5, 0.6),
		NumberSequenceKeypoint.new(0.7, 0.05), NumberSequenceKeypoint.new(1, 1) })
	ff.Lifetime = NumberRange.new(5, 8)
	ff.Speed = NumberRange.new(0.3, 0.8)
	ff.SpreadAngle = Vector2.new(180, 180)
	ff.Acceleration = Vector3.new(0, 0.08, 0)
	ff.Rate = 2.5
	ff.Parent = ffBox

	-- The campfire circle: your hero waits standing at your seat (three-
	-- quarters to the camera) until you sit; the party sits around the fire.
	fgInfo = { fg = fg, upright = upright, bowl = bowlCF.Position }
	heroHome = fg
	heroGround = standSpot(1)
	heroShowcase()
	refreshCampfire()
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
	if not f or not vista then return false end
	if f.Parent ~= Workspace and not stashed then return false end -- (parked: you're on the plaza)
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

	-- Golden hour: the real sun low over the valley, a little left of the
	-- castle, so the haze glows round it and the crowns are rim-lit.
	local sunDir = (dirAt(9) + Vector3.new(0, 0.13, 0)).Unit
	applyGrade(sunDir)

	-- Level frames (the title shot looks down into the valley; the scene is
	-- laid out level so the clearing's seats stay where they were).
	local flat = CFrame.new(camPos) * CFrame.lookAt(Vector3.zero, fwd).Rotation
	-- The far view: a misty valley of round trees, the ruined castle on its
	-- hill, ridges fading into the haze.
	local site = MenuForest.Valley(f, flat, rng)
	-- The capital on its hilltop: the gothic castle on a faceted crown of
	-- rock and grass.
	-- (low enough that the pillar of light and the halo show above it; the
	-- mound runs down into the hill so nothing floats)
	local capW = 34
	MenuForest.Blob(f, site.Position - Vector3.new(0, 10, 0), Vector3.new(capW * 1.35, 20, capW * 1.25),
		Color3.fromRGB(104, 110, 58), rng, { jitter = 0.05 })
	local capital = buildIsland("spire", capW, true)
	capital:PivotTo(site * CFrame.Angles(0, math.rad(25), 0))
	local spirePos = site.Position
	local s = capW / 44
	-- The pillar of light rising from the great spire's tip.
	local tip = spirePos + Vector3.new(0, 45 * s, 0)
	local beamLen = 600
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
	rise.Speed = NumberRange.new(6, 12)
	rise.EmissionDirection = Enum.NormalId.Right
	rise.Rate = 25
	rise.Enabled = false
	rise.Parent = beamSheath
	beamRise = rise
	-- The runic halo above the castle, two counter-spinning rings.
	local tilt = CFrame.Angles(math.rad(10), 0, math.rad(-4))
	runeRing(f, CFrame.new(spirePos + Vector3.new(0, 40 * s, 0)) * tilt, 34 * s, 96, Color3.fromRGB(110, 150, 255), 0.08, 0.21)
	runeRing(f, CFrame.new(spirePos + Vector3.new(0, 42 * s, 0)) * tilt, 30 * s, 84, Color3.fromRGB(170, 130, 255), -0.12, 0.21)
	-- Foreground: the clearing with the campfire, just ahead of and below
	-- the camera.
	buildForeground(f, flat * CFrame.new(0, -3, -6))
	castleDir = Vector3.new(spirePos.X - camPos.X, 0, spirePos.Z - camPos.Z).Unit
	-- Soft clouds drifting slowly across the sky band (particle banks: lit
	-- by the sky, not shaded like solid parts).
	for i = 1, 4 do
		local bank = part(f, { Size = Vector3.new(60, 6, 10), Transparency = 1,
			CFrame = flat * CFrame.new(-110 + (i - 1) * 70 + rng:NextNumber(-10, 10), rng:NextNumber(20, 34), -rng:NextNumber(135, 160)) })
		local cl = Instance.new("ParticleEmitter")
		cl.Texture = TEX_SMOKE
		cl.Color = ColorSequence.new(Color3.fromRGB(255, 244, 228), Color3.fromRGB(250, 222, 196))
		cl.LightInfluence = 0.15
		cl.LightEmission = 0.1
		cl.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 16), NumberSequenceKeypoint.new(1, 24) })
		cl.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.55), NumberSequenceKeypoint.new(0.75, 0.6), NumberSequenceKeypoint.new(1, 1),
		})
		cl.Lifetime = NumberRange.new(40, 55)
		cl.Speed = NumberRange.new(0.6, 1)
		cl.EmissionDirection = Enum.NormalId.Right
		cl.SpreadAngle = Vector2.new(3, 3)
		cl.Rotation = NumberRange.new(0, 360)
		cl.RotSpeed = NumberRange.new(-1, 1)
		cl.Rate = 0.25
		cl.Parent = bank
		cl:Emit(8)
	end

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
		-- (on the plaza the title scene is parked: nothing of it to move; only
		-- the plaza sky's halo turns, every other frame)
		for _, r in ipairs(haloRings) do
			if r.hub and onPlaza and frame % 2 == 0 and r.model.Parent then r.model:PivotTo(r.center * CFrame.Angles(0, t * r.speed, 0)) end
		end
		if onPlaza then return end
		-- The islands bob slowly, so each one only needs moving every third
		-- frame (staggered).
		for i, fl in ipairs(floaters) do
			if fl.model.Parent and (i + frame) % 3 == 0 then
				local bob = math.sin(t * fl.speed + fl.phase) * fl.amp
				fl.model:PivotTo(fl.base * CFrame.new(0, bob, 0) * CFrame.Angles(0, t * fl.yaw, math.sin(t * fl.speed * 0.7 + fl.phase) * 0.012))
			end
		end
		for _, r in ipairs(haloRings) do
			if not r.hub and r.model.Parent then r.model:PivotTo(r.center * CFrame.Angles(0, t * r.speed, 0)) end
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
		-- The campfire's light flickers.
		if fireLight then
			fireLight.Brightness = 1.5 + math.noise(t * 3.1, 0.5) * 0.5 + math.noise(t * 9.7, 2.5) * 0.2
			fireLight.Range = 17 + math.noise(t * 2.3, 7.5) * 1.5
		end
		-- Trees sway gently from the foot (staggered: every third frame each).
		for i, sw in ipairs(swayers) do
			if (i + frame) % 3 == 0 and sw.model.Parent then
				local a = sw.amt * 0.012
				sw.model:PivotTo(sw.base * CFrame.Angles(math.sin(t * 0.7 + sw.phase) * a * 0.6, 0, math.sin(t * 0.55 + sw.phase * 1.3) * a))
			end
		end
		-- Your hero glances off toward the castle now and then.
		local h = hero
		if h and castleDir then
			local torso = h:FindFirstChild("Torso")
			local neck = torso and torso:FindFirstChild("Neck")
			local root = h.PrimaryPart
			if neck and neck:IsA("Motor6D") and root then
				local base = neck:GetAttribute("BaseC0")
				if typeof(base) ~= "CFrame" then
					base = neck.C0
					neck:SetAttribute("BaseC0", base)
				end
				local cyc = t % 11
				local w = if cyc > 6.5 and cyc < 9.5 then math.sin(math.pi * (cyc - 6.5) / 3) else 0
				local rel = root.CFrame:VectorToObjectSpace(castleDir)
				local yaw = w * 0.42 * (if rel.X > 0 then -1 else 1) + math.sin(t * 0.4) * 0.04
				neck.C0 = (base :: CFrame) * CFrame.Angles(0, 0, yaw)
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
	table.clear(swayers)
	fireLight, castleDir = nil, nil
	table.clear(windows)
	table.clear(haloRings)
	table.clear(ringParts)
	if folder then folder:Destroy() folder = nil end
	stashed = false
	beamCore, beamSheath, beamRise, hero = nil, nil, nil, nil
	revealedAt = nil
	clearGrade()
	vista = nil
end

-- ── The lobby's sky ─────────────────────────────────────────────────────────
-- The title screen's floating kingdom drawn round the lobby plaza too: the
-- great capital with its pillar of light and runic halo behind the DUNGEON
-- gate, islands and shards across the sky, a cloud sea below and the sunset.
-- Built (once) when you enter the lobby; it has its own folder, so the title
-- scene's rebuilds leave it be. Depth is compressed round the plaza like the
-- title shot's, but wider (you walk about in this one).
function MenuBackdrop.BuildHubSky(center: Vector3, forward: Vector3)
	if hubSky then
		if onPlaza then hubSky.Parent = Workspace end
		return
	end
	local hs = Instance.new("Folder")
	hs.Name = "HubSky"
	hs.Parent = Workspace
	hubSky = hs
	local prevFolder, prevOrigin, prevScale = folder, compressOrigin, compressScale
	folder = hs
	compressOrigin = center
	compressScale = 3.2
	buildingHub = true
	local ok, err = pcall(function()
		local fwd = Vector3.new(forward.X, 0, forward.Z).Unit
		local function dirAt(yawDeg: number): Vector3
			return CFrame.Angles(0, math.rad(yawDeg), 0) * fwd
		end
		-- the capital behind the gate, off to the right (as in the art)
		local capScale = 3.6
		local spireFar = center + dirAt(-24) * 1000 + Vector3.new(0, 40, 0)
		place("spire", spireFar, capScale)
		local spirePos, ck = compress(spireFar)
		local sz = 68 * capScale * ck / 44
		local tip = spirePos + Vector3.new(0, 45 * sz, 0)
		local beamLen = 2048 * ck
		part(hs, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(beamLen, 1.4 * sz, 1.4 * sz),
			CFrame = CFrame.new(tip + Vector3.new(0, beamLen / 2, 0)) * UP, Color = GOLD, Material = Enum.Material.Neon, Transparency = 0.15 })
		part(hs, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(beamLen, 4.5 * sz, 4.5 * sz),
			CFrame = CFrame.new(tip + Vector3.new(0, beamLen / 2, 0)) * UP, Color = Color3.fromRGB(255, 170, 70), Material = Enum.Material.Neon, Transparency = 0.75 })
		local tilt = CFrame.Angles(math.rad(10), 0, math.rad(-4))
		local before = #ringParts
		runeRing(hs, CFrame.new(spirePos + Vector3.new(0, 40 * sz, 0)) * tilt, 34 * sz, 96, Color3.fromRGB(110, 150, 255), 0.08, ck)
		runeRing(hs, CFrame.new(spirePos + Vector3.new(0, 42 * sz, 0)) * tilt, 30 * sz, 84, Color3.fromRGB(170, 130, 255), -0.12, ck)
		-- (lit now: the title's halo fades in with its beam, this one just shines)
		for i = before + 1, #ringParts do ringParts[i].part.Transparency = ringParts[i].base end
		-- islands round the sky (clear of the capital's line), farther ones bigger
		local kinds = { "keep", "ruin", "keep", "ruin", "keep", "ruin", "keep", "ruin", "keep", "ruin", "keep", "ruin" }
		local placed = 0
		local tries = 0
		while placed < #kinds and tries < 600 do
			tries += 1
			local yaw = rng:NextNumber(-150, 150)
			local dist = rng:NextNumber(560, 1400)
			if math.abs(yaw + 24) < 12 then continue end
			placed += 1
			place(kinds[placed], center + dirAt(yaw) * dist + Vector3.new(0, rng:NextNumber(-0.12, 0.1) * dist, 0), rng:NextNumber(2, 3.6) * dist / 700)
		end
		for _ = 1, 14 do
			local dist = rng:NextNumber(560, 1300)
			shard(center + dirAt(rng:NextNumber(-170, 170)) * dist + Vector3.new(0, rng:NextNumber(0, 0.35) * dist, 0), rng:NextNumber(12, 26) * dist / 600)
		end
		-- the cloud sea below, banks far off
		for i = 1, 10 do
			cloudBank(hs, center + dirAt(-180 + i * 36) * 900 + Vector3.new(0, -500, 0), 600, 240, 1)
		end
		for i = 1, 5 do
			cloudBank(hs, center + dirAt(-90 + (i - 1) * 45) * 1500 + Vector3.new(0, -160, 0), 380, 260, 0.4)
		end
		-- the sun where the light actually comes from
		local sd = Lighting:GetSunDirection()
		if sd.Y > -0.2 then sunset(hs, center + Vector3.new(sd.X, math.max(sd.Y, 0.05), sd.Z).Unit * 2600) end
	end)
	folder, compressOrigin, compressScale = prevFolder, prevOrigin, prevScale
	buildingHub = false
	if not ok then warn("[MenuBackdrop] lobby sky:", err) end
	-- The far islands' waterfalls: their spray specks and steam are too small
	-- to see from the plaza (the falls and their mist stay).
	for _, d in ipairs(hs:GetDescendants()) do
		if d:IsA("ParticleEmitter") and (d.Name == "Specs" or d.Name == "Smoke") then d:Destroy() end
	end
	if not onPlaza then hs.Parent = nil end
end

function MenuBackdrop.DestroyHubSky()
	if hubSky then hubSky:Destroy() end
	hubSky = nil
end

-- Building, keeping and tearing down the scene (and switching between lobby
-- and dungeon lighting) is MenuLoader's job.

return MenuBackdrop
