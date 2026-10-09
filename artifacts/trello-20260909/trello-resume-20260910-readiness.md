# Resumed Trello scope and bounded implementation opportunities

Read-only preparation on 2026-09-10; final board capture 09:04:11 Europe/Copenhagen. No runtime, Studio, Trello, image or price changes. Token-opportunity research is expressly deferred; its card was read only to classify scope.

The full two-board/member/workspace scan ends with no more pages. Development has 47 cards (41 open, 6 archived), and the starter board has 5. Against `trello-reconcile-20260910-final.json`, all 47 old IDs remain and exactly 5 IDs are new: WJLErpHx, O0h3ag8I, 53c4MFE5, ne5X0bYj, DEmpCU8O. All five are To Do/complete=false, with empty dedicated checklist and comment results. The same four Testing cards remain excluded. The connector exposes no attachment endpoint/field, and these descriptions contain no attachment references; this is not a claim of complete attachment inspection.

Boards: https://trello.com/b/6FHYrsMR/backrooms-stay-quiet-development and https://trello.com/b/DzYNLBmn/my-trello-board.

Protection is fully installed and the independently read `protection-prepared/installation/final-functional-review.md` awards 8/10. Root reports final cleanup/compile/audit work and the pending mouse publication after Escape pause. At this snapshot its card is To Do, not Testing. Do not call it published or overwrite its installed sources with the earlier proposals. Its next step is root's separate publication/checkpoint; the small tasks below must follow that checkpoint for runtime delivery.

## Suggested next order

1. Finish Protection publication (root).
2. ne5X0bYj: two-token completion reward — importance 3, XS remaining work.
3. kQ4GNLUU: existing reviewed studio-introduction proposal — importance 2, XS remaining implementation.
4. DEmpCU8O: lobby music toggle — importance 2, S.
5. WJLErpHx: three section icons — importance 2, S.
6. RynrscFW: twelve product/pass icons and six Shop consumers — importance 2, M, reviewed artwork/runbook ready.
7. 53c4MFE5: developer-only player ESP — importance 1, S.

This orders higher gameplay importance first and smaller remaining changes before larger work at equal importance. Estimates concern scoped delivery, not guarantees of platform-upload time. Each feature retains its own review and mouse-publish boundary. iMTZhXMy and gTgtoztS remain external dependencies. O0h3ag8I, pricing, current Testing, delegated Pool Foam audio and Done/archive history do not become implementation work.

## Two-token reward: exact minimum

`ReplicatedStorage/ZyntraConfig.ModuleScript.lua:14` has `LevelCompletionTokens = 1`. The actual event consumer at `ServerScriptService/ZyntraMonetization.Script.lua:2489` adds that field and increments CompletedLevels inside the existing profile mutation, but its line2498 message hardcodes `+1 Zyntra Research Token`. Change the configured amount to 2 and render the message from that actual amount, with correct plural wording. Apply this tiny delta to the current Protection-merged source.

`ServerScriptService/GameManager.Script.lua:2468` iterates the round participants once; line2472 fires `ZyntraLevelCompleted` only for an escaped participant with result=win. This event is server-only. No GameManager or objective changes are needed for the requested amount. Preserve current badge, completion-stat and profile pathways; do not invent a new currency ledger or change unrelated paid grants. Current receipt/profile failure semantics are not redefined by this amount-only card.

Meaningful narrow verification: invoke the actual completion handler against the existing isolated/fake profile path and assert tokens +2, CompletedLevels +1, correct level flag and matching message. Inspect the existing win/escape producer and exercise one normal level completion; loss/non-escape should retain current behavior. Compile the two whole files. No live DataStore writes or paid purchases are necessary for this verification.

## Player ESP: independent small client change

`StarterPlayer/StarterPlayerScripts/DevCheats.LocalScript.lua:22` exits before creating commands or visuals unless DevAccess allows the local player. Its existing `tag`/`setEsp` functions (92/106), 0.5-second discovery loop and `dispatchCommand` (436) provide local visual/state patterns. The current global ESP covers objectives and hostiles, never Players. The Dev UI control inventory is in `StarterPlayer/StarterPlayerScripts/ZyntraStore.LocalScript.lua:705` and already routes controls through the shared local DevCheatCommand.

Small independent option: add a separate default-off player-ESP toggle/state/command, with its own highlight ownership/name so the existing B/ESP-plus-fast-queue behavior remains intact. Track current Players and later joins/characters; clear exact old character adorners and listeners on removal/respawn/leave. A per-player name label may help identify targets, but do not add server replication/remotes or grant this view to ordinary users. Distinguish the local player's own character if including it; the user-facing requirement is developer visibility of other players' locations.

Meaningful narrow verification: actual toggle lifecycle under current/late character, respawn and leave; no duplicate or lingering adorners; no creation for a non-whitelisted local player; existing objective/entity ESP unaffected. Native actual second-player visibility through walls and off/on is the strongest final check. An NPC clone is not an actual second Player. This task can be prepared independently from reward/lobby music; serialize any eventual shared Store edits.

## Lobby music: existing Settings button and saved preference

Independent read-only investigation by audio identified a two-file path: add `LobbyMusicEnabled`, label Lobby music, default true to Config.AccessibilitySettings; add that attribute to `LobbyMusicController.shouldPlay` and its change subscriptions. The existing Store settings builder, server allow-list, boolean normalization, profile/attribute updates and coalesced save already share that array. No Store/Moneti/new-remote change is necessary. Requiring true rather than nil enables silence until the loaded preference arrives, avoiding saved-OFF startup playback.

Root has authorized artifact-only preparation of this option under `lobby-music-prepared/`. Its actual controller/settings tests and independent review remain a separate handoff. The normal lobby Settings ON/OFF interaction, seam/rapid-toggle stability, saved-OFF rejoin, ordinary round transitions and preservation of briefing duck/voice/effects are the meaningful acceptance checks. This is a switch for existing lobby music, with no delegated Pool Foam audio production.

## UI section icons: asset preparation independent of runtime

The exact new card asks for one icon for each of Upgrades, Gear and Shop. The current Store has a combined `UPGRADES & GEAR` lobby entry at line110, a separate SHOP entry at119, and tabs Upgrades/Shop/Donate/Colors/Settings (+Dev) at380. There is no separate Gear tab. Prepare three coherent, legible motifs in the established dark/teal style and map them to existing visible headings/entries; do not add a new Gear page or rearrange routing as an unrequested side effect. Retain the clear text labels and tap targets. Coordinate the precise placement with root's current Store work before applying runtime changes.

Asset/visual work can proceed independently from the reward patch and music controller. Final verification must use the actual rendered small icons, existing 220px phone entry width, modal suppression, DEV variant and current device/safe-area behavior. This card remains distinct from the twelve existing product/pass artworks in RynrscFW.

## Source-reading boundary

The existing graphify graph was checked first and queried for Monetization. It was built from e3904931 on September3, while the current checkout is 7f13f532; it is stale. All implementation locations above were verified directly against current source, and no graph rebuild or runtime edit was performed. The fresh raw card/checklist evidence is in `trello-resume-20260910-new-cards.json`; prior publication records remain untouched.
