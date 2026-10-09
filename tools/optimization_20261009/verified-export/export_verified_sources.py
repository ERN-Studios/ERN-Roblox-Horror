"""Read-only fresh native Source export for the seven reviewed installed scripts.

Writes only this task's verified-export directory. Every chunk uses exact
Source/editor/identity/parent/path/class compare-and-swap assertions. Raw bytes
are hex transported in small responses, then reassembled without line-ending
or Unicode normalization. Never writes Studio or runtime repository mirrors.
"""
from __future__ import annotations

from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
TASK = HERE.parent
ROOT = TASK.parents[1]
sys.path.insert(0, str(TASK))
from native_probe_runner import StudioMcpClient, find_mcp_batch, literal, load_inputs, read_source, select_studio, sha

CHUNK_BYTES = 4096
MAX_OUTPUT_BYTES = 12000
GUARD = '''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning(),"Read-only export requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
local function targetAt(segments)
 local node=game
 for _,segment in ipairs(segments) do
  local match=nil
  for _,child in ipairs(node:GetChildren()) do
   if child.Name==segment then assert(match==nil,"Ambiguous export path: "..segment);match=child end
  end
  assert(match~=nil,"Missing export path: "..segment);node=match
 end
 return node
end
local function check(row)
 local node=targetAt(row.segments)
 assert(node.ClassName==row.class,"Export class changed: "..node:GetFullName())
 local source,editor=node.Source,SES:GetEditorSource(node)
 assert(source==row.source and editor==source,"Export Source/editor differs from reviewed candidate: "..node:GetFullName())
 if row.identity then
  local identity=row.identity
  assert(node:GetDebugId(16)==identity.instanceId and node:GetFullName()==identity.path
   and node.Name==identity.name and node.Parent:GetDebugId(16)==identity.parentId
   and node.Parent:GetFullName()==identity.parentPath and node.Parent.ClassName==identity.parentClass,
   "Export exact instance/parent identity changed: "..node:GetFullName())
 end
 return node,source
end
'''


def reviewed_sources():
    sources, _ = load_inputs()
    manifest = json.loads((TASK / "loading/install/compatibility/source-install-manifest.json").read_text(encoding="utf-8"))
    assert manifest["placeId"] == 131311258779917 and manifest["universeId"] == 10559217407
    assert len(manifest["scripts"]) == 2
    for row in manifest["scripts"]:
        path = (ROOT / row["afterFile"]).resolve()
        assert path.is_relative_to(TASK)
        source = read_source(path)
        assert sha(source) == row["afterSha256"]
        sources.append({"segments":row["segments"], "class":row["class"], "source":source, "sha256":sha(source)})
    assert len(sources) == len({tuple(row["segments"]) for row in sources}) == 7
    return sources


def safe_output(relative: Path):
    path = (HERE / relative).resolve()
    assert path.is_relative_to(HERE), "Export must remain in task-owned verified-export"
    path.parent.mkdir(parents=True, exist_ok=True)
    return path


