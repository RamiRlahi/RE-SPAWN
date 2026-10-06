--[[
	DragonBossFX.luau
	Ignarath, the dragon boss (server: DragonBoss), on every client:

	  • animates its wings, neck, jaw and legs from the server's "DragonState"
	  • draws its fire (breath, fireballs, explosions, the beam charge), wing
	    gusts, quakes, roars, the boss intro and the boss health bar
	  • knockback on your own character (your game owns its physics)
	  • the Inferno Beam minigame: you're handed a huge metal shield and must
	    press the arrow keys shown before the beam breaks through
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ContextActionService = game:GetService("ContextActionService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DragonBossFX = {}

local FIRE_TEXTURE = "rbxassetid://11534281007"
local SPARK_TEXTURE = "rbxasset://textures/particles/sparkles_main.dds"
local SMOKE_TEXTURE = "rbxasset://textures/particles/smoke_main.dds"
local FLAME = Color3.fromRGB(255, 130, 40)
local FLAME_DEEP = Color3.fromRGB(200, 40, 10)
local FLAME_HOT = Color3.fromRGB(255, 235, 180)
local GOLD = Color3.fromRGB(255, 215, 120)
local FLAT = CFrame.Angles(0, 0, math.rad(90))

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function fxFolder(): Instance
	local f = Workspace:FindFirstChild("DragonClientFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "DragonClientFX"
		f.Parent = Workspace
	end
	return f
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = fxFolder()
	return p
end

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local e = Instance.new("ParticleEmitter")
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Rate = 0
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
	return e
end

local function seq(...: number): NumberSequence
	local args = { ... }
	local kps = {}
	for i = 1, #args, 2 do
		table.insert(kps, NumberSequenceKeypoint.new(args[i], args[i + 1]))
	end
	return NumberSequence.new(kps)
end

-- A one-shot particle burst at `pos`.
local function burst(pos: Vector3, props: { [string]: any }, count: number)
	local holder = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(pos) })
	local att = Instance.new("Attachment")
	att.Parent = holder
	local e = emitter(att, props)
	e:Emit(count)
	Debris:AddItem(holder, 3)
end

local function flashLight(pos: Vector3, color: Color3, brightness: number, range: number, life: number)
	local holder = part({ Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(pos) })
	local l = Instance.new("PointLight")
	l.Color = color
	l.Brightness = brightness
	l.Range = range
	l.Parent = holder
	TweenService:Create(l, TweenInfo.new(life), { Brightness = 0 }):Play()
	Debris:AddItem(holder, life + 0.1)
end

local shakeUntil, shakePower = 0, 0
local function shake(power: number, duration: number)
	if power > shakePower or os.clock() > shakeUntil then shakePower = power end
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

local function shakeNear(pos: Vector3, power: number, reach: number, duration: number)
	local root = myRoot()
	if not root then return end
	local d = (root.Position - pos).Magnitude
	if d < reach then shake(power * (1 - d / reach) + power * 0.2, duration) end
end

-- ── Which dragons are about, and whether we're in one's arena ───────────────
type Rig = {
	model: Model,
	body: BasePart,
	head: BasePart?,
	motors: { [string]: Motor6D },
	cur: { [string]: number }, -- the eased joint angles (see POSES)
	phase: number,
	walk: number,
	yaw: number,
	snapAt: number,
}
local rigs: { [Model]: Rig } = {}

local function scanDragons()
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then
		for _, m in ipairs(mobs:GetChildren()) do
			if m:IsA("Model") and m:GetAttribute("BossKind") == "dragon" and not rigs[m] then
				local body = m:FindFirstChild("Body")
				if body and body:IsA("BasePart") then
					local motors = {}
					for _, d in ipairs(m:GetDescendants()) do
						if d:IsA("Motor6D") then motors[d.Name] = d end
					end
					rigs[m] = {
						model = m, body = body, head = m:FindFirstChild("Head") :: BasePart?, motors = motors,
						cur = {}, phase = 0, walk = 0, yaw = 0, snapAt = 0,
					}
				end
			end
		end
	end
	for m in pairs(rigs) do
		if not m.Parent then rigs[m] = nil end
	end
end

local function inArena(model: Model, pad: number?): boolean
	local root = myRoot()
	local lo, hi = model:GetAttribute("ArenaMin"), model:GetAttribute("ArenaMax")
	if not root or typeof(lo) ~= "Vector3" or typeof(hi) ~= "Vector3" then return false end
	local p, e = root.Position, pad or 4
	return p.X >= lo.X - e and p.X <= hi.X + e and p.Z >= lo.Z - e and p.Z <= hi.Z + e and math.abs(p.Y - lo.Y) < 25
end

local function mouthOf(model: Model): Vector3
	local head = model:FindFirstChild("Head")
	local m = head and head:FindFirstChild("DragonMouth")
	if m and m:IsA("Attachment") then return m.WorldPosition end
	return model:GetPivot().Position
end

-- ── Animation ───────────────────────────────────────────────────────────────
-- The dragon (DragonBuilder) crouches on the ground; every joint eases toward
-- the pose of the server's current "DragonState". Degrees:
--   freq/amp/bias  wing flap (Hz, either side, resting raise)
--   fold           wing elbow (- sweeps the hand back)
--   nb/nm/nk       neck base / middle / head pitch (+ = down)
--   jaw            jaw open
--   armL/armR      forelegs (- = raised forward)
--   foreL/foreR    forearms
type Pose = { [string]: number }
local POSES: { [string]: Pose } = {
	idle         = { freq = 0.35, amp = 4,  bias = 0 },
	breathWindup = { freq = 0.4,  amp = 5,  bias = 8,  nb = -18, nm = -10, nk = -14, jaw = 9 },
	breath       = { freq = 0.5,  amp = 5,  bias = 6,  nb = 12,  nm = 8,   nk = 16,  jaw = 20 },
	spit         = { freq = 0.5,  amp = 6,  bias = 4,  nk = 4 },
	gust         = { freq = 2.2,  amp = 38, bias = 6,  nb = -6,  nk = -6,  jaw = 8, fold = 10 },
	rise         = { freq = 0.8,  amp = 10, bias = 15, nb = -10, nk = -10, jaw = 13, armL = -60, armR = -60, foreL = 50, foreR = 50 },
	slam         = { freq = 0.3,  amp = 4,  bias = 4,  nk = 14,  jaw = 17, armL = 10, armR = 10, foreL = -10, foreR = -10 },
	swipeWindup  = { freq = 0.4,  amp = 5,  bias = 8,  nb = -6,  nk = -8,  jaw = 12, armR = -85, foreR = 60 },
	swipe        = { freq = 0.4,  amp = 5,  bias = 4,  nk = 10,  jaw = 17, armR = 20, foreR = -30 },
	roar         = { freq = 0.6,  amp = 8,  bias = 18, nb = -22, nm = -12, nk = -22, jaw = 25, fold = 12 },
	beamCharge   = { freq = 0.4,  amp = 4,  bias = 12, nb = -14, nk = -16, jaw = 9 },
	beam         = { freq = 0.2,  amp = 2,  bias = 14, nb = 4,   nm = 4,   nk = 6,   jaw = 22 },
	stunned      = { freq = 0,    amp = 0,  bias = -30, nb = 22, nm = 16,  nk = 20,  jaw = 8, fold = -20, armL = 20, armR = 20 },
	dead         = { freq = 0,    amp = 0,  bias = -40, nb = 28, nm = 20,  nk = 26,  jaw = 14, fold = -30 },
}
local JOINT_KEYS = { "freq", "amp", "bias", "fold", "nb", "nm", "nk", "jaw", "armL", "armR", "foreL", "foreR" }

local function nearestPlayerTo(pos: Vector3): Vector3?
	local best, bestD = nil, 90
	for _, plr in ipairs(Players:GetPlayers()) do
		local r = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if r then
			local d = (r.Position - pos).Magnitude
			if d < bestD then best, bestD = r.Position, d end
		end
	end
	return best
end

local function setT(r: Rig, name: string, cf: CFrame)
	local m = r.motors[name]
	if m then m.Transform = cf end
end

local function animate(dt: number)
	local now = os.clock()
	for m, r in pairs(rigs) do
		if not m.Parent then
			rigs[m] = nil
			continue
		end
		local state = m:GetAttribute("DragonState") or "idle"
		local p = POSES[state] or POSES.idle
		local k = math.min(1, dt * (if state == "swipe" or state == "slam" then 16 else 5))
		for _, key in ipairs(JOINT_KEYS) do
			local want = p[key] or 0
			if key == "freq" and m:GetAttribute("Enraged") then want *= 1.3 end
			r.cur[key] = (r.cur[key] or 0) + (want - (r.cur[key] or 0)) * k
		end
		local c = r.cur
		r.phase += dt * c.freq * math.pi * 2
		local snap = math.max(0, 1 - (now - r.snapAt) / 0.35) * 18
		local jaw = math.max(c.jaw, snap)

		-- Eyes on the nearest player: the turn spread down the neck.
		local wantYaw = 0
		if state ~= "beam" and state ~= "breath" and state ~= "dead" and state ~= "stunned" then
			local target = nearestPlayerTo(r.body.Position)
			if target then
				local rel = r.body.CFrame:PointToObjectSpace(target)
				wantYaw = math.clamp(math.deg(math.atan2(rel.X, rel.Z)), -45, 45)
			end
		end
		r.yaw += (wantYaw - r.yaw) * math.min(1, dt * 3)
		local breathe = math.sin(now * 1.3) * 1.5
		setT(r, "NeckBase", CFrame.Angles(0, math.rad(r.yaw * 0.4), 0) * CFrame.Angles(math.rad(c.nb + breathe), 0, 0))
		setT(r, "NeckMid", CFrame.Angles(0, math.rad(r.yaw * 0.3), 0) * CFrame.Angles(math.rad(c.nm - breathe * 0.5), 0, 0))
		setT(r, "Neck", CFrame.Angles(0, math.rad(r.yaw * 0.3), 0) * CFrame.Angles(math.rad(c.nk), 0, 0))
		setT(r, "Jaw", CFrame.Angles(math.rad(jaw + math.sin(now * 2.1) * 1.5), 0, 0))

		-- Wings: flap about the body's length, the hands sweeping as they go.
		local flap = c.bias + c.amp * math.sin(r.phase)
		local sweep = c.fold + c.amp * 0.35 * math.sin(r.phase - 0.8)
		setT(r, "LeftShoulder", CFrame.Angles(0, 0, math.rad(flap)))
		setT(r, "RightShoulder", CFrame.Angles(0, 0, -math.rad(flap)))
		setT(r, "LeftElbow", CFrame.Angles(0, math.rad(sweep), 0))
		setT(r, "RightElbow", CFrame.Angles(0, math.rad(sweep), 0))

		-- Legs: a prowling gait while it moves, else planted.
		local v = r.body.AssemblyLinearVelocity
		local speed = Vector3.new(v.X, 0, v.Z).Magnitude
		r.walk += dt * math.min(speed, 14) * 0.45
		local gait = math.clamp(speed / 6, 0, 1) * (if state == "idle" then 1 else 0)
		local s1, s2 = math.sin(r.walk) * 16 * gait, math.sin(r.walk + math.pi) * 16 * gait
		setT(r, "LeftArm", CFrame.Angles(math.rad(c.armL + s1), 0, 0))
		setT(r, "RightArm", CFrame.Angles(math.rad(c.armR + s2), 0, 0))
		setT(r, "LeftForearm", CFrame.Angles(math.rad(c.foreL - math.max(s1, 0) * 0.8), 0, 0))
		setT(r, "RightForearm", CFrame.Angles(math.rad(c.foreR - math.max(s2, 0) * 0.8), 0, 0))
		setT(r, "LeftHip", CFrame.Angles(math.rad(s2 * 0.7), 0, 0))
		setT(r, "RightHip", CFrame.Angles(math.rad(s1 * 0.7), 0, 0))

		-- The tail never stops moving.
		local lash = if m:GetAttribute("Enraged") or state == "gust" or state == "roar" then 11 else 5
		if state == "dead" then lash = 0 end
		for i = 1, 7 do
			setT(r, "Tail" .. i, CFrame.Angles(math.rad(math.sin(now * 0.9 - i * 0.5) * 2), math.rad(math.sin(now * 1.1 - i * 0.55) * lash), 0))
		end
	end
end

-- ── Knockback on your own character ─────────────────────────────────────────
local function knockSelf(from: Vector3, power: number, lift: number)
	local root = myRoot()
	if not root or root.Anchored then return end
	local dir = flat(root.Position - from)
	dir = if dir.Magnitude > 0.1 then dir.Unit else -flat(root.CFrame.LookVector).Unit
	local DUR = 0.28
	local dist = SafeMove.ClampDash(root, dir, power * DUR)
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	lv.VectorVelocity = dir * (dist / DUR)
	lv.Parent = root
	root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, lift, root.AssemblyLinearVelocity.Z)
	task.delay(DUR, function()
		lv:Destroy()
		att:Destroy()
		if root.Parent then
			local v = root.AssemblyLinearVelocity
			root.AssemblyLinearVelocity = Vector3.new(v.X * 0.3, v.Y, v.Z * 0.3)
		end
	end)
end

-- ── Fire ────────────────────────────────────────────────────────────────────
-- ── The beam meeting the shield ─────────────────────────────────────────────
-- Fire crackling along the beam like lightning, a white-hot flare where it
-- strikes the shield, and the fire SPREADING out over and around the shield:
-- branching fire-lightning and flame licks flung out sideways in every
-- direction across its face.
local clashToken = 0

local function fireBolt(a: Vector3, b: Vector3, width: number, life: number, jag: number)
	local dir = b - a
	local len = dir.Magnitude
	if len < 0.1 then return end
	local side = dir:Cross(Vector3.yAxis)
	if side.Magnitude < 0.01 then side = Vector3.xAxis end
	side = side.Unit
	local up = dir.Unit:Cross(side)
	local steps = math.clamp(math.floor(len / 2.2), 3, 14)
	local prev = a
	for s = 1, steps do
		local t = s / steps
		local nxt = if s == steps then b else a + dir * t
			+ (side * (math.random() - 0.5) + up * (math.random() - 0.5)) * jag
		local mid = (prev + nxt) / 2
		local l = (nxt - prev).Magnitude
		-- (deep orange with a gold core: pale cores just bloom into white)
		for _, layer in ipairs({ { w = width, c = Color3.fromRGB(235, 70, 12), tr = 0 }, { w = width * 0.4, c = Color3.fromRGB(255, 175, 60), tr = 0 } }) do
			local seg = part({ Size = Vector3.new(layer.w, layer.w, l + layer.w * 0.5), CFrame = CFrame.lookAt(mid, nxt),
				Color = layer.c, Transparency = layer.tr })
			TweenService:Create(seg, TweenInfo.new(life), { Transparency = 1 }):Play()
			Debris:AddItem(seg, life + 0.05)
		end
		prev = nxt
	end
end

local function clash(model: Model, front: Attachment)
	clashToken += 1
	local my = clashToken
	-- the white-hot flare on the shield's face
	local flare = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2.2, Color = Color3.fromRGB(255, 160, 50), Transparency = 0.25,
		CFrame = front.WorldCFrame })
	local halo = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4.5, Color = Color3.fromRGB(230, 70, 15), Transparency = 0.8,
		CFrame = front.WorldCFrame })
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 14
	light.Brightness = 1.5
	light.Parent = flare
	local t0 = os.clock()
	local nextCrackle, nextSpread = 0, 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		if clashToken ~= my or not front.Parent or not model.Parent or now - t0 > 15 then
			conn:Disconnect()
			for _, p in ipairs({ flare, halo }) do
				TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1, Size = p.Size * 1.6 }):Play()
				Debris:AddItem(p, 0.3)
			end
			return
		end
		local hit = front.WorldPosition
		local mouth = mouthOf(model)
		local toward = (mouth - hit)
		toward = if toward.Magnitude > 0.1 then toward.Unit else Vector3.zAxis
		-- the shield plane: two directions across its face
		local across = toward:Cross(Vector3.yAxis)
		across = if across.Magnitude > 0.01 then across.Unit else Vector3.xAxis
		local upFace = across:Cross(toward).Unit
		local pulse = 1 + 0.18 * math.sin(now * 40) + 0.1 * math.sin(now * 23)
		flare.CFrame = CFrame.new(hit + toward * 0.6)
		flare.Size = Vector3.one * 2.2 * pulse
		halo.CFrame = CFrame.new(hit + toward * 0.4)
		halo.Size = Vector3.one * 4.5 * pulse
		light.Brightness = 1.2 + 0.6 * pulse
		-- crackling fire-lightning along the beam
		if now >= nextCrackle then
			nextCrackle = now + 0.05
			fireBolt(mouth, hit + toward * 0.5, 0.7, 0.12, 3.2)
			fireBolt(mouth, hit + toward * 0.5, 0.45, 0.1, 4.6)
		end
		-- the spread: branching fire-lightning and flame licks thrown outward
		-- across the shield's face (and a little back toward the dragon)
		if now >= nextSpread then
			nextSpread = now + 0.035
			for _ = 1, 6 do
				local a = math.random() * math.pi * 2
				local out = (across * math.cos(a) + upFace * math.sin(a)).Unit
				local len = 9 + math.random() * 11
				local tip = hit + out * len + toward * (math.random() * 2.5)
				fireBolt(hit + toward * 0.4, tip, 0.6 + math.random() * 0.35, 0.22, 2.4)
				if math.random() < 0.4 then
					-- a fork off the branch
					local mid = hit + out * len * 0.55 + toward * 0.8
					local fork = (out + (across * (math.random() - 0.5) + upFace * (math.random() - 0.5))).Unit
					fireBolt(mid, mid + fork * (3 + math.random() * 5), 0.4, 0.18, 1.4)
				end
			end
			burst(hit + toward * 0.6, { Texture = FIRE_TEXTURE, Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, FLAME_HOT), ColorSequenceKeypoint.new(0.4, FLAME), ColorSequenceKeypoint.new(1, FLAME_DEEP) }),
				Size = seq(0, 3.4, 1, 0.5), Transparency = seq(0, 0, 1, 1), Lifetime = NumberRange.new(0.3, 0.55),
				Speed = NumberRange.new(20, 38), SpreadAngle = Vector2.new(180, 180), Drag = 3 }, 9)
		end
	end)
