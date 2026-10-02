local H,E,SES=game:GetService("HttpService"),game:GetService("EncodingService"),game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local function sha(s)return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end))end
local rows={}
for _,x in ipairs(game:GetDescendants())do
 if x:IsA("LuaSourceContainer")then
  local s=x.Source local editor=SES:GetEditorSource(x)
  table.insert(rows,{path=x:GetFullName(),className=x.ClassName,sourceSHA256=sha(s),editorSHA256=sha(editor),bytes=#s,editorMatch=s==editor})
 end
end
table.sort(rows,function(a,b)return a.path<b.path end)
return H:JSONEncode({task="level3-finale-player-20261002",placeId=game.PlaceId,universeId=game.GameId,isRunning=false,capturedAtUTC=DateTime.now():ToIsoDate(),sourceCount=#rows,sources=rows})
