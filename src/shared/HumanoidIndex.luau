--!strict
--[[
	HumanoidIndex.luau
	Every model in the Workspace with a Humanoid (mobs, bosses, players,
	allies, decoys), kept up to date as they come and go, on the server and on
	each client.

	  HumanoidIndex.List() → { Model }        (a fresh array, safe to keep)
	  HumanoidIndex.Each() → { [Model]: Humanoid }  (the live map: don't modify)

	Performance rule: never walk Workspace:GetDescendants() to find targets.
	The generated dungeon is tens of thousands of instances, and targets are
	looked up for every swing, bullet, ricochet and blast.
--]]

local Workspace = game:GetService("Workspace")

local HumanoidIndex = {}

local models: { [Model]: Humanoid } = {}

local function register(h: Instance)
	if not h:IsA("Humanoid") then return end
	local model = h.Parent
	if not (model and model:IsA("Model")) then return end
	models[model] = h
	local conn: RBXScriptConnection? = nil
	conn = h.AncestryChanged:Connect(function()
		if h.Parent == model and h:IsDescendantOf(Workspace) then return end
		if models[model] == h then models[model] = nil end
		if conn then conn:Disconnect() end
		-- (still in the world, in another model: follow it there)
		if h:IsDescendantOf(Workspace) then register(h) end
	end)
end

for _, d in ipairs(Workspace:GetDescendants()) do register(d) end
Workspace.DescendantAdded:Connect(register)

function HumanoidIndex.Each(): { [Model]: Humanoid }
	return models
end

function HumanoidIndex.List(): { Model }
	local out = {}
	for m in pairs(models) do table.insert(out, m) end
	return out
end

return HumanoidIndex
