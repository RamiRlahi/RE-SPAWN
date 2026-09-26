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
local IsometricCamera = require(script.Parent:WaitForChild("IsometricCamera"))
local DivineBeamChannel = require(script.Parent:WaitForChild("DivineBeamChannel"))
local ClericVFX = require(script.Parent:WaitForChild("ClericVFX"))
local AllyHover = require(script.Parent:WaitForChild("AllyHover"))
AllyHover.Init()
local DivineAscentCutscene = require(script.Parent:WaitForChild("DivineAscentCutscene"))

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

-- Token to cancel an in-flight Divine Ascent cinematic camera
local divineCamToken = 0

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

local function triggerFOVPunch(fovDelta: number, duration: number)
	task.spawn(function()
		local startFOV = camera.FieldOfView
		local tweenIn = TweenService:Create(camera, TweenInfo.new(duration * 0.22, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			FieldOfView = math.max(30, startFOV - fovDelta),
		})
		tweenIn:Play()
		tweenIn.Completed:Wait()
		TweenService:Create(camera, TweenInfo.new(duration * 0.78, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			FieldOfView = startFOV,
		}):Play()
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
-- Skill 2: Fire Slam VFX (High Vertical Leap + Meteor Plunge + Multilayer Shockwave & Debris)
-- ─────────────────────────────────────────────────────────────────────────────
-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 2: Fire Slam VFX (High Vertical Leap + Meteor Plunge + Multilayer Shockwave & Debris)
-- ─────────────────────────────────────────────────────────────────────────────
local function playFireSlamVFX(char: Model, origin: Vector3, targetPos: Vector3, sizeMultiplier: number?)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = char:FindFirstChildOfClass("Humanoid")
	if not rootPart or not humanoid then return end

	local isLocalCaster = (char == player.Character)
	local charPlayer = Players:GetPlayerFromCharacter(char) or (isLocalCaster and player)
	local sizeScale = math.max(0.4, (sizeMultiplier or (charPlayer and charPlayer:GetAttribute("Stat_size")) or 1.0))

	local flatDiff = Vector3.new(targetPos.X - origin.X, 0, targetPos.Z - origin.Z)
	local flatDir = flatDiff.Magnitude > 0.1 and flatDiff.Unit or rootPart.CFrame.LookVector
	local leapDist = math.min(flatDiff.Magnitude, 42)
	local landingPos = origin + flatDir * leapDist

	-- Ground raycast for landing Y
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList: { Instance } = { char }
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and (desc:FindFirstChildOfClass("Humanoid") or desc:FindFirstAncestorOfClass("Accessory")) then
			table.insert(ignoreList, desc)
		end
	end
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.IgnoreWater = true

	local groundRay = Workspace:Raycast(landingPos + Vector3.new(0, 25, 0), Vector3.new(0, -60, 0), rayParams)
	local landingY = origin.Y
	if groundRay then
		local hipHeight = humanoid.HipHeight or 2.0
		landingY = groundRay.Position.Y + (rootPart.Size.Y * 0.5) + hipHeight
	end
	landingPos = Vector3.new(landingPos.X, landingY, landingPos.Z)

	-- ─── Phase 1: High Vertical Ascent & Meteor Plunge Kinematics ────────────────
	local flameAtt = Instance.new("Attachment")
	flameAtt.Name = "FireSlamFlameAura"
	flameAtt.Position = Vector3.new(0, 0, 0)
	flameAtt.Parent = rootPart

	-- Heavy upward/downward flame shroud
	local leapFlames = makeFlameEmitter(flameAtt, 160, 7.0 * sizeScale, 28 * sizeScale)
	leapFlames.SpreadAngle = Vector2.new(180, 180)
	leapFlames.Lifetime = NumberRange.new(0.3, 0.65)

	local leapEmbers = makeEmberEmitter(flameAtt, 110)
	leapEmbers.SpreadAngle = Vector2.new(180, 180)
	leapEmbers.Lifetime = NumberRange.new(0.5, 1.2)
	leapEmbers.Speed = NumberRange.new(12 * sizeScale, 32 * sizeScale)

	-- Downward rocket booster under feet
	local rocketBooster = Instance.new("ParticleEmitter")
	rocketBooster.Name = "RocketBooster"
	rocketBooster.Texture = "rbxassetid://258129523"
	rocketBooster.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 220)),
		ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 160, 20)),
		ColorSequenceKeypoint.new(0.8, Color3.fromRGB(255, 50, 0)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 10, 0)),
	})
	rocketBooster.Transparency = FLAME_TRANSPARENCY_SEQUENCE
	rocketBooster.LightEmission = 1
	rocketBooster.LightInfluence = 0
	rocketBooster.Rate = 120
	rocketBooster.Lifetime = NumberRange.new(0.2, 0.45)
	rocketBooster.Speed = NumberRange.new(25 * math.sqrt(sizeScale), 45 * math.sqrt(sizeScale))
	rocketBooster.SpreadAngle = Vector2.new(15, 15)
	rocketBooster.EmissionDirection = Enum.NormalId.Bottom
	rocketBooster.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 2.5 * sizeScale),
		NumberSequenceKeypoint.new(0.5, 4.0 * sizeScale),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	rocketBooster.Parent = flameAtt

	-- Lock the camera to the ground Y during the leap so it follows X/Z only
	if isLocalCaster then
		pcall(function() IsometricCamera.SetFocusYLock(origin.Y) end)
	end

	-- Vertical leap metrics
	local jumpApexHeight = 38.0
	local totalDuration = 0.72
	local ascentDuration = 0.34
	local hoverDuration = 0.08
	local plungeDuration = totalDuration - ascentDuration - hoverDuration -- 0.30s

	task.spawn(function()
		local startTime = os.clock()
		while os.clock() - startTime < totalDuration do
			local elapsed = os.clock() - startTime
			local currentPos: Vector3

			if elapsed < ascentDuration then
				-- 1. Rocketing Vertical Ascent: Rapidly climb Y, translate smoothly towards landing XZ
				local aAlpha = elapsed / ascentDuration
				local yProgress = math.sin(aAlpha * (math.pi * 0.5))
				local xzProgress = aAlpha * aAlpha
				local currentXZ = origin + flatDir * (leapDist * xzProgress)
				local currentY = origin.Y + (jumpApexHeight * yProgress) + (landingY - origin.Y) * (xzProgress * 0.5)
				currentPos = Vector3.new(currentXZ.X, currentY, currentXZ.Z)
			elseif elapsed < ascentDuration + hoverDuration then
				-- 2. Apex Hover: Suspended high in the sky directly above landing position
				local currentY = origin.Y + jumpApexHeight + (landingY - origin.Y) * 0.5
				currentPos = Vector3.new(landingPos.X, currentY, landingPos.Z)
			else
				-- 3. Vertical Meteor Plunge: Steep quartic acceleration straight down into ground
				local pElapsed = elapsed - (ascentDuration + hoverDuration)
				local pAlpha = math.clamp(pElapsed / plungeDuration, 0, 1)
				local fallProgress = pAlpha * pAlpha * pAlpha * pAlpha
				local startPlungeY = origin.Y + jumpApexHeight + (landingY - origin.Y) * 0.5
				local currentY = startPlungeY + (landingY - startPlungeY) * fallProgress
				currentPos = Vector3.new(landingPos.X, currentY, landingPos.Z)
			end

			rootPart.CFrame = CFrame.lookAt(currentPos, currentPos + flatDir)
			rootPart.AssemblyLinearVelocity = Vector3.zero

			RunService.RenderStepped:Wait()
		end

		-- ─── Snap to landing position ──────────────────────────────────────────
		rootPart.CFrame = CFrame.lookAt(landingPos, landingPos + flatDir)
		rootPart.AssemblyLinearVelocity = Vector3.zero

		-- Release the camera Y-lock now that the character is back on the ground
		if isLocalCaster then
			pcall(function() IsometricCamera.SetFocusYLock(nil) end)
		end

		-- Cleanup airborne emitters
		leapFlames.Enabled = false
		leapEmbers.Enabled = false
		rocketBooster.Enabled = false
		Debris:AddItem(flameAtt, 0.8)

		-- ─── Phase 2: Cataclysmic Impact & Multilayer Shockwave System ────────
		local impactPos = landingPos - Vector3.new(0, (rootPart.Size.Y * 0.5) + (humanoid.HipHeight or 2.0), 0)

		-- Screen shake & visceral FOV punch on impact
		if isLocalCaster then
			triggerCameraShake(1.3 * math.clamp(sizeScale, 0.8, 1.8), 0.48)
			triggerFOVPunch(7, 0.38)
		end

		-- ─── 2a. Expanding 3D Distortion Hemisphere Dome ───────────────────────
		local shockDome = Instance.new("Part")
		shockDome.Name = "FireSlamShockDome"
		shockDome.Shape = Enum.PartType.Ball
		shockDome.Size = Vector3.new(2, 2, 2)
		shockDome.CFrame = CFrame.new(impactPos + Vector3.new(0, 1, 0))
		shockDome.Anchored = true
		shockDome.CanCollide = false
		shockDome.CanTouch = false
		shockDome.CanQuery = false
		shockDome.Material = Enum.Material.Neon
		shockDome.Color = Color3.fromRGB(255, 235, 180)
		shockDome.Transparency = 0.2
		shockDome.Parent = Workspace.Terrain

		TweenService:Create(shockDome, TweenInfo.new(0.34, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(46 * sizeScale, 32 * sizeScale, 46 * sizeScale),
			Transparency = 1,
			Color = Color3.fromRGB(255, 60, 0),
		}):Play()
		Debris:AddItem(shockDome, 0.4)

		-- ─── 2b. Primary Superheated White-Hot Floor Blast Disc ───────────────
		local blastDisc = Instance.new("Part")
		blastDisc.Name = "FireSlamBlastDisc"
		blastDisc.Shape = Enum.PartType.Cylinder
		blastDisc.Size = Vector3.new(0.25, 2, 2)
		blastDisc.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, 0, math.rad(90))
		blastDisc.Anchored = true
		blastDisc.CanCollide = false
		blastDisc.CanTouch = false
		blastDisc.CanQuery = false
		blastDisc.Material = Enum.Material.Neon
		blastDisc.Color = Color3.fromRGB(255, 255, 230)
		blastDisc.Transparency = 0.05
		blastDisc.Parent = Workspace.Terrain

		TweenService:Create(blastDisc, TweenInfo.new(0.24, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.25, 32 * sizeScale, 32 * sizeScale),
			Transparency = 1,
			Color = Color3.fromRGB(255, 140, 10),
		}):Play()
		Debris:AddItem(blastDisc, 0.3)

		-- ─── 2c. Outer Razor Flame Shockwave Ring (Matching Reference Diagram) ─
		local outerRing = Instance.new("Part")
		outerRing.Name = "FireSlamOuterRing"
		outerRing.Shape = Enum.PartType.Cylinder
		outerRing.Size = Vector3.new(0.18, 3, 3)
		outerRing.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.06, 0)) * CFrame.Angles(0, 0, math.rad(90))
		outerRing.Anchored = true
		outerRing.CanCollide = false
		outerRing.CanTouch = false
		outerRing.CanQuery = false
		outerRing.Material = Enum.Material.Neon
		outerRing.Color = Color3.fromRGB(255, 130, 15)
		outerRing.Transparency = 0.1
		outerRing.Parent = Workspace.Terrain

		TweenService:Create(outerRing, TweenInfo.new(0.52, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.18, 42 * sizeScale, 42 * sizeScale),
			Transparency = 1,
			Color = Color3.fromRGB(180, 20, 0),
		}):Play()
		Debris:AddItem(outerRing, 0.6)

		-- ─── 2d. Low-Lying Floor Smoke & Ash Shockwave (Hugging the ground) ────
		local groundBurstAtt = Instance.new("Attachment")
		groundBurstAtt.Name = "FireSlamGroundBurst"
		groundBurstAtt.WorldPosition = impactPos
		groundBurstAtt.Parent = Workspace.Terrain

		local floorAshPE = Instance.new("ParticleEmitter")
		floorAshPE.Name = "FloorAshWave"
		floorAshPE.Texture = "rbxassetid://258128463"
		floorAshPE.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 140, 30)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(120, 60, 40)),
			ColorSequenceKeypoint.new(0.7, Color3.fromRGB(40, 30, 28)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(15, 12, 12)),
		})
		floorAshPE.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.6, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		floorAshPE.LightEmission = 0.6
		floorAshPE.LightInfluence = 0
		floorAshPE.Rate = 0
		floorAshPE.Lifetime = NumberRange.new(0.55, 0.95)
		floorAshPE.Speed = NumberRange.new(35 * sizeScale, 68 * sizeScale)
		floorAshPE.SpreadAngle = Vector2.new(180, 0)
		floorAshPE.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 2.5 * sizeScale),
			NumberSequenceKeypoint.new(0.4, 7.0 * sizeScale),
			NumberSequenceKeypoint.new(1, 9.5 * sizeScale),
		})
		floorAshPE.Parent = groundBurstAtt
		floorAshPE:Emit(math.floor(80 * math.clamp(sizeScale, 0.8, 1.6)))

		-- ─── 2e. Central Vertical Fire Pillar / Spire (Shooting straight up) ───
		local pillarHeight = 44 * math.sqrt(sizeScale)
		local centralPillar = Instance.new("Part")
		centralPillar.Name = "FireSlamCentralSpire"
		centralPillar.Shape = Enum.PartType.Cylinder
		centralPillar.Size = Vector3.new(pillarHeight, 3.6 * sizeScale, 3.6 * sizeScale)
		centralPillar.CFrame = CFrame.new(impactPos + Vector3.new(0, pillarHeight * 0.5, 0)) * CFrame.Angles(0, 0, math.rad(90))
		centralPillar.Anchored = true
		centralPillar.CanCollide = false
		centralPillar.CanTouch = false
		centralPillar.CanQuery = false
		centralPillar.Material = Enum.Material.Neon
		centralPillar.Color = Color3.fromRGB(255, 245, 190)
		centralPillar.Transparency = 0.05
		centralPillar.Parent = Workspace.Terrain

		TweenService:Create(centralPillar, TweenInfo.new(0.50, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(pillarHeight + 6, 0.1, 0.1),
			Transparency = 1,
			Color = Color3.fromRGB(255, 80, 0),
		}):Play()
		Debris:AddItem(centralPillar, 0.58)

		-- High-velocity roaring fire column
		local columnFlames = Instance.new("ParticleEmitter")
		columnFlames.Name = "FireSlamColumn"
		columnFlames.Texture = "rbxassetid://258129523"
		columnFlames.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 255, 230)),
			ColorSequenceKeypoint.new(0.25, Color3.fromRGB(255, 180, 30)),
			ColorSequenceKeypoint.new(0.65, Color3.fromRGB(255, 60, 5)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 15, 0)),
		})
		columnFlames.Transparency = FLAME_TRANSPARENCY_SEQUENCE
		columnFlames.LightEmission = 1
		columnFlames.LightInfluence = 0
		columnFlames.Rate = 0
		columnFlames.Lifetime = NumberRange.new(0.65, 1.15)
		columnFlames.Speed = NumberRange.new(55 * math.sqrt(sizeScale), 95 * math.sqrt(sizeScale))
		columnFlames.SpreadAngle = Vector2.new(8, 8)
		columnFlames.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 6.0 * sizeScale),
			NumberSequenceKeypoint.new(0.3, 10.0 * sizeScale),
			NumberSequenceKeypoint.new(1, 1.2 * sizeScale),
		})
		columnFlames.Parent = groundBurstAtt
		columnFlames:Emit(math.floor(60 * math.clamp(sizeScale, 0.8, 1.5)))

		-- Radial bursting flames
		local radialFlames = makeFlameEmitter(groundBurstAtt, 0, 9.0 * sizeScale, 50 * sizeScale)
		radialFlames.SpreadAngle = Vector2.new(180, 75)
		radialFlames.Lifetime = NumberRange.new(0.45, 0.95)
		radialFlames:Emit(math.floor(80 * math.clamp(sizeScale, 0.8, 1.5)))

		-- Shower of 100+ sharp volcanic sparks
		local burstEmbers = makeEmberEmitter(groundBurstAtt, 0)
		burstEmbers.SpreadAngle = Vector2.new(180, 180)
		burstEmbers.Speed = NumberRange.new(25 * sizeScale, 75 * sizeScale)
		burstEmbers.Lifetime = NumberRange.new(0.7, 1.7)
		burstEmbers.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.8 * sizeScale),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		burstEmbers:Emit(math.floor(110 * math.clamp(sizeScale, 0.8, 1.6)))

		Debris:AddItem(groundBurstAtt, 2.5)

		-- ─── 2f. 3D Tectonic Crust Slabs (Shattered Raised Crater Edge) ────────
		local slabCount = 10
		local craterRadius = 7.5 * sizeScale
		for s = 1, slabCount do
			local sAngle = (s / slabCount) * (math.pi * 2) + (math.random() - 0.5) * 0.25
			local sDir = Vector3.new(math.cos(sAngle), 0, math.sin(sAngle))
			local sPos = impactPos + sDir * (craterRadius + (math.random() * 2.5 * sizeScale))

			local slabRay = Workspace:Raycast(sPos + Vector3.new(0, 10, 0), Vector3.new(0, -25, 0), rayParams)
			local sGroundY = slabRay and slabRay.Position.Y or impactPos.Y

			local slabWidth = (2.4 + math.random() * 1.6) * sizeScale
			local slabLength = (3.2 + math.random() * 2.0) * sizeScale
			local slabThickness = (0.8 + math.random() * 0.5) * sizeScale

			-- Outer dark rock slab
			local slab = Instance.new("Part")
			slab.Name = "CraterSlab_" .. s
			slab.Size = Vector3.new(slabWidth, slabThickness, slabLength)
			slab.Material = Enum.Material.Basalt
			slab.Color = Color3.fromRGB(30, 24, 20)
			slab.Anchored = true
			slab.CanCollide = false
			slab.CanTouch = false
			slab.CanQuery = false

			-- Tilted upward and outward
			local tiltAngle = math.rad(28 + math.random() * 20)
			local slabCF = CFrame.lookAt(sPos, sPos + sDir) * CFrame.Angles(tiltAngle, 0, (math.random() - 0.5) * 0.4)
			slab.CFrame = CFrame.new(sPos.X, sGroundY - slabThickness, sPos.Z) * slabCF.Rotation
			slab.Parent = Workspace.Terrain

			-- Inner molten magma seam
			local magmaSeam = Instance.new("Part")
			magmaSeam.Name = "MagmaSeam_" .. s
			magmaSeam.Size = Vector3.new(slabWidth * 0.8, 0.15, slabLength * 0.8)
			magmaSeam.Material = Enum.Material.Neon
			magmaSeam.Color = Color3.fromRGB(255, 95, 10)
			magmaSeam.Transparency = 0.15
			magmaSeam.Anchored = true
			magmaSeam.CanCollide = false
			magmaSeam.CanTouch = false
			magmaSeam.CanQuery = false
			magmaSeam.CFrame = slab.CFrame * CFrame.new(0, -slabThickness * 0.4, 0)
			magmaSeam.Parent = Workspace.Terrain

			-- Burst slabs upward violently on impact
			local targetSlabCFrame = CFrame.new(sPos.X, sGroundY + slabThickness * 0.4, sPos.Z) * slabCF.Rotation
			TweenService:Create(slab, TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				CFrame = targetSlabCFrame,
			}):Play()
			TweenService:Create(magmaSeam, TweenInfo.new(0.12, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
				CFrame = targetSlabCFrame * CFrame.new(0, -slabThickness * 0.4, 0),
			}):Play()

			-- Slabs settle, cool down and sink back into terrain
			task.delay(1.6, function()
				TweenService:Create(magmaSeam, TweenInfo.new(1.0), { Transparency = 1, Color = Color3.fromRGB(40, 10, 5) }):Play()
				TweenService:Create(slab, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(sPos.X, sGroundY - slabThickness * 2, sPos.Z) * slabCF.Rotation,
					Transparency = 1,
				}):Play()
				Debris:AddItem(slab, 1.6)
				Debris:AddItem(magmaSeam, 1.6)
			end)
		end

		-- ─── 2g. Volcanic Rock Debris Fountain (Physical Arc Simulation) ──────
		local debrisCount = 16
		for i = 1, debrisCount do
			local dAngle = (i / debrisCount) * (math.pi * 2) + (math.random() - 0.5) * 0.4
			local dDist = (7.0 + math.random() * 9.0) * sizeScale
			local dEndPos = impactPos + Vector3.new(math.cos(dAngle) * dDist, 0, math.sin(dAngle) * dDist)

			local dRay = Workspace:Raycast(dEndPos + Vector3.new(0, 12, 0), Vector3.new(0, -30, 0), rayParams)
			local dGroundY = dRay and dRay.Position.Y or impactPos.Y
			dEndPos = Vector3.new(dEndPos.X, dGroundY + 0.4, dEndPos.Z)

			local dSize = Vector3.new(
				1.2 + math.random() * 1.5,
				1.0 + math.random() * 1.4,
				1.2 + math.random() * 1.5
			) * math.clamp(sizeScale, 0.75, 2.2)

			local dRock = Instance.new("Part")
			dRock.Name = "FireSlamDebrisRock_" .. i
			dRock.Size = dSize
			dRock.Position = impactPos + Vector3.new(0, 0.5, 0)
			dRock.CFrame = CFrame.new(impactPos) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
			dRock.Anchored = true
			dRock.CanCollide = false
			dRock.CanTouch = false
			dRock.CanQuery = false
			dRock.Material = Enum.Material.Basalt
			dRock.Color = Color3.fromRGB(30, 22, 18)
			dRock.Parent = Workspace.Terrain

			-- Fire trail attached to rock
			local dRockAtt = Instance.new("Attachment")
			dRockAtt.Parent = dRock

			local dFlame = makeFlameEmitter(dRockAtt, 25, 2.4 * sizeScale, 12 * sizeScale)
			dFlame.SpreadAngle = Vector2.new(180, 180)
			dFlame.Lifetime = NumberRange.new(0.25, 0.6)

			local dEmbers = makeEmberEmitter(dRockAtt, 18)
			dEmbers.Speed = NumberRange.new(4 * sizeScale, 12 * sizeScale)
			dEmbers.Lifetime = NumberRange.new(0.35, 0.8)

			-- Launch rock along explosive arc
			task.spawn(function()
				local apexY = impactPos.Y + (8.0 + math.random() * 10.0) * math.sqrt(sizeScale)
				local flyDuration = 0.36 + math.random() * 0.20
				local dStartTime = os.clock()
				local rotSpeedX = (math.random() - 0.5) * 16
				local rotSpeedY = (math.random() - 0.5) * 16
				local rotSpeedZ = (math.random() - 0.5) * 16

				while os.clock() - dStartTime < flyDuration do
					local rAlpha = math.clamp((os.clock() - dStartTime) / flyDuration, 0, 1)
					local rY = impactPos.Y + (apexY - impactPos.Y) * (4 * rAlpha * (1 - rAlpha)) + (dGroundY - impactPos.Y) * (rAlpha * rAlpha)
					local rPos = impactPos:Lerp(dEndPos, rAlpha)
					rPos = Vector3.new(rPos.X, rY, rPos.Z)

					dRock.CFrame = CFrame.new(rPos) * CFrame.Angles(rotSpeedX * rAlpha, rotSpeedY * rAlpha, rotSpeedZ * rAlpha)
					RunService.RenderStepped:Wait()
				end

				-- Settle into ground rubble
				dRock.CFrame = CFrame.new(dEndPos) * CFrame.Angles(math.random() * 6, math.random() * 6, 0)

				-- Cool down and dissolve
				task.delay(1.3, function()
					dFlame.Enabled = false
					dEmbers.Enabled = false
					TweenService:Create(dRock, TweenInfo.new(1.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						Position = dEndPos - Vector3.new(0, dSize.Y + 0.5, 0),
						Transparency = 1,
					}):Play()
					Debris:AddItem(dRock, 1.4)
				end)
			end)
		end

		-- ─── 2h. Crown of Vertical Flame Needle Spires ─────────────────────────
		local spikeCount = 9
		for i = 1, spikeCount do
			local angle = (i / spikeCount) * (math.pi * 2) + (math.random() - 0.5) * 0.35
			local spikeDist = (4.5 + math.random() * 4.5) * sizeScale
			local spikePos = impactPos + Vector3.new(math.cos(angle) * spikeDist, 0, math.sin(angle) * spikeDist)

			task.delay(i * 0.015, function()
				local spike = Instance.new("Part")
				spike.Name = "FireSpike_" .. i
				spike.Size = Vector3.new(1.6 * sizeScale, 0.6, 1.6 * sizeScale)
				spike.CFrame = CFrame.new(spikePos)
				spike.Anchored = true
				spike.CanCollide = false
				spike.CanTouch = false
				spike.CanQuery = false
				spike.Material = Enum.Material.Neon
				spike.Color = Color3.fromRGB(255, 120, 15)
				spike.Transparency = 0.15
				spike.Parent = Workspace.Terrain

				local targetHeight = (10 + math.random() * 12) * math.sqrt(sizeScale)
				TweenService:Create(spike, TweenInfo.new(0.14, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Size = Vector3.new(1.6 * sizeScale, targetHeight, 1.6 * sizeScale),
					CFrame = CFrame.new(spikePos + Vector3.new(0, targetHeight * 0.5, 0)),
				}):Play()

				local spikeAtt = Instance.new("Attachment")
				spikeAtt.Parent = spike
				local spikePE = makeFlameEmitter(spikeAtt, 45, 4.5 * sizeScale, 22 * sizeScale)
				spikePE.SpreadAngle = Vector2.new(20, 20)

				task.delay(0.35, function()
					spikePE.Enabled = false
					TweenService:Create(spike, TweenInfo.new(0.40, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
						Size = Vector3.new(0.2, 0.2, 0.2),
						Transparency = 1,
					}):Play()
					Debris:AddItem(spike, 0.50)
				end)
			end)
		end

		-- ─── 2i. Molten Ground Crater Disc & Radiating Lava Fractures ──────────
		local crater = Instance.new("Part")
		crater.Name = "FireSlamCrater"
		crater.Shape = Enum.PartType.Cylinder
		crater.Size = Vector3.new(0.08, 17 * sizeScale, 17 * sizeScale)
		crater.CFrame = CFrame.new(impactPos - Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90))
		crater.Anchored = true
		crater.CanCollide = false
		crater.CanTouch = false
		crater.CanQuery = false
		crater.Material = Enum.Material.Neon
		crater.Color = Color3.fromRGB(255, 75, 10)
		crater.Transparency = 0.25
		crater.Parent = Workspace.Terrain

		task.delay(0.8, function()
			TweenService:Create(crater, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Transparency = 1,
				Color = Color3.fromRGB(40, 10, 5),
			}):Play()
			Debris:AddItem(crater, 1.8)
		end)

		-- Radiating magma cracks
		for f = 1, 10 do
			local fAngle = (f / 10) * (math.pi * 2) + (math.random() - 0.5) * 0.3
			local fDir = Vector3.new(math.cos(fAngle), 0, math.sin(fAngle))
			local fLength = (10 + math.random() * 8) * sizeScale
			local fCenter = impactPos + fDir * (fLength * 0.5)

			local fracture = Instance.new("Part")
			fracture.Name = "FireFracture_" .. f
			fracture.Size = Vector3.new(0.7 * sizeScale, 0.05, fLength)
			fracture.CFrame = CFrame.lookAt(fCenter, fCenter + fDir)
			fracture.Anchored = true
			fracture.CanCollide = false
			fracture.CanTouch = false
			fracture.CanQuery = false
			fracture.Material = Enum.Material.Neon
			fracture.Color = Color3.fromRGB(255, 130, 15)
			fracture.Transparency = 0.2
			fracture.Parent = Workspace.Terrain

			task.delay(0.5, function()
				TweenService:Create(fracture, TweenInfo.new(1.3, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					Transparency = 1,
					Color = Color3.fromRGB(30, 8, 2),
				}):Play()
				Debris:AddItem(fracture, 1.5)
			end)
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
	local ssP = Players:GetPlayerFromCharacter(char)
	local sizeScale = math.max(0.4, (ssP and ssP:GetAttribute("Stat_size")) or 1.0)

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

	-- 2b. Charging energy vortex around the sword during the windup: orbiting ember sprites
	--     that spiral inward, building intensity until the slash fires.
	do
		local chargeAtt = Instance.new("Attachment")
		chargeAtt.Name = "InfernalChargeVortex"
		chargeAtt.Position = Vector3.new(0, 0, 0)
		chargeAtt.Parent = rootPart
		local chargeEmbers = makeEmberEmitter(chargeAtt, 120)
		chargeEmbers.Name = "InfernalChargeEmbers"
		chargeEmbers.Speed = NumberRange.new(0, 0)
		chargeEmbers.SpreadAngle = Vector2.new(0, 0)
		chargeEmbers.Lifetime = NumberRange.new(0.5, 0.9)
		chargeEmbers.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.7),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		local chargeFlames = makeFlameEmitter(chargeAtt, 90, 3.2, 4)
		chargeFlames.Name = "InfernalChargeFlames"
		chargeFlames.SpreadAngle = Vector2.new(180, 180)
		chargeFlames.Speed = NumberRange.new(2, 8)

		-- Orbit a ring of glowing sprites that rise and tighten as the windup completes
		task.spawn(function()
			local orbitParts: { BasePart } = {}
			local ORBIT_COUNT = 8
			local orbitFolder = Instance.new("Folder")
			orbitFolder.Name = "InfernalChargeOrbit"
			orbitFolder.Parent = char
			for i = 1, ORBIT_COUNT do
				local orb = Instance.new("Part")
				orb.Name = "ChargeOrb"
				orb.Shape = Enum.PartType.Ball
				orb.Size = Vector3.new(0.7, 0.7, 0.7)
				orb.Material = Enum.Material.Neon
				orb.Color = Color3.fromRGB(255, 180, 60)
				orb.CanCollide = false
				orb.CanTouch = false
				orb.CanQuery = false
				orb.Anchored = true
				orb.Parent = orbitFolder
				local oLight = Instance.new("PointLight")
				oLight.Color = Color3.fromRGB(255, 150, 40)
				oLight.Brightness = 3
				oLight.Range = 10
				oLight.Parent = orb
				table.insert(orbitParts, orb)
			end

			local chargeStart = os.clock()
			local chargeDur = 1.5
			while os.clock() - chargeStart < chargeDur do
				if not char or not char.Parent or not rootPart.Parent then break end
				local a = math.clamp((os.clock() - chargeStart) / chargeDur, 0, 1)
				local radius = 5.0 - 3.5 * a
				local baseY = rootPart.Position.Y + 1.0 + a * 1.5
				for i, orb in ipairs(orbitParts) do
					local ang = (i / ORBIT_COUNT) * math.pi * 2 + a * math.pi * 4
					orb.CFrame = CFrame.new(rootPart.Position + Vector3.new(math.cos(ang) * radius, (baseY - rootPart.Position.Y), math.sin(ang) * radius))
					orb.Size = Vector3.new(0.7 + a * 0.6, 0.7 + a * 0.6, 0.7 + a * 0.6)
				end
				RunService.RenderStepped:Wait()
			end

			-- Collapse: orbs snap to the sword then vanish
			for _, orb in ipairs(orbitParts) do
				TweenService:Create(orb, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.In), {
					Size = Vector3.new(0.1, 0.1, 0.1),
					Transparency = 1,
				}):Play()
			end
			Debris:AddItem(orbitFolder, 0.3)
			chargeEmbers.Enabled = false
			chargeFlames.Enabled = false
			Debris:AddItem(chargeAtt, 0.6)
		end)
	end

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

	-- 3b. Infernal Wrath ULTIMATE impact: multi-layer shockwave, sky pillar, ground crack, aftershock.
	local function playInfernalImpactMegaVFX()
		local groundY = impactPos.Y
		local megaFolder = Instance.new("Folder")
		megaFolder.Name = "InfernalWrathImpact"
		megaFolder.Parent = Workspace.Terrain

		-- (a) Blinding flash ball + shock dome
		local flash = Instance.new("Part")
		flash.Name = "InfernalFlash"
		flash.Shape = Enum.PartType.Ball
		flash.Size = Vector3.new(4, 4, 4) * sizeScale
		flash.CFrame = CFrame.new(impactPos + Vector3.new(0, 1.5, 0))
		flash.Anchored = true
		flash.CanCollide = false
		flash.CanTouch = false
		flash.CanQuery = false
		flash.Material = Enum.Material.Neon
		flash.Color = Color3.fromRGB(255, 245, 210)
		flash.Transparency = 0.05
		flash.Parent = megaFolder
		TweenService:Create(flash, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(58, 40, 58) * sizeScale,
			Transparency = 1,
			Color = Color3.fromRGB(255, 80, 0),
		}):Play()
		Debris:AddItem(flash, 0.55)

		local flashLight = Instance.new("PointLight")
		flashLight.Color = Color3.fromRGB(255, 150, 40)
		flashLight.Brightness = 40
		flashLight.Range = 90
		flashLight.Parent = flash
		TweenService:Create(flashLight, TweenInfo.new(0.5), { Brightness = 0 }):Play()

		-- (b) Expanding ground shockwave rings (3 pulses)
		for ringIdx = 1, 3 do
			task.delay((ringIdx - 1) * 0.12, function()
				local ring = Instance.new("Part")
				ring.Name = "InfernalShockRing"
				ring.Shape = Enum.PartType.Cylinder
				ring.Size = Vector3.new(0.4, 6, 6) * sizeScale
				ring.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.15, 0)) * CFrame.Angles(0, 0, math.rad(90))
				ring.Anchored = true
				ring.CanCollide = false
				ring.CanTouch = false
				ring.CanQuery = false
				ring.Material = Enum.Material.Neon
				ring.Color = Color3.fromRGB(255, 120 + ringIdx * 30, 20)
				ring.Transparency = 0.1
				ring.Parent = megaFolder
				TweenService:Create(ring, TweenInfo.new(0.65 + ringIdx * 0.1, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
					Size = Vector3.new(0.4, (24 + ringIdx * 22) * sizeScale, (24 + ringIdx * 22) * sizeScale),
					Transparency = 1,
				}):Play()
				Debris:AddItem(ring, 1.2)
			end)
		end

		-- (c) Sky-splitting flame pillar
		local pillar = Instance.new("Part")
		pillar.Name = "InfernalPillar"
		pillar.Shape = Enum.PartType.Cylinder
		pillar.Size = Vector3.new(120, 22, 22) * sizeScale
		pillar.CFrame = CFrame.new(impactPos + Vector3.new(0, 60, 0)) * CFrame.Angles(0, 0, math.rad(90))
		pillar.Anchored = true
		pillar.CanCollide = false
		pillar.CanTouch = false
		pillar.CanQuery = false
		pillar.Material = Enum.Material.Neon
		pillar.Color = Color3.fromRGB(255, 170, 40)
		pillar.Transparency = 0.35
		pillar.Parent = megaFolder
		local pillarAtt = Instance.new("Attachment")
		pillarAtt.Parent = pillar
		local pillarFlames = makeFlameEmitter(pillarAtt, 300, 14, 30)
		pillarFlames.SpreadAngle = Vector2.new(8, 8)
		pillarFlames.Speed = NumberRange.new(20, 60)
		pillarFlames.Lifetime = NumberRange.new(0.4, 0.9)
		local pillarEmbers = makeEmberEmitter(pillarAtt, 160)
		pillarEmbers.Speed = NumberRange.new(30, 90)
		TweenService:Create(pillar, TweenInfo.new(0.9, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(180, 34, 34) * sizeScale,
		}):Play()
		Debris:AddItem(pillar, 1.1)

		-- (d) Ground crack decal
		local crack = Instance.new("Part")
		crack.Name = "InfernalGroundCrack"
		crack.Shape = Enum.PartType.Cylinder
		crack.Size = Vector3.new(0.2, 46, 46) * sizeScale
		crack.CFrame = CFrame.new(Vector3.new(impactPos.X, groundY + 0.05, impactPos.Z)) * CFrame.Angles(0, 0, math.rad(90))
		crack.Anchored = true
		crack.CanCollide = false
		crack.CanTouch = false
		crack.CanQuery = false
		crack.Material = Enum.Material.Neon
		crack.Color = Color3.fromRGB(255, 60, 0)
		crack.Transparency = 0.25
		crack.Parent = megaFolder
		TweenService:Create(crack, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
		}):Play()
		Debris:AddItem(crack, 2.4)

		-- (e) Camera juice for local caster
		if isLocalCaster then
			triggerCameraShake(2.4, 0.7)
			triggerFOVPunch(14, 0.5)
		end

		-- (f) Delayed secondary aftershock
		task.delay(0.35, function()
			if not char or not char.Parent then return end
			local aftershock = Instance.new("Part")
			aftershock.Name = "InfernalAftershock"
			aftershock.Shape = Enum.PartType.Cylinder
			aftershock.Size = Vector3.new(0.35, 8, 8) * sizeScale
			aftershock.CFrame = CFrame.new(impactPos + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
			aftershock.Anchored = true
			aftershock.CanCollide = false
			aftershock.CanTouch = false
			aftershock.CanQuery = false
			aftershock.Material = Enum.Material.Neon
			aftershock.Color = Color3.fromRGB(255, 200, 90)
			aftershock.Transparency = 0.15
			aftershock.Parent = Workspace.Terrain
			TweenService:Create(aftershock, TweenInfo.new(0.8, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), {
				Size = Vector3.new(0.35, 70, 70) * sizeScale,
				Transparency = 1,
			}):Play()
			Debris:AddItem(aftershock, 1.0)
		end)

		Debris:AddItem(megaFolder, 3.0)
	end

	-- 4. Impact explosion using 'Light Explosion VFX' asset
	local function triggerImpactVFX()
		if not char or not char.Parent then return end

		-- Mega cinematic impact layers
		playInfernalImpactMegaVFX()

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

	local travelTime = (lifetime or 0.32) * 0.55
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Rain of Arrows: Vine Arena Cage (Visual entrapment cage around the AoE zone)
-- Uses the same vine stem/node/leaf primitives from Entangling Arrow for a
-- cohesive woodland briar aesthetic. Builds arched vine pillars around the
-- perimeter with horizontal vine rings and scattered leaf clusters.
-- ─────────────────────────────────────────────────────────────────────────────
local function spawnVineArenaCage(center: Vector3, radius: number, duration: number)
	-- Ground level detection
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {}
	rayParams.IgnoreWater = true
	local groundRay = Workspace:Raycast(center + Vector3.new(0, 5, 0), Vector3.new(0, -15, 0), rayParams)
	local groundY = groundRay and groundRay.Position.Y or center.Y
	local centerBase = Vector3.new(center.X, groundY, center.Z)

	local cage = Instance.new("Model")
	cage.Name = "VineArenaCageVFX"
	cage.Parent = Workspace.Terrain

	local allParts: { BasePart } = {}
	local function regPart(p: BasePart?)
		if p then table.insert(allParts, p) end
		return p
	end

	local cageHeight = 14
	local numPillars = 10
	local pillarSteps = 12

	-- =====================================================================
	-- 1. ARCHED VINE PILLARS around the perimeter
	-- =====================================================================
	for pillar = 1, numPillars do
		local baseAngle = (pillar / numPillars) * math.pi * 2
		local pillarBaseX = math.cos(baseAngle) * radius
		local pillarBaseZ = math.sin(baseAngle) * radius
		local pillarBase = centerBase + Vector3.new(pillarBaseX, 0.1, pillarBaseZ)

		-- Slight inward lean at the top to form an arena dome shape
		local topLean = 0.88
		local prevP = pillarBase

		for step = 1, pillarSteps do
			local alpha = step / pillarSteps
			-- Arch inward slightly towards top
			local curRadius = radius * (1 - (1 - topLean) * math.pow(alpha, 1.5))
			local curY = alpha * cageHeight
			-- Gentle spiral twist along each pillar
			local twistAngle = baseAngle + math.sin(alpha * math.pi * 2) * 0.15
			local curX = math.cos(twistAngle) * curRadius
			local curZ = math.sin(twistAngle) * curRadius
			local curP = centerBase + Vector3.new(curX, curY, curZ)

			local thick = math.max(0.28, 0.65 * (1 - alpha * 0.35))
			local col = (step % 3 == 0) and VINE_BARK_LIGHT or ((step % 2 == 0) and VINE_BARK_MID or VINE_BARK_DARK)

			regPart(createVineSegment(cage, prevP, curP, thick, col))
			regPart(createVineJointNode(cage, curP, thick * 1.1, col))

			-- Leaf sprouts on alternating segments facing outward
			if step % 3 == 0 then
				local outNorm = Vector3.new(math.cos(twistAngle), 0.2, math.sin(twistAngle))
				regPart(createLeafSprout(cage, curP, outNorm, 1.15))
				if math.random() > 0.4 then
					regPart(createLeafSprout(cage, curP, -outNorm + Vector3.new(0, 0.5, 0), 0.9))
				end
			end

			-- Prominent leaf crown at the top of each pillar
			if step == pillarSteps then
				local topNorm = Vector3.new(math.cos(baseAngle), 0.8, math.sin(baseAngle))
				regPart(createLeafSprout(cage, curP, topNorm, 1.35))
				regPart(createLeafSprout(cage, curP, Vector3.new(-topNorm.X, 0.9, -topNorm.Z), 1.25))
				regPart(createLeafSprout(cage, curP, Vector3.new(0, 1, 0), 1.1))
			end

			prevP = curP
		end
	end

	-- =====================================================================
	-- 2. HORIZONTAL VINE RINGS connecting pillars at multiple heights
	-- =====================================================================
	local ringHeights = { 0.2, 0.4, 0.65, 0.88 }
	for _, heightFrac in ipairs(ringHeights) do
		local ringY = heightFrac * cageHeight
		local ringRadius = radius * (1 - (1 - 0.88) * math.pow(heightFrac, 1.5))
		local ringSegments = numPillars * 3
		local prevRingP = centerBase + Vector3.new(math.cos(0) * ringRadius, ringY, math.sin(0) * ringRadius)

		for seg = 1, ringSegments do
			local angle = (seg / ringSegments) * math.pi * 2
			local wobble = math.sin(seg * 2.3 + heightFrac * 7) * 0.4
			local curP = centerBase + Vector3.new(
				math.cos(angle) * (ringRadius + wobble),
				ringY + math.sin(seg * 1.7) * 0.3,
				math.sin(angle) * (ringRadius + wobble)
			)
			local thick = math.max(0.2, 0.38 * (1 - heightFrac * 0.3))
			local col = (seg % 2 == 0) and VINE_BARK_MID or VINE_BARK_DARK

			regPart(createVineSegment(cage, prevRingP, curP, thick, col))

			-- Joint nodes at pillar intersections
			if seg % 3 == 0 then
				regPart(createVineJointNode(cage, curP, thick * 1.15, VINE_BARK_LIGHT))
			end

			-- Leaf clusters along the rings
			if seg % 5 == 0 then
				local outNorm = Vector3.new(math.cos(angle), 0.15, math.sin(angle))
				regPart(createLeafSprout(cage, curP, outNorm, 0.95))
			end

			prevRingP = curP
		end
	end

	-- =====================================================================
	-- 3. GROUND ROOT MAT around the cage perimeter
	-- =====================================================================
	local numGroundRoots = 14
	for r = 1, numGroundRoots do
		local baseAngle = (r / numGroundRoots) * math.pi * 2 + (math.random() - 0.5) * 0.3
		local rootLen = math.random(28, 50) / 10
		local steps = 3
		local prevP = centerBase + Vector3.new(
			math.cos(baseAngle) * (radius - 1.2),
			0.08,
			math.sin(baseAngle) * (radius - 1.2)
		)

		for s = 1, steps do
			local distFrac = s / steps
			local curDist = (radius - 1.2) + rootLen * distFrac
			local curveAngle = baseAngle + math.sin(s * 1.6 + r) * 0.22
			local curP = centerBase + Vector3.new(
				math.cos(curveAngle) * curDist,
				0.06 + math.sin(s * 1.1) * 0.06,
				math.sin(curveAngle) * curDist
			)
			local thick = math.max(0.16, 0.38 * (1 - distFrac * 0.5))
			regPart(createVineSegment(cage, prevP, curP, thick, VINE_BARK_DARK))
			regPart(createVineJointNode(cage, curP, thick * 1.08, VINE_BARK_DARK))

			if s >= 2 and math.random() > 0.35 then
				local leafDir = Vector3.new(math.cos(curveAngle + math.pi * 0.5), 0.3, math.sin(curveAngle + math.pi * 0.5))
				regPart(createLeafSprout(cage, curP, leafDir, 0.8))
			end

			prevP = curP
		end
	end

	-- =====================================================================
	-- 4. EMERALD LIGHTING & FLOATING LEAF PARTICLES
	-- =====================================================================
	local lightPart = Instance.new("Part")
	lightPart.Name = "CageCenter"
	lightPart.Size = Vector3.new(1, 1, 1)
	lightPart.Transparency = 1
	lightPart.CanCollide = false
	lightPart.CanTouch = false
	lightPart.CanQuery = false
	lightPart.Anchored = true
	lightPart.CFrame = CFrame.new(centerBase + Vector3.new(0, cageHeight * 0.35, 0))
	lightPart.Parent = cage

	local cageLight = Instance.new("PointLight")
	cageLight.Color = Color3.fromRGB(110, 235, 60)
	cageLight.Brightness = 3.2
	cageLight.Range = radius * 2.5
	cageLight.Parent = lightPart

	local cageLightAtt = Instance.new("Attachment")
	cageLightAtt.Parent = lightPart

	-- Ambient floating leaves inside the cage
	local cageLeavesPE = Instance.new("ParticleEmitter")
	cageLeavesPE.Name = "CageAmbientLeaves"
	cageLeavesPE.Texture = "rbxassetid://258128463"
	cageLeavesPE.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(170, 255, 90)),
		ColorSequenceKeypoint.new(0.5, Color3.fromRGB(130, 230, 65)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(85, 175, 40)),
	})
	cageLeavesPE.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	cageLeavesPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(0.5, 0.75),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	cageLeavesPE.Lifetime = NumberRange.new(1.8, 3.0)
	cageLeavesPE.Rate = 25
	cageLeavesPE.Speed = NumberRange.new(1, 3.5)
	cageLeavesPE.SpreadAngle = Vector2.new(180, 60)
	cageLeavesPE.Rotation = NumberRange.new(0, 360)
	cageLeavesPE.RotSpeed = NumberRange.new(-40, 40)
	cageLeavesPE.LightEmission = 0.5
	cageLeavesPE.Parent = cageLightAtt
	cageLeavesPE:Emit(20)

	-- Emerald spore glow particles
	local cageSporesPE = Instance.new("ParticleEmitter")
	cageSporesPE.Name = "CageSporeGlow"
	cageSporesPE.Color = ColorSequence.new(Color3.fromRGB(180, 255, 95))
	cageSporesPE.LightEmission = 1
	cageSporesPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.22),
		NumberSequenceKeypoint.new(1, 0.04),
	})
	cageSporesPE.Lifetime = NumberRange.new(1.0, 1.8)
	cageSporesPE.Rate = 30
	cageSporesPE.Speed = NumberRange.new(0.5, 2.0)
	cageSporesPE.SpreadAngle = Vector2.new(180, 90)
	cageSporesPE.Parent = cageLightAtt
	cageSporesPE:Emit(25)

	-- =====================================================================
	-- 5. GROWTH SURGE ANIMATION (parts scale upward from ground)
	-- =====================================================================
	local partOrigData: { { part: BasePart, origCF: CFrame, origSize: Vector3 } } = {}
	for _, p in ipairs(allParts) do
		table.insert(partOrigData, { part = p, origCF = p.CFrame, origSize = p.Size })
	end

	local growDuration = 0.32
	local growStartTime = os.clock()
	local growConn: RBXScriptConnection?
	growConn = RunService.Heartbeat:Connect(function()
		local elapsed = os.clock() - growStartTime
		local alpha = math.clamp(elapsed / growDuration, 0, 1)
		local smoothAlpha = 1 - math.pow(1 - alpha, 3)

		for _, data in ipairs(partOrigData) do
			if data.part and data.part.Parent then
				local groundCF = CFrame.new(data.origCF.Position.X, groundY, data.origCF.Position.Z)
				data.part.CFrame = groundCF:Lerp(data.origCF, smoothAlpha)
				data.part.Size = data.origSize * math.max(0.05, smoothAlpha)
			end
		end

		if alpha >= 1 then
			if growConn then growConn:Disconnect() end
			for _, data in ipairs(partOrigData) do
				if data.part and data.part.Parent then
					data.part.CFrame = data.origCF
					data.part.Size = data.origSize
				end
			end
		end
	end)

	-- =====================================================================
	-- 6. CRUMBLE DECAY at end of duration
	-- =====================================================================
	local decayTime = 0.5
	task.delay(math.max(0, duration - decayTime), function()
		if growConn then growConn:Disconnect() end
		cageLeavesPE.Enabled = false
		cageSporesPE.Enabled = false

		local decayStart = os.clock()
		local decayConn: RBXScriptConnection?
		decayConn = RunService.Heartbeat:Connect(function()
			local elapsed = os.clock() - decayStart
			local alpha = math.clamp(elapsed / decayTime, 0, 1)
			local smoothFade = math.pow(alpha, 2)

			for _, data in ipairs(partOrigData) do
				if data.part and data.part.Parent then
					data.part.Transparency = smoothFade
					data.part.Size = data.origSize * (1 - smoothFade * 0.35)
				end
			end

			cageLight.Brightness = 3.2 * (1 - smoothFade)

			if alpha >= 1 then
				if decayConn then decayConn:Disconnect() end
				cage:Destroy()
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

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 1: Verdant Slash VFX (Instant Piercing Nature Dash & Clean Lingering Slash)
-- ─────────────────────────────────────────────────────────────────────────────
local function spawnRangerDashAfterimages(char: Model, startPos: Vector3, endPos: Vector3, flatDir: Vector3)
	local partsToClone: { BasePart } = {}
	for _, desc in ipairs(char:GetDescendants()) do
		if desc:IsA("BasePart") and desc.Transparency < 0.9 and desc.Name ~= "HumanoidRootPart" then
			table.insert(partsToClone, desc)
		end
	end
	if #partsToClone == 0 then return end

	local ghostModel = Instance.new("Model")
	ghostModel.Name = "RangerDashGhost"
	ghostModel.Parent = Workspace.Terrain

	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local currentRootCF = rootPart and rootPart.CFrame or CFrame.new(startPos)
	local sampleAlphas = { 0.25, 0.60, 0.90 }

	for _, alpha in ipairs(sampleAlphas) do
		local samplePos = startPos:Lerp(endPos, alpha)
		local sampleCF = CFrame.lookAt(samplePos, samplePos + flatDir)
		local offsetFromRoot = currentRootCF:Inverse()

		for _, p in ipairs(partsToClone) do
			local ghostPart = Instance.new("Part")
			ghostPart.Name = "GhostPart"
			ghostPart.Size = p.Size
			ghostPart.Material = Enum.Material.Neon
			ghostPart.Color = Color3.fromRGB(135, 255, 80)
			ghostPart.Transparency = 0.5
			ghostPart.CanCollide = false
			ghostPart.CanTouch = false
			ghostPart.CanQuery = false
			ghostPart.Anchored = true
			ghostPart.CFrame = sampleCF * (offsetFromRoot * p.CFrame)
			ghostPart.Parent = ghostModel

			TweenService:Create(ghostPart, TweenInfo.new(0.24, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
				Transparency = 1,
				Size = p.Size * 1.08,
			}):Play()
		end
	end

	Debris:AddItem(ghostModel, 0.3)
end

local function spawnVerdantPierceHitEffect(targetRoot: BasePart, dashDir: Vector3)
	local targetPos = targetRoot.Position + Vector3.new(0, 0.5, 0)
	local holder = Instance.new("Part")
	holder.Name = "VerdantHitEffect"
	holder.Size = Vector3.new(0.2, 0.2, 0.2)
	holder.Transparency = 1
	holder.CanCollide = false
	holder.CanTouch = false
	holder.CanQuery = false
	holder.Anchored = true
	holder.CFrame = CFrame.new(targetPos)
	holder.Parent = Workspace.Terrain

	local att = Instance.new("Attachment")
	att.Parent = holder

	-- 1. Sharp nature leaves radiating outward (Reference Panel 3)
	local leavesPE = Instance.new("ParticleEmitter")
	leavesPE.Name = "PierceLeaves"
	leavesPE.Texture = "rbxassetid://258128463"
	leavesPE.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 255, 130)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(150, 255, 75)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 200, 45)),
	})
	leavesPE.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.7, 0.2),
		NumberSequenceKeypoint.new(1, 1),
	})
	leavesPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.8),
		NumberSequenceKeypoint.new(0.5, 0.65),
		NumberSequenceKeypoint.new(1, 0.1),
	})
	leavesPE.Lifetime = NumberRange.new(0.35, 0.65)
	leavesPE.Speed = NumberRange.new(12, 26)
	leavesPE.SpreadAngle = Vector2.new(180, 60)
	leavesPE.Rotation = NumberRange.new(0, 360)
	leavesPE.RotSpeed = NumberRange.new(-180, 180)
	leavesPE.LightEmission = 0.8
	leavesPE.Parent = att
	leavesPE:Emit(18)

	-- 2. Sharp energy spark particles / shards
	local sparkPE = Instance.new("ParticleEmitter")
	sparkPE.Name = "PierceSparks"
	sparkPE.Texture = "rbxassetid://241594419"
	sparkPE.Color = ColorSequence.new(Color3.fromRGB(210, 255, 120), Color3.fromRGB(110, 245, 60))
	sparkPE.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.8, 0.3),
		NumberSequenceKeypoint.new(1, 1),
	})
	sparkPE.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.55),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	sparkPE.Lifetime = NumberRange.new(0.25, 0.45)
	sparkPE.Speed = NumberRange.new(15, 32)
	sparkPE.SpreadAngle = Vector2.new(180, 45)
	sparkPE.LightEmission = 1
	sparkPE.Parent = att
	sparkPE:Emit(24)

	-- 3. Sharp piercing energy slash blades cutting across target body
	for i = 1, 2 do
		local slashBlade = Instance.new("Part")
		slashBlade.Name = "PierceSlashCut"
		slashBlade.Size = Vector3.new(0.15, 0.3, 4.2)
		slashBlade.Material = Enum.Material.Neon
		slashBlade.Color = (i == 1) and Color3.fromRGB(235, 255, 160) or Color3.fromRGB(130, 255, 65)
		slashBlade.Transparency = 0.1
		slashBlade.CanCollide = false
		slashBlade.CanTouch = false
		slashBlade.CanQuery = false
		slashBlade.Anchored = true
		local rollAngle = (i == 1) and 35 or -40
		slashBlade.CFrame = CFrame.lookAt(targetPos, targetPos + dashDir) * CFrame.Angles(0, 0, math.rad(rollAngle))
		slashBlade.Parent = holder

		TweenService:Create(slashBlade, TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Transparency = 1,
			Size = Vector3.new(0.05, 0.1, 5.5),
		}):Play()
	end

	-- 4. Emerald PointLight flash
	local pLight = Instance.new("PointLight")
	pLight.Color = Color3.fromRGB(145, 255, 80)
	pLight.Brightness = 4.5
	pLight.Range = 12
	pLight.Parent = holder

	TweenService:Create(pLight, TweenInfo.new(0.24), { Brightness = 0 }):Play()
	Debris:AddItem(holder, 0.7)
