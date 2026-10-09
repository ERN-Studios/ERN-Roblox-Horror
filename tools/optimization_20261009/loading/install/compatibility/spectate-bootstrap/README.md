# Spectate selection with streamed avatars

The previous client required a target's Humanoid and HumanoidRootPart before selecting that player. A distant avatar could therefore remain unselected, so the server never added the replication focus needed to bring its body and surroundings in. Roblox documents this avatar stream-out behavior in its [streaming techniques](https://create.roblox.com/docs/workspace/streaming/techniques#slim-avatars).

The scoped fix uses the existing RoundStatus remote. A valid dead or escaped participant requests `spectatecandidates` immediately on start and on the existing one-second refresh. The server answers only that player with `{Serial, UserIds}` after checking its authoritative living roster and applying a 0.8-second per-player rate guard. The client rejects stale-session responses and retains an eligible chosen ID while its Character, HumanoidRootPart or Head is absent. Local avatar health does not overrule the server's current roster. The existing single additional focus, counts, target reporting and camera path remain in use. Reset, respawn and leave clear request/session state. The approved Level 5/6 fallback requires both server-owned live-domain flags and matching Level 5 domain; it does not expose unrelated players.

The fresh Edit baseline, exact proposals, scoped diffs and complete instance/parent identities are recorded in `baseline-capture.json` and `source-install-manifest.json`. Root installed both sources with strict identity and Source/editor compare-and-swap guards; `source-install-receipt.json` records the result.

| Source | Installed raw bytes | Installed SHA256 |
| --- | ---: | --- |
| ServerScriptService.GameManager | 194825 | `0610a0361dcdeec62ac603a72f0948309b7aa95d638056a38fcd0f0a3fa7b3a4` |
| StarterPlayer.StarterPlayerScripts.SpectateController | 20082 | `f912a197184846e20cb1ba1c65a34bda3a2b6acdc3d263e0dc73abb3dc20645b` |

The production-extracted contract suite passed 99 assertions with official Luau 0.741. Root also ran those 99 mocked contracts natively in a fresh empty ModuleScript, with all eight authoritative sources pinned and verified through cleanup (`native-bootstrap-probe-receipt.json`). These mocked checks are not gameplay or performance measurements.

Root's separate two-client test subsequently passed distant-first selection naturally: the target moved 924 studs away; its HumanoidRootPart and Head were absent from the spectator before death; the actual serial-1 server roster selected that player; the spectator count was one; the camera followed its head and the actual target floor streamed in. No missing-body name fixture was needed. The [gameplay receipt](../../../../runtime/observations/bootstrap-distant-first-floor-corrected.json) records the observations. An earlier floor-query fixture failed before gameplay mutation and its receipt remains preserved; the corrected fixture was separately verified and rerun. This proves that bounded scenario, not all levels or a measured performance improvement.

`refresh_eight_sources.py` defaults to local-only preflight. It validates exactly eight reviewed paths, six unchanged mirrors, two acceptable local before sources, full target rows and the current global-manifest shape. Its 96 mocked preservation/CAS checks are recorded in `eight-refresh-test-result.json`; the tested helper SHA256 is `f701a03518e726a82e58997b568c455475d5e2701d7fdcbd4a8361d74225e6e6`. Default preflight does not connect to Studio or modify runtime mirrors, the global manifest or either Git index.

Root alone runs the authorized promotion:

```powershell
python -B tools/optimization_20261009/loading/install/compatibility/spectate-bootstrap/refresh_eight_sources.py --apply
```

Apply reads only the original authoritative Edit Studio `1b603e69-7ae1-4572-b210-d5bf05c684ff`, cross-checked against both capture manifests. It pins all eight identities, Source/editor pairs, hashes, relevant properties and primitive attributes before and after bounded raw capture and local promotion. Only the two revised mirrors are copied after exact local-before guards. Only the eight source fields in the current global manifest are refreshed; other developers' rows, metadata and properties are preserved.

The new export is `verified-export-eight/manifest.json`, with changed raw sources in that directory and unchanged raw sources referenced from the historical seven-source export. The historical seven-source manifest, old GameManager row and all prior receipts stay immutable. Apply writes its separate `eight-source-refresh-receipt.json`. It creates no backup, performs no Studio mutation, stages or commits no Git changes, and is a source export rather than a complete native place backup. Root owns the subsequent exact scoped index review, commit and publication.

Root completed the eight-source promotion; its separate receipt and current manifest are preserved. `check_eight_sources.py` is the repeatable final read-only protocol for a fresh prepublish or postpublish receipt. It loads the current eight raw sources and properties/attributes from this manifest, locks the original Edit connection through both historical and fresh baseline Studio IDs, and checks all eight exact native sources, editor pairs and identities twice. It writes only the explicitly named fresh JSON receipt under the task's runtime directory. For example:

```powershell
python -B tools/optimization_20261009/loading/install/compatibility/spectate-bootstrap/check_eight_sources.py --receipt tools/optimization_20261009/runtime/final-eight-prepublish-source-check.json
```

That prepublish receipt is complete. Repeating the command requires a new receipt filename; existing receipts are never overwritten. `check-eight-test-result.json` records bounded mocked rejection/preservation checks and compilation of the generated native read code plus all eight current runtime sources with official Luau 0.741. The source checker performs no native probe, property write, backup, mirror/global refresh, Git action or publication.
