--!strict
--[[
	IslandMobs.luau
	The Forgotten Isle's own enemies: four to a biome, each one of MobKinds'
	four base templates dressed in its own silhouette and given one of
	MobKinds' signature moves. Requiring this registers them all into
	MobKinds.Kinds (IslandMode requires it); IslandConfig.Enemies names which
	biome raises which.

	  The Shipwreck Coast   Pirate Raider (pounce), Pirate Gunner (snipe),
	                        Reef Shark (pounce), Crustacean Brute (charge)
	  The Verdant Ruins     Jungle Warrior (pounce), Jungle Archer (arrows),
	                        Vine Crawler (bit hop), Stone Guardian (quake)
	  The Corrupted Forest  Corrupted Stalker (blink), Void Archer (snipe),
	                        Corrupted Brute (charge), Shadow Wisp (fuse)
	  The Frozen Isle       Frost Wolf (pounce), Ice Archer (arrows),
	                        Frost Wraith (blink), Yeti Brute (quake)
	  The Sunken Sanctuary  Aqua Sentinel (charge), Tide Archer (arrows),
	                        Guardian Leviathan (quake), Water Sprite (bit hop)
	  The Infernal Citadel  Lava Imp (pounce), Fire Archer (mortar),
	                        Magma Brute (quake), Flame Elemental (blink)
	  The Ancient Spire     Spire Knight (execute), Arcane Mage (bolt, hex),
	                        Void Golem (quake), Rift Drone (laser)

	No lights on any of them (Neon glows on its own).
--]]

local MobKinds = require(script.Parent:WaitForChild("MobKinds"))

local IslandMobs = {}

local M = Enum.Material
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end

-- ── Dressing ────────────────────────────────────────────────────────────────
-- A piece welded onto `body` at `offset` (body space).
local function piece(body: BasePart?, offset: CFrame, size: Vector3, color: Color3, mat: Enum.Material?, props: { [string]: any }?): BasePart?
	if not body then return nil end
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, false, true
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Size, p.Color, p.Material = size, color, mat or M.SmoothPlastic
	p.CastShadow = false
	p.Name = "Dress"
	if props then for k, v in pairs(props) do (p :: any)[k] = v end end
	p.CFrame = body.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0, w.Part1, w.C0 = body, p, offset
	w.Parent = p
	p.Parent = body.Parent
	return p
end
local function glow(body: BasePart?, offset: CFrame, size: Vector3, color: Color3, props: { [string]: any }?): BasePart?
	return piece(body, offset, size, color, M.Neon, props)
end
local function bp(model: Model, name: string): BasePart?
	local p = model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end
local function color(model: Model, names: { string }, c: Color3, mat: Enum.Material?)
	for _, n in ipairs(names) do
		local p = bp(model, n)
		if p then
			p.Color = c
			if mat then p.Material = mat end
		end
	end
end
local ARMS = { "Left Arm", "Right Arm" }
local LEGS = { "Left Leg", "Right Leg" }
local BODY = { "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }
-- drop what dresses a rig on its own (clothes, body colours, the face, a bow)
local function strip(model: Model, keepBow: boolean?)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") or d:IsA("Accessory") then
			d:Destroy()
		elseif d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
			d:Destroy()
		end
	end
	if not keepBow then
		local bow = model:FindFirstChild("Bow")
		if bow then bow:Destroy() end
	end
end
local function eyes(model: Model, c: Color3, spread: number?, y: number?, size: number?)
	local head = bp(model, "Head")
	local s = size or 0.18
	for _, sx in ipairs({ -1, 1 }) do
		glow(head, CFrame.new(sx * (spread or 0.24), y or 0.1, -0.61), Vector3.new(s * 1.3, s, 0.06), c)
	end
end
-- something held in the right fist: its +Y runs out of the fist
local GRIP = CFrame.new(0, -1.05, 0) * CFrame.Angles(math.rad(-90), 0, 0)
local function held(model: Model, side: string?): (BasePart?, CFrame)
	return bp(model, side or "Right Arm"), GRIP
end
local function bowColor(model: Model, c: Color3)
	local bow = model:FindFirstChild("Bow")
	if bow then
		for _, d in ipairs(bow:GetDescendants()) do
			if d:IsA("BasePart") then d.Color = c end
		end
		if bow:IsA("BasePart") then bow.Color = c end
	end
end
-- a ghost's body: one colour, see-through, no legs (a tail of the same)
local function ghost(model: Model, c: Color3, tail: Color3, transparency: number)
	strip(model)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material, d.Color, d.Transparency = M.SmoothPlastic, c, transparency
		end
	end
	for _, n in ipairs(LEGS) do
		local leg = bp(model, n)
		if leg then leg.Transparency = 1 end
	end
	local torso = bp(model, "Torso")
	for i, t in ipairs({ { -1.6, Vector3.new(1.9, 1.3, 1) }, { -2.55, Vector3.new(1.3, 1.1, 0.75) }, { -3.3, Vector3.new(0.7, 0.8, 0.45) } }) do
		piece(torso, CFrame.new(0, t[1], 0.15 * i), t[2], tail, M.SmoothPlastic, { Transparency = transparency + i * 0.12 })
	end
end
local function slime(model: Model): (BasePart?, BasePart?)
	local inner, outer = nil, nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Sphere.001" then inner = d elseif d.Name == "Sphere" then outer = d end
		end
	end
	return inner, outer
end
local function particles(parent: BasePart?, props: { [string]: any })
	if not parent then return end
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
end
local FIRE = "rbxasset://textures/particles/fire_main.dds"
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local function seq(a: number, b: number): NumberSequence return NumberSequence.new(a, b) end

local kinds = MobKinds.Kinds :: any

-- ── The Shipwreck Coast ─────────────────────────────────────────────────────
local SKIN, SEA_BLUE, RED, WOOD = rgb(214, 170, 130), rgb(60, 90, 140), rgb(180, 40, 40), rgb(110, 76, 46)

-- a deckhand gone to piracy: red bandana, striped shirt, eyepatch, cutlass
local function dressRaider(model: Model)
	strip(model)
	color(model, { "Head" }, SKIN)
	color(model, ARMS, SKIN)
	color(model, { "Torso" }, rgb(235, 232, 220), M.Fabric)
	color(model, LEGS, rgb(50, 46, 56), M.Fabric)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	for k = -1, 1 do piece(torso, CFrame.new(0, k * 0.6, 0), Vector3.new(2.04, 0.24, 1.04), SEA_BLUE, M.Fabric) end
	piece(torso, CFrame.new(0, -0.85, 0), Vector3.new(2.06, 0.3, 1.06), rgb(60, 40, 26), M.Leather)
	piece(head, CFrame.new(0, 0.42, 0), Vector3.new(1.3, 0.4, 1.3), RED, M.Fabric)
	piece(head, CFrame.new(0.5, 0.35, 0.75) * CFrame.Angles(math.rad(30), 0, 0), Vector3.new(0.3, 0.2, 0.7), RED, M.Fabric) -- (its knot)
	piece(head, CFrame.new(0.24, 0.12, -0.61), Vector3.new(0.4, 0.34, 0.06), rgb(20, 18, 20)) -- (the eyepatch)
	glow(head, CFrame.new(-0.24, 0.12, -0.61), Vector3.new(0.22, 0.16, 0.06), rgb(255, 230, 140))
	piece(head, CFrame.new(0, -0.38, -0.62), Vector3.new(0.9, 0.3, 0.06), rgb(80, 50, 30)) -- (a beard)
	local arm, g = held(model)
	piece(arm, g * CFrame.new(0, 0.3, 0), Vector3.new(0.3, 0.6, 0.3), rgb(60, 40, 26), M.Leather)
	piece(arm, g * CFrame.new(0, 0.66, 0), Vector3.new(0.9, 0.16, 0.3), rgb(200, 170, 70), M.Metal)
	piece(arm, g * CFrame.new(0.1, 2.0, 0) * CFrame.Angles(0, 0, math.rad(-6)), Vector3.new(0.4, 2.6, 0.12), rgb(200, 205, 215), M.Metal)
end
-- a gunner in a long faded coat and tricorn, a long musket
local function dressGunner(model: Model)
	strip(model)
	color(model, { "Head" }, rgb(226, 218, 196))
	color(model, { "Torso" }, SEA_BLUE, M.Fabric)
	color(model, ARMS, SEA_BLUE, M.Fabric)
	color(model, LEGS, rgb(70, 60, 50), M.Fabric)
	model:SetAttribute("NoArrows", true)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -1.3, 0.1), Vector3.new(2.1, 1.4, 1.1), SEA_BLUE, M.Fabric) -- (coat tails)
	for k = -1, 1 do piece(torso, CFrame.new(0.45, k * 0.45, -0.52), Vector3.new(0.16, 0.16, 0.06), rgb(210, 180, 80), M.Metal) end
	piece(torso, CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(-35)), Vector3.new(0.3, 2.6, 1.08), rgb(70, 46, 28), M.Leather)
	piece(head, CFrame.new(0, 0.62, 0), Vector3.new(1.9, 0.18, 1.9), rgb(30, 26, 30), M.Fabric)
	piece(head, CFrame.new(0, 0.86, 0), Vector3.new(1.1, 0.5, 1.1), rgb(30, 26, 30), M.Fabric)
	piece(head, CFrame.new(0, 0.7, -0.92), Vector3.new(0.7, 0.14, 0.1), rgb(210, 180, 80), M.Metal)
	eyes(model, rgb(255, 120, 80), 0.24, 0.1, 0.16)
	local arm, g = held(model)
	piece(arm, g * CFrame.new(0, 0.4, 0), Vector3.new(0.4, 1.4, 0.5), WOOD, M.Wood)
	piece(arm, g * CFrame.new(0, 2.4, 0), Vector3.new(0.22, 3.2, 0.22), rgb(70, 70, 76), M.Metal)
	piece(arm, g * CFrame.new(0, 4.0, 0), Vector3.new(0.3, 0.2, 0.3), rgb(40, 40, 44), M.Metal)
