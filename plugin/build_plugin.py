"""Package the Master Tuning panel as a local Studio plugin and install it.

The plugin lives OUTSIDE the Studio mirror on purpose: it is not part of the
place, so it has no manifest entry, no `.ClassName.lua` name, and
`verify_studio_parity.py` must never see it. That is also why it is installed by
copying a file rather than pushed through the sync pipeline.

Studio loads local plugins from %LOCALAPPDATA%\\Roblox\\Plugins on start, and
rescans when you use Plugins > Manage Plugins. A `.rbxmx` holding one Script is
the whole format.

    python plugin/build_plugin.py            build and install
    python plugin/build_plugin.py --print    write nothing, show where it would go
"""

from __future__ import annotations

import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
SOURCE = ROOT / "MasterTuningPlugin.server.lua"
PLUGIN_NAME = "MongoTV Master Tuning"
FILE_NAME = "MongoTVMasterTuning.rbxmx"


def escape(text: str) -> str:
    """XML-escape a Luau source, matching tools/stage_push_payload.py.

    Line endings are normalised to LF: Studio's XML reader hands CRLF back on
    load, and a plugin that grows one byte per line on every rebuild is the kind
    of thing nobody notices until a diff is unreadable.
    """
    return (
        text.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\r\n", "\n")
        .replace("\r", "\n")
    )


def plugins_dir() -> Path:
    local = os.environ.get("LOCALAPPDATA")
    if not local:
        raise SystemExit(
            "LOCALAPPDATA is not set. Studio plugins only install on the owner's "
            "Windows PC; a cloud session can build the .rbxmx but not place it."
        )
    return Path(local) / "Roblox" / "Plugins"


def build(source_text: str) -> str:
    return (
        '<roblox version="4">\n'
        '\t<Item class="Script" referent="RBX0">\n'
        "\t\t<Properties>\n"
        f'\t\t\t<string name="Name">{PLUGIN_NAME}</string>\n'
        f'\t\t\t<ProtectedString name="Source">{escape(source_text)}</ProtectedString>\n'
        "\t\t</Properties>\n"
        "\t</Item>\n"
        "</roblox>\n"
    )


def main(argv: list[str]) -> int:
    if not SOURCE.is_file():
        raise SystemExit(f"missing plugin source: {SOURCE}")
    source_text = SOURCE.read_text(encoding="utf-8")
    payload = build(source_text)

    target_dir = plugins_dir()
    target = target_dir / FILE_NAME

    if "--print" in argv:
        print(f"source : {SOURCE}  ({len(source_text.encode('utf-8'))} B)")
        print(f"target : {target}")
        print(f"exists : {target.is_file()}")
        return 0

    target_dir.mkdir(parents=True, exist_ok=True)
    previous = target.read_text(encoding="utf-8") if target.is_file() else None
    target.write_text(payload, encoding="utf-8", newline="\n")

    print(f"installed {target}")
    print(f"  {len(source_text.encode('utf-8'))} B of Luau -> {len(payload.encode('utf-8'))} B of .rbxmx")
    if previous is None:
        print("  new plugin: restart Studio, or use Plugins > Manage Plugins to load it")
    elif previous == payload:
        print("  unchanged")
    else:
        print("  updated: restart Studio to pick up the new source")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
