--!strict
--[[
	IslandHUD.luau
	The Forgotten Isle on screen, only while on an island run (RunScope
	"Island"). Everything it shows comes from the server (IslandEvent); every
	choice it offers is a request the server checks (IslandAction).

	  • the title as the run begins ("THE FORGOTTEN ISLE")
	  • top right: the region they're in, the wave, the island's level and its
	    XP bar, the event running and its time left, and a GEAR button
	  • notices under the timer: landmarks found, loot (in its rarity's
	    colour), level-ups, waves, a Behemoth, a perk going off, an ambush
	  • big banners: events, the ritual, a boss's arrival and its fall
	  • the boss's bar while a ritual boss fights
	  • the ritual panel (examining the altar): what it is, whether it's
	    ready, and BEGIN THE RITUAL
	  • the gear panel (G): what they wear, their bag, an item against what
	    it would replace, EQUIP / SALVAGE / UNEQUIP
	  • markers: a chest within an Oracle's Veil's reach, the Elite Hunt's
	    beast, the Cursed Treasure, the Ancient Echo's shrine
	  • the sky: the Rift Surge's violet, the Blood Moon's red, the ritual's
	    tremor (the camera shakes while the statues wake), the Eclipse
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local EquipmentData = require(Shared:WaitForChild("EquipmentData"))

local player = Players.LocalPlayer

local IslandHUD = {}

-- (the in-game HUD's palette: GameHUD)
local C = {
	stone = Color3.fromRGB(14, 11, 17),
	stone2 = Color3.fromRGB(28, 23, 32),
	gold = Color3.fromRGB(212, 172, 92),
	goldBright = Color3.fromRGB(255, 222, 140),
	white = Color3.fromRGB(242, 236, 224),
	dim = Color3.fromRGB(160, 150, 140),
	red = Color3.fromRGB(214, 64, 58),
	violet = Color3.fromRGB(185, 110, 255),
	green = Color3.fromRGB(120, 230, 140),
	xp = Color3.fromRGB(150, 110, 255),
}
local SERIF = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local REGION_COLORS: { [string]: Color3 } = {
	shore = Color3.fromRGB(140, 210, 230), forest = Color3.fromRGB(150, 210, 110), ruins = Color3.fromRGB(220, 200, 150),
	highlands = Color3.fromRGB(255, 140, 80), caves = Color3.fromRGB(150, 170, 255), sanctuary = Color3.fromRGB(200, 150, 255),
}
local STAT_NAMES: { [string]: string } = {
	damage = "Damage", maxHealth = "Max Health", armor = "Armor", evasion = "Evasion", critChance = "Crit Chance",
	critDamage = "Crit Damage", abilityDamage = "Ability Damage", abilityCooldown = "Cooldowns", movementSpeed = "Speed",
	basicAttackSpeed = "Attack Speed", luck = "Luck", killHeal = "Heal on Kill", lifesteal = "Lifesteal", goldGain = "Gold",
	healthRegenPerMinute = "Regen / min", knockback = "Knockback", xpGain = "XP", shield = "Shield",
}

-- (the chests' own sounds: IslandChests)
local SFX = {
	boom = "rbxassetid://9125404320",
	burst = "rbxassetid://9116384485",
	chime = "rbxassetid://9116394545",
}
local function sfx(id: string, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.Parent = game:GetService("SoundService")
	s:Play()
	s.Ended:Once(function() s:Destroy() end)
end

local function remote(name: string): RemoteEvent
	return Network.GetRemoteEvent((Network.Remotes :: any)[name])
end

local function ask(action: string, data: { [string]: any }?)
	local msg = data or {}
	msg.action = action
	remote("IslandAction"):FireServer(msg)
end

-- ── Little builders ─────────────────────────────────────────────────────────
local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in pairs(props) do (i :: any)[k] = v end
	if parent then i.Parent = parent end
	return i
end

local function label(parent: Instance, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = SERIF, TextColor3 = C.white, TextSize = 14,
		TextStrokeTransparency = 0.5, TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props) do (l :: any)[k] = v end
	return l
end

local function plate(parent: Instance, props: { [string]: any }): Frame
	local f = new("Frame", { BackgroundColor3 = C.stone, BackgroundTransparency = 0.12, BorderSizePixel = 0 }, parent)
	for k, v in pairs(props) do (f :: any)[k] = v end
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, f)
	new("UIStroke", { Color = C.gold, Thickness = 1.2, Transparency = 0.25 }, f)
	return f
end

local function button(parent: Instance, text: string, color: Color3, props: { [string]: any }): TextButton
	local b = new("TextButton", {
		BackgroundColor3 = C.stone2, BorderSizePixel = 0, AutoButtonColor = true, FontFace = SERIF_BOLD,
		Text = text, TextColor3 = color, TextSize = 14,
	}, parent)
	for k, v in pairs(props) do (b :: any)[k] = v end
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
	new("UIStroke", { Color = color, Thickness = 1.2, Transparency = 0.3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end

local function pct(v: number): string
	local p = v * 100
	return if math.abs(p - math.floor(p + 0.5)) < 0.05 then tostring(math.floor(p + 0.5)) else string.format("%.1f", p)
end

-- One tome effect in words ("+8% Damage", "+40 Max Health").
local function effectText(stat: string, op: string, value: number): string
	local name = STAT_NAMES[stat] or stat
	local sign = if value >= 0 then "+" else "-"
	local v = math.abs(value)
	if op == "add" and v >= 1 then return `{sign}{math.floor(v + 0.5)} {name}` end
	if stat == "abilityCooldown" then return `-{pct(v)}% {name}` end
	return `{sign}{pct(v)}% {name}`
end

-- An item's effects summed by stat (and how each is shown).
local function totals(item: EquipmentData.Item?): { [string]: { op: string, value: number } }
	local out = {}
	if not item then return out end
	for _, e in ipairs(item.stats) do
		local t = out[e.stat] or { op = e.operation, value = 0 }
		t.value += e.value
		out[e.stat] = t
	end
	return out
end

-- ── State ───────────────────────────────────────────────────────────────────
local gui: ScreenGui
local onIsland = false
local bag: { { uid: number, id: string } } = {}
local equipped: { [string]: { uid: number, id: string } } = {}
local eventEnds = 0
local eventName = ""

-- ── The title ───────────────────────────────────────────────────────────────
local titleFrame: Frame
local function showTitle()
	titleFrame.Visible = true
	for _, l in ipairs(titleFrame:GetChildren()) do
		if l:IsA("TextLabel") then
			l.TextTransparency = 1
			l.TextStrokeTransparency = 1
			TweenService:Create(l, TweenInfo.new(1.2), { TextTransparency = 0, TextStrokeTransparency = 0.4 }):Play()
		end
	end
	task.delay(4.5, function()
		for _, l in ipairs(titleFrame:GetChildren()) do
			if l:IsA("TextLabel") then TweenService:Create(l, TweenInfo.new(1.5), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
		end
		task.wait(1.6)
		titleFrame.Visible = false
	end)
end

-- ── Notices ─────────────────────────────────────────────────────────────────
local toastList: Frame
local function toast(text: string, color: Color3?, sub: string?)
	local f = plate(toastList, { Size = UDim2.fromOffset(340, if sub then 48 else 30), BackgroundTransparency = 0.25 })
	label(f, { Text = text, Size = UDim2.new(1, -16, 0, 26), Position = UDim2.fromOffset(8, 2), FontFace = SERIF_BOLD,
		TextColor3 = color or C.white, TextSize = 15, TextXAlignment = Enum.TextXAlignment.Center, RichText = true })
	if sub then
		label(f, { Text = sub, Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 26), TextSize = 12,
			TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center, RichText = true, TextScaled = true }).TextWrapped = true
	end
	-- (no more than four at once: the oldest goes)
	local shown = {}
	for _, c in ipairs(toastList:GetChildren()) do
		if c:IsA("Frame") then table.insert(shown, c) end
	end
	if #shown > 4 then shown[1]:Destroy() end
	task.delay(4.2, function()
		if not f.Parent then return end
		for _, d in ipairs(f:GetDescendants()) do
			if d:IsA("TextLabel") then TweenService:Create(d, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play() end
			if d:IsA("UIStroke") then TweenService:Create(d, TweenInfo.new(0.6), { Transparency = 1 }):Play() end
		end
		TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 1 }):Play()
		task.wait(0.65)
		f:Destroy()
	end)
end

local bannerFrame: Frame
local bannerTitle: TextLabel
local bannerSub: TextLabel
local bannerToken = 0
local function banner(title: string, color: Color3, sub: string?, hold: number?)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color
	bannerSub.Text = sub or ""
	bannerFrame.Visible = true
	bannerTitle.TextTransparency, bannerSub.TextTransparency = 1, 1
	bannerTitle.TextStrokeTransparency, bannerSub.TextStrokeTransparency = 1, 1
	bannerTitle.Position = UDim2.fromOffset(0, 10)
	TweenService:Create(bannerTitle, TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextTransparency = 0, TextStrokeTransparency = 0.3, Position = UDim2.fromOffset(0, 0) }):Play()
	TweenService:Create(bannerSub, TweenInfo.new(0.6), { TextTransparency = 0, TextStrokeTransparency = 0.5 }):Play()
	task.delay(hold or 3.5, function()
		if bannerToken ~= token then return end
		TweenService:Create(bannerTitle, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		TweenService:Create(bannerSub, TweenInfo.new(0.8), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		task.wait(0.85)
		if bannerToken == token then bannerFrame.Visible = false end
	end)
end

-- ── The sky ─────────────────────────────────────────────────────────────────
local tint: ColorCorrectionEffect? = nil
local function setTint(props: { [string]: any }?, t: number)
	if not tint then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "IsleTint"
		cc.Parent = Lighting
		tint = cc
	end
	local goal = props or { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0, Brightness = 0 }
	TweenService:Create(tint :: ColorCorrectionEffect, TweenInfo.new(t), goal):Play()
end
local EVENT_TINTS: { [string]: { [string]: any } } = {
	rift_surge = { TintColor = Color3.fromRGB(228, 205, 255), Saturation = 0.1, Contrast = 0.05, Brightness = 0 },
	blood_moon = { TintColor = Color3.fromRGB(255, 165, 160), Saturation = -0.05, Contrast = 0.12, Brightness = -0.03 },
}
local currentEvent: string? = nil

-- The ground shaking, for `t` seconds, growing: a small jolt to the camera
-- after the camera scripts have placed it each frame.
local tremorUntil, tremorStart, tremorStrength = 0, 0, 0
local function tremor(t: number, strength: number)
	tremorStart = os.clock()
	tremorUntil = tremorStart + t
	tremorStrength = strength
end
local function tremorStep()
	local now = os.clock()
	if now >= tremorUntil then return end
	local k = tremorStrength * (0.4 + 0.6 * ((now - tremorStart) / math.max(0.01, tremorUntil - tremorStart)))
	local cam = Workspace.CurrentCamera
	cam.CFrame = cam.CFrame * CFrame.new((math.random() - 0.5) * k, (math.random() - 0.5) * k, 0)
		* CFrame.Angles(0, 0, math.rad((math.random() - 0.5) * k * 1.5))
end

-- ── Markers ─────────────────────────────────────────────────────────────────
local markers: { [string]: { part: BasePart?, gui: BillboardGui } } = {}
local function clearMarker(key: string)
	local m = markers[key]
	if not m then return end
	m.gui:Destroy()
	if m.part then m.part:Destroy() end
	markers[key] = nil
end

-- A marker over `at` (an instance, or a point), seen through walls.
local function marker(key: string, at: Instance | Vector3, text: string, color: Color3)
	clearMarker(key)
	local anchor: Instance
	local part: BasePart? = nil
	if typeof(at) == "Vector3" then
		local p = new("Part", { Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Transparency = 1,
			Size = Vector3.one, CFrame = CFrame.new(at + Vector3.new(0, 8, 0)) }, Workspace)
		part = p
		anchor = p
	else
		anchor = at
	end
	local g = new("BillboardGui", { Size = UDim2.fromOffset(160, 40), AlwaysOnTop = true, LightInfluence = 0,
		StudsOffset = Vector3.new(0, 6, 0), MaxDistance = 2000, Adornee = if anchor:IsA("Model") then (anchor :: Model).PrimaryPart else anchor }, gui)
	local l = label(g, { Text = text, Size = UDim2.fromScale(1, 0.6), FontFace = SERIF_BOLD, TextSize = 15, TextColor3 = color,
		TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2 })
	local d = label(g, { Text = "", Size = UDim2.fromScale(1, 0.4), Position = UDim2.fromScale(0, 0.6), TextSize = 12,
		TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.3 })
	d.Name = "Dist"
	l.Name = "Title"
	markers[key] = { part = part, gui = g }
end

-- ── The boss's bar ──────────────────────────────────────────────────────────
local bossFrame: Frame
local bossName: TextLabel
local bossFill: Frame
local bossTrail: Frame
local bossPct: TextLabel
local bossModel: Model? = nil

local function setBoss(model: Model?, name: string?, title: string?, color: Color3?)
	bossModel = model
	bossFrame.Visible = model ~= nil
	if model then
		bossName.Text = (name or "") .. (if title and title ~= "" then `  <font size="13" color="#b9aea0">— {title}</font>` else "")
		bossFill.BackgroundColor3 = color or C.red
		bossFill.Size = UDim2.fromScale(1, 1)
		bossTrail.Size = UDim2.fromScale(1, 1)
	end
end

-- ── The ritual panel ────────────────────────────────────────────────────────
local ritualPanel: Frame
local ritualStatus: TextLabel
local ritualSlain: TextLabel
local ritualBegin: TextButton
local ritualLore: TextLabel
local ritualOpenAt: Vector3? = nil

local function showRitual(msg: any)
	ritualPanel.Visible = true
	ritualLore.Text = tostring(msg.lore or "")
	local ready = msg.state == "ready"
	local status
	if msg.state == "dormant" then
		status = `<font color="#9d93a8">DORMANT</font> — the island hasn't stirred enough yet (wave {msg.wave} of {msg.minWave})`
	elseif msg.state == "cooldown" then
		status = `<font color="#9d93a8">RESTING</font> — the altar wakes again in {msg.cooldown}s`
	elseif msg.state == "summoning" or msg.state == "fighting" then
		status = `<font color="#ff6a5a">AWAKE</font> — a ritual is already under way`
	else
		status = `<font color="#c9a4ff">READY</font> — one of {msg.bosses} sovereigns will answer. Beware: it fights until it falls.`
	end
	ritualStatus.Text = status
	ritualSlain.Text = if (msg.slain or 0) > 0 then `Sovereigns slain this run: {msg.slain}` else ""
	ritualBegin.Visible = ready
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	ritualOpenAt = root and root.Position or nil
end

-- ── The gear panel ──────────────────────────────────────────────────────────
local gearPanel: Frame
local slotsFrame: Frame
local bagFrame: Frame
local detail: Frame
local detailTitle: TextLabel
local detailBody: TextLabel
local detailA: TextButton
local detailB: TextButton
local selected: { kind: string, uid: number?, slot: string? }? = nil
local renderGear: () -> ()

local function itemColor(item: EquipmentData.Item?): Color3
	local r = item and EquipmentData.Rarities[item.rarity]
	return if r then r.color else C.dim
end

-- The item it would replace (what's in its slot; for an accessory, the
-- first of the two that's empty, else the first).
local function replaces(item: EquipmentData.Item): EquipmentData.Item?
	local fits = EquipmentData.SlotFits[item.slot] or { item.slot }
	for _, s in ipairs(fits) do
		if not equipped[s] then return nil end
	end
	local o = equipped[fits[1]]
	return o and EquipmentData.Get(o.id)
end

local function describe(item: EquipmentData.Item, against: EquipmentData.Item?): string
	local lines = {}
	local rar = EquipmentData.Rarities[item.rarity]
	table.insert(lines, `<font color="#{(rar and rar.color or C.dim):ToHex()}">{item.rarity}</font> · {EquipmentData.SlotNames[item.slot] or item.slot} · <i>{item.role}</i>`)
	local mine, theirs = totals(item), totals(against)
	local seen = {}
	for stat, t in pairs(mine) do
		seen[stat] = true
		local diff = ""
		if against then
			local d = t.value - (if theirs[stat] then theirs[stat].value else 0)
			if math.abs(d) > 1e-6 then
				diff = if d > 0 then `  <font color="#78e68c">({effectText(stat, t.op, d)})</font>` else `  <font color="#ff7a6a">({effectText(stat, t.op, d)})</font>`
			end
		end
		table.insert(lines, effectText(stat, t.op, t.value) .. diff)
	end
	if against then
		for stat, t in pairs(theirs) do
			if not seen[stat] then table.insert(lines, `<font color="#ff7a6a">({effectText(stat, t.op, -t.value)})</font>`) end
		end
	end
	table.insert(lines, `<font color="#ffde8c">PERK: {item.perk.text}</font>`)
	if against then
		table.insert(lines, `<font color="#9d93a8">Replaces {against.name} (PERK: {against.perk.text})</font>`)
	end
	return table.concat(lines, "\n")
end

local function selectItem(sel: { kind: string, uid: number?, slot: string? }?)
	selected = sel
	if not sel then
		detail.Visible = false
		return
	end
	local owned: { uid: number, id: string }? = nil
	if sel.kind == "bag" then
		for _, o in ipairs(bag) do
			if o.uid == sel.uid then owned = o end
		end
	else
		owned = if sel.slot then equipped[sel.slot] else nil
	end
	local item = owned and EquipmentData.Get(owned.id)
	if not item or not owned then
		detail.Visible = false
		return
	end
	detail.Visible = true
	detailTitle.Text = item.name
	detailTitle.TextColor3 = itemColor(item)
	local salvage = EquipmentData.Rarities[item.rarity] and EquipmentData.Rarities[item.rarity].salvage or 0
	if sel.kind == "bag" then
		detailBody.Text = describe(item, replaces(item))
		detailA.Text = "EQUIP"
		detailA.Visible = true
		detailB.Text = `SALVAGE ({salvage}g)`
		detailB.Visible = true
	else
		detailBody.Text = describe(item, nil)
		detailA.Text = "UNEQUIP"
		detailA.Visible = true
		detailB.Visible = false
	end
end

local function cell(parent: Instance, item: EquipmentData.Item?, caption: string, order: number, onClick: () -> ()): TextButton
	local b = new("TextButton", { Name = "Cell" .. order, BackgroundColor3 = C.stone2, BorderSizePixel = 0, Text = "", LayoutOrder = order,
		Size = UDim2.fromOffset(86, 58), AutoButtonColor = true }, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
	new("UIStroke", { Color = itemColor(item), Thickness = if item then 1.6 else 1, Transparency = if item then 0 else 0.6,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	label(b, { Text = caption, Size = UDim2.new(1, -6, 0, 14), Position = UDim2.fromOffset(3, 2), TextSize = 10, TextColor3 = C.dim,
		TextXAlignment = Enum.TextXAlignment.Center })
	label(b, { Text = if item then item.name else "—", Size = UDim2.new(1, -6, 1, -18), Position = UDim2.fromOffset(3, 16), TextSize = 11,
		FontFace = SERIF_BOLD, TextColor3 = if item then itemColor(item) else C.dim, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center })
	b.MouseButton1Click:Connect(onClick)
	return b
end

renderGear = function()
	for _, c in ipairs(slotsFrame:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for _, c in ipairs(bagFrame:GetChildren()) do
		if c:IsA("TextButton") then c:Destroy() end
	end
	for i, slot in ipairs(EquipmentData.Slots) do
		local o = equipped[slot]
		local item = o and EquipmentData.Get(o.id)
		cell(slotsFrame, item, EquipmentData.SlotNames[slot] or slot, i, function()
			if item then selectItem({ kind = "slot", slot = slot }) else selectItem(nil) end
		end)
	end
	for i = 1, EquipmentData.BAG do
		local o = bag[i]
		local item = o and EquipmentData.Get(o.id)
		cell(bagFrame, item, if item then EquipmentData.SlotNames[item.slot] or item.slot else "empty", i, function()
			if o then selectItem({ kind = "bag", uid = o.uid }) else selectItem(nil) end
		end)
	end
	if selected then selectItem(selected) end
end

local function toggleGear(open: boolean?)
	local want = if open == nil then not gearPanel.Visible else open
	gearPanel.Visible = want and onIsland
	if gearPanel.Visible then
		ask("gear")
		renderGear()
	else
		selectItem(nil)
	end
end

-- ── Building it ─────────────────────────────────────────────────────────────
local panel: Frame
local regionText: TextLabel
local waveText: TextLabel
local levelText: TextLabel
local xpFill: Frame
local eventText: TextLabel

local function build()
	gui = new("ScreenGui", { Name = "IslandHUD", IgnoreGuiInset = true, ResetOnSpawn = false, DisplayOrder = 34, Enabled = false },
		player:WaitForChild("PlayerGui"))

	-- the title
	titleFrame = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.34),
		Size = UDim2.fromOffset(800, 120), Visible = false }, gui)
	label(titleFrame, { Text = "THE FORGOTTEN ISLE", Size = UDim2.new(1, 0, 0, 64), FontFace = SERIF_BOLD, TextSize = 52,
		TextColor3 = C.goldBright, TextXAlignment = Enum.TextXAlignment.Center })
	label(titleFrame, { Text = "Survive the island. Grow stronger. Wake the altar at its heart.", Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.fromOffset(0, 70), TextSize = 18, TextColor3 = C.white, TextXAlignment = Enum.TextXAlignment.Center })

	-- top right
	panel = plate(gui, { Name = "Status", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 18), Size = UDim2.fromOffset(250, 128) })
	regionText = label(panel, { Text = "", Size = UDim2.new(1, -16, 0, 20), Position = UDim2.fromOffset(8, 6), FontFace = SERIF_BOLD, TextSize = 15 })
	waveText = label(panel, { Text = "WAVE 1", Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 28), TextSize = 13, TextColor3 = C.gold })
	levelText = label(panel, { Text = "LEVEL 1", Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 48), TextSize = 13, RichText = true })
	local xpBack = new("Frame", { BackgroundColor3 = Color3.fromRGB(30, 20, 45), BorderSizePixel = 0, Position = UDim2.fromOffset(8, 70),
		Size = UDim2.new(1, -16, 0, 8) }, panel)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, xpBack)
	xpFill = new("Frame", { BackgroundColor3 = C.xp, BorderSizePixel = 0, Size = UDim2.fromScale(0, 1) }, xpBack)
	new("UICorner", { CornerRadius = UDim.new(0, 3) }, xpFill)
	eventText = label(panel, { Text = "", Size = UDim2.new(1, -16, 0, 18), Position = UDim2.fromOffset(8, 82), TextSize = 12,
		TextColor3 = C.violet, FontFace = SERIF_BOLD, RichText = true })
	local gearBtn = button(panel, "GEAR  [G]", C.gold, { Position = UDim2.fromOffset(8, 102), Size = UDim2.new(1, -16, 0, 20), TextSize = 12 })
	gearBtn.MouseButton1Click:Connect(function() toggleGear() end)

	-- notices, down the right under the panel (clear of the relic icons at the edge)
	toastList = new("Frame", { Name = "Notices", BackgroundTransparency = 1, AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -72, 0, 160),
		Size = UDim2.fromOffset(340, 300) }, gui)
	new("UIListLayout", { Padding = UDim.new(0, 6), HorizontalAlignment = Enum.HorizontalAlignment.Right, SortOrder = Enum.SortOrder.LayoutOrder }, toastList)

	-- banners
	bannerFrame = new("Frame", { BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(900, 100), Visible = false }, gui)
	bannerTitle = label(bannerFrame, { Text = "", Size = UDim2.new(1, 0, 0, 56), FontFace = SERIF_BOLD, TextSize = 44,
		TextXAlignment = Enum.TextXAlignment.Center })
	bannerSub = label(bannerFrame, { Text = "", Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 58), TextSize = 18,
		TextXAlignment = Enum.TextXAlignment.Center, RichText = true })

	-- the boss's bar
	bossFrame = new("Frame", { Name = "BossBar", BackgroundTransparency = 1, AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 148),
		Size = UDim2.fromOffset(620, 50), Visible = false }, gui)
	bossName = label(bossFrame, { Text = "", Size = UDim2.new(1, 0, 0, 22), FontFace = SERIF_BOLD, TextSize = 18, TextColor3 = C.goldBright,
		TextXAlignment = Enum.TextXAlignment.Center, RichText = true })
	local bar = plate(bossFrame, { Position = UDim2.fromOffset(0, 26), Size = UDim2.new(1, 0, 0, 16), BackgroundColor3 = Color3.fromRGB(30, 8, 12),
		BackgroundTransparency = 0 })
	bar.ClipsDescendants = true
	bossTrail = new("Frame", { BackgroundColor3 = Color3.fromRGB(236, 170, 70), BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, bar)
	bossFill = new("Frame", { BackgroundColor3 = C.red, BorderSizePixel = 0, Size = UDim2.fromScale(1, 1) }, bar)
	bossPct = label(bar, { Text = "", Size = UDim2.fromScale(1, 1), TextSize = 11, FontFace = SERIF_BOLD, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })

	-- the ritual panel
	ritualPanel = plate(gui, { Name = "RitualPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(520, 300),
		Visible = false, BackgroundTransparency = 0.05 })
	label(ritualPanel, { Text = "THE RITUAL ALTAR", Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 14), FontFace = SERIF_BOLD,
		TextSize = 26, TextColor3 = C.violet, TextXAlignment = Enum.TextXAlignment.Center })
	ritualLore = label(ritualPanel, { Text = "", Size = UDim2.new(1, -48, 0, 60), Position = UDim2.fromOffset(24, 56), TextSize = 14,
		TextColor3 = C.white, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Center, TextYAlignment = Enum.TextYAlignment.Top })
	label(ritualPanel, { Text = "Eight statues. One altar. Six sovereigns: the Drowned Sovereign, the Ashen Colossus, the Hollow Saint, the Thorn Matriarch, the Riftbound Knight, the Eclipse Wyrm.",
		Size = UDim2.new(1, -48, 0, 40), Position = UDim2.fromOffset(24, 116), TextSize = 12, TextColor3 = C.dim, TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Center })
	ritualStatus = label(ritualPanel, { Text = "", Size = UDim2.new(1, -48, 0, 40), Position = UDim2.fromOffset(24, 164), TextSize = 14,
		TextWrapped = true, RichText = true, TextXAlignment = Enum.TextXAlignment.Center })
	ritualSlain = label(ritualPanel, { Text = "", Size = UDim2.new(1, -48, 0, 18), Position = UDim2.fromOffset(24, 206), TextSize = 12,
		TextColor3 = C.gold, TextXAlignment = Enum.TextXAlignment.Center })
	ritualBegin = button(ritualPanel, "BEGIN THE RITUAL", C.violet, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, -95, 0, 238),
		Size = UDim2.fromOffset(200, 40), TextSize = 15 })
	local leave = button(ritualPanel, "LEAVE", C.dim, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 125, 0, 238),
		Size = UDim2.fromOffset(120, 40) })
	ritualBegin.MouseButton1Click:Connect(function()
		ask("ritual_begin")
		ritualPanel.Visible = false
	end)
	leave.MouseButton1Click:Connect(function() ritualPanel.Visible = false end)

	-- the gear panel
	gearPanel = plate(gui, { Name = "GearPanel", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(680, 470),
		Visible = false, BackgroundTransparency = 0.05 })
	label(gearPanel, { Text = "ISLAND GEAR", Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 10), FontFace = SERIF_BOLD,
		TextSize = 22, TextColor3 = C.goldBright, TextXAlignment = Enum.TextXAlignment.Center })
	label(gearPanel, { Text = "Worn for this run only: lost when it ends.", Size = UDim2.new(1, 0, 0, 16), Position = UDim2.fromOffset(0, 40),
		TextSize = 12, TextColor3 = C.dim, TextXAlignment = Enum.TextXAlignment.Center })
	local close = button(gearPanel, "X", C.dim, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 10), Size = UDim2.fromOffset(28, 28) })
	close.MouseButton1Click:Connect(function() toggleGear(false) end)
	label(gearPanel, { Text = "EQUIPPED", Size = UDim2.fromOffset(200, 16), Position = UDim2.fromOffset(20, 64), TextSize = 12, TextColor3 = C.gold })
	slotsFrame = new("Frame", { Name = "Slots", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 82), Size = UDim2.new(1, -40, 0, 60) }, gearPanel)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(86, 58), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, slotsFrame)
	label(gearPanel, { Text = `BAG (holds {EquipmentData.BAG}: more is salvaged for gold)`, Size = UDim2.fromOffset(400, 16), Position = UDim2.fromOffset(20, 152),
		TextSize = 12, TextColor3 = C.gold })
	bagFrame = new("Frame", { Name = "Bag", BackgroundTransparency = 1, Position = UDim2.fromOffset(20, 170), Size = UDim2.new(1, -40, 0, 124) }, gearPanel)
	new("UIGridLayout", { CellSize = UDim2.fromOffset(118, 58), CellPadding = UDim2.fromOffset(6, 6), SortOrder = Enum.SortOrder.LayoutOrder }, bagFrame)
	detail = new("Frame", { Name = "Detail", BackgroundColor3 = C.stone2, BorderSizePixel = 0, Position = UDim2.fromOffset(20, 302), Size = UDim2.new(1, -40, 0, 154),
		Visible = false }, gearPanel)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, detail)
	detailTitle = label(detail, { Text = "", Size = UDim2.new(1, -170, 0, 22), Position = UDim2.fromOffset(10, 6), FontFace = SERIF_BOLD, TextSize = 17 })
	detailBody = label(detail, { Text = "", Size = UDim2.new(1, -170, 1, -32), Position = UDim2.fromOffset(10, 30), TextSize = 13, RichText = true,
		TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top })
	detailA = button(detail, "EQUIP", C.green, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 14), Size = UDim2.fromOffset(145, 36) })
	detailB = button(detail, "SALVAGE", C.red, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 58), Size = UDim2.fromOffset(145, 36) })
	detailA.MouseButton1Click:Connect(function()
		local sel = selected
		if not sel then return end
		if sel.kind == "bag" then ask("equip", { uid = sel.uid }) else ask("unequip", { slot = sel.slot }) end
		selectItem(nil)
	end)
	detailB.MouseButton1Click:Connect(function()
		local sel = selected
		if sel and sel.kind == "bag" then ask("salvage", { uid = sel.uid }) end
		selectItem(nil)
	end)
