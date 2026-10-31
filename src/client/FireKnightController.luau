--!strict
--[[
	FireKnightController.luau
	Client side of the Fire Knight (class id "heavy_knight"; server:
	FireKnightServer).

	  • Emberblade: your own swings are predicted (pose, flaming crescents,
	    explosions) on click; the server resolves hits and sends everyone
	    else's swings over FireKnightFX.
	  • Skills: the Fire Tornado spin, the Phoenix Slam flight (rise,
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
local AimInput = require(script.Parent:WaitForChild("AimInput")) -- (the mouse, or a controller's aim)
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))
local FireFX = require(script.Parent:WaitForChild("FireFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local player = Players.LocalPlayer

local FireKnightController = {}

local CLASS = "heavy_knight"

-- ── Tuning (mirrors FireKnightServer) ───────────────────────────────────────
local SWING_INTERVAL = 0.42
local COMBO_RESET = 1.2
local EXECUTION_WINDUP = 0.32
-- Fire Tornado: the wind-up, then the spin (Overheated: longer).
local TORNADO = { windup = 0.14, dur = 2.6, empDur = 3.4 }
local QUAKE_WINDUP = 0.55
local AWAKEN = 2.2 -- (the charge, the pillar of light, the camera pulling out)
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
-- (`lean`, - = forward) and turns (`twist`; CastPoses turns the hips back
-- so the feet stay pointing ahead), the legs are set by their WORLD
-- angles (left foot `front`, right foot `back`, `spread` to the sides) with
-- the lean cancelled at the hips, and the body drops exactly as far as the
-- legs' angles lower the hips, so the feet stay on the floor.
type Pose = { [string]: { number } }

local function stance(p: Pose, lean: number, twist: number, front: number, back: number, spread: number?): Pose
	local sp = spread or 6
	p.W = { lean, twist, 0 }
	p.LH = { front - lean, 0, -sp }
	p.RH = { -back - lean, 0, sp }
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

local function gripOf(char: Model): GripState?
	local tool = char:FindFirstChild("Greatsword")
	if not (tool and tool:IsA("Tool")) then return nil end
	local s = grips[tool]
	if not s then
		s = { tool = tool, base = tool.Grip, k = 0, from = 0, target = 0, t0 = 0, dur = 0 }
		grips[tool] = s
	end
	return s
end

local function gripTo(char: Model, target: number, dur: number)
	local g = gripOf(char)
	if not g then return end
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

-- ── Two hands on the hilt (the chops and the Excalibur raise / slam) ────────
-- After the pose: the grip goes as far out from him as BOTH short R6 arms
-- reach (on the ring where the right hand's reach meets the left's, toward
-- where the pose put the right hand), the right arm re-aims there and the
-- left hand closes on the hilt just behind it, toward the pommel. Switched on
-- by twoHands(char, seconds); eased in and out so the arms don't pop.
local REACH_SLACK = 0.97
local LEFT_BEHIND = 0.6 -- studs from the right hand toward the pommel
local twoHandUntil: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any
local twoHandW: { [Model]: number } = setmetatable({}, { __mode = "k" }) :: any

local function twoHands(char: Model, seconds: number)
	twoHandUntil[char] = math.max(twoHandUntil[char] or 0, os.clock() + seconds)
end

local function insideSphere(p: Vector3, c: Vector3, r: number): Vector3
	local d = p - c
	return if d.Magnitude > r then c + d.Unit * r else p
end

-- Re-aim an arm (torso-space CFrame `a`) about its shoulder pivot so the point
-- `handLocal` (arm space) lands as close as it can to `target`.
local function aimArm(m: Motor6D, a: CFrame, handLocal: Vector3, target: Vector3): CFrame
	local pivot = m.C0.Position
	local from = a * handLocal - pivot
	local to = target - pivot
	if from.Magnitude < 1e-3 or to.Magnitude < 1e-3 then return a end
	local axis = from.Unit:Cross(to.Unit)
	if axis.Magnitude < 1e-5 then return a end
	local r = CFrame.fromAxisAngle(axis.Unit, math.acos(math.clamp(from.Unit:Dot(to.Unit), -1, 1)))
	return CFrame.new(pivot) * r * CFrame.new(-pivot) * a
end

-- Whether a grip point (torso space: X right, Y up, -Z forward) is clear of
-- his body: outside the torso and head, with room for the hands and hilt.
local CLEAR = 0.65
local function clearOfBody(p: Vector3): boolean
	local inTorso = math.abs(p.X) < 1 + CLEAR and math.abs(p.Y) < 1 + CLEAR and p.Z > -(0.5 + CLEAR)
	local inHead = math.abs(p.X) < 0.6 + CLEAR and p.Y >= 1 and p.Y < 2.2 + CLEAR and p.Z > -(0.6 + CLEAR)
	return not (inTorso or inHead)
end

local function twoHandStep(dt: number)
	local now = os.clock()
	for _, pl in ipairs(Players:GetPlayers()) do
		local char = pl.Character
		if not char then continue end
		local want = (twoHandUntil[char] or 0) > now and not char:GetAttribute("Tumbling")
		local w = twoHandW[char] or 0
		w = if want then math.min(1, w + dt * 16) else math.max(0, w - dt * 8)
		twoHandW[char] = w
		if w <= 0 then continue end
		local tool = char:FindFirstChild("Greatsword")
		local torso = char:FindFirstChild("Torso")
		local rArm = char:FindFirstChild("Right Arm")
		if not (tool and tool:IsA("Tool") and torso and rArm) then continue end
		local rs, ls = torso:FindFirstChild("Right Shoulder"), torso:FindFirstChild("Left Shoulder")
		local grip = rArm:FindFirstChild("RightGrip")
		if not (rs and ls and grip and rs:IsA("Motor6D") and ls:IsA("Motor6D") and grip:IsA("JointInstance")) then continue end

		local handR = grip.C0.Position
		local handL = Vector3.new(0, -1, 0)
		local reachR = (handR - rs.C1.Position).Magnitude * REACH_SLACK
		local reachL = (handL - ls.C1.Position).Magnitude * REACH_SLACK
		local pR, pL = rs.C0.Position, ls.C0.Position
		local aR0 = rs.C0 * rs.Transform * rs.C1:Inverse()
		local aL0 = ls.C0 * ls.Transform * ls.C1:Inverse()
		local free = aR0 * handR
		-- (the blade runs up the handle's +Y)
		local blade0 = (aR0 * grip.C0 * grip.C1:Inverse()):VectorToWorldSpace(Vector3.yAxis)
		local pL2 = pL + blade0 * LEFT_BEHIND
		local held = free
		local across = pL2 - pR
		local d = across.Magnitude
		if d > 1e-3 and d < reachR + reachL and d > math.abs(reachR - reachL) then
			local n = across / d
			local a = (d * d + reachR * reachR - reachL * reachL) / (2 * d)
			local ring = math.sqrt(math.max(reachR * reachR - a * a, 0))
			local c = pR + n * a
			local off = free - c
			off -= n * off:Dot(n)
			if off.Magnitude < 1e-3 then
				local fwd = Vector3.new(0, -0.5, -1)
				off = fwd - n * fwd:Dot(n)
			end
			held = c + off.Unit * ring
			-- (never through him: slide round the ring, the shorter way, to the
			-- nearest point clear of his body)
			if not clearOfBody(held) then
				local u = off.Unit
				local v = n:Cross(u)
				for k = 1, 18 do
					local a2 = math.rad(k * 10)
					local p1 = c + (u * math.cos(a2) + v * math.sin(a2)) * ring
					local p2 = c + (u * math.cos(a2) - v * math.sin(a2)) * ring
					if clearOfBody(p1) then held = p1 break end
					if clearOfBody(p2) then held = p2 break end
				end
			end
		else
			for _ = 1, 4 do
				held = insideSphere(held, pL2, reachL)
				held = insideSphere(held, pR, reachR)
			end
			-- (out of reach of each other: at least keep it in front of him)
			if not clearOfBody(held) then
				held = insideSphere(Vector3.new(held.X * 0.5, held.Y, -(0.5 + CLEAR) - 0.2), pR, reachR)
			end
		end
		local aR = aimArm(rs, aR0, handR, held)
		local handleCF = aR * grip.C0 * grip.C1:Inverse()
		local blade = handleCF:VectorToWorldSpace(Vector3.yAxis)
		local gl = insideSphere(held - blade * LEFT_BEHIND, pL, reachL)
		local aL = aimArm(ls, aL0, handL, gl)
		rs.Transform = rs.C0:Inverse() * aR0:Lerp(aR, w) * rs.C1
		ls.Transform = ls.C0:Inverse() * aL0:Lerp(aL, w) * ls.C1
	end
end

-- Seconds from the start of each combo swing to its hit (FireKnightServer
-- lands the damage on the same beat).
local COMBO_HIT = { 0.12, 0.11, 0.14, EXECUTION_WINDUP }

local function swingPose(char: Model, step: number)
	if step == 1 then
		-- Cinder Slash: weight back and coiled right, the blade low and flat;
		-- the hips drive a wide sweep across to the left and carry on round
		-- (twist + = to the left, as its crescent).
		gripTo(char, 0, 0.1)
		CastPoses.play(char, {
			{ dur = 0.12, style = QUAD, pose = pose(-6, -45, 14, 14, 25, -105, 20, -80, { N = { 0, 30, 0 } }) },
			{ dur = 0.08, style = QUART, pose = pose(-12, 35, 22, 22, 25, 90, 20, 65, { N = { 0, -20, 0 } }) },
			{ dur = 0.16, pose = pose(-10, 50, 22, 22, 20, 115, 15, 88, { N = { 0, -28, 0 } }) },
		}, 0.34, true)
	elseif step == 2 then
		-- Scorching Cross: gathered up high on the left, then cut down across
		-- to the low right; the two trails cross into an X.
		gripTo(char, 0, 0.1)
		CastPoses.play(char, {
			{ dur = 0.11, style = QUAD, pose = pose(4, 40, 14, 14, 115, 65, 105, 45, { N = { -6, -25, 0 } }) },
			{ dur = 0.08, style = QUART, pose = pose(-16, -38, 24, 24, 5, -85, 10, -60, { N = { 8, 15, 0 } }) },
			{ dur = 0.16, pose = pose(-13, -50, 24, 24, 0, -98, 5, -72, { N = { 8, 22, 0 } }) },
		}, 0.34, true)
	elseif step == 3 then
		-- Furnace Breaker: the blade turned to run along the arms and lifted
		-- straight overhead (arching back), then chopped down into the ground
		-- ahead with the whole body. Both hands on the hilt.
		gripTo(char, 1, 0.12)
		twoHands(char, 0.62)
		CastPoses.play(char, {
			{ dur = 0.14, style = QUAD, pose = pose(8, 0, 14, 14, 172, 0, 170, 0, { N = { 12, 0, 0 } }) },
			{ dur = 0.07, style = QUART, pose = pose(-26, 0, 30, 30, 38, 0, 40, 0, { N = { 16, 0, 0 } }) },
			{ dur = 0.2, pose = pose(-30, 0, 32, 32, 32, 0, 34, 0, { N = { 18, 0, 0 } }) },
		}, 0.4, true)
		task.delay(0.21, CastPoses.hitStop, char, 0.06)
		gripBack(char, 0.42, 0.3)
	else
		-- Infernal Execution: the sword hauled back over the shoulder until the
		-- blade hangs behind him, held trembling... then the SLAM, the whole
		-- body following it down into a deep lunge. Both hands on the hilt.
		gripTo(char, 1, 0.14)
		twoHands(char, EXECUTION_WINDUP + 0.75)
		CastPoses.play(char, {
			{ dur = 0.18, style = QUAD, pose = pose(14, 28, 18, 18, 200, 18, 195, 12, { N = { 14, -12, 0 } }) },
			{ dur = EXECUTION_WINDUP - 0.18, style = Enum.EasingStyle.Linear,
				pose = pose(16, 30, 18, 18, 206, 18, 200, 12, { N = { 16, -12, 0 } }), wobble = tremble(1.5) },
			{ dur = 0.08, style = QUART, pose = pose(-38, 0, 38, 38, 42, 0, 44, 0, { N = { 22, 0, 0 } }) },
			{ dur = 0.34, pose = pose(-36, 0, 38, 38, 38, 0, 40, 0, { N = { 20, 0, 0 } }) },
		}, 0.48, true)
		task.delay(EXECUTION_WINDUP + 0.08, CastPoses.hitStop, char, 0.09)
		gripBack(char, EXECUTION_WINDUP + 0.5, 0.35)
	end
end

-- Fire Tornado: the blade swung round low to the right, then carried flat
-- at the waist in both hands as the whole body spins round and round inside
-- the fire (a whole number of turns, so he ends facing the way he started).
local function spinPose(char: Model, dur: number)
	local w = TORNADO.windup
	gripTo(char, 0, w)
	local spinFor = math.max(dur - w, 0.1)
	local turns = math.max(1, math.floor(spinFor * 2.4 + 0.5))
	local rate = turns * 360 / spinFor
	CastPoses.play(char, {
		{ dur = w, style = QUAD, pose = pose(-6, -45, 14, 14, 25, -105, 20, -80, { N = { 0, 30, 0 } }) },
		{ dur = spinFor, pose = pose(-10, 40, 22, 22, 30, 100, 25, 75, { N = { 0, -24, 0 } }), wobble = function(t: number)
			return { Root = { 0, math.max(t - w, 0) * rate, 0 } }
		end },
	}, 0.3, true)
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
	twoHands(char, seconds + 0.1)
	local p = pose(8, 0, 12, 12, 172, 0, 170, 0, { N = { 18, 0, 0 } }, 8)
	CastPoses.play(char, {
		{ dur = 0.22, style = QUAD, pose = p },
		{ dur = math.max(seconds - 0.22, 0.05), pose = p, wobble = tremble(1.2) },
	}, 0.3, true)
end

local function slamPose(char: Model)
	-- The Final Blow: one enormous downward slash into a deep lunge, both
	-- hands on the hilt.
	gripTo(char, 1, 0.05)
	twoHands(char, 0.85)
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
		-- A vertical chop (drawn top to bottom) that bursts into a small explosion.
		task.delay(COMBO_HIT[3] - 0.04, crescent, look * CFrame.new(0, 1, 0) * CFrame.Angles(0, 0, math.rad(90)), 5.5 * size, 150, thick, 0.25, 1, color)
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
			crescent(base * CFrame.new(0, 1.2, 0) * CFrame.Angles(0, 0, math.rad(90)), 7.5 * size, 170, thick * 1.5, 0.3, 1, color)
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
	local m = AimInput.ScreenPoint() -- (the mouse, or a controller's aim)
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

function FireKnightController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any)
	local dir = flat(aimDir)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local now = os.clock()
	local hot = empowered(player)
	char:SetAttribute("AllowSkillMovement", false)
	if skillIndex == 1 then
		-- Fire Tornado: spun round inside the fire, free to walk it about.
		local dur = if hot then TORNADO.empDur else TORNADO.dur
		busyUntil = now + dur + 0.1
		char:SetAttribute("AllowSkillMovement", true)
		spinPose(char, dur)
		releaseAfter(char, dur + 0.05)
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
		-- (front three-quarter at face height, tilted, pushing slowly in: his
		-- head, his chest and the whole blade in frame, like the reference)
		-- (the reference GIF's angle: 45° round to his right, above him and
		-- looking down on him, tilted, pushing slowly in)
		startOffset = { 7.4, 7.4, 6.0 },
		endOffset = { 6.6, 6.6, 5.4 },
		focusHeight = 1.4,
		fovStart = 42,
		fovEnd = 37,
		-- (the pillar: the camera pulls out wide to take it in)
		pullAt = AWAKEN - 0.7,
		pullOffset = { 22, 22, 13 },
		pullFocus = 11,
		pullFov = 62,
		roll = 7,
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

-- Fire Tornado (every client): the tornado effect made for it,
-- ReplicatedStorage.Tornado (its spinning wind of fire and the waves rolling
-- up off the floor), set at his feet and carried with him. It starts small
-- and swells to full size (sized to the tornado's reach); at the end its
-- emitters stop and what's left blows away. Its burst-only emitters (an
-- EmitCount attribute, after EmitDelay) go off once as it appears.
local TORNADO_FX = {
	grow = 0.7,        -- seconds from small to full size
	steps = 8,         -- (sizes re-set this many times while it grows)
	start = 0.25,      -- the size it starts at
	baseRadius = 7.5,  -- the reach the effect was made at full size for
	lift = 0.6,        -- its part sits this far over the floor (its Main attachment is at -0.6)
}

local function scaledSeq(seq: NumberSequence, k: number): NumberSequence
	local kps = {}
	for _, kp in ipairs(seq.Keypoints) do
		table.insert(kps, NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k))
	end
	return NumberSequence.new(kps)
end

local function onTornado(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local dur = tonumber(msg.dur) or TORNADO.dur
	local r = tonumber(msg.radius) or TORNADO_FX.baseRadius
	if msg.attacker ~= player then spinPose(char, dur) end
	trail(char, dur)
	ClassFX.Sound("fireWhoosh", root, 0.9, 0.7)
	ClassFX.Sound("wind", root, 0.7, 0.9)
	if msg.attacker == player then deps.shake(0.3, 0.2) end
	local template = ReplicatedStorage:FindFirstChild("Tornado")
	if not (template and template:IsA("BasePart")) then return end

	-- a copy of it, unseen holders that never touch anything
	local fx = template:Clone()
	local lvl = fx:FindFirstChild("Lvlup")
	local lvlPart = if lvl and lvl:IsA("BasePart") then lvl else nil
	local lvlRel = if lvlPart then template.CFrame:ToObjectSpace((template :: any).Lvlup.CFrame) else CFrame.identity
	type Em = { e: ParticleEmitter, size: NumberSequence, speed: NumberRange }
	local ems: { Em } = {}
	local density = 1 - 0.6 * FxBudget.Pressure() -- (fewer when the frame rate's struggling)
	for _, d in ipairs({ fx :: Instance, unpack(fx:GetDescendants()) }) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanQuery, d.CanTouch, d.CastShadow = true, false, false, false, false
			d.Transparency = 1
		elseif d:IsA("ParticleEmitter") then
			d.Rate *= density
			table.insert(ems, { e = d, size = d.Size, speed = d.Speed })
		end
	end
	local full = r / TORNADO_FX.baseRadius
	local function setScale(k: number)
		for _, m in ipairs(ems) do
			m.e.Size = scaledSeq(m.size, k)
			m.e.Speed = NumberRange.new(m.speed.Min * k, m.speed.Max * k)
		end
	end
	setScale(TORNADO_FX.start * full)
	local floorY = groundY(root.Position)
	local function place()
		local c = root.Position
		fx.CFrame = CFrame.new(c.X, floorY + TORNADO_FX.lift, c.Z)
		if lvlPart then lvlPart.CFrame = fx.CFrame * lvlRel end
	end
	place()
	fx.Parent = ClassFX.Folder()
	for _, m in ipairs(ems) do
		local n = tonumber(m.e:GetAttribute("EmitCount"))
		if n and n > 0 then
			task.delay(tonumber(m.e:GetAttribute("EmitDelay")) or 0, function()
				if m.e.Parent then m.e:Emit(n) end
			end)
		end
	end

	local t0 = os.clock()
	local floorAt, grown = 0, 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= dur or not root.Parent or not fx.Parent then
			conn:Disconnect()
			local longest = 0
			for _, m in ipairs(ems) do
				m.e.Enabled = false
				longest = math.max(longest, m.e.Lifetime.Max)
			end
			Debris:AddItem(fx, longest + 0.2)
			return
		end
		-- (the floor under him, a few times a second)
		if t - floorAt > 0.07 then
			floorAt = t
			floorY = groundY(root.Position)
		end
		place()
		-- growing: small to full size, re-sized in a few steps
		if grown < TORNADO_FX.steps then
			local g = math.clamp(t / TORNADO_FX.grow, 0, 1)
			local stepNow = math.floor(g * TORNADO_FX.steps)
			if stepNow > grown then
				grown = stepNow
				local e = 1 - (1 - grown / TORNADO_FX.steps) ^ 2
				setScale((TORNADO_FX.start + (1 - TORNADO_FX.start) * e) * full)
			end
		end
	end)
end

-- The tornado blowing apart: an explosion, a ring of fire bursting out and
-- the flames flung off it.
local function onTornadoEnd(msg: any)
	local pos = msg.pos :: Vector3
	local r = tonumber(msg.radius) or 10
	local big = msg.empowered == true
	explosion(pos, r * 0.7, big)
	FireFX.FlameRing(pos, r * 0.85, if big then 9 else 6)
	FireFX.Puff("lick", CFrame.new(pos + Vector3.new(0, 1.5, 0)), 1.2, 18)
	ClassFX.Sound("fireBurst", pos, 0.9, 0.85)
	if msg.attacker == player then
		deps.shake(0.8, 0.25)
		deps.fovPunch(6, 0.25)
	elseif near(pos, 50) then
		deps.shake(0.3, 0.15)
	end
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

-- The Awakening (after the reference): the sword raised upright before him in
-- both hands, the hilt at his chest, the blade rising past his face; his
-- head bowed, still, breathing slow while the blade fills with light.
-- (both hands on the hilt in front of the chest: the right brought in to just
-- right of the middle, the left crossing over to close round the grip under
-- it. Measured on the rig: a - sideways turn brings the right hand in, a +
-- the left)
local HOLD_UPRIGHT = pose(-4, -8, 6, 6, 74, 0, 74, 0, { RS = { 90, 0, -36, 0, 0, -0.8 }, LS = { 90, 0, 36, 0, 0, -0.8 }, N = { -14, 8, 0 } }, 8)
local function holdUpright(char: Model, seconds: number)
	gripTo(char, 0, 0.2)
	CastPoses.play(char, {
		{ dur = 0.3, style = SINE, pose = HOLD_UPRIGHT },
		{ dur = math.max(seconds - 0.3, 0.05), pose = HOLD_UPRIGHT, wobble = function(t)
			local b = math.sin(t * 2.2) * 1.2
			return { N = { b * 0.6, 0, 0 }, W = { b * 0.5, 0, 0 } }
		end },
	}, 0.3, true)
	-- The sword itself held exactly, whatever the arms are doing: straight up
	-- along his body, the broad flat of the blade turned to whoever's
	-- watching (never its edge), the hilt still in his hand. The grip is set
	-- each frame from where it has to end up; eased in over the raise.
	local tool = char:FindFirstChild("Greatsword")
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	local arm = char:FindFirstChild("Right Arm") :: BasePart?
	local weld = arm and arm:FindFirstChild("RightGrip") :: Weld?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	local leftArm = char:FindFirstChild("Left Arm") :: BasePart?
	if not (tool and tool:IsA("Tool") and handle and arm and weld and torso) then return end
	local blade: BasePart? = nil
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle and (not blade or d.Size.Magnitude > blade.Size.Magnitude) then blade = d end
	end
	-- The blade runs up the handle's +Y; its thickness is the blade mesh's X
	-- (whichever way the mesh itself is turned): that, toward the camera,
	-- shows the flat. Both in the handle's frame.
	local thick = if blade then handle.CFrame:VectorToObjectSpace(blade.CFrame.XVector) else Vector3.xAxis
	thick = Vector3.new(thick.X, 0, thick.Z)
	thick = if thick.Magnitude > 0.01 then thick.Unit else Vector3.xAxis
	local localBasis = CFrame.fromMatrix(Vector3.zero, thick, Vector3.yAxis, thick:Cross(Vector3.yAxis))
	local g = gripOf(char)
	local base = if g then g.base else tool.Grip
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > seconds or not (tool.Parent and handle.Parent and weld.Parent) then
			if conn then conn:Disconnect() end
			if tool.Parent then tool.Grip = base end
			return
		end
		local hand = arm.CFrame * weld.C0
		local up = torso.CFrame.UpVector
		local cam = Workspace.CurrentCamera
		local toCam = if cam then cam.CFrame.Position - hand.Position else -torso.CFrame.LookVector
		toCam -= up * toCam:Dot(up)
		if toCam.Magnitude < 0.01 then return end
		-- (its flat to his front: the crossguard runs left to right across his
		-- body, as in the reference)
		local front = torso.CFrame.LookVector
		front -= up * front:Dot(up)
		local x = front.Unit
		local handleRot = CFrame.fromMatrix(Vector3.zero, x, up, x:Cross(up)) * localBasis:Inverse()
		-- (the hilt between his two hands, side by side on it)
		local mid = hand.Position
		if leftArm then
			local l = (leftArm.CFrame * CFrame.new(0, -leftArm.Size.Y / 2 + 0.3, 0)).Position
			mid = (hand.Position + l) / 2
		end
		local want = CFrame.new(mid) * handleRot * CFrame.new(-base.Position)
		local w = math.clamp(t / 0.3, 0, 1)
		local now = handle.CFrame:Lerp(want, w)
		tool.Grip = now:Inverse() * hand
	end)
end

-- The blade filling with light (the reference): a white-gold core drawn up it
-- from the hilt, a sheath of fire-gold round it, ribbons of golden fire
-- curling up round it, gold sparks drifting up off it, and a warm light on
-- his face. For `seconds`, then it all dies down.
local GOLD = Color3.fromRGB(255, 196, 70)
local function bladeBlaze(char: Model, seconds: number)
	local tool = char:FindFirstChild("Greatsword")
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	if not (tool and handle) then return end
	-- the blade: the sword's biggest part (the whole sword is often one mesh)
	local blade: BasePart? = nil
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle and (not blade or d.Size.Magnitude > blade.Size.Magnitude) then blade = d end
	end
	if not blade then return end
	local bladePart = blade :: BasePart
	-- where it runs along the handle's +Y, and how broad it is
	local rel = handle.CFrame:ToObjectSpace(bladePart.CFrame)
	local longest = math.max(bladePart.Size.X, bladePart.Size.Y, bladePart.Size.Z)
	local midY = rel.Position.Y
	local base, tip = midY - longest * 0.32, midY + longest * 0.5
	local len = tip - base
	local folder = ClassFX.Folder()
	local made: { Instance } = {}

	-- the blade itself catching light: a copy of its own shape in white-gold
	-- light laid over it, a bigger, fainter copy round it for the glow
	local function overlay(scale: number, color: Color3): BasePart
		local c = bladePart:Clone()
		for _, k in ipairs(c:GetChildren()) do
			if not (k:IsA("SpecialMesh")) then k:Destroy() end
		end
		if c:IsA("MeshPart") then c.TextureID = "" end
		local mesh = c:FindFirstChildOfClass("SpecialMesh")
		if mesh then mesh.TextureId = "" end
		c.Size = bladePart.Size * scale
		c.Color = color
		c.Material = Enum.Material.Neon
		c.Transparency = 1
		c.Anchored = false
		c.CanCollide, c.CanQuery, c.CanTouch, c.CastShadow, c.Massless = false, false, false, false, true
		c.CFrame = bladePart.CFrame
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = bladePart, c
		w.Parent = c
		c.Parent = folder
		table.insert(made, c)
		return c
	end
	-- (saturated gold: near-white light reads pink under a dusk sky)
	local core = overlay(1.02, Color3.fromRGB(255, 200, 80))
	local halo = overlay(1.14, Color3.fromRGB(255, 140, 30))
	-- the band of light drawn up the blade from the hilt as it fills
	local band = Instance.new("Part")
	band.Size = Vector3.new(bladePart.Size.X * 1.25, 0.18, bladePart.Size.Z * 1.25)
	band.Color = WHITE
	band.Material = Enum.Material.Neon
	band.Transparency = 1
	band.Anchored = true
	band.CanCollide, band.CanQuery, band.CanTouch, band.CastShadow = false, false, false, false
	band.Parent = folder
	table.insert(made, band)
	local fill = 0.55

	-- the ribbons: little carriers wound up round the blade, a trail behind each
	type Ribbon = { p: BasePart, trail: Trail, phase: number, lastU: number }
	local ribbons: { Ribbon } = {}
	local rx, rz = bladePart.Size.X * 0.9, bladePart.Size.Z * 0.62
	for i = 1, 3 do
		local p = Instance.new("Part")
		p.Size = Vector3.one * 0.1
		p.Transparency = 1
		p.Anchored = true
		p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = false, false, false, false
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, 0.06, 0)
		a0.Parent = p
		local a1 = Instance.new("Attachment")
		a1.Position = Vector3.new(0, -0.06, 0)
		a1.Parent = p
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(GOLD, FIRE)
		tr.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		tr.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 0.1) })
		tr.Lifetime = 0.22
		tr.LightEmission = 1
		tr.LightInfluence = 0
		tr.FaceCamera = true
		tr.Enabled = false
		tr.Parent = p
		p.Parent = folder
		table.insert(made, p)
		table.insert(ribbons, { p = p, trail = tr, phase = (i - 1) / 3, lastU = 0 })
	end
	-- the sparks: drifting up off the whole blade
	local sparkHolder = Instance.new("Part")
	sparkHolder.Size = Vector3.new(bladePart.Size.X * 1.3, len, bladePart.Size.Z * 1.2)
	sparkHolder.Transparency = 1
	sparkHolder.CanCollide, sparkHolder.CanQuery, sparkHolder.CanTouch, sparkHolder.CastShadow, sparkHolder.Massless = false, false, false, false, true
	sparkHolder.CFrame = handle.CFrame * CFrame.new(0, base + len / 2, 0)
	local sw = Instance.new("WeldConstraint")
	sw.Part0, sw.Part1 = handle, sparkHolder
	sw.Parent = sparkHolder
	sparkHolder.Parent = folder
	table.insert(made, sparkHolder)
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = ColorSequence.new(HOT, EMBER)
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(1, 0) })
	sparks.Lifetime = NumberRange.new(0.8, 1.4)
	sparks.Speed = NumberRange.new(0.6, 2)
	sparks.Acceleration = Vector3.new(0, 3, 0)
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Shape = Enum.ParticleEmitterShape.Box
	sparks.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	sparks.Rate = 0
	sparks.Parent = sparkHolder
	-- and real fire licking up it (the Fire Knight's own flames)
	local flames = FireFX.Emitter("flame", sparkHolder, 1.7)
	flames.Shape = Enum.ParticleEmitterShape.Box
	flames.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	flames.EmissionDirection = Enum.NormalId.Top
	flames.Rate = 0
	-- the warm light on his face (counted against the effect-light budget)
	local glow: PointLight? = nil
	if FxBudget.Light() then
		local l = Instance.new("PointLight")
		l.Color = Color3.fromRGB(255, 200, 120)
		l.Brightness = 0
		l.Range = 9
		l.Shadows = false
		l.Parent = sparkHolder
		FxBudget.TrackLight(l)
		glow = l
	end

	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > seconds or not handle.Parent then
			if conn then conn:Disconnect() end
			for _, r in ipairs(ribbons) do r.trail.Enabled = false end
			sparks.Rate = 0
			flames.Rate = 0
			for _, p in ipairs({ core, halo, band }) do
				TweenService:Create(p, TweenInfo.new(0.3), { Transparency = 1 }):Play()
			end
			if glow then TweenService:Create(glow, TweenInfo.new(0.3), { Brightness = 0 }):Play() end
			for _, p in ipairs(made) do Debris:AddItem(p, 1.6) end
			return
		end
		-- the light fills the blade from the hilt up (once the hands are up)
		local k = math.clamp((t - 0.25) / fill, 0, 1)
		local eased = 1 - (1 - k) ^ 3
		local pulse = 0.5 + 0.5 * math.sin(t * 6)
		core.Transparency = 1 - 0.8 * eased
		halo.Transparency = 1 - (0.38 + 0.1 * pulse) * eased
		if k < 1 then
			band.Transparency = 0.1
			band.CFrame = handle.CFrame * CFrame.new(0, base + len * eased, 0)
		else
			band.Transparency = 1
		end
		sparks.Rate = 30 * k
		flames.Rate = 30 * k
		if glow then glow.Brightness = 2.2 * k + 0.4 * pulse * k end
		-- the ribbons wind up round it, over and over, once it's lit
		for _, r in ipairs(ribbons) do
			local u = (t * 1.5 + r.phase) % 1
			if u < r.lastU then r.trail:Clear() end -- (back to the hilt: no line drawn across)
			r.lastU = u
			r.trail.Enabled = k > 0.3
			local a = t * 9 + r.phase * 6.28 + u * 6
			local shrink = 1 - u * 0.5
			r.p.CFrame = handle.CFrame * CFrame.new(math.cos(a) * rx * shrink, base + u * len * math.max(eased, 0.2), math.sin(a) * rz * shrink)
		end
	end)
