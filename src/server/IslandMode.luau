--!strict
--[[
	IslandMode.luau
	The Forgotten Isle's run (MapData "isle"): what happens on the island once
	it's built (IslandGenerator) and while its party is on it.

	  IslandMode.Start(runId)   the island is up: start its run
	  IslandMode.Stop(runId)    the run is over (RunManager tears it down)
	  IslandMode.Of(runId)      its state (nil if it isn't an island run)
	  IslandMode.Notify(runId, msg, only?)   a message on the island HUD
	  IslandMode.Mods(runId)    the run's live modifiers (events: IslandEvents)

	Survival (IslandConfig.Survival): the dead never stop coming. Every
	SPAWN_TICK the island tops its population back up toward a target that
	grows with the wave (one every WAVE_SECONDS of the run's clock) and with
	the party's size, raising them in small batches from spawn sources
	(IslandGenerator) far enough from every player not to land on anyone,
	near enough to someone to find them. Which kinds rise depends on the wave
	and on the source's region (IslandConfig.Enemies, its danger); elites come
	more often as the waves climb, and every BEHEMOTH_EVERY waves a Cursed
	Behemoth. Enemies left far from everyone are taken back. Nothing spawns
	while the run is paused for a tome choice, and the ritual's arena is left
	clear while its boss fights.

	Their health and damage climb with the run's Threat tier (MobManager,
	DifficultyManager: as in any dungeon); kills give XP, gold and drops the
	usual way (MobManager), so levelling and tome choices are the run's own
	(PlayerStats).

	Discovery: coming within reach of a landmark (IslandConfig.Pois) names it
	on screen and gives its XP, once per player.

	Levels: the island's own (a dungeon levels on its rooms; here there are
	none). Every XP award (kills, discoveries, the ritual: PlayerStats.OnXP,
	after the Fortune Tome's xpGain) fills the run's bar; each level is a tome
	choice the usual way (PlayerStats.LevelUp: three tomes, the run paused
	while they choose). Shown as IslandLevel / IslandXP / IslandXPNext.

	Asks from the island HUD come in on one remote (IslandAction), each
	routed to the system that owns it (IslandMode.Handle) only for a player
	on an island run, and only so many a second.

	Run attributes (RunScope): Island (true), IslandStart, IslandWave,
	IslandAlive (enemies out). (Each client works out which region it's in
	itself: IslandHUD.)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RunScope = require(Shared:WaitForChild("RunScope"))
local Network = require(Shared:WaitForChild("Network"))
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local IslandGenerator = require(script.Parent:WaitForChild("IslandGenerator"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))
require(script.Parent:WaitForChild("IslandMobs")) -- (registers the biomes' enemies into MobKinds)
local DifficultyManager = require(script.Parent:WaitForChild("DifficultyManager"))

local IslandMode = {}

local S = IslandConfig.Survival

export type Mods = { spawn: number, xp: number, loot: number, damage: number, speed: number }
type Enemy = { model: Model, archetype: string, behemoth: boolean }
type Level = { level: number, xp: number }
export type RunState = {
	runId: string,
	started: number,
	alive: boolean,
	wave: number,
	enemies: { [Model]: Enemy },
	behemothWave: number,
	discovered: { [Player]: { [string]: boolean } },
	mods: Mods,
	arena: { center: Vector3, radius: number }?, -- the ritual's arena while its boss fights (IslandRitual)
	rng: Random,
	levels: { [Player]: Level },
}

local runs: { [string]: RunState } = {}

local function members(runId: string): { Player }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("RunId") == runId and p:GetAttribute("InLobby") == false then table.insert(out, p) end
	end
	return out
end
IslandMode.Members = members

local function rootOf(p: Player): BasePart?
	local c = p.Character
	return c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function living(runId: string): { { player: Player, root: BasePart } }
	local out = {}
	for _, p in ipairs(members(runId)) do
		local c = p.Character
		local hum = c and c:FindFirstChildOfClass("Humanoid")
		local root = rootOf(p)
		if hum and root and hum.Health > 0 and p:GetAttribute("IsDead") ~= true then table.insert(out, { player = p, root = root }) end
	end
	return out
end
IslandMode.Living = living

-- A message on the island's HUD (IslandHUD): to one player, or the whole run.
function IslandMode.Notify(runId: string, msg: { [string]: any }, only: Player?)
	local remote = Network.GetRemoteEvent(Network.Remotes.IslandEvent)
	if only then
		remote:FireClient(only, msg)
		return
	end
	for _, p in ipairs(members(runId)) do remote:FireClient(p, msg) end
end

-- ── Discovery ───────────────────────────────────────────────────────────────
local function discoverStep(st: RunState)
	local island = IslandGenerator.Get(st.runId)
	if not island then return end
	local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
	for _, p in ipairs(members(st.runId)) do
		local root = rootOf(p)
		if not root then continue end
		local seen = st.discovered[p] or {}
		st.discovered[p] = seen
		-- (the region they're in, for their HUD)
		local region = island.RegionAt(root.Position)
		if p:GetAttribute("IslandRegion") ~= region then p:SetAttribute("IslandRegion", region) end
		for _, poi in ipairs(island.pois) do
			if not seen[poi.id] and (root.Position - poi.pos).Magnitude <= poi.radius then
				seen[poi.id] = true
				if poi.xp > 0 then pcall(PlayerStats.AwardXP, p, poi.xp) end
				IslandMode.Notify(st.runId, { kind = "discover", name = poi.name, region = poi.region, xp = poi.xp }, p)
			end
		end
	end
end

-- The XP the island's level `level` asks for.
local function xpFor(level: number): number
	return math.floor(S.LEVEL_XP * S.LEVEL_GROWTH ^ (level - 1))
end

-- ── Survival ────────────────────────────────────────────────────────────────
-- Someone just arrived: their level bar starts at 1.
local function arrivals(st: RunState)
	for _, p in ipairs(members(st.runId)) do
		if not st.levels[p] then
			st.levels[p] = { level = 1, xp = 0 }
			p:SetAttribute("IslandLevel", 1)
			p:SetAttribute("IslandXP", 0)
			p:SetAttribute("IslandXPNext", xpFor(1))
		end
	end
end

local function pickArchetype(st: RunState, danger: number, region: string?): IslandConfig.Archetype?
	local total, pool = 0, {}
	for _, a in ipairs(IslandConfig.Enemies) do
		-- (each biome raises its own)
		if a.regions and region and not table.find(a.regions, region) then continue end
		if a.from <= st.wave and (a.minDanger or 1) <= danger then
			-- (tougher kinds come more often where the island is more dangerous)
			local w = a.weight * (if (a.minDanger or 1) > 1 then 1 + 0.25 * (danger - 1) else 1)
			total += w
			table.insert(pool, { a = a, w = w })
		end
	end
	if total <= 0 then return nil end
	local roll = st.rng:NextNumber(0, total)
	for _, e in ipairs(pool) do
		roll -= e.w
		if roll <= 0 then return e.a end
	end
	return pool[#pool].a
end

local function groundUnder(island: any, pos: Vector3): Vector3
	local y = island.GroundAt(pos + Vector3.new(0, 8, 0))
	return Vector3.new(pos.X, (y or pos.Y) + 3, pos.Z)
end

-- One enemy (or a Behemoth) out of a source.
local function raise(st: RunState, island: any, src: any, archetype: any, behemoth: boolean, n: number)
	local danger = (IslandConfig.Region(src.region) :: any).danger
	local healthMult = (1 + S.HEALTH_PER_EXTRA_PLAYER * math.max(0, n - 1)) * (1 + S.DANGER_HEALTH * (danger - 1))
	local xpMult = 1 + S.DANGER_HEALTH * 1.5 * (danger - 1)
	local eliteChance = math.min(S.ELITE_BASE + S.ELITE_PER_WAVE * st.wave, S.ELITE_MAX)
	local elite = archetype.elite == true or (not behemoth and st.rng:NextNumber() < eliteChance)
	local off = Vector3.new(st.rng:NextNumber(-5, 5), 0, st.rng:NextNumber(-5, 5))
	local at = groundUnder(island, src.pos + off)
	local B = IslandConfig.Behemoth
	local runId = st.runId
	local model = MobManager.Spawn({
		kind = archetype.kind,
		cf = CFrame.new(at),
		runId = st.runId,
		elite = elite,
		name = if behemoth then "☠ " .. B.name elseif elite then "Elite " .. archetype.name else archetype.name,
		healthMult = healthMult * (if behemoth then B.health else 1),
		damageMult = st.mods.damage * (if behemoth then B.damage else 1) * (1 + (S.DANGER_DAMAGE or 0) * (danger - 1)),
		xpMult = xpMult * st.mods.xp * (if behemoth then B.xp else 1),
		scale = if behemoth then B.scale else nil,
		-- (the island's dead hunt: they notice you from much further than a
		-- dungeon's, and a Blood Moon makes them quicker)
		attrs = { AggroRange = S.AGGRO, IslandEnemy = archetype.id, Behemoth = behemoth or nil,
			WalkSpeed = if st.mods.speed ~= 1 then st.mods.speed else nil },
		-- an elite (always a Behemoth) may leave an Elite Chest where it falls
		onDied = if elite or behemoth then function(m: Model)
			local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			local chance = if behemoth then 1 else IslandConfig.Loot.eliteChestChance * st.mods.loot
			if root and st.rng:NextNumber() < chance then
				local chests = script.Parent:FindFirstChild("IslandChests")
				if chests then pcall(function() (require(chests) :: any).DropElite(runId, root.Position) end) end
			end
		end else nil,
	})
	if not model then return end
	st.enemies[model] = { model = model, archetype = archetype.id, behemoth = behemoth }
end

local function sourcesFor(st: RunState, island: any, people: { { player: Player, root: BasePart } }): { any }
	local anchor = people[st.rng:NextInteger(1, #people)].root.Position
	local out = {}
	for _, src in ipairs(island.sources) do
		if src.gone then continue end
		local d = (src.pos - anchor).Magnitude
		if d < S.SPAWN_MIN or d > S.SPAWN_MAX then continue end
		local clear = true
		for _, l in ipairs(people) do
			if (src.pos - l.root.Position).Magnitude < S.SPAWN_MIN then
				clear = false
				break
			end
		end
		-- (the ritual's arena stays the boss's while it fights)
		if clear and st.arena and (src.pos - st.arena.center).Magnitude < st.arena.radius + 30 then clear = false end
		if clear then table.insert(out, src) end
	end
	return out
end

local function spawnStep(st: RunState)
	local island = IslandGenerator.Get(st.runId)
	if not island then return end
	local people = living(st.runId)
	arrivals(st)
	-- the count, and the ones too far from anyone (taken back, no reward)
	local alive = 0
	for model, e in pairs(st.enemies) do
		local hum = model:FindFirstChildOfClass("Humanoid")
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not model.Parent or not hum or hum.Health <= 0 or not root then
			st.enemies[model] = nil
			continue
		end
		local near = false
		for _, l in ipairs(people) do
			if (l.root.Position - root.Position).Magnitude < S.DESPAWN then
				near = true
				break
			end
		end
		if not near and #people > 0 and not e.behemoth then
			st.enemies[model] = nil
			model:Destroy()
			continue
		end
		alive += 1
	end
	RunScope.Set(st.runId, "IslandAlive", alive)

	-- the wave, from the run's clock
	local wave = math.floor(DifficultyManager.GetElapsed(st.runId) / S.WAVE_SECONDS) + 1
	if wave ~= st.wave then
		st.wave = wave
		RunScope.Set(st.runId, "IslandWave", wave)
		if wave > 1 then IslandMode.Notify(st.runId, { kind = "wave", wave = wave }) end
	end
	if #people == 0 or RunScope.Get(st.runId, "TomesPaused") == true then return end

	-- a Cursed Behemoth every few waves, from somewhere far off
	if wave >= S.BEHEMOTH_EVERY and wave % S.BEHEMOTH_EVERY == 0 and st.behemothWave ~= wave then
		st.behemothWave = wave
		local srcs = sourcesFor(st, island, people)
		if #srcs > 0 then
			local src = srcs[st.rng:NextInteger(1, #srcs)]
			raise(st, island, src, IslandConfig.Behemoth, true, #people)
			local reg = IslandConfig.Region(src.region)
			IslandMode.Notify(st.runId, { kind = "behemoth", region = reg and reg.name or "the island" })
		end
	end

	-- top the population back up toward the target
	local n = #people
	local target = math.min(S.ALIVE_MAX, S.ALIVE_BASE + S.ALIVE_PER_WAVE * (wave - 1))
	target = math.floor(target * (1 + S.ALIVE_PER_EXTRA_PLAYER * (n - 1)) * st.mods.spawn)
	if st.arena then target = math.floor(target * 0.5) end
	local deficit = target - alive
	local passes = 0
	while deficit > 0 and passes < 3 do
		passes += 1
		local srcs = sourcesFor(st, island, people)
		if #srcs == 0 then break end
		local src = srcs[st.rng:NextInteger(1, #srcs)]
		local danger = (IslandConfig.Region(src.region) :: any).danger
		local batch = math.min(deficit, st.rng:NextInteger(1, S.BATCH))
		for _ = 1, batch do
			local a = pickArchetype(st, danger, src.region)
			if a then raise(st, island, src, a, false, n) end
			deficit -= 1
		end
	end
end

-- ── Levels ──────────────────────────────────────────────────────────────────
local function addXP(player: Player, gain: number)
	local runId = player:GetAttribute("RunId")
	local st = if typeof(runId) == "string" then runs[runId] else nil
	if not st or player:GetAttribute("InLobby") ~= false then return end
	local lv = st.levels[player] or { level = 1, xp = 0 }
	st.levels[player] = lv
	lv.xp += gain
	local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
	local ups = 0
	while lv.xp >= xpFor(lv.level) and ups < 5 do
		lv.xp -= xpFor(lv.level)
		lv.level += 1
		ups += 1
		-- a tome choice, the usual way (the run pauses while they choose)
		pcall(PlayerStats.LevelUp, player, nil)
	end
	player:SetAttribute("IslandLevel", lv.level)
	player:SetAttribute("IslandXP", math.floor(lv.xp))
	player:SetAttribute("IslandXPNext", xpFor(lv.level))
	if ups > 0 then IslandMode.Notify(st.runId, { kind = "level", level = lv.level }, player) end
end

-- ── Asks from the HUD ───────────────────────────────────────────────────────
local handlers: { [string]: (Player, any, RunState) -> () } = {}
function IslandMode.Handle(action: string, fn: (Player, any, RunState) -> ())
	handlers[action] = fn
end
local asks: { [Player]: { n: number, t: number } } = {}

-- ── Run ─────────────────────────────────────────────────────────────────────
function IslandMode.Start(runId: string)
	local st: RunState = {
		runId = runId,
		started = Workspace:GetServerTimeNow(),
		alive = true,
		wave = 1,
		enemies = {},
		behemothWave = 0,
		discovered = {},
		mods = { spawn = 1, xp = 1, loot = 1, damage = 1, speed = 1 },
		arena = nil,
		rng = Random.new(),
		levels = {},
	}
	runs[runId] = st
	for _, p in ipairs(members(runId)) do
		p:SetAttribute("IslandLevel", 1)
		p:SetAttribute("IslandXP", 0)
		p:SetAttribute("IslandXPNext", xpFor(1))
	end
	RunScope.Set(runId, "Island", true)
	RunScope.Set(runId, "IslandStart", st.started)
	RunScope.Set(runId, "IslandWave", 1)
	task.spawn(function()
		while st.alive do
			task.wait(0.5)
			pcall(arrivals, st)
			local ok, err = pcall(discoverStep, st)
			if not ok then warn("[IslandMode] discover:", err) end
		end
	end)
	task.spawn(function()
		task.wait(4) -- (a moment to look round the shore first)
		while st.alive do
			local ok, err = pcall(spawnStep, st)
			if not ok then warn("[IslandMode] spawn:", err) end
			task.wait(S.SPAWN_TICK)
		end
	end)
	-- the island's other systems, as they come up
	for _, name in ipairs({ "IslandChests", "IslandRitual", "IslandEvents" }) do
		local m = script.Parent:FindFirstChild(name)
		if m then
			local ok, err = pcall(function() (require(m) :: any).Start(runId) end)
			if not ok then warn("[IslandMode] " .. name .. ":", err) end
		end
	end
end

function IslandMode.Stop(runId: string)
	local st = runs[runId]
	if not st then return end
	st.alive = false
	runs[runId] = nil
	for model in pairs(st.enemies) do
		if model.Parent then model:Destroy() end
	end
	for _, name in ipairs({ "IslandChests", "IslandRitual", "IslandEvents" }) do
		local m = script.Parent:FindFirstChild(name)
		if m then pcall(function() (require(m) :: any).Stop(runId) end) end
	end
end

-- Every enemy out taken back (the isle they stood on is going).
function IslandMode.ClearEnemies(runId: string)
	local st = runs[runId]
	if not st then return end
	for model in pairs(st.enemies) do
		if model.Parent then model:Destroy() end
	end
	table.clear(st.enemies)
end

function IslandMode.Of(runId: string?): RunState?
	return if runId then runs[runId] else nil
end

function IslandMode.Mods(runId: string?): Mods
	local st = runId and runs[runId]
	return if st then st.mods else { spawn = 1, xp = 1, loot = 1, damage = 1, speed = 1 }
end

-- The ritual's arena, kept clear of the island's spawns while its boss fights
-- (IslandRitual); nil when it's over.
function IslandMode.SetArena(runId: string, center: Vector3?, radius: number?)
	local st = runs[runId]
	if not st then return end
	st.arena = if center then { center = center, radius = radius or 70 } else nil
end

function IslandMode.Init()
	local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
	PlayerStats.OnXP(addXP)
	Network.GetRemoteEvent(Network.Remotes.IslandAction).OnServerEvent:Connect(function(p: Player, msg: any)
		if typeof(msg) ~= "table" or typeof(msg.action) ~= "string" then return end
		local runId = p:GetAttribute("RunId")
		local st = if typeof(runId) == "string" then runs[runId] else nil
		if not st or p:GetAttribute("InLobby") ~= false then return end
		-- (at most 10 asks a second each)
		local now = os.clock()
		local a = asks[p]
		if not a or now - a.t > 1 then
			a = { n = 0, t = now }
			asks[p] = a
		end
		a.n += 1
		if a.n > 10 then return end
		local fn = handlers[msg.action]
		if fn then
			local ok, err = pcall(fn, p, msg, st)
			if not ok then warn("[IslandMode] " .. msg.action .. ":", err) end
		end
	end)
	-- the island's own systems
	for _, name in ipairs({ "EquipmentManager", "EquipmentPerks", "IslandBosses", "IslandRitual" }) do
		local m = script.Parent:FindFirstChild(name)
		if m then
			local ok, err = pcall(function() (require(m) :: any).Init() end)
			if not ok then warn("[IslandMode] " .. name .. ":", err) end
		end
	end
end

Players.PlayerRemoving:Connect(function(p)
	for _, st in pairs(runs) do
		st.discovered[p] = nil
		st.levels[p] = nil
	end
	asks[p] = nil
end)

return IslandMode
