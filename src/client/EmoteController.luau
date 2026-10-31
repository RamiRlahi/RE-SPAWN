--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- EmoteController.luau (Client)
--
-- Handles emote playback during dungeon runs (and lobby).
--   • Press T to open/close the radial emote wheel.
--   • Click an emote to play it.
--   • Movement, attacking, using a skill, or taking damage cancels the emote.
--   • Emotes set the "IsEmoting" attribute on the character so the
--     AnimationController knows to hold still.
--   • The chosen emote is replicated to everyone via the EmotePlay remote.
--   • Other players' emotes arrive through the same remote and are played
--     on their characters locally.
-- ─────────────────────────────────────────────────────────────────────────────

local Players           = game:GetService("Players")
local RunService        = game:GetService("RunService")
local UserInputService  = game:GetService("UserInputService")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local Network   = require(Shared:WaitForChild("Network"))
local EmoteData = require(Shared:WaitForChild("EmoteData"))

local player  = Players.LocalPlayer
local EmoteController = {}

-- ── State ────────────────────────────────────────────────────────────────────
local isInit         = false
local wheelOpen      = false
local currentTrack: AnimationTrack? = nil
local currentEmoteId: string?       = nil
local lastEmoteTime  = 0
local renderConn: RBXScriptConnection? = nil
local wheelGui: ScreenGui?             = nil
local wheelFrame: Frame?               = nil
local conns: { RBXScriptConnection }   = {}

