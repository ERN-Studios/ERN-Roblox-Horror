local S=game.ServerScriptService["Level 3 Systems"]
local A=require(S["Level 3 Round Adapter"])
local M=require(S["Level 3 Mall Manager AI Controller"])
local m=A.GetManifest()
local snap=M.GetSnapshot()
local out={}
for k,v in pairs(snap or {}) do
 if typeof(v)=="Vector3" then out[k]={v.X,v.Y,v.Z}
 elseif type(v)=="number" or type(v)=="boolean" or type(v)=="string" then out[k]=v end
end
local p=m.EscapeTrigger.Position
out.escapeTrigger={p.X,p.Y,p.Z}
local size=m.EscapeTrigger.Size
out.escapeSize={size.X,size.Y,size.Z}
return out
