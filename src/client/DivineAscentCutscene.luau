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
DivineAscentCutscene.LIGHT_AT = 1.9
DivineAscentCutscene.REVIVE_AT = 3.7

local token = 0

-- ── Lighting: warm and shadow-free for the cinematic, restored afterwards ──
local HOLY_LIGHTING = {
	GlobalShadows = false,
	Ambient = Color3.fromRGB(125, 112, 95),
	OutdoorAmbient = Color3.fromRGB(140, 128, 110),
	EnvironmentDiffuseScale = 0.8,
}
local savedLighting: { [string]: any }? = nil
local savedGrade: boolean? = nil

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

function DivineAscentCutscene.Play(duration: number, aimDir: Vector3?)
	duration = math.max(duration or 5.5, 4)
	token += 1
	local my = token

	local char = player.Character
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
				-- PRAYER: low, frontal, a touch off-centre; slow push toward the bowed head.
				local k = smooth(t / LIGHT_AT)
				camPos = (base + fwd * 7.5 - right * 1.2 + Vector3.new(0, 0.2, 0)):Lerp(base + fwd * 4.6 - right * 0.8 + Vector3.new(0, 0.5, 0), k)
				lookAt = base + Vector3.new(0, 0.3 + 0.2 * k, 0)
				fov = 50 - 8 * k
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
