--!strict
--[[
	GuildScreen.luau
	Guilds (server: GuildManager, rules: GuildData), from the lobby's GUILD
	button.

	  MY GUILD     not in one: found a guild (souls), ask to join one by name,
	               your pending request, guilds that invited you.
	               in one: its name, your role, this season's points and when
	               it ends, last season's finish; the members by points (online
	               marked), with promote / demote (leader) and remove (leader,
	               officers); join requests to accept or decline; invite a
	               player in this server; leave.
	  LEADERBOARD  this season's top 10 guilds, and what each rank pays.

	Toasts for guild news (GuildUpdate): points from a run, an invite,
	joined, removed, a season's rewards.

	GuildScreen.Init()   GuildScreen.Open()   GuildScreen.Close()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GuildData = require(Shared:WaitForChild("GuildData"))

local player = Players.LocalPlayer

local GuildScreen = {}

local GOLD = Color3.fromRGB(240, 196, 110)
local PARCH = Color3.fromRGB(238, 226, 204)
local MUTED = Color3.fromRGB(140, 130, 118)
local DARK = Color3.fromRGB(16, 12, 14)
local CARD = Color3.fromRGB(30, 24, 26)
local GREEN = Color3.fromRGB(70, 150, 80)
local RED = Color3.fromRGB(150, 50, 46)
local BODY = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

local gui: ScreenGui? = nil
local content: ScrollingFrame? = nil
local status: TextLabel? = nil
local tabButtons: { [string]: TextButton } = {}
local tab = "guild"
local state: any = nil
local busy = false

-- ── Little builders ─────────────────────────────────────────────────────────
local function corner(p: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = p
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

local function button(parent: Instance, text: string, color: Color3, size: UDim2, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.AutoButtonColor = true
	b.BackgroundColor3 = color
	b.FontFace = BOLD
	b.Text = text
	b.TextSize = 13
	b.TextColor3 = PARCH
	b.Size = size
	b.Parent = parent
	corner(b, 6)
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Transparency = 0.55
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = b
	b.MouseButton1Click:Connect(onClick)
	return b
end

local function box(parent: Instance, placeholder: string, size: UDim2, maxLen: number): TextBox
	local t = Instance.new("TextBox")
	t.BackgroundColor3 = CARD
	t.FontFace = BODY
	t.PlaceholderText = placeholder
	t.PlaceholderColor3 = MUTED
	t.Text = ""
	t.TextSize = 14
	t.TextColor3 = PARCH
	t.ClearTextOnFocus = false
	t.Size = size
	t.Parent = parent
	corner(t, 6)
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Transparency = 0.7
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = t
	t:GetPropertyChangedSignal("Text"):Connect(function()
		if #t.Text > maxLen then t.Text = string.sub(t.Text, 1, maxLen) end
	end)
	return t
end

-- A row / card in the scrolling content.
local order = 0
local function section(height: number): Frame
	order += 1
	local f = Instance.new("Frame")
	f.BackgroundColor3 = CARD
	f.Size = UDim2.new(1, -12, 0, height)
	f.LayoutOrder = order
	f.Parent = content
	corner(f, 8)
	return f
end

local function heading(text: string)
	order += 1
	label(content :: any, text, 15, GOLD, { FontFace = BOLD, Size = UDim2.new(1, -12, 0, 26), LayoutOrder = order })
end

local function setStatus(text: string, bad: boolean?)
	if status then
		status.Text = text
		status.TextColor3 = if bad then Color3.fromRGB(240, 120, 110) else GOLD
	end
end

local function timeLeft(ends: number): string
	local s = math.max(0, ends - os.time())
	local d, h = math.floor(s / 86400), math.floor((s % 86400) / 3600)
	if d > 0 then return `{d}d {h}h` end
	return `{h}h {math.floor((s % 3600) / 60)}m`
end

local function classLabel(c: any): string
	if typeof(c) ~= "string" then return "" end
	return (string.gsub(c, "_", " "))
end

-- ── Talking to the server ───────────────────────────────────────────────────
local render: () -> ()

local function call(op: string, args: { [string]: any }?)
	if busy then return end
	busy = true
	setStatus("…")
	task.spawn(function()
		local msg = args or {}
		msg.op = op
		local ok, r = pcall(function()
			return Network.GetRemoteFunction(Network.Functions.GuildAction):InvokeServer(msg)
		end)
		busy = false
		if not ok or typeof(r) ~= "table" then
			setStatus("Couldn't reach the server.", true)
			return
		end
		if not r.ok then
			setStatus(r.error or "Something went wrong.", true)
			return
		end
		setStatus("")
		if op == "top" then
			state = state or {}
			state.top, state.seasonEnds = r.top, r.seasonEnds
		else
			local top = state and state.top
			state = r
			state.top = top
		end
		render()
	end)
end

-- ── The tabs ────────────────────────────────────────────────────────────────
local function renderNoGuild()
	local s = state
	-- found a guild
	heading("FOUND A GUILD")
	local f = section(96)
	label(f, `Costs {s.cost} souls (you have {s.souls}). Up to {GuildData.MAX_MEMBERS} members.`, 13, PARCH,
		{ Position = UDim2.fromOffset(14, 8), Size = UDim2.new(1, -28, 0, 18) })
	local name = box(f, "Guild name (3–20)", UDim2.fromOffset(300, 34), GuildData.NAME_MAX)
	name.Position = UDim2.fromOffset(14, 40)
	local tag = box(f, "TAG", UDim2.fromOffset(80, 34), GuildData.TAG_MAX)
	tag.Position = UDim2.fromOffset(324, 40)
	local create = button(f, "FOUND", GREEN, UDim2.fromOffset(120, 34), function()
		call("create", { name = name.Text, tag = tag.Text })
	end)
	create.Position = UDim2.fromOffset(414, 40)
	-- join one
	heading("JOIN A GUILD")
	local j = section(if s.pending then 96 else 60)
	local jname = box(j, "Guild name", UDim2.fromOffset(300, 34), GuildData.NAME_MAX)
	jname.Position = UDim2.fromOffset(14, 13)
	local ask = button(j, "ASK TO JOIN", Color3.fromRGB(70, 56, 30), UDim2.fromOffset(140, 34), function()
		call("request", { name = jname.Text })
	end)
	ask.Position = UDim2.fromOffset(324, 13)
	if s.pending then
		label(j, "Your request is waiting for the guild's leader or an officer.", 13, MUTED,
			{ Position = UDim2.fromOffset(14, 58), Size = UDim2.new(1, -170, 0, 26) })
		local cancel = button(j, "CANCEL", RED, UDim2.fromOffset(100, 28), function() call("cancelRequest") end)
		cancel.Position = UDim2.new(1, -114, 0, 58)
	end
	-- invites
	if #(s.invites or {}) > 0 then
		heading("INVITATIONS")
		for _, inv in ipairs(s.invites) do
			local r = section(48)
			label(r, `{inv.name}  [{inv.tag}]`, 15, PARCH, { FontFace = BOLD, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, 0, 1, 0) })
			label(r, `{inv.members}/{GuildData.MAX_MEMBERS} members`, 12, MUTED, { Position = UDim2.new(0.5, 0, 0, 0), Size = UDim2.new(0, 140, 1, 0) })
			local a = button(r, "ACCEPT", GREEN, UDim2.fromOffset(90, 30), function() call("acceptInvite", { guildId = inv.id }) end)
			a.Position = UDim2.new(1, -200, 0, 9)
			local d = button(r, "DECLINE", RED, UDim2.fromOffset(90, 30), function() call("declineInvite", { guildId = inv.id }) end)
			d.Position = UDim2.new(1, -104, 0, 9)
		end
	end
end

local function renderGuild()
	local g = state.guild
	local staff = g.role == "leader" or g.role == "officer"
	-- the header
	local h = section(84)
	label(h, `{g.name}  [{g.tag}]`, 24, GOLD, { Font = Enum.Font.Antique, Position = UDim2.fromOffset(14, 6), Size = UDim2.new(1, -28, 0, 32) })
	label(h, `You: {string.upper(g.role or "")}   ·   {#g.members}/{g.maxMembers} members   ·   {g.total} points this season   ·   season ends in {timeLeft(g.seasonEnds)}`,
		13, PARCH, { Position = UDim2.fromOffset(14, 40), Size = UDim2.new(1, -28, 0, 18) })
	if g.lastSeason then
		label(h, `Last season: {g.lastSeason.total} points`, 12, MUTED, { Position = UDim2.fromOffset(14, 60), Size = UDim2.new(1, -28, 0, 16) })
	end
	-- requests
	if staff and #g.requests > 0 then
		heading("ASKING TO JOIN")
		for _, rq in ipairs(g.requests) do
			local r = section(44)
			label(r, rq.name, 15, PARCH, { FontFace = BOLD, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0.5, 0, 1, 0) })
			local a = button(r, "ACCEPT", GREEN, UDim2.fromOffset(90, 28), function() call("accept", { userId = rq.userId }) end)
			a.Position = UDim2.new(1, -200, 0, 8)
			local d = button(r, "DECLINE", RED, UDim2.fromOffset(90, 28), function() call("decline", { userId = rq.userId }) end)
			d.Position = UDim2.new(1, -104, 0, 8)
		end
	end
	-- members
	heading("MEMBERS (by points this season)")
	for i, m in ipairs(g.members) do
		local r = section(44)
		local dot = Instance.new("Frame")
		dot.Size = UDim2.fromOffset(8, 8)
		dot.Position = UDim2.fromOffset(12, 18)
		dot.BackgroundColor3 = if m.online then Color3.fromRGB(90, 220, 110) else Color3.fromRGB(80, 74, 70)
		dot.Parent = r
		corner(dot, 4)
		label(r, `{i}. {m.name}`, 15, PARCH, { FontFace = BOLD, Position = UDim2.fromOffset(28, 0), Size = UDim2.new(0, 210, 1, 0), TextTruncate = Enum.TextTruncate.AtEnd })
		label(r, string.upper(m.role) .. (if m.class then "  ·  " .. classLabel(m.class) else ""), 12,
			if m.role == "leader" then GOLD elseif m.role == "officer" then Color3.fromRGB(190, 170, 240) else MUTED,
			{ Position = UDim2.fromOffset(244, 0), Size = UDim2.new(0, 190, 1, 0) })
		label(r, `{m.points} pts`, 14, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(436, 0), Size = UDim2.new(0, 90, 1, 0) })
		local me = m.userId == player.UserId
		local x = -8
		if staff and not me and m.role ~= "leader" and (g.role == "leader" or m.role == "member") then
			x -= 84
			local k = button(r, "REMOVE", RED, UDim2.fromOffset(80, 26), function() call("kick", { userId = m.userId }) end)
			k.Position = UDim2.new(1, x, 0, 9)
		end
		if g.role == "leader" and not me then
			x -= 96
			local promote = m.role == "member"
			local pb = button(r, if promote then "PROMOTE" else "DEMOTE", Color3.fromRGB(70, 56, 100), UDim2.fromOffset(92, 26), function()
				call(if promote then "promote" else "demote", { userId = m.userId })
			end)
			pb.Position = UDim2.new(1, x, 0, 9)
		end
	end
	-- invite / leave
	heading("")
	local f = section(56)
	if staff then
		local who = box(f, "Player name (in this server)", UDim2.fromOffset(260, 34), 30)
		who.Position = UDim2.fromOffset(14, 11)
		local inv = button(f, "INVITE", Color3.fromRGB(70, 56, 30), UDim2.fromOffset(100, 34), function()
			call("invite", { name = who.Text })
		end)
		inv.Position = UDim2.fromOffset(284, 11)
	end
	local leave = button(f, "LEAVE GUILD", RED, UDim2.fromOffset(130, 34), function() call("leave") end)
	leave.Position = UDim2.new(1, -144, 0, 11)
