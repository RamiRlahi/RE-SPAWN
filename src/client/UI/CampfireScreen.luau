--!strict
--[[
	CampfireScreen.luau
	The gathering after you confirm a class: your hero takes a seat at the
	brazier and your party (up to 4) sits around it, each in their own pose
	(MenuBackdrop draws the circle). The left column, styled like the title
	menu, lists who's here and who's ready:

	  READY UP       — toggle; when everyone still in the lobby is seated and
	                   ready, the server opens a red portal and you all walk in
	  <class>        — switch class right here (click or the < > arrows);
	                   your hero at the fire changes weapon and armor
	  SWITCH SEAT    — move round the fire (or click a seat in the scene;
	                   an occupied one swaps with whoever sits there)
	  INVITE FRIENDS — the co-op party screen (Roblox friend invites + players
	                   in this server)
	  BACK           — stand up and go back to class selection

	State comes from CampfireManager (CampfireState); MenuBackdrop gets every
	update so friends appear around the fire even on the title screen.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local MenuEntry = require(script.Parent:WaitForChild("MenuEntry"))
local TitleScreen = require(script.Parent:WaitForChild("TitleScreen"))
local CoopScreen = require(script.Parent:WaitForChild("CoopScreen"))

local MenuBackdrop: any = nil
pcall(function()
	MenuBackdrop = require(script.Parent.Parent:WaitForChild("MenuBackdrop", 5) :: any)
end)

export type Callbacks = {
	onChangeClass: () -> (),
}

local CampfireScreen = {}

local player = Players.LocalPlayer
local BRASS = MenuEntry.Colors.Brass
local BRASS_LIGHT = MenuEntry.Colors.BrassLight
local IVORY = MenuEntry.Colors.Ivory
local BOLD = MenuEntry.Bold

type Member = { userId: number, name: string, level: number?, classId: string?, seated: boolean, seat: number?, ready: boolean }
local members: { Member } = {}
local portalAt: number? = nil
local playedPortal: number? = nil
local myReady = false
local myClass: string? = nil
local mySeat: number? = nil
local thumbs: { [number]: string } = {}

local function act(payload: any)
	Network.GetRemoteEvent(Network.Remotes.CampfireAction):FireServer(payload)
end

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Text = text
	l.FontFace = BOLD
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextStrokeColor3 = Color3.fromRGB(20, 8, 4)
	l.TextStrokeTransparency = 0.55
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function thumbnail(userId: number, image: ImageLabel)
	if thumbs[userId] then
		image.Image = thumbs[userId]
		return
	end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
		end)
		if ok and url then
			thumbs[userId] = url
			image.Image = url
		end
	end)
end

