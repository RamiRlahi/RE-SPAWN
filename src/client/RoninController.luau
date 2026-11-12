--!strict
--[[
	RoninController.luau
	Client side of the Ronin (server: RoninServer). Plays the four baked katana
	moves (RoninMoves: per-frame R6 poses with the feet locked to the floor),
	swaps the katana between the right hand and the scabbard in the left hand
	frame by frame, slides the blade home on the sheathes, and draws the cuts.

	Your own moves are predicted on cast; everyone else's arrive over RoninFX
	and play on their character here (poses are local to each client).

	Effects follow CLAUDE.md: every per-cut part goes through FxBudget.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RoninLook = require(Shared:WaitForChild("RoninLook"))
local RoninMoves = require(Shared:WaitForChild("RoninMoves")) :: any
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local RoninStorm = require(script.Parent:WaitForChild("RoninStorm"))
local PackFX = require(script.Parent:WaitForChild("PackFX"))
-- (the Ronin's ability impacts are air shockwaves only: no lightning, no
-- explosions. The ult keeps its own blast: RoninStorm, ultBurst.)
local AirShock = require(script.Parent:WaitForChild("AirShock"))
-- (the particle pack's pieces used here, loaded ahead)
local PACK_USED = { "Slashes/A - CUTS 01", "Slashes/C - SLASH STRIKE", "Slashes/D - MULTIPLE SLASHES", "Slashes/E - ARC SLASHES 01",
	"Slashes/F - ARC SLASHES 02", "Hits/E -  FAST TRAVEL", "Other/Perfect Block", "Slashes/wind1", -- (wind1: the whole Distant Cut)
	"Explosions/Explosion (*)", "Explosions/Hit" } -- (the ult's finish, in RoninStorm)

local player = Players.LocalPlayer

local RoninController = {}

type Deps = { shake: (number, number) -> (), fovPunch: (number, number) -> (), getAim: (BasePart) -> Vector3 }
local deps: Deps = nil :: any

-- ── Tuning (mirrored in RoninServer) ─────────────────────────────────────────
local LEAD = 0.1          -- the blend from whatever was playing into a move's first frame
local RECOVER = 0.25      -- the blend back out at the end
local COMBO_RESET = 1.2
local M1_FREE = { 0.36, 0.36, 0.6 }
-- The katana stays in his hand while he fights: after an M1, or a skill that
-- ends with the blade out (Rising Cut, Falling Heaven), it's sheathed (the
-- SHEATHE clip below) once this long has passed without an attack. (The
-- Distant Cut and the ult end on their own sheathe: the click is the hit.)
local COMBAT_HOLD = 5

local BLUE = Color3.fromRGB(150, 225, 255)
local WHITE = Color3.new(1, 1, 1)
local DEEP = Color3.fromRGB(40, 90, 170)
local INK = Color3.fromRGB(8, 8, 14)
local INK_CORE = Color3.fromRGB(20, 40, 80)

-- ═════════════════════════════════════════════════════════════════════════════
-- The baked moves → CastPoses stages
-- ═════════════════════════════════════════════════════════════════════════════
local stagesCache: { [string]: { any } } = {}

-- The baked drop (up to 0.42 studs) barely reads against legs spread 20-25
-- degrees: the body sinks this much MORE of it, and the legs slide that much
-- further up into the torso (straight up in the world), so the feet stay
-- exactly where they were baked and the tops of the spread legs are hidden.
local EXTRA_DROP = 1.0

-- The sheathe: the end of the Distant Cut, from where the blade comes back
-- round to the scabbard in the left hand (still drawn), through the slide
-- home and the click, to standing easy. A move like the baked ones, so the
-- scabbard mount, the katana swap and the slide all follow it frame by frame.
local SHEATHE_FROM = 18
local SHEATHE_CLICK = 24 -- (the frame the blade's home)
local SHEATHE = (function()
	local src = RoninMoves.rangedCut
	local frames, slide = {}, {}
	for i = SHEATHE_FROM, #src.frames do
		table.insert(frames, src.frames[i])
		table.insert(slide, src.slide[i] or 0)
	end
	return {
		length = (#frames - 1) / RoninMoves.fps,
		frames = frames,
		slide = slide,
		drawn = string.sub(src.drawn, SHEATHE_FROM),
		events = { click = (SHEATHE_CLICK - SHEATHE_FROM) / RoninMoves.fps },
	}
end)()
-- Rising Cut is charged (hold the key): stage 2 at RISE_STAGE2 seconds,
-- stage 3 (full) at RISE_STAGE3, let go by itself RISE_STILL after full.
-- (mirrored in RoninServer RISE) He holds the coiled draw (baked frame
-- RISE_HOLD: low, hand on the hilt) while it charges; the release is the rest.
local RISE_STAGE2, RISE_STAGE3, RISE_STILL, RISE_HOLD = 0.55, 1.2, 0.8, 6
local function slice(src: any, from: number, to: number, events: { [string]: number }, length: number?): any
	local frames, slide = {}, {}
	for i = from, to do
		table.insert(frames, src.frames[i])
		table.insert(slide, src.slide[i] or 0)
	end
	return {
		length = length or (#frames - 1) / RoninMoves.fps,
		frames = frames,
		slide = slide,
		drawn = string.sub(src.drawn, from, to),
		events = events,
	}
end
local RISING = RoninMoves.risingCut
-- (the coil: held as long as it charges; its last frame stays put)
local RISING_COIL = slice(RISING, 1, RISE_HOLD, {}, 99)
local RISING_RELEASE = slice(RISING, RISE_HOLD + 1, #RISING.frames,
	{ slash_up = RISING.events.slash_up - RISE_HOLD / RoninMoves.fps })

-- The baked moves, plus the sheathe ("sheathe": standing; "sheathe_walk":
-- the legs keep walking under it) and the Rising Cut's two halves.
local MOVES: { [string]: any } = setmetatable({ sheathe = SHEATHE, sheathe_walk = SHEATHE,
	risingCut_coil = RISING_COIL, risingCut_release = RISING_RELEASE }, { __index = RoninMoves }) :: any
local SHEATHE_ARMS = { RS = true, LS = true }

local function stagesOf(key: string): { any }
	local cached = stagesCache[key]
	if cached then return cached end
	local m = MOVES[key]
	local walking = key == "sheathe_walk"
	local stages = {}
	for i, f in ipairs(m.frames) do
		local drop = math.max(0, -f[5]) * EXTRA_DROP
		-- (straight up in the world, in the torso's own space: it's leaning and turned)
		local up = CFrame.fromEulerAnglesXYZ(math.rad(f[1]), math.rad(f[2]), math.rad(f[3])):VectorToObjectSpace(Vector3.new(0, drop, 0))
		local pose = {
			Root = { f[1], f[2], f[3], f[4], f[5] - drop, f[6] },
			N = { f[7], f[8], f[9] },
			RS = { f[10], f[11], f[12] },
			LS = { f[13], f[14], f[15] },
			-- (R6 legs are shins: their hips slide up into the torso as the body drops)
			RH = { f[16], f[17], f[18], f[19] + up.X, f[20] + up.Y, f[21] + up.Z },
			LH = { f[22], f[23], f[24], f[25] + up.X, f[26] + up.Y, f[27] + up.Z },
		}
		if walking then
			-- (on the move: the turn of the body only, no crouch, no lean, and the
			-- legs left to the walk)
			pose.Root = { 0, f[2] * 0.7, 0, 0, 0, 0 }
		end
		table.insert(stages, {
			dur = if i == 1 then LEAD else 1 / RoninMoves.fps,
			pose = pose,
			style = if i == 1 then Enum.EasingStyle.Quad else Enum.EasingStyle.Linear,
			release = if walking then 1 else nil,
			keep = if walking then SHEATHE_ARMS else nil,
		})
	end
	stagesCache[key] = stages
	return stages
end

-- ═════════════════════════════════════════════════════════════════════════════
-- The katana: in the hand or in the scabbard (each client's own view)
-- ═════════════════════════════════════════════════════════════════════════════
-- (`keep`: the blade was already in his hand when it started; `seen`: the
-- move's own frames have drawn it since)
type Playing = { key: string, t0: number, char: Model, keep: boolean, seen: boolean }
local playing: { [Model]: Playing } = {}
local drawnUntil: { [Model]: number } = {} -- (M1) drawn until then
local shownDrawn: { [Model]: boolean } = {}

local function katanaTool(char: Model): Tool?
	local t = char:FindFirstChild("Katana")
	return if t and t:IsA("Tool") then t else nil
end

local SCABBARD_ONLY = { Saya = true, Koiguchi = true, Kojiri = true }

local function setDrawn(char: Model, drawn: boolean)
	if shownDrawn[char] == drawn then return end
	local tool = katanaTool(char)
	local scab = char:FindFirstChild("RoninScabbard")
	if not tool or not scab then return end -- (not built yet: try again next frame)
	shownDrawn[char] = drawn
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then d.LocalTransparencyModifier = if drawn then 0 else 1 end
	end
	for _, d in ipairs(scab:GetDescendants()) do
		if d:IsA("BasePart") and not SCABBARD_ONLY[d.Name] then
			d.LocalTransparencyModifier = if drawn then 1 else 0
		end
	end
end

local function trailOn(char: Model, seconds: number)
	local tool = katanaTool(char)
	local handle = tool and tool:FindFirstChild("Handle")
	local trail = handle and handle:FindFirstChild("KatanaTrail") :: Trail?
	if not trail then return end
	trail.Enabled = true
	task.delay(seconds, function() if trail.Parent then trail.Enabled = false end end)
end

local function rootOf(char: Model?): BasePart?
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function charOf(p: any): Model?
	return if typeof(p) == "Instance" and p:IsA("Player") then p.Character else nil
end

local function flatDir(v: Vector3, fallback: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 0.05 then f = Vector3.new(fallback.X, 0, fallback.Z) end
	return if f.Magnitude > 0.05 then f.Unit else Vector3.new(0, 0, -1)
end

local function groundAt(p: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ex = {}
	for _, pl in ipairs(Players:GetPlayers()) do if pl.Character then table.insert(ex, pl.Character) end end
	params.FilterDescendantsInstances = ex
	local hit = Workspace:Raycast(p + Vector3.new(0, 6, 0), Vector3.new(0, -40, 0), params)
	return if hit then hit.Position else p - Vector3.new(0, 3, 0)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Cuts (all budgeted)
-- ═════════════════════════════════════════════════════════════════════════════
-- White shards: thin flecks of light flung out along their flight (glass-like).
local function shards(pos: Vector3, count: number, speed: number)
	if not FxBudget.Allow("roninShard", 14) then return end
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = pos
	anchor.Parent = Workspace
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(WHITE, BLUE)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Orientation = Enum.ParticleOrientation.VelocityParallel
	e.Squash = NumberSequence.new(-2.2) -- (long, thin)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.16), NumberSequenceKeypoint.new(1, 0) })
	e.Transparency = NumberSequence.new(0, 0.6)
	e.Lifetime = NumberRange.new(0.25, 0.55)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 5
	e.Rate = 0
	e.Parent = anchor
	e:Emit(count)
	game:GetService("Debris"):AddItem(anchor, 0.8)
end

-- Black slashes: one whole crescent image lying flat in the slash's plane,
-- tinted black. The sheet (rbxassetid://11189077263) is 2x2 frames of one
-- slash wearing away (256 px each), played through over its life. One piece,
-- so no seams: beam-built arcs split where their pieces meet, and unlit black
-- can't hide the split the way glow does.
-- The crescent bulges toward the frame's bottom; turned 90 degrees on its
-- Top face it bulges toward -Z, like SwordFX.Arc. Mirrored (sweep -1) it's
-- flipped over and turned the other way, so it still bulges to -Z (both
-- checked against a forward marker in Studio).
-- `glow` makes it emit light (SurfaceGui.Brightness, so it blooms): the same
-- image then draws the light slashes too, with no seams either.
local INK_SHEET = "rbxassetid://11189077263"
local INK_FRAMES = { Vector2.new(0, 0), Vector2.new(256, 0), Vector2.new(0, 256), Vector2.new(256, 256) }
local INK_TURN = CFrame.Angles(0, math.pi / 2, 0)
local INK_FLIP = CFrame.Angles(0, -math.pi / 2, 0) * CFrame.Angles(math.pi, 0, 0)
type InkOpts = {
	cf: CFrame, radius: number, sweep: number?, life: number?, grow: number?,
	move: Vector3?, color: Color3?, opacity: number?, key: string?, perSecond: number?,
	glow: number?, -- light: SurfaceGui brightness (nil = flat, for ink)
	hold: number?, -- 0..1 of its life it stays whole before wearing away (default 0.45)
}
local function inkSlash(o: InkOpts)
	if not FxBudget.Allow(o.key or "roninInkSlash", o.perSecond or 40) then return end
	local life = o.life or 0.4
	local grow = o.grow or 0.08
	local opacity = o.opacity or 1
	local base = o.radius * 2.2 -- (the crescent's circle fills about 90% of its frame)
	local turn = if (o.sweep or 1) < 0 then INK_FLIP else INK_TURN
	local p = Instance.new("Part")
	p.Name = "RoninInk"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Transparency = 1
	p.Size = Vector3.new(base, 0.05, base)
	p.CFrame = o.cf * turn
	local images: { ImageLabel } = {}
	for _, face in ipairs({ Enum.NormalId.Top, Enum.NormalId.Bottom }) do
		local sg = Instance.new("SurfaceGui")
		sg.Face = face
		sg.LightInfluence = 0
		if o.glow then sg.Brightness = o.glow end
		sg.CanvasSize = Vector2.new(256, 256)
		sg.Parent = p
		local im = Instance.new("ImageLabel")
		im.BackgroundTransparency = 1
		im.Size = UDim2.fromScale(1, 1)
		im.Image = INK_SHEET
		im.ImageColor3 = o.color or INK
		im.ImageRectSize = Vector2.new(256, 256)
		im.ImageRectOffset = INK_FRAMES[1]
		im.ImageTransparency = 1
		im.Parent = sg
		table.insert(images, im)
	end
	p.Parent = Workspace
	local t0 = os.clock()
	local lastFrame = 1
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= life or not p.Parent then
			conn:Disconnect()
			p:Destroy()
			return
		end
		local u = t / life
		-- (whole for the first part, then wearing away frame by frame)
		local h = o.hold or 0.45
		local w = (u - h) / (1 - h)
		local frame = if u < h then 1 elseif w < 0.36 then 2 elseif w < 0.67 then 3 else 4
		-- (snaps in, holds, thins out at the end)
		local a = opacity * (if u < 0.06 then u / 0.06 elseif u > 0.75 then (1 - u) / 0.25 else 1)
		for _, im in ipairs(images) do
			im.ImageTransparency = 1 - a
			if frame ~= lastFrame then im.ImageRectOffset = INK_FRAMES[frame] end
		end
		lastFrame = frame
		local s = base * (1 + grow * u)
		local cf = o.cf
		if o.move then cf += o.move * (1 - (1 - u) ^ 2) end
		p.Size = Vector3.new(s, 0.05, s)
		p.CFrame = cf * turn
	end)
end

-- A layered cut: the bright edge (glow + white core), the blade's filled path
-- behind it, a thin afterimage edge just outside that trails in a beat later,
-- sparks and shards off the tip where the stroke ends, and last a black ink
-- stroke that settles over the edge as the light fades and lingers after it.
-- Every cut is an uneven crescent: a long thin tail, widest past the middle,
-- a sharp head, flatter than a circle and set off-centre, a little different
-- each time. `move` rolls the whole cut forward as it fades.
-- `solid`: the bright edge is the whole-crescent image too (glowing), for the
-- big ability cuts, where a wide beam edge splits into visible sections.
-- An M1 (no `life`) clears quickly; ability cuts linger.
local function arc(cf: CFrame, radius: number, span: number, sweep: number, width: number, life: number?, move: Vector3?, solid: boolean?)
	if not FxBudget.Allow("roninArc", 40) then return end
	local quick = life == nil
	local l = life or 0.22
	local peak = 0.6 + math.random() * 0.15
	local squash = 0.72 + math.random() * 0.16
	local offset = 0.04 + math.random() * 0.1
	if solid then
		-- light: cyan, a white-hot copy just inside it
		inkSlash({ cf = cf, radius = radius, sweep = sweep, color = BLUE, glow = 3, life = l * 1.2, grow = 0.05, hold = 0.55,
			move = move, key = "roninSolid", perSecond = 20 })
		inkSlash({ cf = cf * CFrame.new(0, 0.05, 0), radius = radius * 0.96, sweep = sweep, color = WHITE, glow = 5, opacity = 0.85,
			life = l, grow = 0.05, hold = 0.5, move = move, key = "roninSolidCore", perSecond = 20 })
	else
		SwordFX.Arc({ cf = cf, radius = radius, arc = span, sweep = sweep, width = width, color = BLUE,
			life = l, draw = 0.05, core = WHITE, peak = peak, squash = squash, offset = offset, move = move })
	end
	-- the blade's path: the same whole crescent, deep blue and see-through, a
	-- touch inside the edge (SwordFX.Sweep's flat pieces showed as sections)
	inkSlash({ cf = cf, radius = radius * 0.92, sweep = sweep, color = DEEP, opacity = 0.4, life = if quick then l else l * 1.3,
		grow = 0.04, hold = if quick then 0.3 else 0.45, move = move, key = "roninSweep", perSecond = 20 })
	task.delay(0.03, function()
		if not FxBudget.Allow("roninEcho", 20) then return end
		-- (the afterimage: shorter, pushed further round, peaking later)
		SwordFX.Arc({ cf = cf, radius = radius * 1.1, arc = span * 0.7, sweep = sweep, width = width * 0.3,
			color = WHITE, life = l * 1.5, draw = 0.06, grow = 0.2, core = BLUE,
			peak = math.min(peak + 0.12, 0.9), squash = squash * 0.95, offset = offset + 0.12, move = move })
	end)
	if FxBudget.Allow("roninSpark", 10) then
		local s = if sweep >= 0 then 1 else -1
		local a = s * math.rad(span) * (0.5 + offset)
		local tip = cf:PointToWorldSpace(Vector3.new(-math.sin(a) * radius, 0, -math.cos(a) * radius * squash))
		SwordFX.Stars(tip, 8, 22, BLUE)
		shards(tip, 10, 26)
	end
	task.delay(0.07, function()
		inkSlash({ cf = cf, radius = radius * 1.03, sweep = sweep, life = if quick then l * 1.25 else l * 2.2, grow = 0.06,
			hold = if quick then 0.3 else 0.45, move = move, key = "roninInk", perSecond = 20 })
	end)
end

-- A hit burst: the air blown out flat across the floor, a second wave
-- rolling after it.
local function burst(pos: Vector3, r: number)
	AirShock.Wave(CFrame.new(pos), r, { key = "roninShock", perSecond = 8, life = 0.45 })
	task.delay(0.08, function()
		AirShock.Wave(CFrame.new(pos + Vector3.new(0, 0.2, 0)), r * 0.7, { dome = false, key = "roninShock2", perSecond = 8, life = 0.5 })
	end)
	-- the black layer: an ink ring that spreads after the light
	task.delay(0.1, function()
		-- (two black crescents back to back: a whole ring, spreading)
		local yaw = math.random() * math.pi * 2
		for k = 0, 1 do
			inkSlash({ cf = CFrame.new(pos) * CFrame.Angles(0, yaw + k * math.pi, 0), radius = r * 0.35, life = 0.5, grow = 1.6,
				key = "roninInk", perSecond = 20 })
		end
	end)
end

-- The ult's own burst, as it was (the shockwaves are for the other abilities):
-- rays, a ring that rolls out after them, sparks, an ink ring spreading.
local function ultBurst(pos: Vector3, r: number)
	if FxBudget.Allow("roninRays", 6) then SwordFX.Rays(pos, r, 10, BLUE, 0.35) end
	if FxBudget.Allow("roninRing", 8) then
		task.delay(0.05, function()
			SwordFX.Arc({ cf = CFrame.new(pos), radius = r * 0.3, arc = 359, width = 0.5, color = DEEP,
				life = 0.45, draw = 0.001, grow = 2.2, core = WHITE })
		end)
	end
	if FxBudget.Allow("roninSpark", 10) then SwordFX.Stars(pos, 14, 30, BLUE) end
	shards(pos, 22, 40)
	task.delay(0.1, function()
		if not FxBudget.Allow("roninInk", 20) then return end
		SwordFX.Arc({ cf = CFrame.new(pos), radius = r * 0.35, arc = 359, width = 0.9, color = INK, core = INK_CORE,
			life = 0.5, draw = 0.001, grow = 1.6, dark = true })
	end)
end

-- Wind: the air the draw moves. Pale ribbons that wind up round `getCenter()`
-- and peel away, dust kicked out across the floor, and thin streaks blowing
-- along `dir` (nil: no streaks). `strength` ~1 for a cut, 2+ for a big beat.
-- One budget key; counts shrink as the frame rate drops.
local WIND_TEX_DUST = "rbxasset://textures/particles/smoke_main.dds"
local WIND_TEX_STREAK = "rbxasset://textures/particles/sparkles_main.dds"
local function wind(getCenter: () -> Vector3?, dir: Vector3?, strength: number, dur: number?)
	if not FxBudget.Allow("roninWind", 8) then return end
	local center0 = getCenter()
	if not center0 then return end
	local k = 1 - 0.5 * FxBudget.Pressure()
	local life = dur or 0.45
	local holder = Instance.new("Part")
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.CFrame = CFrame.new(center0)
	holder.Parent = Workspace

	-- ribbons: each a trail between two attachments, swept round and up
	type Ribbon = { a0: Attachment, a1: Attachment, phase: number, spin: number }
	local ribbons: { Ribbon } = {}
	for i = 1, math.max(1, math.floor(3 * k + 0.5)) do
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Parent, a1.Parent = holder, holder
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.FaceCamera = true
		tr.LightEmission = 0.6
		tr.LightInfluence = 0
		tr.Lifetime = 0.22
		tr.Color = ColorSequence.new(WHITE, BLUE)
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) })
		tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) })
		tr.Parent = holder
		table.insert(ribbons, { a0 = a0, a1 = a1, phase = i * 2.1 + math.random() * 0.6,
			spin = (if i % 2 == 0 then -1 else 1) * (11 + math.random() * 4) })
	end
	local width = 0.18 + 0.1 * strength
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local c = getCenter()
		if t > life or not c or not holder.Parent then
			conn:Disconnect()
			return
		end
		holder.CFrame = CFrame.new(c)
		local u = t / life
		for _, r in ipairs(ribbons) do
			local a = r.phase + r.spin * t
			local rad = (1.6 + 2.2 * u) * (0.8 + 0.25 * strength)
			local p = Vector3.new(math.cos(a) * rad, -2.4 + 5 * u, math.sin(a) * rad)
			r.a0.Position = p
			r.a1.Position = p + Vector3.new(0, width * (1 - u * 0.6), 0)
		end
	end)

	-- dust thrown out across the floor in a ring
	local floor = Instance.new("Attachment")
	floor.Position = Vector3.new(0, -2.8, 0)
	floor.Parent = holder
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = WIND_TEX_DUST
	dust.Color = ColorSequence.new(Color3.fromRGB(225, 235, 245), Color3.fromRGB(150, 175, 205))
	dust.LightInfluence = 0.4
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 2.6 + strength) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(0.35, 0.6)
	dust.Speed = NumberRange.new(9 * strength, 15 * strength)
	dust.Drag = 6
	dust.SpreadAngle = Vector2.new(12, 12)
	dust.Rotation = NumberRange.new(0, 360)
	dust.RotSpeed = NumberRange.new(-60, 60)
	dust.Rate = 0
	dust.Parent = floor
	local dirs = math.max(4, math.floor(8 * k))
	for i = 1, dirs do
		-- (each puff along the floor: the emitter's up turned out flat)
		floor.CFrame = CFrame.new(floor.Position) * CFrame.Angles(0, (i / dirs) * math.pi * 2, 0) * CFrame.Angles(-math.pi / 2, 0, 0)
		dust:Emit(2)
	end

	-- streaks blowing the way the cut goes
	if dir and dir.Magnitude > 0.01 then
		local chest = Instance.new("Attachment")
		chest.CFrame = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(-math.pi / 2, 0, 0)
		chest.Parent = holder
		local streak = Instance.new("ParticleEmitter")
		streak.Texture = WIND_TEX_STREAK
		streak.Color = ColorSequence.new(WHITE, BLUE)
		streak.LightEmission = 0.8
		streak.LightInfluence = 0
		streak.Orientation = Enum.ParticleOrientation.VelocityParallel
		streak.Squash = NumberSequence.new(-2.6)
		streak.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0.05) })
		streak.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		streak.Lifetime = NumberRange.new(0.18, 0.32)
		streak.Speed = NumberRange.new(30 * strength, 50 * strength)
		streak.SpreadAngle = Vector2.new(28, 28)
		streak.Rate = 0
		streak.Parent = chest
		streak:Emit(math.floor(14 * strength * k))
	end
	game:GetService("Debris"):AddItem(holder, life + 0.8)
