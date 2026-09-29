# Level 5 lobby closure, preview QA and audio — 2026-09-27

**Published v2157 closes Level 5 lobby access for everyone at the owner's latest request.** Public and developer access flags are false, the lobby builder defaults Level 5 to inactive, its door is visible and colliding, and all four queue stations are offline. A fresh native build confirmed zero active stations and four future/offline stations. The Studio log confirms the final closure publish succeeded at 11:09:42 UTC. Restarting already-running servers remains unverified, so older servers may retain their earlier access state.

The earlier opening was **published as v2153** to place `131311258779917`, universe `10559217407`, with a successful Studio log at 10:54:28 UTC. The playtest results below describe that session before the requested closure. The outage, clue, residential styling and audio work remain; the H ending and new audio integration are unfinished.

## Changes

- Level 5 retains its independent public-preview access logic, with public and developer access disabled after QA. Level 4 keeps its developer checks, Level 6 remains closed, and campaign progression still ends at Level 3.
- The Level 5 lobby bay now uses residential carpet, plaster, floral wallpaper, dark windows, domestic fronts and shared ceiling lights. Existing queue objects were retained. After QA, its door was restored to visible/colliding and the four stations were returned to offline status. Level 4/6 doors remain sealed.
- Power outages are temporarily disabled. Fixture metadata and cleanup remain intact.
- The B clue keeps its title, answers and layout, with `LightInfluence = 0.25` for dim interiors. Depth testing remains enabled; no extra lights were added to the clue.
- Entry and H signs identify the preview and direct players to the existing lobby control. The Window Watcher access guards accept the public preview. No win, reward, automatic return or slide mechanic was added.

## Native playtest

The test used one desktop Studio client. The real lobby queue entered Level 5. Puzzle prompts and mouse controls were used; gate answers and solved states were not forced. Character navigation and native keyboard movement were used without character teleports.

| Section | Result |
|---|---|
| A — colours | Wrong answer rejected; correct answer fully opened the gate. |
| B — symbols | Wrong answer rejected; correct answer fully opened the gate. The earlier clue inspection found readable normal lighting and severe darkening during an outage. |
| C — address | Wrong answer rejected; correct answer fully opened the gate. |
| D — switches | Wrong answer rejected; correct answer fully opened the gate. |
| E — clocks | Wrong answer rejected; correct answer fully opened the gate. |
| F — television | Wrong answer rejected; correct answer fully opened the gate. The authored rescue route and crossings were walked. |
| G — arrows | Wrong answer rejected; correct answer fully opened the gate. All seven puzzle-solved flags were true. |
| H — dark chute | Endpoint reached with 2.5 seconds of native W movement after the navigation tool stopped short on the slope. Health remained 100. Geometry is traversable, but still declares `GeometryOnly_NoSlideOrCompletion = true`. |
| Return to lobby | Holding L for 2.5 seconds returned to the lobby: `InRound = false`, `RoundActive = false`, generated world removed, no remaining checked round-owned objects, health 100. |

Every solved gate reported `FullyOpen = true`, `Unlocked = true` and `OpenReason = "SOLVED"`. Current-session B–G solved receipts reported no outage. The F/G wrong-answer receipts record corrective feedback and the puzzle UI staying open; they do not separately record an unlocked flag.

This establishes the tested desktop Studio path. Published reserved-server transfer, ordinary-account multiplayer, mobile/controller play, performance and subjective audio listening were not tested. The existing arithmetic UI test also retains its known very-small-viewport limit: a 248 px minimum panel exceeds a 244 px usable frame.

## Source preservation and offline checks

Six scripts were initially installed with guarded, scoped compare-and-swap edits. Their full Source and editor-source exports matched the intended SHA-256 hashes and the repository mirrors at that time. The 197-script post-install inventory found exactly those six changes, 191 unchanged fingerprints, no additions/removals and no Source/editor conflicts. The latest lobby closure then changed only the GameManager access defaults and the lobby builder's Level 5 active setting and station registration override. An initial v2156 closure denied access, but a fresh build exposed the old registration override; removing it and rechecking the native lobby completed v2157. Four pre-existing concurrent Level 6 scripts remain preserved in Studio and the native checkpoint, outside the repository's 193-script mirror. The historical parity tool's four reported extras were expected.

After the initial publication, a fresh cloud reopen found **198 scripts**: all 197 prior scripts matched the post-install fingerprints, and another developer had added `ServerScriptService.Level6Renovation`. Its full Source/editor export matched at 28,679 bytes, SHA-256 `d0853a3f7c4d80ad6718c5a54147afc0b943e12ba8c9d04c63558a5782aa7cd2`. It is preserved separately in the artifact record, with no runtime mirror change. There were no Source/editor conflicts. That native lobby readback retained the Level 5 styling/open access and sealed Level 4/6 doors before the subsequent requested closure. The reopened Edit metadata reports v2150; the successful publication logs independently establish v2153, v2156 and v2157.

All six changed scripts and all 12 apply/verify payloads compile at Luau `-O0`. Offline tests passed: 256 access-policy assertions, 78 disabled-outage lifecycle assertions, 1,456 lobby geometry assertions, and 360 CAS assertions across 90 scenarios. Puzzle logic passed 6,910 assertions over 2,185 combinations; layout arithmetic passed 2,737 assertions. These offline checks are separate from the native results above.

The final two closed-access sources were independently exported again, Source/editor matched, and both repository mirrors matched their SHA-256 hashes. Both compile; 120 additional tests exercise the exact closed-access defaults and actual builder room/door expressions. The artifact replay passes 25 commands covering the historical opening tests and current closure tests. Final native closure evidence includes a complete scoped export of 219 lobby instances and their relevant properties.

## Audio delivery

`/Users/zeanjuul4/Downloads/Level 5 Final Sounds - Cleaned` contains **16 active WAVs**, including Window Watcher and door opening/closing cues. Four deferred files are in `DO_NOT_UPLOAD_NOW`. All 12 existing sounds have cleaned derivatives with the originals preserved; eight additional cues were selected from the authorized ElevenLabs batch. All 20 delivered files passed format, hash, clipping, peak and boundary checks as mono 44.1 kHz, 16-bit PCM WAV.

**No new audio was uploaded to Roblox and no new audio IDs or playback hooks were installed.** The manual upload sheet still awaits Roblox IDs. Subjective headphone and in-game listening remain unverified. Processing, measurements and the sanitized asset archive are documented in [the audio record](LEVEL5_FINAL_AUDIO_2026-09-27.md).

## Backup and evidence

The archived full native recovery file is a **prechange v2150 checkpoint**, 17,362,339 bytes, SHA-256 `13710246d8b2f634631418080f7cfe3eda6110791e88517bda7a5219910acc92`. Its hierarchy and all 197 baseline script hashes were verified, including the concurrent Level 6 scripts. It precedes these six source edits and the lobby changes; it must not be presented or restored as the final v2157 state.

A final full native copy could not be obtained because Studio's save picker blocked completion. The browser fallback was also unavailable. Publication succeeded independently, but source exports and publication receipts do not replace a full final native backup. The 197-script post-install expectation and the latest 198-script expectation are both included, with a read-only native-file audit script that defaults to the latter for the next successful save.

The [artifact record](../artifacts/level5-opening-20260927/README.md) contains scoped patches, apply/verify scripts, test records, verified source fingerprints, native QA receipts, the publication receipt and the prechange native checkpoint. Full exported script sets are not duplicated there; the six verified current sources are the repository runtime mirrors.
