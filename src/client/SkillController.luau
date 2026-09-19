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
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))

local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local SkillController = {}

local currentKeybinds: { [string]: string } = {}

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
local currentLoadedCharacter: Model? = nil
local loadedSkillTracks: { [number]: AnimationTrack } = {}
local loadedSkillSlashTracks: { [number]: AnimationTrack } = {}
local rangerShootTracks: { [Humanoid]: AnimationTrack } = {}
local RANGER_SHOOT_ANIMATION_ID = "rbxassetid://86878349532622"

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
		string.gsub(string.lower(name), " ", "_"),
		string.gsub(string.lower(name), "_", " "),
	}

	local roots = {
		ReplicatedStorage:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("VFX"),
		ReplicatedStorage:FindFirstChild("VFX"),
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

local function getCursorWorldPosition(rootPart: BasePart): Vector3
	local mousePos = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mousePos.X, mousePos.Y)
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { player.Character }
	raycastParams.IgnoreWater = true
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 1000, raycastParams)
	if hit then
		return hit.Position
	end
	
	-- Intersect ray with horizontal plane at character Y
	local planeY = rootPart.Position.Y
	local dir = ray.Direction
	if math.abs(dir.Y) > 0.001 then
		local t = (planeY - ray.Origin.Y) / dir.Y
		if t > 0 then
			local hitPoint = ray.Origin + dir * t
			local diff = hitPoint - rootPart.Position
			local flatDiff = Vector3.new(diff.X, 0, diff.Z)
			if flatDiff.Magnitude > 0.5 then return hitPoint end
		end
	end

	return rootPart.Position + rootPart.CFrame.LookVector * 100
end

local function getAimDirection(rootPart: BasePart): Vector3
	local diff = getCursorWorldPosition(rootPart) - rootPart.Position
	local flatDiff = Vector3.new(diff.X, 0, diff.Z)
	return flatDiff.Magnitude > 0.5 and flatDiff.Unit or rootPart.CFrame.LookVector
end

local function clampRangerCursorTarget(origin: Vector3, target: Vector3, maxRange: number, fallbackDirection: Vector3): Vector3
	local offset = Vector3.new(target.X - origin.X, 0, target.Z - origin.Z)
	if offset.Magnitude < 0.5 then
		offset = Vector3.new(fallbackDirection.X, 0, fallbackDirection.Z)
		if offset.Magnitude < 0.1 then
			offset = Vector3.new(0, 0, -1)
		end
		return origin + offset.Unit * maxRange
	end
	return origin + offset.Unit * math.min(offset.Magnitude, maxRange)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 1: Spin Attack VFX (5s Continuous Whirlwind Spin)
