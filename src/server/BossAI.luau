--!strict
--[[
	BossAI.luau
	Boss movesets. MobManager picks a boss kind for each Boss room and calls
	Attach once the boss model is configured; the normal chase AI keeps it
	walking toward players, and between moves this loop takes over (the model's
	"BossBusy" attribute pauses the chase AI while a move runs).

	Every attack is telegraphed on the ground in red first. Below half health a
	boss ENRAGES: shorter gaps between moves and bigger versions of them.

	  The Iron Warlord   (melee)  Ground Slam · Charge · Whirlwind
	  The Hex Witch      (caster) Orb Nova · Hex Zones · Summon · Blink
	  The Bone Colossus  (heavy)  Meteor Rain · Shockwave (jump it!) · Stomp Combo
	  The Fallen Angel   (void)   Dark Descent · Feather Storm · Void Cross · Shadow Dash ·
	                              Blade Sweep · JUDGEMENT (pillars fall from the sky, then a
	                              slam floods the whole arena: hide behind a pillar)

	Bosses are not staggered by hits (MobManager / SkillManager), so a player
	hitting non-stop can't lock them out of their moves.

	Every boss arrives with an intro cinematic (BossIntro → BossCinematic on
	the clients) and can't be hurt during it. Each has a SIGNATURE move (its
	`signature`, at least every few moves): while it runs the boss is
	INVULNERABLE ("BossInvulnerable"; SkillManager deals nothing and shows
	IMMUNE), wrapped in a golden barrier with a label over its head.
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local PhysicsService = game:GetService("PhysicsService")

-- A swallowed player is held (anchored) inside the slime: their body must
-- not collide with it, or the physics shoves the slime out of the way, down
-- through the floor.
local SWALLOWED = "Swallowed"
pcall(function()
	PhysicsService:RegisterCollisionGroup(SWALLOWED)
	PhysicsService:CollisionGroupSetCollidable(SWALLOWED, "Default", false)
end)
local function setGroup(char: Model, group: string)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then d.CollisionGroup = group end
	end
end

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local DifficultyManager = require(script.Parent:WaitForChild("DifficultyManager"))
local Hazards = require(script.Parent:WaitForChild("Hazards"))

local BossAI = {}

export type Kind = {
	name: string,
	health: number, -- × the base boss health
	damage: number, -- × the base boss damage
	xp: number,
	color: Color3,
	moves: { string },
	signature: string?, -- the move that makes it invulnerable while it runs
	gap: number?,       -- seconds between its moves (GAP otherwise; less enraged)
}

BossAI.Kinds = {
	warlord = {
		name = "★ The Iron Warlord", health = 3.5, damage = 1.2, xp = 3,
		color = Color3.fromRGB(255, 90, 40), moves = { "slam", "charge", "whirlwind" }, signature = "whirlwind",
	},
	witch = {
		name = "★ The Hex Witch", health = 2.8, damage = 1, xp = 3,
		color = Color3.fromRGB(120, 255, 120), moves = { "nova", "hex", "summon", "blink" }, signature = "nova",
	},
	colossus = {
		name = "★ The Bone Colossus", health = 4.5, damage = 1.4, xp = 3.5,
		color = Color3.fromRGB(255, 170, 60), moves = { "meteors", "shockwave", "stomp" }, signature = "meteors",
	},
	fallen_angel = {
		name = "★ Malakor, The Fallen Angel", health = 4.2, damage = 1.3, xp = 4,
		color = Color3.fromRGB(225, 35, 45),
		moves = { "dark_descent", "feather_storm", "void_cross", "shadow_dash", "blade_sweep", "judgement" },
		signature = "judgement", gap = 1.4,
	},
} :: { [string]: Kind }

-- What each signature move is called on screen.
local SIGNATURE_NAMES: { [string]: string } = {
	whirlwind = "IRON CYCLONE",
	nova = "HEX NOVA",
	meteors = "METEOR RAIN",
	judgement = "JUDGEMENT FROM ON HIGH",
}
-- A signature move comes at least this often (every Nth move).
local SIGNATURE_EVERY = 4
-- The intro cinematic: the boss holds still (and can't be hurt) this long.
local INTRO_TIME = 3.6

function BossAI.KindIds(): { string }
	local ids = {}
	for id in pairs(BossAI.Kinds) do table.insert(ids, id) end
	table.sort(ids)
	return ids
end

-- Set by MobManager.Init.
type Deps = {
	canAct: (Model) -> boolean,           -- not frozen / paused / chilled
	hurt: (Model, number, Vector3?) -> (), -- damage a player (i-frames, curses); optional knockback origin
	spawnMinion: (Vector3) -> Model?,
	roomAt: (Vector3) -> { minX: number, maxX: number, minZ: number, maxZ: number, floorY: number }?, -- the room's flat bounds
}
local deps: Deps

local BASE_DAMAGE = 25
local TELEGRAPH = Color3.fromRGB(255, 50, 40)
local GAP = 0.9          -- seconds between moves
local GAP_ENRAGED = 0.45

-- ── Helpers ─────────────────────────────────────────────────────────────────
local fxFolder: Folder? = nil
local function fx(): Folder
	if fxFolder and fxFolder.Parent then return fxFolder end
	local f = Instance.new("Folder")
	f.Name = "BossFX"
	f.Parent = Workspace
	fxFolder = f
	return f
end

local function part(props: { [string]: any }, class: string?): BasePart
	local p = Instance.new(class or "Part") :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = fx()
	return p
end

local FLAT = CFrame.Angles(0, 0, math.rad(90)) -- cylinder lying flat

type Victim = { char: Model, root: BasePart, hum: Humanoid }

local function victims(): { Victim }
	local out = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char and plr:GetAttribute("InLobby") ~= true then
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				table.insert(out, { char = char, root = root, hum = hum })
			end
		end
	end
	return out
end

local function flatDist(a: Vector3, b: Vector3): number
	return Vector3.new(a.X - b.X, 0, a.Z - b.Z).Magnitude
end

-- Red disc that fills up over `t`, then is removed. Blocks for `t`.
local function telegraphCircle(center: Vector3, radius: number, t: number, floorY: number)
	local pos = Vector3.new(center.X, floorY + 0.08, center.Z)
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, radius * 2, radius * 2),
		CFrame = CFrame.new(pos) * FLAT, Color = TELEGRAPH, Transparency = 0.65 })
	local fill = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.2, 0.2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.02, 0)) * FLAT, Color = TELEGRAPH, Transparency = 0.35 })
	TweenService:Create(fill, TweenInfo.new(t, Enum.EasingStyle.Linear), { Size = Vector3.new(0.14, radius * 2, radius * 2) }):Play()
	Debris:AddItem(ring, t)
	Debris:AddItem(fill, t)
end

local function telegraphLine(from: Vector3, dir: Vector3, length: number, width: number, t: number, floorY: number)
	local mid = from + dir * (length / 2)
	local cf = CFrame.lookAt(Vector3.new(mid.X, floorY + 0.1, mid.Z), Vector3.new(mid.X + dir.X, floorY + 0.1, mid.Z + dir.Z))
	local bar = part({ Size = Vector3.new(width, 0.12, length), CFrame = cf, Color = TELEGRAPH, Transparency = 0.55 })
	Debris:AddItem(bar, t)
end

-- A long telegraph bar starting at `from` (beams, dashes).
local function telegraphBeam(from: Vector3, dir: Vector3, length: number, width: number, t: number, floorY: number)
	telegraphLine(from, dir, length, width, t, floorY)
end

-- A flat triangle a-b-c, out of two wedges.
local function triangle(a: Vector3, b: Vector3, c: Vector3, props: { [string]: any }): { BasePart }
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local right = ac:Cross(ab).Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	local w1 = part(props, "WedgePart")
	w1.Size = Vector3.new(0.1, height, math.abs(ab:Dot(back)))
	w1.CFrame = CFrame.fromMatrix((a + b) / 2, right, up, back)
	local w2 = part(props, "WedgePart")
	w2.Size = Vector3.new(0.1, height, math.abs(ac:Dot(back)))
	w2.CFrame = CFrame.fromMatrix((a + c) / 2, -right, up, -back)
	return { w1, w2 }
end

-- A red fan on the floor, `radius` out from `origin` and `half` (radians)
-- to either side of flat `dir`, deepening over `t`, then removed.
local function telegraphCone(origin: Vector3, dir: Vector3, radius: number, half: number, t: number, floorY: number)
	local o = Vector3.new(origin.X, floorY + 0.1, origin.Z)
	local base = math.atan2(dir.Z, dir.X)
	local n = math.max(2, math.ceil(half * 2 / math.rad(14)))
	local step = half * 2 / n
	for i = 0, n - 1 do
		local a1, a2 = base - half + i * step, base - half + (i + 1) * step
		local p1 = o + Vector3.new(math.cos(a1), 0, math.sin(a1)) * radius
		local p2 = o + Vector3.new(math.cos(a2), 0, math.sin(a2)) * radius
		for _, w in ipairs(triangle(o, p1, p2, { Color = TELEGRAPH, Transparency = 0.7 })) do
			TweenService:Create(w, TweenInfo.new(t, Enum.EasingStyle.Linear), { Transparency = 0.4 }):Play()
			Debris:AddItem(w, t)
		end
	end
end

-- An expanding flat shock ring for impacts.
local function shock(center: Vector3, radius: number, color: Color3, floorY: number)
	local ring = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 2, 2),
		CFrame = CFrame.new(Vector3.new(center.X, floorY + 0.2, center.Z)) * FLAT, Color = color, Transparency = 0.1 })
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.1, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.4)
end

-- Damage every player within `radius` (flat) of `center`, once.
local function blast(center: Vector3, radius: number, damage: number)
	for _, v in ipairs(victims()) do
		if flatDist(v.root.Position, center) <= radius then
			deps.hurt(v.char, damage, center)
		end
	end
end