end

local function playRangerVerdantSlashVFX(casterChar: Model, startPos: Vector3, endPos: Vector3, flatDir: Vector3, actualDist: number)
	local midPos = startPos:Lerp(endPos, 0.5)

	local slashModel = Instance.new("Model")
	slashModel.Name = "VerdantSlashPathVFX"
	slashModel.Parent = Workspace.Terrain

	-- Core anchor part for attachments
	local anchor = Instance.new("Part")
	anchor.Name = "SlashAnchor"
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.Transparency = 1
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.Anchored = true
	anchor.CFrame = CFrame.new(midPos)
	anchor.Parent = slashModel

	local startAtt = Instance.new("Attachment")
	startAtt.Name = "StartAtt"
	startAtt.WorldPosition = startPos + Vector3.new(0, 1.2, 0)
	startAtt.Parent = anchor

	local midAtt = Instance.new("Attachment")
	midAtt.Name = "MidAtt"
	midAtt.WorldPosition = midPos + Vector3.new(0, 1.2, 0)
	midAtt.Parent = anchor

	local endAtt = Instance.new("Attachment")
	endAtt.Name = "EndAtt"
	endAtt.WorldPosition = endPos + Vector3.new(0, 1.2, 0)
	endAtt.Parent = anchor

	-- 1. Outer Nature Aura Beams (double-tapered blade: 0 -> 2.6 -> 0 studs)
	local auraBeam1 = Instance.new("Beam")
	auraBeam1.Name = "AuraBeam1"
	auraBeam1.Attachment0 = startAtt
	auraBeam1.Attachment1 = midAtt
	auraBeam1.Width0 = 0.08
	auraBeam1.Width1 = 2.6
	auraBeam1.Color = ColorSequence.new(Color3.fromRGB(150, 255, 80), Color3.fromRGB(90, 235, 50))
	auraBeam1.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.3),
		NumberSequenceKeypoint.new(1, 0.05),
	})
	auraBeam1.LightEmission = 1
	auraBeam1.FaceCamera = true
	auraBeam1.Parent = anchor

	local auraBeam2 = Instance.new("Beam")
	auraBeam2.Name = "AuraBeam2"
	auraBeam2.Attachment0 = midAtt
	auraBeam2.Attachment1 = endAtt
	auraBeam2.Width0 = 2.6
	auraBeam2.Width1 = 0.08
	auraBeam2.Color = ColorSequence.new(Color3.fromRGB(90, 235, 50), Color3.fromRGB(150, 255, 80))
	auraBeam2.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.05),
		NumberSequenceKeypoint.new(1, 0.3),
	})
	auraBeam2.LightEmission = 1
	auraBeam2.FaceCamera = true
	auraBeam2.Parent = anchor

	-- 2. Inner Brilliant White-Lime Blade Core (0 -> 0.9 -> 0 studs)
	local coreBeam1 = Instance.new("Beam")
	coreBeam1.Name = "CoreBeam1"
	coreBeam1.Attachment0 = startAtt
	coreBeam1.Attachment1 = midAtt
	coreBeam1.Width0 = 0.04
	coreBeam1.Width1 = 0.9
	coreBeam1.Color = ColorSequence.new(Color3.fromRGB(245, 255, 200), Color3.fromRGB(200, 255, 140))
	coreBeam1.Transparency = NumberSequence.new(0)
	coreBeam1.LightEmission = 1
	coreBeam1.FaceCamera = true
	coreBeam1.Parent = anchor

	local coreBeam2 = Instance.new("Beam")
	coreBeam2.Name = "CoreBeam2"
	coreBeam2.Attachment0 = midAtt
	coreBeam2.Attachment1 = endAtt
	coreBeam2.Width0 = 0.9
	coreBeam2.Width1 = 0.04
	coreBeam2.Color = ColorSequence.new(Color3.fromRGB(200, 255, 140), Color3.fromRGB(245, 255, 200))
	coreBeam2.Transparency = NumberSequence.new(0)
	coreBeam2.LightEmission = 1
	coreBeam2.FaceCamera = true
	coreBeam2.Parent = anchor

	-- 3. Sharp 3D Neon Blade Centerpiece
	local blade = Instance.new("Part")
	blade.Name = "VerdantSlashBlade"
	blade.Size = Vector3.new(0.18, 0.45, actualDist)
	blade.Material = Enum.Material.Neon
	blade.Color = Color3.fromRGB(175, 255, 95)
	blade.Transparency = 0.15
	blade.CanCollide = false
	blade.CanTouch = false
	blade.CanQuery = false
	blade.Anchored = true
	blade.CFrame = CFrame.lookAt(midPos + Vector3.new(0, 1.2, 0), endPos + Vector3.new(0, 1.2, 0))
	blade.Parent = slashModel

	-- Subtle ground trace strip
	local groundStrip = Instance.new("Part")
	groundStrip.Name = "VerdantGroundStrip"
	groundStrip.Size = Vector3.new(0.8, 0.05, actualDist)
	groundStrip.Material = Enum.Material.Neon
	groundStrip.Color = Color3.fromRGB(120, 240, 60)
	groundStrip.Transparency = 0.55
	groundStrip.CanCollide = false
	groundStrip.CanTouch = false
	groundStrip.CanQuery = false
	groundStrip.Anchored = true
	groundStrip.CFrame = CFrame.lookAt(midPos + Vector3.new(0, 0.08, 0), endPos + Vector3.new(0, 0.08, 0))
	groundStrip.Parent = slashModel

	-- 4. Floating leaves gently suspended & drifting along the slash (Panel 2)
	local slashLeaves = Instance.new("ParticleEmitter")
	slashLeaves.Name = "SlashPathLeaves"
	slashLeaves.Texture = "rbxassetid://258128463"
	slashLeaves.Color = ColorSequence.new(Color3.fromRGB(180, 255, 100), Color3.fromRGB(100, 230, 60))
	slashLeaves.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.1),
		NumberSequenceKeypoint.new(0.7, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	slashLeaves.Size = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.65),
		NumberSequenceKeypoint.new(0.5, 0.5),
		NumberSequenceKeypoint.new(1, 0.15),
	})
	slashLeaves.Lifetime = NumberRange.new(0.4, 0.75)
	slashLeaves.Speed = NumberRange.new(2, 5)
	slashLeaves.SpreadAngle = Vector2.new(180, 180)
	slashLeaves.Rotation = NumberRange.new(0, 360)
	slashLeaves.RotSpeed = NumberRange.new(-60, 60)
	slashLeaves.LightEmission = 0.7
	slashLeaves.Parent = midAtt
	slashLeaves:Emit(22)

	-- ─── LEAF FLURRY VFX: Rich leaf bursts scattered along the dash trajectory ───
	local leafBurstAlphas = { 0.0, 0.25, 0.5, 0.75, 1.0 }
	for _, alpha in ipairs(leafBurstAlphas) do
		local burstPos = startPos:Lerp(endPos, alpha) + Vector3.new(0, 1.2, 0)
		local burstHolder = Instance.new("Part")
		burstHolder.Name = "DashLeafBurst"
		burstHolder.Size = Vector3.new(0.1, 0.1, 0.1)
		burstHolder.Transparency = 1
		burstHolder.CanCollide = false
		burstHolder.CanTouch = false
		burstHolder.CanQuery = false
		burstHolder.Anchored = true
		burstHolder.CFrame = CFrame.new(burstPos)
		burstHolder.Parent = slashModel

		local burstAtt = Instance.new("Attachment")
		burstAtt.Parent = burstHolder

		-- Large swirling leaf burst
		local leafPE = Instance.new("ParticleEmitter")
		leafPE.Name = "DashLeafFlurry"
		leafPE.Texture = "rbxassetid://258128463"
		leafPE.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 255, 130)),
			ColorSequenceKeypoint.new(0.4, Color3.fromRGB(140, 250, 70)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 200, 40)),
		})
		leafPE.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.0),
			NumberSequenceKeypoint.new(0.6, 0.15),
			NumberSequenceKeypoint.new(1, 1),
		})
		leafPE.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.9),
			NumberSequenceKeypoint.new(0.4, 0.7),
			NumberSequenceKeypoint.new(1, 0.2),
		})
		leafPE.Lifetime = NumberRange.new(0.5, 1.1)
		leafPE.Speed = NumberRange.new(6, 16)
		leafPE.SpreadAngle = Vector2.new(360, 120)
		leafPE.Rotation = NumberRange.new(0, 360)
		leafPE.RotSpeed = NumberRange.new(-120, 120)
		leafPE.LightEmission = 0.65
		leafPE.Drag = 3
		leafPE.Parent = burstAtt
		leafPE:Emit(12)

		-- Sparkling emerald dust at each burst point
		local dustPE = Instance.new("ParticleEmitter")
		dustPE.Name = "DashLeafDust"
		dustPE.Color = ColorSequence.new(Color3.fromRGB(185, 255, 110))
		dustPE.LightEmission = 1
		dustPE.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		dustPE.Lifetime = NumberRange.new(0.3, 0.65)
		dustPE.Speed = NumberRange.new(4, 12)
		dustPE.SpreadAngle = Vector2.new(360, 90)
		dustPE.Parent = burstAtt
		dustPE:Emit(8)
	end

	-- Leaf swirl attached to the caster's root part (follows character briefly)
	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if casterRoot then
		local swirlAtt = Instance.new("Attachment")
		swirlAtt.Name = "DashLeafSwirl"
		swirlAtt.Position = Vector3.new(0, 0.5, 0)
		swirlAtt.Parent = casterRoot

		local swirlPE = Instance.new("ParticleEmitter")
		swirlPE.Name = "DashSwirlLeaves"
		swirlPE.Texture = "rbxassetid://258128463"
		swirlPE.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 255, 160)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(160, 255, 85)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(90, 210, 50)),
		})
		swirlPE.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.0),
			NumberSequenceKeypoint.new(0.5, 0.1),
			NumberSequenceKeypoint.new(1, 1),
		})
		swirlPE.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.5, 0.55),
			NumberSequenceKeypoint.new(1, 0.15),
		})
		swirlPE.Lifetime = NumberRange.new(0.45, 0.95)
		swirlPE.Rate = 80
		swirlPE.Speed = NumberRange.new(4, 10)
		swirlPE.SpreadAngle = Vector2.new(360, 60)
		swirlPE.Rotation = NumberRange.new(0, 360)
		swirlPE.RotSpeed = NumberRange.new(-100, 100)
		swirlPE.LightEmission = 0.6
		swirlPE.Drag = 4
		swirlPE.Parent = swirlAtt
		swirlPE:Emit(18)

		task.delay(0.35, function()
			swirlPE.Enabled = false
			task.delay(1.0, function()
				if swirlAtt and swirlAtt.Parent then
					swirlAtt:Destroy()
				end
			end)
		end)
	end

	-- 5. Arrowhead / piercing tip flare at end position (Panel 1)
	local flareSpike1 = Instance.new("Part")
	flareSpike1.Name = "ArrowheadSpike1"
	flareSpike1.Size = Vector3.new(0.22, 0.22, 4.2)
	flareSpike1.Material = Enum.Material.Neon
	flareSpike1.Color = Color3.fromRGB(235, 255, 160)
	flareSpike1.CanCollide = false
	flareSpike1.CanTouch = false
	flareSpike1.CanQuery = false
	flareSpike1.Anchored = true
	flareSpike1.CFrame = CFrame.lookAt(endPos + Vector3.new(0, 1.2, 0), endPos + Vector3.new(0, 1.2, 0) + flatDir)
	flareSpike1.Parent = slashModel

	local flareSpike2 = Instance.new("Part")
	flareSpike2.Name = "ArrowheadSpike2"
	flareSpike2.Size = Vector3.new(3.6, 0.22, 0.22)
	flareSpike2.Material = Enum.Material.Neon
	flareSpike2.Color = Color3.fromRGB(150, 255, 80)
	flareSpike2.CanCollide = false
	flareSpike2.CanTouch = false
	flareSpike2.CanQuery = false
	flareSpike2.Anchored = true
	flareSpike2.CFrame = flareSpike1.CFrame * CFrame.Angles(0, 0, math.rad(45))
	flareSpike2.Parent = slashModel

	TweenService:Create(flareSpike1, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(0.05, 0.05, 5.6),
	}):Play()
	TweenService:Create(flareSpike2, TweenInfo.new(0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Transparency = 1,
		Size = Vector3.new(4.8, 0.05, 0.05),
	}):Play()

	-- 6. Emerald PointLight illuminating the path
	local pLight = Instance.new("PointLight")
	pLight.Color = Color3.fromRGB(130, 255, 75)
	pLight.Brightness = 4.0
	pLight.Range = 16
	pLight.Parent = midAtt

	-- 7. Visual Hit Effect on all pierced targets in path (Panel 3)
	for _, desc in ipairs(Workspace:GetDescendants()) do
		if desc:IsA("Model") and desc ~= casterChar and not desc:IsDescendantOf(casterChar) and not desc:FindFirstAncestorOfClass("Accessory") then
			local hum = desc:FindFirstChildOfClass("Humanoid")
			local root = (desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")) :: BasePart?
			if hum and hum.Health > 0 and root then
				local diff = root.Position - startPos
				local along = diff:Dot(flatDir)
				if along >= -0.5 and along <= (actualDist + 1.0) then
					local closestPoint = startPos + flatDir * math.clamp(along, 0, actualDist)
					local lateralDist = (Vector3.new(root.Position.X, startPos.Y, root.Position.Z) - closestPoint).Magnitude
					if lateralDist <= 6.0 then
						spawnVerdantPierceHitEffect(root, flatDir)
					end
				end
			end
		end
	end

	-- 8. Lingering duration & clean fade out (Panel 2: "A single, clean slash remains in the path of the dash")
	task.delay(0.42, function()
		slashLeaves.Enabled = false
		local fadeInfo = TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		TweenService:Create(blade, fadeInfo, { Transparency = 1 }):Play()
		TweenService:Create(groundStrip, fadeInfo, { Transparency = 1 }):Play()
		TweenService:Create(pLight, fadeInfo, { Brightness = 0 }):Play()
		TweenService:Create(auraBeam1, fadeInfo, { Width1 = 0 }):Play()
		TweenService:Create(auraBeam2, fadeInfo, { Width0 = 0 }):Play()
		TweenService:Create(coreBeam1, fadeInfo, { Width1 = 0 }):Play()
		TweenService:Create(coreBeam2, fadeInfo, { Width0 = 0 }):Play()
		task.delay(0.24, function()
			slashModel:Destroy()
		end)
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Skill 3: Seeker Barrage / Missile Buff & Guided Missile System
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

local function launchSingleSeekerMissile(casterChar: Model, sideOffset: number, verticalOffset: number, backwardOffset: number, curveDir: Vector3, speedMult: number?, sizeMult: number?)
	local rootPart = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local speed = math.max(0.2, speedMult or 1.0)
	local sizeScale = math.max(0.4, sizeMult or 1.0)

	local lookVec = rootPart.CFrame.LookVector
	local rightVec = rootPart.CFrame.RightVector
	local upVec = Vector3.new(0, 1, 0)

	local spawnOffset = -lookVec * backwardOffset + rightVec * sideOffset + upVec * verticalOffset
	local spawnPos = rootPart.Position + spawnOffset
	local initialDir = (curveDir).Unit
	local currentPos = spawnPos
	local currentVel = initialDir * (70.0 * speed)

	-- Small, streamlined projectile part scaled with size tome
	local carrier = Instance.new("Part")
	carrier.Name = "SeekerMissileVFX"
	carrier.Size = Vector3.new(0.35 * sizeScale, 0.35 * sizeScale, 0.75 * sizeScale)
	carrier.Material = Enum.Material.Neon
	carrier.Color = Color3.fromRGB(150, 255, 70)
	carrier.CanCollide = false
	carrier.CanTouch = false
	carrier.CanQuery = false
	carrier.Anchored = true
	carrier.CFrame = CFrame.lookAt(spawnPos, spawnPos + initialDir)

	-- Dynamic green light
	local mLight = Instance.new("PointLight")
	mLight.Color = Color3.fromRGB(150, 255, 70)
	mLight.Brightness = 3
	mLight.Range = 7 * sizeScale
	mLight.Parent = carrier

	-- Attachments on local X-axis (left and right of missile forward direction)
	local att0 = Instance.new("Attachment")
	att0.Name = "TrailAtt0"
	att0.Position = Vector3.new(-0.25 * sizeScale, 0, 0)
	att0.Parent = carrier

	local att1 = Instance.new("Attachment")
	att1.Name = "TrailAtt1"
	att1.Position = Vector3.new(0.25 * sizeScale, 0, 0)
	att1.Parent = carrier

	local trail = Instance.new("Trail")
	trail.Name = "SeekerTrail"
	trail.Attachment0 = att0
	trail.Attachment1 = att1
	trail.FaceCamera = true
	trail.Lifetime = 0.28 / speed
	trail.MinLength = 0.05
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Color = ColorSequence.new(Color3.fromRGB(150, 255, 70))
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.65, 0.25),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1.3 * sizeScale),
		NumberSequenceKeypoint.new(0.45, 0.75 * sizeScale),
		NumberSequenceKeypoint.new(1, 0.02),
	})
	trail.Parent = carrier

	carrier.Parent = Workspace.Terrain

	local function cleanupMissile()
		if not carrier or not carrier.Parent then return end
		carrier.Transparency = 1
		mLight.Enabled = false
		trail.Enabled = false
		for _, d in ipairs(carrier:GetDescendants()) do
			if d:IsA("BasePart") or d:IsA("Decal") then
				d.Transparency = 1
			elseif d:IsA("Light") then
				d.Enabled = false
			elseif d:IsA("ParticleEmitter") or d:IsA("Beam") or d:IsA("Trail") then
				d.Enabled = false
			end
		end
		task.delay(0.32, function()
			if carrier and carrier.Parent then
				carrier:Destroy()
			end
		end)
	end

	-- Search for nearest enemy target in workspace
	local function findNearestEnemy(pos: Vector3): (Model?, BasePart?)
		local bestDist = 70
		local bestTarget: Model? = nil
		local bestPart: BasePart? = nil

		for _, desc in ipairs(Workspace:GetDescendants()) do
			if desc:IsA("Model") and desc ~= casterChar and not desc:IsDescendantOf(casterChar) and not desc:FindFirstAncestorOfClass("Accessory") then
				local hum = desc:FindFirstChildOfClass("Humanoid")
				local root = (desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")) :: BasePart?
				if hum and hum.Health > 0 and root then
					local dist = (root.Position - pos).Magnitude
					if dist < bestDist then
						bestDist = dist
						bestTarget = desc
						bestPart = root
					end
				end
			end
		end
		return bestTarget, bestPart
	end

	task.spawn(function()
		local startTime = os.clock()
		local maxLifetime = 1.8 / speed
		local targetModel, targetRoot = findNearestEnemy(spawnPos)

		while os.clock() - startTime < maxLifetime do
			local dt = RunService.RenderStepped:Wait()
			local elapsed = os.clock() - startTime

			-- Re-check target if lost
			if not targetModel or not targetModel.Parent or not targetRoot or not targetRoot.Parent then
				targetModel, targetRoot = findNearestEnemy(currentPos)
			end

			if targetRoot and targetRoot.Parent and elapsed > (0.05 / speed) then
				local targetAimPos = targetRoot.Position + Vector3.new(0, 0.8, 0)
				local toTarget = (targetAimPos - currentPos)
				local distToTarget = toTarget.Magnitude

				if distToTarget < (3.2 * sizeScale) then
					-- Hit target!
					break
				end

				local desiredDir = toTarget.Unit
				local steerSpeed = 24.0 * speed
				local targetSpeed = 130.0 * speed
				currentVel = currentVel:Lerp(desiredDir * targetSpeed, math.clamp(dt * steerSpeed, 0, 1))
			else
				currentVel = currentVel + Vector3.new(0, 4.0 * dt, 0)
			end

			currentPos = currentPos + currentVel * dt

			if carrier and carrier.Parent then
				carrier.CFrame = CFrame.lookAt(currentPos, currentPos + currentVel)
			else
				break
			end
		end

		cleanupMissile()
	end)
end

function SkillController.LaunchMissile(casterChar: Model)
	local rootPart = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local charPlayer = Players:GetPlayerFromCharacter(casterChar) or (casterChar == player.Character and player)
	local extraProjectiles = math.max(0, math.floor((charPlayer and charPlayer:GetAttribute("Stat_projectileCount")) or 0))
	local totalMissiles = 3 + extraProjectiles
	local speedMult = math.max(0.2, (charPlayer and charPlayer:GetAttribute("Stat_projectileSpeed")) or 1.0)
	local sizeMult = math.max(0.4, (charPlayer and charPlayer:GetAttribute("Stat_size")) or 1.0)

	local lookVec = rootPart.CFrame.LookVector
	local rightVec = rootPart.CFrame.RightVector
	local upVec = Vector3.new(0, 1, 0)

	-- Dynamic fan-out formation based on total missile count (scaling with Quantity Tome)
	for i = 1, totalMissiles do
		local fraction = (totalMissiles == 1) and 0.5 or ((i - 1) / (totalMissiles - 1))
		local sideOffset = -1.4 + fraction * 2.8
		local vertOffset = 2.0 + math.sin(fraction * math.pi) * 0.75
		local backOffset = 1.2 + math.sin(fraction * math.pi) * 0.4
		local curveSide = -0.65 + fraction * 1.3
		local curveDir = (-lookVec * 0.75 + rightVec * curveSide + upVec * 0.6)

		local delayTime = (i - 1) * (0.035 / math.max(speedMult, 0.5))
		if delayTime > 0 then
			task.delay(delayTime, function()
				if casterChar and casterChar.Parent then
					launchSingleSeekerMissile(casterChar, sideOffset, vertOffset, backOffset, curveDir, speedMult, sizeMult)
				end
			end)
		else
			launchSingleSeekerMissile(casterChar, sideOffset, vertOffset, backOffset, curveDir, speedMult, sizeMult)
		end
	end
end

local function playRangerSkillVFX(char: Model, skillIndex: number, origin: Vector3, lookDir: Vector3, targetPosition: Vector3?, projectileCountParam: number?)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end
	local baseOrigin = rootPart.Position + Vector3.new(0, 1.35, 0)

	if skillIndex == 1 then
		local flatDir = flatUnit(lookDir)
		local dashDist = 32
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		local ignoreList: { Instance } = { char }
		for _, desc in ipairs(Workspace:GetDescendants()) do
			if desc:IsA("Model") and (desc:FindFirstChildOfClass("Humanoid") or desc:FindFirstAncestorOfClass("Accessory")) then
				table.insert(ignoreList, desc)
			end
		end
		rayParams.FilterDescendantsInstances = ignoreList
		rayParams.IgnoreWater = true

		local forwardRay = Workspace:Raycast(origin + Vector3.new(0, 1.2, 0), flatDir * dashDist, rayParams)
		local actualDist = dashDist
		if forwardRay and forwardRay.Distance > 0 then
			actualDist = math.max(3.0, forwardRay.Distance - 1.5)
		end
		local endPos = origin + flatDir * actualDist
		local groundRay = Workspace:Raycast(endPos + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), rayParams)
		if groundRay then
			local hum = char:FindFirstChildOfClass("Humanoid")
			local hipHeight = hum and hum.HipHeight or 2.0
			endPos = Vector3.new(endPos.X, groundRay.Position.Y + (rootPart.Size.Y * 0.5) + hipHeight, endPos.Z)
		end

		if char ~= player.Character then
			-- Replicated for other players
			spawnRangerDashAfterimages(char, origin, endPos, flatDir)
			playRangerVerdantSlashVFX(char, origin, endPos, flatDir, actualDist)
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
		playMissileBuffVFX(char)
	elseif skillIndex == 4 then
		makeRangerArrow(baseOrigin, Vector3.new(0, 0, -1), 0.1, Color3.fromRGB(185, 255, 145), 0.4, 0.08)
		local center = targetPosition or (origin + flatUnit(lookDir) * 42)
		local casterP = Players:GetPlayerFromCharacter(char)
		local sizeScale = math.max(0.4, (casterP and casterP:GetAttribute("Stat_size")) or 1.0)
		local marker = Instance.new("Model")
		marker.Name = "RainOfArrowsRing"
		marker.Parent = Workspace.Terrain

		-- Perimeter-only indicator ring (hollow center, nothing filling the area)
		local RING_SEGMENTS = 48
		local ringRadius = 18 * sizeScale
		local segLen = (2 * math.pi * ringRadius) / RING_SEGMENTS
		local ringColor = Color3.fromRGB(95, 215, 115)
		for s = 1, RING_SEGMENTS do
			local ang = (s / RING_SEGMENTS) * math.pi * 2
			local px = center.X + math.cos(ang) * ringRadius
			local pz = center.Z + math.sin(ang) * ringRadius
			local seg = Instance.new("Part")
			seg.Name = "RingSeg"
			seg.Size = Vector3.new(0.6, 0.18, segLen * 1.12)
			seg.Material = Enum.Material.Neon
			seg.Color = ringColor
			seg.Transparency = 0.3
			seg.CanCollide = false
			seg.CanTouch = false
			seg.CanQuery = false
			seg.Anchored = true
			seg.CFrame = CFrame.lookAt(Vector3.new(px, center.Y + 0.08, pz), Vector3.new(px, center.Y + 0.08, pz) + Vector3.new(-math.sin(ang), 0, math.cos(ang)))
			seg.Parent = marker
		end

		-- Spawn the vine arena cage around the drop zone
		spawnVineArenaCage(center, 18 * sizeScale, 5.2)

		task.delay(1.05, function()
			for i = 1, 70 do
				task.delay(i * 0.035, function()
					local angle = math.random() * math.pi * 2
					local dist = math.sqrt(math.random()) * 18 * sizeScale
					local ground = center + Vector3.new(math.cos(angle) * dist, 0, math.sin(angle) * dist)
					makeRangerArrow(ground + Vector3.new(0, 38, 0), Vector3.new(0, -1, 0), 38, i % 4 == 0 and POISON_PURPLE or NATURE_GREEN, 0.18, 0.18)
				end)
			end
		end)
		task.delay(5.2, function()
			if marker and marker.Parent then
				for _, mp in ipairs(marker:GetChildren()) do
					if mp:IsA("BasePart") then
						TweenService:Create(mp, TweenInfo.new(0.35), { Transparency = 1 }):Play()
					end
				end
				Debris:AddItem(marker, 0.4)
			end
		end)
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleric Ultimate: Divine Ascent VFX (angelic wings, sky pillar, holy judgment)
-- ─────────────────────────────────────────────────────────────────────────────
local playDivineAscentCamera: (Model, Vector3, number) -> ()

