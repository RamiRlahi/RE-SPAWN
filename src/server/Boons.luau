--!strict
--[[
	Boons.luau
	What the run's boons (TomeData, category "Boon") and their evolutions do.
	Every hit a player lands goes through SkillManager.dealDamage, which asks
	here for a damage multiplier first, then tells us about the hit and any
	kill. So every class gets them, whatever its skills.

	  Burning Blade    hits ignite (a burn over 3s)       → Inferno, Infernal Blade
	  Frostbite        hits chill; chilled take more      → Glacial Shatter, Glacial Ray
	  Chain Lightning  crits arc to nearby enemies        → Stormcaller, Thunder Rounds
	  Bloodlust        kills stack bonus damage           → Blood Frenzy, Bloodbath
	  Volatile Corpses kills explode                      → Chain Reaction, Plague Volley
	  Executioner      more damage to the wounded         → Reaper, Deathblow
	  Thunderstrike    every Nth hit calls lightning      → Judgement, Judgement Ray
	  Second Wind      low on health: hit harder, take less → Undying

	And the run relics' behaviour (TomeData relics: their stat effects are
	plain tomes; what they *do* is here): Dragon's Heart, Bloodied Crown,
	Frozen Soul, Berserker's Tooth, Gambler's Coin, Vampire Fang, Eye of the
	Storm, and the class relics (Frozen Heart, Blood Oath, Saint's Bell,
	Loaded Dice, Ember Heart, Duelist's Mark, Hunter's Sigil).

	Their own damage carries a "BOON_" source, which never sets off more procs
	(except Chain Reaction's explosions, which are meant to).

	Co-op synergies (anyone's status, anyone's hit: built for parties):
	  SHATTER          a heavy hit on a chilled enemy: an ice blast
	  STEAM BURST      fire on a chilled enemy: double damage and a scalding cloud
	  HOLY DETONATION  radiant power on a burning / scorched enemy: a holy blast
	  CONDUCTION       lightning on a chilled enemy: it jumps to more of them
	  RICOCHET FLARE   a bullet near a fresh explosion bounces off it
	  RALLY            fighting near your party: +5% damage per ally (up to 15%)
	Each one calls its name over the enemy (everyone sees it).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Boons = {}
local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local WeeklyModifiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeeklyModifiers"))

type Target = { character: Model, humanoid: Humanoid, rootPart: BasePart }
type Deps = {
	dealDamage: (Player, Target, number, string, any?) -> (number?, boolean?),
	getPotentialTargets: (Model) -> { Target },
	getStat: (Player, string) -> number,
	chill: (Model, number) -> (),
	addIncomingHook: ((Player, Model, number) -> number) -> (),
}
local deps: Deps

local function lvl(player: Player, id: string): number
	return math.floor(deps.getStat(player, id) + 0.5)
end
local function evo(player: Player, id: string): boolean
	return deps.getStat(player, id) > 0
end
local function classOf(player: Player): string
	local c = player:GetAttribute("SelectedClass")
	return if typeof(c) == "string" then c else ""
end

-- ── FX (short-lived, server-side: everyone sees them) ─────────────────────
local fxFolder: Folder? = nil
local function fx(): Folder
	if fxFolder and fxFolder.Parent then return fxFolder end
	local f = Instance.new("Folder")
	f.Name = "BoonFX"
	f.Parent = Workspace
	fxFolder = f
	return f
end

local function fxPart(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = fx()
	return p
end

-- A ball that swells and fades (explosions, shatters).
local function burstFX(at: Vector3, radius: number, color: Color3)
	local b = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1, CFrame = CFrame.new(at), Color = color, Transparency = 0.25 })
	TweenService:Create(b, TweenInfo.new(0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	Debris:AddItem(b, 0.35)
end

-- A jagged bolt from `a` to `b` (chain lightning).
local function boltFX(a: Vector3, b: Vector3, color: Color3)
	local segs = 5
	local prev = a
	for i = 1, segs do
		local t = i / segs
		local p = a:Lerp(b, t)
		if i < segs then p += Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2 end
		local len = (p - prev).Magnitude
		local seg = fxPart({ Size = Vector3.new(0.25, 0.25, len), CFrame = CFrame.lookAt((p + prev) / 2, p), Color = color })
		TweenService:Create(seg, TweenInfo.new(0.18), { Transparency = 1 }):Play()
		Debris:AddItem(seg, 0.2)
		prev = p
	end
end

-- A lightning strike from the sky onto `at`.
local function skyBoltFX(at: Vector3, radius: number, color: Color3)
	local top = at + Vector3.new(0, 40, 0)
	boltFX(top, at, color)
	local col = fxPart({ Size = Vector3.new(0.6, 40, 0.6), CFrame = CFrame.new(at + Vector3.new(0, 20, 0)), Color = Color3.new(1, 1, 1), Transparency = 0.2 })
	TweenService:Create(col, TweenInfo.new(0.2), { Transparency = 1, Size = Vector3.new(0.1, 40, 0.1) }):Play()
	Debris:AddItem(col, 0.25)
	local ring = fxPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 1, 1), CFrame = CFrame.new(at - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color, Transparency = 0.2 })
	TweenService:Create(ring, TweenInfo.new(0.3), { Size = Vector3.new(0.15, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.35)
end

-- ── Helpers ───────────────────────────────────────────────────────────────
local function targetOf(model: Model): Target?
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if hum and root and hum.Health > 0 then return { character = model, humanoid = hum, rootPart = root } end
	return nil
end

local function around(player: Player, at: Vector3, radius: number, except: Model?): { Target }
	local char = player.Character
	if not char then return {} end
	local out = {}
	for _, t in ipairs(deps.getPotentialTargets(char)) do
		if t.character ~= except and t.humanoid.Health > 0 and (t.rootPart.Position - at).Magnitude <= radius then
			table.insert(out, t)
		end
	end
	return out
end

local function isChilled(model: Model): boolean
	return (model:GetAttribute("ChilledUntil") or 0) > os.clock()
end

local function heal(player: Player, frac: number)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		local amount = hum.MaxHealth * frac
		if (player.Character :: Model):GetAttribute("CursedUntil") and (player.Character :: Model):GetAttribute("CursedUntil") > os.clock() then amount *= 0.35 end
		hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
	end
end

local function hpFrac(t: Target): number
	return if t.humanoid.MaxHealth > 0 then t.humanoid.Health / t.humanoid.MaxHealth else 1
end

local function isElite(model: Model): boolean
	return model:GetAttribute("IsElite") == true or model:GetAttribute("IsBoss") == true
end

-- (the class skills the class evolutions change)
local EMBERBLADE = { ["CINDER SLASH"] = true, ["SCORCHING CROSS"] = true, ["FURNACE BREAKER"] = true, ["INFERNAL EXECUTION"] = true }
local BERSERK_COMBO = { ["BERSERK CLEAVE"] = true, ["BERSERK SMASH"] = true }
local RADIANT = { ["RADIANT BOLT"] = true, ["DIVINE BEAM"] = true, ["RADIANT GROUND"] = true }

-- ── Burning Blade ─────────────────────────────────────────────────────────
type Burn = { owner: Player, untilT: number, tick: number, fire: Fire? }
local burns: { [Model]: Burn } = {}

local function ignite(owner: Player, t: Target, hit: number)
	local L = math.max(1, lvl(owner, "boon_ignite"))
	local per = ({ 0.08, 0.10, 0.12 })[math.min(L, 3)]
	local tick = math.max(2, math.floor(hit * per * (if evo(owner, "evo_inferno") then 2 else 1)))
	local b = burns[t.character]
	if b then
		b.untilT = os.clock() + 3
		b.tick = math.max(b.tick, tick)
		b.owner = owner
		return
	end
	local fire = Instance.new("Fire")
	fire.Name = "BoonBurn"
	fire.Size = 4
	fire.Heat = 6
	fire.Color = Color3.fromRGB(255, 120, 30)
	fire.SecondaryColor = Color3.fromRGB(255, 210, 80)
	fire.Parent = t.rootPart
	burns[t.character] = { owner = owner, untilT = os.clock() + 3, tick = tick, fire = fire }
end

local function burnLoop()
	while true do
		task.wait(0.5)
		local now = os.clock()
		for model, b in pairs(burns) do
			local t = targetOf(model)
			if not t or now > b.untilT or not b.owner.Parent then
				if b.fire then b.fire:Destroy() end
				burns[model] = nil
			else
				deps.dealDamage(b.owner, t, b.tick, "BOON_BURN")
			end
		end
	end
end

-- ── Bloodlust stacks ──────────────────────────────────────────────────────
local lust: { [Player]: { stacks: number, untilT: number } } = {}
local function addLust(player: Player, n: number)
	local L = lvl(player, "boon_bloodlust")
	if L <= 0 then return end
	local cap = if evo(player, "evo_blood_frenzy") then 12 else ({ 3, 5, 7 })[math.min(L, 3)]
	local s = lust[player] or { stacks = 0, untilT = 0 }
	if os.clock() > s.untilT then s.stacks = 0 end
	s.stacks = math.min(cap, s.stacks + n)
	s.untilT = os.clock() + (if L >= 3 then 6 else 5)
	lust[player] = s
	player:SetAttribute("BloodlustStacks", s.stacks)
end

-- ── Thunderstrike counter ─────────────────────────────────────────────────
local hits: { [Player]: number } = {}
local stormCrits: { [Player]: number } = {} -- (Eye of the Storm)
local frozenKills: { [Player]: number } = {} -- (Frozen Heart)

local function thunder(player: Player, t: Target, hit: number)
	local L = lvl(player, "boon_thunder")
	local judge = evo(player, "evo_judgement")
	local radius = if judge then 10 elseif L >= 3 then 8 else 6
	local at = t.rootPart.Position
	skyBoltFX(at, radius, Color3.fromRGB(255, 235, 140))
	local dmg = math.max(15, hit * 1.2)
	for _, other in ipairs(around(player, at, radius)) do
		deps.dealDamage(player, other, dmg, "BOON_THUNDER")
		if judge then deps.chill(other.character, 1) end
	end
	-- Judgement Ray (the Cleric): the strike heals allies near it.
	if evo(player, "evo_judgement_ray") then
		for _, p in ipairs(Players:GetPlayers()) do
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and p:GetAttribute("RunId") == player:GetAttribute("RunId") and (root.Position - at).Magnitude <= 14 then heal(p, 0.03) end
		end
	end
end

-- ── Explosions (Volatile Corpses, Chain Reaction, Plague Volley, shatters) ─
local blasts: { { at: Vector3, t: number } } = {} -- recent explosions (Ricochet Flare)
local function explode(player: Player, at: Vector3, radius: number, dmg: number, color: Color3, source: string, except: Model?, chillToo: boolean?)
	burstFX(at, radius, color)
	table.insert(blasts, { at = at, t = os.clock() })
	if #blasts > 24 then table.remove(blasts, 1) end
	for _, other in ipairs(around(player, at, radius, except)) do
		deps.dealDamage(player, other, dmg, source)
		if chillToo then deps.chill(other.character, 2) end
	end
end

-- ── Co-op synergies ───────────────────────────────────────────────────────
local FIRE = { ["CINDER SLASH"] = true, ["SCORCHING CROSS"] = true, ["FURNACE BREAKER"] = true, ["INFERNAL EXECUTION"] = true,
	["PHOENIX SLAM"] = true, ["PHOENIX FLARE"] = true, ["FIRE RING"] = true, ["FIRE LINE"] = true, ["INFERNO BLAST"] = true,
	["INFERNO ERUPTION"] = true, ["HEART OF THE INFERNO"] = true, ["BURNING GROUND"] = true, ["BLAZING CHARGE"] = true,
	["IGNITE"] = true, ["SCORCH"] = true, BOON_BURN = true, BOON_EMBER = true }
local HOLY = { ["RADIANT BOLT"] = true, ["DIVINE BEAM"] = true, ["RADIANT GROUND"] = true, ["DIVINE ASCENT"] = true, BOON_BELL = true }
local LIGHTNING = { BOON_CHAIN = true, BOON_THUNDER = true }
local BULLETS = { ["SIX SHOOTER"] = true, ["RICOCHET"] = true, ["RICOCHET BLAST"] = true, ["DEADEYE SHOT"] = true, ["FINAL SHOT"] = true, ["HIGH NOON"] = true }
local SYNERGY_CD = 1.2 -- per enemy, between synergies
local lastSynergy: { [Model]: number } = {}

local function announce(player: Player, at: Vector3, name: string, color: Color3)
	Network.GetRemoteEvent(Network.Remotes.RoomEvent):FireAllClients({ kind = "Pop", position = at + Vector3.new(0, 4, 0), text = name .. "!", color = color })
	pcall(function()
		local RunStats = require(script.Parent:WaitForChild("RunStats")) :: any
		RunStats.Add(player, "synergies", 1)
	end)
end

local function noteBlast(at: Vector3)
	table.insert(blasts, { at = at, t = os.clock() })
	if #blasts > 24 then table.remove(blasts, 1) end
end

-- After a hit: does it combine with what's already on the enemy?
local function synergy(player: Player, t: Target, hit: number, source: string)
	local model = t.character
	if (lastSynergy[model] or 0) > os.clock() - SYNERGY_CD then return end
	local at = t.rootPart.Position
	local chilled = isChilled(model)
	local burning = burns[model] ~= nil or (tonumber(model:GetAttribute("FK_Scorch")) or 0) > 0
	local fired: string? = nil
	if chilled and FIRE[source] then
		fired = "STEAM BURST"
		model:SetAttribute("ChilledUntil", 0)
		burstFX(at, 7, Color3.fromRGB(230, 235, 240))
		deps.dealDamage(player, t, math.max(6, hit), "BOON_STEAM")
		for _, other in ipairs(around(player, at, 7, model)) do deps.dealDamage(player, other, math.max(5, hit * 0.5), "BOON_STEAM") end
		noteBlast(at)
	elseif chilled and LIGHTNING[source] then
		fired = "CONDUCTION"
		local near = around(player, at, 18, model)
		for i = 1, math.min(3, #near) do
			boltFX(at, near[i].rootPart.Position, Color3.fromRGB(170, 220, 255))
			deps.dealDamage(player, near[i], math.max(5, hit * 0.7), "BOON_CONDUCT")
			deps.chill(near[i].character, 1)
		end
	elseif chilled and t.humanoid.MaxHealth > 0 and hit >= t.humanoid.MaxHealth * 0.18 then
		fired = "SHATTER"
		model:SetAttribute("ChilledUntil", 0)
		explode(player, at, 9, math.max(8, hit), Color3.fromRGB(180, 230, 255), "BOON_SYN_SHATTER", nil, true)
		noteBlast(at)
	elseif burning and HOLY[source] then
		fired = "HOLY DETONATION"
		explode(player, at, 10, math.max(8, hit * 1.2), Color3.fromRGB(255, 240, 170), "BOON_HOLY", nil)
		noteBlast(at)
	elseif BULLETS[source] then
		for _, b in ipairs(blasts) do
			if os.clock() - b.t < 1.5 and (b.at - at).Magnitude < 12 then
				local near = around(player, at, 22, model)
				if #near > 0 then
					fired = "RICOCHET FLARE"
					local target = near[math.random(1, #near)]
					boltFX(at, target.rootPart.Position, Color3.fromRGB(255, 210, 120))
					deps.dealDamage(player, target, math.max(5, hit * 0.6), "BOON_FLARE")
				end
				break
			end
		end
	end
	if fired then
		lastSynergy[model] = os.clock()
		local color = if fired == "STEAM BURST" then Color3.fromRGB(230, 235, 240)
			elseif fired == "CONDUCTION" then Color3.fromRGB(170, 220, 255)
			elseif fired == "SHATTER" then Color3.fromRGB(150, 220, 255)
			elseif fired == "HOLY DETONATION" then Color3.fromRGB(255, 235, 150)
			else Color3.fromRGB(255, 200, 110)
		announce(player, at, fired, color)
	end
end

-- Rally: allies in the same run fighting near you.
local function rally(player: Player): number
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return 1 end
	local runId = player:GetAttribute("RunId")
	local n = 0
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p:GetAttribute("RunId") == runId and p:GetAttribute("IsDead") ~= true then
			local r = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if r and (r.Position - root.Position).Magnitude <= 18 then n += 1 end
		end
	end
	return 1 + math.min(3, n) * 0.05
end

-- ── The hooks ─────────────────────────────────────────────────────────────
-- Before a hit lands: how much harder it hits.
function Boons.DamageMult(player: Player, t: Target, source: string): number
	local mult = rally(player)
	-- This week's omen
	if WeeklyModifiers.Is("frozen_abyss") and isChilled(t.character) then mult *= 1.25 end
	if WeeklyModifiers.Is("inferno") and burns[t.character] then mult *= 1.3 end
	-- Frostbite: chilled enemies take more.
	local frost = lvl(player, "boon_frost")
	if frost > 0 and isChilled(t.character) then mult *= 1 + ({ 0.15, 0.25, 0.35 })[math.min(frost, 3)] end
	-- Executioner: the wounded take more.
	local ex = lvl(player, "boon_execute")
	if ex > 0 and hpFrac(t) < 0.3 then mult *= 1 + ({ 0.3, 0.45, 0.6 })[math.min(ex, 3)] end
	-- Bloodlust stacks.
	local s = lust[player]
	if s and os.clock() <= s.untilT and s.stacks > 0 then
		mult *= 1 + s.stacks * (if lvl(player, "boon_bloodlust") >= 3 then 0.07 else 0.06)
	end
	-- Second Wind: low on health.
	local sw = lvl(player, "boon_secondwind")
	if sw > 0 then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.MaxHealth > 0 and hum.Health / hum.MaxHealth < 0.35 then mult *= 1 + ({ 0.2, 0.3, 0.4 })[math.min(sw, 3)] end
	end
	-- Infernal Blade (the Fire Knight): burning enemies take more from Emberblade.
	if EMBERBLADE[source] and burns[t.character] and evo(player, "evo_infernal_blade") then mult *= 1.25 end
	-- Relics
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	local hpf = if hum and hum.MaxHealth > 0 then hum.Health / hum.MaxHealth else 1
	if evo(player, "relic_berserkers_tooth") and hpf < 0.3 then mult *= 1.4 end
	if evo(player, "relic_blood_oath") then mult *= 1 + (1 - hpf) end
	if evo(player, "relic_duelists_mark") and isElite(t.character) then mult *= 1.3 end
	if evo(player, "relic_hunters_sigil") then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and (root.Position - t.rootPart.Position).Magnitude > 20 then mult *= 1.25 end
	end
	return mult
end

-- Loaded Dice: every 6th Six Shooter hit is a crit (asked before the roll).
local diceCount: { [Player]: number } = {}
function Boons.ForceCrit(player: Player, source: string): boolean
	if source ~= "SIX SHOOTER" or not evo(player, "relic_loaded_dice") then return false end
	diceCount[player] = (diceCount[player] or 0) + 1
	if diceCount[player] >= 6 then
		diceCount[player] = 0
		return true
	end
	return false
end

-- Dragon's Heart: an ability costs health.
function Boons.OnAbility(player: Player)
	if not evo(player, "relic_dragons_heart") then return end
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 1 then hum.Health = math.max(1, hum.Health - hum.MaxHealth * 0.04) end
end

-- A heal on `target` (Vampire Fang halves every other one; Saint's Bell: a
-- Cleric's heal on an ally shocks the enemies round them). Returns the amount.
local fangToggle: { [Player]: boolean } = {}
function Boons.OnHeal(healer: Player?, target: Model, amount: number): number
	local targetPlayer = Players:GetPlayerFromCharacter(target)
	if targetPlayer and evo(targetPlayer, "relic_vampire_fang") then
		fangToggle[targetPlayer] = not fangToggle[targetPlayer]
		if fangToggle[targetPlayer] then amount *= 0.5 end
	end
	if healer and targetPlayer ~= healer and evo(healer, "relic_saints_bell") then
		local root = target:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			local at = root.Position
			task.defer(function()
				burstFX(at, 10, Color3.fromRGB(255, 240, 170))
				for _, other in ipairs(around(healer, at, 10)) do deps.dealDamage(healer, other, math.max(8, amount * 2), "BOON_BELL") end
			end)
		end
	end
	return amount
end

-- After a hit lands (and wasn't a boon's own damage).
function Boons.OnHit(player: Player, t: Target, hit: number, source: string, crit: boolean)
	-- (synergies: lightning from a boon still conducts; other boon damage doesn't combine)
	if t.humanoid.Health > 0 and (string.sub(source, 1, 5) ~= "BOON_" or LIGHTNING[source] or source == "BOON_BURN" or source == "BOON_BELL") then
		synergy(player, t, hit, source)
	end
	if string.sub(source, 1, 5) == "BOON_" then return end
	-- (Inferno week: every hit can ignite)
	if WeeklyModifiers.Is("inferno") and math.random() < 0.1 then ignite(player, t, hit) end
	-- Burning Blade
	local ig = lvl(player, "boon_ignite")
	if ig > 0 then
		local always = EMBERBLADE[source] and evo(player, "evo_infernal_blade")
		if always or math.random() < ({ 0.15, 0.25, 0.35 })[math.min(ig, 3)] then ignite(player, t, hit) end
	end
	-- Frostbite
	local fr = lvl(player, "boon_frost")
	if fr > 0 then
		local always = source == "ICE BEAM" and evo(player, "evo_glacial_ray")
		if always or math.random() < ({ 0.12, 0.2, 0.28 })[math.min(fr, 3)] then deps.chill(t.character, 2) end
	end
	-- Chain Lightning (crits; every Six Shooter hit with Thunder Rounds)
	local ch = lvl(player, "boon_chain")
	if ch > 0 then
		local rounds = source == "SIX SHOOTER" and evo(player, "evo_thunder_rounds")
		if crit or rounds then
			local storm = evo(player, "evo_stormcaller")
			local count = if storm then 6 elseif rounds then math.max(2, ch) else ch
			local share = if storm then 0.6 elseif ch >= 3 then 0.45 else 0.4
			local from = t.rootPart.Position
			local near = around(player, from, 16, t.character)
			table.sort(near, function(a, b) return (a.rootPart.Position - from).Magnitude < (b.rootPart.Position - from).Magnitude end)
			for i = 1, math.min(count, #near) do
				boltFX(from, near[i].rootPart.Position, Color3.fromRGB(160, 200, 255))
				deps.dealDamage(player, near[i], math.max(4, hit * share), "BOON_CHAIN")
			end
		end
	end
	-- Thunderstrike
	local th = lvl(player, "boon_thunder")
	if th > 0 then
		local every = if evo(player, "evo_judgement") then 4 else ({ 10, 8, 6 })[math.min(th, 3)]
		local add = if RADIANT[source] and evo(player, "evo_judgement_ray") then 3 else 1
		hits[player] = (hits[player] or 0) + add
		if hits[player] >= every then
			hits[player] = 0
			thunder(player, t, hit)
		end
	end
	-- Relics on hit: Frozen Soul and Ember Heart's own chill / ignite; the
	-- Gambler's Coin bites; the Eye of the Storm calls lightning every 5th crit.
	if evo(player, "relic_frozen_soul") and math.random() < 0.1 then deps.chill(t.character, 2) end
	if evo(player, "relic_ember_heart") and math.random() < 0.2 then ignite(player, t, hit) end
	if crit and evo(player, "relic_gamblers_coin") and math.random() < 0.1 then
		local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 1 then hum.Health = math.max(1, hum.Health - hum.MaxHealth * 0.05) end
	end
	if crit and evo(player, "relic_storm_eye") then
		stormCrits[player] = (stormCrits[player] or 0) + 1
		if stormCrits[player] >= 5 then
			stormCrits[player] = 0
			thunder(player, t, hit)
		end
	end
	-- Reaper / Deathblow: execute outright.
	if t.humanoid.Health > 0 then
		local frac = hpFrac(t)
		local elite = isElite(t.character)
		local reap = evo(player, "evo_reaper") and not elite and frac < 0.15
		local deathblow = source == "SWORD FINISHER" and evo(player, "evo_deathblow") and (frac < (if elite then 0.1 else 0.25))
			and t.character:GetAttribute("IsBoss") ~= true
		if reap or deathblow then
			burstFX(t.rootPart.Position, 3, Color3.fromRGB(230, 230, 255))
			deps.dealDamage(player, t, t.humanoid.Health + 1, "BOON_EXECUTE")
		end
	end
end

-- After a killing blow.
function Boons.OnKill(player: Player, t: Target, hit: number, source: string)
	local at = t.rootPart.Position
	local model = t.character
	-- Bloodlust
	if lvl(player, "boon_bloodlust") > 0 then
		local combo = BERSERK_COMBO[source] and evo(player, "evo_bloodbath")
		addLust(player, if combo then 2 else 1)
		if evo(player, "evo_blood_frenzy") then heal(player, 0.015) end
		if combo then heal(player, 0.02) end
	end
	-- Executioner: elite kills heal.
	local ex = lvl(player, "boon_execute")
	if ex > 0 and isElite(model) then heal(player, ({ 0.05, 0.08, 0.12 })[math.min(ex, 3)]) end
	-- Inferno: a burning enemy that dies sets those around it alight.
	if burns[model] and evo(player, "evo_inferno") then
		burstFX(at, 8, Color3.fromRGB(255, 120, 30))
		for _, other in ipairs(around(player, at, 10, model)) do ignite(player, other, math.max(hit, 20)) end
	end
	-- Glacial Shatter / Glacial Ray: chilled (or Ice Beam) kills shatter.
	local shatter = (isChilled(model) and evo(player, "evo_glacial_shatter")) or (source == "ICE BEAM" and evo(player, "evo_glacial_ray"))
	if shatter and source ~= "BOON_SHATTER" then
		explode(player, at, 10, math.max(10, hit * 0.8), Color3.fromRGB(170, 230, 255), "BOON_SHATTER", model, true)
	end
	-- Relics on a kill.
	if evo(player, "relic_bloodied_crown") and isElite(model) then heal(player, 0.15) end
	local chilled = isChilled(model)
	if chilled and evo(player, "relic_frozen_soul") and source ~= "BOON_SHATTER" then
		explode(player, at, 8, math.max(8, hit * 0.6), Color3.fromRGB(170, 230, 255), "BOON_SHATTER", model)
	end
	if chilled and evo(player, "relic_frozen_heart") then
		frozenKills[player] = (frozenKills[player] or 0) + 1
		if frozenKills[player] >= 3 then
			frozenKills[player] = 0
			explode(player, at, 12, math.max(12, hit * 1.5), Color3.fromRGB(140, 210, 255), "BOON_SPIKES", model, true)
		end
	end
	if burns[model] and evo(player, "relic_ember_heart") then
		explode(player, at, 9, math.max(10, hit * 0.7), Color3.fromRGB(255, 120, 40), "BOON_EMBER", model)
	end
	-- Volatile Corpses (Chain Reaction: always, and explosion kills explode too;
	-- Plague Volley: Venom Arrows kills always burst).
	local co = lvl(player, "boon_corpse")
	if co > 0 then
		local chainR = evo(player, "evo_chain_reaction")
		local plague = source == "VENOM ARROWS" and evo(player, "evo_plague_volley")
		local fromBlast = source == "BOON_CORPSE"
		if (not fromBlast or chainR) and (chainR or plague or math.random() < ({ 0.15, 0.25, 0.35 })[math.min(co, 3)]) then
			local r = if co >= 3 then 11 else 9
			local share = if co >= 3 then 0.6 else 0.5
			local color = if plague then Color3.fromRGB(140, 230, 90) else Color3.fromRGB(255, 150, 60)
			-- (a breath, so a chain reaction ripples rather than all at once)
			task.delay(if fromBlast then 0.12 else 0, function()
				explode(player, at, r, math.max(10, hit * share), color, "BOON_CORPSE", model)
			end)
		end
	end
end

function Boons.Init(d: Deps)
	deps = d
	task.spawn(burnLoop)
	-- Second Wind (less damage taken low on health) and Undying (once a floor,
	-- a killing blow leaves you at 1 HP).
	local undyingUsed: { [Player]: number } = {}
	deps.addIncomingHook(function(player: Player, char: Model, amount: number): number
		local sw = lvl(player, "boon_secondwind")
		if sw <= 0 then return amount end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.MaxHealth <= 0 then return amount end
		if hum.Health / hum.MaxHealth < 0.35 then amount *= 1 - ({ 0.1, 0.15, 0.2 })[math.min(sw, 3)] end
		if amount >= hum.Health and evo(player, "evo_undying") then
			local runId = player:GetAttribute("RunId")
			local folder = Workspace:FindFirstChild("Runs")
			local scope = folder and typeof(runId) == "string" and folder:FindFirstChild(runId)
			local level = scope and scope:GetAttribute("RunLevel") or 1
			if undyingUsed[player] ~= level then
				undyingUsed[player] = level
				char:SetAttribute("InvulnerableUntil", os.clock() + 2)
				local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if root then burstFX(root.Position, 6, Color3.fromRGB(255, 210, 120)) end
				return math.max(0, hum.Health - 1)
			end
		end
		return amount
	end)
	Players.PlayerRemoving:Connect(function(p)
		lust[p] = nil
		hits[p] = nil
		undyingUsed[p] = nil
		stormCrits[p] = nil
		frozenKills[p] = nil
		diceCount[p] = nil
		fangToggle[p] = nil
	end)
end

return Boons
