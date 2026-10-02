assert(game:GetService("RunService"):IsClient(),"Expected client Play context")
-- Read-only Play inspection. Does not require runtime modules, force queues,
-- change attributes, create live objects, move a camera/avatar, or invoke remotes.
local H = game:GetService("HttpService")
local R = game:GetService("RunService")
local EXPECT = H:JSONDecode([====[{"assets":{"materials":{"asphalt_road":{"color":{"originalURI":"rbxassetid://122629305677764","pngSHA256":"f25701af130f829777208c0b6679cb46f5418cb18f8c22d13d6b969f0b969482","uri":"rbxassetid://93427464566515"},"normal":{"originalURI":"rbxassetid://124637763157232","pngSHA256":"a8eb947bede56280fcbfe794c53959e901d8cabb517759c20afbdb8901d68831","uri":"rbxassetid://85799149505047"},"roughness":{"originalURI":"rbxassetid://102850469487873","pngSHA256":"d3a24522eedbfa79c1880b39d354ac702bfd6c90867e20ce80ddaf76266ab563","uri":"rbxassetid://106931720832992"}},"sidewalk_concrete":{"color":{"originalURI":"rbxassetid://103015335983029","pngSHA256":"c2ff43d2c7b6254589d99cbf5e09f727ec9faede72034fa054515a2c75fdb5f4","uri":"rbxassetid://137946858019381"},"normal":{"originalURI":"rbxassetid://134697002832773","pngSHA256":"0fcfeaf303ca9ac4a68e6f319a2f961594f0ac9fccdf140e8f47d026f8656ab6","uri":"rbxassetid://97239310145567"},"roughness":{"originalURI":"rbxassetid://117887403540614","pngSHA256":"881ae43eb5ef0b4ade620d2922a6966dae7864139a5ba2e788c866813ef1c2ee","uri":"rbxassetid://138358337027432"}},"tunnel_concrete":{"color":{"originalURI":"rbxassetid://75893473229833","pngSHA256":"174360cb5b0b750ccb4183fe393e29cf6f33149eb462786f8691ef2d56f0c130","uri":"rbxassetid://72127726815177"},"normal":{"originalURI":"rbxassetid://127271719715729","pngSHA256":"87693ee0d94628e58f20901849584d1eb6c35f71dc5c76fc4e200572b8f53c04","uri":"rbxassetid://112801222792719"},"roughness":{"originalURI":"rbxassetid://96772314871126","pngSHA256":"0e302cdf650a03989127b2e3cf05032348bfa4cbbaacdf1437b3f238097ae902","uri":"rbxassetid://70562685470916"}}},"sidewalkAtlas":{"chunkSHA256":"9f1e2113cecb2fb4697f28fbd3088ba3981cddd9ad72c98564730ecdbe17e50f","pngSHA256":"86447fb4c82082d2262327765a21ba8ef87c85b13dc53f524cbd130d5625d5f1","uri":"rbxassetid://85967831334476"}},"bays":[{"floorPosition":[-63,0.4,-80],"level":1,"yaw":1.5707963267948966},{"floorPosition":[63,0.4,-80],"level":2,"yaw":-1.5707963267948966},{"floorPosition":[-63,0.4,0],"level":3,"yaw":1.5707963267948966},{"floorPosition":[63,0.4,0],"level":4,"yaw":-1.5707963267948966},{"floorPosition":[-63,0.4,80],"level":5,"yaw":1.5707963267948966},{"floorPosition":[63,0.4,80],"level":6,"yaw":-1.5707963267948966}],"catalogSHA256":"a7b74111671b2baaa3dba2e8ac4602e1d5f9c9d6569436d4381cc90426c6f7d1","djConsoleSHA256":"9a48ba903b8105664d14d827caa0303497b79ea3e7e7a73467b3f6c046f28776","finalSourcePinsSHA256":"f975db7ff15edfae199325d3632fb321beb772378b83a96cb651d78e5ac80162","pads":[{"level":1,"position":[-72,1.62,-93.2]},{"level":1,"position":[-54,1.62,-93.2]},{"level":1,"position":[-72,1.62,-66.8]},{"level":1,"position":[-54,1.62,-66.8]},{"level":2,"position":[54,1.62,-93.2]},{"level":2,"position":[72,1.62,-93.2]},{"level":2,"position":[54,1.62,-66.8]},{"level":2,"position":[72,1.62,-66.8]},{"level":3,"position":[-72,1.62,-13.2]},{"level":3,"position":[-54,1.62,-13.2]},{"level":3,"position":[-72,1.62,13.2]},{"level":3,"position":[-54,1.62,13.2]},{"level":4,"position":[54,1.62,-13.2]},{"level":4,"position":[72,1.62,-13.2]},{"level":4,"position":[54,1.62,13.2]},{"level":4,"position":[72,1.62,13.2]},{"level":5,"position":[-72,1.62,66.8]},{"level":5,"position":[-54,1.62,66.8]},{"level":5,"position":[-72,1.62,93.2]},{"level":5,"position":[-54,1.62,93.2]},{"level":6,"position":[54,1.62,66.8]},{"level":6,"position":[72,1.62,66.8]},{"level":6,"position":[54,1.62,93.2]},{"level":6,"position":[72,1.62,93.2]}],"pbrCounts":{"asphalt_road":7,"sidewalk_concrete":26,"tunnel_concrete":15},"placeId":131311258779917,"rawManifestSHA256":"17b68efc473a0f100cf6ce6b9389332a5f2a87d82faf7694a0536a82483bc995","signs":[{"bladeLocalPosition":[-15,17,5.1],"bladeLocalSize":[0.86,2.95,9.2],"gatePosition":[-28.6,0.8,-80],"headerLocalPosition":[0,17.2,1.42],"headerLocalSize":[22.8,2.68,0.04],"level":1,"yaw":1.5707963267948966},{"bladeLocalPosition":[-15,17,5.1],"bladeLocalSize":[0.86,2.95,9.2],"gatePosition":[-28.6,0.8,0],"headerLocalPosition":[0,17.2,1.42],"headerLocalSize":[22.8,2.68,0.04],"level":3,"yaw":1.5707963267948966},{"bladeLocalPosition":[-15,17,5.1],"bladeLocalSize":[0.86,2.95,9.2],"gatePosition":[-28.6,0.8,80],"headerLocalPosition":[0,17.2,1.42],"headerLocalSize":[22.8,2.68,0.04],"level":5,"yaw":1.5707963267948966},{"bladeLocalPosition":[-15,17,5.1],"bladeLocalSize":[0.86,2.95,9.2],"gatePosition":[28.6,0.8,-80],"headerLocalPosition":[0,17.2,1.42],"headerLocalSize":[22.8,2.68,0.04],"level":2,"yaw":-1.5707963267948966},{"bladeLocalPosition":[-15,17,5.1],"bladeLocalSize":[0.86,2.95,9.2],"gatePosition":[28.6,0.8,0],"headerLocalPosition":[0,17.2,1.42],"headerLocalSize":[22.8,2.68,0.04],"level":4,"yaw":-1.5707963267948966},{"bladeLocalPosition":[-15,17,5.1],"bladeLocalSize":[0.86,2.95,9.2],"gatePosition":[28.6,0.8,80],"headerLocalPosition":[0,17.2,1.42],"headerLocalSize":[22.8,2.68,0.04],"level":6,"yaw":-1.5707963267948966}],"sources":[{"className":"ModuleScript","file":"tools/lobby_reimagined/polish_20261002/clutter/backing-v2/EndBlockades.ModuleScript.candidate.luau","new":false,"path":"ServerScriptService.LobbyReimaginedPreview.EndBlockades","sha256":"5c120357fad94d1274a7eb6e39c6ce0cbf996505246b3b6b5c68d3dfa5cff98a"},{"className":"LocalScript","file":"tools/lobby_reimagined/polish_20261002/bays/LobbyReimaginedQueueController.LocalScript.candidate.luau","new":false,"path":"StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController","sha256":"ecb544ac31e9cc343858a399cab93da1a0a71f861ee519643c7834d7848ae0ac"},{"className":"ModuleScript","file":"tools/lobby_reimagined/polish_20261002/materials/MaterialPolish.ModuleScript.luau","new":true,"path":"ServerScriptService.LobbyReimaginedPreview.MaterialPolish","sha256":"6b4ef80ea746c39c900c59f6311ad1f7ea862cb20b24aa1aaab85816ec71c54e"},{"className":"ModuleScript","file":"tools/lobby_reimagined/polish_20261002/bays/LobbyPolishBays.ModuleScript.candidate.luau","new":true,"path":"ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays","sha256":"1ab19711a303b058d033de6652da3d94c15e73f7e40b4e983036fa99c805bc2c"},{"className":"ModuleScript","file":"tools/lobby_reimagined/polish_20261002/scene/LobbyPolishScene.ModuleScript.candidate.luau","new":true,"path":"ServerScriptService.LobbyReimaginedPreview.LobbyPolishScene","sha256":"9dd927b5927249b42655c297d96a24a06c581c6fa9f01adac0ce7cde4e40746d"},{"className":"ModuleScript","file":"artifacts/lobby-polish-20261002/root/Builder.candidate.luau","new":false,"path":"ServerScriptService.LobbyReimaginedPreview.Builder","sha256":"37e9885eb0922da4126de82b3a82066cb435baf1aede3386d7e6ef5f241b3b8b"}],"themes":["OFFICE BACKROOMS · START HERE","POOLROOMS","MALL BACKROOMS","90s CINEMA · DEV ONLY","QUIET SUBURBS","MALL PARTY"],"universeId":10559217407}]====])
assert(R:IsRunning() and game.PlaceId==EXPECT.placeId and game.GameId==EXPECT.universeId,"Wrong Play context/place")
local model = assert(workspace:FindFirstChild("LobbyReimaginedPreview"),"Preview absent")
assert(model:IsA("Model") and model:GetAttribute("LobbyReimaginedOwned")==true
 and model:GetAttribute("LobbyVisualRevision")==4 and model:GetAttribute("Ready")==true,"Preview not ready/owned R4")
