"""Decode an actual MCP screen capture, without altering its pixels."""
from pathlib import Path
import argparse,base64,hashlib,json
p=argparse.ArgumentParser();p.add_argument('source',type=Path);p.add_argument('destination',type=Path)
a=p.parse_args();raw=base64.b64decode(a.source.read_text().strip(),validate=True)
assert raw[:8]==b'\x89PNG\r\n\x1a\n' or raw[:3]==b'\xff\xd8\xff', 'Expected actual PNG or JPEG capture'
a.destination.parent.mkdir(parents=True,exist_ok=True)
assert not a.destination.exists(),'Capture paths are immutable'
a.destination.write_bytes(raw)
print(json.dumps(dict(path=str(a.destination),bytes=len(raw),sha256=hashlib.sha256(raw).hexdigest(),pixelEditing=False)))
