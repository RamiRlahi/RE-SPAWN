--[[
	AnimationManager (Server-Side)
	Coordinates class animation states and server-side fallbacks.
--]]

local Players = game:GetService("Players")

local AnimationManager = {}

function AnimationManager.PlayLobbyIdle(player: Player)
	-- Handled by client AnimationController cleanly
end

function AnimationManager.PlayClassIdle(player: Player, classId: string)
	-- Handled by client AnimationController upon ClassConfirmed
end

function AnimationManager.Cleanup(player: Player)
	-- Cleanup if needed
end

function AnimationManager.Init()
	Players.PlayerRemoving:Connect(function(player: Player)
		AnimationManager.Cleanup(player)
	end)
end

return AnimationManager
