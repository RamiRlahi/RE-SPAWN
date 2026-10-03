--!strict
--[[
	FireKnightController.luau
	Client side of the Fire Knight (class id "heavy_knight"; server:
	FireKnightServer).

	  • Emberblade: your own swings are predicted (pose, flaming crescents,
	    explosions) on click; the server resolves hits and sends everyone
	    else's swings over FireKnightFX.
	  • Skills: the Blazing Charge movement, the Phoenix Slam flight (rise,
	    the landing marker under the cursor, the dive), the Earthshaker
	    wind-up and the Heart of the Inferno awakening (camera close-up).
	  • Every Fire Knight effect for every player, in real flame (FireFX's
	    flipbook fire): slashes, explosions, fire lines, burning ground,
	    cracks in the ground, rings of fire, ignites, the phoenix, the Overheat
	    flare, the Inferno and the Final Blow (every flame flying into the
	    sword, then the flame wave).
	  • Heat you can see on every Fire Knight: blade flames grow, embers, a
	    glow through the armor, burning footprints, fire on the shoulders at
	    100, glowing eyes in the Inferno.
	  • Heat bar above the skill bar (OVERHEAT / INFERNO timers), and Scorch
	    pips over burning enemies.
	Visuals are particles, beams and a little Neon (no lights).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))

local player = Players.LocalPlayer

local FireKnightController = {}

local CLASS = "heavy_knight"

-- ── Tuning (mirrors FireKnightServer) ───────────────────────────────────────
local SWING_INTERVAL = 0.42
local COMBO_RESET = 1.2
local EXECUTION_WINDUP = 0.32
local CHARGE_WINDUP = 0.22
local QUAKE_WINDUP = 0.55
local AWAKEN = 1.6
local PHOENIX_RISE = 0.55
local PHOENIX_AIM = 2.2
local PHOENIX_DIVE = 0.3
local PHOENIX_HEIGHT = 13

local FIRE = Color3.fromRGB(255, 120, 40)
local EMBER = Color3.fromRGB(255, 190, 90)
local HOT = Color3.fromRGB(255, 236, 170)
local DEEP = Color3.fromRGB(190, 45, 15)
local WHITE = Color3.fromRGB(255, 255, 255)

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local FLAT = CFrame.Angles(0, 0, math.rad(90))

type Deps = {
	shake: (number, number) -> (),
	fovPunch: (number, number) -> (),
	getAim: (BasePart) -> Vector3,
}
local deps: Deps

local localStep = 0
local lastSwing = 0
local busyUntil = 0
local rootToken = 0
local rng = Random.new()

local function isFireKnight(p: Player?): boolean
	return p ~= nil and p:GetAttribute("SelectedClass") == CLASS
end

local function rootOf(char: Model?): BasePart?
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function charOf(p: Player?): Model?
	return p and p.Character or nil
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function heatOf(p: Player?): number
	return if p then tonumber(p:GetAttribute("FK_Heat")) or 0 else 0
end

local function empowered(p: Player?): boolean
	local c = charOf(p)
	return p ~= nil and (p:GetAttribute("FK_Overheat") == true or (c ~= nil and c:GetAttribute("FK_Inferno") ~= nil))
end

local function sizeMult(): number
	return tonumber(player:GetAttribute("Stat_size")) or 1
end

local function near(pos: Vector3, dist: number): boolean
	local r = rootOf(player.Character)
	return r ~= nil and (r.Position - pos).Magnitude < dist
end

-- ── VFX pieces ──────────────────────────────────────────────────────────────
local function neon(props: { [string]: any }): BasePart
	return ClassFX.Neon(props)
end

local function nsk(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

local function fireColors(): ColorSequence
	return ColorSequence.new({
		ColorSequenceKeypoint.new(0, HOT),
		ColorSequenceKeypoint.new(0.35, FIRE),
		ColorSequenceKeypoint.new(1, DEEP),
	})
end

-- Running flames (on the blade, the hair, the shoulders, burning enemies):
-- the flipbook flame, kept upright.
local function fireEmitter(parent: Instance, size: number, rate: number, speed: number, life: number): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.Texture = FireFX.TEX.flame
	e.FlipbookLayout = Enum.ParticleFlipbookLayout.Grid4x4
	e.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
	e.Color = fireColors()
	e.Brightness = 2.5
	e.LightEmission = 0.6
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ nsk(0, size * 0.75), nsk(0.3, size), nsk(1, size * 0.3) })
	e.Transparency = NumberSequence.new({ nsk(0, 0.1), nsk(0.7, 0.25), nsk(1, 1) })
	e.Lifetime = NumberRange.new(life * 0.7, life)
	e.Speed = NumberRange.new(speed * 0.4, speed)
	e.Acceleration = Vector3.new(0, 7, 0)
	e.SpreadAngle = Vector2.new(30, 30)
	e.Rotation = NumberRange.new(-12, 12)
	e.RotSpeed = NumberRange.new(-15, 15)
	e.Drag = 1.5
	e.Rate = rate
	e.Parent = parent
	return e
end

local function smokePuff(pos: Vector3, count: number, size: number)
	local anchor = neon({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SMOKE
	e.Color = ColorSequence.new(Color3.fromRGB(70, 50, 44), Color3.fromRGB(30, 26, 26))
	e.LightInfluence = 0.3
	e.Size = NumberSequence.new({ nsk(0, size * 0.5), nsk(1, size) })
	e.Transparency = NumberSequence.new({ nsk(0, 0.55), nsk(1, 1) })
	e.Lifetime = NumberRange.new(0.8, 1.4)
	e.Speed = NumberRange.new(2, 6)
	e.Acceleration = Vector3.new(0, 3, 0)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 2
	e.Rate = 0
	e.Parent = anchor
	e:Emit(count)
	Debris:AddItem(anchor, 1.6)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundY(pos: Vector3): number
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	groundParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -24, 0), groundParams)
	return if hit then hit.Position.Y else pos.Y - 3
end

local function onGround(pos: Vector3): Vector3
	return Vector3.new(pos.X, groundY(pos), pos.Z)
end

-- A fiery explosion (FireFX: a flash, the fireball, flame licks, embers,
-- smoke, a shockwave and the floor scorched).
local function explosion(pos: Vector3, radius: number, big: boolean?)
	FireFX.Explosion(pos, radius, big)
end

-- A column of flame erupting from the ground (fire lines, eruptions).
local function eruption(pos: Vector3, height: number, width: number)
	FireFX.Column(pos, height, width)
end

-- Where the greatsword is (for flames gathering on it).
local function bladeTip(char: Model): Vector3?
	local tool = char:FindFirstChild("Greatsword")
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	if not handle then return nil end
	return (handle.CFrame * CFrame.new(0, 6.5, 0)).Position
end

local function trail(char: Model, seconds: number)
	local tool = char:FindFirstChild("Greatsword")
	local t = tool and tool:FindFirstChild("SlashTrail", true)
	if t and t:IsA("Trail") then
		t.Enabled = true
		task.delay(seconds, function() if t.Parent then t.Enabled = false end end)
	end
end

