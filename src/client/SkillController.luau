--[[
	SkillController.luau
	Client-side combat skill controller handling user inputs, cooldown syncing with GameHUD,
	aiming calculations, character animations, and visual effects (VFX).
--]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SkillData = require(Shared:WaitForChild("SkillData"))

local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local SkillController = {}

-- Lazy-required GameHUD to avoid circular dependencies
local GameHUD: any = nil
local function getHUD()
	if not GameHUD then
		local uiFolder = script.Parent:FindFirstChild("UI")
		if uiFolder and uiFolder:FindFirstChild("GameHUD") then
			pcall(function()
				GameHUD = require(uiFolder:FindFirstChild("GameHUD") :: ModuleScript)
			end)
		end
	end
	return GameHUD
end

-- Active cooldowns: activeCooldowns[slotIndex] = { startTime: number, duration: number }
local activeCooldowns: { [number]: { startTime: number, duration: number } } = {}

-- Loaded animation tracks per skill index
local loadedSkillTracks: { [number]: AnimationTrack } = {}
local loadedSkillSlashTracks: { [number]: AnimationTrack } = {}

-- Character visibility storage for skill 3 (Phoenix Dash invisibility)
local savedTransparencies: { [Model]: { [Instance]: number } } = {}

local function setCharacterVisibility(char: Model, visible: boolean)
	if not char then return end

	if not visible then
		local charSaved = savedTransparencies[char]
		if not charSaved then
			charSaved = {}
			savedTransparencies[char] = charSaved
		end

		for _, desc in ipairs(char:GetDescendants()) do
			if desc:IsA("BasePart") then
				if charSaved[desc] == nil then
					charSaved[desc] = desc.Transparency
				end
				desc.Transparency = 1
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				if charSaved[desc] == nil then
					charSaved[desc] = desc.Transparency
				end
				desc.Transparency = 1
			end
		end
	else
		local charSaved = savedTransparencies[char]
		if charSaved then
			for inst, origTrans in pairs(charSaved) do
				if inst and inst.Parent then
					inst.Transparency = origTrans
				end
			end
			savedTransparencies[char] = nil
		else
			for _, desc in ipairs(char:GetDescendants()) do
				if desc:IsA("BasePart") then
					if desc.Name == "HumanoidRootPart" then
						desc.Transparency = 1
					else
						desc.Transparency = 0
					end
				elseif desc:IsA("Decal") or desc:IsA("Texture") then
					desc.Transparency = 0
				end
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- VFX Utility Helpers
-- ─────────────────────────────────────────────────────────────────────────────

local FLAME_COLOR_SEQUENCE = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 210)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 190, 40)),
	ColorSequenceKeypoint.new(0.55, Color3.fromRGB(255, 90, 15)),
	ColorSequenceKeypoint.new(0.85, Color3.fromRGB(180, 25, 5)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 10, 10)),
})

local FLAME_TRANSPARENCY_SEQUENCE = NumberSequence.new({
	NumberSequenceKeypoint.new(0, 0.1),
	NumberSequenceKeypoint.new(0.4, 0.2),
	NumberSequenceKeypoint.new(0.8, 0.6),
	NumberSequenceKeypoint.new(1, 1),
})

local function makeFlameEmitter(parent: Instance, emitRate: number, sizeNum: number, speedNum: number): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "FlameEmitter"
	pe.Texture = "rbxassetid://258129523"
	pe.Color = FLAME_COLOR_SEQUENCE
	pe.Transparency = FLAME_TRANSPARENCY_SEQUENCE
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Rate = emitRate
	pe.Lifetime = NumberRange.new(0.25, 0.55)
	pe.Speed = NumberRange.new(speedNum * 0.7, speedNum * 1.3)
	pe.SpreadAngle = Vector2.new(20, 20)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, sizeNum * 0.5),
		NumberSequenceKeypoint.new(0.4, sizeNum * 1.2),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	pe.Parent = parent
	return pe
end

local function makeEmberEmitter(parent: Instance, count: number): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Name = "EmberEmitter"
	pe.Texture = "rbxassetid://241594419"
	pe.Color = ColorSequence.new(Color3.fromRGB(255, 220, 120), Color3.fromRGB(255, 90, 20))
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Rate = count
	pe.Lifetime = NumberRange.new(0.4, 0.8)
	pe.Speed = NumberRange.new(4, 12)
	pe.SpreadAngle = Vector2.new(45, 45)
	pe.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.4),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	pe.Parent = parent
	return pe
end

local function spawnGroundScorch(position: Vector3, size: number, duration: number)
	-- Removed extra red ground circle VFX when casting abilities
	return
end

local function triggerCameraShake(intensity: number, duration: number)
	task.spawn(function()
		local start = os.clock()
		local origCFrame = camera.CFrame
		while os.clock() - start < duration do
			local alpha = 1 - ((os.clock() - start) / duration)
			local curIntensity = intensity * alpha
			local offset = Vector3.new(
				(math.random() - 0.5) * curIntensity,
				(math.random() - 0.5) * curIntensity * 0.6,
				(math.random() - 0.5) * curIntensity
			)
			camera.CFrame = camera.CFrame * CFrame.new(offset)
			RunService.RenderStepped:Wait()
		end
	end)
end

