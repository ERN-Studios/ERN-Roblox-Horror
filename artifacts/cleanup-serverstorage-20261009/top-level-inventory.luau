local HS=game:GetService("HttpService")
local RS=game:GetService("RunService")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local rows={}
for _,item in game:GetService("ServerStorage"):GetChildren() do
 local keys={}
 for key in item:GetAttributes() do keys[#keys+1]=key end
 table.sort(keys)
 rows[#rows+1]={name=item.Name,class=item.ClassName,children=#item:GetChildren(),attributeKeys=keys}
end
table.sort(rows,function(a,b) return a.name==b.name and a.class<b.class or a.name<b.name end)
return HS:JSONEncode({placeId=game.PlaceId,universeId=game.GameId,running=RS:IsRunning(),scope="read-only authoritative Edit top-level inventory; attribute values not included",rootCount=#rows,roots=rows})
