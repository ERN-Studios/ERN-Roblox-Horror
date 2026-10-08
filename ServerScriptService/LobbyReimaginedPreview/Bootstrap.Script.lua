-- GameManager builds and validates the public revised lobby before loading characters.
-- This script only reports bounded readiness; it never races a second Build transaction.
-- SERVER_KIND_20261008: a reserved server can be a party's own lobby (Levels 5 and 6); that one has a lobby.
if require(script.Parent.Parent:WaitForChild("ServerKind")).IsRoundServer() then
 script:SetAttribute("PreviewReady", false)
 script:SetAttribute("BuildStatus", "Reserved round server")
 return
end
local began, deadline = os.clock(), os.clock() + 60
script:SetAttribute("BuildAttempts", 0)
script:SetAttribute("BuildStatus", "Waiting for authoritative lobby startup")
repeat
 local model = workspace:FindFirstChild("LobbyReimaginedPreview")
 local lobby = workspace:FindFirstChild("ServerLobby")
 local spawn = lobby and lobby:FindFirstChild("LobbySpawn")
 if workspace:GetAttribute("LobbySpawnMigrationReady") == true and model and model:IsA("Model")
  and model:GetAttribute("LobbyReimaginedOwned") == true and model:GetAttribute("Ready") == true
  and spawn and spawn:IsA("SpawnLocation") and spawn:GetAttribute("LobbySpawnRevision") == 4
  and spawn:GetAttribute("LobbySpawnFloorModelName") == model.Name then
  script:SetAttribute("PreviewReady", true)
  script:SetAttribute("PreviewError", nil)
  script:SetAttribute("BuildSeconds", os.clock() - began)
  script:SetAttribute("BuildStatus", "Public lobby ready")
  return
 end
 local problem = workspace:GetAttribute("LobbySpawnMigrationError")
 if type(problem) == "string" and problem ~= "" then
  script:SetAttribute("PreviewReady", false)
  script:SetAttribute("PreviewError", problem)
  script:SetAttribute("BuildStatus", "Safe original spawn retained")
  warn("[Lobby startup monitor] " .. problem)
  return
 end
 task.wait(.1)
until os.clock() >= deadline
script:SetAttribute("PreviewReady", false)
script:SetAttribute("PreviewError", "Authoritative revised lobby readiness timed out")
script:SetAttribute("BuildStatus", "Readiness timeout")
warn("[Lobby startup monitor] Authoritative revised lobby readiness timed out")
