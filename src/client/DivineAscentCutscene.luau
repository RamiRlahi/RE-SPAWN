--!strict
-- DivineAscentCutscene.luau
-- Cinematic cutscene for the Cleric ultimate (Divine Ascent).
-- Cuts to a locked side-on hero shot of the caster (as the angel) and the
-- revived party below (reaching up to him) - recreating the Creation-of-Adam pose.
-- Replaces the old broken orbit camera that flew into unstreamed darkness.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local ContentProvider = game:GetService("ContentProvider")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DivineAscentCutscene = {}
local token = 0

-- ── Pose tuning (radians via math.rad) ───────────────────────────────────────
-- The caster reaches DOWN toward the party like the angel in the painting.
local ANGEL_SHOULDER = 120  -- arm swing: 90 = horizontal forward, >90 = pointing down-forward
local ANGEL_HEAD = 18       -- slight downward head tilt toward the party

-- ── Camera framing tuning ────────────────────────────────────────────────────
-- Authored Cleric ultimate pose animation (replaces the hand-coded reach pose).
local CLERIC_POSE_ID = "rbxassetid://82203027084666"
local clericAnimation = Instance.new("Animation")
clericAnimation.Name = "DivineAscentClericPose"
clericAnimation.AnimationId = CLERIC_POSE_ID
pcall(function()
	ContentProvider:PreloadAsync({ clericAnimation })
end)
local clericTrack = nil

local CAM_NEAR = 13   -- starting distance: zoomed IN on the tableau
local CAM_FAR = 30    -- ending distance: pull OUT to the wide framing
local CAM_HEIGHT = 5.5
local CAM_FOV = 50

local function getIso()
	local ok, iso = pcall(function()
		return require(script.Parent:WaitForChild("IsometricCamera"))
	end)
	if ok then return iso end
	return nil
end

local function makeFade()
	local pg = player:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("DivineAscentCutscene")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "DivineAscentCutscene"
		gui.ResetOnSpawn = false
		gui.IgnoreGuiInset = true
		gui.DisplayOrder = 1000
		gui.Parent = pg
		local f = Instance.new("Frame")
		f.Name = "Fade"
		f.Size = UDim2.fromScale(1, 1)
		f.BackgroundColor3 = Color3.new(0, 0, 0)
		f.BackgroundTransparency = 1
		f.BorderSizePixel = 0
		f.Parent = gui
	end
	return gui, gui:FindFirstChild("Fade")
end

-- Aim one arm so its hand points at a world target, by offsetting the joint's C0.
-- (A player's AnimationController constantly overwrites Motor6D.Transform, but it
--  never touches C0, so C0 is the reliable channel for a manual pose.)
local function aimArm(torso: BasePart, side: string, targetPos: Vector3)
	local arm = torso.Parent and torso.Parent:FindFirstChild(side .. " Arm")
	local joint = torso:FindFirstChild(side .. " Shoulder")
	if not (arm and arm:IsA("BasePart") and joint and joint:IsA("Motor6D")) then return end
	if joint:GetAttribute("BaseC0") == nil then
		joint:SetAttribute("BaseC0", joint.C0)
	end
	local dir = targetPos - arm.CFrame.Position
	if dir.Magnitude < 0.01 then return end
	local desired = CFrame.lookAt(arm.CFrame.Position, arm.CFrame.Position + dir.Unit) * CFrame.Angles(math.rad(90), 0, 0)
	joint.C0 = torso.CFrame:Inverse() * desired * joint.C1
end

local function restoreJoints(char: Model)
	local torso = char:FindFirstChild("Torso")
	if not torso then return end
	for _, side in ipairs({ "Right", "Left" }) do
		local joint = torso:FindFirstChild(side .. " Shoulder")
		if joint and joint:IsA("Motor6D") then
			local base = joint:GetAttribute("BaseC0")
			if base then joint.C0 = base end
		end
	end
	local nk = torso:FindFirstChild("Neck")
	if nk and nk:IsA("Motor6D") then
		local base = nk:GetAttribute("BaseC0")
		if base then nk.C0 = base end
	end
end

