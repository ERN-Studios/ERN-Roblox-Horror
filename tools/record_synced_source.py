"""Re-record mirrored files in the manifest after a VERIFIED direct push.

`record_pending_push.py` queues a repo edit for `push_repo_to_studio.py`. That
route is unavailable whenever the MCP proxy is out of date, and the fallback
transport (tools/stage_push_payload.py + ScriptEditorService:UpdateSourceAsync)
lands the bytes itself and verifies them. This tool is the bookkeeping half of
that fallback: it writes the manifest entry for a file whose new content is
ALREADY in Studio.

It refuses to guess. Run tools/verify_studio_parity.py first and pass its dump;
an entry is only re-recorded when the dump says Studio really holds the repo
file (exactly, or plus the one permitted trailing newline). The recorded hash is
always the REPO file's canonical bytes, never Studio's copy -- recording
Studio's bytes is the mistake that once let drift be blessed as "synced".

Usage:
  python tools/record_synced_source.py <studio-dump.txt> <repo-relative file> [...]
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from studio_source_contract import (  # noqa: E402
    EXACT,
    TRAILING_NEWLINE,
    apply_trailing_newline_verdict,
    canonical_bytes,
    refresh_trailing_newline_metadata,
    sha256_of,
)
from verify_studio_parity import canonical, fingerprint, load_studio_dump  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "studio-sync-manifest.json"


def main(argv: list[str]) -> int:
    if len(argv) < 3:
        print(__doc__)
        return 2
    dump = Path(argv[1])
    if not dump.is_file():
        print(f"no such probe dump: {dump}")
        return 2
    studio = load_studio_dump(dump)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    by_file = {item["file"]: item for item in manifest["items"]}

    updated, refused = [], []
    for rel in argv[2:]:
        rel = rel.replace("\\", "/")
        item = by_file.get(rel)
        if item is None:
            refused.append(f"{rel}: not a mirrored file")
            continue
        text = (ROOT / rel).read_text(encoding="utf-8")
        repo_bytes = canonical(text)
        held = studio.get(item["studioPath"])
        if held is None:
            refused.append(f"{rel}: Studio does not hold {item['studioPath']}")
            continue
        held_class, held_fingerprint = held
        if held_class != item["className"]:
            refused.append(
                f"{rel}: Studio class is {held_class}, manifest expects "
                f"{item['className']}"
            )
            continue
        exact = held_fingerprint == fingerprint(repo_bytes)
        permitted = item.get("studioTrailingNewline") is True and held_fingerprint == fingerprint(
            repo_bytes + b"\n"
        )
        if not (exact or permitted):
            refused.append(
                f"{rel}: Studio does not hold this content "
                f"(probe says {held_fingerprint})"
            )
            continue
        landing = EXACT if exact else TRAILING_NEWLINE
        apply_trailing_newline_verdict(item, landing)
        item["bytes"] = len(canonical_bytes(text))
        item["sha256"] = sha256_of(text)
        item["status"] = "synced"
        item.pop("studioSha256Before", None)
        updated.append(f"{rel}  {'exact' if exact else 'permitted newline'}  {item['sha256'][:12]}")

    for line in updated:
        print("  recorded  " + line)
    for line in refused:
        print("  REFUSED   " + line)
    if refused:
        print("nothing written: every named file must already be in Studio")
        return 1
    refresh_trailing_newline_metadata(manifest)
    MANIFEST.write_text(
        json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8"
    )
    print(f"studio-sync-manifest.json updated for {len(updated)} entr(ies)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
