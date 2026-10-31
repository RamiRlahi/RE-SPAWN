--!strict
--[[
	SummonerController.luau
	Client side of the Summoner, "The Beastcaller" (server: SummonerServer,
	tuning: SummonerData). Draws the beasts every client sees on the field
	and everything they do, and runs the Summoner's own casts.

	  • Every beast in Workspace.Summons (an invisible root the server glides
	    about) is drawn here from the artist's model (Summons/Rig) and moved
	    by its animator (Summons/Beasts): its gait from how fast the root is
	    really going, its banking from how fast it turns, its head on the
	    nearest enemy; attacks, arrivals and the signature moves from the
	    server's SummonerFX moments, timed to its hits.
	  • E / F / Q call a beast (the Rockborn falls as a meteor where you aim,
	    the Skyfeather dives in, the Lunari rises from a moon gate); pressed
	    again while it's out, the staff points and the beast makes its
	    signature move at the cursor (Ground Slam, Wind Circle, Radiant
	    Bloom; each its own short recharge, shown on the beast cards).
	  • R: the beasts fly to you and fuse into the Skyrockorn.
	  • The Bond Bolt (M1) leaves the staff at once on your screen; whatever
	    it hits gets the Focus sigil and every beast turns on it.
	  • The beast cards over the skill bar: each beast's time left and its
	    signature's recharge.

	The caster's poses are R6: a limb is one piece, so each is posed by
	where its forearm (or shin) should point: the staff arm straight out at
	the target, raised overhead, driven down at the floor.
	Per-hit effects go through FxBudget; nothing a player must see is
	budgeted (the arrivals, the signatures, the ult).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SummonerData = require(Shared:WaitForChild("SummonerData"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local PackFX = require(script.Parent:WaitForChild("PackFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))
local SummonsFolder = script.Parent:WaitForChild("Summons")
local Rig = require(SummonsFolder:WaitForChild("Rig"))
local Beasts = require(SummonsFolder:WaitForChild("Beasts"))

local player = Players.LocalPlayer

local SummonerController = {}

local BEAST = SummonerData.BEAST
local COLOR = SummonerData.COLOR
local CORE = SummonerData.CORE
local BOLT = SummonerData.BOLT
local LIFT = SummonerData.ROOT_LIFT
local BOND = COLOR.bond
local WHITE = Color3.new(1, 1, 1)
local DEEP_EMBER = Color3.fromRGB(220, 80, 20)
local CULL = 320 -- beasts further than this from the camera aren't posed

type Deps = {
	shake: (number, number) -> (),
	fovPunch: (number, number) -> (),
	getAim: (BasePart) -> Vector3,
	getCursor: ((BasePart) -> Vector3)?,
}
local deps: Deps

local lastBolt = 0
local busyUntil = 0
local sigReadyAt: { [string]: number } = {} -- server time each signature is back

local function isSummoner(p: Player?): boolean
	return (p or player):GetAttribute("SelectedClass") == "summoner"
end

local function serverNow(): number
	return Workspace:GetServerTimeNow()
end

local function rootOf(char: Model?): BasePart?
	return if char then char:FindFirstChild("HumanoidRootPart") :: BasePart? else nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function yawOf(v: Vector3): number
	return math.atan2(-v.X, -v.Z)
end

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function mine(msg: any): boolean
	return msg.owner == player
end

-- How close the camera is to a point (effects shake only those near).
local function nearCamera(pos: Vector3, reach: number): boolean
	return (Workspace.CurrentCamera.CFrame.Position - pos).Magnitude < reach
end

local function shakeAt(pos: Vector3, power: number, time: number, reach: number?)
	local r = rootOf(player.Character)
	if not r or not deps then return end
	local d = (r.Position - pos).Magnitude
	local k = 1 - math.clamp(d / (reach or 60), 0, 1)
	if k > 0 then deps.shake(power * k, time) end
end

local function part(props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = ClassFX.Folder()
	return p
end

-- ── One loop for every running effect ───────────────────────────────────────
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
		if not ok then warn("[SummonerController] fx:", res) end
		if a >= 1 or not ok or res == true then table.remove(running, i) end
	end
end

local function after(t: number, fn: () -> ())
	task.delay(t, function()
		local ok, err = pcall(fn)
		if not ok then warn("[SummonerController]", err) end
	end)
end

local function easeOut(a: number): number return 1 - (1 - a) ^ 3 end

-- The floor under a point (ignoring bodies and effects).
local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
groundParams.RespectCanCollide = true
local function ground(pos: Vector3): Vector3
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	local rigs = Workspace:FindFirstChild("SummonRigs")
	if rigs then table.insert(ignore, rigs) end
	groundParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), groundParams)
	return if hit then hit.Position else pos
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
local function floorRing(pos: Vector3, radius: number, life: number, color: Color3, width: number?, core: Color3?)
	SwordFX.Arc({ cf = CFrame.new(pos + Vector3.new(0, 0.2, 0)), radius = radius * 0.6, arc = 359, width = width or 1,
		color = color, life = life, draw = 0.001, grow = 0.7, core = core or WHITE })
end

local function flare(pos: Vector3, size: number, life: number, color: Color3)
	-- (never white: the dungeon's bloom blows pale light out to a blank)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * size * 0.3, CFrame = CFrame.new(pos), Color = color, Transparency = 0.3 })
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * size, Transparency = 1, Color = color }):Play()
	Debris:AddItem(b, life + 0.05)
end

-- A shell of energy swelling out (a 3D shockwave).
local function shell(pos: Vector3, from: number, to: number, life: number, color: Color3)
	local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * from, CFrame = CFrame.new(pos), Color = color,
		Material = Enum.Material.ForceField })
	TweenService:Create(b, TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * math.max(to, 0.05), Transparency = 1 }):Play()
	Debris:AddItem(b, life + 0.05)
end

local function sparks(pos: Vector3, count: number, speed: number, color: Color3)
	ClassFX.Burst(pos, color, count, speed, ClassFX.TEX_SPARK, 0.4, 0.55)
end

local function streak(a: Vector3, b: Vector3, width: number, life: number, color: Color3, core: Color3?)
	SwordFX.Streak(a, b, width, color, life, nil, core or WHITE)
end

-- Chunks of rock thrown up from a point, falling back (anchored, moved here).
local ROCK = { Color3.fromRGB(85, 62, 47), Color3.fromRGB(122, 90, 66), Color3.fromRGB(60, 44, 36) }
local function debris(pos: Vector3, count: number, power: number, lava: boolean?)
	if not FxBudget.Allow("sumDebris", 4) then count = math.ceil(count / 3) end
	for _ = 1, count do
		local s = 0.4 + math.random() * 0.9
		local hot = lava and math.random() < 0.3
		local p = part({ Size = Vector3.new(s, s * 0.8, s * 1.1), CFrame = CFrame.new(pos) * CFrame.Angles(math.random() * 6, math.random() * 6, 0),
			Color = if hot then COLOR.rock else ROCK[math.random(1, #ROCK)],
			Material = if hot then Enum.Material.Neon else Enum.Material.Slate })
		local a = math.random() * math.pi * 2
		local v = Vector3.new(math.cos(a), 0, math.sin(a)) * (power * (0.4 + math.random() * 0.6)) + Vector3.new(0, power * (0.9 + math.random() * 0.7), 0)
		local spin = CFrame.Angles(math.random() * 8 - 4, math.random() * 8 - 4, 0)
		local p0, life = p.Position, 0.7 + math.random() * 0.5
		animate(life, function(u, dt)
			local t = u * life
			local at = p0 + v * t + Vector3.new(0, -60 * t * t, 0)
			p.CFrame = CFrame.new(at) * (p.CFrame - p.CFrame.Position) * spin:Lerp(CFrame.identity, 1 - dt)
			if u > 0.7 then p.Transparency = (u - 0.7) / 0.3 end
			if u >= 1 then p:Destroy() end
			return nil
		end)
	end
end

local function dust(pos: Vector3, scale: number, color: Color3?)
	PackFX.Burst("Anime/Smoke-01", CFrame.new(pos + Vector3.new(0, 0.5, 0)),
		{ color = color or Color3.fromRGB(150, 130, 112), scale = scale, count = 0.6, light = 0 })
end

-- ── Earth spikes ────────────────────────────────────────────────────────────
-- The craters' rock: jagged spikes of dirt and stone bursting up out of the
-- floor (built like the Ice Mage's ice spikes, in earth): four corner
-- wedges, each a little wider or narrower than the next, their tips meeting
-- in one point; a glow of the beast's light at the root. They punch up with
-- an overshoot, hold, then crumble back into the floor.
local DIRT = {
	Color3.fromRGB(92, 68, 50), Color3.fromRGB(108, 82, 60), Color3.fromRGB(74, 56, 44),
	Color3.fromRGB(84, 76, 70), Color3.fromRGB(116, 92, 70),
}
type Spike = { parts: { BasePart }, rel: { CFrame }, cf: CFrame, h: number, delay: number }

local function makeSpike(cf: CFrame, width: number, height: number, accent: Color3?, delay: number): Spike
	local sp: Spike = { parts = {}, rel = {}, cf = cf, h = height, delay = delay }
	local tone = DIRT[math.random(1, #DIRT)]
	for k = 0, 3 do
		local ax = width * 0.5 * (0.7 + math.random() * 0.6)
		local az = width * 0.5 * (0.7 + math.random() * 0.6)
		local w = part({ Size = Vector3.new(ax, height, az), Color = tone:Lerp(Color3.new(0, 0, 0), (k % 2) * 0.18),
			Material = Enum.Material.Slate, CFrame = cf * CFrame.new(0, -height * 2, 0) }, "CornerWedgePart")
		w.CastShadow = height > 2.5
		table.insert(sp.parts, w)
		table.insert(sp.rel, CFrame.Angles(0, k * math.pi / 2, 0) * CFrame.new(-ax / 2, height / 2, az / 2))
	end
	if accent then
		-- (the light that tore it up, glowing in the cracks at its root)
		local g = part({ Size = Vector3.new(width * 0.55, 0.3, width * 0.55), Color = accent, CFrame = cf * CFrame.new(0, -height * 2, 0) })
		table.insert(sp.parts, g)
		table.insert(sp.rel, CFrame.new(0, 0.12, 0) * CFrame.Angles(0, math.rad(45), 0))
	end
	return sp
end

-- Erupts every spike (each after its own delay), holds them `hold` seconds,
-- then sinks them.
local RISE, SINK = 0.13, 0.45
local function overshoot(a: number): number
	local c = 1.7
	return 1 + (c + 1) * (a - 1) ^ 3 + c * (a - 1) ^ 2
end
local function erupt(spikes: { Spike }, hold: number)
	local last = 0
	for _, sp in ipairs(spikes) do last = math.max(last, sp.delay) end
	local total = last + RISE + hold + SINK
	local all: { BasePart } = {}
	for _, sp in ipairs(spikes) do
		for _, p in ipairs(sp.parts) do table.insert(all, p) end
	end
	local cfs = table.create(#all)
	animate(total, function(u, _dt)
		local age = u * total
		local i = 0
		for _, sp in ipairs(spikes) do
			local t = age - sp.delay
			local rise = if t <= 0 then 0 else overshoot(math.min(t / RISE, 1))
			local sink = math.clamp((t - RISE - hold) / SINK, 0, 1)
			local at = sp.cf * CFrame.new(0, -sp.h * 1.05 * (1 - rise) - sp.h * 0.75 * sink * sink, 0)
			for k, rel in ipairs(sp.rel) do
				i += 1
				cfs[i] = at * rel
				if sink > 0 then sp.parts[k].Transparency = sink * sink end
			end
		end
		Workspace:BulkMoveTo(all, cfs, Enum.BulkMoveMode.FireCFrameChanged)
		if u >= 1 then for _, p in ipairs(all) do p:Destroy() end end
		return nil
	end)
end

-- A spike leaning away from `center` (out of a crater), any which way round.
local function outward(at: Vector3, center: Vector3, lean: number): CFrame
	local out = Vector3.new(at.X - center.X, 0, at.Z - center.Z)
	out = if out.Magnitude > 0.05 then out.Unit else Vector3.new(0, 0, -1)
	return CFrame.lookAt(at, at + out) * CFrame.Angles(math.rad(-lean), 0, 0) * CFrame.Angles(0, math.random() * 6.28, 0)
end

-- A crater of spikes: `rings` rings between `inner` and `outer` studs out,
-- erupting outward like a ripple, leaning out of the bowl, bigger toward
-- the rim.
local function spikeCrater(center: Vector3, inner: number, outer: number, rings: number, height: number, accent: Color3?, hold: number)
	local spikes: { Spike } = {}
	for ring = 1, rings do
		local f = if rings == 1 then 1 else (ring - 1) / (rings - 1)
		local r = inner + (outer - inner) * f
		local n = math.max(6, math.floor(r * 1.1))
		for k = 1, n do
			local a = (k + math.random() * 0.6) / n * math.pi * 2 + ring * 0.7
			local at = ground(center + Vector3.new(math.cos(a) * r, 2, math.sin(a) * r))
			local h = height * (0.55 + 0.45 * f) * (0.7 + math.random() * 0.6)
			local w = h * (0.42 + math.random() * 0.18)
			table.insert(spikes, makeSpike(outward(at, center, 10 + math.random() * 26), w, h,
				if math.random() < 0.6 then accent else nil, r / 90 + math.random() * 0.04))
		end
	end
	erupt(spikes, hold)
end

-- A sigil on the floor: rings and runes turning, in the beast's colour.
type Sigil = { parts: { BasePart }, rel: { CFrame }, cf: CFrame, spin: number, angle: number, alpha: number, dead: boolean }
local function sigil(at: Vector3, radius: number, color: Color3, spikes: number?): Sigil
	local cf = CFrame.new(at + Vector3.new(0, 0.12, 0))
	local s: Sigil = { parts = {}, rel = {}, cf = cf, spin = 0.9, angle = 0, alpha = 1, dead = false }
	local function add(p: BasePart, rel: CFrame)
		table.insert(s.parts, p)
		table.insert(s.rel, rel)
	end
	-- two rings of segments
	for ring = 1, 2 do
		local r = radius * (if ring == 1 then 1 else 0.68)
		local n = if ring == 1 then 28 else 20
		for k = 1, n do
			local a = k / n * math.pi * 2
			local len = 2 * math.pi * r / n * 0.82
			add(part({ Size = Vector3.new(len, 0.08, if ring == 1 then 0.32 else 0.22), Color = color, Transparency = 1 }),
				CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -r))
		end
	end
	-- spokes of light between them
	local m = spikes or 6
	for k = 1, m do
		local a = k / m * math.pi * 2
		add(part({ Size = Vector3.new(0.22, 0.08, radius * 0.32), Color = color, Transparency = 1 }),
			CFrame.Angles(0, -a, 0) * CFrame.new(0, 0, -radius * 0.84))
		add(part({ Size = Vector3.new(0.6, 0.08, 0.6), Color = WHITE, Transparency = 1 }),
			CFrame.Angles(0, -a + math.pi / m, 0) * CFrame.new(0, 0, -radius * 0.84) * CFrame.Angles(0, math.rad(45), 0))
	end
	return s
end

local function setSigil(s: Sigil, alpha: number, dt: number)
	s.alpha = alpha
	s.angle += s.spin * dt
	local turn = CFrame.Angles(0, s.angle, 0)
	local cfs = table.create(#s.parts)
	for i, rel in ipairs(s.rel) do cfs[i] = s.cf * turn * rel end
	Workspace:BulkMoveTo(s.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
	for _, p in ipairs(s.parts) do p.Transparency = 1 - alpha end
end

-- A sigil that grows in, turns for `hold` seconds, then fades.
local function sigilFor(at: Vector3, radius: number, color: Color3, hold: number, spin: number?)
	local s = sigil(at, radius, color)
	s.spin = spin or 0.9
	animate(hold + 0.4, function(u, dt)
		local t = u * (hold + 0.4)
		local a = math.min(t / 0.18, 1) * (1 - math.clamp((t - hold) / 0.4, 0, 1))
		setSigil(s, a * 0.9, dt)
		if u >= 1 then for _, p in ipairs(s.parts) do p:Destroy() end end
		return nil
	end)
end

-- ── The beasts on the field ─────────────────────────────────────────────────
type Rec = {
	model: Model, root: BasePart, kind: string, owner: number, rig: any, anim: any,
	pos: Vector3, yaw: number, lastPos: Vector3, vel: Vector3, yawRate: number,
	lookAt: Vector3?, nextLook: number, born: number, leaving: number?, cf: CFrame,
	trails: { Trail }, emitters: { ParticleEmitter }, bar: BillboardGui?,
}
local records: { [Model]: Rec } = {}
local pendingArrive: { [Model]: number } = {}
local models: { [string]: any } = {}
local rigFolder: Folder

local function modelData(kind: string): any
	local name = SummonerData.MODEL[kind]
	local d = models[name]
	if not d then
		d = require(SummonsFolder:WaitForChild("Models"):WaitForChild(name) :: ModuleScript)
		models[name] = d
	end
	return d
end

-- The part of a bone furthest from it (a wing's tip, the end of a tail).
local function tipOf(rig: any, bone: string): BasePart?
	local bi = rig:bone(bone)
	if not bi then return nil end
	local best, bestD = nil, -1
	for k, b in ipairs(rig.boneOf) do
		if b == bi then
			local d = rig.offsets[k].Position.Magnitude
			if d > bestD then best, bestD = rig.parts[k], d end
		end
	end
	return best
end

-- The biggest part on a bone (where its aura hangs).
local function bulkOf(rig: any, bone: string): BasePart?
	local bi = rig:bone(bone)
	if not bi then return nil end
	local best, bestV = nil, -1
	for k, b in ipairs(rig.boneOf) do
		if b == bi then
			local s = rig.parts[k].Size
			local v = s.X * s.Y * s.Z
			if v > bestV then best, bestV = rig.parts[k], v end
		end
	end
	return best
end

local function addTrail(p: BasePart?, color: Color3, length: number, life: number, list: { Trail })
	if not p then return end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0, -length / 2)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, 0, length / 2)
	a1.Parent = p
	local t = Instance.new("Trail")
	t.Attachment0, t.Attachment1 = a0, a1
	t.Color = ColorSequence.new(WHITE, color)
	t.Transparency = NumberSequence.new(0.35, 1)
	t.Lifetime = life
	t.LightEmission = 0.8
	t.FaceCamera = true
	t.WidthScale = NumberSequence.new(1, 0)
	t.Parent = p
	table.insert(list, t)
end

local function addAura(p: BasePart?, props: { [string]: any }, list: { ParticleEmitter })
	if not p then return end
	local e = Instance.new("ParticleEmitter")
	e.LightInfluence = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = p
	table.insert(list, e)
end

-- Each beast's own light: embers off the golem, wind off the hawk's wings,
-- moon motes off the stag's antlers, all of it off the fused one.
local function decorate(rec: Rec)
	local rig = rec.rig
	if rec.kind == "rock" then
		addAura(bulkOf(rig, "UpperTorso"), {
			Texture = FireFX.TEX.specs, Color = ColorSequence.new(COLOR.rock, Color3.fromRGB(255, 70, 20)),
			Size = NumberSequence.new(0.35, 0), Lifetime = NumberRange.new(0.8, 1.4), Rate = 7,
			Speed = NumberRange.new(2, 4), Acceleration = Vector3.new(0, 4, 0), SpreadAngle = Vector2.new(40, 40),
			LightEmission = 1, Brightness = 2,
		}, rec.emitters)
	elseif rec.kind == "sky" then
		addTrail(tipOf(rig, "LeftWing2"), COLOR.sky, 0.6, 0.28, rec.trails)
		addTrail(tipOf(rig, "RightWing2"), COLOR.sky, 0.6, 0.28, rec.trails)
	elseif rec.kind == "moon" then
		addAura(tipOf(rig, "Head"), {
			Texture = ClassFX.TEX_SPARK, Color = ColorSequence.new(CORE.moon, COLOR.moon),
			Size = NumberSequence.new(0.3, 0), Lifetime = NumberRange.new(0.8, 1.3), Rate = 6,
			Speed = NumberRange.new(0.5, 1.5), Acceleration = Vector3.new(0, 1.5, 0), SpreadAngle = Vector2.new(180, 180),
			LightEmission = 1, Brightness = 2,
		}, rec.emitters)
		addTrail(tipOf(rig, "Tail3"), COLOR.moon, 0.5, 0.25, rec.trails)
	elseif rec.kind == "fused" then
		addTrail(tipOf(rig, "LeftWing2"), COLOR.fused, 1.4, 0.45, rec.trails)
		addTrail(tipOf(rig, "RightWing2"), COLOR.fused, 1.4, 0.45, rec.trails)
		addTrail(tipOf(rig, "Tail3"), COLOR.moon, 1, 0.35, rec.trails)
		addAura(bulkOf(rig, "UpperTorso"), {
			Texture = ClassFX.TEX_SPARK, Color = ColorSequence.new(WHITE, COLOR.fused),
			Size = NumberSequence.new(0.7, 0), Lifetime = NumberRange.new(0.6, 1.2), Rate = 16,
			Speed = NumberRange.new(2, 5), SpreadAngle = Vector2.new(180, 180), LightEmission = 1, Brightness = 3,
		}, rec.emitters)
	end
end

-- The Rockborn's health, over its head (it's the one enemies can break).
local function healthBar(rec: Rec)
	local hum = rec.model:FindFirstChildOfClass("Humanoid")
	local head = bulkOf(rec.rig, "Head")
	if not hum or not head then return end
	local g = Instance.new("BillboardGui")
	g.Size = UDim2.fromOffset(70, 7)
	g.StudsOffsetWorldSpace = Vector3.new(0, 3.2, 0)
	g.AlwaysOnTop = true
	g.MaxDistance = 120
	g.Adornee = head
	local bg = Instance.new("Frame")
	bg.Size = UDim2.fromScale(1, 1)
	bg.BackgroundColor3 = Color3.fromRGB(20, 14, 10)
	bg.BorderSizePixel = 0
	bg.Parent = g
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLOR.rock
	fill.BorderSizePixel = 0
	fill.Parent = bg
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = bg
	g.Parent = rec.model
	rec.bar = g
	local last = hum.Health
	hum.HealthChanged:Connect(function(h)
		fill.Size = UDim2.fromScale(math.clamp(h / math.max(hum.MaxHealth, 1), 0, 1), 1)
		if h < last - 1 and records[rec.model] then
			-- (a hit: it flashes hot)
			local rig = rec.rig
			rig:tint(Color3.fromRGB(255, 80, 40), 0.55)
			task.delay(0.08, function() if rig.model.Parent then rig:tint(WHITE, 0) end end)
		end
		last = h
	end)
end

local function track(model: Model)
	if records[model] then return end
	local kind = model:GetAttribute("Summon")
	if typeof(kind) ~= "string" or not BEAST[kind] then return end
	local root = model:WaitForChild("HumanoidRootPart", 6) :: BasePart?
	if not root or not model.Parent or records[model] then return end
	local rig = Rig.new(modelData(kind), BEAST[kind].scale, rigFolder)
	local anim = Beasts.new(kind, rig)
	local at = root.Position - Vector3.new(0, LIFT, 0)
	local rec: Rec = {
		model = model, root = root, kind = kind, owner = tonumber(model:GetAttribute("Owner")) or 0, rig = rig, anim = anim,
		pos = at, yaw = yawOf(root.CFrame.LookVector), lastPos = at, vel = Vector3.zero, yawRate = 0,
		lookAt = nil, nextLook = 0, born = os.clock(), leaving = nil, cf = CFrame.new(at),
		trails = {}, emitters = {}, bar = nil,
	}
	records[model] = rec
	decorate(rec)
	if kind == "rock" then
		healthBar(rec)
		anim.onStep = function(foot: string)
			local bone = rig:bone(if foot == "L" then "LeftFoot" else "RightFoot")
			if not bone or not FxBudget.Allow("rockStep", 5) then return end
			local p = rig:world(bone).Position
			if nearCamera(p, 110) then
				dust(ground(p), 0.45)
				ClassFX.Sound("rockHit", p, 0.18, 0.55 + math.random() * 0.1)
			end
			shakeAt(p, 0.18, 0.12, 22)
		end
	end
	local fall = pendingArrive[model]
	if fall then
		pendingArrive[model] = nil
		anim:arrive(fall)
	end
	-- (not shown until its first pose)
	rig:render(CFrame.new(at) * CFrame.Angles(0, rec.yaw, 0) * CFrame.new(0, -400, 0))
end

local function untrack(model: Model)
	local rec = records[model]
	if not rec then return end
	-- (gone without a word: a quick fade)
	if not rec.leaving then
		rec.leaving = os.clock()
		rec.anim:leave("expire")
		for _, e in ipairs(rec.emitters) do e.Enabled = false end
	end
	-- it keeps animating on its own until it's faded
	local keep = rec.cf
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < 1 and rec.rig.model.Parent do
			local dt = RunService.RenderStepped:Wait()
			local extra = rec.anim:update(dt, { clock = os.clock(), speed = 0, climb = 0, yawRate = 0, look = 0 })
			rec.rig:render(CFrame.new(keep.Position) * (keep - keep.Position) * extra)
		end
		rec.rig:destroy()
	end)
	records[model] = nil
end

-- The nearest enemy to look at (refreshed a few times a second).
local function lookTarget(pos: Vector3, reach: number): Vector3?
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return nil end
	local best, bestD = nil, reach
	for _, m in ipairs(mobs:GetChildren()) do
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			local d = (r.Position - pos).Magnitude
			if d < bestD then best, bestD = r.Position, d end
		end
	end
	return best
end

local function stepBeasts(dt: number)
	if dt <= 0 then return end
	local cam = Workspace.CurrentCamera.CFrame.Position
	local now = os.clock()
	for _, rec in pairs(records) do
		local root = rec.root
		if not root.Parent then continue end
		local target = root.Position - Vector3.new(0, LIFT, 0)
		-- (smoothed: the replicated root can step; a long way is a blink)
		if (target - rec.pos).Magnitude > 25 then
			rec.pos = target
			rec.lastPos = target
		else
			rec.pos = rec.pos:Lerp(target, 1 - math.exp(-dt * 16))
		end
		local wantYaw = yawOf(root.CFrame.LookVector)
		local dyaw = wrap(wantYaw - rec.yaw)
		local turn = dyaw * (1 - math.exp(-dt * 12))
		rec.yaw = wrap(rec.yaw + turn)
		rec.yawRate += (turn / dt - rec.yawRate) * math.min(1, dt * 8)
		local v = (rec.pos - rec.lastPos) / dt
		rec.lastPos = rec.pos
		rec.vel = rec.vel:Lerp(v, math.min(1, dt * 10))
		if (rec.pos - cam).Magnitude > CULL then continue end
		if now >= rec.nextLook then
			rec.nextLook = now + 0.25
			rec.lookAt = lookTarget(rec.pos, if rec.kind == "sky" then 40 else 26)
		end
		local look = 0
		if rec.lookAt then
			look = wrap(yawOf(flat(rec.lookAt - rec.pos)) - rec.yaw)
		end
		local flatV = Vector3.new(rec.vel.X, 0, rec.vel.Z)
		local ok, extra = pcall(rec.anim.update, rec.anim, dt, {
			clock = now, speed = flatV.Magnitude, climb = rec.vel.Y, yawRate = rec.yawRate, look = look,
		})
		if not ok then
			warn("[SummonerController] beast:", extra)
			extra = CFrame.identity
		end
		rec.cf = CFrame.new(rec.pos) * CFrame.Angles(0, rec.yaw, 0) * (extra :: CFrame)
		rec.rig:render(rec.cf)
	end
end

local function recOf(model: any): Rec?
	return if typeof(model) == "Instance" then records[model :: Model] else nil
end

-- Where a beast's chest is now (rays, tethers).
local function chestOf(rec: Rec): Vector3
	local b = rec.rig:bone("UpperTorso") or 1
	return rec.rig:world(b).Position
end

-- ── Arrivals and departures ─────────────────────────────────────────────────
local function onSummon(msg: any)
	local model = msg.model
	local kind = msg.beast
	local at = msg.pos :: Vector3
	local rec = recOf(model)
	if msg.quiet then
		-- (back out of the Skyrockorn: a burst of its light where it stands)
		after(0.05, function()
			flare(at + Vector3.new(0, 3, 0), 8, 0.5, COLOR[kind])
			sparks(at + Vector3.new(0, 3, 0), 14, 16, COLOR[kind])
		end)
		return
	end
	if rec then rec.anim:arrive(msg.fall) else pendingArrive[model] = msg.fall end
	local fall = msg.fall :: number
	local floor = ground(at)
	if kind == "rock" then
		-- a burning sigil marks where it'll land; it comes down as a meteor
		sigilFor(floor, 6, COLOR.rock, fall, 2.2)
		ClassFX.Sound("fireWhoosh", at, 0.7, 0.6)
		after(fall, function()
			FireFX.Explosion(floor, 4.5)
			FireFX.Cracks(floor, 9, 3, true)
			PackFX.Burst("Big/Big-Crack-01", CFrame.new(floor), { color = COLOR.rock, scale = 0.9 })
			floorRing(floor, 13, 0.5, COLOR.rock, 1.6, DEEP_EMBER)
			spikeCrater(floor, 4.5, 8.5, 2, 6, DEEP_EMBER, 1.3)
			debris(floor, 10, 30, true)
			dust(floor, 1.4)
			ClassFX.Sound("boom", floor, 0.9, 0.85)
			ClassFX.Sound("quake", floor, 0.6, 1.1)
			shakeAt(floor, 1.1, 0.4, 70)
		end)
		-- (the fall: a fireball's trail on the way down)
		after(0.02, function()
			local r = recOf(model)
			local body = r and bulkOf(r.rig, "UpperTorso")
			if body then
				local e = FireFX.Emitter("flame", body, 3)
				e.Rate = 60
				task.delay(fall, function() e.Enabled = false Debris:AddItem(e, 1.2) end)
			end
		end)
	elseif kind == "sky" then
		ClassFX.Sound("wind", at, 0.6, 1.4)
		ClassFX.Sound("whoosh", at, 0.7, 0.8)
		after(fall, function()
			PackFX.Burst("Anime/Wind-02", CFrame.new(floor + Vector3.new(0, 1, 0)), { color = COLOR.sky, scale = 1.1 })
			floorRing(floor, 9, 0.45, COLOR.sky, 1.1, CORE.sky)
			shell(floor + Vector3.new(0, 4, 0), 2, 16, 0.35, COLOR.sky)
			sparks(floor + Vector3.new(0, 5, 0), 18, 22, CORE.sky)
			ClassFX.Sound("whoosh", floor, 0.8, 1.1)
			shakeAt(floor, 0.4, 0.2, 40)
		end)
	elseif kind == "moon" then
		-- a moon gate opens on the floor and it rises out of it
		sigilFor(floor, 7, COLOR.moon, fall + 0.6, 1.2)
		PackFX.Burst("Anime/Portal-01", CFrame.new(floor + Vector3.new(0, 0.3, 0)) * CFrame.Angles(math.rad(90), 0, 0),
			{ color = COLOR.moon, scale = 1.3 })
		ClassFX.Pillar(floor, COLOR.moon, 5, 26, fall + 0.5)
		ClassFX.Sound("choir", at, 0.45, 1.25)
		ClassFX.Sound("magicBurst", at, 0.5, 0.9)
	end
end

local function onMoonGate(msg: any)
	local floor = ground(msg.pos)
	floorRing(floor, msg.radius, 0.7, COLOR.moon, 1.2, CORE.moon)
	sparks(floor + Vector3.new(0, 2, 0), 24, 14, CORE.moon)
	ClassFX.Sound("chime", floor, 0.6, 1.1)
	for _, c in ipairs(msg.healed or {}) do
		local r = rootOf(c)
		if r then sparks(r.Position, 10, 8, COLOR.moon) end
	end
end

local function onDismiss(msg: any)
	local rec = recOf(msg.model)
	local how = msg.how
	local at = if rec then rec.pos else msg.pos
	if rec then
		rec.leaving = os.clock()
		rec.anim:leave(how)
		for _, e in ipairs(rec.emitters) do e.Enabled = false end
		if rec.bar then rec.bar:Destroy() end
	end
	local color = COLOR[msg.beast] or BOND
	if how == "break" then
		debris(at + Vector3.new(0, 3, 0), 18, 26, true)
		FireFX.Explosion(at + Vector3.new(0, 2, 0), 6)
		dust(at, 1.4)
		ClassFX.Sound("rockHit", at, 0.9, 0.7)
		ClassFX.Sound("quake", at, 0.4, 1.3)
	elseif how == "expire" then
		sparks(at + Vector3.new(0, 3, 0), 16, 10, color)
		if msg.beast == "rock" then
			debris(at + Vector3.new(0, 1, 0), 8, 10)
			dust(at, 1)
		end
		ClassFX.Sound("poof", at, 0.5, 0.9)
	elseif how == "unfuse" then
		flare(at + Vector3.new(0, 8, 0), 26, 0.7, COLOR.fused)
		shell(at + Vector3.new(0, 6, 0), 4, 30, 0.6, COLOR.fused)
		sparks(at + Vector3.new(0, 8, 0), 40, 26, CORE.fused)
		ClassFX.Sound("magicBurst", at, 0.8, 0.8)
	end
end

local function onBlink(msg: any)
	sparks(msg.from + Vector3.new(0, 3, 0), 10, 12, COLOR[msg.beast] or BOND)
	sparks(msg.to + Vector3.new(0, 3, 0), 10, 12, COLOR[msg.beast] or BOND)
	ClassFX.Sound("poof", msg.to, 0.4, 1.2)
end

-- ── The beasts' attacks ─────────────────────────────────────────────────────
local function onAct(msg: any)
	local rec = recOf(msg.model)
	local act = msg.act
	if act == "impact" then
		if not FxBudget.Allow("rockPunch", 6) then return end
		local p = msg.pos :: Vector3
		PackFX.Burst("Anime/Punch-02", CFrame.new(p), { color = COLOR.rock, scale = 0.8 })
		ClassFX.Sound("punch", p, 0.7, 0.75)
		ClassFX.Sound("rockHit", p, 0.5, 0.9)
		shakeAt(p, 0.35, 0.15, 30)
		return
	end
	if not rec then return end
	rec.anim:play(act, msg.dur or 0.7, msg)
	local at = rec.pos
	if act == "hookL" or act == "hookR" then
		after(0.26, function() ClassFX.Sound("whoosh", at, 0.55, 0.6) end)
	elseif act == "hammer" then
		after(0.2, function() ClassFX.Sound("whoosh", at, 0.7, 0.5) end)
	elseif act == "volley" then
		ClassFX.Sound("whoosh", at, 0.45, 1.5)
		after(0.18, function()
			if FxBudget.Allow("skyVolley", 3) then
				local r = recOf(msg.model)
				if r then PackFX.Burst("Anime/Wind-02", r.cf * CFrame.new(0, 2, 0), { color = COLOR.sky, scale = 0.45, count = 0.5 }) end
			end
		end)
	elseif act == "dive" then
		ClassFX.Sound("whoosh", at, 0.7, 0.9)
		ClassFX.Sound("wind", at, 0.4, 1.6)
	elseif act == "jab" then
		after(0.25, function() ClassFX.Sound("whoosh", at, 0.5, 1.2) end)
	elseif act == "charge" then
		ClassFX.Sound("whoosh", at, 0.7, 0.75)
		local from, to = msg.from :: Vector3, msg.to :: Vector3
		after(0.1, function()
			streak(from + Vector3.new(0, 3, 0), to + Vector3.new(0, 3, 0), 1.6, 0.5, COLOR.moon, CORE.moon)
		end)
		for k = 0, 3 do
			after(k * 0.18, function()
				local r = recOf(msg.model)
				if r and FxBudget.Allow("moonDust", 8) then dust(ground(r.pos), 0.6, Color3.fromRGB(200, 196, 220)) end
			end)
		end
	end
end

local function onRockHammer(msg: any)
	local p = ground(msg.pos)
	FireFX.Cracks(p, msg.radius * 0.8, 2.2, false)
	PackFX.Burst("Anime/Crack-01", CFrame.new(p), { color = COLOR.rock, scale = 0.8 })
	floorRing(p, msg.radius, 0.4, COLOR.rock, 1.2, CORE.rock)
	debris(p, 8, 20, true)
	dust(p, 1.1)
	ClassFX.Sound("rockHit", p, 0.9, 0.65)
	ClassFX.Sound("boom", p, 0.5, 1.2)
	shakeAt(p, 0.6, 0.25, 45)
end

local function onSkyDiveHit(msg: any)
	local p = ground(msg.pos)
	PackFX.Burst("Anime/Wind-02", CFrame.new(p + Vector3.new(0, 1, 0)), { color = COLOR.sky, scale = 0.8 })
	floorRing(p, msg.radius, 0.35, COLOR.sky, 0.9, CORE.sky)
	sparks(p + Vector3.new(0, 1.5, 0), 12, 16, CORE.sky)
	ClassFX.Sound("punch", p, 0.5, 1.2)
	shakeAt(p, 0.3, 0.15, 30)
end

-- The feathers: blades of white with a cyan edge, flying straight; drawn
-- until they reach an enemy (judged here for the picture), a wall or their
-- range.
local function mobNear(pos: Vector3, reach: number): boolean
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return false end
	for _, m in ipairs(mobs:GetChildren()) do
		local r = m:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r and (r.Position - pos).Magnitude < reach then return true end
	end
	return false
end

local function wallDistance(from: Vector3, dir: Vector3, length: number): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local ignore: { Instance } = { ClassFX.Folder(), rigFolder }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(from, dir * length, params)
	return if hit then hit.Distance else length
end

local function onFeathers(msg: any)
	local from = msg.from :: Vector3
	local to = msg.to :: Vector3
	local drop = (to.Y - from.Y)
	for _, d in ipairs(msg.dirs or {}) do
		local dir = d :: Vector3
		local length = wallDistance(from, dir, msg.range)
		local f = part({ Size = Vector3.new(0.12, 0.5, 1.7), Color = Color3.fromRGB(236, 242, 250), Material = Enum.Material.SmoothPlastic })
		local edge = part({ Size = Vector3.new(0.14, 0.12, 1.5), Color = COLOR.sky })
		local list = {}
		addTrail(f, COLOR.sky, 0.4, 0.14, list)
		local flown = 0
		animate(length / msg.speed + 0.05, function(_u, dt)
			flown += msg.speed * dt
			local k = math.min(flown / math.max(length, 1), 1)
			local p = from + dir * flown + Vector3.new(0, drop * k * 0.9, 0)
			local cf = CFrame.lookAt(p, p + dir + Vector3.new(0, drop / math.max(length, 1), 0)) * CFrame.Angles(0, 0, math.rad(flown * 30))
			f.CFrame = cf
			edge.CFrame = cf * CFrame.new(0, 0.28, 0.05)
			if flown >= length or mobNear(p, 2.8) then
				f:Destroy()
				edge:Destroy()
				return true
			end
			return nil
		end)
	end
end

local function onFeatherHit(msg: any)
	if not FxBudget.Allow("featherHit", 16) then return end
	sparks(msg.pos, 6, 12, CORE.sky)
	if FxBudget.Allow("featherHitSnd", 6) then ClassFX.Sound("arrowHit", msg.pos, 0.35, 1.5) end
end

local function onMoonPulse(msg: any)
	local rec = recOf(msg.model)
	-- (a toss of the head, unless it's busy with an attack)
	if rec and not rec.anim.act and not rec.anim:sigActive() then rec.anim:play("pulse", 0.6) end
	if not nearCamera(msg.pos, 160) then return end
	local floor = ground(msg.pos)
	floorRing(floor, msg.radius, 0.9, COLOR.moon, 0.6, CORE.moon)
	if FxBudget.Allow("moonPulse", 3) then ClassFX.Sound("chime", floor, 0.3, 1.3) end
	for _, c in ipairs(msg.healed or {}) do
		local r = rootOf(c)
		if r and FxBudget.Allow("moonHeal", 8) then sparks(r.Position, 6, 6, COLOR.moon) end
	end
end

-- ── Signatures ──────────────────────────────────────────────────────────────
local function rockSlamFX(msg: any)
	local s = BEAST.rock.sig
	local to = ground(msg.to)
	local radius = msg.radius :: number
	ClassFX.Sound("rockHit", msg.from, 0.6, 0.6)
	-- the spot it'll come down on, burning in as it rises
	after(s.leapFrom, function()
		sigilFor(to, radius * 0.75, COLOR.rock, s.hit - s.leapFrom, 3)
		ClassFX.Sound("fireWhoosh", to, 0.7, 0.55)
	end)
	after(s.hit, function()
		FireFX.Explosion(to, radius * 0.45)
		FireFX.Cracks(to, radius, 3.5, true)
		PackFX.Burst("Big/Big-Crack-01", CFrame.new(to), { color = COLOR.rock, scale = radius / 11 })
		floorRing(to, radius, 0.6, COLOR.rock, 2, DEEP_EMBER)
		after(0.12, function() floorRing(to, radius * 1.4, 0.5, DEEP_EMBER, 1.2, COLOR.rock) end)
		spikeCrater(to, radius * 0.3, radius * 0.75, 3, 6.5, DEEP_EMBER, 1.4)
		debris(to, 16, 40, true)
		dust(to, 2)
		ClassFX.Sound("boom", to, 1, 0.75)
		ClassFX.Sound("quake", to, 0.9, 0.9)
		shakeAt(to, 1.5, 0.5, 90)
	end)
	-- fissures: lava splitting out along the floor, erupting as they run
	after(s.fissureAt, function()
		local n = msg.fissures or 4
		local len = msg.fissureLen or 18
		local from = msg.from :: Vector3
		local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
		local face = if d.Magnitude > 0.5 then d.Unit else Vector3.new(0, 0, -1)
		for k = 0, n - 1 do
			local dir = (CFrame.Angles(0, k * math.pi * 2 / n + math.pi / n, 0) * CFrame.lookAt(Vector3.zero, face)).LookVector
			local start = to + dir * radius * 0.6
			local segs = math.floor(len / 2.2)
			local spikes: { Spike } = {}
			for i = 0, segs - 1 do
				local f = i / math.max(segs - 1, 1)
				local side = Vector3.new(-dir.Z, 0, dir.X) * (math.random() - 0.5) * 1.6
				local p = ground(start + dir * (i * 2.2) + side + Vector3.new(0, 2, 0))
				-- (growing as the split runs out, leaning along it)
				local h = (2.6 + f * 3.6) * (0.75 + math.random() * 0.5)
				local cf = CFrame.lookAt(p, p + dir) * CFrame.Angles(math.rad(-(14 + math.random() * 30)), 0, math.rad((math.random() - 0.5) * 50))
					* CFrame.Angles(0, math.random() * 6.28, 0)
				table.insert(spikes, makeSpike(cf, h * 0.5, h, DEEP_EMBER, i * 0.04))
				if i % 2 == 0 then
					after(i * 0.04, function()
						if FxBudget.Allow("fissure", 30) then FireFX.Flames(p, 1.4, 2, 0.8) end
						if FxBudget.Allow("fissureDust", 20) then dust(p, 0.5) end
					end)
				end
				if i == segs - 1 then
					after(i * 0.04, function()
						FireFX.Column(p, 9, 2.2)
						ClassFX.Sound("fireBurst", p, 0.5, 0.8)
					end)
				end
			end
			erupt(spikes, 1.2)
		end
		shakeAt(to, 0.7, 0.3, 70)
	end)
end

local function skyCircleFX(msg: any)
	local s = BEAST.sky.sig
	local to = ground(msg.to)
	local radius = msg.radius :: number
	local lead = msg.lead :: number
	-- the dash: a streak of wind to the spot
	streak(msg.from + Vector3.new(0, BEAST.sky.fly + 2, 0), to + Vector3.new(0, 2, 0), 1.4, 0.35, COLOR.sky, CORE.sky)
	ClassFX.Sound("whoosh", msg.from, 0.8, 0.9)
	sigilFor(to, radius * 0.8, COLOR.sky, lead + s.hit, -2.6)
	-- the cyclone, while it circles
	after(lead + s.from, function()
		local runFor = s.to - s.from
		local tornado = PackFX.Run("Big/Tornado-01", CFrame.new(to), runFor, { color = COLOR.sky, scale = radius / 11 })
		local _ = tornado
		ClassFX.Sound("wind", to, 0.9, 1)
		local spin = 0
		animate(runFor, function(u, dt)
			spin += dt
			if spin > 0.16 and FxBudget.Allow("skyCyclone", 14) then
				spin = 0
				-- wind arcs whirling round the eye
				local a = math.random() * math.pi * 2
				local h = math.random() * 6 + 1
				SwordFX.Arc({ cf = CFrame.new(to + Vector3.new(0, h, 0)) * CFrame.Angles(0, a, 0), radius = radius * (0.45 + math.random() * 0.4),
					arc = 120, width = 0.6, color = COLOR.sky, life = 0.25, draw = 0.12, core = WHITE })
			end
			return nil
		end)
	end)
	after(lead + s.hit, function()
		-- (the burst as it lands: skyBurst draws the rest)
		ClassFX.Sound("whoosh", to, 0.9, 0.6)
	end)
end

local function onSkyBurst(msg: any)
	local p = ground(msg.pos)
	local r = msg.radius :: number
	PackFX.Burst("Anime/Wind-02", CFrame.new(p + Vector3.new(0, 1.5, 0)), { color = COLOR.sky, scale = r / 7 })
	shell(p + Vector3.new(0, 3, 0), 3, r * 2.4, 0.45, COLOR.sky)
	floorRing(p, r, 0.5, COLOR.sky, 1.6, CORE.sky)
	after(0.1, function() floorRing(p, r * 1.3, 0.45, COLOR.sky, 1, CORE.sky) end)
	sparks(p + Vector3.new(0, 4, 0), 30, 30, CORE.sky)
	ClassFX.Sound("boom", p, 0.5, 1.4)
	ClassFX.Sound("wind", p, 0.6, 1.5)
	shakeAt(p, 0.9, 0.35, 70)
end

local function moonBloomSigil(msg: any)
	local s = BEAST.moon.sig
	local to = ground(msg.to)
	local lead = msg.lead :: number
	sigilFor(to, msg.radius * 0.85, COLOR.moon, lead + s.hit + 0.2, 0.7)
	after(lead + 0.9, function() ClassFX.Sound("angel", to, 0.4, 1.3) end)
end

-- Radiant Bloom: petals of moonlight opening out of the floor, a pillar of
-- light, the healed sparkling.
local function onMoonBloom(msg: any)
	local p = ground(msg.pos)
	local r = msg.radius :: number
	local petals = {}
	local n = 10
	for k = 1, n do
		local a = k / n * math.pi * 2
		local pt = part({ Size = Vector3.new(r * 0.32, 0.18, r * 0.62), Color = if k % 2 == 0 then CORE.moon else COLOR.moon, Transparency = 0.1 }, "WedgePart")
		table.insert(petals, { p = pt, a = a })
	end
	animate(1.3, function(u, _dt)
		local open = easeOut(math.min(u / 0.35, 1))
		local fade = math.clamp((u - 0.55) / 0.45, 0, 1)
		for _, it in ipairs(petals) do
			local tilt = math.rad(80 - 62 * open)
			local cf = CFrame.new(p) * CFrame.Angles(0, -it.a, 0) * CFrame.new(0, 0.3 + r * 0.1 * open, -r * 0.18 * open)
				* CFrame.Angles(-tilt, 0, 0) * CFrame.new(0, 0, -r * 0.3)
			it.p.CFrame = cf
			it.p.Transparency = 0.1 + 0.9 * fade
		end
		if u >= 1 then for _, it in ipairs(petals) do it.p:Destroy() end end
		return nil
	end)
	PackFX.Burst("Anime/Shiny-01", CFrame.new(p + Vector3.new(0, 2, 0)), { color = COLOR.moon, scale = r / 9 })
	ClassFX.Pillar(p, CORE.moon, r * 0.5, 40, 0.9)
	shell(p + Vector3.new(0, 2, 0), 3, r * 2.2, 0.55, COLOR.moon)
	floorRing(p, r, 0.7, COLOR.moon, 1.8, CORE.moon)
	sparks(p + Vector3.new(0, 3, 0), 36, 20, CORE.moon)
	ClassFX.Sound("magicBurst", p, 0.8, 1)
	ClassFX.Sound("choir", p, 0.6, 1.1)
	ClassFX.Sound("rockHit", p, 0.4, 1.4)
	shakeAt(p, 0.6, 0.3, 60)
	for _, c in ipairs(msg.healed or {}) do
		local rr = rootOf(c)
		if rr then
			sparks(rr.Position, 14, 10, COLOR.moon)
			flare(rr.Position, 5, 0.4, COLOR.moon)
		end
	end
end

local function onSig(msg: any)
	local rec = recOf(msg.model)
	local kind = msg.beast
	if rec then
		local travel = if kind == "sky" then Vector3.new(msg.travel, 1, msg.travel) else nil
		rec.anim:signature(msg.lead or 0, msg.clip, travel)
	end
	if kind == "rock" then rockSlamFX(msg)
	elseif kind == "sky" then skyCircleFX(msg)
	elseif kind == "moon" then moonBloomSigil(msg) end
end

local function onSigReady(msg: any)
	if not mine(msg) then return end
	sigReadyAt[msg.beast] = msg.at
end

-- ── R: Divine Cataclysm ─────────────────────────────────────────────────────
local function tint(seconds: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "SummonerCataclysm"
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.5), { Brightness = 0.04, Contrast = 0.16, Saturation = 0.15,
		TintColor = Color3.fromRGB(226, 246, 255) }):Play()
	task.delay(seconds, function()
		TweenService:Create(cc, TweenInfo.new(0.8), { Brightness = 0, Contrast = 0, Saturation = 0, TintColor = WHITE }):Play()
		Debris:AddItem(cc, 0.85)
	end)
end

local function screenFlash(t: number, color: Color3)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SummonerFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 120
	gui.Parent = player:WaitForChild("PlayerGui")
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 0.25
	f.BorderSizePixel = 0
	f.Parent = gui
	TweenService:Create(f, TweenInfo.new(t), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, t + 0.05)
end

local function onUlt(msg: any)
	local anchor = ground(msg.pos)
	local gather = msg.gather :: number
	local center = anchor + Vector3.new(0, 10, 0)
	if nearCamera(anchor, 200) then tint(gather + msg.clip) end
	ClassFX.Sound("angel", anchor, 0.8, 1)
	ClassFX.Sound("charge", anchor, 0.7, 0.8)
	sigilFor(anchor, 9, COLOR.fused, gather + 0.3, 1.6)
	-- every beast's light streams to the meeting point
	for _, b in ipairs(msg.beasts or {}) do
		local rec = recOf(b.model)
		local color = COLOR[b.beast] or BOND
		animate(gather, function(u, _dt)
			if rec and FxBudget.Allow("ultGather", 30) then
				streak(chestOf(rec), center, 0.5 + u, 0.12, color)
			end
			return nil
		end)
	end
	-- the light gathers into a sphere and bursts
	local orb = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5, CFrame = CFrame.new(center), Color = WHITE })
	animate(gather, function(u, _dt)
		orb.Size = Vector3.one * (0.5 + 7 * u * u)
		orb.Color = WHITE:Lerp(COLOR.fused, 0.4 * u)
		if u >= 1 then orb:Destroy() end
		return nil
	end)
	after(gather, function()
		flare(center, 34, 0.6, COLOR.fused)
		shell(center, 6, 46, 0.6, COLOR.fused)
		sparks(center, 50, 34, CORE.fused)
		if nearCamera(anchor, 140) then screenFlash(0.35, Color3.fromRGB(230, 250, 255)) end
		ClassFX.Sound("magicBurst", anchor, 1, 0.7)
		ClassFX.Sound("boom", anchor, 0.7, 1.1)
		shakeAt(anchor, 0.9, 0.4, 90)
	end)
end

local function onFusedRise(msg: any)
	local function go()
		local rec = recOf(msg.model)
		if not rec then return false end
		local tr = msg.travel or 0.75
		rec.anim:signature(0, msg.clip, Vector3.new(tr, 1, tr))
		return true
	end
	if not go() then
		-- (the body may not have arrived yet)
		task.spawn(function()
			for _ = 1, 30 do
				task.wait(0.05)
				if go() then return end
			end
		end)
	end
	ClassFX.Sound("thunder", msg.pos, 0.6, 0.8)
end

local function onUltRain(msg: any)
	if not FxBudget.Allow("ultRain", 12) then return end
	local p = msg.pos :: Vector3
	local from = p + Vector3.new(math.random(-8, 8), 46, math.random(-8, 8))
	local star = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(from), Color = WHITE })
	local list = {}
	addTrail(star, if math.random() < 0.5 then COLOR.fused else COLOR.moon, 1.4, 0.2, list)
	animate(0.16, function(u, _dt)
		star.CFrame = CFrame.new(from:Lerp(p, u * u))
		if u >= 1 then
			star:Destroy()
			if FxBudget.Allow("ultRainHit", 10) then
				PackFX.Burst("Anime/Shiny-01", CFrame.new(p + Vector3.new(0, 1, 0)), { color = COLOR.fused, scale = 0.55, count = 0.5 })
				floorRing(p, 4, 0.3, COLOR.fused, 0.7)
			end
			if FxBudget.Allow("ultRainSnd", 5) then ClassFX.Sound("fireBurst", p, 0.3, 1.5) end
		end
		return nil
	end)
end

local function onUltRays(msg: any)
	local rec = recOf(msg.model)
	if not rec then return end
	local from = chestOf(rec)
	for _, m in ipairs(msg.targets or {}) do
		local r = rootOf(m)
		if r and FxBudget.Allow("ultRay", 40) then
			streak(from, r.Position, 0.9, 0.16, COLOR.fused, WHITE)
			if FxBudget.Allow("ultRayHit", 20) then sparks(r.Position, 5, 10, CORE.fused) end
		end
	end
	if FxBudget.Allow("ultRaySnd", 5) then ClassFX.Sound("thunder", from, 0.25, 1.6) end
end

-- Scarred floor that stays a while, then sinks away: `parts` fade out over
-- `fade` seconds after `hold`.
local function linger(parts: { BasePart }, hold: number, fade: number)
	task.delay(hold, function()
		for _, p in ipairs(parts) do
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ Transparency = 1, CFrame = p.CFrame * CFrame.new(0, -0.6, 0) }):Play()
			end
		end
		task.delay(fade + 0.1, function()
			for _, p in ipairs(parts) do p:Destroy() end
		end)
	end)
