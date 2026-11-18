--!strict
--[[
	ExitArrows.luau
	Once a floor's done (its boss room cleared: RunScope "BossRoom" in
	"ClearedRooms"), arrows on the ground lead each player to the way out,
	on every map: the lift, the Infernal Keep's dark hall, the arcade's
	portal (RunScope "ExitAt", set by DungeonGenerator's watchPortals; an
	extraction floor's portal, "ExtractAt", when it's nearer).

	A short chain of glowing chevrons runs from your feet along a path
	(PathfindingService, worked out again every couple of seconds or when
	you've moved on), a pulse running along it toward the exit. They go once
	you're there, dead, or the floor changes.

	Cheap: one pool of chevrons made once and moved (never re-made), a path
	only every 2 s, nothing at all until the floor's done.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local PathfindingService = game:GetService("PathfindingService")
local Workspace = game:GetService("Workspace")

local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))

local player = Players.LocalPlayer

local ExitArrows = {}

local COUNT = 9          -- chevrons shown
local SPACING = 6        -- studs between them
local FIRST = 4          -- studs ahead of you, the first
local NEAR = 12          -- this close to the way out: no arrows
local REPATH = 2         -- seconds between paths
local REPATH_MOVED = 10  -- ... or once you've moved this far from the last one's start
local COLOR = Color3.fromRGB(255, 236, 170)

type Chevron = { model: Model, left: BasePart, right: BasePart }
local chevrons: { Chevron } = {}
local folder: Folder? = nil

local path: { Vector3 }? = nil
local pathFrom: Vector3? = nil
local pathTo: Vector3? = nil
local lastPath = 0
local computing = false

local function part(parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = COLOR
	p.Size = Vector3.new(0.6, 0.15, 2.8)
	p.Parent = parent
	return p
end

-- The pool: made once, the first time arrows are wanted.
local function ensurePool()
	if folder then return end
	local f = Instance.new("Folder")
	f.Name = "ExitArrows"
	f.Parent = Workspace
	folder = f
	for i = 1, COUNT do
		local m = Instance.new("Model")
		m.Name = "Chevron" .. i
		m.Parent = f
		table.insert(chevrons, { model = m, left = part(m), right = part(m) })
	end
end

local function hideAll()
	for _, c in ipairs(chevrons) do
		c.left.Transparency = 1
		c.right.Transparency = 1
	end
end

-- Where to go: the way down, or the extraction portal when it's nearer.
local function target(from: Vector3): Vector3?
	local exit = RunScope.Mine("ExitAt")
	local extract = RunScope.Mine("ExtractAt")
	local best: Vector3? = nil
	for _, v in ipairs({ exit, extract }) do
		if typeof(v) == "Vector3" and (not best or (v - from).Magnitude < (best - from).Magnitude) then best = v end
	end
	return best
end

-- Is this floor done (its boss room cleared)?
local function floorDone(): boolean
	local boss = RunScope.Mine("BossRoom")
	local cleared = RunScope.Mine("ClearedRooms")
	if boss == nil or typeof(cleared) ~= "string" then return false end
	return string.find(cleared, `|{boss}|`, 1, true) ~= nil
end

local function computePath(from: Vector3, to: Vector3)
	if computing then return end
	computing = true
	lastPath = os.clock()
	pathFrom, pathTo = from, to
	task.spawn(function()
		local p = PathfindingService:CreatePath({ AgentRadius = 2, AgentHeight = 5, AgentCanJump = true, WaypointSpacing = 3 })
		local ok = pcall(function() p:ComputeAsync(from, to) end)
		if ok and p.Status == Enum.PathStatus.Success then
			local pts = {}
			for _, wp in ipairs(p:GetWaypoints()) do table.insert(pts, wp.Position) end
			path = pts
		else
			-- (no way found: straight at it)
			path = { from - Vector3.new(0, 2.5, 0), to }
		end
		computing = false
	end)
end

-- The point `d` studs along the path from where it's nearest `from`, and its heading.
local function along(pts: { Vector3 }, from: Vector3, d: number): (Vector3?, Vector3?)
	-- (start from the segment nearest you)
	local bestI, bestD, bestP = 1, math.huge, pts[1]
	for i = 1, #pts - 1 do
		local a, b = pts[i], pts[i + 1]
		local ab = b - a
		local t = if ab.Magnitude > 0 then math.clamp((from - a):Dot(ab) / ab:Dot(ab), 0, 1) else 0
		local onto = a + ab * t
		local dist = (onto - from).Magnitude
		if dist < bestD then bestI, bestD, bestP = i, dist, onto end
	end
	local left = d
	-- (measured from the point of the path beside you, not its segment's start)
	local a = bestP
	for i = bestI, #pts - 1 do
		local b = pts[i + 1]
		local seg = (b - a).Magnitude
		if seg >= left and seg > 0 then
			local dir = (b - a).Unit
			return a + dir * left, dir
		end
		left -= seg
		a = b
	end
	return nil, nil
end

local function step()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local active = root ~= nil and hum ~= nil and hum.Health > 0 and player:GetAttribute("InLobby") == false
		and player:GetAttribute("IsDead") ~= true and floorDone()
	local to = if active and root then target(root.Position) else nil
	if not active or not to or not root or (to - root.Position).Magnitude < NEAR then
		hideAll()
		if not active then path = nil end
		return
	end
	ensurePool()
	local from = root.Position
	if not computing and (not path or pathTo ~= to or os.clock() - lastPath > REPATH
		or (pathFrom and (from - pathFrom).Magnitude > REPATH_MOVED)) then
		computePath(from, to)
	end
	local pts = path
	if not pts then
		hideAll()
		return
	end
	local t = os.clock()
	for i, c in ipairs(chevrons) do
		local at, dir = along(pts, from, FIRST + (i - 1) * SPACING)
		if not at or not dir or (at - to).Magnitude < 2 then
			c.left.Transparency, c.right.Transparency = 1, 1
			continue
		end
		local flat = Vector3.new(dir.X, 0, dir.Z)
		if flat.Magnitude < 0.05 then flat = Vector3.new(0, 0, -1) end
		local cf = CFrame.lookAt(at + Vector3.new(0, 0.3, 0), at + Vector3.new(0, 0.3, 0) + flat.Unit)
		-- (a ">" laid flat, its point toward the exit; the pulse runs that way)
		c.left.CFrame = cf * CFrame.new(-0.7, 0, 0.45) * CFrame.Angles(0, math.rad(-40), 0)
		c.right.CFrame = cf * CFrame.new(0.7, 0, 0.45) * CFrame.Angles(0, math.rad(40), 0)
		local pulse = 0.5 + 0.5 * math.sin(t * 6 - i * 0.9)
		local fade = math.clamp((i - 1) / COUNT, 0, 1)
		local a = 0.15 + 0.45 * (1 - pulse) + 0.3 * fade
		c.left.Transparency, c.right.Transparency = a, a
	end
end

function ExitArrows.Init()
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		-- (the floor's state is checked a few times a second; the chevrons
		-- move every frame only while they're shown)
		acc += dt
		if acc < 1 / 30 then return end
		acc = 0
		local ok, err = pcall(step)
		if not ok then warn("[ExitArrows]", err) end
	end)
end

return ExitArrows
