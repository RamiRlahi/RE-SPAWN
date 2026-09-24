local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local HOLY_IVORY = Color3.fromRGB(255, 250, 238)
local HOLY_GOLD = Color3.fromRGB(255, 206, 112)
local HOLY_RAY_TEXTURE = "rbxassetid://1053548563"

local ClericVFX = {}

-- Radiant Ground: a single narrow ray of light strikes down from above,
-- then bursts along the ground as an expanding shockwave ring.
function ClericVFX.playRadiantGround(origin, radius)
	radius = radius or 16
	local holder = Instance.new("Folder")
	holder.Name = "ClericRadiantGround"
	holder.Parent = Workspace.Terrain

	-- Find the ground surface under the origin so the ray lands on the floor.
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { holder }
	rayParams.IgnoreWater = true
	local down = Workspace:Raycast(origin + Vector3.new(0, 30, 0), Vector3.new(0, -120, 0), rayParams)
	local groundY = down and down.Position.Y or (origin.Y - 2.4)
	local center = Vector3.new(origin.X, groundY + 0.06, origin.Z)

	-- ── 1. The single ray of light: a thin vertical beam that drops in ──
	local rayHeight = 200
	local ray = Instance.new("Part")
	ray.Name = "RadiantRay"
	ray.Shape = Enum.PartType.Cylinder
	ray.Size = Vector3.new(rayHeight, 0.55, 0.55)
	ray.Material = Enum.Material.Neon
	ray.Color = HOLY_IVORY
	ray.Transparency = 0.1
	ray.Anchored = true
	ray.CanCollide = false
	ray.CanTouch = false
	ray.CanQuery = false
	ray.CastShadow = false
	ray.CFrame = CFrame.new(center + Vector3.new(0, rayHeight * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ray.Parent = holder

	-- Soft outer glow sleeve around the core ray
	local rayGlow = Instance.new("Part")
	rayGlow.Name = "RadiantRayGlow"
	rayGlow.Shape = Enum.PartType.Cylinder
	rayGlow.Size = Vector3.new(rayHeight, 2.2, 2.2)
	rayGlow.Material = Enum.Material.Neon
	rayGlow.Color = HOLY_GOLD
	rayGlow.Transparency = 0.82
	rayGlow.Anchored = true
	rayGlow.CanCollide = false
	rayGlow.CanTouch = false
	rayGlow.CanQuery = false
	rayGlow.CastShadow = false
	rayGlow.CFrame = ray.CFrame
	rayGlow.Parent = holder

	-- ── 2. The ground shockwave: a flat expanding perimeter ring ──
	local RING_N = 40
	local segs = {}
	for k = 1, RING_N do
		local ang = (k / RING_N) * math.pi * 2
		local seg = Instance.new("Part")
		seg.Name = "RadiantShockSeg"
		seg.Size = Vector3.new(0.5, 0.35, 1.4)
		seg.Material = Enum.Material.Neon
		seg.Color = (k % 4 == 0) and HOLY_IVORY or HOLY_GOLD
		seg.Transparency = 0.1
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanTouch = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.CFrame = CFrame.new(center) * CFrame.Angles(0, -ang, 0)
		seg.Parent = holder
		segs[#segs + 1] = { part = seg, ang = ang }
	end

	-- Ground flash disc under the ray impact
	local flash = Instance.new("Part")
	flash.Name = "RadiantFlash"
	flash.Shape = Enum.PartType.Cylinder
	flash.Size = Vector3.new(0.1, 2, 2)
	flash.Material = Enum.Material.Neon
	flash.Color = HOLY_IVORY
	flash.Transparency = 0.2
	flash.Anchored = true
	flash.CanCollide = false
	flash.CanTouch = false
	flash.CanQuery = false
	flash.CastShadow = false
	flash.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	flash.Parent = holder

	-- Gold light flash at the impact point
	local light = Instance.new("PointLight")
	light.Color = HOLY_GOLD
	light.Brightness = 5
	light.Range = radius * 1.6
	light.Shadows = false
	light.Parent = flash

	-- Dust / holy motes kicked outward along the ground
	local att = Instance.new("Attachment")
	att.Parent = flash
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = HOLY_RAY_TEXTURE
	pe.Rate = 0
	pe.Lifetime = NumberRange.new(0.35, 0.7)
	pe.Speed = NumberRange.new(radius * 0.8, radius * 1.6)
	pe.SpreadAngle = Vector2.new(4, 4)
	pe.Size = NumberSequence.new(1.4)
	pe.Color = ColorSequence.new(HOLY_GOLD)
	pe.LightEmission = 1
	pe.Transparency = NumberSequence.new(0.25)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Parent = att

	-- ── Animation: ray flashes in, then ground shockwave races outward ──
	local t0 = os.clock()
	local DROP = 0.10      -- ray punch-in
	local EXPAND = 0.34    -- shockwave travel time
	local LIFE = 0.75
	local impactDone = false

	local conn
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local elapsed = now - t0

		-- Ray punch-in: thickness pulse then settles
		local dropA = math.clamp(elapsed / DROP, 0, 1)
		local coreW = 0.55 + 1.2 * (1 - dropA)
		ray.Size = Vector3.new(rayHeight, coreW, coreW)
		rayGlow.Size = Vector3.new(rayHeight, 2.2 + 3.0 * (1 - dropA), 2.2 + 3.0 * (1 - dropA))

		-- Ground shockwave expansion (ease-out)
		local eA = math.clamp(elapsed / EXPAND, 0, 1)
		local a = 1 - math.pow(1 - eA, 3)
		local r = 1.0 + (radius - 1.0) * a
		for _, s in ipairs(segs) do
			s.part.CFrame = CFrame.new(center) * CFrame.new(math.cos(s.ang) * r, 0, math.sin(s.ang) * r)
				* CFrame.Angles(0, -s.ang, 0)
		end
		flash.Size = Vector3.new(0.1, 2 + radius * 0.7 * a, 2 + radius * 0.7 * a)

		-- Once the ray has landed, fire the outward dust burst
		if not impactDone and elapsed >= DROP then
			impactDone = true
			pe:Emit(math.floor(28 + radius * 1.5))
		end

		if elapsed >= LIFE then
			if conn then conn:Disconnect() end
			light.Enabled = false
			pe.Enabled = false
			for _, d in ipairs(holder:GetDescendants()) do
				if d:IsA("BasePart") then
					TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				end
			end
			Debris:AddItem(holder, 0.45)
		end
	end)
end

return ClericVFX
