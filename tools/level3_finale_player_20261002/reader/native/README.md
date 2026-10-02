# Local native verification and five-source mirror export

Prepared for the root agent. These utilities have no Studio, Git, network or DataStore tools. Actual before backup is pinned to 51826241 bytes / SHA `bc32152e6fd668aab75108576c454ef84a3c914ec4e606f094e5599c5e34f378`. The independent local probe found 231 Sources, 52 service roots and 391959 descendants; repeated Source-masked canonical serialization is deterministic. See `preparation-receipt.json`. No after/native/live parity has yet been claimed.

Invoke only after saving the authoritative stopped Edit place as `after.rbxl` and capturing all 231 live Source/editor fingerprints. The live JSON must include `placeId`, `universeId`, `isRunning:false`, `capturedAtUTC`, and `sources` rows with `path`, `class`, `sourceSHA256`, `editorSHA256`, `editorMatch:true`, and optional `sourceBytes`. Other equivalent existing names in the helper are accepted. The frozen install manifest uses `changes` or `rows` with exactly five fixed paths, `class`/`className`, `baselineSHA256`, `candidateSHA256`, and `candidateFile`. Candidate file bytes must still match the frozen hash.

Create an empty verification output directory, then run:

```sh
/private/tmp/level3-promotion-backup-lune-20261002/lune run tools/level3_finale_player_20261002/reader/native/verify-native-five.luau BEFORE.rbxl AFTER.rbxl FIVE_MANIFEST.json LIVE_231_CATALOG.json OUTPUT_DIR
```

The helper deserializes both raw native files, requires 231 unique exact Source paths/classes, compares every Source byte, requires exactly the five frozen baseline-to-candidate changes (226 unchanged), and matches every saved after Source to the fresh live Source/editor fingerprint. It then masks only Source in memory and compares full-place canonical native serialization. It records full raw bytes/SHA, service and descendant counts, every Source hash and per-root canonical hashes. A native-content difference writes a diagnostic verification receipt with `verified:false` and blocks the Source payload; use a fresh output directory for a reconciled retry. Raw native files are never modified.

Non-Source equality means content supported by Lune deserialize/serialize, including its serialized properties, attributes and instance references. Unsupported native fields are retained in the full raw backups but have no semantic equality claim. This limitation is explicit in the receipt; neither utility makes gameplay/performance/publication claims.

Once verified, inspect the default read-only export plan:

```sh
python3 tools/level3_finale_player_20261002/reader/native/export-native-five.py --verification-dir OUTPUT_DIR --repo REPO_ROOT --checkpoint EXTERNAL_PRIOR_MIRROR_DIR
```

Root explicitly adds `--apply` to write the five fixed repository Source mirrors. The driver rechecks native-after/live-catalog/frozen-manifest hashes, validates all Source payload bytes against the verified native hashes, durably preserves the current five mirror files in the external checkpoint, compares each mirror again immediately before the scoped in-place write, and writes an immutable export receipt. No Git/index action occurs. Fixtures used a temporary synthetic repository only; the real mirrors were not written during preparation.
