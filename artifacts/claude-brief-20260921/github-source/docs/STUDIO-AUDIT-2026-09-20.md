# Studio audit and Trello implementation order — 20 September 2026

## Result and scope

The open Studio place is BACKROOMS: STAY QUIET [CO-OP HORROR], place
131311258779917, universe 10559217407, observed PlaceVersion 1933. Studio is the
source of truth. This task reads and records the current game; it does not
implement the proposed Trello features or publish a new game version.

Against freshly fetched `origin/main` at `d17fa28`, 42 scripts differ: 26 changed
and 16 new. All 145 scripts are mirrored, with exact UTF-8 byte lengths and SHA-256
hashes. Source and ScriptEditorService editor source agreed for all 145 scripts.
The snapshot also records 15 RemoteEvents and the observed BindableFunction.
The source manifest contains scripts and RemoteEvent markers; the separate
remote inventory additionally records the BindableFunction. Objects created
during gameplay are not expected to exist in the Edit DataModel.

The complete native backup is
`artifacts/studio-audit-20260920/place-v1933.rbxl` (9,326,597 bytes), SHA-256
`2c32b4c63495afcec75f1333e25cd9c6d28b81490e499ef0879c81fd2ec5200f`.
This retains geometry and non-script properties; source files alone are not a
complete game backup. Cloud-hosted asset references do not archive the original
Blender, texture or audio authoring files.

## Existing additions reviewed before synchronization

These are cumulative Studio changes missing from main, not claims that one
specific developer authored every change. Studio source alone cannot establish
authorship.

- **Hologram shop:** `LobbyShopDisplay` and `Shop Display Client` create the
  product displays and detail cards. Walking into a display opens information;
  the explicit BUY action uses the existing store purchase path. Local bobbing
  avoids replicating every animation frame. New art references are retained.
- **Daily Rewards and Lucky Wheel:** dedicated clients, a shared rewards page,
  server-controlled playtime/prize selection, saved claim markers and inventory
  rewards now exist. Review covered reward claims, wheel replay handling and
  server-side item costs. This was not a live DataStore test.
- **Field Notes and Route Markers:** a saved collection/UI and server-placed
  route markers exist. Notes use bounded placement attempts and are optional;
  markers use the server's player position instead of accepting a client CFrame.
- **Friend Boost:** server-verified friendships within the same round add 10%
  completion tokens per friend. Fractional token tenths accumulate in the saved
  profile. The implementation does not track who sent an invitation. Failed or
  unresolved friendship lookups grant no bonus for that completion.
- **Level 1 feedback:** fuse/box/lever actions already publish actor-aware team
  messages; cable-current visuals are also present. The all-level Trello card
  should extend this implementation, not rebuild Level 1.
- **Hiding and UI:** revised Level 3 table-hiding animation/root positioning,
  collision suppression, UIStyle, equipment HUD, round exit UI and responsive
  layout changes are preserved. Anchoring and collision suppression already
  exist, so the reported pushing bug needs reproduction before choosing a fix.
- **Level 2 audio and navigation:** the audio bank/client and updated Pool Slide
  controller/navigation are preserved, together with historical uploaded asset
  IDs. Historical evidence is not a new runtime test.
- **Donations:** 5,000 and 10,000 Robux developer products and the existing
  20,000 Robux gamepass are present in the current catalog. Receipt processing
  excludes gamepasses, validates the paid amount and deduplicates PurchaseIds.
  This review does not verify current external product pricing or sale status.

No gameplay fix was applied during this audit. Source review and compilation do
not establish that every new system works in a published multiplayer session.

## Git reconciliation

`origin/main` ended at `d17fa28`. The local donation branch contained `b57a400`
without a corresponding remote branch; the audio branch was pushed through
`c21e126` but was not on main. Their current runtime behavior is captured from
Studio rather than copied over newer developer work. Relevant historical
donation evidence, receipt tests and audio records are retained verbatim; see
`artifacts/studio-audit-20260920/preserved-history.json` for their originating
commits. Historical draft scripts are references, not deployment input.

