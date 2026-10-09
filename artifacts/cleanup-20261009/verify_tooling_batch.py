"""Offline negative/safety gates for the 2026-10-09 tooling cleanup.

All mutants and historical authoring inputs stay in OS temporary directories.
No Studio/network operation or original source mutation is performed.
"""

from pathlib import Path
import hashlib
import importlib.util
import os
import subprocess
import sys
import tempfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[2]
TOOLS = ROOT / "tools"
LUAU = Path(os.environ.get("LUAU_BIN") or Path(os.environ["TEMP"]) / "codex-luau-0.737/luau.exe")
HISTORY = "46073662^"


def load_test(name):
    path = TOOLS / "tests" / f"{name}.py"
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def execute_module(module):
    try:
        module.main()
    except SystemExit as result:
        return result.code or 0
    return 0


def historic(path):
    result = subprocess.run(["git", "show", f"{HISTORY}:{path}"], cwd=ROOT,
                            capture_output=True, check=True)
    return result.stdout


def receipt_negative():
    module = load_test("test_support_product_receipts")
    marker = "if id == purchaseId then\n\t\t\t\talreadyGranted = true"
    assert module.SERVER.count(marker) == 1, "receipt dedupe mutation boundary changed"
    module.SERVER = module.SERVER.replace(marker, "if false then\n\t\t\t\talreadyGranted = true", 1)
    # The real test asserts token/support balances on receipt replay. Only the
    # in-memory copy of the production handler has its dedupe guard disabled.
    assert execute_module(module) != 0, "duplicate-grant mutant escaped the receipt oracle"
    print("PASS negative receipt: duplicate-grant handler fails the balance oracle")


def inventory_negative():
    module = load_test("test_item_inventory")
    marker = "data.Items[itemKey] -= amount"
    assert module.SERVER.count(marker) == 1, "inventory mutation boundary changed"
    module.SERVER = module.SERVER.replace(marker, "data.Items[itemKey] -= 0", 1)
    assert execute_module(module) != 0, "unpaid inventory effect escaped the inventory oracle"
    print("PASS negative inventory: no-debit handler fails the durable balance oracle")


def inventory_unknown_commit():
    """Record CORE-004's uncertain-commit scenario without claiming it is fixed."""
    module = load_test("test_item_inventory")
    marker = "if result then w.db[key] = clone(result); w.writes += 1 end\n        return clone(result)"
    assert module.WORLD.count(marker) == 1, "fake inventory store commit boundary changed"
    module.WORLD = module.WORLD.replace(marker,
        'if result then w.db[key] = clone(result); w.writes += 1 end\n'
        '        if w.failAfter then w.failAfter = false; error("Committed; response lost") end\n'
        '        return clone(result)', 1)
    marker = 'print(string.format("item inventory: %d checks passed", checks))'
    assert module.TESTS.count(marker) == 1
    module.TESTS = module.TESTS.replace(marker, r'''
do
    local w = fresh()
    w.buy(w.player, {Key = "RouteMarker"})
    w.failAfter = true
    local first = w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 1)
    eq(first, false, "lost response reports no accepted effect")
    eq(w:saved().Items.RouteMarker, 2, "lost response can already have spent one marker")
    local retry = w.inventory.OnInvoke("Consume", w.player, "RouteMarker", 1)
    eq(retry, true, "a fresh retry can spend another marker")
    eq(w:saved().Items.RouteMarker, 1, "unkeyed retry consumes twice across unknown commit")
end
print("REPRODUCED CORE-004: unknown commit can spend an item without acknowledged effect; fresh retry spends again")
''', 1)
    assert execute_module(module) == 0, "uncertain-commit fixture did not reproduce the documented scenario"
    print("CORE-004 remains pending: this fixture is failure evidence, not a gameplay/economy pass")


def mutation_safety():
    module = load_test("test_level2_kit_layout")
    with tempfile.TemporaryDirectory(prefix="mongotv-retired-layout-fixture-") as directory:
        base = Path(directory)
        module.MODULE = base / "archived-layout.lua"
        module.CONFIG = base / "archived-config.lua"
        module.MODULE.write_bytes(historic("ServerScriptService/Level 2 Systems/Level 2 Kit Layout Generator.ModuleScript.lua"))
        module.CONFIG.write_bytes(historic("ServerScriptService/Level 2 Systems/Level 2 Configuration.ModuleScript.lua"))
        # This archived planner predates today's additional vault/swerve oracle
        # rules. Keep the production full validator unchanged; this fixture
        # tests only the independent geometric rule this mutation violates.
        # Full legacy authoring-suite coverage is explicitly still pending.
        def corridor_gap_oracle(layout, _seed):
            assert layout["Corridors"], "historical fixture has no corridors"
            for corridor in layout["Corridors"]:
                assert corridor["Length"] == corridor["To"] - corridor["From"] > 0, \
                    "corridor Length must equal the exact wall gap"

        for _, layout in module.run_layouts(str(LUAU), [1]):
            corridor_gap_oracle(layout, 1)
        module.validate = corridor_gap_oracle
        protected = {module.MODULE: module.MODULE.read_bytes(), module.CONFIG: module.CONFIG.read_bytes()}
        write_text, write_bytes = Path.write_text, Path.write_bytes

        def guarded_text(path, *args, **kwargs):
            assert path not in protected, "mutation attempted to write an authoring source"
            return write_text(path, *args, **kwargs)

        def guarded_bytes(path, *args, **kwargs):
            assert path not in protected, "mutation attempted to restore/overwrite an authoring source"
            return write_bytes(path, *args, **kwargs)

        with patch.object(Path, "write_text", guarded_text), patch.object(Path, "write_bytes", guarded_bytes):
            module.mutation_check(str(LUAU))
            # Run a real child interpreter, interrupt it while the disposable
            # runner exists, and let the helper's original error path unwind.
            def interrupted_run(args, **kwargs):
                fixture = Path(args[1])
                assert fixture.is_file() and "Length = 68" in fixture.read_text(encoding="utf-8")
                assert all(path.read_bytes() == data for path, data in protected.items())
                child = subprocess.Popen(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                child.terminate()
                child.communicate(timeout=10)
                raise subprocess.TimeoutExpired(args, kwargs.get("timeout", 60))

            with patch.object(module.subprocess, "run", interrupted_run):
                try:
                    module.mutation_check(str(LUAU))
                except subprocess.TimeoutExpired:
                    pass
                else:
                    raise AssertionError("interruption fixture did not interrupt")
        assert all(path.read_bytes() == data for path, data in protected.items())
    print("PASS mutation safety: source writes rejected; interrupted real Luau child leaves originals untouched")


def main():
    assert LUAU.is_file()
    os.environ["LUAU_BIN"] = str(LUAU)
    protected = [ROOT / "ServerScriptService/ZyntraMonetization.Script.lua",
                 ROOT / "ReplicatedStorage/ZyntraSkins.ModuleScript.lua",
                 ROOT / "ReplicatedStorage/DevAccess.ModuleScript.lua"]
    before = {path: hashlib.sha256(path.read_bytes()).hexdigest() for path in protected}
    receipt_negative()
    inventory_negative()
    inventory_unknown_commit()
    mutation_safety()
    assert all(hashlib.sha256(path.read_bytes()).hexdigest() == digest for path, digest in before.items())
    print("PASS authoritative runtime sources unchanged by all negative/safety fixtures")


if __name__ == "__main__":
    main()
