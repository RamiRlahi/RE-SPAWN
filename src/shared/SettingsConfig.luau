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
	autoFire: boolean,      -- ranged classes' basic attack shoots the nearest enemy in the room by itself
	keybinds: { [string]: string }, -- actionName -> Enum.KeyCode name or UserInputType name
}

local DefaultKeybinds: { KeybindEntry } = {
	{ action = "PrimaryAttack", displayName = "Primary Attack", category = "Combat", defaultKey = "MouseButton1" },
	{ action = "Skill1", displayName = "Skill 1 (Spin)", category = "Combat", defaultKey = "E" },
	{ action = "Skill2", displayName = "Skill 2 (Flame Slash)", category = "Combat", defaultKey = "F" },
	{ action = "Skill3", displayName = "Skill 3 (Dash)", category = "Combat", defaultKey = "Q" },
	{ action = "Ultimate", displayName = "Ultimate Ability", category = "Combat", defaultKey = "R" },
	{ action = "Sprint", displayName = "Sprint", category = "Movement", defaultKey = "LeftShift" },
	{ action = "Dash", displayName = "Dash", category = "Movement", defaultKey = "MouseButton2" },
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
	teammateCinematics = false, -- (off by default: your camera stays on you)
	classicCamera = false,
	autoFire = true,
	keybinds = {
		["PrimaryAttack"] = "MouseButton1",
		["Skill1"] = "E",
		["Skill2"] = "F",
		["Skill3"] = "Q",
		["Ultimate"] = "R",
		["Sprint"] = "LeftShift",
		["Dash"] = "MouseButton2",
		["Mount"] = "B",
		["Interact"] = "V",
		["OpenMenu"] = "M",
	},
}

local SettingsConfig = {}
SettingsConfig.DefaultSettings = DefaultSettings
SettingsConfig.DefaultKeybinds = DefaultKeybinds

-- A controller's buttons for the same actions (fixed: not rebindable): the
-- four face buttons are the skills; RT attacks (and, with a prompt showing
-- close by, uses it instead: GamepadSupport), RB dodges, LT sprints, LB
-- jumps (moved off A: GamepadSupport).
SettingsConfig.GamepadBinds = {
	PrimaryAttack = "ButtonR2",
	Skill1 = "ButtonX",
	Skill2 = "ButtonY",
	Skill3 = "ButtonB",
	Ultimate = "ButtonA",
	Sprint = "ButtonL2",
	Dash = "ButtonR1",
	Jump = "ButtonL1",
	Mount = "DPadUp",
	Interact = "ButtonR2",
	OpenMenu = "ButtonSelect",
} :: { [string]: string }
-- (the rest of a controller's layout, for the screens that ask)
SettingsConfig.GamepadExtra = {
	Tomes = "DPadDown",   -- the tome list / the full map (Tab)
	Emotes = "DPadLeft",  -- the emote wheel (T)
	Gear = "DPadRight",   -- the Forgotten Isle's gear panel (G)
	Back = "ButtonB",     -- closes a panel (Escape)
	Confirm = "ButtonA",  -- skips a cinematic, picks on the class screen (Enter)
}

local GAMEPADS: { [Enum.UserInputType]: boolean } = {}
for i = 1, 8 do GAMEPADS[(Enum.UserInputType :: any)["Gamepad" .. i]] = true end
function SettingsConfig.IsGamepad(input: InputObject): boolean
	return GAMEPADS[input.UserInputType] == true
end

-- Does `input` press `action`: its bound key (`keyName`: a KeyCode or a
-- UserInputType's name), or its controller button?
function SettingsConfig.Matches(input: InputObject, keyName: any, action: string): boolean
	if GAMEPADS[input.UserInputType] then
		local pad = SettingsConfig.GamepadBinds[action] or SettingsConfig.GamepadExtra[action]
		return pad ~= nil and input.KeyCode.Name == pad
	end
	if typeof(keyName) ~= "string" or keyName == "" or keyName == "None" then return false end
	if input.UserInputType == Enum.UserInputType.Keyboard then return input.KeyCode.Name == keyName end
	return input.UserInputType.Name == keyName
end

-- Is `action`'s controller button held down right now (any controller)?
function SettingsConfig.GamepadDown(action: string): boolean
	local pad = SettingsConfig.GamepadBinds[action] or SettingsConfig.GamepadExtra[action]
	if not pad then return false end
	local UserInputService = game:GetService("UserInputService")
	local key = (Enum.KeyCode :: any)[pad]
	for gp in pairs(GAMEPADS) do
		if UserInputService:GetGamepadConnected(gp) and UserInputService:IsGamepadButtonDown(gp, key) then return true end
	end
	return false
end

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
		autoFire = DefaultSettings.autoFire,
		keybinds = {},
	}
	for action, key in pairs(DefaultSettings.keybinds) do
		clone.keybinds[action] = key
	end
	return clone
end

-- A settings table from anywhere (the client, an old save) made safe: only
-- the known settings, each of the right type (volumes kept to 0..1), keybinds
-- only for known actions and plain key names; anything missing or wrong is
-- the default.
function SettingsConfig.Sanitize(input: any): PlayerSettings
	local out = SettingsConfig.CloneDefaultSettings()
	if typeof(input) ~= "table" then return out end
	for k, def in pairs(DefaultSettings :: any) do
		if k == "keybinds" then continue end
		local v = input[k]
		if typeof(v) == typeof(def) then
			if typeof(v) == "number" then
				if v ~= v then continue end -- (NaN)
				v = math.clamp(v, 0, 1)
			end
			(out :: any)[k] = v
		end
	end
	if typeof(input.keybinds) == "table" then
		for action in pairs(DefaultSettings.keybinds) do
			local key = input.keybinds[action]
			if typeof(key) == "string" and #key <= 40 and string.match(key, "^[%w]+$") then
				out.keybinds[action] = key
			end
		end
	end
	return out
end

return SettingsConfig
