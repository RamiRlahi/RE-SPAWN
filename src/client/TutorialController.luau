--!strict
--[[
	TutorialController.luau
	The tutorial's popups (Tutorial.luau sends TutorialStep { step, room, of }):
	a card at the top of the screen explaining what's in front of you: the
	controls as you land, then each room's kind as you walk in, and what a
	cleared fight room leaves.

	Nothing stops while a card is up: you play on and DO what it says. Each
	card goes when it's done:
	  move / dash / sprint / tab   you did it
	  attack   you hit a straw training dummy (the first room's: Tutorial.luau)
	  skills   every one of your four skills has hit a dummy (a skill that
	           can't hit anything, a heal or a buff, counts once used); the
	           card ticks them off as you go
	  claim   you took the room's reward (a tome choice came up)
	  next    you've moved on (the next popup arrived: next room, room cleared)
	  (none)  read: it goes by itself after a while
	Enter skips a card.

	The boss's card waits for its entrance cinematic to finish. Keys are shown
	as you have them bound (Settings), e.g. [Right Click].

	In the lobby, until the tutorial is done ("TutorialDone"): the way to the
	DUNGEON gate's portal, arrows streaming along the ground to it, a START
	HERE sign over it and a line at the top of the screen (walking in starts
	the tutorial: Tutorial.luau).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local SkillData = require(Shared:WaitForChild("SkillData"))
local RunScope = require(Shared:WaitForChild("RunScope"))

local TutorialController = {}

local player = Players.LocalPlayer

local GOLD = Color3.fromRGB(226, 196, 132)
local GOLD_BRIGHT = Color3.fromRGB(255, 222, 140)
local INK = Color3.fromRGB(16, 12, 18)
local PARCH = Color3.fromRGB(242, 236, 224)
local MUTED = Color3.fromRGB(160, 145, 120)
local DONE = Color3.fromRGB(140, 230, 140)
local SERIF = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)
local CARD_W = 380 -- (small: the tome choice, the shop and the fight stay readable)
local TOP = 128 -- (under the TIME SURVIVED plaque)
local MOVE_DIST = 14 -- studs walked to count as "moved"
local BOSS_WAIT = 4 -- seconds to wait for the boss's cinematic to start
local BOSS_INTRO = 6 -- and how long it lasts

-- ── Keys ────────────────────────────────────────────────────────────────────
local KEY_NAMES: { [string]: string } = {
	MouseButton1 = "Left Click", MouseButton2 = "Right Click", MouseButton3 = "Middle Click",
	LeftShift = "Shift", RightShift = "Shift", LeftControl = "Ctrl", Tab = "Tab", Space = "Space",
}
local function bound(action: string): string
	local k = player:GetAttribute("Keybind_" .. action)
	if typeof(k) ~= "string" or k == "" then k = SettingsConfig.DefaultSettings.keybinds[action] end
	return tostring(k)
end
local function isAction(input: InputObject, action: string): boolean
	local k = bound(action)
	if input.UserInputType == Enum.UserInputType.Keyboard then return input.KeyCode.Name == k end
	return input.UserInputType.Name == k
end
-- a key, drawn as a gold chip in the text
local function K(name: string): string
	return `<font color="#ffde8c"><b>[{name}]</b></font>`
end
local function A(action: string): string
	local k = bound(action)
	return K(KEY_NAMES[k] or k)
end
local function B(text: string): string return `<font color="#ffde8c"><b>{text}</b></font>` end

-- ── What each step says ─────────────────────────────────────────────────────
-- Each a list of cards { title, body, done? } (built when shown, so the keys
-- are current).
type Card = { title: string, body: string, done: string? }
local STEPS: { [string]: () -> { Card } } = {
	Start = function()
		return {
			{ title = "Welcome to the Proving Grounds",
				body = "A short dungeon that walks you through every kind of room, one at a time. Do what each card says to move on." },
			{ title = "Move", done = "move",
				body = `{K("W")}{K("A")}{K("S")}{K("D")} to walk around. Your character faces the mouse cursor: you aim with the mouse.` },
			{ title = "Attack", done = "attack",
				body = `Walk up to a {B("straw dummy")} and {A("PrimaryAttack")} to hit it (you attack where you aim). Hold it to keep attacking.` },
			{ title = "Skills", done = "skills",
				body = `{A("Skill1")} {A("Skill2")} {A("Skill3")} are your skills, {A("Ultimate")} your ultimate (the strongest, on a long cooldown). Try every one of them on the dummies: they never fall.\nHover a skill icon at the bottom of the screen to see what it does and which tomes suit it.` },
			{ title = "Dash", done = "dash",
				body = `{A("Dash")} dashes the way you're moving (or toward the cursor standing still). For a moment nothing can hit you: dash {B("through")} an attack that's about to land.` },
			{ title = "Sprint", done = "sprint",
				body = `{A("Sprint")} switches sprinting on and off, to cross a room quickly.` },
			{ title = "Onward", done = "next",
				body = "Each room's portals, on its far wall, light up once the room is cleared. This room is safe: walk into the glowing portal." },
		}
	end,
	Combat = function()
		return {
			{ title = "A fight", done = "next",
				body = `Defeat every enemy to clear the room.\nWatch the floor: {B("red markers")} show where an attack is about to land. Step out of them, or {A("Dash")} through.` },
		}
	end,
	["Combat:clear"] = function()
		return {
			{ title = "The room's reward", done = "claim",
				body = `A cleared fight room leaves a {B("reward orb")}. Walk up to it and {A("PrimaryAttack")} it: you level up and pick one of three {B("tomes")}, upgrades that stack for the rest of the run.` },
			{ title = "Your tomes", done = "tab",
				body = `Hold {K("Tab")} to look over the tomes you have (hover one to read it).` },
		}
	end,
	Treasure = function()
		return {
			{ title = "Treasure", done = "next",
				body = "No fight here: open the chest (walk up and use the prompt). It always holds gold, usually a tome, and now and then a curse. Then take the portal." },
		}
	end,
	Elite = function()
		return {
			{ title = "Elite fight", done = "next",
				body = `Tougher enemies, each with a special power named over its head: a harder fight, a better reward.\nIn a real run the clock at the top raises the {B("Threat")}: the longer you take, the stronger enemies get.` },
		}
	end,
	["Elite:clear"] = function()
		return {
			{ title = "Choose well", done = "claim",
				body = "Claim the reward. Some tomes are Boons: take the same Boon again to level it up, and at its top level it can evolve into something new." },
		}
	end,
	Shop = function()
		return {
			{ title = "The merchant", done = "next",
				body = `Spend {B("gold")} (under your health bar) on tomes, a healing potion, or the bell that rerolls the wares. Enemies and chests drop gold.\nYou've got 300 gold here: buy something.` },
		}
	end,
	Gamble = function()
		return {
			{ title = "The gambling den", done = "next",
				body = "Spin the Wheel of Fate (bet 25, 50 or 100 gold) for a chance at more, or try the Double-or-Nothing altar. Or keep your gold and walk on." },
		}
	end,
	Rest = function()
		return {
			{ title = "The Moonwell", done = "next",
				body = "Drink from the well to heal: its water drops as it heals, so leave some for your party. Offer coins for a blessing.\nIf you fall in battle you can revive once per run." },
		}
	end,
	Cursed = function()
		return {
			{ title = "The cursed altar", done = "next",
				body = `Clear the room, then choose. Accept the curse: lose {B("25% max health")} for the run, but take a {B("relic")} (pick one of three) and Epic-or-better gear.\nRelics are strong, with a cost of their own: yours show down the right of the screen.` },
		}
	end,
	Purge = function()
		return {
			{ title = "The purge shrine", done = "next",
				body = "Clear the room, then sacrifice a tome you don't want to the flames: fewer unwanted tomes, more of the ones you want." },
		}
	end,
	Boss = function()
		return {
			{ title = "The boss", done = "next",
				body = `Every attack it makes is {B("telegraphed")}: a marker grows on the floor before it strikes. Step out of it, or {A("Dash")} through at the last moment.\nAt half health it enrages. Save your ultimate {A("Ultimate")} for it.` },
		}
	end,
	["Boss:clear"] = function()
		return {
			{ title = "You did it", done = "next",
				body = `Step into the {B("golden portal")} to finish.\nIn a real run the boss's lift goes on to the next floor; every third floor offers a golden portal to {B("extract")} with your loot. Go deeper and the dungeon's Corruption rises: tougher enemies, better loot.` },
		}
	end,
}

local HINTS: { [string]: string } = {
	move = "Walk to continue", attack = "Hit a dummy to continue",
	dash = "Dash to continue", sprint = "Sprint to continue", tab = "Hold Tab to continue",
	claim = "Claim the reward to continue",
}

-- ── The card ────────────────────────────────────────────────────────────────
local gui: ScreenGui? = nil
local card: Frame? = nil
local scale: UIScale? = nil
local header: TextLabel? = nil
local titleL: TextLabel? = nil
local bodyL: TextLabel? = nil
local hintL: TextLabel? = nil

type Entry = { cards: { Card }, room: number, of: number }
local queue: { Entry } = {}
local current: Entry? = nil
local page = 1
local shownAt = 0
local startPos: Vector3? = nil
local finishing = false
-- (when you last pressed attack / a skill, and a dummy last took a hit)
local attackAt, dummyHitAt = -math.huge, -math.huge
local ATTACK_WINDOW, SKILL_WINDOW = 1.2, 3
-- The skills card: which of your four have been tried, and the last pressed.
local SKILL_ACTIONS = { "Skill1", "Skill2", "Skill3", "Ultimate" }
local tested: { [number]: boolean } = {}
local lastSkill, lastSkillAt = 0, -math.huge
-- (skills that never hit anything: they count once used)
local USE_ONLY: { [string]: boolean } = {
	["Heal"] = true, ["Gunslinger's Roll"] = true, ["Invisibility"] = true,
	["Parry"] = true, ["Seeker Barrage"] = true, ["Ice Clone"] = true,
}
local function skillConfig(i: number): any
	local classId = player:GetAttribute("SelectedClass")
	return if typeof(classId) == "string" then SkillData.GetSkill(classId, i) else nil
end
-- "[E] Fire Tornado ✔   [F] Phoenix Slam   ..." (ticked green as they're done)
local function checklist(): string
	local parts = {}
	for i, action in ipairs(SKILL_ACTIONS) do
		local cfg = skillConfig(i)
		local k = bound(action)
		local name = `[{KEY_NAMES[k] or k}] {if cfg then cfg.name else action}`
		table.insert(parts, if tested[i] then `<font color="#8ce68c">✔ {name}</font>` else name)
	end
	return table.concat(parts, "     ")
end

local function build()
	if gui then return end
	local g = Instance.new("ScreenGui")
	g.Name = "TutorialCards"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 40
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, TOP)
	f.Size = UDim2.fromOffset(CARD_W, 0)
	f.AutomaticSize = Enum.AutomaticSize.Y
	f.BackgroundColor3 = INK
	f.BackgroundTransparency = 0.12
	f.BorderSizePixel = 0
	f.Visible = false
	f.Parent = g
	card = f
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = f
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Thickness = 1.5
	stroke.Transparency = 0.2
	stroke.Parent = f
	local pad = Instance.new("UIPadding")
	pad.PaddingTop, pad.PaddingBottom = UDim.new(0, 7), UDim.new(0, 7)
	pad.PaddingLeft, pad.PaddingRight = UDim.new(0, 16), UDim.new(0, 16)
	pad.Parent = f
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 3)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = f
	local sc = Instance.new("UIScale")
	sc.Parent = f
	scale = sc
	local function text(name: string, order: number, font: Font, size: number, color: Color3): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.LayoutOrder = order
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, 0)
		l.AutomaticSize = Enum.AutomaticSize.Y
		l.FontFace = font
		l.TextSize = size
		l.TextColor3 = color
		l.TextWrapped = true
		l.RichText = true
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextYAlignment = Enum.TextYAlignment.Top
		l.TextStrokeTransparency = 0.7
		l.Parent = f
		return l
	end
	header = text("Header", 1, SERIF_BOLD, 9, MUTED)
	titleL = text("Title", 2, SERIF_BOLD, 15, GOLD_BRIGHT)
	bodyL = text("Body", 3, SERIF, 12, PARCH)
	hintL = text("Hint", 4, SERIF_BOLD, 10, MUTED)
end

local function currentCard(): Card?
	local cur = current
	return if cur then cur.cards[page] else nil
end

local function render()
	local cur = current
	local c = currentCard()
	if not cur or not c then return end
	;(header :: TextLabel).Text = `TUTORIAL  ·  ROOM {cur.room} / {cur.of}` .. (if #cur.cards > 1 then `  ·  {page} / {#cur.cards}` else "")
	;(titleL :: TextLabel).Text = c.title
	;(bodyL :: TextLabel).Text = c.body
	if c.done == "skills" then
		table.clear(tested)
		;(hintL :: TextLabel).Text = checklist() .. "\nEnter to skip"
	else
		local hint = HINTS[c.done or ""]
		;(hintL :: TextLabel).Text = (if hint then `▶ {hint}   ·   ` else "") .. "Enter to skip"
	end
	;(hintL :: TextLabel).TextColor3 = MUTED
	shownAt = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	startPos = if root then root.Position else nil
end

local showNext: () -> ()

-- The card's been done (or skipped): a beat in green, then the next.
local function complete(instant: boolean?)
	local cur = current
	if not cur or finishing then return end
	local function go()
		finishing = false
		if current ~= cur then return end
		if page < #cur.cards then
			page += 1
			render()
		else
			current = nil
			showNext()
		end
	end
	if instant then
		go()
		return
	end
	finishing = true
	;(hintL :: TextLabel).Text = "✔ Done"
	;(hintL :: TextLabel).TextColor3 = DONE
	task.delay(0.7, go)
end

showNext = function()
	build()
	local f = card :: Frame
	local nxt = table.remove(queue, 1)
	if not nxt then
		f.Visible = false
		return
	end
	current = nxt
	page = 1
	render()
	local cam = workspace.CurrentCamera
	local vp = if cam then cam.ViewportSize else Vector2.new(1280, 720)
	;(scale :: UIScale).Scale = math.min(1, (vp.X - 32) / CARD_W)
	if not f.Visible then
		f.Visible = true
		f.Position = UDim2.new(0.5, 0, 0, TOP - 30)
		TweenService:Create(f, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0.5, 0, 0, TOP) }):Play()
	end
