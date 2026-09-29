-- Read-only verification for a separately executed single-script payload.
local H=game:GetService("HttpService");local E=game:GetService("ScriptEditorService")
local names={"ServerScriptService","GameManager"};local target=game
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
assert(not game:GetService("RunService"):IsRunning(),"Edit mode required")
for _,name in ipairs(names) do
 local found=nil
 for _,child in ipairs(target:GetChildren()) do if child.Name==name then assert(not found,"Ambiguous path");found=child end end
 assert(found,"Missing path");target=found
end
assert(target.ClassName=="Script","Wrong class")
local function djb(s)local h=5381;for i=1,#s do h=(h*33+string.byte(s,i))%4294967296 end;return h end
local s,e=target.Source,E:GetEditorSource(target)
return H:JSONEncode({path=target:GetFullName(),version=game.PlaceVersion,sourceLength=#s,editorLength=#e,sourceDjb2=djb(s),editorDjb2=djb(e),equal=s==e,expectedLength=166063,expectedDjb2=951332234,matchesExpected=s==e and #s==166063 and djb(s)==951332234})
