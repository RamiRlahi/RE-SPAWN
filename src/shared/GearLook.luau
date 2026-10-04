--!strict
--[[
	GearLook.luau
	Puts Armory gear (GearData) on a character or a weapon. Used on the server
	for real characters (everyone sees them) and on clients for the menu's
	copies (the hero, the party round the campfire).

	  GearLook.Weapon(container, itemId?)    a weapon finish on a weapon (a Tool or a Model)
	  GearLook.Aura(character, itemId?)      an aura on a character (nil: none)
	  GearLook.Nameplate(character, name, titleItemId?, shown)   the name and title over its head
--]]

local GearData = require(script.Parent:WaitForChild("GearData"))

local GearLook = {}

-- ── Weapon finishes ───────────────────────────────────────────────────────
-- The biggest pieces take the finish's metal and colour, the small ones its
-- trim; anything that glows (neon, a swing trail) takes its glow.
function GearLook.Weapon(container: Instance, itemId: string?)
	local item = GearData.Get(itemId)
	if not item or item.slot ~= "weapon" then return end
	local parts: { BasePart } = {}
	local biggest = 0
	for _, d in ipairs(container:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			table.insert(parts, d)
			biggest = math.max(biggest, d.Size.Magnitude)
		end
	end
	for _, p in ipairs(parts) do
		-- (a texture or SurfaceAppearance would hide the new colour)
		if p:IsA("MeshPart") then pcall(function() (p :: MeshPart).TextureID = "" end) end
		for _, c in ipairs(p:GetChildren()) do
			if c:IsA("SurfaceAppearance") or c:IsA("Decal") or c:IsA("Texture") then c:Destroy() end
		end
		local sm = p:FindFirstChildOfClass("SpecialMesh")
		if sm then sm.TextureId = "" end
		if p.Material == Enum.Material.Neon then
			if item.glow then p.Color = item.glow end
		elseif p.Size.Magnitude >= biggest * 0.45 then
			p.Color = item.color or p.Color
			p.Material = item.material or p.Material
		else
			p.Color = item.trim or item.color or p.Color
			if item.material == Enum.Material.Foil or item.material == Enum.Material.Metal then p.Material = Enum.Material.Metal end
		end
	end
	if item.glow then
		for _, d in ipairs(container:GetDescendants()) do
			if d:IsA("Trail") then d.Color = ColorSequence.new(Color3.new(1, 1, 1), item.glow) end
			if d:IsA("PointLight") or d:IsA("SpotLight") then (d :: any).Color = item.glow end
		end
		-- a faint edge light on the blade
		local blade: BasePart? = nil
		for _, p in ipairs(parts) do
			if not blade or p.Size.Magnitude > blade.Size.Magnitude then blade = p end
		end
		if blade and not blade:FindFirstChild("GearGlow") then
			local l = Instance.new("PointLight")
			l.Name = "GearGlow"
			l.Color = item.glow
			l.Range = 5
			l.Brightness = 0.8
			l.Shadows = false
			l.Parent = blade
			if item.sparkle then
				local e = Instance.new("ParticleEmitter")
				e.Name = "GearSparkle"
				e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
				e.Color = ColorSequence.new(item.glow)
				e.LightEmission = 1
				e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.18), NumberSequenceKeypoint.new(1, 0) })
				e.Lifetime = NumberRange.new(0.5, 0.9)
				e.Speed = NumberRange.new(0.3, 1)
				e.SpreadAngle = Vector2.new(180, 180)
				e.Rate = 6
				e.Parent = blade
			end
		end
	end
end