end

local function push(step: string, room: number, of: number)
	local make = STEPS[step]
	if not make then return end
	-- (a card waiting for you to move on is done: you have)
	local c = currentCard()
	if c and c.done == "next" then
		current = nil
		finishing = false
	end
	table.insert(queue, { cards = make(), room = room, of = of })
	if not current then showNext() end
end

local function closeAll()
	table.clear(queue)
	current = nil
	finishing = false
	if card then card.Visible = false end
end

-- One of your skills tried: ticked off, and the card done once all four are.
local function tick(i: number)
	local c = currentCard()
	if not c or c.done ~= "skills" or tested[i] or finishing then return end
	tested[i] = true
	;(hintL :: TextLabel).Text = checklist() .. "\nEnter to skip"
	for k = 1, #SKILL_ACTIONS do
		if not tested[k] then return end
	end
	complete()
end

-- An action the card asks for, done.
local function did(kind: string)
	local c = currentCard()
	if c and c.done == kind then complete() end
end

-- ── The way to the portal (the lobby, until it's done) ───────────────────────
local CHEVRON = "rbxassetid://116498485433110" -- (ArcadeKit's: an arrow, white on clear)
type Guide = { beam: Beam, from: Attachment, anchor: Part, sign: BillboardGui, hint: ScreenGui }
local guide: Guide? = nil

local function dropGuide()
	local g = guide
	guide = nil
	if not g then return end
	g.beam:Destroy()
	g.from:Destroy()
	g.anchor:Destroy()
	g.sign:Destroy()
	g.hint:Destroy()
end

local function makeGuide(root: BasePart, portal: BasePart): Guide
	-- the portal end: at the foot of the gate's steps, on the plaza
	local anchor = Instance.new("Part")
	anchor.Name = "TutorialGuideEnd"
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.CFrame = CFrame.new(portal.Position - Vector3.new(0, portal.Size.Y / 2 - 0.3, 0) + portal.CFrame.LookVector * -2)
	anchor.Parent = workspace
	-- (both ends' axis up: the beam lies flat on the ground)
	local to = Instance.new("Attachment")
	to.Orientation = Vector3.new(0, 0, 90)
	to.Parent = anchor
	local from = Instance.new("Attachment")
	from.Position = Vector3.new(0, -2.8, 0) -- (at the feet)
	from.Orientation = Vector3.new(0, 0, 90)
	from.Parent = root
	local beam = Instance.new("Beam")
	-- (the arrows point toward Attachment0, and stream that way: to the portal)
	beam.Attachment0, beam.Attachment1 = to, from
	beam.Texture = CHEVRON
	beam.TextureMode = Enum.TextureMode.Static
	beam.TextureLength = 3
	beam.TextureSpeed = -1.4
	beam.Width0, beam.Width1 = 3.6, 3.6
	beam.FaceCamera = false
	beam.Brightness = 3
	beam.LightEmission = 1
	beam.LightInfluence = 0
	beam.Color = ColorSequence.new(Color3.fromRGB(255, 222, 140))
	beam.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.85, 0.1), NumberSequenceKeypoint.new(1, 0.6) })
	beam.Parent = root
	-- the sign over the gate
	local sign = Instance.new("BillboardGui")
	sign.Name = "TutorialStartSign"
	sign.Adornee = portal
	sign.Size = UDim2.fromOffset(260, 70)
	sign.StudsOffset = Vector3.new(0, 1, 0) -- (in the portal's glow)
	sign.AlwaysOnTop = true
	sign.LightInfluence = 0
	sign.Parent = player:WaitForChild("PlayerGui")
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 0.6)
	t.FontFace = SERIF_BOLD
	t.TextScaled = true
	t.TextColor3 = GOLD_BRIGHT
	t.TextStrokeTransparency = 0.2
	t.Text = "▼ START HERE ▼"
	t.Parent = sign
	local t2 = t:Clone()
	t2.Position = UDim2.fromScale(0, 0.6)
	t2.Size = UDim2.fromScale(1, 0.4)
	t2.TextColor3 = PARCH
	t2.Text = "Your training awaits"
	t2.Parent = sign
	-- the line at the top of the screen
	local hint = Instance.new("ScreenGui")
	hint.Name = "TutorialPortalHint"
	hint.ResetOnSpawn = false
	hint.IgnoreGuiInset = true
	hint.DisplayOrder = 40
	hint.Parent = player:WaitForChild("PlayerGui")
	local h = Instance.new("TextLabel")
	h.AnchorPoint = Vector2.new(0.5, 0)
	h.Position = UDim2.new(0.5, 0, 0, 70)
	h.Size = UDim2.fromOffset(620, 40)
	h.BackgroundColor3 = INK
	h.BackgroundTransparency = 0.2
	h.FontFace = SERIF_BOLD
	h.TextSize = 18
	h.TextColor3 = GOLD_BRIGHT
	h.Text = "Follow the arrows: walk into the portal to begin the tutorial"
	h.Parent = hint
	local hc = Instance.new("UICorner")
	hc.CornerRadius = UDim.new(0, 8)
	hc.Parent = h
	local hs = Instance.new("UIStroke")
	hs.Color = GOLD
	hs.Parent = h
	return { beam = beam, from = from, anchor = anchor, sign = sign, hint = hint }
