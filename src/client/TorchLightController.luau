--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- TorchLightController.luau
-- Client-side organic flicker & dynamic motion loop for player torch lights.
-- Instant client-side torch light attachment upon character spawn.
-- ─────────────────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService        = game:GetService("RunService")
local Players           = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared", 5)
local AtmosphereManager = Shared and require(Shared:WaitForChild("AtmosphereManager", 5) :: ModuleScript) or nil

local TorchLightController = {}

local renderConnection: RBXScriptConnection? = nil

local function ensureTorchAttached(char: Model)
	if AtmosphereManager then
		AtmosphereManager.AttachTorchLight(char)
	else
		local rootPart = (char:FindFirstChild("HumanoidRootPart") or char.PrimaryPart) :: BasePart?
		if rootPart and not rootPart:FindFirstChild("PlayerTorchLight") then
			local torchLight = Instance.new("PointLight")
			torchLight.Name = "PlayerTorchLight"
			torchLight.Color = Color3.fromRGB(255, 175, 75)
			torchLight.Range = 32
			torchLight.Brightness = 2.4
			torchLight.Shadows = true
			torchLight.Parent = rootPart
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

		local baseBrightness = 2.4
		local baseRange = 32.0

		local currentBrightness = baseBrightness + flicker1 + flicker2 + noiseVal
		local currentRange = baseRange + flicker1 * 3.5 + noiseVal * 2.5

		-- Apply flicker & ensure torch exists for local & nearby player characters
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if char then
				ensureTorchAttached(char)
				local rootPart = char:FindFirstChild("HumanoidRootPart") :: BasePart?
				if rootPart then
					local torchLight = rootPart:FindFirstChild("PlayerTorchLight") :: PointLight?
					if torchLight then
						torchLight.Brightness = math.clamp(currentBrightness, 1.8, 3.1)
						torchLight.Range = math.clamp(currentRange, 26, 38)
					end
				end
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