local function setWeaponTrailEnlarged(character: Model, enlarged: boolean)
	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("Trail") then
			desc.Enabled = enlarged
			if enlarged then
				desc.WidthScale = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 4.0),
					NumberSequenceKeypoint.new(0.5, 3.0),
					NumberSequenceKeypoint.new(1, 0.4),
				})
			else
				desc.WidthScale = NumberSequence.new({
					NumberSequenceKeypoint.new(0, 1.5),
					NumberSequenceKeypoint.new(0.65, 1.2),
					NumberSequenceKeypoint.new(1, 0.2),
				})
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Aim Direction Calculation (Mouse Raycast to Floor)
-- ─────────────────────────────────────────────────────────────────────────────
local function findVFXAsset(name: string): Instance?
	local searchNames = {
		name,
		string.lower(name),
		string.upper(name),
		string.gsub(name, " ", "_"),
		string.gsub(name, "_", " "),
	}

	local roots = {
		ReplicatedStorage:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("VFX"),
		ReplicatedStorage:FindFirstChild("Assets"),
		ReplicatedStorage,
	}

	for _, folder in ipairs(roots) do
		if folder then
			for _, n in ipairs(searchNames) do
				local found = folder:FindFirstChild(n)
				if found then return found end
			end
			for _, child in ipairs(folder:GetChildren()) do
				for _, n in ipairs(searchNames) do
					if string.lower(child.Name) == string.lower(n) then
						return child
					end
				end
			end
		end
	end
	return nil
end

