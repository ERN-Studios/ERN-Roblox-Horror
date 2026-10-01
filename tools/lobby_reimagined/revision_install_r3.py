"""Generate a pinned R3 import with exact Source/editor CAS and additive payloads."""
import json
from pathlib import Path
from serve import load_package, sha
from install import long_string

ROOT = Path(__file__).resolve().parents[2]
TASK = ROOT / "artifacts/lobby-reimagined-r3-20261001"
HERE = Path(__file__).resolve().parent
NEW_PATH = "ServerScriptService.LobbyReimaginedPreview.QueueBridge"
package = load_package(ROOT / "assets/models/lobby-reimagined-r3-20261001",
                       HERE / "source_module_manifest_r3.json",
                       "LobbyReimaginedBlenderSource20261001R3", True)
plan = package["plan"]
by_path = {row["path"]: row for row in json.loads((TASK / "native-before/source-manifest.json").read_text())["scripts"]}
expected = []
for spec in plan["sources"]:
    if spec["path"] == NEW_PATH:
        assert spec["path"] not in by_path
        expected.append({"path": NEW_PATH, "class": "ModuleScript", "isNew": True})
    else:
        row = dict(by_path[spec["path"]])
        row["owned"] = ".LobbyReimaginedPreview." in row["path"] or row["path"].endswith(".LobbyReimaginedQueueController")
        expected.append(row)

# Verify shared candidates are exact scoped changes to the captured authoritative source.
baseline = {row["path"]: row for row in json.loads((TASK / "native-before/scripts.json").read_text())}
for name, key in [("GameManager.queue", "game-manager"), ("LobbyShopDisplay.focus", "shop-focus"),
                  ("Level4V4PreviewAccess.entry", "level4-preview"), ("Level5PreviewAccess.entry", "level5-preview"),
                  ("Level6PreviewAccess.entry", "level6-preview")]:
    change = json.loads((TASK / "shared-candidates" / (name + "-replacements.json")).read_text())
    spec = next(row for row in plan["sources"] if row["key"] == key)
    source = baseline[spec["path"]]["source"]
    assert sha(source.encode()) == change["beforeSha256"] == by_path[spec["path"]]["sourceSha256"]
    for replacement in change["replacements"]:
        if replacement.get("at") == "EOF":
            assert replacement["old"] == ""
            source += replacement["new"]
        else:
            assert source.count(replacement["old"]) == 1, replacement["label"]
            source = source.replace(replacement["old"], replacement["new"], 1)
    assert sha(source.encode()) == change["afterSha256"] == spec["sha256"], name

