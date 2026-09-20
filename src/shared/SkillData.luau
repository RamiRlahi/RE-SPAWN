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
	slashAnimationId: string?,
	range: number?,
	angle: number?,
	projectileSpeed: number?,
	dashDistance: number?,
	dashSpeed: number?,
	duration: number?,
	width: number?,
}

export type ClassSkills = {
	[number]: SkillConfig
}

local SkillData: { [string]: ClassSkills } = {
	ranger = {
		[1] = {
			name = "Verdant Slash",
			slot = 1,
			keybind = "E",
			cooldown = 5.0,
			damage = 38,
			range = 32,
			dashDistance = 32,
			width = 6.0,
			description = "Instantly dash forward, piercing all enemies in your path and leaving a lingering nature energy slash.",
			animationId = "rbxassetid://139832137467263",
		},
		[2] = {
			name = "Entangling Arrow",
			slot = 2,
			keybind = "F",
			cooldown = 10.0,
			damage = 30,
			range = 44,
			duration = 2.6,
			description = "Fire a special arrow that erupts into grasping vines, rooting all enemies in a small area.",
		},
		[3] = {
			name = "Seeker Barrage",
			slot = 3,
			keybind = "Q",
			cooldown = 12.0,
			damage = 35,
			duration = 8.0,
			description = "Buff: For 8 seconds, each attack launches homing nature missiles from your back that curve and seek out nearby enemies.",
		},
		[4] = {
			name = "Rain of Arrows",
			slot = 4,
			keybind = "R",
			cooldown = 30.0,
			damage = 24,
			range = 42,
			duration = 4.0,
			description = "Fire an arrow skyward to mark a large zone, then call down a repeated storm of arrows.",
		},
	},
	heavy_knight = {
		[1] = {
			name = "Spin Attack",
			slot = 1,
			keybind = "E",
			cooldown = 8.0,
			damage = 45,
			duration = 5.0,
			range = 14,
			description = "A continuous spinning whirlwind attack for 5 seconds, slicing all nearby enemies.",
			animationId = "rbxassetid://94745840711885",
		},
		[2] = {
			name = "Fire Slam",
			slot = 2,
			keybind = "F",
			cooldown = 12.0,
			damage = 55,
			range = 16,
			maxLeapDistance = 42,
			description = "Leap into the air and strike the ground, creating a fiery shockwave.",
			animationId = "rbxassetid://84579017139529",
		},
		[3] = {
			name = "Phoenix Dash",
			slot = 3,
			keybind = "Q",
			cooldown = 7.5,
			damage = 35,
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
			damage = 150,
			description = "Ultimate: Empower your sword in roaring flames and slam down a massive impact slash that shatters the earth into a rock crater.",
			animationId = "rbxassetid://84579017139529",
			slashAnimationId = "rbxassetid://108875775887071",
		},
	},
}

local SkillModule = {}

function SkillModule.GetSkills(classId: string): ClassSkills?
	return SkillData[classId]
end

function SkillModule.GetSkill(classId: string, skillIndex: number): SkillConfig?
	local skills = SkillModule.GetSkills(classId)
	return skills and skills[skillIndex]
end

return SkillModule
