"""Root-operated manual phases; merely importing/running --help writes no Studio data.

Persistent state lives in the require result of one fresh ModuleScript. No Lua
source container is cloned and no native place backup is created.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
from pathlib import Path
import sys

FOLDER = Path(__file__).resolve().parent
ROOT = FOLDER.parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio

MODULE_NAME = "_OptimizationGeometryInstall_20261009"
OWNER_NO_BACKUP = "Ik tak nogen backup please."
RECEIPT = FOLDER / "runner-receipt.json"
PAYLOAD_FILE = FOLDER / "staged-payload.luau"


def literal(value):
    return json.dumps(json.dumps(value, ensure_ascii=True))


def payload():
    geometry = (FOLDER / "GeometryOptimization.luau").read_text(encoding="utf-8")
    probe = (FOLDER / "NativeMergeProbe.luau").read_text(encoding="utf-8")
    return (
        "-- Task-owned fresh ModuleScript; no native place backup.\n"
        "local Geometry = (function()\n" + geometry + "\nend)()\n"
        "local NativeProbe = (function()\n" + probe + "\nend)()\n"
        "return {Geometry=Geometry, NativeProbe=NativeProbe, Plan=nil, Originals=nil}\n"
    )


GUARD = '''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local SS=game:GetService("ServerStorage")
assert(not game:GetService("RunService"):IsRunning(),"Geometry phase requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
'''

ORIGINAL_CHECK = '''local function originalConflicts(originals)
 local changed={}
 for _,row in ipairs(originals) do
  local ok,editor=pcall(SES.GetEditorSource,SES,row.instance)
  if not ok or row.instance.Source~=row.source or editor~=row.editor
   or row.instance.Parent~=row.parent or row.instance.Name~=row.name or row.instance.ClassName~=row.className
   or row.instance:GetDebugId()~=row.id or row.instance:GetFullName()~=row.path then
   table.insert(changed,row.path)
  end
 end
 return changed
end
local function waitExact(inst,expected)
 local deadline=os.clock()+1
 repeat
  if inst.Source==expected and SES:GetEditorSource(inst)==expected then return end
  assert(not game:GetService("RunService"):IsRunning(),"Play began during Source/editor propagation")
  task.wait(.03)
 until os.clock()>=deadline
 assert(inst.Source==expected and SES:GetEditorSource(inst)==expected,"Source/editor propagation did not become exact within 1 second")
end
local function checked(state,operation)
 assert(state.Originals,"Original staging evidence is missing")
 local pre=originalConflicts(state.Originals)
 assert(#pre==0,"Authoritative original changed before phase; reread Studio: "..table.concat(pre,", "))
 local ok,result=xpcall(operation,debug.traceback)
 local conflicts=originalConflicts(state.Originals)
 assert(#conflicts==0,"Authoritative original changed during success/failure; reconcile Studio without overwriting: "..table.concat(conflicts,", "))
 assert(ok,tostring(result))
 return result
end
'''


def stage_code(body):
    return GUARD + ORIGINAL_CHECK + '''
local name=H:JSONDecode(%s)
assert(SS:FindFirstChild(name)==nil,"Staging module already exists; use the recorded instance or reconcile")
local originals={}
for i,inst in ipairs(game:GetDescendants()) do
 if inst:IsA("LuaSourceContainer") then
  table.insert(originals,{instance=inst,source=inst.Source,editor=SES:GetEditorSource(inst),path=inst:GetFullName(),
   parent=inst.Parent,name=inst.Name,className=inst.ClassName,id=inst:GetDebugId()})
 end
 if i%%1000==0 then task.wait() end
end
assert(not game:GetService("RunService"):IsRunning(),"Play began during staging baseline")
local initial=originalConflicts(originals)
assert(#initial==0,"Original changed during staging baseline; reread Studio")
assert(SS:FindFirstChild(name)==nil,"Concurrent staging module appeared")
local node=Instance.new("ModuleScript")
node.Name=name
assert(node.Source=="" and SES:GetEditorSource(node)=="","Fresh empty Source/editor baseline is not exact")
node.Parent=SS
local source=H:JSONDecode(%s)
local stagedId=node:GetDebugId()
local state,summary
local ok,problem=xpcall(function()
 SES:UpdateSourceAsync(node,function(current)
  assert(not game:GetService("RunService"):IsRunning(),"Play began before staging write")
  assert(node.Parent==SS and node.Name==name and node.ClassName=="ModuleScript" and SS:FindFirstChild(name)==node,"Fresh staging identity changed")
  assert(current=="" and node.Source=="","Staging baseline changed inside write")
  local changed=originalConflicts(originals)
  assert(#changed==0,"Original changed before staging callback; reread Studio")
  return source
 end)
 waitExact(node,source)
 local stagedConflicts=originalConflicts(originals)
 assert(#stagedConflicts==0,"Authoritative original changed during staging; reconcile: "..table.concat(stagedConflicts,", "))
 state=require(node)
 state.Originals=originals
 summary=checked(state,function()
  state.Plan=state.Geometry.Prepare()
  state.ProbeReport=nil
  return state.Geometry.Summary(state.Plan)
 end)
end,debug.traceback)
local conflicts=originalConflicts(originals)
if not ok then
 -- Cleanup ONLY this exact newly created ModuleScript, and check originals again
 -- even if the editor operation failed. No authoritative source is restored.
 local editorOk,currentEditor=pcall(SES.GetEditorSource,SES,node)
 local cleaned=false
 if node.Parent==SS and node.Name==name and node.ClassName=="ModuleScript" and node:GetDebugId()==stagedId
  and #node:GetChildren()==0 and next(node:GetAttributes())==nil and #node:GetTags()==0 and editorOk
  and (node.Source=="" or node.Source==source) and (currentEditor=="" or currentEditor==source) then
  node:Destroy();cleaned=true
 end
 local after=originalConflicts(originals)
 return H:JSONEncode({ok=false,phase="prepareFailed",moduleId=stagedId,moduleCleaned=cleaned,
  authoritativeOriginalsUnchanged=#after==0,originalConflicts=after,error=tostring(problem),nativeBackupCreated=false})
end
assert(#conflicts==0,"Authoritative original changed during staging; preserve and reconcile: "..table.concat(conflicts,", "))
return H:JSONEncode({ok=true,phase="prepared",moduleId=node:GetDebugId(),modulePath=node:GetFullName(),className=node.ClassName,
 payloadBytes=#source,sourceEditorExact=true,authoritativeOriginalsChecked=#originals,summary=summary})
''' % (literal(MODULE_NAME), literal(body))


def existing_code(receipt, body, action):
    return GUARD + ORIGINAL_CHECK + '''
local name=H:JSONDecode(%s)
local matches={}
for _,child in ipairs(SS:GetChildren()) do if child.Name==name then table.insert(matches,child) end end
assert(#matches==1,"Missing/ambiguous staging module; reconcile exact recorded instance")
local node=matches[1]
local expected=H:JSONDecode(%s)
assert(node:GetDebugId()==H:JSONDecode(%s) and node.ClassName=="ModuleScript" and node.Parent==SS,"Staging identity changed")
assert(node.Source==expected and SES:GetEditorSource(node)==expected,"Staged Source/editor changed")
local state=require(node)
local result=checked(state,function()
%s
end)
return H:JSONEncode(result)
''' % (literal(MODULE_NAME), literal(body), literal(receipt["moduleId"]), action)


def save_receipt(data):
    RECEIPT.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def compressed_export_action(page_action):
    # Transport only: the already staged utility and its persistent Plan stay exact.
    return "local page=(function()\n" + page_action + "\nend)()\n" + '''
local E=game:GetService("EncodingService")
local json=H:JSONEncode(page)
local compressed=E:CompressBuffer(buffer.fromstring(json),Enum.CompressionAlgorithm.Zstd,3)
local encoded=E:Base64Encode(compressed)
assert(buffer.tostring(E:Base64Decode(encoded))==buffer.tostring(compressed),"Native Base64 roundtrip differs")
assert(buffer.tostring(E:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd))==json,"Native Zstd roundtrip differs")
local binaryHash=E:ComputeStringHash(json,Enum.HashAlgorithm.Sha256)
local hex={}
for i=1,#binaryHash do hex[i]=string.format("%02x",string.byte(binaryHash,i)) end
return {encoding="zstd-base64",uncompressedBytes=#json,compressedBytes=buffer.len(compressed),
 base64=buffer.tostring(encoded),sha256=table.concat(hex),nativeRoundtripExact=true}
'''


def compressed_manifest_action(first, count):
    return compressed_export_action("return state.Geometry.Manifest(state.Plan,%d,%d)" % (first, count))


POSTAPPLY_HELPERS = '''
assert(state.Plan and state.Plan.Phase=="applied","Successful apply is required for the postapply ledger")
local plan=state.Plan
local function identity(inst)
 return {id=inst:GetDebugId(),path=inst:GetFullName(),parentId=inst.Parent and inst.Parent:GetDebugId() or false,className=inst.ClassName}
end
local function encodeValue(value)
 local kind=typeof(value)
 if kind=="Color3" then return {kind,value.R,value.G,value.B} end
 if kind=="Vector3" then return {kind,value.X,value.Y,value.Z} end
 if kind=="Vector2" then return {kind,value.X,value.Y} end
 if kind=="CFrame" then return {kind,value:GetComponents()} end
 if kind=="EnumItem" then return {kind,tostring(value)} end
 if kind=="BrickColor" then return {kind,value.Number} end
 if kind=="NumberRange" then return {kind,value.Min,value.Max} end
 assert(kind=="boolean" or kind=="number" or kind=="string","Unsupported native ledger value: "..kind)
 return {kind,value}
end
local function nativeValues(inst,schema)
 local props,attrs,keys={}, {}, {}
 for _,pair in ipairs(schema[5]) do table.insert(props,{pair[1],encodeValue(inst[pair[1]])}) end
 local currentAttributes=inst:GetAttributes()
 for key in pairs(currentAttributes) do table.insert(keys,key) end
 table.sort(keys)
 for _,key in ipairs(keys) do table.insert(attrs,{key,encodeValue(currentAttributes[key])}) end
 local tags=inst:GetTags();table.sort(tags)
 local p=inst.CustomPhysicalProperties
 return {inst.ClassName,inst.Name,{inst.CFrame:GetComponents()},{inst.Size.X,inst.Size.Y,inst.Size.Z},props,
  p and {p.Density,p.Friction,p.Elasticity,p.FrictionWeight,p.ElasticityWeight} or false,attrs,tags,#inst:GetChildren()}
end
local function readableAssets(inst)
 local assets={}
 for _,key in ipairs({"AssetId","MeshContent"}) do
  local ok,value=pcall(function() return inst[key] end)
  if ok then
   local entry={type=typeof(value),text=tostring(value)}
   if typeof(value)=="Content" then
    local uriOk,uri=pcall(function() return value.Uri end)
    if uriOk and type(uri)=="string" then entry.uri=uri end
    local typeOk,sourceType=pcall(function() return value.SourceType end)
    if typeOk then entry.sourceType=tostring(sourceType) end
   end
   assets[key]=entry
  end
 end
 return next(assets) and assets or false
end
local descriptors={}
for _,row in ipairs(plan.ChangedCollision) do table.insert(descriptors,{kind="archivedContainedOriginal",before=row.Before,instance=row.Before.Instance,parent=plan.Archive}) end
for _,row in ipairs(plan.ChangedMerges) do
 table.insert(descriptors,{kind="exactMergeProxy",instance=row.Proxy,parent=plan.Collision,values=row.ExpectedValues,fingerprint=row.ExpectedFingerprint})
 for _,before in ipairs(row.Before) do table.insert(descriptors,{kind="archivedMergedOriginal",before=before,instance=before.Instance,parent=plan.Archive}) end
end
for _,before in ipairs(plan.ChangedLOD) do table.insert(descriptors,{kind="renderFidelity",before=before,instance=before.Instance,parent=before.Parent}) end
'''


def postapply_info_action():
    return POSTAPPLY_HELPERS + '''
local verification=state.Geometry.Verify(plan)
return {verification=verification,total=#descriptors,archive=identity(plan.Archive),collision=identity(plan.Collision),level6=identity(plan.Level6)}
'''


def compressed_postapply_action(first, count):
    return compressed_export_action(POSTAPPLY_HELPERS + '''
local output={startIndex=%d,total=#descriptors,rows={},archive=identity(plan.Archive)}
for index=%d,math.min(%d+%d-1,#descriptors) do
 local descriptor=descriptors[index]
 local inst=descriptor.instance
 assert(inst and inst.Parent==descriptor.parent,"Postapply ledger instance/parent changed")
 local expectedValues=descriptor.values or descriptor.before.Values
 local expectedFingerprint=descriptor.fingerprint or descriptor.before.Fingerprint
 if descriptor.before then assert(inst:GetDebugId()==descriptor.before.Id,"Postapply original identity changed") end
 if descriptor.kind=="renderFidelity" then
  expectedValues=H:JSONDecode(H:JSONEncode(expectedValues))
  for _,pair in ipairs(expectedValues[5]) do if pair[1]=="RenderFidelity" then pair[2]={"EnumItem","Enum.RenderFidelity.Automatic"} end end
  expectedFingerprint=H:JSONEncode(expectedValues)
 end
 local current=nativeValues(inst,expectedValues)
 local fingerprint=H:JSONEncode(current)
 assert(fingerprint==expectedFingerprint,"Fresh postapply native fingerprint changed: "..inst:GetFullName())
 local row=identity(inst);row.kind=descriptor.kind
 if descriptor.kind=="renderFidelity" then
  row.renderFidelity=tostring(inst.RenderFidelity);row.collisionFidelity=tostring(inst.CollisionFidelity)
  row.assetReferences=readableAssets(inst)
 else
  row.values=current;row.fingerprint=fingerprint
  if descriptor.before then row.beforePath=descriptor.before.Path;row.beforeParentId=descriptor.before.ParentId end
 end
 table.insert(output.rows,row)
end
return output
''' % (first, first, first, count))


def decode_manifest(envelope):
    vendor = ROOT / "_local" / "optimization-20261009" / "vendor"
    sys.path.insert(0, str(vendor))
    import zstandard
    assert zstandard.__version__ == "0.25.0", "Use the task-isolated reviewed zstandard 0.25.0"
    assert envelope["encoding"] == "zstd-base64" and envelope["nativeRoundtripExact"] is True, "Native transport verification is missing"
    expected = envelope["uncompressedBytes"]
    assert isinstance(expected, int) and 0 < expected <= 64 * 1024 * 1024, "Invalid/beyond-budget native manifest size"
    compressed = base64.b64decode(envelope["base64"], validate=True)
    assert len(compressed) == envelope["compressedBytes"], "Compressed transport byte count differs"
    raw = zstandard.ZstdDecompressor().decompress(compressed, max_output_size=expected)
    assert len(raw) == expected, "Decompressed manifest byte count differs"
    digest = hashlib.sha256(raw).hexdigest()
    assert digest == envelope["sha256"], "Native and local SHA256 differ for the exact manifest bytes"
    page = json.loads(raw.decode("utf-8"))
    return page, raw, {"encoding": envelope["encoding"], "uncompressedBytes": expected,
                       "compressedBytes": len(compressed), "sha256": digest,
                       "compressedSha256": hashlib.sha256(compressed).hexdigest(), "nativeRoundtripExact": True}


def capture_pages(call, receipt, body, total, destination, page_size, action_factory):
    destination.mkdir(exist_ok=True)
    first, count, pages = 1, min(max(page_size, 1), 250), []
    while first <= total:
        try:
            envelope = call(existing_code(receipt, body, action_factory(first, count)))
            page, data, transport = decode_manifest(envelope)
        except json.JSONDecodeError:
            if count == 1:
                raise
            count = max(1, count // 2)
            continue
        assert page["startIndex"] == first and page["total"] == total and page["rows"], "Incomplete manifest page"
        assert len(page["rows"]) <= count and first + len(page["rows"]) - 1 <= total, "Out-of-range manifest page"
        path = destination / ("page-%06d.json" % first)
        path.write_bytes(data)  # exact, unmodified native JSON, including fingerprints
        pages.append({"path": str(path.relative_to(ROOT)), "first": first, "rows": len(page["rows"]), **transport})
        first += len(page["rows"])
    return pages


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    phases = parser.add_mutually_exclusive_group(required=True)
    for phase in ("prepare", "manifest", "probe", "apply", "verify", "cleanup"):
        phases.add_argument("--" + phase, action="store_true")
    parser.add_argument("--owner-no-backup", help="Exact explicit owner instruction; required only for --apply")
    parser.add_argument("--page-size", type=int, default=10, help="Manifest rows per call, capped at 250; automatically reduced for truncated JSON")
    args = parser.parse_args()
    phase = next(p for p in ("prepare", "manifest", "probe", "apply", "verify", "cleanup") if getattr(args, p))
    if phase == "apply":
        assert args.owner_no_backup == OWNER_NO_BACKUP, "Supply the exact owner instruction: " + OWNER_NO_BACKUP
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")

        def call(code):
            raw = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
            return json.loads(raw)

        if phase == "prepare":
            previous = json.loads(RECEIPT.read_text(encoding="utf-8")) if RECEIPT.exists() else None
            assert previous is None or previous.get("phase") == "prepareFailed" and previous.get("moduleCleaned") \
                and previous.get("authoritativeOriginalsUnchanged"), "A previous runner receipt exists; finish/reconcile that exact staged module first"
            body = payload()
            PAYLOAD_FILE.write_text(body, encoding="utf-8", newline="\n")
            receipt = {"phase": "pendingPrepare", "studioId": sid, "moduleName": MODULE_NAME,
                       "payloadSha256": hashlib.sha256(body.encode()).hexdigest(), "nativeBackupCreated": False}
            if previous:
                receipt["previousCleanedFailure"] = previous
            save_receipt(receipt)
            result = call(stage_code(body))
            receipt.update(result)
            save_receipt(receipt)
            print(json.dumps(result, ensure_ascii=False, indent=2))
            if not result.get("ok"):
                raise RuntimeError(result.get("error", "Geometry preparation failed; inspect the explicit cleanup receipt"))
            return

        receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
        assert receipt["studioId"] == sid and receipt.get("moduleId"), "Pending stage or different Studio; reconcile before continuing"
        body = PAYLOAD_FILE.read_bytes().decode("utf-8")
        assert hashlib.sha256(body.encode()).hexdigest() == receipt["payloadSha256"], "Staged payload file changed"
        receipt["pendingPhase"] = phase
        save_receipt(receipt)

        if phase == "manifest":
            info = call(existing_code(receipt, body, '''
assert(state.Plan,"Prepare first")
state.Geometry.AssertPlan(state.Plan)
return {summary=state.Geometry.Summary(state.Plan),total=state.Geometry.Manifest(state.Plan,1,1).total}
'''))
            pages = capture_pages(call, receipt, body, info["total"], FOLDER / "manifest", args.page_size, compressed_manifest_action)
            call(existing_code(receipt, body, "state.Geometry.AssertPlan(state.Plan); return {exactBaseline=true}"))
            receipt.update(manifest={"summary": info["summary"], "totalRows": info["total"], "pages": pages})
            result = {"phase": "manifestCaptured", "rows": info["total"], "pages": len(pages)}
        elif phase == "probe":
            result = call(existing_code(receipt, body, '''
assert(state.Plan,"Prepare first")
state.ProbeReport=state.NativeProbe(state.Plan,state.Geometry)
return state.ProbeReport
'''))
            receipt["nativeProbe"] = result
        elif phase == "apply":
            assert receipt.get("manifest"), "Capture/review the complete exact manifest before apply"
            assert receipt.get("nativeProbe", {}).get("authoritativeOriginalsUnchanged"), "Native actual-collider probe must pass before apply"
            instruction = literal(args.owner_no_backup)
            result = call(existing_code(receipt, body, '''
assert(state.Plan and state.ProbeReport and state.ProbeReport.authoritativeOriginalsUnchanged,"Native probe evidence is missing")
return state.Geometry.Apply(state.Plan,{ownerExplicitlyForbidsNewBackups=true,ownerInstruction=H:JSONDecode(%s)})
''' % instruction))
            receipt["apply"] = result
        elif phase == "verify":
            info = call(existing_code(receipt, body, postapply_info_action()))
            pages = capture_pages(call, receipt, body, info["total"], FOLDER / "postapply-manifest", args.page_size, compressed_postapply_action)
            final = call(existing_code(receipt, body, postapply_info_action()))
            assert final == info, "Postapply verification/identity changed while exporting the ledger"
            receipt["postapplyLedger"] = {"totalRows": info["total"], "pages": pages,
                                           "archive": info["archive"], "collision": info["collision"], "level6": info["level6"]}
            result = info["verification"]
            result["postapplyLedgerCaptured"] = {"rows": info["total"], "pages": len(pages), "archive": info["archive"]}
            receipt["verify"] = result
        else:
            result = call(existing_code(receipt, body, '''
local originals=state.Originals
assert(node.Parent==SS and node.Name==name and node.Source==expected and SES:GetEditorSource(node)==expected,"Cleanup exact Source/editor identity changed")
assert(#node:GetChildren()==0 and next(node:GetAttributes())==nil and #node:GetTags()==0,"Staged module gained unrelated children/attributes/tags; preserve and reconcile")
node:Destroy() -- the exact fresh task-owned ModuleScript only
local after=originalConflicts(originals)
assert(#after==0,"Authoritative original changed during cleanup; reconcile: "..table.concat(after,", "))
return {stagedModuleCleaned=true,authoritativeOriginalsUnchanged=true,originalsChecked=#originals}
'''))
            receipt["cleanup"] = result
        receipt.pop("pendingPhase", None)
        receipt["phase"] = phase + "Complete"
        save_receipt(receipt)
        print(json.dumps(result, ensure_ascii=False, indent=2))
    finally:
        client.close()


if __name__ == "__main__":
    main()
