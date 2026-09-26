--!strict
-- DivineAscentCutscene.luau
-- Cinematic cutscene for the Cleric ultimate (Divine Ascent).
-- Replicates a heavenly celestial realm: massive golden orbital rings at
-- multiple tilted angles, dense volumetric golden cloud ocean, colossal
-- divine light pillars, radiating golden ground streaks, floating debris,
-- holy bridge tether, and dense sparkle/star particles everywhere.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DivineAscentCutscene = {}
local token = 0

-- ── Color palette ────────────────────────────────────────────────────────────
local HOLY_IVORY  = Color3.fromRGB(255, 252, 242)
local HOLY_GOLD   = Color3.fromRGB(255, 200, 80)
local HOLY_AMBER  = Color3.fromRGB(255, 175, 50)
local HOLY_WARM   = Color3.fromRGB(255, 235, 175)
local HOLY_WHITE  = Color3.fromRGB(255, 255, 245)
local CLOUD_DEEP  = Color3.fromRGB(200, 155, 90)
local CLOUD_MID   = Color3.fromRGB(240, 190, 120)
local CLOUD_LIGHT = Color3.fromRGB(255, 230, 170)
local HOLY_RAY_TEXTURE = "rbxassetid://1053548563"

-- ── Camera framing tuning ────────────────────────────────────────────────────
local CLERIC_POSE_ID = "rbxassetid://82203027084666"
local clericAnimation = Instance.new("Animation")
clericAnimation.Name = "DivineAscentClericPose"
clericAnimation.AnimationId = CLERIC_POSE_ID
pcall(function()
	ContentProvider:PreloadAsync({ clericAnimation })
end)
local clericTrack = nil

local CAM_NEAR = 16
local CAM_FAR  = 32
local CAM_HEIGHT = -2.5 -- very low angle looking UP into the celestial realm
local CAM_FOV = 56

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function getIso()
	local ok, iso = pcall(function()
		return require(script.Parent:WaitForChild("IsometricCamera"))
	end)
	if ok then return iso end
	return nil
end

