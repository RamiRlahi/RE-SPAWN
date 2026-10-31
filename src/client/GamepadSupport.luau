--!strict
--[[
	GamepadSupport.luau
	Playing on a controller. The actions (attack, skills, dash, sprint, the
	mount, the menu) are matched to its buttons wherever they're read
	(SettingsConfig.GamepadBinds / Matches), and the aim to its right stick
	(AimInput). This module does the rest: whenever a screen wants a pointer
	(the mouse is shown: picking a tome, a fallen hero's choice, a panel, the
	lobby's menus, the title and class screens) the controller drives Roblox's
	own virtual cursor (the left stick moves it, A clicks); otherwise the
	sticks are the character's.

	It also moves two of Roblox's own buttons to fit the layout
	(SettingsConfig.GamepadBinds): jump from A (the ultimate's now) to LB,
	and every prompt from X (a skill's) to RT, the attack's: with a prompt
	showing close by, RT uses it instead of attacking ("PromptNear", read by
	the attack scripts).

	  GamepadSupport.Init()
--]]

local Players = game:GetService("Players")
local GamepadService = game:GetService("GamepadService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local AimInput = require(script.Parent:WaitForChild("AimInput"))

local GamepadSupport = {}

local player = Players.LocalPlayer
local cursorOn = false

-- Does a screen want a pointer right now?
local function wantsPointer(): boolean
	-- (picking a tome or relic: ChoiceScreen's own controls, not a cursor)
	if player:GetAttribute("ChoosingTome") == true then return false end
	if player:GetAttribute("SettingsOpen") == true then return true end
	-- (the lobby: only its menus; walking about, the sticks are yours)
	if player:GetAttribute("InHub") == true then return player:GetAttribute("UIModal") == true end
	return UserInputService.MouseIconEnabled
end

-- A's jump held off (A is the ultimate's) while the sticks are the
-- character's: the Jumping state switched off on this client (nothing else
-- touches it). Not by sinking A: a sunk press reaches every script as
-- already handled, and the skills skip those. LB switches it on for its jump.
local aBlocked = false
local lbJumpUntil = 0 -- (LB's jump under way: left alone till then)
local function humanoid(): Humanoid?
	local char = player.Character
	return char and char:FindFirstChildOfClass("Humanoid")
end
local function blockA(on: boolean)
	if os.clock() < lbJumpUntil then return end
	local hum = humanoid()
	if on == aBlocked and (not hum or hum:GetStateEnabled(Enum.HumanoidStateType.Jumping) ~= on) then return end
	aBlocked = on
	if hum then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, not on) end
end

function GamepadSupport.Init()
	-- LB jumps
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or cursorOn or input.KeyCode ~= Enum.KeyCode.ButtonL1 then return end
		local hum = humanoid()
		if not hum or hum.Health <= 0 then return end
		lbJumpUntil = os.clock() + 0.25
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, true)
		-- (ChangeState, not Jump = true: Roblox's controls rewrite Jump every frame)
		local st = hum:GetState()
		if st ~= Enum.HumanoidStateType.Freefall and st ~= Enum.HumanoidStateType.Jumping and st ~= Enum.HumanoidStateType.Seated then
			hum:ChangeState(Enum.HumanoidStateType.Jumping)
		end
		-- (and off again once it's away, while A is still the ultimate's)
		task.delay(0.2, function()
			if aBlocked and hum.Parent then hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false) end
		end)
	end)
	-- every prompt on RT, and RT holding its attack while one shows
	local shown: { [ProximityPrompt]: boolean } = {}
	local function count()
		player:SetAttribute("PromptNear", next(shown) ~= nil or nil)
	end
	ProximityPromptService.PromptShown:Connect(function(prompt: ProximityPrompt)
		prompt.GamepadKeyCode = Enum.KeyCode.ButtonR2
		shown[prompt] = true
		count()
		local conn
		conn = prompt.PromptHidden:Connect(function()
			conn:Disconnect()
			shown[prompt] = nil
			count()
		end)
	end)
	local last = 0
	RunService.Heartbeat:Connect(function()
		local now = os.clock()
		if now - last < 0.1 then return end
		last = now
		local want = AimInput.UsingGamepad() and wantsPointer()
		blockA(AimInput.UsingGamepad() and not want)
		if want == cursorOn then return end
		cursorOn = want
		pcall(function()
			if want then
				GamepadService:EnableGamepadCursor(nil)
			else
				GamepadService:DisableGamepadCursor()
			end
		end)
	end)
end

return GamepadSupport
