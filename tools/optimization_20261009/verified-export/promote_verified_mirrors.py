"""Root-controlled promotion of exactly seven raw, verified Studio source mirrors.

Default invocation performs a local-only preflight and records exact current
local byte hashes. --apply first performs read-only fresh Studio Source/editor/
identity CAS, then copies only the seven pinned raw files. No native backup,
whole-place export, Studio mutation, git staging/commit, or global sync-manifest
write is performed. Unexpected local source is rejected rather than overwritten.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
TASK = HERE.parent
ROOT = TASK.parents[1]
sys.path.insert(0, str(TASK))
from native_probe_runner import StudioMcpClient, find_mcp_batch, literal, select_studio
from export_verified_sources import GUARD


def digest(raw: bytes):
    return hashlib.sha256(raw).hexdigest()


def utc():
    return datetime.now(timezone.utc).isoformat()


def task_input(relative):
    path = (ROOT / relative).resolve()
    assert path.is_relative_to(TASK), "Only reviewed task-owned source inputs"
    return path


def native_rows():
    export = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    assert export["complete"] and export["readOnly"] and not export["studioMutation"]
    assert export["placeId"] == 131311258779917 and export["universeId"] == 10559217407
    assert len(export["scripts"]) == 7
    candidate = []
    for filename in (TASK / "proposed-source-manifest.json", TASK / "loading/install/compatibility/source-install-manifest.json"):
        manifest = json.loads(filename.read_text(encoding="utf-8"))
        assert manifest["placeId"] == export["placeId"] and manifest["universeId"] == export["universeId"]
        candidate.extend(manifest["scripts"])
    assert len(candidate) == 7
    baseline = {tuple(row["segments"]):row for row in candidate}
    assert len(baseline) == 7
    rows = []
    for captured in export["scripts"]:
        before = baseline[tuple(captured["segments"])]
        assert before["class"] == captured["class"] and captured["editorParity"]
        raw_path = task_input(captured["rawFile"])
        assert raw_path.is_relative_to(HERE)
        raw = raw_path.read_bytes()
        assert len(raw) == captured["rawBytes"] and digest(raw) == captured["rawSourceSha256"] == before["afterSha256"]
        raw.decode("utf-8")
        expected = Path(*captured["segments"][:-1]) / (captured["segments"][-1]+"."+captured["class"]+".lua")
        assert expected.as_posix() == captured["expectedRepositoryPath"]
        destination = ROOT / expected
        assert destination.resolve().is_relative_to(ROOT) and destination.resolve() == destination.absolute() and not destination.is_symlink(), "Unexpected mirror target or redirected parent"
        native_before = None
        if before["beforeFile"]:
            native_before = task_input(before["beforeFile"]).read_bytes()
            assert digest(native_before) == before["beforeSha256"]
        rows.append({"captured":captured, "raw":raw, "rawPath":raw_path,
            "destination":destination, "nativeBefore":native_before})
    return rows


def local_snapshot(row):
    destination = row["destination"]
    if not destination.exists():
        assert row["nativeBefore"] is None, "Existing script mirror unexpectedly absent: " + str(destination)
        raw = None
        state = "absent-new-mirror"
    else:
        assert destination.is_file() and not destination.is_symlink(), "Mirror target is not a regular file"
        raw = destination.read_bytes()
        canonical = raw.replace(b"\r\n", b"\n")
        if raw == row["raw"]:
            state = "already-exact-native-after"
        elif canonical == row["raw"]:
            state = "native-after-with-CRLF-only"
        elif row["nativeBefore"] is not None and raw == row["nativeBefore"]:
            state = "exact-native-before"
        elif row["nativeBefore"] is not None and canonical == row["nativeBefore"]:
            state = "native-before-with-CRLF-only"
        else:
            raise AssertionError("Unexpected local Source; preserve and reconcile: " + destination.relative_to(ROOT).as_posix()
                + " (raw SHA256=" + digest(raw) + ")")
    return raw, {"path":destination.relative_to(ROOT).as_posix(), "localBeforeExists":raw is not None,
        "localBeforeRawSha256":digest(raw) if raw is not None else None,
        "localBeforeRawBytes":len(raw) if raw is not None else 0,
        "localBeforeCanonicalSha256":digest(raw.replace(b"\r\n",b"\n")) if raw is not None else None,
        "acceptedLocalState":state, "nativeAfterSha256":digest(row["raw"]),
        "nativeAfterBytes":len(row["raw"]), "capturedRawFile":row["captured"]["rawFile"],
        "localBeforePreservation":"Exact raw hash/byte-count record only; owner instructed no backups"}


def native_cas_code(rows):
    expected = []
    for row in rows:
        captured = row["captured"]
        identity = {key:captured[key] for key in ("instanceId","path","name","parentId","parentPath","parentClass")}
        expected.append({"segments":captured["segments"], "class":captured["class"],
            "source":row["raw"].decode("utf-8"), "sha256":digest(row["raw"]), "identity":identity})
    code = GUARD + '''local expected=H:JSONDecode(%s)
local pins={}
for _,row in ipairs(expected) do
 local node,source=check(row)
 table.insert(pins,{path=node:GetFullName(),class=node.ClassName,instanceId=node:GetDebugId(16),
  parentId=node.Parent:GetDebugId(16),rawBytes=#source,nativeCurrentSourceSha256=row.sha256,
  exactCapturedSourceMatches=true,editorParity=true,exactExportIdentityMatches=true})
end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),datamodel="Edit",readOnly=true,complete=true,pins=pins})
''' % literal(expected)
    return code


def fresh_native_cas(rows):
    code = native_cas_code(rows)
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 25)
        sid = studio.get("studio_id") or studio.get("id")
        result = json.loads(client.call("execute_luau", {"studio_id":sid,"datamodel_type":"Edit","code":code}))
        assert result["complete"] and result["readOnly"] and len(result["pins"]) == 7
        result["studioId"] = sid
        return result
    finally:
        client.close()


def assert_local_cas(destination: Path, before):
    assert destination.resolve() == destination.absolute() and not destination.is_symlink(), "Local mirror/parent replaced by symlink"
    if before is None:
        assert not destination.exists(), "Concurrent local mirror appeared: " + str(destination)
    else:
        assert destination.is_file() and destination.read_bytes() == before, "Concurrent local Source changed: " + str(destination)


def copy_exact(row, before):
    destination = row["destination"]
    assert_local_cas(destination, before)
    assert digest(row["rawPath"].read_bytes()) == digest(row["raw"]), "Verified raw export changed"
    if before == row["raw"]:
        return False
    destination.parent.mkdir(parents=True, exist_ok=True)
    assert destination.parent.resolve().is_relative_to(ROOT)
    # This temporary file contains only the verified AFTER candidate. No old
    # mirror/native contents are backed up or copied anywhere.
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(mode="wb", prefix=".optimization-20261009-", suffix=".tmp",
                dir=destination.parent, delete=False) as handle:
            temporary = Path(handle.name)
            handle.write(row["raw"])
            handle.flush()
            os.fsync(handle.fileno())
        assert temporary.parent.resolve() == destination.parent.resolve()
        assert digest(temporary.read_bytes()) == digest(row["raw"])
        assert_local_cas(destination, before)
        os.replace(temporary, destination)
        temporary = None
        assert destination.read_bytes() == row["raw"], "Promoted raw mirror mismatch"
        return True
    finally:
        if temporary is not None:
            assert temporary.parent.resolve() == destination.parent.resolve() and temporary.name.startswith(".optimization-20261009-")
            temporary.unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apply", action="store_true", help="Root only: fresh read-only native CAS followed by scoped seven-mirror copy")
    parser.add_argument("--receipt", type=Path, help="Optional fresh receipt filename within verified-export; existing receipts are never overwritten")
    args = parser.parse_args()
    receipt_path = (HERE / args.receipt).resolve() if args.receipt else HERE / ("mirror-promotion-receipt.json" if args.apply else "promotion-preflight.json")
    assert receipt_path.is_relative_to(HERE) and receipt_path.suffix == ".json", "Receipt must remain a task-owned JSON file"
    assert not receipt_path.exists(), "Preserve existing promotion receipt; root must review before rerun"
    receipt = {"startedUtc":utc(), "apply":args.apply, "nativeBackup":False, "localBeforeBackup":False,
        "studioMutation":False, "globalSyncManifestWritten":False, "gitStaged":False, "gitCommitted":False,
        "ownerPolicy":"Owner instructed no backups; exact local before hashes recorded without content copies",
        "complete":False, "mirrors":[]}
    def save(): receipt_path.write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    save()
    try:
        rows = native_rows()
        snapshots = []
        for row in rows:
            before, record = local_snapshot(row)
            snapshots.append(before)
            receipt["mirrors"].append(record)
        save() # Exact before hashes recorded before any native call or copy.
        if args.apply:
            receipt["freshNativeCas"] = fresh_native_cas(rows)
            save()
            # Reject every unexpected local change before writing the first file.
            for row, before in zip(rows,snapshots): assert_local_cas(row["destination"],before)
            for row,before,record in zip(rows,snapshots,receipt["mirrors"]):
                record["copied"] = copy_exact(row,before)
                record["promotedRawSha256"] = digest(row["destination"].read_bytes())
                assert record["promotedRawSha256"] == record["nativeAfterSha256"]
                save()
            for row in rows: assert row["destination"].read_bytes() == row["raw"]
        receipt["complete"] = True
        print(f"{'Promoted' if args.apply else 'Local-only preflight passed for'} seven exact verified mirrors; no global manifest, Studio, git stage/commit, or backup writes.")
    except Exception as error:
        receipt["error"] = f"{type(error).__name__}: {error}"
        raise
    finally:
        receipt["finishedUtc"] = utc()
        save()


if __name__ == "__main__": main()
