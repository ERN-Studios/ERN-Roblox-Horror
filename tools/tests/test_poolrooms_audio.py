"""Execute the actual Poolrooms LocalScript in a bounded offline Luau mock.

Requires the official Luau interpreter and compiler in PATH or --luau-dir.
This checks lifecycle behavior; it cannot establish audible quality or engine performance.
"""
import argparse
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument("--luau-dir", type=Path)
args = parser.parse_args()

def binary(name):
    path = str(args.luau_dir / name) if args.luau_dir else shutil.which(name)
    if not path:
        raise SystemExit(f"Install the official Luau tools or specify --luau-dir ({name} missing)")
    return path

source = ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Poolrooms Ambience.LocalScript.lua"
legacy = ROOT / "StarterPlayer/StarterPlayerScripts/Level 2 Sound Controller.LocalScript.lua"
for path in (source, legacy):
    subprocess.run([binary("luau-compile"), str(path)], check=True, stdout=subprocess.DEVNULL)

harness = (ROOT / "tools/tests/poolrooms_audio_mock.luau").read_text()
assert harness.count("\n__RUN_CONTROLLER__\n") == 1
harness = harness.replace("\n__RUN_CONTROLLER__\n", "\n" + source.read_text() + "\n")
with tempfile.TemporaryDirectory(prefix="poolrooms-audio-test-") as folder:
    path = Path(folder) / "poolrooms_audio_mock.luau"
    path.write_text(harness)
    subprocess.run([binary("luau"), str(path)], check=True, timeout=30)
