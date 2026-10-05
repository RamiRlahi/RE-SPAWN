local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local Network = require(Shared:WaitForChild("Network"))

local function safeRequire(childName: string)
	local child = script.Parent:WaitForChild(childName, 5)
	if not child then
		warn(`[UIManager] Could not find child module: {childName}`)
		return nil
	end
	local ok, res = pcall(function()
		return require(child)
	end)
	if not ok then
		warn(`[UIManager ERROR] Failed requiring {childName}:`, res)
		return nil
	end
	return res
end

local TitleScreen = safeRequire("TitleScreen")
local SettingsModal = safeRequire("SettingsModal") -- in a run: the glass panel in the world
local MenuSettingsModal = safeRequire("MenuSettingsModal") -- on the title screen: the menu-styled window
local ClassSelectionScreen = safeRequire("ClassSelectionScreen")
local CampfireScreen = safeRequire("CampfireScreen")
local MinimapUI = safeRequire("MinimapUI")
local GameHUD = safeRequire("GameHUD")

local SkillController: any = nil
pcall(function()
	SkillController = require(script.Parent.Parent:WaitForChild("SkillController"))
end)

local LobbyCamera: any = nil
pcall(function()
	LobbyCamera = require(script.Parent.Parent:WaitForChild("LobbyCamera"))
end)

local UIManager = {}

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui

local screenGui: ScreenGui
local titleScreenGroup: CanvasGroup
local settingsModalGroup: CanvasGroup
local menuSettingsGroup: CanvasGroup? = nil
local menuSettingsStale = false -- (settings changed in a run: rebuild before showing)
local buildMenuSettings: () -> ()
local classSelectGroup: CanvasGroup
local campfireGroup: CanvasGroup? = nil

local currentSettings = SettingsConfig.CloneDefaultSettings()

