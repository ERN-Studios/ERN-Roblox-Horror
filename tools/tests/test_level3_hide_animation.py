"""Level 3 under-table hiding places the ROOT, not the model pivot (Trello #80).

The gameplay rig is authored with its pivot on the floor, 3.49 studs under the
HumanoidRootPart (measured in Studio 2026-09-15, PlaceVersion 1894), so the old
`character:PivotTo(hiddenCFrame)` parked the whole crouched body ON the tabletop
while the hide camera sat under it, and the exit dropped the player 3.2 studs.

This runs the REAL `pivotRootTo` helper out of the Hiding Controller against a
fake model whose pivot is offset exactly like the shipped rig, and checks that
both placement call sites route through it. Fails on the pre-fix source (no
helper, bare PivotTo). No Studio, no network. Set LUAU_BIN to the official Luau
interpreter.
"""

from pathlib import Path
import os
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
CONTROLLER = ROOT / "ServerScriptService/Level 3 Systems/Level 3 Hiding Controller.ModuleScript.lua"
CONFIG = ROOT / "ServerScriptService/Level 3 Systems/Level 3 Configuration.ModuleScript.lua"
SOURCE = CONTROLLER.read_text(encoding="utf-8")


def func(name):
    marker = "local function " + name + "("
    assert marker in SOURCE, f"{name} is not defined in the Hiding Controller"
    start = SOURCE.index(marker)
    end = re.search(r"\n(?:local function |function Controller)", SOURCE[start + 1:])
    assert end, name
    return SOURCE[start:start + 1 + end.start()]


def source_contract():
    """The two placements that must land the root, and the tuning they read."""
    helper = func("pivotRootTo")
    assert SOURCE.replace(helper, "").count("character:PivotTo(") == 0, (
        "a bare character:PivotTo moves the model's authored pivot (the rig's feet), "
        "not the HumanoidRootPart -- route it through pivotRootTo"
    )
    assert "pivotRootTo(character, root, hiddenCFrame)" in SOURCE, "tryEnter must place the root"
    assert "pivotRootTo(character, root, record.ExitCFrame)" in SOURCE, "releasePlayer must place the root"
    assert SOURCE.index("local function pivotRootTo(") < SOURCE.index("local function releasePlayer("), (
        "pivotRootTo must be defined before its first caller"
    )
    # The corrected placement is measured against these; a silent change here
    # re-breaks it (the anchor part itself is built at HiddenRootHeight).
    config = CONFIG.read_text(encoding="utf-8")
    for key, value in (
        ("HiddenRootHeight", "2.2"),
        ("ExitVerticalOffset", "1.0"),
        ("HideOccupantCap", "2"),
        ("HideOccupantLateralOffset", "2.0"),
    ):
        assert re.search(rf"\b{key}\s*=\s*{re.escape(value)}\b", config), f"Hiding.{key} is no longer {value}"