end

local SCORCH = Color3.fromRGB(34, 28, 30)
-- The trench the Skyrockorn tears along the floor under its flight: a
-- scorched furrow, a crack of its light down the middle, broken rock
-- heaved up along both lips, dust and stones thrown out of it.
local function onUltTrench(msg: any)
	local a, b = msg.a :: Vector3, msg.b :: Vector3
	local w = msg.width :: number
	local d = Vector3.new(b.X - a.X, 0, b.Z - a.Z)
	local len = d.Magnitude
	if len < 0.2 then return end
	local dir = d / len
	local mid = Vector3.new((a.X + b.X) / 2, math.max(a.Y, b.Y), (a.Z + b.Z) / 2)
	local cf = CFrame.lookAt(mid, mid + dir)
	local list: { BasePart } = {}
	table.insert(list, part({ Size = Vector3.new(w * 0.8, 0.3, len + 1.2), CFrame = cf * CFrame.new(0, 0.1, 0),
		Color = SCORCH, Material = Enum.Material.Slate }))
	table.insert(list, part({ Size = Vector3.new(w * 0.5, 0.32, len + 1), CFrame = cf * CFrame.new(0, 0.12, 0),
		Color = Color3.fromRGB(18, 14, 16), Material = Enum.Material.Basalt }))
	local glow = part({ Size = Vector3.new(0.45, 0.36, len + 0.6), CFrame = cf * CFrame.new((math.random() - 0.5) * 0.6, 0.14, 0)
		* CFrame.Angles(0, math.rad(math.random(-8, 8)), 0), Color = COLOR.fused })
	TweenService:Create(glow, TweenInfo.new(2.5), { Color = Color3.fromRGB(40, 120, 160) }):Play()
	table.insert(list, glow)
	-- the lips: spikes of rock heaved up and tipped out of the furrow
	local spikes: { Spike } = {}
	local across = Vector3.new(-dir.Z, 0, dir.X)
	for _, sd in ipairs({ -1, 1 }) do
		if math.random() < 0.75 then
			local h = 3.2 + math.random() * 3.2
			local at = mid + across * sd * w * 0.5 + dir * ((math.random() - 0.5) * len)
			local cf = CFrame.lookAt(at, at + across * sd) * CFrame.Angles(math.rad(-(22 + math.random() * 30)), 0, 0)
				* CFrame.Angles(0, math.random() * 6.28, 0)
			table.insert(spikes, makeSpike(cf, h * 0.5, h, if math.random() < 0.5 then COLOR.fused else nil, math.random() * 0.05))
		end
	end
	erupt(spikes, 3.6)
	linger(list, 5.5, 1.6)
	if FxBudget.Allow("ultTrenchFx", 6) then
		dust(mid, 0.9)
		debris(mid, 4, 22, false)
	end
	if FxBudget.Allow("ultTrenchCrack", 3) then
		PackFX.Burst("Anime/Crack-01", cf, { color = COLOR.fused, scale = w / 8 })
		ClassFX.Sound("rockHit", mid, 0.5, 0.7 + math.random() * 0.2)
	end
	if FxBudget.Allow("ultTrenchShake", 4) then shakeAt(mid, 0.45, 0.15, 50) end
