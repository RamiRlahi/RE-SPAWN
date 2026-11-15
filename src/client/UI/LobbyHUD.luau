--!strict
--[[
	LobbyHUD.luau
	What's on screen while you walk the lobby (LobbyManager): your party (with
	the leader marked and a LEAVE PARTY button), how it works, notices (e.g.
	only the leader picks the map), and an "Interact" prompt over every other
	player in the lobby (walk up and press E: their card, to invite them, say
	hello or wave: LobbySocial, which also has the emotes and chat bubbles).

	All of it sits in a dock at the bottom right: the character features
	(Party, Armory, Wardrobe, Skill Tree, Build Codex) as tiles of their own,
	then three categories that open a small panel each: Social (Guild,
	Invite Friends), Market (Summon Shop, Mounts Shop), Extras (Community
	Rewards, Controls). Each tile shows its name on hover.

	It also drives the menus for the lobby's states: LobbyState "hub" → the
	plaza (UIManager.EnterHub), "campfire" → the ready-up (UIManager.
	ShowCampfireFromHub).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local SocialService = game:GetService("SocialService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClickOutside = require(script.Parent:WaitForChild("ClickOutside"))
local MapData = require(Shared:WaitForChild("MapData"))

local player = Players.LocalPlayer
local MenuBackdrop: any = nil
pcall(function() MenuBackdrop = require(script.Parent.Parent:WaitForChild("MenuBackdrop")) end)
local SummonScreen: any = nil
pcall(function() SummonScreen = require(script.Parent:WaitForChild("SummonScreen")) end)
local LobbySocial = require(script.Parent:WaitForChild("LobbySocial"))
local BuildCodex = require(script.Parent:WaitForChild("BuildCodex"))
local Armory = require(script.Parent:WaitForChild("Armory"))
local WardrobeScreen = require(script.Parent:WaitForChild("WardrobeScreen"))
local GuildScreen = require(script.Parent:WaitForChild("GuildScreen"))
local TalentScreen = require(script.Parent:WaitForChild("TalentScreen"))
local StoreScreen = require(script.Parent:WaitForChild("StoreScreen"))
local Icons = require(script.Parent:WaitForChild("Icons"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))

local LobbyHUD = {}

local GOLD = Color3.fromRGB(232, 196, 120)
local PARCH = Color3.fromRGB(240, 226, 200)
local DARK = Color3.fromRGB(22, 17, 15)
local FONT = Enum.Font.Antique

local gui: ScreenGui? = nil
local list: Frame? = nil
local noticeLabel: TextLabel? = nil
local leaveBtn: TextButton? = nil
local inviteFriendsBtn: TextButton? = nil
local party: { leader: number?, members: { any } } = { leader = nil, members = {} }

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextStrokeTransparency = 0.5
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

-- ── The dock (bottom right) ──
-- RE's navigation: one dark, gold-trimmed plate. The character features
-- (Party, Armory, Wardrobe, Talents, Codex) sit on it all the time; after a
-- separator, Social, Market and Extras are category tiles that open a small
-- panel above themselves with their features. Every feature has its own
-- colour: a lit gradient tile with a dark outline and a darker lip under it
-- (tactile, like a key), a gloss on top, a white icon with a shadow. Hover
-- lifts and brightens a tile, a press pushes it in, and the tile of
-- whatever is open wears a gold ring. Party / Controls / Rewards still open
-- their small cards above the dock. The whole dock scales with the screen.
local DOCK_BG = Color3.fromRGB(20, 16, 18)
local TRIM = Color3.fromRGB(214, 170, 96)     -- (the gold trim: RE's frame colour)
local INK = Color3.fromRGB(12, 8, 10)         -- (outlines and shadows)
local DOCK_FONT = Enum.Font.GothamMedium
local DOCK_BOLD = Enum.Font.GothamBold
local DOCK_BLACK = Enum.Font.GothamBlack
local TILE = 56
-- Each feature's colours (top -> bottom of its tile).
local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end
local HUES: { [string]: { Color3 } } = {
	party = { rgb(255, 222, 110), rgb(206, 128, 18) },     -- warm gold
	armory = { rgb(255, 112, 84), rgb(158, 20, 28) },      -- aggressive red, warm metal
	wardrobe = { rgb(206, 132, 255), rgb(104, 36, 196) },  -- vibrant purple
	talents = { rgb(96, 236, 150), rgb(10, 132, 78) },     -- emerald
	codex = { rgb(104, 220, 255), rgb(28, 96, 214) },      -- blue / cyan
	social = { rgb(255, 204, 96), rgb(196, 28, 52) },      -- gold into crimson
	guild = { rgb(255, 204, 96), rgb(196, 28, 52) },
	invite = { rgb(120, 236, 140), rgb(24, 150, 76) },
	market = { rgb(186, 104, 255), rgb(36, 186, 226) },    -- vivid purple into cyan
	summon = { rgb(198, 100, 255), rgb(96, 28, 196) },
	mounts = { rgb(96, 226, 246), rgb(20, 116, 204) },
	extras = { rgb(255, 234, 120), rgb(226, 146, 20) },    -- bright gold
	rewards = { rgb(255, 234, 120), rgb(226, 146, 20) },
	help = { rgb(140, 184, 255), rgb(52, 92, 196) },       -- neutral blue
}
local partyTip: (() -> string)? = nil
local partyBadge: ((number) -> ())? = nil

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "LobbyHUD"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 30
	g.Enabled = false
	g:SetAttribute("KeepFont", true) -- (plain Roblox fonts here, not the Arcade one)
	-- (clickable UI stays inside the core UI safe area on phones: clear of
	-- the top bar and screen cutouts)
	g.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g

	local function corner(inst: Instance, r: number)
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, r)
		c.Parent = inst
	end
	local function stroke(inst: Instance, color: Color3, thick: number, tr: number?): UIStroke
		local s = Instance.new("UIStroke")
		s.Color, s.Thickness, s.Transparency = color, thick, tr or 0
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = inst
		return s
	end
	local function grad(inst: Instance, top: Color3, bottom: Color3, rot: number?): UIGradient
		local gr = Instance.new("UIGradient")
		gr.Color = ColorSequence.new(top, bottom)
		gr.Rotation = rot or 90
		gr.Parent = inst
		return gr
	end
	local function frame(parent: Instance, props: { [string]: any }): Frame
		local f = Instance.new("Frame")
		f.BorderSizePixel = 0
		for k, v in pairs(props) do (f :: any)[k] = v end
		f.Parent = parent
		return f
	end
	local function tween(inst: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?)
		TweenService:Create(inst, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.Out), props):Play()
	end

	-- (on a phone the jump button has the corner: the dock sits above it)
	local touch = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
	local bottom = if touch then -150 else -14
	local dock = frame(g, { Name = "Dock", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, bottom),
		Size = UDim2.fromOffset(0, 0), AutomaticSize = Enum.AutomaticSize.XY, BackgroundColor3 = DOCK_BG, BackgroundTransparency = 0.08 })
	-- (FontStyle reads KeepFont on frames, not on the ScreenGui itself: set it on
	-- each top-level piece before any text goes in, or it turns Arcade)
	dock:SetAttribute("KeepFont", true)
	corner(dock, 16)
	stroke(dock, TRIM, 1.5, 0.2)
	grad(dock, Color3.fromRGB(255, 255, 255), Color3.fromRGB(150, 140, 150))
	do
		local pad = Instance.new("UIPadding")
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 6)
		pad.Parent = dock
		local row = Instance.new("UIListLayout")
		row.FillDirection = Enum.FillDirection.Horizontal
		row.VerticalAlignment = Enum.VerticalAlignment.Center
		row.SortOrder = Enum.SortOrder.LayoutOrder
		row.Padding = UDim.new(0, 6)
		row.Parent = dock
	end
	-- (the whole dock, its panels and cards scale with the screen: never
	-- tiny on a laptop, never a wall on a big monitor; touch targets stay
	-- at least ~46 px)
	local dockScale = Instance.new("UIScale")
	dockScale.Parent = dock
	local scaled: { UIScale } = { dockScale }
	local function rescale()
		local cam = workspace.CurrentCamera
		local vp = if cam then cam.ViewportSize else Vector2.new(1600, 900)
		local s = math.clamp(math.min(vp.X / 1500, vp.Y / 850), 0.72, 1.15)
		if touch then s = math.max(s, 0.82) end
		for _, u in ipairs(scaled) do u.Scale = s end
	end

	-- the name of the button under the mouse, above it (slides up into place)
	local tip = Instance.new("TextLabel")
	tip.Name = "Tooltip"
	tip.AnchorPoint = Vector2.new(0.5, 1)
	tip.Size = UDim2.fromOffset(0, 28)
	tip.AutomaticSize = Enum.AutomaticSize.X
	tip.BackgroundColor3 = DOCK_BG
	tip.BackgroundTransparency = 1
	tip.BorderSizePixel = 0
	tip.Font = DOCK_BOLD
	tip.TextSize = 14
	tip.TextColor3 = Color3.new(1, 1, 1)
	tip.TextTransparency = 1
	tip.Visible = false
	tip.ZIndex = 20
	tip:SetAttribute("KeepFont", true)
	tip.Parent = g
	corner(tip, 8)
	local tipStroke = stroke(tip, TRIM, 1.2, 1)
	do
		local tp = Instance.new("UIPadding")
		tp.PaddingLeft, tp.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		tp.Parent = tip
	end
	local tipOwner: GuiObject? = nil
	local function showTip(owner: GuiObject, text: string)
		tipOwner = owner
		tip.Text = text
		local x = owner.AbsolutePosition.X - g.AbsolutePosition.X + owner.AbsoluteSize.X / 2
		local y = owner.AbsolutePosition.Y - g.AbsolutePosition.Y - 8
		local half = (game:GetService("TextService"):GetTextSize(text, 14, DOCK_BOLD, Vector2.new(1000, 28)).X + 24) / 2
		x = math.clamp(x, half + 8, g.AbsoluteSize.X - 8 - half)
		tip.Position = UDim2.fromOffset(x, y + 6)
		tip.Visible = true
		tween(tip, 0.14, { Position = UDim2.fromOffset(x, y), TextTransparency = 0, BackgroundTransparency = 0.05 })
		tween(tipStroke, 0.14, { Transparency = 0.25 })
	end
	local function hideTip(owner: GuiObject?)
		if owner and tipOwner ~= owner then return end
		tipOwner = nil
		tip.Visible = false
		tip.TextTransparency, tip.BackgroundTransparency, tipStroke.Transparency = 1, 1, 1
	end

	-- A feature tile. `size` its face; `label` the short name under it;
	-- `interactive` false for the small tiles inside a panel row (the row
	-- is the button). Returns the button and its state setters.
	type Tile = { button: GuiButton, setActive: (boolean) -> (), setBadge: (number?) -> (), body: Frame }
	local function tile(parent: Instance, order: number, hue: string, glyph: string, size: number, label: string?,
		interactive: boolean, extra: { hotkey: string?, chevron: boolean? }?): Tile
		local top, bot = HUES[hue][1], HUES[hue][2]
		local labelH = if label then 15 else 0
		local b = Instance.new("TextButton")
		b.Name = "Tile_" .. hue
		b.LayoutOrder = order
		b.Size = UDim2.fromOffset(size + 8, size + labelH + 6)
		b.BackgroundTransparency = 1
		b.Text = ""
		b.AutoButtonColor = false
		b.Selectable = interactive
		b.Active = interactive
		b.Parent = parent
		-- the body: everything that lifts / presses, scaled about its centre
		local body = frame(b, { Name = "Body", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, size / 2 + 3),
			Size = UDim2.fromOffset(size, size), BackgroundTransparency = 1 })
		local bodyScale = Instance.new("UIScale")
		bodyScale.Parent = body
		local r = math.floor(size * 0.24)
		-- a soft glow behind it (hover)
		local glow = frame(body, { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 10, 1, 10), BackgroundColor3 = top, BackgroundTransparency = 1, ZIndex = 1 })
		corner(glow, r + 6)
		-- the active ring (gold), round the outside
		local ring = frame(body, { Name = "Ring", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, 8, 1, 8), BackgroundTransparency = 1, ZIndex = 2 })
		corner(ring, r + 4)
		local ringStroke = stroke(ring, TRIM, 2.5, 1)
		-- shadow, then the lip (the tile's darker underside), then the face
		local shadow = frame(body, { Name = "Shadow", Position = UDim2.fromOffset(0, 5), Size = UDim2.fromScale(1, 1),
			BackgroundColor3 = INK, BackgroundTransparency = 0.45, ZIndex = 2 })
		corner(shadow, r)
		local lip = frame(body, { Name = "Lip", Size = UDim2.fromScale(1, 1), BackgroundColor3 = bot:Lerp(INK, 0.45), ZIndex = 3 })
		corner(lip, r)
		stroke(lip, INK, 2)
		local face = frame(body, { Name = "Face", Size = UDim2.new(1, 0, 1, -4), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 4 })
		corner(face, r)
		local faceGrad = grad(face, top, bot)
		stroke(face, INK, 2)
		-- a light rim just inside the outline, and a gloss over the top half
		local rim = frame(face, { Name = "Rim", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.new(1, -4, 1, -4), BackgroundTransparency = 1, ZIndex = 5 })
		corner(rim, r - 2)
		stroke(rim, Color3.new(1, 1, 1), 1, 0.65)
		local gloss = frame(face, { Name = "Gloss", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 3),
			Size = UDim2.new(1, -8, 0.42, 0), BackgroundColor3 = Color3.new(1, 1, 1), ZIndex = 5 })
		corner(gloss, r - 3)
		local gg = Instance.new("UIGradient")
		gg.Rotation = 90
		gg.Transparency = NumberSequence.new(0.62, 1)
		gg.Parent = gloss
		local shine = frame(face, { Name = "Shine", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1),
			BackgroundTransparency = 1, ZIndex = 8 })
		corner(shine, r)
		-- the icon: white, with a dark drop shadow under it
		local iconShadow = Icons.Draw(glyph, face, INK, size * 0.6)
		iconShadow.Position = UDim2.new(0.5, 0, 0.5, math.max(2, size * 0.04))
		iconShadow.ZIndex = 6
		for _, d in ipairs(iconShadow:GetDescendants()) do if d:IsA("GuiObject") then d.ZIndex = 6 end end
		local icon = Icons.Draw(glyph, face, Color3.new(1, 1, 1), size * 0.6)
		icon.ZIndex = 7
		for _, d in ipairs(icon:GetDescendants()) do if d:IsA("GuiObject") then d.ZIndex = 7 end end
		-- the short name under it
		if label then
			local t = Instance.new("TextLabel")
			t.Name = "Label"
			t.AnchorPoint = Vector2.new(0.5, 0)
			t.Position = UDim2.new(0.5, 0, 0, size + 4)
			t.Size = UDim2.new(1, 10, 0, 13)
			t.BackgroundTransparency = 1
			t.Font = DOCK_BLACK
			t.TextSize = 12
			t.TextColor3 = Color3.new(1, 1, 1)
			t.Text = label
			t.ZIndex = 12 -- (over the body's hover glow)
			t.Parent = b
			stroke(t, INK, 1.5).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
		end
		-- a corner chip: a hotkey, or a ^ on the category tiles (they open upward)
		local function chip(): Frame
			local c = frame(body, { Name = "Chip", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -3, 0, 3),
				Size = UDim2.fromOffset(17, 17), BackgroundColor3 = DOCK_BG, ZIndex = 9 })
			corner(c, 5)
			stroke(c, TRIM, 1.2)
			return c
		end
		if extra and extra.hotkey then
			local c = chip()
			local k = Instance.new("TextLabel")
			k.BackgroundTransparency = 1
			k.Size = UDim2.fromScale(1, 1)
			k.Font = DOCK_BLACK
			k.TextSize = 11
			k.TextColor3 = TRIM
			k.Text = extra.hotkey
			k.ZIndex = 10
			k.Parent = c
		elseif extra and extra.chevron then
			local c = chip()
			local ch = Icons.Draw("chevron", c, TRIM, 17)
			ch.Size = UDim2.fromScale(0.7, 0.7)
			for _, d in ipairs(ch:GetDescendants()) do if d:IsA("GuiObject") then d.ZIndex = 10 end end
		end
		-- a count badge (crimson, top left)
		local badge = frame(body, { Name = "Badge", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(3, 3),
			Size = UDim2.fromOffset(18, 18), BackgroundColor3 = rgb(214, 36, 52), ZIndex = 9, Visible = false })
		corner(badge, 9)
		stroke(badge, Color3.new(1, 1, 1), 1.5)
		local badgeText = Instance.new("TextLabel")
		badgeText.BackgroundTransparency = 1
		badgeText.Size = UDim2.fromScale(1, 1)
		badgeText.Font = DOCK_BLACK
		badgeText.TextSize = 11
		badgeText.TextColor3 = Color3.new(1, 1, 1)
		badgeText.ZIndex = 10
		badgeText.Parent = badge

		-- states: idle / hover (lift, brighter, glow) / pressed (pushed into the lip)
		local hover, pressed, active = false, false, false
		local function settle()
			local s = if pressed then 0.94 elseif hover then 1.08 else 1
			tween(bodyScale, if pressed then 0.06 else 0.16, { Scale = s }, if pressed then Enum.EasingStyle.Quad else Enum.EasingStyle.Back)
			tween(face, 0.08, { Position = UDim2.fromOffset(0, if pressed then 3 else 0) })
			tween(shine, 0.14, { BackgroundTransparency = if pressed then 0.7 elseif hover then 0.86 else 1 })
			tween(glow, 0.16, { BackgroundTransparency = if hover or active then 0.6 else 1,
				Size = if hover then UDim2.new(1, 16, 1, 16) else UDim2.new(1, 10, 1, 10) })
			faceGrad.Offset = Vector2.new(0, if hover then -0.08 else 0) -- (the light rides up a little)
		end
		if interactive then
			b.MouseEnter:Connect(function() hover = true; settle() end)
			b.MouseLeave:Connect(function() hover, pressed = false, false; settle(); hideTip(b) end)
			b.SelectionGained:Connect(function() hover = true; settle() end)
			b.SelectionLost:Connect(function() hover, pressed = false, false; settle(); hideTip(b) end)
			b.MouseButton1Down:Connect(function() pressed = true; settle() end)
			b.MouseButton1Up:Connect(function() pressed = false; settle() end)
			b.Activated:Connect(function()
				-- (a brief flash of light on the click)
				shine.BackgroundTransparency = 0.5
				tween(shine, 0.25, { BackgroundTransparency = if hover then 0.86 else 1 })
			end)
		end
		return {
			button = b,
			body = body,
			setActive = function(on: boolean)
				if on == active then return end
				active = on
				tween(ringStroke, 0.18, { Transparency = if on then 0 else 1 })
				settle()
			end,
			setBadge = function(n: number?)
				badge.Visible = n ~= nil
				if n then badgeText.Text = tostring(n) end
			end,
		}
	end

	-- a card above the dock (the party, the key hints, the rewards): one open at a time
	local cards: { Frame } = {}
	local function card(name: string, width: number): Frame
		local f = Instance.new("Frame")
		f.Name = name
		f.AnchorPoint = Vector2.new(1, 1)
		f.Position = UDim2.new(1, -14, 1, bottom - 100)
		f.Size = UDim2.fromOffset(width, 0)
		f.AutomaticSize = Enum.AutomaticSize.Y
		f.BackgroundColor3 = DOCK_BG
		f.BackgroundTransparency = 0.06
		f.BorderSizePixel = 0
		f.Active = true
		f.Visible = false
		f:SetAttribute("KeepFont", true)
		f.Parent = g
		corner(f, 12)
		stroke(f, TRIM, 1.5, 0.2)
		local pad = Instance.new("UIPadding")
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
		pad.Parent = f
		local lay = Instance.new("UIListLayout")
		lay.Padding = UDim.new(0, 4)
		lay.SortOrder = Enum.SortOrder.LayoutOrder
		lay.Parent = f
		local u = Instance.new("UIScale")
		u.Parent = f
		table.insert(scaled, u)
		table.insert(cards, f)
		return f
	end
	local function closeCards()
		for _, c in ipairs(cards) do c.Visible = false end
	end
	local closePanels: () -> () = function() end
	local function toggleCard(f: Frame)
		local show = not f.Visible
		closeCards()
		closePanels()
		-- (just above the dock, whatever its scaled height)
		f.Position = UDim2.new(1, -14, 1, bottom - dock.AbsoluteSize.Y - 10)
		f.Visible = show
	end
	local function named(text: string): () -> string
		return function() return text end
	end
	-- The party: who is in it (the leader starred), and LEAVE PARTY.
	local partyCard = card("Party", 240)
	label(partyCard, "Your party", 16, Color3.new(1, 1, 1), { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Font = DOCK_BOLD, TextStrokeTransparency = 1 })
	local l = Instance.new("Frame")
	l.Name = "Members"
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = 2
	l.Parent = partyCard
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 2)
	ll.Parent = l
	list = l
	local b = Instance.new("TextButton")
	b.Name = "Leave"
	b.LayoutOrder = 3
	b.Size = UDim2.new(1, 0, 0, 30)
	b.BackgroundColor3 = Color3.fromRGB(150, 44, 40)
	b.BorderSizePixel = 0
	b.Font = DOCK_BOLD
	b.TextSize = 14
	b.TextColor3 = Color3.new(1, 1, 1)
	b.Text = "Leave party"
	b.Visible = false
	b.Parent = partyCard
	corner(b, 6)
	b.MouseButton1Click:Connect(function()
		Network.GetRemoteEvent(Network.Remotes.PartyAction):FireServer({ kind = "leave" })
	end)
	leaveBtn = b

	-- The keys.
	local helpCard = card("Help", 300)
	label(helpCard, "Controls", 16, Color3.new(1, 1, 1), { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Font = DOCK_BOLD, TextStrokeTransparency = 1 })
	label(helpCard, "E: the Armory (near a player: meet them)\nK: the skill tree\nF at the FORGE: forge gear\n1-5: emotes\n/: chat\nF at the DUNGEON gate: pick a map\nGACHA tent: summon\nCtrl: shift lock\nM: settings", 14,
		Color3.fromRGB(225, 225, 225), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top, Font = DOCK_FONT, TextStrokeTransparency = 1, LineHeight = 1.25 })

	-- Community rewards (StoreManager): the group (checked), and liking /
	-- favoriting the game (Roblox can't check those: claimed on trust, once).
	local rewardsCard = card("Rewards", 300)
	label(rewardsCard, "Community rewards", 16, Color3.new(1, 1, 1), { Size = UDim2.new(1, 0, 0, 20), LayoutOrder = 1, Font = DOCK_BOLD, TextStrokeTransparency = 1 })
	local rewardsMsg = label(rewardsCard, "", 13, Color3.fromRGB(255, 210, 140), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
		LayoutOrder = 9, TextWrapped = true, Font = DOCK_FONT, TextStrokeTransparency = 1 })
	local function rewardRow(order: number, text: string, buttons: { { any } })
		label(rewardsCard, text, 14, Color3.fromRGB(225, 225, 225), { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = order,
			TextWrapped = true, Font = DOCK_FONT, TextStrokeTransparency = 1 })
		local row = Instance.new("Frame")
		row.BackgroundTransparency = 1
		row.Size = UDim2.new(1, 0, 0, 30)
		row.LayoutOrder = order + 1
		row.Parent = rewardsCard
		local rl = Instance.new("UIListLayout")
		rl.FillDirection = Enum.FillDirection.Horizontal
		rl.SortOrder = Enum.SortOrder.LayoutOrder
		rl.Padding = UDim.new(0, 6)
		rl.Parent = row
		for i, spec in ipairs(buttons) do
			local rb = Instance.new("TextButton")
			rb.Name = spec[3] or spec[1]
			rb.LayoutOrder = i
			rb.Size = UDim2.new(1 / #buttons, -6, 1, 0)
			rb.BackgroundColor3 = Color3.fromRGB(0, 162, 95)
			rb.BorderSizePixel = 0
			rb.Font = DOCK_BOLD
			rb.TextSize = 13
			rb.TextColor3 = Color3.new(1, 1, 1)
			rb.Text = spec[1]
			rb.Parent = row
			corner(rb, 6)
			Icons.Press(rb)
			rb.Activated:Connect(spec[2])
		end
	end
	local C = StoreConfig.Community
	local function storeAction(kind: string)
		rewardsMsg.Text = ""
		Network.GetRemoteEvent(Network.Remotes.StoreAction):FireServer({ kind = kind })
	end
	if C.groupId > 0 then
		rewardRow(2, `Join our Roblox group: +{C.groupReward.amount} Pull Tickets`, {
			{ "Join group", function()
				pcall(function() game:GetService("GroupService"):PromptJoinAsync(C.groupId) end)
			end, "JoinGroup" },
			{ "Claim", function() storeAction("claimGroup") end, "ClaimGroup" },
		})
	end
	rewardRow(4, `Like and favorite the game: +{C.likeReward.amount} Pull Tickets`, {
		{ "Favorite", function()
			pcall(function()
				game:GetService("AvatarEditorService"):PromptSetFavorite(game.PlaceId, Enum.AvatarItemType.Asset, true)
			end)
		end, "Favorite" },
		{ "Claim", function() storeAction("claimLike") end, "ClaimLike" },
	})
	label(rewardsCard, "Join our Discord from the game's page for news and codes.", 12, Color3.fromRGB(170, 170, 170), { Size = UDim2.new(1, 0, 0, 0),
		AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 8, TextWrapped = true, Font = DOCK_FONT, TextStrokeTransparency = 1 })
	local function refreshClaims()
		for _, pair in ipairs({ { "ClaimGroup", "ClaimedGroup" }, { "ClaimLike", "ClaimedLike" } }) do
			local btn = rewardsCard:FindFirstChild(pair[1], true) :: TextButton?
			if btn then
				local done = player:GetAttribute(pair[2]) == true
				btn.Text = if done then "Claimed" else "Claim"
				btn.AutoButtonColor = not done
				btn.BackgroundColor3 = if done then Color3.fromRGB(80, 82, 86) else Color3.fromRGB(0, 162, 95)
			end
		end
	end
	player:GetAttributeChangedSignal("ClaimedGroup"):Connect(refreshClaims)
	player:GetAttributeChangedSignal("ClaimedLike"):Connect(refreshClaims)
	refreshClaims()
	Network.GetRemoteEvent(Network.Remotes.StoreResult).OnClientEvent:Connect(function(d: any)
		if typeof(d) == "table" and (d.kind == "claimGroup" or d.kind == "claimLike") then rewardsMsg.Text = tostring(d.message) end
	end)

	-- ── The dock's contents ──
	-- CHARACTER (always on the dock): Party, Armory, Wardrobe, Talents, Codex.
	local partyTile = tile(dock, 1, "party", "party", TILE, "Party", true)
	local armoryTile = tile(dock, 2, "armory", "sword", TILE, "Armory", true, { hotkey = "E" })
	local wardrobeTile = tile(dock, 3, "wardrobe", "shirt", TILE, "Wardrobe", true)
	local talentsTile = tile(dock, 4, "talents", "tree", TILE, "Talents", true, { hotkey = "K" })
	local codexTile = tile(dock, 5, "codex", "book", TILE, "Codex", true)
	local function onTile(t: Tile, tipText: () -> string, action: () -> ())
		t.button.MouseEnter:Connect(function() showTip(t.button, tipText()) end)
		t.button.SelectionGained:Connect(function() showTip(t.button, tipText()) end)
		t.button.Activated:Connect(function()
			hideTip()
			action()
		end)
	end
	onTile(partyTile, function() return if partyTip then partyTip() else "Party" end, function() toggleCard(partyCard) end)
	onTile(armoryTile, named("Armory  (E)"), function() closeCards() closePanels() Armory.Open() end)
	onTile(wardrobeTile, named("Wardrobe"), function() closeCards() closePanels() WardrobeScreen.OpenLobby("armor") end)
	onTile(talentsTile, named("Skill Tree  (K)"), function() closeCards() closePanels() TalentScreen.Open() end)
	onTile(codexTile, named("Build Codex"), function() closeCards() closePanels() BuildCodex.Open() end)
	partyBadge = function(n: number) partyTile.setBadge(if n > 1 then n else nil) end

	-- the separator between the character features and the categories
	do
		local sep = frame(dock, { Name = "Separator", LayoutOrder = 10, Size = UDim2.fromOffset(2, TILE + 4), BackgroundColor3 = TRIM })
		local sg = Instance.new("UIGradient")
		sg.Rotation = 90
		sg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.25), NumberSequenceKeypoint.new(1, 1) })
		sg.Parent = sep
	end

	-- SOCIAL, MARKET, EXTRAS: category tiles, each opening a floating panel
	-- of its features above itself (one open at a time; a click outside, or
	-- picking anything, closes it).
	type Item = { hue: string, glyph: string, name: string, sub: string, action: () -> (), id: string? }
	type Group = { id: string, hue: string, glyph: string, label: string, title: string, items: { Item } }
	local GROUPS: { Group } = {
		{ id = "social", hue = "social", glyph = "flag", label = "Social", title = "SOCIAL", items = {
			{ hue = "guild", glyph = "flag", name = "Guild", sub = "Your guild and its members",
				action = function() GuildScreen.Open() end },
			{ hue = "invite", glyph = "plus", name = "Invite Friends", sub = "Bring friends into this lobby",
				action = function() end, id = "InviteFriends" },
		} },
		{ id = "market", hue = "market", glyph = "bag", label = "Market", title = "MARKETPLACE", items = {
			{ hue = "summon", glyph = "bag", name = "Summon Shop", sub = "Pull tickets, gems and bundles",
				action = function() StoreScreen.Open("summon") end },
			{ hue = "mounts", glyph = "horseshoe", name = "Mounts Shop", sub = "Steeds and flyers",
				action = function() StoreScreen.Open("mounts") end },
		} },
		{ id = "extras", hue = "extras", glyph = "gift", label = "Extras", title = "EXTRAS", items = {
			{ hue = "rewards", glyph = "gift", name = "Community Rewards", sub = "Free pull tickets",
				action = function() toggleCard(rewardsCard) end },
			{ hue = "help", glyph = "help", name = "Controls", sub = "Every key in the lobby",
				action = function() toggleCard(helpCard) end },
		} },
	}
	type Panel = { group: Group, tileRef: Tile, wrap: Frame, canvas: CanvasGroup, inner: UIScale, caret: Frame, open: boolean }
	local panels: { Panel } = {}
	local PANEL_W = 250
	local function placePanel(p: Panel)
		-- (above its tile, the caret pointing down at it; kept on screen)
		local t = p.tileRef.body
		local s = dockScale.Scale
		local cx = t.AbsolutePosition.X + t.AbsoluteSize.X / 2 - g.AbsolutePosition.X
		local topY = dock.AbsolutePosition.Y - g.AbsolutePosition.Y - 6
		local half = PANEL_W * s / 2
		local x = math.clamp(cx, half + 8, g.AbsoluteSize.X - half - 8)
		p.wrap.Position = UDim2.fromOffset(x, topY)
		p.caret.Position = UDim2.new(0.5, (cx - x) / s, 1, -9)
	end
	local function setPanel(p: Panel, open: boolean)
		if p.open == open then return end
		p.open = open
		p.tileRef.setActive(open or p.tileRef.button:GetAttribute("ScreenOpen") == true)
		if open then
			placePanel(p)
			p.wrap.Visible = true
			p.canvas.GroupTransparency = 1
			p.inner.Scale = 0.9
			p.canvas.Position = UDim2.new(0.5, 0, 1, 10)
			tween(p.canvas, 0.18, { GroupTransparency = 0, Position = UDim2.new(0.5, 0, 1, 0) })
			tween(p.inner, 0.2, { Scale = 1 }, Enum.EasingStyle.Back)
		else
			tween(p.canvas, 0.12, { GroupTransparency = 1, Position = UDim2.new(0.5, 0, 1, 8) })
			tween(p.inner, 0.12, { Scale = 0.94 })
			task.delay(0.12, function() if not p.open then p.wrap.Visible = false end end)
		end
	end
	closePanels = function() for _, p in ipairs(panels) do setPanel(p, false) end end

	for gi, grp in ipairs(GROUPS) do
		local t = tile(dock, 10 + gi, grp.hue, grp.glyph, TILE, grp.label, true, { chevron = true })
		-- the panel: a wrapper (screen scale) round a canvas (fade + pop)
		local wrap = frame(g, { Name = "Panel_" .. grp.id, AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(PANEL_W, 0),
			BackgroundTransparency = 1, Visible = false, ZIndex = 10 })
		wrap:SetAttribute("KeepFont", true)
		local ws = Instance.new("UIScale")
		ws.Parent = wrap
		table.insert(scaled, ws)
		local canvas = Instance.new("CanvasGroup")
		canvas.Name = "Canvas"
		canvas.AnchorPoint = Vector2.new(0.5, 1)
		canvas.Position = UDim2.new(0.5, 0, 1, 0)
		-- (sized exactly: the box, plus room under it for the caret, which a
		-- canvas would clip)
		local boxH = 20 + 18 + 1 + 6 * (#grp.items + 1) + 50 * #grp.items
		canvas.Size = UDim2.fromOffset(PANEL_W, boxH + 10)
		canvas.BackgroundTransparency = 1
		canvas.Parent = wrap
		local inner = Instance.new("UIScale")
		inner.Parent = canvas
		local box = frame(canvas, { Name = "Box", Size = UDim2.new(1, 0, 0, boxH),
			BackgroundColor3 = DOCK_BG, BackgroundTransparency = 0.04 })
		corner(box, 14)
		stroke(box, TRIM, 1.5, 0.15)
		grad(box, Color3.fromRGB(255, 255, 255), Color3.fromRGB(160, 150, 160))
		do
			local pad = Instance.new("UIPadding")
			pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
			pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
			pad.Parent = box
			local lay = Instance.new("UIListLayout")
			lay.Padding = UDim.new(0, 6)
			lay.SortOrder = Enum.SortOrder.LayoutOrder
			lay.Parent = box
		end
		-- header: the category's name in its own colours, a trim line under it
		local head = Instance.new("TextLabel")
		head.Name = "Title"
		head.LayoutOrder = 0
		head.Size = UDim2.new(1, 0, 0, 18)
		head.BackgroundTransparency = 1
		head.Font = DOCK_BLACK
		head.TextSize = 14
		head.TextXAlignment = Enum.TextXAlignment.Left
		head.TextColor3 = Color3.new(1, 1, 1)
		head.Text = grp.title
		head.Parent = box
		grad(head, HUES[grp.hue][1], HUES[grp.hue][2], 0)
		local line = frame(box, { Name = "Line", LayoutOrder = 1, Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = TRIM, BackgroundTransparency = 0.5 })
		local lg = Instance.new("UIGradient")
		lg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
		lg.Parent = line
		-- the caret: a small diamond under the box, pointing at the tile
		local caret = frame(canvas, { Name = "Caret", AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(14, 14),
			BackgroundColor3 = DOCK_BG, Rotation = 45, ZIndex = 0 })
		stroke(caret, TRIM, 1.5, 0.15)
		local p: Panel = { group = grp, tileRef = t, wrap = wrap, canvas = canvas, inner = inner, caret = caret, open = false }
		-- the rows: a small tile, the name and a line under it
		for ii, it in ipairs(grp.items) do
			local row = Instance.new("TextButton")
			row.Name = it.id or ("Row_" .. it.hue)
			row.LayoutOrder = 1 + ii
			row.Size = UDim2.new(1, 0, 0, 50)
			row.BackgroundColor3 = Color3.new(1, 1, 1)
			row.BackgroundTransparency = 1
			row.AutoButtonColor = false
			row.Text = ""
			row.Selectable = true
			row.Parent = box
			corner(row, 10)
			local mini = tile(row, 0, it.hue, it.glyph, 40, nil, false)
			mini.button.Position = UDim2.fromOffset(0, 2)
			local nm = Instance.new("TextLabel")
			nm.BackgroundTransparency = 1
			nm.Position = UDim2.fromOffset(56, 7)
			nm.Size = UDim2.new(1, -60, 0, 18)
			nm.Font = DOCK_BOLD
			nm.TextSize = 15
			nm.TextXAlignment = Enum.TextXAlignment.Left
			nm.TextColor3 = Color3.new(1, 1, 1)
			nm.Text = it.name
			nm.Parent = row
			local sub = Instance.new("TextLabel")
			sub.BackgroundTransparency = 1
			sub.Position = UDim2.fromOffset(56, 26)
			sub.Size = UDim2.new(1, -60, 0, 16)
			sub.Font = DOCK_FONT
			sub.TextSize = 12
			sub.TextXAlignment = Enum.TextXAlignment.Left
			sub.TextColor3 = Color3.fromRGB(190, 182, 176)
			sub.TextTruncate = Enum.TextTruncate.AtEnd
			sub.Text = it.sub
			sub.Parent = row
			local ms = mini.body:FindFirstChildOfClass("UIScale") :: UIScale
			local function hl(on: boolean)
				tween(row, 0.12, { BackgroundTransparency = if on then 0.9 else 1 })
				tween(ms, 0.14, { Scale = if on then 1.08 else 1 }, Enum.EasingStyle.Back)
			end
			row.MouseEnter:Connect(function() hl(true) end)
			row.MouseLeave:Connect(function() hl(false) end)
			row.SelectionGained:Connect(function() hl(true) end)
			row.SelectionLost:Connect(function() hl(false) end)
			row.MouseButton1Down:Connect(function() tween(ms, 0.06, { Scale = 0.92 }) end)
			row.Activated:Connect(function()
				closePanels()
				if it.hue ~= "rewards" and it.hue ~= "help" then closeCards() end
				it.action()
			end)
			-- (Invite Friends: Roblox's own invite window, wired in Init)
			if it.id == "InviteFriends" then inviteFriendsBtn = row end
		end
		table.insert(panels, p)
		onTile(t, named(grp.label), function()
			local was = p.open
			closePanels()
			closeCards()
			if not was then setPanel(p, true) end
		end)
	end

	-- a click (or tap) outside an open panel or card closes it: an invisible
	-- catcher across the screen, behind the dock, only there while one is open
	local catcher = Instance.new("TextButton")
	catcher.Name = "ClickOutside"
	catcher.Size = UDim2.fromScale(1, 1)
	catcher.BackgroundTransparency = 1
	catcher.Text = ""
	catcher.AutoButtonColor = false
	catcher.Selectable = false
	catcher.ZIndex = 0
	catcher.Visible = false
	catcher.Parent = g
	catcher.Activated:Connect(function()
		closePanels()
		closeCards()
	end)
	local function syncCatcher()
		local any = false
		for _, p in ipairs(panels) do if p.open then any = true end end
		for _, c in ipairs(cards) do if c.Visible then any = true end end
		if catcher.Visible ~= any then catcher.Visible = any end
	end
	for _, c in ipairs(cards) do c:GetPropertyChangedSignal("Visible"):Connect(syncCatcher) end
	for _, p in ipairs(panels) do p.wrap:GetPropertyChangedSignal("Visible"):Connect(syncCatcher) end
	-- the gold ring on the tile of whatever is open (checked 5x a second;
	-- only written when it changes)
	local pg = player:WaitForChild("PlayerGui")
	local function open(name: string): boolean
		local sg = pg:FindFirstChild(name)
		return sg ~= nil and sg:IsA("ScreenGui") and sg.Enabled
	end
	local watch: { { any } } = { -- ({ tile, is its screen open? })
		{ partyTile, function() return partyCard.Visible end },
		{ armoryTile, function() return open("Armory") end },
		{ wardrobeTile, function() return open("WardrobeScreen") end },
		{ talentsTile, function() return open("TalentScreen") end },
		{ codexTile, function() return open("BuildCodex") end },
	}
	task.spawn(function()
		while g.Parent do
			if g.Enabled then
				for _, w in ipairs(watch) do w[1].setActive(w[2]()) end
				for _, p in ipairs(panels) do
					local screenOpen = (p.group.id == "social" and open("GuildScreen")) or (p.group.id == "market" and open("StoreScreen"))
						or (p.group.id == "extras" and (rewardsCard.Visible or helpCard.Visible))
					p.tileRef.button:SetAttribute("ScreenOpen", screenOpen == true)
					p.tileRef.setActive(p.open or screenOpen == true)
				end
				syncCatcher()
			end
			task.wait(0.2)
		end
	end)

	rescale()
	local cam = workspace.CurrentCamera
	if cam then cam:GetPropertyChangedSignal("ViewportSize"):Connect(rescale) end
	-- Notices (centre, below the top)
	local n = label(g, "", 22, PARCH, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(700, 34), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, TextStrokeTransparency = 1 })
	n:SetAttribute("KeepFont", false) -- (the game's own lettering)
	noticeLabel = n
end

-- ── The map picker (the gate / the quest board) ──
local picker: ScreenGui? = nil

local function closePicker()
	if picker then picker.Enabled = false end
end

local function openPicker()
	if not picker then
		local g = Instance.new("ScreenGui")
		g.Name = "MapPicker"
		g.ResetOnSpawn = false
		g.IgnoreGuiInset = true
		g.DisplayOrder = 60
		g.Parent = player:WaitForChild("PlayerGui")
		picker = g
		local dim = Instance.new("TextButton")
		dim.Text = ""
		dim.AutoButtonColor = false
		dim.Size = UDim2.fromScale(1, 1)
		dim.BackgroundColor3 = Color3.new(0, 0, 0)
		dim.BackgroundTransparency = 0.45
		dim.Parent = g
		label(g, "CHOOSE YOUR DUNGEON", 40, GOLD, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.06, 0),
			Size = UDim2.fromOffset(900, 50), TextXAlignment = Enum.TextXAlignment.Center })
		label(g, "The party leader chooses.", 18, PARCH, { AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.06, 50), Size = UDim2.fromOffset(900, 24), TextXAlignment = Enum.TextXAlignment.Center })
		do
			-- this week's omen (WeeklyModifiers): every run this week has it
			local WeeklyModifiers = require(Shared:WaitForChild("WeeklyModifiers"))
			local m = WeeklyModifiers.Current()
			label(g, `THIS WEEK: {m.name}  ·  {m.description}`, 16, m.color, { AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.06, 78), Size = UDim2.fromOffset(1000, 22), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
		end
		-- (a card per map: the row as wide as they are)
		local rowW = #MapData.Maps * 252 + (#MapData.Maps - 1) * 16
		local row = Instance.new("Frame")
		row.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Position = UDim2.new(0.5, 0, 0.55, 10)
		row.Size = UDim2.fromOffset(rowW, 420)
		row.BackgroundTransparency = 1
		row.Parent = g
		-- (a click between the cards leaves it open)
		ClickOutside.Bind(dim, row, closePicker)
		local lay = Instance.new("UIListLayout")
		lay.FillDirection = Enum.FillDirection.Horizontal
		lay.SortOrder = Enum.SortOrder.LayoutOrder -- (rank order, not by name)
		lay.HorizontalAlignment = Enum.HorizontalAlignment.Center
		lay.Padding = UDim.new(0, 16)
		lay.Parent = row
		-- (it fits small screens)
		local fit = Instance.new("UIScale")
		fit.Parent = row
		local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
		fit.Scale = math.min(1, (vp.X - 40) / rowW)
		for i, map in ipairs(MapData.Maps) do
			local card = Instance.new("TextButton")
			card.Name = map.id
			card.LayoutOrder = i
			card.Text = ""
			card.AutoButtonColor = false
			card.Size = UDim2.fromOffset(252, 410)
			card.BackgroundColor3 = DARK
			card.BackgroundTransparency = 0.1
			card.Parent = row
			local cc = Instance.new("UICorner")
			cc.CornerRadius = UDim.new(0, 10)
			cc.Parent = card
			local st = Instance.new("UIStroke")
			st.Color = map.color
			st.Thickness = 2
			st.Transparency = 0.3
			st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			st.Parent = card
			local band = Instance.new("Frame")
			band.Size = UDim2.new(1, 0, 0, 120)
			band.BackgroundColor3 = map.color
			band.BackgroundTransparency = 0.55
			band.BorderSizePixel = 0
			band.Parent = card
			local bc = Instance.new("UICorner")
			bc.CornerRadius = UDim.new(0, 10)
			bc.Parent = band
			label(band, "RANK " .. tostring(map.rank), 22, PARCH, { Position = UDim2.fromOffset(16, 12), Size = UDim2.new(1, -32, 0, 26) })
			label(band, map.name, 30, Color3.new(1, 1, 1), { Position = UDim2.fromOffset(16, 46), Size = UDim2.new(1, -32, 0, 64), TextWrapped = true })
			label(card, map.subtitle, 19, map.color, { Position = UDim2.fromOffset(16, 132), Size = UDim2.new(1, -32, 0, 26) })
			local desc = label(card, map.description, 17, PARCH, { Position = UDim2.fromOffset(16, 166), Size = UDim2.new(1, -32, 0, 56), TextWrapped = true, TextScaled = true,
				TextYAlignment = Enum.TextYAlignment.Top })
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = 17
			cap.Parent = desc
			-- The difficulty modes (MapData.MODES), one button each: its name and
			-- the POWER it asks for, green when yours is enough, amber when close,
			-- red when you're under-geared. Clicking one enters on that mode.
			local go = Instance.new("Frame")
			go.Name = "Modes"
			go.AnchorPoint = Vector2.new(0.5, 1)
			go.Position = UDim2.new(0.5, 0, 1, -12)
			go.Size = UDim2.new(1, -24, 0, 150)
			go.BackgroundTransparency = 1
			go.Parent = card
			local ml = Instance.new("UIListLayout")
			ml.SortOrder = Enum.SortOrder.LayoutOrder
			ml.Padding = UDim.new(0, 6)
			ml.Parent = go
			label(go, "RECOMMENDED POWER", 13, PARCH, { LayoutOrder = 0, Size = UDim2.new(1, 0, 0, 14), TextXAlignment = Enum.TextXAlignment.Center,
				TextTransparency = 0.25 })
			local powerLabels: { { label: TextLabel, need: number } } = {}
			for mi, mode in ipairs(MapData.MODES) do
				local b = Instance.new("TextButton")
				b.Name = "Mode_" .. mode.id
				b.LayoutOrder = mi
				b.Text = ""
				b.AutoButtonColor = false
				b.Size = UDim2.new(1, 0, 0, 38)
				b.BackgroundColor3 = Color3.fromRGB(46, 32, 26)
				b.BackgroundTransparency = 0.15
				b.Parent = go
				local bcr = Instance.new("UICorner")
				bcr.CornerRadius = UDim.new(0, 6)
				bcr.Parent = b
				local bst = Instance.new("UIStroke")
				bst.Color = mode.color
				bst.Thickness = 1.5
				bst.Transparency = 0.4
				bst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
				bst.Parent = b
				label(b, mode.name, 20, mode.color, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0.55, 0, 1, 0) })
				local need = MapData.RecommendedPower(map, mode.id)
				local pl = label(b, `◆ {need}`, 18, PARCH, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 0), Size = UDim2.new(0.45, 0, 1, 0),
					TextXAlignment = Enum.TextXAlignment.Right })
				table.insert(powerLabels, { label = pl, need = need })
				b.MouseEnter:Connect(function()
					TweenService:Create(bst, TweenInfo.new(0.1), { Transparency = 0, Thickness = 2.5 }):Play()
					TweenService:Create(b, TweenInfo.new(0.1), { BackgroundTransparency = 0 }):Play()
				end)
				b.MouseLeave:Connect(function()
					TweenService:Create(bst, TweenInfo.new(0.1), { Transparency = 0.4, Thickness = 1.5 }):Play()
					TweenService:Create(b, TweenInfo.new(0.1), { BackgroundTransparency = 0.15 }):Play()
				end)
				if not map.sealed then
					b.MouseButton1Click:Connect(function()
						closePicker()
						Network.GetRemoteEvent(Network.Remotes.LobbyAction):FireServer({ kind = "pick", mapId = map.id, mode = mode.id })
					end)
				end
			end
			local function colorPower()
				local mine = tonumber(player:GetAttribute("Power")) or 0
				for _, e in ipairs(powerLabels) do
					e.label.TextColor3 = if mine >= e.need then Color3.fromRGB(140, 230, 140)
						elseif mine >= e.need * 0.75 then Color3.fromRGB(255, 200, 90)
						else Color3.fromRGB(255, 110, 110)
				end
			end
			colorPower()
			player:GetAttributeChangedSignal("Power"):Connect(colorPower)
			card.MouseEnter:Connect(function()
				TweenService:Create(st, TweenInfo.new(0.12), { Transparency = 0, Thickness = 3 }):Play()
			end)
			card.MouseLeave:Connect(function()
				TweenService:Create(st, TweenInfo.new(0.12), { Transparency = 0.3, Thickness = 2 }):Play()
			end)
			-- (a map locked until you've been deep enough)
			if map.unlockFloor then
				local lock = label(card, "", 15, Color3.fromRGB(255, 120, 120), { Position = UDim2.fromOffset(12, 222),
					Size = UDim2.new(1, -24, 0, 22), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
				local function upd()
					local best = player:GetAttribute("BestFloor") or 0
					local open = best >= map.unlockFloor
					lock.Text = if open then "" else `LOCKED · Floor {map.unlockFloor} (best: {best})`
					lock.TextColor3 = if open then Color3.fromRGB(210, 170, 255) else Color3.fromRGB(255, 120, 120)
				end
				upd()
				player:GetAttributeChangedSignal("BestFloor"):Connect(upd)
			end
			-- (sealed: dimmed under two heavy chains crossing it, a padlock where
			-- they meet; it can't be chosen)
			if map.sealed then
				go.Visible = false
				local shade = Instance.new("Frame")
				shade.Size = UDim2.fromScale(1, 1)
				shade.BackgroundColor3 = Color3.new(0, 0, 0)
				shade.BackgroundTransparency = 0.45
				shade.ZIndex = 5
				shade.Parent = card
				local sc = Instance.new("UICorner")
				sc.CornerRadius = UDim.new(0, 10)
				sc.Parent = shade
				local IRON_LIGHT, IRON_DARK = Color3.fromRGB(150, 156, 168), Color3.fromRGB(70, 74, 84)
				-- each chain: oval links alternating face-on and edge-on, end to end
				local diag = math.deg(math.atan2(410, 252))
				for _, ang in ipairs({ diag, -diag }) do
					local chain = Instance.new("Frame")
					chain.AnchorPoint = Vector2.new(0.5, 0.5)
					chain.Position = UDim2.fromScale(0.5, 0.5)
					chain.Size = UDim2.fromOffset(520, 30)
					chain.Rotation = ang
					chain.BackgroundTransparency = 1
					chain.ZIndex = 6
					chain.Parent = card
					local n = 21
					for i = 0, n - 1 do
						local flat = i % 2 == 0
						local link = Instance.new("Frame")
						link.AnchorPoint = Vector2.new(0.5, 0.5)
						link.Position = UDim2.new(0, 12 + i * 23.8, 0.5, 0)
						link.Size = if flat then UDim2.fromOffset(34, 22) else UDim2.fromOffset(32, 9)
						link.BackgroundColor3 = if flat then IRON_DARK else IRON_LIGHT
						link.BackgroundTransparency = if flat then 1 else 0
						link.ZIndex = if flat then 6 else 7
						link.Parent = chain
						local lc = Instance.new("UICorner")
						lc.CornerRadius = UDim.new(1, 0)
						lc.Parent = link
						local ls = Instance.new("UIStroke")
						ls.Color = if flat then IRON_LIGHT else IRON_DARK
						ls.Thickness = if flat then 5 else 1.5
						ls.Parent = link
					end
				end
				-- the padlock where they cross
				local lock = Instance.new("Frame")
				lock.AnchorPoint = Vector2.new(0.5, 0.5)
				lock.Position = UDim2.fromScale(0.5, 0.53)
				lock.Size = UDim2.fromOffset(64, 54)
				lock.BackgroundColor3 = Color3.fromRGB(176, 140, 64)
				lock.ZIndex = 9
				lock.Parent = card
				local lc = Instance.new("UICorner")
				lc.CornerRadius = UDim.new(0, 8)
				lc.Parent = lock
				local lst = Instance.new("UIStroke")
				lst.Color = Color3.fromRGB(90, 66, 24)
				lst.Thickness = 2.5
				lst.Parent = lock
				local shackle = Instance.new("Frame")
				shackle.AnchorPoint = Vector2.new(0.5, 1)
				shackle.Position = UDim2.new(0.5, 0, 0, 8)
				shackle.Size = UDim2.fromOffset(42, 44)
				shackle.BackgroundTransparency = 1
				shackle.ZIndex = 8
				shackle.Parent = lock
				local shc = Instance.new("UICorner")
				shc.CornerRadius = UDim.new(1, 0)
				shc.Parent = shackle
				local shs = Instance.new("UIStroke")
				shs.Color = IRON_LIGHT
				shs.Thickness = 7
				shs.Parent = shackle
				local hole = Instance.new("Frame")
				hole.AnchorPoint = Vector2.new(0.5, 0.5)
				hole.Position = UDim2.fromScale(0.5, 0.45)
				hole.Size = UDim2.fromOffset(12, 18)
				hole.BackgroundColor3 = Color3.fromRGB(40, 28, 10)
				hole.ZIndex = 10
				hole.Parent = lock
				local hc = Instance.new("UICorner")
				hc.CornerRadius = UDim.new(1, 0)
				hc.Parent = hole
				local sealedLabel = label(card, "SEALED", 30, Color3.fromRGB(190, 225, 255), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -18),
					Size = UDim2.new(1, -32, 0, 40), TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.2 })
				sealedLabel.ZIndex = 11
			end
		end
		local close = Instance.new("TextButton")
		close.AnchorPoint = Vector2.new(0.5, 0)
		close.Position = UDim2.new(0.5, 0, 0.56, 230)
		close.Size = UDim2.fromOffset(180, 40)
		close.BackgroundColor3 = Color3.fromRGB(60, 40, 30)
		close.Font = FONT
		close.TextSize = 22
		close.TextColor3 = PARCH
		close.Text = "BACK"
		close.Parent = g
		local xc = Instance.new("UICorner")
		xc.CornerRadius = UDim.new(0, 6)
		xc.Parent = close
		close.MouseButton1Click:Connect(closePicker)
		-- The tutorial (MapData.Tutorial, Tutorial.luau): just you, every kind
		-- of room in turn with a card explaining each.
		local tut = Instance.new("TextButton")
		tut.AnchorPoint = Vector2.new(1, 0)
		tut.Position = UDim2.new(0.5, -110, 0.56, 230)
		tut.Size = UDim2.fromOffset(220, 40)
		tut.BackgroundColor3 = Color3.fromRGB(28, 44, 60)
		tut.Font = FONT
		tut.TextSize = 20
		tut.TextColor3 = Color3.fromRGB(170, 225, 255)
		tut.Text = "TUTORIAL (solo)"
		tut.Parent = g
		local tc = Instance.new("UICorner")
		tc.CornerRadius = UDim.new(0, 6)
		tc.Parent = tut
		local ts = Instance.new("UIStroke")
		ts.Color = Color3.fromRGB(150, 220, 255)
		ts.Thickness = 1.5
		ts.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		ts.Parent = tut
		tut.MouseButton1Click:Connect(function()
			closePicker()
			Network.GetRemoteEvent(Network.Remotes.LobbyAction):FireServer({ kind = "tutorial" })
		end)
	end
	(picker :: ScreenGui).Enabled = true
end

local function render()
	local l = list
	if not l then return end
	for _, c in ipairs(l:GetChildren()) do
		if c:IsA("TextLabel") then c:Destroy() end
	end
	local members = party.members
	if #members == 0 then members = { { userId = player.UserId, name = player.DisplayName } } end
	for _, m in ipairs(members) do
		local lead = party.leader == m.userId or (party.leader == nil and #members == 1)
		label(l, (if lead then "★ " else "• ") .. tostring(m.name) .. (if m.userId == player.UserId then "  (you)" else ""), 15,
			if lead then GOLD else Color3.fromRGB(235, 235, 235), { Size = UDim2.new(1, 0, 0, 20), Font = DOCK_FONT, TextStrokeTransparency = 1 })
	end
	local count = #members
	partyTip = function() return `Party  ({count})` end
	if partyBadge then partyBadge(count) end
	if leaveBtn then leaveBtn.Visible = #members > 1 end
end

local function notice(text: string)
	local n = noticeLabel
	if not n then return end
	n.Text = text
	n.TextTransparency, n.TextStrokeTransparency = 0, 0.4
	task.delay(3.5, function()
		if n.Text == text then
			TweenService:Create(n, TweenInfo.new(0.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
		end
	end)
end

-- ── "Interact" over everyone else in the lobby ──
local prompts: { [Player]: ProximityPrompt } = {}

local function inParty(p: Player): boolean
	for _, m in ipairs(party.members) do
		if m.userId == p.UserId then return true end
	end
	return false
end

local function refreshPrompts()
	local here = player:GetAttribute("InHub") == true
	for _, p in ipairs(Players:GetPlayers()) do
		if p == player then continue end
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
		local want = here and p:GetAttribute("InHub") == true and root ~= nil
		local pr = prompts[p]
		if want and (not pr or pr.Parent ~= root) then
			if pr then pr:Destroy() end
			local np = Instance.new("ProximityPrompt")
			np.Name = "InteractPrompt"
			np.ActionText = "Interact"
			np.ObjectText = p.DisplayName
			np.KeyboardKeyCode = Enum.KeyCode.E
			np.MaxActivationDistance = 12
			np.RequiresLineOfSight = false
			np.Parent = root
			np.Triggered:Connect(function()
				LobbySocial.OpenCard(p)
			end)
			prompts[p] = np
		elseif not want and pr then
			pr:Destroy()
			prompts[p] = nil
		end
	end
	for p, pr in pairs(prompts) do
		if not p.Parent then
			pr:Destroy()
			prompts[p] = nil
		end
	end
end

-- ── Walking the lobby in shift lock (your choice) ──
-- Off by default: the normal camera and cursor. Ctrl turns shift lock on
-- (and off again; the choice stays for your next visit): the mouse locked to
-- the screen's centre, the camera over your right shoulder. Your top half
-- turns to where you aim; your legs keep walking where you're going (W A S
-- D), so you can strafe and look about. (Shift sprints in runs; not here.)
-- It lets go by itself while a window is open (the map picker, the summon
-- page, an invite, a player's card, the menus).
local SHIFT_OFFSET = Vector3.new(1.75, 0, 0)
local TWIST_MAX = math.rad(75)  -- how far the top half turns from the legs
local BACKPEDAL = math.rad(110) -- moving further round than this from the aim: walk backwards, facing it
local lockWanted = false
local lockApplied = false
local dotGui: ScreenGui? = nil

local MODALS = { MapPicker = true, SummonScreen = true, CoopInvite = true, LobbyScreenGui = true, PlayerCard = true, BuildCodex = true, Armory = true, TalentScreen = true, StoreScreen = true }

local function modalOpen(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	for name in pairs(MODALS) do
		local g = pg:FindFirstChild(name)
		if g and g:IsA("ScreenGui") and g.Enabled then return true end
	end
	return false
end

-- (a controller's cursor follows only the lobby's own menus: not
-- LobbyScreenGui, UIManager's canvas, which can stay switched on in the
-- lobby with nothing showing)
local function padModalOpen(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	for name in pairs(MODALS) do
		if name == "LobbyScreenGui" then continue end
		local g = pg:FindFirstChild(name)
		if g and g:IsA("ScreenGui") and g.Enabled then return true end
	end
	return false
end

local function crosshairDot(on: boolean)
	if on and not dotGui then
		local g = Instance.new("ScreenGui")
		g.Name = "HubCrosshair"
		g.IgnoreGuiInset = true
		g.ResetOnSpawn = false
		g.DisplayOrder = 25
		local d = Instance.new("Frame")
		d.AnchorPoint = Vector2.new(0.5, 0.5)
		d.Position = UDim2.fromScale(0.5, 0.5)
		d.Size = UDim2.fromOffset(6, 6)
		d.BackgroundColor3 = Color3.new(1, 1, 1)
		d.BorderSizePixel = 0
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = d
		local st = Instance.new("UIStroke")
		st.Color = Color3.new(0, 0, 0)
		st.Transparency = 0.3
		st.Parent = d
		d.Parent = g
		g.Parent = player:WaitForChild("PlayerGui")
		dotGui = g
	end
	if dotGui and dotGui.Enabled ~= on then dotGui.Enabled = on end
end

-- The waist: the torso turned on the hips (RootJoint), the legs turned back
-- the other way at the hips, so they stay with the body's facing. (R6.)
type Waist = { char: Model, root: Motor6D, rootC0: CFrame, hips: { { m: Motor6D, c0: CFrame } } }
local waist: Waist? = nil
local twist = 0

local function waistOf(char: Model): Waist?
	if waist and waist.char == char then return waist end
	local root = char:FindFirstChild("HumanoidRootPart")
	local torso = char:FindFirstChild("Torso")
	local rj = root and root:FindFirstChild("RootJoint")
	if not torso or not rj or not rj:IsA("Motor6D") then return nil end
	local hips = {}
	for _, name in ipairs({ "Left Hip", "Right Hip" }) do
		local m = torso:FindFirstChild(name)
		if m and m:IsA("Motor6D") then table.insert(hips, { m = m, c0 = m.C0 }) end
	end
	waist = { char = char, root = rj, rootC0 = rj.C0, hips = hips }
	return waist
end

local function setTwist(w: Waist, a: number)
	w.root.C0 = CFrame.Angles(0, a, 0) * w.rootC0
	for _, h in ipairs(w.hips) do h.m.C0 = CFrame.Angles(0, -a, 0) * h.c0 end
end

local function untwist()
	twist = 0
	local w = waist
	if w and w.char.Parent then setTwist(w, 0) end
end

local function releaseLock()
	if not lockApplied then return end
	lockApplied = false
	untwist()
	UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	UserInputService.MouseIconEnabled = true
	crosshairDot(false)
	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.CameraOffset = Vector3.zero
		hum.AutoRotate = true
	end
end

local function lockStep(dt: number)
	local here = player:GetAttribute("InHub") == true
	local modal = here and padModalOpen()
	if player:GetAttribute("UIModal") ~= modal then player:SetAttribute("UIModal", modal) end
	local cam = workspace.CurrentCamera
	if not here or not lockWanted or modalOpen() or cam.CameraType ~= Enum.CameraType.Custom then
		releaseLock()
		return
	end
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not hum or not root or hum.Health <= 0 then return end
	lockApplied = true
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	if UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = false end
	crosshairDot(true)
	if hum.CameraOffset ~= SHIFT_OFFSET then hum.CameraOffset = SHIFT_OFFSET end
	if hum.AutoRotate then hum.AutoRotate = false end
	if root.Anchored or hum.Sit then
		untwist()
		return
	end
	local look = cam.CFrame.LookVector
	local aim = Vector3.new(look.X, 0, look.Z)
	if aim.Magnitude < 0.01 then return end
	aim = aim.Unit
	-- The legs face where you walk (or the aim, standing still or backing up).
	local move = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
	local face = aim
	if move.Magnitude > 0.1 then
		move = move.Unit
		if math.acos(math.clamp(move:Dot(aim), -1, 1)) <= BACKPEDAL then face = move end
	end
	local cur = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	cur = if cur.Magnitude > 0.01 then cur.Unit else face
	local turned = cur:Lerp(face, math.min(1, dt * 14))
	if turned.Magnitude < 0.05 then turned = face end -- (a half turn: no way round to ease)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + turned.Unit)
	-- The top half to the aim.
	local w = waistOf(char :: Model)
	if w then
		local rel = root.CFrame:VectorToObjectSpace(aim)
		local want = math.clamp(math.atan2(-rel.X, -rel.Z), -TWIST_MAX, TWIST_MAX)
		twist += (want - twist) * math.min(1, dt * 14)
		setTwist(w, twist)
	end
end

function LobbyHUD.Init(UIManager: any)
	RunService:BindToRenderStep("HubShiftLock", Enum.RenderPriority.Camera.Value + 1, function(dt: number)
		local ok, err = pcall(lockStep, dt)
		if not ok then warn("[LobbyHUD] shift lock:", err) end
	end)
	-- E: the Armory, anywhere in the lobby (not while a prompt is up: E is
	-- theirs then, talking to a player or using a station)
	local promptsUp = 0
	ProximityPromptService.PromptShown:Connect(function() promptsUp += 1 end)
	ProximityPromptService.PromptHidden:Connect(function() promptsUp = math.max(0, promptsUp - 1) end)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or player:GetAttribute("InHub") ~= true then return end
		if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
			lockWanted = not lockWanted
		end
		if input.KeyCode == Enum.KeyCode.E and promptsUp == 0 and player:GetAttribute("Forging") ~= true
			and UserInputService:GetFocusedTextBox() == nil then
			Armory.Toggle()
		end
		-- K: the skill tree
		if input.KeyCode == Enum.KeyCode.K and UserInputService:GetFocusedTextBox() == nil then TalentScreen.Toggle() end
	end)
	build()
	render()
	GuildScreen.Init()
	-- The stations whose screens open here (LobbyBuilder: OpenScreen).
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local screen = prompt:GetAttribute("OpenScreen")
		if player:GetAttribute("InHub") ~= true or typeof(screen) ~= "string" then return end
		if screen == "armory" then Armory.Open()
		elseif screen == "forge" then Armory.OpenForge()
		elseif screen == "wardrobe" then WardrobeScreen.OpenLobby("armor")
		elseif screen == "codex" then BuildCodex.Open()
		elseif screen == "guild" then GuildScreen.Open()
		end
	end)
	-- The lobby's slow motions: the fountain's crystal turning and bobbing,
	-- the portal's swirl; the podium's figures in their classes' looks.
	local ClassLook: any = nil
	pcall(function() ClassLook = require(script.Parent.Parent:WaitForChild("ClassLook")) end)
	local base: { [BasePart]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
	local dressed: { [Model]: string } = setmetatable({}, { __mode = "k" }) :: any
	local nextDress = 0
	RunService.RenderStepped:Connect(function()
		if player:GetAttribute("InHub") ~= true then return end
		local t = os.clock()
		for _, p in ipairs(CollectionService:GetTagged("LobbyCrystal")) do
			if p:IsA("BasePart") then
				base[p] = base[p] or p.CFrame
				p.CFrame = CFrame.new(base[p].Position + Vector3.new(0, math.sin(t * 1.3) * 0.8, 0)) * CFrame.Angles(0, t * 0.6, 0) * base[p].Rotation
			end
		end
		for _, p in ipairs(CollectionService:GetTagged("LobbyPortalSwirl")) do
			if p:IsA("BasePart") then
				base[p] = base[p] or p.CFrame
				p.CFrame = base[p] * CFrame.Angles(t * 0.8, 0, 0)
			end
		end
		if ClassLook and t > nextDress then
			nextDress = t + 2
			local lobby = workspace:FindFirstChild("Lobby")
			local pod = lobby and lobby:FindFirstChild("GuildPodium", true)
			if pod then
				for _, f in ipairs(pod:GetChildren()) do
					local class = f:GetAttribute("PodiumClass")
					if f:IsA("Model") and f.Name == "PodiumFigure" and typeof(class) == "string" and dressed[f] ~= class then
						dressed[f] = class
						pcall(ClassLook.Apply, f, class)
					end
				end
			end
		end
	end)
	if inviteFriendsBtn then
		local busy = false
		inviteFriendsBtn.MouseButton1Click:Connect(function()
			if busy then return end
			busy = true
			task.spawn(function()
				local ok, can = pcall(function() return SocialService:CanSendGameInviteAsync(player) end)
				if ok and can then
					local opts = Instance.new("ExperienceInviteOptions")
					opts.PromptMessage = "Meet me at the Crossroads!"
					local shown = pcall(function() SocialService:PromptGameInvite(player, opts) end)
					if not shown then notice("Couldn't open invites. Try again.") end
				else
					notice("Invites unavailable here.")
				end
				busy = false
			end)
		end)
	end
	LobbySocial.Init({
		inParty = inParty,
		isLeader = function(p: Player): boolean return party.leader == p.UserId end,
		invite = function(p: Player)
			Network.GetRemoteEvent(Network.Remotes.PartyAction):FireServer({ kind = "invite", userId = p.UserId })
			notice(`Invited {p.DisplayName} to your party.`)
		end,
	})
	Network.GetRemoteEvent(Network.Remotes.PartyState).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		party = { leader = payload.leader, members = payload.members or {} }
		render()
		refreshPrompts()
	end)
	Network.GetRemoteEvent(Network.Remotes.LobbyState).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		if payload.mode == "hub" then
			if UIManager and UIManager.EnterHub then UIManager.EnterHub() end
			-- the floating kingdom round the plaza
			if MenuBackdrop and MenuBackdrop.BuildHubSky then
				task.defer(MenuBackdrop.BuildHubSky, MapData.LOBBY_CENTER, Vector3.new(0, 0, -1))
			end
			if typeof(payload.notice) == "string" then notice(payload.notice) end
		elseif payload.mode == "pick" then
			openPicker()
		elseif payload.mode == "gacha" then
			if SummonScreen then SummonScreen.Open() end
		elseif payload.mode == "campfire" then
			closePicker()
			local map = MapData.Get(payload.mapId)
			if map then notice(`{map.name}: gather at the fire and ready up.`) end
			if UIManager and UIManager.ShowCampfireFromHub then UIManager.ShowCampfireFromHub() end
		end
	end)
	local function sync()
		local here = player:GetAttribute("InHub") == true
		-- (the summon page, opened at the tent, has the screen to itself)
		local pg = player:FindFirstChildOfClass("PlayerGui")
		local summon = pg and pg:FindFirstChild("SummonScreen")
		local busy = (summon ~= nil and summon:IsA("ScreenGui") and summon.Enabled) or player:GetAttribute("SettingsOpen") == true
			or player:GetAttribute("Forging") == true -- (the forge's minigame: ForgeMinigame)
		if gui then gui.Enabled = here and not busy end
		if not here then
			closePicker()
			TalentScreen.Close()
			StoreScreen.Close()
		end
		if MenuBackdrop and MenuBackdrop.SetInHub then MenuBackdrop.SetInHub(here) end
		refreshPrompts()
	end
	player:GetAttributeChangedSignal("InHub"):Connect(sync)
	player:GetAttributeChangedSignal("Forging"):Connect(sync)
	task.spawn(function()
		while true do
			task.wait(1)
			sync()
		end
	end)
	sync()
end

return LobbyHUD
