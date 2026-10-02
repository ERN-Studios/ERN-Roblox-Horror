local H,E=game:GetService("HttpService"),game:GetService("EncodingService") local S=game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Edit/context")
local function h(s)return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end))end
local raw=H:GetAsync("http://127.0.0.1:8913/payload",true);assert(h(raw)=="fcab74f3d1b6be42bc57c5dc8ecde97dd58d95fa43b1e3a4911125ae8af2cd63","Frozen catalog changed");local d=H:JSONDecode(raw);local n=0
for _,r in ipairs(d.sources) do local x=game;for seg in r.path:gmatch("[^.]+")do x=assert(x:FindFirstChild(seg))end;assert(x.ClassName==r.class and h(x.Source)==r.sourceSha256 and S:GetEditorSource(x)==x.Source,"Source/editor changed since after export: "..r.path);local f,err=loadstring(x.Source,"="..r.path);assert(f,err);n+=1 end
local count=0;for _,x in ipairs(game:GetDescendants())do if x:IsA("LuaSourceContainer")then count+=1 end end;assert(count==n and n==228,"Source inventory changed")
local receipt={checkedAt=DateTime.now():ToIsoDate(),placeId=game.PlaceId,universeId=game.GameId,sourceCount=n,compiled=n,editorConflicts=0,afterCaptureId="2a0eb6ad-aa1d-4580-8a4c-b60008064944",exactAfterCatalog=true,sourceWrites=false,sceneWrites=false}
assert(H:PostAsync("http://127.0.0.1:8913/receipt/install",H:JSONEncode(receipt),Enum.HttpContentType.ApplicationJson)=="saved");print("FINAL_ACCESS_SPAWN_COMPILE_PARITY_PASS",n);return receipt