local HOLY_IVORY = Color3.fromRGB(255, 250, 238)
local HOLY_WHITE = Color3.fromRGB(255, 243, 212)
local HOLY_GOLD = Color3.fromRGB(255, 206, 112)
local HOLY_GOLD_DEEP = Color3.fromRGB(233, 170, 64)
local HOLY_RAY_TEXTURE = 'rbxassetid://1053548563'
local HEAL_GREEN = Color3.fromRGB(110, 245, 140)

-- LAYOUT CONTRACT
--   A Roblox character faces along -Z (LookVector), so 'behind the back' is
--   local +Z. Every wing / halo / body VFX part goes through behindCF(), which
--   clamps local Z to >= 0.75 studs. Wings are built from a BASE point and grow
--   away from it: the rotated long axis always gains Z, so no feather can ever
--   swing in front of the torso or head.
--
-- READABILITY CONTRACT
--   No light is parented to HumanoidRootPart (that lit him from the inside and
--   blew out the silhouette). Warm gold PointLights sit BEHIND him instead,
--   giving a golden rim light on a dark, readable body.
local function behindCF(rootPart: BasePart, x: number, y: number, z: number, rx: number?, ry: number?, rz: number?): CFrame
    local cf = rootPart.CFrame * CFrame.new(x, y, math.max(0.75, z))
    if rx or ry or rz then
        cf = cf * CFrame.Angles(rx or 0, ry or 0, rz or 0)
    end
    return cf