end
-- a shark that walks: grey-blue hide, a white belly, a snout of teeth, fins
local function dressShark(model: Model)
	strip(model)
	local HIDE, BELLY = rgb(96, 118, 140), rgb(226, 230, 232)
	color(model, BODY, HIDE)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -0.1, -0.51), Vector3.new(1.4, 1.7, 0.06), BELLY)
	piece(torso, CFrame.new(0, 0.6, 0.9) * CFrame.Angles(math.rad(-25), 0, 0), Vector3.new(0.25, 1.6, 1.2), HIDE) -- (the dorsal fin)
	piece(torso, CFrame.new(0, -1.3, 1.1) * CFrame.Angles(math.rad(40), 0, 0), Vector3.new(0.25, 1.5, 0.9), HIDE) -- (its tail)
	piece(head, CFrame.new(0, -0.05, -0.75), Vector3.new(1.05, 0.8, 0.7), HIDE) -- (the snout)
	piece(head, CFrame.new(0, -0.32, -0.75), Vector3.new(1.0, 0.25, 0.68), BELLY)
	for k = -2, 2 do
		piece(head, CFrame.new(k * 0.2, -0.2, -1.1) * CFrame.Angles(0, 0, math.rad(45)), Vector3.new(0.12, 0.12, 0.06), rgb(250, 250, 250))
	end
	for _, sx in ipairs({ -1, 1 }) do
		glow(head, CFrame.new(sx * 0.55, 0.15, -0.5), Vector3.new(0.12, 0.2, 0.2), rgb(20, 20, 24))
		piece(bp(model, if sx < 0 then "Left Arm" else "Right Arm"), CFrame.new(sx * 0.6, 0, 0.2) * CFrame.Angles(0, 0, math.rad(sx * 25)), Vector3.new(0.2, 1.4, 0.9), HIDE) -- (fins)
	end
end
-- a hulking crab-man: red-orange shell plates, two great pincers, eye stalks
local function dressCrab(model: Model)
	strip(model)
	local SHELL, DARK = rgb(214, 86, 50), rgb(150, 50, 34)
	color(model, BODY, DARK)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0.2, 0.3), Vector3.new(2.6, 2.2, 1.4), SHELL, M.SmoothPlastic)
	for k = 0, 2 do piece(torso, CFrame.new(0, 0.9 - k * 0.7, 1.05), Vector3.new(2.4 - k * 0.3, 0.2, 0.25), rgb(240, 140, 90)) end
	piece(head, CFrame.new(0, 0.2, 0), Vector3.new(1.4, 0.9, 1.3), SHELL)
	for _, sx in ipairs({ -1, 1 }) do
		piece(head, CFrame.new(sx * 0.35, 0.9, -0.3), Vector3.new(0.16, 0.8, 0.16), DARK)
		glow(head, CFrame.new(sx * 0.35, 1.35, -0.3), Vector3.new(0.3, 0.3, 0.3), rgb(20, 20, 24), { Material = M.SmoothPlastic })
		local arm = bp(model, if sx < 0 then "Left Arm" else "Right Arm")
		local g = GRIP
		piece(arm, g * CFrame.new(0, 0.5, 0), Vector3.new(1.4, 1.2, 1.2), SHELL)
		piece(arm, g * CFrame.new(-0.3, 1.5, 0) * CFrame.Angles(0, 0, math.rad(15)), Vector3.new(0.6, 1.6, 0.8), SHELL)
		piece(arm, g * CFrame.new(0.4, 1.3, 0) * CFrame.Angles(0, 0, math.rad(-20)), Vector3.new(0.4, 1.2, 0.6), rgb(240, 140, 90))
	end
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 1 do
			piece(torso, CFrame.new(sx * 1.4, -0.6 - k * 0.5, 0.2) * CFrame.Angles(0, 0, math.rad(sx * 60)), Vector3.new(0.2, 1.1, 0.2), DARK) -- (little legs)
		end
	end
end

-- ── The Verdant Ruins ───────────────────────────────────────────────────────
local BRONZE, LEAF, LEAF2, MOSS_GLOW = rgb(150, 100, 64), rgb(70, 150, 50), rgb(50, 120, 40), rgb(110, 255, 130)

-- a jungle warrior: painted skin, a leaf skirt, a carved wooden mask, a spear
local function dressJungleWarrior(model: Model)
	strip(model)
	color(model, BODY, BRONZE)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -1.15, 0), Vector3.new(2.15, 0.8, 1.15), LEAF, M.Grass) -- (the leaf skirt)
	piece(torso, CFrame.new(0, 0.4, -0.51), Vector3.new(1.6, 0.14, 0.06), rgb(240, 230, 200)) -- (war paint)
	piece(torso, CFrame.new(0, 0.85, 0), Vector3.new(2.1, 0.3, 1.1), rgb(200, 60, 50), M.Fabric) -- (a bead collar)
	piece(head, CFrame.new(0, 0, -0.66), Vector3.new(1.1, 1.3, 0.2), rgb(120, 80, 46), M.Wood) -- (the mask)
	piece(head, CFrame.new(0, 0.2, -0.78), Vector3.new(0.9, 0.12, 0.06), rgb(230, 200, 60))
	piece(head, CFrame.new(0, -0.3, -0.78), Vector3.new(0.5, 0.12, 0.06), rgb(200, 60, 50))
	for _, sx in ipairs({ -1, 1 }) do glow(head, CFrame.new(sx * 0.25, 0.05, -0.78), Vector3.new(0.2, 0.14, 0.05), MOSS_GLOW) end
	for k = -1, 1 do piece(head, CFrame.new(k * 0.4, 1.0, 0.1) * CFrame.Angles(0, 0, math.rad(-k * 20)), Vector3.new(0.2, 1, 0.1), if k == 0 then rgb(230, 60, 50) else LEAF) end -- (feathers)
	local arm, g = held(model)
	piece(arm, g * CFrame.new(0, 1.2, 0), Vector3.new(0.22, 5, 0.22), WOOD, M.Wood)
	piece(arm, g * CFrame.new(0, 3.9, 0), Vector3.new(0.4, 0.8, 0.12), rgb(90, 90, 96), M.Slate)