-- A pop-up word over a character ("OVERHEAT", "PERFECT PARRY").
local function popWord(char: Model, text: string, color: Color3, size: number)
	local root = rootOf(char)
	if not root then return end
	local bb = Instance.new("BillboardGui")
	bb.Adornee = root
	bb.Size = UDim2.fromOffset(280, 60)
	bb.StudsOffset = Vector3.new(0, 4.4, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = ClassFX.Folder()
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.Arcade
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeColor3 = Color3.fromRGB(50, 10, 0)
	l.TextStrokeTransparency = 0.2
	l.Parent = bb
	local sc = Instance.new("UIScale")
	sc.Scale = 1.8
	sc.Parent = l
	TweenService:Create(sc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(bb, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.5),
		{ StudsOffset = Vector3.new(0, 6.4, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.7),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(bb, 1.2)
end

-- A flaming slash: the whole blade's path burns (a filled sweep from the
-- hilt to the tip), with a white-hot edge where the tip passed.
local function crescent(cf: CFrame, radius: number, arc: number, thickness: number, life: number, sweep: number?, color: Color3?)
	SwordFX.Sweep({ cf = cf, inner = radius * 0.2, outer = radius, arc = arc, sweep = sweep, color = color or FIRE,
		life = life * 1.15, draw = 0.07, opacity = 0.55 })
	SwordFX.Sweep({ cf = cf, inner = radius * 0.55, outer = radius * 0.95, arc = arc, sweep = sweep, color = HOT,
		life = life * 0.8, draw = 0.07, opacity = 0.4 })
	SwordFX.Arc({ cf = cf, radius = radius, arc = arc, sweep = sweep, width = thickness * 2.4, color = color or FIRE, life = life })
	FireFX.Slash(cf, radius, arc, sweep or 1, 0.07, color == HOT)
end

-- Burning ground left behind (FireFX: glowing cracks with flames licking up
-- across them); drawn in by the Final Blow.
local patchFx: { FireFX.Burn } = {}

local function patch(pos: Vector3, radius: number, life: number)
	local b = FireFX.Burning(pos, radius, life)
	table.insert(patchFx, b)
	task.delay(life, function()
		local i = table.find(patchFx, b)
		if i then table.remove(patchFx, i) end
	end)
end

-- The ground splitting open from `center` over `t` (and staying split for
-- `hold`): the cracks spread, light and flame push up through them.
local function cracks(center: Vector3, radius: number, t: number, hold: number)
	local g = onGround(center)
	FireFX.Cracks(g, radius * 0.45, t * 0.5 + hold + 0.3, true)
	task.delay(t * 0.4, FireFX.Cracks, g, radius, t * 0.6 + hold + 0.4, false)
	-- flames licking up out of the cracks as they open
	for i = 1, 7 do
		task.delay(t * (0.2 + 0.7 * i / 7), function()
			local a = rng:NextNumber(0, math.pi * 2)
			local d = radius * rng:NextNumber(0.2, 0.85)
			FireFX.Puff("flame", CFrame.new(g + Vector3.new(math.cos(a) * d, 0.4, math.sin(a) * d)), 1.6, 2, function(e)
				e.EmissionDirection = Enum.NormalId.Top
				e.Speed = NumberRange.new(3, 6)
			end)
		end)
	end
	-- Light pushing up through the cracks.
	local anchor = neon({ Size = Vector3.new(radius * 1.6, 0.1, radius * 1.6), CFrame = CFrame.new(g + Vector3.new(0, 0.1, 0)),
		Transparency = 1 })
	local e = FireFX.Emitter("embers", anchor, 0.3)
	e.EmissionDirection = Enum.NormalId.Top
	e.SpreadAngle = Vector2.new(5, 5)
	e.Speed = NumberRange.new(4, 9)
	e.Rate = radius * 3
	task.delay(t, function() e.Enabled = false end)
	Debris:AddItem(anchor, t + 1.5)
end

-- ── Poses (CastPoses: +rx raises the arm forward, ry turns about vertical) ──
-- Weight and follow-through: each move is an anticipation (Quad, smooth),
-- a strike (Quart, accelerating into the hit), a follow-through (Cubic out,
-- settling) and a slow recovery, so the greatsword feels heavy.
--
-- R6: the waist IS the root joint, so leaning or turning the torso swings
-- the legs with it. `stance` builds a grounded lower body: the torso leans
-- (`lean`, - = forward) and turns (`twist`), the legs are set by their WORLD
-- angles (left foot `front`, right foot `back`, `spread` to the sides) with
-- the lean cancelled at the hips, and the body drops exactly as far as the
-- legs' angles lower the hips, so the feet stay on the floor.
type Pose = { [string]: { number } }

local function stance(p: Pose, lean: number, twist: number, front: number, back: number, spread: number?): Pose
	local sp = spread or 6
	p.W = { lean, twist, 0 }
	p.LH = { front - lean, -twist, -sp }
	p.RH = { -back - lean, -twist, sp }
	local legs = math.rad((math.abs(front) + math.abs(back)) / 2)
	local drop = (1 - math.cos(math.rad(lean))) + 2 * (1 - math.cos(legs)) + 2 * (1 - math.cos(math.rad(sp)))
	p.Root = { 0, 0, 0, 0, -drop, 0 }
	return p
end

-- Arms by WORLD angle (rx from hanging, + = forward/up), so a pose reads the
-- same whatever the lean. `lz` / `rz` bring the hands together on the hilt.
local function arms(p: Pose, lean: number, rx: number, ry: number, lx: number, ly: number, rz: number?, lz: number?): Pose
	p.RS = { rx - lean, ry, rz or 0 }
	p.LS = { lx - lean, ly, lz or 0 }
	return p
end

local function pose(lean: number, twist: number, front: number, back: number, rx: number, ry: number, lx: number, ly: number,
	extra: Pose?, spread: number?): Pose
	local p: Pose = {}
	stance(p, lean, twist, front, back, spread)
	arms(p, lean, rx, ry, lx, ly, 8, -8)
	if extra then
		for k, v in pairs(extra) do p[k] = v end
	end
	return p
end

-- ── The grip ────────────────────────────────────────────────────────────────
-- Held normally the blade stands out of the fist at right angles to the arm
-- (right for flat sweeps and the guard). For chops, slams, the charge and
-- the rising slash the hands turn it to run along the arm (k = 1), so arms
-- overhead put the blade to the sky and arms coming down drive it into the
-- ground ahead; k = 2 reverses it (planted point-down). Eased every frame.
type GripState = { tool: Tool, base: CFrame, k: number, from: number, target: number, t0: number, dur: number }
local grips: { [Tool]: GripState } = {}

local function gripTo(char: Model, target: number, dur: number)
	local tool = char:FindFirstChild("Greatsword")
	if not (tool and tool:IsA("Tool")) then return end
	local s = grips[tool]
	if not s then
		s = { tool = tool, base = tool.Grip, k = 0, from = 0, target = 0, t0 = 0, dur = 0 }
		grips[tool] = s
	end
	local g = s :: GripState
	g.from, g.target, g.t0, g.dur = g.k, target, os.clock(), math.max(dur, 0.01)
end

RunService.RenderStepped:Connect(function()
	local now = os.clock()
	for tool, g in pairs(grips) do
		if not tool.Parent then
			grips[tool] = nil
		elseif g.k ~= g.target then
			local a = math.clamp((now - g.t0) / g.dur, 0, 1)
			local e = -(math.cos(math.pi * a) - 1) / 2
			g.k = if a >= 1 then g.target else g.from + (g.target - g.from) * e
			tool.Grip = g.base * CFrame.Angles(math.rad(90) * g.k, 0, 0)
		end
	end
end)

-- Back to the normal grip after `after` seconds, unless another move has
-- taken the grip since.
local function gripBack(char: Model, after: number, dur: number)
	local tool = char:FindFirstChild("Greatsword")
	local s = tool and tool:IsA("Tool") and grips[tool]
	if not s then return end
	local stamp = s.t0
	task.delay(after, function()
		if grips[s.tool] == s and s.t0 == stamp then gripTo(char, 0, dur) end
	end)
end

local QUAD = Enum.EasingStyle.Quad
local QUART = Enum.EasingStyle.Quart
local SINE = Enum.EasingStyle.Sine

-- A held pose trembling with effort.
local function tremble(amount: number)
	return function(t: number): Pose
		local s = math.sin(t * 47) * amount
		return { RS = { s, 0, s * 0.5 }, LS = { -s, 0, -s * 0.5 }, N = { s * 0.4, 0, 0 } }
	end
end

-- Seconds from the start of each combo swing to its hit (FireKnightServer
-- lands the damage on the same beat).
local COMBO_HIT = { 0.12, 0.11, 0.14, EXECUTION_WINDUP }

local function swingPose(char: Model, step: number)
	if step == 1 then
		-- Cinder Slash: weight back and coiled right, the blade low and flat;
		-- the hips drive a wide sweep across to the left and carry on round.
		gripTo(char, 0, 0.1)
		CastPoses.play(char, {
			{ dur = 0.12, style = QUAD, pose = pose(-6, 45, 14, 14, 25, 105, 20, 80, { N = { 0, -30, 0 } }) },
			{ dur = 0.08, style = QUART, pose = pose(-12, -35, 22, 22, 25, -90, 20, -65, { N = { 0, 20, 0 } }) },
			{ dur = 0.16, pose = pose(-10, -50, 22, 22, 20, -115, 15, -88, { N = { 0, 28, 0 } }) },
		}, 0.34, true)
	elseif step == 2 then
		-- Scorching Cross: gathered up high on the left, then cut down across
		-- to the low right; the two trails cross into an X.
		gripTo(char, 0, 0.1)
		CastPoses.play(char, {
			{ dur = 0.11, style = QUAD, pose = pose(4, -40, 14, 14, 115, -65, 105, -45, { N = { -6, 25, 0 } }) },
			{ dur = 0.08, style = QUART, pose = pose(-16, 38, 24, 24, 5, 85, 10, 60, { N = { 8, -15, 0 } }) },
			{ dur = 0.16, pose = pose(-13, 50, 24, 24, 0, 98, 5, 72, { N = { 8, -22, 0 } }) },
		}, 0.34, true)
	elseif step == 3 then
		-- Furnace Breaker: the blade turned to run along the arms and lifted
		-- straight overhead (arching back), then chopped down into the ground
		-- ahead with the whole body.
		gripTo(char, 1, 0.12)
		CastPoses.play(char, {
			{ dur = 0.14, style = QUAD, pose = pose(8, 0, 14, 14, 172, 0, 170, 0, { N = { 12, 0, 0 } }) },
			{ dur = 0.07, style = QUART, pose = pose(-26, 0, 30, 30, 38, 0, 40, 0, { N = { 16, 0, 0 } }) },
			{ dur = 0.2, pose = pose(-30, 0, 32, 32, 32, 0, 34, 0, { N = { 18, 0, 0 } }) },
		}, 0.4, true)
		gripBack(char, 0.42, 0.3)
	else
		-- Infernal Execution: the sword hauled back over the shoulder until the
		-- blade hangs behind him, held trembling... then the SLAM, the whole
		-- body following it down into a deep lunge.
		gripTo(char, 1, 0.14)
		CastPoses.play(char, {
			{ dur = 0.18, style = QUAD, pose = pose(14, 28, 18, 18, 200, 18, 195, 12, { N = { 14, -12, 0 } }) },
			{ dur = EXECUTION_WINDUP - 0.18, style = Enum.EasingStyle.Linear,
				pose = pose(16, 30, 18, 18, 206, 18, 200, 12, { N = { 16, -12, 0 } }), wobble = tremble(1.5) },
			{ dur = 0.08, style = QUART, pose = pose(-38, 0, 38, 38, 42, 0, 44, 0, { N = { 22, 0, 0 } }) },
			{ dur = 0.34, pose = pose(-36, 0, 38, 38, 38, 0, 40, 0, { N = { 20, 0, 0 } }) },
		}, 0.48, true)
		gripBack(char, EXECUTION_WINDUP + 0.5, 0.35)
	end
end

local function chargePose(char: Model, windup: number, dur: number)
	-- He lowers the sword (tip trailing low behind him), crouches and
	-- ignites, then drives forward in long running strides.
	gripTo(char, 1, windup)
	local t0 = os.clock()
	CastPoses.play(char, {
		{ dur = windup, style = QUAD, pose = pose(-18, 25, 22, 22, -35, 30, 25, 0, { N = { 12, -15, 0 } }) },
		{ dur = dur, pose = pose(-34, 12, 30, 30, -40, 25, 30, 0, { N = { 26, -8, 0 } }),
			wobble = function()
				local s = math.sin((os.clock() - t0) * 22) * 28
				return { RH = { s, 0, 0 }, LH = { -s, 0, 0 }, LS = { -s * 0.6, 0, 0 } }
			end },
	}, nil, true)
end

local function risePose(char: Model)
	-- The upward slash: sunk low with the blade down by the floor, then
	-- ripped up and over, rising onto the toes.
	gripTo(char, 1, 0.05)
	local up = pose(10, -5, 18, 18, 165, 0, 160, 0, { N = { -18, 0, 0 } })
	up.Root[5] += 0.6
	CastPoses.play(char, {
		{ dur = 0.06, style = QUAD, pose = pose(-24, 10, 32, 32, 18, 5, 20, 0, { N = { 18, 0, 0 } }) },
		{ dur = 0.12, style = QUART, pose = up },
		{ dur = 0.22, pose = pose(6, 0, 16, 16, 150, 0, 145, 0, { N = { -12, 0, 0 } }) },
	}, 0.42, true)
	gripBack(char, 0.5, 0.3)
end

local function quakePose(char: Model, windup: number)
	-- Both hands lift the sword high over his head, arched back, trembling
	-- with the heat... then drive it straight down into the ground.
	gripTo(char, 1, windup * 0.4)
	CastPoses.play(char, {
		{ dur = windup * 0.55, style = QUAD, pose = pose(12, 0, 16, 16, 178, 0, 176, 0, { N = { 20, 0, 0 } }, 10) },
		{ dur = windup * 0.45, style = Enum.EasingStyle.Linear, pose = pose(14, 0, 16, 16, 182, 0, 180, 0, { N = { 22, 0, 0 } }, 10),
			wobble = tremble(2) },
		{ dur = 0.08, style = QUART, pose = pose(-44, 0, 34, 34, 22, 0, 24, 0, { N = { 24, 0, 0 } }, 16) },
		{ dur = 0.36, pose = pose(-42, 0, 34, 34, 20, 0, 22, 0, { N = { 22, 0, 0 } }, 16) },
	}, 0.5, true)
	gripBack(char, windup + 0.5, 0.35)
end

-- Planted sword, both hands on the pommel, head bowed (the Awakening): the
-- grip reversed so the blade points into the ground.
local PLANTED = pose(-10, 0, 4, 4, 65, 0, 65, 0, { RS = { 75, 0, -18 }, LS = { 75, 0, 18 }, N = { -30, 0, 0 } }, 8)

local function plantSword(char: Model, seconds: number)
	gripTo(char, 2, 0.2)
	CastPoses.play(char, {
		{ dur = 0.35, style = SINE, pose = PLANTED },
		{ dur = math.max(seconds - 0.35, 0.05), pose = PLANTED, wobble = function(t)
			local b = math.sin(t * 2) * 1
			return { N = { b, 0, 0 } }
		end },
	}, 0.3, true)
	gripBack(char, seconds, 0.25)
end

local function raisePose(char: Model, seconds: number)
	-- The sword raised to the sky in both hands, blade straight up.
	gripTo(char, 1, 0.2)
	local p = pose(8, 0, 12, 12, 172, 0, 170, 0, { N = { 18, 0, 0 } }, 8)
	CastPoses.play(char, {
		{ dur = 0.22, style = QUAD, pose = p },
		{ dur = math.max(seconds - 0.22, 0.05), pose = p, wobble = tremble(1.2) },
	}, 0.3, true)
end

local function slamPose(char: Model)
	-- The Final Blow: one enormous downward slash into a deep lunge.
	gripTo(char, 1, 0.05)
	CastPoses.play(char, {
		{ dur = 0.08, style = QUART, pose = pose(-40, 0, 40, 40, 40, 0, 42, 0, { N = { 22, 0, 0 } }) },
		{ dur = 0.45, pose = pose(-38, 0, 40, 40, 36, 0, 38, 0, { N = { 20, 0, 0 } }) },
	}, 0.5, true)
	gripBack(char, 0.6, 0.35)
end

-- ── Combo visuals ───────────────────────────────────────────────────────────
local function comboVFX(char: Model, attacker: Player?, step: number, dir: Vector3)
	local root = rootOf(char)
	if not root then return end
	local look = CFrame.lookAt(root.Position, root.Position + dir)
	local heat = heatOf(attacker)
	local hot = empowered(attacker)
	local thick = (1 + heat / 100 * 0.6) * (if hot then 1.3 else 1)
	local color = if hot then HOT else FIRE
	local size = tonumber(attacker and attacker:GetAttribute("Stat_size")) or 1
	trail(char, if step == 4 then EXECUTION_WINDUP + 0.3 else 0.3)
	if step == 1 then
		-- High-right to low-left: half of the X.
		-- (Each slash draws in over the strike, landing on COMBO_HIT.)
		task.delay(COMBO_HIT[1] - 0.04, crescent, look * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(-24)), 6.5 * size, 150, thick, 0.4, 1, color)
		task.delay(COMBO_HIT[1], ClassFX.Burst, root.Position + dir * 4 + Vector3.new(0, 1, 0), EMBER, 10, 14, TEX_SPARK, 0.3, 0.5)
	elseif step == 2 then
		-- High-left to low-right: crosses the first trail into an X.
		task.delay(COMBO_HIT[2] - 0.04, crescent, look * CFrame.new(0, 0.6, 0) * CFrame.Angles(0, 0, math.rad(24)), 6.5 * size, 150, thick, 0.4, -1, color)
		task.delay(COMBO_HIT[2], ClassFX.Burst, root.Position + dir * 4 + Vector3.new(0, 1, 0), EMBER, 10, 14, TEX_SPARK, 0.3, 0.5)
	elseif step == 3 then
		-- A vertical chop that bursts into a small explosion.
		task.delay(COMBO_HIT[3] - 0.04, crescent, look * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)), 5.5 * size, 150, thick, 0.25, -1, color)
		task.delay(COMBO_HIT[3] + 0.02, function()
			explosion(onGround(root.Position + dir * 6 * size) + Vector3.new(0, 0.8, 0), 7 * size * 0.55, false)
		end)
	else
		-- Flames gather on the pulled-back blade...
		task.delay(0.05, function()
			local tip = bladeTip(char)
			if tip then FireFX.Flames(tip, 2.2, 3, 0.8) end
			ClassFX.Sound("fireWhoosh", root, 0.6, 0.8)
		end)
		-- ...then the SLAM: a massive overhead crescent, a big explosion and a
		-- line of fire racing on from the impact.
		task.delay(EXECUTION_WINDUP, function()
			if not root.Parent then return end
			local base = CFrame.lookAt(root.Position, root.Position + dir)
			crescent(base * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), 7.5 * size, 170, thick * 1.5, 0.3, -1, color)
			local impact = onGround(root.Position + dir * 6 * size)
			explosion(impact + Vector3.new(0, 1, 0), 8.5 * size * 0.6, true)
			for i = 1, 8 do
				task.delay(i * 0.035, eruption, impact + dir * (i * 2.5 * size), 5 + rng:NextNumber(0, 2), 1.6)
			end
			ClassFX.Sound("rockHit", impact, 0.8, 0.8)
			if attacker == player then
				deps.shake(0.9, 0.22)
				deps.fovPunch(4, 0.2)
			end
		end)
	end