end

local function weldTo(part: BasePart, rootPart: BasePart)
    part.CanCollide = false
    part.CanTouch = false
    part.CanQuery = false
    part.Massless = true
    part.CastShadow = false
    local w = Instance.new('WeldConstraint')
    w.Part0 = rootPart
    w.Part1 = part
    w.Parent = part
    part.Anchored = false
end

local function newHolyRayEmitter(parent: Instance, rate: number, size: number, speed: number, color: Color3): ParticleEmitter
    local pe = Instance.new('ParticleEmitter')
    pe.Name = 'HolyRay'
    pe.Texture = HOLY_RAY_TEXTURE
    pe.Color = ColorSequence.new(color)
    pe.LightEmission = 1
    pe.LightInfluence = 0
    pe.Rate = rate
    pe.Lifetime = NumberRange.new(0.4, 0.9)
    pe.Speed = NumberRange.new(speed * 0.5, speed * 1.2)
    pe.SpreadAngle = Vector2.new(18, 18)
    pe.EmissionDirection = Enum.NormalId.Top
    pe.Size = NumberSequence.new({
        NumberSequenceKeypoint.new(0, size * 0.25),
        NumberSequenceKeypoint.new(0.35, size),
        NumberSequenceKeypoint.new(1, 0.05),
    })
    pe.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 0.15),
        NumberSequenceKeypoint.new(0.7, 0.4),
        NumberSequenceKeypoint.new(1, 1),
    })
    pe.Parent = parent
    return pe
