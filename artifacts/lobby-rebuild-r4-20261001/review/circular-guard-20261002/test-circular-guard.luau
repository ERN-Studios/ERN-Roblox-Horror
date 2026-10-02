-- Exact Bridge.Build regression; native float32 Vector3 geometry, graph fixture.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local rbx=require("@lune/roblox")
local task=require("@lune/task")
local process=require("@lune/process")
local root=assert(process.args[1],"Pass the directory containing the fixed exact before/after inputs")
if string.sub(root,-1)~="/" then root..="/" end
local before=fs.readFile(root.."QueueBridge.circular-tolerance.before.luau")
local after=fs.readFile(root.."QueueBridge.circular-tolerance.candidate.luau")
assert(serde.hash("sha256",before)=="1a5e14256a7725a35b0b13a6d31b6fd4ea47d14875368d46e9593fe365226e08")
assert(serde.hash("sha256",after)=="ad7752eefc2561ccda5fb92828dc71d1a2ff805a0fadca6d740c0e1b3e82d674")
assert(pcall(luau.compile,before) and pcall(luau.compile,after))
local function instance(class,name,parent)
 local obj={ClassName=class,Name=name,Parent=parent,attrs={},children={}}
 function obj:IsA(wanted) return class==wanted or (class=="Part" and wanted=="BasePart") end
 function obj:GetAttribute(key) return self.attrs[key] end
 function obj:SetAttribute(key,value) self.attrs[key]=value end
 function obj:FindFirstChild(name,recursive)
  for _,child in self.children do if child.Name==name then return child end end
  if recursive then for _,child in self.children do local found=child:FindFirstChild(name,true);if found then return found end end end
  return nil
 end
 function obj:GetDescendants()
  local all={}
  local function walk(o) for _,child in o.children do table.insert(all,child);walk(child) end end
  walk(self);return all
 end
 function obj:IsDescendantOf(parent)
  local next=self.Parent;while next do if next==parent then return true end;next=next.Parent end;return false
 end
 if parent then table.insert(parent.children,obj) end
 return obj
end
local function fixture(source)
 local workspace=instance("Workspace","Workspace")
 local model=instance("Model","LobbyReimaginedPreview",workspace)
 model.attrs={LobbyReimaginedOwned=true,R3QueueRevision=3,Ready=true}
 local zones={}
 for level=1,6 do
  local bay=instance("Model","QueueBay_Level"..level,model);bay.attrs.CircularBayDiameter=56
  instance("Part","ChamberFloor",bay)
  for k=1,4 do
   local zone=instance("Part","QueueZone"..k,bay)
   zone.Size=rbx.Vector3.new(14.82,1,14.82)
   zone.Anchored=true;zone.CanCollide=false;zone.CanTouch=false;zone.CanQuery=false;zone.Color=rbx.Color3.new(1,1,1)
   zone.attrs={R3QueueId=100+(level-1)*4+k,LevelNumber=level,QueueDisplayIndex=k,QueueDetectorShape="Circle",QueueRadius=7.41}
   local station=instance("Model","Level"..level.." Queue"..k,bay)
   local ref=instance("ObjectValue","QueueRenderOwner",zone);ref.Value=station
   instance("TextLabel","QueueTitle",station);instance("TextLabel","QueueSubtitle",station)
   table.insert(zones,zone)
  end
 end
 local players=instance("Players","Players")
 local run={IsClient=function()return false end}
 local game={GetService=function(_,name)return if name=="Players" then players elseif name=="RunService" then run else instance(name,name) end}
 local bridge=luau.load(source,{environment={workspace=workspace,game=game,
  typeof=function(o) return if type(o)=="table" and o.ClassName then "Instance" else typeof(o) end,
  Vector2=rbx.Vector2,Vector3=rbx.Vector3,CFrame=rbx.CFrame,Enum=rbx.Enum,task=task}})()
 return bridge,model,zones
end
local results={}
local function check(name,source,expected,edit)
 local b,m,z=fixture(source);if edit then edit(z,m) end
 local ok,answer=pcall(b.Build,m)
 assert(ok==expected,name..": unexpected result "..tostring(answer))
 if ok then assert(#answer==24);for i,s in answer do assert(s.index==100+i and s.zone==z[i] and s.zone:GetAttribute("QueueRadius")>0) end end
 table.insert(results,{name=name,expectedPass=expected,actualPass=ok,testPassed=true,error=if ok then nil else tostring(answer)})
end
check("installed guard reproduces native float32 detector rejection",before,false)
check("candidate registers all24 unchanged radius7.41 detector zones",after,true)
check("valid strict-inside radius still accepted",after,true,function(z)z[1].attrs.QueueRadius=7.409 end)
check("half-size boundary rounding tolerated",after,true,function(z)z[1].attrs.QueueRadius=7.41002 end)
check("materially oversized radius rejected",after,false,function(z)z[1].attrs.QueueRadius=7.5 end)
check("radius beyond tolerance rejected",after,false,function(z)z[1].attrs.QueueRadius=7.4102 end)
check("zero radius rejected",after,false,function(z)z[1].attrs.QueueRadius=0 end)
check("negative radius rejected",after,false,function(z)z[1].attrs.QueueRadius=-1 end)
check("NaN radius rejected",after,false,function(z)z[1].attrs.QueueRadius=0/0 end)
check("infinite radius rejected",after,false,function(z)z[1].attrs.QueueRadius=math.huge end)
check("non-number radius rejected",after,false,function(z)z[1].attrs.QueueRadius="7.41" end)
check("undersized X detector rejected",after,false,function(z)z[1].Size=rbx.Vector3.new(14,1,14.82) end)
check("undersized Z detector rejected",after,false,function(z)z[1].Size=rbx.Vector3.new(14.82,1,14) end)
check("wrong detector shape rejected",after,false,function(z)z[1].attrs.QueueDetectorShape="Box" end)
check("physical detector remains rejected",after,false,function(z)z[1].CanCollide=true end)
check("duplicate station ID remains rejected",after,false,function(z)z[2].attrs.R3QueueId=101 end)
local size=rbx.Vector3.new(14.82,1,14.82)
local report={schema="lobby-r4-circular-guard-regression-v1",passed=true,completedTestCount=#results,
 beforeSHA256=serde.hash("sha256",before),afterSHA256=serde.hash("sha256",after),syntaxPassed=true,
 actualNativeVector3={sizeX=size.X,sizeZ=size.Z,halfSize=size.X*.5,radius=7.41,difference=7.41-size.X*.5},
 results=results,studioExecuted=false,limits="Exact unmodified Bridge.Build code runs with native float32 Vector3 geometry and double radius attributes on an Instance graph fixture. Graph/typeof are mocks because Lune NativePart.Size introduces different upward quantization than actual engine Vector3. No live Play registration/group test claim."}
fs.writeFile(root.."circular-guard-regression.json",serde.encode("json",report,true).."\n")
print(serde.encode("json",{passed=true,completedTestCount=#results,afterSHA256=report.afterSHA256,nativeSize=size.X},true))
