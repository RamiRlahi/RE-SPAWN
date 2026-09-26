--[[
	AllyManager.luau
	Server-side test allies: spawns a few friendly rigs scattered on the map.
	They can be damaged (go "Downed"), healed, and revived by cleric abilities.
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ServerStorage = game:GetService("ServerStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ContentProvider = game:GetService("ContentProvider")

local ALLY_FOLDER_NAME = "Allies"
local ALLY_HP = 250

local AllyManager = {}

local alliesFolder: Folder?
local setDownedPose: (Model, boolean) -> ()

local function getAllyFolder(): Folder
	if alliesFolder and alliesFolder.Parent then return alliesFolder end
	local f = Workspace:FindFirstChild(ALLY_FOLDER_NAME)
	if not f then
		f = Instance.new("Folder")
		f.Name = ALLY_FOLDER_NAME
		f.Parent = Workspace
	end
	alliesFolder = f
	return f
end

-- Returns every live ally model (tagged with the IsAlly attribute).
function AllyManager.GetAllies(): { Model }
	local list = {}
	for _, c in ipairs(getAllyFolder():GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("IsAlly") == true then
			table.insert(list, c)
		end
	end
	return list
end

function AllyManager.GetAllyByName(name: string): Model?
	local a = getAllyFolder():FindFirstChild(name)
	if a and a:IsA("Model") and a:GetAttribute("IsAlly") == true then
		return a
	end
	return nil
end

-- Bring an ally back from "downed" (Health 0) to full health.
function AllyManager.Revive(ally: Model): boolean
	if not ally or not ally.Parent then return false end
	local hum = ally:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	-- Dead state stays disabled so this actually sticks (see watchAlly).
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum.Health = hum.MaxHealth
	setDownedPose(ally, false)
	local _hrp = ally:FindFirstChild("HumanoidRootPart")
	if _hrp then _hrp.Anchored = false end
	return true
end

function AllyManager.HealAlly(ally: Model, amount: number): boolean
	if not ally then return false end
	local hum = ally:FindFirstChildOfClass("Humanoid")
	if not hum then return false end
	if hum.Health <= 0 then
		return AllyManager.Revive(ally)
	end
	hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
	return true
end

-- Heal (and revive if downed) every ally within radius of a world position.
function AllyManager.HealAlliesInRadius(origin: Vector3, radius: number, amount: number): number
	local n = 0
	for _, ally in ipairs(AllyManager.GetAllies()) do
		local root = ally:FindFirstChild("HumanoidRootPart")
		local hum = ally:FindFirstChildOfClass("Humanoid")
		if root and hum then
			if (root.Position - origin).Magnitude <= radius then
				if hum.Health <= 0 then
					AllyManager.Revive(ally)
				else
					hum.Health = math.min(hum.MaxHealth, hum.Health + amount)
				end
				n += 1
			end
		end
	end
	return n
end

function AllyManager.GetNearestAlly(origin: Vector3, radius: number): Model?
	local best, bestDist = nil, radius
	for _, ally in ipairs(AllyManager.GetAllies()) do
		local root = ally:FindFirstChild("HumanoidRootPart")
		if root then
			local d = (root.Position - origin).Magnitude
			if d <= bestDist then
				best, bestDist = ally, d
			end
		end
	end
	return best
end

-- Looped "revived" reach pose for the allies (animation authored by the user).
local REVIVE_POSE_ID = "rbxassetid://100018297459066"
local reviveAnimation = Instance.new("Animation")
reviveAnimation.Name = "DivineAscentRevivePose"
reviveAnimation.AnimationId = REVIVE_POSE_ID
pcall(function()
	ContentProvider:PreloadAsync({ reviveAnimation })
end)
local reviveTracks = {}

local function playRevivePose(ally: Model)
	local hum = ally:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	local track = reviveTracks[ally]
	if not track then
		local ok, t = pcall(function()
			return animator:LoadAnimation(reviveAnimation)
		end)
		if not ok or not t then return end
		track = t
		track.Looped = true
		track.Priority = Enum.AnimationPriority.Action
		reviveTracks[ally] = track
	end
	if not track.IsPlaying then
		track:Play(0, 1, 1)
		track.TimePosition = 0
	end
end

local function stopRevivePose(ally: Model)
	local track = reviveTracks[ally]
	if track then
		pcall(function()
			track:Stop(0.15)
		end)
	end
end

setDownedPose = function(ally: Model, downed: boolean)
	local hum = ally:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	ally:SetAttribute("Downed", downed)
	if downed then
		-- Limbs go limp so they read as collapsed / dead (Dead state stays disabled
		-- so they remain revivable).
		hum.PlatformStand = true
		hum:ChangeState(Enum.HumanoidStateType.Physics)
		stopRevivePose(ally)
	else
		hum.PlatformStand = false
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
		playRevivePose(ally)
	end
end

local function watchAlly(ally: Model)
	local hum = ally:FindFirstChildOfClass("Humanoid")
	if not hum then return end
	-- Keep allies in a revivable "downed" state: with the Dead state disabled, Health=0
	-- collapses them instead of latching them permanently dead.
	hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	hum.HealthChanged:Connect(function(hp)
		if ally.Parent then
			setDownedPose(ally, hp <= 0)
		end
	end)
end

-- Vertical "ray of light" beam VFX at a spawn position.
function AllyManager.spawnLightRays(position: Vector3)
	local holder = Instance.new("Folder")
	holder.Name = "AllyLightRays"
	holder.Parent = Workspace.Terrain

	local beam = Instance.new("Part")
	beam.Name = "Ray"
	beam.Shape = Enum.PartType.Cylinder
	beam.Size = Vector3.new(60, 2.6, 2.6)
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 240, 190)
	beam.Transparency = 0.32
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanTouch = false
	beam.CanQuery = false
	beam.CastShadow = false
	beam.CFrame = CFrame.new(position + Vector3.new(0, 30, 0)) * CFrame.Angles(0, 0, math.rad(90))
	beam.Parent = holder

	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 240, 190)
	light.Brightness = 4
	light.Range = 26
	light.Shadows = false
	light.Parent = beam

	task.delay(1.1, function()
		if not holder.Parent then return end
		TweenService:Create(beam, TweenInfo.new(0.8), { Transparency = 1 }):Play()
		TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
		Debris:AddItem(holder, 0.9)
	end)
end

local function spawnAlly(template: Model, name: string, cframe: CFrame, downed: boolean?)
	local ally = template:Clone()
	ally.Name = name
	ally:SetAttribute("IsAlly", true)
	ally:SetAttribute("Downed", false)
	if not ally.PrimaryPart then
		ally.PrimaryPart = ally:FindFirstChild("HumanoidRootPart")
	end
	local hum = ally:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.MaxHealth = ALLY_HP
		hum.Health = ALLY_HP
		hum.BreakJointsOnDeath = false
		hum.WalkSpeed = 0
		hum.JumpPower = 0
		hum:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
	end
	ally.Parent = getAllyFolder()
	ally:PivotTo(cframe)
	watchAlly(ally)
	if downed and hum then
		setDownedPose(ally, true)
		hum.Health = 0
	end
	return ally
end

-- Clears any previously-spawned test allies.
local function clearAllies()
	local folder = getAllyFolder()
	for _, c in ipairs(folder:GetChildren()) do
		if c:IsA("Model") and c:GetAttribute("IsAlly") == true then
			c:Destroy()
		end
	end
end

-- Spawn the 3 allies BEHIND the given player, already downed, with light rays.
local function poseReaching(ally: Model)
	-- Hold the revived reach pose (animation 100018297459066) and anchor the rig.
	playRevivePose(ally)
	local hrp = ally:FindFirstChild("HumanoidRootPart")
	if hrp then hrp.Anchored = true end
end

function AllyManager.SpawnAlliesBehindPlayer(player: Player, returnCFrame: CFrame?)
	local template = ServerStorage:FindFirstChild("AllyTemplate")
	if not template then
		warn("[AllyManager] No ServerStorage.AllyTemplate - cannot spawn allies.")
		return
	end
	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	clearAllies()

	-- The caster was lifted to +53 studs; the revived party floats 50 studs up
	-- (3 below him), fanned out IN FRONT of him so he faces them and they all
	-- face back toward him.
	local baseCF = returnCFrame or root.CFrame
	local casterPos = root.Position
	local look = baseCF.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude < 0.001 then flat = Vector3.new(0, 0, -1) end
	flat = flat.Unit
	local right = Vector3.new(-flat.Z, 0, flat.X)
	local allyY = casterPos.Y + 6
	local returnOffsets = { Vector3.new(-7, 0, 8), Vector3.new(0, 0, 11), Vector3.new(7, 0, 8) }
	local fanCenter = Vector3.new(casterPos.X, allyY, casterPos.Z) + flat * 10
	local lateral = { -7, 0, 7 }
	local cen = Vector3.zero
	for i, lat in ipairs(lateral) do
		local pos = fanCenter + right * lat
		pos = Vector3.new(pos.X, allyY, pos.Z)
		local tgt = Vector3.new(casterPos.X, allyY, casterPos.Z)
		local ally = spawnAlly(template, "Ally" .. i, CFrame.lookAt(pos, tgt), true)
		poseReaching(ally)

		local localOffset = returnOffsets[i]
		local groundPos = (baseCF * CFrame.new(localOffset)).Position
		local rayParams = RaycastParams.new()
		rayParams.FilterType = Enum.RaycastFilterType.Exclude
		rayParams.FilterDescendantsInstances = { getAllyFolder(), player.Character }
		rayParams.IgnoreWater = true
		local hit = Workspace:Raycast(groundPos + Vector3.new(0, 8, 0), Vector3.new(0, -300, 0), rayParams)
		local returnY = groundPos.Y
		local hum = ally:FindFirstChildOfClass("Humanoid")
		local hrp = ally:FindFirstChild("HumanoidRootPart")
		if hit and hrp and hrp:IsA("BasePart") then
			local hipHeight = hum and hum.HipHeight or 2
			returnY = hit.Position.Y + (hrp.Size.Y * 0.5) + hipHeight
		end
		ally:SetAttribute("ReturnCFrame", CFrame.new(groundPos.X, returnY, groundPos.Z) * baseCF.Rotation)
		cen = cen + pos
	end

	-- Revive the party a beat later; they stay floating + anchored in the reach pose
	-- (the ground aura can't reach them at +50, so revive them directly here).
	task.delay(0.4, function()
		for _, ally in ipairs(AllyManager.GetAllies()) do
			AllyManager.Revive(ally)
			local hrp = ally:FindFirstChild("HumanoidRootPart")
			if hrp then hrp.Anchored = true end
		end
	end)

	cen = cen / #lateral
	Workspace:SetAttribute("ReviveStageCenter", cen)
	local vd = Vector3.new(flat.X, 0, flat.Z)
	if vd.Magnitude < 0.001 then vd = Vector3.new(0, 0, 1) end
	Workspace:SetAttribute("ReviveStageView", vd.Unit)

	print("[AllyManager] Spawned " .. #lateral .. " downed allies in front of " .. player.Name)
end

-- Drop the floating party back to the ground when the ult ends.
function AllyManager.ReleaseAllies()
	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = {getAllyFolder()}
	rayParams.IgnoreWater = true

	for _, ally in ipairs(AllyManager.GetAllies()) do
		local hrp = ally:FindFirstChild("HumanoidRootPart")
		if hrp then
			local returnCF = ally:GetAttribute("ReturnCFrame")
			if typeof(returnCF) == "CFrame" then
				hrp.CFrame = returnCF
			else
				local rayOrigin = hrp.Position + Vector3.new(0, 8, 0)
				local hit = Workspace:Raycast(rayOrigin, Vector3.new(0, -300, 0), rayParams)
				if hit then
					local hum = ally:FindFirstChildOfClass("Humanoid")
					local hipHeight = hum and hum.HipHeight or 2
					local y = hit.Position.Y + (hrp.Size.Y * 0.5) + hipHeight
					hrp.CFrame = CFrame.new(hrp.Position.X, y, hrp.Position.Z) * (hrp.CFrame - hrp.Position)
				end
			end
			hrp.AssemblyLinearVelocity = Vector3.zero
			hrp.AssemblyAngularVelocity = Vector3.zero
			hrp.Anchored = false
		end
		stopRevivePose(ally)
	end
end

function AllyManager.Init()
	getAllyFolder()
	print("[AllyManager] initialized.")
end

return AllyManager
