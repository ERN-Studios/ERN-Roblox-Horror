-- Offline before/after native-capture comparison. No Studio connection, no
-- reconstruction and no duplicated forest files. Run after both captures exist.
local fs=require("@lune/fs")
local process=require("@lune/process")
local serde=require("@lune/serde")
local rbx=require("@lune/roblox")
local base=assert(process.args[1],"Pass backup root")
local output=assert(process.args[2],"Pass new compact receipt path")
local function sha(s) return serde.hash("sha256",s) end
local function readPhase(phase)
    local directory=base.."/"..phase
    local m=serde.decode("json",fs.readFile(directory.."/metadata.received.json"))
    assert(m.task=="level3-promotion-20261002" and m.phase==phase)
    assert(m.placeId==131311258779917 and m.universeId==10559217407 and m.groupId==1039373905)
    assert(#m.editorConflicts==0 and #m.skipped==0)
    local chunks={}
    for i=0,m.nativeParts-1 do table.insert(chunks,fs.readFile(directory.."/native-part-"..string.format("%05d",i)..".bin")) end
    local raw=table.concat(chunks)
    assert(#raw==m.nativeBytes and sha(raw)==m.nativeSHA256)
    local roots=rbx.deserializeModel(raw)
    assert(#roots==m.rootCount and #roots==#m.roots)
    local result={}
    for i,row in m.roots do
        assert(roots[i].Name==row.name and roots[i].ClassName==row.class)
        result[row.path]=roots[i]
    end
    return m,result
end
local before,old=readPhase("before")
local after,new=readPhase("after")
local rows={}
for _,path in ipairs({"ServerScriptService.Level 6 Systems","ServerScriptService.Level6PreviewAccess",
    "ServerStorage.Level6BlenderSource","ServerStorage.Level6BlenderSourceRevision20261001",
    "ServerStorage.Level6TextureImportReferences"}) do
    local a=assert(old[path],"Original Level 6 baseline root missing "..path)
    local b=assert(new[path],"Original Level 6 after root missing "..path)
    local ha=sha(rbx.serializeModel({a}))
    local hb=sha(rbx.serializeModel({b}))
    table.insert(rows,{path=path,class=a.ClassName,beforeDescendants=#a:GetDescendants(),
        afterDescendants=#b:GetDescendants(),beforeCanonicalSHA256=ha,afterCanonicalSHA256=hb,
        unchanged=a.ClassName==b.ClassName and a.Name==b.Name and ha==hb})
end
local all=true
for _,row in rows do if not row.unchanged then all=false end end
local report={schema="level3-promotion-original6-captured-native-parity-v1",task=after.task,
    beforeCaptureId=before.captureId,captureId=after.captureId,roots=rows,allFiveOriginal6RootsUnchanged=all,
    studioWritesPerformed=false,nativeFilesReconstructed=false,
    limits="Exact canonical serialization equality of the five original Level 6 captured roots between fresh Edit snapshots. Separately check all original Level 6 Sources and the actual saved native after place. No whole-game geometry, gameplay or publication claim."}
fs.writeFile(output,serde.encode("json",report,true).."\n")
print(serde.encode("json",{captureId=after.captureId,allFiveOriginal6RootsUnchanged=all,output=output},true))
