--!strict
--[[
	AccountManager.luau
	The saved account level (1..100). XP comes from runs: every kill, every
	cleared room and every boss (MobManager → PlayerStats). Each level costs
	more than the last (shared AccountLevel curve).

	Replicated as player attributes, which the HUD's level bar, the campfire
	roster and the seated heroes' name tags read:
	  AccountLevel, AccountXP, AccountXPToNext
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local AccountLevel = require(Shared:WaitForChild("AccountLevel"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local RunStats = require(script.Parent:WaitForChild("RunStats"))

local AccountManager = {}

-- XP for claiming a cleared room's reward (on top of the kills in it).
AccountManager.ROOM_XP = 150

local function account(player: Player): { level: number, xp: number }?
	local p = PlayerData.Get(player) :: any
	if not p then return nil end
	if typeof(p.account) ~= "table" then p.account = { level = 1, xp = 0 } end
	local a = p.account
	a.level = math.clamp(math.floor(tonumber(a.level) or 1), 1, AccountLevel.MAX)
	a.xp = math.max(0, math.floor(tonumber(a.xp) or 0))
	return a
end

function AccountManager.Sync(player: Player)
	local a = account(player)
	if not a then return end
	local toNext = AccountLevel.XpToNext(a.level)
	player:SetAttribute("AccountLevel", a.level)
	player:SetAttribute("AccountXP", a.xp)
	player:SetAttribute("AccountXPToNext", toNext)
	-- The in-run level bar.
	Network.GetRemoteEvent(Network.Remotes.TomeProgress):FireClient(player, {
		level = a.level,
		xp = a.xp,
		xpToNext = toNext,
		max = a.level >= AccountLevel.MAX,
	})
end

function AccountManager.GetLevel(player: Player): number
	local a = account(player)
	return if a then a.level else 1
end

-- Add account XP, levelling up as many times as it covers (capped at 100).
function AccountManager.AddXP(player: Player, amount: number)
	local a = account(player)
	if not a or amount <= 0 or a.level >= AccountLevel.MAX then return end
	a.xp += math.floor(amount + 0.5)
	RunStats.Add(player, "xp", math.floor(amount + 0.5))
	while a.level < AccountLevel.MAX and a.xp >= AccountLevel.XpToNext(a.level) do
		a.xp -= AccountLevel.XpToNext(a.level)
		a.level += 1
	end
	if a.level >= AccountLevel.MAX then a.xp = 0 end
	PlayerData.MarkDirty(player)
	AccountManager.Sync(player)
end

function AccountManager.Init()
	PlayerData.OnLoaded(function(player: Player)
		AccountManager.Sync(player)
	end)
end

return AccountManager