-- ── A boss instance ─────────────────────────────────────────────────────────
type Boss = {
	model: Model,
	hum: Humanoid,
	root: BasePart,
	kind: Kind,
	floorY: number,
	damage: number,
	enraged: boolean,
	minions: { Model },
	home: Vector3,          -- where it spawned (the arena's middle)
	lockedHealth: number?,  -- its health while invulnerable
	runId: any,
	mover: any?,            -- the Fallen Angel's flight aligners (takeOff)
	flying: boolean?,
}

-- Everyone in this boss's run (for its cinematic effects).
local function runPlayers(b: Boss): { Player }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if (b.runId == nil or p:GetAttribute("RunId") == b.runId) and p:GetAttribute("InLobby") == false then
			table.insert(out, p)
		end
	end
	return out
end

local function bossFX(b: Boss, data: { [string]: any })
	data.model = b.model
	data.color = b.kind.color
	local remote = Network.GetRemoteEvent(Network.Remotes.BossFX)
	for _, p in ipairs(runPlayers(b)) do remote:FireClient(p, data) end
end

-- ── Invulnerability (intro, signature moves) ────────────────────────────────
-- SkillManager deals nothing to a boss with "BossInvulnerable" (it shows
-- IMMUNE); anything else that takes health off meanwhile is put back
-- (Attach's HealthChanged). `label` shows a golden barrier and a tag over its
-- head so everyone sees why their hits do nothing.
local function setInvulnerable(b: Boss, on: boolean, label: string?)
	local old = b.model:FindFirstChild("InvulnBarrier")
	if old then old:Destroy() end
	local oldTag = b.root:FindFirstChild("InvulnTag")
	if oldTag then oldTag:Destroy() end
	if not on then
		b.model:SetAttribute("BossInvulnerable", nil)
		b.lockedHealth = nil
		return
	end
	b.lockedHealth = b.hum.Health
	b.model:SetAttribute("BossInvulnerable", true)
	if not label then return end
	local box, size = b.model:GetBoundingBox()
	-- (sized to its body, not its reach: the Fallen Angel's wingspan would
	-- swallow half the screen)
	local d = math.clamp(math.max(size.Y, math.min(size.X, size.Z)) + 2.5, 7, 30)
	local barrier = Instance.new("Part")
	barrier.Name = "InvulnBarrier"
	barrier.Shape = Enum.PartType.Ball
	barrier.Size = Vector3.one * 1
	barrier.CFrame = CFrame.new(box.Position)
	barrier.Material = Enum.Material.ForceField
	barrier.Color = Color3.fromRGB(255, 215, 110)
	barrier.Transparency = 0.15
	barrier.CanCollide = false
	barrier.CanQuery = false
	barrier.CanTouch = false
	barrier.CastShadow = false
	barrier.Massless = true
	barrier.Parent = b.model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = b.root
	weld.Part1 = barrier
	weld.Parent = barrier
	TweenService:Create(barrier, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Size = Vector3.one * d }):Play()
	local tag = Instance.new("BillboardGui")
	tag.Name = "InvulnTag"
	tag.Size = UDim2.fromOffset(260, 46)
	tag.StudsOffset = Vector3.new(0, box.Position.Y - b.root.Position.Y + size.Y * 0.5 + 6, 0)
	tag.AlwaysOnTop = true
	tag.LightInfluence = 0
	tag.MaxDistance = 160
	tag.Parent = b.root
	local top = Instance.new("TextLabel")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0.55, 0)
	top.Font = Enum.Font.GothamBlack
	top.TextScaled = true
	top.TextColor3 = Color3.fromRGB(255, 220, 120)
	top.TextStrokeColor3 = Color3.fromRGB(40, 20, 0)
	top.TextStrokeTransparency = 0.2
	top.Text = "INVULNERABLE"
	top.Parent = tag
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0, 0.58)
	sub.Size = UDim2.new(1, 0, 0.42, 0)
	sub.Font = Enum.Font.GothamBold
	sub.TextScaled = true
	sub.TextColor3 = b.kind.color:Lerp(Color3.new(1, 1, 1), 0.4)
	sub.TextStrokeTransparency = 0.3
	sub.Text = label
	sub.Parent = tag
end

local function alive(b: Boss): boolean
	return b.model.Parent ~= nil and b.hum.Health > 0 and b.root.Parent ~= nil
end

-- Wait `t` seconds of *active* time (paused while the boss can't act).
local function hold(b: Boss, t: number): boolean
	local left = t
	while left > 0 do
		local dt = task.wait(0.05)
		if not alive(b) then return false end
		if deps.canAct(b.model) then left -= dt end
	end
	return true
end

local function nearestVictim(b: Boss): Victim?
	local best, bestD = nil, 90
	for _, v in ipairs(victims()) do
		local d = (v.root.Position - b.root.Position).Magnitude
		if d < bestD and v.char:GetAttribute("Hidden") ~= true then best, bestD = v, d end
	end
	return best
end

local function face(b: Boss, pos: Vector3)
	local flat = Vector3.new(pos.X, b.root.Position.Y, pos.Z)
	if (flat - b.root.Position).Magnitude > 0.1 then
		b.root.CFrame = CFrame.lookAt(b.root.Position, flat)
		-- (the Fallen Angel's turning aligner would only turn it back)
		local m = b.mover
		if m then m.rot.CFrame = b.root.CFrame.Rotation end
	end
end

local function dmg(b: Boss, mult: number): number
	return BASE_DAMAGE * b.damage * mult
end

-- ── Iron Warlord ────────────────────────────────────────────────────────────
local MOVES: { [string]: (Boss, Victim) -> () } = {}

MOVES.slam = function(b, target)
	-- Leap onto the target's spot, then a big circular slam.
	local r = if b.enraged then 16 else 13
	local spot = target.root.Position
	telegraphCircle(spot, r, 1.0, b.floorY)
	face(b, spot)
	if not hold(b, 0.55) then return end
	local from = b.root.Position
	local land = Vector3.new(spot.X, from.Y, spot.Z)
	for i = 1, 8 do
		local a = i / 8
		b.root.CFrame = CFrame.new(from:Lerp(land, a) + Vector3.new(0, math.sin(a * math.pi) * 8, 0)) * b.root.CFrame.Rotation
		task.wait(0.055)
	end
	b.root.AssemblyLinearVelocity = Vector3.zero
	blast(spot, r, dmg(b, 1.5))
	shock(spot, r, b.kind.color, b.floorY)
	if b.enraged then
		-- Aftershocks ripple outward.
		for k = 1, 3 do
			if not hold(b, 0.35) then return end
			local rr = r + k * 5
			shock(spot, rr, TELEGRAPH, b.floorY)
			for _, v in ipairs(victims()) do
				local d = flatDist(v.root.Position, spot)
				if d > rr - 5 and d <= rr then deps.hurt(v.char, dmg(b, 0.6), spot) end
			end
		end
	end
	hold(b, 0.5)
end

MOVES.charge = function(b, target)
	local dir = Vector3.new(target.root.Position.X - b.root.Position.X, 0, target.root.Position.Z - b.root.Position.Z)
	if dir.Magnitude < 1 then return end
	dir = dir.Unit
	local length = 46
	local charges = if b.enraged then 2 else 1
	for _ = 1, charges do
		telegraphLine(b.root.Position, dir, length, 7, 0.75, b.floorY)
		face(b, b.root.Position + dir)
		if not hold(b, 0.75) then return end
		local hit: { [Model]: boolean } = {}
		local start = b.root.Position
		local t0 = os.clock()
		local dur = 0.55
		while os.clock() - t0 < dur and alive(b) do
			local a = (os.clock() - t0) / dur
			local pos = start + dir * length * a
			-- Stop at walls.
			local params = RaycastParams.new()
			params.FilterType = Enum.RaycastFilterType.Exclude
			local ignore: { Instance } = { b.model, fx() }
			local mobs = Workspace:FindFirstChild("Mobs")
			if mobs then table.insert(ignore, mobs) end
			for _, v in ipairs(victims()) do table.insert(ignore, v.char) end
			params.FilterDescendantsInstances = ignore
			if Workspace:Raycast(b.root.Position, dir * 3, params) then break end
			b.root.CFrame = CFrame.new(pos) * b.root.CFrame.Rotation
			for _, v in ipairs(victims()) do
				if not hit[v.char] and (v.root.Position - b.root.Position).Magnitude <= 5.5 then
					hit[v.char] = true
					deps.hurt(v.char, dmg(b, 1.3), b.root.Position)
				end
			end
			RunService.Heartbeat:Wait()
		end
		b.root.AssemblyLinearVelocity = Vector3.zero
		shock(b.root.Position, 6, b.kind.color, b.floorY)
		if not hold(b, 0.35) then return end
		local nextTarget = nearestVictim(b)
		if not nextTarget then return end
		local d = Vector3.new(nextTarget.root.Position.X - b.root.Position.X, 0, nextTarget.root.Position.Z - b.root.Position.Z)
		if d.Magnitude < 1 then return end
		dir = d.Unit
	end
	hold(b, 0.4)
end

MOVES.whirlwind = function(b, target)
	-- Spin toward the players, hurting everything close.
	local radius = 8
	local spinner = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, radius * 2, radius * 2),
		Color = b.kind.color, Transparency = 0.6 })
	telegraphCircle(b.root.Position, radius, 0.6, b.floorY)
	if not hold(b, 0.6) then spinner:Destroy() return end
	local dur = if b.enraged then 3.4 else 2.4
	local speed = b.hum.WalkSpeed * 1.5
	local t0 = os.clock()
	local lastHit = 0
	while os.clock() - t0 < dur and alive(b) do
		local v = nearestVictim(b)
		if v and deps.canAct(b.model) then
			local d = Vector3.new(v.root.Position.X - b.root.Position.X, 0, v.root.Position.Z - b.root.Position.Z)
			if d.Magnitude > 1 then
				b.root.CFrame = CFrame.new(b.root.Position + d.Unit * speed * 0.05) * CFrame.Angles(0, (os.clock() - t0) * 18, 0)
			end
		end
		spinner.CFrame = CFrame.new(Vector3.new(b.root.Position.X, b.floorY + 1, b.root.Position.Z)) * FLAT
		if os.clock() - lastHit > 0.35 then
			lastHit = os.clock()
			blast(b.root.Position, radius, dmg(b, 0.45))
		end
		task.wait(0.05)
	end
	spinner:Destroy()
	hold(b, 0.6)
end

-- ── Hex Witch ───────────────────────────────────────────────────────────────
local function orb(b: Boss, from: Vector3, dir: Vector3, speed: number, damage: number)
	local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.4, CFrame = CFrame.new(from), Color = b.kind.color })
	ball:AddTag("EnemyProjectile")
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = b.kind.color, 6, 1.5
	light.Parent = ball
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function(dt)
		if os.clock() - t0 > 3.5 or not ball.Parent then
			if conn then conn:Disconnect() end
			ball:Destroy()
			return
		end
		ball.CFrame = ball.CFrame + dir * speed * dt
		for _, v in ipairs(victims()) do
			if (v.root.Position - ball.Position).Magnitude <= 2.4 then
				deps.hurt(v.char, damage, ball.Position)
				if conn then conn:Disconnect() end
				ball:Destroy()
				return
			end
		end
	end)
end

MOVES.nova = function(b, _target)
	-- Rings of orbs, each wave turned a little.
	local waves = if b.enraged then 5 else 3
	local count = if b.enraged then 16 else 12
	local glow = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = b.root.CFrame, Color = b.kind.color, Transparency = 0.3 })
	TweenService:Create(glow, TweenInfo.new(0.7), { Size = Vector3.one * 9, Transparency = 1 }):Play()
	Debris:AddItem(glow, 0.75)
	if not hold(b, 0.7) then return end
	for w = 1, waves do
		local from = b.root.Position + Vector3.new(0, 0.5, 0)
		for i = 1, count do
			local a = (i / count) * math.pi * 2 + w * (math.pi / count)
			orb(b, from, Vector3.new(math.cos(a), 0, math.sin(a)), 26, dmg(b, 0.55))
		end
		if not hold(b, 0.45) then return end
	end
	hold(b, 0.4)
end

MOVES.hex = function(b, _target)
	-- Cursed circles under every player (and around them), then they erupt.
	local r = 6
	local spots = {}
	for _, v in ipairs(victims()) do
		if (v.root.Position - b.root.Position).Magnitude < 80 then
			table.insert(spots, v.root.Position)
			for _ = 1, (if b.enraged then 3 else 2) do
				local a = math.random() * math.pi * 2
				table.insert(spots, v.root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(6, 11))
			end
		end
	end
	for _, s in ipairs(spots) do telegraphCircle(s, r, 1.1, b.floorY) end
	if not hold(b, 1.1) then return end
	for _, s in ipairs(spots) do
		local pillar = part({ Size = Vector3.new(r * 1.2, 16, r * 1.2), CFrame = CFrame.new(Vector3.new(s.X, b.floorY + 8, s.Z)),
			Color = b.kind.color, Transparency = 0.3 })
		TweenService:Create(pillar, TweenInfo.new(0.4), { Size = Vector3.new(0.2, 22, 0.2), Transparency = 1 }):Play()
		Debris:AddItem(pillar, 0.45)
		blast(s, r, dmg(b, 1))
	end
	hold(b, 0.5)
