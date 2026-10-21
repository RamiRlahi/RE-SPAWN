--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- EmoteData.luau (Shared)
-- The catalog of emotes available in lobby and dungeon runs.
-- Includes all 5 lobby emotes (wave, cheer, point, laugh, dance) plus extra
-- expressive emotes (dance2, dance3, bow, salute, shrug, flex, tilt).
-- Supports both R6 and R15 rigs so animations always play properly.
-- ─────────────────────────────────────────────────────────────────────────────

export type EmoteInfo = {
	id: string,             -- unique key
	name: string,           -- display name on the wheel
	r15: number,            -- Roblox animation asset ID for R15
	r6: number,             -- Roblox animation asset ID for R6
	looping: boolean,       -- true = loops until cancelled
	category: string,       -- for grouping on the wheel
	glyph: string,          -- 1-2 char icon/emoji for the button
	cooldown: number,       -- seconds before you can emote again
}

local EmoteData = {}

-- ── The Catalog ──────────────────────────────────────────────────────────────
-- Official Roblox emote animations (universally accessible)
local emoteList: { EmoteInfo } = {
	-- ── Lobby Classics ───────────────────────────────────────────
	{
		id          = "wave",
		name        = "Wave",
		r15         = 507770239,
		r6          = 128777973,
		looping     = false,
		category    = "Greetings",
		glyph       = "👋",
		cooldown    = 1.5,
	},
	{
		id          = "cheer",
		name        = "Cheer",
		r15         = 507770677,
		r6          = 129423030,
		looping     = false,
		category    = "Celebration",
		glyph       = "🎉",
		cooldown    = 2.0,
	},
	{
		id          = "point",
		name        = "Point",
		r15         = 507770453,
		r6          = 128853357,
		looping     = false,
		category    = "Expression",
		glyph       = "👉",
		cooldown    = 1.5,
	},
	{
		id          = "laugh",
		name        = "Laugh",
		r15         = 507770818,
		r6          = 129423131,
		looping     = false,
		category    = "Celebration",
		glyph       = "😂",
		cooldown    = 2.0,
	},
	{
		id          = "dance",
		name        = "Dance",
		r15         = 507771019,
		r6          = 182435998,
		looping     = true,
		category    = "Dance",
		glyph       = "💃",
		cooldown    = 1.0,
	},

	-- ── Extra Dances ─────────────────────────────────────────────
	{
		id          = "dance2",
		name        = "Dance 2",
		r15         = 507776043,
		r6          = 182436842,
		looping     = true,
		category    = "Dance",
		glyph       = "🕺",
		cooldown    = 1.0,
	},
	{
		id          = "dance3",
		name        = "Dance 3",
		r15         = 507777623,
		r6          = 182436935,
		looping     = true,
		category    = "Dance",
		glyph       = "🪩",
		cooldown    = 1.0,
	},

	-- ── Honor & Respect ──────────────────────────────────────────
	{
		id          = "bow",
		name        = "Bow",
		r15         = 507773322,
		r6          = 204295235,
		looping     = false,
		category    = "Greetings",
		glyph       = "🙇",
		cooldown    = 2.0,
	},
	{
		id          = "salute",
		name        = "Salute",
		r15         = 3360689775,
		r6          = 3360689775,
		looping     = false,
		category    = "Greetings",
		glyph       = "🫡",
		cooldown    = 1.5,
	},

	-- ── Expressions & Taunts ──────────────────────────────────────
	{
		id          = "shrug",
		name        = "Shrug",
		r15         = 3360690947,
		r6          = 3360690947,
		looping     = false,
		category    = "Expression",
		glyph       = "🤷",
		cooldown    = 1.5,
	},
	{
		id          = "flex",
		name        = "Flex",
		r15         = 3360686498,
		r6          = 3360686498,
		looping     = false,
		category    = "Taunt",
		glyph       = "💪",
		cooldown    = 2.0,
	},
	{
		id          = "tilt",
		name        = "Tilt",
		r15         = 3360692915,
		r6          = 3360692915,
		looping     = false,
		category    = "Taunt",
		glyph       = "😏",
		cooldown    = 1.5,
	},
}

-- Exported table and lookup table
EmoteData.Emotes = emoteList
EmoteData._byId = {} :: { [string]: EmoteInfo }
for _, emote in ipairs(EmoteData.Emotes) do
	EmoteData._byId[emote.id] = emote
end

function EmoteData.Get(id: string): EmoteInfo?
	return EmoteData._byId[id]
end

function EmoteData.GetAll(): { EmoteInfo }
	return EmoteData.Emotes
end

-- Resolves the correct rbxassetid:// string for the given rig type
function EmoteData.GetAssetId(emote: EmoteInfo, rigType: Enum.HumanoidRigType?): string
	local idNum = if rigType == Enum.HumanoidRigType.R6 then emote.r6 else emote.r15
	return "rbxassetid://" .. tostring(idNum)
end

function EmoteData.Categories(): { string }
	local seen: { [string]: boolean } = {}
	local cats: { string } = {}
	for _, emote in ipairs(EmoteData.Emotes) do
		if not seen[emote.category] then
			seen[emote.category] = true
			table.insert(cats, emote.category)
		end
	end
	return cats
end

return EmoteData
