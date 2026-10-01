#!/usr/bin/env python3
"""Verify approved pricing spans using committed Sources, without native backups.

Run from any directory: python3 verify_committed_pricing_scope.py
Optional --mirror and --report paths override the recorded mirror/output.
This checker never connects to Studio or accesses the network.
"""

import argparse
import hashlib
import json
from pathlib import Path


def digest(source):
    return hashlib.sha256(source.encode("utf-8")).hexdigest()


def main():
    directory = Path(__file__).resolve().parent
    task = directory.parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mirror", type=Path, default=task / "verified-studio-mirror")
    parser.add_argument("--report", type=Path, default=directory / "committed-pricing-scope-verification.json")
    args = parser.parse_args()
    manifest = json.loads((directory / "exact-replacements.json").read_text())
    checks = []
    for record in manifest["scripts"]:
        path, klass = record["path"], record["class"]
        before_file = task / "audit/live-sources" / (path + "." + klass + ".luau")
        after_file = args.mirror.joinpath(*path.split("."))
        after_file = after_file.with_name(after_file.name + "." + klass + ".luau")
        before = before_file.read_bytes().decode("utf-8")
        after = after_file.read_bytes().decode("utf-8")
        assert digest(before) == record["beforeSourceSHA256"], "Baseline hash mismatch: " + path
        expected = before
        for replacement in record["replacements"]:
            assert expected.count(replacement["old"]) == 1, "Absent or ambiguous approved span: " + path
            expected = expected.replace(replacement["old"], replacement["new"], 1)
        assert digest(expected) == record["afterSourceSHA256"], "Approved result hash mismatch: " + path
        assert after == expected, "Source changed beyond approved pricing spans: " + path
        checks.append({"path": path, "class": klass, "exactApprovedSpans": len(record["replacements"]),
                       "beforeSHA256": digest(before), "afterSHA256": digest(after),
                       "actualSourceExactlyMatchesApprovedSpans": True})
    assert len(checks) == 2, "Expected exactly two pricing Sources"
    result = {"passed": True, "nativeBackupsRequired": False, "scripts": checks,
              "totalApprovedSpans": sum(item["exactApprovedSpans"] for item in checks)}
    encoded = json.dumps(result, indent=2) + "\n"
    args.report.write_text(encoded)
    print(encoded, end="")


if __name__ == "__main__":
    main()
