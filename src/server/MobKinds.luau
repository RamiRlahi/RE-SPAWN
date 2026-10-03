--!strict
--[[
	MobKinds.luau
	The dungeon's mob roster. Every kind is one of the four base templates in
	ReplicatedStorage.Mobs (Zombie, Skeleton, Slime, NPCghost) dressed in its
	own look, with its own stats and a signature move. MobManager plans each
	room from a themed pack, dresses the clone (Prepare) before configuring
	it, then starts the kind's move loop (Attach).

	  Zombie, Skeleton archer, Slime     the base mobs, as they were
	  Ghoul        (Zombie)    hunched and fast: POUNCES onto your spot
	  Brute        (Zombie)    huge, slow, iron-shod: CHARGES down a line; can't be staggered
	  Bone Mage    (Skeleton)  hooded caster: a HEX circle under your feet
	  Wraith       (NPCghost)  vanishes and BLINKS in behind you, then slashes
	  Magma Slime  (Slime)     rushes you and EXPLODES (kill it first to defuse it)
	  Bloat Slime  (Slime)     big and slow: SPLITS into three slimelings when it dies
	  Necromancer  (Skeleton)  keeps away, RAISES the dead and throws soul bolts

	Every move is telegraphed on the floor first (a ring in the kind's colour
	filling up), and hitting a caster or a crouching ghoul mid-windup
	(stagger) cancels it.

	Elites roll a trait on top of the purple flames: Frenzied (faster),
	Vampiric (heals when it hurts you), Volatile (explodes when it dies) or
	Blazing (leaves burning ground behind it).

	While a move runs the mob's "MobBusy" attribute pauses MobManager's chase
	AI, the same way "BossBusy" does for bosses.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local MobKinds = {}

-- Set by MobManager.Init.
export type Deps = {
	canAct: (Model) -> boolean,                       -- not frozen / paused / chilled
	hurt: (Model, number, Vector3?, Model?) -> number, -- damage a player (from, attacker); returns what landed
	spawnKind: (string, CFrame, Model?) -> Model?,    -- another mob, in `near`'s room
	damageScale: () -> number,                        -- the Threat tier's damage multiplier
}
local deps: Deps

-- ── Kinds ───────────────────────────────────────────────────────────────────
type MoveSlot = { id: string, every: { number } }

export type Kind = {
	name: string,
	base: string,              -- template in ReplicatedStorage.Mobs
	health: number,            -- × the base mob health
	damage: number,            -- × its damage
	xp: number,
	scale: number?,
	attrs: { [string]: any }?, -- MobType, WalkSpeed, AttackRange, ...
	dress: ((Model) -> ())?,
	moves: { MoveSlot }?,
	color: Color3?,            -- its telegraphs / magic
}

local VIOLET = Color3.fromRGB(190, 110, 255)
local CYAN = Color3.fromRGB(120, 235, 255)
local SOUL = Color3.fromRGB(120, 255, 140)
local EMBER = Color3.fromRGB(255, 120, 30)
local BLOOD = Color3.fromRGB(255, 60, 50)

local kinds: { [string]: Kind } = {}
MobKinds.Kinds = kinds

-- ── Dressing helpers ────────────────────────────────────────────────────────
-- A piece welded onto `body` at `offset` (body space).
local function piece(body: BasePart, offset: CFrame, props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.CFrame = body.CFrame * offset
	local w = Instance.new("Weld")
	w.Part0 = body
	w.Part1 = p
	w.C0 = offset
	w.Parent = p
	p.Parent = body.Parent
	return p
end

local function bodyPart(model: Model, name: string): BasePart?
	local p = model:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function recolor(model: Model, names: { string }, color: Color3, material: Enum.Material?)
	for _, n in ipairs(names) do
		local p = bodyPart(model, n)
		if p then
			p.Color = color
			if material then p.Material = material end
		end
	end
end

-- Drop what dresses an R6 rig on its own (clothes, body colours, the face).
local function strip(model: Model, keepFace: boolean?)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Shirt") or d:IsA("Pants") or d:IsA("ShirtGraphic") or d:IsA("BodyColors") then
			d:Destroy()
		elseif not keepFace and d:IsA("Decal") and d.Parent and d.Parent.Name == "Head" then
			d:Destroy()
		end
	end
end

-- Two glowing eyes on the head (head space: the classic head's face is at -Z).
local function eyes(model: Model, color: Color3, spread: number?, depth: number?, size: number?)
	local head = bodyPart(model, "Head")
	if not head then return end
	local s = size or 0.16
	for _, side in ipairs({ -1, 1 }) do
		piece(head, CFrame.new(side * (spread or 0.22), 0.1, -(depth or 0.6)), {
			Name = "Eye", Size = Vector3.new(s * 1.3, s, 0.06), Color = color, Material = Enum.Material.Neon,
		})
	end
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = 6
	light.Brightness = 1.2
	light.Parent = head
end

-- A deep hood around the head with an open face (head space).
local function hood(model: Model, color: Color3, trim: Color3?)
	local head = bodyPart(model, "Head")
	local torso = bodyPart(model, "Torso")
	if not head or not torso then return end
	local parts = {
		{ CFrame.new(0, 0.74, 0.06), Vector3.new(1.55, 0.3, 1.5) },           -- crown
		{ CFrame.new(0, 0.05, 0.7), Vector3.new(1.55, 1.45, 0.24) },          -- back
		{ CFrame.new(-0.74, 0.05, 0.04), Vector3.new(0.22, 1.4, 1.48) },      -- sides
		{ CFrame.new(0.74, 0.05, 0.04), Vector3.new(0.22, 1.4, 1.48) },
		{ CFrame.new(0, 0.66, -0.7), Vector3.new(1.5, 0.24, 0.22) },          -- brim, shading the face
		{ CFrame.new(0, 0.92, 0.42) * CFrame.Angles(math.rad(-25), 0, 0), Vector3.new(1.2, 0.3, 0.9) }, -- the peak
	}
	for _, d in ipairs(parts) do
		piece(head, d[1], { Name = "Hood", Size = d[2], Color = color, Material = Enum.Material.Fabric })
	end
	-- the cowl draping onto the shoulders
	piece(torso, CFrame.new(0, 0.92, 0.08), { Name = "Cowl", Size = Vector3.new(2.25, 0.42, 1.3), Color = color, Material = Enum.Material.Fabric })
	if trim then
		piece(head, CFrame.new(0, 0.66, -0.82), { Name = "HoodTrim", Size = Vector3.new(1.5, 0.08, 0.04), Color = trim, Material = Enum.Material.Metal })
	end
end

-- A long robe over the torso and down past the knees (torso space).
local function robe(model: Model, color: Color3, trim: Color3)
	local torso = bodyPart(model, "Torso")
	if not torso then return end
	local function c(name: string, size: Vector3): { [string]: any }
		return { Name = name, Size = size, Color = color, Material = Enum.Material.Fabric }
	end
	piece(torso, CFrame.new(0, 0, 0), c("Robe", Vector3.new(2.12, 2.04, 1.12)))
	piece(torso, CFrame.new(0, -1.75, 0.04), c("RobeSkirt", Vector3.new(2.2, 1.6, 1.22)))
	piece(torso, CFrame.new(0, -2.45, 0.06), c("RobeHem", Vector3.new(2.32, 0.5, 1.32)))
	-- gold (or bone) trim down the front and round the waist
	piece(torso, CFrame.new(0, -0.6, -0.575), { Name = "RobeTrim", Size = Vector3.new(0.22, 3.6, 0.04), Color = trim, Material = Enum.Material.Metal })
	piece(torso, CFrame.new(0, -0.95, 0), { Name = "RobeBelt", Size = Vector3.new(2.16, 0.2, 1.16), Color = trim, Material = Enum.Material.Metal })
	-- wide sleeves over the arms, the bony hands poking out
	for _, n in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = bodyPart(model, n)
		if arm then
			piece(arm, CFrame.new(0, 0.25, 0), c("Sleeve", Vector3.new(1.12, 1.55, 1.12)))
			piece(arm, CFrame.new(0, -0.55, 0), { Name = "SleeveCuff", Size = Vector3.new(1.18, 0.16, 1.18), Color = trim, Material = Enum.Material.Metal })
		end
	end
end

-- A staff held upright in the right hand (arm space); returns the arm, for
-- what crowns it.
local function staff(model: Model, wood: Color3): BasePart?
	local arm = bodyPart(model, "Right Arm")
	if not arm then return nil end
	piece(arm, CFrame.new(0, 0.1, -0.62), { Name = "Staff", Size = Vector3.new(0.18, 4.6, 0.18), Color = wood, Material = Enum.Material.Wood })
	piece(arm, CFrame.new(0, -1, -0.62), { Name = "StaffGrip", Size = Vector3.new(0.26, 0.5, 0.26), Color = Color3.fromRGB(40, 28, 22), Material = Enum.Material.Fabric })
	-- the crook cradling the head
	piece(arm, CFrame.new(-0.22, 2.45, -0.62) * CFrame.Angles(0, 0, math.rad(25)), { Name = "StaffCrook", Size = Vector3.new(0.14, 0.7, 0.14), Color = wood, Material = Enum.Material.Wood })
	piece(arm, CFrame.new(0.22, 2.45, -0.62) * CFrame.Angles(0, 0, math.rad(-25)), { Name = "StaffCrook", Size = Vector3.new(0.14, 0.7, 0.14), Color = wood, Material = Enum.Material.Wood })
	return arm
end

-- ── The kinds' looks ────────────────────────────────────────────────────────
local function dressGhoul(model: Model)
	strip(model)
	local skin = Color3.fromRGB(146, 156, 128)
	local rag = Color3.fromRGB(52, 46, 44)
	recolor(model, { "Head", "Left Arm", "Right Arm" }, skin)
	recolor(model, { "Torso" }, Color3.fromRGB(70, 62, 56))
	recolor(model, { "Left Leg", "Right Leg" }, rag)
	eyes(model, BLOOD, 0.24, 0.6, 0.15)
	local head = bodyPart(model, "Head")
	if head then
		-- a gaping, toothy mouth
		piece(head, CFrame.new(0, -0.28, -0.6), { Name = "Mouth", Size = Vector3.new(0.5, 0.2, 0.06), Color = Color3.fromRGB(40, 8, 10) })
		for i = -2, 2 do
			piece(head, CFrame.new(i * 0.1, -0.2, -0.62), { Name = "Tooth", Size = Vector3.new(0.05, 0.08, 0.05), Color = Color3.fromRGB(225, 215, 180) })
		end
	end
	-- long claws
	for _, n in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = bodyPart(model, n)
		if arm then
			for i = -1, 1 do
				piece(arm, CFrame.new(i * 0.3, -1.25, -0.15) * CFrame.Angles(math.rad(-20), 0, 0), {
					Name = "Claw", Size = Vector3.new(0.1, 0.6, 0.1), Color = Color3.fromRGB(220, 210, 180),
				})
			end
			piece(arm, CFrame.new(0, 0.2, 0), { Name = "Rag", Size = Vector3.new(1.06, 0.7, 1.06), Color = rag, Material = Enum.Material.Fabric })
		end
	end
	local torso = bodyPart(model, "Torso")
	if torso then
		-- tattered strips hanging off the waist
		for i, x in ipairs({ -0.75, -0.25, 0.3, 0.8 }) do
			piece(torso, CFrame.new(x, -1.25 - (i % 2) * 0.15, -0.52), { Name = "Rag", Size = Vector3.new(0.38, 0.6 + (i % 2) * 0.3, 0.06),
				Color = rag, Material = Enum.Material.Fabric })
		end
		piece(torso, CFrame.new(0, 0.3, 0), { Name = "Rag", Size = Vector3.new(2.06, 1.3, 1.06), Color = rag, Material = Enum.Material.Fabric })
	end
end

local function dressBrute(model: Model)
	strip(model)
	local skin = Color3.fromRGB(96, 112, 72)
	local metal = Color3.fromRGB(78, 80, 90)
	local leather = Color3.fromRGB(72, 46, 30)
	recolor(model, { "Head", "Left Arm", "Right Arm", "Torso" }, skin)
	recolor(model, { "Left Leg", "Right Leg" }, Color3.fromRGB(52, 40, 34))
	eyes(model, Color3.fromRGB(255, 200, 60), 0.24, 0.6, 0.13)
	local torso = bodyPart(model, "Torso")
	local head = bodyPart(model, "Head")
	if torso then
		-- a strap across the chest, a heavy belt with an iron buckle
		piece(torso, CFrame.new(0, 0.1, 0) * CFrame.Angles(0, 0, math.rad(40)), { Name = "Strap", Size = Vector3.new(0.4, 2.7, 1.08), Color = leather, Material = Enum.Material.Leather })
		piece(torso, CFrame.new(0, -0.82, 0), { Name = "Belt", Size = Vector3.new(2.1, 0.38, 1.1), Color = leather, Material = Enum.Material.Leather })
		piece(torso, CFrame.new(0, -0.82, -0.56), { Name = "Buckle", Size = Vector3.new(0.5, 0.42, 0.08), Color = metal, Material = Enum.Material.Metal })
		piece(torso, CFrame.new(0, -1.35, -0.54), { Name = "Loincloth", Size = Vector3.new(0.9, 0.9, 0.06), Color = leather, Material = Enum.Material.Leather })
	end
	-- iron pauldrons with studs
	for _, n in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = bodyPart(model, n)
		if arm then
			piece(arm, CFrame.new(0, 0.82, 0), { Name = "Pauldron", Size = Vector3.new(1.35, 0.6, 1.35), Color = metal, Material = Enum.Material.Metal })
			piece(arm, CFrame.new(0, 1.18, 0) * CFrame.Angles(0, math.rad(45), 0) * CFrame.Angles(math.rad(45), 0, 0),
				{ Name = "Spike", Size = Vector3.new(0.34, 0.34, 0.34), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Metal })
			piece(arm, CFrame.new(0, -0.7, 0), { Name = "Bracer", Size = Vector3.new(1.08, 0.5, 1.08), Color = leather, Material = Enum.Material.Leather })
		end
	end
	if head then
		-- a half-helm with horns
		piece(head, CFrame.new(0, 0.5, 0.02), { Name = "Helm", Size = Vector3.new(1.35, 0.42, 1.35), Color = metal, Material = Enum.Material.Metal })
		piece(head, CFrame.new(0, 0.2, -0.66), { Name = "Helm", Size = Vector3.new(0.18, 0.5, 0.08), Color = metal, Material = Enum.Material.Metal })
		for _, side in ipairs({ -1, 1 }) do
			piece(head, CFrame.new(side * 0.78, 0.66, 0) * CFrame.Angles(0, 0, math.rad(-side * 35)),
				{ Name = "Horn", Size = Vector3.new(0.22, 0.6, 0.22), Color = Color3.fromRGB(225, 215, 185) })
			piece(head, CFrame.new(side * 0.98, 1.02, 0) * CFrame.Angles(0, 0, math.rad(-side * 10)),
				{ Name = "Horn", Size = Vector3.new(0.16, 0.42, 0.16), Color = Color3.fromRGB(225, 215, 185) })
		end
	end
	-- a spiked club gripped in the right fist (held like a tool: it stands
	-- up when the arm reaches forward)
	local arm = bodyPart(model, "Right Arm")
	if arm then
		local grip = CFrame.new(0, -1.05, 0) * CFrame.Angles(math.rad(-90), 0, 0) -- its +Y runs out of the fist
		piece(arm, grip * CFrame.new(0, 0.55, 0), { Name = "Club", Size = Vector3.new(0.34, 2.1, 0.34), Color = Color3.fromRGB(88, 60, 38), Material = Enum.Material.Wood })
		piece(arm, grip * CFrame.new(0, 2.15, 0), { Name = "ClubHead", Size = Vector3.new(0.95, 1.25, 0.95), Color = Color3.fromRGB(70, 48, 30), Material = Enum.Material.Wood })
		piece(arm, grip * CFrame.new(0, 1.55, 0), { Name = "ClubBand", Size = Vector3.new(1.02, 0.16, 1.02), Color = metal, Material = Enum.Material.Metal })
		for _, d in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
			for _, y in ipairs({ 1.95, 2.45 }) do
				piece(arm, grip * CFrame.new(d * 0.5 + Vector3.new(0, y, 0)) * CFrame.Angles(math.rad(45), math.rad(45), 0),
					{ Name = "Spike", Size = Vector3.new(0.2, 0.2, 0.2), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Metal })
			end
		end
	end
end

local function dressBoneMage(model: Model)
	local bow = model:FindFirstChild("Bow")
	if bow then bow:Destroy() end
	strip(model, true)
	local cloth = Color3.fromRGB(58, 30, 92)
	local gold = Color3.fromRGB(212, 170, 80)
	robe(model, cloth, gold)
	hood(model, Color3.fromRGB(44, 22, 70), gold)
	eyes(model, VIOLET, 0.22, 0.62, 0.15)
	local arm = staff(model, Color3.fromRGB(70, 50, 36))
	if arm then
		local orb = piece(arm, CFrame.new(0, 2.75, -0.62), { Name = "StaffOrb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.62, 0.62, 0.62),
			Color = VIOLET, Material = Enum.Material.Neon })
		local light = Instance.new("PointLight")
		light.Name = "OrbLight"
		light.Color = VIOLET
		light.Range = 9
		light.Brightness = 1.6
		light.Parent = orb
		local motes = Instance.new("ParticleEmitter")
		motes.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		motes.Color = ColorSequence.new(VIOLET)
		motes.LightEmission = 1
		motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
		motes.Lifetime = NumberRange.new(0.6, 1)
		motes.Speed = NumberRange.new(0.5, 1.5)
		motes.SpreadAngle = Vector2.new(180, 180)
		motes.Rate = 8
		motes.Parent = orb
	end
end

local function dressNecromancer(model: Model)
	local bow = model:FindFirstChild("Bow")
	if bow then bow:Destroy() end
	strip(model, true)
	local cloth = Color3.fromRGB(24, 30, 26)
	local bone = Color3.fromRGB(220, 214, 190)
	robe(model, cloth, bone)
	hood(model, Color3.fromRGB(16, 20, 18), bone)
	eyes(model, SOUL, 0.22, 0.62, 0.15)
	local torso = bodyPart(model, "Torso")
	if torso then
		-- a ribbed bone collar over the robe
		for i = -2, 2 do
			piece(torso, CFrame.new(i * 0.32, 0.55 - math.abs(i) * 0.08, -0.6), { Name = "Rib", Size = Vector3.new(0.14, 0.5, 0.06), Color = bone })
		end
	end
	local arm = staff(model, Color3.fromRGB(46, 40, 36))
	if arm then
		-- a skull on the staff, wreathed in green flame
		local skull = piece(arm, CFrame.new(0, 2.78, -0.62), { Name = "StaffSkull", Size = Vector3.new(0.55, 0.5, 0.55), Color = bone })
		for _, side in ipairs({ -1, 1 }) do
			piece(arm, CFrame.new(side * 0.12, 2.82, -0.9), { Name = "StaffSkullEye", Size = Vector3.new(0.12, 0.12, 0.04), Color = SOUL, Material = Enum.Material.Neon })
		end
		local fire = Instance.new("Fire")
		fire.Color = SOUL
		fire.SecondaryColor = Color3.fromRGB(20, 80, 30)
		fire.Size = 2.5
		fire.Heat = 6
		fire.Parent = skull
		local light = Instance.new("PointLight")
		light.Name = "OrbLight"
		light.Color = SOUL
		light.Range = 10
		light.Brightness = 1.6
		light.Parent = skull
	end
end

local function dressRisen(model: Model)
	strip(model)
	recolor(model, { "Head", "Left Arm", "Right Arm" }, Color3.fromRGB(118, 132, 110))
	recolor(model, { "Torso" }, Color3.fromRGB(64, 68, 60))
	recolor(model, { "Left Leg", "Right Leg" }, Color3.fromRGB(48, 50, 46))
	eyes(model, SOUL, 0.24, 0.6, 0.14)
	local torso = bodyPart(model, "Torso")
	if torso then
		-- grave dirt clinging on
		piece(torso, CFrame.new(0.4, -0.5, -0.52), { Name = "Dirt", Size = Vector3.new(0.7, 0.5, 0.06), Color = Color3.fromRGB(70, 56, 40), Material = Enum.Material.Ground })
	end
end

local function dressWraith(model: Model)
	strip(model)
	local body = Color3.fromRGB(34, 26, 58)
	local cloak = Color3.fromRGB(14, 10, 22)
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			d.Material = Enum.Material.SmoothPlastic
			d.Color = body
			d.Transparency = 0.25
		end
	end
	recolor(model, { "Left Leg", "Right Leg" }, body)
	for _, n in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = bodyPart(model, n)
		if leg then leg.Transparency = 1 end
	end
	hood(model, cloak)
	eyes(model, CYAN, 0.24, 0.55, 0.17)
	local torso = bodyPart(model, "Torso")
	if torso then
		-- a ragged cloak and a tail of shadow instead of legs
		piece(torso, CFrame.new(0, -0.1, 0.12), { Name = "Cloak", Size = Vector3.new(2.3, 2.3, 1.2), Color = cloak, Material = Enum.Material.Fabric, Transparency = 0.1 })
		local tail = {
			{ CFrame.new(0, -1.6, 0.1), Vector3.new(1.9, 1.3, 1.0), 0.15 },
			{ CFrame.new(0, -2.55, 0.3), Vector3.new(1.3, 1.1, 0.75), 0.35 },
			{ CFrame.new(0, -3.3, 0.5), Vector3.new(0.7, 0.8, 0.45), 0.6 },
		}
		for _, t in ipairs(tail) do
			piece(torso, t[1], { Name = "Tail", Size = t[2], Color = cloak, Material = Enum.Material.Fabric, Transparency = t[3] })
		end
		local smoke = Instance.new("ParticleEmitter")
		smoke.Name = "WraithSmoke"
		smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
		smoke.Color = ColorSequence.new(Color3.fromRGB(40, 30, 70), Color3.fromRGB(10, 8, 16))
		smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
		smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 2.6) })
		smoke.Lifetime = NumberRange.new(0.8, 1.3)
		smoke.Speed = NumberRange.new(0.5, 1.5)
		smoke.Acceleration = Vector3.new(0, 1.5, 0)
		smoke.Rate = 10
		smoke.Parent = torso
	end
	-- long pale claws, reaching out
	for _, n in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = bodyPart(model, n)
		if arm then
			piece(arm, CFrame.new(0, 0.3, 0), { Name = "Sleeve", Size = Vector3.new(1.12, 1.5, 1.12), Color = cloak, Material = Enum.Material.Fabric })
			for i = -1, 1 do
				piece(arm, CFrame.new(i * 0.3, -1.35, -0.1) * CFrame.Angles(math.rad(-15), 0, 0), {
					Name = "Claw", Size = Vector3.new(0.08, 0.8, 0.08), Color = Color3.fromRGB(200, 215, 230), Material = Enum.Material.Neon, Transparency = 0.2,
				})
			end
		end
	end
end

-- Slimes: the template's inner body is the coloured sphere, the outer one its
-- glossy skin.
local function slimeParts(model: Model): (BasePart?, BasePart?)
	local inner, outer = nil, nil
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Sphere.001" then inner = d elseif d.Name == "Sphere" then outer = d end
		end
	end
	return inner, outer
end

local function dressSlime(body: Color3, skin: Color3, glow: boolean): (Model) -> ()
	return function(model: Model)
		local inner, outer = slimeParts(model)
		if inner then
			inner.Color = body
			if glow then inner.Material = Enum.Material.Neon end
		end
		if outer then outer.Color = skin end
	end
end

local function dressMagma(model: Model)
	dressSlime(Color3.fromRGB(255, 104, 24), Color3.fromRGB(62, 26, 16), true)(model)
	local inner = slimeParts(model)
	if inner then
		local light = Instance.new("PointLight")
		light.Name = "CoreLight"
		light.Color = EMBER
		light.Range = 10
		light.Brightness = 1.5
		light.Parent = inner
		local embers = Instance.new("ParticleEmitter")
		embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		embers.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), EMBER)
		embers.LightEmission = 1
		embers.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		embers.Lifetime = NumberRange.new(0.6, 1.1)
		embers.Speed = NumberRange.new(2, 4)
		embers.Acceleration = Vector3.new(0, 4, 0)
		embers.SpreadAngle = Vector2.new(40, 40)
		embers.EmissionDirection = Enum.NormalId.Top
		embers.Rate = 12
		embers.Parent = inner
	end
