#!/usr/bin/env python3
"""Run the proposed REAL Routing and GameManager access functions in Luau.

This checks authority/transport combinations, not Roblox physics or teleport.
"""
from pathlib import Path
import argparse
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--sources", type=Path, required=True)
    parser.add_argument("--luau", type=Path, required=True)
    args = parser.parse_args()
    routing = (args.sources / "ServerScriptService/Round Completion Routing.ModuleScript.lua").read_text()
    manager = (args.sources / "ServerScriptService/GameManager.Script.lua").read_text()
    begin = manager.index("-- LEVEL5_MAP_PREVIEW_20260923. A ceiling")
    end = manager.index("-- Always-on server authority", begin)
    access = manager[begin:end]
    code = "local Routing = (function()\n" + routing + "\nend)()\n" + r'''
local flags = {}
local workspace = {}
function workspace:GetAttribute(name) return flags[name] end
function workspace:SetAttribute(name, value) flags[name] = value end
local DevAccess = {}
function DevAccess.IsAllowed(subject) return subject == true end
''' + access + r'''
local checks = 0
local function check(actual, wanted, name)
 checks += 1
 assert(actual == wanted, name .. ": " .. tostring(actual) .. " expected " .. tostring(wanted))
end
check(Routing.MaxLevel, 3, "public campaign stays 3")
check(Routing.DevLevel, 4, "legacy Level 4 constant unchanged")
check(Routing.DevCeiling(true, true), 4, "legacy developer ceiling unchanged")
check(Routing.NextLevel(3), nil, "no Level 3 continuation")
check(Routing.NextLevel(4), nil, "no Level 4 continuation")
check(Routing.NextLevel(5), nil, "no Level 5 continuation")
for _, four in ipairs({false, true}) do
 for _, five in ipairs({false, true}) do
  flags.Level4DevEnabled, flags.Level5DevEnabled = four, five
  for _, developers in ipairs({false, true}) do
   local group = developers and {true, true} or {true, false}
   local expectedCeiling = developers and (five and 5 or four and 4 or 3) or 3
   check(devCeiling(group), expectedCeiling, "derived ceiling")
   for level = 1, 6 do
    local expected = level <= 3 or developers and ((level == 4 and four) or (level == 5 and five))
    check(canAccessLevel(level, group), expected == true, "exact requested level " .. level)
   end
  end
 end
end
flags.Level4DevEnabled, flags.Level5DevEnabled = false, true
check(canAccessLevel(4, {true}), false, "5 enabled never bypasses 4 off")
check(canAccessLevel(5, {true}), true, "5 independent of 4 off")
check(canAccessLevel(5, {}), false, "empty group refused")
check(canAccessLevel(5, nil), false, "missing group refused")
check(canAccessLevel(4.5, {true}), false, "fractional development level refused")
check(canAccessLevel(0/0, {true}), false, "NaN refused")
check(canAccessLevel("bad", {true}), false, "invalid level refused")
check(devCeiling({}), 3, "empty group has no elevated transport ceiling")
local packet = Routing.ArrivalPacket({Level=5,Ceiling=5,SessionId="preview",Expected=2,Final=true})
check(packet.Level, 5, "authorized packet keeps level 5")
local parsed = Routing.SelectArrivalSession({{Member="dev1",Data=packet},{Member="dev2",Data=packet}})
check(parsed.Level, 5, "destination parser keeps level 5")
check(canAccessLevel(parsed.Level, {true,false}), false, "forged mixed roster cannot use packet")
check(Routing.ArrivalPacket({Level=5,Ceiling=3,SessionId="ordinary",Expected=1}).Level, 3, "ordinary transport ceiling remains 3")
print("PASS: " .. checks .. " access/transport assertions against proposed production source")
'''
    with tempfile.TemporaryDirectory(prefix="level5-access-") as tmp:
        path = Path(tmp) / "checks.luau"
        path.write_text(code)
        result = subprocess.run([str(args.luau.resolve()), str(path)], text=True, capture_output=True)
        print(result.stdout, end="")
        print(result.stderr, end="")
        raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
