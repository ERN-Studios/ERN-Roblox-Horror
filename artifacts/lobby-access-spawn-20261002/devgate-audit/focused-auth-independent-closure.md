# Independent closure of Claude's focused authorization findings

**Conclusion: the shown authorization gaps are closed by the full installed server sources.** This is source inference plus offline exact-policy execution, not an ordinary-player live admission or multiplayer gameplay claim. No Studio instances, source, play mode, account or Git index were changed by this follow-up.

The six relevant sources were independently read from the actual running PlayServer after the new public-lobby startup. After the root stopped Play, all six exact captured sources were compared against fresh Edit Source and ScriptEditorService editor Source: every comparison matched, with no source/editor conflict (`post-play-edit-source-editor-check.json`).

## Trusted station metadata

Unchanged `ServerScriptService.LobbyReimaginedPreview.QueueBridge.Build`, lines 12–53, validates the exact owned ready model, integer IDs 101–124, unique IDs, per-ID level/display ordinal, anchored nonphysical detector, finite radius, direct bay parent/floor and owned render target. Line 45 creates server station records with `revisionOwned=true`, `previewOnly=level>3`, `previewQueue=level>3`.

The actual new PlayServer contained all 24 queue detector instances; Level 5 IDs 117–120 and Level 6 IDs 121–124 had matching level and display metadata (`post-install-server-auth.json`, `actualQueueZones`). The station flags follow from the exact unchanged server Build function. This audit did not introspect GameManager's private local station table or mutate records.

GameManager's `bindR3`, lines 3754–3821, obtains these records from the required server QueueBridge, checks conflicts/unavailable campaign IDs, stores each in private `lobbyStations`, and starts the existing station loop. A client sends only a station index/max/privacy/mode through `QueueConfig`; lines 1537–1559 resolve that index from the private server table and require the real host, current setup state and `playerInsideZone`. The client cannot supply a station record or replace its flags.

Only the exact Level 4 choice bay may switch `previewQueue` off for trial mode (`isLevel4Choice` lines 1218–1220 and `queueConfig` lines 1564–1581). Level 5/6 never enter that branch. Reset and new-host setup restore `previewQueue = station.previewOnly == true` (lines 3368–3369 and 3650–3651).

## Ordinary-player preview admission

The installed GameManager `playerInsideZone`, lines 1248–1271, keeps public Level 1–3 revised queues open but explicitly rejects `revisionOwned` levels 5 and above unless `DevAccess.IsLevel6PreviewAllowed(player)` succeeds. Then every `previewQueue` station requires `QueueBridge.AllowsPreview`. Its only campaign-choice exception is the exact Level 4 chooser.

`rawQueuedPlayers` uses `playerInsideZone` for every participant. Host setup, configured-party enumeration, each countdown tick, final participant selection and queue config recheck the same admission. The final preview launch calls `QueueBridge.LaunchPreviewGroup`, which validates every frozen participant through the active server callback and repeats authorization/living-avatar/zone/epoch checks during preparation and before/after commit. A public privacy setting or friendship with a developer does not bypass this earlier admission boundary.

The active Level 5 `readyPlayer` and Level 6 `playerReady` callbacks both require the unchanged permanent-UserId `IsLevel6PreviewAllowed` predicate. It includes the existing two general developers and ZenMeister02's existing narrow preview grant. Ordinary IDs fail. Zen remains excluded from general `IsAllowed` developer commands. Level 6 transport nonce/expiry acknowledgment separately rechecks the same predicate.

## Hypothetical station missing both flags

Claude flagged a hypothetical Level 5/6 station with neither `revisionOwned` nor `previewQueue`. That hypothetical still fails the complete GameManager function: its nonpreview branch rejects `station.level > Routing.MaxLevel` when `canAccessLevel` fails (line 1257).

`canAccessLevel`, lines 148–171, accepts public levels only through `Routing.MaxLevel=3`; an all-general-developer cohort has `Routing.DevMaxLevel=4`. Level 5 and 6 therefore fail even for general developers on a campaign/nonpreview path. Offline execution of the **exact fresh playerInsideZone function** confirmed rejection for ordinary and shared-developer subjects with both flags false. This is not a live forged-client attempt.

## Complete campaign route checks

The installed `canAccessLevel` has explicit invalid/integer/NaN/positive validation and is called before all campaign entry stages:

| Route | Installed GameManager line | Effect |
| --- | --- | --- |
| World generation / ensureWorld | 1623 | Rejects unauthorized requested level before clamp/generator selection. |
| Group loading / prepareGroupLoading | 2200 | Fails with LEVEL_ACCESS_DENIED before entering the round. |
| playRound | 2577 | Returns unauthorized cohorts to the lobby. |
| Nonpreview queue launch | 3228 | Rejects before Studio local round or production reserved-server transfer. |
| Reserved-server arriving cohort | 3930 | Rechecks the actual arrived players and destination before loading. |

`Round Completion Routing.NextLevel`, lines 276–281, has no route past Level 3 for anybody; `DevMaxLevel` is 4, and `ClampLevelTo` clamps its ceiling to that maximum. Spoofed arrival data cannot create a Level 5/6 campaign world. The world's generator table lists only Level 2, 3 and 4. The new public startup changes lobby placement/public Level 1–3 queue admission; it does not widen campaign ceilings.

General developer command handlers still require `DevAccess.IsAllowed`; DevAccess Source is unchanged. No separate ordinary-player campaign path to Level 5/6 was found in the complete fresh GameManager and Routing sources.

## Visibility limitation

The client controller implements the requested normal-player blocked wall, progress display, hidden bay interior and prompts. Server bay enforcement and preview authorization remain independent of that presentation. This establishes intended normal-client visibility and server access authority; it does not claim that already replicated geometry is secret from a modified client or asset extractor.

## Bound evidence

- GameManager: 178,031 bytes, SHA-256 `cd045eee01354ea97fb49b35a78a31a968aab47a8cdd34cb34a3d16318416a11`.
- QueueBridge: 20,289 bytes, SHA-256 `ad7752eefc2561ccda5fb92828dc71d1a2ff805a0fadca6d740c0e1b3e82d674`.
- Routing: 75,964 bytes, SHA-256 `a6d7e8936fb026a8437932b49e97faff2a9617e625a8aaeee30675538217d00b`.
- DevAccess: 1,353 bytes, SHA-256 `49b292d585f47604b84486585af39edf9915e08f3eaf7e253485769260e4b29f`.
- Level5PreviewAccess: 12,258 bytes, SHA-256 `914c4d5453712ad238373ec51218529e0b294dd9dc52907eb53b154265329f43`.
- Level6PreviewAccess: 14,842 bytes, SHA-256 `bfcfc43d291a1de6dee7d77de439e5828c4a5c65906ed4e2c2b586a2f6c7d7cd`.

`campaign-route-closure-test-receipt.json`: **10/10 offline cases passed**, exercising the exact fresh Routing module and extracted GameManager campaign functions for ordinary, narrow-preview Zen, shared-developer, mixed and empty cohorts; malformed levels; hypothetical missing flags; and the actual startup detector metadata. The existing root's actual Solo developer preview tests are separate evidence. This follow-up has not verified a live ordinary player's CreateParty/join/countdown attempt or multiplayer behavior.
