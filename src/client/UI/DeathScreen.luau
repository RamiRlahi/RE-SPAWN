--!strict
--[[
	DeathScreen.luau
	Shown when you die in the dungeon (server: DeathManager).

	  • Two choices: REVIVE (once per run: time rewinds and you stand up where
	    you fell, run intact) or GIVE UP. With the revive spent, only GIVE UP.
	  • GIVE UP: the portal drags the body down; then, if allies still fight,
	    you SPECTATE them (‹ › cycles) with LEAVE GAME to go to the menu; if
	    no one is left, straight to the menu.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local MenuStyle = require(script.Parent:WaitForChild("MenuStyle"))

local IsometricCamera: any = nil
pcall(function()
	IsometricCamera = require(script.Parent.Parent:WaitForChild("IsometricCamera"))
end)

local player = Players.LocalPlayer
local M = MenuStyle.Colors

local DeathScreen = {}

export type Callbacks = { onMenu: () -> () }

local gui: ScreenGui
local backdrop: Frame
local panel: Frame
local title: TextLabel
local subtitle: TextLabel
local leftLabel: TextLabel
local rightLabel: TextLabel
local leftButton: GuiObject? = nil
local rightButton: GuiObject? = nil
local revivesLeft = 0 -- this run's REVIVE (DeathManager)
local spectateBar: Frame
local spectateName: TextLabel

local mode = "clear"
local alive: { number } = {}
local watching = 0 -- index into `alive`, 0 = not spectating
local shownAt = 0

local function tween(obj: Instance, t: number, props: { [string]: any })
	TweenService:Create(obj, TweenInfo.new(t, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), props):Play()
end

local function button(parent: Instance, size: UDim2, pos: UDim2, text: string, opts: any, onClick: () -> ()): TextLabel
	local b = Instance.new("TextButton")
	b.Size = size
	b.AnchorPoint = Vector2.new(0.5, 0.5)
	b.Position = pos
	b.Parent = parent
	return MenuStyle.PlaqueButton(b, text, opts, onClick)
end

-- ── Spectating ──────────────────────────────────────────────────────────────
local function watchTarget(): Player?
	local id = alive[watching]
	return if id then Players:GetPlayerByUserId(id) else nil
end

local followBody: (boolean) -> ()

local function applySpectate()
	followBody(false)
	local target = watchTarget()
	if IsometricCamera and IsometricCamera.SetFocus then
		IsometricCamera.SetFocus(if target then target.Character else nil)
	end
	spectateName.Text = if target then `SPECTATING  {string.upper(target.DisplayName)}` else "NO ONE LEFT STANDING"
end

-- The camera follows your torso as the body falls apart (and into the portal).
followBody = function(on: boolean)
	if not (IsometricCamera and IsometricCamera.SetFocusPart) then return end
	local char = player.Character
	local torso = char and (char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso"))
	IsometricCamera.SetFocusPart(if on and torso and torso:IsA("BasePart") then torso else nil)
end

local function stopSpectating()
	watching = 0
	spectateBar.Visible = false
	if IsometricCamera and IsometricCamera.SetFocus then IsometricCamera.SetFocus(nil) end
	followBody(true)
end

local function cycle(step: number)
	if #alive == 0 then return end
	watching = ((watching - 1 + step) % #alive) + 1
	applySpectate()
end

-- ── Panel ───────────────────────────────────────────────────────────────────

-- ── The void: everything black except your scattered limbs ──────────────────
-- Copies of your body parts live in a ViewportFrame over a black screen, kept
-- in step with the real ones and drawn through the real camera. Their motion
-- is recorded so a revive can play it backwards ("time rewinding").
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local voidFrame: Frame
local viewport: ViewportFrame
local vpCam: Camera
local pairsList: { { real: BasePart, copy: BasePart } } = {}
local history: { { CFrame } } = {}
local voidConn: RBXScriptConnection? = nil
local voidOn = false
local MAX_HISTORY = 360
local onLeftRef: () -> ()
local onRightRef: () -> ()

local function stopVoid(fade: boolean?)
	if voidConn then voidConn:Disconnect() voidConn = nil end
	voidOn = false
	if fade then
		tween(voidFrame, 0.5, { BackgroundTransparency = 1 })
		tween(viewport, 0.5, { ImageTransparency = 1 })
		task.delay(0.55, function()
			if not voidOn then
				voidFrame.Visible = false
				viewport:ClearAllChildren()
			end
		end)
	else
		voidFrame.Visible = false
		viewport:ClearAllChildren()
	end
end

local function startVoid()
	if voidOn then return end
	local char = player.Character
	if not char then return end
	voidOn = true
	viewport:ClearAllChildren()
	pairsList, history = {}, {}
	vpCam = Instance.new("Camera")
	vpCam.Parent = viewport
	viewport.CurrentCamera = vpCam
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
			local copy = d:Clone()
			for _, c in ipairs(copy:GetDescendants()) do
				if not (c:IsA("SpecialMesh") or c:IsA("Decal") or c:IsA("SurfaceAppearance")) then c:Destroy() end
			end
			copy.Anchored = true
			copy.Parent = viewport
			table.insert(pairsList, { real = d, copy = copy })
		end
	end
	voidFrame.Visible = true
	voidFrame.BackgroundTransparency = 1
	viewport.ImageTransparency = 0
	tween(voidFrame, 0.6, { BackgroundTransparency = 0 })
	voidConn = RunService.RenderStepped:Connect(function()
		local cam = Workspace.CurrentCamera
		vpCam.CFrame = cam.CFrame
		vpCam.FieldOfView = cam.FieldOfView
		local snap = {}
		for i, pr in ipairs(pairsList) do
			if pr.real.Parent then pr.copy.CFrame = pr.real.CFrame end
			snap[i] = pr.copy.CFrame
		end
		if #history < MAX_HISTORY then table.insert(history, snap) end
	end)
end

-- Play the recorded fall backwards: the limbs fly back together.
local function rewind(duration: number, onDone: () -> ())
	if voidConn then voidConn:Disconnect() voidConn = nil end
	local n = #history
	if n == 0 then onDone() return end
	viewport.LightColor = Color3.fromRGB(150, 220, 255)
	viewport.Ambient = Color3.fromRGB(120, 160, 200)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		-- Starts fast and gradually slows as the limbs settle back together.
		local k = 1 - (1 - a) ^ 3
		local idx = math.clamp(math.floor(n - k * (n - 1) + 0.5), 1, n)
		local snap = history[idx]
		for i, pr in ipairs(pairsList) do
			if snap[i] then pr.copy.CFrame = snap[i] end
		end
		vpCam.CFrame = Workspace.CurrentCamera.CFrame
		if a >= 1 then
			if conn then conn:Disconnect() end
			onDone()
		end
	end)
end

-- ── Heartbeat countdown (10 → 1) ─────────────────────────────────────────────
local heart: TextLabel
local heartScale: UIScale
local heartCount: TextLabel
local countdownToken = 0

local function stopCountdown()
	countdownToken += 1
	heart.Visible = false
end

local function startCountdown(onZero: () -> ())
	countdownToken += 1
	local my = countdownToken
	heart.Visible = true
	task.spawn(function()
		for n = 10, 1, -1 do
			if countdownToken ~= my then return end
			heartCount.Text = tostring(n)
			-- Lub-dub.
			heartScale.Scale = 1.28
			tween(heartScale, 0.14, { Scale = 1 })
			task.wait(0.22)
			if countdownToken ~= my then return end
			heartScale.Scale = 1.16
			tween(heartScale, 0.18, { Scale = 1 })
			task.wait(0.78)
		end
		if countdownToken == my then
			heart.Visible = false
			onZero()
		end
	end)
end

local function hideAll()
	stopSpectating()
	stopCountdown()
	stopVoid()
	gui.Enabled = false
	panel.Visible = false
end

local function showPanel()
	local fresh = not panel.Visible
	gui.Enabled = true
	spectateBar.Visible = false
	panel.Visible = true
	-- REVIVE and GIVE UP (GIVE UP alone in the middle once the revive is spent)
	local both = revivesLeft > 0
	if leftButton then leftButton.Visible = both end
	if rightButton then rightButton.Position = if both then UDim2.new(0.5, 135, 0, 300) else UDim2.new(0.5, 0, 0, 300) end
	leftLabel.Text = "REVIVE"
	rightLabel.Text = "GIVE UP"
	if revivesLeft > 0 then
		subtitle.Text = if #alive > 0 then "Your allies fight on. One revive left." else "The dungeon claims another soul. One revive left."
	elseif #alive > 0 then
		subtitle.Text = "No revives left. Your allies fight on: reach the next floor and you rise."
	else
		subtitle.Text = "No revives left. The run is over."
	end
	if not fresh then return end
	startVoid()
	backdrop.BackgroundTransparency = 1
	title.TextTransparency, title.TextStrokeTransparency = 1, 1
	tween(backdrop, 1.2, { BackgroundTransparency = 0.25 })
	tween(title, 1.4, { TextTransparency = 0, TextStrokeTransparency = 0.25 })
	-- (No timer that gives up for you: lying there, you're still in the run
	-- and come back when the party kills a boss. Giving up is your choice.)
end

local function onLeft()
	stopCountdown()
	if mode == "dead" and revivesLeft > 0 then
		-- Revive: time runs backwards and the limbs fly together, then the
		-- server stands us up where we fell (once per run).
		mode = "reviving"
		revivesLeft -= 1
		panel.Visible = false
		tween(backdrop, 0.3, { BackgroundTransparency = 1 })
		rewind(2.4, function()
			Network.GetRemoteEvent(Network.Remotes.DeathAction):FireServer("revive")
		end)
	end
end
onLeftRef = onLeft

local callbacks: Callbacks

-- Give up: the server opens a portal under the body and drags the limbs in,
-- then either sends us to spectate (allies still fighting) or clears us with
-- toMenu (see onState) and we go to the title menu.
local function onRight()
	if mode ~= "dead" then return end
	Network.GetRemoteEvent(Network.Remotes.DeathAction):FireServer("giveup")
	mode = "leaving"
	hideAll()
	gui.Enabled = true
	followBody(true)
end
onRightRef = onRight

-- Spectating after giving up: leave the game for the title menu.
local function onLeave()
	if mode ~= "spectate" then return end
	Network.GetRemoteEvent(Network.Remotes.DeathAction):FireServer("leave")
	mode = "leaving"
end

local function showSpectate()
	stopCountdown()
	panel.Visible = false
	gui.Enabled = true
	spectateBar.Visible = true
	tween(backdrop, 0.4, { BackgroundTransparency = 1 })
	stopVoid(true)
	watching = if #alive > 0 then math.clamp(if watching > 0 then watching else 1, 1, #alive) else 0
	applySpectate()
end

local function onState(msg: any)
	if typeof(msg) ~= "table" then return end
	local prev = mode
	mode = msg.mode
	alive = msg.alive or {}
	if typeof(msg.revives) == "number" then revivesLeft = msg.revives end
	if mode == "clear" then
		-- Revived: let the void fade off the standing body.
		if voidOn or voidFrame.Visible then
			stopSpectating()
			stopCountdown()
			panel.Visible = false
			stopVoid(true)
			task.delay(0.55, function()
				if mode == "clear" then gui.Enabled = false end
			end)
		else
			hideAll()
		end
		followBody(false)
		if msg.toMenu then callbacks.onMenu() end
		return
	end
	if prev == "reviving" then
		mode = "reviving"
		return
	end
	if mode == "spectate" then
		-- Gave up and allies fight on (or the last one just fell).
		showSpectate()
		return
	end
	if prev == "leaving" then
		mode = "leaving" -- the portal is already taking us; ignore updates
		return
	end
	if prev == "clear" then
		followBody(true)
		-- The world goes black around the scattered limbs straight away.
		gui.Enabled = true
		startVoid()
		-- First notice of this death: let the body fall before the screen.
		shownAt = os.clock()
		task.delay(1.2, function()
			if mode ~= "clear" and os.clock() - shownAt >= 1.1 then showPanel() end
		end)
		return
	end
	if panel.Visible then
		-- Allies fell or rose while we decide: refresh the wording.
		showPanel()
	end
end

function DeathScreen.Init(cb: Callbacks)
	callbacks = cb
	gui = Instance.new("ScreenGui")
	gui.Name = "DeathScreen"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 150
	-- Children draw over their parent (the plaque buttons put their label above
	-- the wood; with Global ordering the wood covered it).
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Enabled = false
	gui.Parent = player:WaitForChild("PlayerGui")

	voidFrame = Instance.new("Frame")
	voidFrame.Name = "Void"
	voidFrame.Size = UDim2.fromScale(1, 1)
	voidFrame.BackgroundColor3 = Color3.new(0, 0, 0)
	voidFrame.BorderSizePixel = 0
	voidFrame.Visible = false
	voidFrame.Parent = gui
	viewport = Instance.new("ViewportFrame")
	viewport.Size = UDim2.fromScale(1, 1)
	viewport.BackgroundTransparency = 1
	viewport.Ambient = Color3.fromRGB(110, 60, 60)
	viewport.LightColor = Color3.fromRGB(255, 180, 160)
	viewport.LightDirection = Vector3.new(-0.4, -1, -0.3)
	viewport.Parent = voidFrame

	backdrop = Instance.new("Frame")
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(20, 4, 4)
	backdrop.BackgroundTransparency = 1
	backdrop.BorderSizePixel = 0
	backdrop.Parent = gui
	local vignette = Instance.new("UIGradient")
	vignette.Rotation = 90
	vignette.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.35), NumberSequenceKeypoint.new(1, 0),
	})
	vignette.Parent = backdrop

	panel = Instance.new("Frame")
	panel.Size = UDim2.fromOffset(620, 380)
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.BackgroundTransparency = 1
	panel.Visible = false
	panel.Parent = gui

	title = MenuStyle.Label(panel, "GAME OVER", 76, Color3.fromRGB(255, 72, 40), {
		Size = UDim2.new(1, 0, 0, 84), Position = UDim2.fromOffset(0, 8), ZIndex = 3,
		TextStrokeColor3 = Color3.fromRGB(90, 0, 0),
	})
	-- Hot red glow behind the letters.
	local glow = Instance.new("UIStroke")
	glow.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	glow.Color = Color3.fromRGB(255, 30, 20)
	glow.Thickness = 3
	glow.Transparency = 0.35
	glow.Parent = title
	MenuStyle.Rule(panel, 100, 0.6)
	subtitle = MenuStyle.Label(panel, "", 20, M.Parchment, {
		Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 118), ZIndex = 3,
	})
	-- The heartbeat countdown between the subtitle and the buttons.
	heart = MenuStyle.Label(panel, "♥", 84, Color3.fromRGB(220, 30, 40), {
		Size = UDim2.fromOffset(110, 100), AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 158),
		ZIndex = 3, Visible = false, TextStrokeTransparency = 1, Font = Enum.Font.GothamBold,
	})
	heartScale = Instance.new("UIScale")
	heartScale.Parent = heart
	heartCount = MenuStyle.Label(heart, "5", 34, Color3.fromRGB(255, 240, 230), {
		Size = UDim2.fromScale(1, 1), Position = UDim2.fromOffset(0, -4), ZIndex = 4,
	})
	leftLabel = button(panel, UDim2.fromOffset(240, 58), UDim2.new(0.5, -135, 0, 300), "REVIVE", { ribbon = true }, onLeft)
	rightLabel = button(panel, UDim2.fromOffset(240, 58), UDim2.new(0.5, 135, 0, 300), "GIVE UP", { ornament = true }, onRight)
	leftButton = leftLabel:FindFirstAncestorWhichIsA("TextButton")
	rightButton = rightLabel:FindFirstAncestorWhichIsA("TextButton")

	-- Spectator bar along the bottom.
	spectateBar = Instance.new("Frame")
	spectateBar.Size = UDim2.fromOffset(640, 70)
	spectateBar.AnchorPoint = Vector2.new(0.5, 1)
	spectateBar.Position = UDim2.new(0.5, 0, 1, -30)
	spectateBar.Visible = false
	spectateBar.Parent = gui
	MenuStyle.Plaque(spectateBar, true)
	spectateName = MenuStyle.Label(spectateBar, "", 22, M.BrassLight, {
		Size = UDim2.new(1, -330, 1, 0), Position = UDim2.fromOffset(70, 0), ZIndex = 3, TextTruncate = Enum.TextTruncate.AtEnd,
	})
	button(spectateBar, UDim2.fromOffset(44, 44), UDim2.new(0, 38, 0.5, 0), "‹", { textSize = 28 }, function() cycle(-1) end)
	button(spectateBar, UDim2.fromOffset(44, 44), UDim2.new(1, -222, 0.5, 0), "›", { textSize = 28 }, function() cycle(1) end)
	button(spectateBar, UDim2.fromOffset(170, 44), UDim2.new(1, -100, 0.5, 0), "LEAVE GAME", {}, onLeave)

	Network.GetRemoteEvent(Network.Remotes.DeathState).OnClientEvent:Connect(onState)

	-- A free mouse cursor while there's something to click (REVIVE / GIVE UP,
	-- or the spectator bar), whatever camera you play with: the normal
	-- camera's shift lock hides the cursor and locks it to the screen's
	-- centre. ("DeathMenuOpen" tells IsometricCamera to leave it free.)
	local UserInputService = game:GetService("UserInputService")
	local wasOpen = false
	local savedIcon: boolean? = nil
	RunService.RenderStepped:Connect(function()
		local open = gui.Enabled and (panel.Visible or spectateBar.Visible)
		if open ~= wasOpen then
			wasOpen = open
			player:SetAttribute("DeathMenuOpen", if open then true else nil)
			if open then
				savedIcon = UserInputService.MouseIconEnabled
			elseif savedIcon ~= nil then
				UserInputService.MouseIconEnabled = savedIcon
				savedIcon = nil
			end
		end
		if open then
			if UserInputService.MouseBehavior ~= Enum.MouseBehavior.Default then
				UserInputService.MouseBehavior = Enum.MouseBehavior.Default
			end
			if not UserInputService.MouseIconEnabled then UserInputService.MouseIconEnabled = true end
		end
	end)
end

return DeathScreen