The audit branch starts from main and preserves its existing documentation,
tools and assets. It also carries the established Studio-authoritative
`AGENTS.md`. No existing branch is reset, force-pushed or deleted. This is a
current-state reconciliation, not a claim that historical feature branches have
been merged by ancestry.

## Easiest cards for Astra High with the available tools

This ranking estimates my implementation and verification effort using Studio
MCP, source/Git access and the available UI tools. It is not a human-developer
estimate or a promise of completion time. Existing systems substantially reduce
the work. All 22 open To Do cards were checked; none is marked Done by this audit.

| Order | Card | Effort | Concrete reason and remaining work |
|---|---|---|---|
| 1 | [Speed potion +30%](https://trello.com/c/a85w9YZj) | Very small | Config still has `SpeedMultiplier = 1.10` and 10% copy. The movement client already accepts up to 1.5. Update value/copy and check boost expiry, crouch/sprint and once-per-round behavior. |
| 2 | [SUPPLIES AND UPGRADES sign](https://trello.com/c/LswEFLHq) | Small | Existing procedural shop provides placement and palette. A neon part/SurfaceGui sign can be built directly through Studio; no external model is required. Check visibility and clearances. |
| 3 | [Level 1 exit indicator, top right](https://trello.com/c/w07K0m5E) | Small | Existing receiver UI can be repositioned. Update both desktop and touch layout paths while preserving safe insets and separation from other controls. It is more than changing the initial Position property. |
| 4 | [Shared objective messages](https://trello.com/c/FAgRQho1) | Small–medium | Level 1 already broadcasts username and validated action. Extend equivalent events/display handling to Level 2/3, preserving round audience, spectators and duplicate protection. |
| 5 | [Advanced Equipment focused flashlight](https://trello.com/c/n1yx5OdQ) | Medium | Existing pass, ownership and shared FlashlightProfiles can be reused. Add toggle, local/teammate/spectator beam handling, battery behavior and old-owner support. |
| 6 | [Expedition Pack](https://trello.com/c/eigEDZAH) | Medium | All three inventory systems exist. A new product still needs atomic multi-item receipt grants, duplicate/retry handling, catalog setup and explicit purchase UI. Current receipts only grant tokens or re-entry directly. |
| 7 | [Entity archive](https://trello.com/c/nWCCdowB) | Medium | Field Notes storage and collection UI already exist. Add entity grouping, locked entries and idempotent milestone rewards while preserving existing notes/title. Later camera/research links remain dependencies. |
| 8 | [Entity Detector](https://trello.com/c/Zyrtgu79) | Medium | Can reuse shop/pass/HUD patterns; needs a new multi-entity danger query, cooldown, tool presentation and mobile activation. Level 4 integration follows when that entity exists. |
| 9 | [Shop demos](https://trello.com/c/UNRk7Qy8) | Medium, dependent | Existing shop supports entry/detail flow, but complete demos depend on the flashlight, detector, skins and camera actually existing. Consumption and ownership must stay isolated from demos. |
| 10 | [Entity rules/onboarding](https://trello.com/c/us5TWr9O) | Medium | Existing briefs/guides/death UI help; fair first encounters still need per-entity gameplay work and observation. Level 4 cannot be finished before that level. |
| 11 | [Mall Manager pushes hidden players](https://trello.com/c/DYnBEZHk) | Uncertain | The card says Level 2, but Mall Manager and table hiding belong to Level 3. Current code already anchors the root and suppresses collisions; reproduce against the current version rather than assume the old defect remains. |
| 12 | [Slide fall on L2→L3, thicker walls](https://trello.com/c/xIjizflN) | Medium, uncertain | High player impact. Wall thickness is configurable, but the full card includes an intermittent transition/fall bug. A 50% thickness change alone does not establish that transition ownership and collision gaps are fixed. |
| 13 | [Re-entry at death position +10s grace](https://trello.com/c/Ejo5OPkG) | Medium–large | Current re-entry uses the round/elevator spawn. Needs safe death-position capture, invalid/fallen-position fallback, round lifecycle handling and consistent immunity/targeting rules across entities. |
| 14 | [Daily research tasks](https://trello.com/c/wEFTmguQ) | Medium–large | Rewards infrastructure exists, but task objectives, daily reset, solo/team attribution and durable progress/rewards are additional systems. |
| 15 | [Level variation](https://trello.com/c/OBjSW30k) | Medium–large | Requires valid placement sets and repeatable checks that generated objectives remain reachable and solvable across seeds. |
| 16 | [Token Earner 2x/3x/5x](https://trello.com/c/EtdsUM4e) | Large | Includes immediately multiplying existing balances. Must define upgrades/stacking, apply historical-owner migration exactly once, and protect purchases/retries/concurrent saved balances. |
| 17 | [Hazmat/equipment skins +3D preview](https://trello.com/c/VSCGGIA9) | Large | New visual assets, preview, ownership/equip persistence and replication. Existing color choices only cover part of this. |
| 18 | [Post-completion challenges](https://trello.com/c/FnF49TWk) | Large | Valid records need death/re-entry/assist tracking, comparable rule sets, persistence and one-time rewards. |
| 19 | [Research Camera](https://trello.com/c/cqvNQIIc) | Large, dependent | Tool and UI, server-valid subject/visibility recognition, research/archive integration and paid variants. Build tasks/archive first. |
| 20 | [Level 4](https://trello.com/c/Y2xXThBN) | Largest | Complete environment, new entity, objectives, art/audio, level transitions and solo/multiplayer/mobile verification. Start with a playable blockout. |
| — | [Purchase alerts](https://trello.com/c/XuxYAtTA) | Deferred | Card explicitly records the owner's postponement. Not a recommended next task. |
| — | [14-day 50% sale](https://trello.com/c/GxhsmCC5) | Deferred | Card explicitly records the owner's postponement. Not a recommended next task. |

**Suggested small implementation batch:** potion, sign, exit indicator, then
cross-level objective messages. For a new paid feature, focused flashlight is
the most straightforward extension; Expedition Pack is the clearest reuse of
existing consumables but needs careful receipt handling.

Ease and impact differ. Investigate the slide transition and hiding reports
before increasing ads if reproducible; a cosmetic quick win does not compensate
for players falling out of the map. The seven cards in “Before big adsspend”
remain measurement/validation work: funnel telemetry, lobby-to-gameplay,
first experience, death/retry, mobile devices, ad alignment and solo/friends.
MCP can implement instrumentation and exercise Studio clients, but cannot replace
real player cohorts, physical-device evidence or elapsed D1/D7 measurement time.
The two Testing cards explicitly record deferred controller and published
multi-player loading checks; this audit does not declare them passed.

## Validation and limits

- All 145 mirrored scripts compiled with the available official Luau compiler.
- All 145 source hashes/byte lengths matched the inventory; no editor conflict.
- A second fresh read of Studio is recorded in `final-parity.json` before commit.
- The retained donation receipt harness is run against this snapshot; the exact
  result is saved in `receipt-validation.txt`.
- `git diff --check` reports an existing Studio trailing blank line in the Level
  2 lighting source and unified-diff context whitespace inside the historical
  donation patch. Both are retained verbatim to preserve source/evidence parity;
  all other staged files pass that whitespace check.
- No gameplay, real purchase, live DataStore, multiplayer, performance or
  physical-device test was performed during this audit. Earlier evidence retains
  its original date and scope.
- The native backup was downloaded before the source export; script parity was
  rechecked afterward. Unsaved concurrent geometry changes cannot be excluded by
  script hashes alone.