end

local function explode(at: Vector3, radius: number, color: Color3?)
	local c = color or FLAME
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(at + Vector3.new(0, 1, 0)),
		Color = FLAME_HOT, Transparency = 0.1 })
	TweenService:Create(ball, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * radius * 2, Transparency = 1, Color = c }):Play()
	Debris:AddItem(ball, 0.4)
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2),
		CFrame = CFrame.new(at + Vector3.new(0, 0.25, 0)) * FLAT, Color = c, Transparency = 0.2 })
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.1, radius * 2.6, radius * 2.6), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.5)
	burst(at + Vector3.new(0, 1, 0), { Texture = FIRE_TEXTURE, Color = ColorSequence.new(FLAME_HOT, c),
		Size = seq(0, 3, 1, 0.5), Transparency = seq(0, 0.1, 1, 1), Lifetime = NumberRange.new(0.4, 0.7),
		Speed = NumberRange.new(10, 22), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 10, 0) }, 30)
	burst(at + Vector3.new(0, 1, 0), { Texture = SPARK_TEXTURE, Color = ColorSequence.new(FLAME_HOT, c),
		Size = seq(0, 0.6, 1, 0), Lifetime = NumberRange.new(0.4, 0.9), Speed = NumberRange.new(20, 40),
		SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, -40, 0) }, 24)
	burst(at + Vector3.new(0, 1, 0), { Texture = SMOKE_TEXTURE, LightEmission = 0, Color = ColorSequence.new(Color3.fromRGB(60, 45, 40)),
		Size = seq(0, 3, 1, 7), Transparency = seq(0, 0.5, 1, 1), Lifetime = NumberRange.new(0.8, 1.4),
		Speed = NumberRange.new(4, 9), SpreadAngle = Vector2.new(180, 180) }, 10)
	flashLight(at + Vector3.new(0, 3, 0), c, 6, radius * 3, 0.5)
	shakeNear(at, 0.9, 40, 0.3)
