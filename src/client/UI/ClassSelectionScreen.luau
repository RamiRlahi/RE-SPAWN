local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UITheme = require(Shared:WaitForChild("UITheme"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local SkillData = require(Shared:WaitForChild("SkillData"))
local SoundManager = require(script.Parent:WaitForChild("SoundManager"))
local MenuStyle = require(script.Parent:WaitForChild("MenuStyle"))
local M = MenuStyle.Colors
local CastPoses = require(script.Parent.Parent:WaitForChild("CastPoses"))
local UltPreviewFX = require(script.Parent.Parent:WaitForChild("UltPreviewFX"))
local LobbyCamera = require(script.Parent.Parent:WaitForChild("LobbyCamera"))
local TalentConstellation = require(script.Parent:WaitForChild("TalentConstellation"))
local SummonScreen = require(script.Parent:WaitForChild("SummonScreen"))
local CoopScreen = require(script.Parent:WaitForChild("CoopScreen"))
local ClassLook = require(script.Parent.Parent:WaitForChild("ClassLook"))
local AbilityPreview = require(script.Parent:WaitForChild("AbilityPreview"))
local ClassPedestal = require(script.Parent.Parent:WaitForChild("ClassPedestal"))
local MenuBackdrop: any = nil
pcall(function()
	MenuBackdrop = require(script.Parent.Parent:WaitForChild("MenuBackdrop", 5) :: any)
end)

local player = Players.LocalPlayer

-- The class preview is shown on the hero standing in the menu scene (the same
-- one you see on the title screen), not on your real character.
local function previewTarget(): Model?
	local hero = MenuBackdrop and MenuBackdrop.Hero and MenuBackdrop.Hero()
	return hero or player.Character
end

-- The greatsword's twist in the class-select preview only (about the
-- handle's Y axis, which runs along the blade). Flip the sign if it turns
-- the wrong way.
local PREVIEW_SWORD_TWIST = CFrame.Angles(0, math.rad(45), 0)
-- Where the Swordsman's planted longsword's grip sits, in Torso space: centred
-- at chest height between his hands, point down into the ground. Scaled
-- so the tip just bites into the ground.
local SWORDSMAN_PLANT_SCALE = 0.85

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
	ClassPedestal.Hide()
	local target = previewTarget()
	CastPoses.stop(target)
	setSilhouette(target, false)
	currentAnimToken += 1
	if currentPreviewTrack then
		currentPreviewTrack:Stop(0.2)
		currentPreviewTrack:Destroy()
		currentPreviewTrack = nil
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
	-- (entrances from the side come in from the screen's right)
	if classId ~= "heavy_knight" and CastPoses.holdUltPreview(character, classId, { right = workspace.CurrentCamera.CFrame.RightVector }) then
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

-- Class armor is a summon reward; the server sets Armor_<classId> while it's
-- owned and equipped. Without it the preview shows your avatar + the weapon.
local function wearsArmor(classId: string): boolean
	return player:GetAttribute(`Armor_{classId}`) == true
end

local previewClassId: string? = nil

-- How the weapon sits in the preview: the Sword Master's rapier runs along
-- his arm (pointing out at the camera, en garde), and the greatsword turns
-- its flat face to the camera.
local function previewGrip(classId: string, grip: CFrame): CFrame
	if classId == "swordsman" then return grip * CFrame.Angles(math.rad(90), 0, 0) end
	if classId == "heavy_knight" then return grip * PREVIEW_SWORD_TWIST end
	return grip
end

local function applyClassCosmetics(classId: string)
	previewClassId = classId
	if currentScreenContainer and not currentScreenContainer.Visible then return end
	local character = previewTarget()
	if not character then return end
	-- The round dais the menu hero stands on, with the class's aura (only on
	-- the menu's copy: never lift your real character).
	local hero = MenuBackdrop and MenuBackdrop.Hero and MenuBackdrop.Hero()
	if hero and character == hero then
		ClassPedestal.Show(hero, classId, not ClassData.IsOwnedBy(player, classId))
	else
		ClassPedestal.Hide()
	end
	-- Weapon in hand and (if owned) armor, then the ultimate's pose with a
	-- looping preview of its effects.
	ClassLook.Apply(character, classId, {
		armor = wearsArmor(classId),
		grip = previewGrip,
		plant = nil,
		plantScale = SWORDSMAN_PLANT_SCALE,
		-- (your Armory gear on every class you look at)
		finish = Players.LocalPlayer:GetAttribute("Gear_weapon"),
		aura = Players.LocalPlayer:GetAttribute("Gear_aura"),
	})
	playPreviewAnimation(character, classId)
	if ClassData.IsPlayable(classId) then
		UltPreviewFX.Start(character, classId)
	else
		UltPreviewFX.Stop()
	end
end

-- The hero is re-copied when your avatar finishes loading or changes: dress
-- the new copy too.
if MenuBackdrop and MenuBackdrop.OnHeroChanged then
	MenuBackdrop.OnHeroChanged(function()
		if previewClassId and currentScreenContainer and currentScreenContainer.Visible then
			applyClassCosmetics(previewClassId)
		end
	end)
end


export type ClassSelectionCallbacks = {
	onBackToTitle: () -> (),
	onConfirmClass: (classId: string) -> (),
	onOpenSettings: (() -> ())?,
}

local ClassSelectionScreen = {}

-- Pulling or (un)equipping armor refreshes the preview of the shown class.
player.AttributeChanged:Connect(function(name)
	if string.sub(name, 1, 6) ~= "Armor_" or not previewClassId then return end
	if currentScreenContainer and currentScreenContainer.Visible then
		tintKnightHair(previewTarget(), if wearsArmor(previewClassId) then previewClassId else "")
		applyClassCosmetics(previewClassId)
	end
end)

-- ── The look ───────────────────────────────────────────────────────────────
-- Laid out on a 1672 × 941 canvas (the reference) and scaled to the screen.
local REF_W, REF_H = 1672, 941

local FONT_DISPLAY = Font.new("rbxasset://fonts/families/AccanthisADFStd.json", Enum.FontWeight.Bold)
local FONT_HEAD = Font.new("rbxasset://fonts/families/AccanthisADFStd.json", Enum.FontWeight.Regular)
local FONT_BODY = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)

local GOLD = Color3.fromRGB(226, 186, 128)
local GOLD_DIM = Color3.fromRGB(128, 96, 62)
local TEXT = Color3.fromRGB(242, 228, 210)
local MUTED = Color3.fromRGB(184, 164, 146)
local PANEL = Color3.fromRGB(14, 10, 11)
local INK = Color3.fromRGB(6, 4, 5)
local LOCKED_GREY = Color3.fromRGB(110, 110, 118)

local function new(className: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(className)
	for k, v in pairs(props) do (inst :: any)[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function text(parent: Instance, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1,
		FontFace = FONT_HEAD,
		TextColor3 = TEXT,
		TextSize = 16,
	}, nil)
	for k, v in pairs(props) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function stroke(parent: Instance, color: Color3, thickness: number, transparency: number?): UIStroke
	return new("UIStroke", {
		Color = color, Thickness = thickness, Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, parent)
end

-- A thin gold rule fading out toward `fade` ("left", "right" or "both").
local function rule(parent: Instance, pos: UDim2, size: UDim2, fade: string, color: Color3?, z: number?): Frame
	local f = new("Frame", { Position = pos, Size = size, BackgroundColor3 = color or GOLD, BorderSizePixel = 0, ZIndex = z or 2 }, parent)
	local keys = if fade == "left" then { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.15) }
		elseif fade == "right" then { NumberSequenceKeypoint.new(0, 0.15), NumberSequenceKeypoint.new(1, 1) }
		else { NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.15), NumberSequenceKeypoint.new(1, 1) }
	new("UIGradient", { Transparency = NumberSequence.new(keys) }, f)
	return f
end

-- A small diamond (a turned square); `filled` or an outline.
local function diamond(parent: Instance, pos: UDim2, size: number, color: Color3, filled: boolean, z: number?): Frame
	local d = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = pos, Size = UDim2.fromOffset(size, size), Rotation = 45,
		BackgroundColor3 = color, BackgroundTransparency = if filled then 0 else 1, BorderSizePixel = 0, ZIndex = z or 3,
	}, parent)
	if not filled then stroke(d, color, 1) end
	return d
