--!strict
--[[
	ForgeMinigame.luau
	Forging a new power piece at the Armory's forge (PowerGear.CRAFT_COST
	scrap), played out in a working village smithy built for it far off-map:
	a timber-framed stone workshop with a brick forge and hood, a great lever
	bellows, the anvil on its stump, a slack tub, a workbench and grindstone,
	racks of tools and finished arms, coal, ore and lanterns. Your own
	character (a clone) is the smith.

	The smith works with real tools, posed by CastPoses (full body, R6
	standard: the torso does the work, the free arm counters, coils are held,
	blows snap in and ease out). The workshop is built AROUND those poses:
	the clone is posed first and the anvil, the coal bed, the bellows lever,
	the hammer stand and the slack tub are placed where its hammer face, tongs
	tip and hands actually land, so every contact is a contact.

	  0. PREPARE  the smith sets the hammer on its stand, takes the cold bar
	              off the anvil with the tongs and buries it in the coals.
	  1. HEAT     hold (mouse / Space / tap / A): the smith hauls the bellows
	              lever (the lever, rod and bellows follow the hand), the fire
	              roars and the bar reddens; let go and the lever rises, the fire
	              settles and the bar cools. Keep the heat inside the drifting
	              band for 5 seconds (a pulse each second held; at the band's
	              edge it flickers; outside, the metal darkens and spits).
	              The forge erupts; the bar comes out onto the anvil, the smith
	              takes up the hammer.
	  2. HAMMER   the smith coils (leaning back, twisting, hammer high, the coil
	              tightening as the marker nears the mark); every press brings
	              it down at once: PERFECT / GOOD / OK / MISS, five times, each
	              sweep faster. Each grade its own blow; they build to the
	              fifth. The bar flattens toward the slot's shape.
	  3. QUENCH   quality = 35% heat + 65% hammer; the server forges the piece
	              (LootManager "craft": the score picks the rarity odds,
	              PowerGear.CraftRarity). The smith lifts it in the tongs, looks
	              it over, turns to the slack tub and plunges it: a splash and
	              layered steam that fills the screen.
	  4. REVEAL   out of the steam the smith raises the finished piece to the
	              light, glowing in its rarity's colour (REVEAL below); its card
	              builds up.

	Gameplay is unchanged by the show: the heat band and its 5 seconds, the
	five strikes and their timing windows, the 35 / 65 split, the server's
	roll, the skip. Only what's drawn and heard around them.

	The scene, the camera, the colour grade and the input binding are all
	undone when it closes.

	ForgeMinigame.Play(slot)
--]]

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GearData = require(Shared:WaitForChild("GearData"))
local PowerGear = require(Shared:WaitForChild("PowerGear"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local CastPoses = require(script.Parent.Parent:WaitForChild("CastPoses") :: ModuleScript) :: any

local player = Players.LocalPlayer

local ForgeMinigame = {}

local GOLD = Color3.fromRGB(240, 196, 110)
local PARCH = Color3.fromRGB(238, 226, 204)
local MUTED = Color3.fromRGB(150, 140, 128)
local GREEN = Color3.fromRGB(120, 230, 140)
local RED = Color3.fromRGB(230, 110, 100)
local WHITE_GOLD = Color3.fromRGB(255, 240, 200)
local GLOW_GOLD = Color3.fromRGB(255, 220, 130)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

local HEAT_TIME = 5
local STRIKES = 5
local ORIGIN = CFrame.new(-9000, 2500, -9000) -- the smithy, far from everything

-- The hammer in the right hand (the wrist angle it's held at) and the tongs in
-- the left (bent forward at the wrist, so they reach ahead of the hand).
local WRIST = math.rad(-165)
local TONGS_LEN = 2.1
local TONGS_BEND = math.rad(30)
local DOWNSWING = 0.08 -- seconds from the press to the blow
local RECOVER = 0.3

local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"

-- Sounds (Roblox's licensed Pro Sound Effects library), each played with a
-- little pitch variation so repeats don't drone.
local SFX = {
	fire = "rbxassetid://9112780462",    -- fireplace, constant burning (loop)
	bellows = "rbxassetid://9113070633", -- short swooshing air burst
	hits = {                             -- blacksmith anvil hammer hits
		"rbxassetid://9113447467", "rbxassetid://9113445305", "rbxassetid://9113447116",
		"rbxassetid://9113447422", "rbxassetid://9113447191",
	},
	boom = "rbxassetid://9125484367",    -- deep reverberant boom
	steam = "rbxassetid://9113073932",   -- hissing rush of air (the steam)
	splash = "rbxassetid://9125703162",  -- shallow water impact
	sparkle = "rbxassetid://9119447936", -- bell tree shimmer
	chime = "rbxassetid://9116394876",   -- soft magic chime
}

-- the ingot's colour by heat: cold iron → cherry → orange → white-hot
local HEAT_COLORS = {
	{ 0, Color3.fromRGB(70, 66, 66) },
	{ 0.35, Color3.fromRGB(150, 30, 20) },
	{ 0.6, Color3.fromRGB(240, 110, 30) },
	{ 0.85, Color3.fromRGB(255, 210, 90) },
	{ 1, Color3.fromRGB(255, 250, 230) },
}
local function heatColor(h: number): Color3
	for i = 2, #HEAT_COLORS do
		local a, b = HEAT_COLORS[i - 1], HEAT_COLORS[i]
		if h <= b[1] then return a[2]:Lerp(b[2], (h - a[1]) / (b[1] - a[1])) end
	end
	return HEAT_COLORS[#HEAT_COLORS][2]
end

local function grade(score: number): string
	return if score >= 0.95 then "MASTERWORK" elseif score >= 0.8 then "EXCELLENT" elseif score >= 0.6 then "FINE"
		elseif score >= 0.35 then "DECENT" else "CRUDE"
end

-- How each rarity is revealed (the odds are the server's; this is only the show).
--   burst: sparks in the burst; light: the flash's peak; shake: camera trauma;
--   tint: how far the colour grade leans into the rarity; tier: 1..6 (layers
--   switch on by tier: the ring at 3, the pillar and the push-in at 5, the held
--   breath at 6).
local REVEAL = {
	Common = { tier = 1, burst = 24, light = 3, shake = 0.25, tint = 0 },
	Uncommon = { tier = 2, burst = 40, light = 4, shake = 0.35, tint = 0.12 },
	Rare = { tier = 3, burst = 60, light = 5.5, shake = 0.5, tint = 0.2 },
	Epic = { tier = 4, burst = 80, light = 7, shake = 0.7, tint = 0.3 },
	Legendary = { tier = 5, burst = 110, light = 9, shake = 0.95, tint = 0.38 },
	Mythic = { tier = 6, burst = 140, light = 11, shake = 1.2, tint = 0.45 },
}

-- what the ingot is hammered toward, by slot (length, thickness, width)
local SHAPE = {
	weapon = Vector3.new(2.5, 0.1, 0.3),
	armor = Vector3.new(1.4, 0.14, 1.1),
	ring = Vector3.new(0.85, 0.12, 0.85),
	charm = Vector3.new(0.75, 0.1, 0.62),
}
local INGOT = Vector3.new(1, 0.24, 0.45)

-- ── The smith's poses (CastPoses, degrees) ────────────────────────────────
-- lean: - = forward over the work; twist: + = shoulders to the left; front /
-- back: the legs' stride (the body drops as they spread, the feet stay
-- planted); yaw: the whole body turned (+ = left) to face another station.
-- RS / LS: + rx raises the arm forward; the counter-arm always does something.
local FURNACE_YAW = 68 -- the forge is on the smith's left
local QUENCH_YAW = -105 -- the slack tub round on the right

local function pose(lean: number, twist: number, front: number, back: number, upper: { [string]: { number } }, yaw: number?): any
	local p = CastPoses.body(lean, twist, front, back, upper, 7)
	if yaw then
		local r = p.Root
		p.Root = { r[1], yaw, r[3], r[4], r[5], r[6] }
	end
	return p
end

local POSE = {
	-- at the anvil, hammer down at the side, tongs ready
	stand = pose(-4, 0, 8, 8, { RS = { 12, 0, 10 }, LS = { 30, 0, -6 }, N = { -6, 0, 0 } }),
	-- bending to set the hammer on its stand (and, later, take it up)
	setHammer = pose(-32, -14, 12, 16, { RS = { 100, 0, 4 }, LS = { 40, 0, -6 }, N = { -24, -10, 0 } }),
	-- tongs down to the anvil face (taking or laying the work)
	grab = pose(-30, -10, 12, 16, { RS = { 16, 0, 14 }, LS = { 90, 0, 22 }, N = { -26, 0, 0 } }),
	-- turned to the forge, the work held in the coals; the right hand on the lever
	pumpUp = pose(-16, -6, 12, 14, { LS = { 62, 0, 4 }, RS = { 116, 0, 26 }, N = { -14, 4, 0 } }, FURNACE_YAW),
	pumpDown = pose(-26, 6, 14, 16, { LS = { 66, 0, 4 }, RS = { 50, 0, 22 }, N = { -18, 0, 0 } }, FURNACE_YAW),
	-- the coil: leaning back over the back foot, shoulders turned right, the
	-- hammer high behind the head, the tongs arm braced forward on the work
	coil = pose(12, -16, 8, 16, { RS = { 172, 0, 14 }, LS = { 62, 0, 20 }, N = { -22, 14, 0 } }),
	-- the blow: thrown over the work, shoulders driven round, head down on it
	impact = pose(-34, 12, 14, 18, { RS = { 115, 0, 4 }, LS = { 92, 0, 20 }, N = { -28, -6, 0 } }),
	glance = pose(-26, 6, 12, 16, { RS = { 130, 0, 10 }, LS = { 88, 0, 20 }, N = { -22, -4, 0 } }),
	rebound = pose(-28, 6, 12, 16, { RS = { 135, 0, 8 }, LS = { 86, 0, 20 }, N = { -24, 0, 0 } }),
	-- the hammer lowered after the last blow
	lower = pose(-14, 0, 10, 12, { RS = { 30, 0, 12 }, LS = { 70, 0, 14 }, N = { -16, 0, 0 } }),
	-- the work held up to the eye and looked over
	inspect = pose(-2, 18, 8, 10, { LS = { 100, 0, 14 }, RS = { 16, 0, 14 }, N = { 10, 24, 0 } }),
	-- turned to the slack tub: over it, then down into it
	quenchAbove = pose(-20, 0, 12, 16, { LS = { 95, 0, 8 }, RS = { 18, 0, 14 }, N = { -22, 0, 0 } }, QUENCH_YAW),
	quenchLow = pose(-30, 0, 16, 20, { LS = { 70, 0, 8 }, RS = { 18, 0, 14 }, N = { -30, 0, 0 } }, QUENCH_YAW),
	-- the finished piece raised to the light
	present = pose(4, 4, 8, 10, { LS = { 95, 0, 18 }, RS = { 22, 0, 14 }, N = { 14, 6, 0 } }),
}

-- (exposed so the poses can be checked in Studio, one at a time)
ForgeMinigame.POSE = POSE

local function make(class: string, props: { [string]: any }, parent: Instance?): any
	local o = Instance.new(class)
	for k, v in pairs(props) do (o :: any)[k] = v end
	if parent then o.Parent = parent end
	return o
end

-- (every prop: no touches, no queries; small ones cast no shadow)
local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): Part
	local p = make("Part", {
		Anchored = true, CanCollide = false, CanTouch = false, CanQuery = false, Size = size, CFrame = cf,
		Color = color, Material = material or Enum.Material.SmoothPlastic,
		TopSurface = Enum.SurfaceType.Smooth, BottomSurface = Enum.SurfaceType.Smooth,
		CastShadow = size.Magnitude > 6,
	}, nil)
	for k, v in pairs(props or {}) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- a part stretched between two points (rods, pipes, chains, levers)
local function between(p: BasePart, a: Vector3, b: Vector3, thick: number)
	local d = (b - a).Magnitude
	p.Size = Vector3.new(thick, thick, math.max(d, 0.05))
	p.CFrame = CFrame.lookAt((a + b) / 2, b)
end

local function sequence(...: number): NumberSequence
	local v = { ... }
	local kps = {}
	for i = 1, #v, 2 do table.insert(kps, NumberSequenceKeypoint.new(v[i], v[i + 1])) end
	return NumberSequence.new(kps)
end

local function tween(o: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local tw = TweenService:Create(o, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- ── The smithy ─────────────────────────────────────────────────────────────
type Scene = { [string]: any }

-- A clone of the player's character, still and script-free, to be the smith.
local function cloneSmith(parent: Instance, at: CFrame): Model?
	local char = player.Character
	if not char then return nil end
	local was = char.Archivable
	char.Archivable = true
	local ok, clone = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not clone then return nil end
	local m = clone :: Model
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("Tool") or d:IsA("BillboardGui") or d:IsA("Highlight")
			or d:IsA("ParticleEmitter") or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("Light") or d:IsA("Trail")
			or d:IsA("Beam") or d:IsA("Animator") then
			d:Destroy()
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.PlatformStand = true
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide, d.CanTouch, d.CanQuery = false, false, false
			d.Anchored = false
			d.Massless = true
		elseif d:IsA("Motor6D") then
			d.Transform = CFrame.identity
		end
	end
	local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		m:Destroy()
		return nil
	end
	root.Anchored = true
	m.Parent = parent
	m:PivotTo(at)
	root.CFrame = at
	return m
end

-- The workshop itself: walls, roof, light from the window, and the life of
-- the place (bench, grindstone, racks, stock, lanterns). The work stations
-- (forge, bellows, anvil, tub, hammer stand) are placed later, from the poses.
-- Coordinates are in the smith's frame (`root` faces -Z; the floor is y = -3).
local function buildRoom(folder: Instance, root: CFrame)
	local STONE = Color3.fromRGB(62, 58, 56)
	local DARK_STONE = Color3.fromRGB(44, 41, 40)
	local PLASTER = Color3.fromRGB(128, 108, 86)
	local OAK = Color3.fromRGB(70, 48, 32)
	local DARK_OAK = Color3.fromRGB(48, 33, 23)
	local IRON = Color3.fromRGB(58, 56, 60)
	local STEEL = Color3.fromRGB(150, 150, 158)
	local function at(x: number, y: number, z: number): CFrame return root * CFrame.new(x, y, z) end
	local function p(size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material?, props: { [string]: any }?): Part
		return part(folder, size, cf, color, mat, props)
	end
	local F = -3 -- the floor
	local X0, X1, Z0, Z1, H = -10, 14, -14, 10, 15 -- the walls, the roof

	-- floor: flagstones, a sooty apron round the forge, a worn path to the anvil
	p(Vector3.new(X1 - X0 + 2, 1, Z1 - Z0 + 2), at((X0 + X1) / 2, F - 0.5, (Z0 + Z1) / 2), STONE, Enum.Material.Slate, { CastShadow = false })
	p(Vector3.new(8, 0.04, 9), at(-6, F + 0.02, -0.5), Color3.fromRGB(30, 27, 26), Enum.Material.Slate)
	p(Vector3.new(7, 0.04, 6), at(1, F + 0.02, -1.5), DARK_STONE, Enum.Material.Slate)
	for i = 0, 5 do -- a few loose flagstones
		local x, z = -3 + (i * 3.7) % 14, -10 + (i * 5.3) % 18
		p(Vector3.new(2.2, 0.06, 1.6), at(x, F + 0.03, z) * CFrame.Angles(0, i * 0.4, 0), Color3.fromRGB(70, 66, 63), Enum.Material.Slate)
	end

	-- walls: a stone base, timber framing and plaster above
	local function wall(cx: number, cz: number, len: number, alongX: boolean)
		local function sz(l: number, h: number, t: number): Vector3
			return if alongX then Vector3.new(l, h, t) else Vector3.new(t, h, l)
		end
		p(sz(len, 4, 1.2), at(cx, F + 2, cz), STONE, Enum.Material.Cobblestone, { CastShadow = true })
		p(sz(len, H - 4, 0.8), at(cx, F + 4 + (H - 4) / 2, cz), PLASTER, Enum.Material.Concrete, { CastShadow = true })
		p(sz(len, 0.6, 1.0), at(cx, F + 4.2, cz), OAK, Enum.Material.Wood)
		p(sz(len, 0.6, 1.0), at(cx, F + H - 0.6, cz), OAK, Enum.Material.Wood)
		local n = math.floor(len / 6)
		for i = 0, n do
			local o = -len / 2 + i * (len / n)
			local cf = if alongX then at(cx + o, F + 4 + (H - 4) / 2, cz) else at(cx, F + 4 + (H - 4) / 2, cz + o)
			p(sz(0.7, H - 4, 1.0), cf, OAK, Enum.Material.Wood)
			if i < n and i % 2 == 0 then -- a diagonal brace in every other bay
				local o2 = o + len / n / 2
				local mid = if alongX then at(cx + o2, F + 4 + (H - 4) / 2, cz) else at(cx, F + 4 + (H - 4) / 2, cz + o2)
				local ang = math.atan2(H - 5, len / n)
				p(sz(math.sqrt((len / n) ^ 2 + (H - 5) ^ 2) - 0.6, 0.45, 0.9), mid * (if alongX then CFrame.Angles(0, 0, ang) else CFrame.Angles(ang, 0, 0)),
					DARK_OAK, Enum.Material.Wood)
			end
		end
	end
	wall((X0 + X1) / 2, Z1, X1 - X0, true)  -- back (behind the smith)
	wall((X0 + X1) / 2, Z0, X1 - X0, true)  -- front (behind the camera)
	wall(X0, (Z0 + Z1) / 2, Z1 - Z0, false) -- left (the forge's)
	wall(X1, (Z0 + Z1) / 2, Z1 - Z0, false) -- right (the door's)

	-- roof: planks, tie beams, rafters and a ridge
	p(Vector3.new(X1 - X0 + 2, 0.6, Z1 - Z0 + 2), at((X0 + X1) / 2, F + H + 0.3, (Z0 + Z1) / 2), DARK_OAK, Enum.Material.WoodPlanks, { CastShadow = true })
	for z = Z0 + 3, Z1 - 2, 5 do
		p(Vector3.new(X1 - X0, 0.9, 0.9), at((X0 + X1) / 2, F + H - 1.4, z), OAK, Enum.Material.Wood)
	end
	p(Vector3.new(0.9, 0.9, Z1 - Z0), at(2, F + H - 0.6, (Z0 + Z1) / 2), OAK, Enum.Material.Wood)
	for x = X0 + 2, X1 - 2, 4 do
		p(Vector3.new(0.5, 0.5, Z1 - Z0), at(x, F + H - 0.2, (Z0 + Z1) / 2), DARK_OAK, Enum.Material.Wood)
	end

	-- the back window: night outside, moonlight in (the only cool light here)
	local winCF = at(5, F + 8.5, Z1 - 0.45)
	p(Vector3.new(5, 4.5, 0.2), winCF, Color3.fromRGB(70, 95, 140), Enum.Material.Neon, { Transparency = 0.15 })
	p(Vector3.new(5.6, 0.5, 0.9), winCF * CFrame.new(0, -2.5, -0.2), OAK, Enum.Material.Wood) -- sill
	p(Vector3.new(5.6, 0.5, 0.9), winCF * CFrame.new(0, 2.5, -0.2), OAK, Enum.Material.Wood)
	for _, x in ipairs({ -2.6, 0, 2.6 }) do p(Vector3.new(0.35, 4.5, 0.5), winCF * CFrame.new(x, 0, -0.15), DARK_OAK, Enum.Material.Wood) end
	p(Vector3.new(5, 0.3, 0.5), winCF * CFrame.new(0, 0.3, -0.15), DARK_OAK, Enum.Material.Wood)
	local moonAtt = make("Attachment", { WorldPosition = (winCF * CFrame.new(0, 0, -3)).Position }, Workspace.Terrain)
	make("PointLight", { Color = Color3.fromRGB(120, 150, 220), Range = 24, Brightness = 1.1, Shadows = false }, moonAtt)
	-- a warm fill from the lanterns over the work (no shadows: the forge casts those)
	local fillAtt = make("Attachment", { WorldPosition = (root * CFrame.new(3, 6, -2)).Position }, Workspace.Terrain)
	make("PointLight", { Color = Color3.fromRGB(255, 190, 130), Range = 30, Brightness = 2, Shadows = false }, fillAtt)
	folder.Destroying:Connect(function()
		moonAtt:Destroy()
		fillAtt:Destroy()
	end)

	-- the door (right wall): planks, iron straps, a ring pull
	local doorCF = at(X1 - 0.5, F + 3.5, 4)
	p(Vector3.new(0.4, 7, 4), doorCF, DARK_OAK, Enum.Material.WoodPlanks)
	for _, y in ipairs({ -2.4, 0, 2.4 }) do p(Vector3.new(0.5, 0.25, 3.6), doorCF * CFrame.new(-0.05, y, 0), IRON, Enum.Material.Metal) end
	p(Vector3.new(0.6, 7.6, 0.5), doorCF * CFrame.new(0, 0.3, 2.2), OAK, Enum.Material.Wood)
	p(Vector3.new(0.6, 7.6, 0.5), doorCF * CFrame.new(0, 0.3, -2.2), OAK, Enum.Material.Wood)
	p(Vector3.new(0.6, 0.5, 4.9), doorCF * CFrame.new(0, 3.8, 0), OAK, Enum.Material.Wood)

	-- the workbench under the window: a vise, files, a blade being finished
	local bench = at(5, F + 3, Z1 - 1.6)
	p(Vector3.new(6.5, 0.4, 2.2), bench, OAK, Enum.Material.WoodPlanks, { CastShadow = true })
	for _, o in ipairs({ Vector2.new(-3, -0.9), Vector2.new(3, -0.9), Vector2.new(-3, 0.9), Vector2.new(3, 0.9) }) do
		p(Vector3.new(0.4, 3, 0.4), bench * CFrame.new(o.X, -1.5, o.Y), DARK_OAK, Enum.Material.Wood)
	end
	p(Vector3.new(6, 0.25, 1.8), bench * CFrame.new(0, -2.3, 0), DARK_OAK, Enum.Material.WoodPlanks) -- the shelf under it
	p(Vector3.new(0.7, 0.8, 0.9), bench * CFrame.new(-2.7, 0.6, -0.4), IRON, Enum.Material.Metal) -- vise
	p(Vector3.new(0.9, 0.15, 0.15), bench * CFrame.new(-2.7, 1.0, -0.95), STEEL, Enum.Material.Metal)
	p(Vector3.new(3, 0.06, 0.35), bench * CFrame.new(0.4, 0.23, -0.2) * CFrame.Angles(0, 0.1, 0), STEEL, Enum.Material.Metal) -- a blade
	p(Vector3.new(0.5, 0.12, 0.7), bench * CFrame.new(-1.3, 0.25, -0.2), Color3.fromRGB(110, 90, 40), Enum.Material.Metal) -- its guard
	for i = 0, 2 do p(Vector3.new(1.2, 0.06, 0.1), bench * CFrame.new(1.8, 0.23, 0.4 + i * 0.18), STEEL, Enum.Material.Metal) end -- files
	for i = 0, 3 do -- bar stock on the shelf
		p(Vector3.new(1.8, 0.2, 0.3), bench * CFrame.new(1 - (i % 2) * 0.1, -2.05 + math.floor(i / 2) * 0.2, -0.4 + i * 0.25), IRON, Enum.Material.Metal)
	end

	-- the grindstone, by the door
	local gs = at(10.5, F, 6.5)
	p(Vector3.new(0.4, 2.2, 0.4), gs * CFrame.new(0, 1.1, -0.9), OAK, Enum.Material.Wood)
	p(Vector3.new(0.4, 2.2, 0.4), gs * CFrame.new(0, 1.1, 0.9), OAK, Enum.Material.Wood)
	p(Vector3.new(1.2, 0.4, 2.6), gs * CFrame.new(0, 0.6, 0), DARK_OAK, Enum.Material.Wood) -- the trough
	p(Vector3.new(0.5, 2.6, 2.6), gs * CFrame.new(0, 2.3, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(120, 112, 100), Enum.Material.Sandstone,
		{ Shape = Enum.PartType.Cylinder })
	p(Vector3.new(0.18, 0.18, 2.4), gs * CFrame.new(0, 2.3, 0), IRON, Enum.Material.Metal) -- axle
	p(Vector3.new(0.15, 0.9, 0.15), gs * CFrame.new(0, 1.9, 1.3), IRON, Enum.Material.Metal) -- crank

	-- the tool wall behind the smith: tongs and hammers on pegs
	local rack = at(-4, F + 6.6, Z1 - 0.55)
	p(Vector3.new(6.5, 0.4, 0.4), rack, OAK, Enum.Material.Wood)
	for i = 0, 6 do
		local x = -2.8 + i * 0.95
		if i % 2 == 0 then -- tongs: two long reins and jaws
			p(Vector3.new(0.08, 2.4, 0.08), rack * CFrame.new(x - 0.06, -1.2, -0.15), IRON, Enum.Material.Metal)
			p(Vector3.new(0.08, 2.4, 0.08), rack * CFrame.new(x + 0.06, -1.2, -0.15) * CFrame.Angles(0, 0, 0.05), IRON, Enum.Material.Metal)
		else -- hammers, hung head down
			p(Vector3.new(0.14, 1.6, 0.14), rack * CFrame.new(x, -0.8, -0.15), Color3.fromRGB(96, 66, 40), Enum.Material.Wood)
			p(Vector3.new(0.7, 0.35, 0.35), rack * CFrame.new(x, -1.7, -0.15), IRON, Enum.Material.Metal)
		end
	end
	-- a shelf of finished pieces above it
	local shelf = at(-4, F + 9.6, Z1 - 0.8)
	p(Vector3.new(6, 0.25, 1), shelf, OAK, Enum.Material.Wood)
	p(Vector3.new(1, 0.5, 0.18), shelf * CFrame.new(-2, 0.4, 0), STEEL, Enum.Material.Metal) -- a buckle
	p(Vector3.new(0.9, 0.9, 0.9), shelf * CFrame.new(-0.4, 0.55, 0), STEEL, Enum.Material.Metal, { Shape = Enum.PartType.Ball }) -- a helm
	p(Vector3.new(1.0, 0.15, 1.0), shelf * CFrame.new(-0.4, 0.2, 0), STEEL, Enum.Material.Metal)
	p(Vector3.new(0.12, 1.1, 1.1), shelf * CFrame.new(1.6, 0.68, 0) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(110, 40, 34), Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder }) -- a round shield
	p(Vector3.new(0.14, 0.3, 0.3), shelf * CFrame.new(1.6, 0.68, -0.06) * CFrame.Angles(0, math.rad(90), 0), STEEL, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder })

	-- the weapon rack on the right wall: swords, an axe, a spear
	local wr = at(X1 - 0.7, F, -5)
	p(Vector3.new(0.5, 0.35, 6), wr * CFrame.new(0, 5.6, 0), OAK, Enum.Material.Wood)
	p(Vector3.new(0.5, 0.35, 6), wr * CFrame.new(0, 1.2, 0), OAK, Enum.Material.Wood)
	for i = 0, 3 do
		local z = -2.2 + i * 1.4
		p(Vector3.new(0.08, 3.8, 0.3), wr * CFrame.new(-0.2, 3.4, z), STEEL, Enum.Material.Metal) -- blade
		p(Vector3.new(0.18, 0.15, 0.9), wr * CFrame.new(-0.2, 5.35, z), Color3.fromRGB(110, 90, 40), Enum.Material.Metal) -- guard
		p(Vector3.new(0.16, 0.8, 0.16), wr * CFrame.new(-0.2, 5.8, z), DARK_OAK, Enum.Material.Wood) -- grip
	end
	p(Vector3.new(0.15, 5, 0.15), wr * CFrame.new(-0.25, 3.5, 3.2), OAK, Enum.Material.Wood) -- the spear
	p(Vector3.new(0.1, 0.8, 0.3), wr * CFrame.new(-0.25, 6.3, 3.2), STEEL, Enum.Material.Metal)

	-- stock: crates of ore, sacks of charcoal, scrap, a coal bin with a shovel
	local function crate(cf: CFrame, s: number)
		p(Vector3.new(s, s * 0.8, s), cf, OAK, Enum.Material.WoodPlanks, { CastShadow = true })
		p(Vector3.new(s + 0.05, 0.15, s + 0.05), cf * CFrame.new(0, s * 0.25, 0), DARK_OAK, Enum.Material.Wood)
	end
	crate(at(-1, F + 0.8, 7.2), 2)
	crate(at(1.2, F + 0.8, 7.6), 2)
	crate(at(0, F + 2.4, 7.4) * CFrame.Angles(0, 0.3, 0), 1.6)
	for i = 1, 5 do -- ore heaped in the open crate
		p(Vector3.new(0.6, 0.5, 0.55), at(1.2 + (i % 3 - 1) * 0.5, F + 1.75, 7.6 + (i % 2 - 0.5) * 0.6) * CFrame.Angles(i, i * 2, 0),
			Color3.fromRGB(96, 70, 60), Enum.Material.Slate)
	end
	for i = 0, 2 do
		p(Vector3.new(1.4, 1.6, 1.2), at(-8.2 + i * 0.3, F + 0.8, 6.5 - i * 1.3) * CFrame.Angles(0, i, 0.1 * i), Color3.fromRGB(80, 66, 50), Enum.Material.Fabric,
			{ Shape = Enum.PartType.Ball })
	end
	local bin = at(-8.5, F + 1, -7.5)
	p(Vector3.new(2.4, 2, 2.4), bin, DARK_OAK, Enum.Material.WoodPlanks, { CastShadow = true })
	p(Vector3.new(2.1, 0.2, 2.1), bin * CFrame.new(0, 0.95, 0), Color3.fromRGB(22, 20, 20), Enum.Material.Slate)
	for i = 1, 4 do
		p(Vector3.new(0.6, 0.6, 0.6), bin * CFrame.new(-0.5 + (i % 2), 1.15, -0.4 + math.floor(i / 2) * 0.5), Color3.fromRGB(26, 24, 24), Enum.Material.Slate,
			{ Shape = Enum.PartType.Ball })
	end
	p(Vector3.new(0.14, 3.4, 0.14), bin * CFrame.new(1.35, 0.6, 0.6) * CFrame.Angles(0, 0, -0.35), OAK, Enum.Material.Wood) -- shovel
	p(Vector3.new(0.6, 0.06, 0.7), bin * CFrame.new(1.0, -0.95, 0.6) * CFrame.Angles(0, 0, -0.35), IRON, Enum.Material.Metal)

	-- a chain hoist hanging from the beam over the work, and lanterns
	local hoist = at(3.6, 0, 2.8)
	local chain = p(Vector3.new(0.12, 1, 0.12), hoist, IRON, Enum.Material.DiamondPlate)
	between(chain, (hoist * CFrame.new(0, F + H - 1.9, 0)).Position, (hoist * CFrame.new(0, 3.2, 0)).Position, 0.14)
	p(Vector3.new(0.5, 0.18, 0.5), hoist * CFrame.new(0, 3.1, 0), IRON, Enum.Material.Metal)
	p(Vector3.new(0.12, 0.6, 0.4), hoist * CFrame.new(0, 2.75, 0.12), IRON, Enum.Material.Metal) -- hook
	local function lantern(x: number, z: number, drop: number)
		local top = at(x, F + H - 1.9, z)
		local l = p(Vector3.new(0.1, 1, 0.1), top, IRON, Enum.Material.Metal)
		between(l, top.Position, (top * CFrame.new(0, -drop, 0)).Position, 0.08)
		local body = top * CFrame.new(0, -drop - 0.45, 0)
		p(Vector3.new(0.55, 0.7, 0.55), body, Color3.fromRGB(255, 170, 80), Enum.Material.Neon, { Transparency = 0.1 })
		p(Vector3.new(0.75, 0.12, 0.75), body * CFrame.new(0, 0.42, 0), IRON, Enum.Material.Metal)
		p(Vector3.new(0.75, 0.12, 0.75), body * CFrame.new(0, -0.42, 0), IRON, Enum.Material.Metal)
	end
	lantern(-1.5, 6, 3.5)
	lantern(8, -4, 3)
	lantern(8.5, 7.5, 4)

	-- air: embers drifting, a haze under the roof
	local air = part(folder, Vector3.new(18, 8, 14), root * CFrame.new(-1, 2, -1), Color3.new(), nil, { Transparency = 1 })
	make("ParticleEmitter", {
		Texture = SPARK_TEX, LightEmission = 1, Rate = 4, Color = ColorSequence.new(Color3.fromRGB(255, 150, 60)),
		Size = sequence(0, 0.08, 0.5, 0.12, 1, 0), Transparency = sequence(0, 1, 0.2, 0, 1, 1),
		Lifetime = NumberRange.new(4, 7), Speed = NumberRange.new(0.2, 0.6), SpreadAngle = Vector2.new(180, 180),
		Acceleration = Vector3.new(0, 0.4, 0),
	}, air)
	local haze = part(folder, Vector3.new(22, 1, 20), root * CFrame.new(2, F + H - 3, -2), Color3.new(), nil, { Transparency = 1 })
	make("ParticleEmitter", {
		Texture = SMOKE_TEX, Rate = 1.2, Color = ColorSequence.new(Color3.fromRGB(70, 56, 50)),
		Transparency = sequence(0, 1, 0.3, 0.88, 0.7, 0.88, 1, 1), Size = NumberSequence.new(7),
		Lifetime = NumberRange.new(8, 10), Speed = NumberRange.new(0.1, 0.3), Rotation = NumberRange.new(0, 360),
		RotSpeed = NumberRange.new(-5, 5), LightInfluence = 1,
	}, haze)
end

local function buildScene(slot: string): Scene
	local folder = make("Folder", { Name = "ForgeScene" }, Workspace)
	local root = ORIGIN * CFrame.new(0, 3, 0) -- an R6 root stands 3 above the floor
	local floorY = ORIGIN.Y
	local IRON = Color3.fromRGB(64, 62, 66)
	local DARK_IRON = Color3.fromRGB(42, 40, 44)
	local WOOD = Color3.fromRGB(64, 44, 30)
	local BRICK = Color3.fromRGB(96, 58, 44)
	local FIREBRICK = Color3.fromRGB(120, 72, 50)
	local WATER = Color3.fromRGB(36, 84, 116)

	buildRoom(folder, root)

	-- the smith (your character), the hammer in its right hand, the tongs in its left
	local smith = cloneSmith(folder, root)
	local rArm = smith and smith:FindFirstChild("Right Arm") :: BasePart?
	local lArm = smith and smith:FindFirstChild("Left Arm") :: BasePart?

	local hammer = make("Model", { Name = "Hammer" }, folder)
	local handle = part(hammer, Vector3.new(0.2, 2.1, 0.2), root, Color3.fromRGB(96, 66, 40), Enum.Material.Wood, { Anchored = false, Massless = true })
	local head = part(hammer, Vector3.new(0.6, 0.6, 1.25), root, IRON, Enum.Material.Metal, { Anchored = false, Massless = true })
	make("Weld", { Part0 = handle, Part1 = head, C0 = CFrame.new(0, 0.95, 0) }, head)
	local hammerWeld: Weld? = nil
	if rArm then
		hammerWeld = make("Weld", { Part0 = rArm, Part1 = handle, C0 = CFrame.new(0, -1, 0) * CFrame.Angles(WRIST, 0, 0),
			C1 = CFrame.new(0, -0.85, 0) }, handle)
	else
		handle.Anchored = true
	end

	local tongs = make("Model", { Name = "Tongs" }, folder)
	local rein = part(tongs, Vector3.new(0.1, TONGS_LEN, 0.1), root, DARK_IRON, Enum.Material.Metal, { Anchored = false, Massless = true })
	local rein2 = part(tongs, Vector3.new(0.09, TONGS_LEN * 0.9, 0.09), root, DARK_IRON, Enum.Material.Metal, { Anchored = false, Massless = true })
	make("Weld", { Part0 = rein, Part1 = rein2, C0 = CFrame.new(0.12, 0.05, 0) * CFrame.Angles(0, 0, 0.04) }, rein2)
	for _, x in ipairs({ -0.05, 0.17 }) do -- the jaws
		local jaw = part(tongs, Vector3.new(0.08, 0.3, 0.18), root, DARK_IRON, Enum.Material.Metal, { Anchored = false, Massless = true })
		make("Weld", { Part0 = rein, Part1 = jaw, C0 = CFrame.new(x, -TONGS_LEN / 2 - 0.05, 0) }, jaw)
	end
	local rivet = part(tongs, Vector3.new(0.3, 0.14, 0.14), root, IRON, Enum.Material.Metal, { Anchored = false, Massless = true })
	make("Weld", { Part0 = rein, Part1 = rivet, C0 = CFrame.new(0.06, -TONGS_LEN / 2 + 0.55, 0) }, rivet)
	if lArm then
		make("Weld", { Part0 = lArm, Part1 = rein, C0 = CFrame.new(0, -0.95, 0) * CFrame.Angles(TONGS_BEND, 0, 0) * CFrame.new(0, -TONGS_LEN / 2 + 0.25, 0) }, rein)
	else
		rein.Anchored = true
	end
	local function tongsTip(): Vector3
		return (rein.CFrame * CFrame.new(0.06, -TONGS_LEN / 2, 0)).Position
	end
	local function rightHand(): Vector3
		return if rArm then (rArm.CFrame * CFrame.new(0, -1, 0)).Position else root.Position
	end

	-- Pose the smith at each station and read where its tools land.
	local function measure(p: any)
		if smith then
			CastPoses.play(smith, { { dur = 0.01, pose = p }, { dur = 3600, pose = p } }, 0.3, true, { carry = 0 })
		end
		for _ = 1, 4 do RunService.Heartbeat:Wait() end
	end
	local function lowest(p: BasePart): Vector3
		local best: Vector3? = nil
		for _, sx in ipairs({ -0.5, 0.5 }) do
			for _, sy in ipairs({ -0.5, 0.5 }) do
				for _, sz in ipairs({ -0.5, 0.5 }) do
					local c = (p.CFrame * CFrame.new(p.Size.X * sx, p.Size.Y * sy, p.Size.Z * sz)).Position
					if not best or c.Y < best.Y then best = c end
				end
			end
		end
		return best :: Vector3
	end
	measure(POSE.impact)
	local strike = (root * CFrame.new(1.5, -1.9, -3.4)).Position
	if smith then
		local a = (head.CFrame * CFrame.new(0, 0, 0.625)).Position
		local b = (head.CFrame * CFrame.new(0, 0, -0.625)).Position
		strike = if a.Y < b.Y then a else b
	end
	measure(POSE.setHammer)
	local hammerRest = handle.CFrame
	local hammerLow = lowest(head)
	measure(POSE.pumpUp)
	local handUp = rightHand()
	local coalTip = tongsTip()
	measure(POSE.pumpDown)
	local handDown = rightHand()
	coalTip = (coalTip + tongsTip()) / 2
	measure(POSE.quenchLow)
	local quenchTip = tongsTip()
	measure(POSE.present)
	local presentTip = tongsTip()
	measure(POSE.stand)

	-- ── the anvil (the ingot's top is the strike point): a heavy one, with a
	-- horn, a heel, a stepped waist and a banded stump
	local face = root.Rotation + Vector3.new(strike.X, 0, strike.Z)
	local topY = strike.Y - 0.24
	local anvilTop = part(folder, Vector3.new(3.1, 0.55, 1.3), face + Vector3.new(0, topY - 0.275, 0), IRON, Enum.Material.Metal)
	anvilTop.CastShadow = true
	part(folder, Vector3.new(3.1, 0.05, 1.3), face + Vector3.new(0, topY + 0.02, 0), Color3.fromRGB(120, 118, 124), Enum.Material.Metal) -- the polished face
	local horn = part(folder, Vector3.new(1.3, 0.55, 1.3), (face + Vector3.new(0, topY - 0.275, 0)) * CFrame.new(2.2, 0, 0) * CFrame.Angles(0, math.rad(90), 0),
		IRON, Enum.Material.Metal)
	make("SpecialMesh", { MeshType = Enum.MeshType.Wedge }, horn)
	part(folder, Vector3.new(0.5, 0.4, 1.0), (face + Vector3.new(0, topY - 0.3, 0)) * CFrame.new(-1.75, 0, 0), IRON, Enum.Material.Metal) -- the heel
	local waistH = math.max(0.3, topY - 0.55 - (floorY + 1.5))
	part(folder, Vector3.new(1.6, 0.25, 1.0), face + Vector3.new(0, topY - 0.65, 0), IRON, Enum.Material.Metal)
	part(folder, Vector3.new(1.1, waistH, 0.8), face + Vector3.new(0, floorY + 1.5 + waistH / 2, 0), IRON, Enum.Material.Metal, { CastShadow = true })
	part(folder, Vector3.new(2.4, 0.5, 1.6), face + Vector3.new(0, floorY + 1.35, 0), IRON, Enum.Material.Metal, { CastShadow = true })
	part(folder, Vector3.new(1.1, 2.2, 2.6), (face + Vector3.new(0, floorY + 0.55, 0)) * CFrame.Angles(0, 0, math.rad(90)), WOOD, Enum.Material.Wood,
		{ Shape = Enum.PartType.Cylinder, CastShadow = true }) -- the stump
	part(folder, Vector3.new(0.12, 2.25, 2.65), (face + Vector3.new(0, floorY + 0.8, 0)) * CFrame.Angles(0, 0, math.rad(90)), DARK_IRON, Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder }) -- its band
	part(folder, Vector3.new(0.6, 0.15, 0.15), (face + Vector3.new(0, topY - 0.15, 0)) * CFrame.new(0.4, 0, 0.75), DARK_IRON, Enum.Material.Metal) -- a punch

	-- ── the hammer stand: a block under where the smith sets the hammer down
	local standTop = hammerLow.Y - 0.02
	local standH = math.max(0.4, standTop - floorY)
	local onAnvil = math.abs(hammerLow.Y - topY) < 0.35
	if not onAnvil then part(folder, Vector3.new(1.4, standH, 1.4), CFrame.new(hammerLow.X, floorY + standH / 2, hammerLow.Z) * root.Rotation, WOOD, Enum.Material.Wood,
		{ CastShadow = true }) end

	-- ── the forge: a brick hearth round the coal bed where the tongs reach,
	-- facing the smith, a firebrick back with a glowing throat, a hood and flue
	local bedTop = coalTip.Y - 0.08
	local bedFlat = Vector3.new(coalTip.X, floorY, coalTip.Z)
	local toSmith = Vector3.new(root.Position.X, floorY, root.Position.Z)
	local fcf = CFrame.lookAt(bedFlat, toSmith) * CFrame.new(0, 0, 0.5) -- (-Z faces the smith; the bed sits near the front edge)
	local hearthH = bedTop - 0.3 - floorY
	part(folder, Vector3.new(4.6, hearthH, 3.8), fcf * CFrame.new(0, hearthH / 2, 0.3), BRICK, Enum.Material.Brick, { CastShadow = true })
	part(folder, Vector3.new(4.8, 0.3, 4.0), fcf * CFrame.new(0, hearthH + 0.15, 0.3), Color3.fromRGB(70, 66, 64), Enum.Material.Slate) -- the hearth top
	local coals = part(folder, Vector3.new(2.6, 0.3, 2.2), CFrame.new(Vector3.new(coalTip.X, bedTop - 0.15, coalTip.Z)) * fcf.Rotation,
		Color3.fromRGB(255, 90, 30), Enum.Material.Neon)
	for i = 1, 6 do -- dark lumps round the glowing heart
		local a = i * 1.05
		part(folder, Vector3.new(0.5, 0.45, 0.5), coals.CFrame * CFrame.new(math.cos(a) * 1.2, 0.12, math.sin(a) * 0.95) * CFrame.Angles(a, a, 0),
			Color3.fromRGB(28, 24, 24), Enum.Material.Slate, { Shape = Enum.PartType.Ball })
	end
	part(folder, Vector3.new(4.6, 3.4, 1.0), fcf * CFrame.new(0, hearthH + 1.7, 2.2), FIREBRICK, Enum.Material.Brick, { CastShadow = true }) -- the back
	part(folder, Vector3.new(1.6, 0.9, 0.2), fcf * CFrame.new(0, hearthH + 0.75, 1.68), Color3.fromRGB(255, 120, 40), Enum.Material.Neon) -- the throat
	for _, x in ipairs({ -2.05, 2.05 }) do
		part(folder, Vector3.new(0.6, 3.4, 3.2), fcf * CFrame.new(x, hearthH + 1.7, 0.6), BRICK, Enum.Material.Brick, { CastShadow = true }) -- cheeks
	end
	part(folder, Vector3.new(5.2, 0.5, 3.6), fcf * CFrame.new(0, hearthH + 3.6, 0.5), BRICK, Enum.Material.Brick) -- the lintel
	part(folder, Vector3.new(5.4, 0.25, 0.4), fcf * CFrame.new(0, hearthH + 3.5, -1.2), DARK_IRON, Enum.Material.Metal) -- its iron band
	local hood = part(folder, Vector3.new(5, 2.6, 3.2), fcf * CFrame.new(0, hearthH + 5.15, 0.9), BRICK, Enum.Material.Brick, { CastShadow = true })
	make("SpecialMesh", { MeshType = Enum.MeshType.Wedge, Scale = Vector3.new(1, 1, 1) }, hood)
	part(folder, Vector3.new(5, 2.6, 1.6), fcf * CFrame.new(0, hearthH + 5.15, 2.3), BRICK, Enum.Material.Brick)
	local flueH = (floorY + 15) - (floorY + hearthH + 6.4)
	part(folder, Vector3.new(2, flueH, 2), fcf * CFrame.new(0, hearthH + 6.4 + flueH / 2, 2.1), BRICK, Enum.Material.Brick, { CastShadow = true })
	-- the forge's tools: a poker and a rake leaning on the cheek, a water can
	part(folder, Vector3.new(0.1, 3.4, 0.1), fcf * CFrame.new(2.55, 1.7, -1.3) * CFrame.Angles(0.15, 0, -0.2), DARK_IRON, Enum.Material.Metal)
	part(folder, Vector3.new(0.1, 3.2, 0.1), fcf * CFrame.new(2.7, 1.6, -0.9) * CFrame.Angles(-0.1, 0, -0.25), DARK_IRON, Enum.Material.Metal)
	part(folder, Vector3.new(0.6, 0.6, 0.6), fcf * CFrame.new(-2.7, 0.3, -1.6), Color3.fromRGB(80, 84, 90), Enum.Material.Metal,
		{ Shape = Enum.PartType.Cylinder })

	local fire = make("Fire", { Heat = 6, Size = 4, Color = Color3.fromRGB(255, 120, 40), SecondaryColor = Color3.fromRGB(255, 40, 10) }, coals)
	local embers = make("ParticleEmitter", {
		Texture = SPARK_TEX, LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 160, 60), Color3.fromRGB(255, 60, 20)),
		Size = sequence(0, 0.15, 1, 0),
		Lifetime = NumberRange.new(1, 2), Rate = 8, Speed = NumberRange.new(2, 4), SpreadAngle = Vector2.new(25, 25),
		Acceleration = Vector3.new(0, 2, 0),
	}, coals)
	make("ParticleEmitter", { -- smoke curling up into the hood
		Texture = SMOKE_TEX, Rate = 3, Color = ColorSequence.new(Color3.fromRGB(60, 52, 48)),
		Transparency = sequence(0, 1, 0.2, 0.75, 1, 1), Size = sequence(0, 1, 1, 3.5),
		Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(1.5, 2.5), SpreadAngle = Vector2.new(12, 12),
		RotSpeed = NumberRange.new(-20, 20), Rotation = NumberRange.new(0, 360), LightInfluence = 1,
	}, coals)
	local hearthLight = make("PointLight", { Color = Color3.fromRGB(255, 130, 60), Range = 28, Brightness = 2.5, Shadows = true }, coals)

	-- ── the great bellows: a lever on a post, worked by the right hand; a rod
	-- from the lever to the bellows' top board; a pipe (the tuyere) to the fire
	local mid = (handUp + handDown) / 2
	local toForge = Vector3.new(coalTip.X - root.Position.X, 0, coalTip.Z - root.Position.Z)
	toForge = if toForge.Magnitude > 0.1 then toForge.Unit else -root.RightVector
	local pivot = mid + toForge * 2.6 + Vector3.new(0, 0.4, 0)
	part(folder, Vector3.new(0.5, pivot.Y - floorY + 0.3, 0.5), CFrame.new(pivot.X, (pivot.Y + floorY) / 2 + 0.15, pivot.Z), WOOD, Enum.Material.Wood,
		{ CastShadow = true }) -- the post
	part(folder, Vector3.new(0.3, 0.3, 0.7), CFrame.lookAt(pivot, pivot + toForge:Cross(Vector3.yAxis)), DARK_IRON, Enum.Material.Metal) -- the pin
	local lever = part(folder, Vector3.new(0.22, 0.22, 3), CFrame.new(pivot), WOOD, Enum.Material.Wood)
	local leverGrip = part(folder, Vector3.new(0.6, 0.18, 0.18), CFrame.new(handUp), Color3.fromRGB(48, 33, 23), Enum.Material.Wood)
	local bellowsAt = mid + (pivot - mid) * 0.6
	local bcf = CFrame.lookAt(Vector3.new(bellowsAt.X, floorY, bellowsAt.Z), Vector3.new(pivot.X, floorY, pivot.Z))
	local BELLOWS_LOW, BELLOWS_HIGH = 1.0, 2.2
	part(folder, Vector3.new(1.6, 0.6, 2.6), bcf * CFrame.new(0, 0.3, 0), WOOD, Enum.Material.Wood) -- its stand
	part(folder, Vector3.new(1.9, 0.15, 2.9), bcf * CFrame.new(0, 0.7, 0), WOOD, Enum.Material.WoodPlanks) -- the bottom board
	local bellowsBody = part(folder, Vector3.new(1.7, 1, 2.6), bcf * CFrame.new(0, 1.2, 0), Color3.fromRGB(110, 70, 44), Enum.Material.Fabric)
	local bellowsTop = part(folder, Vector3.new(1.9, 0.15, 2.9), bcf * CFrame.new(0, BELLOWS_HIGH, 0), WOOD, Enum.Material.WoodPlanks)
	local rod = part(folder, Vector3.new(0.1, 0.1, 1), bcf, DARK_IRON, Enum.Material.Metal)
	local nozzleFrom = (bcf * CFrame.new(0, 0.9, -1.4)).Position
	local nozzleTo = Vector3.new(coals.Position.X, floorY + hearthH - 0.3, coals.Position.Z) + (fcf.LookVector * -0.2)
	local pipe = part(folder, Vector3.new(0.3, 0.3, 1), bcf, DARK_IRON, Enum.Material.Metal)
	between(pipe, nozzleFrom, nozzleTo, 0.3)
	local puffAtt = make("Attachment", { WorldPosition = coals.Position + Vector3.new(0, 0.2, 0) }, Workspace.Terrain)
	local puff = make("ParticleEmitter", {
		Texture = SPARK_TEX, Enabled = false, LightEmission = 1, Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), Color3.fromRGB(255, 90, 30)),
		Size = sequence(0, 0.18, 1, 0), EmissionDirection = Enum.NormalId.Top,
		Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(5, 9), SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 4, 0),
	}, puffAtt)

	-- ── the slack tub (the quench), where the tongs go down on the right
	local surfaceY = quenchTip.Y + 0.35
	local tubFlat = Vector3.new(quenchTip.X, floorY, quenchTip.Z)
	-- (an open tub: the solid body stops under the waterline, the water fills
	-- the top, and a ring of staves stands above it as the rim)
	local tubH = math.max(0.8, surfaceY - 0.04 - floorY)
	local tubCF = CFrame.new(tubFlat) * root.Rotation
	local RIM = 0.3
	part(folder, Vector3.new(tubH, 2.8, 2.8), tubCF * CFrame.new(0, tubH / 2, 0) * CFrame.Angles(0, 0, math.rad(90)), WOOD, Enum.Material.WoodPlanks,
		{ Shape = Enum.PartType.Cylinder, CastShadow = true })
	for _, y in ipairs({ 0.3, tubH - 0.25 }) do
		part(folder, Vector3.new(0.14, 2.88, 2.88), tubCF * CFrame.new(0, y, 0) * CFrame.Angles(0, 0, math.rad(90)), DARK_IRON, Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder })
	end
	local STAVES = 16
	for i = 0, STAVES - 1 do
		local a = i / STAVES * math.pi * 2
		part(folder, Vector3.new(0.56, tubH + RIM, 0.16), tubCF * CFrame.Angles(0, a, 0) * CFrame.new(0, (tubH + RIM) / 2, -1.33), WOOD, Enum.Material.WoodPlanks)
	end
	local water = part(folder, Vector3.new(0.1, 2.56, 2.56), tubCF * CFrame.new(0, surfaceY - floorY, 0) * CFrame.Angles(0, 0, math.rad(90)),
		WATER, Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder })
	part(folder, Vector3.new(0.02, 1.6, 1.6), tubCF * CFrame.new(0.3, surfaceY - floorY + 0.055, -0.2) * CFrame.Angles(0, 0, math.rad(90)),
		Color3.fromRGB(70, 120, 150), Enum.Material.SmoothPlastic, { Shape = Enum.PartType.Cylinder, Transparency = 0.5 }) -- a sheen on it
	part(folder, Vector3.new(2.5, 0.03, 1.8), tubCF * CFrame.new(1.6, 0.02, -1.2), Color3.fromRGB(30, 40, 46), Enum.Material.Glass,
		{ Transparency = 0.3 }) -- a puddle
	-- a bucket of water: upright, iron-hooped, filled near the brim, a rope handle
	local bucketCF = tubCF * CFrame.new(1.9, 0, 1.0) -- (the tub's far side, clear of the anvil)
	local upright = CFrame.Angles(0, 0, math.rad(90))
	part(folder, Vector3.new(0.78, 0.95, 0.95), bucketCF * CFrame.new(0, 0.39, 0) * upright, WOOD, Enum.Material.WoodPlanks,
		{ Shape = Enum.PartType.Cylinder }) -- (its body stops under the waterline; staves make the rim)
	for i = 0, 9 do
		part(folder, Vector3.new(0.3, 0.2, 0.07), bucketCF * CFrame.Angles(0, i / 10 * math.pi * 2, 0) * CFrame.new(0, 0.86, -0.45), WOOD, Enum.Material.WoodPlanks)
	end
	for _, y in ipairs({ 0.15, 0.75 }) do
		part(folder, Vector3.new(0.08, 1.0, 1.0), bucketCF * CFrame.new(0, y, 0) * upright, DARK_IRON, Enum.Material.Metal,
			{ Shape = Enum.PartType.Cylinder })
	end
	part(folder, Vector3.new(0.04, 0.82, 0.82), bucketCF * CFrame.new(0, 0.82, 0) * upright, WATER, Enum.Material.SmoothPlastic,
		{ Shape = Enum.PartType.Cylinder }) -- the water (plain, not glass: glass mirrors the sky outside and reads white)
	part(folder, Vector3.new(0.05, 0.6, 0.05), bucketCF * CFrame.new(0.47, 1.15, 0) * CFrame.Angles(0, 0, 0.5), Color3.fromRGB(140, 110, 70), Enum.Material.Fabric)
	part(folder, Vector3.new(0.05, 0.6, 0.05), bucketCF * CFrame.new(-0.47, 1.15, 0) * CFrame.Angles(0, 0, -0.5), Color3.fromRGB(140, 110, 70), Enum.Material.Fabric)
	part(folder, Vector3.new(0.7, 0.06, 0.06), bucketCF * CFrame.new(0, 1.41, 0), Color3.fromRGB(140, 110, 70), Enum.Material.Fabric)

	-- ── the work: a cold bar on the anvil to start; its shimmer and stray sparks
	local anvilSpot = strike - Vector3.new(0, 0.12, 0)
	local ingot = part(folder, INGOT, CFrame.new(anvilSpot) * root.Rotation, heatColor(0), Enum.Material.Metal)
	local ingotAtt = make("Attachment", {}, ingot)
	local shimmer = make("ParticleEmitter", { -- (Roblox has no refraction: a faint rising wobble of hot air)
		Texture = SMOKE_TEX, Rate = 0, Color = ColorSequence.new(Color3.fromRGB(255, 200, 160)),
		Transparency = sequence(0, 1, 0.3, 0.9, 1, 1), Size = sequence(0, 0.4, 1, 1.4), LightEmission = 0.3,
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(1.5, 2.5), SpreadAngle = Vector2.new(10, 10),
		Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-60, 60), EmissionDirection = Enum.NormalId.Top,
	}, ingotAtt)
	local ingotSparks = make("ParticleEmitter", {
		Texture = SPARK_TEX, Enabled = false, LightEmission = 1,
		Color = ColorSequence.new(Color3.fromRGB(255, 200, 110), Color3.fromRGB(255, 80, 20)),
		Size = sequence(0, 0.14, 1, 0), Lifetime = NumberRange.new(0.3, 0.7), Speed = NumberRange.new(3, 7),
		SpreadAngle = Vector2.new(60, 60), Acceleration = Vector3.new(0, -18, 0), EmissionDirection = Enum.NormalId.Top,
	}, ingotAtt)

	-- the blow: sparks, streaks, a flash and a shockwave ring at the strike point
	local strikeAtt = make("Attachment", { WorldPosition = strike }, Workspace.Terrain)
	local sparks = make("ParticleEmitter", {
		Texture = SPARK_TEX, LightEmission = 1, Enabled = false,
		Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), Color3.fromRGB(255, 120, 30)),
		Size = sequence(0, 0.3, 1, 0),
		Lifetime = NumberRange.new(0.25, 0.6), Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(75, 75),
		Acceleration = Vector3.new(0, -40, 0), EmissionDirection = Enum.NormalId.Top, Drag = 2,
	}, strikeAtt)
	local streaks = make("ParticleEmitter", { -- long, fast, flat: the radial spray off the anvil
		Texture = SPARK_TEX, LightEmission = 1, Enabled = false, Orientation = Enum.ParticleOrientation.VelocityParallel,
		Color = ColorSequence.new(Color3.fromRGB(255, 245, 210), Color3.fromRGB(255, 140, 40)),
		Size = sequence(0, 0.12, 1, 0.02), Squash = NumberSequence.new(-2.5),
		Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(18, 34), SpreadAngle = Vector2.new(85, 85),
		Acceleration = Vector3.new(0, -30, 0), EmissionDirection = Enum.NormalId.Top, Drag = 3,
	}, strikeAtt)
	local burst = make("ParticleEmitter", {
		Texture = SPARK_TEX, LightEmission = 1, Enabled = false,
		Size = sequence(0, 0.5, 1, 0),
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(4, 10), SpreadAngle = Vector2.new(180, 180),
	}, strikeAtt)
	local motes = make("ParticleEmitter", { -- rarity motes rising slowly after the reveal
		Texture = SPARK_TEX, LightEmission = 1, Enabled = false, Rate = 0,
		Size = sequence(0, 0, 0.2, 0.18, 1, 0), Lifetime = NumberRange.new(1.4, 2.4), Speed = NumberRange.new(0.6, 1.6),
		SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, 1.2, 0), EmissionDirection = Enum.NormalId.Top,
	}, strikeAtt)
	local flash = make("PointLight", { Color = Color3.fromRGB(255, 200, 120), Range = 12, Brightness = 0 }, strikeAtt)
	local ring = part(folder, Vector3.new(0.05, 0.3, 0.3), CFrame.new(strike) * CFrame.Angles(0, 0, math.rad(90)), WHITE_GOLD, Enum.Material.Neon,
		{ Shape = Enum.PartType.Cylinder, Transparency = 1 })
	local pillar = part(folder, Vector3.new(0.4, 14, 0.4), CFrame.new(presentTip + Vector3.new(0, 7, 0)), WHITE_GOLD, Enum.Material.Neon,
		{ Transparency = 1 })

	-- the quench: layered steam, embers inside it, a lamp lighting it from behind
	local steamAtt = make("Attachment", { WorldPosition = water.Position + Vector3.new(0, 0.2, 0) }, Workspace.Terrain)
	local function steamLayer(props: { [string]: any }): ParticleEmitter
		local base = {
			Texture = SMOKE_TEX, Enabled = false, Color = ColorSequence.new(Color3.fromRGB(232, 232, 238)),
			EmissionDirection = Enum.NormalId.Top, Rotation = NumberRange.new(0, 360), LightInfluence = 1,
		}
		for k, v in pairs(props) do base[k] = v end
		return make("ParticleEmitter", base, steamAtt)
	end
	local steamBig = steamLayer({
		Transparency = sequence(0, 0.2, 0.6, 0.6, 1, 1), Size = sequence(0, 2.5, 1, 10),
		Lifetime = NumberRange.new(2.4, 3.4), Speed = NumberRange.new(3, 6), SpreadAngle = Vector2.new(35, 35),
		RotSpeed = NumberRange.new(-25, 25), Drag = 0.8,
	})
	local steamJet = steamLayer({
		Transparency = sequence(0, 0.35, 1, 1), Size = sequence(0, 0.5, 1, 3),
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(12, 18), SpreadAngle = Vector2.new(18, 18),
		RotSpeed = NumberRange.new(-90, 90), Drag = 2,
	})
	local steamFog = steamLayer({
		Transparency = sequence(0, 1, 0.25, 0.65, 1, 1), Size = sequence(0, 3, 1, 7), Rate = 6,
		Lifetime = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(0.6, 1.4), SpreadAngle = Vector2.new(60, 60),
		RotSpeed = NumberRange.new(-10, 10),
	})
	local steamGlow = make("ParticleEmitter", {
		Texture = SPARK_TEX, Enabled = false, LightEmission = 1, Color = ColorSequence.new(Color3.fromRGB(255, 170, 90)),
		Size = sequence(0, 0.12, 1, 0), Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(2, 6),
		SpreadAngle = Vector2.new(40, 40), Acceleration = Vector3.new(0, 1, 0), EmissionDirection = Enum.NormalId.Top,
	}, steamAtt)
	local droplets = make("ParticleEmitter", {
		Texture = SPARK_TEX, Enabled = false, Color = ColorSequence.new(Color3.fromRGB(180, 210, 230)),
		Size = sequence(0, 0.1, 1, 0.06), Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(5, 9),
		SpreadAngle = Vector2.new(50, 50), Acceleration = Vector3.new(0, -35, 0), EmissionDirection = Enum.NormalId.Top,
	}, steamAtt)
	local steamLight = make("PointLight", { Color = Color3.fromRGB(255, 150, 80), Range = 14, Brightness = 0, Enabled = false }, steamAtt)

	-- (the attachments live under Terrain: tidied with the folder)
	folder.Destroying:Connect(function()
		strikeAtt:Destroy()
		steamAtt:Destroy()
		puffAtt:Destroy()
	end)

	-- the shots (three-quarter views from the front right, the forge glowing beyond)
	local function shot(pos: Vector3, look: Vector3): CFrame
		return CFrame.lookAt((root * CFrame.new(pos)).Position, look)
	end
	local chest = root.Position + Vector3.new(0, 0.6, 0)
	local shots = {
		intro = shot(Vector3.new(11, 8, 4), (chest + coals.Position) / 2),
		heat = shot(Vector3.new(5.5, 3.6, -11.5), chest:Lerp(coals.Position, 0.45)),
		hammer = shot(Vector3.new(10, 3.8, -8), chest:Lerp(strike, 0.45) + Vector3.new(0, 0.3, 0)),
		finale = shot(Vector3.new(7.5, 2.6, -6.5), chest:Lerp(strike, 0.6)),
		quench = shot(Vector3.new(7.5, 3.6, -10), chest:Lerp(water.Position, 0.5)),
		reveal = shot(Vector3.new(6.2, 3.4, -7.8), presentTip - Vector3.new(0, 1.1, 0)),
		revealWide = shot(Vector3.new(9.5, 4.4, -11), presentTip - Vector3.new(0, 1.1, 0)),
	}

	return {
		folder = folder, root = root, smith = smith, slot = slot,
		rArm = rArm, lArm = lArm, rein = rein, tongsTip = tongsTip, rightHand = rightHand,
		handle = handle, hammerWeld = hammerWeld, hammerRest = hammerRest,
		ingot = ingot, coals = coals, fire = fire, embers = embers, hearthLight = hearthLight, flash = flash,
		lever = lever, leverGrip = leverGrip, pivot = pivot, handUp = handUp, handDown = handDown,
		bellowsBody = bellowsBody, bellowsTop = bellowsTop, bcf = bcf, bellowsLow = BELLOWS_LOW, bellowsHigh = BELLOWS_HIGH, rod = rod, puff = puff,
		shimmer = shimmer, ingotSparks = ingotSparks,
		sparks = sparks, streaks = streaks, burst = burst, motes = motes, ring = ring, pillar = pillar, strikeAtt = strikeAtt,
		steamBig = steamBig, steamJet = steamJet, steamFog = steamFog, steamGlow = steamGlow, droplets = droplets, steamLight = steamLight,
		anvilTop = strike, anvilSpot = anvilSpot, quenchSpot = water.Position,
		shots = shots,
	}