end

-- ── Messages ────────────────────────────────────────────────────────────────
local function itemName(id: string): string
	local it = EquipmentData.Get(id)
	if not it then return id end
	return `<font color="#{itemColor(it):ToHex()}">{it.name}</font>`
end

local CHEST_TITLES: { [string]: string } = { common = "Chest", rare = "Rare Chest", cursed = "Cursed Chest", elite = "Elite Chest", ritual = "Ritual Chest" }

local function onMessage(msg: any)
	if typeof(msg) ~= "table" then return end
	local kind = msg.kind
	if kind == "gear" then
		bag = msg.bag or {}
		equipped = msg.equipped or {}
		if gearPanel.Visible then renderGear() end
	elseif kind == "discover" then
		toast(`Discovered: {msg.name}`, REGION_COLORS[msg.region] or C.goldBright, if (msg.xp or 0) > 0 then `+{msg.xp} XP` else nil)
	elseif kind == "loot" then
		local parts = {}
		for _, id in ipairs(msg.items or {}) do table.insert(parts, itemName(id)) end
		if msg.gold then table.insert(parts, `<font color="#ffdc78">{msg.gold} gold</font>`) end
		if msg.consumable then
			local c = EquipmentData.Consumables[msg.consumable]
			if c then table.insert(parts, `<font color="#{c.color:ToHex()}">{c.name}</font>`) end
		end
		if msg.tome then table.insert(parts, `<font color="#c9a4ff">{msg.tome}</font>`) end
		toast(CHEST_TITLES[msg.chest] or "Chest", C.goldBright, table.concat(parts, "  ·  "))
		-- a Legendary gets a banner of its own
		for _, id in ipairs(msg.items or {}) do
			local it = EquipmentData.Get(id)
			if it and it.rarity == "Legendary" then
				banner(it.name, itemColor(it), "LEGENDARY  ·  press G to wear it", 3)
				sfx(SFX.burst, 0.6)
			end
		end
	elseif kind == "salvaged" then
		local it = EquipmentData.Get(msg.id)
		toast(if msg.auto then "Bag full: salvaged" else "Salvaged", C.dim, `{it and it.name or msg.id}  →  {msg.gold} gold`)
	elseif kind == "level" then
		toast(`LEVEL {msg.level}`, C.xp, "Choose a tome")
	elseif kind == "wave" then
		toast(`WAVE {msg.wave}`, C.red, "The island stirs: more of them, and stronger")
	elseif kind == "behemoth" then
		banner("A CURSED BEHEMOTH", C.red, `It stalks {msg.region}`, 3)
	elseif kind == "perk" then
		toast(msg.text, C.goldBright)
	elseif kind == "cursed" then
		toast("The seal breaks", C.red, `{msg.by} woke {msg.count} of the dead: clear them to open the chest`)
	elseif kind == "ritual_info" then
		showRitual(msg)
	elseif kind == "ritual_ready" then
		toast("The altar is ready", C.violet, "Find it at the island's heart, in the Ancient Sanctuary")
		sfx(SFX.chime, 0.5)
	elseif kind == "ritual_start" then
		ritualPanel.Visible = false
		banner("THE RITUAL BEGINS", C.violet, `{msg.by} woke the statues`, (msg.duration or 7) - 1)
		tremor(msg.duration or 7, 0.6)
		setTint({ TintColor = Color3.fromRGB(215, 190, 255), Saturation = 0.15, Contrast = 0.15, Brightness = -0.05 }, 2)
	elseif kind == "ritual_boss" then
		setTint(if currentEvent then EVENT_TINTS[currentEvent] else nil, 2)
		banner(msg.name or "", msg.color or C.red, msg.title, 3.5)
		setBoss(msg.model, msg.name, msg.title, msg.color)
	elseif kind == "ritual_victory" then
		setBoss(nil)
		banner("SOVEREIGN SLAIN", C.goldBright, `{msg.name} has fallen. A Ritual Chest rises at the altar.`, 4)
		sfx(SFX.burst, 0.8)
	elseif kind == "ritual_failed" then
		setBoss(nil)
		setTint(if currentEvent then EVENT_TINTS[currentEvent] else nil, 2)
		banner("THE RITUAL BREAKS", C.dim, "Everyone left the circle. The sovereign sinks back into the stone.", 3.5)
	elseif kind == "event" then
		currentEvent = msg.id
		eventEnds = os.clock() + (msg.duration or 0)
		eventName = msg.name or ""
		banner(msg.name or "", if msg.id == "blood_moon" then C.red else C.violet, msg.line, 4)
		sfx(SFX.boom, 0.6)
		setTint(EVENT_TINTS[msg.id], 3)
		if msg.id == "elite_hunt" and typeof(msg.model) == "Instance" then
			marker("hunt", msg.model, "THE HUNTED", C.red)
		elseif msg.id == "cursed_treasure" and typeof(msg.pos) == "Vector3" then
			marker("treasure", msg.pos, "CURSED TREASURE", Color3.fromRGB(255, 80, 90))
		elseif msg.id == "ancient_echo" and typeof(msg.pos) == "Vector3" then
			marker("echo", msg.pos, "FORGOTTEN SHRINE", Color3.fromRGB(120, 230, 255))
		end
	elseif kind == "event_end" then
		currentEvent = nil
		eventEnds = 0
		setTint(nil, 3)
		clearMarker("hunt")
		clearMarker("treasure")
		clearMarker("echo")
	elseif kind == "echo" then
		clearMarker("echo")
		if msg.blessed then
			banner("A BLESSING", Color3.fromRGB(255, 230, 140), `{msg.by} communed with the shrine: {msg.line} for {msg.seconds}s`, 4)
		else
			banner("A CURSE", C.red, `{msg.by} woke something angry: {msg.line}`, 4)
		end
	elseif kind == "hunt_done" then
		clearMarker("hunt")
		toast("The beast is slain", C.goldBright, `+{msg.gold} gold each, and an Elite Chest where it fell`)
	end