end

-- A tornado dropped in its wake: a whirling column of its wind, wandering
-- off across the floor with rocks and dust spun up round it.
local function onUltTornado(msg: any)
	local start = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local speed = msg.speed :: number
	local life = msg.life :: number
	local radius = msg.radius :: number
	local run = PackFX.Run("Big/Tornado-01", CFrame.new(start), life, { color = COLOR.fused, scale = radius / 9 })
	local inner = PackFX.Run("Big/Tornado-01", CFrame.new(start), life, { color = CORE.fused, scale = radius / 15 })
	local rocks: { BasePart } = {}
	for k = 1, 5 do
		local s = 0.5 + math.random() * 0.6
		table.insert(rocks, part({ Size = Vector3.new(s, s * 0.8, s), Color = ROCK[(k % #ROCK) + 1], Material = Enum.Material.Slate }))
	end
	ClassFX.Sound("wind", start, 0.7, 0.8 + math.random() * 0.3)
	floorRing(start, radius, 0.5, COLOR.fused, 1, CORE.fused)
	local spin, nextArc, nextDust = 0, 0, 0
	animate(life, function(u, dt)
		local age = u * life
		local p = start + dir * speed * age
		local cf = CFrame.new(p)
		run.move(cf)
		inner.move(cf)
		spin += dt * 7
		-- (it winds up, then frays away at the end)
		local k = math.min(age / 0.4, 1) * (1 - math.clamp((age - life + 0.6) / 0.6, 0, 1))
		for i, r in ipairs(rocks) do
			local a = spin * (1 + i * 0.12) + i * 1.3
			local h = (age * 4 + i * 1.7) % 7
			local rr = radius * (0.25 + h / 7 * 0.45) * k
			r.CFrame = CFrame.new(p + Vector3.new(math.cos(a) * rr, 0.5 + h, math.sin(a) * rr)) * CFrame.Angles(a, a * 0.7, 0)
			r.Transparency = 1 - k
		end
		nextArc -= dt
		if nextArc <= 0 and FxBudget.Allow("ultTornadoArc", 16) then
			nextArc = 0.18
			SwordFX.Arc({ cf = CFrame.new(p + Vector3.new(0, math.random() * 6 + 0.5, 0)) * CFrame.Angles(0, math.random() * 6.3, 0),
				radius = radius * (0.35 + math.random() * 0.35), arc = 140, width = 0.5, color = COLOR.fused, life = 0.22, draw = 0.1, core = CORE.fused })
		end
		nextDust -= dt
		if nextDust <= 0 and FxBudget.Allow("ultTornadoDust", 6) then
			nextDust = 0.45
			dust(p, 0.7)
		end
		if u >= 1 then
			for _, r in ipairs(rocks) do r:Destroy() end
		end
		return nil
	end)
end

-- The crash's crater: a scorched bowl, its light cracking out of it in
-- spokes, a ring of heaved-up rock round the rim; it smoulders a while.
local function crater(p: Vector3, r: number)
	local list: { BasePart } = {}
	local disc = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, r * 2, r * 2),
		CFrame = CFrame.new(p + Vector3.new(0, 0.08, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = SCORCH, Material = Enum.Material.Slate })
	table.insert(list, disc)
	table.insert(list, part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.42, r * 1.2, r * 1.2),
		CFrame = CFrame.new(p + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = Color3.fromRGB(16, 12, 14),
		Material = Enum.Material.Basalt }))
	for k = 1, 10 do
		local a = k / 10 * math.pi * 2 + math.random() * 0.3
		local len = r * (0.6 + math.random() * 0.5)
		local c = part({ Size = Vector3.new(0.5, 0.46, len), Color = if k % 2 == 0 then COLOR.fused else COLOR.moon,
			CFrame = CFrame.new(p + Vector3.new(0, 0.12, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -len / 2) })
		TweenService:Create(c, TweenInfo.new(4), { Color = Color3.fromRGB(50, 90, 120) }):Play()
		table.insert(list, c)
	end
	-- the rim: great spikes of rock thrown up round the bowl, smaller ones
	-- inside it
	spikeCrater(p, r * 0.45, r * 1.05, 3, 9, COLOR.fused, 5.5)
	FireFX.Cracks(p, r * 1.2, 6, true)
	linger(list, 7, 2)
end

local function onUltImpact(msg: any)
	local p = ground(msg.pos)
	local r = msg.radius :: number
	PackFX.Burst("Big/Explosion-01", CFrame.new(p + Vector3.new(0, 2, 0)), { color = COLOR.fused, scale = r / 12 })
	PackFX.Burst("Big/Big-Crack-01", CFrame.new(p), { color = COLOR.fused, scale = r / 12 })
	flare(p + Vector3.new(0, 4, 0), r * 0.9, 0.6, COLOR.fused)
	shell(p + Vector3.new(0, 2, 0), 6, r * 2.6, 0.7, COLOR.fused)
	floorRing(p, r, 0.8, COLOR.fused, 2.6, COLOR.sky)
	after(0.12, function() floorRing(p, r * 1.35, 0.7, COLOR.moon, 1.6, WHITE) end)
	after(0.24, function() floorRing(p, r * 1.7, 0.6, COLOR.rock, 1.2, WHITE) end)
	if msg.crater then crater(p, msg.crater) end
	debris(p, 26, 46, true)
	dust(p, 2.6)
	sparks(p + Vector3.new(0, 4, 0), 60, 40, CORE.fused)
	ClassFX.Pillar(p, WHITE, r * 0.6, 60, 0.8)
	if nearCamera(p, 160) then screenFlash(0.5, WHITE) end
	ClassFX.Sound("boom", p, 1, 0.6)
	ClassFX.Sound("quake", p, 1, 0.8)
	ClassFX.Sound("thunder", p, 0.8, 0.7)
	shakeAt(p, 2.2, 0.7, 130)
end

-- ── M1: the Bond Bolt ───────────────────────────────────────────────────────
-- A bolt of pale spirit-light with a white core and three motes (amber, sky,
-- moon: the three beasts) spiralling round it.
local function fireBolt(from: Vector3, dir: Vector3, speed: number)
	local length = wallDistance(from, dir, BOLT.range)
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.55, CFrame = CFrame.new(from), Color = WHITE })
	local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.3, CFrame = CFrame.new(from), Color = BOND, Transparency = 0.45 })
	local list = {}
	addTrail(glow, BOND, 0.9, 0.18, list)
	local motes = {}
	for _, c in ipairs({ COLOR.rock, COLOR.sky, COLOR.moon }) do
		table.insert(motes, part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.32, Color = c }))
	end
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local flown = 0
	animate(length / speed + 0.05, function(_u, dt)
		flown += speed * dt
		local p = from + dir * math.min(flown, length)
		core.CFrame = CFrame.new(p)
		glow.CFrame = CFrame.new(p)
		for k, m in ipairs(motes) do
			local a = flown * 0.9 + k * math.pi * 2 / 3
			m.CFrame = CFrame.new(p + side * math.cos(a) * 0.75 + Vector3.new(0, math.sin(a) * 0.75, 0))
		end
		if flown >= length or mobNear(p, 2.6) then
			core:Destroy()
			glow:Destroy()
			for _, m in ipairs(motes) do m:Destroy() end
			if FxBudget.Allow("sumBoltEnd", 12) then
				flare(p, 2.6, 0.18, BOND)
				sparks(p, 6, 12, BOND)
			end
			return true
		end
		return nil
	end)
