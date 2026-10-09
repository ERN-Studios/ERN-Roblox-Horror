"""Record repo-side script edits in the manifest as pending Studio pushes.

Scans every manifest item whose mirrored file on disk no longer matches its
recorded sha256 and rewrites the entry to the new content, remembering the
previous hash as "studioSha256Before" (what Studio is still expected to hold).
push_repo_to_studio.py consumes exactly these entries.

Also reports mirrored script files that no manifest item claims -- a NEW script
cannot be pushed by these tools -- and exits 1 when it finds any.

Usage:
    python tools/record_pending_push.py            # record all mismatches
    python tools/record_pending_push.py --dry-run  # report only
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path


# A default Windows console is cp1252 and raises UnicodeEncodeError on anything
# it cannot represent -- including from argparse's --help, which renders the
# module docstring. Degrading those characters is always better than aborting a
# release tool, so replace rather than raise. Everything this file prints is
# ASCII anyway; this is the belt to that braces.
for _stream in (sys.stdout, sys.stderr):
    try:
        _stream.reconfigure(errors="replace")
    except (AttributeError, ValueError, OSError):
        pass
sys.path.insert(0, str(Path(__file__).resolve().parent))

from studio_source_contract import normalize, sha256_of  # noqa: E402
from pull_source_from_studio import SERVICES  # noqa: E402

PROJECT_ROOT = Path(__file__).resolve().parents[1]
MANIFEST_PATH = PROJECT_ROOT / "studio-sync-manifest.json"

SCRIPT_SUFFIXES = (".Script.lua", ".LocalScript.lua", ".ModuleScript.lua")
# Backups, the knowledge graph's scratch output and the retired-code archive are
# all real .lua on disk but none of them mirror a live Studio instance.
SKIP_DIR_NAMES = (".studio-push-backups", "graphify-out")
SKIP_PREFIXES = ("ServerStorage/Archive/",)


def find_unknown(known: set[str]) -> list[str]:
    """Mirrored script files on disk that no manifest item claims.

    Roots are pull_source_from_studio's SERVICES (the mirrored services) UNION
    whatever the manifest items name: SERVICES alone would miss a folder the
    manifest still uses, and the manifest alone misses a service that holds no
    item yet -- today Workspace and RobloxReplicatedStorage, which is exactly
    where a first new script would hide.
    """
    unknown = []
    for root in sorted(set(SERVICES) | {file.split("/", 1)[0] for file in known}):
        for path in sorted((PROJECT_ROOT / root).rglob("*.lua")):
            rel = path.relative_to(PROJECT_ROOT).as_posix()
            if not rel.endswith(SCRIPT_SUFFIXES) or rel in known:
                continue
            # Match on the repo-relative path: path.parts carries the ancestors
            # of the checkout too, so a repo cloned under a directory named
            # graphify-out would skip every file and report nothing.
            if rel.startswith(SKIP_PREFIXES) or any(
                part in SKIP_DIR_NAMES for part in rel.split("/")
            ):
                continue
            unknown.append(rel)
    return unknown


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
        text = normalize(path.read_text(encoding="utf-8"))
        data = text.encode("utf-8")
        digest = sha256_of(text)
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

    unknown = find_unknown({item["file"] for item in manifest.get("items", [])})
    for rel in unknown:
        print(
            f"UNKNOWN {rel} -- not in the manifest; create it in Studio first "
            "(execute_luau + UpdateSourceAsync), then add the manifest item "
            "(see CLAUDE.md 'New scripts cannot be pushed by the tools')"
        )
    return 1 if unknown else 0


if __name__ == "__main__":
    raise SystemExit(main())
