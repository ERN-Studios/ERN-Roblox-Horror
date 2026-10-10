"""Point-in-time metadata/hash-only Studio parity diagnostic; zero native writes."""
from pathlib import Path
from datetime import datetime, timezone
import hashlib
import json
import subprocess
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, mirrored_candidates
from studio_source_contract import canonical_bytes

SID = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
PAGE = 24
CODE = r'''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local RS=game:GetService("RunService")
local function mode()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
 assert(not RS:IsRunning(),"Authoritative Edit read only; no mode switch")
end
local function sha(text)
 local b=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(b)-1 do out[#out+1]=string.format("%02x",buffer.readu8(b,i)) end
 return table.concat(out)
end
local function stable(v)
 if type(v)~="table" then return H:JSONEncode(v) end
 local keys={} for key in v do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=H:JSONEncode(key)..":"..stable(v[key]) end
 return "{"..table.concat(out,",").."}"
end
local function segments(n)
 local out={} while n~=game do table.insert(out,1,n.Name);n=n.Parent;assert(n,"Detached during census") end
 return out
end
local function catalog()
 mode()
 local rows,conflicts={},{}
 local census=game:GetDescendants()
 for i,n in census do
  if n:IsA("LuaSourceContainer") or n.ClassName=="RemoteEvent" then
   local row={segments=segments(n),path=n:GetFullName(),className=n.ClassName,
    instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),properties={},propertyReadErrors={}}
   for _,name in {"Enabled","Disabled","RunContext","Archivable","LinkedSource"} do
    if n:IsA("LuaSourceContainer") or name=="Archivable" then
     local ok,value=pcall(function()return n[name]end)
     if ok then row.properties[name]=if typeof(value)=="EnumItem" then tostring(value) else value
     elseif name=="Archivable" or name=="LinkedSource" or n.ClassName~="ModuleScript" then row.propertyReadErrors[#row.propertyReadErrors+1]=name end
    end
   end
   if n:IsA("LuaSourceContainer") then
    local ok,source=pcall(function()return n.Source end)
    local editorOk,editor=pcall(function()return SES:GetEditorSource(n)end)
    row.sourceReadable=ok row.editorReadable=editorOk
    if ok then
     local canonical=source:gsub("\r\n","\n")
     row.rawSourceSHA256=sha(source) row.sourceSHA256=sha(canonical) row.rawBytes=#source row.canonicalBytes=#canonical
     if canonical:sub(-1)=="\n" then row.minusOneTrailingLFSHA256=sha(canonical:sub(1,-2)) end
    end
    if editorOk then row.rawEditorSHA256=sha(editor) row.editorSHA256=sha(editor:gsub("\r\n","\n")) end
    row.sourceEditorMatches=ok and editorOk and source==editor
    row.readStable=ok and editorOk and n.Source==source and SES:GetEditorSource(n)==editor
    if not row.sourceEditorMatches or not row.readStable then conflicts[#conflicts+1]=row.path end
   end
   rows[#rows+1]=row
  end
  if i%10000==0 then task.wait();mode() end
 end
 table.sort(rows,function(a,b)return stable(a.segments)..a.className<stable(b.segments)..b.className end)
 mode()
 return rows,{catalogSHA256=sha(stable(rows)),rowCount=#rows,sceneCount=#census,
  serverStorageRootCount=#game:GetService("ServerStorage"):GetChildren(),sourceEditorConflictCount=#conflicts,
  conflicts=conflicts,readAtUtc=DateTime.now():ToIsoDate(),datamodel="Edit",placeId=game.PlaceId,universeId=game.GameId}
end
'''


def sha(raw): return hashlib.sha256(raw).hexdigest()


def new(name, value):
    raw = value if isinstance(value, bytes) else (json.dumps(value, indent=2) + "\n").encode()
    with (HERE / name).open("xb") as stream: assert stream.write(raw) == len(raw)


def repo_snapshot():
    raw = (ROOT / "studio-sync-manifest.json").read_bytes()
    files = {}
    for name in sorted(mirrored_candidates(ROOT)):
        data = (ROOT / name).read_bytes()
        row = {"rawSHA256": sha(data), "bytes": len(data)}
        if name.endswith(".lua"): row["sourceSHA256"] = sha(canonical_bytes(data.decode("utf-8")))
        files[name] = row
    return raw, files


