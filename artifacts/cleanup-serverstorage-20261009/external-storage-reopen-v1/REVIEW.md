# S06 native archive reopen — failed full-object restoration gate

`reopen-result.txt` is the final native result from 2026-10-09T22:12:00Z.
It reports `pass=false`, `readableDataPass=false` and
`restorationCertified=false`. Preserve this failed result; the archive was not
restored into the game and this trial does not authorize native removal.

The engine reopened the complete 23-root forest into unparented, test-owned
copies: 14,079 instances and 12 LuaSourceContainers. Twenty-one readable root
subtree digests matched. These two differed:

| Root | Captured readable subtree SHA256 | Reopened readable subtree SHA256 |
|---|---|---|
| `TEMP_PipeEntityValidation` | `0e614ad1094d38a85fe0129adf687d42ca201b453215cff360c8f76000f0cb18` | `48ff97b6218fe26e337907476a0e2640242e888e995e511d3ce566c54bc08855` |
| `TrelloPoolSlideReleaseBackup_20260910` | `55b631609cc5c10ce83d2c96e338ccd8bcecbd85af086a7f420a5bd554659892` | `55633ba82d7419f4ebbebca5d303766527c12b95729e6dd5594d0a35015695b0` |

The concrete typed-property differences have not been classified. Do not
normalize this failure away or attribute it to identity-only fields. Twelve
Sources and ten forest-internal reference properties passed their checks. That
does not establish full restoration of the two failing object trees or the
98,648 protected/unreadable property observations.

All 23 created roots were destroyed independently. The report records original
Source/editor guards and the original native forest hash unchanged, zero
original Parent writes, zero Source writes and zero mode switches. The measured
watcher release duration is a cleanup diagnostic, not a performance improvement.

The complete copy reserialization was retained before reporting the readable
failure. Both binary files have 2,739,764 bytes; their SHA256 values differ:

- Original `../external-storage-archive-v1/native.rbxm`:
  `139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca`.
- Owned-copy `roundtrip.rbxm`:
  `dbfb34d6dc742c50c4b743fd7a5fc0e374599f3b8c81ea1e8f5d6baa455eb121`.

`inputs.json` pins the raw native archive, complete capture facts, successful
capture completion and the exact `reopen-source.luau` used. The source hash is
`52a3fc3aa70acd4e60977594f96caee7a2bba583f021246aa5677a0a0f9305d7`.
`transfer-receipt.json` pins the retained copy binary. Keep these historical
inputs/results byte-exact; transfer part files are redundant local receiver
fragments and need not be committed.

The 41,912,358-byte capture facts are committed losslessly as
`../external-storage-archive-v1/facts.json.gz`, with exact raw/gzip hashes in
`facts-compression.json`. Offline verification confirmed decompression equals
the local raw `facts.json` byte-for-byte and matches the original transfer
receipt. The offline S06 wrapper fixture reads gzip directly. Before an
explicitly reviewed native replay that requires the raw receiver file, inflate
it strictly and exclusively; preserve an existing raw file only if equal:

```powershell
$archiveCode = @'
from pathlib import Path
import gzip, hashlib, json
p = Path("artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1")
m = json.loads((p / "facts-compression.json").read_bytes())
packed = (p / "facts.json.gz").read_bytes()
sha = lambda raw: hashlib.sha256(raw).hexdigest()
assert (len(packed), sha(packed)) == (m["gzipBytes"], m["gzipSHA256"])
raw = gzip.decompress(packed)
assert (len(raw), sha(raw)) == (41912358, "b6b86b7871bab31d8fdebd9afa5cf3367426fad4e6a5eaef9038e4e8b1434f33")
assert (len(raw), sha(raw)) == (m["rawBytes"], m["rawSHA256"])
target = p / "facts.json"
if target.exists():
    assert target.read_bytes() == raw
else:
    with target.open("xb") as stream:
        assert stream.write(raw) == len(raw)
assert target.read_bytes() == raw
'@
python -B -c $archiveCode
```

This command only reconstructs a local evidence file. It makes no Studio calls.
Executing a native archive/reopen helper is a separate action requiring the
original identity ledger, a fresh compatible Edit baseline and scoped review;
these historical receipts are not a current Studio baseline.

The parent approved a separate source-only S06 gate for retiring 12 downstream
mirror files/manifest rows whose native originals had already been detached by
another actor. Exact source archives, compile/contracts, fresh native absence
and held Source/editor/properties checks support that narrower gate. It does
not certify restoration of this full object forest, remove runtime features,
claim the other actor's removal as cleanup work, or provide gameplay,
multiplayer, streaming, external-asset, UI or publication certification.
