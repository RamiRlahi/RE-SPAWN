local SoundService = game:GetService("SoundService")
local Players = game:GetService("Players")

local SoundManager = {}

-- Audio asset IDs (configure with your custom asset IDs when ready)
local Sounds = {
	Hover = "",
	Click = "",
	Select = "",
	Confirm = "",
	Close = "",
	Error = "",
}

local createdSounds: { [string]: Sound } = {}

local function getSound(name: string): Sound?
	local assetId = Sounds[name]
	if not assetId or assetId == "" then return nil end

	if not createdSounds[name] then
		pcall(function()
			local sound = Instance.new("Sound")
			sound.Name = `UISound_{name}`
			sound.SoundId = assetId
			sound.Volume = 0.5
			local player = Players.LocalPlayer
			if player and player:FindFirstChild("PlayerGui") then
				sound.Parent = player.PlayerGui
			else
				sound.Parent = SoundService
			end
			createdSounds[name] = sound
		end)
	end

	return createdSounds[name]
end

function SoundManager.Play(name: string, volumeScale: number?)
	pcall(function()
		local sound = getSound(name)
		if sound and sound.SoundId ~= "" then
			sound.Volume = (volumeScale or 1) * 0.4
			sound:Play()
		end
	end)
end

function SoundManager.PlayHover()
	SoundManager.Play("Hover", 0.3)
end

function SoundManager.PlayClick()
	SoundManager.Play("Click", 0.6)
end

function SoundManager.PlaySelect()
	SoundManager.Play("Select", 0.8)
end

function SoundManager.PlayConfirm()
	SoundManager.Play("Confirm", 1.0)
end

function SoundManager.PlayClose()
	SoundManager.Play("Close", 0.5)
end

return SoundManager
