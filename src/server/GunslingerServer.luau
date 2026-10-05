--[[
	GunslingerServer.luau
	Server-authoritative Gunslinger kit. SkillManager routes the class here and
	passes its combat helpers in through Init (targets, damage, the Ricochet
	Tome, cooldown refunds), so hits, crits, impacts and friendly-fire rules
	stay identical to every other class.

	  Six Shooter   6 rounds (+2 per Extended Cylinder); the last one in the
	                cylinder is the Final Shot (+80%, heavy knockback). Empty →
	                automatic reload.
	  Deadeye       clean hits fill the meter; misses drain it (not while it's
	                full); it decays after a few seconds without a hit. Full:
	                the next hit is a Deadeye shot — guaranteed crit, pierces
	                everything in line — and empties the meter.
	  Q Ricochet    flips a coin straight up and shoots it at the top of its
	                rise (free shot). A struck coin (or a Lucky Coin that
	                survives and hangs, then gets hit again) splits into projectiles
	                that seek every enemy in the room, at least one each (extras
	                loop back over the nearest targets rather than vanishing).
	  E Fan         fires every remaining bullet in a quick, slightly spread
	                burst (can hit coins too).
	  Roll          brief invulnerability; the landing shot (sent by the
	                client) skips the fire-rate check once. Leaves flashbangs
	                behind (one, +1 per Projectile Count) that pop after a
	                short fuse and stun every enemy near them but bosses.
	  R High Noon   marks every enemy in the room (or in range, out of one),
	                shoots them one by one, executing with a Deadeye shot at
	                the end of each cylinder. Mobs are frozen for the ult's
	                standoff by SkillManager.

	State reaches clients as player attributes (GS_Ammo, GS_MaxAmmo,
	GS_Deadeye, GS_ReloadEnd, GS_ReloadTime); effects go out on the
	GunslingerFX remote.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local GunslingerServer = {}

-- ── Tuning ──────────────────────────────────────────────────────────────────
local BASE_AMMO = 6
local FIRE_INTERVAL = 0.26        -- seconds between shots at 1× attack speed
local BULLET_DAMAGE = 20
local BULLET_RANGE = 62
local BULLET_WIDTH = 1.9
local FINAL_SHOT_MULT = 1.8
local RELOAD_TIME = 1.1
local QUICK_HANDS = 0.7           -- reload time × this per Quick Hands

local DEADEYE_MAX = 100
local DEADEYE_GAIN = 17           -- per hit
local DEADEYE_MISS = 40           -- lost per miss
local DEADEYE_DECAY_AFTER = 3     -- seconds without a hit before it drains
local DEADEYE_DECAY_RATE = 30     -- per second
local DEADEYE_MULT = 1.6          -- × damage, and the hit is a guaranteed crit (×1.5)

local HIT_LENIENCY = 0.6 -- mobs move between the client's frame and ours
local CLAIM_SLACK = 5    -- how far off our line an enemy the shooter saw get hit may have moved
local FIRE_JITTER = 0.15
local RELOAD_GRACE = 0.25
local COIN_FLIGHT = 0.5
local COIN_RISE = 8 -- studs the coin flips up before it is shot
local COIN_FORWARD = 13 -- and how far ahead of him it goes
local COIN_HIT_RADIUS = 2.8       -- how close (top-down) a bullet must pass
local SPLIT_BASE = 5
local EXTRA_SPREAD = 7 -- degrees between Projectile Count bullets
local SPLIT_RADIUS = 30
local EXPLOSION_RADIUS = 7
local EXPLOSION_SHARE = 0.45      -- × ricochet damage, per Explosive Ricochet
local MARK_TIME = 6
local COLLECTOR_REFUND = 1.5

local FAN_INTERVAL = 0.075
local FAN_SPREAD = 9              -- degrees either side

local ROLL_IFRAMES = 0.42
local ROLL_SHOT_WINDOW = 0.8
local FLASH_FUSE = 0.45   -- seconds from the drop to the bang
local FLASH_RADIUS = 9    -- studs (× Size)
local FLASH_STUN = 1.8    -- seconds stunned (bosses aren't)
local FLASH_TRAIL = 10    -- extra flashbangs spread this far along the roll

local NOON_MAX_TIME = 20 -- safety cap on the volley (seconds)
local NOON_RELOAD_MULT = 0.35 -- reloads during High Noon take 35% as long
local NOON_WINDUP = 1.4 -- covers the client's sunset standoff shot
local NOON_INTERVAL = 0.11 -- seconds between High Noon shots (normal fire is 0.26)
local NOON_EXEC_MULT = 4.5

-- ── State ───────────────────────────────────────────────────────────────────
type Coin = { id: number, pos: Vector3, landAt: number, expires: number, heads: boolean, damage: number, alive: boolean }
type State = {
	ammo: number,
	lastShot: number,
	reloadEnd: number?,
	deadeye: number,
	lastHitAt: number,
	coins: { Coin },
	rolledAt: number,
	rollShotUsed: boolean,
	busyUntil: number, -- fanning / High Noon: no normal shots
}

local H: any = nil -- helpers from SkillManager
local states: { [Player]: State } = {}
local nextCoinId = 0
local rng = Random.new()

local function stat(player: Player, name: string): number
	return PlayerStats.GetStat(player, name)
end

local function maxAmmo(player: Player): number
	return BASE_AMMO + 2 * math.floor(stat(player, "gs_extendedCylinder"))
end

local function reloadTime(player: Player): number
	return math.max(0.35, RELOAD_TIME * QUICK_HANDS ^ math.floor(stat(player, "gs_quickHands")))
end

local function getState(player: Player): State
	local st = states[player]
	if not st then
		st = {
			ammo = maxAmmo(player), lastShot = 0, reloadEnd = nil, deadeye = 0, lastHitAt = 0,
			coins = {}, rolledAt = -10, rollShotUsed = true, busyUntil = 0,
		}
		states[player] = st
	end
	return st
end

local function publish(player: Player, st: State)
	player:SetAttribute("GS_Ammo", st.ammo)
	player:SetAttribute("GS_MaxAmmo", maxAmmo(player))
	player:SetAttribute("GS_Deadeye", math.floor(st.deadeye))
	if st.reloadEnd then
		player:SetAttribute("GS_ReloadEnd", Workspace:GetServerTimeNow() + (st.reloadEnd - os.clock()))
		player:SetAttribute("GS_ReloadTime", reloadTime(player))
	else
		player:SetAttribute("GS_ReloadEnd", 0)
	end
end

local function fx(payload: any, exclude: Player?)
	local remote = Network.GetRemoteEvent(Network.Remotes.GunslingerFX)
	if exclude then
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= exclude then remote:FireClient(p, payload) end
		end
	else
		remote:FireAllClients(payload)
	end
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 0.01 then f.Unit else Vector3.new(0, 0, -1)
end

local function rotate(dir: Vector3, degrees: number): Vector3
	return (CFrame.Angles(0, math.rad(degrees), 0) * flat(dir)).Unit
end

-- ── Reload ──────────────────────────────────────────────────────────────────
local function startReload(player: Player, st: State)
	if st.reloadEnd then return end
	local t = reloadTime(player)
	local endsAt = os.clock() + t
	st.reloadEnd = endsAt
	publish(player, st)
	fx({ kind = "reload", attacker = player, duration = t })
	task.delay(t, function()
		if st.reloadEnd == endsAt then
			st.reloadEnd = nil
			st.ammo = maxAmmo(player)
			publish(player, st)
		end
	end)
end

-- ── Deadeye ─────────────────────────────────────────────────────────────────
local function deadeyeHit(player: Player, st: State)
	local mult = 1.5 ^ math.min(math.floor(stat(player, "gs_steadyAim")), 1)
	st.deadeye = math.min(DEADEYE_MAX, st.deadeye + DEADEYE_GAIN * mult)
	st.lastHitAt = os.clock()
end

local function deadeyeMiss(player: Player, st: State)
	if st.deadeye >= DEADEYE_MAX then return end -- a ready shot waits for a hit
	local loss = if stat(player, "gs_steadyAim") >= 1 then DEADEYE_MISS * 0.5 else DEADEYE_MISS
	st.deadeye = math.max(0, st.deadeye - loss)
end

-- ── Targets along a shot ────────────────────────────────────────────────────
-- Half the target's footprint, so a bullet that visibly clips a big mob's
-- body counts (not just one passing within `width` of its root's centre).
local function bodyRadius(t: any): number
	local size = t.character:GetExtentsSize()
	return math.min(math.max(size.X, size.Z) * 0.5, 8)
end

local function targetsOnLine(char: Model, origin: Vector3, dir: Vector3, range: number, width: number): { any }
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local reach = width + bodyRadius(t) * 0.6 + HIT_LENIENCY
		local diff = t.rootPart.Position - origin
		local along = Vector3.new(diff.X, 0, diff.Z):Dot(dir)
		if along >= 0 and along <= range then
			local closest = origin + dir * along
			local lateral = (Vector3.new(t.rootPart.Position.X, origin.Y, t.rootPart.Position.Z) - closest).Magnitude
			if lateral <= reach then
				table.insert(out, { target = t, along = along })
			end
		end
	end
	table.sort(out, function(a, b) return a.along < b.along end)
	return out
end

local function coinOnLine(st: State, origin: Vector3, dir: Vector3, range: number): (Coin?, number)
	local now = os.clock()
	local best: Coin? = nil
	local bestAlong = math.huge
	for _, coin in ipairs(st.coins) do
		if coin.alive and now >= coin.landAt - 0.08 and now <= coin.expires then
			local diff = coin.pos - origin
			local along = Vector3.new(diff.X, 0, diff.Z):Dot(dir)
			if along >= 0 and along <= range and along < bestAlong then
				local closest = origin + dir * along
				local lateral = Vector3.new(coin.pos.X - closest.X, 0, coin.pos.Z - closest.Z).Magnitude
				if lateral <= COIN_HIT_RADIUS then
					best, bestAlong = coin, along
				end
			end
		end
	end
	return best, bestAlong
end

-- ── Ricochet projectiles ────────────────────────────────────────────────────
local function isHeavyTarget(t: any): boolean
	return t.character:GetAttribute("IsBoss") == true or t.character:GetAttribute("IsElite") == true
end

local function explode(player: Player, char: Model, center: Vector3, damage: number, except: Model?)
	fx({ kind = "blast", attacker = player, pos = center, radius = EXPLOSION_RADIUS })
	for _, t in ipairs(H.getPotentialTargets(char)) do
		if t.character ~= except and (t.rootPart.Position - center).Magnitude <= EXPLOSION_RADIUS then
			H.dealDamage(player, t, damage, "RICOCHET BLAST")
		end
	end
end

-- Split `count` projectiles from `from` toward enemies near it. Extra
-- projectiles go round the nearest targets again (preferring `favour`, the
-- original target) instead of vanishing. `opts.roomAt`: every enemy in the
-- room at that spot is fair game (and gets one at least), not just those
-- near `from`.
local function splitProjectiles(player: Player, char: Model, from: Vector3, count: number, damage: number, opts: any)
	opts = opts or {}
	local bounds = if opts.roomAt and H.roomBoundsAt then H.roomBoundsAt(opts.roomAt) else nil
	local near = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local p = t.rootPart.Position
		local d = (p - from).Magnitude
		local reach = if bounds
			then p.X >= bounds.minX and p.X <= bounds.maxX and p.Z >= bounds.minZ and p.Z <= bounds.maxZ
				and math.abs(p.Y - bounds.floorY) < 14
			else d <= SPLIT_RADIUS
		if reach and t.character ~= opts.exclude then
			table.insert(near, { target = t, dist = d })
		end
	end
	if bounds then count = math.max(count, #near) end
	table.sort(near, function(a, b) return a.dist < b.dist end)
	if opts.favour then
		for i, n in ipairs(near) do
			if n.target.character == opts.favour then
				table.remove(near, i)
				table.insert(near, 1, n)
				break
			end
		end
	end

	local shots = {}
	for i = 1, count do
		if #near > 0 then
			local n = near[((i - 1) % #near) + 1]
			-- Straight, instant bullets (like the revolver's), fired in quick succession.
			local delay = (i - 1) * 0.02
			table.insert(shots, { to = n.target.rootPart.Position, model = n.target.character, delay = delay, target = n.target })
		else
			-- Nothing to seek: fan out and fizzle.
			local a = (i / count) * math.pi * 2
			table.insert(shots, { to = from + Vector3.new(math.cos(a), 0, math.sin(a)) * 14, delay = 0.1 })
		end
	end

	local payload = { kind = "split", attacker = player, from = from, shots = {} }
	for _, s in ipairs(shots) do
		table.insert(payload.shots, { to = s.to, model = s.model, delay = s.delay })
	end
	fx(payload)

	local silver = stat(player, "gs_silverDollar")
	local explosive = stat(player, "gs_explosive")
	local marked = stat(player, "gs_markedCurrency")
	local collector = stat(player, "gs_coinCollector")
	for _, s in ipairs(shots) do
		local t = s.target
		if t then
			task.delay(s.delay, function()
				if t.humanoid.Health <= 0 or not t.character.Parent then return end
				local dmg = damage
				if silver > 0 and isHeavyTarget(t) then dmg *= 1 + 0.6 * silver end
				H.dealDamage(player, t, dmg, "RICOCHET")
				if explosive > 0 then
					explode(player, char, t.rootPart.Position, dmg * EXPLOSION_SHARE * explosive, t.character)
				end
				if marked > 0 and t.humanoid.Health > 0 then
					t.character:SetAttribute("GS_MarkedBy", player.UserId)
					t.character:SetAttribute("GS_MarkUntil", os.clock() + MARK_TIME)
					fx({ kind = "mark", attacker = player, model = t.character, duration = MARK_TIME })
				end
				if collector > 0 and opts.fromCoin and t.humanoid.Health <= 0 then
					H.reduceCooldown(player, 3, COLLECTOR_REFUND * collector)
				end
			end)
		end
	end
end

local function hitCoin(player: Player, char: Model, st: State, coin: Coin)
	local count = SPLIT_BASE + 2 * math.floor(stat(player, "gs_loadedCoin"))
	local dmg = coin.damage
	if coin.heads then
		dmg *= 1 + 0.5 * stat(player, "gs_heads")
	else
		count += 3 * math.floor(stat(player, "gs_tails"))
	end
	if stat(player, "gs_doubleCoin") >= 1 then count -= 2 end
	count = math.max(2, count)

	local lucky = math.min(0.3 * stat(player, "gs_luckyCoin"), 0.9)
	local survives = rng:NextNumber() < lucky
	coin.alive = survives
	fx({ kind = "coinHit", attacker = player, id = coin.id, pos = coin.pos, survives = survives })
	-- (the room you're standing in: the coin itself is up in the air)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	splitProjectiles(player, char, coin.pos, count, dmg, { fromCoin = true, roomAt = if root then root.Position else coin.pos })
end

-- ── A single bullet ─────────────────────────────────────────────────────────
-- Resolves one shot from `origin` along `dir`: a coin in the way splits it,
-- otherwise it hits the first enemy (more with Piercing Rounds / Deadeye).
local function fireBullet(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, o: any)
	local damage = o.damage
	local range = o.range or BULLET_RANGE
	local width = o.width or BULLET_WIDTH
	local deadeye = st.deadeye >= DEADEYE_MAX
	local hits = targetsOnLine(char, origin, dir, range, width)
	-- Lag allowance: the shooter's screen shows mobs (and their own body) a
	-- moment behind ours, so an enemy their bullet visibly struck may have
	-- stepped off our line since. If it's still close to the line, it's hit.
	local claim = o.claim
	if typeof(claim) == "Instance" and claim:IsA("Model") then
		local listed = false
		for _, h in ipairs(hits) do
			if h.target.character == claim then listed = true break end
		end
		if not listed then
			for _, t in ipairs(H.getPotentialTargets(char)) do
				if t.character == claim then
					local diff = t.rootPart.Position - origin
					local along = Vector3.new(diff.X, 0, diff.Z):Dot(dir)
					local closest = origin + dir * along
					local lateral = Vector3.new(t.rootPart.Position.X - closest.X, 0, t.rootPart.Position.Z - closest.Z).Magnitude
					if along >= -2 and along <= range + 4 and lateral <= width + bodyRadius(t) * 0.6 + CLAIM_SLACK then
						table.insert(hits, { target = t, along = math.max(along, 0) })
						table.sort(hits, function(a, b) return a.along < b.along end)
					end
					break
				end
			end
		end
	end

	local coin, coinAlong = coinOnLine(st, origin, dir, range)
	if coin and (#hits == 0 or coinAlong < hits[1].along) then
		deadeyeHit(player, st)
		fx({ kind = "shot", attacker = player, from = origin, to = coin.pos, final = o.final, deadeye = false, hit = true }, o.exclude)
		hitCoin(player, char, st, coin)
		return
	end

	local pierce = if deadeye then math.huge else math.floor(stat(player, "gs_pierce"))
	local source = if deadeye then "DEADEYE SHOT" elseif o.final then "FINAL SHOT" else o.source
	local mult = (if o.final then FINAL_SHOT_MULT else 1) * (if deadeye then DEADEYE_MULT else 1)
	local endPoint = origin + dir * range
	local hitCount = 0
	for i, h in ipairs(hits) do
		if i > 1 + pierce then break end
		local t = h.target
		if hitCount == 0 then endPoint = t.rootPart.Position end
		hitCount += 1
		local dealt = H.dealDamage(player, t, damage * mult, source, { forceCrit = deadeye })
		-- Marked Currency: shooting a marked enemy refunds a bullet.
		if (t.character:GetAttribute("GS_MarkedBy") == player.UserId)
			and (t.character:GetAttribute("GS_MarkUntil") or 0) > os.clock() then
			t.character:SetAttribute("GS_MarkUntil", 0)
			st.ammo = math.min(maxAmmo(player), st.ammo + 1)
			fx({ kind = "refund", attacker = player, pos = t.rootPart.Position })
		end
		if i == 1 then
			-- Last Word: the final bullet splits into ricochets on hit.
			local lastWord = math.floor(stat(player, "gs_lastWord"))
			if o.final and lastWord > 0 and dealt then
				splitProjectiles(player, char, t.rootPart.Position, 2 * lastWord, damage * 0.6, { exclude = t.character })
			end
			H.ricochet(player, char, t, damage * mult, source) -- the Ricochet Tome
		end
	end
	if deadeye and hitCount > 0 then
		endPoint = origin + dir * range -- a Deadeye shot tears through the line
	end

	if hitCount > 0 then
		if deadeye then
			st.deadeye = 0
			st.lastHitAt = os.clock()
		else
			deadeyeHit(player, st)
		end
	else
		deadeyeMiss(player, st)
	end
	fx({ kind = "shot", attacker = player, from = origin, to = endPoint, final = o.final, deadeye = deadeye and hitCount > 0,
		hit = hitCount > 0 }, o.exclude)
end

-- ── Public: basic attack (click) and the roll's landing shot ───────────────
function GunslingerServer.OnShoot(player: Player, char: Model, root: BasePart, payload: any)
	local st = getState(player)
	local now = os.clock()
	if now < st.busyUntil then return end
	if st.reloadEnd then
		-- The client's reload bar can finish a few frames before ours.
		if now < st.reloadEnd - RELOAD_GRACE then return end
		st.reloadEnd = nil
		st.ammo = maxAmmo(player)
	end
	if st.ammo <= 0 then
		startReload(player, st)
		return
	end

	local rollShot = typeof(payload) == "table" and payload.rollShot == true
		and not st.rollShotUsed and now - st.rolledAt <= ROLL_SHOT_WINDOW
	if rollShot then
		st.rollShotUsed = true
		st.lastShot = now
	else
		-- Packets bunch up in transit, so judge the pace, not each gap: a shot
		-- may arrive early as long as the average rate stays at the cap.
		local interval = FIRE_INTERVAL / math.max(stat(player, "basicAttackSpeed"), 0.1)
		local due = st.lastShot + interval
		if now < due - FIRE_JITTER then return end
		st.lastShot = math.max(now - FIRE_JITTER, due)
	end

	local dir = flat(if typeof(payload) == "table" and typeof(payload.direction) == "Vector3" then payload.direction else root.CFrame.LookVector)
	st.ammo -= 1
	local final = st.ammo == 0
	local shot = {
		damage = BULLET_DAMAGE * stat(player, "damage"),
		width = BULLET_WIDTH * stat(player, "size"),
		source = "SIX SHOOTER",
		final = final,
		exclude = player, -- the shooter already drew this shot locally
		claim = if typeof(payload) == "table" then payload.target else nil,
	}
	local origin = root.Position + Vector3.new(0, 1.4, 0)
	fireBullet(player, char, st, origin, dir, shot)
	-- Projectile Count: extra bullets fanned either side of the aim (same round).
	local extra = math.max(0, math.floor(stat(player, "projectileCount")))
	for k = 1, extra do
		local side = if k % 2 == 1 then 1 else -1
		local o = table.clone(shot)
		o.exclude = nil -- the shooter only predicted the centre bullet
		o.claim = nil
		fireBullet(player, char, st, origin, rotate(dir, side * EXTRA_SPREAD * math.ceil(k / 2)), o)
	end
	publish(player, st)
	if st.ammo <= 0 then startReload(player, st) end
end

-- ── Public: skills ──────────────────────────────────────────────────────────
function GunslingerServer.CanUseSkill(player: Player, skillIndex: number): boolean
	local st = getState(player)
	if os.clock() < st.busyUntil then return false end
	if skillIndex == 1 then
		return st.ammo > 0 and st.reloadEnd == nil
	end
	return true
end

-- Flips the coin straight up over the Gunslinger; at the top of its rise the
-- Gunslinger snaps a shot into it automatically (no ammo), splitting it.
local function throwCoins(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, _targetPosition: any, config: any)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	-- One coin, +1 per Projectile Count, +1 for the Double Coin tome; they
	-- fan out side by side and he shoots them all within about a second.
	local extra = math.max(0, math.floor(config.projectileCount or 0))
	local count = 1 + extra + (if stat(player, "gs_doubleCoin") >= 1 then 1 else 0)
	local sides = {}
	for k = 1, count do sides[k] = (k - (count + 1) / 2) * 2.4 end
	local gap = math.min(0.15, 0.9 / count)
	local right = dir:Cross(Vector3.yAxis).Unit
	local showFace = stat(player, "gs_heads") > 0 or stat(player, "gs_tails") > 0

	for n, side in ipairs(sides) do
		-- Tossed from the off hand, rising just in front of his head. It rides
		-- along with him while it rises (he may be walking).
		local function apexFrom(pos: Vector3): Vector3
			return pos + dir * COIN_FORWARD + right * side + Vector3.new(0, COIN_RISE, 0)
		end
		local start = if root then root.Position else origin
		local base = start + dir * 0.9 - right * 0.9
		local apex = apexFrom(start)
		nextCoinId += 1
		local now = os.clock()
		local coin: Coin = {
			id = nextCoinId, pos = apex, landAt = now + COIN_FLIGHT, expires = now + COIN_FLIGHT + (config.duration or 2.6),
			heads = rng:NextNumber() < 0.5, damage = config.damage, alive = true,
		}
		table.insert(st.coins, coin)
		fx({ kind = "coin", attacker = player, id = coin.id, from = base + Vector3.new(0, 0.3, 0), to = apex,
			flight = COIN_FLIGHT, hang = config.duration or 2.6, heads = coin.heads, showFace = showFace, up = true })
		-- The quick-draw: shoot it at the apex (a second coin a beat later).
		task.delay(COIN_FLIGHT + (n - 1) * gap, function()
			if not coin.alive or not char.Parent then return end
			if root then coin.pos = apexFrom(root.Position) end -- it followed him up
			local from = if root then root.Position + Vector3.new(0, 1.4, 0) else origin
			fx({ kind = "shot", attacker = player, from = from, to = coin.pos, final = false, deadeye = false, hit = true })
			hitCoin(player, char, st, coin)
		end)
		task.delay(coin.expires - now, function()
			local k = table.find(st.coins, coin)
			if k then table.remove(st.coins, k) end
			if coin.alive then
				coin.alive = false
				fx({ kind = "coinGone", attacker = player, id = coin.id })
			end
		end)
	end
end

local function fanTheHammer(player: Player, char: Model, st: State, dir: Vector3, config: any)
	local count = st.ammo
	st.busyUntil = os.clock() + count * FAN_INTERVAL + 0.1
	for i = 1, count do
		task.delay((i - 1) * FAN_INTERVAL, function()
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root or st.ammo <= 0 then return end
			st.ammo -= 1
			local final = st.ammo == 0
			local aim = rotate(dir, rng:NextNumber(-FAN_SPREAD, FAN_SPREAD))
			local o = {
				damage = config.damage,
				range = config.range or 34,
				width = BULLET_WIDTH * (config.areaMultiplier or 1),
				source = "FAN THE HAMMER",
				final = final,
			}
			local origin = root.Position + Vector3.new(0, 1.4, 0)
			fireBullet(player, char, st, origin, aim, o)
			-- Projectile Count: extra bullets per hammer strike.
			for k = 1, math.max(0, math.floor(config.projectileCount or 0)) do
				local side = if k % 2 == 1 then 1 else -1
				fireBullet(player, char, st, origin, rotate(aim, side * EXTRA_SPREAD * math.ceil(k / 2)), o)
			end
			publish(player, st)
			if st.ammo <= 0 then startReload(player, st) end
		end)
	end
end

-- Flashbangs dropped where the roll starts (extras strewn along the roll):
-- after the fuse each one bangs, stunning every enemy near it but bosses.
local function flashbangs(player: Player, char: Model, origin: Vector3, dir: Vector3, config: any)
	local n = 1 + math.max(0, math.floor(config.projectileCount or 0))
	local radius = FLASH_RADIUS * (config.areaMultiplier or 1)
	local side = Vector3.new(-dir.Z, 0, dir.X)
	local spots = {}
	for k = 1, n do
		local along = if n == 1 then 0 else (k - 1) / (n - 1) * FLASH_TRAIL
		local off = if k == 1 then 0 elseif k % 2 == 0 then 2.5 else -2.5
		table.insert(spots, origin + dir * along + side * off)
	end
	fx({ kind = "flashDrop", attacker = player, spots = spots, fuse = FLASH_FUSE })
	task.delay(FLASH_FUSE, function()
		local stunned = {}
		local seen: { [Model]: boolean } = {}
		local untilT = os.clock() + FLASH_STUN
		for _, at in ipairs(spots) do
			for _, t in ipairs(H.getPotentialTargets(char)) do
				local m = t.character
				if not seen[m] and t.humanoid.Health > 0 and m:GetAttribute("IsBoss") ~= true
					and (t.rootPart.Position - at).Magnitude <= radius then
					seen[m] = true
					m:SetAttribute("StaggerUntil", math.max(tonumber(m:GetAttribute("StaggerUntil")) or 0, untilT))
					m:SetAttribute("StunnedUntil", untilT)
					table.insert(stunned, m)
				end
			end
		end
		fx({ kind = "flashBang", attacker = player, spots = spots, radius = radius, stunned = stunned, stun = FLASH_STUN })
	end)
end

local function roll(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, config: any)
	local now = os.clock()
	st.rolledAt = now
	st.rollShotUsed = false
	char:SetAttribute("InvulnerableUntil", now + ROLL_IFRAMES)
	-- Every roll reloads the cylinder instantly.
	st.reloadEnd = nil
	st.ammo = maxAmmo(player)
	publish(player, st)
	fx({ kind = "roll", attacker = player, from = origin, dir = dir }, player)
	flashbangs(player, char, origin, dir, config)
end

-- High Noon: after the standoff, the Gunslinger auto-fires one bullet into
-- each enemy in the room (nearest first, including ones that walk in), and
-- stops once every one of them has been shot once.
-- A faster fire rate and quick reloads; the last round of every cylinder is
-- a crit "execution" shot. Mobs are frozen only for the standoff cutscene.
-- Who High Noon reaches from `at`: every enemy in the room there, or (out
-- of a room) everyone within `range`.
local function noonReach(char: Model, at: Vector3, range: number): { any }
	local bounds = if H.roomBoundsAt then H.roomBoundsAt(at) else nil
	local out = {}
	for _, t in ipairs(H.getPotentialTargets(char)) do
		local p = t.rootPart.Position
		local ok = if bounds
			then p.X >= bounds.minX and p.X <= bounds.maxX and p.Z >= bounds.minZ and p.Z <= bounds.maxZ
				and math.abs(p.Y - bounds.floorY) < 14
			else (p - at).Magnitude <= range
		if ok and t.humanoid.Health > 0 then table.insert(out, t) end
	end
	return out
end

local function highNoon(player: Player, char: Model, st: State, origin: Vector3, dir: Vector3, config: any)
	local range = (config.range or 50) * (config.areaMultiplier or 1)
	st.busyUntil = math.huge
	-- Everyone in the room gets marked during the standoff.
	local marks = {}
	for _, t in ipairs(noonReach(char, origin, range)) do
		table.insert(marks, t.character)
	end
	fx({ kind = "highNoon", attacker = player, origin = origin, dir = dir, windup = NOON_WINDUP, marks = marks })

	task.spawn(function()
		task.wait(NOON_WINDUP)
		local started = os.clock()
		local ammo = maxAmmo(player)
		local interval = NOON_INTERVAL / math.max(stat(player, "basicAttackSpeed"), 0.1)
		local shot: { [Model]: boolean } = {} -- one bullet per enemy, hit or survive
		while char.Parent and os.clock() - started < NOON_MAX_TIME do
			local hum = char:FindFirstChildOfClass("Humanoid")
			local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not hum or hum.Health <= 0 or not root then break end
			-- Nearest enemies in the room: one per shot, +1 per Projectile Count.
			local near = {}
			for _, t in ipairs(noonReach(char, root.Position, range)) do
				if not shot[t.character] then
					table.insert(near, { target = t, dist = (t.rootPart.Position - root.Position).Magnitude })
				end
			end
			if #near == 0 then break end
			table.sort(near, function(a, b) return a.dist < b.dist end)
			local best = near[1].target

			ammo -= 1
			local final = ammo == 0
			local volley = math.min(#near, 1 + math.max(0, math.floor(config.projectileCount or 0)))
			for k = 1, volley do
				local t = near[k].target
				shot[t.character] = true
				local dmg = config.damage * (if final then NOON_EXEC_MULT else 1)
				H.dealDamage(player, t, dmg, if final then "HIGH NOON EXECUTION" else "HIGH NOON", { forceCrit = final })
				fx({ kind = "noonShot", attacker = player, model = t.character,
					from = root.Position + Vector3.new(0, 1.4, 0), to = t.rootPart.Position, final = final })
			end
			if final then
				-- The execution round tears on through anything behind it.
				local line = flat(best.rootPart.Position - root.Position)
				for _, h in ipairs(targetsOnLine(char, root.Position, line, BULLET_RANGE, BULLET_WIDTH * 1.4)) do
					if h.target.character ~= best.character then
						H.dealDamage(player, h.target, config.damage * 1.5, "HIGH NOON")
					end
				end
				local t = reloadTime(player) * NOON_RELOAD_MULT
				fx({ kind = "reload", attacker = player, duration = t })
				task.wait(t)
				ammo = maxAmmo(player)
			else
				task.wait(interval)
			end
		end
		st.busyUntil = os.clock() + 0.2
		st.reloadEnd = nil
		st.ammo = maxAmmo(player)
		publish(player, st)
		fx({ kind = "noonEnd", attacker = player })
	end)
end

-- The server refused a cast the client already started playing (cooldown /
-- busy). For High Noon the client has locked itself up waiting for noonEnd;
-- release it.
function GunslingerServer.Refused(player: Player, skillIndex: number)
	if skillIndex == 4 then
		Network.GetRemoteEvent(Network.Remotes.GunslingerFX):FireClient(player, { kind = "noonEnd", attacker = player })
	end
end

function GunslingerServer.OnSkill(player: Player, char: Model, skillIndex: number, origin: Vector3, dir: Vector3, targetPosition: any, config: any)
	local st = getState(player)
	dir = flat(dir)
	if skillIndex == 1 then
		fanTheHammer(player, char, st, dir, config)
	elseif skillIndex == 2 then
		roll(player, char, st, origin, dir, config)
	elseif skillIndex == 3 then
		throwCoins(player, char, st, origin, dir, targetPosition, config)
	elseif skillIndex == 4 then
		highNoon(player, char, st, origin, dir, config)
	end
end

-- Fresh cylinder, empty meter, no coins (new character / class / run).
function GunslingerServer.Reset(player: Player)
	local st = getState(player)
	st.ammo = maxAmmo(player)
	st.reloadEnd = nil
	st.deadeye = 0
	st.coins = {}
	st.busyUntil = 0
	publish(player, st)
end

function GunslingerServer.Init(helpers: any)
	H = helpers
	-- Deadeye drains after a few seconds without a hit.
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		acc += dt
		if acc < 0.1 then return end
		local step = acc
		acc = 0
		local now = os.clock()
		for player, st in pairs(states) do
			if st.deadeye > 0 and st.deadeye < DEADEYE_MAX and now - st.lastHitAt > DEADEYE_DECAY_AFTER then
				local before = math.floor(st.deadeye)
				st.deadeye = math.max(0, st.deadeye - DEADEYE_DECAY_RATE * step)
				if math.floor(st.deadeye) ~= before then
					player:SetAttribute("GS_Deadeye", math.floor(st.deadeye))
				end
			end
		end
	end)

	local function watch(player: Player)
		player.CharacterAdded:Connect(function()
			if player:GetAttribute("SelectedClass") == "gunslinger" then GunslingerServer.Reset(player) end
		end)
		player:GetAttributeChangedSignal("SelectedClass"):Connect(function()
			if player:GetAttribute("SelectedClass") == "gunslinger" then GunslingerServer.Reset(player) end
		end)
		-- Extended Cylinder: the new chambers arrive loaded.
		player:GetAttributeChangedSignal("Stat_gs_extendedCylinder"):Connect(function()
			local st = states[player]
			if st then
				st.ammo = math.min(maxAmmo(player), st.ammo + 2)
				publish(player, st)
			end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(player) states[player] = nil end)
end

return GunslingerServer