end

local function buildDivineWings(char: Model, rootPart: BasePart): (Folder, { BasePart })
    local folder = Instance.new('Folder')
    folder.Name = 'DivineAscentWings'
    folder.Parent = char
    -- Weld the wings to the TORSO (not the root) so they follow the torso through
    -- the ultimate's animation instead of staying fixed behind the root.
    local torsoRef = char:FindFirstChild('Torso')
    if not (torsoRef and torsoRef:IsA('BasePart')) then torsoRef = rootPart end

    local generalVFX = game:GetService('ReplicatedStorage'):FindFirstChild('generalVFX')
    local template = generalVFX and generalVFX:FindFirstChild('Wings')

    if template and template:IsA('BasePart') then
        local meshWings = template:Clone()
        meshWings.Name = 'AngelWings'
        meshWings.CanCollide = false
        meshWings.CanTouch = false
        meshWings.CanQuery = false
        meshWings.Massless = true
        meshWings.CastShadow = false
        meshWings.Anchored = false
        meshWings.Material = Enum.Material.Neon
        meshWings.Color = Color3.fromRGB(255, 246, 224)
        meshWings.Transparency = 0.04
        meshWings.CFrame = behindCF(torsoRef, 0, 4.05, 1.15)
        meshWings.Parent = folder

        local snd = meshWings:FindFirstChildOfClass('Sound')
        if snd then snd:Destroy() end

        local mesh = meshWings:FindFirstChildOfClass('SpecialMesh')
        if mesh then
            mesh.TextureId = ''
            mesh.VertexColor = Vector3.new(1, 1, 1)
            local fullScale = mesh.Scale * 1.35
            mesh.Scale = Vector3.new(0.06, 0.06, 0.06)
            TweenService:Create(mesh, TweenInfo.new(0.55, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = fullScale }):Play()
        end

        weldTo(meshWings, torsoRef)

        -- Golden rim glow behind the feather plane so the silhouette pops.
        local glow = Instance.new('Part')
        glow.Name = 'WingBackGlow'
        glow.Size = Vector3.new(6.8, 4.4, 0.2)
        glow.Material = Enum.Material.Neon
        glow.Color = HOLY_GOLD
        glow.Transparency = 0.87
        glow.CFrame = behindCF(torsoRef, 0, 4.15, 1.42)
        glow.Parent = folder
        weldTo(glow, torsoRef)

        -- Rising holy motes across the span of the wings.
        for _, mx in ipairs({ -3.0, -1.5, 0, 1.5, 3.0 }) do
            local att = Instance.new('Attachment')
            att.Name = 'WingMote'
            att.CFrame = CFrame.new(mx, math.abs(mx) * 0.35, 0.15)
            att.Parent = glow
            local pe = newHolyRayEmitter(att, 8, 1.6, 3, (mx == 0) and HOLY_GOLD or HOLY_IVORY)
            pe.SpreadAngle = Vector2.new(38, 38)
            pe.Lifetime = NumberRange.new(0.8, 1.6)
        end
    end

    local parts: { BasePart } = {}
    for _, d in ipairs(folder:GetDescendants()) do
        if d:IsA('BasePart') then table.insert(parts, d) end
    end
    return folder, parts
