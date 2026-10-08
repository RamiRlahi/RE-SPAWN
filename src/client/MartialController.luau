--!strict
--[[
	MartialController.luau
	Client side of the Martial Artist (server: MartialServer), after the class
	sheet: golden Qi, dragons of living flame, a crimson blindfold and sash
	streaming behind him.

	  • Your own strikes, channels and leaps start at once on your screen; the
	    server decides the hits and sends every Martial Artist's moments to
	    everyone over MartialFX.
	  • The band and sash tails sway and stream as he moves, and his fists
	    leave streaks of Qi when they strike (every Martial Artist, every
	    client).
	  • The Qi Charge orbs over the skill bar fill one by one (MA_Charge; full
	    = the next ability is EMPOWERED, and his fists burn).

	The effects (one RenderStepped loop runs them all, `animate`):
	  dragon        a Chinese dragon of golden Qi: a horned head with brows,
	                frills, glowing eyes and an open jaw of teeth; a body of
	                flowing flame (layered ribbons of light following the
	                head's path, two strands spiralling round them, fire
	                pouring off it), a crest of fins, two pairs of claws, and
	                a streaming mane, beard and whiskers (Dragon Fist, Dragon
	                Ascent, Empowered Qi Release, and the colossal Dragon Soul)
	  swirl         streaks of Qi orbiting him (Qi Release)
	  the pack      ReplicatedStorage.VFXPack effects recoloured gold
	                (PackFX): impacts, explosions, cracks, smoke, fire
	Per-hit effects go through FxBudget.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local PackFX = require(script.Parent:WaitForChild("PackFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))

local player = Players.LocalPlayer

local MartialController = {}

-- ── Tuning (matches MartialServer) ──────────────────────────────────────────
local COMBO_INTERVAL = 0.3
local COMBO_RESET = 1.0
local CHARGE_MAX = 100
local FIST_CHANNEL = 0.3
local ASCENT = { rise = 0.24, dash = 0.22, fall = 0.12 }
local ASCENT_HEIGHT = 7
local SOUL_TOTAL = 3.6
local LUNGE = { 0.8, 0.8, 0.6, 1.8 } -- how far each strike of the combo steps in

local GOLD = Color3.fromRGB(255, 176, 60)
local BRIGHT = Color3.fromRGB(255, 228, 156)
local EMBER = Color3.fromRGB(255, 112, 26)
local WHITE = Color3.new(1, 1, 1)
local ROCK = Color3.fromRGB(58, 52, 50)

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_FIRE = "rbxasset://textures/particles/fire_main.dds"
local TEX_WISPS = "rbxassetid://9541055154"  -- (the pack's beam textures: wavy wisps of flame,
local TEX_FLICKER = "rbxassetid://10365550877" -- and flickering streaks of energy)

type Deps = { shake: (number, number) -> (), fovPunch: (number, number) -> (), getAim: (BasePart) -> Vector3 }
local deps: Deps

local lastSwing = 0
local step = 0
local busyUntil = 0

local function isMartial(p: Player?): boolean
	return (p or player):GetAttribute("SelectedClass") == "martial_artist"
end

local function charOf(p: any): Model?
	return if typeof(p) == "Instance" and p:IsA("Player") then p.Character else nil
end

local function rootOf(char: Model?): BasePart?
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function near(pos: Vector3, reach: number): boolean
	local r = rootOf(player.Character)
	return r ~= nil and (r.Position - pos).Magnitude < reach
end

local function part(props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = ClassFX.Folder()
	return p
end

-- An invisible anchored point to hang trails and emitters on.
local function carrier(cf: CFrame): BasePart
	return part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = cf })
end

-- ── One loop for every running effect ───────────────────────────────────────
-- `fn(a, dt)` gets 0..1 over `dur` (called a last time with a = 1); it can
-- return true to finish early.
local running: { { t0: number, dur: number, fn: (number, number) -> boolean? } } = {}
local function animate(dur: number, fn: (number, number) -> boolean?)
	table.insert(running, { t0 = os.clock(), dur = math.max(dur, 0.01), fn = fn })
end
local function stepAnims(dt: number)
	local now = os.clock()
	for i = #running, 1, -1 do
		local r = running[i]
		local a = math.min((now - r.t0) / r.dur, 1)
		local ok, res = pcall(r.fn, a, dt)
		if not ok then warn("[MartialController] fx:", res) end
		if a >= 1 or not ok or res == true then table.remove(running, i) end
	end
end

local function easeOut(a: number): number return 1 - (1 - a) ^ 3 end
local function easeIn(a: number): number return a * a end

local function groundY(pos: Vector3): number
	return FireFX.GroundY(pos)
end

local function onGround(pos: Vector3): Vector3
	return Vector3.new(pos.X, groundY(pos), pos.Z)
end

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- ── Small pieces of light ───────────────────────────────────────────────────
local function floorRing(pos: Vector3, radius: number, life: number, color: Color3?, width: number?)
	SwordFX.Arc({ cf = CFrame.new(pos + Vector3.new(0, 0.15, 0)), radius = radius * 0.6, arc = 359, width = width or 0.9,
		color = color or GOLD, life = life, draw = 0.001, grow = 0.7, core = BRIGHT })
end

local function flare(pos: Vector3, size: number, life: number, color: Color3?)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.3, CFrame = CFrame.new(pos), Color = color or BRIGHT, Transparency = 0.1 })
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size, Transparency = 1, Color = EMBER }):Play()
	Debris:AddItem(b, life + 0.05)
end

-- A shell of energy swelling out (the 3D shockwave).
local function shell(pos: Vector3, from: number, to: number, life: number, color: Color3?)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * from, CFrame = CFrame.new(pos), Color = color or GOLD,
		Material = Enum.Material.ForceField })
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * to, Transparency = 1 }):Play()
	Debris:AddItem(b, life + 0.05)
end

local function sparks(pos: Vector3, count: number, speed: number, color: Color3?)
	ClassFX.Burst(pos, color or GOLD, count, speed, ClassFX.TEX_SPARK, 0.35, 0.5)
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function nseq(...: number): NumberSequence
	local v = { ... }
	if #v == 2 then return NumberSequence.new(v[1], v[2]) end
	local kps = {}
	for i = 1, #v, 2 do table.insert(kps, NumberSequenceKeypoint.new(v[i], v[i + 1])) end
	return NumberSequence.new(kps)
end

-- A ribbon of light following `on` as it moves (a Trail between two points
-- `width` apart across it, always turned to the camera).
local function ribbon(on: BasePart, at: Vector3, width: number, life: number, colors: ColorSequence, transp: NumberSequence,
	taper: NumberSequence?, texture: string?, texLength: number?, emission: number?): Trail
	local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
	a0.Position, a1.Position = at + Vector3.new(0, width / 2, 0), at - Vector3.new(0, width / 2, 0)
	a0.Parent, a1.Parent = on, on
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = colors
	t.Transparency = transp
	t.LightEmission = emission or 1
	t.LightInfluence = 0
	t.FaceCamera = true
	t.Lifetime = life
	t.MinLength = 0.02
	if taper then t.WidthScale = taper end
	if texture then
		-- (tiled along the path in the world, so the body flows through it)
		t.Texture = texture
		t.TextureMode = Enum.TextureMode.Wrap
		t.TextureLength = texLength or 4
	end
	t.Parent = on
	return t
end

-- A slash of Qi from a to b: a streak that flares and fades.
local function streak(a: Vector3, b: Vector3, width: number, life: number, color: Color3?)
	SwordFX.Streak(a, b, width, color or GOLD, life, nil, BRIGHT)
end

-- The world warmed and dimmed a little (the Dragon Soul).
local function tint(seconds: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "MartialSoul"
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.4), { Brightness = -0.1, Contrast = 0.18, Saturation = 0.12,
		TintColor = Color3.fromRGB(255, 222, 180) }):Play()
	task.delay(seconds, function()
		TweenService:Create(cc, TweenInfo.new(0.6), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }):Play()
		Debris:AddItem(cc, 0.65)
	end)
end

local function flash(t: number, from: number?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "MartialFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = BRIGHT
	f.BackgroundTransparency = from or 0.3
	f.BorderSizePixel = 0
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, t + 0.05)
end

