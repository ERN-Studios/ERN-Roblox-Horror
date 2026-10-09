"""Independent repo <-> Studio parity check.

The sync tools decide what to WRITE. This decides, separately, whether what is
in Studio right now is what the repo says it is -- without going through any of
them. Studio is asked for a fingerprint of every LuaSourceContainer it holds
(the companion probe in tools/studio_parity_probe.luau prints it); this script
computes the same fingerprint over the mirrored files and reconciles the two.

The fingerprint is byte length plus two independent 32-bit rolling hashes over
the canonical bytes. It is deliberately NOT the manifest's sha256: a check that
reuses the recorded hash proves only that the manifest is self-consistent.

Every mirrored script must land in exactly one bucket:

  exact      -- Studio holds the repo file byte for byte
  permitted  -- Studio holds it plus the ONE trailing newline the manifest flags
  drift      -- anything else
  class      -- Studio holds the path as the wrong LuaSourceContainer class
  missing    -- the repo mirrors it, Studio does not hold it
  extra      -- Studio holds a script the repo does not mirror

Usage:
  python tools/verify_studio_parity.py <studio-dump.txt>
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "studio-sync-manifest.json"

FNV_OFFSET = 0x811C9DC5
FNV_PRIME = 0x01000193
MASK = 0xFFFFFFFF


def fingerprint(data: bytes) -> str:
    """Length + FNV-1a-32 + djb2-32, the same three numbers the Luau probe prints."""
    fnv = FNV_OFFSET
    djb = 5381
    for byte in data:
        fnv = ((fnv ^ byte) * FNV_PRIME) & MASK
        djb = ((djb * 33) + byte) & MASK
    return f"{len(data)}:{fnv:08x}:{djb:08x}"


def canonical(text: str) -> bytes:
    """Studio normalises line endings to LF; the working tree may hold CRLF."""
    return text.replace("\r\n", "\n").replace("\r", "\n").encode("utf-8")


def load_studio_dump(path: Path) -> dict[str, tuple[str, str]]:
    """path -> (className, fingerprint), from the probe's `path\tclass\tprint` lines."""
    held: dict[str, tuple[str, str]] = {}
    for line_number, line in enumerate(
        path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise SystemExit(f"malformed probe line: {line!r}")
        if parts[0] in held:
            raise SystemExit(
                f"duplicate Studio path in probe dump at line {line_number}: "
                f"{parts[0]!r}"
            )
        held[parts[0]] = (parts[1], parts[2])
    return held


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print(__doc__)
        return 2
    dump = Path(argv[1])
    if not dump.is_file():
        print(f"no such probe dump: {dump}")
        return 2

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    studio = load_studio_dump(dump)

    exact: list[str] = []
    permitted: list[str] = []
    drift: list[str] = []
    class_mismatch: list[str] = []
    missing: list[str] = []
    mirrored: set[str] = set()

    for item in manifest["items"]:
        if not str(item["file"]).endswith(".lua"):
            continue  # RemoteEvent placeholders carry no source
        path = item["studioPath"]
        mirrored.add(path)
        entry = studio.get(path)
        if entry is None:
            missing.append(path)
            continue
        held_class, held_fingerprint = entry
        expected_class = item["className"]
        if held_class != expected_class:
            class_mismatch.append(
                f"{path}  manifest={expected_class} studio={held_class}"
            )
            continue
        repo_bytes = canonical((ROOT / item["file"]).read_text(encoding="utf-8"))
        if held_fingerprint == fingerprint(repo_bytes):
            exact.append(path)
        elif (
            item.get("studioTrailingNewline") is True
            and held_fingerprint == fingerprint(repo_bytes + b"\n")
        ):
            permitted.append(path)
        else:
            drift.append(
                f"{path}  repo={fingerprint(repo_bytes)} studio={held_fingerprint}"
            )

    extra = sorted(set(studio) - mirrored)

    print(f"exact      {len(exact)}")
    print(f"permitted  {len(permitted)}")
    print(f"drift      {len(drift)}")
    print(f"class      {len(class_mismatch)}")
    print(f"missing    {len(missing)}")
    print(f"extra      {len(extra)}")
    for label, rows in (
        ("drift", drift),
        ("class", class_mismatch),
        ("missing", missing),
        ("extra", extra),
    ):
        for row in rows:
            print(f"  {label}: {row}")

    ok = not drift and not class_mismatch and not missing and not extra
    expected_scripts = manifest["counts"]["scripts"]
    if len(exact) + len(permitted) != expected_scripts:
        print(f"FAIL: {len(exact) + len(permitted)} reconciled, manifest counts {expected_scripts}")
        ok = False
    flagged = sum(
        1
        for i in manifest["items"]
        if str(i.get("file", "")).endswith(".lua")
        and i.get("studioTrailingNewline") is True
    )
    if len(permitted) != flagged:
        print(f"FAIL: {len(permitted)} permitted, {flagged} entries carry the flag")
        ok = False
    print("PARITY OK" if ok else "PARITY FAILED")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
