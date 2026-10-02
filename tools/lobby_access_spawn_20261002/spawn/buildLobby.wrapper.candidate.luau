local function buildLobby()
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
end
