
local R=game:GetService("RunService")
local E=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
assert(not R:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407 and game.CreatorId==1039373905,"Wrong mode/place")
local function hash(s)return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",c:byte())end))end
local function exact(parent,name,class)
 local found
 for _,i in ipairs(parent:GetChildren())do if i.Name==name then assert(not found,"Duplicate exact path");found=i end end
 assert(found and found.ClassName==class,"Exact path missing");return found
end
local service=game:GetService("ServerScriptService")
local owner=exact(service,"LobbyReimaginedPreview","Folder")
local target=exact(owner,"LobbyPolishBays","ModuleScript")
local OLD="2f6c8007a8472aefad700dac5511a0ad24e8ba1341e745c7ef5306142fb92058"
local NEW="1ab19711a303b058d033de6652da3d94c15e73f7e40b4e983036fa99c805bc2c"
local before=target.Source
local candidate,count=before:gsub("\t\t\tobject.RenderFidelity = Enum.RenderFidelity.Precise\n","",1)
assert(count==1 and hash(candidate)==NEW,"Fix is not the reviewed single deletion")
local function verify()
 assert(not R:IsRunning() and exact(service,"LobbyReimaginedPreview","Folder")==owner and exact(owner,"LobbyPolishBays","ModuleScript")==target,"Mode or identity changed")
 assert(owner:GetAttribute("LobbyReimaginedOwned")==true and target:GetAttribute("LobbyReimaginedOwned")==true and target:GetAttribute("InstalledSourceSHA256")==OLD,"Ownership or installed pin changed")
 assert(hash(target.Source)==OLD and hash(SES:GetEditorSource(target))==OLD,"Live Source/editor baseline changed")
end
verify()
SES:UpdateSourceAsync(target,function(current) verify();assert(current==before,"CAS editor changed");return candidate end)
assert(hash(target.Source)==NEW and SES:GetEditorSource(target)==candidate,"Post-write conflict")
target:SetAttribute("InstalledSourceSHA256",NEW)
return game:GetService("HttpService"):JSONEncode({path=target:GetFullName(),beforeSHA256=OLD,afterSHA256=NEW,onlyRemovedRuntimeRenderFidelityWrite=true,sourceBytes=#candidate,editorMatch=true,cloneFidelityInheritedFromKit=true,liveCloneFidelityStillRequiresPlay=true,DoubleSidedPreserved=true,changedAt=DateTime.now():ToIsoDate()})