end

local function dressBloat(model: Model)
	dressSlime(Color3.fromRGB(132, 196, 58), Color3.fromRGB(72, 96, 38), false)(model)
	local inner = slimeParts(model)
	if inner then
		local bubbles = Instance.new("ParticleEmitter")
		bubbles.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		bubbles.Color = ColorSequence.new(Color3.fromRGB(200, 255, 120))
		bubbles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0.5) })
		bubbles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		bubbles.Lifetime = NumberRange.new(0.8, 1.4)
		bubbles.Speed = NumberRange.new(1, 2)
		bubbles.EmissionDirection = Enum.NormalId.Top
		bubbles.Rate = 6
		bubbles.Parent = inner
	end
end

-- ── The roster ──────────────────────────────────────────────────────────────
kinds.zombie = { name = "Zombie", base = "Zombie", health = 1, damage = 1, xp = 1 }
kinds.skeleton = { name = "Skeleton", base = "Skeleton", health = 1, damage = 1, xp = 1 }
kinds.slime = { name = "Slime", base = "Slime", health = 1, damage = 1, xp = 1 }

kinds.ghoul = {
	name = "Ghoul", base = "Zombie", health = 0.75, damage = 1, xp = 1.2, color = BLOOD,
	attrs = { WalkSpeed = 15, Damage = 9, AttackCooldown = 0.9 },
	dress = dressGhoul, moves = { { id = "pounce", every = { 3.5, 5 } } },
}
kinds.brute = {
	name = "Brute", base = "Zombie", health = 3.2, damage = 1, xp = 2.4, scale = 1.45, color = BLOOD,
	attrs = { WalkSpeed = 8, Damage = 20, AttackCooldown = 1.6, AttackRange = 7.5, Unstaggerable = true },
	dress = dressBrute, moves = { { id = "charge", every = { 5.5, 7.5 } } },
}
kinds.bonemage = {
	name = "Bone Mage", base = "Skeleton", health = 0.8, damage = 1, xp = 1.4, color = VIOLET,
	attrs = { WalkSpeed = 10, Damage = 12, PreferredRange = 26, NoArrows = true },
	dress = dressBoneMage, moves = { { id = "hex", every = { 3, 4.2 } } },
}
kinds.wraith = {
	name = "Wraith", base = "NPCghost", health = 0.9, damage = 1, xp = 1.4, color = CYAN,
	attrs = { MobType = "Melee", WalkSpeed = 12, Damage = 10, AttackCooldown = 1.2, AttackRange = 5, XP = 30 },
	dress = dressWraith, moves = { { id = "blink", every = { 4.5, 6.5 } } },
}
kinds.magmaslime = {
	name = "Magma Slime", base = "Slime", health = 0.55, damage = 1, xp = 1, color = EMBER,
	attrs = { WalkSpeed = 17, Damage = 12, NoContact = true },
	dress = dressMagma, moves = { { id = "fuse", every = { 0, 0 } } },
}
kinds.bloatslime = {
	name = "Bloat Slime", base = "Slime", health = 2.4, damage = 1.3, xp = 1.6, scale = 1.6,
	attrs = { WalkSpeed = 9 },
	dress = dressBloat,
}
kinds.slimeling = {
	name = "Slimeling", base = "Slime", health = 0.3, damage = 0.6, xp = 0.3, scale = 0.55,
	attrs = { WalkSpeed = 18 },
	dress = dressSlime(Color3.fromRGB(168, 232, 96), Color3.fromRGB(92, 120, 50), false),
}
kinds.necromancer = {
	name = "Necromancer", base = "Skeleton", health = 1.1, damage = 1, xp = 2.2, color = SOUL,
	attrs = { WalkSpeed = 9, Damage = 10, PreferredRange = 32, NoArrows = true },
	dress = dressNecromancer, moves = { { id = "raise", every = { 7, 9 } }, { id = "bolt", every = { 2.4, 3.4 } } },
}
kinds.risen = {
	name = "Risen", base = "Zombie", health = 0.45, damage = 0.8, xp = 0.3, color = SOUL,
	attrs = { WalkSpeed = 11, Damage = 9 },
	dress = dressRisen,
}

