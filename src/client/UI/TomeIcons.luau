--!strict
-- TomeIcons.luau
-- A pixel-art logo for every tome, boon and relic (on a dark plaque edged in
-- its colour, with a count badge); the HUD's two columns of them (your tomes
-- down the left of the screen, your relics down the right); and the tooltip
-- shown when you hover one: what it does, and for a Chaos Tome the stats it
-- rolled. (Tab brings the cursor back to hover them mid-fight.)

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local TomeData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TomeData"))

local TomeController: any = nil
pcall(function()
	TomeController = require(script.Parent.Parent:WaitForChild("TomeController"))
end)

local player = Players.LocalPlayer

local TomeIcons = {}

local GOLD = Color3.fromRGB(255, 222, 140)
local PLAQUE = Color3.fromRGB(28, 20, 18)
local PARCHMENT = Color3.fromRGB(239, 213, 170)
local FONT = Enum.Font.Arcade

-- ── The pixel art ───────────────────────────────────────────────────────────
-- 11×11 each: "." is empty, "A" the tome's own colour, the rest from PALETTE.
local GRID = 11
local PALETTE: { [string]: Color3 } = {
	W = Color3.fromRGB(240, 240, 240), K = Color3.fromRGB(30, 24, 30), S = Color3.fromRGB(185, 190, 200),
	L = Color3.fromRGB(255, 255, 255), R = Color3.fromRGB(220, 50, 55), D = Color3.fromRGB(130, 20, 30),
	O = Color3.fromRGB(255, 140, 40), Y = Color3.fromRGB(255, 205, 60), N = Color3.fromRGB(140, 90, 50),
	G = Color3.fromRGB(80, 200, 90), B = Color3.fromRGB(120, 190, 255), P = Color3.fromRGB(150, 80, 220),
	T = Color3.fromRGB(230, 205, 160),
}