local function setCasterAnimate(char: Model, disabled: boolean)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if animator and disabled then
		for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
			track:Stop(0)
		end
	end
	-- The character's AnimationController writes Motor6D.Transform every frame,
	-- which would override our manual pose - so silence it for the cutscene.
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BaseScript") and d.Name == "AnimationController" then
			d.Disabled = disabled
		end
	end
end

-- Hold the caster in the authored ultimate pose (animation 82203027084666).
local function poseAngel(char: Model, targetPos: Vector3?)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	if not clericTrack then
		local anim = Instance.new("Animation")
		anim.AnimationId = CLERIC_POSE_ID
		local ok, t = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok or not t then return end
		clericTrack = t
		clericTrack.Looped = true
		clericTrack.Priority = Enum.AnimationPriority.Action4
	end
	if not clericTrack.IsPlaying then
		clericTrack:Play(0, 1, 1)
		clericTrack.TimePosition = 0
	end
end

-- Average world position of the live allies in Workspace.Allies.
local function allyCenter(): (Vector3?, number)
	local folder = Workspace:FindFirstChild("Allies")
	local sum, n = Vector3.zero, 0
	if folder then
		for _, a in ipairs(folder:GetChildren()) do
			if a:IsA("Model") and a:GetAttribute("IsAlly") == true then
				local r = a:FindFirstChild("HumanoidRootPart")
				if r and r:IsA("BasePart") then
					sum += r.Position
					n += 1
				end
			end
		end
	end
	if n > 0 then return sum / n, n end
	return nil, 0
end

-- Holy light bridging the caster's reaching hands to the revived party below.
-- Reuses the project's ReplicatedStorage.generalVFX.Holy particle VFX.
local function buildHolyBridge(casterChar: Model, allyCenter: Vector3)
	local holder = Instance.new("Folder")
	holder.Name = "DivineAscentHolyBridge"

	local core = Instance.new("Part")
	core.Name = "HolyCore"
	core.Anchored = true
	core.CanCollide = false
	core.CanQuery = false
	core.Material = Enum.Material.Neon
	core.Color = Color3.fromRGB(255, 250, 235)
	core.Shape = Enum.PartType.Ball
	core.Size = Vector3.new(1.4, 1.4, 1.4)
	core.Parent = holder

	local light = Instance.new("PointLight")
	light.Brightness = 5
	light.Range = 24
	light.Color = Color3.fromRGB(255, 240, 190)
	light.Shadows = false
	light.Parent = core

	local beam = Instance.new("Part")
	beam.Name = "LightBridge"
	beam.Anchored = true
	beam.CanCollide = false
	beam.CanQuery = false
	beam.Material = Enum.Material.Neon
	beam.Color = Color3.fromRGB(255, 250, 225)
	beam.Transparency = 0.2
	beam.Parent = holder

	local gv = ReplicatedStorage:FindFirstChild("generalVFX")
	local holySrc = gv and gv:FindFirstChild("Holy")
	if holySrc then
		local holy = holySrc:Clone()
		holy.Name = "HolyLight"
		if holy:IsA("BasePart") then
			holy.Anchored = true
			holy.CanCollide = false
			holy.CanQuery = false
			holy.Size = Vector3.new(5, 5, 5)
		end
		holy.Parent = holder
	end

	holder.Parent = Workspace

	local function tip(side: string): Vector3?
		local arm = casterChar:FindFirstChild(side .. " Arm")
		if arm and arm:IsA("BasePart") then
			return (arm.CFrame * CFrame.new(0, -1, 0)).Position
		end
		return nil
	end

	local function update()
		local hand = tip("Right") or tip("Left")
		local root = casterChar:FindFirstChild("HumanoidRootPart")
		if not hand and root and root:IsA("BasePart") then
			hand = root.Position
		end
		if not hand then return end
		local mid = (hand + allyCenter) * 0.5
		core.CFrame = CFrame.new(mid)
		local holy = holder:FindFirstChild("HolyLight")
		if holy and holy:IsA("BasePart") then
			holy.CFrame = CFrame.new(mid)
		end
		local diff = allyCenter - hand
		if diff.Magnitude > 0.1 then
			beam.Size = Vector3.new(0.7, diff.Magnitude, 0.7)
			beam.CFrame = CFrame.lookAt(mid, allyCenter) * CFrame.Angles(math.rad(90), 0, 0)
		end
	end

	return update, holder
