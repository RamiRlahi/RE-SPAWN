--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- AtmosphereManager.luau
-- Manages grim, moody medieval dungeon lighting, atmosphere, and player torch lights.
-- ─────────────────────────────────────────────────────────────────────────────

local Lighting   = game:GetService("Lighting")
local Workspace  = game:GetService("Workspace")

local AtmosphereManager = {}

-- ── 1. Lighting & Atmosphere Setup ───────────────────────────────────────────

function AtmosphereManager.ApplyLobbyLighting()
	-- Configure bright daytime lobby / sanctuary lighting
	Lighting.Ambient = Color3.fromRGB(180, 180, 190)
	Lighting.OutdoorAmbient = Color3.fromRGB(150, 150, 160)
	Lighting.Brightness = 2.0
	Lighting.ClockTime = 14 -- Daytime illumination
	Lighting.GlobalShadows = true

	pcall(function()
		Lighting.EnvironmentDiffuseScale = 1.0
		Lighting.EnvironmentSpecularScale = 1.0
	end)

	local colorCorr = Lighting:FindFirstChild("DungeonColorCorrection") :: ColorCorrectionEffect?
	if colorCorr then
		colorCorr.Enabled = false
	end

	local bloom = Lighting:FindFirstChild("DungeonTorchBloom") :: BloomEffect?
	if bloom then
		bloom.Enabled = false
	end

	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if atmosphere then
		atmosphere.Density = 0.1
		atmosphere.Color = Color3.fromRGB(199, 217, 230)
		atmosphere.Decay = Color3.fromRGB(106, 126, 143)
		atmosphere.Haze = 0
	end

	print("[AtmosphereManager] Lobby / Sanctuary bright lighting applied.")
end

function AtmosphereManager.ApplyDungeonLighting()
	-- Configure global dim indoor lighting (dim & visible, not pitch black)
	Lighting.Ambient = Color3.fromRGB(52, 48, 62)          -- Dim cool indoor shadows (visible details)
	Lighting.OutdoorAmbient = Color3.fromRGB(42, 38, 50)    -- Visible perimeter ambient
	Lighting.Brightness = 0.75                              -- Atmospheric dim global illumination
	Lighting.ClockTime = 0                                  -- Midnight darkness baseline
	Lighting.GlobalShadows = true

	pcall(function()
		Lighting.EnvironmentDiffuseScale = 0.25
		Lighting.EnvironmentSpecularScale = 0.2
	end)

	pcall(function()
		Lighting.Technology = Enum.Technology.ShadowMap
	end)

	-- 1. ColorCorrection Effect
	local colorCorr = Lighting:FindFirstChild("DungeonColorCorrection") :: ColorCorrectionEffect?
	if not colorCorr then
		colorCorr = Instance.new("ColorCorrectionEffect")
		colorCorr.Name = "DungeonColorCorrection"
		colorCorr.Parent = Lighting
	end
	colorCorr.Brightness = 0.02
	colorCorr.Contrast = 0.12
	colorCorr.Saturation = -0.04
	colorCorr.TintColor = Color3.fromRGB(252, 245, 235)
	colorCorr.Enabled = true

	-- 2. Warm Bloom Effect
	local bloom = Lighting:FindFirstChild("DungeonTorchBloom") :: BloomEffect?
	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "DungeonTorchBloom"
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.45
	bloom.Size = 24
	bloom.Threshold = 0.75
	bloom.Enabled = true

	-- 3. Atmospheric Dungeon Fog
	local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.25
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(28, 32, 42)
	atmosphere.Decay = Color3.fromRGB(18, 22, 30)
	atmosphere.Haze = 0.4
	atmosphere.Glare = 0

	print("[AtmosphereManager] Dungeon atmosphere & lighting applied successfully.")
end

-- ── 2. Player Torch Light Attachment ─────────────────────────────────────────

function AtmosphereManager.AttachTorchLight(character: Model)
	local rootPart = (character:FindFirstChild("HumanoidRootPart") or character.PrimaryPart) :: BasePart?
	if not rootPart then
		-- Fast asynchronous check if rootPart hasn't loaded yet
		task.spawn(function()
			local rp = character:WaitForChild("HumanoidRootPart", 3) :: BasePart?
			if rp then
				AtmosphereManager.AttachTorchLight(character)
			end
		end)
		return
	end

	-- Do not re-attach if light is already attached
	if rootPart:FindFirstChild("PlayerTorchLight") then
		return
	end

	-- 1. Create Warm PointLight (Dynamic Torch)
	local torchLight = Instance.new("PointLight")
	torchLight.Name = "PlayerTorchLight"
	torchLight.Color = Color3.fromRGB(255, 175, 75) -- Warm flame orange-gold
	torchLight.Range = 32                           -- Illuminated radius (studs)
	torchLight.Brightness = 2.4                     -- Brightness intensity
	torchLight.Shadows = true                       -- Dynamic shadows from walls/pillars
	torchLight.Parent = rootPart

	-- 2. Create Subtle Floating Torch Embers Attachment
	if not rootPart:FindFirstChild("TorchEmbersAttachment") then
		local att = Instance.new("Attachment")
		att.Name = "TorchEmbersAttachment"
		att.Position = Vector3.new(0.6, 1.2, -0.4) -- Off to upper-right torso like held torch
		att.Parent = rootPart

		local embers = Instance.new("ParticleEmitter")
		embers.Name = "TorchEmbers"
		embers.Texture = "rbxassetid://258129532" -- Sparkle/Ember particle
		embers.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 200, 100)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(255, 120, 30)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(180, 40, 10)),
		})
		embers.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.2),
			NumberSequenceKeypoint.new(0.8, 0.5),
			NumberSequenceKeypoint.new(1, 1),
		})
		embers.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 0.05),
		})
		embers.Lifetime = NumberRange.new(0.8, 1.4)
		embers.Rate = 6
		embers.Speed = NumberRange.new(1.0, 2.5)
		embers.SpreadAngle = Vector2.new(25, 25)
		embers.VelocityInheritance = 0.2
		embers.Parent = att
	end

	print(`[AtmosphereManager] Torch light attached to character: {character.Name}`)
end

return AtmosphereManager