local ICONS: { [string]: { string } } = {
	agility = {
		"...........",
		"..WW.......",
		".WWWW......",
		"..WWNNN....",
		"....NNN....",
		"....NNN....",
		"....NNN....",
		"....NNNNN..",
		"....NNNNNN.",
		"....KKKKKK.",
		"...........",
	},
	attack_speed = {
		"..........S",
		".........SS",
		"........SS.",
		".......SS..",
		"WW....SS...",
		".....SS....",
		"WWW.YS.....",
		"....YY.....",
		"WW.N..Y....",
		"..N........",
		".N.........",
	},
	cooldown = {
		".YYYYYYYYY.",
		"..B.....B..",
		"..BOOOOOB..",
		"...BOOOB...",
		"....BOB....",
		".....B.....",
		"....B.B....",
		"...B.O.B...",
		"..B.OOO.B..",
		"..BOOOOOB..",
		".YYYYYYYYY.",
	},
	damage = {
		".....S.....",
		"....SSS....",
		"....SRS....",
		"....SRS....",
		"....SRS....",
		"....SRS....",
		"..YYYYYYY..",
		".....N.....",
		".....N.....",
		"....YYY....",
		"...........",
	},
	evasion = {
		"...BBBBB...",
		"..BBBBBBB..",
		".BBBBBBBBB.",
		".BBKBBBKBB.",
		".BBKBBBKBB.",
		".BBBBBBBBB.",
		".BBBBBBBBB.",
		".BBBBBBBBB.",
		".BB.BBB.BB.",
		".B...B...B.",
		"...........",
	},
	gold = {
		"...YYYYY...",
		"..YYLLLYY..",
		".YYLYYYYYY.",
		".YLYYOOYYY.",
		".YLYOYYYYY.",
		".YYYYOOYYY.",
		".YYYYYYOYY.",
		".YYYOOOYYO.",
		"..YYYYYYO..",
		"...YOOOO...",
		"...........",
	},
	health = {
		"...........",
		".RRR...RRR.",
		"RRLRR.RRRRR",
		"RLRRRRRRRRR",
		"RRRRRRRRRRR",
		"RRRRRRRRRRR",
		".RRRRRRRRD.",
		"..RRRRRRD..",
		"...RRRRD...",
		"....RRD....",
		".....D.....",
	},
	knockback = {
		"..KKKKKKK..",
		"..KSSSSSK..",
		"..KSLSSSK..",
		"..KSSSSSK..",
		"..KKKKKKK..",
		".....N.....",
		".....N.....",
		".....N.....",
		".....N.....",
		"....NNN....",
		"...........",
	},
	precision = {
		".....R.....",
		"...RRRRR...",
		"..R.....R..",
		".R.......R.",
		".R...R...R.",
		"RRR.RRR.RRR",
		".R...R...R.",
		".R.......R.",
		"..R.....R..",
		"...RRRRR...",
		".....R.....",
	},
	projectile_speed = {
		"...........",
		"...........",
		"..AAA......",
		"W........S.",
		"WWNNNNNNSSS",
		"W........S.",
		"..AAA......",
		"...........",
		"...........",
		"...........",
		"...........",
	},
	regen = {
		"...........",
		"....GGG....",
		"....GLG....",
		"....GGG....",
		".GGGGGGGGG.",
		".GLGGGGGGG.",
		".GGGGGGGGG.",
		"....GGG....",
		"....GGG....",
		"....GGG....",
		"...........",
	},
	shield = {
		".SSSSSSSSS.",
		".SBBBBBBBS.",
		".SBBBLBBBS.",
		".SBBBLBBBS.",
		".SBLLLLLBS.",
		".SBBBLBBBS.",
		"..SBBLBBS..",
		"..SBBBBBS..",
		"...SBBBS...",
		"....SBS....",
		".....S.....",
	},
	silver = {
		"...SSSSS...",
		"..SSLLLSS..",
		".SSLSSSSSS.",
		".SLSSKKSSS.",
		".SLSKSSSSS.",
		".SSSSKKSSS.",
		".SSSSSSKSS.",
		".SSSKKKSSK.",
		"..SSSSSSK..",
		"...SKKKK...",
		"...........",
	},
	ricochet = {
		"..........W",
		"O.........O",
		".O.......O.",
		"..O.....O..",
		"...O...O...",
		"....O.O....",
		".....O.....",
		"...........",
		"SSSSSSSSSSS",
		"KKKKKKKKKKK",
		"...........",
	},
	size = {
		"WWW.....WWW",
		"WW.......WW",
		"W.W.....W.W",
		"...W...W...",
		"....AAA....",
		"....AAA....",
		"....AAA....",
		"...W...W...",
		"W.W.....W.W",
		"WW.......WW",
		"WWW.....WWW",
	},
	armor = {
		".SS.....SS.",
		"SSSS...SSSS",
		"SSSSSSSSSSS",
		".SSSSLSSSS.",
		".SSSSLSSSS.",
		".SSSSLSSSS.",
		".SSSSLSSSS.",
		"..SSSLSSS..",
		"..SSSSSSS..",
		"...SSSSS...",
		"...........",
	},
	attraction = {
		"..RRRRRRR..",
		".RRRRRRRRR.",
		".RRR...RRR.",
		".RRR...RRR.",
		".RRR...RRR.",
		".RRR...RRR.",
		".RRR...RRR.",
		".SSS...SSS.",
		".SSS...SSS.",
		"...........",
		"...........",
	},
	bloody = {
		".....R.....",
		".....R.....",
		"....RRR....",
		"....RRR....",
		"...RRRRR...",
		"..RRLRRRR..",
		"..RLRRRRR..",
		"..RRRRRRR..",
		"..RRRRRRD..",
		"...RRRRD...",
		"....DDD....",
	},
	chaos = {
		"...........",
		".PPPPPPPPP.",
		".PKPPPPPKP.",
		".PPPPPPPPP.",
		".PPPPPPPPP.",
		".PPPPKPPPP.",
		".PPPPPPPPP.",
		".PPPPPPPPP.",
		".PKPPPPPKP.",
		".PPPPPPPPP.",
		"...........",
	},
	cursed = {
		"...WWWWW...",
		"..WWWWWWW..",
		".WWWWWWWWW.",
		".WKKWWWKKW.",
		".WKKWWWKKW.",
		".WWWWKWWWW.",
		"..WWWWWWW..",
		"..WKWKWKW..",
		"...WWWWW...",
		"...........",
		"...........",
	},
	duration = {
		"....YYY....",
		".....Y.....",
		"..YYYYYYY..",
		".YWWWWWWWY.",
		".YWWWKWWWY.",
		".YWWWKWWWY.",
		".YWWWKKKWY.",
		".YWWWWWWWY.",
		".YWWWWWWWY.",
		"..YYYYYYY..",
		"...........",
	},
	luck = {
		"..GG...GG..",
		".GGGG.GGGG.",
		".GGLG.GGGG.",
		"..GGGGGGG..",
		"....GGG....",
		"..GGGGGGG..",
		".GGGG.GGGG.",
		".GGGG.GGGG.",
		"..GG...GG..",
		"......N....",
		".......N...",
	},
	quantity = {
		".S...S...S.",
		"SSS.SSS.SSS",
		".N...N...N.",
		".N...N...N.",
		".N...N...N.",
		".N...N...N.",
		".N...N...N.",
		"WNW.WNW.WNW",
		"W.W.W.W.W.W",
		"...........",
		"...........",
	},
	thorns = {
		".....G.....",
		"..G..G..G..",
		"...GGGGG...",
		"...GDDDG...",
		"GGGGDDDGGGG",
		"...GDDDG...",
		"...GGGGG...",
		"..G..G..G..",
		".....G.....",
		"...........",
		"...........",
	},
	boon_ignite = {
		".....O.....",
		"....OO.....",
		"....OOO....",
		"...OOYO....",
		"..OOYYOO...",
		"..OYYYYO.O.",
		".OOYYWYOOO.",
		".OYYWWWYYO.",
		".OYYWWWYYO.",
		"..OYYYYYO..",
		"...OOOOO...",
	},
	boon_frost = {
		".....B.....",
		"...B.B.B...",
		"....BBB....",
		".B...B...B.",
		"..B..B..B..",
		"BBBBBBBBBBB",
		"..B..B..B..",
		".B...B...B.",
		"....BBB....",
		"...B.B.B...",
		".....B.....",
	},
	boon_chain = {
		"W.....YYY..",
		".....YYY...",
		"....YYY....",
		"...YYYYYY..",
		".....YYY...",
		"....YYY..W.",
		"...YYY.....",
		"..YY.Y.....",
		".YY...Y....",
		".Y.....W...",
		"W..........",
	},
	boon_bloodlust = {
		".....R.....",
		"....RRR....",
		"...RRDRR...",
		"..RRD.DRR..",
		".RRD...DRR.",
		".....R.....",
		"....RRR....",
		"...RRDRR...",
		"..RRD.DRR..",
		".RRD...DRR.",
		"...........",
	},
	boon_corpse = {
		"........Y..",
		".......Y.Y.",
		"......N....",
		"....KKKK...",
		"...KKKKKK..",
		"..KKLKKKKK.",
		"..KLKKKKKK.",
		"..KKKKKKKK.",
		"..KKKKKKKK.",
		"...KKKKKK..",
		"....KKKK...",
	},
	boon_execute = {
		".SSSS......",
		"SSSSSN.....",
		"SSSSSSN....",
		"SSSSS.N....",
		".SSS...N...",
		".......N...",
		"........N..",
		"........N..",
		".........N.",
		".........N.",
		"...........",
	},
	boon_thunder = {
		"..SSSSS....",
		".SSSSSSSS..",
		"SSSSSSSSSS.",
		".SSSSSSSS..",
		"....YY.....",
		"...YY......",
		"..YYYY.....",
		"....YY.....",
		"...YY......",
		"..Y........",
		"...........",
	},
	boon_secondwind = {
		"...........",
		"WW.......WW",
		"WWW.R.R.WWW",
		".WWRRRRRWW.",
		"..WRRRRRW..",
		"...WRRRW...",
		".....R.....",
		"...........",
		"...........",
		"...........",
		"...........",
	},
	relic_dragons_heart = {
		"...........",
		".OOO...OOO.",
		"OORRO.ORROO",
		"ORKRRORKRRO",
		"ORRRKRRRKRO",
		"ORKRRRKRRRO",
		".ORRRKRRRO.",
		"..ORRRRRO..",
		"...ORRRO...",
		"....ORO....",
		".....O.....",
	},
	relic_bloodied_crown = {
		"...........",
		".Y...Y...Y.",
		".YY.YYY.YY.",
		".YYYYYYYYY.",
		".YRYYRYYRY.",
		".YYYYYYYYY.",
		"..R.....R..",
		"..R........",
		"...........",
		"...........",
		"...........",
	},
	relic_frozen_soul = {
		".....B.....",
		"....BB.....",
		"....BBB....",
		"...BBWB....",
		"..BBWWBB...",
		"..BWWWWB.B.",
		".BBWWLWBBB.",
		".BWWLLLWWB.",
		".BWWLLLWWB.",
		"..BWWWWWB..",
		"...BBBBB...",
	},
	relic_berserkers_tooth = {
		"...WWWWW...",
		"..WWWWWWW..",
		"..WWLWWWW..",
		"...WLWWW...",
		"...WWWWW...",
		"....WWW....",
		"....WWW....",
		".....W.....",
		".....R.....",
		".....R.....",
		"...........",
	},
	relic_shattered_mirror = {
		"...YYYYY...",
		"..YBBBBBY..",
		".YBBBWBBBY.",
		".YBBWBBBBY.",
		".YBBBWBBBY.",
		".YBBBBWBBY.",
		".YBBBWBBBY.",
		"..YBBBBBY..",
		"...YYYYY...",
		".....Y.....",
		"....YYY....",
	},
	relic_gamblers_coin = {
		"...YYSSS...",
		"..YYYSSSS..",
		".YYLYSSSSS.",
		".YLYYSSSSS.",
		".YLYYSSSSS.",
		".YYYYSSSSS.",
		".YYYYSSSKS.",
		".YYYYSSSKS.",
		"..YYYSSKS..",
		"...YYSSS...",
		"...........",
	},
	relic_hollow_lantern = {
		".....K.....",
		"....KKK....",
		"...KKKKK...",
		"...KOYOK...",
		"...KYWYK...",
		"...KOYOK...",
		"...KYYYK...",
		"...KKKKK...",
		"....KKK....",
		"...........",
		"...........",
	},
	relic_iron_vow = {
		"....RRR....",
		"....RRR....",
		"...SSSSS...",
		"..SS...SS..",
		".SS.....SS.",
		".S.......S.",
		".S.......S.",
		".SS.....SS.",
		"..SS...SS..",
		"...SSSSS...",
		"...........",
	},
	relic_vampire_fang = {
		"...........",
		"...........",
		"P..P...P..P",
		"PP.PPPPP.PP",
		"PPPPPPPPPPP",
		".PPPRPRPPP.",
		"..PPPPPPP..",
		"...P.P.P...",
		"...........",
		"...........",
		"...........",
	},
	relic_storm_eye = {
		"...........",
		"...........",
		"...BBBBB...",
		".BB.....BB.",
		"B...YYY...B",
		"B..YKKKY..B",
		"B...YYY...B",
		".BB.....BB.",
		"...BBBBB...",
		"...........",
		"...........",
	},
	relic_frozen_heart = {
		"...........",
		".BBB...BBB.",
		"BBWBB.BBBBB",
		"BWBBBBBBBBB",
		"BBBBBBBBBBB",
		"BBBBBBBBBBB",
		".BBBBBBBBS.",
		"..BBBBBBS..",
		"...BBBBS...",
		"....BBS....",
		".....S.....",
	},
	relic_blood_oath = {
		".TTTTTTTT..",
		".TKKKKKKT..",
		".TTTTTTTT..",
		".TKKKKKT...",
		".TTTTTTRR..",
		".TKKKTRRRR.",
		".TTTTTRRRR.",
		"..TTTTTRR..",
		"...........",
		"...........",
		"...........",
	},
	relic_saints_bell = {
		".....Y.....",
		"....YYY....",
		"...YYYYY...",
		"...YYYYY...",
		"..YYYLYYY..",
		"..YYYLYYY..",
		"..YYYYYYY..",
		".YYYYYYYYY.",
		"YYYYYYYYYYY",
		".....N.....",
		"...........",
	},
	relic_loaded_dice = {
		"...........",
		".RRRRRRRRR.",
		".RWRRRRRWR.",
		".RRRRRRRRR.",
		".RRRRRRRRR.",
		".RRRRWRRRR.",
		".RRRRRRRRR.",
		".RRRRRRRRR.",
		".RWRRRRRWR.",
		".RRRRRRRRR.",
		"...........",
	},
	relic_ember_heart = {
		"...........",
		".OOO...OOO.",
		"OOYOO.OOOOO",
		"OYOOOOOOOOO",
		"OOOOYYYOOOO",
		"OOOYYWYYOOO",
		".OOYWWWYOR.",
		"..OOYYYOR..",
		"...OOOOR...",
		"....OOR....",
		".....R.....",
	},
	relic_duelists_mark = {
		"S.........S",
		".S.......S.",
		"..S.....S..",
		"...S...S...",
		"....S.S....",
		".....S.....",
		"....S.S....",
		"...Y...Y...",
		"..N.....N..",
		".N.......N.",
		"...........",
	},
	relic_hunters_sigil = {
		"...RRRRR...",
		"..RWWWWWR..",
		".RWRRRRRWR.",
		".RWRWWWRWR.",
		".RWRWRWRWR.",
		".RWRWWWRWR.",
		".RWRRRRRWR.",
		"..RWWWWWR..",
		"...RRRRR...",
		"...........",
		"...........",
	},
}