end

function DivineAscentCutscene.Play(duration: number)
	duration = 2.0  -- fixed: the cutscene is a quick 2-second beat
	token += 1
	local my = token

	local char = player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local iso = getIso()
	local wasIso = iso and iso.IsActive and iso.IsActive()
	if wasIso then iso.Pause() end

	local _, fade = makeFade()
	if not fade then return end

	camera.CameraType = Enum.CameraType.Scriptable

	local function still(): boolean
		return token == my and char.Parent ~= nil
	end

	local function restore()
		if token ~= my then return end
		if wasIso and iso then
			iso.Resume(0.5)
		else
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then camera.CameraSubject = hum end
		end
	end

	task.spawn(function()
		-- Instant cut to black, then reveal.
		fade.BackgroundTransparency = 0

		-- INSTANT: lift the caster and hit the pose the moment R is pressed, BEFORE any
		-- waiting on the server round-trip (that wait used to delay the pose ~0.8s).
		-- The caster is the LOCAL player: the server's lift never applies on our own
		-- client (we own our own character), so lift it locally for a coherent tableau.
		local LIFT = 53
		local returnCF = root.CFrame
		local liftedCF = CFrame.new(root.Position + Vector3.new(0, LIFT, 0)) * (root.CFrame - root.CFrame.Position)
		local wasAnchored = root.Anchored
		root.Anchored = true
		root.CFrame = liftedCF
		setCasterAnimate(char, true)
		poseAngel(char, nil)

		-- Then wait briefly for the revived party to replicate (used only for the
		-- camera framing below, not for the pose).
		local ac = allyCenter()
		local waited = 0
		while not ac and waited < 0.8 do
			task.wait(0.1)
			waited += 0.1
			if not still() then return end
			ac = allyCenter()
		end

		local casterPos = liftedCF.Position
		local center = ac or (casterPos - root.CFrame.LookVector * 10)
		local axis = Vector3.new(casterPos.X - center.X, 0, casterPos.Z - center.Z)
		if axis.Magnitude < 1 then axis = root.CFrame.LookVector * -1 end
		axis = axis.Unit
		local side = Vector3.new(-axis.Z, 0, axis.X)
		local mid = (casterPos + center) * 0.5

		local nearPos = mid + side * CAM_NEAR + Vector3.new(0, CAM_HEIGHT, 0)
		local farPos = mid + side * CAM_FAR + Vector3.new(0, CAM_HEIGHT - 1, 0)
		local focus = mid + Vector3.new(0, 1.5, 0)

		camera.CFrame = CFrame.lookAt(nearPos, focus)
		camera.FieldOfView = CAM_FOV

		-- (The blinding holy bridge is NOT shown during the cutscene - it is
		--  spawned once AFTER the scene resets to normal, below.)

		-- Reveal from black.
		TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()

		local t0 = os.clock()
		local holdDur = math.max(0.6, duration - 0.7)
		while still() and (os.clock() - t0) < holdDur do
			local a = math.clamp((os.clock() - t0) / holdDur, 0, 1)
			local p = nearPos:Lerp(farPos, a)
			camera.CFrame = CFrame.lookAt(p, focus)
			poseAngel(char, center)
			RunService.RenderStepped:Wait()
		end
		if not still() then return end

		if clericTrack then
			pcall(function()
				clericTrack:Stop(0.2)
			end)
			clericTrack = nil
		end
		restoreJoints(char)
		setCasterAnimate(char, false)
		if root then
			root.CFrame = returnCF
			root.AssemblyLinearVelocity = Vector3.zero
			root.AssemblyAngularVelocity = Vector3.zero
			root.Anchored = wasAnchored
		end

		-- Fade back out and hand the camera back.
		TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 0 }):Play()
		task.wait(0.4)
		restore()
		TweenService:Create(fade, TweenInfo.new(0.35), { BackgroundTransparency = 1 }):Play()

	end)
end

function DivineAscentCutscene.Stop()
	token += 1
end

return DivineAscentCutscene
