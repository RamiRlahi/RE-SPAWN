--!strict
--[[
	GearModels.luau
	The Forgotten Isle's gear (EquipmentData) as toy-brick models, built with
	BrickModels' kit so they sit with the relics and tomes:

	  GearModels.Icon(id)   → Model?   the item on its own (a slot, a bag
	                                   entry, the detail view), pivot at the
	                                   voxel origin
	  GearModels.Look(id)   → { kind, pal }

	Every icon is built once and kept as a template: Icon() hands out clones.
	Nothing here is parented: the caller puts it in a ViewportFrame.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EquipmentData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("EquipmentData"))
local BrickModels = require(script.Parent:WaitForChild("BrickModels"))
local K = BrickModels.Kit

local GearModels = {}

type Pal = { [string]: Color3 }
type Look = { kind: string, pal: Pal, neon: { [string]: boolean }? }

local function rgb(r: number, g: number, b: number): Color3 return Color3.fromRGB(r, g, b) end

-- Each item: the shape it's drawn with and its colours. Letters in the
-- sprites: M main, D dark, L light, E edge, T trim, H handle, P pommel,
-- N glow, O hot glow, K hollow/black, S string.
local LOOKS: { [string]: Look } = {
	-- weapons
	wardens_edge = { kind = "sword", pal = { E = rgb(230, 236, 245), L = rgb(170, 182, 200), N = rgb(90, 170, 255), T = rgb(214, 170, 70), H = rgb(80, 50, 32), P = rgb(90, 170, 255) } },
	ashfang_greatsword = { kind = "greatsword", pal = { E = rgb(150, 140, 135), L = rgb(70, 64, 66), N = rgb(255, 120, 40), T = rgb(40, 36, 38), D = rgb(120, 40, 25), H = rgb(55, 35, 28), P = rgb(255, 120, 40) } },
	stormpiercer_rapier = { kind = "rapier", pal = { E = rgb(235, 245, 255), L = rgb(160, 210, 240), N = rgb(90, 230, 255), T = rgb(200, 210, 225), H = rgb(40, 60, 110), P = rgb(90, 230, 255) } },
	plaguewood_longbow = { kind = "bow", pal = { M = rgb(95, 110, 50), D = rgb(60, 70, 30), H = rgb(70, 45, 30), S = rgb(225, 230, 200), N = rgb(140, 255, 80) } },
	riftcaller_staff = { kind = "staff", pal = { N = rgb(170, 90, 255), O = rgb(235, 200, 255), T = rgb(200, 170, 255), H = rgb(55, 38, 60), D = rgb(150, 110, 210) } },
	sunken_kings_axe = { kind = "axe", pal = { M = rgb(70, 150, 135), E = rgb(170, 225, 210), N = rgb(80, 255, 220), T = rgb(220, 180, 70), H = rgb(70, 50, 40), D = rgb(220, 180, 70) } },
	tidebreaker_trident = { kind = "trident", pal = { E = rgb(200, 250, 255), L = rgb(60, 170, 190), N = rgb(60, 240, 255), T = rgb(240, 130, 110), H = rgb(30, 70, 95), D = rgb(240, 130, 110) } },
	riftbound_blade = { kind = "sword", pal = { E = rgb(215, 170, 255), L = rgb(50, 30, 70), N = rgb(255, 60, 200), T = rgb(120, 60, 170), H = rgb(30, 20, 40), P = rgb(255, 60, 200) } },
	-- armour
	bastion_plate = { kind = "plate", pal = { M = rgb(160, 170, 185), L = rgb(215, 222, 232), D = rgb(95, 102, 115), T = rgb(214, 170, 70), N = rgb(120, 180, 255) } },
	ashen_mantle = { kind = "mantle", pal = { M = rgb(110, 104, 104), D = rgb(65, 60, 62), K = rgb(20, 16, 18), T = rgb(214, 160, 80), N = rgb(255, 120, 40) } },
	stalker_leathers = { kind = "leathers", pal = { M = rgb(120, 78, 48), D = rgb(70, 45, 30), T = rgb(45, 32, 26), N = rgb(220, 190, 120) } },
	wyrmhide_armor = { kind = "scales", pal = { M = rgb(150, 30, 35), L = rgb(205, 70, 55), D = rgb(80, 20, 22), T = rgb(240, 190, 70), N = rgb(255, 170, 60) } },
	plagueweave_robes = { kind = "robes", pal = { M = rgb(85, 55, 110), D = rgb(45, 30, 60), T = rgb(130, 190, 80), N = rgb(150, 255, 90) } },
	colossus_core = { kind = "core", pal = { M = rgb(45, 40, 42), D = rgb(25, 22, 24), T = rgb(95, 85, 80), N = rgb(255, 110, 30), O = rgb(255, 225, 120) } },
	-- helmets
	hollow_kings_crown = { kind = "crown", pal = { T = rgb(205, 165, 70), D = rgb(120, 90, 40), N = rgb(150, 60, 255) } },
	ashguard_helm = { kind = "helm", pal = { M = rgb(75, 72, 78), D = rgb(45, 42, 48), T = rgb(150, 140, 135), K = rgb(15, 12, 14), N = rgb(255, 120, 40) } },
	oracles_veil = { kind = "veil", pal = { M = rgb(150, 120, 200), L = rgb(200, 180, 240), K = rgb(30, 20, 45), T = rgb(240, 210, 120), N = rgb(120, 255, 240) } },
	saints_halo = { kind = "halo", pal = { N = rgb(255, 225, 130), O = rgb(255, 250, 225), T = rgb(220, 180, 80) } },
	-- accessories
	ring_of_embers = { kind = "ring", pal = { T = rgb(225, 175, 60), D = rgb(160, 110, 30), N = rgb(255, 100, 30), O = rgb(255, 210, 110) } },
	riftglass_pendant = { kind = "pendant", pal = { T = rgb(200, 205, 220), N = rgb(185, 100, 255), O = rgb(240, 210, 255) } },
	hunters_sigil = { kind = "sigil", pal = { M = rgb(170, 110, 60), D = rgb(110, 70, 40), T = rgb(230, 190, 110), N = rgb(120, 230, 90) } },
	greedbound_coin = { kind = "coin", pal = { M = rgb(240, 190, 50), D = rgb(185, 130, 25), T = rgb(255, 230, 130), N = rgb(230, 40, 50) } },
	heartroot_charm = { kind = "charm", pal = { M = rgb(140, 85, 50), D = rgb(90, 55, 35), N = rgb(110, 240, 100), T = rgb(230, 80, 90) } },
	soulkeeper_relic = { kind = "relic", pal = { M = rgb(70, 80, 95), D = rgb(40, 45, 55), T = rgb(210, 180, 100), N = rgb(90, 230, 255), O = rgb(220, 255, 255) } },
	eclipse_scale = { kind = "scale", pal = { M = rgb(25, 20, 35), D = rgb(10, 8, 15), N = rgb(255, 190, 70), T = rgb(160, 80, 255) } },
	-- boots
	wayfarers_boots = { kind = "boots", pal = { M = rgb(125, 85, 55), L = rgb(165, 120, 80), D = rgb(55, 40, 30), T = rgb(200, 170, 110), N = rgb(200, 170, 110) } },
	riftwalker_greaves = { kind = "greaves", pal = { M = rgb(70, 60, 110), L = rgb(130, 110, 190), D = rgb(35, 30, 55), T = rgb(190, 175, 230), N = rgb(200, 90, 255) } },
	ironroot_sabatons = { kind = "sabatons", pal = { M = rgb(100, 100, 108), L = rgb(150, 150, 160), D = rgb(55, 55, 60), T = rgb(110, 80, 50), N = rgb(120, 220, 90) } },
	-- gloves
	gravegrip_gauntlets = { kind = "gauntlets", pal = { M = rgb(80, 80, 88), L = rgb(225, 215, 190), D = rgb(45, 45, 52), T = rgb(160, 150, 130), N = rgb(140, 255, 200) } },
	tempest_grips = { kind = "grips", pal = { M = rgb(50, 80, 140), L = rgb(110, 150, 220), D = rgb(28, 40, 75), T = rgb(220, 225, 240), N = rgb(120, 220, 255) } },
	thornmother_grasp = { kind = "thorns", pal = { M = rgb(50, 75, 45), L = rgb(90, 130, 70), D = rgb(28, 40, 25), T = rgb(140, 100, 70), N = rgb(255, 70, 190) } },
}
-- (an item without a look of its own: its slot's plain shape)
local SLOT_KIND = { weapon = "sword", armor = "plate", helmet = "helm", accessory = "ring", boots = "boots", gloves = "gauntlets" }
local DEFAULT_PAL: Pal = {
	M = rgb(140, 140, 150), L = rgb(200, 200, 210), D = rgb(80, 80, 90), E = rgb(220, 225, 235), T = rgb(214, 170, 70),
	H = rgb(80, 55, 35), P = rgb(214, 170, 70), N = rgb(255, 213, 128), O = rgb(255, 245, 220), K = rgb(20, 18, 22), S = rgb(230, 230, 220),
}
local GLOWS = { N = true, O = true }
local GLOW_OF: { [string]: Color3 } = {
	Common = rgb(200, 200, 200), Uncommon = rgb(110, 230, 130), Rare = rgb(90, 170, 255),
	Epic = rgb(200, 120, 255), Legendary = rgb(255, 185, 60), Mythic = rgb(255, 70, 95),
}

function GearModels.Look(id: string): Look
	local look = LOOKS[id]
	if look then return look end
	local item = EquipmentData.Get(id)
	return { kind = if item then (SLOT_KIND[item.slot] or "ring") else "ring", pal = DEFAULT_PAL }
end

local function palette(look: Look): { [string]: any }
	local out = {}
	for ch, col in pairs(DEFAULT_PAL) do out[ch] = { color = look.pal[ch] or col, neon = GLOWS[ch] == true } end
	return out
end

-- ── Sprites (rows top → bottom; `grip` = the row held in the hand) ──────────
local SPRITES: { [string]: { rows: { string }, depth: number, grip: number? } } = {
	sword = { depth = 2, grip = 14, rows = {
		"...E...", "..ELE..", "..ELE..", "..ENE..", "..ELE..", "..ENE..", "..ELE..", "..ENE..", "..ELE..", "..ELE..",
		"TTTTTTT", ".T.H.T.", "...H...", "...H...", "...H...", "..TPT..", "...T...",
	} },
	greatsword = { depth = 2, grip = 16, rows = {
		"....E....", "...ELE...", "..ELLLE..", "..ELNLE..", ".EELLLE..", "..ELNLEE.", "..ELLLE..", ".EELNLE..",
		"..ELLLEE.", "..ELNLE..", "..ELLLE..", "..ELLLE..", "TTTTTTTTT", "T..DHD..T", "...DHD...", "....H....",
		"....H....", "...TPT...", "....T....",
	} },
	rapier = { depth = 1, grip = 14, rows = {
		"...E...", "...E...", "...E...", "...L...", "...E...", "...L...", "...E...", "...L...", "...E...", "...N...",
		"...E...", ".TTTTT.", "T..H..T", "T..H..T", ".T.H.T.", "..TTT..", "...P...",
	} },
	bow = { depth = 1, grip = 10, rows = {
		".....N..", "....MS..", "...M.S..", "..D..S..", ".M...S..", ".M...S..", "M....S..", "D....S..", "HH...S..",
		"HH...S..", "D....S..", "M....S..", ".M...S..", ".M...S..", "..D..S..", "...M.S..", "....MS..", ".....N..",
	} },
	staff = { depth = 2, grip = 12, rows = {
		"..NNN..", ".NOOON.", ".NOOON.", "..NNN..", ".T...T.", "..TTT..", "...H...", "...H...", "...D...", "...H...",
		"...H...", "...H...", "...D...", "...H...", "...H...", "...H...", "...H...", "...D...", "...H...", "..TTT..", "...T...",
	} },
	axe = { depth = 2, grip = 14, rows = {
		"...T......", "...H.MMM..", "...HMMMMM.", "...HMMMMEE", "..THTMNMEE", "..THTMMMEE", "...HMMMMEE", "...HMMMMM.",
		"...H.MMM..", "...H......", "...H......", "...D......", "...H......", "...H......", "...H......", "...D......",
		"..TTT.....", "...T......",
	} },
	trident = { depth = 2, grip = 15, rows = {
		"E..E..E", "E..E..E", "L..L..L", "L..L..L", "L..L..L", "LL.L.LL", ".LLLLL.", "..TNT..", "...H...", "...H...",
		"...D...", "...H...", "...H...", "...H...", "...D...", "...H...", "...H...", "...H...", "...D...", "...H...", "..TTT..",
	} },
	plate = { depth = 3, rows = {
		"TT.MMMMMM.TT", "TTTMLLLLMTTT", "TTMMLMMLMMTT", ".TMMMNNMMMT.", "..MMMNNMMM..", "..DMMMMMMD..", "..DMMMMMMD..",
		"..TTTTTTTT..", "..DDDTTDDD..", "..DD.DD.DD..", "..D..DD..D..",
	} },
	mantle = { depth = 3, rows = {
		"....DDDD....", "...DMMMMD...", "..DMKKKKMD..", "..DMKKKKMD..", ".DMMMKKMMMD.", "DMMMMTTMMMMD", "DMMMMMMMMMMD",
		"DMMDMMMMDMMD", "DMMDMMMMDMMD", "DMDMMMMMMDMD", "DM.DMMMMD.MD", "N...NNNN...N",
	} },
	leathers = { depth = 3, rows = {
		"MM......MM", "MMMDDDDMMM", "MMMMDDMMMM", ".MTMMMMTM.", ".MMTMMTMM.", ".MMMTTMMM.", ".MMMTTMMM.", ".MMTMMTMM.",
		".TTTTTTTT.", ".DD.NN.DD.", ".D......D.",
	} },
	scales = { depth = 3, rows = {
		"TT.MLMLML.TT", "TTTLMLMLMTTT", "TTMLMLMLMLTT", ".TLMLNNLMLT.", "..MLMNNMLM..", "..LMLMLMLM..", "..MLMLMLML..",
		"..TTTTTTTT..", "..LMLDDLML..", "..ML.DD.ML..", "..L..DD..L..",
	} },
	robes = { depth = 3, rows = {
		"...DDDDD...", "..DMMMMMD..", ".DMMTNTMMD.", "DMMMTMTMMMD", "DM.MMTMM.MD", "DM.MMTMM.MD", "D..TTTTT..D",
		"...MMTMM...", "...MMTMM...", "..MMMTMMM..", "..MMMTMMM..", ".MMMMTMMMM.", ".MMMMTMMMM.", ".NNNNNNNNN.",
	} },
	core = { depth = 3, rows = {
		"TT.DDDDDD.TT", "TTTDMMMMDTTT", "TTDMNMMNMDTT", ".TDMMNNMMDT.", "..DNNOONND..", "..DMMNNMMD..", "..DMNMMNMD..",
		"..TTTTTTTT..", "..DDDNNDDD..", "..DD.DD.DD..", "..D..DD..D..",
	} },
	helm = { depth = 5, rows = {
		"...TTT...", "..MMTMM..", ".MMMTMMM.", "MMMMTMMMM", "MMKNNNKMM", "MMMMMMMMM", "MDMMMMMDM", "MD.MMM.DM", "MD.....DM",
	} },
	crown = { depth = 3, rows = {
		"N....N....N", "T....T....T", "T...TNT...T", "TT.TTTTT.TT", "TTTTTTTTTTT", "TNTTNTNTTNT", "DDDDDDDDDDD",
	} },
	veil = { depth = 4, rows = {
		"...MMM...", "..MMMMM..", ".MMLLLMM.", ".MLKKKLM.", "MMKKNKKMM", "MMKKKKKMM", "MLMKKKMLM", "ML.MMM.LM", "M.L...L.M", "T.......T",
	} },
	pendant = { depth = 2, rows = {
		"T.......T", ".T.....T.", "..T...T..", "...TTT...", "...TNT...", "..NNONN..", ".NNOOONN.", ".NNOONNN.", "..NNNNN..", "...NNN...", "....N....",
	} },
	charm = { depth = 3, rows = {
		"....NN...", "...N.N...", "....D....", ".MM.D.MM.", "MMMMDMMMM", "MMMTMTMMM", "MMMMTMMMM", ".MMMMMMM.", "..MMMMM..", "...MMM...", "....M....",
	} },
	relic = { depth = 4, rows = {
		"...TTT...", "...T.T...", "..TTTTT..", ".DMMMMMD.", ".MNNNNNM.", ".MNOOONM.", ".MNOOONM.", ".MNNONNM.", ".MNNNNNM.", ".DMMMMMD.", "..TTTTT..", ".TTTTTTT.",
	} },
	boots = { depth = 3, rows = {
		"TTTTT...", "MMMMM...", "MLMMM...", "MMMMM...", "MMMMM...", "MMMMMM..", "MMMMMMMM", "MMMMMMMM", "DDDDDDDD",
	} },
	greaves = { depth = 3, rows = {
		"TTTTTT..", "LMNMMT..", "TMMMMM..", ".MNMM...", ".MMMM...", ".LMMMM..", "LMMMMMMM", "MMMMMMLM", "DDDDDDDD",
	} },
	sabatons = { depth = 3, rows = {
		"DDDDD...", "LLLLL...", "MMMMM...", "LLLLL...", "MNMMM...", "LLLLLL..", "MMMMMMMT", "LLNLLLLT", "DDDDDDDD",
	} },
	gauntlets = { depth = 3, rows = {
		".L.L.L..", ".L.L.L..", ".LLLLL.L", ".MMMMMMM", ".MDMMMM.", ".MMMMMM.", ".TNTTNT.", "TMMMMMMT", "TMMMMMMT", "TTTTTTTT",
	} },
	grips = { depth = 3, rows = {
		".M.M.M..", ".M.M.M..", ".MMMMM.M", ".MMNMMMM", ".MNMMMM.", ".NMMMMM.", ".TTTTTT.", "TMNMMNMT", "TMMMMMMT", "TTTTTTTT",
	} },
	thorns = { depth = 3, rows = {
		"T..T..T.", ".M.M.M..", ".M.M.M..", ".MMMMM.M", "TMMMMMMM", ".MLMMMMT", "TMMMMMM.", ".DNDDND.", "TMMMMMMT", "DDDDDDDD",
	} },
}

-- ── Builders ────────────────────────────────────────────────────────────────
local function spriteGroups(kind: string, look: Look): { any }
	local s = SPRITES[kind]
	local g = K.group()
	local yOff = if s.grip then s.grip - #s.rows else 0
	K.sprite(g, s.rows, palette(look), s.depth, math.floor(s.depth / 2), 0, yOff)
	if kind == "boots" or kind == "greaves" or kind == "sabatons" then
		-- the pair: the second boot behind and a little to the side
		local g2 = K.group(CFrame.new(-2, 0, -4))
		K.sprite(g2, s.rows, palette(look), s.depth, 0, 0, 0)
		return { g2, g }
	end
	return { g }
end

local function paint(look: Look, ch: string): any
	return { color = look.pal[ch] or DEFAULT_PAL[ch], neon = GLOWS[ch] == true }
end

local SHAPES: { [string]: (Look) -> { any } } = {}

-- a ring standing up, a cluster of gems set on top
SHAPES.ring = function(look)
	local g = K.group()
	K.disc(g, 4.2, 2, function(_, _, d)
		if d < 2.6 then return nil end
		return if d > 3.6 then paint(look, "D") else paint(look, "T")
	end)
	K.sprite(g, { ".N.", "NON", ".N." }, { N = paint(look, "N"), O = paint(look, "O") }, 3, 1, 0, 4)
	return { g }
end
-- a badge: a rim, its field, a raised arrowhead
SHAPES.sigil = function(look)
	local g = K.group()
	K.disc(g, 4.3, 2, function(_, _, d)
		return if d > 3.4 then paint(look, "T") elseif d > 2.6 then paint(look, "D") else paint(look, "M")
	end)
	K.sprite(g, { "..N..", ".NNN.", "NN.NN", "..N..", "..N..", ".N.N." }, { N = paint(look, "N") }, 1, 1, 0, -3)
	return { g }
end
-- a coin on a short chain, its face marked
SHAPES.coin = function(look)
	local g = K.group()
	K.disc(g, 4.3, 2, function(x, y, d)
		if d > 3.5 then return paint(look, "D") end
		if d > 3 then return paint(look, "T") end
		return paint(look, "M")
	end)
	K.sprite(g, { ".NNN.", "N....", ".NNN.", "....N", ".NNN." }, { N = paint(look, "N") }, 1, 1, 0, -2)
	K.sprite(g, { "D.D", ".D.", "D.D" }, { D = paint(look, "D") }, 1, 0, 0, 5)
	return { g }
end
-- a black scale ringed by a golden corona, a violet glint
SHAPES.scale = function(look)
	local g = K.group()
	K.disc(g, 4.6, 2, function(x, y, d)
		if d > 3.7 then return if (x + y) % 2 == 0 then paint(look, "N") else nil end
		if d > 2.9 then return paint(look, "N") end
		return if x > 0 and y > 0 and d > 1.5 then paint(look, "D") else paint(look, "M")
	end)
	K.set(g, -1, 1, 1, look.pal.T, true)
	K.set(g, -2, 2, 1, look.pal.T, true)
	return { g }
end
-- a floating ring of light with short rays
SHAPES.halo = function(look)
	local g = K.group(CFrame.Angles(math.rad(65), 0, 0))
	K.disc(g, 5, 1, function(_, _, d)
		if d < 3.5 then return nil end
		return if d > 4.4 then paint(look, "T") else paint(look, "N")
	end)
	local rays = K.group()
	for _, p in ipairs({ { 0, 5 }, { 0, -5 }, { 5, 0 }, { -5, 0 } }) do
		K.set(rays, p[1], p[2] + 2, 0, look.pal.O, true)
	end
	return { g, rays }
end

local templates: { [string]: Model } = {}

-- The item on its own (a clone of its template).
function GearModels.Icon(id: string): Model?
	local t = templates[id]
	if not t then
		local item = EquipmentData.Get(id)
		if not item then return nil end
		local look = GearModels.Look(id)
		local groups = if SHAPES[look.kind] then SHAPES[look.kind](look) else spriteGroups(look.kind, look)
		t = K.render(id, groups, true)
		templates[id] = t
	end
	return t:Clone()
end

-- ── The Armory's gear (PowerGear) ───────────────────────────────────────────
-- A rolled piece has a slot, a base word ("Fang", "Aegis", "Signet") and a
-- rarity: the base picks the shape, the rarity the metal and the glow.
local POWER_KIND: { [string]: string } = {
	Fang = "greatsword", Edge = "sword", Talon = "rapier", Reaver = "axe", Cleaver = "greatsword",
	Plate = "plate", Mantle = "mantle", Hauberk = "scales", Aegis = "core", Cuirass = "leathers",
	Band = "ring", Loop = "ring", Signet = "sigil", Coil = "ring",
	Idol = "charm", Sigil = "sigil", Totem = "relic", Relic = "relic",
}
local POWER_SLOT_KIND = { weapon = "sword", armor = "plate", ring = "ring", charm = "charm" }
-- each grade's metal: main, light, dark, trim
local POWER_METAL: { [string]: { Color3 } } = {
	Common = { rgb(120, 116, 112), rgb(165, 160, 155), rgb(70, 66, 64), rgb(120, 85, 55) },
	Uncommon = { rgb(140, 150, 145), rgb(195, 205, 200), rgb(80, 90, 85), rgb(90, 150, 95) },
	Rare = { rgb(150, 170, 200), rgb(215, 228, 245), rgb(85, 100, 130), rgb(190, 195, 210) },
	Epic = { rgb(95, 70, 140), rgb(170, 140, 220), rgb(50, 35, 80), rgb(205, 175, 90) },
	Legendary = { rgb(215, 165, 60), rgb(255, 225, 140), rgb(140, 95, 30), rgb(255, 245, 210) },
	Mythic = { rgb(60, 20, 30), rgb(150, 50, 65), rgb(30, 10, 15), rgb(240, 200, 120) },
}

-- The base word of a rolled piece's name ("Keen Talon" → "Talon").
local function baseOf(name: string): string
	local last = string.match(name, "(%a+)%s*$")
	return last or name
end

function GearModels.PowerLook(item: { slot: string, rarity: string, name: string }): (string, Look)
	local kind = POWER_KIND[baseOf(item.name)] or POWER_SLOT_KIND[item.slot] or "ring"
	local m = POWER_METAL[item.rarity] or POWER_METAL.Common
	local glow = GLOW_OF[item.rarity] or rgb(255, 213, 128)
	local pal: Pal = {
		M = m[1], L = m[2], D = m[3], T = m[4], E = m[2]:Lerp(Color3.new(1, 1, 1), 0.3),
		H = rgb(70, 48, 35), P = glow, N = glow, O = glow:Lerp(Color3.new(1, 1, 1), 0.6), K = rgb(18, 14, 18), S = rgb(230, 225, 210),
	}
	return `{kind}|{item.rarity}`, { kind = kind, pal = pal }
end

-- A rolled piece as its brick model (a clone of its shape-and-grade template).
function GearModels.PowerIcon(item: { slot: string, rarity: string, name: string }): Model?
	local key, look = GearModels.PowerLook(item)
	local t = templates["power|" .. key]
	if not t then
		local groups = if SHAPES[look.kind] then SHAPES[look.kind](look) else spriteGroups(look.kind, look)
		t = K.render(key, groups, true)
		templates["power|" .. key] = t
	end
	return t:Clone()
end

return GearModels
