-- Exact extracted RoundUI helper+apply fragment, mocked Lighting/positions.
local fs=require("@lune/fs")
local luau=require("@lune/luau")
local serde=require("@lune/serde")
local roblox=require("@lune/roblox")
local V3,C3=roblox.Vector3,roblox.Color3
local ownedProperties={"ColorShift_Top","ColorShift_Bottom","Ambient","OutdoorAmbient","Brightness","ClockTime","FogColor","FogStart","FogEnd"}
local fragment=fs.readFile("/private/tmp/lobby-r4-roundui-lighting-review/review-fragment-v6.luau")
local function fixture()
 local lighting={children={},
  ColorShift_Top=C3.new(0,0,0),ColorShift_Bottom=C3.new(0,0,0),Ambient=C3.fromRGB(76,69,45),OutdoorAmbient=C3.fromRGB(48,43,28),
  Brightness=1.35,ClockTime=14,FogColor=C3.fromRGB(205,190,125),FogStart=0,FogEnd=100000,
 }
 function lighting:FindFirstChild(name)return self.children[name]end
 function lighting:FindFirstChildOfClass(class)
  for _,child in pairs(self.children)do if child.class==class then return child end end
 end
 local grade={Name="LobbyLocalGrade",Enabled=true};lighting.children.LobbyLocalGrade=grade
 local maze={Name="MongoGrade",Enabled=false};lighting.children.MongoGrade=maze
 local atmosphere={class="Atmosphere",Name="Atmosphere",Parent=lighting,Density=.3};lighting.children.Atmosphere=atmosphere
 local player={attrs={}}
 function player:GetAttribute(name)return self.attrs[name]end
 local root={class="Part",Position=V3.new(220,34,-760)}
 function root:IsA(class)return class=="BasePart"end
 local char={}
 function char:FindFirstChild(name)return if name=="HumanoidRootPart"then root else nil end
 player.Character=char
 local workspace={children={},attrs={}}
 function workspace:FindFirstChild(name)return self.children[name]end
 function workspace:GetAttribute(name)return self.attrs[name]end
 local model={class="Model",Parent=workspace,attrs={LobbyReimaginedOwned=true,Ready=true,LobbyVisualRevision=4,PreviewCenter=V3.new(220,30,-760)}}
 function model:IsA(class)return class=="Model"end
 function model:GetAttribute(name)return self.attrs[name]end
 workspace.children.LobbyReimaginedPreview=model
 local functions=luau.load(fragment.."\nreturn {apply=applyPlayerLighting,helper=revisedLobbyLighting}",{environment={
  Lighting=lighting,player=player,workspace=workspace,Color3=C3,
  Instance={new=function()return{}end},typeof=function(value)return if type(value)=="table" and value.class then "Instance"else typeof(value)end,
 }})()
 return {lighting=lighting,grade=grade,maze=maze,atmosphere=atmosphere,player=player,root=root,world=workspace,model=model,apply=functions.apply,helper=functions.helper}
end
local results={}
local function check(name,callback)
 local ok,why=pcall(callback);table.insert(results,{name=name,passed=ok,error=if ok then nil else tostring(why)})
 if not ok then warn(name,why)end
