--!strict
-- DivineAscentCutscene.luau
-- Camera cinematic for the Cleric ultimate (Divine Ascent), played for the caster.
-- Staged on the ground where the ult was cast, in three hard-cut shots:
--
--   PRAYER   0 → LIGHT_AT          Low frontal shot, slow push-in: the Cleric kneels in prayer.
--   LIGHT    LIGHT_AT → REVIVE_AT  Behind and to the right, craning up: a shaft of holy
--                                  light breaks from above onto the Cleric.
--   REVIVAL  REVIVE_AT → end       Wide, looking past the Cleric: the fallen allies behind
--                                  them rise, each in a beam of light.
--
-- The kneel pose and the light VFX are played for everyone by SkillController
-- (CastPoses.clericPrayer / ClericFlair.prayerLight); this module only drives the
-- caster's camera and a warm, shadow-free lighting preset.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local DivineAscentCutscene = {}

-- Shot timings (seconds from cast). ClericFlair, CastPoses and the server's
-- reviveTime follow the same beats.
DivineAscentCutscene.LIGHT_AT = 0.55
DivineAscentCutscene.REVIVE_AT = 1.2

local token = 0

-- ── Lighting: warm and shadow-free for the cinematic, restored afterwards ──
-- Moody and dim so the god rays and the rim light carry the frame (like the
-- reference: dark surroundings, warm light breaking from above).
local HOLY_LIGHTING = {
	GlobalShadows = false,
	Ambient = Color3.fromRGB(62, 56, 52),
	OutdoorAmbient = Color3.fromRGB(78, 70, 64),
	EnvironmentDiffuseScale = 0.5,
}
local savedLighting: { [string]: any }? = nil
local savedGrade: boolean? = nil
local savedBloom: { [string]: any }? = nil
local effects: { Instance } = {}

local function applyLighting()
	if savedLighting then return end
	local saved = {}
	for k, v in pairs(HOLY_LIGHTING) do
		local ok, cur = pcall(function() return (Lighting :: any)[k] end)
		if ok then saved[k] = cur end
		pcall(function() (Lighting :: any)[k] = v end)
	end
	savedLighting = saved
	local grade = Lighting:FindFirstChild("DungeonColorCorrection") :: ColorCorrectionEffect?
	if grade then
		savedGrade = grade.Enabled
		grade.Enabled = false
	end
	-- Warm, contrasty grade and a strong soft bloom for the glowing light.
	local cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "AscentGrade"
	cc.TintColor = Color3.fromRGB(255, 238, 214)
	cc.Contrast = 0.22
	cc.Saturation = -0.12
	cc.Parent = Lighting
	table.insert(effects, cc)
	local bloom = Lighting:FindFirstChild("DungeonTorchBloom") :: BloomEffect?
	if bloom then
		savedBloom = { Enabled = bloom.Enabled, Intensity = bloom.Intensity, Size = bloom.Size, Threshold = bloom.Threshold }
		bloom.Enabled, bloom.Intensity, bloom.Size, bloom.Threshold = true, 0.9, 32, 0.78
	else
		local b = Instance.new("BloomEffect")
		b.Name = "AscentBloom"
		b.Intensity, b.Size, b.Threshold = 0.9, 32, 0.78
		b.Parent = Lighting
		table.insert(effects, b)
	end
	local dof = Instance.new("DepthOfFieldEffect")
	dof.Name = "AscentDOF"
	dof.FocusDistance = 6
	dof.InFocusRadius = 4
	dof.NearIntensity = 0.15
	dof.FarIntensity = 0.4
	dof.Parent = Lighting
	table.insert(effects, dof)
end

local function restoreLighting()
	if savedLighting then
		for k, v in pairs(savedLighting) do
			pcall(function() (Lighting :: any)[k] = v end)
		end
		savedLighting = nil
	end
	if savedGrade ~= nil then
		local grade = Lighting:FindFirstChild("DungeonColorCorrection") :: ColorCorrectionEffect?
		if grade then grade.Enabled = savedGrade end
		savedGrade = nil
	end
	if savedBloom then
		local bloom = Lighting:FindFirstChild("DungeonTorchBloom") :: BloomEffect?
		if bloom then
			for k, v in pairs(savedBloom) do (bloom :: any)[k] = v end
		end
		savedBloom = nil
	end
	for _, e in ipairs(effects) do
		e:Destroy()
	end
	table.clear(effects)
