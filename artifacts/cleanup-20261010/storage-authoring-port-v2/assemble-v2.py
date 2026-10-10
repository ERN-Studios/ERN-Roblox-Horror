"""Assemble the mutable V2 delta once before its explicit freeze; no native calls."""
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
    assert not (HERE / "frozen-pins-v1.json").exists(), "Frozen V2 cannot be assembled again"
    inherited = V1 / "preparation-v1.json"
    assert SHA(inherited.read_bytes()) == "a02fe0ef5b50ca3dc29a70f9bdf77e84e43179f01ef18dfc240b15e5a8a1b337"
    prep = json.loads(inherited.read_bytes())
    config_raw = (HERE / "trial-config.json").read_bytes()
    config = json.loads(config_raw)
    assert config["captureId"] != json.loads((V1 / "trial-config.json").read_bytes())["captureId"]
    assert config["catalogSHA256"] == "81115530329fefcca83091e74379f63983ca0aa4b1da0b43bc64e653956623dd"
    assert config["expectedSceneCount"] == 417075 and len(config["sources"]) == 213
    common = ROOT / "tools/cleanup_20261009/retired_authoring_archive_common.luau"
    core, suffix = HERE / "transaction-core.luau", HERE / "native-trial.luau"
    assert core.read_bytes() == (V1 / "transaction-core.luau").read_bytes()
    source = (common.read_bytes() + b"\n" + core.read_bytes() + b"\nlocal PORT_CONFIG=A.HS:JSONDecode([====[" + config_raw
              + b"]====])\n" + suffix.read_bytes())
    assert b"]====]" not in config_raw
    (HERE / "trial-source.luau").write_bytes(source)
    prep["schema"] = "retired-authoring-controlled-absence-preparation-v2"
    prep["inheritedPreparation"] = pin(inherited)
    prep["inputs"] += [pin(path) for path in (common, core, suffix)]
    prep["config"] = pin(HERE / "trial-config.json")
    prep["assembledSource"] = pin(HERE / "trial-source.luau")
    prep["v2Delta"] = ["Inverse must not adopt foreign nil before actual native setter invocation",
                       "Explicit controlled server-data domain; separately observed actual Edit domain and actual-body client rejection"]
    prep["actualV1NativeFailure"] = pin(V1 / "native-run-v1/root-completion.json")
    (HERE / "preparation-v1.json").write_bytes((json.dumps(prep, ensure_ascii=False, indent=2) + "\n").encode())
    print(json.dumps({"assembledSource": prep["assembledSource"], "preparation": pin(HERE / "preparation-v1.json")}))


if __name__ == "__main__":
    main()
