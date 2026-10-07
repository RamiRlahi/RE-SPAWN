--!strict
--[[
	RogueController.luau
	Client side of the Rogue, "The Shadow" (server: RogueServer).

	  • Your own moves happen at once on your screen (the dash and the Shadow
	    Step blink you there in the same frame; the server decides the hits).
	  • E twice: throw the Shadow Dagger, then press E again while it's out to
	    Shadow Step to it (behind the enemy it's stuck in). TryRecast catches
	    that second press before the cooldown check.
	  • F Dash: instant, leaving silhouettes along the path drawn white inside
	    a black outline (one Highlight over the whole set).
	  • Invisible Rogues vanish on other screens and are a faint shadow on
	    their own.
	  • Every Rogue effect for every player arrives over RogueFX.
	  • The Shadow Energy bar over the skill bar (RG_Energy, full = ENHANCED).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local CastPoses = require(script.Parent:WaitForChild("CastPoses"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local player = Players.LocalPlayer

local RogueController = {}

-- ── Tuning (matches RogueServer) ────────────────────────────────────────────
local SWING_INTERVAL = 0.26
local COMBO_RESET = 0.9
local ENERGY_MAX = 100

local CRIMSON = Color3.fromRGB(225, 30, 55)
local SHADOW = Color3.fromRGB(14, 10, 18)
local VIOLET = Color3.fromRGB(150, 60, 230)
local WHITE = Color3.new(1, 1, 1)

type Deps = { shake: (number, number) -> (), fovPunch: (number, number) -> (), getAim: (BasePart) -> Vector3 }
local deps: Deps

local localStep = 0
local lastSwing = 0
local busyUntil = 0

-- The dagger we threw (for the Shadow Step).
type MyDagger = { to: Vector3, stuck: Model?, landsAt: number, expires: number }
local myDagger: MyDagger? = nil

local function isRogue(): boolean
	return player:GetAttribute("SelectedClass") == "rogue"
end

local function charOf(p: any): Model?
	return if typeof(p) == "Instance" and p:IsA("Player") then p.Character else nil
end

local function rootOf(char: Model?): BasePart?
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = ClassFX.Folder()
	return p
end

local function trailOn(char: Model, t: number)
	local tool = char:FindFirstChild("Shadowfang")
	local tr = tool and tool:FindFirstChild("DaggerTrail", true) :: Trail?
	if not tr then return end
	tr.Enabled = true
	task.delay(t, function() if tr.Parent then tr.Enabled = false end end)
end

-- ── Poses ───────────────────────────────────────────────────────────────────
local function swingPose(char: Model, step: number)
	if step == 1 then
		CastPoses.play(char, {
			{ dur = 0.06, pose = { Root = { 0, 0, 0, 0, -0.4, 0.2 }, W = { 8, 45, 0 }, RS = { 30, 90, 0 }, LS = { 40, -20, -30 }, N = { 0, -25, 0 } } },
			{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.3, -0.5 }, W = { -8, -50, 0 }, RS = { 15, -100, 0 }, LS = { -20, 0, -60 }, N = { 0, 20, 0 } } },
			{ dur = 0.12, pose = { Root = { 0, 0, 0, 0, -0.2, -0.3 }, W = { -4, -30, 0 }, RS = { 10, -70, 0 }, LS = { -10, 0, -40 } } },
		})
	elseif step == 2 then
		CastPoses.play(char, {
			{ dur = 0.06, pose = { Root = { 0, 0, 0, 0, -0.5, 0 }, W = { 14, -45, 0 }, RS = { -10, -80, 0 }, LS = { 25, 0, -20 } } },
			{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, 0.3, -0.3 }, W = { -18, 50, 0 }, RS = { 65, 95, 0 }, LS = { 45, 0, -70 }, N = { -12, 15, 0 } } },
			{ dur = 0.12, pose = { Root = { 0, 0, 0, 0, 0.1, -0.2 }, W = { -10, 30, 0 }, RS = { 50, 70, 0 }, LS = { 25, 0, -45 } } },
		})
	else
		CastPoses.play(char, {
			{ dur = 0.07, pose = { Root = { 0, 0, 0, 0, -0.5, 0.3 }, W = { 10, 35, 0 }, RS = { -30, 20, 0, 0, 0, 0.7 }, LS = { 80, -10, -10 }, N = { 0, -30, 0 } } },
			{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.8, -1.1 }, W = { -24, -10, 0 }, RS = { 6, 0, 0, 0, 0, -1 }, LS = { -30, 0, -50 }, RH = { -50, 0, 0 }, LH = { 40, 0, 0 } } },
			{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, -0.5, -0.8 }, W = { -15, -8, 0 }, RS = { 6, 0, 0, 0, 0, -0.7 }, LS = { -20, 0, -40 } } },
		})
	end