local center = model:GetAttribute("PreviewCenter")
assert(typeof(center)=="Vector3" and (center-Vector3.new(220,30,-760)).Magnitude<.002,"Preview center changed")
local report={schema="lobby-polish-readonly-play-inspection-v1",context=R:IsClient() and "Client" or "Server",
 catalogSHA256=EXPECT.catalogSHA256,expectedFinalSourcePinsSHA256=EXPECT.finalSourcePinsSHA256,candidateSources=EXPECT.sources,
 checks={},failures={},coverage={},checkCount=0,passedCount=0,
 scope="Actual instance/property observations only; screenshots, avatar walking, multiplayer and material shader rendering remain separate checks"}
local function ck(name,ok,detail)
 report.checkCount+=1
 if ok==true then report.passedCount+=1
 else table.insert(report.checks,{name=name,pass=false,detail=detail});table.insert(report.failures,name) end
 return ok
end
local function v(a) return Vector3.new(table.unpack(a)) end
local function close(a,b,tol)
 if typeof(a)=="Color3" and typeof(b)=="Color3" then
  return (Vector3.new(a.R,a.G,a.B)-Vector3.new(b.R,b.G,b.B)).Magnitude<(tol or .003)
 end
 return (a-b).Magnitude<(tol or .003)
end
local function near(a,b) return type(a)=="number" and math.abs(a-b)<.002 end
local function cfclose(a,b,tol)
 local x,y={a:GetComponents()},{b:GetComponents()}
 for i=1,12 do if math.abs(x[i]-y[i])>(tol or .003) then return false end end
 return true