end

-- A sphere of cuts: slashes at random angles round `pos`.
local function cutSphere(pos: Vector3, radius: number, count: number, spread: number)
	for i = 1, count do
		task.delay((i - 1) * spread / count, function()
			if not FxBudget.Allow("roninSphere", 60) then return end
			local cf = CFrame.new(pos + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * radius * 0.6)
				* CFrame.Angles(math.random() * math.pi * 2, math.random() * math.pi * 2, math.random() * math.pi * 2)
			SwordFX.Arc({ cf = cf, radius = radius * (0.5 + math.random() * 0.4), arc = 120 + math.random() * 80,
				sweep = if math.random() < 0.5 then 1 else -1, width = 0.6, color = BLUE, life = 0.25, draw = 0.04, core = WHITE })
		end)
	end
end

local function flash(seconds: number, strength: number)
	local gui = player:FindFirstChildOfClass("PlayerGui")
	if not gui then return end
	local sg = Instance.new("ScreenGui")
	sg.Name = "RoninFlash"
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 50
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = WHITE
	f.BackgroundTransparency = 1 - strength
	f.BorderSizePixel = 0
	f.Parent = sg
	sg.Parent = gui
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - t0) / seconds
		if a >= 1 then
			conn:Disconnect()
			sg:Destroy()
			return
		end
		f.BackgroundTransparency = 1 - strength * (1 - a) ^ 2
	end)
