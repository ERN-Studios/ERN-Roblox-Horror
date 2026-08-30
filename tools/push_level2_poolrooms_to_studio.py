"""Push the reviewed Level 2 Poolrooms polish scripts to the open Studio place."""

from __future__ import annotations

import json
from pathlib import Path
import sys
import time

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import (  # noqa: E402
    StudioMcpClient,
    StudioMcpError,
    decode_script_read,
    find_mcp_batch,
    select_studio,
)


ROOT = Path(__file__).resolve().parents[1]
CHANGED_FILES = (
    "ServerScriptService/GameManager.Script.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Slide Ragdoll Service.Script.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Configuration.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Layout Generator.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 World Builder.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Objective Controller.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Round Adapter.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Configuration.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Controller.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Navigator.ModuleScript.lua",
    "ServerScriptService/Level 2 Systems/Level 2 Pool Foam Proxy Factory.ModuleScript.lua",
    "StarterPlayer/StarterPlayerScripts/NoiseReporter.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/Level 2 Pool Foam Client.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/Level 2 Slide Controller.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua",
)


def main() -> int:
    manifest = json.loads((ROOT / "studio-sync-manifest.json").read_text(encoding="utf-8"))
    by_file = {item["file"]: item for item in manifest["items"]}
    missing = [relative for relative in CHANGED_FILES if relative not in by_file]
    if missing:
        raise StudioMcpError(f"Files missing from sync manifest: {missing}")

    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        time.sleep(2)
        studio = select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        studio_id = studio["id"]
        state = client.call("get_studio_state", {"studio_id": studio_id})
        if "Current Studio Mode: Edit" not in state:
            raise StudioMcpError("Refusing to push while Studio is not in Edit mode")

        prepared: list[tuple[str, str | None, str, str]] = []
        for relative in CHANGED_FILES:
            manifest_item = by_file[relative]
            studio_path = manifest_item["studioPath"]
            try:
                current = decode_script_read(
                    client.call(
                        "script_read",
                        {
                            "studio_id": studio_id,
                            "target_file": f"game.{studio_path}",
                            "should_read_entire_file": True,
                        },
                    )
                )
            except StudioMcpError:
                # New reviewed scripts can be created atomically by multi_edit;
                # all existing-script read failures are still caught by the
                # verification read immediately after the write.
                current = None
            desired = (ROOT / relative).read_text(encoding="utf-8")
            if current != desired:
                prepared.append((
                    studio_path, current, desired, manifest_item["className"]))

        for index, (studio_path, current, desired, class_name) in enumerate(prepared, start=1):
            request = {
                "studio_id": studio_id,
                "file_path": f"game.{studio_path}",
                "datamodel_type": "Edit",
                "edits": [{
                    "old_string": current if current is not None else "",
                    "new_string": desired,
                }],
            }
            if current is None:
                request["className"] = class_name
            client.call("multi_edit", request)
            reread = decode_script_read(
                client.call(
                    "script_read",
                    {
                        "studio_id": studio_id,
                        "target_file": f"game.{studio_path}",
                        "should_read_entire_file": True,
                    },
                )
            )
            if reread != desired:
                raise StudioMcpError(f"Verification failed after pushing {studio_path}")
            print(f"[{index}/{len(prepared)}] pushed and verified {studio_path}")

        if not prepared:
            print("Studio already matches all reviewed Level 2 Poolrooms scripts")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
