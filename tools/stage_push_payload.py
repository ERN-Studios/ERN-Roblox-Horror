"""Stage mirrored scripts for Studio as an .rbxmx in Studio's own content folder.

The MCP proxy this repo's sync tools speak to (`%LOCALAPPDATA%\Roblox\mcp.bat`)
answers "Client proxy is out of date, restart to update", so
`push_repo_to_studio.py` cannot reach the live place. This is the fallback
transport, and it keeps the one property that matters: the bytes are never
retyped or re-escaped through a tool call. The sources are written into an
.rbxmx under `rbxasset://`, Studio loads it with `game:GetObjects`, and the
companion Luau applies each one through `ScriptEditorService:UpdateSourceAsync`
(a raw `.Source` write leaves LocalScripts running stale bytecode) and verifies
the landed text byte for byte before reporting.

Nothing is left behind: `--clean` removes the staged file, and the Luau side
destroys the loaded objects.

Usage:
  python tools/stage_push_payload.py <repo-relative file> [more files ...]
  python tools/stage_push_payload.py --clean
"""

from __future__ import annotations

import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "studio-sync-manifest.json"
STAGE_DIR_NAME = "MongoTVPush"
PAYLOAD_NAME = "payload.rbxmx"


def studio_content_dir() -> Path:
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        raise SystemExit("LOCALAPPDATA is not set; this only runs on the owner's PC")
    versions = Path(local) / "Roblox" / "Versions"
    candidates = [d for d in versions.iterdir() if (d / "RobloxStudioBeta.exe").is_file()]
    if not candidates:
        raise SystemExit(f"no Studio install with RobloxStudioBeta.exe under {versions}")
    # The installed Studio, not an older leftover version folder.
    newest = max(candidates, key=lambda d: (d / "RobloxStudioBeta.exe").stat().st_mtime)
    content = newest / "content"
    if not content.is_dir():
        raise SystemExit(f"no content directory under {newest}")
    return content


def escape(text: str) -> str:
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
    )


def main(argv: list[str]) -> int:
    stage = studio_content_dir() / STAGE_DIR_NAME
    payload = stage / PAYLOAD_NAME

    if len(argv) == 2 and argv[1] == "--clean":
        removed = []
        for path in (payload, stage / "manifest.json"):
            if path.exists():
                path.unlink()
                removed.append(str(path))
        if stage.is_dir() and not any(stage.iterdir()):
            stage.rmdir()
            removed.append(str(stage))
        print("removed: " + (", ".join(removed) if removed else "nothing staged"))
        return 0

    files = argv[1:]
    if not files:
        print(__doc__)
        return 2

    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    by_file = {item["file"]: item for item in manifest["items"]}

    stage.mkdir(parents=True, exist_ok=True)
    parts = ['<roblox version="4">']
    staged = []
    for index, rel in enumerate(files, start=1):
        rel = rel.replace("\\", "/")
        item = by_file.get(rel)
        if item is None:
            raise SystemExit(f"{rel} is not a mirrored file in studio-sync-manifest.json")
        text = (ROOT / rel).read_text(encoding="utf-8")
        canonical = text.replace("\r\n", "\n").replace("\r", "\n")
        name = f"P{index}"
        parts.append(f'\t<Item class="ModuleScript" referent="RBX{index}">')
        parts.append("\t\t<Properties>")
        parts.append(f'\t\t\t<string name="Name">{name}</string>')
        parts.append(f'\t\t\t<ProtectedString name="Source">{escape(text)}</ProtectedString>')
        parts.append("\t\t</Properties>")
        parts.append("\t</Item>")
        staged.append(
            {
                "Slot": name,
                "StudioPath": item["studioPath"],
                "ClassName": item["className"],
                "File": rel,
                "Bytes": len(canonical.encode("utf-8")),
                "TrailingNewline": bool(item.get("studioTrailingNewline")),
            }
        )
    parts.append("</roblox>")
    payload.write_text("\n".join(parts), encoding="utf-8")
    (stage / "manifest.json").write_text(
        json.dumps(staged, indent=1, ensure_ascii=False), encoding="utf-8"
    )

    print(f"staged {len(staged)} script(s) -> {payload}")
    print(f"asset url: rbxasset://{STAGE_DIR_NAME}/{PAYLOAD_NAME}")
    print(json.dumps(staged, indent=1, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv))