-- ── UltAtmosphere: clone from generalVFX and float above the camera ──
local function spawnUltAtmosphere(): Instance?
	local gv = ReplicatedStorage:FindFirstChild("generalVFX")
	local src = gv and gv:FindFirstChild("UltAtmosphere")
	if not src then return nil end
	local atmo = src:Clone()
	atmo.Name = "DA_UltAtmosphere"
	if atmo:IsA("BasePart") then
		atmo.Anchored = true
		atmo.CanCollide = false
		atmo.CanTouch = false
		atmo.CanQuery = false
		atmo.CastShadow = false
	elseif atmo:IsA("Model") then
		for _, p in ipairs(atmo:GetDescendants()) do
			if p:IsA("BasePart") then
				p.Anchored = true
				p.CanCollide = false
				p.CanTouch = false
				p.CanQuery = false
				p.CastShadow = false
			end
		end
	end
	-- Enable any particle emitters inside
	for _, d in ipairs(atmo:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = true
		end
	end
	atmo.Parent = Workspace.Terrain
	return atmo
end

local function positionAtmosphereAboveCamera(atmo: Instance)
	if not atmo or not atmo.Parent then return end
	local camCF = camera.CFrame
	local aboveCF = camCF * CFrame.new(0, 35, 0)
	if atmo:IsA("BasePart") then
		atmo.CFrame = aboveCF
	elseif atmo:IsA("Model") then
		atmo:PivotTo(aboveCF)
	end
end

local function restoreJoints(char: Model)
	local torso = char:FindFirstChild("Torso")
	if not torso then return end
	for _, side in ipairs({ "Right", "Left" }) do
		local joint = torso:FindFirstChild(side .. " Shoulder")
		if joint and joint:IsA("Motor6D") then
			local base = joint:GetAttribute("BaseC0")
			if base then joint.C0 = base end
		end
	end
	local nk = torso:FindFirstChild("Neck")
	if nk and nk:IsA("Motor6D") then
		local base = nk:GetAttribute("BaseC0")
		if base then nk.C0 = base end
	end
end

local function setCasterAnimate(char: Model, disabled: boolean)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator and disabled then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BaseScript") and d.Name == "AnimationController" then
			d.Disabled = disabled
		end
	end
end

local function poseAngel(char: Model, _targetPos: Vector3?)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	if not clericTrack then
		local anim = Instance.new("Animation")
		anim.AnimationId = CLERIC_POSE_ID
		local ok, t = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not t then return end
		clericTrack = t
		clericTrack.Looped = true
		clericTrack.Priority = Enum.AnimationPriority.Action4
	end
	if not clericTrack.IsPlaying then
		clericTrack:Play(0, 1, 1)
		clericTrack.TimePosition = 0
	end
end

local function allyCenter(minY: number?): (Vector3?, number)
	local folder = Workspace:FindFirstChild("Allies")
	local sum, n = Vector3.zero, 0
	if folder then
		for _, a in ipairs(folder:GetChildren()) do
			if a:IsA("Model") and a:GetAttribute("IsAlly") == true then
				local r = a:FindFirstChild("HumanoidRootPart")
				if r and r:IsA("BasePart") then
					if not minY or r.Position.Y >= minY then
						sum += r.Position
						n += 1
					end
				end
			end
		end
	end
	if n > 0 then return sum / n, n end
	return nil, 0
end

-- Quick neon part factory
local function neonPart(name: string, size: Vector3, color: Color3, trans: number, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = trans
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 1. DENSE GOLDEN CLOUD OCEAN (eliminates the black void below the horizon)
-- ══════════════════════════════════════════════════════════════════════════════
local function buildCloudOcean(center: Vector3): Folder
	local h = Instance.new("Folder")
	h.Name = "DA_CloudOcean"
	h.Parent = Workspace.Terrain

	local floorY = center.Y - 20

	-- Multiple stacked glowing cloud discs
	local layers = {
		{ s = 400, t = 0.40, c = CLOUD_DEEP,  dy = 0 },
		{ s = 340, t = 0.35, c = CLOUD_MID,   dy = -0.6 },
		{ s = 260, t = 0.28, c = CLOUD_LIGHT, dy = -1.2 },
		{ s = 180, t = 0.22, c = HOLY_WARM,   dy = -1.8 },
		{ s = 110, t = 0.15, c = HOLY_IVORY,  dy = -2.4 },
	}
	for _, l in ipairs(layers) do
		local d = neonPart("CloudDisc", Vector3.new(1, l.s, l.s), l.c, l.t, h)
		d.Shape = Enum.PartType.Cylinder
		d.CFrame = CFrame.new(center.X, floorY + l.dy, center.Z) * CFrame.Angles(0, 0, math.rad(90))
	end

	-- Dense cloud particle emitters spread across the floor
	local offsets = {
		Vector3.zero,
		Vector3.new(50,0,35), Vector3.new(-50,0,35),
		Vector3.new(35,0,-50), Vector3.new(-35,0,-50),
		Vector3.new(70,0,0), Vector3.new(-70,0,0),
		Vector3.new(0,0,70), Vector3.new(0,0,-70),
		Vector3.new(45,0,45), Vector3.new(-45,0,45),
		Vector3.new(45,0,-45), Vector3.new(-45,0,-45),
	}
	for _, off in ipairs(offsets) do
		local anchor = neonPart("CloudAnchor", Vector3.new(1,1,1), HOLY_GOLD, 1, h)
		anchor.CFrame = CFrame.new(center.X + off.X, floorY, center.Z + off.Z)

		local pe = Instance.new("ParticleEmitter")
		pe.Texture = HOLY_RAY_TEXTURE
		pe.Rate = 28
		pe.Lifetime = NumberRange.new(3, 6)
		pe.Speed = NumberRange.new(2, 7)
		pe.SpreadAngle = Vector2.new(90, 90)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 20),
			NumberSequenceKeypoint.new(0.4, 40),
			NumberSequenceKeypoint.new(1, 28),
		})
		pe.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HOLY_AMBER),
			ColorSequenceKeypoint.new(0.3, HOLY_GOLD),
			ColorSequenceKeypoint.new(0.7, HOLY_WARM),
			ColorSequenceKeypoint.new(1, HOLY_IVORY),
		})
		pe.LightEmission = 0.55
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.75),
			NumberSequenceKeypoint.new(0.35, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.EmissionDirection = Enum.NormalId.Top
		pe.Parent = anchor
	end

	return h
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 2. COLOSSAL DIVINE LIGHT PILLAR (massive cross-shaped central beam)
-- ══════════════════════════════════════════════════════════════════════════════
local function buildDivinePillar(casterPos: Vector3, allyPos: Vector3): Folder
	local h = Instance.new("Folder")
	h.Name = "DA_DivinePillar"
	h.Parent = Workspace.Terrain

	local rayH = 500

	local function pillar(pos: Vector3, coreW: number, glowW: number, col: Color3, brightness: number)
		local c = neonPart("PillarCore", Vector3.new(rayH, coreW, coreW), HOLY_WHITE, 0.55, h)
		c.Shape = Enum.PartType.Cylinder
		c.CFrame = CFrame.new(pos.X, pos.Y + 90, pos.Z) * CFrame.Angles(0, 0, math.rad(90))

		local g = neonPart("PillarGlow", Vector3.new(rayH, glowW, glowW), col, 0.82, h)
		g.Shape = Enum.PartType.Cylinder
		g.CFrame = c.CFrame

		local g2 = neonPart("PillarOuter", Vector3.new(rayH, glowW * 1.8, glowW * 1.8), col, 0.92, h)
		g2.Shape = Enum.PartType.Cylinder
		g2.CFrame = c.CFrame

		local pl = Instance.new("PointLight")
		pl.Color = col
		pl.Brightness = brightness * 0.3
		pl.Range = 40
		pl.Shadows = false
		pl.Parent = c

		-- Cross-beam: perpendicular neon bar at the base of the pillar
		local cross = neonPart("PillarCross", Vector3.new(glowW * 3, coreW * 0.6, coreW * 0.6), col, 0.7, h)
		cross.CFrame = CFrame.new(pos.X, pos.Y, pos.Z)

		-- Star burst at the top of the pillar
		local star = neonPart("PillarStar", Vector3.new(3, 3, 3), HOLY_WHITE, 0.4, h)
		star.Shape = Enum.PartType.Ball
		star.CFrame = CFrame.new(pos.X, pos.Y + rayH * 0.35, pos.Z)
		local sl = Instance.new("PointLight")
		sl.Color = HOLY_IVORY
		sl.Brightness = 3
		sl.Range = 45
		sl.Shadows = false
		sl.Parent = star
	end

	-- Main cleric pillar
	pillar(casterPos, 3, 14, HOLY_GOLD, 4)
	-- Secondary ally pillar
	pillar(allyPos, 2.5, 11, HOLY_AMBER, 3)

	return h
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 3. MASSIVE ORBITAL RINGS (tilted at various dramatic angles like the reference)
-- ══════════════════════════════════════════════════════════════════════════════
local function buildOrbitalRings(center: Vector3): (((number) -> ()), Folder)
	local h = Instance.new("Folder")
	h.Name = "DA_OrbitalRings"
	h.Parent = Workspace.Terrain

	-- Each ring: { radius, segCount, thickness, color, transparency, tiltX, tiltZ, speed, yOffset }
	local ringDefs = {
		-- Giant outermost rings (tilted dramatically like the reference)
		{ r=55, n=72, w=1.0, c=HOLY_GOLD,  t=0.15, tx=0.15, tz=0,     sp=0.25, dy=0 },
		{ r=48, n=64, w=0.8, c=HOLY_AMBER, t=0.20, tx=-0.1, tz=0.2,   sp=-0.35, dy=2 },
		{ r=42, n=56, w=0.7, c=HOLY_WARM,  t=0.22, tx=0.25, tz=-0.15, sp=0.45, dy=-1 },
		-- Medium rings
		{ r=34, n=48, w=0.9, c=HOLY_GOLD,  t=0.12, tx=0,    tz=0,     sp=-0.3, dy=-3 },
		{ r=28, n=44, w=0.6, c=HOLY_IVORY, t=0.25, tx=-0.2, tz=0.1,   sp=0.55, dy=1 },
		{ r=22, n=36, w=0.7, c=HOLY_AMBER, t=0.18, tx=0.3,  tz=0.2,   sp=-0.5, dy=-2 },
		-- Inner rings
		{ r=16, n=28, w=0.5, c=HOLY_GOLD,  t=0.15, tx=0,    tz=-0.25, sp=0.7,  dy=0 },
		{ r=10, n=20, w=0.45,c=HOLY_WHITE, t=0.20, tx=0.15, tz=0.15,  sp=-0.8, dy=1 },
	}

	local ringModels = {}

	for i, def in ipairs(ringDefs) do
		local rm = Instance.new("Model")
		rm.Name = "OrbitalRing_" .. i
		local chord = (2 * math.pi * def.r / def.n) * 1.4
		for k = 1, def.n do
			local ang = (k / def.n) * math.pi * 2
			local px = math.cos(ang) * def.r
			local pz = math.sin(ang) * def.r
			local seg = neonPart("RingSeg", Vector3.new(def.w, 0.3, chord), def.c, def.t, rm)
			seg.CFrame = CFrame.new(px, 0, pz) * CFrame.Angles(0, -ang, 0)
		end

		-- Add bright glow segments every few segments for the sparkle effect
		local glowInterval = math.max(4, math.floor(def.n / 8))
		for k = 1, def.n, glowInterval do
			local ang = (k / def.n) * math.pi * 2
			local px = math.cos(ang) * def.r
			local pz = math.sin(ang) * def.r
			local glow = neonPart("RingGlow", Vector3.new(def.w * 3, 0.5, def.w * 3), HOLY_WHITE, 0.5, rm)
			glow.Shape = Enum.PartType.Ball
			glow.Size = Vector3.new(1.5, 1.5, 1.5)
			glow.CFrame = CFrame.new(px, 0, pz)
		end

		rm.Parent = h
		table.insert(ringModels, { model = rm, def = def })
	end

	local function update(_dt: number)
		local t = os.clock()
		for _, entry in ipairs(ringModels) do
			local def = entry.def
			local baseRot = CFrame.Angles(def.tx, t * def.sp, def.tz)
			entry.model:PivotTo(CFrame.new(center.X, center.Y + def.dy, center.Z) * baseRot)
		end
	end

	return update, h
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 4. RADIATING GROUND LIGHT STREAKS (golden light lines radiating outward)
-- ══════════════════════════════════════════════════════════════════════════════
local function buildRadiatingStreaks(center: Vector3): Folder
	local h = Instance.new("Folder")
	h.Name = "DA_RadiatingStreaks"
	h.Parent = Workspace.Terrain

	local streakY = center.Y - 18
	local streakCount = 24
	for k = 1, streakCount do
		local ang = (k / streakCount) * math.pi * 2
		local len = 40 + math.random() * 60
		local mid = len * 0.5
		local px = center.X + math.cos(ang) * mid
		local pz = center.Z + math.sin(ang) * mid

		local streak = neonPart("Streak", Vector3.new(0.6 + math.random() * 0.4, 0.15, len), HOLY_GOLD, 0.2 + math.random() * 0.15, h)
		streak.CFrame = CFrame.new(px, streakY + math.random() * 0.3, pz) * CFrame.Angles(0, -ang, 0)

		-- Glow sleeve
		local glow = neonPart("StreakGlow", Vector3.new(2.0, 0.1, len * 0.8), HOLY_AMBER, 0.7, h)
		glow.CFrame = streak.CFrame
	end

	return h
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 5. FLOATING DEBRIS / ROCK FRAGMENTS
-- ══════════════════════════════════════════════════════════════════════════════
local function buildFloatingDebris(center: Vector3): (((number) -> ()), Folder)
	local h = Instance.new("Folder")
	h.Name = "DA_FloatingDebris"
	h.Parent = Workspace.Terrain

	local debris = {}
	for k = 1, 18 do
		local ang = math.random() * math.pi * 2
		local dist = 15 + math.random() * 45
		local sz = 1.5 + math.random() * 4
		local yOff = -12 + math.random() * 24

		local rock = neonPart("Debris", Vector3.new(sz, sz * 0.7, sz * 0.9), CLOUD_DEEP, 0.1, h)
		rock.Material = Enum.Material.Slate
		rock.Color = Color3.fromRGB(80 + math.random(40), 65 + math.random(30), 45 + math.random(25))
		local basePos = Vector3.new(center.X + math.cos(ang) * dist, center.Y + yOff, center.Z + math.sin(ang) * dist)
		rock.CFrame = CFrame.new(basePos) * CFrame.Angles(math.random() * math.pi, math.random() * math.pi, math.random() * math.pi)

		table.insert(debris, {
			part = rock,
			basePos = basePos,
			ang = ang,
			bobSpeed = 0.3 + math.random() * 0.5,
			bobAmp = 0.5 + math.random() * 1.5,
			rotSpeed = 0.1 + math.random() * 0.3,
			phase = math.random() * math.pi * 2,
		})
	end

	local function update(_dt: number)
		local t = os.clock()
		for _, d in ipairs(debris) do
			local bob = math.sin(t * d.bobSpeed + d.phase) * d.bobAmp
			d.part.CFrame = CFrame.new(d.basePos + Vector3.new(0, bob, 0)) * CFrame.Angles(0, t * d.rotSpeed, 0)
		end
	end

	return update, h
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 6. DENSE SPARKLE / STAR PARTICLES
-- ══════════════════════════════════════════════════════════════════════════════
local function buildSparkleField(center: Vector3): Folder
	local h = Instance.new("Folder")
	h.Name = "DA_Sparkles"
	h.Parent = Workspace.Terrain

	-- Multiple emitter anchors spread in a sphere around the scene
	local sphereOffsets = {
		Vector3.new(0, 10, 0),
		Vector3.new(20, 5, 15), Vector3.new(-20, 5, 15),
		Vector3.new(15, -5, -20), Vector3.new(-15, -5, -20),
		Vector3.new(0, -10, 0),
		Vector3.new(30, 0, 0), Vector3.new(-30, 0, 0),
		Vector3.new(0, 0, 30), Vector3.new(0, 0, -30),
		Vector3.new(10, 15, 10), Vector3.new(-10, 15, -10),
	}

	for _, off in ipairs(sphereOffsets) do
		local anchor = neonPart("SparkleAnchor", Vector3.new(1,1,1), HOLY_GOLD, 1, h)
		anchor.CFrame = CFrame.new(center + off)

		local pe = Instance.new("ParticleEmitter")
		pe.Texture = HOLY_RAY_TEXTURE
		pe.Rate = 40
		pe.Lifetime = NumberRange.new(0.8, 2.5)
		pe.Speed = NumberRange.new(1, 5)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(0.3, 1.8),
			NumberSequenceKeypoint.new(1, 0.5),
		})
		pe.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, HOLY_WHITE),
			ColorSequenceKeypoint.new(0.5, HOLY_GOLD),
			ColorSequenceKeypoint.new(1, HOLY_IVORY),
		})
		pe.LightEmission = 1
		pe.LightInfluence = 0
		pe.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(0.3, 0),
			NumberSequenceKeypoint.new(1, 1),
		})
		pe.EmissionDirection = Enum.NormalId.Front
		pe.Parent = anchor
	end

	return h
