local se=game:GetService("ScriptEditorService")
local function hash(s)local h=5381;for i=1,#s do h=(h*33+s:byte(i))%4294967296 end;return h end
local function replace(s,a,b)local p=s:find(a,1,true);assert(p and not s:find(a,p+#a,true),"Expected one exact fragment");return s:sub(1,p-1)..b..s:sub(p+#a)end
local gm=game.ServerScriptService.GameManager;local lb=game.ServerScriptService.TunnelLobbyBuilder
local specs={{gm,166063,951332234,{{'workspace:SetAttribute("Level5PublicPreviewEnabled", true)','workspace:SetAttribute("Level5PublicPreviewEnabled", false)'},{'workspace:SetAttribute(Routing.Level5DevAttribute, true)','workspace:SetAttribute(Routing.Level5DevAttribute, false)'}}},{lb,116631,3492273471,{{'{level = 5, side = -1, z = 80, active = true}','{level = 5, side = -1, z = 80, active = false}'}}}}
local prepared={}
for _,s in ipairs(specs)do local old=s[1].Source;assert(#old==s[2] and hash(old)==s[3] and se:GetEditorSource(s[1])==old,"Baseline changed");local new=old;for _,r in ipairs(s[4])do new=replace(new,r[1],r[2])end;table.insert(prepared,{script=s[1],old=old,new=new})end
local room=workspace.ServerLobby.LevelQueueRooms.Level5QueueRoom;local doors=workspace.ServerLobby.LevelDoorways;local door=doors.Level5SealedDoor
assert(room:GetAttribute("LevelNumber")==5 and room:GetAttribute("LevelEnabled")==true and not door.CanCollide and door.Transparency==1,"Native baseline changed")
for i=17,20 do assert(room:FindFirstChild("LaunchZone"..i) and not room:FindFirstChild("FutureLaunchZone"..i),"Station baseline changed")end
local result={}
for _,s in ipairs(prepared)do assert(s.script.Source==s.old and se:GetEditorSource(s.script)==s.old);se:UpdateSourceAsync(s.script,function(old)assert(old==s.old,"Concurrent source change");return s.new end);assert(s.script.Source==s.new and se:GetEditorSource(s.script)==s.new);table.insert(result,{path=s.script:GetFullName(),length=#s.new,hash=hash(s.new)})end
workspace:SetAttribute("Level5PublicPreviewEnabled",false);workspace:SetAttribute("Level5DevEnabled",false)
room:SetAttribute("LevelEnabled",false)
for i=17,20 do
room["LaunchZone"..i].Name="FutureLaunchZone"..i
local sign=room["Station"..i.."Sign"];local title=sign:FindFirstChild("Title",true);local subtitle=sign:FindFirstChild("Subtitle",true)
title.Text="STATION "..(i-16).."  •  OFFLINE";title.TextColor3=Color3.fromRGB(226,133,112)
subtitle.Text="AWAITING LEVEL AUTHORIZATION"
end
door.CanCollide=true;door.CanTouch=true;door.CanQuery=true;door.Transparency=0;door:SetAttribute("Level5PreviewDoorOpen",false);door.Display.Enabled=true
for _,s in ipairs({doors.Level5Information,room:FindFirstChild("ExitMarker")})do if s then local sub=s:FindFirstChild("Subtitle",true);local title=s:FindFirstChild("Title",true);if sub then sub.Text="COMING SOON  •  WORK IN PROGRESS" end;if title then title.TextColor3=Color3.fromRGB(226,133,112)end end end
return {status="CLOSED_VERIFIED",scripts=result,public5=workspace:GetAttribute("Level5PublicPreviewEnabled"),dev5=workspace:GetAttribute("Level5DevEnabled"),door=door.CanCollide,enabled=room:GetAttribute("LevelEnabled")}

