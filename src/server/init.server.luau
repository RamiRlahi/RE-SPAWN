local ClassManager = require(script:WaitForChild("ClassManager"))
local PlayerManager = require(script:WaitForChild("PlayerManager"))

print("[Server] Initializing SoloProject Game Server...")

ClassManager.Init()
PlayerManager.Init()

print("[Server] Game Server initialized successfully. Ready for players.")
