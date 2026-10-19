--!strict
--[[
	DjinnFX.luau
	ZAR-0, the Arcade Djinn (BossAI.BuildDjinn), on every client: its body in
	motion, and the pictures of its attacks.

	The body (each piece hangs on a Motor6D; their Transform is set here each
	frame, local only):
	  Body        hovering, bobbing, breathing; leaning into its moves (and
	              spinning round for the Coin Spray)
	  Head        turned to watch you
	  ArmL/ArmR   a slow sway; then the pose ("DjinnPose", from BossAI):
	              conducting, casting, a fist raised and slammed, a swipe
	  Tail1..4    a wisp curling and waving under it
	  Strand      its crest of light swaying
	  While "DjinnGlitch" is set it flickers in and out of sight.

	The attacks (BossFX kind "djinn"; the server draws the red telegraphs and
	deals the damage):
	  blocks    tetromino blocks falling from the sky onto their squares,
	            bursting into pixels as they land
	  grid      warn: thin lasers drawn across the arena; fire: the beams
	  slam      raise: a giant fist of light over the spot, coming down;
	            impact: rings, pixels, the fist fading
	  glitch    out / in: a burst of pixels; slash: an arc of light
	  coins     golden coins rolling out across the floor
	  gameover  the floor a game board: red everywhere but the lit tiles, then
	            the red blows; each round named on screen

	Boss attacks are warnings the player must see: none of it asks the
	FxBudget, and none of it makes lights.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local BossCinematic: any = nil
pcall(function() BossCinematic = require(script.Parent:WaitForChild("BossCinematic")) end)

local DjinnFX = {}

local player = Players.LocalPlayer
local CULL_DIST = 320
local SPARK = "rbxasset://textures/particles/sparkles_main.dds"
local PINK = Color3.fromRGB(255, 70, 210)
local CYAN = Color3.fromRGB(90, 230, 255)
local GOLD = Color3.fromRGB(255, 215, 110)
local HOLO = Color3.fromRGB(205, 160, 255)
local RED = Color3.fromRGB(255, 50, 60)
local FLAT = CFrame.Angles(0, 0, math.rad(90))
local rad = math.rad

-- ── The body ────────────────────────────────────────────────────────────────
type Joint = { motor: Motor6D, cur: CFrame }
type Rig = {
	model: Model,
	root: BasePart,
	scale: number,
	joints: { [string]: Joint },
	tails: { Joint },
	strands: { { motor: Motor6D, phase: number } },
	parts: { BasePart },
	glitching: boolean,
	spin: number,
}
local rigs: { [Model]: Rig } = {}

-- Each pose: the arms (x forward / up, y across, z out to the side), the
-- body (lean, twist, lift in units); `snap` eases in fast.
type Pose = { armR: { number }, armL: { number }, body: { number }, snap: boolean?, spin: boolean? }
local IDLE: Pose = { armR = { 8, 0, 6 }, armL = { 8, 0, -6 }, body = { 0, 0, 0 } }
local POSES: { [string]: Pose } = {
	conduct = { armR = { 110, -20, 40 }, armL = { 110, 20, -40 }, body = { 6, 0, 0.2 } },
	cast = { armR = { 20, 0, 95 }, armL = { 20, 0, -95 }, body = { 10, 0, 0.3 } },
	rise = { armR = { 60, 0, 70 }, armL = { 60, 0, -70 }, body = { 8, 0, 0.4 } },
	raiseR = { armR = { 175, 0, 15 }, armL = { 20, 0, -30 }, body = { 10, -15, 0.2 } },
	slamR = { armR = { 40, 10, 0 }, armL = { -10, 0, -25 }, body = { -18, 10, -0.3 }, snap = true },
	raiseL = { armR = { 20, 0, 30 }, armL = { 175, 0, -15 }, body = { 10, 15, 0.2 } },
	slamL = { armR = { -10, 0, 25 }, armL = { 40, -10, 0 }, body = { -18, -10, -0.3 }, snap = true },
	swipeWind = { armR = { 90, -70, 50 }, armL = { 30, 0, -40 }, body = { 4, -30, 0 } },
	swipe = { armR = { 70, 80, -10 }, armL = { -10, 0, -40 }, body = { -8, 35, 0 }, snap = true },
	spin = { armR = { 10, 0, 85 }, armL = { 10, 0, -85 }, body = { 0, 0, 0.2 }, spin = true },
}

local function rigOf(model: Model): Rig?
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local scale = model:GetAttribute("DjinnScale")
	local r: Rig = {
		model = model, root = root,
		scale = if typeof(scale) == "number" then scale else 2.6,
		joints = {}, tails = {}, strands = {}, parts = {}, glitching = false, spin = 0,
	}
	local tails: { [number]: Joint } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("Motor6D") then
			if d.Name == "Strand" then
				table.insert(r.strands, { motor = d, phase = math.random() * 10 })
			elseif string.sub(d.Name, 1, 4) == "Tail" then
				tails[tonumber(string.sub(d.Name, 5)) or 1] = { motor = d, cur = CFrame.identity }
			else
				r.joints[d.Name] = { motor = d, cur = CFrame.identity }
			end
		elseif d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(r.parts, d)
		end
	end
	for k = 1, 8 do
		if tails[k] then table.insert(r.tails, tails[k]) end
	end
	if next(r.joints) == nil then return nil end
	return r
end

local function scan()
	for model in pairs(rigs) do
		if not model.Parent then rigs[model] = nil end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return end
	for _, m in ipairs(mobs:GetChildren()) do
		if m:IsA("Model") and not rigs[m] and m:GetAttribute("DjinnBuilt") == true then
			local r = rigOf(m)
			if r then rigs[m] = r end
		end
	end
end

local function angles(v: { number }): CFrame
	return CFrame.Angles(rad(v[1]), rad(v[2]), rad(v[3]))
end

local function drive(r: Rig, name: string, target: CFrame, alpha: number): boolean
	local j = r.joints[name]
	if not j then return true end
	if not j.motor.Parent then return false end
	j.cur = j.cur:Lerp(target, alpha)
	j.motor.Transform = j.cur
	return true
end

local function animate(r: Rig, t: number, dt: number): boolean
	local S = r.scale
	local enraged = r.model:GetAttribute("Enraged") == true
	local poseName = r.model:GetAttribute("DjinnPose")
	local p = (typeof(poseName) == "string" and POSES[poseName]) or IDLE
	local alpha = 1 - math.exp(-dt * (if p.snap then 24 else 8))
	local bob = math.sin(t * 1.4)

	-- Body: bobbing over its tail; spinning for the coins.
	if p.spin then r.spin += dt * 9 else r.spin = 0 end
	local body = CFrame.new(0, (0.12 * bob + p.body[3]) * S, 0)
		* CFrame.Angles(rad(p.body[1]) + rad(2) * math.sin(t * 1.4 + 1), rad(p.body[2]) + r.spin, rad(2) * math.sin(t * 0.8))
	if not drive(r, "Body", body, if p.spin then 1 else alpha) then return false end

	-- Head: watching you.
	local look = CFrame.identity
	local char = player.Character
	local me = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local headJoint = r.joints.Head
	if me and headJoint and headJoint.motor.Part1 and not p.spin then
		local d = r.root.CFrame:VectorToObjectSpace(me.Position - (headJoint.motor.Part1 :: BasePart).Position)
		local yaw = math.clamp(math.atan2(-d.X, -d.Z), rad(-55), rad(55))
		local pitch = math.clamp(math.atan2(d.Y, Vector3.new(d.X, 0, d.Z).Magnitude), rad(-35), rad(15))
		look = CFrame.Angles(0, yaw - rad(p.body[2]), 0) * CFrame.Angles(pitch, 0, 0)
	end
	if not drive(r, "Head", look * CFrame.Angles(0, 0, rad(3) * math.sin(t * 0.7)), alpha) then return false end

	-- Arms: a slow sway, then the pose.
	local sway = rad(4) * math.sin(t * 1.4 + 0.5)
	if not drive(r, "ArmR", angles(p.armR) * CFrame.Angles(sway, 0, 0), alpha) then return false end
	if not drive(r, "ArmL", angles(p.armL) * CFrame.Angles(-sway, 0, 0), alpha) then return false end

	-- Tail: a wave running down it, quicker enraged.
	local rate = if enraged then 3.2 else 2.2
	for k, j in ipairs(r.tails) do
		if not j.motor.Parent then return false end
		j.motor.Transform = CFrame.Angles(rad(10) * math.sin(t * rate - k * 0.9), rad(14) * math.sin(t * rate * 0.6 - k * 0.7), rad(8) * math.sin(t * rate * 0.8 - k))
	end
	-- Crest: swaying.
	for _, s in ipairs(r.strands) do
		if not s.motor.Parent then return false end
		s.motor.Transform = CFrame.Angles(rad(8) * math.sin(t * 2.3 + s.phase), 0, rad(6) * math.sin(t * 1.7 + s.phase))
	end

	-- Glitching: flickering in and out.
	local glitch = r.model:GetAttribute("DjinnGlitch") == true
	if glitch then
		local on = math.random() < 0.35
		for _, part in ipairs(r.parts) do part.LocalTransparencyModifier = if on then 0.2 else 1 end
		r.glitching = true
	elseif r.glitching then
		for _, part in ipairs(r.parts) do part.LocalTransparencyModifier = 0 end
		r.glitching = false
	end
	return true
end

-- ── Attack helpers ──────────────────────────────────────────────────────────
local function folder(): Instance
	local f = Workspace:FindFirstChild("DjinnClientFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "DjinnClientFX"
		f.Parent = Workspace
	end
	return f :: Instance
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
	p.Parent = folder()
	return p
end

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
end

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function shakeNear(pos: Vector3, power: number, duration: number, range: number?)
	local r = myRoot()
	if r and (r.Position - pos).Magnitude < (range or 80) and BossCinematic and BossCinematic.Shake then
		BossCinematic.Shake(power, duration)
	end
end

-- Pixels: little neon cubes flung out from `pos`, tumbling and fading.
local function pixels(pos: Vector3, n: number, colors: { Color3 }, speed: number, size: number?)
	for i = 1, n do
		local s = (size or 0.6) * (0.6 + math.random() * 0.8)
		local cube = part({ Size = Vector3.one * s, CFrame = CFrame.new(pos), Color = colors[(i - 1) % #colors + 1] })
		local a = math.random() * math.pi * 2
		local out = Vector3.new(math.cos(a), 0.4 + math.random() * 0.9, math.sin(a)) * speed * (0.5 + math.random() * 0.6)
		local life = 0.45 + math.random() * 0.35
		tween(cube, life, { CFrame = CFrame.new(pos + out) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Transparency = 1, Size = Vector3.one * s * 0.3 })
		Debris:AddItem(cube, life + 0.05)
	end
end

local function sparkle(pos: Vector3, n: number, color: Color3, speed: number)
	local holder = part({ Size = Vector3.one * 0.2, Transparency = 1, CFrame = CFrame.new(pos) })
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 0) })
	e.Lifetime = NumberRange.new(0.3, 0.7)
	e.Speed = NumberRange.new(speed * 0.5, speed)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.Rate = 0
	e.Parent = holder
	e:Emit(n)
	Debris:AddItem(holder, 1)
end

local function ringOut(pos: Vector3, radius: number, color: Color3, t: number?)
	local r = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, 2, 2), CFrame = CFrame.new(pos + Vector3.new(0, 0.25, 0)) * FLAT,
		Color = color, Transparency = 0.1 })
	tween(r, t or 0.4, { Size = Vector3.new(0.1, radius * 2.2, radius * 2.2), Transparency = 1 }, Enum.EasingStyle.Quart)
	Debris:AddItem(r, (t or 0.4) + 0.05)
