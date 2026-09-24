--[[
	AllyHover.luau
	Client-side: detects friendly ally rigs near the cursor and shows the heal icon
	on the hovered ally. SkillController uses AllyHover.getHoveredAlly() so the cleric
	heal (Divine Touch) lands on the ally instead of the player.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local HOVER_TOLERANCE = 6  -- studs from the cursor ray to count as "hovering"

local HEAL_ICON_TEXTURE: string? = nil
local decal = ReplicatedStorage:WaitForChild("healicon", 10)
if decal and decal:IsA("Decal") then
	HEAL_ICON_TEXTURE = decal.Texture
end

local AllyHover = {}
local currentAlly: Model? = nil
local currentGui: BillboardGui? = nil

local function getAllies(): { Model }
	local folder = Workspace:FindFirstChild("Allies")
	if not folder then return {} end
	local list = {}
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("IsAlly") == true then
			table.insert(list, c)
		end
	end
	return list
end

local function pickHoveredAlly(): Model?
	local mouse = UserInputService:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mouse.X, mouse.Y)
	local best: Model? = nil
	local bestDist: number? = nil
	for _, ally in ipairs(getAllies()) do
		local root = ally:FindFirstChild("HumanoidRootPart")
		if root then
			local toPoint = root.Position - ray.Origin
			local along = toPoint:Dot(ray.Direction)
			if along > 0 then
				local closest = ray.Origin + ray.Direction * along
				local dist = (root.Position - closest).Magnitude
				if dist <= HOVER_TOLERANCE then
					if not bestDist or dist < bestDist then
						best, bestDist = ally, dist
					end
				end
			end
		end
	end
	return best
end

local function clearGui()
	if currentGui then
		currentGui:Destroy()
		currentGui = nil
	end
end

local function attachGui(ally: Model)
	clearGui()
	local anchor = ally:FindFirstChild("Head") or ally:FindFirstChild("HumanoidRootPart")
	if not anchor then return end

	local bb = Instance.new("BillboardGui")
	bb.Name = "AllyHealIcon"
	bb.Size = UDim2.new(0, 64, 0, 64)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = true
	bb.Adornee = anchor
	bb.Parent = anchor

	local img = Instance.new("ImageLabel")
	img.Name = "Icon"
	img.Size = UDim2.fromScale(1, 1)
	img.BackgroundTransparency = 1
	img.ImageTransparency = 0
	img.ScaleType = Enum.ScaleType.Fit
	img.Image = HEAL_ICON_TEXTURE or ""
	img.Parent = bb

	currentGui = bb
end

function AllyHover.getHoveredAlly(): Model?
	return currentAlly
end

function AllyHover.Init()
	RunService.RenderStepped:Connect(function()
		local ally = pickHoveredAlly()
		if ally ~= currentAlly then
			currentAlly = ally
			if ally then
				attachGui(ally)
			else
				clearGui()
			end
		elseif currentAlly and (not currentGui or not currentGui.Parent) then
			-- ally still hovered but its gui got cleaned up (e.g. respawned)
			if currentAlly.Parent then
				attachGui(currentAlly)
			else
				currentAlly = nil
				clearGui()
			end
		end
	end)
end

return AllyHover