end

-- ── Heat HUD ────────────────────────────────────────────────────────────────
local hud: ScreenGui? = nil
local hudFill: Frame? = nil
local hudLabel: TextLabel? = nil
local hudGlow: UIStroke? = nil

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "FireKnightHeat"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local bar = Instance.new("Frame")
	bar.AnchorPoint = Vector2.new(0.5, 1)
	bar.Position = UDim2.new(0.5, 0, 1, -132)
	bar.Size = UDim2.fromOffset(300, 12)
	bar.BackgroundColor3 = Color3.fromRGB(24, 14, 12)
	bar.BorderSizePixel = 0
	bar.Parent = g
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 60, 30)
	stroke.Thickness = 1.5
	stroke.Parent = bar
	hudGlow = stroke
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = WHITE
	fill.BorderSizePixel = 0
	fill.Parent = bar
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, DEEP),
		ColorSequenceKeypoint.new(0.6, FIRE),
		ColorSequenceKeypoint.new(1, HOT),
	})
	grad.Parent = fill
	hudFill = fill
	for _, at in ipairs({ 0.25, 0.5, 0.75 }) do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(at, 0.5)
		tick.Size = UDim2.new(0, 2, 1, 4)
		tick.BackgroundColor3 = Color3.fromRGB(255, 220, 170)
		tick.BackgroundTransparency = 0.45
		tick.BorderSizePixel = 0
		tick.ZIndex = 2
		tick.Parent = bar
	end
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 0, -3)
	lbl.Size = UDim2.fromOffset(300, 20)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Arcade
	lbl.TextSize = 18
	lbl.TextColor3 = EMBER
	lbl.TextStrokeColor3 = Color3.fromRGB(40, 10, 0)
	lbl.TextStrokeTransparency = 0.3
	lbl.Text = "HEAT 0"
	lbl.Parent = bar
	hudLabel = lbl
end

local function refreshHud()
	local g, fill, lbl = hud, hudFill, hudLabel
	if not g or not fill or not lbl then return end
	g.Enabled = isFireKnight(player) and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	if not g.Enabled then return end
	local now = Workspace:GetServerTimeNow()
	local char = player.Character
	local infernoEnd = tonumber(player:GetAttribute("FK_InfernoEnd"))
	local overEnd = tonumber(player:GetAttribute("FK_OverheatEnd"))
	if infernoEnd and infernoEnd > now and char and char:GetAttribute("FK_Inferno") ~= nil then
		fill.Size = UDim2.fromScale(1, 1)
		lbl.Text = string.format("INFERNO  %.1f", infernoEnd - now)
		lbl.TextColor3 = HOT
	elseif player:GetAttribute("FK_Overheat") == true and overEnd then
		-- The bar drains as the Overheat runs out.
		fill.Size = UDim2.fromScale(math.clamp((overEnd - now) / 6, 0, 1), 1)
		lbl.Text = "OVERHEAT"
		lbl.TextColor3 = if math.floor(os.clock() * 6) % 2 == 0 then HOT else FIRE
	else
		local h = heatOf(player)
		fill.Size = UDim2.fromScale(h / 100, 1)
		lbl.Text = `HEAT {h}`
		lbl.TextColor3 = EMBER
	end
	if hudGlow then
		hudGlow.Color = if player:GetAttribute("FK_Overheat") == true then FIRE else Color3.fromRGB(120, 60, 30)
	end
end

