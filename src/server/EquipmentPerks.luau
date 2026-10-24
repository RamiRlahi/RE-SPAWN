--!strict
--[[
	EquipmentPerks.luau
	What the Forgotten Isle's gear perks (EquipmentData) actually do, on the
	server. Every number they use is the item's own (EquipmentData), read
	through EquipmentManager.Perk; nothing here is balanced in place.

	Where they plug in:
	  SkillManager.dealDamage   DamageMult (before the crit roll), ForceCrit,
	                            CritBonus, then OnHit after the hit lands
	  SkillManager (a cast)     OnCast
	  Dash.luau                 OnDash
	  MobManager                an incoming-damage hook and a dodge hook
	  IslandChests              OnChestOpened
	  Humanoid.HealthChanged    Heartroot's stronger healing

	Timed buffs are tome effects for a while (PlayerStats.SetExtraEffects
	"perk_<id>"), shields the Shield Tome's way (extra max health, arriving
	full). Perk damage (explosions, chains, poison, waves) is dealt as its own
	source and never sets off another perk, so nothing loops; every perk that
	could fire too often has its own cooldown.

	Every hit a player takes also passes their Armor (damage ÷ armor) and
	their Evasion (that chance to take none of it): the Armor and Evasion
	Tomes, which nothing applied before.

	Feedback: each perk that fires tells its owner (IslandEvent "perk") and
	shows (a burst of light where it happens).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EquipmentData = require(Shared:WaitForChild("EquipmentData"))
local Network = require(Shared:WaitForChild("Network"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))
local EquipmentManager = require(script.Parent:WaitForChild("EquipmentManager"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))

local EquipmentPerks = {}

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type Deps = {
	dealDamage: (Player, Target, number, string, any?) -> (number?, boolean?),
	targets: (Model) -> { Target },
	reduceCooldown: (Player, number, number) -> (),
}
local deps: Deps? = nil

-- Damage the perks deal themselves: never sets off another perk.
local PERK_SOURCES = { ["EMBER BURST"] = true, ["CHAIN LIGHTNING"] = true, ["ARCANE ECHO"] = true, POISON = true,
	["TIDAL WAVE"] = true, ["MAGMA CORE"] = true }

type Streak = { n: number, t: number }
type PState = {
	hits: Streak, basic: Streak, melee: Streak, sixth: Streak,
	casts: number,
	cooldowns: { [string]: number },
	buffTokens: { [string]: number },
	lastDash: number,
	riftMarks: { [Model]: number },
	soulkeeperUsed: boolean,
	killHeal: { t: number, healed: number },
}
local states: { [Player]: PState } = {}

local function stateOf(p: Player): PState
	local s = states[p]
	if not s then
		s = {
			hits = { n = 0, t = 0 }, basic = { n = 0, t = 0 }, melee = { n = 0, t = 0 }, sixth = { n = 0, t = 0 },
			casts = 0, cooldowns = {}, buffTokens = {}, lastDash = 0, riftMarks = {}, soulkeeperUsed = false,
			killHeal = { t = 0, healed = 0 },
		}
		states[p] = s
	end
	return s :: PState
end

local function ready(s: PState, key: string, cooldown: number?): boolean
	local now = os.clock()
	if (s.cooldowns[key] or 0) > now then return false end
	s.cooldowns[key] = now + (cooldown or 0)
	return true
end

local function bump(st: Streak, window: number): number
	local now = os.clock()
	if now - st.t > window then st.n = 0 end
	st.n += 1
	st.t = now
	return st.n
end

-- A buff of tome effects for `duration` seconds (a fresh one replaces it).
local function buff(p: Player, key: string, effects: { any }, duration: number)
	local s = stateOf(p)
	local token = (s.buffTokens[key] or 0) + 1
	s.buffTokens[key] = token
	PlayerStats.SetExtraEffects(p, "perk_" .. key, effects)
	task.delay(duration, function()
		if s.buffTokens[key] == token and p.Parent then PlayerStats.SetExtraEffects(p, "perk_" .. key, nil) end
	end)
end

local function maxHealth(p: Player): number
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	return if hum then hum.MaxHealth else 100
end

-- A shield: extra health that arrives full and goes when it ends.
local function shield(p: Player, key: string, fraction: number, duration: number)
	buff(p, key, { { stat = "shield", operation = "add", value = math.floor(maxHealth(p) * fraction) } }, duration)
end

local function say(p: Player, id: string, text: string)
	Network.GetRemoteEvent(Network.Remotes.IslandEvent):FireClient(p, { kind = "perk", id = id, text = text })
end

-- ── Visuals (budgeted: a few a second each) ─────────────────────────────────
local fxCount: { [Player]: { n: number, t: number } } = {}
local function fxAllowed(p: Player): boolean
	local now = os.clock()
	local c = fxCount[p]
	if not c or now - c.t > 1 then
		c = { n = 0, t = now }
		fxCount[p] = c
	end
	c.n += 1
	return c.n <= 6
end
local fxFolder: Folder? = nil
local function folder(): Folder
	if fxFolder and fxFolder.Parent then return fxFolder end
	local f = Instance.new("Folder")
	f.Name = "PerkFX"
	f.Parent = Workspace
	fxFolder = f
	return f
end
local function burst(p: Player, at: Vector3, radius: number, color: Color3)
	if not fxAllowed(p) then return end
	local ring = Instance.new("Part")
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Shape = Enum.PartType.Ball
	ring.Material = Enum.Material.Neon
	ring.Color = color
	ring.Transparency = 0.35
	ring.Size = Vector3.one * 1.5
	ring.CFrame = CFrame.new(at)
	ring.Parent = folder()
	TweenService:Create(ring, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.4)
end
local function zap(p: Player, a: Vector3, b: Vector3, color: Color3)
	if not fxAllowed(p) then return end
	local l = (b - a).Magnitude
	local bolt = Instance.new("Part")
	bolt.Anchored, bolt.CanCollide, bolt.CanQuery, bolt.CanTouch, bolt.CastShadow = true, false, false, false, false
	bolt.Material = Enum.Material.Neon
	bolt.Color = color
	bolt.Size = Vector3.new(0.35, 0.35, l)
	bolt.CFrame = CFrame.lookAt((a + b) / 2, b)
	bolt.Parent = folder()
	TweenService:Create(bolt, TweenInfo.new(0.25), { Transparency = 1, Size = Vector3.new(0.05, 0.05, l) }):Play()
	Debris:AddItem(bolt, 0.3)
end

local function isBossOrElite(c: Model): boolean
	return c:GetAttribute("IsBoss") == true or c:GetAttribute("IsElite") == true or c:GetAttribute("Behemoth") == true
end

local function around(p: Player, at: Vector3, radius: number, except: Model?): { Target }
	local out = {}
	local d = deps
	local char = p.Character
	if not d or not char then return out end
	for _, t in ipairs(d.targets(char)) do
		if t.character ~= except and t.humanoid.Health > 0 and (t.rootPart.Position - at).Magnitude <= radius then table.insert(out, t) end
	end
	return out
end

-- ── Poison (Plaguewood Longbow, Thornmother's Grasp) ────────────────────────
type Poison = { stacks: number, until_: number, perStack: number, target: Target }
local poisons: { [Player]: { [Model]: Poison } } = {}
local function poison(p: Player, t: Target, perk: any)
	local list = poisons[p] or {}
	poisons[p] = list
	local cur = list[t.character]
	local now = os.clock()
	if cur and cur.until_ > now then
		cur.stacks = math.min(cur.stacks + 1, perk.maxStacks)
		cur.until_ = now + perk.duration
		cur.perStack = math.max(cur.perStack, perk.perStack)
	else
		list[t.character] = { stacks = 1, until_ = now + perk.duration, perStack = perk.perStack, target = t }
	end
end

-- ── Outgoing (SkillManager.dealDamage) ──────────────────────────────────────
-- × a hit's damage, before the crit roll.
function EquipmentPerks.DamageMult(p: Player, t: Target, source: string): number
	if PERK_SOURCES[source] then return 1 end
	local s = stateOf(p)
	local mult = 1
	local hum = t.humanoid
	local ratio = if hum.MaxHealth > 0 then hum.Health / hum.MaxHealth else 1
	local perk = EquipmentManager.Perk(p, "heavy_opener")
	if perk and EquipmentData.IsHeavy(source) and ratio > perk.threshold then mult += perk.bonus end
	perk = EquipmentManager.Perk(p, "hunter")
	if perk and isBossOrElite(t.character) then mult += perk.bonus end
	perk = EquipmentManager.Perk(p, "riftwalk")
	if perk and (s.riftMarks[t.character] or 0) > os.clock() then mult += perk.bonus end
	perk = EquipmentManager.Perk(p, "fifth_hit")
	if perk and bump(s.hits, perk.window) % perk.every == 0 then
		mult += perk.bonus
		-- a normal enemy staggers under it
		if not isBossOrElite(t.character) then
			t.character:SetAttribute("StaggerUntil", math.max(t.character:GetAttribute("StaggerUntil") or 0, os.clock() + perk.stagger))
		end
		burst(p, t.rootPart.Position, 4, Color3.fromRGB(255, 230, 160))
	end
	return mult
end

-- A guaranteed critical (the Riftbound Blade's first hit after a dash).
function EquipmentPerks.ForceCrit(p: Player, source: string): boolean
	if PERK_SOURCES[source] then return false end
	local perk = EquipmentManager.Perk(p, "rift_strike")
	local s = stateOf(p)
	if perk and s.lastDash > 0 and os.clock() - s.lastDash <= perk.window then
		s.lastDash = 0
		return true
	end
	return false
end

-- Added to a critical hit's multiplier (on top of ×1.5 + Crit Damage).
function EquipmentPerks.CritBonus(p: Player, t: Target): number
	local perk = EquipmentManager.Perk(p, "eclipse")
	local hum = t.humanoid
	if perk and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth < perk.below then return perk.bonus end
	return 0
end

function EquipmentPerks.OnHit(p: Player, t: Target, dealt: number, source: string, isCrit: boolean, killed: boolean)
	local d = deps
	if not d then return end
	local s = stateOf(p)
	local char = p.Character
	if killed then
		-- Leech Tome: a share of max health per kill, at most 8% a second
		local heal = PlayerStats.GetStat(p, "killHeal")
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if heal > 0 and hum and hum.Health > 0 then
			local now = os.clock()
			if now - s.killHeal.t > 1 then s.killHeal = { t = now, healed = 0 } end
			local amount = math.min(hum.MaxHealth * heal, hum.MaxHealth * 0.08 - s.killHeal.healed)
			if amount > 0 then
				s.killHeal.healed += amount
				hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
			end
		end
		if isBossOrElite(t.character) then
			local perk = EquipmentManager.Perk(p, "elite_fury")
			if perk then
				buff(p, "elite_fury", { { stat = "damage", operation = "multiplier", value = perk.bonus } }, perk.duration)
				say(p, "elite_fury", `+{math.floor(perk.bonus * 100)}% damage`)
			end
			perk = EquipmentManager.Perk(p, "crown_ult")
			if perk then
				d.reduceCooldown(p, 4, perk.seconds)
				say(p, "crown_ult", `Ultimate -{perk.seconds}s`)
			end
		end
	end
	if PERK_SOURCES[source] then return end
	local basic = EquipmentData.BASIC[source] == true
	local dot = EquipmentData.DOT[source] == true
	-- streaks of basic hits
	if basic then
		local perk = EquipmentManager.Perk(p, "thrust_rush")
		if perk and bump(s.basic, perk.window) >= perk.hits and ready(s, "thrust_rush", perk.cooldown) then
			s.basic.n = 0
			buff(p, "thrust_rush", { { stat = "movementSpeed", operation = "percent", value = perk.speed } }, perk.duration)
			say(p, "thrust_rush", "Swift!")
		end
		perk = EquipmentManager.Perk(p, "gravegrip")
		if perk and EquipmentData.MELEE[source] then
			local n = math.min(bump(s.melee, perk.window), perk.maxStacks)
			buff(p, "gravegrip", { { stat = "basicAttackSpeed", operation = "percent", value = perk.perStack * n } }, perk.window)
		end
	end
	-- the Tidebreaker's wave: every sixth hit
	local perk = EquipmentManager.Perk(p, "tidal_wave")
	if perk and char and bump(s.sixth, perk.window) % perk.every == 0 then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			burst(p, root.Position, perk.radius, Color3.fromRGB(80, 200, 255))
			for _, o in ipairs(around(p, root.Position, perk.radius)) do d.dealDamage(p, o, dealt * perk.share, "TIDAL WAVE") end
		end
	end
	-- poison
	perk = EquipmentManager.Perk(p, "crit_poison")
	if perk and isCrit then poison(p, t, perk) end
	perk = EquipmentManager.Perk(p, "thorn_venom")
	if perk then poison(p, t, perk) end
	-- damage over time → ability damage for a while
	perk = EquipmentManager.Perk(p, "venom_focus")
	if perk and dot then
		buff(p, "venom_focus", { { stat = "abilityDamage", operation = "percent", value = perk.bonus } }, perk.duration)
	end
	-- a crit's chance to explode
	perk = EquipmentManager.Perk(p, "ember_burst")
	if perk and isCrit and math.random() < perk.chance and ready(s, "ember_burst", perk.cooldown) then
		burst(p, t.rootPart.Position, perk.radius, Color3.fromRGB(255, 120, 40))
		for _, o in ipairs(around(p, t.rootPart.Position, perk.radius, t.character)) do d.dealDamage(p, o, dealt * perk.share, "EMBER BURST") end
	end
	-- an ability hit's chance to chain lightning
	perk = EquipmentManager.Perk(p, "tempest")
	if perk and not basic and not dot and math.random() < perk.chance and ready(s, "tempest", perk.cooldown) then
		local from = t.rootPart.Position
		local hit: { [Model]: boolean } = { [t.character] = true }
		for _ = 1, perk.bounces do
			local best, bd = nil, perk.range
			for _, o in ipairs(around(p, from, perk.range)) do
				if not hit[o.character] then
					local dist = (o.rootPart.Position - from).Magnitude
					if dist < bd then best, bd = o, dist end
				end
			end
			if not best then break end
			hit[best.character] = true
			zap(p, from, best.rootPart.Position, Color3.fromRGB(150, 200, 255))
			d.dealDamage(p, best, dealt * perk.share, "CHAIN LIGHTNING")
			from = best.rootPart.Position
		end
	end
end

-- ── Casting ─────────────────────────────────────────────────────────────────
function EquipmentPerks.OnCast(p: Player, _skillIndex: number)
	local d = deps
	local char = p.Character
	if not d or not char then return end
	local s = stateOf(p)
	s.casts += 1
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local perk = EquipmentManager.Perk(p, "arcane_echo")
	if perk and root and s.casts % perk.every == 0 then
		local best, bd = nil, perk.range
		for _, t in ipairs(d.targets(char)) do
			local dist = (t.rootPart.Position - root.Position).Magnitude
			if t.humanoid.Health > 0 and dist < bd then best, bd = t, dist end
		end
		if best then
			zap(p, root.Position + Vector3.new(0, 2, 0), best.rootPart.Position, Color3.fromRGB(190, 120, 255))
			local dmg = perk.damage * PlayerStats.GetStat(p, "damage") * PlayerStats.GetStat(p, "abilityDamage")
			d.dealDamage(p, best, dmg, "ARCANE ECHO")
		end
	end
	perk = EquipmentManager.Perk(p, "rift_shield")
	if perk and s.casts % perk.every == 0 then
		shield(p, "rift_shield", perk.shield, perk.duration)
		say(p, "rift_shield", "Riftglass shield")
	end
	perk = EquipmentManager.Perk(p, "halo")
	if perk then
		local hum = char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * perk.heal) end
	end
end

-- ── Dashing (Dash.luau) ─────────────────────────────────────────────────────
function EquipmentPerks.OnDash(p: Player)
	local s = stateOf(p)
	s.lastDash = os.clock()
	local perk = EquipmentManager.Perk(p, "riftwalk")
	if not perk then return end
	-- the enemies it passes through, through the dash
	task.spawn(function()
		for _ = 1, 6 do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				for _, t in ipairs(around(p, root.Position, perk.radius)) do
					if not s.riftMarks[t.character] or s.riftMarks[t.character] < os.clock() then
						burst(p, t.rootPart.Position, 2.5, Color3.fromRGB(170, 90, 255))
					end
					s.riftMarks[t.character] = os.clock() + perk.duration
				end
			end
			task.wait(0.05)
		end
	end)
end

-- ── Chests (IslandChests) ───────────────────────────────────────────────────
function EquipmentPerks.OnChestOpened(p: Player)
	local perk = EquipmentManager.Perk(p, "wayfarer")
	if perk then
		buff(p, "wayfarer", { { stat = "movementSpeed", operation = "percent", value = perk.speed } }, perk.duration)
		say(p, "wayfarer", "Wayfarer's stride")
	end
end

-- How strongly a consumable heals this player (Greedbound Coin's price).
function EquipmentPerks.HealMult(p: Player): number
	local perk = EquipmentManager.Perk(p, "greed")
	return if perk then perk.healMult else 1
end

-- ── Incoming ────────────────────────────────────────────────────────────────
local function isRanged(attacker: Model?): boolean
	if not attacker then return false end
	local mt = attacker:GetAttribute("MobType")
	return (mt ~= nil and mt ~= "Melee") or attacker:GetAttribute("PreferredRange") ~= nil
end

local function incomingHook(p: Player, char: Model, damage: number, attacker: Model?, fromBoss: boolean?): number
	if damage <= 0 then return damage end
	local s = stateOf(p)
	-- Evasion: none of it at all
	local evasion = math.min(PlayerStats.GetStat(p, "evasion"), 0.6)
	if evasion > 0 and math.random() < evasion then
		local perk = EquipmentManager.Perk(p, "dodge_crit")
		if perk and ready(s, "dodge_crit", perk.cooldown) then
			buff(p, "dodge_crit", { { stat = "critChance", operation = "percent", value = perk.crit } }, perk.duration)
		end
		say(p, "evade", "Evaded")
		return 0
	end
	-- Armor
	local armor = PlayerStats.GetStat(p, "armor")
	if armor > 1 then damage /= armor end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local max = if hum then hum.MaxHealth else 100
	local perk = EquipmentManager.Perk(p, "last_stand")
	if perk and hum and hum.Health / max < perk.below then damage *= 1 - perk.reduction end
	perk = EquipmentManager.Perk(p, "dragonhide")
	if perk and (fromBoss or (attacker and attacker:GetAttribute("IsBoss") == true)) then damage *= 1 - perk.reduction end
	perk = EquipmentManager.Perk(p, "arrow_ward")
	if perk and isRanged(attacker) then damage *= 1 - perk.reduction end
	if (s.cooldowns.soulkeeper_dr or 0) > os.clock() then
		local sk = EquipmentManager.Perk(p, "soulkeeper")
		if sk then damage *= 1 - sk.reduction end
	end
	-- Soulkeeper Relic: once a run, a killing blow leaves you standing
	perk = EquipmentManager.Perk(p, "soulkeeper")
	if perk and hum and not s.soulkeeperUsed and damage >= hum.Health then
		s.soulkeeperUsed = true
		damage = math.max(0, hum.Health - max * perk.health)
		s.cooldowns.soulkeeper_dr = os.clock() + perk.duration
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then burst(p, root.Position, 8, Color3.fromRGB(150, 255, 220)) end
		say(p, "soulkeeper", "The Soulkeeper holds you back")
	end
	-- Bastion Plate: a heavy blow raises a shield
	perk = EquipmentManager.Perk(p, "bulwark")
	if perk and damage >= max * perk.threshold and ready(s, "bulwark", perk.cooldown) then
		task.defer(shield, p, "bulwark", perk.shield, perk.duration)
		say(p, "bulwark", "Bulwark!")
	end
	-- the Molten Colossus Core: fire round you when you're hit
	perk = EquipmentManager.Perk(p, "magma_core")
	if perk and ready(s, "magma_core", perk.cooldown) and deps then
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local d = deps :: Deps
			local at = root.Position
			task.defer(function()
				burst(p, at, perk.radius, Color3.fromRGB(255, 90, 30))
				for _, t in ipairs(around(p, at, perk.radius)) do d.dealDamage(p, t, perk.damage, "MAGMA CORE") end
			end)
		end
	end
	return damage
end

local function dodgeHook(p: Player, _attacker: Model?)
	local perk = EquipmentManager.Perk(p, "dodge_crit")
	local s = stateOf(p)
	if perk and ready(s, "dodge_crit", perk.cooldown) then
		buff(p, "dodge_crit", { { stat = "critChance", operation = "percent", value = perk.crit } }, perk.duration)
		say(p, "dodge_crit", "Perfect dodge: +crit")
	end
end

-- ── Heartroot (stronger healing outside boss fights) ────────────────────────
local function watchHealing(p: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	local last = hum.Health
	local adding = false
	hum.HealthChanged:Connect(function(h: number)
		local delta = h - last
		last = h
		if adding or delta <= 0 or h <= 0 then return end
		local perk = EquipmentManager.Perk(p, "heartroot")
		if not perk then return end
		local runId = p:GetAttribute("RunId")
		local RunScope = require(Shared:WaitForChild("RunScope")) :: any
		if typeof(runId) == "string" and RunScope.Get(runId, "IslandBossActive") == true then return end
		adding = true
		hum.Health = math.min(hum.MaxHealth, hum.Health + delta * perk.bonus)
		last = hum.Health
		adding = false
	end)
end

-- ── Start ───────────────────────────────────────────────────────────────────
function EquipmentPerks.SetDeps(d: Deps)
	deps = d
end

function EquipmentPerks.Init()
	MobManager.AddIncomingHook(incomingHook)
	MobManager.AddDodgeHook(dodgeHook)
	local function hook(p: Player)
		p.CharacterAdded:Connect(function(c) watchHealing(p, c) end)
		if p.Character then task.spawn(watchHealing, p, p.Character) end
		-- a new run: the relic's one save back, the counters fresh
		p:GetAttributeChangedSignal("RunId"):Connect(function() states[p] = nil end)
	end
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerAdded:Connect(hook)
	Players.PlayerRemoving:Connect(function(p)
		states[p] = nil
		poisons[p] = nil
		fxCount[p] = nil
	end)
	-- the poison ticks
	task.spawn(function()
		while true do
			task.wait(0.5)
			local d = deps
			if d then
				local now = os.clock()
				for p, list in pairs(poisons) do
					for model, po in pairs(list) do
						if po.until_ < now or not model.Parent or po.target.humanoid.Health <= 0 or not p.Parent then
							list[model] = nil
						else
							d.dealDamage(p, po.target, po.stacks * po.perStack, "POISON")
						end
					end
				end
			end
		end
	end)
	-- (the Riftwalker's marks: forget the dead and the long-gone)
	task.spawn(function()
		while true do
			task.wait(5)
			local now = os.clock()
			for _, s in pairs(states) do
				for m, t in pairs(s.riftMarks) do
					if t < now or not m.Parent then s.riftMarks[m] = nil end
				end
			end
		end
	end)
end

return EquipmentPerks
