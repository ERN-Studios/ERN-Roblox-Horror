"""HazmatSkinDriver clearState is idempotent (Trello IRLeRBcN, Codex review of bc1192b).

Runs the REAL clearState sliced out of the driver. The server can remove a
False Sun visual (lobby return, death, unequip) before the client clears its
state; the motes attachment is then already gone. Cleanup must still restore
the native body instead of throwing half way and leaving it invisible.
Set LUAU_BIN, or put luau on PATH.
"""

import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
DRIVER = (ROOT / "StarterPlayer/StarterPlayerScripts/HazmatSkinDriver.LocalScript.lua").read_text(encoding="utf-8")


def section(source, start, stop):
    begin = source.index(start)
    return source[begin:source.index(stop, begin)]


TESTS = r'''
local checks = 0
local function equal(a, b, m) assert(a == b, m .. ": expected " .. tostring(b) .. ", got " .. tostring(a)); checks += 1 end
local function part(transparency)
    local p = {Parent = true, Transparency = transparency, LocalTransparencyModifier = 0, attrs = {}}
    function p:SetAttribute(k, v) self.attrs[k] = v end
    return p
end
local function world(motesParent)
    local body, suit = part(1), part(0)
    local bone = {Parent = true, Transform = "posed"}
    local destroyed = false
    local attachment = motesParent and {Destroy = function() destroyed = true end} or nil
    local state = {Originals = {[body] = 0}, VisualParts = {suit}, Bones = {{Bone = bone}},
        Motes = {Parent = attachment}}
    return state, body, suit, bone, function() return destroyed end
end
for _, alive in ipairs({true, false}) do
    local state, body, suit, bone, destroyed = world(alive)
    states = {p = state}
    local ok, err = pcall(clearState, "p")
    local label = alive and "motes still present" or "motes already removed"
    equal(ok, true, label .. ": clearState does not throw (" .. tostring(err) .. ")")
    equal(body.Transparency, 0, label .. ": native body visible again")
    equal(suit.Transparency, 1, label .. ": suit hidden")
    equal(bone.Transform, CFrame.identity, label .. ": bones reset")
    equal(destroyed(), alive, label .. ": motes destroyed only when present")
    equal(states.p, nil, label .. ": state dropped")
end
print(("HazmatSkinDriver cleanup: %d checks passed (real clearState)"):format(checks))
'''


def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN or install luau; no tests were executed.")
    clear = section(DRIVER, "local function clearState(player)", "local function buildState(")
    # clearState is a local; expose it (and the table it reads) to the checks.
    prelude = "\n".join([
        'local ORIGINAL_ATTRIBUTE = "ZyntraHazmatOriginalTransparency"',
        "local CFrame = {identity = 'identity'}",
        "states = {}",
    ])
    source = prelude + "\n" + clear.replace("local function clearState(player)", "function clearState(player)", 1) \
        .replace("local state = states[player]", "local state = states[player]", 1) + "\n" + TESTS
    with tempfile.TemporaryDirectory(prefix="hazmat-cleanup-") as directory:
        path = Path(directory) / "hazmat_cleanup.luau"
        path.write_text(source, encoding="utf-8")
        subprocess.run([binary, str(path)], check=True, timeout=60)


if __name__ == "__main__":
    main()
