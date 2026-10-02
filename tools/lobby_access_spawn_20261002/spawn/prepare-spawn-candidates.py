#!/usr/bin/env python3
"""Build file-only spawn candidates from fresh authoritative Source/editor exports."""
import json, hashlib, pathlib, difflib
ROOT = pathlib.Path(__file__).resolve().parents[3]
BASE = ROOT / "artifacts/lobby-access-spawn-20261002/spawn-audit/candidate-baseline-sources.json"
OUT = ROOT / "tools/lobby_access_spawn_20261002/spawn"
doc = json.loads(BASE.read_text())
rows = {r["name"]: r for r in doc["rows"]}
for r in rows.values():
    body = r["source"].encode()
    assert hashlib.sha256(body).hexdigest() == r["expectedSha256"]
    assert len(body) == r["expectedBytes"]
    assert r["editorSourceParity"] is True

old_wrapper = '''local function buildLobby()
 return require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
end'''
new_wrapper = '''local function buildLobby()
 local lobby, spawn, stations = require(script.Parent:WaitForChild("TunnelLobbyBuilder")).Build(LOBBY_CENTER)
 if IS_RESERVED_ROUND_SERVER then return lobby, spawn, stations end
 -- Preserve the canonical pad/reference used by every join, reset and preview return.
 -- No lobby character is loaded until this synchronous startup wrapper returns.
 workspace:SetAttribute("LobbySpawnMigrationReady", false)
 workspace:SetAttribute("LobbySpawnMigrationError", nil)
 local originalSpawn = spawn.CFrame
 local ok, problem = pcall(function()
  local folder = script.Parent:FindFirstChild("LobbyReimaginedPreview")
  local builder = folder and folder:FindFirstChild("Builder")
  assert(builder and builder:IsA("ModuleScript"), "Revised lobby builder is missing")
  -- The original builder starts its shop asynchronously. The clone must wait
  -- for its existing completion marker, not merely the early-parented Model.
  local shop, deadline = nil, os.clock() + 20
  repeat
   shop = lobby:FindFirstChild("ZyntraShopDisplay")
   if shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0 then break end
   assert(lobby.Parent == workspace, "Lobby changed while waiting for its shop")
   task.wait(.05)
  until os.clock() >= deadline
  assert(shop and shop:IsA("Model") and (tonumber(shop:GetAttribute("ShopItemCount")) or 0) > 0,
   "Original lobby shop did not finish before revised lobby startup")
  local revised = require(builder).Build()
  assert(revised and revised:IsA("Model") and revised.Parent == workspace
   and revised.Name == "LobbyReimaginedPreview" and revised:GetAttribute("LobbyReimaginedOwned") == true
   and revised:GetAttribute("Ready") == true, "Revised lobby is not ready")
  local center = revised:GetAttribute("PreviewCenter")
  assert(center == Vector3.new(220, 30, -760), "Unexpected revised lobby center")
  local position = center + Vector3.new(0, .4, -100)
  local params = RaycastParams.new()
  params.FilterType = Enum.RaycastFilterType.Include
  params.FilterDescendantsInstances = {revised}
  params.RespectCanCollide = true
  -- Cover every possible scatter offset; fail safely before moving the pad.
  for _, dx in ipairs({-2, 0, 2}) do
   for _, dz in ipairs({-2, 0, 2}) do
    local hit = workspace:Raycast(position + Vector3.new(dx, 12, dz), Vector3.new(0, -18, 0), params)
    assert(hit and hit.Instance.CanCollide and hit.Normal.Y > .7
     and math.abs(hit.Position.Y - position.Y) < 2, "Revised lobby spawn floor is incomplete")
   end
  end
  assert(spawn.Parent == lobby and lobby.Parent == workspace, "Canonical lobby spawn changed during startup")
  spawn.CFrame = CFrame.lookAt(position, center + Vector3.new(0, .4, 0))
  spawn:SetAttribute("LobbySpawnFloorModelName", "LobbyReimaginedPreview")
  spawn:SetAttribute("LobbySpawnRevision", 4)
  workspace:SetAttribute("LobbySpawnMigrationReady", true)
 end)
 if not ok then
  spawn.CFrame = originalSpawn
  spawn:SetAttribute("LobbySpawnFloorModelName", nil)
  spawn:SetAttribute("LobbySpawnRevision", nil)
  workspace:SetAttribute("LobbySpawnMigrationError", tostring(problem))
  warn("[GameManager] Revised lobby startup failed; retaining safe original spawn: " .. tostring(problem))
 end
 return lobby, spawn, stations
end'''
gm = rows["GameManager"]["source"]
assert gm.count(old_wrapper) == 1
gm = gm.replace(old_wrapper, new_wrapper, 1)

bootstrap = '''-- GameManager builds and validates the public revised lobby before loading characters.
-- This script only reports bounded readiness; it never races a second Build transaction.
if game.PrivateServerId ~= "" and game.PrivateServerOwnerId == 0 then
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
'''
access = rows["Level6PreviewAccess"]["source"]
old_stream = '''		if not streamReady(player, landing, "ServerLobby") then error("Lobby streaming confirmation timed out") end'''
new_stream = '''		local floorModelName = if spawn:GetAttribute("LobbySpawnFloorModelName") == "LobbyReimaginedPreview" then "LobbyReimaginedPreview" else "ServerLobby"
		if not streamReady(player, landing, floorModelName) then error("Lobby streaming confirmation timed out") end'''
assert access.count(old_stream) == 1
access = access.replace(old_stream, new_stream, 1)
transport = rows["Level6PreviewTransport"]["source"]
old_models = '''		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby") then return end'''
new_models = '''		or (modelName ~= "Level 6 Generated World" and modelName ~= "ServerLobby"
			and modelName ~= "LobbyReimaginedPreview") then return end'''
assert transport.count(old_models) == 1
transport = transport.replace(old_models, new_models, 1)
bodies = {"GameManager": gm, "Bootstrap": bootstrap, "Level6PreviewAccess": access, "Level6PreviewTransport": transport}
manifest = {"mode":"file-only-candidates-no-Studio-mutation","studioId":doc["studioId"],
 "placeId":doc["placeId"],"universeId":doc["universeId"],"canonicalSpawnPath":"Workspace.ServerLobby.LobbySpawn",
 "targetPosition":[220,30.4,-860],"targetLookAt":[220,30.4,-760],"rows":[]}
for name, body in bodies.items():
    row = rows[name]
    ext = "LocalScript" if name == "Level6PreviewTransport" else "Script"
    path = OUT / (name + "." + ext + ".candidate.luau")
    path.write_bytes(body.encode())
    baseline = OUT / (name + "." + ext + ".baseline.luau")
    baseline.write_bytes(row["source"].encode())
    delta = "".join(difflib.unified_diff(row["source"].splitlines(keepends=True),body.splitlines(keepends=True),
        fromfile=row["path"]+".baseline",tofile=row["path"]+".candidate"))
    (OUT / (name + ".scoped.diff")).write_text(delta)
    manifest["rows"].append({"path":row["path"],"class":row["class"],
      "baselineSha256":row["expectedSha256"],"baselineBytes":row["expectedBytes"],
      "candidateSha256":hashlib.sha256(body.encode()).hexdigest(),"candidateBytes":len(body.encode()),
      "candidate":str(path.relative_to(ROOT)),"baseline":str(baseline.relative_to(ROOT))})
(OUT / "candidate-manifest.json").write_text(json.dumps(manifest,indent=2)+"\n")
(OUT / "buildLobby.wrapper.candidate.luau").write_text(new_wrapper+"\n")
print(json.dumps(manifest,indent=2))