end
-- a jungle archer: a hooded cloak of leaves, a bone mask, a vine-wrapped bow
local function dressJungleArcher(model: Model)
	strip(model, true)
	color(model, BODY, rgb(160, 130, 90))
	bowColor(model, rgb(90, 64, 40))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -0.2, 0.2), Vector3.new(2.3, 2.4, 1.2), LEAF2, M.Grass)
	piece(head, CFrame.new(0, 0.3, 0.15), Vector3.new(1.45, 1.1, 1.45), LEAF2, M.Grass) -- (the hood)
	piece(head, CFrame.new(0, 0.7, -0.4), Vector3.new(1.2, 0.3, 0.6), LEAF, M.Grass)
	piece(head, CFrame.new(0, -0.1, -0.62), Vector3.new(0.9, 0.7, 0.06), rgb(230, 222, 200))
	eyes(model, MOSS_GLOW, 0.22, 0.0, 0.15)
	piece(torso, CFrame.new(0.6, 0.2, 0.65) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(0.5, 1.8, 0.5), rgb(110, 76, 46), M.Leather) -- (a quiver)
end
-- a vine crawler: a heap of green coiled vines with a flower crown
local function dressVineCrawler(model: Model)
	local inner, outer = slime(model)
	if inner then inner.Color = rgb(60, 140, 40) end
	if outer then outer.Color, outer.Material, outer.Transparency = rgb(40, 100, 30), M.Grass, 0 end
	local body = outer or inner
	if body then
		local s = body.Size
		for k = 0, 5 do
			local a = k / 6 * math.pi * 2
			piece(body, CFrame.new(math.cos(a) * s.X * 0.45, -s.Y * 0.2, math.sin(a) * s.Z * 0.45) * CFrame.Angles(0, -a, math.rad(70)), Vector3.new(0.3, s.X * 0.6, 0.3), LEAF2, M.Grass)
		end
		for k = 0, 4 do
			local a = k / 5 * math.pi * 2
			piece(body, CFrame.new(math.cos(a) * 0.5, s.Y * 0.5, math.sin(a) * 0.5) * CFrame.Angles(0, -a, math.rad(30)), Vector3.new(0.5, 0.15, 0.9), rgb(255, 120, 160))
		end
		glow(body, CFrame.new(0, s.Y * 0.52, 0), Vector3.new(0.4, 0.4, 0.4), rgb(255, 230, 90))
	end
end
-- a stone guardian: a great block of mossy temple stone, glowing green runes
local function dressGuardian(model: Model)
	strip(model)
	local ST = rgb(120, 124, 120)
	color(model, BODY, ST, M.Slate)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0.3, 0), Vector3.new(2.6, 1.6, 1.4), rgb(104, 108, 104), M.Slate)
	piece(torso, CFrame.new(0, 1.15, 0), Vector3.new(2.8, 0.3, 1.5), rgb(80, 140, 60), M.Grass)
	glow(torso, CFrame.new(0, 0.2, -0.72), Vector3.new(0.6, 0.6, 0.05), MOSS_GLOW, { CFrame = CFrame.Angles(0, 0, math.rad(45)) })
	piece(head, CFrame.new(0, 0.1, 0), Vector3.new(1.5, 1.4, 1.5), ST, M.Slate)
	piece(head, CFrame.new(0, 0.55, -0.8), Vector3.new(1.4, 0.3, 0.2), rgb(100, 104, 100), M.Slate)
	eyes(model, MOSS_GLOW, 0.3, 0.15, 0.22)
	for _, n in ipairs(ARMS) do
		local arm = bp(model, n)
		piece(arm, CFrame.new(0, 0.6, 0), Vector3.new(1.5, 1.2, 1.5), rgb(104, 108, 104), M.Slate)
		piece(arm, CFrame.new(0, -0.8, 0), Vector3.new(1.4, 0.9, 1.4), ST, M.Slate)
		glow(arm, CFrame.new(0, 0.2, -0.56), Vector3.new(0.2, 0.8, 0.05), MOSS_GLOW)
	end
	for _ = 1, 3 do piece(torso, CFrame.new(math.random(-8, 8) / 10, math.random(-6, 6) / 10, 0.71), Vector3.new(0.6, 0.4, 0.06), rgb(70, 130, 50), M.Grass) end
end

-- ── The Corrupted Forest ────────────────────────────────────────────────────
local VOID, VIOLET, MAGENTA = rgb(34, 24, 44), rgb(150, 70, 230), rgb(255, 60, 200)

-- a stalker: a shadow shape, crystals jutting from its back, magenta eyes
local function dressStalker(model: Model)
	ghost(model, rgb(40, 26, 56), rgb(20, 12, 30), 0.2)
	eyes(model, MAGENTA, 0.24, 0.05, 0.18)
	local torso = bp(model, "Torso")
	for k = -1, 1 do
		glow(torso, CFrame.new(k * 0.6, 0.6 - math.abs(k) * 0.3, 0.7) * CFrame.Angles(math.rad(-30), 0, math.rad(-k * 20)), Vector3.new(0.35, 1.4 - math.abs(k) * 0.4, 0.35), VIOLET)
	end
	for _, n in ipairs(ARMS) do
		local arm = bp(model, n)
		for i = -1, 1 do glow(arm, CFrame.new(i * 0.3, -1.4, -0.1) * CFrame.Angles(math.rad(-15), 0, 0), Vector3.new(0.08, 0.9, 0.08), MAGENTA) end
	end
	particles(torso, { Texture = SMOKE, Color = ColorSequence.new(rgb(90, 40, 140), rgb(20, 10, 30)), Size = seq(1.2, 2.6),
		Transparency = seq(0.5, 1), Lifetime = NumberRange.new(0.8, 1.3), Speed = NumberRange.new(0.5, 1.5), Rate = 8 })
end
-- a void archer: a black hood over a hollow face, a long crystal bow
local function dressVoidArcher(model: Model)
	strip(model)
	model:SetAttribute("NoArrows", true)
	color(model, BODY, rgb(48, 40, 56))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -0.6, 0.15), Vector3.new(2.2, 2.6, 1.2), VOID, M.Fabric)
	piece(head, CFrame.new(0, 0.25, 0.12), Vector3.new(1.45, 1.4, 1.45), VOID, M.Fabric)
	piece(head, CFrame.new(0, 0.95, 0.4) * CFrame.Angles(math.rad(-30), 0, 0), Vector3.new(0.6, 0.9, 0.6), VOID, M.Fabric)
	piece(head, CFrame.new(0, 0, -0.62), Vector3.new(0.9, 0.9, 0.05), rgb(8, 6, 12))
	eyes(model, MAGENTA, 0.2, 0.05, 0.15)
	local arm = bp(model, "Left Arm")
	local g = CFrame.new(0, -1.05, -0.2)
	glow(arm, g * CFrame.new(0, 0, -0.3), Vector3.new(0.18, 4.4, 0.18), VIOLET)
	for _, sy in ipairs({ -1, 1 }) do glow(arm, g * CFrame.new(0, sy * 2.1, 0.3) * CFrame.Angles(math.rad(sy * 30), 0, 0), Vector3.new(0.3, 0.9, 0.3), MAGENTA) end