-- Rubble torn up off the floor round `center`: chunks of rock that rise and
-- hang turning in the air (the Dragon Soul's summoning) until thrown.
type Rubble = { parts: { BasePart }, home: { Vector3 }, spin: { CFrame }, throw: (Vector3) -> (), drop: () -> () }
local function rubble(center: Vector3, count: number, radius: number, rise: number): Rubble
	local parts, home, spins = {}, {}, {}
	for k = 1, count do
		local a = k / count * math.pi * 2 + math.random() * 0.5
		local r = radius * (0.45 + math.random() * 0.55)
		local g = onGround(center + Vector3.new(math.cos(a) * r, 0, math.sin(a) * r))
		local s = 0.5 + math.random() * 1.2
		local p = part({ Size = Vector3.new(s, s * (0.6 + math.random() * 0.5), s * (0.7 + math.random() * 0.4)), Color = ROCK,
			Material = Enum.Material.Slate, CFrame = CFrame.new(g) * CFrame.Angles(math.random() * 6, math.random() * 6, 0) })
		table.insert(parts, p)
		table.insert(home, g + Vector3.new(0, 1.2 + math.random() * rise, 0))
		table.insert(spins, CFrame.Angles(math.random() * 0.03, math.random() * 0.04, math.random() * 0.03))
	end
	local state = "rise"
	local vel: { Vector3 } = {}
	local t0 = os.clock()
	animate(8, function(a, dt)
		if state == "gone" then return true end
		local t = os.clock() - t0
		for i, p in ipairs(parts) do
			if not p.Parent then continue end
			if state == "rise" then
				local u = math.min(t / 0.9, 1)
				local target = home[i] + Vector3.new(0, math.sin(t * 2 + i) * 0.25, 0)
				p.CFrame = (CFrame.new(p.Position:Lerp(target, math.min(dt * 3 * (0.4 + u), 1))) * p.CFrame.Rotation) * spins[i]
			else
				vel[i] += Vector3.new(0, -70 * dt, 0)
				p.CFrame = CFrame.new(p.Position + vel[i] * dt) * p.CFrame.Rotation * spins[i] * spins[i]
			end
		end
		if a >= 1 then
			for _, p in ipairs(parts) do p:Destroy() end
		end
		return nil
	end)
	local function fade()
		for _, p in ipairs(parts) do
			TweenService:Create(p, TweenInfo.new(0.5), { Transparency = 1 }):Play()
			Debris:AddItem(p, 0.55)
		end
		task.delay(0.6, function() state = "gone" end)
	end
	return {
		parts = parts,
		home = home,
		spin = spins,
		-- thrown along `dir`, scattering
		throw = function(dir: Vector3)
			state = "thrown"
			for i in ipairs(parts) do
				vel[i] = dir * (30 + math.random() * 30) + Vector3.new((math.random() - 0.5) * 20, 18 + math.random() * 22, (math.random() - 0.5) * 20)
			end
			task.delay(1.1, fade)
		end,
		drop = function()
			state = "thrown"
			for i in ipairs(parts) do vel[i] = Vector3.new(0, -2, 0) end
			task.delay(0.6, fade)
		end,
	}
end

-- ── The dragon ──────────────────────────────────────────────────────────────
-- A Chinese dragon of golden Qi, `scale` big. Its body is flame: layered
-- ribbons of light that follow the path its head takes (as long as `life`
-- seconds of that path), two strands spiralling round them, fire pouring off
-- the head and lying along the path; plates down its spine, a crest of fins
-- and two pairs of claws ride the same path. Move it with move(pos, look)
-- every frame. set(alpha) fades it, jaw(k) opens the mouth (0..1),
-- destroy() clears it away (what it left on the path burns out on its own).
type Dragon = {
	move: (Vector3, Vector3) -> (),
	set: (number) -> (),
	jaw: (number) -> (),
	destroy: () -> (),
	head: () -> CFrame,
}

local HEAD = 1.55 -- (the head, big against the body as on the sheet)

local function newDragon(scale: number, start: Vector3, look: Vector3, life: number): Dragon
	local s = scale
	local hs = scale * HEAD
	local parts: { BasePart } = {}
	local base: { number } = {} -- each part's own transparency at full alpha
	local function add(p: BasePart, tr: number): BasePart
		table.insert(parts, p)
		table.insert(base, tr)
		p.Transparency = 1
		return p
	end
	-- The head (in its own frame, looking down -Z).
	local headParts: { BasePart } = {}
	local headRel: { CFrame } = {}
	local jawParts: { BasePart } = {}
	local jawRel: { CFrame } = {} -- relative to the hinge
	local function piece(size: Vector3, rel: CFrame, color: Color3, tr: number, onJaw: boolean?)
		local p = add(part({ Size = size * hs, Color = color }), tr)
		local cf = CFrame.new(rel.Position * hs) * rel.Rotation
		if onJaw then
			table.insert(jawParts, p)
			table.insert(jawRel, cf)
		else
			table.insert(headParts, p)
			table.insert(headRel, cf)
		end
	end
	local R = math.rad
	-- (the head in a deeper orange-gold, so it doesn't bloom into a blob:
	-- the bright ridges, horns, eyes and teeth stand out against it)
	local HIDE = Color3.fromRGB(232, 128, 26)
	local MOUTH = Color3.fromRGB(150, 30, 12)
	piece(Vector3.new(1.3, 1.0, 1.5), CFrame.new(0, 0.05, 0.1), HIDE, 0.02)                                       -- skull
	piece(Vector3.new(0.95, 0.5, 1.4), CFrame.new(0, -0.05, -1.25), HIDE, 0.02)                                   -- snout
	piece(Vector3.new(0.5, 0.16, 1.35), CFrame.new(0, 0.24, -1.2), BRIGHT, 0.05)                                  -- the ridge of the nose
	piece(Vector3.new(0.75, 0.36, 0.26), CFrame.new(0, 0.04, -1.98), BRIGHT, 0.02)                                -- nose pad
	for _, sx in ipairs({ -1, 1 }) do
		piece(Vector3.new(0.38, 0.16, 0.75), CFrame.new(sx * 0.42, 0.55, -0.38) * CFrame.Angles(R(-14), 0, R(sx * -16)), BRIGHT, 0.02) -- brows
		piece(Vector3.new(0.3, 0.14, 0.26), CFrame.new(sx * 0.48, 0.3, -0.52), WHITE, 0)                         -- eyes
		piece(Vector3.new(0.18, 0.18, 1.9), CFrame.new(sx * 0.38, 0.62, 0.8) * CFrame.Angles(R(-28), R(sx * 14), 0), BRIGHT, 0.02) -- horns
		piece(Vector3.new(0.12, 0.12, 0.8), CFrame.new(sx * 0.5, 0.98, 0.72) * CFrame.Angles(R(-62), R(sx * 26), 0), BRIGHT, 0.02)  -- their branches
		for k = 0, 2 do                                                                                           -- cheek frills
			piece(Vector3.new(0.07, 0.7 - k * 0.12, 0.3), CFrame.new(sx * 0.68, -0.05, 0.15 + k * 0.22)
				* CFrame.Angles(R(-25 - k * 12), 0, R(sx * -(55 + k * 18))) * CFrame.new(0, 0.3, 0), GOLD, 0.12)
		end
		for k = 0, 2 do                                                                                           -- upper teeth
			piece(Vector3.new(0.08, 0.24, 0.08), CFrame.new(sx * (0.28 + k * 0.06), -0.36, -1.82 + k * 0.28), WHITE, 0)
		end
		for k = 0, 1 do                                                                                           -- lower teeth
			piece(Vector3.new(0.08, 0.2, 0.08), CFrame.new(sx * (0.26 + k * 0.06), 0.18, -1.3 + k * 0.3), WHITE, 0, true)
		end
	end
	piece(Vector3.new(0.88, 0.22, 1.45), CFrame.new(0, 0, -0.75), HIDE, 0.02, true)                                -- lower jaw
	piece(Vector3.new(0.6, 0.1, 1.25), CFrame.new(0, 0.12, -0.75), MOUTH, 0, true)                                -- inside the mouth
	piece(Vector3.new(0.7, 0.08, 1.1), CFrame.new(0, -0.3, -1.25), MOUTH, 0)                                      -- the roof of it
	local HINGE = CFrame.new(0, -0.32 * hs, -0.25 * hs)
	local jawOpen = 0.4

	-- The spine: plates, a crest of fins, two pairs of claws, riding the
	-- path the head has taken (by time, so they match the ribbons).
	local PLATES = 11
	local plates: { BasePart } = {}
	local fins: { BasePart } = {}
	local claws: { BasePart } = {}
	local clawAt: { number } = {}  -- which plate each claw rides
	local clawRel: { CFrame } = {}
	for k = 1, PLATES do
		local u = k / (PLATES + 1)
		local w = s * (0.85 - 0.55 * u)
		table.insert(plates, add(part({ Size = Vector3.new(w * 0.8, w * 0.8, 0.14 * s), Color = Color3.fromRGB(232, 128, 26):Lerp(EMBER, u) }), 0.5 + u * 0.35))
		if k % 2 == 1 then
			-- (a crest standing up out of the flame)
			table.insert(fins, add(part({ Size = Vector3.new(0.07 * s, w * 1.3, w * 0.9), Color = BRIGHT }), 0.1 + u * 0.45))
		end
	end
	for _, at in ipairs({ 3, 7 }) do
		for _, sx in ipairs({ -1, 1 }) do
			local w = s * (0.85 - 0.55 * at / (PLATES + 1))
			-- the leg, reaching down out of the flame, then three talons splayed
			table.insert(claws, add(part({ Size = Vector3.new(0.18, 1.3, 0.18) * s, Color = GOLD }), 0.05))
			table.insert(clawAt, at)
			table.insert(clawRel, CFrame.new(sx * w * 0.7, -w * 0.4, 0) * CFrame.Angles(R(-35), 0, R(sx * 32)) * CFrame.new(0, -0.65 * s, 0))
			for t = -1, 1 do
				table.insert(claws, add(part({ Size = Vector3.new(0.09, 0.09, 0.6) * s, Color = WHITE }), 0))
				table.insert(clawAt, at)
				table.insert(clawRel, CFrame.new(sx * (w * 0.7 + 0.72 * s), -w * 0.4 - 1.0 * s, -0.55 * s) * CFrame.Angles(R(25), R(t * 32), 0)
					* CFrame.new(0, 0, -0.25 * s))
			end
		end
	end

	-- The body of flame: ribbons trailing the head.
	local core = headParts[1]
	local behind = Vector3.new(0, 0, 0.7 * hs)
	local trails: { Trail } = {}
	local trailBase: { NumberSequence } = {}
	local function body(t: Trail)
		table.insert(trails, t)
		table.insert(trailBase, t.Transparency)
	end
	-- (a deep orange under-layer that keeps it saturated, then the flame
	-- itself, wisps flowing through it, then flickering energy, then a thin
	-- bright line down the middle)
	body(ribbon(core, behind, 2.3 * s, life, ColorSequence.new(EMBER, Color3.fromRGB(180, 50, 10)), nseq(0, 0.45, 0.7, 0.65, 1, 1),
		nseq(0, 1, 0.7, 0.8, 1, 0.2), nil, nil, 0.25))
	body(ribbon(core, behind, 1.75 * s, life, ColorSequence.new({ ColorSequenceKeypoint.new(0, BRIGHT), ColorSequenceKeypoint.new(0.5, GOLD),
		ColorSequenceKeypoint.new(1, EMBER) }), nseq(0, 0.05, 0.75, 0.35, 1, 1), nseq(0, 1, 0.8, 0.7, 1, 0.12), TEX_WISPS, 5 * s, 0.85))
	body(ribbon(core, behind, 1.2 * s, life * 0.9, ColorSequence.new(BRIGHT, GOLD), nseq(0, 0.25, 1, 1), nseq(0, 1, 1, 0.15), TEX_FLICKER, 3 * s, 1))
	body(ribbon(core, behind, 0.22 * s, life * 0.8, ColorSequence.new(WHITE, BRIGHT), nseq(0, 0.3, 1, 1), nseq(0, 1, 1, 0.2)))
	-- two strands spiralling round the body (carried round the head's axis)
	local strands: { BasePart } = {}
	for _ = 1, 2 do
		local c = carrier(CFrame.new(start))
		table.insert(strands, c)
		body(ribbon(c, Vector3.zero, 0.26 * s, life * 0.9, ColorSequence.new(BRIGHT, EMBER), nseq(0, 0.15, 1, 1), nseq(0, 1, 1, 0.3), nil, nil, 0.8))
	end
	-- the mane streaming back off the head, the beard, the whiskers
	for _, at in ipairs({ Vector3.new(0, 0.6, 0.5), Vector3.new(-0.55, 0.35, 0.6), Vector3.new(0.55, 0.35, 0.6) }) do
		body(ribbon(core, at * hs, 0.5 * hs, life * 0.35, ColorSequence.new(BRIGHT, EMBER), nseq(0, 0.1, 1, 1), nseq(0, 1, 1, 0.1), TEX_WISPS, 2 * hs, 0.9))
	end
	local snout = headParts[2]
	body(ribbon(snout, Vector3.new(0, -0.35, 0.2) * hs, 0.3 * hs, life * 0.25, ColorSequence.new(BRIGHT, GOLD), nseq(0, 0.2, 1, 1), nseq(0, 1, 1, 0)))
	for _, sx in ipairs({ -1, 1 }) do
		body(ribbon(snout, Vector3.new(sx * 0.5, -0.1, -0.5) * hs, 0.07 * hs, life * 0.5, ColorSequence.new(WHITE, BRIGHT), nseq(0, 0.05, 1, 1)))
	end
	-- fire pouring off the head, lying along the path; motes of light
	local fire = emitter(core, { Texture = TEX_FIRE, Color = ColorSequence.new(GOLD, EMBER), LightEmission = 0.7,
		Size = nseq(0, 1.6 * s, 1, 0.3 * s), Transparency = nseq(0, 0.35, 1, 1), Lifetime = NumberRange.new(life * 0.6, life),
		Speed = NumberRange.new(0.5, 2.5), SpreadAngle = Vector2.new(30, 30), EmissionDirection = Enum.NormalId.Back,
		Rate = 50, RotSpeed = NumberRange.new(-150, 150), Rotation = NumberRange.new(0, 360), Drag = 2 })
	local motes = emitter(core, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, GOLD), LightEmission = 1,
		Size = nseq(0, 0.45 * s, 1, 0), Transparency = nseq(0, 0, 1, 1), Lifetime = NumberRange.new(life * 0.8, life * 1.4),
		Speed = NumberRange.new(1, 4), SpreadAngle = Vector2.new(180, 180), Rate = 30 })
	if FxBudget.Light() then
		local l = Instance.new("PointLight")
		l.Color = GOLD
		l.Brightness = 2.5
		l.Range = 10 * math.min(s, 2.5)
		l.Parent = core
		FxBudget.TrackLight(l)
	end

	-- Where the head has been, newest first, by time.
	local hist: { { t: number, p: Vector3 } } = { { t = os.clock(), p = start } }
	local headCF = CFrame.lookAt(start, start + (if look.Magnitude > 0.01 then look else Vector3.zAxis))
	local alive = true
	local spin = 0
	local all: { BasePart } = {}
	for _, p in ipairs(headParts) do table.insert(all, p) end
	for _, p in ipairs(jawParts) do table.insert(all, p) end
	for _, p in ipairs(plates) do table.insert(all, p) end
	for _, p in ipairs(fins) do table.insert(all, p) end
	for _, p in ipairs(claws) do table.insert(all, p) end
	for _, p in ipairs(strands) do table.insert(all, p) end
	local cfs = table.create(#all)

	-- Where the head was `age` seconds ago, and which way it was going.
	local function past(age: number): (Vector3, Vector3)
		local want = os.clock() - age
		for i = 1, #hist - 1 do
			local a, b = hist[i], hist[i + 1]
			if b.t <= want then
				local k = if a.t > b.t then (a.t - want) / (a.t - b.t) else 0
				local d = a.p - b.p
				return a.p:Lerp(b.p, math.clamp(k, 0, 1)), if d.Magnitude > 0.001 then d.Unit else headCF.LookVector
			end
		end
		local last = hist[#hist]
		local d = if #hist > 1 then hist[#hist - 1].p - last.p else headCF.LookVector
		return last.p, if d.Magnitude > 0.001 then d.Unit else headCF.LookVector
	end

	local function place()
		local n = 0
		for _, rel in ipairs(headRel) do
			n += 1
			cfs[n] = headCF * rel
		end
		local hinge = headCF * HINGE * CFrame.Angles(math.rad(-(6 + 34 * jawOpen)), 0, 0)
		for _, rel in ipairs(jawRel) do
			n += 1
			-- (relative to the hinge: back out of the head frame first)
			cfs[n] = hinge * HINGE:Inverse() * rel
		end
		local plateCF = {}
		for k = 1, PLATES do
			local p, d = past(life * 0.92 * k / (PLATES + 1))
			-- (a slow roll along the body, so it reads as round)
			local cf = CFrame.lookAt(p, p + d, if math.abs(d.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis) * CFrame.Angles(0, 0, math.rad(45))
			plateCF[k] = cf * CFrame.Angles(0, 0, math.rad(-45))
			n += 1
			cfs[n] = cf
		end
		for k = 1, PLATES do
			if k % 2 == 1 then
				local u = k / (PLATES + 1)
				n += 1
				cfs[n] = plateCF[k] * CFrame.new(0, s * (0.85 - 0.55 * u) * 1.05, 0)
			end
		end
		for i, rel in ipairs(clawRel) do
			n += 1
			cfs[n] = plateCF[clawAt[i]] * rel
		end
		for i in ipairs(strands) do
			n += 1
			cfs[n] = headCF * CFrame.new(behind) * CFrame.Angles(0, 0, spin + i * math.pi) * CFrame.new(0, 0.95 * s, 0)
		end
		Workspace:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	end

	local alphaNow = -1
	local d: Dragon = {
		move = function(pos: Vector3, lookDir: Vector3)
			if not alive then return end
			local lv = if lookDir.Magnitude > 0.01 then lookDir.Unit else headCF.LookVector
			headCF = CFrame.lookAt(pos, pos + lv, if math.abs(lv.Y) > 0.95 then Vector3.xAxis else Vector3.yAxis)
			local now = os.clock()
			spin += 0.35
			table.insert(hist, 1, { t = now, p = pos })
			for i = #hist, 2, -1 do
				if now - hist[i - 1].t > life + 0.1 then hist[i] = nil else break end
			end
			place()
		end,
		set = function(alpha: number)
			if math.abs(alpha - alphaNow) < 0.02 then return end
			alphaNow = alpha
			for i, p in ipairs(parts) do
				p.Transparency = base[i] + (1 - base[i]) * (1 - alpha)
			end
			for i, t in ipairs(trails) do
				local kps = {}
				for _, kp in ipairs(trailBase[i].Keypoints) do
					table.insert(kps, NumberSequenceKeypoint.new(kp.Time, 1 - (1 - kp.Value) * alpha))
				end
				t.Transparency = NumberSequence.new(kps)
			end
			fire.Enabled = alpha > 0.3
			motes.Enabled = alpha > 0.3
		end,
		jaw = function(k: number) jawOpen = math.clamp(k, 0, 1) end,
		destroy = function()
			if not alive then return end
			alive = false
			fire.Enabled = false
			motes.Enabled = false
			for _, t in ipairs(trails) do t.Enabled = false end
			-- (the parts holding the ribbons and the fire stay, unseen, till
			-- what they left on the path has burnt out)
			for _, p in ipairs(parts) do
				if p == core or p == snout then
					p.Transparency = 1
					Debris:AddItem(p, life + 0.3)
				else
					p:Destroy()
				end
			end
			for _, c in ipairs(strands) do Debris:AddItem(c, life + 0.3) end
		end,
		head = function() return headCF end,
	}
	d.set(0)
	place()
	return d
end

-- ── Every Martial Artist: the tails, the fist streaks ───────────────────────
type Rig = { motors: { Motor6D }, phase: { number }, band: { boolean }, fists: { Trail } }
local rigs: { [Model]: Rig } = {}

local function rigOf(char: Model): Rig?
	local r = rigs[char]
	if r and r.motors[1] and r.motors[1].Parent then return r end
	local gi = char:FindFirstChild("MartialGi")
	if not gi then return nil end
	local nr: Rig = { motors = {}, phase = {}, band = {}, fists = {} }
	for _, d in ipairs(gi:GetDescendants()) do
		if d:IsA("Motor6D") and string.sub(d.Name, -5) == "Motor" then
			table.insert(nr.motors, d)
			table.insert(nr.phase, math.random() * 6)
			table.insert(nr.band, string.sub(d.Name, 1, 4) == "Band")
		end
	end
	if #nr.motors == 0 then return nil end
	-- a streak of Qi off each fist and the right foot (lit only while they strike)
	for _, side in ipairs({ "Right Arm", "Left Arm", "Right Leg" }) do
		local limb = char:FindFirstChild(side) :: BasePart?
		if limb then
			local old = limb:FindFirstChild("MartialFistTrail")
			if old then old:Destroy() end
			local t = ribbon(limb, Vector3.new(0, -0.95, 0), if side == "Right Leg" then 0.8 else 0.6, 0.18,
				ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.35, BRIGHT), ColorSequenceKeypoint.new(1, EMBER) }),
				nseq(0, 0, 1, 1), nseq(0, 1, 1, 0.2))
			t.Name = "MartialFistTrail"
			t.Enabled = false
			table.insert(nr.fists, t)
		end
	end
	rigs[char] = nr
	return nr