PRELUDE = r'''
local checks = 0
local function check(ok, why) checks += 1; assert(ok, why) end

-- Minimal position + yaw CFrame: the authored rig pivot is a pure translation
-- and hide anchors are yawed, which is exactly what the helper has to survive.
local CF = {}
CF.__index = CF
local function cf(x, y, z, yaw) return setmetatable({X = x, Y = y, Z = z, Yaw = yaw or 0}, CF) end
local function rot(yaw, x, z)
    local c, s = math.cos(yaw), math.sin(yaw)
    return c * x + s * z, -s * x + c * z
end
CF.__mul = function(a, b)
    local x, z = rot(a.Yaw, b.X, b.Z)
    return cf(a.X + x, a.Y + b.Y, a.Z + z, a.Yaw + b.Yaw)
end
function CF:Inverse()
    local x, z = rot(-self.Yaw, -self.X, -self.Z)
    return cf(x, -self.Y, z, -self.Yaw)
end
function CF:ToObjectSpace(other) return self:Inverse() * other end
local CFrame = {}
function CFrame.new(x, y, z) return cf(x or 0, y or 0, z or 0, 0) end
function CFrame.Angles(_, yaw, _) return cf(0, 0, 0, yaw) end

local function same(a, b, why)
    local dyaw = (a.Yaw - b.Yaw) % (math.pi * 2)
    dyaw = math.min(dyaw, math.pi * 2 - dyaw)
    check(math.abs(a.X - b.X) < 1e-6 and math.abs(a.Y - b.Y) < 1e-6
        and math.abs(a.Z - b.Z) < 1e-6 and dyaw < 1e-6, why)
end

-- Model:PivotTo moves WorldPivot; parts keep their rigid offset from it.
local Model = {}
Model.__index = Model
local function rig(rootCFrame, pivotOffset)
    return setmetatable({Root = {CFrame = rootCFrame}, Offset = pivotOffset}, Model)
end
function Model:GetPivot() return self.Root.CFrame * self.Offset end
function Model:PivotTo(target) self.Root.CFrame = target * self.Offset:Inverse() end

-- The shipped hazmat rig, measured in Studio: pivot 3.49 studs under the root.
local RIG_PIVOT = CFrame.new(0, -3.49, 0)

-- ACTUAL_SOURCE

-- 1. The bug the fix exists for: a raw PivotTo leaves the root 3.49 too high.
local naive = rig(CFrame.new(0, 100, 0), RIG_PIVOT)
local anchor = CFrame.new(10, 26.2, -80)
naive:PivotTo(anchor)
check(math.abs(naive.Root.CFrame.Y - (anchor.Y + 3.49)) < 1e-6,
    "fake rig must reproduce the engine behaviour the bug depended on")

-- 2. The helper lands the HumanoidRootPart exactly on the hide anchor.
local model = rig(CFrame.new(0, 100, 0), RIG_PIVOT)
pivotRootTo(model, model.Root, anchor)
same(model.Root.CFrame, anchor, "hidden placement puts the root on the anchor (HiddenRootHeight)")

-- 3. Still exact through a yawed anchor with a lane offset and a facing flip --
--    the correction must be applied in ROOT space, not in world Y.
local yawed = CFrame.new(10, 26.2, -80) * CFrame.Angles(0, 0.9, 0)
local lane = yawed * CFrame.new(2.0, 0, 0) * CFrame.Angles(0, math.pi, 0)
model = rig(CFrame.new(-40, 3, 12) * CFrame.Angles(0, -2.2, 0), RIG_PIVOT)
pivotRootTo(model, model.Root, lane)
same(model.Root.CFrame, lane, "slot 2 lane placement is exact through anchor yaw and the facing flip")

-- 4. The exit lane: root on the exit CFrame, so ExitVerticalOffset is clearance
--    above the anchor rather than a 3-stud fall.
local exitCFrame = yawed * CFrame.new(-2.0, 1.0, 5.8)
pivotRootTo(model, model.Root, exitCFrame)
same(model.Root.CFrame, exitCFrame, "exit places the root on ExitVerticalOffset")

-- 5. A rig whose pivot already is the root is unaffected.
local plain = rig(CFrame.new(0, 0, 0), CFrame.new(0, 0, 0))
pivotRootTo(plain, plain.Root, anchor)
same(plain.Root.CFrame, anchor, "a rig pivoted on its root is unchanged by the helper")

print(string.format("level 3 hide placement: %d checks passed (actual pivotRootTo; fake rig)", checks))
'''


def main():
    source_contract()
    luau = os.environ.get("LUAU_BIN") or shutil.which("luau")
    if not luau:
        raise SystemExit("Set LUAU_BIN or put luau on PATH")
    source = PRELUDE.replace("-- ACTUAL_SOURCE", func("pivotRootTo"))
    with tempfile.TemporaryDirectory(prefix="hide-placement-") as directory:
        path = Path(directory) / "hide_placement.luau"
        path.write_text(source, encoding="utf-8")
        result = subprocess.run([luau, str(path)], capture_output=True, text=True, timeout=60)
    if result.stdout:
        print(result.stdout, end="")
    if result.stderr:
        print(result.stderr, end="")
    raise SystemExit(result.returncode)


if __name__ == "__main__":
    main()
