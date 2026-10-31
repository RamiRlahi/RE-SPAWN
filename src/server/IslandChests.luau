--!strict
--[[
	IslandChests.luau
	The Forgotten Isle's chests (IslandKit builds them; IslandConfig.Chests
	says how many, IslandConfig.Loot what's in them).

	  common   by the beaches, the ruins, the clearings: gold, a draught or
	           tonic, now and then a piece of Rare gear or a tome
	  rare     in the caves (their crystal halls), deep ruins, the highlands:
	           better odds of better gear
	  cursed   sealed with a red glow: opening it wakes an ambush round it,
	           and only once the ambush is dead does it open, with the best
	           odds outside a boss
	  elite    left where an elite fell (sometimes; a Behemoth always)
	  ritual   raised by the altar when its boss falls (IslandRitual): boss
	           gear (its own exclusive, or the legendary pool) and a tome

	Opening one (its prompt, on the server): it opens once. Every player of
	the run near it when it does gets their own roll (no one takes another's
	loot, and nothing can be claimed twice): gear into the bag
	(EquipmentManager), gold, a consumable used at once, a tome
	(PlayerStats.GrantTome). Luck (the Luck Tome, the Oracle's Veil) and the
	island's events tip the odds toward the rarer. An opened common chest
	comes back elsewhere after a while.

	  IslandChests.Start(runId) / Stop(runId)   (IslandMode)
	  IslandChests.DropElite(runId, pos)
	  IslandChests.Spawn(runId, kind, cf, ctx?) → Model   (ctx.boss: the
	      boss whose exclusive gear a ritual chest can hold; ctx.participants:
	      the UserIds who fought it, each of whom gets a share wherever they are)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local IslandKit = require(Shared:WaitForChild("IslandKit"))
local EquipmentData = require(Shared:WaitForChild("EquipmentData"))
local IslandGenerator = require(script.Parent:WaitForChild("IslandGenerator"))
local IslandMode = require(script.Parent:WaitForChild("IslandMode"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))
local EquipmentManager = require(script.Parent:WaitForChild("EquipmentManager"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))

local IslandChests = {}

local LOOT = IslandConfig.Loot
local CHEST_NAMES = { common = "Chest", rare = "Rare Chest", cursed = "Cursed Chest", elite = "Elite Chest", ritual = "Ritual Chest" }
local SFX = {
	open = "rbxassetid://9116406610",   -- a magic poof
	rare = "rbxassetid://9116384485",   -- a magic burst
	chime = "rbxassetid://9116394545",
	seal = "rbxassetid://9125404320",   -- a deep boom
}

type Chest = { model: Model, kind: string, state: string, spot: number?, ctx: any, runId: string }
type RunChests = { runId: string, folder: Folder, chests: { Chest }, usedSpots: { [number]: boolean }, alive: boolean, rng: Random }
local runs: { [string]: RunChests } = {}

local function sound(at: BasePart, id: string, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMaxDistance = 120
	s.Parent = at
	s:Play()
	Debris:AddItem(s, 6)
end

-- ── Rolling ─────────────────────────────────────────────────────────────────
local function pickRarity(rng: Random, odds: { [string]: number }, luck: number): string
	local total, pool = 0, {}
	for r, w in pairs(odds) do
		local order = EquipmentData.Rarities[r].order
		local tilted = w * (1 + luck * LOOT.luckTilt) ^ (order - 1)
		total += tilted
		table.insert(pool, { r = r, w = tilted })
	end
	table.sort(pool, function(a, b) return a.r < b.r end)
	local roll = rng:NextNumber(0, total)
	for _, e in ipairs(pool) do
		roll -= e.w
		if roll <= 0 then return e.r end
	end
	return pool[#pool].r
end

local function pickItem(rng: Random, rarity: string, boss: string?): string?
	local pool = EquipmentData.Pool(rarity)
	if #pool == 0 then return nil end
	return pool[rng:NextInteger(1, #pool)]
end

local function useConsumable(p: Player, id: string)
	local char = p.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local Perks = require(script.Parent:WaitForChild("EquipmentPerks")) :: any
	if id == "healing_draught" then
		if hum and hum.Health > 0 then hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.4 * Perks.HealMult(p)) end
	elseif id == "fury_tonic" then
		PlayerStats.SetExtraEffects(p, "tonic_fury", { { stat = "damage", operation = "multiplier", value = 0.25 } })
		task.delay(25, function() if p.Parent then PlayerStats.SetExtraEffects(p, "tonic_fury", nil) end end)
	elseif id == "swift_tonic" then
		PlayerStats.SetExtraEffects(p, "tonic_swift", { { stat = "movementSpeed", operation = "percent", value = 0.2 } })
		task.delay(25, function() if p.Parent then PlayerStats.SetExtraEffects(p, "tonic_swift", nil) end end)
	elseif id == "insight_scroll" then
		PlayerStats.AwardXP(p, 120)
	end
end

local CONSUMABLE_IDS = { "healing_draught", "healing_draught", "fury_tonic", "swift_tonic", "insight_scroll" }

-- One player's share of a chest.
local function roll(rc: RunChests, p: Player, kind: string, ctx: any): { [string]: any }
	local tbl = LOOT.tables[kind] or LOOT.tables.common
	local rng = rc.rng
	local mods = IslandMode.Mods(rc.runId)
	local luck = PlayerStats.GetStat(p, "luck") + (mods.loot - 1)
	local out: { [string]: any } = { kind = "loot", chest = kind, items = {} }
	local function gearRoll()
		if ctx and ctx.boss and tbl.bossItem and rng:NextNumber() < tbl.bossItem then
			local exclusive = {}
			for id, item in pairs(EquipmentData.Items) do
				if item.boss == ctx.boss then table.insert(exclusive, id) end
			end
			if #exclusive > 0 then return exclusive[rng:NextInteger(1, #exclusive)] end
		end
		return pickItem(rng, pickRarity(rng, tbl.rarity, luck))
	end
	if rng:NextNumber() < tbl.gear * mods.loot then
		local id = gearRoll()
		if id and EquipmentManager.Grant(p, id) then table.insert(out.items, id) end
	end
	if tbl.extra and rng:NextNumber() < tbl.extra then
		local id = gearRoll()
		if id and EquipmentManager.Grant(p, id) then table.insert(out.items, id) end
	end
	out.gold = PlayerStats.AwardGold(p, rng:NextInteger(tbl.gold[1], tbl.gold[2]))
	if rng:NextNumber() < tbl.consumable then
		local c = CONSUMABLE_IDS[rng:NextInteger(1, #CONSUMABLE_IDS)]
		useConsumable(p, c)
		out.consumable = c
	end
	if rng:NextNumber() < tbl.tome then
		local tome = PlayerStats.GrantTome(p)
		if tome then out.tome = tome.name end
	end
	return out
end

-- ── Opening ─────────────────────────────────────────────────────────────────
local function swingLid(model: Model)
	local lid = model:FindFirstChild("Lid") :: BasePart?
	local band = model:FindFirstChild("LidBand") :: BasePart?
	local base = model:FindFirstChild("Base") :: BasePart?
	if not (lid and base) then return end
	-- hinged along the back edge (+Z)
	local hinge = lid.CFrame * CFrame.new(0, -lid.Size.Y / 2, lid.Size.Z / 2)
	local open = hinge * CFrame.Angles(math.rad(-105), 0, 0)
	local lidOff = hinge:ToObjectSpace(lid.CFrame)
	TweenService:Create(lid, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = open * lidOff }):Play()
	if band then
		local bandOff = hinge:ToObjectSpace(band.CFrame)
		TweenService:Create(band, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { CFrame = open * bandOff }):Play()
	end
end

local function flash(at: Vector3, color: Color3, size: number)
	local f = Instance.new("Part")
	f.Anchored, f.CanCollide, f.CanQuery, f.CanTouch, f.CastShadow = true, false, false, false, false
	f.Shape = Enum.PartType.Ball
	f.Material = Enum.Material.Neon
	f.Color = color
	f.Size = Vector3.one * 2
	f.CFrame = CFrame.new(at)
	f.Parent = Workspace
	TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(f, 0.6)
	-- a pillar of light in the chest's colour
	local pillar = Instance.new("Part")
	pillar.Anchored, pillar.CanCollide, pillar.CanQuery, pillar.CanTouch, pillar.CastShadow = true, false, false, false, false
	pillar.Material = Enum.Material.Neon
	pillar.Color = color
	pillar.Size = Vector3.new(1.4, 30, 1.4)
	pillar.CFrame = CFrame.new(at + Vector3.new(0, 15, 0))
	pillar.Transparency = 0.4
	pillar.Parent = Workspace
	TweenService:Create(pillar, TweenInfo.new(1.6), { Transparency = 1, Size = Vector3.new(0.2, 40, 0.2) }):Play()
	Debris:AddItem(pillar, 1.7)
end

local placeCommon: (RunChests) -> ()

local function open(rc: RunChests, chest: Chest, opener: Player?)
	if chest.state == "open" then return end
	chest.state = "open"
	local model = chest.model
	local base = model.PrimaryPart
	if not base then return end
	local prompt = base:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt:Destroy() end
	swingLid(model)
	local look = IslandKit.ChestLook[chest.kind] or IslandKit.ChestLook.common
	flash(base.Position + Vector3.new(0, 2, 0), look.glow, if chest.kind == "ritual" then 18 else 10)
	sound(base, SFX.open, 0.8)
	if chest.kind ~= "common" then sound(base, SFX.rare, 0.7) end
	-- everyone of the run near it gets their own share
	local Perks = require(script.Parent:WaitForChild("EquipmentPerks")) :: any
	local given = 0
	-- (a Ritual Chest: everyone who fought its boss, wherever they are now)
	local fought = chest.ctx and chest.ctx.participants
	for _, p in ipairs(IslandMode.Members(rc.runId)) do
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local near = root and (root.Position - base.Position).Magnitude <= LOOT.shareRadius
		if (fought and fought[p.UserId]) or (not fought and near) then
			local msg = roll(rc, p, chest.kind, chest.ctx)
			IslandMode.Notify(rc.runId, msg, p)
			pcall(Perks.OnChestOpened, p)
			given += 1
		end
	end
	if given == 0 and opener then
		IslandMode.Notify(rc.runId, roll(rc, opener, chest.kind, chest.ctx), opener)
	end
	-- it fades, and a common one comes back somewhere else later
	task.delay(8, function()
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then TweenService:Create(d, TweenInfo.new(1.2), { Transparency = 1 }):Play() end
		end
		task.wait(1.3)
		model:Destroy()
		local i = table.find(rc.chests, chest)
		if i then table.remove(rc.chests, i) end
		if chest.spot then rc.usedSpots[chest.spot] = nil end
		if chest.kind == "common" and rc.alive then
			task.delay(IslandConfig.Chests.respawnAfter, function()
				if rc.alive then placeCommon(rc) end
			end)
		end
	end)
end

-- A cursed chest's price: an ambush round it; it opens when they're dead.
local function ambush(rc: RunChests, chest: Chest, opener: Player)
	chest.state = "sealed"
	local model = chest.model
	local base = model.PrimaryPart :: BasePart
	local prompt = base:FindFirstChildOfClass("ProximityPrompt")
	if prompt then prompt.Enabled = false end
	sound(base, SFX.seal, 1)
	flash(base.Position, Color3.fromRGB(220, 40, 90), 26)
	local ring = Instance.new("Part")
	ring.Name = "Seal"
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Shape = Enum.PartType.Cylinder
	ring.Material = Enum.Material.Neon
	ring.Color = Color3.fromRGB(220, 40, 90)
	ring.Transparency = 0.5
	ring.Size = Vector3.new(0.2, 30, 30)
	ring.CFrame = CFrame.new(base.Position - Vector3.new(0, base.Size.Y / 2 - 0.1, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = model
	local st = IslandMode.Of(rc.runId)
	local wave = if st then st.wave else 1
	local A = LOOT.cursedAmbush
	local n = math.min(A.max, math.floor(A.base + A.perWave * wave))
	local island = IslandGenerator.Get(rc.runId)
	local foes: { Model } = {}
	local pool = {}
	-- (the ambush is the chest's own biome's)
	local region = island and island.RegionAt(base.Position)
	for _, a in ipairs(IslandConfig.Enemies) do
		if a.regions and region and not table.find(a.regions, region) then continue end
		if a.from <= math.max(wave, 3) then table.insert(pool, a) end
	end
	if #pool == 0 then
		for _, a in ipairs(IslandConfig.Enemies) do
			if a.from <= 1 then table.insert(pool, a) end
		end
	end
	for i = 1, n do
		local a = pool[rc.rng:NextInteger(1, #pool)]
		local ang = i / n * math.pi * 2
		local at = base.Position + Vector3.new(math.cos(ang), 0, math.sin(ang)) * 13
		local y = island and island.GroundAt(at + Vector3.new(0, 12, 0)) or at.Y
		local m = MobManager.Spawn({
			kind = a.kind, cf = CFrame.new(Vector3.new(at.X, (y or at.Y) + 3, at.Z)), runId = rc.runId,
			elite = i == 1, name = if i == 1 then "Cursed " .. a.name else a.name,
			healthMult = 1 + 0.25 * math.max(0, #IslandMode.Members(rc.runId) - 1),
			attrs = { AggroRange = 120, IslandEnemy = a.id },
		})
		if m then table.insert(foes, m) end
	end
	IslandMode.Notify(rc.runId, { kind = "cursed", by = opener.DisplayName, count = #foes })
	-- open when they're all down (or re-arm if everyone walks away)
	task.spawn(function()
		local t0 = os.clock()
		while rc.alive and chest.state == "sealed" do
			task.wait(0.5)
			local left = 0
			for _, m in ipairs(foes) do
				local hum = m.Parent and m:FindFirstChildOfClass("Humanoid")
				if hum and hum.Health > 0 then left += 1 end
			end
			if left == 0 then
				ring:Destroy()
				open(rc, chest, opener)
				return
			end
			if os.clock() - t0 > 90 then
				local anyone = false
				for _, p in ipairs(IslandMode.Members(rc.runId)) do
					local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
					if root and (root.Position - base.Position).Magnitude < 150 then anyone = true end
				end
				if not anyone then
					for _, m in ipairs(foes) do if m.Parent then m:Destroy() end end
					ring:Destroy()
					chest.state = "closed"
					if prompt then prompt.Enabled = true end
					return
				end
			end
		end
	end)
end

-- ── Placing ─────────────────────────────────────────────────────────────────
function IslandChests.Spawn(runId: string, kind: string, cf: CFrame, ctx: any?, spot: number?): Model?
	local rc = runs[runId]
	if not rc then return nil end
	local model = IslandKit.Chest(kind, cf, rc.folder)
	model:SetAttribute("ChestKind", kind)
	model:SetAttribute("RunId", runId)
	CollectionService:AddTag(model, "IslandChest")
	local chest: Chest = { model = model, kind = kind, state = "closed", spot = spot, ctx = ctx, runId = runId }
	table.insert(rc.chests, chest)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = if kind == "cursed" then "Break the seal" else "Open"
	prompt.ObjectText = CHEST_NAMES[kind] or "Chest"
	prompt.HoldDuration = if kind == "common" then 0.4 elseif kind == "ritual" then 1.2 else 0.8
	prompt.MaxActivationDistance = 11
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.Parent = model.PrimaryPart
	prompt.Triggered:Connect(function(p: Player)
		-- (only someone of this run, on the island, alive)
		if p:GetAttribute("RunId") ~= runId or p:GetAttribute("InLobby") ~= false then return end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or chest.state ~= "closed" then return end
		if kind == "cursed" then ambush(rc, chest, p) else open(rc, chest, p) end
	end)
	return model
end

placeCommon = function(rc: RunChests)
	local island = IslandGenerator.Get(rc.runId)
	if not island then return end
	local free = {}
	for i, spot in ipairs(island.chestSpots) do
		if spot.kind == "common" and not rc.usedSpots[i] and not spot.gone then table.insert(free, i) end
	end
	if #free == 0 then return end
	local i = free[rc.rng:NextInteger(1, #free)]
	rc.usedSpots[i] = true
	IslandChests.Spawn(rc.runId, "common", island.chestSpots[i].cf, nil, i)
end

function IslandChests.DropElite(runId: string, pos: Vector3)
	local island = IslandGenerator.Get(runId)
	local y = island and island.GroundAt(pos + Vector3.new(0, 10, 0)) or pos.Y - 3
	local model = IslandChests.Spawn(runId, "elite", CFrame.new(pos.X, y or (pos.Y - 3), pos.Z))
	if model and model.PrimaryPart then flash(model.PrimaryPart.Position, Color3.fromRGB(200, 120, 255), 12) end
end

function IslandChests.Start(runId: string)
	local island = IslandGenerator.Get(runId)
	if not island then return end
	local folder = Instance.new("Folder")
	folder.Name = "Chests"
	folder.Parent = island.folder
	local rc: RunChests = { runId = runId, folder = folder, chests = {}, usedSpots = {}, alive = true, rng = Random.new() }
	runs[runId] = rc
	for i, spot in ipairs(island.chestSpots) do
		rc.usedSpots[i] = true
		IslandChests.Spawn(runId, spot.kind, spot.cf, nil, i)
	end
end

-- The next isle raised: the last one's chests gone with it, its own chest
-- spots (from `first` on) filled.
function IslandChests.AddSpots(runId: string, first: number)
	local rc = runs[runId]
	local island = IslandGenerator.Get(runId)
	if not rc or not island then return end
	for i = #rc.chests, 1, -1 do
		local c = rc.chests[i]
		local spot = c.spot and island.chestSpots[c.spot]
		if not spot or spot.gone then
			if c.model.Parent then c.model:Destroy() end
			table.remove(rc.chests, i)
		end
	end
	for i = first, #island.chestSpots do
		local spot = island.chestSpots[i]
		if not rc.usedSpots[i] and not spot.gone then
			rc.usedSpots[i] = true
			IslandChests.Spawn(runId, spot.kind, spot.cf, nil, i)
		end
	end
end

function IslandChests.Stop(runId: string)
	local rc = runs[runId]
	if not rc then return end
	rc.alive = false
	runs[runId] = nil
end

return IslandChests
