--!strict
--[[
	GuildManager.luau
	Guilds (rules: GuildData). Guilds live in their own DataStore so they work
	across servers; each player's profile holds the id of their guild.

	  Guilds_v1         "g_<id>" → the guild record (below)
	  GuildNames_v1     lower-cased name → id (names are unique)
	  GuildSeason_<n>   OrderedDataStore: guild id → its points that season

	A guild record: { id, name, tag, leader (userId), officers { [uid] = true },
	members { [uid] = { name, class, joined } }, requests { [uid] = name },
	invites { [uid] = true }, season, points { [uid] = pts } (this season),
	total (this season), lastSeason { season, total, top } }. A record still on
	an older season is rolled over (its points cleared, the old season kept in
	lastSeason) the next time anything writes to it.

	Points: RunStats calls AddRunPoints when a run ends (GuildData.Points).
	Rewards: a player whose guild ranked last season is paid on their first
	login after it ended (souls, tickets, a title for the top 3, a run buff for
	the top 10: BuffOf).
	The podium: Top3() — the leading guilds this season, each with its top
	contributor (refreshed every minute; Changed fires when it moves).

	Client ↔ server: GuildAction (RemoteFunction) { op, ... } → { ok, error?, ... }
	  info / create {name, tag} / request {name} / cancelRequest / accept {userId}
	  / decline {userId} / invite {name} / acceptInvite {guildId} /
	  declineInvite {guildId} / leave / kick {userId} / promote {userId} /
	  demote {userId} / top
	Player attributes: GuildId, GuildName, GuildTag, GuildRole (leader /
	officer / member).
--]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GuildData = require(Shared:WaitForChild("GuildData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local GuildManager = {}

local CACHE_FOR = 20       -- seconds a read guild record is trusted
local TOP_EVERY = 60       -- seconds between podium refreshes
local RANK_PAGES = 4       -- 4 × 50: ranks looked up as deep as 200

-- ── Storage (in memory when DataStores aren't available, e.g. Studio) ─────
local guildStore: DataStore? = nil
local nameStore: DataStore? = nil
do
	local ok = pcall(function()
		guildStore = DataStoreService:GetDataStore("Guilds_v1")
		nameStore = DataStoreService:GetDataStore("GuildNames_v1")
	end)
	if not ok then
		guildStore, nameStore = nil, nil
		warn("[GuildManager] DataStores unavailable: guilds are kept in memory this session")
	end
end
local memory: { [string]: any } = {}
local memoryBoards: { [number]: { [string]: number } } = {}

local function update(store: DataStore?, key: string, fn: (any) -> any): (boolean, any)
	if store then
		local result
		local ok, err = pcall(function()
			result = store:UpdateAsync(key, fn)
		end)
		if not ok then warn("[GuildManager] update", key, err) end
		return ok, result
	end
	local mk = (if store == nameStore then "n:" else "g:") .. key
	local nv = fn(memory[mk])
	if nv ~= nil then memory[mk] = nv end
	return true, memory[mk]
end

local function get(store: DataStore?, key: string): any
	if store then
		local ok, v = pcall(function() return store:GetAsync(key) end)
		return if ok then v else nil
	end
	return memory[(if store == nameStore then "n:" else "g:") .. key]
end

local function board(season: number): OrderedDataStore?
	local ok, s = pcall(function() return DataStoreService:GetOrderedDataStore(`GuildSeason_{season}`) end)
	return if ok and guildStore then s else nil
end

local function setBoard(season: number, id: string, total: number)
	local b = board(season)
	if b then
		pcall(function() b:SetAsync(id, total) end)
	else
		memoryBoards[season] = memoryBoards[season] or {}
		memoryBoards[season][id] = total
	end
end

-- The top `n` guilds of a season: { { id, points } } best first.
local function topOf(season: number, n: number): { { id: string, points: number } }
	local out = {}
	local b = board(season)
	if b then
		local ok, pages = pcall(function() return b:GetSortedAsync(false, math.min(n, 100)) end)
		if not ok or not pages then return out end
		local page = pages:GetCurrentPage()
		for _, e in ipairs(page) do
			table.insert(out, { id = e.key, points = e.value })
			if #out >= n then break end
		end
		return out
	end
	for id, pts in pairs(memoryBoards[season] or {}) do table.insert(out, { id = id, points = pts }) end
	table.sort(out, function(a, b2) return a.points > b2.points end)
	while #out > n do table.remove(out) end
	return out
end

-- A guild's rank in a season (nil: not in the top RANK_PAGES × 50).
local function rankOf(season: number, id: string): number?
	local b = board(season)
	if b then
		local ok, pages = pcall(function() return b:GetSortedAsync(false, 50) end)
		if not ok or not pages then return nil end
		local rank = 0
		for _ = 1, RANK_PAGES do
			for _, e in ipairs(pages:GetCurrentPage()) do
				rank += 1
				if e.key == id then return rank end
			end
			if pages.IsFinished then break end
			local okNext = pcall(function() pages:AdvanceToNextPageAsync() end)
			if not okNext then break end
		end
		return nil
	end
	for i, e in ipairs(topOf(season, 200)) do
		if e.id == id then return i end
	end
	return nil
end

-- ── Guild records ───────────────────────────────────────────────────────────
local cache: { [string]: { data: any, at: number } } = {}

local function season(): number
	return GuildData.SeasonOf(os.time())
end

-- The member who earned the most this season (for the podium / lastSeason).
local function topContributor(g: any): any?
	local best, bestPts = nil, -1
	for uid, pts in pairs(g.points or {}) do
		local m = g.members[uid]
		if m and pts > bestPts then
			best, bestPts = uid, pts
		end
	end
	if not best then return nil end
	local m = g.members[best]
	return { userId = tonumber(best), name = m.name, class = m.class, points = bestPts }
end

-- Bring a record up to this season (it's written back by the caller).
local function rollover(g: any)
	local now = season()
	if g.season ~= now then
		if (g.total or 0) > 0 then
			g.lastSeason = { season = g.season, total = g.total, top = topContributor(g) }
		end
		g.season, g.points, g.total = now, {}, 0
	end
end

local function loadGuild(id: string, fresh: boolean?): any?
	if id == "" then return nil end
	local c = cache[id]
	if c and not fresh and os.clock() - c.at < CACHE_FOR then return c.data end
	local g = get(guildStore, `g_{id}`)
	if g then
		rollover(g)
		cache[id] = { data = g, at = os.clock() }
	end
	return g
end

-- Change a guild atomically; `fn(g)` returns an error string to cancel.
local function editGuild(id: string, fn: (any) -> string?): (boolean, string?)
	local err: string? = nil
	local ok, g = update(guildStore, `g_{id}`, function(g: any)
		if not g then
			err = "That guild no longer exists."
			return nil
		end
		rollover(g)
		err = fn(g)
		if err then return nil end
		return g
	end)
	if not ok then return false, "Couldn't reach the guild records, try again." end
	if err then return false, err end
	if g then cache[id] = { data = g, at = os.clock() } end
	return true, nil
end

local function memberCount(g: any): number
	local n = 0
	for _ in pairs(g.members) do n += 1 end
	return n
end

local function roleOf(g: any, uid: string): string?
	if not g.members[uid] then return nil end
	if tostring(g.leader) == uid then return "leader" end
	if g.officers[uid] then return "officer" end
	return "member"
end

-- ── The player's side ───────────────────────────────────────────────────────
local function profileOf(player: Player): any?
	return PlayerData.Get(player) :: any
end

local function syncAttributes(player: Player)
	local p = profileOf(player)
	local id = p and p.guild or ""
	local g = if id ~= "" then loadGuild(id, true) else nil
	local uid = tostring(player.UserId)
	if id ~= "" and (not g or not g.members[uid]) then
		-- (removed while away, or the guild is gone: the profile follows)
		p.guild = ""
		PlayerData.MarkDirty(player)
		g = nil
	end
	player:SetAttribute("GuildId", if g then g.id else nil)
	player:SetAttribute("GuildName", if g then g.name else nil)
	player:SetAttribute("GuildTag", if g then g.tag else nil)
	player:SetAttribute("GuildRole", if g then roleOf(g, uid) else nil)
end

local function setGuildOf(player: Player, id: string)
	local p = profileOf(player)
	if not p then return end
	p.guild = id
	p.guildInvites = {}
	PlayerData.MarkDirty(player)
	syncAttributes(player)
end

local function onlinePlayer(uid: string): Player?
	return Players:GetPlayerByUserId(tonumber(uid) or 0)
end

-- What the guild screen shows.
local function view(g: any, viewer: Player): any
	local uid = tostring(viewer.UserId)
	local members = {}
	for id, m in pairs(g.members) do
		table.insert(members, { userId = tonumber(id), name = m.name, class = m.class, role = roleOf(g, id),
			points = (g.points or {})[id] or 0, online = onlinePlayer(id) ~= nil })
	end
	table.sort(members, function(a, b) return a.points > b.points end)
	local requests = {}
	local role = roleOf(g, uid)
	if role == "leader" or role == "officer" then
		for id, name in pairs(g.requests or {}) do table.insert(requests, { userId = tonumber(id), name = name }) end
	end
	return { id = g.id, name = g.name, tag = g.tag, role = role, members = members, requests = requests,
		total = g.total or 0, season = g.season, seasonEnds = GuildData.SeasonEnds(g.season),
		maxMembers = GuildData.MAX_MEMBERS, lastSeason = g.lastSeason }
end

-- ── Seasons: the podium, rewards, buffs ─────────────────────────────────────
local top3: { any } = {}
local changed = Instance.new("BindableEvent")
GuildManager.Changed = changed.Event

function GuildManager.Top3(): { any }
	return top3
end

local function refreshTop()
	local list = {}
	for i, e in ipairs(topOf(season(), 3)) do
		local g = loadGuild(e.id, true)
		if g then
			table.insert(list, { rank = i, id = g.id, name = g.name, tag = g.tag, points = g.total or e.points,
				top = topContributor(g) })
		end
	end
	local before = HttpService:JSONEncode(top3)
	top3 = list
	if HttpService:JSONEncode(list) ~= before then changed:Fire(list) end
end

local TITLE_IDS = { t_guild_champion = true, t_guild_vanguard = true }

-- Paid once per season, on the first login after it ends.
local function claimRewards(player: Player)
	local p = profileOf(player)
	if not p or (p.guild or "") == "" then return end
	local last = season() - 1
	if (p.guildClaimed or -1) >= last then return end
	local rank = rankOf(last, p.guild)
	p.guildClaimed = last
	PlayerData.MarkDirty(player)
	if not rank then return end
	local r = GuildData.RewardFor(rank)
	if not r then return end
	pcall(function()
		local TalentManager = require(script.Parent:WaitForChild("TalentManager")) :: any
		TalentManager.AwardSouls(player, r.souls)
	end)
	pcall(function()
		local GachaManager = require(script.Parent:WaitForChild("GachaManager")) :: any
		GachaManager.AwardTickets(player, r.tickets, "guild")
	end)
	if r.title and TITLE_IDS[r.title] then
		p.gear = p.gear or { owned = {}, equipped = {} }
		p.gear.owned[r.title] = math.max(p.gear.owned[r.title] or 0, 1)
	end
	if r.buff then p.guildBuff = { season = season(), mult = r.buff } end
	PlayerData.MarkDirty(player)
	Network.GetRemoteEvent(Network.Remotes.GuildUpdate):FireClient(player, { kind = "reward", rank = rank,
		souls = r.souls, tickets = r.tickets, title = r.title, buff = r.buff })
end

-- The run buff earned last season (0: none): +this share of run souls / XP.
function GuildManager.BuffOf(player: Player): number
	local p = profileOf(player)
	local b = p and p.guildBuff
	if typeof(b) == "table" and b.season == season() then return tonumber(b.mult) or 0 end
	return 0
end

-- ── Points ──────────────────────────────────────────────────────────────────
function GuildManager.AddRunPoints(player: Player, floor: number, bosses: number, elites: number, extracted: boolean)
	local p = profileOf(player)
	local id = p and p.guild or ""
	if id == "" then return end
	local pts = GuildData.Points(floor, bosses, elites, extracted)
	if pts <= 0 then return end
	local uid = tostring(player.UserId)
	local class = player:GetAttribute("SelectedClass")
	task.spawn(function()
		local total = 0
		local ok = editGuild(id, function(g)
			if not g.members[uid] then return "not a member" end
			g.points[uid] = (g.points[uid] or 0) + pts
			g.total = (g.total or 0) + pts
			if typeof(class) == "string" then g.members[uid].class = class end
			g.members[uid].name = player.Name
			total = g.total
			return nil
		end)
		if ok then
			setBoard(season(), id, total)
			Network.GetRemoteEvent(Network.Remotes.GuildUpdate):FireClient(player, { kind = "points", points = pts, total = total })
		end
	end)
end

-- ── Actions ─────────────────────────────────────────────────────────────────
local ACTIONS: { [string]: (Player, any) -> any } = {}

ACTIONS.info = function(player)
	local p = profileOf(player)
	local id = p and p.guild or ""
	local g = if id ~= "" then loadGuild(id, true) else nil
	local invites = {}
	for _, gid in ipairs(p and p.guildInvites or {}) do
		local ig = loadGuild(gid)
		if ig then table.insert(invites, { id = ig.id, name = ig.name, tag = ig.tag, members = memberCount(ig) }) end
	end
	return { ok = true, guild = if g then view(g, player) else nil, invites = invites,
		pending = if p and p.guildRequest ~= "" then p.guildRequest else nil, cost = GuildData.CREATE_COST,
		souls = p and p.souls or 0 }
end

ACTIONS.create = function(player, msg)
	local p = profileOf(player)
	if not p then return { ok = false, error = "Your profile hasn't loaded yet." } end
	if (p.guild or "") ~= "" then return { ok = false, error = "Leave your guild first." } end
	local name = typeof(msg.name) == "string" and string.gsub(msg.name, "%s+", " ") or ""
	local tag = typeof(msg.tag) == "string" and string.upper(msg.tag) or ""
	if not GuildData.ValidName(name) then return { ok = false, error = "Names are 3–20 letters, digits and spaces." } end
	if not GuildData.ValidTag(tag) then return { ok = false, error = "Tags are 2–4 letters or digits." } end
	if (p.souls or 0) < GuildData.CREATE_COST then
		return { ok = false, error = `It costs {GuildData.CREATE_COST} souls to found a guild.` }
	end
	local okText, filtered = pcall(function()
		local TextService = game:GetService("TextService")
		local r = TextService:FilterStringAsync(name .. " [" .. tag .. "]", player.UserId)
		return r:GetNonChatStringForBroadcastAsync()
	end)
	if okText and filtered ~= name .. " [" .. tag .. "]" then return { ok = false, error = "That name isn't allowed." } end
	local id = HttpService:GenerateGUID(false):sub(1, 8)
	-- (claim the name first: unique across every server)
	local taken = false
	local okName = update(nameStore, string.lower(name), function(old: any)
		if old ~= nil then
			taken = true
			return nil
		end
		return id
	end)
	if not okName then return { ok = false, error = "Couldn't reach the guild records, try again." } end
	if taken then return { ok = false, error = "A guild already has that name." } end
	local uid = tostring(player.UserId)
	local g = { id = id, name = name, tag = tag, leader = player.UserId, officers = {},
		members = { [uid] = { name = player.Name, class = player:GetAttribute("SelectedClass"), joined = os.time() } },
		requests = {}, invites = {}, season = season(), points = {}, total = 0, created = os.time() }
	update(guildStore, `g_{id}`, function() return g end)
	cache[id] = { data = g, at = os.clock() }
	p.souls -= GuildData.CREATE_COST
	p.guildClaimed = season() - 1 -- (no back-pay for seasons before it existed)
	pcall(function()
		local TalentManager = require(script.Parent:WaitForChild("TalentManager")) :: any
		TalentManager.Sync(player) -- (the souls shown)
	end)
	setGuildOf(player, id)
	return ACTIONS.info(player)
end

ACTIONS.request = function(player, msg)
	local p = profileOf(player)
	if not p or (p.guild or "") ~= "" then return { ok = false, error = "Leave your guild first." } end
	local name = typeof(msg.name) == "string" and string.lower(msg.name) or ""
	local id = get(nameStore, name)
	if typeof(id) ~= "string" then return { ok = false, error = "No guild by that name." } end
	local uid = tostring(player.UserId)
	local ok, err = editGuild(id, function(g)
		if memberCount(g) >= GuildData.MAX_MEMBERS then return "That guild is full." end
		g.requests = g.requests or {}
		g.requests[uid] = player.Name
		return nil
	end)
	if not ok then return { ok = false, error = err } end
	p.guildRequest = id
	PlayerData.MarkDirty(player)
	return ACTIONS.info(player)
end

ACTIONS.cancelRequest = function(player)
	local p = profileOf(player)
	local id = p and p.guildRequest
	if typeof(id) == "string" and id ~= "" then
		local uid = tostring(player.UserId)
		editGuild(id, function(g)
			if g.requests then g.requests[uid] = nil end
			return nil
		end)
		p.guildRequest = ""
		PlayerData.MarkDirty(player)
	end
	return ACTIONS.info(player)
end

-- Officers and the leader.
local function staffGuild(player: Player): (string?, string?)
	local p = profileOf(player)
	local id = p and p.guild or ""
	if id == "" then return nil, "You're not in a guild." end
	local g = loadGuild(id)
	local role = g and roleOf(g, tostring(player.UserId))
	if role ~= "leader" and role ~= "officer" then return nil, "Only the leader or an officer can do that." end
	return id, nil
end

local function addMember(id: string, uid: string, name: string, class: any): (boolean, string?)
	return editGuild(id, function(g)
		if g.members[uid] then return nil end
		if memberCount(g) >= GuildData.MAX_MEMBERS then return "The guild is full." end
		g.members[uid] = { name = name, class = class, joined = os.time() }
		if g.requests then g.requests[uid] = nil end
		if g.invites then g.invites[uid] = nil end
		return nil
	end)
end

ACTIONS.accept = function(player, msg)
	local id, err = staffGuild(player)
	if not id then return { ok = false, error = err } end
	local uid = tostring(tonumber(msg.userId) or 0)
	local g = loadGuild(id, true)
	local name = g and g.requests and g.requests[uid]
	if not name then return { ok = false, error = "That request is gone." } end
	local ok, e2 = addMember(id, uid, name, nil)
	if not ok then return { ok = false, error = e2 } end
	local who = onlinePlayer(uid)
	if who then
		local wp = profileOf(who)
		if wp then wp.guildRequest = "" end
		setGuildOf(who, id)
		Network.GetRemoteEvent(Network.Remotes.GuildUpdate):FireClient(who, { kind = "joined", name = g.name })
	end
	-- (offline: their profile picks the guild up next login, see onLoaded)
	return ACTIONS.info(player)
end

ACTIONS.decline = function(player, msg)
	local id, err = staffGuild(player)
	if not id then return { ok = false, error = err } end
	local uid = tostring(tonumber(msg.userId) or 0)
	editGuild(id, function(g)
		if g.requests then g.requests[uid] = nil end
		return nil
	end)
	return ACTIONS.info(player)
end

ACTIONS.invite = function(player, msg)
	local id, err = staffGuild(player)
	if not id then return { ok = false, error = err } end
	local target = typeof(msg.name) == "string" and Players:FindFirstChild(msg.name)
	if not (target and target:IsA("Player")) then return { ok = false, error = "They need to be in this server to invite them." } end
	local tp = profileOf(target)
	if not tp then return { ok = false, error = "Their profile hasn't loaded yet." } end
	if (tp.guild or "") ~= "" then return { ok = false, error = "They're already in a guild." } end
	local uid = tostring(target.UserId)
	editGuild(id, function(g)
		g.invites = g.invites or {}
		g.invites[uid] = true
		return nil
	end)
	tp.guildInvites = tp.guildInvites or {}
	if not table.find(tp.guildInvites, id) then table.insert(tp.guildInvites, id) end
	PlayerData.MarkDirty(target)
	local g = loadGuild(id)
	Network.GetRemoteEvent(Network.Remotes.GuildUpdate):FireClient(target, { kind = "invited", id = id, name = g and g.name, from = player.Name })
	return ACTIONS.info(player)
end

ACTIONS.acceptInvite = function(player, msg)
	local p = profileOf(player)
	if not p or (p.guild or "") ~= "" then return { ok = false, error = "Leave your guild first." } end
	local id = typeof(msg.guildId) == "string" and msg.guildId or ""
	if not table.find(p.guildInvites or {}, id) then return { ok = false, error = "That invite is gone." } end
	local g = loadGuild(id, true)
	if not g or not (g.invites or {})[tostring(player.UserId)] then return { ok = false, error = "That invite is gone." } end
	local ok, err = addMember(id, tostring(player.UserId), player.Name, player:GetAttribute("SelectedClass"))
	if not ok then return { ok = false, error = err } end
	if (p.guildRequest or "") ~= "" then ACTIONS.cancelRequest(player) end
	setGuildOf(player, id)
	return ACTIONS.info(player)
end

ACTIONS.declineInvite = function(player, msg)
	local p = profileOf(player)
	if p and p.guildInvites then
		local i = table.find(p.guildInvites, msg.guildId)
		if i then table.remove(p.guildInvites, i) end
		PlayerData.MarkDirty(player)
	end
	return ACTIONS.info(player)
end

ACTIONS.leave = function(player)
	local p = profileOf(player)
	local id = p and p.guild or ""
	if id == "" then return { ok = false, error = "You're not in a guild." } end
	local uid = tostring(player.UserId)
	editGuild(id, function(g)
		g.members[uid] = nil
		g.officers[uid] = nil
		if tostring(g.leader) == uid then
			-- (the leadership passes to an officer, else the top contributor,
			-- else anyone; the last one out leaves it empty)
			local heir = next(g.officers)
			if not heir then
				local t = topContributor(g)
				heir = t and tostring(t.userId) or next(g.members)
			end
			g.leader = if heir then tonumber(heir) else 0
			if heir then g.officers[heir] = nil end
		end
		return nil
	end)
	setGuildOf(player, "")
	return ACTIONS.info(player)
end

ACTIONS.kick = function(player, msg)
	local id, err = staffGuild(player)
	if not id then return { ok = false, error = err } end
	local me, uid = tostring(player.UserId), tostring(tonumber(msg.userId) or 0)
	local ok, e2 = editGuild(id, function(g)
		local mine, theirs = roleOf(g, me), roleOf(g, uid)
		if not theirs then return "They're not in the guild." end
		if theirs == "leader" or (theirs == "officer" and mine ~= "leader") or uid == me then return "You can't remove them." end
		g.members[uid] = nil
		g.officers[uid] = nil
		return nil
	end)
	if not ok then return { ok = false, error = e2 } end
	local who = onlinePlayer(uid)
	if who then
		setGuildOf(who, "")
		Network.GetRemoteEvent(Network.Remotes.GuildUpdate):FireClient(who, { kind = "kicked" })
	end
	return ACTIONS.info(player)
end

local function setOfficer(player: Player, msg: any, on: boolean): any
	local p = profileOf(player)
	local id = p and p.guild or ""
	local me, uid = tostring(player.UserId), tostring(tonumber(msg.userId) or 0)
	local ok, err = editGuild(id, function(g)
		if roleOf(g, me) ~= "leader" then return "Only the leader can do that." end
		if not g.members[uid] or uid == me then return "Pick another member." end
		if on then
			local n = 0
			for _ in pairs(g.officers) do n += 1 end
			if n >= GuildData.MAX_OFFICERS then return `A guild has at most {GuildData.MAX_OFFICERS} officers.` end
			g.officers[uid] = true
		else
			g.officers[uid] = nil
		end
		return nil
	end)
	if not ok then return { ok = false, error = err } end
	local who = onlinePlayer(uid)
	if who then syncAttributes(who) end
	return ACTIONS.info(player)
end
ACTIONS.promote = function(player, msg) return setOfficer(player, msg, true) end
ACTIONS.demote = function(player, msg) return setOfficer(player, msg, false) end

ACTIONS.top = function(_player)
	local list = {}
	for i, e in ipairs(topOf(season(), 10)) do
		local g = loadGuild(e.id)
		if g then table.insert(list, { rank = i, name = g.name, tag = g.tag, points = e.points, members = memberCount(g) }) end
	end
	return { ok = true, top = list, seasonEnds = GuildData.SeasonEnds(season()) }
end

-- ── Init ────────────────────────────────────────────────────────────────────
local busy: { [Player]: boolean } = {}

local function onLoaded(player: Player, p: any)
	if typeof(p.guild) ~= "string" then p.guild = "" end
	-- (an offline request that was accepted: the guild has them now)
	if p.guild == "" and typeof(p.guildRequest) == "string" and p.guildRequest ~= "" then
		local g = loadGuild(p.guildRequest, true)
		if g and g.members[tostring(player.UserId)] then
			p.guild = g.id
			p.guildRequest = ""
			PlayerData.MarkDirty(player)
		end
	end
	syncAttributes(player)
	task.spawn(claimRewards, player)
end

function GuildManager.Init()
	Network.GetRemoteEvent(Network.Remotes.GuildUpdate)
	local rf = Network.GetRemoteFunction(Network.Functions.GuildAction)
	rf.OnServerInvoke = function(player: Player, msg: any)
		if typeof(msg) ~= "table" or typeof(msg.op) ~= "string" then return { ok = false, error = "Bad request." } end
		local fn = ACTIONS[msg.op]
		if not fn then return { ok = false, error = "Bad request." } end
		if busy[player] then return { ok = false, error = "One moment…" } end
		busy[player] = true
		local ok, result = pcall(fn, player, msg)
		busy[player] = nil
		if not ok then
			warn("[GuildManager]", msg.op, result)
			return { ok = false, error = "Something went wrong, try again." }
		end
		return result
	end
	PlayerData.OnLoaded(onLoaded)
	for _, pl in ipairs(Players:GetPlayers()) do
		local prof = PlayerData.Get(pl)
		if prof then task.spawn(onLoaded, pl, prof) end
	end
	Players.PlayerRemoving:Connect(function(p) busy[p] = nil end)
	task.spawn(function()
		while true do
			local ok, err = pcall(refreshTop)
			if not ok then warn("[GuildManager] podium", err) end
			task.wait(TOP_EVERY)
		end
	end)
end

return GuildManager