end

-- ══════════════════════════════════════════════════════════════════════════════
-- 7. HOLY BRIDGE & DIVINE TETHER
-- ══════════════════════════════════════════════════════════════════════════════
local function buildHolyBridge(casterChar: Model, allyPos: Vector3): ((Vector3?) -> (), Folder)
	local h = Instance.new("Folder")
	h.Name = "DA_HolyBridge"
	h.Parent = Workspace.Terrain

	local core = neonPart("BridgeCore", Vector3.new(2, 2, 2), HOLY_WHITE, 0.35, h)
	core.Shape = Enum.PartType.Ball

	local pl = Instance.new("PointLight")
	pl.Color = HOLY_GOLD
	pl.Brightness = 3
	pl.Range = 30
	pl.Shadows = false
	pl.Parent = core

	local beam = neonPart("BridgeBeam", Vector3.new(1, 10, 1), HOLY_WARM, 0.4, h)
	local outerBeam = neonPart("BridgeOuter", Vector3.new(2.5, 10, 2.5), HOLY_GOLD, 0.78, h)
	local ultraOuter = neonPart("BridgeUltra", Vector3.new(4, 10, 4), HOLY_AMBER, 0.9, h)

	-- Clone the Holy VFX at the bridge midpoint
	local gv = ReplicatedStorage:FindFirstChild("generalVFX")
	local holySrc = gv and gv:FindFirstChild("Holy")
	if holySrc then
		local holy = holySrc:Clone()
		holy.Name = "HolyLight"
		if holy:IsA("BasePart") then
			holy.Anchored = true
			holy.CanCollide = false
			holy.CanQuery = false
			holy.Size = Vector3.new(12, 12, 12)
		end
		holy.Parent = h
	end

	local function tip(side: string): Vector3?
		local arm = casterChar:FindFirstChild(side .. " Arm")
		if arm and arm:IsA("BasePart") then
			return (arm.CFrame * CFrame.new(0, -1.2, 0)).Position
		end
		return nil
	end

	local function update(liveAllyPos: Vector3?)
		local target = liveAllyPos or allyPos
		local hand = tip("Right") or tip("Left")
		local root = casterChar:FindFirstChild("HumanoidRootPart")
		if not hand and root and root:IsA("BasePart") then
			hand = root.Position
		end
		if not hand then return end
		local mid = (hand + target) * 0.5
		core.CFrame = CFrame.new(mid)
		local holy = h:FindFirstChild("HolyLight")
		if holy and holy:IsA("BasePart") then
			holy.CFrame = CFrame.new(mid)
		end
		local diff = target - hand
		if diff.Magnitude > 0.1 then
			local rot = CFrame.lookAt(mid, target) * CFrame.Angles(math.rad(90), 0, 0)
			beam.Size = Vector3.new(1.4, diff.Magnitude, 1.4)
			beam.CFrame = rot
			outerBeam.Size = Vector3.new(3.5, diff.Magnitude, 3.5)
			outerBeam.CFrame = rot
			ultraOuter.Size = Vector3.new(6, diff.Magnitude, 6)
			ultraOuter.CFrame = rot
		end
	end

	return update, h
