--!strict
--[[
	DragonBuilder.luau
	Ignarath, the dragon boss, built out of parts (like the menu's sky castle):
	a crimson western dragon crouched on all fours, wings raised, horns swept
	back, jaws open in a snarl.

	Every limb is a jointed segment (an invisible core part carrying its
	sculpted pieces), joined by Motor6Ds so the clients can animate it:

	  Body ─ NeckBase ─ NeckMid ─ Neck ─ Head ─ Jaw
	       ├ LeftShoulder / RightShoulder (wing) ─ LeftElbow / RightElbow
	       ├ LeftArm / RightArm (foreleg) ─ LeftForearm / RightForearm
	       ├ LeftHip / RightHip (hind leg) ─ LeftKnee / RightKnee ─ LeftAnkle / RightAnkle
	       └ Tail1 ─ Tail2 ─ … ─ Tail7

	Frames: the body's +Z is forward, +Y up, +X its left. The model's pivot is
	the Body; `GroundOffset` (attribute) is how far the Body sits above the
	floor it crouches on.
--]]

local DragonBuilder = {}

-- ── Palette (from the concept art) ──────────────────────────────────────────
local RED = Color3.fromRGB(92, 22, 24)         -- the scales (dark maroon)
local RED_DARK = Color3.fromRGB(44, 34, 40)    -- the charcoal armour plates on top
local RED_HOT = Color3.fromRGB(150, 40, 30)    -- highlights, ridges
local BELLY = Color3.fromRGB(125, 36, 30)      -- the ridged underside
local MEMBRANE = Color3.fromRGB(140, 26, 24)   -- wing skin
local WING_BONE = Color3.fromRGB(40, 32, 38)
local BONE = Color3.fromRGB(150, 36, 30)       -- horn tips (dark red)
local BONE_DARK = Color3.fromRGB(38, 30, 36)   -- horn roots, spikes (charcoal)
local CLAW = Color3.fromRGB(232, 222, 200)
local TOOTH = Color3.fromRGB(240, 232, 212)
local EYE = Color3.fromRGB(255, 190, 60)
local MOUTH = Color3.fromRGB(255, 96, 18) -- a molten glow inside the jaws

local SCALES = Enum.Material.SmoothPlastic
-- The concept art is faceted, low-poly: "blobs" are built as angled blocks.
local FACETED = true
local SMOOTH = Enum.Material.SmoothPlastic

type Seg = BasePart

-- Parts on a segment can be scaled up about it (the head is sculpted at 1 and
-- built bigger).
local segScale: { [BasePart]: number } = {}
local function scaled(s: BasePart, at: CFrame): CFrame
	local k = segScale[s] or 1
	return CFrame.new(at.Position * k) * at.Rotation
end

-- ── Building blocks ─────────────────────────────────────────────────────────
local model: Model
local function base(p: BasePart, name: string, color: Color3, material: Enum.Material)
	p.Name = name
	p.Color = color
	p.Material = material
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = true
	p.Massless = true
	p.CastShadow = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
end

local function weldTo(seg: Seg, p: BasePart)
	local w = Instance.new("WeldConstraint")
	w.Part0 = seg
	w.Part1 = p
	w.Parent = p
	p.Parent = seg
end

-- A joint segment: an invisible core at `parent.CFrame * c0`, motored to it.
local function seg(name: string, parent: Seg?, c0: CFrame): Seg
	local p = Instance.new("Part")
	base(p, name, RED, SMOOTH)
	p.Size = Vector3.new(0.4, 0.4, 0.4)
	p.Transparency = 1
	p.CanQuery = false
	if parent then
		p.CFrame = parent.CFrame * c0
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Part0 = parent
		m.Part1 = p
		m.C0 = c0
		m.C1 = CFrame.identity
		m.Parent = parent
		p.Parent = model
	else
		p.CFrame = c0
		p.Parent = model
	end
	return p
end

-- An ellipsoid (a sphere mesh stretched to the part's size).
local function blob(s: Seg, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	base(p, name, color, material or SCALES)
	p.Size = size * (segScale[s] or 1)
	p.CFrame = s.CFrame * scaled(s, at)
	if FACETED then
		-- A block, a little smaller than the ellipsoid, turned 45° about its
		-- long axis so its edges catch the light like cut facets.
		local long = if size.Z >= size.X and size.Z >= size.Y then "Z" elseif size.Y >= size.X then "Y" else "X"
		p.Size = p.Size * 0.8
		p.CFrame *= if long == "Z" then CFrame.Angles(0, 0, math.rad(45)) elseif long == "Y" then CFrame.Angles(0, math.rad(45), 0) else CFrame.Angles(math.rad(45), 0, 0)
	else
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = p
	end
	weldTo(s, p)
	return p
end

local function box(s: Seg, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("Part")
	base(p, name, color, material or SCALES)
	p.Size = size * (segScale[s] or 1)
	p.CFrame = s.CFrame * scaled(s, at)
	weldTo(s, p)
	return p
end

local function wedge(s: Seg, name: string, size: Vector3, at: CFrame, color: Color3, material: Enum.Material?): BasePart
	local p = Instance.new("WedgePart")
	base(p, name, color, material or SCALES)
	p.Size = size * (segScale[s] or 1)
	p.CFrame = s.CFrame * scaled(s, at)
	weldTo(s, p)
	return p
end

-- A spike / horn tip: a corner wedge pointing along the frame's +Y.
local function spike(s: Seg, name: string, size: Vector3, at: CFrame, color: Color3): BasePart
	local p = Instance.new("CornerWedgePart")
	base(p, name, color, SMOOTH)
	p.Size = size * (segScale[s] or 1)
	p.CFrame = s.CFrame * scaled(s, at)
	weldTo(s, p)
	return p
end

-- A flat triangle a-b-c (segment-local points) from two wedges: wing skin.
local function tri(s: Seg, name: string, a: Vector3, b: Vector3, c: Vector3, color: Color3, thick: number)
	local k = segScale[s] or 1
	a, b, c = s.CFrame * (a * k), s.CFrame * (b * k), s.CFrame * (c * k)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab)
	if right.Magnitude < 1e-4 then return end
	right = right.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	for i, spec in ipairs({ { ab, a + b, 1 }, { ac, a + c, -1 } }) do
		local w = Instance.new("WedgePart")
		base(w, name, color, SMOOTH)
		local edge = spec[1] :: Vector3
		local k = spec[3] :: number
		w.Size = Vector3.new(thick, math.max(height, 0.05), math.max(math.abs(edge:Dot(back)), 0.05))
		w.CFrame = CFrame.fromMatrix((spec[2] :: Vector3) / 2, right * k, up, back * k)
		w.CastShadow = false
		weldTo(s, w)
		local _ = i
	end
end

-- A tapering chain of blobs from `from` along `dir` (a horn, a claw, a finger).
local function taper(s: Seg, name: string, from: Vector3, dirs: { Vector3 }, len: number, r0: number, r1: number, color: Color3, tipColor: Color3?)
	local k = segScale[s] or 1
	from, len, r0, r1 = from * k, len * k, r0 * k, r1 * k
	local p = from
	local n = #dirs
	local tipC = tipColor or color
	for i, d in ipairs(dirs) do
		local dir = d.Unit
		local l = len / n
		local r = r0 + (r1 - r0) * (i - 1) / math.max(n - 1, 1)
		local mid = p + dir * (l / 2)
		-- (placed in segment space already scaled: bypass the blob's scaling)
		local part = Instance.new("Part")
		base(part, name, color:Lerp(tipC, (i - 1) / math.max(n, 1)), SMOOTH)
		part.Size = Vector3.new(r, r, l * 1.9)
		part.CFrame = s.CFrame * CFrame.lookAt(mid, mid + dir)
		local mesh = Instance.new("SpecialMesh")
		mesh.MeshType = Enum.MeshType.Sphere
		mesh.Parent = part
		weldTo(s, part)
		p += dir * l
	end
	-- the point
	local tip = p
	local last = dirs[n].Unit
	local pt = Instance.new("Part")
	base(pt, name .. "Tip", tipC, SMOOTH)
	pt.Size = Vector3.new(r1 * 0.7, r1 * 0.7, r1 * 2.6)
	pt.CFrame = s.CFrame * CFrame.lookAt(tip + last * r1 * 0.5, tip + last * 2)
	local cone = Instance.new("SpecialMesh")
	cone.MeshType = Enum.MeshType.Sphere
	cone.Scale = Vector3.new(0.7, 0.7, 1)
	cone.Parent = pt
	weldTo(s, pt)
end

-- ── The dragon ──────────────────────────────────────────────────────────────
local R = math.rad
local HEAD_SCALE = 1.15

local function buildHead(head: Seg): Attachment
	-- Skull and snout: a long, angular reptile head.
	blob(head, "Skull", Vector3.new(4.6, 3.8, 5.4), CFrame.new(0, 0.5, 1.2), RED_DARK)
	blob(head, "Cheek", Vector3.new(5.2, 3, 3.4), CFrame.new(0, -0.2, 0.6), RED_DARK)
	blob(head, "Snout", Vector3.new(3.4, 2.3, 6.4), CFrame.new(0, 0.3, 4.9) * CFrame.Angles(R(-6), 0, 0), RED_DARK)
	wedge(head, "SnoutTop", Vector3.new(3.2, 1.4, 5.6), CFrame.new(0, 1.55, 4.6) * CFrame.Angles(R(-4), math.pi, 0), RED_DARK)
	blob(head, "NoseTip", Vector3.new(2.5, 1.4, 2.8), CFrame.new(0, 0.35, 7.3) * CFrame.Angles(R(10), 0, 0), RED)
	-- A ridge down the top of the snout.
	blob(head, "SnoutRidge", Vector3.new(0.9, 0.8, 5.6), CFrame.new(0, 1.55, 4.4) * CFrame.Angles(R(-8), 0, 0), RED_DARK)
	for _, sx in ipairs({ -1, 1 }) do
		blob(head, "Nostril", Vector3.new(0.3, 0.22, 0.6), CFrame.new(sx * 0.65, 1, 8.2) * CFrame.Angles(R(-20), R(sx * 20), 0), MOUTH, SMOOTH)
		-- Heavy brow ridge, angled down toward the snout, over a glowing eye.
		blob(head, "Brow", Vector3.new(1.2, 0.75, 3.6), CFrame.new(sx * 1.6, 1.95, 2.7) * CFrame.Angles(R(12), R(sx * 12), R(sx * -18)), RED)
		spike(head, "BrowSpike", Vector3.new(0.45, 1.3, 1.2), CFrame.new(sx * 1.9, 2.5, 0.9) * CFrame.Angles(R(-55), 0, R(sx * -25)), BONE_DARK)
		local eye = blob(head, "Eye", Vector3.new(0.5, 0.55, 1.2), CFrame.new(sx * 2.05, 1.5, 2.9) * CFrame.Angles(0, R(sx * 22), R(sx * -20)), EYE, Enum.Material.Neon)
		local light = Instance.new("PointLight")
		light.Color = EYE
		light.Brightness = 1.2
		light.Range = 6
		light.Parent = eye
		-- Cheek frill spikes.
		for i = 0, 2 do
			spike(head, "Frill", Vector3.new(0.5, 1.8 - i * 0.3, 1.3), CFrame.new(sx * (2.5 + i * 0.1), -0.4 - i * 0.6, -0.6 - i * 0.5)
				* CFrame.Angles(R(-60), 0, R(sx * -70)), BONE_DARK)
		end
		-- Upper fangs.
		for i = 0, 4 do
			spike(head, "Fang", Vector3.new(0.3, if i == 1 then 1.3 else 0.8, 0.35), CFrame.new(sx * (1.35 - i * 0.05), -0.75, 7.2 - i * 1.1)
				* CFrame.Angles(math.pi, 0, 0), TOOTH)
		end
		-- The crown: two great horns sweeping back, two lesser below them.
		taper(head, "Horn", Vector3.new(sx * 1.4, 2.1, 0.4), {
			Vector3.new(sx * 0.3, 0.8, -1), Vector3.new(sx * 0.28, 0.6, -1), Vector3.new(sx * 0.22, 0.4, -1),
			Vector3.new(sx * 0.15, 0.2, -1), Vector3.new(sx * 0.08, 0, -1), Vector3.new(sx * 0.03, -0.2, -1),
			Vector3.new(0, -0.35, -1),
		}, 10.5, 1.55, 0.4, BONE_DARK, BONE)
		taper(head, "Horn", Vector3.new(sx * 2.2, 0.8, -0.3), {
			Vector3.new(sx * 0.7, 0.2, -1), Vector3.new(sx * 0.55, 0.05, -1), Vector3.new(sx * 0.4, -0.1, -1),
			Vector3.new(sx * 0.25, -0.3, -1),
		}, 5.4, 1, 0.3, BONE_DARK, BONE)
	end
	-- A row of small crest spikes between the horns.
	for i = 0, 2 do
		spike(head, "Crest", Vector3.new(0.5, 1.3 - i * 0.2, 1.2), CFrame.new(0, 2.3 - i * 0.2, 0.6 - i * 1.1) * CFrame.Angles(R(-30), 0, 0), BONE_DARK)
	end
	-- The mouth: dark inside, beneath the snout.
	box(head, "Mouth", Vector3.new(1.8, 0.2, 4.4), CFrame.new(0, -0.6, 4.6), MOUTH, Enum.Material.Neon)
	local mouth = Instance.new("Attachment")
	mouth.Name = "DragonMouth"
	mouth.Position = Vector3.new(0, -0.6, 7.6) * (segScale[head] or 1)
	mouth.Parent = head
	return mouth
end

local function buildJaw(jaw: Seg)
	box(jaw, "LowerJaw", Vector3.new(2.9, 1, 6), CFrame.new(0, -0.35, 3.2) * CFrame.Angles(R(4), 0, 0), RED)
	wedge(jaw, "Chin", Vector3.new(2.9, 1.1, 5.4), CFrame.new(0, -1.3, 3) * CFrame.Angles(math.pi, math.pi, 0), RED_DARK)
	box(jaw, "Tongue", Vector3.new(1.6, 0.25, 4), CFrame.new(0, 0.15, 3.2), MOUTH, Enum.Material.Neon)
	for _, sx in ipairs({ -1, 1 }) do
		for i = 0, 4 do
			spike(jaw, "Fang", Vector3.new(0.28, if i == 0 then 1.1 else 0.7, 0.32), CFrame.new(sx * 1.2, 0.45, 5.7 - i * 1.1), TOOTH)
		end
		spike(jaw, "JawSpike", Vector3.new(0.5, 1.4, 1.1), CFrame.new(sx * 1.4, -1.1, 0.4) * CFrame.Angles(R(-120), 0, R(sx * -30)), BONE_DARK)
	end
end

-- A wing, built raised and spread in its own frame: +X runs out along the
-- arm, the skin lies in the X–Z plane, trailing back toward -Z.
local function buildWing(body: Seg, side: number): Seg
	-- side = 1 (left, +X) or -1 (right): the right wing's frame is turned
	-- half round about Z, so the same geometry mirrors.
	local raise = R(50)
	local c0 = CFrame.new(side * 3.6, 3.4, 3.2) * (if side == 1 then CFrame.Angles(0, 0, raise) else CFrame.Angles(0, 0, math.pi - raise))
	local name = if side == 1 then "Left" else "Right"
	-- The shoulder joint flaps about the body's length (its Z); a fixed twist
	-- below it turns the wing so its skin faces forward, open like a cape
	-- behind the dragon (as in the art), not edge-on.
	local shoulder = seg(name .. "Shoulder", body, c0)
	local upper = seg(name .. "WingTwist", shoulder, CFrame.Angles(side * R(-62), 0, 0))
	blob(upper, "WingArm", Vector3.new(10, 1.7, 1.9), CFrame.new(4.8, 0, 0), WING_BONE)
	blob(upper, "WingShoulder", Vector3.new(3.2, 2.6, 3.2), CFrame.new(0.6, 0, 0), RED_DARK)
	local elbowAt = Vector3.new(9.6, 0, 0)
	local elbowC0 = CFrame.new(elbowAt) * CFrame.Angles(0, R(-28), 0)
	local fore = seg(name .. "Elbow", upper, elbowC0)
	blob(fore, "WingForearm", Vector3.new(11.5, 1.3, 1.4), CFrame.new(5.6, 0, 0), WING_BONE)
	-- The thumb claw at the wrist.
	local wrist = Vector3.new(11.2, 0, 0)
	taper(fore, "WingClaw", wrist, { Vector3.new(0.6, 0, 1), Vector3.new(0.2, 0, 1) }, 2.2, 0.6, 0.3, BONE_DARK, CLAW)
	-- Four long fingers fanning back, and the skin between them.
	local fingers = { { 15, 4 }, { 18, 34 }, { 16, 66 }, { 12.5, 102 } }
	local tips: { Vector3 } = {}
	for i, f in ipairs(fingers) do
		local a = R(f[2])
		local dir = Vector3.new(math.cos(a), 0, -math.sin(a))
		local tip = wrist + dir * f[1]
		tips[i] = tip
		local mid = wrist + dir * (f[1] / 2)
		box(fore, "WingFinger", Vector3.new(0.4, 0.4, f[1]), CFrame.lookAt(mid, tip), WING_BONE, SMOOTH)
		taper(fore, "WingTip", tip - dir * 0.3, { dir }, 1.2, 0.4, 0.2, BONE_DARK, BONE_DARK)
	end
	for i = 1, #tips - 1 do
		-- Deeply scalloped: the skin between two fingers sags into a curve,
		-- with a few torn notches along its edge.
		local a, b = tips[i], tips[i + 1]
		local prev = a
		local STEPS = 6
		for s = 1, STEPS do
			local t = s / STEPS
			local chord = a:Lerp(b, t)
			local sag = math.sin(t * math.pi) * 0.45 -- how far the edge sags toward the wrist
			local pnt = chord:Lerp(wrist, sag)
			if s < STEPS and (s + i) % 3 == 0 then
				pnt = pnt:Lerp(wrist, 0.08) -- a tear
			end
			tri(fore, "WingSkin", wrist, prev, pnt, MEMBRANE, 0.12)
			prev = pnt
		end
	end
	-- The inner skin from the arm back to the flank (on the upper arm).
	local restTip4 = elbowC0 * tips[4]
	local restWrist = elbowC0 * wrist
	tri(upper, "WingSkin", Vector3.new(0.5, 0, 0), elbowAt, restWrist, MEMBRANE, 0.12)
	tri(upper, "WingSkin", Vector3.new(0.5, 0, 0), restWrist, restTip4, MEMBRANE, 0.12)
	tri(upper, "WingSkin", Vector3.new(0.5, 0, 0), restTip4, Vector3.new(1.2, 0, -10.5), MEMBRANE, 0.12)
	return upper
end

-- A foreleg: upper arm down and back, forearm forward, a clawed hand flat
-- on the floor. The leg's frame runs down its -Y.
local function buildForeleg(body: Seg, side: number)
	local name = if side == 1 then "Left" else "Right"
	local arm = seg(name .. "Arm", body, CFrame.new(side * 4, -1.2, 5.2) * CFrame.Angles(R(38), 0, R(side * -10)))
	blob(arm, "ArmMuscle", Vector3.new(4.4, 7.4, 4.8), CFrame.new(0, -2.6, 0), RED)
	blob(arm, "ArmScales", Vector3.new(3.2, 5.2, 3.4), CFrame.new(side * 0.5, -3, 1), RED_DARK)
	local fore = seg(name .. "Forearm", arm, CFrame.new(0, -5.6, 0) * CFrame.Angles(R(-78), 0, 0))
	blob(fore, "Forearm", Vector3.new(3.4, 6, 3.5), CFrame.new(0, -2.6, 0), RED)
	blob(fore, "ForearmShade", Vector3.new(2.6, 4.4, 2.6), CFrame.new(side * 0.5, -2.4, -0.7), RED_DARK)
	spike(fore, "ElbowSpike", Vector3.new(0.6, 2, 1.5), CFrame.new(0, 0.3, -1.5) * CFrame.Angles(R(-140), 0, 0), BONE_DARK)
	-- The hand, flat on the ground, claws splayed forward.
	local hand = CFrame.new(0, -5.2, 0) * CFrame.Angles(R(40), 0, 0)
	blob(fore, "Hand", Vector3.new(4.6, 1.6, 4.4), hand * CFrame.new(0, 0, 0.9), RED_DARK)
	for i = -1.5, 1.5 do
		local x = i * 1.15
		local from = (hand * CFrame.new(x, 0, 2.6)).Position
		local dir = (hand:VectorToWorldSpace(Vector3.new(x * 0.14, -0.2, 1)))
		taper(fore, "Claw", from, { dir, dir + Vector3.new(0, -0.7, 0) }, 3.4, 1, 0.45, RED_DARK, CLAW)
	end
end

-- A hind leg: a big haunch, the shin back, the foot down, claws forward.
local function buildHindleg(body: Seg, side: number)
	local name = if side == 1 then "Left" else "Right"
	local thigh = seg(name .. "Hip", body, CFrame.new(side * 4.4, -0.2, -6) * CFrame.Angles(R(-58), 0, R(side * -8)))
	blob(thigh, "Haunch", Vector3.new(6, 9, 8), CFrame.new(0, -2.4, 0.5), RED)
	blob(thigh, "HaunchShade", Vector3.new(4.4, 6.4, 6), CFrame.new(side * 1, -2.8, -0.2), RED_DARK)
	local shin = seg(name .. "Knee", thigh, CFrame.new(0, -6, 0) * CFrame.Angles(R(118), 0, 0))
	blob(shin, "Shin", Vector3.new(3, 5.6, 3.2), CFrame.new(0, -2.5, 0), RED)
	local foot = seg(name .. "Ankle", shin, CFrame.new(0, -5, 0) * CFrame.Angles(R(-66), 0, 0))
	blob(foot, "Foot", Vector3.new(2.2, 3.6, 2.2), CFrame.new(0, -1.6, 0), RED_DARK)
	local sole = CFrame.new(0, -3.3, 0.6) * CFrame.Angles(R(10), 0, 0)
	blob(foot, "Sole", Vector3.new(3, 1.1, 3.2), sole, RED_DARK)
	for i = -1, 1 do
		local from = (sole * CFrame.new(i * 0.9, 0, 1.4)).Position
		local dir = sole:VectorToWorldSpace(Vector3.new(i * 0.25, -0.2, 1))
		taper(foot, "Claw", from, { dir, dir + Vector3.new(0, -0.7, 0) }, 2.2, 0.65, 0.3, RED_DARK, CLAW)
	end
end

local function buildTail(body: Seg)
	-- Seven segments sweeping back, down, and curling round to one side.
	local c0 = CFrame.new(0, 0.6, -9.4) * CFrame.Angles(0, math.pi, 0) * CFrame.Angles(R(14), 0, 0)
	local parent = body
	local radius = 4.4
	for i = 1, 7 do
		local s = seg("Tail" .. i, parent, c0)
		local len = 5.8 - i * 0.35
		blob(s, "TailScales", Vector3.new(radius, radius * 0.92, len * 1.35), CFrame.new(0, 0, len / 2), RED)
		blob(s, "TailBelly", Vector3.new(radius * 0.7, radius * 0.5, len * 1.2), CFrame.new(0, -radius * 0.28, len / 2), BELLY)
		spike(s, "TailSpike", Vector3.new(0.45, 1.8 - i * 0.18, 1.5 - i * 0.1), CFrame.new(0, radius * 0.45, len * 0.4) * CFrame.Angles(R(-20), math.pi, 0), BONE_DARK)
		if i == 7 then
			-- A bladed tip.
			for _, sx in ipairs({ -1, 1 }) do
				wedge(s, "TailBlade", Vector3.new(0.25, 1.4, 3), CFrame.new(sx * 0.6, 0, len + 1.1) * CFrame.Angles(0, 0, R(sx * 90)), BONE_DARK, SMOOTH)
			end
			taper(s, "TailTip", Vector3.new(0, 0, len), { Vector3.zAxis }, 2.5, 0.8, 0.3, BONE_DARK, BONE)
		end
		parent = s
		c0 = CFrame.new(0, 0, len) * CFrame.Angles(R(5), R(19), 0)
		radius *= 0.82
	end
end

local function buildBody(body: Seg)
	-- The torso: chest heavy and high, belly ridged, haunches low.
	blob(body, "Torso", Vector3.new(8.6, 7.8, 17), CFrame.new(0, 0.2, -0.6), RED)
	blob(body, "Chest", Vector3.new(9.4, 9.2, 9), CFrame.new(0, 0.6, 4.8), RED)
	blob(body, "Back", Vector3.new(6.4, 4, 15), CFrame.new(0, 2.6, -0.4), RED_DARK)
	blob(body, "Belly", Vector3.new(6.8, 5.2, 14), CFrame.new(0, -1.9, 1), BELLY)
	blob(body, "Hips", Vector3.new(8.8, 7.4, 8), CFrame.new(0, 0.4, -6.4), RED)
	-- Belly plates.
	for i = 0, 6 do
		local z = 6.2 - i * 1.9
		box(body, "BellyPlate", Vector3.new(4.6 - math.abs(i - 3) * 0.3, 0.35, 1.2), CFrame.new(0, -4.35 + math.abs(i - 2.5) * 0.12, z) * CFrame.Angles(R(-8), 0, 0),
			Color3.fromRGB(190, 110, 78), SMOOTH)
	end
	-- Spikes along the spine.
	for i = 0, 7 do
		local z = 7.2 - i * 2.2
		local h = 2.6 - math.abs(i - 2) * 0.22
		spike(body, "SpineSpike", Vector3.new(0.6, h, 1.8), CFrame.new(0, 4.4 - math.abs(i - 3) * 0.12, z) * CFrame.Angles(R(-18), math.pi, 0), BONE_DARK)
	end
end

local function buildNeck(body: Seg): Seg
	-- Three segments: rising from the chest, arching over, head low and forward.
	local s1 = seg("NeckBase", body, CFrame.new(0, 2.6, 7.6) * CFrame.Angles(R(-42), 0, 0))
	blob(s1, "NeckScales", Vector3.new(5.2, 5.2, 7), CFrame.new(0, 0, 2.6), RED)
	blob(s1, "NeckThroat", Vector3.new(3.6, 3, 6.4), CFrame.new(0, -1.6, 2.6), BELLY)
	spike(s1, "NeckSpike", Vector3.new(0.5, 1.9, 1.5), CFrame.new(0, 2.5, 2.4) * CFrame.Angles(R(-18), math.pi, 0), BONE_DARK)
	local s2 = seg("NeckMid", s1, CFrame.new(0, 0, 5) * CFrame.Angles(R(24), 0, 0))
	blob(s2, "NeckScales", Vector3.new(4.4, 4.4, 6.2), CFrame.new(0, 0, 2.4), RED)
	blob(s2, "NeckThroat", Vector3.new(3, 2.6, 5.6), CFrame.new(0, -1.3, 2.4), BELLY)
	spike(s2, "NeckSpike", Vector3.new(0.5, 1.6, 1.4), CFrame.new(0, 2.1, 2.2) * CFrame.Angles(R(-18), math.pi, 0), BONE_DARK)
	local head = seg("Neck", s2, CFrame.new(0, 0, 4.8) * CFrame.Angles(R(30), 0, 0))
	head.Name = "Head"
	blob(head, "NeckTop", Vector3.new(3.8, 3.8, 3.6), CFrame.new(0, 0, -0.6), RED)
	return head
end

-- Build Ignarath at the origin (Body at `at`). Returns the model; its
-- PrimaryPart is the Body.
function DragonBuilder.Build(at: CFrame?): Model
	model = Instance.new("Model")
	model.Name = "Ignarath"
	local body = seg("Body", nil, at or CFrame.identity)
	body.Transparency = 1
	body.Size = Vector3.new(6, 6, 12)
	body.Massless = false
	model.PrimaryPart = body

	buildBody(body)
	local head = buildNeck(body)
	segScale[head] = HEAD_SCALE
	local mouth = buildHead(head)
	local jaw = seg("Jaw", head, CFrame.new(Vector3.new(0, -0.9, 1.2) * HEAD_SCALE) * CFrame.Angles(R(7), 0, 0))
	segScale[jaw] = HEAD_SCALE
	buildJaw(jaw)
	buildWing(body, 1)
	buildWing(body, -1)
	buildForeleg(body, 1)
	buildForeleg(body, -1)
	buildHindleg(body, 1)
	buildHindleg(body, -1)
	buildTail(body)

	-- Lit like the concept art in a dark dungeon: a warm glow over its body
	-- and an ember light from the throat.
	local glow = Instance.new("PointLight")
	glow.Name = "DragonGlow"
	glow.Color = Color3.fromRGB(255, 120, 80)
	glow.Brightness = 0.8
	glow.Range = 34
	glow.Shadows = false
	glow.Parent = body
	local top = Instance.new("Attachment")
	top.Name = "KeyLight"
	top.Position = Vector3.new(0, 16, 14)
	top.Parent = body
	local key = Instance.new("SpotLight")
	key.Color = Color3.fromRGB(255, 170, 120)
	key.Brightness = 1.4
	key.Range = 40
	key.Angle = 80
	key.Face = Enum.NormalId.Bottom
	key.Parent = top
	local ember = Instance.new("PointLight")
	ember.Color = Color3.fromRGB(255, 110, 30)
	ember.Brightness = 1.2
	ember.Range = 12
	ember.Parent = head

	-- For the boss code: a humanoid (health), its root, and the mouth.
	local root = Instance.new("Part")
	base(root, "Root", RED, SMOOTH)
	root.Size = Vector3.new(6, 6, 12)
	root.Transparency = 1
	root.CanQuery = false
	root.CFrame = body.CFrame
	local rj = Instance.new("Motor6D")
	rj.Name = "Root"
	rj.Part0 = body
	rj.Part1 = root
	rj.Parent = body
	root.Parent = model
	local hum = Instance.new("Humanoid")
	hum.Parent = model
	local fire = Instance.new("Attachment")
	fire.Name = "Fire"
	fire.Position = mouth.Position
	fire.Parent = head

	local sounds = {
		{ "Roar1", "rbxassetid://7127123487", head }, { "Roar2", "rbxassetid://7127123554", head },
		{ "Charge", "rbxassetid://5868574236", head }, { "Wing", "rbxassetid://9120771266", body },
	}
	for _, s in ipairs(sounds) do
		local snd = Instance.new("Sound")
		snd.Name = s[1] :: string
		snd.SoundId = s[2] :: string
		snd.Parent = s[3] :: Instance
	end

	-- How high the Body sits above the floor under its feet.
	local cf, size = model:GetBoundingBox()
	local lowest = math.huge
	for _, p in ipairs(model:GetDescendants()) do
		if p:IsA("BasePart") and (p.Name == "Hand" or p.Name == "Sole") then
			lowest = math.min(lowest, p.Position.Y - p.Size.Y * 0.5)
		end
	end
	if lowest == math.huge then lowest = cf.Position.Y - size.Y / 2 end
	model:SetAttribute("GroundOffset", body.Position.Y - lowest)
	return model
end

return DragonBuilder
