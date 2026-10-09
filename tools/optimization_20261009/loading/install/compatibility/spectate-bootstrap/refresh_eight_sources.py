"""Root-only fresh eight-source export, guarded mirror promotion and global refresh.

Default writes only a local preflight receipt. --apply connects read-only to
Studio, verifies all eight before/after the two raw captures and local writes,
promotes only GM/SpectateController and scopes the working global source fields.
Historical seven-source exports and all old receipts remain untouched. No backup,
Studio mutation, Git staging/commit or publication is performed.
"""
from __future__ import annotations
import argparse
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
TASK = HERE.parents[3]
ROOT = TASK.parents[1]
SEVEN = TASK / "verified-export"
EIGHT = HERE / "verified-export-eight"
GLOBAL = ROOT / "studio-sync-manifest.json"
sys.path.insert(0, str(TASK))
sys.path.insert(0, str(SEVEN))
from native_probe_runner import StudioMcpClient, find_mcp_batch, literal, select_studio
from export_verified_sources import GUARD
from promote_verified_mirrors import copy_exact, local_snapshot, assert_local_cas


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode("utf-8")


def inputs():
    seven_raw = (SEVEN / "manifest.json").read_bytes()
    seven = json.loads(seven_raw)
    proposal_raw = (HERE / "source-install-manifest.json").read_bytes()
    proposal = json.loads(proposal_raw)
    assert seven["complete"] and len(seven["scripts"]) == 7
    assert seven["placeId"] == proposal["placeId"] == 131311258779917
    assert seven["universeId"] == proposal["universeId"] == 10559217407
    updates = {tuple(row["segments"]): row for row in proposal["scripts"]}
    assert len(proposal["scripts"]) == len(updates) == 2
    rows = []
    previous_gm = None
    for captured in seven["scripts"]:
        raw = (ROOT / captured["rawFile"]).read_bytes()
        assert sha(raw) == captured["rawSourceSha256"] and len(raw) == captured["rawBytes"]
        update = updates.get(tuple(captured["segments"]))
        if update:
            assert captured["path"] == "ServerScriptService.GameManager" and sha(raw) == update["beforeSha256"]
            previous_gm = copy.deepcopy(captured)
            raw = (ROOT / update["afterFile"]).read_bytes()
            assert sha(raw) == update["afterSha256"]
        identity = {key: captured[key] for key in ("path", "name", "instanceId", "parentId", "parentPath", "parentClass")}
        rows.append({"segments": captured["segments"], "class": captured["class"], "identity": identity,
            "source": raw.decode("utf-8"), "sha256": sha(raw), "captured": copy.deepcopy(captured), "update": update})
    spectate = updates[("StarterPlayer", "StarterPlayerScripts", "SpectateController")]
    raw = (ROOT / spectate["afterFile"]).read_bytes()
    assert sha(raw) == spectate["afterSha256"]
    rows.append({"segments": spectate["segments"], "class": spectate["class"], "identity": spectate["identity"],
        "source": raw.decode("utf-8"), "sha256": sha(raw), "captured": None, "update": spectate})
    assert previous_gm and len(rows) == len({tuple(row["segments"]) for row in rows}) == 8
    for row in rows:
        relative = Path(*row["segments"][:-1]) / (row["segments"][-1] + "." + row["class"] + ".lua")
        row["repositoryPath"] = relative.as_posix()
        if row["update"]:
            before = (ROOT / row["update"]["beforeFile"]).read_bytes()
            assert sha(before) == row["update"]["beforeSha256"]
            export = EIGHT / relative
            row["copyRow"] = {"destination": ROOT / relative, "nativeBefore": before,
                "raw": row["source"].encode("utf-8"), "rawPath": export,
                "captured": {"rawFile": export.relative_to(ROOT).as_posix()}}
        else:
            assert (ROOT / relative).read_bytes() == row["source"].encode("utf-8"), "Unchanged mirror not exact native source"
    return rows, seven_raw, proposal_raw, previous_gm