-- Letters for anything without a picture (the first letters of its name).
function TomeIcons.Glyph(id: string): string
	local tome = TomeData.GetTome and TomeData.GetTome(id)
	local name = if tome then string.gsub(tome.name, " Tome$", "") else id
	return string.upper(string.sub(name, 1, 3))
end

function TomeIcons.Accent(id: string): Color3
	if TomeController and TomeController.AccentFor then return TomeController.AccentFor(id) end
	return GOLD
end

-- The picture, each pixel `px` screen pixels wide, from `origin`. A row's
-- runs of one colour are one frame.
local function drawPixels(parent: Instance, rows: { string }, px: number, origin: Vector2, accent: Color3, z: number)
	for y, row in ipairs(rows) do
		local x = 1
		while x <= GRID do
			local ch = string.sub(row, x, x)
			if ch == "." then
				x += 1
			else
				local run = 1
				while x + run <= GRID and string.sub(row, x + run, x + run) == ch do run += 1 end
				local f = Instance.new("Frame")
				f.BorderSizePixel = 0
				f.BackgroundColor3 = if ch == "A" then accent else (PALETTE[ch] or accent)
				f.Position = UDim2.fromOffset(origin.X + (x - 1) * px, origin.Y + (y - 1) * px)
				f.Size = UDim2.fromOffset(run * px, px)
				f.ZIndex = z
				f.Parent = parent
				x += run
			end
		end
	end