-- ─────────────────────────────────────────────────────────────────────────────
local function playSpinAttackVFX(char: Model, origin: Vector3, lookDir: Vector3)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end
	local caster = Players:GetPlayerFromCharacter(char)
	local sizeMultiplier = caster and caster:GetAttribute("Stat_size") or 1

	local duration = 5.0

	-- 1. Enlarge weapon trail during continuous spin
	setWeaponTrailEnlarged(char, true)

	-- 2. Cloned VFX asset from ReplicatedStorage.generalVFX ("spin vfx")
	local spinTemplate = findVFXAsset("spin vfx") or findVFXAsset("spin") or findVFXAsset("Spin VFX")
	local spawnedVFX: Instance? = nil

	if spinTemplate then
		local clone = spinTemplate:Clone()
		spawnedVFX = clone
		if clone:IsA("Model") then
			clone:ScaleTo(sizeMultiplier)
		elseif clone:IsA("BasePart") then
			clone.Size *= sizeMultiplier
		end

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

	local vortexPE = makeFlameEmitter(vortexAtt, 90, 3.8 * sizeMultiplier, 18)
	vortexPE.SpreadAngle = Vector2.new(180, 45)
	vortexPE.Speed = NumberRange.new(14, 26)
	vortexPE.Lifetime = NumberRange.new(0.3, 0.55)

	local vortexEmbers = makeEmberEmitter(vortexAtt, 50)
	vortexEmbers.Speed = NumberRange.new(15, 30)

	-- Dynamic light attached to player
	local spinLight = Instance.new("PointLight")
	spinLight.Color = Color3.fromRGB(255, 140, 30)
	spinLight.Brightness = 7
	spinLight.Range = 22 * sizeMultiplier
	spinLight.Parent = rootPart

	-- 4. Ground Scorch pulses & camera pulses every 0.45s for 5.0 seconds
	local startTime = os.clock()
	task.spawn(function()
		while os.clock() - startTime < duration do
			if not char or not char.Parent or not rootPart or not rootPart.Parent then break end
			spawnGroundScorch(rootPart.Position, 9.0 * sizeMultiplier, 1.4)
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
-- Skill 2: Missile Barrage Buff & Guided Missile System
-- ─────────────────────────────────────────────────────────────────────────────
local function playMissileBuffVFX(char: Model)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	char:SetAttribute("IsMissileBuffActive", true)

	-- Brief activation flash on character
	local buffAtt = Instance.new("Attachment")
	buffAtt.Name = "MissileBuffActivation"
	buffAtt.Position = Vector3.new(0, 1.5, 0)
	buffAtt.Parent = rootPart

	local flamePE = makeFlameEmitter(buffAtt, 0, 3.5, 18)
	flamePE:Emit(25)

	local emberPE = makeEmberEmitter(buffAtt, 0)
	emberPE:Emit(20)

	task.delay(0.6, function()
		if buffAtt and buffAtt.Parent then
			buffAtt:Destroy()
		end
	end)

	-- Buff duration: 8.0 seconds
	task.delay(8.0, function()
		if char and char.Parent then
			char:SetAttribute("IsMissileBuffActive", false)
		end
	end)
end

local function launchSingleMissile(casterChar: Model, missileIndex: number)
	local rootPart = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local lookVec = rootPart.CFrame.LookVector
	local rightVec = rootPart.CFrame.RightVector
	local upVec = Vector3.new(0, 1, 0)

	-- 1. Spawn position & launch angle staggered per missile in succession
	local sideSigns = { -1, 1, 0.6, -1.1, -0.4 }
	local sideSign = sideSigns[((missileIndex - 1) % #sideSigns) + 1] or (math.random() > 0.5 and 1 or -1)
	local spawnOffset = upVec * 1.5 + rightVec * (sideSign * 1.1) - lookVec * 0.2
	local spawnPos = rootPart.Position + spawnOffset

	-- 2. Initial launch direction: arced wide outward and upward/forward
	local outwardRatio = (math.random(70, 115) / 100) * sideSign
	local upwardRatio = math.random(25, 75) / 100 * (missileIndex % 2 == 1 and 1 or 0.6)
	local forwardRatio = math.random(30, 50) / 100
	local currentDir = (lookVec * forwardRatio + rightVec * outwardRatio + upVec * upwardRatio).Unit
	local currentSpeed = 46.0 -- Initial launch speed
	local maxSpeed = 110.0    -- Terminal cruising speed
	local currentPos = spawnPos
	local currentVel = currentDir * currentSpeed

	-- 3. Find missile VFX asset from ReplicatedStorage
	local missileTemplate = findVFXAsset("missile") or findVFXAsset("Missile") or findVFXAsset("hk_missile")
	local missileInstance: Instance? = nil

	if missileTemplate then
		missileInstance = missileTemplate:Clone()
		for _, d in ipairs(missileInstance:GetDescendants()) do
			if d:IsA("BasePart") then
				d.CanCollide = false
				d.CanTouch = false
				d.CanQuery = false
				d.Anchored = true
			elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
				d.Enabled = true
			end
		end
		if missileInstance:IsA("BasePart") then
			missileInstance.CanCollide = false
			missileInstance.CanTouch = false
			missileInstance.CanQuery = false
			missileInstance.Anchored = true
		end
		missileInstance.Parent = Workspace.Terrain
	end

	-- 4. Create carrier part as physics/visual anchor
	local carrier = Instance.new("Part")
	carrier.Name = `MissileCarrier_{missileIndex}`
	carrier.Size = Vector3.new(0.3, 0.3, 0.9)
	carrier.Transparency = 0.2
	carrier.Material = Enum.Material.Neon
	carrier.Color = Color3.fromRGB(255, 120, 20)
	carrier.CanCollide = false
	carrier.CanTouch = false
	carrier.CanQuery = false
	carrier.Anchored = true
	carrier.CFrame = CFrame.lookAt(spawnPos, spawnPos + currentDir)
	carrier.Parent = Workspace.Terrain

	-- Add sleek fire red / amber energy ribbon trail
	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0.25, 0)
	att0.Parent = carrier

	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, -0.25, 0)
	att1.Parent = carrier

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 140)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(255, 120, 20)),
		ColorSequenceKeypoint.new(0.75, Color3.fromRGB(230, 40, 10)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(150, 15, 0)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.6, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.38
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3),
		NumberSequenceKeypoint.new(0.5, 0.8),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	trail.FaceCamera = true
	trail.Parent = carrier

	-- Fire / Amber exhaust emitter & light
	local rocketAtt = Instance.new("Attachment")
	rocketAtt.Parent = carrier

	local energyPE = Instance.new("ParticleEmitter")
	energyPE.Name = "EnergyEmitter"
	energyPE.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 240, 180)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(255, 130, 20)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 30, 5)),
	})
	energyPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.7),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	energyPE.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(1, 1),
	})
	energyPE.Lifetime = NumberRange.new(0.18, 0.32)
	energyPE.Rate = 90
	energyPE.Speed = NumberRange.new(4, 10)
	energyPE.SpreadAngle = Vector2.new(15, 15)
	energyPE.Parent = rocketAtt

	local rocketLight = Instance.new("PointLight")
	rocketLight.Color = Color3.fromRGB(255, 120, 25)
	rocketLight.Brightness = 4.5
	rocketLight.Range = 9
	rocketLight.Parent = carrier

	if missileInstance then
		if missileInstance:IsA("Model") then
			missileInstance:PivotTo(carrier.CFrame)
		elseif missileInstance:IsA("BasePart") then
			missileInstance.CFrame = carrier.CFrame
		elseif missileInstance:IsA("Attachment") then
			missileInstance.Parent = carrier
		end
	end

	-- Search for nearest enemy target in workspace (including Workspace.Mobs)
	local function findNearestEnemy(pos: Vector3): (Model?, BasePart?)
		local bestDist = 140
		local bestTarget: Model? = nil
		local bestPart: BasePart? = nil

		for _, desc in ipairs(Workspace:GetDescendants()) do
			if desc:IsA("Model") and desc ~= casterChar and not desc:IsDescendantOf(casterChar) then
				if desc:FindFirstAncestorOfClass("Accessory") then continue end

				local hum = desc:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then
					local root = (desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")) :: BasePart?
					if root then
						local dist = (root.Position - pos).Magnitude
						if dist < bestDist then
							bestDist = dist
							bestTarget = desc
							bestPart = root
						end
					end
				end
			end
		end
		return bestTarget, bestPart
	end

	task.spawn(function()
		local startTime = os.clock()
		local maxLifetime = 3.5
		local targetModel, targetRoot = findNearestEnemy(spawnPos)

		while os.clock() - startTime < maxLifetime do
			local dt = RunService.RenderStepped:Wait()
			local elapsed = os.clock() - startTime

			-- Continuously acquire or validate target position every frame
			if not targetModel or not targetModel.Parent or not targetRoot or not targetRoot.Parent or (targetModel:FindFirstChildOfClass("Humanoid") and targetModel:FindFirstChildOfClass("Humanoid").Health <= 0) then
				targetModel, targetRoot = findNearestEnemy(currentPos)
			end

			-- Determine desired aim point
			local targetAimPos: Vector3
			if targetRoot and targetRoot.Parent then
				targetAimPos = targetRoot.Position + Vector3.new(0, 0.5, 0)
			else
				local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
				local forward = (casterRoot and casterRoot.CFrame.LookVector) or lookVec
				targetAimPos = currentPos + forward * 80 + Vector3.new(0, 1.5, 0)
			end

			local toTarget = (targetAimPos - currentPos)
			local distToTarget = toTarget.Magnitude

			-- Direct impact on target
			if distToTarget < 2.2 and targetRoot and targetRoot.Parent then
				break
			end

			local desiredDir = toTarget.Unit

			-- Continuous smooth spherical curvature toward target (arcing then curving smoothly in)
			local turnRate = math.clamp(math.rad(140) + elapsed * math.rad(420), math.rad(140), math.rad(720))
			local maxTurnThisFrame = turnRate * dt

			local dot = math.clamp(currentDir:Dot(desiredDir), -1, 1)
			local angle = math.acos(dot)

			if angle > 0.001 then
				local turnStep = math.min(angle, maxTurnThisFrame)
				local rotAxis = currentDir:Cross(desiredDir)
				if rotAxis.Magnitude > 0.001 then
					currentDir = (CFrame.fromAxisAngle(rotAxis.Unit, turnStep) * currentDir).Unit
				else
					currentDir = (CFrame.Angles(0, turnStep, 0) * currentDir).Unit
				end
			end

			-- Accelerate forward along the newly curved trajectory
			currentSpeed = math.min(currentSpeed + 65.0 * dt, maxSpeed)
			currentVel = currentDir * currentSpeed
			currentPos = currentPos + currentVel * dt

			-- Rotate carrier and missile model to continually face flight direction (tangent to arc)
			local orientCF = CFrame.lookAt(currentPos, currentPos + currentDir)
			carrier.CFrame = orientCF

			if missileInstance and missileInstance.Parent then
				if missileInstance:IsA("Model") then
					missileInstance:PivotTo(orientCF)
				elseif missileInstance:IsA("BasePart") then
					missileInstance.CFrame = orientCF
				end
			end
		end

		-- Cleanup exhaust emitters and carrier (no explosion!)
		trail.Enabled = false
		energyPE.Enabled = false
		TweenService:Create(rocketLight, TweenInfo.new(0.12), { Brightness = 0 }):Play()
		Debris:AddItem(carrier, 0.35)

		if missileInstance and missileInstance.Parent then
			for _, d in ipairs(missileInstance:GetDescendants()) do
				if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
					d.Enabled = false
				end
			end
			Debris:AddItem(missileInstance, 0.35)
		end
	end)
end

function SkillController.LaunchMissile(casterChar: Model)
	task.spawn(function()
		local charPlayer = Players:GetPlayerFromCharacter(casterChar) or (player.Character == casterChar and player)
		local extraProjectiles = 0
		if charPlayer then
			extraProjectiles = math.max(0, math.floor(charPlayer:GetAttribute("Stat_projectileCount") or 0))
		end
		local missileCount = 5 + extraProjectiles
		for i = 1, missileCount do
			if not casterChar or not casterChar.Parent then break end
			launchSingleMissile(casterChar, i)
			task.wait(0.055)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 3: Phoenix Dash VFX (Dash + Fire Whirlwind)
-- ─────────────────────────────────────────────────────────────────────────────
local function playPhoenixDashVFX(char: Model, origin: Vector3, lookDir: Vector3)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local dashDist = 24
	local dashSpeed = 80
	local duration = 0.28

	-- 1. Apply physical LinearVelocity with zero vertical force
	local att = Instance.new("Attachment")
	att.Name = "DashAttachment"
	att.Parent = rootPart

	local lv = Instance.new("LinearVelocity")
	lv.Name = "DashLinearVelocity"
	lv.Attachment0 = att
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(250000, 0, 250000)
	lv.VectorVelocity = flatDir * dashSpeed
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.Parent = rootPart

	-- Clamp upward vertical velocity during dash so colliding with walls/obstacles cannot launch player
	local isDashing = true
	local groundLockConn: RBXScriptConnection? = nil
	groundLockConn = RunService.Heartbeat:Connect(function()
		if not isDashing or not rootPart or not rootPart.Parent then return end
		local vel = rootPart.AssemblyLinearVelocity
		if vel.Y > 0 then
			rootPart.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
		end
	end)

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

		local dashOrientCF = CFrame.lookAt(rootPart.Position, rootPart.Position + flatDir) * CFrame.Angles(math.rad(-90), 0, 0)

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
		isDashing = false
		if groundLockConn then
			groundLockConn:Disconnect()
			groundLockConn = nil
		end

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
	local weapon = char:FindFirstChild("EquippedWeapon") or char:FindFirstChild("PreviewGreatsword") or char:FindFirstChildOfClass("Tool") or player.Backpack:FindFirstChildOfClass("Tool")
	local bladeMesh: BasePart? = nil

	if weapon then
		local handle = weapon:FindFirstChild("Handle") :: BasePart?
		bladeMesh = handle
		for _, desc in ipairs(weapon:GetDescendants()) do
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
	local travelDist = 32.0
	local impactPos = origin + flatDir * travelDist

	-- 1. Find and clone custom hk_ULT asset from ReplicatedStorage.generalVFX
	local ultTemplate = findVFXAsset("hk_ULT") or findVFXAsset("hk_ult") or findVFXAsset("ULT") or findVFXAsset("ult")
	local spawnedUltVFX: Instance? = nil

	-- Find sword blade mesh
	local weapon = char:FindFirstChild("EquippedWeapon") or char:FindFirstChild("PreviewGreatsword") or char:FindFirstChildOfClass("Tool") or player.Backpack:FindFirstChildOfClass("Tool")
	local bladeMesh: BasePart? = nil
	if weapon then
		local handle = weapon:FindFirstChild("Handle") :: BasePart?
		bladeMesh = handle
		for _, desc in ipairs(weapon:GetDescendants()) do
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

	-- 3. Moving traveling slash wave (Shot 3: uses 'hk_ult_slash' asset, travels fast in 1.1s from t=1.70s to t=2.80s)
	local function spawnTravelingSlashVFX()
		if not char or not char.Parent then return end
		local slashTemplate = findVFXAsset("hk_ult_slash") or findVFXAsset("hk_ult") or findVFXAsset("ult_slash")
		local slashClone: Instance? = nil
		local slashStartPos = rootPart.Position + flatDir * 3.0 + Vector3.new(0, 1.2, 0)
		local endP = impactPos + Vector3.new(0, 1.2, 0)

		if slashTemplate then
			slashClone = slashTemplate:Clone()
			if slashClone:IsA("Model") then
				local prim = slashClone.PrimaryPart or slashClone:FindFirstChildWhichIsA("BasePart")
				if prim then
					prim.CanCollide = false
					prim.CanTouch = false
					prim.CanQuery = false
					prim.Anchored = true
					slashClone:PivotTo(CFrame.lookAt(slashStartPos, slashStartPos + flatDir))
				end
				for _, d in ipairs(slashClone:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
						d.CanTouch = false
						d.CanQuery = false
						d.Anchored = true
					elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
						d.Enabled = true
					end
				end
			elseif slashClone:IsA("BasePart") then
				slashClone.CanCollide = false
				slashClone.CanTouch = false
				slashClone.CanQuery = false
				slashClone.Anchored = true
				slashClone.CFrame = CFrame.lookAt(slashStartPos, slashStartPos + flatDir)
				for _, d in ipairs(slashClone:GetDescendants()) do
					if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
						d.Enabled = true
					end
				end
			elseif slashClone:IsA("Attachment") then
				local carrier = Instance.new("Part")
				carrier.Size = Vector3.new(1, 1, 1)
				carrier.Transparency = 1
				carrier.CanCollide = false
				carrier.Anchored = true
				carrier.CFrame = CFrame.lookAt(slashStartPos, slashStartPos + flatDir)
				slashClone.Parent = carrier
				slashClone = carrier
			end
			slashClone.Parent = Workspace.Terrain
		else
			-- Procedural fiery crescent slash wave fallback
			local slashPart = Instance.new("Part")
			slashPart.Name = "ProceduralSlashWave"
			slashPart.Size = Vector3.new(12, 1.5, 4)
			slashPart.Transparency = 0.25
			slashPart.Material = Enum.Material.Neon
			slashPart.Color = Color3.fromRGB(255, 115, 25)
			slashPart.CanCollide = false
			slashPart.CanTouch = false
			slashPart.CanQuery = false
			slashPart.Anchored = true
			slashPart.CFrame = CFrame.lookAt(slashStartPos, slashStartPos + flatDir)

			local slashMesh = Instance.new("SpecialMesh")
			slashMesh.MeshType = Enum.MeshType.Sphere
			slashMesh.Scale = Vector3.new(1, 0.15, 0.6)
			slashMesh.Parent = slashPart

			local pe = Instance.new("ParticleEmitter")
			pe.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 230, 90)),
				ColorSequenceKeypoint.new(0.5, Color3.fromRGB(255, 90, 20)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 20, 10)),
			})
			pe.LightEmission = 1
			pe.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 3.5),
				NumberSequenceKeypoint.new(1, 0.5),
			})
			pe.Lifetime = NumberRange.new(0.2, 0.45)
			pe.Rate = 90
			pe.Speed = NumberRange.new(6, 16)
			pe.SpreadAngle = Vector2.new(30, 15)
			pe.Orientation = Enum.ParticleOrientation.VelocityParallel
			pe.Parent = slashPart

			local pLight = Instance.new("PointLight")
			pLight.Color = Color3.fromRGB(255, 120, 30)
			pLight.Range = 16
			pLight.Brightness = 3
			pLight.Parent = slashPart

			slashPart.Parent = Workspace.Terrain
			slashClone = slashPart
		end

		-- Fast travel: 0.60s duration across 32 studs (very fast slash)
		task.spawn(function()
			local travelDuration = 0.60
			local travelStart = os.clock()

			while os.clock() - travelStart < travelDuration do
				local alpha = math.clamp((os.clock() - travelStart) / travelDuration, 0, 1)
				local curP = slashStartPos:Lerp(endP, alpha)
				if slashClone and slashClone.Parent then
					local orientCF = CFrame.lookAt(curP, curP + flatDir)
					if slashClone:IsA("Model") then
						slashClone:PivotTo(orientCF)
					elseif slashClone:IsA("BasePart") then
						slashClone.CFrame = orientCF
					end
				end
				RunService.RenderStepped:Wait()
			end

			if slashClone and slashClone.Parent then
				for _, d in ipairs(slashClone:GetDescendants()) do
					if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
						d.Enabled = false
					end
				end
				Debris:AddItem(slashClone, 0.4)
			end
		end)
	end

	-- 4. Impact explosion using 'Light Explosion VFX' asset
	local function triggerImpactVFX()
		if not char or not char.Parent then return end

		-- Spawn Crater Debris
		spawnCraterDebris(impactPos, 8.0, 16)

		-- Spawn 'Light Explosion VFX' asset
		local explTemplate = findVFXAsset("Light Explosion VFX") or findVFXAsset("Light Explosion") or findVFXAsset("Light_Explosion_VFX") or findVFXAsset("Explosion")
		if explTemplate then
			local explClone = explTemplate:Clone()
			if explClone:IsA("Model") then
				explClone:PivotTo(CFrame.new(impactPos))
				for _, d in ipairs(explClone:GetDescendants()) do
					if d:IsA("BasePart") then
						d.CanCollide = false
						d.CanTouch = false
						d.CanQuery = false
						d.Anchored = true
					elseif d:IsA("ParticleEmitter") then
						d.Enabled = true
						d:Emit(15)
					elseif d:IsA("Beam") or d:IsA("Trail") then
						d.Enabled = true
					end
				end
			elseif explClone:IsA("BasePart") then
				explClone.CanCollide = false
				explClone.Anchored = true
				explClone.CFrame = CFrame.new(impactPos)
				for _, d in ipairs(explClone:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						d.Enabled = true
						d:Emit(15)
					end
				end
			elseif explClone:IsA("Attachment") then
				explClone.CFrame = CFrame.new(impactPos)
				explClone.Parent = Workspace.Terrain
				for _, d in ipairs(explClone:GetDescendants()) do
					if d:IsA("ParticleEmitter") then
						d.Enabled = true
						d:Emit(15)
					end
				end
			end
			explClone.Parent = Workspace.Terrain

			task.delay(1.5, function()
				if explClone and explClone.Parent then
					for _, d in ipairs(explClone:GetDescendants()) do
						if d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
							d.Enabled = false
						end
					end
					Debris:AddItem(explClone, 0.5)
				end
			end)
		end
	end

	-- Trigger 4-shot Ultimate Camera Choreography for local player
	if char == player.Character then
		-- Shot 2 begins at t=1.0s: switch animation from windup to slash
		-- Slash VFX launches AFTER the animation finishes (0.50s later, at t=1.50s)
		local function onSlashStart()
			print("[SkillController] onSlashStart: executing ultimate slash attack phase") 
			-- 1. Explicitly stop windup track on the character
			local windupTrack = getSkillTrack(char, 4)
			if windupTrack and windupTrack.IsPlaying then
				windupTrack:Stop(0.08)
			end
			local hum = char:FindFirstChildOfClass("Humanoid")
			local animtr = hum and hum:FindFirstChildOfClass("Animator")
			if animtr then
				for _, t in ipairs(animtr:GetPlayingAnimationTracks()) do
					if t.Animation and (t.Animation.AnimationId == "rbxassetid://84579017139529" or t.Name == "SkillAnim_4") then
						t:Stop(0.08)
					end
				end
			end

			-- 2. Play slash attack animation at highest priority
			local slashTrack = getSkillSlashTrack(char, 4)
			if slashTrack then
				slashTrack.Priority = Enum.AnimationPriority.Action4
				slashTrack:Play(0.05)
			else
				warn("[SkillController] Skill 4 slash track not found!")
			end

			-- Keep weapon flame aura and enlarged trail active during swing
			setWeaponTrailEnlarged(char, true)

			-- 3. Launch traveling slash wave as the sword strikes down (0.45s)
			task.delay(0.45, function()
				spawnTravelingSlashVFX()
			end)
		end

		UltimateCameraChoreography.PlaySequence(
			char,
			flatDir,
			function()
				-- Triggered at t = 2.10s (Shot 4: impact explosion)
				triggerImpactVFX()
			end,
			function()
				-- Completed at t = 3.10s
			end,
			onSlashStart
		)
	else
		-- For non-local players — slash launches at t=1.50s (after animation)
		task.delay(1.50, function()
			spawnTravelingSlashVFX()
		end)
		task.delay(2.10, function()
			triggerImpactVFX()
		end)
	end

	-- Cleanup sword aura and hk_ULT asset after sequence
	task.delay(3.5, function()
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

local NATURE_GREEN = Color3.fromRGB(72, 210, 92)
local FOREST_GREEN = Color3.fromRGB(18, 92, 42)
local POISON_PURPLE = Color3.fromRGB(145, 55, 190)

local function flatUnit(direction: Vector3): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.1 then
		return Vector3.new(0, 0, -1)
	end
	return flat.Unit
end

local function rotatedFlat(direction: Vector3, degrees: number): Vector3
	return (CFrame.Angles(0, math.rad(degrees), 0) * flatUnit(direction)).Unit
end

local function makeRangerArrow(startPos: Vector3, direction: Vector3, distance: number, color: Color3, width: number?, lifetime: number?)
	local dir = direction.Magnitude > 0.1 and direction.Unit or Vector3.new(0, 0, -1)
	local arrow = Instance.new("Part")
	arrow.Name = "RangerArrowVFX"
	arrow.Size = Vector3.new(width or 0.22, width or 0.22, 2.8)
	arrow.Material = Enum.Material.Neon
	arrow.Color = color
	arrow.CanCollide = false
	arrow.CanTouch = false
	arrow.CanQuery = false
	arrow.Anchored = true
	arrow.CFrame = CFrame.lookAt(startPos, startPos + dir)
	arrow.Parent = Workspace.Terrain

	local att0 = Instance.new("Attachment")
	att0.Position = Vector3.new(0, 0, 0.9)
	att0.Parent = arrow
	local att1 = Instance.new("Attachment")
	att1.Position = Vector3.new(0, 0, -1.1)
	att1.Parent = arrow

	local trail = Instance.new("Trail")
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.Color = ColorSequence.new(color, POISON_PURPLE)
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(0.7, 0.35),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.Lifetime = 0.28
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, width or 0.55),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	trail.FaceCamera = true
	trail.Parent = arrow

	local travelTime = lifetime or 0.32
	local endPos = startPos + dir * distance
	TweenService:Create(arrow, TweenInfo.new(travelTime, Enum.EasingStyle.Linear), {
		CFrame = CFrame.lookAt(endPos, endPos + dir),
	}):Play()
	Debris:AddItem(arrow, travelTime + 0.35)
	return endPos
end

local function playRangerBasicAttackVFX(char: Model, lookDir: Vector3)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end
	local startPos = rootPart.Position + Vector3.new(0, 1.4, 0) + flatUnit(lookDir) * 2
	makeRangerArrow(startPos, lookDir, 70, NATURE_GREEN, 0.18, 0.26)
end

local function playRangerShootAnimation(char: Model)
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local animator = humanoid and humanoid:FindFirstChildOfClass("Animator")
	if not humanoid or not animator then return end

	local track = rangerShootTracks[humanoid]
	if not track then
		local animation = Instance.new("Animation")
		animation.Name = "RangerShoot"
		animation.AnimationId = RANGER_SHOOT_ANIMATION_ID
		track = animator:LoadAnimation(animation)
		track.Priority = Enum.AnimationPriority.Action4
		track.Looped = false
		rangerShootTracks[humanoid] = track
	end

	if track.IsPlaying then track:Stop(0.05) end
	track:Play(0.05)
end

local function findRangerArrowImpact(casterChar: Model, origin: Vector3, direction: Vector3, range: number, width: number): Vector3
	local bestAlong = range
	local bestPos = origin + flatUnit(direction) * range
	local flatDir = flatUnit(direction)

	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc ~= casterChar and not desc:IsDescendantOf(casterChar) and not desc:FindFirstAncestorOfClass("Accessory") then
			local hum = desc:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local root = (desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")) :: BasePart?
				if root then
					local diff = root.Position - origin
					local flatDiff = Vector3.new(diff.X, 0, diff.Z)
					local along = flatDiff:Dot(flatDir)
					if along >= 0 and along <= range then
						local closest = origin + flatDir * along
						local lateral = (Vector3.new(root.Position.X, origin.Y, root.Position.Z) - closest).Magnitude
						if lateral <= width and along < bestAlong then
							bestAlong = along
							bestPos = root.Position
						end
					end
				end
			end
		end
	end

	return bestPos
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 2: Entangling Arrow VFX (Realistic Thick Woodland Briar Vines with Leaves)
-- Recreates thick gnarled briar vines, ground root matting, body-binding helical
-- coils wrapping the legs/chest/arms, and arching tendrils with glowing lime leaves.
-- ─────────────────────────────────────────────────────────────────────────────
local VINE_BARK_DARK = Color3.fromRGB(46, 72, 32)
local VINE_BARK_MID = Color3.fromRGB(60, 94, 42)
local VINE_BARK_LIGHT = Color3.fromRGB(76, 116, 52)
local LEAF_LIME = Color3.fromRGB(155, 245, 75)
local LEAF_GLOW = Color3.fromRGB(188, 255, 95)
local LEAF_DEEP = Color3.fromRGB(105, 195, 55)

local function createVineSegment(parent: Instance, p1: Vector3, p2: Vector3, thickness: number, color: Color3, material: Enum.Material?): BasePart?
	local diff = p2 - p1
	local length = diff.Magnitude
	if length < 0.04 then return nil end

	local part = Instance.new("Part")
	part.Name = "VineStem"
	part.Shape = Enum.PartType.Cylinder
	part.Size = Vector3.new(length, thickness, thickness)
	part.Color = color
	part.Material = material or Enum.Material.Wood
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.Anchored = true
	part.CFrame = CFrame.lookAt((p1 + p2) * 0.5, p2) * CFrame.Angles(0, math.rad(90), 0)
	part.Parent = parent
	return part
end

local function createVineJointNode(parent: Instance, pos: Vector3, size: number, color: Color3): BasePart
	local node = Instance.new("Part")
	node.Name = "VineNode"
	node.Shape = Enum.PartType.Ball
	node.Size = Vector3.new(size, size, size)
	node.Color = color
	node.Material = Enum.Material.Wood
	node.CanCollide = false
	node.CanTouch = false
	node.CanQuery = false
	node.Anchored = true
	node.CFrame = CFrame.new(pos)
	node.Parent = parent
	return node
end

local function createLeafSprout(parent: Instance, position: Vector3, normal: Vector3, scale: number?): BasePart
	local s = scale or 1.0
	local leaf = Instance.new("Part")
	leaf.Name = "VineLeaf"
	leaf.Size = Vector3.new(0.32 * s, 0.08 * s, 0.72 * s)
	leaf.Material = Enum.Material.Neon
	leaf.Color = math.random() > 0.35 and LEAF_LIME or LEAF_GLOW
	leaf.CanCollide = false
	leaf.CanTouch = false
	leaf.CanQuery = false
	leaf.Anchored = true

	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Scale = Vector3.new(1, 0.18, 1.85)
	mesh.Parent = leaf

	local outDir = (normal + Vector3.new((math.random() - 0.5) * 0.3, 0.25, (math.random() - 0.5) * 0.3)).Unit
	local cf = CFrame.lookAt(position, position + outDir) * CFrame.Angles(
		math.rad(math.random(-15, 15)),
		0,
		math.rad(math.random(-25, 25))
	)
	leaf.CFrame = cf
	leaf.Parent = parent
	return leaf
end

local function spawnVinePinRing(targetRoot: BasePart, duration: number)
	local targetModel = targetRoot:FindFirstAncestorOfClass("Model")
	local bounds = targetModel and targetModel:GetExtentsSize() or Vector3.new(2.5, 5.0, 2.5)
	local rootPos = targetRoot.Position
	local charRadius = math.clamp(math.max(bounds.X, bounds.Z) * 0.52, 1.35, 3.8)
	local charHeight = math.clamp(bounds.Y, 4.4, 10.0)

	-- Find ground surface directly beneath target
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { targetModel or targetRoot }
	rayParams.IgnoreWater = true
	local groundRay = Workspace:Raycast(rootPos, Vector3.new(0, -7, 0), rayParams)
	local groundY = groundRay and groundRay.Position.Y or (rootPos.Y - (charHeight * 0.5))
	local centerBase = Vector3.new(rootPos.X, groundY, rootPos.Z)

	local prison = Instance.new("Model")
	prison.Name = "EntangleVinePrisonVFX"
	prison.Parent = Workspace.Terrain

	local allParts: { BasePart } = {}

	-- Helper to track and register parts
	local function regPart(p: BasePart?)
		if p then table.insert(allParts, p) end
		return p
	end

	-- =========================================================================
	-- 1. GROUND ROOT MAT (Radial crawling roots across the floor)
	-- =========================================================================
	local numRoots = 9
	for r = 1, numRoots do
		local baseAngle = (r / numRoots) * math.pi * 2 + (math.random() - 0.5) * 0.35
		local rootLength = math.random(34, 52) / 10
		local steps = 4
		local prevP = centerBase + Vector3.new(math.cos(baseAngle) * 0.6, 0.08, math.sin(baseAngle) * 0.6)

		for s = 1, steps do
			local distFraction = s / steps
			local curDist = 0.6 + (rootLength - 0.6) * distFraction
			local curveAngle = baseAngle + math.sin(s * 1.8 + r) * 0.28
			local curP = centerBase + Vector3.new(
				math.cos(curveAngle) * curDist,
				0.06 + math.sin(s * 1.2) * 0.08,
				math.sin(curveAngle) * curDist
			)
			local thick = math.max(0.18, 0.44 * (1 - distFraction * 0.55))
			local color = (s % 2 == 0) and VINE_BARK_MID or VINE_BARK_DARK
			regPart(createVineSegment(prison, prevP, curP, thick, color))
			regPart(createVineJointNode(prison, curP, thick * 1.08, color))

			-- Ground leaves sprouting along root branches
			if s >= 2 and math.random() > 0.3 then
				local leafDir = Vector3.new(math.cos(curveAngle + math.pi * 0.5), 0.3, math.sin(curveAngle + math.pi * 0.5))
				regPart(createLeafSprout(prison, curP, leafDir, 0.85))
				if math.random() > 0.5 then
					regPart(createLeafSprout(prison, curP, -leafDir, 0.75))
				end
			end

			prevP = curP
		end
	end

	-- =========================================================================
	-- 2. LOWER HELIX (Tightly binding the legs & knees)
	-- =========================================================================
	local legSteps = 16
	local legTurns = 2.2
	local legBottom = 0.2
	local legTop = charHeight * 0.38
	local prevLegP = centerBase + Vector3.new(math.cos(0) * (charRadius * 0.85), legBottom, math.sin(0) * (charRadius * 0.85))

	for i = 1, legSteps do
		local alpha = i / legSteps
		local angle = alpha * math.pi * 2 * legTurns + 0.3
		local radius = charRadius * (0.82 + math.sin(i * 1.5) * 0.08)
		local curY = legBottom + (legTop - legBottom) * alpha
		local curP = centerBase + Vector3.new(math.cos(angle) * radius, curY, math.sin(angle) * radius)
		local thick = 0.42
		local col = (i % 2 == 0) and VINE_BARK_MID or VINE_BARK_LIGHT

		regPart(createVineSegment(prison, prevLegP, curP, thick, col))
		regPart(createVineJointNode(prison, curP, thick * 1.1, col))

		-- Leaf pairs facing outward
		if i % 3 == 0 then
			local outNorm = Vector3.new(math.cos(angle), 0.15, math.sin(angle))
			regPart(createLeafSprout(prison, curP, outNorm, 0.95))
		end

		prevLegP = curP
	end

	-- =========================================================================
	-- 3. TORSO & ARMS HELIX (Tightly binding waist, chest & upper limbs)
	-- =========================================================================
	local torsoSteps = 18
	local torsoTurns = 2.1
	local torsoBottom = charHeight * 0.34
	local torsoTop = charHeight * 0.76
	local startAngleTorso = math.pi * 0.7
	local prevTorsoP = centerBase + Vector3.new(
		math.cos(startAngleTorso) * (charRadius * 1.05),
		torsoBottom,
		math.sin(startAngleTorso) * (charRadius * 1.05)
	)

	for i = 1, torsoSteps do
		local alpha = i / torsoSteps
		local angle = startAngleTorso + alpha * math.pi * 2 * torsoTurns
		-- Bulge slightly around chest and shoulders
		local radiusMultiplier = 1.02 + math.sin(alpha * math.pi) * 0.14
		local radius = charRadius * radiusMultiplier
		local curY = torsoBottom + (torsoTop - torsoBottom) * alpha
		local curP = centerBase + Vector3.new(math.cos(angle) * radius, curY, math.sin(angle) * radius)
		local thick = 0.46
		local col = (i % 2 == 0) and VINE_BARK_LIGHT or VINE_BARK_MID

		regPart(createVineSegment(prison, prevTorsoP, curP, thick, col))
		regPart(createVineJointNode(prison, curP, thick * 1.1, col))

		-- Sprout glowing leaves prominently from chest/arm bindings
		if i % 2 == 0 then
			local outNorm = Vector3.new(math.cos(angle), 0.2, math.sin(angle))
			regPart(createLeafSprout(prison, curP, outNorm, 1.05))
			if i % 4 == 0 then
				local sideNorm = Vector3.new(-math.sin(angle), 0.3, math.cos(angle))
				regPart(createLeafSprout(prison, curP, sideNorm, 0.85))
			end
		end

		prevTorsoP = curP
	end

	-- =========================================================================
	-- 4. CROSS-DIAGONAL BODY BINDING (From hip across chest to shoulder)
	-- =========================================================================
	local diagSteps = 10
	local diagStart = centerBase + Vector3.new(-charRadius * 0.95, charHeight * 0.3, charRadius * 0.4)
	local diagEnd = centerBase + Vector3.new(charRadius * 0.95, charHeight * 0.74, -charRadius * 0.3)
	local prevDiagP = diagStart

	for i = 1, diagSteps do
		local alpha = i / diagSteps
		local midPoint = diagStart:Lerp(diagEnd, alpha)
		-- Push outwards along front body contour
		local pushOut = Vector3.new(0, 0, math.sin(alpha * math.pi) * (charRadius * 0.35))
		local curP = midPoint + pushOut
		local thick = 0.38
		local col = VINE_BARK_DARK

		regPart(createVineSegment(prison, prevDiagP, curP, thick, col))
		regPart(createVineJointNode(prison, curP, thick * 1.08, col))

		if i % 3 == 0 then
			local outNorm = (curP - targetRoot.Position).Unit
			regPart(createLeafSprout(prison, curP, outNorm, 0.9))
		end

		prevDiagP = curP
	end

	-- =========================================================================
	-- 5. HIGH ARCHING TENDRILS (Iconic tendrils curling up behind head/shoulders)
	-- =========================================================================
	-- Tendril 1: Right back tendril arching high above head
	local t1Steps = 9
	local t1Base = centerBase + Vector3.new(charRadius * 0.8, charHeight * 0.65, -charRadius * 0.6)
	local prevT1 = t1Base
	for i = 1, t1Steps do
		local alpha = i / t1Steps
		local curY = charHeight * 0.65 + math.sin(alpha * math.pi * 0.75) * (charHeight * 0.52)
		local curX = charRadius * 0.8 + alpha * 0.9
		local curZ = -charRadius * 0.6 - math.sin(alpha * math.pi) * 0.85
		local curP = centerBase + Vector3.new(curX, curY, curZ)
		local thick = math.max(0.16, 0.38 * (1 - alpha * 0.5))
		local col = VINE_BARK_LIGHT

		regPart(createVineSegment(prison, prevT1, curP, thick, col))
		regPart(createVineJointNode(prison, curP, thick * 1.1, col))

		-- Sprouting prominent leaf pairs along the arch
		local leafNorm = Vector3.new(0.5, 0.4, -0.6)
		regPart(createLeafSprout(prison, curP, leafNorm, 1.1))

		-- Tip leaf crown
		if i == t1Steps then
			regPart(createLeafSprout(prison, curP, Vector3.new(0.7, 0.7, -0.2), 1.25))
			regPart(createLeafSprout(prison, curP, Vector3.new(0.3, 0.8, -0.7), 1.2))
			regPart(createLeafSprout(prison, curP, Vector3.new(-0.2, 0.9, -0.4), 1.15))
		end

		prevT1 = curP
	end

	-- Tendril 2: Left back tendril arching outward and forward
	local t2Steps = 8
	local t2Base = centerBase + Vector3.new(-charRadius * 0.85, charHeight * 0.62, -charRadius * 0.5)
	local prevT2 = t2Base
	for i = 1, t2Steps do
		local alpha = i / t2Steps
		local curY = charHeight * 0.62 + math.sin(alpha * math.pi * 0.75) * (charHeight * 0.42)
		local curX = -charRadius * 0.85 - alpha * 0.75
		local curZ = -charRadius * 0.5 + math.sin(alpha * math.pi) * 0.65
		local curP = centerBase + Vector3.new(curX, curY, curZ)
		local thick = math.max(0.16, 0.36 * (1 - alpha * 0.45))
		local col = VINE_BARK_LIGHT

		regPart(createVineSegment(prison, prevT2, curP, thick, col))
		regPart(createVineJointNode(prison, curP, thick * 1.1, col))

		local leafNorm = Vector3.new(-0.6, 0.4, 0.3)
		regPart(createLeafSprout(prison, curP, leafNorm, 1.05))

		-- Tip leaf cluster
		if i == t2Steps then
			regPart(createLeafSprout(prison, curP, Vector3.new(-0.6, 0.7, 0.5), 1.2))
			regPart(createLeafSprout(prison, curP, Vector3.new(-0.8, 0.6, -0.2), 1.15))
		end

		prevT2 = curP
	end

	-- =========================================================================
	-- 6. MYSTICAL LEAVES & SPORE PARTICLES + EMERALD LIGHTING
	-- =========================================================================
	local lightPart = Instance.new("Part")
	lightPart.Name = "EntangleCenterAnchor"
	lightPart.Size = Vector3.new(0.5, 0.5, 0.5)
	lightPart.Transparency = 1
	lightPart.CanCollide = false
	lightPart.CanTouch = false
	lightPart.CanQuery = false
	lightPart.Anchored = true
	lightPart.CFrame = CFrame.new(centerBase + Vector3.new(0, charHeight * 0.45, 0))
	lightPart.Parent = prison

	local pLight = Instance.new("PointLight")
	pLight.Color = Color3.fromRGB(125, 240, 65)
	pLight.Brightness = 3.6
	pLight.Range = charRadius * 4.8
	pLight.Parent = lightPart

	-- Floating leaves gently swirling upward
	local leafAtt = Instance.new("Attachment")
	leafAtt.Parent = lightPart

	local leavesPE = Instance.new("ParticleEmitter")
	leavesPE.Name = "FloatingEntangleLeaves"
	leavesPE.Texture = "rbxassetid://258128463"
	leavesPE.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(165, 250, 85)),
		ColorSequenceKeypoint.new(0.6, Color3.fromRGB(135, 230, 65)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 180, 45)),
	})
	leavesPE.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.15),
		NumberSequenceKeypoint.new(0.75, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	leavesPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.45),
		NumberSequenceKeypoint.new(0.5, 0.7),
		NumberSequenceKeypoint.new(1, 0.35),
	})
	leavesPE.Lifetime = NumberRange.new(1.6, 2.6)
	leavesPE.Rate = 18
	leavesPE.Speed = NumberRange.new(1.0, 2.8)
	leavesPE.SpreadAngle = Vector2.new(60, 60)
	leavesPE.Rotation = NumberRange.new(0, 360)
	leavesPE.RotSpeed = NumberRange.new(-50, 50)
	leavesPE.Parent = leafAtt
	leavesPE:Emit(15)

	-- Spores / sparkling pollen
	local sporesPE = Instance.new("ParticleEmitter")
	sporesPE.Name = "EntangleSporeGlow"
	sporesPE.Color = ColorSequence.new(Color3.fromRGB(185, 255, 100))
	sporesPE.LightEmission = 1
	sporesPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.25),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	sporesPE.Lifetime = NumberRange.new(1.2, 2.0)
	sporesPE.Rate = 22
	sporesPE.Speed = NumberRange.new(0.6, 2.0)
	sporesPE.SpreadAngle = Vector2.new(180, 45)
	sporesPE.Parent = leafAtt
	sporesPE:Emit(20)

	-- =========================================================================
	-- 7. GROWTH BURST & DISSIPATION ANIMATION
	-- =========================================================================
	-- Store original CFrames & scales for smooth growth & crumble
	local partOrigData: { part: BasePart, origCF: CFrame, origSize: Vector3 } = {}
	for _, p in ipairs(allParts) do
		table.insert(partOrigData, { part = p, origCF = p.CFrame, origSize = p.Size })
	end

	-- Rapid surging growth in (0.18s): parts scale up from ground level
	local growDuration = 0.18
	local growStartTime = os.clock()
	local growConn: RBXScriptConnection?
	growConn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - growStartTime
		local alpha = math.clamp(elapsed / growDuration, 0, 1)
		local smoothAlpha = 1 - math.pow(1 - alpha, 3)

		for _, data in ipairs(partOrigData) do
			if data.part and data.part.Parent then
				-- Grow upward from ground position
				local groundTargetCF = CFrame.new(data.origCF.Position.X, groundY, data.origCF.Position.Z)
				data.part.CFrame = groundTargetCF:Lerp(data.origCF, smoothAlpha)
				data.part.Size = data.origSize * math.max(0.1, smoothAlpha)
			end
		end

		if alpha >= 1 then
			if growConn then growConn:Disconnect() end
			-- Restore exact full size
			for _, data in ipairs(partOrigData) do
				if data.part and data.part.Parent then
					data.part.CFrame = data.origCF
					data.part.Size = data.origSize
				end
			end
		end
	end)

	-- Fade and crumble decay at the end of root duration
	local decayTime = 0.38
	task.delay(math.max(0, duration - decayTime), function()
		if growConn then growConn:Disconnect() end
		leavesPE.Enabled = false
		sporesPE.Enabled = false

		local decayStart = os.clock()
		local decayConn: RBXScriptConnection?
		decayConn = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - decayStart
			local alpha = math.clamp(elapsed / decayTime, 0, 1)
			local smoothFade = math.pow(alpha, 2)

			for _, data in ipairs(partOrigData) do
				if data.part and data.part.Parent then
					data.part.Transparency = smoothFade
					data.part.Size = data.origSize * (1 - smoothFade * 0.4)
				end
			end

			pLight.Brightness = 3.6 * (1 - smoothFade)

			if alpha >= 1 then
				if decayConn then decayConn:Disconnect() end
				prison:Destroy()
			end
		end)
	end)