end

-- "———◆  TEXT  ◆———", centred in `parent` at height `y`.
local function headerRule(parent: Instance, y: number, width: number, label: string, textSize: number): TextLabel
	local t = text(parent, {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0, y), Size = UDim2.fromOffset(width, textSize + 6),
		Text = label, TextSize = textSize, TextColor3 = GOLD, ZIndex = 3,
	})
	local half = math.floor((width - (#label * textSize * 0.62) - 40) / 2)
	half = math.max(half, 20)
	rule(parent, UDim2.new(0.5, -width / 2, 0, y), UDim2.fromOffset(half, 1), "left")
	rule(parent, UDim2.new(0.5, width / 2 - half, 0, y), UDim2.fromOffset(half, 1), "right")
	diamond(parent, UDim2.new(0.5, -width / 2 + half, 0, y), 6, GOLD, true)
	diamond(parent, UDim2.new(0.5, width / 2 - half, 0, y), 6, GOLD, true)
	return t
end

-- Corner ornaments for a panel: a little diamond at each corner and an
-- inner hairline.
local function ornateFrame(f: GuiObject, color: Color3)
	stroke(f, color, 1, 0.35)
	local inner = new("Frame", { Name = "Inner", Size = UDim2.new(1, -10, 1, -10), Position = UDim2.fromOffset(5, 5),
		BackgroundTransparency = 1, ZIndex = f.ZIndex }, f)
	stroke(inner, color, 1, 0.75)
	for _, c in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
		diamond(f, UDim2.fromScale(c.X, c.Y), 7, color, true, f.ZIndex + 2)
	end
end

-- Small line-art icons drawn from frames (Roblox's fonts carry almost no
-- symbols). Each fills a 34 px box; tint() recolours one.
local function bar(parent: Instance, cx: number, cy: number, w: number, h: number, rot: number, z: number?): Frame
	return new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(cx, cy), Size = UDim2.fromOffset(w, h),
		Rotation = rot, BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = z or 5 }, parent)
end

local ICONS: { [string]: (Frame) -> { any } } = {
	damage = function(b) -- a sword, point up and to the right
		return { bar(b, 19, 15, 4, 24, 45), bar(b, 11, 23, 13, 3, 45), bar(b, 7, 27, 3, 6, 45) }
	end,
	survivability = function(b) -- a shield
		local top = bar(b, 17, 12, 20, 12, 0)
		local tip = bar(b, 17, 18, 14, 14, 45)
		local inner = bar(b, 17, 15, 3, 14, 0, 6)
		inner.BackgroundColor3 = INK
		inner.BackgroundTransparency = 0.4
		return { top, tip }
	end,
	mobility = function(b) -- two chevrons
		return { bar(b, 11, 13, 12, 3, 45), bar(b, 11, 21, 12, 3, -45), bar(b, 21, 13, 12, 3, 45), bar(b, 21, 21, 12, 3, -45) }
	end,
	range = function(b) -- crosshair
		local ring = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(17, 17), Size = UDim2.fromOffset(18, 18),
			BackgroundTransparency = 1, ZIndex = 5 }, b)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, ring)
		local st = new("UIStroke", { Color = GOLD, Thickness = 2 }, ring)
		local parts: { any } = { bar(b, 17, 4, 2, 8, 0), bar(b, 17, 30, 2, 8, 0), bar(b, 4, 17, 8, 2, 0), bar(b, 30, 17, 8, 2, 0), bar(b, 17, 17, 4, 4, 45) }
		table.insert(parts, st)
		return parts
	end,
	difficulty = function(b) -- a four-pointed star
		return { bar(b, 17, 17, 3, 28, 0), bar(b, 17, 17, 28, 3, 0), bar(b, 17, 17, 10, 10, 45), bar(b, 17, 17, 2, 16, 45), bar(b, 17, 17, 16, 2, 45) }
	end,
}

local function tint(parts: { any }, color: Color3)
	for _, p in ipairs(parts) do
		if p:IsA("UIStroke") then p.Color = color else p.BackgroundColor3 = color end
	end
end

-- The RE-SPAWN compass star.
local function compassStar(parent: Instance, size: number)
	local c = size / 2
	local long = bar(parent, c, c, 2, size, 0, 3)
	local wide = bar(parent, c, c, size, 2, 0, 3)
	for _, f in ipairs({ long, wide }) do
		new("UIGradient", { Rotation = if f == long then 90 else 0, Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0), NumberSequenceKeypoint.new(1, 1) }) }, f)
	end
	bar(parent, c, c, 1, size * 0.6, 45, 3)
	bar(parent, c, c, size * 0.6, 1, 45, 3)
	local o = bar(parent, c, c, size * 0.36, size * 0.36, 45, 4)
	o.BackgroundTransparency = 1
	new("UIStroke", { Color = GOLD, Thickness = 1.5 }, o)
	bar(parent, c, c, size * 0.16, size * 0.16, 45, 5)