end

-- ── Tooltip (shared) ────────────────────────────────────────────────────────
local tipGui: ScreenGui? = nil
local tip: Frame? = nil
local tipStroke: UIStroke? = nil
local tipName: TextLabel? = nil
local tipDesc: TextLabel? = nil
local inspecting = false
local TIP_W = 250

local function ensureTip()
	if tipGui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "TomeTooltip"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 300
	g.Parent = player:WaitForChild("PlayerGui")
	tipGui = g
	local f = Instance.new("Frame")
	f.Size = UDim2.fromOffset(TIP_W, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = PLAQUE
	f.BackgroundTransparency = 0.05
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = g
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Thickness = 2
	st.Parent = f
	tipStroke = st
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 8), UDim.new(0, 8)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 10), UDim.new(0, 10)
	pad.Parent = f
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	tip = f
	local n = Instance.new("TextLabel")
	n.BackgroundTransparency = 1
	n.Size = UDim2.new(1, 0, 0, 18)
	n.Font = FONT
	n.TextSize = 16
	n.TextXAlignment = Enum.TextXAlignment.Left
	n.TextColor3 = GOLD
	n.LayoutOrder = 1
	n.Parent = f
	tipName = n
	local d = Instance.new("TextLabel")
	d.BackgroundTransparency = 1
	d.Size = UDim2.new(1, 0, 0, 0)
	d.AutomaticSize = Enum.AutomaticSize.Y
	d.Font = FONT
	d.TextSize = 13
	d.TextWrapped = true
	d.TextXAlignment = Enum.TextXAlignment.Left
	d.TextYAlignment = Enum.TextYAlignment.Top
	d.TextColor3 = PARCHMENT
	d.LayoutOrder = 2
	d.Parent = f
	tipDesc = d
