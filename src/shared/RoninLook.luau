--!strict
--[[
	RoninLook.luau
	The Ronin's katana and scabbard, built in code; the blade itself is the
	katana model in ReplicatedStorage.Preload.RoninKatana when the place has it
	(else built from parts too). Geometry and
	frames match the Blender R6 previews the moves were baked from
	(RoninMoves), so the hands meet the hilt where the animation expects:

	  Katana   a Tool held at the RightGripAttachment: the hilt's middle in the
	           fist, the blade along the handle's -Z, the edge along -Y
	           (the arm's length), curving slightly toward +Y at the tip.
	  Scabbard worn at the LEFT hip at rest; during the four baked moves it is
	           held in the left hand, through the fist, the mouth 1 stud in
	           front of it (RoninLook.SetMount blends between the two). A
	           second, sheathed katana sits in it; RoninLook.SetSlide slides it
	           out of the mouth (client, local).

	Which katana shows (in the hand or in the scabbard) is each client's call
	(RoninController, LocalTransparencyModifier), so it follows the move
	playing on that client.
--]]

local RoninLook = {}

-- Mirrored from the preview rig (scratchpad r6.py): keep in step with RoninMoves.
RoninLook.GRIP_DROP = 1.0      -- the grip attachment: 1 stud down the arm
RoninLook.MOUTH = 1.0          -- the scabbard's mouth this far in front of the left fist
RoninLook.SWORD_OUT = 0.6      -- the sheathed hilt's middle this far in front of the mouth
RoninLook.ROLL = 220           -- the sheathed blade's roll in the scabbard (degrees)
RoninLook.BLADE = 4.5          -- blade length (studs), guard to tip
-- The scabbard's mouth at rest, in the Torso's space: front-left of the hip, the
-- scabbard running back, out and down past the hanging left arm (+Z toward its tip).
local HIP_AT = Vector3.new(-0.9, -0.9, -0.7)
local HIP_TIP = Vector3.new(-0.35, -0.3, 0.89).Unit
RoninLook.HIP = CFrame.lookAt(HIP_AT, HIP_AT - HIP_TIP)

local STEEL = Color3.fromRGB(205, 222, 236)
local EDGE = Color3.fromRGB(150, 225, 255)
local WRAP = Color3.fromRGB(22, 14, 32)
local GUARD = Color3.fromRGB(160, 126, 54)
local SAYA = Color3.fromRGB(10, 10, 14)

local function part(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart, c0: CFrame): Weld
	local w = Instance.new("Weld")
	w.Part0 = a
	w.Part1 = b
	w.C0 = c0
	w.Parent = b
	return w
end

-- The katana's parts round `root` (the hilt's middle), in its own space.
local function buildBlade(root: BasePart, parent: Instance)
	local pommel = part("Pommel", Vector3.new(0.2, 0.24, 0.08), GUARD, Enum.Material.Metal, parent)
	weld(root, pommel, CFrame.new(0, 0, 0.56))
	local guard = part("Guard", Vector3.new(0.5, 0.5, 0.07), GUARD, Enum.Material.Metal, parent)
	weld(root, guard, CFrame.new(0, 0, -0.56))
	-- the blade: three straight pieces along a gentle curve (the tip rises 0.28)
	local L, prev = RoninLook.BLADE, Vector3.new(0, 0, -0.6)
	for i = 1, 3 do
		local t = i / 3
		local nxt = Vector3.new(0, 0.28 * t * t, -0.6 - L * t)
		local mid = (prev + nxt) / 2
		local len = (nxt - prev).Magnitude
		local depth = 0.2 * (1 - 0.35 * (t - 1 / 6))
		local seg = part("Blade" .. i, Vector3.new(0.07, depth, len + 0.02), STEEL, Enum.Material.Metal, parent)
		seg.Reflectance = 0.25
		weld(root, seg, CFrame.lookAt(mid, nxt, Vector3.new(0, 1, 0)))
		local edge = part("Edge" .. i, Vector3.new(0.035, 0.04, len + 0.02), EDGE, Enum.Material.Neon, parent)
		weld(root, edge, CFrame.lookAt(mid, nxt, Vector3.new(0, 1, 0)) * CFrame.new(0, -depth / 2, 0))
		prev = nxt
	end
