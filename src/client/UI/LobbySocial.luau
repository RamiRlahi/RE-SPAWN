--!strict
--[[
	LobbySocial.luau
	Meeting people on the lobby plaza (LobbyHUD runs it):
	  • E on another player opens their card: name, class and level, with
	    INVITE TO PARTY, SAY HELLO (said in chat, so it pops up in a bubble over
	    you for everyone) and WAVE.
	  • 1–5: emotes (wave, cheer, point, laugh, dance). Everyone sees them;
	    moving ends them.
	  • Chat bubbles over everyone's heads in the game's look, and the chat
	    window moved to the bottom left while you're on the plaza (the party
	    panel has the top left).

	LobbySocial.Init(hooks)      hooks.inParty(p), hooks.isLeader(p), hooks.invite(p)
	LobbySocial.OpenCard(p)      (from the player's E prompt)
	LobbySocial.CloseCard()
--]]

local Players = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local GearData = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("GearData"))

local LobbySocial = {}

local GOLD = Color3.fromRGB(232, 196, 120)
local PARCH = Color3.fromRGB(240, 226, 200)
local DARK = Color3.fromRGB(22, 17, 15)
local FONT = Enum.Font.Antique

type Hooks = {
	inParty: (Player) -> boolean,
	isLeader: (Player) -> boolean,
	invite: (Player) -> (),
}
local hooks: Hooks? = nil

local function onPlaza(): boolean
	return player:GetAttribute("InHub") == true
end

-- ── Emotes ────────────────────────────────────────────────────────────────
-- Roblox's own emote animations (any experience may play them), for R6 and
-- R15 rigs.
type Emote = { name: string, label: string, key: Enum.KeyCode, r6: number, r15: number, loop: boolean }
local EMOTES: { Emote } = {
	{ name = "wave", label = "Wave", key = Enum.KeyCode.One, r6 = 128777973, r15 = 507770239, loop = false },
	{ name = "cheer", label = "Cheer", key = Enum.KeyCode.Two, r6 = 129423030, r15 = 507770677, loop = false },
	{ name = "point", label = "Point", key = Enum.KeyCode.Three, r6 = 128853357, r15 = 507770453, loop = false },
	{ name = "laugh", label = "Laugh", key = Enum.KeyCode.Four, r6 = 129423131, r15 = 507770818, loop = false },
	{ name = "dance", label = "Dance", key = Enum.KeyCode.Five, r6 = 182435998, r15 = 507771019, loop = true },
}
local byName: { [string]: Emote } = {}
for _, e in ipairs(EMOTES) do byName[e.name] = e end

-- (one track per emote per animator: an animator only holds so many)
local loaded: { [string]: AnimationTrack } = {}
local loadedFor: Animator? = nil
local playing: AnimationTrack? = nil

local function stopEmote()
	local t = playing
	playing = nil
	if t then t:Stop(0.2) end
end

local function emote(name: string)
	local e = byName[name]
	if not e or not onPlaza() or player:GetAttribute("SettingsOpen") == true then return end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not hum or not animator or hum.Health <= 0 then return end
	if loadedFor ~= animator then
		table.clear(loaded)
		loadedFor = animator
	end
	local track = loaded[name]
	if not track then
		local a = Instance.new("Animation")
		a.AnimationId = "rbxassetid://" .. tostring(if hum.RigType == Enum.HumanoidRigType.R15 then e.r15 else e.r6)
		local ok, t = pcall(function() return animator:LoadAnimation(a) end)
		if not ok or not t then return end
		t.Priority = Enum.AnimationPriority.Action4 -- (over the walk / idle, which play at Action)
		t.Looped = e.loop
		loaded[name] = t
		track = t
	end
	stopEmote()
	local t = track :: AnimationTrack
	t:Play(0.15)
	playing = t
	t.Stopped:Once(function()
		if playing == t then playing = nil end
	end)
end

-- ── Speaking ──────────────────────────────────────────────────────────────
-- Said in the general chat: everyone reads it, in the window and in a bubble
-- over you.
local function say(text: string)
	task.spawn(function()
		local channels = TextChatService:FindFirstChild("TextChannels")
		local general = channels and channels:FindFirstChild("RBXGeneral")
		if general and general:IsA("TextChannel") then
			pcall(function() general:SendAsync(text) end)
		end
	end)
end

