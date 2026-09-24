local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local HOLY_IVORY = Color3.fromRGB(255, 250, 238)
local HOLY_WHITE = Color3.fromRGB(255, 243, 212)
local HOLY_GOLD = Color3.fromRGB(255, 206, 112)
local HOLY_YELLOW = Color3.fromRGB(255, 232, 120)
local HOLY_AMBER = Color3.fromRGB(255, 184, 66)
local HOLY_RAY_TEXTURE = "rbxassetid://1053548563"

local function getCursorWorldPosition(rootPart)
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { player.Character }
	rp.IgnoreWater = true
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, rp)
	if hit then return hit.Position end
	local planeY = rootPart.Position.Y
	local d = ray.Direction
	if math.abs(d.Y) > 0.001 then
		local t = (planeY - ray.Origin.Y) / d.Y
		if t > 0 then
			local hp = ray.Origin + d * t
			local diff = hp - rootPart.Position
			local flat = Vector3.new(diff.X, 0, diff.Z)
			if flat.Magnitude > 0.5 then return hp end
		end
	end
	return rootPart.Position + rootPart.CFrame.LookVector * 100
end

local function getAimDirection(rootPart)
	local diff = getCursorWorldPosition(rootPart) - rootPart.Position
	local flat = Vector3.new(diff.X, 0, diff.Z)
	return flat.Magnitude > 0.5 and flat.Unit or rootPart.CFrame.LookVector
end

local function makeEmitter(att, rate, size, speed, color)
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = HOLY_RAY_TEXTURE
	pe.Rate = rate
	pe.Lifetime = NumberRange.new(0.35, 0.6)
	pe.Speed = NumberRange.new(speed * 0.7, speed)
	pe.Size = NumberSequence.new(size)
	pe.Color = ColorSequence.new(color)
	pe.LightEmission = 1
	pe.Transparency = NumberSequence.new(0.15)
	pe.Parent = att
	return pe
end

local DivineBeamChannel = {}

local RING_R = 1.9

local function makeRing(parent, radius, count, thickness)
	local ringHub = Instance.new("Part")
	ringHub.Name = "BeamRingHub"
	ringHub.Size = Vector3.new(0.2, 0.2, 0.2)
	ringHub.Transparency = 1
	ringHub.Anchored = true
	ringHub.CanCollide = false
	ringHub.CanTouch = false
	ringHub.CanQuery = false
	ringHub.CastShadow = false
	ringHub.Parent = parent
	for k = 1, count do
		local ang = (k / count) * math.pi * 2
		local seg = Instance.new("Part")
		seg.Name = "BeamRingSeg"
		seg.Size = Vector3.new(thickness, thickness * 3.6, thickness)
		seg.Material = Enum.Material.Neon
		seg.Color = (k % 2 == 0) and HOLY_IVORY or HOLY_YELLOW
		seg.Transparency = 0.15
		seg.Anchored = false
		seg.CanCollide = false
		seg.CanTouch = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.Massless = true
		seg.CFrame = ringHub.CFrame * CFrame.new(math.cos(ang) * radius, math.sin(ang) * radius, 0)
		seg.Parent = parent
		local w = Instance.new("WeldConstraint")
		w.Part0 = ringHub
		w.Part1 = seg
		w.Parent = seg
	end
	return ringHub
end

local function makeCylinder(parent, name, length, diameter, color, transparency)
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.Size = Vector3.new(length, diameter, diameter)
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function makeAnchor(parent, name)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = Vector3.new(0.2, 0.2, 0.2)
	p.Transparency = 1
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

