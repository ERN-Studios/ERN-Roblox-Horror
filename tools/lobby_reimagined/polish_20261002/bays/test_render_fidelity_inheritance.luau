-- Offline engine-property proxy: runtime RenderFidelity writes are forbidden.
-- Execute the complete helper Add against six real Lune bay graphs and 24 pads.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local r=require("@lune/roblox")
local base="tools/lobby_reimagined/polish_20261002/bays/"
local source=fs.readFile(base.."LobbyPolishBays.ModuleScript.candidate.luau")
local baseline=fs.readFile("/private/tmp/lobby-polish-frozen-receivers-20261002/catalog.json")
local catalog=serde.decode("json",baseline)
local original
for _,row in ipairs(catalog.sources) do if row.path=="ServerScriptService.LobbyReimaginedPreview.LobbyPolishBays" then original=row.source end end
assert(original and serde.hash("sha256",original)=="2f6c8007a8472aefad700dac5511a0ad24e8ba1341e745c7ef5306142fb92058")
assert(source==original:gsub("\t\t\tobject.RenderFidelity = Enum.RenderFidelity.Precise\n","",1),"Fix exceeds one forbidden property write")
local manifest=serde.decode("json",fs.readFile(base.."baseline/live-manifest-excerpt.json"))
local function run(candidate, fidelity)
 local rawByProxy,proxyByRaw={},{};local runtime=false;local forbidden=0
 local function unwrap(x) return rawByProxy[x] or x end
 local wrap
 wrap=function(raw)
  if typeof(raw)~="Instance" then return raw end
  if proxyByRaw[raw] then return proxyByRaw[raw] end
  local proxy={};rawByProxy[proxy]=raw;proxyByRaw[raw]=proxy
  setmetatable(proxy,{
   __index=function(_,key)
    local value=raw[key]
    if type(value)=="function" then return function(_, ...)
     local args=table.pack(...);for i=1,args.n do args[i]=unwrap(args[i]) end
     local out=table.pack(value(raw,table.unpack(args,1,args.n)))
     for i=1,out.n do
      if typeof(out[i])=="Instance" then out[i]=wrap(out[i])
      elseif type(out[i])=="table" and (key=="GetChildren" or key=="GetDescendants") then
       for j,x in ipairs(out[i]) do out[i][j]=wrap(x) end
      end
     end
     return table.unpack(out,1,out.n)
    end end
    return wrap(value)
   end,
   __newindex=function(_,key,value)
    if runtime and key=="RenderFidelity" then forbidden+=1;error("Runtime RenderFidelity write forbidden by Plugin security fixture") end
    raw[key]=unwrap(value)
   end,
  });return proxy
 end
 local function new(class,name,parent)
  local x=r.Instance.new(class);if name then x.Name=name end;if parent then x.Parent=parent end;return x
 end
 local model=new("Model","LobbyReimaginedPreview");model:SetAttribute("LobbyReimaginedOwned",true)
 model:SetAttribute("LobbyVisualRevision",4);model:SetAttribute("Ready",false)
 local kit=new("Folder","Kit");local signs=new("Folder","LevelGateSigns",model)
 local pads=new("Folder","PreviewQueuePads",model)
 for family,spec in pairs(manifest.families) do
  if #spec.chunks==1 then
   local p=new("MeshPart",family,kit);p.CFrame=r.CFrame.new(table.unpack(spec.chunks[1].center))
   p.Size=r.Vector3.new(table.unpack(spec.chunks[1].size));p.RenderFidelity=fidelity
   p:SetAttribute("BlenderTriangles",spec.triangles)
  end
 end
 local center=r.Vector3.new(table.unpack(manifest.previewCenter))
 for _,b in ipairs(manifest.bays) do new("Model","QueueBay_Level"..b.level,pads) end
 for _,s in ipairs(manifest.signs) do
  local p=new("Part","LEVEL "..s.level.." Door Header",signs)
  p.CFrame=r.CFrame.new(center+r.Vector3.new(table.unpack(s.gatePosition)))*r.CFrame.Angles(0,s.yaw,0)*r.CFrame.new(table.unpack(s.headerLocalPosition))
  p:SetAttribute("Level",s.level)
 end
 local counts={}
 for _,p in ipairs(manifest.pads) do
  counts[p.level]=(counts[p.level] or 0)+1;local bay=pads:FindFirstChild("QueueBay_Level"..p.level)
  local station=new("Model",string.format("Level%d Queue %02d",p.level,counts[p.level]),bay)
  station:SetAttribute("HologramBase",r.CFrame.new(center+r.Vector3.new(table.unpack(p.position))))
  new("MeshPart","Active Queue Ring",station);new("TextLabel","QueueTitle",station);new("TextLabel","QueueSubtitle",station)
 end
 local module=luau.load(candidate,{environment={Instance={new=function(class)return wrap(r.Instance.new(class)) end},
  Vector3=r.Vector3,Vector2=r.Vector2,CFrame=r.CFrame,Color3=r.Color3,UDim2=r.UDim2,Enum=r.Enum}})()
 runtime=true
 local ok,result=pcall(module.Add,wrap(model),wrap(kit),manifest)
 return {ok=ok,result=result,forbidden=forbidden,model=model,kit=kit}
