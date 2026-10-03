--!strict
--[[
	EnemyProjectiles.luau
	Every enemy projectile (tagged "EnemyProjectile": skeleton arrows,
	necromancer soul bolts, boss orbs, the dragon's fireballs) is drawn so it
	can't be missed, in the dark or in a crowd:
	  • a bright core dot drawn over everything (walls, mobs, effects), white
	    ringed in red, sized to the projectile
	  • a streaking red-to-orange trail behind it
	  • a white outline and red fill (a Highlight, while there are some to spare)
	  • a small light around it
--]]

local CollectionService = game:GetService("CollectionService")

local EnemyProjectiles = {}

local TAG = "EnemyProjectile"
local DANGER = Color3.fromRGB(255, 50, 35)
local HOT = Color3.fromRGB(255, 170, 60)
-- (Roblox draws at most 31 Highlights at once; leave room for the rest)
local MAX_OUTLINES = 20
local outlined = 0

local function mark(inst: Instance)
	if not inst:IsA("BasePart") then return end
	local part = inst :: BasePart
	local big = math.max(part.Size.X, part.Size.Y, part.Size.Z)
	local thick = math.min(part.Size.X, part.Size.Y, part.Size.Z)

	-- The dot: over everything, a white core ringed in red.
	local bb = Instance.new("BillboardGui")
	bb.Name = "ProjectileDot"
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	local dot = math.clamp(thick * 2.2 + 0.6, 1.1, 4)
	bb.Size = UDim2.fromScale(dot, dot)
	bb.MaxDistance = 220
	bb.Adornee = part
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(1, 1)
	ring.BackgroundColor3 = DANGER
	ring.BackgroundTransparency = 0.15
	ring.BorderSizePixel = 0
	ring.Parent = bb
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(1, 0)
	rc.Parent = ring
	local core = Instance.new("Frame")
	core.AnchorPoint = Vector2.new(0.5, 0.5)
	core.Position = UDim2.fromScale(0.5, 0.5)
	core.Size = UDim2.fromScale(0.5, 0.5)
	core.BackgroundColor3 = Color3.new(1, 1, 1)
	core.BorderSizePixel = 0
	core.Parent = ring
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(1, 0)
	cc.Parent = core
	local st = Instance.new("UIStroke")
	st.Color = Color3.new(1, 1, 1)
	st.Thickness = 2
	st.Transparency = 0.2
	st.Parent = ring
	bb.Parent = part

	-- The trail: across the projectile, facing the camera.
	local w = math.clamp(thick * 1.4, 0.5, 3)
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailTop"
	a0.Position = Vector3.new(0, w / 2, 0)
	a0.Parent = part
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailBottom"
	a1.Position = Vector3.new(0, -w / 2, 0)
	a1.Parent = part
	local trail = Instance.new("Trail")
	trail.Name = "ProjectileTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.FaceCamera = true
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Lifetime = math.clamp(0.12 + big * 0.04, 0.18, 0.4)
	trail.MinLength = 0.05
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), HOT)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) })
	trail.Parent = part
	-- (a second, wider, red one under it)
	local glow = trail:Clone()
	glow.Name = "ProjectileTrailGlow"
	glow.Color = ColorSequence.new(DANGER)
	glow.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
	local b0 = a0:Clone()
	b0.Position = Vector3.new(0, w, 0)
	b0.Parent = part
	local b1 = a1:Clone()
	b1.Position = Vector3.new(0, -w, 0)
	b1.Parent = part
	glow.Attachment0, glow.Attachment1 = b0, b1
	glow.Parent = part

	if outlined < MAX_OUTLINES then
		outlined += 1
		local hl = Instance.new("Highlight")
		hl.Name = "ProjectileOutline"
		hl.Adornee = part
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.OutlineTransparency = 0
		hl.FillColor = DANGER
		hl.FillTransparency = 0.2
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = part
		hl.Destroying:Connect(function() outlined -= 1 end)
	end
	local light = Instance.new("PointLight")
	light.Name = "ProjectileGlow"
	light.Color = Color3.fromRGB(255, 120, 90)
	light.Range = 10
	light.Brightness = 2
	light.Shadows = false
	light.Parent = part
end

function EnemyProjectiles.Init()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(mark)
	for _, p in ipairs(CollectionService:GetTagged(TAG)) do mark(p) end
end

return EnemyProjectiles
