--!strict
--[[
	PartyManager.luau
	Co-op parties (up to MAX_PARTY players in the same server).

	  • A player invites friends from the Co-op screen. Roblox friend invites
	    carry the leader's UserId as launch data, so a friend who accepts joins
	    this server and lands straight in the leader's party.
	  • Players already in the server can be invited directly; they get an
	    Accept / Decline prompt.
	  • Everything a party member earns as XP is shared with every other member
	    who is in the dungeon (see MobManager → PartyManager.XPRecipients).

	Remotes: PartyState (server → client), PartyAction (client → server),
	PartyInvite (server → invited client).
--]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))

local PartyManager = {}

local MAX_PARTY = 4
local INVITE_TTL = 60 -- seconds an in-server invite stays valid

type Party = { leader: Player, members: { Player } }

local partyOf: { [Player]: Party } = {}
-- invites[target][leader] = time sent
local invites: { [Player]: { [Player]: number } } = {}

local function members(player: Player): { Player }
	local party = partyOf[player]
	return if party then party.members else { player }
end
PartyManager.Members = members

-- Listeners told which players' party just changed (CampfireManager).
local changedListeners: { (players: { Player }) -> () } = {}
function PartyManager.OnChanged(cb: (players: { Player }) -> ())
	table.insert(changedListeners, cb)
end
local function changed(players: { Player })
	for _, cb in ipairs(changedListeners) do task.spawn(cb, table.clone(players)) end
end

local function syncParty(party: Party?)
	local list = if party then party.members else {}
	local payload = { leader = party and party.leader.UserId or nil, members = {} }
	for _, m in ipairs(list) do
		table.insert(payload.members, { userId = m.UserId, name = m.DisplayName })
	end
	for _, m in ipairs(list) do
		Network.GetRemoteEvent(Network.Remotes.PartyState):FireClient(m, payload)
	end
	changed(list)
end

local function syncSolo(player: Player)
	Network.GetRemoteEvent(Network.Remotes.PartyState):FireClient(player, {
		leader = nil,
		members = { { userId = player.UserId, name = player.DisplayName } },
	})
	changed({ player })
end

local function leave(player: Player)
	local party = partyOf[player]
	if not party then return end
	partyOf[player] = nil
	local i = table.find(party.members, player)
	if i then table.remove(party.members, i) end
	if #party.members <= 1 then
		-- A party of one is just a solo player again.
		for _, m in ipairs(party.members) do
			partyOf[m] = nil
			syncSolo(m)
		end
	else
		if party.leader == player then party.leader = party.members[1] end
		syncParty(party)
	end
	if player.Parent then syncSolo(player) end
end

local function join(player: Player, leader: Player): boolean
	if player == leader then return false end
	local party = partyOf[leader]
	if party and #party.members >= MAX_PARTY then return false end
	if partyOf[player] then leave(player) end
	if not party then
		party = { leader = leader, members = { leader } }
		partyOf[leader] = party
	end
	local p = party :: Party
	table.insert(p.members, player)
	partyOf[player] = p
	syncParty(p)
	return true
end

-- Everyone who should get XP when these players earn it: the players
-- themselves plus their party members who are in the dungeon (not the lobby).
function PartyManager.XPRecipients(earners: { Player }): { Player }
	local out: { Player } = {}
	local seen: { [Player]: boolean } = {}
	for _, p in ipairs(earners) do
		for _, m in ipairs(members(p)) do
			if not seen[m] and m.Parent and m:GetAttribute("InLobby") ~= true then
				seen[m] = true
				table.insert(out, m)
			end
		end
	end
	return out
end

local function onAction(player: Player, payload: any)
	if typeof(payload) ~= "table" then return end
	local kind = payload.kind
	if kind == "invite" and typeof(payload.userId) == "number" then
		-- In-server invite: only the leader (or a solo player) invites.
		local party = partyOf[player]
		if party and party.leader ~= player then return end
		if party and #party.members >= MAX_PARTY then return end
		local target = Players:GetPlayerByUserId(payload.userId)
		if not target or target == player or table.find(members(player), target) then return end
		invites[target] = invites[target] or {}
		invites[target][player] = os.clock()
		Network.GetRemoteEvent(Network.Remotes.PartyInvite):FireClient(target, { fromUserId = player.UserId, fromName = player.DisplayName })
	elseif kind == "accept" and typeof(payload.userId) == "number" then
		local leader = Players:GetPlayerByUserId(payload.userId)
		local sent = leader and invites[player] and invites[player][leader]
		if not leader or not sent or os.clock() - sent > INVITE_TTL then return end
		invites[player][leader] = nil
		join(player, leader)
	elseif kind == "decline" and typeof(payload.userId) == "number" then
		local leader = Players:GetPlayerByUserId(payload.userId)
		if leader and invites[player] then invites[player][leader] = nil end
	elseif kind == "leave" then
		leave(player)
	elseif kind == "kick" and typeof(payload.userId) == "number" then
		local party = partyOf[player]
		local target = Players:GetPlayerByUserId(payload.userId)
		if party and party.leader == player and target and partyOf[target] == party then
			leave(target)
		end
	elseif kind == "request" then
		local party = partyOf[player]
		if party then syncParty(party) else syncSolo(player) end
	end
end

-- A friend who joined through a Co-op invite joins the inviter's party.
local function onPlayerAdded(player: Player)
	syncSolo(player)
	local ok, joinData = pcall(function() return player:GetJoinData() end)
	local launch = ok and joinData and joinData.LaunchData
	if typeof(launch) ~= "string" or launch == "" then return end
	local decoded = nil
	pcall(function() decoded = HttpService:JSONDecode(launch) end)
	local leaderId = if typeof(decoded) == "table" then tonumber((decoded :: any).party) else nil
	local leader = leaderId and Players:GetPlayerByUserId(leaderId)
	if leader then join(player, leader) end
end

function PartyManager.Init()
	Network.GetRemoteEvent(Network.Remotes.PartyAction).OnServerEvent:Connect(onAction)
	for _, p in ipairs(Players:GetPlayers()) do task.spawn(onPlayerAdded, p) end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		leave(player)
		invites[player] = nil
		for _, byLeader in pairs(invites) do byLeader[player] = nil end
	end)
	print("[PartyManager] initialized.")
end

return PartyManager