function CampfireScreen.Create(parent: GuiObject, callbacks: Callbacks): CanvasGroup
	local container = Instance.new("CanvasGroup")
	container.Name = "CampfireScreen"
	container.Size = UDim2.fromScale(1, 1)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 1
	container.Visible = false
	container.Parent = parent

	local rail = Instance.new("Frame")
	rail.BackgroundTransparency = 1
	rail.Size = UDim2.new(0, 44, 1, 0)
	rail.Parent = container
	TitleScreen.Rail(rail)

	local col = Instance.new("Frame")
	col.Name = "CampfireMenu"
	col.AnchorPoint = Vector2.new(0, 0.5)
	col.Position = UDim2.new(0.035, 0, 0.5, 0)
	col.Size = UDim2.new(0.3, 0, 0, 700)
	col.BackgroundTransparency = 1
	col.Parent = container
	MenuEntry.FitHeight(col, 700)

	label(col, "THE CAMPFIRE", 34, BRASS_LIGHT, { Size = UDim2.new(1, 0, 0, 44), TextStrokeTransparency = 0.25 })
	label(col, "Gather your party. The portal opens when everyone is ready.", 14, IVORY,
		{ Size = UDim2.new(1, 0, 0, 38), Position = UDim2.fromOffset(0, 46), TextWrapped = true, TextTransparency = 0.25,
			TextYAlignment = Enum.TextYAlignment.Top })
	local rule = Instance.new("Frame")
	rule.Size = UDim2.new(1, 0, 0, 1)
	rule.Position = UDim2.fromOffset(0, 92)
	rule.BackgroundColor3 = BRASS
	rule.BorderSizePixel = 0
	rule.Parent = col
	local rg = Instance.new("UIGradient")
	rg.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	rg.Parent = rule

	-- The party roster: one row per member.
	local roster = Instance.new("Frame")
	roster.Name = "Roster"
	roster.BackgroundTransparency = 1
	roster.Position = UDim2.fromOffset(0, 104)
	roster.Size = UDim2.new(1, 0, 0, 4 * 58)
	roster.Parent = col
	local rl = Instance.new("UIListLayout")
	rl.Padding = UDim.new(0, 6)
	rl.SortOrder = Enum.SortOrder.LayoutOrder
	rl.Parent = roster

	local entries = Instance.new("Frame")
	entries.Name = "Entries"
	entries.BackgroundTransparency = 1
	entries.Position = UDim2.fromOffset(0, 104 + 4 * 58 + 18)
	entries.Size = UDim2.new(1, 0, 0, 300)
	entries.Parent = col
	local el = Instance.new("UIListLayout")
	el.Padding = UDim.new(0, 4)
	el.SortOrder = Enum.SortOrder.LayoutOrder
	el.Parent = entries

	local hint = label(col, "", 13, Color3.fromRGB(255, 150, 120), { Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(14, 104 + 4 * 58 + 18 + 300) })

	-- The classes you can switch between without leaving the fire.
	local playable: { string } = {}
	for _, id in ipairs(ClassData.Order) do
		if ClassData.IsPlayable(id) then table.insert(playable, id) end
	end
	local function className(id: string?): string
		local info = if id then ClassData.GetClass(id) else nil
		return if info then string.upper(info.name) else "—"
	end

	local readyEntry: MenuEntry.Entry
	local classEntry: MenuEntry.Entry
	local seatEntry: MenuEntry.Entry
	local inviteEntry: MenuEntry.Entry
	local backEntry: MenuEntry.Entry
	local function stepClass(dir: number)
		if portalAt or #playable == 0 then return end
		local i = table.find(playable, myClass or "") or 0
		local nextId = playable[((i - 1 + dir) % #playable) + 1]
		myClass = nextId
		classEntry.setLabel(className(nextId))
		act({ kind = "class", classId = nextId })
	end
	readyEntry = MenuEntry.Button(entries, "READY UP", "ready", 1, function()
		if portalAt then return end
		act({ kind = "ready", value = not myReady })
	end)
	-- Your class: click (or the arrows) to switch; your hero changes at the fire.
	classEntry = MenuEntry.Button(entries, "—", "class", 2, function()
		stepClass(1)
	end)
	for i, dir in ipairs({ -1, 1 }) do
		local arrow = Instance.new("TextButton")
		arrow.AnchorPoint = Vector2.new(1, 0.5)
		arrow.Position = UDim2.new(1, if i == 1 then -44 else -8, 0.5, -3)
		arrow.Size = UDim2.fromOffset(32, 32)
		arrow.BackgroundTransparency = 1
		arrow.FontFace = MenuEntry.Bold
		arrow.TextSize = 22
		arrow.TextColor3 = BRASS_LIGHT
		arrow.TextStrokeColor3 = Color3.fromRGB(20, 8, 4)
		arrow.TextStrokeTransparency = 0.2
		arrow.Text = if dir < 0 then "<" else ">"
		arrow.ZIndex = 3
		arrow.Parent = classEntry.button
		arrow.Activated:Connect(function() stepClass(dir) end)
	end
	seatEntry = MenuEntry.Button(entries, "SWITCH SEAT", "play", 3, function()
		if portalAt or not mySeat then return end
		act({ kind = "seat", seat = (mySeat % 4) + 1 })
	end)
	inviteEntry = MenuEntry.Button(entries, "INVITE FRIENDS", "invite", 4, function()
		if portalAt then return end
		CoopScreen.Open()
	end)
	backEntry = MenuEntry.Button(entries, "BACK", "quit", 5, function()
		if portalAt then return end
		act({ kind = "leave" })
		callbacks.onChangeClass()
	end)

	-- Click a seat around the fire (the empty ones glow) to move there; an
	-- occupied one swaps with whoever sits in it.
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not container.Visible or portalAt or not mySeat then return end
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 and input.UserInputType ~= Enum.UserInputType.Touch then return end
		if not MenuBackdrop or not MenuBackdrop.SeatAtScreen then return end
		local seat = MenuBackdrop.SeatAtScreen(UserInputService:GetMouseLocation())
		if seat and seat ~= mySeat then act({ kind = "seat", seat = seat }) end
	end)

	-- A red wash as the portal flares (the game's black fade follows).
	local wash = Instance.new("Frame")
	wash.Size = UDim2.fromScale(1, 1)
	wash.BackgroundColor3 = Color3.fromRGB(150, 10, 12)
	wash.BackgroundTransparency = 1
	wash.BorderSizePixel = 0
	wash.ZIndex = 50
	wash.Parent = container

	local function row(m: Member, order: number)
		local r = Instance.new("Frame")
		r.BackgroundTransparency = 1
		r.Size = UDim2.new(1, 0, 0, 52)
		r.LayoutOrder = order
		r.Parent = roster
		local head = Instance.new("ImageLabel")
		head.Size = UDim2.fromOffset(44, 44)
		head.Position = UDim2.fromOffset(6, 4)
		head.BackgroundColor3 = Color3.fromRGB(30, 22, 34)
		head.BorderSizePixel = 0
		head.Parent = r
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = head
		local st = Instance.new("UIStroke")
		st.Color = if m.ready then BRASS_LIGHT else BRASS
		st.Thickness = if m.ready then 2 else 1
		st.Transparency = if m.ready then 0 else 0.4
		st.Parent = head
		thumbnail(m.userId, head)
		local info = if m.classId then ClassData.GetClass(m.classId) else nil
		label(r, m.name .. (if m.userId == player.UserId then "  (you)" else ""), 17, IVORY,
			{ Size = UDim2.new(1, -150, 0, 22), Position = UDim2.fromOffset(60, 5), TextTruncate = Enum.TextTruncate.AtEnd })
		-- Account level, then class.
		local lv = if m.level then `LV {m.level}   •   ` else ""
		label(r, lv .. (if info then string.upper(info.name) else "CHOOSING A CLASS"), 11, BRASS,
			{ Size = UDim2.new(1, -150, 0, 16), Position = UDim2.fromOffset(60, 28), TextTransparency = if info then 0.1 else 0.45 })
		local status = if portalAt then "ENTERING" elseif m.ready then "READY" elseif m.seated then "BY THE FIRE" else "AWAY"
		label(r, status, 13, if m.ready or portalAt then BRASS_LIGHT else IVORY, {
			Size = UDim2.fromOffset(110, 20), AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
			TextXAlignment = Enum.TextXAlignment.Right, TextTransparency = if m.ready or portalAt then 0 else 0.45 })
		local under = Instance.new("Frame")
		under.AnchorPoint = Vector2.new(0, 1)
		under.Position = UDim2.new(0, 60, 1, 0)
		under.Size = UDim2.new(1, -66, 0, 1)
		under.BackgroundColor3 = BRASS
		under.BackgroundTransparency = 0.6
		under.BorderSizePixel = 0
		under.Parent = r
	end

	local function render()
		for _, c in ipairs(roster:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local list = members
		if #list == 0 then
			list = { { userId = player.UserId, name = player.DisplayName, level = player:GetAttribute("AccountLevel"), classId = nil, seated = false, ready = false } }
		end
		local readyCount, total = 0, 0
		for i, m in ipairs(list) do
			row(m, i)
			total += 1
			if m.ready then readyCount += 1 end
		end
		readyEntry.setLabel(if myReady then "YOU'RE READY" else "READY UP")
		readyEntry.setLit(myReady)
		readyEntry.setEnabled(portalAt == nil)
		classEntry.setLabel(className(myClass))
		classEntry.setEnabled(portalAt == nil)
		seatEntry.setEnabled(portalAt == nil and mySeat ~= nil)
		inviteEntry.setEnabled(portalAt == nil)
		backEntry.setEnabled(portalAt == nil)
		hint.Text = if portalAt then "The portal is open…"
			elseif total > 1 then `{readyCount} / {total} ready`
			else ""
	end

	local function onState(payload: any)
		if typeof(payload) ~= "table" then return end
		members = {}
		for _, m in ipairs(payload.members or {}) do
			if typeof(m) == "table" and typeof(m.userId) == "number" then
				table.insert(members, {
					userId = m.userId, name = tostring(m.name), level = if typeof(m.level) == "number" then m.level else nil,
					classId = if typeof(m.classId) == "string" then m.classId else nil,
					seated = m.seated == true, seat = if typeof(m.seat) == "number" then m.seat else nil, ready = m.ready == true,
				})
			end
		end
		myReady = false
		mySeat = nil
		for _, m in ipairs(members) do
			if m.userId == player.UserId then
				myReady = m.ready
				mySeat = if m.seated then m.seat else nil
				if m.classId then myClass = m.classId end
			end
		end
		portalAt = if typeof(payload.portalAt) == "number" then payload.portalAt else nil
		render()
		if MenuBackdrop and MenuBackdrop.SetCampfire then MenuBackdrop.SetCampfire(members) end
		if portalAt and playedPortal ~= portalAt then
			playedPortal = portalAt
			if MenuBackdrop and MenuBackdrop.OpenPortal then MenuBackdrop.OpenPortal(payload) end
			-- Red wash as the portal flares, just before the fade into the run.
			local seatedCount = 0
			for _, m in ipairs(members) do
				if m.seated then seatedCount += 1 end
			end
			local flareAt = (portalAt :: number) + (tonumber(payload.open) or 1.1)
				+ (tonumber(payload.stagger) or 0.5) * math.max(seatedCount - 1, 0) + (tonumber(payload.walk) or 1.9)
			task.delay(math.max(0, flareAt - Workspace:GetServerTimeNow()), function()
				wash.BackgroundTransparency = 1
				TweenService:Create(wash, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 0.25 }):Play()
			end)
		end
	end
	Network.GetRemoteEvent(Network.Remotes.CampfireState).OnClientEvent:Connect(onState)

	-- Coming back to the campfire later starts clean.
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible then
			wash.BackgroundTransparency = 1
			act({ kind = "request" })
		end
	end)

	render()
	return container
end

return CampfireScreen
