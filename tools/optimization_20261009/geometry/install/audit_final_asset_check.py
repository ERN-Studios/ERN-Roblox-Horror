"""Audit the saved read-only native asset-check evidence without Studio access."""
import argparse
import hashlib
import json
from pathlib import Path

from final_asset_check import HERE, ROOT, expected_targets, normalized_id


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt-prefix", choices=("final", "prepublish"), default="final")
    args = parser.parse_args()
    install = json.loads((HERE / "runner-receipt.json").read_text())
    targets, _ = expected_targets(install)
    receipt_path = HERE / (args.receipt_prefix + "-asset-check.json")
    final_raw = receipt_path.read_bytes()
    final = json.loads(final_raw)
    assert final["phase"] == "complete" and final["exact"] is True
    assert final["checked"] == final["nativeFingerprintChecked"] == final["normalizedIdentityChecked"] == len(targets) == 6996
    first, identities, full_id_matches = 1, set(), 0
    roots, counts = None, None
    for entry in final["pages"]:
        raw = (ROOT / entry["path"]).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == entry["sha256"]
        page = json.loads(raw)
        assert entry["nativeRoundtripExact"] is True and entry["uncompressedBytes"] == len(raw)
        assert page["first"] == first and entry["first"] == first and page["total"] == len(targets)
        assert page["readOnly"] and page["nativeFingerprintSchemaExact"] and page["exact"]
        assert page["placeId"] == 131311258779917 and page["universeId"] == 10559217407
        assert not page["mismatches"] and page["checked"] == len(page["verified"]) == entry["rows"]
        if roots is None:
            roots, counts = page["roots"], page["rootCounts"]
        assert roots == page["roots"] and counts == page["rootCounts"]
        for target, row in zip(targets[first-1:first-1+entry["rows"]], page["verified"]):
            assert row["id"] == target["id"]
            key = normalized_id(row["actualId"])
            assert key == normalized_id(target["id"]) and key not in identities
            identities.add(key)
            assert len(row["sha256"]) == 64 and int(row["sha256"], 16) >= 0
            # Fingerprints are exact native UTF-8 strings, not Python JSON output.
            assert hashlib.sha256(target["fingerprint"].encode()).hexdigest() == row["sha256"]
            full_id_matches += row["actualId"] == target["id"]
        first += entry["rows"]
    assert first == len(targets) + 1 and len(identities) == 6996
    assert final["latestRoots"] == roots and final["latestRootCounts"] == counts
    report = {"exact": True, "nativeRows": len(identities), "uniqueNormalizedCurrentIds": len(identities),
              "fullDebugIdStringsAlsoExact": full_id_matches, "exactNativeFingerprintSha256Matches": len(identities),
              "nativePages": len(final["pages"]), "pageHashesAndOrderExact": True,
              "rootsStableAcrossAllBatches": True, "rootCounts": counts,
              "targetKinds": final["targetKinds"], "finishedUtc": final["finishedUtc"],
              "finalReceiptSha256": hashlib.sha256(final_raw).hexdigest(), "studioAccessPerformed": False,
              "receiptPath": str(receipt_path.relative_to(ROOT))}
    (HERE / (args.receipt_prefix + "-asset-local-audit.json")).write_text(json.dumps(report, indent=2) + "\n")
    print(json.dumps(report, indent=2))


if __name__ == "__main__":
    main()