-- ── Room packs ──────────────────────────────────────────────────────────────
-- Each room is one theme: a weighted draw of kinds, with caps so a room is
-- never all brutes or all necromancers.
local PACKS: { { [string]: number } } = {
	{ zombie = 4, ghoul = 3, skeleton = 2, wraith = 1, necromancer = 1 },   -- the crypt
	{ slime = 3, magmaslime = 3, bloatslime = 2, ghoul = 1 },               -- the slime pit
	{ skeleton = 4, bonemage = 2, brute = 1, ghoul = 2 },                    -- the bone legion
	{ wraith = 3, ghoul = 2, bonemage = 2, skeleton = 2, zombie = 1 },       -- the haunt
	{ brute = 1, zombie = 3, skeleton = 3, magmaslime = 1, bonemage = 1 },   -- the warband
}
local CAPS: { [string]: number } = { brute = 2, necromancer = 1, bloatslime = 2, magmaslime = 3, bonemage = 3, wraith = 3 }

function MobKinds.PlanRoom(count: number, level: number): { string }
	local pack = PACKS[math.random(1, #PACKS)]
	local taken: { [string]: number } = {}
	local out = {}
	for _ = 1, count do
		local total = 0
		for id, w in pairs(pack) do
			local cap = CAPS[id]
			if cap then cap += math.floor((level - 1) / 2) end
			if not cap or (taken[id] or 0) < cap then total += w end
		end
		local pick = "zombie"
		local r = math.random() * total
		for id, w in pairs(pack) do
			local cap = CAPS[id]
			if cap then cap += math.floor((level - 1) / 2) end
			if not cap or (taken[id] or 0) < cap then
				r -= w
				if r <= 0 then
					pick = id
					break
				end
			end
		end
		taken[pick] = (taken[pick] or 0) + 1
		table.insert(out, pick)
	end
	return out
end

-- Kinds that can stand in for any old minion (a boss's summons).
MobKinds.MINIONS = { "zombie", "skeleton", "slime", "risen", "ghoul" }

function MobKinds.Template(kindId: string): Model?
	local kind = kinds[kindId]
	local folder = ReplicatedStorage:FindFirstChild("Mobs")
	local t = kind and folder and folder:FindFirstChild(kind.base)
	return if t and t:IsA("Model") then t else nil
end

-- ── Elite traits ────────────────────────────────────────────────────────────
type Affix = { name: string, color: Color3 }
local AFFIXES: { [string]: Affix } = {
	frenzied = { name = "Frenzied", color = Color3.fromRGB(255, 120, 60) },
	vampiric = { name = "Vampiric", color = Color3.fromRGB(210, 20, 50) },
	volatile = { name = "Volatile", color = Color3.fromRGB(255, 160, 40) },
	blazing = { name = "Blazing", color = Color3.fromRGB(255, 110, 20) },
}
local AFFIX_IDS = { "frenzied", "vampiric", "volatile", "blazing" }

function MobKinds.RollAffix(): string
	return AFFIX_IDS[math.random(1, #AFFIX_IDS)]
end

-- Dress a fresh clone of the kind's template and set its stats, before
-- MobManager configures it (`elite` multiplies on top).
function MobKinds.Prepare(model: Model, kindId: string, affixId: string?)
	local kind = kinds[kindId]
	if not kind then return end
	if kind.dress then kind.dress(model) end
	if kind.scale and kind.scale ~= 1 then
		pcall(function() model:ScaleTo(model:GetScale() * (kind.scale :: number)) end)
	end
	for k, v in pairs(kind.attrs or {}) do model:SetAttribute(k, v) end
	model:SetAttribute("MobKind", kindId)
	model:SetAttribute("DisplayName", kind.name)
	model:SetAttribute("HealthMult", kind.health)
	model:SetAttribute("DamageMult", kind.damage)
	model:SetAttribute("XPMult", kind.xp)
	local affix = affixId and AFFIXES[affixId]
	if affix then
		model:SetAttribute("Affix", affixId)
		model:SetAttribute("DisplayName", `{affix.name} {kind.name}`)
		if affixId == "frenzied" then
			local speed = model:GetAttribute("WalkSpeed")
			model:SetAttribute("WalkSpeed", (if typeof(speed) == "number" then speed else 12) * 1.35)
			local cd = model:GetAttribute("AttackCooldown")
			model:SetAttribute("AttackCooldown", (if typeof(cd) == "number" then cd else 1) * 0.6)
			model:SetAttribute("CooldownMult", 0.6)
		end
	end
end

-- ── FX ──────────────────────────────────────────────────────────────────────
local fxFolder: Folder? = nil
local function fx(): Folder
	if fxFolder and fxFolder.Parent then return fxFolder end
	local f = Instance.new("Folder")
	f.Name = "MobFX"
	f.Parent = Workspace
	fxFolder = f
	return f
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = fx()
	return p
end

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- a cylinder lying flat

local function tween(inst: Instance, t: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal):Play()
end

-- A ring on the floor in `color` that fills up over `t`: where the move
-- lands. Returns its parts (to cancel it early).
local function ring(center: Vector3, radius: number, t: number, floorY: number, color: Color3): { BasePart }
	local pos = Vector3.new(center.X, floorY + 0.1, center.Z)
	local rim = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, radius * 2, radius * 2),
		CFrame = CFrame.new(pos) * FLAT, Color = color, Transparency = 0.5 })
	local inner = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, radius * 2 - 0.5, radius * 2 - 0.5),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.01, 0)) * FLAT, Color = Color3.fromRGB(20, 10, 14),
		Material = Enum.Material.SmoothPlastic, Transparency = 0.45 })
	local fill = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.3, 0.3),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.02, 0)) * FLAT, Color = color, Transparency = 0.72 })
	tween(fill, t, { Size = Vector3.new(0.14, radius * 2 - 0.5, radius * 2 - 0.5), Transparency = 0.5 }, Enum.EasingStyle.Linear)
	-- the rim brightens as it's about to go off
	tween(rim, t, { Transparency = 0.05 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, p in ipairs({ rim, inner, fill }) do Debris:AddItem(p, t) end
	return { rim, inner, fill }
end

-- A band along the floor from `from` in `dir`, filling out to the far end.
local function lane(from: Vector3, dir: Vector3, length: number, width: number, t: number, floorY: number, color: Color3): { BasePart }
	local y = floorY + 0.1
	local mid = from + dir * (length / 2)
	local cf = CFrame.lookAt(Vector3.new(mid.X, y, mid.Z), Vector3.new(mid.X + dir.X, y, mid.Z + dir.Z))
	local bar = part({ Size = Vector3.new(width, 0.1, length), CFrame = cf, Color = Color3.fromRGB(20, 10, 14),
		Material = Enum.Material.SmoothPlastic, Transparency = 0.5 })
	local edges = {}
	for _, side in ipairs({ -1, 1 }) do
		table.insert(edges, part({ Size = Vector3.new(0.18, 0.12, length), CFrame = cf * CFrame.new(side * (width / 2 - 0.09), 0.01, 0),
			Color = color, Transparency = 0.35 }))
	end
	local fill = part({ Size = Vector3.new(width - 0.4, 0.12, 0.2),
		CFrame = CFrame.lookAt(Vector3.new(from.X, y + 0.02, from.Z), Vector3.new(from.X + dir.X, y + 0.02, from.Z + dir.Z)) * CFrame.new(0, 0, -0.1),
		Color = color, Transparency = 0.6 })
	tween(fill, t, { Size = Vector3.new(width - 0.4, 0.12, length), CFrame = cf * CFrame.new(0, 0.02, 0) }, Enum.EasingStyle.Linear)
	local all = { bar, fill, edges[1], edges[2] }
	for _, p in ipairs(all) do Debris:AddItem(p, t) end
	return all
end

local function cancel(parts: { BasePart })
	for _, p in ipairs(parts) do p:Destroy() end
end

-- An expanding ring where something lands.
local function shock(center: Vector3, radius: number, color: Color3, floorY: number)
	local r = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.5, 1.5),
		CFrame = CFrame.new(Vector3.new(center.X, floorY + 0.2, center.Z)) * FLAT, Color = color, Transparency = 0.15 })
	tween(r, 0.35, { Size = Vector3.new(0.1, radius * 2.2, radius * 2.2), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(r, 0.4)
end

-- A bright burst: a sphere flashing out and fading.
local function burst(center: Vector3, radius: number, color: Color3)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = CFrame.new(center), Color = color, Transparency = 0.1 })
	tween(b, 0.3, { Size = Vector3.one * radius * 2, Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(b, 0.35)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = radius * 2.5
	light.Brightness = 3
	light.Parent = b
end

-- A column of light rising out of the floor (the hex going off).
local function pillar(center: Vector3, radius: number, color: Color3, floorY: number)
	local c = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, radius * 1.6, radius * 1.6),
		CFrame = CFrame.new(Vector3.new(center.X, floorY + 0.2, center.Z)) * CFrame.Angles(0, 0, math.rad(90)), Color = color, Transparency = 0.2 })
	tween(c, 0.4, { Size = Vector3.new(9, radius * 0.4, radius * 0.4), CFrame = CFrame.new(Vector3.new(center.X, floorY + 4.5, center.Z)) * CFrame.Angles(0, 0, math.rad(90)), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(c, 0.45)
end

local function sparks(at: Vector3, color: Color3, count: number, speed: number)
	local p = part({ Size = Vector3.one * 0.2, CFrame = CFrame.new(at), Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.4), color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.3, 0.7)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 1)
end

local function smokePuff(at: Vector3, color: Color3, count: number)
	local p = part({ Size = Vector3.one * 0.2, CFrame = CFrame.new(at), Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/smoke_main.dds"
	e.Color = ColorSequence.new(color)
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.5), NumberSequenceKeypoint.new(1, 3.5) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(2, 5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Rate = 0
	e.Parent = p
	e:Emit(count)
	Debris:AddItem(p, 1.2)
end

-- ── A live mob ──────────────────────────────────────────────────────────────
type Mob = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	kind: Kind,
	id: string,
	floorY: number,
	base: { [Motor6D]: CFrame },  -- resting joint offsets (poses turn about these)
	minions: { Model },
	nextMove: { [string]: number },
}

type Victim = { char: Model, root: BasePart }

local function victims(): { Victim }
	local out = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char and plr:GetAttribute("InLobby") ~= true then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then table.insert(out, { char = char, root = root }) end
		end
	end
	return out
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

local function alive(m: Mob): boolean
	return m.model.Parent ~= nil and m.hum.Health > 0 and m.root.Parent ~= nil
end

local function staggered(m: Mob): boolean
	return (m.model:GetAttribute("StaggerUntil") or 0) > os.clock()
end

-- Wait `t` seconds of active time (paused while the mob can't act). An
-- `interruptible` wait gives up when the mob is staggered by a hit.
local function hold(m: Mob, t: number, interruptible: boolean?): boolean
	local left = t
	while left > 0 do
		local dt = task.wait(0.05)
		if not alive(m) then return false end
		if interruptible and staggered(m) then return false end
		if deps.canAct(m.model) then left -= dt end
	end
	return true
end

local function nearest(m: Mob, range: number): (Victim?, number)
	local best, bestD = nil, range
	for _, v in ipairs(victims()) do
		local d = flatDist(v.root.Position, m.root.Position)
		if d < bestD then best, bestD = v, d end
	end
	return best, bestD
end

local function face(m: Mob, pos: Vector3)
	local flat = Vector3.new(pos.X, m.root.Position.Y, pos.Z)
	if (flat - m.root.Position).Magnitude > 0.1 then
		m.root.CFrame = CFrame.lookAt(m.root.Position, flat)
	end
end

local function halt(m: Mob)
	m.hum:Move(Vector3.zero)
	m.hum:MoveTo(m.root.Position)
	m.root.AssemblyLinearVelocity = Vector3.new(0, m.root.AssemblyLinearVelocity.Y, 0)
end

-- How hard this mob hits (its base damage, Threat, kind and elite).
local function power(m: Mob): number
	local base = m.model:GetAttribute("Damage")
	return (if typeof(base) == "number" then base else 10) * deps.damageScale() * (m.model:GetAttribute("DamageMult") or 1)
end

-- Hurt a player; a Vampiric elite drinks it back.
local function strike(m: Mob, char: Model, damage: number, from: Vector3?)
	local dealt = deps.hurt(char, damage, from, m.model)
	MobKinds.OnDealt(m.model, dealt)
end

-- Hurt every player within `radius` (flat) of `center`.
local function blast(m: Mob, center: Vector3, radius: number, damage: number, knock: boolean?)
	for _, v in ipairs(victims()) do
		if flatDist(v.root.Position, center) <= radius and math.abs(v.root.Position.Y - center.Y) < 8 then
			strike(m, v.char, damage, if knock == false then nil else center)
		end
	end
end

local function sightParams(m: Mob): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { m.model, fx() }
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	for _, v in ipairs(victims()) do table.insert(ignore, v.char) end
	params.FilterDescendantsInstances = ignore
	return params
end

-- Is there clear floor at `pos` and a clear path to it from `from`?
local function reachable(m: Mob, from: Vector3, pos: Vector3): boolean
	local params = sightParams(m)
	local a = Vector3.new(from.X, m.floorY + 2, from.Z)
	local b = Vector3.new(pos.X, m.floorY + 2, pos.Z)
	if Workspace:Raycast(a, b - a, params) then return false end
	local down = Workspace:Raycast(b + Vector3.new(0, 1, 0), Vector3.new(0, -6, 0), params)
	return down ~= nil
end

-- ── Poses (joint turns, in the parent part's space, about the joint) ───────
local function motors(model: Model): { [string]: Motor6D }
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") and d.Part1 then
			local n = d.Part1.Name
			if n == "Torso" then out.Root = d
			elseif n == "Head" then out.Neck = d
			elseif n == "Right Arm" then out.RightArm = d
			elseif n == "Left Arm" then out.LeftArm = d
			elseif n == "Right Leg" then out.RightLeg = d
			elseif n == "Left Leg" then out.LeftLeg = d
			end
		end
	end
	return out
end

local function turned(base: CFrame, rx: number, ry: number?, rz: number?): CFrame
	return CFrame.new(base.Position) * CFrame.Angles(math.rad(rx), math.rad(ry or 0), math.rad(rz or 0)) * base.Rotation
end

-- Ease joints to a pose: { Root = {rx, ry, rz}, ... } (degrees); nil = rest.
local function pose(m: Mob, p: { [string]: { number } }?, t: number)
	for name, motor in pairs(motors(m.model)) do
		local base = m.base[motor]
		if base then
			local a = p and p[name]
			local goal = if a then turned(base, a[1], a[2], a[3]) else base
			tween(motor, t, { C0 = goal })
		end
	end
end

-- Hunch a rig for good (the ghoul): becomes its resting pose.
local function setRest(m: Mob, p: { [string]: { number } })
	for name, motor in pairs(motors(m.model)) do
		local base = m.base[motor]
		local a = p[name]
		if base and a then
			m.base[motor] = turned(base, a[1], a[2], a[3])
			motor.C0 = m.base[motor]
		end
	end
end

-- Fade the visible body in or out (the wraith's blink).
local function fade(m: Mob, out: boolean, t: number)
	for _, d in ipairs(m.model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" then
			local rest = d:GetAttribute("RestTransparency")
			if rest == nil then
				rest = d.Transparency
				d:SetAttribute("RestTransparency", rest)
			end
			if rest < 1 then tween(d, t, { Transparency = if out then 1 else rest }) end
		elseif d:IsA("ParticleEmitter") or d:IsA("PointLight") or d:IsA("BillboardGui") then
			(d :: any).Enabled = not out
		end
	end
end

-- ── Moves ───────────────────────────────────────────────────────────────────
-- Each returns true if it went off (or started and was cut short), false if
-- now isn't the moment (the cooldown isn't spent).
local MOVES: { [string]: (Mob, Victim, number) -> boolean } = {}

-- Ghoul: crouch, then leap onto the spot you were standing on.
MOVES.pounce = function(m, v, d)
	if d < 9 or d > 26 then return false end
	local spot = Vector3.new(v.root.Position.X, m.floorY, v.root.Position.Z)
	if not reachable(m, m.root.Position, spot) then return false end
	local r = 4.2
	halt(m)
	face(m, spot)
	local tele = ring(spot, r, 0.6, m.floorY, BLOOD)
	pose(m, { Root = { -28 }, LeftLeg = { 28 }, RightLeg = { 28 }, LeftArm = { 40, 0, -20 }, RightArm = { 40, 0, 20 } }, 0.2)
	if not hold(m, 0.6, true) then
		cancel(tele)
		pose(m, nil, 0.2)
		return true
	end
	pose(m, { Root = { -10 }, LeftArm = { 150, 0, -25 }, RightArm = { 150, 0, 25 } }, 0.12)
	local from = m.root.Position
	local to = Vector3.new(spot.X, from.Y, spot.Z)
	local dir = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	local look = if dir.Magnitude > 0.1 then dir.Unit else m.root.CFrame.LookVector
	local dur = 0.42
	local t0 = os.clock()
	while alive(m) do
		local a = math.min((os.clock() - t0) / dur, 1)
		local pos = from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * 5.5, 0)
		m.root.CFrame = CFrame.lookAt(pos, pos + look)
		m.root.AssemblyLinearVelocity = Vector3.zero
		if a >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	if not alive(m) then return true end
	shock(spot, r, BLOOD, m.floorY)
	sparks(spot + Vector3.new(0, 0.5, 0), Color3.fromRGB(150, 130, 110), 14, 14)
	blast(m, spot, r, power(m) * 1.6)
	pose(m, { Root = { -20 }, LeftArm = { 60 }, RightArm = { 60 } }, 0.1)
	hold(m, 0.45)
	pose(m, nil, 0.25)
	return true
end

-- Brute: rear back, then charge down a lane, flattening anyone in it.
MOVES.charge = function(m, v, d)
	if d < 10 or d > 34 then return false end
	local dir = Vector3.new(v.root.Position.X - m.root.Position.X, 0, v.root.Position.Z - m.root.Position.Z)
	if dir.Magnitude < 1 then return false end
	dir = dir.Unit
	local length = math.clamp(d + 8, 14, 34)
	local hit = Workspace:Raycast(Vector3.new(m.root.Position.X, m.floorY + 2, m.root.Position.Z), dir * length, sightParams(m))
	if hit then length = hit.Distance - 3 end
	if length < 9 then return false end
	local width = 5.5
	halt(m)
	face(m, m.root.Position + dir)
	local tele = lane(m.root.Position, dir, length, width, 0.9, m.floorY, BLOOD)
	pose(m, { Root = { 14 }, RightArm = { 160, 0, 10 }, LeftArm = { 30, 0, -20 } }, 0.3)
	if not hold(m, 0.9) then
		cancel(tele)
		pose(m, nil, 0.2)
		return true
	end
	pose(m, { Root = { -22 }, RightArm = { 70 }, LeftArm = { 50 }, LeftLeg = { 22 }, RightLeg = { 22 } }, 0.1)
	local hitSet: { [Model]: boolean } = {}
	local start = m.root.Position
	local speed = 44
	local dur = length / speed
	local t0 = os.clock()
	local lastDust = 0
	while alive(m) do
		local a = math.min((os.clock() - t0) / dur, 1)
		local pos = start + dir * length * a
		m.root.CFrame = CFrame.lookAt(pos, pos + dir)
		m.root.AssemblyLinearVelocity = dir * speed
		for _, vv in ipairs(victims()) do
			if not hitSet[vv.char] and flatDist(vv.root.Position, m.root.Position) <= width / 2 + 1.5 then
				hitSet[vv.char] = true
				strike(m, vv.char, power(m) * 1.4, m.root.Position)
			end
		end
		if os.clock() - lastDust > 0.08 then
			lastDust = os.clock()
			smokePuff(Vector3.new(pos.X, m.floorY + 0.5, pos.Z), Color3.fromRGB(120, 110, 100), 2)
		end
		if a >= 1 then break end
		RunService.Heartbeat:Wait()
	end
	if not alive(m) then return true end
	m.root.AssemblyLinearVelocity = Vector3.zero
	shock(m.root.Position, 6, Color3.fromRGB(200, 180, 150), m.floorY)
	-- winded after the charge: a moment to punish it
	pose(m, { Root = { -12 }, RightArm = { 20 }, LeftArm = { 20 } }, 0.2)
	hold(m, 1.1)
	pose(m, nil, 0.3)
	return true
end

-- Bone Mage: raise the staff, and a hex ring opens under the target.
MOVES.hex = function(m, v, d)
	if d > 46 then return false end
	local spot = Vector3.new(v.root.Position.X, m.floorY, v.root.Position.Z)
	local r = 5
	halt(m)
	face(m, spot)
	pose(m, { RightArm = { 165, 0, 10 }, LeftArm = { 70, 0, -30 } }, 0.25)
	local orb = m.model:FindFirstChild("StaffOrb", true)
	local light = orb and orb:FindFirstChild("OrbLight")
	if light and light:IsA("PointLight") then tween(light, 1.1, { Brightness = 4, Range = 14 }) end
	local tele = ring(spot, r, 1.15, m.floorY, VIOLET)
	local ok = hold(m, 1.15, true)
	if light and light:IsA("PointLight") then tween(light, 0.3, { Brightness = 1.6, Range = 9 }) end
	if not ok then
		cancel(tele)
		pose(m, nil, 0.2)
		return true
	end
	pillar(spot, r, VIOLET, m.floorY)
	shock(spot, r, VIOLET, m.floorY)
	sparks(spot + Vector3.new(0, 1, 0), VIOLET, 18, 12)
	blast(m, spot, r, power(m) * 1.5, false)
	hold(m, 0.3)
	pose(m, nil, 0.3)
	return true
end

-- Wraith: vanish, come back behind the target, and slash.
MOVES.blink = function(m, v, d)
	if d < 6 or d > 40 then return false end
	-- behind them (or to a side if a wall is there)
	local back = -v.root.CFrame.LookVector
	back = Vector3.new(back.X, 0, back.Z)
	back = if back.Magnitude > 0.1 then back.Unit else Vector3.xAxis
	local spot: Vector3? = nil
	for _, turn in ipairs({ 0, 90, -90, 180 }) do
		local dir = CFrame.Angles(0, math.rad(turn), 0) * back
		local p = Vector3.new(v.root.Position.X, m.floorY, v.root.Position.Z) + dir * 4
		if reachable(m, v.root.Position, p) then
			spot = p
			break
		end
	end
	if not spot then return false end
	local at = spot :: Vector3
	local r = 4
	halt(m)
	smokePuff(m.root.Position, Color3.fromRGB(40, 30, 70), 10)
	fade(m, true, 0.25)
	local tele = ring(at, r, 0.75, m.floorY, CYAN)
	if not hold(m, 0.3) then
		cancel(tele)
		return true
	end
	-- (moved while unseen)
	local height = m.root.Position.Y - m.floorY
	m.root.CFrame = CFrame.lookAt(at + Vector3.new(0, height, 0), Vector3.new(v.root.Position.X, m.floorY + height, v.root.Position.Z))
	m.root.AssemblyLinearVelocity = Vector3.zero
	if not hold(m, 0.3) then
		fade(m, false, 0.1)
		return true
	end
	smokePuff(m.root.Position, Color3.fromRGB(40, 30, 70), 10)
	fade(m, false, 0.15)
	pose(m, { RightArm = { 160, 0, 30 }, LeftArm = { 160, 0, -30 } }, 0.15)
	if not hold(m, 0.15) then return true end
	pose(m, { Root = { -15 }, RightArm = { 40, 0, -20 }, LeftArm = { 40, 0, 20 } }, 0.08)
	sparks(at + Vector3.new(0, 2, 0), CYAN, 16, 16)
	shock(at, r, CYAN, m.floorY)
	blast(m, at, r, power(m) * 1.5)
	hold(m, 0.4)
	pose(m, { RightArm = { 70 }, LeftArm = { 70 } }, 0.25)
	return true
end

-- Magma Slime: right next to you it swells, glows white-hot, and bursts.
MOVES.fuse = function(m, v, d)
	if d > 7 then return false end
	local r = 8
	halt(m)
	m.root.Anchored = true
	local inner = select(1, slimeParts(m.model))
	local light = inner and inner:FindFirstChild("CoreLight")
	local tele = ring(m.root.Position - Vector3.new(0, m.root.Position.Y - m.floorY, 0), r, 1.1, m.floorY, EMBER)
	if inner then tween(inner, 1.1, { Color = Color3.fromRGB(255, 235, 170) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
	if light and light:IsA("PointLight") then tween(light, 1.1, { Brightness = 5, Range = 16 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In) end
	-- swelling in pulses
	local scale0 = m.model:GetScale()
	for i = 1, 4 do
		if not hold(m, 0.275) then
			cancel(tele)
			if alive(m) then m.root.Anchored = false end
			return true
		end
		pcall(function() m.model:ScaleTo(scale0 * (1 + i * 0.07)) end)
	end
	if not alive(m) then return true end
	local center = m.root.Position
	burst(center, r * 0.8, Color3.fromRGB(255, 170, 60))
	shock(center, r, EMBER, m.floorY)
	sparks(center, EMBER, 30, 26)
	smokePuff(center, Color3.fromRGB(60, 40, 30), 12)
	blast(m, center, r, power(m) * 2.4)
	m.model:SetAttribute("Detonated", true)
	m.model:SetAttribute("XPMult", 0)
	m.hum.Health = 0
	return true
end

-- Necromancer: green rings open near it and the dead climb out.
MOVES.raise = function(m, v, d)
	for i = #m.minions, 1, -1 do
		local mm = m.minions[i]
		local h = mm:FindFirstChildOfClass("Humanoid")
		if not mm.Parent or not h or h.Health <= 0 then table.remove(m.minions, i) end
	end
	if #m.minions >= 3 then return false end
	local toward = Vector3.new(v.root.Position.X - m.root.Position.X, 0, v.root.Position.Z - m.root.Position.Z)
	toward = if toward.Magnitude > 0.1 then toward.Unit else m.root.CFrame.LookVector
	local spots = {}
	for _, turn in ipairs({ 35, -35 }) do
		local p = Vector3.new(m.root.Position.X, m.floorY, m.root.Position.Z) + (CFrame.Angles(0, math.rad(turn), 0) * toward) * 6
		if reachable(m, m.root.Position, p) then table.insert(spots, p) end
	end
	if #spots == 0 then return false end
	halt(m)
	face(m, v.root.Position)
	pose(m, { RightArm = { 165, 0, 10 }, LeftArm = { 120, 0, -40 } }, 0.3)
	local teles = {}
	for _, p in ipairs(spots) do
		for _, part0 in ipairs(ring(p, 2.4, 1.2, m.floorY, SOUL)) do table.insert(teles, part0) end
	end
	if not hold(m, 1.2, true) then
		cancel(teles)
		pose(m, nil, 0.2)
		return true
	end
	for _, p in ipairs(spots) do
		local mm = deps.spawnKind("risen", CFrame.lookAt(p, p + toward), m.model)
		if mm then table.insert(m.minions, mm) end
	end
	hold(m, 0.3)
	pose(m, nil, 0.3)
	return true
end

-- Necromancer: a slow soul bolt thrown at the target.
MOVES.bolt = function(m, v, d)
	if d > 44 then return false end
	halt(m)
	face(m, v.root.Position)
	pose(m, { RightArm = { 110, 0, 0 } }, 0.15)
	if not hold(m, 0.35, true) then
		pose(m, nil, 0.2)
		return true
	end
	local from = m.root.Position + m.root.CFrame.LookVector * 2 + Vector3.new(0, 1.2, 0)
	local aim = Vector3.new(v.root.Position.X, from.Y, v.root.Position.Z)
	local dir = (aim - from)
	dir = if dir.Magnitude > 0.1 then dir.Unit else m.root.CFrame.LookVector
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = CFrame.new(from), Color = SOUL })
	ball:AddTag("EnemyProjectile")
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = SOUL, 8, 2
	light.Parent = ball
	local trail = Instance.new("ParticleEmitter")
	trail.Texture = "rbxasset://textures/particles/smoke_main.dds"
	trail.Color = ColorSequence.new(SOUL, Color3.fromRGB(20, 60, 30))
	trail.LightEmission = 0.8
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0.2) })
	trail.Lifetime = NumberRange.new(0.3, 0.5)
	trail.Speed = NumberRange.new(0, 0.5)
	trail.Rate = 40
	trail.Parent = ball
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { m.model, fx() }
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local damage = power(m) * 1.2
	local speed = 30
	local owner = m
	task.spawn(function()
		local t0 = os.clock()
		local last = t0
		while ball.Parent and os.clock() - t0 < 3 do
			RunService.Heartbeat:Wait()
			local now = os.clock()
			local step = speed * math.min(now - last, 0.1)
			last = now
			local hitRes = Workspace:Raycast(ball.Position, dir * step, params)
			-- (a near miss still counts: it's a big ball)
			local struck: Victim? = nil
			for _, vv in ipairs(victims()) do
				if (vv.root.Position - ball.Position).Magnitude <= 2 then struck = vv end
			end
			if struck then
				strike(owner, struck.char, damage, ball.Position)
				break
			elseif hitRes then
				local char = hitRes.Instance:FindFirstAncestorOfClass("Model")
				if char and Players:GetPlayerFromCharacter(char) then strike(owner, char, damage, ball.Position) end
				break
			end
			ball.CFrame = CFrame.new(ball.Position + dir * step)
		end
		if ball.Parent then
			burst(ball.Position, 2.5, SOUL)
			ball:Destroy()
		end
	end)
	hold(m, 0.25)
	pose(m, nil, 0.25)
	return true
end

-- ── Elite traits at work ────────────────────────────────────────────────────
local function addTraitLook(m: Mob, affixId: string)
	local affix = AFFIXES[affixId]
	if not affix then return end
	local att = Instance.new("Attachment")
	att.Name = "TraitAura"
	att.Parent = m.root
	local e = Instance.new("ParticleEmitter")
	e.Name = "TraitAura"
	e.LightEmission = 1
	e.Rate = 0
	if affixId == "frenzied" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), affix.color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.25, 0.45)
		e.Speed = NumberRange.new(6, 10)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 18
	elseif affixId == "vampiric" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(affix.color, Color3.fromRGB(90, 0, 20))
		e.LightEmission = 0.4
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0.1) })
		e.Lifetime = NumberRange.new(0.6, 1)
		e.Speed = NumberRange.new(0.5, 1.5)
		e.Acceleration = Vector3.new(0, -8, 0)
		e.SpreadAngle = Vector2.new(60, 60)
		e.Rate = 10
	elseif affixId == "volatile" then
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 230, 150), affix.color)
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(0.2, 0.4)
		e.Speed = NumberRange.new(3, 7)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Rate = 14
		local light = Instance.new("PointLight")
		light.Name = "VolatileGlow"
		light.Color = affix.color
		light.Range = 8
		light.Brightness = 1
		light.Parent = m.root
		TweenService:Create(light, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Brightness = 3.5 }):Play()
	elseif affixId == "blazing" then
		local fire = Instance.new("Fire")
		fire.Color = affix.color
		fire.SecondaryColor = Color3.fromRGB(255, 200, 60)
		fire.Size = 5
		fire.Heat = 9
		fire.Parent = m.root
	end
	e.Parent = att
