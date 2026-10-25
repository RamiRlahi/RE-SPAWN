--[[
	Mounts
	The reworked mounts, one file per tier, built with the shared BeastKit.
	WingsMounts hands over its rig helpers and takes back every builder:

	  require(Mounts)(helpers) → { [look]: () -> Rig }
--]]

return function(W: any): { [string]: () -> any }
	local K = require(script:WaitForChild("BeastKit"))(W)
	local out = {}
	for _, tier in ipairs({ "Rare", "Epic", "Legendary", "MythicCosmic", "MythicDivine", "Secret" }) do
		local m = script:FindFirstChild(tier)
		if m then
			for look, build in pairs(require(m)(K)) do out[look] = build end
		end
	end
	return out
end
