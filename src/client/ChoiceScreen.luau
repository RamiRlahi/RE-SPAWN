--[[
	ChoiceScreen.luau
	The pick-one screen for tomes and relics, in one style:
	  • "BUFF SELECTION / CHOOSE ONE BUFF" for a level-up's tomes and boons:
	    each a toy-brick book in its colour, its emblem glowing on the cover;
	  • "RELIC SELECTION / CHOOSE ONE RELIC" for a relic found: each relic as
	    its own toy-brick model (BrickModels).
	Every choice floats over a glowing pedestal in a beam of its colour, with a
	card under it (name, what it does, a badge: BASE / UNLOCKABLE / BOON LV /
	relic rarity) and SKIP (REROLL) at the bottom.

	Lives inside TomeController's choice overlay (so the cursor / reticle /
	"waiting for…" handling is shared).

	  local screen = ChoiceScreen.Create(parent, onChoose(id), onReroll())
	  screen.Show(choices, rerollsRemaining, lockDuration)
	  screen.Hide()
--]]

local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BrickModels = require(script.Parent:WaitForChild("BrickModels"))
local TomeData = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("TomeData"))

local ChoiceScreen = {}

local FONT = Enum.Font.Arcade
local GOLD = Color3.fromRGB(255, 200, 60)
local GOLD_L = Color3.fromRGB(255, 235, 150)
local GOLD_D = Color3.fromRGB(150, 95, 20)
local INK = Color3.fromRGB(12, 8, 18)
local PANEL = Color3.fromRGB(14, 12, 22)
local Z = 40 -- above the tome overlay's own layers

-- Designed at 1600×900, scaled to the screen.
local W, H = 1600, 900
local MODEL_SIZE = 8 -- a model's longest side in the viewport, in studs

type Shown = { model: Model, column: TextButton, hover: boolean, phase: number, book: boolean }
type Look = { theme: Color3, badge: string, badgeColor: Color3, model: Model, book: boolean }

-- A tome's accent, pushed bright and saturated for the light beam.
local function vivid(c: Color3): Color3
	local h, s, v = c:ToHSV()
	return Color3.fromHSV(h, math.min(1, s * 1.35 + 0.15), math.max(v, 0.92))
end

-- What a choice looks like: its colour, its badge and its 3D model.
local function lookFor(choice: any): Look
	if choice.category == "Relic" then
		local info = BrickModels.RelicInfo(choice.id)
		return {
			theme = info.theme,
			badge = string.upper(info.rarity) .. (if choice.classId then " - CLASS" else ""),
			badgeColor = BrickModels.RARITY[info.rarity] or info.theme,
			model = BrickModels.Relic(choice.id) or BrickModels.Tome(choice.id, info.theme),
			book = false,
		}
	end
	local theme = vivid(TomeData.AccentFor(choice.id))
	local badge = if choice.category == "Boon" then `BOON - LV {choice.level or 1}/{choice.maxLevel or 3}`
		elseif choice.category == "Unlockable" then "UNLOCKABLE"
		elseif choice.category == "Gunslinger" then "GUNSLINGER"
		else "BASE"
	return { theme = theme, badge = badge, badgeColor = theme, model = BrickModels.Tome(choice.id, TomeData.AccentFor(choice.id)), book = true }
end

-- The pixel font has plain ASCII only: swap the few other characters the
-- tome / relic texts use.
local function ascii(str: string): string
	return (str:gsub("×", "x"):gsub("·", "-"):gsub("—", "-"):gsub("–", "-"):gsub("’", "'"))
end

local function new(class: string, props: { [string]: any }, parent: Instance?): any
	local inst = Instance.new(class)
	for k, v in pairs(props) do (inst :: any)[k] = v end
	if parent then inst.Parent = parent end
	return inst
end

local function text(parent: Instance, str: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local label = new("TextLabel", {
		BackgroundTransparency = 1,
		Font = FONT,
		Text = ascii(str),
		TextSize = size,
		TextColor3 = color,
		TextStrokeColor3 = INK,
		TextStrokeTransparency = 0.2,
		ZIndex = Z + 4,
	}, parent)
	for k, v in pairs(props or {}) do (label :: any)[k] = v end
	return label
end

-- A small diamond (a square turned 45°).
local function diamond(parent: Instance, pos: UDim2, size: number, color: Color3, hollow: boolean?)
	local d = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = pos,
		Size = UDim2.fromOffset(size, size),
		Rotation = 45,
		BackgroundColor3 = color,
		BackgroundTransparency = if hollow then 1 else 0,
		BorderSizePixel = 0,
		ZIndex = Z + 5,
	}, parent)
	if hollow then new("UIStroke", { Color = color, Thickness = 2 }, d) end
	return d
end

