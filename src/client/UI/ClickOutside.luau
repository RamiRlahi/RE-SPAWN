--!strict
--[[
	ClickOutside.luau
	A window closes on its close button or on a click OUTSIDE it, never on a
	click on its own body. A dim backdrop button behind (or around) a panel
	can't tell the two apart by itself: a click on a plain Frame falls through
	to the button under it, and a button also hears the clicks on its own
	children. So the backdrop asks here where the click landed.

	  ClickOutside.Bind(dim, panels, close)
	      dim     the full-screen backdrop button
	      panels  the window (or a list of them, or a function returning them)
	      close   called for a click that landed on none of them
--]]

local ClickOutside = {}

type Panels = GuiObject | { GuiObject } | () -> { GuiObject }

local function inside(panel: GuiObject, x: number, y: number): boolean
	if not panel.Parent or not panel.Visible then return false end
	local p, s = panel.AbsolutePosition, panel.AbsoluteSize
	return x >= p.X and x <= p.X + s.X and y >= p.Y and y <= p.Y + s.Y
end

function ClickOutside.Hit(panels: Panels, x: number, y: number): boolean
	local list: { GuiObject }
	if typeof(panels) == "function" then
		list = panels()
	elseif typeof(panels) == "table" then
		list = panels
	else
		list = { panels :: GuiObject }
	end
	for _, panel in ipairs(list) do
		if inside(panel, x, y) then return true end
	end
	return false
end

function ClickOutside.Bind(dim: GuiButton, panels: Panels, close: () -> ()): RBXScriptConnection
	return dim.Activated:Connect(function(input: InputObject?)
		-- (a mouse click or a tap has a place; a gamepad press on the backdrop
		-- itself has none, and closes)
		if input and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
			if ClickOutside.Hit(panels, input.Position.X, input.Position.Y) then return end
		end
		close()
	end)
end

return ClickOutside
