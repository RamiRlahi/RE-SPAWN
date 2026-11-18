--[[
	HitFX.luau
	Impact feedback for every hit (server SkillManager → HitImpact remote):

	  • a per-attack impact effect, by style:
	      slash  — Heavy Knight blade: bright crescent + sparks
	      fire   — Heavy Knight flame: fireball bloom, embers, smoke
	      arrow  — Ranger shots: puncture ring, splinters, venom puff
	      nature — Ranger nature: green slash, leaves
	      holy   — Cleric: golden cross flash, ring, motes
	      ice    — Ice Mage: shard spray, frost puff
	      fist   — Martial Artist: a white starburst hit marker, crimson ring
	  • a white hit-flash on the target (recolour, not a Highlight — the game
	    already runs close to Roblox's on-screen Highlight limit)
	  • crits: larger and gold-tinged; heavy hits: a small shake for the attacker
	  • under every style, the impact layers from the reference clips
	    (docs/vfx-reference-timing.md), on pooled emitters (no instances per hit):
	      - a floor glow on frame 0, tinted per style, faded within ~0.35-0.5 s
	      - a starburst flash (Grid2x2 flipbook) that lives 3 frames
	      - heavy hits and crits: a ground stain (scorch / frost / holy) that
	        outlives the effect, and client-only hit stop for the attacker
	        (BigHitFX.HitStop: 2-4 frames; damage timing is unchanged)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local VfxAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxAssets"))
local VariantFX = require(script.Parent:WaitForChild("VariantFX"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local BigHitFX = require(script.Parent:WaitForChild("BigHitFX"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local CRIT_GOLD = Color3.fromRGB(255, 215, 90)

local HitFX = {}

-- Whose hit is being drawn (its VFX variant colours the impact).
local currentAttacker: Player? = nil

-- ─── Helpers ────────────────────────────────────────────────────────────────
local function part(props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = VariantFX.RootFor(currentAttacker)
	return p
end

local function burst(pos: Vector3, props: { [string]: any }, count: number, life: number?)
	local a = Instance.new("Attachment")
	a.Parent = VariantFX.RootFor(currentAttacker)
	a.WorldPosition = pos
	local pe = Instance.new("ParticleEmitter")
	pe.LightInfluence = 0
	pe.Rate = 0
	pe.SpreadAngle = Vector2.new(180, 180)
	for k, v in pairs(props) do
		(pe :: any)[k] = v
	end
	pe.Parent = a
	pe:Emit(count)
	Debris:AddItem(a, life or 1.5)
end

local function seq(...): NumberSequence
	local a = { ... }
	local k = {}
	for i = 1, #a, 2 do table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1])) end
	return NumberSequence.new(k)
end

local function flashLight(pos: Vector3, color: Color3, brightness: number, range: number)
	if not FxBudget.Light() then return end
	local a = Instance.new("Attachment")
	a.Parent = VariantFX.RootFor(currentAttacker)
	a.WorldPosition = pos
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range, l.Shadows = color, brightness, range, false
	l.Parent = a
	TweenService:Create(l, TweenInfo.new(0.25), { Brightness = 0 }):Play()
	Debris:AddItem(a, 0.3)
end

-- Grow-and-fade a part (flashes, rings, blooms).
local function pop(p: BasePart, toSize: Vector3, t: number)
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = toSize, Transparency = 1 }):Play()
	Debris:AddItem(p, t + 0.05)
end

-- A flat ring facing `normal`, expanding.
local function ringWave(pos: Vector3, normal: Vector3, r0: number, r1: number, t: number, color: Color3)
	local ring = part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.08, r0 * 2, r0 * 2),
		CFrame = CFrame.lookAt(pos, pos + normal) * CFrame.Angles(0, math.rad(90), 0),
		Color = color,
		Transparency = 0.25,
	})
	pop(ring, Vector3.new(0.05, r1 * 2, r1 * 2), t)
end

-- ─── Hit flash on the target ────────────────────────────────────────────────
local flashing: { [Model]: { [BasePart]: { Color3 | Enum.Material } } } = {}

local function hitFlash(model: Model?, crit: boolean, hold: number?)
	if not model or not model.Parent then return end
	local saved = flashing[model]
	if not saved then
		saved = {}
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "HumanoidRootPart" then
				saved[d] = { d.Color, d.Material }
			end
		end
		flashing[model] = saved
	end
	for p in pairs(saved) do
		if p.Parent then
			p.Color = crit and CRIT_GOLD or Color3.new(1, 1, 1)
			p.Material = Enum.Material.Neon
		end
	end
	local stamp = os.clock()
	model:SetAttribute("HitFlashStamp", stamp)
	task.delay(hold or (crit and 0.1 or 0.07), function()
		if model:GetAttribute("HitFlashStamp") ~= stamp then return end -- a newer hit owns the flash
		for p, orig in pairs(saved) do
			if p.Parent then
				p.Color = orig[1] :: Color3
				p.Material = orig[2] :: Enum.Material
			end
		end
		flashing[model] = nil
	end)
end

-- ─── Styles ─────────────────────────────────────────────────────────────────
type Hit = { pos: Vector3, dir: Vector3, scale: number, crit: boolean, heavy: boolean }

local STYLES: { [string]: (Hit) -> () } = {}

STYLES.slash = function(h)
	local c = h.pos + Vector3.new(0, 0.5, 0)
	local side = h.dir:Cross(Vector3.yAxis).Unit
	-- Crescent of three blades sweeping across the target.
	local tilt = math.rad(math.random(-35, 35))
	for i = -1, 1 do
		local blade = part({
			Size = Vector3.new(0.12, 0.35 - math.abs(i) * 0.1, 4.2 * h.scale),
			CFrame = CFrame.lookAt(c + h.dir * (0.3 * i), c + h.dir * (0.3 * i) + side) * CFrame.Angles(0, 0, tilt) * CFrame.Angles(math.rad(i * 12), 0, 0),
			Color = h.crit and CRIT_GOLD or (i == 0 and Color3.new(1, 1, 1) or Color3.fromRGB(255, 200, 120)),
			Transparency = 0,
		})
		pop(blade, Vector3.new(0.05, 0.1, 6 * h.scale), 0.18)
	end
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(255, 170, 70)), LightEmission = 1,
		Size = seq(0, 0.5 * h.scale, 1, 0), Lifetime = NumberRange.new(0.15, 0.35), Speed = NumberRange.new(18, 34),
		SpreadAngle = Vector2.new(35, 35), EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, -40, 0) }, math.floor(14 * h.scale))
	flashLight(c, Color3.fromRGB(255, 220, 170), 3 * h.scale, 12)