end
-- a corrupted brute: blackened violet flesh split by crystal growths
local function dressCorruptBrute(model: Model)
	strip(model)
	color(model, BODY, rgb(70, 50, 86))
	color(model, LEGS, rgb(36, 26, 44))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	eyes(model, MAGENTA, 0.26, 0.1, 0.16)
	for _, c in ipairs({ { -0.7, 0.9, 0.5, 20 }, { 0.6, 1.0, 0.6, -25 }, { 0.1, 0.4, 0.7, 5 }, { -0.4, -0.2, 0.65, 35 } }) do
		glow(torso, CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(math.rad(-40), 0, math.rad(c[4])), Vector3.new(0.45, 1.6, 0.45), if c[4] > 0 then VIOLET else MAGENTA)
	end
	for _, n in ipairs(ARMS) do
		local arm = bp(model, n)
		glow(arm, CFrame.new(0, 1.1, 0) * CFrame.Angles(0, math.rad(45), math.rad(20)), Vector3.new(0.5, 1.2, 0.5), VIOLET)
		piece(arm, CFrame.new(0, -0.6, 0), Vector3.new(1.3, 1.2, 1.3), rgb(40, 30, 50), M.Slate) -- (a fist of crystal-crusted stone)
	end
	piece(head, CFrame.new(0, -0.35, -0.62), Vector3.new(1, 0.35, 0.06), rgb(20, 10, 26))
	glow(head, CFrame.new(0, 0.7, 0) * CFrame.Angles(math.rad(-10), 0, 0), Vector3.new(0.35, 0.9, 0.35), MAGENTA)
end
-- a shadow wisp: a ball of smoke round a burning magenta core
local function dressWisp(model: Model)
	local inner, outer = slime(model)
	if inner then inner.Color, inner.Material = MAGENTA, M.Neon end
	if outer then outer.Color, outer.Transparency = rgb(30, 20, 40), 0.35 end
	particles(inner or outer, { Texture = SMOKE, Color = ColorSequence.new(rgb(60, 30, 90), rgb(10, 6, 16)), Size = seq(1.4, 3),
		Transparency = seq(0.4, 1), Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(1, 2), Rate = 12, SpreadAngle = Vector2.new(180, 180) })
end

-- ── The Sunken Sanctuary ────────────────────────────────────────────────────
local TEAL, TEAL2, CYAN, PEARL = rgb(70, 150, 150), rgb(40, 100, 110), rgb(90, 240, 255), rgb(220, 240, 240)

-- an aqua sentinel: teal temple armour, a fin crest, a trident
local function dressSentinel(model: Model)
	strip(model)
	color(model, BODY, rgb(50, 110, 130))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0.2, 0), Vector3.new(2.15, 1.7, 1.15), TEAL, M.Metal)
	glow(torso, CFrame.new(0, 0.3, -0.6), Vector3.new(0.5, 0.5, 0.06), CYAN)
	for _, n in ipairs(ARMS) do piece(bp(model, n), CFrame.new(0, 0.8, 0), Vector3.new(1.4, 0.6, 1.4), TEAL, M.Metal) end
	piece(head, CFrame.new(0, 0.2, 0), Vector3.new(1.35, 1.35, 1.35), TEAL, M.Metal)
	piece(head, CFrame.new(0, 0.1, -0.68), Vector3.new(1.0, 0.18, 0.06), rgb(10, 20, 24))
	glow(head, CFrame.new(0, 0.1, -0.7), Vector3.new(0.8, 0.08, 0.04), CYAN)
	piece(head, CFrame.new(0, 1.0, 0.1), Vector3.new(0.15, 0.9, 1.4), CYAN, M.Neon, { Transparency = 0.3 }) -- (the fin crest)
	local arm, g = held(model)
	piece(arm, g * CFrame.new(0, 1.3, 0), Vector3.new(0.2, 5.2, 0.2), rgb(200, 180, 90), M.Metal)
	for _, sx in ipairs({ -0.4, 0, 0.4 }) do glow(arm, g * CFrame.new(sx, 4.2, 0), Vector3.new(0.12, 0.9, 0.12), CYAN) end
	piece(arm, g * CFrame.new(0, 3.75, 0), Vector3.new(1, 0.16, 0.16), rgb(200, 180, 90), M.Metal)
end
-- a tide archer: a hood of kelp, gills, a pearl-tipped coral bow
local function dressTideArcher(model: Model)
	strip(model, true)
	color(model, BODY, rgb(110, 170, 170))
	bowColor(model, rgb(240, 140, 150))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -0.3, 0.2), Vector3.new(2.2, 2.4, 1.15), TEAL2, M.Fabric)
	piece(head, CFrame.new(0, 0.3, 0.15), Vector3.new(1.4, 1.1, 1.4), TEAL2, M.Fabric)
	for _, sx in ipairs({ -1, 1 }) do
		for k = 0, 2 do piece(head, CFrame.new(sx * 0.62, -0.1 - k * 0.15, 0), Vector3.new(0.06, 0.06, 0.5), rgb(40, 80, 90)) end -- (gills)
		piece(head, CFrame.new(sx * 0.75, 0.3, 0.2) * CFrame.Angles(0, 0, math.rad(sx * -30)), Vector3.new(0.1, 0.8, 0.6), CYAN, M.Neon, { Transparency = 0.4 })
	end
	eyes(model, CYAN, 0.22, 0.05, 0.15)
	piece(torso, CFrame.new(0, 0.9, 0), Vector3.new(1.8, 0.25, 1.1), PEARL) -- (a pearl collar)
end
-- a guardian leviathan: a serpent-headed giant, scales, a glowing crest
local function dressLeviathan(model: Model)
	strip(model)
	local SC, SC2 = rgb(40, 110, 120), rgb(30, 80, 96)
	color(model, BODY, SC)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	for r = 0, 2 do for c = -1, 1 do piece(torso, CFrame.new(c * 0.6, 0.6 - r * 0.6, -0.52), Vector3.new(0.5, 0.45, 0.06), SC2) end end
	piece(torso, CFrame.new(0, 0, 0.6), Vector3.new(0.3, 2, 0.5), CYAN, M.Neon, { Transparency = 0.2 }) -- (a glowing spine)
	piece(head, CFrame.new(0, 0, -0.5), Vector3.new(1.2, 0.9, 1.6), SC)
	piece(head, CFrame.new(0, -0.35, -0.85), Vector3.new(1.0, 0.3, 1.0), SC2)
	for _, sx in ipairs({ -1, 1 }) do
		glow(head, CFrame.new(sx * 0.4, 0.2, -1.1), Vector3.new(0.2, 0.15, 0.2), CYAN)
		piece(head, CFrame.new(sx * 0.55, 0.6, 0.3) * CFrame.Angles(math.rad(-40), 0, math.rad(sx * -20)), Vector3.new(0.2, 1.2, 0.2), PEARL) -- (horns)
	end
	glow(head, CFrame.new(0, 0.7, 0.1), Vector3.new(0.15, 0.7, 1.4), CYAN, { Transparency = 0.25 })
	for _, n in ipairs(ARMS) do piece(bp(model, n), CFrame.new(0, -0.9, -0.3), Vector3.new(1.1, 0.4, 0.8), PEARL) end -- (claws)
end
-- a water sprite: a glowing drop of the sanctuary's water
local function dressSprite(model: Model)
	local inner, outer = slime(model)
	if inner then inner.Color, inner.Material = CYAN, M.Neon end
	if outer then outer.Color, outer.Material, outer.Transparency = rgb(120, 220, 240), M.Glass, 0.45 end
	particles(inner or outer, { Texture = SPARK, Color = ColorSequence.new(rgb(200, 250, 255), CYAN), Size = seq(0.4, 0), LightEmission = 1,
		Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(1, 3), Rate = 10, SpreadAngle = Vector2.new(180, 180) })