end

-- The ult's storm on each Ronin (RoninStorm), from the freeze to the click.
local storms: { [Model]: any } = {}

local function near(pos: Vector3, dist: number): boolean
	local r = rootOf(player.Character)
	return r ~= nil and (r.Position - pos).Magnitude <= dist
end

-- The beats of each move, drawn where they land.
-- (`stage`: the Rising Cut's charge, 1-3)
type Ctx = { char: Model, root: BasePart, dir: Vector3, pos: Vector3?, radius: number?, mine: boolean, stage: number? }

local function chestCF(c: Ctx, up: number): CFrame
	local p = c.root.Position + Vector3.new(0, up, 0)
	return CFrame.lookAt(p, p + c.dir)
end

-- (the wind follows him)
local function at(c: Ctx): () -> Vector3?
	local root = c.root
	return function() return if root.Parent then root.Position else nil end
end

-- Distant Cut: how long the flurry of cuts on the cursor keeps going, and its
-- bursts (RoninServer hits on the same beats).
local DISTANT_FLURRY, DISTANT_BURSTS = 0.9, 5
-- Rising Cut: the crescent's thickness and how long it takes to roll out.
local RISING_WIDTH, RISING_LIFE = 5.2, 0.5

-- (the sheathe's click: the blade home)
local function sheatheClick(c: Ctx)
	ClassFX.Sound("swordHit", c.root, 0.35, 2.4)
	-- (a glint at the scabbard's mouth as the blade goes home)
	local torso = c.char:FindFirstChild("Torso") :: BasePart?
	if torso then
		PackFX.Burst("Other/Perfect Block", torso.CFrame * RoninLook.HIP, { scale = 0.6, color = BLUE, key = "roninSheathe", perSecond = 4 })
	end
end

-- A pack effect at `cf` in the Ronin's blue.
local function pack(path: string, cf: CFrame, scale: number, count: number?)
	PackFX.Burst(path, cf, { scale = scale, color = BLUE, count = count, key = "ronin:" .. path, perSecond = 12 })
end

-- The Distant Cut is made of the pack's wind ring alone (Slashes/wind1: a
-- swirl of wind cuts lying in its plane), in black and cold blue: each ring
-- is two thin black slashes curving with it, deep royal blue, electric cyan,
-- and a small white-hot core, each layer turned its own way so they never sit
-- exactly on each other.
local WIND_RING = "Slashes/wind1"
local V_INK = Color3.fromRGB(8, 12, 32)
local V_ROYAL = Color3.fromRGB(38, 82, 210)
local V_CYAN = Color3.fromRGB(110, 205, 255)
local V_WHITE = Color3.fromRGB(235, 248, 255)
local function windRing(cf: CFrame, scale: number)
	local spin = function() return CFrame.Angles(0, math.random() * math.pi * 2, 0) end
	-- (black strokes woven through the blue: as many as the blue, solid, unlit)
	-- The black: thin dark slashes curving round in the ring's own plane (sword
	-- arcs, not the wind texture: its black background would show as squares).
	for k = 1, 2 do
		inkSlash({ cf = cf * spin(), radius = scale * (if k == 1 then 3.6 else 2.4) * (0.85 + math.random() * 0.3),
			sweep = if math.random() < 0.5 then 1 else -1, color = V_INK, life = 0.36, key = "roninWindInk", perSecond = 30 })
	end
	PackFX.Burst(WIND_RING, cf * spin(), { scale = scale * 1.05, color = V_ROYAL, solid = true, light = 1, count = 0.7, brightness = 2,
		key = "roninWindRoyal", perSecond = 30 })
	PackFX.Burst(WIND_RING, cf * spin(), { scale = scale * 0.85, color = V_CYAN, count = 0.6, zOffset = 0.5, brightness = 3.5,
		key = "roninWindCyan", perSecond = 30 })
	PackFX.Burst(WIND_RING, cf * spin(), { scale = scale * 0.55, color = V_WHITE, count = 0.5, zOffset = 1, brightness = 6,
		key = "roninWindCore", perSecond = 30 })
end

-- A ring somewhere in the storm round `center` (radius `r`): its own size,
-- spot and tilt: some lying near flat, most at any angle, so together they
-- make a ball of wind cuts.
local function stormRing(center: Vector3, r: number, big: number)
	local off = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * r * 0.6
	local tilt = if math.random() < 0.35
		then CFrame.Angles(math.rad((math.random() - 0.5) * 30), 0, math.rad((math.random() - 0.5) * 30))
		else CFrame.Angles(math.random() * math.pi, math.random() * math.pi * 2, math.random() * math.pi)
	windRing(CFrame.new(center + off) * tilt, r / 9 * big * (0.75 + math.random() * 0.7))
end

local function rand(a: number, b: number): number
	return a + math.random() * (b - a)
end

-- The Distant Cut's burst: a ball of whole crescents (the slash image) round
-- `center`, each lying on its own great circle, bulging outward, and
-- spreading out as it wears away, the way the wind rings did. Black and
-- royal blue mostly, cyan, a few white-hot.
local SPHERE_LOOKS = {
	{ color = V_INK, glow = nil, opacity = 1, weight = 0.35 },
	{ color = V_ROYAL, glow = 2.5, opacity = 0.9, weight = 0.3 },
	{ color = V_CYAN, glow = 3.5, opacity = 0.85, weight = 0.23 },
	{ color = V_WHITE, glow = 5, opacity = 0.8, weight = 0.12 },
}
local function sphereLook()
	local roll = math.random()
	for _, l in ipairs(SPHERE_LOOKS) do
		roll -= l.weight
		if roll <= 0 then return l end
	end
	return SPHERE_LOOKS[1]
end
local function slashSphere(center: Vector3, r: number, count: number, life: number?)
	local n = math.max(3, math.floor(count * (1 - 0.5 * FxBudget.Pressure()) + 0.5))
	for i = 1, n do
		task.delay((i - 1) * 0.012, function()
			local d = Vector3.new(rand(-1, 1), rand(-0.7, 1), rand(-1, 1))
			if d.Magnitude < 0.05 then d = Vector3.yAxis end
			-- (-Z out along `d`; spun round it, so each lies on its own circle)
			local cf = CFrame.lookAt(center, center + d.Unit) * CFrame.Angles(0, 0, rand(0, math.pi * 2))
			local look = sphereLook()
			inkSlash({ cf = cf, radius = r * rand(0.45, 0.8), sweep = if math.random() < 0.5 then 1 else -1,
				color = look.color, glow = look.glow, opacity = look.opacity,
				life = (life or 0.45) * rand(0.85, 1.15), grow = rand(0.7, 1.1), hold = 0.4,
				key = "roninSphere", perSecond = 70 })
		end)
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Rising Cut: the charge (held) and the release, three stages
-- ═════════════════════════════════════════════════════════════════════════════
local function riseStage(held: number): number
	return if held >= RISE_STAGE3 then 3 elseif held >= RISE_STAGE2 then 2 else 1
end
-- (the reach per stage: mirrored in RoninServer RISE_SCALE)
local RISE_RANGE = { 1, 1.35, 1.8 }
-- The release's crescent per stage: thicker, bigger, longer-lived.
local RISE_FX = {
	{ width = RISING_WIDTH, radius = 8.5, life = RISING_LIFE },
	{ width = RISING_WIDTH * 1.45, radius = 10, life = RISING_LIFE + 0.08 },
	{ width = RISING_WIDTH * 2, radius = 12.5, life = RISING_LIFE + 0.16 },
}

-- Three diamonds over your head, lit one by one as the charge climbs.
local function stagePips(char: Model): ((number) -> (), () -> ())
	local head = char:FindFirstChild("Head") :: BasePart?
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not head or not pg then return function() end, function() end end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RoninRisingPips"
	gui.Adornee = head
	gui.Size = UDim2.fromOffset(78, 22)
	gui.StudsOffset = Vector3.new(0, 2.4, 0)
	gui.AlwaysOnTop = true
	gui.ResetOnSpawn = false
	gui.Parent = pg
	local pips: { Frame } = {}
	for i = 1, 3 do
		local f = Instance.new("Frame")
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Position = UDim2.new(0.5, (i - 2) * 24, 0.5, 0)
		f.Size = UDim2.fromOffset(11, 11)
		f.Rotation = 45
		f.BorderSizePixel = 0
		f.BackgroundColor3 = V_INK
		f.BackgroundTransparency = 0.2
		local s = Instance.new("UIStroke")
		s.Color = V_ROYAL
		s.Thickness = 1.5
		s.Parent = f
		f.Parent = gui
		pips[i] = f
	end
	local function set(stage: number)
		for i, f in ipairs(pips) do
			local lit = i <= stage
			f.BackgroundColor3 = if not lit then V_INK elseif stage >= 3 then V_WHITE elseif i == 2 then V_CYAN else V_ROYAL
			f.Size = if lit then UDim2.fromOffset(13, 13) else UDim2.fromOffset(11, 11)
			local s = f:FindFirstChildOfClass("UIStroke")
			if s then s.Color = if stage >= 3 then V_CYAN else V_ROYAL end
		end
	end
	return set, function() gui:Destroy() end
end

-- The charge on someone's body: light drawn in to him from all round, black
-- and blue slashes whirling round him faster each stage, the air pulsing
-- out round him from stage 2, wind rings rising off the floor at full; each
-- stage lands with a shockwave. Yours also drains the colour from the world as it
-- builds and shows the stage pips. stop(stage): it all goes (the release
-- carries on from there).
type ChargeFx = { stop: (stage: number) -> () }
local function risingChargeFx(char: Model, root: BasePart, mine: boolean): ChargeFx
	local t0 = os.clock()
	local stage = 0
	local alive = true
	local k = 1 - 0.5 * FxBudget.Pressure()
	local holder = Instance.new("Part")
	holder.Name = "RoninChargeFX"
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch = true, false, false, false
	holder.Transparency = 1
	holder.Shape = Enum.PartType.Ball
	holder.Size = Vector3.one * 13
	holder.CFrame = CFrame.new(root.Position)
	holder.Parent = Workspace
	-- the gathering: streaks of light pulled in to him from everywhere round
	local gather = Instance.new("ParticleEmitter")
	gather.Texture = WIND_TEX_STREAK
	gather.Color = ColorSequence.new(V_CYAN, V_WHITE)
	gather.LightEmission, gather.LightInfluence = 1, 0
	gather.Orientation = Enum.ParticleOrientation.VelocityParallel
	gather.Squash = NumberSequence.new(-2.2)
	gather.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.6, 0.28), NumberSequenceKeypoint.new(1, 0) })
	gather.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.1), NumberSequenceKeypoint.new(1, 0.4) })
	gather.Lifetime = NumberRange.new(0.38, 0.45)
	gather.Speed = NumberRange.new(14, 16)
	gather.Shape = Enum.ParticleEmitterShape.Sphere
	gather.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	gather.ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward
	gather.Rate = 0
	gather.Parent = holder
	-- black motes lifting off the floor round his feet (stage 2 on)
	local feet = Instance.new("Attachment")
	feet.Position = Vector3.new(0, -2.8, 0)
	feet.Parent = holder
	local motes = Instance.new("ParticleEmitter")
	motes.Texture = WIND_TEX_DUST
	motes.Color = ColorSequence.new(V_INK)
	motes.LightEmission, motes.LightInfluence = 0, 0
	motes.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1.6) })
	motes.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.45), NumberSequenceKeypoint.new(1, 1) })
	motes.Lifetime = NumberRange.new(0.6, 1)
	motes.Speed = NumberRange.new(2, 5)
	motes.SpreadAngle = Vector2.new(35, 35)
	motes.Rotation = NumberRange.new(0, 360)
	motes.Rate = 0
	motes.Parent = feet
	-- yours: the world's colour drains and cools as it builds
	local cc: ColorCorrectionEffect? = nil
	if mine then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "RoninRisingGrade"
		c.Parent = game:GetService("Lighting")
		cc = c
	end
	local setPips, dropPips = function(_: number) end, function() end
	if mine then setPips, dropPips = stagePips(char) end

	local function stageUp(s: number)
		stage = s
		setPips(s)
		local p = root.Position
		local g = groundAt(p)
		if s == 1 then
			windRing(CFrame.new(g + Vector3.new(0, 0.5, 0)), 0.6)
			ClassFX.Sound("charge", root, 0.45, 1.1)
		elseif s == 2 then
			-- the air punched out flat across the floor round him
			AirShock.Wave(CFrame.new(g + Vector3.new(0, 0.3, 0)), 9, { dome = false, key = "roninRiseShock", perSecond = 6 })
			windRing(CFrame.new(g + Vector3.new(0, 0.5, 0)), 1)
			ClassFX.Sound("swordHit", root, 0.6, 1.7)
			ClassFX.Sound("wind", root, 0.35, 1.6, 0.4)
			if mine then
				deps.shake(0.25, 0.15)
				deps.fovPunch(3, 0.15)
			end
		else
			-- full: a shockwave of air bursting off him and rolling out across the
			-- floor, a black ring tearing out after it, the floor cracking
			AirShock.Wave(CFrame.new(p), 8, { key = "roninRiseFull", perSecond = 4, life = 0.5 })
			AirShock.Wave(CFrame.new(g + Vector3.new(0, 0.3, 0)), 15, { dome = false, key = "roninRiseFullRing", perSecond = 4, life = 0.55 })
			task.delay(0.06, function()
				for k = 0, 1 do
					inkSlash({ cf = CFrame.new(g + Vector3.new(0, 0.32, 0)) * CFrame.Angles(0, k * math.pi, 0), radius = 2.2,
						color = V_INK, life = 0.6, grow = 5, key = "roninRiseInkRing", perSecond = 8 })
				end
			end)
			if FxBudget.Allow("roninRiseCrack", 2) then
				for i = 1, 8 do
					local a = (i / 8) * math.pi * 2 + math.random() * 0.5
					local d = Vector3.new(math.cos(a), 0, math.sin(a))
					SwordFX.Streak(g + d * 1 + Vector3.new(0, 0.2, 0), g + d * rand(5, 9) + Vector3.new(0, 0.2, 0), 0.45, V_CYAN, 0.6, 1, V_WHITE)
				end
			end
			ClassFX.Sound("boom", root, 0.4, 1.4)
			ClassFX.Sound("wind", root, 0.5, 1.3, 0.6)
			if mine then
				deps.shake(0.6, 0.25)
				deps.fovPunch(6, 0.25)
				flash(0.18, 0.3)
			end
		end
	end

	local lastArc, lastZap, lastRing = 0, 0, 0
	local conn = RunService.Heartbeat:Connect(function()
		if not alive then return end
		if not root.Parent or not char.Parent then return end
		local now = os.clock()
		local held = now - t0
		local s = riseStage(held)
		if s ~= stage then stageUp(s) end
		holder.CFrame = CFrame.new(root.Position)
		gather.Rate = ({ 30, 70, 140 })[stage] * k
		motes.Rate = ({ 0, 14, 36 })[stage] * k
		-- slashes whirling round him, black and blue, faster and wider each stage
		if now - lastArc > ({ 0.4, 0.2, 0.09 })[stage] then
			lastArc = now
			if FxBudget.Allow("roninRiseArc", 20) then
				local dark = math.random() < 0.45
				local acf = CFrame.new(root.Position + Vector3.new(0, rand(-0.6, 2), 0))
					* CFrame.Angles(rand(-0.9, 0.9), rand(0, math.pi * 2), rand(-0.9, 0.9))
				local ar = 2.4 + stage * 0.7 + rand(0, 0.8)
				local asweep = if math.random() < 0.5 then 1 else -1
				if dark then
					inkSlash({ cf = acf, radius = ar, sweep = asweep, color = V_INK, life = 0.3, key = "roninRiseArcInk", perSecond = 12 })
				else
					inkSlash({ cf = acf, radius = ar, sweep = asweep, color = if stage >= 3 then V_CYAN else V_ROYAL,
						glow = 2 + stage, life = 0.3, key = "roninRiseArcLight", perSecond = 14 })
				end
			end
		end
		-- from stage 2 the air round him pulses outward, faster at full
		if stage >= 2 and now - lastZap > (if stage == 2 then 0.5 else 0.3) then
			lastZap = now
			AirShock.Wave(CFrame.new(groundAt(root.Position) + Vector3.new(0, rand(0.3, 1.5), 0)), 3 + stage,
				{ dome = false, key = "roninRisePulse", perSecond = 5, life = 0.35 })
		end
		-- at full: wind rings rising off the floor round him
		if stage == 3 and now - lastRing > 0.35 then
			lastRing = now
			windRing(CFrame.new(groundAt(root.Position) + Vector3.new(0, rand(0.4, 2.2), 0)) * CFrame.Angles(rand(-0.2, 0.2), 0, rand(-0.2, 0.2)), 1.1)
		end
		if cc then
			local q = math.clamp(held / RISE_STAGE3, 0, 1)
			cc.Saturation = -0.5 * q
			cc.Contrast = 0.18 * q
			cc.Brightness = -0.06 * q
			cc.TintColor = Color3.new(1, 1, 1):Lerp(Color3.fromRGB(185, 212, 255), q)
		end
	end)

	local fx: ChargeFx = {} :: any
	function fx.stop(_s: number)
		if not alive then return end
		alive = false
		conn:Disconnect()
		gather.Rate, motes.Rate = 0, 0
		game:GetService("Debris"):AddItem(holder, 1.2)
		dropPips()
		local c = cc
		if c then
			-- (the colour comes back over the cut)
			game:GetService("TweenService"):Create(c, TweenInfo.new(0.45, Enum.EasingStyle.Quad),
				{ Saturation = 0, Contrast = 0, Brightness = 0, TintColor = Color3.new(1, 1, 1) }):Play()
			game:GetService("Debris"):AddItem(c, 0.5)
		end
	end
	return fx
