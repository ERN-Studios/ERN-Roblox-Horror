"""Stage only named task entries while preserving pre-existing manifest edits."""
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[2]
selected=set(sys.argv[1:])
assert selected,"name explicit mirrored files"
committed=json.loads(subprocess.check_output(["git","show","HEAD:studio-sync-manifest.json"],cwd=ROOT))
working=json.loads((ROOT/"studio-sync-manifest.json").read_text(encoding="utf-8"))
current={i.get("file"):i for i in working["items"]}
found=set()
for index,item in enumerate(committed["items"]):
 if item.get("file") in selected:
  committed["items"][index]=current[item["file"]];found.add(item["file"])
assert found==selected,"unknown entry"
content=(json.dumps(committed,ensure_ascii=False,indent=2)+"\n").encode()
blob=subprocess.check_output(["git","hash-object","-w","--stdin"],input=content,cwd=ROOT).decode().strip()
subprocess.run(["git","update-index","--cacheinfo",f"100644,{blob},studio-sync-manifest.json"],cwd=ROOT,check=True)
print("Staged scoped manifest entries:",sorted(found))