def source_fields(current, pins):
    assert current["placeId"] == 131311258779917 and current["universeId"] == 10559217407, "Wrong global manifest place/universe"
    proposed = copy.deepcopy(current)
    targets = {pin["path"]: pin for pin in pins}
    assert len(pins) == len(targets) == 8
    old = {row["studioPath"]: row for row in current["items"] if row["studioPath"] in targets}
    assert len(old) == sum(row["studioPath"] in targets for row in current["items"]) == 8
    changes = []
    for path, pin in targets.items():
        item = next(row for row in proposed["items"] if row["studioPath"] == path)
        relative = Path(*pin["segments"][:-1]) / (pin["segments"][-1] + "." + pin["class"] + ".lua")
        assert item["segments"] == pin["segments"] and item["className"] == pin["class"] and item["file"] == relative.as_posix()
        item.update(bytes=pin["rawBytes"], sha256=pin["sourceSha256"], status="synced", sourceEditorMatches=True)
        item.pop("studioTrailingNewline", None)
        changes.append({"path": path, "beforeSha256": old[path]["sha256"], "afterSha256": pin["sourceSha256"]})
    for key, value in current.items():
        if key not in {"items", "counts"}:
            assert proposed[key] == value
    assert [row for row in current["items"] if row["studioPath"] not in targets] == [row for row in proposed["items"] if row["studioPath"] not in targets]
    for path, item in old.items():
        after = next(row for row in proposed["items"] if row["studioPath"] == path)
        assert {key: value for key, value in item.items() if key not in {"bytes", "sha256", "status", "sourceEditorMatches", "studioTrailingNewline"}} == {key: value for key, value in after.items() if key not in {"bytes", "sha256", "status", "sourceEditorMatches", "studioTrailingNewline"}}
    proposed["counts"]["scripts"] = sum(row["className"] in {"Script", "LocalScript", "ModuleScript"} for row in proposed["items"])
    proposed["counts"]["total"] = len(proposed["items"])
    proposed["counts"]["studioTrailingNewline"] = sum(row.get("studioTrailingNewline") is True for row in proposed["items"])
    return proposed, changes


