local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassData = require(Shared:WaitForChild("ClassData"))
local Network = require(Shared:WaitForChild("Network"))

local ClassManager = {}

type PlayerCallback = (player: Player, classId: string) -> ()
local onClassSelectedCallbacks: { PlayerCallback } = {}

function ClassManager.Init()
	local selectClassRemote = Network.GetRemoteEvent(Network.Remotes.SelectClass)
	local classConfirmedRemote = Network.GetRemoteEvent(Network.Remotes.ClassConfirmed)

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

		-- Assign class attribute to Player
		player:SetAttribute("SelectedClass", classId)
		player:SetAttribute("ClassName", classInfo.name)
		player:SetAttribute("ClassRole", classInfo.role)

		-- Assign to character if present
		local character = player.Character
		if character then
			character:SetAttribute("Class", classId)
		end

		print(`[ClassManager] {player.Name} selected class: {classInfo.name} ({classId})`)

		-- Notify client
		classConfirmedRemote:FireClient(player, classId)

		-- Trigger internal listeners (e.g. PlayerManager for unfreeze)
		for _, cb in ipairs(onClassSelectedCallbacks) do
			task.spawn(cb, player, classId)
		end
	end)
end

function ClassManager.OnClassSelected(callback: PlayerCallback)
	table.insert(onClassSelectedCallbacks, callback)
end

return ClassManager