-- ── Helpers ──────────────────────────────────────────────────────────────────
local function getCharacter(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then return nil, nil, nil end
	local hum  = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return char, hum, root
end

local function getAnimator(): Animator?
	local char = player.Character
	if not char then return nil end
	local hum = char:FindFirstChildOfClass("Humanoid")
	return hum and hum:FindFirstChildOfClass("Animator")
end

-- ── Cancel emote (public, also called from AnimationController / SkillController) ─
function EmoteController.CancelEmote()
	local hadEmote = currentTrack ~= nil or currentEmoteId ~= nil
	if currentTrack then
		currentTrack:Stop(0.18)
		currentTrack = nil
	end
	currentEmoteId = nil

	local char = player.Character
	if char and char:GetAttribute("IsEmoting") ~= false then
		char:SetAttribute("IsEmoting", false)
	end

	-- Notify server so other players stop seeing our emote
	if hadEmote then
		pcall(function()
			Network.GetRemoteEvent(Network.Remotes.EmotePlay):FireServer("__cancel")
		end)
	end
end

local function isEmoting(): boolean
	return currentTrack ~= nil and currentTrack.IsPlaying
end

-- ── Play an emote locally + replicate ────────────────────────────────────────
local function playEmoteLocal(emoteId: string, replicate: boolean)
	local emote = EmoteData.Get(emoteId)
	if not emote then return end

	local char, hum, _ = getCharacter()
	if not char or not hum or hum.Health <= 0 then return end

	-- Can't emote while moving: player must be standing still
	if hum.MoveDirection.Magnitude > 0.05 then return end

	-- Can't emote while casting / ulting / tumbling / attacking / dead
	if char:GetAttribute("IsAttacking") == true then return end
	if char:GetAttribute("IsSkillCasting") == true then return end
	if char:GetAttribute("IsUltActive") == true then return end
	if char:GetAttribute("Tumbling") == true then return end
	if char:GetAttribute("Riding") ~= nil then return end

	-- Cooldown
	local now = os.clock()
	if now - lastEmoteTime < (emote.cooldown or 1.2) then return end
	lastEmoteTime = now

	-- Cancel any previous emote
	EmoteController.CancelEmote()

	-- Load and play
	local animator = getAnimator()
	if not animator then return end

	local animObj = Instance.new("Animation")
	animObj.AnimationId = EmoteData.GetAssetId(emote, hum.RigType)
	local track = animator:LoadAnimation(animObj)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = emote.looping
	track:Play(0.2)

	currentTrack = track
	currentEmoteId = emoteId
	char:SetAttribute("IsEmoting", true)

	-- When the animation finishes (non-looping), clear the state
	track.Stopped:Connect(function()
		if currentTrack == track then
			currentTrack = nil
			currentEmoteId = nil
			if char and char.Parent then
				char:SetAttribute("IsEmoting", false)
			end
		end
	end)

	-- Replicate to others
	if replicate then
		pcall(function()
			Network.GetRemoteEvent(Network.Remotes.EmotePlay):FireServer(emoteId)
		end)
	end

	-- Close the wheel
	if wheelOpen then
		EmoteController.CloseWheel()
	end
end

-- ── Play another player's emote on their character ───────────────────────────
local otherTracks: { [Player]: AnimationTrack } = {}

local function playRemoteEmote(emotingPlayer: Player, emoteId: string)
	if emotingPlayer == player then return end -- we already played ours

	local emote = EmoteData.Get(emoteId)
	if not emote then return end

	local char = emotingPlayer.Character
	if not char then return end
	local hum = char:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end

	-- Stop any previous emote on this player
	local old = otherTracks[emotingPlayer]
	if old and old.IsPlaying then old:Stop(0.18) end

	local animObj = Instance.new("Animation")
	animObj.AnimationId = EmoteData.GetAssetId(emote, hum.RigType)
	local track = animator:LoadAnimation(animObj)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = emote.looping
	track:Play(0.2)
	otherTracks[emotingPlayer] = track
end

local function cancelRemoteEmote(emotingPlayer: Player)
	if emotingPlayer == player then return end
	local old = otherTracks[emotingPlayer]
	if old and old.IsPlaying then old:Stop(0.18) end
	otherTracks[emotingPlayer] = nil
end

-- ── Emote Wheel UI ───────────────────────────────────────────────────────────
local WHEEL_SIZE     = 360
local BUTTON_SIZE    = 52
local CENTER_SIZE    = 46
local FONT           = Font.new("rbxasset://fonts/families/GothamSSm.json", Enum.FontWeight.Bold)

local function createWheelUI()
	local pGui = player:WaitForChild("PlayerGui") :: PlayerGui
	local existing = pGui:FindFirstChild("EmoteWheelGui")
	if existing then existing:Destroy() end

	local gui = Instance.new("ScreenGui")
	gui.Name = "EmoteWheelGui"
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 50
	gui.IgnoreGuiInset = true
	gui.Enabled = false
	gui.Parent = pGui

	-- Dark scrim behind the wheel (click to close)
	local scrim = Instance.new("TextButton")
	scrim.Name = "Scrim"
	scrim.Size = UDim2.fromScale(1, 1)
	scrim.BackgroundColor3 = Color3.new(0, 0, 0)
	scrim.BackgroundTransparency = 0.65
	scrim.BorderSizePixel = 0
	scrim.Text = ""
	scrim.AutoButtonColor = false
	scrim.ZIndex = 1
	scrim.Parent = gui
	scrim.MouseButton1Click:Connect(function()
		EmoteController.CloseWheel()
	end)

	-- Container centered on screen
	local container = Instance.new("Frame")
	container.Name = "WheelContainer"
	container.Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE)
	container.AnchorPoint = Vector2.new(0.5, 0.5)
	container.Position = UDim2.fromScale(0.5, 0.5)
	container.BackgroundTransparency = 1
	container.ZIndex = 2
	container.Parent = gui

	-- Outer ring (decorative)
	local ring = Instance.new("Frame")
	ring.Name = "Ring"
	ring.Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE)
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.BackgroundColor3 = Color3.fromRGB(18, 14, 22)
	ring.BackgroundTransparency = 0.3
	ring.ZIndex = 2
	ring.Parent = container

	local ringCorner = Instance.new("UICorner")
	ringCorner.CornerRadius = UDim.new(1, 0)
	ringCorner.Parent = ring

	local ringStroke = Instance.new("UIStroke")
	ringStroke.Color = Color3.fromRGB(180, 145, 72)
	ringStroke.Thickness = 2.5
	ringStroke.Transparency = 0.15
	ringStroke.Parent = ring

	-- Center label
	local center = Instance.new("TextLabel")
	center.Name = "CenterLabel"
	center.Size = UDim2.fromOffset(CENTER_SIZE, CENTER_SIZE)
	center.AnchorPoint = Vector2.new(0.5, 0.5)
	center.Position = UDim2.fromScale(0.5, 0.5)
	center.BackgroundColor3 = Color3.fromRGB(30, 24, 36)
	center.BackgroundTransparency = 0.2
	center.Text = "T"
	center.TextColor3 = Color3.fromRGB(212, 172, 92)
	center.FontFace = FONT
	center.TextSize = 18
	center.ZIndex = 4
	center.Parent = container

	local centerCorner = Instance.new("UICorner")
	centerCorner.CornerRadius = UDim.new(1, 0)
	centerCorner.Parent = center

	local centerStroke = Instance.new("UIStroke")
	centerStroke.Color = Color3.fromRGB(140, 110, 50)
	centerStroke.Thickness = 1.5
	centerStroke.Parent = center

	-- Place emote buttons in a circle
	local emotes = EmoteData.GetAll()
	local count = #emotes
	local radius = (WHEEL_SIZE / 2) - (BUTTON_SIZE / 2) - 12

	for i, emote in ipairs(emotes) do
		local angle = (i - 1) / count * math.pi * 2 - math.pi / 2
		local x = 0.5 + math.cos(angle) * radius / WHEEL_SIZE
		local y = 0.5 + math.sin(angle) * radius / WHEEL_SIZE

		local btn = Instance.new("TextButton")
		btn.Name = "Emote_" .. emote.id
		btn.Size = UDim2.fromOffset(BUTTON_SIZE, BUTTON_SIZE)
		btn.AnchorPoint = Vector2.new(0.5, 0.5)
		btn.Position = UDim2.fromScale(x, y)
		btn.BackgroundColor3 = Color3.fromRGB(28, 22, 34)
		btn.BackgroundTransparency = 0.15
		btn.AutoButtonColor = false
		btn.Text = emote.glyph
		btn.TextSize = 22
		btn.ZIndex = 5
		btn.Parent = container

		local btnCorner = Instance.new("UICorner")
		btnCorner.CornerRadius = UDim.new(1, 0)
		btnCorner.Parent = btn

		local btnStroke = Instance.new("UIStroke")
		btnStroke.Color = Color3.fromRGB(120, 95, 45)
		btnStroke.Thickness = 1.5
		btnStroke.Transparency = 0.3
		btnStroke.Parent = btn

		-- Name label below
		local label = Instance.new("TextLabel")
		label.Name = "Label"
		label.Size = UDim2.new(1.4, 0, 0, 14)
		label.AnchorPoint = Vector2.new(0.5, 0)
		label.Position = UDim2.new(0.5, 0, 1, 3)
		label.BackgroundTransparency = 1
		label.Text = emote.name
		label.TextColor3 = Color3.fromRGB(220, 210, 190)
		label.FontFace = FONT
		label.TextSize = 10
		label.TextTruncate = Enum.TextTruncate.AtEnd
		label.ZIndex = 5
		label.Parent = btn

		-- Hover
		btn.MouseEnter:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.12, Enum.EasingStyle.Quad), {
				BackgroundColor3 = Color3.fromRGB(60, 46, 70),
				BackgroundTransparency = 0,
			}):Play()
			TweenService:Create(btnStroke, TweenInfo.new(0.12), {
				Color = Color3.fromRGB(212, 172, 92),
				Transparency = 0,
			}):Play()
		end)
		btn.MouseLeave:Connect(function()
			TweenService:Create(btn, TweenInfo.new(0.15, Enum.EasingStyle.Quad), {
				BackgroundColor3 = Color3.fromRGB(28, 22, 34),
				BackgroundTransparency = 0.15,
			}):Play()
			TweenService:Create(btnStroke, TweenInfo.new(0.15), {
				Color = Color3.fromRGB(120, 95, 45),
				Transparency = 0.3,
			}):Play()
		end)

		-- Click → play
		btn.MouseButton1Click:Connect(function()
			playEmoteLocal(emote.id, true)
		end)
	end

	wheelGui   = gui
	wheelFrame = container
	return gui