end
check("only owned Ready R4 spatial lobby receives neutral night pass",function()
 local f=fixture();f.apply();assert(f.lighting.ClockTime==0 and f.lighting.Brightness==.6)
 assert(f.lighting.Ambient==C3.fromRGB(30,32,30));assert(f.atmosphere.Density==0)
 assert(f.grade.TintColor==C3.new(1,1,1) and f.grade.Contrast==.12 and f.grade.Saturation==0)
end)
check("original lobby immediately restores exact inherited density and warm defaults",function()
 local f=fixture();f.apply();f.root.Position=V3.new(0,34,-760);f.apply()
 assert(f.atmosphere.Density==.3 and f.lighting.ClockTime==14 and f.lighting.Brightness==1.35)
 assert(f.lighting.Ambient==C3.fromRGB(76,69,45));assert(f.grade.TintColor==C3.fromRGB(255,242,188) and f.grade.Contrast==.04)
end)
check("active maze is excluded even before position transfer",function()
 local f=fixture();f.apply();f.player.attrs.InRound=true;f.apply()
 assert(f.atmosphere.Density==.3 and f.lighting.Ambient==C3.fromRGB(4,4,3) and f.grade.Enabled==false and f.maze.Enabled==true)
end)
check("unowned or unfinished visual revision cannot acquire lighting",function()
 for _,case in ipairs({{"LobbyReimaginedOwned",false},{"Ready",false},{"LobbyVisualRevision",3}})do
  local f=fixture();f.model.attrs[case[1]]=case[2];f.apply();assert(f.lighting.ClockTime==14 and f.atmosphere.Density==.3)
 end
end)
check("all existing controller guards release R4 without touching owned level values",function()
 for _,level in ipairs({2,3,4,6})do
  local f=fixture();f.apply();local sentinel=C3.fromRGB(71,51,11);f.lighting.Ambient=sentinel;f.atmosphere.Density=.16
  if level==4 then f.player.attrs.Level4LightingOwned=true
  elseif level==6 then
   f.world.children["Level 6 Generated World"]={};f.world.attrs.Level6SelectedLevel=6;f.world.attrs.Level6LightingOwnedByController=true;f.player.attrs.Level6InRound=true
  else
   f.world.children["Level "..level.." Generated World"]={};f.world.attrs.SelectedLevel=level;f.world.attrs["Level"..level.."LightingOwnedByController"]=true;f.player.attrs.InRound=true
  end
  f.apply();assert(f.lighting.Ambient==sentinel and f.atmosphere.Density==.16 and not f.grade.Enabled and not f.helper.active)
 end
end)
check("new external atmosphere density while inside becomes restoration baseline",function()
 local f=fixture();f.apply();f.atmosphere.Density=.21;f.apply();assert(f.atmosphere.Density==0)
 f.root.Position=V3.new(0,34,-760);f.apply();assert(f.atmosphere.Density==.21)
end)
check("replacement atmosphere is restored without overwriting another controller",function()
 local f=fixture();f.apply();f.atmosphere.Parent=nil
 local replacement={class="Atmosphere",Parent=f.lighting,Density=.15};f.lighting.children.Atmosphere=replacement;f.apply();assert(replacement.Density==0)
 replacement.Density=.09;f.root.Position=V3.new(0,34,-760);f.apply();assert(replacement.Density==.09)
end)
check("missing character and distant previews release owned atmosphere",function()
 local f=fixture();f.apply();f.player.Character=nil;f.apply();assert(f.atmosphere.Density==.3 and not f.helper.active)
 f=fixture();f.apply();f.root.Position=V3.new(5000,34,-760);f.apply();assert(f.atmosphere.Density==.3 and f.lighting.ClockTime==14)
end)
check("Level4 snapshot of R4 zero cannot leak into original lobby after return",function()
 local f=fixture();f.apply();local level4Saved=f.atmosphere.Density;assert(level4Saved==0)
 f.player.attrs.Level4LightingOwned=true;f.root.Position=V3.new(6000,34,-760);f.atmosphere.Density=.1;f.apply()
 assert(f.atmosphere.Density==.1 and f.helper.atmospheres[f.atmosphere]==.3)
 f.player.attrs.Level4LightingOwned=nil;f.root.Position=V3.new(0,34,-760);f.atmosphere.Density=level4Saved;f.apply()
 assert(f.atmosphere.Density==.3 and not f.helper.active and f.helper.atmospheres[f.atmosphere]==nil)
end)
check("Level4 intentional zero remains untouched until owner releases",function()
 local f=fixture();f.apply();f.player.attrs.Level4LightingOwned=true;f.atmosphere.Density=0;f.apply()
 assert(f.atmosphere.Density==0 and f.helper.atmospheres[f.atmosphere]==.3)
 f.player.attrs.Level4LightingOwned=nil;f.root.Position=V3.new(0,34,-760);f.apply();assert(f.atmosphere.Density==.3)
end)
check("R4 nonparticipants retain night while another global Level2 or3 controller is selected",function()
 for _,level in ipairs({2,3})do
  local f=fixture();f.world.children["Level "..level.." Generated World"]={};f.world.attrs.SelectedLevel=level;f.world.attrs["Level"..level.."LightingOwnedByController"]=true
  f.player.attrs.InRound=false;f.apply()
  assert(f.lighting.ClockTime==0 and f.lighting.Ambient==C3.fromRGB(30,32,30) and f.atmosphere.Density==0 and f.grade.Enabled==true and f.helper.active)
  local sentinel=C3.fromRGB(51,22,80);f.lighting.Ambient=sentinel;f.player.attrs.InRound=true;f.apply()
  assert(f.lighting.Ambient==sentinel and f.grade.Enabled==false and not f.helper.active)
 end
end)
check("outside R4 nonparticipant retains existing global Level2 or3 stand-down",function()
 for _,level in ipairs({2,3})do
  local f=fixture();f.root.Position=V3.new(0,34,-760)
  f.world.children["Level "..level.." Generated World"]={};f.world.attrs.SelectedLevel=level;f.world.attrs["Level"..level.."LightingOwnedByController"]=true
  f.player.attrs.InRound=false;local sentinel=C3.fromRGB(23,49,62);f.lighting.Ambient=sentinel;f.apply()
  assert(f.lighting.Ambient==sentinel and f.atmosphere.Density==.3 and f.grade.Enabled==false and not f.helper.active)
 end
end)
check("leaving R4 restores all nine globals despite another global Level2 or3 stand-down",function()
 for _,level in ipairs({2,3})do
  local f=fixture();local saved={};for _,property in ipairs(ownedProperties)do saved[property]=f.lighting[property]end
  f.world.children["Level "..level.." Generated World"]={};f.world.attrs.SelectedLevel=level;f.world.attrs["Level"..level.."LightingOwnedByController"]=true
  f.player.attrs.InRound=false;f.apply();assert(f.lighting.ClockTime==0 and f.atmosphere.Density==0)
  f.root.Position=V3.new(0,34,-860);f.apply()
  for property,baseline in pairs(saved)do assert(f.lighting[property]==baseline,property)end
  assert(f.atmosphere.Density==.3 and f.helper.lighting==nil and not f.helper.active)
 end
end)
check("R4 exit preserves newer external values rather than restoring over them",function()
 local f=fixture();f.apply();f.lighting.Ambient=C3.fromRGB(9,13,27);f.lighting.Brightness=1.8
 f.world.children["Level 3 Generated World"]={};f.world.attrs.SelectedLevel=3;f.world.attrs.Level3LightingOwnedByController=true
 f.root.Position=V3.new(0,34,-860);f.apply()
 assert(f.lighting.Ambient==C3.fromRGB(9,13,27) and f.lighting.Brightness==1.8 and f.lighting.ClockTime==14)
end)
check("actual local participant ownership retains global snapshot until release",function()
 for _,level in ipairs({2,3,4,6})do
  local f=fixture();f.apply();local saved=f.helper.lighting;local sentinel=C3.fromRGB(2,9,15)
  f.lighting.Ambient=sentinel;f.root.Position=V3.new(8000,34,-860)
  if level==4 then f.player.attrs.Level4LightingOwned=true
  elseif level==6 then f.player.attrs.Level6InRound=true;f.world.children["Level 6 Generated World"]={};f.world.attrs.Level6SelectedLevel=6;f.world.attrs.Level6LightingOwnedByController=true
  else f.player.attrs.InRound=true;f.world.children["Level "..level.." Generated World"]={};f.world.attrs.SelectedLevel=level;f.world.attrs["Level"..level.."LightingOwnedByController"]=true end
  f.apply();assert(f.lighting.Ambient==sentinel and f.helper.lighting==saved)
  f.player.attrs.Level4LightingOwned=nil;f.player.attrs.Level6InRound=nil;f.player.attrs.InRound=false
  f.lighting.Ambient=f.helper.values.Ambient;f.lighting.ClockTime=0;f.root.Position=V3.new(0,34,-860);f.apply()
  assert(f.lighting.Ambient==C3.fromRGB(76,69,45) and f.lighting.ClockTime==14 and f.helper.lighting==nil)
 end
end)
check("returning inside R4 after Level4 ownership keeps the pre-R4 global baseline",function()
 local f=fixture();f.apply();local saved=f.helper.lighting
 f.player.attrs.Level4LightingOwned=true;f.lighting.Ambient=C3.fromRGB(46,36,60);f.atmosphere.Density=.1;f.apply()
 assert(f.helper.lighting==saved and f.atmosphere.Density==.1)
 f.player.attrs.Level4LightingOwned=nil;f.atmosphere.Density=0
 for property,value in pairs(f.helper.values)do f.lighting[property]=value end
 f.apply();assert(f.helper.lighting==saved and f.helper.active)
 f.root.Position=V3.new(0,34,-860);f.world.children["Level 3 Generated World"]={};f.world.attrs.SelectedLevel=3;f.world.attrs.Level3LightingOwnedByController=true;f.apply()
 assert(f.lighting.ClockTime==14 and f.lighting.Ambient==C3.fromRGB(76,69,45) and f.atmosphere.Density==.3)
end)
check("Float32 engine readback brightness restores on nonparticipant R4 exit",function()
 local f=fixture();local stored={}
 for _,property in ipairs(ownedProperties)do stored[property]=f.lighting[property];f.lighting[property]=nil end
 setmetatable(f.lighting,{__index=function(_,property)return stored[property]end,
  __newindex=function(target,property,value)
   if stored[property]~=nil then
    stored[property]=if property=="Brightness" and value==.6 then .6000000238418579 else value
   else rawset(target,property,value)end
  end})
 f.world.children["Level 3 Generated World"]={};f.world.attrs.SelectedLevel=3;f.world.attrs.Level3LightingOwnedByController=true
 f.apply();assert(f.lighting.Brightness==.6000000238418579 and f.lighting.Brightness~=.6)
 assert(f.helper.applied.Brightness==f.lighting.Brightness)
 f.root.Position=V3.new(0,34,-860);f.apply()
 assert(f.lighting.Brightness==1.35 and f.lighting.ClockTime==14 and f.helper.applied==nil)
end)
local passed=true;for _,r in ipairs(results)do passed=passed and r.passed end
local result={passed=passed,candidateSHA256=serde.hash("sha256",fs.readFile("/private/tmp/lobby-r4-roundui-lighting-review/RoundUI.v6.candidate.luau")),fragmentSHA256=serde.hash("sha256",fragment),tests=results,scope="Offline exact extracted RoundUI lighting fragment with mocks; not actual Studio, gameplay, performance or multiplayer"}
fs.writeFile("/private/tmp/lobby-r4-roundui-lighting-review/mock-lighting-receipt-v6.json",serde.encode("json",result,true).."\n")
print(serde.encode("json",result,true));assert(passed)