end

-- Light the streaks for `seconds` (`which`: "R", "L", "both" fists, or "kick").
local function fistStreak(char: Model, which: string, seconds: number)
	local r = rigOf(char)
	if not r then return end
	for i, t in ipairs(r.fists) do
		if (which == "both" and i <= 2) or (which == "R" and i == 1) or (which == "L" and i == 2) or (which == "kick" and i == 3) then
			t.Enabled = true
			task.delay(seconds, function() t.Enabled = false end)
		end
	end
end

local function stepRigs(_dt: number)
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		if not (char and isMartial(p)) then continue end
		local root = rootOf(char)
		local r = rigOf(char)
		if not (root and r) then continue end
		local v = root.AssemblyLinearVelocity
		local k = math.clamp(Vector3.new(v.X, 0, v.Z).Magnitude / 22, 0, 1)
		local rise = math.clamp(-v.Y / 40, -0.5, 0.6)
		for i, m in ipairs(r.motors) do
			local ph = r.phase[i]
			if r.band[i] then
				-- (streaming out behind the head, fluttering harder the faster he goes)
				m.Transform = CFrame.Angles(-0.4 * k - rise * 0.5 + math.sin(now * (7 + 6 * k) + ph) * (0.07 + 0.2 * k), 0,
					math.sin(now * 5.3 + ph) * (0.1 + 0.15 * k))
			else
				-- (the sash's tails swing back as he runs)
				m.Transform = CFrame.Angles(-1.0 * k - rise * 0.8 + math.sin(now * 6 + ph) * (0.05 + 0.12 * k), 0,
					math.sin(now * 4.4 + ph) * 0.07)
			end
		end
	end
	for c in pairs(rigs) do
		if not c.Parent then rigs[c] = nil end
	end
end

-- ── Poses ───────────────────────────────────────────────────────────────────
local STRIKES = {
	-- 1 · the jab: chambered at the hip, then snapped out with the whole body
	-- behind it, a deep step in, the left fist guarding the chin
	{ { dur = 0.045, pose = { RS = { 30, 0, 24 }, LS = { 75, 0, -28 }, W = { 6, -24, 0 }, N = { 0, 16, 0 }, Root = { 0, 0, 0, 0, -0.3, 0.2 },
			RH = { 14, 0, 8 }, LH = { -10, 0, -8 } } },
		{ dur = 0.055, style = Enum.EasingStyle.Quart, pose = { RS = { 98, 0, -8 }, LS = { 78, 0, -30 }, W = { -8, 32, 0 }, N = { 0, -16, 0 },
			Root = { 0, 0, 0, 0, -0.35, -0.35 }, RH = { 26, 0, 8 }, LH = { -24, 0, -8 } } },
		{ dur = 0.08, pose = { RS = { 96, 0, -8 }, LS = { 76, 0, -30 }, W = { -6, 30, 0 }, Root = { 0, 0, 0, 0, -0.32, -0.3 } } } },
	-- 2 · the cross: the hips whipped round into it, the left driven through,
	-- the right pulled back to the hip
	{ { dur = 0.045, pose = { LS = { 30, 0, -24 }, RS = { 75, 0, 28 }, W = { 6, 26, 0 }, N = { 0, -16, 0 }, Root = { 0, 0, 0, 0, -0.3, 0.2 } } },
		{ dur = 0.055, style = Enum.EasingStyle.Quart, pose = { LS = { 98, 0, 8 }, RS = { 20, 0, 30 }, W = { -10, -36, 0 }, N = { 0, 18, 0 },
			Root = { 0, 0, 0, 0, -0.38, -0.4 }, RH = { -24, 0, 8 }, LH = { 28, 0, -8 } } },
		{ dur = 0.08, pose = { LS = { 96, 0, 8 }, RS = { 22, 0, 30 }, W = { -8, -34, 0 }, Root = { 0, 0, 0, 0, -0.35, -0.35 } } } },
	-- 3 · the spinning roundhouse: wound right round, then the whole body
	-- spins through and the right leg sweeps out at full stretch, arms flung
	-- wide for balance
	{ { dur = 0.06, pose = { Root = { 0, -110, 0, 0, -0.25, 0 }, W = { 0, -20, 0 }, RS = { 50, 0, 50 }, LS = { 50, 0, -50 }, N = { 0, 40, 0 },
			RH = { 10, 0, -6 }, LH = { -6, 0, -8 } } },
		{ dur = 0.09, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 70, -14, 0, 0.1, 0 }, W = { 0, 10, -16 }, RS = { 20, 0, 75 },
			LS = { 60, 0, -70 }, N = { 0, -20, 0 }, RH = { 18, 0, 92 }, LH = { -4, 0, -10 } } },
		{ dur = 0.08, pose = { Root = { 0, 95, -10, 0, 0.05, 0 }, W = { 0, 6, -12 }, RS = { 20, 0, 70 }, LS = { 55, 0, -65 }, RH = { 14, 0, 80 } } } },
	-- 4 · the dragon palm: both hands coiled back at the hip, the body low,
	-- then both palms driven out in a deep lunge as the dragon leaves them
	{ { dur = 0.09, pose = { RS = { 18, 0, 26 }, LS = { 18, 0, -26 }, Root = { 0, 0, 0, 0, -0.55, 0.45 }, W = { 12, 34, 0 }, N = { 0, -30, 0 },
			RH = { 30, 0, 14 }, LH = { -20, 0, -12 } } },
		{ dur = 0.07, style = Enum.EasingStyle.Quart, pose = { RS = { 100, 0, -14 }, LS = { 100, 0, 14 }, Root = { 0, 0, 0, 0, -0.8, -0.6 },
			W = { -16, 0, 0 }, N = { 8, 0, 0 }, RH = { 48, 0, 8 }, LH = { -36, 0, -8 } } },
		{ dur = 0.16, pose = { RS = { 98, 0, -14 }, LS = { 98, 0, 14 }, Root = { 0, 0, 0, 0, -0.75, -0.55 }, W = { -14, 0, 0 } } } },
}
local STRIKE_HAND = { "R", "L", "kick", "both" }

