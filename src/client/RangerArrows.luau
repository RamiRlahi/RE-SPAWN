--!strict
--[[
	RangerArrows.luau
	Draws the Ranger's basic arrows, which are real projectiles: the server
	flies each one and deals its damage when it arrives (SkillManager). Here
	they're drawn smoothly every frame on every screen:

	  • the shooter's own volley straight away, as the string is released
	    (RangerArrows.FireLocal), with the same keys the server gives them
	  • everyone else's from the server's "fire" message
	  • each one stops where the server says it landed ("hit": an enemy or a
	    wall); until then the screen stops it at the first wall or enemy it
	    reaches by itself, so it never flies through them

	An arrow that lands sticks there a moment, then goes.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RangerArrowData = require(Shared:WaitForChild("RangerArrowData"))
local HumanoidIndex = require(Shared:WaitForChild("HumanoidIndex"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local RangerArrows = {}

local player = Players.LocalPlayer
local STICK_TIME = 0.45
local TRAIL_COLOR = Color3.fromRGB(190, 255, 170)

type Flying = {
	model: Instance,
	turn: CFrame,      -- the model's own orientation relative to its flight
	origin: Vector3,
	dir: Vector3,
	speed: number,
	range: number,
	dist: number,
	stopAt: number?,   -- where it lands (the server's word, or what this screen saw)
}
local flying: { [string]: Flying } = {}
local conn: RBXScriptConnection? = nil
local folder: Folder? = nil
local shotCounter = 0

local wallParams = RaycastParams.new()
wallParams.FilterType = Enum.RaycastFilterType.Include
wallParams.IgnoreWater = true

-- ── The arrow model ─────────────────────────────────────────────────────────
-- The game's own arrow asset if there is one (the same the server used to fly),
-- else a simple wooden arrow.
local template: Instance? = nil
local templateTurn = CFrame.Angles(0, math.rad(90), 0) -- (the asset lies along X)
local looked = false
local function findTemplate(): Instance?
	if looked then return template end
	looked = true
	local a = ReplicatedStorage:FindFirstChild("Arrow") or ReplicatedStorage:FindFirstChild("arrow")
	if not (a and (a:IsA("Model") or a:IsA("BasePart"))) then
		local assets = ReplicatedStorage:FindFirstChild("Assets")
		local classes = assets and assets:FindFirstChild("Classes")
		local ranger = classes and classes:FindFirstChild("Ranger armor")
		a = ranger and (ranger:FindFirstChild("Arrow") or ranger:FindFirstChild("arrow"))
	end
	template = if a and (a:IsA("Model") or a:IsA("BasePart")) then a else nil
	return template
end

local function plainArrow(): Model
	local m = Instance.new("Model")
	local function bit(size: Vector3, cf: CFrame, color: Color3, material: Enum.Material)
		local p = Instance.new("Part")
		p.Size, p.CFrame, p.Color, p.Material = size, cf, color, material
		p.Parent = m
		return p
	end
	-- along -Z (the way it flies)
	local shaft = bit(Vector3.new(0.12, 0.12, 2.6), CFrame.new(), Color3.fromRGB(120, 84, 50), Enum.Material.Wood)
	m.PrimaryPart = shaft
	bit(Vector3.new(0.26, 0.08, 0.4), CFrame.new(0, 0, -1.4), Color3.fromRGB(150, 255, 120), Enum.Material.Neon)
	bit(Vector3.new(0.34, 0.03, 0.5), CFrame.new(0, 0, 1.1), Color3.fromRGB(235, 235, 225), Enum.Material.SmoothPlastic)
	bit(Vector3.new(0.03, 0.34, 0.5), CFrame.new(0, 0, 1.1), Color3.fromRGB(235, 235, 225), Enum.Material.SmoothPlastic)
	return m
end

local function holder(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "RangerArrows"
	f.Parent = Workspace
	folder = f
	return f
end

local function place(f: Flying, at: Vector3)
	local cf = CFrame.lookAt(at, at + f.dir) * f.turn
	if f.model:IsA("Model") then
		(f.model :: Model):PivotTo(cf)
	else
		(f.model :: BasePart).CFrame = cf
	end
end

local function spawnModel(origin: Vector3, dir: Vector3): (Instance, CFrame)
	local t = findTemplate()
	local m: Instance = if t then t:Clone() else plainArrow()
	local turn = if t then templateTurn else CFrame.identity
	local parts = if m:IsA("BasePart") then { m } else m:GetDescendants()
	local first: BasePart? = nil
	for _, d in ipairs(parts) do
		if d:IsA("BasePart") then
			d.Anchored, d.CanCollide, d.CanTouch, d.CanQuery, d.CastShadow = true, false, false, false, false
			first = first or d
		end
	end
	local cf = CFrame.lookAt(origin, origin + dir) * turn
	if m:IsA("Model") then (m :: Model):PivotTo(cf) else (m :: BasePart).CFrame = cf end
	-- a faint green streak behind it
	if first then
		local a0, a1 = Instance.new("Attachment"), Instance.new("Attachment")
		a0.Parent, a1.Parent = first, first
		a0.WorldPosition = origin + Vector3.new(0, 0.12, 0)
		a1.WorldPosition = origin - Vector3.new(0, 0.12, 0)
		local tr = Instance.new("Trail")
		tr.Attachment0, tr.Attachment1 = a0, a1
		tr.Color = ColorSequence.new(Color3.new(1, 1, 1), TRAIL_COLOR)
		tr.Transparency = NumberSequence.new(0.35, 1)
		tr.Lifetime = 0.12
		tr.LightEmission = 1
		tr.FaceCamera = true
		tr.Parent = first
	end
	m.Parent = holder()
	return m, turn
end

-- An arrow that has landed: it stays stuck there a moment, then fades.
local function land(f: Flying, at: Vector3)
	place(f, at)
	local m = f.model
	for _, d in ipairs(if m:IsA("BasePart") then { m } else m:GetDescendants()) do
		if d:IsA("Trail") then d.Enabled = false end
		if d:IsA("BasePart") then
			TweenService:Create(d, TweenInfo.new(0.25, Enum.EasingStyle.Linear, Enum.EasingDirection.In, 0, false, STICK_TIME), { Transparency = 1 }):Play()
		end
	end
	Debris:AddItem(m, STICK_TIME + 0.3)
end

-- ── Flying ──────────────────────────────────────────────────────────────────
local function enemies(): { { pos: Vector3 } }
	local out = {}
	for model, hum in pairs(HumanoidIndex.Each()) do
		if hum.Health > 0 and model.Parent and not Players:GetPlayerFromCharacter(model)
			and model:GetAttribute("IsAlly") ~= true and model:GetAttribute("IsDecoy") ~= true then
			local r = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
			if r and r:IsA("BasePart") then table.insert(out, { pos = r.Position }) end
		end
	end
	return out
end

local function step(dt: number)
	local walls = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		if c.Name == "GeneratedDungeon" then table.insert(walls, c) end
	end
	wallParams.FilterDescendantsInstances = walls
	local foes: { { pos: Vector3 } }? = nil
	for key, f in pairs(flying) do
		if not f.model.Parent then
			flying[key] = nil
			continue
		end
		local move = f.speed * dt
		local here = f.origin + f.dir * f.dist
		-- (no word from the server yet: stop at the first wall or enemy reached)
		if not f.stopAt then
			local wall = if #walls > 0 then Workspace:Raycast(here, f.dir * move, wallParams) else nil
			local limit = if wall then wall.Distance else move
			foes = foes or enemies()
			for _, e in ipairs(foes :: { { pos: Vector3 } }) do
				local d = Vector3.new(e.pos.X - here.X, 0, e.pos.Z - here.Z)
				local along = d:Dot(f.dir)
				if along >= 0 and along <= limit and math.abs(e.pos.Y - here.Y) <= 9 and (d - f.dir * along).Magnitude <= 2 then
					limit = along
					wall = nil
					f.stopAt = f.dist + along
				end
			end
			if wall then f.stopAt = f.dist + wall.Distance end
		end
		local stop = math.min(f.stopAt or f.range, f.range)
		if f.dist + move >= stop then
			flying[key] = nil
			land(f, f.origin + f.dir * stop)
		else
			f.dist += move
			place(f, f.origin + f.dir * f.dist)
		end
	end
	if next(flying) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

local function fly(owner: Player, key: number, origin: Vector3, dir: Vector3, speed: number, always: boolean?)
	if not always and not FxBudget.Allow("rangerArrow", 40, 12) then return end
	local id = `{owner.UserId}:{key}`
	local old = flying[id]
	if old then old.model:Destroy() end
	local model, turn = spawnModel(origin, dir)
	flying[id] = { model = model, turn = turn, origin = origin, dir = dir, speed = speed, range = RangerArrowData.RANGE, dist = 0 }
	if not conn then conn = RunService.RenderStepped:Connect(step) end
end

-- The server says where an arrow landed.
local function onHit(owner: Player, key: number, at: Vector3)
	local id = `{owner.UserId}:{key}`
	local f = flying[id]
	if not f then return end
	local along = Vector3.new(at.X - f.origin.X, 0, at.Z - f.origin.Z):Dot(f.dir)
	if along <= f.dist then
		-- (already past it on this screen: it lands there now)
		flying[id] = nil
		land(f, f.origin + f.dir * math.max(along, 0))
	else
		f.stopAt = along
	end
end

-- ── Public ──────────────────────────────────────────────────────────────────
-- A fresh volley number, for the shooter's PerformAttack (`shot`).
function RangerArrows.NextShot(): number
	shotCounter = (shotCounter + 1) % 900000
	return shotCounter
end

-- Draw this player's own volley now (the server flies the same one).
function RangerArrows.FireLocal(shot: number, origin: Vector3, look: Vector3)
	local count = 1 + math.max(0, math.floor(tonumber(player:GetAttribute("Stat_projectileCount")) or 0))
	local speed = RangerArrowData.SPEED * math.max(0.2, tonumber(player:GetAttribute("Stat_projectileSpeed")) or 1)
	local width = RangerArrowData.WIDTH * (tonumber(player:GetAttribute("Stat_size")) or 1)
	local positions = {}
	for i, e in ipairs(enemies()) do positions[i] = e.pos end
	for index, dir in ipairs(RangerArrowData.Directions(look, count)) do
		dir = RangerArrowData.Assist(origin, dir, positions, function() return width + 1 end)
		fly(player, RangerArrowData.Key(shot, index), origin, dir, speed, index == 1)
	end
end

function RangerArrows.Init()
	Network.GetRemoteEvent(Network.Remotes.RangerArrows).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local owner = msg.attacker
		if typeof(owner) ~= "Instance" or not owner:IsA("Player") then return end
		if msg.kind == "fire" and typeof(msg.shots) == "table" then
			local speed = tonumber(msg.speed) or RangerArrowData.SPEED
			for _, s in ipairs(msg.shots) do
				if typeof(s) == "table" and typeof(s.origin) == "Vector3" and typeof(s.dir) == "Vector3" and typeof(s.key) == "number" then
					fly(owner, s.key, s.origin, s.dir, speed)
				end
			end
		elseif msg.kind == "hit" and typeof(msg.key) == "number" and typeof(msg.at) == "Vector3" then
			onHit(owner, msg.key, msg.at)
		end
	end)
end

return RangerArrows