end

local function fireball(model: Model, to: Vector3, t: number)
	local from = mouthOf(model)
	local r = rigs[model]
	if r then r.snapAt = os.clock() end
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(2.6, 2.6, 2.6), CFrame = CFrame.new(from),
		Color = FLAME, Transparency = 0.05 })
	ball:AddTag("EnemyProjectile")
	local core = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(1.5, 1.5, 1.5), CFrame = CFrame.new(from),
		Color = FLAME_HOT, Transparency = 0 })
	local att = Instance.new("Attachment")
	att.Parent = ball
	emitter(att, { Texture = FIRE_TEXTURE, Color = ColorSequence.new(FLAME_HOT, FLAME_DEEP), Size = seq(0, 2.6, 1, 0.4),
		Transparency = seq(0, 0.1, 1, 1), Lifetime = NumberRange.new(0.25, 0.45), Speed = NumberRange.new(0.5, 2),
		SpreadAngle = Vector2.new(180, 180), Rate = 70 })
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 14
	light.Brightness = 3
	light.Parent = ball
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / t, 0, 1)
		local pos = from:Lerp(to + Vector3.new(0, 1, 0), a) + Vector3.new(0, 4 * 11 * a * (1 - a), 0)
		ball.CFrame = CFrame.new(pos)
		core.CFrame = CFrame.new(pos)
		if a >= 1 then
			conn:Disconnect()
			ball:Destroy()
			core:Destroy()
		end
	end)
end

-- The flame cone: a jet from the (animated) mouth, sweeping `from` → `to`.
local function breathFX(model: Model, duration: number, range: number, from: Vector3, to: Vector3)
	local floorY = model:GetAttribute("FloorY") or model:GetPivot().Position.Y - 8
	local att = Instance.new("Attachment")
	att.Parent = Workspace.Terrain
	local jet = emitter(att, { Texture = FIRE_TEXTURE, Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, FLAME_HOT), ColorSequenceKeypoint.new(0.35, FLAME), ColorSequenceKeypoint.new(1, FLAME_DEEP) }),
		Size = seq(0, 1.5, 0.4, 6, 1, 11), Transparency = seq(0, 0.2, 0.7, 0.35, 1, 1),
		Lifetime = NumberRange.new(0.5, 0.6), SpreadAngle = Vector2.new(13, 13),
		EmissionDirection = Enum.NormalId.Front, Rate = 170, Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90) })
	local core = emitter(att, { Texture = SPARK_TEXTURE, Color = ColorSequence.new(Color3.new(1, 1, 1), FLAME_HOT),
		Size = seq(0, 1.2, 1, 3), Transparency = seq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.25, 0.35),
		SpreadAngle = Vector2.new(5, 5), EmissionDirection = Enum.NormalId.Front, Rate = 90 })
	local smoke = emitter(att, { Texture = SMOKE_TEXTURE, LightEmission = 0, Color = ColorSequence.new(Color3.fromRGB(70, 50, 45)),
		Size = seq(0, 3, 1, 10), Transparency = seq(0, 0.7, 1, 1), Lifetime = NumberRange.new(0.8, 1.2),
		SpreadAngle = Vector2.new(20, 20), EmissionDirection = Enum.NormalId.Front, Rate = 25 })
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 30
	light.Brightness = 5
	light.Parent = att
	local t0 = os.clock()
	local lastPuff = 0
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local now = os.clock()
		local a = math.clamp((now - t0) / duration, 0, 1)
		local dir = from:Lerp(to, a)
		dir = if dir.Magnitude > 0.01 then dir.Unit else from
		local m = mouthOf(model)
		local aim = Vector3.new(m.X, floorY, m.Z) + dir * range * 0.72
		att.WorldCFrame = CFrame.lookAt(m, aim)
		local dist = (aim - m).Magnitude
		jet.Speed = NumberRange.new(dist / 0.55 * 0.85, dist / 0.55 * 1.05)
		core.Speed = NumberRange.new(dist / 0.3 * 0.6, dist / 0.3 * 0.8)
		smoke.Speed = NumberRange.new(dist / 1.0 * 0.5, dist / 1.0 * 0.7)
		-- The floor catches: bursts of flame along the cone.
		if now - lastPuff > 0.07 then
			lastPuff = now
			local along = 8 + math.random() * (range - 8)
			local side = (math.random() * 2 - 1) * along * 0.35
			local right = Vector3.new(-dir.Z, 0, dir.X)
			local p = Vector3.new(m.X, floorY + 0.5, m.Z) + dir * along + right * side
			burst(p, { Texture = FIRE_TEXTURE, Color = ColorSequence.new(FLAME_HOT, FLAME_DEEP), Size = seq(0, 2.5, 1, 0.5),
				Transparency = seq(0, 0.2, 1, 1), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(3, 8),
				SpreadAngle = Vector2.new(25, 25), EmissionDirection = Enum.NormalId.Top, Acceleration = Vector3.new(0, 6, 0) }, 5)
		end
		if a >= 1 or not model.Parent then
			conn:Disconnect()
			jet.Enabled, core.Enabled, smoke.Enabled = false, false, false
			TweenService:Create(light, TweenInfo.new(0.4), { Brightness = 0 }):Play()
			Debris:AddItem(att, 1.5)
		end
	end)
	shakeNear(mouthOf(model), 0.35, 60, duration)
