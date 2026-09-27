from pathlib import Path
import os
import shutil
import subprocess
import sys

task = Path(__file__).resolve().parents[1]
local_runtime = task.parents[1] / "output/level5-build/tools/luau/luau"
runtime = (sys.argv[1] if len(sys.argv) > 1 else os.environ.get("LUAU_BIN")
           or shutil.which("luau") or (str(local_runtime) if local_runtime.is_file() else None))
if not runtime:
    raise SystemExit("Pass the Luau executable path as the first argument or set LUAU_BIN.")
tests = task / "tests"
controller = task / "patches/Level5SoundController.LocalScript.lua"
generated = tests / "test_controller.generated.luau"
generated.write_text(
    (tests / "controller_mock_prefix.luau").read_text()
    + "\n-- BEGIN ACTUAL CONTROLLER SOURCE\ndo\n"
    + controller.read_text()
    + "\nend\n-- END ACTUAL CONTROLLER SOURCE\n"
    + (tests / "controller_mock_suffix.luau").read_text()
)
subprocess.run(
    [runtime, str(generated)],
    check=True,
)
