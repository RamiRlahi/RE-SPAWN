--[[
	SkillManager.luau
	Server-authoritative combat skill execution, cooldown tracking, hitbox detection,
	and visual event replication.
--]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local HumanoidIndex = require(Shared:WaitForChild("HumanoidIndex"))
local RangerArrowData = require(Shared:WaitForChild("RangerArrowData"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local SkillData = require(Shared:WaitForChild("SkillData"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))
local RunStats = require(script.Parent:WaitForChild("RunStats"))
local AllyManager = require(script.Parent:WaitForChild("AllyManager"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))
local MobKinds = require(script.Parent:WaitForChild("MobKinds"))
local Boons = require(script.Parent:WaitForChild("Boons"))
local GunslingerServer = require(script.Parent:WaitForChild("GunslingerServer"))
local SwordsmanServer = require(script.Parent:WaitForChild("SwordsmanServer"))
local RogueServer = require(script.Parent:WaitForChild("RogueServer"))
local BerserkerServer = require(script.Parent:WaitForChild("BerserkerServer"))
local FireKnightServer = require(script.Parent:WaitForChild("FireKnightServer"))
local MountManager = require(script.Parent:WaitForChild("MountManager"))

local PhysicsService = game:GetService("PhysicsService")

local SkillManager = {}
local basicAttackTimes: { [Player]: number } = {}

-- Collision groups so a ranger can walk out of his own Rain of Arrows cage.
local ULT_BARRIER_GROUP = "RangerUltBarrier"
local ULT_CASTER_GROUP = "RangerUltCaster"
local ultGroupsReady = false
local function ensureUltCollisionGroups()
	if ultGroupsReady then return end
	ultGroupsReady = true
	pcall(function() PhysicsService:RegisterCollisionGroup(ULT_BARRIER_GROUP) end)
	pcall(function() PhysicsService:RegisterCollisionGroup(ULT_CASTER_GROUP) end)
	-- The caster's character passes through the barrier; everyone else is still blocked.
	pcall(function() PhysicsService:CollisionGroupSetCollidable(ULT_CASTER_GROUP, ULT_BARRIER_GROUP, false) end)
end

local function setCharacterCollisionGroup(char: Model, group: string)
	if not char then return end
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") then
			pcall(function() d.CollisionGroup = group end)
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: Find VFX asset in ReplicatedStorage (server can read ReplicatedStorage)
-- ─────────────────────────────────────────────────────────────────────────────
local function findVFXAsset(name: string): Instance?
	local searchNames = {
		name,
		string.lower(name),
		string.upper(name),
		string.gsub(name, " ", "_"),
		string.gsub(name, "_", " "),
		string.gsub(string.lower(name), " ", "_"),
		string.gsub(string.lower(name), "_", " "),
	}

	local roots = {
		ReplicatedStorage:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("generalVFX"),
		ReplicatedStorage:FindFirstChild("Assets") and ReplicatedStorage.Assets:FindFirstChild("VFX"),
		ReplicatedStorage:FindFirstChild("VFX"),
		ReplicatedStorage:FindFirstChild("Assets"),
		ReplicatedStorage,
	}

	for _, folder in ipairs(roots) do
		if folder then
			for _, n in ipairs(searchNames) do
				local found = folder:FindFirstChild(n)
				if found then return found end
			end
			for _, child in ipairs(folder:GetChildren()) do
				for _, n in ipairs(searchNames) do
					if string.lower(child.Name) == string.lower(n) then
						return child
					end
				end
			end
		end
	end
	return nil
end

-- playerCooldowns[player][skillIndex] = lastCastTime
local playerCooldowns: { [Player]: { [number]: number } } = {}
-- cooldownLengths[player][skillIndex] = that cast's effective cooldown
local cooldownLengths: { [Player]: { [number]: number } } = {}
-- Charge skills (SkillData `charges`): chargesFullAt[player][skillIndex] =
-- when every charge is back. Each use pushes it one recharge later; a use
-- needs it no more than (charges - 1) recharges away.
local chargesFullAt: { [Player]: { [number]: number } } = {}

-- Character visibility storage for skill 3 (Phoenix Dash invisibility)
local savedTransparencies: { [Model]: { [Instance]: number } } = {}

local function setCharacterVisibility(char: Model, visible: boolean)
	if not char then return end

	if not visible then
		local charSaved = savedTransparencies[char]
		if not charSaved then
			charSaved = {}
			savedTransparencies[char] = charSaved
		end

		for _, desc in ipairs(char:GetDescendants()) do
			if desc:IsA("BasePart") then
				if charSaved[desc] == nil then
					charSaved[desc] = desc.Transparency
				end
				desc.Transparency = 1
			elseif desc:IsA("Decal") or desc:IsA("Texture") then
				if charSaved[desc] == nil then
					charSaved[desc] = desc.Transparency
				end
				desc.Transparency = 1
			end
		end
	else
		local charSaved = savedTransparencies[char]
		if charSaved then
			for inst, origTrans in pairs(charSaved) do
				if inst and inst.Parent then
					inst.Transparency = origTrans
				end
			end
			savedTransparencies[char] = nil
		else
			for _, desc in ipairs(char:GetDescendants()) do
				if desc:IsA("BasePart") then
					if desc.Name == "HumanoidRootPart" then
						desc.Transparency = 1
					else
						desc.Transparency = 0
					end
				elseif desc:IsA("Decal") or desc:IsA("Texture") then
					desc.Transparency = 0
				end
			end
		end
	end
end

-- No friendly fire: other players (co-op), friendly allies and Ice Clone
-- decoys are never valid targets for damage, knockback, roots or chills.
local function isFriendly(model: Model): boolean
	return Players:GetPlayerFromCharacter(model) ~= nil
		or model:GetAttribute("IsAlly") == true
		or model:GetAttribute("IsDecoy") == true
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Helper: Find all target humanoids in workspace (excluding caster and friendlies)
-- ─────────────────────────────────────────────────────────────────────────────
-- Huge bosses (the dragon) are hit anywhere on their body, not only near
-- their centre: their HitProxy is moved to the body point nearest the caster
-- (at the caster's height) and stands in for the root.
local function hitPoint(model: Model, root: BasePart, casterChar: Model): BasePart
	local radius = model:GetAttribute("HitRadius")
	local proxy = model:FindFirstChild("HitProxy")
	local from = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if typeof(radius) ~= "number" or not (proxy and proxy:IsA("BasePart")) or not from then return root end
	local c = root.Position
	local off = Vector3.new(from.Position.X - c.X, 0, from.Position.Z - c.Z)
	local p = if off.Magnitude > radius then c + off.Unit * radius else Vector3.new(from.Position.X, c.Y, from.Position.Z)
	proxy.CFrame = CFrame.new(p.X, from.Position.Y, p.Z)
	return proxy
end

-- (every model in the world with a Humanoid, kept up to date: HumanoidIndex.
-- Targets are looked up for every swing, bullet, bounce and blast; walking
-- the whole Workspace each time brought the server to its knees.)
local humanoidModels = HumanoidIndex.Each()

local function getPotentialTargets(casterChar: Model): { { character: Model, humanoid: Humanoid, rootPart: BasePart } }
	local targets = {}

	for desc, hum in pairs(humanoidModels) do
		if desc ~= casterChar then
			-- Don't consider accessories or player character sub-models
			if desc:FindFirstAncestorOfClass("Accessory") then continue end
			if desc:IsDescendantOf(casterChar) then continue end
			if isFriendly(desc) then continue end

			if hum.Parent == desc and hum.Health > 0 then
				local root: BasePart? = (desc:FindFirstChild("HumanoidRootPart") or desc.PrimaryPart or desc:FindFirstChildWhichIsA("BasePart")) :: BasePart?
				if root and desc:GetAttribute("HitRadius") ~= nil then
					root = hitPoint(desc, root, casterChar)
				end
				if root then
					table.insert(targets, {
						character = desc,
						humanoid = hum,
						rootPart = root,
					})
				end
			end
		end
	end

	return targets
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hit impact: per-attack knockback, stagger and impact VFX style.
--   kb      extra knockback speed (studs/s) away from the attacker; 0 where the
--           ability already applies its own impulse or is meant to pin/freeze
--   lift    upward speed added to the knockback
--   stagger seconds the mob's AI pauses (so MoveTo doesn't cancel the push)
--   style   client impact VFX: slash / fire / arrow / nature / holy / ice
--   heavy   bigger VFX + a small camera shake for the attacker
-- ─────────────────────────────────────────────────────────────────────────────
type ImpactProfile = { kb: number, lift: number, stagger: number, style: string, heavy: boolean? }
local IMPACT_PROFILES: { [string]: ImpactProfile } = {
	-- Fire Knight (Scorch / burning-ground ticks have no profile: no impact
	-- VFX or stagger on every tick)
	["CINDER SLASH"]         = { kb = 4,  lift = 0,  stagger = 0.3,  style = "fire" },
	["SCORCHING CROSS"]      = { kb = 4,  lift = 0,  stagger = 0.3,  style = "fire" },
	["FURNACE BREAKER"]      = { kb = 14, lift = 6,  stagger = 0.45, style = "fire", heavy = true },
	["INFERNAL EXECUTION"]   = { kb = 26, lift = 10, stagger = 0.7,  style = "fire", heavy = true },
	["FIRE LINE"]            = { kb = 0,  lift = 0,  stagger = 0.2,  style = "fire" },
	["INFERNO BLAST"]        = { kb = 10, lift = 4,  stagger = 0.3,  style = "fire" },
	["BLAZING CHARGE"]       = { kb = 0,  lift = 0,  stagger = 0.5,  style = "fire", heavy = true },
	["RISING SLASH"]         = { kb = 6,  lift = 42, stagger = 0.9,  style = "fire", heavy = true },
	["PHOENIX SLAM"]         = { kb = 34, lift = 16, stagger = 0.9,  style = "fire", heavy = true },
	["PHOENIX FLARE"]        = { kb = 12, lift = 8,  stagger = 0.4,  style = "fire" },
	["EARTHSHAKER"]          = { kb = 30, lift = 10, stagger = 0.8,  style = "fire", heavy = true },
	["AFTERSHOCK"]           = { kb = 8,  lift = 4,  stagger = 0.35, style = "fire" },
	["FIRE RING"]            = { kb = 22, lift = 8,  stagger = 0.6,  style = "fire", heavy = true },
	["IGNITE"]               = { kb = 10, lift = 5,  stagger = 0.3,  style = "fire" },
	["HEART OF THE INFERNO"] = { kb = 30, lift = 14, stagger = 1.0,  style = "fire", heavy = true },
	["EXECUTION"]            = { kb = 20, lift = 6,  stagger = 1.0,  style = "fire", heavy = true },
	["INFERNO ERUPTION"]     = { kb = 12, lift = 24, stagger = 0.8,  style = "fire", heavy = true },
	-- Ranger
	["VENOM ARROWS"]     = { kb = 0,  lift = 0,  stagger = 0.15, style = "arrow" },
	["SEEKER BARRAGE"]   = { kb = 0,  lift = 0,  stagger = 0.15, style = "arrow" },
	["RAIN OF ARROWS"]   = { kb = 0,  lift = 0,  stagger = 0.2,  style = "arrow" },
	["VERDANT SLASH"]    = { kb = 0,  lift = 0,  stagger = 0.4,  style = "nature", heavy = true },
	["ENTANGLING ARROW"] = { kb = 0,  lift = 0,  stagger = 0.2,  style = "nature" },
	-- Cleric
	["RADIANT BOLT"]     = { kb = 0,  lift = 0,  stagger = 0.2,  style = "holy" },
	["DIVINE BEAM"]      = { kb = 6,  lift = 0,  stagger = 0.3,  style = "holy" },
	["RADIANT GROUND"]   = { kb = 28, lift = 12, stagger = 0.5,  style = "holy", heavy = true },
	["DIVINE ASCENT"]    = { kb = 0,  lift = 0,  stagger = 0.8,  style = "holy", heavy = true },
	-- Ice Mage (spikes / beam / shatter / blizzard freeze their targets instead)
	["ICE CRYSTAL"]      = { kb = 14, lift = 4,  stagger = 0.2,  style = "ice" },
	["ICE SPIKES"]       = { kb = 0,  lift = 0,  stagger = 0,    style = "ice", heavy = true },
	["ICE BEAM"]         = { kb = 0,  lift = 0,  stagger = 0,    style = "ice" },
	["SHATTER"]          = { kb = 0,  lift = 0,  stagger = 0,    style = "ice", heavy = true },
	["BLIZZARD"]         = { kb = 0,  lift = 0,  stagger = 0,    style = "ice" },
	-- Gunslinger (bullets push a little; the final / Deadeye shots punch hard)
	["SIX SHOOTER"]      = { kb = 6,  lift = 0,  stagger = 0.15, style = "bullet" },
	["FAN THE HAMMER"]   = { kb = 5,  lift = 0,  stagger = 0.12, style = "bullet" },
	["FINAL SHOT"]       = { kb = 24, lift = 5,  stagger = 0.35, style = "bullet", heavy = true },
	["DEADEYE SHOT"]     = { kb = 18, lift = 4,  stagger = 0.45, style = "bullet", heavy = true },
	["RICOCHET"]         = { kb = 9,  lift = 2,  stagger = 0.2,  style = "bullet" },
	["RICOCHET BLAST"]   = { kb = 16, lift = 7,  stagger = 0.3,  style = "fire" },
	["HIGH NOON"]        = { kb = 10, lift = 2,  stagger = 0.3,  style = "bullet", heavy = true },
	["HIGH NOON EXECUTION"] = { kb = 42, lift = 12, stagger = 0.9, style = "bullet", heavy = true },
	-- Swordsman
	["SWORD COMBO"]        = { kb = 0,  lift = 0,  stagger = 0.25, style = "slash" },
	["SWORD FINISHER"]     = { kb = 22, lift = 6,  stagger = 0.4,  style = "slash", heavy = true },
	["SWORD RUSH"]         = { kb = 4,  lift = 0,  stagger = 0.35, style = "slash", heavy = true },
	["COUNTER SLASH"]      = { kb = 10, lift = 40, stagger = 1.2,  style = "slash", heavy = true },
	["WHIRL CUT"]          = { kb = 0,  lift = 0,  stagger = 0.2,  style = "slash" },
	["WHIRL FINISH"]       = { kb = 34, lift = 10, stagger = 0.5,  style = "slash", heavy = true },
	["BLADE STORM"]        = { kb = 6,  lift = 4,  stagger = 0.5,  style = "slash", heavy = true },
	["BLADE STORM FINISH"] = { kb = 30, lift = 12, stagger = 0.9,  style = "slash", heavy = true },
	-- Berserker
	["BERSERK CLEAVE"]     = { kb = 6,  lift = 0,  stagger = 0.35, style = "slash" },
	["BERSERK SMASH"]      = { kb = 24, lift = 8,  stagger = 0.5,  style = "slash", heavy = true },
	["RUPTURE"]            = { kb = 12, lift = 22, stagger = 0.8,  style = "slash", heavy = true },
	["BLOODSTORM"]         = { kb = 16, lift = 4,  stagger = 0.5,  style = "slash", heavy = true },
	["BLOODSTORM FINISH"]  = { kb = 46, lift = 12, stagger = 0.8,  style = "slash", heavy = true },
	["BLOODRAGE PULSE"]    = { kb = 26, lift = 4,  stagger = 0.4,  style = "slash" },
	["WORLDBREAKER"]       = { kb = 34, lift = 30, stagger = 1.2,  style = "slash", heavy = true },
	["WORLDBREAKER EXECUTE"] = { kb = 44, lift = 20, stagger = 1.0, style = "slash", heavy = true },
}

-- How many effect messages a player's hits may send each second. The hits
-- themselves (damage, knockback, stagger) are never limited; only their
-- pictures are, so a flood of them (a stack of Projectile + Ricochet tomes)
-- can't swamp the network and every client's frame rate.
type Bucket = { tokens: number, at: number }
local fxBuckets: { [Player]: { [string]: Bucket } } = {}
Players.PlayerRemoving:Connect(function(p) fxBuckets[p] = nil end)
local function fxAllowed(player: Player, key: string, perSecond: number): boolean
	local mine = fxBuckets[player]
	if not mine then
		mine = {}
		fxBuckets[player] = mine
	end
	local now = os.clock()
	local cap = math.max(2, perSecond / 4)
	local b = mine[key]
	if not b then
		b = { tokens = cap, at = now }
		mine[key] = b
	end
	b.tokens = math.min(cap, b.tokens + (now - b.at) * perSecond)
	b.at = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

local function applyImpact(player: Player, target: { character: Model, humanoid: Humanoid, rootPart: BasePart }, source: string, crit: boolean)
	local profile = IMPACT_PROFILES[source]
	if not profile then return end
	local attackerRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local away = attackerRoot and (target.rootPart.Position - attackerRoot.Position) or target.rootPart.CFrame.LookVector * -1
	local flatAway = Vector3.new(away.X, 0, away.Z)
	flatAway = flatAway.Magnitude > 0.1 and flatAway.Unit or Vector3.new(0, 0, 1)

	-- Physics only on mobs (never shove other players' characters).
	if not Players:GetPlayerFromCharacter(target.character) and not target.rootPart.Anchored then
		-- Bosses aren't staggered by hits (it would freeze their move loop).
		-- (nor are the mobs built not to be: a Brute)
		if profile.stagger > 0 and target.character:GetAttribute("IsBoss") ~= true and target.character:GetAttribute("Unstaggerable") ~= true then
			local untilTime = os.clock() + profile.stagger * (crit and 1.4 or 1)
			if (target.character:GetAttribute("StaggerUntil") or 0) < untilTime then
				target.character:SetAttribute("StaggerUntil", untilTime)
			end
		end
		if profile.kb > 0 or profile.lift > 0 then
			local mult = (crit and 1.3 or 1) * math.max(PlayerStats.GetStat(player, "knockback"), 0.1)
			local v = flatAway * profile.kb * mult + Vector3.new(0, profile.lift * mult, 0)
			target.rootPart.AssemblyLinearVelocity = Vector3.new(
				target.rootPart.AssemblyLinearVelocity.X * 0.3 + v.X,
				math.max(target.rootPart.AssemblyLinearVelocity.Y, 0) + v.Y,
				target.rootPart.AssemblyLinearVelocity.Z * 0.3 + v.Z)
		end
	end

	if not fxAllowed(player, if crit or profile.heavy then "impactBig" else "impact", if crit or profile.heavy then 15 else 30) then return end
	Network.GetRemoteEvent(Network.Remotes.HitImpact):FireAllClients({
		position = target.rootPart.Position,
		direction = flatAway,
		style = profile.style,
		crit = crit,
		heavy = profile.heavy == true,
		model = target.character,
		attacker = player,
	})
end

-- Keep combat authoritative while giving the attacking player immediate, exact
-- feedback about the damage that was actually applied to a target.
-- opts.forceCrit makes the hit a guaranteed critical (e.g. a Deadeye shot).
-- Returns the damage dealt and whether it crit (nil if nothing was dealt).
local function dealDamage(player: Player, target: { character: Model, humanoid: Humanoid, rootPart: BasePart }, amount: number, source: string, opts: { forceCrit: boolean? }?): (number?, boolean?)
	local finalAmount = math.max(0, math.floor(amount))
	if finalAmount <= 0 or target.humanoid.Health <= 0 then return nil, nil end
	if isFriendly(target.character) then return nil, nil end -- belt and braces: no friendly fire
	-- A boss mid-intro or mid-signature move can't be hurt: say so.
	if target.character:GetAttribute("BossInvulnerable") == true then
		if fxAllowed(player, "immune", 4) then
			Network.GetRemoteEvent(Network.Remotes.DamageDealt):FireClient(player, {
				position = target.rootPart.Position + Vector3.new(0, 2.5, 0),
				amount = 0,
				source = "IMMUNE",
			})
		end
		return nil, nil
	end
	local shielded = false
	-- (the run's boons: Frostbite, Executioner, Bloodlust, Second Wind…)
	finalAmount = math.floor(finalAmount * Boons.DamageMult(player, target, source))

	local isCrit = false
	local critChance = PlayerStats.GetStat(player, "critChance")
	if (opts and opts.forceCrit) or Boons.ForceCrit(player, source) or (critChance > 0 and math.random() < critChance) then
		isCrit = true
		finalAmount = math.floor(finalAmount * 1.5)
	end

	-- A Shielded elite's barrier soaks the hit first (MobKinds).
	local shield = target.character:GetAttribute("Shield")
	if typeof(shield) == "number" and shield > 0 then
		local soaked = math.min(shield, finalAmount)
		target.character:SetAttribute("Shield", shield - soaked)
		finalAmount -= soaked
		shielded = true
	end
	local killed = false
	if finalAmount > 0 then
		target.humanoid:TakeDamage(finalAmount)
		killed = target.humanoid.Health <= 0
		RunStats.OnDamage(player, target, finalAmount)
		Boons.OnHit(player, target, finalAmount, source, isCrit)
		if killed then Boons.OnKill(player, target, finalAmount, source) end
	end
	applyImpact(player, target, source, isCrit)

	local lifesteal = PlayerStats.GetStat(player, "lifesteal")
	if lifesteal > 0 then
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then
			local cursed = char and (char:GetAttribute("CursedUntil") or 0) > os.clock()
			local heal = math.floor(finalAmount * lifesteal * (if cursed then MobKinds.CURSE_HEAL else 1))
			if heal > 0 then
				hum.Health = math.min(hum.MaxHealth, hum.Health + heal)
			end
		end
	end

	Network.GetRemoteEvent(Network.Remotes.DamageDealt):FireClient(player, {
		position = target.rootPart.Position + Vector3.new(0, 2.5, 0),
		amount = finalAmount,
		source = if shielded and finalAmount <= 0 then "SHIELD" else source,
		crit = isCrit,
	})
	return finalAmount, isCrit
end

local function rotateFlatDirection(direction: Vector3, degrees: number): Vector3
	local flat = Vector3.new(direction.X, 0, direction.Z)
	if flat.Magnitude < 0.1 then
		flat = Vector3.new(0, 0, -1)
	end
	return (CFrame.Angles(0, math.rad(degrees), 0) * flat.Unit).Unit
end

local function getRangerCursorTarget(origin: Vector3, lookDir: Vector3, requestedTarget: any, maxRange: number): Vector3
	local offset: Vector3? = nil
	if typeof(requestedTarget) == "Vector3" then
		offset = Vector3.new(requestedTarget.X - origin.X, 0, requestedTarget.Z - origin.Z)
	end
	if not offset or offset.Magnitude < 0.5 then
		offset = rotateFlatDirection(lookDir, 0)
	end
	return origin + offset.Unit * math.min(offset.Magnitude, maxRange)
end

-- Ricochet Tome: after a projectile hit, bounce to the nearest enemy not yet
-- hit in this chain, once per tome, each bounce doing a share of the last hit.
local RICOCHET_RANGE = 22
local RICOCHET_DAMAGE = 0.6
local RICOCHET_HOP_TIME = 0.08
-- Continuous beams tick many times a second; bouncing every tick would swamp.
local NO_RICOCHET: { [string]: boolean } = { ["ICE BEAM"] = true }

local function ricochet(player: Player, casterChar: Model, first: any, damage: number, source: string)
	local bounces = math.floor(PlayerStats.GetStat(player, "ricochet"))
	if bounces <= 0 or NO_RICOCHET[source] then return end
	task.spawn(function()
		local hit: { [Model]: boolean } = { [first.character] = true }
		local fromPos: Vector3 = first.rootPart.Position
		local dmg = damage
		for _ = 1, bounces do
			task.wait(RICOCHET_HOP_TIME)
			local best, bestDist = nil, RICOCHET_RANGE
			for _, t in ipairs(getPotentialTargets(casterChar)) do
				if not hit[t.character] then
					local d = (t.rootPart.Position - fromPos).Magnitude
					if d < bestDist then best, bestDist = t, d end
				end
			end
			if not best then break end
			hit[best.character] = true
			dmg = math.max(1, math.floor(dmg * RICOCHET_DAMAGE))
			local toPos = best.rootPart.Position
			if fxAllowed(player, "ricochet", 25) then
				Network.GetRemoteEvent(Network.Remotes.RicochetFX):FireAllClients({ from = fromPos, to = toPos, attacker = player })
			end
			dealDamage(player, best, dmg, source)
			fromPos = toPos
		end
	end)
end

-- How far from a shot's line a target still counts as hit: the shot's own
-- width, plus most of the target's body half-width (a shot clipping an arm
-- or a held bow is a hit, not just one through its middle), plus a little
-- for the mob having moved between the client's frame and ours.
local LINE_LENIENCY = 0.6
local function lineReach(target: any, width: number): number
	local size = target.character:GetExtentsSize()
	return width + math.min(math.max(size.X, size.Z) * 0.5, 8) * 0.6 + LINE_LENIENCY
end

local function damageFirstTargetOnLine(player: Player, casterChar: Model, origin: Vector3, direction: Vector3, range: number, width: number, damage: number, source: string)
	local bestTarget = nil
	local bestAlong = range
	local flatDir = rotateFlatDirection(direction, 0)

	for _, target in ipairs(getPotentialTargets(casterChar)) do
		local diff = target.rootPart.Position - origin
		local flatDiff = Vector3.new(diff.X, 0, diff.Z)
		local along = flatDiff:Dot(flatDir)
		if along >= 0 and along <= range then
			local closest = origin + flatDir * along
			local lateral = (Vector3.new(target.rootPart.Position.X, origin.Y, target.rootPart.Position.Z) - closest).Magnitude
			if lateral <= lineReach(target, width) and along < bestAlong then
				bestAlong = along
				bestTarget = target
			end
		end
	end

	if bestTarget then
		dealDamage(player, bestTarget, damage, source)
		ricochet(player, casterChar, bestTarget, damage, source)
		return bestTarget, bestAlong
	end

	return nil, nil
end

local findArrowUncached: () -> Instance?
local cachedArrow: Instance? = nil
-- (looked up once, not on every shot: ReplicatedStorage holds every asset)
local function findRangerArrowTemplate(): Instance?
	if cachedArrow and cachedArrow.Parent then return cachedArrow end
	cachedArrow = findArrowUncached()
	return cachedArrow
end

findArrowUncached = function(): Instance?
	-- Prefer the dedicated projectile asset placed directly in ReplicatedStorage.
	-- The recursive lookup keeps this resilient if it is later organized into a
	-- different ReplicatedStorage folder.
	local arrow = ReplicatedStorage:FindFirstChild("Arrow") or ReplicatedStorage:FindFirstChild("arrow")
	if arrow and (arrow:IsA("Model") or arrow:IsA("BasePart")) then return arrow end
	for _, descendant in ipairs(ReplicatedStorage:GetDescendants()) do
		if string.lower(descendant.Name) == "arrow" and (descendant:IsA("Model") or descendant:IsA("BasePart")) then
			return descendant
		end
	end

	-- Backwards-compatible fallback for the original Ranger armor location.
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	local classes = assets and assets:FindFirstChild("Classes")
	local rangerArmor = classes and classes:FindFirstChild("Ranger armor")
	if not rangerArmor then return nil end

	arrow = rangerArmor:FindFirstChild("Arrow") or rangerArmor:FindFirstChild("arrow")
	if arrow and (arrow:IsA("Model") or arrow:IsA("BasePart")) then return arrow end
	for _, child in ipairs(rangerArmor:GetChildren()) do
		if (child:IsA("Model") or child:IsA("BasePart")) and string.find(string.lower(child.Name), "arrow") then
			return child
		end
	end
	return nil
end

local function fireRangerArrowVisual(origin: Vector3, direction: Vector3, distance: number, speedMultiplier: number?)
	local template = findRangerArrowTemplate()
	if not template then
		warn("[SkillManager] Ranger Arrow model not found in ReplicatedStorage.")
		return
	end

	local arrow = template:Clone()
	local function positionArrow(cframe: CFrame)
		if arrow:IsA("Model") then
			arrow:PivotTo(cframe)
		elseif arrow:IsA("BasePart") then
			arrow.CFrame = cframe
		end
	end
	for _, descendant in ipairs(arrow:GetDescendants()) do
		if descendant:IsA("BasePart") then
			descendant.Anchored = true
			descendant.CanCollide = false
			descendant.CanTouch = false
			descendant.CanQuery = false
		end
	end
	if arrow:IsA("BasePart") then
		arrow.Anchored = true
		arrow.CanCollide = false
		arrow.CanTouch = false
		arrow.CanQuery = false
	end

	arrow.Name = "RangerArrowProjectile"
	arrow.Parent = Workspace
	local flatDirection = rotateFlatDirection(direction, 0)
	local validDistance = (typeof(distance) == "number" and distance > 0) and distance or 70
	local mult = (typeof(speedMultiplier) == "number" and speedMultiplier > 0) and speedMultiplier or 1
	local travelTime = math.max(0.05, validDistance / (180 * mult))
	local baseOrigin = typeof(origin) == "Vector3" and origin or Vector3.zero
	task.spawn(function()
		local startTime = os.clock()
		while arrow.Parent do
			local progress = math.clamp((os.clock() - startTime) / travelTime, 0, 1)
			local position = baseOrigin + flatDirection * (validDistance * progress)
			local lookCF = CFrame.lookAt(position, position + flatDirection)
			positionArrow(lookCF * CFrame.Angles(0, math.rad(90), 0))
			if progress >= 1 then break end
			task.wait()
		end
		if arrow.Parent then arrow:Destroy() end
	end)
end

local function applyRangerArrowKnockback(target: any, direction: Vector3, multiplier: number)
	if not target then return end
	local pushDirection = (rotateFlatDirection(direction, 0) + Vector3.new(0, 0.12, 0)).Unit
	target.rootPart:ApplyImpulse(pushDirection * (target.rootPart.AssemblyMass * 8 * multiplier))
end

-- ─────────────────────────────────────────────────────────────────────────────
-- The Ranger's basic arrows: real projectiles. Each one flies (SPEED studs/s,
-- × Projectile Speed) and deals its damage when it reaches an enemy, or stops
-- at a wall (or a low barrier: cover works). Clients draw them (RangerArrows):
-- the shooter's straight away, everyone else's from one "fire" message per
-- volley, and every client is told where each one landed ("hit").
-- ─────────────────────────────────────────────────────────────────────────────
type FlyingArrow = {
	player: Player, char: Model, key: number, pos: Vector3, dir: Vector3,
	speed: number, left: number, width: number, damage: number, knockback: number,
}
local flyingArrows: { FlyingArrow } = {}
local arrowConn: RBXScriptConnection? = nil
local arrowWallParams = RaycastParams.new()
arrowWallParams.FilterType = Enum.RaycastFilterType.Include
arrowWallParams.IgnoreWater = true
local serverShot = 0

local function arrowRemote(): RemoteEvent
	return Network.GetRemoteEvent(Network.Remotes.RangerArrows)
end

local function stepArrows(dt: number)
	local walls = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		if c.Name == "GeneratedDungeon" then table.insert(walls, c) end
	end
	arrowWallParams.FilterDescendantsInstances = walls
	local targetsOf: { [Model]: { any } } = {}
	local bodyReach: { [Model]: number } = {} -- (lineReach without the arrow's width: once per enemy per step)
	for i = #flyingArrows, 1, -1 do
		local a = flyingArrows[i]
		if not a.char.Parent or not a.player.Parent then
			table.remove(flyingArrows, i)
			continue
		end
		local move = math.min(a.speed * dt, a.left)
		local from = a.pos
		-- the first wall (or low barrier) along this step
		local reach = move
		local wall = if #walls > 0 then Workspace:Raycast(from, a.dir * move, arrowWallParams) else nil
		if wall then reach = wall.Distance end
		-- the first enemy along it, before the wall
		local targets = targetsOf[a.char]
		if not targets then
			targets = getPotentialTargets(a.char)
			targetsOf[a.char] = targets
		end
		local best, bestAlong = nil, reach + 0.5
		for _, t in ipairs(targets) do
			if t.humanoid.Health > 0 then
				local p = t.rootPart.Position
				local d = Vector3.new(p.X - from.X, 0, p.Z - from.Z)
				-- (cheap first: near this step and on its level)
				if math.abs(p.Y - from.Y) <= 9 and d.Magnitude <= move + 14 then
					local along = d:Dot(a.dir)
					if along >= -1 and along < bestAlong then
						local body = bodyReach[t.character]
						if not body then
							body = lineReach(t, 0)
							bodyReach[t.character] = body
						end
						if (d - a.dir * along).Magnitude <= body + a.width then
							best, bestAlong = t, math.max(along, 0)
						end
					end
				end
			end
		end
		if best then
			table.remove(flyingArrows, i)
			dealDamage(a.player, best, a.damage, "VENOM ARROWS")
			ricochet(a.player, a.char, best, a.damage, "VENOM ARROWS")
			applyRangerArrowKnockback(best, a.dir, a.knockback)
			if fxAllowed(a.player, "arrowHit", 40) then
				arrowRemote():FireAllClients({ kind = "hit", attacker = a.player, key = a.key, at = best.rootPart.Position })
			end
		elseif wall then
			table.remove(flyingArrows, i)
			if fxAllowed(a.player, "arrowHit", 40) then
				arrowRemote():FireAllClients({ kind = "hit", attacker = a.player, key = a.key, at = wall.Position, wall = true })
			end
		else
			a.pos = from + a.dir * move
			a.left -= move
			if a.left <= 0.01 then table.remove(flyingArrows, i) end
		end
	end
	if #flyingArrows == 0 and arrowConn then
		arrowConn:Disconnect()
		arrowConn = nil
	end
end

-- Loose a volley (the fan: one arrow, plus one per Projectile tome) from
-- `origin` toward `look`. `shot`: the shooter's volley number (they drew it
-- already, with the same keys); nil: the server numbers it and tells them too.
local function fireRangerVolley(player: Player, char: Model, origin: Vector3, look: Vector3, shot: number?)
	local count = 1 + math.max(0, math.floor(PlayerStats.GetStat(player, "projectileCount")))
	local speed = RangerArrowData.SPEED * math.max(0.2, PlayerStats.GetStat(player, "projectileSpeed"))
	local width = RangerArrowData.WIDTH * PlayerStats.GetStat(player, "size")
	local damage = math.floor(24 * PlayerStats.GetStat(player, "damage"))
	local knockback = PlayerStats.GetStat(player, "knockback")
	local predicted = shot ~= nil
	if not shot then
		serverShot += 1
		shot = 900000 + serverShot % 90000
	end
	local targets = getPotentialTargets(char)
	local positions = {}
	for i, t in ipairs(targets) do positions[i] = t.rootPart.Position end
	local shots = {}
	for index, dir in ipairs(RangerArrowData.Directions(look, count)) do
		dir = RangerArrowData.Assist(origin, dir, positions, function(i) return lineReach(targets[i], width) end)
		local key = RangerArrowData.Key(shot :: number, index)
		table.insert(flyingArrows, {
			player = player, char = char, key = key, pos = origin, dir = dir,
			speed = speed, left = RangerArrowData.RANGE, width = width, damage = damage, knockback = knockback,
		})
		table.insert(shots, { key = key, origin = origin, dir = dir })
	end
	if not arrowConn then arrowConn = RunService.Heartbeat:Connect(stepArrows) end
	-- (everyone else draws them; the shooter already has, if it predicted)
	if fxAllowed(player, "arrowFire", 20) then
		local msg = { kind = "fire", attacker = player, speed = speed, shots = shots }
		for _, other in ipairs(Players:GetPlayers()) do
			if other ~= player or not predicted then arrowRemote():FireClient(other, msg) end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Barrier helper: a collidable ring of parts that physically stops players from
-- walking out of a rooted area (vine root / ult cage). Parts are spaced so they
-- never collide with each other, only with characters.
-- ─────────────────────────────────────────────────────────────────────────────
local function buildBarrierRing(center: Vector3, radius: number, height: number, color: Color3, transparency: number, name: string, collisionGroup: string?)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = Workspace.Terrain

	local SEG = math.max(24, math.floor(radius * 4))
	local segLen = (2 * math.pi * radius) / SEG
	local countPer = math.max(2, math.floor((segLen / 0.4)))
	local spacing = segLen / countPer

	for s = 1, SEG do
		local ang = (s / SEG) * math.pi * 2
		local px = center.X + math.cos(ang) * radius
		local pz = center.Z + math.sin(ang) * radius
		local tangent = Vector3.new(-math.sin(ang), 0, math.cos(ang))
		for k = 1, countPer do
			local off = -segLen / 2 + spacing * (k - 0.5)
			local p = Instance.new("Part")
			p.Name = "Barrier"
			p.Size = Vector3.new(0.35, height, 0.35)
			p.Material = Enum.Material.Neon
			p.Color = color
			p.Transparency = transparency
			p.Anchored = true
			p.CanCollide = true
			p.CanTouch = false
			p.CanQuery = false
			if collisionGroup then
				pcall(function() p.CollisionGroup = collisionGroup end)
			end
			p.CFrame = CFrame.new(Vector3.new(px, center.Y, pz) + tangent * off + Vector3.new(0, height / 2, 0))
			p.Parent = folder
		end
	end
	return folder
end

local function spawnVineBarrier(center: Vector3, radius: number, duration: number)
	-- Invisible; height matches the vine cage visual (14 studs)
	local folder = buildBarrierRing(center, radius, 14, Color3.fromRGB(60, 140, 55), 1, "VineRootBarrier")
	Debris:AddItem(folder, duration + 0.5)
end

local function spawnUltBarrier(center: Vector3, radius: number, duration: number, casterChar: Model?)
	ensureUltCollisionGroups()
	-- Invisible; height matches the vine cage visual (14 studs)
	local folder = buildBarrierRing(center, radius, 14, Color3.fromRGB(70, 200, 90), 1, "RainOfArrowsBarrier", ULT_BARRIER_GROUP)
	-- Put the caster in a group that does not collide with the barrier so he can leave the AoE.
	if casterChar then
		setCharacterCollisionGroup(casterChar, ULT_CASTER_GROUP)
		task.delay(duration + 0.6, function()
			if casterChar and casterChar.Parent then
				setCharacterCollisionGroup(casterChar, "Default")
			end
		end)
	end
	Debris:AddItem(folder, duration + 0.6)
end

local function rootTarget(target: { character: Model, humanoid: Humanoid, rootPart: BasePart }, duration: number)
	local root = target.rootPart
	local oldWalkSpeed = target.humanoid.WalkSpeed
	local oldJumpPower = target.humanoid.JumpPower
	root.Anchored = true
	target.humanoid.WalkSpeed = 0
	target.humanoid.JumpPower = 0
	task.delay(duration, function()
		if root and root.Parent then
			root.Anchored = false
		end
		if target.character and target.character.Parent and target.humanoid and target.humanoid.Health > 0 then
			target.humanoid.WalkSpeed = oldWalkSpeed
			target.humanoid.JumpPower = oldJumpPower
		end
	end)
end

local function executeRangerVerdantSlash(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local damage = config.damage or 38
	local dashDist = config.dashDistance or 32
	local hitboxWidth = (config.width or 6.0) * (config.areaMultiplier or 1)
	local flatDir = rotateFlatDirection(lookDir, 0)
	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then return end

	-- 1. Obstacle raycast: stop before walls/geometry, passing freely through enemies & players
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local ignoreList: { Instance } = { casterChar }
	for model in pairs(humanoidModels) do
		table.insert(ignoreList, model)
	end
	rayParams.FilterDescendantsInstances = ignoreList
	rayParams.IgnoreWater = true

	local forwardRay = Workspace:Raycast(origin + Vector3.new(0, 1.2, 0), flatDir * dashDist, rayParams)
	local actualDist = dashDist
	if forwardRay and forwardRay.Distance > 0 then
		actualDist = math.max(3.0, forwardRay.Distance - 1.5)
	end

	local endPos = origin + flatDir * actualDist

	-- Maintain ground alignment at destination
	local groundRay = Workspace:Raycast(endPos + Vector3.new(0, 4, 0), Vector3.new(0, -10, 0), rayParams)
	if groundRay then
		local humanoid = casterChar:FindFirstChildOfClass("Humanoid")
		local hipHeight = humanoid and humanoid.HipHeight or 2.0
		endPos = Vector3.new(endPos.X, groundRay.Position.Y + (casterRoot.Size.Y * 0.5) + hipHeight, endPos.Z)
	end

	-- Move caster rootPart on server to synchronize authoritative position
	casterRoot.CFrame = CFrame.lookAt(endPos, endPos + flatDir)
	casterRoot.AssemblyLinearVelocity = Vector3.zero

	-- 2. Line-segment hitbox: hit all potential targets along the dash path
	local knockback = PlayerStats.GetStat(player, "knockback")
	local targets = getPotentialTargets(casterChar)
	local hitCount = 0

	for _, target in ipairs(targets) do
		local diff = target.rootPart.Position - origin
		local flatDiff = Vector3.new(diff.X, 0, diff.Z)
		local along = flatDiff:Dot(flatDir)

		-- Within line segment range (with slight leeway)
		if along >= -1.0 and along <= (actualDist + 1.5) then
			local closestPoint = origin + flatDir * math.clamp(along, 0, actualDist)
			local lateralDist = (Vector3.new(target.rootPart.Position.X, origin.Y, target.rootPart.Position.Z) - closestPoint).Magnitude

			if lateralDist <= hitboxWidth then
				hitCount += 1
				dealDamage(player, target, damage, "VERDANT SLASH")

				-- Forward pierce impulse + slight lift
				local impulseDir = (flatDir * 0.85 + Vector3.new(0, 0.25, 0)).Unit
				local impulseMag = target.rootPart.AssemblyMass * (12 + knockback * 8)
				target.rootPart:ApplyImpulse(impulseDir * impulseMag)
				print(`[SkillManager] Verdant Slash pierced {target.character.Name} for {damage} damage!`)
			end
		end
	end

	print(`[SkillManager] Verdant Slash dashed {math.floor(actualDist)} studs, hitting {hitCount} targets.`)
end

local function executeRangerEntanglingArrow(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local flatDir = rotateFlatDirection(lookDir, 0)
	local range = config.range or 44
	local arrowOrigin = origin + Vector3.new(0, 1.2, 0)
	local directHit, hitDistance = damageFirstTargetOnLine(player, casterChar, arrowOrigin, flatDir, range, 2.8 * (config.areaMultiplier or 1), config.damage or 30, "ENTANGLING ARROW")
	local projectileSpeed = PlayerStats.GetStat(player, "projectileSpeed")
	fireRangerArrowVisual(arrowOrigin, flatDir, hitDistance or range, projectileSpeed)
	local impactPos = directHit and directHit.rootPart.Position or (origin + flatDir * range)
	local radius = 10 * (config.areaMultiplier or 1)
	local damage = math.floor((config.damage or 30) * 0.75)
	local rootDuration = config.duration or 2.6

	-- Physical vine barrier so rooted targets cannot walk out of the vines
	spawnVineBarrier(impactPos, radius, rootDuration)

	for _, target in ipairs(getPotentialTargets(casterChar)) do
		local dist = (target.rootPart.Position - impactPos).Magnitude
		if dist <= radius then
			if target.character ~= (directHit and directHit.character) then
				dealDamage(player, target, damage, "ENTANGLING ARROW")
			end
			rootTarget(target, rootDuration)
		end
	end

	print(`[SkillManager] Entangling Arrow impacted at {math.floor(hitDistance or range)} studs.`)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Hitbox: Skill 3 — Seeker Barrage (Buff: Attacks launch guided missiles)
-- ─────────────────────────────────────────────────────────────────────────────
local function executeMissileBuff(player: Player, casterChar: Model, config: any)
	local duration = config.duration or 8.0
	casterChar:SetAttribute("IsMissileBuffActive", true)

	task.delay(duration, function()
		if casterChar and casterChar.Parent then
			casterChar:SetAttribute("IsMissileBuffActive", false)
		end
	end)

	print(`[SkillManager] {player.Name} activated Seeker Barrage missile buff for {duration}s!`)
end

function SkillManager.HandleMissileAttack(player: Player, casterChar: Model)
	local root = casterChar:FindFirstChild("HumanoidRootPart") or casterChar.PrimaryPart
	if not root then return end
	local origin = root.Position

	local extraProjectiles = math.max(0, math.floor(PlayerStats.GetStat(player, "projectileCount")))
	local totalMissiles = 3 + extraProjectiles
	local speedMult = math.max(0.2, PlayerStats.GetStat(player, "projectileSpeed"))
	local delayStep = 0.035 / math.max(speedMult, 0.5)

	-- Fast missile strikes per attack matching projectile tome stats
	for i = 1, totalMissiles do
		task.spawn(function()
			task.wait((0.10 + (i - 1) * delayStep) / math.max(speedMult, 0.5))
			if not casterChar or not casterChar.Parent then return end

			local targets = getPotentialTargets(casterChar)
			local closestTarget = nil
			local closestDist = 65

			for _, t in ipairs(targets) do
				local d = (t.rootPart.Position - origin).Magnitude
				if d < closestDist then
					closestDist = d
					closestTarget = t
				end
			end

			if closestTarget and closestTarget.humanoid and closestTarget.humanoid.Health > 0 then
				local damage = math.floor(20 * PlayerStats.GetStat(player, "damage"))
				dealDamage(player, closestTarget, damage, "SEEKER BARRAGE")
				local kbDir = (closestTarget.rootPart.Position - origin).Unit + Vector3.new(0, 0.25, 0)
				closestTarget.rootPart:ApplyImpulse(kbDir.Unit * (closestTarget.rootPart.AssemblyMass * 12))
				print(`[SkillManager] Seeker Missile #{i}/{totalMissiles} struck {closestTarget.character.Name} for {damage} damage!`)
			end
		end)
	end
end

local function executeRangerRainOfArrows(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, targetPosition: any, config: any)
	local center = getRangerCursorTarget(origin, lookDir, targetPosition, config.range or 42)
	local radius = 18 * (config.areaMultiplier or 1)
	local damage = config.damage or 24
	local duration = config.duration or 4.0

	task.spawn(function()
		task.wait(1.05)
		-- Physical ult cage so targets cannot leave the Rain of Arrows zone
		spawnUltBarrier(center, radius, duration + 0.2, casterChar)
		local startTime = os.clock()
		while os.clock() - startTime < duration do
			if not casterChar or not casterChar.Parent then break end
			for _, target in ipairs(getPotentialTargets(casterChar)) do
				local targetPos = target.rootPart.Position
				local offset = targetPos - center
				local flatOffset = Vector3.new(offset.X, 0, offset.Z)
				local dist = flatOffset.Magnitude

				if dist <= radius then
					-- Deal damage to all targets inside the zone
					dealDamage(player, target, damage, "RAIN OF ARROWS")
					local push = Vector3.new(0, 1, 0)
					target.rootPart:ApplyImpulse(push * (target.rootPart.AssemblyMass * 8))

					-- Root every target inside the cage so they can't walk out
					rootTarget(target, 0.6)

					-- If target is near the perimeter, pull them back inward
					if dist > radius - 3.5 and dist > 0.5 then
						local pullDir = -flatOffset.Unit
						local pullStrength = target.rootPart.AssemblyMass * 22
						target.rootPart:ApplyImpulse(pullDir * pullStrength + Vector3.new(0, target.rootPart.AssemblyMass * 3, 0))
					end
				end
			end
			task.wait(0.45)
		end
	end)
end


local Debris = game:GetService("Debris")
-- ─────────────────────────────────────────────────────────────────────────────
-- Cleric Basic Combat: Divine Touch + Divine Beam
-- ─────────────────────────────────────────────────────────────────────────────
local function healCharacter(targetChar: Model, amount: number, healer: Player?)
	local hum = targetChar and targetChar:FindFirstChildOfClass("Humanoid")
	if hum and hum.Health > 0 then
		local before = hum.Health
		-- (a Cursed elite's mark cuts healing hard; relics: Vampire Fang, Saint's Bell)
		if (targetChar:GetAttribute("CursedUntil") or 0) > os.clock() then amount *= MobKinds.CURSE_HEAL end
		amount = Boons.OnHeal(healer, targetChar, amount)
		hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
		if healer then RunStats.Add(healer, "healing", hum.Health - before) end
	end
end

local function getClericHealTarget(casterChar: Model, range: number): Model?
	local bestTarget: Model? = casterChar
	local bestFrac = 1.0
	local casterHum = casterChar:FindFirstChildOfClass("Humanoid")
	if casterHum and casterHum.MaxHealth > 0 then
		bestFrac = casterHum.Health / casterHum.MaxHealth
	end

	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then return bestTarget end

	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		local otherChar = otherPlayer.Character
		if otherChar and otherChar ~= casterChar and otherChar.Parent then
			local otherRoot = otherChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			local otherHum = otherChar:FindFirstChildOfClass("Humanoid")
			if otherRoot and otherHum and otherHum.Health > 0 then
				local dist = (otherRoot.Position - casterRoot.Position).Magnitude
				if dist <= range then
					local frac = otherHum.Health / math.max(otherHum.MaxHealth, 1)
					if frac < bestFrac then
						bestFrac = frac
						bestTarget = otherChar
					end
				end
			end
		end
	end

	return bestTarget
end

-- Returns where it healed (the player it chose, and an ally), so every
-- client draws the heal sign on whoever was actually healed.
local function executeClericDivineTouch(player: Player, casterChar: Model, config: any): { Vector3 }
	local healed: { Vector3 } = {}
	local range = config.range or 30
	local healAmount = config.healAmount or 35
	local targetChar = getClericHealTarget(casterChar, range)
	if targetChar then
		healCharacter(targetChar, healAmount, player)
		local tr = targetChar:FindFirstChild("HumanoidRootPart") :: BasePart?
		if tr then table.insert(healed, tr.Position) end
	end
	-- Allies: heal the hovered ally if the client named one, else the nearest ally in range.
	local root = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then
		local ally = nil
		if config.allyTarget then
			ally = AllyManager.GetAllyByName(config.allyTarget)
		end
		if not ally then
			ally = AllyManager.GetNearestAlly(root.Position, range)
		end
		if ally then
			AllyManager.HealAlly(ally, healAmount)
			local ar = (ally:FindFirstChild("HumanoidRootPart") or ally.PrimaryPart) :: BasePart?
			if ar then table.insert(healed, ar.Position) end
		end
	end
	return healed
end

local function executeClericDivineBeam(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local damage = config.damage or 40
	local range = config.range or 48
	local duration = config.duration or 5.0
	local halfWidth = math.max(0.5, (config.width or 3.0) * (config.areaMultiplier or 1) * 0.5)
	local TICK = 0.5
	local perHit = damage * TICK / math.max(duration, 0.001)
	local numBeams = 1 + math.max(0, math.floor(config.projectileCount or 0))
	local spreadDeg = if numBeams > 1 then math.clamp(12, 6, 60 / (numBeams - 1)) else 0

	-- Channeled holy laser: tick damage for the full channel, tracking the caster's facing
	-- (the client rotates the character to face the cursor, so LookVector IS the aim).
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			if not casterChar or not casterChar.Parent then break end
			local root = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then break end
			local curOrigin = root.Position
			local flatDir = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
			if flatDir.Magnitude < 0.001 then flatDir = Vector3.new(0, 0, -1) end
			flatDir = flatDir.Unit

			local beamDirs = {}
			if numBeams <= 1 then
				table.insert(beamDirs, flatDir)
			else
				local startAngle = - (numBeams - 1) * spreadDeg * 0.5
				for i = 1, numBeams do
					local deg = startAngle + (i - 1) * spreadDeg
					table.insert(beamDirs, rotateFlatDirection(flatDir, deg))
				end
			end

			local damagedThisTick = {}
			for _, target in ipairs(getPotentialTargets(casterChar)) do
				local offset = target.rootPart.Position - curOrigin
				local flatOffset = Vector3.new(offset.X, 0, offset.Z)
				local vertical = math.abs(offset.Y)
				if vertical <= 6 then
					for _, bDir in ipairs(beamDirs) do
						local along = flatOffset:Dot(bDir)
						if along >= 0 and along <= range then
							local lateral = (flatOffset - bDir * along).Magnitude
							if lateral <= lineReach(target, halfWidth) then
								if not damagedThisTick[target] then
									damagedThisTick[target] = true
									dealDamage(player, target, perHit, "DIVINE BEAM")
								end
								break
							end
						end
					end
				end
			end
			task.wait(TICK)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleric Ultimate: Divine Ascent (Heal allies, purge debuffs, holy judgment)
-- ─────────────────────────────────────────────────────────────────────────────

local function executeClericDivineAscent(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local humanoid = casterChar:FindFirstChildOfClass("Humanoid")
	if not casterRoot or not humanoid then return end

	local healAmount = (config.healAmount or 100) * (config.areaMultiplier or 1)
	local damage = config.damage or 90
	local radius = (config.range or 30) * (config.areaMultiplier or 1)
	local duration = config.duration or 5.5
	local reviveTime = math.min(config.reviveTime or 3.7, duration)

	-- Kneel where they stand: root the Cleric (facing the aim) for the cinematic.
	local flat = Vector3.new(lookDir.X, 0, lookDir.Z)
	if flat.Magnitude < 0.001 then flat = casterRoot.CFrame.LookVector end
	flat = Vector3.new(flat.X, 0, flat.Z).Unit
	local kneelCF = CFrame.lookAt(casterRoot.Position, casterRoot.Position + flat)
	casterChar:SetAttribute("IsSkillCasting", true)
	casterRoot.Anchored = true
	casterRoot.CFrame = kneelCF

	-- THE REVIVAL: fallen teammates rise beside the Cleric, players are healed
	-- and cleansed, enemies are smitten.
	task.delay(reviveTime, function()
		if not casterChar.Parent then return end
		local okDM, DeathManager = pcall(function()
			return require(script.Parent:WaitForChild("DeathManager")) :: any
		end)
		if okDM and DeathManager then
			DeathManager.ReviveParty(player, casterRoot.Position + flat * 3)
		end
		for _, other in ipairs(Players:GetPlayers()) do
			local oc = other.Character
			local oroot = oc and oc:FindFirstChild("HumanoidRootPart")
			if oc and oroot and (oroot.Position - origin).Magnitude <= radius then
				healCharacter(oc, healAmount, player)
				oc:SetAttribute("DebuffCleanse", os.clock())
			end
		end
		for _, target in ipairs(getPotentialTargets(casterChar)) do
			if not Players:GetPlayerFromCharacter(target.character) and (target.rootPart.Position - origin).Magnitude <= radius then
				dealDamage(player, target, damage, "DIVINE ASCENT")
				local kb = target.rootPart.Position - origin
				local flatKb = Vector3.new(kb.X, 0, kb.Z)
				local kbDir = (flatKb.Magnitude > 0.1 and flatKb.Unit or Vector3.new(0, 0, 1)) + Vector3.new(0, 0.5, 0)
				target.rootPart:ApplyImpulse(kbDir.Unit * (target.rootPart.AssemblyMass * 30))
			end
		end
	end)

	-- End: release the Cleric.
	task.delay(duration, function()
		if casterChar.Parent then
			local root2 = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root2 then
				root2.Anchored = false
				pcall(function() root2:SetNetworkOwner(player) end)
			end
			casterChar:SetAttribute("IsSkillCasting", false)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Cleric Skill 3: Radiant Ground (consecrated zone that heals allies over time,
-- cleanses them, and scorches enemies standing inside it)
-- ─────────────────────────────────────────────────────────────────────────────
local function executeClericRadiantGround(player: Player, casterChar: Model, origin: Vector3, config: any)
	local radius = (config.range or 16) * (config.areaMultiplier or 1)
	local healAmount = math.floor((config.healAmount or 12) * (config.areaMultiplier or 1))
	local damage = math.floor(config.damage or 10)
	local flatOrigin = Vector3.new(origin.X, origin.Y, origin.Z)

	-- Instant holy burst centred on the caster: heal + cleanse allies in radius.
	for _, other in ipairs(Players:GetPlayers()) do
		local oc = other.Character
		if oc and oc.Parent then
			local oroot = oc:FindFirstChild("HumanoidRootPart") :: BasePart?
			local ohum = oc:FindFirstChildOfClass("Humanoid")
			if oroot and ohum and ohum.Health > 0 then
				local flatOffset = Vector3.new(oroot.Position.X - flatOrigin.X, 0, oroot.Position.Z - flatOrigin.Z)
				if flatOffset.Magnitude <= radius then
					healCharacter(oc, healAmount, player)
					oc:SetAttribute("DebuffCleanse", os.clock())
				end
			end
		end
	end

	-- Heal / revive allies inside the burst too.
	AllyManager.HealAlliesInRadius(flatOrigin, radius, healAmount)

	-- Scorch enemies in the burst (never friendly-fire other players).
	for _, target in ipairs(getPotentialTargets(casterChar)) do
		if not Players:GetPlayerFromCharacter(target.character) then
			local offset = target.rootPart.Position - flatOrigin
			local flatOffset = Vector3.new(offset.X, 0, offset.Z)
			if flatOffset.Magnitude <= radius then
				dealDamage(player, target, damage, "RADIANT GROUND")
			end
		end
	end
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Ice Mage
-- ─────────────────────────────────────────────────────────────────────────────
local ICE_CORE = Color3.fromRGB(150, 235, 255)
local ICE_BODY = Color3.fromRGB(120, 200, 255)

local function fireIceEvent(payload: any)
	Network.GetRemoteEvent(Network.Remotes.IceMageEvent):FireAllClients(payload)
end

local function chillTarget(target: any, duration: number)
	if Players:GetPlayerFromCharacter(target.character) then return end
	MobManager.ChillMob(target.character, duration)
	fireIceEvent({ kind = "Chill", model = target.character, duration = duration })
end

-- Skill 1: a line of spikes races along the floor; each enemy is hit when the
-- spike front reaches it, so damage lines up with the eruption the clients see.
local function executeIceSpikes(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local range = config.range or 42
	local halfWidth = (config.width or 4) * (config.areaMultiplier or 1) * 0.5 + 1
	local speed = config.projectileSpeed or 95
	local flatDir = rotateFlatDirection(lookDir, 0)
	for _, target in ipairs(getPotentialTargets(casterChar)) do
		local offset = target.rootPart.Position - origin
		local flatOffset = Vector3.new(offset.X, 0, offset.Z)
		local along = flatOffset:Dot(flatDir)
		if along >= 0 and along <= range and (flatOffset - flatDir * along).Magnitude <= halfWidth and math.abs(offset.Y) <= 8 then
			task.delay(along / speed, function()
				if target.humanoid.Health <= 0 then return end
				dealDamage(player, target, config.damage, "ICE SPIKES")
				chillTarget(target, 0.9)
			end)
		end
	end
end

-- Skill 2: channelled beam that stops on the first enemy along the caster's facing (supports multi-beam from projectileCount).
local function executeIceBeam(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local range = config.range or 55
	local duration = config.duration or 3
	local width = (config.width or 3) * (config.areaMultiplier or 1) * 0.5 + 0.5
	local TICK = 0.25
	local perHit = config.damage * TICK / math.max(duration, 0.001)
	local numBeams = 1 + math.max(0, math.floor(config.projectileCount or 0))
	local spreadDeg = if numBeams > 1 then math.clamp(12, 6, 60 / (numBeams - 1)) else 0

	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			local root = casterChar.Parent and casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then break end

			local startAngle = if numBeams > 1 then - (numBeams - 1) * spreadDeg * 0.5 else 0
			for i = 1, numBeams do
				local deg = if numBeams > 1 then (startAngle + (i - 1) * spreadDeg) else 0
				local bDir = rotateFlatDirection(root.CFrame.LookVector, deg)
				local target = damageFirstTargetOnLine(player, casterChar, root.Position, bDir, range, width, perHit, "ICE BEAM")
				if target then
					chillTarget(target, TICK + 0.3)
				end
			end
			task.wait(TICK)
		end
	end)
end

-- Skill 3: crystalline clone of the caster that taunts, then explodes.
local function buildIceClone(casterChar: Model, cframe: CFrame, health: number): Model?
	local wasArchivable = casterChar.Archivable
	casterChar.Archivable = true
	local clone = casterChar:Clone()
	casterChar.Archivable = wasArchivable
	if not clone then return nil end

	clone.Name = "IceClone"
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("Script") or d:IsA("LocalScript") or d:IsA("Tool") or d:IsA("ForceField")
			or d:IsA("ParticleEmitter") or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light")
			or d:IsA("BillboardGui") or d:IsA("Sound") or d:IsA("Clothing") or d:IsA("ShirtGraphic") then
			d:Destroy()
		elseif d:IsA("Decal") then
			d.Transparency = 0.6
			d.Color3 = ICE_CORE
		end
	end
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanTouch = false
			d.CastShadow = false
			d.Massless = true
			if d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
				d.Material = Enum.Material.Glass
				d.Color = ICE_BODY
				d.Transparency = 0.35
				d.Reflectance = 0.25
				if d:IsA("MeshPart") then d.TextureID = "" end
				local sm = d:FindFirstChildOfClass("SpecialMesh")
				if sm then sm.TextureId = "" end
			end
		end
	end

	local hum = clone:FindFirstChildOfClass("Humanoid")
	local root = clone:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root then
		clone:Destroy()
		return nil
	end
	hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	hum.BreakJointsOnDeath = false
	hum.RequiresNeck = false
	hum.WalkSpeed = 0
	hum.JumpPower = 0
	hum.MaxHealth = health
	hum.Health = health
	root.CanCollide = true
	root.Anchored = true
	clone:SetAttribute("IsDecoy", true)
	clone:PivotTo(cframe)
	return clone
end

local function executeIceClone(player: Player, casterChar: Model, origin: Vector3, lookDir: Vector3, config: any)
	local casterRoot = casterChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not casterRoot then return end
	local flatDir = rotateFlatDirection(lookDir, 0)
	local spawnPos = casterRoot.Position + flatDir * 6
	-- Don't put the clone inside a wall.
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = { casterChar }
	local wallHit = Workspace:Raycast(casterRoot.Position, flatDir * 7, rp)
	if wallHit then spawnPos = casterRoot.Position + flatDir * math.max(0, wallHit.Distance - 2) end

	local tauntRadius = (config.range or 34) * (config.areaMultiplier or 1)
	local clone = buildIceClone(casterChar, CFrame.lookAt(spawnPos, spawnPos + flatDir), config.cloneHealth or 50)
	if not clone then return end
	local folder = Workspace:FindFirstChild("IceClones")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "IceClones"
		folder.Parent = Workspace
	end
	clone:SetAttribute("TauntRadius", tauntRadius)
	clone.Parent = folder
	MobManager.RegisterDecoy(clone, tauntRadius)

	local hum = clone:FindFirstChildOfClass("Humanoid") :: Humanoid
	local shattered = false
	local function shatter()
		if shattered then return end
		shattered = true
		MobManager.UnregisterDecoy(clone)
		local pos = clone:GetPivot().Position
		local radius = (config.explosionRadius or 14) * (config.areaMultiplier or 1)
		fireIceEvent({ kind = "CloneShatter", position = pos, radius = radius })
		for _, target in ipairs(getPotentialTargets(casterChar)) do
			if not Players:GetPlayerFromCharacter(target.character) and (target.rootPart.Position - pos).Magnitude <= radius then
				dealDamage(player, target, config.damage, "SHATTER")
				chillTarget(target, 2.0)
			end
		end
		clone:Destroy()
	end
	hum.Died:Connect(shatter)
	task.delay(config.duration or 10, shatter)
	casterChar.AncestryChanged:Connect(function(_, parent)
		if not parent then shatter() end
	end)
end

-- Ultimate: Blizzard. Mobs are frozen through the reveal cutscene;
-- the storm batters everything inside the zone on a steady tick.
local function executeIceBlizzard(player: Player, casterChar: Model, origin: Vector3, config: any)
	local radius = (config.range or 48) * (config.areaMultiplier or 1)
	local duration = config.duration or 6
	local TICK = 0.5
	local perHit = config.damage * TICK / math.max(duration, 0.001)
	task.spawn(function()
		local t0 = os.clock()
		while os.clock() - t0 < duration do
			for _, target in ipairs(getPotentialTargets(casterChar)) do
				if not Players:GetPlayerFromCharacter(target.character) then
					local offset = target.rootPart.Position - origin
					if Vector3.new(offset.X, 0, offset.Z).Magnitude <= radius then
						dealDamage(player, target, perHit, "BLIZZARD")
					end
				end
			end
			task.wait(TICK)
		end
	end)
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Main Skill Request Handler
-- ─────────────────────────────────────────────────────────────────────────────
local ultCutscene: (string, any) -> number

function SkillManager.HandleSkillUse(player: Player, payload: any)
	if typeof(payload) ~= "table" then return end

	local skillIndex = payload.skillIndex
	if typeof(skillIndex) ~= "number" or skillIndex < 1 or skillIndex > 4 then return end

	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end

	-- Block skills in lobby
	if player:GetAttribute("InLobby") ~= false then return end -- (only in a run: never in the lobby)
	-- Thrown off a mount: nothing till back on their feet. Riding: casting gets them off.
	if MountManager.IsTumbling(player) then return end
	MountManager.Dismount(player)

	-- Block skills while a tome/level-up selection is pausing the game.
	if RunScope.Paused(player.Character) then
		if player:GetAttribute("SelectedClass") == "gunslinger" then GunslingerServer.Refused(player, skillIndex) end
		return
	end

	-- Block skill use while Skill 1 (Spin Attack) is active
	if char:GetAttribute("IsSkill1Active") == true or char:GetAttribute("IsSpinAttackActive") == true then
		warn(`[SkillManager] {player.Name} attempted to cast skill while Skill 1 was active!`)
		return
	end

	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" then return end
	local config = SkillData.GetSkill(classId, skillIndex)
	if not config then return end
	local effectiveConfig = table.clone(config)
	effectiveConfig.damage *= PlayerStats.GetStat(player, "damage")
	effectiveConfig.cooldown *= PlayerStats.GetStat(player, "abilityCooldown")
	if effectiveConfig.duration then
		effectiveConfig.duration *= PlayerStats.GetStat(player, "abilityDuration")
	end
	if effectiveConfig.projectileSpeed then
		effectiveConfig.projectileSpeed *= PlayerStats.GetStat(player, "projectileSpeed")
	end
	effectiveConfig.areaMultiplier = PlayerStats.GetStat(player, "size")
	effectiveConfig.projectileCount = math.max(0, math.floor(PlayerStats.GetStat(player, "projectileCount")))
	effectiveConfig.allyTarget = payload.allyTarget

	-- Gunslinger: e.g. Fan the Hammer needs bullets in the cylinder.
	if classId == "gunslinger" and not GunslingerServer.CanUseSkill(player, skillIndex) then
		GunslingerServer.Refused(player, skillIndex)
		return
	end
	-- Swordsman: nothing mid-Whirlwind / mid-Blade Storm.
	if classId == "swordsman" and not SwordsmanServer.CanUseSkill(player, skillIndex) then return end
	-- Rogue: nothing mid-Shadow Realm; E with a dagger out is the Shadow Step (no cooldown).
	if classId == "rogue" then
		if not RogueServer.CanUseSkill(player, skillIndex) then return end
		if RogueServer.TryRecast(player, char, skillIndex) then return end
	end
	-- Berserker: nothing mid-leap, mid-Bloodstorm or mid-Worldbreaker.
	if classId == "berserker" and not BerserkerServer.CanUseSkill(player, skillIndex) then return end
	-- Fire Knight: nothing mid-charge / mid-guard / mid-slam / mid-awakening.
	if classId == "heavy_knight" and not FireKnightServer.CanUseSkill(player, skillIndex) then return end

	-- Validate Cooldown
	local now = os.clock()
	if not playerCooldowns[player] then
		playerCooldowns[player] = {}
	end

	local lastUsed = playerCooldowns[player][skillIndex] or 0
	local cdBuffer = 0.12 -- 120ms leeway for latency
	local charges = (config :: any).charges
	if charges and charges > 1 then
		chargesFullAt[player] = chargesFullAt[player] or {}
		local fullAt = math.max(chargesFullAt[player][skillIndex] or 0, now)
		local per = effectiveConfig.cooldown
		if fullAt - now > (charges - 1) * per + cdBuffer then
			Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate):FireClient(player, {
				skillIndex = skillIndex, cooldown = fullAt - now, per = per,
			})
			return
		end
		chargesFullAt[player][skillIndex] = fullAt + per
		-- (the plain check below lets it through)
		lastUsed = -math.huge
	end
	if now - lastUsed < (effectiveConfig.cooldown - cdBuffer) then
		-- The client thought it was ready (e.g. its timer drifted): resync
		-- its cooldown to ours instead of silently eating the cast.
		Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate):FireClient(player, {
			skillIndex = skillIndex,
			cooldown = effectiveConfig.cooldown,
			elapsed = now - lastUsed,
		})
		if classId == "gunslinger" then GunslingerServer.Refused(player, skillIndex) end
		return
	end

	-- Mark cooldown
	playerCooldowns[player][skillIndex] = now
	RunStats.Add(player, "abilities", 1)
	Boons.OnAbility(player)
	cooldownLengths[player] = cooldownLengths[player] or {}
	cooldownLengths[player][skillIndex] = effectiveConfig.cooldown

	-- Direction and origin extraction
	local clientOrigin = typeof(payload.origin) == "Vector3" and payload.origin or rootPart.Position
	local origin = rootPart.Position
	-- Check for reasonable origin proximity
	if (clientOrigin - rootPart.Position).Magnitude < 10 then
		origin = clientOrigin
	end

	local direction = rootPart.CFrame.LookVector
	if typeof(payload.direction) == "Vector3" and payload.direction.Magnitude > 0.1 then
		direction = Vector3.new(payload.direction.X, 0, payload.direction.Z).Unit
	end
	local targetPosition = payload.targetPosition
	local healAt: { Vector3 }? = nil -- Divine Touch: who it actually healed
	if classId == "ranger" and skillIndex == 4 then
		targetPosition = getRangerCursorTarget(origin, direction, targetPosition, effectiveConfig.range or 42)
	end

	-- Execute authoritative skill logic
	if classId == "ranger" then
		if skillIndex == 1 then
			executeRangerVerdantSlash(player, char, origin, direction, effectiveConfig)
		elseif skillIndex == 2 then
			executeRangerEntanglingArrow(player, char, origin, direction, effectiveConfig)
		elseif skillIndex == 3 then
			executeMissileBuff(player, char, effectiveConfig)
		elseif skillIndex == 4 then
			executeRangerRainOfArrows(player, char, origin, direction, targetPosition, effectiveConfig)
		end
	elseif classId == "heavy_knight" then
		FireKnightServer.OnSkill(player, char, skillIndex, origin, direction, effectiveConfig)
	elseif classId == "cleric" and skillIndex == 1 then
		healAt = executeClericDivineTouch(player, char, effectiveConfig)
	elseif classId == "cleric" and skillIndex == 2 then
		executeClericDivineBeam(player, char, origin, direction, effectiveConfig)
	elseif classId == "cleric" and skillIndex == 3 then
		executeClericRadiantGround(player, char, origin, effectiveConfig)
	elseif classId == "cleric" and skillIndex == 4 then
		executeClericDivineAscent(player, char, origin, direction, effectiveConfig)
	elseif classId == "gunslinger" then
		GunslingerServer.OnSkill(player, char, skillIndex, origin, direction, targetPosition, effectiveConfig)
	elseif classId == "swordsman" then
		SwordsmanServer.OnSkill(player, char, skillIndex, origin, direction, effectiveConfig)
	elseif classId == "rogue" then
		RogueServer.OnSkill(player, char, skillIndex, origin, direction, effectiveConfig)
	elseif classId == "berserker" then
		BerserkerServer.OnSkill(player, char, skillIndex, origin, direction, effectiveConfig,
			if typeof(targetPosition) == "Vector3" then targetPosition else nil)
	elseif classId == "ice_mage" then
		if skillIndex == 1 then
			-- Hits line up with the cast pose's impact frame (castDelay).
			task.delay(effectiveConfig.castDelay or 0, executeIceSpikes, player, char, origin, direction, effectiveConfig)
		elseif skillIndex == 2 then
			executeIceBeam(player, char, origin, direction, effectiveConfig)
		elseif skillIndex == 3 then
			task.delay(effectiveConfig.castDelay or 0, executeIceClone, player, char, origin, direction, effectiveConfig)
		elseif skillIndex == 4 then
			task.delay(effectiveConfig.castDelay or 0, executeIceBlizzard, player, char, origin, effectiveConfig)
		end
	end

	-- Ultimates freeze every mob only while the cutscene plays; they move
	-- again as the camera cuts back.
	if skillIndex == 4 then
		MobManager.FreezeMobs(ultCutscene(classId, effectiveConfig) + 0.1, RunScope.Of(char))
	end

	-- Replicate VFX to other players (for Skill 4, fire to ALL including caster
	-- since server handles the main VFX and caster needs client-side camera/particles)
	-- (Divine Touch goes to the caster too: only the server knows who it healed.)
	local vfxRemote = Network.GetRemoteEvent(Network.Remotes.SkillVFX)
	for _, otherPlayer in ipairs(Players:GetPlayers()) do
		-- For skill 4: server spawns main VFX, so only send for client-side extras
		-- For other skills: send to everyone except caster (caster already plays locally)
		if otherPlayer ~= player or skillIndex == 4 or healAt then
			if skillIndex ~= 4 or otherPlayer ~= player then
				vfxRemote:FireClient(otherPlayer, {
					player = player,
					skillIndex = skillIndex,
					origin = origin,
					direction = direction,
					targetPosition = targetPosition,
					projectileCount = effectiveConfig.projectileCount,
					areaMultiplier = effectiveConfig.areaMultiplier,
					healAt = healAt,
				})
			end
		end
	end

	-- Confirm Cooldown to Caster
	local cdRemote = Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate)
	local fullAt = chargesFullAt[player] and chargesFullAt[player][skillIndex]
	if (config :: any).charges and (config :: any).charges > 1 and fullAt then
		cdRemote:FireClient(player, {
			skillIndex = skillIndex,
			cooldown = math.max(0, fullAt - os.clock()),
			per = effectiveConfig.cooldown,
		})
	else
		cdRemote:FireClient(player, {
			skillIndex = skillIndex,
			cooldown = effectiveConfig.cooldown,
		})
	end

	print(`[SkillManager] {player.Name} successfully cast Skill {skillIndex} ({config.name})`)
end

-- Seconds each class's ult cutscene holds the camera (matches the client).
ultCutscene = function(classId: string, config: any): number
	if classId == "cleric" then return config.duration or 2 end
	if classId == "ice_mage" then return config.castDelay or 1.5 end
	if classId == "gunslinger" then return 1.4 end
	if classId == "swordsman" then return SwordsmanServer.STORM_WINDUP end
	if classId == "rogue" then return RogueServer.REALM_WINDUP end
	if classId == "berserker" then return BerserkerServer.GATHER_TIME end -- Worldbreaker's gathering
	if classId == "heavy_knight" then return FireKnightServer.AWAKEN end
	return 1.0 -- Ranger close-up
end

function SkillManager.HandleBasicAttack(player: Player, payload: any)
	local char = player.Character
	if not char then return end

	local humanoid = char:FindFirstChildOfClass("Humanoid")
	local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not humanoid or not rootPart or humanoid.Health <= 0 then return end
	if player:GetAttribute("InLobby") ~= false then return end -- (only in a run: never in the lobby)
	if RunScope.Paused(player.Character) then return end
	-- Thrown off a mount: nothing till back on their feet. Riding: attacking gets them off.
	if MountManager.IsTumbling(player) then return end
	MountManager.Dismount(player)
	-- The Gunslinger's revolver has its own ammo, fire rate and roll shot.
	if player:GetAttribute("SelectedClass") == "gunslinger" then
		GunslingerServer.OnShoot(player, char, rootPart, payload)
		return
	end
	-- The Swordsman's 4-hit combo, Momentum and its own swing speed.
	if player:GetAttribute("SelectedClass") == "swordsman" then
		SwordsmanServer.OnBasic(player, char, rootPart, payload)
		return
	end
	-- The Rogue's dagger combo and Shadow Energy.
	if player:GetAttribute("SelectedClass") == "rogue" then
		RogueServer.OnBasic(player, char, rootPart, payload)
		return
	end
	-- The Berserker's greatsword chain and Bloodrage.
	if player:GetAttribute("SelectedClass") == "berserker" then
		BerserkerServer.OnBasic(player, char, rootPart, payload)
		return
	end
	-- The Fire Knight's Emberblade combo, Heat and Scorch.
	if player:GetAttribute("SelectedClass") == "heavy_knight" then
		FireKnightServer.OnBasic(player, char, rootPart, payload)
		return
	end
	local now = os.clock()
	local attackInterval = 0.38 / math.max(PlayerStats.GetStat(player, "basicAttackSpeed"), 0.1)
	if now - (basicAttackTimes[player] or 0) < attackInterval then return end
	basicAttackTimes[player] = now

	local origin = rootPart.Position
	local lookDir = rootPart.CFrame.LookVector
	if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then
		local requestedDirection = Vector3.new(payload.direction.X, 0, payload.direction.Z)
		if requestedDirection.Magnitude > 0.1 then
			lookDir = requestedDirection.Unit
		end
	end
	local flatLook = Vector3.new(lookDir.X, 0, lookDir.Z).Unit
	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" then return end

	-- Everyone else sees this attack too (the attacker already drew it).
	local fxRemote = Network.GetRemoteEvent(Network.Remotes.BasicAttackFX)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then
			fxRemote:FireClient(other, { attacker = player, classId = classId, direction = flatLook })
		end
	end

	if classId == "ranger" then
		if char:GetAttribute("IsMissileBuffActive") == true then
			SkillManager.HandleMissileAttack(player, char)
		end

		-- Real arrows: they fly, and hit when they get there (a generous hit
		-- line and a little aim assist: easy to land).
		local shot = if typeof(payload) == "table" and typeof(payload.shot) == "number" and payload.shot == payload.shot
			then math.clamp(math.floor(payload.shot), 0, 899999) else nil
		fireRangerVolley(player, char, origin + Vector3.new(0, 1.2, 0), flatLook, shot)
		return
	end

	if classId == "cleric" then
		-- Radiant Bolt: ranged holy projectile fired straight forward.
		local damage = math.floor(34 * PlayerStats.GetStat(player, "damage"))
		local boltOrigin = origin + Vector3.new(0, 1.4, 0)
		local hitWidth = 2.5 * PlayerStats.GetStat(player, "size")
		local target = damageFirstTargetOnLine(player, char, boltOrigin, flatLook, 60, hitWidth, damage, "RADIANT BOLT")
		if target then
			local kbDir = (flatLook + Vector3.new(0, 0.25, 0)).Unit
			target.rootPart:ApplyImpulse(kbDir * (target.rootPart.AssemblyMass * 8))
		end
		return
	end

	if classId == "ice_mage" then
		-- Ice Crystal: a single fast shard that hits the first enemy in line.
		local damage = math.floor(22 * PlayerStats.GetStat(player, "damage"))
		local hitWidth = 2.2 * PlayerStats.GetStat(player, "size")
		damageFirstTargetOnLine(player, char, origin + Vector3.new(0, 1.4, 0), flatLook, 60, hitWidth, damage, "ICE CRYSTAL")
		return
	end
end

-- Take `seconds` off a skill's remaining cooldown and tell the caster.
local function reduceCooldown(player: Player, skillIndex: number, seconds: number)
	-- (a charge skill: its recharge queue gets shorter)
	local fullAt = chargesFullAt[player] and chargesFullAt[player][skillIndex]
	local length0 = cooldownLengths[player] and cooldownLengths[player][skillIndex]
	if fullAt and length0 then
		chargesFullAt[player][skillIndex] = fullAt - seconds
		Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate):FireClient(player, {
			skillIndex = skillIndex, cooldown = math.max(0, fullAt - seconds - os.clock()), per = length0,
		})
		return
	end
	local last = playerCooldowns[player] and playerCooldowns[player][skillIndex]
	local length = cooldownLengths[player] and cooldownLengths[player][skillIndex]
	if not last or not length then return end
	playerCooldowns[player][skillIndex] = last - seconds
	Network.GetRemoteEvent(Network.Remotes.SkillCooldownUpdate):FireClient(player, {
		skillIndex = skillIndex,
		cooldown = length,
		elapsed = os.clock() - (last - seconds),
	})
end

function SkillManager.Init()
	GunslingerServer.Init({
		getPotentialTargets = getPotentialTargets,
		dealDamage = dealDamage,
		ricochet = ricochet,
		reduceCooldown = reduceCooldown,
		freezeMobs = MobManager.FreezeMobs,
		roomBoundsAt = MobManager.RoomBoundsAt,
	})
	SwordsmanServer.Init({
		getPotentialTargets = getPotentialTargets,
		dealDamage = dealDamage,
		setParryHook = MobManager.SetParryHook,
		roomBoundsAt = MobManager.RoomBoundsAt,
	})
	RogueServer.Init({
		getPotentialTargets = getPotentialTargets,
		dealDamage = dealDamage,
		reduceCooldown = reduceCooldown,
		cooldownLeft = function(player: Player, skillIndex: number): number
			local fullAt = chargesFullAt[player] and chargesFullAt[player][skillIndex]
			if fullAt then return math.max(0, fullAt - os.clock()) end
			local last = playerCooldowns[player] and playerCooldowns[player][skillIndex]
			local length = cooldownLengths[player] and cooldownLengths[player][skillIndex]
			if not last or not length then return 0 end
			return math.max(0, length - (os.clock() - last))
		end,
		addIncomingHook = MobManager.AddIncomingHook,
	})
	BerserkerServer.Init({
		getPotentialTargets = getPotentialTargets,
		dealDamage = dealDamage,
		addIncomingHook = MobManager.AddIncomingHook,
	})
	FireKnightServer.Init({
		getPotentialTargets = getPotentialTargets,
		dealDamage = dealDamage,
		addParryHook = MobManager.AddParryHook,
		addIncomingHook = MobManager.AddIncomingHook,
	})
	Boons.Init({
		dealDamage = dealDamage,
		getPotentialTargets = getPotentialTargets,
		getStat = PlayerStats.GetStat,
		chill = MobManager.ChillMob,
		addIncomingHook = MobManager.AddIncomingHook,
	})

	local useSkillRemote = Network.GetRemoteEvent(Network.Remotes.UseSkill)
	useSkillRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		SkillManager.HandleSkillUse(player, payload)
	end)

	local performAttackRemote = Network.GetRemoteEvent(Network.Remotes.PerformAttack)
	performAttackRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		SkillManager.HandleBasicAttack(player, payload)
	end)

	-- Picking a class starts a fresh run: fresh cooldowns (the client clears
	-- its own on ClassConfirmed). Deaths and revives keep them.
	Network.GetRemoteEvent(Network.Remotes.SelectClass).OnServerEvent:Connect(function(player: Player)
		playerCooldowns[player] = nil
		cooldownLengths[player] = nil
		chargesFullAt[player] = nil
	end)

	Players.PlayerRemoving:Connect(function(player: Player)
		playerCooldowns[player] = nil
		cooldownLengths[player] = nil
		chargesFullAt[player] = nil
		basicAttackTimes[player] = nil
	end)

	print("[SkillManager] Server SkillManager initialized.")
end

return SkillManager