local function strikePose(char: Model, n: number)
	CastPoses.play(char, STRIKES[n] or STRIKES[1], 0.18)
	fistStreak(char, STRIKE_HAND[n] or "R", if n == 4 then 0.3 else 0.2)
end

-- Dragon Fist: 1 · Channel (Qi gathered into both fists drawn back at the
-- hip, a wide low stance) → 2 · Release (the right fist driven out, the
-- body behind it, the left pulled back).
local function fistPose(char: Model, channel: number)
	CastPoses.play(char, {
		{ dur = channel * 0.45, pose = { RS = { 18, 0, 22 }, LS = { 18, 0, -22 }, Root = { 0, 0, 0, 0, -0.55, 0.25 }, W = { 8, 34, 0 },
			N = { 0, -28, 0 }, RH = { 32, 0, 14 }, LH = { -22, 0, -12 } } },
		{ dur = channel * 0.55, pose = { RS = { 24, 0, 26 }, LS = { 20, 0, -24 }, Root = { 0, 0, 0, 0, -0.6, 0.3 }, W = { 10, 38, 0 },
			N = { 0, -30, 0 } }, wobble = function(t: number)
			local s = math.sin(t * 60) * 1.5
			return { RS = { s, 0, 0 }, LS = { -s, 0, 0 } }
		end },
		{ dur = 0.06, style = Enum.EasingStyle.Quart, pose = { RS = { 96, 0, -4 }, LS = { 26, 0, -30 }, Root = { 0, 0, 0, 0, -0.45, -0.6 },
			W = { -10, -30, 0 }, N = { 0, 20, 0 }, RH = { 40, 0, 8 }, LH = { -32, 0, -8 } } },
		{ dur = 0.35, pose = { RS = { 94, 0, -4 }, LS = { 26, 0, -30 }, Root = { 0, 0, 0, 0, -0.45, -0.55 }, W = { -8, -28, 0 } } },
	}, 0.25)
	task.delay(channel, function() fistStreak(char, "R", 0.25) end)
end

-- Qi Release: 1 · Activate (arms flung out, chest up, Qi bursting) →
-- 3 · Enhance (fists clenched in, the body braced, the aura forming).
local function qiPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.12, pose = { RS = { 30, 0, 30 }, LS = { 30, 0, -30 }, Root = { 0, 0, 0, 0, -0.55, 0 }, W = { 16, 0, 0 }, N = { 16, 0, 0 },
			RH = { 18, 0, 18 }, LH = { 18, 0, -18 } } },
		{ dur = 0.1, style = Enum.EasingStyle.Back, pose = { RS = { 20, 0, 75 }, LS = { 20, 0, -75 }, Root = { 0, 0, 0, 0, -0.3, 0 }, W = { -14, 0, 0 },
			N = { -20, 0, 0 }, RH = { 10, 0, 24 }, LH = { 10, 0, -24 } } },
		{ dur = 0.25, pose = { RS = { 18, 0, 70 }, LS = { 18, 0, -70 }, Root = { 0, 0, 0, 0, -0.3, 0 }, W = { -12, 0, 0 }, N = { -16, 0, 0 } } },
		{ dur = 0.15, style = Enum.EasingStyle.Back, pose = { RS = { 60, 0, 40 }, LS = { 60, 0, -40 }, Root = { 0, 0, 0, 0, -0.45, 0 }, W = { 6, 0, 0 },
			RH = { 16, 0, 20 }, LH = { 16, 0, -20 } } },
		{ dur = 0.2, pose = { RS = { 60, 0, 40 }, LS = { 60, 0, -40 }, Root = { 0, 0, 0, 0, -0.45, 0 }, W = { 6, 0, 0 } } },
	}, 0.3)
end

-- Dragon Ascent: 1 · Ascend (a rising uppercut, straight up, a knee
-- tucked) → 2 · Strike (flying forward, the body flat behind the fist) →
-- 3 · Impact (a hero's landing: the fist driven into the ground).
local function ascentPose(char: Model)
	local T = ASCENT
	CastPoses.play(char, {
		{ dur = T.rise * 0.35, pose = { RS = { 60, 0, 10 }, LS = { 40, 0, -40 }, Root = { 0, 0, 0, 0, -0.6, 0 }, W = { 18, 0, 0 },
			RH = { 40, 0, 0 }, LH = { 30, 0, 0 } } },
		{ dur = T.rise * 0.65, style = Enum.EasingStyle.Quart, pose = { RS = { 172, 0, 6 }, LS = { 30, 0, -50 }, RH = { 80, 0, 0 },
			LH = { -6, 0, 0 }, W = { -6, 0, 0 }, N = { -24, 0, 0 } } },
		{ dur = T.dash, pose = { Root = { 60, 0, 0, 0, 0, 0 }, RS = { 160, 0, -6 }, LS = { 10, 0, -30 }, RH = { 10, 0, 6 }, LH = { -14, 0, -6 },
			W = { 0, 0, 0 }, N = { -40, 0, 0 } } },
		{ dur = T.fall, style = Enum.EasingStyle.Quart, pose = { Root = { 20, 0, 0, 0, -0.4, 0 }, RS = { 60, 0, -8 }, LS = { 40, 0, -60 },
			W = { 20, 0, 0 }, RH = { 70, 0, 6 }, LH = { -10, 0, -6 } } },
		{ dur = 0.3, pose = { Root = { 10, 0, 0, 0, -1.25, 0 }, RS = { 25, 0, -10 }, LS = { 50, 0, -60 }, W = { 32, 0, 0 }, N = { -20, 0, 0 },
			RH = { 85, 0, 10 }, LH = { -15, 0, -14 } } },
	}, 0.35)
	task.delay(T.rise * 0.3, function() fistStreak(char, "R", T.rise + T.dash + T.fall) end)
end

-- Dragon Soul: 1 · Summon (a deep stance, both hands drawing Qi in to the
-- chest) → 2 · Manifest (both fists thrown to the sky as the dragon rises)
-- → 3 · Devastate (a palm thrust after it as it's sent through) → 4 · Fade
local function soulPose(char: Model)
	local stance = { Root = { 0, 0, 0, 0, -0.75, 0 }, RH = { 26, 0, 32 }, LH = { 26, 0, -32 }, W = { 8, 0, 0 } }
	local function with(extra: { [string]: any }): { [string]: any }
		local p = table.clone(stance)
		for k, v in pairs(extra) do p[k] = v end
		return p
	end
	CastPoses.play(char, {
		{ dur = 0.25, pose = with({ RS = { 60, 0, 50 }, LS = { 60, 0, -50 }, N = { 12, 0, 0 } }) },
		{ dur = 0.55, pose = with({ RS = { 70, 0, 12 }, LS = { 70, 0, -12 }, N = { 8, 0, 0 } }), wobble = function(t: number)
			local s = math.sin(t * 10) * 10
			return { RS = { s, 0, 0 }, LS = { -s, 0, 0 } }
		end },
		{ dur = 0.18, style = Enum.EasingStyle.Back, pose = with({ RS = { 168, 0, 24 }, LS = { 168, 0, -24 }, N = { -28, 0, 0 }, W = { -8, 0, 0 } }) },
		{ dur = 0.52, pose = with({ RS = { 170, 0, 26 }, LS = { 170, 0, -26 }, N = { -28, 0, 0 }, W = { -8, 0, 0 } }) },
		{ dur = 0.1, style = Enum.EasingStyle.Quart, pose = with({ RS = { 96, 0, -6 }, LS = { 40, 0, -40 }, W = { -12, -22, 0 }, N = { 0, 14, 0 } }) },
		{ dur = 1.8, pose = with({ RS = { 94, 0, -6 }, LS = { 40, 0, -40 }, W = { -10, -20, 0 } }) },
	}, 0.45)
end

-- ── M1: Flowing Fists ───────────────────────────────────────────────────────
-- 1 · jab and 2 · cross: a crescent of Qi off the fist, a flurry of phantom
-- fists thrown round the real one, rings of air bursting off the punch.
-- 3 · the spinning roundhouse: a ring of Qi swept all the way round him,
-- wind kicked up off the floor. 4 · the dragon palm: a small dragon bursts
-- out of both palms, a shell of Qi, cracked ground. Every strike stamps a
-- ring of Qi at his feet.

-- A ring of air bursting off a punch, standing across the line of it.
local function punchRing(at: Vector3, dir: Vector3, radius: number, life: number, color: Color3?)
	SwordFX.Arc({ cf = CFrame.lookAt(at, at + dir) * CFrame.Angles(math.rad(90), 0, 0), radius = radius, arc = 359, width = 0.35,
		color = color or GOLD, life = life, draw = 0.001, grow = 1.1, core = WHITE })
end

-- Phantom fists: streaks of Qi thrown in a flurry round the real one.
local function phantoms(fist: Vector3, dir: Vector3, count: number, reach: number)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for i = 1, count do
		task.delay((i - 1) * 0.035, function()
			local off = side * (math.random() - 0.5) * 1.8 + Vector3.new(0, (math.random() - 0.5) * 1.3, 0)
			local a = fist + off - dir * 0.6
			local b = a + dir * reach * (0.7 + math.random() * 0.3)
			streak(a, b, 0.34, 0.13, if i % 2 == 0 then BRIGHT else GOLD)
			flare(b, 1.8, 0.12)
		end)
	end
end

local function strikeFx(msg: any)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local n = tonumber(msg.step) or 1
	local mine = msg.attacker == nil or msg.attacker == player
	local fist = pos + dir * 2.6 + Vector3.new(0, 0.6, 0)
	local feet = onGround(pos)
	if not FxBudget.Allow("maStrike", 14) then return end
	-- (a stamp of Qi at his feet)
	floorRing(feet, if n == 4 then 4.5 else 2.4, 0.25, GOLD, 0.45)
	if n == 1 or n == 2 then
		local side = Vector3.new(-dir.Z, 0, dir.X)
		local hand = fist + side * (if n == 1 then 0.5 else -0.5)
		SwordFX.Arc({ cf = CFrame.lookAt(hand, hand + dir) * CFrame.Angles(0, 0, math.rad(if n == 1 then 70 else -70)), radius = 2.4,
			arc = 120, width = 0.6, color = GOLD, life = 0.2, draw = 0.04, grow = 0.35, core = WHITE })
		punchRing(hand + dir * 1.2, dir, 1.0, 0.2)
		task.delay(0.05, function() punchRing(hand + dir * 2.6, dir, 1.5, 0.22, BRIGHT) end)
		if FxBudget.Allow("maPhantom", 8) then phantoms(hand, dir, if n == 1 then 3 else 4, 6) end
		ClassFX.Sound("whoosh", hand, 0.4, 1 + n * 0.08)
	elseif n == 3 then
		-- the roundhouse: a full ring of Qi swept round him at the height of
		-- the kick, a thinner one just above it, wind off the floor
		local c = pos + Vector3.new(0, -0.4, 0)
		SwordFX.Arc({ cf = CFrame.lookAt(c, c + dir), radius = 3.4, arc = 359, width = 1.0, color = GOLD, life = 0.28, draw = 0.09,
			grow = 0.4, core = WHITE })
		SwordFX.Arc({ cf = CFrame.lookAt(c + Vector3.new(0, 0.6, 0), c + Vector3.new(0, 0.6, 0) + dir) * CFrame.Angles(0, 0, math.rad(8)),
			radius = 2.7, arc = 300, width = 0.5, color = BRIGHT, life = 0.22, draw = 0.08, grow = 0.3, core = WHITE })
		if FxBudget.Allow("maKickPack", 4) then
			PackFX.Burst("Anime/Wind-02", CFrame.new(feet + Vector3.new(0, 0.4, 0)), { color = GOLD, scale = 0.9 })
		end
		sparks(c, 14, 20)
		ClassFX.Sound("whoosh", c, 0.6, 0.8)
	else
		-- the dragon palm
		local p = (msg.palm :: Vector3?) or (pos + dir * 4)
		local r = tonumber(msg.radius) or 6
		local hands = pos + dir * 2.2 + Vector3.new(0, 0.4, 0)
		flare(hands, 6, 0.2, WHITE)
		shell(p, 1, r * 2.2, 0.32, GOLD)
		flare(p, r * 1.3, 0.25)
		punchRing(hands + dir * 1.5, dir, 1.6, 0.25)
		punchRing(hands + dir * 3.5, dir, 2.6, 0.3, BRIGHT)
		PackFX.Burst("Anime/Shoot-01", CFrame.lookAt(p, p + dir), { color = GOLD, scale = 1.1 })
		floorRing(onGround(p), r, 0.35, GOLD, 0.8)
		if FxBudget.Allow("maPalmDragon", 2) then
			local dragon = newDragon(0.7, hands, dir, 0.2)
			dragon.jaw(1)
			local len = r * 1.6
			animate(len / 42 + 0.15, function(a)
				local s = a * (len + 6)
				local q = hands + dir * s + Vector3.new(0, math.sin(s * 0.5) * 0.4, 0)
				dragon.move(q, dir)
				dragon.set(math.min(s / 1.5, 1) * (if s > len then math.max(0, 1 - (s - len) / 6) else 1))
				if a >= 1 then dragon.destroy() end
				return nil
			end)
			PackFX.Burst("Anime/Crack-01", CFrame.new(onGround(p) + Vector3.new(0, 0.1, 0)), { color = EMBER, scale = 0.6 })
		end
		sparks(p, 22, 28)
		ClassFX.Sound("fireBurst", p, 0.6, 1.2)
		ClassFX.Sound("boom", p, 0.35, 1.5)
		if mine and deps then
			deps.shake(0.3, 0.12)
			deps.fovPunch(3, 0.18)
		end
	end
end

local function strikeLanded(msg: any)
	local n = tonumber(msg.step) or 1
	local dir = msg.dir :: Vector3
	local fist = (msg.pos :: Vector3) + dir * 3 + Vector3.new(0, 0.6, 0)
	flare(fist, 3.4, 0.16)
	punchRing(fist + dir * 0.4, dir, 1.8, 0.18, WHITE)
	sparks(fist, 10, 18)
	ClassFX.Sound("punch", fist, 0.6, 0.9 + n * 0.08)
	if FxBudget.Allow("maPunchPack", 6) then
		PackFX.Burst("Anime/Punch-0" .. tostring(((n - 1) % 3) + 1), CFrame.lookAt(fist, fist + dir), { color = GOLD, scale = 0.8 })
	end
	if msg.attacker == player and deps then deps.shake(if n == 4 then 0.35 else 0.15, 0.07) end
end

local function onStrike(msg: any)
	if msg.attacker ~= player then
		local char = charOf(msg.attacker)
		if char then strikePose(char, tonumber(msg.step) or 1) end
		strikeFx(msg)
	end
	if msg.landed and FxBudget.Allow("maLanded", 14) then strikeLanded(msg) end
end

-- ── E: Dragon Fist ──────────────────────────────────────────────────────────
-- 1 · Channel: Qi drawn into the fists (fire on both hands, light rushing
-- in, a ring at his feet). 2 · Release: a dragon bursts out of the fist and
-- surges forward, weaving (Empowered: three side by side). 3 · Impact: it
-- tears through them. 4 · End: a starburst shockwave where it ends.
local function channelFx(char: Model, channel: number)
	local list: { Instance } = {}
	for _, side in ipairs({ "Right Arm", "Left Arm" }) do
		local arm = char:FindFirstChild(side)
		if arm then
			local att = Instance.new("Attachment")
			att.Name = "MartialChannel"
			att.Position = Vector3.new(0, -1.05, 0)
			att.Parent = arm
			emitter(att, { Texture = TEX_FIRE, Color = ColorSequence.new(BRIGHT, EMBER), LightEmission = 1, Size = nseq(0, 1.3, 1, 0),
				Transparency = nseq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.2, 0.35), Speed = NumberRange.new(1, 3),
				SpreadAngle = Vector2.new(180, 180), Rate = 70, RotSpeed = NumberRange.new(-200, 200) })
			emitter(att, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, GOLD), LightEmission = 1, Size = nseq(0, 0.4, 1, 0),
				Lifetime = NumberRange.new(0.2, 0.35), Speed = NumberRange.new(2, 6), SpreadAngle = Vector2.new(180, 180),
				Drag = 6, Rate = 50 })
			table.insert(list, att)
		end
	end
	task.delay(channel + 0.15, function()
		for _, a in ipairs(list) do
			for _, e in ipairs(a:GetChildren()) do
				if e:IsA("ParticleEmitter") then e.Enabled = false end
			end
			Debris:AddItem(a, 0.5)
		end
	end)
