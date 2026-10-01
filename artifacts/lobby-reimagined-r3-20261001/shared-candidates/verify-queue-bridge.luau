-- Executes only the isolated adapter against local Lune instances, never Studio.
local fs = require('@lune/fs')
local luau = require('@lune/luau')
local rbx = require('@lune/roblox')
local serde = require('@lune/serde')
local source = fs.readFile('tools/lobby_reimagined/queue_bridge.ModuleScript.luau')
local gm = fs.readFile('artifacts/lobby-reimagined-r3-20261001/shared-candidates/ServerScriptService.GameManager.Script.luau')
luau.compile(source);luau.compile(gm)
local workspace = rbx.Instance.new('Workspace')
local bridge = luau.load('return function(workspace)\n'..source..'\nend')()(workspace)
local function instance(class, name, parent)
 local value=rbx.Instance.new(class);value.Name=name;value.Parent=parent;return value
end
local function fixture()
 local model=instance('Model','LobbyReimaginedPreview',workspace)
 model:SetAttribute('LobbyReimaginedOwned',true);model:SetAttribute('R3QueueRevision',3);model:SetAttribute('Ready',true)
 local zones={}
 for level=1,6 do
  local bay=instance('Model','QueueBay_Level'..level,model);bay:SetAttribute('CircularBayDiameter',60)
  local floor=instance('Part','ChamberFloor',bay);floor.Size=rbx.Vector3.new(60,1,60)
  for display=1,4 do
   local zone=instance('Part','QueueZone_'..display,bay)
   zone.Size=rbx.Vector3.new(14.8,1,14.8);zone.Anchored=true;zone.CanCollide=false;zone.CanTouch=false;zone.CanQuery=false
   zone:SetAttribute('R3QueueId',100+(level-1)*4+display);zone:SetAttribute('LevelNumber',level);zone:SetAttribute('QueueDisplayIndex',display)
   zone:SetAttribute('QueueDetectorShape','Circle');zone:SetAttribute('QueueRadius',7.18)
   local owner=instance('Model','RenderOwner_'..display,bay)
   local gui=instance('SurfaceGui','Status',owner)
   instance('TextLabel','QueueTitle',gui);instance('TextLabel','QueueSubtitle',gui)
   local ref=instance('ObjectValue','QueueRenderOwner',zone);ref.Value=owner
   table.insert(zones,zone)
  end
 end
 return model,zones
end
local checks={}
local function check(name, callback) callback();table.insert(checks,{name=name,passed=true}) end
check('Actual R3-only access predicate: Studio/DEV accepted; original zones unchanged',function()
 local guard=gm:match('local function playerInsideZone%(player, station, includeBusy%)\n (if station%.revisionOwned.- end)\n')
 assert(guard,'Missing actual installed-candidate access predicate')
 local make=luau.load('return function(RunService,DevAccess)\nreturn function(player,station)\n'..guard..'\nreturn true end end')()
 for _,owned in ipairs({false,true}) do for _,studio in ipairs({false,true}) do for _,allowed in ipairs({false,true}) do
  local admit=make({IsStudio=function() return studio end},{IsLevel6PreviewAllowed=function() return allowed end})
  assert(admit({}, {revisionOwned=owned}) == (not owned or studio or allowed))
 end end end
end)
check('24 descriptors, 12 public queues, original presentation index retained',function()
 local model=fixture();local rows=bridge.Build(model);assert(#rows==24)
 local public=0
 for i,row in ipairs(rows) do assert(row.index==100+i);assert(row.level==math.floor((i-1)/4)+1);assert(row.displayIndex==(i-1)%4+1);assert(row.revisionOwned and row.lobbyOwner==model);if not row.previewOnly then public+=1 end end
 assert(public==12);model:Destroy()
end)
for _,test in ipairs({
 {'unowned lobby',function(m) m:SetAttribute('LobbyReimaginedOwned',false) end},
 {'unready lobby',function(m) m:SetAttribute('Ready',false) end},
 {'wrong revision',function(m) m:SetAttribute('R3QueueRevision',2) end},
 {'wrong parent',function(m) m.Parent=instance('Folder','NotWorkspace',workspace) end},
 {'missing zone',function(_,z) z[24]:Destroy() end},
 {'duplicate id',function(_,z) z[24]:SetAttribute('R3QueueId',101) end},
 {'mismatched level',function(_,z) z[1]:SetAttribute('LevelNumber',6) end},
 {'mismatched display index',function(_,z) z[1]:SetAttribute('QueueDisplayIndex',4) end},
 {'physical detector',function(_,z) z[1].CanCollide=true end},
 {'radius outside bounds',function(_,z) z[1]:SetAttribute('QueueRadius',9) end},
 {'zone reparented below floor contract',function(_,z) z[1].Parent=instance('Model','WrongNesting',z[1].Parent) end},
 {'missing render owner',function(_,z) z[1]:FindFirstChild('QueueRenderOwner'):Destroy() end},
 {'render owner outside owned lobby',function(_,z) z[1]:FindFirstChild('QueueRenderOwner').Value.Parent=workspace end},
 {'missing title',function(_,z) z[1]:FindFirstChild('QueueRenderOwner').Value:FindFirstChild('QueueTitle',true):Destroy() end},
}) do
 check('rejects '..test[1],function() local m,z=fixture();test[2](m,z);assert(not pcall(bridge.Build,m));m:Destroy() end)
end
check('DEV endpoint guard accepts exact owned hosts and rejects public/foreign hosts',function()
 local m=fixture();local host=instance('Part','PreviewEntry',m);host:SetAttribute('R3DeveloperPreviewEntry',6)
 assert(bridge.IsPreviewEntry(host,6));assert(not bridge.IsPreviewEntry(host,5));assert(not bridge.IsPreviewEntry(host,3))
 assert(#bridge.GetPreviewEntries(m,6)==1);host.Parent=workspace;assert(not bridge.IsPreviewEntry(host,6));m:Destroy();host:Destroy()
end)
local report={schema='r3-queue-adapter-local-contract-v1',passed=true,checks=checks,syntaxOnlyForGameManager=true,executedStudio=false,limitations='Local adapter fixtures only. Real queue admission/cancellation/countdown/teleport, DEV preview streaming and multiplayer remain Play checks.'}
fs.writeFile('artifacts/lobby-reimagined-r3-20261001/shared-candidates/queue-contract-local-qa.json',serde.encode('json',report,true))
print(serde.encode('json',{passed=true,checks=#checks,gameManagerCompiled=true},true))
