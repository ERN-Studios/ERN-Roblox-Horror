"""Offline Level 2 kit contract: real Luau, 400 seeds, independent geometry oracle.

Only this new module is mutated, briefly, by --mutation-check. Existing files are
read only. Fixtures live in the OS temporary directory. Roblox RNG distributions
will differ: the stub uses Park-Miller integer arithmetic, not Roblox Random.
"""

from __future__ import annotations

import argparse
from collections import Counter, defaultdict, deque
import hashlib
import json
import math
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 2 Systems"
MODULE = SYSTEMS / "Level 2 Kit Layout Generator.ModuleScript.lua"
LIVE = SYSTEMS / "Level 2 Layout Generator.ModuleScript.lua"
CONFIG = SYSTEMS / "Level 2 Configuration.ModuleScript.lua"
DEFAULT_BIN = ("C:/Users/mikke/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/"
               "LocalCache/Local/CodexTools/luau/0.737/luau.exe")
TUNNEL_LENGTHS = {64, 72, 80}
PASSAGE_LENGTHS = {16, 24, 32, 48, 64, 80}
PREFABS = {
    "Chamber_A": (48, 48, "Chamber", 15),
    "Chamber_B": (48, 64, "Chamber", 15),
    "Chamber_C": (64, 64, "Chamber", 15),
    "Chamber_D": (40, 56, "Chamber", 15),
}
HALL_TYPE_WEIGHTS = {"ColumnHall": 25, "BigPool": 15, "VaultArcade": 15,
                     "CurvedChannel": 20, "SpiralWell": 10, "CorridorHall": 15}
VAULT_MIN_SIDE = 160
ARCHETYPES = {
    "Deep": {"Diving Well", "Pillar Basin", "Column Forest"},
    "Shallow": {"Flooded Gallery", "Curved Gallery", "Skylight Hall", "Column Forest",
                "Arch Tunnel", "Ring Corridor", "Spiral Stair Well", "Porthole Hall"},
}

PRELUDE = r'''
local Vector3 = {}
local vectorMeta = {
    __sub = function(a,b) return Vector3.new(a.X-b.X,a.Y-b.Y,a.Z-b.Z) end,
    __index = function(v,k)
        if k == "Magnitude" then return math.sqrt(v.X*v.X+v.Y*v.Y+v.Z*v.Z) end
        return nil
    end,
}
function Vector3.new(x,y,z) return setmetatable({X=x,Y=y,Z=z},vectorMeta) end
local Color3 = {fromRGB = function(r,g,b) return {R=r,G=g,B=b} end}
local DateTime = {now = function() return {UnixTimestampMillis=1728000000000} end}
local Random = {}
local randomSeeds = {}
function Random.new(seed)
    seed = seed or 123456789
    table.insert(randomSeeds, seed)
    local state = math.floor(seed) % 2147483647
    if state == 0 then state = 1 end
    local function draw()
        state = (state * 16807) % 2147483647
        return (state - 1) / 2147483646
    end
    return {
        NextNumber = function(_,low,high)
            local n = draw()
            if low == nil then return n end
            return low + (high - low) * n
        end,
        NextInteger = function(_,low,high) return low + math.floor(draw() * (high-low+1)) end,
    }
end
-- Luau 0.737 already supplies math.clamp/sign and table.clone/find.
local Configuration = (function()
__CONFIG__
end)()
local script = {Parent={WaitForChild=function(_,name)
    assert(name == "Level 2 Configuration")
    return Configuration
end}}
local require = function(value) return value end
local Generator = (function()
__MODULE__
end)()
local function encode(value)
    local kind = type(value)
    if kind == "string" then return string.format("%q", value) end
    if kind == "number" or kind == "boolean" then return tostring(value) end
    assert(kind == "table", "unsupported serialized value: "..kind)
    local parts = {}
    if #value > 0 then
        for _, item in ipairs(value) do table.insert(parts, encode(item)) end
        return "["..table.concat(parts,",").."]"
    end
    local keys = {}
    for key in pairs(value) do table.insert(keys, tostring(key)) end
    table.sort(keys)
    for _, key in ipairs(keys) do
        local item = value[key]
        if item == nil then item = value[tonumber(key)] end
        table.insert(parts, string.format("%q",key)..":"..encode(item))
    end
    return "{"..table.concat(parts,",").."}"
end
local function emit(seed, options, label)
    local before = #randomSeeds
    local layout = Generator.Generate(seed, options)
    local ok, reason = Generator.Validate(layout)
    assert(ok, tostring(reason))
    local separate = false
    for i=before+1,#randomSeeds do
        if randomSeeds[i] == layout.Seed + 0x2B1E then separate = true end
    end
    assert(separate, "extras must use a separate RNG with the specified seed")
    print(label.." "..encode(layout))
end
__RUN__
'''


def run_layouts(binary, seeds, extra="", timeout=120, source=None, prelude=PRELUDE):
    source = source or MODULE.read_text(encoding="utf-8")
    script = prelude.replace("__CONFIG__", CONFIG.read_text(encoding="utf-8"))
    script = script.replace("__MODULE__", source)
    calls = [f'emit({seed}, nil, "LAYOUT")' for seed in seeds]
    script = script.replace("__RUN__", "\n".join(calls) + "\n" + extra)
    with tempfile.TemporaryDirectory(prefix="level2-kit-layout-") as directory:
        fixture = Path(directory) / "kit_test.luau"
        fixture.write_text(script, encoding="utf-8")
        result = subprocess.run([binary, str(fixture)], capture_output=True, text=True, timeout=timeout)
    if result.returncode:
        raise AssertionError(f"Luau execution failed:\n{result.stderr}\n{result.stdout[-2000:]}")
    return [(line.split(" ", 1)[0], json.loads(line.split(" ", 1)[1]))
            for line in result.stdout.splitlines() if " " in line]