end

-- ── The Infernal Citadel ────────────────────────────────────────────────────
local CHAR, EMBER, MOLTEN = rgb(40, 32, 32), rgb(255, 110, 30), rgb(255, 170, 60)

-- a lava imp: small, red, horned, a forked tail, ember eyes
local function dressImp(model: Model)
	strip(model)
	color(model, BODY, rgb(180, 50, 36))
	color(model, LEGS, rgb(90, 30, 24))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	eyes(model, MOLTEN, 0.24, 0.1, 0.2)
	for _, sx in ipairs({ -1, 1 }) do
		piece(head, CFrame.new(sx * 0.5, 0.75, 0) * CFrame.Angles(0, 0, math.rad(sx * -30)), Vector3.new(0.25, 0.8, 0.25), CHAR)
		piece(torso, CFrame.new(sx * 0.6, 0.6, 0.6) * CFrame.Angles(math.rad(-20), 0, math.rad(sx * 50)), Vector3.new(0.12, 1.4, 1.0), rgb(110, 30, 24)) -- (stub wings)
	end
	piece(torso, CFrame.new(0, -1.1, 0.9) * CFrame.Angles(math.rad(50), 0, 0), Vector3.new(0.2, 1.8, 0.2), rgb(150, 40, 30))
	glow(torso, CFrame.new(0, -1.6, 1.7), Vector3.new(0.35, 0.35, 0.35), EMBER, { CFrame = CFrame.Angles(math.rad(45), 0, math.rad(45)) })
	glow(torso, CFrame.new(0, 0, -0.52), Vector3.new(0.5, 0.8, 0.05), EMBER)
	particles(torso, { Texture = SPARK, Color = ColorSequence.new(MOLTEN, EMBER), Size = seq(0.3, 0), LightEmission = 1,
		Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(2, 4), Rate = 6, Acceleration = Vector3.new(0, 4, 0) })
end
-- a fire archer: charred bones, an ember hood, a bag of fire pots
local function dressFireArcher(model: Model)
	strip(model)
	model:SetAttribute("NoArrows", true)
	color(model, BODY, rgb(60, 48, 44))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -0.4, 0.15), Vector3.new(2.2, 2.4, 1.15), rgb(110, 30, 24), M.Fabric)
	piece(head, CFrame.new(0, 0.25, 0.1), Vector3.new(1.4, 1.2, 1.4), rgb(110, 30, 24), M.Fabric)
	piece(head, CFrame.new(0, 0, -0.62), Vector3.new(0.9, 0.9, 0.05), rgb(20, 14, 12))
	eyes(model, MOLTEN, 0.2, 0.05, 0.16)
	piece(torso, CFrame.new(0.7, -0.6, -0.5), Vector3.new(0.9, 0.9, 0.6), rgb(80, 56, 36), M.Leather)
	for k = -1, 1 do glow(torso, CFrame.new(0.7 + k * 0.25, -0.1, -0.5), Vector3.new(0.25, 0.25, 0.25), EMBER) end
	local arm, g = held(model)
	glow(arm, g * CFrame.new(0, 0.3, 0), Vector3.new(0.6, 0.6, 0.6), EMBER)
	particles(bp(model, "Right Arm"), { Texture = FIRE, Color = ColorSequence.new(MOLTEN, EMBER), Size = seq(0.9, 0.1), LightEmission = 1,
		Transparency = seq(0.2, 1), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(1, 3), Rate = 10 })
end
-- a magma brute: black rock split by molten cracks
local function dressMagmaBrute(model: Model)
	strip(model)
	color(model, BODY, CHAR, M.Basalt)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0.4, 0), Vector3.new(2.6, 1.6, 1.5), rgb(52, 42, 40), M.Basalt)
	for _, c in ipairs({ { -0.5, 0.2, 30 }, { 0.4, -0.3, -20 }, { 0.1, 0.7, 70 }, { -0.2, -0.7, -45 } }) do
		glow(torso, CFrame.new(c[1], c[2], -0.76) * CFrame.Angles(0, 0, math.rad(c[3])), Vector3.new(0.12, 0.9, 0.05), EMBER)
	end
	piece(head, CFrame.new(0, 0, 0), Vector3.new(1.4, 1.3, 1.4), rgb(52, 42, 40), M.Basalt)
	glow(head, CFrame.new(0, -0.3, -0.71), Vector3.new(0.9, 0.2, 0.05), EMBER)
	eyes(model, MOLTEN, 0.3, 0.2, 0.2)
	for _, n in ipairs(ARMS) do
		local arm = bp(model, n)
		piece(arm, CFrame.new(0, 0.7, 0), Vector3.new(1.6, 1, 1.6), rgb(52, 42, 40), M.Basalt)
		piece(arm, CFrame.new(0, -0.9, 0), Vector3.new(1.5, 1.1, 1.5), rgb(52, 42, 40), M.Basalt)
		glow(arm, CFrame.new(0, -0.9, -0.76), Vector3.new(0.8, 0.12, 0.05), EMBER)
	end
	particles(torso, { Texture = SMOKE, Color = ColorSequence.new(rgb(70, 60, 58)), Size = seq(1.4, 3), Transparency = seq(0.5, 1),
		Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(2, 3), Rate = 4, EmissionDirection = Enum.NormalId.Top })
end
-- a flame elemental: a body of living fire round a white-hot core
local function dressFlame(model: Model)
	ghost(model, rgb(255, 120, 30), rgb(255, 80, 20), 0.35)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then d.Material = M.Neon end
	end
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	glow(torso, CFrame.new(0, 0.2, 0), Vector3.new(1, 1, 1), rgb(255, 240, 200))
	eyes(model, rgb(255, 255, 220), 0.24, 0.1, 0.2)
	particles(torso, { Texture = FIRE, Color = ColorSequence.new(MOLTEN, EMBER), Size = seq(2.6, 0.4), LightEmission = 1,
		Transparency = seq(0.2, 1), Lifetime = NumberRange.new(0.5, 0.9), Speed = NumberRange.new(3, 6), Rate = 18 })
	particles(head, { Texture = FIRE, Color = ColorSequence.new(MOLTEN, EMBER), Size = seq(1.8, 0.2), LightEmission = 1,
		Transparency = seq(0.2, 1), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(3, 5), Rate = 10, EmissionDirection = Enum.NormalId.Top })
end

-- ── The Ancient Spire ───────────────────────────────────────────────────────
local OBS, OBS2, CRIMSON, SILVER = rgb(30, 26, 34), rgb(46, 40, 52), rgb(235, 40, 55), rgb(170, 172, 184)

