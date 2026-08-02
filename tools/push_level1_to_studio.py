"""Safely push this task's changed scripts back to the open Studio place."""

from __future__ import annotations

import hashlib
import difflib
import json
from pathlib import Path
import re
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
    "ServerScriptService/EntityAI.Script.lua",
    "ServerScriptService/EntityAnimation.Script.lua",
    "ServerScriptService/MazeGenerator.Script.lua",
    "ServerScriptService/PuzzleManager.Script.lua",
    "StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/FlashlightController.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua",
    "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua",
)


def digest(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def main() -> int:
    manifest = json.loads((ROOT / "studio-sync-manifest.json").read_text(encoding="utf-8"))
    by_file = {item["file"]: item for item in manifest["items"]}
    missing = [file for file in CHANGED_FILES if file not in by_file]
    if missing:
        raise StudioMcpError(f"Files missing from baseline manifest: {missing}")

    animation_ids_only = "--animation-ids-only" in sys.argv[1:]
    post_playtest_fixes = "--post-playtest-fixes" in sys.argv[1:]
    if animation_ids_only:
        changed_files = ("ServerScriptService/EntityAnimation.Script.lua",)
    elif post_playtest_fixes:
        changed_files = (
            "ServerScriptService/EntityAI.Script.lua",
            "ServerScriptService/MazeGenerator.Script.lua",
        )
    else:
        changed_files = CHANGED_FILES

    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "Backrooms: No Way Out", 20)

        prepared: list[tuple[str, str, str]] = []
        conflicts: list[str] = []
        for relative in changed_files:
            item = by_file[relative]
            studio_path = item["studioPath"]
            current = decode_script_read(
                client.call(
                    "script_read",
                    {
                        "target_file": f"game.{studio_path}",
                        "should_read_entire_file": True,
                    },
                )
            )
            desired = (ROOT / relative).read_text(encoding="utf-8")
            if post_playtest_fixes:
                expected_previous = desired
                if relative.endswith("EntityAI.Script.lua"):
                    expected_previous = expected_previous.replace(
                        "\t2.0,   -- friction (Roblox maximum; grips hard without runtime clamping)",
                        "\t3.0,   -- friction (high — grips hard)",
                        1,
                    )
                elif relative.endswith("MazeGenerator.Script.lua"):
                    expected_previous = expected_previous.replace(
                        "ELEV_CEILING_TEXTURE = resolveTexture(ELEV_CEILING_TEXTURE)\n",
                        "",
                        1,
                    )
                if current != expected_previous:
                    conflicts.append(studio_path)
                    continue
            elif animation_ids_only:
                previous_id_block = '''local ANIMATION_IDS = {
	Watch = "",                    -- Blender: Watch (idle loop)
	Walk = "74979742062849",       -- Blender: Walk
	Run = "138859570115399",       -- Blender: Run_Chase
	Howl = "117128353689729",      -- Blender: Yell_Howl (first sight)
	YellFromRun = "",              -- Blender: Yell_FromRun (pit yell)
	Lunge = "",                   -- Blender: Lunge (fallback)
	LungeFromRun = "",            -- Blender: Lunge_FromRun (normal chase lunge)
}'''
                expected_previous = re.sub(
                    r"local ANIMATION_IDS = \{.*?\n\}",
                    previous_id_block,
                    desired,
                    count=1,
                    flags=re.DOTALL,
                )
                if current != expected_previous:
                    print("".join(difflib.unified_diff(
                        expected_previous.splitlines(keepends=True),
                        current.splitlines(keepends=True),
                        fromfile="expected Studio copy",
                        tofile="current Studio copy",
                    )))
                    conflicts.append(studio_path)
                    continue
            elif digest(current) != item["sha256"]:
                if relative.endswith("DevCheats.LocalScript.lua"):
                    guard = '''		if not unlimitedAllowed() then
			print("[DevCheats] Unlimited battery/stamina: not on the whitelist")
			return
		end
'''
                    merged = re.sub(
                        r"--[^\n]*OWN whitelist[^\n]*\n"
                        r"--[^\n]*case-sensitive[^\n]*\n"
                        r"local UNLIMITED_ALLOWED[^\n]*\n"
                        r"local unlimitedOn = false\n"
                        r"local function unlimitedAllowed\(\)\n.*?\nend",
                        "local unlimitedOn = false",
                        current,
                        count=1,
                        flags=re.DOTALL,
                    )
                    merged = merged.replace(guard, "")
                    if merged != desired:
                        conflicts.append(studio_path)
                        continue
                else:
                    conflicts.append(studio_path)
                    continue
            prepared.append((studio_path, current, desired))

        if conflicts:
            raise StudioMcpError(
                "Studio changed after the baseline sync; refusing to overwrite: "
                + ", ".join(conflicts)
            )

        for index, (studio_path, current, desired) in enumerate(prepared, start=1):
            client.call(
                "multi_edit",
                {
                    "file_path": f"game.{studio_path}",
                    "datamodel_type": "Edit",
                    "edits": [{"old_string": current, "new_string": desired}],
                },
            )
            reread = decode_script_read(
                client.call(
                    "script_read",
                    {
                        "target_file": f"game.{studio_path}",
                        "should_read_entire_file": True,
                    },
                )
            )
            if reread != desired:
                raise StudioMcpError(f"Verification failed after pushing {studio_path}")
            print(f"[{index}/{len(prepared)}] pushed and verified {studio_path}")
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