-- Graphics settings, held on this client (lighting presets change on the way
-- in and out of the dungeon, so they're re-applied every second).
local function applyGraphics(settings: any)
	local Lighting = game:GetService("Lighting")
	-- (performance mode, switched on when the frame rate stays low: no shadows)
	local shadows = not (settings and settings.shadows == false) and player:GetAttribute("PerfMode") ~= true
	local bloom = not (settings and settings.bloom == false)
	if Lighting.GlobalShadows ~= shadows then Lighting.GlobalShadows = shadows end
	for _, e in ipairs(Lighting:GetChildren()) do
		-- No bloom anywhere (it smeared lights together); the setting now only
		-- turns the sun rays on or off.
		if e:IsA("BloomEffect") and e.Enabled then e.Enabled = false end
		if e:IsA("SunRaysEffect") and e.Enabled ~= bloom then e.Enabled = bloom end
	end
end

local function applySettingsToRuntime(settings: any)
	applyGraphics(settings)
	-- Read by the character script (sprint toggle vs hold).
	player:SetAttribute("Setting_toggleSprint", not (settings and settings.toggleSprint == false))
	-- Read by SkillController (teammates' ult cutscenes on your screen or not).
	player:SetAttribute("Setting_teammateCinematics", not (settings and settings.teammateCinematics == false))
	-- Read by IsometricCamera (top-down or a normal third-person camera).
	player:SetAttribute("Setting_classicCamera", settings ~= nil and settings.classicCamera == true)
	player:SetAttribute("Setting_lowDetailVFX", settings ~= nil and settings.lowDetailVFX == true)
	-- Read by SkillController (ranged basic attacks firing by themselves).
	player:SetAttribute("Setting_autoFire", not (settings and settings.autoFire == false))
	-- Read by MusicController.
	player:SetAttribute("Setting_musicVolume", if settings and typeof(settings.musicVolume) == "number" then settings.musicVolume else 0.6)
	if settings and settings.keybinds then
		for action, key in pairs(settings.keybinds) do
			player:SetAttribute(`Keybind_{action}`, key)
		end
	end

	if GameHUD and GameHUD.SetKeybinds then
		pcall(function()
			GameHUD.SetKeybinds(settings and settings.keybinds)
		end)
	end

	if SkillController and SkillController.SetKeybinds then
		pcall(function()
			SkillController.SetKeybinds(settings and settings.keybinds)
		end)
	end
end

local function fadeCanvas(group: CanvasGroup, targetTrans: number, duration: number?, onComplete: (() -> ())?)
	if not group then return end
	local tween = TweenService:Create(
		group,
		TweenInfo.new(duration or 0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ GroupTransparency = targetTrans }
	)
	if onComplete then
		tween.Completed:Once(function()
			onComplete()
		end)
	end
	tween:Play()
end

-- QUIT: a small "leave?" confirmation over the title screen. Roblox can't close
-- the app from a game, so leaving takes you out of the server with a farewell.
local quitDialog: Frame? = nil
local function showQuitConfirm()
	if quitDialog then
		quitDialog.Visible = true
		return
	end
	local MenuEntry = safeRequire("MenuEntry")
	local overlay = Instance.new("TextButton") -- swallows clicks behind it
	overlay.Name = "QuitConfirm"
	overlay.Text = ""
	overlay.AutoButtonColor = false
	overlay.Size = UDim2.fromScale(1, 1)
	overlay.BackgroundColor3 = Color3.fromRGB(4, 3, 8)
	overlay.BackgroundTransparency = 0.35
	overlay.ZIndex = 50
	overlay.Parent = screenGui
	quitDialog = overlay

	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(380, 250)
	panel.BackgroundColor3 = Color3.fromRGB(16, 11, 20)
	panel.BackgroundTransparency = 0.1
	panel.ZIndex = 51
	panel.Parent = overlay
	UITheme.AddCorner(panel, 6)
	UITheme.AddStroke(panel, Color3.fromRGB(194, 132, 52), 1.5, 0.2)

	local title = Instance.new("TextLabel")
	title.BackgroundTransparency = 1
	title.Position = UDim2.fromOffset(0, 18)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.FontFace = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
	title.TextSize = 22
	title.TextColor3 = Color3.fromRGB(255, 213, 128)
	title.Text = "LEAVE RE:SPAWN?"
	title.ZIndex = 52
	title.Parent = panel

	local list = Instance.new("Frame")
	list.BackgroundTransparency = 1
	list.Position = UDim2.fromOffset(40, 70)
	list.Size = UDim2.new(1, -80, 0, 130)
	list.ZIndex = 52
	list.Parent = panel
	local layout = Instance.new("UIListLayout")
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, 6)
	layout.Parent = list

	if MenuEntry then
		MenuEntry.Button(list, "LEAVE", "quit", 1, function()
			player:Kick("Thanks for playing RE:SPAWN. See you soon!")
		end)
		MenuEntry.Button(list, "STAY", "play", 2, function()
			overlay.Visible = false
		end)
	end
	for _, d in ipairs(panel:GetDescendants()) do
		if d:IsA("GuiObject") and d.ZIndex < 52 then d.ZIndex = 52 end
	end
end

function UIManager.Init(onGameStartRequested: (classId: string) -> ())
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = playerGui
	task.spawn(function()
		while true do
			task.wait(1)
			pcall(applyGraphics, currentSettings)
		end
	end)

	-- The Toggle Menu key (default M, rebindable) in the dungeon and on the
	-- lobby plaza: the settings window (angled, in the world). (Not Escape: Roblox keeps that for its
	-- own menu and a game can't take it over.)
	game:GetService("UserInputService").InputBegan:Connect(function(input: InputObject, processed: boolean)
		if processed or game:GetService("UserInputService"):GetFocusedTextBox() then return end
		-- (not while the settings window is waiting for a new key)
		if settingsModalGroup and settingsModalGroup:GetAttribute("Listening") == true then return end
		local keyName = (currentSettings and currentSettings.keybinds and currentSettings.keybinds.OpenMenu) or "M"
		if input.KeyCode.Name ~= keyName then return end
		UIManager.ToggleInGameSettings()
	end)

	-- 1. Initialize Title Screen
	if TitleScreen then
		titleScreenGroup = TitleScreen.Create(screenGui, {
			onStartGame = function()
				UIManager.ShowClassSelect()
			end,
			onOpenSettings = function()
				UIManager.ShowSettings()
			end,
			onQuit = showQuitConfirm,
		})
	end

	-- 2. Initialize Settings Modal
	if SettingsModal then
		settingsModalGroup = SettingsModal.Create(screenGui, currentSettings, {
			onClose = function()
				UIManager.CloseSettings()
			end,
			onSave = function(newSettings)
				currentSettings = newSettings
				applySettingsToRuntime(currentSettings)
				local saveRemote = Network.GetRemoteEvent(Network.Remotes.SaveSettings)
				saveRemote:FireServer(newSettings)
				menuSettingsStale = true
			end,
		})
	end
	-- The title screen's window (menu style); it holds its own copy of the
	-- settings, so it's rebuilt when they changed in a run.
	buildMenuSettings = function()
		if not MenuSettingsModal then return end
		if menuSettingsGroup then menuSettingsGroup:Destroy() end
		menuSettingsStale = false
		menuSettingsGroup = MenuSettingsModal.Create(screenGui, currentSettings, {
			onClose = function()
				UIManager.CloseSettings()
			end,
			onSave = function(newSettings)
				currentSettings = newSettings
				applySettingsToRuntime(currentSettings)
				local saveRemote = Network.GetRemoteEvent(Network.Remotes.SaveSettings)
				saveRemote:FireServer(newSettings)
				if SettingsModal and settingsModalGroup then SettingsModal.Reload(settingsModalGroup, currentSettings) end
			end,
		})
	end
	buildMenuSettings()

	-- 3. Initialize Class Selection Screen
	if ClassSelectionScreen then
		classSelectGroup = ClassSelectionScreen.Create(screenGui, {
			onBackToTitle = function()
				UIManager.ShowTitle()
			end,
			onConfirmClass = function(classId: string)
				local selectRemote = Network.GetRemoteEvent(Network.Remotes.SelectClass)
				selectRemote:FireServer(classId)
				onGameStartRequested(classId)
				-- Into the lobby: the server answers with LobbyState "hub"
				-- (UIManager.EnterHub); a map's gate leads on to the campfire.
			end,
		})
	end

	-- 3b. The campfire: the party gathers, readies up and leaves by portal.
	if CampfireScreen then
		campfireGroup = CampfireScreen.Create(screenGui, {
			onChangeClass = function()
				-- BACK: stand up and walk the lobby again
				Network.GetRemoteEvent(Network.Remotes.LobbyAction):FireServer({ kind = "toHub" })
			end,
		})
	end

	-- 4. Initialize Minimap Overlay
	if MinimapUI then
		pcall(function()
			MinimapUI.Init()
		end)
	end

	-- 5. Initialize Game HUD (hidden until game starts)
	if GameHUD then
		pcall(function()
			GameHUD.Init()
			GameHUD.SetKeybinds(currentSettings.keybinds)
			GameHUD.SetVisible(false)
		end)
	end
	applySettingsToRuntime(currentSettings)

	-- The settings saved on this account (PlayerData, via the server): they
	-- replace the defaults as soon as they arrive.
	local syncRemote = Network.GetRemoteEvent(Network.Remotes.SettingsSync)
	syncRemote.OnClientEvent:Connect(function(saved: any)
		if typeof(saved) ~= "table" then return end
		currentSettings = SettingsConfig.Sanitize(saved)
		applySettingsToRuntime(currentSettings)
		if GameHUD then pcall(GameHUD.SetKeybinds, currentSettings.keybinds) end
		if SettingsModal and settingsModalGroup then pcall(SettingsModal.Reload, settingsModalGroup, currentSettings) end
		-- (the title screen's window holds its own copy: rebuilt)
		pcall(buildMenuSettings)
	end)
	syncRemote:FireServer()

	-- Start on Title Screen
	if titleScreenGroup then
		titleScreenGroup.Visible = true
		titleScreenGroup.GroupTransparency = 0
	end
end

function UIManager.ShowTitle()
	if settingsModalGroup then
		settingsModalGroup.Visible = false
		settingsModalGroup.GroupTransparency = 1
	end
	if menuSettingsGroup then
		menuSettingsGroup.Visible = false
		menuSettingsGroup.GroupTransparency = 1
	end

	if LobbyCamera then
		pcall(function()
			LobbyCamera.StartTitleMode()
		end)
	end

	if classSelectGroup and titleScreenGroup then
		fadeCanvas(classSelectGroup, 1, 0.25, function()
			classSelectGroup.Visible = false
			titleScreenGroup.Visible = true
			fadeCanvas(titleScreenGroup, 0, 0.25)
		end)
	end
end

local inGameSettings = false -- opened with Escape during a run (the menu UI is off)
local inHub = false -- walking the lobby plaza (its settings open in the world too)

function UIManager.ShowSettings()
	if player:GetAttribute("InLobby") == false or inHub then
		-- In the dungeon (or walking the lobby): just the settings window over the game.
		inGameSettings = true
		screenGui.Enabled = true
		if settingsModalGroup then
			settingsModalGroup.Visible = true
			fadeCanvas(settingsModalGroup, 0, 0.2)
		end
		return
	end
	-- Settings is a separate screen state; fully hide the title controls so the
	-- modal's translucent backdrop can't reveal them (a fade alone isn't enough -
	-- UIStrokes / rotated plaques still ghost through at GroupTransparency 1).
	if menuSettingsStale or not menuSettingsGroup then buildMenuSettings() end
	local menuGroup = menuSettingsGroup
	if not menuGroup then return end
	if titleScreenGroup and titleScreenGroup.Visible then
		fadeCanvas(titleScreenGroup, 1, 0.15, function()
			if menuGroup.Visible then
				titleScreenGroup.Visible = false
			end
		end)
	end
	menuGroup.Visible = true
	fadeCanvas(menuGroup, 0, 0.2)
end

function UIManager.CloseSettings()
	if inGameSettings then
		inGameSettings = false
		if settingsModalGroup then
			fadeCanvas(settingsModalGroup, 1, 0.2, function()
				settingsModalGroup.Visible = false
				if player:GetAttribute("InLobby") == false or inHub then screenGui.Enabled = false end
			end)
		end
		return
	end
	local menuGroup = menuSettingsGroup
	if menuGroup then
		fadeCanvas(menuGroup, 1, 0.2, function()
			menuGroup.Visible = false
			if titleScreenGroup then
				titleScreenGroup.Visible = true
				fadeCanvas(titleScreenGroup, 0, 0.15)
			end
		end)
	end
end

function UIManager.ShowClassSelect()
	-- The class preview is on the hero standing in the menu scene; the camera
	-- just eases in front of it.
	if LobbyCamera then
		pcall(function()
			LobbyCamera.StartHeroMode()
		end)
	end

	-- From the title or back from the campfire.
	local from = if campfireGroup and campfireGroup.Visible then campfireGroup else titleScreenGroup
	if from and classSelectGroup then
		fadeCanvas(from, 1, 0.25, function()
			from.Visible = false
			classSelectGroup.Visible = true
			fadeCanvas(classSelectGroup, 0, 0.25)
		end)
	end
end

function UIManager.ShowCampfire()
	if LobbyCamera then
		pcall(function()
			LobbyCamera.StartCampfireMode()
		end)
	end
	local group = campfireGroup
	if group and classSelectGroup then
		fadeCanvas(classSelectGroup, 1, 0.25, function()
			classSelectGroup.Visible = false
			group.Visible = true
			fadeCanvas(group, 0, 0.35)
		end)
	end
end

-- ── The lobby (walk around as your class, party up, pick a map) ──
local hubFade: Frame? = nil

local function fadeFlash(then_: () -> ())
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = Color3.new(0, 0, 0)
	f.BackgroundTransparency = 1
	f.ZIndex = 999
	f.Parent = screenGui
	hubFade = f
	screenGui.Enabled = true
	local tIn = TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Sine), { BackgroundTransparency = 0 })
	tIn.Completed:Once(function()
		then_()
		task.wait(0.15)
		local tOut = TweenService:Create(f, TweenInfo.new(0.5, Enum.EasingStyle.Sine), { BackgroundTransparency = 1 })
		tOut.Completed:Once(function() f:Destroy() end)
		tOut:Play()
	end)
	tIn:Play()
end

-- Into the lobby: the menus give way to the plaza; the camera follows you.
function UIManager.EnterHub()
	if inHub then return end
	inHub = true
	fadeFlash(function()
		if titleScreenGroup then titleScreenGroup.Visible = false end
		if classSelectGroup then classSelectGroup.Visible = false end
		if menuSettingsGroup then menuSettingsGroup.Visible = false end
		if campfireGroup then
			campfireGroup.Visible = false
			campfireGroup.GroupTransparency = 1
		end
		if LobbyCamera then pcall(function() LobbyCamera.StopImmediate() end) end
		local cam = workspace.CurrentCamera
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		cam.CameraType = Enum.CameraType.Custom
		cam.FieldOfView = 70
		if hum then cam.CameraSubject = hum end
		game:GetService("UserInputService").MouseIconEnabled = true
		-- (the plaza has no menu UI on screen; its own HUD is LobbyHUD)
		task.delay(0.6, function()
			if inHub and not (hubFade and hubFade.Parent) then screenGui.Enabled = false end
		end)
	end)
end

-- From the lobby's gate to the campfire platform (ready up for the run).
function UIManager.ShowCampfireFromHub()
	inHub = false
	fadeFlash(function()
		screenGui.Enabled = true
		if LobbyCamera then pcall(function() LobbyCamera.StartCampfireMode() end) end
		local group = campfireGroup
		if group then
			if classSelectGroup then classSelectGroup.Visible = false end
			group.Visible = true
			fadeCanvas(group, 0, 0.35)
		end
	end)
end

function UIManager.InHub(): boolean
	return inHub
end

function UIManager.FadeOutToGame(onComplete: (() -> ())?)
	local fadeOverlay = Instance.new("Frame")
	fadeOverlay.Name = "GameTransitionFade"
	fadeOverlay.Size = UDim2.new(1, 0, 1, 0)
	fadeOverlay.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
	fadeOverlay.BackgroundTransparency = 1
	fadeOverlay.ZIndex = 999
	fadeOverlay.Parent = screenGui

	local fadeIn = TweenService:Create(fadeOverlay, TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.In), {
		BackgroundTransparency = 0,
	})

	fadeIn.Completed:Once(function()
		if titleScreenGroup then titleScreenGroup.Visible = false end
		if classSelectGroup then classSelectGroup.Visible = false end
		if settingsModalGroup then settingsModalGroup.Visible = false end
		if menuSettingsGroup then menuSettingsGroup.Visible = false end
		if campfireGroup then
			campfireGroup.Visible = false
			campfireGroup.GroupTransparency = 1
		end

		-- Wait until character has actually teleported/spawned into the map
		task.spawn(function()
			local startWait = os.clock()
			while (player:GetAttribute("InLobby") ~= false or player:GetAttribute("SpawnedInMap") ~= true) and (os.clock() - startWait < 5.0) do
				task.wait(0.1)
			end

			if onComplete then
				onComplete()
			end

			-- Reveal HUD and Minimap only after spawning into the map
			if GameHUD then
				pcall(function()
					GameHUD.SetVisible(true)
				end)
			end
			if MinimapUI then
				pcall(function()
					MinimapUI.SetVisible(true)
				end)
			end

			task.wait(0.2)
			local fadeOut = TweenService:Create(fadeOverlay, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), {
				BackgroundTransparency = 1,
			})
			fadeOut.Completed:Once(function()
				fadeOverlay:Destroy()
				screenGui.Enabled = false
			end)
			fadeOut:Play()
		end)
	end)

	fadeIn:Play()
end

-- Back to the title menu (after dying): hide the HUD, show the lobby again.
-- The Toggle Menu key during a run opens / closes the settings window.
function UIManager.ToggleInGameSettings()
	if player:GetAttribute("InLobby") ~= false and not inHub then return end
	if settingsModalGroup and settingsModalGroup.Visible then
		UIManager.CloseSettings()
	else
		UIManager.ShowSettings()
	end
end

function UIManager.ReturnToMenu()
	inGameSettings = false
	inHub = false
	if GameHUD then pcall(function() GameHUD.SetVisible(false) end) end
	if MinimapUI then pcall(function() MinimapUI.SetVisible(false) end) end
	screenGui.Enabled = true
	if classSelectGroup then classSelectGroup.Visible = false end
	if settingsModalGroup then settingsModalGroup.Visible = false end
	if menuSettingsGroup then menuSettingsGroup.Visible = false end
	if campfireGroup then campfireGroup.Visible = false end
	if LobbyCamera then pcall(function() LobbyCamera.StartTitleMode() end) end
	if titleScreenGroup then
		titleScreenGroup.Visible = true
		titleScreenGroup.GroupTransparency = 1
		fadeCanvas(titleScreenGroup, 0, 0.4)
	end
end

return UIManager
