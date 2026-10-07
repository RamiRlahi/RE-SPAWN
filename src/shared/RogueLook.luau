--!strict
--[[
	RogueLook.luau
	The Rogue's gear, built in code:
	  BuildDagger()   "Shadowfang": a plain steel combat knife held point
	                  forward, with a white swing trail (DaggerTrail).
	  BuildBlade()    the knife itself (the thrown one is the same).
	  Dress(char)     nothing any more (no hood); clears an old one.
--]]

local RogueLook = {}

local BLACK = Color3.fromRGB(18, 14, 20)
local WHITE = Color3.new(1, 1, 1)

local function piece(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material, props: { [string]: any }?): BasePart
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
	for k, v in pairs(props or {}) do (p :: any)[k] = v end
	p.CFrame = base.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

local function wedge(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3, material: Enum.Material): BasePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Size = size
	w.Color = color
	w.Material = material
	w.CanCollide, w.CanTouch, w.CanQuery, w.Massless, w.CastShadow = false, false, false, true, false
	w.CFrame = base.CFrame * offset
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = base, w
	weld.Parent = w
	w.Parent = parent
	return w
end

-- "Shadowfang", built onto `base` (the handle: the blade runs out along its
-- -Z, flat side up): a plain combat knife. A blade of worn steel with an
-- angled point, a brighter bevel along the edge, a short black guard, a black
-- grip with two steel rivets and a steel butt cap. No glow: it's just a knife.
-- Returns the blade body (for the trail).
local STEEL_DARK = Color3.fromRGB(118, 120, 128)
local STEEL_BRIGHT = Color3.fromRGB(196, 198, 206)
local GRIP = Color3.fromRGB(22, 22, 25)
local TIP_R = CFrame.Angles(0, 0, math.rad(90))  -- a wedge laid flat, its straight side on +X
function RogueLook.BuildBlade(parent: Instance, base: BasePart): BasePart
	-- Grip, rivets, butt cap.
	piece(parent, base, "Grip", Vector3.new(0.17, 0.2, 0.8), CFrame.new(0, 0, 0.25), GRIP, Enum.Material.SmoothPlastic)
	for _, z in ipairs({ 0.05, 0.42 }) do
		piece(parent, base, "Rivet", Vector3.new(0.06, 0.21, 0.06), CFrame.new(0, 0, z), STEEL_BRIGHT, Enum.Material.Metal)
	end
	piece(parent, base, "ButtCap", Vector3.new(0.19, 0.22, 0.1), CFrame.new(0, 0, 0.68), STEEL_DARK, Enum.Material.Metal)
	-- Guard.
	piece(parent, base, "Guard", Vector3.new(0.36, 0.24, 0.08), CFrame.new(0, 0, -0.18), GRIP, Enum.Material.Metal)
	-- Blade: the body, the bevel along the edge (+X), the spine (-X).
	local blade = piece(parent, base, "Blade", Vector3.new(0.24, 0.05, 1.3), CFrame.new(0, 0, -0.87), STEEL_DARK, Enum.Material.Metal,
		{ Reflectance = 0.15 })
	piece(parent, base, "Bevel", Vector3.new(0.09, 0.055, 1.3), CFrame.new(0.08, 0, -0.87), STEEL_BRIGHT, Enum.Material.Metal,
		{ Reflectance = 0.3 })
	-- The point: the edge runs on to it, the spine slopes in to meet it.
	wedge(parent, base, "TipEdge", Vector3.new(0.05, 0.16, 0.5), CFrame.new(0.04, 0, -1.77) * TIP_R, STEEL_BRIGHT, Enum.Material.Metal)
	wedge(parent, base, "TipSpine", Vector3.new(0.05, 0.08, 0.32), CFrame.new(-0.08, 0, -1.68) * TIP_R, STEEL_DARK, Enum.Material.Metal)
	return blade
end

-- Where the fist holds the knife (handle space: +Z runs down the grip to
-- the butt, +X toward the edge, +Y the flat). Nudge this to seat it better.
local GRIP_AT = Vector3.new(0.04, 0.1, 0.32)

function RogueLook.BuildDagger(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Shadowfang"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- Held in the fist, the blade out of the hand (along the handle's -Z).
	-- GRIP_AT is the point of the handle (handle space) that sits in the fist:
	-- the middle of the grip, not the guard, so the fist closes round it.
	tool.Grip = CFrame.new(GRIP_AT) * CFrame.Angles(math.rad(-90), 0, 0)
	tool:SetAttribute("BladeAxis", "-Z")

	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.2, 0.2, 0.2)
	handle.Transparency = 1
	handle.CanCollide = false
	handle.CanTouch = false
	handle.CanQuery = false
	handle.Massless = true
	handle.CFrame = CFrame.new(0, 50, 0)
	handle.Parent = tool

	local blade = RogueLook.BuildBlade(tool, handle)

	local a0 = Instance.new("Attachment")
	a0.Name = "BladeBase"
	a0.Position = Vector3.new(0, 0, 0.6)
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "BladeTip"
	a1.Position = Vector3.new(0, 0, -1.0)
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "DaggerTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = 0.2
	trail.Color = ColorSequence.new(WHITE, Color3.fromRGB(120, 120, 126))
	trail.Transparency = NumberSequence.new(0.15, 1)
	trail.Enabled = false
	trail.Parent = blade
	return tool
end

-- The hood. Safe to call again (the old ones go first).
-- The Rogue wears no hood (the hair shows; the scarf over the mouth is
-- RogueScarf's, on the client). This only takes off anything an older
-- version put on.
function RogueLook.Dress(character: Model)
	for _, d in ipairs(character:GetChildren()) do
		if d:GetAttribute("RogueLook") then d:Destroy() end
	end
end

return RogueLook