-- ── The player card ───────────────────────────────────────────────────────
local cardGui: ScreenGui? = nil
local cardFor: Player? = nil
local inviteBtn: TextButton? = nil
local nameLabel: TextLabel? = nil
local userLabel: TextLabel? = nil
local classLabel: TextLabel? = nil
local partyLabel: TextLabel? = nil
local headshot: ImageLabel? = nil
local gearLabel: TextLabel? = nil
local CARD_RANGE = 22 -- walk further off and it closes

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextStrokeTransparency = 0.6
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function button(parent: Instance, text: string, order: number, color: Color3, onClick: () -> ()): TextButton
	local b = Instance.new("TextButton")
	b.LayoutOrder = order
	b.Size = UDim2.new(1, 0, 0, 34)
	b.AutoButtonColor = false
	b.BackgroundColor3 = color
	b.BackgroundTransparency = 0.25
	b.Font = FONT
	b.TextSize = 18
	b.TextColor3 = PARCH
	b.Text = text
	b.Parent = parent
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 6)
	c.Parent = b
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Transparency = 0.7
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.1), { BackgroundTransparency = 0.05 }):Play()
		TweenService:Create(st, TweenInfo.new(0.1), { Transparency = 0.2 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.1), { BackgroundTransparency = 0.25 }):Play()
		TweenService:Create(st, TweenInfo.new(0.1), { Transparency = 0.7 }):Play()
	end)
	b.MouseButton1Click:Connect(onClick)
	return b
end

function LobbySocial.CloseCard()
	cardFor = nil
	if cardGui then cardGui.Enabled = false end
end

local function buildCard()
	local g = Instance.new("ScreenGui")
	g.Name = "PlayerCard"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 55
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	cardGui = g

	local card = Instance.new("Frame")
	card.Name = "Card"
	card.AnchorPoint = Vector2.new(0.5, 0.5)
	card.Position = UDim2.fromScale(0.5, 0.55)
	card.Size = UDim2.fromOffset(340, 0)
	card.AutomaticSize = Enum.AutomaticSize.Y
	card.BackgroundColor3 = DARK
	card.BackgroundTransparency = 0.1
	card.Parent = g
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 10)
	cc.Parent = card
	local cs = Instance.new("UIStroke")
	cs.Color = GOLD
	cs.Transparency = 0.35
	cs.Thickness = 1.5
	cs.Parent = card
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 14), UDim.new(0, 14)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	pad.Parent = card
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 8)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = card

	-- who: their headshot, names, class and level
	local head = Instance.new("Frame")
	head.LayoutOrder = 0
	head.Size = UDim2.new(1, 0, 0, 84)
	head.BackgroundTransparency = 1
	head.Parent = card
	local img = Instance.new("ImageLabel")
	img.Size = UDim2.fromOffset(84, 84)
	img.BackgroundColor3 = Color3.fromRGB(46, 36, 32)
	img.Image = ""
	img.Parent = head
	local ic = Instance.new("UICorner")
	ic.CornerRadius = UDim.new(0, 8)
	ic.Parent = img
	local is = Instance.new("UIStroke")
	is.Color = GOLD
	is.Transparency = 0.5
	is.Parent = img
	headshot = img
	nameLabel = label(head, "", 24, GOLD, { Position = UDim2.fromOffset(98, 2), Size = UDim2.new(1, -98, 0, 28), TextTruncate = Enum.TextTruncate.AtEnd })
	userLabel = label(head, "", 14, PARCH, { Position = UDim2.fromOffset(98, 30), Size = UDim2.new(1, -98, 0, 18), TextTransparency = 0.35 })
	classLabel = label(head, "", 17, PARCH, { Position = UDim2.fromOffset(98, 50), Size = UDim2.new(1, -98, 0, 20) })
	partyLabel = label(head, "", 14, GOLD, { Position = UDim2.fromOffset(98, 68), Size = UDim2.new(1, -98, 0, 16), TextTransparency = 0.2 })

	-- what they wear (the Armory): title, weapon finish, aura
	gearLabel = label(card, "", 14, PARCH, { LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		TextWrapped = true, RichText = true })
	inviteBtn = button(card, "INVITE TO PARTY", 2, Color3.fromRGB(70, 52, 30), function()
		local p = cardFor
		if p and hooks then hooks.invite(p) end
		LobbySocial.CloseCard()
	end)
	button(card, "SAY HELLO", 3, Color3.fromRGB(44, 52, 70), function()
		local p = cardFor
		if p then
			say(`Hello, {p.DisplayName}!`)
			emote("wave")
		end
		LobbySocial.CloseCard()
	end)
	button(card, "WAVE", 4, Color3.fromRGB(44, 52, 70), function()
		emote("wave")
		LobbySocial.CloseCard()
	end)
	button(card, "CLOSE", 5, Color3.fromRGB(60, 30, 28), LobbySocial.CloseCard)
end

