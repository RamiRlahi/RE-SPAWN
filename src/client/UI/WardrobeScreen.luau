--[[
	WardrobeScreen.luau
	The Wardrobe: "ARMOR SELECTION" / "WINGS SELECTION" / "MOUNTS SELECTION"
	(tabs along the top). Every class's outfit, every pair of wings or every
	mount on its own pedestal, a page of six at a time (arrows for the rest,
	so it never crowds the screen). Owned ones stand in a beam of their
	rarity's colour and move (outfits turn, wings flap, mounts walk in place);
	ones you don't own yet are dark silhouettes. Click an owned one to wear /
	ride it (an outfit: on its class; click it again to take it off).

	Same look as the buff / relic screens (ChoiceScreen.Style).

	WardrobeScreen.Open(kind, state, act)   kind = "armor" | "wings" | "mount"
	  state: the GachaState (collection.cosmetics, equipped)
	  act(payload): sends a GachaAction
	WardrobeScreen.OpenLobby(kind?)         from the lobby's WARDROBE button:
	  fetches the GachaState itself
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local ChoiceScreen = require(script.Parent.Parent:WaitForChild("ChoiceScreen"))
local BrickModels = require(script.Parent.Parent:WaitForChild("BrickModels"))
local WingsMounts = require(script.Parent.Parent:WaitForChild("WingsMounts"))
local RewardPreview = require(script.Parent.Parent:WaitForChild("RewardPreview"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local Network = require(Shared:WaitForChild("Network"))

local player = Players.LocalPlayer
local S = ChoiceScreen.Style
local new, text, diamond, ornament, glow = S.new, S.text, S.diamond, S.ornament, S.glow
local W, H = S.W, S.H

local WardrobeScreen = {}

local PER_PAGE = 6
local CARD_W, GAP = 220, 26
local DARK = Color3.fromRGB(22, 20, 30)

local gui: ScreenGui? = nil
type Shown = { rig: any, cam: Camera, owned: boolean }

local function rarityColor(r: string): Color3
	return GachaConfig.Rarities[r] and GachaConfig.Rarities[r].color or S.GOLD
end

-- Everything of a kind, in rarity order (outfits: in class order).
local function itemsOf(kind: string): { any }
	local list = {}
	for _, r in ipairs(GachaRewards.All) do
		if r.type == kind then table.insert(list, r) end
	end
	if kind == "armor" then
		table.sort(list, function(a, b)
			return (table.find(ClassData.Order, a.classId) or 99) < (table.find(ClassData.Order, b.classId) or 99)
		end)
		return list
	end
	table.sort(list, function(a, b)
		local ia = table.find(GachaConfig.RarityOrder, a.rarity) or 0
		local ib = table.find(GachaConfig.RarityOrder, b.rarity) or 0
		if ia ~= ib then return ia < ib end
		return a.name < b.name
	end)
	return list
end

-- A rig you don't own yet: a dark silhouette, no particles.
local function silhouette(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Color = DARK
			d.Material = Enum.Material.SmoothPlastic
		elseif d:IsA("ParticleEmitter") then
			d.Enabled = false
		end
	end
end

function WardrobeScreen.Open(kind: string, state: any, act: (any) -> ())
	if gui then gui:Destroy() end
	local sg = Instance.new("ScreenGui")
	sg.Name = "WardrobeScreen"
	sg.IgnoreGuiInset = true
	sg.ResetOnSpawn = false
	sg.DisplayOrder = 60
	sg.Parent = player:WaitForChild("PlayerGui")
	gui = sg

	local root = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(6, 5, 14), BackgroundTransparency = 0.08, ZIndex = 40 }, sg)
	new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(40, 30, 80), Color3.fromRGB(6, 5, 14)), Rotation = 90 }, root)
	local stage = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 1, ZIndex = 40 }, root)
	local scale = new("UIScale", {}, stage)
	local function fit()
		local cam = Workspace.CurrentCamera
		local v = if cam then cam.ViewportSize else Vector2.new(W, H)
		scale.Scale = math.min(v.X / W, v.Y / H)
	end
	fit()

	local isWings = kind == "wings"
	local isArmor = kind == "armor"
	ornament(stage, 58, 640)
	local title = text(stage, if isArmor then "ARMOR SELECTION" elseif isWings then "WINGS SELECTION" else "MOUNTS SELECTION", 76, S.GOLD,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, 70), Size = UDim2.fromOffset(1100, 84) })
	new("UIGradient", { Color = ColorSequence.new(S.GOLD_L, S.GOLD), Rotation = 90 }, title)
	ornament(stage, 166, 600)
	text(stage, if isArmor then "DRESS EACH CLASS" elseif isWings then "CHOOSE YOUR WINGS" else "CHOOSE YOUR MOUNT", 28, S.GOLD_L,
		{ AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, 184), Size = UDim2.fromOffset(700, 32) })
	local note = text(stage, if isArmor then "Each class wears its own outfit (found in summons). Without it: your own avatar."
		elseif isWings then "Worn everywhere." else "Press B to ride: faster than running. A hit throws you off.", 20,
		Color3.fromRGB(200, 200, 220), { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(W / 2, 222), Size = UDim2.fromOffset(900, 24) })
	note.TextTransparency = 0.2
	-- the tabs: the Wardrobe's three sections
	for i, tab in ipairs({ { "armor", "ARMOR" }, { "wings", "WINGS" }, { "mount", "MOUNTS" } }) do
		local on = tab[1] == kind
		local b = new("TextButton", { Position = UDim2.fromOffset(40 + (i - 1) * 150, 40), Size = UDim2.fromOffset(140, 46),
			BackgroundColor3 = if on then Color3.fromRGB(70, 56, 30) else S.PANEL, BackgroundTransparency = 0.1, Text = "", ZIndex = 44 }, stage)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		new("UIStroke", { Color = if on then S.GOLD_L else S.GOLD, Thickness = if on then 3 else 1.5 }, b)
		text(b, tab[2], 22, if on then S.GOLD_L else Color3.fromRGB(220, 220, 235), { Size = UDim2.fromScale(1, 1), ZIndex = 45 })
		if not on then
			b.Activated:Connect(function() WardrobeScreen.Open(tab[1], state, act) end)
		end
	end

	local items = itemsOf(kind)
	local pages = math.max(1, math.ceil(#items / PER_PAGE))
	local page = 1
	local row = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = 41 }, stage)
	local pageLabel = text(stage, "", 22, Color3.fromRGB(210, 210, 230), { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W / 2, 806),
		Size = UDim2.fromOffset(300, 28) })

	local shown: { Shown } = {}
	local cleanups: { () -> () } = {} -- (the outfits' showcase models)
	local conn: RBXScriptConnection? = nil

	local function owned(id: string): boolean
		return (state.collection and state.collection.cosmetics or {})[id] == true
	end
	-- what's worn: the kind's one, or (outfits) that class's
	local function wornId(r: any): string?
		local eq = state.equipped or {}
		if isArmor then return (eq.armor or {})[r.classId] end
		return eq[kind]
	end

	local function build()
		for _, f in ipairs(cleanups) do pcall(f) end
		table.clear(cleanups)
		row:ClearAllChildren()
		table.clear(shown)
		local first = (page - 1) * PER_PAGE + 1
		local count = math.min(PER_PAGE, #items - first + 1)
		local total = count * CARD_W + (count - 1) * GAP
		for k = 0, count - 1 do
			local r = items[first + k]
			local mine = owned(r.id)
			local worn = wornId(r) == r.id
			local col = rarityColor(r.rarity)
			local bright = col:Lerp(Color3.new(1, 1, 1), 0.35)
			local x0 = W / 2 - total / 2 + k * (CARD_W + GAP)
			local card = new("TextButton", { Position = UDim2.fromOffset(x0, 262), Size = UDim2.fromOffset(CARD_W, 520), BackgroundTransparency = 1,
				Text = "", AutoButtonColor = false, ZIndex = 42 }, row)
			local sc = new("UIScale", {}, card)
			if mine then
				glow(card, UDim2.fromOffset(CARD_W / 2, 330), UDim2.fromOffset(CARD_W * 0.6, 320), col, 0.5)
			end
			-- the model on its pedestal
			local vp = new("ViewportFrame", { Size = UDim2.fromOffset(CARD_W, 340), BackgroundTransparency = 1,
				Ambient = Color3.fromRGB(150, 150, 170), LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-0.6, -1, -0.8), ZIndex = 43 }, card)
			local world = new("WorldModel", {}, vp)
			local cam = new("Camera", { FieldOfView = 32 }, vp)
			vp.CurrentCamera = cam
			local pedestal = BrickModels.Pedestal(if mine then col else Color3.fromRGB(70, 70, 80))
			pedestal:ScaleTo(0.45)
			pedestal:PivotTo(CFrame.new(0, -0.6, 0))
			pedestal.Parent = world
			local rig = if isArmor then nil else WingsMounts.Build(r.id, true)
			if isArmor then
				-- the outfit, turning slowly on the pedestal (RewardPreview)
				local ok, model, cleanup = pcall(RewardPreview.Build, r)
				if ok and model then
					model.Parent = world
					if not mine then silhouette(model) end
					local _, ext = model:GetBoundingBox()
					model:PivotTo(CFrame.new(0, ext.Y / 2 - 0.1, 0) * CFrame.Angles(0, math.pi, 0))
					local center = model:GetBoundingBox().Position
					local size = math.max(ext.X, ext.Y, ext.Z, 3)
					cam.CFrame = CFrame.lookAt(center + Vector3.new(0, size * 0.15, size * 1.35 + 2), center)
					table.insert(cleanups, cleanup)
				end
			end
			if rig then
				rig.world = world
				rig.model.Parent = world
				if not mine then silhouette(rig.model) end
				local up = if isWings then 2.2 else 0.4
				WingsMounts.Pose(rig, CFrame.new(0, up, 0) * CFrame.Angles(0, math.rad(if isWings then 180 else 145), 0), 0, 0.4)
				local _, ext = rig.model:GetBoundingBox()
				local size = math.max(ext.X, ext.Y, ext.Z, 3)
				local center = rig.model:GetBoundingBox().Position
				cam.CFrame = CFrame.lookAt(center + Vector3.new(0, size * 0.25, size * 1.9 + 2), center)
				table.insert(shown, { rig = rig, cam = cam, owned = mine })
			end
			-- the card
			local plate = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromOffset(CARD_W / 2, 350), Size = UDim2.fromOffset(CARD_W - 10, 150),
				BackgroundColor3 = S.PANEL, BackgroundTransparency = 0.08, ZIndex = 43 }, card)
			new("UICorner", { CornerRadius = UDim.new(0, 4) }, plate)
			local stroke = new("UIStroke", { Color = if mine then col else Color3.fromRGB(80, 80, 95), Thickness = if worn then 4 else 2,
				ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, plate)
			local nameL = text(plate, string.upper(r.name), 22, if mine then bright else Color3.fromRGB(150, 150, 165),
				{ Position = UDim2.fromOffset(8, 12), Size = UDim2.new(1, -16, 0, 26), TextScaled = true, ZIndex = 45 })
			new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }, nameL)
			local cls = isArmor and ClassData.GetClass(r.classId)
			text(plate, (if cls then string.upper(cls.name) .. "  ·  " else "") .. string.upper(r.rarity), 18, col,
				{ Position = UDim2.fromOffset(0, 46), Size = UDim2.new(1, 0, 0, 22), ZIndex = 45 })
			local status = if worn then (if kind == "mount" then "RIDING" else "WEARING") elseif mine then "EQUIP" else "NOT OWNED"
			local statusL = text(plate, status, 20, if worn then S.GOLD_L elseif mine then Color3.new(1, 1, 1) else Color3.fromRGB(120, 120, 135),
				{ Position = UDim2.fromOffset(0, 96), Size = UDim2.new(1, 0, 0, 24), ZIndex = 45 })
			if worn then
				diamond(plate, UDim2.new(0.5, -70, 0, 108), 10, S.GOLD_L)
				diamond(plate, UDim2.new(0.5, 70, 0, 108), 10, S.GOLD_L)
			end
			if mine then
				card.MouseEnter:Connect(function()
					TweenService:Create(sc, TweenInfo.new(0.15), { Scale = 1.05 }):Play()
					stroke.Color = bright
					statusL.Text = if worn then "TAKE OFF" elseif kind == "mount" then "RIDE" else "WEAR"
				end)
				card.MouseLeave:Connect(function()
					TweenService:Create(sc, TweenInfo.new(0.15), { Scale = 1 }):Play()
					stroke.Color = col
					statusL.Text = status
				end)
				card.Activated:Connect(function()
					state.equipped = state.equipped or {}
					if isArmor then
						act({ kind = "equipArmor", classId = r.classId, id = if worn then nil else r.id })
						state.equipped.armor = state.equipped.armor or {}
						state.equipped.armor[r.classId] = if worn then nil else r.id
					else
						act({ kind = if isWings then "equipWings" else "equipMount", id = if worn then nil else r.id })
						-- (shown at once; the server's sync confirms it)
						state.equipped[kind] = if worn then nil else r.id
					end
					build()
				end)
			end
		end
		pageLabel.Text = if pages > 1 then `{page} / {pages}` else ""
	end

	-- arrows and close
	local function arrow(str: string, x: number, step: number)
		local b = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(x, 500), Size = UDim2.fromOffset(64, 120),
			BackgroundColor3 = S.PANEL, BackgroundTransparency = 0.2, Text = "", ZIndex = 44 }, stage)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
		new("UIStroke", { Color = S.GOLD, Thickness = 2 }, b)
		text(b, str, 44, S.GOLD, { Size = UDim2.fromScale(1, 1), ZIndex = 45 })
		b.Visible = pages > 1
		b.Activated:Connect(function()
			page = (page - 1 + step) % pages + 1
			build()
		end)
	end
	arrow("<", 70, -1)
	arrow(">", W - 70, 1)
	local close = new("TextButton", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(W / 2, 852), Size = UDim2.fromOffset(240, 54),
		BackgroundColor3 = S.PANEL, Text = "", ZIndex = 44 }, stage)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, close)
	new("UIStroke", { Color = Color3.fromRGB(200, 200, 215), Thickness = 3 }, close)
	text(close, "BACK", 24, Color3.fromRGB(235, 235, 245), { Size = UDim2.fromScale(1, 1), ZIndex = 45 })
	close.Activated:Connect(function()
		if conn then conn:Disconnect() end
		for _, f in ipairs(cleanups) do pcall(f) end
		sg:Destroy()
		gui = nil
	end)

	build()
	-- Owned ones animate: wings flap, mounts walk in place on their pedestals.
	conn = RunService.RenderStepped:Connect(function()
		if not sg.Parent then
			if conn then conn:Disconnect() end
			for _, f in ipairs(cleanups) do pcall(f) end
			return
		end
		local t = os.clock()
		for _, s in ipairs(shown) do
			if s.owned then
				local up = if isWings then 2.2 else 0.4
				local yaw = if isWings then math.rad(180) + math.sin(t * 0.6) * 0.5 else math.rad(145) + math.sin(t * 0.4) * 0.35
				WingsMounts.Pose(s.rig, CFrame.new(0, up + math.sin(t * 1.5) * 0.08, 0) * CFrame.Angles(0, yaw, 0), t, if isWings then 0.5 else 0.7)
			end
		end
	end)
end

-- From the lobby (its WARDROBE button, like the ARMORY's): the collection
-- fetched first, kept up to date while it's open.
local lobbyState: any = nil
local listening = false
function WardrobeScreen.OpenLobby(kind: string?)
	local function act(payload: any)
		Network.GetRemoteEvent(Network.Remotes.GachaAction):FireServer(payload)
	end
	if not listening then
		listening = true
		Network.GetRemoteEvent(Network.Remotes.GachaState).OnClientEvent:Connect(function(payload)
			if typeof(payload) ~= "table" then return end
			if lobbyState then
				-- (in place: an open Wardrobe holds this table)
				for k in pairs(lobbyState) do lobbyState[k] = nil end
				for k, v in pairs(payload) do lobbyState[k] = v end
			else
				lobbyState = payload
			end
		end)
	end
	Network.GetRemoteEvent(Network.Remotes.RequestGacha):FireServer()
	task.spawn(function()
		local t0 = os.clock()
		while not lobbyState and os.clock() - t0 < 5 do task.wait(0.1) end
		WardrobeScreen.Open(kind or "armor", lobbyState or { collection = { cosmetics = {} }, equipped = {} }, act)
	end)
end

return WardrobeScreen