end

local function buildDivineHalo(char: Model, rootPart: BasePart): Model
    local halo = Instance.new('Model')
    halo.Name = 'DivineHalo'
    halo.Parent = char

    local RING_N = 16
    local R = 1.95
    local Y = 1.6
    local Z = 1.05
    local chord = (2 * math.pi * R / RING_N) * 1.06
    for k = 1, RING_N do
        local ang = (k / RING_N) * math.pi * 2
        local seg = Instance.new('Part')
        seg.Name = 'HaloSeg'
        seg.Size = Vector3.new(0.14, chord, 0.2)
        seg.Material = Enum.Material.Neon
        seg.Color = HOLY_GOLD
        seg.Transparency = 0.08
        seg.CFrame = rootPart.CFrame * CFrame.new(math.cos(ang) * R, Y + math.sin(ang) * R, Z) * CFrame.Angles(0, 0, ang)
        seg.Parent = halo
        weldTo(seg, rootPart)
    end

    local glow = Instance.new('Part')
    glow.Name = 'HaloGlow'
    glow.Shape = Enum.PartType.Cylinder
    glow.Size = Vector3.new(0.08, R * 2.4, R * 2.4)
    glow.Material = Enum.Material.Neon
    glow.Color = HOLY_WHITE
    glow.Transparency = 0.84
    glow.CFrame = rootPart.CFrame * CFrame.new(0, Y, Z + 0.22) * CFrame.Angles(0, math.rad(90), 0)
    glow.Parent = halo
    weldTo(glow, rootPart)

    return halo
end

local function buildRimLights(char: Model, rootPart: BasePart): Folder
    local folder = Instance.new('Folder')
    folder.Name = 'DivineRimLights'
    folder.Parent = char

    local specs = {
        { x = 0, y = 2.2, z = 2.6, b = 2.4, r = 15, c = HOLY_WHITE },
        { x = -2.6, y = 1.6, z = 2.2, b = 1.4, r = 12, c = HOLY_GOLD },
        { x = 2.6, y = 1.6, z = 2.2, b = 1.4, r = 12, c = HOLY_GOLD },
    }
    for _, s in ipairs(specs) do
        local anchor = Instance.new('Part')
        anchor.Name = 'RimAnchor'
        anchor.Size = Vector3.new(0.2, 0.2, 0.2)
        anchor.Transparency = 1
        anchor.CFrame = behindCF(rootPart, s.x, s.y, s.z)
        anchor.Parent = folder
        weldTo(anchor, rootPart)
        local pl = Instance.new('PointLight')
        pl.Color = s.c
        pl.Brightness = s.b
        pl.Range = s.r
        pl.Shadows = false
        pl.Parent = anchor
    end
    return folder
end

local function buildGroundSeal(origin: Vector3, groundY: number, radius: number, holder: Instance): Model
    local seal = Instance.new('Model')
    seal.Name = 'DivineGroundSeal'
    seal.Parent = holder

    local baseY = groundY + 0.06

    local function ring(ringRadius, segCount, thickness, height, color, transparency)
        local chord = (2 * math.pi * ringRadius / segCount) * 1.35
        for k = 1, segCount do
            local ang = (k / segCount) * math.pi * 2
            local px = origin.X + math.cos(ang) * ringRadius
            local pz = origin.Z + math.sin(ang) * ringRadius
            local seg = Instance.new('Part')
            seg.Name = 'SealSeg'
            seg.Size = Vector3.new(thickness, height, chord)
            seg.Material = Enum.Material.Neon
            seg.Color = color
            seg.Transparency = transparency
            seg.CanCollide = false
            seg.CanTouch = false
            seg.CanQuery = false
            seg.CastShadow = false
            seg.Anchored = true
            seg.CFrame = CFrame.lookAt(Vector3.new(px, baseY, pz), Vector3.new(px, baseY, pz) + Vector3.new(-math.sin(ang), 0, math.cos(ang)))
            seg.Parent = seal
        end
    end

    ring(radius, 48, 0.75, 0.22, HOLY_GOLD, 0.2)
    ring(radius * 0.66, 36, 0.45, 0.18, HOLY_WHITE, 0.35)
    ring(radius * 0.34, 24, 0.4, 0.16, HOLY_GOLD, 0.3)

    for k = 1, 8 do
        local ang = (k / 8) * math.pi * 2
        local midR = radius * 0.5
        local spoke = Instance.new('Part')
        spoke.Name = 'SealSpoke'
        spoke.Size = Vector3.new(0.35, 0.14, radius * 0.33)
        spoke.Material = Enum.Material.Neon
        spoke.Color = HOLY_IVORY
        spoke.Transparency = 0.4
        spoke.CanCollide = false
        spoke.CanTouch = false
        spoke.CanQuery = false
        spoke.CastShadow = false
        spoke.Anchored = true
        local sp = Vector3.new(origin.X + math.cos(ang) * midR, baseY, origin.Z + math.sin(ang) * midR)
        spoke.CFrame = CFrame.lookAt(sp, sp + Vector3.new(math.cos(ang), 0, math.sin(ang)))
        spoke.Parent = seal
    end

    return seal
end

local function spawnHolyCross(parent: Instance, baseCF: CFrame, scale: number, riseTime: number, color: Color3)
    local model = Instance.new('Model')
    model.Name = 'HolyCross'

    local pieces = {}
    local function makePiece(size: Vector3, offset: CFrame)
        local p = Instance.new('Part')
        p.Size = size
        p.Material = Enum.Material.Neon
        p.Color = color
        p.Transparency = 0.1
        p.CanCollide = false
        p.CanTouch = false
        p.CanQuery = false
        p.CastShadow = false
        p.Anchored = true
        p.CFrame = baseCF * offset
        p.Parent = model
        table.insert(pieces, { part = p, base = baseCF * offset })
    end

    makePiece(Vector3.new(0.16 * scale, 1.1 * scale, 0.12 * scale), CFrame.new(0, 0, 0))
    makePiece(Vector3.new(0.7 * scale, 0.16 * scale, 0.12 * scale), CFrame.new(0, 0.22 * scale, 0))

    model.Parent = parent

    task.spawn(function()
        local t0 = os.clock()
        while os.clock() - t0 < riseTime do
            if not model.Parent then return end
            local a = (os.clock() - t0) / riseTime
            local fade = a < 0.22 and (a / 0.22) or (1 - (a - 0.22) / 0.78)
            local tr = math.clamp(1 - fade, 0, 1)
            local rise = a * 5.0
            local wobble = math.sin(a * math.pi * 4) * 0.3
            for _, rec in ipairs(pieces) do
                rec.part.Transparency = tr
                rec.part.CFrame = rec.base + Vector3.new(wobble, rise, 0)
            end
            RunService.RenderStepped:Wait()
        end
        model:Destroy()
    end)
end

