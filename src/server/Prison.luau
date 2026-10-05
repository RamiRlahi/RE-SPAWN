--!strict
--[[
	Prison.luau
	The prison map's mechanic (MapData.prison). Every combat room has a
	searchlight on its wall, its pool of light sweeping the floor:

	  • it wanders the room, and when it's near a player it turns and hunts
	    them (slower than you run: you can always get out of it)
	  • stand in the light for half a second and you've been SEEN: the light
	    flares red, and the run's sightings go up by one (RunScope
	    "SpotStrikes", the three eyes on the HUD); that light then rests a
	    few seconds
	  • the third sighting raises the ALARM (RunScope "AlarmAt"): the inmates
	    of every other room (MobManager.TakeForAlarm) ride the lifts down into
	    the room you were seen in, through hatches in its ceiling. The
	    sightings start over, and the lights rest a while.

	The lamp models carry what the clients draw (PrisonFX): "SpotAt" (where
	the light is), "FloorY", "Hunting", "SeenAt", "Resting".
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RunScope = require(Shared:WaitForChild("RunScope"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))

local Prison = {}

local FLOOR_SIZE = 12
local TAG = "PrisonSpotlight"
local TICK = 0.1
local SPOT_RADIUS = 6.5       -- the pool of light on the floor
local SEEN_AFTER = 0.5        -- seconds in the light to be seen
local PATROL_SPEED = 10
local HUNT_SPEED = 8.5        -- (a walking player outpaces it)
local HUNT_RANGE = 26         -- a player this close to the light draws it
local LAMP_REST = 5           -- a light that saw someone rests this long
local STRIKES = 3
local ALARM_REST = 25         -- every light rests this long after an alarm
local ALARM_MOBS = 12         -- the most the lifts bring down
local LIFT_HEIGHT = 30        -- how far above the floor the lifts start
local LIFT_TIME = 3.2

type Spot = {
	runId: string,
	lamp: Model,
	room: any,
	minX: number, maxX: number, minZ: number, maxZ: number, floorY: number,
	pos: Vector3,
	goal: Vector3,
	seen: { [Player]: number },
	restUntil: number,
}
local spots: { Spot } = {}
local alarmRestUntil: { [string]: number } = {}
local loopStarted = false

-- ── The lamp ────────────────────────────────────────────────────────────────
local IRON = Color3.fromRGB(52, 54, 60)
local function lampPart(model: Model, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanTouch, p.CanQuery, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Metal
	p.Color = IRON
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = model
	return p
end

-- A searchlight high in the room's corner, aimed at its middle.
local function buildLamp(at: Vector3, aim: Vector3, parent: Instance): Model
	local m = Instance.new("Model")
	m.Name = "Searchlight"
	local cf = CFrame.lookAt(at, aim)
	lampPart(m, { Name = "Bracket", Size = Vector3.new(0.6, 0.6, 3), CFrame = cf * CFrame.new(0, 0, 1.6) })
	local housing = lampPart(m, { Name = "Housing", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.4, 2.2, 2.2),
		CFrame = cf * CFrame.Angles(0, math.rad(90), 0) })
	lampPart(m, { Name = "Lens", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.2, 1.9, 1.9), Material = Enum.Material.Neon,
		Color = Color3.fromRGB(255, 250, 225), CFrame = cf * CFrame.new(0, 0, -1.25) * CFrame.Angles(0, math.rad(90), 0) })
	m.PrimaryPart = housing
	local a = Instance.new("Attachment")
	a.Name = "Beam0"
	a.Parent = housing
	a.WorldPosition = (cf * CFrame.new(0, 0, -1.4)).Position
	m.Parent = parent
	return m
end

