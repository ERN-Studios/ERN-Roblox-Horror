"""Read an existing native engine archive; never connects to Studio or receiver."""
from pathlib import Path
import argparse
import json
from raw_binary_refs import parse, sha

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args(); target = args.receipt.resolve()
    assert target.parent.is_dir() and target.is_relative_to(ROOT / "artifacts/cleanup-20261010") and not target.exists()
    path = ROOT / "artifacts/cleanup-serverstorage-20261009/diagnostic-archive-before-v4/references.rbxm"
    raw = path.read_bytes()
    receipt = {"schema": "retired-authoring-existing-native-raw-parser-observation-v2", "passed": False, "nativeCalls": 0,
        "rawArchive": {"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": sha(raw)},
        "parserSHA256": sha((HERE / "raw_binary_refs.py").read_bytes()),
        "limits": "Existing engine buffer/different targets and epoch. Protected wire-field semantics evidence only, not current 109/five-forest reference absence."}
    try:
        assert sha(raw) == "590ca74c6a4c6fbfbcc03f3f1ab7cc574268e22c52b8df95170c41ef5c45d0a7"
        dom = parse(raw)
        wanted = {("StarterPlayer", "PlaceAvatarRules"), ("WeldConstraint", "Part0Internal"), ("WeldConstraint", "Part1Internal")}
        rows = []
        for row in dom["properties"].values():
            if (row["class"], row["name"]) in wanted:
                assert row["decoded"] and row["typeCode"] == 0x13
                rows.append({**{k: v for k, v in row.items() if k != "values"}, "owners": len(row["values"]),
                             "values": row["values"], "referentClasses": [None if ref == -1 else dom["nodes"][ref]["class"] for ref in row["values"]]})
        assert {(row["class"], row["name"]) for row in rows} == wanted
        assert next(row for row in rows if row["name"] == "PlaceAvatarRules")["values"] == [-1]
        assert all(row["owners"] == 3 for row in rows if row["class"] == "WeldConstraint")
        receipt.update(passed=True, actualRelevantRawColumns=rows, instances=len(dom["nodes"]), chunks=len(dom["chunks"]),
                       opaqueColumns=sum(not row["decoded"] for row in dom["properties"].values()), rawWeldConstraints=3)
    except BaseException as error:
        receipt["error"] = str(error); raise
    finally:
        assert path.read_bytes() == raw
        with target.open("xb") as stream: stream.write((json.dumps(receipt, indent=2) + "\n").encode())
    print(json.dumps({"passed": True, "rawWeldConstraints": 3, "requiredProtectedRawColumns": len(rows), "receiptSHA256": sha(target.read_bytes())}))


if __name__ == "__main__": main()