end

STYLES.fire = function(h)
	local c = h.pos + Vector3.new(0, 0.8, 0)
	local bloom = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, CFrame = CFrame.new(c), Color = Color3.fromRGB(255, 150, 50), Transparency = 0.1 })
	pop(bloom, Vector3.one * 6 * h.scale, 0.3)
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = CFrame.new(c), Color = Color3.fromRGB(255, 240, 200) })
	pop(core, Vector3.one * 3.5 * h.scale, 0.18)
	burst(c, { Texture = TEX_FIRE, Color = ColorSequence.new(Color3.fromRGB(255, 200, 90), Color3.fromRGB(255, 70, 20)), LightEmission = 1,
		Size = seq(0, 1.6 * h.scale, 1, 0), Lifetime = NumberRange.new(0.3, 0.6), Speed = NumberRange.new(8, 18),
		Acceleration = Vector3.new(0, 12, 0), Rotation = NumberRange.new(0, 360) }, math.floor(18 * h.scale))
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(255, 180, 80)), LightEmission = 1,
		Size = seq(0, 0.3, 1, 0), Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(10, 22),
		Acceleration = Vector3.new(0, 6, 0), Drag = 2 }, math.floor(16 * h.scale))
	burst(c, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(60, 45, 40)), LightEmission = 0,
		Size = seq(0, 1.5, 1, 4.5 * h.scale), Transparency = seq(0, 0.5, 1, 1), Lifetime = NumberRange.new(0.6, 1),
		Speed = NumberRange.new(2, 5), Acceleration = Vector3.new(0, 4, 0) }, 4)
	flashLight(c, Color3.fromRGB(255, 150, 60), 5 * h.scale, 18)
