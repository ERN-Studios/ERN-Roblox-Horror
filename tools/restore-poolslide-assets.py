#!/usr/bin/env python3
"""Verify and restore the Pool Slide source archive; never contacts Studio.

Uses only Python's standard library. Refuses an existing output directory and
rejects archive traversal, duplicate members, links and unexpected contents.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import tarfile
import tempfile


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def safe_relative(name: str) -> Path:
    value = PurePosixPath(name)
    if not name or not value.parts or value.is_absolute() or ".." in value.parts or "\\" in name or "\x00" in name:
        raise ValueError(f"Unsafe archive path: {name!r}")
    if str(value) != name or ":" in value.parts[0]:
        raise ValueError(f"Noncanonical archive path: {name!r}")
    return Path(*value.parts)


def restore(pack: Path, output: Path | None) -> dict:
    manifest = json.loads((pack / "manifest.json").read_text(encoding="utf-8"))
    if manifest.get("schema") != "poolslide-source-pack-v1":
        raise ValueError("Unexpected source-pack manifest schema")
    if output is not None and output.exists():
        raise FileExistsError(f"Output already exists; choose a new directory: {output}")
    expected = {}
    for record in manifest["files"]:
        safe_relative(record["path"])
        if record["path"] in expected:
            raise ValueError("Duplicate manifest file")
        expected[record["path"]] = record
    with tempfile.TemporaryDirectory(prefix="rblx-poolslide-verify-") as scratch:
        archive = Path(scratch) / "source.tar.gz"
        with archive.open("wb") as target:
            for part in manifest["parts"]:
                relative = safe_relative(part["path"])
                raw = (pack / relative).read_bytes()
                if len(raw) != part["bytes"] or digest(raw) != part["sha256"]:
                    raise ValueError(f"Part checksum mismatch: {relative}")
                target.write(raw)
        raw = archive.read_bytes()
        if len(raw) != manifest["archiveBytes"] or digest(raw) != manifest["archiveSha256"]:
            raise ValueError("Reassembled archive checksum mismatch")
        # Fully verify before creating ANY destination files.
        seen = set()
        with tarfile.open(archive, "r:gz") as source:
            for member in source:
                safe_relative(member.name)
                record = expected.get(member.name)
                if not member.isfile() or member.name in seen or record is None:
                    raise ValueError(f"Unexpected, linked or duplicate archive member: {member.name}")
                if member.size != record["bytes"]:
                    raise ValueError(f"Archive size mismatch: {member.name}")
                stream = source.extractfile(member)
                if stream is None or digest(stream.read()) != record["sha256"]:
                    raise ValueError(f"File checksum mismatch: {member.name}")
                seen.add(member.name)
        if seen != set(expected):
            raise ValueError("Archive is missing expected files")
        if output is not None:
            output.mkdir(parents=True, exist_ok=False)
            with tarfile.open(archive, "r:gz") as source:
                for member in source:
                    destination = output / safe_relative(member.name)
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    with destination.open("xb") as target:
                        target.write(source.extractfile(member).read())
            for name, record in expected.items():
                if digest((output / safe_relative(name)).read_bytes()) != record["sha256"]:
                    raise ValueError(f"Post-extraction checksum mismatch: {name}")
    return {"verifiedFiles": len(expected), "sourceFiles": manifest["verifiedSourceFileCount"],
            "parts": len(manifest["parts"]), "archiveSha256": manifest["archiveSha256"],
            "output": str(output) if output is not None else None}


def main() -> int:
    root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pack-dir", type=Path, default=root / "assets/level2/poolslide/source-pack")
    parser.add_argument("--output", type=Path, default=root / "restored-assets/poolslide-2026-08-31")
    parser.add_argument("--verify-only", action="store_true")
    args = parser.parse_args()
    result = restore(args.pack_dir.resolve(), None if args.verify_only else args.output.absolute())
    print(json.dumps(result, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