end

local function onBolt(msg: any)
	if mine(msg) then return end -- (ours left the staff already)
	for _, d in ipairs(msg.dirs or {}) do fireBolt(msg.from, d, msg.speed) end
end

-- The Focus: a turning sigil over the enemy every beast is now on, and a
-- tether of light to it from each of your beasts.
local focusOn: { [Model]: number } = {}
local function onFocus(msg: any)
	local target = msg.target
	if typeof(target) ~= "Instance" or not target:IsA("Model") then return end
	local r = rootOf(target) or target.PrimaryPart
	if not r then return end
	local untilT = os.clock() + (msg.life or 4)
	local had = focusOn[target]
	focusOn[target] = untilT
	if mine(msg) then
		for _, rec in pairs(records) do
			if rec.owner == player.UserId and not rec.leaving then
				streak(chestOf(rec), r.Position, 0.35, 0.25, COLOR[rec.kind] or BOND)
			end
		end
	end
	if had and had > os.clock() then return end
	local ring = part({ Size = Vector3.new(0.12, 3.4, 3.4), Shape = Enum.PartType.Cylinder, Color = BOND, Transparency = 0.2 })
	local pips = {}
	for _, c in ipairs({ COLOR.rock, COLOR.sky, COLOR.moon }) do
		table.insert(pips, part({ Size = Vector3.new(0.4, 0.4, 0.4), Color = c }))
	end
	local spin = 0
	animate(30, function(_u, dt)
		spin += dt * 2.5
		local stop = os.clock() > (focusOn[target] or 0) or not target.Parent or not r.Parent
		if stop then
			ring:Destroy()
			for _, p in ipairs(pips) do p:Destroy() end
			focusOn[target] = nil
			return true
		end
		local size = target:GetExtentsSize()
		local top = r.Position + Vector3.new(0, size.Y * 0.5 + 1.6, 0)
		local pulse = 1 + 0.08 * math.sin(spin * 3)
		ring.Size = Vector3.new(0.12, 3.4 * pulse, 3.4 * pulse)
		ring.CFrame = CFrame.new(top) * CFrame.Angles(0, spin, math.rad(90))
		for k, p in ipairs(pips) do
			local a = spin + k * math.pi * 2 / 3
			p.CFrame = CFrame.new(top + Vector3.new(math.cos(a) * 1.9, 0, math.sin(a) * 1.9)) * CFrame.Angles(spin, spin, 0)
		end
		return nil
	end)
