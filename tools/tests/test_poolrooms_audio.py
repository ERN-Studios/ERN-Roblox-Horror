"""Execute the actual Poolrooms LocalScript in a bounded offline Luau mock.

Requires the official Luau interpreter and compiler in PATH or --luau-dir.
This checks lifecycle behavior; it cannot establish audible quality or engine performance.
"""
import argparse
import json
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
# AUDIO_SECTIONS_20261010: use the live v2 JSON and unchanged input client as a deterministic reference.
def luau(value):
    if value is None:
        return "nil"
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, list):
        return "{" + ",".join(luau(item) for item in value) + "}"
    return "{" + ",".join("[" + luau(key) + "]=" + luau(item) for key, item in value.items()) + "}"

V3 = ROOT / "assets/poolrooms-audio-20261010/plan.json"   # the plan that ships; absent in a checkout without the pack
original = ROOT / "tools/tests/fixtures/poolrooms_ambience_v2_client.lua"   # the client as it was live with plan v2 (2026-10-09)
for marker, content in {
    "\n__RUN_CONTROLLER__\n": "\n" + source.read_text() + "\n",
    "\n__BASELINE_CONTROLLER__\n": "\n" + original.read_text() + "\n",
    "__V2_PLAN__": luau(json.loads((ROOT / "assets/poolrooms-audio-20261009/plan.json").read_text())),
    "__V3_PLAN__": luau(json.loads(V3.read_text())) if V3.exists() else "nil",
}.items():
    assert harness.count(marker) == 1, marker
    harness = harness.replace(marker, content)
# Keep all transient files inside the user's workspace.
with tempfile.TemporaryDirectory(prefix="poolrooms-audio-test-", dir=ROOT / "tools/tests") as folder:
    path = Path(folder) / "poolrooms_audio_mock.luau"
    path.write_text(harness)
    subprocess.run([binary("luau"), str(path)], check=True, timeout=30)
