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
	  The Slime King     (slime)  Swallow · Goo Barrage · Split · Bounce

	Bosses are not staggered by hits (MobManager / SkillManager), so a player
	hitting non-stop can't lock them out of their moves.
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

local DifficultyManager = require(script.Parent:WaitForChild("DifficultyManager"))

local BossAI = {}

export type Kind = {
	name: string,
	health: number, -- × the base boss health
	damage: number, -- × the base boss damage
	xp: number,
	color: Color3,
	moves: { string },
}

BossAI.Kinds = {
	warlord = {
		name = "★ The Iron Warlord", health = 3.5, damage = 1.2, xp = 3,
		color = Color3.fromRGB(255, 90, 40), moves = { "slam", "charge", "whirlwind" },
	},
	witch = {
		name = "★ The Hex Witch", health = 2.8, damage = 1, xp = 3,
		color = Color3.fromRGB(120, 255, 120), moves = { "nova", "hex", "summon", "blink" },
	},
	colossus = {
		name = "★ The Bone Colossus", health = 4.5, damage = 1.4, xp = 3.5,
		color = Color3.fromRGB(255, 170, 60), moves = { "meteors", "shockwave", "stomp" },
	},
	slime = {
		name = "★ The Slime King", health = 4, damage = 1.1, xp = 3.5,
		color = Color3.fromRGB(110, 235, 90), moves = { "swallow", "goo", "split", "bounce" },
	},
} :: { [string]: Kind }

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
}

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

MOVES.swallow = function(b, target)
	-- Lunge onto the target; if they're still there they are engulfed: held
	-- inside the slime and digested for a moment, then spat out.
	local spot = target.root.Position
	local wind = if b.enraged then 0.4 else 0.55
	telegraphCircle(spot, 5, wind, b.floorY)
	face(b, spot)
	if not hold(b, wind) then return end
	hop(b, spot, 6, 0.3)
	shock(spot, 6, GOO, b.floorY)
	local victim: Victim? = nil
	for _, v in ipairs(victims()) do
		if flatDist(v.root.Position, b.root.Position) <= 6
			and (v.char:GetAttribute("InvulnerableUntil") or 0) <= os.clock()
			and (v.char:GetAttribute("ParryUntil") or 0) <= os.clock() then
			victim = v
			break
		end
	end
	if not victim then hold(b, 0.25) return end
	local v = victim :: Victim
	v.char:SetAttribute("Swallowed", true)
	setGroup(v.char, SWALLOWED)
	v.root.Anchored = true
	scaleBoss(b, 1.25)
	local held = if b.enraged then 2.2 else 1.6
	local t0 = os.clock()
	local lastBite = 0
	while os.clock() - t0 < held and alive(b) and v.hum.Health > 0 and v.root.Parent do
		v.root.CFrame = b.root.CFrame * CFrame.new(0, 0.5, 0)
		if os.clock() - lastBite > 0.4 then
			lastBite = os.clock()
			v.hum:TakeDamage(dmg(b, 0.3))
		end
		RunService.Heartbeat:Wait()
	end
	-- Spit them out a few studs ahead, briefly untouchable.
	scaleBoss(b, 1)
	local out = b.root.Position + b.root.CFrame.LookVector * 9
	if v.root.Parent then
		v.root.CFrame = CFrame.new(out.X, groundAt(out, b) + 3.2, out.Z)
		v.root.Anchored = false
		v.char:SetAttribute("InvulnerableUntil", os.clock() + 1)
	end
	v.char:SetAttribute("Swallowed", nil)
	setGroup(v.char, "Default")
	puddle(b, out, 4, 3)
	hold(b, 0.3)
end