end

-- The release's cut, at `stage`: the crescent thicker, bigger and further
-- each stage; from stage 2 a black crescent riding behind it, a second blade
-- crossing it and rings of air punched down the path; at full a cinematic
-- beat: the body holds for a split second, the screen flares white, straight
-- neon cuts hang across the path and the air bursts out at its end.
local function risingSlash(c: Ctx, stage: number)
	local S = RISE_FX[stage] or RISE_FX[1]
	trailOn(c.char, 0.25 + 0.1 * stage)
	local cf = chestCF(c, 0.1) * CFrame.Angles(0, 0, math.rad(-16))
	local reach = c.radius or 20
	local travel = c.dir * reach
	local from = c.root.Position
	if stage == 3 then
		CastPoses.hitStop(c.char, 0.12)
		if c.mine then
			flash(0.14, 0.85)
			deps.shake(1.3, 0.4)
			deps.fovPunch(10, 0.3)
		elseif near(from, 60) then
			deps.shake(0.4, 0.2)
		end
	end
	arc(cf, S.radius, 175, -1, S.width, S.life, travel, true)
	-- (a second, smaller crescent just behind, for depth)
	task.delay(0.04, function()
		inkSlash({ cf = cf * CFrame.new(0, 0.4, 1.2), radius = S.radius * 0.85, sweep = -1, color = V_ROYAL, glow = 2.5,
			opacity = 0.75, life = S.life * 0.95, grow = 0.05, hold = 0.5, move = travel * 0.9, key = "roninWide", perSecond = 6 })
	end)
	if stage >= 2 then
		-- a black crescent riding just behind the light, and a second blade crossing it
		task.delay(0.02, function()
			inkSlash({ cf = cf * CFrame.new(0, -0.2, 0.8), radius = S.radius * 1.06, sweep = -1, color = V_INK,
				life = S.life * 1.2, move = travel * 0.95, key = "roninRiseInk", perSecond = 6 })
		end)
		task.delay(0.05, function()
			arc(cf * CFrame.Angles(0, 0, math.rad(34)), S.radius * 0.9, 160, 1, S.width * 0.55, S.life, travel * 0.9, true)
		end)
	end
	pack("Slashes/F - ARC SLASHES 02", cf * CFrame.new(0, 0, -3), S.radius / 3.3)
	-- the wind it drags along: at his feet, then down the path behind the
	-- crescent, the pack's fast-travel streaks blowing along it (rings of air too, from stage 2)
	wind(at(c), c.dir, 1.2 + 0.4 * stage)
	for i = 1, 3 do
		task.delay(S.life * i / 4, function()
			local p = from + c.dir * (reach * i / 4 + 3)
			if i < 3 then wind(function() return p end, c.dir, 1 + 0.2 * stage, 0.4) end
			pack("Hits/E -  FAST TRAVEL", CFrame.lookAt(p, p + c.dir), 1.6 + 0.4 * stage)
			-- (from stage 2: upright rings of air punched down the path, like a sonic boom)
			if stage >= 2 then
				AirShock.Wave(CFrame.lookAt(p + Vector3.new(0, 1.5, 0), p + Vector3.new(0, 1.5, 0) + c.dir) * CFrame.Angles(math.pi / 2, 0, 0),
					2 + 1.2 * stage, { dome = false, key = "roninRiseBoom", perSecond = 8, life = 0.35 })
			end
		end)
	end
	local tip = from + c.dir * (4 + reach)
	task.delay(S.life * 0.6, function()
		if c.root.Parent then shards(tip + Vector3.new(0, 1, 0), 18, 34) end
	end)
	if stage == 3 then
		-- straight neon cuts slashed across the path, hanging a beat
		local side = c.dir:Cross(Vector3.yAxis)
		for i = 1, 7 do
			task.delay(0.03 * i, function()
				local mid = from + c.dir * rand(4, reach) + Vector3.new(0, rand(0.5, 4), 0)
				local a = rand(-1, 1)
				local d = (side * math.cos(a) + Vector3.new(0, math.sin(a), 0) + c.dir * rand(-0.4, 0.4)).Unit
				local len = rand(8, 16)
				SwordFX.Streak(mid - d * len / 2, mid + d * len / 2, 0.5, V_CYAN, 0.4, 1, V_WHITE)
			end)
		end
		-- the end of the path: the air the cut drove ahead of it bursts out
		task.delay(S.life * 0.85, function()
			local g = groundAt(tip)
			AirShock.Wave(CFrame.new(g + Vector3.new(0, 1.5, 0)), 11, { key = "roninRiseEnd", perSecond = 3, life = 0.5 })
			AirShock.Wave(CFrame.new(g + Vector3.new(0, 0.3, 0)), 16, { dome = false, key = "roninRiseEndRing", perSecond = 3, life = 0.6 })
			wind(function() return g + Vector3.new(0, 2.8, 0) end, nil, 2.4, 0.5)
			ClassFX.Sound("boom", g, 0.8, 1)
			ClassFX.Sound("wind", g, 0.5, 1.1, 0.6)
			if c.mine then deps.shake(0.8, 0.25) end
		end)
	end
	ClassFX.Sound("whoosh", c.root, 1, 0.95 - 0.08 * stage)
	ClassFX.Sound("wind", c.root, 0.35 + 0.1 * stage, 1.3, 0.6)
	if c.mine and stage < 3 then deps.fovPunch(4 + 2 * stage, 0.18) end
