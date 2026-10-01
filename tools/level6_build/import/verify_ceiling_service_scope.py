"""Compare independent live service-setting receipts, without contacting Studio."""
import json
from pathlib import Path
import sys


def main(before_dir, after_dir, output_path):
    before_dir, after_dir = Path(before_dir), Path(after_dir)
    before = json.loads((before_dir / "metadata.json").read_text())
    after = json.loads((after_dir / "metadata.json").read_text())
    assert before["placeId"] == after["placeId"] == 131311258779917
    assert before["universeId"] == after["universeId"] == 10559217407
    b_services = {s["class"]: s for s in before["services"]}
    a_services = {s["class"]: s for s in after["services"]}
    failures, checks = [], []

    def check(condition, description):
        checks.append({"passed": condition, "description": description})
        if not condition:
            failures.append(description)

    check(set(b_services) == set(a_services), "Same captured services retained")
    for name, old in b_services.items():
        new = a_services.get(name, {})
        for key in ("name", "properties", "attributes", "tags", "propertyErrors"):
            check(old.get(key) == new.get(key), f"Service {name} {key} unchanged")
    for key in ("collisionGroups", "collisionMatrix", "materialOverrides"):
        check(before[key] == after[key], f"Global {key} unchanged")
    report = {
        "schema": "level6-ceiling-independent-service-scope/1",
        "placeId": before["placeId"],
        "universeId": before["universeId"],
        "beforeCapture": before["capturedAt"],
        "afterCapture": after["capturedAt"],
        "counts": {
            "services": len(b_services),
            "readableProperties": sum(len(s["properties"]) for s in b_services.values()),
            "attributes": sum(len(s["attributes"]) for s in b_services.values()),
            "tags": sum(len(s["tags"]) for s in b_services.values()),
        },
        "checks": checks,
        "failures": failures,
        "passed": not failures,
        "limitations": "Equality of readable saved service settings only. Unreadable properties and native recovery reconstruction limitations are separately recorded; no gameplay or publishing inference.",
    }
    Path(output_path).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps({k: report[k] for k in ("passed", "counts", "failures")}))
    assert not failures, failures


if __name__ == "__main__":
    main(*sys.argv[1:])
