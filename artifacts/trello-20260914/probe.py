"""Queue one Studio test command from a local Luau file, or read a result."""
from pathlib import Path
import json
import sys
ROOT = Path(__file__).parent / 'multiplayer-results'
if len(sys.argv) > 2:
    code = Path(sys.argv[2]).read_text(encoding='utf-8')
    pending = ROOT / 'pending.json'
    assert not pending.exists(), 'previous command has not been consumed'
    pending.write_text(json.dumps({'id':sys.argv[1], 'code':code}), encoding='utf-8')
    print('Queued ' + sys.argv[1])
else:
    path = ROOT / (sys.argv[1] + '.json')
    print(path.read_text(encoding='utf-8') if path.exists() else 'Pending')