end

MOVES.summon = function(b, _target)
	for i = #b.minions, 1, -1 do
		local m = b.minions[i]
		local h = m:FindFirstChildOfClass("Humanoid")
		if not m.Parent or not h or h.Health <= 0 then table.remove(b.minions, i) end
	end
	local want = (if b.enraged then 4 else 3)
	local room = 7 - #b.minions
	if room <= 0 then MOVES.nova(b, _target) return end
	for i = 1, math.min(want, room) do
		local a = (i / want) * math.pi * 2
		local pos = b.root.Position + Vector3.new(math.cos(a) * 7, 0, math.sin(a) * 7)
		telegraphCircle(pos, 2.5, 0.8, b.floorY)
		task.delay(0.8, function()
			if not alive(b) then return end
			local m = deps.spawnMinion(Vector3.new(pos.X, b.floorY, pos.Z))
			if m then table.insert(b.minions, m) end
			shock(pos, 4, b.kind.color, b.floorY)
		end)
	end
	hold(b, 1.2)
end

MOVES.blink = function(b, target)
	-- Vanish and reappear away from the target, leaving a burst behind.
	local from = b.root.Position
	shock(from, 7, b.kind.color, b.floorY)
	blast(from, 7, dmg(b, 0.8))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { b.model, fx() }
	for _ = 1, 10 do
		local a = math.random() * math.pi * 2
		local cand = target.root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(16, 24)
		local down = Workspace:Raycast(cand + Vector3.new(0, 6, 0), Vector3.new(0, -14, 0), params)
		local wall = Workspace:Raycast(target.root.Position, cand - target.root.Position, params)
		if down and not wall then
			b.root.CFrame = CFrame.new(Vector3.new(cand.X, from.Y, cand.Z))
			shock(cand, 5, b.kind.color, b.floorY)
			break
		end
	end
	hold(b, 0.4)
	MOVES.nova(b, target)
end

-- ── Bone Colossus ───────────────────────────────────────────────────────────
MOVES.meteors = function(b, _target)
	local count = if b.enraged then 16 else 10
	local r = 6
	for i = 1, count do
		local vs = victims()
		if #vs == 0 then break end
		local v = vs[math.random(1, #vs)]
		local a = math.random() * math.pi * 2
		local spot = v.root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(0, 7)
		telegraphCircle(spot, r, 1.0, b.floorY)
		task.delay(0.55, function()
			local rock = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 3.5,
				CFrame = CFrame.new(Vector3.new(spot.X, b.floorY + 45, spot.Z)), Color = b.kind.color, Material = Enum.Material.Neon })
			local fire = Instance.new("Fire")
			fire.Color, fire.SecondaryColor, fire.Size = b.kind.color, Color3.fromRGB(80, 20, 10), 8
			fire.Parent = rock
			TweenService:Create(rock, TweenInfo.new(0.45, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ CFrame = CFrame.new(Vector3.new(spot.X, b.floorY + 1, spot.Z)) }):Play()
			task.delay(0.45, function()
				rock:Destroy()
				shock(spot, r, b.kind.color, b.floorY)
				blast(spot, r, dmg(b, 0.9))
			end)
		end)
		if not hold(b, if b.enraged then 0.16 else 0.24) then return end
	end
	hold(b, 1.2)
end

MOVES.shockwave = function(b, _target)
	-- Rings of force roll out along the ground: jump over them.
	local rings = if b.enraged then 3 else 2
	telegraphCircle(b.root.Position, 5, 0.8, b.floorY)
	if not hold(b, 0.8) then return end
	for _ = 1, rings do
		local center = b.root.Position
		shock(center, 6, b.kind.color, b.floorY)
		local segs = {}
		for i = 1, 28 do
			segs[i] = part({ Size = Vector3.new(1.4, 1.6, 2.6), Color = b.kind.color, Transparency = 0.15 })
		end
		local hit: { [Model]: boolean } = {}
		local r = 3
		task.spawn(function()
			while r < 48 do
				local dt = RunService.Heartbeat:Wait()
				r += 26 * dt
				for i, sgm in ipairs(segs) do
					local a = (i / #segs) * math.pi * 2
					local p = Vector3.new(center.X + math.cos(a) * r, b.floorY + 0.8, center.Z + math.sin(a) * r)
					sgm.CFrame = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
					sgm.Size = Vector3.new(r * 2 * math.pi / #segs + 0.4, 1.6, 1.4)
				end
				for _, v in ipairs(victims()) do
					local d = flatDist(v.root.Position, center)
					-- Airborne players clear the wave.
					if not hit[v.char] and math.abs(d - r) <= 1.8 and v.hum.FloorMaterial ~= Enum.Material.Air then
						hit[v.char] = true
						deps.hurt(v.char, dmg(b, 0.9), center)
					end
				end
			end
			for _, sgm in ipairs(segs) do sgm:Destroy() end
		end)
		if not hold(b, 0.9) then return end
	end
	hold(b, 0.8)
end

MOVES.stomp = function(b, target)
	-- Three heavy stomps chasing the target's position.
	local stomps = if b.enraged then 4 else 3
	local r = 9
	for _ = 1, stomps do
		local v = nearestVictim(b) or target
		local spot = v.root.Position
		face(b, spot)
		telegraphCircle(spot, r, 0.65, b.floorY)
		if not hold(b, 0.65) then return end
		shock(spot, r, b.kind.color, b.floorY)
		blast(spot, r, dmg(b, 1.1))
	end
	hold(b, 0.7)
end


-- One rolling ring of force from the boss (jump it). Used by the Slime's Split.
MOVES.shockwaveOnce = function(b, _target)
	local center = b.root.Position
	local color = b.kind.color
	local segs = {}
	for i = 1, 28 do
		segs[i] = part({ Size = Vector3.new(1.4, 1.6, 2.6), Color = color, Transparency = 0.15 })
	end
	local hit: { [Model]: boolean } = {}
	local r = 3
	task.spawn(function()
		while r < 40 do
			local dt = RunService.Heartbeat:Wait()
			r += 28 * dt
			for i, sgm in ipairs(segs) do
				local a = (i / #segs) * math.pi * 2
				local p = Vector3.new(center.X + math.cos(a) * r, b.floorY + 0.8, center.Z + math.sin(a) * r)
				sgm.CFrame = CFrame.lookAt(p, Vector3.new(center.X, p.Y, center.Z))
				sgm.Size = Vector3.new(r * 2 * math.pi / #segs + 0.4, 1.6, 1.4)
			end
			for _, v in ipairs(victims()) do
				local d = flatDist(v.root.Position, center)
				if not hit[v.char] and math.abs(d - r) <= 1.8 and v.hum.FloorMaterial ~= Enum.Material.Air then
					hit[v.char] = true
					deps.hurt(v.char, dmg(b, 0.8), center)
				end
			end
		end
		for _, sgm in ipairs(segs) do sgm:Destroy() end
	end)
end

-- ── Slime King ──────────────────────────────────────────────────────────────
local GOO = Color3.fromRGB(110, 235, 90)

local function scaleBoss(b: Boss, s: number)
	pcall(function() b.model:ScaleTo(s) end)
end

local function groundAt(pos: Vector3, b: Boss): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { b.model, fx() }
	for _, v in ipairs(victims()) do table.insert(ignore, v.char) end
	params.FilterDescendantsInstances = ignore
	local hit = Workspace:Raycast(pos + Vector3.new(0, 6, 0), Vector3.new(0, -20, 0), params)
	return if hit then hit.Position.Y else b.floorY
end


-- A goo puddle that burns anyone standing in it for `life` seconds.
local function puddle(b: Boss, center: Vector3, r: number, life: number)
	local y = groundAt(center, b)
	local disc = part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.5, 0.5),
		CFrame = CFrame.new(center.X, y + 0.08, center.Z) * FLAT, Color = GOO, Transparency = 0.35 })
	TweenService:Create(disc, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.12, r * 2, r * 2) }):Play()
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < life and disc.Parent do
			task.wait(0.5)
			blast(center, r, dmg(b, 0.18))
		end
		TweenService:Create(disc, TweenInfo.new(0.4), { Transparency = 1 }):Play()
		Debris:AddItem(disc, 0.45)
	end)
end

-- ── The Fallen Angel ────────────────────────────────────────────────────────
-- Malakor flies its moves. While one runs, its root is steered by two rigid
-- aligners (takeOff / glide / touchDown): it swoops smoothly on every client
-- (it's physics, so it's interpolated) with no humanoid fighting it. Between
-- moves a soft aligner keeps it turned toward its prey. "AngelPose" (windup,
-- slash, plunge, rise, dive, slam, cast, volley, dash) is the pose
-- FallenAngelFX moves its body into; each attack's picture is AngelAttackFX's,
-- on every client (bossFX kind "angel" / "judgement"). The red telegraphs and
-- the damage are here.
local CELESTIAL_DARK = Color3.fromRGB(200, 28, 40) -- (the angel is black, white and blood red)
local VOID_CRIMSON = Color3.fromRGB(255, 70, 60)

local function pose(b: Boss, name: string?)
	if b.model.Parent then b.model:SetAttribute("AngelPose", name) end
end

-- Where its root is when it stands on the floor.
local function standY(b: Boss): number
	return b.floorY + b.root.Size.Y / 2 + b.hum.HipHeight
end

-- Its rotation turned (flat) toward `to`.
local function flatLook(b: Boss, to: Vector3): CFrame
	local from = b.root.Position
	local d = Vector3.new(to.X - from.X, 0, to.Z - from.Z)
	if d.Magnitude < 0.1 then return b.root.CFrame.Rotation end
	return CFrame.lookAt(Vector3.zero, d)
end

type Mover = { att: Attachment, pos: AlignPosition, rot: AlignOrientation }

local function mover(b: Boss): Mover
	local m = b.mover :: Mover?
	if m and m.att.Parent then return m end
	local att = Instance.new("Attachment")
	att.Name = "FlyAtt"
	att.Parent = b.root
	local ap = Instance.new("AlignPosition")
	ap.Name = "FlyPos"
	ap.Mode = Enum.PositionAlignmentMode.OneAttachment
	ap.Attachment0 = att
	ap.RigidityEnabled = true
	ap.Enabled = false
	ap.Parent = b.root
	local ao = Instance.new("AlignOrientation")
	ao.Name = "FlyRot"
	ao.Mode = Enum.OrientationAlignmentMode.OneAttachment
	ao.Attachment0 = att
	ao.MaxTorque = math.huge
	ao.MaxAngularVelocity = math.huge
	ao.Responsiveness = 12
	ao.CFrame = b.root.CFrame.Rotation
	ao.Enabled = false
	ao.Parent = b.root
	local made: Mover = { att = att, pos = ap, rot = ao }
	b.mover = made
	return made
end

