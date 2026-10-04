--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- TorchLightController.luau
-- Every character's outline (AtmosphereManager.AttachCharacterOutline), put on
-- as it spawns; and the lobby's flame lights (tagged "CandleLight" by
-- LobbyBuilder) flickering gently, each about its own BaseBrightness and Phase.
--
-- One Highlight per character at most (each is a full extra pass over the
-- screen): a Legendary aura's own glowing outline (GearAuraHighlight, from
-- the server) stands in for the black one while it's worn, and only your own
-- weapon's finish keeps its Highlight (GearHighlight) on your screen.
-- (There is no player torch: the dungeons are lit bright and clear.)
-- ─────────────────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local AtmosphereManager = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AtmosphereManager"))

local TorchLightController = {}

local renderConnection: RBXScriptConnection? = nil

local function syncOutlines(plr: Player, char: Model)
	local outline = char:FindFirstChild("CharacterOutline")
	local aura = char:FindFirstChild("GearAuraHighlight")
	if outline and outline:IsA("Highlight") then
		local want = aura == nil
		if outline.Enabled ~= want then outline.Enabled = want end
	end
	if plr ~= Players.LocalPlayer then
		for _, d in ipairs(char:GetDescendants()) do
			if d.Name == "GearHighlight" and d:IsA("Highlight") and d.Enabled then d.Enabled = false end
		end
	end
end

local function setupCharacter(plr: Player, char: Model)
	AtmosphereManager.AttachCharacterOutline(char)
	syncOutlines(plr, char)
	char.DescendantAdded:Connect(function(d)
		if d.Name == "GearAuraHighlight" or d.Name == "GearHighlight" then task.defer(syncOutlines, plr, char) end
	end)
	char.DescendantRemoving:Connect(function(d)
		if d.Name == "GearAuraHighlight" then task.defer(syncOutlines, plr, char) end
	end)
end

local function setupPlayer(plr: Player)
	if plr.Character then setupCharacter(plr, plr.Character) end
	plr.CharacterAdded:Connect(function(char)
		setupCharacter(plr, char)
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
