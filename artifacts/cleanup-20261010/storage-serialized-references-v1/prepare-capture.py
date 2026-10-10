"""Assemble public readonly template with a private runtime-token placeholder."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def main():
    target = HERE / "capture-source-template.luau"
    assert not target.exists() and not (HERE / "frozen-pins-v1.json").exists()
    common = ROOT / "tools/cleanup_20261009/retired_authoring_archive_common.luau"
    config, suffix = HERE / "capture-config.json", HERE / "native-capture.luau"
    source = common.read_bytes() + b"\nlocal PORT_CONFIG=A.HS:JSONDecode([====[" + config.read_bytes() + b"]====])\n" + suffix.read_bytes()
    assert source.count(b"__ROOT_PRIVATE_TOKEN__") == 1 and b"]====]" not in config.read_bytes()
    with target.open("xb") as stream: stream.write(source)
    receipt = {"schema": "retired-authoring-raw-capture-preparation-v1", "nativeCalls": 0, "receiverStarted": False,
               "sourceTemplate": {"bytes": len(source), "sha256": SHA(source)}, "privateTokenPlaceholderOnly": True,
               "inputs": [{"path": path.relative_to(ROOT).as_posix(), "bytes": len(path.read_bytes()), "sha256": SHA(path.read_bytes())} for path in (common, config, suffix)],
               "deletionApproved": False, "limits": "Prepared readonly source only. Root must bind new private token and complete exact native/API/transport/raw-reference gates."}
    with (HERE / "preparation-v1.json").open("xb") as stream: stream.write((json.dumps(receipt, indent=2) + "\n").encode())
    print(json.dumps(receipt["sourceTemplate"]))


if __name__ == "__main__": main()