end

-- Burning ground left behind a Blazing elite.
local function burnPatch(m: Mob, at: Vector3)
	local r = 2.6
	local pos = Vector3.new(at.X, m.floorY + 0.08, at.Z)
	local patch = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, r * 2, r * 2), CFrame = CFrame.new(pos) * FLAT,
		Color = Color3.fromRGB(255, 96, 20), Material = Enum.Material.CrackedLava, Transparency = 0.25 })
	local flames = Instance.new("ParticleEmitter")
	flames.Texture = "rbxasset://textures/particles/fire_main.dds"
	flames.Color = ColorSequence.new(Color3.fromRGB(255, 200, 80), Color3.fromRGB(255, 80, 20))
	flames.LightEmission = 1
	flames.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 0) })
	flames.Lifetime = NumberRange.new(0.4, 0.7)
	flames.Speed = NumberRange.new(2, 4)
	flames.EmissionDirection = Enum.NormalId.Right
	flames.Shape = Enum.ParticleEmitterShape.Cylinder
	flames.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	flames.Rate = 16
	flames.Parent = patch
	local damage = power(m) * 0.35
	local owner = m
	local life = 3.5
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < life and patch.Parent do
			task.wait(0.5)
			for _, v in ipairs(victims()) do
				if flatDist(v.root.Position, pos) <= r and math.abs(v.root.Position.Y - pos.Y) < 5 then
					strike(owner, v.char, damage, nil)
				end
			end
		end
		flames.Rate = 0
		tween(patch, 0.5, { Transparency = 1 })
		Debris:AddItem(patch, 0.6)
	end)