end

local function guideStep()
	local want = player:GetAttribute("InHub") == true and player:GetAttribute("TutorialDone") == false
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local lobby = workspace:FindFirstChild("Lobby")
	local portal = lobby and lobby:FindFirstChild("Portal", true)
	if not want or not root or not (portal and portal:IsA("BasePart")) then
		dropGuide()
		return
	end
	local g = guide
	if g and g.from.Parent ~= root then
		dropGuide()
		g = nil
	end
	if not g then guide = makeGuide(root, portal :: BasePart) end
end

-- ── Wiring ──────────────────────────────────────────────────────────────────
function TutorialController.Init()
	build()
	task.spawn(function()
		while true do
			local ok, err = pcall(guideStep)
			if not ok then warn("[TutorialController] guide:", err) end
			task.wait(0.4)
		end
	end)
	UserInputService.InputBegan:Connect(function(input, gpe)
		if not current then return end
		if input.KeyCode == Enum.KeyCode.Return or input.KeyCode == Enum.KeyCode.KeypadEnter then
			complete(true)
			return
		end
		if gpe then return end
		if isAction(input, "PrimaryAttack") then attackAt = os.clock() end
		for i, action in ipairs(SKILL_ACTIONS) do
			if isAction(input, action) then
				lastSkill, lastSkillAt = i, os.clock()
				local cfg = skillConfig(i)
				if cfg and (cfg.damage == 0 or USE_ONLY[cfg.name]) then tick(i) end
			end
		end
		if isAction(input, "Dash") then did("dash") end
		if isAction(input, "Sprint") then did("sprint") end
		if input.KeyCode == Enum.KeyCode.Tab then did("tab") end
	end)
	-- walked far enough, a tome choice came up, a read card's time is up
	RunService.Heartbeat:Connect(function()
		-- (out of the way while a tome or relic is being chosen)
		if card then
			local hide = RunScope.Mine("TomesPaused") == true
			local want = current ~= nil and not hide
			if card.Visible ~= want then card.Visible = want end
		end
		local c = currentCard()
		if not c or finishing then return end
		if c.done == "move" then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root and startPos and (root.Position - startPos).Magnitude > MOVE_DIST then did("move") end
		elseif c.done == "attack" then
			if attackAt > shownAt and dummyHitAt >= attackAt and dummyHitAt - attackAt <= ATTACK_WINDOW then did("attack") end
		elseif c.done == "skills" then
			-- a dummy hit soon after a skill's key (it can take a moment to land),
			-- and not just a basic attack's since
			if lastSkill > 0 and lastSkillAt > shownAt and dummyHitAt >= lastSkillAt
				and dummyHitAt - lastSkillAt <= SKILL_WINDOW and not (attackAt > lastSkillAt and dummyHitAt - attackAt <= ATTACK_WINDOW) then
				tick(lastSkill)
			end
		elseif c.done == "claim" then
			if RunScope.Mine("TomesPaused") == true then did("claim") end
		elseif c.done == nil then
			if os.clock() - shownAt > math.clamp(#c.body / 20, 6, 12) then complete() end
		end
	end)
	-- the straw dummies: when one takes a hit
	local function watchDummy(m: Instance)
		local hum = m:FindFirstChildOfClass("Humanoid") or m:WaitForChild("Humanoid", 5)
		if not hum or not hum:IsA("Humanoid") then return end
		local last = hum.Health
		hum.HealthChanged:Connect(function(h: number)
			if h < last then dummyHitAt = os.clock() end
			last = h
		end)
	end
	CollectionService:GetInstanceAddedSignal("TrainingDummy"):Connect(function(m) task.spawn(watchDummy, m) end)
	for _, m in ipairs(CollectionService:GetTagged("TrainingDummy")) do task.spawn(watchDummy, m) end
	-- the boss's cinematic: its card waits for it
	local bossIntroAt = -math.huge
	Network.GetRemoteEvent(Network.Remotes.BossIntro).OnClientEvent:Connect(function()
		bossIntroAt = os.clock()
	end)
	Network.GetRemoteEvent(Network.Remotes.TutorialStep).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" or typeof(payload.step) ~= "string" then return end
		local step = payload.step :: string
		local room = tonumber(payload.room) or 1
		local of = tonumber(payload.of) or 1
		task.spawn(function()
			if step == "Start" then
				task.wait(1.5) -- (the loading cover lifts first)
			elseif step == "Boss" then
				local t0 = os.clock()
				while os.clock() - t0 < BOSS_WAIT and bossIntroAt < t0 - 0.5 do task.wait(0.1) end
				if bossIntroAt >= t0 - 0.5 then
					task.wait(math.max(0, BOSS_INTRO - (os.clock() - bossIntroAt)))
				end
			end
			if player:GetAttribute("InLobby") ~= false then return end
			push(step, room, of)
		end)
	end)
	-- back to the lobby (finished, left, fell): no cards left over
	player:GetAttributeChangedSignal("InLobby"):Connect(function()
		if player:GetAttribute("InLobby") ~= false then closeAll() end
	end)
end

return TutorialController