end

-- ── The attacks ─────────────────────────────────────────────────────────────
local MOVES: { [string]: (any) -> () } = {}

MOVES.blocks = function(d)
	local cells = d.cells
	if typeof(cells) ~= "table" then return end
	local size = tonumber(d.size) or 5
	local delay = tonumber(d.delay) or 1
	local tint: Color3 = if typeof(d.tint) == "Color3" then d.tint else CYAN
	for _, c in ipairs(cells) do
		if typeof(c) ~= "Vector3" then continue end
		local s = size - 0.4
		local landCF = CFrame.new(c + Vector3.new(0, s / 2, 0))
		local block = part({ Size = Vector3.one * s, CFrame = landCF + Vector3.new(0, 48, 0), Color = tint, Transparency = 0.15 })
		local inner = part({ Size = Vector3.one * s * 0.7, CFrame = block.CFrame, Color = Color3.new(1, 1, 1), Transparency = 0.5 })
		-- (it falls the last stretch, landing right as the square fills)
		local wait = math.max(0, delay - 0.45)
		task.delay(wait, function()
			tween(block, delay - wait, { CFrame = landCF }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			tween(inner, delay - wait, { CFrame = landCF }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end)
		task.delay(delay, function()
			inner:Destroy()
			tween(block, 0.5, { Transparency = 1, Size = Vector3.one * s * 1.15 })
			Debris:AddItem(block, 0.55)
			pixels(c + Vector3.new(0, 1, 0), 6, { tint, Color3.new(1, 1, 1) }, 12)
		end)
	end
	task.delay(delay, function()
		if typeof(cells[1]) == "Vector3" then shakeNear(cells[1], 0.5, 0.2, 60) end
	end)
end

MOVES.grid = function(d)
	local lines = d.lines
	if typeof(lines) ~= "table" then return end
	local width = tonumber(d.width) or 5
	for _, l in ipairs(lines) do
		if typeof(l) ~= "table" or typeof(l.from) ~= "Vector3" or typeof(l.dir) ~= "Vector3" then continue end
		local len = tonumber(l.len) or 60
		local mid = l.from + l.dir * (len / 2)
		local cf = CFrame.lookAt(mid, mid + l.dir)
		if d.phase == "warn" then
			local dur = tonumber(d.duration) or 1
			local thin = part({ Size = Vector3.new(0.25, 0.25, len), CFrame = cf + Vector3.new(0, 2.5, 0), Color = PINK, Transparency = 0.4 })
			tween(thin, dur, { Transparency = 0.05, Size = Vector3.new(0.45, 0.45, len) }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
			Debris:AddItem(thin, dur)
		else
			local beam = part({ Size = Vector3.new(width, 4, len), CFrame = cf + Vector3.new(0, 2, 0), Color = PINK, Transparency = 0.15 })
			local core = part({ Size = Vector3.new(width * 0.35, 1.2, len), CFrame = cf + Vector3.new(0, 2, 0), Color = Color3.new(1, 1, 1), Transparency = 0.05 })
			tween(beam, 0.4, { Size = Vector3.new(0.2, 0.2, len), Transparency = 1 })
			tween(core, 0.3, { Size = Vector3.new(0.1, 0.1, len), Transparency = 1 })
			Debris:AddItem(beam, 0.45)
			Debris:AddItem(core, 0.35)
		end
	end
	if d.phase == "fire" and typeof(lines[1]) == "table" and typeof(lines[1].from) == "Vector3" then
		shakeNear(lines[1].from, 0.6, 0.25, 140)
	end
end

-- A fist of light (a block hand with knuckles), its knuckles down.
local function fist(scale: number): { BasePart }
	local s = scale
	local out = {}
	table.insert(out, part({ Size = Vector3.new(5, 4.2, 5) * s, Color = HOLO, Material = Enum.Material.ForceField }))
	table.insert(out, part({ Size = Vector3.new(4.6, 3.8, 4.6) * s, Color = PINK, Transparency = 0.7 }))
	table.insert(out, part({ Size = Vector3.new(5.1, 0.6, 1) * s, Color = PINK }))
	table.insert(out, part({ Size = Vector3.new(4, 4.5, 4) * s, Color = HOLO, Material = Enum.Material.ForceField }))
	table.insert(out, part({ Size = Vector3.new(4.3, 0.8, 4.3) * s, Color = GOLD }))
	return out
end
local function placeFist(f: { BasePart }, at: Vector3, scale: number)
	local base = CFrame.new(at + Vector3.new(0, 2.1 * scale, 0))
	f[1].CFrame = base
	f[2].CFrame = base
	f[3].CFrame = base * CFrame.new(0, -1.6 * scale, -2.4 * scale)
	f[4].CFrame = base * CFrame.new(0, 4.3 * scale, 0)
	f[5].CFrame = base * CFrame.new(0, 3.2 * scale, 0)
end

MOVES.slam = function(d)
	if typeof(d.pos) ~= "Vector3" then return end
	local pos: Vector3 = d.pos
	local radius = tonumber(d.radius) or 9
	if d.phase == "raise" then
		local dur = tonumber(d.duration) or 0.9
		local scale = radius / 9
		local f = fist(scale)
		local t0 = os.clock()
		local conn: RBXScriptConnection
		conn = RunService.RenderStepped:Connect(function()
			local a = math.min((os.clock() - t0) / dur, 1)
			local h = 40 * (1 - TweenService:GetValue(a, Enum.EasingStyle.Quad, Enum.EasingDirection.In))
			placeFist(f, pos + Vector3.new(0, h, 0), scale)
			if a >= 1 then
				conn:Disconnect()
				for _, p in ipairs(f) do
					tween(p, 0.5, { Transparency = 1 })
					Debris:AddItem(p, 0.55)
				end
			end
		end)
	else
		ringOut(pos, radius, PINK, 0.4)
		ringOut(pos, radius * 1.4, CYAN, 0.6)
		pixels(pos + Vector3.new(0, 1.5, 0), 14, { PINK, CYAN, Color3.new(1, 1, 1) }, 18, 0.9)
		sparkle(pos + Vector3.new(0, 1, 0), 24, PINK, 26)
		shakeNear(pos, 1.3, 0.35, 90)
	end
end

MOVES.glitch = function(d)
	if typeof(d.pos) ~= "Vector3" then return end
	local pos: Vector3 = d.pos
	if d.phase == "out" or d.phase == "in" then
		pixels(pos, 18, { PINK, CYAN, HOLO }, 14, 1.1)
		-- a torn band of colour where it was
		for k = -1, 1 do
			local band = part({ Size = Vector3.new(12, 0.5, 0.2), CFrame = CFrame.new(pos + Vector3.new(0, 4 + k * 3, 0)),
				Color = if k == 0 then Color3.new(1, 1, 1) elseif k < 0 then CYAN else PINK, Transparency = 0.2 })
			tween(band, 0.3, { Size = Vector3.new(0.2, 0.5, 0.2), Transparency = 1 })
			Debris:AddItem(band, 0.35)
		end
	elseif d.phase == "slash" and typeof(d.dir) == "Vector3" then
		local dir: Vector3 = d.dir
		local radius = tonumber(d.radius) or 17
		local half = tonumber(d.half) or rad(60)
		local base = math.atan2(dir.Z, dir.X)
		local n = 9
		for i = 0, n - 1 do
			local a = base - half + (i + 0.5) / n * half * 2
			local at = pos + Vector3.new(math.cos(a), 0, math.sin(a)) * radius * 0.7
			local seg = part({ Size = Vector3.new(0.5, 1.2, radius * 0.5), Color = if i % 2 == 0 then PINK else CYAN, Transparency = 0.1,
				CFrame = CFrame.lookAt(at + Vector3.new(0, 2.5, 0), at + Vector3.new(0, 2.5, 0) + Vector3.new(-math.sin(a), 0, math.cos(a))) })
			task.delay(i * 0.012, function()
				tween(seg, 0.3, { Transparency = 1, Size = Vector3.new(0.1, 0.2, radius * 0.6) })
			end)
			Debris:AddItem(seg, 0.45)
		end
		sparkle(pos + dir * radius * 0.5 + Vector3.new(0, 2, 0), 16, CYAN, 18)
	end
end

MOVES.coins = function(d)
	if typeof(d.pos) ~= "Vector3" or typeof(d.coins) ~= "table" then return end
	local center: Vector3 = d.pos
	local speed = tonumber(d.speed) or 28
	local delay = tonumber(d.delay) or 0.5
	task.delay(delay, function()
		for _, c in ipairs(d.coins) do
			if typeof(c) ~= "table" or typeof(c.dir) ~= "Vector3" then continue end
			local dir: Vector3 = c.dir
			local len = tonumber(c.len) or 40
			local coin = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 3.2, 3.2), Color = GOLD })
			local face = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.55, 1.6, 1.6), Color = Color3.fromRGB(255, 245, 190) })
			local t0 = os.clock()
			local dur = len / speed
			local turn = CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(0, math.rad(90), 0) -- (rolling: its axis across the way it goes)
			local conn: RBXScriptConnection
			conn = RunService.RenderStepped:Connect(function()
				local el = os.clock() - t0
				local a = math.min(el / dur, 1)
				local at = center + dir * len * a + Vector3.new(0, 1.7, 0)
				local cf = CFrame.new(at) * turn * CFrame.Angles(el * 12, 0, 0)
				coin.CFrame = cf
				face.CFrame = cf
				if a >= 1 or not coin.Parent then
					conn:Disconnect()
					coin:Destroy()
					face:Destroy()
					sparkle(at, 6, GOLD, 10)
				end
			end)
		end
	end)