end
local function texts(host)
 local out={};for _,x in ipairs(host:GetDescendants()) do
  if x:IsA("TextLabel") then table.insert(out,{text=x.Text,visible=x.Visible,name=x.Name}) end
 end;return out
end
local function label(host) return host and host:FindFirstChildWhichIsA("TextLabel",true) end
local function ybounds(host,frame)
 local lo,hi=math.huge,-math.huge
 for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
  local p=frame:PointToObjectSpace(host.CFrame:PointToWorldSpace(host.Size*Vector3.new(x,y,z)/2))
  lo,hi=math.min(lo,p.Y),math.max(hi,p.Y)
 end end end;return lo,hi
end
local function uri(content)
 return content.SourceType==Enum.ContentSourceType.Uri and content.Uri or "SOURCE:"..content.SourceType.Name
end
local pads=assert(model:FindFirstChild("PreviewQueuePads"),"Queue folder absent")
local signs=assert(model:FindFirstChild("LevelGateSigns"),"Gate signs absent")
local bays=assert(model:FindFirstChild("R4BayPresentation"),"Bay polish absent")
local scene=assert(model:FindFirstChild("R4ScenePresentation"),"Scene polish absent")
local stations,zones,bayframes={},{},{}
local qrows,srows={},{}
local nmodels=0
for _,x in ipairs(pads:GetChildren()) do if x:IsA("Model") and x.Name:match("^QueueBay_Level%d$") then nmodels+=1 end end
ck("six-bays",nmodels==6,nmodels)
for _,b in ipairs(EXPECT.bays) do
 local level=b.level;local bay=pads:FindFirstChild("QueueBay_Level"..level)
 assert(bay and bay:IsA("Model"),"Bay absent: "..level)
 local floor=bay:FindFirstChild("ChamberFloor")
 ck("bay-floor-"..level,floor and floor:IsA("BasePart") and floor.CanCollide and floor.Shape==Enum.PartType.Cylinder
  and close(floor.Position,center+v(b.floorPosition)) and bay:GetAttribute("CircularBayDiameter")==56)
 bayframes[level]=CFrame.new(center+Vector3.new(b.floorPosition[1],0,b.floorPosition[3]))*CFrame.Angles(0,b.yaw,0)
