--!strict
--[[
	DevHooks.luau
	Studio-only test hooks (never in a live server), so a test can grant tomes
	and relics, force drops, set the Corruption, start a horde or jump floors
	without playing there. A command is an attribute on ServerStorage.DevHooks
	(a Folder): set "Cmd" to "name|a|b"; the answer appears in "Result".
	(An attribute, not a BindableFunction: the Studio test tools may set
	properties but not invoke the game's functions.)

	  tome|userId|tomeId         a level of a tome / boon
	  relics|userId              a relic choice
	  drop|userId|rarity         a gear drop
	  corruption|runId|level     set it (wakes it)
	  horde|runId                a horde, now
	  descend|runId              straight to the next floor
	  extract|runId              the party extracts
	  rides|userId               every pair of wings and every mount, owned
	                             (their two sets marked done, no payout)
	  gear|userId                every Armory weapon finish, aura and title, owned
	  ride|userId|on             call the mount (on = 1) or send it away (0)
	  hit|userId|damage          a hit on the player (thrown off a mount)
	  souls|userId|amount        souls given (or taken, negative)
	  boss|userId|kind           the player's run's boss made a `kind`
	                             (BossAI.Kinds), the player put in its arena
	                             (sent into a run first if in the lobby; set
	                             "DevMove" on the boss model to call a move)
	  tower|userId|radius        an immunity tower (ImmunityTower) on the floor
	                             16 studs in front of the player
	  ready|userId               every skill off cooldown, the class meters
	                             full (Rage, Qi Charge, ...): ults on demand
	The Forgotten Isle:
	  isle_gear|userId|itemId    a piece of gear into their bag (EquipmentData)
	  isle_equip|userId|itemId   ... and put it on
	  isle_chest|userId|kind     a chest 10 studs in front of them
	  isle_state|userId          their island state: wave, enemies, level, gear, stats
	  isle_ritual|userId|bossId  wake the altar now (a boss id, or random)
	  isle_event|userId|eventId  start one of the island's events now (IslandConfig.Events)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevHooks = {}

function DevHooks.Init()
	if not RunService:IsStudio() then return end
	local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
	local folder = Instance.new("Folder")
	folder.Name = "DevHooks"
	local function run(cmd: string, a: any, b: any): any
		local function plr(id: any): Player?
			return Players:GetPlayerByUserId(tonumber(id) or 0)
		end
		if cmd == "tome" then
			local p = plr(a)
			local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
			local t = p and PlayerStats.GrantTome(p, b)
			return if t then t.name else "none"
		elseif cmd == "relics" then
			local p = plr(a)
			local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
			return p and PlayerStats.OfferRelics(p)
		elseif cmd == "drop" then
			local p = plr(a)
			local LootManager = require(script.Parent:WaitForChild("LootManager")) :: any
			return p and LootManager.Drop(p, "dev", nil, b)
		elseif cmd == "corruption" then
			RunScope.Set(a, "CorruptionActive", true)
			RunScope.Set(a, "CorruptionSince", RunScope.Get(a, "RunElapsed") or 0)
			RunScope.Set(a, "CorruptionFloors", tonumber(b) or 0)
			return true
		elseif cmd == "souls" then
			local p = plr(a)
			local PlayerData = require(script.Parent:WaitForChild("PlayerData")) :: any
			local TalentManager = require(script.Parent:WaitForChild("TalentManager")) :: any
			local prof = p and PlayerData.Get(p)
			if not prof then return "no profile" end
			prof.souls = math.max(0, prof.souls + (tonumber(b) or 0))
			PlayerData.MarkDirty(p)
			TalentManager.Sync(p)
			return prof.souls
		elseif cmd == "horde" then
			-- (the next tick starts it)
			RunScope.Set(a, "DevHordeNow", true)
			return true
		elseif cmd == "descend" then
			local DungeonGenerator = require(script.Parent:WaitForChild("DungeonGenerator")) :: any
			task.spawn(DungeonGenerator.NextLevel, a)
			return true
		elseif cmd == "extract" then
			local DungeonGenerator = require(script.Parent:WaitForChild("DungeonGenerator")) :: any
			local hook = DungeonGenerator.Hooks.extract
			if hook then task.spawn(hook, a, {}) end
			return hook ~= nil
		elseif cmd == "isle_gear" or cmd == "isle_equip" then
			local p = plr(a)
			local EquipmentManager = require(script.Parent:WaitForChild("EquipmentManager")) :: any
			local item = p and EquipmentManager.Grant(p, b)
			if not item then return "no such item" end
			if cmd == "isle_equip" then
				-- (the newest piece in the bag)
				for uid = 200, 1, -1 do
					if EquipmentManager.Equip(p, uid) then break end
				end
			end
			return item.name
		elseif cmd == "isle_chest" then
			local p = plr(a)
			local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then return "no character" end
			local IslandChests = require(script.Parent:WaitForChild("IslandChests")) :: any
			local at = root.Position + root.CFrame.LookVector * 10
			local IslandGenerator = require(script.Parent:WaitForChild("IslandGenerator")) :: any
			local island = IslandGenerator.Get(p:GetAttribute("RunId"))
			local y = island and island.GroundAt(at + Vector3.new(0, 10, 0)) or (at.Y - 3)
			local m = IslandChests.Spawn(p:GetAttribute("RunId"), b or "rare", CFrame.lookAt(Vector3.new(at.X, y, at.Z), Vector3.new(root.Position.X, y, root.Position.Z)))
			return m and m:GetFullName()
		elseif cmd == "isle_state" then
			local p = plr(a)
			if not p then return "no player" end
			local IslandMode = require(script.Parent:WaitForChild("IslandMode")) :: any
			local EquipmentManager = require(script.Parent:WaitForChild("EquipmentManager")) :: any
			local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
			local st = IslandMode.Of(p:GetAttribute("RunId"))
			local eq = {}
			for slot, id in pairs(EquipmentManager.Equipped(p)) do table.insert(eq, slot .. "=" .. id) end
			local stats = {}
			for _, k in ipairs({ "damage", "maxHealth", "armor", "evasion", "critChance", "critDamage", "abilityDamage", "movementSpeed", "basicAttackSpeed", "luck", "shield" }) do
				table.insert(stats, k .. "=" .. string.format("%.3g", PlayerStats.GetStat(p, k)))
			end
			local alive = 0
			if st then for _ in pairs(st.enemies) do alive += 1 end end
			return string.format("wave=%s alive=%d level=%s xp=%s/%s gear={%s} stats={%s}", st and st.wave or "-", alive,
				tostring(p:GetAttribute("IslandLevel")), tostring(p:GetAttribute("IslandXP")), tostring(p:GetAttribute("IslandXPNext")),
				table.concat(eq, " "), table.concat(stats, " "))
		elseif cmd == "isle_ritual" then
			local p = plr(a)
			local ritual = script.Parent:FindFirstChild("IslandRitual")
			if not (p and ritual) then return "no ritual" end
			return (require(ritual) :: any).Begin(p:GetAttribute("RunId"), p, b, true)
		elseif cmd == "isle_event" then
			local p = plr(a)
			local events = script.Parent:FindFirstChild("IslandEvents")
			if not (p and events) then return "no events" end
			return (require(events) :: any).Force(p:GetAttribute("RunId"), b)
		elseif cmd == "traps" then
			-- one of each new trap round the player (Hazards.Showcase)
			local p = plr(a)
			local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then return "no character" end
			local Hazards = require(script.Parent:WaitForChild("Hazards")) :: any
			local rp = RaycastParams.new()
			rp.FilterType = Enum.RaycastFilterType.Exclude
			rp.FilterDescendantsInstances = { p.Character :: Model }
			local hit = workspace:Raycast(root.Position, Vector3.new(0, -20, 0), rp)
			local floor = if hit then hit.Position else root.Position - Vector3.new(0, 3, 0)
			Hazards.Showcase(floor, workspace, p:GetAttribute("RunId"))
			return "placed"
		elseif cmd == "rides" then
			local p = plr(a)
			local PlayerData = require(script.Parent:WaitForChild("PlayerData")) :: any
			local GachaManager = require(script.Parent:WaitForChild("GachaManager")) :: any
			local GachaRewards = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GachaRewards")) :: any
			local prof = p and PlayerData.Get(p)
			if not prof then return "no profile" end
			local n = 0
			for _, r in ipairs(GachaRewards.All) do
				if (r.type == "wings" or r.type == "mount") and not prof.collection.cosmetics[r.id] then
					prof.collection.cosmetics[r.id] = true
					n += 1
				end
			end
			prof.stats["set:set_skyborne"] = prof.stats["set:set_skyborne"] or 1
			prof.stats["set:set_beastmaster"] = prof.stats["set:set_beastmaster"] or 1
			PlayerData.MarkDirty(p)
			GachaManager.Sync(p)
			return `{n} granted`
		elseif cmd == "gear" then
			local p = plr(a)
			local PlayerData = require(script.Parent:WaitForChild("PlayerData")) :: any
			local LootManager = require(script.Parent:WaitForChild("LootManager")) :: any
			local GearData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GearData")) :: any
			local prof = p and PlayerData.Get(p)
			if not prof then return "no profile" end
			if typeof(prof.gear) ~= "table" then prof.gear = { owned = {}, equipped = {} } end
			prof.gear.owned = prof.gear.owned or {}
			prof.gear.equipped = prof.gear.equipped or {}
			local n = 0
			for _, item in ipairs(GearData.Items) do
				if (prof.gear.owned[item.id] or 0) <= 0 then
					prof.gear.owned[item.id] = 1
					n += 1
				end
			end
			PlayerData.MarkDirty(p)
			LootManager.Sync(p)
			return `{n} granted`
		elseif cmd == "ride" then
			local p = plr(a)
			local MountManager = require(script.Parent:WaitForChild("MountManager")) :: any
			if p then MountManager.Request(p, b == "1") end
			return p and p.Character and p.Character:GetAttribute("Riding")
		elseif cmd == "hit" then
			local p = plr(a)
			local hum = p and p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			if hum then hum:TakeDamage(tonumber(b) or 5) end
			return hum and hum.Health
		elseif cmd == "enter" then
			-- (straight from the lobby into a run, as the campfire's portal would)
			local p = plr(a)
			if not p then return "no player" end
			local ClassManager = require(script.Parent:WaitForChild("ClassManager")) :: any
			local classId = b or p:GetAttribute("SelectedClass") or "swordsman"
			ClassManager.SetClass(p, classId) -- (recorded first, as picking it on the screen would)
			ClassManager.Enter(p, classId)
			return true
		elseif cmd == "boss" then
			local p = plr(a)
			if not p then return "no player" end
			if p:GetAttribute("InLobby") ~= false then
				-- (in the lobby: into a run first, as the campfire's portal would)
				local ClassManager = require(script.Parent:WaitForChild("ClassManager")) :: any
				ClassManager.Enter(p, p:GetAttribute("SelectedClass") or "swordsman")
				local t0 = os.clock()
				while p:GetAttribute("InLobby") ~= false and os.clock() - t0 < 30 do task.wait(0.2) end
			end
			local runId = p:GetAttribute("RunId")
			if typeof(runId) ~= "string" then return "not in a run" end
			local MobManager = require(script.Parent:WaitForChild("MobManager")) :: any
			local mid = MobManager.DevBoss(runId, b or "fallen_angel")
			if not mid then return "no boss room" end
			local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			-- (off the arena's cross, where its flame vents are)
			if root then root.CFrame = CFrame.new(mid + Vector3.new(30, 5, 16)) end
			return mid
		elseif cmd == "ready" then
			local p = plr(a)
			if not p then return "no player" end
			local SkillManager = require(script.Parent:WaitForChild("SkillManager")) :: any
			SkillManager.DevResetCooldowns(p)
			-- (the meters some ults wait on)
			for _, name in ipairs({ "BR_Rage", "MA_Charge", "FK_Heat", "UltCharge" }) do
				if p:GetAttribute(name) ~= nil then p:SetAttribute(name, 100) end
			end
			return true
		elseif cmd == "tower" then
			local p = plr(a)
			local char = p and p.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not (char and root) then return "no character" end
			local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z).Unit
			local at = root.Position + look * 16
			local rp = RaycastParams.new()
			rp.FilterDescendantsInstances = { char }
			local hit = workspace:Raycast(at + Vector3.new(0, 4, 0), Vector3.new(0, -40, 0), rp)
			local floor = if hit then hit.Position else at - Vector3.new(0, 3, 0)
			local ImmunityTower = require(script.Parent:WaitForChild("ImmunityTower")) :: any
			ImmunityTower.Spawn(CFrame.lookAt(floor, floor - look), { radius = tonumber(b) })
			return floor
		end
		return "unknown command"
	end
	folder:GetAttributeChangedSignal("Cmd"):Connect(function()
		local line = folder:GetAttribute("Cmd")
		if typeof(line) ~= "string" or line == "" then return end
		local parts = string.split(line, "|")
		local ok, res = pcall(run, parts[1], parts[2], parts[3])
		folder:SetAttribute("Result", (if ok then "ok: " else "error: ") .. tostring(res))
		folder:SetAttribute("Cmd", "")
	end)
	folder.Parent = ServerStorage
	print("[DevHooks] Studio test hooks ready (ServerStorage.DevHooks).")
end

return DevHooks