def main():
    assert not (HERE / "result.json").exists()
    new(".gitattributes", b"* -text -whitespace\n")
    new("native-reader.luau", CODE.encode())
    before_raw, before_files = repo_snapshot()
    manifest = json.loads(before_raw)
    new("repo-before-metadata.json", {"manifestRawSHA256":sha(before_raw),"declaredCounts":manifest["counts"],"files":before_files})
    native_rows = []
    report = {"schema":"mongotv-final-parity-diagnostic-v1","complete":False,"nativeWrites":0,
              "repositorySourceWrites":0,"manifestWrites":0,"modeSwitches":0,"studioId":SID,
              "limits":"Metadata/hash snapshot of authoritative Edit Sources. No gameplay, full native assets, publication or continuous epoch guarantee. Failed stability guards leave partial evidence."}
    client = None
    primary = None
    try:
        client = StudioMcpClient(find_mcp_batch()); client.initialize()
        studio = select_studio(client,"[UPDATE] BACKROOMS: STAY QUIET",20)
        assert (studio.get("studio_id") or studio.get("id"))==SID
        state_raw = client.call("get_studio_state",{"studio_id":SID})
        assert len(state_raw.encode())<=16000,"State metadata response bound exceeded"
        new("studio-state-before.txt",state_raw.encode())
        new("studio-state-before.json",{"format":"MCP state text","sha256":sha(state_raw.encode()),"bytes":len(state_raw.encode())})
        def call(suffix):
            output=client.call("execute_luau",{"studio_id":SID,"datamodel_type":"Edit","code":CODE+suffix})
            assert len(output.encode())<=32000,"Diagnostic response bound exceeded"
            return json.loads(output)
        begin=call('local rows,meta=catalog() return H:JSONEncode(meta)')
        report["nativeBegin"]=begin
        new("native-begin.json",begin)
        if begin["sourceEditorConflictCount"]:
            print("SOURCE/EDITOR CONFLICT: "+json.dumps(begin["conflicts"]),flush=True)
        for offset in range(0,begin["rowCount"],PAGE):
            result=call('local rows,meta=catalog() assert(meta.catalogSHA256=="'+begin["catalogSHA256"]+'","Native Source/editor/identity/property drift during diagnostic") '
                        +f'local page={{}} for i={offset+1},math.min(#rows,{offset+PAGE}) do page[#page+1]=rows[i] end '
                        +'return H:JSONEncode({rows=page,meta=meta})')
            new(f"native-page-{offset//PAGE:02d}.json",result)
            native_rows.extend(result["rows"])
        end=call('local rows,meta=catalog() assert(meta.catalogSHA256=="'+begin["catalogSHA256"]+'","Final native catalog changed") return H:JSONEncode(meta)')
        new("native-end.json",end); report["nativeEnd"]=end
        after_raw, after_files=repo_snapshot()
        new("repo-after-metadata.json",{"manifestRawSHA256":sha(after_raw),"files":after_files})
        report["repoSnapshotStable"]=after_raw==before_raw and after_files==before_files
        assert report["repoSnapshotStable"],"Concurrent repository/manifest changes; compare partial snapshot honestly"
        assert len(native_rows)==begin["rowCount"]
        entries={tuple(row["segments"]):row for row in manifest["items"]}
        assert len(entries)==len(manifest["items"]),"Duplicate manifest paths"
        native={tuple(row["segments"]):row for row in native_rows}
        assert len(native)==len(native_rows),"Duplicate native paths"
        mismatches=[]; coverage=[]; extra=[]
        for key,row in native.items():
            entry=entries.get(key)
            if entry is None: extra.append({"path":row["path"],"className":row["className"]});continue
            if row["className"]!=entry["className"]: mismatches.append({"path":row["path"],"kind":"manifestClass","native":row["className"],"manifest":entry["className"]})
            for name,value in row["properties"].items():
                if name in entry.get("properties",{}):
                    if entry["properties"][name]!=value: mismatches.append({"path":row["path"],"kind":"property","property":name,"native":value,"manifest":entry["properties"][name]})
                elif name in ("Enabled","Disabled","RunContext"):
                    coverage.append({"path":row["path"],"unrecordedManifestProperty":name,"native":value})
            if row["className"] in ("Script","LocalScript","ModuleScript"):
                file=entry["file"]; mirror=before_files.get(file)
                accepted={row.get("sourceSHA256")}
                if entry.get("studioTrailingNewline") is True: accepted.add(row.get("minusOneTrailingLFSHA256"))
                if not row.get("sourceReadable") or not row.get("editorReadable") or not row.get("sourceEditorMatches") or not row.get("readStable"):
                    mismatches.append({"path":row["path"],"kind":"nativeSourceEditorReadConflict"})
                if mirror is None: mismatches.append({"path":row["path"],"kind":"missingWorkingMirror","file":file})
                elif mirror["sourceSHA256"] not in accepted:
                    mismatches.append({"path":row["path"],"kind":"workingSourceHash","file":file,"nativeSHA256":row.get("sourceSHA256"),"workingSHA256":mirror["sourceSHA256"]})
                if entry["sha256"] not in accepted:
                    mismatches.append({"path":row["path"],"kind":"manifestSourceHash","nativeSHA256":row.get("sourceSHA256"),"manifestSHA256":entry["sha256"]})
        missing=[{"path":row["studioPath"],"file":row["file"],"className":row["className"],"workingMirrorPresent":row["file"] in before_files} for key,row in entries.items() if key not in native]
        native_files={"/".join(row["segments"][:-1])+"/"+row["segments"][-1]+"."+row["className"]+(".txt" if row["className"]=="RemoteEvent" else ".lua") for row in native_rows}
        extra_working=sorted(set(before_files)-native_files)
        actual_scripts=sum(row["className"] in ("Script","LocalScript","ModuleScript") for row in manifest["items"])
        actual_remotes=sum(row["className"]=="RemoteEvent" for row in manifest["items"])
        native_scripts=sum(row["className"] in ("Script","LocalScript","ModuleScript") for row in native_rows)
        native_remotes=sum(row["className"]=="RemoteEvent" for row in native_rows)
        report.update(complete=True,nativeSourceEditorConflictCount=begin["sourceEditorConflictCount"],
                      counts={"nativeScripts":native_scripts,"nativeRemotes":native_remotes,"nativeTotal":len(native_rows),
                              "actualManifestScripts":actual_scripts,"actualManifestRemotes":actual_remotes,"actualManifestTotal":len(manifest["items"]),"declaredManifest":manifest["counts"]},
                      declaredManifestCountsMatchActual=all(manifest["counts"][key]==value for key,value in (("scripts",actual_scripts),("remoteEvents",actual_remotes),("total",len(manifest["items"])))),
                      mismatches=mismatches,missingNative=missing,extraNative=extra,extraWorkingFiles=extra_working,
                      manifestPropertyCoverageGaps=coverage,manifestPropertyCoverageGapCount=len(coverage),
                      nativeScriptPropertyReadErrors=[{"path":row["path"],"properties":row["propertyReadErrors"]} for row in native_rows if row["propertyReadErrors"]],
                      sourceAndRecordedPropertyParity=len(mismatches)==0 and len(missing)==0 and len(extra)==0 and len(extra_working)==0,
                      attributesTagsAndNonScriptNativeAssetsCompared=False)
    except BaseException as error:
        primary=error;report["error"]=str(error);raise
    finally:
        if client is not None:
            try:client.close()
            except BaseException as cleanup:
                report["closeError"]=str(cleanup);report["complete"]=False
                if primary is not None:primary.add_note("Diagnostic MCP close: "+str(cleanup))
        report["finishedUtc"]=datetime.now(timezone.utc).isoformat()
        new("result.json",report)
    print(json.dumps({key:report.get(key) for key in ("complete","counts","nativeSourceEditorConflictCount","sourceAndRecordedPropertyParity","declaredManifestCountsMatchActual","mismatches","missingNative","extraNative","extraWorkingFiles","manifestPropertyCoverageGapCount")}),flush=True)


if __name__=="__main__":main()
