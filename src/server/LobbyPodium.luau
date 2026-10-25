--!strict
--[[
	LobbyPodium.luau
	The guild podium in the lobby (LobbyBuilder's GuildPodium): stands the
	season's top 3 guilds' top contributors (GuildManager.Top3) on its tiers,
	as their own avatars (R6), still, facing the plaza, a nameplate over each
	(rank, guild [TAG], name, the guild's points). Their class shows on every
	client (PodiumClass: LobbyHUD dresses them with ClassLook). An empty tier
	shows "Unclaimed". Re-stood whenever the ranking moves.

	LobbyPodium.Init(lobbyModel)
--]]

local Players = game:GetService("Players")

local GuildManager = require(script.Parent:WaitForChild("GuildManager"))

local LobbyPodium = {}

local MEDAL = { Color3.fromRGB(255, 210, 90), Color3.fromRGB(215, 220, 230), Color3.fromRGB(215, 140, 80) }
local FONT = Enum.Font.Antique

local podium: Model? = nil
local token = 0

local function plate(adornee: BasePart, rank: number, lines: { string }, height: number): BillboardGui
	local bb = Instance.new("BillboardGui")
	bb.Name = "PodiumPlate"
	bb.Size = UDim2.new(11, 0, 3.8, 0) -- (studs: shrinks with distance)
	bb.StudsOffsetWorldSpace = Vector3.new(0, height, 0)
	bb.LightInfluence = 0
	bb.MaxDistance = 140
	bb.Adornee = adornee
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.Parent = bb
	for i, text in ipairs(lines) do
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Size = UDim2.fromScale(1, if i == 1 then 0.38 else 0.31)
		t.Font = FONT
		t.TextScaled = true
		t.TextColor3 = if i == 1 then MEDAL[rank] else Color3.fromRGB(245, 235, 210)
		t.TextStrokeTransparency = 0.3
		t.Text = text
		t.Parent = bb
	end
	bb.Parent = adornee
	return bb
end

local function clear()
	local p = podium
	if not p then return end
	for _, d in ipairs(p:GetChildren()) do
		if d.Name == "PodiumFigure" then d:Destroy() end
	end
	for _, d in ipairs(p:GetDescendants()) do
		if d:IsA("BillboardGui") and d.Name == "PodiumPlate" then d:Destroy() end
	end
end

local function figure(entry: any, spot: BasePart, my: number)
	local top = entry.top
	if not top or not top.userId then return end
	local ok, desc = pcall(function() return Players:GetHumanoidDescriptionFromUserId(top.userId) end)
	if not ok or not desc or my ~= token then return end
	local ok2, model = pcall(function() return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R6) end)
	if not ok2 or not model or my ~= token then return end
	model.Name = "PodiumFigure"
	local hum = model:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.PlatformStand = true
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.CanCollide = false
			d.CanQuery = false
			d.CanTouch = false
		elseif d:IsA("Script") or d:IsA("LocalScript") then
			d:Destroy()
		end
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then root.Anchored = true end
	model:SetAttribute("PodiumClass", top.class)
	model:SetAttribute("Rank", entry.rank)
	-- (standing on the tier, facing the plaza)
	model:PivotTo(spot.CFrame * CFrame.new(0, 3, 0))
	model.Parent = podium
end

local function stand(list: { any })
	token += 1
	local my = token
	clear()
	local p = podium
	if not p then return end
	for rank = 1, 3 do
		local spot = p:FindFirstChild(`Spot{rank}`) :: BasePart?
		if not spot then continue end
		local entry = list[rank]
		if entry then
			plate(spot, rank, { `#{rank}  {entry.name} [{entry.tag}]`, if entry.top then entry.top.name else "", `{entry.points} pts` }, 8.4)
			task.spawn(figure, entry, spot, my)
		else
			plate(spot, rank, { `#{rank}`, "Unclaimed", "" }, 3)
		end
	end
end

function LobbyPodium.Init(lobby: Model)
	podium = lobby:FindFirstChild("GuildPodium", true) :: Model?
	if not podium then
		warn("[LobbyPodium] no GuildPodium in the lobby")
		return
	end
	stand(GuildManager.Top3())
	GuildManager.Changed:Connect(stand)
end

return LobbyPodium
