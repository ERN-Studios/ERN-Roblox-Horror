# Final CAS fingerprints

Each row records exact UTF-8 source byte length and additive djb2 modulo 2^32. Full SHA-256 records and instance name components are in manifest.json. No payload has been executed in Studio.

| Payload | Baseline bytes / djb2 | Expected bytes / djb2 | Payload bytes |
|---|---:|---:|---:|
| 01-game-manager.apply.luau | 165648 / 3634059721 | 166063 / 951332234 | 8952 |
| 02-level5-adapter.apply.luau | 15482 / 2781571066 | 17720 / 3055794701 | 9372 |
| 03-window-watcher.apply.luau | 23722 / 2001089542 | 23818 / 4257775843 | 7597 |
| 04-lobby-builder.apply.luau | 103305 / 3458785195 | 116631 / 3492273471 | 20532 |
| 05-outage.apply.luau | 8618 / 398132620 | 8818 / 3854323309 | 5498 |
| 06-b-clue.apply.luau | 26930 / 1904696397 | 27031 / 3047997768 | 5527 |

Lobby source SHA-256: `e98ae3de991fb6a12a8b5f358eb6e61d5dbc395f30b89f3d8d0f36f90cb89b75`. This includes the final revision supporting existing FutureLaunchZone17–20 markers and reversible station activation. Renaming native detector markers does not add stations to the already-running GameManager private local table; a new normal runtime Build creates the intended stations.

All six complete draft sources and all apply/verify payloads compile at -O0. All six apply payloads pass 90 total mocked scenarios and 360 assertions. The GameManager payload contains only four unique three-context-line fragments, not its full source.

The B clue patch is one line: `if gateIndex==2 then gui.LightInfluence=.25 end`. Preview wording refers to the existing lobby control. No new completion/reward/travel signals are introduced.