end

local function beamCharge(model: Model, t: number)
	local orb = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(0.5, 0.5, 0.5), Color = FLAME_HOT, Transparency = 0.1,
		CFrame = CFrame.new(mouthOf(model)) })
	local shell = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(14, 14, 14), Transparency = 1, CFrame = orb.CFrame })
	emitter(shell, { Texture = SPARK_TEXTURE, Color = ColorSequence.new(FLAME_HOT, FLAME), Size = seq(0, 0.2, 1, 0.8),
		Transparency = seq(0, 1, 0.3, 0.2, 1, 0), Lifetime = NumberRange.new(0.5, 0.6), Speed = NumberRange.new(12, 14),
		Shape = Enum.ParticleEmitterShape.Sphere, ShapeInOut = Enum.ParticleEmitterShapeInOut.Inward,
		ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface, Rate = 80 })
	local light = Instance.new("PointLight")
	light.Color = FLAME
	light.Range = 4
	light.Brightness = 3
	light.Parent = orb
	TweenService:Create(orb, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Size = Vector3.new(4.5, 4.5, 4.5) }):Play()
	TweenService:Create(light, TweenInfo.new(t), { Range = 26, Brightness = 6 }):Play()
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function()
		local p = mouthOf(model)
		orb.CFrame = CFrame.new(p)
		shell.CFrame = CFrame.new(p)
		if os.clock() - t0 >= t or not model.Parent then
			conn:Disconnect()
			orb:Destroy()
			shell:Destroy()
		end
	end)
	shakeNear(mouthOf(model), 0.25, 80, t)
end

local function gustFX(at: Vector3, radius: number)
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(1.2, 6, 6), Material = Enum.Material.SmoothPlastic,
		CFrame = CFrame.new(at + Vector3.new(0, 1, 0)) * FLAT, Color = Color3.fromRGB(210, 200, 190), Transparency = 0.55 })
	TweenService:Create(ring, TweenInfo.new(0.55, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.2, radius * 2.2, radius * 2.2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)
	for i = 1, 16 do
		local a = i / 16 * math.pi * 2
		local dir = Vector3.new(math.cos(a), 0, math.sin(a))
		burst(at + dir * radius * 0.5 + Vector3.new(0, 1, 0), { Texture = SMOKE_TEXTURE, LightEmission = 0,
			Color = ColorSequence.new(Color3.fromRGB(150, 140, 130)), Size = seq(0, 2, 1, 6), Transparency = seq(0, 0.5, 1, 1),
			Lifetime = NumberRange.new(0.6, 1), Speed = NumberRange.new(20, 30), SpreadAngle = Vector2.new(15, 15),
			EmissionDirection = Enum.NormalId.Front }, 2)
	end
	shakeNear(at, 0.6, radius * 1.6, 0.4)
end

local function quakeFX(at: Vector3, radius: number)
	explode(at, radius * 0.5, Color3.fromRGB(255, 150, 60))
	for _, s in ipairs({ 0, 0.12 }) do
		task.delay(s, function()
			local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 4, 4),
				CFrame = CFrame.new(at + Vector3.new(0, 0.3, 0)) * FLAT, Color = FLAME, Transparency = 0.1 })
			TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
				{ Size = Vector3.new(0.1, radius * 2.3, radius * 2.3), Transparency = 1 }):Play()
			Debris:AddItem(ring, 0.55)
		end)
	end
	for _ = 1, 14 do
		local a = math.random() * math.pi * 2
		local chunk = Instance.new("Part")
		chunk.Size = Vector3.new(1, 1, 1) * (0.6 + math.random() * 1.2)
		chunk.Color = Color3.fromRGB(70, 62, 66)
		chunk.Material = Enum.Material.Slate
		chunk.CanCollide = false
		chunk.CanQuery = false
		chunk.CanTouch = false
		chunk.CFrame = CFrame.new(at + Vector3.new(math.cos(a), 0.8, math.sin(a)) * (2 + math.random() * radius * 0.5))
		chunk.Parent = fxFolder()
		chunk.AssemblyLinearVelocity = Vector3.new(math.cos(a) * 18, 30 + math.random() * 20, math.sin(a) * 18)
		Debris:AddItem(chunk, 1.4)
	end
	shakeNear(at, 1.4, 60, 0.5)
end

local function roarFX(model: Model, enrage: boolean)
	local m = mouthOf(model)
	for i = 0, 2 do
		task.delay(i * 0.22, function()
			local wave = part({ Shape = Enum.PartType.Ball, Size = Vector3.new(4, 4, 4), Material = Enum.Material.ForceField,
				CFrame = CFrame.new(m), Color = if enrage then Color3.fromRGB(255, 80, 40) else Color3.fromRGB(255, 200, 150), Transparency = 0.2 })
			TweenService:Create(wave, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ Size = Vector3.new(60, 60, 60), Transparency = 1 }):Play()
			Debris:AddItem(wave, 1)
		end)
	end
	shakeNear(m, 1.1, 150, 1.4)
	if enrage and inArena(model, 20) then
		local gui = Instance.new("ScreenGui")
		gui.Name = "DragonRageFlash"
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 130
		gui.Parent = player:WaitForChild("PlayerGui")
		local f = Instance.new("Frame")
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.fromRGB(255, 40, 20)
		f.BackgroundTransparency = 0.6
		f.BorderSizePixel = 0
		f.Parent = gui
		TweenService:Create(f, TweenInfo.new(1.2), { BackgroundTransparency = 1 }):Play()
		Debris:AddItem(gui, 1.3)
	end
end

