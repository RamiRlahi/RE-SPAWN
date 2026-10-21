--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- EmoteManager.luau (Server)
--
-- Validates and relays emote requests from one client to all others.
-- Rate-limited per player (no faster than 1 emote per second per player).
-- ─────────────────────────────────────────────────────────────────────────────

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")

local Shared    = ReplicatedStorage:WaitForChild("Shared")
local Network   = require(Shared:WaitForChild("Network"))
local EmoteData = require(Shared:WaitForChild("EmoteData"))

local EmoteManager = {}

local lastEmoteTime: { [Player]: number } = {}
local RATE_LIMIT = 0.8 -- seconds between emotes per player

function EmoteManager.Init()
	local remote = Network.GetRemoteEvent(Network.Remotes.EmotePlay)

	remote.OnServerEvent:Connect(function(sender: Player, emoteId: any)
		-- Validate
		if typeof(emoteId) ~= "string" then return end
		if #emoteId > 40 then return end

		-- Must be alive
		local char = sender.Character
		if not char then return end
		local hum = char:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then return end

		-- Cancel request (bypasses rate limit so cancels are instant)
		if emoteId == "__cancel" then
			char:SetAttribute("IsEmoting", false)
			for _, plr in ipairs(Players:GetPlayers()) do
				if plr ~= sender then
					remote:FireClient(plr, { player = sender, emoteId = "__cancel" })
				end
			end
			return
		end

		-- Rate limit for starting new emotes
		local now = os.clock()
		local last = lastEmoteTime[sender] or 0
		if now - last < RATE_LIMIT then return end
		lastEmoteTime[sender] = now

		-- Validate emote exists
		local emote = EmoteData.Get(emoteId)
		if not emote then return end

		-- Can't emote while moving or casting
		if hum.MoveDirection.Magnitude > 0.1 then return end
		if char:GetAttribute("IsSkillCasting") == true then return end
		if char:GetAttribute("IsUltActive") == true then return end
		if char:GetAttribute("Tumbling") == true then return end

		-- Set attribute on character (so others see it)
		char:SetAttribute("IsEmoting", true)

		-- Relay to all other clients
		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= sender then
				remote:FireClient(plr, { player = sender, emoteId = emoteId })
			end
		end
	end)

	-- Cleanup on leave
	Players.PlayerRemoving:Connect(function(plr)
		lastEmoteTime[plr] = nil
	end)

	print("[EmoteManager] Server emote relay ready.")
end

return EmoteManager
