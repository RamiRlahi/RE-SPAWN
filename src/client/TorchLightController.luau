--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- TorchLightController.luau
-- Every character's outline (AtmosphereManager.AttachCharacterOutline), put on
-- as it spawns; and the lobby's flame lights (tagged "CandleLight" by
-- LobbyBuilder) flickering gently, each about its own BaseBrightness and Phase.
-- (There is no player torch: the dungeons are lit bright and clear.)
-- ─────────────────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local AtmosphereManager = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AtmosphereManager"))

local TorchLightController = {}

local renderConnection: RBXScriptConnection? = nil

local function setupPlayer(plr: Player)
	if plr.Character then AtmosphereManager.AttachCharacterOutline(plr.Character) end
	plr.CharacterAdded:Connect(function(char)
		AtmosphereManager.AttachCharacterOutline(char)
	end)
end

function TorchLightController.Start()
	for _, plr in ipairs(Players:GetPlayers()) do
		setupPlayer(plr)
	end
	Players.PlayerAdded:Connect(setupPlayer)

	if renderConnection then return end
	renderConnection = RunService.RenderStepped:Connect(function()
		local t = os.clock()
		for _, light in ipairs(CollectionService:GetTagged("CandleLight")) do
			if light:IsA("Light") then
				local base = light:GetAttribute("BaseBrightness") or 2.4
				local phase = light:GetAttribute("Phase") or 0
				local f = math.sin((t + phase) * 8.3) * 0.06 + (math.noise((t + phase) * 4.1, phase, 0) or 0) * 0.18
				light.Brightness = base * (1 + f)
			end
		end
	end)
end

function TorchLightController.Stop()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

return TorchLightController