end
for _,s in ipairs(EXPECT.signs) do
 local level=s.level;local header=signs:FindFirstChild("LEVEL "..level.." Door Header")
 local arrow=signs:FindFirstChild("LEVEL "..level.." Projecting Arrow")
 assert(header and arrow,"Main sign absent: "..level)
 local gate=CFrame.new(center+v(s.gatePosition))*CFrame.Angles(0,s.yaw,0)
 ck("header-unchanged-"..level,cfclose(header.CFrame,gate*CFrame.new(v(s.headerLocalPosition)))
  and close(header.Size,v(s.headerLocalSize)) and label(header).Text=="LEVEL "..level)
 local arrowok=cfclose(arrow.CFrame,gate*CFrame.new(v(s.bladeLocalPosition))) and close(arrow.Size,v(s.bladeLocalSize))
 local faces={};for _,g in ipairs(arrow:GetChildren()) do if g:IsA("SurfaceGui") then faces[g.Face.Name]=label(g).Text end end
 ck("arrow-unchanged-"..level,arrowok and faces.Left=="←  LEVEL "..level and faces.Right=="LEVEL "..level.."  →",faces)
 local theme=bays:FindFirstChild("Level"..level.." Theme Ribbon")
 local instruction=bays:FindFirstChild("Level"..level.." Queue Instruction")
 assert(theme and instruction,"Polish sign absent: "..level)
 local expectedInstruction=level<=3 and "STEP ON A PAD · CHOOSE 1–6 PLAYERS"
  or level==4 and "DEV ONLY · TRIAL OR MAP PREVIEW" or "DEV ACCESS REQUIRED · PARTY QUEUE"
 ck("theme-"..level,label(theme).Text==EXPECT.themes[level] and cfclose(theme.CFrame,header.CFrame*CFrame.new(0,-1.95,.08)),label(theme).Text)
 ck("instruction-"..level,label(instruction).Text==expectedInstruction
  and cfclose(instruction.CFrame,header.CFrame*CFrame.new(0,-3.4,.08)),label(instruction).Text)
 local hlow,hhigh=ybounds(header,header.CFrame);local tlow,thigh=ybounds(theme,header.CFrame)
 local ilow,ihigh=ybounds(instruction,header.CFrame)
 ck("mounted-text-host-separation-"..level,hlow-thigh>.1 and tlow-ihigh>.1,{headerThemeGap=hlow-thigh,themeInstructionGap=tlow-ihigh})
 table.insert(srows,{level=level,header=texts(header),arrow=faces,theme=texts(theme),instruction=texts(instruction),
  approachCameraViewsRequired=true})
end
local perlevel={}
for _,p in ipairs(EXPECT.pads) do
 local level=p.level;perlevel[level]=(perlevel[level] or 0)+1;local index=perlevel[level]
 local bay=pads:FindFirstChild("QueueBay_Level"..level)
 local station=bay:FindFirstChild(string.format("Level%d Queue %02d",level,index))
 local zone=bay:FindFirstChild("QueueZone"..index);local id=100+(level-1)*4+index
 assert(station and zone,"Station/detector absent: "..id)
 table.insert(stations,station);table.insert(zones,zone)
 local ref=zone:FindFirstChild("QueueRenderOwner")
 ck("queue-id-reference-"..id,zone:GetAttribute("R3QueueId")==id and zone:GetAttribute("LevelNumber")==level
  and zone:GetAttribute("QueueDisplayIndex")==index and zone:GetAttribute("QueueRadius")==7.41
  and zone:GetAttribute("QueueDetectorShape")=="Circle" and zone.Anchored
  and not zone.CanCollide and not zone.CanTouch and not zone.CanQuery and ref and ref:IsA("ObjectValue") and ref.Value==station
  and close(zone.Position,center+v(p.position)) and cfclose(station:GetAttribute("HologramBase"),CFrame.new(center+v(p.position))))
 local number=bays:FindFirstChild(string.format("Level%d Pad %d Number",level,index))
 local inlay=bays:FindFirstChild(string.format("Level%d Pad %d Matte Inlay",level,index))
 ck("number-inlay-"..id,number and inlay and label(number).Text==tostring(index)
  and number:FindFirstChildWhichIsA("SurfaceGui").Face==Enum.NormalId.Top and not number.CanCollide
  and inlay.Shape==Enum.PartType.Cylinder and not inlay.CanCollide and not inlay.CanQuery)
 local bands=0;for _,x in ipairs(station:GetChildren()) do if x:IsA("MeshPart") and x:GetAttribute("HologramBandIndex") then bands+=1 end end
 ck("queue-presentation-contract-"..id,bands==10 and station:GetAttribute("QueueIdleRingAlpha")==.52
  and station:GetAttribute("QueueActiveRingAlpha")==.18 and station:GetAttribute("QueueHologramLowerAlpha")==.74,{bands=bands})
 local title=station:FindFirstChild("QueueTitle",true);local sub=station:FindFirstChild("QueueSubtitle",true)
 ck("queue-monitor-two-rows-"..id,title and sub and title.TextWrapped and sub.TextWrapped
  and title.Position.Y.Scale+title.Size.Y.Scale<=sub.Position.Y.Scale)
 table.insert(qrows,{id=id,level=level,index=index,active=station:GetAttribute("QueueActive")==true,
  detector=zone:GetFullName(),renderOwner=ref and ref.Value and ref.Value:GetFullName(),title=title and title.Text,
  subtitle=sub and sub.Text,titleVisible=title and title.Visible,subtitleVisible=sub and sub.Visible})