end

-- The sword become light (the reference's end): out of the blazing blade a
-- vast blade of light shoots up, the sword's own shape (flat and broad,
-- facing the same way, a point at the top): white-hot down its middle,
-- golden toward its edges, a soft glow round it, golden ribbons curling up
-- round it and sparks streaming off. Held by its hilt. On the swing
-- (onExcalibur) it tips over forward, down the line, and goes out as the
-- wave runs.
type Pillar = { parts: { BasePart }, ribbons: { Trail }, tilt: number, dir: Vector3?, fade: number, conn: RBXScriptConnection? }
local swordPillars: { [Model]: Pillar } = {}
local PILLAR_HEIGHT = 70
local function raisePillar(char: Model, life: number)
	local tool = char:FindFirstChild("Greatsword")
	local handle = tool and tool:FindFirstChild("Handle") :: BasePart?
	if not (tool and handle) then return end
	local blade: BasePart? = nil
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d ~= handle and (not blade or d.Size.Magnitude > blade.Size.Magnitude) then blade = d end
	end
	-- the blade's broad axis (its mesh's Z) and how broad it is
	local broadW = if blade then math.min(blade.Size.Z, blade.Size.X * 4) else 2.2
	broadW = math.max(broadW, 1.6)
	local function slab(w: number, thick: number, color: Color3, tr: number, class: string?): BasePart
		local p = Instance.new(class or "Part") :: BasePart
		p.Material = Enum.Material.Neon
		p.Color = color
		p.Transparency = tr
		p.Size = Vector3.new(w, 0.1, thick)
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Parent = ClassFX.Folder()
		return p
	end
	-- A pillar of fire streaming up out of the blade: rolling flame, a white-
	-- hot core, embers flying off, a flare at the top (no neon light).
	local function holder(): BasePart
		local q = Instance.new("Part")
		q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.CastShadow = true, false, false, false, false
		q.Transparency = 1
		q.Size = Vector3.one
		q.Parent = ClassFX.Folder()
		return q
	end
	local function stream(e: ParticleEmitter, life: number, speed: number)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Front
		e.SpreadAngle = Vector2.new(5, 5)
		e.Speed = NumberRange.new(speed * 0.7, speed)
		e.Acceleration = Vector3.zero
		e.Drag = 2
		e.Lifetime = NumberRange.new(life * 0.8, life)
		e.Enabled = true
	end
	-- (as broad as the colossal blade it comes down as)
	local bw = math.max(broadW * 5, 10)
	local shaftBox = holder()
	local coreBox = holder()
	local topBox = holder()
	topBox.Size = Vector3.one * bw
	-- (several of each: an emitter tops out at 400 a second, far too thin
	-- for a pillar this size)
	local shaftFires: { ParticleEmitter } = {}
	for _ = 1, 3 do
		local roll = FireFX.Emitter("roll", shaftBox, bw * 0.6)
		stream(roll, 0.35, 26)
		table.insert(shaftFires, roll)
	end
	for _ = 1, 2 do
		local flame = FireFX.Emitter("flame", shaftBox, bw * 0.45)
		stream(flame, 0.3, 34)
		table.insert(shaftFires, flame)
	end
	local coreFire = FireFX.Emitter("flame", coreBox, bw * 0.3)
	stream(coreFire, 0.22, 44)
	coreFire.Color = FireFX.Colors(true)
	coreFire.Brightness = 8
	local sparks = FireFX.Emitter("embers", shaftBox, 0.35)
	stream(sparks, 0.9, 20)
	sparks.SpreadAngle = Vector2.new(40, 40)
	local flare = FireFX.Emitter("roll", topBox, bw * 1.4)
	flare.SpreadAngle = Vector2.new(180, 180)
	flare.Speed = NumberRange.new(3, 8)
	flare.Lifetime = NumberRange.new(0.25, 0.35)
	flare.Enabled = true
	local fires = { coreFire, sparks, flare }
	for _, e in ipairs(shaftFires) do table.insert(fires, e) end

	local P: Pillar = { parts = { shaftBox, coreBox, topBox }, ribbons = {}, tilt = 0, fade = 0 }
	local old = swordPillars[char]
	if old then for _, q in ipairs(old.parts) do q:Destroy() end end
	swordPillars[char] = P
	FireFX.Explosion((handle.CFrame * CFrame.new(0, 3, 0)).Position, 4, true)
	ClassFX.Sound("boom", handle.Position, 0.8, 1.2)
	local t0 = os.clock()
	P.conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > life or not handle.Parent then
			if P.conn then P.conn:Disconnect() end
			for _, e in ipairs(fires) do e.Enabled = false end
			for _, q in ipairs(P.parts) do Debris:AddItem(q, 1) end
			if swordPillars[char] == P then swordPillars[char] = nil end
			return
		end
		-- it shoots up in a quarter second
		local h = PILLAR_HEIGHT * (1 - (1 - math.min(t / 0.25, 1)) ^ 3)
		-- (out of the blade, along it: it follows the sword through the raise
		-- and the swing, and comes down with it as the slam)
		local up = handle.CFrame.UpVector
		local hilt = handle.Position + up * 1
		local shaft = math.max(h, 0.5)
		-- (a box's -Z runs up the pillar: the flames stream along it)
		local side = if math.abs(up.Y) > 0.99 then Vector3.xAxis else Vector3.yAxis
		local cf = CFrame.lookAt(hilt + up * (shaft / 2), hilt + up * shaft, side)
		local k = 1 - P.fade
		shaftBox.Size = Vector3.new(bw * 0.7, bw * 0.7, shaft)
		shaftBox.CFrame = cf
		coreBox.Size = Vector3.new(bw * 0.25, bw * 0.25, shaft)
		coreBox.CFrame = cf
		topBox.CFrame = CFrame.new(hilt + up * shaft)
		for _, e in ipairs(shaftFires) do e.Rate = math.min(shaft * 7, 400) * k end
		coreFire.Rate = math.min(shaft * 6, 400) * k
		sparks.Rate = shaft * 2 * k
		flare.Rate = 50 * k
	end)