-- ── Lifts ───────────────────────────────────────────────────────────────────
local WOOD = Color3.fromRGB(92, 64, 42)
local function liftPart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanTouch, p.CanQuery = false, false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- A lift: a plank platform on two chains, lowered from a hatch high above,
-- carrying `records` (taken by MobManager) down to the floor at `at`.
local function runLift(at: Vector3, floorY: number, records: { any }, parent: Instance)
	local folder = Instance.new("Model")
	folder.Name = "PrisonLift"
	folder.Parent = parent
	local topY = floorY + LIFT_HEIGHT
	-- the platform: physics-driven (smooth on every screen), held level
	local deck = liftPart(folder, { Name = "Deck", Size = Vector3.new(9, 0.7, 9), Color = WOOD, Material = Enum.Material.WoodPlanks,
		CFrame = CFrame.new(at.X, topY, at.Z) })
	deck.Anchored = false
	deck.CanCollide = true
	for _, side in ipairs({ -1, 1 }) do
		local band = liftPart(folder, { Name = "Band", Size = Vector3.new(9.2, 0.75, 0.6), Color = IRON, Material = Enum.Material.Metal,
			CFrame = deck.CFrame * CFrame.new(0, 0, side * 3.2), CanCollide = false })
		band.Anchored = false
		band.Massless = true
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = deck, band
		w.Parent = band
	end
	local att = Instance.new("Attachment")
	att.Parent = deck
	local align = Instance.new("AlignPosition")
	align.Mode = Enum.PositionAlignmentMode.OneAttachment
	align.Attachment0 = att
	align.Position = deck.Position
	align.MaxForce = 1e8
	align.MaxVelocity = LIFT_HEIGHT / LIFT_TIME
	align.Responsiveness = 40
	align.Parent = deck
	local keep = Instance.new("AlignOrientation")
	keep.Mode = Enum.OrientationAlignmentMode.OneAttachment
	keep.Attachment0 = att
	keep.CFrame = CFrame.identity
	keep.MaxTorque = 1e8
	keep.Responsiveness = 40
	keep.Parent = deck
	-- the hatch above and its chains (beams: they follow the deck smoothly)
	local hatch = liftPart(folder, { Name = "Hatch", Size = Vector3.new(11, 1, 11), Color = Color3.fromRGB(30, 30, 34), Material = Enum.Material.Metal,
		CFrame = CFrame.new(at.X, topY + 9, at.Z), CanCollide = false })
	for _, c in ipairs({ Vector3.new(-3.8, 0, -3.8), Vector3.new(3.8, 0, 3.8), Vector3.new(-3.8, 0, 3.8), Vector3.new(3.8, 0, -3.8) }) do
		local a0 = Instance.new("Attachment")
		a0.Position = c + Vector3.new(0, 0.35, 0)
		a0.Parent = deck
		local a1 = Instance.new("Attachment")
		a1.Position = c - Vector3.new(0, 0.5, 0)
		a1.Parent = hatch
		local chain = Instance.new("Beam")
		chain.Attachment0, chain.Attachment1 = a0, a1
		chain.Width0, chain.Width1 = 0.35, 0.35
		chain.Color = ColorSequence.new(Color3.fromRGB(70, 70, 78))
		chain.LightInfluence = 1
		chain.Segments = 1
		chain.FaceCamera = true
		chain.Parent = deck
	end
	pcall(function() deck:SetNetworkOwner(nil) end)

	-- the inmates: up in the world, welded to the deck for the ride, still
	local riders: { Model } = {}
	local spotsOnDeck = { Vector3.new(-2.2, 0, -2.2), Vector3.new(2.2, 0, 2.2), Vector3.new(-2.2, 0, 2.2), Vector3.new(2.2, 0, -2.2) }
	for i, r in ipairs(records) do
		local o = spotsOnDeck[(i - 1) % #spotsOnDeck + 1]
		r.spawnCFrame = CFrame.new(at.X + o.X, floorY, at.Z + o.Z)
		MobManager.ActivateRecord(r)
		local model = r.model :: Model?
		local root = model and model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if model and root then
			model:SetAttribute("MobBusy", true)
			local lift = Vector3.new(0, LIFT_HEIGHT, 0)
			root.CFrame += lift
			local w = Instance.new("WeldConstraint")
			w.Name = "LiftWeld"
			w.Part0, w.Part1 = deck, root
			w.Parent = root
			table.insert(riders, model)
		end
	end

	-- down it comes
	task.wait(0.4)
	align.Position = Vector3.new(at.X, floorY + 0.35, at.Z)
	task.wait(LIFT_TIME + 0.4)
	for _, model in ipairs(riders) do
		local root = model:FindFirstChild("HumanoidRootPart")
		local w = root and root:FindFirstChild("LiftWeld")
		if w then w:Destroy() end
		if model.Parent then model:SetAttribute("MobBusy", false) end
	end
	-- a moment, then back up and gone
	task.wait(1.5)
	align.Position = Vector3.new(at.X, topY + 4, at.Z)
	deck.CanCollide = false
	task.wait(LIFT_TIME + 0.3)
	TweenService:Create(hatch, TweenInfo.new(0.6), { Transparency = 1 }):Play()
	Debris:AddItem(folder, 0.7)
end

-- The alarm: the inmates come down into the room at `pos`.
local function soundAlarm(runId: string, pos: Vector3, parent: Instance)
	alarmRestUntil[runId] = os.clock() + ALARM_REST
	RunScope.Set(runId, "AlarmAt", Workspace:GetServerTimeNow())
	local records, room = MobManager.TakeForAlarm(runId, pos, ALARM_MOBS)
	if not room or #records == 0 then return end
	-- lifts at the room's quarter points nearest its middle, four inmates each
	local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE * 0.5
	local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
	local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE * 0.5
	local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
	local cx, cz = (minX + maxX) / 2, (minZ + maxZ) / 2
	local qx, qz = (maxX - minX) * 0.25, (maxZ - minZ) * 0.25
	local spotsFor = {
		Vector3.new(cx - qx, 0, cz - qz), Vector3.new(cx + qx, 0, cz + qz),
		Vector3.new(cx + qx, 0, cz - qz), Vector3.new(cx - qx, 0, cz + qz),
	}
	local lifts = math.min(#spotsFor, math.ceil(#records / 4))
	for l = 1, lifts do
		local batch = {}
		for i = (l - 1) * 4 + 1, math.min(l * 4, #records) do table.insert(batch, records[i]) end
		local at = spotsFor[l]
		task.spawn(runLift, at, room.floorY, batch, parent)
	end
end

-- ── The searchlights ────────────────────────────────────────────────────────
local function inRun(p: Player, runId: string): boolean
	return p:GetAttribute("RunId") == runId and p:GetAttribute("InLobby") == false and p:GetAttribute("IsDead") ~= true
end

local function playersIn(s: Spot): { { player: Player, root: BasePart } }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if inRun(p, s.runId) then
			local char = p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if root and hum and hum.Health > 0 then
				local q = root.Position
				if q.X >= s.minX and q.X <= s.maxX and q.Z >= s.minZ and q.Z <= s.maxZ and math.abs(q.Y - s.floorY) < 12 then
					table.insert(out, { player = p, root = root })
				end
			end
		end
	end
	return out
end

local function wander(s: Spot): Vector3
	local inset = 8
	return Vector3.new(
		s.minX + inset + math.random() * math.max(1, s.maxX - s.minX - inset * 2),
		s.floorY,
		s.minZ + inset + math.random() * math.max(1, s.maxZ - s.minZ - inset * 2))
end

local function step()
	local now = os.clock()
	for i = #spots, 1, -1 do
		local s = spots[i]
		if not s.lamp.Parent then
			table.remove(spots, i)
			continue
		end
		local inside = playersIn(s)
		local resting = now < s.restUntil or now < (alarmRestUntil[s.runId] or 0)
		if s.lamp:GetAttribute("Resting") ~= resting then s.lamp:SetAttribute("Resting", resting) end
		if #inside == 0 then
			table.clear(s.seen)
			continue -- (nobody here: it waits where it is)
		end
		-- hunt the nearest player close to the light, else wander
		local prey, preyD = nil, HUNT_RANGE
		if not resting then
			for _, v in ipairs(inside) do
				local d = Vector3.new(v.root.Position.X - s.pos.X, 0, v.root.Position.Z - s.pos.Z).Magnitude
				if d < preyD then prey, preyD = v, d end
			end
		end
		local hunting = prey ~= nil
		if s.lamp:GetAttribute("Hunting") ~= hunting then s.lamp:SetAttribute("Hunting", hunting) end
		if prey then
			s.goal = Vector3.new(prey.root.Position.X, s.floorY, prey.root.Position.Z)
		elseif (s.goal - s.pos).Magnitude < 1 then
			s.goal = wander(s)
		end
		local to = s.goal - s.pos
		local speed = if hunting then HUNT_SPEED else PATROL_SPEED
		if to.Magnitude > 0.05 then
			s.pos += to.Unit * math.min(to.Magnitude, speed * TICK)
			s.lamp:SetAttribute("SpotAt", s.pos)
		end
		if resting then
			table.clear(s.seen)
			continue
		end
		-- who's standing in the light
		for _, v in ipairs(inside) do
			local d = Vector3.new(v.root.Position.X - s.pos.X, 0, v.root.Position.Z - s.pos.Z).Magnitude
			if d <= SPOT_RADIUS then
				s.seen[v.player] = (s.seen[v.player] or 0) + TICK
				if (s.seen[v.player] :: number) >= SEEN_AFTER then
					table.clear(s.seen)
					s.restUntil = now + LAMP_REST
					s.goal = wander(s)
					s.lamp:SetAttribute("SeenAt", Workspace:GetServerTimeNow())
					local strikes = (tonumber(RunScope.Get(s.runId, "SpotStrikes")) or 0) + 1
					if strikes >= STRIKES then
						RunScope.Set(s.runId, "SpotStrikes", STRIKES)
						task.spawn(soundAlarm, s.runId, v.root.Position, s.lamp.Parent or Workspace)
						task.delay(2, function() RunScope.Set(s.runId, "SpotStrikes", 0) end)
					else
						RunScope.Set(s.runId, "SpotStrikes", strikes)
					end
					break
				end
			else
				s.seen[v.player] = nil
			end
		end
	end
end

-- Hang a searchlight in every combat room of run `runId`'s new level.
function Prison.Setup(rooms: { any }, runId: string, parent: Instance)
	for i = #spots, 1, -1 do
		if spots[i].runId == runId then table.remove(spots, i) end
	end
	RunScope.Set(runId, "SpotStrikes", 0)
	RunScope.Set(runId, "Prison", true)
	alarmRestUntil[runId] = nil
	for _, room in ipairs(rooms) do
		if room.id == 1 or room.roomType ~= "Combat" and room.roomType ~= "Elite" then continue end
		local minX = room.gx * FLOOR_SIZE - FLOOR_SIZE * 0.5
		local maxX = (room.gx + room.w - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
		local minZ = room.gz * FLOOR_SIZE - FLOOR_SIZE * 0.5
		local maxZ = (room.gz + room.d - 1) * FLOOR_SIZE + FLOOR_SIZE * 0.5
		local center = Vector3.new((minX + maxX) / 2, room.floorY, (minZ + maxZ) / 2)
		-- in a corner, high up (clear of a wide corner pillar)
		local inset = 12
		local corner = Vector3.new(if math.random() < 0.5 then minX + inset else maxX - inset, room.floorY + 22,
			if math.random() < 0.5 then minZ + inset else maxZ - inset)
		local lamp = buildLamp(corner, center, parent)
		lamp:SetAttribute("FloorY", room.floorY)
		lamp:SetAttribute("SpotAt", center)
		lamp:AddTag(TAG)
		table.insert(spots, {
			runId = runId, lamp = lamp, room = room,
			minX = minX, maxX = maxX, minZ = minZ, maxZ = maxZ, floorY = room.floorY,
			pos = center, goal = center, seen = {}, restUntil = 0,
		})
	end
	if not loopStarted then
		loopStarted = true
		task.spawn(function()
			while true do
				task.wait(TICK)
				local ok, err = pcall(step)
				if not ok then warn("[Prison]", err) end
			end
		end)
	end
end

return Prison