end

-- ── Every frame (only what changed is written) ──────────────────────────────
local last: { [string]: any } = {}
local function set(key: string, inst: any, prop: string, value: any)
	if last[key] ~= value then
		last[key] = value
		inst[prop] = value
	end
end

local trail = 1
local function step()
	local now = RunScope.Mine("Island") == true and player:GetAttribute("InLobby") == false
	if now ~= onIsland then
		onIsland = now
		gui.Enabled = now
		if now then
			showTitle()
			ask("gear")
		else
			gearPanel.Visible = false
			ritualPanel.Visible = false
			setBoss(nil)
			setTint(nil, 1)
			for key in pairs(markers) do clearMarker(key) end
			currentEvent = nil
			eventEnds = 0
		end
	end
	if not onIsland then return end

	local region = IslandConfig.Region(player:GetAttribute("IslandRegion"))
	set("region", regionText, "Text", if region then string.upper(region.name) else "THE FORGOTTEN ISLE")
	set("regionC", regionText, "TextColor3", if region then (REGION_COLORS[region.id] or C.white) else C.white)
	local wave = RunScope.Mine("IslandWave") or 1
	local alive = RunScope.Mine("IslandAlive") or 0
	set("wave", waveText, "Text", `WAVE {wave}   ·   {alive} foes near`)
	local lv = player:GetAttribute("IslandLevel") or 1
	local xp = player:GetAttribute("IslandXP") or 0
	local nxt = math.max(1, player:GetAttribute("IslandXPNext") or 1)
	set("level", levelText, "Text", `LEVEL {lv}   <font color="#9d93a8">{xp} / {nxt} XP</font>`)
	set("xp", xpFill, "Size", UDim2.fromScale(math.clamp(xp / nxt, 0, 1), 1))
	if eventEnds > 0 then
		set("event", eventText, "Text", `{eventName}  ·  {math.max(0, math.ceil(eventEnds - os.clock()))}s`)
	else
		set("event", eventText, "Text", if RunScope.Mine("IslandBossActive") == true then `<font color="#ff6a5a">A SOVEREIGN FIGHTS AT THE ALTAR</font>` else "")
	end

	-- the boss's bar
	local m = bossModel
	if m then
		local hum = m:FindFirstChildOfClass("Humanoid")
		if not m.Parent or not hum or hum.Health <= 0 then
			setBoss(nil)
		else
			local f = math.clamp(hum.Health / math.max(1, hum.MaxHealth), 0, 1)
			trail = if trail > f then math.max(f, trail - 0.004) else f
			set("bossF", bossFill, "Size", UDim2.fromScale(f, 1))
			set("bossT", bossTrail, "Size", UDim2.fromScale(trail, 1))
			local state = if m:GetAttribute("BossInvulnerable") == true then "INVULNERABLE" elseif m:GetAttribute("Enraged") == true then `ENRAGED  ·  {math.ceil(f * 100)}%` else `{math.ceil(f * 100)}%`
			set("bossP", bossPct, "Text", state)
		end
	end

	-- the ritual panel closes if they walk away from the altar
	if ritualPanel.Visible and ritualOpenAt then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root or (root.Position - ritualOpenAt).Magnitude > 22 then ritualPanel.Visible = false end
	end