end

-- ── Air ─────────────────────────────────────────────────────────────────────
-- A streak of wind: a thin pale line flying from `a` to `b` (curving round
-- `bend`) and thinning out.
local function windStreak(a: Vector3, b: Vector3, bend: Vector3, life: number, thick: number)
	local q = Instance.new("Part")
	q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.CastShadow = true, false, false, false, false
	q.Material = Enum.Material.Neon
	q.Color = Color3.fromRGB(255, 244, 228)
	q.Transparency = 0.55
	q.Size = Vector3.new(thick, thick, 0.1)
	q.Parent = ClassFX.Folder()
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local k = math.clamp((os.clock() - t0) / life, 0, 1)
		local function at(u: number): Vector3
			local m = a:Lerp(bend, u)
			return m:Lerp(bend:Lerp(b, u), u)
		end
		local head = at(math.min(k * 1.15, 1))
		local tail = at(math.max(k * 1.15 - 0.35, 0))
		local len = (head - tail).Magnitude
		if len > 0.05 then
			q.Size = Vector3.new(thick * (1 - k * 0.6), thick * (1 - k * 0.6), len)
			q.CFrame = CFrame.lookAt((head + tail) / 2, head)
		end
		q.Transparency = 0.55 + 0.45 * k * k
		if k >= 1 then
			if conn then conn:Disconnect() end
			q:Destroy()
		end
	end)