end

local function throwPose(char: Model)
	CastPoses.play(char, {
		{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.3, 0.4 }, W = { 6, 40, 0 }, RS = { 150, 30, 0 }, LS = { 50, -10, -30 }, N = { 0, -20, 0 } } },
		{ dur = 0.08, pose = { Root = { 0, 0, 0, 0, -0.4, -0.6 }, W = { -14, -30, 0 }, RS = { 60, -20, 0 }, LS = { -25, 0, -50 } } },
		{ dur = 0.14, pose = { Root = { 0, 0, 0, 0, -0.2, -0.3 }, W = { -6, -15, 0 }, RS = { 40, -10, 0 }, LS = { -10, 0, -30 } } },
	})
end

local function crouchPose(char: Model, dur: number)
	CastPoses.play(char, {
		{ dur = 0.1, pose = { Root = { 0, 0, 0, 0, -0.9, 0.2 }, W = { 25, 0, 0 }, RS = { 40, 30, 0 }, LS = { 40, -30, 0 }, RH = { 40, 0, 0 }, LH = { -20, 0, 0 }, N = { -15, 0, 0 } } },
		{ dur = dur, pose = { Root = { 0, 0, 0, 0, -0.9, 0.2 }, W = { 25, 0, 0 }, RS = { 40, 30, 0 }, LS = { 40, -30, 0 }, RH = { 40, 0, 0 }, LH = { -20, 0, 0 }, N = { -15, 0, 0 } } },
	})
end

-- ── Movement ────────────────────────────────────────────────────────────────
-- There in the same frame (walls and ledges still stop it short).
local function blinkTo(root: BasePart, to: Vector3, face: Vector3?)
	local stand = SafeMove.StandHeight(root)
	local start = root.CFrame
	local dir = flat(to - root.Position)
	local dist = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z).Magnitude
	dist = math.min(SafeMove.ClampDash(root, dir, dist), SafeMove.ClampToFloor(root, dir, dist))
	local at = root.Position + dir * dist
	local look = face or dir
	root.CFrame = CFrame.lookAt(at, at + look)
	root.AssemblyLinearVelocity = Vector3.new(0, math.max(root.AssemblyLinearVelocity.Y, 0), 0)
	SafeMove.SnapToFloor(root, stand)
	if not SafeMove.HasFloor(root) then
		root.CFrame = start
		root.AssemblyLinearVelocity = Vector3.zero
	end
end

local function releaseAfter(char: Model, t: number)
	task.delay(t, function()
		if char.Parent then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end)
end

-- ── Effects ─────────────────────────────────────────────────────────────────
-- A puff of black smoke (step / vanish).
local function smoke(pos: Vector3, size: number?)
	local s = size or 1
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local b = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * (1.6 * s), Material = Enum.Material.SmoothPlastic,
			Color = SHADOW, Transparency = 0.2, CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 0.6 * s, 0.5 + math.random() * 1.5, math.sin(a) * 0.6 * s)) })
		TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.one * (3.4 * s), Transparency = 1,
			CFrame = b.CFrame + Vector3.new(math.cos(a) * 1.5 * s, 1.2, math.sin(a) * 1.5 * s),
		}):Play()
		Debris:AddItem(b, 0.55)
	end
end

-- A thin slash streak (`color` core).
local function slash(at: Vector3, dir: Vector3, length: number, color: Color3, life: number?)
	local p = part({ Size = Vector3.new(0.25, 0.08, length), Color = color, Transparency = 0.05,
		CFrame = CFrame.lookAt(at, at + dir) * CFrame.Angles(0, 0, math.rad(math.random(-35, 35))) })
	TweenService:Create(p, TweenInfo.new(life or 0.25), { Size = Vector3.new(0.02, 0.02, length * 1.15), Transparency = 1 }):Play()
	Debris:AddItem(p, (life or 0.25) + 0.05)
end