local function getAimDirection(rootPart: BasePart): Vector3
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	
	-- Intersect ray with horizontal plane at character Y
	local planeY = rootPart.Position.Y
	local dir = ray.Direction
	if math.abs(dir.Y) > 0.001 then
		local t = (planeY - ray.Origin.Y) / dir.Y
		if t > 0 then
			local hitPoint = ray.Origin + dir * t
			local diff = hitPoint - rootPart.Position
			local flatDiff = Vector3.new(diff.X, 0, diff.Z)
			if flatDiff.Magnitude > 0.5 then
				return flatDiff.Unit
			end
		end
	end

	return rootPart.CFrame.LookVector
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 1: Spin Attack VFX (5s Continuous Whirlwind Spin)
-- ─────────────────────────────────────────────────────────────────────────────
local function playSpinAttackVFX(char: Model, origin: Vector3, lookDir: Vector3)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local duration = 5.0

	-- 1. Enlarge weapon trail during continuous spin
	setWeaponTrailEnlarged(char, true)

	-- 2. Cloned VFX asset from ReplicatedStorage.generalVFX ("spin vfx")
	local spinTemplate = findVFXAsset("spin vfx") or findVFXAsset("spin") or findVFXAsset("Spin VFX")
	local spawnedVFX: Instance? = nil

	if spinTemplate then
		local clone = spinTemplate:Clone()
		spawnedVFX = clone

		for _, inst in ipairs(clone:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.CanCollide = false
				inst.CanTouch = false
				inst.CanQuery = false
				inst.Massless = true
				inst.Anchored = false
			elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
				inst.Enabled = true
			end
		end

		if clone:IsA("Model") then
			local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
			if primary then
				primary.CanCollide = false
				primary.Massless = true
				primary.Anchored = false
				clone:PivotTo(rootPart.CFrame)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rootPart
				weld.Part1 = primary
				weld.Parent = primary
				for _, p in ipairs(clone:GetChildren()) do
					if p:IsA("BasePart") and p ~= primary then
						p.CanCollide = false
						p.Massless = true
						p.Anchored = false
						local w = Instance.new("WeldConstraint")
						w.Part0 = primary
						w.Part1 = p
						w.Parent = p
					end
				end
			end
			clone.Parent = char
		elseif clone:IsA("BasePart") then
			clone.CanCollide = false
			clone.Massless = true
			clone.Anchored = false
			clone.CFrame = rootPart.CFrame
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = clone
			weld.Parent = clone
			clone.Parent = char
		elseif clone:IsA("Attachment") then
			clone.Parent = rootPart
		else
			clone.Parent = char
		end
	end

	-- 3. Dynamic Fiery Whirlwind attached to RootPart
	local vortexAtt = Instance.new("Attachment")
	vortexAtt.Name = "SpinWhirlwindAttachment"
	vortexAtt.Position = Vector3.new(0, -0.8, 0)
	vortexAtt.Parent = rootPart

	local vortexPE = makeFlameEmitter(vortexAtt, 90, 3.8, 18)
	vortexPE.SpreadAngle = Vector2.new(180, 45)
	vortexPE.Speed = NumberRange.new(14, 26)
	vortexPE.Lifetime = NumberRange.new(0.3, 0.55)

	local vortexEmbers = makeEmberEmitter(vortexAtt, 50)
	vortexEmbers.Speed = NumberRange.new(15, 30)

	-- Dynamic light attached to player
	local spinLight = Instance.new("PointLight")
	spinLight.Color = Color3.fromRGB(255, 140, 30)
	spinLight.Brightness = 7
	spinLight.Range = 22
	spinLight.Parent = rootPart

	-- 4. Ground Scorch pulses & camera pulses every 0.45s for 5.0 seconds
	local startTime = os.clock()
	task.spawn(function()
		while os.clock() - startTime < duration do
			if not char or not char.Parent or not rootPart or not rootPart.Parent then break end
			spawnGroundScorch(rootPart.Position, 9.0, 1.4)
			if char == player.Character then
				triggerCameraShake(0.35, 0.2)
			end
			task.wait(0.45)
		end
	end)

	-- 5. Cleanup after 5 seconds base duration
	task.delay(duration, function()
		vortexPE.Enabled = false
		vortexEmbers.Enabled = false
		setWeaponTrailEnlarged(char, false)

		if spawnedVFX then
			for _, inst in ipairs(spawnedVFX:GetDescendants()) do
				if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
					inst.Enabled = false
				end
			end
			Debris:AddItem(spawnedVFX, 0.6)
		end

		if spinLight and spinLight.Parent then
			TweenService:Create(spinLight, TweenInfo.new(0.4), { Brightness = 0 }):Play()
			Debris:AddItem(spinLight, 0.45)
		end

		Debris:AddItem(vortexAtt, 0.6)
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 2: Flame Slash VFX (Ranged Projectile)
-- ─────────────────────────────────────────────────────────────────────────────
local function playFlameSlashVFX(char: Model, origin: Vector3, lookDir: Vector3)
	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local startPos = origin + Vector3.new(0, 1.2, 0) + flatDir * 2
	local range = 45
	local speed = 70
	local duration = range / speed

	-- Create Projectile Carrier
	local proj = Instance.new("Part")
	proj.Name = "FlameSlashProjectile"
	proj.Size = Vector3.new(6.0, 0.4, 2.2)
	proj.Material = Enum.Material.Neon
	proj.Color = Color3.fromRGB(255, 170, 35)
	proj.Transparency = 0.1
	proj.CanCollide = false
	proj.CanTouch = false
	proj.CanQuery = false
	proj.Massless = true
	proj.Anchored = true
	proj.CFrame = CFrame.lookAt(startPos, startPos + flatDir) * CFrame.Angles(0, 0, math.rad(15))
	proj.Parent = Workspace

	-- Slash crescent shape mesh
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.15, 0.5)
	mesh.Parent = proj

	-- Fiery PointLight
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 160, 40)
	light.Brightness = 5
	light.Range = 16
	light.Parent = proj

	-- Particles on projectile
	local flamePE = makeFlameEmitter(proj, 40, 2.0, 8)
	local emberPE = makeEmberEmitter(proj, 25)

	-- Fiery Trail behind projectile
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(-3, 0, 0)
	att0.Parent = proj

	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(3, 0, 0)
	att1.Parent = proj

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = FLAME_COLOR_SEQUENCE
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.28
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.FaceCamera = true
	trail.Parent = proj

	-- Move projectile forward
	task.spawn(function()
		local startTime = os.clock()
		local lastPos = startPos

		while os.clock() - startTime < duration do
			local dt = RunService.RenderStepped:Wait()
			local elapsed = os.clock() - startTime
			local currentPos = startPos + flatDir * (elapsed * speed)

			proj.CFrame = CFrame.lookAt(currentPos, currentPos + flatDir) * CFrame.Angles(0, 0, math.rad(15 + math.sin(elapsed * 20) * 8))

			-- Check wall raycast
			local raycastParams = RaycastParams.new()
			raycastParams.FilterType = Enum.RaycastFilterType.Exclude
			raycastParams.FilterDescendantsInstances = { char, proj }
			local ray = Workspace:Raycast(lastPos, currentPos - lastPos, raycastParams)
			if ray and ray.Instance and ray.Instance.CanCollide then
				currentPos = ray.Position
				break
			end

			lastPos = currentPos
		end

		-- Explosion burst on impact / expiration
		flamePE.Enabled = false
		emberPE.Enabled = false
		proj.Transparency = 1

		local burstAtt = Instance.new("Attachment")
		burstAtt.CFrame = CFrame.new(proj.Position)
		burstAtt.Parent = Workspace.Terrain

		local burstPE = makeFlameEmitter(burstAtt, 0, 4.0, 20)
		local burstEmbers = makeEmberEmitter(burstAtt, 0)
		burstPE:Emit(25)
		burstEmbers:Emit(20)

		spawnGroundScorch(proj.Position, 7, 1.8)

		task.wait(0.5)
		burstAtt:Destroy()
		proj:Destroy()
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 3: Phoenix Dash VFX (Dash + Fire Whirlwind)
-- ─────────────────────────────────────────────────────────────────────────────
local function playPhoenixDashVFX(char: Model, origin: Vector3, lookDir: Vector3)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	-- Make player invisible when using 3rd ability (Phoenix Dash)
	setCharacterVisibility(char, false)

	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local dashDist = 24
	local dashSpeed = 80
	local duration = 0.28

	-- 1. Apply physical LinearVelocity
	local att = Instance.new("Attachment")
	att.Name = "DashAttachment"
	att.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashLinearVelocity"
	lv.Attachment0 = att
	lv.MaxForce = 250000
	lv.VectorVelocity = flatDir * dashSpeed
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = rootPart

	-- 2. Cloned Dash VFX asset from ReplicatedStorage.generalVFX ("hk_dash" / "Dash") stuck to player
	local dashTemplate = findVFXAsset("hk_dash") or findVFXAsset("Dash") or findVFXAsset("dash")
	local spawnedDashVFX: Instance? = nil

	if dashTemplate then
		local clone = dashTemplate:Clone()
		spawnedDashVFX = clone

		for _, inst in ipairs(clone:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.CanCollide = false
				inst.CanTouch = false
				inst.CanQuery = false
				inst.Massless = true
				inst.Anchored = false
			elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
				inst.Enabled = true
				if inst:IsA("ParticleEmitter") then
					inst:Emit(15)
				end
			end
		end

		local dashOrientCF = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDir) * CFrame.Angles(0, math.rad(-90), 0)

		if clone:IsA("Model") then
			local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
			if primary then
				primary.CanCollide = false
				primary.Massless = true
				primary.Anchored = false
				clone:PivotTo(dashOrientCF)
				local weld = Instance.new("WeldConstraint")
				weld.Part0 = rootPart
				weld.Part1 = primary
				weld.Parent = primary

				for _, p in ipairs(clone:GetChildren()) do
					if p:IsA("BasePart") and p ~= primary then
						p.CanCollide = false
						p.Massless = true
						p.Anchored = false
						local w = Instance.new("WeldConstraint")
						w.Part0 = primary
						w.Part1 = p
						w.Parent = p
					end
				end
			end
			clone.Parent = char
		elseif clone:IsA("BasePart") then
			clone.CanCollide = false
			clone.Massless = true
			clone.Anchored = false
			clone.CFrame = dashOrientCF
			local weld = Instance.new("WeldConstraint")
			weld.Part0 = rootPart
			weld.Part1 = clone
			weld.Parent = clone
			clone.Parent = char
		elseif clone:IsA("Attachment") then
			clone.Parent = rootPart
		else
			clone.Parent = char
		end
	end

	-- 3. Whirlwind Fire Vortex attached to RootPart
	local vortexAtt = Instance.new("Attachment")
	vortexAtt.Name = "WhirlwindAttachment"
	vortexAtt.Position = Vector3.new(0, -1, 0)
	vortexAtt.Parent = rootPart

	local vortexPE = makeFlameEmitter(vortexAtt, 80, 3.0, 15)
	vortexPE.SpreadAngle = Vector2.new(180, 30)
	vortexPE.Speed = NumberRange.new(10, 22)
	vortexPE.Lifetime = NumberRange.new(0.2, 0.4)

	local vortexEmbers = makeEmberEmitter(vortexAtt, 40)
	vortexEmbers.Speed = NumberRange.new(12, 25)

	-- Light
	local dashLight = Instance.new("PointLight")
	dashLight.Color = Color3.fromRGB(255, 120, 20)
	dashLight.Brightness = 6
	dashLight.Range = 18
	dashLight.Parent = rootPart

	-- Weapon trail on during spin
	setWeaponTrailEnlarged(char, true)

	-- 4. Leave fire trail along ground
	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			local curPos = rootPart.Position
			spawnGroundScorch(curPos, 4.5, 1.2)
			task.wait(0.06)
		end
	end)

	-- 5. Cleanup dash after duration
	task.delay(duration, function()
		setCharacterVisibility(char, true)

		if lv and lv.Parent then lv:Destroy() end
		if att and att.Parent then att:Destroy() end
		vortexPE.Enabled = false
		vortexEmbers.Enabled = false
		setWeaponTrailEnlarged(char, false)

		if spawnedDashVFX then
			for _, inst in ipairs(spawnedDashVFX:GetDescendants()) do
				if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
					inst.Enabled = false
				end
			end
			Debris:AddItem(spawnedDashVFX, 0.45)
		end

		TweenService:Create(dashLight, TweenInfo.new(0.3), { Brightness = 0 }):Play()
		Debris:AddItem(dashLight, 0.35)
		Debris:AddItem(vortexAtt, 0.5)

		-- End burst shockwave
		local endBurstAtt = Instance.new("Attachment")
		endBurstAtt.CFrame = CFrame.new(rootPart.Position)
		endBurstAtt.Parent = Workspace.Terrain
		local endPE = makeFlameEmitter(endBurstAtt, 0, 4.5, 25)
		endPE.SpreadAngle = Vector2.new(180, 60)
		endPE:Emit(30)
		spawnGroundScorch(rootPart.Position, 9, 2.0)

		task.wait(0.6)
		endBurstAtt:Destroy()
	end)

	-- Camera impulse for player
	if char == player.Character then
		triggerCameraShake(0.5, 0.25)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 4: Infernal Wrath VFX (Ultimate: Flaming Sword + Impact Slash + Cube Crater)
