--[[
	IceCape.luau
	The Ice Mage's cape, built from parts so it needs no uploaded mesh.

	  • Five fabric rows (deep navy outside, pale ice lining) that widen toward
	    the hem, each hung from the one above by a Motor6D named "CapeJoint".
	    The client's CapeController animates those joints (billow, flutter).
	  • White fur collar across the shoulders with crystal clasps.
	  • Frost-trimmed edges and a jagged hem of icicles that glitter.

	Built for R6 (hangs from Torso); falls back to UpperTorso on R15.
--]]

local IceCape = {}

local NAVY = Color3.fromRGB(20, 32, 68)
local NAVY_DARK = Color3.fromRGB(12, 20, 44)
local LINING = Color3.fromRGB(160, 205, 240)
local FROST = Color3.fromRGB(120, 220, 255)
local FUR = Color3.fromRGB(235, 242, 250)
local ICE = Color3.fromRGB(190, 240, 255)

local ROWS = 5
local ROW_LEN = 0.74
local TOP_WIDTH = 2.3
local BOTTOM_WIDTH = 3.3
local THICK = 0.1

local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function weld(a: BasePart, b: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = a, b
	w.Parent = b
end

function IceCape.Attach(character: Model)
	local torso = (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
	if not torso then return end
	local old = character:FindFirstChild("IceCape")
	if old then old:Destroy() end

	-- Built unparented: every part gets its rest pose before any joint is live,
	-- so nothing tugs on the character's assembly while assembling.
	local model = Instance.new("Model")
	model.Name = "IceCape"

	-- Hang point: top of the back, just behind the shoulders (+Z is the back).
	local hang = CFrame.new(0, torso.Size.Y * 0.45, torso.Size.Z * 0.5 + 0.08)

	local prev: BasePart = torso
	local prevCF = torso.CFrame
	local prevC0 = hang
	local joints = {}
	for i = 1, ROWS do
		local k = (i - 0.5) / ROWS
		local width = TOP_WIDTH + (BOTTOM_WIDTH - TOP_WIDTH) * k
		local row = part(model, {
			Name = `CapeRow{i}`,
			Size = Vector3.new(width, ROW_LEN, THICK),
			Color = i % 2 == 0 and NAVY or NAVY_DARK,
			Material = Enum.Material.Fabric,
		})
		-- Pale ice lining on the inner face (toward the body, -Z).
		local lining = part(model, {
			Name = "Lining",
			Size = Vector3.new(width - 0.08, ROW_LEN, 0.04),
			Color = LINING,
			Material = Enum.Material.SmoothPlastic,
			CastShadow = false,
		})
		lining.CFrame = CFrame.new() -- positioned after the motor places the row
		-- Frost trim down both edges.
		local trims = {}
		for side = -1, 1, 2 do
			trims[side] = part(model, {
				Name = "FrostTrim",
				Size = Vector3.new(0.1, ROW_LEN + 0.02, THICK + 0.04),
				Color = FROST,
				Material = Enum.Material.Neon,
				Transparency = 0.15,
				CastShadow = false,
			})
		end

		local joint = Instance.new("Motor6D")
		joint.Name = "CapeJoint"
		joint.Part0 = prev
		joint.Part1 = row
		joint.C0 = prevC0
		joint.C1 = CFrame.new(0, ROW_LEN * 0.5, 0) -- top edge of this row
		table.insert(joints, joint)

		-- Rest pose, computed rather than read back from a live assembly.
		local rowCF = prevCF * joint.C0 * joint.C1:Inverse()
		row.CFrame = rowCF
		prevCF = rowCF
		lining.CFrame = row.CFrame * CFrame.new(0, 0, -THICK * 0.5 - 0.02)
		weld(row, lining)
		for side, trim in pairs(trims) do
			trim.CFrame = row.CFrame * CFrame.new(side * (width * 0.5 - 0.02), 0, 0)
			weld(row, trim)
		end

		prev = row
		prevC0 = CFrame.new(0, -ROW_LEN * 0.5, 0) -- bottom edge of this row
		row:SetAttribute("CapeRow", i)
	end

	-- Jagged icicle hem under the last row.
	local last = prev
	local hemWidth = BOTTOM_WIDTH
	local teeth = 9
	for t = 1, teeth do
		local x = -hemWidth * 0.5 + (t - 0.5) * (hemWidth / teeth)
		local len = (t % 2 == 0) and 0.55 or 0.9
		local icicle = part(model, {
			ClassName = "WedgePart",
			Name = "Icicle",
			Size = Vector3.new(0.06, len, hemWidth / teeth * 0.9),
			Color = ICE,
			Material = Enum.Material.Glass,
			Transparency = 0.2,
			Reflectance = 0.2,
		})
		-- Wedge rotated so its point hangs downward.
		icicle.CFrame = last.CFrame * CFrame.new(x, -ROW_LEN * 0.5 - len * 0.5, 0) * CFrame.Angles(0, math.rad(90), math.rad(180))
		weld(last, icicle)
	end
	local hemGlow = part(model, {
		Name = "HemGlow",
		Size = Vector3.new(hemWidth, 0.08, THICK + 0.05),
		Color = FROST,
		Material = Enum.Material.Neon,
		CastShadow = false,
	})
	hemGlow.CFrame = last.CFrame * CFrame.new(0, -ROW_LEN * 0.5, 0)
	weld(last, hemGlow)
	local a = Instance.new("Attachment")
	a.Parent = hemGlow
	local glitter = Instance.new("ParticleEmitter")
	glitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glitter.Color = ColorSequence.new(Color3.new(1, 1, 1), FROST)
	glitter.LightEmission = 1
	glitter.LightInfluence = 0
	glitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
	glitter.Lifetime = NumberRange.new(0.5, 1)
	glitter.Speed = NumberRange.new(0.3, 1)
	glitter.SpreadAngle = Vector2.new(180, 180)
	glitter.Acceleration = Vector3.new(0, -2, 0)
	glitter.Rate = 6
	glitter.Parent = a

	-- Fur collar: an arc of fluffy tufts across the shoulders.
	for i = 1, 9 do
		local u = (i - 5) / 4 -- -1 .. 1
		local x = u * torso.Size.X * 0.55
		local z = 0.15 - u * u * 0.45 -- centre sits over the back, ends curl toward the chest
		local s = 0.62 - math.abs(u) * 0.12
		local tuft = part(model, {
			Name = "FurTuft",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s * 0.85, s),
			Color = FUR,
			Material = Enum.Material.Fabric,
			CastShadow = false,
		})
		tuft.CFrame = torso.CFrame * CFrame.new(x, torso.Size.Y * 0.5 + 0.02, z)
		weld(torso, tuft)
	end
	-- Crystal clasps on the front of each shoulder.
	for side = -1, 1, 2 do
		local clasp = part(model, {
			Name = "CrystalClasp",
			Size = Vector3.new(0.34, 0.34, 0.2),
			Color = FROST,
			Material = Enum.Material.Neon,
			CastShadow = false,
		})
		clasp.CFrame = torso.CFrame * CFrame.new(side * torso.Size.X * 0.34, torso.Size.Y * 0.38, -torso.Size.Z * 0.5 - 0.08) * CFrame.Angles(0, 0, math.rad(45))
		weld(torso, clasp)
		local l = Instance.new("PointLight")
		l.Color, l.Brightness, l.Range, l.Shadows = FROST, 0.6, 5, false
		l.Parent = clasp
	end

	-- Go live: connect the joints, then attach to the character.
	for _, j in ipairs(joints) do
		j.Parent = j.Part1
	end
	model.Parent = character
	return model
end

return IceCape