-- ── Heat you can see: per Fire Knight character ─────────────────────────────
type Look = {
	char: Model,
	handle: BasePart?,
	flames: { ParticleEmitter },
	aura: ParticleEmitter?,
	shoulders: { ParticleEmitter },
	cape: { ParticleEmitter },
	hl: Highlight,
	eyes: { BasePart },
	lastStep: number,
	folder: Folder,
	hair: { Hair },
	hairLit: boolean,
	hairHold: number, -- lit at least until then (from the Awakening until the Inferno starts)
}
-- A hair accessory set alight, and what it looked like before.
type Hair = {
	handle: BasePart,
	color: Color3,
	material: Enum.Material,
	mesh: SpecialMesh?,
	meshTex: string?,
	partTex: string?,
	surface: SurfaceAppearance?,
	flames: ParticleEmitter,
}
local looks: { [Player]: Look } = {}

-- Heart of the Inferno sets his hair on fire: every hair accessory turns to
-- glowing flame (texture off, neon, flickering) with fire licking off it,
-- and goes back to exactly how it was when the Inferno ends.
local function setHair(L: Look, lit: boolean)
	if lit == L.hairLit then return end
	L.hairLit = lit
	local head = L.char:FindFirstChild("Head")
	if lit then
		L.hair = {}
		for _, acc in ipairs(L.char:GetChildren()) do
			local h = if acc:IsA("Accessory") then acc:FindFirstChild("Handle") else nil
			if not (h and h:IsA("BasePart")) then continue end
			if acc.AccessoryType ~= Enum.AccessoryType.Hair and not h:FindFirstChild("HairAttachment") then continue end
			local mesh = h:FindFirstChildOfClass("SpecialMesh")
			local surface = h:FindFirstChildOfClass("SurfaceAppearance")
			local s: Hair = {
				handle = h, color = h.Color, material = h.Material, mesh = mesh,
				meshTex = mesh and mesh.TextureId, partTex = if h:IsA("MeshPart") then h.TextureID else nil,
				surface = surface, flames = fireEmitter(h, 0.55, 26, 2.5, 0.45),
			}
			if mesh then mesh.TextureId = "" end
			if h:IsA("MeshPart") then h.TextureID = "" end
			if surface then surface.Parent = nil end
			h.Material = Enum.Material.Neon
			h.Color = FIRE
			s.flames.Shape = Enum.ParticleEmitterShape.Box
			s.flames.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
			s.flames.SpreadAngle = Vector2.new(25, 25)
			table.insert(L.hair, s)
		end
		if head and head:IsA("BasePart") then
			ClassFX.Burst(head.Position + Vector3.new(0, 0.6, 0), EMBER, 16, 7, TEX_SPARK, 0.3, 0.6)
		end
	else
		for _, s in ipairs(L.hair) do
			s.flames:Destroy()
			if s.handle.Parent then
				s.handle.Color = s.color
				s.handle.Material = s.material
				if s.mesh and s.meshTex then s.mesh.TextureId = s.meshTex end
				if s.partTex and s.handle:IsA("MeshPart") then s.handle.TextureID = s.partTex end
				if s.surface then s.surface.Parent = s.handle end
			end
		end
		L.hair = {}
		if head and head:IsA("BasePart") and head.Parent then smokePuff(head.Position + Vector3.new(0, 0.8, 0), 6, 1.2) end
	end
end

local function dropLook(p: Player)
	local L = looks[p]
	looks[p] = nil
	if L then
		setHair(L, false)
		L.folder:Destroy()
	end
end

local function buildLook(p: Player, char: Model): Look?
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
	if not torso or not torso:IsA("BasePart") then return nil end
	local folder = Instance.new("Folder")
	folder.Name = "FireKnightLook"
	folder.Parent = char
	local L: Look = {
		char = char, handle = nil, flames = {}, aura = nil, shoulders = {}, cape = {},
		hl = Instance.new("Highlight"), eyes = {}, lastStep = 0, folder = folder,
		hair = {}, hairLit = false, hairHold = 0,
	}
	-- The armor glowing through the cracks.
	L.hl.FillColor = FIRE
	L.hl.OutlineColor = EMBER
	L.hl.FillTransparency = 1
	L.hl.OutlineTransparency = 1
	L.hl.DepthMode = Enum.HighlightDepthMode.Occluded
	L.hl.Adornee = char
	L.hl.Enabled = false
	L.hl.Parent = folder
	-- Embers drifting off the body.
	local auraAtt = Instance.new("Attachment")
	auraAtt.Parent = torso
	local aura = fireEmitter(auraAtt, 0.18, 0, 3, 1.4)
	aura.Texture = TEX_SPARK
	aura.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	aura.SpreadAngle = Vector2.new(180, 180)
	aura.Acceleration = Vector3.new(0, 5, 0)
	aura.Parent = auraAtt
	L.aura = aura
	auraAtt:SetAttribute("FK", true)
	-- Fire around the shoulders.
	for side = -1, 1, 2 do
		local a = Instance.new("Attachment")
		a.Position = Vector3.new(side * torso.Size.X * 0.45, torso.Size.Y * 0.5, 0)
		a.Parent = torso
		a:SetAttribute("FK", true)
		local e = fireEmitter(a, 0.9, 30, 3, 0.6)
		e.Enabled = false
		table.insert(L.shoulders, e)
	end
	-- Cape edges catch fire (any cape the armor has).
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and string.find(string.lower(d.Name), "cape") and #L.cape < 6 then
			local a = Instance.new("Attachment")
			a.Parent = d
			a:SetAttribute("FK", true)
			local e = fireEmitter(a, 0.5, 0, 2, 0.6)
			table.insert(L.cape, e)
		end
	end
	-- Eyes that glow in the Inferno.
	local head = char:FindFirstChild("Head")
	if head and head:IsA("BasePart") then
		for side = -1, 1, 2 do
			local eye = Instance.new("Part")
			eye.Name = "FKEye"
			eye.Shape = Enum.PartType.Ball
			eye.Size = Vector3.one * 0.16
			eye.Material = Enum.Material.Neon
			eye.Color = HOT
			eye.Transparency = 1
			eye.CanCollide, eye.CanQuery, eye.CanTouch, eye.Massless, eye.CastShadow = false, false, false, true, false
			eye.CFrame = head.CFrame * CFrame.new(side * 0.2, 0.15, -head.Size.Z * 0.5 - 0.02)
			local w = Instance.new("WeldConstraint")
			w.Part0, w.Part1 = head, eye
			w.Parent = eye
			eye.Parent = folder
			table.insert(L.eyes, eye)
		end
	end
	return L
end

-- Flames along the blade (rebuilt when the sword is re-equipped).
local function attachBlade(L: Look)
	local tool = L.char:FindFirstChild("Greatsword")
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	if handle == L.handle then return end
	L.handle = handle
	for _, e in ipairs(L.flames) do
		local a = e.Parent
		if a then a:Destroy() end
	end
	L.flames = {}
	if not handle then return end
	for _, y in ipairs({ 2.4, 3.6, 4.8, 6.0, 7.1 }) do
		local a = Instance.new("Attachment")
		a.Name = "FKFlame"
		a.Position = Vector3.new(0, y, 0)
		a.Parent = handle
		local e = fireEmitter(a, 0.4, 3, 1, 0.45)
		e.SpreadAngle = Vector2.new(180, 180)
		e.Acceleration = Vector3.new(0, 9, 0)
		table.insert(L.flames, e)
	end
end

local lookAcc = 0
local function updateLooks(dt: number)
	lookAcc += dt
	local tune = lookAcc >= 0.1
	if tune then lookAcc = 0 end
	local now = os.clock()
	for _, p in ipairs(Players:GetPlayers()) do
		local char = p.Character
		local want = char ~= nil and isFireKnight(p) and p:GetAttribute("InLobby") == false
		local L = looks[p]
		if L and (not want or L.char ~= char or not L.folder.Parent) then
			dropLook(p)
			L = nil
		end
		if want and not L and char then
			local built = buildLook(p, char)
			if built then
				looks[p] = built
				L = built
			end
		end
		if not L then continue end
		-- (soaring in the Phoenix Slam: no footprints in the air)
		if L.char:GetAttribute("FK_Phoenix") == true then continue end
		local heat = heatOf(p)
		local over = p:GetAttribute("FK_Overheat") == true
		local inferno = L.char:GetAttribute("FK_Inferno") ~= nil
		local k = heat / 100
		-- Burning hair through the whole Inferno (white-hot when Primordial).
		setHair(L, inferno or now < L.hairHold)
		if L.hairLit then
			local tier = L.char:GetAttribute("FK_Inferno")
			-- (neon glows brighter than its colour: deep ember → flame reads as fire, not white)
			local a, b = if tier == 3 then FIRE else DEEP, if tier == 3 then HOT else FIRE
			for i, s in ipairs(L.hair) do
				s.handle.Color = a:Lerp(b, 0.5 + 0.5 * math.sin(now * 11 + i * 1.7))
			end
		end
		if tune then
			attachBlade(L)
			-- The sword's flames grow with Heat; the whole blade burns at 100.
			local size = if inferno then 1.5 elseif over then 1.1 else 0.3 + 0.5 * k
			local rate = if inferno then 55 elseif over then 40 else 2 + 20 * k
			for _, e in ipairs(L.flames) do
				e.Rate = rate
				e.Size = NumberSequence.new({ nsk(0, size), nsk(1, size * 0.15) })
			end
			if L.aura then
				L.aura.Rate = if inferno then 40 elseif over then 24 elseif heat >= 25 then (heat - 25) / 75 * 10 else 0
			end
			for _, e in ipairs(L.shoulders) do e.Enabled = over or inferno end
			for _, e in ipairs(L.cape) do
				e.Rate = if over or inferno then 18 elseif heat >= 50 then 4 else 0
				e.Texture = if over or inferno then FireFX.TEX.flame else TEX_SMOKE
				e.FlipbookLayout = if over or inferno then Enum.ParticleFlipbookLayout.Grid4x4 else Enum.ParticleFlipbookLayout.None
			end
			-- Glow through the armor from 50 Heat, full at Overheat.
			local glow = if inferno then 1 elseif over then 0.8 + 0.2 * math.sin(now * 8) else math.clamp((heat - 50) / 50, 0, 1) * 0.55
			L.hl.Enabled = glow > 0.02
			L.hl.FillColor = if inferno then HOT else FIRE
			L.hl.FillTransparency = 1 - glow * (if inferno then 0.55 else 0.4)
			L.hl.OutlineTransparency = 1 - glow * 0.85
			for _, eye in ipairs(L.eyes) do eye.Transparency = if inferno or over then 0 else 1 end
			-- Hotter attack trails.
			local tool = L.char:FindFirstChild("Greatsword")
			local tr = tool and tool:FindFirstChild("SlashTrail", true)
			if tr and tr:IsA("Trail") then
				local w = 1.2 + k * 0.8 + (if over or inferno then 0.8 else 0)
				tr.WidthScale = NumberSequence.new({ nsk(0, w), nsk(0.65, w * 0.8), nsk(1, 0.2) })
				tr.Lifetime = if over or inferno then 0.8 else 0.5 + k * 0.2
			end
		end
		-- Footsteps leave embers from 50 Heat; burning footprints at 100.
		local root = rootOf(L.char)
		local hum = L.char:FindFirstChildOfClass("Humanoid")
		if root and hum and (heat >= 50 or over or inferno) and hum.MoveDirection.Magnitude > 0.1
			and now - L.lastStep > (if over or inferno then 0.2 else 0.3) then
			L.lastStep = now
			local foot = root.Position - Vector3.new(0, 2.8, 0)
			ClassFX.Burst(foot, EMBER, if over or inferno then 8 else 4, 5, TEX_SPARK, 0.22, 0.5)
			if over or inferno then
				-- burning footprints: a little flame left where he stepped
				local g = onGround(root.Position)
				FireFX.Puff("flame", CFrame.new(g + Vector3.new(0, 0.35, 0)), 1.2, 1, function(e)
					e.EmissionDirection = Enum.NormalId.Top
					e.Speed = NumberRange.new(1, 2)
					e.Lifetime = NumberRange.new(0.7, 0.9)
				end)
			end
		end
	end
	for p in pairs(looks) do
		if not p.Parent then dropLook(p) end
	end