end

-- The class emblem: its passive's icon (else the ultimate's).
local function emblemIcon(info: any): string
	local pick = ""
	for _, ab in ipairs(info.abilities or {}) do
		local tag = ab.tag or ""
		if ab.icon and ab.icon ~= "" then
			if string.find(tag, "Passive", 1, true) then return ab.icon end
			if string.find(tag, "Ultimate", 1, true) then pick = ab.icon end
		end
	end
	return pick
end

local function percent(v: number): string
	return `{math.floor(v + 0.5)}`
end

-- The weapon, turned to lie corner to corner in a ViewportFrame (the
-- Signature Equipment picture). Returns false when the class has none.
local function showWeapon(vp: ViewportFrame, classId: string, accent: Color3): boolean
	for _, c in ipairs(vp:GetChildren()) do
		if not c:IsA("UICorner") then c:Destroy() end
	end
	local ok, tool = pcall(ClassLook.BuildWeapon, classId)
	if not ok or not tool then return false end
	local model = Instance.new("Model")
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("LuaSourceContainer") or d:IsA("ParticleEmitter") or d:IsA("Light") or d:IsA("Sound") or d:IsA("Trail") or d:IsA("Beam") then
			d:Destroy()
		end
	end
	for _, c in ipairs(tool:GetChildren()) do c.Parent = model end
	tool:Destroy()
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			d.Anchored = true
			table.insert(parts, d)
		end
	end
	if #parts == 0 then
		model:Destroy()
		return false
	end
	local cf, size = model:GetBoundingBox()
	-- Longest axis corner to corner (up and to the right), the flat face to us.
	local axes = { { v = cf.RightVector, s = size.X }, { v = cf.UpVector, s = size.Y }, { v = -cf.LookVector, s = size.Z } }
	local order = { 1, 2, 3 }
	table.sort(order, function(a, b) return axes[a].s > axes[b].s end)
	local tilt = math.rad(32)
	local target: { Vector3 } = {}
	target[order[1]] = Vector3.new(math.cos(tilt), math.sin(tilt), 0)
	target[order[2]] = Vector3.new(-math.sin(tilt), math.cos(tilt), 0)
	target[order[3]] = Vector3.new(0, 0, 1)
	if target[1]:Cross(target[2]):Dot(target[3]) < 0 then target[order[3]] = Vector3.new(0, 0, -1) end
	local goal = CFrame.fromMatrix(Vector3.zero, target[1], target[2], -target[3])
	for _, p in ipairs(parts) do
		p.CFrame = goal * cf:ToObjectSpace(p.CFrame)
	end
	model.Parent = vp
	local long = axes[order[1]].s
	local cam = new("Camera", { FieldOfView = 30 }, vp)
	local dist = (long * 0.5) / math.tan(math.rad(15))
	cam.CFrame = CFrame.lookAt(Vector3.new(0, 0, dist), Vector3.zero)
	vp.CurrentCamera = cam
	vp.LightColor = accent:Lerp(Color3.new(1, 1, 1), 0.6)
	vp.LightDirection = Vector3.new(-0.4, -1, -0.6)
	vp.Ambient = Color3.fromRGB(205, 190, 175)
	return true
end

