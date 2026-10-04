local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "NetworkRemotes"

local Network = {}

-- Predefined remote names
Network.Remotes = {
	SelectClass    = "SelectClass",
	ClassConfirmed = "ClassConfirmed",
	SaveSettings   = "SaveSettings",    -- client → server: the settings (saved on their account: PlayerData)
	SettingsSync   = "SettingsSync",    -- client → server: ask for the saved settings; server → client: them (nil: none saved yet)
	SpawnInChurch  = "SpawnInChurch",
	PlayAnimation  = "PlayAnimation",   -- server → client: { idle, walk, sprint } config
	SetSprint      = "SetSprint",       -- client → server: boolean (sprinting?)
	AimTwist       = "AimTwist",        -- client → server: number (the upper body's turn to the cursor, radians; AimStance)
	MountToggle    = "MountToggle",     -- client → server: boolean (ride / get off), from the mount key (B)
	MountFX        = "MountFX",         -- server → clients: { kind = "thrown" } to a rider knocked off; { kind = "tumble", player, plan } to everyone else
	TumblePlan     = "TumblePlan",      -- client → server: how the rider's tumble goes (TumbleData), for everyone else to see it
	PerformAttack       = "PerformAttack",   -- client → server: { attackType, comboStep }
	UseSkill            = "UseSkill",        -- client → server: { skillIndex, origin, direction }
	SkillCooldownUpdate = "SkillCooldownUpdate", -- server → client: { skillIndex, duration }
	SkillVFX            = "SkillVFX",        -- server → client: { player, skillIndex, origin, direction }
	DungeonMapData      = "DungeonMapData",  -- server → client: map grid payload for minimap overlay
	MobDeathVFX         = "MobDeathVFX",     -- server → client: { position }
	DamageDealt         = "DamageDealt",     -- server → attacking client: { position, amount, source }
	TomeProgress        = "TomeProgress",    -- server → client: { level, xp, xpToNext }
	TomeChoices         = "TomeChoices",     -- server → client: { choices = TomeDefinition[] }
	ChooseTome          = "ChooseTome",      -- client → server: tome id
	RerollTomes         = "RerollTomes",     -- client → server: reroll the current tome choices
	GachaState          = "GachaState",      -- server → client: currencies, collection, equipped, pity, policy
	Summon              = "Summon",          -- client → server: { banner, count = 1|10, pay = "tickets"|"crystals" }
	SummonResult        = "SummonResult",    -- server → client: { results = { {id, rarity, isNew, note} }, best } | { error }
	GachaAction         = "GachaAction",     -- client → server: equipRelic / unequipRelic / equipVariant / refineShards / buyCrystals
	RequestGacha        = "RequestGacha",    -- client → server: ask for a GachaState sync
	SummonAnnounce      = "SummonAnnounce",  -- server → all clients: { userId, name, id, rarity } someone wished a Legendary or better
	TalentState         = "TalentState",     -- server → client: { souls, unlocked = { [classId] = { [nodeId] = true } } }
	UnlockTalent        = "UnlockTalent",    -- client → server: { classId, nodeId }
	RequestTalents      = "RequestTalents",  -- client → server: ask for a TalentState sync
	HitImpact           = "HitImpact",       -- server → all clients: { position, style, direction, crit, heavy }
	RoomEvent           = "RoomEvent",       -- server → all clients: special-room feedback (pops, coins, bursts)
	IceMageEvent        = "IceMageEvent",    -- server → all clients: { kind = "CloneShatter"|"Chill", ... }
	GunslingerFX        = "GunslingerFX",
	BasicAttackFX       = "BasicAttackFX",   -- server → other clients: { attacker, classId, direction } (Ranger / Cleric / Ice Mage basic attacks, so everyone sees them)
	FireKnightFX        = "FireKnightFX",    -- server → clients: Emberblade swings, charge, Phoenix Slam, Earthshaker, ignites, Overheat, Heart of the Inferno
	FireKnightAim       = "FireKnightAim",   -- client → server: { target = Vector3 } where the Phoenix Slam lands
	BerserkerFX         = "BerserkerFX",     -- server → clients: combo swings, Rupture, Bloodstorm, Bloodrage: Unchained, Worldbreaker
	SwordsmanFX         = "SwordsmanFX",     -- server → clients: combo swings, rush, parry, whirlwind, Blade Storm, momentum    -- server → clients: Gunslinger shots, coins, splits, reloads, High Noon
	DragonFX            = "DragonFX",        -- server → clients: the dragon boss's fireballs, breath, gusts, roars, knockback, beam clash
	DragonBeam          = "DragonBeam",      -- server → beam target: { phase = "start"|"end", token, keys, windup, duration, success? }
	DragonBeamResult    = "DragonBeamResult", -- client → server: (token, step) each correct arrow key while holding the shield
	RicochetFX          = "RicochetFX",      -- server → all clients: { from, to, attacker } one ricochet hop
	PartyState          = "PartyState",      -- server → client: { leader = userId?, members = { {userId, name} } }
	PartyAction         = "PartyAction",     -- client → server: invite / accept / decline / leave / kick / request
	PartyInvite         = "PartyInvite",     -- server → invited client: { fromUserId, fromName }
	LobbyState          = "LobbyState",      -- server → client: { mode = "hub" | "campfire", mapId?, notice? }
	LobbyAction         = "LobbyAction",     -- client → server: { kind = "toHub" }
	CampfireState       = "CampfireState",   -- server → party: { members = { {userId, name, classId, seated, seat, ready} }, portalAt?, open, stagger, walk }
	CampfireAction      = "CampfireAction",  -- client → server: { kind = "ready", value } | { kind = "class", classId } | { kind = "seat", seat } | { kind = "leave" }
	DeathState          = "DeathState",      -- server → dead client: { mode = "solo"|"coop"|"wipe"|"clear", alive = {userId} }
	DeathAction         = "DeathAction",
	FloorPortal         = "FloorPortal",
	RunSummary          = "RunSummary",
	Evolution           = "Evolution",
	ArmoryState         = "ArmoryState",     -- server → client: { owned = { [id] = count }, equipped = { weapon, aura, title } }
	ArmoryAction        = "ArmoryAction",    -- client → server: { kind = "equip", slot, id? }
	RequestArmory       = "RequestArmory",   -- client → server: ask for an ArmoryState sync
	LootDrop            = "LootDrop",        -- server → finder: { id, name, rarity, slot, glyph, isNew, source }       -- server → client: a boon evolved { id, name, description, color, isNew }
	CodexState          = "CodexState",      -- server → client: { discovered = { [evoId] = true } }
	RequestCodex        = "RequestCodex",    -- client → server: ask for a CodexState sync      -- server → client: the run's over for you: { result, floor, time, tier, stats, rewards, party }     -- server → run's players: { ready, total, readyIds, waiting = {names}, descending } at the floor's exit
	ClaimReward         = "ClaimReward",     -- client → server: the room reward Model you left-clicked near     -- client → server: "respawn" | "menu"
}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
		end
	end
	return folder :: Folder
end

-- Auto-create all remotes on server at load time
if RunService:IsServer() then
	local folder = getFolder()
	for _, remoteName in pairs(Network.Remotes) do
		if not folder:FindFirstChild(remoteName) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = remoteName
			remote.Parent = folder
		end
	end
end

function Network.GetRemoteEvent(name: string): RemoteEvent
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name) :: RemoteEvent
		end
	end
	return remote :: RemoteEvent
end

function Network.GetRemoteFunction(name: string): RemoteFunction
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name) :: RemoteFunction
		end
	end
	return remote :: RemoteFunction
end

return Network
