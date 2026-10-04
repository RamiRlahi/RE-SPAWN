--[[
	PlayerData.luau
	The one saved profile per player (DataStore), shared by every progression
	system: talents (TalentManager), the gacha (GachaManager), currencies and
	the collection. Systems read/modify the profile table and call MarkDirty.

	  • Loaded on join (3 attempts), saved after changes (debounced), on leave
	    and at shutdown.
	  • Migrates the old talent-only profile (ClassTalents_v1) on first load.
	  • If DataStores are unavailable (e.g. Studio without API access) it warns
	    and keeps progress in memory for the session.
--]]

local Players = game:GetService("Players")
local DataStoreService = game:GetService("DataStoreService")

local PlayerData = {}

local STORE_NAME = "PlayerProfile_v1"
local LEGACY_TALENT_STORE = "ClassTalents_v1"
local SAVE_DEBOUNCE = 8
local STARTING_SOULS = 3

export type Profile = {
	version: number,
	souls: number,
	unlocked: { [string]: { [string]: boolean } },   -- talents: classId → nodeId → true
	currencies: { [string]: number },                  -- tickets, crystals, soulShards, relicDust, ascension
	collection: {
		characters: { [string]: { copies: number, ascension: number } },
		relics: { [string]: { level: number } },
		cosmetics: { [string]: boolean },                -- titles and armor sets
	},
	equipped: { relics: { string }, variants: { [string]: string }, armor: { [string]: string } }, -- classId → VFX variant id / armor id
	pity: { [string]: { sinceEpic: number, sinceLegendary: number, guaranteedFeatured: boolean } },
	stats: { [string]: number },                      -- lifetime counters (pulls, kills…)
	purchases: { [string]: boolean },                 -- processed receipt ids (idempotent grants)
	account: { level: number, xp: number },           -- account level 1..100 (AccountManager)
	codex: { [string]: boolean },                     -- evolutions discovered (the Build Codex)
	gear: { owned: { [string]: number }, equipped: { [string]: string } }, -- the Armory (LootManager)
	records: { [string]: number },                    -- bests and totals (deepest floor, runs, kills…)
	settings: { [string]: any },                      -- the player's settings (SettingsConfig; empty: never saved)
}

local function newProfile(): Profile
	return {
		version = 1,
		souls = STARTING_SOULS,
		unlocked = {},
		currencies = {},
		collection = { characters = {}, relics = {}, cosmetics = {} },
		equipped = { relics = {}, variants = {}, armor = {} },
		pity = {},
		stats = {},
		purchases = {},
		account = { level = 1, xp = 0 },
		codex = {},
		records = {},
		gear = { owned = {}, equipped = {} },
		settings = {},
	}
end

-- Fill any missing fields so older saves keep working as the schema grows.
local function reconcile(data: any): Profile
	local p = newProfile()
	if typeof(data) ~= "table" then return p end
	for k, v in pairs(data) do
		if typeof(v) == typeof((p :: any)[k]) then (p :: any)[k] = v end
	end
	p.collection.characters = p.collection.characters or {}
	p.collection.relics = p.collection.relics or {}
	p.collection.cosmetics = p.collection.cosmetics or {}
	p.equipped.relics = p.equipped.relics or {}
	p.equipped.variants = p.equipped.variants or {}
	p.equipped.armor = p.equipped.armor or {}
	return p
end

local profiles: { [Player]: Profile } = {}
local dirty: { [Player]: boolean } = {}
local loadedSignals: { (Player, Profile) -> () } = {}
local store: DataStore? = nil
local legacyStore: DataStore? = nil

do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(STORE_NAME)
	end)
	if ok then
		store = result
		pcall(function() legacyStore = DataStoreService:GetDataStore(LEGACY_TALENT_STORE) end)
	else
		warn("[PlayerData] DataStore unavailable — progress will not persist this session:", result)
	end
end

local function key(player: Player): string
	return `u_{player.UserId}`
end

function PlayerData.Get(player: Player): Profile?
	return profiles[player]
end

-- Wait (briefly) for a player's profile to finish loading.
function PlayerData.Await(player: Player, timeout: number?): Profile?
	local t0 = os.clock()
	while not profiles[player] and player.Parent and os.clock() - t0 < (timeout or 15) do
		task.wait(0.1)
	end
	return profiles[player]
end

function PlayerData.Save(player: Player)
	local p = profiles[player]
	if not p or not store then return end
	local ok, err = pcall(function()
		(store :: DataStore):SetAsync(key(player), p)
	end)
	if ok then
		dirty[player] = nil
	else
		warn("[PlayerData] Save failed for", player.Name, err)
	end
end

function PlayerData.MarkDirty(player: Player)
	if dirty[player] then return end
	dirty[player] = true
	task.delay(SAVE_DEBOUNCE, function()
		if dirty[player] and player.Parent then PlayerData.Save(player) end
	end)
end

-- Run `fn` for every profile once it's loaded (and for already-loaded ones).
function PlayerData.OnLoaded(fn: (Player, Profile) -> ())
	table.insert(loadedSignals, fn)
	for player, profile in pairs(profiles) do
		task.spawn(fn, player, profile)
	end
end

local function load(player: Player)
	local data: any = nil
	local legacy: any = nil
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return (store :: DataStore):GetAsync(key(player))
			end)
			if ok then
				data = result
				break
			end
			warn(`[PlayerData] Load attempt {attempt} failed for {player.Name}:`, result)
			task.wait(1)
		end
		if data == nil and legacyStore then
			pcall(function() legacy = (legacyStore :: DataStore):GetAsync(key(player)) end)
		end
	end
	local profile = reconcile(data)
	-- One-time migration from the talent-only profile.
	if data == nil and typeof(legacy) == "table" then
		profile.souls = tonumber(legacy.souls) or profile.souls
		if typeof(legacy.unlocked) == "table" then profile.unlocked = legacy.unlocked end
	end
	if not player.Parent then return end
	profiles[player] = profile
	for _, fn in ipairs(loadedSignals) do
		task.spawn(fn, player, profile)
	end
end

function PlayerData.Init()
	Players.PlayerAdded:Connect(function(player) task.spawn(load, player) end)
	for _, player in ipairs(Players:GetPlayers()) do task.spawn(load, player) end
	Players.PlayerRemoving:Connect(function(player)
		PlayerData.Save(player)
		profiles[player] = nil
		dirty[player] = nil
	end)
	game:BindToClose(function()
		for _, player in ipairs(Players:GetPlayers()) do PlayerData.Save(player) end
	end)
end

return PlayerData
