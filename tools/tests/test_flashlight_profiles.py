"""FlashlightProfiles: every BASE beam still gains reach when focused (Roblox clamps Light.Range at 60).

The 2026-10-02 rework made the torch much stronger; a BASE range above 60/1.45 would make the paid focus
mode (Advanced Equipment, "+45% range") narrow the beam for no extra reach. Runs the real module.
Set LUAU_BIN to a luau executable.
"""
import os, shutil, subprocess, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SRC = (ROOT / "ReplicatedStorage/FlashlightProfiles.ModuleScript.lua").read_text(encoding="utf-8-sig")
CHECKS = r'''
local workspace = {GetAttribute = function() return nil end}
local Profiles = (function() SRC_HERE end)()
local function light() return {Brightness = 0, Range = 0, Angle = 0} end
local n = 0
for _, setName in ipairs({"Own", "Mount", "Mate", "Spectate"}) do
	local set = Profiles[setName]
	for _, name in ipairs({"BASE", "L3", "L3_BLACKOUT"}) do assert(set[name], setName .. "." .. name) end
	local core, spill, fcore, fspill = light(), light(), light(), light()
	Profiles.Apply(set, "BASE", core, spill, false)
	Profiles.Apply(set, "BASE", fcore, fspill, true)
	assert(core.Range * 1.45 <= 60.5, setName .. " BASE core range leaves no room for focus: " .. core.Range)
	assert(math.min(fcore.Range, 60) > core.Range, setName .. " focus must add core reach")
	assert(math.min(fspill.Range, 60) > spill.Range, setName .. " focus must add spill reach")
	assert(core.Brightness >= 4, setName .. " BASE core is the reworked (bright) torch")
	n += 1
end
print("flashlight profiles: " .. n .. " BASE sets keep a real focus gain under the 60-stud cap")
'''

def main():
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not binary:
        raise SystemExit("Set LUAU_BIN; no tests were executed.")
    script = CHECKS.replace("SRC_HERE", SRC)
    with tempfile.TemporaryDirectory() as d:
        f = Path(d) / "profiles.luau"
        f.write_text(script, encoding="utf-8")
        subprocess.run([binary, str(f)], check=True, timeout=60)

if __name__ == "__main__":
    main()