def main():
    sources = reviewed_sources()
    receipt_path = safe_output(Path("manifest.json"))
    assert not receipt_path.exists(), "Preserve existing verified export; root must choose a fresh scope before recapture"
    receipt = {"startedUtc":datetime.now(timezone.utc).isoformat(), "placeId":131311258779917,
        "universeId":10559217407, "datamodel":"Edit", "readOnly":True, "studioMutation":False,
        "nativeBackup":False, "runtimeMirrorsWritten":False, "reviewedSources":7,
        "transport":"raw-byte hexadecimal", "chunkBytes":CHUNK_BYTES, "maxChunkOutputBytes":MAX_OUTPUT_BYTES,
        "complete":False, "scripts":[]}
    def save():
        receipt_path.write_text(json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    client = None
    save()
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        receipt["studioId"] = sid
        def call(code):
            output = client.call("execute_luau", {"studio_id":sid, "datamodel_type":"Edit", "code":GUARD+code})
            assert len(output.encode("utf-8")) <= MAX_OUTPUT_BYTES, "Export response exceeds bounded output"
            return json.loads(output)
        # Begin across all seven, before any byte export. No instances or Source
        # are retained in Studio globals: each call independently resolves/CASes.
        begin = call('''local expected=H:JSONDecode(%s)
local pins={}
for _,row in ipairs(expected) do
 local node,source=check(row)
 table.insert(pins,{segments=row.segments,path=node:GetFullName(),class=node.ClassName,name=node.Name,
  instanceId=node:GetDebugId(16),parentId=node.Parent:GetDebugId(16),parentPath=node.Parent:GetFullName(),
  parentClass=node.Parent.ClassName,rawBytes=#source,editorParity=true,reviewedCandidateMatches=true})
end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),pins=pins})
''' % literal(sources))
        receipt["beginVerifiedUtc"] = begin["verifiedUtc"]
        for row, pin in zip(sources, begin["pins"]):
            assert row["segments"] == pin["segments"] and row["class"] == pin["class"]
            row["identity"] = pin
        save()
        for row in sources:
            pin = row["identity"]
            blocks = []
            chunk_receipts = []
            for offset in range(0, pin["rawBytes"], CHUNK_BYTES):
                result = call('''local row=H:JSONDecode(%s)
local node,source=check(row)
local offset,count=%d,%d
assert(#source==row.identity.rawBytes,"Raw byte length changed during export")
local piece=source:sub(offset+1,offset+count)
local encoded={}
for i=1,#piece do encoded[i]=string.format("%%02x",string.byte(piece,i)) end
return H:JSONEncode({offset=offset,rawBytes=#piece,hex=table.concat(encoded),instanceId=node:GetDebugId(16),editorParity=true})
''' % (literal(row), offset, CHUNK_BYTES))
                assert result["offset"] == offset and result["instanceId"] == pin["instanceId"] and result["editorParity"] is True
                block = bytes.fromhex(result["hex"])
                assert len(block) == result["rawBytes"] == min(CHUNK_BYTES, pin["rawBytes"]-offset)
                blocks.append(block)
                chunk_receipts.append({"offset":offset,"rawBytes":len(block),"exactSourceEditorIdentityCas":True})
            raw = b"".join(blocks)
            assert len(raw) == pin["rawBytes"]
            assert raw.decode("utf-8") == row["source"], "Reassembled native UTF-8 differs from candidate"
            digest = hashlib.sha256(raw).hexdigest()
            assert digest == row["sha256"]
            repository = Path(*row["segments"][:-1]) / (row["segments"][-1]+"."+row["class"]+".lua")
            destination = safe_output(repository)
            assert not destination.exists(), "Preserve any existing task export file"
            destination.write_bytes(raw)
            receipt["scripts"].append({**pin,"rawFile":destination.relative_to(ROOT).as_posix(),
                "expectedRepositoryPath":repository.as_posix(), "rawSourceSha256":digest,
                "reviewedCandidateSha256":row["sha256"], "rawUtf8Verified":True,
                "chunks":chunk_receipts,"runtimeRepositoryMirrorWritten":False})
            save()
            print(pin["path"], len(raw), digest, flush=True)
        # End across every source, including scripts exported earlier. Replacing
        # an instance with byte-identical Source still fails its recorded identity.
        end = call('''local expected=H:JSONDecode(%s)
local pins={}
for _,row in ipairs(expected) do
 local node,source=check(row)
 assert(#source==row.identity.rawBytes,"Final byte length changed")
 table.insert(pins,{path=node:GetFullName(),class=node.ClassName,instanceId=node:GetDebugId(16),parentId=node.Parent:GetDebugId(16),editorParity=true,reviewedCandidateMatches=true})
end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),pins=pins})
''' % literal(sources))
        receipt["endVerifiedUtc"] = end["verifiedUtc"]
        receipt["finalPins"] = end["pins"]
        assert len(receipt["scripts"]) == len(end["pins"]) == 7
        # Disk recheck prevents a concurrent local writer changing an export.
        for row in receipt["scripts"]:
            assert hashlib.sha256((ROOT / row["rawFile"]).read_bytes()).hexdigest() == row["rawSourceSha256"]
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        receipt["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        save()
        if client is not None: client.close()


if __name__ == "__main__":
    main()