end

STYLES.arrow = function(h)
	local c = h.pos + Vector3.new(0, 0.6, 0)
	ringWave(c - h.dir * 0.8, -h.dir, 0.3, 1.8 * h.scale, 0.2, h.crit and CRIT_GOLD or Color3.fromRGB(190, 255, 120))
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(230, 255, 190), Color3.fromRGB(120, 220, 70)), LightEmission = 1,
		Size = seq(0, 0.35, 1, 0), Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(14, 26),
		SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Front }, math.floor(10 * h.scale))
	burst(c, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(120, 200, 70), Color3.fromRGB(70, 130, 40)), LightEmission = 0.3,
		Size = seq(0, 0.8, 1, 2.6 * h.scale), Transparency = seq(0, 0.45, 1, 1), Lifetime = NumberRange.new(0.5, 0.8),
		Speed = NumberRange.new(1, 3) }, 3)
end

-- Gunslinger bullets: a brass spark spray, a ring on heavy/crit hits and a
-- small gunpowder puff.
STYLES.bullet = function(h)
	local c = h.pos + Vector3.new(0, 0.9, 0)
	local brass = if h.crit then CRIT_GOLD else Color3.fromRGB(255, 196, 110)
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(255, 250, 230), brass), LightEmission = 1,
		Size = seq(0, 0.4 * h.scale, 1, 0), Lifetime = NumberRange.new(0.12, 0.28), Speed = NumberRange.new(16, 30),
		SpreadAngle = Vector2.new(35, 35), EmissionDirection = Enum.NormalId.Front }, math.floor(12 * h.scale))
	if h.heavy or h.crit then
		ringWave(c - h.dir * 0.6, -h.dir, 0.3, 2.2 * h.scale, 0.2, brass)
	end
	burst(c, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(150, 138, 124), Color3.fromRGB(90, 84, 78)), LightEmission = 0,
		Size = seq(0, 0.7, 1, 2.2 * h.scale), Transparency = seq(0, 0.5, 1, 1), Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(1, 3) }, 3)
	flashLight(c, brass, 2 * h.scale, 8)
end

STYLES.nature = function(h)
	local c = h.pos + Vector3.new(0, 0.6, 0)
	local side = h.dir:Cross(Vector3.yAxis).Unit
	local slash = part({ Size = Vector3.new(0.12, 0.3, 5 * h.scale), CFrame = CFrame.lookAt(c, c + side) * CFrame.Angles(0, 0, math.rad(math.random(-40, 40))),
		Color = h.crit and CRIT_GOLD or Color3.fromRGB(190, 255, 110) })
	pop(slash, Vector3.new(0.05, 0.1, 7 * h.scale), 0.22)
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(190, 255, 100), Color3.fromRGB(90, 190, 50)), LightEmission = 0.8,
		Size = seq(0, 0.55, 1, 0), Lifetime = NumberRange.new(0.5, 1), Speed = NumberRange.new(8, 18),
		Acceleration = Vector3.new(0, -15, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-300, 300) }, math.floor(16 * h.scale))
	flashLight(c, Color3.fromRGB(170, 255, 110), 2.5 * h.scale, 12)
end