-- a spire knight: obsidian plate trimmed silver, a crimson visor, a greatsword
local function dressKnight(model: Model)
	strip(model)
	color(model, BODY, OBS, M.Metal)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0.2, 0), Vector3.new(2.2, 1.8, 1.2), OBS2, M.Metal)
	piece(torso, CFrame.new(0, 0.2, -0.62), Vector3.new(0.2, 1.6, 0.06), SILVER, M.Metal)
	piece(torso, CFrame.new(0, -0.4, 0.62), Vector3.new(2.0, 2.4, 0.1), rgb(90, 14, 24), M.Fabric) -- (a crimson cape)
	for _, sx in ipairs({ -1, 1 }) do
		local arm = bp(model, if sx < 0 then "Left Arm" else "Right Arm")
		piece(arm, CFrame.new(0, 0.85, 0), Vector3.new(1.5, 0.7, 1.5), OBS2, M.Metal)
		piece(arm, CFrame.new(sx * 0.3, 1.3, 0) * CFrame.Angles(0, 0, math.rad(sx * -30)), Vector3.new(0.25, 0.9, 0.25), SILVER, M.Metal)
	end
	piece(head, CFrame.new(0, 0.1, 0), Vector3.new(1.4, 1.5, 1.4), OBS2, M.Metal)
	glow(head, CFrame.new(0, 0.15, -0.71), Vector3.new(1.0, 0.16, 0.05), CRIMSON)
	piece(head, CFrame.new(0, 0.95, 0), Vector3.new(0.2, 0.6, 1.2), SILVER, M.Metal)
	local arm, g = held(model)
	piece(arm, g * CFrame.new(0, 0.4, 0), Vector3.new(0.3, 1, 0.3), rgb(40, 30, 30), M.Leather)
	piece(arm, g * CFrame.new(0, 0.95, 0), Vector3.new(1.4, 0.25, 0.3), SILVER, M.Metal)
	piece(arm, g * CFrame.new(0, 3.3, 0), Vector3.new(0.6, 4.6, 0.15), OBS2, M.Metal)
	glow(arm, g * CFrame.new(0, 3.3, 0), Vector3.new(0.12, 4.4, 0.17), CRIMSON)
end
-- an arcane mage: a high-collared robe, silver circlet, runes orbiting it
local function dressMage(model: Model)
	strip(model)
	model:SetAttribute("NoArrows", true)
	color(model, BODY, rgb(60, 40, 70))
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -0.9, 0), Vector3.new(2.3, 3, 1.3), rgb(40, 20, 50), M.Fabric)
	piece(torso, CFrame.new(0, 0.95, 0.3), Vector3.new(2.3, 0.9, 0.3), rgb(40, 20, 50), M.Fabric) -- (the collar)
	piece(torso, CFrame.new(0, 0, -0.62), Vector3.new(0.3, 2, 0.06), CRIMSON, M.Fabric)
	piece(head, CFrame.new(0, 0.45, 0), Vector3.new(1.3, 0.18, 1.3), SILVER, M.Metal)
	glow(head, CFrame.new(0, 0.45, -0.66), Vector3.new(0.25, 0.25, 0.06), CRIMSON, { CFrame = CFrame.Angles(0, 0, math.rad(45)) })
	eyes(model, rgb(200, 120, 255), 0.22, 0.05, 0.15)
	for k = 0, 2 do
		local a = k / 3 * math.pi * 2
		glow(torso, CFrame.new(math.cos(a) * 1.8, 1.4, math.sin(a) * 1.8) * CFrame.Angles(0, a, math.rad(45)), Vector3.new(0.4, 0.4, 0.08), CRIMSON, { Transparency = 0.15 })
	end
	local arm, g = held(model)
	piece(arm, g * CFrame.new(0, 1.4, 0), Vector3.new(0.2, 4.2, 0.2), OBS2, M.Metal)
	glow(arm, g * CFrame.new(0, 3.6, 0), Vector3.new(0.55, 0.55, 0.55), CRIMSON, { CFrame = CFrame.Angles(math.rad(45), math.rad(45), 0) })
end
-- a void golem: stacked obsidian blocks round a red core, floating fists
local function dressGolem(model: Model)
	strip(model)
	color(model, BODY, OBS, M.Slate)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0.3, 0), Vector3.new(2.8, 2, 1.7), OBS2, M.Slate)
	glow(torso, CFrame.new(0, 0.3, -0.86), Vector3.new(0.9, 0.9, 0.06), CRIMSON)
	for _, c in ipairs({ { -1, 1 }, { 1, 1 } }) do piece(torso, CFrame.new(c[1] * 1.5, 1.2, 0), Vector3.new(1.2, 1.2, 1.4), OBS, M.Slate) end
	piece(head, CFrame.new(0, -0.1, -0.1), Vector3.new(1.2, 1, 1.2), OBS2, M.Slate)
	glow(head, CFrame.new(0, 0, -0.71), Vector3.new(0.7, 0.14, 0.05), CRIMSON)
	for _, n in ipairs(ARMS) do
		local arm = bp(model, n)
		piece(arm, CFrame.new(0, -1.2, 0), Vector3.new(1.7, 1.4, 1.7), OBS2, M.Slate)
		glow(arm, CFrame.new(0, -0.3, 0), Vector3.new(1.1, 0.2, 1.1), CRIMSON, { Transparency = 0.3 })
	end
	for _, n in ipairs(ARMS) do color(model, { n }, OBS, M.Slate) end
end
-- a rift drone: a floating black eye in a ring of shards, red beam-lens
local function dressDrone(model: Model)
	strip(model)
	model:SetAttribute("NoArrows", true)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Name ~= "Head" and d.Name ~= "Torso" then d.Transparency = 1 end
	end
	color(model, { "Torso", "Head" }, OBS, M.Metal)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0, 0), Vector3.new(2.4, 2.4, 2.4), OBS2, M.Metal)
	glow(head, CFrame.new(0, 0, -0.62), Vector3.new(0.7, 0.7, 0.06), CRIMSON)
	piece(head, CFrame.new(0, 0, -0.66), Vector3.new(1.0, 1.0, 0.05), SILVER, M.Metal, { Transparency = 0.6 })
	for k = 0, 5 do
		local a = k / 6 * math.pi * 2
		piece(torso, CFrame.new(math.cos(a) * 1.9, math.sin(a) * 1.9, 0.2) * CFrame.Angles(0, 0, a), Vector3.new(0.4, 1.0, 0.3), OBS, M.Metal)
		if k % 2 == 0 then glow(torso, CFrame.new(math.cos(a) * 2.2, math.sin(a) * 2.2, 0.2) * CFrame.Angles(0, 0, a), Vector3.new(0.15, 0.4, 0.15), CRIMSON) end
	end
	particles(torso, { Texture = SPARK, Color = ColorSequence.new(CRIMSON), Size = seq(0.3, 0), LightEmission = 1,
		Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(1, 2), Rate = 6, SpreadAngle = Vector2.new(180, 180) })
end


-- ── The Frozen Isle ─────────────────────────────────────────────────────────
local FROST, ICEB, FUR, RIME = rgb(150, 210, 255), rgb(170, 210, 240), rgb(232, 236, 240), rgb(110, 200, 255)

-- a frost wolf: grey-white fur, a long muzzle, ice along its spine
local function dressWolf(model: Model)
	strip(model)
	color(model, BODY, rgb(190, 196, 206), M.Fabric)
	color(model, LEGS, rgb(150, 156, 168), M.Fabric)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(head, CFrame.new(0, -0.15, -0.8), Vector3.new(0.8, 0.6, 0.9), rgb(200, 206, 214), M.Fabric) -- (the muzzle)
	piece(head, CFrame.new(0, -0.1, -1.27), Vector3.new(0.3, 0.25, 0.1), rgb(30, 30, 34))
	for _, sx in ipairs({ -1, 1 }) do piece(head, CFrame.new(sx * 0.4, 0.75, 0.05), Vector3.new(0.3, 0.6, 0.2), rgb(160, 166, 178), M.Fabric) end -- (ears)
	eyes(model, FROST, 0.26, 0.15, 0.17)
	for k = 0, 3 do piece(torso, CFrame.new(0, 0.8 - k * 0.5, 0.6) * CFrame.Angles(math.rad(-30), 0, 0), Vector3.new(0.3, 0.6, 0.3), ICEB, M.Ice) end
	piece(torso, CFrame.new(0, -1.2, 1.0) * CFrame.Angles(math.rad(55), 0, 0), Vector3.new(0.5, 1.8, 0.5), rgb(210, 214, 222), M.Fabric) -- (the tail)
	for _, n in ipairs(ARMS) do
		for i = -1, 1 do piece(bp(model, n), CFrame.new(i * 0.3, -1.1, -0.45), Vector3.new(0.12, 0.3, 0.12), rgb(240, 240, 240)) end -- (claws)
	end