end

-- A Vampiric elite heals for the damage it lands (twice over).
function MobKinds.OnDealt(model: Model?, amount: number)
	if not model or amount <= 0 or model:GetAttribute("Affix") ~= "vampiric" then return end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or hum.Health <= 0 then return end
	hum.Health = math.min(hum.MaxHealth, hum.Health + amount * 2)
	if root then sparks(root.Position + Vector3.new(0, 1, 0), AFFIXES.vampiric.color, 10, 6) end
end

-- What a mob does as it dies (a bloat splitting, a volatile elite going off).
-- Called before the room counts it as dead, so slimelings keep it open.
function MobKinds.OnDied(model: Model, pos: Vector3)
	local kindId = model:GetAttribute("MobKind")
	local floorY = model:GetAttribute("FloorY")
	local fy = if typeof(floorY) == "number" then floorY else pos.Y - 2
	if kindId == "bloatslime" then
		sparks(pos, Color3.fromRGB(170, 235, 90), 20, 14)
		smokePuff(pos, Color3.fromRGB(110, 160, 60), 8)
		for i = 1, 3 do
			local a = (i / 3) * math.pi * 2
			local at = Vector3.new(pos.X + math.cos(a) * 2.5, fy, pos.Z + math.sin(a) * 2.5)
			deps.spawnKind("slimeling", CFrame.new(at) * CFrame.Angles(0, a, 0), model)
		end
	end
	if model:GetAttribute("Affix") == "volatile" then
		local base = model:GetAttribute("Damage")
		local damage = (if typeof(base) == "number" then base else 10) * deps.damageScale() * 2.2
		local center = Vector3.new(pos.X, fy, pos.Z)
		local r = 9
		ring(center, r, 1.2, fy, AFFIXES.volatile.color)
		task.delay(1.2, function()
			burst(center + Vector3.new(0, 1.5, 0), r * 0.8, Color3.fromRGB(255, 170, 60))
			shock(center, r, AFFIXES.volatile.color, fy)
			sparks(center + Vector3.new(0, 1, 0), AFFIXES.volatile.color, 26, 24)
			for _, v in ipairs(victims()) do
				if flatDist(v.root.Position, center) <= r and math.abs(v.root.Position.Y - fy) < 8 then
					deps.hurt(v.char, damage, center, nil)
				end
			end
		end)
	end