end

-- Markers' distances, and the Oracle's Veil's chests (a few times a second).
local function slowStep()
	if not onIsland then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	for _, mk in pairs(markers) do
		local ad = mk.gui.Adornee
		local d = mk.gui:FindFirstChild("Dist") :: TextLabel?
		if ad and ad:IsA("BasePart") and d then d.Text = `{math.floor((ad.Position - root.Position).Magnitude)} studs` end
	end
	local reach = player:GetAttribute("OracleRadius")
	for _, chest in ipairs(CollectionService:GetTagged("IslandChest")) do
		if chest:IsA("Model") and chest.PrimaryPart then
			local key = "chest_" .. chest:GetDebugId()
			local inReach = typeof(reach) == "number" and reach > 0 and (chest.PrimaryPart.Position - root.Position).Magnitude <= reach
			if inReach and not markers[key] then
				local k = chest:GetAttribute("ChestKind")
				marker(key, chest, CHEST_TITLES[k] or "Chest", if k == "cursed" then C.red elseif k == "rare" or k == "elite" then C.violet else C.goldBright)
			elseif not inReach and markers[key] then
				clearMarker(key)
			end
		end
	end
	for key, mk in pairs(markers) do
		local ad = mk.gui.Adornee
		if string.sub(key, 1, 6) == "chest_" and (not ad or not ad.Parent) then clearMarker(key) end
	end
