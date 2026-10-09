"""Compile exact mirror/native snapshots without executing gameplay code."""
import ast
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

ROOT=Path(__file__).resolve().parents[2]
BIN=Path(os.environ.get("LUAU_COMPILE_BIN",str(Path(os.environ["TEMP"])/"codex-luau-0.737"/"luau-compile.exe")))
label=sys.argv[1] if len(sys.argv)>1 else "baseline"
manifest=json.loads((ROOT/"studio-sync-manifest.json").read_text(encoding="utf-8"))
native=json.loads((ROOT/".git"/"mongotv-cleanup-20261009"/f"{label}-native.json").read_text(encoding="utf-8"))
results={"compiler":str(BIN),"mirror":[],"native":[],"python":[]}
for item in manifest["items"]:
 if item["className"] not in {"Script","LocalScript","ModuleScript"}: continue
 r=subprocess.run([str(BIN),"--null",str(ROOT/item["file"])],capture_output=True)
 results["mirror"].append({"file":item["file"],"pass":r.returncode==0,"error":r.stderr.decode("utf-8",errors="replace")})
with tempfile.TemporaryDirectory(prefix="mongotv-native-compile-") as temp:
 for i,item in enumerate(native["items"]):
  if "source" not in item: continue
  path=Path(temp)/f"native{i}.luau"; path.write_text(item["source"],encoding="utf-8")
  r=subprocess.run([str(BIN),"--null",str(path)],capture_output=True)
  results["native"].append({"path":item["studioPath"],"pass":r.returncode==0,"error":r.stderr.decode("utf-8",errors="replace")})
for path in (ROOT/"tools").rglob("*.py"):
 try: ast.parse(path.read_text(encoding="utf-8-sig")); error=""
 except (SyntaxError,UnicodeError) as exc: error=str(exc)
 results["python"].append({"file":path.relative_to(ROOT).as_posix(),"pass":not error,"error":error})
out=ROOT/"artifacts"/"cleanup-20261009"/f"{label}-compile.json"
out.write_text(json.dumps(results,indent=2)+"\n",encoding="utf-8")
print(json.dumps({kind:{"pass":sum(r["pass"] for r in rows),"total":len(rows),"failures":[r for r in rows if not r["pass"]]} for kind,rows in results.items() if isinstance(rows,list)}))
sys.exit(any(not r["pass"] for rows in results.values() if isinstance(rows,list) for r in rows))