end

-- The katana model (ReplicatedStorage.Preload.RoninKatana, saved in the place:
-- a MeshPart with the blade along +Y, the hilt at -Y, the edge on +X), cloned,
-- or nil without it (then the blade is built from parts).
RoninLook.MESH_GRIP_Y = -1.62 -- the middle of the mesh's hilt
RoninLook.MESH_TIP = 3.96     -- grip to tip along the blade
local function katanaMesh(): BasePart?
	local preload = game:GetService("ReplicatedStorage"):FindFirstChild("Preload")
	local src = preload and preload:FindFirstChild("RoninKatana")
	if not (src and src:IsA("BasePart")) then return nil end
	local m = src:Clone()
	m.Name = "KatanaMesh"
	m.Anchored = false
	m.CanCollide, m.CanTouch, m.CanQuery = false, false, false
	m.Massless = true
	m.CastShadow = false
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("Trail") then d.Enabled = false end
	end
	return m
end

-- The katana round `root` (the hilt's middle; the blade along its -Z, the edge
-- along -Y): the model if it's there (root itself then hidden: the model has
-- its own hilt), else the built pieces. True with the model.
local function dressBlade(root: BasePart, parent: Instance): boolean
	local m = katanaMesh()
	if not m then
		buildBlade(root, parent)
		return false
	end
	root.Transparency = 1
	m.Parent = parent
	-- (the mesh's +X, the edge, to -Y; its +Y, the blade, to -Z; its hilt's middle on root)
	weld(root, m, CFrame.fromMatrix(Vector3.zero, Vector3.new(0, -1, 0), Vector3.new(0, 0, -1))
		* CFrame.new(0, -RoninLook.MESH_GRIP_Y, 0))
	return true
end

-- The katana held in the right hand.
function RoninLook.BuildKatana(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Katana"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- (as the Rogue's dagger: the handle's -Z out of the fist, the grip's
	-- middle in it; the arm's own frame, 1 stud down)
	tool.Grip = CFrame.Angles(math.rad(-90), 0, 0)
	tool:SetAttribute("BladeAxis", "-Z")
	local handle = part("Handle", Vector3.new(0.16, 0.2, 1.05), WRAP, Enum.Material.Fabric, tool)
	handle.CFrame = CFrame.new(0, 50, 0)
	local mesh = dressBlade(handle, tool)
	-- a trail along the blade for the cuts (RoninController turns it on)
	local a0 = Instance.new("Attachment")
	a0.Name = "BladeBase"
	a0.Position = Vector3.new(0, 0, -0.8)
	a0.Parent = handle
	local a1 = Instance.new("Attachment")
	a1.Name = "BladeTip"
	a1.Position = if mesh then Vector3.new(0, 0.12, -RoninLook.MESH_TIP) else Vector3.new(0, 0.25, -0.6 - RoninLook.BLADE)
	a1.Parent = handle
	local trail = Instance.new("Trail")
	trail.Name = "KatanaTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = 0.16
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), EDGE)
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.Enabled = false
	trail.Parent = handle
	return tool
end

-- Where the scabbard's mouth sits on the Left Arm when held (+Z runs to its tip).
function RoninLook.MouthOffset(): CFrame
	return CFrame.new(0, -RoninLook.GRIP_DROP, -RoninLook.MOUTH)
end

-- The sheathed katana's place relative to the mouth, `slide` studs drawn out.
function RoninLook.SheathedOffset(slide: number): CFrame
	return CFrame.new(0, 0, -slide - RoninLook.SWORD_OUT)
		* CFrame.Angles(math.pi, 0, 0) * CFrame.Angles(0, 0, math.rad(RoninLook.ROLL))
end