-- ── Banners (the boss intro, its fall, a reflected beam) ────────────────────
local function banner(small: string, big: string, color: Color3, hold: number?)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DragonBanner"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 140
	gui.Parent = player:WaitForChild("PlayerGui")
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.28)
	holder.Size = UDim2.fromOffset(900, 150)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local top = Instance.new("TextLabel")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 28)
	top.Font = Enum.Font.GothamBold
	top.TextSize = 22
	top.TextColor3 = Color3.fromRGB(235, 220, 200)
	top.TextStrokeTransparency = 0.4
	top.Text = small
	top.Parent = holder
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 30)
	title.Size = UDim2.new(1, 0, 0, 84)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 76
	title.TextColor3 = color
	title.TextStrokeColor3 = Color3.fromRGB(40, 10, 0)
	title.TextStrokeTransparency = 0.2
	title.Text = big
	title.Parent = holder
	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 120)
	rule.Size = UDim2.fromOffset(0, 3)
	rule.BackgroundColor3 = color
	rule.BorderSizePixel = 0
	rule.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 1.25
	scale.Parent = holder
	for _, l in ipairs({ top, title }) do l.TextTransparency = 1 end
	TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(top, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(title, TweenInfo.new(0.4), { TextTransparency = 0 }):Play()
	TweenService:Create(rule, TweenInfo.new(0.6, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = UDim2.fromOffset(520, 3) }):Play()
	task.delay(hold or 2.4, function()
		for _, l in ipairs({ top, title }) do
			TweenService:Create(l, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		TweenService:Create(rule, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		Debris:AddItem(gui, 0.7)
	end)
end

-- ── The boss health bar ─────────────────────────────────────────────────────
local barGui: ScreenGui? = nil
local barFill: Frame? = nil
local barTrail: Frame? = nil
local barName: TextLabel? = nil
local barTag: TextLabel? = nil
local trail = 1

local function buildBar()
	local gui = Instance.new("ScreenGui")
	gui.Name = "DragonBossBar"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 58
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local frame = Instance.new("Frame")
	frame.AnchorPoint = Vector2.new(0.5, 0)
	frame.Position = UDim2.new(0.5, 0, 0, 92) -- under the run timer / Threat panel
	frame.Size = UDim2.fromOffset(560, 46)
	frame.BackgroundTransparency = 1
	frame.Parent = gui
	local name = Instance.new("TextLabel")
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 20)
	name.Font = Enum.Font.GothamBlack
	name.TextSize = 17
	name.TextColor3 = Color3.fromRGB(255, 225, 190)
	name.TextStrokeTransparency = 0.35
	name.Text = "IGNARATH, THE CINDER WYRM"
	name.Parent = frame
	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.AnchorPoint = Vector2.new(1, 0)
	tag.Position = UDim2.new(1, 0, 0, 2)
	tag.Size = UDim2.fromOffset(120, 18)
	tag.Font = Enum.Font.GothamBlack
	tag.TextSize = 13
	tag.TextXAlignment = Enum.TextXAlignment.Right
	tag.TextColor3 = Color3.fromRGB(255, 80, 50)
	tag.TextStrokeTransparency = 0.4
	tag.Text = "ENRAGED"
	tag.Visible = false
	tag.Parent = frame
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 24)
	back.Size = UDim2.new(1, 0, 0, 16)
	back.BackgroundColor3 = Color3.fromRGB(20, 12, 12)
	back.BackgroundTransparency = 0.15
	back.BorderSizePixel = 0
	back.Parent = frame
	back.BackgroundColor3 = Color3.fromRGB(14, 9, 9)
	back.BackgroundTransparency = 0.05
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(200, 160, 90) -- a gold frame
	stroke.Thickness = 2
	stroke.Parent = back
	local phase = Instance.new("TextLabel")
	phase.Name = "Phase"
	phase.BackgroundTransparency = 1
	phase.Position = UDim2.fromOffset(0, 2)
	phase.Size = UDim2.fromOffset(120, 18)
	phase.Font = Enum.Font.GothamBold
	phase.TextSize = 12
	phase.TextXAlignment = Enum.TextXAlignment.Left
	phase.TextColor3 = Color3.fromRGB(220, 190, 140)
	phase.TextStrokeTransparency = 0.5
	phase.Text = "PHASE I"
	phase.Parent = frame
	local tr = Instance.new("Frame")
	tr.Size = UDim2.fromScale(1, 1)
	tr.BackgroundColor3 = Color3.fromRGB(255, 240, 220)
	tr.BorderSizePixel = 0
	tr.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(230, 60, 30)
	fill.BorderSizePixel = 0
	fill.Parent = back
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(Color3.fromRGB(255, 150, 60), Color3.fromRGB(200, 30, 20))
	grad.Rotation = 90
	grad.Parent = fill
	-- Marks where it calls its Inferno Beam (and enrages, at half).
	for _, at in ipairs({ 0.75, 0.5, 0.45, 0.2 }) do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0)
		tick.Position = UDim2.fromScale(at, 0)
		tick.Size = UDim2.new(0, 2, 1, 0)
		tick.BackgroundColor3 = if at == 0.5 then Color3.fromRGB(255, 80, 50) else GOLD
		tick.BorderSizePixel = 0
		tick.ZIndex = 3
		tick.Parent = back
	end
	barGui, barFill, barTrail, barName, barTag = gui, fill, tr, name, tag
end

local rimPlayers: (boolean) -> () -- (defined below, with the other effects)

local function updateBar(dt: number)
	local shown: Model? = nil
	for m in pairs(rigs) do
		local hum = m:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 and inArena(m, 6) then
			shown = m
			break
		end
	end
	-- In its arena the camera pulls back and leans toward it (IsometricCamera),
	-- so the dragon stays in view as in the concept art.
	rimPlayers(shown ~= nil)
	if shown then
		player:SetAttribute("CameraZoom", 1.75)
		local body = shown:FindFirstChild("Body")
		player:SetAttribute("CameraBias", if body and body:IsA("BasePart") then body.Position else nil)
	elseif player:GetAttribute("CameraZoom") ~= nil then
		player:SetAttribute("CameraZoom", nil)
		player:SetAttribute("CameraBias", nil)
	end
	if not shown then
		if barGui then barGui.Enabled = false end
		return
	end
	if not barGui then buildBar() end
	local hum = shown:FindFirstChildOfClass("Humanoid") :: Humanoid
	local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
	trail = if trail < frac then frac else trail + (frac - trail) * math.min(1, dt * 3)
	;(barGui :: ScreenGui).Enabled = true
	;(barFill :: Frame).Size = UDim2.fromScale(frac, 1)
	;(barTrail :: Frame).Size = UDim2.fromScale(trail, 1)
	;(barTag :: TextLabel).Visible = shown:GetAttribute("Enraged") == true
	local ph = (barGui :: ScreenGui):FindFirstChild("Phase", true) :: TextLabel?
	if ph then ph.Text = if shown:GetAttribute("Enraged") == true then "PHASE II" else "PHASE I" end
end

-- ── The shield minigame ─────────────────────────────────────────────────────
local beamResult = Network.GetRemoteEvent(Network.Remotes.DragonBeamResult)
local ARROW_ROT = { Up = 0, Right = 90, Down = 180, Left = -90 }
local KEY_OF: { [Enum.KeyCode]: string } = {
	[Enum.KeyCode.Up] = "Up", [Enum.KeyCode.Down] = "Down", [Enum.KeyCode.Left] = "Left", [Enum.KeyCode.Right] = "Right",
	[Enum.KeyCode.W] = "Up", [Enum.KeyCode.S] = "Down", [Enum.KeyCode.A] = "Left", [Enum.KeyCode.D] = "Right",
	[Enum.KeyCode.DPadUp] = "Up", [Enum.KeyCode.DPadDown] = "Down", [Enum.KeyCode.DPadLeft] = "Left", [Enum.KeyCode.DPadRight] = "Right",
}
local ACTION = "DragonShieldArrows"

type BeamUI = {
	gui: ScreenGui,
	token: number,
	keys: { string },
	step: number,
	opensAt: number,
	deadline: number,
	duration: number,
	lockedUntil: number,
	finished: boolean,
	tiles: { Frame },
	row: Frame,
	title: TextLabel,
	sub: TextLabel,
	timer: Frame,
	heat: Frame,
	conn: RBXScriptConnection?,
}
local ui: BeamUI? = nil

local TILE, GAP = 62, 10
local TILE_IDLE = Color3.fromRGB(34, 26, 26)
local TILE_DONE = Color3.fromRGB(70, 190, 90)
local TILE_BAD = Color3.fromRGB(220, 50, 40)

-- Tiles are nearly see-through: a thin outline and a glowing white / gold
-- arrow, no dark box behind it. The next arrow pulses (see the minigame's
-- RenderStepped); pressed ones turn to a green check.
-- While the shield holds, everything but the minigame (and the boss bar)
-- is hidden, so the arrows are the focus; restored after.
local hiddenHud: { ScreenGui } = {}
local KEEP_GUI = { DragonShieldGame = true, DragonGrabShield = true, DragonBossBar = true, DragonBanner = true }
local function focusHud(on: boolean)
	if on then
		for _, g in ipairs(player:WaitForChild("PlayerGui"):GetChildren()) do
			if g:IsA("ScreenGui") and g.Enabled and not KEEP_GUI[g.Name] and g.DisplayOrder < 900 then
				g.Enabled = false
				table.insert(hiddenHud, g)
			end
		end
	else
		for _, g in ipairs(hiddenHud) do
			if g.Parent then g.Enabled = true end
		end
		hiddenHud = {}
	end
