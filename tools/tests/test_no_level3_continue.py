"""Finishing Level 3 continues into Level 4, and Level 4 ends the campaign.

History: the owner's rule of 2026-09-23 (NO_LEVEL3_CONTINUE_20260923) stopped the
campaign at Level 3; this file guarded it. On 2026-10-05 the owner lifted it: the
cinema round is the public Level 4 and the campaign's last level, so a Level 3
clear offers Continue into Level 4 and a Level 4 clear offers none. The file name
is kept; the contract is now the positive one.

What still holds from the old rule: no dev-ceiling route onward. Continue comes
only from the campaign chain, never from a developer ceiling.

Two halves, because either one alone can pass while the game is wrong:
  1. The REAL Round Completion Routing module, run in offline Luau: the campaign
     chain is 1 -> 2 -> 3 -> 4, ends at 4, and there is no dev-ceiling NextLevel.
  2. The REAL GameManager source: the post-win window takes its next level from
     that chain and applies no dev ceiling to it.
Set LUAU_BIN to an official luau executable, or put luau on PATH.
"""

import os
import re
import shutil
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "ServerScriptService"

LUAU_CHECKS = r'''
local failures = {}
local function check(condition, message)
    if not condition then table.insert(failures, message) end
end
-- 2026-10-05: NO_LEVEL3_CONTINUE_20260923 was lifted; Level 4 (the cinema) is public and the
-- campaign's last level. These replace the old "ends at 3" / "Level 3 offers nothing" checks.
check(Routing.MaxLevel == 4, "the campaign ends at Level 4")
check(Routing.NextLevel(1) == 2 and Routing.NextLevel(2) == 3, "Levels 1 and 2 still continue")
check(Routing.NextLevel(3) == 4, "Level 3 must continue into Level 4")
check(Routing.OffersContinue(3), "Level 3 must offer Continue")
check(Routing.NextLevel(4) == nil, "Level 4 is the last level: no next level")
check(not Routing.OffersContinue(4), "Level 4 must offer no Continue")
check(Routing.NextLevel(5) == nil, "nothing continues past the campaign")
check(Routing.NextLevelTo == nil, "no dev-ceiling NextLevel may exist")
check(Routing.DevCeiling == nil, "no dev ceiling above the campaign may exist")
check(Routing.DevMaxLevel == 4, "developer rounds stop at Level 4")
check(Routing.ClampLevelTo(4, 3) == 3, "an explicit ceiling of 3 still holds")
-- Was 3 under the old rule; with no ceiling the clamp is now the campaign's end, Level 4.
check(Routing.ClampLevelTo(4, nil) == 4, "no ceiling means the campaign ceiling")
check(Routing.ClampLevelTo(5, 5) == 4, "no round may be routed above Level 4")
-- Was ClampLevel(4) == 3 under the old rule; Level 4 is now inside the campaign.
check(Routing.ClampLevel(4) == 4, "the unceilinged clamp reaches Level 4")
check(Routing.ClampLevel(5) == 4, "the unceilinged clamp stops at Level 4")
for _, message in ipairs(failures) do print("FAIL: " .. message) end
assert(#failures == 0, #failures .. " routing checks failed")
print("routing: Level 3 continues to Level 4, Level 4 ends the campaign")
'''


def post_win_body(source: str) -> str:
    start = source.index("local function runPostWinIntermission")
    end = source.index("\nend\n", start)
    return source[start:end]


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")

    routing = (SERVER / "Round Completion Routing.ModuleScript.lua").read_text(encoding="utf-8-sig")
    script = "local Routing = (function()\n" + routing + "\nend)()\n" + LUAU_CHECKS
    with tempfile.TemporaryDirectory(prefix="no-l3-continue-") as directory:
        fixture = Path(directory) / "no_level3_continue.luau"
        fixture.write_text(script, encoding="utf-8")
        subprocess.run([binary, str(fixture)], check=True, timeout=60)

    manager = (SERVER / "GameManager.Script.lua").read_text(encoding="utf-8-sig").replace("\r\n", "\n")
    body = post_win_body(manager)
    # The Level 2 Blender preview may suppress the next level; nothing may raise it.
    assert re.search(r'local nextLevel = (?:workspace:GetAttribute\("Level2BlenderPreviewActive"\) ~= true and )?'
                     r'Routing\.NextLevel\(activeLevel\)(?: or nil)?\n', body), \
        "the post-win window must take its next level from the campaign chain"
    assert "devCeiling" not in body, "the post-win window must apply no dev ceiling"

    # No live script may bring a dev-ceiling continuation back under any name.
    offenders = []
    for path in list(SERVER.rglob("*.lua")) + list((ROOT / "StarterPlayer").rglob("*.lua")) \
            + list((ROOT / "ReplicatedStorage").rglob("*.lua")):
        if "Archive" in path.parts:
            continue
        if "NextLevelTo" in path.read_text(encoding="utf-8-sig", errors="replace"):
            offenders.append(str(path.relative_to(ROOT)))
    assert not offenders, "NextLevelTo is back in: " + ", ".join(offenders)
    print("GameManager: the post-win window follows the campaign chain, no dev ceiling")


if __name__ == "__main__":
    main()