end

-- ── Open / Close ─────────────────────────────────────────────────────────────
function EmoteController.OpenWheel()
	if wheelOpen then return end
	if not wheelGui then createWheelUI() end
	if wheelGui then
		wheelGui.Enabled = true
		-- Animate in
		if wheelFrame then
			wheelFrame.Size = UDim2.fromOffset(0, 0)
			TweenService:Create(wheelFrame, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
				Size = UDim2.fromOffset(WHEEL_SIZE, WHEEL_SIZE),
			}):Play()
		end
	end
	wheelOpen = true
end

function EmoteController.CloseWheel()
	if not wheelOpen then return end
	if wheelGui then
		if wheelFrame then
			local tw = TweenService:Create(wheelFrame, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
				Size = UDim2.fromOffset(0, 0),
			})
			tw:Play()
			tw.Completed:Connect(function()
				if wheelGui then wheelGui.Enabled = false end
			end)
		else
			wheelGui.Enabled = false
		end
	end
	wheelOpen = false
end

function EmoteController.ToggleWheel()
	if wheelOpen then
		EmoteController.CloseWheel()
	else
		EmoteController.OpenWheel()
	end
end

-- ── Movement / attack / skill cancel watcher ─────────────────────────────────
local function startCancelWatcher()
	if renderConn then renderConn:Disconnect() end
	renderConn = RunService.Heartbeat:Connect(function()
		if not isEmoting() then return end

		local char, hum, _ = getCharacter()
		if not char or not hum then
			EmoteController.CancelEmote()
			return
		end

		-- Cancel if dead
		if hum.Health <= 0 then
			EmoteController.CancelEmote()
			return
		end

		-- Cancel on movement (standing still required)
		if hum.MoveDirection.Magnitude > 0.05 then
			EmoteController.CancelEmote()
			return
		end

		-- Cancel on skill cast / attack / ult / mount / external cancel
		if char:GetAttribute("IsAttacking") == true
			or char:GetAttribute("IsSkillCasting") == true
			or char:GetAttribute("IsUltActive") == true
			or char:GetAttribute("Tumbling") == true
			or char:GetAttribute("Riding") ~= nil
			or char:GetAttribute("IsEmoting") == false then
			EmoteController.CancelEmote()
			return
		end
	end)