end

local function styleTile(tile: Frame, mode: string)
	local stroke = tile:FindFirstChildOfClass("UIStroke") :: UIStroke
	local glyph = tile:FindFirstChild("Glyph") :: TextLabel
	local scale = tile:FindFirstChildOfClass("UIScale") :: UIScale
	tile.BackgroundTransparency = 0.88
	glyph.TextStrokeTransparency = 0.35
	if mode == "next" then
		tile.BackgroundColor3 = GOLD
		stroke.Color = GOLD
		stroke.Thickness = 2
		stroke.Transparency = 0
		glyph.TextColor3 = Color3.new(1, 0.97, 0.88)
		glyph.TextStrokeColor3 = Color3.fromRGB(255, 170, 60)
		glyph.TextTransparency = 0
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1.15 }):Play()
	elseif mode == "done" then
		tile.BackgroundColor3 = TILE_DONE
		stroke.Color = Color3.fromRGB(150, 255, 170)
		stroke.Thickness = 1.5
		stroke.Transparency = 0.2
		glyph.Text = "✓"
		glyph.Rotation = 0
		glyph.TextColor3 = Color3.fromRGB(170, 255, 185)
		glyph.TextStrokeColor3 = Color3.fromRGB(40, 140, 60)
		glyph.TextTransparency = 0
		scale.Scale = 1.3
		TweenService:Create(scale, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 0.9 }):Play()
	elseif mode == "wait" then
		tile.BackgroundColor3 = Color3.new(1, 1, 1)
		tile.BackgroundTransparency = 0.95
		stroke.Color = Color3.fromRGB(255, 235, 200)
		stroke.Thickness = 1
		stroke.Transparency = 0.55
		glyph.TextColor3 = Color3.new(1, 1, 1)
		glyph.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
		glyph.TextTransparency = 0.4
		scale.Scale = 1
	end
end

local function endMinigame(success: boolean?)
	local u = ui
	if not u then return end
	ui = nil
	focusHud(false)
	ContextActionService:UnbindAction(ACTION)
	if u.conn then u.conn:Disconnect() end
	if success ~= nil then
		u.title.Text = if success then "REFLECTED!" else "THE SHIELD BROKE!"
		u.title.TextColor3 = if success then GOLD else TILE_BAD
		u.sub.Text = if success then "Ignarath is stunned. Strike now!" else ""
	end
	for _, l in ipairs({ u.title, u.sub }) do
		TweenService:Create(l, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.9),
			{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
	for _, t in ipairs(u.tiles) do
		TweenService:Create(t, TweenInfo.new(0.3), { BackgroundTransparency = 1 }):Play()
		local g = t:FindFirstChild("Glyph") :: TextLabel?
		if g then TweenService:Create(g, TweenInfo.new(0.3), { TextTransparency = 1 }):Play() end
		local s = t:FindFirstChildOfClass("UIStroke")
		if s then TweenService:Create(s, TweenInfo.new(0.3), { Transparency = 1 }):Play() end
	end
	TweenService:Create(u.heat, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
	u.timer.Parent.Visible = false
	Debris:AddItem(u.gui, 1.6)
end

local function press(name: string?)
	local u = ui
	if not u or u.finished or not name then return end
	local now = os.clock()
	if now < u.opensAt or now < u.lockedUntil then return end
	local want = u.keys[u.step + 1]
	if not want then return end
	if name == want then
		u.step += 1
		styleTile(u.tiles[u.step], "done")
		beamResult:FireServer(u.token, u.step)
		shake(0.25, 0.08)
		if u.step >= #u.keys then
			u.finished = true
			u.sub.Text = "THE SHIELD HOLDS!"
		else
			styleTile(u.tiles[u.step + 1], "next")
		end
	else
		-- A slip: the beam bites, the row shudders, a beat before you can recover.
		u.lockedUntil = now + 0.35
		local tile = u.tiles[u.step + 1]
		tile.BackgroundColor3 = TILE_BAD
		task.delay(0.3, function()
			if ui == u and not u.finished then styleTile(tile, "next") end
		end)
		local x0 = u.row.Position
		task.spawn(function()
			for i = 1, 6 do
				u.row.Position = x0 + UDim2.fromOffset(if i % 2 == 0 then 8 else -8, 0)
				task.wait(0.03)
			end
			u.row.Position = x0
		end)
		shake(0.6, 0.15)
	end
end

local function startMinigame(token: number, keys: { string }, windup: number, duration: number)
	endMinigame(nil)
	focusHud(true)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DragonShieldGame"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 950
	gui.Parent = player:WaitForChild("PlayerGui")

	-- The heat of the beam at the screen's edges.
	local heat = Instance.new("Frame")
	heat.Size = UDim2.fromScale(1, 1)
	heat.BackgroundColor3 = Color3.fromRGB(255, 90, 20)
	heat.BackgroundTransparency = 1
	heat.BorderSizePixel = 0
	heat.Parent = gui
	local hg = Instance.new("UIGradient")
	hg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.18, 0.85),
		NumberSequenceKeypoint.new(0.82, 0.85), NumberSequenceKeypoint.new(1, 0) })
	hg.Parent = heat

	local n = #keys
	local width = n * TILE + (n - 1) * GAP
	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 0.7, -64)
	title.Size = UDim2.fromOffset(800, 50)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 42
	title.TextColor3 = GOLD
	title.TextStrokeColor3 = Color3.fromRGB(60, 20, 0)
	title.TextStrokeTransparency = 0.1
	title.Text = "HOLD THE SHIELD!"
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 1)
	sub.Position = UDim2.new(0.5, 0, 0.7, -40)
	sub.Size = UDim2.fromOffset(800, 24)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 20
	sub.TextColor3 = Color3.fromRGB(255, 235, 215)
	sub.TextStrokeTransparency = 0.3
	sub.Text = "BRACE YOURSELF…"
	sub.Parent = gui

	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0.5)
	row.Position = UDim2.fromScale(0.5, 0.7)
	row.Size = UDim2.fromOffset(width, TILE)
	row.BackgroundTransparency = 1
	row.Parent = gui
	local tiles: { Frame } = {}
	for i, k in ipairs(keys) do
		local tile = Instance.new("Frame")
		tile.Position = UDim2.fromOffset((i - 1) * (TILE + GAP), 0)
		tile.Size = UDim2.fromOffset(TILE, TILE)
		tile.BackgroundColor3 = TILE_IDLE
		tile.BorderSizePixel = 0
		tile.Parent = row
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 10)
		corner.Parent = tile
		local stroke = Instance.new("UIStroke")
		stroke.Parent = tile
		local scale = Instance.new("UIScale")
		scale.Parent = tile
		local glyph = Instance.new("TextLabel")
		glyph.Name = "Glyph"
		glyph.BackgroundTransparency = 1
		glyph.AnchorPoint = Vector2.new(0.5, 0.5)
		glyph.Position = UDim2.fromScale(0.5, 0.5)
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Font = Enum.Font.GothamBlack
		glyph.TextSize = 34
		glyph.Text = "▲"
		glyph.Rotation = ARROW_ROT[k] or 0
		glyph.Parent = tile
		styleTile(tile, "wait")
		-- Touch screens tap the tiles' arrows instead (a d-pad below).
		tiles[i] = tile
	end

	local timerBack = Instance.new("Frame")
	timerBack.AnchorPoint = Vector2.new(0.5, 0)
	timerBack.Position = UDim2.new(0.5, 0, 0.7, TILE / 2 + 14)
	timerBack.Size = UDim2.fromOffset(math.max(width, 300), 10)
	timerBack.BackgroundColor3 = Color3.fromRGB(25, 15, 15)
	timerBack.BorderSizePixel = 0
	timerBack.Parent = gui
	local tc = Instance.new("UICorner")
	tc.CornerRadius = UDim.new(1, 0)
	tc.Parent = timerBack
	local timer = Instance.new("Frame")
	timer.Size = UDim2.fromScale(1, 1)
	timer.BackgroundColor3 = Color3.fromRGB(150, 140, 130)
	timer.BorderSizePixel = 0
	timer.Parent = timerBack
	local tc2 = Instance.new("UICorner")
	tc2.CornerRadius = UDim.new(1, 0)
	tc2.Parent = timer

	-- On a touch screen: a d-pad to tap.
	if UserInputService.TouchEnabled then
		local pad = Instance.new("Frame")
		pad.AnchorPoint = Vector2.new(1, 1)
		pad.Position = UDim2.new(1, -30, 1, -30)
		pad.Size = UDim2.fromOffset(200, 200)
		pad.BackgroundTransparency = 1
		pad.Parent = gui
		for k, pos in pairs({ Up = { 70, 0 }, Down = { 70, 140 }, Left = { 0, 70 }, Right = { 140, 70 } }) do
			local b = Instance.new("TextButton")
			b.Position = UDim2.fromOffset(pos[1], pos[2])
			b.Size = UDim2.fromOffset(60, 60)
			b.BackgroundColor3 = TILE_IDLE
			b.BackgroundTransparency = 0.1
			b.Font = Enum.Font.GothamBlack
			b.TextSize = 30
			b.TextColor3 = Color3.new(1, 1, 1)
			b.Text = "▲"
			b.Rotation = ARROW_ROT[k]
			b.Parent = pad
			local c = Instance.new("UICorner")
			c.CornerRadius = UDim.new(0, 12)
			c.Parent = b
			b.Activated:Connect(function() press(k) end)
		end
	end

	local now = os.clock()
	local u: BeamUI = {
		gui = gui, token = token, keys = keys, step = 0, opensAt = now + windup, deadline = now + windup + duration,
		duration = duration, lockedUntil = 0, finished = false, tiles = tiles, row = row, title = title, sub = sub,
		timer = timer, heat = heat, conn = nil,
	}
	ui = u
	ContextActionService:BindActionAtPriority(ACTION, function(_, state, input)
		if state == Enum.UserInputState.Begin then press(KEY_OF[input.KeyCode]) end
		return Enum.ContextActionResult.Sink
	end, false, 3000, Enum.KeyCode.Up, Enum.KeyCode.Down, Enum.KeyCode.Left, Enum.KeyCode.Right,
		Enum.KeyCode.W, Enum.KeyCode.A, Enum.KeyCode.S, Enum.KeyCode.D,
		Enum.KeyCode.DPadUp, Enum.KeyCode.DPadDown, Enum.KeyCode.DPadLeft, Enum.KeyCode.DPadRight)

	local opened = false
	u.conn = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		if t < u.opensAt then
			timer.Size = UDim2.fromScale(1 - (u.opensAt - t) / windup, 1)
			heat.BackgroundTransparency = 1 - 0.25 * (1 - (u.opensAt - t) / windup)
			return
		end
		if not opened then
			opened = true
			sub.Text = "PRESS WASD OR ARROW KEYS!"
			timer.BackgroundColor3 = GOLD
			if u.step < #u.keys then styleTile(tiles[u.step + 1], "next") end
		end
		local left = math.clamp((u.deadline - t) / u.duration, 0, 1)
		timer.Size = UDim2.fromScale(left, 1)
		timer.BackgroundColor3 = GOLD:Lerp(TILE_BAD, 1 - left)
		heat.BackgroundTransparency = 0.72 - 0.1 * math.sin(t * 9) - (1 - left) * 0.2
		if not u.finished then
			shake(0.12, 0.05)
			local nxt = tiles[u.step + 1]
			local sc = nxt and nxt:FindFirstChildOfClass("UIScale")
			if sc then sc.Scale = 1.12 + 0.06 * math.sin(t * 9) end
		end
		-- Never stuck: the server's answer should come first.
		if t > u.deadline + 3 then endMinigame(false) end
	end)
