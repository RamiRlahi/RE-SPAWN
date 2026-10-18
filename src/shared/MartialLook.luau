--!strict
--[[
	MartialLook.luau
	The Martial Artist's look, built in code (after the class portrait): a
	ragged black gi hanging open at the chest, a crimson sash knotted at the
	front with its long tails hanging, torn sleeves over bare arms, black
	braces striped red round the forearms (bare fists), baggy torn black
	trousers over white ankle wraps, black shoes with white soles. His own
	head, face and hair are his avatar's.

	The gi goes on over the avatar, not on top of its clothes: the avatar's
	shirt, trousers, body package (CharacterMesh) and anything it wears on
	the body (not the head) are put away while he wears it, even pieces that
	load in late. The bare chest is his own skin colour. Undress gives it all
	back.

	The sash's tails hang on Motor6Ds the client sways as he moves
	(MartialController).

	  Dress(char)     put it all on (safe to call again)
	  Undress(char)   take it off
--]]

local MartialLook = {}

local ATTR = "MartialLook" -- on everything added (cleanup)
local HID = "MartialHid"   -- on everything of the avatar's hidden (its old value)

local GI = Color3.fromRGB(18, 16, 20)
local GI_WORN = Color3.fromRGB(30, 27, 32)
local CRIMSON = Color3.fromRGB(176, 22, 28)
local CRIMSON_DARK = Color3.fromRGB(116, 12, 18)
local WRAP_WHITE = Color3.fromRGB(226, 222, 214)
local SHOE = Color3.fromRGB(20, 18, 18)
MartialLook.QI = Color3.fromRGB(255, 176, 60)

local function R(d: number): number return math.rad(d) end

local function piece(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3,
	material: Enum.Material?, shape: string?): BasePart
	local p: BasePart
	if shape == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
	end
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or Enum.Material.Fabric
	p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = base.CFrame * offset
	p:SetAttribute(ATTR, true)
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

-- A hanging tail on its own motor (the client sways it): `name` .. "Motor".
local function tail(model: Model, base: BasePart, name: string, at: CFrame, length: number, width: number, color: Color3)
	local hub = Instance.new("Part")
	hub.Name = name
	hub.Size = Vector3.new(width, length, 0.08)
	hub.Color = color
	hub.Material = Enum.Material.Fabric
	hub.CanCollide, hub.CanTouch, hub.CanQuery, hub.Massless, hub.CastShadow = false, false, false, true, false
	hub.CFrame = base.CFrame * at * CFrame.new(0, -length / 2, 0)
	hub:SetAttribute(ATTR, true)
	hub.Parent = model
	local m = Instance.new("Motor6D")
	m.Name = name .. "Motor"
	m.Part0 = base
	m.Part1 = hub
	m.C0 = at
	m.C1 = CFrame.new(0, length / 2, 0)
	m.Parent = hub
	-- (a frayed, darker end)
	piece(model, hub, name .. "Tip", Vector3.new(width + 0.01, 0.14, 0.09), CFrame.new(0, -length / 2 + 0.07, 0), CRIMSON_DARK)
	piece(model, hub, name .. "Fray", Vector3.new(0.08, width * 0.6, width * 0.6), CFrame.new(width * 0.2, -length / 2 - 0.06, 0)
		* CFrame.Angles(0, R(90), R(180)), CRIMSON_DARK, nil, "wedge")
end