STYLES.holy = function(h)
	local c = h.pos + Vector3.new(0, 1, 0)
	local face = CFrame.lookAt(c, c - h.dir)
	local gold = h.crit and CRIT_GOLD or Color3.fromRGB(255, 225, 140)
	local v = part({ Size = Vector3.new(0.35, 3 * h.scale, 0.1), CFrame = face, Color = Color3.fromRGB(255, 252, 235) })
	local hz = part({ Size = Vector3.new(2 * h.scale, 0.35, 0.1), CFrame = face * CFrame.new(0, 0.5 * h.scale, 0), Color = Color3.fromRGB(255, 252, 235) })
	pop(v, Vector3.new(0.1, 4.5 * h.scale, 0.05), 0.3)
	pop(hz, Vector3.new(3 * h.scale, 0.1, 0.05), 0.3)
	ringWave(c, -h.dir, 0.4, 2.6 * h.scale, 0.3, gold)
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), gold), LightEmission = 1,
		Size = seq(0, 0.45, 1, 0), Lifetime = NumberRange.new(0.4, 0.8), Speed = NumberRange.new(4, 12),
		Acceleration = Vector3.new(0, 6, 0), Drag = 3 }, math.floor(12 * h.scale))
	flashLight(c, gold, 3.5 * h.scale, 14)
end

STYLES.ice = function(h)
	local c = h.pos + Vector3.new(0, 0.6, 0)
	for _ = 1, math.floor(7 * h.scale) do
		local s = 0.3 + math.random() * 0.5
		local shard = part({ ClassName = "WedgePart", Size = Vector3.new(s * 0.3, s * 1.4, s * 0.8),
			CFrame = CFrame.new(c) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6),
			Color = math.random() < 0.5 and Color3.fromRGB(200, 245, 255) or Color3.fromRGB(120, 220, 255),
			Material = Enum.Material.Glass, Transparency = 0.15, Anchored = false })
		local d = (h.dir + Vector3.new((math.random() - 0.5) * 1.6, 0.6 + math.random(), (math.random() - 0.5) * 1.6)).Unit
		shard.AssemblyLinearVelocity = d * (16 + math.random() * 14)
		shard.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 20
		task.delay(0.35, function()
			if shard.Parent then TweenService:Create(shard, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
		end)
		Debris:AddItem(shard, 0.7)
	end
	burst(c, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(235, 250, 255)), LightEmission = 0.3,
		Size = seq(0, 1, 1, 3 * h.scale), Transparency = seq(0, 0.5, 1, 1), Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(1, 3) }, 3)
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), Color3.fromRGB(110, 220, 255)), LightEmission = 1,
		Size = seq(0, 0.35, 1, 0), Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(8, 16) }, math.floor(10 * h.scale))
	flashLight(c, Color3.fromRGB(150, 230, 255), 3 * h.scale, 12)
end

-- Martial Artist: the hit marker. A white starburst turned to the camera
-- (spikes shooting out of a white core), a crimson ring punched out of it,
-- sparks flung on the way the blow went.
local FIST_RED = Color3.fromRGB(226, 26, 46)
STYLES.fist = function(h)
	local c = h.pos + Vector3.new(0, 1, 0)
	local eye = camera.CFrame.Position
	local face = CFrame.lookAt(c, eye)
	local tint = if h.crit then CRIT_GOLD else Color3.new(1, 1, 1)
	local n = if h.heavy then 8 else 6
	local turn = math.random() * math.pi
	for i = 1, n do
		local a = CFrame.Angles(0, 0, turn + i / n * math.pi * 2)
		local len = (if i % 2 == 0 then 1.5 else 2.5) * h.scale
		local spike = part({ Size = Vector3.new(0.24 * h.scale, len, 0.05), Color = tint, CFrame = face * a * CFrame.new(0, len * 0.5 + 0.3, 0) })
		TweenService:Create(spike, TweenInfo.new(0.16, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.03, len * 1.4, 0.03), CFrame = face * a * CFrame.new(0, len * 0.9 + 0.7, 0), Transparency = 1 }):Play()
		Debris:AddItem(spike, 0.2)
	end
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.2 * h.scale, CFrame = CFrame.new(c), Color = tint })
	pop(core, Vector3.one * 3.2 * h.scale, 0.12)
	ringWave(c, eye - c, 0.4, 2.8 * h.scale, 0.2, FIST_RED)
	burst(c, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), FIST_RED), LightEmission = 1,
		Size = seq(0, 0.45 * h.scale, 1, 0), Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(18, 32),
		SpreadAngle = Vector2.new(40, 40), EmissionDirection = Enum.NormalId.Front, Acceleration = Vector3.new(0, -30, 0) },
		math.floor(12 * h.scale))
	flashLight(c, Color3.fromRGB(255, 220, 220), 3 * h.scale, 10)