end
-- an ice archer: a fur-trimmed hood, a bow of pale ice
local function dressIceArcher(model: Model)
	strip(model, true)
	color(model, BODY, rgb(120, 140, 170))
	bowColor(model, ICEB)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, -0.3, 0.2), Vector3.new(2.25, 2.5, 1.2), rgb(70, 90, 130), M.Fabric)
	piece(torso, CFrame.new(0, 0.9, 0), Vector3.new(2.2, 0.5, 1.2), FUR, M.Fabric)
	piece(head, CFrame.new(0, 0.3, 0.15), Vector3.new(1.45, 1.15, 1.45), rgb(70, 90, 130), M.Fabric)
	piece(head, CFrame.new(0, 0.05, -0.62), Vector3.new(1.3, 1.2, 0.2), FUR, M.Fabric, { Transparency = 0 })
	piece(head, CFrame.new(0, 0.05, -0.7), Vector3.new(0.9, 0.7, 0.1), rgb(20, 24, 34))
	eyes(model, RIME, 0.2, 0.05, 0.15)
	piece(torso, CFrame.new(0.6, 0.2, 0.65) * CFrame.Angles(0, 0, math.rad(20)), Vector3.new(0.5, 1.8, 0.5), rgb(80, 60, 44), M.Leather)
	for k = -1, 1 do glow(torso, CFrame.new(0.6 + k * 0.12, 1.15, 0.65), Vector3.new(0.1, 0.4, 0.1), RIME) end
end
-- a frost wraith: a shape of drifting snow and pale ice, glowing blue
local function dressFrostWraith(model: Model)
	ghost(model, rgb(200, 230, 250), rgb(150, 196, 230), 0.3)
	eyes(model, RIME, 0.24, 0.05, 0.18)
	local torso = bp(model, "Torso")
	for k = -1, 1 do
		piece(torso, CFrame.new(k * 0.7, 1.0, 0.3) * CFrame.Angles(math.rad(-20), 0, math.rad(-k * 25)), Vector3.new(0.3, 1.2, 0.3), ICEB, M.Ice) -- (an ice crown of shards)
	end
	for _, n in ipairs(ARMS) do
		for i = -1, 1 do glow(bp(model, n), CFrame.new(i * 0.3, -1.4, -0.1) * CFrame.Angles(math.rad(-15), 0, 0), Vector3.new(0.08, 0.9, 0.08), RIME) end
	end
	particles(torso, { Texture = SPARK, Color = ColorSequence.new(rgb(240, 250, 255), RIME), Size = seq(0.4, 0), LightEmission = 0.6,
		Lifetime = NumberRange.new(1, 2), Speed = NumberRange.new(0.5, 1.5), Rate = 10, SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -2, 0) })
end
-- a yeti brute: shaggy white fur, a blue face, great fists rimed in ice
local function dressYeti(model: Model)
	strip(model)
	color(model, BODY, FUR, M.Fabric)
	local torso, head = bp(model, "Torso"), bp(model, "Head")
	piece(torso, CFrame.new(0, 0.3, 0.1), Vector3.new(2.6, 2.1, 1.5), rgb(226, 230, 236), M.Fabric)
	piece(head, CFrame.new(0, 0.15, 0.05), Vector3.new(1.5, 1.4, 1.5), rgb(226, 230, 236), M.Fabric)
	piece(head, CFrame.new(0, -0.05, -0.72), Vector3.new(1.0, 0.9, 0.08), rgb(90, 120, 160))
	eyes(model, RIME, 0.24, 0.12, 0.2)
	piece(head, CFrame.new(0, -0.35, -0.78), Vector3.new(0.7, 0.2, 0.06), rgb(30, 30, 40))
	for _, sx in ipairs({ -1, 1 }) do
		piece(head, CFrame.new(sx * 0.6, 0.7, 0) * CFrame.Angles(0, 0, math.rad(sx * -40)), Vector3.new(0.3, 0.9, 0.3), rgb(200, 190, 170)) -- (horns)
		local arm = bp(model, if sx < 0 then "Left Arm" else "Right Arm")
		piece(arm, CFrame.new(0, 0.3, 0), Vector3.new(1.4, 1.6, 1.4), rgb(226, 230, 236), M.Fabric)
		piece(arm, CFrame.new(0, -1, 0), Vector3.new(1.5, 1.1, 1.5), ICEB, M.Ice, { Transparency = 0.15 })
	end
end

-- ── The kinds ───────────────────────────────────────────────────────────────
-- (the Skeleton's ribs and bones are parts of their own on each limb: they
-- take the limb's colour, material and transparency once it's dressed)
local function matchBones(model: Model)
	for _, n in ipairs(BODY) do
		local limb = bp(model, n)
		if not limb then continue end
		for _, d in ipairs(limb:GetChildren()) do
			if d:IsA("BasePart") and d.Name ~= "Dress" then
				d.Color, d.Material = limb.Color, limb.Material
				d.Transparency = math.max(d.Transparency, limb.Transparency)
				if d:IsA("UnionOperation") then d.UsePartColor = true end
			end
		end
	end
end
local function kind(id: string, k: { [string]: any })
	local dress = k.dress
	if dress then
		k.dress = function(model: Model)
			dress(model)
			matchBones(model)
		end
	end
	kinds[id] = k
end

-- the coast: the easiest of the island
kind("pirate_raider", { name = "Pirate Raider", base = "Zombie", health = 0.9, damage = 1, xp = 1, color = RED,
	attrs = { WalkSpeed = 14, Damage = 9, AttackCooldown = 1 }, dress = dressRaider, moves = { { id = "pounce", every = { 4, 6 } } } })
kind("pirate_gunner", { name = "Pirate Gunner", base = "Skeleton", health = 0.75, damage = 1, xp = 1.4, color = rgb(255, 180, 80),
	attrs = { WalkSpeed = 9, Damage = 11, PreferredRange = 42, NoArrows = true }, dress = dressGunner, moves = { { id = "snipe", every = { 4.5, 6 } } } })
kind("reef_shark", { name = "Reef Shark", base = "Zombie", health = 1, damage = 1.1, xp = 1.3, color = rgb(120, 200, 255),
	attrs = { WalkSpeed = 16, Damage = 11, AttackCooldown = 0.9 }, dress = dressShark, moves = { { id = "pounce", every = { 3.5, 5 } } } })
kind("crustacean_brute", { name = "Crustacean Brute", base = "Zombie", health = 3, damage = 1, xp = 2.4, scale = 1.5, color = rgb(255, 110, 60),
	attrs = { WalkSpeed = 8, Damage = 18, AttackCooldown = 1.6, AttackRange = 7.5, Unstaggerable = true }, dress = dressCrab, moves = { { id = "charge", every = { 5.5, 7.5 } } } })
-- the ruins
kind("jungle_warrior", { name = "Jungle Warrior", base = "Zombie", health = 1, damage = 1, xp = 1.2, color = MOSS_GLOW,
	attrs = { WalkSpeed = 14, Damage = 10, AttackCooldown = 1, AttackRange = 6 }, dress = dressJungleWarrior, moves = { { id = "pounce", every = { 4, 5.5 } } } })
kind("jungle_archer", { name = "Jungle Archer", base = "Skeleton", health = 0.8, damage = 1, xp = 1.2,
	attrs = { WalkSpeed = 10 }, dress = dressJungleArcher })
kind("vine_crawler", { name = "Vine Crawler", base = "Slime", health = 1.1, damage = 1, xp = 1.1, scale = 1.2, color = rgb(120, 220, 80),
	attrs = { WalkSpeed = 11 }, dress = dressVineCrawler, moves = { { id = "bithop", every = { 3.4, 4.8 } } } })
