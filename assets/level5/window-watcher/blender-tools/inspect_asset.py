"""blender --background --factory-startup --python inspect_asset.py -- input output.json"""
import sys
from pathlib import Path
sys.path.insert(0, str(Path(__file__).resolve().parent))
from watcher_common import import_asset, inventory, write_json

args = sys.argv[sys.argv.index("--") + 1:]
if len(args) != 2:
    raise SystemExit("Expected source asset and output JSON")
source = import_asset(args[0])
result = inventory()
result["source"] = str(source)
write_json(args[1], result)
print("WATCHER_INVENTORY=" + str(Path(args[1]).resolve()))
