local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassData = require(Shared:WaitForChild("ClassData"))
local Network = require(Shared:WaitForChild("Network"))

local ClassManager = {}

type PlayerCallback = (player: Player, classId: string) -> ()
local onClassSelectedCallbacks: { PlayerCallback } = {}
local gate: ((player: Player, classId: string) -> boolean)? = nil

function ClassManager.Init()
	local selectClassRemote = Network.GetRemoteEvent(Network.Remotes.SelectClass)

	selectClassRemote.OnServerEvent:Connect(function(player: Player, classId: any)
		if typeof(classId) ~= "string" then
			warn(`[ClassManager] Invalid class ID payload from {player.Name}`)
			return
		end

		local classInfo = ClassData.GetClass(classId)
		if not classInfo then
			warn(`[ClassManager] Unknown class ID '{classId}' requested by {player.Name}`)
			return
		end

		-- Assign class attributes to Player
		if not ClassData.IsPlayable(classId) then
			warn(`[ClassManager] {player.Name} tried to pick locked class '{classId}'`)
			return
		end

		player:SetAttribute("SelectedClass", classId)
		player:SetAttribute("ClassName", classInfo.name)
		player:SetAttribute("ClassRole", classInfo.role)

		-- Assign to character if present
		local character = player.Character
		if character then
			character:SetAttribute("Class", classId)
		end

		print(`[ClassManager] {player.Name} confirmed class: {classInfo.name} ({classId})`)

		-- The campfire takes over from here (the party gathers, readies up and
		-- leaves through the portal); without it, straight into the dungeon.
		if gate and gate(player, classId) then return end
		ClassManager.Enter(player, classId)
	end)
end

-- Record `classId` as the player's class (used when it changes at the
-- campfire). Returns false for an unknown or locked class.
function ClassManager.SetClass(player: Player, classId: string): boolean
	local classInfo = ClassData.GetClass(classId)
	if not classInfo or not ClassData.IsPlayable(classId) then return false end
	player:SetAttribute("SelectedClass", classId)
	player:SetAttribute("ClassName", classInfo.name)
	player:SetAttribute("ClassRole", classInfo.role)
	if player.Character then player.Character:SetAttribute("Class", classId) end
	return true
end

-- gate(player, classId) -> true when it will call Enter itself later.
function ClassManager.SetGate(fn: (player: Player, classId: string) -> boolean)
	gate = fn
end

-- Sends the player into the dungeon as `classId`: confirms it to the client
-- (which fades into the game) and runs every listener (weapon, teleport, run
-- start). Also used to respawn after a death.
function ClassManager.Enter(player: Player, classId: string)
	local character = player.Character
	if character then character:SetAttribute("Class", classId) end
	Network.GetRemoteEvent(Network.Remotes.ClassConfirmed):FireClient(player, classId)
	for _, cb in ipairs(onClassSelectedCallbacks) do
		task.spawn(cb, player, classId)
	end
end

function ClassManager.OnClassSelected(callback: PlayerCallback)
	table.insert(onClassSelectedCallbacks, callback)
end

return ClassManager
