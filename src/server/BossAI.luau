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
	                              JUDGEMENT (pillars fall from the sky: hide behind one)

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

local BossAI = {}

export type Kind = {
	name: string,
	health: number, -- × the base boss health
	damage: number, -- × the base boss damage
	xp: number,
	color: Color3,
	moves: { string },
	signature: string?, -- the move that makes it invulnerable while it runs
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
		color = Color3.fromRGB(175, 75, 255), moves = { "dark_descent", "feather_storm", "void_cross", "shadow_dash", "judgement" },
		signature = "judgement",
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
	local _, size = b.model:GetBoundingBox()
	local d = math.clamp(math.max(size.X, size.Y, size.Z) + 2.5, 7, 22)
	local barrier = Instance.new("Part")
	barrier.Name = "InvulnBarrier"
	barrier.Shape = Enum.PartType.Ball
	barrier.Size = Vector3.one * 1
	barrier.CFrame = b.root.CFrame
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
	tag.StudsOffset = Vector3.new(0, size.Y * 0.5 + 6, 0)
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
		if d < bestD then best, bestD = v, d end
	end
	return best
end

local function face(b: Boss, pos: Vector3)
	local flat = Vector3.new(pos.X, b.root.Position.Y, pos.Z)
	if (flat - b.root.Position).Magnitude > 0.1 then
		b.root.CFrame = CFrame.lookAt(b.root.Position, flat)
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

-- A quick hop onto `spot` (the slime bounce).
local function hop(b: Boss, spot: Vector3, height: number, t: number)
	local from = b.root.Position
	local land = Vector3.new(spot.X, from.Y, spot.Z)
	local steps = math.max(4, math.floor(t / 0.04))
	for i = 1, steps do
		local a = i / steps
		b.root.CFrame = CFrame.new(from:Lerp(land, a) + Vector3.new(0, math.sin(a * math.pi) * height, 0)) * b.root.CFrame.Rotation
		task.wait(t / steps)
	end
	b.root.AssemblyLinearVelocity = Vector3.zero
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

local CELESTIAL_DARK = Color3.fromRGB(170, 70, 255)
local VOID_CRIMSON = Color3.fromRGB(255, 45, 90)

MOVES.dark_descent = function(b, target)
	-- Malakor rises high into the air, casting a massive void circle beneath players,
	-- then crashes down with dark thunder and radial shockwaves!
	local spot = target.root.Position
	local wind = if b.enraged then 0.45 else 0.7
	telegraphCircle(spot, 12, wind, b.floorY)
	face(b, spot)
	local startPos = b.root.Position
	hop(b, startPos + Vector3.new(0, 18, 0), 18, 0.35)
	if not hold(b, wind) then return end
	hop(b, Vector3.new(spot.X, b.floorY, spot.Z), 2, 0.22)
	shock(spot, 14, CELESTIAL_DARK, b.floorY)
	shock(spot, 8, VOID_CRIMSON, b.floorY)
	blast(spot, 12, dmg(b, 1.2))
	hold(b, 0.3)
end

MOVES.feather_storm = function(b, _target)
	-- Summons a volley of obsidian feather blades that target nearby players
	local count = if b.enraged then 10 else 7
	for i = 1, count do
		local vs = victims()
		if #vs == 0 then break end
		local v = vs[math.random(1, #vs)]
		local a = (i / count) * math.pi * 2
		local spawnPos = b.root.Position + Vector3.new(math.cos(a) * 6, 8, math.sin(a) * 6)
		local targetPos = v.root.Position + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
		telegraphCircle(targetPos, 5, 0.4, b.floorY)
		local blade = part({ Size = Vector3.new(0.6, 3, 0.6), CFrame = CFrame.lookAt(spawnPos, targetPos) * CFrame.Angles(math.rad(90), 0, 0),
			Color = CELESTIAL_DARK, Material = Enum.Material.Neon })
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.38 do
				local k = (os.clock() - t0) / 0.38
				blade.CFrame = CFrame.lookAt(spawnPos:Lerp(targetPos, k), targetPos)
				RunService.Heartbeat:Wait()
			end
			blade:Destroy()
			blast(targetPos, 5, dmg(b, 0.55))
			shock(targetPos, 5, CELESTIAL_DARK, b.floorY)
		end)
		if not hold(b, if b.enraged then 0.08 else 0.12) then return end
	end
	hold(b, 0.35)
end

MOVES.void_cross = function(b, _target)
	-- Smites the arena in a massive cardinal cross of dark holy fire
	local center = b.root.Position
	local len = 42
	local wid = 7
	local wind = if b.enraged then 0.5 else 0.7
	telegraphBeam(center, Vector3.new(1, 0, 0), len, wid, wind, b.floorY)
	telegraphBeam(center, Vector3.new(-1, 0, 0), len, wid, wind, b.floorY)
	telegraphBeam(center, Vector3.new(0, 0, 1), len, wid, wind, b.floorY)
	telegraphBeam(center, Vector3.new(0, 0, -1), len, wid, wind, b.floorY)
	if not hold(b, wind) then return end
	shock(center, 9, VOID_CRIMSON, b.floorY)
	for _, dir in ipairs({ Vector3.new(1, 0, 0), Vector3.new(-1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(0, 0, -1) }) do
		for step = 1, 6 do
			local p = center + dir * (step * 6.5)
			blast(p, 4.5, dmg(b, 0.85))
			shock(p, 4.5, CELESTIAL_DARK, b.floorY)
		end
	end
	hold(b, 0.4)
end

MOVES.shadow_dash = function(b, target)
	-- High speed spectral wing dash across the arena
	local dir = (target.root.Position - b.root.Position)
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then dir = b.root.CFrame.LookVector end
	dir = dir.Unit
	local wind = if b.enraged then 0.3 else 0.45
	telegraphBeam(b.root.Position, dir, 32, 7, wind, b.floorY)
	face(b, b.root.Position + dir * 10)
	if not hold(b, wind) then return end
	local start = b.root.Position
	local dest = start + dir * 32
	hop(b, dest, 2, 0.22)
	shock(dest, 8, VOID_CRIMSON, b.floorY)
	blast(dest, 7, dmg(b, 0.9))
	hold(b, 0.3)
end

-- ── JUDGEMENT (the Fallen Angel's signature) ────────────────────────────────
-- Stone pillars crash down from the sky around the arena. Malakor rises
-- above it all and gathers a sphere of void light, then rains it down on
-- every player it can see: a player with a pillar between them and the angel
-- is safe, anyone else is all but killed. Then the pillars crumble.
local PILLAR_STONE = Color3.fromRGB(205, 198, 215)

local function dropPillar(b: Boss, at: Vector3, pillars: { BasePart })
	local y = groundAt(at, b)
	local h = 18
	local pillar = part({ Name = "JudgementPillar", Size = Vector3.new(5, h, 5), Material = Enum.Material.Marble,
		Color = PILLAR_STONE, CanCollide = true, CanQuery = true, CastShadow = true,
		CFrame = CFrame.new(at.X, y + h / 2 + 70, at.Z) * CFrame.Angles(0, math.random() * math.pi, 0) })
	local cap = part({ Name = "PillarCap", Size = Vector3.new(5.8, 1, 5.8), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 215, 130), Transparency = 0.1, CFrame = pillar.CFrame * CFrame.new(0, h / 2 + 0.5, 0) })
	local capWeld = Instance.new("WeldConstraint")
	capWeld.Part0, capWeld.Part1 = pillar, cap
	capWeld.Parent = cap
	cap.Anchored = false
	cap.Massless = true
	table.insert(pillars, pillar)
	local landCF = CFrame.new(at.X, y + h / 2, at.Z) * pillar.CFrame.Rotation
	TweenService:Create(pillar, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = landCF }):Play()
	task.delay(0.5, function()
		if not pillar.Parent then return end
		cap.CFrame = pillar.CFrame * CFrame.new(0, h / 2 + 0.5, 0)
		shock(at, 7, PILLAR_STONE, y)
		blast(at, 3.6, dmg(b, 0.6)) -- (don't stand where it lands)
	end)
end

MOVES.judgement = function(b, _target)
	local home = b.home
	local pillars: { BasePart } = {}
	local orb: BasePart? = nil
	local anchoredHere = false
	local startCF = b.root.CFrame
	local function cleanup()
		if orb then orb:Destroy() end
		for _, p in ipairs(pillars) do
			if p.Parent then
				for _, c in ipairs(p:GetConnectedParts()) do
					if c ~= p then
						TweenService:Create(c, TweenInfo.new(0.8), { Transparency = 1 }):Play()
					end
				end
				TweenService:Create(p, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ CFrame = p.CFrame - Vector3.new(0, p.Size.Y, 0), Transparency = 1 }):Play()
				Debris:AddItem(p, 1)
			end
		end
		for _, c in ipairs(fx():GetChildren()) do
			if c.Name == "PillarCap" then Debris:AddItem(c, 1) end
		end
		if anchoredHere and b.root.Parent then
			b.root.Anchored = false
			pcall(function() b.root:SetNetworkOwner(nil) end)
		end
	end

	-- 1. The pillars fall: a ring round the arena's middle, one more than
	-- there are players (and never fewer than four).
	local count = 0
	for _, v in ipairs(victims()) do
		if flatDist(v.root.Position, home) < 90 then count += 1 end
	end
	if count == 0 then return end
	local n = math.clamp(count + 2, 4, 7)
	bossFX(b, { kind = "judgement", phase = "pillars", pos = home })
	local a0 = math.random() * math.pi * 2
	for i = 1, n do
		local a = a0 + (i / n) * math.pi * 2
		local ring = 13 + math.random() * 4
		local at = home + Vector3.new(math.cos(a), 0, math.sin(a)) * ring
		-- (no floor there, a wall in the way: pull it in closer)
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { b.model, fx() }
		local wall = Workspace:Raycast(home + Vector3.new(0, 3, 0), (at - home), params)
		if wall then at = home + (at - home).Unit * math.max(6, (wall.Position - home).Magnitude - 4) end
		telegraphCircle(at, 3.6, 1.1, b.floorY)
		task.delay(0.6 + i * 0.08, function()
			if alive(b) then dropPillar(b, at, pillars) end
		end)
	end
	if not hold(b, 1.9) then cleanup() return end

	-- 2. Malakor rises over the arena.
	face(b, home)
	b.root.Anchored = true
	anchoredHere = true
	local upCF = CFrame.new(home.X, b.floorY + 24, home.Z) * startCF.Rotation
	TweenService:Create(b.root, TweenInfo.new(0.9, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = upCF }):Play()
	if not hold(b, 0.9) then cleanup() return end

	-- 3. The void gathers (the warning: hide!).
	local charge = if b.enraged then 2.8 else 3.4
	bossFX(b, { kind = "judgement", phase = "charge", duration = charge, pos = home })
	local o = part({ Name = "JudgementOrb", Shape = Enum.PartType.Ball, Size = Vector3.one * 1,
		CFrame = upCF * CFrame.new(0, 5, 0), Color = Color3.fromRGB(235, 200, 255), Transparency = 0.05 })
	orb = o
	TweenService:Create(o, TweenInfo.new(charge, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ Size = Vector3.one * 9, Color = Color3.fromRGB(150, 60, 255) }):Play()
	if not hold(b, charge) then cleanup() return end

	-- 4. JUDGEMENT: a ray to every player; the pillars are the only cover.
	bossFX(b, { kind = "judgement", phase = "strike", pos = home })
	local from = o.Position
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = pillars
	for _, v in ipairs(victims()) do
		if (v.root.Position - from).Magnitude < 140 then
			local to = v.root.Position
			local hit = Workspace:Raycast(from, to - from, params)
			local stop = if hit then hit.Position else to
			local len = (stop - from).Magnitude
			local beam = part({ Name = "JudgementRay", Size = Vector3.new(1.6, 1.6, len),
				CFrame = CFrame.lookAt((from + stop) / 2, stop), Color = Color3.fromRGB(220, 170, 255), Transparency = 0.05 })
			TweenService:Create(beam, TweenInfo.new(0.5), { Size = Vector3.new(0.1, 0.1, len), Transparency = 1 }):Play()
			Debris:AddItem(beam, 0.55)
			if hit then
				shock(hit.Position, 4, Color3.fromRGB(255, 220, 140), b.floorY)
			else
				shock(to, 6, VOID_CRIMSON, b.floorY)
				deps.hurt(v.char, math.max(dmg(b, 4), v.hum.MaxHealth * 0.85), from)
			end
		end
	end
	o:Destroy()
	orb = nil
	if not hold(b, 0.6) then cleanup() return end

	-- 5. Back down; the pillars crumble.
	local downCF = CFrame.new(home.X, startCF.Position.Y, home.Z) * startCF.Rotation
	TweenService:Create(b.root, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { CFrame = downCF }):Play()
	hold(b, 0.5)
	shock(home, 12, CELESTIAL_DARK, b.floorY)
	cleanup()
	hold(b, 0.4)
end

-- ── The Fallen Angel's body ─────────────────────────────────────────────────
-- Built from parts (the place's boss template is a slime): a hovering
-- armoured angel in a torn robe, black feathered wings, a broken violet halo
-- and a greatsword. The HumanoidRootPart sits low in the robe so the angel
-- hovers just over the floor (MobManager's HipHeight). Faces -Z.
function BossAI.BuildFallenAngel(): Model
	local m = Instance.new("Model")
	m.Name = "FallenAngel"
	m:SetAttribute("AngelBuilt", true)
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 2)
	root.Transparency = 1
	root.Anchored = true
	-- (low in the robe: the hem then hovers just over the floor)
	root.CFrame = CFrame.new(0, -1.2, 0)
	root.Parent = m
	m.PrimaryPart = root
	local function p(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, props: { [string]: any }?): BasePart
		local q = Instance.new("Part")
		q.Name = name
		q.Size = size
		q.CFrame = cf
		q.Color = color
		q.Material = material or Enum.Material.SmoothPlastic
		q.Anchored = true
		q.CanCollide = false
		q.CanTouch = false
		q.TopSurface = Enum.SurfaceType.Smooth
		q.BottomSurface = Enum.SurfaceType.Smooth
		for k, v in pairs(props or {}) do (q :: any)[k] = v end
		q.Parent = m
		return q
	end
	local ROBE = Color3.fromRGB(32, 22, 44)
	local ARMOR = Color3.fromRGB(70, 62, 86)
	local GOLDC = Color3.fromRGB(215, 175, 95)
	local VOID = Color3.fromRGB(175, 75, 255)
	local SKIN = Color3.fromRGB(205, 198, 218)
	-- Robe (hovering, tattered hem) and belt.
	p("Robe", Vector3.new(3.4, 3.6, 2.6), CFrame.new(0, 0.3, 0), ROBE, Enum.Material.Fabric)
	for i = -2, 2 do
		p("RobeHem", Vector3.new(0.6, 1.2 + (i % 2) * 0.5, 2.4), CFrame.new(i * 0.68, -1.6 - (i % 2) * 0.2, 0) * CFrame.Angles(0, 0, math.rad(i * 4)), ROBE, Enum.Material.Fabric)
	end
	p("Belt", Vector3.new(3.0, 0.4, 2.0), CFrame.new(0, 2.1, 0), VOID, Enum.Material.Neon)
	-- Armoured chest and pauldrons.
	p("Torso", Vector3.new(2.8, 2.4, 1.6), CFrame.new(0, 3.4, 0), ARMOR, Enum.Material.Metal)
	p("ChestTrim", Vector3.new(0.4, 2.2, 1.7), CFrame.new(0, 3.4, 0), GOLDC, Enum.Material.Metal)
	p("Rune", Vector3.new(0.7, 0.7, 0.2), CFrame.new(0, 3.7, -0.82), VOID, Enum.Material.Neon)
	for _, side in ipairs({ -1, 1 }) do
		p("Pauldron", Vector3.new(1.6, 1.0, 1.8), CFrame.new(side * 1.75, 4.5, 0) * CFrame.Angles(0, 0, math.rad(side * -18)), ARMOR, Enum.Material.Metal)
		p("PauldronSpike", Vector3.new(0.3, 1.1, 0.3), CFrame.new(side * 2.2, 5.2, 0) * CFrame.Angles(0, 0, math.rad(side * -30)), GOLDC, Enum.Material.Metal)
		p("Arm", Vector3.new(0.8, 2.6, 0.8), CFrame.new(side * 1.85, 3.0, 0), ROBE, Enum.Material.Fabric)
		p("Gauntlet", Vector3.new(0.95, 0.9, 0.95), CFrame.new(side * 1.85, 1.6, 0), ARMOR, Enum.Material.Metal)
	end
	-- Head: pale, hooded, burning eyes.
	p("Head", Vector3.new(1.3, 1.4, 1.3), CFrame.new(0, 5.35, 0), SKIN)
	p("Hood", Vector3.new(1.6, 1.3, 1.6), CFrame.new(0, 5.6, 0.12), ROBE, Enum.Material.Fabric)
	for _, side in ipairs({ -1, 1 }) do
		p("Eye", Vector3.new(0.26, 0.14, 0.1), CFrame.new(side * 0.3, 5.4, -0.66), VOID, Enum.Material.Neon)
	end
	-- The broken halo: a tilted violet ring with a gap.
	for i = 0, 13 do
		if i ~= 3 and i ~= 4 then
			local a = (i / 14) * math.pi * 2
			p("DarkHalo", Vector3.new(0.6, 0.18, 0.28), CFrame.new(0, 6.7, 0.5) * CFrame.Angles(math.rad(-15), 0, 0)
				* CFrame.new(math.cos(a) * 1.35, 0, math.sin(a) * 1.35) * CFrame.Angles(0, -a + math.pi / 2, 0), VOID, Enum.Material.Neon)
		end
	end
	-- Wings: fans of black feathers with violet edges, swept up and back.
	for _, side in ipairs({ -1, 1 }) do
		local base = CFrame.new(side * 0.9, 4.4, 0.9)
		for k = 1, 6 do
			local len = 3.2 + k * 0.75
			local cf = base * CFrame.Angles(math.rad(-12), math.rad(side * 18), math.rad(side * (78 - k * 15)))
				* CFrame.new(side * len / 2, 0, 0)
			p("Feather", Vector3.new(len, 0.9, 0.25), cf, Color3.fromRGB(22, 14, 30), Enum.Material.SmoothPlastic)
			p("FeatherEdge", Vector3.new(len * 0.35, 0.92, 0.27), cf * CFrame.new(side * len * 0.33, 0, 0), VOID, Enum.Material.Neon,
				{ Transparency = 0.15 })
		end
	end
	-- The greatsword, point down at its side.
	p("Hilt", Vector3.new(0.35, 1.4, 0.35), CFrame.new(2.4, 1.9, -0.4), GOLDC, Enum.Material.Metal)
	p("Guard", Vector3.new(1.8, 0.3, 0.4), CFrame.new(2.4, 1.15, -0.4), GOLDC, Enum.Material.Metal)
	p("Blade", Vector3.new(0.3, 5.2, 0.9), CFrame.new(2.4, -1.6, -0.4), Color3.fromRGB(40, 30, 55), Enum.Material.Metal)
	p("BladeEdge", Vector3.new(0.32, 4.8, 0.2), CFrame.new(2.4, -1.6, -0.88), VOID, Enum.Material.Neon)
	return m
end

-- ── Attach ──────────────────────────────────────────────────────────────────
local function addAura(b: Boss)
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
		root.Anchored = true
		root.CFrame = landCF + Vector3.new(0, 34, 0)
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
			TweenService:Create(root, TweenInfo.new(INTRO_TIME * 0.6, Enum.EasingStyle.Quint, Enum.EasingDirection.Out), { CFrame = landCF }):Play()
			task.wait(INTRO_TIME * 0.6)
			if root.Parent then
				root.Anchored = false
				pcall(function() root:SetNetworkOwner(nil) end)
			end
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
				if signature and model.Parent then setInvulnerable(b, false) end
				if model.Parent then model:SetAttribute("BossBusy", false) end
				if not hold(b, if b.enraged then GAP_ENRAGED else GAP) then break end
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