code = r'''-- R3: additive Blender payload, one new bridge, nine fresh-baseline Sources.
local HS=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local SES=game:GetService("ScriptEditorService")
local SS=game:GetService("ServerStorage")
local PLAN=HS:JSONDecode(__PLAN__)
local EXPECTED=HS:JSONDecode(__EXPECTED__)
local BASE="http://127.0.0.1:8892"
assert(game.PlaceId==PLAN.placeId and game.GameId==PLAN.universeId and game.CreatorId==PLAN.groupId)
assert(not game:GetService("RunService"):IsRunning(),"Edit only")
assert(not SS:FindFirstChild(PLAN.sourceName),"R3 payload already exists; inspect it")
local function sha(raw)
 local b=E:ComputeBufferHash(raw,Enum.HashAlgorithm.Sha256);local t={}
 for i=0,buffer.len(b)-1 do t[i+1]=string.format("%02x",buffer.readu8(b,i))end
 return table.concat(t)
end
local function resolve(path)
 local cursor=game
 for token in path:gmatch("[^%.]+")do cursor=cursor and cursor:FindFirstChild(token)end
 return cursor
end
local baseline={}
for _,row in ipairs(EXPECTED)do
 local instance=resolve(row.path)
 if row.isNew then
  assert(not instance,"New bridge namespace occupied")
  local parent=assert(resolve(row.path:match("^(.*)%.[^.]+$")))
  assert(parent:GetAttribute("LobbyReimaginedOwned")==true,"Bridge parent not ours")
  baseline[row.path]={parent=parent,isNew=true}
 else
  assert(instance and instance.ClassName==row.class,"Exact baseline instance missing")
  if row.owned then assert(instance:GetAttribute("LobbyReimaginedOwned")==true)end
  local source=instance.Source
  assert(sha(buffer.fromstring(source))==row.sourceSha256 and SES:GetEditorSource(instance)==source,"Fresh Source/editor differs: "..row.path)
  baseline[row.path]={instance=instance,source=source,owned=row.owned}
 end
end
local source=Instance.new("Folder");source.Name=PLAN.sourceName;source:SetAttribute("LobbyReimaginedOwned",true)
local function compressed(name,raw,parent,expected)
 assert(buffer.len(raw)==expected.bytes and sha(raw)==expected.sha256,"Wrong R3 payload "..name)
 local folder=Instance.new("Folder");folder.Name=name;folder.Parent=parent
 local packed=E:CompressBuffer(raw,Enum.CompressionAlgorithm.Zstd,3)
 local encoded=buffer.tostring(E:Base64Encode(packed))
 for offset=1,#encoded,60000 do
  local item=Instance.new("StringValue");item.Name=string.format("%05d",math.floor((offset-1)/60000));item.Value=encoded:sub(offset,offset+59999);item.Parent=folder
 end
 folder:SetAttribute("RawBytes",buffer.len(raw));folder:SetAttribute("RawSHA256",expected.sha256);folder:SetAttribute("CompressedBytes",buffer.len(packed))
end
local oldHttp=HS.HttpEnabled
local texts={}
local ok,err=pcall(function()
 HS.HttpEnabled=true
 local serverPlan=HS:JSONDecode(HS:GetAsync(BASE.."/source-module-manifest",true))
 assert(serverPlan.manifestSha256==PLAN.manifestSha256 and serverPlan.sourceName==PLAN.sourceName)
 compressed("ManifestJSON",buffer.fromstring(HS:GetAsync(BASE.."/manifest",true)),source,{bytes=PLAN.manifestBytes,sha256=PLAN.manifestSha256})
 local meshes=Instance.new("Folder");meshes.Name="Meshes";meshes.Parent=source
 for _,chunk in ipairs(PLAN.chunks)do
  compressed(tostring(chunk.id),E:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/chunk/"..chunk.id,true))),meshes,chunk)
 end
 compressed("AtlasPixels",E:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/atlas-pixels",true))),source,PLAN.atlas)
 for _,spec in ipairs(PLAN.sources)do
  local text=HS:GetAsync(BASE.."/script/"..spec.key,true)
  assert(#text==spec.bytes and sha(buffer.fromstring(text))==spec.sha256,"Candidate Source differs")
  texts[spec.path]=text
 end
 assert(not SS:FindFirstChild(PLAN.sourceName) and not game:GetService("RunService"):IsRunning())
 for path,row in pairs(baseline)do
  if row.isNew then assert(not resolve(path) and row.parent==resolve(path:match("^(.*)%.[^.]+$")),"New bridge baseline changed")
  else assert(resolve(path)==row.instance and row.instance.Source==row.source and SES:GetEditorSource(row.instance)==row.source,"Baseline changed during download: "..path)end
 end
 -- Create our additive bridge first; existing shared instances retain their attributes.
 for _,spec in ipairs(PLAN.sources)do
  local row=baseline[spec.path]
  if row.isNew then
   assert(not resolve(spec.path))
   local instance=Instance.new(spec.class);instance.Name=spec.path:match("[^.]+$")
   instance:SetAttribute("LobbyReimaginedOwned",true);instance.Parent=row.parent
   row.instance=instance;row.source=instance.Source;row.owned=true
  end
 end
 source:SetAttribute("ManifestSHA256",PLAN.manifestSha256);source:SetAttribute("Ready",true);source.Parent=SS
 local changed=0
 for _,spec in ipairs(PLAN.sources)do
  local row=baseline[spec.path]
  assert(resolve(spec.path)==row.instance and row.instance.Source==row.source and SES:GetEditorSource(row.instance)==row.source,"Fresh Source changed before scoped write: "..spec.path)
  if row.source~=texts[spec.path] then
   SES:UpdateSourceAsync(row.instance,function(editor)
    assert(editor==row.source and row.instance.Source==row.source,"Source changed inside CAS callback")
    return texts[spec.path]
   end)
   changed+=1
  end
  assert(row.instance.Source==texts[spec.path] and SES:GetEditorSource(row.instance)==texts[spec.path],"Post-write Source/editor conflict")
  if row.owned then row.instance:SetAttribute("InstalledSourceSHA256",spec.sha256)end
 end
 source:SetAttribute("ChangedSources",changed)
end)
HS.HttpEnabled=oldHttp
if not ok then
 if not source.Parent then source:Destroy()end
 error(err) -- Never roll back live developer work after a partial conflict.
end
return {Installed=true,Source=source:GetFullName(),ManifestSHA256=PLAN.manifestSha256,Sources=#PLAN.sources,ChangedSources=source:GetAttribute("ChangedSources"),Chunks=#PLAN.chunks}
'''
code = code.replace("__PLAN__", long_string(json.dumps(plan, separators=(",", ":")))).replace("__EXPECTED__", long_string(json.dumps(expected, separators=(",", ":"))))
output = TASK / "install_revision_r3.luau"
assert not output.exists() or output.read_text() == code, "Refusing different revision installer"
output.write_text(code)
output.with_suffix(".receipt.json").write_text(json.dumps({"sha256": sha(code.encode()), "manifestSha256": plan["manifestSha256"], "sources": plan["sources"], "expected": expected,
 "scope": "Additive R3 payload + new owned QueueBridge; nine pinned Source/editor comparisons; original Source changes replay exactly five scoped replacement sets."}, indent=2) + "\n")
print("R3 installer generated", plan["manifestSha256"])