end

-- ── The overlay (kept small: the scene is the show) ─────────────────────────
local function text(parent: Instance, t: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = make("TextLabel", {
		BackgroundTransparency = 1, FontFace = BOLD, Text = t, TextSize = size, TextColor3 = color,
		TextStrokeTransparency = 0.35, Size = UDim2.new(1, 0, 0, size + 6),
	}, parent)
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	return l
end

local function corner(o: Instance, r: number)
	make("UICorner", { CornerRadius = UDim.new(0, r) }, o)
end

-- how hard the frame rate is struggling (0..1): particle counts shrink with it
local fxBudget: any = nil
pcall(function() fxBudget = require(script.Parent.Parent:WaitForChild("FxBudget", 5) :: ModuleScript) end)
local function fxScale(): number
	local p = 0
	if fxBudget and fxBudget.Pressure then
		local ok, v = pcall(fxBudget.Pressure)
		if ok and typeof(v) == "number" then p = v end
	end
	return 1 - 0.6 * math.clamp(p, 0, 1)
end
local function emit(e: ParticleEmitter, n: number)
	local k = math.max(1, math.floor(n * fxScale() + 0.5))
	e:Emit(k)
end

local playing = false
local armoryToRestore: ScreenGui? = nil -- (re-opened when you're done, after any FORGE AGAIN)

function ForgeMinigame.Play(slot: string)
	if playing then return end
	playing = true
	local slotName = string.upper(PowerGear.SLOT_NAME[slot] or slot)
	local pg = player:WaitForChild("PlayerGui")

	-- every other screen steps aside while you forge (the Armory comes back after;
	-- the HUDs that keep themselves up watch "Forging")
	player:SetAttribute("Forging", true)
	local hidden: { ScreenGui } = {}
	for _, sg in ipairs(pg:GetChildren()) do
		if sg:IsA("ScreenGui") and sg.Enabled and sg.Name ~= "Armory" and sg.Name ~= "ForgeMinigame" then
			sg.Enabled = false
			table.insert(hidden, sg)
		end
	end
	local armoryGui = pg:FindFirstChild("Armory") :: ScreenGui?
	if armoryGui and armoryGui.Enabled then
		armoryToRestore = armoryGui
		armoryGui.Enabled = false
	end

	-- the overlay (a black cover first: the smithy is set up behind it)
	local g = make("ScreenGui", { Name = "ForgeMinigame", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 70 }, pg)
	local cover = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0, ZIndex = 50 }, g)

	local scene = buildScene(slot)
	local shots = scene.shots
	local smith = scene.smith

	-- ── sound ───────────────────────────────────────────────────────────────
	local lastHit = 0
	local function sfx(id: string, volume: number, speed: number?): Sound
		local s = make("Sound", { SoundId = id, Volume = volume, PlaybackSpeed = (speed or 1) * (0.96 + math.random() * 0.08) }, scene.folder)
		s:Play()
		s.Ended:Once(function() s:Destroy() end)
		task.delay(8, function() if s.Parent then s:Destroy() end end)
		return s
	end
	local function hitSound(volume: number, speed: number)
		local i = math.random(1, #SFX.hits - 1)
		if i >= lastHit then i += 1 end -- (never the same clip twice running)
		lastHit = i
		sfx(SFX.hits[i], volume, speed)
	end
	local fireLoop = make("Sound", { SoundId = SFX.fire, Volume = 0, Looped = true }, scene.folder)
	fireLoop:Play()
	tween(fireLoop, 1, { Volume = 0.25 })

	-- ── the camera: shots it glides between, a slow sway, trauma shake, FOV kicks
	local cam = Workspace.CurrentCamera
	local oldType = cam.CameraType
	local oldSubject = cam.CameraSubject
	local oldFov = cam.FieldOfView
	local BASE_FOV = 50
	local shotCF: CFrame = shots.intro
	local camCF: CFrame = shots.intro
	local camSpeed = 2
	local trauma = 0
	local fovKick = 0
	local function setShot(cf: CFrame, speed: number?)
		shotCF = cf
		camSpeed = speed or 3
	end
	local function cutTo(cf: CFrame) -- (a hard cut: only while something hides it)
		shotCF = cf
		camCF = cf
	end
	local function shake(amount: number)
		trauma = math.min(1.6, math.max(trauma, amount))
	end
	cam.CameraType = Enum.CameraType.Scriptable
	cam.FieldOfView = BASE_FOV
	local cc = make("ColorCorrectionEffect", { Name = "ForgeGrade", Saturation = -0.12, Contrast = 0.1, TintColor = Color3.fromRGB(255, 246, 238) }, cam)
	local bloom = make("BloomEffect", { Name = "ForgeBloom", Intensity = 0.35, Size = 20, Threshold = 2.2 }, cam)
	-- the smithy lights itself, whatever the hour outside (put back on close)
	local Lighting = game:GetService("Lighting")
	local oldAmbient, oldOutdoor, oldExposure = Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ExposureCompensation
	Lighting.Ambient = Color3.fromRGB(78, 58, 46)
	Lighting.OutdoorAmbient = Color3.fromRGB(78, 58, 46)
	Lighting.ExposureCompensation = 0.25
	RunService:BindToRenderStep("ForgeCamera", Enum.RenderPriority.Camera.Value + 10, function(dt: number)
		cam.CameraType = Enum.CameraType.Scriptable
		camCF = camCF:Lerp(shotCF, 1 - math.exp(-camSpeed * dt))
		local t = os.clock()
		local sway = CFrame.Angles(math.sin(t * 0.6) * 0.004, math.sin(t * 0.45) * 0.006, 0)
		local cf = camCF * sway
		if trauma > 0.01 then
			local k = trauma * trauma
			cf *= CFrame.new(math.noise(t * 22, 1.3) * 0.35 * k, math.noise(t * 22, 7.1) * 0.35 * k, 0)
				* CFrame.Angles(0, 0, math.noise(t * 18, 3.7) * 0.02 * k)
			trauma = math.max(0, trauma - dt * 3)
		end
		fovKick *= math.exp(-dt * 6)
		cam.FieldOfView = BASE_FOV + fovKick
		cam.CFrame = cf
	end)

	-- (a vignette, so the overlay reads against the fire)
	local vig = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0 }, g)
	make("UIGradient", { Transparency = sequence(0, 0.35, 0.22, 1, 0.78, 1, 1, 0.3), Rotation = 90 }, vig)
	-- the steam that fills the screen at the quench, and a flash for the big moments
	local steamScreen = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(226, 226, 232), BackgroundTransparency = 1,
		ZIndex = 5 }, g)
	make("UIGradient", { Transparency = sequence(0, 0.25, 0.5, 0, 1, 0.25), Rotation = 90 }, steamScreen)
	local flashScreen = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE_GOLD, BackgroundTransparency = 1, ZIndex = 6 }, g)
	local function screenFlash(color: Color3, strength: number, time: number)
		flashScreen.BackgroundColor3 = color
		flashScreen.BackgroundTransparency = 1 - strength
		tween(flashScreen, time, { BackgroundTransparency = 1 })
	end

	text(g, "THE FORGE", 30, GOLD, { Position = UDim2.fromOffset(0, 26), Font = Enum.Font.Antique, ZIndex = 10 })
	local phaseLabel = text(g, `FORGING A {slotName}`, 14, PARCH, { Position = UDim2.fromOffset(0, 62), ZIndex = 10 })
	local hint = text(g, "", 16, PARCH, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -26), ZIndex = 10 })
	-- a grade (or a heat score) springs up, rises and fades
	local function pop(t: string, color: Color3, big: boolean?)
		local l = text(g, t, if big then 44 else 34, color, { Position = UDim2.new(0, 0, 0.3, 0), TextStrokeTransparency = 0.1, ZIndex = 10 })
		local sc = make("UIScale", { Scale = if big then 1.6 else 1.3 }, l)
		tween(sc, 0.22, { Scale = 1 }, Enum.EasingStyle.Back)
		task.delay(0.25, function()
			if not l.Parent then return end
			tween(l, 0.65, { Position = UDim2.new(0, 0, 0.3, -40), TextTransparency = 1, TextStrokeTransparency = 1 })
		end)
		task.delay(0.95, function() l:Destroy() end)
	end

	-- SKIP: the piece forged as if every strike was perfect, for Robux (a
	-- skip you already hold is used first: StoreManager). The forged piece
	-- arrives as the usual LootDrop; the minigame then jumps to the reveal.
	local result: any = nil
	local skipped = false
	local resultConn = Network.GetRemoteEvent(Network.Remotes.LootDrop).OnClientEvent:Connect(function(d: any)
		if typeof(d) == "table" and d.source == "forge" then
			result = d
			if not skipped and player:GetAttribute("ForgeSkipping") == true then skipped = true end
		end
	end)
	local skipBtn: TextButton? = nil
	local function skipText(): string
		local held = player:GetAttribute("ForgeSkips")
		if typeof(held) == "number" and held > 0 then return `SKIP  ·  {held} LEFT` end
		return `SKIP  ·  R$ {StoreConfig.ForgeSkip.robux}`
	end
	local held0 = player:GetAttribute("ForgeSkips")
	if StoreConfig.ForgeSkip.productId > 0 or (typeof(held0) == "number" and held0 > 0) then
		local b = make("TextButton", { Name = "Skip", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -24, 0, 24), Size = UDim2.fromOffset(170, 38),
			BackgroundColor3 = Color3.fromRGB(0, 132, 84), FontFace = BOLD, TextSize = 15, TextColor3 = Color3.new(1, 1, 1), Text = skipText(), ZIndex = 10 }, g)
		corner(b, 6)
		b.Activated:Connect(function()
			player:SetAttribute("ForgeSkipping", true)
			Network.GetRemoteEvent(Network.Remotes.StoreAction):FireServer({ kind = "forgeSkip", slot = slot })
		end)
		player:GetAttributeChangedSignal("ForgeSkips"):Connect(function()
			if b.Parent then b.Text = skipText() end
		end)
		skipBtn = b
	end
	local storeConn = Network.GetRemoteEvent(Network.Remotes.StoreResult).OnClientEvent:Connect(function(d: any)
		if typeof(d) == "table" and d.kind == "forgeSkip" and not d.ok then
			player:SetAttribute("ForgeSkipping", nil)
			pop(tostring(d.message), RED)
		end
	end)

	-- input: bound above the game's own (Space would jump), sunk while forging
	local holding, pressed = false, false
	local acceptAfter = 0 -- (presses before this are ignored: the phase just started)
	ContextActionService:BindActionAtPriority("ForgeMinigame", function(_, state)
		if state == Enum.UserInputState.Begin then
			holding = true
			if os.clock() >= acceptAfter then pressed = true end
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			holding = false
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Space, Enum.KeyCode.ButtonA, Enum.UserInputType.MouseButton1, Enum.UserInputType.Touch)

	-- ── the smith's body: stages eased into, the last one held ───────────────
	local function act(stages: { any }, carry: number?)
		if not smith then return end
		local list = table.clone(stages)
		local last = list[#list]
		table.insert(list, { dur = 3600, pose = last.pose, wobble = last.wobble })
		CastPoses.play(smith, list, 0.3, true, { carry = carry or 1 })
	end
	local SINE, CUBIC, QUART = Enum.EasingStyle.Sine, Enum.EasingStyle.Cubic, Enum.EasingStyle.Quart
	-- breathing while a pose holds (and the coil tightening as the marker nears)
	local nearK = 0
	local function breathe(t: number): any
		local b = math.sin(t * 2.6)
		return { W = { b * 0.8 + nearK * 6, -nearK * 5, 0 }, RS = { b * 1.5 + nearK * 9, 0, 0 }, N = { -b * 0.6, 0, 0 } }
	end

	-- the hammer: set down on its stand, taken up again (the weld is the grip)
	local function hammerDown()
		local hw = scene.hammerWeld :: Weld?
		if hw then
			local cf = scene.handle.CFrame
			hw.Enabled = false
			scene.handle.Anchored = true
			scene.handle.CFrame = cf
		end
	end
	local function hammerUp()
		local hw = scene.hammerWeld :: Weld?
		if hw then
			scene.handle.Anchored = false
			hw.Enabled = true
		end
	end

	-- the work in the tongs (follows the jaws, eased in when gripped) or lying free
	local held = false
	local holdFrom: CFrame = scene.ingot.CFrame
	local holdT0 = 0
	local HOLD_BLEND = 0.2
	local shapeRot = CFrame.identity -- (a ring or charm ends up a flat disc)
	local inspectSpin = 0
	local function workLength(): number
		return if scene.ingot.Shape == Enum.PartType.Cylinder then scene.ingot.Size.Y else scene.ingot.Size.X
	end
	local function heldCF(): CFrame
		local tc = scene.rein.CFrame
		local tip = scene.tongsTip()
		local d = -tc.UpVector
		local dh = Vector3.new(d.X, 0, d.Z)
		dh = if dh.Magnitude > 0.05 then dh.Unit else scene.root.LookVector
		local center = tip + dh * (workLength() / 2 - 0.1)
		return CFrame.lookAt(center, center + dh) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(inspectSpin, 0, 0) * shapeRot
	end
	local function grip()
		held = true
		holdFrom = scene.ingot.CFrame
		holdT0 = os.clock()
	end
	local function anvilCF(): CFrame
		local size = scene.ingot.Size
		local thick = if scene.ingot.Shape == Enum.PartType.Cylinder then size.X else size.Y
		local bottom = scene.anvilSpot.Y - INGOT.Y / 2
		return CFrame.new(Vector3.new(scene.anvilSpot.X, bottom + thick / 2, scene.anvilSpot.Z)) * scene.root.Rotation * shapeRot
	end
	local function layDown(time: number)
		held = false
		tween(scene.ingot, time, { CFrame = anvilCF() }, Enum.EasingStyle.Quad)
	end

	-- the lever follows the right hand while it works the bellows; the rod and
	-- the bellows' top board follow the lever
	local onLever = false
	local leverEnd: Vector3 = scene.handUp
	local propsConn = RunService.Heartbeat:Connect(function()
		if held then
			local target = heldCF()
			local k = math.clamp((os.clock() - holdT0) / HOLD_BLEND, 0, 1)
			scene.ingot.CFrame = if k < 1 then holdFrom:Lerp(target, k * k * (3 - 2 * k)) else target
		end
		if onLever then leverEnd = scene.rightHand() end
		local pivot = scene.pivot :: Vector3
		local dir = (leverEnd - pivot)
		local tipAt = leverEnd + dir.Unit * 0.25
		between(scene.lever, pivot, tipAt, 0.22)
		scene.leverGrip.CFrame = CFrame.lookAt(leverEnd, leverEnd + dir) * CFrame.Angles(0, math.rad(90), 0)
		local k = math.clamp((leverEnd.Y - scene.handDown.Y) / math.max(0.2, scene.handUp.Y - scene.handDown.Y), 0, 1)
		local topH = scene.bellowsLow + (scene.bellowsHigh - scene.bellowsLow) * k
		local bcf = scene.bcf :: CFrame
		scene.bellowsTop.CFrame = bcf * CFrame.new(0, topH, 0)
		scene.bellowsBody.Size = Vector3.new(1.7, topH - 0.75, 2.6)
		scene.bellowsBody.CFrame = bcf * CFrame.new(0, 0.75 + (topH - 0.75) / 2, 0)
		local onLeverAt = pivot + (leverEnd - pivot) * 0.6
		between(scene.rod, onLeverAt, (bcf * CFrame.new(0, topH, 0)).Position, 0.1)
	end)

	-- the ingot's look: its heat, darkened when it's losing it, gilded after a perfect blow
	local glow = 0
	local function setIngot(h: number, darken: number?, gild: number?)
		local c = heatColor(h)
		if darken and darken > 0 then c = c:Lerp(Color3.fromRGB(30, 20, 18), darken) end
		if gild and gild > 0 then c = c:Lerp(GLOW_GOLD, gild) end
		scene.ingot.Color = c
		scene.ingot.Material = if h < 0.3 and (gild or 0) <= 0 then Enum.Material.Metal else Enum.Material.Neon
	end

	-- ── 0. PREPARE: hammer to its stand, the cold bar into the coals ─────────
	phaseLabel.Text = `FORGING A {slotName}`
	hint.Text = "The metal is cold. Ready the fire."
	act({ { dur = 0.01, pose = POSE.stand, wobble = breathe } }, 0)
	tween(cover, 0.6, { BackgroundTransparency = 1 })
	setShot(shots.heat, 1.4)
	task.wait(0.25)
	if not skipped then
		-- the hammer onto its stand
		act({ { dur = 0.55, pose = POSE.setHammer, style = SINE } })
		task.wait(0.55)
		hammerDown()
		hitSound(0.15, 1.7)
		-- the tongs onto the cold bar
		act({ { dur = 0.45, pose = POSE.stand, style = SINE }, { dur = 0.45, pose = POSE.grab, style = SINE } })
		task.wait(0.9)
		grip()
		hitSound(0.08, 2.2)
		task.wait(0.12)
		-- lifted, turned to the forge, and buried in the coals; the hand finds the lever
		act({ { dur = 0.35, pose = POSE.lower, style = SINE }, { dur = 0.6, pose = POSE.pumpUp, style = SINE } })
		task.wait(0.95)
		emit(scene.embers, 12)
		sfx(SFX.bellows, 0.15, 0.7)
	else
		hammerDown()
		grip()
		act({ { dur = 0.3, pose = POSE.pumpUp, style = SINE } })
		task.wait(0.3)
	end

	-- ── 1. HEAT ──────────────────────────────────────────────────────────
	phaseLabel.Text = `FORGING A {slotName}   ·   1 / 2   HEAT`
	hint.Text = "HOLD to work the bellows  ·  keep the heat inside the band"
	-- the gauge: a forged-iron thermometer with a gold rim and tick marks
	local gauge = make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -60, 0.5, 0), Size = UDim2.fromOffset(26, 300),
		BackgroundColor3 = Color3.fromRGB(20, 14, 12), BackgroundTransparency = 0.2, ZIndex = 10 }, g)
	corner(gauge, 6)
	local gaugeStroke = make("UIStroke", { Color = GOLD, Transparency = 0.4, Thickness = 1.4 }, gauge)
	for i = 1, 9 do
		make("Frame", { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(0, -4, i / 10, 0), Size = UDim2.fromOffset(if i % 5 == 0 then 10 else 6, 2),
			BackgroundColor3 = GOLD, BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 10 }, gauge)
	end
	local fill = make("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0),
		BackgroundColor3 = heatColor(0.5), BorderSizePixel = 0, ZIndex = 10 }, gauge)
	corner(fill, 6)
	make("UIGradient", { Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)), Rotation = 0 }, fill)
	local band = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.new(1, 14, 0.2, 0), Position = UDim2.fromScale(0.5, 0.5),
		BackgroundTransparency = 1, BackgroundColor3 = GREEN, ZIndex = 11 }, gauge)
	local bandStroke = make("UIStroke", { Color = GOLD, Thickness = 2.5 }, band)
	corner(band, 4)
	local pulseFrame = make("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = WHITE_GOLD, BackgroundTransparency = 1, ZIndex = 12 }, gauge)
	corner(pulseFrame, 6)
	text(gauge, "HEAT", 12, GOLD, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 8), Size = UDim2.fromOffset(60, 16), ZIndex = 10 })
	local inLabel = text(gauge, "", 13, PARCH, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -8), Size = UDim2.fromOffset(80, 16), ZIndex = 10 })
	local gaugeScale = make("UIScale", { Scale = 0.6 }, gauge)
	tween(gaugeScale, 0.3, { Scale = 1 }, Enum.EasingStyle.Back)

	onLever = true
	local heat, inBand, t = 0.1, 0, 0
	local phase0 = math.random() * 6
	local lastSecond = 0
	local flare = 0
	local stroking = false -- (the lever on its way down)
	local nextStroke = 0
	local STROKE = 0.35
	while t < HEAT_TIME and not skipped do
		local dt = RunService.RenderStepped:Wait()
		t += dt
		heat = math.clamp(heat + (if holding then 0.7 else -0.4) * dt, 0, 1)
		local center = 0.6 + 0.22 * math.sin(phase0 + t * 1.3) + 0.06 * math.sin(phase0 * 2 + t * 3.1)
		local dist = math.abs(heat - center)
		local ok = dist <= 0.1
		if ok then inBand += dt end
		local edge = ok and dist > 0.07

		-- the gauge: green and steady inside, flickering at the edge, warning red outside
		band.Position = UDim2.fromScale(0.5, 1 - center)
		bandStroke.Color = if not ok then GOLD elseif edge then GOLD:Lerp(GREEN, 0.5) else GREEN
		bandStroke.Transparency = if edge then math.random() * 0.6 else 0
		band.BackgroundTransparency = if ok and not edge then 0.82 else 1
		gaugeStroke.Color = if ok then GOLD else GOLD:Lerp(RED, 0.5 + 0.5 * math.sin(t * 12))
		gaugeStroke.Transparency = if ok then 0.4 else 0.1
		fill.Size = UDim2.fromScale(1, heat)
		fill.BackgroundColor3 = heatColor(math.max(0.35, heat))
		inLabel.Text = `{math.floor(inBand / HEAT_TIME * 100 + 0.5)}%`

		-- every second held in the band: a pulse, a flare, a ring of the metal
		local sec = math.floor(inBand)
		if sec > lastSecond then
			lastSecond = sec
			pulseFrame.BackgroundTransparency = 0.3
			tween(pulseFrame, 0.35, { BackgroundTransparency = 1 })
			local s = make("UIScale", { Scale = 1.12 }, inLabel)
			tween(s, 0.3, { Scale = 1 })
			task.delay(0.32, function() s:Destroy() end)
			emit(scene.ingotSparks, 10)
			flare = 1
			sfx(SFX.chime, 0.12, 1.3 + sec * 0.08)
		end

		-- the smith hauls the lever while you hold: down (a gust into the fire), up, down...
		local now = os.clock()
		if holding and now >= nextStroke then
			stroking = not stroking
			nextStroke = now + STROKE
			act({ { dur = STROKE, pose = if stroking then POSE.pumpDown else POSE.pumpUp, style = SINE } }, 0.6)
			if stroking then
				task.delay(STROKE * 0.6, function()
					if not scene.folder.Parent then return end
					sfx(SFX.bellows, 0.3, 1.1)
					emit(scene.puff, 8)
					emit(scene.embers, 6)
					flare = math.max(flare, 0.6)
				end)
			end
		elseif not holding and stroking then
			stroking = false
			nextStroke = 0
			act({ { dur = 0.45, pose = POSE.pumpUp, style = SINE, wobble = breathe } }, 0.6)
		end

		-- the hearth answers: brighter, taller fire, more embers; it settles when you let go
		flare = math.max(0, flare - dt * 3)
		scene.hearthLight.Brightness = 2 + 3 * heat + 2 * flare
		scene.fire.Size = 4 + heat * 5 + (if holding then 1.5 else 0)
		scene.fire.Heat = 6 + heat * 8
		scene.embers.Rate = 5 + heat * 25
		scene.coals.Color = heatColor(math.clamp(0.45 + heat * 0.5, 0, 1))
		fireLoop.Volume = 0.2 + heat * 0.35

		-- the metal: glowing steady in the band, shimmering harder at its edge,
		-- darker and spitting stray sparks outside it
		setIngot(heat, if ok then 0 else 0.3)
		scene.shimmer.Rate = heat * 14 * (if edge then 1.8 else 1)
		if not ok and heat > 0.3 and math.random() < dt * 5 then emit(scene.ingotSparks, 2) end
	end
	local heatScore = math.clamp(inBand / HEAT_TIME, 0, 1)
	gauge:Destroy()
	onLever = false
	pop(`HEAT  {math.floor(heatScore * 100 + 0.5)}%`, if heatScore >= 0.7 then GREEN else GOLD)

	-- the forge erupts: the work at its ideal heat
	heat = math.max(heat, 0.8)
	setIngot(heat)
	scene.fire.Size = 14
	tween(scene.fire, 0.8, { Size = 6 })
	scene.hearthLight.Brightness = 9
	tween(scene.hearthLight, 0.9, { Brightness = 3.5 })
	emit(scene.embers, 50)
	emit(scene.ingotSparks, 25)
	sfx(SFX.boom, 0.35, 1.4)
	sfx(SFX.bellows, 0.45, 0.8)
	shake(0.35)
	scene.shimmer.Rate = 10
	setShot(shots.hammer, 2.2)

	-- out of the fire, round to the anvil, laid on the face; the hammer taken up
	act({ { dur = 0.3, pose = POSE.lower, style = SINE }, { dur = 0.5, pose = POSE.grab, style = SINE } })
	task.wait(0.8)
	layDown(0.12)
	hitSound(0.16, 1.6)
	act({ { dur = 0.4, pose = POSE.setHammer, style = SINE } })
	task.wait(0.4)
	hammerUp()
	hitSound(0.06, 2)
	act({ { dur = 0.45, pose = POSE.coil, style = CUBIC, wobble = breathe } })
	task.wait(0.3)

	-- ── 2. HAMMER ────────────────────────────────────────────────────────
	phaseLabel.Text = `FORGING A {slotName}   ·   2 / 2   HAMMER`
	hint.Text = "PRESS to strike  ·  hit while the marker crosses the glowing mark"
	local bar = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -86), Size = UDim2.fromOffset(520, 22),
		BackgroundColor3 = Color3.fromRGB(20, 14, 12), BackgroundTransparency = 0.15, ZIndex = 10 }, g)
	corner(bar, 6)
	make("UIStroke", { Color = GOLD, Transparency = 0.4, Thickness = 1.4 }, bar)
	local okZone = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0.24, 0, 1, 0), BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.8, BorderSizePixel = 0, ZIndex = 10 }, bar)
	local goodZone = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0.12, 0, 1, 0), BackgroundColor3 = GOLD,
		BackgroundTransparency = 0.5, BorderSizePixel = 0, ZIndex = 10 }, bar)
	local perfectZone = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Size = UDim2.new(0.04, 0, 1, 0),
		BackgroundColor3 = WHITE_GOLD, BorderSizePixel = 0, ZIndex = 10 }, bar)
	local marker = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(5, 36), Position = UDim2.fromScale(0, 0.5),
		BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 11 }, bar)
	local pips = make("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, 10), Size = UDim2.fromOffset(200, 14),
		BackgroundTransparency = 1, ZIndex = 10 }, bar)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 10) }, pips)
	local pipFrames = {}
	for i = 1, STRIKES do
		local pf = make("Frame", { Size = UDim2.fromOffset(12, 12), BackgroundColor3 = Color3.fromRGB(60, 50, 46), LayoutOrder = i, ZIndex = 10 }, pips)
		corner(pf, 6)
		pipFrames[i] = pf
	end
	local barScale = make("UIScale", { Scale = 0.7 }, bar)
	tween(barScale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)

	-- the work's shape: from the bar toward the slot's shape, a step per good blow
	local shapeTarget: Vector3 = (SHAPE :: any)[slot] or SHAPE.weapon
	local shaped = 0 -- 0..1
	local function reshape()
		local size = INGOT:Lerp(shapeTarget, shaped)
		if shaped >= 1 and (slot == "ring" or slot == "charm") then
			scene.ingot.Shape = Enum.PartType.Cylinder
			scene.ingot.Size = Vector3.new(size.Y, size.X, size.Z)
			shapeRot = CFrame.Angles(0, 0, math.rad(90))
		else
			scene.ingot.Size = size
		end
		if not held then scene.ingot.CFrame = anvilCF() end
	end

	-- the blow, by grade (q) and by strike (each heavier than the last)
	local function blow(q: number, strike: number)
		local intensity = 0.6 + 0.2 * (strike - 1) -- 0.6 → 1.4
		local final = strike == STRIKES
		local ring = scene.ring :: Part
		local function shockwave(color: Color3, size: number)
			ring.Color = color
			ring.Size = Vector3.new(0.04, 0.3, 0.3)
			ring.Transparency = 0.55
			tween(ring, 0.2, { Size = Vector3.new(0.04, size, size), Transparency = 1 })
		end
		if q >= 1 then
			scene.sparks.Color = ColorSequence.new(WHITE_GOLD, Color3.fromRGB(255, 170, 60))
			emit(scene.sparks, 60 * intensity)
			emit(scene.streaks, 26 * intensity)
			scene.flash.Color = WHITE_GOLD
			scene.flash.Brightness = 9 * intensity
			shockwave(WHITE_GOLD, 1.6 + intensity * 0.8)
			hitSound(0.9, 1)
			hitSound(0.4, 0.72) -- (the weight under it)
			sfx(SFX.boom, 0.12 * intensity, 1.7)
			shake(0.75 * intensity)
			fovKick = -2.5 * intensity
			glow = 1
			screenFlash(WHITE_GOLD, 0.12 + 0.06 * intensity, 0.18)
		elseif q >= 0.75 then
			scene.sparks.Color = ColorSequence.new(Color3.fromRGB(255, 210, 120), Color3.fromRGB(255, 110, 30))
			emit(scene.sparks, 38 * intensity)
			emit(scene.streaks, 14 * intensity)
			scene.flash.Color = Color3.fromRGB(255, 190, 110)
			scene.flash.Brightness = 5 * intensity
			shockwave(Color3.fromRGB(255, 180, 90), 1.2 + intensity * 0.6)
			hitSound(0.75, 1.02)
			hitSound(0.22, 0.75)
			shake(0.5 * intensity)
			fovKick = -1.2 * intensity
		elseif q > 0.2 then
			scene.sparks.Color = ColorSequence.new(Color3.fromRGB(255, 190, 100), Color3.fromRGB(230, 90, 30))
			emit(scene.sparks, 18 * intensity)
			emit(scene.streaks, 5 * intensity)
			scene.flash.Color = Color3.fromRGB(255, 170, 90)
			scene.flash.Brightness = 3 * intensity
			hitSound(0.45, 1.12)
			shake(0.3 * intensity)
		else
			scene.sparks.Color = ColorSequence.new(Color3.fromRGB(200, 90, 40), Color3.fromRGB(120, 40, 20))
			emit(scene.sparks, 5)
			scene.flash.Color = Color3.fromRGB(200, 80, 50)
			scene.flash.Brightness = 1.5
			hitSound(0.3, 0.62) -- (dull, glancing)
			shake(0.18)
		end
		tween(scene.flash, if q >= 1 then 0.45 else 0.3, { Brightness = 0 })
		-- the work takes the blow: a full step toward its shape for a good one, less for a weak one
		shaped = math.min(1, shaped + (if q >= 0.45 then 0.2 elseif q > 0.2 then 0.12 else 0.06))
		if final then shaped = 1 end
		reshape()
		if final then
			emit(scene.burst, 50)
			emit(scene.streaks, 30)
			shockwave(WHITE_GOLD, 3.2)
			sfx(SFX.boom, 0.4, 1.2)
			shake(1.2)
			fovKick = -6
			screenFlash(WHITE_GOLD, 0.25, 0.35)
		end
	end

	local hits = {}
	local pos, dir = 0, 1
	for strike = 1, STRIKES do
		if skipped then
			for i = #hits + 1, STRIKES do
				hits[i] = 1
				pipFrames[i].BackgroundColor3 = WHITE_GOLD
			end
			break
		end
		local mark = 0.2 + math.random() * 0.6
		for _, z in ipairs({ okZone, goodZone, perfectZone }) do z.Position = UDim2.fromScale(mark, 0) end
		local speed = 0.85 + 0.3 * (strike - 1) -- bar widths a second
		pressed = false
		acceptAfter = os.clock() + 0.15
		local waited = 0
		if strike == STRIKES then setShot(shots.finale, 2.5) end
		while not pressed and not skipped do
			local dt = RunService.RenderStepped:Wait()
			waited += dt
			pos += dir * speed * dt
			if pos > 1 then pos, dir = 2 - pos, -1 elseif pos < 0 then pos, dir = -pos, 1 end
			marker.Position = UDim2.fromScale(pos, 0.5)
			-- (the coil tightens as the marker nears the mark; the work cools)
			nearK = math.clamp(1 - math.abs(pos - mark) / 0.3, 0, 1)
			heat = math.max(0.35, heat - dt * 0.05)
			glow = math.max(0, glow - dt * 1.5)
			setIngot(heat, 0, glow)
			if waited > 6 then break end -- (no strike: a miss)
		end
		nearK = 0
		-- judged at the press; the blow lands right after
		local off = math.abs(pos - mark)
		local q, name, color
		if skipped then
			q, name, color = 1, "PERFECT!", WHITE_GOLD
		elseif not pressed then
			q, name, color = 0, "MISS", RED
		elseif off <= 0.02 then
			q, name, color = 1, "PERFECT!", WHITE_GOLD
		elseif off <= 0.06 then
			q, name, color = 0.75, "GOOD", GREEN
		elseif off <= 0.12 then
			q, name, color = 0.45, "OK", GOLD
		else
			q, name, color = 0.1, "MISS", RED
		end
		table.insert(hits, q)
		-- the downswing: the whole body thrown over the work (a MISS lands short and glancing)
		act({ { dur = DOWNSWING, pose = if q > 0.2 then POSE.impact else POSE.glance, style = QUART } }, 1.2)
		task.wait(DOWNSWING)
		blow(q, strike)
		if q >= 1 then CastPoses.hitStop(smith, 0.1) end
		pipFrames[strike].BackgroundColor3 = color
		local ps = make("UIScale", { Scale = 1.8 }, pipFrames[strike])
		tween(ps, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
		pop(name, color, q >= 1)
		-- the impact holds (a beat longer for a perfect, longest for the last), the
		-- hammer rebounds off the metal, and the smith coils again
		task.wait(if strike == STRIKES then 0.4 elseif q >= 1 then 0.14 else 0.06)
		if strike < STRIKES then
			act({ { dur = 0.12, pose = POSE.rebound, style = SINE }, { dur = RECOVER, pose = POSE.coil, style = CUBIC, wobble = breathe } })
			task.wait(0.12 + RECOVER)
		end
	end
	if skipped and shaped < 1 then -- (a skip: the piece shaped as if every blow had landed)
		shaped = 1
		reshape()
	end
	local hammerScore = 0
	for _, q in ipairs(hits) do hammerScore += q end
	hammerScore /= STRIKES
	tween(barScale, 0.2, { Scale = 0.6 })
	task.delay(0.2, function() bar:Destroy() end)

	-- ── 3. QUENCH ────────────────────────────────────────────────────────
	ContextActionService:UnbindAction("ForgeMinigame")
	if skipBtn then skipBtn:Destroy() end
	if skipped then heatScore, hammerScore = 1, 1 end
	local score = math.clamp(0.35 * heatScore + 0.65 * hammerScore, 0, 1)
	phaseLabel.Text = `FORGING A {slotName}   ·   QUENCHING`
	hint.Text = ""
	local q = text(g, `QUALITY  {math.floor(score * 100 + 0.5)}%   ·   {grade(score)}`, 26, GOLD, { Position = UDim2.fromOffset(0, 92), ZIndex = 10 })
	q.TextTransparency = 1
	tween(q, 0.4, { TextTransparency = 0 })

	-- (skipped: the server forged it already)
	if not skipped and not result then
		Network.GetRemoteEvent(Network.Remotes.ArmoryAction):FireServer({ kind = "craft", slot = slot, score = score })
	end

	-- the hammer down, the work up in the tongs and looked over...
	act({ { dur = 0.3, pose = POSE.lower, style = SINE }, { dur = 0.35, pose = POSE.grab, style = SINE } })
	task.wait(0.6)
	grip()
	act({ { dur = 0.5, pose = POSE.inspect, style = SINE, wobble = breathe } })
	local i0 = os.clock()
	while os.clock() - i0 < 0.85 do
		local k = (os.clock() - i0) / 0.85
		inspectSpin = math.sin(k * math.pi) * math.rad(70) -- (turned in the jaws, one face then the other)
		RunService.Heartbeat:Wait()
	end
	inspectSpin = 0
	-- ...then round to the slack tub, held over it, and plunged
	setShot(shots.quench, 2.6)
	act({ { dur = 0.6, pose = POSE.quenchAbove, style = SINE } })
	task.wait(0.72)
	act({ { dur = 0.16, pose = POSE.quenchLow, style = Enum.EasingStyle.Quad } }, 0.8)
	task.wait(0.16)
	sfx(SFX.splash, 0.6)
	local hiss = sfx(SFX.steam, 0.75, 0.85)
	sfx(SFX.boom, 0.18, 0.9)
	emit(scene.droplets, 22)
	emit(scene.steamJet, 26)
	emit(scene.steamBig, 16)
	emit(scene.steamGlow, 30)
	scene.steamFog.Enabled = true
	scene.steamLight.Enabled = true
	scene.steamLight.Brightness = 7
	tween(scene.steamLight, 1.4, { Brightness = 1.5 })
	shake(0.45)
	-- the steam fills the screen
	tween(steamScreen, 0.35, { BackgroundTransparency = 0.12 })
	task.delay(0.5, function() if scene.ingot.Parent then emit(scene.steamBig, 8) end end)
	setIngot(0.15)
	scene.shimmer.Rate = 0
	task.wait(0.9)
	local tw = os.clock()
	while not result and os.clock() - tw < 5 do task.wait(0.05) end
	resultConn:Disconnect()
	storeConn:Disconnect()
	player:SetAttribute("ForgeSkipping", nil)

	-- out of the water and raised to the light, while the steam still hides it
	local bigReveal = result and ((REVEAL :: any)[tostring(result.rarity)] or REVEAL.Common).tier >= 5
	cutTo(if bigReveal then shots.revealWide else shots.reveal)
	act({ { dur = 0.6, pose = POSE.present, style = SINE, wobble = breathe } })
	scene.steamFog.Enabled = false
	tween(hiss, 1.5, { Volume = 0 })
	task.wait(0.6)
	scene.strikeAtt.WorldPosition = scene.ingot.Position

	-- ── 4. REVEAL ────────────────────────────────────────────────────────
	if result then
		local rarity = tostring(result.rarity)
		local fx = (REVEAL :: any)[rarity] or REVEAL.Common
		local col: Color3 = GearData.RARITY_COLOR[rarity] or PARCH
		local hot = if fx.tier >= 6 then Color3.fromRGB(255, 245, 235) else col:Lerp(Color3.new(1, 1, 1), 0.45)

		-- a Mythic holds its breath: the light drains, the steam hangs, two heartbeats
		if fx.tier >= 6 then
			tween(scene.hearthLight, 0.5, { Brightness = 0.4 })
			tween(cc, 0.5, { Brightness = -0.25, Saturation = -0.3 })
			tween(fireLoop, 0.5, { Volume = 0.05 })
			for i = 1, 2 do
				sfx(SFX.boom, 0.45, 0.6)
				scene.ingot.Material = Enum.Material.Neon
				scene.ingot.Color = col
				scene.flash.Color = col
				scene.flash.Brightness = 4
				tween(scene.flash, 0.35, { Brightness = 0 })
				shake(0.3)
				task.wait(0.4)
				scene.ingot.Color = Color3.fromRGB(40, 20, 22)
				task.wait(i == 1 and 0.15 or 0.05)
			end
		end

		-- the steam clears on the piece in its rarity's colour
		phaseLabel.Text = `{slotName} FORGED   ·   {string.upper(rarity)}`
		phaseLabel.TextColor3 = col
		tween(steamScreen, if fx.tier >= 5 then 0.35 else 0.7, { BackgroundTransparency = 1 })
		scene.ingot.Material = Enum.Material.Neon
		scene.ingot.Color = col
		scene.burst.Color = ColorSequence.new(hot, col)
		emit(scene.burst, fx.burst)
		emit(scene.streaks, fx.burst * 0.3)
		scene.flash.Color = col
		scene.flash.Brightness = fx.light * 0.55
		scene.flash.Range = 10 + fx.tier
		tween(scene.flash, 1.2, { Brightness = 0.8 + fx.tier * 0.15 })
		shake(fx.shake)
		if fx.tier >= 2 then
			scene.steamBig.Color = ColorSequence.new(col:Lerp(Color3.new(1, 1, 1), 0.6))
			emit(scene.steamBig, 4 + fx.tier * 2)
		end
		if fx.tier >= 3 then
			local ring = scene.ring :: Part
			ring.Color = col
			ring.CFrame = CFrame.new(scene.ingot.Position) * CFrame.Angles(0, 0, math.rad(90))
			ring.Size = Vector3.new(0.04, 0.4, 0.4)
			ring.Transparency = 0.5
			tween(ring, 0.35, { Size = Vector3.new(0.04, 1.5 + fx.tier * 0.5, 1.5 + fx.tier * 0.5), Transparency = 1 })
			scene.motes.Color = ColorSequence.new(hot, col)
			scene.motes.Rate = 4 + fx.tier * 3
			scene.motes.Enabled = true
		end
		if fx.tier >= 5 then
			-- a shaft of light, a push-in, the room lit in the rarity
			local pillar = scene.pillar :: Part
			pillar.CFrame = CFrame.new(scene.ingot.Position + Vector3.new(0, 7, 0))
			pillar.Color = hot
			pillar.Size = Vector3.new(0.15, 14, 0.15)
			pillar.Transparency = 0.35
			tween(pillar, 0.8, { Size = Vector3.new(0.9, 14, 0.9), Transparency = 1 })
			setShot(shots.reveal, 5)
			fovKick = -5
			screenFlash(hot, 0.35, 0.5)
			scene.hearthLight.Color = col:Lerp(Color3.fromRGB(255, 130, 60), 0.5)
			tween(scene.hearthLight, 0.6, { Brightness = 3 })
		end
		if fx.tier >= 6 then
			-- the second layer: white-hot, then crimson again
			task.delay(0.18, function()
				if not scene.ingot.Parent then return end
				scene.burst.Color = ColorSequence.new(Color3.new(1, 1, 1), col)
				emit(scene.burst, 90)
				emit(scene.sparks, 60)
				shake(0.8)
				screenFlash(col, 0.25, 0.6)
			end)
			tween(cc, 1.2, { Brightness = 0, Saturation = -0.12 })
			tween(fireLoop, 1.5, { Volume = 0.25 })
		end
		-- the colour grade leans into the rarity, then eases back
		if fx.tint > 0 then
			cc.TintColor = Color3.fromRGB(255, 246, 238):Lerp(col:Lerp(Color3.new(1, 1, 1), 0.5), fx.tint * 2)
			tween(cc, 1.6, { TintColor = Color3.fromRGB(255, 246, 238) })
		end
		-- its sound, by rarity
		if fx.tier <= 2 then
			sfx(SFX.chime, 0.3, 0.95 + fx.tier * 0.1)
		elseif fx.tier <= 4 then
			sfx(SFX.sparkle, 0.35, 0.9 + fx.tier * 0.05)
			sfx(SFX.chime, 0.25, 0.9)
			if fx.tier == 4 then sfx(SFX.boom, 0.2, 1.3) end
		elseif fx.tier == 5 then
			sfx(SFX.boom, 0.45, 1.05)
			sfx(SFX.sparkle, 0.5, 1)
			sfx(SFX.chime, 0.35, 0.8)
		else
			sfx(SFX.boom, 0.6, 0.85)
			task.delay(0.18, function() if scene.folder.Parent then sfx(SFX.boom, 0.35, 1.3) end end)
			sfx(SFX.sparkle, 0.6, 0.8)
			sfx(SFX.chime, 0.4, 0.7)
		end
		task.wait(if fx.tier >= 5 then 0.55 else 0.35)

		-- the card builds up: the glyph's silhouette, the glow, the name, the header, the stats
		local card = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -84), Size = UDim2.fromOffset(500, 128),
			BackgroundColor3 = col:Lerp(Color3.fromRGB(16, 12, 14), 0.78), BackgroundTransparency = 1, ZIndex = 20 }, g)
		corner(card, 8)
		local stroke = make("UIStroke", { Color = col, Thickness = 0, Transparency = 0 }, card)
		local halo = make("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 18, 1, 18),
			BackgroundColor3 = col, BackgroundTransparency = 1, ZIndex = 19 }, card)
		corner(halo, 14)
		local sc = make("UIScale", { Scale = 0.85 }, card)
		tween(sc, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
		tween(card, 0.3, { BackgroundTransparency = 0.05 })
		-- the glyph: a black silhouette that fills with its colour
		local icon = make("Frame", { Position = UDim2.fromOffset(14, 14), Size = UDim2.fromOffset(100, 100),
			BackgroundColor3 = Color3.fromRGB(12, 10, 12), BackgroundTransparency = 0.1, ZIndex = 21 }, card)
		corner(icon, 8)
		local iconStroke = make("UIStroke", { Color = col, Thickness = 1.5, Transparency = 1 }, icon)
		local glyph = text(icon, tostring(result.glyph or "?"), 40, Color3.new(0, 0, 0), { Size = UDim2.new(1, 0, 1, -18), TextStrokeTransparency = 1,
			TextScaled = false, ZIndex = 22 })
		local tag = text(icon, `+0  ·  iLvl {result.ilvl}`, 12, PARCH, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -4),
			Size = UDim2.new(1, 0, 0, 16), TextTransparency = 1, ZIndex = 22 })
		task.wait(0.15)
		tween(glyph, 0.4, { TextColor3 = col })
		tween(iconStroke, 0.4, { Transparency = 0 })
		tween(stroke, 0.4, { Thickness = 2 })
		tween(halo, 0.4, { BackgroundTransparency = 0.8 })
		task.wait(0.2)
		-- the header and the name
		local header = text(card, `{string.upper(rarity)}  ·  {string.upper(tostring(result.slotName))}  ·  iLvl {result.ilvl}  ·  {result.itemPower} POWER`,
			12, col, { Position = UDim2.fromOffset(128, 14), Size = UDim2.new(1, -140, 0, 16), TextXAlignment = Enum.TextXAlignment.Left,
				TextTransparency = 1, ZIndex = 21 })
		tween(header, 0.25, { TextTransparency = 0 })
		local nameText = tostring(result.name)
		local nameLabel = text(card, nameText, 24, Color3.new(1, 1, 1), { Position = UDim2.fromOffset(128, 32), Size = UDim2.new(1, -140, 0, 30),
			TextXAlignment = Enum.TextXAlignment.Left, MaxVisibleGraphemes = 0, ZIndex = 21 })
		local n = utf8.len(nameText) or #nameText
		local t0 = os.clock()
		while scene.folder.Parent and os.clock() - t0 < 0.4 do
			nameLabel.MaxVisibleGraphemes = math.floor(n * (os.clock() - t0) / 0.4)
			RunService.RenderStepped:Wait()
		end
		nameLabel.MaxVisibleGraphemes = -1
		sfx(SFX.chime, 0.15, 1.5)
		-- the stats, one after another
		local stats = make("Frame", { Position = UDim2.fromOffset(128, 66), Size = UDim2.new(1, -140, 0, 52), BackgroundTransparency = 1, ZIndex = 21 }, card)
		make("UIGridLayout", { CellSize = UDim2.new(0.5, -4, 0, 16), CellPadding = UDim2.fromOffset(8, 2), SortOrder = Enum.SortOrder.LayoutOrder }, stats)
		for i, line in ipairs(result.stats or {}) do
			local l = text(stats, tostring(line), 12, PARCH, { TextXAlignment = Enum.TextXAlignment.Left, LayoutOrder = i, TextTransparency = 1,
				TextStrokeTransparency = 1, ZIndex = 21 })
			tween(l, 0.2, { TextTransparency = 0, TextStrokeTransparency = 0.35 })
			task.wait(0.07)
		end
		tween(tag, 0.25, { TextTransparency = 0 })
		-- the glow keeps breathing
		task.spawn(function()
			while halo.Parent do
				tween(halo, 1.1, { BackgroundTransparency = 0.88 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(1.1)
				if not halo.Parent then break end
				tween(halo, 1.1, { BackgroundTransparency = 0.78 }, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
				task.wait(1.1)
			end
		end)
		if result.worn then pop(`WORN!  ▲ +{result.gain}`, GREEN) end
	else
		tween(steamScreen, 0.7, { BackgroundTransparency = 1 })
		text(g, "The forge went cold. Try again.", 18, MUTED, { AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 0, 1, -110), ZIndex = 10 })
	end

	-- done (or again, while the scrap lasts)
	local row = make("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -30), Size = UDim2.fromOffset(420, 40),
		BackgroundTransparency = 1, ZIndex = 20 }, g)
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		Padding = UDim.new(0, 14) }, row)
	local function close(again: boolean)
		RunService:UnbindFromRenderStep("ForgeCamera")
		ContextActionService:UnbindAction("ForgeMinigame")
		propsConn:Disconnect()
		cam.CameraType = oldType
		cam.CameraSubject = oldSubject
		cam.FieldOfView = oldFov
		cc:Destroy()
		bloom:Destroy()
		Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ExposureCompensation = oldAmbient, oldOutdoor, oldExposure
		scene.folder:Destroy()
		g:Destroy()
		player:SetAttribute("Forging", nil)
		for _, sg in ipairs(hidden) do
			if sg.Parent then sg.Enabled = true end
		end
		if not again and armoryToRestore then
			armoryToRestore.Enabled = true
			armoryToRestore = nil
		end
		playing = false
		if again then task.defer(ForgeMinigame.Play, slot) end
	end
	local function button(label: string, color: Color3, order: number, fn: () -> ())
		local b = make("TextButton", { Size = UDim2.fromOffset(190, 40), BackgroundColor3 = color, FontFace = BOLD, TextSize = 15,
			TextColor3 = GOLD, Text = label, LayoutOrder = order, ZIndex = 20 }, row)
		corner(b, 6)
		make("UIStroke", { Color = GOLD, Transparency = 0.5 }, b)
		b.MouseButton1Click:Connect(fn)
	end
	button("DONE", Color3.fromRGB(60, 40, 30), 2, function() close(false) end)
	task.wait(0.3) -- (the scrap count arrives with the sync)
	local scrap = 0
	pcall(function()
		local armory = require(script.Parent:WaitForChild("Armory")) :: any
		scrap = armory.Scrap()
	end)
	if scrap >= PowerGear.CRAFT_COST then
		button(`FORGE AGAIN  ·  {PowerGear.CRAFT_COST}`, Color3.fromRGB(110, 70, 26), 1, function() close(true) end)
	end
end

return ForgeMinigame