def validate_native(result, rows):
    assert result["complete"] is True and result["readOnly"] is True
    pins = result["pins"]
    assert len(pins) == len(rows) == 8 and len({pin["path"] for pin in pins}) == 8, "Incomplete/duplicate native source pins"
    for row, pin in zip(rows, pins):
        assert pin["segments"] == row["segments"] and pin["class"] == row["class"]
        assert pin["sourceSha256"] == row["sha256"] and pin["rawBytes"] == len(row["source"].encode("utf-8"))
        assert pin["editorParity"] is True and pin["reviewedCandidateMatches"] is True
        for key in ("path", "name", "instanceId", "parentId", "parentPath", "parentClass"):
            assert pin[key] == row["identity"][key], "Native exact identity mismatch: " + key
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Root only after guarded source install: read-only Studio export, exact mirror copies and scoped global source fields")
    parser.add_argument("--receipt", type=Path, help="Fresh task-owned JSON filename; preserve existing receipt history")
    args = parser.parse_args()
    output = (HERE / args.receipt).resolve() if args.receipt else HERE / ("eight-source-refresh-receipt.json" if args.apply else "eight-source-preflight.json")
    assert output.is_relative_to(HERE) and output.suffix == ".json"
    assert not output.exists(), "Preserve eight-source receipt history; reconcile rather than overwriting"
    rows, seven_raw, proposal_raw, old_gm = inputs()
    snapshots = []
    for row in rows:
        if row["update"]:
            before, record = local_snapshot(row["copyRow"])
            snapshots.append((row, before, record))
    global_before = GLOBAL.read_bytes()
    expected_pins = [{"path": row["identity"]["path"], "segments": row["segments"], "class": row["class"],
        "rawBytes": len(row["source"].encode("utf-8")), "sourceSha256": row["sha256"]} for row in rows]
    _, planned_changes = source_fields(json.loads(global_before), expected_pins) # Full shape/path guards before any mirror/export write.
    receipt = {"startedUtc": datetime.now(timezone.utc).isoformat(), "apply": args.apply, "complete": False,
        "studioMutation": False, "nativeBackup": False, "gitStaged": False, "gitCommitted": False,
        "historicalSevenManifestSha256": sha(seven_raw), "historicalSevenGameManagerRow": old_gm,
        "reviewedTwoSourceManifestSha256": sha(proposal_raw), "globalBeforeSha256": sha(global_before),
        "globalShapePreflightPassed": True, "plannedGlobalSourceChanges": planned_changes,
        "localCopies": [record for _, _, record in snapshots], "historicalReceiptsOverwritten": False}
    def save():
        output.write_bytes(encoded(receipt))
    save()
    if not args.apply:
        receipt["complete"] = True
        save()
        print("Prepared exact local before hashes for GM/Spectate and six unchanged native mirrors; no Studio connection, mirror/global write, stage or backup.")
        return
    assert not (EIGHT / "manifest.json").exists(), "Preserve current eight-source export"
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        # Parallel test copies share the place name. Pin the authoritative Edit
        # connection captured with these exact identities, never the active copy.
        sid = json.loads(seven_raw)["studioId"]
        assert sid == json.loads((HERE / "baseline-capture.json").read_bytes())["studioId"]
        receipt["studioId"] = sid
        expected = [{key: row[key] for key in ("segments", "class", "identity", "source", "sha256")} for row in rows]
        def call(code):
            raw = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": GUARD + code})
            assert len(raw.encode("utf-8")) <= 12000
            return json.loads(raw)
        def native_all():
            result = call('''local expected=H:JSONDecode(%s);local pins={}
for _,row in ipairs(expected) do local n,s=check(row)
 local properties={}
 for _,key in ipairs({"Archivable","LinkedSource","Disabled","RunContext"}) do
  local ok,value=pcall(function() return n[key] end)
  if ok then properties[key]=if typeof(value)=="EnumItem" then tostring(value) else value end
 end
 local attributes={}
 for key,value in pairs(n:GetAttributes()) do
  if typeof(value)=="string" or typeof(value)=="boolean" or typeof(value)=="number" then attributes[key]=value end
 end
 table.insert(pins,{path=n:GetFullName(),segments=row.segments,class=n.ClassName,name=n.Name,
 instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),parentPath=n.Parent:GetFullName(),parentClass=n.Parent.ClassName,
 rawBytes=#s,sourceSha256=row.sha256,editorParity=true,reviewedCandidateMatches=true,properties=properties,attributes=attributes}) end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),readOnly=true,complete=true,pins=pins})
''' % literal(expected))
            return validate_native(result, rows)
        receipt["nativeBegin"] = native_all()
        save()
        captured = []
        for row, pin in zip(rows, receipt["nativeBegin"]["pins"]):
            assert pin["segments"] == row["segments"]
            if row["update"]:
                raw_file = row["copyRow"]["rawPath"]
                assert not raw_file.exists(), "Preserve prior fresh raw export"
                blocks, chunks = [], []
                for offset in range(0, pin["rawBytes"], 4096):
                    block = call('''local row=H:JSONDecode(%s);local n,s=check(row);local piece=s:sub(%d+1,%d+4096)
local out={};for i=1,#piece do out[i]=string.format("%%02x",string.byte(piece,i)) end
return H:JSONEncode({offset=%d,rawBytes=#piece,hex=table.concat(out),id=n:GetDebugId(16),editorParity=true})
''' % (literal({key: row[key] for key in ("segments", "class", "identity", "source", "sha256")}), offset, offset, offset))
                    raw = bytes.fromhex(block["hex"])
                    assert block["offset"] == offset and len(raw) == block["rawBytes"] == min(4096, pin["rawBytes"] - offset)
                    assert block["id"] == pin["instanceId"] and block["editorParity"]
                    blocks.append(raw)
                    chunks.append({"offset": offset, "rawBytes": len(raw), "exactSourceEditorIdentityCas": True})
                raw = b"".join(blocks)
                assert raw == row["source"].encode("utf-8") and sha(raw) == row["sha256"]
                raw_file.parent.mkdir(parents=True, exist_ok=True)
                raw_file.write_bytes(raw)
                item = {**pin, "rawFile": raw_file.relative_to(ROOT).as_posix(), "chunks": chunks,
                    "reviewedCandidateManifest": (HERE / "source-install-manifest.json").relative_to(ROOT).as_posix()}
            else:
                item = {**copy.deepcopy(row["captured"]), **pin, "reverifiedCurrentSourceUtc": receipt["nativeBegin"]["verifiedUtc"]}
            item.update(expectedRepositoryPath=row["repositoryPath"], rawSourceSha256=row["sha256"],
                reviewedCandidateSha256=row["sha256"], rawUtf8Verified=True, editorParity=True, reviewedCandidateMatches=True)
            captured.append(item)
        receipt["nativeAfterRawCapture"] = native_all()
        save()
        EIGHT.mkdir(parents=True, exist_ok=True)
        export = {"placeId": 131311258779917, "universeId": 10559217407, "datamodel": "Edit", "readOnly": True,
            "complete": True, "scripts": captured, "reviewedSources": 8, "studioMutation": False, "nativeBackup": False,
            "beginVerifiedUtc": receipt["nativeBegin"]["verifiedUtc"], "endVerifiedUtc": receipt["nativeAfterRawCapture"]["verifiedUtc"],
            "historicalSevenManifest": (SEVEN / "manifest.json").relative_to(ROOT).as_posix(), "historicalSevenManifestSha256": sha(seven_raw)}
        (EIGHT / "manifest.json").write_bytes(encoded(export))
        receipt["eightExportManifestSha256"] = sha((EIGHT / "manifest.json").read_bytes())
        assert (SEVEN / "manifest.json").read_bytes() == seven_raw and (HERE / "source-install-manifest.json").read_bytes() == proposal_raw
        for row, before, _ in snapshots:
            assert_local_cas(row["copyRow"]["destination"], before)
        assert GLOBAL.read_bytes() == global_before, "Concurrent global manifest change; preserve and reconcile"
        for row, before, record in snapshots:
            record["copied"] = copy_exact(row["copyRow"], before)
            record["copiedRawSha256"] = sha(row["copyRow"]["destination"].read_bytes())
            save()
        for row in rows:
            assert (ROOT / row["repositoryPath"]).read_bytes() == row["source"].encode("utf-8")
        proposed, changes = source_fields(json.loads(global_before), receipt["nativeAfterRawCapture"]["pins"])
        global_after = encoded(proposed)
        (HERE / "studio-sync-manifest.eight.proposed.json").write_bytes(global_after)
        assert GLOBAL.read_bytes() == global_before, "Concurrent global manifest changed immediately before scoped write"
        GLOBAL.write_bytes(global_after)
        assert GLOBAL.read_bytes() == global_after
        receipt.update(globalAfterSha256=sha(global_after), scopedGlobalSourceRows=changes, workingOtherGlobalRowsAndFieldsPreserved=True)
        receipt["nativeEnd"] = native_all()
        assert (SEVEN / "manifest.json").read_bytes() == seven_raw
        assert all(sha((ROOT / item["rawFile"]).read_bytes()) == item["rawSourceSha256"] for item in captured)
        receipt["complete"] = True
        print("Fresh eight-source export/mirrors/scoped global verified; historical seven records intact; no Studio mutation, backups or Git actions.")
    except Exception as error:
        receipt["error"] = type(error).__name__ + ": " + str(error)
        raise
    finally:
        receipt["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        save()
        client.close()


if __name__ == "__main__":
    main()
