"""Repeat the actual ownership/compile preflight against immutable V2 only."""
from pathlib import Path
source = Path(__file__).with_name("verify-prepared.py").read_text(encoding="utf-8")
assert source.count('source_path = OUT / "restoration-supplement-probe.luau"') == 1
assert source.count('target = OUT / "offline-preflight.json"') == 1
source = source.replace('source_path = OUT / "restoration-supplement-probe.luau"', 'source_path = OUT / "restoration-supplement-probe-v2.luau"')
source = source.replace('target = OUT / "offline-preflight.json"', 'target = OUT / "offline-preflight-v2.json"')
source = source.replace('"schema": "s06-exact-supplement-offline-preflight-v1"', '"schema": "s06-exact-supplement-offline-preflight-v2"')
exec(compile(source, str(Path(__file__).with_name("verify-prepared.py")), "exec"), {"__file__": __file__, "__name__": "__main__"})