end

local function onFist(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	local channel = tonumber(msg.channel) or FIST_CHANNEL
	if char and owner ~= player then fistPose(char, channel) end
	local from = msg.from :: Vector3
	local dir = flat((msg.dir :: Vector3?) or Vector3.new(0, 0, -1))
	local speed = tonumber(msg.speed) or 58
	local emp = msg.empowered == true
	if char then channelFx(char, channel) end
	floorRing(onGround(from), 4, channel, GOLD, 0.6)
	ClassFX.Sound("fireWhoosh", from, 0.5, 0.8)
	task.delay(channel, function()
		ClassFX.Sound("fireBurst", from, 0.8, 0.8)
		ClassFX.Sound("whoosh", from, 0.7, 0.7)
		if owner == player and deps then
			deps.shake(0.45, 0.15)
			deps.fovPunch(4, 0.2)
		end
		local hand = from + dir * 2.4
		flare(hand, 6, 0.22)
		shell(hand, 1, 7, 0.25, GOLD)
		PackFX.Burst("Anime/Wind-02", CFrame.lookAt(hand, hand + dir), { color = GOLD, scale = 0.7 })
		local side = Vector3.new(-dir.Z, 0, dir.X)
		for k, o in ipairs(msg.origins or { from }) do
			local origin = o :: Vector3
			local length = (msg.lengths and tonumber(msg.lengths[k])) or 28
			local phase = k * 1.7
			-- (the dragons beside the fist swing out to their lanes)
			local laneOff = (origin - from):Dot(side)
			local function at(s: number): Vector3
				local fade = math.min(s / 5, 1)
				local lane = from + side * laneOff * math.min(s / 6, 1)
				return lane + dir * (s + 2) + side * math.sin(s * 0.28 + phase) * 1.4 * fade
					+ Vector3.new(0, 0.4 + math.sin(s * 0.42 + phase) * 0.8 * fade, 0)
			end
			local life = 0.3
			local dragon = newDragon(if emp then 1.0 else 0.85, at(0), dir, life)
			dragon.jaw(0.85)
			local over = 6 -- (it runs on past the end as it dissolves)
			local total = (length + over) / speed
			animate(total + 0.05, function(a)
				local s = math.min(a * total * speed, length + over)
				local p = at(s)
				local q = at(s + 0.5)
				dragon.move(p, q - p)
				local fadeIn = math.min(s / 2, 1)
				local fadeOut = if s > length then 1 - (s - length) / over else 1
				dragon.set(fadeIn * fadeOut)
				if a >= 1 then dragon.destroy() end
				return nil
			end)
		end
	end)
end

-- 4 · End: a brief shockwave, a starburst of light.
local function onFistEnd(msg: any)
	local pos = msg.pos :: Vector3
	local r = tonumber(msg.radius) or 5
	if not FxBudget.Allow("maFistEnd", 8) then return end
	shell(pos, 1, r * 2.6, 0.32, GOLD)
	flare(pos, r * 1.8, 0.25)
	floorRing(onGround(pos), r * 1.4, 0.35, GOLD, 0.8)
	SwordFX.Rays(pos, r * 2.2, 14, BRIGHT, 0.3)
	PackFX.Burst("Big/Explosion-01", CFrame.new(pos), { color = GOLD, scale = 0.45, count = 0.5 })
	sparks(pos, 24, 30)
	ClassFX.Sound("boom", pos, 0.5, 1.2)
end

-- ── F: Qi Release ───────────────────────────────────────────────────────────
-- 1 · Activate: a whirlwind of Qi spiralling up round him, a burst. 2 · Buff
-- / 3 · Enhance: streaks of Qi orbiting him every which way, flames of Qi
-- rising off his body, a circle turning at his feet (Empowered: bigger,
-- faster, and a dragon coiling round him). 4 · End: the streaks fly out and
-- fade.
type Aura = { carriers: { BasePart }, alive: boolean, endsAt: number, emitters: { ParticleEmitter }, dragon: Dragon? }
local auras: { [Player]: Aura } = {}

local function dropAura(owner: Player)
	local a = auras[owner]
	if not a then return end
	auras[owner] = nil
	a.alive = false
	for _, e in ipairs(a.emitters) do
		if e.Parent then e.Enabled = false end
		Debris:AddItem(e, 1.2)
	end
	if a.dragon then a.dragon.destroy() end
	-- the streaks fly outward and fade
	local root = rootOf(charOf(owner))
	local c = if root then root.Position else (a.carriers[1] and a.carriers[1].Position or Vector3.zero)
	for _, p in ipairs(a.carriers) do
		local out = flat(p.Position - c)
		local p0 = p.Position
		animate(0.3, function(k)
			if p.Parent then p.CFrame = CFrame.new(p0 + out * k * 6 + Vector3.new(0, k * 2, 0)) end
			if k >= 1 then Debris:AddItem(p, 0.3) end
			return nil
		end)
	end
	if root then
		sparks(root.Position, 20, 14, BRIGHT)
		floorRing(onGround(root.Position), 5, 0.3, GOLD, 0.5)
	end
end

local function onQi(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	local root = rootOf(char)
	if not (char and root) then return end
	if owner ~= player then qiPose(char) end
	dropAura(owner)
	local radius = tonumber(msg.radius) or 9
	local seconds = tonumber(msg.seconds) or 6
	local emp = msg.empowered == true
	local k = if emp then 1.35 else 1
	-- 1 · the burst: a whirlwind of streaks spiralling up round him
	local g = onGround(root.Position)
	shell(root.Position, 2, radius * 2.2, 0.4, GOLD)
	flare(root.Position, radius * 1.1, 0.3)
	floorRing(g, radius, 0.45, GOLD, 1.1)
	floorRing(g, radius * 0.55, 0.35, BRIGHT, 0.7)
	PackFX.Burst("Anime/Charge-01", root.CFrame, { color = GOLD, scale = 1.2 * k })
	PackFX.Burst("Anime/Wind-02", CFrame.new(g + Vector3.new(0, 0.3, 0)), { color = GOLD, scale = 1.1 * k })
	sparks(root.Position, 30, 24)
	ClassFX.Sound("fireBurst", root, 0.7, 0.9)
	ClassFX.Sound("wind", root, 0.5, 1.2)
	if owner == player and deps then
		deps.shake(0.35, 0.15)
		deps.fovPunch(5, 0.25)
	end
	for i = 1, 6 do
		local c = carrier(CFrame.new(g))
		ribbon(c, Vector3.zero, 0.5 * k, 0.28, ColorSequence.new(WHITE, GOLD), nseq(0, 0, 1, 1), nseq(0, 1, 1, 0.1))
		local a0 = i / 6 * math.pi * 2
		animate(0.5, function(u)
			local ang = a0 + u * math.pi * 3
			local r = (2.8 - u * 1.4) * k
			c.CFrame = CFrame.new(g + Vector3.new(math.cos(ang) * r, 0.3 + u * 7, math.sin(ang) * r))
			if u >= 1 then Debris:AddItem(c, 0.3) end
			return nil
		end)
	end
	-- 2 · 3 · the aura
	local ORBITS = {
		{ r = 2.4, tilt = CFrame.Angles(math.rad(72), 0, 0), w = 6.5, h = 0.6 },
		{ r = 2.7, tilt = CFrame.Angles(math.rad(-58), math.rad(65), 0), w = -5.6, h = 0.3 },
		{ r = 3.0, tilt = CFrame.Angles(math.rad(14), 0, math.rad(8)), w = 4.4, h = -1.2 },
		{ r = 2.6, tilt = CFrame.Angles(math.rad(40), math.rad(-50), 0), w = 7.2, h = 1.4 },
		{ r = 3.3, tilt = CFrame.Angles(math.rad(-10), 0, math.rad(-12)), w = -3.8, h = -2.2 },
	}
	local a: Aura = { carriers = {}, alive = true, endsAt = os.clock() + seconds, emitters = {}, dragon = nil }
	for _, o in ipairs(ORBITS) do
		local c = carrier(root.CFrame)
		-- (each streak: a solid golden band, wisps flowing over it, a glow)
		ribbon(c, Vector3.zero, 1.0 * k, 0.32, ColorSequence.new(GOLD, EMBER), nseq(0, 0.35, 1, 1), nseq(0, 1, 1, 0.2), TEX_WISPS, 3, 0.8)
		ribbon(c, Vector3.zero, 0.38 * k, 0.3, ColorSequence.new({ ColorSequenceKeypoint.new(0, WHITE), ColorSequenceKeypoint.new(0.25, BRIGHT),
			ColorSequenceKeypoint.new(1, GOLD) }), nseq(0, 0, 0.7, 0.4, 1, 1), nseq(0, 1, 1, 0.15))
		table.insert(a.carriers, c)
	end
	-- flames of Qi rising off his body (an aura round him), motes, the
	-- circle at his feet
	table.insert(a.emitters, emitter(root, { Texture = TEX_FIRE, Color = ColorSequence.new(BRIGHT, EMBER), LightEmission = 1,
		Size = nseq(0, 2.4 * k, 1, 0.4), Transparency = nseq(0, 0.3, 0.6, 0.5, 1, 1), Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(4, 7), SpreadAngle = Vector2.new(15, 15), EmissionDirection = Enum.NormalId.Top,
		Rate = if emp then 55 else 38, RotSpeed = NumberRange.new(-120, 120), Rotation = NumberRange.new(0, 360) }))
	table.insert(a.emitters, emitter(root, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, GOLD), LightEmission = 1,
		Size = nseq(0, 0.35, 1, 0), Lifetime = NumberRange.new(0.6, 1.1), Speed = NumberRange.new(2, 5), Acceleration = Vector3.new(0, 4, 0),
		SpreadAngle = Vector2.new(60, 60), EmissionDirection = Enum.NormalId.Top, Rate = if emp then 36 else 22 }))
	local floorParts: { BasePart } = {}
	local floorN = 24
	for j = 1, floorN do
		if j % 4 == 0 then continue end
		local seg = 2 * math.pi * 3.6 * k / floorN * 1.15
		local p = part({ Size = Vector3.new(seg, 0.06, 0.38), Color = GOLD, Transparency = 0.2 })
		p:SetAttribute("Angle", j / floorN * math.pi * 2)
		table.insert(floorParts, p)
	end
	-- Empowered: a dragon coils round him
	if emp then a.dragon = newDragon(0.5, root.Position + Vector3.new(4, 0, 0), Vector3.zAxis, 0.45) end
	auras[owner] = a
	local spin = 0
	local all: { BasePart } = table.clone(a.carriers)
	for _, p in ipairs(floorParts) do table.insert(all, p) end
	local cfs = table.create(#all)
	animate(seconds + 0.5, function(_, dt)
		if not a.alive then
			for _, p in ipairs(floorParts) do
				TweenService:Create(p, TweenInfo.new(0.3), { Transparency = 1 }):Play()
				Debris:AddItem(p, 0.35)
			end
			return true
		end
		if os.clock() >= a.endsAt or not root.Parent then
			dropAura(owner)
			return nil
		end
		spin += dt
		local c = root.Position
		local fg = Vector3.new(c.X, groundY(c) + 0.12, c.Z)
		for i, o in ipairs(ORBITS) do
			cfs[i] = CFrame.new(c + Vector3.new(0, o.h * k, 0)) * o.tilt * CFrame.Angles(0, spin * o.w * (if emp then 1.25 else 1), 0)
				* CFrame.new(0, 0, -o.r * k)
		end
		for j, p in ipairs(floorParts) do
			cfs[#ORBITS + j] = CFrame.new(fg) * CFrame.Angles(0, (p:GetAttribute("Angle") :: number) - spin * 0.8, 0) * CFrame.new(0, 0, -3.6 * k)
		end
		Workspace:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if a.dragon then
			local ang = spin * 2.4
			local p = c + Vector3.new(math.cos(ang) * 4.2, 0.5 + math.sin(spin * 1.7) * 1.6, math.sin(ang) * 4.2)
			local q = c + Vector3.new(math.cos(ang + 0.2) * 4.2, 0.5 + math.sin((spin + 0.08) * 1.7) * 1.6, math.sin(ang + 0.2) * 4.2)
			a.dragon.move(p, q - p)
			a.dragon.set(math.min(spin / 0.3, 1))
		end
		return nil
	end)
end

-- ── Q: Dragon Ascent ────────────────────────────────────────────────────────
-- His flight (every client draws it from the same numbers): straight up,
-- along over the path, down onto the landing.
local function ascentPath(from: Vector3, to: Vector3, stand: number): (number) -> Vector3
	local T = ASCENT
	local o = from + Vector3.new(0, stand, 0)
	local apex = o + Vector3.new(0, ASCENT_HEIGHT, 0)
	local over = to + Vector3.new(0, stand + ASCENT_HEIGHT * 0.45, 0)
	local land = to + Vector3.new(0, stand, 0)
	return function(t: number): Vector3
		if t < T.rise then
			return o:Lerp(apex, easeOut(t / T.rise))
		elseif t < T.rise + T.dash then
			return apex:Lerp(over, (t - T.rise) / T.dash)
		else
			return over:Lerp(land, easeIn(math.min((t - T.rise - T.dash) / T.fall, 1)))
		end
	end
end

type Mover = { set: (Vector3) -> (), face: (Vector3) -> (), stop: () -> (), alive: () -> boolean, stand: number }
local function holdBody(char: Model, root: BasePart): Mover?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local stand = SafeMove.StandHeight(root)
	local att = Instance.new("Attachment")
	att.Name = "MartialMove"
	att.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.RigidityEnabled = true
	ap.Position = root.Position
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root
	hum.AutoRotate = false
	hum.PlatformStand = true
	local stopped = false
	return {
		stand = stand,
		set = function(p: Vector3)
			if stopped then return end
			ap.Position = p
			if root.Parent then root.CFrame = CFrame.new(p) * root.CFrame.Rotation end
		end,
		face = function(d: Vector3)
			local f = Vector3.new(d.X, 0, d.Z)
			if f.Magnitude > 0.05 and not stopped then ao.CFrame = CFrame.lookAt(Vector3.zero, f.Unit) end
		end,
		alive = function() return not stopped and root.Parent ~= nil and hum.Health > 0 end,
		stop = function()
			if stopped then return end
			stopped = true
			ap:Destroy()
			ao:Destroy()
			att:Destroy()
			if hum.Parent then
				hum.PlatformStand = false
				hum.AutoRotate = true
			end
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.zero
				SafeMove.SnapToFloor(root, stand)
			end
		end,
	}
end

-- (ours: flown on our screen, the landing returned for the server)
local function ascentFly(char: Model, root: BasePart, dir: Vector3, cursor: Vector3?, range: number): Vector3?
	local mv = holdBody(char, root)
	if not mv then return nil end
	local origin = root.Position
	local want = range
	if cursor then
		want = math.min(Vector3.new(cursor.X - origin.X, 0, cursor.Z - origin.Z).Magnitude, range)
	end
	local dist = math.min(SafeMove.ClampDash(root, dir, want), SafeMove.ClampToFloor(root, dir, want))
	local landXZ = origin + dir * dist
	local from = onGround(origin)
	local to = onGround(landXZ)
	local path = ascentPath(from, to, mv.stand)
	mv.face(dir)
	local T = ASCENT
	local total = T.rise + T.dash + T.fall
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = math.min(os.clock() - t0, total)
		if mv.alive() then mv.set(path(t)) end
		if t >= total then
			conn:Disconnect()
			mv.set(path(total))
			mv.stop()
		end
	end)
	return to
end

-- 1 · Ascend: a pillar of Qi under him, light streaming up, the dragon
-- spiralling up round him. 2 · Strike: he rides it over the path, a slash
-- of light through everything on it (Empowered: three dragons crossing).
-- 3 · Impact: an explosion where he lands. 4 · End: the dragon's path
-- hangs in the air as a ribbon of fire, and the ground burns along it.
local function onAscent(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	if char and owner ~= player then ascentPose(char) end
	local from = msg.from :: Vector3
	local to = msg.to :: Vector3
	local radius = tonumber(msg.radius) or 9
	local width = tonumber(msg.width) or 4
	local trailFor = tonumber(msg.trail) or 2.5
	local emp = msg.empowered == true
	local T = ASCENT
	local total = T.rise + T.dash + T.fall
	local dir = flat(to - from)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local path = ascentPath(from, to, 3)
	-- 1 · the pillar
	local pillar = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 3, 3), Color = BRIGHT, Transparency = 0.2,
		CFrame = CFrame.new(from + Vector3.new(0, 7, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	local glow = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(14, 6, 6), Color = GOLD, Transparency = 0.6,
		Material = Enum.Material.ForceField, CFrame = pillar.CFrame })
	TweenService:Create(pillar, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(18, 0.1, 0.1), Transparency = 1 }):Play()
	TweenService:Create(glow, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(18, 9, 9), Transparency = 1 }):Play()
	Debris:AddItem(pillar, 0.5)
	Debris:AddItem(glow, 0.55)
	local pad = part({ Size = Vector3.new(4, 0.2, 4), CFrame = CFrame.new(from + Vector3.new(0, 0.2, 0)), Transparency = 1 })
	local rising = emitter(pad, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, GOLD), LightEmission = 1,
		Orientation = Enum.ParticleOrientation.VelocityParallel, Size = nseq(0, 0.5, 1, 0.1), Lifetime = NumberRange.new(0.35, 0.5),
		Speed = NumberRange.new(26, 34), SpreadAngle = Vector2.new(6, 6), EmissionDirection = Enum.NormalId.Top, Rate = 90,
		Shape = Enum.ParticleEmitterShape.Box })
	task.delay(T.rise + 0.05, function() rising.Enabled = false end)
	Debris:AddItem(pad, 1)
	floorRing(from, 4.5, 0.35, GOLD, 0.8)
	PackFX.Burst("Anime/Wind-02", CFrame.new(from + Vector3.new(0, 0.3, 0)), { color = GOLD, scale = 0.9 })
	PackFX.Burst("Anime/Crack-01", CFrame.new(from + Vector3.new(0, 0.1, 0)), { color = GOLD, scale = 0.5 })
	ClassFX.Sound("whoosh", from, 0.8, 0.8)
	ClassFX.Sound("fireWhoosh", from, 0.6, 1)
	-- the dragons (the middle one also draws the trail of fire that hangs
	-- in the air after it, all the way round the spiral and over the path)
	local count = if emp then 3 else 1
	local linger = carrier(CFrame.new(from))
	ribbon(linger, Vector3.zero, 2.2, trailFor, ColorSequence.new({ ColorSequenceKeypoint.new(0, BRIGHT), ColorSequenceKeypoint.new(0.4, GOLD),
		ColorSequenceKeypoint.new(1, EMBER) }), nseq(0, 0.1, 0.6, 0.35, 1, 1), nseq(0, 0.8, 0.5, 1, 1, 0.3), TEX_WISPS, 4, 0.9)
	ribbon(linger, Vector3.zero, 0.9, trailFor, ColorSequence.new(GOLD, EMBER), nseq(0, 0.25, 0.7, 0.55, 1, 1), nseq(0, 0.6, 0.4, 1, 1, 0.2), nil, nil, 0.7)
	ribbon(linger, Vector3.zero, 0.35, trailFor * 0.8, ColorSequence.new(WHITE, GOLD), nseq(0, 0.2, 1, 1), nil, TEX_FLICKER, 3)
	Debris:AddItem(linger, total + trailFor + 0.5)
	for k = 1, count do
		local off = (k - (count + 1) / 2) * 3.2
		local phase = k * 2.1
		local dragon = newDragon(if k == math.ceil(count / 2) then 0.85 else 0.65, from, Vector3.yAxis, 0.32)
		dragon.jaw(0.8)
		local main = k == math.ceil(count / 2)
		local function headAt(t: number): Vector3
			if t < T.rise then
				local u = t / T.rise
				local ang = u * math.pi * 2.4 + phase
				return from + Vector3.new(math.cos(ang) * 2.6, 0.5 + u * (ASCENT_HEIGHT + 2.5), math.sin(ang) * 2.6)
			elseif t < total then
				local u = math.min((t - T.rise) / (T.dash + T.fall), 1)
				local p = path(math.min(t + 0.06, total))
				-- (the outer two cross over the path, side to side)
				return p + dir * 2.5 + side * off * math.cos(u * math.pi)
			else
				-- into the ground and gone
				local u = (t - total) / 0.3
				return to + dir * (2.5 + u * 3) + Vector3.new(0, 1.5 - u * 5, 0)
			end
		end
		animate(total + 0.35, function(a)
			local t = a * (total + 0.35)
			local p = headAt(t)
			local q = headAt(t + 0.03)
			dragon.move(p, q - p)
			dragon.set(math.min(t / 0.06, 1) * (if t > total then 1 - (t - total) / 0.35 else 1))
			if main and t <= total + 0.05 then linger.CFrame = CFrame.new(p) end
			if a >= 1 then dragon.destroy() end
			return nil
		end)
	end
	-- 2 · the slash of light through the path
	task.delay(T.rise + T.dash * 0.4, function()
		streak(from + Vector3.new(0, 1.2, 0), to + Vector3.new(0, 1.2, 0), width * 0.5, 0.35, GOLD)
		if emp then
			streak(from + side * 3 + Vector3.new(0, 1.2, 0), to - side * 3 + Vector3.new(0, 1.2, 0), width * 0.35, 0.35, BRIGHT)
			streak(from - side * 3 + Vector3.new(0, 1.2, 0), to + side * 3 + Vector3.new(0, 1.2, 0), width * 0.35, 0.35, BRIGHT)
		end
		ClassFX.Sound("swordHit", to, 0.5, 1.3)
	end)
	-- 3 · the landing, 4 · the lingering trail
	task.delay(total, function()
		local g = to + Vector3.new(0, 0.2, 0)
		shell(g, 2, radius * 2.4, 0.4, GOLD)
		flare(g + Vector3.new(0, 1, 0), radius * 1.4, 0.3)
		floorRing(to, radius, 0.45, GOLD, 1.2)
		floorRing(to, radius * 0.6, 0.35, BRIGHT, 0.8)
		PackFX.Burst("Big/Explosion-01", CFrame.new(g), { color = GOLD, scale = radius / 10, count = 0.6 })
		PackFX.Burst("Big/Big-Crack-01", CFrame.new(g), { color = EMBER, scale = radius / 12 })
		SwordFX.Rays(g + Vector3.new(0, 0.5, 0), radius * 1.4, 14, BRIGHT, 0.35)
		sparks(g, 40, 34)
		ClassFX.Sound("quake", g, 0.7, 1.1)
		ClassFX.Sound("boom", g, 0.8, 1)
		if owner == player and deps then
			deps.shake(0.9, 0.25)
			deps.fovPunch(6, 0.25)
		elseif near(g, 50) and deps then
			deps.shake(0.3, 0.15)
		end
		-- the ground burning along the path (the fire in the air hangs on
		-- the middle dragon's trail)
		local len = Vector3.new(to.X - from.X, 0, to.Z - from.Z).Magnitude
		local n = math.clamp(math.floor(len / 3.5), 1, 9)
		for i = 1, n do
			local p = onGround(from:Lerp(to, (i - 0.5) / n)) + Vector3.new(0, 0.3, 0)
			PackFX.Run("Anime/Fire-02", CFrame.new(p), trailFor * (0.7 + math.random() * 0.3), { color = GOLD, scale = width / 5 })
		end
	end)
end

-- ── R: Dragon Soul ──────────────────────────────────────────────────────────
-- 1 · Summon: Qi gathers round him: rings of light rippling out over the
-- floor, the ground cracking and glowing, rubble lifting into the air,
-- light rushing in. 2 · Manifest: a colossal dragon rises behind him, coils
-- up over him and roars. 3 · Devastate: it dives and sweeps forward through
-- everything, weaving, the ground exploding under it, the rubble hurled
-- after it. 4 · Fade: it climbs away and dissipates into smoke and embers.
local function onSoul(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	local pos = msg.pos :: Vector3
	local dir = flat(msg.dir :: Vector3)
	local length = tonumber(msg.length) or 70
	local width = tonumber(msg.width) or 11
	local emp = msg.empowered == true
	local T = msg.t or { summon = 0.8, manifest = 1.5, passes = { 1.75, 2.35, 2.95 }, fade = 3.3, total = 3.6 }
	local side = Vector3.new(-dir.Z, 0, dir.X)
	if char and owner ~= player then soulPose(char) end
	if owner == player or near(pos, length + 30) then tint(SOUL_TOTAL) end
	-- 1 · the summon: a circle of Qi burning into the floor (three rings,
	-- the lines between them), rings rippling out over it
	local sigil: { BasePart } = {}
	local sigilRel: { CFrame } = {}
	for i, r in ipairs({ 4.5, 8, 11.5 }) do
		local n = math.floor(r * 4)
		for j = 1, n do
			local a = j / n * math.pi * 2
			table.insert(sigil, part({ Size = Vector3.new(2 * math.pi * r / n * 1.12, 0.06, 0.5 - i * 0.08), Color = if i == 2 then BRIGHT else GOLD,
				Transparency = 1 }))
			table.insert(sigilRel, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -r))
		end
	end
	for j = 1, 8 do
		local a = j / 8 * math.pi * 2
		table.insert(sigil, part({ Size = Vector3.new(0.22, 0.06, 7), Color = GOLD, Transparency = 1 }))
		table.insert(sigilRel, CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -8))
	end
	local sigilCF = table.create(#sigil)
	animate(T.total, function(a)
		local t = a * T.total
		local alpha = if t < 0.25 then t / 0.25 elseif t < T.manifest then 1 else math.max(0, 1 - (t - T.manifest) / 0.6)
		local pulse = 0.2 + math.sin(t * 14) * 0.08
		local base = CFrame.new(pos + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, t * 0.8, 0)
		for i, p in ipairs(sigil) do
			sigilCF[i] = base * sigilRel[i]
			p.Transparency = 1 - (1 - pulse) * alpha
		end
		Workspace:BulkMoveTo(sigil, sigilCF, Enum.BulkMoveMode.FireCFrameChanged)
		if a >= 1 then
			for _, p in ipairs(sigil) do p:Destroy() end
		end
		return nil
	end)
	for i = 0, 3 do
		task.delay(i * 0.2, function()
			floorRing(pos, 5 + i * 4, 0.55, if i % 2 == 0 then GOLD else BRIGHT, 1.1 - i * 0.15)
		end)
	end
	PackFX.Burst("Big/Big-Crack-01", CFrame.new(pos + Vector3.new(0, 0.1, 0)), { color = GOLD, scale = 1.1 })
	local rocks = rubble(pos, if emp then 18 else 14, 13, 5)
	local gather = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 26, CFrame = CFrame.new(pos + Vector3.new(0, 3, 0)), Transparency = 1 })
	local inward = emitter(gather, { Texture = TEX_SPARKLE, Color = ColorSequence.new(WHITE, GOLD), LightEmission = 1,
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Orientation = Enum.ParticleOrientation.VelocityParallel,
		Lifetime = NumberRange.new(0.5), Speed = NumberRange.new(21, 24), Size = nseq(0, 0.6, 1, 0.1), Transparency = nseq(0, 0.6, 1, 0), Rate = 90 })
	task.delay(T.summon, function()
		inward.Enabled = false
		Debris:AddItem(gather, 0.6)
	end)
	if char then channelFx(char, T.summon) end
	ClassFX.Sound("fireWhoosh", pos, 0.7, 0.6)
	ClassFX.Sound("wind", pos, 0.6, 0.8)
	ClassFX.Sound("quake", pos, 0.4, 1.4)
	-- 2 · the dragon
	local scale = if emp then 3.6 else 3.1
	local behind = pos - dir * 7
	local dragon = newDragon(scale, behind + Vector3.new(0, -6, 0), Vector3.yAxis, 0.75)
	local endAt = pos + dir * length
	local function headAt(t: number): Vector3
		if t < T.summon then
			return behind + Vector3.new(0, -6, 0)
		elseif t < T.manifest then
			-- rising up behind him, coiling, cresting over him
			local u = (t - T.summon) / (T.manifest - T.summon)
			local e = easeOut(u)
			return behind + side * math.sin(u * math.pi * 2) * 5 * (1 - u) + dir * e * 5 + Vector3.new(0, -6 + e * 21, 0)
		elseif t < T.passes[3] then
			-- the dive and the sweep forward, weaving through the line
			local u = (t - T.manifest) / (T.passes[3] - T.manifest)
			local along = -2 + u * (length + 2)
			local dive = math.clamp(u * 4.5, 0, 1)
			local h = 15 * (1 - dive) + (3.5 + math.sin(u * 14) * 2.5) * dive
			return pos + dir * along + side * math.sin(u * math.pi * 3) * width * 0.6 * dive + Vector3.new(0, h, 0)
		else
			-- climbing away into the sky
			local u = (t - T.passes[3]) / (T.total - T.passes[3])
			return endAt + dir * u * 10 + Vector3.new(0, 4 + u * 26, 0)
		end
	end
	local t0 = os.clock()
	local roared, thrown = false, false
	local lastBoom = 0
	animate(T.total + 0.1, function(a)
		local t = os.clock() - t0
		local p = headAt(t)
		local q = headAt(t + 0.04)
		dragon.move(p, q - p)
		local alpha = if t < T.summon then 0 elseif t < T.summon + 0.2 then (t - T.summon) / 0.2
			elseif t > T.fade then math.max(0, 1 - (t - T.fade) / (T.total - T.fade)) else 1
		dragon.set(alpha)
		-- the jaw: shut as it rises, thrown open in the roar, open as it sweeps
		dragon.jaw(if t < T.manifest - 0.2 then 0.25 elseif t < T.manifest + 0.25 then 1 else 0.7)
		-- its roar as it crests over him
		if not roared and t >= T.manifest - 0.12 then
			roared = true
			shell(p, 4, 44, 0.55, GOLD)
			shell(p, 2, 26, 0.4, BRIGHT)
			flare(p, 20, 0.4)
			SwordFX.Rays(p, 26, 18, BRIGHT, 0.45)
			ClassFX.Sound("quake", pos, 0.9, 0.6)
			ClassFX.Sound("boom", pos, 1, 0.55)
			ClassFX.Sound("fireBurst", pos, 1, 0.5)
			if owner == player or near(pos, 60) then flash(0.3, 0.5) end
			if owner == player and deps then
				deps.shake(0.9, 0.45)
				deps.fovPunch(8, 0.35)
			end
		end
		-- the rubble hurled after it
		if not thrown and t >= T.manifest + 0.1 then
			thrown = true
			rocks.throw(dir)
		end
		-- the ground exploding where it skims over
		if t > T.manifest + 0.15 and t < T.passes[3] and os.clock() - lastBoom > 0.13 and FxBudget.Allow("maSoulBoom", 10) then
			lastBoom = os.clock()
			local g = onGround(p)
			PackFX.Burst("Big/Explosion-01", CFrame.new(g + Vector3.new(0, 1, 0)), { color = GOLD, scale = 0.95, count = 0.5 })
			if math.random() < 0.5 then PackFX.Burst("Anime/Crack-01", CFrame.new(g + Vector3.new(0, 0.1, 0)), { color = EMBER, scale = 1.2 }) end
			floorRing(g, 8, 0.4, GOLD, 1.1)
			sparks(g + Vector3.new(0, 1, 0), 18, 32)
			ClassFX.Sound("boom", g, 0.5, 1.1 + math.random() * 0.3)
			if owner == player and deps then deps.shake(0.5, 0.12) end
		end
		if a >= 1 then
			-- 4 · dissolving into smoke and embers
			local hp = dragon.head().Position
			sparks(hp, 50, 22, BRIGHT)
			flare(hp, 16, 0.45)
			dragon.destroy()
		end
		return nil
	end)
	for _, at in ipairs(T.passes or {}) do
		task.delay(at, function()
			if owner == player and deps then deps.fovPunch(5, 0.25) end
		end)
	end
	-- 4 · the dust it leaves, drifting over the battlefield
	task.delay(T.fade - 0.2, function()
		for i = 1, 6 do
			local p = onGround(pos + dir * (length * i / 6.5) + side * (math.random() - 0.5) * width)
			PackFX.Burst("Anime/Smoke-01", CFrame.new(p + Vector3.new(0, 1.5, 0)), { color = Color3.fromRGB(110, 96, 84), scale = 2.2, keepColor = false })
		end
		if owner == player and deps then
			deps.shake(1.0, 0.35)
			deps.fovPunch(10, 0.35)
		end
	end)
