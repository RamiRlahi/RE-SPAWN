local ClassManager      = require(script:WaitForChild("ClassManager"))
local PlayerManager     = require(script:WaitForChild("PlayerManager"))
local WeaponManager     = require(script:WaitForChild("WeaponManager"))
local AnimationManager  = require(script:WaitForChild("AnimationManager"))

print("[Server] Initializing SoloProject Game Server...")

ClassManager.Init()
PlayerManager.Init()
WeaponManager.Init()
AnimationManager.Init()

-- When a player confirms their class, equip their weapon.
ClassManager.OnClassSelected(function(player: Player, classId: string)
	WeaponManager.EquipWeapon(player, classId)
end)

print("[Server] Game Server initialized successfully. Ready for players.")