end

-- A ring of air (a flat pale band) growing from `r0` to `r1`, facing `normal`.
local function airRing(c: Vector3, normal: Vector3, r0: number, r1: number, life: number, width: number)
	local ring = CFrame.lookAt(c, c + normal) * CFrame.Angles(math.rad(90), 0, 0)
	SwordFX.Arc({ cf = ring, radius = r0, arc = 359, width = width, color = Color3.fromRGB(255, 246, 232),
		draw = 0.001, life = life, grow = r1 / r0 - 1 })
end

-- The wind-up: air drawn in round him for `seconds` — streaks of wind
-- spiralling in from all round and up into the blade, rings of air closing
-- in at his feet.
local function airWindup(char: Model, seconds: number)
	local root = rootOf(char)
	if not root then return end
	local t0 = os.clock()
	task.spawn(function()
		local i = 0
		while os.clock() - t0 < seconds and root.Parent do
			i += 1
			local feet = onGround(root.Position)
			local blade = bladeMid(char) or (root.Position + Vector3.new(0, 4, 0))
			for _ = 1, 3 do
				local ang = rng:NextNumber(0, math.pi * 2)
				local r = rng:NextNumber(12, 20)
				local from = feet + Vector3.new(math.cos(ang) * r, rng:NextNumber(0.5, 6), math.sin(ang) * r)
				-- (curving round as it comes in: a spiral)
				local swirl = ang + rng:NextNumber(0.8, 1.3)
				local bend = feet + Vector3.new(math.cos(swirl) * r * 0.5, rng:NextNumber(2, 7), math.sin(swirl) * r * 0.5)
				windStreak(from, blade, bend, rng:NextNumber(0.35, 0.5), rng:NextNumber(0.08, 0.16))
			end
			if i % 4 == 0 then
				airRing(feet + Vector3.new(0, 0.3, 0), Vector3.yAxis, 14, 4, 0.35, 0.5)
			end
			task.wait(0.07)
		end
	end)