-- A gold rule with diamonds at its ends and a big one in the middle.
local function ornament(parent: Instance, y: number, width: number)
	local line = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W / 2, y),
		Size = UDim2.fromOffset(width, 4),
		BackgroundColor3 = GOLD,
		BorderSizePixel = 0,
		ZIndex = Z + 4,
	}, parent)
	new("UIGradient", { Color = ColorSequence.new(GOLD_D, GOLD_L) , Rotation = 90 }, line)
	diamond(parent, UDim2.fromOffset(W / 2 - width / 2 - 14, y), 12, GOLD, true)
	diamond(parent, UDim2.fromOffset(W / 2 + width / 2 + 14, y), 12, GOLD, true)
	diamond(parent, UDim2.fromOffset(W / 2, y), 20, GOLD)
	diamond(parent, UDim2.fromOffset(W / 2, y), 9, INK)
end

-- A soft vertical glow (fades to nothing at the top and the sides).
local function glow(parent: Instance, pos: UDim2, size: UDim2, color: Color3, strength: number): Frame
	local f = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1),
		Position = pos,
		Size = size,
		BackgroundColor3 = color,
		BorderSizePixel = 0,
		ZIndex = Z + 1,
	}, parent)
	new("UIGradient", {
		Rotation = 90,
		Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 1),
			NumberSequenceKeypoint.new(0.6, 1 - strength * 0.6),
			NumberSequenceKeypoint.new(1, 1 - strength),
		}),
	}, f)
	return f
end

