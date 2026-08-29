local ClassManager  = require(script:WaitForChild("ClassManager"))
local PlayerManager = require(script:WaitForChild("PlayerManager"))
local WeaponManager = require(script:WaitForChild("WeaponManager"))

print("[Server] Initializing SoloProject Game Server...")

ClassManager.Init()
PlayerManager.Init()
WeaponManager.Init()

-- Equip the correct weapon whenever a player confirms their class.
ClassManager.OnClassSelected(function(player: Player, classId: string)
	WeaponManager.EquipWeapon(player, classId)
end)

print("[Server] Game Server initialized successfully. Ready for players.")