-- The scabbard and the sheathed katana. Everything hangs off "Mouth" (an
-- invisible part at the scabbard's mouth), welded to the Torso at the hip;
-- SetMount moves it into the left hand. Safe to call again (the old one goes first).
function RoninLook.AttachScabbard(character: Model): Model?
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not torso then return nil end
	RoninLook.RemoveScabbard(character)
	local model = Instance.new("Model")
	model.Name = "RoninScabbard"
	model:SetAttribute("RoninLook", true)
	local mouthPart = part("Mouth", Vector3.new(0.1, 0.1, 0.1), SAYA, Enum.Material.SmoothPlastic, model)
	mouthPart.Transparency = 1
	local mount = weld(torso, mouthPart, RoninLook.HIP)
	mount.Name = "ScabbardMount"
	-- the scabbard (rolled with the blade inside, deep enough for its curve)
	local len = RoninLook.BLADE + 0.25
	local roll = CFrame.Angles(0, 0, math.rad(-RoninLook.ROLL))
	local saya = part("Saya", Vector3.new(0.19, 0.5, len), SAYA, Enum.Material.SmoothPlastic, model)
	saya.Reflectance = 0.08
	weld(mouthPart, saya, roll * CFrame.new(0, -0.1, len / 2))
	local collar = part("Koiguchi", Vector3.new(0.24, 0.56, 0.12), GUARD, Enum.Material.Metal, model)
	weld(mouthPart, collar, roll * CFrame.new(0, -0.1, 0.06))
	local cap = part("Kojiri", Vector3.new(0.23, 0.54, 0.14), GUARD, Enum.Material.Metal, model)
	weld(mouthPart, cap, roll * CFrame.new(0, -0.1, len - 0.05))
	-- the katana in it (its hilt sticks out of the mouth)
	local hilt = part("SheathedHilt", Vector3.new(0.16, 0.2, 1.05), WRAP, Enum.Material.Fabric, model)
	local w = weld(mouthPart, hilt, RoninLook.SheathedOffset(0))
	w.Name = "SheathWeld"
	dressBlade(hilt, model)
	-- (the blade's pieces are welded to the hilt, so the slide moves them all)
	model.PrimaryPart = mouthPart
	model.Parent = character
	return model
end

-- (client) Where the scabbard is: 0 = at the hip, 1 = in the left hand, between = on its way.
function RoninLook.SetMount(character: Model, alpha: number)
	local model = character:FindFirstChild("RoninScabbard")
	local mouthPart = model and model:FindFirstChild("Mouth")
	local w = mouthPart and mouthPart:FindFirstChild("ScabbardMount") :: Weld?
	local torso = character:FindFirstChild("Torso") :: BasePart?
	local arm = character:FindFirstChild("Left Arm") :: BasePart?
	if not w or not torso or not arm then return end
	if alpha >= 1 then
		if w.Part0 ~= arm then w.Part0 = arm end
		w.C0 = RoninLook.MouthOffset()
	elseif alpha <= 0 then
		if w.Part0 ~= torso then w.Part0 = torso end
		w.C0 = RoninLook.HIP
	else
		local hand = torso.CFrame:ToObjectSpace(arm.CFrame * RoninLook.MouthOffset())
		if w.Part0 ~= torso then w.Part0 = torso end
		w.C0 = RoninLook.HIP:Lerp(hand, alpha)
	end
end

function RoninLook.RemoveScabbard(character: Model)
	for _, d in ipairs(character:GetChildren()) do
		if d:GetAttribute("RoninLook") then d:Destroy() end
	end
end

-- (client) Slide the sheathed katana `slide` studs out of the mouth.
function RoninLook.SetSlide(character: Model, slide: number)
	local model = character:FindFirstChild("RoninScabbard")
	local hilt = model and model:FindFirstChild("SheathedHilt")
	local w = hilt and hilt:FindFirstChild("SheathWeld") :: Weld?
	if w then w.C0 = RoninLook.SheathedOffset(slide) end
end

return RoninLook
