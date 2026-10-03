--!strict
--[[
	LobbyHUD.luau
	What's on screen while you walk the lobby (LobbyManager): your party (with
	the leader marked and a LEAVE PARTY button), how it works, notices (e.g.
	only the leader picks the map), and an "Interact" prompt over every other
	player in the lobby (walk up and press E: their card, to invite them, say
	hello or wave: LobbySocial, which also has the emotes and chat bubbles).

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

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local MapData = require(Shared:WaitForChild("MapData"))

local player = Players.LocalPlayer
local MenuBackdrop: any = nil
pcall(function() MenuBackdrop = require(script.Parent.Parent:WaitForChild("MenuBackdrop")) end)
local SummonScreen: any = nil
pcall(function() SummonScreen = require(script.Parent:WaitForChild("SummonScreen")) end)
local LobbySocial = require(script.Parent:WaitForChild("LobbySocial"))
local BuildCodex = require(script.Parent:WaitForChild("BuildCodex"))
local Armory = require(script.Parent:WaitForChild("Armory"))

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

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "LobbyHUD"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 30
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g

	-- The party panel (top left)
	local panel = Instance.new("Frame")
	panel.Name = "Party"
	panel.Position = UDim2.fromOffset(20, 70)
	panel.Size = UDim2.fromOffset(270, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = DARK
	panel.BackgroundTransparency = 0.25
	panel.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 8)
	c.Parent = panel
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Transparency = 0.4
	st.Parent = panel
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 10), UDim.new(0, 10)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 12), UDim.new(0, 12)
	pad.Parent = panel
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 4)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = panel
	label(panel, "THE CROSSROADS", 24, GOLD, { Size = UDim2.new(1, 0, 0, 26), LayoutOrder = 0 })
	label(panel, "YOUR PARTY", 15, PARCH, { Size = UDim2.new(1, 0, 0, 18), LayoutOrder = 1, TextTransparency = 0.2 })
	local l = Instance.new("Frame")
	l.Name = "Members"
	-- (order: the heading, YOUR PARTY, the members, LEAVE PARTY, ARMORY,
	-- INVITE FRIENDS, BUILD CODEX, the help)
	l.BackgroundTransparency = 1
	l.Size = UDim2.new(1, 0, 0, 0)
	l.AutomaticSize = Enum.AutomaticSize.Y
	l.LayoutOrder = 2
	l.Parent = panel
	local ll = Instance.new("UIListLayout")
	ll.Padding = UDim.new(0, 2)
	ll.Parent = l
	list = l
	local b = Instance.new("TextButton")
	b.Name = "Leave"
	b.LayoutOrder = 3
	b.Size = UDim2.new(1, 0, 0, 26)
	b.BackgroundColor3 = Color3.fromRGB(90, 30, 26)
	b.BackgroundTransparency = 0.2
	b.Font = FONT
	b.TextSize = 16
	b.TextColor3 = PARCH
	b.Text = "LEAVE PARTY"
	b.Visible = false
	b.Parent = panel
	local bc = Instance.new("UICorner")
	bc.CornerRadius = UDim.new(0, 6)
	bc.Parent = b
	b.MouseButton1Click:Connect(function()
		Network.GetRemoteEvent(Network.Remotes.PartyAction):FireServer({ kind = "leave" })
	end)
	leaveBtn = b
	-- Bring friends from outside the game: Roblox's own invite window (they
	-- join this server when there's room).
	local inv = Instance.new("TextButton")
	inv.Name = "InviteFriends"
	inv.LayoutOrder = 5
	inv.Size = UDim2.new(1, 0, 0, 28)
	inv.BackgroundColor3 = Color3.fromRGB(70, 52, 30)
	inv.BackgroundTransparency = 0.15
	inv.Font = FONT
	inv.TextSize = 16
	inv.TextColor3 = PARCH
	inv.Text = "INVITE FRIENDS"
	inv.Parent = panel
	local ic = Instance.new("UICorner")
	ic.CornerRadius = UDim.new(0, 6)
	ic.Parent = inv
	local is = Instance.new("UIStroke")
	is.Color = GOLD
	is.Transparency = 0.5
	is.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	is.Parent = inv
	inviteFriendsBtn = inv
	-- The Build Codex (every evolution found).
	local cdx = inv:Clone()
	cdx.Name = "Codex"
	cdx.LayoutOrder = 6
	cdx.Text = "BUILD CODEX"
	cdx.BackgroundColor3 = Color3.fromRGB(40, 34, 62)
	cdx.Parent = panel
	cdx.MouseButton1Click:Connect(function() BuildCodex.Open() end)
	-- The Armory (gear found in runs, worn for everyone to see).
	local arm = inv:Clone()
	arm.Name = "Armory"
	arm.LayoutOrder = 4
	arm.Text = "ARMORY"
	arm.BackgroundColor3 = Color3.fromRGB(86, 58, 24)
	arm.Parent = panel
	arm.MouseButton1Click:Connect(function() Armory.Open() end)
	label(panel, "Walk up to a player and press E to meet them.\n1-5: emotes (wave, cheer, point, laugh, dance).\n/ to chat.\nAt the DUNGEON gate (or the QUESTS board) press F\nto choose where to go (the leader chooses).\nAt the GACHA tent: summon.\nCtrl: shift lock on / off (off to click INVITE FRIENDS).\nM: settings.", 14, PARCH,
		{ Size = UDim2.new(1, 0, 0, 156), LayoutOrder = 7, TextWrapped = true, TextYAlignment = Enum.TextYAlignment.Top, TextTransparency = 0.15 })

	-- Notices (centre, below the top)
	local n = label(g, "", 22, PARCH, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 90),
		Size = UDim2.fromOffset(700, 34), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 1, TextStrokeTransparency = 1 })
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
		dim.MouseButton1Click:Connect(closePicker)
		label(g, "CHOOSE YOUR DUNGEON", 40, GOLD, { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.06, 0),
			Size = UDim2.fromOffset(900, 50), TextXAlignment = Enum.TextXAlignment.Center })
		label(g, "Your whole party goes together. Only the party leader chooses.", 18, PARCH, { AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.new(0.5, 0, 0.06, 50), Size = UDim2.fromOffset(900, 24), TextXAlignment = Enum.TextXAlignment.Center })
		do
			-- this week's omen (WeeklyModifiers): every run this week has it
			local WeeklyModifiers = require(Shared:WaitForChild("WeeklyModifiers"))
			local m = WeeklyModifiers.Current()
			label(g, `THIS WEEK: {m.glyph}  {m.name}  ·  {m.description}`, 16, m.color, { AnchorPoint = Vector2.new(0.5, 0),
				Position = UDim2.new(0.5, 0, 0.06, 78), Size = UDim2.fromOffset(1000, 22), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
		end
		local row = Instance.new("Frame")
		row.AnchorPoint = Vector2.new(0.5, 0.5)
		row.Position = UDim2.new(0.5, 0, 0.55, 10)
		row.Size = UDim2.fromOffset(1060, 420)
		row.BackgroundTransparency = 1
		row.Parent = g
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
		fit.Scale = math.min(1, (vp.X - 40) / 1060)
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
			local desc = label(card, map.description, 17, PARCH, { Position = UDim2.fromOffset(16, 166), Size = UDim2.new(1, -32, 0, 150), TextWrapped = true, TextScaled = true,
				TextYAlignment = Enum.TextYAlignment.Top })
			local cap = Instance.new("UITextSizeConstraint")
			cap.MaxTextSize = 17
			cap.Parent = desc
			local go = label(card, "ENTER", 24, GOLD, { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.new(1, -32, 0, 40),
				TextXAlignment = Enum.TextXAlignment.Center, BackgroundTransparency = 0.3, BackgroundColor3 = Color3.fromRGB(60, 40, 30) })
			local gc = Instance.new("UICorner")
			gc.CornerRadius = UDim.new(0, 6)
			gc.Parent = go
			card.MouseEnter:Connect(function()
				TweenService:Create(st, TweenInfo.new(0.12), { Transparency = 0, Thickness = 3 }):Play()
			end)
			card.MouseLeave:Connect(function()
				TweenService:Create(st, TweenInfo.new(0.12), { Transparency = 0.3, Thickness = 2 }):Play()
			end)
			-- (the Endless Abyss: locked until you've been deep enough)
			if map.unlockFloor then
				local lock = label(card, "", 15, Color3.fromRGB(255, 120, 120), { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -62),
					Size = UDim2.new(1, -24, 0, 34), TextXAlignment = Enum.TextXAlignment.Center, TextWrapped = true })
				local function upd()
					local best = player:GetAttribute("BestFloor") or 0
					local open = best >= map.unlockFloor
					lock.Text = if open then `Your deepest: floor {player:GetAttribute("BestEndless") or 0}` else `🔒 Reach floor {map.unlockFloor} to open (best: {best})`
					lock.TextColor3 = if open then Color3.fromRGB(210, 170, 255) else Color3.fromRGB(255, 120, 120)
				end
				upd()
				player:GetAttributeChangedSignal("BestFloor"):Connect(upd)
				player:GetAttributeChangedSignal("BestEndless"):Connect(upd)
			end
			card.MouseButton1Click:Connect(function()
				closePicker()
				Network.GetRemoteEvent(Network.Remotes.LobbyAction):FireServer({ kind = "pick", mapId = map.id })
			end)
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
		label(l, (if lead then "★ " else "• ") .. tostring(m.name) .. (if m.userId == player.UserId then "  (you)" else ""), 18,
			if lead then GOLD else PARCH, { Size = UDim2.new(1, 0, 0, 22) })
	end
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
-- D), so you can strafe and look about. (Shift itself sprints in this game.)
-- It lets go by itself while a window is open (the map picker, the summon
-- page, an invite, a player's card, the menus).
local SHIFT_OFFSET = Vector3.new(1.75, 0, 0)
local TWIST_MAX = math.rad(75)  -- how far the top half turns from the legs
local BACKPEDAL = math.rad(110) -- moving further round than this from the aim: walk backwards, facing it
local lockWanted = false
local lockApplied = false
local dotGui: ScreenGui? = nil

local MODALS = { MapPicker = true, SummonScreen = true, CoopInvite = true, LobbyScreenGui = true, PlayerCard = true, BuildCodex = true, Armory = true }

local function modalOpen(): boolean
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if not pg then return false end
	for name in pairs(MODALS) do
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
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or player:GetAttribute("InHub") ~= true then return end
		if input.KeyCode == Enum.KeyCode.LeftControl or input.KeyCode == Enum.KeyCode.RightControl then
			lockWanted = not lockWanted
		end
	end)
	build()
	render()
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
					if not shown then notice("Couldn't open the invite window. Try again in a moment.") end
				else
					notice("Invites can't be sent from here (Studio, or your privacy settings).")
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
		if gui then gui.Enabled = here and not busy end
		if not here then closePicker() end
		if MenuBackdrop and MenuBackdrop.SetInHub then MenuBackdrop.SetInHub(here) end
		refreshPrompts()
	end
	player:GetAttributeChangedSignal("InHub"):Connect(sync)
	task.spawn(function()
		while true do
			task.wait(1)
			sync()
		end
	end)
	sync()
end

return LobbyHUD
