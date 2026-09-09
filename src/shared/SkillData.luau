--[[
	SkillData.luau
	Shared configuration for class skills, stats, cooldowns, and visual parameters.
--]]

export type SkillConfig = {
	name: string,
	slot: number,
	keybind: string,
	cooldown: number,
	damage: number,
	description: string,
	animationId: string?,
	range: number?,
	angle: number?,
	projectileSpeed: number?,
	dashDistance: number?,
	dashSpeed: number?,
	duration: number?,
}

export type ClassSkills = {
	[number]: SkillConfig
}

local SkillData: { [string]: ClassSkills } = {
	heavy_knight = {
		[1] = {
			name = "Spin Attack",
			slot = 1,
			keybind = "E",
			cooldown = 8.0,
			damage = 16,
			duration = 5.0,
			range = 14,
			description = "A continuous spinning whirlwind attack for 5 seconds, slicing all nearby enemies.",
			animationId = "rbxassetid://94745840711885",
		},
		[2] = {
			name = "Missile Barrage",
			slot = 2,
			keybind = "F",
			cooldown = 12.0,
			damage = 35,
			duration = 8.0,
			description = "Buff: For 8 seconds, each attack launches a guided missile from your back that curves and homes in on nearby foes.",
		},
		[3] = {
			name = "Phoenix Dash",
			slot = 3,
			keybind = "Q",
			cooldown = 7.5,
			damage = 25,
			dashDistance = 24,
			dashSpeed = 80,
			range = 8,
			description = "Surge forward in a roaring whirlwind of flames, scorching foes.",
			animationId = "rbxassetid://139832137467263",
		},
		[4] = {
			name = "Infernal Wrath",
			slot = 4,
			keybind = "R",
			cooldown = 30.0,
			damage = 100,
			description = "Ultimate: Empower your sword in roaring flames and slam down a massive impact slash that shatters the earth into a rock crater.",
			animationId = "rbxassetid://84579017139529",
			slashAnimationId = "rbxassetid://108875775887071",
		},
	},
	default = {
		[1] = {
			name = "Spin Attack",
			slot = 1,
			keybind = "E",
			cooldown = 8.0,
			damage = 16,
			duration = 5.0,
			range = 14,
			description = "A continuous spinning whirlwind attack for 5 seconds, slicing all nearby enemies.",
			animationId = "rbxassetid://94745840711885",
		},
		[2] = {
			name = "Missile Barrage",
			slot = 2,
			keybind = "F",
			cooldown = 12.0,
			damage = 35,
			duration = 8.0,
			description = "Buff: For 8 seconds, each attack launches a guided missile from your back that curves and homes in on nearby foes.",
		},
		[3] = {
			name = "Phoenix Dash",
			slot = 3,
			keybind = "Q",
			cooldown = 7.5,
			damage = 25,
			dashDistance = 24,
			dashSpeed = 80,
			range = 8,
			description = "Surge forward in a roaring whirlwind of flames, scorching foes.",
			animationId = "rbxassetid://139832137467263",
		},
		[4] = {
			name = "Infernal Wrath",
			slot = 4,
			keybind = "R",
			cooldown = 30.0,
			damage = 100,
			description = "Ultimate: Empower your sword in roaring flames and slam down a massive impact slash that shatters the earth into a rock crater.",
			animationId = "rbxassetid://86943794416151",
		},
	},
}

local SkillModule = {}

function SkillModule.GetSkills(classId: string): ClassSkills
	return SkillData[classId] or SkillData.default
end

function SkillModule.GetSkill(classId: string, skillIndex: number): SkillConfig?
	local skills = SkillModule.GetSkills(classId)
	return skills[skillIndex]
end

return SkillModule
