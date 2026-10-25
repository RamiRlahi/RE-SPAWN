--!strict
--[[
	GuildData
	The guild rules, shared by GuildManager (server) and the guild screens.

	  • Creating a guild costs CREATE_COST souls (a name and a 2–4 letter tag);
	    MAX_MEMBERS members. Join by invite, or by a request the leader or an
	    officer accepts.
	  • Members earn guild points from dungeon runs (Points): deeper floors,
	    bosses, elites, and getting out alive are worth more.
	  • Seasons are a week long (SeasonOf). When one ends, every member of a
	    ranked guild is paid by its final rank (Rewards), the top 3 get a title,
	    the top 10 a run buff for the next season, and the top 3 guilds' top
	    contributors stand on the podium in every lobby.
--]]

local GuildData = {}

GuildData.CREATE_COST = 100   -- souls
GuildData.MAX_MEMBERS = 20
GuildData.MAX_OFFICERS = 3
GuildData.NAME_MIN, GuildData.NAME_MAX = 3, 20
GuildData.TAG_MIN, GuildData.TAG_MAX = 2, 4

-- Seasons: a week each, starting Monday 00:00 UTC.
GuildData.SEASON_LENGTH = 7 * 24 * 3600
GuildData.SEASON_EPOCH = 1704672000 -- Mon 8 Jan 2024 00:00 UTC

function GuildData.SeasonOf(t: number): number
	return math.floor((t - GuildData.SEASON_EPOCH) / GuildData.SEASON_LENGTH)
end

function GuildData.SeasonEnds(season: number): number
	return GuildData.SEASON_EPOCH + (season + 1) * GuildData.SEASON_LENGTH
end

-- Guild points for one finished run.
function GuildData.Points(floor: number, bosses: number, elites: number, extracted: boolean): number
	local p = floor * 10 + bosses * 25 + elites * 5
	if extracted then p += 20 end
	return math.max(0, math.floor(p))
end

-- What a season's final rank pays every member (rank → bracket).
GuildData.Rewards = {
	{ upTo = 1, souls = 300, tickets = 30, title = "t_guild_champion", buff = 0.10 },
	{ upTo = 3, souls = 200, tickets = 20, title = "t_guild_vanguard", buff = 0.08 },
	{ upTo = 10, souls = 120, tickets = 12, buff = 0.05 },
	{ upTo = 50, souls = 60, tickets = 5 },
	{ upTo = 200, souls = 25, tickets = 2 },
}

function GuildData.RewardFor(rank: number): any?
	for _, r in ipairs(GuildData.Rewards) do
		if rank <= r.upTo then return r end
	end
	return nil
end

-- A guild name / tag the rules allow (letters, digits, spaces in the name).
function GuildData.ValidName(name: string): boolean
	local n = #name
	return n >= GuildData.NAME_MIN and n <= GuildData.NAME_MAX and string.match(name, "^[%w ]+$") ~= nil
		and string.match(name, "^ ") == nil and string.match(name, " $") == nil
end

function GuildData.ValidTag(tag: string): boolean
	local n = #tag
	return n >= GuildData.TAG_MIN and n <= GuildData.TAG_MAX and string.match(tag, "^%w+$") ~= nil
end

return GuildData
