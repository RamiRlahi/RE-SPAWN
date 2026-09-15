local StarterGui = game:GetService("StarterGui")

local function disableBackpack()
	local maxAttempts = 20
	local attempts = 0
	while attempts < maxAttempts do
		local success = pcall(function()
			StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		end)
		if success then
			break
		end
		attempts += 1
		task.wait(0.2)
	end
end

task.spawn(disableBackpack)

return disableBackpack