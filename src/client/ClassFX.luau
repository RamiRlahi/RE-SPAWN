--!strict
--[[
	ClassFX.luau
	Sound effects for every class's skills and basic attacks, plus an extra
	layer of VFX on top of each skill's existing effects: ground runes,
	shockwave rings, particle bursts, afterimages and rising motes. No
	PointLights: glow comes from Neon parts and light-emitting particles.

	Runs on every client for every caster (your casts and teammates'), so
	everyone hears and sees them. Called from SkillController:
	  ClassFX.Cast(char, classId, skillIndex, origin, dir, targetPos?, config)
	  ClassFX.Basic(char, classId, dir)

	All sounds are from Roblox's licensed ProSoundEffects library (free to use
	in any experience). Swap an id in SFX to change it everywhere.
--]]

local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local ClassFX = {}

local function id(n: number): string return "rbxassetid://" .. n end

local SFX = {
	whoosh = { id(9120742716), id(9120742729), id(9120742710), id(9120742903) }, -- Whoosh Thick Quick
	swordHit = { id(9119746592), id(9119746598), id(9119746751) },               -- Sword Hit
	fireBurst = { id(9117985933), id(9117987278), id(9117983605) },              -- Pyro Fire Ball Burst
	fireWhoosh = { id(9114446852), id(9114444008), id(9114444052) },             -- Fire Whoosh (short)
	quake = { id(9114224354) },                                                  -- Earthquake Explosion 1
	boom = { id(9125404320) },                                                   -- Boom Impact Deep Distant
	rockHit = { id(9118612665), id(9125869504) },                                -- Rock Impact / Cracks
	chime = { id(9116394545), id(9116395089), id(9116394876) },                  -- Magic Glows chiming hits
	magicBurst = { id(9116384485) },                                             -- Magic Burst 1
	poof = { id(9116406610), id(9125640290) },                                   -- Magic Poofs
	ding = { id(9126073001), id(9126073318) },                                   -- Synth Sparkle bell ding
	choir = { id(9114791989) },                                                  -- Heavenly Presence Choir Pad
	angel = { id(9113122077) },                                                  -- Angel Power Tone Accelerating
	iceCrack = { id(9114858761), id(9114858583), id(9114858605) },               -- Ice Cracks / Crackle
	iceBreak = { id(9125610574), id(9114590297) },                               -- Ice Break / Glass Break
	freeze = { id(9125611419), id(9125611312) },                                 -- Ice Freeze Liquid Nitro
	wind = { id(9113732197) },                                                   -- Cavernous Winds (faded)
	arrowOut = { id(9113166206), id(9113166362), id(9113166561) },               -- Arrow Out Whooshing
	arrowHit = { id(9113161857), id(9113158923), id(9113162463) },               -- Arrow In And Hit
	bowDraw = { id(9125407239), id(9125405163) },                                -- Bow Stretches Wood Creak
	leaves = { id(9116258071) },                                                 -- Leaves Rustle (faded)
	charge = { id(9125973433) },                                                 -- Energy Charge Up
	thunder = { id(9120016037) },                                                -- Thunder Cracks
	punch = { id(9117969687), id(9117969717) },                                  -- Punch Kit Beefy Hit
	clang = { id(9119072660), id(9119072674) },                                  -- Shield Clang (metal sword on metal)
	swordIn = { id(9119747260), id(9119747270) },                                -- Sword In (steel ring)
}

local rng = Random.new()

local function fxFolder(): Folder
	local f = Workspace:FindFirstChild("ClassFX")
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = "ClassFX"
	nf.Parent = Workspace
	return nf
end