-- ─────────────────────────────────────────────────────────────────────────────
local function createCraterCube(position: Vector3, radius: number)
	local angle = math.random() * math.pi * 2
	local dist = math.random() * (radius * 0.75) + (radius * 0.25)
	local offset = Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
	local targetPos = position + offset

	local cube = Instance.new("Part")
	cube.Name = "CraterDebrisCube"
	cube.Shape = Enum.PartType.Block
	local sz = math.random(8, 16) / 10 -- 0.8 to 1.6 studs cube
	cube.Size = Vector3.new(sz, sz, sz)
	cube.Material = Enum.Material.Slate
	cube.Color = Color3.fromRGB(60, 55, 50)
	cube.CanCollide = false
	cube.CanTouch = false
	cube.CanQuery = false
	cube.Anchored = true

	-- Start slightly below ground level
	local tiltX = math.rad(math.random(-35, 35))
	local tiltZ = math.rad(math.random(-35, 35))
	local rotY = math.rad(math.random(0, 360))
	local startCF = CFrame.new(targetPos - Vector3.new(0, 1.2, 0)) * CFrame.Angles(tiltX, rotY, tiltZ)
	cube.CFrame = startCF
	cube.Parent = Workspace

	-- Burst upward & outward forming crater rim blocks
	local riseHeight = math.random(12, 26) / 10
	local endCF = CFrame.new(targetPos + Vector3.new(0, riseHeight * 0.5, 0)) * CFrame.Angles(
		tiltX + math.rad(math.random(15, 45)),
		rotY,
		tiltZ + math.rad(math.random(15, 45))
	)

	TweenService:Create(cube, TweenInfo.new(0.24, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		CFrame = endCF,
	}):Play()

	-- Fade and sink back into earth
	task.delay(1.8, function()
		if cube and cube.Parent then
			TweenService:Create(cube, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				CFrame = endCF - Vector3.new(0, 2.5, 0),
				Transparency = 1,
				Size = cube.Size * 0.2,
			}):Play()
			Debris:AddItem(cube, 0.65)
		end
	end)