end

local function renderTop()
	local s = state
	heading(`THIS SEASON  ·  ends in {if s and s.seasonEnds then timeLeft(s.seasonEnds) else "…"}`)
	if not s or not s.top then
		label(content :: any, "Loading…", 14, MUTED, { Size = UDim2.new(1, -12, 0, 30) })
		return
	end
	if #s.top == 0 then
		local r = section(44)
		label(r, "No guild has scored this season yet. Clear floors to put yours on the board.", 14, MUTED,
			{ Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -28, 1, 0) })
	end
	for _, e in ipairs(s.top) do
		local r = section(44)
		local medal = ({ Color3.fromRGB(255, 210, 90), Color3.fromRGB(205, 210, 220), Color3.fromRGB(205, 130, 70) })[e.rank]
		label(r, `#{e.rank}`, 18, medal or PARCH, { FontFace = BOLD, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 50, 1, 0) })
		label(r, `{e.name}  [{e.tag}]`, 15, PARCH, { FontFace = BOLD, Position = UDim2.fromOffset(64, 0), Size = UDim2.new(0, 300, 1, 0) })
		label(r, `{e.members} members`, 12, MUTED, { Position = UDim2.fromOffset(370, 0), Size = UDim2.new(0, 110, 1, 0) })
		label(r, `{e.points} pts`, 15, GOLD, { FontFace = BOLD, Position = UDim2.new(1, -110, 0, 0), Size = UDim2.new(0, 100, 1, 0) })
	end
	heading("SEASON REWARDS (every member)")
	local prev = 0
	for _, r in ipairs(GuildData.Rewards) do
		local row = section(36)
		local range = if r.upTo == 1 then "#1" elseif prev + 1 == r.upTo then `#{r.upTo}` else `#{prev + 1}–{r.upTo}`
		local extras = {}
		if r.title then table.insert(extras, "title") end
		if r.buff then table.insert(extras, `+{math.floor(r.buff * 100)}% run souls & XP next season`) end
		label(row, range, 14, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(14, 0), Size = UDim2.new(0, 90, 1, 0) })
		label(row, `{r.souls} souls  ·  {r.tickets} tickets` .. (if #extras > 0 then "  ·  " .. table.concat(extras, "  ·  ") else ""),
			13, PARCH, { Position = UDim2.fromOffset(110, 0), Size = UDim2.new(1, -120, 1, 0) })
		prev = r.upTo
	end
	label(content :: any, "The top 3 guilds' best players stand on the podium in every lobby.", 12, MUTED,
		{ Size = UDim2.new(1, -12, 0, 24), LayoutOrder = 999 })
end

render = function()
	local c = content
	if not c then return end
	for _, ch in ipairs(c:GetChildren()) do
		if not ch:IsA("UIListLayout") and not ch:IsA("UIPadding") then ch:Destroy() end
	end
	order = 0
	for id, b in pairs(tabButtons) do
		b.BackgroundColor3 = if id == tab then Color3.fromRGB(86, 64, 30) else CARD
	end
	if tab == "top" then
		renderTop()
	elseif not state then
		label(c, "Loading…", 14, MUTED, { Size = UDim2.new(1, -12, 0, 30) })
	elseif state.guild then
		renderGuild()
	else
		renderNoGuild()
	end
end

-- ── The window ──────────────────────────────────────────────────────────────
local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "GuildScreen"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 60
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = g
	dim.MouseButton1Click:Connect(GuildScreen.Close)
	local W, H = 760, 580
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W, H)
	panel.BackgroundColor3 = DARK
	panel.Parent = g
	corner(panel, 12)
	local ps = Instance.new("UIStroke")
	ps.Color = GOLD
	ps.Transparency = 0.35
	ps.Parent = panel
	local sc = Instance.new("UIScale")
	sc.Parent = panel
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	sc.Scale = math.min(1, (vp.X - 40) / W, (vp.Y - 40) / H)
	label(panel, "GUILDS", 34, GOLD, { Font = Enum.Font.Antique, Position = UDim2.fromOffset(0, 14), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	label(panel, "Clear dungeons together to climb the weekly rankings.", 14, PARCH,
		{ Position = UDim2.fromOffset(0, 54), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.15 })
	for i, t in ipairs({ { id = "guild", name = "MY GUILD" }, { id = "top", name = "LEADERBOARD" } }) do
		local b = button(panel, t.name, CARD, UDim2.fromOffset(170, 32), function()
			tab = t.id
			render()
			if t.id == "top" then call("top") else call("info") end
		end)
		b.Position = UDim2.new(0.5, (i - 1.5) * 180 - 85, 0, 84)
		tabButtons[t.id] = b
	end
	status = label(panel, "", 13, GOLD, { Position = UDim2.fromOffset(20, 122), Size = UDim2.new(1, -40, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(20, 146)
	list.Size = UDim2.new(1, -40, 1, -166)
	list.ScrollBarThickness = 6
	list.ScrollBarImageColor3 = GOLD
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	content = list
	local close = button(panel, "X", RED, UDim2.fromOffset(32, 32), GuildScreen.Close)
	close.Position = UDim2.new(1, -44, 0, 12)
end

function GuildScreen.Open()
	if not gui then build() end
	(gui :: ScreenGui).Enabled = true
	render()
	call(if tab == "top" then "top" else "info")
end

function GuildScreen.Close()
	if gui then gui.Enabled = false end
end

-- ── Toasts ──────────────────────────────────────────────────────────────────
local toastGui: ScreenGui? = nil
local function toast(text: string)
	if not toastGui then
		local g = Instance.new("ScreenGui")
		g.Name = "GuildToasts"
		g.ResetOnSpawn = false
		g.DisplayOrder = 70
		g.Parent = player:WaitForChild("PlayerGui")
		toastGui = g
	end
	local f = Instance.new("TextLabel")
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, -60)
	f.Size = UDim2.fromOffset(460, 44)
	f.BackgroundColor3 = DARK
	f.FontFace = BOLD
	f.TextSize = 15
	f.TextColor3 = GOLD
	f.TextWrapped = true
	f.Text = text
	f.Parent = toastGui
	corner(f, 8)
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Transparency = 0.3
	s.Parent = f
	TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, 70) }):Play()
	task.delay(4, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.3), { Position = UDim2.new(0.5, 0, 0, -60) }):Play()
		end
	end)
	Debris:AddItem(f, 4.5)
end

function GuildScreen.Init()
	Network.GetRemoteEvent(Network.Remotes.GuildUpdate).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		if msg.kind == "points" then
			toast(`+{msg.points} guild points  ·  your guild has {msg.total} this season`)
		elseif msg.kind == "invited" then
			toast(`{msg.from} invited you to {msg.name or "their guild"}. Open GUILD to answer.`)
		elseif msg.kind == "joined" then
			toast(`You joined {msg.name}!`)
		elseif msg.kind == "kicked" then
			toast("You were removed from your guild.")
		elseif msg.kind == "reward" then
			toast(`Your guild finished #{msg.rank} last season: {msg.souls} souls and {msg.tickets} tickets!`)
		end
		if gui and gui.Enabled then call("info") end
	end)
end

return GuildScreen