end

-- ── Scorch on enemies ───────────────────────────────────────────────────────
type ScorchFx = { bb: BillboardGui, pips: { Frame }, flame: ParticleEmitter, anchor: Attachment }
local scorched: { [Model]: ScorchFx } = {}

local function dropScorch(m: Model)
	local s = scorched[m]
	scorched[m] = nil
	if s then
		s.bb:Destroy()
		s.anchor:Destroy()
	end
end

local scorchAcc = 0
local function updateScorch(dt: number)
	scorchAcc += dt
	if scorchAcc < 0.2 then return end
	scorchAcc = 0
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then
		for _, m in ipairs(mobs:GetChildren()) do
			if not m:IsA("Model") then continue end
			local stacks = tonumber(m:GetAttribute("FK_Scorch")) or 0
			local s = scorched[m]
			if stacks <= 0 then
				if s then dropScorch(m) end
				continue
			end
			local root = (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart) :: BasePart?
			if not root then continue end
			if not s then
				local anchor = Instance.new("Attachment")
				anchor.Parent = root
				local flame = fireEmitter(anchor, 0.7, 0, 2, 0.6)
				flame.SpreadAngle = Vector2.new(60, 60)
				local bb = Instance.new("BillboardGui")
				bb.Adornee = root
				bb.Size = UDim2.fromOffset(70, 10)
				bb.StudsOffset = Vector3.new(0, 3.6, 0)
				bb.AlwaysOnTop = true
				bb.LightInfluence = 0
				bb.MaxDistance = 120
				bb.Parent = ClassFX.Folder()
				local pips = {}
				for i = 1, 5 do
					local d = Instance.new("Frame")
					d.AnchorPoint = Vector2.new(0.5, 0.5)
					d.Position = UDim2.new(0, (i - 0.5) * 14, 0.5, 0)
					d.Size = UDim2.fromOffset(8, 8)
					d.Rotation = 45
					d.BorderSizePixel = 0
					d.Parent = bb
					pips[i] = d
				end
				s = { bb = bb, pips = pips, flame = flame, anchor = anchor }
				scorched[m] = s
			end
			local sfx = s :: ScorchFx
			sfx.flame.Rate = stacks * 6
			for i, d in ipairs(sfx.pips) do
				d.BackgroundColor3 = if i <= stacks then (if stacks >= 4 then HOT else FIRE) else Color3.fromRGB(40, 22, 16)
				d.BackgroundTransparency = if i <= stacks then 0 else 0.4
			end
		end
	end
	for m in pairs(scorched) do
		if not m.Parent then dropScorch(m) end
	end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

