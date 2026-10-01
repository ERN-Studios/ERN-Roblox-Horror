#!/usr/bin/env python3
"""Export only the requested, hash-verified scripts from the final Studio native capture."""
import hashlib
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
TASK = ROOT / "artifacts/level6-studio-revision-20261001"
def sha(data):
    return hashlib.sha256(data).hexdigest()
def main():
    entries = json.loads((TASK / "native-after/scripts.json").read_text())
    live = {row["path"]: row for row in entries}
    allowed = json.loads((TASK / "scoped-script-manifest.json").read_text())["scripts"]
    output = TASK / "verified-studio-mirror"
    records = []
    for item in allowed:
        row = live[item["path"]]
        assert row["editorMatch"] is True and not row.get("editorSource"), item["path"]
        data = row["source"].encode()
        assert sha(data) == item["afterSHA256"], item["path"]
        parts = item["path"].split(".")
        target = output.joinpath(*parts[:-1], parts[-1] + "." + row["class"] + ".luau")
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        records.append({"studioPath": item["path"], "class": row["class"],
                        "sourceSHA256": sha(data), "bytes": len(data),
                        "sourceEditorParity": True, "repositoryFile": str(target.relative_to(ROOT))})
    result = {"schema": "verified-studio-scoped-mirror/1", "placeId": 131311258779917,
              "universeId": 10559217407, "capturedScriptsSHA256": sha((TASK / "native-after/scripts.json").read_bytes()),
              "studioSourceIsAuthoritative": True, "scripts": records}
    (output / "manifest.json").write_text(json.dumps(result, indent=2) + "\n")
    print(json.dumps({"verifiedScripts": len(records), "manifest": str((output / "manifest.json").relative_to(ROOT))}))
if __name__ == "__main__":
    main()
