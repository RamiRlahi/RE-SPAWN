--!strict
--[[
	SwordModel
	Builds the Sword Master's rapier as a Tool from parts (no uploaded asset).
	Shared by the server (the real weapon) and the class-select preview. The
	Tool keeps the name "Longsword" so the rest of the Swordsman code finds it.

	Handle space: the blade runs along -Z from the hand, and the Tool's Grip
	turns it to stick out of the fist (forward with the arm hanging, up with
	the arm raised). Named pieces the client uses:
	  BladeBase / BladeTip — Attachments on the blade for the swing trail
	  SwordTrail           — the white/blue swing Trail (off until a swing)

	To flip a sword point-down (planted), set tool.Grip =
	SwordModel.FlippedGrip(tool.Grip): it turns the handle 180° across the
	blade whatever the tool's own Grip is.
--]]


local SwordModel = {}

local STEEL = Color3.fromRGB(205, 212, 226)
local EDGE = Color3.fromRGB(240, 246, 255)
local SILVER = Color3.fromRGB(176, 184, 204)
local NAVY = Color3.fromRGB(22, 28, 58)
local GEM = Color3.fromRGB(90, 150, 255)

-- Slides the whole sword along the blade so the wrapped grip (not the guard)
-- sits in the fist. More negative = sword further toward its tip.
local HAND_OFFSET = -0.5
-- Sideways nudge into the palm (the hand's X axis). Negative = toward the
-- character's left (screen-right when they face the camera).
local HAND_SIDE = -0.35

local function piece(tool: Tool, handle: BasePart, name: string, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	local offset = props.Offset :: CFrame
	props.Offset = nil
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.CFrame = handle.CFrame * CFrame.new(HAND_SIDE, 0, HAND_OFFSET) * offset
	-- A Weld with its offset written down (not a WeldConstraint, which takes
	-- whatever offset there is when it switches on: if the grip has already
	-- moved the handle by then, the piece is left behind).
	local w = Instance.new("Weld")
	w.Part0 = handle
	w.Part1 = p
	w.C0 = CFrame.new(HAND_SIDE, 0, HAND_OFFSET) * offset
	w.Parent = p
	p.Parent = tool
	return p
end

function SwordModel.Build(): Tool
	local tool = Instance.new("Tool")
	tool.Name = "Longsword"
	tool.RequiresHandle = true
	tool.CanBeDropped = false
	-- Held in the fist, blade pointing forward (not along the arm): the grip
	-- turns the handle's -Z (blade) from "down the arm" to "out of the hand".
	tool.Grip = CFrame.Angles(math.rad(-90), 0, 0)
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

	local metal = Enum.Material.Metal
	-- Wire-wrapped grip and a ball pommel with a blue stone.
	piece(tool, handle, "Grip", { Size = Vector3.new(0.18, 0.18, 0.95), Offset = CFrame.new(0, 0, 0.15),
		Color = NAVY, Material = Enum.Material.Fabric })
	piece(tool, handle, "Pommel", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.32, Offset = CFrame.new(0, 0, 0.7),
		Color = SILVER, Material = metal })
	piece(tool, handle, "PommelGem", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.14, Offset = CFrame.new(0, 0, 0.84),
		Color = GEM, Material = Enum.Material.Neon })
	-- The swept hilt: a straight cross-guard, a cup over the hand, a knuckle
	-- bow curving from the guard to the pommel, and two side rings.
	piece(tool, handle, "Quillons", { Size = Vector3.new(1.3, 0.08, 0.08), Offset = CFrame.new(0, 0, -0.38),
		Color = SILVER, Material = metal })
	piece(tool, handle, "Cup", { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 0.62, 0.62),
		Offset = CFrame.new(0, 0, -0.42) * CFrame.Angles(0, math.rad(90), 0), Color = SILVER, Material = metal })
	for i = 0, 4 do
		local a = math.rad(-80 + i * 40)
		piece(tool, handle, "KnuckleBow" .. i, { Size = Vector3.new(0.06, 0.06, 0.3),
			Offset = CFrame.new(0, -0.32 * math.cos(a) - 0.05, 0.15 + 0.48 * math.sin(a)) * CFrame.Angles(-a, 0, 0),
			Color = SILVER, Material = metal })
	end
	for _, side in ipairs({ -1, 1 }) do
		for i = 0, 5 do
			local a = math.rad(i * 60)
			piece(tool, handle, "Ring" .. side .. "_" .. i, { Size = Vector3.new(0.05, 0.05, 0.16),
				Offset = CFrame.new(side * (0.3 + 0.14 * math.cos(a)), 0, -0.26 + 0.14 * math.sin(a)) * CFrame.Angles(0, math.rad(90) + a, 0),
				Color = SILVER, Material = metal })
		end
	end
	piece(tool, handle, "GuardGem", { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.16, Offset = CFrame.new(0, 0, -0.42),
		Color = GEM, Material = Enum.Material.Neon })
	-- The long, narrow blade: a squared ricasso, then the blade with a
	-- bright edge, tapering to a needle point.
	piece(tool, handle, "Ricasso", { Size = Vector3.new(0.14, 0.1, 0.5), Offset = CFrame.new(0, 0, -0.7),
		Color = STEEL, Material = metal })
	local blade = piece(tool, handle, "Blade", { Size = Vector3.new(0.12, 0.05, 3.9), Offset = CFrame.new(0, 0, -2.9),
		Color = STEEL, Material = metal, Reflectance = 0.2 })
	piece(tool, handle, "Edge", { Size = Vector3.new(0.15, 0.025, 3.8), Offset = CFrame.new(0, 0, -2.9),
		Color = EDGE, Material = metal, Reflectance = 0.35 })
	piece(tool, handle, "Tip", { Size = Vector3.new(0.07, 0.04, 0.4), Offset = CFrame.new(0, 0, -5.0),
		Color = EDGE, Material = metal })

	-- Swing trail along the blade, and the point (camera / thrust effects).
	local base = Instance.new("Attachment")
	base.Name = "BladeBase"
	base.Position = Vector3.new(0, 0, 1.6)
	base.Parent = blade
	local tip = Instance.new("Attachment")
	tip.Name = "BladeTip"
	tip.Position = Vector3.new(0, 0, -2.3)
	tip.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "SwordTrail"
	trail.Attachment0 = base
	trail.Attachment1 = tip
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = 0.18
	trail.MinLength = 0.02
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(170, 205, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 130, 255)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	trail.Enabled = false
	trail.Parent = blade

	return tool
end

-- The Grip that holds `grip`'s sword upside-down in the same hand (blade
-- reversed): turns the handle 180° about its X axis, across the blade.
function SwordModel.FlippedGrip(grip: CFrame): CFrame
	return CFrame.Angles(math.pi, 0, 0) * grip
end

return SwordModel