function FireKnightController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
		* (if char:GetAttribute("FK_Inferno") ~= nil then 1.25 else 1)
	if now - lastSwing < SWING_INTERVAL / speed then return true end
	localStep = if now - lastSwing > COMBO_RESET then 1 else (localStep % 4) + 1
	lastSwing = now
	local dir = flat(deps.getAim(root))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	swingPose(char, localStep)
	comboVFX(char, player, localStep, dir)
	ClassFX.Sound("whoosh", root, 0.65, if localStep == 4 then 0.7 else 0.85 + localStep * 0.04)
	ClassFX.Sound("fireWhoosh", root, 0.35, 1.1)
	-- Feet planted for the swing (the greatsword is too heavy to swing on
	-- the move); each strike steps into the hit.
	local step = localStep
	local hitAt = COMBO_HIT[step]
	rootToken += 1
	local token = rootToken
	char:SetAttribute("Rooted", true)
	task.delay(hitAt + (if step == 4 then 0.3 else 0.2), function()
		if rootToken == token and char.Parent then char:SetAttribute("Rooted", nil) end
	end)
	if step == 4 then busyUntil = now + EXECUTION_WINDUP + 0.15 end
	task.delay(hitAt - 0.03, function()
		if root.Parent then
			local push = ({ 10, 12, 22, 18 })[step]
			root.AssemblyLinearVelocity = dir * push + Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── The Phoenix Slam ────────────────────────────────────────────────────────
-- On every client: a Fire Knight flying the Phoenix Slam (his character's
-- FK_Phoenix set) soars on great wings of flame, a crown of fire over his
-- head, wreathed in fire, shedding burning feathers.
type Flight = { char: Model, wings: FireFX.Wings?, crownOff: (() -> ())?, auraOff: () -> (), diving: boolean }
local flights: { [Model]: Flight } = {}

-- Hovering on the wings, the sword hanging point-down in his hand.
local function hoverPose(char: Model, seconds: number)
	gripTo(char, 2, 0.25)
	local p = pose(4, 0, -6, 24, 28, 12, 34, -12, { N = { -8, 0, 0 } }, 4)
	CastPoses.play(char, {
		{ dur = 0.25, style = QUAD, pose = p },
		{ dur = math.max(seconds - 0.25, 0.05), pose = p, wobble = function(t)
			local b = math.sin(t * 4) * 3
			return { RH = { b, 0, 0 }, LH = { b * 0.6, 0, 0 }, N = { b * 0.3, 0, 0 } }
		end },
	}, 0.2, true)
end

-- Diving: the sword up over his head in both hands, to drive it down.
local function divePose(char: Model, dur: number)
	gripTo(char, 1, 0.08)
	CastPoses.play(char, {
		{ dur = 0.1, style = QUAD, pose = pose(10, 0, 10, 10, 175, 0, 172, 0, { N = { 14, 0, 0 } }) },
		{ dur = math.max(dur, 0.05), pose = pose(-6, 0, 14, 14, 178, 0, 176, 0, { N = { 10, 0, 0 } }) },
	}, 0.1, true)
end

local function startFlight(char: Model)
	if flights[char] then return end
	local root = rootOf(char)
	if not root then return end
	local f: Flight = {
		char = char,
		wings = FireFX.Wings(char, 1),
		crownOff = FireFX.Crown(char),
		auraOff = FireFX.Aura(char),
		diving = false,
	}
	flights[char] = f
	hoverPose(char, PHOENIX_RISE + PHOENIX_AIM)
	-- He bursts into flame as the wings unfurl: a ring of fire round his feet
	-- and a column of it lifting him.
	local g = onGround(root.Position)
	FireFX.FlameRing(g, 4.5, 4)
	FireFX.Column(g, 12, 2.6)
	FireFX.Flames(root.Position, 3.5, 6, 1.4)
	FireFX.FeatherBurst(root.Position + Vector3.new(0, 1, 0), 14, 12)
	FireFX.Shockwave(g, 7)
	ClassFX.Sound("fireWhoosh", root, 1, 0.7)
	ClassFX.Sound("fireBurst", root, 0.7, 0.9)
end

local function endFlight(char: Model)
	local f = flights[char]
	if not f then return end
	flights[char] = nil
	if f.wings then f.wings.fade(0.18) end
	if f.crownOff then f.crownOff() end
	f.auraOff()
	local root = rootOf(char)
	-- the wings burst into feathers as he lands
	if root then FireFX.FeatherBurst(root.Position + Vector3.new(0, 2, 0), 26, 22) end
end

-- Where the cursor points on the floor (the marker), ignoring characters,
-- mobs and effects; else on the take-off's floor height.
local cursorParams = RaycastParams.new()
cursorParams.FilterType = Enum.RaycastFilterType.Exclude
local function cursorGround(floorY: number): Vector3
	local cam = Workspace.CurrentCamera
	local m = UserInputService:GetMouseLocation()
	local ray = cam:ViewportPointToRay(m.X, m.Y)
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(ignore, p.Character) end
	end
	for _, n in ipairs({ "Mobs", "Allies", "IceClones", "BossFX", "MobFX", "RoomEmblems" }) do
		local fo = Workspace:FindFirstChild(n)
		if fo then table.insert(ignore, fo) end
	end
	cursorParams.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(ray.Origin, ray.Direction * 600, cursorParams)
	if hit and hit.Normal.Y > 0.5 and math.abs(hit.Position.Y - floorY) < 12 then return hit.Position end
	if math.abs(ray.Direction.Y) > 0.001 then
		local t = (floorY - ray.Origin.Y) / ray.Direction.Y
		if t > 0 then return ray.Origin + ray.Direction * t end
	end
	return Vector3.new(ray.Origin.X, floorY, ray.Origin.Z)
end

-- A beam of light from the knight down to the heart of the sigil.
local function lightThread(root: BasePart): (Attachment, () -> ())
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, -1.5, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Parent = Workspace.Terrain
	local function beam(w: number, c0: Color3, c1: Color3, tr: number): Beam
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Brightness = 1.5
		b.Width0, b.Width1 = w, w * 0.6
		b.Color = ColorSequence.new(c0, c1)
		b.Transparency = NumberSequence.new(tr)
		b.Parent = a0
		return b
	end
	beam(1.6, Color3.fromRGB(255, 110, 35), Color3.fromRGB(255, 140, 50), 0.6)
	beam(0.3, Color3.fromRGB(255, 200, 110), Color3.fromRGB(255, 170, 80), 0.1)
	-- sparks where it meets the floor
	local star = FireFX.Emitter("embers", a1, 0.35)
	star.Rate = 18
	star.Speed = NumberRange.new(1, 3)
	return a1, function()
		a0:Destroy()
		star.Enabled = false
		Debris:AddItem(a1, 1.3)
		for _, c in ipairs(a1:GetChildren()) do
			if c:IsA("Beam") then c:Destroy() end
		end
	end
end

-- The caster's own flight: rise, hold the marker under the cursor, dive.
local aiming: { confirm: () -> () }? = nil

local function phoenixFlight(char: Model, root: BasePart, dir: Vector3, config: any, hot: boolean)
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local area = config.areaMultiplier or 1
	local range = (config.range or 40) * area
	local radius = 11 * area * (if hot then 1.35 else 1)
	busyUntil = os.clock() + PHOENIX_RISE + PHOENIX_AIM + PHOENIX_DIVE + 0.6
	char:SetAttribute("IsSkillCasting", true)
	char:SetAttribute("AllowSkillMovement", false)
	hum.AutoRotate = false
	local origin = root.Position
	local stand = SafeMove.StandHeight(root)
	local floorY = origin.Y - stand
	-- Held up by movers (they replicate; an anchored root wouldn't).
	local att = Instance.new("Attachment")
	att.Name = "PhoenixFlight"
	att.Parent = root
	local ap = Instance.new("AlignPosition")
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.RigidityEnabled = true
	ap.Position = origin
	ap.Parent = root
	local ao = Instance.new("AlignOrientation")
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.RigidityEnabled = true
	ao.CFrame = CFrame.lookAt(Vector3.zero, dir)
	ao.Parent = root
	hum.PlatformStand = true
	startFlight(char)

	local sigil = FireFX.Sigil(radius)
	local threadEnd, dropThread = lightThread(root)
	local target = Vector3.new(origin.X, floorY, origin.Z) + dir * 16
	local phase = "rise"
	local t0 = os.clock()
	local aimT0 = 0
	local diveFrom, diveTo, diveT0 = origin, origin, 0
	local confirmed = false
	-- (not the very press that cast it)
	aiming = { confirm = function() if os.clock() - t0 > 0.25 then confirmed = true end end }
	local conn: RBXScriptConnection? = nil

	local function face(toward: Vector3)
		local d = Vector3.new(toward.X - root.Position.X, 0, toward.Z - root.Position.Z)
		if d.Magnitude > 0.5 then ao.CFrame = CFrame.lookAt(Vector3.zero, d.Unit) end
	end

	local function finish()
		if conn then conn:Disconnect() end
		aiming = nil
		sigil.destroy(0.25)
		dropThread()
		ap:Destroy()
		ao:Destroy()
		att:Destroy()
		if hum.Parent then hum.PlatformStand = false end
		if root.Parent then
			local look = flat(diveTo - diveFrom)
			root.AssemblyLinearVelocity = Vector3.zero
			root.CFrame = CFrame.lookAt(diveTo, diveTo + look)
			SafeMove.SnapToFloor(root, stand)
		end
		endFlight(char)
		hum.AutoRotate = true
		busyUntil = os.clock() + 0.3
		releaseAfter(char, 0.3)
	end

	conn = RunService.RenderStepped:Connect(function()
		if not root.Parent or hum.Health <= 0 then
			finish()
			return
		end
		local now = os.clock()
		if phase ~= "dive" then
			-- the sigil follows the cursor, within range of the take-off
			local c = cursorGround(floorY)
			local d = Vector3.new(c.X - origin.X, 0, c.Z - origin.Z)
			if d.Magnitude > range then d = d.Unit * range end
			target = Vector3.new(origin.X + d.X, c.Y, origin.Z + d.Z)
			sigil.move(target)
			threadEnd.WorldPosition = target + Vector3.new(0, 0.3, 0)
			face(target)
		end
		if phase == "rise" then
			local a = math.min((now - t0) / PHOENIX_RISE, 1)
			ap.Position = origin + Vector3.new(0, PHOENIX_HEIGHT * (1 - (1 - a) ^ 3), 0)
			if a >= 1 then
				phase = "aim"
				aimT0 = now
			end
		elseif phase == "aim" then
			ap.Position = origin + Vector3.new(0, PHOENIX_HEIGHT + math.sin((now - aimT0) * 3) * 0.6, 0)
			if confirmed or now - aimT0 >= PHOENIX_AIM then
				phase = "dive"
				diveFrom = root.Position
				diveTo = Vector3.new(target.X, target.Y + stand, target.Z)
				diveT0 = now
				sigil.lock()
				face(target)
				Network.GetRemoteEvent(Network.Remotes.FireKnightAim):FireServer({ target = target })
				local f = flights[char]
				if f then
					f.diving = true
					if f.wings then
						f.wings.sweep(1)
						f.wings.beat(0.3)
					end
				end
				divePose(char, PHOENIX_DIVE)
				ClassFX.Sound("fireWhoosh", root, 1, 0.6)
			end
		elseif phase == "dive" then
			local a = math.min((now - diveT0) / PHOENIX_DIVE, 1)
			ap.Position = diveFrom:Lerp(diveTo, a * a)
			if a >= 1 then finish() end
		end
	end)
	ClassFX.Sound("charge", root, 0.5, 1.2)
	deps.shake(0.4, 0.2)
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function FireKnightController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

-- A mob close in front (a plain charge stops just after meeting one).
local function enemyAhead(root: BasePart, dir: Vector3, reach: number): boolean
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return false end
	local p = root.Position + dir * 1.5
	for _, m in ipairs(mobs:GetChildren()) do
		if not m:IsA("Model") then continue end
		local r = (m:FindFirstChild("HumanoidRootPart") or m.PrimaryPart) :: BasePart?
		local h = m:FindFirstChildOfClass("Humanoid")
		if r and h and h.Health > 0 then
			local d = r.Position - p
			if Vector3.new(d.X, 0, d.Z).Magnitude < reach and math.abs(d.Y) < 6 then return true end
		end
	end
	return false
end

local function chargeMove(root: BasePart, dir: Vector3, dist: number, dur: number, plows: boolean)
	local stand = SafeMove.StandHeight(root)
	dist = SafeMove.ClampDash(root, dir, dist)
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	lv.VectorVelocity = dir * (dist / dur)
	lv.Parent = root
	local t0 = os.clock()
	local contactAt: number? = nil
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if not plows and not contactAt and enemyAhead(root, dir, 4.5) then contactAt = now end
		if now - t0 >= dur or (contactAt and now - contactAt > 0.12) or not root.Parent then
			if conn then conn:Disconnect() end
			lv:Destroy()
			att:Destroy()
			if root.Parent then
				root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
				SafeMove.SnapToFloor(root, stand)
			end
		end
	end)
end

function FireKnightController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any)
	local dir = flat(aimDir)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local now = os.clock()
	local hot = empowered(player)
	char:SetAttribute("AllowSkillMovement", false)
	if skillIndex == 1 then
		-- Blazing Charge: ignite, then drive forward.
		local dur = if hot then 0.5 else 0.38
		local dist = (config.dashDistance or 22) * (if hot then 1.45 else 1)
		busyUntil = now + CHARGE_WINDUP + dur + 0.4
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum then hum.AutoRotate = false end
		chargePose(char, CHARGE_WINDUP, dur)
		task.delay(CHARGE_WINDUP, chargeMove, root, dir, dist, dur, hot)
		releaseAfter(char, CHARGE_WINDUP + dur + 0.3)
		task.delay(CHARGE_WINDUP + dur + 0.3, function() if hum then hum.AutoRotate = true end end)
	elseif skillIndex == 2 then
		-- Phoenix Slam: up into the air as the phoenix; the marker picks
		-- where it dives.
		phoenixFlight(char, root, dir, config, hot)
	elseif skillIndex == 3 then
		-- Infernal Earthshaker.
		busyUntil = now + QUAKE_WINDUP + 0.45
		quakePose(char, QUAKE_WINDUP)
		releaseAfter(char, QUAKE_WINDUP + 0.4)
	elseif skillIndex == 4 then
		-- Heart of the Inferno: the Awakening close-up.
		busyUntil = now + AWAKEN + 0.2
		FireKnightController.PlayUltCutscene(char, dir)
		releaseAfter(char, AWAKEN + 0.25)
	end
end

-- The Awakening close-up (for the caster and everyone watching).
function FireKnightController.PlayUltCutscene(char: Model, dir: Vector3)
	UltimateCameraChoreography.PlayCloseUp(char, dir, AWAKEN, nil, nil, {
		startOffset = { 8, 1.5, 1.4 },
		endOffset = { 5.5, 1.1, 0.9 },
		focusHeight = 1.4,
		fovStart = 50,
		fovEnd = 40,
	})
end

-- ── Server moments (FireKnightFX) ───────────────────────────────────────────
local function onCombo(msg: any)
	if msg.attacker == player then return end -- ours was predicted on click
	local char = charOf(msg.attacker)
	if not char then return end
	swingPose(char, msg.step)
	comboVFX(char, msg.attacker, msg.step, msg.dir)
	local root = rootOf(char)
	if root then ClassFX.Sound("whoosh", root, 0.5, 0.9) end
end

