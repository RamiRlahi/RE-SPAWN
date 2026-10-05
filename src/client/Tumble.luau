--!strict
--[[
	Tumble.luau
	Thrown off a mount (MountManager): the rider is flung clear and tumbles
	along the way they were riding, rolling over and over (more rolls and
	further the faster they went), flops flat on their face as the momentum
	dies, lies there a moment, then gets up in a second: pushes up on the
	hands, plants the right foot, rises onto the right leg with the left one
	still off the ground, sets the left one down, and is back to the idle.

	Every client plays it from the same plan (TumbleData): the whole body
	posed joint by joint (over the Animator, in Stepped) and kept touching the
	ground: each frame the posed parts' lowest corner is worked out and the
	body set down on the floor by it, so it bumps over head, shoulders and back
	as it rolls. The rider's own client also carries the body along the ground
	(held, as the Berserker's leaps are) and lets go once they're up.

	  Tumble.Plan(char, root, dir, speed) → plan   the rider's: from their
	                                               momentum; walls and ledges
	                                               cut it short
	  Tumble.Play(char, plan, own)                  (plan.startedAt: server time)
	  Tumble.IsPlaying(char)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local TumbleData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TumbleData"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))

local Tumble = {}

export type Plan = { dir: Vector3, speed: number, dist: number, rolls: number, yaw: number, lift: number, startedAt: number }

local BLEND_IN = 0.08
local BLEND_OUT = 0.2
local AIR_TILT = 75   -- how far over (degrees) the body has pitched by the time it hits the ground
local TOSS = 1.1      -- studs it's tossed up as it's thrown clear

-- ── Poses ───────────────────────────────────────────────────────────────────
-- Character space, degrees (as CastPoses): +rx swings an arm or leg forward,
-- +rz raises the right arm or leg out to the side (-rz the left), -rx on the
-- neck tips the head back.
type Limbs = { [string]: { number } }

-- Sat on the mount (roughly the riding pose: where it starts from).
local SEAT: Limbs = { RS = { 35, 0, 10 }, LS = { 35, 0, -10 }, RH = { 80, 0, 8 }, LH = { 80, 0, -8 }, N = { 0, 0, 0 } }
-- Flung off: arms thrown up and out, legs left behind, head snapped back.
local FLUNG: Limbs = { RS = { 150, 0, 40 }, LS = { 125, 0, -50 }, RH = { 40, 0, 14 }, LH = { -10, 0, -10 }, N = { -28, 18, 0 } }
-- Tucked for the rolls: knees to the chest, arms round them, chin down.
local TUCK: Limbs = { RS = { 80, 0, -12 }, LS = { 80, 0, 12 }, RH = { 118, 0, 8 }, LH = { 112, 0, -8 }, N = { 38, 0, 0 } }
-- Sprawled as it slaps down: arms flung out along the floor, legs straight.
local SPRAWL: Limbs = { RS = { 0, 0, 140 }, LS = { 0, 0, -135 }, RH = { -6, 0, 10 }, LH = { -2, 0, -12 }, N = { -32, 28, 0 } }
-- Lying face down, limp, cheek to the floor.
local PRONE: Limbs = { RS = { 0, 0, 118 }, LS = { 0, 0, -128 }, RH = { -4, 0, 9 }, LH = { -6, 0, -11 }, N = { -28, 40, 0 } }

-- The stand-up: [when (s), limbs, how far over the body is (degrees), and
-- how far back it sits (studs: so the hands and then the right foot stay
-- planted while the body moves over them)].
type Key = { at: number, limbs: Limbs, pitch: number, back: number }
local STAND_KEYS: { Key } = {
	{ at = 0, limbs = PRONE, pitch = 90, back = 0 },
	-- pushed up on straight arms, the body straight from the toes
	{ at = 0.27, limbs = { RS = { 55, 0, 12 }, LS = { 55, 0, -12 }, RH = { 0, 0, 5 }, LH = { 0, 0, -5 }, N = { -22, 0, 0 } }, pitch = 55, back = 0.55 },
	-- the right foot brought up and planted under the chest, left knee down
	{ at = 0.52, limbs = { RS = { 60, 0, 10 }, LS = { 60, 0, -10 }, RH = { 110, 0, 6 }, LH = { -10, 0, -6 }, N = { -12, 0, 0 } }, pitch = 50, back = 0.9 },
	-- up on the right leg, the left still off the floor behind, arms out for balance
	{ at = 0.78, limbs = { RS = { 30, 0, 24 }, LS = { 18, 0, -30 }, RH = { 12, 0, 4 }, LH = { -24, 0, -6 }, N = { 4, 0, 0 } }, pitch = 12, back = -0.25 },
	-- the left foot set down: standing
	{ at = 1.0, limbs = { RS = { 0, 0, 0 }, LS = { 0, 0, 0 }, RH = { 0, 0, 0 }, LH = { 0, 0, 0 }, N = { 0, 0, 0 } }, pitch = 0, back = 0 },
}

local KEYS = { "N", "RS", "LS", "RH", "LH" }

local function smooth(a: number): number
	a = math.clamp(a, 0, 1)
	return a * a * (3 - 2 * a)
end

local function mix(a: Limbs, b: Limbs, k: number): Limbs
	local out = {}
	for _, key in ipairs(KEYS) do
		local x, y = a[key], b[key]
		out[key] = { x[1] + (y[1] - x[1]) * k, x[2] + (y[2] - x[2]) * k, x[3] + (y[3] - x[3]) * k }
	end
	return out
end

local function add(a: Limbs, key: string, rx: number, ry: number, rz: number)
	local v = a[key]
	a[key] = { v[1] + rx, v[2] + ry, v[3] + rz }
end

-- ── The rig ────────────────────────────────────────────────────────────────
type Joint = { motor: Motor6D, basis: CFrame, c0: CFrame, c1inv: CFrame, part: BasePart }
type Rig = { root: Joint, joints: { [string]: Joint } }

local R6 = {
	N = { "Torso", "Neck" }, RS = { "Torso", "Right Shoulder" }, LS = { "Torso", "Left Shoulder" },
	RH = { "Torso", "Right Hip" }, LH = { "Torso", "Left Hip" },
}

local function joint(m: Instance?): Joint?
	if not (m and m:IsA("Motor6D") and m.Part1) then return nil end
	return { motor = m, basis = m.C0.Rotation, c0 = m.C0, c1inv = m.C1:Inverse(), part = m.Part1 :: BasePart }
end

local function rigOf(char: Model): Rig?
	local hrp = char:FindFirstChild("HumanoidRootPart")
	local root = joint(hrp and hrp:FindFirstChild("RootJoint"))
	if not root then return nil end
	local joints = {}
	for key, spec in pairs(R6) do
		local part = char:FindFirstChild(spec[1])
		local j = joint(part and part:FindFirstChild(spec[2]))
		if not j then return nil end
		joints[key] = j
	end
	return { root = root, joints = joints }
end

-- Character space → the motor's own frame (as CastPoses).
local function toMotor(j: Joint, cf: CFrame): CFrame
	return j.basis:Inverse() * cf * j.basis
end

local function limbCF(v: { number }): CFrame
	return CFrame.fromEulerAnglesXYZ(math.rad(v[1]), math.rad(v[2]), math.rad(v[3]))
end

-- The lowest corner of the posed body, relative to the root's height.
local function lowest(rig: Rig, rootT: CFrame, limbT: { [string]: CFrame }): number
	local torso = rig.root.c0 * rootT * rig.root.c1inv
	local low = math.huge
	local function corners(cf: CFrame, size: Vector3)
		local h = size / 2
		for _, sx in ipairs({ -1, 1 }) do
			for _, sy in ipairs({ -1, 1 }) do
				for _, sz in ipairs({ -1, 1 }) do
					local y = (cf * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)).Y
					if y < low then low = y end
				end
			end
		end
	end
	corners(torso, rig.root.part.Size)
	for key, j in pairs(rig.joints) do
		local size = j.part.Size
		-- (the head part is a long block; its mesh is a round head)
		if key == "N" then size = Vector3.new(1.2, 1.2, 1.2) end
		corners(torso * j.c0 * limbT[key] * j.c1inv, size)
	end
	return low
end

-- ── The floor ──────────────────────────────────────────────────────────────
local cachedParams: RaycastParams? = nil
local cachedAt = -math.huge

local function floorParams(): RaycastParams
	if cachedParams and os.clock() - cachedAt < 0.5 then return cachedParams end
	local p = RaycastParams.new()
	cachedParams, cachedAt = p, os.clock()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	for _, name in ipairs({ "Mobs", "Allies", "IceClones", "ClassFX", "BossFX", "MobFX", "RoomEmblems", "WingsMounts" }) do
		local f = Workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end
	p.FilterDescendantsInstances = ignore
	p.RespectCanCollide = true
	return p
end

local function groundY(at: Vector3, from: number?): number?
	local top = (from or at.Y) + 2
	local hit = Workspace:Raycast(Vector3.new(at.X, top, at.Z), Vector3.new(0, -40, 0), floorParams())
	return if hit then hit.Position.Y else nil
end

-- Root height above the floor standing (R6: legs 2, half the torso 1, plus
-- the HipHeight it had before riding).
local function standOf(char: Model, root: BasePart): number
	local hum = char:FindFirstChildOfClass("Humanoid")
	local base = char:GetAttribute("BaseHipHeight")
	local hip = if typeof(base) == "number" then base else (if hum and not char:GetAttribute("Riding") then hum.HipHeight else 0)
	if hum and hum.RigType ~= Enum.HumanoidRigType.R6 then return hip + root.Size.Y / 2 end
	return 3 + hip
end

-- ── Little touches: dust, thumps, the camera ───────────────────────────────
local DUST = Color3.fromRGB(150, 138, 120)
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

local function dust(at: Vector3, count: number, size: number)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = ClassFX.Folder()
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SMOKE
	e.Color = ColorSequence.new(DUST)
	e.LightEmission = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, size * 0.5), NumberSequenceKeypoint.new(1, size * 1.6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.45), NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(0.5, 0.9)
	e.Speed = NumberRange.new(3, 7)
	e.SpreadAngle = Vector2.new(80, 15)
	e.EmissionDirection = Enum.NormalId.Top
	e.Acceleration = Vector3.new(0, 1.5, 0)
	e.Drag = 4
	e.RotSpeed = NumberRange.new(-60, 60)
	e.Rate = 0
	e.Parent = anchor
	e:Emit(count)
	Debris:AddItem(anchor, 1.3)
end

local function shake(amount: number, dur: number)
	local cam = Workspace.CurrentCamera
	if not cam then return end
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < dur do
			local a = amount * (1 - (os.clock() - t0) / dur)
			cam.CFrame *= CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
			RunService.RenderStepped:Wait()
		end
	end)