end

local function onBoltEnd(msg: any)
	if mine(msg) then return end
	if FxBudget.Allow("sumBoltEnd", 12) then sparks(msg.pos, 6, 12, BOND) end
end

-- ── The Summoner's poses (R6: each limb posed as its forearm / shin) ────────
local Poses = {}

-- The staff thrust out at the target, the torso turning behind it.
function Poses.bolt(char: Model)
	CastPoses.play(char, {
		{ dur = 0.06, style = Enum.EasingStyle.Quart, pose = { RS = { 100, -10, 0 }, W = { -4, -16, 0 }, LS = { -14, 0, -10 }, N = { 0, 12, 0 } } },
		{ dur = 0.16, pose = { RS = { 94, -8, 0 }, W = { -3, -12, 0 }, LS = { -10, 0, -8 } } },
	}, 0.22)
end

-- Rockborn: the staff raised high, then driven down at the floor in a lunge
-- as the meteor falls.
function Poses.rock(char: Model)
	CastPoses.play(char, {
		{ dur = 0.14, pose = { W = { 12, 0, 0 }, RS = { 168, 0, 12 }, LS = { 70, 0, -34 }, N = { -18, 0, 0 },
			RH = { -6, 0, 0 }, LH = { 6, 0, 0 } } },
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.5, 0 }, W = { -24, 0, 0 },
			RS = { 52, 0, 8 }, LS = { 24, 0, -44 }, RH = { 28, 0, 0 }, LH = { -18, 0, 0 }, N = { 16, 0, 0 } } },
		{ dur = 0.34, pose = { Root = { 0, 0, 0, 0, -0.45, 0 }, W = { -20, 0, 0 }, RS = { 50, 0, 8 }, LS = { 22, 0, -42 },
			RH = { 24, 0, 0 }, LH = { -16, 0, 0 }, N = { 12, 0, 0 } } },
	}, 0.3)