local function playDivineAscentVFX(char: Model, origin: Vector3, lookDir: Vector3, config: any)
    local rootPart = char:FindFirstChild('HumanoidRootPart') :: BasePart?
    local humanoid = char:FindFirstChildOfClass('Humanoid')
    if not rootPart or not humanoid then return end

    local isLocalCaster = (char == player.Character)
    local ssPlayer = Players:GetPlayerFromCharacter(char)
    local sizeScale = math.max(0.4, (ssPlayer and ssPlayer:GetAttribute('Stat_size')) or 1.0)
    local radius = (config and config.range or 30) * sizeScale
    local duration = (config and config.duration or 8.0)

    local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z)
    if flatLook.Magnitude < 0.001 then flatLook = rootPart.CFrame.LookVector end
    flatLook = Vector3.new(flatLook.X, 0, flatLook.Z).Unit
    local backDir = -flatLook

    -- Find the actual ground under him so the seal sits beneath his FEET.
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = { char }
    rayParams.IgnoreWater = true
    local groundY = origin.Y - 3
    local hit = Workspace:Raycast(origin + Vector3.new(0, 6, 0), Vector3.new(0, -60, 0), rayParams)
    -- Clean up any existing Divine Ascent VFX attachments/folders from a previous cast
    for _, child in ipairs(char:GetChildren()) do
        if child.Name == "DivineAscentWings" or child.Name == "DivineHalo" or child.Name == "DivineRimLights" then
            child:Destroy()
        end
    end
    for _, att in ipairs(rootPart:GetChildren()) do
        if att.Name == "DivineMotes" then
            att:Destroy()
        end
    end

    local worldHolder = Instance.new('Folder')
    worldHolder.Name = 'DivineAscentWorldVFX'
    worldHolder.Parent = Workspace.Terrain

    local wingsFolder = buildDivineWings(char, rootPart)
    local halo = buildDivineHalo(char, rootPart)
    buildRimLights(char, rootPart)

    -- Raised to the party's float level so the holy seal travels with the ult
    -- tableau (caster lifted to +159, allies float at +171).
    local seal = buildGroundSeal(origin, origin.Y + 150, radius, worldHolder)

    -- Holy radiance, reusing generalVFX.Holy as the light-ray source, placed above the head.
    local radianceFolder = Instance.new('Folder')
    radianceFolder.Name = 'DivineRadiance'
    radianceFolder.Parent = worldHolder

    local ReplicatedStorage = game:GetService('ReplicatedStorage')
    local generalVFX = ReplicatedStorage:FindFirstChild('generalVFX')
    local holyTemplate = generalVFX and generalVFX:FindFirstChild('Holy')

    if holyTemplate then
        local clone = holyTemplate:Clone()
        clone.Name = 'DivineRadiance'
        clone.CanCollide = false
        clone.CanTouch = false
        clone.CanQuery = false
        clone.CastShadow = false
        clone.Transparency = 1
        clone.Size = Vector3.new(12, 12, 12)
        clone.CFrame = rootPart.CFrame * CFrame.new(0, 2.9, 0.4)
        clone.Parent = radianceFolder
        local w = Instance.new('WeldConstraint')
        w.Part0 = rootPart
        w.Part1 = clone
        w.Parent = clone
        clone.Anchored = false
        for _, d in ipairs(clone:GetDescendants()) do
            if d:IsA('ParticleEmitter') then
                d.Rate = math.clamp(d.Rate * 0.25, 6, 30)
                d.Color = ColorSequence.new(HOLY_GOLD)
                d.LightEmission = 1
                d.LightInfluence = 0
                d.Size = NumberSequence.new(13)
            end
        end
    end

    -- Small floating crosses rising all around the celestial tableau
    local crossHolder = Instance.new('Folder')
    crossHolder.Name = 'DivineCrosses'
    crossHolder.Parent = worldHolder

    for k = 1, 24 do
        task.delay(k * 0.15, function()
            if not crossHolder.Parent or not rootPart.Parent then return end
            local side = (k % 2 == 0) and 1 or -1
            local spread = 1.6 + math.random() * 5.0
            local cf = behindCF(rootPart, side * spread, 0.8 + math.random() * 3.6, 1.1 + math.random() * 2.5)
            spawnHolyCross(crossHolder, cf, 1.1 + math.random() * 0.6, 2.5 + math.random() * 1.5,
                (k % 3 == 0) and HOLY_WHITE or HOLY_GOLD)
        end)
    end

    -- Holy motes drifting up around the wings.
    local moteAtt = Instance.new('Attachment')
    moteAtt.Name = 'DivineMotes'
    moteAtt.CFrame = CFrame.new(0, 1.6, 1.3)
    moteAtt.Parent = rootPart
    local motePE = newHolyRayEmitter(moteAtt, 48, 2.8, 6, HOLY_WHITE)
    motePE.SpreadAngle = Vector2.new(80, 80)
    motePE.Lifetime = NumberRange.new(1.2, 2.5)

    if isLocalCaster then
        triggerFOVPunch(6, 0.5)
    end

    -- Cast burst placed BEHIND the shoulders
    local burstAtt = Instance.new('Attachment')
    burstAtt.CFrame = CFrame.new(0, 1.7, 2.0)
    burstAtt.Parent = rootPart
    local burstPE = newHolyRayEmitter(burstAtt, 0, 5, 22, HOLY_GOLD)
    burstPE.SpreadAngle = Vector2.new(180, 180)
    burstPE:Emit(72)
    Debris:AddItem(burstAtt, 1.5)

    task.delay(duration, function()
        if wingsFolder then
            for _, d in ipairs(wingsFolder:GetDescendants()) do
                if d:IsA('BasePart') then
                    TweenService:Create(d, TweenInfo.new(0.7), { Transparency = 1 }):Play()
                end
            end
            Debris:AddItem(wingsFolder, 0.9)
        end
        if halo then
            for _, d in ipairs(halo:GetDescendants()) do
                if d:IsA('BasePart') then
                    TweenService:Create(d, TweenInfo.new(0.7), { Transparency = 1 }):Play()
                end
            end
            Debris:AddItem(halo, 0.9)
        end
        local rim = char:FindFirstChild('DivineRimLights')
        if rim then
            for _, d in ipairs(rim:GetDescendants()) do
                if d:IsA('PointLight') then
                    TweenService:Create(d, TweenInfo.new(0.6), { Brightness = 0 }):Play()
                end
            end
            Debris:AddItem(rim, 0.9)
        end
        if radianceFolder then
            for _, d in ipairs(radianceFolder:GetDescendants()) do
                if d:IsA('ParticleEmitter') then d.Enabled = false end
            end
            Debris:AddItem(radianceFolder, 1.0)
        end
        if motePE then motePE.Enabled = false end
        if moteAtt and moteAtt.Parent then Debris:AddItem(moteAtt, 1.2) end
        for _, container in ipairs({ seal }) do
            if container then
                for _, d in ipairs(container:GetDescendants()) do
                    if d:IsA('BasePart') then
                        TweenService:Create(d, TweenInfo.new(0.8), { Transparency = 1 }):Play()
                    elseif d:IsA('ParticleEmitter') then
                        d.Enabled = false
                    end
                end
            end
        end
        Debris:AddItem(worldHolder, 1.8)
    end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleric Basic Combat VFX: Light Attack, Divine Touch (Heal), Divine Beam (Laser)
-- ─────────────────────────────────────────────────────────────────────────────
local function findGeneralVFX(name: string): Instance?
	local rs = game:GetService("ReplicatedStorage")
	local g = rs:FindFirstChild("generalVFX") or rs:FindFirstChild("GeneralVFX")
	if not g then return nil end
	for _, c in ipairs(g:GetChildren()) do
		if string.lower(c.Name) == string.lower(name) then return c end
	end
	return nil
end

-- 1) NORMAL ATTACK: reuse generalVFX["Light attack"], swept along the swing arc.
local function playClericBasicAttackVFX(char: Model, lookDir: Vector3)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end
	local flatDir = flatUnit(lookDir)
	if flatDir.Magnitude < 0.001 then flatDir = flatUnit(rootPart.CFrame.LookVector) end

	local template = findGeneralVFX("Light attack")
	if not template or not template:IsA("BasePart") then return end

	local slash = template:Clone()
	slash.Name = "ClericLightAttack"
	slash.Anchored = true
	slash.CanCollide = false
	slash.CanTouch = false
	slash.CanQuery = false
	slash.CastShadow = false
	slash.Transparency = 1
	slash.Color = Color3.fromRGB(255, 248, 226)
	slash.Material = Enum.Material.Neon

	local origin = rootPart.Position + Vector3.new(0, 0.4, 0) + flatDir * 2.3
	slash.CFrame = CFrame.lookAt(origin, origin + flatDir)

	-- Reuse its star emitters but keep them thin and short-lived.
	for _, d in ipairs(slash:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = true
			d.Rate = math.clamp(d.Rate * 0.3, 6, 24)
			d.Color = ColorSequence.new(Color3.fromRGB(255, 246, 220))
			d.LightEmission = 1
			d.LightInfluence = 0
			d.Lifetime = NumberRange.new(0.12, 0.3)
			d.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.5),
				NumberSequenceKeypoint.new(1, 0.1),
			})
		end
	end

	-- Thin glowing arc that sweeps with the swing.
	local ARC_SEG = 9
	for k = 1, ARC_SEG do
		local t = (k - 1) / (ARC_SEG - 1)
		local seg = Instance.new("Part")
		seg.Name = "SlashArc"
		seg.Size = Vector3.new(0.12, 1.5, 0.5)
		seg.Material = Enum.Material.Neon
		seg.Color = (k % 2 == 0) and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(255, 214, 130)
		seg.Transparency = 0.2
		seg.Anchored = false
		seg.CanCollide = false
		seg.CanTouch = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.Massless = true
		seg.CFrame = slash.CFrame * CFrame.new(0, -0.5 + t * 1.0, (t - 0.5) * 2.4)
		seg.Parent = slash
		local wc = Instance.new("WeldConstraint")
		wc.Part0 = slash
		wc.Part1 = seg
		wc.Parent = seg
	end

	slash.Parent = Workspace.Terrain

	local travelStart = slash.CFrame
	local travelEnd = CFrame.lookAt(origin + flatDir * 60, origin + flatDir * 61)

	task.spawn(function()
		local t0 = os.clock()
		local LIFE = 0.22
		while slash.Parent do
			local a = math.clamp((os.clock() - t0) / LIFE, 0, 1)
			slash.CFrame = travelStart:Lerp(travelEnd, a)
			for _, d in ipairs(slash:GetDescendants()) do
				if d:IsA("ParticleEmitter") then
					d.Enabled = a < 0.85
				end
			end
			if a >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		slash:Destroy()
	end)

	-- A few small holy particles at the impact point.
	local sparkAtt = Instance.new("Attachment")
	sparkAtt.CFrame = CFrame.new(origin + flatDir * 1.6)
	sparkAtt.Parent = Workspace.Terrain
	local sparkPE = newHolyRayEmitter(sparkAtt, 0, 1.1, 5, HOLY_GOLD)
	sparkPE.SpreadAngle = Vector2.new(180, 180)
	sparkPE:Emit(7)
	Debris:AddItem(sparkAtt, 0.5)
end

-- 2) HEAL: Divine Touch (magic circle, crosses, particles, brief beam) at a world position.
local function playClericHealVFX(targetPos: Vector3)
	local holder = Instance.new("Folder")
	holder.Name = "ClericDivineTouch"
	holder.Parent = Workspace.Terrain

	local center = targetPos

	-- Ground magic circle
	local RING_N = 24
	local R = 3.0
	local chord = (2 * math.pi * R / RING_N) * 1.15
	for k = 1, RING_N do
		local ang = (k / RING_N) * math.pi * 2
		local px = center.X + math.cos(ang) * R
		local pz = center.Z + math.sin(ang) * R
		local seg = Instance.new("Part")
		seg.Name = "HealRing"
		seg.Size = Vector3.new(0.18, 0.16, chord)
		seg.Material = Enum.Material.Neon
		seg.Color = (k % 4 == 0) and Color3.fromRGB(255, 255, 255) or HEAL_GREEN
		seg.Transparency = 0.25
		seg.Anchored = true
		seg.CanCollide = false
		seg.CanTouch = false
		seg.CanQuery = false
		seg.CastShadow = false
		seg.CFrame = CFrame.lookAt(Vector3.new(px, center.Y - 2.6, pz), Vector3.new(px, center.Y - 2.6, pz) + Vector3.new(-math.sin(ang), 0, math.cos(ang)))
		seg.Parent = holder
	end

	-- Brief vertical beam of light
	local beam = Instance.new("Part")
	beam.Name = "HealBeam"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(13, 1.5, 1.5)
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(150, 255, 170)
	beam.Transparency = 0.62
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	beam.Parent = holder

	-- Rising particles
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, -2.2, 0)
	att.Parent = beam
	local pe = newHolyRayEmitter(att, 45, 1.9, 5, HEAL_GREEN)
	pe.SpreadAngle = Vector2.new(22, 22)
	pe.Lifetime = NumberRange.new(0.8, 1.6)

	-- Floating golden crosses
	for k = 1, 6 do
		task.delay(k * 0.12, function()
			if not holder.Parent then return end
			local ang = math.random() * math.pi * 2
			local rr = 1.1 + math.random() * 1.6
			local cf = CFrame.new(center + Vector3.new(math.cos(ang) * rr, -1.4 + math.random() * 2.4, math.sin(ang) * rr))
			spawnHolyCross(holder, cf, 0.65, 1.3, (k % 3 == 0) and Color3.fromRGB(255, 255, 255) or HEAL_GREEN)
		end)
	end

	task.delay(1.5, function()
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("BasePart") then
				TweenService:Create(d, TweenInfo.new(0.45), { Transparency = 1 }):Play()
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		Debris:AddItem(holder, 0.6)
	end)
end

-- 3) DIVINE BEAM: Holy Laser (white core, gold glow, rotating rings, travelling particles)
local function playClericDivineBeamVFX(char: Model, origin: Vector3, direction: Vector3, range: number)
	local flatDir = flatUnit(direction)
	local rootPart = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if flatDir.Magnitude < 0.001 and rootPart then
		flatDir = flatUnit(rootPart.CFrame.LookVector)
	end

	local holder = Instance.new("Folder")
	holder.Name = "ClericDivineBeam"
	holder.Parent = Workspace.Terrain

	local length = math.max(8, range or 48)
	local muzzlePos = origin + Vector3.new(0, 1.2, 0)
	local rHand = char and (char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm"))
	local lHand = char and (char:FindFirstChild("LeftHand") or char:FindFirstChild("Left Arm"))
	if rHand and rHand:IsA("BasePart") then
		muzzlePos = rHand.Position
		if lHand and lHand:IsA("BasePart") then
			muzzlePos = (rHand.Position + lHand.Position) * 0.5
		end
	end
	local startPos = muzzlePos + flatDir * 1.6
	local midPos = startPos + flatDir * (length * 0.5)
	local beamBasis = CFrame.lookAt(midPos, midPos + flatDir) * CFrame.Angles(0, math.rad(90), 0)

	-- Warm gold outer glow
	local outer = Instance.new("Part")
	outer.Name = "BeamGlow"
	outer.Shape = Enum.PartType.Cylinder
	outer.Size = Vector3.new(length, 1.5, 1.5)
	outer.Material = Enum.Material.Neon
	outer.Color = HOLY_GOLD
	outer.Transparency = 0.55
	outer.Anchored = true
	outer.CanCollide = false
	outer.CanTouch = false
	outer.CanQuery = false
	outer.CastShadow = false
	outer.CFrame = beamBasis
	outer.Parent = holder

	-- Brilliant white core
	local core = Instance.new("Part")
	core.Name = "BeamCore"
	core.Shape = Enum.PartType.Cylinder
	core.Size = Vector3.new(length, 0.7, 0.7)
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 255, 255)
	core.Transparency = 0.12
	core.Anchored = true
	core.CanCollide = false
	core.CanTouch = false
	core.CanQuery = false
	core.CastShadow = false
	core.CFrame = beamBasis
	core.Parent = holder

	-- Muzzle flash + origin rings + particles
	local hub = Instance.new("Part")
	hub.Name = "BeamHub"
	hub.Size = Vector3.new(0.2, 0.2, 0.2)
	hub.Transparency = 1
	hub.Anchored = true
	hub.CanCollide = false
	hub.CanTouch = false
	hub.CanQuery = false
	hub.CastShadow = false
	hub.CFrame = CFrame.lookAt(startPos, startPos + flatDir) * CFrame.Angles(0, math.rad(90), 0)
	hub.Parent = holder

	local RING_R = 1.5
	for ringIdx, lx in ipairs({ 0.3, 1.2 }) do
		for k = 1, 12 do
			local ang = (k / 12) * math.pi * 2
			local seg = Instance.new("Part")
			seg.Name = "BeamRing"
			seg.Size = Vector3.new(0.12, 0.5, 0.12)
			seg.Material = Enum.Material.Neon
			seg.Color = (ringIdx == 1) and HOLY_IVORY or HOLY_GOLD
			seg.Transparency = 0.2
			seg.Anchored = false
			seg.CanCollide = false
			seg.CanTouch = false
			seg.CanQuery = false
			seg.CastShadow = false
			seg.Massless = true
			seg.CFrame = hub.CFrame * CFrame.new(lx, math.cos(ang) * RING_R, math.sin(ang) * RING_R)
			seg.Parent = holder
			local w = Instance.new("WeldConstraint")
			w.Part0 = hub
			w.Part1 = seg
			w.Parent = seg
		end
	end

	local muzzleAtt = Instance.new("Attachment")
	muzzleAtt.Parent = hub
	local muzzlePE = newHolyRayEmitter(muzzleAtt, 0, 1.8, 8, HOLY_WHITE)
	muzzlePE.SpreadAngle = Vector2.new(180, 180)
	muzzlePE:Emit(12)

	local flowAtt = Instance.new("Attachment")
	flowAtt.Parent = hub
	local flowPE = newHolyRayEmitter(flowAtt, 70, 1.3, 60, HOLY_WHITE)
	flowPE.SpreadAngle = Vector2.new(5, 5)
	flowPE.Speed = NumberRange.new(55, 85)
	flowPE.Lifetime = NumberRange.new(0.35, 0.6)
	flowPE.EmissionDirection = Enum.NormalId.Front

	-- Animate rings + fade out
	local LIFE = 0.42
	task.spawn(function()
		local t0 = os.clock()
		while holder.Parent do
			local a = math.clamp((os.clock() - t0) / LIFE, 0, 1)
			hub.CFrame = hub.CFrame * CFrame.Angles(math.rad(11), 0, 0)
			if a >= 1 then break end
			RunService.RenderStepped:Wait()
		end
		for _, d in ipairs(holder:GetDescendants()) do
			if d:IsA("BasePart") and d ~= hub then
				TweenService:Create(d, TweenInfo.new(0.25), { Transparency = 1 }):Play()
			elseif d:IsA("ParticleEmitter") then
				d.Enabled = false
			end
		end
		task.delay(0.3, function()
			if hub then hub.Transparency = 1 end
		end)
		Debris:AddItem(holder, 0.8)
	end)
end