end

-- ══════════════════════════════════════════════════════════════════════════════
-- CLEANUP helper: fade-out and destroy a folder of VFX
-- ══════════════════════════════════════════════════════════════════════════════
local function cleanupFolder(folder: Folder?)
	if not folder or not folder.Parent then return end
	for _, d in ipairs(folder:GetDescendants()) do
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(0.5), { Transparency = 1 }):Play()
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		elseif d:IsA("PointLight") then
			TweenService:Create(d, TweenInfo.new(0.5), { Brightness = 0 }):Play()
		end
	end
	Debris:AddItem(folder, 0.7)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- MAIN PLAY
-- ══════════════════════════════════════════════════════════════════════════════
function DivineAscentCutscene.Play(duration: number, aimDir: Vector3?)
	duration = 2.0
	token += 1
	local my = token

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local iso = getIso()
	local wasIso = iso and iso.IsActive and iso.IsActive()
	if wasIso then iso.Pause() end

	-- No black fade screen — direct camera cut

	camera.CameraType = Enum.CameraType.Scriptable

	local function still(): boolean
		return token == my and char.Parent ~= nil
	end

	local function restore()
		if token ~= my then return end
		if wasIso and iso then
			iso.Resume(0.5)
		else
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then camera.CameraSubject = hum end
		end
	end

	task.spawn(function()

		local LIFT = 159
		local returnCF = root.CFrame
		local flatAim = aimDir and Vector3.new(aimDir.X, 0, aimDir.Z) or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		if flatAim.Magnitude < 0.001 then flatAim = Vector3.new(0, 0, -1) end
		flatAim = flatAim.Unit
		local casterPos = root.Position + Vector3.new(0, LIFT, 0)
		local liftedCF = CFrame.lookAt(casterPos, casterPos + flatAim)
		local wasAnchored = root.Anchored
		root.Anchored = true
		root.CFrame = liftedCF
		setCasterAnimate(char, true)
		poseAngel(char, nil)

		local skyMinY = casterPos.Y - 25
		local ac = allyCenter(skyMinY)
		local waited = 0
		while not ac and waited < 0.8 do
			task.wait(0.05)
			waited += 0.05
			if not still() then return end
			ac = allyCenter(skyMinY)
		end

		local center = ac or (casterPos + flatAim * 10 + Vector3.new(0, 12, 0))
		local toCenter = Vector3.new(center.X - casterPos.X, 0, center.Z - casterPos.Z)
		if toCenter.Magnitude > 0.1 then
			root.CFrame = CFrame.lookAt(casterPos, casterPos + toCenter.Unit)
		end

		local axis = Vector3.new(casterPos.X - center.X, 0, casterPos.Z - center.Z)
		if axis.Magnitude < 1 then axis = flatAim * -1 end
		axis = axis.Unit
		local side = Vector3.new(-axis.Z, 0, axis.X)
		local mid = (casterPos + center) * 0.5

		local nearPos = mid + side * CAM_NEAR + Vector3.new(0, CAM_HEIGHT, 0)
		local farPos = mid + side * CAM_FAR + Vector3.new(0, CAM_HEIGHT - 0.8, 0)
		local focus = mid + Vector3.new(0, 4.0, 0)

		camera.CFrame = CFrame.lookAt(nearPos, focus)
		camera.FieldOfView = CAM_FOV

		-- ── Spawn the entire celestial realm ──
		local cloudOcean      = buildCloudOcean(mid)
		local divinePillar    = buildDivinePillar(casterPos, center)
		local updateRings, orbitalRings = buildOrbitalRings(mid)
		local radiatingStreaks = buildRadiatingStreaks(mid)
		local updateDebris, floatingDebris = buildFloatingDebris(mid)
		local sparkleField    = buildSparkleField(mid)
		local updateBridge, holyBridge = buildHolyBridge(char, center)

		-- ── UltAtmosphere sky dome above the camera ──
		local ultAtmo = spawnUltAtmosphere()
		if ultAtmo then
			positionAtmosphereAboveCamera(ultAtmo)
		end

		local t0 = os.clock()
		local holdDur = math.max(0.6, duration - 0.7)
		while still() and (os.clock() - t0) < holdDur do
			local a = math.clamp((os.clock() - t0) / holdDur, 0, 1)
			local p = nearPos:Lerp(farPos, a)
			camera.CFrame = CFrame.lookAt(p, focus)

			local liveCenter = allyCenter(skyMinY) or center
			local toLive = Vector3.new(liveCenter.X - casterPos.X, 0, liveCenter.Z - casterPos.Z)
			if toLive.Magnitude > 0.1 and root then
				root.CFrame = CFrame.lookAt(casterPos, casterPos + toLive.Unit)
			end

			poseAngel(char, liveCenter)
			local dt = RunService.RenderStepped:Wait()
			updateRings(dt)
			updateDebris(dt)
			updateBridge(liveCenter)
			if ultAtmo then positionAtmosphereAboveCamera(ultAtmo) end
		end
		if not still() then return end

		-- Cleanup all VFX
		cleanupFolder(cloudOcean)
		cleanupFolder(divinePillar)
		cleanupFolder(orbitalRings)
		cleanupFolder(radiatingStreaks)
		cleanupFolder(floatingDebris)
		cleanupFolder(sparkleField)
		cleanupFolder(holyBridge)
		if ultAtmo and ultAtmo.Parent then
			if ultAtmo:IsA("BasePart") then
				TweenService:Create(ultAtmo, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			else
				for _, d in ipairs(ultAtmo:GetDescendants()) do
					if d:IsA("BasePart") then
						TweenService:Create(d, TweenInfo.new(0.5), { Transparency = 1 }):Play()
					elseif d:IsA("ParticleEmitter") then
						d.Enabled = false
					end
				end
			end
			Debris:AddItem(ultAtmo, 0.7)
		end

		if clericTrack then
			pcall(function() clericTrack:Stop(0.2) end)
			clericTrack = nil
		end
		restoreJoints(char)
		setCasterAnimate(char, false)
		if root then
			root.CFrame = returnCF
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = wasAnchored
		end

		-- Direct camera hand-back (no black fade)
		restore()
	end)
end

function DivineAscentCutscene.Stop()
	token += 1
end

return DivineAscentCutscene