-- The dash: silhouettes of the Rogue along the path, white inside a black
-- outline (one Highlight over all of them), and a white cut with a black rim.
local function dashSilhouettes(char: Model, from: Vector3, to: Vector3, enhanced: boolean)
	local root = rootOf(char)
	if not root then return end
	local model = Instance.new("Model")
	model.Name = "RogueDashGhosts"
	model.Parent = ClassFX.Folder()
	local dir = flat(to - from)
	local lookCF = CFrame.lookAt(Vector3.zero, dir)
	local copies = if enhanced then 5 else 4
	local parts: { BasePart } = {}
	local rootCF = root.CFrame
	for n = 1, copies do
		local a = (n - 0.5) / copies
		local here = from:Lerp(to, a)
		local base = CFrame.new(here.X, rootCF.Position.Y, here.Z) * lookCF
		for _, d in ipairs(char:GetChildren()) do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
				local rel = rootCF:ToObjectSpace(d.CFrame)
				local g = Instance.new("Part")
				g.Anchored, g.CanCollide, g.CanQuery, g.CanTouch, g.CastShadow = true, false, false, false, false
				g.Material = Enum.Material.SmoothPlastic
				g.Color = WHITE
				g.Size = d.Size
				g.CFrame = base * rel
				g.Transparency = 0.1 + 0.5 * (1 - a)
				g.Parent = model
				table.insert(parts, g)
			end
		end
	end
	-- The cut along the path.
	local mid = (from + to) / 2 + Vector3.new(0, 1.2, 0)
	local cut = Instance.new("Part")
	cut.Anchored, cut.CanCollide, cut.CanQuery, cut.CanTouch, cut.CastShadow = true, false, false, false, false
	cut.Material = Enum.Material.Neon
	cut.Color = WHITE
	cut.Size = Vector3.new(0.5, 0.15, (to - from).Magnitude + 3)
	cut.CFrame = CFrame.lookAt(mid, mid + dir)
	cut.Parent = model
	table.insert(parts, cut)
	local hl = Instance.new("Highlight")
	hl.FillColor = WHITE
	hl.FillTransparency = 0
	hl.OutlineColor = Color3.new(0, 0, 0)
	hl.OutlineTransparency = 0
	hl.DepthMode = Enum.HighlightDepthMode.Occluded
	hl.Adornee = model
	hl.Parent = model
	local fade = TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(hl, fade, { FillTransparency = 1, OutlineTransparency = 1 }):Play()
	for _, p in ipairs(parts) do
		TweenService:Create(p, fade, { Transparency = 1 }):Play()
	end
	TweenService:Create(cut, TweenInfo.new(0.3), { Size = Vector3.new(0.05, 0.05, cut.Size.Z) }):Play()
	Debris:AddItem(model, 0.5)
end

-- ── The thrown dagger ───────────────────────────────────────────────────────
type FlyingDagger = { model: Model, conn: RBXScriptConnection? }
local daggers: { [Player]: FlyingDagger } = {}

local function dropDagger(owner: Player)
	local d = daggers[owner]
	if not d then return end
	daggers[owner] = nil
	if d.conn then d.conn:Disconnect() end
	local m = d.model
	for _, p in ipairs(m:GetChildren()) do
		if p:IsA("BasePart") then TweenService:Create(p, TweenInfo.new(0.25), { Transparency = 1 }):Play() end
	end
	Debris:AddItem(m, 0.3)
end

local function buildDagger(): (Model, BasePart)
	local m = Instance.new("Model")
	m.Name = "ShadowDagger"
	local blade = part({ Name = "Blade", Size = Vector3.new(0.22, 0.06, 1.6), Color = SHADOW, Material = Enum.Material.Metal })
	blade.Parent = m
	local edge = part({ Name = "Edge", Size = Vector3.new(0.3, 0.08, 1.4), Color = CRIMSON, Transparency = 0.2 })
	edge.Parent = m
	local hilt = part({ Name = "Hilt", Size = Vector3.new(0.18, 0.18, 0.6), Color = SHADOW, Material = Enum.Material.Fabric })
	hilt.Parent = m
	local glow = part({ Name = "Glow", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, Color = CRIMSON, Transparency = 0.6 })
	glow.Parent = m
	m.PrimaryPart = blade
	m.Parent = ClassFX.Folder()
	return m, blade
end