end

-- ─── Impact layers (floor glow, flash frame, ground stain) ─────────────────
-- Per style: the floor glow's tint, the starburst's palette (+ a tint over its
-- baked colours) and the stain left by heavy hits and crits.
type Look = { glow: Color3, burst: string, burstTint: Color3, stain: string? }
local LOOKS: { [string]: Look } = {
	fire = { glow = Color3.fromRGB(255, 62, 40), burst = "fire", burstTint = Color3.new(1, 1, 1), stain = "scorch" },
	ice = { glow = Color3.fromRGB(80, 160, 255), burst = "ice", burstTint = Color3.new(1, 1, 1), stain = "frost" },
	holy = { glow = Color3.fromRGB(255, 196, 80), burst = "holy", burstTint = Color3.new(1, 1, 1), stain = "holy" },
	slash = { glow = Color3.fromRGB(255, 170, 90), burst = "holy", burstTint = Color3.fromRGB(255, 240, 225), stain = "scorch" },
	fist = { glow = Color3.fromRGB(230, 30, 50), burst = "holy", burstTint = Color3.fromRGB(255, 225, 225), stain = "scorch" },
	bullet = { glow = Color3.fromRGB(255, 180, 90), burst = "fire", burstTint = Color3.new(1, 1, 1), stain = nil },
	arrow = { glow = Color3.fromRGB(130, 230, 80), burst = "holy", burstTint = Color3.fromRGB(200, 255, 170), stain = nil },
	nature = { glow = Color3.fromRGB(130, 230, 80), burst = "holy", burstTint = Color3.fromRGB(200, 255, 170), stain = nil },
}

-- Pooled emitters: one per look and size, moved to each hit and Emit()ed.
-- Particles are world-space once emitted, so moving the attachment is safe.
local poolFolder: Folder? = nil
local pool: { [string]: { att: Attachment, pe: ParticleEmitter } } = {}

local function emitter(key: string, build: (ParticleEmitter) -> ()): (Attachment, ParticleEmitter)
	local e = pool[key]
	if e and e.att.Parent then return e.att, e.pe end
	if not poolFolder or not poolFolder.Parent then
		local f = Instance.new("Folder")
		f.Name = "ImpactFX"
		f.Parent = Workspace
		poolFolder = f
	end
	local holder = Instance.new("Part")
	holder.Name = key
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.Parent = poolFolder
	local att = Instance.new("Attachment")
	att.Parent = holder
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.LightInfluence = 0
	pe.LockedToPart = false
	build(pe)
	pe.Parent = att
	pool[key] = { att = att, pe = pe }
	return att, pe
end

-- Something lying flat on the floor: a particle facing up (VelocityPerpendicular,
-- drifting up so slowly it never moves).
local function flat(pe: ParticleEmitter)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pe.Speed = NumberRange.new(0.01)
	pe.SpreadAngle = Vector2.zero
	pe.Rotation = NumberRange.new(0, 360)
end