-- A 3D sound at `at` (a part to follow, or a position). `fadeAfter` fades a
-- long clip out; `pitch` gets a small random wobble so repeats don't drone.
local function play(list: { string }, at: BasePart | Vector3, volume: number, pitch: number?, fadeAfter: number?)
	local parent: Instance
	if typeof(at) == "Vector3" then
		local anchor = Instance.new("Part")
		anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
		anchor.Transparency = 1
		anchor.Size = Vector3.one * 0.2
		anchor.Position = at
		anchor.Parent = fxFolder()
		Debris:AddItem(anchor, (fadeAfter or 6) + 2)
		parent = anchor
	else
		parent = at
	end
	local s = Instance.new("Sound")
	s.SoundId = list[rng:NextInteger(1, #list)]
	s.Volume = volume
	s.PlaybackSpeed = (pitch or 1) * rng:NextNumber(0.95, 1.05)
	s.RollOffMinDistance = 12
	s.RollOffMaxDistance = 140
	s.Parent = parent
	s:Play()
	if fadeAfter then
		task.delay(fadeAfter, function()
			if s.Parent then TweenService:Create(s, TweenInfo.new(0.8), { Volume = 0 }):Play() end
		end)
		Debris:AddItem(s, fadeAfter + 1)
	else
		s.Ended:Once(function() s:Destroy() end)
		Debris:AddItem(s, 12)
	end
end

local function later(t: number, f: () -> ())
	task.delay(t, f)
end

-- ── VFX building blocks (Neon + particles, no lights) ───────────────────────
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function neon(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = fxFolder()
	return p
end

local function groundY(pos: Vector3, ignore: Instance?): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local list: { Instance } = { fxFolder() }
	if ignore then table.insert(list, ignore) end
	params.FilterDescendantsInstances = list
	local hit = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position.Y else pos.Y - 3
end

-- Expanding flat shockwave ring (a thin disc edge that fades).
local function ring(pos: Vector3, color: Color3, radius: number, t: number, ignore: Instance?)
	local y = groundY(pos, ignore) + 0.15
	local r = neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 1, 1),
		CFrame = CFrame.new(pos.X, y, pos.Z) * FLAT, Color = color, Transparency = 0.15 })
	TweenService:Create(r, TweenInfo.new(t, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.05, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(r, t + 0.05)
end

-- A rune circle on the ground: a disc, a rim and rotating spokes that spin up
-- then fade.
local function rune(pos: Vector3, color: Color3, radius: number, life: number, ignore: Instance?)
	local y = groundY(pos, ignore) + 0.1
	local base = CFrame.new(pos.X, y, pos.Z)
	local disc = neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, radius * 2, radius * 2),
		CFrame = base * FLAT, Color = color, Transparency = 0.8 })
	local rim = neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, radius * 2.1, radius * 2.1),
		CFrame = base * CFrame.new(0, -0.01, 0) * FLAT, Color = color, Transparency = 0.55 })
	local spokes: { BasePart } = {}
	for i = 1, 6 do
		spokes[i] = neon({ Size = Vector3.new(0.18, 0.08, radius * 1.8), Color = color, Transparency = 0.35 })
	end
	local inner = neon({ Size = Vector3.new(radius * 0.9, 0.08, radius * 0.9), Color = color, Transparency = 0.5 })
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = game:GetService("RunService").RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > life then
			if conn then conn:Disconnect() end
			return
		end
		local spin = t * (1.5 + t * 2)
		for i, s in ipairs(spokes) do
			s.CFrame = base * CFrame.new(0, 0.05, 0) * CFrame.Angles(0, spin + i * math.pi / 6 * 2, 0)
		end
		inner.CFrame = base * CFrame.new(0, 0.06, 0) * CFrame.Angles(0, -spin * 1.5 + math.pi / 4, 0)
	end)
	local fade = TweenInfo.new(life * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, life * 0.6)
	for _, p in ipairs({ disc, rim, inner, table.unpack(spokes) }) do
		TweenService:Create(p, fade, { Transparency = 1 }):Play()
		Debris:AddItem(p, life + 0.1)
	end
end