local function onCharge(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then chargePose(char, msg.windup, msg.dur) end
	-- The whole body ignites, then a trail of fire along the ground behind
	-- the charge (a flaming bull rush when Empowered).
	FireFX.Flames(root.Position, 3.2, 7, 1.4)
	FireFX.Puff("embers", CFrame.new(root.Position), 0.35, 20)
	ClassFX.Sound("fireWhoosh", root, 0.8, 0.8)
	ClassFX.Sound("charge", root, 0.4, 1.3)
	local hl = Instance.new("Highlight")
	hl.FillColor = FIRE
	hl.FillTransparency = 0.45
	hl.OutlineColor = HOT
	hl.Adornee = char
	hl.Parent = ClassFX.Folder()
	Debris:AddItem(hl, msg.windup + msg.dur + 0.1)
	local big = msg.empowered == true
	task.delay(msg.windup, function()
		local t0 = os.clock()
		local last = root.Position
		while os.clock() - t0 < msg.dur and root.Parent do
			task.wait(0.03)
			local p = root.Position
			if (p - last).Magnitude > 1.4 then
				SwordFX.Streak(last + Vector3.new(0, 0.5, 0), p + Vector3.new(0, 0.5, 0), if big then 2 else 1.2, FIRE, 0.2)
				local g = onGround(p)
				FireFX.Puff("roll", CFrame.new(g + Vector3.new(0, 1, 0)), if big then 3.6 else 2.6, 1, function(e)
					e.EmissionDirection = Enum.NormalId.Top
					e.Speed = NumberRange.new(2, 5)
				end)
				FireFX.Puff("lick", CFrame.new(g + Vector3.new(0, 0.8, 0)), 0.9, if big then 5 else 3)
				-- the body wrapped in flame as he goes
				FireFX.Puff("flame", CFrame.new(p), if big then 3 else 2.2, 1, nil, Vector3.new(1.5, 3, 1.5))
				last = p
			end
		end
		if big then ClassFX.Afterimages(char, FIRE, 4, 0.06) end
	end)
end

local function onRise(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	if char then
		risePose(char)
		trail(char, 0.35)
	end
	-- The upward slash rips a column of fire out of the ground.
	local base = CFrame.lookAt(pos + Vector3.new(0, 1, 0), pos + Vector3.new(0, 1, 0) + dir)
	crescent(base * CFrame.Angles(0, 0, math.rad(-80)), if msg.empowered then 8 else 6.5, 170, 1.6, 0.3, -1,
		if msg.empowered then HOT else FIRE)
	eruption(pos + dir * 4, if msg.empowered then 16 else 11, if msg.empowered then 3 else 2.2)
	FireFX.Puff("lick", CFrame.new(pos + dir * 4 + Vector3.new(0, 2, 0)), 1, 16)
	ClassFX.Sound("swordHit", pos, 0.9, 0.8)
	if msg.attacker == player then deps.shake(0.7, 0.18) end
end

-- ── Phoenix Slam (every client) ──
local function onPhoenixRise(msg: any)
	local char = charOf(msg.attacker)
	if not char or msg.attacker == player then return end -- the caster flies their own
	startFlight(char)
end

local function onPhoenixDive(msg: any)
	local char = charOf(msg.attacker)
	if not char then return end
	local f = flights[char]
	if msg.attacker ~= player then
		if f and f.wings then
			f.wings.sweep(1)
			f.wings.beat(0.3)
		end
		divePose(char, msg.dur)
		-- everyone sees where he's coming down
		local mark = FireFX.Sigil(msg.radius or 11)
		mark.move(onGround(msg.to))
		mark.lock()
		task.delay(msg.dur + 0.1, mark.destroy, 0.3)
	end
	local root = rootOf(char)
	if root then
		SwordFX.Streak(root.Position, msg.to + Vector3.new(0, 1, 0), 3, FIRE, 0.35, 3, HOT)
		ClassFX.Sound("fireWhoosh", root, 0.8, 0.55)
	end
end

local function onPhoenixImpact(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	local r = msg.radius :: number
	local big = msg.empowered == true
	if char then
		endFlight(char)
		-- landed in a crouch, the sword driven into the ground
		quakePose(char, 0.02)
	end
	local g = onGround(pos)
	-- The crash: a pillar of light and fire where the sword went in, the
	-- explosion, fire tearing out through the floor, rock thrown up, burning
	-- feathers everywhere, a wall of flame racing out, and the sigil burnt
	-- into the ground for a moment.
	FireFX.LightPillar(g, if big then 48 else 36, r * 0.32, 0.7)
	explosion(g + Vector3.new(0, 1.5, 0), r * 0.75, true)
	FireFX.Fissures(g, r * 1.15, if big then 3 else 2.2)
	FireFX.Rocks(g, if big then 16 else 11, 24)
	FireFX.FeatherBurst(g + Vector3.new(0, 2, 0), if big then 40 else 26, 26)
	task.delay(0.05, FireFX.FlameRing, g, r * 0.9, if big then 7 else 5)
	local scar = FireFX.Sigil(r)
	scar.move(g)
	scar.lock()
	task.delay(if big then 1.2 else 0.7, scar.destroy, 0.6)
	ClassFX.Sound("boom", g, 1, 0.85)
	ClassFX.Sound("fireBurst", g, 1, 0.7)
	ClassFX.Sound("rockHit", g, 0.9, 0.8)
	if near(pos, 110) then deps.shake(if msg.attacker == player then 1.5 else 0.6, 0.4) end
	if msg.attacker == player then deps.fovPunch(10, 0.3) end
end

local function onFlares(msg: any)
	-- Overheated: flares going off all round the impact.
	for i, p in ipairs(msg.points or {}) do
		task.delay(0.15 + i * 0.07, function()
			local g = onGround(p)
			explosion(g + Vector3.new(0, 1, 0), (msg.radius or 5) * 0.8, false)
			eruption(g, 9, 1.8)
		end)
	end
end

local function onQuake(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	if msg.attacker ~= player then quakePose(char, msg.windup) end
	-- The ground cracks under him, flame pushing up through it; the blade
	-- catches fire as he lifts it.
	cracks(root.Position, msg.radius * 0.8, msg.windup, 0.5)
	ClassFX.Sound("rockHit", root, 0.7, 0.7)
	ClassFX.Sound("charge", root, 0.5, 0.9)
	local tip = bladeTip(char)
	if tip then FireFX.Flames(tip, 2.4, 4, 0.6) end
end

local function onQuakeHit(msg: any)
	local pos = msg.pos :: Vector3
	local r = msg.radius :: number
	-- BOOM: a giant explosion, a wall of fire racing out to the edge of it.
	local g = onGround(pos)
	explosion(g + Vector3.new(0, 1, 0), r * 0.75, true)
	eruption(g, 20, r * 0.25)
	FireFX.FlameRing(g, r * 0.55, 5)
	task.delay(0.08, FireFX.FlameRing, g, r, 6)
	FireFX.Cracks(g, r * 1.05, 2.6, false)
	ClassFX.Sound("quake", pos, 0.9, 1.1, 1.5)
	if near(pos, 90) then deps.shake(if msg.attacker == player then 1.4 else 0.6, 0.35) end
	if msg.attacker == player then deps.fovPunch(8, 0.3) end
end

local function onAftershocks(msg: any)
	for i, p in ipairs(msg.points or {}) do
		task.delay(0.12 + i * 0.05, function()
			local g = onGround(p)
			explosion(g + Vector3.new(0, 0.8, 0), msg.radius * 0.7, false)
			eruption(g, 8, 1.6)
		end)
	end
end

local function onRings(msg: any)
	local pos = msg.pos :: Vector3
	local g = onGround(pos)
	explosion(g + Vector3.new(0, 1, 0), 7, true)
	eruption(g, 24, 3.5)
	ClassFX.Sound("quake", pos, 0.9, 1, 1.5)
	-- THREE RINGS OF FIRE expanding outward: walls of flame, each further out.
	for i, r in ipairs(msg.radii or {}) do
		task.delay((i - 1) * (msg.gap or 0.28), function()
			FireFX.FlameRing(g, r, 7 + i)
			FireFX.Cracks(g, r, 2.2, false)
			ClassFX.Sound("fireBurst", pos, 0.7, 0.9 - i * 0.05)
			if near(pos, 90) then deps.shake(if msg.attacker == player then 0.9 else 0.4, 0.25) end
		end)
	end
end

local function onPatch(msg: any)
	patch(msg.pos, msg.radius, msg.life)
end

local function onIgnite(msg: any)
	local pos = msg.pos :: Vector3
	explosion(pos, msg.radius * 0.55, false)
	FireFX.Flames(pos, 3, 5, 1)
end

local function onBlast(msg: any)
	explosion(msg.pos, msg.radius * 0.6, false)
end

local function onOverheat(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	-- The flare: he bursts into flame and a jet of fire goes up off him.
	FireFX.Flames(root.Position, 4.5, 10, 2)
	FireFX.Puff("embers", CFrame.new(root.Position), 0.45, 40)
	eruption(root.Position, 18, 3)
	FireFX.Shockwave(root.Position, 9)
	ClassFX.Sound("fireBurst", root, 1, 0.8)
	popWord(char, "OVERHEAT", HOT, 32)
	if msg.attacker == player then deps.shake(0.6, 0.2) end
end

local function onCooldown(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	-- Heat crashes: a hiss of steam off the armor.
	smokePuff(root.Position + Vector3.new(0, 1, 0), 18, 3)
	ClassFX.Sound("wind", root, 0.4, 1.4, 0.8)
end

-- The arena darkens; the knight is the brightest thing on screen.
local function darken(seconds: number)
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "InfernoDark"
	cc.Parent = Lighting
	TweenService:Create(cc, TweenInfo.new(0.4), { Brightness = -0.2, Saturation = -0.25, Contrast = 0.2,
		TintColor = Color3.fromRGB(255, 225, 205) }):Play()
	task.delay(seconds, function()
		TweenService:Create(cc, TweenInfo.new(0.6), { Brightness = 0, Saturation = 0, Contrast = 0, TintColor = WHITE }):Play()
		Debris:AddItem(cc, 0.65)
	end)
end

-- Halfway up the blade (the planted sword, during the Awakening).
local function bladeMid(char: Model): Vector3?
	local tool = char:FindFirstChild("Greatsword")
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	if not handle then return nil end
	return (handle.CFrame * CFrame.new(0, 3.5, 0)).Position
end

local function onAwaken(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local awaken = msg.awaken :: number
	-- He plants the sword; the flames go out; silence...
	plantSword(char, awaken)
	if near(root.Position, 110) then darken(awaken + (msg.inferno or 6) + 1) end
	for _, L in pairs(looks) do
		if L.char == char then
			for _, e in ipairs(L.flames) do e.Enabled = false end
			task.delay(awaken, function() for _, e in ipairs(L.flames) do e.Enabled = true end end)
			-- His hair catches fire as the armor starts to glow (and stays lit
			-- until the Inferno it's heralding is over).
			task.delay(awaken * 0.55, function()
				L.hairHold = os.clock() + awaken * 0.45 + 1
				setHair(L, true)
			end)
		end
	end
	local feet = onGround(root.Position)
	local tier = msg.tier or 1
	-- ...then the flames come back to him: little fires kindle all round on
	-- the floor and are drawn in to the planted blade...
	task.delay(awaken * 0.15, function()
		local n = 8 + tier * 3
		for i = 1, n do
			local a = i / n * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
			local d = rng:NextNumber(8, 14 + tier * 2)
			local from = onGround(feet + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d)) + Vector3.new(0, 0.6, 0)
			task.delay(i * awaken * 0.035, function()
				FireFX.Puff("flame", CFrame.new(from), 1.6, 2, function(e) e.EmissionDirection = Enum.NormalId.Top end)
				FireFX.Homing(from, function() return bladeMid(char) end, awaken * 0.35, 1.3)
			end)
		end
	end)
	-- ...the armor glows, the ground splits, a wall of fire rises round him
	-- and the screen starts to shake.
	task.delay(awaken * 0.35, function()
		if not root.Parent then return end
		local hl = Instance.new("Highlight")
		hl.FillColor = FIRE
		hl.FillTransparency = 1
		hl.OutlineColor = HOT
		hl.OutlineTransparency = 1
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Adornee = char
		hl.Parent = ClassFX.Folder()
		TweenService:Create(hl, TweenInfo.new(awaken * 0.6), { FillTransparency = 0.4, OutlineTransparency = 0 }):Play()
		Debris:AddItem(hl, awaken * 0.65 + 0.3)
		cracks(root.Position, 9 + tier, awaken * 0.5, 0.4)
		ClassFX.Sound("charge", root, 0.8, 0.7)
		if msg.attacker == player then deps.shake(0.35, awaken * 0.6) end
	end)
	task.delay(awaken * 0.7, function()
		FireFX.FlameRing(feet, 6 + tier, 3 + tier)
	end)
end

local function onPillar(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	local r = msg.radius :: number
	local g = onGround(pos)
	-- He pulls the sword from the ground: a massive pillar of fire.
	if char then raisePose(char, 0.5) end
	eruption(g, 46, r * 0.4)
	eruption(g, 30, r * 0.65)
	explosion(g + Vector3.new(0, 2, 0), r * 0.7, true)
	FireFX.FlameRing(g, r * 0.9, 8)
	for i = 1, 10 do
		task.delay(i * 0.03, FireFX.Flames, g + Vector3.new(0, i * 3.5, 0), 4, 3, 1.2)
	end
	ClassFX.Sound("boom", pos, 1, 0.8)
	ClassFX.Sound("fireBurst", pos, 1, 0.7)
	if near(pos, 110) then deps.shake(if msg.attacker == player then 1.5 else 0.7, 0.4) end
	if msg.attacker == player then deps.fovPunch(10, 0.4) end
	if char and msg.tier and msg.tier >= 3 then popWord(char, "PRIMORDIAL INFERNO", HOT, 26) end
end

local function onGather(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local delay = msg.delay :: number
	-- He raises the sword, and every flame in the arena leaves where it's
	-- burning and flies to it, following the blade wherever it moves, each
	-- one swallowed by it in a flash.
	raisePose(char, delay + 0.1)
	if msg.attacker == player then
		char:SetAttribute("IsSkillCasting", true)
		char:SetAttribute("AllowSkillMovement", false)
		busyUntil = os.clock() + delay + 0.5
		releaseAfter(char, delay + 0.45)
	end
	local function tip(): Vector3?
		return bladeTip(char)
	end
	-- The burning ground goes out as its fire lifts off.
	for _, b in ipairs(patchFx) do b.stop() end
	table.clear(patchFx)
	local list: { Vector3 } = {}
	for _, src in ipairs(msg.sources or {}) do table.insert(list, src) end
	-- (and fire kindling all round him, so it's never just a few)
	local tier = msg.tier or 1
	local want = 16 + tier * 4
	while #list < want do
		local a = rng:NextNumber(0, math.pi * 2)
		local d = rng:NextNumber(7, 24)
		table.insert(list, root.Position + Vector3.new(math.cos(a) * d, 0, math.sin(a) * d))
	end
	-- The sword's glow, swelling with every flame it swallows.
	local glow = neon({ Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, Color = HOT, Transparency = 0.15 })
	local swallowed = 0
	local glowConn = RunService.RenderStepped:Connect(function()
		local p = tip()
		if p then glow.CFrame = CFrame.new(p) end
		local s = 0.8 + math.min(swallowed, 40) * 0.11
		glow.Size = glow.Size:Lerp(Vector3.one * s, 0.25)
	end)
	task.delay(delay + 0.05, function()
		glowConn:Disconnect()
		TweenService:Create(glow, TweenInfo.new(0.15), { Size = Vector3.one * 7, Transparency = 1, Color = WHITE }):Play()
		Debris:AddItem(glow, 0.2)
	end)
	local n = #list
	local window = math.max(delay - 0.85, 0.3)
	for i, src in ipairs(list) do
		local start = (i - 1) / n * window
		task.delay(start, function()
			local from = onGround(src) + Vector3.new(0, 1, 0)
			FireFX.Puff("flame", CFrame.new(from), 2.2, 2, function(e) e.EmissionDirection = Enum.NormalId.Top end)
			FireFX.Homing(from, tip, rng:NextNumber(0.55, 0.75), rng:NextNumber(1.6, 2.4), function(at)
				swallowed += 1
				FireFX.Puff("lick", CFrame.new(at), 0.7, 5)
				FireFX.Puff("embers", CFrame.new(at), 0.25, 6)
			end)
		end)
	end
	ClassFX.Sound("charge", root, 0.9, 0.8)
	ClassFX.Sound("fireWhoosh", root, 0.7, 0.6)
end

local function onExecution(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local length, width = msg.length :: number, msg.width :: number
	if char then
		-- Turn into the wave (the server aims it down the busiest line).
		local root = rootOf(char)
		if root and msg.attacker == player then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
		end
		slamPose(char)
		trail(char, 0.4)
	end
	-- One enormous downward slash, then a gigantic wave of fire tearing
	-- across the arena, the floor splitting under it.
	local base = CFrame.lookAt(pos + Vector3.new(0, 1.5, 0), pos + Vector3.new(0, 1.5, 0) + dir)
	crescent(base * CFrame.Angles(0, 0, math.rad(90)), 9, 170, 3, 0.35, -1, HOT)
	SwordFX.Blade(pos + dir * length * 0.5 + Vector3.new(0, 0.5, 0), dir, length, width * 0.35, FIRE, 0.3)
	explosion(pos + dir * 4 + Vector3.new(0, 1, 0), 6, true)
	local steps = math.floor(length / 3)
	for i = 1, steps do
		task.delay(i * 0.016, function()
			local p = pos + dir * (i * 3)
			eruption(p, 14 + rng:NextNumber(0, 7), width * 0.45)
			if i % 3 == 0 then FireFX.Cracks(p, width * 0.7, 2.4, false) end
		end)
	end
	ClassFX.Sound("swordHit", pos, 1, 0.6)
	ClassFX.Sound("fireWhoosh", pos, 1, 0.6)
	if near(pos, 110) then deps.shake(if msg.attacker == player then 1.6 else 0.8, 0.4) end
	if msg.attacker == player then deps.fovPunch(12, 0.4) end
end

local function onErupt(msg: any)
	-- BOOOOOM: everything inside the wave erupts.
	local origin = msg.origin :: Vector3
	local dir = msg.dir :: Vector3
	local length = msg.length :: number
	for i = 1, 7 do
		task.delay(i * 0.03, explosion, onGround(origin + dir * (length * i / 8)) + Vector3.new(0, 1, 0), 6, i % 2 == 0)
	end
	for i, p in ipairs(msg.points or {}) do
		task.delay(0.05 + i * 0.02, explosion, p, 4, false)
	end
	ClassFX.Sound("quake", origin, 1, 1, 1.5)
	if near(origin, 120) then deps.shake(if msg.attacker == player then 1.4 else 0.7, 0.4) end
end

local HANDLERS: { [string]: (any) -> () } = {
	combo = onCombo,
	charge = onCharge,
	rise = onRise,
	phoenixRise = onPhoenixRise,
	phoenixDive = onPhoenixDive,
	phoenixImpact = onPhoenixImpact,
	flares = onFlares,
	quake = onQuake,
	quakeHit = onQuakeHit,
	aftershocks = onAftershocks,
	rings = onRings,
	patch = onPatch,
	ignite = onIgnite,
	blast = onBlast,
	overheat = onOverheat,
	cooldown = onCooldown,
	awaken = onAwaken,
	pillar = onPillar,
	gather = onGather,
	execution = onExecution,
	erupt = onErupt,
}

function FireKnightController.Init(d: Deps)
	deps = d
	buildHud()
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localStep = 0
	end)
	RunService.Heartbeat:Connect(function(dt)
		refreshHud()
		-- Other Fire Knights' Phoenix Slams (the caster flies their own).
		for c in pairs(flights) do
			if not c.Parent or (c ~= player.Character and c:GetAttribute("FK_Phoenix") ~= true) then endFlight(c) end
		end
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if p ~= player and c and c:GetAttribute("FK_Phoenix") == true and not flights[c] then startFlight(c) end
		end
		local ok, err = pcall(updateLooks, dt)
		if not ok then warn("[FireKnightController] look:", err) end
		ok, err = pcall(updateScorch, dt)
		if not ok then warn("[FireKnightController] scorch:", err) end
	end)
	-- The Phoenix Slam's marker: a click (or F again) sends it diving.
	UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
		local a = aiming
		if not a then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch
			or (input.KeyCode == Enum.KeyCode.F and not processed) then
			a.confirm()
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.FireKnightFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[FireKnightController]", msg.kind, err) end
		end
	end)
end

return FireKnightController
