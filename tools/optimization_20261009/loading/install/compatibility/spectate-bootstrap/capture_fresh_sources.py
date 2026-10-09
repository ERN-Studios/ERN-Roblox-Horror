"""Read-only exact fresh Edit baselines for the bounded spectate bootstrap fix."""
from __future__ import annotations
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
TASK = HERE.parents[3]
ROOT = TASK.parents[1]
sys.path.insert(0, str(TASK))
from native_probe_runner import StudioMcpClient, find_mcp_batch, literal, select_studio

ROWS = [
    {"segments": ["ServerScriptService", "GameManager"], "class": "Script", "file": "GameManager.before.luau"},
    {"segments": ["StarterPlayer", "StarterPlayerScripts", "SpectateController"], "class": "LocalScript", "file": "SpectateController.before.luau"},
]
GUARD = '''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local E=game:GetService("EncodingService")
assert(not game:GetService("RunService"):IsRunning(),"Fresh baseline requires Edit")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407)
local function digest(source)
 local raw=E:ComputeStringHash(source,Enum.HashAlgorithm.Sha256);local out={}
 for i=1,#raw do out[i]=string.format("%02x",string.byte(raw,i)) end
 return table.concat(out)
end
local function check(row)
 local node=game
 for _,seg in ipairs(row.segments) do
  local match=nil
  for _,child in ipairs(node:GetChildren()) do if child.Name==seg then assert(match==nil,"Ambiguous target");match=child end end
  node=assert(match,"Missing target")
 end
 assert(node.ClassName==row.class,"Target class changed")
 local source=node.Source;assert(SES:GetEditorSource(node)==source,"Source/editor conflict")
 if row.identity then local pin=row.identity
  assert(node:GetDebugId(16)==pin.instanceId and node.Parent:GetDebugId(16)==pin.parentId
   and node:GetFullName()==pin.path and node.Name==pin.name and node.Parent:GetFullName()==pin.parentPath
   and node.Parent.ClassName==pin.parentClass and #source==pin.rawBytes and digest(source)==pin.sourceSha256,
   "Fresh baseline Source/editor/identity CAS changed")
 end
 return node,source
end
'''


def main():
    output = HERE / "baseline-capture.json"
    assert not output.exists() and all(not (HERE / row["file"]).exists() for row in ROWS)
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        def call(code):
            raw = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": GUARD + code})
            assert len(raw.encode()) <= 12000
            return json.loads(raw)
        begin = call('''local rows=H:JSONDecode(%s);local pins={}
for _,row in ipairs(rows) do local n,s=check(row)
 table.insert(pins,{segments=row.segments,class=n.ClassName,path=n:GetFullName(),name=n.Name,
  instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),parentPath=n.Parent:GetFullName(),parentClass=n.Parent.ClassName,
  rawBytes=#s,sourceSha256=digest(s),editorParity=true})
end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),pins=pins})
''' % literal(ROWS))
        receipt = {"studioId": sid, "placeId": 131311258779917, "universeId": 10559217407,
            "datamodel": "Edit", "readOnly": True, "studioMutation": False, "nativeBackup": False,
            "begin": begin, "complete": False, "sources": []}
        for row, pin in zip(ROWS, begin["pins"]):
            row["identity"] = pin
            blocks = []
            for offset in range(0, pin["rawBytes"], 4096):
                block = call('''local row=H:JSONDecode(%s);local n,s=check(row);local piece=s:sub(%d+1,%d+4096)
local out={};for i=1,#piece do out[i]=string.format("%%02x",string.byte(piece,i)) end
return H:JSONEncode({offset=%d,rawBytes=#piece,hex=table.concat(out),instanceId=n:GetDebugId(16)})
''' % (literal(row), offset, offset, offset))
                raw = bytes.fromhex(block["hex"])
                assert block["offset"] == offset and block["instanceId"] == pin["instanceId"] and len(raw) == block["rawBytes"]
                blocks.append(raw)
            source = b"".join(blocks)
            assert len(source) == pin["rawBytes"] and hashlib.sha256(source).hexdigest() == pin["sourceSha256"]
            source.decode("utf-8")
            (HERE / row["file"]).write_bytes(source)
            receipt["sources"].append({**pin, "beforeFile": (HERE / row["file"]).relative_to(ROOT).as_posix()})
        receipt["end"] = call('''local rows=H:JSONDecode(%s);local pins={}
for _,row in ipairs(rows) do local n,s=check(row);table.insert(pins,{path=n:GetFullName(),instanceId=n:GetDebugId(16),sourceSha256=digest(s),editorParity=true}) end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),pins=pins})
''' % literal(ROWS))
        receipt["complete"] = True
        output.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8", newline="\n")
        print(json.dumps({"capturedFreshSources": len(ROWS), "beginUtc": begin["verifiedUtc"], "endUtc": receipt["end"]["verifiedUtc"], "sources": receipt["sources"], "studioMutation": False}))
    finally:
        client.close()


if __name__ == "__main__":
    main()