local function placeDagger(m: Model, cf: CFrame)
	local blade = m:FindFirstChild("Blade") :: BasePart
	blade.CFrame = cf
	;(m:FindFirstChild("Edge") :: BasePart).CFrame = cf
	;(m:FindFirstChild("Hilt") :: BasePart).CFrame = cf * CFrame.new(0, 0, 1.05)
	;(m:FindFirstChild("Glow") :: BasePart).CFrame = cf
end

local function onDagger(msg: any)
	local owner = msg.attacker :: Player
	dropDagger(owner)
	local from, to = msg.from :: Vector3, msg.to :: Vector3
	local travel = math.max(0.03, tonumber(msg.travel) or 0.2)
	local stuck = if typeof(msg.stuck) == "Instance" then msg.stuck :: Model else nil
	local life = tonumber(msg.life) or 4
	if owner == player then
		myDagger = { to = to, stuck = stuck, landsAt = os.clock() + travel, expires = os.clock() + travel + life }
	end
	local caster = charOf(owner)
	if caster and owner ~= player then throwPose(caster) end
	local m, _ = buildDagger()
	local d: FlyingDagger = { model = m, conn = nil }
	daggers[owner] = d
	local dir = flat(to - from)
	local y = 1.6
	local t0 = os.clock()
	local offset: CFrame? = nil
	local spin = 0
	d.conn = RunService.RenderStepped:Connect(function(dt)
		local a = (os.clock() - t0) / travel
		if a < 1 then
			spin += dt * 30
			local p = from:Lerp(to, a) + Vector3.new(0, y, 0)
			placeDagger(m, CFrame.lookAt(p, p + dir) * CFrame.Angles(0, 0, spin))
			return
		end
		-- Landed: in the enemy (follows it) or in the floor, glowing.
		local sroot = stuck and rootOf(stuck)
		if sroot and stuck and stuck.Parent then
			if not offset then
				local at = to + Vector3.new(0, y, 0)
				offset = sroot.CFrame:ToObjectSpace(CFrame.lookAt(at, at + dir))
			end
			placeDagger(m, sroot.CFrame * (offset :: CFrame))
		elseif not offset then
			offset = CFrame.new()
			placeDagger(m, CFrame.new(to + Vector3.new(0, 0.6, 0)) * CFrame.lookAt(Vector3.zero, dir) * CFrame.Angles(math.rad(-60), 0, 0))
		end
		local g = m:FindFirstChild("Glow") :: BasePart?
		if g then g.Transparency = 0.55 + 0.25 * math.sin(os.clock() * 8) end
	end)
end

local function onStep(msg: any)
	local owner = msg.attacker :: Player
	dropDagger(owner)
	if owner == player then myDagger = nil end
	local from, to = msg.from :: Vector3, msg.to :: Vector3
	smoke(from)
	smoke(to)
	local target = if typeof(msg.target) == "Instance" then msg.target :: Model else nil
	local troot = rootOf(target)
	if troot then
		for _ = 1, 2 do slash(troot.Position + Vector3.new(0, 1.5, 0), flat(troot.Position - to), 6, CRIMSON, 0.3) end
		ClassFX.Sound("swordHit", troot, 0.7, 0.9)
	end
	local char = charOf(owner)
	if char and owner ~= player then
		local root = rootOf(char)
		if root then ClassFX.Sound("whoosh", root, 0.5, 1.3) end
	end
end

-- ── Marks ───────────────────────────────────────────────────────────────────
local marks: { [Model]: BillboardGui } = {}
local function onMark(msg: any)
	local model = msg.model
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent then return end
	local dur = tonumber(msg.duration) or 5
	local bb = marks[model]
	if not bb or not bb.Parent then
		if not FxBudget.Allow("rogueMark", 12) then return end
		local root = rootOf(model)
		if not root then return end
		local g = Instance.new("BillboardGui")
		g.Name = "ShadowMark"
		g.Size = UDim2.fromOffset(34, 34)
		g.StudsOffsetWorldSpace = Vector3.new(0, 4.5, 0)
		g.AlwaysOnTop = true
		g.LightInfluence = 0
		g.MaxDistance = 120
		g.Adornee = root
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.Text = "✦"
		t.TextColor3 = CRIMSON
		t.TextStrokeColor3 = Color3.new(0, 0, 0)
		t.TextStrokeTransparency = 0
		t.Parent = g
		g.Parent = ClassFX.Folder()
		marks[model] = g
		bb = g
	end
	local mine = (bb :: BillboardGui)
	local token = (mine:GetAttribute("Token") or 0) + 1
	mine:SetAttribute("Token", token)
	task.delay(dur, function()
		if mine:GetAttribute("Token") == token then
			mine:Destroy()
			if marks[model] == mine then marks[model] = nil end
		end
	end)