function DivineBeamChannel.play(char, range, duration)
	range = math.max(8, range or 60)
	duration = duration or 5.0
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local isLocal = (player.Character == char)

	local holder = Instance.new("Folder")
	holder.Name = "ClericDivineBeam"
	holder.Parent = Workspace.Terrain

	local length = range

	local halo = makeCylinder(holder, "BeamHalo", length, 4.2, HOLY_AMBER, 0.86)
	local outer = makeCylinder(holder, "BeamGlow", length, 2.2, HOLY_GOLD, 0.55)
	local mid = makeCylinder(holder, "BeamMid", length, 1.35, HOLY_YELLOW, 0.32)
	local core = makeCylinder(holder, "BeamCore", length, 0.8, Color3.fromRGB(255, 255, 255), 0.05)

	local hub = makeAnchor(holder, "BeamHub")
	local tip = makeAnchor(holder, "BeamTip")

	-- YELLOW TRAIL: ribbon of holy light left along the beam
	local tAtt0 = Instance.new("Attachment")
	tAtt0.Parent = hub
	local tAtt1 = Instance.new("Attachment")
	tAtt1.Parent = tip
	local trail = Instance.new("Trail")
	trail.Attachment0 = tAtt0
	trail.Attachment1 = tAtt1
	trail.Texture = HOLY_RAY_TEXTURE
	trail.TextureMode = Enum.TextureMode.Stretch
	trail.LightEmission = 1
	trail.Lifetime = 0.4
	trail.Color = ColorSequence.new(HOLY_YELLOW, HOLY_AMBER)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 0.95),
	})
	trail.Parent = holder

	local muzzleLight = Instance.new("PointLight")
	muzzleLight.Color = HOLY_GOLD
	muzzleLight.Brightness = 3.5
	muzzleLight.Range = 22
	muzzleLight.Shadows = false
	muzzleLight.Parent = hub
	local tipLight = Instance.new("PointLight")
	tipLight.Color = HOLY_YELLOW
	tipLight.Brightness = 4.5
	tipLight.Range = 26
	tipLight.Shadows = false
	tipLight.Parent = tip

	local flowAtt = Instance.new("Attachment")
	flowAtt.Parent = hub
	local flowPE = makeEmitter(flowAtt, 140, 1.6, 110, HOLY_WHITE)
	flowPE.SpreadAngle = Vector2.new(6, 6)
	flowPE.EmissionDirection = Enum.NormalId.Front
	flowPE.Lifetime = NumberRange.new(0.5, 0.9)

	-- golden sparks streaming backwards off the beam
	local sparkAtt = Instance.new("Attachment")
	sparkAtt.Parent = tip
	local sparkPE = makeEmitter(sparkAtt, 90, 0.9, 34, HOLY_YELLOW)
	sparkPE.SpreadAngle = Vector2.new(30, 30)
	sparkPE.EmissionDirection = Enum.NormalId.Back
	sparkPE.Lifetime = NumberRange.new(0.45, 0.85)
	sparkPE.Acceleration = Vector3.new(0, 6, 0)

	-- impact bloom at the far end
	local impactAtt = Instance.new("Attachment")
	impactAtt.Parent = tip
	local impactPE = makeEmitter(impactAtt, 120, 2.0, 26, HOLY_GOLD)
	impactPE.SpreadAngle = Vector2.new(180, 180)
	impactPE.Lifetime = NumberRange.new(0.25, 0.5)

	-- rotating energy rings sweeping down the beam
	local rings = {}
	for i = 1, 4 do
		local rh = makeRing(holder, RING_R - (i - 1) * 0.18, 14, 0.13)
		rings[i] = { hub = rh, phase = (i - 1) / 4, spin = (i % 2 == 0) and 3.4 or -4.2 }
	end

	-- holy seal on the ground under the caster
	local seal = Instance.new("Part")
	seal.Name = "BeamSeal"
	seal.Shape = Enum.PartType.Cylinder
	seal.Size = Vector3.new(0.15, 9, 9)
	seal.Material = Enum.Material.Neon
	seal.Color = HOLY_GOLD
	seal.Transparency = 0.55
	seal.Anchored = true
	seal.CanCollide = false
	seal.CanTouch = false
	seal.CanQuery = false
	seal.CastShadow = false
	seal.Parent = holder

	local t0 = os.clock()
	local active = true
	local conn
	conn = RunService.RenderStepped:Connect(function()
		if not active then return end
		if not (char and char.Parent) or (os.clock() - t0) >= duration then
			active = false
			if conn then conn:Disconnect() end
			flowPE.Enabled = false
			sparkPE.Enabled = false
			impactPE.Enabled = false
			trail.Enabled = false
			for _, d in ipairs(holder:GetDescendants()) do
				if d:IsA("BasePart") and d ~= hub and d ~= tip then
					TweenService:Create(d, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				elseif d:IsA("ParticleEmitter") then
					d.Enabled = false
				elseif d:IsA("PointLight") then
					TweenService:Create(d, TweenInfo.new(0.3), { Brightness = 0 }):Play()
				end
			end
			if isLocal and char and char.Parent then
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end
			Debris:AddItem(holder, 0.9)
			return
		end

		local elapsed = os.clock() - t0

		local flatDir
		if isLocal and rootPart.Parent then
			local aim = getAimDirection(rootPart)
			flatDir = Vector3.new(aim.X, 0, aim.Z)
			if flatDir.Magnitude > 0.001 then
				flatDir = flatDir.Unit
				rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDir)
			end
		else
			flatDir = Vector3.new(rootPart.CFrame.LookVector.X, 0, rootPart.CFrame.LookVector.Z)
		end
		if flatDir.Magnitude < 0.001 then flatDir = Vector3.new(0, 0, -1) end
		flatDir = flatDir.Unit

		local rHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
		local lHand = char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm")
		local muzzlePos = rootPart.Position + Vector3.new(0, 1.2, 0)
		if rHand and rHand:IsA("BasePart") then
			muzzlePos = rHand.Position
			if lHand and lHand:IsA("BasePart") then
				muzzlePos = (rHand.Position + lHand.Position) * 0.5
			end
		end
		local startPos = muzzlePos + flatDir * 1.6
		local midPos = startPos + flatDir * (length * 0.5)
		local endPos = startPos + flatDir * length

		local pulse = 1 + math.sin(elapsed * 14) * 0.12

		local beamBasis = CFrame.lookAt(midPos, midPos + flatDir) * CFrame.Angles(0, math.rad(90), 0)
		halo.CFrame = beamBasis
		halo.Size = Vector3.new(length, 4.2 * pulse, 4.2 * pulse)
		outer.CFrame = beamBasis
		outer.Size = Vector3.new(length, 2.2 * pulse, 2.2 * pulse)
		mid.CFrame = beamBasis
		mid.Size = Vector3.new(length, 1.35 * pulse, 1.35 * pulse)
		core.CFrame = beamBasis
		core.Size = Vector3.new(length, 0.8 * pulse, 0.8 * pulse)

		hub.CFrame = CFrame.lookAt(startPos, startPos + flatDir)
		tip.CFrame = CFrame.lookAt(endPos, endPos + flatDir)

		for i, r in ipairs(rings) do
			local f = ((elapsed * 0.55) + r.phase) % 1
			local pos = startPos + flatDir * (f * length)
			local spin = elapsed * r.spin
			r.hub.CFrame = CFrame.lookAt(pos, pos + flatDir) * CFrame.Angles(0, 0, spin)
		end

		seal.CFrame = CFrame.new(rootPart.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, elapsed * 1.6, math.rad(90))
	end)
end

return DivineBeamChannel