-- A ragged hem: black teeth of torn cloth hanging along the bottom of a piece
-- (`across` studs wide, `count` teeth, at `at` in `base`'s space, facing -Z).
local function hem(model: Model, base: BasePart, name: string, at: CFrame, across: number, depth: number, count: number, color: Color3)
	for i = 1, count do
		local x = (i - 0.5) / count * across - across / 2
		local long = 0.22 + ((i * 37) % 5) * 0.05 -- (uneven lengths)
		piece(model, base, name, Vector3.new(0.06, long, across / count), at * CFrame.new(x, -long / 2, depth)
			* CFrame.Angles(0, R(90), R(180)), color, nil, "wedge")
	end
end

-- ── The avatar's own look: hidden while he's dressed ───────────────────────
local HEAD_ATTACH = { HatAttachment = true, HairAttachment = true, FaceFrontAttachment = true, FaceCenterAttachment = true }

-- A body package (CharacterMesh: the bigger, sculpted torso and limbs some
-- avatars have) would poke out through the gi: put aside while he's dressed.
local stashed: { [Model]: { Instance } } = setmetatable({}, { __mode = "k" }) :: any

local function hideAvatarPiece(d: Instance)
	if d:GetAttribute(ATTR) or d:GetAttribute(HID) ~= nil then return end
	if d:IsA("CharacterMesh") then
		local char = d.Parent :: Model
		stashed[char] = stashed[char] or {}
		table.insert(stashed[char], d)
		d.Parent = nil
	elseif d:IsA("Shirt") then
		d:SetAttribute(HID, d.ShirtTemplate)
		d.ShirtTemplate = ""
	elseif d:IsA("Pants") then
		d:SetAttribute(HID, d.PantsTemplate)
		d.PantsTemplate = ""
	elseif d:IsA("ShirtGraphic") then
		d:SetAttribute(HID, d.Graphic)
		d.Graphic = ""
	elseif d:IsA("Accessory") then
		-- (what's worn on the head stays: hats, hair, the face)
		local handle = d:FindFirstChild("Handle")
		for _, a in ipairs(if handle then handle:GetChildren() else {}) do
			if a:IsA("Attachment") and HEAD_ATTACH[a.Name] then return end
		end
		for _, x in ipairs(d:GetDescendants()) do
			if x:IsA("BasePart") and x:GetAttribute(HID) == nil then
				x:SetAttribute(HID, x.Transparency)
				x.Transparency = 1
			elseif x:IsA("Decal") and x:GetAttribute(HID) == nil then
				x:SetAttribute(HID, x.Transparency)
				x.Transparency = 1
			end
		end
		d:SetAttribute(HID, true)
	end
end

local watching: { [Model]: RBXScriptConnection } = setmetatable({}, { __mode = "k" }) :: any

local function hideAvatar(char: Model)
	for _, d in ipairs(char:GetChildren()) do hideAvatarPiece(d) end
	-- (the avatar's pieces can load in after he's dressed)
	if not watching[char] then
		watching[char] = char.ChildAdded:Connect(function(d)
			task.defer(function()
				if d.Parent == char then hideAvatarPiece(d) end
			end)
		end)
	end
end

local function restoreAvatar(char: Model)
	local conn = watching[char]
	if conn then
		conn:Disconnect()
		watching[char] = nil
	end
	local meshes = stashed[char]
	if meshes then
		stashed[char] = nil
		for _, m in ipairs(meshes) do m.Parent = char end
	end
	for _, d in ipairs(char:GetDescendants()) do
		local old = d:GetAttribute(HID)
		if old == nil then continue end
		if d:IsA("Shirt") and typeof(old) == "string" then
			d.ShirtTemplate = old
		elseif d:IsA("Pants") and typeof(old) == "string" then
			d.PantsTemplate = old
		elseif d:IsA("ShirtGraphic") and typeof(old) == "string" then
			d.Graphic = old
		elseif (d:IsA("BasePart") or d:IsA("Decal")) and typeof(old) == "number" then
			d.Transparency = old
		end
		d:SetAttribute(HID, nil)
	end
end

function MartialLook.Undress(char: Model)
	for _, d in ipairs(char:GetDescendants()) do
		if d:GetAttribute(ATTR) and d.Parent then
			d:Destroy()
		elseif d:IsA("Decal") and d:GetAttribute("MartialFace") ~= nil then
			d.Transparency = d:GetAttribute("MartialFace")
			d:SetAttribute("MartialFace", nil)
		end
	end
	restoreAvatar(char)
end

function MartialLook.Dress(char: Model)
	MartialLook.Undress(char)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not (head and torso) then return end
	hideAvatar(char)
	local model = Instance.new("Model")
	model.Name = "MartialGi"
	model:SetAttribute(ATTR, true)

	-- ── The body ──
	-- The gi: black, worn ragged, hanging open in a V down to the sash (the
	-- chest bare).
	local skinTone = torso.Color
	local bc = char:FindFirstChildOfClass("BodyColors")
	if bc then skinTone = bc.TorsoColor3 end
	local shade = skinTone:Lerp(Color3.new(0, 0, 0), 0.15)
	piece(model, torso, "Gi", Vector3.new(2.08, 2.02, 1.08), CFrame.new(0, 0, 0), GI)
	piece(model, torso, "Chest", Vector3.new(0.9, 1.2, 0.04), CFrame.new(0, 0.38, -0.555), skinTone)
	piece(model, torso, "ChestLine", Vector3.new(0.05, 0.6, 0.045), CFrame.new(0, 0.42, -0.565), shade)
	for _, sx in ipairs({ -1, 1 }) do
		-- the lapels: wide black panels crossing in, so the bare chest is a V
		piece(model, torso, "Lapel", Vector3.new(0.62, 1.5, 0.06), CFrame.new(sx * 0.52, 0.22, -0.57) * CFrame.Angles(0, 0, R(sx * -18)), GI_WORN)
		piece(model, torso, "Pec", Vector3.new(0.34, 0.05, 0.045), CFrame.new(sx * 0.2, 0.28, -0.565) * CFrame.Angles(0, 0, R(sx * 12)), shade)
		-- torn sleeves over the shoulders
		piece(model, torso, "GiShoulder", Vector3.new(1.1, 0.34, 1.12), CFrame.new(sx * 0.98, 0.9, 0), GI_WORN)
	end
	-- the gi's skirt below the sash, hanging ragged over the trousers
	hem(model, torso, "GiHem", CFrame.new(0, -1.0, 0), 2.08, -0.56, 7, GI)
	hem(model, torso, "GiHemBack", CFrame.new(0, -1.0, 0) * CFrame.Angles(0, math.pi, 0), 2.08, -0.56, 7, GI)

	-- The sash: crimson round the waist, knotted at the front, two long tails
	-- hanging down the front.
	piece(model, torso, "Sash", Vector3.new(2.14, 0.4, 1.14), CFrame.new(0, -0.8, 0), CRIMSON)
	piece(model, torso, "SashFold", Vector3.new(2.16, 0.06, 1.16), CFrame.new(0, -0.66, 0), CRIMSON_DARK)
	piece(model, torso, "SashKnot", Vector3.new(0.42, 0.38, 0.22), CFrame.new(0.05, -0.8, -0.64), CRIMSON_DARK)
	tail(model, torso, "SashTailA", CFrame.new(-0.06, -0.9, -0.68) * CFrame.Angles(R(-4), 0, R(4)), 1.9, 0.26, CRIMSON)
	tail(model, torso, "SashTailB", CFrame.new(0.18, -0.9, -0.66) * CFrame.Angles(R(-3), 0, R(-6)), 1.6, 0.24, CRIMSON)

	-- ── The arms ──
	-- Torn sleeves to above the elbow, the arm bare, black wraps striped red
	-- round the forearm, the fist bare.
	for _, side in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = char:FindFirstChild(side) :: BasePart?
		if not arm then continue end
		piece(model, arm, "Sleeve", Vector3.new(1.1, 0.62, 1.1), CFrame.new(0, 0.7, 0), GI)
		hem(model, arm, "SleeveHem", CFrame.new(0, 0.39, 0), 1.1, -0.56, 3, GI)
		hem(model, arm, "SleeveHemBack", CFrame.new(0, 0.39, 0) * CFrame.Angles(0, math.pi, 0), 1.1, -0.56, 3, GI)
		piece(model, arm, "Wraps", Vector3.new(1.06, 0.82, 1.06), CFrame.new(0, -0.42, 0), GI)
		for k = 0, 2 do
			piece(model, arm, "WrapStripe", Vector3.new(1.08, 0.07, 1.08), CFrame.new(0, -0.16 - k * 0.24, 0) * CFrame.Angles(0, 0, R(if k % 2 == 0 then 7 else -7)),
				CRIMSON)
		end
	end

	-- ── The legs ──
	-- Baggy torn black trousers, white wraps at the ankle, black shoes with
	-- white soles.
	for _, side in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = char:FindFirstChild(side) :: BasePart?
		if not leg then continue end
		piece(model, leg, "Trousers", Vector3.new(1.16, 1.5, 1.16), CFrame.new(0, 0.25, 0), GI)
		piece(model, leg, "TrouserCrease", Vector3.new(0.05, 1.2, 1.17), CFrame.new(0.2, 0.3, 0), GI_WORN)
		hem(model, leg, "TrouserHem", CFrame.new(0, -0.5, 0), 1.16, -0.59, 4, GI)
		hem(model, leg, "TrouserHemBack", CFrame.new(0, -0.5, 0) * CFrame.Angles(0, math.pi, 0), 1.16, -0.59, 4, GI)
		piece(model, leg, "AnkleWrap", Vector3.new(1.05, 0.3, 1.05), CFrame.new(0, -0.66, 0), WRAP_WHITE)
		piece(model, leg, "Shoe", Vector3.new(1.06, 0.26, 1.16), CFrame.new(0, -0.86, -0.05), SHOE, Enum.Material.Leather)
		piece(model, leg, "Sole", Vector3.new(1.08, 0.08, 1.18), CFrame.new(0, -0.97, -0.05), WRAP_WHITE, Enum.Material.SmoothPlastic)
	end
	model.Parent = char
end

return MartialLook
