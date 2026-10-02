"""Export the final eight catalog-pinned Sources from a verified local snapshot.

No Studio calls, Source changes, staging, or overwrite of different mirror bytes.
The complete scripts.json remains authoritative for all captured Sources.
"""
from pathlib import Path
import datetime
import hashlib
import json
import os

TASK = Path(__file__).resolve().parent
ROOT = TASK.parents[1]
SNAPSHOT = Path("/private/tmp/lobby-r4-native-after-20261001")
CATALOG = ROOT / "tools/lobby_reimagined/r4_candidates/install-catalog-r4-final.json"


def digest(raw):
    return hashlib.sha256(raw).hexdigest()


def save_exact(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        assert path.read_bytes() == raw, f"Existing Source mirror differs: {path.name}"
        return
    partial = path.with_name(path.name + ".partial")
    with partial.open("xb") as outgoing:
        outgoing.write(raw)
        outgoing.flush()
        os.fsync(outgoing.fileno())
    os.replace(partial, path)
    assert path.read_bytes() == raw


def main():
    catalog_raw = CATALOG.read_bytes()
    catalog = json.loads(catalog_raw)
    gate = json.loads((SNAPSHOT / "checkpoint-install-gate.json").read_bytes())
    metadata = json.loads((SNAPSHOT / "metadata.json").read_bytes())
    rows = json.loads((SNAPSHOT / "scripts.json").read_bytes())
    assert gate["verified"] is True
    assert gate["captureId"] == metadata["captureId"]
    assert gate["nativeSHA256"] == metadata["nativeSHA256"]
    assert gate["placeId"] == 131311258779917 and gate["universeId"] == 10559217407
    assert gate["groupId"] == 1039373905 and not metadata["editorConflicts"]
    assert catalog["sourceCount"] == len(catalog["sources"]) == 8
    by_path = {row["path"]: row for row in rows}
    assert len(by_path) == len(rows), "Ambiguous captured Source path"
    prepared = []
    for spec in catalog["sources"]:
        row = by_path[spec["path"]]
        raw = row["source"].encode("utf-8")
        sha = digest(raw)
        assert row["class"] == spec["class"]
        assert row["editorMatch"] is True and row["editorSourceSha256"] == sha
        assert sha == spec["afterSHA256"] and len(raw) == spec["candidateBytes"]
        filename = row["path"].replace("/", "_").replace("\\", "_") + "." + row["class"] + ".luau"
        prepared.append((SNAPSHOT / "fresh-source" / filename, raw, {
            "path": row["path"], "class": row["class"], "file": "fresh-source/" + filename,
            "bytes": len(raw), "sourceSHA256": sha, "editorSourceSHA256": sha, "editorMatch": True,
            "baselineSourceSHA256": spec["expectedSourceSHA256"], "owned": spec["owned"],
        }))
    # Validate every catalog pin before producing any plain Source mirror.
    for path, raw, _ in prepared:
        save_exact(path, raw)
    receipt = {
        "schema": "lobby-r4-final-eight-source-mirror-v1", "verified": True,
        "createdAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "captureId": gate["captureId"], "nativeSHA256": gate["nativeSHA256"],
        "catalogSHA256": digest(catalog_raw), "sourceCount": len(prepared),
        "sources": [record for _, _, record in prepared],
        "completeSourceExport": "scripts.json", "studioActions": False,
        "scope": "Exact captured Source/class/editor parity and final task-catalog pins; no gameplay or publication claim",
    }
    target = SNAPSHOT / "final-scoped-source-mirror.json"
    if target.exists():
        previous = json.loads(target.read_bytes())
        receipt["createdAtUtc"] = previous["createdAtUtc"]
    save_exact(target, (json.dumps(receipt, indent=2) + "\n").encode())
    print(json.dumps({"verified": True, "sourceCount": len(prepared), "captureId": gate["captureId"], "receipt": str(target)}), flush=True)


if __name__ == "__main__":
    main()