end

local function getIso()
	local ok, iso = pcall(function()
		return require(script.Parent:WaitForChild("IsometricCamera"))
	end)
	if ok then return iso end
	return nil
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

-- `who` defaults to your own character (others' casts play it on theirs).
function DivineAscentCutscene.Play(duration: number, aimDir: Vector3?, who: Model?)
	duration = math.max(duration or 2, 1.5)
	token += 1
	local my = token

	local char = who or player.Character
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end

	local iso = getIso()
	local wasIso = iso and iso.IsActive and iso.IsActive()
	if wasIso then iso.Pause() end
	camera.CameraType = Enum.CameraType.Scriptable
	applyLighting()
	char:SetAttribute("HideHalo", true)

	local function still(): boolean
		return token == my and char.Parent ~= nil and root.Parent ~= nil
	end

	local function finish()
		char:SetAttribute("HideHalo", false)
		if token ~= my then return end
		restoreLighting()
		if wasIso and iso then
			iso.Resume(0.5)
		else
			camera.CameraType = Enum.CameraType.Custom
			camera.FieldOfView = 70
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum then camera.CameraSubject = hum end
		end
	end

	-- Shot geometry is fixed at cast time; the Cleric is rooted while kneeling.
	local fwd = aimDir and Vector3.new(aimDir.X, 0, aimDir.Z) or Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if fwd.Magnitude < 0.001 then fwd = Vector3.new(0, 0, -1) end
	fwd = fwd.Unit
	local right = fwd:Cross(Vector3.yAxis).Unit
	local base = root.Position
	local LIGHT_AT = DivineAscentCutscene.LIGHT_AT
	local REVIVE_AT = DivineAscentCutscene.REVIVE_AT

	task.spawn(function()
		local t0 = os.clock()
		while still() do
			local t = os.clock() - t0
			if t >= duration then break end
			local camPos: Vector3, lookAt: Vector3, fov: number

			if t < LIGHT_AT then
				-- PRAYER: near the floor, front-left, tilted up past the bowed head into
				-- the god rays breaking from above; a slow creep in.
				local k = smooth(t / LIGHT_AT)
				camPos = (base + fwd * 6.5 - right * 3 + Vector3.new(0, -2, 0)):Lerp(base + fwd * 5.2 - right * 2.4 + Vector3.new(0, -1.8, 0), k)
				lookAt = base - fwd * 1 + Vector3.new(0, 2.2, 0)
				fov = 64 - 4 * k
			elseif t < REVIVE_AT then
				-- LIGHT: behind and to the right, craning up as the shaft of light lands.
				local k = smooth((t - LIGHT_AT) / (REVIVE_AT - LIGHT_AT))
				camPos = (base - fwd * 6 + right * 4.5 + Vector3.new(0, 1.8, 0)):Lerp(base - fwd * 7.5 + right * 5.5 + Vector3.new(0, 5, 0), k)
				lookAt = base + Vector3.new(0, 1.2 + 1.6 * k, 0)
				fov = 56
			else
				-- REVIVAL: wide from the front-left, looking past the Cleric to the
				-- allies rising behind them; slow pull-back.
				local k = smooth((t - REVIVE_AT) / math.max(duration - REVIVE_AT, 0.1))
				camPos = (base + fwd * 9 - right * 5 + Vector3.new(0, 5, 0)):Lerp(base + fwd * 12 - right * 7 + Vector3.new(0, 7.5, 0), k)
				lookAt = base - fwd * 4 + Vector3.new(0, 1.5, 0)
				fov = 58 + 4 * k
			end

			camera.CFrame = CFrame.lookAt(camPos, lookAt)
			camera.FieldOfView = fov
			-- Keep the Cleric (and, in the wide shot, the allies) in focus.
			local dofFx = Lighting:FindFirstChild("AscentDOF") :: DepthOfFieldEffect?
			if dofFx then
				local d = (camPos - base).Magnitude
				dofFx.FocusDistance = d
				dofFx.InFocusRadius = math.max(4, d * 0.6)
			end
			RunService.RenderStepped:Wait()
		end
		finish()
	end)
end

function DivineAscentCutscene.Stop()
	token += 1
	restoreLighting()
end

return DivineAscentCutscene
