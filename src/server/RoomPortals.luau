--!strict
--[[
	RoomPortals.luau
	The Neon Arcade's way through a floor (MapData transit "portal").
	DungeonGenerator lays the floor out room by room (buildLayeredGraph:
	layers of 1, 2, 3, 2 and 1 rooms, the last the boss's), every room an
	island on its own. Here, each room's ways on: a portal gate (ArcadeKit's
	"Gate_Portal") on its far wall for each room of the next layer, a sign over
	each saying what's through it. They stay dark until the room is cleared
	(its mobs all dead: MobManager's ClearedRooms; a room with none opens at
	once). Which way the party goes is a vote: step into an open portal to
	vote for it (into another to change your vote); its sign counts the votes
	and names who cast them. When one way has more than half the party's votes
	(the living), the whole party goes through together, out at that room's
	entrance, facing in; and the map, only ever the room you're in, moves with
	you. (Alone, your vote is everyone's: through at once.) The party is kept
	in one room: anyone who comes back from the dead elsewhere, or is left
	outside it, is brought to the party's room.

	  RoomPortals.Build(rooms, runId, parent)   DungeonGenerator, as it builds
	      the floor (`rooms`: its RoomData; `connections`, the next layer's ids)

	Watched a few times a second (no touch events: the dungeon's parts listen
	for none). A floor's portals go when the floor is cleared away.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ArcadeKit = require(Shared:WaitForChild("ArcadeKit"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local Network = require(Shared:WaitForChild("Network"))

local RoomPortals = {}

local FLOOR = 12      -- (DungeonGenerator's FLOOR_SIZE)
local INSIDE = 3.5    -- how far in from its wall a gate stands
local ENTRY = 16      -- where the party steps out: this far in from the room's back wall
local GRACE = 1.5     -- seconds after a trip before the same player can vote again
local ARRIVE_SAFE = 1.5 -- seconds no hit lands on you as you step out (the room's mobs wake as you arrive)
local TICK = 0.15
-- (a gate's mouth, in its own space: its disc spans ±6 across, up to 14)
local MOUTH_X, MOUTH_Y, MOUTH_Z = 6, 14, 1.8
local PURPLE = Color3.fromRGB(160, 80, 255)
local SHUT = Color3.fromRGB(56, 40, 76)

-- What's through each way (the room's type): its name, a line, its colour.
local SIGNS: { [string]: { any } } = {
	Combat = { "COMBAT", "A fight, and its reward", Color3.fromRGB(255, 90, 110) },
	Elite = { "ELITE", "Tougher foes, a better reward", Color3.fromRGB(190, 110, 255) },
	Treasure = { "TREASURE", "A chest, no fight", Color3.fromRGB(255, 210, 90) },
	Shop = { "SHOP", "The merchant's wares", Color3.fromRGB(110, 230, 140) },
	Rest = { "REST", "The Moonwell: heal", Color3.fromRGB(110, 220, 255) },
	Gamble = { "GAMBLE", "The Wheel of Fate", Color3.fromRGB(255, 160, 60) },
	Event = { "EVENT", "Something strange", Color3.fromRGB(235, 235, 255) },
	Cursed = { "CURSED ALTAR", "Power, at a price", Color3.fromRGB(220, 50, 90) },
	Purge = { "PURGE SHRINE", "Give up a tome", Color3.fromRGB(160, 255, 220) },
	Boss = { "BOSS", "The floor's master", Color3.fromRGB(255, 60, 60) },
}
-- (rooms MobManager fills with no mobs: open as soon as you're in)
local NO_MOBS = { Start = true, Rest = true, Treasure = true, Shop = true, Gamble = true }

type Room = { id: number, roomType: string, gx: number, gz: number, w: number, d: number, floorY: number, connections: { number } }
type Exit = { model: Model, cf: CFrame, from: Room, to: Room, open: boolean, lock: TextLabel?, tally: TextLabel?, names: TextLabel? }
type Floor = { runId: string, folder: Folder, rooms: { [number]: Room }, exits: { Exit }, entries: { [number]: CFrame },
	votes: { [Player]: Exit }, here: number }

local floors: { Floor } = {}
local grace: { [Player]: number } = {}
local stepping: RBXScriptConnection? = nil
local acc = 0

local function flash(at: Vector3)
	local f = Instance.new("Part")
	f.Shape = Enum.PartType.Ball
	f.Material = Enum.Material.Neon
	f.Color = Color3.fromRGB(240, 150, 255)
	f.Size = Vector3.one * 3
	f.Anchored, f.CanCollide, f.CanQuery, f.CanTouch, f.CastShadow = true, false, false, false, false
	f.CFrame = CFrame.new(at)
	f.Parent = workspace
	TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * 12, Transparency = 1 }):Play()
	Debris:AddItem(f, 0.4)
end

local function cleared(runId: string, room: Room): boolean
	if room.id == 1 or NO_MOBS[room.roomType] then return true end
	local list = RunScope.Get(runId, "ClearedRooms")
	return typeof(list) == "string" and string.find(list, "|" .. room.id .. "|", 1, true) ~= nil
end

-- A gate lit and open, or dark and shut (its disc dim, no swirl, no orb).
local function setOpen(e: Exit, open: boolean)
	e.open = open
	local m = e.model
	local disc = m:FindFirstChild("PortalDisc") :: BasePart?
	if disc then
		disc.Transparency = if open then 0.25 else 0.8
		disc.Color = if open then PURPLE else SHUT
	end
	local sheet = m:FindFirstChild("PortalSheet")
	for _, sg in ipairs(if sheet then sheet:GetChildren() else {}) do
		if sg:IsA("SurfaceGui") then sg.Enabled = open end
	end
	local orb = m:FindFirstChild("PortalOrb") :: BasePart?
	local halo = m:FindFirstChild("PortalHalo") :: BasePart?
	if orb then orb.Transparency = if open then 0 else 1 end
	if halo then halo.Transparency = if open then 0.7 else 1 end
	local motes = orb and orb:FindFirstChildOfClass("ParticleEmitter")
	if motes then motes.Enabled = open end
	if e.lock then e.lock.Visible = not open end
	if e.tally then e.tally.Visible = open end
end

-- The sign over a gate: what's through it.
local function sign(e: Exit, at: Vector3)
	local info = SIGNS[e.to.roomType] or SIGNS.Combat
	local anchor = Instance.new("Part")
	anchor.Name = "PortalSign"
	anchor.Size = Vector3.one * 0.2
	anchor.Transparency = 1
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.CFrame = CFrame.new(at)
	anchor.Parent = e.model
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(240, 104)
	bb.MaxDistance = 160
	bb.LightInfluence = 0
	local function line(text: string, y: number, h: number, color: Color3): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(0, y)
		t.Size = UDim2.new(1, 0, 0, h)
		t.Text = text
		t.Font = Enum.Font.Arcade
		t.TextScaled = true
		t.TextColor3 = color
		t.TextStrokeTransparency = 0.25
		t.Parent = bb
		return t
	end
	line(info[1], 0, 34, info[3])
	line(info[2], 36, 20, Color3.fromRGB(235, 228, 255))
	e.lock = line("CLEAR THE ROOM", 60, 18, Color3.fromRGB(255, 120, 140))
	-- (the votes for it: how many and how long left; who cast them)
	e.tally = line("", 60, 18, Color3.fromRGB(255, 235, 140))
	e.names = line("", 82, 16, Color3.fromRGB(220, 210, 245))
	bb.Parent = anchor
end

-- The map: just the room they're in.
local function sendMap(f: Floor, room: Room)
	local grid = {}
	for x = room.gx, room.gx + room.w - 1 do
		for z = room.gz, room.gz + room.d - 1 do
			grid[x .. "_" .. z] = { floorY = room.floorY, wallY = room.floorY + 7, tier = 0 }
		end
	end
	local payload = { tileSize = FLOOR, grid = grid,
		rooms = { { id = room.id, roomType = room.roomType, gx = room.gx, gz = room.gz, w = room.w, d = room.d } } }
	local remote = Network.GetRemoteEvent(Network.Remotes.DungeonMapData)
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("RunId") == f.runId then remote:FireClient(plr, payload) end
	end
end

-- Through: the whole party, out at the chosen room's entrance side by side.
local function travel(f: Floor, to: Room, now: number)
	table.clear(f.votes)
	f.here = to.id
	local entry = f.entries[to.id]
	if not entry then return end
	local n = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("RunId") ~= f.runId or plr:GetAttribute("InLobby") ~= false then continue end
		local char = plr.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not (root and hum and hum.Health > 0) then continue end
		-- (spread along the back wall: 0, +4, -4, +8...)
		local side = (if n % 2 == 0 then 1 else -1) * math.ceil(n / 2) * 4
		flash(root.Position)
		root.AssemblyLinearVelocity = Vector3.zero
		root.CFrame = entry * CFrame.new(side, 0, 0)
		grace[plr] = now + GRACE
		char:SetAttribute("InvulnerableUntil", math.max(tonumber(char:GetAttribute("InvulnerableUntil")) or 0, now + ARRIVE_SAFE))
		n += 1
	end
	flash(entry.Position)
	sendMap(f, to)
end

-- Everyone in the run who can vote: in the dungeon, alive.
local function party(f: Floor): { Player }
	local out = {}
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("RunId") ~= f.runId or plr:GetAttribute("InLobby") ~= false then continue end
		local char = plr.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then table.insert(out, plr) end
	end
	return out
end

local function setText(label: TextLabel?, text: string)
	if label and label.Text ~= text then label.Text = text end
end

-- Every sign's count of its votes (and the time left, once it's running).
local function showVotes(f: Floor, total: number, now: number)
	local need = math.floor(total / 2) + 1
	for _, e in ipairs(f.exits) do
		local n, who = 0, {}
		for plr, v in pairs(f.votes) do
			if v == e then
				n += 1
				if #who < 3 then table.insert(who, plr.DisplayName) end
			end
		end
		if n == 0 then
			setText(e.tally, "")
			setText(e.names, "")
		else
			setText(e.tally, `{n}/{need} VOTES`)
			setText(e.names, table.concat(who, ", ") .. (if n > #who then "…" else ""))
		end
	end
end

local function inside(e: Exit, pos: Vector3): boolean
	local l = e.cf:PointToObjectSpace(pos)
	return math.abs(l.X) < MOUTH_X and l.Y > 0 and l.Y < MOUTH_Y and math.abs(l.Z) < MOUTH_Z
end

local function step(dt: number)
	acc += dt
	if acc < TICK then return end
	acc = 0
	local now = os.clock()
	for i = #floors, 1, -1 do
		local f = floors[i]
		if not f.folder.Parent then
			table.remove(floors, i)
			continue
		end
		-- a room's ways on open when it's cleared
		for _, e in ipairs(f.exits) do
			if not e.open and cleared(f.runId, e.from) then
				setOpen(e, true)
				flash(e.cf.Position + Vector3.new(0, 8, 0))
			end
		end
		-- the vote: a step into an open portal is a vote for it
		local voters = party(f)
		local can: { [Player]: boolean } = {}
		for _, plr in ipairs(voters) do
			can[plr] = true
			if (grace[plr] or 0) > now then continue end
			local root = (plr.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then continue end
			for _, e in ipairs(f.exits) do
				if e.open and inside(e, root.Position) then
					if f.votes[plr] ~= e then
						f.votes[plr] = e
						flash(root.Position)
					end
					break
				end
			end
		end
		-- (the dead, the gone and the left don't count)
		for plr in pairs(f.votes) do
			if not can[plr] then f.votes[plr] = nil end
		end
		showVotes(f, #voters, now)
		-- a way with more than half the party's votes: through
		local count: { [Exit]: number } = {}
		local chosen: Exit? = nil
		for _, e in pairs(f.votes) do
			count[e] = (count[e] or 0) + 1
			if count[e] * 2 > #voters then chosen = e end
		end
		if chosen then
			travel(f, chosen.to, now)
			showVotes(f, #voters, now)
		end
		-- one room for the whole party: whoever's outside it (back from the
		-- dead somewhere else, knocked off the edge) is brought to it
		local here = f.rooms[f.here]
		local entry = here and f.entries[here.id]
		if here and entry then
			local minX, maxX = (here.gx - 0.5) * FLOOR - 6, (here.gx + here.w - 0.5) * FLOOR + 6
			local minZ, maxZ = (here.gz - 0.5) * FLOOR - 6, (here.gz + here.d - 0.5) * FLOOR + 6
			for _, plr in ipairs(party(f)) do
				if (grace[plr] or 0) > now then continue end
				local root = (plr.Character :: Model):FindFirstChild("HumanoidRootPart") :: BasePart?
				if not root then continue end
				local p = root.Position
				if p.X < minX or p.X > maxX or p.Z < minZ or p.Z > maxZ or math.abs(p.Y - here.floorY) > 40 then
					root.AssemblyLinearVelocity = Vector3.zero
					root.CFrame = entry
					grace[plr] = now + GRACE
					flash(entry.Position)
					sendMap(f, here)
				end
			end
		end
	end
	for plr in pairs(grace) do
		if not plr.Parent then grace[plr] = nil end
	end
	if #floors == 0 and stepping then
		stepping:Disconnect()
		stepping = nil
	end
end

function RoomPortals.Build(rooms: { Room }, runId: string, parent: Instance)
	local folder = Instance.new("Folder")
	folder.Name = "RoomPortals"
	folder.Parent = parent
	local f: Floor = { runId = runId, folder = folder, rooms = {}, exits = {}, entries = {}, votes = {}, here = 1 }
	for _, r in ipairs(rooms) do f.rooms[r.id] = r end
	for _, r in ipairs(rooms) do
		local top = r.floorY + 0.5
		local minX, maxX = (r.gx - 0.5) * FLOOR, (r.gx + r.w - 0.5) * FLOOR
		local zc = (r.gz + (r.d - 1) / 2) * FLOOR
		-- in at its back wall (-X), facing on toward its exits (+X)
		local entryAt = Vector3.new(minX + ENTRY, top + 3, zc)
		f.entries[r.id] = CFrame.lookAt(entryAt, entryAt + Vector3.xAxis)
		-- out through its far wall (+X): a gate for each room of the next layer
		local n = #r.connections
		local spacing = math.min(30, (r.d * FLOOR - 22) / math.max(n - 1, 1))
		for i, toId in ipairs(r.connections) do
			local to = f.rooms[toId]
			local m = to and ArcadeKit.Build("Gate_Portal")
			if not (to and m) then continue end
			local base = Vector3.new(maxX - INSIDE, top, zc + (i - (n + 1) / 2) * spacing)
			local cf = CFrame.lookAt(base, base - Vector3.xAxis) -- (its face to the room)
			m.Name = "RoomPortal"
			m:PivotTo(cf)
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then
					d.Anchored = true
					d.CanTouch = false
				end
			end
			m.Parent = folder
			local e: Exit = { model = m, cf = cf, from = r, to = to, open = true }
			-- (on the disc, a little in front of it: the camera looks down from high)
			sign(e, base + cf.LookVector * 2.5 + Vector3.new(0, 10, 0))
			setOpen(e, cleared(runId, r))
			table.insert(f.exits, e)
		end
	end
	table.insert(floors, f)
	if not stepping then
		acc = 0
		stepping = RunService.Heartbeat:Connect(step)
	end
end

return RoomPortals