end

-- The impact: the air blasted out from it — pressure rings racing out flat
-- at a few heights, gusts shooting outward, an upright ring punched out
-- down the line.
local function airImpact(g: Vector3, dir: Vector3, size: number)
	for i, h in ipairs({ 0.4, 2.5, 5 }) do
		task.delay((i - 1) * 0.04, airRing, g + Vector3.new(0, h, 0), Vector3.yAxis, size * 0.6, size * (3.2 - i * 0.4),
			0.4 + i * 0.05, 1.2 - i * 0.25)
	end
	for _ = 1, 22 do
		local ang = rng:NextNumber(0, math.pi * 2)
		local out = Vector3.new(math.cos(ang), rng:NextNumber(0.05, 0.4), math.sin(ang)).Unit
		local from = g + Vector3.new(0, rng:NextNumber(0.5, 4), 0) + out * size * 0.4
		local to = from + out * rng:NextNumber(size * 2.5, size * 4)
		windStreak(from, to, from:Lerp(to, 0.5) + Vector3.new(0, rng:NextNumber(-1, 2), 0), rng:NextNumber(0.25, 0.4),
			rng:NextNumber(0.12, 0.25))
	end
	local up = g + Vector3.new(0, size * 0.6, 0)
	airRing(up + dir * 3, dir, size * 0.5, size * 1.8, 0.35, 0.8)
	task.delay(0.06, airRing, up + dir * 8, dir, size * 0.5, size * 2.2, 0.35, 0.5)
