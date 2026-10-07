--!strict
--[[
	AbilityPreview.luau
	Video preview overlay for character abilities in the class selection screen.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local MenuStyle = require(script.Parent:WaitForChild("MenuStyle"))

local player = Players.LocalPlayer

local AbilityPreview = {}

local M = MenuStyle.Colors
local FONT = MenuStyle.Font

local gui: ScreenGui? = nil
local rootGroup: CanvasGroup? = nil
local videoFrame: VideoFrame? = nil
local isVisible = false

local function resolveVideoSource(videoId: string): (string?, Instance?)
	if not videoId or videoId == "" then return nil, nil end
	-- 1. Direct Roblox asset id
	if string.sub(videoId, 1, 13) == "rbxassetid://" or tonumber(videoId) ~= nil then
		local id = if tonumber(videoId) then `rbxassetid://{videoId}` else videoId
		return id, nil
	end
	-- 2. Instance in ReplicatedStorage or subfolders
	local asset = ReplicatedStorage:FindFirstChild(videoId, true)
	if asset and asset:IsA("VideoFrame") then
		return asset.Video, asset
	elseif asset and asset:IsA("StringValue") then
		return asset.Value, asset
	end
	return videoId, nil
end

local function close()
	if not isVisible or not rootGroup then return end
	isVisible = false
	if videoFrame then
		videoFrame.Playing = false
		videoFrame.TimePosition = 0
	end
	local tween = TweenService:Create(rootGroup, TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
		GroupTransparency = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		if not isVisible and gui then
			gui.Enabled = false
		end
	end)
end

function AbilityPreview.Hide()
	close()
end

function AbilityPreview.Show(name: string, tag: string, videoId: string, accentColor: Color3?, description: string?)
	local accent = accentColor or M.BrassLight

	if not gui then
		local pg = player:WaitForChild("PlayerGui") :: PlayerGui
		gui = Instance.new("ScreenGui")
		gui.Name = "AbilityPreviewGui"
		gui.ResetOnSpawn = false
		gui.DisplayOrder = 45
		gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
		gui.Parent = pg

		rootGroup = Instance.new("CanvasGroup")
		rootGroup.Name = "RootGroup"
		rootGroup.Size = UDim2.fromScale(1, 1)
		rootGroup.BackgroundTransparency = 1
		rootGroup.GroupTransparency = 1
		rootGroup.Parent = gui

		UserInputService.InputBegan:Connect(function(input, gp)
			if isVisible and input.KeyCode == Enum.KeyCode.Escape then
				close()
			end
		end)
	end

	local rg = rootGroup :: CanvasGroup
	rg:ClearAllChildren()

	-- Dark Backing Backdrop
	local backdrop = Instance.new("TextButton")
	backdrop.Name = "Backdrop"
	backdrop.Size = UDim2.fromScale(1, 1)
	backdrop.BackgroundColor3 = Color3.fromRGB(8, 6, 8)
	backdrop.BackgroundTransparency = 0.4
	backdrop.BorderSizePixel = 0
	backdrop.Text = ""
	backdrop.AutoButtonColor = false
	backdrop.Parent = rg
	backdrop.MouseButton1Click:Connect(close)

	-- Modal Frame
	local modal = Instance.new("Frame")
	modal.Name = "Modal"
	modal.Size = UDim2.fromOffset(720, 520)
	modal.AnchorPoint = Vector2.new(0.5, 0.5)
	modal.Position = UDim2.fromScale(0.5, 0.5)
	modal.BackgroundColor3 = M.PlaqueDark
	modal.BorderSizePixel = 0
	modal.Parent = rg

	MenuStyle.Plaque(modal, false)

	local modalCorner = Instance.new("UICorner")
	modalCorner.CornerRadius = UDim.new(0, 10)
	modalCorner.Parent = modal

	local modalStroke = Instance.new("UIStroke")
	modalStroke.Color = accent
	modalStroke.Thickness = 1.5
	modalStroke.Parent = modal

	-- Header Tag Badge
	local tagBadge = Instance.new("TextLabel")
	tagBadge.Name = "TagBadge"
	tagBadge.Size = UDim2.fromOffset(100, 22)
	tagBadge.Position = UDim2.new(0, 24, 0, 18)
	tagBadge.BackgroundColor3 = M.Crimson
	tagBadge.BorderSizePixel = 0
	tagBadge.Font = FONT
	tagBadge.TextSize = 12
	tagBadge.TextColor3 = M.Parchment
	tagBadge.Text = string.upper(tag)
	tagBadge.Parent = modal

	local tagCorner = Instance.new("UICorner")
	tagCorner.CornerRadius = UDim.new(0, 4)
	tagCorner.Parent = tagBadge

	UITheme.AddStroke(tagBadge, Color3.fromRGB(59, 16, 12), 1, 0.2)

	-- Header Title
	local titleLabel = Instance.new("TextLabel")
	titleLabel.Name = "Title"
	titleLabel.Size = UDim2.new(1, -180, 0, 26)
	titleLabel.Position = UDim2.new(0, 134, 0, 16)
	titleLabel.BackgroundTransparency = 1
	titleLabel.Font = FONT
	titleLabel.TextSize = 22
	titleLabel.TextColor3 = accent
	titleLabel.TextXAlignment = Enum.TextXAlignment.Left
	titleLabel.Text = name
	titleLabel.Parent = modal

	-- Close Button
	local closeBtn = Instance.new("TextButton")
	closeBtn.Name = "CloseButton"
	closeBtn.Size = UDim2.fromOffset(32, 32)
	closeBtn.AnchorPoint = Vector2.new(1, 0)
	closeBtn.Position = UDim2.new(1, -16, 0, 14)
	closeBtn.BackgroundTransparency = 1
	closeBtn.Font = FONT
	closeBtn.TextSize = 22
	closeBtn.TextColor3 = M.ParchmentMuted
	closeBtn.Text = "✕"
	closeBtn.Parent = modal

	closeBtn.MouseEnter:Connect(function() closeBtn.TextColor3 = Color3.fromRGB(255, 100, 100) end)
	closeBtn.MouseLeave:Connect(function() closeBtn.TextColor3 = M.ParchmentMuted end)
	closeBtn.MouseButton1Click:Connect(close)

	-- Video Container Frame (16:9 Aspect)
	local vidContainer = Instance.new("Frame")
	vidContainer.Name = "VideoContainer"
	vidContainer.Size = UDim2.new(1, -48, 0, 360)
	vidContainer.Position = UDim2.new(0, 24, 0, 52)
	vidContainer.BackgroundColor3 = Color3.fromRGB(10, 8, 10)
	vidContainer.BorderSizePixel = 0
	vidContainer.ClipsDescendants = true
	vidContainer.Parent = modal

	local vidCorner = Instance.new("UICorner")
	vidCorner.CornerRadius = UDim.new(0, 8)
	vidCorner.Parent = vidContainer

	local vidStroke = Instance.new("UIStroke")
	vidStroke.Color = Color3.fromRGB(50, 40, 45)
	vidStroke.Thickness = 1
	vidStroke.Parent = vidContainer

	local resolvedVideo = resolveVideoSource(videoId)

	if resolvedVideo and resolvedVideo ~= "" then
		local vf = Instance.new("VideoFrame")
		vf.Name = "Player"
		vf.Size = UDim2.fromScale(1, 1)
		vf.BackgroundTransparency = 1
		vf.Video = resolvedVideo
		vf.Looped = true
		vf.Volume = 0.5
		vf.Playing = true
		vf.Parent = vidContainer
		videoFrame = vf

		-- Replay / Click video to toggle play/pause
		local toggleBtn = Instance.new("TextButton")
		toggleBtn.Name = "TogglePlay"
		toggleBtn.Size = UDim2.fromScale(1, 1)
		toggleBtn.BackgroundTransparency = 1
		toggleBtn.Text = ""
		toggleBtn.Parent = vidContainer
		toggleBtn.MouseButton1Click:Connect(function()
			if vf.Playing then
				vf.Playing = false
			else
				vf.Playing = true
			end
		end)
	else
		-- Placeholder message if video asset is not uploaded yet
		local placeholder = Instance.new("Frame")
		placeholder.Size = UDim2.fromScale(1, 1)
		placeholder.BackgroundTransparency = 1
		placeholder.Parent = vidContainer

		local playIcon = Instance.new("TextLabel")
		playIcon.Size = UDim2.fromOffset(64, 64)
		playIcon.AnchorPoint = Vector2.new(0.5, 0.5)
		playIcon.Position = UDim2.fromScale(0.5, 0.42)
		playIcon.BackgroundTransparency = 1
		playIcon.Font = FONT
		playIcon.TextSize = 48
		playIcon.TextColor3 = accent
		playIcon.Text = "▶"
		playIcon.Parent = placeholder

		local msg = Instance.new("TextLabel")
		msg.Size = UDim2.new(1, -40, 0, 24)
		msg.AnchorPoint = Vector2.new(0.5, 0.5)
		msg.Position = UDim2.fromScale(0.5, 0.58)
		msg.BackgroundTransparency = 1
		msg.Font = FONT
		msg.TextSize = 16
		msg.TextColor3 = M.Parchment
		msg.Text = "Ability Video Preview"
		msg.Parent = placeholder

		local subMsg = Instance.new("TextLabel")
		subMsg.Size = UDim2.new(1, -40, 0, 20)
		subMsg.AnchorPoint = Vector2.new(0.5, 0.5)
		subMsg.Position = UDim2.fromScale(0.5, 0.66)
		subMsg.BackgroundTransparency = 1
		subMsg.Font = Enum.Font.GothamMedium
		subMsg.TextSize = 12
		subMsg.TextColor3 = M.ParchmentMuted
		subMsg.Text = if videoId and videoId ~= "" then `Asset: {videoId}` else "Upload video asset to ReplicatedStorage to preview"
		subMsg.Parent = placeholder
	end

	-- Bottom Description
	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(1, -48, 0, 70)
	descLabel.Position = UDim2.new(0, 24, 0, 422)
	descLabel.BackgroundTransparency = 1
	descLabel.Font = FONT
	descLabel.TextSize = 14
	descLabel.TextColor3 = M.Parchment
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.TextYAlignment = Enum.TextYAlignment.Top
	descLabel.Text = description or ""
	descLabel.Parent = modal

	-- Open Transition
	if gui then gui.Enabled = true end
	isVisible = true
	TweenService:Create(rg, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		GroupTransparency = 0,
	}):Play()
end

return AbilityPreview