end

-- What your Chaos Tomes rolled this run (ChaosBonus_1, _2, ...: one stat
-- tome's effect each), the same roll counted together.
local function chaosRolls(): { string }
	local counts: { [string]: number } = {}
	local order: { string } = {}
	local i = 1
	while true do
		local id = player:GetAttribute(`ChaosBonus_{i}`)
		if typeof(id) ~= "string" then break end
		if not counts[id] then
			counts[id] = 0
			table.insert(order, id)
		end
		counts[id] += 1
		i += 1
	end
	local lines = {}
	for _, id in ipairs(order) do
		local t = TomeData.GetTome(id)
		local eff = t and t.effects[1]
		local text = (eff and eff.description) or (t and t.name) or id
		table.insert(lines, if counts[id] > 1 then `- {text}  x{counts[id]}` else `- {text}`)
	end
	return lines
end

local function showTip(id: string, count: number)
	ensureTip()
	local tome = TomeData.GetTome(id)
	local accent = TomeIcons.Accent(id)
	local name = tipName :: TextLabel
	local desc = tipDesc :: TextLabel
	local title = if tome then tome.name else id
	name.Text = if count > 1 then `{title}  x{count}` else title
	name.TextColor3 = accent
	local text = if tome then tome.description else ""
	if id == "chaos" then
		local rolls = chaosRolls()
		text = if #rolls > 0 then "It rolled:\n" .. table.concat(rolls, "\n") else "A random stat boost."
	end
	desc.Text = text
	if tipStroke then tipStroke.Color = accent end
	-- (beside the cursor, kept on screen)
	local f = tip :: Frame
	local m = UserInputService:GetMouseLocation()
	local view = if Workspace.CurrentCamera then Workspace.CurrentCamera.ViewportSize else Vector2.new(1920, 1080)
	local x = if m.X + 18 + TIP_W > view.X then m.X - 18 - TIP_W else m.X + 18
	local y = math.clamp(m.Y - 20, 8, math.max(8, view.Y - f.AbsoluteSize.Y - 8))
	f.Position = UDim2.fromOffset(x, y)
	f.Visible = true
end

local function hideTip()
	if tip then tip.Visible = false end
end

-- Tab held: bring the cursor back, to hover the icons.
local savedMouseIcon: boolean? = nil
function TomeIcons.SetInspecting(on: boolean)
	if on == inspecting then return end
	inspecting = on
	if on then
		savedMouseIcon = UserInputService.MouseIconEnabled
		UserInputService.MouseIconEnabled = true
	else
		hideTip()
		if savedMouseIcon ~= nil then UserInputService.MouseIconEnabled = savedMouseIcon end
		savedMouseIcon = nil
	end
end

-- ── One logo ────────────────────────────────────────────────────────────────
function TomeIcons.Make(parent: Instance, id: string, count: number, size: number): Frame
	local accent = TomeIcons.Accent(id)
	local holder = Instance.new("Frame")
	holder.Name = `TomeIcon_{id}`
	holder.Size = UDim2.fromOffset(size, size)
	holder.BackgroundColor3 = PLAQUE
	holder.BackgroundTransparency = 0.1
	holder.BorderSizePixel = 0
	holder.Parent = parent
	local st = Instance.new("UIStroke")
	st.Color = accent
	st.Thickness = 2
	st.Parent = holder

	local rows = ICONS[id]
	if rows then
		-- (whole pixels only, so the art stays crisp)
		local px = math.max(1, math.floor((size - 6) / GRID))
		local inner = px * GRID
		local o = math.floor((size - inner) / 2)
		drawPixels(holder, rows, px, Vector2.new(o, o), accent, 2)
	else
		local glyph = Instance.new("TextLabel")
		glyph.BackgroundTransparency = 1
		glyph.Size = UDim2.fromScale(1, 1)
		glyph.Text = TomeIcons.Glyph(id)
		glyph.TextScaled = true
		glyph.Font = FONT
		glyph.TextColor3 = accent
		glyph.ZIndex = 2
		glyph.Parent = holder
		local pad = Instance.new("UIPadding")
		local p = math.floor(size * 0.18)
		pad.PaddingTop, pad.PaddingBottom = UDim.new(0, p), UDim.new(0, p)
		pad.PaddingLeft, pad.PaddingRight = UDim.new(0, p), UDim.new(0, p)
		pad.Parent = glyph
	end

	if count > 1 then
		local badge = Instance.new("TextLabel")
		badge.AnchorPoint = Vector2.new(1, 1)
		badge.Position = UDim2.new(1, 4, 1, 4)
		badge.Size = UDim2.fromOffset(math.max(16, math.floor(size * 0.42)), math.max(14, math.floor(size * 0.36)))
		badge.BackgroundColor3 = accent
		badge.BorderSizePixel = 0
		badge.Font = FONT
		badge.TextScaled = true
		badge.TextColor3 = PLAQUE
		badge.Text = tostring(count)
		badge.ZIndex = 3
		badge.Parent = holder
	end

	holder.MouseEnter:Connect(function() showTip(id, count) end)
	holder.MouseMoved:Connect(function() showTip(id, count) end)
	holder.MouseLeave:Connect(hideTip)
	return holder
end

-- Your tomes this run (from the Tome_<id> attributes), most-taken first.
-- `kind`: "tomes" (boons too) or "relics" for just those; nil for all.
function TomeIcons.Owned(kind: string?): { { id: string, count: number } }
	local owned = {}
	for name, count in pairs(player:GetAttributes()) do
		if string.sub(name, 1, 5) == "Tome_" and typeof(count) == "number" and count > 0 then
			local id = string.sub(name, 6)
			if kind == nil or (kind == "relics") == TomeData.IsRelic(id) then
				table.insert(owned, { id = id, count = count })
			end
		end
	end
	table.sort(owned, function(a, b)
		if a.count ~= b.count then return a.count > b.count end
		return a.id < b.id
	end)
	return owned
end

-- A self-updating column of logos for the HUD: your tomes (`kind` "tomes",
-- down the left edge) or your relics ("relics", down the right). Past six it
-- starts another column beside the first.
function TomeIcons.Column(parent: Instance, size: number, kind: string): Frame
	local col = Instance.new("Frame")
	col.Name = if kind == "relics" then "RelicColumn" else "TomeColumn"
	col.BackgroundTransparency = 1
	col.Size = UDim2.fromOffset(size, size)
	col.AutomaticSize = Enum.AutomaticSize.XY
	col.Parent = parent
	local grid = Instance.new("UIGridLayout")
	grid.CellSize = UDim2.fromOffset(size, size)
	grid.CellPadding = UDim2.fromOffset(8, 8)
	grid.FillDirection = Enum.FillDirection.Vertical
	grid.FillDirectionMaxCells = 6
	grid.StartCorner = if kind == "relics" then Enum.StartCorner.TopRight else Enum.StartCorner.TopLeft
	grid.SortOrder = Enum.SortOrder.LayoutOrder
	grid.Parent = col
	local function refresh()
		for _, c in ipairs(col:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		hideTip()
		for i, t in ipairs(TomeIcons.Owned(kind)) do
			TomeIcons.Make(col, t.id, t.count, size).LayoutOrder = i
		end
	end
	refresh()
	player.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) == "Tome_" then refresh() end
	end)
	return col
end

return TomeIcons
