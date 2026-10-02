Read-only bounded CODE-DELTA judgment only, MAXIMUM100words answer. Inspect exact corrected installer excerpts plus verified six-helper DIGEST below. State a concrete material issue in this evidence, or scoped PASS with limitations. No full-source audit or Studio visit claimed. Static10-image experienceaccess is already a KNOWN releaseblocker: root preload aborted BEFORE persistentSourcewrites. ActualPlay/assets/performance remain unverified; do not spend the response diagnosing that known blocker again. Existing DevAccess/serverQueueBridge/clientdevshutters untouched; originalLobby/globalLighting/concurrentL4 preserved.

Verified frozen helper digest (not omitted source validation):
Builder37e988: owned unparented R4 model; End→Bays→Material→Scene before Ready/Workspace; destroy failed new model only.
End426937: PLAN-only16overlay reposes;179densebacking/24otheroverlays/66curtains unchanged;219instances220612meshtriangles; corners33.50423<33.55/DJclearance1.49156.
Bays2f6c8:19existingmeshprops outside24queuecircles, noncolliding; matteidleinlays/presentationattributes, serverdetectors/admission unchanged.
Queueecb544: alpha/colorpresentationreads; upwardfade preserved; lifecycle/eventtail byte-identical; serverauthority untouched.
Material6b4ef8: validatesownedR4/sourcehash/PBRoriginalURI sets, replaces onlyownedruntimecloneappearances/14sidewalktextures; staticmaps; optionalrenderoptimization flags OFF.
Scene9dd927…40746d: controlledexistingfill relocation; no newlights/globalLighting; matte noncollidingstageguidance; clonedshop row/labels, movedfocuscopies followplates; keys/kinds/purchasewriter unchanged.

Exact corrected installer SHAfdff806e8f81f7f85f44a74cefd1aa2b84dc70e228ab6f59b46d210e63d2aa6f. Full guard additionally requires correctEdit/place/universe/group, nativebackupmarker match, noEditpreview, ownedpreviewfolder, seven Source/editor/class/identitypins, newhelpernamesabsent, all10assetsPreloadSuccess beforepersistentwrites. Source updates orderedEnd/Queue/Builder; eachCAS re-verifies dynamic expected pins, with newhelpersparented only afterexistingwrites. PartialCASfailure stops; no rollback/Play/publish authorized.

EXACT GUARD DELTA AND CAS EXCERPTS
local function hash(s) return(E:ComputeStringHash(s,Enum.HashAlgorithm.Sha256):gsub(".",function(c)return string.format("%02x",string.byte(c))end)) end
local rawCatalog=H:GetAsync(BASE.."/catalog",true)
assert(hash(rawCatalog)=="a7b74111671b2baaa3dba2e8ac4602e1d5f9c9d6569436d4381cc90426c6f7d1","Reviewed catalog bytes changed")
local C=H:JSONDecode(rawCatalog)
local parent=at("ServerScriptService.LobbyReimaginedPreview")
assert(parent:IsA("Folder") and parent:GetAttribute("LobbyReimaginedOwned")==true,"Foreign preview owner")
local clientParent=at("StarterPlayer.StarterPlayerScripts")
assert(clientParent:IsA("StarterPlayerScripts"))
local ids,expected={},{}
for _,row in ipairs(C.baseline) do
 assert(row.editorMatch and row.editorSourceSha256==row.sourceSha256)
 ids[row.path]=at(row.path);expected[row.path]=row.sourceSha256
end
local function verify()
 assert(at("StarterPlayer.StarterPlayerScripts")==clientParent and clientParent:IsA("StarterPlayerScripts"),"Client parent changed")
 assert(not game:GetService("RunService"):IsRunning() and not workspace:FindFirstChild("LobbyReimaginedPreview"),"Edit preview conflict")
 assert(at("ServerScriptService.LobbyReimaginedPreview")==parent and parent:GetAttribute("LobbyReimaginedOwned")==true,"Preview owner changed")
 for _,row in ipairs(C.baseline) do
  local i=at(row.path)
  assert(i==ids[row.path] and i.ClassName==row.class and hash(i.Source)==expected[row.path] and hash(SES:GetEditorSource(i))==expected[row.path],"Fresh baseline changed: "..row.path)
 end
verify()
for _,row in ipairs(C.sources) do
 if not row.new then
  local target=ids[row.path];assert(target:GetAttribute("LobbyReimaginedOwned")==true or row.path=="StarterPlayer.StarterPlayerScripts.LobbyReimaginedQueueController","Target ownership missing")
  SES:UpdateSourceAsync(target,function(current)
   verify();assert(hash(current)==expected[row.path],"Editor CAS changed")
   return row.source
  end)
  assert(target.Source==row.source and SES:GetEditorSource(target)==row.source,"Post-write editor conflict")
  expected[row.path]=row.sha256;target:SetAttribute("InstalledSourceSHA256",row.sha256)
 end
