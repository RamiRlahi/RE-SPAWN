--!strict
--[[
	CampfireManager.luau
	The gathering before a run. Confirming a class no longer drops you straight
	into the dungeon: you take a seat at the title scene's brazier, where your
	party (PartyManager) gathers too. Everyone taps READY; once every party
	member still in the lobby is seated and ready, the server opens a red
	portal (clients play it from `portalAt`, server time), the heroes walk in
	one after another, and then each is sent in with ClassManager.Enter.

	Solo players are a party of one: READY opens the portal for just them.

	Each seated player has one of four seats around the brazier; they can move
	to another (swapping with whoever is there) and change class without
	leaving the fire.

	Remotes: CampfireState (server → the party), CampfireAction (client →
	server: ready / class / seat / leave).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClassData = require(Shared:WaitForChild("ClassData"))

local ClassManager = require(script.Parent:WaitForChild("ClassManager"))
local PartyManager = require(script.Parent:WaitForChild("PartyManager"))

local CampfireManager = {}

-- Portal timing (sent to clients so both sides agree).
local LEAD = 0.3      -- seconds between the last READY and the portal opening
local OPEN = 1.1      -- the portal tears open
local STAGGER = 0.5   -- between heroes stepping in
local WALK = 1.9      -- one hero standing up and walking in
local FLARE = 0.6     -- the portal flares before everyone is sent in

local SEATS = 4 -- places around the brazier (the client lays them out)

type Seat = { classId: string, ready: boolean, seat: number }
local seated: { [Player]: Seat } = {}
local launching: { [Player]: boolean } = {}

-- Party members still in the lobby (members already in a run don't count).
local function group(player: Player): { Player }
	local out: { Player } = {}
	for _, m in ipairs(PartyManager.Members(player)) do
		if m.Parent and m:GetAttribute("InLobby") ~= false then table.insert(out, m) end
	end
	return out
end

-- Everyone seated in `list` on a different seat (two groups merging can
-- bring two players with the same seat; the later one moves up).
local function settleSeats(list: { Player })
	local used: { [number]: boolean } = {}
	for _, m in ipairs(list) do
		local s = seated[m]
		if s then
			if used[s.seat] or s.seat < 1 or s.seat > SEATS then
				for i = 1, SEATS do
					if not used[i] then
						s.seat = i
						break
					end
				end
			end
			used[s.seat] = true
		end
	end
end

-- The lowest seat nobody in `player`'s group is on.
local function freeSeat(player: Player): number
	local used: { [number]: boolean } = {}
	for _, m in ipairs(group(player)) do
		local s = seated[m]
		if s and m ~= player then used[s.seat] = true end
	end
	for i = 1, SEATS do
		if not used[i] then return i end
	end
	return 1
end

local function sync(player: Player, portalAt: number?)
	local list = group(player)
	settleSeats(list)
	local members = {}
	for _, m in ipairs(list) do
		local s = seated[m]
		table.insert(members, {
			userId = m.UserId,
			name = m.DisplayName,
			level = m:GetAttribute("AccountLevel") or 1,
			classId = if s then s.classId else nil,
			seated = s ~= nil,
			seat = if s then s.seat else nil,
			ready = s ~= nil and s.ready,
		})
	end
	local payload = { members = members, portalAt = portalAt, open = OPEN, stagger = STAGGER, walk = WALK }
	for _, m in ipairs(list) do
		Network.GetRemoteEvent(Network.Remotes.CampfireState):FireClient(m, payload)
	end
end

-- Everyone seated and ready → open the portal, then send them all in.
local function tryLaunch(player: Player)
	local list = group(player)
	if #list == 0 then return end
	for _, m in ipairs(list) do
		local s = seated[m]
		if not s or not s.ready or launching[m] then return end
	end
	for _, m in ipairs(list) do launching[m] = true end
	local portalAt = Workspace:GetServerTimeNow() + LEAD
	sync(player, portalAt)
	task.delay(LEAD + OPEN + STAGGER * (#list - 1) + WALK + FLARE, function()
		for _, m in ipairs(list) do
			local s = seated[m]
			seated[m] = nil
			launching[m] = nil
			if m.Parent then
				m:SetAttribute("AtCampfire", nil)
				if s then ClassManager.Enter(m, s.classId) end
			end
		end
	end)
end

local function leave(player: Player)
	if launching[player] then return end
	seated[player] = nil
	player:SetAttribute("AtCampfire", nil)
	if player.Parent then sync(player) end
end

local function onAction(player: Player, payload: any)
	if typeof(payload) ~= "table" then return end
	if payload.kind == "ready" and typeof(payload.value) == "boolean" then
		local s = seated[player]
		if not s or launching[player] then return end
		s.ready = payload.value
		sync(player)
		if s.ready then tryLaunch(player) end
	elseif payload.kind == "class" and typeof(payload.classId) == "string" then
		-- Change class without leaving the fire (it un-readies you).
		local s = seated[player]
		if not s or launching[player] or not ClassManager.SetClass(player, payload.classId) then return end
		s.classId = payload.classId
		s.ready = false
		sync(player)
	elseif payload.kind == "seat" and typeof(payload.seat) == "number" then
		-- Move to another seat; whoever sits there takes yours.
		local s = seated[player]
		local want = math.floor(payload.seat)
		if not s or launching[player] or want < 1 or want > SEATS or want == s.seat then return end
		for _, m in ipairs(group(player)) do
			local o = seated[m]
			if m ~= player and o and o.seat == want then
				if launching[m] then return end
				o.seat = s.seat
			end
		end
		s.seat = want
		sync(player)
	elseif payload.kind == "leave" then
		leave(player)
	elseif payload.kind == "request" then
		sync(player)
	end
end

function CampfireManager.Init()
	-- Confirming a class takes a seat at the campfire instead of entering.
	ClassManager.SetGate(function(player: Player, classId: string): boolean
		if launching[player] or not ClassData.GetClass(classId) then return false end
		local prev = seated[player]
		seated[player] = { classId = classId, ready = false, seat = if prev then prev.seat else freeSeat(player) }
		player:SetAttribute("AtCampfire", true)
		sync(player)
		return true
	end)
	Network.GetRemoteEvent(Network.Remotes.CampfireAction).OnServerEvent:Connect(onAction)
	-- Party changes reshuffle who sits together.
	PartyManager.OnChanged(function(players: { Player })
		for _, p in ipairs(players) do
			if p.Parent then sync(p) end
		end
	end)
	-- Coming back from a run to the menu: no longer seated.
	local function watch(p: Player)
		p:GetAttributeChangedSignal("InLobby"):Connect(function()
			if p:GetAttribute("InLobby") == false then
				seated[p] = nil
				launching[p] = nil
			end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		local others = group(p)
		seated[p] = nil
		launching[p] = nil
		task.defer(function()
			for _, o in ipairs(others) do
				if o ~= p and o.Parent then sync(o) end
			end
		end)
	end)
	print("[CampfireManager] initialized.")
end

return CampfireManager
