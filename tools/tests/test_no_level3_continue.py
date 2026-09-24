"""Finishing Level 3 must never continue into Level 4 -- for anyone.

The owner's rule of 2026-09-23 (NO_LEVEL3_CONTINUE_20260923): Level 4 stays
reachable only from its dev-gated lobby stations and ServerStorage.Level4DevStart.
Before this, GameManager's post-win window asked for the next level under the
dev ceiling, so an all-developer party was offered Level 3 -> Level 4.

Two halves, because either one alone can pass while the game is wrong:
  1. The REAL Round Completion Routing module, run in offline Luau: the campaign
     chain ends at 3 and there is no dev-ceiling version of NextLevel left.
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
check(Routing.MaxLevel == 3, "the campaign still ends at Level 3")
check(Routing.NextLevel(1) == 2 and Routing.NextLevel(2) == 3, "Levels 1 and 2 still continue")
check(Routing.NextLevel(3) == nil, "Level 3 must offer no next level")
check(not Routing.OffersContinue(3), "Level 3 must offer no Continue")
check(Routing.NextLevelTo == nil, "no dev-ceiling NextLevel may exist")
-- The dev gate itself is unchanged: a developer party may still be SENT to
-- Level 4 from the lobby, which is ClampLevelTo, not a continuation.
check(Routing.ClampLevelTo(4, Routing.DevCeiling(true, true)) == 4, "the dev lobby gate still reaches Level 4")
check(Routing.ClampLevelTo(4, Routing.DevCeiling(true, false)) == 3, "a normal party is still clamped to 3")
for _, message in ipairs(failures) do print("FAIL: " .. message) end
assert(#failures == 0, #failures .. " routing checks failed")
print("routing: Level 3 has no continuation")
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
    assert re.search(r"local nextLevel = Routing\.NextLevel\(activeLevel\)\n", body), \
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
    print("GameManager: the post-win window never continues past Level 3")


if __name__ == "__main__":
    main()
