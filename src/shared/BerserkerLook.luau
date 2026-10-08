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
-- Built over his armour in R6 units, before the server scales the whole
-- character up (BerserkerServer): a monstrous skull with an open jaw, slit
-- red eyes and swept-back horns; a hunched, spiked back; long arms ending in
-- huge black claws tipped red; red energy cracks; the scarf grown long,
-- trailing behind. The armour that breaks away (helm, breastplate,
-- gauntlets) is hidden, and comes back with UndressBeast.
local BEAST_TAG = "BerserkerBeast"
local HIDE = { Helm = true, HelmCrest = true, Visor = true, Cheek = true, ChestPlate = true, Gauntlet = true,
	GauntletRim = true, PauldronTop = true, Horn = true }
local HIDE_FLAG = "BeastHidden"
local FLESH = Color3.fromRGB(46, 12, 16)
local HIDE_DARK = Color3.fromRGB(20, 12, 14)
local BONE = Color3.fromRGB(214, 196, 178)
local SCARF = Color3.fromRGB(176, 18, 28)

local function beastPart(parent: BasePart, name: string, shape: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = plate(parent, name, shape, size, offset, color, material)
	p:RemoveTag(TAG)
	p:AddTag(BEAST_TAG)
	return p
end

function BerserkerLook.UndressBeast(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:HasTag(BEAST_TAG) then
			d:Destroy()
		elseif d:IsA("BasePart") and d:GetAttribute(HIDE_FLAG) ~= nil then
			d.Transparency = d:GetAttribute(HIDE_FLAG) :: number
			d:SetAttribute(HIDE_FLAG, nil)
		end
	end
end

function BerserkerLook.DressBeast(char: Model)
	BerserkerLook.UndressBeast(char)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not (head and torso) then return end
	-- The armour that breaks away.
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d:HasTag(TAG) and HIDE[d.Name] then
			d:SetAttribute(HIDE_FLAG, d.Transparency)
			d.Transparency = 1
		end
	end

	-- The head: a long skull, the jaw hanging open, teeth, slit eyes, horns.
	beastPart(head, "Skull", "block", Vector3.new(1.45, 1.2, 1.55), CFrame.new(0, 0.1, 0.05), HIDE_DARK)
	beastPart(head, "Brow", "wedge", Vector3.new(1.5, 0.35, 0.5), CFrame.new(0, 0.42, -0.72) * CFrame.Angles(0, math.pi, 0), FLESH)
	beastPart(head, "Snout", "wedge", Vector3.new(1.15, 0.5, 0.75), CFrame.new(0, -0.18, -0.95) * CFrame.Angles(0, math.pi, 0), HIDE_DARK)
	beastPart(head, "Jaw", "block", Vector3.new(1.05, 0.26, 0.85), CFrame.new(0, -0.62, -0.72) * CFrame.Angles(R(18), 0, 0), FLESH)
	beastPart(head, "Maw", "block", Vector3.new(0.85, 0.12, 0.6), CFrame.new(0, -0.42, -0.8), CRIMSON, Enum.Material.Neon)
	for i = -1, 1, 2 do
		for k = 0, 1 do
			beastPart(head, "Fang", "wedge", Vector3.new(0.1, 0.26, 0.1), CFrame.new(i * (0.18 + k * 0.22), -0.33, -1.05 + k * 0.12) * CFrame.Angles(math.pi, 0, 0), BONE, Enum.Material.SmoothPlastic)
			beastPart(head, "Fang", "wedge", Vector3.new(0.1, 0.22, 0.1), CFrame.new(i * (0.16 + k * 0.22), -0.5, -1.0 + k * 0.12), BONE, Enum.Material.SmoothPlastic)
		end
	end
	for _, sx in ipairs({ -1, 1 }) do
		beastPart(head, "BeastEye", "block", Vector3.new(0.34, 0.1, 0.1), CFrame.new(sx * 0.34, 0.24, -0.84) * CFrame.Angles(0, 0, R(sx * -14)), Color3.fromRGB(255, 40, 40), Enum.Material.Neon)
		-- horns sweeping back and up, in three segments
		beastPart(head, "BeastHorn", "corner", Vector3.new(0.42, 0.9, 0.42), CFrame.new(sx * 0.62, 0.78, 0.15) * CFrame.Angles(R(-25), 0, R(sx * -30)), HIDE_DARK)
		beastPart(head, "BeastHorn", "corner", Vector3.new(0.32, 0.9, 0.32), CFrame.new(sx * 0.95, 1.35, 0.55) * CFrame.Angles(R(-45), 0, R(sx * -15)), BLACK)
		beastPart(head, "BeastHorn", "corner", Vector3.new(0.2, 0.8, 0.2), CFrame.new(sx * 1.05, 1.8, 1.1) * CFrame.Angles(R(-75), 0, R(sx * -5)), CRIMSON_DARK)
	end
	for k = 0, 2 do
		beastPart(head, "Crest", "corner", Vector3.new(0.2, 0.55 - k * 0.1, 0.3), CFrame.new(0, 0.8 - k * 0.15, 0.25 + k * 0.38) * CFrame.Angles(R(-35), 0, 0), CRIMSON_DARK)
	end

	-- The torso: a hunched, spiked back, broken plates, glowing cracks.
	beastPart(torso, "Hump", "block", Vector3.new(2.5, 1.6, 1.1), CFrame.new(0, 0.55, 0.55), FLESH)
	for k = 0, 3 do
		beastPart(torso, "SpineSpike", "corner", Vector3.new(0.35, 0.9 - k * 0.12, 0.45), CFrame.new(0, 1.3 - k * 0.55, 1.1) * CFrame.Angles(R(-40), 0, 0), CRIMSON_DARK)
	end
	beastPart(torso, "BrokenPlate", "wedge", Vector3.new(0.9, 0.7, 0.2), CFrame.new(-0.55, 0.45, -0.66) * CFrame.Angles(0, 0, R(20)), IRON)
	beastPart(torso, "BrokenPlate", "wedge", Vector3.new(0.7, 0.55, 0.2), CFrame.new(0.6, -0.1, -0.66) * CFrame.Angles(0, math.pi, R(-15)), IRON)
	for _, c in ipairs({
		{ 0.1, 0.4, -0.71, 25, 1.1 }, { -0.25, -0.2, -0.71, -30, 0.8 }, { 0.45, 0.55, -0.71, -50, 0.6 },
		{ 0.2, 0.3, 1.12, 20, 1.2 }, { -0.4, -0.1, 1.12, -35, 0.9 },
	}) do
		beastPart(torso, "BeastCrack", "block", Vector3.new(0.08, c[5], 0.05), CFrame.new(c[1], c[2], c[3]) * CFrame.Angles(0, 0, R(c[4])), CRIMSON, Enum.Material.Neon)
	end
	-- The scarf, grown long, trailing back from the neck.
	for i, sx in ipairs({ -0.35, 0.3 }) do
		local len = 4.2 - i * 0.6
		local tilt = R(-50 + i * 6)
		beastPart(torso, "BeastScarf", "block", Vector3.new(0.75, len, 0.07), CFrame.new(sx, 0.9, 0.75) * CFrame.Angles(tilt, 0, R(sx * 8)) * CFrame.new(0, -len / 2, 0), SCARF, Enum.Material.Fabric)
		beastPart(torso, "BeastScarfEnd", "wedge", Vector3.new(0.07, 0.6, 0.6), CFrame.new(sx, 0.9, 0.75) * CFrame.Angles(tilt, 0, R(sx * 8)) * CFrame.new(0, -len - 0.25, 0) * CFrame.Angles(0, R(90), math.pi), SCARF, Enum.Material.Fabric)
	end

	-- The arms: bulked, longer, ending in great claws.
	for _, side in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = char:FindFirstChild(side) :: BasePart?
		if not arm then continue end
		local sx = if side == "Left Arm" then -1 else 1
		beastPart(arm, "Forearm", "block", Vector3.new(1.3, 1.5, 1.3), CFrame.new(0, -0.35, 0), FLESH)
		beastPart(arm, "ArmCrack", "block", Vector3.new(0.07, 1.1, 0.05), CFrame.new(sx * 0.2, -0.35, -0.67) * CFrame.Angles(0, 0, R(sx * 15)), CRIMSON, Enum.Material.Neon)
		beastPart(arm, "LongArm", "block", Vector3.new(1.05, 1.3, 1.05), CFrame.new(0, -1.6, -0.08), HIDE_DARK)
		beastPart(arm, "Paw", "block", Vector3.new(1.3, 0.5, 1.35), CFrame.new(0, -2.4, -0.18), HIDE_DARK)
		for k = -1, 2 do
			local x = (k - 0.5) * 0.36
			beastPart(arm, "Claw", "wedge", Vector3.new(0.16, 1.3, 0.34), CFrame.new(x, -3.05, -0.55) * CFrame.Angles(R(-28), 0, 0), BLACK)
			beastPart(arm, "ClawTip", "wedge", Vector3.new(0.12, 0.4, 0.2), CFrame.new(x, -3.68, -0.88) * CFrame.Angles(R(-28), 0, 0), CRIMSON, Enum.Material.Neon)
		end
		for k = -1, 1, 2 do
			beastPart(arm, "ShoulderSpike", "corner", Vector3.new(0.4, 1.2, 0.4), CFrame.new(sx * 0.35, 1.7, k * 0.35) * CFrame.Angles(R(k * 15), 0, R(sx * -28)), CRIMSON_DARK)
		end
	end
	-- Clawed feet.
	for _, side in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = char:FindFirstChild(side) :: BasePart?
		if not leg then continue end
		for k = -1, 1 do
			beastPart(leg, "Talon", "wedge", Vector3.new(0.14, 0.32, 0.45), CFrame.new(k * 0.32, -0.92, -0.85), BLACK)
		end
		beastPart(leg, "CalfSpike", "corner", Vector3.new(0.3, 0.7, 0.3), CFrame.new(0, -0.1, 0.65) * CFrame.Angles(R(35), 0, 0), CRIMSON_DARK)
	end

	-- Red energy leaking out of him, black smoke off the back.
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