end

function IslandHUD.Init()
	build()
	remote("IslandEvent").OnClientEvent:Connect(function(msg)
		local ok, err = pcall(onMessage, msg)
		if not ok then warn("[IslandHUD]", err) end
	end)
	-- (the Eclipse Wyrm's TOTAL ECLIPSE: the light dies while it lasts)
	remote("BossFX").OnClientEvent:Connect(function(data)
		if typeof(data) == "table" and data.kind == "island_eclipse" then
			setTint({ TintColor = Color3.fromRGB(255, 200, 150), Saturation = -0.3, Contrast = 0.2, Brightness = -0.25 }, 1)
			tremor(1.2, 0.4)
			task.delay(data.duration or 8, function()
				setTint(if currentEvent then EVENT_TINTS[currentEvent] else nil, 2)
			end)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not onIsland then return end
		if input.KeyCode == Enum.KeyCode.G then toggleGear() end
	end)
	RunService.Heartbeat:Connect(step)
	RunService:BindToRenderStep("IsleTremor", Enum.RenderPriority.Camera.Value + 2, tremorStep)
	-- (a panel open: the mouse is freed from the crosshair to click it; IsometricCamera)
	RunService.Heartbeat:Connect(function()
		local want = onIsland and (gearPanel.Visible or ritualPanel.Visible)
		if (player:GetAttribute("UIFreeMouse") == true) ~= want then player:SetAttribute("UIFreeMouse", if want then true else nil) end
	end)
	task.spawn(function()
		while true do
			task.wait(0.4)
			pcall(slowStep)
		end
	end)
end

return IslandHUD
