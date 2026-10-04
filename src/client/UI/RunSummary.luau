--!strict
--[[
	RunSummary.luau
	The screen at the end of a run (RunStats sends it when the run's over for
	you: you left, fell for good, or extracted). Over everything, the menu
	loading behind it:

	  RUN COMPLETE / FALLEN IN THE ABYSS / RUN ENDED
	  the map, the floor reached, the time, the Threat
	  YOUR RUN   kills, elites, bosses, best streak, damage, biggest hit,
	             damage taken, healing, abilities, revives, deaths
	  REWARDS    souls, account XP (with the floor bonus), gold, tickets,
	             and every piece of loot found, by rarity
	  THE PARTY  everyone who ran with you, side by side (co-op)

	Numbers count up as it opens. CONTINUE closes it.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local MapData = require(Shared:WaitForChild("MapData"))
local ClassData = require(Shared:WaitForChild("ClassData"))

local player = Players.LocalPlayer

local RunSummary = {}

local GOLD = Color3.fromRGB(240, 196, 110)
local PARCH = Color3.fromRGB(238, 226, 204)
local MUTED = Color3.fromRGB(170, 158, 140)
local DARK = Color3.fromRGB(16, 12, 14)
local CARD = Color3.fromRGB(28, 22, 24)
local RED = Color3.fromRGB(220, 80, 70)
local TITLE_FONT = Enum.Font.Antique
local BODY = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

-- Rarity colours (loot cards).
local RARITY: { [string]: Color3 } = {
	Common = Color3.fromRGB(170, 170, 170),
	Uncommon = Color3.fromRGB(90, 200, 110),
	Rare = Color3.fromRGB(80, 150, 255),
	Epic = Color3.fromRGB(180, 100, 255),
	Legendary = Color3.fromRGB(255, 170, 40),
	Mythic = Color3.fromRGB(255, 70, 90),
}
RunSummary.Rarity = RARITY

local gui: ScreenGui? = nil

local function commas(n: number): string
	local s = tostring(math.floor(n + 0.5))
	local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if out:sub(1, 1) == "," then out = out:sub(2) end
	return out
end

local function clock(sec: number): string
	sec = math.max(0, math.floor(sec))
	return string.format("%d:%02d", sec // 60, sec % 60)
end

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = BODY
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function card(parent: Instance, title: string, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BackgroundColor3 = CARD
	f.BackgroundTransparency = 0.1
	for k, v in pairs(props) do (f :: any)[k] = v end
	f.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = f
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Transparency = 0.6
	s.Parent = f
	label(f, title, 15, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(16, 10), Size = UDim2.new(1, -32, 0, 20) })
	return f
end

-- A number that counts up to `to` once shown.
local counters: { { l: TextLabel, to: number, fmt: (number) -> string, delay: number } } = {}
local function countUp(l: TextLabel, to: number, fmt: ((number) -> string)?, delay: number?)
	table.insert(counters, { l = l, to = to, fmt = fmt or commas, delay = delay or 0 })
	l.Text = (fmt or commas)(0)
end

local function statRow(parent: Instance, y: number, x: number, w: number, name: string, value: number, order: number, fmt: ((number) -> string)?)
	label(parent, name, 15, MUTED, { Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 22) })
	local v = label(parent, "", 17, PARCH, { FontFace = BOLD, Position = UDim2.fromOffset(x, y), Size = UDim2.fromOffset(w, 22),
		TextXAlignment = Enum.TextXAlignment.Right })
	countUp(v, value, fmt, 0.15 + order * 0.06)
end

local function close()
	local g = gui
	if not g then return end
	gui = nil
	local root = g:FindFirstChild("Root") :: CanvasGroup?
	if root then
		TweenService:Create(root, TweenInfo.new(0.3), { GroupTransparency = 1 }):Play()
	end
	task.delay(0.32, function() g:Destroy() end)
end

local function show(s: any)
	if gui then gui:Destroy() end
	table.clear(counters)
	local g = Instance.new("ScreenGui")
	g.Name = "RunSummary"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 1100 -- (over the loading screen: the menu loads behind it)
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g

	local root = Instance.new("CanvasGroup")
	root.Name = "Root"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.new(0, 0, 0)
	root.BackgroundTransparency = 0.35
	root.GroupTransparency = 1
	root.Parent = g

	local W, H = 1000, 640
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W, H)
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.04
	panel.Parent = root
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 14)
	pc.Parent = panel
	local ps = Instance.new("UIStroke")
	ps.Color = GOLD
	ps.Thickness = 1.5
	ps.Transparency = 0.3
	ps.Parent = panel
	-- (fits small screens)
	local sc = Instance.new("UIScale")
	sc.Parent = panel
	local function fit()
		local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		sc.Scale = math.min(1, (vp.X - 40) / W, (vp.Y - 40) / H)
	end
	fit()

	-- The heading.
	local result = tostring(s.result)
	local heading = if result == "extracted" then "RUN COMPLETE"
		elseif result == "fallen" then "FALLEN IN THE ABYSS"
		else "RUN ENDED"
	label(panel, heading, 44, if result == "fallen" then RED else GOLD, { Font = TITLE_FONT, Position = UDim2.fromOffset(0, 18),
		Size = UDim2.new(1, 0, 0, 48), TextXAlignment = Enum.TextXAlignment.Center })
	local map = MapData.Get(s.mapId)
	local class = ClassData.GetClass(s.classId)
	local bits = {}
	if class then table.insert(bits, class.name) end
	if map then table.insert(bits, map.name) end
	table.insert(bits, `Floor {s.floor or 1}`)
	table.insert(bits, clock(tonumber(s.time) or 0))
	table.insert(bits, `Threat {math.max(1, (tonumber(s.tier) or 0) + 1)}`)
	if (tonumber(s.corruption) or 0) > 0 then table.insert(bits, `Corruption {s.corruption}`) end
	label(panel, table.concat(bits, "   ·   "), 16, PARCH, { Position = UDim2.fromOffset(0, 70), Size = UDim2.new(1, 0, 0, 22),
		TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.15 })

	-- a new deepest floor
	if typeof(s.records) == "table" and s.records.newBest then
		local rec = label(panel, `◆  NEW RECORD: FLOOR {s.floor}, YOUR DEEPEST YET  ◆`, 14, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(0, 90),
			Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
		task.spawn(function()
			while rec.Parent do
				TweenService:Create(rec, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { TextTransparency = 0.35 }):Play()
				task.wait(0.6)
				TweenService:Create(rec, TweenInfo.new(0.6, Enum.EasingStyle.Sine), { TextTransparency = 0 }):Play()
				task.wait(0.6)
			end
		end)
	end

	-- YOUR RUN
	local st = s.stats or {}
	local partyRows = (s.party or {}) :: { any }
	local hasParty = #partyRows > 0
	local cardsH = if hasParty then 330 else 440
	local mine = card(panel, "YOUR RUN", { Position = UDim2.fromOffset(24, 108), Size = UDim2.fromOffset(470, cardsH) })
	local rows = {
		{ "Enemies slain", st.kills }, { "Elites slain", st.elites }, { "Bosses slain", st.bosses },
		{ "Best kill streak", st.bestStreak }, { "Damage dealt", st.damage }, { "Biggest hit", st.bestHit },
		{ "Damage taken", st.taken }, { "Healing done", st.healing }, { "Abilities used", st.abilities },
		{ "Allies revived", st.revives }, { "Synergies", st.synergies }, { "Deaths", st.deaths },
	}
	local step = math.min(28, (cardsH - 50) / #rows)
	for i, r in ipairs(rows) do
		statRow(mine, 42 + (i - 1) * step, 18, 434, r[1], tonumber(r[2]) or 0, i)
	end

	-- REWARDS
	local rw = s.rewards or {}
	local rewards = card(panel, "REWARDS", { Position = UDim2.fromOffset(506, 108), Size = UDim2.fromOffset(470, cardsH) })
	local rrows = {
		{ "◆  Souls", rw.souls, `(+{rw.floorSouls or 0} floor bonus)` },
		{ "◆  Account XP", rw.xp, `(+{commas(rw.floorXP or 0)} floor bonus)` },
		{ "◆  Summon tickets", rw.tickets, nil },
		{ "◆  Gold collected", rw.gold, nil },
	}
	for i, r in ipairs(rrows) do
		local y = 42 + (i - 1) * 28
		label(rewards, r[1], 15, MUTED, { Position = UDim2.fromOffset(18, y), Size = UDim2.fromOffset(200, 22) })
		if r[3] then
			label(rewards, r[3], 12, MUTED, { Position = UDim2.fromOffset(170, y + 2), Size = UDim2.fromOffset(170, 20), TextTransparency = 0.3 })
		end
		local v = label(rewards, "", 17, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(18, y), Size = UDim2.fromOffset(434, 22),
			TextXAlignment = Enum.TextXAlignment.Right })
		countUp(v, tonumber(r[2]) or 0, function(n) return "+" .. commas(n) end, 0.3 + i * 0.08)
	end
	if typeof(s.level) == "number" then
		label(rewards, `Account level {s.level}`, 13, PARCH, { Position = UDim2.fromOffset(18, 42 + 4 * 28), Size = UDim2.fromOffset(434, 18),
			TextTransparency = 0.25 })
	end
	-- the loot found
	local lootTop = 42 + 4 * 28 + 30
	label(rewards, "LOOT", 13, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(18, lootTop), Size = UDim2.fromOffset(200, 18) })
	local loot = (rw.loot or {}) :: { any }
	local grid = Instance.new("ScrollingFrame")
	grid.Position = UDim2.fromOffset(14, lootTop + 22)
	grid.Size = UDim2.new(1, -28, 1, -(lootTop + 32))
	grid.BackgroundTransparency = 1
	grid.BorderSizePixel = 0
	grid.ScrollBarThickness = 4
	grid.AutomaticCanvasSize = Enum.AutomaticSize.Y
	grid.CanvasSize = UDim2.new()
	grid.Parent = rewards
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.fromOffset(104, 74)
	gl.CellPadding = UDim2.fromOffset(6, 6)
	gl.Parent = grid
	if #loot == 0 then
		label(grid, "Nothing this time. Go deeper: elites, bosses and every floor cleared drop gear.", 13, MUTED,
			{ Size = UDim2.fromOffset(420, 40), TextWrapped = true })
		gl:Destroy()
	end
	for i, item in ipairs(loot) do
		local col = RARITY[tostring(item.rarity)] or RARITY.Common
		local f = Instance.new("Frame")
		f.BackgroundColor3 = col:Lerp(DARK, 0.75)
		f.LayoutOrder = i
		f.Parent = grid
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = f
		local stroke = Instance.new("UIStroke")
		stroke.Color = col
		stroke.Thickness = 1.5
		stroke.Parent = f
		label(f, tostring(item.glyph or "◆"), 22, col, { Position = UDim2.fromOffset(0, 4), Size = UDim2.new(1, 0, 0, 28),
			TextXAlignment = Enum.TextXAlignment.Center })
		label(f, tostring(item.name or "?"), 11, PARCH, { FontFace = BOLD, Position = UDim2.fromOffset(4, 32), Size = UDim2.new(1, -8, 0, 26),
			TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
		local status = if item.lost then "LOST" elseif item.dupeSouls then `DUPE · +{item.dupeSouls} ◆`
			elseif item.isNew then "NEW!" elseif item.secured then "SECURED" else string.upper(tostring(item.rarity or ""))
		label(f, status, 9, if item.lost then RED elseif item.secured and not item.dupeSouls then Color3.fromRGB(120, 230, 140) else col,
			{ FontFace = BOLD, Position = UDim2.fromOffset(4, 58), Size = UDim2.new(1, -8, 0, 12), TextXAlignment = Enum.TextXAlignment.Center })
		if item.lost then
			f.BackgroundTransparency = 0.5
			stroke.Transparency = 0.5
			local x = label(f, "X", 40, RED, { Size = UDim2.fromScale(1, 1), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.35 })
			x.ZIndex = 3
		end
		-- (each card pops in, in turn)
		local scale = Instance.new("UIScale")
		scale.Scale = 0
		scale.Parent = f
		task.delay(0.9 + i * 0.12, function()
			TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end)
	end

	-- THE PARTY
	if hasParty then
		local pt = card(panel, "THE PARTY", { Position = UDim2.fromOffset(24, 108 + cardsH + 12), Size = UDim2.fromOffset(952, H - (108 + cardsH + 12) - 70) })
		local everyone = table.clone(partyRows)
		table.insert(everyone, {
			userId = player.UserId, name = player.DisplayName, classId = s.classId,
			kills = st.kills, damage = st.damage, healing = st.healing, taken = st.taken, revives = st.revives, you = true,
		})
		table.sort(everyone, function(a, b) return (a.damage or 0) > (b.damage or 0) end)
		local cols = { { "PLAYER", 18, 260 }, { "CLASS", 280, 160 }, { "KILLS", 450, 100 }, { "DAMAGE", 560, 120 }, { "HEALING", 690, 110 }, { "REVIVES", 810, 110 } }
		for _, col in ipairs(cols) do
			label(pt, col[1], 11, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(col[2], 32), Size = UDim2.fromOffset(col[3], 16), TextTransparency = 0.2 })
		end
		for i, r in ipairs(everyone) do
			if i > 4 then break end
			local y = 50 + (i - 1) * 22
			local c = ClassData.GetClass(r.classId)
			local color = if r.you then GOLD else PARCH
			local vals = { (if i == 1 then "★ " else "") .. tostring(r.name), if c then c.name else "", commas(r.kills or 0), commas(r.damage or 0),
				commas(r.healing or 0), commas(r.revives or 0) }
			for j, col in ipairs(cols) do
				label(pt, vals[j], 14, color, { FontFace = if r.you then BOLD else BODY, Position = UDim2.fromOffset(col[2], y), Size = UDim2.fromOffset(col[3], 20),
					TextTruncate = Enum.TextTruncate.AtEnd })
			end
		end
	end

	-- CONTINUE
	local btn = Instance.new("TextButton")
	btn.AnchorPoint = Vector2.new(0.5, 1)
	btn.Position = UDim2.new(0.5, 0, 1, -16)
	btn.Size = UDim2.fromOffset(240, 44)
	btn.BackgroundColor3 = Color3.fromRGB(70, 50, 26)
	btn.AutoButtonColor = false
	btn.FontFace = BOLD
	btn.TextSize = 18
	btn.TextColor3 = GOLD
	btn.Text = "CONTINUE"
	btn.Parent = panel
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 8)
	bc.Parent = btn
	local bs = Instance.new("UIStroke")
	bs.Color = GOLD
	bs.Transparency = 0.3
	bs.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	bs.Parent = btn
	btn.MouseEnter:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(100, 72, 36) }):Play() end)
	btn.MouseLeave:Connect(function() TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = Color3.fromRGB(70, 50, 26) }):Play() end)
	local ready = os.clock() + 1.2 -- (not skipped by a stray click)
	btn.MouseButton1Click:Connect(function()
		if os.clock() >= ready then close() end
	end)

	-- In: fade, then the numbers count up.
	TweenService:Create(root, TweenInfo.new(0.4, Enum.EasingStyle.Sine), { GroupTransparency = 0 }):Play()
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		if gui ~= g then
			if conn then conn:Disconnect() end
			return
		end
		fit()
		local t = os.clock() - t0
		local done = true
		for _, c in ipairs(counters) do
			local k = math.clamp((t - c.delay) / 1.1, 0, 1)
			k = 1 - (1 - k) ^ 3
			if k < 1 then done = false end
			c.l.Text = c.fmt(c.to * k)
		end
		if done and t > 2 and conn then conn:Disconnect() end
	end)
end

function RunSummary.Init()
	Network.GetRemoteEvent(Network.Remotes.RunSummary).OnClientEvent:Connect(function(s: any)
		if typeof(s) ~= "table" then return end
		local ok, err = pcall(show, s)
		if not ok then warn("[RunSummary]", err) end
	end)
end

-- (for testing)
RunSummary.Show = show

return RunSummary