end
local actualzones=0
for _,x in ipairs(model:GetDescendants()) do if x:GetAttribute("R3QueueId")~=nil then actualzones+=1 end end
ck("exact-24-detectors",actualzones==24,actualzones)
report.queues,report.signs=qrows,srows
local props=bays:FindFirstChild("Theme Furniture");assert(props,"Theme furniture absent")
local minClear=math.huge;local propRows={}
for _,prop in ipairs(props:GetChildren()) do
 local level=prop:GetAttribute("BayLevel");local frame=assert(bayframes[level]);local low,high=Vector3.new(math.huge,math.huge,math.huge),Vector3.new(-math.huge,-math.huge,-math.huge)
 local descendants=prop:GetDescendants();if prop:IsA("BasePart") then table.insert(descendants,prop) end
 for _,part in ipairs(descendants) do if part:IsA("BasePart") then
  ck("bay-prop-physical-"..prop.Name,part.Anchored and not part.CanCollide and not part.CanTouch and not part.CanQuery)
  if part:IsA("MeshPart") then ck("bay-prop-double-sided-"..prop.Name,part.DoubleSided,{renderFidelity=part.RenderFidelity.Name}) end
  for _,x in ipairs({-1,1}) do for _,y in ipairs({-1,1}) do for _,z in ipairs({-1,1}) do
   local point=frame:PointToObjectSpace(part.CFrame:PointToWorldSpace(part.Size*Vector3.new(x,y,z)/2))
   low=Vector3.new(math.min(low.X,point.X),math.min(low.Y,point.Y),math.min(low.Z,point.Z))
   high=Vector3.new(math.max(high.X,point.X),math.max(high.Y,point.Y),math.max(high.Z,point.Z))
  end end end
 end end
 local clear=math.huge
 for _,zone in ipairs(zones) do if zone:GetAttribute("LevelNumber")==level then
  local p=frame:PointToObjectSpace(zone.Position);local dx=math.max(low.X-p.X,0,p.X-high.X);local dz=math.max(low.Z-p.Z,0,p.Z-high.Z)
  clear=math.min(clear,math.sqrt(dx*dx+dz*dz)-zone:GetAttribute("QueueRadius"))
 end end
 minClear=math.min(minClear,clear);ck("prop-outside-detectors-"..prop.Name,clear>.5,clear)
 table.insert(propRows,{name=prop.Name,level=level,family=prop:GetAttribute("SourceFamily"),nearestDetectorClearance=clear,
  renderFidelity=prop:IsA("MeshPart") and prop.RenderFidelity.Name or "Composite"})
