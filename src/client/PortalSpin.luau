--!strict
--[[
	PortalSpin.luau
	Every portal's swirl turning (ArcadeKit's Gate_Portal: its swirl images
	are tagged "PortalSwirl", each with the speed it turns at, "Spin", in
	degrees a second; the paler inner one turns back against the outer). Only
	the lit ones (an open portal) near the camera are turned.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PortalSpin = {}

local TAG = "PortalSwirl"
local RANGE = 300 -- (the swirl isn't drawn past this anyway: its SurfaceGui's MaxDistance)

local swirls: { [ImageLabel]: number } = {}

local function add(inst: Instance)
	if inst:IsA("ImageLabel") then
		swirls[inst] = tonumber(inst:GetAttribute("Spin")) or 60
	end
end

function PortalSpin.Init()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do add(inst) end
	CollectionService:GetInstanceAddedSignal(TAG):Connect(add)
	CollectionService:GetInstanceRemovedSignal(TAG):Connect(function(inst)
		swirls[inst :: ImageLabel] = nil
	end)
	RunService.RenderStepped:Connect(function()
		if next(swirls) == nil then return end
		local cam = Workspace.CurrentCamera
		if not cam then return end
		local eye = cam.CFrame.Position
		local t = os.clock()
		for img, spin in pairs(swirls) do
			local sg = img.Parent
			local part = sg and sg.Parent
			if sg and sg:IsA("SurfaceGui") and sg.Enabled and part and part:IsA("BasePart") and (part.Position - eye).Magnitude < RANGE then
				img.Rotation = (t * spin) % 360
			end
		end
	end)
end

return PortalSpin
