-- Pure mocked startup fixtures: no DataModel instance/property/Source writes.
local WRAPPER = [===[local function buildLobby()
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
]===]
local originalGlobals = getfenv(0)
local function runCase(name, config)
 local clock, waits, rays, revisedBuilds, oldBuilds = 0, 0, 0, 0, 0
 local messages = {}
 local fakeWorkspace = {Attrs={}}
 function fakeWorkspace:SetAttribute(k,v) self.Attrs[k]=v end
 local oldLobby = {Parent=fakeWorkspace}
 local originalCF = CFrame.lookAt(Vector3.new(0,30.4,-860),Vector3.new(0,30.4,-760))
 local spawn = {CFrame=originalCF,Parent=oldLobby,Attrs={}}
 function spawn:SetAttribute(k,v) self.Attrs[k]=v end
 local shop = {Count=config.delayedShop and 0 or 10}
 function shop:IsA(class) return class=="Model" end
 function shop:GetAttribute(k) if k=="ShopItemCount" then return self.Count end end
 function oldLobby:FindFirstChild(name) if name=="ZyntraShopDisplay" and not config.shopMissing then return shop end end
 local revised = {Parent=fakeWorkspace,Name="LobbyReimaginedPreview",Attrs={
  LobbyReimaginedOwned=not config.unowned,Ready=not config.notReady,
  PreviewCenter=config.wrongCenter and Vector3.new(221,30,-760) or Vector3.new(220,30,-760)}}
 function revised:IsA(class) return class=="Model" end
 function revised:GetAttribute(k) return self.Attrs[k] end
 local oldModule, newModule = {}, {}
 function newModule:IsA(class) return class=="ModuleScript" end
 local folder={}
 function folder:FindFirstChild(name) if name=="Builder" then return newModule end end
 local parent={}
 function parent:WaitForChild(name) assert(name=="TunnelLobbyBuilder"); return oldModule end
 function parent:FindFirstChild(name) if name=="LobbyReimaginedPreview" and not config.missingBuilder then return folder end end
 function fakeWorkspace:Raycast(origin,direction,params)
  rays+=1
  assert(params.RespectCanCollide==true and params.FilterDescendantsInstances[1]==revised)
  assert(direction==Vector3.new(0,-18,0))
  if config.missingFloor and rays==5 then return nil end
  return {Instance={CanCollide=not config.nonSolidFloor},Normal=Vector3.new(0,config.tiltedFloor and .6 or 1,0),
   Position=Vector3.new(origin.X,config.wrongHeight and 34 or 30,origin.Z)}
 end
 local stations={}
 local env=setmetatable({
  script={Parent=parent}, workspace=fakeWorkspace,
  RaycastParams={new=function() return {} end},
  IS_RESERVED_ROUND_SERVER=config.reserved==true, LOBBY_CENTER=Vector3.new(0,30,-760),
  os={clock=function() return clock end},
  task={wait=function(dt)
   clock+=dt; waits+=1; assert(waits<2000,"Fixture loop was not bounded")
   if config.delayedShop and clock>=.15 then shop.Count=10 end
  end},
  warn=function(message) table.insert(messages,message) end,
  require=function(module)
   if module==oldModule then return {Build=function(center)
    assert(center==Vector3.new(0,30,-760));oldBuilds+=1
    return oldLobby,spawn,stations
   end} end
   assert(module==newModule)
   return {Build=function()
    revisedBuilds+=1
    assert(shop.Count>0 and not config.shopMissing,"Built revision before complete original shop")
    if config.buildThrows then error("Injected revised build failure") end
    if config.changedPad then spawn.Parent={} end
    return revised
   end}
  end
 },{__index=originalGlobals})
 local loader,why=loadstring(WRAPPER.."\nreturn buildLobby","Spawn startup fixture: "..name)
 assert(loader,why);setfenv(loader,env)
 local build=loader()
 local gotLobby,gotSpawn,gotStations=build()
 assert(gotLobby==oldLobby and gotSpawn==spawn and gotStations==stations,"Canonical references changed")
 assert(oldBuilds==1,"Original lobby builder did not run exactly once")
 local expectedSuccess=config.expectSuccess==true
 if expectedSuccess then
  assert(fakeWorkspace.Attrs.LobbySpawnMigrationReady==true and fakeWorkspace.Attrs.LobbySpawnMigrationError==nil, name..": "..tostring(fakeWorkspace.Attrs.LobbySpawnMigrationError))
  assert((spawn.CFrame.Position-Vector3.new(220,30.4,-860)).Magnitude<.001)
  assert((spawn.CFrame.LookVector-Vector3.new(0,0,1)).Magnitude<.001,"Facing points to wrong lobby")
  assert(spawn.Attrs.LobbySpawnFloorModelName=="LobbyReimaginedPreview" and spawn.Attrs.LobbySpawnRevision==4)
  assert(rays==9 and revisedBuilds==1 and #messages==0)
 else
  assert(spawn.CFrame==originalCF,"Unsafe fallback moved canonical spawn")
  assert(spawn.Attrs.LobbySpawnFloorModelName==nil and spawn.Attrs.LobbySpawnRevision==nil)
  if config.reserved then
   assert(revisedBuilds==0 and rays==0 and waits==0 and #messages==0,"Reserved round built revised lobby")
  else
   assert(fakeWorkspace.Attrs.LobbySpawnMigrationReady==false and type(fakeWorkspace.Attrs.LobbySpawnMigrationError)=="string")
   assert(#messages==1,"Failure did not produce single clear warning")
  end
 end
 if config.shopMissing then assert(clock>=20 and clock<20.2 and revisedBuilds==0,"Shop timeout was not bounded") end
 return {name=name,passed=true,success=expectedSuccess,oldBuilds=oldBuilds,revisedBuilds=revisedBuilds,
  solidFloorChecks=rays,waitIterations=waits,simulatedSeconds=clock}
end
local cases={
 {"public-ready",{expectSuccess=true}},
 {"public-delayed-shop",{expectSuccess=true,delayedShop=true}},
 {"reserved-no-revision-build",{reserved=true}},
 {"shop-missing-bounded-fallback",{shopMissing=true}},
 {"builder-missing-safe-fallback",{missingBuilder=true}},
 {"build-fails-safe-fallback",{buildThrows=true}},
 {"unowned-model-rejected",{unowned=true}},
 {"not-ready-model-rejected",{notReady=true}},
 {"unexpected-center-rejected",{wrongCenter=true}},
 {"missing-scatter-floor-rejected",{missingFloor=true}},
 {"non-solid-floor-rejected",{nonSolidFloor=true}},
 {"steep-floor-rejected",{tiltedFloor=true}},
 {"incorrect-floor-height-rejected",{wrongHeight=true}},
 {"changed-canonical-pad-rejected",{changedPad=true}}
}
local results={}
for _,c in ipairs(cases) do table.insert(results,runCase(c[1],c[2])) end
return game:GetService("HttpService"):JSONEncode({
 scope="Pure fake tables; no Studio instance, Source, property or global setting changes",
 placeId=game.PlaceId,universeId=game.GameId,at=DateTime.now():ToIsoDate(),
 wrapperCandidateSHA256="a87238d2189715a54f2db02a0b75d1d534a7c04841ab938628735294515a01c6",
 passed=true,caseCount=#results,results=results})