-- ── Auras ─────────────────────────────────────────────────────────────────
local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0.3
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local function seq(...: number): NumberSequence
	local v = { ... }
	local pts = {}
	for i, x in ipairs(v) do table.insert(pts, NumberSequenceKeypoint.new((i - 1) / math.max(1, #v - 1), x)) end
	return NumberSequence.new(pts)
end

-- An invisible part welded to the root, for an aura to rise from: a disc at
-- the feet, or a shell round the body. (An emitter on an attachment fires
-- from a single point; one on a part fills its shape.)
local function auraPart(root: BasePart, name: string, size: Vector3, offset: CFrame): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Transparency = 1
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.CFrame = root.CFrame * offset
	p.Parent = root
	local w = Instance.new("WeldConstraint")
	w.Part0 = root
	w.Part1 = p
	w.Parent = p
	return p
end

-- A little solid piece of an aura (an ice crystal, a star point), welded so
-- it rides along with the character.
local function piece(parent: BasePart, weldTo: BasePart, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	local w = Instance.new("WeldConstraint")
	w.Part0 = weldTo
	w.Part1 = p
	w.Parent = p
	return p
end

-- A beam between two points on aura parts: textures scroll along it on
-- their own (TextureSpeed), so it moves without any script.
local function beam(from: BasePart, fromPos: Vector3, to: BasePart, toPos: Vector3, props: { [string]: any }): Beam
	local a0 = Instance.new("Attachment")
	a0.Position = fromPos
	a0.Parent = from
	local a1 = Instance.new("Attachment")
	a1.Position = toPos
	a1.Parent = to
	local b = Instance.new("Beam")
	b.Attachment0, b.Attachment1 = a0, a1
	b.FaceCamera = true
	b.LightInfluence = 0
	b.TextureMode = Enum.TextureMode.Wrap
	for k, v in pairs(props) do (b :: any)[k] = v end
	b.Parent = from
	return b
end

local GLOW = "rbxasset://textures/particles/forcefield_glow_main.dds"
local VORTEX = "rbxasset://textures/particles/forcefield_vortex_main.dds"
local FIRE_SPARK = "rbxasset://textures/particles/fire_sparks_main.dds"
local RING = "rbxasset://textures/particles/explosion01_shockwave_main.dds"
local FLAT = Enum.ParticleOrientation.VelocityPerpendicular -- (moving straight up: lies flat on the ground)

function GearLook.Aura(character: Model, itemId: string?)
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	for _, name in ipairs({ "GearAura", "GearAuraFeet", "GearAuraBody" }) do
		local old = root:FindFirstChild(name)
		if old then old:Destroy() end
	end
	local head = character:FindFirstChild("Head")
	local oldHalo = head and head:FindFirstChild("GearHalo")
	if oldHalo then oldHalo:Destroy() end
	local item = GearData.Get(itemId)
	if not item or item.slot ~= "aura" then return end
	local c = item.auraColor or Color3.new(1, 1, 1)
	local feet = auraPart(root, "GearAuraFeet", Vector3.new(3.4, 0.2, 3.4), CFrame.new(0, -2.8, 0))
	local body = auraPart(root, "GearAuraBody", Vector3.new(3.2, 5.2, 3.2), CFrame.new(0, -0.2, 0))
	local kind = item.aura
	local BOX = Enum.ParticleEmitterShape.Box
	local VOLUME = Enum.ParticleEmitterShapeStyle.Volume
	local SURFACE = Enum.ParticleEmitterShapeStyle.Surface
	local headPart: BasePart? = if head and head:IsA("BasePart") then head else nil

	-- A flat ring of light pulsing out from the feet.
	local function groundPulse(texture: string, color: Color3, rate: number, from: number, to: number, transparency: number)
		emitter(feet, { Texture = texture, Color = ColorSequence.new(color), LightEmission = 1, Orientation = FLAT,
			Size = seq(from, to), Transparency = seq(transparency, 1), Lifetime = NumberRange.new(1.4, 1.4),
			Speed = NumberRange.new(0.01, 0.01), SpreadAngle = Vector2.zero, Rate = rate, EmissionDirection = Enum.NormalId.Top })
	end
	-- Things placed in a circle round the feet.
	local function around(n: number, r: number, fn: (number, Vector3) -> ())
		for i = 1, n do
			local a = i / n * math.pi * 2
			fn(a, Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		end
	end

	if kind == "dust" then
		-- Grave Dust: low dust rolling along the ground, specks drifting up.
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(c), Transparency = seq(0.55, 0.75, 1), Size = seq(1.6, 3.4),
			Lifetime = NumberRange.new(2, 3), Speed = NumberRange.new(0.6, 1.4), Drag = 1.5, SpreadAngle = Vector2.new(80, 10), Rate = 7,
			Acceleration = Vector3.new(0, -0.3, 0), Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Front })
		emitter(feet, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 0.2, Size = seq(0.12, 0),
			Lifetime = NumberRange.new(2, 3.5), Speed = NumberRange.new(0.2, 0.6), Rate = 6, Acceleration = Vector3.new(0, 0.4, 0),
			Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Top })
	elseif kind == "embers" then
		-- Embers: sparks spiralling up fast, a pulsing heat ring, a warm glow.
		emitter(feet, { Texture = FIRE_SPARK, Color = ColorSequence.new(Color3.fromRGB(255, 235, 150), c), LightEmission = 1, Size = seq(0.5, 0.3, 0),
			Lifetime = NumberRange.new(1, 1.8), Speed = NumberRange.new(3, 6), Acceleration = Vector3.new(0.8, 2.5, 0.5), SpreadAngle = Vector2.new(25, 25),
			RotSpeed = NumberRange.new(-200, 200), Rate = 28, Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Top })
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 1, Size = seq(0.18, 0), Lifetime = NumberRange.new(0.4, 0.8),
			Speed = NumberRange.new(1, 3), Rate = 10, Shape = BOX, ShapeStyle = SURFACE })
		groundPulse(RING, c, 1.2, 2, 6, 0.4)
		local l = Instance.new("PointLight")
		l.Color, l.Range, l.Brightness, l.Shadows = c, 9, 1.2, false
		l.Parent = feet
	elseif kind == "frost" then
		-- Frost Mist: a ring of ice crystals, mist pouring outward, snow falling.
		around(7, 1.9, function(a, offset)
			local h = 0.8 + (math.floor(a * 10) % 3) * 0.35
			piece(feet, root, { Size = Vector3.new(0.3, h, 0.3), Material = Enum.Material.Ice, Color = Color3.fromRGB(190, 230, 255), Transparency = 0.15,
				CFrame = feet.CFrame * CFrame.new(offset + Vector3.new(0, h / 2, 0)) * CFrame.Angles(math.rad(14), a, math.rad(10)) })
		end)
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(Color3.new(1, 1, 1), c), Transparency = seq(0.35, 0.7, 1), Size = seq(1.2, 3.6),
			Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(1.2, 2), Drag = 1.2, SpreadAngle = Vector2.new(180, 5), Rate = 12,
			Acceleration = Vector3.new(0, -0.6, 0), Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Top })
		local sky = auraPart(root, "GearAura", Vector3.new(5, 0.2, 5), CFrame.new(0, 4, 0))
		emitter(sky, { Texture = SPARK, Color = ColorSequence.new(Color3.new(1, 1, 1)), LightEmission = 0.6, Size = seq(0.22, 0.18),
			Lifetime = NumberRange.new(2.5, 3.5), Speed = NumberRange.new(0.6, 1), Acceleration = Vector3.new(0.3, -1.2, 0), RotSpeed = NumberRange.new(-60, 60),
			Rate = 10, Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Bottom })
	elseif kind == "holy" then
		-- Holy Motes: a golden ring of light, light pillars, orbiting motes.
		groundPulse(GLOW, c, 2, 4.5, 5.2, 0.35)
		groundPulse(RING, Color3.new(1, 1, 1), 0.7, 1, 6, 0.5)
		around(6, 1.8, function(_, offset)
			beam(feet, offset, body, offset * 0.8 + Vector3.new(0, 3.4, 0), { Texture = SPARK, TextureSpeed = 0.6, TextureLength = 2,
				Color = ColorSequence.new(c), LightEmission = 1, Width0 = 0.35, Width1 = 0.05,
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) }) })
		end)
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 1, Size = seq(0.5, 0.45, 0),
			Lifetime = NumberRange.new(1.6, 2.6), Speed = NumberRange.new(0.2, 0.6), RotSpeed = NumberRange.new(-90, 90), Rate = 14,
			Acceleration = Vector3.new(0, 0.8, 0), Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = SURFACE })
	elseif kind == "blood" then
		-- Blood Moon: crimson fog, drops of blood falling; a red moon behind you.
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(c, Color3.fromRGB(60, 0, 10)), Transparency = seq(0.35, 1), Size = seq(1.6, 3.6),
			Lifetime = NumberRange.new(1.6, 2.4), Speed = NumberRange.new(0.6, 1.4), SpreadAngle = Vector2.new(60, 60), Rate = 11,
			Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Top })
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 0.4, Size = seq(0.2, 0.15),
			Lifetime = NumberRange.new(0.8, 1.2), Speed = NumberRange.new(0, 0.2), Acceleration = Vector3.new(0, -12, 0), Rate = 8,
			Shape = BOX, ShapeStyle = SURFACE })
		groundPulse(RING, c, 0.8, 2, 7, 0.45)
	elseif kind == "stars" then
		-- Starfall: shooting stars streaking down, twinkles round you.
		local sky = auraPart(root, "GearAura", Vector3.new(5, 0.2, 5), CFrame.new(0, 6, 0))
		emitter(sky, { Texture = SPARK, Color = ColorSequence.new(Color3.new(1, 1, 1), c), LightEmission = 1, Size = seq(0.3, 0.1),
			Orientation = Enum.ParticleOrientation.VelocityParallel, Squash = NumberSequence.new(-3),
			Lifetime = NumberRange.new(0.6, 0.9), Speed = NumberRange.new(9, 13), Rate = 9, SpreadAngle = Vector2.new(15, 15),
			Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Bottom })
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 1, Size = seq(0, 0.5, 0),
			Lifetime = NumberRange.new(0.6, 1.2), Speed = NumberRange.new(0, 0.2), RotSpeed = NumberRange.new(-180, 180), Rate = 12,
			Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = SURFACE })
		groundPulse(GLOW, c, 1.5, 3.5, 4.5, 0.55)
	elseif kind == "void" then
		-- Void Rift: a dark vortex underfoot, tendrils curling up, crackles.
		emitter(feet, { Texture = VORTEX, Color = ColorSequence.new(c, Color3.fromRGB(25, 0, 50)), LightEmission = 0.6, Orientation = FLAT,
			Size = seq(5.5, 5.5), Transparency = seq(1, 0.25, 1), Lifetime = NumberRange.new(2, 2), Speed = NumberRange.new(0.01, 0.01),
			SpreadAngle = Vector2.zero, RotSpeed = NumberRange.new(120, 120), Rotation = NumberRange.new(0, 360), Rate = 2,
			EmissionDirection = Enum.NormalId.Top })
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(Color3.fromRGB(30, 0, 50)), Transparency = seq(0.3, 1), Size = seq(1.6, 3.2),
			Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.4, 1), RotSpeed = NumberRange.new(-120, 120), Rate = 8,
			Shape = BOX, ShapeStyle = VOLUME, EmissionDirection = Enum.NormalId.Top })
		around(4, 1.6, function(a, offset)
			beam(feet, offset, body, Vector3.new(math.cos(a + 1.4) * 1.2, 2.4, math.sin(a + 1.4) * 1.2), { Texture = SMOKE, TextureSpeed = 1.2,
				Color = ColorSequence.new(c, Color3.fromRGB(30, 0, 60)), LightEmission = 0.5, Width0 = 0.5, Width1 = 0.05, CurveSize0 = 2, CurveSize1 = -1.5,
				Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) }) })
		end)
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(230, 200, 255), c), LightEmission = 1, Size = seq(0.3, 0),
			Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(6, 10), Rate = 18, Shape = BOX, ShapeStyle = SURFACE })
	end

	-- The crown over the head, one per aura that has one.
	if not headPart then return end
	local crown = Instance.new("Model")
	crown.Name = "GearHalo"
	local top = headPart.CFrame * CFrame.new(0, 1.3, 0)
	local function headPiece(props: { [string]: any })
		piece(headPart :: any, headPart, props).Parent = crown
	end
	if kind == "holy" or kind == "void" then
		-- a ring of glowing links (the void's is broken and askew)
		local n, r = 14, if kind == "holy" then 0.8 else 1
		for i = 1, n do
			if kind == "void" and (i % 5 == 0 or i % 7 == 0) then continue end
			local a = i / n * math.pi * 2
			local tilt = if kind == "void" then CFrame.Angles(0, 0, math.rad(12)) * CFrame.new(0, (i % 3) * 0.08, 0) else CFrame.new()
			local p = top * tilt * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r)
			headPiece({ Size = Vector3.new(0.12, 0.12, r * 2 * math.pi / n * 0.85), Color = c, Transparency = 0.15,
				CFrame = CFrame.lookAt(p.Position, p.Position + (top.RightVector * -math.sin(a) + top.LookVector * -math.cos(a))) })
		end
	elseif kind == "blood" then
		-- a blood moon, a disc behind the head
		headPiece({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 2.6, 2.6), Color = c, Transparency = 0.25,
			CFrame = headPart.CFrame * CFrame.new(0, 0.5, 0.9) * CFrame.Angles(0, math.rad(90), 0) })
		headPiece({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 3.1, 3.1), Color = Color3.fromRGB(120, 0, 15), Transparency = 0.6,
			CFrame = headPart.CFrame * CFrame.new(0, 0.5, 0.95) * CFrame.Angles(0, math.rad(90), 0) })
	elseif kind == "stars" then
		-- five star points floating in a crown
		for i = 1, 5 do
			local a = i / 5 * math.pi * 2
			headPiece({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.28, Color = Color3.new(1, 1, 1),
				CFrame = top * CFrame.new(math.cos(a) * 0.9, 0.15 * math.sin(a * 2), math.sin(a) * 0.9) })
		end
	end
	if #crown:GetChildren() > 0 then crown.Parent = headPart else crown:Destroy() end