end
ck("nineteen-prop-clones",#props:GetChildren()==19,#props:GetChildren())
report.propClearance={minimum=minClear,rows=propRows,scope="Bounding-box X/Z distance to actual circular detectors; not an avatar movement test"}
local lighting=assert(model:FindFirstChild("PreviewLighting"));local lightCount,enabled,tunnelCount,stageCount,disabledShop,warmEnds,warmShop=0,0,0,0,0,0,0
for _,x in ipairs(model:GetDescendants()) do if x:IsA("Light") then
 lightCount+=1;if x.Enabled then enabled+=1 end
 if x.Name=="ShopBoxGlow" and not x.Enabled then disabledShop+=1 end
end end
for _,p in ipairs(lighting:GetChildren()) do if p:IsA("BasePart") then
 local position=p.Position-center;local fill=p:FindFirstChild("Preview Fill")
 if p.Name=="Tunnel Lamp" then tunnelCount+=1;ck("tunnel-fill-"..tunnelCount,fill and math.abs(position.Y-17)<.002
  and near(fill.Brightness,.42) and fill.Range==28 and not fill.Shadows and close(fill.Color,Color3.fromRGB(226,230,213))) end
 if p.Name=="Stage Fill" then stageCount+=1;ck("stage-fill-"..stageCount,fill and math.abs(position.Y-10.5)<.002
  and math.abs(position.Z-111)<.002 and near(fill.Brightness,.62) and fill.Range==18 and not fill.Shadows) end
 if p.Name=="Warm Wall Fill" and math.abs(math.abs(position.Z)-120)<.002 then
  warmEnds+=1;ck("warm-end-fill-"..warmEnds,fill and near(fill.Brightness,.3) and fill.Range==21) end
 if p.Name=="Warm Wall Fill" and math.abs(position.X-27)<.002 and math.abs(position.Z+40)<.002 then
  warmShop+=1;ck("warm-shop-fill",fill and near(fill.Brightness,.3) and fill.Range==25) end
end end
ck("light-counts",lightCount==87 and enabled==77 and disabledShop==10 and tunnelCount==28 and stageCount==3,
 {total=lightCount,enabled=enabled,disabledShop=disabledShop,tunnel=tunnelCount,stage=stageCount})
ck("five-reused-warm-fills",warmEnds==4 and warmShop==1,{ends=warmEnds,shop=warmShop})
ck("scene-count-contract",scene:GetAttribute("ChangedExistingEmitters")==36 and scene:GetAttribute("StageGuidanceParts")==20
 and scene:GetAttribute("ShopCards")==10 and scene:GetAttribute("AddedPointLights")==0 and scene:GetAttribute("AddedColliders")==0)
local newPhysical=0;for _,root in ipairs({bays,scene}) do for _,x in ipairs(root:GetDescendants()) do
 if x:IsA("BasePart") and (x.CanCollide or x.CanTouch or x.CanQuery) then newPhysical+=1 end
end end;ck("presentation-has-zero-physical-parts",newPhysical==0,newPhysical)
local pbrCounts={};local atlasCount=0;local materialRows={}
for _,p in ipairs(model:GetDescendants()) do if p:IsA("MeshPart") then
 local key=p:GetAttribute("LobbyR4PBRMaterial")
 if key then
  pbrCounts[key]=(pbrCounts[key] or 0)+1;local appearances={}
  for _,a in ipairs(p:GetChildren()) do if a:IsA("SurfaceAppearance") then table.insert(appearances,a) end end
  ck("one-pbr-"..p:GetFullName(),#appearances==1)
  local a=appearances[1];local maps={}
  if a then
   for role,property in pairs({color="ColorMapContent",normal="NormalMapContent",roughness="RoughnessMapContent"}) do
    maps[role]=uri(a[property]);ck("pbr-map-"..key.."-"..role,maps[role]==EXPECT.assets.materials[key][role].uri)
   end
   ck("pbr-dielectric-"..key,a.MetalnessMapContent.SourceType==Enum.ContentSourceType.None and a.AlphaMode==Enum.AlphaMode.Overlay)
  end
  table.insert(materialRows,{name=p:GetFullName(),material=key,maps=maps})
 end
 if p:GetAttribute("BlenderSourceSHA256")==EXPECT.assets.sidewalkAtlas.chunkSHA256 then
  atlasCount+=1;ck("joint-atlas-"..atlasCount,uri(p.TextureContent)==EXPECT.assets.sidewalkAtlas.uri)
 end
end end
for key,n in pairs(EXPECT.pbrCounts) do ck("pbr-count-"..key,pbrCounts[key]==n,pbrCounts[key] or 0) end
ck("joint-atlas-count",atlasCount==14,atlasCount)
report.materials={counts=pbrCounts,jointAtlasCount=atlasCount,rows=materialRows,shaderRenderingVerified=false}
local shop=assert(model:FindFirstChild("R3ShopDisplay"));local focus=assert(model:FindFirstChild("PreviewShopPressurePlates"))
local originalLobby=workspace:FindFirstChild("ServerLobby");local original=originalLobby and originalLobby:FindFirstChild("ZyntraShopDisplay",true)
local cards=0;local shopRows={}
for _,stand in ipairs(shop:GetChildren()) do if stand:IsA("Model") and stand:GetAttribute("ShopItemKey") then
 cards+=1;local key=stand:GetAttribute("ShopItemKey");local box=stand:FindFirstChild("ShopHologramBox");local plate=stand:FindFirstChild("ShopPressurePlate")
 local copies={};for _,p in ipairs(focus:GetChildren()) do if p:GetAttribute("ShopItemKey")==key then table.insert(copies,p) end end
 ck("shop-focus-"..key,#copies==1 and plate and cfclose(copies[1].CFrame,plate.CFrame) and close(copies[1].Size,plate.Size))
 ck("shop-card-"..key,box and close(box.Size,Vector3.new(3.7,3.7,.55)) and box.ShopHologramCaption.Enabled==false
  and stand:FindFirstChild("ShopFixedNamePanel")~=nil)
 local oldStand
 if original then for _,s in ipairs(original:GetChildren()) do if s:GetAttribute("ShopItemKey")==key then oldStand=s;break end end end
 local sameAttributes=oldStand~=nil
 if oldStand then for attr,value in pairs(oldStand:GetAttributes()) do
  if attr:match("^Shop") and not attr:match("^ShopBob") and stand:GetAttribute(attr)~=value then sameAttributes=false end
 end end
 ck("shop-product-routing-attrs-"..key,sameAttributes,stand:GetAttributes())
 local art,oldArt={},{};for _,x in ipairs(box:GetDescendants()) do if x:IsA("ImageLabel") then table.insert(art,x.Image) end end
 local oldBox=oldStand and oldStand:FindFirstChild("ShopHologramBox")
 if oldBox then for _,x in ipairs(oldBox:GetDescendants()) do if x:IsA("ImageLabel") then table.insert(oldArt,x.Image) end end end
 table.sort(art);table.sort(oldArt);local artEqual=#art==#oldArt
 for i,value in ipairs(art) do if value~=oldArt[i] then artEqual=false end end
 ck("shop-art-retained-"..key,artEqual and #art>0,art)
 table.insert(shopRows,{key=key,kind=stand:GetAttribute("ShopItemKind"),art=art,name=label(stand.ShopFixedNamePanel).Text})
end end
ck("ten-shop-cards",cards==10,cards);report.shop=shopRows
local routeParams=RaycastParams.new();routeParams.FilterType=Enum.RaycastFilterType.Include
routeParams.FilterDescendantsInstances={model};routeParams.RespectCanCollide=true
local routes={};local function rayRoute(name,a,b)
 local hit=workspace:Raycast(a,b-a,routeParams);table.insert(routes,{name=name,clear=hit==nil,blockedBy=hit and hit.Instance:GetFullName()})
 ck("route-ray-"..name,hit==nil,hit and hit.Instance:GetFullName() or "clear")
end
rayRoute("central-road-eye-height",center+Vector3.new(0,4,-125),center+Vector3.new(0,4,101))
for level,frame in pairs(bayframes) do
 -- Client Coming Soon shutters are expected blockers, reported separately below.
 local gates=model:FindFirstChild("R4ClientDevGates");local gate=gates and gates:FindFirstChild("Level"..level.." Client Gate")
 if gate and gate:GetAttribute("PreviewAllowed")==false then
  table.insert(routes,{name="bay-"..level,expectedClientShutter=true})
 else rayRoute("bay-"..level,frame:PointToWorldSpace(Vector3.new(0,4,36)),frame:PointToWorldSpace(Vector3.new(0,4,0))) end
end
report.routes={rows=routes,scope="Thin horizontal collision rays only; avatar width, walking/stairs and return-lobby travel require actual interaction"}

assert(R:IsClient(),"Run this inspector in Client Play context")
local player=assert(game:GetService("Players").LocalPlayer)
local gates=model:FindFirstChild("R4ClientDevGates")
ck("client-gates-owned",gates and gates:GetAttribute("R4DevGateControllerOwned")==true)
local gateRows={}
for _,level in ipairs({5,6}) do
 local gate=gates and gates:FindFirstChild("Level"..level.." Client Gate")
 local allowed=gate and gate:GetAttribute("PreviewAllowed")
 local status=gate and gate:FindFirstChild("Mounted Access Subtitle")
 local shutter=gate and gate:FindFirstChild("Coming Soon Shutter")
 local header=signs:FindFirstChild("LEVEL "..level.." Door Header")
 local _,hhigh=ybounds(header,header.CFrame);local statusLow=status and ybounds(status,header.CFrame)
 ck("gate-status-"..level,gate and type(allowed)=="boolean" and status
  and label(status).Text==(allowed and "DEV PREVIEW" or "COMING SOON") and (shutter~=nil)==not allowed
  and (not shutter or shutter.CanCollide),{allowed=allowed,text=status and label(status).Text})
 ck("gate-status-header-separated-"..level,statusLow and statusLow-hhigh>.1,statusLow and statusLow-hhigh)
 for _,row in ipairs(qrows) do if row.level==level then
  ck("viewer-queue-label-"..row.id,allowed or (row.titleVisible==false and row.subtitleVisible==false))
 end end
 table.insert(gateRows,{level=level,allowed=allowed,status=status and label(status).Text,shutter=shutter~=nil})
end
report.viewer={name=player.Name,userId=player.UserId,reduceFlashing=player:GetAttribute("ReduceFlashing"),gates=gateRows}
-- Allow existing renderer tweens to settle. No state is changed to create coverage.
task.wait(1.15)
local active,idle=0,0;local animationRows={}
for index,station in ipairs(stations) do
 local isActive=station:GetAttribute("QueueActive")==true;local ring=station:FindFirstChild("Active Queue Ring")
 local expectedAlpha=isActive and .18 or .52;local expectedColor=isActive and Color3.fromRGB(123,231,197) or Color3.fromRGB(224,209,154)
 ck("observed-ring-"..index,ring and near(ring.Transparency,expectedAlpha) and close(ring.Color,expectedColor),
  {active=isActive,transparency=ring and ring.Transparency})
 local bandRows={};local previous=-math.huge;local faded=true
 for band=1,10 do
  local wall=station:FindFirstChild(string.format("HologramBand%02d",band));assert(wall,"Band absent")
  local full=wall:GetAttribute("HologramFullSize");local target=wall:GetAttribute("HologramFullCFrame")
  local alpha=.74+.26*((band-1)/9)^.85
  if isActive then
   if not near(wall.Transparency,alpha) or not close(wall.Size,full) or not cfclose(wall.CFrame,target) then faded=false end
   if wall.Transparency<previous then faded=false end
  else
   if not near(wall.Transparency,1) or not near(wall.Size.Y,.015)
    or not cfclose(wall.CFrame,station:GetAttribute("HologramBase")*CFrame.new(0,.008,0)) then faded=false end
  end
  previous=wall.Transparency;table.insert(bandRows,{index=band,transparency=wall.Transparency,height=wall.Size.Y})
 end
 ck((isActive and "active-upward-fade-" or "idle-collapsed-bands-")..index,faded,bandRows)
 if isActive then active+=1 else idle+=1 end
 table.insert(animationRows,{station=station:GetFullName(),active=isActive,bands=bandRows})
end
report.holograms={active=active,idle=idle,rows=animationRows,activeVisualCoverage=active>0,idleVisualCoverage=idle>0}
if active==0 then table.insert(report.coverage,"Active hologram fade was not observed; rerun during a real queue") end
local discs,needles={},{},{}
for _,p in ipairs(model:GetDescendants()) do if p:IsA("MeshPart") then
 if p:GetAttribute("PreviewVinylDisc")==true then table.insert(discs,{object=p,before=p.CFrame,pivot=p:GetAttribute("RecordPivot"),offset=p:GetAttribute("RecordMeshOffset")}) end
 if p:GetAttribute("BlenderSourceSHA256")==EXPECT.djConsoleSHA256 then table.insert(needles,{object=p,before=p.CFrame}) end
end end
ck("two-records-and-static-console",#discs==2 and #needles==1,{records=#discs,console=#needles})
local root=player.Character and player.Character:FindFirstChild("HumanoidRootPart")
local inRange=root and (root.Position-center).Magnitude<=220
local enabled=player:GetAttribute("ReduceFlashing")==false and inRange
local t0=os.clock();task.wait(3.05);local elapsed=os.clock()-t0
local sameEligibility=player:GetAttribute("ReduceFlashing")==false and root and root.Parent
 and (root.Position-center).Magnitude<=220
local vinylRows={}
for _,row in ipairs(discs) do
 local p=row.object;local diff=row.before:Inverse()*p.CFrame;local _,angle=diff:ToAxisAngle()
 local beforePivot=row.before*row.offset:Inverse();local afterPivot=p.CFrame*row.offset:Inverse()
 local centerDrift=(afterPivot.Position-beforePivot.Position).Magnitude
 local degrees=math.deg(math.abs(angle));local expected=elapsed*12
 ck("vinyl-center-stable-"..p.Name,centerDrift<.004,centerDrift)
 if enabled and sameEligibility then ck("vinyl-12-degrees-per-second-"..p.Name,math.abs(degrees-expected)<1.8,{degrees=degrees,expected=expected,elapsed=elapsed})
 elseif not enabled then ck("vinyl-reduced-or-distant-stable-"..p.Name,degrees<.01,{degrees=degrees}) end
 table.insert(vinylRows,{name=p.Name,degrees=degrees,elapsed=elapsed,centerDrift=centerDrift,animationEligible=enabled and sameEligibility})
end
for _,row in ipairs(needles) do ck("integral-tonearms-fixed-"..row.object.Name,cfclose(row.before,row.object.CFrame,.00001)) end
report.vinyl={rows=vinylRows,animationEligibility=enabled==true,scope="Two separate discs; known DJConsole mesh containing tonearms/needles observed fixed for the same interval"}
if not enabled then table.insert(report.coverage,"Vinyl motion not covered: existing ReduceFlashing setting or avatar distance disables animation") end
report.propertyChecksPassed=#report.failures==0
report.playVisualsVerified=false;report.gameplayVerified=false;report.performanceVerified=false
return report
