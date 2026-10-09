# ESP merge against the current installation checkpoint

Artifact only. No production file, Studio source, UI or settings were changed.

This proposal applies the previously reviewed Player ESP changes to the current files: GameManager is the restored v1849 spawn-spacing checkpoint (`4d0ee8f3…`), Store includes Entity Shield and the existing section-icon/ghost correction (`efe9d5b2…`), and DevCheats remains `39072aee…`. The superseded wait-for-everyone Continue proposal is absent. No revised Continue work is included.

`baseline/` preserves those exact current bytes. `inputs/` preserves the original generator, test runner and manifest; the original proposal and narrow diffs one directory above remain unchanged. The original generator and test runner are executed with exactly one filesystem root-depth substitution each. Their source transformations, actual test extraction and all assertions are unchanged.

`merge-proof.json` verifies the original input hashes and independently compares every changed-line payload between the old baseline/proposal and current baseline/merge. All three files have precisely the same ESP insertions/replacement payloads as the reviewed original. This preserves all intervening spawn, Store, Entity Shield, caption and existing Continue behavior. The new manifest and three diffs describe this current checkpoint.

Validation: **67 actual-source checks**, both original required negative controls and **three complete compilations** pass against the actual merged sources. Current production hashes remain identical to `baseline/`. This reuses the original bounded suite and does not claim a real multiplayer/native test.

Run:

```powershell
python artifacts/trello-20260909/player-esp-prepared/installation-merge/prepare_merge.py
python artifacts/trello-20260909/player-esp-prepared/installation-merge/test_merge.py
```

`prepare_merge.py` explicitly refuses any advance from the recorded current checkpoint. Root may install these proposals only after matching each current hash and the Studio audit. Later Continue or logo work requires applying that separate feature to a fresh checkpoint; never overwrite it with an older complete ESP file. Config/product IDs are not touched by ESP.

Merged SHA-256:

- DevCheats: `f16d6fc3f23fbd314f77498788eae3a08fb4698ba5160166064846f3eabd5aeb`
- Store: `18669976cc8f88881c8939a98276f88cf1cf12bc933789924dd93ab884e824bf`
- GameManager: `9ad40894ee97ed440acfa027513f79865926a8a39fa798819fa4455937e71350`

The original bounded code review was 9/10. This merge's independent check and native acceptance remain separate; no self-score or publication claim is made here.