function LobbySocial.OpenCard(p: Player)
	if not onPlaza() or p == player then return end
	-- (E on the same player again: put it away)
	if cardFor == p and cardGui and cardGui.Enabled then
		LobbySocial.CloseCard()
		return
	end
	if not cardGui then buildCard() end
	cardFor = p
	local h = hooks
	local partied = h ~= nil and h.inParty(p)
	if nameLabel then nameLabel.Text = p.DisplayName end
	if userLabel then userLabel.Text = "@" .. p.Name end
	if classLabel then
		local class = p:GetAttribute("ClassName")
		local lvl = p:GetAttribute("AccountLevel")
		local bits = {}
		if typeof(class) == "string" then table.insert(bits, class) end
		if typeof(lvl) == "number" then table.insert(bits, `Level {lvl}`) end
		classLabel.Text = table.concat(bits, "  ·  ")
	end
	if partyLabel then
		partyLabel.Text = if partied and h and h.isLeader(p) then "★ Your party's leader"
			elseif partied then "In your party"
			else ""
	end
	if inviteBtn then inviteBtn.Visible = not partied end
	if gearLabel then
		local bits = {}
		for _, slot in ipairs({ "title", "weapon", "aura" }) do
			local item = GearData.Get(p:GetAttribute(`Gear_{slot}`))
			if item then
				local col = (GearData.RARITY_COLOR[item.rarity] or Color3.new(1, 1, 1)):ToHex()
				local what = if slot == "title" then `« {item.title} »` elseif slot == "weapon" then `{item.name} weapon finish` else `{item.name} aura`
				table.insert(bits, string.format('<font color="#%s">%s</font>', col, what))
			end
		end
		gearLabel.Text = if #bits > 0 then table.concat(bits, "   ·   ") else "No gear worn yet."
	end
	if headshot then
		local img = headshot
		img.Image = ""
		task.spawn(function()
			local ok, url = pcall(function()
				return Players:GetUserThumbnailAsync(p.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
			end)
			if ok and cardFor == p then img.Image = url end
		end)
	end
	local g = cardGui :: ScreenGui
	g.Enabled = true
end

-- ── Chat: the bubbles and the window ──────────────────────────────────────
local function styleBubbles()
	local bubble = TextChatService:FindFirstChildOfClass("BubbleChatConfiguration")
	if not bubble then return end
	bubble.Enabled = true
	bubble.BackgroundColor3 = Color3.fromRGB(28, 22, 20)
	bubble.BackgroundTransparency = 0.1
	bubble.TextColor3 = PARCH
	bubble.TextSize = 18
	bubble.TailVisible = true
	bubble.BubbleDuration = 12
	bubble.MaxBubbles = 3
	bubble.MaxDistance = 120
	bubble.MinimizeDistance = 60
	bubble.VerticalStudsOffset = 1.5 -- (over hats, horns and hoods)
	if not bubble:FindFirstChildOfClass("UICorner") then
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 10)
		c.Parent = bubble
	end
	if not bubble:FindFirstChildOfClass("UIPadding") then
		local p = Instance.new("UIPadding")
		p.PaddingLeft, p.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
		p.PaddingTop, p.PaddingBottom = UDim.new(0, 6), UDim.new(0, 6)
		p.Parent = bubble
	end
end

-- The chat window: bottom left on the plaza, back where it was elsewhere.
local savedWindow: { h: Enum.HorizontalAlignment, v: Enum.VerticalAlignment }? = nil
local function placeChatWindow(here: boolean)
	local w = TextChatService:FindFirstChildOfClass("ChatWindowConfiguration")
	if not w then return end
	if here then
		if not savedWindow then savedWindow = { h = w.HorizontalAlignment, v = w.VerticalAlignment } end
		w.HorizontalAlignment = Enum.HorizontalAlignment.Left
		w.VerticalAlignment = Enum.VerticalAlignment.Bottom
	elseif savedWindow then
		w.HorizontalAlignment = savedWindow.h
		w.VerticalAlignment = savedWindow.v
		savedWindow = nil
	end
end

-- (The chat bar opens with /, Roblox's own key: it can't be moved to Enter,
-- Roblox's chat won't draw that key, and nothing else can open the bar.)

function LobbySocial.Init(h: Hooks)
	hooks = h
	pcall(styleBubbles)
	local function sync()
		local here = onPlaza()
		pcall(placeChatWindow, here)
		if not here then
			LobbySocial.CloseCard()
			stopEmote()
		end
	end
	player:GetAttributeChangedSignal("InHub"):Connect(sync)
	sync()

	-- 1–5: emotes (not while typing: the chat bar takes the keys then)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or UserInputService:GetFocusedTextBox() or not onPlaza() then return end
		for _, e in ipairs(EMOTES) do
			if input.KeyCode == e.key then
				emote(e.name)
				return
			end
		end
	end)

	-- Moving ends an emote; the card closes when its player walks off (or
	-- you do).
	local acc = 0
	RunService.Heartbeat:Connect(function(dt)
		local t = playing
		if t then
			local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
			if not hum or hum.MoveDirection.Magnitude > 0.1 or hum.FloorMaterial == Enum.Material.Air then stopEmote() end
		end
		acc += dt
		if acc < 0.25 then return end
		acc = 0
		local p = cardFor
		if p then
			local a = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			local b = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not p.Parent or p:GetAttribute("InHub") ~= true or not a or not b or (a.Position - b.Position).Magnitude > CARD_RANGE then
				LobbySocial.CloseCard()
			end
		end
	end)
	player.CharacterAdded:Connect(function()
		stopEmote()
		table.clear(loaded)
		loadedFor = nil
	end)
end

return LobbySocial
