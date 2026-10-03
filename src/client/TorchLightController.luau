--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- TorchLightController.luau
-- Client-side organic flicker & dynamic motion loop for player torch lights.
-- Instant client-side torch light attachment upon character spawn.
-- ─────────────────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
local AtmosphereManager = Shared and require(Shared:WaitForChild("AtmosphereManager", 5) :: ModuleScript) or nil

local TorchLightController = {}

local renderConnection: RBXScriptConnection? = nil

local function ensureTorchAttached(char: Model)
	if AtmosphereManager then
		AtmosphereManager.AttachTorchLight(char)
		AtmosphereManager.AttachCharacterOutline(char)
	else
		-- Fallback torch (only if AtmosphereManager failed to load) — currently off.
		local rootPart = nil :: BasePart?
		if rootPart and not rootPart:FindFirstChild("PlayerTorchLight", true) then
			local torchLight = Instance.new("PointLight")
			torchLight.Name = "PlayerTorchLight"
			torchLight.Color = Color3.fromRGB(255, 175, 75)
			torchLight.Range = 32
			torchLight.Brightness = 1.3
			torchLight.Shadows = true
			torchLight.Parent = rootPart
		end
		if not char:FindFirstChild("CharacterOutline") then
			local highlight = Instance.new("Highlight")
			highlight.Name = "CharacterOutline"
			highlight.FillTransparency = 1
			highlight.OutlineColor = Color3.fromRGB(0, 0, 0)
			highlight.OutlineTransparency = 0
			highlight.DepthMode = Enum.HighlightDepthMode.Occluded
			highlight.Adornee = char
			highlight.Parent = char
		end
	end
end

local function setupPlayer(plr: Player)
	if plr.Character then
		ensureTorchAttached(plr.Character)
	end
	plr.CharacterAdded:Connect(function(char)
		ensureTorchAttached(char)
	end)
end

function TorchLightController.Start()
	-- Listen for all current & new players to attach torch immediately client-side
	for _, plr in ipairs(Players:GetPlayers()) do
		setupPlayer(plr)
	end
	Players.PlayerAdded:Connect(setupPlayer)

	if renderConnection then return end

	renderConnection = RunService.RenderStepped:Connect(function()
		local t = os.clock()

		-- Organic torch flicker waveform calculations
		local flicker1 = math.sin(t * 9.7) * 0.14
		local flicker2 = math.sin(t * 23.1) * 0.08
		local noiseVal = (math.noise(t * 6.5, 0, 0) or 0) * 0.28

		local baseBrightness = (AtmosphereManager and AtmosphereManager.Config and AtmosphereManager.Config.TorchBrightness) or 1.3
		local baseRange = (AtmosphereManager and AtmosphereManager.Config and AtmosphereManager.Config.TorchRange) or 32.0

		-- Flicker was tuned for a 2.8 torch; scale it so a dimmer torch doesn't strobe.
		local currentBrightness = baseBrightness + (flicker1 + flicker2 + noiseVal) * (baseBrightness / 2.8)

		-- Apply flicker & ensure torch exists for local & nearby player characters
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if char then
				ensureTorchAttached(char)
				local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if rootPart then
					-- One torch per character: this client may have attached its
					-- own before the server's replicated in; drop the extra.
					-- (the same for the high spotlight)
					local spread: Instance? = nil
					for _, d in ipairs(rootPart:GetChildren()) do
						if d.Name == "TorchSpreadMount" then
							if spread then d:Destroy() else spread = d end
						end
					end
					local torchLight: PointLight? = nil
					for _, d in ipairs(rootPart:GetDescendants()) do
						if d.Name == "PlayerTorchLight" and d:IsA("PointLight") then
							if torchLight then
								local mount = d.Parent
								d:Destroy()
								if mount and mount.Name == "TorchLightMount" and #mount:GetChildren() == 0 then mount:Destroy() end
							else
								torchLight = d
							end
						end
					end
					if torchLight then
						-- Flicker the brightness only: changing a moving light's
						-- Range every frame makes the engine re-light the area
						-- each time, and the glow trails behind the player.
						torchLight.Brightness = math.clamp(currentBrightness, baseBrightness * 0.7, baseBrightness * 1.35)
						if torchLight.Range ~= baseRange then torchLight.Range = baseRange end
					end
				end
			end
		end

		-- Candle clusters placed by the dungeon generator: gentle, desynced flicker.
		for _, light in ipairs(CollectionService:GetTagged("CandleLight")) do
			if light:IsA("PointLight") then
				local base = light:GetAttribute("BaseBrightness") or 2.4
				local phase = light:GetAttribute("Phase") or 0
				local f = math.sin((t + phase) * 8.3) * 0.06 + (math.noise((t + phase) * 4.1, phase, 0) or 0) * 0.18
				light.Brightness = base * (1 + f)
			end
		end
	end)

	print("[TorchLightController] Dynamic Torch Flicker Controller started.")
end

function TorchLightController.Stop()
	if renderConnection then
		renderConnection:Disconnect()
		renderConnection = nil
	end
end

return TorchLightController
