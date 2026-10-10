"""Artifact-only preparation from the completed native cache inventory."""
from pathlib import Path
import hashlib
import json
import subprocess

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
INVENTORY = HERE.with_name("animation-cache-inventory-v1")
SHA = lambda b: hashlib.sha256(b).hexdigest()
manifest_path = INVENTORY / "native-run-v1/cache-manifest-raw.json"
raw = manifest_path.read_bytes()
assert len(raw) == 237199 and SHA(raw) == "4caa106ecfcf965013c4ac6759c61c3fa752ff855f51614b9392ba8e0cbc1d94"
manifest = json.loads(raw)
finish = json.loads((INVENTORY / "native-run-v1/finish-completion.json").read_bytes())
assert finish["pass"] is True and finish["cleanup"]["closed"] is True and finish["manifestSHA256"] == SHA(raw)
collector = (INVENTORY / "collector.luau").read_bytes()
assert SHA(collector) == "5af553bdfa8eeffe6fdd3cf64e9202f87dd04156313f65b98e0bdf0ca2866c0a"
text = collector.decode().replace("\r\n", "\n")
anchor = "local ok,result=xpcall(function()"
assert text.count(anchor) == 1
prefix = text.split(anchor, 1)[0].encode()
suffix = (HERE / "frontier-suffix.luau").read_bytes()
template = prefix + suffix
config = {"captureId": "animation-full-archive-frontier-20261010-v1", "templateSHA256": SHA(template),
          "inventoryManifestSHA256": SHA(raw), "expectedSourceCatalogSHA256": manifest["sourceCatalogBeforeSHA256"],
          "roots": [row["root"] for row in manifest["roots"]], "records": manifest["records"],
          "classes": sorted({klass for row in manifest["roots"] for klass in row["classHistogram"]} | {"Folder", "Model"})}
config_raw = (json.dumps(config, ensure_ascii=False, indent=2) + "\n").encode()
literal = json.dumps(json.dumps(config, ensure_ascii=True, separators=(",", ":")))
source = ("local REQUEST=game:GetService('HttpService'):JSONDecode(" + literal + ")\n").encode() + template
inputs = [manifest_path, INVENTORY / "collector.luau", INVENTORY / "native-run-v1/finish-completion.json", HERE / "frontier-suffix.luau", Path(__file__).resolve()]
proof = {"schema": "mongotv-animation-full-archive-frontier-preparation-v1", "nativeExecuted": False,
         "productionWrites": 0, "deletionApproved": False, "inventoryManifestSHA256": SHA(raw),
         "helperPrefixSHA256": SHA(prefix), "templateSHA256": SHA(template),
         "preparedCode": {"bytes": len(source), "sha256": SHA(source)},
         "inputs": [{"path": p.relative_to(ROOT).as_posix(), "bytes": len(p.read_bytes()), "sha256": SHA(p.read_bytes())} for p in inputs]}
for name, data in (("frontier-template.luau", template), ("frontier-config.json", config_raw),
                   ("frontier-source.luau", source), ("frontier-preparation.json", (json.dumps(proof, indent=2) + "\n").encode())):
    with (HERE / name).open("xb") as stream:
        stream.write(data)
binary = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe")
compiled = subprocess.run([str(binary), str(HERE / "frontier-source.luau")], capture_output=True, text=True, timeout=30)
result = {"passed": compiled.returncode == 0, "exitCode": compiled.returncode, "stderr": compiled.stderr[:5000],
          "preparedCodeSHA256": SHA(source), "nativeCalls": 0, "limits": "Native APIs have not been invoked by this compile pass."}
with (HERE / "frontier-compile-v1.json").open("xb") as stream:
    stream.write((json.dumps(result, indent=2) + "\n").encode())
assert compiled.returncode == 0, compiled.stderr
print(json.dumps(result))