end

local BEATS: { [string]: { [string]: (Ctx) -> () } } = {
	sheathe = { click = sheatheClick },
	sheathe_walk = { click = sheatheClick },
	rangedCut = {
		slash_h = function(c)
			-- the draw: just the blade's trail and its sound (the wind is all at the target)
			trailOn(c.char, 0.2)
			ClassFX.Sound("whoosh", c.root, 0.8, 1.3)
		end,
		click_cuts = function(c)
			local pos = c.pos or (c.root.Position + c.dir * 20)
			local r = c.radius or 9
			local center = groundAt(pos) + Vector3.new(0, r * 0.35, 0)
			-- the flurry: with each hit a ball of slashes bursts round the spot and
			-- spreads out (the slash image is the main piece now); the wind rings
			-- stay behind them, fewer, as the air they move
			for i = 0, DISTANT_BURSTS - 1 do
				task.delay(i * DISTANT_FLURRY / (DISTANT_BURSTS - 1), function()
					local last = i == DISTANT_BURSTS - 1
					local jitter = Vector3.new(rand(-1, 1), rand(-0.5, 0.5), rand(-1, 1)) * r * 0.15
					if last then
						-- the last: a big ball, and two wind rings crossing in an X under it
						slashSphere(center, r * 1.4, 14, 0.6)
						local face = CFrame.lookAt(center, center + c.dir)
						windRing(face * CFrame.Angles(0, 0, math.rad(35)), r / 9 * 1.6)
						windRing(face * CFrame.Angles(math.rad(90), 0, math.rad(-35)), r / 9 * 1.6)
					else
						slashSphere(center + jitter, r * 0.9, 7, 0.42)
						if i % 2 == 0 then stormRing(center, r, 0.9) end
					end
					ClassFX.Sound("swordHit", pos, 0.7, 1.3 + i * 0.08)
				end)
			end
			ClassFX.Sound("swordHit", c.root, 0.4, 2.2) -- (the click of the blade home)
			ClassFX.Sound("wind", pos, 0.35, 1.5, DISTANT_FLURRY)
			if c.mine then deps.shake(0.35, 0.12) end
		end,
	},
	risingCut = { slash_up = function(c) risingSlash(c, 1) end },
	risingCut_release = { slash_up = function(c) risingSlash(c, c.stage or 1) end },
	airCut = {
		slash_h = function(c)
			trailOn(c.char, 0.18)
			arc(chestCF(c, 0.4) * CFrame.Angles(0, 0, math.rad(12)), 6.5, 170, 1, 1.5)
			pack("Slashes/E - ARC SLASHES 01", chestCF(c, 0.4) * CFrame.new(0, 0, -3), 1.6)
			wind(at(c), c.dir, 0.9, 0.35)
			ClassFX.Sound("whoosh", c.root, 0.8, 1.35)
		end,
		slash_h2 = function(c)
			trailOn(c.char, 0.18)
			arc(chestCF(c, 0.4) * CFrame.Angles(0, 0, math.rad(-12)), 6.5, 170, -1, 1.5)
			pack("Slashes/F - ARC SLASHES 02", chestCF(c, 0.4) * CFrame.new(0, 0, -3), 1.6)
			wind(at(c), c.dir, 0.9, 0.35)
			ClassFX.Sound("whoosh", c.root, 0.8, 1.45)
		end,
		slash_spin = function(c)
			trailOn(c.char, 0.25)
			arc(chestCF(c, 0.2), 7, 359, 1, 1.4, 0.3)
			pack("Slashes/A - CUTS 01", chestCF(c, 0.2), 2.2)
			wind(at(c), nil, 1.4, 0.5)
			ClassFX.Sound("whoosh", c.root, 0.9, 1.0)
		end,
		slash_down = function(c)
			trailOn(c.char, 0.35)
			arc(chestCF(c, 0) * CFrame.Angles(0, 0, math.rad(90)), 7, 190, 1, 2, 0.3)
			pack("Slashes/C - SLASH STRIKE", chestCF(c, 0) * CFrame.new(0, -1, -2), 2)
			wind(at(c), Vector3.new(0, -1, 0) + c.dir * 0.4, 1.2, 0.35)
			ClassFX.Sound("whoosh", c.root, 1, 0.8)
		end,
		impact = function(c)
			local g = groundAt(c.root.Position + c.dir * 3)
			local r = c.radius or 12
			-- (the slam blows the air out flat across the floor)
			wind(function() return g + Vector3.new(0, 2.8, 0) end, nil, 2.2, 0.5)
			ClassFX.Sound("wind", g, 0.45, 1.2, 0.6)
			burst(g + Vector3.new(0, 0.3, 0), r)
			-- ground cracks: straight cuts radiating from the landing
			if FxBudget.Allow("roninCrack", 4) then
				for i = 1, 6 do
					local a = (i / 6) * math.pi * 2 + math.random() * 0.4
					local d = Vector3.new(math.cos(a), 0, math.sin(a))
					SwordFX.Streak(g + d * 1.2 + Vector3.new(0, 0.2, 0), g + d * r * (0.6 + math.random() * 0.4) + Vector3.new(0, 0.2, 0),
						0.6, BLUE, 0.25, 1, WHITE)
				end
			end
			ClassFX.Sound("boom", g, 0.7, 1.1)
			ClassFX.Sound("swordHit", g, 0.8, 0.8)
			if c.mine then
				deps.shake(1.1, 0.25)
				deps.fovPunch(6, 0.2)
			elseif near(g, 50) then
				deps.shake(0.3, 0.15)
			end
		end,
	},
	finisher = {
		-- (the dimensional storm: RoninStorm. The space cracks in through the draw,
		-- the cuts fill it, and the click shatters everything)
		freeze = function(c)
			local r = c.radius or 30
			local center = c.pos or c.root.Position
			-- (everyone close sees the grade; only the caster's camera is taken)
			local close = c.mine or near(center, r + 25)
			if storms[c.char] then storms[c.char].Cancel() end
			storms[c.char] = RoninStorm.Begin(c.char, center, {
				-- (a teammate's ult takes your camera only if Settings > Gameplay says so)
				radius = r, grade = close,
				cinematic = c.mine or (close and player:GetAttribute("Setting_teammateCinematics") == true),
				build = 0.94, stormLength = 2.48,
			})
		end,
		aura = function(c)
			local root = c.root
			if FxBudget.Allow("roninAura", 2) then
				SwordFX.Spiral(function() return if root.Parent then root.Position else nil end, 3.2, 0.5, BLUE)
			end
			-- (the air gathering round him as he draws)
			wind(at(c), nil, 1.4, 0.8)
		end,
		slash_storm = function(c)
			local s = storms[c.char]
			if s then s.Unleash() end
			-- (the storm's gale: round him and blowing through the space)
			wind(at(c), c.dir, 2, 0.7)
			ClassFX.Sound("wind", c.root, 0.5, 1.2, 1.2)
			ClassFX.Sound("whoosh", c.root, 1, 1.6)
			if c.mine then deps.shake(0.4, 0.5) end
		end,
		click_finish = function(c)
			local center = c.pos or c.root.Position
			local r = c.radius or 30
			local s = storms[c.char]
			storms[c.char] = nil
			if s then s.Finish() end -- every hanging cut blows apart on the click
			ultBurst(groundAt(center) + Vector3.new(0, 0.5, 0), r * 0.5)
			-- (the click blows the air out across the floor)
			local g = groundAt(center)
			wind(function() return g + Vector3.new(0, 2.8, 0) end, nil, 3, 0.6)
			if FxBudget.Allow("roninRing", 6) then
				SwordFX.Arc({ cf = CFrame.new(groundAt(center) + Vector3.new(0, 0.5, 0)), radius = 3, arc = 359, width = 1.4,
					color = BLUE, life = 0.55, draw = 0.001, grow = (r - 3) / 3, core = WHITE })
			end
			ClassFX.Sound("swordHit", c.root, 0.7, 2.4) -- the click
			ClassFX.Sound("boom", center, 0.9, 0.9)
			if c.mine or near(center, r + 20) then flash(0.5, if c.mine then 0.9 else 0.5) end
			if c.mine then
				deps.shake(1.4, 0.35)
				deps.fovPunch(8, 0.25)
			end
		end,
	},
}

-- ═════════════════════════════════════════════════════════════════════════════
-- Playing a move
-- ═════════════════════════════════════════════════════════════════════════════
local function play(char: Model, key: string, ctx: Ctx)
	local m = MOVES[key]
	CastPoses.play(char, stagesOf(key), RECOVER, true, { carry = 0, plant = false })
	-- (already holding the blade: it stays out through the move's opening
	-- frames, which draw it from the scabbard, instead of vanishing into it)
	playing[char] = { key = key, t0 = os.clock(), char = char, keep = shownDrawn[char] == true, seen = false }
	drawnUntil[char] = nil
	for name, t in pairs(m.events) do
		local fn = BEATS[key] and BEATS[key][name]
		if fn then
			task.delay(LEAD + t, function()
				local p = playing[char]
				if not p or p.key ~= key or not ctx.root.Parent then return end
				local ok, err = pcall(fn, ctx)
				if not ok then warn("[RoninController]", key, name, err) end
			end)
		end
	end
end

-- The scabbard: at the hip, except through a baked move, when the left hand
-- holds it (blended in over the move's lead-in, back out over its recovery).
local mountA: { [Model]: number } = {}
local MOUNT_IN, MOUNT_OUT = 1 / LEAD, 1 / RECOVER
local lastDrive = os.clock()

local function driveMounts(dt: number)
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		if not char or not char:FindFirstChild("RoninScabbard") then continue end
		local a = mountA[char] or 0
		local goal = if playing[char] then 1 else 0
		if a == goal then continue end
		a = if goal > a then math.min(goal, a + dt * MOUNT_IN) else math.max(goal, a - dt * MOUNT_OUT)
		mountA[char] = a
		RoninLook.SetMount(char, a)
	end
	for char in pairs(mountA) do
		if not char.Parent then mountA[char] = nil end
	end
end

-- No attack for COMBAT_HOLD: the blade goes home (the SHEATHE clip), the legs
-- left to the walk if he's on the move. Not mid-air, not dead: then it just goes.
local function sheathe(char: Model)
	local root = rootOf(char)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not root or not hum or hum.Health <= 0 or hum.FloorMaterial == Enum.Material.Air
		or char:GetAttribute("IsSkillCasting") == true then
		setDrawn(char, false)
		return
	end
	local walking = hum.MoveDirection.Magnitude > 0.1
	play(char, if walking then "sheathe_walk" else "sheathe",
		{ char = char, root = root, dir = flatDir(root.CFrame.LookVector, root.CFrame.LookVector), mine = char == player.Character })
end

-- Each frame: which katana shows, how far the sheathed one is out, where the scabbard is.
local function driveStep()
	local now = os.clock()
	driveMounts(math.min(now - lastDrive, 0.1))
	lastDrive = now
	for char, p in pairs(playing) do
		if not char.Parent then
			playing[char] = nil
			continue
		end
		local m = MOVES[p.key]
		local t = now - p.t0 - LEAD
		if t > m.length + 0.05 then
			playing[char] = nil
			RoninLook.SetSlide(char, 0)
			-- ended with the blade out: it stays in his hand while he fights
			if string.sub(m.drawn, #m.drawn) == "1" then
				drawnUntil[char] = now + COMBAT_HOLD
				setDrawn(char, true)
			else
				setDrawn(char, false)
			end
			continue
		end
		local i = math.clamp(math.floor(math.max(t, 0) * RoninMoves.fps) + 1, 1, #m.frames)
		local frameDrawn = string.sub(m.drawn, i, i) == "1"
		if frameDrawn then p.seen = true end
		setDrawn(char, frameDrawn or (p.keep and not p.seen))
		RoninLook.SetSlide(char, m.slide[i] or 0)
	end
	for char, untilT in pairs(drawnUntil) do
		if not char.Parent then
			drawnUntil[char] = nil
		elseif not playing[char] then
			if now >= untilT then
				drawnUntil[char] = nil
				sheathe(char)
			else
				setDrawn(char, true)
			end
		end
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Holding the body through a move (your own character: it replicates)
-- ═════════════════════════════════════════════════════════════════════════════
type Mover = { set: (CFrame) -> (), stop: () -> (), alive: () -> boolean }

local function holdBody(char: Model, root: BasePart): Mover?
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return nil end
	local stand = SafeMove.StandHeight(root)
	local a = Instance.new("Attachment")
	a.Name = "RoninMove"
	a.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = a
	ap.RigidityEnabled = true
	ap.Position = root.Position
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = a
	ao.RigidityEnabled = true
	ao.CFrame = root.CFrame.Rotation
	ao.Parent = root
	hum.AutoRotate = false
	hum.PlatformStand = true
	local stopped = false
	return {
		set = function(cf: CFrame)
			if stopped then return end
			ap.Position = cf.Position
			ao.CFrame = cf.Rotation
		end,
		alive = function() return not stopped and root.Parent ~= nil and hum.Health > 0 end,
		stop = function()
			if stopped then return end
			stopped = true
			ap:Destroy()
			ao:Destroy()
			a:Destroy()
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

local busyUntil = 0
-- (a dash cuts the move short: free to cast again at once)
(require(script.Parent:WaitForChild("DashController")) :: any).OnCancel(function(c: Model)
	if c == game:GetService("Players").LocalPlayer.Character then busyUntil = 0 end
end)
local activeMover: Mover? = nil

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- Held where it stands (or carried along the baked path: the Air Cut) for the move.
local function hold(char: Model, root: BasePart, key: string, dir: Vector3)
	if activeMover then activeMover.stop() end
	local mv = holdBody(char, root)
	activeMover = mv
	if not mv then return end
	local m = MOVES[key]
	local start = CFrame.lookAt(root.Position, root.Position + dir)
	mv.set(start)
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0 - LEAD
		if not mv.alive() or t > m.length then
			conn:Disconnect()
			mv.stop()
			if activeMover == mv then activeMover = nil end
			return
		end
		if m.mover then
			-- (between two baked frames: blended so the leap is smooth)
			local x = math.max(t, 0) * RoninMoves.fps
			local i = math.clamp(math.floor(x) + 1, 1, #m.mover)
			local j = math.min(i + 1, #m.mover)
			local a, b = m.mover[i], m.mover[j]
			local f = x - math.floor(x)
			local function lerp(k: number): number return a[k] + (b[k] - a[k]) * f end
			mv.set(start * CFrame.new(lerp(1), lerp(2), lerp(3)) * CFrame.Angles(0, math.rad(lerp(4)), 0))
		end
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- M1: Edge (upper body only: you keep moving)
-- ═════════════════════════════════════════════════════════════════════════════
-- (RS solved from where the blade should point: the katana sticks straight out of the fist,
-- so the arm angles come from the blade's direction; scratchpad m1.py)
local SWINGS = {
	-- 1: right → left, flat
	{
		{ dur = 0.07, style = Enum.EasingStyle.Quad, pose = { W = { -4, -24, 0 }, N = { 0, 20, 0 }, RS = { 78.1, -67.8, 60.8 }, LS = { 25, 0, -18 } } },
		{ dur = 0.07, pose = { W = { -9, 28, 0 }, N = { 4, -22, 0 }, RS = { 17.9, 23.5, 52.7 }, LS = { -40, 0, -24 } } },
		{ dur = 0.08, style = Enum.EasingStyle.Quad, pose = { W = { -10, 34, 0 }, N = { 4, -26, 0 }, RS = { 17.2, 46.7, 49.8 }, LS = { -44, 0, -24 } } },
	},
	-- 2: left → right, backhand
	{
		{ dur = 0.07, style = Enum.EasingStyle.Quad, pose = { W = { -6, 30, 0 }, N = { 2, -24, 0 }, RS = { 57.4, 62.3, -3.3 }, LS = { -30, 0, -20 } } },
		{ dur = 0.07, pose = { W = { -10, -30, 0 }, N = { 4, 24, 0 }, RS = { 23.3, -23.1, -38.2 }, LS = { 35, 0, -28 } } },
		{ dur = 0.08, style = Enum.EasingStyle.Quad, pose = { W = { -11, -36, 0 }, N = { 4, 28, 0 }, RS = { 22.8, -53.4, -38.9 }, LS = { 38, 0, -30 } } },
	},
	-- 3: a coiled rising cut (the finisher)
	{
		{ dur = 0.12, style = Enum.EasingStyle.Quad, pose = { W = { -14, -22, 0 }, N = { -6, 18, 0 }, RS = { 214.7, -25.0, 156.8 }, LS = { 30, 0, -10 } } },
		{ dur = 0.07, pose = { W = { 8, 24, 0 }, N = { -8, -18, 0 }, RS = { 102.5, 22.7, 26.6 }, LS = { -55, 0, -30 } } },
		{ dur = 0.12, style = Enum.EasingStyle.Quad, pose = { W = { 10, 26, 0 }, N = { -8, -20, 0 }, RS = { 106.0, 29.6, 26.7 }, LS = { -58, 0, -32 } } },
	},
}
local SWING_LAND = { 0.14, 0.14, 0.19 }
local SWING_FX: { (Ctx) -> () } = {
	function(c) arc(chestCF(c, 0.5) * CFrame.Angles(0, 0, math.rad(6)), 6, 150, 1, 1.2) end,
	function(c) arc(chestCF(c, 0.5) * CFrame.Angles(0, 0, math.rad(-6)), 6, 150, -1, 1.2) end,
	function(c) arc(chestCF(c, -0.2) * CFrame.Angles(0, 0, math.rad(-70)), 6.5, 165, -1, 1.6, 0.26) end,
}

local localStep, lastSwing = 0, 0

local function swing(char: Model, root: BasePart, step: number, dir: Vector3, speed: number)
	local stages = {}
	for _, s in ipairs(SWINGS[step]) do
		table.insert(stages, { dur = s.dur / speed, style = s.style, pose = s.pose })
	end
	-- (a swing cuts a sheathe short: the blade's back out)
	local p = playing[char]
	if p and (p.key == "sheathe" or p.key == "sheathe_walk") then
		playing[char] = nil
		RoninLook.SetSlide(char, 0)
	end
	CastPoses.play(char, stages, 0.2 / speed)
	drawnUntil[char] = os.clock() + COMBAT_HOLD
	setDrawn(char, true)
	local ctx: Ctx = { char = char, root = root, dir = dir, mine = char == player.Character }
	task.delay(SWING_LAND[step] / speed - 0.05, function()
		if not root.Parent then return end
		trailOn(char, 0.15)
		SWING_FX[step](ctx)
		ClassFX.Sound("whoosh", root, 0.7, 1.25 + step * 0.08)
	end)
end

function RoninController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	if localStep > 0 and now - lastSwing < M1_FREE[localStep] / speed then return true end
	localStep = if now - lastSwing > COMBO_RESET or localStep >= 3 then 1 else localStep + 1
	lastSwing = now
	local dir = flatDir(deps.getAim(root), root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	swing(char, root, localStep, dir, speed)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Skills (caster)
-- ═════════════════════════════════════════════════════════════════════════════
local SKILL_MOVE = { "rangedCut", "risingCut", "airCut", "finisher" }

function RoninController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

-- ── Rising Cut: held ────────────────────────────────────────────────────────
-- He sinks into the coiled draw (the baked frames up to RISE_HOLD) and holds
-- it, the hand trembling on the hilt harder each stage, until the release.
local function coil(char: Model)
	local stages = table.clone(stagesOf("risingCut_coil"))
	local last = stages[#stages].pose
	local t0 = os.clock()
	table.insert(stages, { dur = 60, pose = last, wobble = function()
		local held = os.clock() - t0
		local k = ({ 0.15, 0.5, 1 })[riseStage(held)]
		local j = math.sin(held * 61) * k
		return { RS = { j * 1.6, 0, j }, LS = { -j, 0, 0 }, N = { j * 0.5, 0, 0 } }
	end })
	CastPoses.play(char, stages, RECOVER, true, { carry = 0, plant = false })
	playing[char] = { key = "risingCut_coil", t0 = os.clock(), char = char, keep = shownDrawn[char] == true, seen = false }
	drawnUntil[char] = nil
end

type Rising = { t0: number, char: Model, root: BasePart, dir: Vector3, config: any, fx: ChargeFx, conn: RBXScriptConnection, token: {} }
local rising: Rising? = nil
-- (everyone else's charges, shown on their bodies here)
local otherCharges: { [Model]: ChargeFx } = {}

local function startRising(char: Model, root: BasePart, dir: Vector3, config: any)
	busyUntil = math.huge
	coil(char)
	hold(char, root, "risingCut_coil", dir)
	local token = {}
	local t0 = os.clock()
	local conn = RunService.Heartbeat:Connect(function()
		local r = rising
		if not r or r.token ~= token then return end
		-- (he turns with the aim while it charges)
		if activeMover and root.Parent and deps then
			local d = flatDir(deps.getAim(root), root.CFrame.LookVector)
			activeMover.set(CFrame.lookAt(root.Position, root.Position + d))
		end
		if os.clock() - t0 >= RISE_STAGE3 + RISE_STILL then RoninController.Release(2) end
	end)
	rising = { t0 = t0, char = char, root = root, dir = dir, config = config, fx = risingChargeFx(char, root, true), conn = conn, token = token }
end

-- The Rising Cut's key came up (SkillController), or it let go by itself.
function RoninController.Release(skillIndex: number)
	if skillIndex ~= 2 then return end
	local r = rising
	if not r then return end
	rising = nil
	r.conn:Disconnect()
	local held = os.clock() - r.t0
	local stage = riseStage(held)
	local char, root = r.char, r.root
	local dir = if root.Parent and deps then flatDir(deps.getAim(root), root.CFrame.LookVector) else r.dir
	Network.GetRemoteEvent(Network.Remotes.RoninInput):FireServer({ kind = "release", held = held, dir = dir })
	r.fx.stop(stage)
	if not (char.Parent and root.Parent) then
		busyUntil = 0
		return
	end
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local length = LEAD + RISING_RELEASE.length
	busyUntil = os.clock() + length
	local size = tonumber(player:GetAttribute("Stat_size")) or 1
	local ctx: Ctx = { char = char, root = root, dir = dir, mine = true, stage = stage,
		radius = ((r.config and r.config.range) or 20) * size * RISE_RANGE[stage] }
	play(char, "risingCut_release", ctx)
	hold(char, root, "risingCut_release", dir)
	releaseAfter(char, length)
end

function RoninController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any, cursor: Vector3?): Vector3?
	local key = SKILL_MOVE[skillIndex]
	if not key then return nil end
	local dir = flatDir(aimDir, root.CFrame.LookVector)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	char:SetAttribute("AllowSkillMovement", false)
	if key == "risingCut" then
		-- (held: it charges until the key comes up)
		startRising(char, root, dir, config)
		return nil
	end
	local length = LEAD + RoninMoves[key].length
	busyUntil = os.clock() + length
	local ctx: Ctx = { char = char, root = root, dir = dir, mine = true }
	local target: Vector3? = nil
	if key == "rangedCut" then
		-- (where the server will land the cuts: the cursor, within reach)
		local range = config and config.range or 40
		local from = root.Position
		local pos = from + dir * math.min(range, 20)
		if cursor then
			local d = Vector3.new(cursor.X - from.X, 0, cursor.Z - from.Z)
			pos = Vector3.new(from.X, cursor.Y, from.Z) + (if d.Magnitude > range then d.Unit * range else d)
		end
		ctx.pos = pos + Vector3.new(0, 2.5, 0)
		ctx.radius = (config and config.radius or 9) * (tonumber(player:GetAttribute("Stat_size")) or 1)
		target = cursor
	elseif key == "risingCut" then
		ctx.radius = (config and config.range or 20) * (tonumber(player:GetAttribute("Stat_size")) or 1)
	elseif key == "airCut" then
		ctx.radius = (config and config.radius or 12) * (tonumber(player:GetAttribute("Stat_size")) or 1)
	elseif key == "finisher" then
		ctx.pos = root.Position
		ctx.radius = (config and config.radius or 30) * (tonumber(player:GetAttribute("Stat_size")) or 1)
	end
	play(char, key, ctx)
	hold(char, root, key, dir)
	releaseAfter(char, length)
	return target
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Server moments (RoninFX): everyone else's moves
-- ═════════════════════════════════════════════════════════════════════════════
local HANDLERS: { [string]: (any) -> () } = {
	move = function(msg)
		if msg.attacker == player then return end -- ours was predicted on cast
		local char = charOf(msg.attacker)
		local root = rootOf(char)
		if not char or not root or not MOVES[msg.move] then return end
		local ctx: Ctx = { char = char, root = root, dir = flatDir(msg.dir, root.CFrame.LookVector),
			pos = if typeof(msg.pos) == "Vector3" then (msg.pos :: Vector3) + Vector3.new(0, if msg.move == "rangedCut" then 2.5 else 0, 0) else nil,
			radius = tonumber(msg.radius), mine = false, stage = tonumber(msg.stage) }
		-- (their charge ends in the release)
		local ch = otherCharges[char]
		if ch then
			otherCharges[char] = nil
			ch.stop(ctx.stage or 1)
		end
		play(char, msg.move, ctx)
	end,
	-- someone else coiling into a charged Rising Cut
	risingCharge = function(msg)
		if msg.attacker == player then return end
		local char = charOf(msg.attacker)
		local root = rootOf(char)
		if not char or not root then return end
		local old = otherCharges[char]
		if old then old.stop(1) end
		coil(char)
		local fx = risingChargeFx(char, root, false)
		otherCharges[char] = fx
		-- (safety: never left running)
		task.delay(RISE_STAGE3 + RISE_STILL + 1.5, function()
			if otherCharges[char] == fx then
				otherCharges[char] = nil
				fx.stop(1)
			end
		end)
	end,
	m1 = function(msg)
		if msg.attacker == player then return end
		local char = charOf(msg.attacker)
		local root = rootOf(char)
		if not char or not root or not FxBudget.Allow("roninSwing", 10) then return end
		swing(char, root, math.clamp(tonumber(msg.step) or 1, 1, 3), flatDir(msg.dir, root.CFrame.LookVector), 1)
	end,
}

function RoninController.Init(d: Deps)
	deps = d
	PackFX.Preload(PACK_USED)
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localStep = 0
		local r = rising
		if r then
			rising = nil
			r.conn:Disconnect()
			r.fx.stop(1)
		end
		if activeMover then
			activeMover.stop()
			activeMover = nil
		end
	end)
	RunService.Heartbeat:Connect(function()
		local ok, err = pcall(driveStep)
		if not ok then warn("[RoninController] drive", err) end
	end)
	-- Every Ronin starts with the katana sheathed (re-checked as tools load in).
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, p in ipairs(Players:GetPlayers()) do
				local c = p.Character
				if c and p:GetAttribute("SelectedClass") == "ronin" and not playing[c] and not drawnUntil[c] then
					if shownDrawn[c] ~= false then setDrawn(c, false) end
				end
			end
			for c in pairs(shownDrawn) do
				if not c.Parent then shownDrawn[c] = nil end
			end
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.RoninFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[RoninController]", msg.kind, err) end
		end
	end)
end

return RoninController
