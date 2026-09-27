local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local SkillData = require(Shared:WaitForChild("SkillData"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))
local CastPoses = require(script.Parent.Parent:WaitForChild("CastPoses"))
local UltPreviewFX = require(script.Parent.Parent:WaitForChild("UltPreviewFX"))
local LobbyCamera = require(script.Parent.Parent:WaitForChild("LobbyCamera"))
local TalentConstellation = require(script.Parent:WaitForChild("TalentConstellation"))
local ClassArmor = require(Shared:WaitForChild("ClassArmor"))
local IceCape = require(Shared:WaitForChild("IceCape"))
local WeaponGrip = require(Shared:WaitForChild("WeaponGrip"))

local player = Players.LocalPlayer

-- Preview weapons per class (matches WeaponManager's loadouts).
local PREVIEW_WEAPONS: { [string]: string } = {
	heavy_knight = "Greatsword",
	ranger = "Bow",
}

local KNIGHT_HAIR_COLOR = Color3.fromRGB(250, 205, 101)
local originalHairColors: { [BasePart]: Color3 } = {}

local function isHairPiece(part: BasePart): boolean
	if string.find(string.lower(part.Name), "hair", 1, true) then
		return true
	end

	local accessory = part:FindFirstAncestorWhichIsA("Accessory")
	if not accessory then
		return false
	end

	return string.find(string.lower(accessory.Name), "hair", 1, true) ~= nil
		or accessory:FindFirstChild("HairAttachment", true) ~= nil
end

local function tintKnightHair(character: Model?, classId: string)
	if not character then return end

	for _, desc in ipairs(character:GetDescendants()) do
		if desc:IsA("BasePart") and isHairPiece(desc) then
			if classId == "heavy_knight" then
				if originalHairColors[desc] == nil then
					originalHairColors[desc] = desc.Color
				end
				desc.Color = KNIGHT_HAIR_COLOR
			elseif originalHairColors[desc] then
				desc.Color = originalHairColors[desc]
				originalHairColors[desc] = nil
			end
		end
	end
end

local function findWeaponTemplate(name: string): Instance?
	local targetName = string.lower(name)
	print(`[DEBUG-ClientWeapon] Searching for weapon template: "{name}" in ReplicatedStorage...`)

	local exact = ReplicatedStorage:FindFirstChild(name)
		or ReplicatedStorage:FindFirstChild(name, true)
	if exact then
		print(`[DEBUG-ClientWeapon] Found exact match: {exact:GetFullName()} ({exact.ClassName})`)
		return exact
	end

	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if assets then
		local inAssets = assets:FindFirstChild(name) or assets:FindFirstChild(name, true)
		if inAssets then
			print(`[DEBUG-ClientWeapon] Found in Assets: {inAssets:GetFullName()} ({inAssets.ClassName})`)
			return inAssets
		end
	end

	for _, child in ipairs(ReplicatedStorage:GetDescendants()) do
		if string.lower(child.Name) == targetName then
			print(`[DEBUG-ClientWeapon] Found case-insensitive match: {child:GetFullName()} ({child.ClassName})`)
			return child
		end
	end
	for _, child in ipairs(ReplicatedStorage:GetDescendants()) do
		local lower = string.lower(child.Name)
		if (child:IsA("Tool") or child:IsA("Model") or child:IsA("BasePart")) and (string.find(lower, "greatsword") or string.find(lower, "great_sword") or string.find(lower, "sword")) then
			print(`[DEBUG-ClientWeapon] Found partial match: {child:GetFullName()} ({child.ClassName})`)
			return child
		end
	end

	warn(`[DEBUG-ClientWeapon] ❌ Weapon "{name}" NOT found in ReplicatedStorage! Listing top-level ReplicatedStorage children:`)
	for _, child in ipairs(ReplicatedStorage:GetChildren()) do
		warn(`   RS Child: "{child.Name}" ({child.ClassName})`)
	end
	return nil
end

-- Disable CanCollide and set Massless on every BasePart inside a tool.
local function disableCollision(root: Instance)
	if root:IsA("BasePart") then
		(root :: BasePart).CanCollide = false
		(root :: BasePart).Massless   = true
	end
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless   = true
		end
	end
end

-- Weld every BasePart in the tool (except Handle) TO the Handle.
local function weldLoosePartsToHandle(tool: Tool, handle: BasePart)
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") and part ~= handle then
			local alreadyWelded = false
			for _, w in ipairs(part:GetChildren()) do
				if w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("Motor6D") then
					alreadyWelded = true
					break
				end
			end
			if not alreadyWelded then
				for _, w in ipairs(handle:GetChildren()) do
					if (w:IsA("Weld") or w:IsA("WeldConstraint"))
						and ((w :: Weld).Part0 == part or (w :: Weld).Part1 == part) then
						alreadyWelded = true
						break
					end
				end
			end

			if not alreadyWelded then
				local wc      = Instance.new("WeldConstraint")
				wc.Part0      = handle
				wc.Part1      = part :: BasePart
				wc.Parent     = handle
			end
		end
	end
end

local currentAnimToken = 0
local currentPreviewTrack: AnimationTrack? = nil
local currentScreenContainer: CanvasGroup? = nil

-- Locked classes: the preview character becomes a black silhouette.
local SILHOUETTE = Color3.fromRGB(8, 8, 10)
local silhouetted: { [Instance]: { [string]: any } } = {}
local function setSilhouette(character: Model?, on: boolean)
	if on and character and next(silhouetted) == nil then
		for _, d in ipairs(character:GetDescendants()) do
			if d:IsA("BasePart") and d.Name ~= "HumanoidRootPart" and d.Transparency < 1 then
				local saved: { [string]: any } = { Color = d.Color, Material = d.Material }
				if d:IsA("MeshPart") then
					saved.TextureID = d.TextureID
					d.TextureID = ""
				end
				silhouetted[d] = saved
				d.Color = SILHOUETTE
				d.Material = Enum.Material.SmoothPlastic
			elseif d:IsA("Decal") or d:IsA("Texture") then
				silhouetted[d] = { Transparency = d.Transparency }
				d.Transparency = 1
			elseif d:IsA("SpecialMesh") and d.TextureId ~= "" then
				silhouetted[d] = { TextureId = d.TextureId }
				d.TextureId = ""
			elseif d:IsA("Shirt") then
				silhouetted[d] = { ShirtTemplate = d.ShirtTemplate }
				d.ShirtTemplate = ""
			elseif d:IsA("Pants") then
				silhouetted[d] = { PantsTemplate = d.PantsTemplate }
				d.PantsTemplate = ""
			elseif d:IsA("ShirtGraphic") then
				silhouetted[d] = { Graphic = d.Graphic }
				d.Graphic = ""
			elseif d:IsA("SurfaceAppearance") then
				silhouetted[d] = { Parent = d.Parent }
				d.Parent = nil
			end
		end
	elseif not on then
		for inst, props in pairs(silhouetted) do
			if inst.Parent or props.Parent then
				for k, v in pairs(props) do
					(inst :: any)[k] = v
				end
			end
		end
		table.clear(silhouetted)
	end
end

local function stopPreviewAnimation()
	UltPreviewFX.Stop()
	CastPoses.stop(player.Character)
	setSilhouette(player.Character, false)
	if player.Character then
		ClassArmor.Remove(player.Character, "PreviewArmor")
	end
	currentAnimToken += 1
	if currentPreviewTrack then
		currentPreviewTrack:Stop(0.2)
		currentPreviewTrack:Destroy()
		currentPreviewTrack = nil
	end
	local character = player.Character
	if character then
		for _, instance in ipairs(character:GetChildren()) do
			-- Never remove gameplay tools here. The real weapon is equipped on the
			-- server as the selection screen is fading away, so only clean previews.
			if instance:GetAttribute("PreviewWeapon") or instance.Name == "PreviewGreatsword" then
				instance:Destroy()
			end
		end
	end
	if player.Backpack then
		for _, instance in ipairs(player.Backpack:GetChildren()) do
			if instance:GetAttribute("PreviewWeapon") or instance.Name == "PreviewGreatsword" then
				instance:Destroy()
			end
		end
	end
end

local function playPreviewAnimation(character: Model, classId: string)
	currentAnimToken += 1
	local myToken = currentAnimToken
	if currentPreviewTrack then
		currentPreviewTrack:Stop(0.2)
		currentPreviewTrack:Destroy()
		currentPreviewTrack = nil
	end

	CastPoses.stop(character)
	if not ClassData.IsPlayable(classId) then return end
	-- Every class shows its ultimate pose; only the Heavy Knight's is an uploaded
	-- animation, the others are held procedural poses.
	if classId ~= "heavy_knight" and CastPoses.holdUltPreview(character, classId) then
		return
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end
	local animator = humanoid:FindFirstChildOfClass("Animator")
	if not animator then
		animator = Instance.new("Animator")
		animator.Parent = humanoid
	end

	local CLASS_PREVIEW_POSES: { [string]: string } = {
		heavy_knight = "rbxassetid://101434181844277",
	}

	local animId = CLASS_PREVIEW_POSES[classId]
	if not animId or animId == "" then
		local skills = SkillData.GetSkills(classId)
		local ultConfig = skills and skills[4]
		animId = ultConfig and ultConfig.animationId
	end
	if not animId or animId == "" then
		animId = "rbxassetid://101434181844277"
	end

	local anim = Instance.new("Animation")
	anim.Name = `PreviewAnim_{classId}`
	anim.AnimationId = animId

	local track = animator:LoadAnimation(anim)
	track.Priority = Enum.AnimationPriority.Action4
	track.Looped = false
	track:Play(0.2)
	currentPreviewTrack = track

	-- Freeze at the last keyframe of the animation so the pose is held indefinitely
	task.spawn(function()
		local waitStart = os.clock()
		while track.Length == 0 and os.clock() - waitStart < 3.0 do
			task.wait()
			if currentAnimToken ~= myToken or not track.IsPlaying then return end
		end

		local length = track.Length
		if length > 0 then
			local holdTime = math.max(0.01, length - 0.06)
			local elapsed = os.clock() - waitStart
			local remaining = holdTime - elapsed
			if remaining > 0 then
				task.wait(remaining)
			end
			if currentAnimToken == myToken and track.IsPlaying then
				track:AdjustSpeed(0)
				track.TimePosition = holdTime
			end
		end
	end)
end

local function applyClassCosmetics(classId: string)
	task.spawn(function()
		-- Only apply cosmetic pose/weapon if the character selection screen is actively visible
		if currentScreenContainer and not currentScreenContainer.Visible then
			return
		end

		local character = player.Character
		if not character or not character.Parent then
			character = player.CharacterAdded:Wait()
		end
		if not character then
			warn("[DEBUG-ClientCosmetics] No player.Character found when applying cosmetics!")
			return
		end

		if currentScreenContainer and not currentScreenContainer.Visible then
			return
		end

		local rootPart = character:WaitForChild("HumanoidRootPart", 5)
		if not rootPart then
			warn("[DEBUG-ClientCosmetics] No HumanoidRootPart found on character!")
			return
		end

		print(`[DEBUG-ClientCosmetics] Applying cosmetics & ultimate pose for classId: "{classId}" on {character.Name}`)

		local humanoid = character:FindFirstChildOfClass("Humanoid")

		-- Remove all previously applied preview armor and preview weapons
		for _, instance in ipairs(character:GetChildren()) do
			if instance:GetAttribute("PreviewArmor") or instance:GetAttribute("PreviewWeapon") or instance.Name == "PreviewGreatsword" then
				instance:Destroy()
			end
		end
		for _, instance in ipairs(player.Backpack:GetChildren()) do
			if instance:GetAttribute("PreviewArmor") or instance:GetAttribute("PreviewWeapon") or instance.Name == "PreviewGreatsword" then
				instance:Destroy()
			end
		end
		for _, limbName in ipairs({ "Right Arm", "RightHand", "Left Arm", "LeftHand" }) do
			local limb = character:FindFirstChild(limbName)
			if limb then
				for _, w in ipairs(limb:GetChildren()) do
					if w.Name == "RightGrip" or w.Name == "LeftGrip" or w.Name == "PreviewGrip" or w:GetAttribute("PreviewArmor") or w:GetAttribute("PreviewWeapon") then
						w:Destroy()
					end
				end
			end
		end

		-- 1. Preview the class weapon via Humanoid:EquipTool (matching gameplay)
		local weaponName = PREVIEW_WEAPONS[classId]
		if weaponName and humanoid and ClassData.IsPlayable(classId) then
			local swordTemplate = findWeaponTemplate(weaponName)

			if swordTemplate then
				local tool = swordTemplate:Clone()
				if not tool:IsA("Tool") then
					local inner = tool:FindFirstChildWhichIsA("Tool")
					if inner then
						tool = inner
					end
				end

				tool.Name = if classId == "heavy_knight" then "PreviewGreatsword" else `Preview{weaponName}`
				tool:SetAttribute("PreviewWeapon", true)

				disableCollision(tool)

				local handle = tool:FindFirstChild("Handle") :: BasePart? or tool:FindFirstChildWhichIsA("BasePart")
				if handle and tool:IsA("Tool") then
					weldLoosePartsToHandle(tool, handle)
				end

				tool.Parent = player.Backpack
				humanoid:EquipTool(tool)
				if classId == "ranger" then
					WeaponGrip.ToLeftHand(character, tool) -- bow in the left hand, as in-game
				end

				print(`[DEBUG-ClientCosmetics] Preview equipped Tool '{tool.Name}' via Humanoid:EquipTool directly on {character.Name}`)
			end
		end

		-- 2. Play the ultimate's first pose / animation for this class, with a
		-- looping preview of the ultimate's effects around the character.
		playPreviewAnimation(character, classId)
		if ClassData.IsPlayable(classId) then
			UltPreviewFX.Start(character, classId)
		else
			UltPreviewFX.Stop()
		end

		-- 3. Armor (and the Ice Mage's cape), fitted exactly as in-game but as
		-- client-only copies tagged PreviewArmor.
		if not ClassData.IsPlayable(classId) then return end
		if currentScreenContainer and not currentScreenContainer.Visible then return end
		ClassArmor.Remove(character, "PreviewArmor")
		ClassArmor.Equip(character, classId, "PreviewArmor")
		if classId == "ice_mage" then
			IceCape.Attach(character, "PreviewArmor")
		end
	end)
end

export type ClassSelectionCallbacks = {
	onBackToTitle: () -> (),
	onConfirmClass: (classId: string) -> (),
}

local ClassSelectionScreen = {}

function ClassSelectionScreen.Create(parent: GuiObject, callbacks: ClassSelectionCallbacks): CanvasGroup
	local container = Instance.new("CanvasGroup")
	container.Name = "ClassSelectionScreen"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 1
	container.Visible = false
	container.Parent = parent
	currentScreenContainer = container

	-- Subtle Dark Vignette Border (Keep center open to see the 3D character clearly)
	local vignette = Instance.new("Frame")
	vignette.Name = "Vignette"
	vignette.Size = UDim2.new(1, 0, 1, 0)
	vignette.BackgroundColor3 = UITheme.Colors.BackgroundOverlay
	vignette.BackgroundTransparency = 0.5
	vignette.BorderSizePixel = 0
	vignette.Parent = container

	local vignetteGrad = Instance.new("UIGradient")
	vignetteGrad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(0.3, 0.75),
		NumberSequenceKeypoint.new(0.7, 0.75),
		NumberSequenceKeypoint.new(1, 0.2),
	})
	vignetteGrad.Rotation = 0
	vignetteGrad.Parent = vignette

	-- Top Header Bar
	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.Size = UDim2.new(1, 0, 0, 70)
	topBar.BackgroundTransparency = 1
	topBar.Parent = container

	local backBtn = Instance.new("TextButton")
	backBtn.Name = "BackButton"
	backBtn.Size = UDim2.new(0, 140, 0, 38)
	backBtn.Position = UDim2.new(0, 24, 0.5, -19)
	backBtn.BackgroundColor3 = UITheme.Colors.Surface
	backBtn.AutoButtonColor = false
	backBtn.Text = "← TITLE"
	backBtn.TextColor3 = UITheme.Colors.TextSecondary
	backBtn.Font = UITheme.Fonts.Button
	backBtn.TextSize = 13
	backBtn.Parent = topBar

	UITheme.AddCorner(backBtn, 6)
	local backStroke = UITheme.AddStroke(backBtn, UITheme.Colors.Border, 1, 0.5)
	UITheme.MakeButtonInteractive(backBtn, backStroke, UITheme.Colors.Gold, SoundManager.PlayHover, function()
		SoundManager.PlayClick()
		callbacks.onBackToTitle()
	end)

	local headerTitle = Instance.new("TextLabel")
	headerTitle.Name = "HeaderTitle"
	headerTitle.Size = UDim2.new(0, 450, 0, 30)
	headerTitle.AnchorPoint = Vector2.new(0.5, 0)
	headerTitle.Position = UDim2.new(0.5, 0, 0, 12)
	headerTitle.BackgroundTransparency = 1
	headerTitle.Text = "CHOOSE YOUR CLASS"
	headerTitle.TextColor3 = UITheme.Colors.GoldLight
	headerTitle.Font = UITheme.Fonts.Header
	headerTitle.TextSize = 22
	headerTitle.Parent = topBar

	local headerCounter = Instance.new("TextLabel")
	headerCounter.Name = "HeaderCounter"
	headerCounter.Size = UDim2.new(0, 450, 0, 20)
	headerCounter.AnchorPoint = Vector2.new(0.5, 0)
	headerCounter.Position = UDim2.new(0.5, 0, 0, 42)
	headerCounter.BackgroundTransparency = 1
	headerCounter.Text = "CLASS 1 OF 8"
	headerCounter.TextColor3 = UITheme.Colors.TextMuted
	headerCounter.Font = UITheme.Fonts.Tag
	headerCounter.TextSize = 11
	headerCounter.Parent = topBar

	---------------------------------------------------------------------
	-- Left Panel: Identity, Lore & Animated Stats
	---------------------------------------------------------------------
	local leftPanel = Instance.new("Frame")
	leftPanel.Name = "LeftPanel"
	leftPanel.Size = UDim2.new(0, 320, 1, -170)
	leftPanel.Position = UDim2.new(0, 24, 0, 75)
	leftPanel.BackgroundColor3 = UITheme.Colors.Surface
	leftPanel.BackgroundTransparency = 0.15
	leftPanel.Parent = container

	UITheme.AddCorner(leftPanel, 10)
	local leftStroke = UITheme.AddStroke(leftPanel, UITheme.Colors.Border, 1.5, 0.4)
	-- The info pane is replaced by the class's talent constellation. It's kept
	-- (hidden) because the carousel still writes class details into it.
	leftPanel.Visible = false
	local constellation = TalentConstellation.Create(container)

	local leftScroll = Instance.new("ScrollingFrame")
	leftScroll.Name = "LeftScroll"
	leftScroll.Size = UDim2.new(1, -24, 1, -24)
	leftScroll.Position = UDim2.new(0, 12, 0, 12)
	leftScroll.BackgroundTransparency = 1
	leftScroll.ScrollBarThickness = 3
	leftScroll.ScrollBarImageColor3 = UITheme.Colors.Gold
	leftScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	leftScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	leftScroll.Parent = leftPanel

	local leftLayout = Instance.new("UIListLayout")
	leftLayout.FillDirection = Enum.FillDirection.Vertical
	leftLayout.SortOrder = Enum.SortOrder.LayoutOrder
	leftLayout.Padding = UDim.new(0, 12)
	leftLayout.Parent = leftScroll

	local classNameLabel = Instance.new("TextLabel")
	classNameLabel.Name = "ClassName"
	classNameLabel.Size = UDim2.new(1, 0, 0, 34)
	classNameLabel.BackgroundTransparency = 1
	classNameLabel.Font = UITheme.Fonts.Title
	classNameLabel.TextSize = 28
	classNameLabel.TextColor3 = UITheme.Colors.GoldLight
	classNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	classNameLabel.LayoutOrder = 1
	classNameLabel.Parent = leftScroll

	local titleRoleRow = Instance.new("Frame")
	titleRoleRow.Name = "TitleRoleRow"
	titleRoleRow.Size = UDim2.new(1, 0, 0, 24)
	titleRoleRow.BackgroundTransparency = 1
	titleRoleRow.LayoutOrder = 2
	titleRoleRow.Parent = leftScroll

	local subtitleLabel = Instance.new("TextLabel")
	subtitleLabel.Name = "Subtitle"
	subtitleLabel.Size = UDim2.new(0.6, 0, 1, 0)
	subtitleLabel.BackgroundTransparency = 1
	subtitleLabel.Font = UITheme.Fonts.Sub
	subtitleLabel.TextSize = 13
	subtitleLabel.TextColor3 = UITheme.Colors.TextSecondary
	subtitleLabel.TextXAlignment = Enum.TextXAlignment.Left
	subtitleLabel.Parent = titleRoleRow

	local roleBadge = Instance.new("TextLabel")
	roleBadge.Name = "RoleBadge"
	roleBadge.Size = UDim2.new(0.4, 0, 1, 0)
	roleBadge.AnchorPoint = Vector2.new(1, 0)
	roleBadge.Position = UDim2.new(1, 0, 0, 0)
	roleBadge.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	roleBadge.Font = UITheme.Fonts.Tag
	roleBadge.TextSize = 10
	roleBadge.TextColor3 = UITheme.Colors.GoldLight
	roleBadge.Parent = titleRoleRow
	UITheme.AddCorner(roleBadge, 4)

	local loreBox = Instance.new("Frame")
	loreBox.Name = "LoreBox"
	loreBox.Size = UDim2.new(1, 0, 0, 0)
	loreBox.AutomaticSize = Enum.AutomaticSize.Y
	loreBox.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	loreBox.BackgroundTransparency = 0.5
	loreBox.LayoutOrder = 3
	loreBox.Parent = leftScroll
	UITheme.AddCorner(loreBox, 6)
	UITheme.AddPadding(loreBox, 8, 8, 10, 10)

	local descLabel = Instance.new("TextLabel")
	descLabel.Name = "Description"
	descLabel.Size = UDim2.new(1, 0, 0, 0)
	descLabel.AutomaticSize = Enum.AutomaticSize.Y
	descLabel.BackgroundTransparency = 1
	descLabel.Font = UITheme.Fonts.Body
	descLabel.TextSize = 12
	descLabel.TextColor3 = UITheme.Colors.TextPrimary
	descLabel.TextWrapped = true
	descLabel.TextXAlignment = Enum.TextXAlignment.Left
	descLabel.Parent = loreBox

	-- Stats Header
	local statsHeader = Instance.new("TextLabel")
	statsHeader.Name = "StatsHeader"
	statsHeader.Size = UDim2.new(1, 0, 0, 20)
	statsHeader.BackgroundTransparency = 1
	statsHeader.Text = "ATTRIBUTES & RATINGS"
	statsHeader.TextColor3 = UITheme.Colors.GoldLight
	statsHeader.Font = UITheme.Fonts.Header
	statsHeader.TextSize = 13
	statsHeader.TextXAlignment = Enum.TextXAlignment.Left
	statsHeader.LayoutOrder = 4
	statsHeader.Parent = leftScroll

	-- Stats Box with animated pips
	local statsBox = Instance.new("Frame")
	statsBox.Name = "StatsBox"
	statsBox.Size = UDim2.new(1, 0, 0, 110)
	statsBox.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	statsBox.LayoutOrder = 5
	statsBox.Parent = leftScroll
	UITheme.AddCorner(statsBox, 6)
	UITheme.AddPadding(statsBox, 8, 8, 10, 10)

	local statsLayout = Instance.new("UIListLayout")
	statsLayout.FillDirection = Enum.FillDirection.Vertical
	statsLayout.SortOrder = Enum.SortOrder.LayoutOrder
	statsLayout.Padding = UDim.new(0, 6)
	statsLayout.Parent = statsBox

	local statBars: { [string]: { Frame } } = {}
	local statKeys = { "strength", "vitality", "defense", "agility" }

	for idx, key in ipairs(statKeys) do
		local statRow = Instance.new("Frame")
		statRow.Name = "Stat_" .. key
		statRow.Size = UDim2.new(1, 0, 0, 18)
		statRow.BackgroundTransparency = 1
		statRow.LayoutOrder = idx
		statRow.Parent = statsBox

		local sTitle = Instance.new("TextLabel")
		sTitle.Size = UDim2.new(0.35, 0, 1, 0)
		sTitle.BackgroundTransparency = 1
		sTitle.Text = key:upper()
		sTitle.TextColor3 = UITheme.Colors.TextSecondary
		sTitle.Font = UITheme.Fonts.Tag
		sTitle.TextSize = 10
		sTitle.TextXAlignment = Enum.TextXAlignment.Left
		sTitle.Parent = statRow

		local barRow = Instance.new("Frame")
		barRow.Size = UDim2.new(0.65, 0, 0, 8)
		barRow.AnchorPoint = Vector2.new(1, 0.5)
		barRow.Position = UDim2.new(1, 0, 0.5, 0)
		barRow.BackgroundTransparency = 1
		barRow.Parent = statRow

		local barLayout = Instance.new("UIListLayout")
		barLayout.FillDirection = Enum.FillDirection.Horizontal
		barLayout.Padding = UDim.new(0, 4)
		barLayout.Parent = barRow

		statBars[key] = {}
		for b = 1, 5 do
			local pip = Instance.new("Frame")
			pip.Name = "Pip_" .. b
			pip.Size = UDim2.new(0.2, -4, 1, 0)
			pip.BackgroundColor3 = UITheme.Colors.SurfaceSelected
			pip.BorderSizePixel = 0
			pip.Parent = barRow
			UITheme.AddCorner(pip, 2)
			table.insert(statBars[key], pip)
		end
	end

	---------------------------------------------------------------------
	-- Right Panel: Skills Showcase & Equipment Showcase
	---------------------------------------------------------------------
	local rightPanel = Instance.new("Frame")
	rightPanel.Name = "RightPanel"
	rightPanel.Size = UDim2.new(0, 360, 1, -170)
	rightPanel.AnchorPoint = Vector2.new(1, 0)
	rightPanel.Position = UDim2.new(1, -24, 0, 75)
	rightPanel.BackgroundColor3 = UITheme.Colors.Surface
	rightPanel.BackgroundTransparency = 0.15
	rightPanel.Parent = container

	UITheme.AddCorner(rightPanel, 10)
	local rightStroke = UITheme.AddStroke(rightPanel, UITheme.Colors.Border, 1.5, 0.4)

	local rightScroll = Instance.new("ScrollingFrame")
	rightScroll.Name = "RightScroll"
	rightScroll.Size = UDim2.new(1, -24, 1, -24)
	rightScroll.Position = UDim2.new(0, 12, 0, 12)
	rightScroll.BackgroundTransparency = 1
	rightScroll.ScrollBarThickness = 3
	rightScroll.ScrollBarImageColor3 = UITheme.Colors.Gold
	rightScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
	rightScroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
	rightScroll.Parent = rightPanel

	local rightLayout = Instance.new("UIListLayout")
	rightLayout.FillDirection = Enum.FillDirection.Vertical
	rightLayout.SortOrder = Enum.SortOrder.LayoutOrder
	rightLayout.Padding = UDim.new(0, 10)
	rightLayout.Parent = rightScroll

	-- 1. Skills Section Header
	local skillsHeader = Instance.new("TextLabel")
	skillsHeader.Name = "SkillsHeader"
	skillsHeader.Size = UDim2.new(1, 0, 0, 20)
	skillsHeader.BackgroundTransparency = 1
	skillsHeader.Text = "CLASS COMBAT SKILLS"
	skillsHeader.TextColor3 = UITheme.Colors.GoldLight
	skillsHeader.Font = UITheme.Fonts.Header
	skillsHeader.TextSize = 13
	skillsHeader.TextXAlignment = Enum.TextXAlignment.Left
	skillsHeader.LayoutOrder = 1
	skillsHeader.Parent = rightScroll

	local abilitiesContainer = Instance.new("Frame")
	abilitiesContainer.Name = "AbilitiesContainer"
	abilitiesContainer.Size = UDim2.new(1, 0, 0, 0)
	abilitiesContainer.AutomaticSize = Enum.AutomaticSize.Y
	abilitiesContainer.BackgroundTransparency = 1
	abilitiesContainer.LayoutOrder = 2
	abilitiesContainer.Parent = rightScroll

	local abilitiesListLayout = Instance.new("UIListLayout")
	abilitiesListLayout.FillDirection = Enum.FillDirection.Vertical
	abilitiesListLayout.Padding = UDim.new(0, 6)
	abilitiesListLayout.SortOrder = Enum.SortOrder.LayoutOrder
	abilitiesListLayout.Parent = abilitiesContainer

	-- 2. Equipment Section Header
	local eqHeader = Instance.new("TextLabel")
	eqHeader.Name = "EquipmentHeader"
	eqHeader.Size = UDim2.new(1, 0, 0, 20)
	eqHeader.BackgroundTransparency = 1
	eqHeader.Text = "SIGNATURE EQUIPMENT"
	eqHeader.TextColor3 = UITheme.Colors.GoldLight
	eqHeader.Font = UITheme.Fonts.Header
	eqHeader.TextSize = 13
	eqHeader.TextXAlignment = Enum.TextXAlignment.Left
	eqHeader.LayoutOrder = 3
	eqHeader.Parent = rightScroll

	-- Equipment Card Container
	local eqCard = Instance.new("Frame")
	eqCard.Name = "EquipmentCard"
	eqCard.Size = UDim2.new(1, 0, 0, 0)
	eqCard.AutomaticSize = Enum.AutomaticSize.Y
	eqCard.BackgroundColor3 = UITheme.Colors.SurfaceAlt
	eqCard.LayoutOrder = 4
	eqCard.Parent = rightScroll

	UITheme.AddCorner(eqCard, 8)
	local eqStroke = UITheme.AddStroke(eqCard, UITheme.Colors.Gold, 1.5, 0.4)
	UITheme.AddPadding(eqCard, 10, 10, 12, 12)

	local eqLayout = Instance.new("UIListLayout")
	eqLayout.FillDirection = Enum.FillDirection.Vertical
	eqLayout.SortOrder = Enum.SortOrder.LayoutOrder
	eqLayout.Padding = UDim.new(0, 6)
	eqLayout.Parent = eqCard

	local eqNameLabel = Instance.new("TextLabel")
	eqNameLabel.Name = "EqName"
	eqNameLabel.Size = UDim2.new(1, 0, 0, 20)
	eqNameLabel.BackgroundTransparency = 1
	eqNameLabel.Font = UITheme.Fonts.Header
	eqNameLabel.TextSize = 15
	eqNameLabel.TextColor3 = UITheme.Colors.GoldLight
	eqNameLabel.TextXAlignment = Enum.TextXAlignment.Left
	eqNameLabel.LayoutOrder = 1
	eqNameLabel.Parent = eqCard

	local eqMetaRow = Instance.new("Frame")
	eqMetaRow.Name = "EqMetaRow"
	eqMetaRow.Size = UDim2.new(1, 0, 0, 18)
	eqMetaRow.BackgroundTransparency = 1
	eqMetaRow.LayoutOrder = 2
	eqMetaRow.Parent = eqCard

	local eqRarityBadge = Instance.new("TextLabel")
	eqRarityBadge.Name = "EqRarity"
	eqRarityBadge.Size = UDim2.new(0, 140, 1, 0)
	eqRarityBadge.BackgroundColor3 = UITheme.Colors.Surface
	eqRarityBadge.Font = UITheme.Fonts.Tag
	eqRarityBadge.TextSize = 10
	eqRarityBadge.TextColor3 = UITheme.Colors.Gold
	eqRarityBadge.Parent = eqMetaRow
	UITheme.AddCorner(eqRarityBadge, 3)

	local eqSlotLabel = Instance.new("TextLabel")
	eqSlotLabel.Name = "EqSlot"
	eqSlotLabel.Size = UDim2.new(1, -150, 1, 0)
	eqSlotLabel.Position = UDim2.new(0, 148, 0, 0)
	eqSlotLabel.BackgroundTransparency = 1
	eqSlotLabel.Font = UITheme.Fonts.Sub
	eqSlotLabel.TextSize = 11
	eqSlotLabel.TextColor3 = UITheme.Colors.TextMuted
	eqSlotLabel.TextXAlignment = Enum.TextXAlignment.Left
	eqSlotLabel.Parent = eqMetaRow

	local eqDescLabel = Instance.new("TextLabel")
	eqDescLabel.Name = "EqDesc"
	eqDescLabel.Size = UDim2.new(1, 0, 0, 0)
	eqDescLabel.AutomaticSize = Enum.AutomaticSize.Y
	eqDescLabel.BackgroundTransparency = 1
	eqDescLabel.Font = UITheme.Fonts.Sub
	eqDescLabel.TextSize = 11
	eqDescLabel.TextColor3 = UITheme.Colors.TextSecondary
	eqDescLabel.TextWrapped = true
	eqDescLabel.TextXAlignment = Enum.TextXAlignment.Left
	eqDescLabel.LayoutOrder = 3
	eqDescLabel.Parent = eqCard

	-- Equipment Stats Container
	local eqStatsRow = Instance.new("Frame")
	eqStatsRow.Name = "EqStatsRow"
	eqStatsRow.Size = UDim2.new(1, 0, 0, 0)
	eqStatsRow.AutomaticSize = Enum.AutomaticSize.Y
	eqStatsRow.BackgroundTransparency = 1
	eqStatsRow.LayoutOrder = 4
	eqStatsRow.Parent = eqCard

	local eqStatsLayout = Instance.new("UIListLayout")
	eqStatsLayout.FillDirection = Enum.FillDirection.Vertical
	eqStatsLayout.Padding = UDim.new(0, 3)
	eqStatsLayout.Parent = eqStatsRow

	---------------------------------------------------------------------
	-- Bottom Carousel Navigation & Confirmation Bar
	---------------------------------------------------------------------
	local bottomControls = Instance.new("Frame")
	bottomControls.Name = "BottomControls"
	bottomControls.Size = UDim2.new(1, 0, 0, 90)
	bottomControls.AnchorPoint = Vector2.new(0, 1)
	bottomControls.Position = UDim2.new(0, 0, 1, -10)
	bottomControls.BackgroundTransparency = 1
	bottomControls.Parent = container

	-- Left Arrow Button (< PREVIOUS)
	local prevBtn = Instance.new("TextButton")
	prevBtn.Name = "PrevButton"
	prevBtn.Size = UDim2.new(0, 60, 0, 50)
	prevBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	prevBtn.Position = UDim2.new(0.5, -230, 0.5, -8)
	prevBtn.BackgroundColor3 = UITheme.Colors.Surface
	prevBtn.AutoButtonColor = false
	prevBtn.Text = "◀"
	prevBtn.TextColor3 = UITheme.Colors.GoldLight
	prevBtn.Font = UITheme.Fonts.Header
	prevBtn.TextSize = 22
	prevBtn.Parent = bottomControls

	UITheme.AddCorner(prevBtn, 10)
	local prevStroke = UITheme.AddStroke(prevBtn, UITheme.Colors.Border, 1.5, 0.4)

	-- Right Arrow Button (NEXT >)
	local nextBtn = Instance.new("TextButton")
	nextBtn.Name = "NextButton"
	nextBtn.Size = UDim2.new(0, 60, 0, 50)
	nextBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	nextBtn.Position = UDim2.new(0.5, 230, 0.5, -8)
	nextBtn.BackgroundColor3 = UITheme.Colors.Surface
	nextBtn.AutoButtonColor = false
	nextBtn.Text = "▶"
	nextBtn.TextColor3 = UITheme.Colors.GoldLight
	nextBtn.Font = UITheme.Fonts.Header
	nextBtn.TextSize = 22
	nextBtn.Parent = bottomControls

	UITheme.AddCorner(nextBtn, 10)
	local nextStroke = UITheme.AddStroke(nextBtn, UITheme.Colors.Border, 1.5, 0.4)

	-- Center Confirm Button
	local confirmBtn = Instance.new("TextButton")
	confirmBtn.Name = "ConfirmButton"
	confirmBtn.Size = UDim2.new(0, 320, 0, 50)
	confirmBtn.AnchorPoint = Vector2.new(0.5, 0.5)
	confirmBtn.Position = UDim2.new(0.5, 0, 0.5, -8)
	confirmBtn.BackgroundColor3 = UITheme.Colors.Gold
	confirmBtn.AutoButtonColor = false
	confirmBtn.Text = "CONFIRM & ENTER WORLD"
	confirmBtn.TextColor3 = Color3.fromRGB(20, 15, 10)
	confirmBtn.Font = UITheme.Fonts.Button
	confirmBtn.TextSize = 16
	confirmBtn.Parent = bottomControls

	UITheme.AddCorner(confirmBtn, 8)
	local confirmStroke = UITheme.AddStroke(confirmBtn, UITheme.Colors.GoldLight, 2, 0)
	UITheme.AddGradient(confirmBtn, UITheme.Colors.GoldLight, UITheme.Colors.Gold, 90)

	-- Dots / Carousel Indicator Container
	local dotsContainer = Instance.new("Frame")
	dotsContainer.Name = "DotsContainer"
	dotsContainer.Size = UDim2.new(0, 320, 0, 16)
	dotsContainer.AnchorPoint = Vector2.new(0.5, 1)
	dotsContainer.Position = UDim2.new(0.5, 0, 1, 2)
	dotsContainer.BackgroundTransparency = 1
	dotsContainer.Parent = bottomControls

	local dotsLayout = Instance.new("UIListLayout")
	dotsLayout.FillDirection = Enum.FillDirection.Horizontal
	dotsLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	dotsLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	dotsLayout.Padding = UDim.new(0, 8)
	dotsLayout.Parent = dotsContainer

	local dotFrames: { [number]: Frame } = {}

	for i = 1, #ClassData.Order do
		local dot = Instance.new("Frame")
		dot.Name = "Dot_" .. i
		dot.Size = UDim2.new(0, 10, 0, 10)
		dot.BackgroundColor3 = UITheme.Colors.SurfaceSelected
		dot.BorderSizePixel = 0
		dot.Parent = dotsContainer
		UITheme.AddCorner(dot, 5)
		dotFrames[i] = dot

		local dotBtn = Instance.new("TextButton")
		dotBtn.Size = UDim2.new(1, 0, 1, 0)
		dotBtn.BackgroundTransparency = 1
		dotBtn.Text = ""
		dotBtn.Parent = dot
	end

	---------------------------------------------------------------------
	-- Carousel State & Transition Logic
	---------------------------------------------------------------------
	local currentIndex = 1 -- First class in the order is playable (Heavy Knight)
	local isTransitioning = false

	local function updateCarouselUI(index: number, isSlideTransition: boolean?)
		local classId = ClassData.Order[index]
		local info = ClassData.GetClass(classId)
		if not info then return end

		-- Hovering or selecting Heavy Knight immediately applies the requested
		-- blond-gold hair tint; navigating away restores the original color.
		tintKnightHair(player.Character, classId)

		local locked = not ClassData.IsPlayable(classId)
		local accent = locked and Color3.fromRGB(90, 90, 95) or info.accentColor
		constellation.Show(classId, accent, locked)

		-- Apply class-specific cosmetic armor preview on the character
		applyClassCosmetics(classId)
		setSilhouette(player.Character, false)
		if locked then
			setSilhouette(player.Character, true)
		end

		headerCounter.Text = `CLASS {index} OF {#ClassData.Order} • {info.name:upper()}`

		-- Update Left Panel
		classNameLabel.Text = if locked then `{info.name:upper()} · LOCKED` else info.name:upper()
		classNameLabel.TextColor3 = accent
		subtitleLabel.Text = if locked then "Coming soon" else info.title
		roleBadge.Text = `[{info.role:upper()}]`
		roleBadge.TextColor3 = accent
		descLabel.Text = if locked then "This class is still being forged. Check back soon." else info.description
		-- Confirm is disabled on locked classes.
		confirmBtn.Text = if locked then "LOCKED" else "CONFIRM & ENTER WORLD"
		confirmBtn.BackgroundColor3 = if locked then Color3.fromRGB(40, 40, 44) else UITheme.Colors.Gold
		confirmBtn.TextColor3 = if locked then Color3.fromRGB(130, 130, 135) else Color3.fromRGB(20, 15, 10)
		local grad = confirmBtn:FindFirstChildOfClass("UIGradient")
		if grad then grad.Enabled = not locked end

		-- Update Border Accents to match active Class Color
		leftStroke.Color = accent
		rightStroke.Color = accent
		eqStroke.Color = accent
		prevStroke.Color = accent
		nextStroke.Color = accent

		-- Update Stats Pips
		for _, key in ipairs(statKeys) do
			local val = (info.stats :: any)[key] or 1
			local pips = statBars[key]
			if pips then
				for bIdx, pip in ipairs(pips) do
					local active = bIdx <= val
					pip.BackgroundColor3 = active and accent or UITheme.Colors.SurfaceSelected
				end
			end
		end

		-- Clear and Rebuild Abilities
		for _, child in ipairs(abilitiesContainer:GetChildren()) do
			if child:IsA("Frame") then
				child:Destroy()
			end
		end

		for i, ab in ipairs(info.abilities) do
			local abCard = Instance.new("Frame")
			abCard.Name = "Ability_" .. i
			abCard.Size = UDim2.new(1, 0, 0, 48)
			abCard.BackgroundColor3 = UITheme.Colors.SurfaceAlt
			abCard.LayoutOrder = i
			abCard.Parent = abilitiesContainer

			UITheme.AddCorner(abCard, 6)
			UITheme.AddStroke(abCard, UITheme.Colors.Border, 1, 0.6)

			local abTag = Instance.new("TextLabel")
			abTag.Name = "Tag"
			abTag.Size = UDim2.new(0, 90, 0, 16)
			abTag.Position = UDim2.new(0, 8, 0, 5)
			abTag.BackgroundColor3 = UITheme.Colors.Surface
			abTag.Font = UITheme.Fonts.Tag
			abTag.TextSize = 9
			abTag.TextColor3 = accent
			abTag.Text = ab.tag:upper()
			abTag.Parent = abCard
			UITheme.AddCorner(abTag, 3)

			local abName = Instance.new("TextLabel")
			abName.Name = "Name"
			abName.Size = UDim2.new(1, -110, 0, 16)
			abName.Position = UDim2.new(0, 104, 0, 5)
			abName.BackgroundTransparency = 1
			abName.Font = UITheme.Fonts.Header
			abName.TextSize = 12
			abName.TextColor3 = UITheme.Colors.TextPrimary
			abName.TextXAlignment = Enum.TextXAlignment.Left
			abName.Text = if locked then "???" else ab.name
			abName.Parent = abCard

			local abDesc = Instance.new("TextLabel")
			abDesc.Name = "Desc"
			abDesc.Size = UDim2.new(1, -16, 0, 22)
			abDesc.Position = UDim2.new(0, 8, 0, 23)
			abDesc.BackgroundTransparency = 1
			abDesc.Font = UITheme.Fonts.Sub
			abDesc.TextSize = 10
			abDesc.TextColor3 = UITheme.Colors.TextMuted
			abDesc.TextXAlignment = Enum.TextXAlignment.Left
			abDesc.Text = if locked then "" else ab.description
			abDesc.Parent = abCard
		end

		-- Update Equipment Card
		local eq = info.equipment
		if eq then
			eqNameLabel.Text = eq.name
			eqNameLabel.TextColor3 = info.accentColor
			eqRarityBadge.Text = eq.rarity:upper()
			eqRarityBadge.TextColor3 = info.accentColor
			eqSlotLabel.Text = `[ {eq.slot} ]`
			eqDescLabel.Text = eq.description

			-- Rebuild Equipment Stat rows
			for _, child in ipairs(eqStatsRow:GetChildren()) do
				if child:IsA("Frame") then
					child:Destroy()
				end
			end

			local statIdx = 0
			for statName, statVal in pairs(eq.stats or {}) do
				statIdx += 1
				local row = Instance.new("Frame")
				row.Name = "StatRow_" .. statIdx
				row.Size = UDim2.new(1, 0, 0, 16)
				row.BackgroundTransparency = 1
				row.LayoutOrder = statIdx
				row.Parent = eqStatsRow

				local lblKey = Instance.new("TextLabel")
				lblKey.Size = UDim2.new(0.6, 0, 1, 0)
				lblKey.BackgroundTransparency = 1
				lblKey.Font = UITheme.Fonts.Sub
				lblKey.TextSize = 10
				lblKey.TextColor3 = UITheme.Colors.TextSecondary
				lblKey.TextXAlignment = Enum.TextXAlignment.Left
				lblKey.Text = `• {statName}:`
				lblKey.Parent = row

				local lblVal = Instance.new("TextLabel")
				lblVal.Size = UDim2.new(0.4, 0, 1, 0)
				lblVal.AnchorPoint = Vector2.new(1, 0)
				lblVal.Position = UDim2.new(1, 0, 0, 0)
				lblVal.BackgroundTransparency = 1
				lblVal.Font = UITheme.Fonts.Header
				lblVal.TextSize = 10
				lblVal.TextColor3 = UITheme.Colors.Success
				lblVal.TextXAlignment = Enum.TextXAlignment.Right
				lblVal.Text = tostring(statVal)
				lblVal.Parent = row
			end
		end

		-- Update Dots indicator
		for dIdx, dot in ipairs(dotFrames) do
			local isActive = (dIdx == index)
			if isActive then
				TweenService:Create(dot, UITheme.Tweens.Fast, {
					Size = UDim2.new(0, 24, 0, 10),
					BackgroundColor3 = accent,
				}):Play()
			else
				local dotLocked = not ClassData.IsPlayable(ClassData.Order[dIdx])
				TweenService:Create(dot, UITheme.Tweens.Fast, {
					Size = UDim2.new(0, 10, 0, 10),
					BackgroundColor3 = if dotLocked then Color3.fromRGB(14, 14, 16) else UITheme.Colors.SurfaceSelected,
				}):Play()
			end
		end
	end

	local function navigateCarousel(direction: number)
		if isTransitioning then return end
		isTransitioning = true

		local totalClasses = #ClassData.Order
		currentIndex = ((currentIndex - 1 + direction) % totalClasses) + 1

		SoundManager.PlaySelect()
		updateCarouselUI(currentIndex, true)

		task.wait(0.12)
		isTransitioning = false
	end

	-- Hook Navigation Buttons
	UITheme.MakeButtonInteractive(prevBtn, prevStroke, UITheme.Colors.GoldLight, SoundManager.PlayHover, function()
		navigateCarousel(-1)
	end)

	UITheme.MakeButtonInteractive(nextBtn, nextStroke, UITheme.Colors.GoldLight, SoundManager.PlayHover, function()
		navigateCarousel(1)
	end)

	-- Hook Dots Clicking & Hovering
	for dIdx, dot in ipairs(dotFrames) do
		local dotBtn = dot:FindFirstChildOfClass("TextButton")
		if dotBtn then
			dotBtn.MouseEnter:Connect(function()
				if currentIndex ~= dIdx and not isTransitioning then
					currentIndex = dIdx
					SoundManager.PlayHover()
					updateCarouselUI(currentIndex, true)
				end
			end)
			dotBtn.MouseButton1Click:Connect(function()
				if currentIndex ~= dIdx and not isTransitioning then
					currentIndex = dIdx
					SoundManager.PlaySelect()
					updateCarouselUI(currentIndex, true)
				end
			end)
		end
	end

	-- Hook Confirm Button
	UITheme.MakeButtonInteractive(confirmBtn, confirmStroke, UITheme.Colors.GoldLight, SoundManager.PlayHover, function()
		local selectedClassId = ClassData.Order[currentIndex]
		if not ClassData.IsPlayable(selectedClassId) then return end
		SoundManager.PlayConfirm()
		stopPreviewAnimation()
		callbacks.onConfirmClass(selectedClassId)
	end)

	-- Left-click and drag to orbit the camera around the preview character
	-- (the character stays put; the lobby camera swings around it).
	local dragging = false
	local lastDragX = 0
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed or not container.Visible or container.GroupTransparency > 0.5 then return end
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			lastDragX = input.Position.X
			LobbyCamera.HoldOrbit()
		end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			local dx = input.Position.X - lastDragX
			lastDragX = input.Position.X
			LobbyCamera.AddOrbit(-dx * 0.012)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = false
			LobbyCamera.ReleaseOrbit()
		end
	end)

	-- Keyboard Navigation (Left / Right Arrow, Enter). A / D are left alone —
	-- the camera is turned by dragging, not by the movement keys.
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not container.Visible or container.GroupTransparency > 0.5 then return end

		if input.KeyCode == Enum.KeyCode.Left then
			navigateCarousel(-1)
		elseif input.KeyCode == Enum.KeyCode.Right then
			navigateCarousel(1)
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space then
			local selectedClassId = ClassData.Order[currentIndex]
			if not ClassData.IsPlayable(selectedClassId) then return end
			SoundManager.PlayConfirm()
			stopPreviewAnimation()
			callbacks.onConfirmClass(selectedClassId)
		end
	end)

	-- Dynamic Re-renders when screen opens / closes
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible then
			updateCarouselUI(currentIndex, false)
		else
			stopPreviewAnimation()
			local char = player.Character
			if char then
				for _, instance in ipairs(char:GetChildren()) do
					if instance:GetAttribute("PreviewWeapon") or instance.Name == "PreviewGreatsword" then
						instance:Destroy()
					end
				end
			end
		end
	end)

	-- Listen for Character spawning
	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		if container.Visible then
			updateCarouselUI(currentIndex, false)
		end
	end)

	-- Initialize to the first (playable) class
	currentIndex = 1
	updateCarouselUI(currentIndex, false)

	return container
end

return ClassSelectionScreen
