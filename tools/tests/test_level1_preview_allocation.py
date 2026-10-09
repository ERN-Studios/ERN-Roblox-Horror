"""Run actual Level 1 elevator and puzzle allocation blocks under offline Luau.

The elevator poster must advertise the same half-party circuit allocation that
PuzzleManager actually generates: 1,1,2,2,3,3 circuits for parties of 1..6.
Roblox rendering/networking is outside this test; no Studio or saves are used.

    LUAU_BIN=/path/to/luau python tools/tests/test_level1_preview_allocation.py

Optional source/individual-file overrides support verification before mirroring
a freshly exported Studio script. An optional historical GameManager baseline
must reproduce the old five party-size mismatches, so a stale repro fails.
"""
from pathlib import Path
import argparse
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANAGER = Path("ServerScriptService/GameManager.Script.lua")
PUZZLE = Path("ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua")


def briefing(source):
    matches = re.findall(
        r'workspace:SetAttribute\("Level1ActiveCircuitCount",[^\n]+', source
    )
    assert len(matches) == 1, "expected one authoritative elevator preview write"
    return matches[0]


def puzzle_allocation(source):
    anchor = "\tlocal n = math.clamp(#roundPlayers, 1, 6)"
    assert source.count(anchor) == 1, "expected one frozen-party puzzle allocation"
    start = source.index(anchor)
    stop = source.index("\n\tlocal fusesNeeded", start)
    return source[start:stop]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--sources", type=Path, default=ROOT)
    parser.add_argument("--manager", type=Path)
    parser.add_argument("--puzzle", type=Path)
    parser.add_argument("--baseline-manager", type=Path)
    parser.add_argument("--luau", default=os.environ.get("LUAU_BIN") or shutil.which("luau"))
    args = parser.parse_args()
    if not args.luau:
        raise SystemExit("Set LUAU_BIN or --luau; no checks were executed.")

    manager = (args.manager or args.sources / MANAGER).read_text(encoding="utf-8")
    puzzle = (args.puzzle or args.sources / PUZZLE).read_text(encoding="utf-8")
    program = '''local attrs={}
local workspace={SetAttribute=function(_,key,value) attrs[key]=value end}
local function roster(n)
 local result={}
 for i=1,n do result[i]={} end
 return result
end
'''
    functions = [
        ("preview", briefing(manager), "participants"),
        ("puzzle", puzzle_allocation(puzzle), "roundPlayers"),
    ]
    if args.baseline_manager:
        functions.append(("before", briefing(args.baseline_manager.read_text(encoding="utf-8")), "participants"))
    for name, body, parameter in functions:
        program += f"local function {name}({parameter})\n{body}\nreturn attrs.Level1ActiveCircuitCount\nend\n"

    program += '''local checks=0
local expected={1,1,2,2,3,3}
for n=1,6 do
 local party=roster(n)
 local actual=puzzle(party)
 assert(actual==expected[n],"puzzle must preserve the half-party rule for "..n)
 assert(preview(party)==actual,"elevator advertises nonexistent circuits for party "..n)
 checks+=2
 print("party="..n.." preview="..preview(party).." actual="..actual)
end
for _,case in ipairs({{0,1},{7,3},{12,3}}) do
 local party=roster(case[1])
 assert(puzzle(party)==case[2],"puzzle clamp boundary "..case[1])
 assert(preview(party)==puzzle(party),"briefing clamp boundary "..case[1])
 checks+=2
end
'''
    if args.baseline_manager:
        program += '''local mismatches=0
for n=1,6 do
 if before(roster(n))~=puzzle(roster(n)) then mismatches+=1 end
end
assert(mismatches==5,"historical baseline must reproduce parties 2..6")
checks+=1
print("Historical baseline reproduced five incorrect party briefings")
'''
    program += 'print("Level 1 preview allocation: "..checks.." checks passed (actual GameManager/PuzzleManager source)")\n'
    with tempfile.TemporaryDirectory(prefix="level1-preview-allocation-") as tmp:
        fixture = Path(tmp) / "allocation.luau"
        fixture.write_text(program, encoding="utf-8")
        result = subprocess.run([args.luau, str(fixture)], text=True, capture_output=True, timeout=15)
    print(result.stdout, end="")
    print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