def compile_module(binary):
    compiler = os.environ.get("LUAU_COMPILE_BIN")
    if not compiler:
        executable = Path(binary)
        compiler = str(executable.with_name("luau-compile" + executable.suffix))
        if not Path(compiler).exists():
            compiler = shutil.which("luau-compile")
    assert compiler, "luau-compile is required; compilation was not tested"
    result = subprocess.run([compiler, "-O0", str(MODULE)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stderr
    print("PASS luau-compile -O0 (including the 200-register limit)")


def rect(room):
    return tuple(room[key] for key in ("MinX", "MaxX", "MinZ", "MaxZ"))


def touches(a, b, inclusive=True):
    ax, bx, az, bz = a
    cx, dx, cz, dz = b
    if inclusive:
        return ax <= dx and cx <= bx and az <= dz and cz <= bz
    return ax < dx and cx < bx and az < dz and cz < bz


def corridor_rect(c):
    low, high = c["Cross"] - c["Width"] / 2, c["Cross"] + c["Width"] / 2
    return (c["From"], c["To"], low, high) if c["Axis"] == "X" else (low, high, c["From"], c["To"])


def span(h, axis):
    return (h["MinZ"], h["MaxZ"]) if axis == "X" else (h["MinX"], h["MaxX"])


def socket(h, axis, cross):
    low, high = span(h, axis)
    assert low + 8 <= cross <= high - 8
    if h["Role"] == "Small":
        # Rotation swaps the wall length; the centre and symmetric +/-16 socket
        # set is invariant under reversing the authored wall's direction.
        assert abs(cross - (low + high) / 2) in ({0, 16} if high - low >= 64 else {0})


def corner_safe(h, axis, cross, width):
    """FA review: the generator's corner-door rule. No door edge 4.8..8.125 from a cove hall's boundary: that corner
    is square and its base foot too short for the mitred inner corner plus a stop (the builder left it bare)."""
    if h["Role"] == "Small":
        return True
    lo, hi = span(h, axis)
    return all(not 4.8 <= clear < 8.125 for clear in (cross - width / 2 - lo, hi - cross - width / 2))


def distances(start, halls, corridors, allow=lambda c: True):
    graph = defaultdict(list)
    for c in corridors:
        if allow(c):
            graph[c["A"]].append(c["B"])
            graph[c["B"]].append(c["A"])
    result = {start: 0}
    queue = deque([start])
    while queue:
        node = queue.popleft()
        for other in graph[node]:
            if other not in result:
                result[other] = result[node] + 1
                queue.append(other)
    return result


def separation(a, b):
    # Roles are chosen before floor assignment: live spacing is horizontal.
    return math.hypot(a["Center"]["X"] - b["Center"]["X"], a["Center"]["Z"] - b["Center"]["Z"])


def spread(candidates, count, gap):
    picked = []
    for h in candidates:
        if all(separation(h, other) >= gap for other in picked):
            picked.append(h)
            if len(picked) == count:
                break
    return picked


def validate_roles(layout, halls, corridors):
    arrival = layout["Arrival"]
    slides, pumps, kids = (layout[key] for key in ("SlideHalls", "PumpHalls", "KidsArea"))
    grand = layout["GrandSlideHall"]
    dens = [layout["EntityDen"], layout["EntityDenB"]]
    named = [arrival, *slides, *pumps, *kids, *dens]
    for h in named:
        assert h == halls[h["Index"]] and h["Role"] != "Small"
    ids = [h["Index"] for h in named]
    assert len(ids) == 12 and len(set(ids)) == 11  # pump 1 is also a kids hall
    assert arrival["Role"] == "Arrival" and arrival["PoolType"] == "Dry" and arrival["Type"] == "Arrival"
    assert arrival["Archetype"] == "Arrival Concourse"
    bounds = layout["Bounds"]
    corner = min((h for h in halls.values() if h["Role"] != "Small"),
                 key=lambda h: math.hypot(h["Center"]["X"] - bounds["MinX"], h["Center"]["Z"] - bounds["MinZ"]))
    assert arrival["Index"] == corner["Index"]
    assert len(slides) == 1 and grand == slides[0] and grand["IsGrand"] is True
    assert [h for h in halls.values() if h["Role"] == "Slide Hall"] == slides
    candidates = sorted([h for h in halls.values() if h != arrival and h["GraphDepth"] >= 1
                         and h.get("Footprint") == "GrandSlideHall"],
                        key=lambda h: (-h["Area"], h["Index"]))
    exits = [h for h in candidates if h.get("Footprint") == "GrandSlideHall"
             and bounds["MaxX"] - h["MaxX"] <= 80]
    assert grand == min(exits, key=lambda h: (-h["MaxX"], h["Index"]))
    assert slides == [grand]
    for i, h in enumerate(slides, 1):
        assert h["Role"] == "Slide Hall" and h["PoolType"] == "Slide" and h["Type"] == "ExitHall"
        assert h["SlideHallIndex"] == i and h["GraphDepth"] >= 1
        assert h["Archetype"] == "Grand Slide Hall"
        assert all(separation(h, other) >= 320 for other in slides if h != other)
    assert grand["Leaf"]["MaxX"] == bounds["MaxX"] and bounds["MaxX"] - grand["MaxX"] <= 80
    assert len(kids) == 5 and len(pumps) == 3
    assert len(set(h["Index"] for h in kids) & set(h["Index"] for h in pumps)) == 1
    assert pumps[0] in kids[1:] and pumps[0]["PoolType"] == "KidsDry"
    assert pumps[0] == min(kids[1:], key=lambda h: (-h["Area"], -h["GraphDepth"], h["Index"]))
    kid_ids = {h["Index"] for h in kids}
    kid_edges = [c for c in corridors if c["A"] in kid_ids and c["B"] in kid_ids]
    assert len(distances(kids[0]["Index"], halls, kid_edges)) == 5
    assigned = {}
    for i, h in enumerate(kids, 1):
        assert h["Role"] == "Kids Area" and h["Type"] == "PaddlingRoom" and h["KidsIndex"] == i and h["GraphDepth"] >= 2
        assert max(h["Width"], h["Depth"]) <= 200
        assert h["Archetype"] == "Kids Play Room"
        assert h["PoolType"] == ("KidsShallow" if i == 1 else "KidsDry")
        used = {assigned[n] for n in h["Connections"] if n in assigned}
        palette = [(i - 1 + offset) % 3 + 1 for offset in range(3)]
        expected = next((color for color in palette if color not in used), (i - 1) % 3 + 1)
        assert h["KidsColorIndex"] == expected
        assigned[h["Index"]] = expected
    protected = {arrival["Index"], *(h["Index"] for h in slides), *kid_ids}
    outside = [h for h in halls.values() if h["Role"] != "Small" and h["Index"] not in protected
               and h["GraphDepth"] >= 1 and separation(h, pumps[0]) >= 300]
    outside.sort(key=lambda h: (-separation(h, pumps[0]), -h["GraphDepth"], h["Index"]))
    assert pumps[1:] == spread(outside, 2, 300)
    for i, h in enumerate(pumps, 1):
        assert h["PumpIndex"] == i
        assert all(separation(h, other) >= 300 for other in pumps if h != other)
        if i > 1:
            assert h["Role"] == "Pump Station" and h["Type"] == "PumpHall"
            assert h["PoolType"] == "Dry" and h["Archetype"] == "Pump Station"
    protected.update(h["Index"] for h in pumps)
    den_candidates = sorted([h for h in halls.values() if h["Role"] != "Small" and h["Index"] not in protected],
                            key=lambda h: (-h["GraphDepth"], h["Index"]))
    assert dens[0] == den_candidates[0]
    assert dens[1] == next((h for h in den_candidates[1:] if separation(h, dens[0]) >= 300), den_candidates[1])
    assert dens[0]["Role"] == "Entity Den" and dens[0]["PoolType"] == "Deep" and dens[0]["Archetype"] == "Sunken Basin"
    assert dens[1]["Role"] == "Entity Den B" and dens[1]["PoolType"] == "Shallow" and dens[1]["Archetype"] == "Column Forest"
    for h in dens:
        assert h["Type"] in {"ColumnHall", "VaultArcade"}
        if h["Type"] == "VaultArcade":
            # F4-I: a den too small for a vault bay (both sides >= 160) is a ColumnHall.
            assert min(h["Width"], h["Depth"]) >= VAULT_MIN_SIDE and h["CeilingClass"] in {34, 42}, \
                "VaultArcade den below the 160-stud vault minimum"


def validate(layout, requested=None, deep_max=2.0, swerve_stats=None):
    assert layout["Version"] == "kit-v1"
    for key in ("Seed", "RequestedSeed", "Attempt", "AttemptWithinSequence", "FallbackUsed", "Distances",
                "Halls", "Corridors", "CorridorByPair", "SmallRooms", "NarrowCount", "TunnelCount"):
        assert key in layout, key
    if requested is not None:
        assert layout["RequestedSeed"] == math.floor(requested) % 2147483647
    if not layout["FallbackUsed"] and "RandomRecoverySeed" not in layout:
        assert layout["Seed"] == (layout["RequestedSeed"] + (layout["Attempt"] - 1) * 104729) % 2147483647
        assert layout["AttemptWithinSequence"] == layout["Attempt"]
    halls = {h["Index"]: h for h in layout["Halls"]}
    corridors = layout["Corridors"]
    assert list(halls) == list(range(1, len(halls) + 1))
    assert layout["HallCount"] == len(halls) and layout["CorridorCount"] == len(corridors)
    assert len(halls) >= 16
    small = set(layout["SmallRooms"])
    assert len(small) == len(layout["SmallRooms"])
    assert small == {i for i, h in halls.items() if h["Role"] == "Small"}
    leaves = defaultdict(list)
    for i, h in halls.items():
        assert h["Id"] == f"Level 2 Hall {i:02d}" and 1 <= h["LocalSeed"] <= 2**30
        assert all(math.isfinite(v) and v % 4 == 0 for v in rect(h))
        assert all(v % 4 == 0 for v in rect(h["Leaf"]))
        x0, x1, z0, z1 = rect(h)
        lx0, lx1, lz0, lz1 = rect(h["Leaf"])
        bx0, bx1, bz0, bz1 = rect(layout["Bounds"])
        assert bx0 <= lx0 <= x0 < x1 <= lx1 <= bx1 and bz0 <= lz0 <= z0 < z1 <= lz1 <= bz1
        assert h["Width"] == x1 - x0 and h["Depth"] == z1 - z0
        assert h["Area"] == h["Width"] * h["Depth"]
        assert h["FloorY"] in {-8, -4, 0, 4, 8}
        assert h["Center"] == {"X": (x0 + x1) / 2, "Y": h["FloorY"], "Z": (z0 + z1) / 2}
        assert 1.6 <= h["DeepEnd"] <= deep_max
        assert h["PoolAxis"] == ("X" if h["Width"] >= h["Depth"] else "Z")
        assert h["Rotation"] in {0, 90, 180, 270}
        leaves[h["LeafIndex"]].append(h)
        if i in small:
            w, d, archetype, ceiling = PREFABS[h["Prefab"]]
            if h["Rotation"] % 180 == 90:
                w, d = d, w
            assert (h["Width"], h["Depth"], h["Archetype"], h["CeilingClass"]) == (w, d, archetype, ceiling)
            assert h["Type"] == "Chamber"
            assert h["PoolType"] == "Dry"
            assert not any(key in h for key in ("PumpIndex", "KidsIndex", "SlideHallIndex", "IsGrand"))
        else:
            assert 96 <= h["Width"] <= 272 and 96 <= h["Depth"] <= 272
            assert set((x0 - lx0, lx1 - x1, z0 - lz0, lz1 - z1)) <= {32, 40}
            if h["Role"] == "Slide Hall":
                assert h["IsGrand"] and h["Footprint"] == "GrandSlideHall" and h["Rotation"] == 0
                assert (h["Width"], h["Depth"], h["Prefab"], h["CeilingClass"]) == (224, 208, "GrandSlideHall", 96)
                assert h["Type"] == "ExitHall"
            else:
                assert h["CeilingClass"] in {34, 42, 52}
            if h["Role"] == "Hall":
                assert h["Archetype"] in ARCHETYPES[h["PoolType"]]
                assert h["Type"] in HALL_TYPE_WEIGHTS
                if h["Type"] == "VaultArcade":
                    # F4-I (replaces >= 96): the builder's groin bays need four piers 25 and 62 off the
                    # axes clear of the deck band, i.e. both sides >= 160; smaller halls were bare pier arcades.
                    assert min(h["Width"], h["Depth"]) >= VAULT_MIN_SIDE and h["CeilingClass"] in {34, 42}, \
                        "VaultArcade hall below the 160-stud vault minimum"
                if h["Type"] == "BigPool":
                    assert h["Area"] >= 24000
                if h["Type"] == "CorridorHall":
                    assert max(h["Width"], h["Depth"]) / min(h["Width"], h["Depth"]) >= 2.2
                if h["Type"] == "SpiralWell":
                    assert h["CeilingClass"] in {42, 52}
                    # F8 (count): only a hall whose shorter side fits the unscaled 40-stud spiral pocket.
                    assert min(h["Width"], h["Depth"]) >= 128, "SpiralWell hall below the 128-stud minimum"
            assert h.get("Prefab") != "SlideHall" and h.get("Footprint") != "SlideHall"
    assert sorted(leaves) == list(range(1, len(leaves) + 1))
    # F8 (count): at most one spiral stair well per map (was a mean of 2.57, up to 7).
    assert sum(h["Type"] == "SpiralWell" for h in layout["Halls"]) <= 1, "more than one SpiralWell hall"
    leaf_rects = []
    for rooms in leaves.values():
        assert all(h["Leaf"] == rooms[0]["Leaf"] for h in rooms)
        assert (2 <= len(rooms) <= 4 and all(h["Role"] == "Small" for h in rooms)) or (len(rooms) == 1 and rooms[0]["Role"] != "Small")
        leaf_rects.append(rect(rooms[0]["Leaf"]))
    assert sum((x1 - x0) * (z1 - z0) for x0, x1, z0, z1 in leaf_rects) == ((layout["Bounds"]["MaxX"] - layout["Bounds"]["MinX"]) * (layout["Bounds"]["MaxZ"] - layout["Bounds"]["MinZ"]))
    assert all(not touches(a, b, False) for i, a in enumerate(leaf_rects) for b in leaf_rects[i+1:])
    pairs, adjacency, drains = {}, defaultdict(set), {}
    narrow = tunnel = 0
    for i, c in enumerate(corridors, 1):
        assert c["Index"] == i and c["Id"] == f"Level 2 Corridor {i:02d}"
        assert c["A"] != c["B"] and c["Axis"] in {"X", "Z"}
        a, b = halls[c["A"]], halls[c["B"]]
        pair = f'{min(c["A"], c["B"])}:{max(c["A"], c["B"])}'
        assert pair not in pairs and layout["CorridorByPair"][pair] == c
        pairs[pair] = c
        adjacency[c["A"]].add(c["B"])
        adjacency[c["B"]].add(c["A"])
        first, last = sorted((a, b), key=lambda h: h["Min" + c["Axis"]])
        assert c["From"] == first["Max" + c["Axis"]] and c["To"] == last["Min" + c["Axis"]]
        assert c["Length"] == c["To"] - c["From"] > 0, "corridor Length must equal the exact wall gap"
        assert all(c[key] % 4 == 0 for key in ("Cross", "From", "To"))
        al, ah = span(a, c["Axis"])
        bl, bh = span(b, c["Axis"])
        overlap = min(ah, bh) - max(al, bl)
        assert c["FromY"] == first["FloorY"] and c["ToY"] == last["FloorY"]
        dy = abs(c["FromY"] - c["ToY"])
        assert dy <= 8
        required_flat = (c["Kind"] == "PressureDoor" or "DrainGroup" in c or a["Role"] == "Kids Area"
                         or b["Role"] == "Kids Area" or a == layout["Arrival"] or b == layout["Arrival"]
                         or "PumpIndex" in a or "PumpIndex" in b)
        if required_flat:
            assert dy == 0
        if c["Kind"] == "Narrow":
            narrow += 1
            assert c["Width"] == 12 and c["Length"] in PASSAGE_LENGTHS and c["PoolType"] == "Dry"
            assert "DrainGroup" not in c and dy in {0, 4}
            assert c["Variant"] == ("Flat" if dy == 0 else "Stair4")
            socket(a, c["Axis"], c["Cross"])
            socket(b, c["Axis"], c["Cross"])
            if a["Index"] not in small and b["Index"] not in small:
                assert 28 <= overlap < 42
        else:
            tunnel += 1
            assert c["Kind"] in {"Open", "PressureDoor"} and c["Width"] == 34
            assert a["Index"] not in small and b["Index"] not in small
            assert c["Length"] in TUNNEL_LENGTHS and overlap >= 42
            assert al + 21 <= c["Cross"] <= ah - 21 and bl + 21 <= c["Cross"] <= bh - 21
            if dy:
                assert c["Variant"] == f"Stair{dy}" and c["PoolType"] == "Dry"
            else:
                expected = "Dry" if a == layout["Arrival"] or b == layout["Arrival"] else "Wet"
                assert c["Variant"] == expected
            assert c["Variant"] in {"Wet", "Dry", "Stair4", "Stair8"}
        # FA review (square corners): no door edge 4.8..8.125 from a cove hall's boundary. Such a corner is square and
        # its base foot (3.05..6.375 between the face and the hole) cannot hold the mitred inner corner's 3-stud leg
        # plus a 2.625 stop, so the builder had to leave it bare. Under 4.8 the door's threshold owns the corner.
        assert corner_safe(a, c["Axis"], c["Cross"], c["Width"]) and corner_safe(b, c["Axis"], c["Cross"], c["Width"]), \
            f"corridor {c['Index']} has an edge 4.8..8.125 from a hall corner (square, base foot too short)"
        grand_edge = a == layout["GrandSlideHall"] or b == layout["GrandSlideHall"]
        assert (c["Kind"] == "PressureDoor") == grand_edge
        if "DrainGroup" in c:
            group = c["DrainGroup"]
            assert group in {1, 2, 3} and group not in drains
            assert c["Kind"] == "Open" and c["PoolType"] == "Deep" and c["Length"] >= 40
            assert a["Role"] != "Kids Area" and b["Role"] != "Kids Area"
            assert a != layout["Arrival"] and b != layout["Arrival"] and c["Variant"] == "Wet"
            drains[group] = c
        envelope = corridor_rect(c)
        assert all(not touches(envelope, rect(h)) for h in halls.values() if h not in (a, b))
        assert all(not touches(envelope, corridor_rect(other)) for other in corridors[i:])
    assert set(drains) == {1, 2, 3}
    assert layout["NarrowCount"] == narrow and layout["TunnelCount"] == tunnel
    assert set(pairs) == set(layout["CorridorByPair"])
    for i, h in halls.items():
        assert len(h["Connections"]) == len(set(h["Connections"]))
        assert set(h["Connections"]) == adjacency[i] and h["ConnectionCount"] == len(adjacency[i])
        for j in range(i + 1, len(halls) + 1):
            other = halls[j]
            assert not touches(rect(h), rect(other), False)
            dx = max(0, h["MinX"] - other["MaxX"], other["MinX"] - h["MaxX"])
            dz = max(0, h["MinZ"] - other["MaxZ"], other["MinZ"] - h["MaxZ"])
            if f"{i}:{j}" not in pairs:
                assert math.hypot(dx, dz) >= 16
                if h["Role"] != "Small" and other["Role"] != "Small":
                    for axis in ("X", "Z"):
                        first, last = sorted((h, other), key=lambda room: room["Min" + axis])
                        gap = last["Min" + axis] - first["Max" + axis]
                        low, high = span(first, axis)
                        ol, oh = span(last, axis)
                        overlap = min(high, oh) - max(low, ol)
                        narrow_pair = 28 <= overlap < 42
                        assert not (narrow_pair and 0 < gap <= 80), "a required facing big-hall narrow link is missing"
                        if gap not in (PASSAGE_LENGTHS if narrow_pair else TUNNEL_LENGTHS) or overlap < 28:
                            continue
                        margin, width = (8, 12) if narrow_pair else (21, 34)
                        crosses = range(math.ceil(max(low + margin, ol + margin) / 4) * 4,
                                        math.floor(min(high - margin, oh - margin) / 4) * 4 + 1, 4)
                        for cross in crosses:
                            if not (corner_safe(first, axis, cross, width) and corner_safe(last, axis, cross, width)):
                                continue    # FA review: the generator's corner-door rule refuses this cross
                            candidate = {"Axis": axis, "From": first["Max" + axis], "To": last["Min" + axis],
                                         "Cross": cross, "Width": width}
                            envelope = corridor_rect(candidate)
                            obstructed = any(touches(envelope, rect(room)) for room in halls.values() if room not in (h, other))
                            obstructed |= any(touches(envelope, corridor_rect(c)) for c in corridors)
                            assert obstructed, "a clear eligible facing big-hall pair is missing its corridor"
    all_distances = distances(layout["Arrival"]["Index"], halls, corridors)
    assert len(all_distances) == len(halls)
    cached_distances = layout["Distances"]
    if isinstance(cached_distances, list):
        cached_distances = {i: v for i, v in enumerate(cached_distances, 1)}
    else:
        cached_distances = {int(k): v for k, v in cached_distances.items()}
    assert cached_distances == all_distances
    assert all(h["GraphDepth"] == all_distances[i] for i, h in halls.items())
    big_reached = distances(layout["Arrival"]["Index"], halls, corridors,
                            lambda c: c["Kind"] not in {"Narrow", "PressureDoor"})
    assert set(halls) - small - {layout["GrandSlideHall"]["Index"]} <= set(big_reached), \
        "every ordinary big hall must remain tunnel-reachable before exit power"
    unlocked = distances(layout["Arrival"]["Index"], halls, corridors, lambda c: c["Kind"] != "PressureDoor")
    assert set(unlocked) == set(halls) - {layout["GrandSlideHall"]["Index"]}
    validate_roles(layout, halls, corridors)
    check_swerve(layout, swerve_stats)


SWERVE_WALLS = ("North", "East", "South", "West")
SWERVE_HEADING = {"North": 0.0, "East": 90.0, "South": 180.0, "West": 270.0}   # travel, degrees in (x, z)
SWERVE_END_CORNER = {"North": 2, "East": 4, "South": 3, "West": 1}             # builder CORNERS index
# LATTICE_SPEC 4.7: (R, Deg label) -> (sin, cos) of the exact Pythagorean bend; Deg only names the kit piece.
SWERVE_S_FAMILIES = {(20, 53): (.8, .6), (15, 53): (.8, .6), (20, 37): (.6, .8)}
SWERVE_ARC_RADII = {24, 32, 48, 64}
SWERVE_TAIL = .25       # LATTICE_SPEC 2.5: the corner arc pieces' straight tails
SWERVE_DOOR = 21        # generator SWERVE_DOOR: d=0 each side of every door cross
HOLE_HALF = 18          # builder: a tunnel's wall hole is Cross +- 18 (a pipe's +- 6 lies further in)


def off_integer(v):
    return abs(v - round(v)) > 1e-6


def swerve_doors(layout):
    """Door crosses per hall and wall, from the corridors' geometry (the builder's hallDoors rule)."""
    halls = {h["Index"]: h for h in layout["Halls"]}
    out = defaultdict(lambda: defaultdict(list))
    for c in layout["Corridors"]:
        a, b = halls[c["A"]], halls[c["B"]]
        key = "X" if c["Axis"] == "X" else "Z"
        first, last = (a, b) if a["Center"][key] <= b["Center"][key] else (b, a)
        out[first["Index"]]["East" if key == "X" else "South"].append(c["Cross"])
        out[last["Index"]]["West" if key == "X" else "North"].append(c["Cross"])
    return out


def face_point(h, wall, along, offset):
    """World (x, z) of a wall-face point 'offset' studs into the room at world coordinate 'along'."""
    if wall == "North":
        return along, h["MinZ"] + 1.75 + offset
    if wall == "South":
        return along, h["MaxZ"] - 1.75 - offset
    if wall == "West":
        return h["MinX"] + 1.75 + offset, along
    return h["MaxX"] - 1.75 - offset, along


def swerve_keep_clear(h, doors):
    """The lane contract of the builder test's obstacle oracle: both full centre axes +-17, every door spoke
    +-17 from its wall to the centre, the 30 x 38 approach and the 34 x 8 mouth, as (x0, x1, z0, z1)."""
    cx, cz = h["Center"]["X"], h["Center"]["Z"]
    rects = [(cx - 17, cx + 17, h["MinZ"], h["MaxZ"]), (h["MinX"], h["MaxX"], cz - 17, cz + 17)]
    for side, crosses in doors.items():
        for cross in crosses:
            for half, depth in ((17, None), (15, 38), (17, 8)):
                if side == "West":
                    rects.append((h["MinX"], cx if depth is None else h["MinX"] + depth, cross - half, cross + half))
                elif side == "East":
                    rects.append((cx if depth is None else h["MaxX"] - depth, h["MaxX"], cross - half, cross + half))
                elif side == "North":
                    rects.append((cross - half, cross + half, h["MinZ"], cz if depth is None else h["MinZ"] + depth))
                else:
                    rects.append((cross - half, cross + half, cz if depth is None else h["MaxZ"] - depth, h["MaxZ"]))
    return rects


def rect_distance(r, x, z):
    return math.hypot(max(r[0] - x, 0, x - r[1]), max(r[2] - z, 0, z - r[3]))


def swerve_outline(h):
    """Walk the planned loop as a turtle: straights, the kit S bends (two equal arcs, turning toward the room
    and back, mirrored for Out) and the quarter corner arcs. Checks each segment starts where the previous
    ended. Returns samples (x, z, heading deg, segment index, curved) at most .5 apart and the polygon."""
    loop = h["Swerve"]["Loop"]
    samples, polygon = [], []
    pose = None
    for index, seg in enumerate(loop):
        wall = seg["Wall"]
        heading = SWERVE_HEADING[wall]
        travel = 1 if wall in ("North", "East") else -1
        if seg["Kind"] == "Straight":
            start = face_point(h, wall, seg["From"], seg["Offset"])
        elif seg["Kind"] == "Corner" and seg["R"]:
            # LATTICE_SPEC 2.5: a corner arc starts with its .25 tail before the tangent (its At).
            start = face_point(h, wall, seg["At"] - travel * SWERVE_TAIL, 0)
        else:
            start = face_point(h, wall, seg["At"], seg["Offset"] if seg["Kind"] == "S" else 0)
        if pose is not None:
            assert math.dist(pose[:2], start) <= .01, f"hall {h['Index']} loop gap before segment {index} {seg}"
            turn = (heading - pose[2]) % 360
            assert min(turn, 360 - turn) <= .1, f"hall {h['Index']} loop heading jumps {turn:.3f} deg before {index}"
        x, z, psi = start[0], start[1], heading

        def emit(curved, heading=None):
            samples.append((x, z, psi if heading is None else heading, index, curved))
            polygon.append((x, z))

        def line(length, curved):
            nonlocal x, z
            steps = max(1, math.ceil(length / .5))
            dx, dz = math.cos(math.radians(psi)), math.sin(math.radians(psi))
            for _ in range(steps):
                x, z = x + dx * length / steps, z + dz * length / steps
                emit(curved)

        def arc(radius, degrees):
            """Turn by 'degrees' (positive: toward the room) on 'radius'."""
            nonlocal x, z, psi
            sign = 1 if degrees > 0 else -1
            a = math.radians(psi)
            cx, cz = x - sign * radius * math.sin(a), z + sign * radius * math.cos(a)
            steps = max(1, math.ceil(radius * math.radians(abs(degrees)) / .5))
            for k in range(1, steps + 1):
                b = math.radians(psi + degrees * k / steps)
                x, z = cx + sign * radius * math.sin(b), cz - sign * radius * math.cos(b)
                emit(True, psi + degrees * k / steps)
            psi = psi + degrees
        emit(seg["Kind"] == "S" or seg["Kind"] == "Corner" and seg["R"] > 0 or seg["Kind"] == "Straight" and seg["Offset"] != 0)
        if seg["Kind"] == "Straight":
            direction = 1 if wall in ("North", "East") else -1
            assert (seg["To"] - seg["From"]) * direction > 0, f"hall {h['Index']} straight {index} runs backwards"
            assert seg["Offset"] >= 0
            line(abs(seg["To"] - seg["From"]), seg["Offset"] != 0)
        elif seg["Kind"] == "S":
            assert (seg["R"], seg["Deg"]) in SWERVE_S_FAMILIES and seg["Piece"] in ("In", "Out")
            sign = 1 if seg["Piece"] == "In" else -1
            angle = math.degrees(math.atan2(*SWERVE_S_FAMILIES[(seg["R"], seg["Deg"])]))
            arc(seg["R"], sign * angle)
            arc(seg["R"], -sign * angle)
        else:
            assert seg["Corner"] == SWERVE_END_CORNER[wall], f"hall {h['Index']} corner {index} on the wrong wall"
            if seg["R"]:
                assert seg["R"] in SWERVE_ARC_RADII
                line(SWERVE_TAIL, False)
                arc(seg["R"], 90)
                line(SWERVE_TAIL, False)
            else:
                # A standard corner: the face corner itself; the builder's fillet (R <= 24) takes over there.
                end = face_point(h, wall, {"North": h["MaxX"] - 1.75, "East": h["MaxZ"] - 1.75,
                                           "South": h["MinX"] + 1.75, "West": h["MinZ"] + 1.75}[wall], 0)
                assert math.dist((x, z), end) <= .01, f"hall {h['Index']} standard corner {index} is off the face corner"
                psi += 90
        pose = (x, z, psi % 360)
    first = loop[0]
    start = face_point(h, first["Wall"], first["From"] if first["Kind"] == "Straight" else first["At"],
                       first.get("Offset", 0) if first["Kind"] != "Corner" else 0)
    assert math.dist(pose[:2], start) <= .01, f"hall {h['Index']} loop does not close"
    turn = (SWERVE_HEADING[first["Wall"]] - pose[2]) % 360
    assert min(turn, 360 - turn) <= .1, f"hall {h['Index']} loop closes with a {turn:.3f} deg kink"
    return samples, polygon


def inside_polygon(polygon, x, z):
    inside = False
    for (x0, z0), (x1, z1) in zip(polygon, polygon[1:] + polygon[:1]):
        if (z0 > z) != (z1 > z) and x < x0 + (z - z0) * (x1 - x0) / (z1 - z0):
            inside = not inside
    return inside


def check_swerve(layout, stats=None):
    """ANALYSIS F9 check 2: an independent oracle of every planned swerve outline (not a port of planSwerve:
    it walks the stored segments as a turtle and measures the result)."""
    doors = swerve_doors(layout)
    swerve = [h for h in layout["Halls"] if h.get("Swerve")]
    # F9 review (G8): 2..3 per map (FIX_SPEC allows 2..4; capping at 3 took the 50-seed max delta +871 -> +686).
    assert 2 <= len(swerve) <= 3, f"F9: {len(swerve)} swerve halls (2..3 per map)"
    for h in layout["Halls"]:
        if h.get("Type") == "CurvedChannel":
            assert h.get("Swerve"), f"F9: CurvedChannel hall {h['Index']} has no swerve plan"
    for h in swerve:
        index = h["Index"]
        assert h["Role"] == "Hall" and h["Type"] == "CurvedChannel", f"F9: swerve hall {index} is {h['Role']}/{h['Type']}"
        loop = h["Swerve"]["Loop"]
        walls = [seg["Wall"] for seg in loop]
        assert [w for i, w in enumerate(walls) if i == 0 or w != walls[i - 1]] == list(SWERVE_WALLS) \
            or [w for i, w in enumerate(walls) if i == 0 or w != walls[i - 1]] == list(SWERVE_WALLS[1:] + SWERVE_WALLS[:1]), \
            f"F9: hall {index} loop does not run North, East, South, West"
        # LATTICE_SPEC 4.7: every joint on an integer (straight ends, S starts, a corner arc's first tail end; its
        # far tail ends on the next wall's first straight or S), so the builder's exact runs and the kit's whole
        # tiles meet. Checked before the turtle walks the loop.
        for seg in loop:
            travel = 1 if seg["Wall"] in ("North", "East") else -1
            joints = [seg["From"], seg["To"]] if seg["Kind"] == "Straight" else [seg["At"]] if seg["Kind"] == "S" \
                else [seg["At"] - travel * SWERVE_TAIL] if seg["R"] else []
            low, high = (h["MinX"], h["MaxX"]) if seg["Wall"] in ("North", "South") else (h["MinZ"], h["MaxZ"])
            for v in joints:
                # A straight's end at a standard corner is the face corner itself (the builder's corner rules own it).
                assert v in (low + 1.75, high - 1.75) or not off_integer(v),                     f"F9: hall {index} {seg['Kind']} joint {v} is off the integer lattice"
        samples, polygon = swerve_outline(h)
        rects = swerve_keep_clear(h, doors[index])
        x0, x1, z0, z1 = h["MinX"] + 1.75, h["MaxX"] - 1.75, h["MinZ"] + 1.75, h["MaxZ"] - 1.75
        keepout = h["Swerve"]["Keepout"]
        for x, z, psi, seg, curved in samples:
            assert x0 - 1e-6 <= x <= x1 + 1e-6 and z0 - 1e-6 <= z <= z1 + 1e-6, \
                f"F9: hall {index} outline leaves the face rectangle at ({x:.2f}, {z:.2f})"
            if not curved:
                continue
            nx, nz = -math.sin(math.radians(psi)), math.cos(math.radians(psi))
            for k, label in ((0, "face"), (9.5, "deck front")):
                px, pz = x + k * nx, z + k * nz
                near = min(rects, key=lambda r: rect_distance(r, px, pz))
                assert rect_distance(near, px, pz) >= 3 - 1e-6, \
                    f"F9: hall {index} {label} at ({px:.2f}, {pz:.2f}) of segment {seg} is within 3 of lane {near}"
                assert any(k0["MinX"] - 1e-6 <= px <= k0["MaxX"] + 1e-6 and k0["MinZ"] - 1e-6 <= pz <= k0["MaxZ"] + 1e-6
                           for k0 in keepout), f"F9: hall {index} {label} at ({px:.2f}, {pz:.2f}) outside every Keepout"
        # d == 0 exactly on [cross-21, cross+21] for every door.
        for side, crosses in doors[index].items():
            flat = [tuple(sorted((seg["From"], seg["To"]))) for seg in loop
                    if seg["Kind"] == "Straight" and seg["Wall"] == side and seg["Offset"] == 0]
            low, high = (x0, x1) if side in ("North", "South") else (z0, z1)
            for cross in crosses:
                need = (max(cross - SWERVE_DOOR, low), min(cross + SWERVE_DOOR, high))    # the face line ends at the corner faces
                assert any(a - 1e-6 <= need[0] and need[1] <= b + 1e-6 for a, b in flat), \
                    f"F9: hall {index} {side} door {cross} lacks its door straight (d=0 over cross+-{SWERVE_DOOR})"
        # Radii, and the builder's deck fit (LATTICE_SPEC 2.5: exact runs at stretch 1 from 14 kit lengths, 128..1):
        # a straight between two curved pieces (a plateau included) is a whole number of studs, and one from a
        # standard corner to a curved piece is >= 56.25 (that corner's deck starts up to 24.25 in).
        for i, seg in enumerate(loop):
            if seg["Kind"] != "Straight" and seg.get("R"):
                assert seg["R"] >= 15, f"F9: hall {index} radius {seg['R']} under 15"
            if seg["Kind"] == "Straight":
                before, after = loop[i - 1], loop[(i + 1) % len(loop)]
                curved = [n["Kind"] == "S" or n["Kind"] == "Corner" and n["R"] > 0 for n in (before, after)]
                length = abs(seg["To"] - seg["From"])
                fits = length >= 1 - 1e-6 and not off_integer(length)
                assert not all(curved) or fits, \
                    f"F9: hall {index} straight {i} between two curved pieces is {length:.2f}: no deck run fits it"
                square = [n["Kind"] == "Corner" and n["R"] == 0 for n in (before, after)]
                assert not (any(curved) and any(square)) or length >= 56.25 - 1e-6, \
                    f"F9: hall {index} straight {i} from a standard corner to a curved piece is {length:.2f} (< 56.25)"
        # LATTICE_SPEC 4.7: the base cove from a tunnel's hole edge (cross +-18) to a swerve junction on the same
        # straight is nothing (0) or a 3-stud stop and an exact run (>= 3): a foot of 0..3 fits neither.
        for seg in loop:
            if seg["Kind"] != "S":
                continue
            sin = SWERVE_S_FAMILIES[(seg["R"], seg["Deg"])][0]
            ends = (seg["At"], seg["At"] + (1 if seg["Wall"] in ("North", "East") else -1) * 2 * seg["R"] * sin)
            for side, crosses in doors[index].items():
                if side != seg["Wall"]:
                    continue
                for cross in crosses:
                    for end in ends:
                        foot = abs(end - cross) - HOLE_HALF
                        assert not 1e-6 < foot < 3 - 1e-6, \
                            f"F9: hall {index} {side} door {cross}: a {foot:.3f} base-cove foot to the swerve fits no stop or run"
        # Curved fraction: the face-line share not at d=0, measured from the stored straights.
        perimeter = 2 * (h["Width"] + h["Depth"]) - 14
        flat = sum(abs(seg["To"] - seg["From"]) for seg in loop if seg["Kind"] == "Straight" and seg["Offset"] == 0)
        fraction = (perimeter - flat) / perimeter
        assert abs(fraction - h["Swerve"]["CurvedFraction"]) <= 1e-9, \
            f"F9: hall {index} CurvedFraction {h['Swerve']['CurvedFraction']} != measured {fraction}"
        arcs = [seg["R"] for seg in loop if seg["Kind"] == "Corner"]
        assert len(arcs) == 4 and fraction >= .30 and sum(r >= 32 for r in arcs) >= 2, \
            f"F9: hall {index} is not swervy enough (fraction {fraction:.2f}, corners {arcs})"
        # F9 review: the owner asked for the whole room to swerve; a rounded rectangle (four arcs, no wave) is not
        # one. Every swerve hall carries at least one S bulge (S-in, plateau, S-out) in its own walls.
        bends = sum(seg["Kind"] == "S" and seg["Piece"] == "In" for seg in loop)
        assert bends >= 1 and bends == sum(seg["Kind"] == "S" and seg["Piece"] == "Out" for seg in loop), \
            f"F9: hall {index} is a rounded rectangle with no S bulge (corners {arcs})"
        # G8 (F9 review): one S bulge per wall at most; each costs about 57 world descendants.
        for side in SWERVE_WALLS:
            per_wall = sum(seg["Kind"] == "S" and seg["Piece"] == "In" and seg["Wall"] == side for seg in loop)
            assert per_wall <= 1, f"F9: hall {index} {side} carries {per_wall} S bulges (one per wall, G8)"
        # Patrol nodes move onto the centre axes: inside the outline, 14 or more from the face.
        cx, cz = h["Center"]["X"], h["Center"]["Z"]
        for px, pz in ((cx - .32 * h["Width"], cz), (cx + .32 * h["Width"], cz),
                       (cx, cz - .32 * h["Depth"]), (cx, cz + .32 * h["Depth"])):
            clearance = min(math.hypot(px - x, pz - z) for x, z, *_ in samples)
            assert inside_polygon(polygon, px, pz) and clearance >= 14, \
                f"F9: hall {index} patrol node ({px:.1f}, {pz:.1f}) clearance {clearance:.2f}"
        if stats is not None:
            stats["fraction"].append(fraction)
            stats["arcs"].update(arcs)
            stats["families"].update((seg["R"], seg["Deg"]) for seg in loop if seg["Kind"] == "S" and seg["Piece"] == "In")
            stats["bends"][sum(seg["Kind"] == "S" and seg["Piece"] == "In" for seg in loop)] += 1
    if stats is not None:
        stats["perMap"][len(swerve)] += 1


def percentile(values, q):
    return sorted(values)[max(0, math.ceil(q * len(values)) - 1)]


def report(layouts, seeds):
    metrics = {
        "big halls": [len(l["Halls"]) - len(l["SmallRooms"]) for l in layouts],
        "small rooms": [len(l["SmallRooms"]) for l in layouts],
        "tunnels": [l["TunnelCount"] for l in layouts],
        "narrow passages": [l["NarrowCount"] for l in layouts],
        "attempts": [l["Attempt"] for l in layouts],
    }
    for name, values in metrics.items():
        print(f"{name}: min={min(values)} p10={percentile(values,.1)} "
              f"p50={percentile(values,.5)} p90={percentile(values,.9)} "
              f"p99={percentile(values,.99)} max={max(values)} mean={sum(values)/len(values):.2f}")
    print(f"small rooms per layout histogram: {dict(sorted(Counter(metrics['small rooms']).items()))}")
    for field in ("FloorY", "CeilingClass"):
        print(f"{field} histogram: {dict(sorted(Counter(h[field] for l in layouts for h in l['Halls']).items()))}")
    for field in ("Length", "Variant"):
        print(f"corridor {field}: {dict(sorted(Counter(c[field] for l in layouts for c in l['Corridors']).items()))}")
    prefabs = Counter(h["Prefab"] for l in layouts for h in l["Halls"] if h["Role"] == "Small")
    print(f"chamber prefabs: {dict(sorted(prefabs.items()))}")
    hall_types = Counter(h["Type"] for l in layouts for h in l["Halls"] if h["Role"] == "Hall")
    print(f"ordinary hall Type: {dict(sorted(hall_types.items()))}")
    print(f"ordinary hall Type share: {dict(sorted((name, f'{count/sum(hall_types.values()):.1%}') for name, count in hall_types.items()))}")
    clusters = sum(len({h["LeafIndex"] for h in l["Halls"] if h["Role"] == "Small"}) for l in layouts)
    leaves = sum(len({h["LeafIndex"] for h in l["Halls"]}) for l in layouts)
    print(f"cluster leaves: {clusters}/{leaves} = {clusters/leaves:.2%} (accepted-layout selection bias)")
    attempts = metrics["attempts"]
    print(f"acceptance: {len(layouts)}/{sum(attempts)} attempts = {len(layouts)/sum(attempts):.2%}; "
          f"fallbacks={sum(l['FallbackUsed'] for l in layouts)}; random recoveries="
          f"{sum('RandomRecoverySeed' in l for l in layouts)}; budget=300")
    worst = max(range(len(layouts)), key=lambda i: attempts[i])
    print(f"worst-case attempts: requested={seeds[worst]} resolved={layouts[worst]['Seed']} attempts={attempts[worst]}")
    assert percentile(attempts, .99) <= 300, "p99 exceeds the live attempt budget: retune only kit geometry constants"
    assert not any(l["FallbackUsed"] or "RandomRecoverySeed" in l for l in layouts), "stress layouts must come from primary seeds"
    # The owner's selected mix (30 / 19 / 39 / 33) stays random within these
    # central-80% bands; check actual accepted plans, not the requested budgets.
    for name, (low, high) in {
        "big halls": (27, 32), "small rooms": (15, 23),
        "narrow passages": (26, 40), "tunnels": (34, 44),
    }.items():
        p10, p90 = (percentile(metrics[name], q) for q in (.1, .9))
        assert low <= p10 <= p90 <= high, f"{name} p10/p90 {p10}/{p90} outside {low}..{high}"
    median = percentile(metrics["small rooms"], .5)
    assert 18 <= median <= 20, f"small-room median {median} must stay near 19"
    print("PASS owner-selected mix: all p10/p90 bands and small-room median")
    # Coverage guards: the stress run must actually exercise the optional geometry.
    assert set(prefabs) == set(PREFABS)
    assert set(hall_types) == set(HALL_TYPE_WEIGHTS)
    assert all(count >= 10 for count in hall_types.values()), "every weighted hall type must appear across 400 seeds"
    # Eligibility redraws make the accepted shares differ from raw weights:
    # most lattice rooms cannot reach CorridorHall's 2.2 aspect threshold.
    total_types = sum(hall_types.values())
    for name, (low, high) in {
        # Measured 2026-10-04 after the F8 spiral cap and the F4-I 160-stud vault minimum (VaultArcade fell
        # from 14.0 %: three quarters of its halls were under 160 and got no bay):
        # ColumnHall 45.2 / BigPool 11.8 / VaultArcade 3.6 / CurvedChannel 35.1 / SpiralWell 3.9 / CorridorHall 0.4 %.
        # WP8 (F9) replaces the ColumnHall/CurvedChannel bands: a CurvedChannel is now a swerve hall, 2..3 per
        # map (ineligible and surplus ones become ColumnHalls). Since the F9 review a swerve hall must also carry an
        # S bulge (only walls of 184+ hold one), one per wall, at most 3 halls: measured ColumnHall 66.7 /
        # CurvedChannel 13.6 % (1009 swerve halls, 2.52 per map); the others unchanged.
        "ColumnHall": (.58, .72), "BigPool": (.06, .14),
        "VaultArcade": (.025, .06), "CurvedChannel": (.11, .20),
        "SpiralWell": (.025, .06), "CorridorHall": (.001, .015),
    }.items():
        share = hall_types[name] / total_types
        assert low <= share <= high, f"{name} accepted share {share:.1%} outside {low:.1%}..{high:.1%}"
    # F8 (count): the cap must not lose the feature: most maps still have their one spiral well.
    with_spiral = sum(any(h["Type"] == "SpiralWell" for h in l["Halls"]) for l in layouts) / len(layouts)
    print(f"layouts with a SpiralWell: {with_spiral:.1%}")
    assert with_spiral >= .5, f"only {with_spiral:.1%} of layouts keep a spiral well"
    assert {-8, -4, 0, 4, 8} <= {h["FloorY"] for l in layouts for h in l["Halls"]}
    assert {"Stair4", "Stair8", "Wet", "Dry", "Flat"} == {c["Variant"] for l in layouts for c in l["Corridors"]}
    assert any(c["Kind"] == "Narrow" and l["Halls"][c["A"]-1]["Role"] != "Small"
               and l["Halls"][c["B"]-1]["Role"] != "Small" for l in layouts for c in l["Corridors"])


def mutation_check(binary):
    original = MODULE.read_bytes()
    marker = "if layout then return layout end"
    replacement = ('if layout then\n'
                   '\t\tfor _, c in ipairs(layout.Corridors) do\n'
                   '\t\t\tif c.Kind ~= "Narrow" then c.Length = 68 break end\n'
                   '\t\tend\n\t\treturn layout\n\tend')
    try:
        text = original.decode("utf-8")
        assert marker in text
        MODULE.write_text(text.replace(marker, replacement, 1), encoding="utf-8")
        # The mutated result is checked independently. Skip the module's own
        # post-return Validate here so this proves the Python oracle catches it.
        patched = PRELUDE.replace('assert(ok, tostring(reason))', '-- mutation bypasses the internal validator')
        script = patched.replace("__CONFIG__", CONFIG.read_text(encoding="utf-8"))
        script = script.replace("__MODULE__", MODULE.read_text(encoding="utf-8"))
        script = script.replace("__RUN__", 'emit(1, nil, "MUTANT")')
        with tempfile.TemporaryDirectory(prefix="level2-kit-mutant-") as directory:
            fixture = Path(directory) / "mutant.luau"
            fixture.write_text(script, encoding="utf-8")
            result = subprocess.run([binary, str(fixture)], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, result.stderr
        mutant = json.loads(result.stdout.split(" ", 1)[1])
        try:
            validate(mutant, 1)
        except AssertionError as error:
            assert "Length must equal" in str(error), f"mutation failed for an unexpected reason: {error}"
            print(f"PASS mutation: tunnel Length=68 produced expected FAIL ({error})")
        else:
            raise AssertionError("mutation survived the independent contract test")
    finally:
        MODULE.write_bytes(original)
        assert MODULE.read_bytes() == original
    print("PASS mutation restored byte-for-byte")


def spiral_cap_mutation(binary, seeds):
    """F8 (count): with the cap raised to 2 (in memory only, the module's own Validate bypassed) the
    independent per-layout rule must reject some layout."""
    source = MODULE.read_text(encoding="utf-8")
    marker = "local MAX_SPIRAL_WELLS, SPIRAL_MIN_SIDE = 1, 128"
    assert marker in source
    prelude = PRELUDE.replace('assert(ok, tostring(reason))', '-- mutation bypasses the internal validator')
    mutants = run_layouts(binary, seeds, source=source.replace(marker, "local MAX_SPIRAL_WELLS, SPIRAL_MIN_SIDE = 2, 128"),
                          prelude=prelude)
    for seed, (_, layout) in zip(seeds, mutants):
        try:
            validate(layout, seed)
        except AssertionError as error:
            assert "more than one SpiralWell hall" in str(error), f"spiral cap mutation failed for the wrong reason: {error}"
            print(f"PASS mutation: MAX_SPIRAL_WELLS=2 rejected (seed {seed})")
            return
    raise AssertionError("MAX_SPIRAL_WELLS=2 survived the per-layout spiral rule")


def vault_size_mutation(binary, seeds):
    """F4-I: with the vault minimum lowered to the old 96 (in memory only, the module's own Validate bypassed)
    the independent rule must reject an undersized VaultArcade."""
    source = MODULE.read_text(encoding="utf-8")
    marker = "local VAULT_MIN_SIDE = 160"
    assert marker in source
    prelude = PRELUDE.replace('assert(ok, tostring(reason))', '-- mutation bypasses the internal validator')
    mutants = run_layouts(binary, seeds, source=source.replace(marker, "local VAULT_MIN_SIDE = 96"), prelude=prelude)
    for seed, (_, layout) in zip(seeds, mutants):
        try:
            validate(layout, seed)
        except AssertionError as error:
            assert "below the 160-stud vault minimum" in str(error), f"vault size mutation failed for the wrong reason: {error}"
            print(f"PASS mutation: VAULT_MIN_SIDE=96 rejected (seed {seed})")
            return
    raise AssertionError("VAULT_MIN_SIDE=96 survived the per-hall vault rule")


def swerve_mutations(binary, seeds):
    """F9: each planner rule, broken in memory (the module's own Validate bypassed), must be rejected by the
    independent outline oracle for the reason it guards."""
    source = MODULE.read_text(encoding="utf-8")
    prelude = PRELUDE.replace('assert(ok, tostring(reason))', '-- mutation bypasses the internal validator')
    for edits, expect, label in (
            # LATTICE_SPEC 2.5: corner arcs without their .25 tails put every joint beside them off the integers.
            ([("local SWERVE_TAIL = .25\n", "local SWERVE_TAIL = 0\n"),
              ('\t\t\tassert(face or math.abs(v - math.floor(v + .5)) < 1e-6, "[Level 2 Kit] swerve joint off the integer lattice: " .. v)\n',
               "\t\t\tlocal _ = v -- mutation bypasses the planner's own assert\n")],
             "off the integer lattice", "corner arcs without their .25 tails (joints off the integer lattice)"),
            # A planner that keeps the centre axes +-12 instead of the contract's +-17 crowds the real lanes.
            ([("local rects = {{cx - 17, cx + 17, hall.MinZ, hall.MaxZ}, {hall.MinX, hall.MaxX, cz - 17, cz + 17}}",
               "local rects = {{cx - 12, cx + 12, hall.MinZ, hall.MaxZ}, {hall.MinX, hall.MaxX, cz - 12, cz + 12}}")],
             "within 3 of lane", "centre lanes planned +-12 instead of +-17 (arcs and bulges crowd the lanes)"),
            # F9 review: without the bend rule 58% of swerve halls were rounded rectangles (four arcs, no wave).
            ([("local SWERVE_MIN_BENDS = 1\n", "local SWERVE_MIN_BENDS = 0\n")],
             "rounded rectangle with no S bulge", "swerve halls without an S bulge"),
            ([("local SWERVE_WALL_BENDS = 1\n", "local SWERVE_WALL_BENDS = 2\n")],
             "S bulges (one per wall, G8)", "two S bulges on one wall (the instance budget)")):
        mutant = source
        for marker, replacement in edits:
            assert source.count(marker) == 1, marker
            mutant = mutant.replace(marker, replacement)
        mutants = run_layouts(binary, seeds, source=mutant, prelude=prelude)
        for seed, (_, layout) in zip(seeds, mutants):
            try:
                validate(layout, seed)
            except AssertionError as error:
                assert expect in str(error), f"{label} mutation failed for the wrong reason: {error}"
                print(f"PASS mutation: {label} rejected (seed {seed})")
                break
        else:
            raise AssertionError(f"{label} survived the swerve outline oracle")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seeds", type=int, default=400)
    parser.add_argument("--mutation-check", action="store_true")
    args = parser.parse_args()
    assert args.seeds > 0
    binary = os.environ.get("LUAU_BIN") or shutil.which("luau") or DEFAULT_BIN
    protected = {p: hashlib.sha256(p.read_bytes()).hexdigest() for p in (LIVE, CONFIG)}
    marker = "local function normalizeSeed"
    assert MODULE.read_text(encoding="utf-8").split(marker)[1] == LIVE.read_text(encoding="utf-8").split(marker)[1]
    print("PASS seed/retry/recovery/fallback implementation unchanged from live")
    compile_module(binary)
    seeds = [1, 101, 1182081016, 738163940][:args.seeds]
    seeds += [(i * 15485863 + 20261003) % 2147483647 for i in range(args.seeds - len(seeds))]
    layouts = [l for _, l in run_layouts(binary, seeds)]
    assert len(layouts) == args.seeds
    swerve_stats = {"fraction": [], "arcs": Counter(), "families": Counter(), "perMap": Counter(), "bends": Counter()}
    for seed, layout in zip(seeds, layouts):
        try:
            validate(layout, seed, swerve_stats=swerve_stats)
        except AssertionError as error:
            raise AssertionError(f"requested seed {seed}, attempt {layout['Attempt']}: {error}") from error
    print(f"PASS independent geometry/roles/heights/graphs: {len(layouts)} seeds")
    fractions = swerve_stats["fraction"]
    print(f"PASS F9 swerve outlines (independent turtle oracle): swerve halls per map "
          f"{dict(sorted(swerve_stats['perMap'].items()))}; curved fraction p10/p50/p90 "
          f"{percentile(fractions, .1):.2f}/{percentile(fractions, .5):.2f}/{percentile(fractions, .9):.2f} "
          f"(ANALYSIS prototype .37/.49/.60); corner radii {dict(sorted(swerve_stats['arcs'].items()))}; "
          f"S bends (R, deg) {dict(sorted(swerve_stats['families'].items()))}; "
          f"halls by S-bend count {dict(sorted(swerve_stats['bends'].items()))}")
    spiral_cap_mutation(binary, seeds[:60])
    vault_size_mutation(binary, seeds[:60])
    swerve_mutations(binary, seeds[:60])
    if args.seeds >= 400:
        report(layouts, seeds)
    else:
        print(f"probe attempts: {[l['Attempt'] for l in layouts]}")
    repeats = [l for _, l in run_layouts(binary, seeds[:3])]
    assert repeats == layouts[:3], "requested seeds must reproduce the entire layout"
    resolved = [l for _, l in run_layouts(binary, [layouts[0]["Seed"]])][0]
    for key in ("Halls", "Corridors", "SmallRooms", "Distances"):
        assert resolved[key] == layouts[0][key], "resolved seed must reproduce geometry and roles"
    assert resolved["Attempt"] == 1
    print("PASS deterministic requested/resolved seed replay (offline stub only; Roblox Random uses a different sequence)")
    # Use config edits only inside the temporary fixture to exercise inherited
    # fallback/recovery paths; the existing configuration file is never written.
    special = r'''
emit(-3.75, nil, "NORMALIZED")
emit("bad seed", nil, "CLOCK")
 local baseline = Generator.Generate(101)
 local savedExtent = Configuration.ComplexExtent
 for _,extent in ipairs({1200,1600}) do
     Configuration.ComplexExtent=extent
     emit(101,nil,"EXTENT")
 end
 Configuration.ComplexExtent=savedExtent
local savedAttempts = Configuration.GenerationAttempts
Configuration.GenerationAttempts = 1
Configuration.GenerationFallbackSeeds = {baseline.Seed}
local rejectingSeed
for s = 1, 1000 do
    local candidate = Generator.Generate(s)
    if candidate.FallbackUsed then rejectingSeed = s break end
end
assert(rejectingSeed, "fixture needs one rejected first attempt")
emit(rejectingSeed, nil, "FALLBACK")
local entropy = Random.new():NextInteger(0,2147483646)
DateTime.now = function() return {UnixTimestampMillis=baseline.Seed-entropy} end
emit(rejectingSeed, {AllowRandomRecovery=true}, "RECOVERY")
Configuration.GenerationFallbackSeeds = {}
local ok, reason = pcall(Generator.Generate, rejectingSeed)
assert(not ok and string.find(reason,"after 1 validated attempts"), "exhaustion must preserve the bounded error path")
Configuration.GenerationAttempts = savedAttempts
Configuration.DeepEndMax = 1.8
emit(1, nil, "DEPTH")
'''
    extras = run_layouts(binary, [], special)
    for label, layout in extras:
        validate(layout, deep_max=1.8 if label == "DEPTH" else 2.0)
        if label == "EXTENT":
            assert layout["Bounds"]["MaxX"]-layout["Bounds"]["MinX"] == 1400, \
                "kit extent must remain on its authored lattice for other Master extents"
        if label == "FALLBACK":
            assert layout["FallbackUsed"] and layout["FallbackBaseSeed"] == layout["Seed"]
            assert layout["Attempt"] == 2 and layout["AttemptWithinSequence"] == 1
        if label == "RECOVERY":
            assert not layout["FallbackUsed"] and layout["RandomRecoverySeed"] == layout["Seed"]
            assert layout["Attempt"] == 2 and layout["AttemptWithinSequence"] == 1
    print("PASS normalization/clock/fallback/random recovery/exhaustion/configured depth")
    if args.mutation_check:
        mutation_check(binary)
        compile_module(binary)
    assert all(hashlib.sha256(p.read_bytes()).hexdigest() == digest for p, digest in protected.items())
    print("PASS existing live generator and configuration unchanged")
    print("PASS Level 2 kit offline suite; Studio gameplay/performance are unverified")


if __name__ == "__main__":
    main()