-- One-shot particle burst at a position.
local function burst(pos: Vector3, color: Color3, count: number, speed: number, texture: string?, size: number?, life: number?)
	local anchor = neon({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = texture or TEX_SPARK
	e.Color = ColorSequence.new(Color3.new(1, 1, 1):Lerp(color, 0.4), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	local sz = size or 0.5
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, sz), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new((life or 0.6) * 0.6, life or 0.6)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Rate = 0
	e.Parent = anchor
	e:Emit(count)
	Debris:AddItem(anchor, (life or 0.6) + 0.3)
end

-- Motes that drift upward from a ground circle for `t` seconds.
local function motes(pos: Vector3, color: Color3, radius: number, t: number, ignore: Instance?)
	local y = groundY(pos, ignore)
	local anchor = neon({ Size = Vector3.new(radius * 2, 0.2, radius * 2), Transparency = 1, CFrame = CFrame.new(pos.X, y + 0.2, pos.Z) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SPARK
	e.Color = ColorSequence.new(color)
	e.LightEmission = 1
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(1, 1.8)
	e.Speed = NumberRange.new(2, 5)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(10, 10)
	e.Rate = 40
	e.Parent = anchor
	task.delay(t, function() e.Enabled = false end)
	Debris:AddItem(anchor, t + 2)
end

-- Glowing ghost copies of the character that fade in place (dash trails).
local function afterimages(char: Model, color: Color3, count: number, gap: number)
	for n = 0, count - 1 do
		task.delay(n * gap, function()
			if not char.Parent then return end
			for _, d in ipairs(char:GetChildren()) do
				if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
					local g = neon({ Size = d.Size, CFrame = d.CFrame, Color = color, Transparency = 0.45,
						Material = Enum.Material.ForceField })
					TweenService:Create(g, TweenInfo.new(0.45), { Transparency = 1 }):Play()
					Debris:AddItem(g, 0.5)
				end
			end
		end)
	end
end

-- A column of light that flashes and thins out.
local function pillar(pos: Vector3, color: Color3, width: number, height: number, t: number)
	local p = neon({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(height, width, width),
		CFrame = CFrame.new(pos + Vector3.new(0, height / 2, 0)) * FLAT, Color = color, Transparency = 0.2 })
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(height, 0.1, 0.1), Transparency = 1 }):Play()
	Debris:AddItem(p, t + 0.05)
end

-- ── Per class ───────────────────────────────────────────────────────────────
local FIRE = Color3.fromRGB(255, 120, 40)
local EMBER = Color3.fromRGB(255, 190, 90)
local NATURE = Color3.fromRGB(110, 230, 120)
local HOLY = Color3.fromRGB(255, 220, 120)
local FROST = Color3.fromRGB(150, 215, 255)
local BRASS = Color3.fromRGB(255, 200, 96)

type Ctx = { char: Model, root: BasePart, origin: Vector3, dir: Vector3, target: Vector3?, config: any }

local CAST: { [string]: { [number]: (Ctx) -> () } } = {}

CAST.ranger = {
	-- Verdant Slash: a dash through enemies.
	[1] = function(c)
		play(SFX.whoosh, c.root, 0.9, 1.2)
		play(SFX.leaves, c.root, 0.5, 1.2, 0.8)
		afterimages(c.char, NATURE, 4, 0.05)
		later(0.2, function() play(SFX.swordHit, c.root, 0.6, 1.2) end)
		burst(c.origin, NATURE, 30, 16, TEX_SPARK, 0.6, 0.6)
	end,
	-- Entangling Arrow.
	[2] = function(c)
		play(SFX.bowDraw, c.root, 0.6, 1.2)
		later(0.12, function() play(SFX.arrowOut, c.root, 0.8) end)
		local hit = c.target or (c.origin + c.dir * 30)
		later(0.45, function()
			play(SFX.arrowHit, hit, 0.8)
			play(SFX.leaves, hit, 0.6, 0.9, 1.2)
			rune(hit, NATURE, 5, 1.2, c.char)
		end)
	end,
	-- Seeker Barrage: a volley of loosed arrows.
	[3] = function(c)
		play(SFX.bowDraw, c.root, 0.6)
		local n = 3 + (c.config.projectileCount or 0)
		for i = 0, math.min(n, 8) - 1 do
			later(0.1 + i * 0.08, function() play(SFX.arrowOut, c.root, 0.55, 1.1) end)
		end
		burst(c.root.Position + Vector3.new(0, 1.5, 0), NATURE, 24, 12, TEX_SPARK, 0.5, 0.5)
	end,
	-- Rain of Arrows.
	[4] = function(c)
		play(SFX.bowDraw, c.root, 0.8, 0.9)
		play(SFX.leaves, c.root, 0.5, 1, 2)
		local area = c.target or (c.origin + c.dir * 30)
		rune(area, NATURE, 14, 3, c.char)
		later(0.3, function() play(SFX.arrowOut, c.root, 0.9, 0.8) end)
		for i = 0, 9 do
			later(1 + i * 0.12, function()
				local p = area + Vector3.new(rng:NextNumber(-10, 10), 0, rng:NextNumber(-10, 10))
				play(SFX.arrowHit, p, 0.5)
				burst(p + Vector3.new(0, 0.5, 0), NATURE, 8, 10, TEX_SPARK, 0.4, 0.4)
			end)
		end
		later(1, function() ring(area, NATURE, 16, 0.6, c.char) end)
	end,
}

CAST.cleric = {
	-- Heal.
	[1] = function(c)
		local at = c.target or c.origin
		play(SFX.chime, at, 0.8)
		play(SFX.ding, at, 0.4, 1.2)
		rune(at, HOLY, 5, 1.4, c.char)
		motes(at, HOLY, 3, 1, c.char)
	end,
	-- Divine Beam (a 5 s channel).
	[2] = function(c)
		play(SFX.charge, c.root, 0.5, 1.3)
		play(SFX.angel, c.root, 0.6, 1, c.config.duration or 5)
		for i = 0, 3 do
			later(0.3 + i * 1.1, function() ring(c.root.Position, HOLY, 7, 0.6, c.char) end)
		end
	end,
	-- Radiant Ground.
	[3] = function(c)
		play(SFX.magicBurst, c.origin, 0.8)
		play(SFX.chime, c.origin, 0.6, 0.9)
		later(0.24, function()
			local r = 16 * (c.config.areaMultiplier or 1)
			ring(c.origin, HOLY, r, 0.6, c.char)
			ring(c.origin, Color3.new(1, 1, 1), r * 0.6, 0.4, c.char)
			motes(c.origin, HOLY, r * 0.6, 1.5, c.char)
		end)
	end,
	-- Divine Ascent: choir through the cutscene, light, then the revive.
	[4] = function(c)
		local dur = c.config.duration or 5.5
		play(SFX.choir, c.root, 0.7, 1, dur - 0.5)
		rune(c.origin, HOLY, 12, dur, c.char)
		later(1.9, function()
			play(SFX.ding, c.root, 0.8, 0.8)
			pillar(c.origin, HOLY, 7, 60, 1.2)
		end)
		later(3.7, function()
			play(SFX.magicBurst, c.root, 1, 0.8)
			ring(c.origin, HOLY, 26, 0.8, c.char)
			motes(c.origin, HOLY, 10, 1.5, c.char)
		end)
	end,
}

CAST.ice_mage = {
	-- Ice Spikes: a line of cracking spikes.
	[1] = function(c)
		local delay = c.config.castDelay or 0.16
		later(delay, function()
			for i = 0, 4 do
				later(i * 0.08, function()
					local p = c.origin + c.dir * (6 + i * 7)
					play(SFX.iceCrack, p, 0.55, 1 + i * 0.05)
					burst(p, FROST, 10, 12, TEX_SPARK, 0.5, 0.5)
				end)
			end
			ring(c.origin, FROST, 7, 0.4, c.char)
		end)
	end,
	-- Ice Beam.
	[2] = function(c)
		local dur = c.config.duration or 3
		play(SFX.freeze, c.root, 0.7, 1.1, dur)
		play(SFX.wind, c.root, 0.4, 1.4, dur)
		rune(c.origin, FROST, 5, dur, c.char)
	end,
	-- Ice Clone.
	[3] = function(c)
		later(c.config.castDelay or 0.2, function()
			play(SFX.freeze, c.root, 0.6, 1.3, 1.2)
			play(SFX.iceCrack, c.root, 0.6)
			afterimages(c.char, FROST, 2, 0.08)
			burst(c.root.Position, FROST, 30, 14, TEX_SPARK, 0.6, 0.6)
		end)
	end,
	-- Blizzard: the reveal, then the storm breaks.
	[4] = function(c)
		local reveal = c.config.castDelay or 1.5
		local dur = c.config.duration or 6
		play(SFX.freeze, c.root, 0.6, 0.8, reveal)
		rune(c.origin, FROST, 10, reveal + 0.5, c.char)
		later(reveal, function()
			play(SFX.iceBreak, c.origin, 1, 0.8)
			play(SFX.wind, c.origin, 0.9, 1, dur)
			ring(c.origin, FROST, (c.config.range or 48) * (c.config.areaMultiplier or 1), 0.9, c.char)
			burst(c.origin + Vector3.new(0, 2, 0), FROST, 80, 40, TEX_SPARK, 0.9, 1)
		end)
	end,
}

-- The Gunslinger already has its own sounds (GunslingerController); these
-- only add visuals.
CAST.gunslinger = {
	[1] = function(c)
		-- Fan the Hammer: spent brass casings spilling from the cylinder.
		for i = 0, 5 do
			later(i * 0.075, function()
				if not c.char.Parent then return end
				local p = c.root.Position + c.root.CFrame.RightVector * 1.2 + Vector3.new(0, 1.2, 0)
				local casing = neon({ Size = Vector3.new(0.12, 0.12, 0.3), CFrame = CFrame.new(p), Color = BRASS, Material = Enum.Material.Metal })
				local out = c.root.CFrame.RightVector * rng:NextNumber(2, 4) + Vector3.new(rng:NextNumber(-1, 1), 0, rng:NextNumber(-1, 1))
				TweenService:Create(casing, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
					CFrame = CFrame.new(Vector3.new(p.X + out.X, groundY(p, c.char) + 0.1, p.Z + out.Z)) * CFrame.Angles(rng:NextNumber(0, 6), rng:NextNumber(0, 6), 0),
				}):Play()
				Debris:AddItem(casing, 1.6)
			end)
		end
	end,
	[2] = function(c)
		afterimages(c.char, BRASS, 4, 0.05)
		ring(c.origin, BRASS, 6, 0.35, c.char)
	end,
	[3] = function(c)
		burst(c.root.Position + Vector3.new(0, 2, 0), BRASS, 16, 10, TEX_SPARK, 0.4, 0.5)
	end,
	[4] = function(c)
		ring(c.origin, BRASS, 14, 0.8, c.char)
	end,
}

-- The Swordsman: cast sounds here; hit / parry / storm sounds and all its
-- VFX play from the server's SwordsmanFX moments (SwordsmanController).
CAST.swordsman = {
	[1] = function(c)
		play(SFX.whoosh, c.root, 0.9, 1.25)
		play(SFX.swordIn, c.root, 0.5, 1.2)
	end,
	[2] = function(c)
		play(SFX.swordIn, c.root, 0.7, 0.9)
	end,
	[3] = function(c)
		local dur = c.config.duration or 1.2
		local t = 0
		while t < dur do
			later(t, function() if c.char.Parent then play(SFX.whoosh, c.root, 0.6, 1.3) end end)
			t += 0.2
		end
	end,
	[4] = function(c)
		play(SFX.swordIn, c.root, 1, 0.7)
		play(SFX.rockHit, c.root, 0.8, 0.8)
		play(SFX.charge, c.root, 0.5, 1.4)
	end,
}

function ClassFX.Cast(char: Model, classId: string, skillIndex: number, origin: Vector3, dir: Vector3, target: Vector3?, config: any)
	local fns = CAST[classId]
	local fn = fns and fns[skillIndex]
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not fn or not root then return end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	local ctx: Ctx = { char = char, root = root, origin = origin,
		dir = if flat.Magnitude > 0.01 then flat.Unit else root.CFrame.LookVector,
		target = target, config = config or {} }
	task.spawn(function()
		local ok, err = pcall(fn, ctx)
		if not ok then warn("[ClassFX]", classId, skillIndex, err) end
	end)
end

-- Basic attacks (the Gunslinger's revolver has its own).
function ClassFX.Basic(char: Model, classId: string, _dir: Vector3?)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	if classId == "heavy_knight" then
		play(SFX.whoosh, root, 0.6, 0.95)
	elseif classId == "ranger" then
		play(SFX.arrowOut, root, 0.5, 1.15)
	elseif classId == "cleric" then
		play(SFX.poof, root, 0.5, 1.2)
		play(SFX.chime, root, 0.25, 1.4)
	elseif classId == "ice_mage" then
		play(SFX.iceCrack, root, 0.4, 1.4)
	end
end

-- Building blocks shared with class controllers (e.g. SwordsmanController).
function ClassFX.Sound(key: string, at: BasePart | Vector3, volume: number, pitch: number?, fadeAfter: number?)
	local list = SFX[key]
	if list then play(list, at, volume, pitch, fadeAfter) end
end
ClassFX.Ring = ring
ClassFX.Burst = burst
ClassFX.Afterimages = afterimages
ClassFX.Pillar = pillar
ClassFX.Neon = neon
ClassFX.Folder = fxFolder
ClassFX.TEX_SPARK = TEX_SPARK

return ClassFX
