--!strict
--[[
	CoopScreen.luau
	Co-op party screen, opened from class selection (CO-OP button).

	  • Four party slots: you, then members; an empty slot is a "+" that opens
	    the invite picker.
	  • Invite picker: INVITE A FRIEND opens Roblox's friend invite (the invite
	    carries the party, so a friend who accepts lands in this server and in
	    your party), plus the players already in this server.
	  • Incoming in-server invites pop up with ACCEPT / DECLINE.

	All XP earned in the dungeon is shared across the party (server side).
	Roblox friend invites only work in the published game, not in Studio.
--]]

local Players = game:GetService("Players")
local HttpService = game:GetService("HttpService")
local SocialService = game:GetService("SocialService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local UITheme = require(Shared:WaitForChild("UITheme"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local MenuStyle = require(script.Parent:WaitForChild("MenuStyle"))

local M = MenuStyle.Colors
local player = Players.LocalPlayer

local CoopScreen = {}

local MAX_PARTY = 4

type Member = { userId: number, name: string }
local party: { leader: number?, members: { Member } } = { leader = nil, members = {} }

local gui: ScreenGui? = nil
local slotsFrame: Frame? = nil
local picker: Frame? = nil
local pickerList: ScrollingFrame? = nil
local message: TextLabel? = nil
local leaveBtn: TextButton? = nil
local invitePopup: ScreenGui? = nil
local thumbs: { [number]: string } = {}
local started = false

local function act(payload: any)
	Network.GetRemoteEvent(Network.Remotes.PartyAction):FireServer(payload)
end

local function isLeader(): boolean
	return party.leader == nil or party.leader == player.UserId
end

local function thumbnail(userId: number, image: ImageLabel)
	if thumbs[userId] then
		image.Image = thumbs[userId]
		return
	end
	task.spawn(function()
		local ok, url = pcall(function()
			return Players:GetUserThumbnailAsync(userId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size150x150)
		end)
		if ok and url then
			thumbs[userId] = url
			image.Image = url
		end
	end)
end

local function statusOf(userId: number): string
	local plr = Players:GetPlayerByUserId(userId)
	if not plr then return "Joining…" end
	local classId = plr:GetAttribute("SelectedClass")
	local info = typeof(classId) == "string" and ClassData.GetClass(classId) or nil
	if plr:GetAttribute("InLobby") == false then
		return if info then `In the dungeon · {info.name}` else "In the dungeon"
	end
	return "Choosing a class"
end

local function flash(text: string)
	if message then message.Text = text end
end

-- ─── Roblox friend invite ───────────────────────────────────────────────────
local function inviteFriend()
	local ok, canSend = pcall(function()
		return SocialService:CanSendGameInviteAsync(player)
	end)
	if not ok or not canSend then
		flash("Friend invites aren't available here — they work in the published game.")
		return
	end
	local options = Instance.new("ExperienceInviteOptions")
	options.PromptMessage = "Join my co-op run!"
	-- The friend's server reads this and puts them in our party.
	options.LaunchData = HttpService:JSONEncode({ party = party.leader or player.UserId })
	pcall(function()
		SocialService:PromptGameInvite(player, options)
	end)
end

-- ─── Rendering ──────────────────────────────────────────────────────────────
local function rebuildPicker()
	local list = pickerList
	if not list then return end
	for _, c in ipairs(list:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local inParty: { [number]: boolean } = {}
	for _, m in ipairs(party.members) do inParty[m.userId] = true end
	local order = 0
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr ~= player and not inParty[plr.UserId] then
			order += 1
			local row = Instance.new("TextButton")
			row.Size = UDim2.new(1, -6, 0, 40)
			row.LayoutOrder = order
			row.Parent = list
			local target = plr
			MenuStyle.PlaqueButton(row, `INVITE {string.upper(plr.DisplayName)}`, { textSize = 15 }, function()
				act({ kind = "invite", userId = target.UserId })
				flash(`Invite sent to {target.DisplayName}.`)
			end)
		end
	end
	if order == 0 then
		MenuStyle.Label(list, "No one else is in this server yet.", 14, M.ParchmentMuted,
			{ Size = UDim2.new(1, 0, 0, 30), LayoutOrder = 1 })
	end
end

local function openPicker()
	if not picker then return end
	if not isLeader() then
		flash("Only the party leader can invite.")
		return
	end
	rebuildPicker()
	picker.Visible = true
end

local function render(refreshPicker: boolean?)
	local frame = slotsFrame
	if not frame then return end
	for _, c in ipairs(frame:GetChildren()) do
		if c:IsA("GuiObject") then c:Destroy() end
	end
	local list = party.members
	if #list == 0 then list = { { userId = player.UserId, name = player.DisplayName } } end
	for i = 1, MAX_PARTY do
		local m = list[i]
		local slot = Instance.new("Frame")
		slot.Name = `Slot{i}`
		slot.LayoutOrder = i
		slot.Size = UDim2.fromOffset(136, 196)
		slot.Parent = frame
		MenuStyle.Plaque(slot, true)
		if m then
			local head = Instance.new("ImageLabel")
			head.Size = UDim2.fromOffset(84, 84)
			head.AnchorPoint = Vector2.new(0.5, 0)
			head.Position = UDim2.new(0.5, 0, 0, 16)
			head.BackgroundColor3 = M.Plaque
			head.BorderSizePixel = 0
			head.ZIndex = 3
			head.Parent = slot
			UITheme.AddCorner(head, 42)
			UITheme.AddStroke(head, M.Brass, 2, 0)
			thumbnail(m.userId, head)
			MenuStyle.Label(slot, m.name, 17, M.Parchment, { Size = UDim2.new(1, -12, 0, 22), Position = UDim2.fromOffset(6, 106), ZIndex = 3, TextTruncate = Enum.TextTruncate.AtEnd })
			MenuStyle.Label(slot, statusOf(m.userId), 12, M.ParchmentMuted, { Size = UDim2.new(1, -12, 0, 32), Position = UDim2.fromOffset(6, 128), TextWrapped = true, ZIndex = 3 })
			local leaderId = party.leader or player.UserId
			if m.userId == leaderId then
				local tag = MenuStyle.Label(slot, "LEADER", 12, M.Parchment, { Size = UDim2.fromOffset(70, 18), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 1, -28), BackgroundTransparency = 0, BackgroundColor3 = M.Crimson, ZIndex = 3 })
				UITheme.AddStroke(tag, Color3.fromRGB(59, 16, 12), 1, 0.2)
			elseif isLeader() then
				local kick = Instance.new("TextButton")
				kick.Size = UDim2.fromOffset(96, 26)
				kick.AnchorPoint = Vector2.new(0.5, 0)
				kick.Position = UDim2.new(0.5, 0, 1, -34)
				kick.ZIndex = 3
				kick.Parent = slot
				local target = m.userId
				MenuStyle.PlaqueButton(kick, "REMOVE", { textSize = 13 }, function()
					act({ kind = "kick", userId = target })
				end)
			end
		else
			local plus = Instance.new("TextButton")
			plus.Size = UDim2.new(1, -24, 1, -24)
			plus.Position = UDim2.fromOffset(12, 12)
			plus.ZIndex = 3
			plus.Parent = slot
			MenuStyle.PlaqueButton(plus, "+", { textSize = 64 }, openPicker)
		end
	end
	if leaveBtn then leaveBtn.Visible = #party.members > 1 end
	if refreshPicker and picker and picker.Visible then rebuildPicker() end
end

-- ─── Build ──────────────────────────────────────────────────────────────────
local function build(): ScreenGui
	local sg = Instance.new("ScreenGui")
	sg.Name = "CoopScreen"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 120
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Enabled = false
	sg.Parent = player:WaitForChild("PlayerGui")

	local shade = Instance.new("Frame")
	shade.Size = UDim2.fromScale(1, 1)
	shade.BackgroundColor3 = Color3.fromRGB(10, 6, 5)
	shade.BackgroundTransparency = 0.4
	shade.BorderSizePixel = 0
	shade.Active = true -- swallow clicks meant for the scene behind
	shade.Parent = sg

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(660, 420)
	panel.Parent = sg
	MenuStyle.Plaque(panel)

	MenuStyle.Label(panel, "CO-OP PARTY", 32, M.BrassLight, { Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 16),
		TextStrokeColor3 = Color3.fromRGB(36, 8, 3), TextStrokeTransparency = 0.1 })
	MenuStyle.Rule(panel, 60, 0.4)
	MenuStyle.Label(panel, "Everyone in your party shares all XP earned in the dungeon.", 15, M.Parchment,
		{ Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 74) })

	local slots = Instance.new("Frame")
	slots.BackgroundTransparency = 1
	slots.AnchorPoint = Vector2.new(0.5, 0)
	slots.Position = UDim2.new(0.5, 0, 0, 108)
	slots.Size = UDim2.new(1, -40, 0, 200)
	slots.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 14)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = slots
	slotsFrame = slots

	message = MenuStyle.Label(panel, "", 13, Color3.fromRGB(235, 150, 120), { Size = UDim2.new(1, -40, 0, 18), Position = UDim2.new(0, 20, 1, -82) })

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 1)
	close.Position = UDim2.new(1, -24, 1, -18)
	close.Size = UDim2.fromOffset(170, 48)
	close.Parent = panel
	MenuStyle.PlaqueButton(close, "CLOSE", { ribbon = true }, function()
		CoopScreen.Close()
	end)

	local leave = Instance.new("TextButton")
	leave.AnchorPoint = Vector2.new(0, 1)
	leave.Position = UDim2.new(0, 24, 1, -18)
	leave.Size = UDim2.fromOffset(190, 48)
	leave.Visible = false
	leave.Parent = panel
	MenuStyle.PlaqueButton(leave, "LEAVE PARTY", {}, function()
		act({ kind = "leave" })
	end)
	leaveBtn = leave

	-- Invite picker (over the panel).
	local pick = Instance.new("Frame")
	pick.AnchorPoint = Vector2.new(0.5, 0.5)
	pick.Position = UDim2.fromScale(0.5, 0.5)
	pick.Size = UDim2.fromOffset(420, 380)
	pick.Visible = false
	pick.ZIndex = 10
	pick.Parent = sg
	MenuStyle.Plaque(pick)
	MenuStyle.Label(pick, "INVITE", 26, M.BrassLight, { Size = UDim2.new(1, 0, 0, 34), Position = UDim2.fromOffset(0, 14), ZIndex = 11 })
	local friendBtn = Instance.new("TextButton")
	friendBtn.AnchorPoint = Vector2.new(0.5, 0)
	friendBtn.Position = UDim2.new(0.5, 0, 0, 58)
	friendBtn.Size = UDim2.new(1, -48, 0, 50)
	friendBtn.ZIndex = 11
	friendBtn.Parent = pick
	MenuStyle.PlaqueButton(friendBtn, "INVITE A FRIEND", { ribbon = true, ornament = true }, inviteFriend)
	MenuStyle.Label(pick, "PLAYERS IN THIS SERVER", 14, M.BrassLight, { Size = UDim2.new(1, -48, 0, 18), Position = UDim2.fromOffset(24, 124),
		TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11 })
	local list = Instance.new("ScrollingFrame")
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.fromOffset(24, 148)
	list.Size = UDim2.new(1, -48, 1, -224)
	list.ScrollBarThickness = 4
	list.ScrollBarImageColor3 = M.Brass
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.new()
	list.ZIndex = 11
	list.Parent = pick
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 8)
	ll.SortOrder = Enum.SortOrder.LayoutOrder
	ll.Parent = list
	pickerList = list
	local back = Instance.new("TextButton")
	back.AnchorPoint = Vector2.new(0.5, 1)
	back.Position = UDim2.new(0.5, 0, 1, -16)
	back.Size = UDim2.fromOffset(160, 44)
	back.ZIndex = 11
	back.Parent = pick
	MenuStyle.PlaqueButton(back, "BACK", {}, function()
		pick.Visible = false
	end)
	picker = pick

	return sg
