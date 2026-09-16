"""Create NEW mirrored scripts in Studio through the supported editor tool, then register them.

The push tools cannot create scripts (CLAUDE.md, 2026-09-03), so a new mirror file is
installed here first: the Studio path and class are derived from the mirror path
(`StarterPlayer/StarterPlayerScripts/Name.LocalScript.lua` ->
`StarterPlayer.StarterPlayerScripts.Name`, class LocalScript), the script is created with
`multi_edit` when absent, its raw `.Source` is read back and compared byte for byte, and only
then is a `synced` manifest item written. An existing script whose source differs is reported
and left alone unless `--overwrite` is given (which then goes through
ScriptEditorService:UpdateSourceAsync, never a raw .Source write).

    python tools/install_new_scripts.py --dry-run <mirror path> [...]
    python tools/install_new_scripts.py <mirror path> [...]

Generalised from tools/install_trello_new_scripts.py (2026-09-14).
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402
from studio_source_contract import normalize, refresh_trailing_newline_metadata, sha256_of  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
PLACE = "BACKROOMS: STAY QUIET [CO-OP HORROR]"
CLASSES = ("Script", "LocalScript", "ModuleScript")


def plan(mirror: str) -> tuple[str, str, str]:
    """mirror path -> (file, studio dotted path, class)."""
    file = mirror.replace("\\", "/").strip("/")
    name = file.rsplit("/", 1)[-1]
    if not name.endswith(".lua"):
        raise SystemExit(f"not a mirrored Lua file: {mirror}")
    stem, kind = name[:-4].rsplit(".", 1)
    if kind not in CLASSES:
        raise SystemExit(f"unknown class suffix in {mirror}")
    parts = file.split("/")[:-1] + [stem]
    return file, ".".join(parts), kind


def lua_lookup(path: str) -> str:
    names = json.dumps(path.split("."))
    return (
        "local c=game;for _,n in " + names.replace("[", "{").replace("]", "}")
        + " do c=c and c:FindFirstChild(n) end;"
        'return game:GetService("HttpService"):JSONEncode(c and {class=c.ClassName,source=c.Source} or {missing=true})'
    )


def lua_update(path: str, source: str) -> str:
    names = json.dumps(path.split("."))
    return (
        "local c=game;for _,n in " + names.replace("[", "{").replace("]", "}")
        + " do c=c and c:FindFirstChild(n) end;assert(c,'missing');"
        'game:GetService("ScriptEditorService"):UpdateSourceAsync(c,function() return '
        + json.dumps(source) + " end);return 'ok'"
    )


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="+", help="mirror paths relative to the repo root")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--overwrite", action="store_true", help="UpdateSourceAsync onto an existing script that differs")
    args = ap.parse_args()
    plans = [plan(f) for f in args.files]
    for file, path, kind in plans:
        if not (ROOT / file).exists():
            raise SystemExit(f"missing mirror file: {file}")
        print(f"PLAN {kind:12} game.{path}  <-  {file}")
    if args.dry_run:
        return 0
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    client = StudioMcpClient(find_mcp_batch())
    failures = 0
    try:
        client.initialize()
        time.sleep(3)
        studio = select_studio(client, PLACE, 20)
        sid = studio["id"]
        for file, path, kind in plans:
            src = normalize((ROOT / file).read_text(encoding="utf-8"))
            live = json.loads(client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_lookup(path)}))
            if live.get("missing"):
                client.call("multi_edit", {"studio_id": sid, "datamodel_type": "Edit", "file_path": "game." + path,
                                           "className": kind, "edits": [{"old_string": "", "new_string": src}]})
                live = json.loads(client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_lookup(path)}))
            if live.get("missing") or live.get("class") != kind:
                print(f"FAILED  {path}: class {live.get('class')!r}")
                failures += 1
                continue
            actual = normalize(live["source"])
            if actual not in (src, src + "\n"):
                if not args.overwrite:
                    print(f"DIFFERS {path}: Studio holds other source ({len(actual)} B vs {len(src)} B); rerun with --overwrite to replace it")
                    failures += 1
                    continue
                client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_update(path, src)})
                live = json.loads(client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_lookup(path)}))
                actual = normalize(live["source"])
                if actual not in (src, src + "\n"):
                    print(f"FAILED  {path}: source mismatch after UpdateSourceAsync")
                    failures += 1
                    continue
            item = {"studioPath": path, "className": kind, "file": file, "bytes": len(src.encode("utf-8")),
                    "sha256": sha256_of(src), "status": "synced"}
            if actual == src + "\n":
                item["studioTrailingNewline"] = True
            manifest["items"] = [i for i in manifest["items"] if i["file"] != file] + [item]
            manifest["studio"] = studio
            manifest["counts"]["scripts"] = sum(i["className"] in CLASSES for i in manifest["items"])
            manifest["counts"]["total"] = len(manifest["items"])
            refresh_trailing_newline_metadata(manifest)
            manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            print(f"VERIFIED {path}")
    finally:
        client.close()
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