kind("stone_guardian", { name = "Stone Guardian", base = "Zombie", health = 4, damage = 1, xp = 3, scale = 1.75, color = MOSS_GLOW,
	attrs = { WalkSpeed = 7, Damage = 22, AttackCooldown = 2, AttackRange = 8.5, Unstaggerable = true }, dress = dressGuardian, moves = { { id = "quake", every = { 6, 8 } } } })
-- the corrupted forest
kind("corrupted_stalker", { name = "Corrupted Stalker", base = "NPCghost", health = 0.95, damage = 1, xp = 1.5, color = MAGENTA,
	attrs = { MobType = "Melee", WalkSpeed = 13, Damage = 11, AttackCooldown = 1.1, AttackRange = 5, XP = 30 }, dress = dressStalker, moves = { { id = "blink", every = { 4.5, 6.5 } } } })
kind("void_archer", { name = "Void Archer", base = "Skeleton", health = 0.8, damage = 1, xp = 1.6, color = VIOLET,
	attrs = { WalkSpeed = 9, Damage = 13, PreferredRange = 44, NoArrows = true }, dress = dressVoidArcher, moves = { { id = "snipe", every = { 4.2, 5.6 } } } })
kind("corrupted_brute", { name = "Corrupted Brute", base = "Zombie", health = 3.4, damage = 1, xp = 2.6, scale = 1.6, color = MAGENTA,
	attrs = { WalkSpeed = 8, Damage = 20, AttackCooldown = 1.6, AttackRange = 7.5, Unstaggerable = true }, dress = dressCorruptBrute, moves = { { id = "charge", every = { 5, 7 } } } })
kind("shadow_wisp", { name = "Shadow Wisp", base = "Slime", health = 0.55, damage = 1, xp = 1, color = MAGENTA,
	attrs = { WalkSpeed = 17, Damage = 13, NoContact = true }, dress = dressWisp, moves = { { id = "fuse", every = { 0, 0 } } } })
-- the sunken sanctuary
kind("aqua_sentinel", { name = "Aqua Sentinel", base = "Zombie", health = 2.2, damage = 1, xp = 2, scale = 1.25, color = CYAN,
	attrs = { WalkSpeed = 10, Damage = 15, AttackCooldown = 1.4, AttackRange = 7, Unstaggerable = true }, dress = dressSentinel, moves = { { id = "charge", every = { 5, 7 } } } })
kind("tide_archer", { name = "Tide Archer", base = "Skeleton", health = 0.85, damage = 1.1, xp = 1.3,
	attrs = { WalkSpeed = 10 }, dress = dressTideArcher })
kind("guardian_leviathan", { name = "Guardian Leviathan", base = "Zombie", health = 4.6, damage = 1.1, xp = 3.4, scale = 2, color = CYAN,
	attrs = { WalkSpeed = 7, Damage = 24, AttackCooldown = 2, AttackRange = 9, Unstaggerable = true }, dress = dressLeviathan, moves = { { id = "quake", every = { 6, 8 } } } })
kind("water_sprite", { name = "Water Sprite", base = "Slime", health = 0.8, damage = 1, xp = 1.1, color = CYAN,
	attrs = { WalkSpeed = 13 }, dress = dressSprite, moves = { { id = "bithop", every = { 3, 4.2 } } } })
-- the infernal citadel: the hardest of the island
kind("lava_imp", { name = "Lava Imp", base = "Zombie", health = 0.7, damage = 1, xp = 1.1, scale = 0.8, color = EMBER,
	attrs = { WalkSpeed = 17, Damage = 10, AttackCooldown = 0.8 }, dress = dressImp, moves = { { id = "pounce", every = { 3, 4.5 } } } })
kind("fire_archer", { name = "Fire Archer", base = "Skeleton", health = 0.9, damage = 1, xp = 1.6, color = EMBER,
	attrs = { WalkSpeed = 9, Damage = 13, PreferredRange = 38, NoArrows = true }, dress = dressFireArcher, moves = { { id = "mortar", every = { 3.6, 5 } } } })
kind("magma_brute", { name = "Magma Brute", base = "Zombie", health = 4.6, damage = 1, xp = 3.2, scale = 1.9, color = EMBER,
	attrs = { WalkSpeed = 7, Damage = 25, AttackCooldown = 2, AttackRange = 8.5, Unstaggerable = true }, dress = dressMagmaBrute, moves = { { id = "quake", every = { 6, 8 } } } })
kind("flame_elemental", { name = "Flame Elemental", base = "NPCghost", health = 1, damage = 1.1, xp = 1.6, color = EMBER,
	attrs = { MobType = "Melee", WalkSpeed = 13, Damage = 12, AttackCooldown = 1.1, AttackRange = 5, XP = 30 }, dress = dressFlame, moves = { { id = "blink", every = { 4, 5.5 } } } })
-- the ancient spire
kind("spire_knight", { name = "Spire Knight", base = "Zombie", health = 3.6, damage = 1, xp = 3, scale = 1.6, color = CRIMSON,
	attrs = { WalkSpeed = 8, Damage = 21, AttackCooldown = 1.8, AttackRange = 8, Unstaggerable = true }, dress = dressKnight, moves = { { id = "execute", every = { 4.5, 6.5 } } } })
kind("arcane_mage", { name = "Arcane Mage", base = "Skeleton", health = 1.1, damage = 1, xp = 2.2, color = CRIMSON,
	attrs = { WalkSpeed = 9, Damage = 11, PreferredRange = 32, NoArrows = true }, dress = dressMage,
	moves = { { id = "bolt", every = { 2.4, 3.4 } }, { id = "hex", every = { 5, 7 } } } })
kind("void_golem", { name = "Void Golem", base = "Zombie", health = 4.8, damage = 1, xp = 3.4, scale = 2, color = CRIMSON,
	attrs = { WalkSpeed = 6.5, Damage = 26, AttackCooldown = 2.1, AttackRange = 9, Unstaggerable = true }, dress = dressGolem, moves = { { id = "quake", every = { 6, 8 } } } })
kind("rift_drone", { name = "Rift Drone", base = "Skeleton", health = 0.8, damage = 1, xp = 1.5, color = CRIMSON,
	attrs = { WalkSpeed = 11, Damage = 11, PreferredRange = 28, NoArrows = true }, dress = dressDrone, moves = { { id = "laser", every = { 3.2, 4.4 } } } })
-- the frozen isle
kind("frost_wolf", { name = "Frost Wolf", base = "Zombie", health = 0.9, damage = 1, xp = 1.2, color = FROST,
	attrs = { WalkSpeed = 17, Damage = 11, AttackCooldown = 0.8 }, dress = dressWolf, moves = { { id = "pounce", every = { 3, 4.5 } } } })
kind("ice_archer", { name = "Ice Archer", base = "Skeleton", health = 0.85, damage = 1.1, xp = 1.3,
	attrs = { WalkSpeed = 10 }, dress = dressIceArcher })
kind("frost_wraith", { name = "Frost Wraith", base = "NPCghost", health = 1, damage = 1, xp = 1.6, color = FROST,
	attrs = { MobType = "Melee", WalkSpeed = 13, Damage = 12, AttackCooldown = 1.1, AttackRange = 5, XP = 30 }, dress = dressFrostWraith, moves = { { id = "blink", every = { 4, 5.5 } } } })
kind("yeti_brute", { name = "Yeti Brute", base = "Zombie", health = 4.4, damage = 1, xp = 3.2, scale = 1.9, color = FROST,
	attrs = { WalkSpeed = 7.5, Damage = 24, AttackCooldown = 1.9, AttackRange = 8.5, Unstaggerable = true }, dress = dressYeti, moves = { { id = "quake", every = { 6, 8 } } } })

return IslandMobs
