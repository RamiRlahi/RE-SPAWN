--[[
	SettingsModal.luau
	"System Settings": a blue glass panel floating in the world at an angle
	(the reference shot). The window is a SurfaceGui on an invisible part held
	in front of the camera, off to the right and turned in toward the middle
	of the screen, so it has real perspective (its right edge nearer).

	  • Tabs down the left: Graphics, Audio, Controls, Gameplay.
	  • Rows of label + control: pill toggles, blue sliders, key buttons.
	  • Changes apply and save as they're made; ✕ closes.
	  • In the dungeon the camera moves in for the shot (over the hero's right
	    shoulder, HUD hidden) and eases back when the window closes.

	SettingsModal.Create(parent, currentSettings, callbacks) → CanvasGroup
	(the screen-space container: show / fade it, the panel follows).
--]]

local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))
local Network = require(Shared:WaitForChild("Network"))

export type SettingsModalCallbacks = {
	onClose: () -> (),
	onSave: (settings: any) -> (),
}

local SettingsModal = {}

-- Per panel: put fresh settings into it (changed elsewhere, e.g. the title
-- screen's window), so it never saves a stale copy back over them.
local reloaders: { [Instance]: (any) -> () } = {}
function SettingsModal.Reload(container: Instance, settings: any)
	local f = reloaders[container]
	if f then f(settings) end
end

-- ── Look (the reference: dark blue glass, a blue rim of light) ──────────────
local GLASS = Color3.fromRGB(18, 24, 46)
local GLASS_TOP = Color3.fromRGB(30, 40, 76)
local GLASS_BOTTOM = Color3.fromRGB(12, 16, 32)
local EDGE = Color3.fromRGB(110, 150, 255)
local TEXT = Color3.fromRGB(236, 241, 255)
local SUB = Color3.fromRGB(168, 180, 212)
local LINE = Color3.fromRGB(120, 140, 205)
local BLUE = Color3.fromRGB(64, 128, 255)
local OFF = Color3.fromRGB(70, 76, 98)
local KNOB_OFF = Color3.fromRGB(196, 202, 220)
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local W, H = 760, 480 -- canvas pixels
local PPS = 100       -- canvas pixels per stud
local SIDEBAR = 196   -- left column width

local function corner(o: GuiObject, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = o
end

local function stroke(o: GuiObject, color: Color3, thickness: number, transparency: number): UIStroke
	local s = Instance.new("UIStroke")
	s.Color = color
	s.Thickness = thickness
	s.Transparency = transparency
	s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	s.Parent = o
	return s
end

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function hairline(parent: Instance, pos: UDim2, size: UDim2)
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	f.BackgroundColor3 = LINE
	f.BackgroundTransparency = 0.72
	f.Position = pos
	f.Size = size
	f.Parent = parent
end

function SettingsModal.Create(parent: GuiObject, currentSettings: any, callbacks: SettingsModalCallbacks): CanvasGroup
	local workingSettings: any = SettingsConfig.CloneDefaultSettings()
	if currentSettings and typeof(currentSettings) == "table" then
		for k, v in pairs(currentSettings) do
			if typeof(v) == "table" then
				local t = {}
				for subK, subV in pairs(v) do t[subK] = subV end
				workingSettings[k] = t
			else
				workingSettings[k] = v
			end
		end
	end

	-- Changes save as they're made (a moment after the last one).
	local saveToken = 0
	local function changed()
		saveToken += 1
		local my = saveToken
		task.delay(0.25, function()
			if my == saveToken then callbacks.onSave(workingSettings) end
		end)
	end

	-- ── Screen side: shown / faded by UIManager ──
	local container = Instance.new("CanvasGroup")
	container.Name = "SettingsModal"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 1
	container.Visible = false
	container.Parent = parent

	-- A soft dim behind it on the title screen (none in the dungeon shot). A
	-- plain Frame: clicks pass through to the panel in the world.
	local backdrop = Instance.new("Frame")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.new(1, 0, 1, 0)
	backdrop.BackgroundColor3 = Color3.fromRGB(6, 8, 16)
	backdrop.BackgroundTransparency = 0.6
	backdrop.Active = false
	backdrop.Parent = container

	-- ── The panel in the world ──
	local panel = Instance.new("Part")
	panel.Name = "SettingsPanel3D"
	panel.Anchored = true
	panel.CanCollide = false
	panel.CanTouch = false
	panel.CanQuery = true -- (SurfaceGui clicks find it by raycast)
	panel.CastShadow = false
	panel.Transparency = 1
	panel.Size = Vector3.new(W / PPS, H / PPS, 0.05)
	-- (a SurfaceGui kept in PlayerGui and adorned to a part doesn't draw here;
	-- parented to the part it does)
	local surface = Instance.new("SurfaceGui")
	surface.Name = "SettingsPanel3D"
	surface.Face = Enum.NormalId.Front
	surface.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
	surface.CanvasSize = Vector2.new(W, H)
	surface.LightInfluence = 0
	-- (not AlwaysOnTop: with it the panel didn't draw at all)
	surface.AlwaysOnTop = false
	surface.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	surface.Enabled = false
	surface.Parent = panel

	local fade = Instance.new("CanvasGroup")
	fade.Name = "Fade"
	fade.Size = UDim2.fromScale(1, 1)
	fade.BackgroundTransparency = 1
	fade.Parent = surface

	-- A glow of blue light round the glass.
	local glow = Instance.new("Frame")
	glow.Name = "Glow"
	glow.AnchorPoint = Vector2.new(0.5, 0.5)
	glow.Position = UDim2.fromScale(0.5, 0.5)
	glow.Size = UDim2.new(1, -14, 1, -14)
	glow.BackgroundTransparency = 1
	glow.Parent = fade
	corner(glow, 26)
	stroke(glow, EDGE, 10, 0.82)

	local window = Instance.new("Frame")
	window.Name = "ModalWindow"
	window.AnchorPoint = Vector2.new(0.5, 0.5)
	window.Position = UDim2.fromScale(0.5, 0.5)
	window.Size = UDim2.new(1, -24, 1, -24)
	window.BackgroundColor3 = Color3.new(1, 1, 1) -- (the gradient gives the colour)
	window.BackgroundTransparency = 0.2
	window.Parent = fade
	corner(window, 22)
	stroke(window, EDGE, 2, 0.15)
	local grad = Instance.new("UIGradient")
	grad.Color = ColorSequence.new(GLASS_TOP, GLASS_BOTTOM)
	grad.Rotation = 90
	grad.Parent = window

	-- Header: the gear, "System Settings", ✕.
	-- the gear: a ring with teeth (drawn: the font has no ⚙)
	local gear = Instance.new("Frame")
	gear.AnchorPoint = Vector2.new(0.5, 0.5)
	gear.Position = UDim2.fromOffset(44, 37)
	gear.Size = UDim2.fromOffset(34, 34)
	gear.BackgroundTransparency = 1
	gear.Parent = window
	for k = 0, 3 do
		local tooth = Instance.new("Frame")
		tooth.AnchorPoint = Vector2.new(0.5, 0.5)
		tooth.Position = UDim2.fromScale(0.5, 0.5)
		tooth.Size = UDim2.fromOffset(34, 8)
		tooth.Rotation = k * 45
		tooth.BackgroundColor3 = TEXT
		tooth.BorderSizePixel = 0
		tooth.Parent = gear
		corner(tooth, 2)
	end
	local hub = Instance.new("Frame")
	hub.AnchorPoint = Vector2.new(0.5, 0.5)
	hub.Position = UDim2.fromScale(0.5, 0.5)
	hub.Size = UDim2.fromOffset(24, 24)
	hub.BackgroundColor3 = TEXT
	hub.Parent = gear
	corner(hub, 12)
	local hole = Instance.new("Frame")
	hole.AnchorPoint = Vector2.new(0.5, 0.5)
	hole.Position = UDim2.fromScale(0.5, 0.5)
	hole.Size = UDim2.fromOffset(10, 10)
	hole.BackgroundColor3 = GLASS_TOP
	hole.Parent = gear
	corner(hole, 5)
	label(window, "System Settings", 32, TEXT, { Position = UDim2.fromOffset(74, 12), Size = UDim2.fromOffset(420, 48), Font = FONT_BOLD })
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseBtn"
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -18, 0, 14)
	closeBtn.Size = UDim2.fromOffset(44, 44)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Text = ""
	closeBtn.Parent = window
	for _, a in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.fromScale(0.5, 0.5)
		bar.Size = UDim2.fromOffset(30, 3)
		bar.Rotation = a
		bar.BackgroundColor3 = TEXT
		bar.BorderSizePixel = 0
		bar.Parent = closeBtn
		corner(bar, 2)
	end
	hairline(window, UDim2.fromOffset(20, 70), UDim2.new(1, -40, 0, 1))
	-- Sidebar and content, split by a hairline.
	hairline(window, UDim2.fromOffset(SIDEBAR, 82), UDim2.new(0, 1, 1, -100))

	local sidebar = Instance.new("Frame")
	sidebar.Name = "Tabs"
	sidebar.BackgroundTransparency = 1
	sidebar.Position = UDim2.fromOffset(14, 84)
	sidebar.Size = UDim2.new(0, SIDEBAR - 26, 1, -100)
	sidebar.Parent = window
	local sideList = Instance.new("UIListLayout")
	sideList.Padding = UDim.new(0, 6)
	sideList.SortOrder = Enum.SortOrder.LayoutOrder
	sideList.Parent = sidebar

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.BackgroundTransparency = 1
	content.Position = UDim2.fromOffset(SIDEBAR + 18, 80)
	content.Size = UDim2.new(1, -(SIDEBAR + 36), 1, -96)
	content.Parent = window

	local TABS = {
		{ id = "Graphics", icon = "▣" },
		{ id = "Audio", icon = "♪" },
		{ id = "Controls", icon = "⌨" },
		{ id = "Gameplay", icon = "⚙" },
	}
	local pages: { [string]: ScrollingFrame } = {}
	local tabButtons: { [string]: TextButton } = {}
	local activeTab = "Graphics"

	local function selectTab(id: string)
		activeTab = id
		for tid, btn in pairs(tabButtons) do
			local on = tid == id
			TweenService:Create(btn, TweenInfo.new(0.15), { BackgroundTransparency = if on then 0.25 else 1 }):Play()
			for _, l in ipairs(btn:GetChildren()) do
				if l:IsA("TextLabel") then l.TextColor3 = if on then TEXT else SUB end
			end
		end
		for pid, page in pairs(pages) do page.Visible = pid == id end
	end

	for i, t in ipairs(TABS) do
		local btn = Instance.new("TextButton")
		btn.Name = t.id .. "Tab"
		btn.LayoutOrder = i
		btn.Size = UDim2.new(1, 0, 0, 46)
		btn.BackgroundColor3 = BLUE
		btn.BackgroundTransparency = if t.id == activeTab then 0.25 else 1
		btn.AutoButtonColor = false
		btn.Text = ""
		btn.Parent = sidebar
		corner(btn, 10)
		label(btn, t.icon, 20, if t.id == activeTab then TEXT else SUB, { Position = UDim2.fromOffset(12, 0), Size = UDim2.new(0, 26, 1, 0),
			TextXAlignment = Enum.TextXAlignment.Center })
		label(btn, t.id, 21, if t.id == activeTab then TEXT else SUB, { Position = UDim2.fromOffset(46, 0), Size = UDim2.new(1, -50, 1, 0) })
		btn.MouseButton1Click:Connect(function()
			SoundManager.PlayClick()
			selectTab(t.id)
		end)
		tabButtons[t.id] = btn

		local page = Instance.new("ScrollingFrame")
		page.Name = t.id .. "Page"
		page.Size = UDim2.fromScale(1, 1)
		page.BackgroundTransparency = 1
		page.BorderSizePixel = 0
		page.ScrollBarThickness = 3
		page.ScrollBarImageColor3 = EDGE
		page.CanvasSize = UDim2.new(0, 0, 0, 0)
		page.AutomaticCanvasSize = Enum.AutomaticSize.Y
		page.Visible = t.id == activeTab
		page.Parent = content
		local list = Instance.new("UIListLayout")
		list.SortOrder = Enum.SortOrder.LayoutOrder
		list.Parent = page
		pages[t.id] = page
	end

	-- A row: the name on the left, a hairline under it; returns the row.
	local function row(page: Instance, order: number, name: string, sub: string?): Frame
		local r = Instance.new("Frame")
		r.Name = "Row_" .. name
		r.LayoutOrder = order
		r.Size = UDim2.new(1, -6, 0, if sub then 62 else 54)
		r.BackgroundTransparency = 1
		r.Parent = page
		label(r, name, 21, TEXT, { Position = UDim2.fromOffset(6, if sub then 8 else 0), Size = UDim2.new(0.6, 0, 0, if sub then 26 else 54) })
		if sub then
			label(r, sub, 13, SUB, { Position = UDim2.fromOffset(6, 34), Size = UDim2.new(0.62, 0, 0, 18), Font = Enum.Font.Gotham,
				TextTruncate = Enum.TextTruncate.AtEnd })
		end
		hairline(r, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1))
		return r
	end

	-- A pill switch, blue when on.
	local toggleSetters: { (boolean) -> () } = {}
	local afterToggle: { () -> () } = {}
	local function toggleRow(page: Instance, order: number, name: string, key: string, sub: string?)
		local r = row(page, order, name, sub)
		local pill = Instance.new("TextButton")
		pill.AnchorPoint = Vector2.new(1, 0.5)
		pill.Position = UDim2.new(1, -8, 0.5, 0)
		pill.Size = UDim2.fromOffset(58, 30)
		pill.AutoButtonColor = false
		pill.Text = ""
		pill.Parent = r
		corner(pill, 15)
		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0, 0.5)
		knob.Size = UDim2.fromOffset(24, 24)
		knob.Parent = pill
		corner(knob, 12)
		local function show(on: boolean, instant: boolean?)
			local info = TweenInfo.new(if instant then 0 else 0.16, Enum.EasingStyle.Quad)
			TweenService:Create(pill, info, { BackgroundColor3 = if on then BLUE else OFF }):Play()
			TweenService:Create(knob, info, {
				Position = if on then UDim2.new(1, -27, 0.5, 0) else UDim2.new(0, 3, 0.5, 0),
				BackgroundColor3 = if on then Color3.new(1, 1, 1) else KNOB_OFF,
			}):Play()
		end
		show(workingSettings[key] == true, true)
		table.insert(toggleSetters, function() show(workingSettings[key] == true, true) end)
		pill.MouseButton1Click:Connect(function()
			SoundManager.PlayClick()
			workingSettings[key] = not (workingSettings[key] == true)
			show(workingSettings[key])
			for _, f in ipairs(afterToggle) do f() end
			changed()
		end)
	end

	-- The mouse on the panel, in canvas pixels (sliders drag by this).
	local function pointer(): Vector2
		local cam = Workspace.CurrentCamera
		local m = UserInputService:GetMouseLocation()
		local ray = cam:ViewportPointToRay(m.X, m.Y)
		local n = panel.CFrame.LookVector
		local denom = ray.Direction:Dot(n)
		if math.abs(denom) < 1e-4 then return Vector2.new(-1, -1) end
		local t = (panel.Position - ray.Origin):Dot(n) / denom
		local lp = panel.CFrame:PointToObjectSpace(ray.Origin + ray.Direction * t)
		-- (seen from the front, the panel's +X is on the viewer's left)
		return Vector2.new((panel.Size.X / 2 - lp.X) / panel.Size.X * W, (panel.Size.Y / 2 - lp.Y) / panel.Size.Y * H)
	end

	-- A blue slider with its value on the right.
	local sliderSetters: { () -> () } = {}
	local function sliderRow(page: Instance, order: number, name: string, key: string)
		local r = row(page, order, name)
		local track = Instance.new("Frame")
		track.AnchorPoint = Vector2.new(1, 0.5)
		track.Position = UDim2.new(1, -70, 0.5, 0)
		track.Size = UDim2.fromOffset(190, 6)
		track.BackgroundColor3 = OFF
		track.BorderSizePixel = 0
		track.Parent = r
		corner(track, 3)
		local fill = Instance.new("Frame")
		fill.BackgroundColor3 = BLUE
		fill.BorderSizePixel = 0
		fill.Parent = track
		corner(fill, 3)
		local knob = Instance.new("Frame")
		knob.AnchorPoint = Vector2.new(0.5, 0.5)
		knob.Size = UDim2.fromOffset(18, 18)
		knob.BackgroundColor3 = Color3.new(1, 1, 1)
		knob.Parent = track
		corner(knob, 9)
		local value = label(r, "", 17, TEXT, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -6, 0.5, 0),
			Size = UDim2.fromOffset(56, 30), TextXAlignment = Enum.TextXAlignment.Right })
		local function show(v: number)
			fill.Size = UDim2.new(v, 0, 1, 0)
			knob.Position = UDim2.new(v, 0, 0.5, 0)
			value.Text = `{math.floor(v * 100 + 0.5)}%`
		end
		show(workingSettings[key] or 0.8)
		table.insert(sliderSetters, function() show(workingSettings[key] or 0.8) end)
		local hit = Instance.new("TextButton")
		hit.BackgroundTransparency = 1
		hit.Text = ""
		hit.AnchorPoint = Vector2.new(0, 0.5)
		hit.Position = UDim2.new(0, -10, 0.5, 0)
		hit.Size = UDim2.new(1, 20, 0, 30)
		hit.Parent = track
		local dragging = false
		local function update()
			local x = pointer().X
			local w = track.AbsoluteSize.X
			if w <= 0 then return end
			local v = math.clamp((x - track.AbsolutePosition.X) / w, 0, 1)
			workingSettings[key] = v
			show(v)
		end
		hit.MouseButton1Down:Connect(function()
			dragging = true
			SoundManager.PlayClick()
			update()
		end)
		UserInputService.InputChanged:Connect(function(inp)
			if dragging and inp.UserInputType == Enum.UserInputType.MouseMovement then update() end
		end)
		UserInputService.InputEnded:Connect(function(inp)
			if dragging and inp.UserInputType == Enum.UserInputType.MouseButton1 then
				dragging = false
				changed()
			end
		end)
	end

	-- ── Graphics ──
	local gfx = pages.Graphics
	-- Graphics Quality: a preset over the switches below ("Custom" once
	-- they've been set by hand); click to step Low → Medium → High.
	local PRESETS = {
		{ name = "Low", shadows = false, bloom = false, lowDetailVFX = true },
		{ name = "Medium", shadows = false, bloom = true, lowDetailVFX = false },
		{ name = "High", shadows = true, bloom = true, lowDetailVFX = false },
	}
	local function currentPreset(): number?
		for i, pr in ipairs(PRESETS) do
			if (workingSettings.shadows == true) == pr.shadows and (workingSettings.bloom == true) == pr.bloom
				and (workingSettings.lowDetailVFX == true) == pr.lowDetailVFX then
				return i
			end
		end
		return nil
	end
	local qRow = row(gfx, 0, "Graphics Quality")
	local qBox = Instance.new("TextButton")
	qBox.Name = "QualityBox"
	qBox.AnchorPoint = Vector2.new(1, 0.5)
	qBox.Position = UDim2.new(1, -8, 0.5, 0)
	qBox.Size = UDim2.fromOffset(180, 38)
	qBox.BackgroundColor3 = GLASS_TOP
	qBox.BackgroundTransparency = 0.25
	qBox.AutoButtonColor = false
	qBox.Text = ""
	qBox.Parent = qRow
	corner(qBox, 8)
	stroke(qBox, EDGE, 1, 0.5)
	local qText = label(qBox, "High", 20, TEXT, { Position = UDim2.fromOffset(14, 0), Size = UDim2.new(1, -46, 1, 0) })
	-- the chevron (drawn)
	for _, a in ipairs({ 45, -45 }) do
		local bar = Instance.new("Frame")
		bar.AnchorPoint = Vector2.new(0.5, 0.5)
		bar.Position = UDim2.new(1, if a > 0 then -27 else -21, 0.5, 0)
		bar.Size = UDim2.fromOffset(10, 2)
		bar.Rotation = a
		bar.BackgroundColor3 = TEXT
		bar.BorderSizePixel = 0
		bar.Parent = qBox
	end
	local function showQuality()
		local i = currentPreset()
		qText.Text = if i then PRESETS[i].name else "Custom"
	end
	showQuality()
	table.insert(toggleSetters, function() showQuality() end)
	table.insert(afterToggle, showQuality)
	qBox.MouseButton1Click:Connect(function()
		SoundManager.PlayClick()
		local nextPreset = PRESETS[(currentPreset() or 3) % #PRESETS + 1]
		workingSettings.shadows = nextPreset.shadows
		workingSettings.bloom = nextPreset.bloom
		workingSettings.lowDetailVFX = nextPreset.lowDetailVFX
		for _, f in ipairs(toggleSetters) do f(true) end
		changed()
	end)
	toggleRow(gfx, 1, "Shadows", "shadows")
	toggleRow(gfx, 2, "Bloom & Glow", "bloom")
	toggleRow(gfx, 3, "Low Detail VFX", "lowDetailVFX", "Fewer particles, for better performance.")

	-- ── Audio ──
	sliderRow(pages.Audio, 1, "Master Volume", "masterVolume")
	sliderRow(pages.Audio, 2, "Music Volume", "musicVolume")
	sliderRow(pages.Audio, 3, "Effects Volume", "sfxVolume")

	-- ── Controls (click a key, then press the new one) ──
	local listeningAction: string? = nil
	local listeningBtn: TextButton? = nil
	local keyButtons: { [string]: TextButton } = {}
	local inputConnection: RBXScriptConnection? = nil

	local function stopListening()
		if listeningBtn and listeningAction then
			listeningBtn.Text = workingSettings.keybinds[listeningAction] or "None"
			listeningBtn.TextColor3 = TEXT
		end
		listeningAction, listeningBtn = nil, nil
		-- (cleared a beat later, so the key just pressed doesn't also toggle the menu)
		task.defer(function() container:SetAttribute("Listening", nil) end)
		if inputConnection then
			inputConnection:Disconnect()
			inputConnection = nil
		end
	end

	for i, entry in ipairs(SettingsConfig.DefaultKeybinds) do
		local r = row(pages.Controls, i, entry.displayName)
		local keyBtn = Instance.new("TextButton")
		keyBtn.AnchorPoint = Vector2.new(1, 0.5)
		keyBtn.Position = UDim2.new(1, -8, 0.5, 0)
		keyBtn.Size = UDim2.fromOffset(150, 34)
		keyBtn.BackgroundColor3 = GLASS
		keyBtn.BackgroundTransparency = 0.3
		keyBtn.AutoButtonColor = false
		keyBtn.Font = FONT
		keyBtn.TextSize = 16
		keyBtn.TextColor3 = TEXT
		keyBtn.Text = workingSettings.keybinds[entry.action] or entry.defaultKey
		keyBtn.Parent = r
		corner(keyBtn, 8)
		stroke(keyBtn, EDGE, 1, 0.55)
		keyButtons[entry.action] = keyBtn
		keyBtn.MouseButton1Click:Connect(function()
			if listeningAction == entry.action then
				stopListening()
				return
			end
			stopListening()
			SoundManager.PlayClick()
			listeningAction, listeningBtn = entry.action, keyBtn
			container:SetAttribute("Listening", true)
			keyBtn.Text = "Press a key…"
			keyBtn.TextColor3 = EDGE
			inputConnection = UserInputService.InputBegan:Connect(function(input)
				local keyName: string? = nil
				if input.UserInputType == Enum.UserInputType.Keyboard then
					if input.KeyCode == Enum.KeyCode.Escape then
						stopListening()
						return
					end
					keyName = input.KeyCode.Name
				elseif input.UserInputType == Enum.UserInputType.MouseButton1 then
					keyName = "MouseButton1"
				elseif input.UserInputType == Enum.UserInputType.MouseButton2 then
					keyName = "MouseButton2"
				end
				if keyName then
					workingSettings.keybinds[entry.action] = keyName
					SoundManager.PlaySelect()
					stopListening()
					changed()
				end
			end)
		end)
	end

	-- ── Gameplay ──
	local gp = pages.Gameplay
	toggleRow(gp, 1, "Camera Shake", "cameraShake", "Screen shake on big hits.")
	toggleRow(gp, 2, "Damage Numbers", "damageNumbers", "Floating combat damage.")
	toggleRow(gp, 3, "Toggle Sprint", "toggleSprint", "Press to start / stop sprinting (off: hold).")
	toggleRow(gp, 5, "Classic Camera", "classicCamera", "A third-person shift-lock camera instead of top-down.")
	toggleRow(gp, 4, "Teammate Cinematics", "teammateCinematics", "Show teammates' ultimate cutscenes (off: your camera stays put).")

	-- Reset to defaults, quietly under the tabs.
	local reset = Instance.new("TextButton")
	reset.Name = "ResetBtn"
	reset.AnchorPoint = Vector2.new(0, 1)
	reset.Position = UDim2.new(0, 24, 1, -18)
	reset.Size = UDim2.fromOffset(SIDEBAR - 40, 30)
	reset.BackgroundTransparency = 1
	reset.Font = FONT
	reset.TextSize = 15
	reset.TextColor3 = SUB
	reset.TextXAlignment = Enum.TextXAlignment.Left
	reset.Text = "↺  Reset defaults"
	reset.Parent = window
	reset.MouseButton1Click:Connect(function()
		SoundManager.PlayClick()
		stopListening()
		workingSettings = SettingsConfig.CloneDefaultSettings()
		for action, btn in pairs(keyButtons) do btn.Text = workingSettings.keybinds[action] or "None" end
		for _, f in ipairs(toggleSetters) do f(true) end
		for _, f in ipairs(sliderSetters) do f() end
		changed()
	end)

	-- Leave the run (in the dungeon only): a second click within a few
	-- seconds confirms. The window closes first (the shot eases out), then
	-- the server sends us to the menu.
	local quitBtn = Instance.new("TextButton")
	quitBtn.Name = "LeaveRunBtn"
	quitBtn.AnchorPoint = Vector2.new(0, 1)
	quitBtn.Position = UDim2.new(0, 18, 1, -54)
	quitBtn.Size = UDim2.fromOffset(SIDEBAR - 36, 34)
	quitBtn.BackgroundColor3 = Color3.fromRGB(150, 30, 40)
	quitBtn.BackgroundTransparency = 0.7
	quitBtn.AutoButtonColor = false
	quitBtn.Font = FONT_BOLD
	quitBtn.TextSize = 15
	quitBtn.TextColor3 = Color3.fromRGB(255, 150, 150)
	quitBtn.Text = "Leave Run"
	quitBtn.Visible = false
	quitBtn.Parent = window
	corner(quitBtn, 8)
	stroke(quitBtn, Color3.fromRGB(255, 90, 100), 1, 0.45)
	local quitArmed = 0
	local quitSent = false
	quitBtn.MouseButton1Click:Connect(function()
		if quitSent then return end
		SoundManager.PlayClick()
		if os.clock() - quitArmed > 3 then
			quitArmed = os.clock()
			quitBtn.Text = "Click again to leave"
			quitBtn.BackgroundTransparency = 0.35
			local armedAt = quitArmed
			task.delay(3, function()
				if quitArmed == armedAt and not quitSent then
					quitBtn.Text = "Leave Run"
					quitBtn.BackgroundTransparency = 0.7
				end
			end)
			return
		end
		quitSent = true
		stopListening()
		callbacks.onSave(workingSettings)
		callbacks.onClose()
		task.delay(0.35, function()
			Network.GetRemoteEvent(Network.Remotes.DeathAction):FireServer("quit")
			quitSent = false
			quitArmed = 0
			quitBtn.Text = "Leave Run"
			quitBtn.BackgroundTransparency = 0.7
		end)
	end)

	reloaders[container] = function(settings: any)
		stopListening()
		local fresh = SettingsConfig.CloneDefaultSettings()
		for k, v in pairs(settings or {}) do
			if typeof(v) == "table" then
				local t = {}
				for kk, vv in pairs(v) do t[kk] = vv end
				fresh[k] = t
			else
				fresh[k] = v
			end
		end
		workingSettings = fresh
		for action, btn in pairs(keyButtons) do btn.Text = workingSettings.keybinds[action] or "None" end
		for _, f in ipairs(toggleSetters) do f(true) end
		for _, f in ipairs(sliderSetters) do f() end
	end

	closeBtn.MouseButton1Click:Connect(function()
		stopListening()
		SoundManager.PlayClose()
		callbacks.onSave(workingSettings)
		callbacks.onClose()
	end)

	-- ── Placing the panel, and the dungeon camera shot ──
	local localPlayer = Players.LocalPlayer
	local YAW = math.rad(-26)  -- turned in toward the screen's middle
	local TILT = math.rad(-4)  -- leaning back a touch
	local holder: Folder? = nil
	-- In the dungeon shot the panel stands still in the world, in front of
	-- the hero (set by enterShot); on the title screen it rides with the camera.
	local worldCF: CFrame? = nil
	-- The in-dungeon shot (matched to the reference frame): the camera just
	-- behind his right shoulder at shoulder height (X right, Y up, Z behind),
	-- looking nearly level; the panel's left / right edges on screen (-1..1
	-- across), its middle's height (-1..1 up), how far out it stands, and its
	-- turn (right edge nearer).
	local SHOT_EYE = Vector3.new(3.1, 1.3, 3.3)
	-- (and turned in toward him: a three-quarter view over the shoulder, not
	-- straight down his back)
	local SHOT_TURN = math.rad(24)
	local SHOT_PITCH = math.rad(4)
	local SHOT_FOV = 60
	local SHOT_LEFT, SHOT_RIGHT, SHOT_MID_Y = 0.04, 0.82, 0.21
	local SHOT_DEPTH = 9
	local SHOT_YAW = math.rad(32)
	local function place()
		local cam = Workspace.CurrentCamera
		if not cam then return end
		if not holder or not holder.Parent then
			local f = Instance.new("Folder")
			f.Name = "LocalSettingsPanel"
			f.Parent = Workspace
			holder = f
		end
		if panel.Parent ~= holder then panel.Parent = holder end
		if worldCF then
			panel.CFrame = worldCF
			return
		end
		local half = math.tan(math.rad(cam.FieldOfView) / 2)
		local aspect = cam.ViewportSize.X / math.max(cam.ViewportSize.Y, 1)
		-- far enough that it stands about half the screen tall, right of centre
		-- (about two fifths of the screen tall, its middle ~70% across: the reference)
		local dist = (H / PPS) / 0.42 / (2 * half)
		local at = cam.CFrame * Vector3.new(dist * half * aspect * 0.36, dist * half * 0.22, -dist)
		panel.CFrame = CFrame.lookAt(at, cam.CFrame.Position, cam.CFrame.UpVector) * CFrame.Angles(TILT, YAW, 0)
	end

	local IsometricCamera: any = nil
	pcall(function()
		IsometricCamera = require(script.Parent.Parent:WaitForChild("IsometricCamera"))
	end)
	-- ── Shot lighting ──
	-- The dungeon is dim and teal and the hero wears black, so in the shot he
	-- read as a flat silhouette against a loud floor. While the window's open:
	-- a warm key light from the camera side, a blue rim behind him, the
	-- panel's own blue spill, softer shadows, less bloom, the floor tiles'
	-- teal runes toned down and a gentle depth of field (the far room
	-- softens, the hero and the panel stay sharp). All of it eases back out.
	local Lighting = game:GetService("Lighting")
	local SHOT_EASE = TweenInfo.new(0.45, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out)
	local FLOOR_TONE = Color3.new(0.74, 0.56, 0.54) -- (multiplies the tile texture: teal drops most)
	local shotUndo: { () -> () } = {}
	-- (the true values, kept while easing back out, so reopening mid-fade
	-- doesn't tone the already-toned floor again)
	local originals: { [Instance]: { [string]: any } } = {}
	local shotGen = 0
	local function tweenBack(inst: Instance, props: { [string]: any })
		local kept = originals[inst] or {}
		originals[inst] = kept
		local was = {}
		for k in pairs(props) do
			if kept[k] == nil then kept[k] = (inst :: any)[k] end
			was[k] = kept[k]
		end
		TweenService:Create(inst, SHOT_EASE, props):Play()
		table.insert(shotUndo, function()
			if inst.Parent then TweenService:Create(inst, SHOT_EASE, was):Play() end
		end)
	end
	local function shotLight(at: Vector3, class: string, color: Color3, brightness: number, range: number, face: Vector3?)
		local a = Instance.new("Attachment")
		a.Name = "SettingsShotLight"
		a.WorldCFrame = if face then CFrame.lookAt(at, face) else CFrame.new(at)
		a.Parent = Workspace.Terrain
		local l = Instance.new(class) :: any
		l.Color = color
		l.Brightness = 0
		l.Range = range
		l.Shadows = false
		if class == "SpotLight" then l.Angle = 80; l.Face = Enum.NormalId.Front end
		l.Parent = a
		TweenService:Create(l, SHOT_EASE, { Brightness = brightness }):Play()
		table.insert(shotUndo, function()
			TweenService:Create(l, SHOT_EASE, { Brightness = 0 }):Play()
			task.delay(0.5, function() a:Destroy() end)
		end)
	end
	local function lightShot(root: BasePart, look: Vector3, right: Vector3, eye: Vector3, front: Vector3)
		shotGen += 1
		local chest = root.Position + Vector3.new(0, 1.2, 0)
		-- warm key from his left, like a brazier off frame
		shotLight(chest - right * 3.6 + look * 0.6 + Vector3.new(0, 2.4, 0), "SpotLight",
			Color3.fromRGB(255, 170, 110), 2.2, 12, chest)
		-- (a faint warm fill from the camera, so the black cloth keeps its folds)
		shotLight(eye + Vector3.new(0, 0.6, 0), "PointLight", Color3.fromRGB(255, 214, 180), 0.55, 7)
		-- blue rim from beyond him, catching his outline
		shotLight(chest + look * 2.6 + right * 0.4 + Vector3.new(0, 2.4, 0), "SpotLight",
			Color3.fromRGB(110, 150, 255), 2.6, 8, chest)
		-- the glass panel's glow spilling back onto his right side
		shotLight(chest + (front - chest) * 0.45, "PointLight", Color3.fromRGB(90, 130, 255), 1, 8)
		tweenBack(Lighting, { ShadowSoftness = 1 })
		local bloom = Lighting:FindFirstChildOfClass("BloomEffect")
		if bloom then
			local o = originals[bloom]
			local i = if o and o.Intensity then o.Intensity else bloom.Intensity
			local t = if o and o.Threshold then o.Threshold else bloom.Threshold
			tweenBack(bloom, { Intensity = i * 0.55, Threshold = math.max(t, 0.92) })
		end
		-- the floor's teal runes, toned down around the hero
		local floors = Workspace:FindFirstChild("GeneratedDungeon")
		floors = floors and floors:FindFirstChild("Floors")
		if floors then
			for _, f in ipairs(floors:GetDescendants()) do
				if f:IsA("BasePart") and (f.Position - root.Position).Magnitude < 60 then
					local c = if originals[f] and originals[f].Color then originals[f].Color else f.Color
					tweenBack(f, { Color = Color3.new(c.R * FLOOR_TONE.R, c.G * FLOOR_TONE.G, c.B * FLOOR_TONE.B) })
				end
			end
		end
		-- separation: hero and panel in focus, the room behind them softened
		local dof = Instance.new("DepthOfFieldEffect")
		dof.Name = "SettingsShotFocus"
		dof.FocusDistance = 9
		dof.InFocusRadius = 9
		dof.NearIntensity = 0
		dof.FarIntensity = 0
		dof.Parent = Lighting
		TweenService:Create(dof, SHOT_EASE, { FarIntensity = 0.3 }):Play()
		table.insert(shotUndo, function()
			TweenService:Create(dof, SHOT_EASE, { FarIntensity = 0 }):Play()
			task.delay(0.5, function() dof:Destroy() end)
		end)
	end
	local function unlightShot()
		for _, undo in ipairs(shotUndo) do pcall(undo) end
		table.clear(shotUndo)
		local gen = shotGen
		task.delay(0.5, function()
			if shotGen == gen then table.clear(originals) end
		end)
	end

	local inShot = false
	local hiddenGuis: { ScreenGui } = {}
	local hiddenParts: { BasePart } = {}
	local heldRoot: BasePart? = nil
	local savedMouseIcon: boolean? = nil
	local function enterShot()
		local char = localPlayer.Character
		local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local cam = Workspace.CurrentCamera
		if not root or not cam or not IsometricCamera then return end
		inShot = true
		backdrop.BackgroundTransparency = 1
		-- a clean frame: the HUD steps aside
		local own = container:FindFirstAncestorWhichIsA("ScreenGui")
		for _, g in ipairs(localPlayer.PlayerGui:GetChildren()) do
			if g:IsA("ScreenGui") and g ~= own and g.Enabled then
				g.Enabled = false
				table.insert(hiddenGuis, g)
			end
		end
		-- (walking the lobby the camera is Roblox's own, not the run's)
		if localPlayer:GetAttribute("InLobby") == false then IsometricCamera.Pause() end
		cam.CameraType = Enum.CameraType.Scriptable
		-- Just behind his right shoulder (the reference): his head and back
		-- fill the left of the frame, and the glass panel floats ahead of him,
		-- centre-right, turned so its right edge is nearer.
		local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
		look = if look.Magnitude > 0.01 then look.Unit else Vector3.new(0, 0, -1)
		local right = look:Cross(Vector3.yAxis)
		local eye = root.Position + Vector3.new(0, SHOT_EYE.Y, 0) - look * SHOT_EYE.Z + right * SHOT_EYE.X
		-- (looking along his facing turned in toward him, nearly level)
		local view = CFrame.fromAxisAngle(Vector3.yAxis, SHOT_TURN):VectorToWorldSpace(look)
		local shotCF = CFrame.lookAt(eye, eye + view * 10 - Vector3.new(0, 10 * math.tan(SHOT_PITCH), 0))
		-- The panel, solved in the camera's own space so its edges land where
		-- the reference has them, whatever the window's shape: turned by
		-- SHOT_YAW, its half-width w and middle cx come from where its left
		-- and right edges must project.
		local t = math.tan(math.rad(SHOT_FOV) / 2)
		local k = t * cam.ViewportSize.X / math.max(cam.ViewportSize.Y, 1)
		local sn, cs = math.sin(SHOT_YAW), math.cos(SHOT_YAW)
		local w = k * SHOT_DEPTH * (SHOT_RIGHT - SHOT_LEFT) / (2 * cs + k * sn * (SHOT_RIGHT + SHOT_LEFT))
		local cx = SHOT_LEFT * k * (SHOT_DEPTH + w * sn) + w * cs
		local at = shotCF * Vector3.new(cx, SHOT_MID_Y * t * SHOT_DEPTH, -SHOT_DEPTH)
		local front = at
		panel.Size = Vector3.new(2 * w, 2 * w * H / W, 0.05)
		-- (square to the screen but for the turn)
		worldCF = CFrame.new(at) * shotCF.Rotation * CFrame.Angles(0, math.pi - SHOT_YAW, 0)
		-- (he stays put while the window's open)
		root.Anchored = true
		heldRoot = root
		-- (no weapon in the shot: it would cover the frame)
		for _, d in ipairs(char:GetDescendants()) do
			if d:IsA("BasePart") and (d:FindFirstAncestorOfClass("Tool") or d:FindFirstAncestor("StowedWeapon")) then
				d.LocalTransparencyModifier = 1
				table.insert(hiddenParts, d)
			end
		end
		localPlayer:SetAttribute("SettingsOpen", true)
		-- (Leave Run: in a run only)
		quitBtn.Visible = localPlayer:GetAttribute("InLobby") == false
		lightShot(root, look, right, eye, front)
		-- (the normal mouse cursor, to click the panel with)
		savedMouseIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
		TweenService:Create(cam, TweenInfo.new(0.45, Enum.EasingStyle.Cubic, Enum.EasingDirection.Out),
			{ CFrame = shotCF, FieldOfView = SHOT_FOV }):Play()
	end
	local function leaveShot()
		backdrop.BackgroundTransparency = 0.6
		for _, g in ipairs(hiddenGuis) do
			if g.Parent then g.Enabled = true end
		end
		table.clear(hiddenGuis)
		for _, d in ipairs(hiddenParts) do
			if d.Parent then d.LocalTransparencyModifier = 0 end
		end
		table.clear(hiddenParts)
		localPlayer:SetAttribute("SettingsOpen", nil)
		quitBtn.Visible = false
		if savedMouseIcon ~= nil then UserInputService.MouseIconEnabled = savedMouseIcon end
		savedMouseIcon = nil
		worldCF = nil
		panel.Size = Vector3.new(W / PPS, H / PPS, 0.05)
		if heldRoot and heldRoot.Parent then heldRoot.Anchored = false end
		heldRoot = nil
		if not inShot then return end
		inShot = false
		unlightShot()
		-- (unless the run's over and the camera's already handed back)
		if IsometricCamera and IsometricCamera.IsActive() then
			IsometricCamera.Resume(0.45)
		elseif localPlayer:GetAttribute("InHub") == true then
			-- the lobby: back to walking behind him
			local cam = Workspace.CurrentCamera
			local hum = localPlayer.Character and localPlayer.Character:FindFirstChildOfClass("Humanoid")
			cam.CameraType = Enum.CameraType.Custom
			cam.FieldOfView = 70
			if hum then cam.CameraSubject = hum end
		end
	end

	local wasShown = false
	RunService.RenderStepped:Connect(function()
		local host = container:FindFirstAncestorWhichIsA("ScreenGui")
		local shown = container.Visible and host ~= nil and host.Enabled
		surface.Enabled = shown
		if shown ~= wasShown then
			wasShown = shown
			local walking = localPlayer:GetAttribute("InLobby") == false or localPlayer:GetAttribute("InHub") == true
			if shown and walking then enterShot() elseif not shown then leaveShot() end
			if not shown then
				stopListening()
				panel.Parent = nil
			end
		end
		if shown then
			fade.GroupTransparency = container.GroupTransparency
			place()
		end
	end)

	return container
end

return SettingsModal