end

-- Skyfeather: the arm swept low behind and flung up over the head, as if
-- throwing the bird into the sky; the eyes follow it.
function Poses.sky(char: Model)
	CastPoses.play(char, {
		{ dur = 0.1, pose = { W = { -6, 26, 0 }, RS = { -38, 0, 34 }, LS = { 44, 0, -22 }, N = { 6, -10, 0 }, RH = { -8, 0, 0 }, LH = { 10, 0, 0 } } },
		{ dur = 0.12, style = Enum.EasingStyle.Back, pose = { W = { 10, -22, 0 }, RS = { 168, 0, -8 }, LS = { -24, 0, -30 },
			N = { -28, 0, 0 }, RH = { 10, 0, 0 }, LH = { -8, 0, 0 } } },
		{ dur = 0.3, pose = { W = { 8, -18, 0 }, RS = { 160, 0, -6 }, LS = { -20, 0, -28 }, N = { -24, 0, 0 } } },
	}, 0.3)
end

-- Lunari: down on one knee, the free hand laid on the floor where the gate
-- opens, then lifted as the stag rises.
function Poses.moon(char: Model)
	CastPoses.play(char, {
		{ dur = 0.14, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -1.0, 0 }, W = { -30, 0, 0 },
			LS = { 74, 0, -8 }, RS = { 34, 0, 26 }, RH = { 70, 0, 0 }, LH = { -34, 0, 0 }, N = { 14, 0, 0 } } },
		{ dur = 0.3, pose = { Root = { 0, 0, 0, 0, -1.0, 0 }, W = { -28, 0, 0 }, LS = { 72, 0, -8 }, RS = { 32, 0, 26 },
			RH = { 68, 0, 0 }, LH = { -32, 0, 0 }, N = { 12, 0, 0 } } },
		{ dur = 0.18, style = Enum.EasingStyle.Back, pose = { Root = { 0, 0, 0, 0, -0.1, 0 }, W = { 6, 0, 0 },
			LS = { 158, 0, -18 }, RS = { 40, 0, 30 }, N = { -14, 0, 0 } } },
		{ dur = 0.25, pose = { W = { 4, 0, 0 }, LS = { 150, 0, -16 }, RS = { 38, 0, 28 }, N = { -10, 0, 0 } } },
	}, 0.3)
