--!strict
--[[
	Tutorial.luau
	The guided first run (MapData.Tutorial, "The Proving Grounds"): every kind
	of room in turn, taken one at a time through portals, with popups
	explaining each. The client's TutorialController draws them; nothing
	stops while one is up: you play on and do what it says.

	  • Anyone who hasn't finished it ("TutorialDone" on the player, from
	    their save) is guided, once they've picked a class and reached the
	    lobby, to the DUNGEON gate's portal (TutorialController draws the way):
	    walking into it, or using the gate, takes them into the tutorial
	    instead of the map picker. Finishing it (its golden portal:
	    Tutorial.Complete) marks it done. Anyone can replay it from the map
	    picker's TUTORIAL button.
	  • The first room has straw training dummies (tag "TrainingDummy") to try
	    your attack and skills on: they take every hit (damage numbers and
	    all), sway, never fall and heal back up when left alone.
	  • Popups (TutorialStep { step, room, of }): "Start" (the controls) as
	    they land, then each room's kind as the party walks into it, and
	    "<kind>:clear" once a fight room is cleared.
	  • The end: the boss, then the golden portal in its room; stepping in
	    ends the run (no haul: Corruption).

	  Tutorial.Begin(player)          into the tutorial now (from the lobby)
	  Tutorial.Done(player) → boolean finished it before
	  Tutorial.Complete(player)       finished it (Corruption's extract)
	  Tutorial.SetPortal(cf, size)    the lobby portal walked into (LobbyManager)
	  Tutorial.Init()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local MapData = require(Shared:WaitForChild("MapData"))
local ClassData = require(Shared:WaitForChild("ClassData"))

local ClassManager = require(script.Parent:WaitForChild("ClassManager"))
local CampfireManager = require(script.Parent:WaitForChild("CampfireManager"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local RoomPortals = require(script.Parent:WaitForChild("RoomPortals"))
local DungeonGenerator = require(script.Parent:WaitForChild("DungeonGenerator"))

local Tutorial = {}

local TICK = 0.3
local FIGHTS = { Combat = true, Elite = true, Cursed = true, Purge = true, Boss = true }

-- Where each player is in their tutorial run (what they've been shown).
type Progress = { runId: string, room: number, cleared: { [number]: boolean } }
local progress: { [Player]: Progress } = {}

local function step(player: Player, name: string, room: number?)
	local plan = MapData.Tutorial.plan or {}
	Network.GetRemoteEvent(Network.Remotes.TutorialStep):FireClient(player, { step = name, room = room or 1, of = #plan })
end

local function inTutorial(player: Player): string?
	local runId = player:GetAttribute("RunId")
	if typeof(runId) ~= "string" or player:GetAttribute("InLobby") ~= false then return nil end
	return if RunScope.Get(runId, "Tutorial") == true then runId else nil
end

-- ── Done it ─────────────────────────────────────────────────────────────────
function Tutorial.Done(player: Player): boolean
	local p = PlayerData.Get(player) :: any
	return p ~= nil and typeof(p.stats) == "table" and (p.stats.tutorial or 0) > 0
end

function Tutorial.Complete(player: Player)
	local p = PlayerData.Get(player) :: any
	if p then
		if typeof(p.stats) ~= "table" then p.stats = {} end
		p.stats.tutorial = 1
		PlayerData.MarkDirty(player)
	end
	player:SetAttribute("TutorialDone", true)
end

-- ── Going in ────────────────────────────────────────────────────────────────
function Tutorial.Begin(player: Player)
	if player:GetAttribute("InLobby") == false then return end
	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" or not ClassData.GetClass(classId) then return end
	CampfireManager.Unseat(player)
	player:SetAttribute("AtCampfire", nil)
	-- (alone: the run is built on the tutorial's map, ClassManager's callback)
	player:SetAttribute("LobbyMap", MapData.Tutorial.id)
	ClassManager.Enter(player, classId)
end

-- The lobby's portal (the DUNGEON gate's opening): someone who hasn't done
-- the tutorial walking into it goes in.
local portalCF: CFrame? = nil
local portalSize = Vector3.zero
function Tutorial.SetPortal(cf: CFrame, size: Vector3)
	portalCF, portalSize = cf, size
end

local function intoPortal(p: Player)
	if not portalCF or p:GetAttribute("InHub") ~= true or p:GetAttribute("TutorialDone") == true then return end
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local rel = (portalCF :: CFrame):PointToObjectSpace(root.Position)
	local h = portalSize / 2
	if math.abs(rel.X) <= h.X and math.abs(rel.Y) <= h.Y and math.abs(rel.Z) <= h.Z then
		Tutorial.Begin(p)
	end
end

-- ── Straw dummies ───────────────────────────────────────────────────────────
-- A post in the floor, a crossbar for arms, a stuffed sack of a body with a
-- target painted on, a burlap head. A target like any mob (a Humanoid), but
-- anchored (no knockback, no stagger) and never beaten.
local STRAW = Color3.fromRGB(214, 178, 96)
local BURLAP = Color3.fromRGB(176, 140, 92)
local WOOD = Color3.fromRGB(96, 66, 40)
local DUMMY_HP = 1e6
local HEAL_AFTER = 2 -- seconds untouched, then whole again

local function dpart(model: Model, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = true
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = model
	return p
end

local function buildDummy(base: CFrame, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "Straw Dummy"
	m:SetAttribute("TrainingDummy", true)
	dpart(m, { Name = "Post", Size = Vector3.new(0.6, 6.5, 0.6), CFrame = base * CFrame.new(0, 3.25, 0), Color = WOOD, Material = Enum.Material.Wood })
	dpart(m, { Name = "Stand", ClassName = "Part", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.5, 3, 3),
		CFrame = base * CFrame.new(0, 0.25, 0) * CFrame.Angles(0, 0, math.rad(90)), Color = WOOD, Material = Enum.Material.Wood })
	dpart(m, { Name = "Arms", Size = Vector3.new(5.6, 0.5, 0.5), CFrame = base * CFrame.new(0, 5.2, 0), Color = WOOD, Material = Enum.Material.Wood })
	for side = -1, 1, 2 do
		-- straw tufts bound at the ends of the arms
		dpart(m, { Name = "Tuft", Size = Vector3.new(0.9, 0.9, 0.9), CFrame = base * CFrame.new(side * 2.9, 5.2, 0) * CFrame.Angles(0.4, 0.3 * side, 0.5),
			Color = STRAW, Material = Enum.Material.Grass, CanCollide = false })
	end
	local body = dpart(m, { Name = "Body", Size = Vector3.new(2.6, 3.2, 1.8), CFrame = base * CFrame.new(0, 4.2, 0), Color = STRAW, Material = Enum.Material.Fabric })
	dpart(m, { Name = "Belt", Size = Vector3.new(2.7, 0.35, 1.9), CFrame = base * CFrame.new(0, 3.2, 0), Color = BURLAP, Material = Enum.Material.Fabric, CanCollide = false })
	-- the target on its chest (facing -Z: turned to face the room below)
	for i, r in ipairs({ 1.1, 0.75, 0.38 }) do
		dpart(m, { Name = "Ring", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06 + i * 0.01, r * 2, r * 2), CanCollide = false,
			CFrame = body.CFrame * CFrame.new(0, 0.2, -0.92 - i * 0.012) * CFrame.Angles(0, math.rad(90), 0),
			Color = if i % 2 == 1 then Color3.fromRGB(190, 40, 40) else Color3.fromRGB(240, 230, 210), Material = Enum.Material.SmoothPlastic })
	end
	local head = dpart(m, { Name = "Head", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.8, CFrame = base * CFrame.new(0, 6.6, 0), Color = BURLAP, Material = Enum.Material.Fabric })
	for side = -1, 1, 2 do
		dpart(m, { Name = "Stitch", Size = Vector3.new(0.35, 0.08, 0.05), CanCollide = false,
			CFrame = head.CFrame * CFrame.new(side * 0.35, 0.15, -0.88) * CFrame.Angles(0, 0, math.rad(45 * side)), Color = Color3.fromRGB(40, 30, 24) })
	end
	local root = dpart(m, { Name = "HumanoidRootPart", Size = Vector3.new(2.6, 5, 2), CFrame = base * CFrame.new(0, 3.5, 0),
		Transparency = 1, CanCollide = false })
	m.PrimaryPart = root
	local hum = Instance.new("Humanoid")
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
	hum.BreakJointsOnDeath = false
	hum.MaxHealth = DUMMY_HP
	hum.Health = DUMMY_HP
	hum.WalkSpeed = 0
	hum.Parent = m
	-- a hit: a sway back and forth, and whole again once left alone
	local rest = m:GetPivot()
	local lastHit = 0
	local swaying = false
	hum.HealthChanged:Connect(function(h: number)
		if h >= hum.MaxHealth then return end
		lastHit = os.clock()
		local hitAt = lastHit
		task.delay(HEAL_AFTER, function()
			if lastHit == hitAt and hum.Parent then hum.Health = hum.MaxHealth end
		end)
		if swaying then return end
		swaying = true
		task.spawn(function()
			local t0 = os.clock()
			while m.Parent and os.clock() - t0 < 0.6 do
				local k = (os.clock() - t0) / 0.6
				m:PivotTo(rest * CFrame.Angles(math.sin(k * math.pi * 3) * (1 - k) * math.rad(14), 0, 0))
				RunService.Heartbeat:Wait()
			end
			if m.Parent then m:PivotTo(rest) end
			swaying = false
		end)
	end)
	m.Parent = parent
	CollectionService:AddTag(m, "TrainingDummy")
	return m
end

-- Three of them in the first room, in a row in front of where you land.
local function placeDummies(runId: string)
	local folder: Instance? = nil
	for _, f in ipairs(Workspace:GetChildren()) do
		if f.Name == "GeneratedDungeon" and f:GetAttribute("RunId") == runId then folder = f end
	end
	if not folder or folder:FindFirstChild("TrainingDummies") then return end
	local holder = Instance.new("Folder")
	holder.Name = "TrainingDummies"
	holder.Parent = folder
	local spawnAt = DungeonGenerator.GetSpawnCFrame(runId).Position
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Include
	rp.FilterDescendantsInstances = { folder }
	for i = -1, 1 do
		local at = spawnAt + Vector3.new(i * 12, 0, -22 + math.abs(i) * 4)
		local hit = Workspace:Raycast(at + Vector3.new(0, 10, 0), Vector3.new(0, -40, 0), rp)
		local y = if hit then hit.Position.Y else spawnAt.Y - 8
		-- (facing where you land)
		local base = CFrame.lookAt(Vector3.new(at.X, y, at.Z), Vector3.new(spawnAt.X, y, spawnAt.Z))
		buildDummy(base, holder)
	end
end

-- ── Watching the runs ───────────────────────────────────────────────────────
local function watch(player: Player)
	local runId = inTutorial(player)
	local pr = progress[player]
	if not runId or player:GetAttribute("SpawnedInMap") ~= true then
		if pr and not runId then progress[player] = nil end
		return
	end
	if not pr or pr.runId ~= runId then
		-- just landed: the controls, and enough gold to try the shop and the wheel
		pr = { runId = runId, room = 1, cleared = {} }
		progress[player] = pr
		player:SetAttribute("Gold", math.max(player:GetAttribute("Gold") or 0, 300))
		placeDummies(runId)
		step(player, "Start", 1)
		return
	end
	local roomId, roomType = RoomPortals.Here(runId)
	if roomId and roomType and roomId ~= pr.room then
		pr.room = roomId
		step(player, roomType, roomId)
		return
	end
	-- a fight room cleared
	if roomId and roomType and FIGHTS[roomType] and not pr.cleared[roomId] then
		local list = RunScope.Get(runId, "ClearedRooms")
		if typeof(list) == "string" and string.find(list, `|{roomId}|`, 1, true) then
			pr.cleared[roomId] = true
			step(player, roomType .. ":clear", roomId)
		end
	end
end

function Tutorial.Init()
	Players.PlayerRemoving:Connect(function(p) progress[p] = nil end)
	-- (done it or not, from the save: the lobby guides those who haven't)
	PlayerData.OnLoaded(function(p: Player)
		p:SetAttribute("TutorialDone", Tutorial.Done(p))
	end)
	for _, p in ipairs(Players:GetPlayers()) do
		if PlayerData.Get(p) then p:SetAttribute("TutorialDone", Tutorial.Done(p)) end
	end
	task.spawn(function()
		while true do
			task.wait(TICK)
			for _, p in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(watch, p)
				if not ok then warn("[Tutorial]", err) end
				local ok2, err2 = pcall(intoPortal, p)
				if not ok2 then warn("[Tutorial]", err2) end
			end
		end
	end)
	print("[Tutorial] initialized.")
end

return Tutorial
