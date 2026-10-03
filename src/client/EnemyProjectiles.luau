--!strict
--[[
	EnemyProjectiles.luau
	Every enemy projectile (tagged "EnemyProjectile": skeleton arrows,
	necromancer soul bolts, boss orbs, the dragon's fireballs) is drawn so it
	reads in the dark: a bright white outline seen through everything, a pale
	fill, and a small white light around it.
--]]

local CollectionService = game:GetService("CollectionService")

local EnemyProjectiles = {}

local TAG = "EnemyProjectile"
-- (Roblox draws at most 31 Highlights at once; leave room for the rest)
local MAX_OUTLINES = 20
local outlined = 0

local function mark(inst: Instance)
	if not inst:IsA("BasePart") then return end
	local part = inst :: BasePart
	if outlined < MAX_OUTLINES then
		outlined += 1
		local hl = Instance.new("Highlight")
		hl.Name = "ProjectileOutline"
		hl.Adornee = part
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.OutlineTransparency = 0
		hl.FillColor = Color3.new(1, 1, 1)
		hl.FillTransparency = 0.55
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.Parent = part
		hl.Destroying:Connect(function() outlined -= 1 end)
	end
	local light = Instance.new("PointLight")
	light.Name = "ProjectileGlow"
	light.Color = Color3.fromRGB(235, 240, 255)
	light.Range = 7
	light.Brightness = 1.6
	light.Shadows = false
	light.Parent = part
end

function EnemyProjectiles.Init()
	CollectionService:GetInstanceAddedSignal(TAG):Connect(mark)
	for _, p in ipairs(CollectionService:GetTagged(TAG)) do mark(p) end
end

return EnemyProjectiles