end

-- ── Invisibility ────────────────────────────────────────────────────────────
local hidden: { [Model]: { conn: RBXScriptConnection, amount: number } } = {}

local function fadeOne(d: Instance, amount: number)
	if d:IsA("BasePart") or d:IsA("Decal") then
		(d :: any).LocalTransparencyModifier = amount
	end
end

local function setHidden(char: Model, on: boolean, amount: number)
	local h = hidden[char]
	if h then
		h.conn:Disconnect()
		hidden[char] = nil
	end
	for _, d in ipairs(char:GetDescendants()) do fadeOne(d, if on then amount else 0) end
	if on then
		hidden[char] = { amount = amount, conn = char.DescendantAdded:Connect(function(d) fadeOne(d, amount) end) }
	end
end

local function onHidden(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	if not char then return end
	local root = rootOf(char)
	if root then smoke(root.Position - Vector3.new(0, 2, 0), 1.1) end
	-- Others lose sight of you completely; you see your own faint shadow.
	setHidden(char, msg.on == true, if owner == player then 0.7 else 1)
	if owner == player and msg.on == true and deps then deps.fovPunch(4, 0.3) end
end

-- ── Shadow Realm ────────────────────────────────────────────────────────────
local function onRealm(msg: any)
	local owner = msg.attacker :: Player
	local pos = msg.pos :: Vector3
	local dur = tonumber(msg.duration) or 4
	local range = tonumber(msg.range) or 24
	local dome = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Material = Enum.Material.ForceField,
		Color = VIOLET, Transparency = 0.2, CFrame = CFrame.new(pos) })
	TweenService:Create(dome, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * range * 2 }):Play()
	local floor = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2, 2), Color = Color3.fromRGB(40, 0, 50),
		Transparency = 0.3, CFrame = CFrame.new(pos - Vector3.new(0, 2.9, 0)) * CFrame.Angles(0, 0, math.rad(90)) })
	TweenService:Create(floor, TweenInfo.new(0.5), { Size = Vector3.new(0.1, range * 2, range * 2) }):Play()
	task.delay(dur, function()
		TweenService:Create(dome, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		TweenService:Create(floor, TweenInfo.new(0.3), { Transparency = 1 }):Play()
		Debris:AddItem(dome, 0.35)
		Debris:AddItem(floor, 0.35)
	end)
	local char = charOf(owner)
	if char then
		-- The Rogue becomes a shade over it all.
		setHidden(char, true, if owner == player then 0.55 else 0.75)
		task.delay(dur, function()
			if char.Parent and not (hidden[char] and hidden[char].amount == 1) then setHidden(char, false, 0) end
		end)
	end
	if owner == player and deps then deps.shake(0.4, 0.4) end
end

local function onRealmSlash(msg: any)
	if not FxBudget.Allow("rogueRealmSlash", 14) then return end
	local at = (msg.pos :: Vector3) + Vector3.new(0, 1.5, 0)
	local a = math.random() * math.pi * 2
	local dir = Vector3.new(math.cos(a), (math.random() - 0.5) * 0.6, math.sin(a)).Unit
	slash(at, dir, 8, if math.random() < 0.5 then CRIMSON else VIOLET, 0.3)
	slash(at, Vector3.new(-dir.Z, 0.2, dir.X).Unit, 6, SHADOW, 0.3)
end

local function onRealmBurst(msg: any)
	local pos = msg.pos :: Vector3
	local range = tonumber(msg.range) or 24
	ClassFX.Ring(pos, VIOLET, range, 0.5)
	ClassFX.Ring(pos, CRIMSON, range * 0.6, 0.4)
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2
		slash(pos + Vector3.new(math.cos(a) * range * 0.4, 1.5, math.sin(a) * range * 0.4), Vector3.new(math.cos(a), 0, math.sin(a)), range * 0.5,
			if i % 2 == 0 then CRIMSON else VIOLET, 0.45)
	end
	if msg.attacker == player and deps then deps.shake(1.2, 0.4) end
end

-- ── Others' moments ─────────────────────────────────────────────────────────
local function onCombo(msg: any)
	if msg.attacker == player then return end
	local char = charOf(msg.attacker)
	if not char then return end
	swingPose(char, msg.step or 1)
	trailOn(char, 0.18)
end

local function onDash(msg: any)
	if msg.attacker == player then return end -- (drawn the moment we pressed it)
	local char = charOf(msg.attacker)
	if char then dashSilhouettes(char, msg.from, msg.to, msg.enhanced == true) end
end

local function onEnhanced(msg: any)
	local char = charOf(msg.attacker)
	local root = rootOf(char)
	if root then ClassFX.Ring(root.Position, CRIMSON, 6, 0.35) end
end

local HANDLERS: { [string]: (any) -> () } = {
	combo = onCombo,
	dagger = onDagger,
	daggerGone = function(msg) dropDagger(msg.attacker); if msg.attacker == player then myDagger = nil end end,
	step = onStep,
	dash = onDash,
	hidden = onHidden,
	realm = onRealm,
	realmSlash = onRealmSlash,
	realmBurst = onRealmBurst,
	mark = onMark,
	enhanced = onEnhanced,
	energyFull = function(msg)
		local root = rootOf(charOf(msg.attacker))
		if root and msg.attacker == player then ClassFX.Ring(root.Position, CRIMSON, 5, 0.3) end
	end,
}

-- ── HUD: Shadow Energy ──────────────────────────────────────────────────────
local hud: ScreenGui? = nil
local fill: Frame? = nil
local fullLabel: TextLabel? = nil

local function energy(): number
	return tonumber(player:GetAttribute("RG_Energy")) or 0
end

local function buildHud()
	local g = Instance.new("ScreenGui")
	g.Name = "RogueEnergy"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	hud = g
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -132)
	back.Size = UDim2.fromOffset(220, 10)
	back.BackgroundColor3 = Color3.fromRGB(20, 12, 18)
	back.BorderSizePixel = 0
	back.Parent = g
	local s = Instance.new("UIStroke")
	s.Color = CRIMSON
	s.Thickness = 1.2
	s.Transparency = 0.3
	s.Parent = back
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(0, 1)
	f.BackgroundColor3 = VIOLET
	f.BorderSizePixel = 0
	f.Parent = back
	fill = f
	local lbl = Instance.new("TextLabel")
	lbl.AnchorPoint = Vector2.new(0.5, 1)
	lbl.Position = UDim2.new(0.5, 0, 0, -3)
	lbl.Size = UDim2.fromOffset(260, 20)
	lbl.BackgroundTransparency = 1
	lbl.Font = Enum.Font.Arcade
	lbl.TextSize = 18
	lbl.Text = "SHADOW ENERGY"
	lbl.TextColor3 = Color3.fromRGB(210, 190, 230)
	lbl.TextStrokeTransparency = 0.3
	lbl.Parent = back
	fullLabel = lbl