end

-- ── Init ─────────────────────────────────────────────────────────────────────
function EmoteController.Init()
	if isInit then return end
	isInit = true

	-- Create the wheel UI
	createWheelUI()

	-- T key toggles the emote wheel; Escape closes it
	table.insert(conns, UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe then return end

		if (input.KeyCode == Enum.KeyCode.Escape or input.KeyCode == Enum.KeyCode.ButtonB) and wheelOpen then
			EmoteController.CloseWheel()
			return
		end

		if input.KeyCode == Enum.KeyCode.T or input.KeyCode == Enum.KeyCode.DPadLeft then
			-- Don't open in menus / loading
			local char = player.Character
			if not char then return end
			local hum = char:FindFirstChildOfClass("Humanoid")
			if not hum or hum.Health <= 0 then return end

			-- If already emoting and the wheel is closed, cancel the emote
			if isEmoting() and not wheelOpen then
				EmoteController.CancelEmote()
				return
			end

			EmoteController.ToggleWheel()
		end

		-- Number keys 1-9 as quick emote shortcuts (when wheel is open)
		if wheelOpen then
			local num = input.KeyCode.Value - Enum.KeyCode.One.Value + 1
			if num >= 1 and num <= #EmoteData.GetAll() then
				local emote = EmoteData.GetAll()[num]
				if emote then
					playEmoteLocal(emote.id, true)
				end
			end
		end
	end))

	-- Listen for other players' emotes
	pcall(function()
		local remote = Network.GetRemoteEvent(Network.Remotes.EmotePlay)
		remote.OnClientEvent:Connect(function(payload: any)
			if typeof(payload) ~= "table" then return end
			local emotingPlayer = payload.player :: Player?
			local emoteId       = payload.emoteId :: string?

			if not emotingPlayer or not emoteId then return end

			if emoteId == "__cancel" then
				cancelRemoteEmote(emotingPlayer)
			else
				playRemoteEmote(emotingPlayer, emoteId)
			end
		end)
	end)

	-- Watch for cancel conditions
	startCancelWatcher()

	-- On respawn, reset emote state
	player.CharacterAdded:Connect(function()
		EmoteController.CancelEmote()
		if wheelOpen then
			EmoteController.CloseWheel()
		end
	end)

	print("[EmoteController] Emote system ready. Press T to open the emote wheel.")
end

function EmoteController.Stop()
	EmoteController.CancelEmote()
	if wheelOpen then EmoteController.CloseWheel() end
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	for _, c in ipairs(conns) do
		c:Disconnect()
	end
	conns = {}
	if wheelGui then
		wheelGui:Destroy()
		wheelGui = nil
		wheelFrame = nil
	end
end

return EmoteController
