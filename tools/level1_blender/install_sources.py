"""Install the scoped facelift scripts against their fresh Studio baselines.

Usage: python tools/level1_blender/install_sources.py --apply
No repository source is used as the baseline for an existing Studio script.
"""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio
from studio_source_contract import refresh_trailing_newline_metadata

BASE = ROOT / "artifacts/level1-facelift-20261002/live-before"
DRAFT = ROOT / "drafts/level1-facelift-20261002"
EXISTING = ["ServerScriptService/GameManager.Script.lua",
    "ServerScriptService/Level 1 Systems/MazeGenerator.Script.lua",
    "ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua"]
NEW = ["ServerScriptService/Level 1 Systems/BlenderRoomRenderer.ModuleScript.lua",
    "ServerScriptService/Level1BlenderPreviewAccess.Script.lua",
    "StarterPlayer/StarterPlayerScripts/Level1BlenderPreviewButton.LocalScript.lua"]


def plan(file):
    path = Path(file)
    name, kind, _ = path.name.rsplit(".", 2)
    return ".".join((*path.parts[:-1], name)), kind


def lookup(file):
    path, kind = plan(file)
    segments = "{" + ",".join(json.dumps(n) for n in path.split(".")) + "}"
    return f'''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
local inst=game;for _,name in {segments} do inst=inst and inst:FindFirstChild(name) end
if not inst then return '{{"missing":true}}' end
assert(inst.ClassName=={json.dumps(kind)},"Wrong class")
local editor=game:GetService("ScriptEditorService"):GetEditorSource(inst)
local function hash(text) local h=5381;for i=1,#text do h=(h*33+string.byte(text,i))%4294967296 end;return h end
return game:GetService("HttpService"):JSONEncode({{bytes=#inst.Source,hash=hash(inst.Source),editorMatches=editor==inst.Source}})'''


def matches(live, source):
    data = source.encode("utf-8")
    value = 5381
    for byte in data:
        value = (value * 33 + byte) % 4294967296
    return live.get("bytes") == len(data) and live.get("hash") == value and live.get("editorMatches") is True