end

local function spawnCraterDebris(impactPos: Vector3, radius: number, count: number)
	for i = 1, count do
		createCraterCube(impactPos, radius)
	end
end

local function attachSwordFlameAura(char: Model)
	local tool = char:FindFirstChildOfClass("Tool") or player.Backpack:FindFirstChildOfClass("Tool")
	local bladeMesh: BasePart? = nil

	if tool then
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		bladeMesh = handle
		for _, desc in ipairs(tool:GetDescendants()) do
			if (desc:IsA("MeshPart") or desc:IsA("BasePart")) and desc.Name ~= "Handle" then
				bladeMesh = desc
				break
			end
		end
	end

	if not bladeMesh then
		bladeMesh = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or char:FindFirstChild("HumanoidRootPart")
	end
	if not bladeMesh then return end

	-- Create Attachment along the blade axis (oriented ALONG the sword blade)
	local bladeAtt = Instance.new("Attachment")
	bladeAtt.Name = "UltSwordFlameAttachment"

	local sz = bladeMesh.Size
	if sz.Y > sz.X and sz.Y > sz.Z then
		bladeAtt.Position = Vector3.new(0, sz.Y * 0.15, 0)
		bladeAtt.Orientation = Vector3.new(90, 0, 0)
	elseif sz.Z > sz.Y and sz.Z > sz.X then
		bladeAtt.Position = Vector3.new(0, 0, sz.Z * 0.15)
		bladeAtt.Orientation = Vector3.new(0, 0, 0)
	else
		bladeAtt.Position = Vector3.new(0, 0, 0)
		bladeAtt.Orientation = Vector3.new(90, 0, 0)
	end
	bladeAtt.Parent = bladeMesh

	-- Flame Emitter streaming parallel along the length of the blade
	local flamePE = makeFlameEmitter(bladeAtt, 130, 2.6, 14)
	flamePE.Name = "SwordBladeFlamePE"
	flamePE.Orientation = Enum.ParticleOrientation.VelocityParallel
	flamePE.SpreadAngle = Vector2.new(12, 12)
	flamePE.Speed = NumberRange.new(10, 22)
	flamePE.Lifetime = NumberRange.new(0.25, 0.45)

	-- Ember Sparkle Emitter along blade
	local emberPE = makeEmberEmitter(bladeAtt, 60)
	emberPE.Name = "SwordBladeEmberPE"
	emberPE.Orientation = Enum.ParticleOrientation.FacingCamera
	emberPE.Speed = NumberRange.new(12, 28)

	-- Dynamic Light on blade
	local light = Instance.new("PointLight")
	light.Name = "UltSwordLight"
	light.Color = Color3.fromRGB(255, 170, 30)
	light.Brightness = 12
	light.Range = 28
	light.Parent = bladeMesh

	return bladeAtt, flamePE, emberPE, light
end

