local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local FOLDER_NAME = "NetworkRemotes"

local Network = {}

-- Predefined remote names
Network.Remotes = {
	SelectClass = "SelectClass",
	ClassConfirmed = "ClassConfirmed",
	SaveSettings = "SaveSettings",
	SpawnInChurch = "SpawnInChurch",
}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(FOLDER_NAME)
	if not folder then
		if RunService:IsServer() then
			folder = Instance.new("Folder")
			folder.Name = FOLDER_NAME
			folder.Parent = ReplicatedStorage
		else
			folder = ReplicatedStorage:WaitForChild(FOLDER_NAME) :: Folder
		end
	end
	return folder :: Folder
end

-- Auto-create all remotes on server at load time
if RunService:IsServer() then
	local folder = getFolder()
	for _, remoteName in pairs(Network.Remotes) do
		if not folder:FindFirstChild(remoteName) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = remoteName
			remote.Parent = folder
		end
	end
end

function Network.GetRemoteEvent(name: string): RemoteEvent
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name) :: RemoteEvent
		end
	end
	return remote :: RemoteEvent
end

function Network.GetRemoteFunction(name: string): RemoteFunction
	local folder = getFolder()
	local remote = folder:FindFirstChild(name)
	if not remote then
		if RunService:IsServer() then
			remote = Instance.new("RemoteFunction")
			remote.Name = name
			remote.Parent = folder
		else
			remote = folder:WaitForChild(name) :: RemoteFunction
		end
	end
	return remote :: RemoteFunction
end

return Network
