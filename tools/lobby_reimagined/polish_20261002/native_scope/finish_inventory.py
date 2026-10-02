"""List only task-owned local files; never stage, commit, sync, or contact Studio."""
from __future__ import annotations

import argparse
import json
from pathlib import Path

PREFIXES = (
    "tools/lobby_reimagined/polish_20261002",
    "artifacts/lobby-polish-20261002",
    "assets/models/lobby-material-polish-20261002",
)
SUFFIXES = {".luau", ".lua", ".py", ".json", ".md", ".txt", ".diff", ".png", ".jpg", ".jpeg", ".webp"}
DENIED_PARTS = {"__pycache__", "node_modules", ".git", ".cache", ".venv"}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--repository", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--pathspec", type=Path, required=True)
    args = parser.parse_args()
    repo = args.repository.resolve()
    accepted, excluded = [], []
    for prefix in PREFIXES:
        directory = repo / prefix
        for path in sorted(directory.rglob("*")):
            if not path.is_file():
                continue
            if path.resolve() == args.output.resolve():
                continue
            rel = path.relative_to(repo)
            permitted = (path.suffix.lower() in SUFFIXES and not any(part in DENIED_PARTS or part.startswith(".") for part in rel.parts)
                         and path.name.lower() not in {"credentials.json", "cookies.json", "secrets.json", "scripts.json"}
                         and not path.name.startswith(("native-part-", "source-part-", "script-part-"))
                         and not path.is_symlink())
            row = {"path": rel.as_posix(), "bytes": path.stat().st_size}
            (accepted if permitted else excluded).append(row)
    output_rel = args.output.resolve().relative_to(repo).as_posix()
    assert any(output_rel.startswith(prefix + "/") for prefix in PREFIXES), "Inventory must be a task artifact"
    accepted.append({"path": output_rel, "bytes": None, "generatedByThisRun": True})
    accepted.sort(key=lambda row: row["path"])
    record = {"schema": "lobby-polish-task-commit-inventory-v1", "repository": str(repo),
              "prefixes": list(PREFIXES), "files": accepted, "excludedFiles": excluded,
              "fileCount": len(accepted), "totalBytes": sum(row["bytes"] or 0 for row in accepted),
              "isContentReview": False, "gitOrStudioWrites": False,
              "notes": "Refresh after final exports/publication records. Inspect actual content/staged diff; no historical task directories, raw native forests, transfer parts, caches or credential files are included."}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(record, indent=2) + "\n")
    args.pathspec.parent.mkdir(parents=True, exist_ok=True)
    args.pathspec.write_bytes(b"\0".join(row["path"].encode() for row in accepted) + b"\0")
    print(json.dumps({"files": len(accepted), "bytes": record["totalBytes"], "excluded": len(excluded),
                      "manifest": str(args.output), "nulPathspec": str(args.pathspec)}))


if __name__ == "__main__":
    main()
