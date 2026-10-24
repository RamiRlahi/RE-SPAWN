--!strict
--[[
	EquipmentManager.luau
	The Forgotten Isle's gear (EquipmentData), worn for the run only: each
	player's bag and what they have on, kept here on the server and never
	saved. A new run (or leaving one) empties it.

	  EquipmentManager.Grant(player, id) → item?   into the bag (a full bag
	                                              salvages its worst piece)
	  EquipmentManager.Perk(player, perkId) → params?   a perk they have on
	  EquipmentManager.Equipped(player) → { [slot]: id }

	The client asks (IslandAction): equip a piece from the bag, take one off,
	salvage one for gold. Every ask is checked: the piece must be theirs, in
	their bag, and they must be on the island. What they have on goes to the
	run's stats as tome effects (PlayerStats.SetExtraEffects "gear"), and as
	attributes for the HUD and the perks that show on the character
	(IsleGear_<slot>, OracleRadius, KnockImmune).

	State to the owner (IslandEvent kind "gear"): the bag and the slots.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EquipmentData = require(Shared:WaitForChild("EquipmentData"))
local Network = require(Shared:WaitForChild("Network"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local EquipmentManager = {}

type Owned = { uid: number, id: string }
type Gear = { runId: string?, bag: { Owned }, equipped: { [string]: Owned }, nextUid: number }
local gear: { [Player]: Gear } = {}

local function gearOf(player: Player): Gear
	local g = gear[player]
	local runId = player:GetAttribute("RunId")
	-- (a different run: a fresh bag)
	if not g or g.runId ~= runId then
		g = { runId = if typeof(runId) == "string" then runId else nil, bag = {}, equipped = {}, nextUid = 1 }
		gear[player] = g
	end
	return g :: Gear
end

local function view(o: Owned): { [string]: any }
	return { uid = o.uid, id = o.id }
end

local function sync(player: Player)
	local g = gearOf(player)
	local bag, eq = {}, {}
	for _, o in ipairs(g.bag) do table.insert(bag, view(o)) end
	for slot, o in pairs(g.equipped) do eq[slot] = view(o) end
	Network.GetRemoteEvent(Network.Remotes.IslandEvent):FireClient(player, { kind = "gear", bag = bag, equipped = eq })
end

-- What they have on → the run's stats, and the attributes that show it.
local function apply(player: Player)
	local g = gearOf(player)
	local effects = {}
	for _, slot in ipairs(EquipmentData.Slots) do
		local o = g.equipped[slot]
		local item = o and EquipmentData.Get(o.id)
		player:SetAttribute("IsleGear_" .. slot, if item then item.id else nil)
		if item then
			for _, e in ipairs(item.stats) do table.insert(effects, e) end
		end
	end
	PlayerStats.SetExtraEffects(player, "gear", if #effects > 0 then effects else nil)
	local oracle = EquipmentManager.Perk(player, "oracle")
	player:SetAttribute("OracleRadius", if oracle then oracle.radius else nil)
	local char = player.Character
	if char then char:SetAttribute("KnockImmune", if EquipmentManager.Perk(player, "ironroot") then true else nil) end
end

local function salvageValue(id: string): number
	local item = EquipmentData.Get(id)
	local r = item and EquipmentData.Rarities[item.rarity]
	return if r then r.salvage else 20
end

function EquipmentManager.Grant(player: Player, id: string): EquipmentData.Item?
	local item = EquipmentData.Get(id)
	if not item then return nil end
	local g = gearOf(player)
	local o: Owned = { uid = g.nextUid, id = id }
	g.nextUid += 1
	table.insert(g.bag, o)
	-- a full bag: its least valuable piece is salvaged
	if #g.bag > EquipmentData.BAG then
		local worst, wi = nil, nil
		for i, b in ipairs(g.bag) do
			local it = EquipmentData.Get(b.id)
			local order = if it then EquipmentData.Rarities[it.rarity].order else 0
			if not worst or order < worst then worst, wi = order, i end
		end
		if wi then
			local gone = table.remove(g.bag, wi) :: Owned
			local gold = PlayerStats.AwardGold(player, salvageValue(gone.id))
			Network.GetRemoteEvent(Network.Remotes.IslandEvent):FireClient(player, { kind = "salvaged", id = gone.id, gold = gold, auto = true })
		end
	end
	sync(player)
	return item
end

local function findInBag(g: Gear, uid: any): (Owned?, number?)
	if typeof(uid) ~= "number" then return nil, nil end
	for i, o in ipairs(g.bag) do
		if o.uid == uid then return o, i end
	end
	return nil, nil
end

function EquipmentManager.Equip(player: Player, uid: any): boolean
	local g = gearOf(player)
	local o, i = findInBag(g, uid)
	if not o or not i then return false end
	local item = EquipmentData.Get(o.id)
	if not item then return false end
	local slot = item.slot
	local fits = EquipmentData.SlotFits[slot]
	if fits then
		-- (an accessory: the first empty accessory slot, else the first)
		slot = fits[1]
		for _, s in ipairs(fits) do
			if not g.equipped[s] then
				slot = s
				break
			end
		end
	end
	table.remove(g.bag, i)
	local old = g.equipped[slot]
	g.equipped[slot] = o
	if old then table.insert(g.bag, old) end
	apply(player)
	sync(player)
	return true
end

function EquipmentManager.Unequip(player: Player, slot: any): boolean
	local g = gearOf(player)
	if typeof(slot) ~= "string" or not g.equipped[slot] then return false end
	if #g.bag >= EquipmentData.BAG then return false end -- (no room)
	table.insert(g.bag, g.equipped[slot])
	g.equipped[slot] = nil
	apply(player)
	sync(player)
	return true
end

function EquipmentManager.Salvage(player: Player, uid: any): boolean
	local g = gearOf(player)
	local o, i = findInBag(g, uid)
	if not o or not i then return false end
	table.remove(g.bag, i)
	local gold = PlayerStats.AwardGold(player, salvageValue(o.id))
	Network.GetRemoteEvent(Network.Remotes.IslandEvent):FireClient(player, { kind = "salvaged", id = o.id, gold = gold })
	sync(player)
	return true
end

-- A perk they have on (its params, from EquipmentData), or nil.
function EquipmentManager.Perk(player: Player, perkId: string): { [string]: any }?
	local g = gear[player]
	if not g then return nil end
	for _, o in pairs(g.equipped) do
		local item = EquipmentData.Get(o.id)
		if item and item.perk.id == perkId then return item.perk end
	end
	return nil
end

function EquipmentManager.Equipped(player: Player): { [string]: string }
	local out = {}
	local g = gear[player]
	if g then
		for slot, o in pairs(g.equipped) do out[slot] = o.id end
	end
	return out
end

-- Empty a player's gear (their run is over).
function EquipmentManager.Clear(player: Player)
	gear[player] = nil
	PlayerStats.SetExtraEffects(player, "gear", nil)
	for _, slot in ipairs(EquipmentData.Slots) do player:SetAttribute("IsleGear_" .. slot, nil) end
	player:SetAttribute("OracleRadius", nil)
end

function EquipmentManager.Init()
	local function watch(p: Player)
		-- leaving the run (to the lobby): the run's gear is gone
		p:GetAttributeChangedSignal("InLobby"):Connect(function()
			if p:GetAttribute("InLobby") == true then EquipmentManager.Clear(p) end
		end)
		-- (a new body: its knockback immunity back on)
		p.CharacterAdded:Connect(function()
			task.defer(function()
				if gear[p] then apply(p) end
			end)
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(p) gear[p] = nil end)

	local IslandMode = require(script.Parent:WaitForChild("IslandMode")) :: any
	IslandMode.Handle("equip", function(p: Player, msg: any) EquipmentManager.Equip(p, msg.uid) end)
	IslandMode.Handle("unequip", function(p: Player, msg: any) EquipmentManager.Unequip(p, msg.slot) end)
	IslandMode.Handle("salvage", function(p: Player, msg: any) EquipmentManager.Salvage(p, msg.uid) end)
	IslandMode.Handle("gear", function(p: Player) sync(p) end)
end

return EquipmentManager