end

-- ── The loop ────────────────────────────────────────────────────────────────
-- The dead climbing out of the floor.
local function rise(m: Mob)
	m.model:SetAttribute("MobBusy", true)
	local root = m.root
	local up = root.CFrame
	root.Anchored = true
	root.CFrame = up - Vector3.new(0, 5, 0)
	smokePuff(Vector3.new(up.Position.X, m.floorY + 0.5, up.Position.Z), Color3.fromRGB(60, 90, 60), 10)
	sparks(Vector3.new(up.Position.X, m.floorY + 0.5, up.Position.Z), SOUL, 14, 8)
	tween(root, 0.8, { CFrame = up }, Enum.EasingStyle.Quad)
	task.wait(0.85)
	if root.Parent then
		root.Anchored = false
		pcall(function() root:SetNetworkOwner(nil) end)
	end
	m.model:SetAttribute("Rising", nil)
	m.model:SetAttribute("MobBusy", false)
end

-- Start a configured mob's moves (and its elite trait).
function MobKinds.Attach(model: Model, kindId: string)
	local kind = kinds[kindId]
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not kind or not hum or not root then return end
	local floorY = model:GetAttribute("FloorY")
	local m: Mob = {
		model = model, hum = hum, root = root, kind = kind, id = kindId,
		floorY = if typeof(floorY) == "number" then floorY else root.Position.Y - 3,
		base = {}, minions = {}, nextMove = {},
	}
	for _, motor in pairs(motors(model)) do m.base[motor] = motor.C0 end
	if kindId == "ghoul" then
		setRest(m, { Root = { -14 }, LeftLeg = { 14 }, RightLeg = { 14 }, Neck = { 16 } })
	elseif kindId == "wraith" then
		setRest(m, { RightArm = { 70, 0, 8 }, LeftArm = { 70, 0, -8 }, Neck = { -6 } })
	end
	local affixId = model:GetAttribute("Affix")
	if typeof(affixId) == "string" then addTraitLook(m, affixId) end
	if model:GetAttribute("Rising") == true then task.spawn(rise, m) end

	local slots = kind.moves or {}
	local cdMult = model:GetAttribute("CooldownMult")
	local mult = if typeof(cdMult) == "number" then cdMult else 1
	for _, slot in ipairs(slots) do
		-- (not all at once when a room wakes up)
		m.nextMove[slot.id] = os.clock() + 1 + math.random() * 2
	end
	local blazing = affixId == "blazing"
	if #slots == 0 and not blazing then return end
	task.spawn(function()
		local lastPatch = root.Position
		local lastPatchAt = 0
		while alive(m) do
			task.wait(0.2)
			if not alive(m) then break end
			if blazing and os.clock() - lastPatchAt > 0.6 and flatDist(root.Position, lastPatch) > 3 then
				lastPatchAt = os.clock()
				lastPatch = root.Position
				burnPatch(m, root.Position)
			end
			if model:GetAttribute("MobBusy") == true or not deps.canAct(model) or staggered(m) then continue end
			local v, d = nearest(m, 70)
			if not v then continue end
			for _, slot in ipairs(slots) do
				if os.clock() >= (m.nextMove[slot.id] or 0) then
					model:SetAttribute("MobBusy", true)
					local ok, fired = pcall(MOVES[slot.id], m, v, d)
					if not ok then warn(`[MobKinds] {slot.id}: {fired}`) end
					if model.Parent then model:SetAttribute("MobBusy", false) end
					if ok and fired then
						local lo, hi = slot.every[1], slot.every[2]
						m.nextMove[slot.id] = os.clock() + (lo + math.random() * (hi - lo)) * mult
						-- (a breath before its next move)
						for _, other in ipairs(slots) do
							m.nextMove[other.id] = math.max(m.nextMove[other.id] or 0, os.clock() + 0.8)
						end
						break
					end
				end
			end
		end
	end)
end

function MobKinds.Init(d: Deps)
	deps = d
end

return MobKinds