end

-- ── Qi Charge: full, spent ──────────────────────────────────────────────────
local function onChargeFull(msg: any)
	local root = rootOf(charOf(msg.attacker))
	if not root then return end
	floorRing(onGround(root.Position), 5, 0.35, GOLD, 0.6)
	sparks(root.Position, 16, 10, BRIGHT)
	if msg.attacker == player then ClassFX.Sound("ding", root, 0.5, 1.1) end
end

local function onEmpowered(msg: any)
	local root = rootOf(charOf(msg.attacker))
	if not root then return end
	PackFX.Burst("Anime/Charge-01", root.CFrame, { color = GOLD, scale = 1.1 })
	flare(root.Position, 9, 0.3)
	sparks(root.Position + Vector3.new(0, 1, 0), 30, 18, BRIGHT)
	SwordFX.Spiral(function() return if root.Parent then root.Position - Vector3.new(0, 2.5, 0) else nil end, 3, 0.6, GOLD)
end

local HANDLERS: { [string]: (any) -> () } = {
	strike = onStrike,
	fist = onFist,
	fistEnd = onFistEnd,
	qi = onQi,
	qiEnd = function(msg) dropAura(msg.attacker) end,
	ascent = onAscent,
	soul = onSoul,
	chargeFull = onChargeFull,
	empowered = onEmpowered,
}

