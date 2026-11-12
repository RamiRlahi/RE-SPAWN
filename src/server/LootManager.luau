--!strict
--[[
	LootManager.luau
	The Armory's loot (GearData): what drops in a run, what you keep, what you
	wear.

	Drops
	  • elites (12% each, for everyone near), bosses (one each, Rare or better),
	    every floor you go down (one each), extracting (two more, Rare or
	    better), and now and then an ordinary mob
	  • the deeper the floor and the higher the Corruption, the rarer
	  • a drop shows as a pillar of light in its rarity's colour where it fell,
	    and a toast on the finder's screen (LootDrop)

	Keeping it (the greed)
	  • loot found in a run is carried, not yours yet: EXTRACT and you keep all
	    of it; fall (or walk out) and each piece has a 50% chance to be lost
	  • the run summary shows each piece SECURED or LOST
	  • a duplicate of something you own becomes souls

	Wearing it
	  • profile.gear.owned / .equipped (weapon, aura, title), replicated as the
	    attributes Gear_weapon, Gear_aura, Gear_title (everyone sees them)
	  • the weapon finish goes on the class weapon (WeaponManager), the aura on
	    the character, the title on the lobby nameplate

	Power gear (PowerGear): most drops are pieces with stats instead, and
	they're what makes you stronger run after run
	  • rolled at an item level from the floor and the Corruption (deeper is
	    stronger), kept by the same rule (extract, or the coin toss)
	  • profile.power = { items = { [uid] = Item }, equipped = { [slot] = uid },
	    nextUid, scrap }; a piece better than what you wear is put on at once
	  • the spare pieces past PowerGear.INVENTORY are salvaged into scrap
	  • POWER (PowerGear.Total) is mirrored as the attribute "Power"
	  • PowerEffects(player): the worn stats and the hero-level bonus, folded
	    into the run by PlayerStats.StartRun

	The forge (ArmoryAction): "upgrade" a piece one level for scrap, "salvage"
	a spare one, "salvageWeaker" every spare piece weaker than what's worn in
	its slot. The worn weapon's forge level is the attribute "WeaponPlus"
	(everyone sees it on the weapon: WeaponForgeFX).

	Remotes: ArmoryState (→ owner), ArmoryAction (equip, equipPower, upgrade,
	salvage, salvageWeaker, craft), LootDrop (→ finder; source "forge" for
	a forged piece)

	"craft" { slot, score }: a new piece forged (PowerGear.CRAFT_COST scrap),
	its rarity from the minigame's score. The score comes from the client
	(it's a minigame): it's clamped, crafts are spaced CRAFT_GAP apart, and
	scrap is the real limit, so a faked score only buys better odds.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GearData = require(Shared:WaitForChild("GearData"))
local GearLook = require(Shared:WaitForChild("GearLook"))
local PowerGear = require(Shared:WaitForChild("PowerGear"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local WeeklyModifiers = require(Shared:WaitForChild("WeeklyModifiers"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local RunStats = require(script.Parent:WaitForChild("RunStats"))

local LootManager = {}

local SLOTS = { "weapon", "aura", "title" }
local KEEP_ON_FALL = 0.5
local POWER_SHARE = 0.8 -- of drops that are power gear (the rest: a cosmetic)
local CRAFT_GAP = 4 -- seconds between two forgings (the minigame alone takes longer)
local lastCraft: { [Player]: number } = {}

-- ── The profile ───────────────────────────────────────────────────────────
type Gear = { owned: { [string]: number }, equipped: { [string]: string } }

local function gearOf(player: Player): Gear?
	local p = PlayerData.Get(player) :: any
	if not p then return nil end
	if typeof(p.gear) ~= "table" then p.gear = { owned = {}, equipped = {} } end
	p.gear.owned = p.gear.owned or {}
	p.gear.equipped = p.gear.equipped or {}
	return p.gear
end

-- ── Power gear ────────────────────────────────────────────────────────────
type Power = { items: { [string]: any }, equipped: { [string]: string }, nextUid: number, scrap: number }

local function powerOf(player: Player): Power?
	local p = PlayerData.Get(player) :: any
	if not p then return nil end
	if typeof(p.power) ~= "table" then p.power = { items = {}, equipped = {}, nextUid = 1, scrap = 0 } end
	local pw = p.power
	pw.items = pw.items or {}
	pw.equipped = pw.equipped or {}
	pw.nextUid = pw.nextUid or 1
	pw.scrap = pw.scrap or 0
	return pw
end

local function heroLevel(player: Player): number
	local lv = player:GetAttribute("AccountLevel")
	return if typeof(lv) == "number" then lv else 1
end

local function worn(pw: Power): { any }
	local list = {}
	for _, slot in ipairs(PowerGear.SLOTS) do
		local uid = pw.equipped[slot]
		local item = uid and pw.items[uid]
		if item then table.insert(list, item) end
	end
	return list
end

local function totalPower(player: Player): number
	local pw = powerOf(player)
	return PowerGear.Total(if pw then worn(pw) else {}, heroLevel(player))
end

-- How much `item` would add over what's worn in its slot (negative: weaker).
local function gainOver(player: Player, item: any): number
	local pw = powerOf(player)
	local uid = pw and pw.equipped[item.slot]
	local cur = if pw and uid then pw.items[uid] else nil
	return PowerGear.ItemPower(item) - PowerGear.ItemPower(cur)
end

-- The worn stats and the hero level's bonus, as tome effects (PlayerStats).
function LootManager.PowerEffects(player: Player): { any }
	local out = PowerGear.HeroEffects(heroLevel(player))
	local pw = powerOf(player)
	if pw then
		for _, item in ipairs(worn(pw)) do
			for _, e in ipairs(PowerGear.Effects(item)) do table.insert(out, e) end
		end
	end
	return out
end

local function sync(player: Player)
	local g = gearOf(player)
	if not g then return end
	for _, slot in ipairs(SLOTS) do
		player:SetAttribute(`Gear_{slot}`, g.equipped[slot])
	end
	local pw = powerOf(player)
	local total = totalPower(player)
	player:SetAttribute("Power", total)
	local wuid = pw and pw.equipped.weapon
	local weapon = if pw and wuid then pw.items[wuid] else nil
	player:SetAttribute("WeaponPlus", if weapon then weapon.plus or 0 else 0)
	Network.GetRemoteEvent(Network.Remotes.ArmoryState):FireClient(player, {
		owned = g.owned, equipped = g.equipped,
		power = pw and { items = pw.items, equipped = pw.equipped, scrap = pw.scrap, total = total },
	})
end
LootManager.Sync = sync

-- The aura and the nameplate on a character (the weapon finish goes on with the weapon).
local function dress(player: Player)
	local char = player.Character
	if not char then return end
	GearLook.Aura(char, player:GetAttribute("Gear_aura"))
	local title = player:GetAttribute("Gear_title")
	GearLook.Nameplate(char, player.DisplayName, if typeof(title) == "string" then title else nil, player:GetAttribute("InHub") == true)
	local hum = char:FindFirstChildOfClass("Humanoid")
	-- (in the lobby our nameplate replaces Roblox's)
	if hum then
		hum.DisplayDistanceType = if player:GetAttribute("InHub") == true then Enum.HumanoidDisplayDistanceType.None else Enum.HumanoidDisplayDistanceType.Viewer
	end
end

-- Give `id` to the player's collection: new, or a duplicate worth souls.
-- Returns whether it was new and the souls a duplicate gave.
local function grant(player: Player, id: string): (boolean, number)
	local g = gearOf(player)
	local item = GearData.Get(id)
	if not g or not item then return false, 0 end
	local had = (g.owned[id] or 0) > 0
	g.owned[id] = (g.owned[id] or 0) + 1
	PlayerData.MarkDirty(player)
	if not had then return true, 0 end
	local souls = GearData.DUPLICATE_SOULS[item.rarity] or 1
	pcall(function()
		local TalentManager = require(script.Parent:WaitForChild("TalentManager")) :: any
		TalentManager.AwardSouls(player, souls)
	end)
	return false, souls
end

-- Keep a power piece: into the collection, worn at once if it beats what's
-- worn. Returns the POWER it added (0 if it went in the bag).
local function grantPower(player: Player, item: any): number
	local pw = powerOf(player)
	if not pw then return 0 end
	local gain = 0
	local better = gainOver(player, item) > 0
	local uid = `i{pw.nextUid}`
	pw.nextUid += 1
	item.uid = uid
	pw.items[uid] = item
	if better then
		local before = totalPower(player)
		pw.equipped[item.slot] = uid
		gain = totalPower(player) - before
	end
	-- (a full bag: the weakest spare piece is salvaged)
	local n = 0
	for _ in pairs(pw.items) do n += 1 end
	while n > PowerGear.INVENTORY do
		local wornSet = {}
		for _, u in pairs(pw.equipped) do wornSet[u] = true end
		local worstUid, worst = nil, math.huge
		for u, it in pairs(pw.items) do
			local v = PowerGear.ItemPower(it)
			if not wornSet[u] and v < worst then worstUid, worst = u, v end
		end
		if not worstUid then break end
		pw.scrap += PowerGear.SCRAP[pw.items[worstUid].rarity] or 1
		pw.items[worstUid] = nil
		n -= 1
	end
	PlayerData.MarkDirty(player)
	return gain
end

-- ── Rolling a drop ────────────────────────────────────────────────────────
local CHANCE = { Mythic = 0.003, Legendary = 0.02, Epic = 0.06, Rare = 0.16, Uncommon = 0.34 }

local function luck(runId: any, extra: number): number
	local floor = RunScope.Get(runId, "RunLevel") or 1
	local corruption = RunScope.Get(runId, "Corruption") or 0
	return 1 + 0.12 * (floor - 1) + 0.25 * corruption + extra
end

local function rollRarity(mult: number, minRarity: string?): string
	local picked = "Common"
	for i = #GearData.RARITIES, 2, -1 do
		local r = GearData.RARITIES[i]
		local moon = if (r == "Legendary" or r == "Mythic") and WeeklyModifiers.Is("blood_moon") then 2 else 1
		if math.random() < (CHANCE[r] or 0) * mult * moon then
			picked = r
			break
		end
	end
	if minRarity and GearData.RarityIndex(picked) < GearData.RarityIndex(minRarity) then picked = minRarity end
	return picked
end

-- Carried loot this run, per player: a cosmetic { id } or a power piece { power }.
local carried: { [Player]: { { id: string?, power: any? } } } = {}

-- The pillar of light where a drop fell.
local function beacon(at: Vector3, color: Color3, big: boolean)
	local folder = Workspace:FindFirstChild("LootFX") or (function()
		local f = Instance.new("Folder")
		f.Name = "LootFX"
		f.Parent = Workspace
		return f
	end)()
	local h = if big then 30 else 18
	local col = Instance.new("Part")
	col.Anchored = true
	col.CanCollide = false
	col.CanQuery = false
	col.CanTouch = false
	col.CastShadow = false
	col.Material = Enum.Material.Neon
	col.Color = color
	col.Transparency = 0.35
	col.Size = Vector3.new(0.9, h, 0.9)
	col.CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0))
	col.Parent = folder
	local orb = col:Clone()
	orb.Shape = Enum.PartType.Ball
	orb.Size = Vector3.one * 1.6
	orb.Transparency = 0.1
	orb.CFrame = CFrame.new(at + Vector3.new(0, 1.2, 0))
	orb.Parent = folder
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.Color = ColorSequence.new(color)
	sp.LightEmission = 1
	sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	sp.Lifetime = NumberRange.new(0.6, 1.2)
	sp.Speed = NumberRange.new(3, 7)
	sp.SpreadAngle = Vector2.new(30, 30)
	sp.Rate = 30
	sp.Parent = orb
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = 14
	l.Brightness = 2
	l.Parent = orb
	TweenService:Create(col, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { Transparency = 1, Size = Vector3.new(0.2, h, 0.2) }):Play()
	TweenService:Create(orb, TweenInfo.new(2.2, Enum.EasingStyle.Sine), { Transparency = 1, Size = Vector3.one * 0.4 }):Play()
	Debris:AddItem(col, 2.3)
	Debris:AddItem(orb, 2.3)
end

-- A drop for `player` (from `source`: "elite", "boss", "floor", "extract", "mob").
function LootManager.Drop(player: Player, source: string, at: Vector3?, minRarity: string?): string?
	if player:GetAttribute("InLobby") ~= false then return nil end
	local runId = player:GetAttribute("RunId")
	local extra = if source == "boss" then 1.5 elseif source == "elite" then 0.6 elseif source == "extract" then 1 else 0
	local rarity = rollRarity(luck(runId, extra), minRarity)
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local spot = at or (if root then root.Position - Vector3.new(0, 2.5, 0) else nil)
	local color = GearData.RARITY_COLOR[rarity] or Color3.new(1, 1, 1)
	if math.random() < POWER_SHARE then
		-- a power piece, at the floor's item level (+1 for a boss or the extraction)
		local floor = RunScope.Get(runId, "RunLevel") or 1
		local corruption = RunScope.Get(runId, "Corruption") or 0
		local ilvl = floor + math.floor(corruption / 2) + (if source == "boss" or source == "extract" then 1 else 0)
		local item = PowerGear.Roll(rarity, ilvl)
		carried[player] = carried[player] or {}
		table.insert(carried[player], { power = item })
		local gain = gainOver(player, item)
		RunStats.AddLoot(player, { kind = "power", name = item.name, glyph = item.glyph, rarity = item.rarity, slot = item.slot,
			ilvl = item.ilvl, power = PowerGear.ItemPower(item), gain = gain })
		if spot then beacon(spot, color, GearData.RarityIndex(item.rarity) >= 5) end
		local lines = {}
		for _, a in ipairs(item.affixes) do table.insert(lines, PowerGear.Describe(a)) end
		Network.GetRemoteEvent(Network.Remotes.LootDrop):FireClient(player, {
			power = true, name = item.name, rarity = item.rarity, slot = item.slot, slotName = PowerGear.SLOT_NAME[item.slot],
			glyph = item.glyph, ilvl = item.ilvl, itemPower = PowerGear.ItemPower(item), gain = gain, stats = lines, source = source,
		})
		return item.name
	end
	local pool = GearData.OfRarity(rarity)
	if #pool == 0 then return nil end
	local item = pool[math.random(1, #pool)]
	carried[player] = carried[player] or {}
	table.insert(carried[player], { id = item.id })
	local g = gearOf(player)
	local isNew = g ~= nil and (g.owned[item.id] or 0) == 0
	RunStats.AddLoot(player, { kind = "gear", id = item.id, name = item.name, glyph = item.glyph, rarity = item.rarity, slot = item.slot, isNew = isNew })
	color = GearData.RARITY_COLOR[item.rarity] or Color3.new(1, 1, 1)
	if spot then beacon(spot, color, GearData.RarityIndex(item.rarity) >= 5) end
	Network.GetRemoteEvent(Network.Remotes.LootDrop):FireClient(player, {
		id = item.id, name = item.name, rarity = item.rarity, slot = item.slot, glyph = item.glyph, isNew = isNew, source = source,
	})
	return item.id
end

-- A mob died: its loot for everyone near enough to share the kill.
function LootManager.OnMobKilled(model: Model, isBoss: boolean, near: { Player })
	local at = (model:FindFirstChild("HumanoidRootPart") :: BasePart?)
	local pos = if at then at.Position - Vector3.new(0, 2.5, 0) else nil
	local elite = model:GetAttribute("IsElite") == true
	-- (run relics: every boss offers a choice of three; elites now and then)
	local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
	for _, p in ipairs(near) do
		if isBoss then
			LootManager.Drop(p, "boss", pos, "Rare")
			PlayerStats.OfferRelics(p)
		elseif elite then
			if math.random() < (if WeeklyModifiers.Is("elite_invasion") then 0.18 else 0.12) then LootManager.Drop(p, "elite", pos) end
			if math.random() < 0.06 then PlayerStats.OfferRelics(p) end
		elseif math.random() < 0.006 then
			LootManager.Drop(p, "mob", pos)
		end
	end
end

-- The run's over for `player` (RunStats.Finish asks us): extracting keeps
-- everything carried; otherwise each piece is a coin toss. Marks the summary's
-- loot SECURED / LOST and grants what's kept.
function LootManager.Settle(player: Player, result: string, loot: { any })
	local list = carried[player] or {}
	carried[player] = nil
	local keepAll = result == "extracted"
	local fate: { [number]: boolean } = {} -- index in `list` → kept
	for i in ipairs(list) do fate[i] = keepAll or math.random() < KEEP_ON_FALL end
	local gi = 0
	for _, entry in ipairs(loot) do
		if entry.kind == "power" then
			gi += 1
			local kept = fate[gi] ~= false
			entry.secured = kept
			entry.lost = not kept
			local c = list[gi]
			if kept and c and c.power then
				local gain = grantPower(player, c.power)
				entry.upgrade = if gain > 0 then gain else nil
			end
		elseif entry.kind == "gear" then
			gi += 1
			local kept = fate[gi] ~= false
			entry.secured = kept
			entry.lost = not kept
			if kept then
				local isNew, souls = grant(player, entry.id)
				entry.isNew = isNew
				entry.dupeSouls = if souls > 0 then souls else nil
			end
		end
	end
	sync(player)
end

-- ── Equipping ─────────────────────────────────────────────────────────────
local function onAction(player: Player, payload: any)
	if typeof(payload) ~= "table" then return end
	if payload.kind == "equipPower" then
		-- (worn from the next run on: a run's stats are set when it starts)
		local pw = powerOf(player)
		local uid = payload.uid
		local item = if pw and typeof(uid) == "string" then pw.items[uid] else nil
		if not pw or not item then return end
		pw.equipped[item.slot] = uid
		PlayerData.MarkDirty(player)
		sync(player)
		return
	end
	if payload.kind == "upgrade" or payload.kind == "salvage" then
		local pw = powerOf(player)
		local uid = payload.uid
		local item = if pw and typeof(uid) == "string" then pw.items[uid] else nil
		if not pw or not item then return end
		if payload.kind == "upgrade" then
			local cost = PowerGear.UpgradeCost(item)
			if not cost or pw.scrap < cost then return end
			pw.scrap -= cost
			item.spent = (item.spent or 0) + cost
			item.plus = (item.plus or 0) + 1
		else
			if pw.equipped[item.slot] == uid then return end -- (never what's worn)
			pw.scrap += PowerGear.SalvageValue(item)
			pw.items[uid] = nil
		end
		PlayerData.MarkDirty(player)
		sync(player)
		return
	end
	if payload.kind == "craft" then
		local pw = powerOf(player)
		local slot, score = payload.slot, payload.score
		if not pw or typeof(slot) ~= "string" or not PowerGear.MAIN[slot] or typeof(score) ~= "number" or score ~= score then return end
		local now = os.clock()
		if now - (lastCraft[player] or -math.huge) < CRAFT_GAP then return end
		if pw.scrap < PowerGear.CRAFT_COST then return end
		lastCraft[player] = now
		pw.scrap -= PowerGear.CRAFT_COST
		local best = player:GetAttribute("BestFloor")
		local ilvl = math.max(1, if typeof(best) == "number" then best else 1)
		local item = PowerGear.Roll(PowerGear.CraftRarity(score), ilvl, slot)
		local gain = gainOver(player, item)
		local added = grantPower(player, item)
		local lines = {}
		for _, a in ipairs(item.affixes) do table.insert(lines, PowerGear.Describe(a)) end
		Network.GetRemoteEvent(Network.Remotes.LootDrop):FireClient(player, {
			power = true, name = item.name, rarity = item.rarity, slot = item.slot, slotName = PowerGear.SLOT_NAME[item.slot],
			glyph = item.glyph, ilvl = item.ilvl, itemPower = PowerGear.ItemPower(item), gain = gain, worn = added > 0,
			stats = lines, source = "forge",
		})
		sync(player)
		return
	end
	if payload.kind == "salvageWeaker" then
		local pw = powerOf(player)
		if not pw then return end
		for uid, item in pairs(pw.items) do
			local wornUid = pw.equipped[item.slot]
			if wornUid ~= uid then
				local cur = if wornUid then pw.items[wornUid] else nil
				if cur and PowerGear.ItemPower(item) < PowerGear.ItemPower(cur) then
					pw.scrap += PowerGear.SalvageValue(item)
					pw.items[uid] = nil
				end
			end
		end
		PlayerData.MarkDirty(player)
		sync(player)
		return
	end
	if payload.kind ~= "equip" then return end
	local slot = payload.slot
	if typeof(slot) ~= "string" or not table.find(SLOTS, slot) then return end
	local g = gearOf(player)
	if not g then return end
	local id = payload.id
	if id == nil then
		g.equipped[slot] = nil
	else
		local item = GearData.Get(id)
		if not item or item.slot ~= slot or (g.owned[id] or 0) <= 0 then return end
		g.equipped[slot] = id
	end
	PlayerData.MarkDirty(player)
	sync(player)
	dress(player)
	-- the weapon finish: re-equip the weapon the way it's carried now
	if slot == "weapon" then
		local classId = player:GetAttribute("SelectedClass")
		if typeof(classId) == "string" then
			local WeaponManager = require(script.Parent:WaitForChild("WeaponManager")) :: any
			if player:GetAttribute("InHub") == true then
				pcall(WeaponManager.StowWeapon, player, classId)
			elseif player:GetAttribute("InLobby") == false then
				pcall(WeaponManager.EquipWeapon, player, classId)
			end
		end
	end
end

function LootManager.Init()
	-- (the run's end decides what's kept: the summary shows it)
	RunStats.SetSettle(LootManager.Settle)
	PlayerData.OnLoaded(function(player: Player)
		sync(player)
		dress(player)
	end)
	Network.GetRemoteEvent(Network.Remotes.ArmoryAction).OnServerEvent:Connect(onAction)
	Network.GetRemoteEvent(Network.Remotes.RequestArmory).OnServerEvent:Connect(sync)
	local function watch(player: Player)
		player.CharacterAdded:Connect(function(char)
			char:WaitForChild("HumanoidRootPart", 10)
			char:WaitForChild("Head", 10)
			dress(player)
		end)
		player:GetAttributeChangedSignal("InHub"):Connect(function() dress(player) end)
		-- (POWER counts the hero level)
		player:GetAttributeChangedSignal("AccountLevel"):Connect(function()
			if PlayerData.Get(player) then player:SetAttribute("Power", totalPower(player)) end
		end)
		if PlayerData.Get(player) then
			sync(player)
			dress(player)
		end
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p)
		carried[p] = nil
		lastCraft[p] = nil
	end)
end

return LootManager
