# Level 2 Poolrooms promotion — 2026-10-09

The approved six-area Poolrooms is published as the normal queued Level 2 in **v2883**, confirmed by Studio Output on 2026-10-09 at 13:56:34.612 UTC (15:56:34.612 Copenhagen). Public access is open; the maintenance sign/barrier and both developer preview controls are removed. The authored map moves between `ServerStorage.Level2PoolroomsMap` and `Workspace.Level 2 Generated World`, preserving its 30,869 descendants, nine Terrain-water regions, fitted gold reflector and lion illumination. Old versions are archived.

Native Studio Round A passed the real zone105 queue, client `ConfigureQueue`, countdown/loading, first-person hazmat arrival, a real hole death with `L2Hole`, and the running GameManager's free developer reentry. Physical walking into the exit flume reached its server completion zone; forced slide, ragdoll and downhill force stopped at the finite runout. The native win offered Level 3. A transition death recovered a new body within 0.104 studs of the safe runout. Return Lobby restored the personal avatar and client grade and stored the map. Round B passed queue rearm, the physical exit ride, native Continue and healthy arrival into an active Level 3 round; the Level 2 grade released for Level 3.

Evidence:

- `qa/roundA-entry.json`, `qa/roundA-hole-reentry.json`, `qa/roundA-recorder-after-reentry-client.json`.
- `qa/roundA-finish.json`, `qa/roundA-finite-stop.json`, `qa/roundA-transition-recovery.json`.
- `qa/roundA-lobby.json`, `qa/roundA-lobby-client.json`, `qa/kiosk-entry.jpg`.
- `qa/roundB-entry.json`, `qa/roundB-lion-live.json`: second native queue and approved A2 noon sun/reflected lion light.
- `qa/roundB-decision.json`, `qa/roundB-level3.json`, `qa/roundB-level3-client.json`: native Continue, real Level 3 release/start events and released Poolrooms grade.
- `final-verification.json`: fresh Edit source/editor/mirror/candidate/manifest parity for all eleven promoted scripts, five retired-name absences, stored map and exact retained Terrain-water counts.
- `verified-installation.json`, `verified-retirement.json`, `scene-verification.json`, `mirror-sync-receipt.json`: scoped installation, source/editor parity, retirement and mirror synchronization.

Installed-mirror regression checks passed: public Level 2 queue 283; shared GameManager loading host 98; Level 4 ordinary bays 449 server + 20 client; campaign routing 15 module assertions + three source assertions. The Level 4 harness also compiles the complete GameManager/RoundUI sources. Tests preserve optional maintenance-mode denial regressions without shipping Level 2 closed.

The retired Pool Foam client now rejects the authored no-entity map before sending reports. Its actual `activeCharacter`/`sendReport` harness passed 2,078 assertions, including 2,048 authored-map ticks sending zero events; the pre-fix handler fails that assertion. Legacy Foam-round eligibility remains covered. In a third native queue run, the running `ClientReport` remote's server counter stayed zero over 30.0155 seconds with Level 2 active and the player in the round (`qa/roundC-zero-legacy-reports.json`). No Foam report-queue warnings or engine errors appeared in that fresh pass. Separate installation/readback/backup evidence is retained under `clientreport-fix/`; its independently synchronized mirror was not applied twice.

Limits: native Play uses one actual owner player. Multi-player privacy/cohort rules are exercised offline against real handlers with fake Roblox boundaries. Studio uses the existing local campaign fallback, so external TeleportService transport, destination admission under real network delays and production persistence are not established by this pass.

Known pre-existing audio limitation: `rbxassetid://134572728354839` reported "Asset is not approved for the requester" in the earlier lion-reflection Play log (`../level2-lion-reflection-20261009/qa/studio-qa.json`). That earlier log also reports a missing `Level 2 Distant Water` library slot. The promotion adds no new audio assets or approvals.

Publication v2883 is recorded in `public-receipt.json`, supported by the actual `publication-output.txt` confirmation and `qa/published-v2883.jpg`. The pre-publish local backup is `backup/BACKROOMS-Level2-public-20261009T1553.rbxl` (45,411,778 bytes; SHA-256 `a4ee0f0bd51016f6e672db0ced72fc7b8706ce449b55afb264c9eaf7b84690cd`). This records the shared Studio release; the native QA and offline test limits above remain unchanged.

Backups: `before/` contains authoritative pre-install source, including the original layout generator. `mirror-backup/20261009T133446557194Z/` contains the replaced mirror files and complete previous manifest. `tool-backup/test_level2_queue_gate.py` contains the prior queue test. Unrelated repository files and manifest rows were preserved.