end

local function refreshHud()
	if not hud then return end
	hud.Enabled = isRogue() and player:GetAttribute("InLobby") == false and player:GetAttribute("SettingsOpen") ~= true
	local e = energy()
	if fill then
		fill.Size = UDim2.fromScale(math.clamp(e / ENERGY_MAX, 0, 1), 1)
		fill.BackgroundColor3 = if e >= ENERGY_MAX then CRIMSON else VIOLET
	end
	if fullLabel then
		local text = if e >= ENERGY_MAX then "ENHANCED: NEXT ABILITY" else "SHADOW ENERGY"
		if fullLabel.Text ~= text then fullLabel.Text = text end
		fullLabel.TextColor3 = if e >= ENERGY_MAX then CRIMSON else Color3.fromRGB(210, 190, 230)
	end
end

-- ── Public: basic attack ────────────────────────────────────────────────────
function RogueController.Basic(char: Model, root: BasePart): boolean
	local now = os.clock()
	if now < busyUntil or char:GetAttribute("IsSkillCasting") == true then return true end
	local speed = math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
	if now - lastSwing < SWING_INTERVAL / speed then return true end
	localStep = if now - lastSwing > COMBO_RESET then 1 else (localStep % 3) + 1
	lastSwing = now
	local dir = flat(deps.getAim(root))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	swingPose(char, localStep)
	trailOn(char, 0.18)
	slash(root.Position + dir * 3.5 + Vector3.new(0, 1.2, 0), Vector3.new(-dir.Z, if localStep == 2 then 0.4 else -0.2, dir.X).Unit,
		if localStep == 3 then 4 else 6, if localStep == 3 then CRIMSON else Color3.fromRGB(255, 120, 135), 0.18)
	ClassFX.Sound("whoosh", root, 0.5, 1.25 + localStep * 0.06)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = dir })
	return true
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function RogueController.CanCast(_skillIndex: number): boolean
	return os.clock() >= busyUntil