end

-- The brace: feet planted wide, leaning into the shield with both arms.
local function bracePose(): { [string]: { number } }
	local lean, front, back, sp = -12, 28, 32, 9
	local p: { [string]: { number } } = {}
	p.W = { lean, 0, 0 }
	p.LH = { front - lean, 0, -sp }
	p.RH = { -back - lean, 0, sp }
	local legs = math.rad((front + back) / 2)
	local drop = (1 - math.cos(math.rad(lean))) + 2 * (1 - math.cos(legs)) + 2 * (1 - math.cos(math.rad(sp)))
	p.Root = { 0, 0, 0, 0, -drop, 0 }
	p.RS = { 80 - lean, 0, 20 }
	p.LS = { 80 - lean, 0, -20 }
	p.N = { 8, 0, 0 }
	return p
end

local function shieldPose(char: Model, on: boolean)
	local p = bracePose()
	if on then
		CastPoses.play(char, {
			{ dur = 0.22, style = Enum.EasingStyle.Back, pose = p },
			{ dur = 14, pose = p, wobble = function(t)
				local b = math.sin(t * 24) * 1.4
				return { RS = { b, 0, 0 }, LS = { -b, 0, 0 }, N = { b * 0.5, 0, 0 } }
			end },
		}, 0.3, true)
	else
		CastPoses.play(char, { { dur = 0.05, pose = p } }, 0.35, true)
	end
end

-- ── The beam's mood: the arena reddens and darkens while it charges and fires
local moodUntil = 0
local function arenaMood(seconds: number)
	local Lighting = game:GetService("Lighting")
	local cc = Lighting:FindFirstChild("DragonMood") :: ColorCorrectionEffect?
	if not cc then
		local c = Instance.new("ColorCorrectionEffect")
		c.Name = "DragonMood"
		c.Parent = Lighting
		cc = c
	end
	local fx = cc :: ColorCorrectionEffect
	moodUntil = os.clock() + seconds
	TweenService:Create(fx, TweenInfo.new(0.6), { TintColor = Color3.fromRGB(255, 196, 180), Brightness = -0.08, Contrast = 0.12 }):Play()
	task.delay(seconds, function()
		if os.clock() >= moodUntil - 0.05 then
			TweenService:Create(fx, TweenInfo.new(0.8), { TintColor = Color3.new(1, 1, 1), Brightness = 0, Contrast = 0 }):Play()
		end
	end)
end

-- Players in the arena get a thin warm rim, so they read against the dragon.
rimPlayers = function(on: boolean)
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local h = char:FindFirstChild("DragonRim") :: Highlight?
			if on and not h then
				local n = Instance.new("Highlight")
				n.Name = "DragonRim"
				n.FillTransparency = 1
				n.OutlineColor = Color3.fromRGB(255, 232, 196)
				n.OutlineTransparency = 0.35
				n.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
				n.Parent = char
			elseif not on and h then
				h:Destroy()
			end
		end
	end
end