MOVES.goo = function(b, _target)
	-- Lob a barrage of goo balls around the players; each splats into a
	-- burning puddle.
	local count = if b.enraged then 12 else 8
	for _ = 1, count do
		local vs = victims()
		if #vs == 0 then break end
		local v = vs[math.random(1, #vs)]
		local a = math.random() * math.pi * 2
		local spot = v.root.Position + Vector3.new(math.cos(a), 0, math.sin(a)) * math.random(0, 8)
		telegraphCircle(spot, 4, 0.5, b.floorY)
		local from = b.root.Position + Vector3.new(0, 3, 0)
		local ball = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.8, CFrame = CFrame.new(from), Color = GOO,
			Material = Enum.Material.Glass, Transparency = 0.2 })
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.5 do
				local k = (os.clock() - t0) / 0.5
				ball.CFrame = CFrame.new(from:Lerp(spot, k) + Vector3.new(0, math.sin(k * math.pi) * 14, 0))
				RunService.Heartbeat:Wait()
			end
			ball:Destroy()
			blast(spot, 4, dmg(b, 0.5))
			puddle(b, spot, 4, 4)
		end)
		if not hold(b, if b.enraged then 0.08 else 0.12) then return end
	end
	hold(b, 0.4)
end

MOVES.split = function(b, target)
	-- Squash down and burst: a goo shockwave rolls out (jump it) and little
	-- slimes pop off.
	scaleBoss(b, 0.8)
	telegraphCircle(b.root.Position, 5, 0.45, b.floorY)
	if not hold(b, 0.45) then scaleBoss(b, 1) return end
	scaleBoss(b, 1.15)
	blast(b.root.Position, 7, dmg(b, 0.8))
	MOVES.shockwaveOnce(b, target)
	for i = #b.minions, 1, -1 do
		local m = b.minions[i]
		local h = m:FindFirstChildOfClass("Humanoid")
		if not m.Parent or not h or h.Health <= 0 then table.remove(b.minions, i) end
	end
	local spawnN = math.min(if b.enraged then 4 else 3, 8 - #b.minions)
	for i = 1, spawnN do
		local a = (i / spawnN) * math.pi * 2
		local pos = b.root.Position + Vector3.new(math.cos(a) * 8, 0, math.sin(a) * 8)
		local m = deps.spawnMinion(Vector3.new(pos.X, b.floorY, pos.Z))
		if m then table.insert(b.minions, m) end
		puddle(b, pos, 3, 3)
	end
	scaleBoss(b, 1)
	hold(b, 0.3)
end

MOVES.bounce = function(b, target)
	-- A chain of fast hops chasing the target, each landing with a splash.
	local hops = if b.enraged then 5 else 4
	for _ = 1, hops do
		local v = nearestVictim(b) or target
		local spot = v.root.Position
		telegraphCircle(spot, 6, 0.3, b.floorY)
		if not hold(b, 0.3) then return end
		hop(b, spot, 7, 0.28)
		shock(spot, 7, GOO, b.floorY)
		blast(spot, 6, dmg(b, 0.7))
	end
	hold(b, 0.3)
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
	local b: Boss = {
		model = model, hum = hum, root = root, kind = kind,
		floorY = model:GetAttribute("FloorY") or (root.Position.Y - 3),
		damage = kind.damage * DifficultyManager.GetMobScale(model:GetAttribute("RunId")).damage,
		enraged = false, minions = {},
	}
	addAura(b)
	if kindId == "slime" then
		-- Solid, not see-through (the model's goo parts are partly transparent).
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") and d ~= root and d.Transparency > 0 and d.Transparency < 0.95 then
				d.Transparency = 0
			end
		end
	end
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
		if not b.enraged and h > 0 and h <= hum.MaxHealth * 0.5 then enrage(b) end
	end)

	task.spawn(function()
		local last = ""
		if not hold(b, 0.6) then return end
		while alive(b) do
			local target = nearestVictim(b)
			if target and deps.canAct(model) then
				local options = {}
				for _, m in ipairs(kind.moves) do
					if m ~= last then table.insert(options, m) end
				end
				local move = options[math.random(1, #options)]
				last = move
				model:SetAttribute("BossBusy", true)
				hum:Move(Vector3.zero)
				local ok, err = pcall(MOVES[move], b, target)
				if not ok then warn(`[BossAI] {kind.name} {move} failed:`, err) end
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
