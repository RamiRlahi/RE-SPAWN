--[[
	SpecialRooms.luau
	Builds and runs the dungeon's non-combat rooms:

	  Rest     — Moonwell: tiered fountain with a finite healing pool (water level
	             drops as it heals) and a coin-offering blessing.
	  Treasure — Vault: ornate chest on a dais; always gold, usually a tome,
	             sometimes a curse.
	  Shop     — Wandering Merchant: three tome wares, a restorative potion and a
	             reroll bell, priced by floor tier.
	  Gamble   — Gambling Den: the Wheel of Fate (bet 25/50/100) and the
	             Double-or-Nothing altar.

	The server owns all state and rewards. Smooth motion (wheel spin, floating
	wares, ripples, pop-up text, coin bursts) is done by the client's RoomFX
	module, driven by attributes and the RoomEvent remote.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local TomeData = require(Shared:WaitForChild("TomeData"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local SpecialRooms = {}

export type Room = {
	id: number,
	roomType: string,
	tier: number,
	floorY: number,
	centerWorld: Vector3,
	w: number,
	d: number,
}

-- ─── Palette ────────────────────────────────────────────────────────────────
local GOLD = Color3.fromRGB(235, 185, 70)
local GOLD_BRIGHT = Color3.fromRGB(255, 220, 110)
local STONE = Color3.fromRGB(78, 80, 90)
local STONE_DARK = Color3.fromRGB(52, 54, 62)
local MARBLE = Color3.fromRGB(190, 192, 200)
local WOOD = Color3.fromRGB(86, 52, 30)
local WOOD_DARK = Color3.fromRGB(58, 34, 20)
local MOON = Color3.fromRGB(120, 220, 255)
local VELVET = Color3.fromRGB(90, 16, 32)
local CRIMSON = Color3.fromRGB(200, 40, 60)
local ROYAL = Color3.fromRGB(110, 60, 190)
local GOOD = Color3.fromRGB(120, 255, 150)
local BAD = Color3.fromRGB(255, 90, 90)

-- ─── Helpers ────────────────────────────────────────────────────────────────
local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function cyl(parent: Instance, name: string, pos: Vector3, height: number, diameter: number, color: Color3, material: Enum.Material, extra: { [string]: any }?): BasePart
	local props = {
		Name = name,
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height, diameter, diameter),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Material = material,
	}
	if extra then
		for k, v in pairs(extra) do props[k] = v end
	end
	return part(parent, props)
end

local function pointLight(parent: Instance, color: Color3, brightness: number, range: number): PointLight
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range = color, brightness, range
	l.Parent = parent
	return l
end

local function fire(parent: BasePart, color: Color3, secondary: Color3, size: number)
	local f = Instance.new("Fire")
	f.Color, f.SecondaryColor, f.Size, f.Heat = color, secondary, size, 6
	f.Parent = parent
end

local function sparkles(parent: Instance, color: Color3, rate: number, speed: number, lifetime: number): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(lifetime * 0.6, lifetime)
	pe.Speed = NumberRange.new(speed * 0.5, speed)
	pe.SpreadAngle = Vector2.new(30, 30)
	pe.Rate = rate
	pe.Parent = parent
	return pe
end

-- Title + status billboard above an object.
local function billboard(parent: Instance, adornee: BasePart, title: string, color: Color3, offsetY: number): (TextLabel, TextLabel)
	local gui = Instance.new("BillboardGui")
	gui.Name = "RoomLabel"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(260, 64)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 80
	gui.LightInfluence = 0
	gui.Parent = parent
	local t = Instance.new("TextLabel")
	t.Size = UDim2.new(1, 0, 0.55, 0)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Antique
	t.TextScaled = true
	t.TextColor3 = color
	t.TextStrokeTransparency = 0.3
	t.Text = title
	t.Parent = gui
	local s = Instance.new("TextLabel")
	s.Size = UDim2.new(1, 0, 0.42, 0)
	s.Position = UDim2.new(0, 0, 0.58, 0)
	s.BackgroundTransparency = 1
	s.Font = Enum.Font.GothamMedium
	s.TextScaled = true
	s.TextColor3 = Color3.fromRGB(235, 230, 220)
	s.TextStrokeTransparency = 0.4
	s.Text = ""
	s.Parent = gui
	return t, s
end

local function prompt(parent: Instance, action: string, object: string, hold: number?): ProximityPrompt
	local p = Instance.new("ProximityPrompt")
	p.ActionText = action
	p.ObjectText = object
	p.HoldDuration = hold or 0.3
	p.MaxActivationDistance = 11
	p.RequiresLineOfSight = false
	p.Style = Enum.ProximityPromptStyle.Default
	-- Only the nearest prompt shows, so neighbouring ones never stack.
	p.Exclusivity = Enum.ProximityPromptExclusivity.OneGlobally
	p.Parent = parent
	return p
end

local function roomEvent(payload: any)
	Network.GetRemoteEvent(Network.Remotes.RoomEvent):FireAllClients(payload)
end

local function pop(position: Vector3, text: string, color: Color3)
	roomEvent({ kind = "Pop", position = position, text = text, color = color })
end

local function coins(position: Vector3, count: number)
	roomEvent({ kind = "Coins", position = position, count = count })
end

local function burst(position: Vector3, color: Color3, size: number?)
	roomEvent({ kind = "Burst", position = position, color = color, size = size or 1 })
end

local function playerHumanoid(player: Player): (Humanoid?, BasePart?)
	local c = player.Character
	local h = c and c:FindFirstChildOfClass("Humanoid")
	local r = c and c:FindFirstChild("HumanoidRootPart") :: BasePart?
	if h and h.Health > 0 then return h, r end
	return nil, nil
end

-- A floating tome book (cover, pages, spine glow) the client bobs and spins.
-- ── Luck (Luck Tomes, +7% each) ───────────────────────────────────────────────
-- Luck tilts every gamble in the player's favour and raises chest loot ranks.
local function luckOf(player: Player): number
	return math.clamp(PlayerStats.GetStat(player, "luck"), 0, 1)
end

-- Vault chest loot ranks. Luck multiplies the weight of the higher ranks.
local CHEST_RANKS = {
	{ name = "COMMON", weight = 55, luckScale = 0, gold = 1, tomes = 1, color = Color3.fromRGB(230, 225, 210) },
	{ name = "RARE", weight = 30, luckScale = 4, gold = 1.5, tomes = 1, color = Color3.fromRGB(90, 170, 255) },
	{ name = "EPIC", weight = 12, luckScale = 8, gold = 2, tomes = 2, color = Color3.fromRGB(190, 95, 255) },
	{ name = "LEGENDARY", weight = 3, luckScale = 12, gold = 3, tomes = 3, color = Color3.fromRGB(255, 200, 70) },
}
local function rollChestRank(rng: Random, luck: number)
	local total = 0
	for _, r in ipairs(CHEST_RANKS) do total += r.weight * (1 + luck * r.luckScale) end
	local x = rng:NextNumber() * total
	for _, r in ipairs(CHEST_RANKS) do
		x -= r.weight * (1 + luck * r.luckScale)
		if x <= 0 then return r end
	end
	return CHEST_RANKS[1]
end

local function buildBook(parent: Instance, pos: Vector3, color: Color3): BasePart
	local hub = part(parent, { Name = "FloatItem", Size = Vector3.new(2.2, 0.55, 1.7), CFrame = CFrame.new(pos), Color = color, Material = Enum.Material.Fabric, CanCollide = false })
	hub:SetAttribute("Float", true)
	local pages = part(parent, { Name = "Pages", Size = Vector3.new(2.05, 0.4, 1.6), CFrame = hub.CFrame * CFrame.new(0.06, 0, 0), Color = Color3.fromRGB(240, 228, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false, Anchored = false, Massless = true })
	local clasp = part(parent, { Name = "Clasp", Size = Vector3.new(0.25, 0.6, 0.5), CFrame = hub.CFrame * CFrame.new(1.1, 0, 0), Color = GOLD, Material = Enum.Material.Metal, CanCollide = false, Anchored = false, Massless = true })
	for _, p in ipairs({ pages, clasp }) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = hub, p
		w.Parent = p
	end
	pointLight(hub, color, 1.5, 9)
	sparkles(hub, color, 6, 1.5, 1.2)
	return hub
end

local function pedestal(parent: Instance, pos: Vector3, trim: Color3): BasePart
	cyl(parent, "PedestalBase", pos + Vector3.new(0, 0.4, 0), 0.8, 3.2, STONE_DARK, Enum.Material.Slate)
	cyl(parent, "PedestalColumn", pos + Vector3.new(0, 2, 0), 2.6, 1.9, MARBLE, Enum.Material.Marble)
	local top = cyl(parent, "PedestalTop", pos + Vector3.new(0, 3.4, 0), 0.35, 2.8, trim, Enum.Material.Metal)
	return top
end

-- ═════════════════════════════════════════════════════════════════════════════
-- REST — the Moonwell
-- ═════════════════════════════════════════════════════════════════════════════
local REST_RADIUS = 17
local REST_TICK = 0.5
local REST_HEAL_PER_TICK = 6
local OFFERING_COST = 15

local function buildRest(room: Room, folder: Folder, rng: Random)
	local model = Instance.new("Model")
	model.Name = `Moonwell_{room.id}`
	model.Parent = folder
	local c = Vector3.new(room.centerWorld.X, room.floorY, room.centerWorld.Z)

	-- Dais + basin wall of stone blocks.
	cyl(model, "Dais", c + Vector3.new(0, 0.3, 0), 0.6, 20, STONE_DARK, Enum.Material.Slate)
	cyl(model, "DaisTrim", c + Vector3.new(0, 0.62, 0), 0.06, 20.4, MOON, Enum.Material.Neon, { Transparency = 0.5, CanCollide = false })
	for i = 1, 18 do
		local a = (i / 18) * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * 7.4, 1.35, math.sin(a) * 7.4)
		part(model, { Name = "BasinStone", Size = Vector3.new(1.3, 1.5, 2.8), CFrame = CFrame.lookAt(p, c + Vector3.new(0, 1.35, 0)), Color = STONE, Material = Enum.Material.Cobblestone })
	end
	-- Water: its height is the remaining healing pool.
	local WATER_TOP = 1.75
	local water = cyl(model, "FountainWater", c + Vector3.new(0, WATER_TOP, 0), 0.3, 13.6, MOON, Enum.Material.Glass, { Transparency = 0.25, CanCollide = false, Reflectance = 0.2 })
	water:SetAttribute("RoomFX", "Water")
	local glow = cyl(model, "WaterGlow", c + Vector3.new(0, WATER_TOP - 0.1, 0), 0.1, 13.4, MOON, Enum.Material.Neon, { Transparency = 0.55, CanCollide = false })

	-- Three-tier centrepiece crowned by a moonstone.
	cyl(model, "Column", c + Vector3.new(0, 3, 0), 5, 2.2, MARBLE, Enum.Material.Marble)
	cyl(model, "LowerBowl", c + Vector3.new(0, 4.3, 0), 0.7, 6.5, MARBLE, Enum.Material.Marble)
	cyl(model, "LowerBowlWater", c + Vector3.new(0, 4.68, 0), 0.08, 5.6, MOON, Enum.Material.Neon, { Transparency = 0.35, CanCollide = false })
	cyl(model, "UpperColumn", c + Vector3.new(0, 6.2, 0), 3, 1.4, MARBLE, Enum.Material.Marble)
	cyl(model, "UpperBowl", c + Vector3.new(0, 7.8, 0), 0.5, 3.6, MARBLE, Enum.Material.Marble)
	local orb = part(model, { Name = "Moonstone", Shape = Enum.PartType.Ball, Size = Vector3.new(2, 2, 2), CFrame = CFrame.new(c + Vector3.new(0, 9.2, 0)), Color = MOON, Material = Enum.Material.Neon, CanCollide = false })
	orb:SetAttribute("Float", true)
	local orbLight = pointLight(orb, MOON, 3, 30)
	-- Falling water streams from the bowls.
	local streams = sparkles(orb, MOON, 30, 4, 1.4)
	streams.SpreadAngle = Vector2.new(180, 20)
	streams.Acceleration = Vector3.new(0, -14, 0)
	local mist = Instance.new("ParticleEmitter")
	mist.Texture = "rbxasset://textures/particles/smoke_main.dds"
	mist.Color = ColorSequence.new(Color3.fromRGB(200, 240, 255))
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) })
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	mist.Lifetime = NumberRange.new(2, 3)
	mist.Speed = NumberRange.new(0.5, 1.5)
	mist.Rate = 4
	mist.Parent = water

	-- Four moonfire lamps and the healing radius ring.
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2 + math.pi / 4
		local p = c + Vector3.new(math.cos(a), 0, math.sin(a)) * 13
		cyl(model, "LampBase", p + Vector3.new(0, 0.3, 0), 0.6, 2, STONE_DARK, Enum.Material.Slate)
		cyl(model, "LampPost", p + Vector3.new(0, 3, 0), 5, 0.6, STONE, Enum.Material.Slate)
		local bowl = cyl(model, "LampBowl", p + Vector3.new(0, 5.7, 0), 0.5, 1.6, GOLD, Enum.Material.Metal)
		fire(bowl, MOON, Color3.fromRGB(40, 90, 255), 3)
		pointLight(bowl, MOON, 1.5, 16)
	end
	local ringSegs = {}
	for i = 1, 40 do
		local a = (i / 40) * math.pi * 2
		local p = c + Vector3.new(math.cos(a) * REST_RADIUS, 0.08, math.sin(a) * REST_RADIUS)
		ringSegs[i] = part(model, { Name = "HealRing", Size = Vector3.new(0.35, 0.06, 2.8), CFrame = CFrame.lookAt(p, p + Vector3.new(-math.sin(a), 0, math.cos(a))), Color = MOON, Material = Enum.Material.Neon, Transparency = 0.45, CanCollide = false })
	end

	local maxPool = 140 + room.tier * 40
	local pool = maxPool
	local title, status = billboard(model, orb, "THE MOONWELL", Color3.fromRGB(170, 235, 255), 3.5)
	local function refreshStatus()
		status.Text = pool > 0 and `Stand in the light to heal · {math.floor(pool)} left` or "The well has run dry"
	end
	refreshStatus()

	local function setLevel()
		local k = pool / maxPool
		local y = c.Y + 0.9 + (WATER_TOP - 0.9) * k
		water.CFrame = CFrame.new(c.X, y, c.Z) * CFrame.Angles(0, 0, math.rad(90))
		glow.CFrame = water.CFrame * CFrame.new(-0.1, 0, 0)
		glow.Transparency = 0.55 + 0.45 * (1 - k)
		orbLight.Brightness = 0.5 + 2.5 * k
		streams.Rate = 30 * k
		for _, s in ipairs(ringSegs) do s.Transparency = 0.45 + 0.55 * (1 - k) end
		if pool <= 0 then
			orb.Color = Color3.fromRGB(90, 110, 130)
			title.TextColor3 = Color3.fromRGB(140, 150, 160)
		end
	end

	-- Offering: toss a coin into the well for a chance at a blessing.
	local offer = prompt(orb, `Offer a coin ({OFFERING_COST} Gold)`, "The Moonwell", 0.5)
	offer.MaxActivationDistance = 14
	local offered: { [Player]: boolean } = {}
	offer.Triggered:Connect(function(player)
		if offered[player] then
			pop(orb.Position, "The well has already answered you", Color3.fromRGB(180, 200, 220))
			return
		end
		if not PlayerStats.SpendGold(player, OFFERING_COST) then
			pop(orb.Position, `Needs {OFFERING_COST} Gold`, BAD)
			return
		end
		offered[player] = true
		coins(orb.Position + Vector3.new(0, 1, 0), 3)
		task.wait(0.6)
		local hum = playerHumanoid(player)
		-- Luck shrinks the roll toward the best outcome (a tome).
		local roll = rng:NextNumber() * (1 - math.min(luckOf(player) * 2, 0.6))
		if roll < 0.3 then
			local tome = PlayerStats.GrantTome(player)
			burst(orb.Position, MOON, 1.6)
			pop(orb.Position, tome and `BLESSED — {tome.name}` or "BLESSED", GOOD)
		elseif roll < 0.8 then
			if hum then hum.Health = hum.MaxHealth end
			pool = math.min(maxPool, pool + maxPool * 0.35)
			setLevel()
			refreshStatus()
			burst(water.Position, MOON, 1.2)
			pop(orb.Position, "The waters rise — fully healed", Color3.fromRGB(170, 235, 255))
		else
			pop(orb.Position, "The coin sinks without a sound…", Color3.fromRGB(160, 170, 185))
		end
	end)

	task.spawn(function()
		while model.Parent do
			task.wait(REST_TICK)
			if pool <= 0 then continue end
			local healedAny = false
			for _, player in ipairs(Players:GetPlayers()) do
				if player:GetAttribute("InLobby") ~= true then
					local hum, root = playerHumanoid(player)
					if hum and root and hum.Health < hum.MaxHealth then
						local flat = Vector3.new(root.Position.X - c.X, 0, root.Position.Z - c.Z)
						if flat.Magnitude <= REST_RADIUS and math.abs(root.Position.Y - c.Y) < 12 then
							local amount = math.min(REST_HEAL_PER_TICK, hum.MaxHealth - hum.Health, pool)
							hum.Health += amount
							pool -= amount
							healedAny = true
							player:SetAttribute("AtRestFountain", true)
							roomEvent({ kind = "Heal", model = player.Character })
						end
					end
				end
			end
			if healedAny then
				setLevel()
				refreshStatus()
			end
		end
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- TREASURE — the Vault
-- ═════════════════════════════════════════════════════════════════════════════
local TRAP_CHANCE = 0.2

local function buildTreasure(room: Room, folder: Folder, rng: Random)
	local model = Instance.new("Model")
	model.Name = `Vault_{room.id}`
	model.Parent = folder
	local c = Vector3.new(room.centerWorld.X, room.floorY, room.centerWorld.Z)

	-- Two-step dais with gold inlay.
	part(model, { Name = "DaisLower", Size = Vector3.new(16, 0.6, 12), CFrame = CFrame.new(c + Vector3.new(0, 0.3, 0)), Color = STONE_DARK, Material = Enum.Material.Slate })
	part(model, { Name = "DaisUpper", Size = Vector3.new(11, 0.6, 8), CFrame = CFrame.new(c + Vector3.new(0, 0.9, 0)), Color = STONE, Material = Enum.Material.Slate })
	part(model, { Name = "DaisInlay", Size = Vector3.new(11.2, 0.08, 8.2), CFrame = CFrame.new(c + Vector3.new(0, 1.22, 0)), Color = GOLD, Material = Enum.Material.Metal, CanCollide = false, Transparency = 0.2 })

	-- The chest: body, bands, corner caps, lock plate, and a hinged lid.
	local base = c + Vector3.new(0, 1.2, 0)
	local body = part(model, { Name = "ChestBody", Size = Vector3.new(6, 2.8, 3.6), CFrame = CFrame.new(base + Vector3.new(0, 1.4, 0)), Color = WOOD, Material = Enum.Material.Wood })
	for _, x in ipairs({ -2.2, 0, 2.2 }) do
		part(model, { Name = "Band", Size = Vector3.new(0.35, 2.9, 3.7), CFrame = CFrame.new(base + Vector3.new(x, 1.4, 0)), Color = GOLD, Material = Enum.Material.Metal })
	end
	local lock = part(model, { Name = "LockPlate", Size = Vector3.new(0.9, 1.1, 0.25), CFrame = CFrame.new(base + Vector3.new(0, 2.2, -1.85)), Color = GOLD_BRIGHT, Material = Enum.Material.Metal })
	local hingeCF = CFrame.new(base + Vector3.new(0, 2.8, 1.8))
	local lidParts = {}
	local lidOffsets = {}
	local function lidPart(props)
		local p = part(model, props)
		table.insert(lidParts, p)
		lidOffsets[p] = hingeCF:ToObjectSpace(p.CFrame)
		return p
	end
	lidPart({ Name = "Lid", Size = Vector3.new(6, 1, 3.6), CFrame = CFrame.new(base + Vector3.new(0, 3.3, 0)), Color = WOOD_DARK, Material = Enum.Material.Wood })
	lidPart({ Name = "LidCrown", Shape = Enum.PartType.Cylinder, Size = Vector3.new(6, 3.6, 3.6), CFrame = CFrame.new(base + Vector3.new(0, 3.8, 0)), Color = WOOD, Material = Enum.Material.Wood })
	for _, x in ipairs({ -2.2, 0, 2.2 }) do
		lidPart({ Name = "LidBand", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 3.7, 3.7), CFrame = CFrame.new(base + Vector3.new(x, 3.8, 0)), Color = GOLD, Material = Enum.Material.Metal })
	end
	-- Golden light leaking from the seam.
	local seam = part(model, { Name = "Seam", Size = Vector3.new(5.8, 0.12, 3.4), CFrame = CFrame.new(base + Vector3.new(0, 2.84, 0)), Color = GOLD_BRIGHT, Material = Enum.Material.Neon, CanCollide = false })
	local seamLight = pointLight(seam, GOLD_BRIGHT, 1.5, 12)
	sparkles(seam, GOLD_BRIGHT, 5, 2, 1.2)

	-- Hoard: coin piles and braziers around the dais.
	for i = 1, 7 do
		local a = rng:NextNumber() * math.pi * 2
		local r = 6 + rng:NextNumber() * 3
		local p = c + Vector3.new(math.cos(a) * r, 0.15, math.sin(a) * r)
		local h = 0.3 + rng:NextNumber() * 0.5
		cyl(model, "CoinPile", p + Vector3.new(0, h * 0.5, 0), h, 1.5 + rng:NextNumber() * 2, GOLD, Enum.Material.Metal, { CanCollide = false })
	end
	for _, off in ipairs({ Vector3.new(-9, 0, -7), Vector3.new(9, 0, -7), Vector3.new(-9, 0, 7), Vector3.new(9, 0, 7) }) do
		local p = c + off
		cyl(model, "BrazierLeg", p + Vector3.new(0, 1.6, 0), 3.2, 0.7, STONE_DARK, Enum.Material.Metal)
		local bowl = cyl(model, "BrazierBowl", p + Vector3.new(0, 3.4, 0), 0.8, 2.4, GOLD, Enum.Material.Metal)
		fire(bowl, Color3.fromRGB(255, 170, 60), Color3.fromRGB(255, 80, 20), 4)
		pointLight(bowl, Color3.fromRGB(255, 170, 80), 2, 18)
	end
	-- A shaft of light falling on the chest.
	cyl(model, "LightShaft", base + Vector3.new(0, 14, 0), 1, 7, GOLD_BRIGHT, Enum.Material.Neon, { Transparency = 0.9, CanCollide = false, CastShadow = false, Size = Vector3.new(26, 7, 7) })

	local title, status = billboard(model, lock, "THE VAULT", GOLD_BRIGHT, 5)
	status.Text = "Ancient treasure lies within"
	local open = prompt(body, "Open", "Ancient Chest", 0.8)

	open.Triggered:Connect(function(player)
		if model:GetAttribute("Opened") == true then return end
		model:SetAttribute("Opened", true)
		open.Enabled = false

		-- Lid swings open about the back hinge.
		local swing = Instance.new("CFrameValue")
		swing.Value = hingeCF
		swing.Changed:Connect(function(v)
			for _, p in ipairs(lidParts) do p.CFrame = v * lidOffsets[p] end
		end)
		TweenService:Create(swing, TweenInfo.new(0.7, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Value = hingeCF * CFrame.Angles(math.rad(-105), 0, 0) }):Play()
		seamLight.Brightness, seamLight.Range = 6, 26
		seam.Size = Vector3.new(5.8, 0.4, 3.4)

		task.wait(0.35)
		local top = base + Vector3.new(0, 4, 0)
		local luck = luckOf(player)
		local rank = rollChestRank(rng, luck)
		local gold = PlayerStats.AwardGold(player, math.floor((rng:NextInteger(40, 70) + room.tier * 15) * rank.gold))
		coins(top, 18 * rank.tomes)
		burst(top, rank.color, 1.4 + rank.tomes * 0.4)
		seam.Color = rank.color
		seamLight.Color = rank.color
		if rng:NextNumber() < TRAP_CHANCE * (1 - math.min(luck * 3, 0.9)) then
			local hum = playerHumanoid(player)
			if hum then hum:TakeDamage(hum.MaxHealth * 0.25) end
			pop(top, `CURSED HOARD — +{gold} Gold, but it bites`, BAD)
			status.Text = "A curse clung to the gold"
			seam.Color = CRIMSON
			seamLight.Color = CRIMSON
		else
			local names = {}
			for _ = 1, rank.tomes do
				local tome = PlayerStats.GrantTome(player)
				if tome then table.insert(names, tome.name) end
			end
			local list = table.concat(names, " · ")
			pop(top, `{rank.name} HOARD — +{gold} Gold{if #names > 0 then " · " .. list else ""}`, rank.color)
			status.Text = if #names > 0 then `{rank.name}: {list}` else `{rank.name} hoard claimed`
		end
		title.Text = "THE VAULT — EMPTIED"
		task.delay(3, function()
			TweenService:Create(seamLight, TweenInfo.new(2), { Brightness = 0.6 }):Play()
		end)
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- SHOP — the Wandering Merchant
-- ═════════════════════════════════════════════════════════════════════════════
local POTION_PRICE = 30
local REROLL_PRICE = 20

local function tomeColor(tomeId: string): Color3
	local h = 0
	for i = 1, #tomeId do h = (h * 31 + string.byte(tomeId, i)) % 360 end
	return Color3.fromHSV(h / 360, 0.65, 0.95)
end

local function buildShop(room: Room, folder: Folder, rng: Random)
	local model = Instance.new("Model")
	model.Name = `Merchant_{room.id}`
	model.Parent = folder
	local c = Vector3.new(room.centerWorld.X, room.floorY, room.centerWorld.Z)
	-- The stall faces -Z; wares are laid out in front of it.
	local back = c + Vector3.new(0, 0, 6)

	-- Rug, counter, back shelves.
	part(model, { Name = "Rug", Size = Vector3.new(22, 0.1, 16), CFrame = CFrame.new(c + Vector3.new(0, 0.05, -1)), Color = Color3.fromRGB(120, 30, 40), Material = Enum.Material.Fabric, CanCollide = false })
	part(model, { Name = "RugBorder", Size = Vector3.new(22.6, 0.08, 16.6), CFrame = CFrame.new(c + Vector3.new(0, 0.03, -1)), Color = GOLD, Material = Enum.Material.Fabric, CanCollide = false })
	part(model, { Name = "Counter", Size = Vector3.new(12, 3, 2.6), CFrame = CFrame.new(back + Vector3.new(0, 1.5, 0)), Color = WOOD, Material = Enum.Material.WoodPlanks })
	part(model, { Name = "CounterTop", Size = Vector3.new(12.4, 0.3, 3), CFrame = CFrame.new(back + Vector3.new(0, 3.15, 0)), Color = WOOD_DARK, Material = Enum.Material.Wood })
	for _, y in ipairs({ 1.5, 3.5, 5.5 }) do
		part(model, { Name = "Shelf", Size = Vector3.new(12, 0.3, 1.6), CFrame = CFrame.new(back + Vector3.new(0, y, 4)), Color = WOOD_DARK, Material = Enum.Material.Wood })
		for k = 1, 5 do
			cyl(model, "Jar", back + Vector3.new(-5 + k * 1.8 + rng:NextNumber() * 0.4, y + 0.6, 4), 0.9, 0.7,
				Color3.fromHSV(rng:NextNumber(), 0.6, 0.9), Enum.Material.Glass, { Transparency = 0.3, CanCollide = false })
		end
	end
	-- Striped awning on four posts.
	for _, x in ipairs({ -6.2, 6.2 }) do
		for _, z in ipairs({ -1.4, 5.4 }) do
			cyl(model, "Post", back + Vector3.new(x, 4, z), 8, 0.5, WOOD_DARK, Enum.Material.Wood)
		end
	end
	for k = 0, 5 do
		part(model, { ClassName = "WedgePart", Name = "Awning", Size = Vector3.new(2.2, 1.6, 7.6),
			CFrame = CFrame.new(back + Vector3.new(-5.5 + k * 2.2, 8.6, 2)) * CFrame.Angles(0, math.pi, 0),
			Color = k % 2 == 0 and CRIMSON or Color3.fromRGB(240, 225, 190), Material = Enum.Material.Fabric })
	end
	-- Lanterns hanging from the awning.
	for _, x in ipairs({ -5.5, 5.5 }) do
		local lantern = part(model, { Name = "Lantern", Size = Vector3.new(0.8, 1.1, 0.8), CFrame = CFrame.new(back + Vector3.new(x, 6.6, -1.4)), Color = GOLD_BRIGHT, Material = Enum.Material.Neon, CanCollide = false })
		pointLight(lantern, Color3.fromRGB(255, 190, 110), 2, 18)
	end

	-- The merchant: a hooded figure with glinting eyes behind the counter.
	local m = back + Vector3.new(0, 0, 1.6)
	cyl(model, "Robe", m + Vector3.new(0, 2.4, 0), 4.8, 2.6, Color3.fromRGB(45, 30, 60), Enum.Material.Fabric)
	part(model, { Name = "Shoulders", Size = Vector3.new(3, 0.8, 1.6), CFrame = CFrame.new(m + Vector3.new(0, 4.6, 0)), Color = Color3.fromRGB(55, 36, 72), Material = Enum.Material.Fabric })
	local hood = part(model, { Name = "Hood", Shape = Enum.PartType.Ball, Size = Vector3.new(2.3, 2.3, 2.3), CFrame = CFrame.new(m + Vector3.new(0, 5.8, 0)), Color = Color3.fromRGB(40, 26, 54), Material = Enum.Material.Fabric })
	part(model, { Name = "HoodShadow", Shape = Enum.PartType.Ball, Size = Vector3.new(1.7, 1.7, 1.7), CFrame = CFrame.new(m + Vector3.new(0, 5.7, -0.45)), Color = Color3.fromRGB(8, 6, 12), Material = Enum.Material.SmoothPlastic })
	for _, x in ipairs({ -0.28, 0.28 }) do
		part(model, { Name = "MerchantEye", Shape = Enum.PartType.Ball, Size = Vector3.new(0.18, 0.18, 0.18), CFrame = CFrame.new(m + Vector3.new(x, 5.8, -1.28)), Color = GOLD_BRIGHT, Material = Enum.Material.Neon, CanCollide = false })
	end
	local merchantTitle, merchantStatus = billboard(model, hood, "THE WANDERING MERCHANT", GOLD_BRIGHT, 3)
	local basePrice = 55 + room.tier * 15

	-- Wares: three tomes on pedestals in an arc.
	local wares = {}
	local function stockTome(slot)
		local pool = {}
		for _, id in ipairs(TomeData.Order) do
			if id ~= "chaos" and id ~= "cursed" then table.insert(pool, id) end
		end
		local id = pool[rng:NextInteger(1, #pool)]
		local tome = TomeData.GetTome(id)
		slot.tomeId = id
		slot.price = basePrice + rng:NextInteger(-8, 12)
		slot.sold = false
		if slot.bookModel then slot.bookModel:Destroy() end
		slot.bookModel = Instance.new("Model")
		slot.bookModel.Name = `Ware_{slot.index}`
		slot.bookModel.Parent = model
		slot.book = buildBook(slot.bookModel, slot.pos + Vector3.new(0, 5, 0), tomeColor(id))
		slot.title.Text = tome and tome.name or id
		slot.status.Text = `{tome and tome.description or ""} · {slot.price} Gold`
		slot.prompt.ActionText = `Buy ({slot.price} Gold)`
		slot.prompt.ObjectText = tome and tome.name or id
		slot.prompt.Enabled = true
	end
	for i = 1, 3 do
		local a = math.rad(-35 + (i - 1) * 35)
		local pos = back + Vector3.new(math.sin(a) * 9, 0, -math.cos(a) * 9)
		local top = pedestal(model, pos, GOLD)
		local t, s = billboard(model, top, "", GOLD_BRIGHT, 4.2)
		local slot = { index = i, pos = pos, top = top, title = t, status = s, prompt = prompt(top, "Buy", "", 0.4) }
		wares[i] = slot
		stockTome(slot)
		slot.prompt.Triggered:Connect(function(player)
			if slot.sold then return end
			if not PlayerStats.CanReceiveTome(player, slot.tomeId) then
				pop(top.Position + Vector3.new(0, 3, 0), "Your tome slots are full", BAD)
				return
			end
			if not PlayerStats.SpendGold(player, slot.price) then
				pop(top.Position + Vector3.new(0, 3, 0), `Needs {slot.price} Gold`, BAD)
				return
			end
			slot.sold = true
			slot.prompt.Enabled = false
			local tome = PlayerStats.GrantTome(player, slot.tomeId)
			burst(slot.book.Position, tomeColor(slot.tomeId), 1.2)
			pop(slot.book.Position, `Purchased {tome and tome.name or ""}`, GOOD)
			slot.bookModel:Destroy()
			slot.bookModel = nil
			slot.title.Text = "SOLD"
			slot.status.Text = ""
			merchantStatus.Text = "A pleasure doing business."
		end)
	end

	-- Potion on the counter: heals 60% of max HP, two in stock.
	local potionPos = back + Vector3.new(-3.5, 4, -0.4)
	local flask = part(model, { Name = "Potion", Shape = Enum.PartType.Ball, Size = Vector3.new(1.2, 1.2, 1.2), CFrame = CFrame.new(potionPos), Color = Color3.fromRGB(230, 40, 70), Material = Enum.Material.Glass, Transparency = 0.15, CanCollide = false })
	cyl(model, "PotionNeck", potionPos + Vector3.new(0, 0.8, 0), 0.6, 0.4, Color3.fromRGB(230, 40, 70), Enum.Material.Glass, { Transparency = 0.15, CanCollide = false })
	pointLight(flask, Color3.fromRGB(255, 70, 90), 1.2, 7)
	local potionStock = 2
	local potionPrompt = prompt(flask, `Buy Potion ({POTION_PRICE} Gold)`, `Restorative Draught ×{potionStock}`, 0.3)
	potionPrompt.Triggered:Connect(function(player)
		local hum = playerHumanoid(player)
		if potionStock <= 0 or not hum then return end
		if not PlayerStats.SpendGold(player, POTION_PRICE) then
			pop(potionPos + Vector3.new(0, 2, 0), `Needs {POTION_PRICE} Gold`, BAD)
			return
		end
		potionStock -= 1
		hum.Health = math.min(hum.MaxHealth, hum.Health + hum.MaxHealth * 0.6)
		roomEvent({ kind = "Heal", model = player.Character })
		pop(potionPos + Vector3.new(0, 2, 0), "Restored!", GOOD)
		potionPrompt.ObjectText = `Restorative Draught ×{potionStock}`
		if potionStock <= 0 then
			potionPrompt.Enabled = false
			flask.Transparency = 0.8
		end
	end)

	-- Bell on the counter: reroll all unsold wares.
	local bell = part(model, { Name = "Bell", Shape = Enum.PartType.Ball, Size = Vector3.new(0.9, 0.9, 0.9), CFrame = CFrame.new(back + Vector3.new(3.5, 3.7, -0.4)), Color = GOLD_BRIGHT, Material = Enum.Material.Metal, CanCollide = false })
	local bellPrompt = prompt(bell, `Reroll wares ({REROLL_PRICE} Gold)`, "Merchant's Bell", 0.3)
	bellPrompt.Triggered:Connect(function(player)
		local unsold = 0
		for _, slot in ipairs(wares) do if not slot.sold then unsold += 1 end end
		if unsold == 0 then return end
		if not PlayerStats.SpendGold(player, REROLL_PRICE) then
			pop(bell.Position + Vector3.new(0, 2, 0), `Needs {REROLL_PRICE} Gold`, BAD)
			return
		end
		burst(bell.Position, GOLD_BRIGHT, 0.8)
		merchantStatus.Text = "Fresh stock, just for you…"
		for _, slot in ipairs(wares) do
			if not slot.sold then stockTome(slot) end
		end
	end)
	merchantStatus.Text = "Rare tomes, fair prices."
end

-- ═════════════════════════════════════════════════════════════════════════════
-- GAMBLE — the Gambling Den
-- ═════════════════════════════════════════════════════════════════════════════
-- Wheel of Fate slices, in order around the wheel.
local WHEEL: { { label: string, kind: string, color: Color3 } } = {
	{ label = "BUST", kind = "bust", color = Color3.fromRGB(40, 36, 48) },
	{ label = "×2", kind = "x2", color = Color3.fromRGB(40, 150, 90) },
	{ label = "BUST", kind = "bust", color = Color3.fromRGB(60, 20, 30) },
	{ label = "TOME", kind = "tome", color = ROYAL },
	{ label = "BUST", kind = "bust", color = Color3.fromRGB(40, 36, 48) },
	{ label = "×3", kind = "x3", color = Color3.fromRGB(30, 110, 200) },
	{ label = "CURSE", kind = "curse", color = CRIMSON },
	{ label = "×2", kind = "x2", color = Color3.fromRGB(40, 150, 90) },
	{ label = "BUST", kind = "bust", color = Color3.fromRGB(60, 20, 30) },
	{ label = "TOME", kind = "tome", color = ROYAL },
	{ label = "BUST", kind = "bust", color = Color3.fromRGB(40, 36, 48) },
	{ label = "JACKPOT", kind = "jackpot", color = GOLD },
}
local SPIN_TIME = 4.2
local WHEEL_RADIUS = 7
-- The den is laid out facing the isometric camera (IsometricCamera's
-- CAMERA_OFFSET sits at -X/+Z), so the wheel's face is always in view.
local VIEW_FACING = Vector3.new(-1, 0, 1).Unit

local function buildWheel(model: Model, center: Vector3, facing: Vector3, rng: Random)
	-- `facing` is the direction the wheel face looks (toward the players).
	local faceCF = CFrame.lookAt(center, center + facing)

	-- Frame: two legs, a crossbeam, base.
	local right = faceCF.RightVector
	for _, s in ipairs({ -1, 1 }) do
		local legPos = center + right * s * (WHEEL_RADIUS + 1) - facing * 0.8
		part(model, { Name = "WheelLeg", Size = Vector3.new(1, center.Y - model:GetAttribute("FloorY"), 1), CFrame = CFrame.new(Vector3.new(legPos.X, (center.Y + model:GetAttribute("FloorY")) / 2, legPos.Z)), Color = WOOD_DARK, Material = Enum.Material.Wood })
	end
	part(model, { Name = "Axle", Shape = Enum.PartType.Cylinder, Size = Vector3.new(2.2, 1, 1), CFrame = faceCF * CFrame.new(0, 0, 0.4) * CFrame.Angles(0, math.rad(90), 0), Color = GOLD, Material = Enum.Material.Metal })

	-- Rotor: everything that spins is tagged WheelRotor; the client rotates it
	-- about the hub's facing axis using the wheel's spin attributes.
	local hub = part(model, { Name = "WheelHub", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.9, 2.6, 2.6), CFrame = faceCF * CFrame.new(0, 0, -0.35) * CFrame.Angles(0, math.rad(90), 0), Color = GOLD_BRIGHT, Material = Enum.Material.Metal })
	hub:SetAttribute("WheelRotor", true)
	model:SetAttribute("WheelFaceCF", faceCF)
	local n = #WHEEL
	local sliceAngle = math.pi * 2 / n
	-- Each slice is a true pie wedge: two right-triangle WedgeParts meeting on
	-- the slice's centre line, apex at the hub. Neighbours share edges instead
	-- of overlapping, so their colours can't flicker over each other.
	local halfWidth = WHEEL_RADIUS * math.sin(sliceAngle / 2)
	local depth = WHEEL_RADIUS * math.cos(sliceAngle / 2)
	for i, slice in ipairs(WHEEL) do
		local a = (i - 1) * sliceAngle
		local sliceCF = faceCF * CFrame.Angles(0, 0, -a) -- +Y points out along the slice
		for _, side in ipairs({ 1, -1 }) do
			-- A WedgePart's triangle lies in its local YZ plane with the right
			-- angle at bottom-back: local +Y runs along the chord, +Z out to it.
			local centre = sliceCF * Vector3.new(side * halfWidth / 2, depth / 2, 0)
			local half = part(model, { ClassName = "WedgePart", Name = "Slice",
				Size = Vector3.new(0.3, halfWidth, depth),
				CFrame = CFrame.fromMatrix(centre, sliceCF.ZVector * side, sliceCF.RightVector * side, sliceCF.UpVector),
				Color = slice.color, Material = Enum.Material.SmoothPlastic })
			half:SetAttribute("WheelRotor", true)
		end
		-- Label on its own invisible plate just in front of the wedges.
		local chord = 2 * halfWidth
		local plate = part(model, { Name = "SliceLabel", Size = Vector3.new(chord * 0.75, 1.8, 0.05), Transparency = 1, CanCollide = false,
			CFrame = sliceCF * CFrame.new(0, WHEEL_RADIUS * 0.7, -0.2) })
		plate:SetAttribute("WheelRotor", true)
		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front -- faceCF looks toward the players
		gui.LightInfluence = 0
		gui.PixelsPerStud = 40
		gui.Parent = plate
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBlack
		t.TextScaled = true
		t.TextColor3 = slice.kind == "jackpot" and Color3.fromRGB(60, 30, 0) or Color3.new(1, 1, 1)
		t.Text = slice.label
		t.Parent = gui
		-- Gold divider between slices.
		local div = part(model, { Name = "Divider", Size = Vector3.new(0.18, WHEEL_RADIUS, 0.4),
			CFrame = faceCF * CFrame.Angles(0, 0, -(a + sliceAngle / 2)) * CFrame.new(0, WHEEL_RADIUS * 0.5, -0.05), Color = GOLD, Material = Enum.Material.Metal })
		div:SetAttribute("WheelRotor", true)
	end
	-- Rim of bulbs (blinked by the client).
	for i = 1, 24 do
		local a = (i / 24) * math.pi * 2
		local bulb = part(model, { Name = "RimBulb", Shape = Enum.PartType.Ball, Size = Vector3.new(0.55, 0.55, 0.55),
			CFrame = faceCF * CFrame.Angles(0, 0, a) * CFrame.new(0, WHEEL_RADIUS + 0.3, -0.2), Color = i % 2 == 0 and GOLD_BRIGHT or Color3.fromRGB(255, 120, 150), Material = Enum.Material.Neon, CanCollide = false })
		bulb:SetAttribute("RimBulb", i)
	end
	-- Pointer at the top.
	-- Pointer: a gold diamond fixed at the top of the wheel (12 o'clock).
	part(model, { Name = "Pointer", Size = Vector3.new(1.2, 1.2, 0.4),
		CFrame = faceCF * CFrame.new(0, WHEEL_RADIUS + 1.1, -0.6) * CFrame.Angles(0, 0, math.rad(45)), Color = GOLD_BRIGHT, Material = Enum.Material.Neon, CanCollide = false })
	model:SetAttribute("WheelAngle", 0)
	return hub
end

local function buildGamble(room: Room, folder: Folder, rng: Random)
	local model = Instance.new("Model")
	model.Name = `GamblingDen_{room.id}`
	model:SetAttribute("FloorY", room.floorY)
	model:SetAttribute("RoomFX", "Wheel")
	model.Parent = folder
	local c = Vector3.new(room.centerWorld.X, room.floorY, room.centerWorld.Z)
	-- Laid out in a frame whose front (-Z) faces the camera; `at` places a
	-- local offset in the world.
	local R = CFrame.lookAt(Vector3.zero, VIEW_FACING)
	local function at(offset: Vector3): Vector3
		return c + R * offset
	end

	-- Velvet carpet with a gold border, card-suit lanterns, piles of chips.
	part(model, { Name = "Carpet", Size = Vector3.new(30, 0.1, 24), CFrame = CFrame.new(c + Vector3.new(0, 0.05, 0)) * R, Color = VELVET, Material = Enum.Material.Fabric, CanCollide = false })
	part(model, { Name = "CarpetBorder", Size = Vector3.new(30.8, 0.08, 24.8), CFrame = CFrame.new(c + Vector3.new(0, 0.03, 0)) * R, Color = GOLD, Material = Enum.Material.Fabric, CanCollide = false })
	for i = 1, 6 do
		local a = (i / 6) * math.pi * 2
		local p = at(Vector3.new(math.cos(a) * 16, 0, math.sin(a) * 13))
		cyl(model, "LanternPost", p + Vector3.new(0, 3, 0), 6, 0.5, WOOD_DARK, Enum.Material.Wood)
		local lamp = part(model, { Name = "DenLantern", Size = Vector3.new(1.1, 1.4, 1.1), CFrame = CFrame.new(p + Vector3.new(0, 6.5, 0)) * CFrame.Angles(0, math.rad(45), 0), Color = i % 2 == 0 and ROYAL or CRIMSON, Material = Enum.Material.Neon, CanCollide = false })
		pointLight(lamp, lamp.Color, 2.2, 20)
	end

	-- ── The Wheel of Fate, at the back of the room facing the camera ──
	local wheelCenter = at(Vector3.new(0, WHEEL_RADIUS + 2.2, 7))
	buildWheel(model, wheelCenter, VIEW_FACING, rng)
	local wheelSign = part(model, { Name = "WheelSign", Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CanCollide = false, CFrame = CFrame.new(wheelCenter + Vector3.new(0, WHEEL_RADIUS + 1, 0)) })
	local wheelTitle, wheelStatus = billboard(model, wheelSign, "WHEEL OF FATE", GOLD_BRIGHT, 2.5)
	wheelStatus.Text = "Bet · spin · pray"

	-- Betting podium in front of the wheel with three stakes.
	local podium = part(model, { Name = "BetPodium", Size = Vector3.new(9, 3, 2.4), CFrame = CFrame.new(at(Vector3.new(0, 1.5, 1.5))) * R, Color = WOOD, Material = Enum.Material.WoodPlanks })
	part(model, { Name = "PodiumTop", Size = Vector3.new(9.4, 0.25, 2.8), CFrame = CFrame.new(at(Vector3.new(0, 3.1, 1.5))) * R, Color = Color3.fromRGB(20, 80, 45), Material = Enum.Material.Fabric })
	local spinning = false
	for i, stake in ipairs({ 25, 50, 100 }) do
		local chipPos = at(Vector3.new(-3 + (i - 1) * 3, 3.5, 1.5))
		local chip = cyl(model, "Chip", chipPos, 0.4, 1.4, ({ Color3.fromRGB(230, 230, 230), CRIMSON, Color3.fromRGB(30, 30, 30) })[i], Enum.Material.SmoothPlastic)
		cyl(model, "ChipRim", chipPos + Vector3.new(0, 0.01, 0), 0.42, 1.0, GOLD, Enum.Material.Metal, { CanCollide = false })
		local p = prompt(chip, `Bet {stake} Gold`, "Wheel of Fate", 0.4)
		p.MaxActivationDistance = 8
		p.Triggered:Connect(function(player)
			if spinning then return end
			if not PlayerStats.SpendGold(player, stake) then
				pop(chipPos + Vector3.new(0, 2, 0), `Needs {stake} Gold`, BAD)
				return
			end
			spinning = true
			wheelStatus.Text = `{player.DisplayName} bets {stake}…`
			-- Pick the result, then aim the wheel so that slice lands under the pointer.
			local index = rng:NextInteger(1, #WHEEL)
			-- Luck: a chance (3× luck, max 75%) to dodge a BUST / CURSE once.
			local kind = WHEEL[index].kind
			if (kind == "bust" or kind == "curse") and rng:NextNumber() < math.min(luckOf(player) * 3, 0.75) then
				index = rng:NextInteger(1, #WHEEL)
			end
			local slice = WHEEL[index]
			local sliceAngle = math.pi * 2 / #WHEEL
			local from = model:GetAttribute("WheelAngle") or 0
			local landing = (index - 1) * sliceAngle + (rng:NextNumber() - 0.5) * sliceAngle * 0.7
			local base = from - (from % (math.pi * 2))
			local to = base + math.pi * 2 * rng:NextInteger(5, 7) + landing
			model:SetAttribute("SpinFrom", from)
			model:SetAttribute("SpinTo", to)
			model:SetAttribute("SpinDuration", SPIN_TIME)
			model:SetAttribute("SpinStart", Workspace:GetServerTimeNow())
			task.wait(SPIN_TIME + 0.15)
			model:SetAttribute("WheelAngle", to)

			local hum = playerHumanoid(player)
			local at = wheelCenter + VIEW_FACING * 1.5
			if slice.kind == "bust" then
				pop(at, "BUST", Color3.fromRGB(190, 190, 200))
				wheelStatus.Text = "The house thanks you."
			elseif slice.kind == "x2" or slice.kind == "x3" then
				local mult = slice.kind == "x2" and 2 or 3
				player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + stake * mult)
				coins(at, 10 * mult)
				burst(at, GOOD, 1.4)
				pop(at, `×{mult}! +{stake * mult} Gold`, GOOD)
				wheelStatus.Text = "Fortune smiles."
			elseif slice.kind == "tome" then
				local tome = PlayerStats.GrantTome(player)
				burst(at, ROYAL, 1.6)
				pop(at, tome and `TOME — {tome.name}` or "TOME", Color3.fromRGB(200, 160, 255))
				wheelStatus.Text = "Knowledge has a price."
			elseif slice.kind == "curse" then
				if hum then hum:TakeDamage(hum.MaxHealth * 0.3) end
				burst(at, CRIMSON, 1.6)
				pop(at, "CURSED", BAD)
				wheelStatus.Text = "Fate bites back."
			elseif slice.kind == "jackpot" then
				player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + stake * 5)
				local tome = PlayerStats.GrantTome(player)
				coins(at, 60)
				burst(at, GOLD_BRIGHT, 3)
				roomEvent({ kind = "Jackpot", position = at })
				pop(at, `JACKPOT! +{stake * 5} Gold{tome and (" · " .. tome.name) or ""}`, GOLD_BRIGHT)
				wheelStatus.Text = "JACKPOT!"
			end
			spinning = false
		end)
	end
	local podiumTitle, podiumStatus = billboard(model, podium, "PLACE YOUR BET", GOLD_BRIGHT, 3.2)
	podiumStatus.Text = "×2 · ×3 · TOME · JACKPOT ×5 — or BUST / CURSE"

	-- ── Double-or-Nothing altar, well off to the podium's left (level with
	-- it, so its sign and prompt never sit over the betting chips) ──
	local altarPos = at(Vector3.new(-12.5, 0, 1.5))
	cyl(model, "AltarBase", altarPos + Vector3.new(0, 0.5, 0), 1, 5, STONE_DARK, Enum.Material.Slate)
	cyl(model, "AltarColumn", altarPos + Vector3.new(0, 2, 0), 2.4, 2.6, Color3.fromRGB(30, 26, 36), Enum.Material.Basalt)
	local coin = cyl(model, "FateCoin", altarPos + Vector3.new(0, 4.4, 0), 0.25, 1.8, GOLD_BRIGHT, Enum.Material.Metal, { CanCollide = false })
	coin.CFrame = CFrame.new(coin.Position) * CFrame.Angles(math.rad(90), 0, 0)
	coin:SetAttribute("Float", true)
	pointLight(coin, GOLD_BRIGHT, 1.5, 10)
	local altarTitle, altarStatus = billboard(model, coin, "DOUBLE OR NOTHING", Color3.fromRGB(255, 150, 170), 2.5)
	altarStatus.Text = "Stake half your gold on a single toss"
	local tossing = false
	local altarPrompt = prompt(coin, "Toss the coin", "Half your gold", 0.8)
	altarPrompt.MaxActivationDistance = 7
	altarPrompt.Triggered:Connect(function(player)
		if tossing then return end
		local gold = player:GetAttribute("Gold") or 0
		local stake = math.floor(gold / 2)
		if stake < 20 then
			pop(coin.Position + Vector3.new(0, 2, 0), "Come back with at least 40 Gold", BAD)
			return
		end
		tossing = true
		player:SetAttribute("Gold", gold - stake)
		roomEvent({ kind = "CoinToss", part = coin })
		task.wait(1.6)
		-- 48% base; each point of luck adds a point of win chance (max 75%).
		if rng:NextNumber() < math.min(0.48 + luckOf(player), 0.75) then
			player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + stake * 2)
			coins(coin.Position, 24)
			burst(coin.Position, GOLD_BRIGHT, 1.6)
			pop(coin.Position + Vector3.new(0, 2, 0), `DOUBLED! +{stake} Gold`, GOOD)
		else
			burst(coin.Position, CRIMSON, 1)
			pop(coin.Position + Vector3.new(0, 2, 0), `NOTHING. −{stake} Gold`, BAD)
		end
		tossing = false
	end)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- ─── Cursed altar ──────────────────────────────────────────────────────────
-- A black altar in violet fire. Accept its bargain (once each): lose a quarter
-- of your max health for the rest of the run, and take a run relic (a choice
-- of three) and a piece of gear, Epic or better.
local CURSE = Color3.fromRGB(150, 50, 220)
local function buildCursed(room: Room, folder: Folder, rng: Random)
	local model = Instance.new("Model")
	model.Name = `CursedAltar_{room.id}`
	model.Parent = folder
	local c = Vector3.new(room.centerWorld.X, room.floorY, room.centerWorld.Z)
	cyl(model, "AltarRing", c + Vector3.new(0, 0.08, 0), 0.08, 16, CURSE, Enum.Material.Neon, { Transparency = 0.45, CanCollide = false })
	cyl(model, "AltarFloor", c + Vector3.new(0, 0.3, 0), 0.5, 13, Color3.fromRGB(26, 20, 30), Enum.Material.Basalt)
	local altar = part(model, { Name = "Altar", Size = Vector3.new(6, 3.4, 3.4), CFrame = CFrame.new(c + Vector3.new(0, 2.25, 0)),
		Color = Color3.fromRGB(20, 16, 24), Material = Enum.Material.Slate })
	part(model, { Name = "AltarTop", Size = Vector3.new(6.8, 0.5, 4.2), CFrame = CFrame.new(c + Vector3.new(0, 4.2, 0)), Color = Color3.fromRGB(40, 30, 50), Material = Enum.Material.Marble })
	-- the skull on it, in violet fire
	local skull = part(model, { Name = "Skull", Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, CFrame = CFrame.new(c + Vector3.new(0, 5.2, 0)),
		Color = Color3.fromRGB(225, 215, 200), Material = Enum.Material.SmoothPlastic, CanCollide = false })
	fire(skull, CURSE, Color3.fromRGB(60, 0, 90), 4)
	pointLight(skull, CURSE, 2.5, 22)
	-- four pillars round it, chained to the altar
	for i = 0, 3 do
		local a = i * math.pi / 2 + math.pi / 4
		local p = c + Vector3.new(math.cos(a) * 6.5, 0, math.sin(a) * 6.5)
		part(model, { Name = "Pillar", Size = Vector3.new(1.4, 7, 1.4), CFrame = CFrame.new(p + Vector3.new(0, 3.5, 0)), Color = Color3.fromRGB(34, 28, 40), Material = Enum.Material.Slate })
		local flame = part(model, { Name = "Brazier", Size = Vector3.new(1.6, 0.6, 1.6), CFrame = CFrame.new(p + Vector3.new(0, 7.3, 0)), Color = Color3.fromRGB(20, 16, 24), Material = Enum.Material.Metal })
		fire(flame, CURSE, Color3.fromRGB(30, 0, 50), 3)
		local from = p + Vector3.new(0, 5, 0)
		local to = c + Vector3.new(0, 3.5, 0)
		part(model, { Name = "Chain", Size = Vector3.new(0.18, 0.18, (to - from).Magnitude), CFrame = CFrame.lookAt((from + to) / 2, to),
			Color = Color3.fromRGB(70, 60, 70), Material = Enum.Material.Metal, CanCollide = false })
	end
	sparkles(skull, CURSE, 8, 1.5, 1.5)
	local title, sub = billboard(model, altar, "CURSED ALTAR", CURSE, 7.5)
	sub.Text = "Lose 25% max HP for the run. Gain a relic and rare gear."
	local taken: { [Player]: boolean } = {}
	local pr = prompt(altar, "Accept the curse", "Cursed Altar", 1.2)
	pr.Triggered:Connect(function(player: Player)
		if taken[player] or player:GetAttribute("InLobby") ~= false then return end
		taken[player] = true
		PlayerStats.AddCurse(player)
		local _, root = playerHumanoid(player)
		if root then
			pop(root.Position + Vector3.new(0, 4, 0), "CURSED: -25% MAX HP", CURSE)
			burst(root.Position, CURSE, 1.4)
		end
		pcall(function()
			local LootManager = require(script.Parent:WaitForChild("LootManager")) :: any
			LootManager.Drop(player, "cursed", c + Vector3.new(0, 0.5, 0), "Epic")
		end)
		PlayerStats.OfferRelics(player)
		title.Text = "CURSED ALTAR"
	end)
end

function SpecialRooms.Build(room: Room, folder: Folder, rng: Random): boolean
	if room.roomType == "Cursed" then
		buildCursed(room, folder, rng)
		return true
	elseif room.roomType == "Rest" then
		buildRest(room, folder, rng)
	elseif room.roomType == "Treasure" then
		buildTreasure(room, folder, rng)
	elseif room.roomType == "Shop" then
		buildShop(room, folder, rng)
	elseif room.roomType == "Gamble" then
		buildGamble(room, folder, rng)
	else
		return false
	end
	return true
end

return SpecialRooms
