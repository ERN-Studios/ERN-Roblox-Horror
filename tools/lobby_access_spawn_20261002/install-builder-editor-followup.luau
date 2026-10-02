local H,E=game:GetService("HttpService"),game:GetService("EncodingService") local S=game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Edit/context")
local function hash(s) return (E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end)) end
local raw=H:GetAsync("http://127.0.0.1:8913/payload",true) assert(hash(raw)=="11509cb8478a0ed7f1eb1fc1606058b19caa70fc0b48679eb7e7978d24c60928","payload") local d=H:JSONDecode(raw)
local row for _,r in ipairs(d.rows) do if r.path=="ServerScriptService.LobbyReimaginedPreview.Builder" then row=r end end
local x=game.ServerScriptService.LobbyReimaginedPreview.Builder local parent=x.Parent
local expected="6154d95902fbe2d89976e6428fc38a69f25e91e78f5ad02afac50ef19a39fad7"
local function verify() assert(x==game.ServerScriptService.LobbyReimaginedPreview.Builder and x.Parent==parent and x:IsA("ModuleScript") and hash(x.Source)==expected and hash(S:GetEditorSource(x))==expected,"fresh Builder conflict") end
assert(hash(row.source)==row.candidateSHA256 and #row.source==row.candidateBytes,"candidate") assert(loadstring(row.source)) verify()
S:UpdateSourceAsync(x,function(current) verify() assert(hash(current)==expected,"callback conflict") return row.source end)
assert(x.Source==row.source and S:GetEditorSource(x)==row.source,"post-write")
local receipt={installedAt=DateTime.now():ToIsoDate(),placeId=game.PlaceId,universeId=game.GameId,path=x:GetFullName(),beforeSHA256=expected,afterSHA256=hash(x.Source),bytes=#x.Source,editorMatch=true,scope="Builder server or Studio Edit only; start guard only during running server"}
assert(H:PostAsync("http://127.0.0.1:8913/receipt/install",H:JSONEncode(receipt),Enum.HttpContentType.ApplicationJson)=="saved") print("BUILDER_EDITOR_FOLLOWUP_PASS",receipt.afterSHA256) return receipt