function ClassSelectionScreen.Create(parent: GuiObject, callbacks: ClassSelectionCallbacks): CanvasGroup
	local container = Instance.new("CanvasGroup")
	container.Name = "ClassSelectionScreen"
	container.Size = UDim2.new(1, 0, 1, 0)
	container.BackgroundTransparency = 1
	container.GroupTransparency = 1
	container.Visible = false
	-- (the serif look of this screen; FontStyle keeps everything else Arcade)
	container:SetAttribute("KeepFont", true)
	container.Parent = parent
	currentScreenContainer = container
	-- Leaving the screen: if the preview had to fall back to your own
	-- character (no menu hero yet), take the preview off it again: the
	-- display weapon, armor and cape, the pose, the effects. (Otherwise the
	-- display sword went into the dungeon beside the real one.)
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible then return end
		pcall(ClassPedestal.Hide)
		local char = player.Character
		if not char then return end
		pcall(ClassLook.Clear, char)
		pcall(UltPreviewFX.Stop)
		pcall(CastPoses.stop, char)
		pcall(setSilhouette, char, false)
		pcall(tintKnightHair, char, "")
	end)

	---------------------------------------------------------------------
	-- Shade: dark edges so the panels read over the scene, the centre open.
	---------------------------------------------------------------------
	local shadeL = new("Frame", { Name = "ShadeLeft", Size = UDim2.new(0.42, 0, 1, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, container)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.25), NumberSequenceKeypoint.new(0.6, 0.6), NumberSequenceKeypoint.new(1, 1) }) }, shadeL)
	local shadeR = new("Frame", { Name = "ShadeRight", AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0.38, 0, 1, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, container)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.45, 0.6), NumberSequenceKeypoint.new(1, 0.3) }) }, shadeR)
	local shadeB = new("Frame", { Name = "ShadeBottom", AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0.3, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, container)
	local shadeBGrad = new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0.2) }) }, shadeB)
	local shadeT = new("Frame", { Name = "ShadeTop", Size = UDim2.new(1, 0, 0.16, 0), BackgroundColor3 = INK, BorderSizePixel = 0 }, container)
	new("UIGradient", { Rotation = 90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }) }, shadeT)
	-- (a warm glow of the class's colour along the bottom)
	local accentGlow = new("Frame", { Name = "AccentGlow", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromScale(0.5, 1), Size = UDim2.new(0.7, 0, 0.22, 0), BackgroundColor3 = GOLD, BorderSizePixel = 0 }, container)
	new("UIGradient", { Rotation = -90, Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 1) }) }, accentGlow)
	local _ = shadeBGrad

	---------------------------------------------------------------------
	-- Scaled groups, each pinned to a corner or edge of the screen.
	---------------------------------------------------------------------
	type Group = { frame: Frame, scale: UIScale, anchor: Vector2, at: Vector2 }
	local groups: { Group } = {}
	local function group(name: string, anchor: Vector2, at: Vector2, size: Vector2): Frame
		local f = new("Frame", { Name = name, AnchorPoint = anchor, Size = UDim2.fromOffset(size.X, size.Y), BackgroundTransparency = 1, ZIndex = 2 }, container)
		local sc = new("UIScale", {}, f)
		table.insert(groups, { frame = f, scale = sc, anchor = anchor, at = at })
		return f
	end
	local function relayout()
		local vp = workspace.CurrentCamera.ViewportSize
		local s = math.clamp(math.min(vp.Y / REF_H, vp.X / REF_W), 0.45, 1.6)
		for _, g in ipairs(groups) do
			g.scale.Scale = s
			g.frame.Position = UDim2.new(g.anchor.X, g.at.X * s, g.anchor.Y, g.at.Y * s)
		end
	end

	---------------------------------------------------------------------
	-- Top left: the RE-SPAWN mark, and Title / Hide UI under it.
	---------------------------------------------------------------------
	local logo = group("Logo", Vector2.new(0, 0), Vector2.new(30, 58), Vector2.new(330, 92))
	local mark = new("Frame", { Name = "Mark", Size = UDim2.fromOffset(60, 60), BackgroundTransparency = 1 }, logo)
	compassStar(mark, 60)
	text(logo, { Position = UDim2.fromOffset(74, 12), Size = UDim2.fromOffset(240, 36), Text = "RE-SPAWN", TextSize = 28,
		TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, FontFace = FONT_HEAD })

	local function textButton(parentF: Instance, label: string, pos: UDim2, size: Vector2, onClick: () -> ()): (TextButton, TextLabel, UIStroke)
		local b = new("TextButton", { Position = pos, Size = UDim2.fromOffset(size.X, size.Y), BackgroundColor3 = PANEL, BackgroundTransparency = 0.25,
			BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 3 }, parentF)
		local st = stroke(b, GOLD_DIM, 1, 0.1)
		local l = text(b, { Size = UDim2.fromScale(1, 1), Text = label, TextSize = 17, TextColor3 = MUTED, ZIndex = 4 })
		b.MouseEnter:Connect(function()
			st.Color = GOLD
			l.TextColor3 = TEXT
			SoundManager.PlayHover()
		end)
		b.MouseLeave:Connect(function()
			st.Color = GOLD_DIM
			l.TextColor3 = MUTED
		end)
		b.MouseButton1Click:Connect(onClick)
		return b, l, st
	end

	local uiHidden = false
	local setHidden: (boolean) -> () = function() end
	textButton(logo, "‹  TITLE", UDim2.fromOffset(0, 66), Vector2.new(104, 26), function()
		SoundManager.Play("Select")
		callbacks.onBackToTitle()
	end)
	textButton(logo, "HIDE UI", UDim2.fromOffset(114, 66), Vector2.new(96, 26), function()
		SoundManager.Play("Select")
		setHidden(true)
	end)

	---------------------------------------------------------------------
	-- Top right: "CHARACTER SELECTION ◆ n / total".
	---------------------------------------------------------------------
	local header = group("Header", Vector2.new(1, 0), Vector2.new(-34, 22), Vector2.new(560, 34))
	local headerText = text(header, { AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(380, 30),
		Text = "CHARACTER SELECTION  ◆  1 / 13", TextSize = 19, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })
	rule(header, UDim2.new(0, 10, 0.5, 0), UDim2.fromOffset(150, 1), "left")
	diamond(header, UDim2.new(0, 10, 0.5, 0), 6, GOLD, false)
	diamond(header, UDim2.new(0, 160, 0.5, 0), 6, GOLD, true)

	---------------------------------------------------------------------
	-- Left: emblem, tagline, name, roles, description, the five ratings.
	---------------------------------------------------------------------
	local left = group("LeftPanel", Vector2.new(0, 0), Vector2.new(44, 150), Vector2.new(410, 520))
	-- the emblem between two short rules
	local emblem = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.fromOffset(46, 46),
		BackgroundColor3 = INK, BorderSizePixel = 0, ScaleType = Enum.ScaleType.Crop, ZIndex = 4 }, left)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, emblem)
	local emblemStroke = stroke(emblem, GOLD, 1.5)
	rule(left, UDim2.new(0.5, -110, 0, 26), UDim2.fromOffset(70, 1), "left")
	rule(left, UDim2.new(0.5, 40, 0, 26), UDim2.fromOffset(70, 1), "right")
	diamond(left, UDim2.new(0.5, -40, 0, 26), 5, GOLD, true)
	diamond(left, UDim2.new(0.5, 40, 0, 26), 5, GOLD, true)

	-- "—— TAGLINE ——": rules sized to the words.
	local tagRow = new("Frame", { Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, ZIndex = 3 }, left)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, tagRow)
	local tagRuleL = rule(tagRow, UDim2.new(), UDim2.fromOffset(46, 1), "left")
	tagRuleL.LayoutOrder = 1
	local tagline = text(tagRow, { Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, Text = "THE INFERNAL VANGUARD",
		TextSize = 19, TextColor3 = TEXT, ZIndex = 3, LayoutOrder = 2 })
	local tagRuleR = rule(tagRow, UDim2.new(), UDim2.fromOffset(46, 1), "right")
	tagRuleR.LayoutOrder = 3

	local nameLabel = text(left, { Position = UDim2.fromOffset(0, 84), Size = UDim2.new(1, 0, 0, 70), Text = "FIRE KNIGHT",
		TextSize = 62, TextScaled = true, FontFace = FONT_DISPLAY, TextColor3 = Color3.new(1, 1, 1), ZIndex = 3 })
	new("UITextSizeConstraint", { MaxTextSize = 62, MinTextSize = 30 }, nameLabel)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(255, 248, 236), Color3.fromRGB(226, 200, 168)) }, nameLabel)
	stroke(nameLabel, INK, 1, 0.5).ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual

	local rolesLabel = text(left, { Position = UDim2.fromOffset(0, 160), Size = UDim2.new(1, 0, 0, 22), Text = "BRUISER  •  VANGUARD",
		TextSize = 17, TextColor3 = MUTED, ZIndex = 3 })
	rule(left, UDim2.fromOffset(4, 171), UDim2.fromOffset(70, 1), "left")
	rule(left, UDim2.new(1, -74, 0, 171), UDim2.fromOffset(70, 1), "right")

	local descLabel = text(left, { Position = UDim2.fromOffset(20, 200), Size = UDim2.new(1, -40, 0, 56), Text = "",
		TextSize = 18, FontFace = FONT_BODY, TextColor3 = TEXT, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 })
	new("UITextSizeConstraint", { MaxTextSize = 18, MinTextSize = 12 }, descLabel)
	descLabel.TextScaled = true

	local statsBox = new("Frame", { Name = "Stats", Position = UDim2.fromOffset(4, 270), Size = UDim2.new(1, -8, 0, 250),
		BackgroundColor3 = PANEL, BackgroundTransparency = 0.35, BorderSizePixel = 0, ZIndex = 2 }, left)
	stroke(statsBox, GOLD_DIM, 1, 0.6)

	local STATS = {
		{ key = "damage", label = "DAMAGE" },
		{ key = "survivability", label = "SURVIVABILITY" },
		{ key = "mobility", label = "MOBILITY" },
		{ key = "range", label = "RANGE" },
		{ key = "difficulty", label = "DIFFICULTY" },
	}
	type StatRow = { value: TextLabel, fill: Frame, glow: Frame, icon: { any } }
	local statRows: { [string]: StatRow } = {}
	for i, st in ipairs(STATS) do
		local y = 14 + (i - 1) * 47
		local row = new("Frame", { Name = "Stat_" .. st.key, Position = UDim2.fromOffset(0, y), Size = UDim2.new(1, 0, 0, 44), BackgroundTransparency = 1, ZIndex = 3 }, statsBox)
		local iconBox = new("Frame", { Position = UDim2.fromOffset(14, 4), Size = UDim2.fromOffset(34, 34), BackgroundTransparency = 1, ZIndex = 4 }, row)
		local icon = ICONS[st.key](iconBox)
		text(row, { Position = UDim2.fromOffset(60, 2), Size = UDim2.fromOffset(200, 20), Text = st.label, TextSize = 17,
			TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 4 })
		local value = text(row, { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -18, 0, 2), Size = UDim2.fromOffset(110, 20),
			Text = "0 / 100", TextSize = 17, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 4 })
		local track = new("Frame", { Position = UDim2.fromOffset(60, 28), Size = UDim2.new(1, -78, 0, 5), BackgroundColor3 = Color3.fromRGB(40, 32, 30),
			BorderSizePixel = 0, ZIndex = 4 }, row)
		local glowBar = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.new(0, 0, 0, 11),
			BackgroundColor3 = GOLD, BackgroundTransparency = 0.75, BorderSizePixel = 0, ZIndex = 4 }, track)
		new("UICorner", { CornerRadius = UDim.new(1, 0) }, glowBar)
		local fill = new("Frame", { Name = "Fill", Size = UDim2.new(0, 0, 1, 0), BackgroundColor3 = GOLD, BorderSizePixel = 0, ZIndex = 5 }, track)
		new("UIGradient", { Color = ColorSequence.new(Color3.fromRGB(255, 255, 255), Color3.fromRGB(200, 200, 200)) }, fill)
		statRows[st.key] = { value = value, fill = fill, glow = glowBar, icon = icon }
	end

	---------------------------------------------------------------------
	-- Right: SKILLS and SIGNATURE EQUIPMENT.
	---------------------------------------------------------------------
	local right = group("RightPanel", Vector2.new(1, 0), Vector2.new(-32, 120), Vector2.new(400, 604))
	local rightBg = new("Frame", { Name = "Bg", Size = UDim2.fromScale(1, 1), BackgroundColor3 = PANEL, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 1 }, right)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(40, 32, 30), Color3.fromRGB(12, 9, 9)) }, rightBg)
	ornateFrame(right, GOLD_DIM)
	headerRule(right, 28, 330, "SKILLS", 19)

	local skillList = new("Frame", { Name = "Skills", Position = UDim2.fromOffset(20, 50), Size = UDim2.new(1, -40, 0, 400), BackgroundTransparency = 1, ZIndex = 2 }, right)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, skillList)

	headerRule(right, 470, 340, "SIGNATURE EQUIPMENT", 18)
	local eqRow = new("Frame", { Name = "Equipment", Position = UDim2.fromOffset(20, 490), Size = UDim2.new(1, -40, 0, 100), BackgroundTransparency = 1, ZIndex = 2 }, right)
	-- (a soft streak of the class colour behind the weapon)
	local eqGlow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(75, 48), Size = UDim2.fromOffset(150, 30),
		Rotation = -32, BackgroundColor3 = GOLD, BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 2 }, eqRow)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, eqGlow)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, eqGlow)
	local eqView = new("ViewportFrame", { Name = "Weapon", Size = UDim2.fromOffset(150, 96), BackgroundTransparency = 1, ZIndex = 3 }, eqRow)
	local eqGlyph = new("ImageLabel", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(75, 48), Size = UDim2.fromOffset(72, 72),
		BackgroundTransparency = 1, ScaleType = Enum.ScaleType.Crop, ZIndex = 3 }, eqRow)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, eqGlyph)
	local eqName = text(eqRow, { Position = UDim2.fromOffset(158, 18), Size = UDim2.new(1, -158, 0, 28), Text = "", TextSize = 22,
		TextScaled = true, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 3 })
	new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }, eqName)
	local eqDesc = text(eqRow, { Position = UDim2.fromOffset(158, 50), Size = UDim2.new(1, -158, 0, 40), Text = "", TextSize = 15,
		FontFace = FONT_BODY, TextColor3 = MUTED, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 3 })

	---------------------------------------------------------------------
	-- Bottom centre: ◇ <  01 – NAME  > ◇, the page dots, SELECT CLASS.
	---------------------------------------------------------------------
	local bottom = group("BottomCenter", Vector2.new(0.5, 1), Vector2.new(0, -22), Vector2.new(620, 196))
	local nameBand = new("Frame", { Name = "NameBand", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(440, 56),
		BackgroundColor3 = INK, BackgroundTransparency = 0.25, BorderSizePixel = 0, ZIndex = 2 }, bottom)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.2), NumberSequenceKeypoint.new(0.8, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, nameBand)
	rule(nameBand, UDim2.fromOffset(0, 0), UDim2.new(1, 0, 0, 1), "both", GOLD_DIM)
	rule(nameBand, UDim2.new(0, 0, 1, -1), UDim2.new(1, 0, 0, 1), "both", GOLD_DIM)
	local indexLabel = text(nameBand, { Size = UDim2.fromScale(1, 1), Text = "01 – FIRE KNIGHT", TextSize = 28, TextColor3 = TEXT, ZIndex = 3 })

	local function arrowButton(dir: number): (TextButton, Frame)
		local b = new("TextButton", { Name = if dir < 0 then "PrevButton" else "NextButton", AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, dir * 262, 0, 34), Size = UDim2.fromOffset(78, 78), BackgroundTransparency = 1, Text = "", ZIndex = 4 }, bottom)
		local outer = diamond(b, UDim2.fromScale(0.5, 0.5), 48, GOLD, false, 4)
		outer.BackgroundColor3 = INK
		outer.BackgroundTransparency = 0.25
		diamond(b, UDim2.fromScale(0.5, 0.5), 38, GOLD_DIM, false, 4)
		text(b, { Size = UDim2.fromScale(1, 1), Text = if dir < 0 then "‹" else "›", TextSize = 46, TextColor3 = TEXT, ZIndex = 6,
			Position = UDim2.fromOffset(0, -4) })
		-- (little ornaments outside the diamond)
		diamond(b, UDim2.new(0.5, dir * -44, 0.5, 0), 6, GOLD, true, 5)
		rule(b, UDim2.new(0.5, if dir < 0 then 36 else -56, 0.5, 0), UDim2.fromOffset(20, 1), if dir < 0 then "right" else "left")
		return b, outer
	end
	local prevBtn, prevDiamond = arrowButton(-1)
	local nextBtn, nextDiamond = arrowButton(1)

	local dotsRow = new("Frame", { Name = "Dots", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 74), Size = UDim2.fromOffset(440, 16),
		BackgroundTransparency = 1, ZIndex = 3 }, bottom)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Center, Padding = UDim.new(0, 12), SortOrder = Enum.SortOrder.LayoutOrder }, dotsRow)
	local dotFrames: { Frame } = {}
	local dotButtons: { TextButton } = {}
	for i = 1, #ClassData.Order do
		local holder = new("TextButton", { Name = "Dot_" .. i, Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 1, Text = "", LayoutOrder = i, ZIndex = 3 }, dotsRow)
		local d = diamond(holder, UDim2.fromScale(0.5, 0.5), 7, GOLD_DIM, true, 4)
		dotFrames[i] = d
		dotButtons[i] = holder
	end

	-- The SELECT CLASS button: a long plate with pointed ends and a double rule.
	local selectBtn = new("TextButton", { Name = "ConfirmButton", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 108),
		Size = UDim2.fromOffset(400, 70), BackgroundColor3 = Color3.fromRGB(22, 14, 12), BorderSizePixel = 0, AutoButtonColor = false, Text = "", ZIndex = 5 }, bottom)
	new("UIGradient", { Rotation = 90, Color = ColorSequence.new(Color3.fromRGB(56, 30, 20), Color3.fromRGB(16, 10, 9)) }, selectBtn)
	local selStroke = stroke(selectBtn, GOLD, 2)
	local selGlow = new("Frame", { Name = "Glow", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 14, 1, 14),
		BackgroundTransparency = 1, ZIndex = 4 }, selectBtn)
	local selGlowStroke = stroke(selGlow, GOLD, 6, 0.75)
	local selInner = new("Frame", { Size = UDim2.new(1, -12, 1, -12), Position = UDim2.fromOffset(6, 6), BackgroundTransparency = 1, ZIndex = 6 }, selectBtn)
	local selInnerStroke = stroke(selInner, GOLD, 1, 0.55)
	local selEnds: { Frame } = {}
	for _, side in ipairs({ 0, 1 }) do
		local e = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(side, 0, 0.5, 0), Size = UDim2.fromOffset(50, 50), Rotation = 45,
			BackgroundColor3 = Color3.fromRGB(30, 18, 14), BorderSizePixel = 0, ZIndex = 4 }, selectBtn)
		stroke(e, GOLD, 2)
		table.insert(selEnds, e)
		diamond(selectBtn, UDim2.new(side, if side == 0 then 34 else -34, 0.5, 0), 8, GOLD, true, 7)
	end
	local selectLabel = text(selectBtn, { Size = UDim2.new(1, -90, 1, 0), Position = UDim2.fromOffset(45, 0), Text = "SELECT CLASS", TextSize = 36,
		TextScaled = true, FontFace = FONT_DISPLAY, TextColor3 = TEXT, ZIndex = 7 })
	new("UITextSizeConstraint", { MaxTextSize = 36, MinTextSize = 14 }, selectLabel)
	local selScale = new("UIScale", {}, selectBtn)

	---------------------------------------------------------------------
	-- Bottom left: Settings, Co-op, Talents. Bottom right: the motto.
	---------------------------------------------------------------------
	local bl = group("BottomLeft", Vector2.new(0, 1), Vector2.new(34, -34), Vector2.new(520, 44))
	textButton(bl, "⚙  SETTINGS", UDim2.fromOffset(0, 0), Vector2.new(158, 44), function()
		SoundManager.Play("Select")
		if callbacks.onOpenSettings then callbacks.onOpenSettings() end
	end)
	CoopScreen.Init() -- listen for party updates and invites from the start
	textButton(bl, "CO-OP", UDim2.fromOffset(168, 0), Vector2.new(132, 44), function()
		SoundManager.Play("Select")
		CoopScreen.Open()
	end)
	local talentsBtnLabel: TextLabel
	local _, tl = textButton(bl, "◆  TALENTS", UDim2.fromOffset(310, 0), Vector2.new(150, 44), function() end)
	talentsBtnLabel = tl

	local br = group("BottomRight", Vector2.new(1, 1), Vector2.new(-36, -40), Vector2.new(420, 24))
	text(br, { Size = UDim2.fromScale(1, 1), Text = "FIGHT   ◆   SURVIVE   ◆   RESPAWN", TextSize = 17, TextColor3 = MUTED,
		TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3 })

	-- The talent constellation (souls, the class's talent tree) takes the left
	-- panel's place while TALENTS is on.
	local constellation = TalentConstellation.Create(container)
	constellation.Frame:SetAttribute("KeepFont", false)
	constellation.Frame.Visible = false
	-- (below the logo and the Title / Hide UI buttons, above the bottom row)
	constellation.Frame.Position = UDim2.new(0, 24, 0, 170)
	constellation.Frame.Size = UDim2.new(0.42, 0, 1, -260)
	local talentsOpen = false
	local talentsBtn = talentsBtnLabel.Parent :: TextButton
	talentsBtn.MouseButton1Click:Connect(function()
		SoundManager.Play("Select")
		talentsOpen = not talentsOpen
		constellation.Frame.Visible = talentsOpen and not uiHidden
		left.Visible = not talentsOpen and not uiHidden
		talentsBtnLabel.Text = if talentsOpen then "◆  CLASS INFO" else "◆  TALENTS"
	end)

	-- Hide UI: everything but a SHOW UI button, so the hero can be admired.
	local showBtn = textButton(container, "SHOW UI", UDim2.new(0, 24, 1, -60), Vector2.new(110, 34), function()
		SoundManager.Play("Select")
		setHidden(false)
	end)
	showBtn.Visible = false
	setHidden = function(on: boolean)
		uiHidden = on
		for _, g in ipairs(groups) do
			g.frame.Visible = not on and not (g.frame == left and talentsOpen)
		end
		constellation.Frame.Visible = talentsOpen and not on
		for _, f in ipairs({ shadeL, shadeR, shadeT }) do f.Visible = not on end
		showBtn.Visible = on
	end

	relayout()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(relayout)

	---------------------------------------------------------------------
	-- Filling it in for a class.
	---------------------------------------------------------------------
	local currentIndex = 1
	local isTransitioning = false
	local ultGlowTween: Tween? = nil

	local function skillRow(ab: any, order: number, accent: Color3, locked: boolean, isUlt: boolean)
		local row = new("TextButton", { Name = "Skill_" .. order, Size = UDim2.new(1, 0, 0, 90), LayoutOrder = order, AutoButtonColor = false,
			Text = "", BackgroundColor3 = if isUlt then accent else PANEL, BackgroundTransparency = if isUlt then 0.86 else 0.5,
			BorderSizePixel = 0, ZIndex = 3 }, skillList)
		local rowStroke = stroke(row, if isUlt then accent else GOLD_DIM, if isUlt then 2 else 1, if isUlt then 0 else 0.55)
		if isUlt then
			-- the ultimate: a glowing double border
			local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.new(1, 10, 1, 10),
				BackgroundTransparency = 1, ZIndex = 2 }, row)
			local gs = stroke(glow, accent, 5, 0.7)
			local inner = new("Frame", { Size = UDim2.new(1, -8, 1, -8), Position = UDim2.fromOffset(4, 4), BackgroundTransparency = 1, ZIndex = 3 }, row)
			stroke(inner, accent:Lerp(Color3.new(1, 1, 1), 0.3), 1, 0.4)
			new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) }) }, row)
			if ultGlowTween then ultGlowTween:Cancel() end
			ultGlowTween = TweenService:Create(gs, TweenInfo.new(1.1, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Transparency = 0.35 })
			ultGlowTween:Play()
			for _, c in ipairs({ 0, 1 }) do
				diamond(row, UDim2.fromScale(c, 0.5), 9, accent, true, 6)
			end
		end
		local tile = new("Frame", { Position = UDim2.fromOffset(10, 11), Size = UDim2.fromOffset(68, 68), BackgroundColor3 = Color3.fromRGB(18, 12, 12),
			BorderSizePixel = 0, ZIndex = 4 }, row)
		new("UICorner", { CornerRadius = UDim.new(0, 6) }, tile)
		stroke(tile, accent, 1, 0.35)
		if ab.icon and ab.icon ~= "" and not locked then
			local img = new("ImageLabel", { Size = UDim2.new(1, -4, 1, -4), Position = UDim2.fromOffset(2, 2), BackgroundTransparency = 1, Image = ab.icon,
				ScaleType = Enum.ScaleType.Crop, ZIndex = 5 }, tile)
			new("UICorner", { CornerRadius = UDim.new(0, 5) }, img)
		else
			text(tile, { Size = UDim2.fromScale(1, 1), Text = if locked then "?" else "◆", TextSize = 30, TextColor3 = accent, ZIndex = 5 })
		end
		local nameL = text(row, { Position = UDim2.fromOffset(92, 12), Size = UDim2.new(1, -140, 0, 28), Text = if locked then "???" else ab.name, TextSize = 22,
			TextScaled = true, TextColor3 = TEXT, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 5 })
		new("UITextSizeConstraint", { MaxTextSize = 22, MinTextSize = 12 }, nameL)
		text(row, { Position = UDim2.fromOffset(92, 42), Size = UDim2.new(1, -140, 0, 40), Text = if locked then "Locked." else (ab.summary or ab.description),
			TextSize = 15, FontFace = FONT_BODY, TextColor3 = TEXT, TextWrapped = true, TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top, TextTruncate = Enum.TextTruncate.AtEnd, ZIndex = 5 })
		local key = string.match(ab.tag or "", "%((%w+)%)") or "?"
		local badge = new("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.fromOffset(32, 32),
			BackgroundColor3 = INK, BackgroundTransparency = 0.2, BorderSizePixel = 0, ZIndex = 5 }, row)
		stroke(badge, if isUlt then accent else GOLD_DIM, 1, 0.1)
		text(badge, { Size = UDim2.fromScale(1, 1), Text = key, TextSize = 20, TextColor3 = TEXT, ZIndex = 6 })
		-- Hover lights the row; a click opens the ability's preview.
		row.MouseEnter:Connect(function()
			if isUlt then return end
			rowStroke.Color = accent
			rowStroke.Transparency = 0.1
		end)
		row.MouseLeave:Connect(function()
			if isUlt then return end
			rowStroke.Color = GOLD_DIM
			rowStroke.Transparency = 0.55
		end)
		row.MouseButton1Click:Connect(function()
			if locked then return end
			SoundManager.Play("Hover")
			AbilityPreview.Show(ab.name, ab.tag, ab.videoId or "", accent, ab.description, ab.icon, ab.summary)
		end)
	end

	local function updateCarouselUI(index: number, _isSlide: boolean?)
		local classId = ClassData.Order[index]
		local info = ClassData.GetClass(classId)
		if not info then return end

		-- The blond knight hair comes with the knight's armor.
		tintKnightHair(previewTarget(), if wearsArmor(classId) then classId else "")

		-- (locked: an unfinished kit, or a class not unlocked at the Altar yet)
		local locked = not ClassData.IsOwnedBy(player, classId)
		local accent = if locked then LOCKED_GREY else info.accentColor
		constellation.Show(classId, accent, locked)

		-- The hero on the pedestal, dressed as the class with its aura. (A
		-- failing preview must not stop the rest of the page updating.)
		local okLook, lookErr = pcall(applyClassCosmetics, classId)
		if not okLook then warn("[ClassSelection] preview failed for", classId, lookErr) end
		setSilhouette(previewTarget(), false)
		if locked then setSilhouette(previewTarget(), true) end

		local total = #ClassData.Order
		headerText.Text = `CHARACTER SELECTION  ◆  {index} / {total}`
		emblem.Image = emblemIcon(info)
		emblem.ImageColor3 = if locked then Color3.fromRGB(90, 90, 96) else Color3.new(1, 1, 1)
		emblemStroke.Color = accent
		tagline.Text = string.upper(info.tagline or info.title)
		nameLabel.Text = string.upper(info.name)
		local roles = info.roles or string.split(info.role, " / ")
		rolesLabel.Text = string.upper(table.concat(roles, "  •  "))
		descLabel.Text = if not locked then info.description
			elseif ClassData.IsPlayable(classId) then "Locked. Summon this class at the Altar of Souls."
			else "Coming soon."

		local ratings: any = info.ratings or {}
		for _, st in ipairs(STATS) do
			local r = statRows[st.key]
			local v = math.clamp(tonumber(ratings[st.key]) or 0, 0, 100)
			r.value.Text = `{percent(v)} / 100`
			tint(r.icon, accent:Lerp(GOLD, 0.45))
			r.fill.BackgroundColor3 = accent
			r.glow.BackgroundColor3 = accent
			TweenService:Create(r.fill, TweenInfo.new(0.45, Enum.EasingStyle.Quart), { Size = UDim2.new(v / 100, 0, 1, 0) }):Play()
			TweenService:Create(r.glow, TweenInfo.new(0.45, Enum.EasingStyle.Quart), { Size = UDim2.new(v / 100, 0, 0, 11) }):Play()
		end

		-- Skills: the three skills and the ultimate (not the basic attack or passive).
		for _, c in ipairs(skillList:GetChildren()) do
			if c:IsA("GuiObject") then c:Destroy() end
		end
		local shown = 0
		for _, ab in ipairs(info.abilities) do
			local tag = ab.tag or ""
			if string.find(tag, "M1", 1, true) or string.find(tag, "Passive", 1, true) then continue end
			shown += 1
			skillRow(ab, shown, accent, locked, string.find(tag, "Ultimate", 1, true) ~= nil)
		end

		-- Signature equipment: the weapon itself, or the class emblem.
		local eq = info.equipment
		eqName.Text = if eq then eq.name else ""
		eqDesc.Text = if eq then eq.description else ""
		local hasWeapon = showWeapon(eqView, classId, accent)
		eqView.Visible = hasWeapon
		eqGlyph.Visible = not hasWeapon
		eqGlyph.Image = emblemIcon(info)
		eqGlow.BackgroundColor3 = accent
		eqGlow.Visible = hasWeapon

		-- Centre: number and name, arrows, dots, the button.
		indexLabel.Text = string.format("%02d – %s", index, string.upper(info.name))
		accentGlow.BackgroundColor3 = accent
		selStroke.Color = accent:Lerp(GOLD, 0.35)
		selGlowStroke.Color = accent
		selInnerStroke.Color = accent:Lerp(GOLD, 0.5)
		for _, e in ipairs(selEnds) do
			local st = e:FindFirstChildOfClass("UIStroke")
			if st then st.Color = accent:Lerp(GOLD, 0.35) end
		end
		selectLabel.Text = if not locked then "SELECT CLASS"
			elseif ClassData.IsPlayable(classId) then "SUMMON AT THE ALTAR"
			else "LOCKED"
		selectLabel.TextColor3 = if locked then MUTED else TEXT
		for i, d in ipairs(dotFrames) do
			local active = i == index
			local dotLocked = not ClassData.IsOwnedBy(player, ClassData.Order[i])
			d.BackgroundColor3 = if active then accent elseif dotLocked then Color3.fromRGB(60, 50, 46) else GOLD_DIM
			TweenService:Create(d, UITheme.Tweens.Fast, { Size = if active then UDim2.fromOffset(11, 11) else UDim2.fromOffset(7, 7) }):Play()
		end
	end

	local function navigateCarousel(direction: number)
		if isTransitioning then return end
		isTransitioning = true
		local total = #ClassData.Order
		currentIndex = ((currentIndex - 1 + direction) % total) + 1
		SoundManager.PlaySelect()
		updateCarouselUI(currentIndex, true)
		task.wait(0.12)
		isTransitioning = false
	end

	local function arrowHover(b: TextButton, d: Frame)
		local st = d:FindFirstChildOfClass("UIStroke")
		b.MouseEnter:Connect(function()
			if st then st.Thickness = 2 end
			SoundManager.PlayHover()
		end)
		b.MouseLeave:Connect(function()
			if st then st.Thickness = 1 end
		end)
	end
	arrowHover(prevBtn, prevDiamond)
	arrowHover(nextBtn, nextDiamond)
	prevBtn.MouseButton1Click:Connect(function() navigateCarousel(-1) end)
	nextBtn.MouseButton1Click:Connect(function() navigateCarousel(1) end)

	for i, b in ipairs(dotButtons) do
		b.MouseButton1Click:Connect(function()
			if currentIndex ~= i and not isTransitioning then
				currentIndex = i
				SoundManager.PlaySelect()
				updateCarouselUI(currentIndex, true)
			end
		end)
	end

	local function confirm()
		local selectedClassId = ClassData.Order[currentIndex]
		if not ClassData.IsOwnedBy(player, selectedClassId) then return end
		SoundManager.PlayConfirm()
		stopPreviewAnimation()
		callbacks.onConfirmClass(selectedClassId)
	end
	selectBtn.MouseEnter:Connect(function()
		SoundManager.PlayHover()
		TweenService:Create(selScale, TweenInfo.new(0.12), { Scale = 1.04 }):Play()
		selGlowStroke.Transparency = 0.45
	end)
	selectBtn.MouseLeave:Connect(function()
		TweenService:Create(selScale, TweenInfo.new(0.12), { Scale = 1 }):Play()
		selGlowStroke.Transparency = 0.75
	end)
	selectBtn.MouseButton1Click:Connect(confirm)

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

	-- Keyboard: Left / Right to browse, Enter / Space to pick. (A / D are left
	-- alone: the camera is turned by dragging.)
	UserInputService.InputBegan:Connect(function(input, gameProcessed)
		if gameProcessed then return end
		if not container.Visible or container.GroupTransparency > 0.5 then return end
		if input.KeyCode == Enum.KeyCode.Left or input.KeyCode == Enum.KeyCode.DPadLeft or input.KeyCode == Enum.KeyCode.ButtonL1 then
			navigateCarousel(-1)
		elseif input.KeyCode == Enum.KeyCode.Right or input.KeyCode == Enum.KeyCode.DPadRight or input.KeyCode == Enum.KeyCode.ButtonR1 then
			navigateCarousel(1)
		elseif input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.Space or input.KeyCode == Enum.KeyCode.ButtonY or input.KeyCode == Enum.KeyCode.ButtonA then
			confirm()
		end
	end)

	-- Re-render when the screen opens; tidy up when it closes.
	container:GetPropertyChangedSignal("Visible"):Connect(function()
		if container.Visible then
			updateCarouselUI(currentIndex, false)
		else
			stopPreviewAnimation()
		end
	end)

	player.CharacterAdded:Connect(function()
		task.wait(0.2)
		if container.Visible then
			updateCarouselUI(currentIndex, false)
		end
	end)

	currentIndex = 1
	updateCarouselUI(currentIndex, false)
	-- A class unlocked (or the owned list arriving after load): redraw locks.
	player:GetAttributeChangedSignal("OwnedClasses"):Connect(function()
		if container.Visible then updateCarouselUI(currentIndex, false) end
	end)

	return container
end

return ClassSelectionScreen