end

-- A command (a signature): the staff snapped out at the spot, held, a
-- little shake of power in it.
function Poses.command(char: Model)
	CastPoses.play(char, {
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { RS = { 104, -4, 0 }, W = { -4, -20, 0 }, LS = { -26, 0, -18 },
			N = { -4, 14, 0 }, RH = { 10, 0, 0 }, LH = { -10, 0, 0 } } },
		{ dur = 0.3, pose = { RS = { 100, -4, 0 }, W = { -3, -18, 0 }, LS = { -22, 0, -16 }, N = { -2, 12, 0 } },
			wobble = function(t: number)
				local s = math.sin(t * 46) * 1.4
				return { RS = { s, 0, 0 } }
			end },
	}, 0.3)
end

-- The ult: both arms flung up to call the beasts, held while they gather,
-- then thrown down and out as they fuse.
function Poses.ult(char: Model, gather: number)
	local up = { W = { 16, 0, 0 }, RS = { 172, 0, 24 }, LS = { 172, 0, -24 }, N = { -30, 0, 0 } }
	CastPoses.play(char, {
		{ dur = 0.24, style = Enum.EasingStyle.Back, pose = up },
		{ dur = math.max(0.2, gather - 0.32), pose = up, wobble = function(t: number)
			local s = math.sin(t * 38) * 1.6
			return { RS = { s, 0, 0 }, LS = { -s, 0, 0 } }
		end },
		{ dur = 0.08, style = Enum.EasingStyle.Quart, pose = { Root = { 0, 0, 0, 0, -0.4, 0 }, W = { -16, 0, 0 },
			RS = { 76, 0, 66 }, LS = { 76, 0, -66 }, N = { 14, 0, 0 }, RH = { 14, 0, 4 }, LH = { -10, 0, -4 } } },
		{ dur = 0.45, pose = { Root = { 0, 0, 0, 0, -0.35, 0 }, W = { -12, 0, 0 }, RS = { 72, 0, 62 }, LS = { 72, 0, -62 } } },
	}, 0.4)
end
SummonerController.Poses = Poses

-- The staff in the fist. At rest it stands upright along the arm (head by
-- the shoulder); to cast it twirls over so the head points out past the
-- fist, wherever the (rigid R6) arm points: at the target, at the sky, at
-- the floor. It twirls back once the casting's done.
local castHoldUntil = 0
local holdK = 0
local CAST_TURN = CFrame.Angles(math.pi, 0, 0) * CFrame.new(0, 1.1, 0)
local function castHold(seconds: number)
	castHoldUntil = math.max(castHoldUntil, os.clock() + seconds)
end
local function stepGrip(dt: number)
	local char = player.Character
	local arm = char and char:FindFirstChild("Right Arm")
	local grip = arm and arm:FindFirstChild("RightGrip") :: Weld?
	if not grip or not isSummoner() then return end
	local want = if os.clock() < castHoldUntil then 1 else 0
	if math.abs(want - holdK) < 1e-3 then return end
	holdK += math.clamp(want - holdK, -dt * 9, dt * 9)
	local k = holdK * holdK * (3 - 2 * holdK)
	local rest = CFrame.new(0, -1, 0) * CFrame.Angles(math.rad(-90), 0, 0)
	local cast = CFrame.new(0, -1, 0) * CAST_TURN * CFrame.Angles(math.rad(-90), 0, 0)
	grip.C0 = rest:Lerp(cast, k)
end

-- A ripple off the staff tip when it commands or casts.
local function staffFlash(root: BasePart, dir: Vector3, color: Color3)
	local tip = root.Position + dir * 2.4 + Vector3.new(0, 1.2, 0)
	flare(tip, 3.4, 0.22, color)
	sparks(tip, 8, 10, color)
end

