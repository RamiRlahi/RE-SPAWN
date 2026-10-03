--!strict
--[[
	BerserkerLook.luau
	The Berserker's look, built from parts (no uploaded assets), black metal
	and deep crimson only:

	  BuildGreatsword()  the "berzerker greatsword" Tool from ReplicatedStorage
	                     as it is (Tool named "Ragebringer").
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
-- The Berserker's own sword: the "berzerker greatsword" Tool in
-- ReplicatedStorage, used as it is (its textures, no glow). Falls back to the
-- game's Greatsword if it's missing.
local function findTool(name: string): Tool?
	local lower = string.lower(name)
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("Tool") and string.lower(d.Name) == lower then return d end
	end
	return nil
end

function BerserkerLook.BuildGreatsword(): Tool
	local template = findTool("berzerker greatsword") or findTool("berserker greatsword") or findTool("Greatsword")
	local tool: Tool
	if template then
		tool = template:Clone()
	else
		-- (no asset: a plain blade so the class still works)
		tool = Instance.new("Tool")
		local h = Instance.new("Part")
		h.Name = "Handle"
		h.Size = Vector3.new(0.4, 7, 1.2)
		h.Parent = tool
	end
	tool.Name = "Ragebringer"
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	-- Weld any loose pieces to the handle where they sit, and find the blade
	-- (the biggest piece).
	local blade: BasePart? = nil
	for _, p in ipairs(tool:GetDescendants()) do
		if p:IsA("BasePart") then
			p.Anchored = false
			p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
			if handle and p ~= handle and #p:GetJoints() == 0 then
				local w = Instance.new("WeldConstraint")
				w.Part0 = handle
				w.Part1 = p
				w.Parent = p
			end
			if not blade or p.Size.Magnitude > blade.Size.Magnitude then blade = p end
		end
	end
	if handle then handle.Transparency = 1 end
	-- Invisible attachments at both ends of the blade for the client's swing
	-- trail (the trail only shows while swinging).
	local b = blade or handle
	if b then
		local s = b.Size
		local long = math.max(s.X, s.Y, s.Z)
		local axis = if long == s.Y then Vector3.yAxis elseif long == s.X then Vector3.xAxis else Vector3.zAxis
		-- The hilt is the end nearer the grip point; the tip is the far end.
		local gripAt = if handle then (handle.CFrame * tool.Grip.Position) else b.Position
		local towardGrip = b.CFrame:VectorToObjectSpace(gripAt - b.Position):Dot(axis)
		local tipSign = if towardGrip > 0 then -1 else 1
		local a0 = Instance.new("Attachment")
		a0.Name = "RageBase"
		a0.Position = axis * tipSign * long * 0.05
		a0.Parent = b
		local a1 = Instance.new("Attachment")
		a1.Name = "RageTip"
		a1.Position = axis * tipSign * long * 0.48
		a1.Parent = b
	end
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

return BerserkerLook
