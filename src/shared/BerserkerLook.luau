--!strict
--[[
	BerserkerLook.luau
	The Berserker's look, built from parts (no uploaded assets), black metal
	and deep crimson only:

	  BuildGreatsword()  his greatsword, "Ragebringer", built from parts: black
	                     stone-iron, crimson cracks, a red-wrapped grip.
	  Dress(char)        chunky black plate on an R6 body: a horned helmet with
	                     glowing crimson eyes, huge spiked pauldrons, layered
	                     chest plate with crimson cracks, gauntlets, heavy
	                     boots and a ragged cloth skirt / cape.
	  Undress(char)      remove it again.

	Used by the server (the real character, seen by everyone) and the menus.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BerserkerLook = {}

local BLACK = Color3.fromRGB(26, 22, 26)
local IRON = Color3.fromRGB(46, 40, 46)
local CRIMSON = Color3.fromRGB(190, 12, 26)
local CRIMSON_DARK = Color3.fromRGB(90, 8, 16)
local CLOTH = Color3.fromRGB(58, 10, 16)
local TAG = "BerserkerArmor"

-- ── The greatsword ──────────────────────────────────────────────────────────
-- "A remnant of rage", built from parts to the design sheet: a long, broad
-- slab of black stone-iron, its edges chipped, a chisel point, glowing
-- crimson cracks running through both faces; a stepped block crossguard; a
-- grip wound with blood-red cloth, torn strips of it hanging loose; a heavy
-- faceted pommel.
--
-- Handle space: the blade runs down -Y from the guard, the pommel up +Y; the
-- Grip holds it at the wrapped grip, so it sits in his fist the same way at
-- any SWORD_SCALE (three-quarters of the old asset's size). The blade is the
-- biggest piece, so the swing trail finds it (RageBase / RageTip).
local SWORD_STONE = Color3.fromRGB(44, 36, 36)
local SWORD_EDGE = Color3.fromRGB(78, 66, 64)
local SWORD_IRON = Color3.fromRGB(58, 50, 50)
local SWORD_WRAP = Color3.fromRGB(96, 16, 22)
local SWORD_GRIP = Color3.fromRGB(30, 22, 22)
local SWORD_CRACK = Color3.fromRGB(235, 28, 36)
-- The whole sword is laid out at full size below, then built at this scale.
local SWORD_SCALE = 0.75

function BerserkerLook.BuildGreatsword(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Ragebringer"
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, 3.9 * SWORD_SCALE, -0.49) * CFrame.Angles(math.pi, 0, 0)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1.8, 0.4) * SWORD_SCALE
	handle.Transparency = 1
	handle.CanCollide, handle.CanTouch, handle.CanQuery, handle.Massless = false, false, false, true
	handle.Parent = tool

	-- A piece at `cf` (handle space, the handle sitting at the origin), welded on.
	local function piece(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, class: string?): BasePart
		local q = Instance.new(class or "Part") :: BasePart
		q.Name = name
		q.Size = size * SWORD_SCALE
		q.CFrame = CFrame.new(cf.Position * SWORD_SCALE) * cf.Rotation
		q.Color = color
		q.Material = material or Enum.Material.Slate
		q.CanCollide, q.CanTouch, q.CanQuery, q.Massless = false, false, false, true
		q.TopSurface, q.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = handle, q
		w.Parent = q
		q.Parent = tool
		return q
	end
	-- A glowing crack along the polyline `pts` (X across, Y along), on the
	-- face at depth `z`.
	local function crack(pts: { Vector2 }, z: number, width: number)
		for i = 1, #pts - 1 do
			local a, b = Vector3.new(pts[i].X, pts[i].Y, z), Vector3.new(pts[i + 1].X, pts[i + 1].Y, z)
			local d = b - a
			-- (length along the crack, flat on the face: "up" is the face's normal)
			local cf = CFrame.lookAt((a + b) / 2, (a + b) / 2 + d, Vector3.zAxis)
			piece("Crack", Vector3.new(width, 0.02, d.Magnitude + width * 0.6), cf, SWORD_CRACK, Enum.Material.Neon)
		end
	end

	local TOP, BOTTOM = 2.45, -4.2 -- the blade's straight run (the point below)
	local W, T = 1.55, 0.32
	local len = TOP - BOTTOM
	-- The blade: a thick slab, lighter bevelled edges, a raised spine.
	local blade = piece("Blade", Vector3.new(W, len, T), CFrame.new(0, (TOP + BOTTOM) / 2, 0), SWORD_STONE)
	for _, side in ipairs({ -1, 1 }) do
		piece("BladeEdge", Vector3.new(0.2, len - 0.15, T * 0.62), CFrame.new(side * (W / 2 + 0.06), (TOP + BOTTOM) / 2 - 0.07, 0), SWORD_EDGE)
		-- chips knocked out of the edges
		for i, y in ipairs({ 1.6, 0.2, -1.1, -2.6, -3.5 }) do
			if (i + (if side > 0 then 1 else 0)) % 2 == 0 then
				piece("Chip", Vector3.new(0.3, 0.3, T + 0.04), CFrame.new(side * (W / 2 + 0.12), y, 0) * CFrame.Angles(0, 0, math.rad(45)), SWORD_STONE)
			end
		end
	end
	piece("Spine", Vector3.new(0.34, len - 0.5, T + 0.08), CFrame.new(-0.1, (TOP + BOTTOM) / 2 + 0.1, 0), SWORD_IRON, Enum.Material.Basalt)
	-- The chisel point: a wedge, the long cut on one side.
	local tipLen = 1.6
	piece("BladePoint", Vector3.new(T, tipLen, W + 0.4), CFrame.new(0, BOTTOM - tipLen / 2, 0) * CFrame.Angles(0, math.rad(90), 0) * CFrame.Angles(0, 0, math.pi),
		SWORD_STONE, Enum.Material.Slate, "WedgePart")
	-- Crimson cracks through both faces: a vein down the middle that forks.
	-- (out past the raised spine, so it never hides them)
	for _, z in ipairs({ T / 2 + 0.06, -(T / 2 + 0.06) }) do
		crack({ Vector2.new(0.05, 2.2), Vector2.new(0.18, 1.3), Vector2.new(-0.05, 0.5), Vector2.new(0.12, -0.6),
			Vector2.new(-0.1, -1.7), Vector2.new(0.08, -2.8), Vector2.new(-0.15, -3.9), Vector2.new(0.05, -4.9) }, z, 0.07)
		crack({ Vector2.new(0.18, 1.3), Vector2.new(0.45, 0.9), Vector2.new(0.62, 0.3) }, z, 0.05)
		crack({ Vector2.new(0.12, -0.6), Vector2.new(-0.3, -1.0), Vector2.new(-0.55, -1.6) }, z, 0.05)
		crack({ Vector2.new(-0.1, -1.7), Vector2.new(0.35, -2.3), Vector2.new(0.5, -3.0) }, z, 0.05)
		crack({ Vector2.new(-0.15, -3.9), Vector2.new(-0.45, -4.4) }, z, 0.04)
	end

	-- The crossguard: a heavy block bar with a smaller block stacked on it.
	piece("Guard", Vector3.new(2.2, 0.42, 0.78), CFrame.new(0, 2.66, 0), SWORD_IRON, Enum.Material.Slate)
	piece("GuardCap", Vector3.new(1.5, 0.28, 0.6), CFrame.new(0, 2.98, 0), SWORD_EDGE, Enum.Material.Slate)
	for _, side in ipairs({ -1, 1 }) do
		piece("GuardEnd", Vector3.new(0.34, 0.56, 0.86), CFrame.new(side * 1.1, 2.66, 0), SWORD_STONE, Enum.Material.Slate)
	end

	-- The grip, wound with red cloth.
	piece("Grip", Vector3.new(0.36, 1.95, 0.36), CFrame.new(0, 4.05, 0), SWORD_GRIP, Enum.Material.Fabric)
	for i = 0, 5 do
		piece("Wrap", Vector3.new(0.42, 0.13, 0.42), CFrame.new(0, 3.25 + i * 0.32, 0) * CFrame.Angles(0, 0, math.rad(if i % 2 == 0 then 18 else -18)),
			SWORD_WRAP, Enum.Material.Fabric)
	end
	-- The pommel: a faceted block on a neck.
	piece("PommelNeck", Vector3.new(0.44, 0.24, 0.44), CFrame.new(0, 5.1, 0), SWORD_IRON, Enum.Material.Slate)
	piece("Pommel", Vector3.new(0.62, 0.58, 0.62), CFrame.new(0, 5.48, 0) * CFrame.Angles(0, math.rad(45), 0), SWORD_STONE, Enum.Material.Slate)
	piece("PommelCap", Vector3.new(0.4, 0.22, 0.4), CFrame.new(0, 5.86, 0) * CFrame.Angles(0, math.rad(45), 0), SWORD_EDGE, Enum.Material.Slate)

	-- Torn strips of the red wrap hanging loose off the grip, frayed at the ends.
	for i, st in ipairs({ { x = 0.3, y = 3.5, len = 3.0, rz = 22 }, { x = 0.36, y = 3.8, len = 2.3, rz = 34 }, { x = 0.24, y = 3.3, len = 1.7, rz = 12 } }) do
		local top = CFrame.new(st.x, st.y, 0.24) * CFrame.Angles(0, 0, math.rad(st.rz))
		piece("Tatter", Vector3.new(0.2 - i * 0.03, st.len, 0.03), top * CFrame.new(0, -st.len / 2, 0), SWORD_WRAP, Enum.Material.Fabric)
		piece("TatterEnd", Vector3.new(0.03, 0.4, 0.14), top * CFrame.new(0.02, -st.len - 0.15, 0) * CFrame.Angles(0, math.rad(90), math.rad(8)),
			SWORD_WRAP, Enum.Material.Fabric, "WedgePart")
	end

	-- Invisible attachments at both ends of the blade for the client's swing
	-- trail (the trail only shows while swinging): base at the guard, tip
	-- toward the point.
	local a0 = Instance.new("Attachment")
	a0.Name = "RageBase"
	a0.Position = Vector3.new(0, len / 2 - 0.3, 0) * SWORD_SCALE
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "RageTip"
	a1.Position = Vector3.new(0, -len / 2 - tipLen * 0.6, 0) * SWORD_SCALE
	a1.Parent = blade
	return tool
end

-- ── The armour ──────────────────────────────────────────────────────────────
local function plate(parent: BasePart, name: string, shape: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p: BasePart
	if shape == "wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "corner" then
		p = Instance.new("CornerWedgePart")
	else
		p = Instance.new("Part")
	end
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Metal
	p.CanCollide, p.CanQuery, p.CanTouch, p.Massless = false, false, false, true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = parent.CFrame * offset
	p:AddTag(TAG)
	local w = Instance.new("WeldConstraint")
	w.Part0 = parent
	w.Part1 = p
	w.Parent = p
	p.Parent = parent.Parent
	return p
end

local R = math.rad

function BerserkerLook.Undress(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:HasTag(TAG) then d:Destroy() end
	end
end

function BerserkerLook.Dress(char: Model)
	BerserkerLook.Undress(char)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not (head and torso) then return end
	-- Hide the face and hair under the helm.
	for _, a in ipairs(char:GetChildren()) do
		if a:IsA("Accessory") then
			local h = a:FindFirstChild("Handle")
			-- (all of them: anything the avatar wears pokes through the plate)
			if h and h:IsA("BasePart") then
				h.Transparency = 1
				h:SetAttribute("BerserkerHid", true)
			end
		end
	end
	local face = head:FindFirstChildOfClass("Decal")
	if face then face.Transparency = 1 end

	-- The horned helm, eye-slit glowing crimson.
	plate(head, "Helm", "block", Vector3.new(1.35, 1.3, 1.35), CFrame.new(0, 0.05, 0), BLACK)
	plate(head, "HelmCrest", "wedge", Vector3.new(0.3, 0.5, 1.4), CFrame.new(0, 0.85, 0.05), IRON)
	plate(head, "Visor", "block", Vector3.new(1.4, 0.18, 0.2), CFrame.new(0, 0.12, -0.62), CRIMSON, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		-- great horns sweeping out and up
		plate(head, "Horn", "corner", Vector3.new(0.45, 1.2, 0.45), CFrame.new(sx * 0.95, 0.55, 0.1) * CFrame.Angles(0, 0, R(sx * -35)), IRON)
		plate(head, "Horn", "corner", Vector3.new(0.3, 1, 0.3), CFrame.new(sx * 1.35, 1.2, 0.1) * CFrame.Angles(0, 0, R(sx * -10)), BLACK)
		plate(head, "Cheek", "wedge", Vector3.new(0.2, 0.6, 0.7), CFrame.new(sx * 0.62, -0.35, -0.35) * CFrame.Angles(0, math.pi, 0), IRON)
	end

	-- Chest: layered plates with crimson cracks.
	plate(torso, "Chest", "block", Vector3.new(2.15, 2.05, 1.2), CFrame.new(0, 0.05, 0), BLACK)
	plate(torso, "ChestPlate", "block", Vector3.new(1.7, 1.1, 0.25), CFrame.new(0, 0.35, -0.65), IRON)
	plate(torso, "Crack", "block", Vector3.new(0.08, 0.9, 0.05), CFrame.new(-0.3, 0.3, -0.79) * CFrame.Angles(0, 0, R(18)), CRIMSON, Enum.Material.Neon)
	plate(torso, "Crack", "block", Vector3.new(0.07, 0.6, 0.05), CFrame.new(0.35, 0.1, -0.79) * CFrame.Angles(0, 0, R(-25)), CRIMSON, Enum.Material.Neon)
	plate(torso, "Belt", "block", Vector3.new(2.2, 0.35, 1.25), CFrame.new(0, -0.85, 0), CRIMSON_DARK)
	-- A ragged cloth skirt and cape.
	for i = -2, 2 do
		plate(torso, "Rag", "wedge", Vector3.new(0.4, 0.9 + (i % 2) * 0.3, 0.06), CFrame.new(i * 0.42, -1.45, -0.58) * CFrame.Angles(0, 0, math.pi), CLOTH, Enum.Material.Fabric)
	end
	plate(torso, "Cape", "block", Vector3.new(1.9, 2.6, 0.08), CFrame.new(0, -0.5, 0.66) * CFrame.Angles(R(-6), 0, 0), CLOTH, Enum.Material.Fabric)
	for i = -2, 2 do
		plate(torso, "CapeRag", "wedge", Vector3.new(0.38, 0.7 + (i % 2) * 0.4, 0.06), CFrame.new(i * 0.38, -2.1, 0.8) * CFrame.Angles(0, 0, math.pi), CLOTH, Enum.Material.Fabric)
	end

	-- Arms: huge spiked pauldrons, gauntlets.
	for _, side in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = char:FindFirstChild(side) :: BasePart?
		if arm then
			local sx = if side == "Left Arm" then -1 else 1
			plate(arm, "Pauldron", "block", Vector3.new(1.55, 0.7, 1.45), CFrame.new(sx * 0.1, 0.9, 0) * CFrame.Angles(0, 0, R(sx * -12)), BLACK)
			plate(arm, "PauldronTop", "block", Vector3.new(1.3, 0.35, 1.25), CFrame.new(sx * 0.15, 1.3, 0) * CFrame.Angles(0, 0, R(sx * -18)), IRON)
			for k = -1, 1 do
				plate(arm, "Spike", "corner", Vector3.new(0.3, 0.8 - math.abs(k) * 0.2, 0.3), CFrame.new(sx * 0.35, 1.7, k * 0.4) * CFrame.Angles(0, 0, R(sx * -20)), CRIMSON_DARK)
			end
			plate(arm, "Gauntlet", "block", Vector3.new(1.15, 0.9, 1.15), CFrame.new(0, -0.6, 0), BLACK)
			plate(arm, "GauntletRim", "block", Vector3.new(1.2, 0.12, 1.2), CFrame.new(0, -0.12, 0), CRIMSON, Enum.Material.Neon)
		end
	end
	-- Legs: heavy boots.
	for _, side in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = char:FindFirstChild(side) :: BasePart?
		if leg then
			plate(leg, "Greave", "block", Vector3.new(1.12, 1.1, 1.15), CFrame.new(0, -0.45, 0), BLACK)
			plate(leg, "Boot", "block", Vector3.new(1.2, 0.5, 1.35), CFrame.new(0, -0.8, -0.1), IRON)
			plate(leg, "Knee", "wedge", Vector3.new(0.9, 0.45, 0.3), CFrame.new(0, 0.1, -0.6), IRON)
		end
	end

	-- A faint crimson glow and embers of rage.
	local ember = Instance.new("ParticleEmitter")
	ember.Name = "RageEmbers"
	ember.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	ember.Color = ColorSequence.new(CRIMSON)
	ember.LightEmission = 1
	ember.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 0) })
	ember.Lifetime = NumberRange.new(0.8, 1.4)
	ember.Speed = NumberRange.new(1, 3)
	ember.SpreadAngle = Vector2.new(60, 60)
	ember.Acceleration = Vector3.new(0, 4, 0)
	ember.Rate = 4
	ember:AddTag(TAG)
	ember.Parent = torso
end

-- ── The beast (Beast Awakening) ─────────────────────────────────────────────
-- After the design sheet: a wolf the size of a horse, hewn out of black
-- stone. Slabs of rock for a body, split by glowing red cracks; a mane of
-- jagged shards round the neck, a ridge of them down the back and on along
-- the long tail; boulders for shoulders; long jointed front legs ending in
-- great black claws; digitigrade hind legs; a wolf's head with slit red eyes,
-- the jaw hanging open on a red glow. Built in R6 units over his body (the
-- man, his armour and whatever he wears all hidden, and back with
-- UndressBeast), before the server scales the whole character up
-- (BerserkerServer).
--
-- (Space: on all fours the torso lies along the body, so the torso's +Y runs
-- toward the head, -Y toward the tail, and its back, +Z, faces up.)
local BEAST_TAG = "BerserkerBeast"
local HIDE_FLAG = "BeastHidden"
-- (the armour's flat plate cape stays as it is: clients hide it under the cloth one)
local KEEP = { HumanoidRootPart = true, Cape = true, CapeRag = true }
local STONE = Color3.fromRGB(36, 30, 34)
local STONE_DARK = Color3.fromRGB(22, 18, 21)
local STONE_EDGE = Color3.fromRGB(54, 46, 50)
local CLAW_BLACK = Color3.fromRGB(14, 11, 13)
local CRACK = Color3.fromRGB(255, 34, 44)
local MAW = Color3.fromRGB(190, 14, 26)
local BONE = Color3.fromRGB(196, 180, 166)
local SLATE = Enum.Material.Slate

local function beastPart(parent: BasePart, name: string, shape: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = plate(parent, name, shape, size, offset, color, material or SLATE)
	p:RemoveTag(TAG)
	p:AddTag(BEAST_TAG)
	-- (only the big slabs cast shadows)
	p.CastShadow = size.X * size.Y * size.Z > 1.5
	return p
end

-- A jagged shard of stone growing out of the surface at `at` (parent-local)
-- along `n`, its point raked toward `rake`: `w` across the base, `h` tall. (A
-- corner wedge: its point stands over one corner of its base, so it leans.)
local function shard(parent: BasePart, at: Vector3, n: Vector3, rake: Vector3, w: number, h: number, color: Color3?): BasePart
	n = n.Unit
	local t = rake - n * rake:Dot(n)
	if t.Magnitude < 1e-3 then
		t = n:Cross(if math.abs(n.X) < 0.9 then Vector3.xAxis else Vector3.zAxis)
	end
	t = t.Unit
	local u = t:Cross(n)
	local k = math.sqrt(0.5)
	-- (the point sits over the base's +X -Z corner: turn that diagonal onto t)
	local cf = CFrame.fromMatrix(at + n * (h * 0.38), (t + u) * k, n, (u - t) * k)
	return beastPart(parent, "Shard", "corner", Vector3.new(w, h, w), cf, color or STONE_DARK)
end

-- A glowing crack along the polyline `pts` (parent-local), lying on a face
-- whose outward normal is `nrm`.
local function crack(parent: BasePart, pts: { Vector3 }, nrm: Vector3, width: number?)
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local mid = (a + b) / 2 + nrm.Unit * 0.012
		beastPart(parent, "BeastCrack", "block", Vector3.new(width or 0.07, 0.04, (b - a).Magnitude + 0.05),
			CFrame.lookAt(mid, mid + (b - a), nrm), CRACK, Enum.Material.Neon)
	end
end

local function slab(parent: BasePart, size: Vector3, cf: CFrame, color: Color3): BasePart
	return beastPart(parent, "Slab", "block", size, cf, color)
end

-- The beast's limb joints (R6 units, in the limb's own space): the knee and
-- the elbow, where the client bends the lower limb (mirrored in
-- BerserkerController's leg and arm lengths).
local LEG_KNEE = Vector3.new(0, -0.7, 0)
local ARM_ELBOW = Vector3.new(0, -0.9, 0)

-- A hidden bone hung off `parent` at `at` (parent-local) on a Motor6D named
-- `joint`, for the limb pieces below the joint.
local function beastBone(char: Model, parent: BasePart, name: string, joint: string, at: Vector3): BasePart
	local bone = Instance.new("Part")
	bone.Name = name
	bone.Size = Vector3.one * 0.2
	bone.Transparency = 1
	bone.CanCollide, bone.CanQuery, bone.CanTouch, bone.Massless, bone.CastShadow = false, false, false, true, false
	bone.CFrame = parent.CFrame * CFrame.new(at)
	bone:AddTag(BEAST_TAG)
	local m = Instance.new("Motor6D")
	m.Name = joint
	m.Part0 = parent
	m.Part1 = bone
	m.C0 = CFrame.new(at)
	m.Parent = bone
	bone.Parent = char
	return bone
end

-- A block from a to b (parent-local), w × d across.
local function limbSeg(parent: BasePart, name: string, a: Vector3, b: Vector3, w: number, d: number, color: Color3): BasePart
	local len = (b - a).Magnitude
	return beastPart(parent, name, "block", Vector3.new(w, len, d),
		CFrame.lookAt((a + b) / 2, b, Vector3.xAxis) * CFrame.Angles(math.rad(-90), 0, 0), color)
end

-- The beast's longer frame: on a man the shoulders and hips are only 1.5
-- apart, so the shoulders (and the neck with them) are brought forward along
-- the body, the hips back, and both set a little wider (R6 units, torso
-- space; mirrored in BerserkerController's gait, which reads the real joints).
local BODY_FRONT = 0.9
local BODY_BACK = 1.0
local JOINT_FLAG = "BeastJointC0" -- (each moved joint's own C0, to put back)
local BEAST_JOINTS = {
	["Right Shoulder"] = Vector3.new(0.15, BODY_FRONT, 0),
	["Left Shoulder"] = Vector3.new(-0.15, BODY_FRONT, 0),
	Neck = Vector3.new(0, BODY_FRONT, 0),
	["Right Hip"] = Vector3.new(0.2, -BODY_BACK, 0),
	["Left Hip"] = Vector3.new(-0.2, -BODY_BACK, 0),
}

function BerserkerLook.UndressBeast(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:HasTag(BEAST_TAG) then
			d:Destroy()
		elseif (d:IsA("BasePart") or d:IsA("Decal")) and d:GetAttribute(HIDE_FLAG) ~= nil then
			(d :: any).Transparency = d:GetAttribute(HIDE_FLAG) :: number
			d:SetAttribute(HIDE_FLAG, nil)
		elseif d:IsA("Motor6D") and d:GetAttribute(JOINT_FLAG) ~= nil then
			d.C0 = d:GetAttribute(JOINT_FLAG) :: CFrame
			d:SetAttribute(JOINT_FLAG, nil)
		end
	end
end

function BerserkerLook.DressBeast(char: Model)
	BerserkerLook.UndressBeast(char)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not (head and torso) then return end
	-- The man is gone: his body, his armour, whatever he wears, his face.
	for _, d in ipairs(char:GetDescendants()) do
		if (d:IsA("BasePart") and not KEEP[d.Name]) or d:IsA("Decal") then
			if d:GetAttribute(HIDE_FLAG) == nil then
				d:SetAttribute(HIDE_FLAG, (d :: any).Transparency)
				;(d :: any).Transparency = 1
			end
		end
	end
	-- The longer frame. (The limbs' pieces below are welded to the limbs where
	-- they are now: they go wherever the moved joints take them.)
	for name, d in pairs(BEAST_JOINTS) do
		local m = torso:FindFirstChild(name)
		if m and m:IsA("Motor6D") then
			m:SetAttribute(JOINT_FLAG, m.C0)
			m.C0 = m.C0 + d
		end
	end

	-- ── The body: slabs of rock, the back a ridge of shards ─────────────────
	-- (from the chest, +2.4, to the rump, -2.8: the hips are at -2, the
	-- shoulders at +1.4)
	slab(torso, Vector3.new(2.4, 2.2, 1.5), CFrame.new(0, 0.85, 0.05), STONE)                             -- the barrel
	slab(torso, Vector3.new(2.05, 1.8, 1.3), CFrame.new(0, -0.8, 0.12), STONE_DARK)                        -- the waist
	slab(torso, Vector3.new(2.35, 1.5, 1.45), CFrame.new(0, -2.1, 0.2) * CFrame.Angles(R(5), 0, 0), STONE) -- the rump
	slab(torso, Vector3.new(2.1, 4.4, 0.5), CFrame.new(0, -0.4, 0.95) * CFrame.Angles(R(2), 0, 0), STONE_DARK) -- the back
	slab(torso, Vector3.new(2.55, 1.0, 1.1), CFrame.new(0, 1.55, 0.55) * CFrame.Angles(R(-6), 0, 0), STONE) -- the withers
	slab(torso, Vector3.new(2.05, 0.6, 1.3), CFrame.new(0, 2.15, -0.15) * CFrame.Angles(R(10), 0, 0), STONE_EDGE) -- the breast
	slab(torso, Vector3.new(1.8, 3.6, 0.35), CFrame.new(0, -0.5, -0.78), STONE_DARK)                       -- the belly
	slab(torso, Vector3.new(1.4, 0.9, 1.2), CFrame.new(0, 2.25, 0.3) * CFrame.Angles(R(-12), 0, 0), STONE) -- the neck
	-- the ridge down the spine, swept back toward the tail, and a row down each side
	for i = 0, 11 do
		shard(torso, Vector3.new(0, 2.1 - i * 0.42, 1.12), Vector3.new(0, 0.25, 1), Vector3.new(0, -1, 0), 0.58 - i * 0.02, 1.5 - i * 0.07)
	end
	for i = 0, 8 do
		for _, sx in ipairs({ -1, 1 }) do
			shard(torso, Vector3.new(sx * 0.65, 1.7 - i * 0.48, 1.02), Vector3.new(sx * 0.55, 0.2, 1), Vector3.new(sx * 0.3, -1, 0),
				0.46, 1.0 - i * 0.05, if i % 2 == 0 then STONE else STONE_DARK)
		end
	end
	-- the mane: a ruff of big shards round the neck, flaring back
	for k = -2, 2 do
		local x = k * 0.45
		shard(torso, Vector3.new(x, 2.2, 0.4 + (2 - math.abs(k)) * 0.1), Vector3.new(x * 0.5, 0.55, 1), Vector3.new(x * 0.3, -1, 0.2),
			0.6, 1.6 - math.abs(k) * 0.15, if k % 2 == 0 then STONE_DARK else STONE)
	end
	for _, sx in ipairs({ -1, 1 }) do
		shard(torso, Vector3.new(sx * 1.17, 1.9, 0.1), Vector3.new(sx, 0.3, 0.6), Vector3.new(0, -1, 0), 0.5, 1.3)
	end
	-- red cracks through the back and down the flanks
	crack(torso, { Vector3.new(-0.6, 1.6, 1.22), Vector3.new(-0.2, 1.0, 1.22), Vector3.new(-0.45, 0.3, 1.22), Vector3.new(-0.1, -0.4, 1.22),
		Vector3.new(-0.5, -1.2, 1.22) }, Vector3.zAxis)
	crack(torso, { Vector3.new(0.5, 0.8, 1.22), Vector3.new(0.25, 0.1, 1.22), Vector3.new(0.6, -0.7, 1.22), Vector3.new(0.3, -1.8, 1.22) },
		Vector3.zAxis)
	for _, sx in ipairs({ -1, 1 }) do
		crack(torso, { Vector3.new(sx * 1.21, 1.6, -0.25), Vector3.new(sx * 1.21, 1.0, 0.2), Vector3.new(sx * 1.21, 0.4, -0.1),
			Vector3.new(sx * 1.21, -0.1, 0.25) }, Vector3.new(sx, 0, 0))
		crack(torso, { Vector3.new(sx * 1.18, -1.5, 0.3), Vector3.new(sx * 1.18, -2.0, -0.05), Vector3.new(sx * 1.18, -2.6, 0.2) },
			Vector3.new(sx, 0, 0))
	end

	-- ── The tail: long and heavy, a ridge of shards along it ────────────────
	local at = Vector3.new(0, -2.85, 0.75)
	local tail = {
		{ dir = Vector3.new(0, -1, 0.45).Unit, len = 1.3, w = 0.78 },
		{ dir = Vector3.new(0, -1, 0.1).Unit, len = 1.2, w = 0.58 },
		{ dir = Vector3.new(0, -1, -0.2).Unit, len = 1.1, w = 0.4 },
	}
	for i, seg in ipairs(tail) do
		local b = at + seg.dir * seg.len
		limbSeg(torso, "Tail", at, b, seg.w, seg.w * 0.9, if i == 2 then STONE_DARK else STONE)
		local top = Vector3.new(0, seg.dir.Z, -seg.dir.Y) -- (square to it, up)
		for k = 0, 2 do
			local p = at + seg.dir * seg.len * (0.15 + k * 0.33) + top * seg.w * 0.4
			shard(torso, p, top + Vector3.new(if k == 1 then 0.25 else -0.25, 0, 0), seg.dir, seg.w * 0.7, 1.0 - (i - 1) * 0.22 - k * 0.06)
		end
		if i == 1 then crack(torso, { at + top * (seg.w * 0.46), b + top * (seg.w * 0.46) }, top, 0.06) end
		at = b
	end
	shard(torso, at, tail[3].dir, Vector3.new(0, tail[3].dir.Z, -tail[3].dir.Y), 0.36, 0.8)

	-- ── The head: a wolf's, slit eyes, the jaw open on a red glow ───────────
	slab(head, Vector3.new(1.5, 1.1, 1.4), CFrame.new(0, 0.15, 0.1), STONE)                                   -- the skull
	slab(head, Vector3.new(1.55, 0.3, 0.5), CFrame.new(0, 0.55, -0.45) * CFrame.Angles(R(-10), 0, 0), STONE_DARK) -- the brow
	slab(head, Vector3.new(0.95, 0.55, 1.15), CFrame.new(0, -0.05, -1.05), STONE)                             -- the muzzle
	beastPart(head, "Snout", "wedge", Vector3.new(0.95, 0.4, 0.95), CFrame.new(0, 0.42, -0.95), STONE_EDGE)  -- (its bridge)
	slab(head, Vector3.new(0.45, 0.28, 0.2), CFrame.new(0, 0.12, -1.66), CLAW_BLACK)                          -- the nose
	beastPart(head, "Jaw", "block", Vector3.new(0.85, 0.24, 1.05),
		CFrame.new(0, -0.42, -0.45) * CFrame.Angles(R(-14), 0, 0) * CFrame.new(0, 0, -0.52), STONE_DARK)
	beastPart(head, "Maw", "block", Vector3.new(0.7, 0.1, 0.8), CFrame.new(0, -0.33, -0.95), MAW, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		beastPart(head, "Fang", "wedge", Vector3.new(0.1, 0.26, 0.12), CFrame.new(sx * 0.32, -0.38, -1.5) * CFrame.Angles(math.pi, 0, 0), BONE, Enum.Material.SmoothPlastic)
		beastPart(head, "Fang", "wedge", Vector3.new(0.08, 0.2, 0.1), CFrame.new(sx * 0.14, -0.36, -1.6) * CFrame.Angles(math.pi, 0, 0), BONE, Enum.Material.SmoothPlastic)
		beastPart(head, "Fang", "wedge", Vector3.new(0.09, 0.2, 0.1), CFrame.new(sx * 0.26, -0.56, -1.3), BONE, Enum.Material.SmoothPlastic)
		-- the eyes: slits, slanted down to the snout
		beastPart(head, "BeastEye", "block", Vector3.new(0.36, 0.1, 0.08), CFrame.new(sx * 0.4, 0.3, -0.71) * CFrame.Angles(0, 0, R(sx * 16)),
			Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		-- pointed ears, laid back; ruffs of shards at the cheeks
		shard(head, Vector3.new(sx * 0.5, 0.62, 0.15), Vector3.new(sx * 0.35, 1, 0.15), Vector3.new(0, 0, 1), 0.46, 0.95, STONE)
		shard(head, Vector3.new(sx * 0.74, -0.15, -0.1), Vector3.new(sx, -0.1, 0.2), Vector3.new(0, 0, 1), 0.42, 0.8)
		shard(head, Vector3.new(sx * 0.6, 0.2, 0.72), Vector3.new(sx * 0.6, 0.2, 1), Vector3.new(0, 0.3, 1), 0.5, 1.1)
		crack(head, { Vector3.new(sx * 0.76, 0.25, -0.4), Vector3.new(sx * 0.76, 0.4, 0.1), Vector3.new(sx * 0.76, 0.2, 0.6) }, Vector3.new(sx, 0, 0), 0.06)
	end
	-- the mane carried up over the skull
	for k = -1, 1 do
		shard(head, Vector3.new(k * 0.45, 0.62, 0.5), Vector3.new(k * 0.4, 0.7, 0.8), Vector3.new(0, 0, 1), 0.56, 1.3 - math.abs(k) * 0.15)
	end

	-- ── The legs: built as a wolf's, scaled up into a monster ───────────────
	-- Long, powerful digitigrade hind legs (a heavy thigh, then the lower leg
	-- on its own knee joint: shin back to the hock, the long hock down to a
	-- clawed paw) that hold the pelvis high; and long front legs, the arms,
	-- with an elbow, ending in great claws. The knee and elbow are Motor6Ds on
	-- hidden bones; the client bends them every frame (BerserkerController)
	-- so the paws land where the stride puts them.
	for _, side in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = char:FindFirstChild(side) :: BasePart?
		if not arm then continue end
		local sx = if side == "Left Arm" then -1 else 1
		slab(arm, Vector3.new(1.35, 1.7, 1.35), CFrame.new(0, -0.05, 0), STONE)                                   -- upper arm
		-- the shoulder: a boulder, capped
		slab(arm, Vector3.new(1.75, 1.35, 1.75), CFrame.new(sx * 0.12, 0.8, 0.05) * CFrame.Angles(R(6), R(sx * 10), R(sx * -8)), STONE_EDGE)
		slab(arm, Vector3.new(1.3, 0.5, 1.3), CFrame.new(sx * 0.2, 1.55, 0.05) * CFrame.Angles(R(-8), 0, R(sx * -14)), STONE)
		shard(arm, Vector3.new(sx * 0.7, 1.3, 0.1), Vector3.new(sx * 0.7, 0.6, 0.4), Vector3.new(0, 0, 1), 0.5, 1.1)
		shard(arm, Vector3.new(sx * 0.5, 1.45, 0.6), Vector3.new(sx * 0.5, 0.7, 0.6), Vector3.new(0, 0.2, 1), 0.44, 0.9, STONE)
		crack(arm, { Vector3.new(sx * 0.68, 0.4, -0.3), Vector3.new(sx * 0.68, -0.1, 0.1), Vector3.new(sx * 0.68, -0.6, -0.2) }, Vector3.new(sx, 0, 0))
		local fore = beastBone(char, arm, "BeastFore" .. (if sx > 0 then "R" else "L"), "BeastElbow", ARM_ELBOW)
		beastPart(fore, "LongArm", "block", Vector3.new(1.12, 1.45, 1.12), CFrame.new(0, -0.7, -0.08), STONE)
		shard(fore, Vector3.new(0, -0.05, 0.5), Vector3.new(0, 0.3, 1), Vector3.new(0, 1, 0), 0.45, 0.9)       -- the elbow spur
		crack(fore, { Vector3.new(0.25, -0.2, -0.65), Vector3.new(-0.1, -0.7, -0.65), Vector3.new(0.2, -1.2, -0.65) }, -Vector3.zAxis)
		slab(fore, Vector3.new(1.3, 0.4, 1.3), CFrame.new(0, -1.35, -0.12), STONE_EDGE)                           -- the wrist
		beastPart(fore, "Paw", "block", Vector3.new(1.4, 0.48, 1.45), CFrame.new(0, -1.62, -0.22), STONE_DARK)
		for k = -1, 2 do
			local x = (k - 0.5) * 0.36
			beastPart(fore, "Claw", "wedge", Vector3.new(0.18, 1.2, 0.36), CFrame.new(x, -2.15, -0.58) * CFrame.Angles(R(-28), 0, 0), CLAW_BLACK)
			beastPart(fore, "ClawTip", "wedge", Vector3.new(0.13, 0.42, 0.22), CFrame.new(x, -2.78, -0.88) * CFrame.Angles(R(-28), 0, 0),
				Color3.fromRGB(150, 12, 22), Enum.Material.Neon)
		end
	end
	for _, side in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = char:FindFirstChild(side) :: BasePart?
		if not leg then continue end
		local sx = if side == "Left Leg" then -1 else 1
		limbSeg(leg, "Thigh", Vector3.new(0, 1.05, 0.1), Vector3.new(0, -0.65, -0.05), 1.3, 1.4, STONE)
		slab(leg, Vector3.new(1.45, 1.2, 1.5), CFrame.new(0, 0.75, 0.35) * CFrame.Angles(R(-6), 0, 0), STONE_EDGE) -- the haunch
		shard(leg, Vector3.new(sx * 0.45, 1.0, 1.0), Vector3.new(sx * 0.4, 0.3, 1), Vector3.new(0, 1, 0.3), 0.5, 1.0)
		shard(leg, Vector3.new(sx * 0.2, 0.45, 1.05), Vector3.new(sx * 0.3, 0.2, 1), Vector3.new(0, 1, 0.3), 0.4, 0.8, STONE)
		crack(leg, { Vector3.new(sx * 0.74, 0.9, 0.2), Vector3.new(sx * 0.74, 0.4, -0.15), Vector3.new(sx * 0.74, -0.1, 0.1) }, Vector3.new(sx, 0, 0))
		local shin = beastBone(char, leg, "BeastShin" .. (if sx > 0 then "R" else "L"), "BeastKnee", LEG_KNEE)
		limbSeg(shin, "Shin", Vector3.new(0, 0.1, -0.05), Vector3.new(0, -1.1, 0.55), 0.8, 0.85, STONE)
		limbSeg(shin, "Hock", Vector3.new(0, -1.1, 0.55), Vector3.new(0, -2.05, 0.05), 0.55, 0.6, STONE_DARK)
		beastPart(shin, "HindPaw", "block", Vector3.new(0.85, 0.32, 1.0), CFrame.new(0, -2.08, -0.25), STONE_DARK)
		for k = -1, 1 do
			beastPart(shin, "Talon", "wedge", Vector3.new(0.15, 0.32, 0.5), CFrame.new(k * 0.28, -2.1, -0.88), CLAW_BLACK)
		end
		shard(shin, Vector3.new(0, -1.1, 0.78), Vector3.new(0, -0.2, 1), Vector3.new(0, 1, 0), 0.35, 0.7)          -- the hock spur
	end

	-- Red energy leaking out of the cracks, black smoke off the back.
	local leak = Instance.new("ParticleEmitter")
	leak.Name = "BeastEnergy"
	leak.Texture = "rbxasset://textures/particles/fire_main.dds"
	leak.Color = ColorSequence.new(Color3.fromRGB(255, 60, 60), CRIMSON_DARK)
	leak.LightEmission = 0.8
	leak.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 0) })
	leak.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
	leak.Lifetime = NumberRange.new(0.5, 0.9)
	leak.Speed = NumberRange.new(2, 5)
	leak.SpreadAngle = Vector2.new(50, 50)
	leak.Acceleration = Vector3.new(0, 6, 0)
	leak.Rate = 22
	leak:AddTag(BEAST_TAG)
	leak.Parent = torso
	local smoke = Instance.new("ParticleEmitter")
	smoke.Name = "BeastSmoke"
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(20, 8, 10))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(0.8, 1.4)
	smoke.Speed = NumberRange.new(1, 3)
	smoke.Acceleration = Vector3.new(0, 3, 0)
	smoke.Rate = 10
	smoke:AddTag(BEAST_TAG)
	smoke.Parent = torso
end

return BerserkerLook