-- Turn it (smoothly, while it's on its feet) toward `pos`.
local function turnTo(b: Boss, pos: Vector3)
	local m = mover(b)
	m.rot.CFrame = flatLook(b, pos)
	m.rot.Enabled = true
end

-- Off its feet: glide() steers it from here.
local function takeOff(b: Boss)
	local m = mover(b)
	m.pos.Position = b.root.Position
	m.rot.CFrame = b.root.CFrame.Rotation
	m.rot.RigidityEnabled = true
	m.pos.Enabled, m.rot.Enabled = true, true
	b.flying = true
	-- (the server must own it, or the aligners steer nothing)
	if not b.root.Anchored then pcall(function() b.root:SetNetworkOwner(nil) end) end
end

-- Back on its feet where it is, walking again.
local function touchDown(b: Boss)
	local m = b.mover :: Mover?
	if not m or not b.flying then return end
	b.flying = false
	m.pos.Enabled = false
	m.rot.RigidityEnabled = false
	if b.root.Parent then
		b.root.AssemblyLinearVelocity = Vector3.zero
		b.root.AssemblyAngularVelocity = Vector3.zero
	end
end

-- Steer the flying angel to `cf` over `t` seconds of active time, eased;
-- `onStep(pos)` every frame on the way. False if it died meanwhile.
local function glide(b: Boss, cf: CFrame, t: number, style: Enum.EasingStyle?, dir: Enum.EasingDirection?, onStep: ((Vector3) -> ())?): boolean
	local m = mover(b)
	local p0, r0, r1 = m.pos.Position, m.rot.CFrame, cf.Rotation
	local s, d = style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out
	local el = 0
	while el < t do
		local dt = RunService.Heartbeat:Wait()
		if not alive(b) then return false end
		if deps.canAct(b.model) then el += dt end
		local a = TweenService:GetValue(math.min(el / t, 1), s, d)
		local p = p0:Lerp(cf.Position, a)
		m.pos.Position = p
		m.rot.CFrame = r0:Lerp(r1, a)
		if onStep then onStep(p) end
	end
	return true
end

-- What its flights stop short of: walls, pillars, scenery (not players,
-- mobs or effects).
local function solidParams(b: Boss): RaycastParams
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = { b.model, fx() }
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(ignore, mobs) end
	for _, v in ipairs(victims()) do table.insert(ignore, v.char) end
	params.FilterDescendantsInstances = ignore
	params.RespectCanCollide = true
	return params
end

-- How far it can go from `from` along flat `dir` (up to `len`), `margin`
-- short of anything solid.
local function reach(b: Boss, from: Vector3, dir: Vector3, len: number, margin: number): number
	local origin = Vector3.new(from.X, b.floorY + 4, from.Z)
	local hit = Workspace:Raycast(origin, dir * (len + margin), solidParams(b))
	return if hit then math.max(0, (hit.Position - origin).Magnitude - margin) else len
end

MOVES.dark_descent = function(b, target)
	-- Up into the air over its prey, then down like a falling star: a crater
	-- of void fire where it lands (enraged, an aftershock rolls out past it).
	local r = if b.enraged then 12 else 10
	local wind = if b.enraged then 1.0 else 1.25
	local from = b.root.Position
	local spot = target.root.Position
	local d = Vector3.new(spot.X - from.X, 0, spot.Z - from.Z)
	if d.Magnitude > 1 then
		spot = from + d.Unit * reach(b, from, d.Unit, d.Magnitude, 4) -- (short of a wall)
	end
	spot = Vector3.new(spot.X, b.floorY, spot.Z)
	telegraphCircle(spot, r, wind, b.floorY)
	bossFX(b, { kind = "angel", move = "descent", phase = "rise", pos = spot, radius = r, duration = wind })
	pose(b, "rise")
	takeOff(b)
	local look = flatLook(b, spot)
	local top = standY(b) + 15
	local mid = from:Lerp(spot, 0.5)
	if not glide(b, CFrame.new(mid.X, top, mid.Z) * look, wind * 0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out) then return end
	if not glide(b, CFrame.new(spot.X, top + 2, spot.Z) * look, wind * 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) then return end
	pose(b, "dive")
	if not glide(b, CFrame.new(spot.X, standY(b), spot.Z) * look, wind * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In) then return end
	pose(b, "slam")
	touchDown(b)
	blast(spot, r, dmg(b, 0.9))
	shock(spot, r, CELESTIAL_DARK, b.floorY)
	bossFX(b, { kind = "angel", move = "descent", phase = "impact", pos = spot, radius = r })
	if b.enraged then
		local rr = r + 8
		telegraphCircle(spot, rr, 0.55, b.floorY)
		if not hold(b, 0.55) then return end
		shock(spot, rr, VOID_CRIMSON, b.floorY)
		bossFX(b, { kind = "angel", move = "descent", phase = "aftershock", pos = spot, radius = rr })
		for _, v in ipairs(victims()) do
			local dd = flatDist(v.root.Position, spot)
			if dd > r and dd <= rr then deps.hurt(v.char, dmg(b, 0.45), spot) end
		end
	end
	hold(b, 0.55)
end

MOVES.feather_storm = function(b, target)
	-- Its wings flare and loose a storm of feather blades, each at a spot by
	-- a player (red where it will land): keep moving.
	local count = if b.enraged then 9 else 6
	local warnT = if b.enraged then 0.7 else 0.85
	local every = if b.enraged then 0.12 else 0.16
	local flight = 0.3
	local r = 4.5
	face(b, target.root.Position)
	pose(b, "volley")
	if not hold(b, 0.3) then return end
	local list: { Victim } = {}
	for _, v in ipairs(victims()) do
		if flatDist(v.root.Position, b.root.Position) < 90 then table.insert(list, v) end
	end
	if #list == 0 then return end
	for i = 1, count do
		local v = list[(i - 1) % #list + 1]
		if v.root.Parent then
			-- (leading a running player a little)
			local vel = v.root.AssemblyLinearVelocity
			local a = math.random() * math.pi * 2
			local spot = v.root.Position + Vector3.new(vel.X, 0, vel.Z) * 0.25 + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random() * 3
			spot = Vector3.new(spot.X, b.floorY, spot.Z)
			-- out of the wings: fanned above and behind it
			local k = (i - 0.5) / count
			local cf = b.root.CFrame
			local from = cf.Position + cf.RightVector * ((k * 2 - 1) * 9) + Vector3.new(0, 7 + math.sin(k * math.pi) * 4, 0) - cf.LookVector * 2
			telegraphCircle(spot, r, warnT, b.floorY)
			bossFX(b, { kind = "angel", move = "feather", from = from, pos = spot, delay = warnT - flight, flight = flight, radius = r })
			task.delay(warnT, function()
				if not alive(b) then return end
				blast(spot, r, dmg(b, 0.4))
				shock(spot, r, CELESTIAL_DARK, b.floorY)
			end)
		end
		if not hold(b, every) then return end
	end
	hold(b, warnT)
end

MOVES.void_cross = function(b, target)
	-- It drives its sword into the floor and void fire runs out along a cross
	-- from it (enraged: a second cross, turned 45°, right behind).
	face(b, target.root.Position)
	local center = Vector3.new(b.root.Position.X, b.floorY, b.root.Position.Z)
	local width = 8
	local speed = 85
	local look = b.root.CFrame.LookVector
	local turn0 = math.atan2(look.Z, look.X)
	local crosses = if b.enraged then 2 else 1
	for c = 1, crosses do
		local wind = if c > 1 then 0.65 elseif b.enraged then 0.85 else 1.05
		local arms = {}
		for k = 0, 3 do
			local a = turn0 + (c - 1) * math.pi / 4 + k * math.pi / 2
			local dir = Vector3.new(math.cos(a), 0, math.sin(a))
			local len = math.max(6, reach(b, center, dir, 46, 2))
			telegraphBeam(center, dir, len, width, wind, b.floorY)
			table.insert(arms, { dir = dir, len = len })
		end
		bossFX(b, { kind = "angel", move = "cross", phase = "warn", pos = center, arms = arms, width = width, duration = wind })
		pose(b, "windup")
		if not hold(b, wind) then return end
		pose(b, "plunge")
		bossFX(b, { kind = "angel", move = "cross", phase = "erupt", pos = center, arms = arms, width = width, speed = speed })
		shock(center, 9, VOID_CRIMSON, b.floorY)
		-- the fire runs out along every arm at `speed`; it catches each player once
		local hit: { [Model]: boolean } = {}
		local longest = 0
		for _, arm in ipairs(arms) do longest = math.max(longest, arm.len) end
		local t0 = os.clock()
		while alive(b) do
			local front = (os.clock() - t0) * speed
			for _, v in ipairs(victims()) do
				if not hit[v.char] then
					local rel = v.root.Position - center
					for _, arm in ipairs(arms) do
						local along = rel.X * arm.dir.X + rel.Z * arm.dir.Z
						local across = math.abs(rel.X * arm.dir.Z - rel.Z * arm.dir.X)
						if along >= -width / 2 and along <= math.min(front, arm.len) and across <= width / 2 + 0.5 then
							hit[v.char] = true
							deps.hurt(v.char, dmg(b, 0.75), center)
							break
						end
					end
				end
			end
			if front > longest then break end
			RunService.Heartbeat:Wait()
		end
		if c < crosses and not hold(b, 0.2) then return end
	end
	hold(b, 0.5)
end

MOVES.shadow_dash = function(b, target)
	-- Wings folded, it streaks straight through its prey and out the far side
	-- (enraged: it wheels round and comes back for a second pass).
	local width = 9
	local passes = if b.enraged then 2 else 1
	local tgt = target
	for p = 1, passes do
		local from = b.root.Position
		local d = Vector3.new(tgt.root.Position.X - from.X, 0, tgt.root.Position.Z - from.Z)
		local look = b.root.CFrame.LookVector
		local dir = if d.Magnitude > 1 then d.Unit else Vector3.new(look.X, 0, look.Z).Unit
		local len = reach(b, from, dir, math.clamp(d.Magnitude + 14, 26, 46), 5)
		if len < 10 then break end
		local wind = if p > 1 then 0.6 elseif b.enraged then 0.75 else 0.9
		face(b, from + dir * 10)
		telegraphBeam(Vector3.new(from.X, b.floorY, from.Z), dir, len, width, wind, b.floorY)
		bossFX(b, { kind = "angel", move = "dash", phase = "warn", from = from, dir = dir, len = len, width = width, duration = wind })
		pose(b, "dash")
		if not hold(b, wind) then return end
		local to = from + dir * len
		bossFX(b, { kind = "angel", move = "dash", phase = "go", from = from, to = to, duration = 0.32 })
		takeOff(b)
		local hit: { [Model]: boolean } = {}
		local ok = glide(b, CFrame.new(to) * b.root.CFrame.Rotation, 0.32, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut, function(pos)
			for _, v in ipairs(victims()) do
				if not hit[v.char] and flatDist(v.root.Position, pos) <= width / 2 + 0.5 then
					hit[v.char] = true
					deps.hurt(v.char, dmg(b, 0.7), pos)
				end
			end
		end)
		touchDown(b)
		if not ok then return end
		shock(to, 7, VOID_CRIMSON, b.floorY)
		if p < passes then
			if not hold(b, 0.3) then return end
			tgt = nearestVictim(b) or tgt
		end
	end
	hold(b, 0.5)
end

MOVES.blade_sweep = function(b, target)
	-- The sword comes round in a great arc in front of it (a red fan first);
	-- enraged, it swings straight back the other way.
	local radius = if b.enraged then 20 else 18
	local half = math.rad(65)
	local swings = if b.enraged then 2 else 1
	local tgt = target
	for s = 1, swings do
		face(b, tgt.root.Position)
		local origin = Vector3.new(b.root.Position.X, b.floorY, b.root.Position.Z)
		local look = b.root.CFrame.LookVector
		local dir = Vector3.new(look.X, 0, look.Z).Unit
		local wind = if s > 1 then 0.6 elseif b.enraged then 0.75 else 0.9
		local side = if s == 1 then 1 else -1 -- (right to left, then back)
		telegraphCone(origin, dir, radius, half, wind, b.floorY)
		bossFX(b, { kind = "angel", move = "sweep", phase = "warn", pos = origin, dir = dir, radius = radius, half = half, side = side, duration = wind })
		pose(b, if side > 0 then "windup" else "slash")
		if not hold(b, wind) then return end
		pose(b, if side > 0 then "slash" else "windup")
		bossFX(b, { kind = "angel", move = "sweep", phase = "slash", pos = origin, dir = dir, radius = radius, half = half, side = side })
		for _, v in ipairs(victims()) do
			local rel = Vector3.new(v.root.Position.X - origin.X, 0, v.root.Position.Z - origin.Z)
			local dd = rel.Magnitude
			if dd <= radius + 1 and (dd < 4 or math.acos(math.clamp(rel.Unit:Dot(dir), -1, 1)) <= half + math.rad(5)) then
				deps.hurt(v.char, dmg(b, 0.75), origin)
			end
		end
		-- (its whole body turns through the swing)
		takeOff(b)
		local cf = b.root.CFrame
		glide(b, cf * CFrame.Angles(0, side * math.rad(35), 0), 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
		glide(b, cf, 0.3, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut)
		touchDown(b)
		if s < swings then
			if not hold(b, 0.25) then return end
			tgt = nearestVictim(b) or tgt
		end
	end
	hold(b, 0.45)
end

-- ── JUDGEMENT (the Fallen Angel's signature) ────────────────────────────────
-- Stone pillars crash down far out round the arena. Malakor rises over the
-- middle and gathers the void, then SLAMS down: a wave of void fire rolls out
-- over the whole room, and only a pillar's shelter is safe (behind one, as
-- seen from where it lands; the arena's own broken pillars count too).
-- AngelAttackFX lights the shelter up in gold while the void gathers. Caught
-- in the open, it takes half your health. Then the pillars crumble.
local PILLAR_STONE = Color3.fromRGB(205, 198, 215)
local PILLAR_GOLD = Color3.fromRGB(255, 215, 130)
local PILLAR_H, PILLAR_W = 18, 6
local PILLAR_DIST = 38 -- how far out from the middle they fall (and up to 6 more)
local WAVE_SPEED = 70  -- the slam's wave, studs a second
local WAVE_REACH = 120 -- (with no room bounds to go by)

-- The arena's own broken pillars (Hazards) in this run's dungeon.
local function arenaPillars(b: Boss): { BasePart }
	local out = {}
	for _, d in ipairs(Workspace:GetChildren()) do
		if d.Name == "GeneratedDungeon" and (b.runId == nil or d:GetAttribute("RunId") == b.runId) then
			local props = d:FindFirstChild("Props")
			local arena = props and props:FindFirstChild("ArenaHazards")
			for _, p in ipairs(if arena then arena:GetChildren() else {}) do
				if p.Name == "ArenaPillar" and p:IsA("BasePart") and flatDist(p.Position, b.home) < WAVE_REACH then
					table.insert(out, p)
				end
			end
		end
	end
	return out
end

-- A spot for a pillar `dist` out from the middle at angle `a`: open floor,
-- clear of lava and vents, with room behind it to hide. Nil if not.
local function pillarSpot(b: Boss, a: number, dist: number): Vector3?
	local mid = Vector3.new(b.home.X, b.floorY, b.home.Z)
	local dir = Vector3.new(math.cos(a), 0, math.sin(a))
	if reach(b, mid, dir, dist + 12, 2) < dist + 12 then return nil end
	local at = mid + dir * dist
	if Hazards.Near(at, PILLAR_W) or Hazards.Near(at + dir * 7, 3) then return nil end
	local params = solidParams(b)
	if not Workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -8, 0), params) then return nil end
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = params.FilterDescendantsInstances
	op.RespectCanCollide = true
	if #Workspace:GetPartBoundsInBox(CFrame.new(at + Vector3.new(0, 4.5, 0)), Vector3.new(PILLAR_W + 2, 6, PILLAR_W + 2), op) > 0 then return nil end
	return at
end

-- A marble pillar with a gold cap and a band of runes falls from the sky
-- onto `at` over `fall` seconds. Its parts go in `parts` (to crumble), the
-- pillar itself (what blocks the wave) in `pillars`.
local function dropPillar(b: Boss, at: Vector3, fall: number, pillars: { BasePart }, parts: { BasePart })
	local y = groundAt(at, b)
	local landCF = CFrame.new(at.X, y + PILLAR_H / 2, at.Z) * CFrame.Angles(0, math.random() * math.pi, 0)
	local sky = Vector3.new(0, 80, 0)
	local pillar = part({ Name = "JudgementPillar", Size = Vector3.new(PILLAR_W, PILLAR_H, PILLAR_W), Material = Enum.Material.Marble,
		Color = PILLAR_STONE, CanCollide = true, CanQuery = true, CastShadow = true, CFrame = landCF + sky })
	table.insert(pillars, pillar)
	table.insert(parts, pillar)
	local info = TweenInfo.new(fall, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	TweenService:Create(pillar, info, { CFrame = landCF }):Play()
	for _, spec in ipairs({
		{ Vector3.new(PILLAR_W + 0.8, 1.1, PILLAR_W + 0.8), PILLAR_H / 2 + 0.55, PILLAR_GOLD, Enum.Material.Neon },
		{ Vector3.new(PILLAR_W + 0.2, 0.45, PILLAR_W + 0.2), PILLAR_H * 0.18, PILLAR_GOLD, Enum.Material.Neon },
		{ Vector3.new(PILLAR_W + 1.2, 1.4, PILLAR_W + 1.2), -PILLAR_H / 2 + 0.7, Color3.fromRGB(150, 142, 160), Enum.Material.Marble },
	}) do
		local cf = landCF * CFrame.new(0, spec[2], 0)
		local q = part({ Name = "PillarTrim", Size = spec[1], Color = spec[3], Material = spec[4], CFrame = cf + sky })
		table.insert(parts, q)
		TweenService:Create(q, info, { CFrame = cf }):Play()
	end
	task.delay(fall, function()
		if not pillar.Parent then return end
		shock(at, 7, PILLAR_STONE, y)
		blast(at, PILLAR_W * 0.75 + 0.5, dmg(b, 0.4)) -- (don't stand where it lands)
	end)
end

MOVES.judgement = function(b, _target)
	local mid = Vector3.new(b.home.X, b.floorY, b.home.Z)
	local pillars: { BasePart } = {}
	local parts: { BasePart } = {}
	local function cleanup()
		for _, p in ipairs(parts) do
			if p.Parent then
				TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = p.CFrame - Vector3.new(0, PILLAR_H, 0), Transparency = 1 }):Play()
				Debris:AddItem(p, 1)
			end
		end
		table.clear(parts)
	end

	-- 1. The pillars fall, far out round the middle: three more than there
	-- are players (four to six), each with room behind it to hide.
	local count = 0
	for _, v in ipairs(victims()) do
		if flatDist(v.root.Position, mid) < 100 then count += 1 end
	end
	if count == 0 then return end
	local n = math.clamp(count + 3, 4, 6)
	local spots: { Vector3 } = {}
	local a0 = math.random() * math.pi * 2
	for i = 1, n do
		local base = a0 + (i - 1) / n * math.pi * 2
		for try = 0, 12 do
			local a = base + (if try % 2 == 0 then 1 else -1) * math.ceil(try / 2) * math.rad(6)
			local at = pillarSpot(b, a, if try < 8 then PILLAR_DIST + math.random() * 6 else PILLAR_DIST - 8)
			local crowded = false
			for _, o in ipairs(spots) do
				if at and flatDist(o, at) < 16 then crowded = true end
			end
			if at and not crowded then
				table.insert(spots, at)
				break
			end
		end
	end
	if #spots == 0 then
		-- (a cramped room: a plain ring, nearer in)
		for i = 1, n do
			local a = a0 + (i - 1) / n * math.pi * 2
			table.insert(spots, mid + Vector3.new(math.cos(a), 0, math.sin(a)) * 24)
		end
	end
	local fall = 0.5
	local drops = {}
	for i, at in ipairs(spots) do
		local start = 0.7 + i * 0.12
		table.insert(drops, { pos = at, at = start })
		telegraphCircle(at, PILLAR_W * 0.75 + 0.5, start + fall, b.floorY)
		task.delay(start, function()
			if alive(b) then dropPillar(b, at, fall, pillars, parts) end
		end)
	end
	bossFX(b, { kind = "judgement", phase = "pillars", pos = mid, drops = drops, fall = fall, height = PILLAR_H })
	if not hold(b, 0.7 + #spots * 0.12 + fall + 0.4) then cleanup() return end

	-- 2. Malakor rises over the middle, wings spread wide.
	pose(b, "cast")
	takeOff(b)
	local rot = b.root.CFrame.Rotation
	if not glide(b, CFrame.new(mid.X, standY(b) + 10, mid.Z) * rot, 1.0, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut) then cleanup() return end

	-- 3. The void gathers: the whole room is about to be struck, all but the
	-- pillars' shelter.
	local cover: { BasePart } = table.clone(pillars)
	for _, p in ipairs(arenaPillars(b)) do table.insert(cover, p) end
	local covers = {}
	for _, p in ipairs(cover) do
		-- (the arena's pillars are cylinders lying on their side: Y is across)
		table.insert(covers, { pos = p.Position, radius = if p.Name == "ArenaPillar" then p.Size.Y / 2 else PILLAR_W / 2 })
	end
	local bounds = deps.roomAt and deps.roomAt(mid)
	local charge = if b.enraged then 3.0 else 3.6
	bossFX(b, { kind = "judgement", phase = "charge", duration = charge, pos = mid, covers = covers, bounds = bounds })
	if not hold(b, charge) then cleanup() return end

	-- 4. Down it comes, and the wave rolls out over the whole room: anyone it
	-- reaches with no pillar between them and the middle is struck.
	pose(b, "dive")
	if not glide(b, CFrame.new(mid.X, standY(b), mid.Z) * rot, 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In) then cleanup() return end
	pose(b, "slam")
	touchDown(b)
	bossFX(b, { kind = "judgement", phase = "strike", pos = mid, speed = WAVE_SPEED, covers = covers, bounds = bounds })
	shock(mid, 16, CELESTIAL_DARK, b.floorY)
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = cover
	local far = WAVE_REACH
	if bounds then
		far = 0
		for _, x in ipairs({ bounds.minX, bounds.maxX }) do
			for _, z in ipairs({ bounds.minZ, bounds.maxZ }) do far = math.max(far, flatDist(Vector3.new(x, 0, z), mid)) end
		end
	end
	local function inRoom(p: Vector3): boolean
		if bounds then
			return p.X >= bounds.minX - 2 and p.X <= bounds.maxX + 2 and p.Z >= bounds.minZ - 2 and p.Z <= bounds.maxZ + 2
		end
		return flatDist(p, mid) <= WAVE_REACH
	end
	local judged: { [Model]: boolean } = {}
	local t0 = os.clock()
	while alive(b) do
		local front = (os.clock() - t0) * WAVE_SPEED
		for _, v in ipairs(victims()) do
			local pos = v.root.Position
			if not judged[v.char] and math.abs(pos.Y - b.floorY) < 14 and inRoom(pos) and flatDist(pos, mid) <= front then
				judged[v.char] = true
				local from = Vector3.new(mid.X, pos.Y, mid.Z)
				if not Workspace:Raycast(from, pos - from, params) then
					deps.hurt(v.char, v.hum.MaxHealth * 0.5, mid)
				end
			end
		end
		if front > far then break end
		RunService.Heartbeat:Wait()
	end

	-- 5. The pillars crumble.
	if not hold(b, 0.8) then cleanup() return end
	cleanup()
	hold(b, 0.5)
end

-- ── The Fallen Angel's body ─────────────────────────────────────────────────
-- Built from parts (the place's boss template is a slime), to the design
-- sheet: a tall (~14 studs to the crown, ~19 to the halo's spike) blocky
-- angel in black plate, its face a black void under a hood with one white
-- four-point star for a face; a floating halo of iron thorns with a tall spike
-- through it; a torn pale scarf wound round the neck, its ends and a ragged
-- cape hanging down front and back with blood-red frayed tips; great torn
-- wings, pale up top, dark below, red-tipped, trailing embers; and a long
-- jagged black sword with a red core held point-down and forward.
--
-- Laid out in R6 units (a 5-stud character) and scaled up by ANGEL_SCALE.
-- Faces -Z. The HumanoidRootPart is the legs' box, its bottom just under the
-- feet, so the angel hovers a little (MobManager's HipHeight).
--
-- Rigged by itself ("SelfRigged": MobManager adds no welds), every piece
-- welded to an invisible pivot hung on a Motor6D: "Body" on the root (the
-- hips), and on the Body "Head", "ArmL"/"ArmR" (the sword in the right
-- hand), "LegL"/"LegR", "WingL"/"WingR", "Halo" and each strip of "Cloth".
-- FallenAngelFX moves them on every client: it hovers and breathes, its
-- legs trail, its arms swing the sword into each attack's pose
-- ("AngelPose"), its wings beat, its halo turns and its cloth blows.
-- It has no contact damage ("NoContact": its attacks are the danger) and
-- holds off at "KeepDistance" rather than walking onto you.
local ANGEL_SCALE = 2.4
local ANGEL = {
	plate = Color3.fromRGB(22, 20, 24),
	plateEdge = Color3.fromRGB(48, 46, 52),
	strap = Color3.fromRGB(32, 27, 25),
	void = Color3.fromRGB(4, 4, 5),
	hood = Color3.fromRGB(14, 13, 16),
	hair = Color3.fromRGB(26, 21, 21),
	cloth = Color3.fromRGB(208, 204, 200),
	clothShade = Color3.fromRGB(150, 146, 145),
	blood = Color3.fromRGB(150, 16, 22),
	featherPale = Color3.fromRGB(220, 216, 214),
	featherMid = Color3.fromRGB(116, 112, 116),
	featherDark = Color3.fromRGB(30, 27, 31),
	ember = Color3.fromRGB(235, 35, 40),
	iron = Color3.fromRGB(58, 56, 60),
	blade = Color3.fromRGB(26, 24, 28),
}

function BossAI.BuildFallenAngel(): Model
	local S = ANGEL_SCALE
	local rng = Random.new(7)
	local m = Instance.new("Model")
	m.Name = "FallenAngel"
	m:SetAttribute("AngelBuilt", true)
	m:SetAttribute("SelfRigged", true)
	m:SetAttribute("AngelScale", S)
	m:SetAttribute("NoContact", true)
	m:SetAttribute("KeepDistance", 13)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic -- (its joints arrive together, for FallenAngelFX)

	local function sc(cf: CFrame): CFrame
		return CFrame.new(cf.Position * S) * cf.Rotation
	end
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2.2, 1.2) * S
	root.CFrame = sc(CFrame.new(0, 1.1, 0))
	root.Transparency = 1
	root.Anchored = true
	root.CanTouch = false
	root.Parent = m
	m.PrimaryPart = root

	-- A part at `cf` (unit space), welded to `base`.
	local function mk(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, base: BasePart?, decor: boolean?, class: string?): BasePart
		local q = Instance.new(class or "Part") :: BasePart
		q.Name = name
		q.Size = size * S
		q.CFrame = sc(cf)
		q.Color = color
		q.Material = material or Enum.Material.SmoothPlastic
		q.Anchored = true
		q.CanCollide, q.CanTouch, q.CanQuery, q.Massless = false, false, false, true
		q.TopSurface, q.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
		q.CastShadow = not (decor ~= false)
		if decor ~= false then q:SetAttribute("Decor", true) end
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = base or root, q
		w.Parent = q
		q.Parent = m
		return q
	end
	-- An invisible pivot at `cf` hung on `on` (the root) by a Motor6D named `name`.
	local function pivot(name: string, cf: CFrame, on: BasePart?): BasePart
		local base = on or root
		local j = Instance.new("Part")
		j.Name = name .. "Pivot"
		j.Size = Vector3.one * 0.2
		j.CFrame = sc(cf)
		j.Transparency = 1
		j.Anchored = true
		j.CanCollide, j.CanTouch, j.CanQuery, j.Massless, j.CastShadow = false, false, false, true, false
		j:SetAttribute("Decor", true)
		j.Parent = m
		local mo = Instance.new("Motor6D")
		mo.Name = name
		mo.Part0, mo.Part1 = base, j
		mo.C0 = base.CFrame:ToObjectSpace(j.CFrame)
		mo.C1 = CFrame.identity
		mo.Parent = j
		return j
	end
	local METAL = Enum.Material.Metal
	local FABRIC = Enum.Material.Fabric
	local NEON = Enum.Material.Neon

	-- The joints: the hips carry everything; the head, arms and legs hang
	-- from them.
	local body = pivot("Body", CFrame.new(0, 2.35, 0))
	local head = pivot("Head", CFrame.new(0, 4.45, 0), body)
	local arms = {
		[-1] = pivot("ArmL", CFrame.new(-1.5, 4.3, 0), body),
		[1] = pivot("ArmR", CFrame.new(1.5, 4.3, 0), body),
	}
	local legs = {
		[-1] = pivot("LegL", CFrame.new(-0.5, 2.35, 0), body),
		[1] = pivot("LegR", CFrame.new(0.5, 2.35, 0), body),
	}

	-- ── Body: black plate ──
	for _, side in ipairs({ -1, 1 }) do
		local x = side * 0.5
		local leg = legs[side]
		mk(if side < 0 then "LegL" else "LegR", Vector3.new(1, 2, 1), CFrame.new(x, 1.3, 0) * CFrame.Angles(math.rad(-6), 0, 0), ANGEL.plate, nil, leg, false)
		mk("Greave", Vector3.new(1.06, 0.55, 1.06), CFrame.new(x, 0.6, -0.03), ANGEL.plateEdge, METAL, leg)
		for _, y in ipairs({ 1.15, 1.95 }) do
			mk("LegBand", Vector3.new(1.05, 0.14, 1.05), CFrame.new(x, y, -0.02), ANGEL.strap, FABRIC, leg)
		end
		mk("Knee", Vector3.new(0.7, 0.45, 0.14), CFrame.new(x, 1.55, -0.58), ANGEL.plateEdge, METAL, leg)
	end
	mk("Torso", Vector3.new(2, 2, 1), CFrame.new(0, 3.3, 0), ANGEL.plate, nil, body, false)
	mk("Breastplate", Vector3.new(1.75, 0.95, 0.14), CFrame.new(0, 3.78, -0.55), ANGEL.plateEdge, METAL, body)
	for i, y in ipairs({ 3.12, 2.86 }) do
		mk("Fauld", Vector3.new(1.6 - i * 0.1, 0.2, 0.1), CFrame.new(0, y, -0.54), ANGEL.plateEdge, METAL, body)
	end
	for _, rz in ipairs({ 36, -36 }) do
		mk("Strap", Vector3.new(0.17, 2.5, 0.05), CFrame.new(0, 3.35, -0.56) * CFrame.Angles(0, 0, math.rad(rz)), ANGEL.strap, FABRIC, body)
	end
	mk("Belt", Vector3.new(2.08, 0.32, 1.08), CFrame.new(0, 2.45, 0), ANGEL.strap, FABRIC, body)
	mk("Buckle", Vector3.new(0.42, 0.3, 0.08), CFrame.new(0, 2.45, -0.57), ANGEL.iron, METAL, body)
	for _, side in ipairs({ -1, 1 }) do
		-- the right arm reaches forward for the sword
		local reach = if side > 0 then 30 else 4
		local shoulder = CFrame.new(side * 1.5, 4.3, 0) * CFrame.Angles(math.rad(reach), 0, math.rad(side * 4))
		local arm = arms[side]
		mk(if side < 0 then "ArmL" else "ArmR", Vector3.new(1, 2, 1), shoulder * CFrame.new(0, -1, 0), ANGEL.plate, nil, arm, false)
		mk("Pauldron", Vector3.new(1.25, 0.55, 1.25), CFrame.new(side * 1.55, 4.38, 0) * CFrame.Angles(0, 0, math.rad(side * -14)), ANGEL.plateEdge, METAL, arm)
		mk("PauldronRidge", Vector3.new(1.3, 0.14, 0.2), CFrame.new(side * 1.55, 4.62, 0) * CFrame.Angles(0, 0, math.rad(side * -14)), ANGEL.iron, METAL, arm)
		mk("Bracer", Vector3.new(1.06, 0.6, 1.06), shoulder * CFrame.new(0, -1.55, 0), ANGEL.plateEdge, METAL, arm)
		mk("ArmBand", Vector3.new(1.05, 0.14, 1.05), shoulder * CFrame.new(0, -0.85, 0), ANGEL.strap, FABRIC, arm)
	end

	-- ── Head: a black void under a hood, one white star for a face ──
	mk("Head", Vector3.new(1.15, 1.15, 1.15), CFrame.new(0, 4.95, 0), ANGEL.hood, FABRIC, head, false)
	mk("HoodBack", Vector3.new(1.36, 1.3, 0.95), CFrame.new(0, 5.0, 0.24), ANGEL.hood, FABRIC, head)
	mk("HoodTop", Vector3.new(1.36, 0.26, 1.42), CFrame.new(0, 5.64, 0.02), ANGEL.hood, FABRIC, head)
	for _, side in ipairs({ -1, 1 }) do
		mk("HoodSide", Vector3.new(0.14, 1.28, 1.36), CFrame.new(side * 0.68, 4.98, 0.02), ANGEL.hood, FABRIC, head)
		mk("Hair", Vector3.new(0.2, 0.95, 0.14), CFrame.new(side * 0.44, 4.62, -0.6), ANGEL.hair, FABRIC, head)
	end
	mk("HoodPeak", Vector3.new(1.24, 0.2, 0.3), CFrame.new(0, 5.5, -0.64) * CFrame.Angles(math.rad(-18), 0, 0), ANGEL.hood, FABRIC, head)
	mk("FaceVoid", Vector3.new(0.98, 0.95, 0.04), CFrame.new(0, 4.92, -0.585), ANGEL.void, nil, head)
	local face = CFrame.new(0, 4.98, -0.612)
	mk("StarV", Vector3.new(0.07, 0.62, 0.03), face, Color3.new(1, 1, 1), NEON, head)
	mk("StarH", Vector3.new(0.4, 0.07, 0.03), face, Color3.new(1, 1, 1), NEON, head)
	local core = mk("StarCore", Vector3.new(0.15, 0.15, 0.035), face * CFrame.Angles(0, 0, math.rad(45)), Color3.new(1, 1, 1), NEON, head)
	local glint = Instance.new("ParticleEmitter")
	glint.Name = "StarGlint"
	glint.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	glint.Color = ColorSequence.new(Color3.new(1, 1, 1))
	glint.LightEmission = 1
	glint.LightInfluence = 0
	glint.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 0.4 * S), NumberSequenceKeypoint.new(1, 0) })
	glint.Lifetime = NumberRange.new(0.6, 0.9)
	glint.Speed = NumberRange.new(0)
	glint.Rate = 1.5
	glint.Parent = core

	-- ── The scarf: wound round the neck, ends hanging front and back ──
	mk("ScarfWrap", Vector3.new(1.58, 0.52, 1.36), CFrame.new(0, 4.4, 0) * CFrame.Angles(0, 0, math.rad(4)), ANGEL.cloth, FABRIC, body)
	mk("ScarfFold", Vector3.new(1.68, 0.3, 1.46), CFrame.new(0, 4.16, 0.02) * CFrame.Angles(math.rad(5), 0, math.rad(-6)), ANGEL.clothShade, FABRIC, body)
	for _, side in ipairs({ -1, 1 }) do
		mk("ScarfShoulder", Vector3.new(0.9, 0.24, 1.18), CFrame.new(side * 0.78, 4.3, 0) * CFrame.Angles(0, 0, math.rad(side * -16)), ANGEL.cloth, FABRIC, body)
	end
	-- Each strip swings from its top (FallenAngelFX): pale cloth going grey,
	-- then a frayed blood-red end.
	local STRIPS = {
		{ x = -0.36, z = -0.6, y = 4.2, len = 2.1, w = 0.5 },  -- the scarf's ends, in front
		{ x = 0.3, z = -0.6, y = 4.2, len = 1.4, w = 0.42 },
		{ x = -0.82, z = 0.58, y = 4.3, len = 2.7, w = 0.44 }, -- the ragged cape down the back
		{ x = -0.42, z = 0.6, y = 4.3, len = 3.2, w = 0.46 },
		{ x = 0, z = 0.62, y = 4.3, len = 2.5, w = 0.44 },
		{ x = 0.42, z = 0.6, y = 4.3, len = 3.1, w = 0.46 },
		{ x = 0.82, z = 0.58, y = 4.3, len = 2.3, w = 0.42 },
		{ x = -1.08, z = 0.25, y = 4.3, len = 2.0, w = 0.36 }, -- off the shoulders
		{ x = 1.08, z = 0.25, y = 4.3, len = 1.8, w = 0.34 },
		{ x = -0.5, z = -0.56, y = 2.35, len = 1.3, w = 0.5 },  -- torn cloth over the legs
		{ x = 0.5, z = -0.56, y = 2.35, len = 1.0, w = 0.44 },
		{ x = 0, z = 0.56, y = 2.35, len = 1.4, w = 0.6 },
	}
	for _, st in ipairs(STRIPS) do
		local top = CFrame.new(st.x, st.y, st.z)
		local hinge = pivot("Cloth", top, body)
		local run = st.len * 0.72
		mk("Cloth", Vector3.new(st.w, run, 0.06), top * CFrame.new(0, -run / 2, 0), ANGEL.cloth, FABRIC, hinge)
		mk("ClothShade", Vector3.new(st.w * 0.92, st.len * 0.16, 0.065), top * CFrame.new(0, -run - st.len * 0.06, 0), ANGEL.clothShade, FABRIC, hinge)
		-- the frayed end: two or three red tatters
		local tatters = if st.w > 0.4 then 3 else 2
		for k = 1, tatters do
			local tw = st.w / tatters * 0.8
			local tx = (k - (tatters + 1) / 2) * st.w / tatters
			local tl = st.len * rng:NextNumber(0.12, 0.24)
			mk("ClothTip", Vector3.new(tw, tl, 0.07), top * CFrame.new(tx, -st.len * 0.86 - tl / 2, 0) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-8, 8))),
				ANGEL.blood, NEON, hinge)
		end
	end

	-- ── The halo: a ring of iron thorns floating over the head, tilted, a
	-- tall spike standing through it ──
	local haloCF = CFrame.new(0, 6.15, 0.3) * CFrame.Angles(math.rad(-12), 0, 0)
	local halo = pivot("Halo", haloCF, body)
	local R = 0.9
	for i = 0, 17 do
		local a = (i / 18) * math.pi * 2
		mk("HaloRing", Vector3.new(0.34, 0.09, 0.1), haloCF * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -R), ANGEL.iron, METAL, halo)
	end
	for i = 0, 13 do
		local a = (i / 14) * math.pi * 2 + 0.2
		local l = if i % 2 == 0 then 0.5 else 0.32
		mk("HaloThorn", Vector3.new(0.05, l, 0.05), haloCF * CFrame.Angles(0, a, 0) * CFrame.new(0, 0, -R) * CFrame.Angles(math.rad(-58), 0, 0) * CFrame.new(0, l / 2, 0),
			ANGEL.iron, METAL, halo)
	end
	mk("HaloSpike", Vector3.new(0.11, 2.3, 0.11), haloCF * CFrame.new(0, 0.55, 0) * CFrame.Angles(0, math.rad(45), 0), ANGEL.iron, METAL, halo)
	mk("HaloSpikeTip", Vector3.new(0.05, 0.6, 0.05), haloCF * CFrame.new(0, 1.95, 0), Color3.fromRGB(150, 148, 154), METAL, halo)
	mk("HaloSpikeFoot", Vector3.new(0.05, 0.5, 0.05), haloCF * CFrame.new(0, -0.8, 0), ANGEL.iron, METAL, halo)
	mk("HaloCross", Vector3.new(1.0, 0.08, 0.08), haloCF * CFrame.new(0, 0.5, 0), ANGEL.iron, METAL, halo)
	for _, a in ipairs({ 0.6, 2.4, 4.3 }) do
		-- little chains hanging under the ring
		mk("HaloChain", Vector3.new(0.04, 0.42, 0.04), haloCF * CFrame.Angles(0, a, 0) * CFrame.new(0, -0.22, -R), ANGEL.iron, METAL, halo)
	end

	-- ── The wings: a pale bone arching up and out, long torn feathers
	-- hanging from it (pale at the root, dark below, red at the tips), short
	-- pale coverts layered over the top ──
	for _, side in ipairs({ -1, 1 }) do
		local baseCF = CFrame.new(side * 0.55, 4.0, 0.6) * CFrame.Angles(0, math.rad(side * -24), 0)
		local wing = pivot(if side < 0 then "WingL" else "WingR", baseCF, body)
		local bone = { Vector3.new(0.1, 0.1, 0), Vector3.new(2.0, 2.6, 0.2), Vector3.new(3.5, 1.1, 0.45) }
		local l1 = (bone[2] - bone[1]).Magnitude
		local l2 = (bone[3] - bone[2]).Magnitude
		local function along(t: number): Vector3
			local d = t * (l1 + l2)
			local p = if d <= l1 then bone[1]:Lerp(bone[2], d / l1) else bone[2]:Lerp(bone[3], (d - l1) / l2)
			return Vector3.new(p.X * side, p.Y, p.Z)
		end
		for k = 1, 2 do
			local a, b = bone[k], bone[k + 1]
			a, b = Vector3.new(a.X * side, a.Y, a.Z), Vector3.new(b.X * side, b.Y, b.Z)
			mk("WingBone", Vector3.new(0.26, 0.26, (b - a).Magnitude + 0.2), baseCF * CFrame.lookAt((a + b) / 2, b), ANGEL.featherPale, nil, wing)
		end
		local N = 13
		for i = 0, N - 1 do
			local t = i / (N - 1)
			local at = along(t)
			local L = 1.4 + 3.7 * t ^ 0.85
			local phi = math.rad(4 + 24 * t) * side
			local w = 0.48 + rng:NextNumber(0, 0.12)
			local z = (if i % 2 == 0 then 0.04 else -0.04) + t * 0.05
			-- the feather's frame: hanging from `at`, turned out by phi
			local f = baseCF * CFrame.new(at + Vector3.new(0, 0, z)) * CFrame.Angles(0, 0, phi)
			mk("Feather", Vector3.new(w, L * 0.42, 0.08), f * CFrame.new(0, -L * 0.21, 0), ANGEL.featherPale, nil, wing)
			mk("Feather", Vector3.new(w * 0.94, L * 0.45, 0.08), f * CFrame.new(0, -L * 0.63, 0.01), if i % 3 == 1 then ANGEL.featherMid else ANGEL.featherDark, nil, wing)
			mk("FeatherTip", Vector3.new(w * 0.55, L * 0.16, 0.085), f * CFrame.new(rng:NextNumber(-0.08, 0.08), -L * 0.92, 0.01) * CFrame.Angles(0, 0, math.rad(rng:NextNumber(-10, 10))),
				ANGEL.blood, NEON, wing)
		end
		for i = 0, 10 do
			local t = i / 10
			local at = along(t)
			local L = 0.9 + 0.5 * math.sin(t * math.pi)
			local f = baseCF * CFrame.new(at + Vector3.new(0, 0, -0.1)) * CFrame.Angles(0, 0, math.rad(10 + 20 * t) * side)
			mk("Covert", Vector3.new(0.58, L, 0.08), f * CFrame.new(0, -L / 2 + 0.1, 0), ANGEL.featherPale, nil, wing)
		end
		-- embers drifting off the lower wing
		local drift = mk("WingEmbers", Vector3.new(3.2, 1.2, 0.4), baseCF * CFrame.new(side * 2.6, -1.6, 0.3), ANGEL.ember, nil, wing)
		drift.Transparency = 1
		local e = Instance.new("ParticleEmitter")
		e.Name = "Embers"
		e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
		e.Color = ColorSequence.new(Color3.fromRGB(255, 120, 100), ANGEL.ember)
		e.LightEmission = 1
		e.LightInfluence = 0
		e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22 * S), NumberSequenceKeypoint.new(1, 0) })
		e.Lifetime = NumberRange.new(1.2, 2)
		e.Speed = NumberRange.new(1, 3)
		e.Acceleration = Vector3.new(0, 4, 0)
		e.SpreadAngle = Vector2.new(30, 30)
		e.Shape = Enum.ParticleEmitterShape.Box
		e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
		e.Rate = 7
		e.Parent = drift
	end

	-- ── The sword: long, black, jagged, a red core, held point-down and
	-- forward in the right hand ──
	local hand = (CFrame.new(1.5, 4.3, 0) * CFrame.Angles(math.rad(30), 0, math.rad(4)) * CFrame.new(0, -2.05, 0)).Position
	local dir = Vector3.new(-0.25, -0.55, -0.8).Unit
	local sw = CFrame.lookAt(hand, hand + dir) -- the blade runs along -Z
	mk("SwordGrip", Vector3.new(0.18, 0.18, 0.75), sw * CFrame.new(0, 0, 0.12), ANGEL.strap, FABRIC, arms[1])
	mk("SwordPommel", Vector3.new(0.1, 0.1, 0.4), sw * CFrame.new(0, 0, 0.66) * CFrame.Angles(0, 0, math.rad(45)), ANGEL.iron, METAL, arms[1])
	mk("SwordGuard", Vector3.new(1.0, 0.14, 0.16), sw * CFrame.new(0, 0, -0.28), ANGEL.iron, METAL, arms[1])
	for _, side in ipairs({ -1, 1 }) do
		mk("SwordGuardSpike", Vector3.new(0.08, 0.08, 0.42), sw * CFrame.new(side * 0.5, 0, -0.42) * CFrame.Angles(0, math.rad(side * -35), 0), ANGEL.iron, METAL, arms[1])
	end
	local BL = 3.7
	mk("SwordBlade", Vector3.new(0.34, 0.09, BL), sw * CFrame.new(0, 0, -0.36 - BL / 2), ANGEL.blade, METAL, arms[1])
	mk("SwordCore", Vector3.new(0.06, 0.1, BL - 0.5), sw * CFrame.new(0, 0, -0.5 - (BL - 0.5) / 2), ANGEL.ember, NEON, arms[1])
	-- jagged teeth down both edges, angled toward the point
	local z = -0.7
	local k = 0
	while z > -0.36 - BL + 0.4 do
		k += 1
		for _, side in ipairs({ -1, 1 }) do
			local len = if k % 2 == 0 then 0.26 else 0.18
			mk("SwordTooth", Vector3.new(0.07, 0.085, len), sw * CFrame.new(side * 0.2, 0, z) * CFrame.Angles(0, math.rad(side * 42), 0) * CFrame.new(0, 0, -len / 2),
				ANGEL.blade, METAL, arms[1])
		end
		z -= 0.42
	end
	mk("SwordTip", Vector3.new(0.24, 0.09, 0.24), sw * CFrame.new(0, 0, -0.36 - BL) * CFrame.Angles(0, math.rad(45), 0), ANGEL.blade, METAL, arms[1])
	mk("SwordPoint", Vector3.new(0.09, 0.09, 0.45), sw * CFrame.new(0, 0, -0.36 - BL - 0.3), ANGEL.blade, METAL, arms[1])

	-- Embers rising round its feet.
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "AngelEmbers"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(Color3.fromRGB(255, 110, 90), ANGEL.ember)
	aura.LightEmission = 1
	aura.LightInfluence = 0
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28 * S), NumberSequenceKeypoint.new(1, 0) })
	aura.Lifetime = NumberRange.new(1.5, 2.5)
	aura.Speed = NumberRange.new(2, 5)
	aura.Acceleration = Vector3.new(0, 3, 0)
	aura.SpreadAngle = Vector2.new(25, 25)
	aura.EmissionDirection = Enum.NormalId.Top
	aura.Shape = Enum.ParticleEmitterShape.Box
	aura.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	aura.Rate = 10
	aura.Parent = root
	return m