-- Divine Ascent cinematic camera: low upward hero shot during the wing unfurl,
-- rising with the caster, then a wide divine-judgment pull-back. Mirrors the
-- reference art (low angle -> soaring ascension -> overhead radiance).
playDivineAscentCamera = function(char: Model, lookDir: Vector3, duration: number)
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return end

	local successIso, IsometricCamera = pcall(function()
		return require(script.Parent:WaitForChild("IsometricCamera"))
	end)
	local wasIsoActive = false
	if successIso and IsometricCamera and IsometricCamera.IsActive and IsometricCamera.IsActive() then
		wasIsoActive = true
		IsometricCamera.Pause()
	end

	local cam = Workspace.CurrentCamera
	cam.CameraType = Enum.CameraType.Scriptable

	local flatDir = Vector3.new(lookDir.X, 0, lookDir.Z)
	if flatDir.Magnitude < 0.001 then flatDir = rootPart.CFrame.LookVector end
	flatDir = Vector3.new(flatDir.X, 0, flatDir.Z).Unit

	local myToken = (divineCamToken or 0) + 1
	divineCamToken = myToken

	local function stillActive()
		return divineCamToken == myToken and char.Parent ~= nil
	end

	local function restore()
		if divineCamToken ~= myToken then return end
		if wasIsoActive and successIso and IsometricCamera then
			IsometricCamera.Resume(0.5)
		else
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = 70
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then cam.CameraSubject = hum end
		end
	end

	-- Ground probe so the lens can never sink through the floor plane.
	local groundParams = RaycastParams.new()
	groundParams.FilterType = Enum.RaycastFilterType.Exclude
	groundParams.FilterDescendantsInstances = { char }
	groundParams.IgnoreWater = true

	local function groundHeightAt(worldPos: Vector3): number?
		local hit = Workspace:Raycast(Vector3.new(worldPos.X, worldPos.Y + 60, worldPos.Z), Vector3.new(0, -400, 0), groundParams)
		if hit then return hit.Position.Y end
		return nil
	end

	task.spawn(function()
		cam.FieldOfView = 54
		local t0 = os.clock()
		local firstFrame = true
		local CS, CH = 1.0, 0.0 -- cutaway DISABLED (was 3.2): far cam flew into unstreamed darkness
		local cut = false
		local sc = Workspace:GetAttribute("ReviveStageCenter")
		local sv = Workspace:GetAttribute("ReviveStageView")
		while stillActive() do
			local e = os.clock() - t0
			if e >= duration then break end
			local rp = rootPart.Position
			local fc, cp, fv, sn
			if sc and sv and e >= CS and e < CS + CH then
				local k = (e - CS) / CH
				local sd = Vector3.new(-flatDir.Z, 0, flatDir.X)
				fc = sc + sv * 4 + Vector3.new(0, 3, 0)
				cp = sc + sd * (52 + k * 2) + Vector3.new(0, 12 + k, 0)
				fv = 56
				sn = not cut
				cut = true
			else
				if cut then firstFrame = true cut = false end
				local p = math.clamp(e / math.max(duration, 0.001), 0, 1)
				fv = 54 - p * 3
				fc = rp + Vector3.new(0, 1.8, 0)
				cp = rp + flatDir * (14.0 - p * 1.5) + Vector3.new(0, -3.5 + math.max(0, 1 - e / 0.45) * 2.5, 0)
			end
			local gy = groundHeightAt(cp)
			if gy then cp = Vector3.new(cp.X, math.max(cp.Y, gy + 1.5), cp.Z) end
			local tc = CFrame.lookAt(cp, fc)
			if firstFrame or sn then cam.CFrame = tc firstFrame = false
			else cam.CFrame = cam.CFrame:Lerp(tc, 0.35) end
			cam.FieldOfView = fv
			RunService.RenderStepped:Wait()
		end
		restore()
	end)
end














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
	if Workspace:GetAttribute("TomesPaused") == true then return end

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
	local skillTargetPosition = nil
	local skillAllyTarget = nil
	if classId == "ranger" and (skillIndex == 3 or skillIndex == 4) then
		skillTargetPosition = clampRangerCursorTarget(rootPart.Position, cursorPosition, config.range or 42, aimDir)
	elseif classId == "heavy_knight" and skillIndex == 2 then
		skillTargetPosition = clampRangerCursorTarget(rootPart.Position, cursorPosition, config.maxLeapDistance or 42, aimDir)
	elseif classId == "cleric" and skillIndex == 1 then
		-- Heal the ally under the cursor (if any) instead of the player.
		local hoveredAlly = AllyHover.getHoveredAlly()
		local hoveredRoot = hoveredAlly and (hoveredAlly:FindFirstChild("HumanoidRootPart") or hoveredAlly.PrimaryPart)
		if hoveredRoot then
			skillTargetPosition = hoveredRoot.Position
			skillAllyTarget = hoveredAlly.Name
		end
	end

	-- Pivot character towards aim direction smoothly
	local targetCF = CFrame.lookAt(rootPart.Position, rootPart.Position + aimDir)
	rootPart.CFrame = targetCF

	-- Set casting attribute & play skill animation
	char:SetAttribute("IsSkillCasting", true)

	if classId == "ranger" then
		if skillIndex == 1 then
			-- Skill 1: Verdant Slash (Instant Piercing Nature Dash)
			char:SetAttribute("AllowSkillMovement", false)
			local track = getSkillTrack(char, 1)
			if track then
				track.Priority = Enum.AnimationPriority.Action4
				track:Play(0.04)
				track:AdjustSpeed(2.4)
			end

			local origin = rootPart.Position
			local flatDir = flatUnit(aimDir)
			local dashDist = config.dashDistance or 32

			local rayParams = RaycastParams.new()
			rayParams.FilterType = Enum.RaycastFilterType.Exclude
			local ignoreList: { Instance } = { char }
			for _, desc in ipairs(Workspace:GetDescendants()) do
				if desc:IsA("Model") and (desc:FindFirstChildOfClass("Humanoid") or desc:FindFirstAncestorOfClass("Accessory")) then
					table.insert(ignoreList, desc)
				end
			end
			rayParams.FilterDescendantsInstances = ignoreList
			rayParams.IgnoreWater = true

			local forwardRay = Workspace:Raycast(origin + Vector3.new(0, 1.2, 0), flatDir * dashDist, rayParams)
			local actualDist = dashDist
			if forwardRay and forwardRay.Distance > 0 then
				actualDist = math.max(3.0, forwardRay.Distance - 1.5)
			end

			local endPos = origin + flatDir * actualDist
			local groundRay = Workspace:Raycast(endPos + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), rayParams)
			if groundRay then
				local hipHeight = humanoid.HipHeight or 2.0
				endPos = Vector3.new(endPos.X, groundRay.Position.Y + (rootPart.Size.Y * 0.5) + hipHeight, endPos.Z)
			end

			-- Spawn afterimage ghost silhouettes along the path
			spawnRangerDashAfterimages(char, origin, endPos, flatDir)

			-- Instant dash snap
			rootPart.CFrame = CFrame.lookAt(endPos, endPos + flatDir)
			rootPart.AssemblyLinearVelocity = Vector3.zero

			-- Camera shake for punchy tactile response
			triggerCameraShake(0.38, 0.2)

			task.delay(0.12, function()
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end)

			playRangerVerdantSlashVFX(char, origin, endPos, flatDir, actualDist)
		elseif skillIndex == 3 then
			-- Skill 3: Seeker Barrage (Missile Buff: instant cast buff, enables homing missile launches on every attack)
			char:SetAttribute("AllowSkillMovement", true)
			char:SetAttribute("IsSkillCasting", false)
			playMissileBuffVFX(char)
		else
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
			playRangerSkillVFX(char, skillIndex, rootPart.Position, aimDir, skillTargetPosition)
		end
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
		-- Skill 2: Fire Slam (High parabolic leap slam into fiery explosion)
		char:SetAttribute("AllowSkillMovement", false)
		local track = getSkillTrack(char, 2)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.06)
		end
		local slamTarget = skillTargetPosition or (rootPart.Position + aimDir * 28)
		local sizeMult = player:GetAttribute("Stat_size") or 1.0
		task.delay(0.80, function()
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end)
		playFireSlamVFX(char, rootPart.Position, slamTarget, sizeMult)
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
		end

		-- After the windup, play the big downward slash animation as the wave travels.
		task.delay(1.5, function()
			if not char or not char.Parent then return end
			local slashTrack = getSkillSlashTrack(char, 4)
			if slashTrack then
				slashTrack.Priority = Enum.AnimationPriority.Action4
				slashTrack:Play(0.06)
			end
		end)

		if track then
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
	elseif classId == "cleric" and skillIndex == 1 then
		-- Skill 1: Divine Touch (heal self or nearest low ally)
		char:SetAttribute("AllowSkillMovement", true)
		local track = getSkillTrack(char, 1)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.08)
		end
		task.delay(0.45, function()
			if char and char.Parent then
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end
		end)

		-- Heal VFX target: the hovered ally (the one showing the heal icon) if any, otherwise on us.
		local vfxPos: Vector3 = rootPart.Position
		local healTarget: Model? = AllyHover.getHoveredAlly()
		if healTarget then
			local hr = healTarget:FindFirstChild("HumanoidRootPart") or healTarget.PrimaryPart
			if hr then vfxPos = hr.Position end
		elseif skillTargetPosition then
			vfxPos = skillTargetPosition
		end
		playClericHealVFX(vfxPos)
	elseif classId == "cleric" and skillIndex == 2 then
		-- Skill 2: Divine Beam (holy laser channel)
		char:SetAttribute("AllowSkillMovement", false)
		local track = getSkillTrack(char, 2)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.06)
		end
		DivineBeamChannel.play(char, config.range or 48, config.duration or 5.0)
	elseif classId == "cleric" and skillIndex == 1 then
		-- Skill 1: Divine Touch (heal self or nearest low ally)
		char:SetAttribute("AllowSkillMovement", true)
		local track = getSkillTrack(char, 1)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.08)
		end
		task.delay(0.45, function()
			if char and char.Parent then
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end
		end)

		-- Pick the heal target: self, or the most-hurt nearby ally.
		local healTarget = char
		local bestFrac = 1.0
		local myHum = char:FindFirstChildOfClass("Humanoid")
		if myHum and myHum.MaxHealth > 0 then
			bestFrac = myHum.Health / myHum.MaxHealth
		end
		for _, other in ipairs(Players:GetPlayers()) do
			local oc = other.Character
			if oc and oc ~= char and oc.Parent then
				local oroot = oc:FindFirstChild("HumanoidRootPart")
				local ohum = oc:FindFirstChildOfClass("Humanoid")
				if oroot and ohum and ohum.Health > 0 and (oroot.Position - rootPart.Position).Magnitude <= 30 then
					local frac = ohum.Health / math.max(ohum.MaxHealth, 1)
					if frac < bestFrac then
						bestFrac = frac
						healTarget = oc
					end
				end
			end
		end
		local tRoot = healTarget:FindFirstChild("HumanoidRootPart") or healTarget.PrimaryPart
		if tRoot then
			playClericHealVFX(tRoot.Position)
		end
	elseif classId == "cleric" and skillIndex == 2 then
		-- Skill 2: Divine Beam (holy laser channel)
		char:SetAttribute("AllowSkillMovement", false)
		local track = getSkillTrack(char, 2)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.06)
		end
		DivineBeamChannel.play(char, config.range or 48, config.duration or 5.0)
	elseif classId == "cleric" and skillIndex == 1 then
		-- Skill 1: Divine Touch (heal self or nearest low ally)
		char:SetAttribute("AllowSkillMovement", true)
		local track = getSkillTrack(char, 1)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.08)
		end
		task.delay(0.45, function()
			if char and char.Parent then
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end
		end)

		-- Pick the heal target: self, or the most-hurt nearby ally.
		local healTarget = char
		local bestFrac = 1.0
		local myHum = char:FindFirstChildOfClass("Humanoid")
		if myHum and myHum.MaxHealth > 0 then
			bestFrac = myHum.Health / myHum.MaxHealth
		end
		for _, other in ipairs(Players:GetPlayers()) do
			local oc = other.Character
			if oc and oc ~= char and oc.Parent then
				local oroot = oc:FindFirstChild("HumanoidRootPart")
				local ohum = oc:FindFirstChildOfClass("Humanoid")
				if oroot and ohum and ohum.Health > 0 and (oroot.Position - rootPart.Position).Magnitude <= 30 then
					local frac = ohum.Health / math.max(ohum.MaxHealth, 1)
					if frac < bestFrac then
						bestFrac = frac
						healTarget = oc
					end
				end
			end
		end
		local tRoot = healTarget:FindFirstChild("HumanoidRootPart") or healTarget.PrimaryPart
		if tRoot then
			playClericHealVFX(tRoot.Position)
		end
	elseif classId == "cleric" and skillIndex == 2 then
		-- Skill 2: Divine Beam (holy laser channel)
		char:SetAttribute("AllowSkillMovement", false)
		local track = getSkillTrack(char, 2)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.06)
		end
		DivineBeamChannel.play(char, config.range or 48, config.duration or 5.0)
	elseif classId == "cleric" and skillIndex == 1 then
		-- Skill 1: Divine Touch (heal self or nearest low ally)
		char:SetAttribute("AllowSkillMovement", true)
		local track = getSkillTrack(char, 1)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.08)
		end
		task.delay(0.45, function()
			if char and char.Parent then
				char:SetAttribute("IsSkillCasting", false)
				char:SetAttribute("AllowSkillMovement", false)
			end
		end)

		-- Pick the heal target: self, or the most-hurt nearby ally.
		local healTarget = char
		local bestFrac = 1.0
		local myHum = char:FindFirstChildOfClass("Humanoid")
		if myHum and myHum.MaxHealth > 0 then
			bestFrac = myHum.Health / myHum.MaxHealth
		end
		for _, other in ipairs(Players:GetPlayers()) do
			local oc = other.Character
			if oc and oc ~= char and oc.Parent then
				local oroot = oc:FindFirstChild("HumanoidRootPart")
				local ohum = oc:FindFirstChildOfClass("Humanoid")
				if oroot and ohum and ohum.Health > 0 and (oroot.Position - rootPart.Position).Magnitude <= 30 then
					local frac = ohum.Health / math.max(ohum.MaxHealth, 1)
					if frac < bestFrac then
						bestFrac = frac
						healTarget = oc
					end
				end
			end
		end
		local tRoot = healTarget:FindFirstChild("HumanoidRootPart") or healTarget.PrimaryPart
		if tRoot then
			playClericHealVFX(tRoot.Position)
		end
	elseif classId == "cleric" and skillIndex == 2 then
		-- Skill 2: Divine Beam (holy laser channel)
		char:SetAttribute("AllowSkillMovement", false)
		local track = getSkillTrack(char, 2)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.06)
		end
		DivineBeamChannel.play(char, config.range or 48, config.duration or 5.0)
	elseif classId == "cleric" and skillIndex == 3 then
		-- Skill 3: Radiant Ground (instant holy burst)
		char:SetAttribute("AllowSkillMovement", true)
		char:SetAttribute("IsSkillCasting", false)
		local track = getSkillTrack(char, 3)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.08)
		end
		ClericVFX.playRadiantGround(rootPart.Position, (config.range or 16) * (config.areaMultiplier or 1))
	elseif classId == "cleric" and skillIndex == 4 then
		-- Ultimate: Divine Ascent (angelic ascension, heal + holy judgment)
		char:SetAttribute("AllowSkillMovement", false)
		local track = getSkillTrack(char, 4)
		if track then
			track.Priority = Enum.AnimationPriority.Action4
			track:Play(0.08)
		end
		local duration = config.duration or 8.0
		task.delay(duration, function()
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end)
		playDivineAscentVFX(char, rootPart.Position, aimDir, config)
		if char == player.Character then
			DivineAscentCutscene.Play(duration, aimDir)
		end
	end

	-- Fire Server Remote
	pcall(function()
		local useSkillRemote = Network.GetRemoteEvent(Network.Remotes.UseSkill)
		useSkillRemote:FireServer({
			skillIndex = skillIndex,
			origin = rootPart.Position,
			direction = aimDir,
			targetPosition = skillTargetPosition,
			allyTarget = skillAllyTarget,
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
	if Workspace:GetAttribute("TomesPaused") == true then return end
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
		local selClass = player:GetAttribute("SelectedClass")
		if selClass == "ranger" then
			playRangerShootAnimation(char)
		elseif selClass == "cleric" then
			playClericBasicAttackVFX(char, aimDir)
		end
	end

	if char:GetAttribute("IsMissileBuffActive") == true then
		SkillController.LaunchMissile(char)
	end

	-- Fire server Remote for basic attack damage
	local performAttackRemote = Network.GetRemoteEvent(Network.Remotes.PerformAttack)
	performAttackRemote:FireServer({ direction = aimDirection })
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
			local landingPos = payload.targetPosition or (origin + direction * 28)
			playFireSlamVFX(char, origin, landingPos, payload.areaMultiplier)
		elseif classId == "heavy_knight" and skillIndex == 3 then
			playPhoenixDashVFX(char, origin, direction)
		elseif classId == "heavy_knight" and skillIndex == 4 then
			playInfernalWrathVFX(char, origin, direction)
 elseif classId == "cleric" and skillIndex == 1 then
  playClericHealVFX(payload.targetPosition or origin)
 elseif classId == "cleric" and skillIndex == 2 then
  DivineBeamChannel.play(char, payload.range or 48, 5.0)
 elseif classId == "cleric" and skillIndex == 3 then
  ClericVFX.playRadiantGround(origin, 16 * (payload.areaMultiplier or 1))
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
