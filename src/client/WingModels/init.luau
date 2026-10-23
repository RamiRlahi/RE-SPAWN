--[[
	WingModels (generated from the voxel wing models, *_wings_voxel.glb)
	WingModels.Get(look) → the wing set's data, or nil if it has no model.
	Each wing set is bricks on bones, flapped by the model's own animation:

	  length, frames   the flap loop (seconds) and its frames, evenly spaced
	  mats             { r, g, b, neon, transparency }
	  nodes            { parent (0 = none), x, y, z, name }: each bone's rest place
	                   on its parent (studs); 1 is the model, the rig's origin
	  anim[bone]       its place on its parent every frame: x, y, z and the
	                   3x3 rotation (rows), 12 numbers a frame (the flap is
	                   swept back, and set off the back, far enough never to
	                   pass through the body)
	  bones[bone]      rot (3x3 rows) of its bricks; boxes { x, y, z, sx, sy,
	                   sz, mat } and studs { x, y, z, side (+1 = the back),
	                   mat } in the bone's own space (studs)
	  sides            per wing: tip { bone, x, y, z } and its biggest bone,
	                   main { bone, centre xyz, size xyz }, for particles
--]]

local WingModels = {}
local cache = {}

function WingModels.Get(look: string): any
	if cache[look] == nil then
		local m = script:FindFirstChild(look)
		cache[look] = if m and m:IsA("ModuleScript") then require(m) :: any else false
	end
	return cache[look] or nil
end

return WingModels
