from pathlib import Path
import subprocess

folder = Path(__file__).resolve().parent
root = folder.parents[2]
binary = root / "output/level5-build/tools/luau/luau"
generated = folder / "mock.generated.luau"
generated.write_text("\n".join((folder / name).read_text() for name in (
    "mock_prefix.luau", "styleLevelFiveRoom.luau", "mock_suffix.luau"
)))
result = subprocess.run([str(binary), str(generated)], text=True, capture_output=True)
(folder / "geometry-checks.txt").write_text(result.stdout + result.stderr)
print(result.stdout + result.stderr, end="")
raise SystemExit(result.returncode)