end

-- Stars of fire hanging in the dark round `center` (radius `r`), twinkling
-- and drifting up, for `seconds`.
local function emberStars(center: Vector3, r: number, seconds: number)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch, a.CastShadow = true, false, false, false, false
	a.Transparency = 1
	a.Size = Vector3.new(r * 2, 14, r * 2)
	a.CFrame = CFrame.new(center + Vector3.new(0, 6, 0))
	a.Parent = ClassFX.Folder()
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SPARK
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Color = ColorSequence.new(HOT, FIRE)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 3
	-- (a star blinks in, twinkles twice, and goes)
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.15, 2),
		NumberSequenceKeypoint.new(0.35, 0.8), NumberSequenceKeypoint.new(0.55, 2.3), NumberSequenceKeypoint.new(0.8, 0.9),
		NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(1.2, 2)
	e.Speed = NumberRange.new(0.3, 1.2)
	e.EmissionDirection = Enum.NormalId.Top
	e.Rotation = NumberRange.new(0, 0)
	e.Rate = 110
	e.Parent = a
	task.delay(seconds, function() e.Enabled = false end)
	Debris:AddItem(a, seconds + 2.2)
end

-- A flash over the whole screen (only for players near enough to see it).
local function screenFlash(pos: Vector3, color: Color3, peak: number, fade: number)
	if not near(pos, 140) then return end
	local gui = Instance.new("ScreenGui")
	gui.Name = "ExcaliburFlash"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 90
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BorderSizePixel = 0
	f.BackgroundColor3 = color
	f.BackgroundTransparency = 1 - peak
	f.Parent = gui
	gui.Parent = player:WaitForChild("PlayerGui")
	TweenService:Create(f, TweenInfo.new(fade, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { BackgroundTransparency = 1 }):Play()
	Debris:AddItem(gui, fade + 0.1)
end

local function onAwaken(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if not char or not root then return end
	local awaken = msg.awaken :: number
	-- He raises the sword upright before him, head bowed; its flames go out,
	-- and the blade fills with light...
	holdUpright(char, awaken)
	bladeBlaze(char, awaken)
	-- ...until it breaks into a pillar of light reaching the sky (held through
	-- the swing, then it comes down as the wave)
	task.delay(math.max(awaken - 0.7, 0), function()
		if char.Parent then raisePillar(char, 0.7 + 0.45) end
	end)
	if near(root.Position, 110) then darken(awaken + (msg.inferno or 6) + 1) end
	-- (Excalibur, not the Inferno: stars of fire hanging all round him)
	if msg.inferno == 0 then
		emberStars(onGround(root.Position), 22, awaken + 0.3)
		airWindup(char, awaken)
	end
	for _, L in pairs(looks) do
		if L.char == char then
			for _, e in ipairs(L.flames) do e.Enabled = false end
			task.delay(awaken, function() for _, e in ipairs(L.flames) do e.Enabled = true end end)
			-- His hair catches fire as the armor starts to glow (and stays lit
			-- until the Inferno it's heralding is over).
			task.delay(awaken * 0.95, function()
				L.hairHold = os.clock() + awaken * 0.05 + 1
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
		-- (a warm rim only: a fill floods the whole figure orange and hides him)
		TweenService:Create(hl, TweenInfo.new(awaken * 0.6), { OutlineTransparency = 0.45 }):Play()
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
	crescent(base * CFrame.Angles(0, 0, math.rad(90)), 9, 170, 3, 0.35, 1, HOT)
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

-- A beam's shape, made of fire (Excalibur's wave): a long box of rolling
-- flame racing out from `g` along `dir` to `reach`, `height` up. The flames
-- hang where they're born, so the column keeps its beam shape and burns away
-- from the back as it fades; a white-hot core of flame runs down its middle,
-- embers fly off it, and a roaring fireball leads it. `travel`: seconds to
-- reach the end; `hold`: seconds it burns at full length before it fades.
local function fireBeam(g: Vector3, dir: Vector3, reach: number, width: number, height: number, travel: number, hold: number?)
	local d = width * 1.3
	local function holder(): BasePart
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Transparency = 1
		p.Size = Vector3.one
		p.Parent = ClassFX.Folder()
		return p
	end
	-- (spawned through the whole box and streaming forward down the line,
	-- not rising, short-lived so the column keeps a beam's straight edges)
	local function stream(e: ParticleEmitter, life: number, speed: number)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.EmissionDirection = Enum.NormalId.Front
		e.SpreadAngle = Vector2.new(6, 6)
		e.Speed = NumberRange.new(speed * 0.7, speed)
		e.Acceleration = Vector3.zero
		e.Drag = 2
		e.Lifetime = NumberRange.new(life * 0.8, life)
		e.Enabled = true
	end
	local body = holder()
	local roll = FireFX.Emitter("roll", body, d * 0.6)
	stream(roll, 0.35, 22)
	local flame = FireFX.Emitter("flame", body, d * 0.5)
	stream(flame, 0.3, 30)
	local coreHolder = holder()
	local core = FireFX.Emitter("flame", coreHolder, d * 0.3)
	stream(core, 0.22, 40)
	core.Color = FireFX.Colors(true)
	core.Brightness = 8
	local embers = FireFX.Emitter("embers", body, 0.35)
	stream(embers, 0.8, 26)
	embers.SpreadAngle = Vector2.new(30, 30)
	-- the fireball at the head
	local head = holder()
	head.Size = Vector3.one * width
	local headFire = FireFX.Emitter("roll", head, width * 2.4)
	headFire.Lifetime = NumberRange.new(0.25, 0.35)
	headFire.Speed = NumberRange.new(2, 6)
	headFire.SpreadAngle = Vector2.new(180, 180)
	headFire.Enabled = true
	local headCore = FireFX.Emitter("flame", head, width * 1.4)
	headCore.Color = FireFX.Colors(true)
	headCore.Lifetime = NumberRange.new(0.2, 0.28)
	headCore.Enabled = true
	local emitters = { roll, flame, core, embers, headFire, headCore }

	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local grow = math.min(t / travel, 1)
		local fade = math.clamp((t - travel - (hold or 0)) / 0.55, 0, 1)
		local len = math.max(reach * grow, 0.5)
		local cf = CFrame.lookAt(g, g + dir) * CFrame.new(0, height, -len / 2)
		local k = 1 - fade -- (the fire thins out as it fades)
		body.Size = Vector3.new(d * 0.8, d * 0.8, len)
		body.CFrame = cf
		coreHolder.Size = Vector3.new(d * 0.3, d * 0.3, len)
		coreHolder.CFrame = cf
		roll.Rate = len * 14 * k
		flame.Rate = len * 12 * k
		core.Rate = len * 12 * k
		embers.Rate = len * 1.5 * k
		head.CFrame = CFrame.new(g + dir * len + Vector3.new(0, height, 0))
		headFire.Rate = 60 * k
		headCore.Rate = 50 * k
		if fade >= 1 then
			if conn then conn:Disconnect() end
			for _, e in ipairs(emitters) do e.Enabled = false end
			Debris:AddItem(body, 1.3)
			Debris:AddItem(coreHolder, 1.3)
			Debris:AddItem(head, 1.3)
		end
	end)
end

-- The wave as a cone of fire: from `g` along `dir`, widening from `width`
-- at the blade to `spread` × `width` at `reach`, in segments racing out over
-- `travel`. The flames fly on forward and fan outward as they burn (they
-- don't hang where they were born), then the whole cone burns out.
local function fireCone(g: Vector3, dir: Vector3, reach: number, width: number, spread: number, height: number, travel: number)
	local N = 8
	local segs = {}
	local function holder(): BasePart
		local q = Instance.new("Part")
		q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.CastShadow = true, false, false, false, false
		q.Transparency = 1
		q.Parent = ClassFX.Folder()
		return q
	end
	local look = CFrame.lookAt(g, g + dir)
	for i = 0, N - 1 do
		local f = (i + 0.5) / N
		local w = width * (0.6 + (spread - 0.6) * f)
		local segLen = reach / N
		local q = holder()
		q.Size = Vector3.new(w, w * 0.55, segLen)
		q.CFrame = look * CFrame.new(0, height * (0.7 + 0.5 * f), -(i + 0.5) * segLen)
		local roll = FireFX.Emitter("roll", q, w * 0.55)
		local flame = FireFX.Emitter("flame", q, w * 0.4)
		local embers = FireFX.Emitter("embers", q, 0.4)
		for _, e in ipairs({ roll, flame, embers }) do
			e.Shape = Enum.ParticleEmitterShape.Box
			e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
			e.EmissionDirection = Enum.NormalId.Front
			-- (wider out at the mouth of the cone: the fire fans out more)
			e.SpreadAngle = Vector2.new(14 + 22 * f, 8 + 10 * f)
			e.Speed = NumberRange.new(16, 30)
			e.Drag = 1.2
			e.Acceleration = Vector3.new(0, 2, 0)
			e.Enabled = false
		end
		roll.Lifetime = NumberRange.new(0.5, 0.7)
		flame.Lifetime = NumberRange.new(0.4, 0.55)
		embers.Lifetime = NumberRange.new(0.8, 1.2)
		embers.SpreadAngle = Vector2.new(50, 30)
		segs[i + 1] = { at = (i / N) * travel, emitters = { roll, flame, embers }, rates = { segLen * w * 1.6, segLen * w * 1.2, segLen * 0.6 } }
		Debris:AddItem(q, travel + 0.55 + 1.4)
	end
	-- the fireball leading it
	local head = holder()
	head.Size = Vector3.one * width
	local headFire = FireFX.Emitter("roll", head, width * 2.4)
	headFire.Lifetime = NumberRange.new(0.25, 0.35)
	headFire.Speed = NumberRange.new(2, 6)
	headFire.SpreadAngle = Vector2.new(180, 180)
	headFire.Rate = 60
	headFire.Enabled = true
	Debris:AddItem(head, travel + 1)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local grow = math.min(t / travel, 1)
		head.CFrame = CFrame.new(g + dir * reach * grow + Vector3.new(0, height * 1.2, 0))
		if t >= travel then headFire.Enabled = false end
		local fade = math.clamp((t - travel) / 0.55, 0, 1)
		for _, sg in ipairs(segs) do
			if t >= sg.at then
				for j, e in ipairs(sg.emitters) do
					e.Enabled = fade < 1
					e.Rate = sg.rates[j] * (1 - fade)
				end
			end
		end
		if fade >= 1 and conn then conn:Disconnect() end
	end)
end

-- ── Excalibur's picture (after the reference: Saber's Excalibur, in fire) ──
-- Hanging four-point stars of fire all round him while the blade fills, a
-- flash and a burst of shards on the swing, a colossal blade of fire crashing
-- down at a slant onto the line, the beam of fire racing out, and where it
-- ends a giant X in a ring, a white-out, then a towering column of fire with
-- a ring whirling at its top.

-- The swing: shards of flame bursting off the blade and arcs of wind.
local function swingBurst(at: Vector3, dir: Vector3)
	FireFX.Puff("lick", CFrame.lookAt(at, at + dir), 4, 22)
	ClassFX.Burst(at, HOT, 30, 40, TEX_SPARK, 0.5, 0.45)
	for i = 1, 3 do
		local roll = rng:NextNumber(-60, 60)
		crescent(CFrame.lookAt(at, at + dir) * CFrame.Angles(0, 0, math.rad(roll)), 6 + i * 2.5, 150, 1.2, 0.3, if i % 2 == 0 then 1 else -1, EMBER)
	end
end

-- The colossal blade of fire crashing down at a slant onto `g`, from high up
-- behind the line (`dir`).
local function fallingBlade(g: Vector3, dir: Vector3, width: number)
	local from = g - dir * 14 + Vector3.new(0, 46, 0)
	local to = g + dir * 10
	local along = to - from
	fireBeam(from, along.Unit, along.Magnitude, width * 1.6, 0, 0.12)
	task.delay(0.12, function()
		FireFX.Explosion(to + Vector3.new(0, 1, 0), width, true)
		FireFX.Shockwave(to, width * 2.4)
	end)
end

-- The giant X in a ring where the wave ends: two streaks of fire crossing in
-- the upright plane facing back down the line, a ring of fire round them.
local function fireX(c: Vector3, dir: Vector3, size: number)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	for _, s2 in ipairs({ 1, -1 }) do
		local d = (Vector3.yAxis + side * s2).Unit
		fireBeam(c - d * size, d, size * 2, size * 0.28, 0, 0.08)
		-- (a crisp white-hot edge under the flames, so the X reads clean)
		SwordFX.Blade(c, d, size * 2.3, size * 0.16, HOT, 0.25)
	end
	local ring = CFrame.lookAt(c, c + dir) * CFrame.Angles(math.rad(90), 0, 0)
	SwordFX.Arc({ cf = ring, radius = size * 0.8, arc = 359, width = size * 0.3, color = FIRE, draw = 0.12, life = 0.5, grow = 0.25 })
	SwordFX.Arc({ cf = ring, radius = size * 0.8, arc = 359, width = size * 0.14, color = HOT, draw = 0.12, life = 0.45, grow = 0.25 })
	SwordFX.Arc({ cf = ring, radius = size * 1.05, arc = 359, width = size * 0.08, color = EMBER, draw = 0.16, life = 0.4, grow = 0.3 })
end

-- The towering column of fire at the end, pulsing for `seconds`, a ring
-- whirling round its top.
local function fireColumn(at: Vector3, width: number, seconds: number)
	local g = onGround(at)
	fireBeam(g, Vector3.yAxis, 70, width * 1.4, 0, 0.15, seconds)
	FireFX.Column(g, 40, width * 1.3)
	FireFX.FlameRing(g, width * 1.2, 4)
	local top = g + Vector3.new(0, 34, 0)
	SwordFX.Spiral(function() return top end, width * 1.6, seconds, FIRE)
end

-- The slam's crater (the Martial Artist's, made bigger): slabs of the floor
-- wrenched up in a ring round the impact and in two ragged ridges along the
-- edges of the cone running out from it, bursting up in a wave, glowing
-- cracks between them, rock thrown up; they stand a while, then sink back.
local CRATER_ROCK = Color3.fromRGB(120, 112, 108)
local function groundUnder(pos: Vector3): (Vector3, Color3, Enum.Material)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { ClassFX.Folder() }
	for _, pl in ipairs(Players:GetPlayers()) do
		if pl.Character then table.insert(ignore, pl.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 4, 0), Vector3.new(0, -14, 0), params)
	if hit then
		local col = hit.Instance.Color
		local mat = hit.Material
		if mat == Enum.Material.Neon or mat == Enum.Material.ForceField or mat == Enum.Material.Glass then
			mat, col = Enum.Material.Slate, CRATER_ROCK
		end
		-- (a dark floor gives paler stone, or the slabs vanish into it)
		if 0.3 * col.R + 0.59 * col.G + 0.11 * col.B < 0.3 then col = Color3.fromRGB(138, 128, 122) end
		return hit.Position, col, mat
	end
	return onGround(pos), CRATER_ROCK, Enum.Material.Slate