end

local function showPinnedTargets(casterChar: Model, center: Vector3, radius: number, duration: number)
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc ~= casterChar and not desc:IsDescendantOf(casterChar) and not desc:FindFirstAncestorOfClass("Accessory") then
			local humanoid = desc:FindFirstChildOfClass("Humanoid")
			local root = (desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")) :: BasePart?
			if humanoid and humanoid.Health > 0 and root and (root.Position - center).Magnitude <= radius then
				spawnVinePinRing(root, duration)
			end
		end
	end
end

local function spawnPoisonEmitter(center: Vector3, radius: number, duration: number)
	local holder = Instance.new("Part")
	holder.Name = "ToxicCloudVFX"
	holder.Size = Vector3.new(1, 1, 1)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Anchored = true
	holder.CFrame = CFrame.new(center + Vector3.new(0, 0.6, 0))
	holder.Parent = Workspace.Terrain

	local att = Instance.new("Attachment")
	att.Parent = holder

	local cloud = Instance.new("ParticleEmitter")
	cloud.Name = "PoisonSpores"
	cloud.Texture = "rbxassetid://258128463"
	cloud.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(90, 230, 85)),
		ColorSequenceKeypoint.new(0.55, Color3.fromRGB(48, 120, 54)),
		ColorSequenceKeypoint.new(1, POISON_PURPLE),
	})
	cloud.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.18),
		NumberSequenceKeypoint.new(1, 0.85),
	})
	cloud.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 3.5),
		NumberSequenceKeypoint.new(1, radius * 0.75),
	})
	cloud.Lifetime = NumberRange.new(1.8, 2.8)
	cloud.Rate = 90
	cloud.Speed = NumberRange.new(2, 7)
	cloud.SpreadAngle = Vector2.new(180, 45)
	cloud.Rotation = NumberRange.new(0, 360)
	cloud.RotSpeed = NumberRange.new(-45, 45)
	cloud.Parent = att

	local light = Instance.new("PointLight")
	light.Color = NATURE_GREEN
	light.Brightness = 3
	light.Range = radius * 1.6
	light.Parent = holder

	task.delay(duration, function()
		cloud.Enabled = false
		TweenService:Create(light, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		Debris:AddItem(holder, 3.0)
	end)
end

local function playRangerSkillVFX(char: Model, skillIndex: number, origin: Vector3, lookDir: Vector3, targetPosition: Vector3?, projectileCountParam: number?)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end
	local baseOrigin = rootPart.Position + Vector3.new(0, 1.35, 0)

	if skillIndex == 1 then
		local casterPlayer = Players:GetPlayerFromCharacter(char) or (player.Character == char and player)
		local extraCount = typeof(projectileCountParam) == "number" and projectileCountParam or (casterPlayer and math.max(0, math.floor(casterPlayer:GetAttribute("Stat_projectileCount") or 0)) or 0)
		local totalProjectiles = 5 + extraCount
		local stepAngle = 9.5
		local totalSpread = (totalProjectiles - 1) * stepAngle
		local startAngle = -totalSpread / 2
		for index = 1, totalProjectiles do
			local angle = startAngle + (index - 1) * stepAngle
			makeRangerArrow(baseOrigin + rotatedFlat(lookDir, angle) * 2, rotatedFlat(lookDir, angle), 64, NATURE_GREEN, 0.24, 0.32)
		end
	elseif skillIndex == 2 then
		local arrowStart = baseOrigin + flatUnit(lookDir) * 2
		local impactPos = findRangerArrowImpact(char, arrowStart, lookDir, 44, 2.8)
		local travelDistance = (impactPos - arrowStart).Magnitude
		local travelTime = math.clamp(travelDistance / 130, 0.08, 0.36)
		makeRangerArrow(arrowStart, lookDir, travelDistance, Color3.fromRGB(105, 245, 110), 0.32, travelTime)
		task.delay(travelTime, function()
			showPinnedTargets(char, impactPos, 10, 2.6)
			triggerCameraShake(char == player.Character and 0.35 or 0, 0.2)
		end)
	elseif skillIndex == 3 then
		local target = targetPosition or (origin + flatUnit(lookDir) * 34)
		local pod = Instance.new("Part")
		pod.Name = "SporePodVFX"
		pod.Shape = Enum.PartType.Ball
		pod.Size = Vector3.new(1.15, 1.15, 1.15)
		pod.Material = Enum.Material.Neon
		pod.Color = POISON_PURPLE
		pod.CanCollide = false
		pod.CanTouch = false
		pod.CanQuery = false
		pod.Anchored = true
		pod.CFrame = CFrame.new(baseOrigin)
		pod.Parent = Workspace.Terrain
		local mid = baseOrigin:Lerp(target + Vector3.new(0, 0.4, 0), 0.5) + Vector3.new(0, 11, 0)
		task.spawn(function()
			local start = os.clock()
			while os.clock() - start < 0.62 do
				local alpha = math.clamp((os.clock() - start) / 0.62, 0, 1)
				local a = baseOrigin:Lerp(mid, alpha)
				local b = mid:Lerp(target, alpha)
				local pos = a:Lerp(b, alpha)
				pod.CFrame = CFrame.new(pos)
				RunService.RenderStepped:Wait()
			end
			pod:Destroy()
			spawnPoisonEmitter(target, 13, 6.0)
		end)
	elseif skillIndex == 4 then
		makeRangerArrow(baseOrigin, Vector3.new(0, 0, -1), 0.1, Color3.fromRGB(185, 255, 145), 0.4, 0.08)
		local center = targetPosition or (origin + flatUnit(lookDir) * 42)
		local marker = Instance.new("Part")
		marker.Name = "RainOfArrowsMarker"
		marker.Shape = Enum.PartType.Cylinder
		marker.Size = Vector3.new(0.12, 36, 36)
		marker.Material = Enum.Material.Neon
		marker.Color = Color3.fromRGB(70, 180, 80)
		marker.Transparency = 0.62
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
		marker.Anchored = true
		marker.CFrame = CFrame.new(center + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
		marker.Parent = Workspace.Terrain
		task.delay(1.05, function()
			for i = 1, 70 do
				task.delay(i * 0.035, function()
					local angle = math.random() * math.pi * 2
					local dist = math.sqrt(math.random()) * 18
					local ground = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
					makeRangerArrow(ground + Vector3.new(0, 38, 0), Vector3.new(0, -1, 0), 38, i % 4 == 0 and POISON_PURPLE or NATURE_GREEN, 0.18, 0.18)
				end)
			end
		end)
		task.delay(5.2, function()
			if marker and marker.Parent then
				TweenService:Create(marker, TweenInfo.new(0.35), { Transparency = 1 }):Play()
				Debris:AddItem(marker, 0.4)
			end
		end)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Animation Loading
-- ─────────────────────────────────────────────────────────────────────────────
local function loadSkillAnimations(char: Model)
	local humanoid = char:WaitForChild("Humanoid", 5) :: Humanoid?
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" then return end
	local skills = SkillData.GetSkills(classId) or {}

	currentLoadedCharacter = char
	table.clear(loadedSkillTracks)
	table.clear(loadedSkillSlashTracks)

	for skillIndex, config in pairs(skills) do
		if config.animationId and config.animationId ~= "" then
			local anim = Instance.new("Animation")
			anim.Name = `SkillAnim_{skillIndex}`
			anim.AnimationId = config.animationId
			anim.Parent = animator
			local track = animator:LoadAnimation(anim)
			track.Priority = (skillIndex == 4) and Enum.AnimationPriority.Action3 or Enum.AnimationPriority.Action4
			track.Looped = false
			loadedSkillTracks[skillIndex] = track
		end
		if (config :: any).slashAnimationId and (config :: any).slashAnimationId ~= "" then
			local slashAnim = Instance.new("Animation")
			slashAnim.Name = `SkillAnimSlash_{skillIndex}`
			slashAnim.AnimationId = (config :: any).slashAnimationId
			slashAnim.Parent = animator
			local slashTrack = animator:LoadAnimation(slashAnim)
			slashTrack.Priority = Enum.AnimationPriority.Action4
			slashTrack.Looped = false
			loadedSkillSlashTracks[skillIndex] = slashTrack
		end
	end
end

local function getSkillTrack(char: Model, skillIndex: number): AnimationTrack?
	if currentLoadedCharacter ~= char or not loadedSkillTracks[skillIndex] then
		loadSkillAnimations(char)
	end
	return loadedSkillTracks[skillIndex]
end

local function getSkillSlashTrack(char: Model, skillIndex: number): AnimationTrack?
	if currentLoadedCharacter ~= char or not loadedSkillSlashTracks[skillIndex] then
		loadSkillAnimations(char)
	end
	return loadedSkillSlashTracks[skillIndex]
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

	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" then return end
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
	local cursorPosition = getCursorWorldPosition(rootPart)
	local aimDir = getAimDirection(rootPart)
	local rangerTargetPosition = classId == "ranger" and (skillIndex == 3 or skillIndex == 4)
		and clampRangerCursorTarget(rootPart.Position, cursorPosition, config.range or 42, aimDir) or nil

	-- Pivot character towards aim direction smoothly
	local targetCF = CFrame.lookAt(rootPart.Position, rootPart.Position + aimDir)
	rootPart.CFrame = targetCF

	-- Set casting attribute & play skill animation
	char:SetAttribute("IsSkillCasting", true)

	if classId == "ranger" then
		char:SetAttribute("AllowSkillMovement", true)
		local track = getSkillTrack(char, skillIndex)
		if track then
			track:Play(0.08)
		end
		local castLock = skillIndex == 4 and 1.1 or 0.35
		task.delay(castLock, function()
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end)
		playRangerSkillVFX(char, skillIndex, rootPart.Position, aimDir, rangerTargetPosition)
	elseif classId == "heavy_knight" and skillIndex == 1 then
		-- Spin attack allows moving for the 5s duration, but blocks other spells/attacks
		char:SetAttribute("AllowSkillMovement", true)
		char:SetAttribute("IsSkill1Active", true)
		char:SetAttribute("IsSpinAttackActive", true)

		local track = getSkillTrack(char, 1)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
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
	elseif classId == "heavy_knight" and skillIndex == 2 then
		-- Skill 2: Missile Barrage Buff (instant cast buff, enables missile launch on every attack)
		char:SetAttribute("AllowSkillMovement", true)
		char:SetAttribute("IsSkillCasting", false)
		playMissileBuffVFX(char)
	elseif classId == "heavy_knight" and skillIndex == 3 then
		char:SetAttribute("AllowSkillMovement", true)
		local track = getSkillTrack(char, 3)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.08)
		end
		task.delay(0.35, function()
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end)
		playPhoenixDashVFX(char, rootPart.Position, aimDir)
	elseif classId == "heavy_knight" and skillIndex == 4 then
		char:SetAttribute("AllowSkillMovement", false)
		local track = getSkillTrack(char, 4)
		if track then
			track.Priority = Enum.AnimationPriority.Action3
			track:Play(0.08)
			task.delay(3.3, function()
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end)
		else
			task.delay(3.3, function()
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
			targetPosition = rangerTargetPosition,
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
			if typeof(hud.SetSkillCooldown) == "function" then
				hud.SetSkillCooldown(slot, remaining, cd.duration)
			end

			if remaining <= 0 then
				activeCooldowns[slot] = nil
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Damage Output
-- ─────────────────────────────────────────────────────────────────────────────
local function showDamageNumber(payload: any)
	if typeof(payload) ~= "table" or typeof(payload.position) ~= "Vector3" or typeof(payload.amount) ~= "number" then
		return
	end

	local anchor = Instance.new("Part")
	anchor.Name = "LocalDamageNumberAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CFrame = CFrame.new(payload.position)
	anchor.Parent = Workspace

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "DamageNumber"
	billboard.Adornee = anchor
	billboard.Size = UDim2.fromOffset(124, 56)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.StudsOffsetWorldSpace = Vector3.new(math.random(-7, 7) / 10, 0, 0)
	billboard.Parent = anchor

	local number = Instance.new("TextLabel")
	number.Size = UDim2.new(1, 0, 0, 34)
	number.BackgroundTransparency = 1
	number.Font = Enum.Font.Antique
	number.Text = `-{math.floor(payload.amount)}`
	number.TextSize = 28
	number.TextColor3 = payload.source == "INFERNAL WRATH" and Color3.fromRGB(255, 108, 52) or Color3.fromRGB(255, 218, 104)
	number.TextStrokeColor3 = Color3.fromRGB(38, 10, 5)
	number.TextStrokeTransparency = 0
	number.Parent = billboard

	local source = Instance.new("TextLabel")
	source.Size = UDim2.new(1, 0, 0, 16)
	source.Position = UDim2.fromOffset(0, 30)
	source.BackgroundTransparency = 1
	source.Font = Enum.Font.GothamBold
	source.Text = typeof(payload.source) == "string" and payload.source or "HIT"
	source.TextSize = 9
	source.TextColor3 = Color3.fromRGB(255, 239, 191)
	source.TextStrokeColor3 = Color3.fromRGB(38, 10, 5)
	source.TextStrokeTransparency = 0.15
	source.Parent = billboard

	local fadeInfo = TweenInfo.new(0.72, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(billboard, fadeInfo, { StudsOffsetWorldSpace = billboard.StudsOffsetWorldSpace + Vector3.new(0, 3.2, 0) }):Play()
	TweenService:Create(number, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	TweenService:Create(source, fadeInfo, { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

local function cloneKeybinds(keybinds: { [string]: string }?)
	currentKeybinds = {}
	for action, key in pairs(SettingsConfig.DefaultSettings.keybinds) do
		currentKeybinds[action] = key
	end
	if keybinds then
		for action, key in pairs(keybinds) do
			currentKeybinds[action] = key
		end
	end
end

local function inputMatchesAction(input: InputObject, action: string): boolean
	local keyName = currentKeybinds[action] or SettingsConfig.DefaultSettings.keybinds[action]
	if not keyName or keyName == "" or keyName == "None" then
		return false
	end

	if input.UserInputType == Enum.UserInputType.Keyboard then
		return input.KeyCode.Name == keyName
	end

	return input.UserInputType.Name == keyName
end

function SkillController.SetKeybinds(keybinds: { [string]: string }?)
	cloneKeybinds(keybinds)
end

local lastBasicAttack = 0

local function performBasicAttack()
	if player:GetAttribute("InLobby") == true then return end
	local char = player.Character
	if not char then return end

	local now = os.clock()
	local attackSpeed = player:GetAttribute("Stat_basicAttackSpeed") or 1
	if now - lastBasicAttack < 0.38 / math.max(attackSpeed, 0.1) then return end
	lastBasicAttack = now

	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local aimDirection: Vector3? = nil
	if rootPart then
		local aimDir = getAimDirection(rootPart)
		aimDirection = aimDir
		rootPart.CFrame = CFrame.lookAt(rootPart.Position, rootPart.Position + aimDir)
		if player:GetAttribute("SelectedClass") == "ranger" then
			playRangerShootAnimation(char)
		end
	end

	-- Fire server Remote for basic attack damage
	local performAttackRemote = Network.GetRemoteEvent(Network.Remotes.PerformAttack)
	performAttackRemote:FireServer({ direction = aimDirection })

	-- If Missile Barrage buff is active, launch missile
	if char:GetAttribute("IsMissileBuffActive") == true then
		SkillController.LaunchMissile(char)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Initialization & Event Connections
-- ─────────────────────────────────────────────────────────────────────────────
function SkillController.Init()
	local damageRemote = Network.GetRemoteEvent(Network.Remotes.DamageDealt)
	damageRemote.OnClientEvent:Connect(showDamageNumber)
	cloneKeybinds(nil)

	-- Keybind listeners use current settings so the controls match the settings UI and HUD.
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end

		if inputMatchesAction(input, "PrimaryAttack") then
			performBasicAttack()
		elseif inputMatchesAction(input, "Skill1") then
			SkillController.UseSkill(1)
		elseif inputMatchesAction(input, "Skill2") then
			SkillController.UseSkill(2)
		elseif inputMatchesAction(input, "Skill3") then
			SkillController.UseSkill(3)
		elseif inputMatchesAction(input, "Ultimate") then
			SkillController.UseSkill(4)
		end
	end)

	-- Client-side Blue Star Death VFX listener
	local deathRemote = Network.GetRemoteEvent(Network.Remotes.MobDeathVFX)
	deathRemote.OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.position) == "Vector3" then
			local pos = payload.position
			local playerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not playerRoot or (playerRoot.Position - pos).Magnitude > 110 then return end
			local vfxHolder = Instance.new("Part")
			vfxHolder.Name = "ClientBlueStarVFX"
			vfxHolder.Size = Vector3.new(0.5, 0.5, 0.5)
			vfxHolder.Transparency = 1
			vfxHolder.CanCollide = false
			vfxHolder.Anchored = true
			vfxHolder.CFrame = CFrame.new(pos)
			vfxHolder.Parent = Workspace.Terrain

			local att = Instance.new("Attachment")
			att.Parent = vfxHolder

			local starPE = Instance.new("ParticleEmitter")
			starPE.Name = "BlueStarBurstClient"
			starPE.Texture = "rbxassetid://1084991219"
			starPE.Color = ColorSequence.new({
				ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 255)),
				ColorSequenceKeypoint.new(0.25, Color3.fromRGB(0, 210, 255)),
				ColorSequenceKeypoint.new(0.7, Color3.fromRGB(0, 140, 255)),
				ColorSequenceKeypoint.new(1, Color3.fromRGB(20, 50, 180)),
			})
			starPE.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0),
				NumberSequenceKeypoint.new(0.7, 0.1),
				NumberSequenceKeypoint.new(1, 1),
			})
			starPE.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(0.35, 2.5),
				NumberSequenceKeypoint.new(1, 0.1),
			})
			starPE.LightEmission = 1
			starPE.LightInfluence = 0
			starPE.Lifetime = NumberRange.new(0.5, 1.2)
			starPE.Speed = NumberRange.new(16, 35)
			starPE.SpreadAngle = Vector2.new(180, 180)
			starPE.Parent = att

			starPE:Emit(50)

			local light = Instance.new("PointLight")
			light.Color = Color3.fromRGB(0, 210, 255)
			light.Brightness = 14
			light.Range = 24
			light.Parent = vfxHolder

			TweenService:Create(light, TweenInfo.new(0.6), { Brightness = 0, Range = 0 }):Play()
			Debris:AddItem(vfxHolder, 1.5)
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

		local classId = castingPlayer:GetAttribute("SelectedClass")
		if classId == "ranger" then
			playRangerSkillVFX(char, skillIndex, origin, direction, payload.targetPosition, payload.projectileCount)
		elseif classId == "heavy_knight" and skillIndex == 1 then
			playSpinAttackVFX(char, origin, direction)
		elseif classId == "heavy_knight" and skillIndex == 2 then
			playMissileBuffVFX(char)
		elseif classId == "heavy_knight" and skillIndex == 3 then
			playPhoenixDashVFX(char, origin, direction)
		elseif classId == "heavy_knight" and skillIndex == 4 then
			playInfernalWrathVFX(char, origin, direction)
		end
	end)

	-- Load animations on character spawn & class selection
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

	player:GetAttributeChangedSignal("SelectedClass"):Connect(function()
		local char = player.Character
		if char then
			loadSkillAnimations(char)
		end
	end)

	local classConfirmedRemote = Network.GetRemoteEvent(Network.Remotes.ClassConfirmed)
	classConfirmedRemote.OnClientEvent:Connect(function()
		local char = player.Character
		if char then
			task.spawn(function()
				loadSkillAnimations(char)
			end)
		end
	end)

	-- Heartbeat cooldown loop
	RunService.Heartbeat:Connect(updateCooldowns)

	print("[SkillController] Client SkillController initialized.")
end

return SkillController
