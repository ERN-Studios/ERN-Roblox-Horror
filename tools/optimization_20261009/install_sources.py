"""Apply an explicitly reviewed source manifest against fresh exact Studio pins.

Not invoked while the owner keeps Play running. This never imports repository
scripts wholesale or publishes. Each row needs segments, class, beforeFile
(null for a new instance), afterFile. Paths are relative to the repository.
"""
from __future__ import annotations
import argparse
import hashlib
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio


def literal(value):
    return json.dumps(json.dumps(value, ensure_ascii=True))


def finder(segments):
    return '''local node=game
for _,seg in ipairs(H:JSONDecode(%s)) do
 local matches={}
 for _,child in ipairs(node:GetChildren()) do if child.Name==seg then table.insert(matches,child) end end
 assert(#matches==1,"Missing or ambiguous target: "..seg)
 node=matches[1]
end
''' % literal(segments)


def task_file(relative):
    path = (ROOT / relative).resolve()
    assert path.is_relative_to(ROOT / "tools/optimization_20261009"), "Source input must be task-owned"
    return path


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("manifest")
    parser.add_argument("--backup", required=True, help="Full native .rbxl/.rbxlx backup path")
    parser.add_argument("--apply", action="store_true", help="Required explicit invocation after owner releases Edit")
    args = parser.parse_args()
    assert args.apply, "No Studio writes without --apply; review the manifest first"
    backup = Path(args.backup).resolve()
    assert backup.is_file() and backup.suffix.lower() in {".rbxl", ".rbxlx"}, "Native place backup required"
    with backup.open("rb") as handle:
        prefix = handle.read(128)
        assert b"<roblox" in prefix, "Not a native Roblox place header"
        handle.seek(0)
        backup_hash = hashlib.file_digest(handle, "sha256").hexdigest()
    manifest = json.loads(task_file(args.manifest).read_text(encoding="utf-8"))
    client = StudioMcpClient(find_mcp_batch())
    receipts = []
    output = ROOT / "tools/optimization_20261009/source-install-receipt.json"
    try:
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        def call(code):
            return client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
        guard = '''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
assert(not game:GetService("RunService"):IsRunning(),"Owner playtest must remain untouched")
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
'''
        for row in manifest["scripts"]:
            before = task_file(row["beforeFile"]).read_bytes().decode("utf-8") if row["beforeFile"] else ""
            after = task_file(row["afterFile"]).read_bytes().decode("utf-8")
            assert row["class"] in {"Script", "LocalScript", "ModuleScript"}
            # Validate input hashes recorded when the proposal was reviewed.
            assert hashlib.sha256(after.encode()).hexdigest() == row["afterSha256"]
            if row["beforeFile"]:
                assert hashlib.sha256(before.encode()).hexdigest() == row["beforeSha256"]
                target = finder(row["segments"])
            else:
                target = finder(row["segments"][:-1]) + '''
local parent=node
assert(parent:FindFirstChild(%s)==nil,"New target already exists; reread Studio")
node=Instance.new(%s)
node.Name=%s
assert(node.Source=="" and SES:GetEditorSource(node)=="","New instance editor baseline is not empty")
node.Parent=parent
''' % (json.dumps(row["segments"][-1]), json.dumps(row["class"]), json.dumps(row["segments"][-1]))
            originals = '''local originals={}
for i,inst in ipairs(game:GetDescendants()) do
 if inst:IsA("LuaSourceContainer") then
  local source=inst.Source
  local editor=SES:GetEditorSource(inst)
  table.insert(originals,{instance=inst,source=source,editor=editor})
 end
 if i%%2000==0 then task.wait() end
end
assert(not game:GetService("RunService"):IsRunning(),"Play started during baseline read")
'''.replace("%%", "%")
            identity = '''local function targetNow()
%s
return node
end
local pinnedNode,pinnedParent,pinnedName=node,node.Parent,node.Name
local function assertIdentity()
 assert(node==pinnedNode and node.Parent==pinnedParent and node.Name==pinnedName and node.ClassName==%s,"Target identity changed")
 assert(targetNow()==node,"Target moved or was replaced at reviewed path")
end
assertIdentity()
''' % (finder(row["segments"]), json.dumps(row["class"]))
            code = guard + originals + target + identity + '''
assert(node.ClassName==%s,"Target class changed")
local before=H:JSONDecode(%s)
local after=H:JSONDecode(%s)
assert(node.Source==before and SES:GetEditorSource(node)==before,"Fresh Source/editor baseline changed")
local ok,problem=xpcall(function()
 SES:UpdateSourceAsync(node,function(current)
  assert(not game:GetService("RunService"):IsRunning(),"Play started before source write")
  assertIdentity()
  assert(current==before and node.Source==before,"Baseline changed inside write")
  return after
 end)
 assertIdentity()
 assert(node.Source==after and SES:GetEditorSource(node)==after,"Installed Source/editor mismatch")
end,debug.traceback)
local conflicts={}
for _,original in ipairs(originals) do
 if original.instance~=node and (original.instance.Source~=original.source or SES:GetEditorSource(original.instance)~=original.editor) then
  table.insert(conflicts,original.instance:GetFullName())
 end
end
assert(#conflicts==0,"Unrelated original source/editor changed; reconcile without overwriting: "..table.concat(conflicts,", "))
assert(ok,tostring(problem))
return H:JSONEncode({path=node:GetFullName(),class=node.ClassName,bytes=#node.Source,editorMatches=true,otherOriginalsChecked=#originals,verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ")})
''' % (json.dumps(row["class"]), literal(before), literal(after))
            output.write_text(json.dumps({"backupPath": str(backup), "backupSha256": backup_hash,
                "scripts": receipts, "pendingTarget": row["segments"], "complete": False}, indent=2) + "\n", encoding="utf-8")
            receipt = json.loads(call(code))
            receipt.update(beforeSha256=hashlib.sha256(before.encode()).hexdigest(), afterSha256=row["afterSha256"])
            receipts.append(receipt)
            output.write_text(json.dumps({"backupPath": str(backup), "backupSha256": backup_hash,
                "scripts": receipts, "complete": False}, indent=2) + "\n", encoding="utf-8")
            print(receipt["path"], "exact Source/editor", flush=True)
        # Recheck every installed source after all scoped writes.
        for row in manifest["scripts"]:
            after = task_file(row["afterFile"]).read_bytes().decode("utf-8")
            assert call(guard + finder(row["segments"]) + '''
assert(node.ClassName==%s,"Final target class changed")
local expected=H:JSONDecode(%s)
assert(node.Source==expected and SES:GetEditorSource(node)==expected,"Final Source/editor conflict")
return "exact"
''' % (json.dumps(row["class"]), literal(after))) == "exact"
        output.write_text(json.dumps({"backupPath": str(backup), "backupSha256": backup_hash,
            "scripts": receipts, "complete": True, "mirrorsExported": False, "published": False}, indent=2) + "\n", encoding="utf-8")
    finally:
        client.close()


if __name__ == "__main__":
    main()
