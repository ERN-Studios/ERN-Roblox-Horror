"""Record repo-side script edits in the manifest as pending Studio pushes.

Scans every manifest item whose mirrored file on disk no longer matches its
recorded sha256 and rewrites the entry to the new content, remembering the
previous hash as "studioSha256Before" (what Studio is still expected to hold).
push_repo_to_studio.py consumes exactly these entries.

Usage:
    python tools/record_pending_push.py            # record all mismatches
    python tools/record_pending_push.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "studio-sync-manifest.json"


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--dry-run", action="store_true", help="report only")
    args = parser.parse_args()

    manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
    changed = 0
    for item in manifest.get("items", []):
        path = PROJECT_ROOT / item["file"]
        if not path.exists():
            print(f"  MISSING FILE {item['file']}")
            continue
        data = path.read_text(encoding="utf-8").replace("\r\n", "\n").encode("utf-8")
        digest = hashlib.sha256(data).hexdigest()
        if digest == item.get("sha256"):
            continue
        changed += 1
        print(f"  PENDING {item['file']} ({item.get('bytes')} -> {len(data)} bytes)")
        if args.dry_run:
            continue
        # Keep the ORIGINAL Studio hash when re-recording a file that is already
        # queued (or stuck in a conflict): the baseline must stay the source
        # Studio actually holds, not an intermediate repo edit.
        if item.get("status") not in ("pending-studio-push", "studio-push-conflict"):
            item["studioSha256Before"] = item.get("sha256")
        item["bytes"] = len(data)
        item["sha256"] = digest
        item["status"] = "pending-studio-push"

    if changed and not args.dry_run:
        MANIFEST_PATH.write_text(
            json.dumps(manifest, indent=2) + "\n", encoding="utf-8", newline="\n"
        )
        print(f"Manifest updated: {changed} file(s) marked pending-studio-push.")
    elif not changed:
        print("No repo-side script edits detected; manifest untouched.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