-- While a Martial Artist's Charge is full: his fists burn with Qi.
local burning: { [Player]: { Attachment } } = {}
local function stepBurning()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local want = char ~= nil and isMartial(p) and (tonumber(p:GetAttribute("MA_Charge")) or 0) >= CHARGE_MAX
		local have = burning[p]
		if want and not have and char then
			local list = {}
			for _, side in ipairs({ "Right Arm", "Left Arm" }) do
				local arm = char:FindFirstChild(side)
				if arm then
					local att = Instance.new("Attachment")
					att.Name = "MartialEmpowered"
					att.Position = Vector3.new(0, -1.05, 0)
					att.Parent = arm
					emitter(att, { Texture = TEX_FIRE, Color = ColorSequence.new(BRIGHT, EMBER), LightEmission = 1,
						Size = nseq(0, 1, 1, 0), Transparency = nseq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.25, 0.45),
						Speed = NumberRange.new(1, 3), SpreadAngle = Vector2.new(30, 30), Acceleration = Vector3.new(0, 6, 0), Rate = 32,
						RotSpeed = NumberRange.new(-150, 150) })
					table.insert(list, att)
				end
			end
			burning[p] = list
		elseif not want and have then
			for _, a in ipairs(have) do a:Destroy() end
			burning[p] = nil
		end
	end
	for p, list in pairs(burning) do
		if not p.Parent then
			for _, a in ipairs(list) do a:Destroy() end
			burning[p] = nil
		end
	end