-- The floor under a hit (mobs, characters and effects ignored).
local floorParams = RaycastParams.new()
floorParams.FilterType = Enum.RaycastFilterType.Exclude
floorParams.IgnoreWater = true
local function floorUnder(pos: Vector3): Vector3?
	local skip: { Instance } = {}
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(skip, mobs) end
	if poolFolder then table.insert(skip, poolFolder) end
	table.insert(skip, VariantFX.Root())
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(skip, plr.Character) end
	end
	floorParams.FilterDescendantsInstances = skip
	local hit = Workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -14, 0), floorParams)
	return hit and hit.Position or nil
end

local function lowDetail(): boolean
	return player:GetAttribute("Setting_lowDetailVFX") == true or player:GetAttribute("PerfMode") == true
end

local function impactLayers(styleName: string, h: Hit)
	local look = LOOKS[styleName]
	if not look then return end
	local big = h.crit or h.heavy
	local size = if big then "big" else "small"

	-- the flash frame: a starburst turned to the camera, alive for 3 frames
	-- (f0 full, f1 stretched, f2 thin: the reference's 2-frame overexposure)
	if FxBudget.Allow("impactFlash", if big then 12 else 24) then
		local tex = VfxAssets.Starburst[look.burst]
		local att, pe = emitter(`flash_{look.burst}_{styleName}_{size}`, function(pe)
			pe.Texture = tex.id
			pe.FlipbookLayout = tex.layout :: Enum.ParticleFlipbookLayout
			pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
			pe.Color = ColorSequence.new(look.burstTint)
			pe.LightEmission = 1
			pe.Brightness = if big then 4 else 3
			pe.Lifetime = NumberRange.new(if big then 0.13 else 0.1)
			pe.Size = NumberSequence.new(if big then 9 else 5)
			pe.Speed = NumberRange.new(0)
			pe.Rotation = NumberRange.new(0, 360)
			pe.ZOffset = 2 -- in front of the target it hits
		end)
		att.WorldPosition = h.pos + Vector3.new(0, 1, 0)
		pe:Emit(1)
	end

	-- the floor: a glow on frame 0 (+ a stain on heavy hits and crits)
	local wantGlow = FxBudget.Allow("floorGlow", if big then 10 else 16)
	local wantStain = big and look.stain ~= nil and not lowDetail() and FxBudget.Allow("groundStain", 6)
	if not (wantGlow or wantStain) then return end
	local floor = floorUnder(h.pos)
	if not floor then return end

	if wantGlow then
		local tex = if big then VfxAssets.Glow.wide else VfxAssets.Glow.soft
		local att, pe = emitter(`glow_{styleName}_{size}`, function(pe)
			flat(pe)
			pe.Texture = tex.id
			pe.Color = ColorSequence.new(look.glow)
			pe.LightEmission = 1
			pe.Brightness = if big then 1.6 else 1.2
			pe.Lifetime = NumberRange.new(if big then 0.5 else 0.35)
			pe.Size = NumberSequence.new(if big then 16 else 8)
			-- full on frame 0, then gone (the reference's glow is gone by ~f12-15)
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1),
			})
		end)
		att.WorldPosition = floor + Vector3.new(0, 0.12, 0)
		pe:Emit(1)
	end

	if wantStain then
		local kind = look.stain :: string
		local tex = (VfxAssets.Stain :: any)[kind]
		local life = if kind == "frost" then 1.4 elseif kind == "scorch" then 1.0 else 0.8
		local att, pe = emitter(`stain_{kind}`, function(pe)
			flat(pe)
			pe.Texture = tex.id
			pe.LightEmission = 0
			pe.LightInfluence = 0.4 -- sits in the room's light, the embers still read
			pe.Brightness = 1.4
			pe.Lifetime = NumberRange.new(life)
			pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 7), NumberSequenceKeypoint.new(0.08, 10), NumberSequenceKeypoint.new(1, 10.5) })
			pe.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.15), NumberSequenceKeypoint.new(1, 1),
			})
		end)
		att.WorldPosition = floor + Vector3.new(0, 0.06, 0)
		pe:Emit(1)
	end