end

local function craterSlam(at: Vector3, dir: Vector3, cone: number, size: number)
	local g0, color, material = groundUnder(at)
	local right = Vector3.new(-dir.Z, 0, dir.X)
	local slabs: { BasePart } = {}
	local speed = 80 -- studs a second the wave runs out
	local function slab(p: Vector3, outward: Vector3, sz: Vector3, delay: number)
		local g = groundUnder(p)
		local tilt = math.rad(25 + rng:NextNumber(0, 35))
		local yaw = math.atan2(-outward.X, -outward.Z) + rng:NextNumber(-0.3, 0.3)
		local rest = CFrame.new(g) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(-tilt, 0, rng:NextNumber(-0.25, 0.25))
			* CFrame.new(0, sz.Y * 0.25, 0)
		local shade = 0.75 + rng:NextNumber(0, 0.3)
		local q = Instance.new("Part")
		q.Anchored, q.CanCollide, q.CanQuery, q.CanTouch, q.CastShadow = true, false, false, false, true
		q.Size = sz
		q.CFrame = rest * CFrame.new(0, -sz.Y, 0)
		q.Color = Color3.new(math.min(color.R * shade, 1), math.min(color.G * shade, 1), math.min(color.B * shade, 1))
		q.Material = material
		q.Parent = ClassFX.Folder()
		table.insert(slabs, q)
		task.delay(delay, function()
			if q.Parent then
				TweenService:Create(q, TweenInfo.new(0.14, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = rest }):Play()
			end
		end)
	end
	-- the ring round the impact
	local n = 16
	for i = 1, n do
		local a = (i + rng:NextNumber(-0.3, 0.3)) / n * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = size * (0.85 + rng:NextNumber(0, 0.3))
		local big = size * 0.42 * (0.8 + rng:NextNumber(0, 0.5))
		slab(g0 + out * r, out, Vector3.new(big, big * 0.6, big * 0.85), r / speed)
	end
	-- a second, broken ring inside it
	for i = 1, 8 do
		local a = (i + rng:NextNumber(-0.4, 0.4)) / 8 * math.pi * 2
		local out = Vector3.new(math.cos(a), 0, math.sin(a))
		local r = size * 0.45
		local big = size * 0.28 * (0.8 + rng:NextNumber(0, 0.4))
		slab(g0 + out * r, out, Vector3.new(big, big * 0.5, big * 0.8), r / speed)
	end
	-- the two ridges along the cone's edges (it opens to 3× at `cone`)
	for _, side in ipairs({ -1, 1 }) do
		local d = size
		while d < cone do
			local w = size * 0.5 + (d / cone) * size * 1.4
			local out = (right * side + dir * 0.3).Unit
			local p = g0 + dir * d + right * side * (w + rng:NextNumber(-1, 1))
			local big = size * 0.3 + (1 - d / cone) * size * 0.25
			slab(p, out, Vector3.new(big * (0.8 + rng:NextNumber(0, 0.5)), big * (0.5 + rng:NextNumber(0, 0.3)), big), d / speed)
			d += 2.2 + rng:NextNumber(0, 1.4)
		end
	end
	-- glowing cracks, fire and rock thrown up
	FireFX.Cracks(g0, size * 1.4, 4, true)
	FireFX.Fissures(g0, size * 1.6, 4)
	FireFX.Rocks(g0 + Vector3.new(0, 1, 0), 18, 1.4)
	FireFX.Shockwave(g0, size * 2.6)
	ClassFX.Burst(g0 + Vector3.new(0, 1, 0), Color3.fromRGB(150, 135, 125), 24, 26, TEX_SPARK, 0.6, 0.7)
	ClassFX.Sound("rockHit", g0, 1, 0.6)
	-- they stand a while, then sink back into the floor
	task.delay(4.5, function()
		for _, q in ipairs(slabs) do
			if q.Parent then
				TweenService:Create(q, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = q.CFrame * CFrame.new(0, -q.Size.Y * 1.2, 0), Transparency = 1 }):Play()
				Debris:AddItem(q, 0.95)
			end
		end
	end)
