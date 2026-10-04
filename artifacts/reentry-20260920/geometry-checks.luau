local fixture=Instance.new("Folder");fixture.Name="ReentryGeometryTest";fixture.Parent=workspace
local function part(name,size,pos) local p=Instance.new("Part");p.Name=name;p.Size=size;p.Position=pos;p.Anchored=true;p.Parent=fixture;return p end
local floor=part("Floor",Vector3.new(60,1,60),Vector3.new(10000,500,10000))
local p=game.Players:GetPlayers()[1];local root=p.Character.HumanoidRootPart;local hum=p.Character.Humanoid
local placement=require(game.ServerScriptService.ReentryPlacement);local frame=CFrame.new(10000,504.2,10000)
local checks=0;local function check(v,msg)assert(v,msg);checks+=1 end
local ok,err=pcall(function()
local exact=placement.At(root,hum,frame);check(exact~=nil,"Flat floor allowed");check((Vector2.new(exact.X,exact.Z)-Vector2.new(frame.X,frame.Z)).Magnitude<.01,"Exact XZ preserved")
local wall=part("Wall",Vector3.new(3,12,3),Vector3.new(10000,506,10000))
check(placement.At(root,hum,frame)==nil,"Wall rejected")
local nearby=placement.Resolve(root,hum,frame,nil);check(nearby and (nearby.Position-frame.Position).Magnitude<14,"Nearby floor after wall")
wall:Destroy()
local blocked=placement.Resolve(root,hum,frame,nil,function(pos)return (pos-Vector3.new(10000,pos.Y,10000)).Magnitude>3.9 end)
check(blocked and (Vector2.new(blocked.X,blocked.Z)-Vector2.new(frame.X,frame.Z)).Magnitude>=3.9,"Other player respected")
check(placement.At(root,hum,CFrame.new(11000,504,11000))==nil,"Void rejected")
local fallback=placement.Resolve(root,hum,CFrame.new(11000,450,11000),frame);check(fallback and math.abs(fallback.X-frame.X)<.01,"Last safe ground fallback")
floor.Anchored=false;check(placement.At(root,hum,frame)==nil,"Moving floor rejected");floor.Anchored=true
local zones=workspace:FindFirstChild("PitZones");local own=false;if not zones then zones=Instance.new("Folder");zones.Name="PitZones";zones.Parent=workspace;own=true end
local zone=Instance.new("Part");zone.Name="Zone";zone.Anchored=true;zone.CanCollide=false;zone.CanQuery=false;zone.Size=Vector3.new(60,2,60);zone.Position=Vector3.new(10000,520,10000);zone.Parent=zones
local rejected=placement.At(root,hum,frame)==nil;zone:Destroy();if own then zones:Destroy()end;check(rejected,"Lethal pit bottom rejected")
end)
fixture:Destroy();assert(ok,err);return tostring(checks).." Studio geometry checks passed"
