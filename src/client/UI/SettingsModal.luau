local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))

export type SettingsModalCallbacks = {
	onClose: () -> (),
	onSave: (settings: any) -> (),
}

local SettingsModal = {}

-- Medieval guild-hall palette, matching TitleScreen (wood / brass / parchment).
local BRASS = Color3.fromRGB(194, 132, 52)
local BRASS_LIGHT = Color3.fromRGB(255, 213, 128)
local PLAQUE = Color3.fromRGB(37, 28, 24)
local PLAQUE_DARK = Color3.fromRGB(17, 13, 13)
local WOOD_MID = Color3.fromRGB(64, 47, 37)
local PARCHMENT = Color3.fromRGB(239, 213, 170)
local ANTIQUE = Enum.Font.Antique

function SettingsModal.Create(
	parent: GuiObject,
	currentSettings: any,
	callbacks: SettingsModalCallbacks
): CanvasGroup
	local workingSettings: any = SettingsConfig.CloneDefaultSettings()
	if currentSettings and typeof(currentSettings) == "table" then
		for k, v in pairs(currentSettings) do
			if typeof(v) == "table" then
				local t = {}
				for subK, subV in pairs(v) do
					t[subK] = subV
				end
				workingSettings[k] = t
			else
				workingSettings[k] = v
			end
		end
	end

	local container = Instance.new("CanvasGroup")
	container.Name = "SettingsModal"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 1
	container.Visible = false
	container.Parent = parent

	-- Dim Backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = PLAQUE_DARK
	backdrop.BackgroundTransparency = 0.45
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = container

	backdrop.MouseButton1Click:Connect(function()
		callbacks.onClose()
	end)

	-- Modal Window
	local modal = Instance.new("Frame")
	modal.Name = "ModalWindow"
	modal.Size = UDim2.new(0, 680, 0, 520)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.new(0.5, 0, 0.5, 0)
	modal.BackgroundColor3 = PLAQUE
	modal.Parent = container

	UITheme.AddCorner(modal, 12)
	UITheme.AddStroke(modal, BRASS, 2.5, 0.05)
	UITheme.AddGradient(modal, WOOD_MID, PLAQUE_DARK, 90)

	-- Header
	local header = Instance.new("Frame")
	header.Name = "Header"
	header.Size = UDim2.new(1, 0, 0, 60)
	header.BackgroundColor3 = PLAQUE_DARK
	header.BorderSizePixel = 0
	header.Parent = modal
	UITheme.AddCorner(header, 12)

	-- Flatten bottom corners of header
	local headerMask = Instance.new("Frame")
	headerMask.Size = UDim2.new(1, 0, 0, 12)
	headerMask.Position = UDim2.new(0, 0, 1, -12)
	headerMask.BackgroundColor3 = PLAQUE_DARK
	headerMask.BorderSizePixel = 0
	headerMask.Parent = header

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "HeaderTitle"
	headerTitle.Size = UDim2.new(0, 300, 1, 0)
	headerTitle.Position = UDim2.new(0, 24, 0, 0)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "SETTINGS & CONTROLS"
	headerTitle.TextColor3 = BRASS_LIGHT
	headerTitle.Font = ANTIQUE
	headerTitle.TextSize = 24
	headerTitle.TextXAlignment = Enum.TextXAlignment.Left
	headerTitle.Parent = header

	-- Close Button "X"
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.Size = UDim2.new(0, 36, 0, 36)
	closeBtn.AnchorPoint = Vector2.new(1, 0.5)
	closeBtn.Position = UDim2.new(1, -16, 0.5, 0)
	closeBtn.BackgroundColor3 = PLAQUE
	closeBtn.AutoButtonColor = false
	closeBtn.Text = "✕"
	closeBtn.TextColor3 = BRASS_LIGHT
	closeBtn.Font = ANTIQUE
	closeBtn.TextSize = 18
	closeBtn.Parent = header

	UITheme.AddCorner(closeBtn, 6)
	local closeStroke = UITheme.AddStroke(closeBtn, BRASS, 1.5, 0.3)
	UITheme.MakeButtonInteractive(closeBtn, closeStroke, UITheme.Colors.Danger, SoundManager.PlayHover, function()
		SoundManager.PlayClose()
		callbacks.onClose()
	end)

	-- Content Body
	local body = Instance.new("Frame")
	body.Name = "Body"
	body.Size = UDim2.new(1, -48, 1, -140)
	body.Position = UDim2.new(0, 24, 0, 70)
	body.BackgroundTransparency = 1
	body.Parent = modal

	-- Tabs Bar
	local tabBar = Instance.new("Frame")
	tabBar.Name = "TabBar"
	tabBar.Size = UDim2.new(1, 0, 0, 40)
	tabBar.BackgroundTransparency = 1
	tabBar.Parent = body

	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.SortOrder = Enum.SortOrder.LayoutOrder
	tabLayout.Padding = UDim.new(0, 10)
	tabLayout.Parent = tabBar

	local tabPages = Instance.new("Frame")
	tabPages.Name = "TabPages"
	tabPages.Size = UDim2.new(1, 0, 1, -50)
	tabPages.Position = UDim2.new(0, 0, 0, 50)
	tabPages.BackgroundTransparency = 1
	tabPages.Parent = body

	-- State tracking for tabs
	local activeTab = "Keybinds"
	local tabButtons: { [string]: TextButton } = {}
	local tabFrames: { [string]: ScrollingFrame } = {}

	local tabsList = { "Keybinds", "Audio", "Gameplay" }

	-- Setup Tab Pages
	for _, tabName in ipairs(tabsList) do
		local page = Instance.new("ScrollingFrame")
		page.Name = tabName .. "Page"
		page.Size = UDim2.new(1, 0, 1, 0)
		page.BackgroundTransparency = 1
		page.ScrollBarThickness = 4
		page.ScrollBarImageColor3 = BRASS
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.Visible = (tabName == activeTab)
		page.Parent = tabPages

		local list = Instance.new("UIListLayout")
		list.FillDirection = Enum.FillDirection.Vertical
		list.Padding = UDim.new(0, 10)
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = page

		tabFrames[tabName] = page

		-- Tab Button
		local tabBtn = Instance.new("TextButton")
		tabBtn.Name = tabName .. "Tab"
		tabBtn.Size = UDim2.new(0, 130, 1, 0)
		tabBtn.BackgroundColor3 = (tabName == activeTab) and BRASS or PLAQUE
		tabBtn.AutoButtonColor = false
		tabBtn.Text = tabName:upper()
		tabBtn.TextColor3 = (tabName == activeTab) and Color3.fromRGB(20, 15, 10) or PARCHMENT
		tabBtn.Font = ANTIQUE
		tabBtn.TextSize = 16
		tabBtn.Parent = tabBar

		UITheme.AddCorner(tabBtn, 6)
		local tStroke = UITheme.AddStroke(
			tabBtn,
			(tabName == activeTab) and BRASS_LIGHT or BRASS,
			1.5,
			(tabName == activeTab) and 0 or 0.4
		)

		tabBtn.MouseButton1Click:Connect(function()
			SoundManager.PlayClick()
			activeTab = tabName
			for name, btn in pairs(tabButtons) do
				local isSel = (name == activeTab)
				btn.BackgroundColor3 = isSel and BRASS or PLAQUE
				btn.TextColor3 = isSel and Color3.fromRGB(20, 15, 10) or PARCHMENT
				local stroke = btn:FindFirstChildOfClass("UIStroke")
				if stroke then
					stroke.Color = isSel and BRASS_LIGHT or BRASS
					stroke.Transparency = isSel and 0 or 0.4
				end
			end
			for name, fr in pairs(tabFrames) do
				fr.Visible = (name == activeTab)
			end
		end)

		tabButtons[tabName] = tabBtn
	end

	-- ========================================================
	-- 1. KEYBINDS TAB POPULATION
	-- ========================================================
	local keybindsPage = tabFrames["Keybinds"]
	local listeningAction: string? = nil
	local listeningBtn: TextButton? = nil
	local keybindBtnMap: { [string]: TextButton } = {}

	local inputConnection: RBXScriptConnection? = nil

	local function stopListening()
		if listeningBtn and listeningAction then
			local currentKey = workingSettings.keybinds[listeningAction] or "None"
			listeningBtn.Text = currentKey
			listeningBtn.TextColor3 = BRASS_LIGHT
		end
		listeningAction = nil
		listeningBtn = nil
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
	end

	for i, entry in ipairs(SettingsConfig.DefaultKeybinds) do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. entry.action
		row.Size = UDim2.new(1, -8, 0, 42)
		row.BackgroundColor3 = PLAQUE
		row.LayoutOrder = i
		row.Parent = keybindsPage

		UITheme.AddCorner(row, 6)
		UITheme.AddStroke(row, BRASS, 1, 0.35)

		local label = Instance.new("TextLabel")
		label.Name = "ActionLabel"
		label.Size = UDim2.new(0.6, 0, 1, 0)
		label.Position = UDim2.new(0, 16, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = entry.displayName
		label.TextColor3 = PARCHMENT
		label.Font = ANTIQUE
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = row

		local keyBtn = Instance.new("TextButton")
		keyBtn.Name = "KeyButton"
		keyBtn.Size = UDim2.new(0, 140, 0, 30)
		keyBtn.AnchorPoint = Vector2.new(1, 0.5)
		keyBtn.Position = UDim2.new(1, -10, 0.5, 0)
		keyBtn.BackgroundColor3 = PLAQUE_DARK
		keyBtn.AutoButtonColor = false
		keyBtn.Text = workingSettings.keybinds[entry.action] or entry.defaultKey
		keyBtn.TextColor3 = BRASS_LIGHT
		keyBtn.Font = ANTIQUE
		keyBtn.TextSize = 14
		keyBtn.Parent = row

		UITheme.AddCorner(keyBtn, 4)
		local kStroke = UITheme.AddStroke(keyBtn, BRASS, 1, 0.3)
		keybindBtnMap[entry.action] = keyBtn

		keyBtn.MouseButton1Click:Connect(function()
			if listeningAction == entry.action then
				stopListening()
				return
			end

			stopListening()
			SoundManager.PlayClick()

			listeningAction = entry.action
			listeningBtn = keyBtn
			keyBtn.Text = "[Press Key...]"
			keyBtn.TextColor3 = UITheme.Colors.Warning

			inputConnection = UserInputService.InputBegan:Connect(function(input, gameProcessed)
				if input.UserInputType == Enum.UserInputType.Keyboard then
					local keyName = input.KeyCode.Name
					if input.KeyCode == Enum.KeyCode.Escape then
						stopListening()
						return
					end
					workingSettings.keybinds[entry.action] = keyName
					SoundManager.PlaySelect()
					stopListening()
				elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
					workingSettings.keybinds[entry.action] = "MouseButton1"
					SoundManager.PlaySelect()
					stopListening()
				elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
					workingSettings.keybinds[entry.action] = "MouseButton2"
					SoundManager.PlaySelect()
					stopListening()
				end
			end)
		end)
	end

	-- ========================================================
	-- 2. AUDIO TAB POPULATION
	-- ========================================================
	local audioPage = tabFrames["Audio"]
	local audioSettingsList = {
		{ key = "masterVolume", name = "Master Volume" },
		{ key = "musicVolume", name = "Music Volume" },
		{ key = "sfxVolume", name = "SFX Volume" },
	}

	for i, item in ipairs(audioSettingsList) do
		local row = Instance.new("Frame")
		row.Name = "AudioRow_" .. item.key
		row.Size = UDim2.new(1, -8, 0, 50)
		row.BackgroundColor3 = PLAQUE
		row.LayoutOrder = i
		row.Parent = audioPage

		UITheme.AddCorner(row, 6)
		UITheme.AddStroke(row, BRASS, 1, 0.35)

		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(0.4, 0, 1, 0)
		label.Position = UDim2.new(0, 16, 0, 0)
		label.BackgroundTransparency = 1
		label.Text = item.name
		label.TextColor3 = PARCHMENT
		label.Font = ANTIQUE
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = row

		-- Slider Bar
		local val = workingSettings[item.key] or 0.8
		local sliderBg = Instance.new("Frame")
		sliderBg.Name = "SliderBg"
		sliderBg.Size = UDim2.new(0, 200, 0, 12)
		sliderBg.AnchorPoint = Vector2.new(1, 0.5)
		sliderBg.Position = UDim2.new(1, -60, 0.5, 0)
		sliderBg.BackgroundColor3 = PLAQUE_DARK
		sliderBg.Parent = row
		UITheme.AddCorner(sliderBg, 6)

		local sliderFill = Instance.new("Frame")
		sliderFill.Name = "Fill"
		sliderFill.Size = UDim2.new(val, 0, 1, 0)
		sliderFill.BackgroundColor3 = BRASS
		sliderFill.BorderSizePixel = 0
		sliderFill.Parent = sliderBg
		UITheme.AddCorner(sliderFill, 6)

		local percentLabel = Instance.new("TextLabel")
		percentLabel.Name = "Percent"
		percentLabel.Size = UDim2.new(0, 45, 1, 0)
		percentLabel.AnchorPoint = Vector2.new(1, 0.5)
		percentLabel.Position = UDim2.new(1, -8, 0.5, 0)
		percentLabel.BackgroundTransparency = 1
		percentLabel.Text = `{math.floor(val * 100)}%`
		percentLabel.TextColor3 = BRASS_LIGHT
		percentLabel.Font = ANTIQUE
		percentLabel.TextSize = 13
		percentLabel.Parent = row

		local sliderBtn = Instance.new("TextButton")
		sliderBtn.Size = UDim2.new(1, 0, 1, 0)
		sliderBtn.BackgroundTransparency = 1
		sliderBtn.Text = ""
		sliderBtn.Parent = sliderBg

		local dragging = false
		local function updateSlider(xPos: number)
			local absPos = sliderBg.AbsolutePosition.X
			local absSize = sliderBg.AbsoluteSize.X
			if absSize <= 0 then
				return
			end
			local rel = math.clamp((xPos - absPos) / absSize, 0, 1)
			workingSettings[item.key] = rel
			sliderFill.Size = UDim2.new(rel, 0, 1, 0)
			percentLabel.Text = `{math.floor(rel * 100)}%`
		end

		sliderBtn.MouseButton1Down:Connect(function()
			dragging = true
			SoundManager.PlayClick()
			updateSlider(UserInputService:GetMouseLocation().X)
		end)

		UserInputService.InputEnded:Connect(function(inp)
			if inp.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
			end
		end)

		UserInputService.InputChanged:Connect(function(inp)
			if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then
				updateSlider(UserInputService:GetMouseLocation().X)
			end
		end)
	end

	-- ========================================================
	-- 3. GAMEPLAY / VFX TAB POPULATION
	-- ========================================================
	local gameplayPage = tabFrames["Gameplay"]
	local togglesList = {
		{ key = "cameraShake", name = "Camera Shake Effects", desc = "Enable dynamic screen impact shaking." },
		{ key = "damageNumbers", name = "Damage Popups", desc = "Show floating combat damage numbers." },
		{ key = "lowDetailVFX", name = "Low Detail Particle VFX", desc = "Reduces particle density for better performance." },
	}

	for i, item in ipairs(togglesList) do
		local row = Instance.new("Frame")
		row.Name = "ToggleRow_" .. item.key
		row.Size = UDim2.new(1, -8, 0, 56)
		row.BackgroundColor3 = PLAQUE
		row.LayoutOrder = i
		row.Parent = gameplayPage

		UITheme.AddCorner(row, 6)
		UITheme.AddStroke(row, BRASS, 1, 0.35)

		local label = Instance.new("TextLabel")
		label.Name = "Title"
		label.Size = UDim2.new(0.65, 0, 0, 22)
		label.Position = UDim2.new(0, 16, 0, 8)
		label.BackgroundTransparency = 1
		label.Text = item.name
		label.TextColor3 = PARCHMENT
		label.Font = ANTIQUE
		label.TextSize = 15
		label.TextXAlignment = Enum.TextXAlignment.Left
		label.Parent = row

		local desc = Instance.new("TextLabel")
		desc.Name = "Desc"
		desc.Size = UDim2.new(0.65, 0, 0, 18)
		desc.Position = UDim2.new(0, 16, 0, 30)
		desc.BackgroundTransparency = 1
		desc.Text = item.desc
		desc.TextColor3 = Color3.fromRGB(160, 140, 118)
		desc.Font = UITheme.Fonts.Sub
		desc.TextSize = 11
		desc.TextXAlignment = Enum.TextXAlignment.Left
		desc.Parent = row

		local curVal = workingSettings[item.key] == true
		local toggleBtn = Instance.new("TextButton")
		toggleBtn.Name = "ToggleBtn"
		toggleBtn.Size = UDim2.new(0, 70, 0, 30)
		toggleBtn.AnchorPoint = Vector2.new(1, 0.5)
		toggleBtn.Position = UDim2.new(1, -16, 0.5, 0)
		toggleBtn.BackgroundColor3 = curVal and BRASS or PLAQUE_DARK
		toggleBtn.AutoButtonColor = false
		toggleBtn.Text = curVal and "ON" or "OFF"
		toggleBtn.TextColor3 = curVal and Color3.fromRGB(20, 15, 10) or PARCHMENT
		toggleBtn.Font = ANTIQUE
		toggleBtn.TextSize = 13
		toggleBtn.Parent = row

		UITheme.AddCorner(toggleBtn, 4)

		toggleBtn.MouseButton1Click:Connect(function()
			SoundManager.PlayClick()
			local newVal = not workingSettings[item.key]
			workingSettings[item.key] = newVal
			toggleBtn.Text = newVal and "ON" or "OFF"
			toggleBtn.TextColor3 = newVal and Color3.fromRGB(20, 15, 10) or PARCHMENT
			TweenService:Create(toggleBtn, UITheme.Tweens.Fast, {
				BackgroundColor3 = newVal and BRASS or PLAQUE_DARK,
			}):Play()
		end)
	end

	-- ========================================================
	-- MODAL FOOTER: RESET & APPLY
	-- ========================================================
	local footer = Instance.new("Frame")
	footer.Name = "Footer"
	footer.Size = UDim2.new(1, 0, 0, 64)
	footer.Position = UDim2.new(0, 0, 1, -64)
	footer.BackgroundColor3 = PLAQUE_DARK
	footer.BorderSizePixel = 0
	footer.Parent = modal
	UITheme.AddCorner(footer, 12)

	-- Flatten top corners of footer
	local footerMask = Instance.new("Frame")
	footerMask.Size = UDim2.new(1, 0, 0, 12)
	footerMask.Position = UDim2.new(0, 0, 0, 0)
	footerMask.BackgroundColor3 = PLAQUE_DARK
	footerMask.BorderSizePixel = 0
	footerMask.Parent = footer

	-- Reset Button
	local resetBtn = Instance.new("TextButton")
	resetBtn.Name = "ResetBtn"
	resetBtn.Size = UDim2.new(0, 150, 0, 38)
	resetBtn.Position = UDim2.new(0, 24, 0.5, -19)
	resetBtn.BackgroundColor3 = PLAQUE
	resetBtn.AutoButtonColor = false
	resetBtn.Text = "RESET DEFAULTS"
	resetBtn.TextColor3 = PARCHMENT
	resetBtn.Font = ANTIQUE
	resetBtn.TextSize = 14
	resetBtn.Parent = footer

	UITheme.AddCorner(resetBtn, 6)
	local rStroke = UITheme.AddStroke(resetBtn, BRASS, 1.5, 0.3)
	UITheme.MakeButtonInteractive(resetBtn, rStroke, UITheme.Colors.Warning, SoundManager.PlayHover, function()
		SoundManager.PlayClick()
		workingSettings = SettingsConfig.CloneDefaultSettings()
		for action, btn in pairs(keybindBtnMap) do
			btn.Text = workingSettings.keybinds[action] or "None"
		end
		callbacks.onSave(workingSettings)
	end)

	-- Apply & Close Button
	local applyBtn = Instance.new("TextButton")
	applyBtn.Name = "ApplyBtn"
	applyBtn.Size = UDim2.new(0, 160, 0, 38)
	applyBtn.AnchorPoint = Vector2.new(1, 0.5)
	applyBtn.Position = UDim2.new(1, -24, 0.5, -19)
	applyBtn.BackgroundColor3 = BRASS
	applyBtn.AutoButtonColor = false
	applyBtn.Text = "APPLY & SAVE"
	applyBtn.TextColor3 = Color3.fromRGB(20, 15, 10)
	applyBtn.Font = ANTIQUE
	applyBtn.TextSize = 16
	applyBtn.Parent = footer

	UITheme.AddCorner(applyBtn, 6)
	local aStroke = UITheme.AddStroke(applyBtn, BRASS_LIGHT, 2, 0)
	UITheme.MakeButtonInteractive(applyBtn, aStroke, UITheme.Colors.GoldLight, SoundManager.PlayHover, function()
		stopListening()
		SoundManager.PlayConfirm()
		callbacks.onSave(workingSettings)
		callbacks.onClose()
	end)

	return container
end

return SettingsModal