end

-- ─── Attacker shake on heavy hits ───────────────────────────────────────────
local lastShake = 0
local function shake(amount: number)
	if os.clock() - lastShake < 0.12 then return end
	lastShake = os.clock()
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 0.15 do
			local a = amount * (1 - (os.clock() - t0) / 0.15)
			camera.CFrame *= CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- Ricochet Tome hop: a bright streak from one enemy to the next plus a spark.
local RICOCHET_COLOR = Color3.fromRGB(255, 214, 120)
local function ricochetHop(from: Vector3, to: Vector3)
	local lift = Vector3.new(0, 1.5, 0)
	local a, b = from + lift, to + lift
	local len = (b - a).Magnitude
	if len < 0.1 then return end
	local streak = part({ Size = Vector3.new(0.25, 0.25, len), CFrame = CFrame.lookAt((a + b) / 2, b), Color = RICOCHET_COLOR, Transparency = 0.1 })
	TweenService:Create(streak, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Transparency = 1, Size = Vector3.new(0.05, 0.05, len) }):Play()
	Debris:AddItem(streak, 0.25)
	burst(b, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.new(1, 1, 1), RICOCHET_COLOR), LightEmission = 1,
		Size = seq(0, 0.5, 1, 0), Lifetime = NumberRange.new(0.15, 0.3), Speed = NumberRange.new(8, 16) }, 10, 0.5)
	flashLight(b, RICOCHET_COLOR, 2, 8)
end

function HitFX.Init()
	Network.GetRemoteEvent(Network.Remotes.RicochetFX).OnClientEvent:Connect(function(p: any)
		if typeof(p) ~= "table" or typeof(p.from) ~= "Vector3" or typeof(p.to) ~= "Vector3" then return end
		if not FxBudget.Allow("ricochetHop", 20) then return end
		currentAttacker = if typeof(p.attacker) == "Instance" and p.attacker:IsA("Player") then p.attacker else nil
		ricochetHop(p.from, p.to)
		currentAttacker = nil
	end)
	Network.GetRemoteEvent(Network.Remotes.HitImpact).OnClientEvent:Connect(function(p: any)
		if typeof(p) ~= "table" or typeof(p.position) ~= "Vector3" then return end
		local style = STYLES[p.style]
		local dir = typeof(p.direction) == "Vector3" and p.direction or Vector3.new(0, 0, 1)
		local crit = p.crit == true
		local heavy = p.heavy == true
		-- (a flood of hits, e.g. a stack of Projectile + Ricochet tomes: only so
		-- many impact effects a second; crits and heavy hits get their own share)
		local key = if crit or heavy then "impactBig" else "impact"
		if style and FxBudget.Allow(key, if crit or heavy then 12 else 24) then
			currentAttacker = if typeof(p.attacker) == "Instance" and p.attacker:IsA("Player") then p.attacker else nil
			local h = { pos = p.position, dir = dir, crit = crit, heavy = heavy, scale = (heavy and 1.4 or 1) * (crit and 1.35 or 1) }
			style(h)
			impactLayers(p.style, h)
			currentAttacker = nil
		end
		-- hit stop: your own heavy hits and crits only (3 frames, 4 on a heavy crit)
		if p.attacker == player and (heavy or crit) then
			local target = if typeof(p.model) == "Instance" and p.model:IsA("Model") then p.model else nil
			BigHitFX.HitStop(target, if heavy and crit then 0.13 elseif heavy then 0.1 else 0.066)
		end
		if typeof(p.model) == "Instance" and p.model:IsA("Model") and FxBudget.Allow("hitFlash", 30) then
			-- (the Martial Artist's hits hold the white a beat longer)
			hitFlash(p.model, crit, if p.style == "fist" then 0.12 else nil)
		end
		if p.attacker == player and (heavy or crit) then
			shake(heavy and 0.35 or 0.2)
		end
	end)
end

return HitFX