end

-- GAME OVER: the board.
local board: { BasePart } = {}
local function clearBoard()
	for _, p in ipairs(board) do p:Destroy() end
	table.clear(board)
end

MOVES.gameover = function(d)
	if d.phase == "start" then
		if BossCinematic and BossCinematic.Title then
			BossCinematic.Title("FIND THE LIT TILES", "GAME OVER", PINK, 1.6, 0.4)
		end
		return
	elseif d.phase == "end" then
		clearBoard()
		return
	end
	local room = d.room
	if typeof(room) ~= "table" then return end
	local tile = tonumber(d.tile) or 12
	local fy = (tonumber(room.floorY) or 0) + 0.18
	local w, dz = room.maxX - room.minX, room.maxZ - room.minZ
	local mid = Vector3.new((room.minX + room.maxX) / 2, fy, (room.minZ + room.maxZ) / 2)
	local safe = if typeof(d.safe) == "table" then d.safe else {}
	if d.phase == "round" then
		clearBoard()
		local dur = tonumber(d.duration) or 2
		-- red over everything...
		local red = part({ Size = Vector3.new(w, 0.12, dz), CFrame = CFrame.new(mid), Color = RED, Transparency = 0.75 })
		tween(red, dur, { Transparency = 0.45 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		table.insert(board, red)
		-- ...but the lit tiles, glowing cyan with a bright rim
		for _, ij in ipairs(safe) do
			if typeof(ij) ~= "table" then continue end
			local c = Vector3.new(room.minX + (ij[1] + 0.5) * tile, fy + 0.04, room.minZ + (ij[2] + 0.5) * tile)
			local pad = part({ Size = Vector3.new(tile - 0.6, 0.14, tile - 0.6), CFrame = CFrame.new(c), Color = CYAN, Transparency = 0.35 })
			table.insert(board, pad)
			for _, side in ipairs({ -1, 1 }) do
				table.insert(board, part({ Size = Vector3.new(tile - 0.4, 0.2, 0.35), CFrame = CFrame.new(c + Vector3.new(0, 0.03, side * (tile / 2 - 0.3))), Color = Color3.new(1, 1, 1) }))
				table.insert(board, part({ Size = Vector3.new(0.35, 0.2, tile - 0.4), CFrame = CFrame.new(c + Vector3.new(side * (tile / 2 - 0.3), 0.03, 0)), Color = Color3.new(1, 1, 1) }))
			end
		end
		if BossCinematic and BossCinematic.Title then
			BossCinematic.Title(`ROUND {d.round or 1} / {d.rounds or 3}`, "STAND ON A LIT TILE", CYAN, math.min(dur, 1.4), 0.62)
		end
	elseif d.phase == "blast" then
		-- the red goes off: a flash over all of it, pixels bursting up from it
		local flash = part({ Size = Vector3.new(w, 6, dz), CFrame = CFrame.new(mid + Vector3.new(0, 3, 0)), Color = RED, Transparency = 0.3 })
		tween(flash, 0.45, { Transparency = 1, Size = Vector3.new(w, 0.5, dz) })
		Debris:AddItem(flash, 0.5)
		for _ = 1, 10 do
			local at = Vector3.new(room.minX + math.random() * w, fy + 1, room.minZ + math.random() * dz)
			pixels(at, 4, { RED, PINK, Color3.new(1, 1, 1) }, 14, 1)
		end
		clearBoard()
		shakeNear(mid, 1.6, 0.4, 200)
		if BossCinematic and BossCinematic.Wash then BossCinematic.Wash(RED, 0.6, 1, 0.4) end
	end
end

local function onFX(data: any)
	if typeof(data) ~= "table" or data.kind ~= "djinn" then return end
	local handler = MOVES[data.move]
	if not handler then return end
	local ok, err = pcall(handler, data)
	if not ok then warn("[DjinnFX]", data.move, data.phase, err) end
end

function DjinnFX.Init()
	Network.GetRemoteEvent(Network.Remotes.BossFX).OnClientEvent:Connect(onFX)
	-- (died or left mid-game: no board left on the floor)
	player.CharacterAdded:Connect(clearBoard)
	task.spawn(function()
		while true do
			pcall(scan)
			task.wait(1)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		if next(rigs) == nil then return end
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		local t = os.clock()
		for model, r in pairs(rigs) do
			if not model.Parent or not r.root.Parent then
				rigs[model] = nil
				continue
			end
			if (r.root.Position - camPos).Magnitude > CULL_DIST then continue end
			local ok, res = pcall(animate, r, t, dt)
			if not ok then
				warn("[DjinnFX]", res)
				rigs[model] = nil
			elseif not res then
				rigs[model] = nil
			end
		end
	end)
end

return DjinnFX