local function playInfernalWrathVFX(char: Model, origin: Vector3, lookDir: Vector3)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local travelDist = 28.0
	local impactPos = origin + flatDir * travelDist

	-- 1. Find and clone custom hk_ULT asset from ReplicatedStorage.generalVFX
	local ultTemplate = findVFXAsset("hk_ULT") or findVFXAsset("hk_ult") or findVFXAsset("ULT") or findVFXAsset("ult")
	local spawnedUltVFX: Instance? = nil

	-- Find sword blade mesh
	local tool = char:FindFirstChildOfClass("Tool") or player.Backpack:FindFirstChildOfClass("Tool")
	local bladeMesh: BasePart? = nil
	if tool then
		local handle = tool:FindFirstChild("Handle") :: BasePart?
		bladeMesh = handle
		for _, desc in ipairs(tool:GetDescendants()) do
			if (desc:IsA("MeshPart") or desc:IsA("BasePart")) and desc.Name ~= "Handle" then
				bladeMesh = desc
				break
			end
		end
	end
	if not bladeMesh then
		bladeMesh = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm") or rootPart
	end

	if ultTemplate and bladeMesh then
		local clone = ultTemplate:Clone()
		spawnedUltVFX = clone

		for _, inst in ipairs(clone:GetDescendants()) do
			if inst:IsA("BasePart") then
				inst.CanCollide = false
				inst.CanTouch = false
				inst.CanQuery = false
				inst.Massless = true
				inst.Anchored = false
			elseif inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
				inst.Enabled = true
				if inst:IsA("ParticleEmitter") then
					inst.Orientation = Enum.ParticleOrientation.VelocityParallel
					inst:Emit(20)
				end
			end
		end

		local sz = bladeMesh.Size
		local bladeOrientCF = bladeMesh.CFrame
		if sz.Y > sz.X and sz.Y > sz.Z then
			bladeOrientCF = bladeMesh.CFrame * CFrame.Angles(math.rad(90), 0, 0)
		end

		if clone:IsA("Model") then
			local primary = clone.PrimaryPart or clone:FindFirstChildWhichIsA("BasePart")
			if primary then
				primary.CanCollide = false
				primary.Massless = true
				primary.Anchored = false
				clone:PivotTo(bladeOrientCF)

				local weld = Instance.new("WeldConstraint")
				weld.Part0 = bladeMesh
				weld.Part1 = primary
				weld.Parent = primary

				for _, p in ipairs(clone:GetChildren()) do
					if p:IsA("BasePart") and p ~= primary then
						p.CanCollide = false
						p.Massless = true
						p.Anchored = false
						local w = Instance.new("WeldConstraint")
						w.Part0 = primary
						w.Part1 = p
						w.Parent = p
					end
				end
			end
			clone.Parent = char
		elseif clone:IsA("BasePart") then
			clone.CanCollide = false
			clone.Massless = true
			clone.Anchored = false
			clone.CFrame = bladeOrientCF

			local weld = Instance.new("WeldConstraint")
			weld.Part0 = bladeMesh
			weld.Part1 = clone
			weld.Parent = clone
			clone.Parent = char
		elseif clone:IsA("Attachment") then
			clone.Parent = bladeMesh
		else
			clone.Parent = char
		end
	end

	-- 2. Ignite sword with extra flame aura ALONG the blade & enlarge weapon trail
	local bladeAtt, flamePE, emberPE, light = attachSwordFlameAura(char)
	setWeaponTrailEnlarged(char, true)

	-- Moving traveling slash wave projectile (Shot 3: travels for 3.0s from t=2.0s to t=5.0s)
	local slashProjectileModel: Model? = nil
	local function spawnTravelingSlashVFX()
		if not char or not char.Parent then return end
		local slashModel = Instance.new("Model")
		slashModel.Name = "InfernalWrath_SlashWave"

		local rootSlash = Instance.new("Part")
		rootSlash.Name = "SlashRoot"
		rootSlash.Size = Vector3.new(6, 1.5, 3)
		rootSlash.Shape = Enum.PartType.Block
		rootSlash.Material = Enum.Material.Neon
		rootSlash.Color = Color3.fromRGB(255, 110, 20)
		rootSlash.Transparency = 0.4
		rootSlash.CanCollide = false
		rootSlash.CanTouch = false
		rootSlash.CanQuery = false
		rootSlash.Anchored = true
		rootSlash.CastShadow = false

		local slashStartPos = rootPart.Position + flatDir * 3.0
		rootSlash.CFrame = CFrame.lookAt(slashStartPos, slashStartPos + flatDir)
		rootSlash.Parent = slashModel
		slashModel.PrimaryPart = rootSlash

		local slashAtt = Instance.new("Attachment")
		slashAtt.Parent = rootSlash

		local pSlash = makeFlameEmitter(slashAtt, 28, 4.0, 24)
		pSlash.SpreadAngle = Vector2.new(60, 20)
		local pEmbers = makeEmberEmitter(slashAtt, 22)

		local slashLight = Instance.new("PointLight")
		slashLight.Color = Color3.fromRGB(255, 120, 20)
		slashLight.Brightness = 10
		slashLight.Range = 24
		slashLight.Parent = rootSlash

		slashModel.Parent = Workspace.Terrain
		slashProjectileModel = slashModel

		-- Animate slash travel across 3.0 seconds
		task.spawn(function()
			local travelDuration = 3.0
			local travelStart = os.clock()
			local startP = slashStartPos
			local endP = impactPos

			while os.clock() - travelStart < travelDuration do
				local alpha = math.clamp((os.clock() - travelStart) / travelDuration, 0, 1)
				local curP = startP:Lerp(endP, alpha)
				if rootSlash and rootSlash.Parent then
					rootSlash.CFrame = CFrame.lookAt(curP, curP + flatDir)
				end
				RunService.RenderStepped:Wait()
			end

			if slashModel and slashModel.Parent then
				if pSlash then pSlash.Enabled = false end
				if pEmbers then pEmbers.Enabled = false end
				if slashLight then
					TweenService:Create(slashLight, TweenInfo.new(0.3), { Brightness = 0 }):Play()
				end
				Debris:AddItem(slashModel, 0.4)
			end
		end)
	end

	local function triggerImpactVFX()
		if not char or not char.Parent then return end

		-- Spawn Crater Debris (Small Earth/Rock Cubes)
		spawnCraterDebris(impactPos, 10.0, 28)

		-- Fiery Impact Shockwave Burst
		local impactAtt = Instance.new("Attachment")
		impactAtt.CFrame = CFrame.new(impactPos)
		impactAtt.Parent = Workspace.Terrain

		local impactFlame = makeFlameEmitter(impactAtt, 0, 6.5, 36)
		impactFlame.SpreadAngle = Vector2.new(180, 70)
		impactFlame:Emit(55)

		local impactEmbers = makeEmberEmitter(impactAtt, 0)
		impactEmbers.Speed = NumberRange.new(22, 48)
		impactEmbers:Emit(45)

		local impactLight = Instance.new("PointLight")
		impactLight.Color = Color3.fromRGB(255, 140, 20)
		impactLight.Brightness = 18
		impactLight.Range = 42
		impactLight.Parent = impactAtt

		TweenService:Create(impactLight, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Brightness = 0,
			Range = 0,
		}):Play()

		task.wait(0.8)
		impactAtt:Destroy()
	end

	-- Trigger 4-shot Ultimate Camera Choreography for local player
	if char == player.Character then
		-- Shot 2 begins at t=1.0s: switch animation from windup to slash
		local function onSlashStart()
			local windupTrack = loadedSkillTracks[4]
			if windupTrack and windupTrack.IsPlaying then
				windupTrack:Stop(0.12)
			end
			local slashTrack = loadedSkillSlashTracks[4]
			if slashTrack then
				slashTrack:Play(0.08)
			end
			-- Launch traveling slash wave at t=2.0s (Shot 3 start)
			task.delay(1.0, function()
				spawnTravelingSlashVFX()
			end)
		end

		UltimateCameraChoreography.PlaySequence(
			char,
			flatDir,
			function()
				-- Triggered at t = 5.0s (Shot 4: impact explosion)
				triggerImpactVFX()
			end,
			function()
				-- Completed at t = 6.5s
			end,
			onSlashStart
		)
	else
		-- For non-local players
		task.delay(1.0, function()
			task.delay(1.0, function()
				spawnTravelingSlashVFX()
			end)
		end)
		task.delay(5.0, function()
			triggerImpactVFX()
		end)
	end

	-- Cleanup sword aura and hk_ULT asset after cinematic sequence
	task.delay(6.8, function()
		setWeaponTrailEnlarged(char, false)
		if flamePE then flamePE.Enabled = false end
		if emberPE then emberPE.Enabled = false end

		if spawnedUltVFX then
			for _, inst in ipairs(spawnedUltVFX:GetDescendants()) do
				if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then
					inst.Enabled = false
				end
			end
			Debris:AddItem(spawnedUltVFX, 0.5)
		end

		if light and light.Parent then
			TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
			Debris:AddItem(light, 0.45)
		end
		if bladeAtt and bladeAtt.Parent then
			Debris:AddItem(bladeAtt, 0.5)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Animation Loading
-- ─────────────────────────────────────────────────────────────────────────────
local function loadSkillAnimations(char: Model)
	local humanoid = char:WaitForChild("Humanoid", 5) :: Humanoid?
	local animator = humanoid and (humanoid:WaitForChild("Animator", 5) :: Animator?)
	if not animator then return end

	local classId = player:GetAttribute("SelectedClass") or "heavy_knight"
	local skills = SkillData.GetSkills(classId)

	for skillIndex, config in pairs(skills) do
		if config.animationId then
			local anim = Instance.new("Animation")
			anim.Name = `SkillAnim_{skillIndex}`
			anim.AnimationId = config.animationId
			local track = animator:LoadAnimation(anim)
			track.Priority = Enum.AnimationPriority.Action4
			track.Looped = false
			loadedSkillTracks[skillIndex] = track
		end
		if (config :: any).slashAnimationId then
			local slashAnim = Instance.new("Animation")
			slashAnim.Name = `SkillAnimSlash_{skillIndex}`
			slashAnim.AnimationId = (config :: any).slashAnimationId
			local slashTrack = animator:LoadAnimation(slashAnim)
			slashTrack.Priority = Enum.AnimationPriority.Action4
			slashTrack.Looped = false
			loadedSkillSlashTracks[skillIndex] = slashTrack
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill Cast Execution
-- ─────────────────────────────────────────────────────────────────────────────
function SkillController.UseSkill(skillIndex: number)
	if player:GetAttribute("InLobby") == true then return end

	local char = player.Character
	if not char then return end

	-- Block casting any spells while using the 1st ability (Spin Attack)
	if char:GetAttribute("IsSkill1Active") == true or char:GetAttribute("IsSpinAttackActive") == true then
		print("[SkillController] Cannot cast other spells while using the 1st ability!")
		return
	end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end

	local classId = player:GetAttribute("SelectedClass") or "heavy_knight"
	local config = SkillData.GetSkill(classId, skillIndex)
	if not config then return end

	-- Check Cooldown
	local now = os.clock()
	local active = activeCooldowns[skillIndex]
	if active and (now - active.startTime) < active.duration then
		-- Still on cooldown
		return
	end

	-- Start local cooldown
	activeCooldowns[skillIndex] = {
		startTime = now,
		duration = config.cooldown,
	}

	-- Calculate Aim Direction
	local aimDir = getAimDirection(rootPart)

	-- Pivot character towards aim direction smoothly
	local targetCF = CFrame.lookAt(rootPart.Position, rootPart.Position + aimDir)
	rootPart.CFrame = targetCF

	-- Set casting attribute & play skill animation
	char:SetAttribute("IsSkillCasting", true)

	if skillIndex == 1 then
		-- Spin attack allows moving for the 5s duration, but blocks other spells/attacks
		char:SetAttribute("AllowSkillMovement", true)
		char:SetAttribute("IsSkill1Active", true)
		char:SetAttribute("IsSpinAttackActive", true)

		local track = loadedSkillTracks[1]
		if track then
			track.Looped = true
			track:Play(0.08)
			task.delay(5.0, function()
				if track.IsPlaying then track:Stop(0.2) end
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
				char:SetAttribute("IsSkill1Active", false)
				char:SetAttribute("IsSpinAttackActive", false)
			end)
		else
			task.delay(5.0, function()
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
				char:SetAttribute("IsSkill1Active", false)
				char:SetAttribute("IsSpinAttackActive", false)
			end)
		end
		playSpinAttackVFX(char, rootPart.Position, aimDir)
	elseif skillIndex == 2 then
		char:SetAttribute("AllowSkillMovement", false)
		local track = loadedSkillTracks[2]
		if track then
			track:Play(0.08)
			local stoppedConn: RBXScriptConnection? = nil
			stoppedConn = track.Stopped:Connect(function()
				if stoppedConn then
					stoppedConn:Disconnect()
					stoppedConn = nil
				end
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end)
		else
			task.delay(0.4, function()
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end)
		end
		playFlameSlashVFX(char, rootPart.Position, aimDir)
	elseif skillIndex == 3 then
		char:SetAttribute("AllowSkillMovement", true)
		local track = loadedSkillTracks[3]
		if track then
			track:Play(0.08)
		end
		task.delay(0.35, function()
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end)
		playPhoenixDashVFX(char, rootPart.Position, aimDir)
	elseif skillIndex == 4 then
		char:SetAttribute("AllowSkillMovement", false)
		local track = loadedSkillTracks[4]
		if track then
			track:Play(0.08)
			task.delay(6.8, function()
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end)
		else
			task.delay(6.8, function()
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end)
		end
		playInfernalWrathVFX(char, rootPart.Position, aimDir)
	end

	-- Fire Server Remote
	pcall(function()
		local useSkillRemote = Network.GetRemoteEvent(Network.Remotes.UseSkill)
		useSkillRemote:FireServer({
			skillIndex = skillIndex,
			origin = rootPart.Position,
			direction = aimDir,
		})
	end)

	print(`[SkillController] Cast Skill {skillIndex} ({config.name})`)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cooldown HUD Tick Loop
-- ─────────────────────────────────────────────────────────────────────────────
local function updateCooldowns()
	local hud = getHUD()
	if not hud then return end

	local now = os.clock()
	for slot = 1, 4 do
		local cd = activeCooldowns[slot]
		if cd then
			local elapsed = now - cd.startTime
			local remaining = math.max(0, cd.duration - elapsed)
			hud.SetSkillCooldown(slot, remaining, cd.duration)

			if remaining <= 0 then
				activeCooldowns[slot] = nil
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Initialization & Event Connections
-- ─────────────────────────────────────────────────────────────────────────────
function SkillController.Init()
	-- Keybind Listeners: E (1: Spin), F (2: Slash), SPACE (3: Dash), R (4: Ultimate)
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end

		if input.KeyCode == Enum.KeyCode.E then
			SkillController.UseSkill(1)
		elseif input.KeyCode == Enum.KeyCode.F then
			SkillController.UseSkill(2)
		elseif input.KeyCode == Enum.KeyCode.Q then
			SkillController.UseSkill(3)
		elseif input.KeyCode == Enum.KeyCode.R then
			SkillController.UseSkill(4)
		end
	end)

	-- Cooldown sync from server
	local cdRemote = Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate)
	cdRemote.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and payload.skillIndex and payload.cooldown then
			activeCooldowns[payload.skillIndex] = {
				startTime = os.clock(),
				duration = payload.cooldown,
			}
		end
	end)

	-- Skill VFX replication for other players
	local vfxRemote = Network.GetRemoteEvent(Network.Remotes.SkillVFX)
	vfxRemote.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		local castingPlayer = payload.player
		if not castingPlayer or castingPlayer == player then return end

		local char = castingPlayer.Character
		if not char then return end

		local origin = payload.origin or char:GetPivot().Position
		local direction = payload.direction or char:GetPivot().LookVector
		local skillIndex = payload.skillIndex

		if skillIndex == 1 then
			playSpinAttackVFX(char, origin, direction)
		elseif skillIndex == 2 then
			playFlameSlashVFX(char, origin, direction)
		elseif skillIndex == 3 then
			playPhoenixDashVFX(char, origin, direction)
		elseif skillIndex == 4 then
			playInfernalWrathVFX(char, origin, direction)
		end
	end)

	-- Load animations on character spawn
	if player.Character then
		task.spawn(function()
			loadSkillAnimations(player.Character)
		end)
	end

	player.CharacterAdded:Connect(function(character)
		activeCooldowns = {}
		task.spawn(function()
			loadSkillAnimations(character)
		end)
	end)

	-- Heartbeat cooldown loop
	RunService.Heartbeat:Connect(updateCooldowns)

	print("[SkillController] Client SkillController initialized.")
end

return SkillController
