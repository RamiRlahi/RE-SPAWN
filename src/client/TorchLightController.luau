--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- TorchLightController.luau
-- Client-side organic flicker & dynamic motion loop for player torch lights.
-- ─────────────────────────────────────────────────────────────────────────────

local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

local TorchLightController = {}

local renderConnection: RBXScriptConnection? = nil

function TorchLightController.Start()
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

		-- Apply flicker to local player & nearby player torch lights
		for _, plr in ipairs(Players:GetPlayers()) do
			local char = plr.Character
			if char then
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
