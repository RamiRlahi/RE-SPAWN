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
	if kind == "dust" then
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(c), Transparency = seq(0.6, 1), Size = seq(1.2, 2.6),
			Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.4, 1), SpreadAngle = Vector2.new(40, 40), Rate = 6,
			Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
	elseif kind == "embers" then
		emitter(feet, { Texture = SPARK, Color = ColorSequence.new(Color3.fromRGB(255, 220, 140), c), LightEmission = 1, Size = seq(0.35, 0),
			Lifetime = NumberRange.new(1.2, 2), Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 1.5, 0), SpreadAngle = Vector2.new(20, 20), Rate = 16,
			Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
	elseif kind == "frost" then
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(c), Transparency = seq(0.45, 1), Size = seq(1.4, 3),
			Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(0.2, 0.6), SpreadAngle = Vector2.new(60, 60), Rate = 8,
			Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(Color3.new(1, 1, 1), c), LightEmission = 0.9, Size = seq(0.25, 0),
			Lifetime = NumberRange.new(0.8, 1.4), Speed = NumberRange.new(0.3, 1), Rate = 8, Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
	elseif kind == "holy" then
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 1, Size = seq(0.5, 0.45, 0),
			Lifetime = NumberRange.new(1.6, 2.6), Speed = NumberRange.new(0.2, 0.6), RotSpeed = NumberRange.new(-90, 90), Rate = 14,
			Acceleration = Vector3.new(0, 0.8, 0), Shape = Enum.ParticleEmitterShape.Sphere, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
		emitter(feet, { Texture = SPARK, Color = ColorSequence.new(Color3.new(1, 1, 1), c), LightEmission = 1, Size = seq(0.3, 0),
			Lifetime = NumberRange.new(1, 1.6), Speed = NumberRange.new(1.5, 3), SpreadAngle = Vector2.new(10, 10), Rate = 6,
			Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
	elseif kind == "blood" then
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(c, Color3.fromRGB(60, 0, 10)), Transparency = seq(0.4, 1), Size = seq(1.4, 3.2),
			Lifetime = NumberRange.new(1.4, 2.2), Speed = NumberRange.new(0.6, 1.4), SpreadAngle = Vector2.new(40, 40), Rate = 9,
			Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
	elseif kind == "stars" then
		local sky = auraPart(root, "GearAura", Vector3.new(4, 0.2, 4), CFrame.new(0, 4.2, 0))
		emitter(sky, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 1, Size = seq(0.45, 0),
			Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.5, 1), Acceleration = Vector3.new(0, -4, 0), Rate = 14,
			Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Bottom })
	elseif kind == "void" then
		emitter(feet, { Texture = SMOKE, Color = ColorSequence.new(c, Color3.fromRGB(20, 0, 40)), Transparency = seq(0.35, 1), Size = seq(1.6, 3.4),
			Lifetime = NumberRange.new(1.2, 1.8), Speed = NumberRange.new(0.4, 1.2), RotSpeed = NumberRange.new(-120, 120), Rate = 10,
			Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume, EmissionDirection = Enum.NormalId.Top })
		emitter(body, { Texture = SPARK, Color = ColorSequence.new(c), LightEmission = 1, Size = seq(0.35, 0), Lifetime = NumberRange.new(0.6, 1.1),
			Speed = NumberRange.new(1, 2), Rate = 12, Shape = BOX, ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface })
	end
	-- the legendary-and-up auras crown you too
	if (kind == "blood" or kind == "void" or kind == "stars") and head and head:IsA("BasePart") then
		-- a ring of glowing links floating over the head
		local halo = Instance.new("Model")
		halo.Name = "GearHalo"
		local center = head.CFrame * CFrame.new(0, 1.3, 0)
		local n, r = 14, 0.95
		for i = 1, n do
			local a = i / n * math.pi * 2
			local seg = Instance.new("Part")
			seg.Size = Vector3.new(0.12, 0.12, r * 2 * math.pi / n * 0.85)
			seg.Material = Enum.Material.Neon
			seg.Color = c
			seg.Transparency = 0.2
			seg.CanCollide = false
			seg.CanQuery = false
			seg.CanTouch = false
			seg.Massless = true
			seg.CastShadow = false
			local p = center * CFrame.new(math.cos(a) * r, 0, math.sin(a) * r)
			seg.CFrame = CFrame.lookAt(p.Position, p.Position + (center.RightVector * -math.sin(a) + center.LookVector * -math.cos(a)))
			seg.Parent = halo
			local w = Instance.new("WeldConstraint")
			w.Part0 = head
			w.Part1 = seg
			w.Parent = seg
		end
		halo.Parent = head
	end
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