end

-- ── HUD: Qi Charge ──────────────────────────────────────────────────────────
-- Five golden orbs over the skill bar, each filling as its 20 Charge comes in
-- (the sheet's: three full, the fourth half), the count beside them; full,
-- they blaze and it reads EMPOWERED.
local hud: ScreenGui? = nil
local fills: { Frame } = {}
local pipFrames: { Frame } = {}
local countLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil

local function charge(): number
	return tonumber(player:GetAttribute("MA_Charge")) or 0
end

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "MartialCharge"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -132)
	row.Size = UDim2.fromOffset(250, 22)
	row.BackgroundTransparency = 1
	row.Parent = g
	for k = 1, 5 do
		local p = Instance.new("Frame")
		p.Name = "Orb" .. k
		p.AnchorPoint = Vector2.new(0.5, 0.5)
		p.Position = UDim2.new(0, 10 + (k - 1) * 28, 0.5, 0)
		p.Size = UDim2.fromOffset(20, 20)
		p.BackgroundColor3 = Color3.fromRGB(26, 20, 12)
		p.BorderSizePixel = 0
		p.ClipsDescendants = true
		p.Parent = row
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = p
		local s = Instance.new("UIStroke")
		s.Color = GOLD
		s.Thickness = 1.5
		s.Parent = p
		-- the fill, rising from the bottom
		local f = Instance.new("Frame")
		f.Name = "Fill"
		f.AnchorPoint = Vector2.new(0, 1)
		f.Position = UDim2.fromScale(0, 1)
		f.Size = UDim2.fromScale(1, 0)
		f.BackgroundColor3 = GOLD
		f.BorderSizePixel = 0
		f.Parent = p
		local fc = Instance.new("UICorner")
		fc.CornerRadius = UDim.new(1, 0)
		fc.Parent = f
		local grad = Instance.new("UIGradient")
		grad.Rotation = 90
		grad.Color = ColorSequence.new(BRIGHT, EMBER)
		grad.Parent = f
		table.insert(pipFrames, p)
		table.insert(fills, f)
	end
	local n = Instance.new("TextLabel")
	n.AnchorPoint = Vector2.new(0, 0.5)
	n.Position = UDim2.new(0, 152, 0.5, 0)
	n.Size = UDim2.fromOffset(100, 20)
	n.BackgroundTransparency = 1
	n.Font = Enum.Font.Arcade
	n.TextSize = 18
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.TextColor3 = BRIGHT
	n.TextStrokeColor3 = Color3.new(0, 0, 0)
	n.TextStrokeTransparency = 0.3
	n.Text = "0 / 100"
	n.Parent = row
	countLabel = n
	local t = Instance.new("TextLabel")
	t.AnchorPoint = Vector2.new(0.5, 1)
	t.Position = UDim2.new(0.5, 0, 0, -4)
	t.Size = UDim2.fromOffset(280, 20)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Arcade
	t.TextSize = 18
	t.TextColor3 = Color3.fromRGB(240, 210, 160)
	t.TextStrokeColor3 = Color3.new(0, 0, 0)
	t.TextStrokeTransparency = 0.3
	t.Text = "QI CHARGE"
	t.Parent = row
	titleLabel = t
end

local function refreshHud()
	if not hud then return end
	hud.Enabled = isMartial() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	local c = charge()
	local full = c >= CHARGE_MAX
	for k, f in ipairs(fills) do
		local frac = math.clamp((c - (k - 1) * 20) / 20, 0, 1)
		f.Size = UDim2.fromScale(1, frac)
		f.BackgroundColor3 = if full then WHITE else GOLD
	end
	if countLabel then
		local txt = `{math.floor(c)} / {CHARGE_MAX}`
		if countLabel.Text ~= txt then countLabel.Text = txt end
	end
	if titleLabel then
		local txt = if full then "EMPOWERED: NEXT ABILITY" else "QI CHARGE"
		if titleLabel.Text ~= txt then titleLabel.Text = txt end
		titleLabel.TextColor3 = if full then BRIGHT else Color3.fromRGB(240, 210, 160)
	end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
local function attackSpeed(): number
	local s = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	local qiUntil = tonumber(player:GetAttribute("MA_QiUntil"))
	if qiUntil and Workspace:GetServerTimeNow() < qiUntil then
		s *= if player:GetAttribute("MA_QiEmp") then 1.5 else 1.3
	end
	return s
end

function MartialController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	if now - lastSwing < COMBO_INTERVAL / attackSpeed() then return true end
	if now - lastSwing > COMBO_RESET then step = 0 end
	step = step % 4 + 1
	lastSwing = now
	local dir = flat(deps.getAim(root))
	-- (a step in behind each strike, short of walls and ledges)
	local lunge = math.min(SafeMove.ClampDash(root, dir, LUNGE[step]), SafeMove.ClampToFloor(root, dir, LUNGE[step]))
	root.CFrame = CFrame.lookAt(root.Position + dir * lunge, root.Position + dir * (lunge + 1))
	strikePose(char, step)
	-- (the swing is drawn now; the hits come back from the server)
	local size = tonumber(player:GetAttribute("Stat_size")) or 1
	strikeFx({ pos = root.Position, dir = dir, step = step, landed = false,
		palm = if step == 4 then root.Position + dir * 4 else nil, radius = 6 * size })
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function MartialController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

-- Returns where the skill is aimed (sent to the server).
function MartialController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any, cursor: Vector3?): Vector3?
	local dir = flat(aimDir)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	if skillIndex == 1 then
		char:SetAttribute("AllowSkillMovement", false)
		fistPose(char, FIST_CHANNEL)
		busyUntil = os.clock() + FIST_CHANNEL + 0.1
		releaseAfter(char, FIST_CHANNEL + 0.15)
		-- (the release steps into the punch)
		task.delay(FIST_CHANNEL, function()
			if root.Parent then
				local d = math.min(SafeMove.ClampDash(root, dir, 1.4), SafeMove.ClampToFloor(root, dir, 1.4))
				root.CFrame = root.CFrame + dir * d
			end
		end)
		return nil
	elseif skillIndex == 2 then
		char:SetAttribute("AllowSkillMovement", true)
		qiPose(char)
		releaseAfter(char, 0.3)
		return nil
	elseif skillIndex == 3 then
		char:SetAttribute("AllowSkillMovement", false)
		ascentPose(char)
		local T = ASCENT
		local total = T.rise + T.dash + T.fall
		busyUntil = os.clock() + total + 0.15
		releaseAfter(char, total + 0.2)
		return ascentFly(char, root, dir, cursor, config.range or 26)
	elseif skillIndex == 4 then
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = os.clock() + SOUL_TOTAL
		soulPose(char)
		releaseAfter(char, SOUL_TOTAL)
		return nil
	end
	return nil
end

-- The Dragon Soul's summoning, seen close and low: Qi gathering round him.
function MartialController.PlayUltCutscene(char: Model, dir: Vector3)
	UltimateCameraChoreography.PlayCloseUp(char, dir, 0.8, nil, nil, {
		startOffset = { 6, -3, 1.5 },
		endOffset = { 8.5, -4, 3 },
		focusHeight = 2.5,
		fovStart = 50,
		fovEnd = 62,
	})
end

function MartialController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	RunService.RenderStepped:Connect(function(dt)
		stepBurning()
		stepAnims(dt)
	end)
	-- (the tails sway after the animation and poses have written the frame)
	CastPoses.addPostHook(stepRigs)
	for _, a in ipairs({ "MA_Charge", "SelectedClass", "InLobby", "SettingsOpen" }) do
		player:GetAttributeChangedSignal(a):Connect(refreshHud)
	end
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		lastSwing = 0
		step = 0
	end)
	Network.GetRemoteEvent(Network.Remotes.MartialFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[MartialController]", msg.kind, err) end
		end
	end)
end

return MartialController