end

-- E while our dagger is out: Shadow Step to it (no cooldown). Returns true
-- when the press was used up here.
function RogueController.TryRecast(skillIndex: number, char: Model, root: BasePart): boolean
	if skillIndex ~= 1 then return false end
	local d = myDagger
	if not d or os.clock() > d.expires then return false end
	if os.clock() < d.landsAt then return true end -- (still flying)
	myDagger = nil
	local to = d.to
	local face: Vector3? = nil
	local sroot = d.stuck and d.stuck.Parent and rootOf(d.stuck)
	if sroot then
		-- Behind them, facing their back.
		local away = flat(sroot.Position - root.Position)
		to = sroot.Position + away * 3.5
		face = -away
	end
	local from = root.Position
	blinkTo(root, to, face)
	smoke(from)
	trailOn(char, 0.2)
	swingPose(char, 3)
	ClassFX.Sound("whoosh", root, 0.6, 1.4)
	if deps then deps.fovPunch(6, 0.25) end
	Network.GetRemoteEvent(Network.Remotes.UseSkill):FireServer({
		skillIndex = 1, origin = root.Position, direction = root.CFrame.LookVector,
	})
	return true
end

function RogueController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local dir = flat(aimDir)
	local enhanced = energy() >= ENERGY_MAX
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	if skillIndex == 1 then
		-- Shadow Dagger: a quick overhand throw (the dagger itself flies on RogueFX).
		char:SetAttribute("AllowSkillMovement", true)
		throwPose(char)
		ClassFX.Sound("whoosh", root, 0.6, 1.5)
		releaseAfter(char, 0.2)
	elseif skillIndex == 2 then
		-- Dash: instant.
		char:SetAttribute("AllowSkillMovement", false)
		local dist = (config.dashDistance or 22) * (if enhanced then 1.5 else 1)
		local from = root.Position
		if hum then hum.AutoRotate = false end
		blinkTo(root, from + dir * dist)
		dashSilhouettes(char, from, root.Position, enhanced)
		swingPose(char, 1)
		trailOn(char, 0.25)
		ClassFX.Sound("whoosh", root, 0.7, 1.15)
		if deps then deps.fovPunch(5, 0.2) end
		busyUntil = os.clock() + 0.1
		releaseAfter(char, 0.12)
		task.delay(0.15, function() if hum then hum.AutoRotate = true end end)
	elseif skillIndex == 3 then
		-- Invisibility: a crouch into the smoke (the fade comes on RogueFX).
		char:SetAttribute("AllowSkillMovement", true)
		crouchPose(char, 0.15)
		releaseAfter(char, 0.25)
	elseif skillIndex == 4 then
		-- Shadow Realm: rise a little and hang there till it bursts.
		char:SetAttribute("AllowSkillMovement", false)
		local dur = (config.duration or 4) * (if enhanced then 1.5 else 1)
		busyUntil = os.clock() + dur
		crouchPose(char, dur)
		root.Anchored = true
		local base = root.CFrame
		TweenService:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = base + Vector3.new(0, 3, 0) }):Play()
		task.delay(dur, function()
			if root.Parent then
				root.CFrame = base
				root.Anchored = false
			end
		end)
		releaseAfter(char, dur)
	end
end

function RogueController.Init(d: Deps)
	deps = d
	buildHud()
	refreshHud()
	player:GetAttributeChangedSignal("RG_Energy"):Connect(refreshHud)
	player:GetAttributeChangedSignal("SelectedClass"):Connect(refreshHud)
	player:GetAttributeChangedSignal("InLobby"):Connect(refreshHud)
	player:GetAttributeChangedSignal("SettingsOpen"):Connect(refreshHud)
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localStep = 0
		myDagger = nil
	end)
	Network.GetRemoteEvent(Network.Remotes.RogueFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local h = HANDLERS[msg.kind]
		if h then
			local ok, err = pcall(h, msg)
			if not ok then warn("[RogueController]", msg.kind, err) end
		end
	end)
end

return RogueController
