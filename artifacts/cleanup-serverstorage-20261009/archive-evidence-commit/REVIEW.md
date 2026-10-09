# Curated S01/S04/S06 archive and tool evidence

This is a downstream evidence/tool commit allowlist, not a runtime removal or deployment batch. Collection performed no Studio/native/network calls, source/editor operations, runtime/manifest changes, staging, commits, publication or GitHub push. Root reviews and stages the exact listed paths. Actor optimization files, canonical game Sources, the main manifest/docs, S08 already committed work, private checkpoints, caches and transfer `*-part-*` chunks are excluded.

`allowlist.json` records exact current paths, bytes and SHA-256 values. Its own path is an explicit additional commit path because a file cannot contain its own SHA-256. Root-owned tool attribute changes are also a separate addition: pin the explicit cleanup-tool paths with `-text`, preserving existing rules, and verify staged blob hashes against these frozen working bytes. Artifact rules preserve raw archive/proof bytes only; they do not change runtime assets or Source.

Included evidence covers the final S01 diagnostic v7/v8 native/facts/reference packs and probe/compile/failure records; all nine S04 helpers, offline proofs v1-v5, two failed captures and the successful v3 scoped native capture/reopen; S06 externally held 23-root native capture and failed independent reopen; exact archived 12 mirror Sources and closure/failure/offline receipts; and future reopen ownership hardening. Historical S03/S05 export receipts are retained as observations at their captured gates. The superseded S05 Source is not copied back into its runtime path. Current S09 export and its canonical Source/manifest are separate root/client scope.

The S04 five roots were not removed by these tools. Native recovery success does not substitute for the missing active R4/V2 before/after runtime, actual asset, multiplayer/streaming and cold-cache flows. S01 actual retirement ports are also pending. The 23 S06 roots were unparented externally, and the S06 native reopen failed readable-data comparison while cleaning all 23 copies and preserving originals. The source-only S06 attempts and tool controls are described by their actual receipts; failed attempts must not be promoted to removal successes.

## Portable full facts archive

`external-storage-archive-v1/facts.json` remains local and is deliberately excluded from Git. The committed `facts.json.gz` and `facts-compression.json` losslessly retain the complete 41,912,358-byte facts document. The gzip is 3,017,503 bytes, SHA-256 `3ff1d40337cb4792c530ea0c1f0f7c2b5a1cacdbffbd1bfce5fb7be7353caa1f`; decompression must produce raw SHA-256 `b6b86b7871bab31d8fdebd9afa5cf3367426fad4e6a5eaef9038e4e8b1434f33`. Collection independently compared the inflated bytes to the existing local raw file and the compression receipt without writing either.

Before reusing native archive/reopen wrappers that read the raw `facts.json` path, run this **offline** inflation/verification from the repository root. It never connects to Studio and refuses to replace different existing raw bytes:

```python
from pathlib import Path
import gzip, hashlib, json

base = Path("artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1")
meta = json.loads((base / "facts-compression.json").read_bytes())
packed = (base / meta["archiveFile"]).read_bytes()
assert len(packed) == meta["gzipBytes"]
assert hashlib.sha256(packed).hexdigest() == meta["gzipSHA256"]
raw = gzip.decompress(packed)
assert len(raw) == meta["rawBytes"]
assert hashlib.sha256(raw).hexdigest() == meta["rawSHA256"]
path = base / meta["rawFile"]
if path.exists():
    assert path.read_bytes() == raw
else:
    with path.open("xb") as stream:
        assert stream.write(raw) == len(raw)
assert path.read_bytes() == raw
```

This recovers the exact local receiver input; it is not a native restoration port. The portable offline S06 fixtures already consume the gzip directly. S04's smaller 2.4 MB facts remain committed as raw bytes. Transfer parts are preserved locally as transport history but excluded from the allowlist once the verified complete files exist. Already committed baseline metadata/tool context is referenced separately in the allowlist and need not be staged again.