end

-- Excalibur: the blazing sword lifted overhead, then brought down, and a vast
-- wave of fire runs out down the line: a beam of fire racing along the floor
-- ahead of a wall of flame, the floor splitting under it, a column of light
-- where it ends.
local function onExcalibur(msg: any)
	local char = charOf(msg.attacker)
	local pos = msg.pos :: Vector3
	local dir = msg.dir :: Vector3
	local length, width = msg.length :: number, msg.width :: number
	local swing = tonumber(msg.swing) or 0.28
	local tier = tonumber(msg.tier) or 1
	local root = char and rootOf(char)
	if char then
		if root and msg.attacker == player then root.CFrame = CFrame.lookAt(root.Position, root.Position + dir) end
		raisePose(char, swing)
		local P = swordPillars[char]
		if P then
			P.dir = dir
			local t0 = os.clock()
			local conn: RBXScriptConnection? = nil
			conn = RunService.RenderStepped:Connect(function()
				local k = math.min((os.clock() - t0) / swing, 1)
				P.tilt = math.rad(90) * k * k -- (falling: slow, then fast)
				if k >= 1 then
					P.fade = 1
					if conn then conn:Disconnect() end
				end
			end)
		end
		task.delay(swing, function()
			if char.Parent then
				slamPose(char)
				trail(char, 0.4)
			end
		end)
	end
	-- the light gathering at the raised blade
	task.delay(swing * 0.4, function()
		local mid = char and bladeMid(char)
		if mid then FireFX.Explosion(mid, 3, false) end
	end)
	task.delay(swing, function()
		local g = onGround(pos)
		-- (stopped short by walls, like the server's wave)
		local reach = length
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = { ClassFX.Folder() }
		if char then table.insert(ignore, char) end
		local mobs = Workspace:FindFirstChild("Mobs")
		if mobs then table.insert(ignore, mobs) end
		rp.FilterDescendantsInstances = ignore
		local wall = Workspace:Raycast(g + Vector3.new(0, 2, 0), dir * length, rp)
		if wall then reach = math.max(8, wall.Distance) end
		-- the swing: a flash over everything, shards bursting off the blade,
		-- and the colossal blade of fire crashing down onto the line
		screenFlash(g, Color3.fromRGB(255, 225, 180), 0.85, 0.35)
		swingBurst(g + dir * 3 + Vector3.new(0, 3, 0), dir)
		craterSlam(g + dir * 6, dir, math.min(reach, 40), 7 + tier)
		airImpact(g + dir * 6, dir, 7 + tier)
		-- the slash
		local base = CFrame.lookAt(g + Vector3.new(0, 1.5, 0), g + Vector3.new(0, 1.5, 0) + dir)
		crescent(base * CFrame.Angles(0, 0, math.rad(90)), 9, 170, 3, 0.35, 1, HOT)
		explosion(g + dir * 4 + Vector3.new(0, 1, 0), 7, true)
		-- a beam of fire racing out along the floor
		local h = 5 + tier
		local travel = reach / 220
		fireCone(g, dir, reach, width, 3, h * 0.45, travel)
		-- the wall of fire behind it, the floor splitting
		local steps = math.floor(reach / 3)
		for i = 1, steps do
			task.delay(i * 3 / 220, function()
				local p = g + dir * (i * 3)
				eruption(p, 22 + tier * 3 + rng:NextNumber(0, 8), width * 0.75)
				FireFX.Flames(p + Vector3.new(0, 1, 0), 3.5 + tier * 0.5, 2, width * 0.5)
				if i % 2 == 0 then FireFX.Cracks(p, width * 0.8, 2.6, false) end
			end)
		end
		-- where it ends: the giant X in its ring, a white-out, then the
		-- towering column of fire with a ring whirling at its top
		task.delay(travel, function()
			local endAt = g + dir * reach
			fireX(endAt + Vector3.new(0, 7, 0), dir, 9 + tier)
			explosion(endAt + Vector3.new(0, 1, 0), 6 + tier, true)
			task.delay(0.22, function()
				screenFlash(endAt, Color3.fromRGB(255, 240, 215), 0.9, 0.5)
				FireFX.Explosion(endAt + Vector3.new(0, 1, 0), 9 + tier, true)
				fireColumn(endAt, width, 1.4)
			end)
		end)
		ClassFX.Sound("swordHit", g, 1, 0.6)
		ClassFX.Sound("fireWhoosh", g, 1, 0.6)
		ClassFX.Sound("boom", g, 0.9, 0.8)
		if near(g, 120) then deps.shake(if msg.attacker == player then 1.6 else 0.8, 0.45) end
		if msg.attacker == player then deps.fovPunch(12, 0.4) end
		if char and tier >= 3 then popWord(char, "EXCALIBUR", HOT, 28) end
	end)
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
	tornado = onTornado,
	tornadoEnd = onTornadoEnd,
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
	excalibur = onExcalibur,
	erupt = onErupt,
}

function FireKnightController.Init(d: Deps)
	deps = d
	CastPoses.addPostHook(twoHandStep)
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
			or (input.KeyCode == Enum.KeyCode.F and not processed)
			or input.KeyCode == Enum.KeyCode.ButtonR2 or input.KeyCode == Enum.KeyCode.ButtonY then
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

-- The pose functions, for previews and tests (they pose any character model).
FireKnightController.Poses = {
	swing = swingPose,
	spin = spinPose,
	quake = quakePose,
	plant = plantSword,
	raise = raisePose,
	slam = slamPose,
}

-- Effects, for previews and tests.
FireKnightController.FX = { fireBeam = fireBeam, fireCone = fireCone, raisePillar = raisePillar, craterSlam = craterSlam, airWindup = airWindup, airImpact = airImpact, emberStars = emberStars, screenFlash = screenFlash,
	swingBurst = swingBurst, fallingBlade = fallingBlade, fireX = fireX, fireColumn = fireColumn }

return FireKnightController
