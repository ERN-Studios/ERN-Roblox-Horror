local se=game:GetService("ScriptEditorService");local s=game.ServerScriptService.TunnelLobbyBuilder;local old=s.Source
local function hash(t)local h=5381;for i=1,#t do h=(h*33+t:byte(i))%4294967296 end;return h end
assert(#old==116632 and hash(old)==4109718538 and se:GetEditorSource(s)==old,"Concurrent source change")
local a="addRoom(rooms, center, def.level, def.side, def.z, def.active or def.level == 4 or def.level == 5, stations)"
local b="addRoom(rooms, center, def.level, def.side, def.z, def.active or def.level == 4, stations)"
local p=assert(old:find(a,1,true));assert(not old:find(a,p+#a,true));local new=old:sub(1,p-1)..b..old:sub(p+#a)
se:UpdateSourceAsync(s,function(current)assert(current==old,"Concurrent source change");return new end)
assert(s.Source==new and se:GetEditorSource(s)==new);return {status="CLOSED_STATION_REGISTRATION",length=#new,hash=hash(new)}