end

-- ── Attach ──────────────────────────────────────────────────────────────────
local function addAura(b: Boss)
	if b.model:GetAttribute("AngelBuilt") == true then return end -- (it glows with its own embers)
	local fire = Instance.new("Fire")
	fire.Name = "BossFlames"
	fire.Color = b.kind.color
	fire.SecondaryColor = Color3.new(0.1, 0.05, 0.05)
	fire.Size = 10
	fire.Heat = 14
	fire.Parent = b.root
	local light = Instance.new("PointLight")
	light.Name = "BossLight"
	light.Color = b.kind.color
	light.Brightness = 2.5
	light.Range = 18
	light.Parent = b.root
end

local function dressFallenAngel(model: Model, root: BasePart)
	local torso = model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso") or root
	local halo = Instance.new("Part")
	halo.Name = "DarkHalo"
	halo.Shape = Enum.PartType.Cylinder
	halo.Size = Vector3.new(0.3, 3.2, 3.2)
	halo.CFrame = root.CFrame * CFrame.new(0, 4.2, 0) * CFrame.Angles(0, 0, math.rad(90))
	halo.Color = Color3.fromRGB(175, 75, 255)
	halo.Material = Enum.Material.Neon
	halo.CanCollide = false
	halo.Anchored = false
	halo.Parent = model
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = torso :: BasePart
	weld.Part1 = halo
	weld.Parent = halo

	-- Dark Wings
	for _, side in ipairs({ -1, 1 }) do
		local wing = Instance.new("Part")
		wing.Name = if side == 1 then "RightWing" else "LeftWing"
		wing.Size = Vector3.new(0.4, 4, 7)
		wing.CFrame = root.CFrame * CFrame.new(side * 2.8, 2, -1.8) * CFrame.Angles(math.rad(25), math.rad(side * 35), math.rad(side * -20))
		wing.Color = Color3.fromRGB(35, 20, 50)
		wing.Material = Enum.Material.SmoothPlastic
		wing.CanCollide = false
		wing.Anchored = false
		wing.Parent = model
		local wingWeld = Instance.new("WeldConstraint")
		wingWeld.Part0 = torso :: BasePart
		wingWeld.Part1 = wing
		wingWeld.Parent = wing
	end
