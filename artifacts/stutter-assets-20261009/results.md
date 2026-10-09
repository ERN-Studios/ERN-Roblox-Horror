# Lobby and in-game stutter / asset loading — 2026-10-09

Five scoped loading, scheduling and room-streaming fixes were verified in authoritative Studio and published to place **131311258779917**, universe **10559217407**, as version **2910**. Roblox Studio reported a successful publish; see [publication.json](publication.json). This establishes publication of the current Studio place, not resolution of every player-reported stutter or a published-client device pass.

## Exact source scope

| Live Studio path | Class | Recorded state |
| --- | --- | --- |
| `StarterPlayer.StarterPlayerScripts.Shop Display Client` | LocalScript | Installed and individually exported from verified native Source/editor |
| `StarterPlayer.StarterPlayerScripts.Lobby DJ Client` | LocalScript | Installed and individually exported from verified native Source/editor |
| `ServerScriptService.Level 1 Systems.BlenderRoomRenderer` | ModuleScript | Installed and individually exported from verified native Source/editor |
| `ReplicatedFirst.Lobby Loading Screen` | LocalScript | Installed and individually exported; subsequent Opaque-content correction verified |
| `StarterPlayer.StarterPlayerScripts.Round Entry Client` | LocalScript | Installed and individually exported; subsequent Opaque-content correction verified |

The shop change limits incomplete lobby replica discovery to twice per second, suspends that work during rounds and restores animated boxes. The DJ change caches the decoded catalogue until its raw attribute changes and exits before decoding while inactive. The renderer marks newly cloned 24-stud room models `Atomic`; it does not change the existing maze generator or make all rooms persistent. Atomic model arrival is not proof that its texture data or GPU resources are ready.

| Installed source | Verified SHA-256 |
| --- | --- |
| Shop Display Client | `0abe08bcdf612c2b8d38b554a61ecdb55c70538326e124d75f73275c45cacfa1` |
| Lobby DJ Client | `5722867c4602ee8d248473dd78f3ce9afe9ec494c8d1767c8a91b7c7d9635163` |
| BlenderRoomRenderer | `0f217e5a3f56751e7672efc035861a2cec1b5f23d581a52020411a8d081790cf` |
| Lobby Loading Screen | `872b9ed13fdc0e21332a844a6931b5ba2796a1ffd659a45f6cf0d5d945049583` |
| Round Entry Client | `a5026683f092bccc1eb106bdc1df56b42b49e18eafddbd8b1c4919010bab9bc5` |

See [shop](shop-scan-native-install.json), [DJ](dj-cache-native-install.json), [renderer](level1-room-streaming-native-install.json), [initial lobby loading](lobby-loading-native-install.json), [initial round entry](round-entry-visuals-native-install.json), [lobby Opaque correction](lobby-opaque-content-native-install.json) and [entry Opaque correction](entry-opaque-content-native-install.json) receipts. Each records matching Source/editor/native/mirror hashes, unchanged properties/attributes, `nativeVerified: true`, `mirrorExported: true`, and `published: false` at place version 2859.

The two loading changes address incomplete asset census and premature readiness. Lobby loading tracks runtime-readable content, deduplicates stable URIs, uses typed mesh carriers, accounts for failed/missing preload callbacks, and indexes arrivals in bounded slices. Embedded Opaque meshes with no remote asset ID are not treated as failed downloads; real textures on those meshes still require a fetch. Its visible live-level cover waits for the current model census; incomplete, capped or failed work does not claim “LEVEL READY.” Round entry retains the actual-floor, character, token and deadline gates, additionally waits for nearby visible assets and a short arrival-settling interval, and uses the existing deadline recovery when nearby assets fail. See [candidate-receipt.json](candidate-receipt.json) and [loading-candidate-notes.md](loading-candidate-notes.md).

The initial lobby preload preserves parallel requests with a four-worker pool under one owner. Retry/skip stops new claims, rejects stale results, and retains the busy lock until every old engine request drains. Background and entry preloads remain sequential. [Pool install](lobby-bounded-pool-native-install.json). This avoids serializing the original parallel loader; it is not a controlled performance-gain claim.

## Validation and preservation

Offline production-code checks recorded 12 shop, 129 DJ and 12 renderer checks. Loading checks recorded 85 round-entry checks and 100 lobby-region checks, including large censuses, worker overlap, late arrivals, stale generations and embedded Opaque content. Twelve deliberate regressions were caught. All five source candidates compiled with official Luau 0.737.

The latest native renderer probe used a tiny actual-kit generation: four rooms, four visible roofs and 44 cloned parts. Fresh empty ModuleScripts were used for staging; authoritative Source/editor remained unchanged and probes were destroyed. [Native probe receipt](native-candidate-probes.json). These are contract checks, not a complete-maze, gameplay, multiplayer or performance pass.

Each source installation uses an explicit fresh live capture and independent comparison guards, including exact instance identity/path, metadata and Source/editor checked again inside `UpdateSourceAsync`. The scoped exporter checks expected manifest and mirror bytes before updating only its corresponding record. Recovery files are under `.git/stutter-assets-20261009`; concurrent dirty and unrelated repository work was preserved. This is scoped mirror parity, not a claim of whole-repository or whole-place parity. The owner reported an existing full native place backup; this report has no independently verified backup path/hash or new backup receipt.