-- ── The beast cards ─────────────────────────────────────────────────────────
local hud: ScreenGui? = nil
type Card = { frame: Frame, life: Frame, sig: TextLabel, name: TextLabel }
local cards: { [string]: Card } = {}

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "SummonerCards"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 1)
	row.Position = UDim2.new(0.5, 0, 1, -128)
	row.Size = UDim2.fromOffset(420, 40)
	row.BackgroundTransparency = 1
	row.Parent = g
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
	for i, kind in ipairs(SummonerData.KINDS) do
		local f = Instance.new("Frame")
		f.LayoutOrder = i
		f.Size = UDim2.fromOffset(130, 40)
		f.BackgroundColor3 = Color3.fromRGB(14, 16, 26)
		f.BackgroundTransparency = 0.2
		f.BorderSizePixel = 0
		f.Parent = row
		local st = Instance.new("UIStroke")
		st.Color = COLOR[kind]
		st.Thickness = 1.5
		st.Parent = f
		local key = Instance.new("TextLabel")
		key.Size = UDim2.fromOffset(18, 18)
		key.Position = UDim2.fromOffset(4, 3)
		key.BackgroundColor3 = COLOR[kind]
		key.BorderSizePixel = 0
		key.Font = Enum.Font.Arcade
		key.TextSize = 14
		key.TextColor3 = Color3.new(0, 0, 0)
		key.Text = ({ "E", "F", "Q" })[i]
		key.Parent = f
		local name = Instance.new("TextLabel")
		name.Position = UDim2.fromOffset(26, 2)
		name.Size = UDim2.fromOffset(100, 18)
		name.BackgroundTransparency = 1
		name.Font = Enum.Font.Arcade
		name.TextSize = 14
		name.TextXAlignment = Enum.TextXAlignment.Left
		name.TextColor3 = COLOR[kind]
		name.TextStrokeTransparency = 0.4
		name.Text = SummonerData.TITLE[kind]
		name.Parent = f
		local bar = Instance.new("Frame")
		bar.Position = UDim2.fromOffset(4, 23)
		bar.Size = UDim2.new(1, -8, 0, 4)
		bar.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
		bar.BorderSizePixel = 0
		bar.Parent = f
		local life = Instance.new("Frame")
		life.Size = UDim2.fromScale(0, 1)
		life.BackgroundColor3 = COLOR[kind]
		life.BorderSizePixel = 0
		life.Parent = bar
		local sig = Instance.new("TextLabel")
		sig.Position = UDim2.fromOffset(4, 27)
		sig.Size = UDim2.new(1, -8, 0, 12)
		sig.BackgroundTransparency = 1
		sig.Font = Enum.Font.Arcade
		sig.TextSize = 11
		sig.TextXAlignment = Enum.TextXAlignment.Left
		sig.TextColor3 = Color3.fromRGB(200, 200, 210)
		sig.Text = "NOT SUMMONED"
		sig.Parent = f
		cards[kind] = { frame = f, life = life, sig = sig, name = name }
	end
end

local SIG_NAME = { rock = "GROUND SLAM", sky = "WIND CIRCLE", moon = "RADIANT BLOOM" }
local function refreshHud()
	if not hud then return end
	local on = isSummoner() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	if hud.Enabled ~= on then hud.Enabled = on end
	if not on then return end
	local now = serverNow()
	for kind, c in pairs(cards) do
		local expires = tonumber(player:GetAttribute("SUM_" .. kind))
		local out = expires ~= nil and expires > now
		local life = math.max(1, tonumber(player:GetAttribute("SUMLIFE_" .. kind)) or 16)
		local frac = if out then math.clamp((expires :: number - now) / life, 0, 1) else 0
		c.life.Size = UDim2.fromScale(frac, 1)
		local txt: string
		if not out then
			txt = "SUMMON"
			c.frame.BackgroundTransparency = 0.45
		else
			c.frame.BackgroundTransparency = 0.15
			local left = (sigReadyAt[kind] or 0) - now
			txt = if left > 0 then string.format("%s %.1f", SIG_NAME[kind], left) else "RECAST: " .. SIG_NAME[kind]
		end
		if c.sig.Text ~= txt then c.sig.Text = txt end
		local col = if out and (sigReadyAt[kind] or 0) <= now then COLOR[kind] else Color3.fromRGB(170, 170, 185)
		if c.sig.TextColor3 ~= col then c.sig.TextColor3 = col end
	end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
function SummonerController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	if now - lastBolt < BOLT.interval / speed then return true end
	lastBolt = now
	local dir = flat(deps.getAim(root))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	Poses.bolt(char)
	castHold(0.8)
	local origin = root.Position + dir * 1.6 + Vector3.new(0, 0.9, 0)
	local count = 1 + math.max(0, math.floor(tonumber(player:GetAttribute("Stat_projectileCount")) or 0))
	local boltSpeed = BOLT.speed * (tonumber(player:GetAttribute("Stat_projectileSpeed")) or 1)
	for k = 1, count do
		local d = flat((CFrame.Angles(0, (k - (count + 1) / 2) * BOLT.fan, 0) * CFrame.lookAt(Vector3.zero, dir)).LookVector)
		fireBolt(origin, d, boltSpeed)
	end
	flare(origin, 2.2, 0.14, BOND)
	ClassFX.Sound("poof", root, 0.4, 1.4)
	ClassFX.Sound("chime", root, 0.18, 1.6)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function SummonerController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

local function myBeast(kind: string): Rec?
	for _, rec in pairs(records) do
		if rec.owner == player.UserId and rec.kind == kind and not rec.leaving then return rec end
	end
	return nil
end

local function cursorOr(root: BasePart, dir: Vector3, range: number): Vector3
	local cursor = if deps.getCursor then deps.getCursor(root) else nil
	local target = root.Position + dir * math.min(range, 14)
	if cursor then
		local d = Vector3.new(cursor.X - root.Position.X, 0, cursor.Z - root.Position.Z)
		target = root.Position + (if d.Magnitude > range then d.Unit * range else d)
		target = Vector3.new(target.X, cursor.Y, target.Z)
	end
	return target
end

-- E / F / Q with that beast out: its signature at the cursor (the skill's
-- cooldown untouched). True when the press was used here.
function SummonerController.TryRecast(skillIndex: number, char: Model, root: BasePart): boolean
	local kind = SummonerData.SKILL_KIND[skillIndex]
	if not kind then return false end
	if not player:GetAttribute("SUM_" .. kind) then return false end
	local rec = myBeast(kind)
	if not rec then
		-- (it's out on the server but not drawn yet: still a recast)
		local exp = tonumber(player:GetAttribute("SUM_" .. kind))
		if not exp or exp <= serverNow() then return false end
	end
	if serverNow() < (sigReadyAt[kind] or 0) then return true end
	if os.clock() < busyUntil then return true end
	local dir = flat(deps.getAim(root))
	local aim = cursorOr(root, dir, BEAST[kind].sig.range + 10)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	Poses.command(char)
	castHold(0.9)
	staffFlash(root, dir, COLOR[kind])
	ClassFX.Sound("charge", root, 0.35, 1.6)
	-- (until the server says, assume it went)
	sigReadyAt[kind] = serverNow() + BEAST[kind].sig.cooldown
	busyUntil = os.clock() + 0.2
	Network.GetRemoteEvent(Network.Remotes.UseSkill):FireServer({
		skillIndex = skillIndex, origin = root.Position, direction = dir, targetPosition = aim,
	})
	return true
end

-- Returns where the skill is aimed (sent to the server).
function SummonerController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any, cursor: Vector3?): Vector3?
	local dir = flat(aimDir)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local range = config.range or 30
	local target = root.Position + dir * math.min(range, 14)
	if cursor then
		local d = Vector3.new(cursor.X - root.Position.X, 0, cursor.Z - root.Position.Z)
		target = root.Position + (if d.Magnitude > range then d.Unit * range else d)
		target = Vector3.new(target.X, cursor.Y, target.Z)
	end
	if skillIndex == 1 then
		char:SetAttribute("AllowSkillMovement", false)
		Poses.rock(char)
		castHold(1.0)
		staffFlash(root, dir, COLOR.rock)
		ClassFX.Sound("charge", root, 0.4, 0.9)
		if deps then deps.fovPunch(4, 0.2) end
		releaseAfter(char, 0.42)
		return target
	elseif skillIndex == 2 then
		char:SetAttribute("AllowSkillMovement", true)
		Poses.sky(char)
		castHold(0.9)
		staffFlash(root, dir, COLOR.sky)
		ClassFX.Sound("wind", root, 0.4, 1.6)
		releaseAfter(char, 0.3)
		return target
	elseif skillIndex == 3 then
		char:SetAttribute("AllowSkillMovement", false)
		Poses.moon(char)
		ClassFX.Sound("chime", root, 0.5, 0.9)
		releaseAfter(char, 0.62)
		return target
	elseif skillIndex == 4 then
		local gather = BEAST.fused.sig.gather
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = os.clock() + gather
		Poses.ult(char, gather)
		castHold(gather + 0.8)
		staffFlash(root, dir, COLOR.fused)
		releaseAfter(char, gather + 0.15)
		return root.Position
	end
	return nil
end

-- The fusion, seen close and low: the beasts converging over his head.
function SummonerController.PlayUltCutscene(char: Model, dir: Vector3)
	UltimateCameraChoreography.PlayCloseUp(char, dir, BEAST.fused.sig.gather, nil, nil, {
		startOffset = { 9, -1.5, 1.5 },
		endOffset = { 13, -2.5, 3 },
		focusHeight = 5,
		fovStart = 54,
		fovEnd = 70,
	})
end

-- ── Wiring ──────────────────────────────────────────────────────────────────
local HANDLERS: { [string]: (any) -> () } = {
	summon = onSummon, moonGate = onMoonGate, dismiss = onDismiss, blink = onBlink,
	act = onAct, rockHammer = onRockHammer, skyDiveHit = onSkyDiveHit,
	feathers = onFeathers, featherHit = onFeatherHit, moonPulse = onMoonPulse,
	sig = onSig, sigReady = onSigReady, skyBurst = onSkyBurst, moonBloom = onMoonBloom,
	ult = onUlt, fusedRise = onFusedRise, ultRain = onUltRain, ultRays = onUltRays, ultImpact = onUltImpact,
	ultTrench = onUltTrench, ultTornado = onUltTornado,
	bolt = onBolt, boltEnd = onBoltEnd, focus = onFocus,
}

function SummonerController.Init(d: Deps)
	deps = d
	rigFolder = Workspace:FindFirstChild("SummonRigs") :: Folder
	if not rigFolder then
		rigFolder = Instance.new("Folder")
		rigFolder.Name = "SummonRigs"
		rigFolder.Parent = Workspace
	end
	buildHud()
	task.spawn(function()
		local summons = Workspace:WaitForChild("Summons", 60)
		if not summons then return end
		summons.ChildAdded:Connect(function(m)
			if m:IsA("Model") then task.spawn(track, m) end
		end)
		summons.ChildRemoved:Connect(function(m)
			if m:IsA("Model") then untrack(m) end
		end)
		for _, m in ipairs(summons:GetChildren()) do
			if m:IsA("Model") then task.spawn(track, m) end
		end
	end)
	local hudAt = 0
	RunService.RenderStepped:Connect(function(dt)
		stepBeasts(dt)
		stepAnims(dt)
		stepGrip(dt)
		hudAt += dt
		if hudAt > 0.1 then
			hudAt = 0
			refreshHud()
		end
	end)
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		lastBolt = 0
		table.clear(sigReadyAt)
	end)
	Network.GetRemoteEvent("SummonerFX").OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[SummonerController]", msg.kind, err) end
		end
	end)
end

return SummonerController
