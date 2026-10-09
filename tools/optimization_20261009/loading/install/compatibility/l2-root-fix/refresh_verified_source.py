"""Scoped fresh native read + correction export/current mirror refresh.

Preserves initial install/promotion/native receipts. Only the controller row of
the seven-source task export is revised. Never changes Studio/global manifest/git
or creates a backup. --apply-mirrors is the authorized local-copy boundary.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE=Path(__file__).resolve().parent
TASK=HERE.parents[3]
ROOT=TASK.parents[1]
EXPORT=TASK/"verified-export"
sys.path.insert(0,str(TASK));sys.path.insert(0,str(EXPORT))
from native_probe_runner import StudioMcpClient,find_mcp_batch,literal,select_studio
from export_verified_sources import GUARD
from promote_verified_mirrors import copy_exact,local_snapshot

TARGET="StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient"


def sha(raw):return hashlib.sha256(raw).hexdigest()


def reviewed_rows():
    manifest=json.loads((EXPORT/"manifest.json").read_text(encoding="utf-8"))
    correction=json.loads((HERE/"source-install-manifest.json").read_text(encoding="utf-8"))["scripts"][0]
    sources=[]
    for row in manifest["scripts"]:
        raw=(ROOT/row["rawFile"]).read_bytes()
        assert sha(raw)==row["rawSourceSha256"]
        if row["path"]==TARGET:
            raw=(ROOT/correction["afterFile"]).read_bytes()
            assert sha(raw)==correction["afterSha256"]
        identity={key:row[key] for key in ("path","name","instanceId","parentId","parentPath","parentClass")}
        sources.append({"segments":row["segments"],"class":row["class"],"source":raw.decode("utf-8"),"sha256":sha(raw),"identity":identity})
    assert len(sources)==7
    return sources


def read_native(sources,include_source=False):
    code=GUARD+'''local expected=H:JSONDecode(%s)
local pins={}
local correctedSource=nil
for _,row in ipairs(expected) do
 local node,source=check(row)
 local properties={}
 for _,key in ipairs({"Archivable","LinkedSource","Disabled","RunContext"}) do
  local ok,value=pcall(function() return node[key] end)
  if ok then properties[key]=if typeof(value)=="EnumItem" then tostring(value) else value end
 end
 local attributes={}
 for key,value in pairs(node:GetAttributes()) do
  if typeof(value)=="string" or typeof(value)=="boolean" or typeof(value)=="number" then attributes[key]=value end
 end
 table.insert(pins,{path=node:GetFullName(),segments=row.segments,class=node.ClassName,name=node.Name,
  instanceId=node:GetDebugId(16),parentId=node.Parent:GetDebugId(16),parentPath=node.Parent:GetFullName(),parentClass=node.Parent.ClassName,
  rawBytes=#source,sourceSha256=row.sha256,editorParity=true,properties=properties,attributes=attributes})
 if node:GetFullName()=="StarterPlayer.StarterPlayerScripts.SceneEffectBudgetClient" then correctedSource=source end
end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),readOnly=true,complete=true,pins=pins,correctedSource=if %s then correctedSource else nil})
'''%(literal(sources),"true" if include_source else "false")
    client=StudioMcpClient(find_mcp_batch())
    try:
        client.initialize();studio=select_studio(client,"[UPDATE] BACKROOMS: STAY QUIET",25)
        sid=studio.get("studio_id") or studio.get("id")
        response=client.call("execute_luau",{"studio_id":sid,"datamodel_type":"Edit","code":code})
        assert len(response.encode("utf-8"))<=12000
        result=json.loads(response);assert result["complete"] and len(result["pins"])==7
        result["studioId"]=sid;return result
    finally:client.close()


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply-mirrors",action="store_true")
    args=parser.parse_args()
    receipt_path=HERE/"verified-source-refresh-receipt.json"
    assert not receipt_path.exists(),"Preserve existing correction refresh receipt"
    install=json.loads((HERE/"source-install-receipt.json").read_text(encoding="utf-8"));assert install["complete"]
    sources=reviewed_rows()
    native=read_native(sources,True)
    pin=next(row for row in native["pins"] if row["path"]==TARGET)
    raw=native.pop("correctedSource").encode("utf-8")
    assert len(raw)==pin["rawBytes"]==3537 and sha(raw)==pin["sourceSha256"]
    before=(HERE/"SceneEffectBudgetClient.before.luau").read_bytes()
    corrected=(HERE/"SceneEffectBudgetClient.proposed.luau").read_bytes();assert raw==corrected
    relative=Path("StarterPlayer/StarterPlayerScripts/SceneEffectBudgetClient.LocalScript.lua")
    scoped_raw=HERE/"verified-export"/relative
    scoped_raw.parent.mkdir(parents=True,exist_ok=True);assert not scoped_raw.exists();scoped_raw.write_bytes(raw)
    current_raw=EXPORT/relative;runtime=ROOT/relative
    rows=[]
    for destination in (current_raw,runtime):
        row={"destination":destination,"nativeBefore":before,"raw":raw,"rawPath":scoped_raw,
             "captured":{"rawFile":scoped_raw.relative_to(ROOT).as_posix()}}
        old,record=local_snapshot(row);rows.append((row,old,record))
    manifest_path=EXPORT/"manifest.json";manifest_before=manifest_path.read_bytes();manifest=json.loads(manifest_before)
    previous=next(row for row in manifest["scripts"] if row["path"]==TARGET)
    updated=dict(previous)
    updated.update(rawBytes=len(raw),rawSourceSha256=sha(raw),reviewedCandidateSha256=sha(raw),editorParity=True,
        currentSourceVerifiedUtc=native["verifiedUtc"],currentSourceCaptureTransport="JSON UTF-8 string; full exact Source/editor/identity CAS",
        reviewedCandidateManifest=(HERE/"source-install-manifest.json").relative_to(ROOT).as_posix(),
        sourceRefreshReceipt=receipt_path.relative_to(ROOT).as_posix(),
        chunks=[{"offset":0,"rawBytes":len(raw),"exactSourceEditorIdentityCas":True,"transport":"JSON UTF-8 string"}])
    manifest["scripts"]=[updated if row["path"]==TARGET else row for row in manifest["scripts"]]
    assert [row for row in manifest["scripts"] if row["path"]!=TARGET]==[row for row in json.loads(manifest_before)["scripts"] if row["path"]!=TARGET]
    receipt={"startedUtc":datetime.now(timezone.utc).isoformat(),"nativeBegin":native,
        "scopedRawFile":scoped_raw.relative_to(ROOT).as_posix(),"sourceSha256":sha(raw),"rawBytes":len(raw),
        "previousSevenExportControllerRow":previous,"updatedSevenExportControllerRow":updated,
        "sevenExportManifestBeforeSha256":sha(manifest_before),"localCopies":[record for _,_,record in rows],
        "applyMirrors":args.apply_mirrors,"studioMutation":False,"nativeBackup":False,"globalManifestWritten":False,
        "initialReceiptsOverwritten":False,"complete":False}
    def save():receipt_path.write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    save()
    try:
        if args.apply_mirrors:
            for row,old,record in rows:
                record["copied"]=copy_exact(row,old)
                record["copiedRawSha256"]=sha(row["destination"].read_bytes());assert record["copiedRawSha256"]==sha(raw)
                save()
            assert manifest_path.read_bytes()==manifest_before,"Concurrent task export manifest changed"
            manifest_path.write_text(json.dumps(manifest,indent=2)+"\n",encoding="utf-8")
            receipt["sevenExportManifestAfterSha256"]=sha(manifest_path.read_bytes())
        receipt["nativeEnd"]=read_native(sources)
        assert all(row["sourceSha256"]==row2["sourceSha256"] for row,row2 in zip(native["pins"],receipt["nativeEnd"]["pins"]))
        receipt["complete"]=True
        print(f"Fresh correction export {len(raw)} bytes {sha(raw)}; mirrors applied={args.apply_mirrors}; all seven native Source/editor/identity pins passed; global manifest untouched.")
    except Exception as error:
        receipt["error"]=f"{type(error).__name__}: {error}";raise
    finally:
        receipt["finishedUtc"]=datetime.now(timezone.utc).isoformat();save()


if __name__=="__main__":main()