end

-- ─── Incoming invites ───────────────────────────────────────────────────────
local function showInvite(fromUserId: number, fromName: string)
	if invitePopup then invitePopup:Destroy() end
	local sg = Instance.new("ScreenGui")
	sg.Name = "CoopInvite"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.DisplayOrder = 130
	sg.Parent = player:WaitForChild("PlayerGui")
	invitePopup = sg

	local box = Instance.new("Frame")
	box.Size = UDim2.fromOffset(440, 130)
	box.Parent = sg
	if player:GetAttribute("InLobby") == false then
		-- In a run: out of the way, sliding in at the bottom right.
		box.AnchorPoint = Vector2.new(1, 1)
		box.Position = UDim2.new(1, 460, 1, -150)
		game:GetService("TweenService"):Create(box, TweenInfo.new(0.35, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
			{ Position = UDim2.new(1, -24, 1, -150) }):Play()
	else
		box.AnchorPoint = Vector2.new(0.5, 0)
		box.Position = UDim2.new(0.5, 0, 0, 90)
	end
	MenuStyle.Plaque(box)
	MenuStyle.Label(box, `{fromName} invites you to their co-op party`, 18, M.Parchment,
		{ Size = UDim2.new(1, -30, 0, 44), Position = UDim2.fromOffset(15, 12), TextWrapped = true })
	local function button(text: string, x: number, onClick: () -> ())
		local b = Instance.new("TextButton")
		b.AnchorPoint = Vector2.new(0.5, 1)
		b.Position = UDim2.new(0.5, x, 1, -14)
		b.Size = UDim2.fromOffset(170, 46)
		b.Parent = box
		MenuStyle.PlaqueButton(b, text, { ribbon = text == "ACCEPT" }, onClick)
	end
	button("ACCEPT", -95, function()
		act({ kind = "accept", userId = fromUserId })
		sg:Destroy()
	end)
	button("DECLINE", 95, function()
		act({ kind = "decline", userId = fromUserId })
		sg:Destroy()
	end)
	task.delay(60, function()
		if sg.Parent then sg:Destroy() end
	end)
end

-- ─── Public API ─────────────────────────────────────────────────────────────
function CoopScreen.Init()
	if started then return end
	started = true
	Network.GetRemoteEvent(Network.Remotes.PartyState).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		party = { leader = payload.leader, members = payload.members or {} }
		render(true)
	end)
	Network.GetRemoteEvent(Network.Remotes.PartyInvite).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) == "table" and typeof(payload.fromUserId) == "number" then
			showInvite(payload.fromUserId, tostring(payload.fromName))
		end
	end)
	-- The picker lists who's in this server.
	local function refreshPicker()
		if picker and picker.Visible then rebuildPicker() end
	end
	Players.PlayerAdded:Connect(refreshPicker)
	Players.PlayerRemoving:Connect(function()
		task.defer(refreshPicker)
	end)
	-- Keep member statuses (choosing / in the dungeon) fresh while open.
	task.spawn(function()
		while true do
			task.wait(1)
			if gui and gui.Enabled then render() end
		end
	end)
	act({ kind = "request" })
end

function CoopScreen.Open()
	CoopScreen.Init()
	if not gui then gui = build() end
	flash("")
	render()
	if gui then gui.Enabled = true end
end

function CoopScreen.Close()
	if picker then picker.Visible = false end
	if gui then gui.Enabled = false end
end

return CoopScreen