-- ── Events ──────────────────────────────────────────────────────────────────
local function onFX(data: any)
	if typeof(data) ~= "table" then return end
	local kind = data.kind
	if kind == "knock" then
		if typeof(data.from) == "Vector3" then knockSelf(data.from, data.power or 50, data.lift or 15) end
	elseif kind == "fireball" then
		if typeof(data.model) == "Instance" and typeof(data.to) == "Vector3" then fireball(data.model, data.to, data.t or 1) end
	elseif kind == "explode" then
		if typeof(data.at) == "Vector3" then explode(data.at, data.radius or 7) end
	elseif kind == "breath" then
		if typeof(data.model) == "Instance" then
			breathFX(data.model, data.duration or 1.6, data.range or 44, data.from, data.to)
		end
	elseif kind == "gust" then
		if typeof(data.at) == "Vector3" then gustFX(data.at, data.radius or 30) end
	elseif kind == "quake" then
		if typeof(data.at) == "Vector3" then quakeFX(data.at, data.radius or 18) end
	elseif kind == "roar" then
		if typeof(data.model) == "Instance" then roarFX(data.model, data.enrage == true) end
	elseif kind == "intro" then
		if typeof(data.model) == "Instance" then
			roarFX(data.model, false)
			if inArena(data.model, 30) then banner(data.title or "", data.name or "", Color3.fromRGB(255, 120, 50), 2.6) end
		end
	elseif kind == "death" then
		if typeof(data.model) == "Instance" then
			shakeNear(data.model:GetPivot().Position, 1.2, 150, 1.2)
			if inArena(data.model, 30) then banner("VICTORY", "IGNARATH HAS FALLEN", GOLD, 3) end
		end
	elseif kind == "shield" then
		if typeof(data.char) == "Instance" and data.char:IsA("Model") then shieldPose(data.char, data.on == true) end
	elseif kind == "beamCharge" then
		if typeof(data.model) == "Instance" then
			beamCharge(data.model, data.t or 1.6)
			if inArena(data.model, 30) then arenaMood((data.t or 1.6) + 9) end
		end
	elseif kind == "beamStop" then
		clashToken += 1
	elseif kind == "beamFire" then
		if typeof(data.model) == "Instance" and typeof(data.front) == "Instance" and data.front:IsA("Attachment") then
			clash(data.model, data.front)
		end
		if typeof(data.model) == "Instance" then
			local m = mouthOf(data.model)
			burst(m, { Texture = FIRE_TEXTURE, Color = ColorSequence.new(FLAME_HOT, FLAME), Size = seq(0, 3, 1, 0.5),
				Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(10, 20), SpreadAngle = Vector2.new(180, 180) }, 25)
			shakeNear(m, 0.8, 90, 0.4)
		end
	elseif kind == "reflect" then
		arenaMood(0.5)
		if typeof(data.model) == "Instance" then
			local m = mouthOf(data.model)
			task.delay(0.3, function()
				explode(m, 12, GOLD)
				shakeNear(m, 1.6, 150, 0.6)
			end)
			if typeof(data.from) == "Vector3" then explode(data.from, 6, GOLD) end
			if inArena(data.model, 30) then banner("THE BEAM IS THROWN BACK", "REFLECTED!", GOLD, 1.6) end
		end
	elseif kind == "beamBreak" then
		arenaMood(0.8)
		if typeof(data.at) == "Vector3" then explode(data.at, 10, Color3.fromRGB(255, 80, 30)) end
	end
end

-- ── "GRAB THE SHIELD!" ───────────────────────────────────────────────────────
-- The dragon is charging its beam at you: run to the Aegis on its plinth. A
-- golden line on the floor leads there; the bar is how long you have.
type Grab = { token: number, gui: ScreenGui, guide: { Instance }, conn: RBXScriptConnection? }
local grab: Grab? = nil

local function endGrab(tooSlow: boolean?)
	local g = grab
	if not g then return end
	grab = nil
	if g.conn then g.conn:Disconnect() end
	for _, i in ipairs(g.guide) do i:Destroy() end
	if tooSlow then
		local title = g.gui:FindFirstChild("Title") :: TextLabel?
		if title then
			title.Text = "TOO SLOW!"
			title.TextColor3 = TILE_BAD
			TweenService:Create(title, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.8),
				{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
		local bar = g.gui:FindFirstChild("Bar")
		if bar and bar:IsA("GuiObject") then bar.Visible = false end
		Debris:AddItem(g.gui, 1.5)
	else
		g.gui:Destroy()
	end
end

local function startGrab(token: number, shield: BasePart, grabTime: number)
	endGrab(nil)
	local gui = Instance.new("ScreenGui")
	gui.Name = "DragonGrabShield"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 950
	gui.Parent = player:WaitForChild("PlayerGui")
	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 0.7, -10)
	title.Size = UDim2.fromOffset(800, 50)
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 42
	title.TextColor3 = GOLD
	title.TextStrokeColor3 = Color3.fromRGB(60, 20, 0)
	title.TextStrokeTransparency = 0.1
	title.Text = "GRAB THE SHIELD!"
	title.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0.7, -6)
	sub.Size = UDim2.fromOffset(800, 24)
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 20
	sub.TextColor3 = Color3.fromRGB(255, 235, 215)
	sub.TextStrokeTransparency = 0.3
	sub.Text = "Ignarath is charging its beam at you. Reach the shield!"
	sub.Parent = gui
	local back = Instance.new("Frame")
	back.Name = "Bar"
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0.7, 26)
	back.Size = UDim2.fromOffset(360, 10)
	back.BackgroundColor3 = Color3.fromRGB(25, 15, 15)
	back.BorderSizePixel = 0
	back.Parent = gui
	local c1 = Instance.new("UICorner")
	c1.CornerRadius = UDim.new(1, 0)
	c1.Parent = back
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = GOLD
	fill.BorderSizePixel = 0
	fill.Parent = back
	local c2 = Instance.new("UICorner")
	c2.CornerRadius = UDim.new(1, 0)
	c2.Parent = fill

	-- A golden line from you to the shield, and the shield outlined.
	local guide: { Instance } = {}
	local root = myRoot()
	if root then
		local a0 = Instance.new("Attachment")
		a0.Position = Vector3.new(0, -2.6, 0)
		a0.Parent = root
		local a1 = Instance.new("Attachment")
		a1.Parent = shield
		local line = Instance.new("Beam")
		line.Attachment0 = a0
		line.Attachment1 = a1
		line.Color = ColorSequence.new(GOLD)
		line.LightEmission = 1
		line.LightInfluence = 0
		line.Width0, line.Width1 = 0.6, 0.6
		line.FaceCamera = true
		line.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0.5) })
		line.Texture = SPARK_TEXTURE
		line.TextureMode = Enum.TextureMode.Wrap
		line.TextureLength = 2
		line.TextureSpeed = 2
		line.Parent = a0
		table.insert(guide, a0)
		table.insert(guide, a1)
	end

	local t0 = os.clock()
	local g: Grab = { token = token, gui = gui, guide = guide, conn = nil }
	grab = g
	g.conn = RunService.RenderStepped:Connect(function()
		local left = math.clamp(1 - (os.clock() - t0) / grabTime, 0, 1)
		fill.Size = UDim2.fromScale(left, 1)
		fill.BackgroundColor3 = GOLD:Lerp(TILE_BAD, 1 - left)
		title.TextColor3 = if left < 0.3 and math.floor(os.clock() * 6) % 2 == 0 then TILE_BAD else GOLD
		if os.clock() - t0 > grabTime + 3 then endGrab(nil) end
	end)
end

local function onBeam(data: any)
	if typeof(data) ~= "table" then return end
	if data.phase == "grab" and typeof(data.token) == "number" and typeof(data.shield) == "Instance" then
		startGrab(data.token, data.shield :: BasePart, data.grabTime or 4)
	elseif data.phase == "start" and typeof(data.token) == "number" and typeof(data.keys) == "table" then
		endGrab(nil)
		startMinigame(data.token, data.keys, data.windup or 1.6, data.duration or 5)
	elseif data.phase == "end" then
		if grab and grab.token == data.token then endGrab(data.grabbed ~= true) end
		if ui and ui.token == data.token then endMinigame(data.success == true) end
	end
end

function DragonBossFX.Init()
	Network.GetRemoteEvent(Network.Remotes.DragonFX).OnClientEvent:Connect(onFX)
	Network.GetRemoteEvent(Network.Remotes.DragonBeam).OnClientEvent:Connect(onBeam)
	Network.GetRemoteEvent(Network.Remotes.BossIntro).OnClientEvent:Connect(function(data: any)
		if typeof(data) ~= "table" then return end
		local small = if data.kind == "fallen_angel" then "CELESTIAL SCOURGE" elseif data.kind == "warlord" then "WARLORD OF IRON" elseif data.kind == "colossus" then "ANCIENT TITAN" else "BOSS ENCOUNTER"
		banner(small, data.name or "BOSS BATTLE", data.color or GOLD, 3.8)
		shake(1.4, 0.35)
	end)
	task.spawn(function()
		while true do
			scanDragons()
			task.wait(0.5)
		end
	end)
	RunService.Stepped:Connect(function(_, dt)
		animate(dt)
	end)
	RunService.RenderStepped:Connect(function(dt)
		updateBar(dt)
		if os.clock() < shakeUntil then
			local a = shakePower
			camera.CFrame *= CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a * 0.6, (math.random() - 0.5) * a * 0.4)
		else
			shakePower = 0
		end
	end)
end

return DragonBossFX
