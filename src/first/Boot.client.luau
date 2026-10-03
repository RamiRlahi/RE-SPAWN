--!strict
-- The first thing a player sees: our loading screen replaces Roblox's default
-- one on the very first frame, reading "AWAKENING THE WORLD…" while the game
-- itself arrives. The menu loader (client MenuLoader) takes the same screen
-- over from there and only lifts it once the menu's critical assets are in.

local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")

local LoadingCover = require(script.Parent:WaitForChild("LoadingCover"))

LoadingCover.Show()
LoadingCover.SetProgress(0.02, "AWAKENING THE WORLD…")
ReplicatedFirst:RemoveDefaultLoadingScreen()

-- The logo first, so the loading screen itself is complete.
task.spawn(function()
	pcall(function()
		ContentProvider:PreloadAsync({ LoadingCover.Logo })
	end)
end)

-- While the place streams in, creep the bar toward 10% (the menu loader
-- reports real progress after this).
local t0 = os.clock()
while not game:IsLoaded() do
	local k = 1 - math.exp(-(os.clock() - t0) / 4)
	LoadingCover.SetProgress(0.02 + 0.08 * k)
	task.wait(0.1)
end
LoadingCover.SetProgress(0.1)