The existing warm Level 1 server baseline recorded physics 0.67–1.11 ms, heartbeat 0.89–1.14 ms and total memory 5560–5565 MB. A genuine normal queue subsequently entered Level 1: the server recorded `active = true`, `loadingState = ready`; the player was unanchored and in-round. The client recorded 1,600 Atomic room models and 89 nearby visible roof meshes. [Client receipt](runtime-level1-client.json), [server receipt](runtime-level1-server.json), [queue](runtime-queue.json), [configuration](runtime-configure.json).

The final lobby reported **17.3 seconds, 87 remote assets, zero failures**. Its five-second sample averaged 16.67 ms, with p95 18.52 ms. Level 1 averaged 16.77 ms, p95 17.99 ms, with one frame over 50 ms. [Console evidence](runtime-console.json). Earlier runs varied with Studio's 15 FPS background throttle, and the Assistant tool reported camera restoration during timed probes. These are instrumented warm Studio observations, not a controlled before/after or normal player camera/rendering pass.

The final active server sample recorded heartbeat 0.53–0.79 ms, physics 0.45–0.77 ms and combined Studio process memory around 5688 MB. Studio memory includes editor, server and client. Cold-cache downloads, low-memory/mobile devices, multiplayer, Level 2–6 gameplay, actual Level 6 chase audio and native failed-entry deadline recovery were not verified. `PreloadAsync` and fetch status cannot establish processed PBR packs, mip residency or GPU readiness.

## Optional Level 6 audio

Read-only Open Cloud metadata reports sound **134572728354839** (`l6_chase_shriek`) owned by the correct group, state `Active`, moderation state **Rejected**. It is not a pending permission grant. The local MP3 SHA-256 is `6698ad7ef9881f224aae992236ed132436aa9e36f005d9de975db1db2b6bceca` and matches its generation manifest.

Fresh live Level 6 client Source/editor agree: failed effects are excluded and chase falls back to `l6_sting_spotted` (**96999429368160**). The shriek was `IsLoaded = false`; that fallback was `IsLoaded = true`. No grant, upload, reupload or moderation bypass was attempted. This pre-existing optional rejected sound alone is not a blocker to separately verified loading/streaming fixes. Actual heard Level 6 chase audio remains unverified. [Timestamped evidence](assets-moderation.json).

## Authored worlds and persistent collision — read-only finding

With streaming enabled, authored maps remain in Workspace, with top-level `ModelStreamingMode = Default`. The actual lobby and Level 1 client censuses confirm that distant Level 5/6 each had **zero BaseParts** on the client. Level 4 had **1,634 BaseParts**, all its Persistent collision, and **zero meshes/lights**. Their authored visible geometry therefore was not all present on that client. [Lobby census](runtime-lobby.json), [Level 1 census](runtime-level1-client.json). The following table is the earlier Edit model census, not those client counts:

| Workspace model | Descendants | BaseParts | MeshParts | Lights |
| --- | ---: | ---: | ---: | ---: |
| `Level 4 Cinema Blender` | 14,464 | 8,909 | 4,051 | 254 |
| `Level 5 Void` | 2,627 | 1,947 | 0 | 661 |
| `Level 6 Indoor Playground` | 20,318 | 14,300 | 73 | 281 |

The exact `Workspace.Level 4 Cinema Blender.Collision` model is **Persistent**, containing 1,634 anchored BaseParts, including 1,502 collidable and 829 transparent parts. This is an unconditional client replication cost under that mode. It was deliberately made persistent after the very large floor streamed away at the back of Cinema 1 and clients fell through: see `tools/level4_blender/README.md:142`, `CLAUDE.md:2360`, and `tools/level4_blender/place_phases.luau:42`.

Blindly changing that model to Default would reintroduce a known floor risk. A future scoped design could use per-player persistence for the actual Level 4 cohort or split large colliders, but either needs Level 4 floor/traversal and lifecycle QA. No such change or test is part of this five-source scope.

Moving whole authored maps to ServerStorage also needs a coordinated lifecycle change. Fresh live Source/editor inspection shows `ServerScriptService.Level4RoundGenerator` builds from Workspace and only cleans its owned runtime objects; `ServerScriptService.Level5PreviewAccess` and `ServerScriptService.Level6PreviewAccess` resolve/watch their Workspace models for entry; `ServerScriptService.Live Level Server` routes parties without moving the geometry. Parking maps must support arrival, reset, reentry and continuation and preserve native object data. No native map relocation, property change or lifecycle source change was made during this investigation.

## Final preservation and publication

[verified-scope.json](verified-scope.json) records post-publication matching native Source/editor, canonical mirror and scoped manifest hashes for all five scripts, with exact classes, properties and attributes. The install receipts retain their historical `published: false` state; the later publication receipt is authoritative for publication. Studio's loaded `PlaceVersion` remained 2859 while Output identified the newly published version as **2910**. No server restart, access-setting change or GitHub push was performed.

Play was stopped and no StutterAssets probe objects remained. Temporary ModuleScripts/non-script clones were destroyed; borrowed renderer attributes were restored; the task's MicroProfiler capture was disabled. Only the five source mirrors, their manifest rows and explicit task evidence/tools belong to this commit. An alternate index keeps other developers' staged/dirty files and the unrelated RoundUI manifest row out of the task commit. Recoverable source/index checkpoints remain under `.git/stutter-assets-20261009`. The local commit ID is recorded in the final task reply.
