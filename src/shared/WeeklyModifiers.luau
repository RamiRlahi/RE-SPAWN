--!strict
--[[
	WeeklyModifiers.luau
	This week's omen: one twist on every run, the same in every server,
	changing each Monday (00:00 UTC). Fresh runs without a new dungeon.

	  BLOOD MOON      enemies +50% health; Legendary & Mythic drops twice as likely
	  FROZEN ABYSS    everyone 10% slower; chilled enemies take +25%; Frozen elites everywhere
	  ELITE INVASION  three times the elites; their loot more often
	  GOLD RUSH       double gold
	  THE SWARM       a horde on every floor, and bigger
	  INFERNO         every hit can ignite; burning enemies take +30%; Blazing elites everywhere

	WeeklyModifiers.Current()     this week's (by the clock)
	WeeklyModifiers.Is(id)        is it this week's?
	(The server also sets ReplicatedStorage's "WeeklyModifier" attribute, so
	clients read the same one whatever their own clock says.)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

export type Modifier = { id: string, name: string, description: string, color: Color3, glyph: string }

local WeeklyModifiers = {}

local LIST: { Modifier } = {
	{ id = "blood_moon", name = "BLOOD MOON", glyph = "BM", color = Color3.fromRGB(230, 40, 50),
		description = "Enemies have 50% more health. Legendary and Mythic drops are twice as likely." },
	{ id = "frozen_abyss", name = "FROZEN ABYSS", glyph = "FA", color = Color3.fromRGB(150, 215, 255),
		description = "Everyone moves 10% slower. Chilled enemies take 25% more damage. Frozen elites everywhere." },
	{ id = "elite_invasion", name = "ELITE INVASION", glyph = "EI", color = Color3.fromRGB(190, 110, 255),
		description = "Three times the elites, and they drop gear more often." },
	{ id = "gold_rush", name = "GOLD RUSH", glyph = "GR", color = Color3.fromRGB(255, 205, 80),
		description = "Double gold from everything." },
	{ id = "swarm", name = "THE SWARM", glyph = "SW", color = Color3.fromRGB(140, 220, 110),
		description = "A horde on every floor, from the first, and bigger." },
	{ id = "inferno", name = "INFERNO", glyph = "IN", color = Color3.fromRGB(255, 120, 40),
		description = "Every hit can set enemies alight, and burning enemies take 30% more. Blazing elites everywhere." },
}
WeeklyModifiers.List = LIST

local byId: { [string]: Modifier } = {}
for _, m in ipairs(LIST) do byId[m.id] = m end

local WEEK = 7 * 24 * 3600
local EPOCH_MONDAY = 4 * 24 * 3600 -- (1 Jan 1970 was a Thursday: weeks start on Monday)

local function byClock(): Modifier
	local week = math.floor((os.time() - EPOCH_MONDAY) / WEEK)
	return LIST[(week % #LIST) + 1]
end

function WeeklyModifiers.Current(): Modifier
	local set = ReplicatedStorage:GetAttribute("WeeklyModifier")
	if typeof(set) == "string" and byId[set] then return byId[set] end
	return byClock()
end

function WeeklyModifiers.Is(id: string): boolean
	return WeeklyModifiers.Current().id == id
end

-- When the next one begins (seconds from now).
function WeeklyModifiers.SecondsLeft(): number
	local t = os.time() - EPOCH_MONDAY
	return WEEK - (t % WEEK)
end

-- (the server keeps the attribute right, through the week's turn)
if RunService:IsServer() then
	task.spawn(function()
		while true do
			ReplicatedStorage:SetAttribute("WeeklyModifier", byClock().id)
			task.wait(60)
		end
	end)
end

return WeeklyModifiers