end

local function enrage(b: Boss)
	b.enraged = true
	b.model:SetAttribute("Enraged", true)
	b.hum.WalkSpeed *= 1.25
	local fire = b.root:FindFirstChild("BossFlames") :: Fire?
	if fire then fire.Size = 16 fire.Color = Color3.fromRGB(255, 40, 30) end
	local outline = Instance.new("Highlight")
	outline.FillColor = Color3.fromRGB(255, 30, 20)
	outline.FillTransparency = 0.75
	outline.OutlineColor = Color3.fromRGB(255, 60, 40)
	outline.Parent = b.model
	shock(b.root.Position, 18, Color3.fromRGB(255, 40, 30), b.floorY)
end

function BossAI.Attach(model: Model, kindId: string)
	local kind = BossAI.Kinds[kindId]
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart?
	if not kind or not hum or not root then return end
	local runId = model:GetAttribute("RunId")
	local b: Boss = {
		model = model, hum = hum, root = root, kind = kind,
		floorY = model:GetAttribute("FloorY") or (root.Position.Y - 3),
		damage = kind.damage * DifficultyManager.GetMobScale(runId).damage,
		enraged = false, minions = {},
		home = root.Position, runId = runId,
	}
	addAura(b)
	if kindId == "fallen_angel" and model:GetAttribute("AngelBuilt") ~= true then
		dressFallenAngel(model, root)
	end

	-- The intro: every client in the run plays the boss's cinematic
	-- (BossCinematic) while it holds still and can't be hurt. The Fallen
	-- Angel comes down out of the sky for it.
	model:SetAttribute("BossBusy", true)
	setInvulnerable(b, true)
	local descend = kindId == "fallen_angel"
	local landCF = root.CFrame
	if descend then
		landCF = CFrame.new(landCF.X, standY(b), landCF.Z) * landCF.Rotation
		root.CFrame = landCF + Vector3.new(0, 34, 0)
		takeOff(b)
		pose(b, "cast")
	end
	task.spawn(function()
		task.wait(0.2)
		local intro = Network.GetRemoteEvent(Network.Remotes.BossIntro)
		for _, p in ipairs(runPlayers(b)) do
			intro:FireClient(p, {
				name = kind.name,
				color = kind.color,
				kind = kindId,
				pos = landCF.Position,
				model = model,
				duration = INTRO_TIME,
			})
		end
		if descend then
			glide(b, landCF, INTRO_TIME * 0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out)
			touchDown(b)
			pose(b, nil)
		else
			task.wait(INTRO_TIME * 0.45)
		end
		if alive(b) then shock(landCF.Position, 22, kind.color, b.floorY) end
	end)

	-- Never lost under the map: if the boss drops through the floor (a bad
	-- landing, a shove), it's put back where it last stood on it.
	task.spawn(function()
		local lastGood = root.Position
		while alive(b) do
			local y = root.Position.Y
			if y >= b.floorY - 1 and y <= b.floorY + 40 then
				lastGood = root.Position
			elseif y < b.floorY - 4 then
				local lift = root.Size.Y / 2 + hum.HipHeight + 0.5
				root.AssemblyLinearVelocity = Vector3.zero
				root.CFrame = CFrame.new(lastGood.X, b.floorY + lift, lastGood.Z) * root.CFrame.Rotation
			end
			task.wait(0.25)
		end
	end)
	-- The Fallen Angel keeps turned toward its prey (no stepping round to
	-- face it: it turns where it hovers).
	if model:GetAttribute("AngelBuilt") == true then
		hum.AutoRotate = false
		task.spawn(function()
			while alive(b) do
				task.wait(0.15)
				if not b.flying and model:GetAttribute("BossBusy") ~= true then
					local v = nearestVictim(b)
					if v then turnTo(b, v.root.Position) end
				end
			end
		end)
	end
	hum.HealthChanged:Connect(function(h)
		-- Invulnerable: whatever took health off (a burn, a bleed) is undone.
		if b.lockedHealth and model:GetAttribute("BossInvulnerable") == true and h > 0 and h < b.lockedHealth then
			hum.Health = b.lockedHealth
			return
		end
		if not b.enraged and h > 0 and h <= hum.MaxHealth * 0.5 then enrage(b) end
	end)

	task.spawn(function()
		local last = ""
		local sinceSignature = 0
		local ready = hold(b, INTRO_TIME)
		if model.Parent then model:SetAttribute("BossBusy", false) end
		setInvulnerable(b, false)
		if not ready then return end
		if not hold(b, 0.4) then return end
		while alive(b) do
			local target = nearestVictim(b)
			if target and deps.canAct(model) then
				local options = {}
				for _, m in ipairs(kind.moves) do
					if m ~= last and MOVES[m] then table.insert(options, m) end
				end
				local move = options[math.random(1, #options)]
				-- (its signature comes round at least every few moves)
				if kind.signature and MOVES[kind.signature] and sinceSignature >= SIGNATURE_EVERY - 1 and last ~= kind.signature then
					move = kind.signature
				end
				-- (a Studio test calls a move by name: DevHooks)
				local devMove = if RunService:IsStudio() then model:GetAttribute("DevMove") else nil
				if typeof(devMove) == "string" and MOVES[devMove] then
					move = devMove
					model:SetAttribute("DevMove", nil)
				end
				last = move
				local signature = move == kind.signature
				sinceSignature = if signature then 0 else sinceSignature + 1
				model:SetAttribute("BossBusy", true)
				hum:Move(Vector3.zero)
				if signature then
					local label = SIGNATURE_NAMES[move] or string.upper(move)
					setInvulnerable(b, true, label)
					bossFX(b, { kind = "signature", name = label, boss = kind.name })
				end
				local ok, err = pcall(MOVES[move], b, target)
				if not ok then warn(`[BossAI] {kind.name} {move} failed:`, err) end
				-- (a move cut short never leaves the Fallen Angel hanging in the
				-- air or frozen in a pose)
				touchDown(b)
				pose(b, nil)
				if signature and model.Parent then setInvulnerable(b, false) end
				if model.Parent then model:SetAttribute("BossBusy", false) end
				local gap = if b.enraged then (if kind.gap then kind.gap * 0.6 else GAP_ENRAGED) else kind.gap or GAP
				if not hold(b, gap) then break end
			else
				task.wait(0.3)
			end
		end
		for _, m in ipairs(b.minions) do
			local h = m:FindFirstChildOfClass("Humanoid")
			if m.Parent and h then h.Health = 0 end
		end
	end)
end

function BossAI.Init(d: Deps)
	deps = d
end

return BossAI
