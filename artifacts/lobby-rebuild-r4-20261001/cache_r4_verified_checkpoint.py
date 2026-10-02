"""Copy a verified fresh checkpoint to noncloud storage without relaxing hashes.

Native chunk cache files are reconstructed from the independently hash-verified
raw forest, then checked against every original receipt row. Original files are
read only. This never calls Studio and never changes the authoritative receipt.
"""
from pathlib import Path
from concurrent.futures import ThreadPoolExecutor, as_completed
import datetime
import hashlib
import json
import os

TASK = Path(__file__).resolve().parent
SOURCE = TASK / "native-before"
CACHE = Path("/private/tmp/lobby-r4-recovery-before-20261001")

def sha(path):
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()

def store_exact(name, value, expected):
    destination = CACHE / name
    assert len(value) == expected["bytes"]
    assert hashlib.sha256(value).hexdigest() == expected["sha256"]
    destination.parent.mkdir(parents=True, exist_ok=True)
    if destination.exists():
        assert destination.stat().st_size == len(value) and sha(destination) == expected["sha256"]
    else:
        partial = destination.with_name(destination.name + ".partial")
        with partial.open("xb") as stream:
            stream.write(value)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(partial, destination)
    assert sha(destination) == expected["sha256"]
    return {"file": name, "bytes": len(value), "sha256": expected["sha256"]}

def copy_exact(row):
    name = row["file"]
    assert Path(name).name == name
    value = (SOURCE / name).read_bytes()
    record = store_exact(name, value, row)
    print(json.dumps({"verifiedCacheFile": name, "bytes": len(value)}), flush=True)
    return record

def main():
    CACHE.mkdir(parents=True, exist_ok=True)
    receipt_bytes = (SOURCE / "checkpoint-install-gate.json").read_bytes()
    receipt = json.loads(receipt_bytes)
    assert receipt["verified"] is True and receipt["captureId"] == "a3e80689-a0f2-4f26-8d6e-f5b8b4adaaf7"
    assert receipt["nativeSHA256"] == "2291d497321cc847d083ab01f30795ebaae29a245701cd51cd91922b808a70e0"
    assert receipt["placeId"] == 131311258779917 and receipt["universeId"] == 10559217407 and receipt["groupId"] == 1039373905
    rows = receipt["files"]
    assert len(rows) == 106 and len({row["file"] for row in rows}) == len(rows)
    other_rows = [row for row in rows if not row["file"].startswith("native-part-")]
    with ThreadPoolExecutor(max_workers=4) as pool:
        futures = [pool.submit(copy_exact, row) for row in other_rows]
        for future in as_completed(futures):
            future.result()
    native = (CACHE / "all-service-children.rbxm").read_bytes()
    assert len(native) == receipt["nativeBytes"] and hashlib.sha256(native).hexdigest() == receipt["nativeSHA256"]
    chunk_rows = sorted([row for row in rows if row["file"].startswith("native-part-")], key=lambda row: row["file"])
    offset = 0
    for index, row in enumerate(chunk_rows):
        assert row["file"] == f"native-part-{index:05d}.bin"
        store_exact(row["file"], native[offset:offset + row["bytes"]], row)
        offset += row["bytes"]
    assert offset == len(native)
    # Re-read all cache files, including the raw forest and reopened place.
    for row in rows:
        cached = CACHE / row["file"]
        assert cached.stat().st_size == row["bytes"] and sha(cached) == row["sha256"]
    metadata = json.loads((CACHE / "metadata.json").read_bytes())
    assert metadata["captureId"] == receipt["captureId"] and metadata["nativeSHA256"] == receipt["nativeSHA256"]
    gate_expected = {"bytes": len(receipt_bytes), "sha256": hashlib.sha256(receipt_bytes).hexdigest()}
    store_exact("checkpoint-install-gate.json", receipt_bytes, gate_expected)
    schema = (SOURCE / "service-property-schema.json").read_bytes()
    store_exact("service-property-schema.json", schema, {"bytes": len(schema), "sha256": hashlib.sha256(schema).hexdigest()})
    record = {"schema": "lobby-r4-noncloud-verified-recovery-cache-v1", "verified": True,
              "verifiedAtUtc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
              "captureId": receipt["captureId"], "nativeSHA256": receipt["nativeSHA256"],
              "nativePlaceSHA256": receipt["nativePlaceSHA256"], "cacheDirectory": str(CACHE),
              "originalDirectory": str(SOURCE), "checkpointReceiptSHA256": gate_expected["sha256"],
              "fileCount": len(rows), "all106FileHashesAndSizesRechecked": True,
              "chunkReconstruction": "Exact byte ranges of independently verified raw forest; each chunk matches its recorded SHA256",
              "originalFilesChanged": False, "studioCalls": False, "files": rows}
    value = (json.dumps(record, indent=2) + "\n").encode()
    store_exact("noncloud-cache-verification.json", value, {"bytes": len(value), "sha256": hashlib.sha256(value).hexdigest()})
    (TASK / "review/noncloud-before-cache-verification.json").write_bytes(value)
    print(json.dumps({"verified": True, "cacheDirectory": str(CACHE), "fileCount": len(rows),
                      "receiptSHA256": gate_expected["sha256"]}), flush=True)

if __name__ == "__main__":
    main()