end
local cases={}
for _,fidelity in ipairs({r.Enum.RenderFidelity.Precise,r.Enum.RenderFidelity.Automatic}) do
 local negative=run(original,fidelity)
 assert(not negative.ok and negative.forbidden==1 and tostring(negative.result):find("Runtime RenderFidelity write forbidden",1,true),"Negative control did not reject known forbidden write")
 local positive=run(source,fidelity);assert(positive.ok,tostring(positive.result));assert(positive.forbidden==0)
 local folder=assert(positive.model:FindFirstChild("R4BayPresentation"))
 local props=assert(folder:FindFirstChild("Theme Furniture"));local meshCount=0
 assert(#props:GetChildren()==19 and folder:GetAttribute("AddedInstancedTriangles")==19312)
 for _,p in ipairs(props:GetChildren()) do
  local pieces=p:GetDescendants();if p:IsA("MeshPart") then table.insert(pieces,p) end
  local kitSource=assert(positive.kit:FindFirstChild(p:GetAttribute("SourceFamily")))
  for _,mesh in ipairs(pieces) do if mesh:IsA("MeshPart") then
   meshCount+=1;assert(mesh.RenderFidelity==kitSource.RenderFidelity and mesh.RenderFidelity==fidelity,"Clone did not preserve source kit RenderFidelity")
   assert(mesh.DoubleSided and not mesh.CanCollide and not mesh.CanQuery and not mesh.CanTouch)
  end end
 end
 assert(meshCount==19)
 table.insert(cases,{sourceKitRenderFidelity=fidelity.Name,cloneCount=meshCount,cloneFidelityEqualsSource=true,knownBadBaselineRejected=true})
end
local receipt={schema="lobby-bays-runtime-property-security-fixture-v1",status="PASS",helperSHA256=serde.hash("sha256",source),
 installedBaselineSHA256=serde.hash("sha256",original),exactOnlyRemovedRenderFidelityWrite=true,
 knownBadBaselineRejected=true,forbiddenWritesInFixedHelper=0,actualHelperAddExecuted=true,
 fidelityInheritanceCases=cases,doubleSidedPreserved=true,queuePads=24,bays=6,
 scope="Offline fixture inputs test Precise and Automatic inheritance, not live kit defaults; actual 19-clone Studio property reads and rebuild remain required"}
fs.writeFile("artifacts/lobby-polish-20261002/bays/render-fidelity-inheritance-receipt.json",serde.encode("json",receipt,true))
print(serde.encode("json",receipt))