function ChoiceScreen.Create(parent: GuiObject, onChoose: (string) -> (), onReroll: () -> ())
	local root = new("Frame", {
		Name = "ChoiceSelection",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(6, 5, 14),
		BackgroundTransparency = 0.15,
		BorderSizePixel = 0,
		Visible = false,
		ZIndex = Z,
	}, parent)
	-- night-sky tint, darker at the edges
	new("UIGradient", {
		Color = ColorSequence.new(Color3.fromRGB(40, 30, 80), Color3.fromRGB(6, 5, 14)),
		Rotation = 90,
	}, root)

	local stage = new("Frame", {
		Name = "Stage",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(W, H),
		BackgroundTransparency = 1,
		ZIndex = Z,
	}, root)
	local scale = new("UIScale", {}, stage)
	local function fit()
		local cam = Workspace.CurrentCamera
		local v = if cam then cam.ViewportSize else Vector2.new(W, H)
		scale.Scale = math.min(v.X / W, v.Y / H)
	end

	-- ── Heading ─────────────────────────────────────────────────────────────
	ornament(stage, 58, 600)
	local title = text(stage, "", 78, GOLD, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(W / 2, 70),
		Size = UDim2.fromOffset(1000, 84),
	})
	new("UIGradient", { Color = ColorSequence.new(GOLD_L, GOLD), Rotation = 90 }, title)
	ornament(stage, 166, 560)
	local subtitle = text(stage, "", 30, GOLD_L, {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.fromOffset(W / 2, 184),
		Size = UDim2.fromOffset(600, 34),
	})

	-- ── SKIP (REROLL) ───────────────────────────────────────────────────────
	local reroll = new("TextButton", {
		Name = "Reroll",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromOffset(W / 2, 852),
		Size = UDim2.fromOffset(280, 54),
		BackgroundColor3 = PANEL,
		BorderSizePixel = 0,
		AutoButtonColor = false,
		Text = "",
		ZIndex = Z + 4,
	}, stage)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, reroll)
	local rerollStroke = new("UIStroke", { Color = Color3.fromRGB(200, 200, 215), Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, reroll)
	local rerollLabel = text(reroll, "SKIP (REROLL)", 24, Color3.fromRGB(235, 235, 245), { Size = UDim2.fromScale(1, 1), ZIndex = Z + 5 })
	diamond(stage, UDim2.fromOffset(W / 2 - 172, 852), 16, Color3.fromRGB(200, 200, 215), true)
	diamond(stage, UDim2.fromOffset(W / 2 + 172, 852), 16, Color3.fromRGB(200, 200, 215), true)
	reroll.MouseEnter:Connect(function()
		if reroll.Active then rerollStroke.Color = GOLD_L end
	end)
	reroll.MouseLeave:Connect(function() rerollStroke.Color = Color3.fromRGB(200, 200, 215) end)
	reroll.Activated:Connect(function()
		if not reroll.Active then return end
		reroll.Active = false
		onReroll()
	end)

	local columns = new("Frame", { Name = "Columns", Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, ZIndex = Z }, stage)

	-- ── Per-show state ──────────────────────────────────────────────────────
	local shown: { Shown } = {}
	local conns: { RBXScriptConnection } = {}
	local alive = 0 -- bumped on each Show/Hide so old timers stop

	local function clear()
		alive += 1
		for _, cn in ipairs(conns) do cn:Disconnect() end
		table.clear(conns)
		table.clear(shown)
		columns:ClearAllChildren()
	end

	local function buildColumn(choice: any, index: number, total: number): Shown
		local look = lookFor(choice)
		local theme = look.theme
		local bright = theme:Lerp(Color3.new(1, 1, 1), 0.35)
		-- up to 4 across; narrower columns when there are more
		local COL_GAP = if total >= 4 then 34 else 60
		local COL_W = math.min(400, (W - 120 - (total - 1) * COL_GAP) / total)
		local x0 = W / 2 - (total * COL_W + (total - 1) * COL_GAP) / 2 + (index - 1) * (COL_W + COL_GAP)

		local column = new("TextButton", {
			Name = choice.id,
			Position = UDim2.fromOffset(x0, 226),
			Size = UDim2.fromOffset(COL_W, 590),
			BackgroundTransparency = 1,
			AutoButtonColor = false,
			Active = false,
			Text = "",
			ZIndex = Z + 2,
		}, columns)
		local colScale = new("UIScale", { Scale = 1 }, column)

		-- Beam of light rising from the pedestal, and a halo behind the relic.
		glow(column, UDim2.fromOffset(COL_W / 2, 390), UDim2.fromOffset(COL_W * 0.55, 390), theme, 0.55)
		glow(column, UDim2.fromOffset(COL_W / 2, 390), UDim2.fromOffset(COL_W * 0.22, 360), bright, 0.6)
		local halo = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(COL_W / 2, 170),
			Size = UDim2.fromOffset(COL_W * 0.62, COL_W * 0.62),
			BackgroundColor3 = theme,
			BackgroundTransparency = 0.82,
			BorderSizePixel = 0,
			ZIndex = Z + 1,
		}, column)
		new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, halo)

		-- The 3D model and its pedestal.
		local vp = new("ViewportFrame", {
			Position = UDim2.fromOffset(0, 0),
			Size = UDim2.fromOffset(COL_W, 400),
			BackgroundTransparency = 1,
			Ambient = Color3.fromRGB(150, 150, 170),
			LightColor = Color3.new(1, 1, 1),
			LightDirection = Vector3.new(-0.6, -1, -0.8),
			ZIndex = Z + 3,
		}, column)
		local cam = new("Camera", { FieldOfView = 34 }, vp)
		cam.CFrame = CFrame.lookAt(Vector3.new(0, 8, 27), Vector3.new(0, 5.2, 0))
		vp.CurrentCamera = cam
		local pedestal = BrickModels.Pedestal(theme)
		pedestal:PivotTo(CFrame.new(0, -1.5, 0))
		pedestal.Parent = vp
		local model = look.model
		local _, ext = model:GetBoundingBox()
		local longest = math.max(ext.X, ext.Y, ext.Z)
		if longest > 0 then model:ScaleTo(MODEL_SIZE / longest) end
		model.Parent = vp

		-- The card.
		local card = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0),
			Position = UDim2.fromOffset(COL_W / 2, 386),
			Size = UDim2.fromOffset(COL_W - 16, 178),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.08,
			BorderSizePixel = 0,
			ZIndex = Z + 3,
		}, column)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, card)
		local cardStroke = new("UIStroke", { Color = theme, Thickness = 3, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
		for _, corner in ipairs({ Vector2.new(0, 0), Vector2.new(1, 0), Vector2.new(0, 1), Vector2.new(1, 1) }) do
			diamond(card, UDim2.fromScale(corner.X, corner.Y), 10, bright)
		end
		local name = text(card, string.upper(choice.name or choice.id), 30, bright, {
			Position = UDim2.fromOffset(12, 14),
			Size = UDim2.new(1, -24, 0, 34),
			TextScaled = true,
		})
		new("UITextSizeConstraint", { MaxTextSize = 30, MinTextSize = 14 }, name)
		local desc = text(card, choice.description or "", 20, theme:Lerp(Color3.new(1, 1, 1), 0.55), {
			Position = UDim2.fromOffset(18, 54),
			Size = UDim2.new(1, -36, 0, 96),
			TextWrapped = true,
			TextScaled = true,
			TextYAlignment = Enum.TextYAlignment.Top,
		})
		new("UITextSizeConstraint", { MaxTextSize = 20, MinTextSize = 12 }, desc)

		-- The badge sitting on the card's bottom edge.
		local rarityColor = look.badgeColor
		local badgeText = look.badge
		local badge = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.new(0.5, 0, 1, 0),
			Size = UDim2.fromOffset(math.min(COL_W - 40, #badgeText * 13 + 64), 34),
			BackgroundColor3 = PANEL,
			BorderSizePixel = 0,
			ZIndex = Z + 5,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 4) }, badge)
		new("UIStroke", { Color = rarityColor, Thickness = 2 }, badge)
		text(badge, badgeText, 20, rarityColor, { Size = UDim2.fromScale(1, 1), ZIndex = Z + 6 })
		diamond(badge, UDim2.new(0, 12, 0.5, 0), 10, rarityColor, true)
		diamond(badge, UDim2.new(1, -12, 0.5, 0), 10, rarityColor, true)

		-- Embers rising in the beam.
		local token = alive
		task.spawn(function()
			while token == alive and column.Parent do
				local s = math.random(3, 6)
				local spark = new("Frame", {
					AnchorPoint = Vector2.new(0.5, 0.5),
					Position = UDim2.fromOffset(COL_W / 2 + math.random(-1, 1) * math.random() * COL_W * 0.24, 360),
					Size = UDim2.fromOffset(s, s),
					BackgroundColor3 = bright,
					BorderSizePixel = 0,
					ZIndex = Z + 2,
				}, column)
				local life = math.random(12, 22) / 10
				TweenService:Create(spark, TweenInfo.new(life, Enum.EasingStyle.Linear), {
					Position = spark.Position - UDim2.fromOffset(math.random(-20, 20), math.random(160, 300)),
					BackgroundTransparency = 1,
				}):Play()
				task.delay(life, function() spark:Destroy() end)
				task.wait(0.12)
			end
		end)

		local entry: Shown = { model = model, column = column, hover = false, phase = index * 1.7, book = look.book }
		column.MouseEnter:Connect(function()
			if not column.Active then return end
			entry.hover = true
			TweenService:Create(colScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1.04 }):Play()
			cardStroke.Color = bright
			cardStroke.Thickness = 4
			halo.BackgroundTransparency = 0.7
		end)
		column.MouseLeave:Connect(function()
			entry.hover = false
			TweenService:Create(colScale, TweenInfo.new(0.15, Enum.EasingStyle.Quad), { Scale = 1 }):Play()
			cardStroke.Color = theme
			cardStroke.Thickness = 3
			halo.BackgroundTransparency = 0.82
		end)
		column.Activated:Connect(function()
			if not column.Active then return end
			onChoose(choice.id)
		end)

		-- Rise into place, one after another.
		column.Position = UDim2.fromOffset(x0, 286)
		colScale.Scale = 0.9
		task.delay((index - 1) * 0.12, function()
			TweenService:Create(column, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Position = UDim2.fromOffset(x0, 226) }):Play()
			TweenService:Create(colScale, TweenInfo.new(0.45, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		end)
		return entry
	end

	local screen = {}

	function screen.Show(choices: { any }, rerollsRemaining: number, lockDuration: number)
		clear()
		fit()
		root.Visible = true
		local relics = #choices > 0 and choices[1].category == "Relic"
		title.Text = if relics then "RELIC SELECTION" else "BUFF SELECTION"
		subtitle.Text = if relics then "CHOOSE ONE RELIC" else "CHOOSE ONE BUFF"
		for i, choice in ipairs(choices) do
			table.insert(shown, buildColumn(choice, i, #choices))
		end
		rerollLabel.Text = if rerollsRemaining > 1 then `SKIP (REROLL x{rerollsRemaining})` else "SKIP (REROLL)"
		reroll.Visible = rerollsRemaining > 0
		reroll.Active = false

		local cam = Workspace.CurrentCamera
		if cam then table.insert(conns, cam:GetPropertyChangedSignal("ViewportSize"):Connect(fit)) end
		-- Relics spin; books sway, tilted, showing their covers. Faster while hovered.
		local spin: { [Model]: number } = {}
		table.insert(conns, RunService.RenderStepped:Connect(function(dt)
			local now = os.clock()
			for _, s in ipairs(shown) do
				local a = (spin[s.model] or s.phase) + dt * (if s.hover then 2.4 else 0.9)
				spin[s.model] = a
				local bob = math.sin(now * 2 + s.phase) * 0.35
				local turn = if s.book
					then CFrame.Angles(math.rad(-10), math.sin(a) * 0.6, math.rad(-14))
					else CFrame.Angles(math.sin(now + s.phase) * 0.12, a, 0)
				s.model:PivotTo(CFrame.new(0, 6.3 + bob, 0) * turn)
			end
		end))

		-- (choices unlock after the lock, so a held click doesn't pick one by accident)
		local token = alive
		task.delay(lockDuration, function()
			if token ~= alive then return end
			for _, s in ipairs(shown) do s.column.Active = true end
			reroll.Active = rerollsRemaining > 0
		end)
	end

	function screen.Hide()
		clear()
		root.Visible = false
	end

	return screen
end

return ChoiceScreen
