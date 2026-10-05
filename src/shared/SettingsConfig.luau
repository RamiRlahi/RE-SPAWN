export type KeybindEntry = {
	action: string,
	displayName: string,
	category: string,
	defaultKey: string, -- e.g. "MouseButton1", "E", "Q", "F"
}

export type PlayerSettings = {
	masterVolume: number, -- 0 to 1
	musicVolume: number,  -- 0 to 1
	sfxVolume: number,    -- 0 to 1
	cameraShake: boolean,
	lowDetailVFX: boolean,
	damageNumbers: boolean,
	toggleSprint: boolean, -- sprint key toggles sprinting on/off (instead of hold)
	shadows: boolean,      -- world shadows (Lighting.GlobalShadows, on this client)
	bloom: boolean,        -- bloom / sun-ray glow post effects
	teammateCinematics: boolean, -- play teammates' ultimate cutscenes on your screen
	classicCamera: boolean, -- a normal third-person camera in runs instead of the top-down one
	keybinds: { [string]: string }, -- actionName -> Enum.KeyCode name or UserInputType name
}

local DefaultKeybinds: { KeybindEntry } = {
	{ action = "PrimaryAttack", displayName = "Primary Attack", category = "Combat", defaultKey = "MouseButton1" },
	{ action = "Skill1", displayName = "Skill 1 (Spin)", category = "Combat", defaultKey = "E" },
	{ action = "Skill2", displayName = "Skill 2 (Flame Slash)", category = "Combat", defaultKey = "F" },
	{ action = "Skill3", displayName = "Skill 3 (Dash)", category = "Combat", defaultKey = "Q" },
	{ action = "Ultimate", displayName = "Ultimate Ability", category = "Combat", defaultKey = "R" },
	{ action = "Sprint", displayName = "Sprint", category = "Movement", defaultKey = "LeftShift" },
	{ action = "Mount", displayName = "Mount", category = "Movement", defaultKey = "B" },
	{ action = "Interact", displayName = "Interact", category = "General", defaultKey = "V" },
	{ action = "OpenMenu", displayName = "Toggle Menu", category = "General", defaultKey = "M" },
}

local DefaultSettings: PlayerSettings = {
	masterVolume = 0.8,
	musicVolume = 0.6,
	sfxVolume = 0.9,
	cameraShake = true,
	lowDetailVFX = false,
	damageNumbers = true,
	toggleSprint = true,
	shadows = true,
	bloom = true,
	teammateCinematics = true,
	classicCamera = false,
	keybinds = {
		["PrimaryAttack"] = "MouseButton1",
		["Skill1"] = "E",
		["Skill2"] = "F",
		["Skill3"] = "Q",
		["Ultimate"] = "R",
		["Sprint"] = "LeftShift",
		["Mount"] = "B",
		["Interact"] = "V",
		["OpenMenu"] = "M",
	},
}

local SettingsConfig = {}
SettingsConfig.DefaultSettings = DefaultSettings
SettingsConfig.DefaultKeybinds = DefaultKeybinds

function SettingsConfig.CloneDefaultSettings(): PlayerSettings
	local clone: PlayerSettings = {
		masterVolume = DefaultSettings.masterVolume,
		musicVolume = DefaultSettings.musicVolume,
		sfxVolume = DefaultSettings.sfxVolume,
		cameraShake = DefaultSettings.cameraShake,
		lowDetailVFX = DefaultSettings.lowDetailVFX,
		damageNumbers = DefaultSettings.damageNumbers,
		toggleSprint = DefaultSettings.toggleSprint,
		shadows = DefaultSettings.shadows,
		bloom = DefaultSettings.bloom,
		teammateCinematics = DefaultSettings.teammateCinematics,
		classicCamera = DefaultSettings.classicCamera,
		keybinds = {},
	}
	for action, key in pairs(DefaultSettings.keybinds) do
		clone.keybinds[action] = key
	end
	return clone
end

return SettingsConfig