def main():
    global BASE, DRAFT, EXISTING, NEW
    ap = argparse.ArgumentParser()
    ap.add_argument("--apply", action="store_true")
    ap.add_argument("--baseline", type=Path, default=BASE)
    ap.add_argument("--drafts", type=Path, default=DRAFT)
    ap.add_argument("--file", action="append", help="Existing scoped source path; disables the original create plan")
    ap.add_argument("--skip-manifest", action="store_true", help="Keep the shared manifest for the coordinated final merge")
    args = ap.parse_args()
    BASE, DRAFT = args.baseline.resolve(), args.drafts.resolve()
    if args.file:
        assert len(args.file) == len(set(args.file)), "Duplicate file"
        # The shared manager only receives the reviewed synchronous animation
        # release against its fresh, Cinema-aware Studio baseline.
        assert all(file.startswith("ServerScriptService/Level 1 Systems/") or file == "ServerScriptService/GameManager.Script.lua"
                   for file in args.file), "Revision is scoped to Level 1 and its animation release"
        EXISTING, NEW = args.file, []
    changes = []
    for file in EXISTING:
        draft = DRAFT / file
        if not draft.exists():
            draft = DRAFT / Path(file).name
        if not draft.exists():
            continue
        expected = (BASE / file).read_text(encoding="utf-8")
        desired = draft.read_text(encoding="utf-8")
        if expected != desired:
            changes.append((file, expected, desired))
    changes += [(file, None, (ROOT / file).read_text(encoding="utf-8")) for file in NEW]
    if not args.apply:
        for file, expected, desired in changes:
            print("CREATE" if expected is None else "UPDATE", file, len(desired.encode()))
        return
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        sid = studio["id"]
        if "Current Studio Mode: Edit" not in client.call("get_studio_state", {"studio_id":sid}):
            raise RuntimeError("Edit mode required")
        def execute(code):
            return client.call("execute_luau", {"studio_id":sid,"datamodel_type":"Edit","code":code})
        # Verify every baseline before changing any source.
        for index, (file, expected, desired) in enumerate(changes):
            live = json.loads(execute(lookup(file)))
            if expected is None:
                if not live.get("missing") and not (matches(live, desired) or matches(live, desired + "\n")):
                    # Only revise a task-owned script that still matches our last
                    # verified receipt. Its fresh Studio source is the CAS baseline.
                    receipt = json.loads((ROOT / "studio-sync-manifest.json").read_text(encoding="utf-8"))
                    item = next((i for i in receipt["items"] if i["file"] == file), None)
                    path, _ = plan(file)
                    segments = "{" + ",".join(json.dumps(n) for n in path.split(".")) + "}"
                    current = json.loads(execute(f'local i=game;for _,n in {segments} do i=assert(i:FindFirstChild(n)) end;return game:GetService("HttpService"):JSONEncode(i.Source)'))
                    if not item or hashlib.sha256(current.encode()).hexdigest() != item["sha256"] or not matches(live, current):
                        raise RuntimeError(f"Concurrent task script changed: {file}")
                    changes[index] = (file, current, desired)
            elif not (matches(live, expected) or matches(live, desired) or matches(live, desired + "\n")):
                raise RuntimeError(f"Fresh Studio/editor baseline changed: {file}; reread and reconcile")
        for file, expected, desired in changes:
            path, kind = plan(file)
            live = json.loads(execute(lookup(file)))
            if expected is None:
                if live.get("missing"):
                    client.call("multi_edit", {"studio_id":sid,"datamodel_type":"Edit",
                        "file_path":"game."+path,"className":kind,
                        "edits":[{"old_string":"","new_string":desired}]})
            elif not (matches(live, desired) or matches(live, desired + "\n")):
                segments = "{" + ",".join(json.dumps(n) for n in path.split(".")) + "}"
                execute(f'''local inst=game;for _,name in {segments} do inst=assert(inst:FindFirstChild(name),name) end
local SES=game:GetService("ScriptEditorService")
local expected,desired={json.dumps(expected, ensure_ascii=False)},{json.dumps(desired, ensure_ascii=False)}
assert(inst.ClassName=={json.dumps(kind)} and inst.Source==expected and SES:GetEditorSource(inst)==expected,"Concurrent Studio/editor edit")
SES:UpdateSourceAsync(inst,function(current)
    assert(current==expected and inst.Source==expected,"Concurrent baseline changed inside write")
    return desired
end)
return 'verified' ''')
            live = json.loads(execute(lookup(file)))
            # UpdateSourceAsync's editor commit can precede replicated Source.
            # Verify the same desired value; never retry the write or relax CAS.
            for _ in range(3):
                if matches(live, desired) or matches(live, desired + "\n"):
                    break
                time.sleep(0.1)
                live = json.loads(execute(lookup(file)))
            if not (matches(live, desired) or matches(live, desired + "\n")):
                raise RuntimeError(f"Post-write source/editor mismatch: {file}")
            actual = desired if matches(live, desired) else desired + "\n"
            target = ROOT / file
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(actual, encoding="utf-8", newline="\n")
            if args.skip_manifest:
                print("VERIFIED", path, hashlib.sha256(actual.encode()).hexdigest(), "(shared manifest deferred)", flush=True)
                continue
            manifest_path = ROOT / "studio-sync-manifest.json"
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            item = {"studioPath":path,"className":kind,"file":file,
                "bytes":len(actual.encode()),"sha256":hashlib.sha256(actual.encode()).hexdigest(),"status":"synced"}
            manifest["items"] = [i for i in manifest["items"] if i["file"] != file] + [item]
            manifest["studio"] = studio
            manifest["counts"]["scripts"] = sum(i["className"] in ("Script","ModuleScript","LocalScript") for i in manifest["items"])
            manifest["counts"]["total"] = len(manifest["items"])
            refresh_trailing_newline_metadata(manifest)
            manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False)+"\n", encoding="utf-8")
            print("VERIFIED", path, item["sha256"], flush=True)
    finally:
        client.close()


if __name__ == "__main__":
    main()
