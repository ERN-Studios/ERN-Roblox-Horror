"""Freeze new V2 evidence; preserve every earlier V1 pin and actual failure."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
V1 = HERE.with_name("storage-authoring-port-v1")
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def pin(path):
    raw = path.read_bytes()
    return {"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": SHA(raw)}


def main():
    target = HERE / "frozen-pins-v1.json"
    assert not target.exists(), "Immutable freeze exists"
    v1pins = json.loads((V1 / "frozen-pins-v1.json").read_bytes())
    for old in v1pins["pins"]:
        assert pin(ROOT / old["path"]) == old, "Frozen V1 drift"
    assert json.loads((HERE / "offline-faults-v1.json").read_bytes())["passed"]
    assert json.loads((HERE / "offline-native-boundaries-attempt-v1.json").read_bytes())["passed"]
    own = sorted(path for path in HERE.iterdir() if path.is_file() and path != target)
    inherited = [ROOT / "AGENTS.md", ROOT / "tools/cleanup_20261009/retired_authoring_archive_common.luau",
                 V1 / "frozen-pins-v1.json", V1 / "native-trial.luau", V1 / "preparation-v1.json"]
    inherited += sorted((V1 / "native-run-v1").glob("*"))
    inherited += sorted((V1 / "before-parity-v2").glob("native-page-*.json"))
    paths = own + [p for p in inherited if p.is_file()]
    assert len({p.resolve() for p in paths}) == len(paths)
    receipt = {"schema": "retired-authoring-controlled-absence-frozen-pins-v2", "frozen": True,
               "nativeExecuted": False, "deletionApproved": False, "v1FrozenPinsPreserved": True,
               "reviewedSourceSHA256": SHA((HERE / "trial-source.luau").read_bytes()), "pins": [pin(p) for p in paths]}
    with target.open("xb") as stream:
        stream.write((json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"frozen": True, "pins": len(paths), "receipt": pin(target), "source": pin(HERE / "trial-source.luau"),
                      "config": pin(HERE / "trial-config.json"), "driver": pin(HERE / "run-root-trial.py")}))


if __name__ == "__main__":
    main()
