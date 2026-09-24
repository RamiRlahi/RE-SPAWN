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
local SettingsModal = safeRequire("SettingsModal")
local ClassSelectionScreen = safeRequire("ClassSelectionScreen")
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
local classSelectGroup: CanvasGroup

local currentSettings = SettingsConfig.CloneDefaultSettings()

local function applySettingsToRuntime(settings: any)
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

function UIManager.Init(onGameStartRequested: (classId: string) -> ())
	screenGui = Instance.new("ScreenGui")
	screenGui.Name = "LobbyScreenGui"
	screenGui.ResetOnSpawn = false
	screenGui.IgnoreGuiInset = true
	screenGui.DisplayOrder = 100
	screenGui.Parent = playerGui

	-- 1. Initialize Title Screen
	if TitleScreen then
		titleScreenGroup = TitleScreen.Create(screenGui, {
			onStartGame = function()
				UIManager.ShowClassSelect()
			end,
			onOpenSettings = function()
				UIManager.ShowSettings()
			end,
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
			end,
		})
	end

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

function UIManager.ShowSettings()
	-- Settings is a separate screen state; fully hide the title controls so the
	-- modal's translucent backdrop can't reveal them (a fade alone isn't enough -
	-- UIStrokes / rotated plaques still ghost through at GroupTransparency 1).
	if titleScreenGroup and titleScreenGroup.Visible then
		fadeCanvas(titleScreenGroup, 1, 0.15, function()
			if settingsModalGroup and settingsModalGroup.Visible then
				titleScreenGroup.Visible = false
			end
		end)
	end

	if settingsModalGroup then
		settingsModalGroup.Visible = true
		fadeCanvas(settingsModalGroup, 0, 0.2)
	end
end

function UIManager.CloseSettings()
	if settingsModalGroup then
		fadeCanvas(settingsModalGroup, 1, 0.2, function()
			settingsModalGroup.Visible = false
			if titleScreenGroup then
				titleScreenGroup.Visible = true
				fadeCanvas(titleScreenGroup, 0, 0.15)
			end
		end)
	end
end

function UIManager.ShowClassSelect()
	if LobbyCamera then
		pcall(function()
			LobbyCamera.SetClassSelectView()
		end)
	end

	if titleScreenGroup and classSelectGroup then
		fadeCanvas(titleScreenGroup, 1, 0.25, function()
			titleScreenGroup.Visible = false
			classSelectGroup.Visible = true
			fadeCanvas(classSelectGroup, 0, 0.25)
		end)
	end
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

return UIManager