end

-- ── The plan ───────────────────────────────────────────────────────────────
function Tumble.Plan(char: Model, root: BasePart, dir: Vector3, speed: number): Plan
	local flat = Vector3.new(dir.X, 0, dir.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else Vector3.new(0, 0, -1)
	local want = TumbleData.Plan(speed).dist + 1.5
	local room = math.min(SafeMove.ClampDash(root, flat, want), SafeMove.ClampToFloor(root, flat, want))
	local p = TumbleData.Plan(speed, room)
	-- (the body starts facing where it faced, and swings round to the way it's thrown)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	local yaw = 0
	if look.Magnitude > 0.01 then
		look = look.Unit
		yaw = math.atan2(flat:Cross(look).Y, flat:Dot(look))
	end
	local g = groundY(root.Position)
	local lift = if g then math.max(0, root.Position.Y - g - standOf(char, root)) else 0
	return { dir = flat, speed = p.speed, dist = p.dist, rolls = p.rolls, yaw = yaw, lift = lift,
		startedAt = Workspace:GetServerTimeNow() }
end

-- ── Playing ────────────────────────────────────────────────────────────────
type Hold = { ap: AlignPosition, ao: AlignOrientation, att: Attachment }
type Play = {
	char: Model, rig: Rig, plan: Plan, times: TumbleData.Times, t0: number, own: boolean,
	start: Vector3, stand: number, hold: Hold?, lastPitch: number, landed: boolean, slapped: boolean,
	planted: { [string]: boolean },
}
local plays: { [Model]: Play } = {}
local conns: { RBXScriptConnection } = {}

-- The pose at time t: the limbs, and the body's turn (degrees: pitch over
-- forward, yaw, roll), how far back it sits, and how much it's set on the
-- floor (0 in the air: carried by the root).
type Frame = { limbs: Limbs, pitch: number, yaw: number, roll: number, back: number, ground: number }

local function frameAt(p: Play, t: number): Frame
	local plan, T = p.plan, p.times
	local yaw = math.deg(plan.yaw) * (1 - smooth(t / math.max(T.air, 0.05)))
	if t < T.move then
		local u = t / T.move
		local s = TumbleData.Travel(u)
		local ground = smooth(t / math.max(T.air, 0.05))
		if plan.rolls == 0 then
			-- Just falls over: flung, then sprawling down onto the face.
			local limbs = mix(SEAT, FLUNG, smooth(t / 0.1))
			limbs = mix(limbs, SPRAWL, smooth((u - 0.3) / 0.6))
			return { limbs = limbs, pitch = 90 * u * u, yaw = yaw, roll = 0, back = 0, ground = ground }
		end
		local total = 360 * plan.rolls + 90
		local sAir = TumbleData.Travel(T.air / T.move)
		local pitch
		if t < T.air then
			pitch = AIR_TILT * smooth(t / T.air)
		else
			pitch = AIR_TILT + (total - AIR_TILT) * math.clamp((s - sAir) / math.max(1 - sAir, 1e-3), 0, 1)
		end
		local limbs: Limbs
		if t < T.air then
			limbs = mix(SEAT, FLUNG, smooth(t / 0.1))
			-- (flailing)
			local w = 1 - smooth((t - T.air + 0.08) / 0.08)
			add(limbs, "RS", math.sin(t * 23) * 20 * w, 0, math.cos(t * 17) * 14 * w)
			add(limbs, "LS", math.sin(t * 19 + 1) * 20 * w, 0, -math.cos(t * 21) * 14 * w)
			add(limbs, "RH", math.sin(t * 20) * 16 * w, 0, 0)
			add(limbs, "LH", -math.sin(t * 20) * 16 * w, 0, 0)
		else
			limbs = mix(FLUNG, TUCK, smooth((t - T.air) / 0.12))
		end
		-- the last quarter turn: unfolding, flat onto the face
		local flop = smooth((pitch - 360 * plan.rolls) / 90)
		limbs = mix(limbs, SPRAWL, flop)
		-- (rolls aren't clean: the body twists and lolls a little as it goes)
		local roll = math.sin(math.rad(pitch) * 0.5 + 0.6) * 9 * (1 - flop) * ground
		add(limbs, "RS", math.sin(math.rad(pitch)) * 7 * (1 - flop), 0, 0)
		add(limbs, "RH", -math.sin(math.rad(pitch) + 1) * 6 * (1 - flop), 0, 0)
		return { limbs = limbs, pitch = pitch, yaw = yaw, roll = roll, back = 0, ground = ground }
	end
	t -= T.move
	if t < T.lie then
		-- Face down, still; a breath or two, the head lolling round.
		local limbs = mix(SPRAWL, PRONE, smooth(t / 0.25))
		add(limbs, "N", 0, math.sin(t * 4) * 4, 0)
		return { limbs = limbs, pitch = 90 + math.sin(t * 9) * 1.2, yaw = 0, roll = 0, back = 0, ground = 1 }
	end
	t -= T.lie
	-- The stand-up.
	local a, b = STAND_KEYS[1], STAND_KEYS[#STAND_KEYS]
	for i = 1, #STAND_KEYS - 1 do
		if t < STAND_KEYS[i + 1].at then
			a, b = STAND_KEYS[i], STAND_KEYS[i + 1]
			break
		end
	end
	local k = if b.at > a.at then smooth((t - a.at) / (b.at - a.at)) else 1
	return { limbs = mix(a.limbs, b.limbs, k), pitch = a.pitch + (b.pitch - a.pitch) * k, yaw = 0, roll = 0,
		back = a.back + (b.back - a.back) * k, ground = 1 }
end

local function stopHold(p: Play)
	local h = p.hold
	if not h then return end
	p.hold = nil
	h.ap:Destroy()
	h.ao:Destroy()
	h.att:Destroy()
	local hum = p.char:FindFirstChildOfClass("Humanoid")
	local root = p.char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hum and hum.Parent then
		hum.PlatformStand = false
		hum.AutoRotate = true
	end
	if root and root.Parent then
		root.AssemblyLinearVelocity = Vector3.zero
		SafeMove.SnapToFloor(root, p.stand)
	end
end

local function finish(p: Play)
	stopHold(p)
	plays[p.char] = nil
end

-- The rider's own body: carried along the floor (and tossed clear at first).
local function moveOwn(p: Play, t: number, root: BasePart)
	local h = p.hold
	if not h then return end
	local plan, T = p.plan, p.times
	local u = math.clamp(t / T.move, 0, 1)
	local at = p.start + plan.dir * plan.dist * TumbleData.Travel(u)
	local g = groundY(at, root.Position.Y) or (root.Position.Y - p.stand)
	local lift = 0
	if t < T.air then
		local a = t / T.air
		lift = plan.lift * (1 - a) ^ 2 + TOSS * 4 * a * (1 - a)
	end
	h.ap.Position = Vector3.new(at.X, g + p.stand + lift, at.Z)
end

-- Little moments: hitting the ground, each roll's thump, the face slap,
-- the hands and feet planting as they get up.
local function beats(p: Play, t: number, f: Frame, root: BasePart)
	local T = p.times
	local floor = (groundY(root.Position) or (root.Position.Y - 3)) + 0.2
	local here = Vector3.new(root.Position.X, floor, root.Position.Z)
	if not p.landed and t >= T.air then
		p.landed = true
		dust(here, 10, 2.4)
		ClassFX.Sound("punch", here, 0.9, 0.75)
		ClassFX.Sound("rockHit", here, 0.35, 0.9)
		if p.own then shake(0.9, 0.22) end
	end
	-- (a thump each half turn on the ground: shoulders, then back)
	if p.landed and t < T.move then
		local was, now = math.floor((p.lastPitch - AIR_TILT) / 180), math.floor((f.pitch - AIR_TILT) / 180)
		if now > was and f.pitch < 360 * p.plan.rolls then
			local fade = 1 - (t / T.move)
			dust(here, 5, 1.6)
			ClassFX.Sound("punch", here, 0.35 + 0.35 * fade, 0.9 + math.random() * 0.15)
			if p.own then shake(0.35 * fade + 0.1, 0.12) end
		end
	end
	p.lastPitch = f.pitch
	if not p.slapped and t >= T.move - 0.05 then
		p.slapped = true
		dust(here + p.plan.dir * 1.2, 12, 2.2)
		ClassFX.Sound("punch", here, 0.8, 0.65)
		if p.own then shake(0.6, 0.18) end
	end
	local st = t - T.move - T.lie
	for _, beat in ipairs({ { "hands", 0.24, 4 }, { "right", 0.5, 3 }, { "left", 0.97, 2 } }) do
		local name, at, n = beat[1] :: string, beat[2] :: number, beat[3] :: number
		if not p.planted[name] and st >= at then
			p.planted[name] = true
			dust(here, n, 1.1)
		end
	end
end

local function step()
	local now = os.clock()
	for char, p in pairs(plays) do
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not char.Parent or not root or not hum or hum.Health <= 0 then
			finish(p)
			continue
		end
		local t = now - p.t0
		local T = p.times
		if t >= T.total + BLEND_OUT then
			finish(p)
			continue
		end
		if t >= T.total then stopHold(p) end
		local f = frameAt(p, math.min(t, T.total))
		if p.own and t < T.total then moveOwn(p, t, root) end
		beats(p, t, f, root)

		-- the pose, in each motor's own frame
		local limbT: { [string]: CFrame } = {}
		for key, j in pairs(p.rig.joints) do
			limbT[key] = toMotor(j, limbCF(f.limbs[key]))
		end
		local turn = CFrame.Angles(0, math.rad(f.yaw), 0) * CFrame.Angles(-math.rad(f.pitch), 0, 0) * CFrame.Angles(0, 0, math.rad(f.roll))
		-- set down on the floor by its lowest point
		local low = lowest(p.rig, toMotor(p.rig.root, CFrame.new(0, 0, f.back) * turn), limbT)
		local g = groundY(root.Position) or (root.Position.Y - p.stand)
		local drop = -((root.Position.Y - g) + low) + 0.03
		local rootT = toMotor(p.rig.root, CFrame.new(0, drop * f.ground, f.back) * turn)

		-- blended in from whatever was playing, and back out to it at the end
		local w = 1
		if t < BLEND_IN then
			w = t / BLEND_IN
		elseif t > T.total then
			w = 1 - (t - T.total) / BLEND_OUT
		end
		local root_ = p.rig.root.motor
		root_.Transform = if w >= 1 then rootT else root_.Transform:Lerp(rootT, w)
		for key, j in pairs(p.rig.joints) do
			j.motor.Transform = if w >= 1 then limbT[key] else j.motor.Transform:Lerp(limbT[key], w)
		end
	end
	if next(plays) == nil then
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end
end

function Tumble.IsPlaying(char: Model): boolean
	return plays[char] ~= nil
end

function Tumble.Play(char: Model, plan: Plan, own: boolean)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char:FindFirstChildOfClass("Humanoid")
	local rig = rigOf(char)
	if not root or not hum or not rig then return end
	local old = plays[char]
	if old then finish(old) end
	local times = TumbleData.Times(plan)
	-- (others start late, by however long the plan took to reach them)
	local late = math.clamp(Workspace:GetServerTimeNow() - plan.startedAt, 0, times.total)
	local p: Play = {
		char = char, rig = rig, plan = plan, times = times, t0 = os.clock() - late, own = own,
		start = root.Position, stand = standOf(char, root), hold = nil, lastPitch = 0,
		landed = false, slapped = false, planted = {},
	}
	if own then
		local att = Instance.new("Attachment")
		att.Name = "TumbleMove"
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
		ao.CFrame = CFrame.lookAt(Vector3.zero, plan.dir)
		ao.Parent = root
		hum.AutoRotate = false
		hum.PlatformStand = true
		p.hold = { ap = ap, ao = ao, att = att }
		-- (flung off with a whoosh)
		ClassFX.Sound("whoosh", root, 0.7, 0.8)
	end
	plays[char] = p
	if #conns == 0 then
		table.insert(conns, RunService.Stepped:Connect(function()
			local ok, err = pcall(step)
			if not ok then warn("[Tumble]", err) end
		end))
	end
end

return Tumble