end

-- ── The nameplate (the lobby): name, and title in its rarity's colour ─────
function GearLook.Nameplate(character: Model, name: string, titleId: string?, shown: boolean)
	local head = character:FindFirstChild("Head") :: BasePart?
	if not head then return end
	local bb = head:FindFirstChild("GearNameplate") :: BillboardGui?
	if not bb then
		local g = Instance.new("BillboardGui")
		g.Name = "GearNameplate"
		g.Size = UDim2.fromOffset(240, 46)
		g.StudsOffsetWorldSpace = Vector3.new(0, 3.4, 0)
		g.MaxDistance = 90
		g.LightInfluence = 0
		g.Parent = head
		local n = Instance.new("TextLabel")
		n.Name = "PlayerName"
		n.BackgroundTransparency = 1
		n.Size = UDim2.new(1, 0, 0, 24)
		n.Font = Enum.Font.Antique
		n.TextSize = 22
		n.TextColor3 = Color3.fromRGB(245, 235, 215)
		n.TextStrokeTransparency = 0.35
		n.Parent = g
		local t = Instance.new("TextLabel")
		t.Name = "Title"
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(0, 24)
		t.Size = UDim2.new(1, 0, 0, 18)
		t.Font = Enum.Font.Antique
		t.TextSize = 16
		t.TextStrokeTransparency = 0.4
		t.Parent = g
		bb = g
	end
	local g = bb :: BillboardGui
	g.Enabled = shown
	local nameLabel = g:FindFirstChild("PlayerName") :: TextLabel
	local titleLabel = g:FindFirstChild("Title") :: TextLabel
	nameLabel.Text = name
	local item = GearData.Get(titleId)
	if item and item.slot == "title" then
		titleLabel.Text = "« " .. tostring(item.title) .. " »"
		titleLabel.TextColor3 = item.titleColor or Color3.new(1, 1, 1)
		titleLabel.Visible = true
	else
		titleLabel.Visible = false
	end
end

return GearLook
